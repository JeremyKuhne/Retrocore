# Backlog: the Commodore VIC-20, 64 and 128

Status: **agreed 2026-11-25** ("Start phase V1"). Phases V1 to V6 are built: V5's DOS source builds the 1540's and
every 1541 revision but 901229-04, which has no dump, and the drives run from it
([Dos1541.md](../conversions/Dos1541.md)). The `cbmbasic` rename is still to do.

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
   run them. [Disk speed](MediaSpeed.md) can later Skip proven standard operations without changing the true-drive
   path for uploaded code or custom loaders.
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

**Built 2026-11-25.** Phase V2 made one change to it: the VIC fetches only the board's RAM,
not the expansion port's 3K at `$0400`, which the Programmer's Reference Guide says it cannot access.

- **`Vic6560`** (in `Retrocore.Core`'s chips, with `IVicMemory` and `VicVideoStandard`):
  - 65 cycles × 261 lines (NTSC) or 71 × 312 (PAL), at 14.318 MHz / 14 or 4.434 MHz / 4.
  - It draws four dots a cycle and fetches a character's code and colour, then its row of dots, two fetches in two
    cycles. It takes the window's columns at each line's second cycle and its rows at the frame's first line, as
    MAME does, and the other registers at the cycle it uses them, so mid-line changes to colours and addresses show.
  - The text window comes from registers 0-3. Characters are 8 × 8 or 8 × 16, hires or multicolour (00 background,
    01 border, 10 character, 11 auxiliary), and register 15's bit 3 reverses them. The raster line reads from
    registers 3 and 4, and the paddles from 8 and 9 (`$FF` with none connected).
  - The visible frame is 200 × 248 from line 12 (NTSC) or 224 × 296 from line 14 (PAL). The widths are MAME's, and
    PAL's starts on the line where MAME's does, while NTSC's starts a cycle later, so its picture sits 4 dots left of
    MAME's and the kernal's window is centred. The heights are taller than MAME's, which shows from line 28: 233
    lines on NTSC and 284 on PAL.
  - Sound: bass, alto and soprano count a clock prescaled by 128, 64 or 32 cycles and reload from
    (register + 1) & 127, toggling at each reload, which gives Mäkelä's measured periods and MAME's. Noise is MAME's:
    a 16-bit shift register stepped every 2 cycles' count, and an 8-bit ring on its rises. The voices are mixed in
    proportion to the volume (MAME uses a DAC table) as 48 kHz stereo.
  - The palettes are MAME's, the 6560's and the 6561's. Interlace is a register bit but is not drawn, and the light
    pen registers read 0, as no pen is connected.
  - Where it differs from MAME, the class remarks say so: a row's screen address, the 6560's raster registers, which
    MAME counts 37 cycles ahead, and what an unanswered read sees.
- **`Retrocore.Machines.Commodore.Vic20`** (in `Vic20/`):
  - `Vic20Machine` (id `vic20`), `Vic20Bus`, `Vic20Keyboard`, `Vic20Key`, `Vic20Roms`, `Vic20Expansion` and
    `Vic20MemoryArea`. `CommodoreJoystick` is shared for the 64.
  - The bus: RAM, the expansion blocks (3K, blocks 1, 2, 3 and 5, in any mix), the VIC's 16K view (its A13 is A15
    inverted), the colour RAM's nybbles, and the VIC at `$9000-$90FF`. A4 and A5 select the VIAs in
    `$9100-$93FF`.
  - A read that nothing answers sees the VIC's last fetch, as Mäkelä measured; so do a colour RAM read's top four
    bits. MAME's decode differs slightly: it puts VIA 1 on any address with A4 set in `$9000-$93FF`, and the VIC at
    `$9000-$900F` only.
  - VIA 1's interrupt is the NMI and VIA 2's the IRQ. RESTORE is on VIA 1's CA1. The joystick is on VIA 1's PA2-PA5
    and VIA 2's PB7. The serial bus's lines are wired already (ATN from VIA 1's PA7, CLK and DATA from VIA 2's CA2
    and CB2, read back on VIA 1's PA0 and PA1), with nothing on the bus yet.
  - The keyboard matrix comes from the kernal's key table at `$EC5E`: column (VIA 2's port B) × 8 + row (port A).
    Typing holds each key three jiffies, with SHIFT or CTRL where PETSCII needs them: the colours, RVS, f1-f8, CLR,
    INST and the cursor keys.
- **Tests:**
  - `Vic20MachineTests`: both standards boot to `**** CBM BASIC V2 ****` with 3,583 bytes free, and 6,655, 11,775,
    19,967 and 28,159 with 3K, 8K, 16K and 24K. All the RAM gives 28,159, as the kernal skips the 3K once block 1
    has RAM.
  - They also check that the screen and colour RAM move with block 1, a typed program prints every symbol, the
    scanned frame shows the kernal's colours, `POKE 36869,242` picks the lower-case set, STOP-RESTORE breaks into a
    running program through the NMI, the joystick reads, and a voice makes a tone.
  - `Vic6560Tests`, on blank ROMs: the light pen reads 0, the VIC sees colour RAM, and the window takes its rows at
    the frame and its columns at the line.
  - `Vic20OracleTests` traces MAME's `vic20` and `vic20p`, unexpanded and with `-exp 3k`, `8k` and `16k`, for three
    emulated seconds: 150,000-476,000 instructions each. They match ours from power-on to the wait for a key.
    - The jiffy interrupt is VIA 2's timer on both, so no beam waits need to be left out.
    - The kernal's RAM test reads unconnected addresses, which see the VIC's bus: here its last fetch or its read of
      `$001C`, and in MAME the last byte on it, including the processor's accesses to RAM, the character ROM and the
      VIC's registers. So A, X and the compare's flags are left out of the test's rows (`$FDAF-$FDEA`, `$FE91-$FEA8`,
      the same in both kernals). The instructions still match.
  - `tools/PetOracle.lua` takes the CPU's tag in `RETRO_CPU` (the PET's `f3` by default, the VIC-20's `ue10`).
- **PGO:** no refresh. The profile trains Apple II workloads only. No Apple II, 6502 core or Desktop path changed;
  the new chip and machine run only on the VIC-20.
- **Speed:** a typed-program test runs about 8 emulated seconds in under half a second, with other tests in parallel,
  so well over ten times real time. That is a rough figure, not a benchmark.
- **Left for later phases:** the serial bus's devices (V3), the ROM sources (V4), the drives' DOS sources (V5), and
  the debugger, extension and Desktop (V6).

#### V2. Tape, cartridges and programs

- `CommodoreDatasette` (from `PetDatasette`) on the VIC's cassette port: TAP at the VIC's clocks, WAV, and `.prg`
  wrapped as a tape. Saves go back through the media pipeline.
- Cartridges: MAME's `.20`, `.40`, `.60`, `.70`, `.a0` and `.b0` chips by address, raw `.prg` images whose first two
  bytes say where, and VICE's `.crt`. Autostart from `A0CBM`.
- `.prg` programs loaded straight into memory, as the PET's debugger does.
- **Done when** LOAD, SAVE and VERIFY work against images MAME reads, both of MAME's tapes load, and a sample of
  cartridges from `vic1001_cart` (games, the Super Expander, the Programmer's Aid) starts on the right RAM size.

**Built 2026-11-25** after "Start phase V2". The Datasette's rename and the TAP changes landed first, with the
plan (#239).

- **`CommodoreDatasette`** is the PET's `PetDatasette`, renamed and given the machine's clock:
  - The tape's pulses are still microseconds. The Datasette works out each pulse's length in the machine's cycles as
    the head reaches it, and a recorded pulse's in microseconds, so the PET's timing is unchanged.
  - On the VIC-20 it is the machine's one device (`cassette`). VIA 1's PA6 senses the keys, its CA2 runs the motor
    (low runs it, as MAME's C2N has it), VIA 2's CA1 reads the tape and its PB3 writes it.
  - It keeps the TAP header it saves with: machine 1 (the VIC-20) and the standard's video byte.
- **`TapFormat` and `CommodoreTapeCodec`:**
  - TAP images are written for the machine that records them. A pulse is a byte of 8-cycle units where that reads
    back as the same pulse, and otherwise a zero and its length in cycles. The PET's and the VIC-20's cycles are no
    longer than a microsecond, so their images hold every pulse recorded to the microsecond exactly.
  - The codec carries the header's machine and video bytes. It keeps those it read from an image, and the debug
    host's Save picks them from the Datasette and keeps them in the recovery journal. Its losses now come from
    reading the image back, so a rounded pulse is listed as well as an over-long pause.
- **`Vic20Cartridge`:**
  - It holds chips at addresses in blocks 1, 2, 3 and 5, and any RAM it brings, such as the Super Expander's 3K.
  - A chip that fills an aligned part of its block is seen again through the rest, as VICE's `.crt` description says
    hardware does: a 4K chip at `$A000` is at `$B000` too, and the Programmer's Aid at `$7000` is at `$6000`.
  - It reads MAME's chips by extension (`.20`, `.40`, `.60`, `.70`, `.a0`, `.b0`), `.prg` images by their first two
    bytes, VICE's generic `.crt` (type 0, with ROM and RAM packets), and a file with no known name at `$A000`, as the
    Super Expander's `325323-01` is. Other `.crt` types are refused, as are chips that overlap or fall outside the
    blocks.
  - `Autostarts` says whether `A0CBM` is at `$A004`. The kernal does the rest.
  - The machine takes it in its constructor; its ROM takes the blocks it fills from any RAM there, and memory areas
    show it as `Cartridge`.
- **`Vic20Machine.LoadProgram`** loads a `.prg` straight into RAM, as LOAD does. A program at a BASIC start (`$0401`,
  `$1001` or `$1201`) goes to this machine's `TXTTAB`, its lines are linked again, and `VARTAB`, `ARYTAB` and
  `STREND` are set past it. Anything else goes where its address says.
- **Tests:**
  - `Vic20TapeTests`:
    - A program saved on NTSC and on PAL loads, runs and verifies, and loads on the other standard.
    - A `CommodoreTapeBuilder` tape, at the PET's pulse lengths, loads.
    - A `.prg` from an unexpanded machine loads into memory at `$1201` with 8K, relinked, and runs.
    - MAME's two tapes load: 3D Maze (TAP) and Speakeasy's PHONEME EDITOR (a WAV marked a bad dump).
    - TAP images carry the VIC-20's header and hold every pulse.
    - MAME's `vic20` loads a program ours saved, as TAP and as WAV, to the same bytes.
    - `tools/PetTapeLoad.lua` takes the CPU's tag in `RETRO_CPU`, as `PetOracle.lua` does.
  - `Vic20CartridgeTests`:
    - The cartridge formats, mirroring, `.crt` packets and refusals, including lengths too big for the file.
    - Avenger, Lode Runner, the Programmer's Aid, Adventureland and Story Machine, read by their files' names, fill
      the addresses MAME's hash file gives.
    - Avenger, Gorf and Lode Runner (PAL) start themselves on the unexpanded machine and run from their ROM.
    - The Super Expander adds its 3K and reaches `READY.`, and `SYS 28681` starts the Programmer's Aid without an
      error.
  - `Vic20OracleTests.CartridgeBootMatchesMame` traces MAME with the list's Avenger, Gorf, Donkey Kong (blocks 1 and
    5), Lode Runner (PAL, blocks 3 and 5), the Super Expander and the Programmer's Aid for three seconds; they match.
    - Lode Runner clears VIA 1's DDR and reads PA7 as an input, a pin nothing drives: high here, as an open TTL input
      is, and low in MAME. So after a load from `$9111` or `$911F` the comparison leaves out bit 7 and the N flag.
- **Not done here:**
  - Insert, Save and the Datasette's keys from the debugger and the Desktop come with the VIC-20's debug target in V6.
    The Datasette is an `IMediumSlot` and the codec is ready, but no client drives it yet.
  - The cartridge is chosen when the machine is built; changing it means building a new machine, as switching the
    VIC-20 off does. Banked cartridges (the Mega-Cart, the Final Expansion) are not modelled.
- **PGO:** no refresh. The Datasette's PET path changed only in working out each pulse's length once per pulse, and
  the profile trains Apple II workloads only.

#### V3. The serial bus and the 1540/1541

- `SerialBus`: ATN, CLK, DATA and SRQ as open-collector lines that any number of devices pull, with the VIC's VIAs on
  it as MAME wires them.
- `Cbm1541`: the 6502, the two VIAs (the bus and the head's stepper, motor, LED and write protect), the gate array's
  GCR read and write with its four speed zones and byte-ready on SO, and a half-track stepper on a `CommodoreDisk`.
  The 1540 works as the same board, with its own ROM (325303-01), for the VIC's faster serial timing.
- `.d64` and `.g64` saved back when written, by the existing formats.
- The drive as a device, numbers 8-11, with Add Card in the Machine view.
- **Done when** `LOAD"$",8` lists a disk, LOAD, SAVE and the DOS commands (`N`, `S`, `R`, `V`, `I`) work, the
  `vic1001_flop` disks load, and drive traces match MAME's `c1541` and `c1540` through a directory load.

**Built 2026-11-25** after "Start phase V3".

- **`Retrocore.Machines.Commodore.Serial`** (in `Serial/`):
  - `SerialBus`, `SerialPort` and `SerialLines`: ATN, CLK, DATA and SRQ, open collector, low while any device pulls
    them.
  - The VIC-20 pulls ATN from VIA 1's PA7, and CLK and DATA from VIA 2's CA2 and CB2. It reads CLK and DATA on VIA
    1's PA0 and PA1, and SRQ on VIA 2's CB1. After each drive cycle only those serial inputs are updated.
- **`Cbm1541`** (with `Cbm1541Bus`, `Cbm1541GateArray` and `Cbm1541Roms`):
  - A 6502 at 1 MHz, 2K of RAM, VIA 1 (the bus) at `$1800`, VIA 2 (the disk) at `$1C00` and 16K of DOS at `$C000`,
    all mirrored as MAME maps them. The 1540 works as the same board, with 325303-01. 901229's revisions 1 to 6 load, with 6
    as the default, as in MAME.
  - The XOR of ATN and ATNA pulls DATA, so every drive answers ATN in hardware.
  - **The gate array** follows the 64H156:
    - The 16 MHz clock recovery is the 4040's, with no GCR PROM: the DOS does the GCR coding itself.
    - Ten ones are SYNC. Every eighth bit after it pulls BYTE READY low for half a bit, when SOE lets it, until the
      quarters counter's bit 1 rises.
    - BYTE READY's fall sets V through SO and latches port A through CA1. The latched byte is the one held when
      BYTE READY fell, even within a microsecond.
    - Writing, the eighth bit loads the write register from port A, and its top bit goes to the head as the counter's
      bit 1 falls.
  - **VIA 1's undriven pins** float high before the DOS sets their direction, as the TTL inverters they drive hold
    them. So a 1540 holds CLK and DATA low at power-on, which is why 901229-05 added its `$FF10` patch.
  - **VIA 2's undriven pins** read low, as in MAME. The DOS reads port B and writes it back when it sets the port's
    direction, so pins read high would start the motor and push the stepper against its stop.
  - **The write-protect sensor:** an empty drive reads not protected, since light passes. A disk going in or out
    blocks the light for 0.1 second, which tells the DOS the disk changed, so it reads the new BAM.
  - The mechanism is the 4040's `CommodoreFloppyDrive`, as a single drive (`disk8` to `disk11`). It saves as G64 or
    D64.
- **`Vic20Machine.AddDisk` and `RemoveDisk`** plug drives 8-11 into the bus. The drives run at 1 MHz against the
  VIC-20's 14.318 MHz / 14 or 4.434 MHz / 4, counted without drift
  against the machine's own clock constants. The machine's reset resets them too, as the bus's RESET
  line does. `Devices` lists the Datasette, then each drive.
- **Tests:**
  - `Vic20DiskTests`:
    - `LOAD"$",8` lists the Data 20 disk on both drives.
    - On a blank disk on both drives: `N` formats, then SAVE, LOAD and VERIFY work. `R`, `S`, `V` and `I` answer on
      the command channel, and the disk saves as a D64 that names the file.
    - MAME's VIC File, VIC Writer and Simplicalc (G64s) and Speakeasy (a D64) load.
    - Drives 8 and 9 list their own disks. A disk swapped in drive 8 lists its own BAM's count.
    - A protected disk refuses a scratch with 26 WRITE PROTECT ON, and a format with 21 READ ERROR, as MAME's 1541
      does too.
    - The gate array reads every byte after each sync on track 18 as the image holds it.
  - `Vic20DiskOracleTests` traces the drive's 6502 in MAME (`tools/Pet4040Oracle.lua` now takes `RETRO_CPU` and
    makes it the debugger's visible CPU, so `tracelog` writes to its trace).
    - Power-on matches on both the 1541 and the 1540. The 1541's directory load matches through 9 seconds: the main
      program as far as the shorter trace goes, and all 508 of MAME's controller passes (46,889 rows), with 27 of
      ours skipped where a job came sooner.
    - The comparison differs from the 4040's, since DOS 2.6's interrupts return:
      - Each trace splits into the main program, without the handlers, and the controller's passes (`$F2B0` to
        `$FE7F`).
      - Loops of up to 64 rows collapse.
      - Passes may skip up to 100 on either side to agree again, as MAME types at its own pace and its jobs come at
        other passes.
      - Registers count until the first interrupt or the first read of a port's pins, and V never counts before the
        first interrupt.
    - **The 1540 directory load is not compared:** MAME's own 1540 on its `vic20` receives the LISTEN as `$2A` and
      ends in `?DEVICE NOT PRESENT`. Ours lists the directory.
- **Found and fixed while building:**
  - BYTE READY was re-checked only at the quarters counter's steps, so a pulse could start and end within one
    microsecond and be latched a bit late. That was data checksum errors.
  - The drive read port B before its inputs were set, which stepped the head half a track at power-on.
  - A VIA write replayed the last microsecond's BYTE READY edges.
  - BYTE READY's rise was lost when the motor stopped, or SOE fell, while it was low, so CA1 and SO missed the next
    byte's fall (found in review; `Cbm1541GateArrayTests`).
- **Not done here:**
  - Add Card and the drives in the Machine view come with the debug target in V6; the drives are `IMediumSlot`s
    already.
  - MAME's random flux on unformatted tracks (weak bits) is not modelled: a run of zeros past the counter's wrap
    reads as ones there.
  - SRQ is wired, but no device drives it until the 128's fast bus.
- **Speed:** about 35× real time with no drive and 14.5× with a 1541, measured over 20 emulated seconds. Most of the
  cost is the drive's 6502, VIAs and gate array.
- **PGO:** no refresh. The new code runs only on the VIC-20, and the shared mechanism's code path is unchanged.

#### V4. ROM sources

- `Vic20/Basic.asm`: BASIC 2 for the VIC, a root over the shared Commodore modules, byte-identical to 901486-01.
- `Vic20/Kernal.asm`: the kernal, with the screen editor, the serial bus, the tape and RS-232, byte-identical to
  901486-06, with a `PAL` switch for -07.
- `Vic20/CharacterGenerator.asm`: 901460-03.
- A conversion log for each in `docs/conversions`, tests pinning each build by digest, and the machine booting from
  the SDK's builds without dumps.
- **Done when** every build is byte-identical, `SdkDocumentationIsClean` passes, and both standards boot from the
  SDK's builds.

**Built 2026-11-26** (started 2026-11-25 after "Start phase V4"); see [the conversion log](../conversions/Vic20.md).

- The character ROM is built: `Vic20/CharacterGenerator.asm` over the PET's source with a `VIC20` switch (£ at
  `$1C`, each set followed by its reversed copy), byte-identical to 901460-03 (`Vic20RomSourceTests`). The PET's two
  chips still assemble byte-identically.
- Decided: the kernal is in the maintained style from the start, one standalone source for now (sharing with the 64
  is decided at C3), and its rename table is reviewed whole, in parts, before conversion (K1-K3).
- Part 1 of the kernal's rename table, the variables, RAM vectors, VIAs and constants (199 rows), is accepted (K5).
  Part 2, the screen editor and keyboard (193 rows), is accepted (K6), and part 3, the serial bus (49 rows) (K7).
  Part 4, the tape (119 rows, with corrections to part 1's tape variables), is accepted (K8). Part 5, RS-232 and
  the NMI (72 rows), is accepted (K9). The owner left the rest to the drafter's judgement: part 6, the channels,
  files, messages, errors and clock (175 rows), and part 7, start-up, the IRQ, the jump table and the VIC's
  registers (94 rows), are settled as recommended (K10, K11), so
  [the table](../conversions/Vic20KernalRenames.md) is complete.
- The kernal is converted (`Vic20/Kernal.asm`): byte-identical to 901486-06 and, with `PAL = 1`, to -07, with
  every routine's contract written (the log's step 4).
- BASIC is built (`Vic20/Basic.asm`), byte-identical to 901486-01 and its part of each kernal chip, over the
  shared modules with new switches (the log's step 5), and the machine boots from the SDK's builds on both standards
  with no dumps (`Vic20SdkModules`, `Vic20RomSourceTests`).

#### V5. The drives' DOS sources

- `Serial/Dos1541.asm`: the 1541's DOS (325302-01 and 901229-xx, 16 KB), one source with a switch for each of the
  901229 revisions (-01 to -06), and the 1540's 325303-01 as another switch. 901229-04 has no dump, so it has no
  switch; the rename table and the inventory are in [Dos1541.md](../conversions/Dos1541.md).
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

**Built 2026-11-27** after "Start phase V6", except the `cbmbasic` rename, which is its own change next.

- `Vic20DebugTarget` (machine `vic20`): `video`, `ramExpansion`, `cartridge`, `sound`, `cassette` and the drives'
  `diskUnits`, `diskModel`, `disks` and `driveRomDirectory`; BASIC and the kernal at source level from the SDK's
  builds, BASIC's source covering its end in the kernal's chip; the call stack, memory, the colour screen and its
  text, sound, the Datasette's keys, and 1541s and 1540s added and removed as devices 8-11. RESTORE, RUN/STOP with
  RESTORE, and SHIFT with the Commodore key are the key codes 256-258, held for a tenth of a second.
- BASIC on the BASIC thread: the dialect's VIC-20 variant, the PET's BASIC 2 with its page zero three bytes higher,
  and errors read through the numbered table. A `.prg` BASIC program moves to where the expansion puts BASIC.
- `Vic20SdkModules` assembles from the repository's layout as well as the SDK's copy beside the debug host.
- The extension's `vic20` entry, launch schema, Start Machine (a source, a `.prg`, a `.bas`, a cartridge, a disk or a
  tape), the key bar, the display's 4:3 aspect, and the 1541 and 1540 in Add Card; the projects' catalog entry.
- The Desktop's catalog entry, icon, key map and key bar.
- [`docs/Vic20.md`](../Vic20.md), the README and the extension's README; `tools/Test-Vic20Dap.mjs` and
  `tools/Test-Vic20BasicDap.mjs` in CI, and `Vic20DebugTargetTests`.

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
- [Disk speed](MediaSpeed.md) support for verified standard operations.

## Not planned

- The Plus/4 and 16 (the TED chip), the CBM-II, the 65 and the 64DTV.
- Third-party ROMs such as JiffyDOS.
