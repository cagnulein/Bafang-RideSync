import 'dart:convert';
import 'workout_record.dart';

class WorkoutSummary {
  final String jsonPath;
  final DateTime startTime;
  final int durationSeconds;
  final double distanceKm;
  final int? avgHrBpm;
  final int? avgPowerW;
  final double? avgCadenceRpm;
  final double? maxSpeedKmh;
  final bool hasPowerEstimate;

  WorkoutSummary({
    required this.jsonPath,
    required this.startTime,
    required this.durationSeconds,
    required this.distanceKm,
    this.avgHrBpm,
    this.avgPowerW,
    this.avgCadenceRpm,
    this.maxSpeedKmh,
    required this.hasPowerEstimate,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  static WorkoutSummary fromJson(String path, Map<String, dynamic> j) {
    return WorkoutSummary(
      jsonPath: path,
      startTime: DateTime.parse(j['startTime'] as String),
      durationSeconds: j['durationSeconds'] as int,
      distanceKm: (j['distanceKm'] as num).toDouble(),
      avgHrBpm: j['avgHrBpm'] as int?,
      avgPowerW: j['avgPowerW'] as int?,
      avgCadenceRpm: (j['avgCadenceRpm'] as num?)?.toDouble(),
      maxSpeedKmh: (j['maxSpeedKmh'] as num?)?.toDouble(),
      hasPowerEstimate: j['hasPowerEstimate'] as bool? ?? false,
    );
  }

  static List<RecordPoint> pointsFromJson(Map<String, dynamic> j) {
    final raw = j['points'] as List<dynamic>? ?? [];
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return RecordPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        hrBpm: m['hr'] as int?,
        speedKmh: (m['speed'] as num?)?.toDouble(),
        powerWatts: m['power'] as int?,
        cadenceRpm: (m['cad'] as num?)?.toDouble(),
        batteryPct: m['bat'] as int?,
        distanceKm: (m['dist'] as num?)?.toDouble(),
        pas: m['pas'] as int?,
        estimatedRiderPowerW: m['estPower'] as int?,
      );
    }).toList();
  }

  static Map<String, dynamic> toJsonMap(WorkoutSummary s, List<RecordPoint> points) {
    return {
      'startTime': s.startTime.toIso8601String(),
      'durationSeconds': s.durationSeconds,
      'distanceKm': s.distanceKm,
      'avgHrBpm': s.avgHrBpm,
      'avgPowerW': s.avgPowerW,
      'avgCadenceRpm': s.avgCadenceRpm,
      'maxSpeedKmh': s.maxSpeedKmh,
      'hasPowerEstimate': s.hasPowerEstimate,
      'points': points.map((p) => {
        'ts': p.timestamp.millisecondsSinceEpoch,
        if (p.lat != null) 'lat': p.lat,
        if (p.lon != null) 'lon': p.lon,
        if (p.hrBpm != null) 'hr': p.hrBpm,
        if (p.speedKmh != null) 'speed': p.speedKmh,
        if (p.powerWatts != null) 'power': p.powerWatts,
        if (p.cadenceRpm != null) 'cad': p.cadenceRpm,
        if (p.batteryPct != null) 'bat': p.batteryPct,
        if (p.distanceKm != null) 'dist': p.distanceKm,
        if (p.pas != null) 'pas': p.pas,
        if (p.estimatedRiderPowerW != null) 'estPower': p.estimatedRiderPowerW,
      }).toList(),
    };
  }

  static String encode(WorkoutSummary s, List<RecordPoint> points) =>
      jsonEncode(toJsonMap(s, points));

  static (WorkoutSummary, List<RecordPoint>) decode(String path, String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    return (WorkoutSummary.fromJson(path, j), pointsFromJson(j));
  }
}
