import Toybox.Lang;

// Builds UART frames for the EKD01-BF protocol.
// Frame format: 55 aa LEN SRC DST OP REG DATA[LEN] CHECKSUM_LE16
// Checksum = (~sum(frame[2 .. 7+LEN-1])) & 0xffff, little-endian.
class FrameBuilder {

    static const SRC_PHONE = 0x11;
    static const DST_CTRL  = 0x10;   // realtime controller node
    static const DST_CFG   = 0xa5;   // config / model node
    static const DST_CFG2  = 0xf1;   // secondary config node

    // OP codes (outgoing)
    static const OP_READ      = 0x01;
    static const OP_WRITE     = 0x02;
    static const OP_HANDSHAKE = 0x20;

    // Registers used during init
    static const REG_STATUS   = 0x00;
    static const REG_MODEL    = 0x18;
    static const REG_CFG2     = 0x01;
    static const REG_SET_E1   = 0xe1;
    static const REG_READ_E0  = 0xe0;

    // Time sync registers on DST_CTRL
    static const REG_LOCAL_EPOCH = 0x3e;   // utc - tz_offset
    static const REG_TZ_OFFSET   = 0x42;   // timezone offset in seconds
    static const REG_UTC_EPOCH   = 0x46;   // raw UTC epoch

    static function build(src as Number, dst as Number, op as Number, reg as Number,
                          data as Lang.ByteArray) as Lang.ByteArray {
        var len   = data.size();
        var total = 9 + len;
        var frame = new [total]b;
        frame[0] = 0x55;
        frame[1] = 0xaa;
        frame[2] = len;
        frame[3] = src;
        frame[4] = dst;
        frame[5] = op;
        frame[6] = reg;
        for (var i = 0; i < len; i++) {
            frame[7 + i] = data[i];
        }
        var sum = 0;
        for (var i = 2; i < 7 + len; i++) {
            sum += frame[i];
        }
        var cksum = (~sum) & 0xffff;
        frame[7 + len]     = cksum & 0xff;
        frame[7 + len + 1] = (cksum >> 8) & 0xff;
        return frame;
    }

    // OP=0x01: request a register value from a node.
    // expectedLen = number of bytes the device should reply with (goes into DATA[0]).
    static function readReg(dst as Number, reg as Number, expectedLen as Number) as Lang.ByteArray {
        var d = new [1]b;
        d[0] = expectedLen & 0xff;
        return build(SRC_PHONE, dst, OP_READ, reg, d);
    }

    // OP=0x02: write a single byte to a register.
    static function writeByte(dst as Number, reg as Number, value as Number) as Lang.ByteArray {
        var d = new [1]b;
        d[0] = value & 0xff;
        return build(SRC_PHONE, dst, OP_WRITE, reg, d);
    }

    // OP=0x02: write a uint32 (little-endian) to a register.
    static function writeU32(dst as Number, reg as Number, value as Number) as Lang.ByteArray {
        var d = new [4]b;
        d[0] =  value        & 0xff;
        d[1] = (value >>  8) & 0xff;
        d[2] = (value >> 16) & 0xff;
        d[3] = (value >> 24) & 0xff;
        return build(SRC_PHONE, dst, OP_WRITE, reg, d);
    }

    // OP=0x20: fixed 16-byte handshake blob observed in the BikeGo capture.
    // This may be a static auth token. Replace if a different unit requires
    // a different value (reverse-engineer the generation if needed).
    static function initHandshake() as Lang.ByteArray {
        var blob = [0xac, 0x8f, 0x09, 0x2a, 0xfb, 0xaa, 0x90, 0xe7,
                    0x92, 0xc9, 0xf8, 0xdc, 0xff, 0x88, 0x6d, 0x58]b;
        return build(SRC_PHONE, DST_CTRL, OP_HANDSHAKE, 0x00, blob);
    }

    // Convenience: full init sequence as an array of frames (in order).
    static function initSequence() as Lang.Array {
        return [
            readReg(DST_CTRL, REG_STATUS,  0x04),   // state request to controller
            initHandshake(),                          // 16-byte auth blob
            readReg(DST_CFG,  REG_MODEL,   0x18),   // read model string (24 bytes)
            readReg(DST_CFG2, REG_CFG2,    0x1a),   // secondary config (26 bytes)
            writeByte(DST_CFG, REG_SET_E1, 0x01),   // set config a5/e1 = 0x01
            readReg(DST_CFG,  REG_READ_E0, 0x01)    // read config a5/e0
        ];
    }
}
