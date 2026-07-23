import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bafang_data.dart';
import 'ble_service.dart';
import 'screens/history_screen.dart';
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
            const HistoryScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF111111),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.speed), label: 'Data'),
            NavigationDestination(icon: Icon(Icons.directions_bike), label: 'Workout'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          ],
        ),
      );
    });
  }

  AppBar _buildAppBar(BafangData data) {
    final connected = data.bleStatus == 'OK';
    return AppBar(
      backgroundColor: Colors.black,
      title: Row(
        children: [
          const Text('E-ERG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: connected ? Colors.greenAccent.shade700.withOpacity(0.2) : Colors.white12,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: connected ? Colors.greenAccent.shade700 : Colors.white24),
            ),
            child: Text(
              data.bleStatus,
              style: TextStyle(
                color: connected ? Colors.greenAccent.shade400 : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (data.bleStatus == 'SCAN' || data.bleStatus == 'ERR' || data.bleStatus == 'IDLE')
          IconButton(
            icon: const Icon(Icons.bluetooth_searching, color: Colors.lightBlueAccent),
            tooltip: 'Reconnect',
            onPressed: widget.bleService.startScan,
          ),
      ],
    );
  }
}

class _DataTab extends StatelessWidget {
  final BafangData data;
  final BleService bleService;
  const _DataTab({required this.data, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data.model != null && data.model!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(data.model!, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        _metric('Battery', _pct(data.battery), Colors.greenAccent),
        _metric('PAS', data.pas?.toString() ?? '--', Colors.lightBlueAccent),
        _metric('Power', _watts(data.powerWatts), Colors.orangeAccent),
        _metric('Cadence', _rpm(data.cadenceRpm), Colors.cyanAccent),
        _metric('Speed', _kmh(data.speedKmh), Colors.white),
        _metric('Trip', _km(data.tripKm), Colors.white70),
        _metric('Odometer', _km(data.odometerKm), Colors.white54),
        const SizedBox(height: 16),
        _pasControls(),
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
      const Text('PAS Level', style: TextStyle(color: Colors.white38, fontSize: 13)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: current > 0 ? () => bleService.setPasLevel(current - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
            label: const Text('PAS'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: current < 9 ? () => bleService.setPasLevel(current + 1) : null,
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
                  foregroundColor: data.pas == level ? Colors.lightBlueAccent : Colors.white54,
                  side: BorderSide(color: data.pas == level ? Colors.lightBlueAccent : Colors.white24),
                ),
                child: Text('$level'),
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
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
            Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
