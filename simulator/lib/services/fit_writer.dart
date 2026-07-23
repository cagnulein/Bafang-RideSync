import 'dart:typed_data';
import '../models/workout_record.dart';

// FIT epoch = seconds since 1989-12-31 00:00:00 UTC
class FitWriter {
  static const int _fitEpochOffset = 631065600;

  static int _fitTs(DateTime dt) =>
      (dt.toUtc().millisecondsSinceEpoch ~/ 1000) - _fitEpochOffset;

  static Uint8List write(WorkoutRecord rec) {
    // Decide which optional standard fields are present
    final hasPower   = rec.points.any((p) => p.powerWatts != null);
    final hasCadence = rec.points.any((p) => p.cadenceRpm != null);

    final body = BytesBuilder();

    // ── Developer data: battery_pct and pas_level ─────────────────────────

    // local 4: developer_data_id (global 207)
    body.add(_defMsg(4, 207, [
      _field(4, 1, 0x02), // developer_data_index: uint8
    ]));
    body.add(_dataMsg(4, [_u8(0)]));

    // local 5: field_description (global 206)
    // field_name = 16 bytes string, units = 4 bytes string
    body.add(_defMsg(5, 206, [
      _field(0, 1, 0x02),  // developer_data_index: uint8
      _field(1, 1, 0x02),  // field_definition_number: uint8
      _field(2, 1, 0x02),  // fit_base_type_id: uint8
      _field(3, 16, 0x07), // field_name: string[16]
      _field(8, 4, 0x07),  // units: string[4]
    ]));

    // dev field 0: battery_pct
    body.add(_dataMsg(5, [
      _u8(0), _u8(0), _u8(0x02),
      _fitStr('battery_pct', 16),
      _fitStr('%', 4),
    ]));

    // dev field 1: pas_level
    body.add(_dataMsg(5, [
      _u8(0), _u8(1), _u8(0x02),
      _fitStr('pas_level', 16),
      _fitStr('', 4),
    ]));

    // ── file_id (global 0) ───────────────────────────────────────────────
    body.add(_defMsg(0, 0, [
      _field(4, 4, 0x86), // type: uint32
      _field(3, 4, 0x86), // time_created: uint32
    ]));
    body.add(_dataMsg(0, [
      _u32(4),
      _u32(_fitTs(rec.startTime)),
    ]));

    // ── record (global 20) with developer fields ─────────────────────────
    final stdFields = <List<int>>[
      _field(253, 4, 0x86), // timestamp: uint32
      _field(0,   4, 0x85), // position_lat: sint32 (semicircles)
      _field(1,   4, 0x85), // position_long: sint32
      _field(6,   2, 0x84), // speed: uint16 (mm/s)
      _field(4,   1, 0x02), // heart_rate: uint8 (bpm)
      if (hasPower)   _field(7, 2, 0x84), // power: uint16 (W)
      if (hasCadence) _field(3, 1, 0x02), // cadence: uint8 (rpm)
    ];
    // dev fields: [field_def_num, size_bytes, dev_data_index]
    const devFields = [
      [0, 1, 0], // battery_pct
      [1, 1, 0], // pas_level
    ];

    body.add(_defMsgWithDev(1, 20, stdFields, devFields));

    for (final p in rec.points) {
      final lat = p.lat != null ? _degToSemi(p.lat!) : 0x7FFFFFFF;
      final lon = p.lon != null ? _degToSemi(p.lon!) : 0x7FFFFFFF;
      final spd = p.speedKmh != null
          ? (p.speedKmh! * 1000 / 3.6).round().clamp(0, 65534)
          : 0xFFFF;

      final values = <List<int>>[
        _u32(_fitTs(p.timestamp)),
        _s32(lat),
        _s32(lon),
        _u16(spd),
        _u8(p.hrBpm?.clamp(0, 254) ?? 0xFF),
        if (hasPower)   _u16(p.powerWatts?.clamp(0, 65534) ?? 0xFFFF),
        if (hasCadence) _u8(p.cadenceRpm?.round().clamp(0, 254) ?? 0xFF),
        // developer fields
        _u8(p.batteryPct?.clamp(0, 254) ?? 0xFF),
        _u8(p.pas?.clamp(0, 254) ?? 0xFF),
      ];
      body.add(_dataMsg(1, values));
    }

    // ── session (global 18) ──────────────────────────────────────────────
    final endTs = rec.points.isNotEmpty
        ? _fitTs(rec.points.last.timestamp)
        : _fitTs(rec.startTime);
    final elapsedMs = rec.elapsed.inMilliseconds * 1000;
    final distCm = (rec.totalDistanceKm * 100000).round();
    final avgHr  = _avg(rec.points.map((p) => p.hrBpm).whereType<int>().toList());
    final avgPow = _avg(rec.points.map((p) => p.powerWatts).whereType<int>().toList());
    final avgCad = _avg(rec.points.map((p) => p.cadenceRpm?.round()).whereType<int>().toList());

    body.add(_defMsg(2, 18, [
      _field(253, 4, 0x86), // timestamp
      _field(2,   4, 0x86), // start_time
      _field(7,   4, 0x86), // total_elapsed_time (ms * 1000)
      _field(9,   4, 0x86), // total_distance (cm)
      _field(26,  2, 0x84), // avg_power
      _field(16,  1, 0x02), // avg_heart_rate
      _field(18,  1, 0x02), // avg_cadence
      _field(5,   1, 0x00), // sport
    ]));
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

    // ── activity (global 34) ─────────────────────────────────────────────
    body.add(_defMsg(3, 34, [
      _field(253, 4, 0x86),
      _field(0,   4, 0x86), // total_timer_time
      _field(1,   2, 0x84), // num_sessions
      _field(2,   1, 0x00), // type
      _field(3,   1, 0x00), // event
      _field(4,   1, 0x00), // event_type
    ]));
    body.add(_dataMsg(3, [
      _u32(endTs),
      _u32(elapsedMs),
      _u16(1),
      _u8(0), _u8(26), _u8(1),
    ]));

    final bodyBytes = body.toBytes();

    // ── File header ───────────────────────────────────────────────────────
    final hdr = BytesBuilder();
    hdr.addByte(14);
    hdr.addByte(0x10);
    hdr.add(_u16le(2132));
    hdr.add(_u32le(bodyBytes.length));
    hdr.add(const [0x2E, 0x46, 0x49, 0x54]); // ".FIT"
    hdr.add(_u16le(_crc16(Uint8List.fromList(hdr.toBytes()))));

    final out = BytesBuilder();
    out.add(hdr.toBytes());
    out.add(bodyBytes);
    out.add(_u16le(_crc16(Uint8List.fromList(bodyBytes))));

    return Uint8List.fromList(out.toBytes());
  }

  // ── Encoding helpers ─────────────────────────────────────────────────────

  static List<int> _defMsg(int local, int global, List<List<int>> fields) {
    final buf = <int>[];
    buf.add(0x40 | (local & 0x0F));
    buf.add(0x00);
    buf.add(0x00); // little-endian architecture
    buf.addAll(_u16le(global));
    buf.add(fields.length);
    for (final f in fields) buf.addAll(f);
    return buf;
  }

  static List<int> _defMsgWithDev(
      int local, int global, List<List<int>> std, List<List<int>> dev) {
    final buf = <int>[];
    buf.add(0x60 | (local & 0x0F)); // bit5 = developer data flag
    buf.add(0x00);
    buf.add(0x00);
    buf.addAll(_u16le(global));
    buf.add(std.length);
    for (final f in std) buf.addAll(f);
    buf.add(dev.length);
    for (final f in dev) buf.addAll(f);
    return buf;
  }

  static List<int> _field(int num, int size, int baseType) =>
      [num, size, baseType];

  static List<int> _dataMsg(int local, List<List<int>> values) {
    final buf = <int>[local & 0x0F];
    for (final v in values) buf.addAll(v);
    return buf;
  }

  static List<int> _u8(int v)  => [v & 0xFF];
  static List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  static List<int> _s32(int v) => _u32(v);
  static List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32le(int v) => _u32(v);

  static List<int> _fitStr(String s, int size) {
    final buf = List<int>.filled(size, 0);
    for (int i = 0; i < s.length && i < size - 1; i++) {
      buf[i] = s.codeUnitAt(i);
    }
    return buf;
  }

  static int _degToSemi(double deg) => (deg * (1 << 31) / 180).round();

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
