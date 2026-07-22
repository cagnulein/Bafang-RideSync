import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/cadence_service.dart';

class CadenceScanScreen extends StatefulWidget {
  const CadenceScanScreen({super.key});

  @override
  State<CadenceScanScreen> createState() => _CadenceScanScreenState();
}

class _CadenceScanScreenState extends State<CadenceScanScreen> {
  static const _accent = Colors.cyanAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CadenceService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CadenceService>(builder: (context, cad, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Cadence Sensor'),
          actions: [
            if (cad.connected)
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
                tooltip: 'Disconnect',
                onPressed: () {
                  cad.disconnect();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (cad.connected)
              _connectedCard(cad)
            else ...[
              Row(children: [
                Text(
                  cad.scanning ? 'Scanning…' : 'Not scanning',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(width: 12),
                if (cad.scanning)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
              ]),
              const SizedBox(height: 16),
              if (!cad.scanning)
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan'),
                  onPressed: cad.startScan,
                ),
              const SizedBox(height: 16),
              if (cad.connectError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Error: ${cad.connectError}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ...cad.scanResults.map((d) {
                final isConnecting = cad.connecting && cad.deviceName == d.platformName;
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
                        : const Icon(Icons.rotate_right, color: _accent),
                    title: Text(
                      d.platformName.isEmpty ? d.remoteId.str : d.platformName,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(d.remoteId.str,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    onTap: cad.connecting ? null : () => cad.connect(d),
                  ),
                );
              }),
            ],
          ],
        ),
      );
    });
  }

  Widget _connectedCard(CadenceService cad) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.rotate_right, color: _accent),
            const SizedBox(width: 8),
            Text(cad.deviceName ?? 'Connected',
                style: const TextStyle(color: _accent)),
          ]),
          const SizedBox(height: 12),
          Text(
            cad.cadenceRpm != null
                ? '${cad.cadenceRpm!.toStringAsFixed(0)} rpm'
                : '-- rpm',
            style: const TextStyle(
                color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
          ),
        ]),
      );
}
