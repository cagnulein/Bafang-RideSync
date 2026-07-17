import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bafang_data.dart';
import 'frame_builder.dart';
import 'frame_parser.dart';

enum BleState {
  idle, scanning, connecting, enablingNotify,
  init1, init2, init3, init4, init5, init6,
  timeSync1, timeSync2, timeSync3,
  running, error,
}

class BleService {
  static const String _serviceUuid = '7dfc9000-7d1c-4951-86aa-8d9728f8d66c';
  static const String _txUuid      = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _rxUuid      = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _deviceName  = 'EKD01-BF';

  final BafangData data;

  BleState _state = BleState.idle;
  BluetoothDevice?        _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;

  int _lastSync = 0;
  int _tzCache  = 0;
  int _utcCache = 0;

  StreamSubscription<List<ScanResult>>?           _scanSub;
  StreamSubscription<List<int>>?                  _rxSub;
  StreamSubscription<BluetoothConnectionState>?   _connSub;

  // Log for the debug pane (newest first, capped at 200 lines)
  final List<String> log = [];

  BleService(this.data);

  // ── Public API ────────────────────────────────────────────────────────────

  BleState get state => _state;

  void startScan() {
    if (_state != BleState.idle && _state != BleState.error) return;
    _log('Scanning for $_deviceName…');
    _setState(BleState.scanning, status: 'SCAN');

    FlutterBluePlus.startScan(
      withServices: [Guid(_serviceUuid)],
      timeout: const Duration(seconds: 30),
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name.contains(_deviceName) ||
            r.advertisementData.advName.contains(_deviceName)) {
          FlutterBluePlus.stopScan();
          _scanSub?.cancel();
          _connect(r.device);
          return;
        }
      }
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _setState(BleState.idle, status: 'IDLE');
  }

  void dispose() {
    _scanSub?.cancel();
    _rxSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
  }

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> _connect(BluetoothDevice device) async {
    _log('Found device: ${device.platformName} – connecting…');
    _setState(BleState.connecting, status: 'CONN');
    _device = device;

    _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _handleDisconnect();
    });

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
    } catch (e) {
      _log('Connect error: $e');
      _setState(BleState.error, status: 'ERR');
      return;
    }
    await _enableNotify();
  }

  Future<void> _enableNotify() async {
    _setState(BleState.enablingNotify, status: 'INIT');
    _log('Discovering services…');

    List<BluetoothService> services;
    try {
      services = await _device!.discoverServices();
    } catch (e) {
      _log('discoverServices error: $e');
      _setState(BleState.error, status: 'ERR');
      return;
    }

    BluetoothService? svc;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == _serviceUuid) { svc = s; break; }
    }
    if (svc == null) {
      _log('Service $_serviceUuid not found');
      _setState(BleState.error, status: 'ERR');
      return;
    }

    for (final c in svc.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid == _txUuid) _txChar = c;
      if (uuid == _rxUuid) _rxChar = c;
    }
    if (_txChar == null || _rxChar == null) {
      _log('TX/RX characteristics not found');
      _setState(BleState.error, status: 'ERR');
      return;
    }

    await _rxChar!.setNotifyValue(true);
    _rxSub?.cancel();
    _rxSub = _rxChar!.onValueReceived.listen(_onRx);

    _log('Notifications enabled – starting init sequence');
    _setState(BleState.init1);
    await _sendFrame(FrameBuilder.initSequence()[0]);
  }

  // ── Receive dispatch ──────────────────────────────────────────────────────

  void _onRx(List<int> value) {
    final bytes = Uint8List.fromList(value);
    final hex   = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _log('RX [$_stateLabel]: $hex');

    final frame = FrameParser.parse(bytes);
    if (frame == null) { _log('  → parse failed'); return; }

    if (_state == BleState.running) {
      _handleTelemetry(frame);
    } else {
      _handleInitResponse(frame);
    }
  }

  // ── Init state machine ────────────────────────────────────────────────────

  Future<void> _handleInitResponse(ParsedFrame frame) async {
    final frames = FrameBuilder.initSequence();
    switch (_state) {
      case BleState.init1:
        if (frame.op == 0x04 && frame.src == FrameBuilder.dstCtrl) {
          _setState(BleState.init2);
          await _sendFrame(frames[1]);
        }
      case BleState.init2:
        if (frame.op == 0x20 && frame.src == FrameBuilder.dstCtrl) {
          _setState(BleState.init3);
          await _sendFrame(frames[2]);
        }
      case BleState.init3:
        if (frame.op == 0x04 && frame.src == FrameBuilder.dstCfg && frame.reg == 0x18) {
          _parseModel(frame.data);
          _setState(BleState.init4);
          await _sendFrame(frames[3]);
        }
      case BleState.init4:
        if (frame.op == 0x04 && frame.src == FrameBuilder.dstCfg2) {
          _setState(BleState.init5);
          await _sendFrame(frames[4]);
        }
      case BleState.init5:
        if (frame.op == 0x05 && frame.src == FrameBuilder.dstCfg) {
          _setState(BleState.init6);
          await _sendFrame(frames[5]);
        }
      case BleState.init6:
        if (frame.op == 0x04 && frame.src == FrameBuilder.dstCfg) {
          await _startTimeSync();
        }
      case BleState.timeSync1:
        if (frame.op == 0x05 && frame.src == FrameBuilder.dstCtrl &&
            frame.reg == FrameBuilder.regLocalEpoch) {
          _setState(BleState.timeSync2);
          await _sendFrame(FrameBuilder.writeU32(
              FrameBuilder.dstCtrl, FrameBuilder.regTzOffset, _tzCache));
        }
      case BleState.timeSync2:
        if (frame.op == 0x05 && frame.src == FrameBuilder.dstCtrl &&
            frame.reg == FrameBuilder.regTzOffset) {
          _setState(BleState.timeSync3);
          await _sendFrame(FrameBuilder.writeU32(
              FrameBuilder.dstCtrl, FrameBuilder.regUtcEpoch, _utcCache));
        }
      case BleState.timeSync3:
        if (frame.op == 0x05 && frame.src == FrameBuilder.dstCtrl &&
            frame.reg == FrameBuilder.regUtcEpoch) {
          _log('Init complete – RUNNING');
          data.bleConnected = true;
          data.bleStatus    = 'OK';
          _setState(BleState.running, status: 'OK');
          _lastSync = _nowSec();
        }
      default:
        break;
    }
  }

  // ── Telemetry ─────────────────────────────────────────────────────────────

  void _handleTelemetry(ParsedFrame frame) async {
    if (frame.op == 0x06) {
      if (frame.reg == 0x01) { data.update0601(frame.data); }
      else if (frame.reg == 0x09) { data.update0609(frame.data); }
    }
    // Periodic re-sync every 5 minutes (mirrors Garmin code)
    if (_nowSec() - _lastSync > 300) {
      _lastSync = _nowSec();
      await _startTimeSync();
    }
  }

  // ── Time sync (exact same logic as BafangBleDelegate.mc) ─────────────────

  void _computeTimeValues() {
    final now = DateTime.now();
    _utcCache = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    _tzCache  = now.timeZoneOffset.inSeconds;
  }

  Future<void> _startTimeSync() async {
    _computeTimeValues();
    _log('Time sync: utc=$_utcCache tz=$_tzCache');
    _setState(BleState.timeSync1);
    await _sendFrame(FrameBuilder.writeU32(
        FrameBuilder.dstCtrl, FrameBuilder.regLocalEpoch, _utcCache - _tzCache));
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  void _handleDisconnect() {
    _log('Disconnected');
    _rxSub?.cancel();
    _connSub?.cancel();
    _txChar = null;
    _rxChar = null;
    _device = null;
    data.bleConnected = false;
    data.bleStatus    = 'SCAN';
    _setState(BleState.idle, status: 'SCAN');
    Future.delayed(const Duration(seconds: 2), startScan);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _sendFrame(Uint8List frame) async {
    final hex = frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _log('TX [$_stateLabel]: $hex');
    if (_txChar == null) return;
    try {
      await _txChar!.write(frame, withoutResponse: false);
    } catch (e) {
      _log('TX error: $e');
    }
  }

  void _setState(BleState s, {String? status}) {
    _state = s;
    if (status != null) {
      data.bleStatus = status;
      data.notifyListeners();
    }
  }

  void _parseModel(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      if (b == 0) break;
      sb.writeCharCode(b);
    }
    data.model = sb.toString();
    _log('Model: ${data.model}');
    data.notifyListeners();
  }

  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    log.insert(0, '[$ts] $msg');
    if (log.length > 200) log.removeLast();
  }

  String get _stateLabel => _state.name;
  int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
