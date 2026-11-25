# Backlog: the Atari 400 and 800

Status: **agreed 2026-11-16.** Phases 0-6 are built; phases 1-6 await review.

The Atari 400 and 800 (1979) are 6502 machines built around three custom chips: ANTIC, which runs a display list
and takes the bus for DMA; CTIA (later GTIA), which makes the colours, the players and missiles, and the collisions;
and POKEY, which makes the sound, scans the keyboard and drives the serial bus that every peripheral hangs off. Like
the Apple IIe, the machine has firmware worth debugging at source level: the OS's documented vectors (`CIOV`,
`SIOV`, `SETVBV`, `DSKINV`), its handlers (`E:`, `S:`, `K:`, `P:`, `C:`), the vertical blank routines, the
floating point package, and Atari BASIC in its cartridge.

The goal is the Apple IIe's level of support:

- the models and their ROMs, built from byte-identical SDK sources that are fully documented;
- the video in every ANTIC mode with players and missiles, the keyboard and console keys, sound, joysticks and
  paddles, the 410 recorder and the 810 disk drive;
- the debugger at source level, and at Atari BASIC level;
- the extension, Start Machine and the Desktop;
- media that saves;
- MAME traces as the oracle.

## The hardware

From Atari's Home Computer System Hardware Manual, the OS User's Manual, De Re Atari, the field service manuals and
MAME's `a400` and `a800` drivers. Phase 1 confirms each row.

| Part | What it is |
| --- | --- |
| CPU | An NMOS 6502B at 1.7898 MHz (NTSC) or 1.7734 MHz (PAL). ANTIC halts it, through RDY, for each DMA cycle and for `WSYNC`. |
| RAM | 8 KB to 48 KB from `$0000`, in 8 KB or 16 KB modules. The 800 has three module slots; the 400 one fixed board, 16 KB as shipped (MAME's `a400` defaults to 16 KB). |
| Cartridges | The 800's left slot is `$A000-$BFFF` (8 KB), its right slot `$8000-$9FFF`; the 400 has the left slot only. A cartridge's `RD4`/`RD5` lines unmap the RAM under it. |
| I/O | `$D000` GTIA (CTIA on early machines), `$D200` POKEY, `$D300` the 6520 PIA, `$D400` ANTIC, each mirrored through its page. `$D100` and `$D500-$D7FF` are open (`$D500` is the cartridge control page). |
| OS ROM | 10 KB: the floating point package at `$D800-$DFFF` (2 KB) and the OS at `$E000-$FFFF` (8 KB, two 4 KB chips), with the character set at `$E000-$E3FF`. |
| ANTIC | Reads the display list from RAM by DMA: 6 text modes (2-7) and 8 bitmap modes (8-15), blank lines, jumps and the vertical blank jump, horizontal and vertical fine scrolling, load memory scan, display list interrupts (NMI), the vertical blank NMI, `WSYNC`, `VCOUNT`, the light pen, and player/missile DMA. Its cycle stealing (refresh, display list, character name and data, P/M) sets the CPU's speed line by line. |
| CTIA/GTIA | The colour registers, four players and four missiles with sizes and priorities, the 60 collision bits, the console keys (START, SELECT, OPTION) and speaker bit, and the joystick triggers. GTIA adds three 16-colour modes (BASIC's `GRAPHICS 9`-`11`). Early 800s had CTIA, which lacks them. |
| POKEY | Four audio channels with 8- or 16-bit dividers, polynomial counters and high-pass filters; the keyboard scan with debounce, the `BREAK` key and SHIFT/CTRL; the serial port (SIO) with its clocks and shift registers; three timer interrupts; eight paddle pots; the random number generator. |
| PIA | The 6520's port A reads joysticks 1 and 2, port B joysticks 3 and 4 (both models have four ports). CA2 is the SIO motor control, CB2 the SIO command line; CA1 and CB1 are the SIO proceed and interrupt lines. |
| Keyboard | 57 keys (the 400's is a membrane) scanned by POKEY's 6-bit counter; SHIFT, CTRL and BREAK are separate lines. START, SELECT and OPTION are read by GTIA, and SYSTEM RESET is wired to ANTIC's NMI, not the CPU's reset. |
| Video | NTSC: 262 lines of 114 CPU cycles (228 colour clocks); PAL: 312 lines. 128 colours on CTIA and GTIA (16 hues, 8 luminances), 256 in GTIA mode 9. |
| SIO | The serial bus at 19,200 baud, with the command line, motor control, proceed and interrupt. Every peripheral (the 410, the 810, the 850 and printers) is a device on it. |
| 410 recorder | Two-tone FSK (5,327 Hz mark, 3,995 Hz space) at about 600 baud, decoded in the recorder and fed to POKEY's serial input; the PIA's CA2 runs the motor. The OS's `C:` handler measures the baud rate from the leader. |
| 810 disk drive | Its own computer: a 6507, a 6532 RIOT, an FD1771 and a 2 KB ROM, on single-sided 40-track disks of 18 sectors of 128 bytes (90 KB). The ROM answers the SIO commands (`R`, `W`, `P`, `S`, `!`). |

### The ROM versions

| ROM | Size | What it is |
| --- | --- | --- |
| OS rev. B, NTSC | 10 KB | CO12399B (FP), CO12499B and CO14599B. The final 400/800 OS, and the one MAME's `a800` uses by default. |
| OS rev. A, NTSC | 10 KB | The same FP chip with CO12499A and CO14599A: the first release; rev. B fixed bugs in it. |
| OS rev. A, PAL | 10 KB | The FP chip with CO15199 and CO15299. MAME calls this rev. A of the PAL OS; there is no PAL rev. B dump. |
| Atari BASIC rev. A | 8 KB | The 400/800's cartridge (Shepardson Microsystems, 1979). |
| Atari BASIC rev. B, C | 8 KB each | B came built into the 600XL and 800XL and added bugs; C (1983) fixed them and is the last. MAME's `a800` cartridge list has all three. |
| 810 firmware | 2 KB | The drive's 6507 ROM, revision B or C, from MAME's `a810` device. Phase 0 confirms which. |

MAME marks the OS chips `BAD_DUMP`. Phase 0 finds out why, and checks them against the combined 10 KB images that
circulate.

## Proposed decisions

These are the plan's choices. Each needs your yes before phase 0.

1. **The project and id.** The project is `Retrocore.Machines.Atari`, which leaves room for the XL and XE (and, much
   later, the 5200). The machine id is `atari800`, and `model` names the variant, as `apple2` and `pet` do.
2. **The models.** `atari800`, the default: 48 KB, OS rev. B NTSC, GTIA, two cartridge slots, Atari BASIC rev. C in
   the left slot unless another cartridge is given. `atari400`: 16 KB (with 48 KB as an option), one slot. PAL is a
   `video: pal` option on both rather than a separate model, since only the OS ROM and the timing change. OS rev. A
   and CTIA are options too, for software that needs them. The XL and XE come later, as their own phase.
3. **The BASIC revision.** One source with `VERSION` builds for revs. A, B and C. I recommend C as the default because
   it is the one that works; A is what the 400 and 800 actually shipped with. Your call.
4. **The 810 at the hardware level.** The drive is emulated as its 6507, 6532 and FD1771, running its own ROM, as the
   4040 and the BBC's 8271 are. A trap that answers SIO commands from the image (MAME's `fdc` HLE option) would be
   faster to build but would not debug the drive, and copy-protected disks would not load. To keep the SIO bus
   testable before then, phase 2 adds a simple SIO disk device that answers from the image; phase 4 replaces it as
   the default.
5. **The sources.** No Atari 8-bit ROM has had an official open-source release. Atari published the OS source listing
   (1982), and COMPUTE! published *The Atari BASIC Source Book* (1983), but both are copyrighted print listings, not
   licensed releases, so as with the BBC's DNFS they are not imported or followed. Every ROM is our own native source,
   written from the dumps with the SDK's tools: the OS (rev. B, with rev. A and PAL as `VERSION` builds), the floating
   point package, the character set, Atari BASIC and the 810's firmware. Names follow Atari's published
   documentation: the OS User's Manual and the Hardware Manual name the vectors, the database variables (`SAVMSC`,
   `DOSVEC`, `SDMCTL`, `ICCOM` and the rest), the shadow registers and the hardware registers. Labels with no
   published name are named by what they are.
6. **Each phase ends in a review** before the next one starts. The ROM sources phase has a review after each ROM.

## Shape in the code base

A new project, `Retrocore.Machines.Atari`, with `Atari800Machine`, `AtariBus`, `AtariModel`, `AtariRoms`, `Antic`,
`Gtia`, `AtariKeyboard`, `AtariSioBus`, `Atari410` and `Atari810`. It shares, rather than copies:

- **The 6502 core.** ANTIC needs the CPU halted on chosen cycles; the core's RDY input may already be enough, and
  phase 1 checks that first. If the core has to change, the change follows the
  [PGO maintenance checklist](../../.claude/skills/performance-testing/overlay.md#native-aot-pgo-maintenance), and the
  IIe's benchmarks must not move.
- **`Pia6821`** for the PIA (the 6520 is register-compatible).
- **New shared chips in `Retrocore.Core`:** `Pokey` (it is also in Atari's arcade boards and the 5200), and an
  `Fd1771` taken out of `Trs80DiskController`, so the TRS-80 and the 810 share it. The 810's 6532 uses the PET
  branch's `Riot6532` if that merges first; otherwise this plan adds one and the second branch to merge takes the
  other's.
- **The native 6502 dialect**, for every ROM source.
- **`Retrocore.Basic`**, which gains `AtariBasicDialect`. Atari BASIC is not a Microsoft BASIC either: a program is a
  variable name table, a variable value table and a statement table, with tokens for statements and operators and
  syntax checked at entry, and numbers in the FP package's 6-byte BCD. So the dialect is new code.
- **The device model, debugger, extension and Desktop**, unchanged in shape. The machine adds a debug target
  (`AtariDebugTarget`, with `AtariDebugTarget.Basic`) and catalog entries. The debugger's memory areas follow the
  cartridge lines, so a breakpoint in BASIC stops only while the cartridge is mapped.
- **`Retrocore.Media`**, which gains `Atari`: `.atr` and `.xfd` disks, `.cas` tapes, `.xex` (binary load) files and
  `.car`/`.rom` cartridges.

## Phases

### 0. Fixtures and references

They are under `%USERPROFILE%\Retrocore` and are never committed. Each folder has a `README.txt` with sources and
SHA-256 hashes. I'll show each download with its site, file and checksum, and wait for approval.

- **`atari8-roms`:** the MAME 0.264 non-merged `a400`, `a800` and `a800pal` sets and the `a810` device set, from the
  same archive.org item as the PET's and the BBC's, with a `mame` ROM path.
- **`atari8-media`:** Atari BASIC revs. A-C from MAME's `a800` cartridge list, and a few `.atr` and `.cas` images from
  its `a800_flop` and `a800_cass` lists, including DOS 2.0S's master disk.
- **`docs\atari8`:** the Hardware Manual, the OS User's Manual, De Re Atari, the 400/800 field service manuals, the
  Atari BASIC Reference Manual, the 810 field service manual, and the 6520, 6532 and FD1771 data sheets, from
  archive.org, with archive.org's OCR text of each.

MAME 0.289 is already in the cache. Its `a800` driver is the trace oracle (with `-sio ""` and no cartridge for the
first traces).

**Built 2026-11-16.** Phase 0 is done.

- **`atari8-roms`** holds MAME 0.264's non-merged `a800`, `a800pal`, `atari810` and `atari1050` zips, each extracted,
  and a `mame` ROM path (with `a400` and `a400pal`, which are the same files).
  - MAME 0.289 calls the OS sets "best available" and the drive sets good. Its `BAD_DUMP` flags on the OS chips say the
    CRCs and labels await confirmation; they don't mark the dumps as wrong. Put together in address order, each OS
    matches the widely circulated 10 KB image's CRC.
  - The PAL OS is rev. A. No PAL rev. B dump exists, so the PAL build in phase 5 is rev. A's.
  - The 810 ROMs are rev. C (9:1 sector skew, MAME's default) and rev. B (12:1). MAME's 810 has the 6507, 6532 and
    FD1771 but no floppy drive attached, so it can't read a disk; phase 4's oracle changed to match.
- **`atari8-media`** holds MAME 0.202's `a800` cartridge list and `a800_flop` list, Atari BASIC revs. A, B and C (each
  matching MAME 0.289's verified hashes), and DOS 2.0S's master disk from archive.org.
  - 446 of 447 cartridge sets and all 39 disk sets that 0.202 has verify against MAME 0.289.
  - MAME boots the master disk to the DOS II menu with its HLE disk (`-sio fdc`).
  - There are no tapes: 0.202 has no tape list, and 0.289's has two games. Phase 3 saves its own.
- **`docs\atari8`** holds the Technical Reference Notes (with the OS User's Manual), the Hardware Manual, De Re Atari,
  the Atari BASIC Reference Manual, the 400/800 and 810 field service manuals, and the R6520, FD1771 and MOS 1982
  (6532) data sheets, with archive.org's OCR text of each.
  - The Technical Reference Notes also contain Atari's OS listing, which is not read, as decision 5 says.

### 1. The machine and its screen

- The bus: RAM sizes, the cartridge slots with `RD4`/`RD5`, the I/O pages and their mirrors, the OS ROM.
- ANTIC: the display list, every mode, fine scrolling, DLIs and the VBI, `WSYNC`, `VCOUNT`, and cycle-exact DMA
  timing, with the CPU halted on the stolen cycles.
- GTIA: the colour registers, players and missiles, priorities, collisions, the console keys, the GTIA modes, and a
  CTIA option.
- POKEY: the keyboard scan, `BREAK`, the timers and IRQs, the pots, the random number generator, and the four audio
  channels with their polynomial counters, filters and 16-bit modes; the console speaker.
- The PIA and joysticks, SYSTEM RESET, and a host key map for the keyboard and console keys.
- The ROMs come from dumps (`romDirectory` or `RETROCORE_ATARI_ROMS`) until phase 5 adds the sources.
- **Done when** both models boot to Memo Pad without a cartridge and to `READY` with BASIC; a typed program runs;
  `GRAPHICS 0`-`11` draw; `SOUND` plays; and instruction traces match MAME's from power-on, cycle counts included.

**Built 2026-11-17.** Phase 1 is done and awaits review. One change from the plan: MAME's ANTIC isn't cycle-exact
(it takes each scan line's DMA in one lump), so the MAME traces check the instructions and registers, and the cycle
timing is checked against the [Altirra Hardware Reference Manual](https://www.virtualdub.org/altirra.html) and Atari's
Hardware Manual instead.

- **What was added:**
  - `Retrocore.Machines.Atari` holds `AtariMachine` (also the `IVideoSource`), `AtariBus`, `Antic`, `Gtia`,
    `AtariPalette`, `AtariKeyboard` with `AtariKey` and `AtariConsoleKeys`, `AtariAudio`, `AtariRoms`,
    `AtariCartridge`, `AtariModel`, `AtariVideoStandard`, `AtariGraphicsChip`, `AtariMemoryArea` and `AtariTiming`.
  - `Retrocore.Core` gains `Pokey`, built by a subagent from the Altirra manual's chapter 5: timers with their
    `N+4` and `N+7` periods and borrow delays, the 64 kHz and 15 kHz clocks' phases, the 4-, 5-, 9- and 17-bit
    polynomial counters and `RANDOM`, the audio channels with distortion, volume-only, high-pass filters and two-tone,
    the keyboard scan with its debounce state machine, the pots, serial transmit and a byte-level receive, and the
    interrupts. Where MAME and Altirra differ it follows Altirra (SHIFT latched at scan code `$10`, the IRQ after the
    borrow, initialization mode leaving `IRQEN` alone).
  - Nothing else changes, apart from the solution and the test project's reference. The 6502 core and the Apple II
    aren't touched, so the PGO profile needs no refresh.
- **The bus:**
  - RAM from `$0000` (48 KB on the 800, 16 KB on the 400 by default), the cartridges unmapping RAM under them (8 KB
    left at `$A000`, 16 KB left at `$8000`, 8 KB right at `$8000` on the 800), the chips mirrored through their pages,
    and the OS ROM.
  - RAM powers on as all ones, and `$C000-$CFFF` reads `$00` and the other empty space `$FF`, as in MAME.
  - The PIA's register selects are wired as the Atari has them: `$D300` PORTA, `$D301` PORTB, `$D302` PACTL,
    `$D303` PBCTL.
- **ANTIC:**
  - The display list with every mode (2-F), blank lines, jumps and JVB, LMS, the 10-bit display list counter and the
    12-bit memory scan counter, vertical scrolling's start and end rows, and horizontal scrolling's wider fetch and
    delay.
  - DMA on the manual's cycles: missiles on 0, the instruction on 1, players on 2-5, the address on 6-7, playfield
    fetches by width and mode (character data three cycles after its name), and refresh from 25 every four cycles,
    put off one at a time. Fetches from cycle 106 on don't take the bus.
  - A DMA cycle halts the CPU for the whole cycle; `WSYNC` holds RDY from the cycle after the next until cycle 105, so
    `INC WSYNC`'s second write still goes through, as on an NMOS 6502.
  - NMIST changes on cycle 7, and the NMI reaches the CPU so its sequence starts on cycle 10 at the earliest. SYSTEM
    RESET raises the reset NMI at vertical blank, so it is a warm start, as on the 400 and 800.
  - `VCOUNT` shows the next line from cycle 111.
- **GTIA:**
  - Two colour clocks a cycle into a 376 × 240 frame (the visible clocks `$22-$DD` of lines 8-247, two pixels a clock,
    so high-resolution modes keep their half clocks).
  - The players' and missiles' shift registers, with sizes and the manual's state machine; the priority logic as the
    manual's gates, so unofficial `PRIOR` values mix and black out as the chip does; fifth player and multicolour.
  - All 60 collision bits, the hires PF1 luminance, GTIA modes 9, 10 (a clock late) and 11, and a CTIA option.
  - Positions and sizes take effect three clocks after the write, graphics registers one clock after; colour
    registers at once (a clock later than the chip).
  - The console keys and speaker, triggers with latching, and the `PAL` register.
  - The palette is a model of the colour encoding, not a measured one.
- **Keyboard:** `Type` queues ATASCII and holds each key three frames, switching CAPS/LOWR when a letter's case
  doesn't match the OS's `SHFLOK`. BREAK, SHIFT, CONTROL, the console keys and SYSTEM RESET are properties.
- **Tests:**
  - `AtariMachineTests`:
    - Memo Pad on both models;
    - `READY` with BASIC revs. A, B and C;
    - a typed program;
    - `GRAPHICS 1`-`11`;
    - the CTIA's lack of GTIA modes;
    - players and their collisions;
    - `SOUND`;
    - the console keys, `STICK` and `STRIG`;
    - BREAK;
    - SYSTEM RESET keeping the program;
    - the PAL machine.
  - `AtariTimingTests`:
    - `WSYNC` releasing on cycle 105, and on the next line for a write on cycle 104 or later;
    - the VBI's sequence starting on cycle 10 or 11;
    - `VCOUNT` on cycle 111;
    - a Graphics 0 frame's DMA at exactly the Hardware Manual's 10,838 cycles;
    - horizontal scrolling's offset;
    - a DLI on its mode line's last line, cycle 7;
    - player DMA.
  - `PokeyTests` (31 cases).
  - `AtariOracleTests`.
- **The MAME oracle:**
  - `tools/AtariOracle.lua` traces MAME's `a800` with `-ramsize 48K -sio ""`, without a cartridge and with BASIC rev.
    C (given as the file: MAME doesn't find `basicc` from its list here).
  - The comparison leaves out interrupts and collapses repeated loops. It also leaves out what reads of `VCOUNT`,
    `NMIST`, `RANDOM`, `IRQST`, `SKSTAT`, `KBCODE` and `CONSOL` gave (`CONSOL`'s speaker bit is the VBI's).
  - Every instruction matches through 4 emulated seconds: about 265,000 rows to Memo Pad and 311,000 to `READY`.
- **Speed:** about 8× real time on a BASIC screen. GTIA's per-clock work is most of it, and can be tuned later.
- **Left for later:**
  - The host key map, the debugger and the Desktop come in phase 6.
  - Serial receive at the bit level and the SIO devices come in phase 2.
  - The light pen, the paddles' wiring to POKEY's pot inputs, and `Render(scanned: false)`. ANTIC's picture depends
    on the CPU's timing, so `Render(scanned: false)` returns the frame as drawn.
  - ANTIC's abnormal DMA cases (mid-line `DMACTL` and `HSCROL` changes beyond the start and stop) and the
    hires-on-line-247 bug.

### 2. The serial bus, cartridges and binary loads

- POKEY's serial port and the PIA's command and motor lines as an SIO bus that devices join.
- A simple SIO disk device that answers `R`, `W`, `P`, `S` and `!` from an `.atr`, so DOS 2.0S boots before the 810
  exists.
- `.car` and `.rom` cartridges in either slot, including the common bank-switched types (OSS, XEGS, Atarimax) as later
  rows.
- `.xex` files loaded by a small boot loader on a virtual disk, as other emulators do, so they run through the OS.
- **Done when** DOS 2.0S boots from its master disk, `DIR` lists, BASIC `SAVE "D:X"` and `LOAD "D:X"` round-trip, and
  an `.xex` and a cartridge game run.

**Built 2026-11-17.** Phase 2 is done and awaits review.

- **What was added:**
  - `Retrocore.Media.Atari`: `AtariDisk`, an `IMedium` of 128-byte (single and enhanced density) or 256-byte
    sectors with the three boot sectors at 128. It reads ATR (double density's padded boot sectors too) and XFD.
    `AtariDiskCodec` saves either; XFD only single and enhanced density.
  - `Retrocore.Machines.Atari` gains `AtariSioBus`, `AtariSioDevice`, `AtariDiskDrive`, `AtariCartridgeType`,
    `AtariExecutable` and `Roms/ExecutableLoader.rom.asm`.
  - `AtariCartridge` now banks.
  - The machine takes `diskDrives` (0-4, none by default, so a machine with no disk still opens Memo Pad), and its
    `Devices` are the drives.
- **The serial bus:**
  - It follows the Altirra manual's chapter 9. While the PIA's CB2 is low, it gathers the five-byte command frame
    from POKEY's `SerialByteSent`, and sorts it out when CB2 rises. A frame with a bad checksum or for no device is
    ignored, as a drive does.
  - The addressed device ACKs or NAKs about 0.6 ms later.
  - A write's data frame is ACKed about 1 ms after its last byte. Complete or Error comes at least 250 µs after the
    ACK, plus the command's time, and a read's data frame follows straight after.
  - The device's bytes reach POKEY one every 932 cycles (19,200 baud) through `ReceiveByte`.
- **The disk drive:**
  - It answers the 810's commands at the command level: Status (the drive status, the inverted 1771 status, the
    format timeout `$E0`), Read, Put, Write and Format. A bad sector number, or anything else, is NAKed.
  - A write to a protected disk gives Error and the write-protect status bits, so BASIC reports error 144.
  - Commands take fixed times: 2 ms for a status, 8 ms for a sector, a quarter of a second for a format.
  - It is an `IDiskDrive` and `IMediumSlot` (ids `d1`-`d4`), with the head's track and sector, the motor, and
    insert, eject, write-protect and save.
- **Cartridges:**
  - The types are numbered as `.car` headers number them: standard 8 KB and 16 KB, right-slot 8 KB, Williams 32 KB
    and 64 KB, Express, Diamond, XEGS 32 KB to 1 MB, Atarimax 128 KB and 1 MB, and OSS 8 KB and 091M, with the banking
    MAME's cartridge devices have.
  - The bus maps `$8000-$BFFF` from each cartridge's `RD4` and `RD5`, so the RAM under a cartridge shows (and keeps
    its contents) when the cartridge turns itself off.
  - `$D500-$D5FF` goes to the cartridges.
- **Binary load files:**
  - `AtariExecutable.BootDisk` builds a write-protected boot disk: our loader in sectors 1-3, then the file. The
    loader is a documented source the ROM generator assembles at build time, as the IIe's slot 7 firmware is.
  - The OS boots it to `$0700`, where DOS boots; it can't go lower, because the OS reads the first sector through its
    cassette buffer at `$0400`. So a file built to load under DOS never loads over it.
  - It reads the file through `DSKINV`, skips `$FFFF` headers, calls `INITAD` after a segment that sets it, and jumps
    to `RUNAD`, or to the first segment's start if no segment set it.
- **Tests:**
  - `AtariDiskTests`:
    - DOS 2.0S boots to DUP's menu and lists its directory (`DOS SYS 039`, `DUP SYS 042`, `AUTORUN SYS 001`, 625
      free sectors);
    - BASIC `SAVE "D:TEST.BAS"`, `NEW`, `LOAD` and `RUN`;
    - error 144 on a protected disk;
    - ATR and XFD round trips;
    - the checksum.
  - `AtariCartridgeTests`:
    - XEGS, Williams (and the RAM showing under it), Atarimax, Express and OSS banking;
    - `.car` headers;
    - Star Raiders and Dropzone (MAME's `a800` list) taking over and drawing their screens;
    - a binary load file with `$FFFF` headers, an `INITAD` segment, `RUNAD`, and a 600-byte segment across five
      sectors.
  - `AtariOracleTests.DosBootMatchesMame`.
- **The MAME oracle:**
  - MAME runs with `-sio fdc`, its command-level drive, and the master disk.
  - Every instruction matches until MAME's drive takes a command frame as bad and answers Error, which a drive
    shouldn't, so its OS retries. That comes after more than 200,000 compared rows, by which point DOS has loaded
    (`DOSVEC` `$179F`).
- **Left for later:**
  - OSS 034M and 043M (BASIC XL, MAC/65 and Action! carts), whose banks AND two chips together, and the rarer types
    in MAME's list (Atrax, SpartaDOS X, Blizzard, Phoenix, SIC!, Turbo).
  - The 850, printers and other SIO devices.
  - The host and Desktop wiring for inserting and saving disks comes with phase 6.
  - Dropzone's title shows a block of colour in the left border on one line, probably mid-line write timing; to look
    at with the 810 phase or when tuning GTIA.

### 3. Tape

- The 410: FSK tones, the motor, and `.cas` images played at the tone level through the OS's own `C:` handler, which
  sets its baud rate from the leader. Saves are written back through the media persistence pipeline.
- **Done when** `CLOAD`, `CSAVE`, `LOAD "C:"` and a boot tape (OPTION-START) work against images MAME reads.

**Built 2026-11-17.** Phase 3 is done and awaits review. One change from the plan: MAME can't load Atari tapes. Its
`a800` cassette takes only WAV, FLAC and AIFF, the driver lists cassette support as a TODO, and its decoder (counting
44.1 kHz ticks between zero crossings, under 5 for a mark) reads some half-cycles of the 5,327 Hz mark as space.
`CLOAD` of our tape as a WAV never finishes there. So the tapes are checked against the OS's own `C:` handler, which
tests every record's checksum, and against MAME's two `a800_cass` tapes, fetched with your OK. The boot tape is held
with START, as the OS has it, not OPTION-START.

- **What was added:**
  - `Retrocore.Media.Atari`:
    - `AtariTape`, an `IMedium` of `AtariTapeBlock`s: a gap of mark tone, then a record's bytes at a baud rate, or a
      run of raw tone.
    - It reads and writes `.cas` (`FUJI`, `baud`, `data` and `fsk ` chunks), and `AtariTapeCodec` saves it.
    - `AtariTapeBuilder` makes the OS's records (two `$55`s, the control byte, 128 bytes, the checksum) and boot tapes.
    - `AtariTapeWave` writes the tape's FSK as a WAV.
  - `Retrocore.Machines.Atari` gains `Atari410`, an `ITapeDrive` and `IMediumSlot` (id `cassette`), the first of the
    machine's devices.
  - `Pokey` receives bit by bit. In asynchronous mode (SKCTL bit 4), timers 3 and 4 are held until a start bit's
    falling edge, then sample each bit's middle. A low stop bit is a framing error (SKSTAT bit 7, cleared by SKRES),
    and SKSTAT bit 1 shows the shift register busy. Synchronous receive on channel 4 works too. `ReceiveByte` stays
    for the disk drive.
- **The 410:**
  - The motor runs while the PIA's CA2 is low and PLAY or RECORD is down.
  - Playing, it puts each block's gap and bits (a 0 start bit, the byte low bit first, a 1 stop bit) on POKEY's serial
    input, which is what the 410 hands the computer once it has decoded the tones.
  - Recording, it keeps the bytes POKEY sends while the motor runs (the OS sends them in two-tone mode). A pause of
    more than four byte times starts a new record, and the baud rate is taken from the bytes' spacing (600 for the
    OS).
  - Recording replaces the tape from where it is. The transport's position and length are in milliseconds.
- **Tests (`AtariTapeTests`):**
  - `CSAVE` onto a blank tape (a ~19.5 s leader, records at 600 baud, an end-of-file record) and `CLOAD` back;
  - `SAVE "C:"` and `LOAD "C:"`, through a `.cas` round trip;
  - a boot tape our test builds, booted with START at power-on: the boot code runs, then `CASINI`, then the OS's
    disk boot times out and it jumps through `DOSVEC`;
  - Serpentine's side A from MAME's list boots: its 82 game records load through the OS's boot and its own loader,
    it stops the tape, and runs from RAM;
  - the `.cas` and WAV formats and the bit timing.
  - `PokeyTests` gains asynchronous receive at 600 baud, with the cassette's timer settings, and the framing error.
  - Checked by hand: Zaxxon (147 blocks, a multi-stage loader that stops and restarts the tape) loads all its records
    and reaches its play screen.
- **Left for later:**
  - Loading WAV recordings, and the `pwm*` chunks of newer `.cas` files.
  - The 410's audio track, which the motor line also powers.
  - The host and Desktop controls (PLAY, RECORD, STOP, rewind and the tape counter) come with phase 6.

### 4. The 810 at the hardware level

- The 810's 6507, `Riot6532` and `Fd1771`, running its ROM, with the drive's mechanics and an `.atr`'s sectors laid out
  on tracks; `.atr` files with bad-sector or timing data for copy protection as later rows.
- The 810 becomes the default disk device; the simple SIO device stays as an option.
- **Done when** phase 2's disk tests pass against the 810, and its power-on traces match MAME's `atari810`. MAME's 810 has no
  floppy drive attached, so disk operations are checked against MAME's HLE `fdc` and the 810 field service manual instead.

**Built 2026-11-17.** Phase 4 is done and awaits review. One change from the plan: the FD1771 isn't moved out of
`Trs80DiskController` into `Retrocore.Core`. Its disks are `Retrocore.Media`'s `FloppyDisk`, which Core can't see, so
the Atari project references the TRS-80's, as the Color Computer already does for its WD1793. Moving it would be a
refactor of its own.

- **What was added:**
  - `Retrocore.Core`: `Riot6532` and `RiotBase`, copied unchanged from the PET branch, so whichever branch merges second
    takes the same files.
  - `Retrocore.Machines.Atari`:
    - `Atari810`, the drive, with `Atari810Bus` (its memory map) and `Atari810Disk` (an image laid out on tracks).
    - `Atari810Firmware`, which finds MAME's `atari810` chips (revision C, else B) and tells the revisions apart by
      CRC.
    - `AtariDiskDrive` is now the drives' shared base. Phase 2's command-level drive is `AtariSioDiskDrive`, and its
      SIO interface is the internal `IAtariSioDevice`.
    - `AtariDiskDriveKind` picks the drive: `Atari810` (the default) or `CommandLevel`. `AtariRoms` carries the
      810's firmware; `LoadFromDirectory` looks for it in an `atari810` folder beside the OS's.
  - `Trs80DiskController` gains `rotationsPerMinute` and `sensorsWired`. With the sensors unwired, the index pulse
    comes from outside, the head is stepped from outside, READY is always true, and an empty drive searches until the
    index pulses time it out.
  - Two fixes there, both from the FD1771 manual:
    - Write Track raises DRQ as soon as it's issued, and ends with lost data if no byte is loaded by the index.
    - A Force Interrupt during Write Track keeps what was written; the 810 ends each track that way.
- **The drive** follows the Altirra Hardware Reference Manual, 10.10:
  - The 6507 runs at 500 kHz, with no interrupts, beside the computer.
  - The RIOT's port A reads DRQ, INTRQ, write protect and the drive-number switches, and runs the spindle motor.
  - Port B reads the computer's serial data (inverted), the command line and the computer's power, drives the
    stepper's four phases, and sends the drive's serial data, which the firmware shifts out bit by bit.
  - The serial data reaches POKEY's bit-level receive from phase 3: the bus ANDs every device's level onto the line.
  - The RIOT's interrupt output is the FD1771's index pulse, and the firmware steps the head itself.
  - The disk turns at 288 rpm. The FD1771's data bus is inverted, so the tracks hold the image's bytes inverted, and
    what the controller writes goes back to the image when its command ends.
  - The drive is switched on when it's built and runs its start-up first: it steps out 40 tracks to find track 0,
    then parks on track 39.
- **Found from the firmware, not the manual:**
  - The computer's power line (PB1) reads low while the computer is on; the manual's table has it the other way.
  - Its track numbers are kept inverted, so its start-up steps out to the stop, then back in to 39.
  - Revision C formats a track as 18, 1, 3, …, 17, 2, …, 16, and revision B as 18, 7, 14, 3, … (13:1). The
    OCR'd table 53 had its labels a row off; each firmware's own table, after its reset code, settles it.
- **Tests:**
  - Phase 2's DOS boot, directory, BASIC `SAVE`/`LOAD` and write-protect tests run against both drives. An 810
    command takes real time (a BASIC save is about 4 s), so the tests wait for each command to finish.
  - `Atari810Tests`:
    - DOS 2.0S's `I` formats a blank disk: about 10 s to write the 40 tracks and 25 s to read them back. Every
      track is in revision C's order, and DOS's VTOC shows 707 free sectors.
    - Each firmware's order table matches the layout.
    - The drive parks on track 39 with its motor off.
    - An empty drive times out, and the OS prints `BOOT ERROR`.
  - `AtariOracleTests.Atari810PowerOnMatchesMame`:
    - MAME's `a800 -sio a810` traces the drive's 6507 (`tools\AtariOracle.lua` takes `RETRO_CPU`, and sets the
      debugger's visible CPU so the trace logs that CPU's registers).
    - Every instruction and register matches through the start-up: the RIOT and FD1771 set up, and the 79 steps,
      each timed by the RIOT.
    - It stops at the firmware's first read of port A. From then on MAME's port A reads `$FF` (write-protected,
      with DRQ and INTRQ always high), since its 810 has no floppy drive.
    - One read is masked: bit 7 of a port B read shows the computer's data-out line. That line changes when the OS
      first sets SKCTL, some milliseconds apart in the two machines, since MAME's ANTIC takes its DMA in lumps.
  - `DosBootMatchesMame` keeps the command-level drive, since MAME's `fdc` is one.
- **Speed:** the 810's 6507 runs all the time, so a machine with a drive runs at about 5× real time, down from 8×.
- **Left for later:**
  - `.atr` files with bad sectors, weak sectors or timing, for copy protection (the `.atr` header has no room for
    them; APE's and Altirra's extensions do).
  - Revision E's download commands.
  - Letting an idle drive sleep, for speed.
  - Moving the FD1771 into `Retrocore.Core`, if the TRS-80 and the Atari should share it more cleanly.

### 5. ROM sources

Stage by stage, each with its review:

1. **The OS (`Os.asm`, rev. B, with rev. A and PAL as `VERSION` builds).** Power-up and SYSTEM RESET, the NMI and IRQ
   dispatch, the vertical blank routines and timers, CIO and its handlers (`E:`, `S:`, `K:`, `P:`, `C:`), SIO, the
   disk interface, the boot paths, and Memo Pad.
2. **The floating point package (`FloatingPoint.asm`)**, its own chip with its own entry points (`AFP`, `FASC`,
   `FADD`, `FMUL`, `PLYEVL` and the rest).
3. **The character set (`CharacterSet.asm`)**, as data in the OS chip, with each glyph drawn in its comment, as
   `CharacterGenerator.asm` does for the TRS-80.
4. **Atari BASIC (`AtariBasic.asm`, rev. C, with A and B as `VERSION` builds).** The editor and its syntax tables,
   the tokenizer, the execution loop, the statements and functions, and the string and array handling.
5. **The 810 firmware (`Atari810.asm`).**

Every source has `;;` documentation and IntelliSense, as the Apple II's sources have, with `Inherit:` entry files
for what BASIC and DOS call. Tests pin every build by digest, and without dumps the machine runs the SDK's builds.
**Done when** every build is byte-identical to its chip, `SdkDocumentationIsClean` passes, and the machine boots from
the SDK's builds.

**Stage 1 built 2026-11-17, awaiting review.** The OS is `src/Retrocore.Machines.Atari/Roms/Os.asm`, which includes
`OsEquates.asm` and sixteen parts in `Roms/Os` in ROM order (CharacterSet, Vectors, Cio, Interrupts, Sio, Disk,
Printer, Cassette, Reset, Editor, Keyboard, ControlCodes, Screen, Draw, Tables, KeyboardInterrupt), about 6,600 lines.

- **Builds:** `VERSION` selects `VERSION_B` (the default), `VERSION_A` or `VERSION_PAL`, and each assembles
  byte-identically to its two chips. Rev. B's code is the main line, with rev. A's in `.if` blocks, mostly in the
  interrupts and SIO. PAL is rev. A with its timing constants changed for 50 Hz frames. Every part starts at the same
  address in all three builds.
- **Names:** the vectors, the database and the registers keep Atari's published names, and `OsEquates.asm` documents
  each from the OS User's Manual's appendix L and the Hardware Manual. Every other label is named for what it does. The
  manual's `BOOT?` is `BOOTQ`. The OS listing in the Technical Reference Notes wasn't read: the work used a copy of the
  manual cut off before it.
- **Tests:** `AtariOsSourceTests` pin the three builds' digests, compare each with its dump, start an 800 from rev. B's
  build (with the FP chip from the dump) to Memo Pad, and run the lint. Rev. A's branches lint clean too.
- **Left for later stages:**
  - The character set was raw bytes; stage 3 drew the glyphs (built).
  - The FP chip was stage 2 (built; the machine now starts from the two SDK builds alone).
  - The SDK copy and entry files (`Inherit:` for BASIC and DOS) came with stage 4, as the BBC's did.
- **What rev. B changed** (in `Os.asm`'s comment):
  - The IRQ handler scans a table and adds BRKKY. Rev. A never reached VTIMR4, and every unclaimed IRQ went to VBREAK.
  - SETVBV waits on WSYNC instead of turning the NMIs off. Rev. A left display list interrupts off.
  - The vertical blank enables IRQs later, and SIO sets TIMFLG after starting its timer.
  - The memory test no longer takes 1 from RAM at $BFFC on each SYSTEM RESET.
  - The chips' checksums are dropped. Rev. A's $E000 chip keeps its sum in two handler tables' pad bytes, and its
    $F000 chip at $FFF8. Rev. B's $FFF8 word, $E6F3, is no sum found, and is kept as data.
- **Where the code and the manuals differ,** the source follows the code and says so:
  - The manual's SETVBV masks display list interrupts, which only rev. A does.
  - The printer's 'W' (wide) mode falls through to normal.
  - Opening the cassette in an invalid mode gives FNCNOT, not NVALID.
  - Only 'W' writes get the send direction, which is why plain 'P' writes don't work through DSKINV.
- **Bugs found in the code,** documented in the source (the first two confirmed against the code):
  - A right cartridge without its run bit sends the start-up back to the disk boot forever.
  - Clear screen writes whole pages to RAMTOP, so it clears 64 bytes past RAMTOP in mode 0.
  - SIO reports a NAK'd data frame as a timeout, after DTIMLO seconds.
  - Insert line always shifts rows down to row 23, even in a split screen's 4-line window.

**Stage 2 built 2026-11-17, awaiting review.** The floating point package is
`src/Retrocore.Machines.Atari/Roms/FloatingPoint.asm`, which includes `OsEquates.asm` and three parts in
`Roms/FloatingPoint` (Conversion, Arithmetic, Functions), about 1,700 lines. The chip is the same in every OS, so there
is one build.

- **Names:** the 22 entry points keep the manual's names (`AFP`, `FASC`, `IFP`, `FPI`, `ZFR0`, `ZF1`, `FSUB`, `FADD`,
  `FMUL`, `FDIV`, `PLYEVL`, the loads and stores, `FMOVE`, `EXP`, `EXP10`, `LOG`, `LOG10`), each with full `In:`,
  `Out:`, `Errors:` and `Uses:` for BASIC's source to inherit. `OsEquates.asm` gained the package's registers and
  buffers from appendix M, and the number's format.
- **The tables BASIC uses by address are named:**
  - the coefficient tables `EXP_COEFFICIENTS`, `LOG_COEFFICIENTS` and `ATN_COEFFICIENTS` (`$DFAE`, which the package
    itself never reads);
  - the constants `FP_ONE`, `FP_HALF`, `FP_SQRT10`, `FP_LOG10_E` and `FP_PI_OVER_4`.

  The tables are written with an `FP_NUMBER` macro, each value in its comment.
- **Tests:** `AtariFloatingPointSourceTests` pin the digest, compare with the dump, run the lint, and start an 800
  from the SDK's two builds alone, with no dumps, to Memo Pad.
- **Where the code and the manual differ:**
  - `LOG` never reports an error except for a negative number.
  - FPI returns 0 without an error from 65535.5 up to 65536, and rounds numbers below 0.01 on their first digit, so
    0.005 gives 1.
  - AFP keeps nine significant digits and drops the rest unrounded. It skips leading spaces, and on failure leaves
    CIX past what it tried.
  - FMUL and FDIV report results below about 1E-130 as overflow. Between that and 1E-98 they give zero.
  - FADD, FMUL and FDIV truncate rather than round.
- **Unexplained:** the ten bytes at `$DFF6` (`98 16 34 FC E0 32 50 D9 68 11`). Nothing reads them. The first three
  repeat the end of pi/4, and they are kept as data.

**Stage 3 built 2026-11-17, awaiting review.** `Roms/Os/CharacterSet.asm` draws the 128 characters with `GLYPH` and
`ROW` macros, eight rows of eight dots each, as `CharacterGenerator.asm` does for the TRS-80. Each glyph is in ANTIC's
internal order, under a heading for its group, and its comment gives its ATASCII code and name. `GLYPH` asserts each
character's place. The set's start is now the label `DISPLAY_CHARACTER_SET`, replacing the editor's equate. Rev. A,
rev. B and the PAL OS have the same characters, so there are no `VERSION` branches. The stage 1 tests cover it: the
three builds still match their digests and dumps, and the lint is clean.

**Stage 4 built 2026-11-17, awaiting review.** Atari BASIC is `src/Retrocore.Machines.Atari/Roms/AtariBasic.asm`,
which includes `OsEquates.asm`, `OsEntries.asm`, `FloatingPointEntries.asm`, `BasicEquates.asm` and ten parts in
`Roms/AtariBasic` (Editor, Syntax, Execution, Expressions, Functions, Statements, List, Control, Devices,
InputOutput), about 8,100 lines.

- **Builds:** `VERSION` selects `VERSION_C` (the default), `VERSION_B` or `VERSION_A`, each byte-identical to its
  cartridge. Rev. B is rev. C with three small branches; rev. A has its own branches throughout, with routines where
  rev. A has them. `AtariBasic.asm`'s comment lists what each revision changed.
- **Names:** Atari's documents name the zero page pointers (`LOMEM`, `VNTP`, `VNTD`, `VVTP`, `STMTAB`, `STMCUR`,
  `STARP`, `RUNSTK`, `STOPLN`, `ERRSAV`, `PTABW`, `RADFLG`); BASIC's `MEMTOP` is `BASIC_MEMTOP`, since the OS has its
  own. Everything else is named by what it does: the tokens (`TOKEN_`, `OP_`, `FN_`), each statement's, operator's
  and function's routine (`STATEMENT_PRINT`, `OPERATOR_ADD`, `FUNCTION_SIN`), the error entries (`DIM_ERROR`...).
- **The syntax tables** read as a grammar: 83 rules (`RULE_PRINT`...), each with its grammar in a comment, written
  with `FAR`, `NEAR`, `ROUTINE`, `OR`, `RETURN`, `MATCH`, `MATCH_HERE`, `REPLACE` and `EXPRESSION` macros. The name
  tables, both execution tables (`.dbyt NAME-1`) and the precedence table are records checked against the tokens.
- **Shared files:** `OsEntries.asm` (the OS's jump vectors) and `FloatingPointEntries.asm` (the FP package's routines,
  five undocumented ones BASIC calls, and its tables) inherit their documentation from `Os.asm` and
  `FloatingPoint.asm`. `FP_NUMBER` and the cartridge flags moved into `OsEquates.asm`. `Retrocore.Debug.csproj` copies
  the Atari sources into `Sdk\Roms\Atari`.
- **Tests:** `AtariBasicSourceTests` pin the three digests, compare each build with its cartridge, lint each build
  (with the OS's and FP package's sources for inherited names), and run a typed program on rev. C's and rev. A's
  builds over the SDK's OS and FP builds, with no dumps.
- **Bugs, confirmed on the machine:** `1 AND 0.01` is 0 (AND tests the exponent bytes against each other); `STR$(1)=
  STR$(2)` is true (one buffer); rev. A's `SGN(-0)` is -1 and its `2^3` is 7.99999991. After an error BASIC prints no
  READY.
- **Bugs from the code, not run:** rev. B's memory mover (insertion, whole pages) and LOAD (+16 bytes), fixed in rev.
  C; SIN and COS keep too few digits of a large argument's remainder; SQR returns the guess before its last step; an
  error line that adds 32 or more new variables takes the wrong number of bytes back out; a typed line can overrun
  LBUFF; IOCB numbers wrap (`#16` is IOCB 0); RETURN accepts LIST's and READ's entries, which they push to come back.
- **Unexplained:** the two NOPs rev. B added at the cassette's open, and rev. A's 96 bytes at `$BF99`, which look
  like bitmap data. The 9 unreached bytes at `$BDDB` are a stale copy of rev. A's line-input prompt.

**Stage 5 built 2026-11-17, awaiting review.** The 810's firmware is
`src/Retrocore.Machines.Atari/Roms/Atari810.asm`, one file of about 1,700 lines with its equates. Phase 5 is complete.

- **Builds:** `VERSION` selects `VERSION_C` (the default) or `VERSION_B`, each byte-identical to its ROM. The two
  differ only in the format's sector order (`FORMAT_ORDER`) and the order its verify reads a track back.
- **Names:** no document names the firmware's routines or variables, so all are named by what they do: the
  command frame (`FRAME_DEVICE`, `FRAME_COMMAND`, `FRAME_AUX1`...), the status block (`DRIVE_STATUS`,
  `CONTROLLER_STATUS`...), the flags (`FLAG_...`), the commands (`COMMAND_READ_SECTOR`, `COMMAND_FORMAT_DISK`...).
  The FD1771's and the 6532's registers and lines follow the Altirra Hardware Reference Manual's tables 60 and 61.
- **The inverted bus:** each FD1771 command and Write Track mark is written as the controller sees it, complemented
  where it's stored (`lda #<(~FDC_READ_SECTOR)`), and so are the firmware's track and sector numbers.
- **Tests:** `Atari810SourceTests` pin both digests, compare each build with its ROM, lint both builds, check the
  emulator's layout against each build's order table, and boot a disk built in the test on the SDK's OS, FP and 810
  builds, with no dumps: the drive reads the boot sector, then parks on track 39 with its motor off.
- **Found in the firmware:**
  - Both revisions accept `$4F` (`O`) as Write: the dispatch's range starts at `$4F`, and its low bits are `W`'s.
  - The motor's run-on after a command is two FD1771 Restores, used as a timer: with nothing wired to its stepper or
    track 0 input, each runs until the controller gives up. Our FD1771 ends a Restore at once when its sensors aren't
    wired, so the emulated motor stops sooner than a real one would. Left for later, with the FD1771's timing.
  - A Status returns the last command's drive status, then clears all but the write-protect bit; each disk command
    sets it to "motor on" first.
  - A read that can't find its sector on the third try recalibrates: steps out 44 times and back.
  - The format's verify reads every fourth sector of a track, from track 39 down to 0, two tries each.
- **Unreached:** six bytes left between routines (`$60`, `$AD`, `$B0 $00`, `$60`, `$01`), kept as data.

### 6. The debugger and extension

- `AtariDebugTarget`: source-level debugging of the OS, the FP package, cartridges and user programs, with breakpoints
  that respect the cartridge mapping, a display list view, and the 810 as a second CPU.
- BASIC debugging, as AppleSoft and Color BASIC have it: `AtariBasicDialect` tokenizes and lists programs, with
  breakpoints on lines and the variables from the name and value tables.
- The extension's `atari800` entries, launch configuration, and Start Machine with a program, a BASIC file, an `.xex`,
  a cartridge, a tape or a disk.
- The Desktop's catalog entry, icon and key map, including START, SELECT, OPTION, BREAK and SYSTEM RESET.
- A `docs/Atari800.md` guide, the README's machine list, and the extension README.
- **Done when** a breakpoint in the OS, one in BASIC's cartridge and one on a BASIC line all stop. Start Machine runs a
  BASIC file, an `.xex` and a disk.

**Built 2026-11-18, awaiting review.** Phase 6 is done in three stages, as the BBC Micro's was: the BASIC dialect,
the debug target, then the extension, the Desktop and the docs. Two items are left for later, below.

- **Atari BASIC's dialect** (`Retrocore.Basic`):
  - `AtariBasicSyntax` is the line editor's syntax checker ported step for step. It runs over the ROM's own table bytes,
    `$A49F-$A879`: the statement names, the grammar and the operator names. It has its syntax routines for names,
    numbers and strings, so `=` is tokenized as a comparison, a numeric assignment or a string's, as the ROM does.
  - `AtariNumbers` and `AtariAfp` are the floating point package's AFP, FASC and FPI, so constants read and list as
    the ROM reads and lists them.
  - `AtariBasicDialect` reads and writes the variable name and value tables and the statement table, and SAVE's file
    format. It lists as LIST does. Each program has a dialect of its own that carries its variable names, since a
    line's variable tokens are numbers into the program's name table; parsing a file numbers its variables in the
    file's order, as typing it would.
  - `BasicVariables` reads the value table: numbers, strings, and arrays with the second subscript fastest. It reads
    FOR loops from the run-time stack. `AtariBasicExpression` evaluates watches, with rev. C's precedence.
  - `AtariBasicDialectTests` types a broad program on an 800 running the SDK's builds and checks that the tokens and
    the variable names are the ROM's, byte for byte. It also checks that LIST and PRINT write what the dialect
    writes, and that a written program runs.
- **The debug target** (`AtariDebugTarget`, `machine: "atari800"`):
  - The OS, the floating point package and each cartridge slot are memory areas of their own, so `Os.asm`'s,
    `FloatingPoint.asm`'s and `AtariBasic.asm`'s modules apply only where their ROM is. Each is known by its build's
    digest.
  - Atari BASIC's thread hooks the execution loop's `EXECUTE_STATEMENT`. GOSUBs come from the run-time stack and
    errors from `HANDLE_ERROR`, with TRAP counted as handled.
  - Launch options cover the model, video, OS, chip, RAM, BASIC's revision, cartridges, drives (the 810 or SIO),
    disks, an `.xex` and a tape. Without dumps every ROM is built from the SDK's sources.
  - WSYNC's RDY hold is the target's `IsHeld`, so the debugger's instruction budget waits it out.
  - Keys above 127 hold START, SELECT, OPTION, BREAK and SYSTEM RESET; `retro/key` now takes 0-255, as the BBC's
    branch has it.
  - `tools/Test-AtariDap.mjs` (in CI) shows what was required: breakpoints in `Os.asm`, in `AtariBasic.asm` and on a
    BASIC line all stop, and the machine runs a BASIC file, an `.xex`, a disk booted through the 810 and the 6502
    sample, `sample/atari/hello.asm`. The native AOT smoke test runs an Atari too.
- **The Desktop:** the Atari 800 and 400 in the catalog, with the key map (F2-F4 START, SELECT and OPTION; Pause
  BREAK), the panel's buttons, the icon and the screen shape.
- **The extension:** the Atari 800 and 400 entries, the launch options, snippets, the Atari BASIC language
  (`retrocore-atari`, `.atari.bas`) with a generated grammar, the display panel's keys, and Start Machine with a
  program, a BASIC file, an `.xex`, a cartridge, a tape or a disk. Its grammar finds statement names where a statement
  starts, and operator and function words only where the tokenizer would. The display panel's Sound button now sends
  `retro/sound`, which the host forwards to the machine; this also fixes the Color Computer's button, which sent
  `apple2/sound`.
- **Docs:** `docs/Atari800.md` is the machine's guide, and the README lists the machine, its sources and its tests.
- **Left for later:**
  - The 810 as a second CPU in the debugger. The coprocessor model, as the SoftCard has it, hands the bus from one CPU
    to the other, while the 810's 6507 runs beside the computer's 6502 all the time. It needs a second thread.
  - A display list view, beyond the memory views and the `Os.asm` names for ANTIC's registers.
  - Hover help for Atari BASIC's words in `Keywords.txt`.

### 7. Later

- The XL and XE (the 6502C SALLY, the XL OS with its self-test, built-in BASIC, banked RAM in the 130XE) and the 1050.
- Atari DOS 2.0S sources, as DOS 3.3's were done.
- The 850 interface, printers, and `.atr` copy protection.
