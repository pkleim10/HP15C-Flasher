---
name: sam4l-samba-flash
description: >-
  Research and implement ATSAM4LC2C / HP 15C CE flashing over SAM-BA USB CDC.
  Use when changing SambaClient, FlashCalw, FlashApplet, Flasher, POSIX serial,
  flash wizard, or diagnosing SAM-BA timeouts, USB dropouts, or verify failures.
---

# SAM4L / SAM-BA flash

You are the protocol owner for this app. The Windows SAM-BA 2.16/2.18 flash
applet is the source of truth. Host `W#` to FLASHCALW and home-grown `G#`
blobs have already failed on real hardware.

## Hard rules

- Do not guess-and-flash the calculator. No “try 80 ms / skip unlock / reopen.”
- Do not write below `0x4000`. Do not issue Erase All / `EA`.
- Do not flash a damaged dump (for example checksum 3A3Ah).
- Known-good factory restore image: 114688 bytes, checksum 9090h, real ARM vectors.
- Reads, CHIPID, and backups are safe. Writes must use `SambaFlashApplet` (official `.bin`), not host FCMD.
- Tests must keep `commandSettleSeconds: 0` (no hardware sleeps).

## What already works

- Port: `/dev/cu.usbmodem*` only. VID `03EB` PID `6124`. FTDI `cu.usbserial` is not SAM-BA.
- Monitor: `v1.1 Oct 16 2012 17:15:20`. Commands `N#` `V#` `w` `W` `R` `S` `G`.
- Identify and 114688-byte application backup over USB CDC.
- **Full application write on real hardware (build 178):** official applet +
  `tcdrain` + 20 ms after every `S#` + `GENERIC::Run` poll (100 ms before first
  `w#`, 1 s between retries). Do not remove those gaps.

## What already failed (do not revive)

| Approach | Result |
|---|---|
| Host `W#` to FCMD + FSR poll | USB dies (monitor lives in flash; FRDY=0 stalls fetch) |
| Fire-and-forget FCMD, no verify | Host “succeeds”; pages stay erased / corrupt |
| Homebrew SRAM applet + `G#` | Go never returns; monitor calls `[addr+4]`, blob had no vector table |
| Close/reopen after FCMD | Needs ERASE+RESET; `connect()` times out |
| Immediate `R#` of the applet after `S#` | Next command is eaten as leftover `S#` payload; “timed out uploading” |
| Tight `w#` retry during WRITE USB NACK | Desyncs CDC; “timed out writing page 1” |

## Required method

Protocol is documented: [protocol.md](protocol.md). Official 2.16 applet:
`applet-flash-sam4l4.bin` (2652 bytes, load/`G#` `0x20002000`, mailbox
`0x20002040`). `G#` is a vector-table **call**; host waits by polling mailbox
command until `~cmd`. Do not invent a new Thumb mailbox.

1. Drive **that binary** from `SambaFlashApplet` over `SambaClient`.
2. After every `S#`, drain and wait (`afterSendDelay` 20 ms on hardware). Mac
   `write()` returns when the host accepts bytes, not when the monitor finishes.
3. After `G#`, wait before the first `w#`. Do not spam `w#` on NACK.
4. Tests keep `commandSettleSeconds: 0` / `afterSendDelay: 0`.

If evidence is missing, stop and say what to capture. Do not revert to host FCMD.

## Code map

- `Sources/HP15CFlasherCore/SambaClient.swift` — monitor
- `Sources/HP15CFlasherCore/FlashCalw.swift` — FLASHCALW + current write path
- `Sources/HP15CFlasherCore/FlashApplet.swift` — unused home-grown blob (do not treat as official)
- `Sources/HP15CFlasherCore/FlashLayout.swift` — `0x4000` / `0x1C000`
- `Sources/HP15CFlasherCore/Flasher.swift` — connect modem-only
- `Tools/sam4l_flash_applet.c` — source of the unused blob

## Additional resources

- Official 2.16 protocol (load/mailbox/`G#`/commands): [protocol.md](protocol.md)
- Known hardware facts: [reference.md](reference.md)
- Applet license: [THIRD_PARTY.md](../../../THIRD_PARTY.md)
- Restore and cable: user holds ERASE, presses RESET, releases ERASE
