import 'dart:typed_data';
import '../models/workout_record.dart';

// Writes a minimal valid FIT file containing file_id, record, session, and activity messages.
// FIT epoch = seconds since 1989-12-31 00:00:00 UTC
class FitWriter {
  static const int _fitEpochOffset = 631065600; // unix seconds to FIT seconds

  static int _fitTs(DateTime dt) =>
      (dt.toUtc().millisecondsSinceEpoch ~/ 1000) - _fitEpochOffset;

  static Uint8List write(WorkoutRecord rec) {
    final body = BytesBuilder();

    // ── Definitions ──────────────────────────────────────────────────────────

    // local msg 0: file_id (global 0)
    body.add(_defMsg(0, 0, [
      _field(4, 4, 134), // type: uint32
      _field(3, 4, 134), // time_created: uint32
    ]));
    body.add(_dataMsg(0, [
      _u32(4), // type = 4 (activity)
      _u32(_fitTs(rec.startTime)),
    ]));

    // local msg 1: record (global 20)
    body.add(_defMsg(1, 20, [
      _field(253, 4, 134), // timestamp
      _field(0, 4, 133),   // position_lat (semicircles s32)
      _field(1, 4, 133),   // position_long
      _field(6, 2, 132),   // speed (mm/s, uint16)
      _field(7, 2, 132),   // power (W, uint16)
      _field(4, 1, 2),     // heart_rate (bpm, uint8)
      _field(3, 1, 2),     // cadence (rpm, uint8)
      _field(13, 1, 2),    // temperature (C, int8) — reused for battery%
    ]));

    for (final p in rec.points) {
      final ts = _fitTs(p.timestamp);
      final lat = p.lat != null ? _degToSemiCircles(p.lat!) : 0x7FFFFFFF;
      final lon = p.lon != null ? _degToSemiCircles(p.lon!) : 0x7FFFFFFF;
      final speed = p.speedKmh != null
          ? ((p.speedKmh! * 1000 / 3.6)).round().clamp(0, 65534)
          : 0xFFFF;
      final power = p.powerWatts?.clamp(0, 65534) ?? 0xFFFF;
      final hrVal = p.hrBpm?.clamp(0, 254) ?? 0xFF;
      final cad = p.cadenceRpm?.round().clamp(0, 254) ?? 0xFF;
      final bat = p.batteryPct?.clamp(0, 127) ?? 0x7F;

      body.add(_dataMsg(1, [
        _u32(ts),
        _s32(lat),
        _s32(lon),
        _u16(speed),
        _u16(power),
        _u8(hrVal),
        _u8(cad),
        _u8(bat),
      ]));
    }

    // ── session (global 18) ──────────────────────────────────────────────────
    body.add(_defMsg(2, 18, [
      _field(253, 4, 134), // timestamp
      _field(2, 4, 134),   // start_time
      _field(7, 4, 134),   // total_elapsed_time (ms * 1000)
      _field(9, 4, 134),   // total_distance (cm)
      _field(26, 2, 132),  // avg_power
      _field(16, 1, 2),    // avg_heart_rate
      _field(18, 1, 2),    // avg_cadence
      _field(5, 1, 0),     // sport = 2 (cycling)
    ]));

    final endTs = rec.points.isNotEmpty
        ? _fitTs(rec.points.last.timestamp)
        : _fitTs(rec.startTime);
    final elapsedMs =
        rec.elapsed.inMilliseconds * 1000; // ms → FIT unit (ms * 1000)
    final distCm = (rec.totalDistanceKm * 100000).round();
    final avgHr = _avg(rec.points.map((p) => p.hrBpm).whereType<int>().toList());
    final avgPow = _avg(rec.points.map((p) => p.powerWatts).whereType<int>().toList());
    final avgCad = _avg(rec.points.map((p) => p.cadenceRpm?.round()).whereType<int>().toList());

    body.add(_dataMsg(2, [
      _u32(endTs),
      _u32(_fitTs(rec.startTime)),
      _u32(elapsedMs),
      _u32(distCm),
      _u16(avgPow.clamp(0, 65534)),
      _u8(avgHr.clamp(0, 254)),
      _u8(avgCad.clamp(0, 254)),
      _u8(2), // sport = cycling
    ]));

    // ── activity (global 34) ─────────────────────────────────────────────────
    body.add(_defMsg(3, 34, [
      _field(253, 4, 134), // timestamp
      _field(0, 4, 134),   // total_timer_time
      _field(1, 2, 132),   // num_sessions
      _field(2, 1, 0),     // type = 0 (manual)
      _field(3, 1, 0),     // event = 26 (activity)
      _field(4, 1, 0),     // event_type = 1 (stop)
    ]));
    body.add(_dataMsg(3, [
      _u32(endTs),
      _u32(elapsedMs),
      _u16(1),
      _u8(0),
      _u8(26),
      _u8(1),
    ]));

    final bodyBytes = body.toBytes();

    // ── File header ───────────────────────────────────────────────────────────
    final header = BytesBuilder();
    header.addByte(14);    // header size
    header.addByte(0x10);  // protocol version 1.0
    header.add(_u16le(2132)); // profile version 21.32
    header.add(_u32le(bodyBytes.length));
    header.add([0x2E, 0x46, 0x49, 0x54]); // ".FIT"
    header.add(_u16le(_crc16(Uint8List.fromList(header.toBytes()))));

    final out = BytesBuilder();
    out.add(header.toBytes());
    out.add(bodyBytes);
    // File CRC
    out.add(_u16le(_crc16(Uint8List.fromList(bodyBytes))));

    return Uint8List.fromList(out.toBytes());
  }

  // ── FIT encoding helpers ──────────────────────────────────────────────────

  static List<int> _defMsg(int localType, int globalMsgNum, List<List<int>> fields) {
    final buf = <int>[];
    buf.add(0x40 | (localType & 0x0F)); // definition record header
    buf.add(0x00);                        // reserved
    buf.add(0x00);                        // little-endian
    buf.addAll(_u16le(globalMsgNum));
    buf.add(fields.length);
    for (final f in fields) buf.addAll(f);
    return buf;
  }

  static List<int> _field(int defNum, int size, int baseType) =>
      [defNum, size, baseType];

  static List<int> _dataMsg(int localType, List<List<int>> values) {
    final buf = <int>[localType & 0x0F];
    for (final v in values) buf.addAll(v);
    return buf;
  }

  static List<int> _u8(int v) => [v & 0xFF];
  static List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  static List<int> _s32(int v) => _u32(v);
  static List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32le(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  static int _degToSemiCircles(double deg) => (deg * (1 << 31) / 180).round();

  static int _avg(List<int> vals) {
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) ~/ vals.length;
  }

  static int _crc16(Uint8List data) {
    const table = [
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ];
    int crc = 0;
    for (final b in data) {
      int tmp = table[(crc ^ b) & 0x0F];
      crc = (crc >> 4) ^ tmp;
      tmp = table[(crc ^ (b >> 4)) & 0x0F];
      crc = (crc >> 4) ^ tmp;
    }
    return crc;
  }
}
