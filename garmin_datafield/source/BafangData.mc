import Toybox.Lang;

// Shared state between BleDelegate (writer) and View (reader).
//
// FIT field layout (8 total, all MESG_TYPE_RECORD, packed as u32 little-endian):
//
//  ID  Name       Covers                               Known decoded content
//  0   r01a u32   06 01  DATA[ 0.. 3]                 b3: mode/status flag (probabile)
//  1   r01b u32   06 01  DATA[ 4.. 7]                 b1: PAS level; b3: battery %
//  2   r01c u32   06 01  DATA[ 8..11]                 b1..2: speed u16LE /100 km/h; b3: trip LSB
//  3   r01d u32   06 01  DATA[12..15]                 b0..2: trip mid bytes; b3: odo LSB
//  4   r01e u32   06 01  DATA[16..19]                 b0..2: odo mid bytes; b3: unknown
//  5   r09a u32   06 09  DATA[ 0.. 3]                 b0..1: tick counter u16LE; b2..3: 0 (reserved)
//  6   r09b u32   06 09  DATA[ 4.. 7]                 b0..1: ~1985 (wheel mm?); b2..3: 4442
//  7   r09c u32   06 09  DATA[ 8..11]                 b0..1: 280; b2..3: 990
//
//  Not logged: 06 01 DATA[20] (always 0x00 in captures)
//              06 09 DATA[12..15] (static: 0x55, 0x00, 0x01, 0x05)
//
//  Extraction cheat-sheet for post-processing (Python / GoldenCheetah formula):
//    battery  (%)    = (r01b >> 24) & 0xFF
//    PAS level       = (r01b >> 8) & 0xFF
//    speed (km/h)    = ((r01c >> 8) & 0xFFFF) / 100.0
//    trip  (km)      = (((r01c >> 24) & 0xFF)
//                       | ((r01d & 0xFFFFFF) << 8)) / 100.0
//    odo   (km)      = (((r01d >> 24) & 0xFF)
//                       | ((r01e & 0xFFFFFF) << 8)) / 100.0
//    tick counter    = r09a & 0xFFFF

class BafangData {

    // Raw DATA bytes from the last received telemetry frames.
    var raw0601 as Lang.ByteArray? = null;   // 21 bytes
    var raw0609 as Lang.ByteArray? = null;   // 16 bytes

    // Decoded values for on-screen display (always up-to-date when raw* != null).
    var battery    as Number? = null;   // % (DATA[7])            CONFIRMED
    var pas        as Number? = null;   // assist level (DATA[5]) CONFIRMED
    var speedKmh   as Float?  = null;   // km/h                   CONFIRMED
    var tripKm     as Float?  = null;   // km                     CONFIRMED
    var odometerKm as Float?  = null;   // km                     CONFIRMED

    // Session metadata
    var model        as String  = "--";
    var bleConnected as Boolean = false;
    var bleStatus    as String  = "SCAN";  // SCAN / CONN / INIT / OK / ERR

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
        raw0601    = data;
        pas        = data[5];
        battery    = data[7];
        speedKmh   = FrameParser.u16le(data, 9).toFloat()  / 100.0;
        tripKm     = FrameParser.u32le(data, 11).toFloat() / 100.0;
        odometerKm = FrameParser.u32le(data, 15).toFloat() / 100.0;
    }

    // Update from a 06 09 DATA block (must be >= 16 bytes).
    function update0609(data as Lang.ByteArray) as Void {
        if (data.size() < 16) { return; }
        raw0609 = data;
    }

    // Pack 4 bytes starting at offset from raw0601 into a u32 LE value.
    // Returns null if data not yet available or offset out of range.
    function pack0601(offset as Number) as Number? {
        if (raw0601 == null) { return null; }
        var d = raw0601 as Lang.ByteArray;
        if (offset + 3 >= d.size()) { return null; }
        return d[offset]
             | (d[offset + 1] << 8)
             | (d[offset + 2] << 16)
             | (d[offset + 3] << 24);
    }

    // Pack 4 bytes starting at offset from raw0609 into a u32 LE value.
    function pack0609(offset as Number) as Number? {
        if (raw0609 == null) { return null; }
        var d = raw0609 as Lang.ByteArray;
        if (offset + 3 >= d.size()) { return null; }
        return d[offset]
             | (d[offset + 1] << 8)
             | (d[offset + 2] << 16)
             | (d[offset + 3] << 24);
    }
}
