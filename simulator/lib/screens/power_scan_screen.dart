import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/power_service.dart';

class PowerScanScreen extends StatefulWidget {
  const PowerScanScreen({super.key});

  @override
  State<PowerScanScreen> createState() => _PowerScanScreenState();
}

class _PowerScanScreenState extends State<PowerScanScreen> {
  static const _accent = Colors.orangeAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PowerService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PowerService>(builder: (context, pwr, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Power Meter'),
          actions: [
            if (pwr.connected)
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
                tooltip: 'Disconnect',
                onPressed: () {
                  pwr.disconnect();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (pwr.connected)
              _connectedCard(pwr)
            else ...[
              Row(children: [
                Text(
                  pwr.scanning ? 'Scanning…' : 'Not scanning',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(width: 12),
                if (pwr.scanning)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
              ]),
              const SizedBox(height: 16),
              if (!pwr.scanning)
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan'),
                  onPressed: pwr.startScan,
                ),
              const SizedBox(height: 16),
              if (pwr.connectError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Error: ${pwr.connectError}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ...pwr.scanResults.map((d) {
                final isConnecting = pwr.connecting && pwr.deviceName == d.platformName;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    tileColor: const Color(0xFF1a1a1a),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    leading: isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                        : const Icon(Icons.bolt, color: _accent),
                    title: Text(
                      d.platformName.isEmpty ? d.remoteId.str : d.platformName,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(d.remoteId.str,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    onTap: pwr.connecting ? null : () => pwr.connect(d),
                  ),
                );
              }),
            ],
          ],
        ),
      );
    });
  }

  Widget _connectedCard(PowerService pwr) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt, color: _accent),
            const SizedBox(width: 8),
            Text(pwr.deviceName ?? 'Connected',
                style: const TextStyle(color: _accent)),
          ]),
          const SizedBox(height: 12),
          Text(
            pwr.watts != null ? '${pwr.watts} W' : '-- W',
            style: const TextStyle(
                color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
          ),
          if (pwr.cadenceRpm != null) ...[
            const SizedBox(height: 8),
            Text(
              '${pwr.cadenceRpm!.toStringAsFixed(0)} rpm',
              style: const TextStyle(color: Colors.white60, fontSize: 22),
            ),
          ],
        ]),
      );
}
