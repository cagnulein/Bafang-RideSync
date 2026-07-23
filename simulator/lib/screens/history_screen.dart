import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/workout_summary.dart';
import '../services/workout_service.dart';
import 'workout_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutSummary>? _workouts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ws = context.read<WorkoutService>();
    final list = await ws.listWorkouts();
    if (mounted) setState(() { _workouts = list; _loading = false; });
  }

  Future<void> _delete(WorkoutSummary s) async {
    final ws = context.read<WorkoutService>();
    await ws.deleteWorkout(s);
    setState(() => _workouts!.remove(s));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            setState(() { _loading = true; _workouts = null; });
            _load();
          }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white24))
          : _workouts == null || _workouts!.isEmpty
              ? const Center(child: Text('No workouts yet', style: TextStyle(color: Colors.white38)))
              : RefreshIndicator(
                  onRefresh: () async { setState(() { _loading = true; }); await _load(); },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _workouts!.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (context, i) => _WorkoutTile(
                      summary: _workouts![i],
                      onDelete: () => _delete(_workouts![i]),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => WorkoutDetailScreen(summary: _workouts![i])),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  final WorkoutSummary summary;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _WorkoutTile({required this.summary, required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final dur = s.duration;
    final hh = dur.inHours.toString().padLeft(2, '0');
    final mm = (dur.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');

    return Dismissible(
      key: Key(s.jsonPath),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade900,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1a1a1a),
            title: const Text('Delete workout?', style: TextStyle(color: Colors.white)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          _fmtDate(s.startTime),
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 12, children: [
            _chip(Icons.timer_outlined, '$hh:$mm:$ss'),
            _chip(Icons.route, '${s.distanceKm.toStringAsFixed(2)} km'),
            if (s.avgHrBpm != null) _chip(Icons.favorite, '${s.avgHrBpm} bpm', Colors.redAccent),
            if (s.avgPowerW != null)
              _chip(Icons.bolt, '${s.avgPowerW} W${s.hasPowerEstimate ? "~" : ""}', Colors.orangeAccent),
          ]),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      ),
    );
  }

  Widget _chip(IconData icon, String label, [Color color = const Color(0xFF999999)]) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 12)),
    ]);
  }

  static String _fmtDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final d = dt.toLocal();
    return '${d.day} ${months[d.month - 1]} ${d.year}  '
        '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
}
