import Toybox.Lang;

// Shared state between BleDelegate (writer) and View (reader).
//
// FIT field layout (decoded bike telemetry, all MESG_TYPE_RECORD):
//
//  ID  Name       Type    Units  Source
//  0   ebatt      u8      %      06 01 DATA[7]
//  1   epas       u8             06 01 DATA[5]
//  2   epasmax    u8             06 01 DATA[6]
//  3   espd       float   km/h   06 01 DATA[9..10] / 100
//  4   etrip      float   km     06 01 DATA[11..14] / 100
//  5   eodo       float   km     06 01 DATA[15..18] / 100
//  6   etick      u16            06 09 DATA[0..1]
//  7   ewheel     u16     mm     06 09 DATA[4..5], candidate wheel config
//  8   dbg        u32            parser/connection diagnostics
//  9   wstate     u8             workout probe state
//  10  wtype      u8             workout target type
//  11  wlow       u16            workout target low, raw Garmin/FIT value
//  12  whigh      u16            workout target high, raw Garmin/FIT value
//  13  whrlow     u8      bpm    normalized HR target low when target is HR
//  14  whrhigh    u8      bpm    normalized HR target high when target is HR
//
class BafangData {

    // Raw DATA bytes from the last received telemetry frames.
    var raw0601 as Lang.ByteArray? = null;   // 21 bytes
    var raw0609 as Lang.ByteArray? = null;   // 16 bytes

    // Decoded values for on-screen display (always up-to-date when raw* != null).
    var battery    as Number? = null;   // % (DATA[7])            CONFIRMED
    var pas        as Number? = null;   // assist level (DATA[5]) CONFIRMED
    var pasMax     as Number? = null;   // max assist level candidate (DATA[6])
    var speedKmh   as Float?  = null;   // km/h                   CONFIRMED
    var tripKm     as Float?  = null;   // km                     CONFIRMED
    var odometerKm as Float?  = null;   // km                     CONFIRMED
    var tickCounter as Number? = null;  // 06 09 DATA[0..1]       PROBABLE
    var wheelCfg    as Number? = null;  // 06 09 DATA[4..5]       CANDIDATE

    // Session metadata
    var model        as String  = "--";
    var bleConnected as Boolean = false;
    var bleStatus    as String  = "SCAN";  // SCAN / CONN / INIT / OK / ERR

    // Diagnostics persisted to FIT on every activity record. These are useful
    // on real devices where System.println is not available after the ride.
    var bleState          as Number = 0;
    var rxCount           as Number = 0;
    var validFrameCount   as Number = 0;
    var parseErrorCount   as Number = 0;
    var lastParseError    as Number = 0;
    var lastRxSize        as Number = 0;
    var lastFrameSrc      as Number = 0;
    var lastFrameDst      as Number = 0;
    var lastFrameOp       as Number = 0;
    var lastFrameReg      as Number = 0;
    var telemetry0601Count as Number = 0;
    var telemetry0609Count as Number = 0;

    // Workout probe. Garmin sometimes exposes current workout target data from
    // a DataField despite the public docs saying otherwise; keep both raw and
    // normalized values visible so the real device/simulator tells us the truth.
    var workoutState as Number = 0;           // 0 unsupported, 1 none, 2 active, 3 error
    var workoutErrorCount as Number = 0;
    var workoutTargetType as Number? = null;
    var workoutTargetLowRaw as Number? = null;
    var workoutTargetHighRaw as Number? = null;
    var workoutDurationType as Number? = null;
    var workoutDurationValue as Number? = null;
    var workoutHrLow as Number? = null;
    var workoutHrHigh as Number? = null;

    function initialize() {}

    // Feed static frames captured from a real ride for Simulator testing.
    // Values: battery=81%, PAS=1, speed=41.27 km/h, trip=115.80 km, odo=282.18 km
    function injectSimFrames() as Void {
        // 06 01 DATA bytes (21 bytes) – pedaling capture, checksums verified
        update0601([0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x09, 0x51,
                    0x00, 0x1f, 0x10, 0x3c, 0x2d, 0x00, 0x00, 0x3a,
                    0x6e, 0x00, 0x00, 0x00, 0x00]b);
        // 06 09 DATA bytes (16 bytes) – tick=0x51fd, wheel config candidate=1985
        update0609([0xfd, 0x51, 0x00, 0x00, 0xc1, 0x07, 0x5a, 0x11,
                    0x18, 0x01, 0xde, 0x03, 0x55, 0x00, 0x01, 0x05]b);
        model        = "EKD01_CAN_BF_N22";
        bleConnected = true;
        bleStatus    = "SIM";
    }

    // Update from a 06 01 DATA block (must be >= 21 bytes).
    function update0601(data as Lang.ByteArray) as Void {
        if (data.size() < 21) { return; }
        telemetry0601Count++;
        raw0601    = data;
        pas        = data[5];
        pasMax     = data[6];
        battery    = data[7];
        speedKmh   = FrameParser.u16le(data, 9).toFloat()  / 100.0;
        tripKm     = FrameParser.u32le(data, 11).toFloat() / 100.0;
        odometerKm = FrameParser.u32le(data, 15).toFloat() / 100.0;
    }

    // Update from a 06 09 DATA block (must be >= 16 bytes).
    function update0609(data as Lang.ByteArray) as Void {
        if (data.size() < 16) { return; }
        telemetry0609Count++;
        raw0609 = data;
        tickCounter = FrameParser.u16le(data, 0);
        wheelCfg = FrameParser.u16le(data, 4);
    }

    function noteWorkoutUnsupported() as Void {
        workoutState = 0;
        _clearWorkoutTarget();
    }

    function noteWorkoutMissing() as Void {
        workoutState = 1;
        _clearWorkoutTarget();
    }

    function noteWorkoutError() as Void {
        workoutState = 3;
        workoutErrorCount++;
        _clearWorkoutTarget();
    }

    function updateWorkoutTarget(targetType as Number?,
                                 lowRaw as Number?,
                                 highRaw as Number?,
                                 durationType as Number?,
                                 durationValue as Number?,
                                 isHeartRate as Boolean) as Void {
        workoutState = 2;
        workoutTargetType = targetType;
        workoutTargetLowRaw = lowRaw;
        workoutTargetHighRaw = highRaw;
        workoutDurationType = durationType;
        workoutDurationValue = durationValue;
        if (isHeartRate) {
            workoutHrLow = _normalizeHrTarget(lowRaw);
            workoutHrHigh = _normalizeHrTarget(highRaw);
        } else {
            workoutHrLow = null;
            workoutHrHigh = null;
        }
    }

    function noteRx(bytes as Lang.ByteArray) as Void {
        rxCount++;
        lastRxSize = bytes.size();
    }

    function noteParseError(errorCode as Number) as Void {
        parseErrorCount++;
        lastParseError = errorCode;
    }

    function noteFrame(frame as ParsedFrame) as Void {
        validFrameCount++;
        lastParseError = 0;
        lastFrameSrc = frame.src;
        lastFrameDst = frame.dst;
        lastFrameOp  = frame.op;
        lastFrameReg = frame.reg;
    }

    function lastFramePacked() as Number {
        return (lastFrameSrc & 0xff)
             | ((lastFrameDst & 0xff) << 8)
             | ((lastFrameOp  & 0xff) << 16)
             | ((lastFrameReg & 0xff) << 24);
    }

    function diagFlags() as Number {
        return (bleConnected ? 1 : 0)
             | ((lastParseError & 0xff) << 8)
             | ((lastRxSize & 0xffff) << 16);
    }

    function diagStatusPacked() as Number {
        return (bleConnected ? 1 : 0)
             | ((lastParseError & 0xff) << 8)
             | ((bleState & 0xff) << 16)
             | ((lastRxSize & 0xff) << 24);
    }

    function diagCountsPacked() as Number {
        return (rxCount & 0xffff)
             | ((validFrameCount & 0xffff) << 16);
    }

    private function _clearWorkoutTarget() as Void {
        workoutTargetType = null;
        workoutTargetLowRaw = null;
        workoutTargetHighRaw = null;
        workoutDurationType = null;
        workoutDurationValue = null;
        workoutHrLow = null;
        workoutHrHigh = null;
    }

    private function _normalizeHrTarget(value as Number?) as Number? {
        if (value == null) { return null; }
        var v = value as Number;
        if (v > 100) { v -= 100; }
        if (v < 0) { return null; }
        if (v > 255) { return 255; }
        return v;
    }

}
