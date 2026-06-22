# EKD01-BF BLE and UART protocol notes

Last checked: 2026-06-22.

## BLE GATT

The current nRF Connect screenshot is committed as `../nrfconnect-ekd01-bf-services.png`.
It shows device `EKD01-BF` exposing:

- Advertised service: HID `0x1812`.
- Connected services: GAP `0x1800`, GATT `0x1801`, Nordic UART Service `6e400001-b5a3-f393-e0a9-e50e24dcca9e`, and HID `00001812-0000-1000-8000-00805f9b34fb`.
- Nordic UART RX characteristic `6e400002-b5a3-f393-e0a9-e50e24dcca9e`: read/write. This is the characteristic the central writes to.
- Nordic UART TX characteristic `6e400003-b5a3-f393-e0a9-e50e24dcca9e`: notify. This is the characteristic the bike notifies on.

`bluetoothd-hci-latest.pklg` was checked with:

```powershell
& "C:\Users\violarob\Downloads\WiresharkPortable64\App\Wireshark\tshark.exe" `
  -r "C:\Work\Bafang-RideSync\bluetoothd-hci-latest.pklg" `
  -Y "frame contains 55:aa"
```

That capture contains the same UART characteristics, but the GATT service database shown by Wireshark places them under custom service `7dfc9000-7d1c-4951-86aa-8d9728f8d66c`. Treat this as stale/cached capture evidence unless a fresh nRF Connect scan reproduces it. Runtime code intentionally targets only the standard Nordic UART service shown by the current nRF Connect screenshot.

Relevant capture evidence for address `70:de:f9:d6:ab:5f`:

- Enable notify: write `0x0001` to CCCD handle `0x0105` for characteristic `6e400003...`.
- Central writes Bafang frames to handle `0x0102`, labelled by Wireshark as `Nordic UART Tx` / characteristic `6e400002...`.
- Bike sends notifications on handle `0x0104`, labelled by Wireshark as `Nordic UART Rx` / characteristic `6e400003...`.

## UART frame format

All application payloads use this frame shape:

```text
55 aa LEN SRC DST OP REG DATA[LEN] CHECKSUM_LE16
```

Checksum is `(~sum(frame[2 .. 6 + LEN])) & 0xffff`, stored little-endian.

Observed node ids:

- `0x11`: central/app.
- `0x10`: realtime controller.
- `0xa5`: config/model node.
- `0xf1`: secondary config node.

Observed opcodes:

- `0x01`: read register request.
- `0x02`: write register request.
- `0x04`: read response.
- `0x05`: write ACK.
- `0x06`: telemetry notification.
- `0x20`: handshake request/ACK.

## Init sequence from capture

Representative packets from `bluetoothd-hci-latest.pklg`:

```text
write 0102: 55 aa 01 11 10 01 00 04 d8 ff
notify 0104: 55 aa 04 10 11 04 00 c9 31 f5 6b 7c fd

write 0102: 55 aa 10 11 10 20 00 ac 8f 09 2a fb aa 90 e7 92 c9 f8 dc ff 88 6d 58 a9 f5
notify 0104: 55 aa 01 10 11 20 00 00 bd ff

write 0102: 55 aa 01 11 a5 01 18 18 17 ff
notify 0104: 55 aa 18 a5 11 04 18 45 4b 44 30 31 5f 43 41 4e 5f 42 46 5f 4e 32 32 00 00 00 00 00 00 b7 fa
model: EKD01_CAN_BF_N22

write 0102: 55 aa 01 11 f1 01 01 1a d0 ff
notify 0104: 55 aa 1a f1 11 04 01 ...

write 0102: 55 aa 04 11 10 02 3e <local_epoch_le32> <checksum>
notify 0104: 55 aa 01 10 11 05 3e 00 9a ff

write 0102: 55 aa 04 11 10 02 42 <tz_offset_le32> <checksum>
notify 0104: 55 aa 01 10 11 05 42 00 96 ff

write 0102: 55 aa 04 11 10 02 46 <utc_epoch_le32> <checksum>
notify 0104: 55 aa 01 10 11 05 46 00 92 ff
```

## Telemetry

After init, the bike sends repeated notifications:

- `OP=0x06 REG=0x01`, 21 data bytes. This carries battery, PAS, speed, trip, and odometer fields currently decoded in `source/BafangData.mc`.
- `OP=0x06 REG=0x09`, 16 data bytes. This appears mostly static/config plus a tick counter.

Examples:

```text
55 aa 15 10 11 06 01 00 00 00 01 00 01 09 51 00 00 00 39 2d 00 00 37 6e 00 00 00 00 5b fe
55 aa 10 10 11 06 09 fd 51 00 00 c1 07 5a 11 18 01 de 03 55 00 01 05 e9 fb
```

## Runtime watchdog

The Garmin data field advances init and time-sync states only from valid notify responses. A `Toybox.Timer.Timer` watchdog checks the pending frame once per second while the state is between `STATE_INIT_1` and `STATE_TIME_SYNC_3`.

- Response timeout: 3 seconds.
- Retries: 2 retransmits of the same pending frame.
- Final failure: clear the pending frame and move to `STATE_ERROR`; a real BLE disconnect still restarts scanning through `onConnectedStateChanged()`.
