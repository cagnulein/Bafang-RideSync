"""
test_frame_parser.py – validates the EKD01-BF UART frame protocol.

All test frames are taken directly from PacketLogger / Wireshark captures
(2026-06-18) and manually verified against the protocol specification in
BIKEGO_EKD01_BLE_PROTOCOL.md.  Running the same logic here lets us catch
checksum regressions and parsing bugs without needing a Garmin device.
"""

import struct
import pytest


# ─────────────────────────────────────────────────────────────────────────────
# Python implementation of FrameParser.mc / FrameBuilder.mc
# ─────────────────────────────────────────────────────────────────────────────

MAGIC = b"\x55\xaa"

SRC_PHONE = 0x11
DST_CTRL  = 0x10
DST_CFG   = 0xa5
DST_CFG2  = 0xf1


def checksum(frame_bytes: bytes, payload_len: int) -> int:
    """One's-complement 16-bit sum of frame[2 : 7+payload_len]."""
    total = sum(frame_bytes[2 : 7 + payload_len])
    return (~total) & 0xFFFF


def parse(raw: bytes):
    """Return (src, dst, op, reg, data) or raise ValueError."""
    if len(raw) < 9:
        raise ValueError("frame too short")
    if raw[:2] != MAGIC:
        raise ValueError("bad magic")
    payload_len = raw[2]
    expected_len = 9 + payload_len
    if len(raw) != expected_len:
        raise ValueError(f"length mismatch: got {len(raw)}, expected {expected_len}")
    ck_got = raw[-2] | (raw[-1] << 8)
    ck_exp = checksum(raw, payload_len)
    if ck_got != ck_exp:
        raise ValueError(f"bad checksum: got 0x{ck_got:04x}, expected 0x{ck_exp:04x}")
    src  = raw[3]
    dst  = raw[4]
    op   = raw[5]
    reg  = raw[6]
    data = raw[7 : 7 + payload_len]
    return src, dst, op, reg, data


def u16le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def u32le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def build(src: int, dst: int, op: int, reg: int, data: bytes) -> bytes:
    body = bytes([len(data), src, dst, op, reg]) + data
    ck = (~sum(body)) & 0xFFFF
    return MAGIC + body + bytes([ck & 0xFF, ck >> 8])


def build_read(dst: int, reg: int, expected_len: int) -> bytes:
    return build(SRC_PHONE, dst, 0x01, reg, bytes([expected_len]))


def build_write_u32(dst: int, reg: int, value: int) -> bytes:
    return build(SRC_PHONE, dst, 0x02, reg, struct.pack("<I", value))


# ─────────────────────────────────────────────────────────────────────────────
# Known frames (verbatim bytes from captures / protocol doc)
# ─────────────────────────────────────────────────────────────────────────────

# Frame 46480 / 46490 / 46500 / 46566 – 06 01 at rest
# Reassembled BTHCI ACL hex (UART portion starting at offset 7):
#  55 aa 15 10 11 06 01 00 00 00 01 00 01 09 51 00 00 00 39 2d 00 00 37 6e 00 00 00 00 5b fe
FRAME_0601_REST = bytes.fromhex(
    "55aa15101106010000000100010951000000392d0000376e000000005bfe"
)

# Frame during pedaling (from BIKEGO_EKD01_BLE_PROTOCOL.md)
FRAME_0601_PEDAL = bytes.fromhex(
    "55aa1510110601000000010001095100 1f103c2d00003a6e000000002 6fe"
    .replace(" ", "")
)

# Frame 46494 – 06 09 (before pedaling, tick=0x51fd)
# Reassembled:  55 aa 10 10 11 06 09 fd 51 00 00 c1 07 5a 11 18 01 de 03 55 00 01 05 e9 fb
FRAME_0609_A = bytes.fromhex(
    "55aa10101106 09fd510000c1075a1118 01de03550001 05e9fb"
    .replace(" ", "")
)

# 06 09 from protocol doc (during pedaling, tick=0x5207)
FRAME_0609_B = bytes.fromhex(
    "55aa101011060907520000c1075a111801de035500010 5defc"
    .replace(" ", "")
)

# Model read response (frame 46348): EKD01_CAN_BF_N22
FRAME_MODEL = bytes.fromhex(
    "55aa18a511041845 4b44303 15f43414e5f42465f4e32320000000000000000b7fa"
    .replace(" ", "")
)

# Secondary config response (frame 46376)
FRAME_CFG2 = bytes.fromhex(
    "55aa1af1110401000055070000 0aa88b8b07401464002c010102320 0f401010 93c5efa"
    .replace(" ", "")
)

# Time sync TX frames (phone -> bike, from protocol doc)
FRAME_TSYNC_3E = bytes.fromhex("55aa0411100 23e0fb9336a35fe".replace(" ", ""))
FRAME_TSYNC_42 = bytes.fromhex("55aa0411100242201c00005aff")
FRAME_TSYNC_46 = bytes.fromhex("55aa041110024 62fd5336af1fd".replace(" ", ""))

# Time sync ACKs (bike -> phone)
FRAME_ACK_3E = bytes.fromhex("55aa0110110 53e009aff".replace(" ", ""))
FRAME_ACK_42 = bytes.fromhex("55aa011011054200 96ff".replace(" ", ""))
FRAME_ACK_46 = bytes.fromhex("55aa011011054600 92ff".replace(" ", ""))

# Handshake blob (OP=0x20, phone -> bike, from capture)
FRAME_HANDSHAKE = bytes.fromhex(
    "55aa101110200 0ac8f092afbaa90e792c9f8dcff886d5 8a9f5"
    .replace(" ", "")
)

# State request / response (frame 46336 / response)
FRAME_STATE_REQ = bytes.fromhex("55aa01111001000 4d8ff".replace(" ", ""))
FRAME_STATE_RESP = bytes.fromhex("55aa04101104 00c931f56b7cfd".replace(" ", ""))


# ─────────────────────────────────────────────────────────────────────────────
# Checksum tests
# ─────────────────────────────────────────────────────────────────────────────

class TestChecksum:
    def test_0601_rest(self):
        assert FRAME_0601_REST[-2:] == bytes([0x5b, 0xfe])
        src, dst, op, reg, data = parse(FRAME_0601_REST)
        assert op == 0x06 and reg == 0x01

    def test_0601_pedal(self):
        parse(FRAME_0601_PEDAL)

    def test_0609_a(self):
        parse(FRAME_0609_A)

    def test_0609_b(self):
        parse(FRAME_0609_B)

    def test_model_response(self):
        parse(FRAME_MODEL)

    def test_cfg2_response(self):
        parse(FRAME_CFG2)

    def test_tsync_3e(self):
        parse(FRAME_TSYNC_3E)

    def test_tsync_42(self):
        parse(FRAME_TSYNC_42)

    def test_tsync_46(self):
        parse(FRAME_TSYNC_46)

    def test_ack_3e(self):
        parse(FRAME_ACK_3E)

    def test_ack_42(self):
        parse(FRAME_ACK_42)

    def test_ack_46(self):
        parse(FRAME_ACK_46)

    def test_handshake(self):
        parse(FRAME_HANDSHAKE)

    def test_state_req(self):
        parse(FRAME_STATE_REQ)

    def test_state_resp(self):
        parse(FRAME_STATE_RESP)


# ─────────────────────────────────────────────────────────────────────────────
# Field extraction – 06 01
# ─────────────────────────────────────────────────────────────────────────────

class TestParse0601:
    def _data(self, raw: bytes) -> bytes:
        _, _, _, _, data = parse(raw)
        return data

    def test_header_fields_rest(self):
        src, dst, op, reg, _ = parse(FRAME_0601_REST)
        assert src == 0x10
        assert dst == 0x11
        assert op  == 0x06
        assert reg == 0x01

    def test_data_length_rest(self):
        assert len(self._data(FRAME_0601_REST)) == 21

    def test_battery_rest(self):
        d = self._data(FRAME_0601_REST)
        assert d[7] == 0x51        # 81%
        assert d[7] == 81

    def test_pas_rest(self):
        d = self._data(FRAME_0601_REST)
        assert d[5] == 0x01        # PAS 1

    def test_speed_rest(self):
        d = self._data(FRAME_0601_REST)
        speed_raw = u16le(d, 9)
        assert speed_raw == 0      # stationary
        assert speed_raw / 100.0 == 0.0

    def test_trip_rest(self):
        d = self._data(FRAME_0601_REST)
        trip_raw = u32le(d, 11)
        assert trip_raw == 0x00002d39   # 11577
        assert abs(trip_raw / 100.0 - 115.77) < 0.001

    def test_odo_rest(self):
        d = self._data(FRAME_0601_REST)
        odo_raw = u32le(d, 15)
        assert odo_raw == 0x00006e37    # 28215
        assert abs(odo_raw / 100.0 - 282.15) < 0.001

    def test_unknown_bytes_rest(self):
        d = self._data(FRAME_0601_REST)
        assert d[0] == 0x00
        assert d[1] == 0x00
        assert d[2] == 0x00
        assert d[3] == 0x01   # possible mode/display flag
        assert d[4] == 0x00
        assert d[6] == 0x09   # possible page/profile
        assert d[8] == 0x00   # separator
        assert d[19] == 0x00
        assert d[20] == 0x00

    def test_speed_pedaling(self):
        d = self._data(FRAME_0601_PEDAL)
        speed_raw = u16le(d, 9)
        # 0x101f = 4127 → 41.27 km/h (wheel spinning)
        assert speed_raw == 0x101f
        assert abs(speed_raw / 100.0 - 41.27) < 0.001

    def test_trip_pedaling(self):
        d = self._data(FRAME_0601_PEDAL)
        trip_raw = u32le(d, 11)
        assert trip_raw == 0x00002d3c   # 11580 → 115.80 km
        assert abs(trip_raw / 100.0 - 115.80) < 0.001

    def test_odo_pedaling(self):
        d = self._data(FRAME_0601_PEDAL)
        odo_raw = u32le(d, 15)
        assert odo_raw == 0x00006e3a    # 28218 → 282.18 km
        assert abs(odo_raw / 100.0 - 282.18) < 0.001


# ─────────────────────────────────────────────────────────────────────────────
# Field extraction – 06 09
# ─────────────────────────────────────────────────────────────────────────────

class TestParse0609:
    def _data(self, raw: bytes) -> bytes:
        _, _, _, _, data = parse(raw)
        return data

    def test_header_fields(self):
        src, dst, op, reg, _ = parse(FRAME_0609_A)
        assert src == 0x10
        assert dst == 0x11
        assert op  == 0x06
        assert reg == 0x09

    def test_data_length(self):
        assert len(self._data(FRAME_0609_A)) == 16

    def test_tick_counter_before_pedaling(self):
        d = self._data(FRAME_0609_A)
        tick = u16le(d, 0)
        assert tick == 0x51fd   # 20989

    def test_tick_counter_during_pedaling(self):
        d = self._data(FRAME_0609_B)
        tick = u16le(d, 0)
        assert tick == 0x5207   # 20999 (+10 from 0x51fd)

    def test_tick_increases(self):
        tick_a = u16le(self._data(FRAME_0609_A), 0)
        tick_b = u16le(self._data(FRAME_0609_B), 0)
        assert tick_b > tick_a

    def test_reserved_bytes_zero(self):
        d = self._data(FRAME_0609_A)
        assert d[2] == 0x00
        assert d[3] == 0x00

    def test_wheel_config_candidate(self):
        # DATA[4..5] = 0x07c1 = 1985, consistent across both frames
        d_a = self._data(FRAME_0609_A)
        d_b = self._data(FRAME_0609_B)
        assert u16le(d_a, 4) == 1985
        assert u16le(d_b, 4) == 1985

    def test_static_fields_consistent(self):
        d_a = self._data(FRAME_0609_A)
        d_b = self._data(FRAME_0609_B)
        # All static fields should match between the two frames
        for i in range(2, 16):      # skip tick counter (bytes 0-1)
            assert d_a[i] == d_b[i], f"byte {i} differs: {d_a[i]:#x} vs {d_b[i]:#x}"

    def test_known_static_values(self):
        d = self._data(FRAME_0609_A)
        assert u16le(d, 4)  == 1985   # wheel mm candidate
        assert u16le(d, 6)  == 4442   # unknown
        assert u16le(d, 8)  == 280    # unknown
        assert u16le(d, 10) == 990    # unknown
        assert d[12] == 85            # unknown
        assert d[13] == 0
        assert d[14] == 1
        assert d[15] == 5


# ─────────────────────────────────────────────────────────────────────────────
# Init frame validation
# ─────────────────────────────────────────────────────────────────────────────

class TestInitFrames:
    def test_model_string(self):
        _, _, op, reg, data = parse(FRAME_MODEL)
        assert op  == 0x04
        assert reg == 0x18
        model = data.rstrip(b"\x00").decode("ascii")
        assert model == "EKD01_CAN_BF_N22"

    def test_handshake(self):
        src, dst, op, reg, data = parse(FRAME_HANDSHAKE)
        assert src == SRC_PHONE
        assert dst == DST_CTRL
        assert op  == 0x20
        assert reg == 0x00
        assert len(data) == 16

    def test_state_request(self):
        src, dst, op, reg, data = parse(FRAME_STATE_REQ)
        assert src == SRC_PHONE
        assert dst == DST_CTRL
        assert op  == 0x01
        assert reg == 0x00
        assert data[0] == 0x04   # expect 4-byte response

    def test_state_response(self):
        src, dst, op, reg, data = parse(FRAME_STATE_RESP)
        assert src == DST_CTRL
        assert dst == SRC_PHONE
        assert op  == 0x04
        assert reg == 0x00
        assert len(data) == 4


# ─────────────────────────────────────────────────────────────────────────────
# Time sync TX frames
# ─────────────────────────────────────────────────────────────────────────────

class TestTimeSync:
    # Reference capture: UTC 2026-06-18T11:23:27Z, CEST (UTC+7200)
    UTC_EPOCH  = 0x6a33d52f    # 1781781807
    TZ_OFFSET  = 7200
    LOCAL_EPOCH = UTC_EPOCH - TZ_OFFSET   # 0x6a33b90f

    def test_reg_3e_local_epoch(self):
        src, dst, op, reg, data = parse(FRAME_TSYNC_3E)
        assert src == SRC_PHONE
        assert dst == DST_CTRL
        assert op  == 0x02
        assert reg == 0x3e
        assert len(data) == 4
        value = u32le(data, 0)
        assert value == self.LOCAL_EPOCH

    def test_reg_42_tz_offset(self):
        _, _, _, reg, data = parse(FRAME_TSYNC_42)
        assert reg == 0x42
        assert u32le(data, 0) == self.TZ_OFFSET

    def test_reg_46_utc_epoch(self):
        _, _, _, reg, data = parse(FRAME_TSYNC_46)
        assert reg == 0x46
        assert u32le(data, 0) == self.UTC_EPOCH

    def test_ack_3e(self):
        src, dst, op, reg, data = parse(FRAME_ACK_3E)
        assert src == DST_CTRL
        assert op  == 0x05
        assert reg == 0x3e
        assert data[0] == 0x00   # success

    def test_ack_42(self):
        _, _, op, reg, _ = parse(FRAME_ACK_42)
        assert op == 0x05 and reg == 0x42

    def test_ack_46(self):
        _, _, op, reg, _ = parse(FRAME_ACK_46)
        assert op == 0x05 and reg == 0x46


# ─────────────────────────────────────────────────────────────────────────────
# Frame builder
# ─────────────────────────────────────────────────────────────────────────────

class TestFrameBuilder:
    def test_build_state_request_matches_capture(self):
        built = build_read(DST_CTRL, 0x00, 0x04)
        assert built == FRAME_STATE_REQ

    def test_build_tsync_3e(self):
        value = TestTimeSync.LOCAL_EPOCH
        built = build_write_u32(DST_CTRL, 0x3e, value)
        assert built == FRAME_TSYNC_3E

    def test_build_tsync_42(self):
        built = build_write_u32(DST_CTRL, 0x42, TestTimeSync.TZ_OFFSET)
        assert built == FRAME_TSYNC_42

    def test_build_tsync_46(self):
        built = build_write_u32(DST_CTRL, 0x46, TestTimeSync.UTC_EPOCH)
        assert built == FRAME_TSYNC_46

    def test_build_model_read_request(self):
        built = build_read(DST_CFG, 0x18, 0x18)
        parsed = parse(built)
        assert parsed[0] == SRC_PHONE
        assert parsed[1] == DST_CFG
        assert parsed[2] == 0x01
        assert parsed[3] == 0x18
        assert parsed[4][0] == 0x18

    def test_roundtrip(self):
        """Build a frame, parse it back, verify all fields."""
        payload = bytes([0xde, 0xad, 0xbe, 0xef])
        raw = build(SRC_PHONE, DST_CTRL, 0x02, 0x7f, payload)
        src, dst, op, reg, data = parse(raw)
        assert src  == SRC_PHONE
        assert dst  == DST_CTRL
        assert op   == 0x02
        assert reg  == 0x7f
        assert data == payload


# ─────────────────────────────────────────────────────────────────────────────
# Rejection tests (invalid frames must raise)
# ─────────────────────────────────────────────────────────────────────────────

class TestRejection:
    def test_too_short(self):
        with pytest.raises(ValueError, match="too short"):
            parse(b"\x55\xaa\x01\x11\x10")

    def test_bad_magic(self):
        bad = b"\x55\xab" + FRAME_0601_REST[2:]
        with pytest.raises(ValueError, match="bad magic"):
            parse(bad)

    def test_bad_checksum(self):
        corrupted = bytearray(FRAME_0601_REST)
        corrupted[-1] ^= 0xFF
        with pytest.raises(ValueError, match="bad checksum"):
            parse(bytes(corrupted))

    def test_length_mismatch(self):
        # Claim LEN=2 but only supply 1 data byte
        frame = build(SRC_PHONE, DST_CTRL, 0x01, 0x00, b"\x04")
        truncated = frame[:-2]   # strip checksum → wrong total length
        with pytest.raises(ValueError):
            parse(truncated)

    def test_extra_bytes(self):
        padded = FRAME_0601_REST + b"\x00"
        with pytest.raises(ValueError):
            parse(padded)


# ─────────────────────────────────────────────────────────────────────────────
# FIT field packing (verify packed u32 values match expected decode)
# ─────────────────────────────────────────────────────────────────────────────

class TestFitPacking:
    """Verify the packed u32 field values so that external tools can decode
    battery/PAS/speed/trip/odo directly from the raw FIT fields."""

    def _pack4(self, data: bytes, offset: int) -> int:
        return data[offset] | (data[offset+1] << 8) | (data[offset+2] << 16) | (data[offset+3] << 24)

    def test_r01b_contains_pas_and_battery(self):
        _, _, _, _, data = parse(FRAME_0601_REST)
        r01b = self._pack4(data, 4)
        # DATA[5] = PAS = 1 → second byte of r01b
        assert (r01b >> 8) & 0xFF == 1
        # DATA[7] = battery = 0x51 → fourth byte (MSB) of r01b
        assert (r01b >> 24) & 0xFF == 0x51

    def test_r01c_contains_speed(self):
        _, _, _, _, data = parse(FRAME_0601_PEDAL)
        r01c = self._pack4(data, 8)
        # DATA[9..10] = speed = 0x101f → bytes 1-2 of r01c
        speed_raw = (r01c >> 8) & 0xFFFF
        assert speed_raw == 0x101f
        assert abs(speed_raw / 100.0 - 41.27) < 0.001

    def test_r09a_contains_tick(self):
        _, _, _, _, data = parse(FRAME_0609_A)
        r09a = self._pack4(data, 0)
        tick = r09a & 0xFFFF
        assert tick == 0x51fd


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
