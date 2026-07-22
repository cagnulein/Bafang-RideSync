import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/heart_zone.dart';
import '../models/workout_plan.dart';
import '../services/workout_service.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late WorkoutPlan _plan;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WorkoutService>();
    _plan = ws.plan ?? WorkoutPlan.empty();
  }

  void _addSegment() {
    setState(() {
      _plan.segments.add(WorkoutSegment(
        zoneNumber: 2,
        constraint: SegmentConstraint.time,
        value: 300, // 5 min default
      ));
      _dirty = true;
    });
  }

  void _save() async {
    final ws = context.read<WorkoutService>();
    await ws.savePlan(_plan);
    ws.loadPlan(_plan);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plan saved')));
    }
  }

  void _load() async {
    final ws = context.read<WorkoutService>();
    final paths = await ws.listSavedPlans();
    if (!mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No saved plans')));
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text('Load plan',
            style: TextStyle(color: Colors.white, fontFamily: 'Courier')),
        children: paths.map((p) {
          final name = p.split('/').last.replaceAll('.brsplan', '');
          return SimpleDialogOption(
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white70, fontFamily: 'Courier')),
            onPressed: () => Navigator.pop(ctx, p),
          );
        }).toList(),
      ),
    );
    if (chosen == null) return;
    final loaded = await ws.loadPlanFromFile(chosen);
    if (loaded != null) {
      setState(() {
        _plan = loaded;
        _dirty = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = context.watch<HrZones>().zones;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: TextField(
          controller: TextEditingController(text: _plan.name),
          style: const TextStyle(
              color: Colors.white, fontFamily: 'Courier', fontSize: 16),
          decoration: const InputDecoration(
              border: InputBorder.none, hintText: 'Workout name'),
          onChanged: (v) {
            _plan.name = v;
            _dirty = true;
          },
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Load',
              onPressed: _load),
          IconButton(
              icon: Icon(Icons.save,
                  color: _dirty ? Colors.amber : Colors.white38),
              tooltip: 'Save',
              onPressed: _dirty ? _save : null),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _plan.segments.length,
        onReorder: (old, nw) {
          setState(() {
            final item = _plan.segments.removeAt(old);
            _plan.segments.insert(nw > old ? nw - 1 : nw, item);
            _dirty = true;
          });
        },
        itemBuilder: (_, i) {
          final seg = _plan.segments[i];
          return _SegmentCard(
            key: ValueKey(i),
            segment: seg,
            zones: zones,
            onChanged: (newSeg) {
              setState(() {
                _plan.segments[i] = newSeg;
                _dirty = true;
              });
            },
            onDelete: () {
              setState(() {
                _plan.segments.removeAt(i);
                _dirty = true;
              });
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSegment,
        backgroundColor: Colors.greenAccent.shade700,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final WorkoutSegment segment;
  final List<HeartZone> zones;
  final ValueChanged<WorkoutSegment> onChanged;
  final VoidCallback onDelete;

  const _SegmentCard({
    super.key,
    required this.segment,
    required this.zones,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final zone = zones.firstWhere((z) => z.number == segment.zoneNumber,
        orElse: () => zones[0]);

    return Card(
      color: const Color(0xFF1a1a1a),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Zone selector
            DropdownButton<int>(
              value: segment.zoneNumber,
              dropdownColor: const Color(0xFF222222),
              style: TextStyle(
                  color: zone.color, fontFamily: 'Courier', fontSize: 14),
              underline: const SizedBox.shrink(),
              items: zones
                  .map((z) => DropdownMenuItem(
                        value: z.number,
                        child: Text('Z${z.number} ${z.name}',
                            style: TextStyle(color: z.color)),
                      ))
                  .toList(),
              onChanged: (v) => v != null
                  ? onChanged(WorkoutSegment(
                      zoneNumber: v,
                      constraint: segment.constraint,
                      value: segment.value))
                  : null,
            ),
            const Spacer(),
            // Constraint toggle
            ToggleButtons(
              isSelected: [
                segment.constraint == SegmentConstraint.time,
                segment.constraint == SegmentConstraint.distance,
              ],
              onPressed: (i) => onChanged(WorkoutSegment(
                zoneNumber: segment.zoneNumber,
                constraint: i == 0
                    ? SegmentConstraint.time
                    : SegmentConstraint.distance,
                value: i == 0 ? 300 : 5.0,
              )),
              borderColor: Colors.white24,
              selectedBorderColor: zone.color,
              fillColor: zone.color.withOpacity(0.2),
              color: Colors.white38,
              selectedColor: zone.color,
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 32),
              children: const [
                Icon(Icons.timer, size: 16),
                Icon(Icons.directions_bike, size: 16),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.white38),
              onPressed: onDelete,
            ),
          ]),
          // Value slider
          Row(children: [
            Expanded(
              child: Slider(
                min: segment.constraint == SegmentConstraint.time ? 60 : 0.5,
                max: segment.constraint == SegmentConstraint.time ? 3600 : 50,
                divisions:
                    segment.constraint == SegmentConstraint.time ? 119 : 99,
                value: segment.value,
                activeColor: zone.color,
                onChanged: (v) => onChanged(WorkoutSegment(
                    zoneNumber: segment.zoneNumber,
                    constraint: segment.constraint,
                    value: v)),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                segment.constraint == SegmentConstraint.time
                    ? _fmtTime(segment.value.round())
                    : '${segment.value.toStringAsFixed(1)} km',
                style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Courier',
                    fontSize: 13),
                textAlign: TextAlign.right,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  String _fmtTime(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
