# HP 15C Flasher

Native macOS app that flashes **HP 15C Collector’s Edition** firmware over the official USB pogo programming cable. Windows SAM-BA is not required.

A Mach II Labs product. Free forever. It does not include HP firmware. Mach II Labs is not affiliated with HP, Atmel, or Microchip.

## Requirements

- macOS 13 or later
- HP 15C Collector’s Edition
- Official USB-C (or USB-A + adapter) pogo programming cable
- A 114,688-byte (112 KB) `.bin` you already have

**Do not use this cable or this app** on an HP 15C Limited Edition, a pre-2015 HP 12C, an HP 20b, or an HP 30b. Those pogo ports are a different protocol and voltage; the cable can destroy them.

## Install

Download `HP15CFlasher-x.y.z-N.dmg` from [machiilabs.com](https://machiilabs.com). Verify the SHA-256 posted with the file, then drag **HP 15C Flasher** to Applications.

The bootloader at `0x0000–0x3FFF` is never overwritten. Writes start at `0x04000`.

## Flash

1. Open the battery door and seat the keyed pogo connector.
2. Plug the cable into this Mac.
3. Hold **ERASE**, press **RESET**, release **ERASE**. The display stays off.
4. In the app: Save Backup, Choose Firmware, Flash.
5. Press **RESET** on the cable, then **ON**. “Pr Error” is expected; user memory was cleared.
6. Turn the calculator off, hold **g** and **ENTER**, press **ON**, then press **2**. The display should show `ChE - -` plus the checksum of the file you flashed (for example `0A0Ah`).
7. Press **ON** a few times to leave the test menu.

## Privacy

The app is offline. No telemetry, no network, no automatic diagnostics. Firmware files never leave this Mac.

## Acknowledgments

The SRAM flash helper is `applet-flash-sam4l4.bin` from Atmel SAM-BA 2.16, © 2011–2012 Atmel Corporation, redistributed under the SAM Software Package License. See [THIRD_PARTY.md](THIRD_PARTY.md). Atmel’s name is not used to endorse this product.

## Build from source

```bash
scripts/build_and_install.sh          # Release → /Applications
scripts/package_dmg.sh                # signed, notarized DMG in dist/
```

Xcode 15+, macOS 13 SDK. Daily installs bump the integer build number. `scripts/package_dmg.sh` is the public-release path.
