# Backlog: the Commodore VIC-20, 64 and 128

Status: **agreed 2026-11-25** ("Start phase V1"). Phases V1 to V4 are built and land in the pull requests that follow
this plan, each adding its phase's notes: the machine, tape and cartridges (V1, V2), the drives (V3), then the ROM
sources (V4).

Commodore's three home computers after the PET share most of what they are made of: a 6502 family processor,
Commodore BASIC 2 (7.0 on the 128), a kernal with the same jump table, the Datasette, and the serial bus with the
1540, 1541 and 1571 drives on it. Each adds its own video and sound chip, and the 64 and 128 add CIAs and the SID.

| Machine | Year | Processor | Video | Sound | What is new to Retrocore |
| --- | --- | --- | --- | --- | --- |
| VIC-20 | 1980 | 6502 at 1.02 MHz (NTSC) or 1.11 MHz (PAL) | VIC 6560/6561, 22 × 23 characters, colour RAM | In the VIC: three square voices, noise | The VIC chip, the serial bus, the 1540 and 1541, cartridges and RAM expansions |
| Commodore 64 | 1982 | 6510 at 1.02 MHz (NTSC) or 0.99 MHz (PAL) | VIC-II 6567/6569, 40 × 25, bitmaps, eight sprites | SID 6581 | The 6510's port, the PLA's banking, the VIC-II's cycle stealing, two CIAs, the SID, `.crt` cartridges |
| Commodore 128 | 1985 | 8502 at 1 or 2 MHz, and a Z80 | VIC-IIe for 40 columns, VDC 8563 for 80 | SID | The MMU, two processors on one bus, the VDC, C64 mode, CP/M 3.0, the 1571 |

The goal is the Apple IIe's level of support, for each machine:

- the models and their ROMs, built from byte-identical SDK sources in the maintained style
  ([ConvertingSources.md](../ConvertingSources.md));
- the video, keyboard, joysticks and paddles, sound, tape, cartridges and disks;
- the debugger at source level and at BASIC level;
- the extension, Start Machine and the Desktop;
- media that saves;
- MAME traces as the oracle.

The VIC-20 is first and is finished, through the debugger and clients, before the 64 starts. The 64 is finished
before the 128 starts, since the 128 contains a 64.

## What the PET already gives

The PET's work ([Pet.md](Pet.md)) is most of the groundwork:

- **The 6502 core**, with undocumented opcodes, RDY that holds reads only (as the VIC-II's BA needs), and SO (as the
  1541's byte-ready line needs). No core change is expected; the 6510's port is on the bus.
- **`Via6522`**: the VIC-20 has two, the 1540/1541 two, the 1571 two.
- **The shared Commodore BASIC modules** behind `Basic2.asm`. The VIC-20's and the 64's BASIC are BASIC 2 with
  other I/O, so each is a new root over the same modules.
- **`Retrocore.Media.Commodore`**: `CommodoreTape`, `TapFormat` (which already reads the VIC's and 64's clocks),
  `CommodoreWave`, `CommodoreTapeBuilder`, `CommodoreDisk`, `GcrLayout`, `D64Format` and `G64Format`. The 1541 writes
  the 4040's format, so a `.d64` is the same image.
- **`CommodoreDatasette`** (the PET's `PetDatasette`, renamed for the VIC-20 to share), counting its tape in the machine's cycles.
- **`Cbm4040Fdc`**, whose GCR read and write logic is the model for the 1541's gate array.
- **`PetBasicDialect`**, whose BASIC 2 tokens are the VIC's and the 64's exactly.
- **`WesternDigitalFloppyDiskController`**, which gains the WD1770 for the 1571.
- **The Z80 core and CP/M experience** (SoftCard, Kaypro), for the 128's CP/M mode.

## The hardware

From MAME's `vic20`, `c64` and `c128` drivers, Commodore's programmer's reference guides and schematics, and the
chips' data sheets. Each machine's first phase confirms its rows.

### VIC-20

| Part | What it is |
| --- | --- |
| CPU | 6502 at 1.0227 MHz (NTSC, 14.318 MHz / 14) or 1.1084 MHz (PAL, 4.434 MHz × 4 / 16). |
| RAM | 5 KB: 1 KB at `$0000-$03FF` and 4 KB at `$1000-$1FFF`, with the screen at `$1E00`. 3,583 bytes free. |
| Expansion | 3 KB at `$0400-$0FFF` (VIC-1210), and 8 KB blocks 1-3 at `$2000-$7FFF` (VIC-1110, VIC-1111). Block 5 at `$A000-$BFFF` is the cartridge's, and cartridges that start with `A0CBM` start themselves. With 8 KB or more the screen moves to `$1000`. |
| Character ROM | 4 KB at `$8000` (901460-03): upper case and graphics, and upper and lower case, each with reverse video. |
| VIC | 6560 (NTSC) or 6561 (PAL) at `$9000-$900F`. Sees 16 KB of its own, mapped onto the CPU's with A13 inverted, so it can show RAM at `$1000-$1FFF` and the character ROM, but not the expansion. Screen size, origin and character height (8 or 16) are registers. Colour RAM is 1 K × 4 bits at `$9400`. Sound: three square-wave voices an octave apart, noise, and a volume. Two paddles (POTX, POTY) and a light pen. |
| VIA 1 (`$9110`) | NMI. RESTORE on CA1, the serial bus's ATN out and its CLK and DATA in, joystick up, down, left and fire, the cassette sense and motor, and the user port. |
| VIA 2 (`$9120`) | IRQ. The keyboard matrix (8 × 8), the jiffy timer, the cassette read and write, the serial bus's CLK and DATA out, and joystick right. |
| Video | NTSC: 65 cycles × 261 lines. PAL: 71 cycles × 312 lines. 16 colours, with a border, a background, and a per-character colour from colour RAM; multicolour characters. |
| ROMs | BASIC 2 at `$C000` (901486-01), the kernal at `$E000` (901486-06 NTSC, -07 PAL). |
| Serial bus | ATN, CLK, DATA (and SRQ, unused by the VIC). Devices 4-30; drives at 8. |

### Commodore 64

| Part | What it is |
| --- | --- |
| CPU | 6510: a 6502 with a six-bit port at `$00`/`$01`. Bits 0-2 (LORAM, HIRAM, CHAREN) choose the banking, bits 3-5 the cassette write, sense and motor. |
| RAM | 64 KB, with 38,911 BASIC bytes free. |
| Banking | The 906114-01 PLA, from the port's three lines and the cartridge's GAME and EXROM, maps BASIC (`$A000`), the kernal (`$E000`), the I/O or character ROM (`$D000`) and the cartridge's ROML and ROMH, including the Ultimax mode. MAME has the PLA's fuse dump, so its logic can be checked exactly. |
| VIC-II | 6567 (NTSC: R8 has 65 cycles × 263 lines; the early R56A 64 × 262) or 6569 (PAL: 63 × 312). Sees one of four 16 KB banks, chosen by CIA 2. Text, bitmap, multicolour and extended colour modes, eight sprites with collisions, raster interrupts, smooth scrolling. Halts the CPU through BA and RDY on bad lines (40 cycles) and for sprite fetches. |
| SID | 6581: three voices of four waveforms with ADSR envelopes, ring modulation and sync, a multimode filter, a volume, and two paddle inputs. The 64C has the 8580. |
| CIA 1 (`$DC00`) | IRQ. The keyboard matrix, both joysticks, the paddle select, the jiffy timer, and the cassette read on FLAG. |
| CIA 2 (`$DD00`) | NMI. The serial bus, the VIC-II's bank, the user port and RS-232. RESTORE is wired to NMI as well. |
| ROMs | BASIC 2 at `$A000` (901226-01), the kernal at `$E000` (901227-01, -02 or -03, -03 the last), the character ROM (901225-01). |
| Expansion port | Cartridges: 8 KB, 16 KB and Ultimax, and bank-switched types in the `.crt` format. |

### Commodore 128

| Part | What it is |
| --- | --- |
| Processors | 8502 (a 6510 that can run at 2 MHz) and a Z80 at 4 MHz, which runs with wait states at about 2 MHz. One runs at a time; the MMU switches them. |
| RAM | 128 KB in two 64 KB banks, with shared "common" RAM at either end and relocatable zero and stack pages. 122,365 BASIC bytes free. |
| MMU 8722 | The configuration register and its four presets, the mode (C128, C64, Z80), the common RAM, the page pointers, and the 40/80 key and the GAME and EXROM lines. With the 8721 PLA, which MAME has only as a bad dump, so it is built from the equations. |
| VIC-IIe | 8564 (NTSC) or 8566 (PAL): the VIC-II with two more keyboard lines and the 2 MHz bit. At 2 MHz the 40-column screen goes blank. |
| VDC 8563 | 80 × 25 RGBI from its own 16 KB of RAM (64 KB on the 128DCR), reached through two registers. Its own character set, attributes, block copy and fill, smooth scrolling and bitmaps. |
| SID, CIAs | As on the 64. CIA 1's serial port drives the fast serial bus. |
| Keyboard | The 64's matrix with the keypad and extra keys (ESC, TAB, ALT, HELP, LINE FEED, NO SCROLL, the cursor keys, 40/80, CAPS LOCK). |
| ROMs | BASIC 7.0 low and high (318018 and 318019), the kernal with the screen editor, the monitor and the Z80 BIOS (318020), the C64 ROMs (251913-01), and the character ROM (390059-01). Revisions -02/-03 (1985) and -04/-05 (1986). |
| 1571 | A 6502, two VIAs, a CIA for the fast serial bus, a WD1770, and the 1541's GCR logic. Double-sided: 340 KB as `.d71`, and MFM for CP/M disks. It runs as a 1541 on a VIC-20 or 64. |

## Answered questions

Answered 2026-11-25:

1. **Commodore's listings: the PET's rule.** Commodore's own listings survive for the VIC-20's and 64's BASIC and
   kernals, the 128's BASIC 7.0, kernal, editor and monitor, and the 1540, 1541 and 1571 DOS. Every source is our own,
   written from the dumps; the listings give names only, kept as `;; Also:`.
2. **NTSC is the default**, with PAL an option on every model, both tested from each machine's first phase.
3. **The 128's CP/M mode is in the plan**, as its own phase after C128 mode, C64 mode and the 1571.
4. **Every drive's DOS becomes a source**: the 1540 and 1541 after the VIC-20's ROMs (phase V5), the 1571 with the
   128's (phase D5).

## Proposed decisions

1. **The project and ids.** All three join `Retrocore.Machines.Commodore`, in folders `Vic20`, `C64` and `C128`, with
   the shared serial bus and drives in `Serial`. The machine ids are `vic20`, `c64` and `c128`; `model` names the
   variant, as `pet` does.
2. **The models.**
   - `vic20`: `ramExpansion` none (the default), 3K, 8K, 16K, 24K, or 3K plus 24K (32K), and `video` ntsc or pal.
   - `c64`: `video` ntsc (6567R8), ntsc-r56a (the early 6567R56A) or pal (6569); `kernalRevision` 3 (the default), 2 or 1; `sid` 6581 or 8580.
   - `c128`: `video` ntsc or pal; `romRevision` 1986 (the default) or 1985. C64 mode and CP/M mode are how it runs,
     not models.
3. **The chips are shared parts.** `Cia6526`, `Sid` and `Vic6560` go into `Retrocore.Core`'s chips beside `Via6522`
   and `Pokey`; the VIC-II and VDC stay in the Commodore project, since only it uses them.
4. **The SID is our own model**, written from the data sheet and Commodore's and Bob Yannes's descriptions, and
   checked against MAME's output and recordings of real chips. reSID, which MAME and VICE use, is GPL and Retrocore
   is MIT, so it is not ported or followed. The filter is the hard part: phase C1 builds it to the data sheet's
   curves, and a closer model of the 6581's distortion is in Later.
5. **The drives at the hardware level.** The 1540, 1541 and 1571 run their own DOS on an emulated 6502, as the 4040
   does. Fast loaders, which most 64 software uses, upload code to the drive, so a trap-based virtual drive would not
   run them. A "fast disk" option that skips the drive's motor and seek waits can come later if loading is too slow.
6. **The sources** are in the maintained style: names that say what a thing is, and Commodore's published names
   (the reference guides' and *Mapping the VIC*'s and *Mapping the 64*'s labels, and the listings' names) as
   `;; Also:`. BASIC 2 for the VIC-20 and the 64 are roots over the shared Commodore modules. The kernals for each
   machine are one source per machine with switches for their revisions and video standards.
7. **The dialect.** `petbasic` becomes `cbmbasic`, which names every version (2, 4 and 7.0), with `petbasic` kept as
   an alias. A running machine reads and writes programs with its own version, as now. BASIC 7.0 is new tokenizing
   (two-byte tokens behind `$CE` and `$FE`) and gets its own conformance test against the 128's CRUNCH.
8. **The oracles.** MAME 0.289's `vic20`, `vic20p`, `c64`, `c64p`, `c128` and `c128p`, and its `c1541` and `c1571`,
   for traces. For the VIC-II's and SID's timing, public test programs (Wolfgang Lorenz's 6510 suite and the VICE
   test programs, run as fixtures, never committed) where MAME's timing is known to differ, as Altirra was for the
   Atari.
9. **Each phase ends in a review** before the next one starts. Source phases have a review after each ROM.

## Phases

### 0. Fixtures and references

They are under `%USERPROFILE%\Retrocore` and are never committed. Each folder has a `README.txt` with sources and
hashes.

**Fetched 2026-11-25**, with your OK in the request:

- **`vic20-roms`**, **`c64-roms`**, **`c128-roms`**: MAME 0.264's non-merged `vic20`, `vic20p`, `vic1001`, `c1540`,
  `c1541`, `c64` (also `c64p`), `c64c`, `c128` (also `c128p`, `c128d`), `c128dcr`, `c1571` and `c1581` zips, from the
  archive.org item the PET's came from. Each is extracted, and each folder has a `mame` ROM path. MAME 0.289 verifies
  every set as good. The zips also hold third-party replacement ROMs (JiffyDOS and others) as MAME BIOS options; they
  are not Commodore's and are not used.
- **`vic20-media`**, **`c64-media`**, **`c128-media`**: MAME 0.202's software lists `vic1001_cart` (287 cartridges),
  `vic1001_cass`, `vic1001_flop`, `c64_cart`, `c64_cass`, `c64_flop` (including the 1541 demo disk), `c128_cart`,
  `c128_flop` (including CP/M 3.0) and `c128_rom`, verified against MAME 0.289's hash files. Only one image
  (`sargon2`'s first chip) has another checksum.
- **The references** (about 470 MB, from zimmers.net, archive.org and the authors' sites), each with a text version
  (archive.org's OCR or pdftotext) unless noted:
  - **`docs\vic20`**: the Programmer's Reference Guide, two user's guides, *Mapping the VIC*, the technical manual
    (990440) with schematics, and the 251027 and 324001 schematics (scans).
  - **`docs\c64`**: the Programmer's Reference Guide, the User's Guide, *Mapping the 64 and 64C*, Christian Bauer's
    VIC-II article, the PLA dissection, the 314001-02 and -03 service manuals, the 64doc 6510 notes, and the
    schematics of the 326106, 250425, 250466 and 250469 boards.
  - **`docs\c128`**: the Programmer's Reference Guide (the source for the 8502, VDC and MMU), the System Guide,
    *Mapping the 128*, the CP/M User's Guide, the 314001-08 service manual (scan only), the 1987 Developer's Package,
    the 8721 PLA's equations, and the 128's and 128DCR's schematics.
  - **`docs\cbm-drives`**: the 1540, 1541 and 1571 user's guides and service manuals, the 1541 technical manual, the
    1541 and 1571 schematics, *Inside Commodore DOS*, the serial bus description, the 1530 manual, and the D64, G64,
    TAP and VICE file-format descriptions.
  - **`docs\cbm-chips`**: the 6500/6510, 6522, 6526, 6560/6561, 6567, 6581 and 6582 (the HMOS SID, nearest to the
    8580) data sheets.
  - Not found as separate data sheets: the 8502, 8563, 8722, 8580, 8521 and 8564/8566. The 128's reference guide and
    service manual describe them. No PAL VIC-20 board schematic was found.

Still to fetch, each shown before it is fetched:

- Commodore's listings from mist64/cbmsrc, for names only, into the scratchpad as the PET's were: `BASIC_VIC`,
  `KERNAL_VIC_04`, `DOS_1540` and `DOS_1541_05` for the VIC-20; `BASIC_C64` and `KERNAL_C64_01`-`03` for the 64; the
  128's BASIC, kernal, editor, monitor and `DOS_1571` sets for the 128. The `_REC` folders are third-party
  reconstructions and are never used.
- Lorenz's test suite and the VICE test programs, at phase C1.

### The VIC-20

#### V1. The machine and its screen

- `Vic20Machine`, `Vic20Bus` (the RAM blocks and expansions, the VIC's 16 KB view, colour RAM, I/O), the two VIAs
  wired as the schematic shows, the NMI from RESTORE and the IRQ from VIA 2.
- `Vic6560`: both standards' timing, the screen and border, the character and multicolour modes, 8 × 16 characters,
  the registers' effects mid-frame at the cycle the chip reads them, the raster register, the light pen, and the
  paddles.
- Its sound: the three voices, noise and volume, as 48 kHz stereo.
- The keyboard matrix with a host key map, RESTORE, and joystick 1.
- The ROMs from dumps (`romDirectory` or `RETROCORE_VIC20_ROMS`) until V4 adds the sources.
- **Done when** NTSC and PAL reach `READY.` with 3,583 bytes free unexpanded and the right count for each expansion,
  a typed program runs, colours and both character sets show, and traces match MAME's `vic20` and `vic20p` from
  power-on.

#### V2. Tape, cartridges and programs

- `CommodoreDatasette` (from `PetDatasette`) on the VIC's cassette port: TAP at the VIC's clocks, WAV, and `.prg`
  wrapped as a tape. Saves go back through the media pipeline.
- Cartridges: MAME's `.20`, `.40`, `.60`, `.70`, `.a0` and `.b0` chips by address, raw `.prg` images whose first two
  bytes say where, and VICE's `.crt`. Autostart from `A0CBM`.
- `.prg` programs loaded straight into memory, as the PET's debugger does.
- **Done when** LOAD, SAVE and VERIFY work against images MAME reads, both of MAME's tapes load, and a sample of
  cartridges from `vic1001_cart` (games, the Super Expander, the Programmer's Aid) starts on the right RAM size.

#### V3. The serial bus and the 1540/1541

- `SerialBus`: ATN, CLK, DATA and SRQ as open-collector lines that any number of devices pull, with the VIC's VIAs on
  it as MAME wires them.
- `Cbm1541`: the 6502, the two VIAs (the bus and the head's stepper, motor, LED and write protect), the gate array's
  GCR read and write with its four speed zones and byte-ready on SO, and a half-track stepper on a `CommodoreDisk`.
  The 1540 is the same board with its own ROM (325303-01), for the VIC's faster serial timing.
- `.d64` and `.g64` saved back when written, by the existing formats.
- The drive as a device, numbers 8-11, with Add Card in the Machine view.
- **Done when** `LOAD"$",8` lists a disk, LOAD, SAVE and the DOS commands (`N`, `S`, `R`, `V`, `I`) work, the
  `vic1001_flop` disks load, and drive traces match MAME's `c1541` and `c1540` through a directory load.

#### V4. ROM sources

- `Vic20/Basic.asm`: BASIC 2 for the VIC, a root over the shared Commodore modules, byte-identical to 901486-01.
- `Vic20/Kernal.asm`: the kernal, with the screen editor, the serial bus, the tape and RS-232, byte-identical to
  901486-06, with a `PAL` switch for -07.
- `Vic20/CharacterGenerator.asm`: 901460-03.
- A conversion log for each in `docs/conversions`, tests pinning each build by digest, and the machine booting from
  the SDK's builds without dumps.
- **Done when** every build is byte-identical, `SdkDocumentationIsClean` passes, and both standards boot from the
  SDK's builds.

#### V5. The drives' DOS sources

- `Serial/Dos1541.asm`: the 1541's DOS (325302-01 and 901229-xx, 16 KB), one source with a switch for each of the
  901229 revisions (-01, -02, -03, -05, -06), and the 1540's 325303-01 as another switch.
- Reviewed in parts, as the Atari BASIC source was: the job loop and GCR code, the command parser, the file and
  directory code, and the serial bus.
- **Done when** every revision is byte-identical, the docs lint is clean, and the drive runs from the SDK's builds.

#### V6. The debugger and clients

- `Vic20DebugTarget` (machine `vic20`): BASIC, the kernal and user programs at source level; breakpoints, the call
  stack, memory, the screen, and the VIC's and VIAs' registers; launch options for the model, expansion, video,
  tape, cartridge and disks.
- BASIC debugging on the VIC as on the PET: the BASIC thread, line breakpoints, statement stepping and variables,
  from the running BASIC's symbols. The `cbmbasic` rename.
- The extension's `vic20` entries, launch schema and Start Machine (a `.prg`, a `.bas`, a tape, a cartridge, a disk,
  or a source); the key bar (RUN/STOP, RESTORE, CLR/HOME, the Commodore key, F1-F8); the display at the VIC's aspect.
- The Desktop's catalog entry, icon and key map.
- `docs/Vic20.md`, the README, the extension README, and a `tools/Test-Vic20Dap.mjs` and BASIC DAP script in CI.
- **Done when** a kernal breakpoint and a BASIC line breakpoint both stop, Start Machine runs a `.bas` file on each
  expansion, and the DAP scripts pass.

### The Commodore 64

#### C1. The machine, its screen and sound

- `C64Machine`, `C64Bus`: the 6510's port, with its unconnected bits' fading as the chip has it, the PLA's banking
  checked against MAME's fuse map for all 32 combinations, colour RAM, the I/O pages (`$DE00` and `$DF00` for
  cartridges).
- `Cia6526`: the timers, TOD clock, shift register, FLAG and interrupts, including the old and new CIA's timer IRQ
  difference.
- `VicII`: cycle-exact for 6567R8, 6567R56A and 6569. The 64 or 65 cycles of each line, bad lines and BA, sprite
  fetches, the sprites and their collisions, all the display modes, the borders (and opening them), raster
  interrupts, the light pen.
- `Sid`: the voices, envelopes, ring modulation, sync, the filter, the volume register's digi trick, and the
  paddles.
- The keyboard, both joysticks, the paddles, RESTORE.
- **Done when** NTSC and PAL reach `READY.` with 38,911 bytes free, traces match MAME's `c64` and `c64p` from
  power-on, Lorenz's CPU suite passes, and the chosen VICE VIC-II and CIA test programs pass.

#### C2. Tape, cartridges and the 1541

- The Datasette on the 6510's port and CIA 1's FLAG, and turbo tapes that time pulses themselves.
- `.crt` cartridges: 8 KB, 16 KB and Ultimax, then the common bank-switched types in MAME's list (Ocean, Magic Desk,
  Fun Play, System 3, Dinamic, Action Replay, Final Cartridge, EasyFlash), each by its `.crt` type.
- The 1541 from V3 on the 64's CIA 2.
- **Done when** LOAD and SAVE work to tape and disk, the 1541 demo disk runs, a sample of disk fast loaders and turbo
  tapes from MAME's lists loads, and a sample of each cartridge type starts.

#### C3. ROM sources

- `C64/Basic.asm` (901226-01), over the shared Commodore modules.
- `C64/Kernal.asm` with a `REVISION` switch for 901227-01, -02 and -03.
- `C64/CharacterGenerator.asm` (901225-01).
- **Done when** each build is byte-identical, the docs lint is clean, and the 64 boots from the SDK's builds.

#### C4. The debugger and clients

- `C64DebugTarget` (machine `c64`), with the CIAs', VIC-II's and SID's registers, the bank the PLA has mapped shown
  on each memory area (so a breakpoint in BASIC stops only while BASIC is mapped), and launch options.
- BASIC debugging, the extension, Start Machine (`.prg`, `.bas`, `.tap`, `.crt`, `.d64`, `.g64`, sources), the key
  bar, joystick on the host's keys or a game controller, the Desktop, `docs/C64.md` and DAP scripts.
- **Done when** as for the VIC-20.

### The Commodore 128

#### D1. C128 mode

- `C128Machine`, `C128Bus`: the 8502 at 1 and 2 MHz, the MMU and 8721 PLA, both RAM banks and common RAM, the page
  pointers, and the internal and external function ROM sockets.
- `VicIIe` (the VIC-II with its extra lines), the shared SID and CIAs, and the extended keyboard.
- `Vdc8563` with 16 KB (64 KB as an option): its registers, the 80-column text and attributes, block copy and fill,
  the cursor and smooth scrolling, and bitmaps. The machine has two screens; the display view and the Desktop show
  either, and the 40/80 key picks which BASIC uses.
- **Done when** BASIC 7.0 reaches `READY.` with 122,365 bytes free on both screens, `FAST` and `SLOW` work, traces
  match MAME's `c128` from power-on, and the 64's chip tests pass on the 128's VIC-IIe.

#### D2. C64 mode

- `GO 64`, and the Commodore key held at reset, through the MMU into the 64's map and the 251913-01 ROMs.
- **Done when** C64 mode runs what C2 ran.

#### D3. The 1571 and the fast serial bus

- `Cbm1571`: the 6502, two VIAs, the CIA's fast serial port, the WD1770 (a variant of the shared Western Digital
  controller), double-sided GCR and MFM, and the 1541 mode.
- `.d71` images, and MFM images for CP/M disks.
- **Done when** burst loads work in C128 mode, the drive runs as a 1541 for C64 mode and the VIC-20, and traces match
  MAME's `c1571`.

#### D4. CP/M mode

- The Z80 on the 128's bus, its wait states, its I/O map, the MMU's Z80 view, and the BIOS in the kernal chip.
- **Done when** CP/M 3.0 from `c128_flop` boots on a 1571 and runs its utilities in 40 and 80 columns.

#### D5. ROM sources

- BASIC 7.0, the kernal and screen editor, the monitor, the Z80 BIOS and the character ROM, for both revisions. This
  is about 48 KB, the largest set yet, so it is staged by chip, with a review after each.
- The 1571's DOS (310654-03 and -05, 32 KB), as the 1541's was, sharing its GCR and file code where the bytes agree.
- **Done when** each chip is byte-identical in both revisions and the 128 and 1571 boot from the SDK's builds.

#### D6. The debugger and clients

- `C128DebugTarget` (machine `c128`): both processors as threads, with the Z80 and CP/M programs at source level as
  the SoftCard has them, the MMU's configuration on each memory area, and the VDC's registers and RAM.
- The dialect's BASIC 7.0, BASIC debugging, the extension, Start Machine, the key bar (40/80, ESC, ALT, HELP), both
  screens in the display, the Desktop, `docs/C128.md` and DAP scripts.
- **Done when** a breakpoint in BASIC 7.0, one on a BASIC line, one in the kernal in C64 mode and one in a CP/M
  program all stop, and the DAP scripts pass.

## Performance

The 64 with a 1541 runs two 6502s, the VIC-II and the SID every cycle; the 128 adds the VDC. Each must run well over
real time in the Debug host and the Desktop. Each machine's first phase measures it, and the chips are written for
speed from the start (the VIC-II by line and cycle tables, the SID by whole samples where it can) rather than
optimized later. The 6502 core is not expected to change. If it does, the change follows the
[PGO maintenance checklist](../../.claude/skills/performance-testing/overlay.md#native-aot-pgo-maintenance). The
Desktop's profile trains Apple II workloads only; the debugger and clients phases decide whether a Commodore workload
joins it, and state the decision.

## Later

- A closer model of the 6581's filter distortion, and the 8580's.
- The 1581, the 64C (8580 SID, 251913-01's combined ROM), the SX-64, the VIC-1001, the 128D and 128DCR.
- The 1700/1750 RAM expansion units, the 1351 mouse, the light pen, printers on the serial bus, and RS-232 on the
  user port.
- A "fast disk" option.

## Not planned

- The Plus/4 and 16 (the TED chip), the CBM-II, the 65 and the 64DTV.
- Third-party ROMs such as JiffyDOS.
