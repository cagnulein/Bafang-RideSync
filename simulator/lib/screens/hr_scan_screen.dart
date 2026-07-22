import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/hr_service.dart';

class HrScanScreen extends StatefulWidget {
  const HrScanScreen({super.key});

  @override
  State<HrScanScreen> createState() => _HrScanScreenState();
}

class _HrScanScreenState extends State<HrScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HrService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HrService>(builder: (context, hr, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Heart Rate Monitor',
              style: TextStyle(fontFamily: 'Courier')),
          actions: [
            if (hr.connected)
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
                tooltip: 'Disconnect',
                onPressed: () {
                  hr.disconnect();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (hr.connected) ...[
              _connectedCard(hr),
            ] else ...[
              Row(
                children: [
                  Text(
                    hr.scanning ? 'Scanning…' : 'Not scanning',
                    style: const TextStyle(
                        color: Colors.white54, fontFamily: 'Courier'),
                  ),
                  const SizedBox(width: 12),
                  if (hr.scanning)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 16),
              if (!hr.scanning)
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan'),
                  onPressed: hr.startScan,
                ),
              const SizedBox(height: 16),
              if (hr.connectError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Error: ${hr.connectError}',
                    style: const TextStyle(color: Colors.redAccent, fontFamily: 'Courier', fontSize: 12),
                  ),
                ),
              ...hr.scanResults.map((d) {
                final isConnecting = hr.connecting && hr.deviceName == d.platformName;
                return ListTile(
                  tileColor: const Color(0xFF1a1a1a),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  leading: isConnecting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                      : const Icon(Icons.favorite, color: Colors.redAccent),
                  title: Text(
                    d.platformName.isEmpty ? d.remoteId.str : d.platformName,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Courier'),
                  ),
                  subtitle: Text(d.remoteId.str,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontFamily: 'Courier',
                          fontSize: 11)),
                  onTap: hr.connecting ? null : () => hr.connect(d),
                );
              }),
            ],
          ],
        ),
      );
    });
  }

  Widget _connectedCard(HrService hr) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.favorite, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(hr.deviceName ?? 'Connected',
                style: const TextStyle(
                    color: Colors.redAccent, fontFamily: 'Courier')),
          ]),
          const SizedBox(height: 12),
          Text(
            '${hr.bpm ?? '--'} bpm',
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Courier',
                fontSize: 48,
                fontWeight: FontWeight.bold),
          ),
        ]),
      );
}
