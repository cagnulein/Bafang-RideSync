import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../bafang_data.dart';
import '../models/heart_zone.dart';
import '../models/workout_plan.dart';
import '../models/workout_record.dart';
import 'cadence_service.dart';
import 'fit_writer.dart';
import 'gps_service.dart';
import 'health_service.dart';
import 'hr_service.dart';
import 'live_activity_service.dart';
import 'pas_pid.dart';
import 'power_estimator.dart';
import 'power_service.dart';
import '../models/pas_config.dart';

enum WorkoutState { idle, running, paused }

class WorkoutService extends ChangeNotifier {
  final BafangData bike;
  final HrService hr;
  final CadenceService cadence;
  final PowerService power;
  final GpsService gps;
  final HrZones zones;
  final HealthService health;
  final LiveActivityService liveActivity;

  WorkoutState state = WorkoutState.idle;
  WorkoutPlan? plan;
  WorkoutRecord? record;

  int currentSegmentIndex = 0;
  // Wall-clock start of the current segment — compared with DateTime.now()
  // so time-based advancement works even in background (no timer ticks needed).
  DateTime? _segmentStartTime;
  double _totalDistAtSegmentStart = 0;

  late final PasPid _pid;

  int get pidIntensity => _pid.intensity;
  set pidIntensity(int v) {
    _pid.intensity = v.clamp(1, 10);
    notifyListeners();
  }

  int get pidMinPas => _pid.minPas;
  set pidMinPas(int v) {
    _pid.minPas = v.clamp(0, _pid.maxPas);
    notifyListeners();
  }

  int get pidMaxPas => _pid.maxPas;
  set pidMaxPas(int v) {
    _pid.maxPas = v.clamp(_pid.minPas, 9);
    notifyListeners();
  }
  // Timer only refreshes the UI while the app is in foreground.
  Timer? _uiTicker;
  int _autoTargetMinBpm = 0;
  int _autoTargetMaxBpm = 999;
  bool autoPasEnabled = true;

  // ── Bike profile & power estimation ─────────────────────────────────────────
  double riderWeightKg = 75;
  double bikeWeightKg = 25;
  List<PasLevelConfig> pasConfigs = PasLevelConfig.defaults();

  // Gradient smoothing: EMA over consecutive GPS+distance samples
  double _currentGradientPct = 0;
  double? _prevAltitudeM;
  double? _prevDistanceKm;

  // Last computed estimated rider power (W), null if not enough data
  int? estimatedRiderPowerW;

  int get motorWattsAtCurrentPas {
    final pas = bike.pas;
    if (pas == null || pas < 0 || pas >= pasConfigs.length) return 0;
    return pasConfigs[pas].motorWatts;
  }

  void updateRiderWeight(double kg) {
    riderWeightKg = kg.clamp(30, 200);
    notifyListeners();
  }

  void updateBikeWeight(double kg) {
    bikeWeightKg = kg.clamp(5, 80);
    notifyListeners();
  }

  void updatePasMotorWatts(int pasLevel, int watts) {
    if (pasLevel < 0 || pasLevel >= pasConfigs.length) return;
    pasConfigs[pasLevel].motorWatts = watts.clamp(0, 1000);
    notifyListeners();
  }

  void updatePasMaxSpeed(int pasLevel, double kmh) {
    if (pasLevel < 0 || pasLevel >= pasConfigs.length) return;
    pasConfigs[pasLevel].maxSpeedKmh = kmh.clamp(5, 99);
    notifyListeners();
  }

  // Cadence-based PAS boost: if cadence stays below threshold for N seconds, +1 PAS.
  bool _lowCadenceBoostEnabled = true;
  bool get lowCadenceBoostEnabled => _lowCadenceBoostEnabled;
  set lowCadenceBoostEnabled(bool v) {
    _lowCadenceBoostEnabled = v;
    _lowCadenceSince = null;
    notifyListeners();
  }
  int _lowCadenceThresholdRpm = 60;
  int _lowCadenceBoostSeconds = 10;
  DateTime? _lowCadenceSince;
  DateTime? _lowCadenceCooldownUntil;

  int get lowCadenceThresholdRpm => _lowCadenceThresholdRpm;
  set lowCadenceThresholdRpm(int v) {
    _lowCadenceThresholdRpm = v.clamp(20, 120);
    _lowCadenceSince = null; _lowCadenceCooldownUntil = null;
    notifyListeners();
  }

  int get lowCadenceBoostSeconds => _lowCadenceBoostSeconds;
  set lowCadenceBoostSeconds(int v) {
    _lowCadenceBoostSeconds = v.clamp(3, 60);
    _lowCadenceSince = null; _lowCadenceCooldownUntil = null;
    notifyListeners();
  }

  // Last PAS level we commanded. If bike.pas differs, the user changed it manually.
  int? _lastCommandedPas;

  // Wired by main.dart to BleService.setPasLevel
  void Function(int)? onSetPas;

  WorkoutService({
    required this.bike,
    required this.hr,
    required this.cadence,
    required this.power,
    required this.gps,
    required this.zones,
    required this.health,
    required this.liveActivity,
  }) {
    _pid = PasPid(intensity: 3);
  }

  HeartZone? get currentZone => hr.bpm != null ? zones.zoneFor(hr.bpm!) : null;

  WorkoutSegment? get currentSegment {
    if (plan == null || currentSegmentIndex >= plan!.segments.length) return null;
    return plan!.segments[currentSegmentIndex];
  }

  Duration get elapsed => record?.elapsed ?? Duration.zero;

  void loadPlan(WorkoutPlan p) {
    if (state != WorkoutState.idle) return;
    plan = p;
    notifyListeners();
  }

  Future<void> start() async {
    if (state == WorkoutState.running) return;
    if (state == WorkoutState.idle) {
      record = WorkoutRecord(startTime: DateTime.now());
      currentSegmentIndex = 0;
      _segmentStartTime = DateTime.now();
      _totalDistAtSegmentStart = bike.tripKm ?? 0;
      _pid.reset(); _lastCommandedPas = null;
      await gps.start();
      await health.startWorkout(record!.startTime);
      final startLabel = _fmtTime(record!.startTime);
      await liveActivity.start(startLabel: 'Started $startLabel');
    }
    state = WorkoutState.running;
    _applySegmentTarget();
    // UI refresh timer — foreground only, not critical
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state == WorkoutState.running) notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    if (state != WorkoutState.running) return;
    state = WorkoutState.paused;
    _uiTicker?.cancel();
    notifyListeners();
  }

  Future<String?> stop() async {
    if (state == WorkoutState.idle) return null;
    _uiTicker?.cancel();
    state = WorkoutState.idle;
    gps.stop();
    _pid.reset(); _lastCommandedPas = null; _lowCadenceSince = null; _lowCadenceCooldownUntil = null;
    _prevAltitudeM = null; _prevDistanceKm = null; _currentGradientPct = 0; estimatedRiderPowerW = null;
    await health.endWorkout(DateTime.now());
    await liveActivity.end();
    notifyListeners();

    if (record == null || record!.points.isEmpty) return null;
    return _exportFit(record!);
  }

  // Called by BleService every time a 0x0601 telemetry frame arrives.
  // This runs via the CoreBluetooth callback — guaranteed even with screen off.
  void onBikeTelemetry() {
    if (state != WorkoutState.running) return;

    // Record point
    final pos = gps.latest;
    final p = RecordPoint(
      timestamp: DateTime.now(),
      lat: pos?.latitude,
      lon: pos?.longitude,
      hrBpm: hr.bpm,
      speedKmh: bike.speedKmh,
      powerWatts: power.watts,
      cadenceRpm: power.cadenceRpm ?? cadence.cadenceRpm,
      batteryPct: bike.battery,
      distanceKm: bike.tripKm,
      pas: bike.pas,
    );
    // Power estimation (only when no real power sensor)
    if (power.watts == null && bike.speedKmh != null && bike.speedKmh! > 0) {
      _updateGradient(pos?.altitude, bike.tripKm);
      estimatedRiderPowerW = PowerEstimator.riderPowerW(
        speedKmh: bike.speedKmh!,
        gradientPct: _currentGradientPct,
        totalMassKg: riderWeightKg + bikeWeightKg,
        motorWatts: motorWattsAtCurrentPas,
      );
    } else if (power.watts != null) {
      estimatedRiderPowerW = null;
    }

    record!.add(RecordPoint(
      timestamp: p.timestamp,
      lat: p.lat,
      lon: p.lon,
      hrBpm: p.hrBpm,
      speedKmh: p.speedKmh,
      powerWatts: p.powerWatts,
      cadenceRpm: p.cadenceRpm,
      batteryPct: p.batteryPct,
      distanceKm: p.distanceKm,
      pas: p.pas,
      estimatedRiderPowerW: estimatedRiderPowerW,
    ));

    // PID — runs on every telemetry frame, guaranteed in background
    if (autoPasEnabled && hr.bpm != null && bike.pas != null) {
      final currentPas = bike.pas!;
      // If bike PAS differs from what we last commanded, user changed it manually.
      // Respect that choice: update our reference and reset PID cooldown.
      if (_lastCommandedPas != null && currentPas != _lastCommandedPas) {
        // User changed PAS manually — respect it and wait a full cooldown before acting
        _lastCommandedPas = currentPas;
        _pid.reset();
      } else {
        final newPas = _pid.update(hr.bpm!, _autoTargetMinBpm, _autoTargetMaxBpm, currentPas);
        if (newPas != currentPas) {
          _lastCommandedPas = newPas;
          onSetPas?.call(newPas);
        }
      }
    }

    // Cadence boost: if cadence below threshold for N seconds, +1 PAS
    if (_lowCadenceBoostEnabled && bike.pas != null) {
      final now = DateTime.now();
      if (_lowCadenceCooldownUntil != null && now.isBefore(_lowCadenceCooldownUntil!)) {
        // In cooldown after last boost — skip entirely
      } else {
        final cad = power.cadenceRpm ?? cadence.cadenceRpm;
        if (cad != null && cad < _lowCadenceThresholdRpm) {
          _lowCadenceSince ??= now;
          final secondsBelow = now.difference(_lowCadenceSince!).inSeconds;
          if (secondsBelow >= _lowCadenceBoostSeconds) {
            final boosted = (bike.pas! + 1).clamp(0, _pid.maxPas);
            if (boosted != bike.pas) {
              _lastCommandedPas = boosted;
              onSetPas?.call(boosted);
            }
            _lowCadenceSince = null;
            _lowCadenceCooldownUntil = now.add(Duration(seconds: _lowCadenceBoostSeconds));
          }
        } else {
          _lowCadenceSince = null;
        }
      }
    }

    // HealthKit sample
    health.addSample(
      heartRate: hr.bpm,
      distanceKm: bike.tripKm,
    );

    // Live Activity update
    final zone = currentZone;
    liveActivity.update(
      heartRate: hr.bpm ?? 0,
      pas: bike.pas ?? 0,
      speedKmh: bike.speedKmh ?? 0,
      battery: bike.battery ?? 0,
      zoneName: zone?.name ?? '--',
      zoneColorHex: zone != null ? _colorToHex(zone.color.value) : '#FFFFFF',
      elapsedSeconds: record!.elapsed.inSeconds,
    );

    // Segment advancement
    _advanceSegment(p);

    notifyListeners();
  }

  void _advanceSegment(RecordPoint p) {
    final seg = currentSegment;
    if (seg == null) return;

    if (seg.constraint == SegmentConstraint.time) {
      // Use wall-clock diff — works in background without timer ticks
      final elapsed = DateTime.now().difference(_segmentStartTime!).inSeconds;
      if (elapsed >= seg.value) _nextSegment();
    } else {
      final distNow = p.distanceKm ?? 0;
      final distInSeg = distNow - _totalDistAtSegmentStart;
      if (distInSeg >= seg.value) _nextSegment();
    }
  }

  void _nextSegment() {
    currentSegmentIndex++;
    _segmentStartTime = DateTime.now();
    _totalDistAtSegmentStart = bike.tripKm ?? 0;
    _pid.reset(); _lastCommandedPas = null;
    _applySegmentTarget();
  }

  void _applySegmentTarget() {
    final seg = currentSegment;
    if (seg == null) {
      _autoTargetMinBpm = 0;
      _autoTargetMaxBpm = 999;
      return;
    }
    final zone = zones.zones.firstWhere(
      (z) => z.number == seg.zoneNumber,
      orElse: () => zones.zones[1],
    );
    _autoTargetMinBpm = zone.minBpm;
    _autoTargetMaxBpm = zone.maxBpm;
  }

  Future<String?> _exportFit(WorkoutRecord rec) async {
    try {
      final bytes = FitWriter.write(rec);
      final dir = await getApplicationDocumentsDirectory();
      final ts =
          rec.startTime.toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('${dir.path}/workout_$ts.fit');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'BafangRideSync workout');
      return file.path;
    } catch (e) {
      debugPrint('FIT export error: $e');
      return null;
    }
  }

  Future<void> savePlan(WorkoutPlan p) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${p.name.replaceAll(' ', '_')}.brsplan');
    await file.writeAsString(p.toJsonString());
  }

  Future<List<String>> listSavedPlans() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.brsplan'))
        .map((f) => f.path)
        .toList();
  }

  Future<WorkoutPlan?> loadPlanFromFile(String path) async {
    try {
      final src = await File(path).readAsString();
      return WorkoutPlan.fromJsonString(src);
    } catch (_) {
      return null;
    }
  }

  void _updateGradient(double? altM, double? distKm) {
    if (altM == null || distKm == null) return;
    if (_prevAltitudeM != null && _prevDistanceKm != null) {
      final dDist = (distKm - _prevDistanceKm!) * 1000; // metres
      if (dDist > 2) {
        final dAlt = altM - _prevAltitudeM!;
        final raw = (dAlt / dDist) * 100; // percent
        // EMA smoothing (α = 0.15)
        _currentGradientPct = _currentGradientPct * 0.85 + raw.clamp(-30, 30) * 0.15;
        _prevAltitudeM = altM;
        _prevDistanceKm = distKm;
      }
    } else {
      _prevAltitudeM = altM;
      _prevDistanceKm = distKm;
    }
  }

  static String _colorToHex(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  static String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
