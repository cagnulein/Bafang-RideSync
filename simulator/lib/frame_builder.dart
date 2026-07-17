import 'dart:typed_data';

class FrameBuilder {
  static const int srcPhone = 0x11;
  static const int dstCtrl  = 0x10;
  static const int dstCfg   = 0xa5;
  static const int dstCfg2  = 0xf1;

  static const int opRead      = 0x01;
  static const int opWrite     = 0x02;
  static const int opHandshake = 0x20;

  static const int regStatus   = 0x00;
  static const int regModel    = 0x18;
  static const int regCfg2     = 0x01;
  static const int regSetE1    = 0xe1;
  static const int regReadE0   = 0xe0;

  static const int regLocalEpoch = 0x3e;
  static const int regTzOffset   = 0x42;
  static const int regUtcEpoch   = 0x46;

  static Uint8List build(int src, int dst, int op, int reg, Uint8List data) {
    final len   = data.length;
    final frame = Uint8List(9 + len);
    frame[0] = 0x55;
    frame[1] = 0xaa;
    frame[2] = len;
    frame[3] = src;
    frame[4] = dst;
    frame[5] = op;
    frame[6] = reg;
    for (int i = 0; i < len; i++) frame[7 + i] = data[i];
    int sum = 0;
    for (int i = 2; i < 7 + len; i++) sum += frame[i];
    final cksum = (~sum) & 0xffff;
    frame[7 + len]     = cksum & 0xff;
    frame[7 + len + 1] = (cksum >> 8) & 0xff;
    return frame;
  }

  static Uint8List readReg(int dst, int reg, int expectedLen) =>
      build(srcPhone, dst, opRead, reg, Uint8List.fromList([expectedLen & 0xff]));

  static Uint8List writeByte(int dst, int reg, int value) =>
      build(srcPhone, dst, opWrite, reg, Uint8List.fromList([value & 0xff]));

  static Uint8List writeU32(int dst, int reg, int value) {
    final d = Uint8List(4);
    d[0] =  value        & 0xff;
    d[1] = (value >>  8) & 0xff;
    d[2] = (value >> 16) & 0xff;
    d[3] = (value >> 24) & 0xff;
    return build(srcPhone, dst, opWrite, reg, d);
  }

  static Uint8List initHandshake() => build(
    srcPhone, dstCtrl, opHandshake, 0x00,
    Uint8List.fromList([
      0xac, 0x8f, 0x09, 0x2a, 0xfb, 0xaa, 0x90, 0xe7,
      0x92, 0xc9, 0xf8, 0xdc, 0xff, 0x88, 0x6d, 0x58,
    ]),
  );

  static List<Uint8List> initSequence() => [
    readReg(dstCtrl, regStatus,  0x04),
    initHandshake(),
    readReg(dstCfg,  regModel,   0x18),
    readReg(dstCfg2, regCfg2,    0x1a),
    writeByte(dstCfg, regSetE1,  0x01),
    readReg(dstCfg,  regReadE0,  0x01),
  ];
}
