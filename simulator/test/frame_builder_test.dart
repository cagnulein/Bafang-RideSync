import 'dart:typed_data';

import 'package:bafang_ride_sync_sim/frame_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BikeGo handshake token matches captured challenge/response pairs', () {
    const pairs = {
      'ca930cbf': 'c9d7c2a5789fb360740faf1622829c53',
      '01596faf': '6afc2d5786c38fd11814188a9ec47de8',
      '74d6071e': '51a29417f1fffa40225f6c72b071ded7',
      'a7d4ecb0': 'fe256e63628de98cf6ff14737c0a3cc9',
    };

    for (final entry in pairs.entries) {
      expect(
        _hex(FrameBuilder.handshakeToken(_bytes(entry.key))),
        entry.value,
      );
    }
  });
}

Uint8List _bytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
