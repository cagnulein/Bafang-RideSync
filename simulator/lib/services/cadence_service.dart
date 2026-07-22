import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class CadenceService extends ChangeNotifier {
  static const _cscSvcUuid  = '00001816-0000-1000-8000-00805f9b34fb';
  static const _cscMeasUuid = '00002a5b-0000-1000-8000-00805f9b34fb';

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

  // Previous crank revolution data for RPM calculation
  int? _prevCrankRevs;
  int? _prevCrankTime; // 1/1024 s units

  void startScan() {
    if (scanning) return;
    scanResults.clear();
    scanning = true;
    notifyListeners();

    FlutterBluePlus.startScan(
      withServices: [Guid(_cscSvcUuid)],
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
        if (svcId == _cscSvcUuid || svcId == '1816') {
          for (final c in svc.characteristics) {
            final cId = c.uuid.toString().toLowerCase();
            if (cId == _cscMeasUuid || cId == '2a5b') {
              await c.setNotifyValue(true);
              _notifySub = c.onValueReceived.listen(_onCscData);
              connected = true;
              connecting = false;
              notifyListeners();
              return;
            }
          }
        }
      }
      connectError = 'CSC service not found on device';
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
    cadenceRpm = null;
    deviceName = null;
    _prevCrankRevs = null;
    _prevCrankTime = null;
  }

  void _onCscData(List<int> data) {
    if (data.isEmpty) return;
    final flags = data[0];
    final wheelPresent = flags & 0x01 != 0;
    final crankPresent = flags & 0x02 != 0;
    if (!crankPresent) return;

    // Skip wheel revolution data if present (4 bytes revs + 2 bytes time)
    int offset = 1 + (wheelPresent ? 6 : 0);
    if (data.length < offset + 4) return;

    final crankRevs = data[offset] | (data[offset + 1] << 8);
    final crankTime = data[offset + 2] | (data[offset + 3] << 8);

    if (_prevCrankRevs != null && _prevCrankTime != null) {
      final deltaRevs = (crankRevs - _prevCrankRevs!) & 0xFFFF;
      var deltaTime = (crankTime - _prevCrankTime!) & 0xFFFF; // 1/1024 s
      if (deltaTime > 0 && deltaRevs >= 0) {
        final rpm = (deltaRevs / (deltaTime / 1024.0)) * 60.0;
        cadenceRpm = rpm.clamp(0, 300);
        notifyListeners();
      }
    }

    _prevCrankRevs = crankRevs;
    _prevCrankTime = crankTime;
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}
