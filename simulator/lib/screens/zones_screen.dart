import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/heart_zone.dart';

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HrZones>(builder: (context, zones, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('HR Zones', style: TextStyle(fontFamily: 'Courier')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _maxHrRow(context, zones),
            const SizedBox(height: 24),
            ...zones.zones.map((z) => _ZoneRow(zone: z)),
          ],
        ),
      );
    });
  }

  Widget _maxHrRow(BuildContext context, HrZones zones) {
    return Row(
      children: [
        const Text('Max HR:',
            style: TextStyle(color: Colors.white70, fontFamily: 'Courier')),
        const SizedBox(width: 16),
        Expanded(
          child: Slider(
            min: 120,
            max: 220,
            divisions: 100,
            value: zones.maxHr.toDouble(),
            label: '${zones.maxHr} bpm',
            activeColor: Colors.redAccent,
            onChanged: (v) => zones.setMaxHr(v.round()),
          ),
        ),
        Text('${zones.maxHr} bpm',
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Courier', fontSize: 16)),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: zone.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: zone.color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 40,
            decoration: BoxDecoration(
              color: zone.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Zone ${zone.number} — ${zone.name}',
                    style: TextStyle(
                        color: zone.color,
                        fontFamily: 'Courier',
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                Text('${zone.minBpm} – ${zone.maxBpm} bpm',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontFamily: 'Courier',
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
