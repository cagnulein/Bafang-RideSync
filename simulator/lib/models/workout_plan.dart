import 'dart:convert';

enum SegmentConstraint { time, distance }

class WorkoutSegment {
  final int zoneNumber;        // 1-5
  final SegmentConstraint constraint;
  final double value;          // seconds if time, km if distance

  const WorkoutSegment({
    required this.zoneNumber,
    required this.constraint,
    required this.value,
  });

  String get label {
    if (constraint == SegmentConstraint.time) {
      final m = (value ~/ 60).toString().padLeft(2, '0');
      final s = (value % 60).toInt().toString().padLeft(2, '0');
      return 'Z$zoneNumber  $m:$s';
    } else {
      return 'Z$zoneNumber  ${value.toStringAsFixed(2)} km';
    }
  }

  Map<String, dynamic> toJson() => {
        'zone': zoneNumber,
        'constraint': constraint.name,
        'value': value,
      };

  factory WorkoutSegment.fromJson(Map<String, dynamic> j) => WorkoutSegment(
        zoneNumber: j['zone'] as int,
        constraint: SegmentConstraint.values
            .firstWhere((e) => e.name == j['constraint']),
        value: (j['value'] as num).toDouble(),
      );
}

class WorkoutPlan {
  String name;
  List<WorkoutSegment> segments;

  WorkoutPlan({required this.name, required this.segments});

  WorkoutPlan.empty()
      : name = 'New workout',
        segments = [];

  String toJsonString() =>
      jsonEncode({'name': name, 'segments': segments.map((s) => s.toJson()).toList()});

  factory WorkoutPlan.fromJsonString(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    return WorkoutPlan(
      name: j['name'] as String,
      segments: (j['segments'] as List)
          .map((s) => WorkoutSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
