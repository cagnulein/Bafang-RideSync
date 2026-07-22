import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bafang_data.dart';
import '../models/heart_zone.dart';
import '../services/workout_service.dart';

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<HrZones, WorkoutService, BafangData>(
        builder: (context, zones, workout, bike, _) {
      final pasAbsMax = bike.pasMax ?? 9;
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionHeader('Heart Rate Zones'),
            _maxHrRow(context, zones),
            const SizedBox(height: 16),
            ...zones.zones.map((z) => _ZoneRow(zone: z)),
            const SizedBox(height: 32),
            _sectionHeader('Auto-PAS'),
            _pidIntensityRow(workout),
            const SizedBox(height: 24),
            _pasRangeRow(workout, pasAbsMax),
          ],
        ),
      );
    });
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
      );

  Widget _maxHrRow(BuildContext context, HrZones zones) {
    return _SliderRow(
      label: 'Max HR',
      value: zones.maxHr.toDouble(),
      min: 120,
      max: 220,
      divisions: 100,
      displayText: '${zones.maxHr} bpm',
      activeColor: Colors.redAccent,
      onChanged: (v) => zones.setMaxHr(v.round()),
    );
  }

  Widget _pidIntensityRow(WorkoutService workout) {
    final intensity = workout.pidIntensity;
    final cooldown = (33 - intensity * 3).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SliderRow(
          label: 'Response speed',
          value: intensity.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          displayText: '$intensity  (±1 PAS every ${cooldown}s)',
          activeColor: Colors.greenAccent,
          onChanged: (v) => workout.pidIntensity = v.round(),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            '1 = very gentle   10 = aggressive',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _pasRangeRow(WorkoutService workout, int pasAbsMax) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SliderRow(
          label: 'Min PAS',
          value: workout.pidMinPas.toDouble(),
          min: 0,
          max: (workout.pidMaxPas - 1).toDouble(),
          divisions: workout.pidMaxPas,
          displayText: '${workout.pidMinPas}',
          activeColor: Colors.lightBlueAccent,
          onChanged: (v) => workout.pidMinPas = v.round(),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Max PAS',
          value: workout.pidMaxPas.toDouble(),
          min: (workout.pidMinPas + 1).toDouble(),
          max: pasAbsMax.toDouble(),
          divisions: pasAbsMax - workout.pidMinPas,
          displayText: '${workout.pidMaxPas}  (bike max: $pasAbsMax)',
          activeColor: Colors.lightBlueAccent,
          onChanged: (v) => workout.pidMaxPas = v.round(),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'Auto-PAS will only operate within this range',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayText;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayText,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max);
    final safeDivisions = divisions.clamp(1, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            Text(displayText, style: TextStyle(color: activeColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(
          value: clampedValue,
          min: min,
          max: max,
          divisions: safeDivisions,
          activeColor: activeColor,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  final HeartZone zone;
  const _ZoneRow({required this.zone});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: zone.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: zone.color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 36,
            decoration: BoxDecoration(
              color: zone.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Zone ${zone.number} — ${zone.name}',
                  style: TextStyle(color: zone.color, fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${zone.minBpm} – ${zone.maxBpm} bpm',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
        ],
      ),
    );
  }
}
