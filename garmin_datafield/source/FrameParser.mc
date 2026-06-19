import Toybox.Lang;

// Parsed representation of a single EKD01-BF UART frame.
class ParsedFrame {
    var src  as Number;
    var dst  as Number;
    var op   as Number;
    var reg  as Number;
    var data as Lang.ByteArray;

    function initialize(s as Number, d as Number, o as Number,
                        r as Number, dat as Lang.ByteArray) {
        src  = s;
        dst  = d;
        op   = o;
        reg  = r;
        data = dat;
    }
}

class FrameParser {

    static const ERR_NONE     = 0;
    static const ERR_SHORT    = 1;
    static const ERR_MAGIC    = 2;
    static const ERR_LENGTH   = 3;
    static const ERR_CHECKSUM = 4;

    // Returns a ParsedFrame or null on error.
    static function parse(bytes as Lang.ByteArray) as ParsedFrame? {
        var sz = bytes.size();
        if (sz < 9)                                    { return null; }
        if (bytes[0] != 0x55 || bytes[1] != 0xaa)     { return null; }
        var payloadLen  = bytes[2];
        var expectedSz  = 9 + payloadLen;
        if (sz != expectedSz)                          { return null; }
        if (!verifyChecksum(bytes, payloadLen))        { return null; }
        return new ParsedFrame(
            bytes[3], bytes[4], bytes[5], bytes[6],
            byteSlice(bytes, 7, 7 + payloadLen)
        );
    }

    static function errorCode(bytes as Lang.ByteArray) as Number {
        var sz = bytes.size();
        if (sz < 9)                                { return ERR_SHORT; }
        if (bytes[0] != 0x55 || bytes[1] != 0xaa) { return ERR_MAGIC; }
        var payloadLen = bytes[2];
        if (sz != 9 + payloadLen)                 { return ERR_LENGTH; }
        if (!verifyChecksum(bytes, payloadLen))   { return ERR_CHECKSUM; }
        return ERR_NONE;
    }

    static function verifyChecksum(bytes as Lang.ByteArray, payloadLen as Number) as Boolean {
        var sum = 0;
        for (var i = 2; i < 7 + payloadLen; i++) {
            sum += bytes[i];
        }
        var expected = (~sum) & 0xffff;
        var got      = bytes[7 + payloadLen] | (bytes[7 + payloadLen + 1] << 8);
        return (expected == got);
    }

    // Read unsigned 16-bit little-endian from data at offset.
    static function u16le(data as Lang.ByteArray, offset as Number) as Number {
        return data[offset] | (data[offset + 1] << 8);
    }

    // Read unsigned 32-bit little-endian from data at offset.
    // NOTE: for values >= 0x80000000 the result will be negative (signed overflow).
    // All values we care about (odometers, timestamps) are well within 0x7fffffff.
    static function u32le(data as Lang.ByteArray, offset as Number) as Number {
        return data[offset]
             | (data[offset + 1] << 8)
             | (data[offset + 2] << 16)
             | (data[offset + 3] << 24);
    }

    // ByteArray slice (CIQ ByteArray.slice() not universally available).
    static function byteSlice(src as Lang.ByteArray, from as Number, to as Number) as Lang.ByteArray {
        var len = to - from;
        var out = new [len]b;
        for (var i = 0; i < len; i++) {
            out[i] = src[from + i];
        }
        return out;
    }
}
