import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class PowerService extends ChangeNotifier {
  static const _cpSvcUuid  = '00001818-0000-1000-8000-00805f9b34fb';
  static const _cpMeasUuid = '00002a63-0000-1000-8000-00805f9b34fb';

  int? watts;
  double? cadenceRpm;
  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  String? deviceName;
  String? connectError;
  List<BluetoothDevice> scanResults = [];

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  int? _prevCrankRevs;
  int? _prevCrankTime;

  void startScan() {
    if (scanning) return;
    scanResults.clear();
    scanning = true;
    notifyListeners();

    FlutterBluePlus.startScan(
      withServices: [Guid(_cpSvcUuid)],
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
        watts = null;
        cadenceRpm = null;
        deviceName = null;
        _device = null;
        _prevCrankRevs = null;
        _prevCrankTime = null;
        notifyListeners();
      }
    });

    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        final svcId = svc.uuid.toString().toLowerCase();
        if (svcId == _cpSvcUuid || svcId == '1818') {
          for (final c in svc.characteristics) {
            final cId = c.uuid.toString().toLowerCase();
            if (cId == _cpMeasUuid || cId == '2a63') {
              await c.setNotifyValue(true);
              _notifySub = c.onValueReceived.listen(_onPowerData);
              connected = true;
              connecting = false;
              notifyListeners();
              return;
            }
          }
        }
      }
      connectError = 'Cycling Power service not found on device';
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
    watts = null;
    cadenceRpm = null;
    deviceName = null;
    _prevCrankRevs = null;
    _prevCrankTime = null;
  }

  void _onPowerData(List<int> data) {
    if (data.length < 4) return;

    // Flags: uint16 little-endian
    final flags = data[0] | (data[1] << 8);

    // Instantaneous power: sint16 at bytes 2-3
    int raw = data[2] | (data[3] << 8);
    if (raw >= 0x8000) raw -= 0x10000; // sign-extend
    watts = raw;

    // Walk optional fields to find crank rev data (flag bit 5)
    int offset = 4;
    if (flags & (1 << 0) != 0) offset += 1; // Pedal Power Balance
    // bit 1 is just a flag value, no extra bytes
    if (flags & (1 << 2) != 0) offset += 2; // Accumulated Torque
    if (flags & (1 << 4) != 0) offset += 6; // Wheel Rev Data (4+2)
    // Crank Rev Data: bit 5
    if (flags & (1 << 5) != 0 && data.length >= offset + 4) {
      final crankRevs = data[offset] | (data[offset + 1] << 8);
      final crankTime = data[offset + 2] | (data[offset + 3] << 8);
      if (_prevCrankRevs != null && _prevCrankTime != null) {
        final deltaRevs = (crankRevs - _prevCrankRevs!) & 0xFFFF;
        final deltaTime = (crankTime - _prevCrankTime!) & 0xFFFF;
        if (deltaTime > 0) {
          final rpm = (deltaRevs / (deltaTime / 1024.0)) * 60.0;
          cadenceRpm = rpm.clamp(0, 300);
        }
      }
      _prevCrankRevs = crankRevs;
      _prevCrankTime = crankTime;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}
