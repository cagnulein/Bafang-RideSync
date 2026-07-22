import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'frame_parser.dart';

class BafangData extends ChangeNotifier {
  Uint8List? raw0601;
  Uint8List? raw0609;

  int? battery;
  int? pas;
  int? pasMax;
  int? powerWatts;
  double? cadenceRpm;
  double? speedKmh;
  double? tripKm;
  double? odometerKm;

  String model = '--';
  bool bleConnected = false;
  String bleStatus = 'SCAN';

  // Feed the same static frames used in BafangData.mc for offline testing.
  // battery=81%, PAS=1, speed=41.27 km/h, trip=115.80 km, odo=282.18 km
  void injectSimFrames() {
    update0601(Uint8List.fromList([
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x09,
      0x51,
      0x00,
      0x1f,
      0x10,
      0x3c,
      0x2d,
      0x00,
      0x00,
      0x3a,
      0x6e,
      0x00,
      0x00,
      0x00,
      0x00,
    ]));
    update0609(Uint8List.fromList([
      0xfd,
      0x51,
      0x00,
      0x00,
      0xc1,
      0x07,
      0x5a,
      0x11,
      0x18,
      0x01,
      0xde,
      0x03,
      0x55,
      0x00,
      0x01,
      0x05,
    ]));
    model = 'EKD01_CAN_BF_N22';
    bleConnected = true;
    bleStatus = 'SIM';
    notifyListeners();
  }

  void update0601(Uint8List data) {
    if (data.length < 21) return;
    raw0601 = data;
    pas = data[5];
    pasMax = data[6];
    battery = data[7];
    speedKmh = FrameParser.u16le(data, 9) / 100.0;
    tripKm = FrameParser.u32le(data, 11) / 100.0;
    odometerKm = FrameParser.u32le(data, 15) / 100.0;
    notifyListeners();
  }

  void update0609(Uint8List data) {
    if (data.length < 16) return;
    raw0609 = data;
    notifyListeners();
  }

  // Inject arbitrary hex string for replay testing, e.g. from ekd01_payloads.txt
  // hex = space-separated bytes, e.g. "55 aa 15 10 11 06 01 ..."
  bool injectHex(String hex) {
    try {
      final bytes = Uint8List.fromList(
        hex
            .trim()
            .split(RegExp(r'\s+'))
            .map((s) => int.parse(s, radix: 16))
            .toList(),
      );
      // Strip the outer frame envelope and route to the right update method
      if (bytes.length >= 9 && bytes[0] == 0x55 && bytes[1] == 0xaa) {
        final payloadLen = bytes[2];
        if (bytes.length == 9 + payloadLen) {
          final op = bytes[5];
          final reg = bytes[6];
          final data = Uint8List.fromList(bytes.sublist(7, 7 + payloadLen));
          if (op == 0x06 && reg == 0x01) {
            update0601(data);
            return true;
          }
          if (op == 0x06 && reg == 0x09) {
            update0609(data);
            return true;
          }
        }
      }
      // Fallback: treat as raw DATA bytes for 06 01 if length == 21
      if (bytes.length == 21) {
        update0601(bytes);
        return true;
      }
      if (bytes.length == 16) {
        update0609(bytes);
        return true;
      }
    } catch (_) {}
    return false;
  }

  int? get tickCounter {
    if (raw0609 == null) return null;
    return FrameParser.u16le(raw0609!, 0);
  }

  int? get wheelCfg {
    if (raw0609 == null) return null;
    return FrameParser.u16le(raw0609!, 4);
  }
}
