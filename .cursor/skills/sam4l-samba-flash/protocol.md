# Official SAM-BA 2.16 SAM4L flash protocol

Source of truth: extracted from `/Volumes/SSD/Downloads/sam-ba_2.16_windows.exe` (NSIS PE32, 12 MiB).  
Do not guess. Do not issue host `W#` to FLASHCALW. Drive this applet.

Local copies (gitignored tree + small bin at skill root):

| File | Role |
|---|---|
| `applet-flash-sam4l4.bin` | Official SRAM applet (2652 bytes). Copy next to this file. |
| `extracted/tcl_lib/at91sam4l-ek/at91sam4l-ek.tcl` | Board script HP 15C CE uses |
| `extracted/tcl_lib/common/generic.tcl` | Host mailbox / `GENERIC::Run` |
| `extracted/applets/sam4l/sam-ba_applets/flash/flash_app_main.c` | Applet commands |
| `extracted/applets/sam4l/sam-ba_applets/common/applet.h` | Command / status codes |
| `extracted/applets/sam4l/sam-ba_applets/common/applet_cstartup.c` | Vector table + return |
| `extracted/applets/sam4l/sam-ba_applets/linker_script/sram_samba.lds` | Load at `0x20002000` |
| `extracted/applets/sam4l/bootloader/sam/applications/sam4l_sam-ba/sam_ba_monitor.c` | `G#` = vector-table **call** |
| `extracted/applets/sam4l/bootloader/sam/applications/sam4l_sam-ba/sam_ba_monitor.h` | Version `"1.1"` |

SHA-256 of `applet-flash-sam4l4.bin`:  
`01672908fce38940ce817e21401b5a89e280d9f12b00a1210bf9f6f12ace0fbf`

---

## 1. Confirmed facts

### Board for HP 15C CE (ATSAM4LC2C)

There is **no** `at91sam4l8-ek` folder in SAM-BA 2.16.

- Board list (`extracted/tcl_lib/common/boards.tcl` line 125):  
  `"sam4l-ek[not factory programmed]"` → `at91sam4l-ek/at91sam4l-ek.tcl`
- That script accepts CIDR `& 0xFFFFFFE0` matching both:
  - `0xAB0A09E0` (SAM4L4 / 256 KB)
  - `0xAB0A07E0` (SAM4L2 / 128 KB) ← HP 15C CE
- Applet is compiled as `__ATSAM4LC4C__` / `sam4l4` but `flashcalw_get_flash_size()` reports the real size at INIT.
- GUI “Flash” send = `FLASH::SendFileNoLock` (write only; refuses dest page `< appStartPage`).
- Application start is page 32 = `0x4000`. Applet refuses writes below `MONITOR_SIZE` (`0x4000`).

HP Museum Windows instructions that say pick **sam4l-ek[not factory programmed]** match this installer.

### Applet binary

| Field | Value |
|---|---|
| Filename | `tcl_lib/at91sam4l-ek/applet-flash-sam4l4.bin` |
| Size | **2652** bytes (`0xA5C`) |
| Load address | **`0x20002000`** (`FLASH::appletAddr`, linker `sram` ORIGIN) |
| `G#` argument | **`0x20002000`** — vector table **base**, **not** Thumb entry |
| Initial SP (word 0) | `0x20007FF0` (unused by `G#`; monitor does not load SP) |
| Reset vector (word 1) | **`0x20002809`** = `0x20002808 \| 1` (Thumb bit) |
| Mailbox | **`0x20002040`** (32 words / 128 bytes, section `.mailbox` after 16-word vector table) |
| Buffer | Returned by INIT at mailbox `+0x0C`. Size forced to **512** (`FLASH_PAGE_SIZE`) — comment in source: “Timeout issue” |
| Stack used on `G#` | Monitor’s stack. Applet `ResetException` `push {r0-r12}` / `pop {r0-r12}` then returns |

Vector table dump of the 2.16 `.bin`:

```
[ 0] 0x20007FF0   SP
[ 1] 0x20002809   ResetException | 1
[ 2..15] 0
mailbox at +0x40 is zeros in the file
```

SRAM: applet at `0x20002000`; SAM-BA monitor uses `0x20000000`–`0x200007FF` (`romcodesram` in the linker). Do not load at `0x20001000`.

### Mailbox word layout

Base `mailbox = 0x20002040`. Little-endian 32-bit words. Union overlays args.

| Offset | Field | INIT out | WRITE in / out | UNLOCK in | ERASE_PAGE in |
|---|---|---|---|---|---|
| `+0x00` | `command` | `0x00` then `~cmd` | `0x02` then `~cmd` | `0x05` | `0x44` |
| `+0x04` | `status` | `APPLET_*` | `APPLET_*` | `APPLET_*` | `APPLET_*` |
| `+0x08` | argv0 | `memorySize` | in: `bufferAddr` / out: `bytesWritten` | `sector` | `page` |
| `+0x0C` | argv1 | `bufferAddress` | `bufferSize` | — | — |
| `+0x10` | argv2 | `bufferSize` | `memoryOffset` | — | — |
| `+0x14` | argv3 | `lockRegionSize:u16` \| `numbersLockBits:u16 << 16` | — | — | — |
| `+0x18` | | `pageSize` | | | |
| `+0x1C` | | `nbPages` | | | |
| `+0x20` | | `appStartPage` (32) | | | |

INIT **input** (written before `G#`):

| Offset | Value for USB CDC |
|---|---|
| `+0x00` | `0x00` (INIT) |
| `+0x08` | `comType` = **`0`** (`USB_COM_TYPE`) |
| `+0x0C` | `traceLevel` (0 is fine) |
| `+0x10` | `bank` = 0 |

Expected INIT on ATSAM4LC2C (128 KB): `memorySize = 0x20000`, `bufferSize = 0x200`, `pageSize = 0x200`, `nbPages = 256`, `appStartPage = 32`, `numbersLockBits = 16`. `bufferAddress` is `&end` (after BSS); **read it from INIT**, do not hard-code.

WRITE `memoryOffset` is from flash base `0x00000000`, so application page 0 is offset **`0x4000`**.

### Command and status codes

From `applet.h` / `appletCmdSam4l` (SAM4L extras in `at91sam4l-ek.tcl`):

| Name | Word | Use on 15C restore |
|---|---|---|
| `APPLET_CMD_INIT` | `0x00` | Load + INIT once |
| `APPLET_CMD_FULL_ERASE` | `0x01` | **Do not use.** Tcl GUI has it; **applet C has no case** |
| `APPLET_CMD_WRITE` | `0x02` | Page program (`flashcalw_memcpy(..., erase=true)`) |
| `APPLET_CMD_READ` | `0x03` | Optional; host `R#` of flash also works |
| `APPLET_CMD_LOCK` | `0x04` | `flashcalw_lock_region(sector, true)` — do not lock after restore |
| `APPLET_CMD_UNLOCK` | `0x05` | `flashcalw_lock_region(sector, false)` — region index 0..15 |
| `APPLET_CMD_SECURITY` | `0x07` | **Do not set** |
| `APPLET_CMD_FUSES` | `0x40` | GUI “Unlock All” / “Set Lock Bit” (GP fuses). Lock bit 0 = locked, 1 = unlocked |
| `APPLET_CMD_ERASE_PAGE` | `0x44` | Page number; refuses pages `< 32` |
| User page / unique SN | `0x41`–`0x43` | Not needed for restore |

Status (`applet.h`):

| Name | Value |
|---|---|
| `APPLET_SUCCESS` | `0x00` |
| `APPLET_DEV_UNKNOWN` | `0x01` |
| `APPLET_WRITE_FAIL` | `0x02` (locked region on WRITE also returns this, **not** `0x04`) |
| `APPLET_READ_FAIL` | `0x03` |
| `APPLET_PROTECT_FAIL` | `0x04` |
| `APPLET_UNPROTECT_FAIL` | `0x05` |
| `APPLET_ERASE_FAIL` | `0x06` |
| `APPLET_FAIL` | `0x0f` |

Completion: applet always does `pMailbox->command = ~(pMailbox->command)` then **returns**.  
INIT `0x00` → mailbox cmd `0xFFFFFFFF`. WRITE `0x02` → `0xFFFFFFFD`.

### Host sequence (exact)

Monitor commands (binary / `N#` already done). `G#` produces **no** serial payload.

1. `S20002000,<size>#` + 2652 applet bytes (`GENERIC::LoadApplet` / `TCL_Write_Data`).
2. `W20002040,00000000#` command = INIT. Then `W` comType / trace / bank at `+8/+C/+10`.
3. `G20002000#` — **not** `G20002001#`.
4. Wait for completion: **poll `w20002040,4#` until the word equals `~cmd`**. Then `w20002044,4#` for status.
5. Read INIT outputs (`memorySize`, `bufferAddress`, `bufferSize`, …).
6. Per 512-byte chunk (HP 15C: 224 pages):
   - `S<bufferAddress>,00000200#` + page bytes
   - `W` command `2`, argv0 = buffer, argv1 = 512, argv2 = flash offset (`0x4000`, `0x4200`, …)
   - `G20002000#`
   - Poll mailbox cmd == `~0x02`, status == 0, argv0 == bytes written
7. Optional unlock **before** write if status is write/protect fail:
   - Per-region: command `0x05`, argv0 = region index (app = regions **2..15** on 128 KB).
   - GUI “Unlock All” is **fuses `0x40`**, value `0xFFFF`, mask `0xFFFF` (sets 16 lock fuses to 1 = unlocked). Different from `0x05`.

`FLASH::SendFileNoLock` does **not** unlock. Official restore may rely on regions already unlocked, or a prior “Unlock All” click.

Windows `GENERIC::Run` (`generic.tcl`): `TCL_Go` then `after 10` (10 ms), then up to **10** `TCL_Read_Int` of the command word, **1 s** apart (25 retries for erase). Linux path spins without the 10 ms delay. Completion is **mailbox invert**, not a `G#` ACK.

AT09423 (same 2.x applet model): while the applet runs, the device is **not** in monitor mode. USB **NACK**s IN packets until `call_applet` returns. The next `w#` succeeds only after the applet returns to the monitor.

### What `G#` actually does on this monitor

`sam_ba_monitor.c` (`command == 'G'`):

```c
void call_applet(uint32_t address)
{
    uint32_t *ptr_reset_vector = (uint32_t *)(address + 4);
    ptrfunc.__ptr = (void *)(*ptr_reset_vector);
    ptrfunc.__fun();          /* CALL, not BX-never-return */
    __enable_interrupt();
}
```

Version string in this tree is `SAM_BA_VERSION "1.1"` plus `__DATE__` `__TIME__` — matches hardware `v1.1 Oct 16 2012 17:15:20`.

The applet `ResetException` (`applet_cstartup.c`) runs `applet_main`, then falls off the function so `BLX` returns to the monitor. It does **not** branch to a fixed monitor address. Host must not expect a `>` or any G# reply in binary mode.

### Why our unused `FlashApplet` never came back

| Ours (`FlashApplet.swift`) | Official |
|---|---|
| Load `0x20001000`, entry `0x20001001` | Load / `G#` `0x20002000` |
| Raw Thumb blob, no vector table | Cortex-M table at load; reset at `[load+4]` |
| Host treated `G#` as “jump to Thumb PC and wait for return token” | `G#` reads **word at address+4** and **calls** it |
| Done flag: `MAIL_CMD = 0` | Done flag: `command = ~command` |
| Mailbox `0x20001F00` | Mailbox `0x20002040` |

`G20001000#` made the monitor execute the word at `0x20001004` (`0xF2C27500` from the blob) — not SRAM code. Monitor never resumed → next `w#` timed out (“timed out unlocking”).  
`G20001001#` is worse (unaligned `[0x20001005]`).

Even a correct vector table would still require polling `~cmd`, not waiting for a serial ACK.

### Cross-checks (not invented)

- **SAM-BA 2.16 installer**: primary evidence above. Applet sources ship inside the NSIS archive (`applets/sam4l/...`). Header still says `SAM_BA_APPLETS_VERSION "2.14"`.
- **SAM-BA 2.18**: same 2.x Tcl + applet model (AT09423). No 2.18 installer in this pass; treat 2.16 `.bin` as the binary to drive unless a 2.18 dump differs by hash.
- **Public GitHub `xtremekforever/sam-ba`**: older 2.x applets; SAM4**S** EEFC `main.c`, not SAM4L FLASHCALW. Same mailbox *idea*, different flash driver.
- **bossac / BOSSA**: **no SAM4L**. Families are EEFC SAM3/SAM4S/SAM4E and SAMD. Protocol uses `S#` + `Y#` (WordCopy applet) / EEFC `FCR` — **not** this FLASHCALW mailbox. Do not copy BOSSA.
- **SAM-BA 3.x**: QML / different host API; secure-monitor applets on other chips. Not the v1.1 Oct 2012 USB CDC monitor.
- **OpenOCD / ASF**: OpenOCD is SWD. ASF `sam4l_sam-ba` **is** the monitor we extracted (`call_applet`). Useful as the same source, not a replacement protocol.
- **AT03454** (in `extracted/docs/`): SAM-BA lives in flash `[0, 0x4000)`, app at `0x4000`. Confirms why host FCMD stalls fetch.

---

## 2. Unknowns (need a Windows SAM-BA USB/COM trace)

Do **not** flash to learn these. Capture SAM-BA 2.16/2.18 on a live 15C CE (or a SAM4L-EK) with a USB analyzer / COM log:

1. Exact `G#` line: confirm `G20002000#` with no extra `#` (SAM9G45 second-`#` workaround is commented out in 2.16 Tcl).
2. First mailbox `w#` timing vs USB NACK duration on this CDC stack (Windows 10 ms + 1 s retries vs our 3 s `readWord` timeout).
3. Whether Voyager/HP flow clicks **Unlock All** (fuses `0x40`) before Send, or only `SendFileNoLock`.
4. Whether 2.18’s `applet-flash-sam4l4.bin` is byte-identical (hash). If not, use 2.18’s bin.
5. INIT `bufferAddress` numeric value on real LC2C (should be just after BSS; ~`0x20002Axx` but **must** come from INIT).
6. Whether `TCL_Write_Int` / `TCL_Go` insert any hidden delay or re-`N#`.

Until (3) is known, first hardware write should be **one already-unlocked page** after INIT, with a command transcript.

---

## 3. Recommended Swift types (do not implement in this pass)

Ownership:

- **`SambaClient`** keeps the monitor: `N#` `V#` `w` `W` `R` `S` `G`. `go(_:)` stays “send `G%08X#` and return”; it must **not** wait for a prompt. Document that `G#` is silent.
- **`SambaFlashApplet`** (new) owns the official `.bin`, mailbox, INIT/WRITE/UNLOCK/ERASE_PAGE, and **poll `~cmd`**. It holds a `SambaClient` (borrowed, not owned).
- **`FlashCalw`** keeps `identify()` and `readApplication()` (direct `R#` is fine). `writeApplication` should call `SambaFlashApplet`, not `issue(FCMD)`.
- **`Flasher`** still owns session lifetime (`connect` / `withClient`) and passes `SambaClient` in.
- **`FlashApplet`** (homebrew at `0x20001000`) stays unused; do not revive.

Sketch:

```swift
public enum SambaAppletCommand: UInt32 {
    case initialize = 0x00
    case write = 0x02
    case read = 0x03
    case lock = 0x04
    case unlock = 0x05
    case erasePage = 0x44
}

public enum SambaAppletStatus: UInt32 {
    case success = 0x00
    case writeFail = 0x02
    case protectFail = 0x04
    case unprotectFail = 0x05
    case eraseFail = 0x06
    case fail = 0x0F
}

public struct SambaAppletInfo: Equatable {
    public var memorySize: UInt32
    public var bufferAddress: UInt32
    public var bufferSize: UInt32
    public var pageSize: UInt32
    public var pageCount: UInt32
    public var appStartPage: UInt32
    public var lockRegionSize: UInt16
    public var lockBitCount: UInt16
}

public final class SambaFlashApplet {
    public static let loadAddress: UInt32 = 0x2000_2000
    public static let mailboxAddress: UInt32 = 0x2000_2040
    public static let goAddress: UInt32 = 0x2000_2000  // vector table base
    public static let image: Data /* applet-flash-sam4l4.bin, 2652 bytes */

    private let samba: SambaClient
    public private(set) var info: SambaAppletInfo?

    public init(samba: SambaClient)

    public func loadAndInitialize(
        comType: UInt32 = 0,
        traceLevel: UInt32 = 0,
        bank: UInt32 = 0
    ) throws -> SambaAppletInfo

    public func unlockRegion(_ region: Int) throws
    public func write(flashOffset: UInt32, data: Data) throws -> Int
    public func erasePage(_ page: Int) throws
    public func read(flashOffset: UInt32, length: Int) throws -> Data

    /// G# then poll mailbox+0 until word == ~command; return status at +4.
    func run(_ command: SambaAppletCommand, timeout: TimeInterval) throws -> SambaAppletStatus
}
```

Rules inside `write`:

- Reject `flashOffset < 0x4000`.
- Chunk to `info.bufferSize` (512).
- Never send `0x01` (full erase) or `0x07` (security).
- Keep a timestamped transcript of every `S#` / `W#` / `G#` / `w#`.

Simulator: `G#` must read `[addr+4]`, call that Thumb entry, invert mailbox command. Today it runs the **homebrew** mailbox at `0x20001F00` — that must change before applet unit tests mean anything.

---

## 4. Exact next implementation step

One page, logged, no UI 224-page flash.

1. Add `applet-flash-sam4l4.bin` (2652 bytes) as a bundle/resource or `static let image` in `SambaFlashApplet`.
2. Implement `loadAndInitialize` + `run` (poll `~cmd`) only. No FCMD, no settle, no reopen.
3. Teach `SimulatedCalculatorTransport` the official vector-table `G#` and mailbox at `0x20002040`. Unit test: load applet bytes, INIT, one 512-byte WRITE at offset `0x4000`, assert mailbox invert and flash contents. `commandSettleSeconds: 0`.
4. On hardware: connect, INIT, transcript on, **write one page at `0x4000`** from factory `hp15c-firmware.bin` (not `-2.bin`), read that page back with `R#`. Stop. If USB dies, capture the transcript and a Windows SAM-BA trace of the same INIT+one WRITE — do not retry with settle/reopen.

If INIT `G#` already times out, the missing evidence is item 2 in Unknowns (poll timeout vs USB NACK), not another FCMD tweak.
