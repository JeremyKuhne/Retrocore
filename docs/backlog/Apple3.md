# Backlog: the Apple III

Status: **agreed 2026-11-12.** Phases 0-6 are built; phase 6 awaits review.

The Apple III (1980) is the Apple II's business sibling. It has the same NMOS 6502 and Disk II logic as the II,
but around them it has a different machine:

- banked memory;
- an extended addressing trick that lets one 6502 instruction reach any bank;
- two 6522 VIAs that hold the system registers;
- character RAM instead of a character ROM;
- new video modes;
- a 6-bit DAC;
- SOS, the operating system ProDOS later borrowed its file system from.

It reuses a lot of what the Apple II and the debugger already have, but it is its own machine, not another
`Apple2Model`.

## The hardware

From the Apple III Service Reference Manual and MAME's `apple3` driver, which the work checks against each other.

| Part | What it is |
| --- | --- |
| CPU | Synertek 6502A (NMOS). About 2 MHz (14.318 MHz / 7). It drops to 1 MHz during active display while video is on, or always when the environment register asks for 1 MHz. |
| RAM | 128K or 256K (512K with third-party upgrades), in 32K banks. |
| ROM | 4K boot ROM at `$F000`, switchable out for RAM. It runs the power-on diagnostics, then boots SOS from the built-in drive. |
| Environment register | VIA 0 port A. 1/2 MHz; I/O at `$C000`; video on; NMI/RESET enable; write-protect `$C000-$FFFF`; force the primary stack; ROM in. |
| Zero-page register | VIA 0 port B. Moves zero page, and with it the stack, to any page. |
| Bank register | VIA 1 port A bits 0-2. Selects the bank seen at `$2000-$9FFF`. The rest is the system bank. |
| Extended addressing | For `(zp),Y` and `(zp,X)` with zero page in `$18xx-$1Fxx`, the "X-byte" at `zp ^ $0C00` names a bank pair when bit 7 is set. SOS keeps its large buffers in banks this way. |
| VIAs | Two 6522s at `$FFD0` and `$FFE0`. They also carry the VBL interrupt, the keyboard, slot IRQs and NMIs, the Apple II mode trap, screen blanking and the DAC. |
| Keyboard | AY-3600 encoder, Open and Solid Apple keys, a numeric keypad, and arrow keys. |
| Video | 40-column text (black and white, or 16-color foreground and background), 80-column text, 280×192 black and white, 560×192 black and white, 280×192 with color per 7-pixel cell, and 140×192 in 16 colors. Smooth scroll. 128 characters in character RAM, loaded through the screen holes. |
| Sound | Speaker toggle, a timed bell (`$C040`), and a 6-bit DAC on VIA 1 port B. |
| Disk | Built-in Disk II-style controller at `$C0E0`, with external drives .D2-.D4 selected through `$C0D0-$C0D7`. Disks have 16 sectors, so `.dsk`, `.po` and WOZ images work as they do on the II. |
| Other I/O | MM58167 clock at `$C070`, 6551 ACIA at `$C0F0`, analog inputs and two joysticks, and four slots for Apple III cards (ProFile, more serial, and so on). |
| Apple II emulation | A disk loads a II Plus ROM image into RAM and locks the machine into a 48K, 1 MHz II Plus. |

## Shape in the code base

A new project, `Retrocore.Machines.Apple3`, with machine id `apple3`. It shares, rather than copies:

- **The 6502 core**, with one addition: a class bus that implements `IOpcodeFetchBus` is told which reads have
  SYNC high, the opcode fetches and the fetch an interrupt discards. Extended addressing latches the X-byte on the
  indirect pointer fetch and clears it on SYNC. Other buses are unchanged and no slower
  ([core speed ledger](CoreOptimization.md)).
- **`Via6522`**, now a public chip in `Retrocore.Core` (`Retrocore.Machines.Chips`), shared with the Mockingboard.
- **The Disk II controller, drives and WOZ media**, from the Apple II project. The Apple III adds drive select for
  four drives on top of them.
- **The video renderer's NTSC and scanline plumbing**, where it fits. The modes and the memory layout are new.
- **The device model, debugger, extension and SDK pipeline**, unchanged in shape. The machine adds a debug target,
  as the Model I did.

## Phases

Each phase ends in a review before the next one starts.

### 0. Fixtures and references

They are under `%USERPROFILE%\Retrocore` and are never committed. Each folder has a `README.txt` with sources and
SHA-256 hashes.

- **`apple3-roms`: the boot ROM.**
  - `apple3.rom` is 4K, CRC `1af7ec42`, SHA-1 `8043f914ebdcdab9838dbb78f8a2ee3867d210d2`: the chip's true
    contents, as MAME 0.289 expects them.
  - Every archived MAME set (to 0.279) has an older dump, CRC `55e8eec9`. It was read from a running machine,
    so `$FFC0-$FFEF` holds RAM.
  - We patched in the chip bytes from MAME pull request 14960, and the hash matched. That range is the
    copyright string "(C) COPYRIGHT JULY, 1980 APPLE COMPUTER INC. JRH", so phase 5's source must build it.
  - `mame\apple3` is a set MAME verifies as good.
- **`apple3-disks`:** SOS 1.3 System Utilities, Business BASIC 1.23, Confidence, Diagnostics, Apple II
  Emulation, and the System Demo.
- **`docs\apple3`:** the boot ROM listing, the SOS 1.3 source as text, the SOS Reference Manual (volumes 1
  and 2), and the Apple III Service Reference Manual (1982, the OCR version).

MAME 0.289 is already in the cache, and its `apple3` driver is the trace oracle.

### 1. The machine without video

- The bus:
  - banks, the system bank and the `$C000`/`$F000` overlays;
  - zero-page and stack relocation;
  - extended addressing, including the X-byte value `$8F`;
  - write protection;
  - the bank wrap MAME describes, checked against the manual.
- The two VIAs wired as the hardware is, the keyboard, the speaker and bell, the 1/2 MHz clock with the
  video-on slowdown, and RESET and NMI as the environment register allows.
- **Done when** the boot ROM's diagnostics pass on 128K and 256K, the ROM waits at its "insert disk" prompt, and
  instruction traces match MAME's from power-on.

Built 2026-11-12:

- `Apple3Bus`, `Apple3Machine`, `Acia6551` (registers only) and `Apple3Roms`. Video switches, smooth scroll and
  character write are recorded for phase 2; the clock, slots and external drive select answer as empty.
- `Apple3BusTests` runs without the dump. `Apple3MachineTests` reaches RETRY on 128K, 256K and 512K, and a key
  is taken there. `Apple3OracleTests` (Conformance) matches MAME's trace, registers included, from power-on to the
  first disk access, through every diagnostic, with `tools\Apple3Oracle.lua`.
- What the hardware leaves to chance follows MAME, so the two run in step: RAM powers on as `$FF`, the beam
  starts at line 192, and the test takes MAME's power-on X, S and P.
- The comparison stops at the drive check. MAME's empty drive returns nothing, while ours reads noise, as our
  Disk II model does and a real drive does. So ours reaches RETRY a little later than MAME's.
- MAME's tracer is unsafe here: a debugger read of zero page latches an X-byte in its `apple3` driver. The
  oracle script traces registers only.
- Checked against the Service Reference Manual's text (`docs\apple3`, extracted with pypdf):
  - It agrees on the register addresses, extended addressing (zero page `$18-$1F`, the X-byte at the page XOR
    `$0C`, bit 7, I/O disabled while it is on, bank N below `$8000` and N+1 above), and 128K as three switchable
    banks plus the fixed one.
  - Speed: the screen and the CPU share RAM on alternate phases, and the CPU takes both "any time the screen is
    off"; 1.4 MHz average, 1.8 maximum. Our 1.905 MHz, MAME's measurement, is a little faster than that maximum.
  - A line is 65 states of 1 MHz, 25 of them horizontal blanking, with one stretched by 2 dots (the HPE freeze):
    912 dots. A frame is 262 lines, 70 of them vertical blanking. `Apple3Machine` now uses 912 (MAME uses 910),
    and a 1 MHz cycle of 912/65 dots (MAME's 1.0218 MHz is 14.013). The MAME comparison still matches, except
    where the ROM reads the screen-blank bit at `$F60F` and then masks it off, which the test leaves out.
  - The X-byte's bank is three lines (DA0-DA2) on Apple's board; we use four bits, as MAME does, for 512K.
  - Bank numbers, worked out from the decode equations, read from the scans rather than the OCR. These are
    PDF pages 39 (the 128K board's chips by RAS and CAS), 43-46 (the CAS and RAS PROMs) and 47 (`IND`).
    - On the 128K board, RAS0,3 is the system RAM, RAS1,2 bank 0, RAS4,5 bank 1 and RAS6,7 bank 2.
    - `IND = ABK4 * (ZPAGE*PA8')'` is an extended access: X-byte bit 7, on anything but zero page.
    - RAS.2 (page 46), for an access that is not extended:
      - RAS1,2 (bank 0) is strobed for bank values 0, 3 and 7.
      - RAS4,5 (bank 1) is strobed for value 1, and RAS6,7 (bank 2) for value 2.
      - Values 4-6 strobe no bank row on this board, since they live on the 256K board's second row (page 40).
    - Extended: values 0-2 give bank N for `$0000-$7FFF` and N+1 above, and N = 2 wraps to bank 0 above.
    - Bank value 7 is special. It strobes the system row as well as bank 0's (RAS0,3 and RAS1,2), and the bank-0
      CAS lines (PCAS1, PCAS2, page 44). The result is system RAM where it always is, with bank 0 at `$2000-$9FFF`,
      for the bank register and for an X-byte alike. That is the view MAME gives X-byte `$8F` only.
    - SOS agrees: `CNVRT.ADR` in BUFMGR turns bank 0, page `$20` into X-byte `$8F`, address `$2000`. With three
      bank lines, `$8F` is bank 7.
    - So MAME's rule, that a bank number equal to the system bank's selects bank 2, does not match the board.
      `Apple3Bus` follows the board instead:
      - bank 7 (15 with 512K) is bank 0 with the system RAM, from the bank register or an X-byte;
      - the last bank's partner wraps to bank 0.
    - The MAME comparison still matches, since the ROM never relies on bank 7 before the drive check.
    - What 128K does with values 3-6 depends on which PROM pairs with which board, which the manual does not
      say; there are two RAS PROMs (pages 45 and 46). Here they wrap to banks 0-2.

### 2. Video

- All six modes, color text, smooth scroll, VBL to the VIA, and character RAM loading.
- **Done when** frames from the ROM's screen, an SOS boot and a mode-test program match MAME frame by frame, with
  any MAME inaccuracy we disagree with written down. MAME's own notes doubt its color hi-res and 80-column
  colors.

Built 2026-11-12: `Apple3Video`.

- **Checked:**
  - The RETRY screen matches MAME pixel for pixel, apart from the cursor (`Apple3OracleTests`).
  - SOS's banner and the Utilities' 80-column menu render correctly.
  - `Apple3VideoTests` pins each mode and page on made-up memory.
- **Not done:** SOS and mode-test frames were not compared with MAME pixel by pixel.
- **Where we follow the manual over MAME:**
  - The mode bits match its truth table (6.24).
  - Page 2 of 280-dot color swaps dots and colors, and page 2 of 560 dots and 140 colors is at `$6000`/`$8000`. MAME
    differs on all three.
  - 80-column text is white; MAME draws it green.
- **Our own choices:**
  - 140-dot color uses the graphics palette; MAME uses the text palette there.
  - Flashing toggles every 16 frames.
  - As in MAME, smooth scrolling moves graphics only.
  - A "scanned" frame keeps each line's switches but reads memory when drawn.

### 3. Disks and SOS

- The built-in and external drives.
- The clock, the ACIA (enough for SOS's `.CONSOLE` and `.PRINTER` to stay quiet), the DAC through the existing
  audio sink, and the joysticks.
- **Done when** SOS 1.3 boots and Business BASIC runs and saves a program. The System Utilities also format and
  copy a disk.

Built 2026-11-12: all three, pinned by `Apple3SosTests`.

- **Drives:**
  - Four drives on the shared `DiskIIController`, selected by `$C0EA`/`$C0EB` and `$C0D0-$C0D3`.
  - The disk sequencer now steps with the CPU, two clocks to a 1 MHz cycle and one to a 2 MHz cycle. SOS writes at
    1 MHz, and drift between the two clocks lost bits.
  - While writing, the shared `DiskIIDrive` makes a cell exactly 8 sequencer clocks. At the media's 8.16, one bit
    in about 50 was lost; this changes Apple II writes too.
- **Keyboard:**
  - A typed capital or shifted symbol holds SHIFT while it is the key, since SOS makes lowercase itself.
  - Queued keys come 20 ms apart, since SOS takes keys by interrupt.
- **Other devices:** the MM58167 clock (counters of their own, set one at a time, advancing with the host's time;
  no interrupts), the ACIA's registers, the speaker and the DAC through `Apple2Audio`, and joysticks through `Apple3Bus.Joysticks`/`Buttons`.
- **Not done:**
  - Host game controllers are not wired to the joysticks.
  - Sector images load read-only, as on the Apple II, so saving needs a WOZ.

### 4. Debugger and extension

- `machine: "apple3"` with `ramKilobytes` (128, 256 or 512) and the boot ROM.
- Memory areas per bank, and bank-qualified addresses in the memory view, breakpoints, watch expressions and
  disassembly. Both the bank:address form and SOS's X-byte "extended address" form are accepted.
- The call stack across bank switches.
- The Retro Devices view with four drives, a launch entry in the machine catalog, and a `Test-Apple3Dap.mjs`.
- `docs/Apple3.md` as the user guide.

Built 2026-11-12:

- **Debug host:** `Apple3DebugTarget`, `Apple3SdkModules` and `DebugMachines.Apple3`.
- **Memory areas:** one per bank (`Apple3MemoryArea.Bank0-Bank14`).
- **Banks:** `system`, `bankN`, `rom`, and `x80-x8F` for extended addresses.
- **Call stack:** `DebugCallStack`, taking the stack page from the bus.
- **Extension:** the catalog entry, launch schema, display panel and request routing. The panel shares the Apple
  II's key buttons (Ctrl, CONTROL-C, CONTROL-RESET, Esc, Open and Solid Apple) and its Sound and volume, with no
  Mockingboard.
- **Checked:** `tools\Test-Apple3Dap.mjs` passes:
  - a power-on breakpoint in `BootRom.asm`;
  - RETRY;
  - the hardware, drives and banks;
  - a ROM read through `rom:`;
  - SOS's Utilities through the debugger.
- **Not checked:**
  - Breakpoints and disassembly qualified by bank.
  - The call stack across a bank switch.
  - The extension's editor test (`npm run test:editor`) past the machine menu, which needs the IIe ROM dumps.
    The language and machine menu tests pass, updated for the Apple III's `COUT` and dropdown entry.
- **Left out:** beam breakpoints, since the Apple III has no `HasBeam` yet.

### 5. SDK sources

- `Roms/Apple3/BootRom.asm` in native syntax, building the boot ROM byte-identically. Labels follow Apple's
  listing and the comments are our own, hand-maintained like the II's.
- `Apple3Equates.asm` for the hardware and SOS's documented entry points, with `;;` docs.
- A source test pins the bytes, and the doc lint covers it.

Built 2026-11-12: `Roms/BootRom.asm` and `Roms/Apple3Equates.asm` in the Apple III project.

- **Tests:** `Apple3RomSourceTests` (SHA-256 `370BE5F0…7520`, and the dump when present), and
  `SdkDocumentationTests.Apple3DocumentationIsCleanInTheEditor`.
- **Labels:** 382 of 390 code labels follow Apple's listing.
- **Listing differences:** the listing is an earlier revision. The source's header notes where it differs: the
  copyright, four branches, two monitor addresses, `ROWTEMP` and the U command.
- **Not done:** the equates cover the hardware only; SOS's entry points are not in it.

### 6. Apple II emulation mode

- The mode trap, the 48K II Plus memory map and 1 MHz, as the Emulation disk sets them up.
- **Done when** DOS 3.3 boots in emulation and AppleSoft runs.

Built 2026-11-12, pinned by `Apple3EmulationTests` and `Apple3BusTests.ClearingTheModeTrapHidesTheViasForGood`.

- **Already there from phases 1-3:** the Emulation disk boots, shows its menu, and boots DOS 3.3 from the built-in
  drive, and AppleSoft runs. It needed nothing new, because three pieces were already in place:
  - The trap: VIA 1 port A bit 6 low hides the VIAs at `$FFD0-$FFEF`. This is MAME's "Apple II mode trap output",
    and with it hidden the environment can never change again.
  - The memory map: write-protected RAM for the ROMs, and RAM at `$C500-$C7FF` for the disk's slot 5-7 firmware.
  - The 1 MHz environment bit.
- **New:**
  - `Apple3Bus.AppleIIMode`.
  - CONTROL-RESET is an NMI in the mode, as the manual's chapter 10 says, and the debugger's reset does the same.
    The emulation's Autostart points both vectors at its reset code.
  - The text rows decode the Apple II's screen codes, so the flashing cursor reads as a space.
  - The Hardware view's environment register says "Apple II mode".
- **Checked by hand:** the environment is `$FC` (1 MHz, I/O, video, NMI, write protection, primary stack, no ROM).
  After CONTROL-RESET the prompt is at the bottom, and the program is kept. The screen scrolls one line, as a
  II Plus's does, since INIT puts the cursor on the last row.
- **Not done:**
  - The Emulation disk's configuration menu (slot 5 and 7 serial cards) was not tried.
  - Paddles were not tried.
  - Frames in emulation were not compared with MAME.

## Later

- The Apple III Plus (interlaced video, its keyboard, 256K standard), once the III is solid.
- The ProFile hard disk and its card.
- Source-level SOS debugging from the SOS 1.3 listing.
- Business BASIC debugging, like AppleSoft's: built, awaiting review ([BusinessBasic.md](BusinessBasic.md)).
- Apple III Pascal: booting, code files and the Pascal thread are built ([Apple Pascal](ApplePascal.md)); line
  breakpoints from listings are next.
- SOS volumes in the media library, through CiderPress2's ProDOS support ([media](Media.md)).

## Decisions

Agreed 2026-11-12:

- A separate `Retrocore.Machines.Apple3` project with machine id `apple3`, not an `Apple2Model`.
- `Via6522` moves into `Retrocore.Core` as a shared chip.
- "Looks right" covered a review after every phase.
- The Apple III Plus comes later.
- Each phase 0 download is approved on its own, with its site, file and checksum.
