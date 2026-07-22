import 'package:flutter/material.dart';

class HeartZone {
  final int number;   // 1-5
  final String name;
  final int minBpm;
  final int maxBpm;
  final Color color;

  const HeartZone({
    required this.number,
    required this.name,
    required this.minBpm,
    required this.maxBpm,
    required this.color,
  });

  bool contains(int bpm) => bpm >= minBpm && bpm <= maxBpm;

  int get centerBpm => (minBpm + maxBpm) ~/ 2;

  HeartZone copyWith({int? minBpm, int? maxBpm}) => HeartZone(
        number: number,
        name: name,
        minBpm: minBpm ?? this.minBpm,
        maxBpm: maxBpm ?? this.maxBpm,
        color: color,
      );
}

class HrZones extends ChangeNotifier {
  int maxHr;

  HrZones({this.maxHr = 190});

  List<HeartZone> get zones => [
        HeartZone(
          number: 1,
          name: 'Recovery',
          minBpm: _pct(0.50),
          maxBpm: _pct(0.60),
          color: const Color(0xFF5B8DEF),
        ),
        HeartZone(
          number: 2,
          name: 'Endurance',
          minBpm: _pct(0.60),
          maxBpm: _pct(0.70),
          color: const Color(0xFF4CAF50),
        ),
        HeartZone(
          number: 3,
          name: 'Tempo',
          minBpm: _pct(0.70),
          maxBpm: _pct(0.80),
          color: const Color(0xFFFFEB3B),
        ),
        HeartZone(
          number: 4,
          name: 'Threshold',
          minBpm: _pct(0.80),
          maxBpm: _pct(0.90),
          color: const Color(0xFFFF9800),
        ),
        HeartZone(
          number: 5,
          name: 'VO2 Max',
          minBpm: _pct(0.90),
          maxBpm: maxHr,
          color: const Color(0xFFF44336),
        ),
      ];

  int _pct(double pct) => (maxHr * pct).round();

  HeartZone? zoneFor(int bpm) {
    for (final z in zones) {
      if (bpm >= z.minBpm && bpm <= z.maxBpm) return z;
    }
    if (bpm > maxHr) return zones.last;
    if (bpm > 0) return zones.first;
    return null;
  }

  void setMaxHr(int v) {
    maxHr = v.clamp(100, 250);
    notifyListeners();
  }
}
