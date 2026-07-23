import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bafang_data.dart';
import '../models/heart_zone.dart';
import '../services/health_service.dart';
import '../services/workout_service.dart';

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer4<HrZones, WorkoutService, BafangData, HealthService>(
        builder: (context, zones, workout, bike, health, _) {
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
            const SizedBox(height: 32),
            _sectionHeader('Cadence Boost'),
            _cadenceBoostSection(workout),
            const SizedBox(height: 32),
            _sectionHeader('Bike Profile'),
            _bikeProfileSection(context, workout, health),
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

  Widget _bikeProfileSection(BuildContext context, WorkoutService workout, HealthService health) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: _SliderRow(
              label: 'Rider weight',
              value: workout.riderWeightKg,
              min: 30,
              max: 200,
              divisions: 170,
              displayText: '${workout.riderWeightKg.round()} kg',
              activeColor: Colors.tealAccent,
              onChanged: (v) => workout.updateRiderWeight(v),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.health_and_safety, size: 16, color: Colors.tealAccent),
            label: const Text('Health', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
            onPressed: () async {
              final kg = await health.fetchBodyWeightKg();
              if (kg != null) workout.updateRiderWeight(kg);
            },
          ),
        ]),
        _SliderRow(
          label: 'Bike weight',
          value: workout.bikeWeightKg,
          min: 5,
          max: 80,
          divisions: 75,
          displayText: '${workout.bikeWeightKg.round()} kg',
          activeColor: Colors.tealAccent,
          onChanged: (v) => workout.updateBikeWeight(v),
        ),
        const SizedBox(height: 16),
        const Text('Motor watts per PAS level',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 8),
        ...List.generate(workout.pasConfigs.length, (i) {
          final cfg = workout.pasConfigs[i];
          return _PasConfigRow(
            pasLevel: i,
            motorWatts: cfg.motorWatts,
            maxSpeedKmh: cfg.maxSpeedKmh,
            onWattsChanged: (w) => workout.updatePasMotorWatts(i, w),
            onSpeedChanged: (s) => workout.updatePasMaxSpeed(i, s),
          );
        }),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Used to estimate rider power when no power meter is connected',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _cadenceBoostSection(WorkoutService workout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Enable',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            Switch(
              value: workout.lowCadenceBoostEnabled,
              activeColor: Colors.orangeAccent,
              onChanged: (v) => workout.lowCadenceBoostEnabled = v,
            ),
          ],
        ),
        if (workout.lowCadenceBoostEnabled) ...[
          const SizedBox(height: 4),
          _SliderRow(
            label: 'Min cadence',
            value: workout.lowCadenceThresholdRpm.toDouble(),
            min: 20,
            max: 120,
            divisions: 100,
            displayText: '${workout.lowCadenceThresholdRpm} rpm',
            activeColor: Colors.orangeAccent,
            onChanged: (v) => workout.lowCadenceThresholdRpm = v.round(),
          ),
          _SliderRow(
            label: 'Delay',
            value: workout.lowCadenceBoostSeconds.toDouble(),
            min: 3,
            max: 60,
            divisions: 57,
            displayText: '${workout.lowCadenceBoostSeconds}s',
            activeColor: Colors.orangeAccent,
            onChanged: (v) => workout.lowCadenceBoostSeconds = v.round(),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'If cadence stays below threshold, +1 PAS after delay',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ],
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

class _PasConfigRow extends StatefulWidget {
  final int pasLevel;
  final int motorWatts;
  final double maxSpeedKmh;
  final ValueChanged<int> onWattsChanged;
  final ValueChanged<double> onSpeedChanged;

  const _PasConfigRow({
    required this.pasLevel,
    required this.motorWatts,
    required this.maxSpeedKmh,
    required this.onWattsChanged,
    required this.onSpeedChanged,
  });

  @override
  State<_PasConfigRow> createState() => _PasConfigRowState();
}

class _PasConfigRowState extends State<_PasConfigRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          SizedBox(
            width: 44,
            child: Text('PAS ${widget.pasLevel}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: widget.motorWatts.toDouble(),
              min: 0,
              max: 1000,
              divisions: 100,
              activeColor: Colors.tealAccent,
              inactiveColor: Colors.white12,
              onChanged: (v) => widget.onWattsChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text('${widget.motorWatts} W',
                style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                textAlign: TextAlign.right),
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white24,
              size: 18,
            ),
          ),
        ]),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 4),
            child: Row(children: [
              const Text('Max speed', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Expanded(
                child: Slider(
                  value: widget.maxSpeedKmh,
                  min: 5,
                  max: 99,
                  divisions: 94,
                  activeColor: Colors.white24,
                  inactiveColor: Colors.white12,
                  onChanged: widget.onSpeedChanged,
                ),
              ),
              Text('${widget.maxSpeedKmh.round()} km/h',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
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
