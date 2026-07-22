import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bafang_data.dart';
import 'ble_service.dart';
import 'screens/workout_screen.dart';

class HomeScreen extends StatefulWidget {
  final BleService bleService;
  const HomeScreen({super.key, required this.bleService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<BafangData>(builder: (context, data, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(data),
        body: IndexedStack(
          index: _tab,
          children: [
            _DataTab(data: data, bleService: widget.bleService),
            const WorkoutScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF111111),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.speed), label: 'Data'),
            NavigationDestination(
                icon: Icon(Icons.directions_bike), label: 'Workout'),
          ],
        ),
      );
    });
  }

  AppBar _buildAppBar(BafangData data) {
    final statusColor = switch (data.bleStatus) {
      'OK' => Colors.greenAccent,
      'SIM' => Colors.amber,
      'INIT' => Colors.lightBlueAccent,
      'ERR' => Colors.redAccent,
      _ => Colors.white54,
    };

    return AppBar(
      backgroundColor: Colors.black,
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Courier', fontSize: 16),
          children: [
            const TextSpan(
                text: 'BafangRideSync  ',
                style: TextStyle(color: Colors.white)),
            TextSpan(
                text: '[${data.bleStatus}]',
                style:
                    TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.science_outlined, color: Colors.amber),
          tooltip: 'Inject sim frames',
          onPressed: data.injectSimFrames,
        ),
        if (data.bleStatus == 'SCAN' ||
            data.bleStatus == 'ERR' ||
            data.bleStatus == 'IDLE')
          IconButton(
            icon: const Icon(Icons.bluetooth_searching,
                color: Colors.lightBlueAccent),
            tooltip: 'Start scan',
            onPressed: widget.bleService.startScan,
          ),
        if (data.bleStatus == 'SCAN')
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled, color: Colors.white54),
            tooltip: 'Stop scan',
            onPressed: widget.bleService.stopScan,
          ),
      ],
    );
  }
}

// ── Data tab ──────────────────────────────────────────────────────────────────

class _DataTab extends StatelessWidget {
  final BafangData data;
  final BleService bleService;
  const _DataTab({required this.data, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('MODEL', data.model),
        const SizedBox(height: 12),
        _metric('BATTERY', _pct(data.battery), Colors.greenAccent),
        _metric('PAS', data.pas?.toString() ?? '--', Colors.lightBlueAccent),
        _metric('POWER', _watts(data.powerWatts), Colors.orangeAccent),
        _metric('CADENCE', _rpm(data.cadenceRpm), Colors.cyanAccent),
        _metric('SPEED', _kmh(data.speedKmh), Colors.white),
        _metric('TRIP', _km(data.tripKm), Colors.white70),
        _metric('ODO', _km(data.odometerKm), Colors.white70),
        const SizedBox(height: 8),
        _pasControls(),
        const Divider(color: Colors.white12, height: 32),
        _label('TICK', data.tickCounter?.toString() ?? '--'),
        _label(
            'WHEEL CFG', data.wheelCfg != null ? '${data.wheelCfg} mm?' : '--'),
        const Divider(color: Colors.white12, height: 32),
        if (data.raw0601 != null) _hexBlock('06 01 DATA', data.raw0601!),
        if (data.raw0609 != null) _hexBlock('06 09 DATA', data.raw0609!),
      ]),
    );
  }

  String _pct(int? v) => v != null ? '$v %' : '--';
  String _watts(int? v) => v != null ? '$v W' : '--';
  String _rpm(double? v) => v != null ? '${v.toStringAsFixed(1)} rpm' : '--';
  String _kmh(double? v) => v != null ? '${v.toStringAsFixed(1)} km/h' : '--';
  String _km(double? v) => v != null ? '${v.toStringAsFixed(2)} km' : '--';

  Widget _pasControls() {
    final current = data.pas ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                current > 0 ? () => bleService.setPasLevel(current - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
            label: const Text('PAS'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                current < 9 ? () => bleService.setPasLevel(current + 1) : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('PAS'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var level = 0; level <= 9; level++)
            SizedBox(
              width: 42,
              child: OutlinedButton(
                onPressed: () => bleService.setPasLevel(level),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: data.pas == level
                      ? Colors.lightBlueAccent
                      : Colors.white54,
                  side: BorderSide(
                    color: data.pas == level
                        ? Colors.lightBlueAccent
                        : Colors.white24,
                  ),
                ),
                child: Text('$level',
                    style: const TextStyle(fontFamily: 'Courier')),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _metric(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontFamily: 'Courier',
                    fontSize: 13)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontFamily: 'Courier',
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _label(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text('$k  ',
              style: const TextStyle(
                  color: Colors.white38, fontFamily: 'Courier', fontSize: 12)),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: Colors.white60,
                      fontFamily: 'Courier',
                      fontSize: 12))),
        ]),
      );

  Widget _hexBlock(String title, List<int> bytes) {
    final rows = <String>[];
    for (int i = 0; i < bytes.length; i += 8) {
      final end = (i + 8).clamp(0, bytes.length);
      final hex = bytes
          .sublist(i, end)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      rows.add('  $hex');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white38, fontFamily: 'Courier', fontSize: 11)),
        Text(rows.join('\n'),
            style: const TextStyle(
                color: Colors.white24, fontFamily: 'Courier', fontSize: 11)),
      ]),
    );
  }
}
