import 'dart:typed_data';

class ParsedFrame {
  final int src, dst, op, reg;
  final Uint8List data;
  ParsedFrame(this.src, this.dst, this.op, this.reg, this.data);

  @override
  String toString() =>
      'Frame(src=0x${src.toRadixString(16)} dst=0x${dst.toRadixString(16)} '
      'op=0x${op.toRadixString(16)} reg=0x${reg.toRadixString(16)} '
      'data=[${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}])';
}

class FrameParser {
  static ParsedFrame? parse(Uint8List bytes) {
    if (bytes.length < 9) return null;
    if (bytes[0] != 0x55 || bytes[1] != 0xaa) return null;
    final payloadLen = bytes[2];
    final expectedSz = 9 + payloadLen;
    if (bytes.length != expectedSz) return null;
    if (!_verifyChecksum(bytes, payloadLen)) return null;
    return ParsedFrame(
      bytes[3], bytes[4], bytes[5], bytes[6],
      Uint8List.fromList(bytes.sublist(7, 7 + payloadLen)),
    );
  }

  static bool _verifyChecksum(Uint8List bytes, int payloadLen) {
    int sum = 0;
    for (int i = 2; i < 7 + payloadLen; i++) sum += bytes[i];
    final expected = (~sum) & 0xffff;
    final got = bytes[7 + payloadLen] | (bytes[7 + payloadLen + 1] << 8);
    return expected == got;
  }

  static int u16le(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  static int u32le(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
