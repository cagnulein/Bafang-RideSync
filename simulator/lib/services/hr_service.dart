import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HrService extends ChangeNotifier {
  static const String _hrServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String _hrMeasUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  int? bpm;
  bool scanning = false;
  bool connected = false;
  String? deviceName;

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  List<BluetoothDevice> scanResults = [];

  void startScan() {
    if (scanning) return;
    scanResults.clear();
    scanning = true;
    notifyListeners();

    FlutterBluePlus.startScan(
      withServices: [Guid(_hrServiceUuid)],
      timeout: const Duration(seconds: 15),
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results.map((r) => r.device).toList();
      notifyListeners();
    });

    FlutterBluePlus.isScanning.listen((active) {
      if (!active && scanning) {
        scanning = false;
        notifyListeners();
      }
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    scanning = false;
    notifyListeners();
  }

  bool connecting = false;
  String? connectError;

  Future<void> connect(BluetoothDevice device) async {
    if (connecting) return;
    stopScan();
    _disconnect();

    connecting = true;
    connectError = null;
    _device = device;
    deviceName = device.platformName;
    notifyListeners();

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    } catch (e) {
      connecting = false;
      connectError = e.toString();
      _device = null;
      deviceName = null;
      notifyListeners();
      return;
    }

    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        connected = false;
        connecting = false;
        bpm = null;
        deviceName = null;
        _device = null;
        notifyListeners();
      }
    });

    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        final svcId = svc.uuid.toString().toLowerCase();
        if (svcId == _hrServiceUuid || svcId == '180d') {
          for (final c in svc.characteristics) {
            final cId = c.uuid.toString().toLowerCase();
            if (cId == _hrMeasUuid || cId == '2a37') {
              await c.setNotifyValue(true);
              _notifySub = c.onValueReceived.listen(_onHrData);
              connected = true;
              connecting = false;
              notifyListeners();
              return;
            }
          }
        }
      }
      connectError = 'HR service not found on device';
    } catch (e) {
      connectError = e.toString();
    }
    connecting = false;
    notifyListeners();
  }

  void disconnect() => _disconnect();

  void _disconnect() {
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    _device = null;
    connected = false;
    bpm = null;
    deviceName = null;
  }

  void _onHrData(List<int> value) {
    if (value.isEmpty) return;
    // Bluetooth HR measurement: flag byte + HR value (1 or 2 bytes)
    final flag = value[0];
    if (flag & 0x01 == 0) {
      // 8-bit HR value
      bpm = value.length > 1 ? value[1] : null;
    } else {
      // 16-bit HR value
      bpm = value.length > 2 ? (value[1] | (value[2] << 8)) : null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}
