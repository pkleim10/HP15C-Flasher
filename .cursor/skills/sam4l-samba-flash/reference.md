# SAM4L / HP 15C CE — hardware facts

## Chip and map

- MCU: ATSAM4LC2C (CIDR family `0xAB0A07E0`, ARCH `0xB0`, Cortex-M4)
- FLASHCALW: base `0x400A0000`, FCMD `+4`, FSR `+8`, KEY `0xA5`
- Commands used: WP=1, EP=2, CPB=3, UP=5. Page 512 bytes. App start page 32 = lock region 2.
- SAM-BA lives **in flash** `0x0000–0x3FFF`, not ROM. Any FCMD with FRDY=0 stalls instruction fetch.
- Application image: `0x4000`, 114688 bytes (`0x1C000`). 224 pages.

## Cable

- Two devices when plugged in:
  - Atmel ATSAM USB CDC `03EB:6124` → `/dev/cu.usbmodem*` — SAM-BA
  - FTDI FT231X `0403:6015` → `/dev/cu.usbserial*` — always present, ignore
- Do not toggle DTR/RTS. Do not set `HUPCL` or `TIOCEXCL` (FTDI can pulse RESET).
- Host FCMD still kills CDC until ERASE+RESET. Official SRAM applet writes (178) leave the session alive.

## Monitor session

- First command: `N#` (binary / non-interactive). Idle `N#` on a live session can desync CDC.
- Ping = CHIPID read only.
- Version seen: `v1.1 Oct 16 2012 17:15:20`
- Official Windows tool: SAM-BA 2.16/2.18, board **`sam4l-ek[not factory programmed]`** (`at91sam4l-ek`). There is no `at91sam4l8-ek` folder in 2.16. CIDR `0xAB0A07E0` (LC2C) is accepted by that script.
- Protocol: [protocol.md](protocol.md). Applet: `applet-flash-sam4l4.bin` at `0x20002000` (from SAM-BA 2.16; see [THIRD_PARTY.md](../../../THIRD_PARTY.md)).

## Images

| Kind | Role |
|---|---|
| Factory restore | 114688 bytes, checksum **9090h**, real ARM vectors. Safe to write at `0x4000`. |
| Damaged dump | Example checksum **3A3Ah**. Do not flash. |

Voyager displayed checksum = last non-padding byte duplicated (`VoyagerFirmwareChecksum.swift`). Known: factory 9090h, 2024 official 0A0Ah, DEC-only AF90h (not treated as recognized).

## Soft-brick vs true brick

- Soft: application flash damaged, bootloader intact. ERASE+RESET still reaches SAM-BA.
- True brick: write to `0x0000–0x3FFF`. Needs a debugger.

## Current Mac writer (proven 178)

`SambaFlashApplet` loads official `applet-flash-sam4l4.bin` at `0x20002000`, mailbox `0x20002040`, `G20002000#`, poll `command == ~cmd`. After each `S#`: `tcdrain` + 20 ms (`SambaClient.afterSendDelay`). After each `G#`: 100 ms, then poll; 1 s between retries. Host FCMD and homebrew `FlashApplet` are unused. See [protocol.md](protocol.md).
