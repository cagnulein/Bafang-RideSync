import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../bafang_data.dart';
import '../models/heart_zone.dart';
import '../services/cadence_service.dart';
import '../services/gps_service.dart';
import '../services/hr_service.dart';
import '../services/power_service.dart';
import '../services/workout_service.dart';
import 'cadence_scan_screen.dart';
import 'hr_scan_screen.dart';
import 'plan_screen.dart';
import 'power_scan_screen.dart';
import 'zones_screen.dart';

class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer6<WorkoutService, HrService, CadenceService, PowerService,
        BafangData, GpsService>(
      builder: (context, ws, hr, cad, pwr, bike, gps, _) {
        final zone = ws.currentZone;
        final accentColor = zone?.color ?? Colors.white54;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _appBar(context, ws, hr, cad, pwr, accentColor),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // HR big display
                _hrCard(hr, zone, accentColor),
                const SizedBox(height: 12),
                // Bike metrics row
                _bikeRow(bike),
                // External sensor row (cadence / power meter / estimated power)
                if (cad.connected || pwr.connected || ws.estimatedRiderPowerW != null) ...[
                  const SizedBox(height: 8),
                  _externalSensorRow(cad, pwr, ws),
                ],
                const SizedBox(height: 12),
                // Workout info
                if (ws.state != WorkoutState.idle) _workoutInfo(ws, accentColor),
                // Segment progress
                if (ws.plan != null && ws.currentSegment != null)
                  _segmentCard(ws, accentColor),
                const SizedBox(height: 16),
                // Controls
                _controls(context, ws),
                const SizedBox(height: 16),
                // Map
                _MapCard(ws: ws, gps: gps, accentColor: accentColor),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _appBar(BuildContext context, WorkoutService ws, HrService hr,
      CadenceService cad, PowerService pwr, Color accent) {
    return AppBar(
      backgroundColor: Colors.black,
      title: const Text('Workout', style: TextStyle()),
      actions: [
        IconButton(
          icon: Icon(Icons.favorite,
              color: hr.connected ? Colors.redAccent : Colors.white38),
          tooltip: 'HR Monitor',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const HrScanScreen())),
        ),
        IconButton(
          icon: Icon(Icons.rotate_right,
              color: cad.connected ? Colors.cyanAccent : Colors.white38),
          tooltip: 'Cadence Sensor',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CadenceScanScreen())),
        ),
        IconButton(
          icon: Icon(Icons.bolt,
              color: pwr.connected ? Colors.orangeAccent : Colors.white38),
          tooltip: 'Power Meter',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PowerScanScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.list_alt, color: Colors.white54),
          tooltip: 'Workout plan',
          onPressed: ws.state == WorkoutState.idle
              ? () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const PlanScreen()))
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart, color: Colors.white54),
          tooltip: 'HR Zones',
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ZonesScreen())),
        ),
        PopupMenuButton<String>(
          color: const Color(0xFF1a1a1a),
          onSelected: (v) {
            if (v == 'auto') {
              ws.autoPasEnabled = !ws.autoPasEnabled;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'auto',
              child: Row(children: [
                Icon(ws.autoPasEnabled ? Icons.check : Icons.close,
                    size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                const Text('Auto PAS',
                    style: TextStyle(color: Colors.white70)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _hrCard(HrService hr, HeartZone? zone, Color accent) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.5),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.favorite, color: accent, size: 22),
          const SizedBox(width: 8),
          Text(
            '${hr.bpm ?? '--'} bpm',
            style: TextStyle(
                color: accent,
                fontSize: 52,
                fontWeight: FontWeight.bold),
          ),
        ]),
        if (zone != null) ...[
          const SizedBox(height: 6),
          Text(
            'Zone ${zone.number} — ${zone.name}',
            style: TextStyle(color: accent, fontSize: 14),
          ),
          Text(
            '${zone.minBpm}–${zone.maxBpm} bpm',
            style: const TextStyle(
                color: Colors.white38, fontSize: 12),
          ),
        ] else if (!hr.connected) ...[
          const SizedBox(height: 8),
          const Text('No HR monitor connected',
              style: TextStyle(
                  color: Colors.white38, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _externalSensorRow(CadenceService cad, PowerService pwr, WorkoutService ws) {
    final rpm = pwr.cadenceRpm ?? cad.cadenceRpm;
    final w = pwr.watts;
    final estW = ws.estimatedRiderPowerW;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d0d),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (rpm != null)
            _metricCell('RPM', rpm.toStringAsFixed(0), 'rpm', Colors.cyanAccent),
          if (w != null)
            _metricCell('POWER', '$w', 'W', Colors.orangeAccent)
          else if (estW != null)
            _metricCell('RIDER~', '$estW', 'W', Colors.orange.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  Widget _bikeRow(BafangData bike) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _metricCell('SPEED',
            bike.speedKmh != null ? '${bike.speedKmh!.toStringAsFixed(1)}' : '--',
            'km/h', Colors.white),
        _metricCell('PAS', bike.pas?.toString() ?? '--', 'lvl',
            Colors.lightBlueAccent),
        _metricCell('BAT', bike.battery != null ? '${bike.battery}' : '--', '%',
            Colors.greenAccent),
        _metricCell(
            'PWR',
            bike.powerWatts != null ? '${bike.powerWatts}' : '--',
            'W',
            Colors.orangeAccent),
      ],
    );
  }

  Widget _metricCell(String label, String value, String unit, Color color) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white38, fontSize: 11)),
      RichText(
        text: TextSpan(
          style: const TextStyle(),
          children: [
            TextSpan(
                text: value,
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            TextSpan(
                text: ' $unit',
                style: TextStyle(color: color.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      ),
    ]);
  }

  Widget _workoutInfo(WorkoutService ws, Color accent) {
    final elapsed = ws.elapsed;
    final hh = elapsed.inHours.toString().padLeft(2, '0');
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _metricCell('TIME', '$hh:$mm:$ss', '', accent),
          _metricCell(
              'DIST',
              ws.record != null
                  ? ws.record!.totalDistanceKm.toStringAsFixed(2)
                  : '--',
              'km',
              accent),
        ],
      ),
    );
  }

  Widget _segmentCard(WorkoutService ws, Color accent) {
    final seg = ws.currentSegment!;
    final total = ws.plan!.segments.length;
    final idx = ws.currentSegmentIndex + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Segment $idx / $total',
            style: const TextStyle(
                color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(seg.label,
            style: TextStyle(
                color: accent, fontSize: 15)),
      ]),
    );
  }

  Widget _controls(BuildContext context, WorkoutService ws) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (ws.state == WorkoutState.idle || ws.state == WorkoutState.paused)
          _ctrlBtn(
            icon: Icons.play_arrow,
            color: Colors.greenAccent,
            label: ws.state == WorkoutState.paused ? 'Resume' : 'Start',
            onPressed: ws.start,
          ),
        if (ws.state == WorkoutState.running) ...[
          _ctrlBtn(
            icon: Icons.pause,
            color: Colors.amberAccent,
            label: 'Pause',
            onPressed: ws.pause,
          ),
          const SizedBox(width: 16),
        ],
        if (ws.state != WorkoutState.idle)
          _ctrlBtn(
            icon: Icons.stop,
            color: Colors.redAccent,
            label: 'Stop',
            onPressed: () async {
              final path = await ws.stop();
              if (context.mounted && path != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('FIT exported: $path')),
                );
              }
            },
          ),
      ],
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback? onPressed,
  }) =>
      ElevatedButton.icon(
        icon: Icon(icon, color: Colors.black),
        label: Text(label,
            style: const TextStyle(color: Colors.black)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        onPressed: onPressed,
      );
}

// ── Map card ──────────────────────────────────────────────────────────────────

class _MapCard extends StatefulWidget {
  final WorkoutService ws;
  final GpsService gps;
  final Color accentColor;

  const _MapCard({
    required this.ws,
    required this.gps,
    required this.accentColor,
  });

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  final _mapController = MapController();
  bool _follow = true;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> get _trackPoints {
    final rec = widget.ws.record;
    if (rec == null) return [];
    return rec.points
        .where((p) => p.lat != null && p.lon != null)
        .map((p) => LatLng(p.lat!, p.lon!))
        .toList();
  }

  LatLng? get _currentPos {
    final pos = widget.gps.latest;
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  @override
  void didUpdateWidget(_MapCard old) {
    super.didUpdateWidget(old);
    final pos = _currentPos;
    if (_follow && pos != null) {
      try {
        _mapController.move(pos, _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _trackPoints;
    final pos = _currentPos;
    final hasData = pos != null || track.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            if (!hasData)
              Container(
                color: const Color(0xFF1a1a1a),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, color: Colors.white24, size: 48),
                    const SizedBox(height: 8),
                    const Text('GPS non disponibile',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 13)),
                  ],
                ),
              )
            else
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: pos ?? track.last,
                  initialZoom: 15,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture) setState(() => _follow = false);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.bafang.ridesync',
                  ),
                  if (track.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: track,
                          color: widget.accentColor,
                          strokeWidth: 3,
                        ),
                      ],
                    ),
                  if (pos != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pos,
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            // Re-center button
            if (hasData && !_follow)
              Positioned(
                bottom: 10,
                right: 10,
                child: FloatingActionButton.small(
                  heroTag: 'map_recenter',
                  backgroundColor: Colors.black87,
                  onPressed: () {
                    final p = _currentPos;
                    if (p != null) {
                      _mapController.move(p, _mapController.camera.zoom);
                    }
                    setState(() => _follow = true);
                  },
                  child: const Icon(Icons.my_location,
                      color: Colors.white, size: 18),
                ),
              ),
            // OSM attribution (required by tile license)
            Positioned(
              bottom: 4,
              left: 8,
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(
                    color: Colors.black54,
                    fontSize: 9,
                    background: Paint()..color = Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
