using Toybox.BluetoothLowEnergy as Ble;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// BLE event delegate for the EKD01-BF display.
//
// State machine:
//   IDLE -> SCANNING -> CONNECTING -> ENABLING_NOTIFY
//        -> INIT_1..6 (init sequence frames)
//        -> TIME_SYNC_1..3 (3 register writes)
//        -> RUNNING (parse telemetry)
//   Any disconnection -> back to SCANNING
class BafangBleDelegate extends Ble.BleDelegate {

    // ── State constants ───────────────────────────────────────────────────
    enum InitState {
        STATE_IDLE            = 0,
        STATE_SCANNING        = 1,
        STATE_CONNECTING      = 2,
        STATE_ENABLING_NOTIFY = 3,
        STATE_INIT_1          = 4,   // status request to controller
        STATE_INIT_2          = 5,   // handshake blob
        STATE_INIT_3          = 6,   // read model string
        STATE_INIT_4          = 7,   // read secondary config
        STATE_INIT_5          = 8,   // set config a5/e1
        STATE_INIT_6          = 9,   // read config a5/e0
        STATE_TIME_SYNC_1     = 10,  // write reg 0x3e (local epoch)
        STATE_TIME_SYNC_2     = 11,  // write reg 0x42 (tz offset)
        STATE_TIME_SYNC_3     = 12,  // write reg 0x46 (utc epoch)
        STATE_RUNNING         = 13,
        STATE_ERROR           = 14
    }

    // ── UUIDs ─────────────────────────────────────────────────────────────
    // Service: 7dfc9000-7d1c-4951-86aa-8d9728f8d66c
    // TX char (phone -> bike): 6e400002-b5a3-f393-e0a9-e50e24dcca9e
    // RX char (bike -> phone, notify): 6e400003-b5a3-f393-e0a9-e50e24dcca9e
    static const SERVICE_UUID = "7dfc9000-7d1c-4951-86aa-8d9728f8d66c";
    static const TX_UUID      = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
    static const RX_UUID      = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
    static const DEVICE_NAME  = "EKD01-BF";

    private var _state     as Number      = STATE_IDLE;
    private var _device    as Ble.Device? = null;
    private var _txChar    as Ble.Characteristic? = null;
    private var _rxChar    as Ble.Characteristic? = null;

    // For periodic time re-sync (every 5 minutes during RUNNING)
    private var _lastSync  as Number = 0;

    function initialize() {
        BleDelegate.initialize();
        _registerProfile();
    }

    // ── Profile registration ──────────────────────────────────────────────

    private function _registerProfile() as Void {
        try {
            Ble.registerProfile({
                :uuid => Ble.stringToUuid(SERVICE_UUID),
                :characteristics => [
                    { :uuid => Ble.stringToUuid(TX_UUID) },
                    { :uuid => Ble.stringToUuid(RX_UUID),
                      :descriptors => [Ble.cccdUuid()] }
                ]
            });
        } catch (ex instanceof Lang.Exception) {
            System.println("BLE registerProfile error: " + ex.getErrorMessage());
        }
    }

    // Called by the View to start scanning (or direct-connect if DIRECT_CONNECT).
    function startScan() as Void {
        if (_state != STATE_IDLE && _state != STATE_ERROR) { return; }
        if (BafangRideSyncApp.DIRECT_CONNECT && _tryConnectBonded()) { return; }
        _setState(STATE_SCANNING);
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    // Try to connect directly using a previously bonded ScanResult by address.
    // Returns true if the device was found and pairDevice() was called.
    private function _tryConnectBonded() as Boolean {
        var iter = Ble.getBondedDevices();
        var item = iter.next();
        while (item != null) {
            var sr = item as Ble.ScanResult;
            if (sr.hasAddress(BafangRideSyncApp.DIRECT_CONNECT_ADDRESS)) {
                _setState(STATE_CONNECTING);
                BafangRideSyncApp.getData().bleStatus = "BOND";
                Ble.pairDevice(sr);
                return true;
            }
            item = iter.next();
        }
        return false;
    }

    // ── BLE callbacks ─────────────────────────────────────────────────────

    function onScanResults(scanResults as Ble.Iterator) as Void {
        var result = scanResults.next();
        while (result != null) {
            var scanResult = result as Ble.ScanResult;
            var match = BafangRideSyncApp.DIRECT_CONNECT
                ? scanResult.hasAddress(BafangRideSyncApp.DIRECT_CONNECT_ADDRESS)
                : (scanResult.getDeviceName() != null &&
                   (scanResult.getDeviceName() as String).find(DEVICE_NAME) != null);
            if (match) {
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                _setState(STATE_CONNECTING);
                Ble.pairDevice(scanResult);
                return;
            }
            result = scanResults.next();
        }
    }

    function onConnectedStateChanged(device as Ble.Device, state as Ble.ConnectionState) as Void {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            _device = device;
            BafangRideSyncApp.getData().bleConnected = true;
            BafangRideSyncApp.getData().bleStatus    = "CONN";
            _setState(STATE_ENABLING_NOTIFY);
            _enableNotify();
        } else {
            _device    = null;
            _txChar    = null;
            _rxChar    = null;
            BafangRideSyncApp.getData().bleConnected = false;
            BafangRideSyncApp.getData().bleStatus    = "SCAN";
            _setState(STATE_IDLE);
            // Auto-restart scan after disconnect
            startScan();
        }
    }

    private function _enableNotify() as Void {
        if (_device == null) { return; }
        var svc = (_device as Ble.Device).getService(Ble.stringToUuid(SERVICE_UUID));
        if (svc == null) { _setState(STATE_ERROR); return; }
        _txChar = svc.getCharacteristic(Ble.stringToUuid(TX_UUID));
        _rxChar = svc.getCharacteristic(Ble.stringToUuid(RX_UUID));
        if (_rxChar == null || _txChar == null) { _setState(STATE_ERROR); return; }
        var cccd = (_rxChar as Ble.Characteristic).getDescriptor(Ble.cccdUuid());
        if (cccd == null) { _setState(STATE_ERROR); return; }
        cccd.requestWrite([0x01, 0x00]b);
    }

    function onDescriptorWrite(descriptor as Ble.Descriptor, status as Ble.Status) as Void {
        if (status != Ble.STATUS_SUCCESS) {
            _setState(STATE_ERROR);
            return;
        }
        // CCCD enabled – start init
        BafangRideSyncApp.getData().bleStatus = "INIT";
        _setState(STATE_INIT_1);
        _sendFrame(FrameBuilder.initSequence()[0]);
    }

    // Called on write-with-response completion (TX writes).
    // We don't need to do anything here; the device's NOTIFY response drives
    // the state machine via onCharacteristicChanged.
    function onCharacteristicWrite(characteristic as Ble.Characteristic,
                                   status as Ble.Status) as Void {
        // No-op: state advances on RX notify.
    }

    // Main receive path – all device->phone traffic comes here.
    function onCharacteristicChanged(characteristic as Ble.Characteristic,
                                     value as Lang.ByteArray) as Void {
        var d = BafangRideSyncApp.getData();
        d.noteRx(value);
        var frame = FrameParser.parse(value);
        if (frame == null) {
            d.noteParseError(FrameParser.errorCode(value));
            return;
        }
        d.noteFrame(frame);

        if (_state == STATE_RUNNING) {
            _handleTelemetry(frame);
            return;
        }
        _handleInitResponse(frame);
    }

    // ── Init state machine ────────────────────────────────────────────────

    private function _handleInitResponse(frame as ParsedFrame) as Void {
        var initFrames = FrameBuilder.initSequence();
        switch (_state) {
            case STATE_INIT_1:
                // Expect OP=0x04 from DST_CTRL
                if (frame.op == 0x04 && frame.src == FrameBuilder.DST_CTRL) {
                    _setState(STATE_INIT_2);
                    _sendFrame(initFrames[1]);
                }
                break;
            case STATE_INIT_2:
                // Expect OP=0x20 ACK from DST_CTRL
                if (frame.op == 0x20 && frame.src == FrameBuilder.DST_CTRL) {
                    _setState(STATE_INIT_3);
                    _sendFrame(initFrames[2]);
                }
                break;
            case STATE_INIT_3:
                // Expect OP=0x04 REG=0x18 from DST_CFG (model string)
                if (frame.op == 0x04 && frame.src == FrameBuilder.DST_CFG
                        && frame.reg == 0x18) {
                    _parseModel(frame.data);
                    _setState(STATE_INIT_4);
                    _sendFrame(initFrames[3]);
                }
                break;
            case STATE_INIT_4:
                // Expect OP=0x04 REG=0x01 from DST_CFG2
                if (frame.op == 0x04 && frame.src == FrameBuilder.DST_CFG2) {
                    _setState(STATE_INIT_5);
                    _sendFrame(initFrames[4]);
                }
                break;
            case STATE_INIT_5:
                // Expect OP=0x05 ACK for set config (from DST_CFG)
                if (frame.op == 0x05 && frame.src == FrameBuilder.DST_CFG) {
                    _setState(STATE_INIT_6);
                    _sendFrame(initFrames[5]);
                }
                break;
            case STATE_INIT_6:
                // Expect OP=0x04 REG=0xe0 from DST_CFG
                if (frame.op == 0x04 && frame.src == FrameBuilder.DST_CFG) {
                    _startTimeSync();
                }
                break;
            case STATE_TIME_SYNC_1:
                // ACK for reg 0x3e
                if (frame.op == 0x05 && frame.src == FrameBuilder.DST_CTRL
                        && frame.reg == FrameBuilder.REG_LOCAL_EPOCH) {
                    _setState(STATE_TIME_SYNC_2);
                    _sendTimeSyncFrame2();
                }
                break;
            case STATE_TIME_SYNC_2:
                // ACK for reg 0x42
                if (frame.op == 0x05 && frame.src == FrameBuilder.DST_CTRL
                        && frame.reg == FrameBuilder.REG_TZ_OFFSET) {
                    _setState(STATE_TIME_SYNC_3);
                    _sendTimeSyncFrame3();
                }
                break;
            case STATE_TIME_SYNC_3:
                // ACK for reg 0x46
                if (frame.op == 0x05 && frame.src == FrameBuilder.DST_CTRL
                        && frame.reg == FrameBuilder.REG_UTC_EPOCH) {
                    _setState(STATE_RUNNING);
                    BafangRideSyncApp.getData().bleStatus = "OK";
                    _lastSync = Time.now().value();
                }
                break;
            default:
                break;
        }
    }

    // ── Telemetry parsing ─────────────────────────────────────────────────

    private function _handleTelemetry(frame as ParsedFrame) as Void {
        var d = BafangRideSyncApp.getData();
        if (frame.op == 0x06) {
            if (frame.reg == 0x01) {
                d.update0601(frame.data);
            } else if (frame.reg == 0x09) {
                d.update0609(frame.data);
            }
        }
        // Periodic time re-sync every 300 seconds (5 minutes)
        var now = Time.now().value();
        if (now - _lastSync > 300) {
            _lastSync = now;
            _startTimeSync();
        }
    }

    // ── Time sync ─────────────────────────────────────────────────────────

    private var _tzCache   as Number = 0;
    private var _utcCache  as Number = 0;

    // Time.now().value() uses the Garmin epoch (1990-01-01).
    // The Bafang controller expects Unix timestamps (epoch 1970-01-01).
    // Offset = 7305 days * 86400 s/day = 631,152,000 s
    private const GARMIN_TO_UNIX as Number = 631152000;

    private function _computeTimeValues() as Void {
        _utcCache = Time.now().value() + GARMIN_TO_UNIX;
        var clock = System.getClockTime();
        var localSec = clock.hour * 3600 + clock.min * 60 + clock.sec;
        var utcSec   = _utcCache % 86400;
        _tzCache = localSec - utcSec;
        if (_tzCache >  43200) { _tzCache -= 86400; }
        if (_tzCache < -43200) { _tzCache += 86400; }
    }

    private function _startTimeSync() as Void {
        _computeTimeValues();
        _setState(STATE_TIME_SYNC_1);
        _sendFrame(FrameBuilder.writeU32(FrameBuilder.DST_CTRL,
                                         FrameBuilder.REG_LOCAL_EPOCH,
                                         _utcCache - _tzCache));
    }

    private function _sendTimeSyncFrame2() as Void {
        _sendFrame(FrameBuilder.writeU32(FrameBuilder.DST_CTRL,
                                         FrameBuilder.REG_TZ_OFFSET,
                                         _tzCache));
    }

    private function _sendTimeSyncFrame3() as Void {
        _sendFrame(FrameBuilder.writeU32(FrameBuilder.DST_CTRL,
                                         FrameBuilder.REG_UTC_EPOCH,
                                         _utcCache));
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private function _sendFrame(frame as Lang.ByteArray) as Void {
        if (_txChar == null) { return; }
        try {
            (_txChar as Ble.Characteristic).requestWrite(frame,
                {:writeType => Ble.WRITE_TYPE_DEFAULT});
        } catch (ex instanceof Lang.Exception) {
            System.println("BLE write error: " + ex.getErrorMessage());
        }
    }

    private function _setState(s as Number) as Void {
        _state = s;
        var d = BafangRideSyncApp.getData();
        d.bleState = s;
        switch (s) {
            case STATE_IDLE:
                d.bleStatus = "IDLE";
                break;
            case STATE_SCANNING:
                d.bleStatus = "SCAN";
                break;
            case STATE_CONNECTING:
                d.bleStatus = "CONN";
                break;
            case STATE_ENABLING_NOTIFY:
                d.bleStatus = "NTFY";
                break;
            case STATE_INIT_1:
                d.bleStatus = "I1";
                break;
            case STATE_INIT_2:
                d.bleStatus = "I2";
                break;
            case STATE_INIT_3:
                d.bleStatus = "I3";
                break;
            case STATE_INIT_4:
                d.bleStatus = "I4";
                break;
            case STATE_INIT_5:
                d.bleStatus = "I5";
                break;
            case STATE_INIT_6:
                d.bleStatus = "I6";
                break;
            case STATE_TIME_SYNC_1:
                d.bleStatus = "T1";
                break;
            case STATE_TIME_SYNC_2:
                d.bleStatus = "T2";
                break;
            case STATE_TIME_SYNC_3:
                d.bleStatus = "T3";
                break;
            case STATE_RUNNING:
                d.bleStatus = "OK";
                break;
            case STATE_ERROR:
                d.bleStatus = "ERR";
                break;
            default:
                break;
        }
    }

    private function _parseModel(data as Lang.ByteArray) as Void {
        // Model is a null-terminated ASCII string.
        var str = "";
        for (var i = 0; i < data.size(); i++) {
            var b = data[i];
            if (b == 0) { break; }
            str = str + b.toChar().toString();
        }
        BafangRideSyncApp.getData().model = str;
    }

    function getState() as Number { return _state; }
}
