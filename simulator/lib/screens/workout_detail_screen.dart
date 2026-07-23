import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import '../models/workout_record.dart';
import '../models/workout_summary.dart';
import '../services/workout_service.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final WorkoutSummary summary;
  const WorkoutDetailScreen({super.key, required this.summary});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  List<RecordPoint>? _points;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final ws = context.read<WorkoutService>();
    final pts = await ws.loadWorkoutPoints(widget.summary);
    if (mounted) setState(() { _points = pts; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final dur = s.duration;
    final hh = dur.inHours.toString().padLeft(2, '0');
    final mm = (dur.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_fmtDate(s.startTime)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white24))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Map
                  _MapCard(points: _points!),
                  const SizedBox(height: 20),
                  // Stats grid
                  _statsGrid(s, '$hh:$mm:$ss'),
                  const SizedBox(height: 20),
                  // Charts section placeholder (HR + power over time)
                  if (_points!.any((p) => p.hrBpm != null))
                    _ChartCard(points: _points!, label: 'Heart Rate', color: Colors.redAccent,
                        getValue: (p) => p.hrBpm?.toDouble()),
                  if (_points!.any((p) => (p.powerWatts ?? p.estimatedRiderPowerW) != null)) ...[
                    const SizedBox(height: 12),
                    _ChartCard(
                      points: _points!,
                      label: s.hasPowerEstimate ? 'Rider Power (estimated)' : 'Power',
                      color: Colors.orangeAccent,
                      getValue: (p) => (p.powerWatts ?? p.estimatedRiderPowerW)?.toDouble(),
                    ),
                  ],
                  if (_points!.any((p) => p.speedKmh != null)) ...[
                    const SizedBox(height: 12),
                    _ChartCard(points: _points!, label: 'Speed', color: Colors.white70,
                        getValue: (p) => p.speedKmh, unit: 'km/h'),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statsGrid(WorkoutSummary s, String durationStr) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        _statCard('Duration', durationStr, Icons.timer_outlined, Colors.white),
        _statCard('Distance', '${s.distanceKm.toStringAsFixed(2)} km', Icons.route, Colors.lightBlueAccent),
        if (s.avgHrBpm != null)
          _statCard('Avg HR', '${s.avgHrBpm} bpm', Icons.favorite, Colors.redAccent),
        if (s.avgPowerW != null)
          _statCard(
            s.hasPowerEstimate ? 'Rider Power~' : 'Avg Power',
            '${s.avgPowerW} W',
            Icons.bolt,
            Colors.orangeAccent,
          ),
        if (s.avgCadenceRpm != null)
          _statCard('Avg Cadence', '${s.avgCadenceRpm!.round()} rpm', Icons.rotate_right, Colors.cyanAccent),
        if (s.maxSpeedKmh != null)
          _statCard('Max Speed', '${s.maxSpeedKmh!.toStringAsFixed(1)} km/h', Icons.speed, Colors.white70),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }

  static String _fmtDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final d = dt.toLocal();
    return '${d.day} ${months[d.month - 1]} ${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
}

// ── Map ──────────────────────────────────────────────────────────────────────

class _MapCard extends StatelessWidget {
  final List<RecordPoint> points;
  const _MapCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final track = points
        .where((p) => p.lat != null && p.lon != null)
        .map((p) => LatLng(p.lat!, p.lon!))
        .toList();

    if (track.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Text('No GPS data', style: TextStyle(color: Colors.white38)),
      );
    }

    // Compute bounding box for initial camera
    final lats = track.map((p) => p.latitude);
    final lons = track.map((p) => p.longitude);
    final centerLat = (lats.reduce((a, b) => a + b)) / track.length;
    final centerLon = (lons.reduce((a, b) => a + b)) / track.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLon),
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bafang.ridesync',
            ),
            PolylineLayer(polylines: [
              Polyline(points: track, color: Colors.lightBlueAccent, strokeWidth: 3),
            ]),
            MarkerLayer(markers: [
              Marker(
                point: track.first,
                width: 16, height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              Marker(
                point: track.last,
                width: 16, height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ]),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap', style: TextStyle(fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini sparkline chart ──────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final List<RecordPoint> points;
  final String label;
  final Color color;
  final double? Function(RecordPoint) getValue;
  final String unit;

  const _ChartCard({
    required this.points,
    required this.label,
    required this.color,
    required this.getValue,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final vals = points
        .map((p) => getValue(p))
        .whereType<double>()
        .toList();

    if (vals.isEmpty) return const SizedBox.shrink();

    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final avgV = vals.reduce((a, b) => a + b) / vals.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          Text('avg ${avgV.round()}${unit.isNotEmpty ? " $unit" : ""}',
              style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: CustomPaint(
            painter: _SparklinePainter(vals: vals, minV: minV, maxV: maxV, color: color),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('min ${minV.round()}', style: TextStyle(color: Colors.white38, fontSize: 10)),
          Text('max ${maxV.round()}', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> vals;
  final double minV;
  final double maxV;
  final Color color;

  _SparklinePainter({required this.vals, required this.minV, required this.maxV, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (vals.length < 2) return;
    final range = (maxV - minV).abs();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final step = size.width / (vals.length - 1);

    double y(double v) {
      if (range < 0.001) return size.height / 2;
      return size.height - ((v - minV) / range) * size.height;
    }

    final path = ui.Path();
    final fill = ui.Path();
    fill.moveTo(0, size.height);
    path.moveTo(0, y(vals[0]));
    fill.lineTo(0, y(vals[0]));

    for (int i = 1; i < vals.length; i++) {
      path.lineTo(i * step, y(vals[i]));
      fill.lineTo(i * step, y(vals[i]));
    }
    fill.lineTo((vals.length - 1) * step, size.height);
    fill.close();

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.vals != vals;
}
