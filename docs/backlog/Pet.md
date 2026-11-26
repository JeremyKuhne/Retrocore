# Backlog: the Commodore PET 2001

Status: **agreed 2026-11-16.** Phases 0-5 are built; phases 4 and 5 await review. Phase 6 is built and awaits review.

The PET 2001 (1977) is the third of the 1977 trinity beside the Apple II and the TRS-80 Model I. It is built from
parts the code base already has:

- an NMOS 6502 at 1 MHz;
- two 6520 PIAs, which work like the 6821 `Pia6821` already models;
- one 6522 VIA, which is `Via6522`;
- Microsoft BASIC, whose source `m6502.asm` is already in the SDK with a Commodore build (`REALIO` 3).

The goal is the Apple IIe's level of support:

- the models and their ROMs, built from byte-identical SDK sources;
- the video, keyboard, tape and disks;
- the debugger at source level and at BASIC level;
- the extension, Start Machine and the Desktop;
- media that saves;
- MAME traces as the oracle.

## The hardware

From MAME's `pet` driver, the PET schematics and the PET's memory maps, as phase 1 confirmed them.

| Part | What it is |
| --- | --- |
| CPU | MOS 6502 at 1 MHz (8 MHz / 8). |
| RAM | 4 KB or 8 KB on the 2001-4 and 2001-8. 16 KB or 32 KB on the later 2001N and 3000 series. BASIC programs start at `$0401`. |
| Video RAM | 1 KB at `$8000-$83FF`, repeated to `$87FF`; `$8800-$8FFF` is empty. 40 × 25 characters. |
| Character ROM | 2 KB (901447-08 on the 2001). Two sets of 128: uppercase and graphics, or upper- and lowercase, chosen by VIA CA2. Bit 7 of a code is reverse video. |
| Monitor | Built-in 9-inch monochrome: white on the 2001, green on later models. |
| ROMs | BASIC at `$C000-$DFFF`, the screen editor at `$E000-$E7FF`, and the kernal at `$F000-$FFFF`. `$9000-$BFFF` is free for option ROMs. |
| I/O | `$E800-$EFFF`: address bit 4 selects PIA 1 (`$E810`), bit 5 PIA 2 (`$E820`) and bit 6 the VIA (`$E840`), so each repeats through the 2K. |
| PIA 1 | Keyboard row select (port A, through a 74145), keyboard columns (port B), cassette 1 read (CA1) and motor (CB2), the cassettes' key senses and the diagnostic sense line, screen blanking (CA2), and the retrace interrupt (CB1, VIDEO ON's falling edge), which drives the jiffy clock and the keyboard scan. |
| PIA 2 | The IEEE-488 data lines in and out, plus ATN, NDAC and DAV. |
| VIA | IEEE-488 NRFD, NDAC and EOI, cassette write (PB3), cassette 2 motor and read, the character set (CA2), and the user port. CB2 with the shift register is the PET's sound, as the later models wire to a piezo and owners wired to a speaker. |
| Keyboard | The 2001's 73-key chiclet keyboard and numeric keypad, as a 10 × 8 matrix. The 2001N's full-size graphics keyboard is wired to the same matrix; the business keyboard is a different one. |
| Tape | The built-in Datasette on cassette port 1, and a second port. Commodore's pulse-width encoding: short, medium and long pulses (about 352, 504 and 672 µs), with each block written twice. |
| Disks | Commodore drives on the IEEE-488 bus: the 2040 (DOS 1) and 4040 (DOS 2). Each drive is a computer of its own, with a 6502 and a 6504, two 6532 RIOTs, a 6530, and its DOS in ROM. The disks are 35 tracks of GCR, 170 KB, as `.d64` images. |
| Snow | On the original 2001, the CPU's access to video RAM during the display shows as snow. The BASIC 1 editor writes only during retrace to avoid it. |

### The ROM versions

| Version | Machines | What changes |
| --- | --- | --- |
| BASIC 1.0 | The original 2001 | `*** COMMODORE BASIC ***`. Its IEEE-488 routines have the bug that stops disk drives working, and there is no built-in machine-language monitor. |
| BASIC 2.0 (the upgrade ROMs) | 2001 with the upgrade, 2001N, 3000 series | `### COMMODORE BASIC ###`. Fixed IEEE-488, garbage collection and arrays over 256 elements. The TIM monitor is built in, reached by `SYS 1024` on a `BRK`. |
| BASIC 4.0 | 4000 and 8000 series | Disk commands in BASIC (`DIRECTORY`, `DLOAD` and others), a faster garbage collector, and 80 columns on the 8032. |

## Proposed decisions

These are the plan's choices. Each needs your yes before phase 0.

1. **The project and id.** The project is `Retrocore.Machines.Commodore`, which leaves room for a VIC-20 or C64 later.
   The machine id is `pet`, and `model` names the variant, as `apple2` does.
2. **The models.** `pet2001` is the 2001-8 with BASIC 1, white screen and chiclet keyboard. `pet2001-basic2` is the
   same machine with the upgrade ROMs, and it is the default, since it is the first version that runs disks.
   `ramKilobytes` is 4, 8, 16 or 32. BASIC 4.0 and the 8032 come later, as their own phase.
3. **The disk drive at the hardware level.** The 2040 and 4040 run their own DOS ROMs on emulated 6502s, as the Disk
   II runs the IIe's own boot ROM and RWTS. A trap-based "virtual drive", which answers DOS commands from a `.d64`
   without running the drive, would be faster to build but would not debug the drive. For now the drive's DOS is a
   dump, not an SDK source.
4. **The sources.** BASIC is an overlay on `m6502.asm`, as `applesoft.mac` is. Commodore's changes are maintained
   by hand and assemble byte-identically to each ROM. Everything else (the editor, the kernal and the character
   ROMs) is our own native source, maintained by hand and byte-identical to its chip. No third-party source listing is
   imported or followed. Names follow `m6502.asm` and the published PET memory maps.
5. **Each phase ends in a review** before the next one starts.

## Shape in the code base

A new project, `Retrocore.Machines.Commodore`, with `PetMachine`, `PetBus`, `PetModel`, `PetVideo`, `PetKeyboard`,
`PetCassette` and `PetIeeeBus`. It shares, rather than copies:

- **The 6502 core**, unchanged. The PET adds a bus, not CPU features.
- **`Pia6821`**, for the 6520s, which differ only in pin names.
- **`Via6522`**, for the VIA and its shift-register sound.
- **The assembler's macro10 overlay**, for BASIC, and the native 6502 dialect, for the editor and kernal.
- **`Retrocore.Basic`**, which gains `CommodoreBasicDialect`: the PET's tokens, its PETSCII text and
  its variables. The variables share Microsoft BASIC's layout, as AppleSoft's and Color BASIC's do.
- **The device model, debugger, extension and Desktop**, unchanged in shape. The machine adds a debug target
  (`PetDebugTarget`, with `PetDebugTarget.Basic`) and catalog entries.
- **`Retrocore.Media`**, which gains `Commodore`: `.prg`, `.tap` and `.d64`.

## Phases

### 0. Fixtures and references

They are under `%USERPROFILE%\Retrocore` and are never committed. Each folder has a `README.txt` with sources and
SHA-256 hashes. I'll show each download with its site, file and checksum, and wait for approval.

- **`pet-roms`:** BASIC 1, BASIC 2 and BASIC 4 sets, the 901447-08 and -10 character ROMs, and the 2040 and 4040 drive
  ROMs. These are the MAME `pet2001`, `pet2001n`, `pet4016`, `c2040` and `c4040` sets.
- **`pet-media`:** a few `.prg`, `.tap` and `.d64` images from MAME's `pet_cass` and `pet_flop` lists, including
  the 2040 and 4040 demo disks.
- **`docs\pet`:** the PET 2001 user's manual and schematics, the PET's memory maps, the 2040 and 4040 user's
  manual, and the 2040 service manual.

MAME 0.289 is already in the cache. Its `pet` driver is the trace oracle, and VICE's `xpet` is the tie-breaker.

**Built 2026-11-16.** Phase 0 is done.

- **`pet-roms`** holds MAME 0.264's non-merged `pet2001`, `pet2001n`, `pet4016`, `c4040`, `c2040` and `c2040_fdc`
  zips, each extracted, and a `mame` ROM path. MAME 0.289 verifies all but `c2040` as good.
  - The archived `c2040` lacks DOS 1.2 (901468-06 and -07), and MAME knows no good DOS 1.0 dump. The two chips were
    fetched from zimmers.net on 2026-11-16, match MAME's CRC and SHA-1, and are in `extract\c2040` and the `mame`
    path's `c2040.zip`, which MAME now calls best available.
- **The 2001's ROM map** is confirmed by the chips' contents:
  - BASIC 1's keyword table starts at `$C000`.
  - Reset is `$FD38`, IRQ `$E66B` (the editor) and NMI `$CA60`.
  - MAME's default BASIC 1 is the revised one, 901447-09 in socket H1, with -01 as the original.
- **`pet-media`** holds MAME 0.202's `pet_flop`, `pet_cass` and `pet_quik` lists. All 36 disks, 226 tapes and 2
  quickloads verify against MAME 0.289's hash files.
- **`docs\pet`** holds the 2001-8 user manual, *Programming the PET/CBM*, the zero-page map, the 2040 user and service
  manuals, the 2001 schematics (320008, 320081 and the main logic assembly) and the dynamic PET's logic diagram.

### 1. The machine and its screen

- The bus: RAM sizes, video RAM and its mirror, the ROM sockets, and I/O.
- PIA 1, PIA 2 and the VIA, wired as the schematic shows. The 60 Hz retrace interrupt, the keyboard matrix with the
  2001's layout and a host key map, and the diagnostic sense line.
- The video: 40 × 25 from the character ROM, both character sets, reverse video, white or green phosphor, retrace
  timing, and snow on the 2001 as an option (on by default for `pet2001`).
- Sound on VIA CB2.
- The ROMs come from dumps (`romDirectory` or `RETROCORE_PET_ROMS`) until phase 3 adds the sources.
- **Done when** both models reach `READY.` with the right bytes free for each RAM size. A typed program runs, and
  instruction traces match MAME's from power-on.

**Built 2026-11-16.** Phase 1 is done.

- `Retrocore.Machines.Commodore` holds `PetMachine`, `PetBus`, `PetVideo`, `PetKeyboard` (and `PetKey`),
  `PetAudio`, `PetRoms`, `PetModel`, `PetPhosphor`, `PetMemoryArea` and `PetTiming`. It shares `Pia6821` and
  `Via6522` from `Retrocore.Core` and changes nothing outside the new project but the solution and the test
  project's reference.
- **The 2001's video timing** is the 2001's own, not MAME's: 64 cycles a line, 260 lines, 16,640 cycles a frame
  (60.1 Hz). VIDEO ON is low for the first 3,840 cycles, and the characters are drawn from cycle 23 of each displayed
  line. Both kernals program PIA 1's CB1 for the falling edge, so the interrupt comes as blanking starts. MAME's 2001
  has no beam: it toggles the line every 1/120 second (its own TODO says so).
- Snow is in the scanned frame, on by default: a CPU access to video RAM in a line's drawn cycles shows its byte under
  the beam. A line's characters are taken as it starts, so a write later in the line shows on the next frame, not on
  its later dots.
- Reads that nothing answers return `$00`, as MAME's do, and RAM comes up in runs of 64 `$00` and `$FF` bytes, as
  MAME fills it, so the RAM test runs the same. The VIA's PB1-PB4 read as zeros when made inputs, as in MAME.
- The keyboard types ASCII and the PETSCII control codes (RETURN, DEL, HOME, CLR, the cursor keys, RVS, STOP),
  holding each key for three frames and releasing it for three, twelve after RETURN.
- Sound is CB2's level, as 48 kHz stereo. Free-running shift mode shifts a bit every second timer 2 timeout.
- `PetRoms.LoadFromDirectory` reads MAME's chip files; BASIC 1 is the revised 901447-09 unless asked for -01.
- Tests: `PetMachineTests` (both BASICs reach `READY.` with the right bytes free for 4K-32K; a typed program runs;
  POKE 59468 switches the character set; snow; the CB2 tone) and `PetOracleTests`.
- **The MAME oracle.** `tools/PetOracle.lua` traces with MAME's debugger.
  - MAME must run with `-ieee8 ""`. Its `tracelog` writes to CPU 0's trace, and with the drive in place CPU 0 is the
    4040's 6502.
  - The comparison leaves out each interrupt, from the vector's target to its RTI, since the interrupts come at
    other times. MAME also logs the instruction it was about to run when it takes the interrupt, then logs it again
    after the RTI, so that repeated row is dropped.
  - The comparison also leaves out the editor's `LDA $E840 / AND #$20` retrace waits, then collapses repeated
    loops.
  - With that, `pet20018` and `pet2001n` match ours for 3 emulated seconds, about 80,000 instructions each, from
    power-on through `READY.` to the wait for a key.

### 2. Tape

- The Datasette on both ports: motor, play and record, and the sense line, as a device in the Drives view.
- `.tap` images played at pulse level, through the kernal's own read and write routines. `.prg` files are wrapped as
  tape files and played the same way. Saves are written back to the image, through the media persistence pipeline.
- **Done when** LOAD and SAVE work on both ports, with VERIFY passing, against images MAME reads.

**Built 2026-11-16.** Phase 2 is done.

- **`Retrocore.Media.Commodore`** holds the tape and its formats:
  - `CommodoreTape`, a medium (`IMedium`) of pulses in microseconds, one PET cycle each. A recording replaces the
    tape from the head on. Its snapshot is a TAP image.
  - `TapFormat` reads TAP versions 0 and 1, by the header's machine and video clock, and writes version 1 for the
    PET (machine 3) in 8 µs units. MAME reads every TAP image at the C64's PAL clock, so it plays a PET image 1.5%
    slow. The loaders don't mind.
  - `CommodoreWave` reads 8- and 16-bit PCM WAV recordings, a pulse running from one fall through the middle to the
    next, and writes a square wave.
  - `CommodoreTapeCodec` saves as TAP, which keeps everything, or WAV, which rounds each pulse to its samples; neither
    keeps the record tab.
  - `CommodoreTapeBuilder` makes a `.prg` file into the tape SAVE would write.
- **MAME's PET tapes are WAV recordings**, not TAP images, so the Datasette reads both.
- **`CommodoreDatasette`** (`PetDatasette` until the VIC-20 shared it), one on each port, is an `ITapeDrive` and an `IMediumSlot` that saves as `tap` or `wav`. It has
  PLAY, RECORD, STOP, rewind and wind. The sense line is low while a key is down, and the motor runs while its line is
  low (cassette 1: PIA 1's CB2; cassette 2: the VIA's PB4), as MAME's C2N has them. The read line goes to PIA 1's CA1
  or the VIA's CB1. It falls at each pulse's start and rises halfway. Recording measures from each rise of the VIA's
  PB3 to the next, since the Datasette inverts what it records.
- **The PET's own tape**, read back from a SAVE, is the format the builder writes:
  - pulses of about 352, 504 and 672 µs;
  - leaders of 27,136 shorts ($6A00) before the header and 5,376 ($1500) before the program;
  - each block twice, the first copy with sync bytes $89-$81 and an end marker (long, short) and 79 shorts, the second
    with $09-$01 and 80 shorts;
  - a byte as long, medium, 8 bits from the lowest and an odd parity bit, each bit short-medium (0) or medium-short
    (1);
  - an XOR checksum;
  - a 192-byte header: type 1, start, end, the name, and spaces.
- The machine's devices are the two Datasettes, `cassette1` and `cassette2`. The Drives view and launch configuration
  pick them up in phase 4. Until then a host loads a tape and keeps the image itself.
- Tests (`PetTapeTests`):
  - SAVE, LOAD, RUN and VERIFY on both ports of both models;
  - a tape built from a program file loads in both;
  - MAME's `hardcore` quickload, built into a tape, loads byte for byte;
  - Count'Em (1980), a WAV from MAME's list, loads in both. Space Fight and Supermon load too;
  - TAP keeps every pulse, and reads a C64 image at its clock;
  - a tape saved as WAV still loads;
  - the Datasette's media state and saves;
  - MAME loads our saved tape, as TAP and as WAV, to the same bytes (`tools/PetTapeLoad.lua` types LOAD and presses
    PLAY).

### 3. ROM sources

- The BASIC 1 and BASIC 2 overlays on `m6502.asm`.
- The editor and kernal for both versions, and the character ROMs, in `Roms`, as our own native sources that
  assemble byte-identically to the chips. They have `;;` documentation and IntelliSense, as the Apple II's sources have.
- Tests pin every build by digest. Without dumps, the machine runs the SDK's builds.
- **Done when** every build is byte-identical to its chip, `SdkDocumentationIsClean` passes, and the machine boots
  from the SDK's builds.

**Built 2026-11-16.** Phase 3 is done.

The SDK now defaults to the native `Basic1.asm`, `Basic2.asm` and `Basic4.asm` roots; the overlays below remain
available with `basicSource: "macro10"`.

- **The sources** are in `src/Retrocore.Machines.Commodore/Roms`:
  - `Basic/Basic1.mac` and `Basic/Basic2.mac`, MACRO-10 overlays on `m6502.asm`, now named by its path in the shared
    BASIC project.
  - `Basic1/` and `Basic2/`, each with `Editor1.asm`/`Editor2.asm` and `Kernal1.asm`/`Kernal2.asm`, an `Equates.asm`
    of page zero, pages 2-3 and constants, and entries files so each module names the other's routines.
  - `PetEquates.asm` for the hardware.
  - `CharacterGenerator.asm`.
  - A module takes its name from its root file, so each version's editor and kernal have their own (`Editor1:`,
    `Kernal2:`).
- **BASIC 2** is `m6502.asm`'s Commodore build, `REALIO` 3, with three changes:
  - long error messages (`LNGERR`);
  - a spare NOP in NEWSTT;
  - PEEK's check against reading BASIC's own ROM, patched to NOPs.
- **BASIC 1** is an earlier Microsoft BASIC: about 500 lines of edits.
  - Its page zero puts BUF at `$0A`.
  - It has no GO keyword, no NULL keyword, and "BAD DATA".
  - It has the code from before the fixes in the base's change log, back to 12/1/77.
  - It has Commodore's patches into the editor ROM (INPUT's STOP, TI and TI$ in arrays, GET, TRMPOS and arrays).
  - `REVISD` picks the first chip. The revised 901447-09 fixes STKINI, which in the original 901447-01 stored a
    return address before moving the stack pointer, so the 60 Hz interrupt could overwrite it.
- **BASIC runs past `$DFFF`**:
  - Each editor chip starts with BASIC's end: its math package, INIT and its sign-on, to `$E1DD` in BASIC 2 and
    `$E1E0` in BASIC 1.
  - BASIC 1 has one more patch at `$E7F3-$E7F8`.
  - The overlays build those bytes. The editor sources start after them (`$E1DE`, `$E1E1`) and leave the patch
    out.
  - `PetSdkModules.EditorImage` puts the chip together.
- **The two character ROMs** are one source; `ORIGINAL` selects the 2001's 901447-08.
  - Its second set has capitals at `$01-$1A` and lowercase at `$41-$5A`, where the 901447-10 has them the other way
    round.
  - Each glyph group is a macro, written once for both sets.
  - `PetVideo` reads the swap from the ROM, so copying text from the screen gives the right case on either chip.
- **The kernals** hold the IEEE-488 routines, the files behind OPEN, CLOSE, GET#, INPUT#, PRINT# and CMD, LOAD,
  SAVE and VERIFY, the cassettes' pulse reader and writer, the jiffy clock and reset. BASIC 1's has the factory test
  at reset. BASIC 2's has the machine-language monitor, entered through BRK.
- **Found while writing the sources**, and documented in them:
  - BASIC 1's OPEN loops for ever with ten files open, instead of giving ?TOO MANY FILES.
  - Its IEEE-488 verify sets the wrong status bit, so VERIFY from a disk would not report a mismatch.
  - Its NMI vector's low byte is the RTS that ends MOTOROFF.
- **`PetSdkModules`** (in the debug host, which the tests reference) assembles each part and builds a model's
  `PetRoms`.
  - The SDK copies `m6502.asm` into `Roms/Microsoft6502Basic`, beside `Roms/Pet`; `OverlayBaseResolver` finds it there
    when the PET overlays' repository-relative paths do not apply.
  - The disassembler gained `--machine none`, which names nothing outside the program, for another machine's ROM.
- Tests (`PetRomSourceTests`):
  - each build is pinned by digest, and with the dumps present a failure names the first differing byte;
  - both models boot to `READY.` from the SDK's builds alone.
  - `SdkDocumentationTests`, including the repository-wide editor lint, are clean.

### 4. The debugger and extension

- `PetDebugTarget`: source-level debugging of the kernal, editor and user programs, with breakpoints, the call
  stack, memory, the screen in the display view, and memory hints.
- BASIC debugging, as Color BASIC has it: `CommodoreBasicDialect` tokenizes and lists PETSCII programs. It adds
  breakpoints on BASIC lines, stepping by statement, and variables in the Variables view. BASIC programs can be
  edited in VS Code.
- The extension's `pet` entries, launch configuration and Start Machine with a program, a BASIC file or a tape.
  The Machine view's devices and the Drives view's tape.
- The Desktop's catalog entry, icon and key map.
- A `docs/Pet.md` guide, the README's machine list, and the extension README.
- **Done when** a breakpoint in the kernal and one on a BASIC line both stop. Start Machine runs a `.bas` file on
  each model, and the DAP test script passes.

**Built 2026-11-16.** Phase 4 is done and awaits review. The user guide is [docs/Pet.md](../Pet.md).

- **`PetDebugTarget`** (machine `pet`) launches either model.
  - Options: `basicRevision`, `ramKilobytes`, `romDirectory`/`RETROCORE_PET_ROMS` (MAME's chips; without them the
    SDK's builds), `snow`, `sound`, `cassette1` and `cassette2` (`.tap`, `.wav`, `.prg`), `fastCassette` and
    `screen`.
  - BASIC, the editor and the kernal debug against their sources whenever the running ROM is that source's build.
    The bus reports BASIC's bytes in the editor's chip as BASIC's area, so each module maps only its own range.
  - The exception filters are reset, BRK (BASIC 2's monitor), the Keeps checks and BASIC's.
  - A `.prg` program loads where its first two bytes say. At `$0401` it is a BASIC program: its pointers are set and
    RUN is typed. Any other address is machine code.
  - Sources load at `$0800`, after a three-second boot to `READY.`.
- **The BASIC thread** follows NEWSTT and GONE, as AppleSoft's does. Every page-zero address comes from the running
  BASIC's assembled symbols, because BASIC 1 and 2 keep page zero in different places. Error messages come from
  BASIC's own ERRTAB.
- **The dialect is `PetBasicDialect`**, not the plan's `CommodoreBasicDialect`. It has one name, `petbasic`, for
  both versions, and the machine picks the version, as for AppleSoft.
  - Its tokenizer is each ROM's CRUNCH: BASIC 1 skips spaces inside words and has no GO. `PetBasicConformanceTests`
    runs the ROMs' own CRUNCH on a 6502 against it, byte for byte.
  - Lowercase outside strings, DATA and REM becomes capitals.
  - PETSCII that can't be typed uses the existing `{$hh}` escapes. Named escapes such as `{CLR}` would need the
    dialect passed through `BasicText`, so they wait.
  - The evaluator gives -1 for true and works AND, OR and NOT bit by bit, as Microsoft's base does.
  - `Keywords.txt` has help for its 76 words.
  - The extension has a `retrocore-petbasic` language and grammar, and the language server maps it.
- **The Datasettes' save path:** `MediaActions` saves a Commodore tape as TAP or WAV. A recording is a changed tape,
  so Save, Save As and eject treat it as they do a changed disk.
  - The Drives view and the Desktop's pane give the Datasettes their keys: Play, Record, Stop and Rewind.
  - The Desktop's Save As says "Save Tape As..." for a tape.
- **The extension:**
  - both models in the dropdown and Start Machine (a `.prg` or `.bin` program, a `.bas` file, a tape or a source);
  - the launch schema and snippets;
  - the display's key bar (Stop, Clr, Reset) with PETSCII codes, 320/200 square dots, Fast tape, and the tapes'
    status;
  - the icon, the README section, and tests.
- **The Desktop:** both models in the catalog (memory, snow, sound, and BASIC 1's revision), its key map, aspect,
  icon and fast tape.
- **The docs:** `docs/Pet.md`; the README's machine table, sources, projects, environment variables, DAP scripts and
  Plans; the extension README; and CI runs `tools/Test-PetDap.mjs` and `tools/Test-PetBasicDap.mjs`.
- **PGO:** no refresh. The profile trains Apple II workloads only, and no Apple II, 6502 or Desktop execution path
  changed.
- **Not done:**
  - The extension's VS Code suite stops where it needs IIe dumps on this machine, as it did before these changes.
  - The PET has no memory-hints file of its own yet; the generic hints work.

### 5. Disk drives

- The IEEE-488 bus, as a shared line model that the PET's PIA 2 and VIA and any number of devices drive.
- The 2040 and 4040 at the hardware level: the 6502 and 6504, the RIOTs and the 6530, the drive's GCR read and write
  electronics, and two drives per unit. `.d64` and `.g64` images, saved back when written.
- Device numbers 8 to 15, chosen in the Machine view. The Drives view shows each unit's two drives.
- **Done when** `LOAD "$",8` lists a disk, LOAD, SAVE and the drive's commands (`N`, `S`, `R`, `V`) work on BASIC 2,
  and drive traces match MAME's `c4040`.

**Built 2026-11-16.** Phase 5 is done for the 4040 and the 2040, and awaits review.

- **The bus:** `Ieee488Bus` holds each device's `Ieee488Port`, and every line is the AND of what they drive. The PET
  is wired as MAME's `pet` driver has it: PIA 2's ports and CA2, CB2 and CA1, the VIA's PB0-PB2 and PB6-PB7, and
  PIA 1's PA6 and CA2.
- **The chips:** `Riot6532` and `Miot6530` in `Retrocore.Core`, on a shared `RiotBase`: RAM, ports, the interval
  timer, the 6532's PA7 edge and the 6530's interrupt on PB7. PA7's level at reset is the one its edges are seen
  from. Without that, the drive took a phantom ATN at start-up that MAME does not.
- **The 4040:**
  - `Cbm4040` holds both processors and their maps (`Cbm4040DosBus`, 15 address lines; `Cbm4040ControllerBus`, 13).
  - It has the four shared buffers and the ATN gates.
  - It steps both processors and the read/write logic each microsecond.
  - Its ROMs are `Cbm4040Roms`, MAME's `c4040` set with either DOS 2.0 revision.
- **The read/write logic:**
  - `Cbm4040Fdc` is MAME's `c2040fdc` logic: the 16 MHz cell counter, the shift registers, the sync and bit
    counters, and the GCR PROM's decode and encode. It runs from event to event: each cell boundary and each flux
    change.
  - READY and ERROR last a clock, so they reach the VIA's CA1 and CB1 as edges.
  - A write starts at the cell under the head and puts each bit in the next cell. A bit's time and a cell's differ by
    a fraction of a clock. Over the formatter's 2.4-turn writes in zone 2, following the head would drop a bit, and
    did.
- **The mechanisms:** `CommodoreFloppyDrive`, two per unit (`disk8-0`, `disk8-1`). Each has a half-track stepper
  that moves only with its motor on, a 300 rpm disk, write protection, and the unsaved mark.
- **The media,** in `Retrocore.Media.Commodore`:
  - `CommodoreDisk` holds 84 half-track positions of cells.
  - `GcrLayout` lays out and reads DOS 2.0's sectors. Track lengths are whole bytes (7,692, 7,142, 6,666 and 6,250),
    as a G64 keeps them. With odd cell counts, a G64 round trip broke the sector that crossed each track's start.
  - `D64Format` reads and writes sectors, naming any it cannot read. `G64Format` keeps every cell. `CommodoreDiskCodec`
    picks between them by contents. `MediaActions` saves a Commodore disk as either.
- **The debugger:**
  - Launch options: `diskUnits` (device numbers), `disks` (images, two per unit), and `driveRomDirectory`.
  - The Machine view has rows `ieee8` to `ieee15`; Add Card (`add4040`) and Remove Card connect and disconnect a
    unit while the machine runs, and `Cards`/`RestoreCards` keep them for the next launch.
  - The drives insert, eject, write-protect and save.
  - `retro/media` names them as `disk8-0` and so on.
- **The clients:** the extension's and the Desktop's Add Card list the 4040 for the PET's device rows; the launch
  schema has the new options, and `diskUnits` and `driveRomDirectory` count as hardware options.
- **Tests:**
  - `PetDiskTests`: the demo disk's directory; format, SAVE, LOAD, RUN, `S`, `R` and `V` on a blank disk; D64 and G64
    write-back; write protection.
  - `Cbm4040FdcTests`: every byte read in each zone, and bytes written and read back.
  - `CommodoreDiskImageTests`, which needs nothing external.
  - `Pet4040OracleTests` against MAME's `c4040`, through [`tools/Pet4040Oracle.lua`](../../tools/Pet4040Oracle.lua):
    power-on with registers, and `LOAD "$0",8` by addresses, each of its seven ATN services.
  - `tools/Test-PetDap.mjs`, with the dumps: a disk formatted, saved through the host as D64, and listed, and a second
    unit added and removed.
- **Oracle notes:**
  - The DOS's ATN handler resets the stack and goes back to the main loop, so the comparison cuts the traces at each
    ATN.
  - MAME's PET takes its interrupts at other times, with no beam, so the handshakes race. A line can read as
    released in one and not yet in the other. After the first ATN, the oracle compares addresses, with each polling
    loop collapsed to its last pass.
- **The 2040,** added once its DOS 1.2 dumps were fetched:
  - It is `Cbm4040` with MAME's `c2040` ROMs (`Cbm4040Roms.Load2040FromDirectory`): DOS 1.2's 8K at `$6000`, the
    first socket empty, and the 6530's 901466-01. `Cbm4040.Model` says which a unit is, and MAME's `c2040` and
    `c4040` are one device with other ROMs and disk formats.
  - DOS 1 lays out 20 sectors on tracks 18-24, 690 in all, with shorter syncs and gaps (`CommodoreDos`,
    `GcrLayout`'s layout parameter, MAME's `c3040` format). `D67Format` reads and writes its images. DOS 1 formats
    headers alone and writes a sector's data when it first uses it, as MAME's DOS 1 demo disk shows, so a D67 keeps
    a sector with a header and no data as zeros without a loss.
  - DOS 1 reads a disk only after the `I` command; until then a LOAD waits for good, on MAME as here.
  - The debugger loads both sets (the `c2040` folder in or beside the ROM directory); `diskModel` picks the launch's
    units, Add Card offers both (`add2040`), and a 2040's drives save as G64 or D67.
  - Tests: `Pet2040DiskTests` (the DOS 1 demo disk read as D67 and listed after `I`, as MAME lists it; format, SAVE,
    LOAD, RUN, `S`, `R`, `V` and D67 write-back), D67 image tests, `Pet4040OracleTests`' power-on and `I` command
    against MAME's `c2040`, and the DAP script adding and removing a 2040.
- **PGO:** no refresh. The profile trains Apple II workloads only. The drive's code runs only on the PET, and no
  Apple II, 6502 core or Desktop hot path changed.
- **Not done:**
  - The 3040, the 2040's European name: MAME's `c3040` is the same ROMs, so it would be a label.
  - BASIC 1 with the drive is untested.
  - The debugger loads DOS 2.0's second revision only; `Cbm4040Roms` can load the first.
  - Sources for the drive's ROMs: they load from dumps.

### 6. BASIC 4 and the later PETs

**Agreed 2026-11-17.** Stages 1-3 are built and await review.

The 4016 and 4032 are the 2001N's board, without a CRTC ("thin 40"), with the BASIC 4 chips. MAME's sets:

| MAME set | Keyboard | Chips |
| --- | --- | --- |
| `pet4016`, `pet4032` | Graphics | 901465-23 (or -19) `$B000`, -20 `$C000`, -21 `$D000`, editor 901447-29, kernal 901465-22 |
| `pet4032b` | Business | The same, with editor 901474-02 |
| `pet4032f` | Graphics | Editor 901499-01, which drives a 6545 CRTC ("fat 40") |

Decisions:

1. **The models.** `pet4032` (graphics keyboard) and `pet4032-business` (business keyboard), with
   `ramKilobytes` 8, 16 or 32. The catalog lists the PET 4016 and the PET 4032 as the graphics model with 16 KB and
   32 KB. The fat 40 joins the 8032 phase, since both need the CRTC.
2. **BASIC 4** is `Basic/Basic4.mac`, an overlay on `m6502.asm` as BASIC 1 and 2 are. `REVISD` picks 901465-23 or
   -19 (60 bytes differ). The base's names stay. Commodore's additions (the disk commands, the new garbage collector)
   take the names from Commodore's 1979 BASIC 4 listing where the code is the same.
3. **The editors and kernal** are our own native sources in `Basic4/`, byte-identical to the chips: `Editor4.asm` with
   a `BUSINESS` switch if the two editors share enough code, otherwise two files, and `Kernal4.asm`. They use
   Commodore's 1979 listing names, which match most closely here, since this is the code that listing became.
4. **The business keyboard** is its own matrix and host key map in `PetKeyboard`.
5. **The 4040 is standard.** A 4000 launches with a 4040 at unit 8 when the drive ROMs are present, and
   `diskUnits: []` turns it off.
6. **The dialect.** `petbasic` gains BASIC 4's words: `CONCAT`, `DOPEN`, `DCLOSE`, `RECORD`, `HEADER`, `COLLECT`,
   `BACKUP`, `COPY`, `APPEND`, `DSAVE`, `DLOAD`, `CATALOG`, `RENAME`, `SCRATCH`, `DIRECTORY`, and `DS` and `DS$`.
   The conformance test runs BASIC 4's CRUNCH as well.
7. **Downloads.** These need your OK, each shown with its site and checksum:
   - MAME 0.264's `pet4032b.zip`, for 901474-02, from the same archive.org set as phase 0;
   - mist64/cbmsrc's `BASIC_PET_V4_1979-07-23`, used for names only, into the scratchpad as the kernal listing
     was.

Stages, each ending in a review:

1. **The machine.** Both models boot to `READY.` from the dumps with the right bytes free, `DIRECTORY` lists the
   4040's demo disk, and traces match MAME's `pet4032` and `pet4032b` from power-on.
2. **The sources.** The kernal, both editors and BASIC 4 assemble byte-identically, both revisions, pinned by digest,
   and the machine boots from the SDK's builds.
3. **The debugger and clients.** The BASIC thread and variables on BASIC 4, the dialect's new words, the extension's
   and the Desktop's entries, icons and key maps, docs, and the DAP scripts on a 4032.

The 8032's 80-column video and its 6545 CRTC would be phase 7, if you want it.

**Stage 1, built 2026-11-17:**

- **Fixtures:** MAME 0.264's `pet4032b.zip` is in `pet-roms` (`extract\pet4032b`, and the `mame` path), and MAME 0.289
  verifies it. Its one new chip is 901474-02. Commodore's 1979 BASIC 4 listing is in the scratchpad, for names.
- **`PetModel`:** `Pet4032` and `Pet4032Business`. `PetModels` gives each model's `BasicVersion` (1, 2 or 4) and
  `HasBusinessKeyboard`.
- **`PetRoms.LoadFromDirectory`** loads BASIC 4 from MAME's `pet4016` or `pet4032b` chips. `original` picks
  901465-19 over -23 at `$B000`, as it picks BASIC 1's 901447-01.
- **`PetBus`:** BASIC 4's `$B000-$BFFF` counts as BASIC, not an option ROM, and its editor's chip is all editor.
- **The business keyboard:** `PetBusinessKey`, from the editor's own key table at `$E60B` in 901474-02, which agrees
  with MAME's `petb` matrix. `PetKeyboard` takes either layout. It types each symbol as its key with SHIFT, since the
  editor makes `$21-$3F`'s shifted characters by flipping bit 4.
- **Tests:**
  - `PetMachineTests`: both models boot to `*** COMMODORE BASIC 4.0 ***` with the right bytes free for 8K-32K. On
    both keyboards, a typed program prints every symbol.
  - `PetDiskTests`: `DIRECTORY` lists the demo disk on both keyboards and leaves the program in memory. `HEADER`,
    `DSAVE`, `DLOAD`, `RENAME`, `SCRATCH` and `DS$` work on a blank disk.
  - `PetOracleTests`: MAME's `pet4016` (16K) and `pet4032b` (32K) match ours from power-on to the wait for a key.
- **Left for stage 3:** the debug host, extension and Desktop don't offer the new models yet, and the 4040 is not
  yet standard at launch. The debug host turns snow on for every model; only the 2001 should have it.
- **PGO:** no refresh. The profile trains Apple II workloads only, and nothing they run changed.

**Stage 2, built 2026-11-17:**

- **`Basic/Basic4.mac`** (about 2,450 lines) assembles byte-identically to 901465-23, -20 and -21, or with `REVISD=0`
  to 901465-19, -20 and -21.
  - BASIC 4 is the base's `REALIO=3` build moved to `$B000`, with the disk commands, `DS` and `DS$`, and the faster
    garbage collector, which links each string back to its descriptor.
  - The `$D000` chip also holds the machine-language monitor (`CALLE`, `BRKE`) and the code behind the disk commands,
    which the kernal's jump table at `$FF93` calls. Nothing spills into the editor's chip.
  - The revised `$B000` chip differs in 60 bytes: its checksum byte and three patches in the chip's spare room. GONE
    no longer runs π as a statement, through bytes past the dispatch table. STRADJ takes a string for `DS$` only
    while a disk status is held. INPUT# takes a blank line at the end of a file instead of reading again.
  - MACRO-10 keeps six characters of a name and no underscores. So the jump table's disk entries are `CQCONC`,
    `CQDOPN` and so on, after m6502.asm's `CQ` entries, and names that clash with the base's become `DCOPY`, `DSCRTC`,
    `MGO`, `GTVLCN`, `KCOUNT`, `PRSCHK` and `RECPOS`.
- **`Basic4/`** holds `Kernal4.asm` (901465-22), `Editor4.asm` and `Equates.asm`, `EditorEntries.asm`,
  `KernalEntries.asm` and `BasicEntries.asm`, as BASIC 2's folder does.
  - With `BUSINESS=1`, `Editor4.asm` builds 901474-02 instead of 901447-29. The business editor adds TAB stops,
    REPEAT and ESC.
  - The kernal's routines take Commodore's 1979 listing's names, and its disk entries use the overlay's names.
  - Each chip has a byte that makes its checksum come out to its page: `CKSUME` in the editors, `CKSUMF` in the kernal.
- **What changed from BASIC 2, found while writing the sources and documented in them:**
  - LOAD from a disk sends its secondary address with `TKSA`, which turns the bus around; the 1979 listing still has
    `SECND`.
  - LOAD gives ?FILE NOT FOUND when the disk sends no first byte.
  - With `BOB` bit 7 set, the bus waits until STOP instead of timing out.
  - The editor no longer waits for the retrace to store a character.
  - SHIFT-RUN types `DLOAD "*"` and RUN.
- **`PetSdkModules`** builds BASIC 4: `BasicOrigin` and `BasicSize` are per model, `BasicFile` names the overlay,
  `REVISD` covers BASIC 1 and 4, and the editor gets `BUSINESS`.
- **The debug host's `--assemble`** takes `--define NAME=value`, so a build's switches can be set from the command
  line.
- **Tests:**
  - `PetRomSourceTests` pins both BASIC 4 builds, both editors and the kernal by digest.
  - Both 4032 models boot from the SDK's builds alone.
  - `SdkDocumentationTests` is clean.
- **Fixed on the way:** the TRS-80 Model I and Model III oracles gave MAME the NEWDOS fixture itself, which MAME locks
  to write back. Tests reading it at the same time failed now and then. Both now give MAME a copy.
- **The monitor and disk commands** in the overlay follow Commodore's own 1979 kernal listing, comments included.
  The user chose this on 2026-11-17: the code is Commodore's, in BASIC's ROM, and needed one patch (`DSLINK`) to
  match the chip.
- **PGO:** no refresh. No Apple II, 6502 core or Desktop path changed.

**Stage 3, built 2026-11-17:**

- **The debug host:**
  - `model` takes `pet4032` and `pet4032-business`.
  - `ramKilobytes` defaults to 32 on a 4032. `snow` is on by default only on the 2001, whose board has it.
  - `basicRevision` picks BASIC 4's `$B000` chip too.
  - Dumps come from the `pet4016` and `pet4032b` folders.
  - A 4032 gets a 4040 as device 8 when the drive's ROMs are found, unless `diskUnits` is given (`[]` leaves it
    out).
  - The Machine view, the thread (`PET 4032 6502`) and the ROM row name the model and BASIC 4's revision.
- **The dialect:**
  - `PetBasicDialect.Basic4` (`BasicDialect.PetBasic4`) has BASIC 2's words and the fifteen disk commands,
    `$CC-$DA`, with the same pointers as BASIC 2.
  - `petbasic` now names BASIC 4, the superset, as AppleSoft's and Color BASIC's names do theirs. A running machine
    still reads and writes programs with its own version.
  - `Keywords.txt` has help for the new words.
  - `PetBasicConformanceTests` runs BASIC 4's CRUNCH on lines using every disk command.
- **The BASIC thread and variables** work unchanged on BASIC 4, from its assembled symbols.
- **The extension:**
  - `pet4032` and `pet4032-business` are in the dropdown and Start Machine, with a `.d64` or `.g64` going into the
    4040's drive 0.
  - The launch schema, labels and grammar (91 words) are updated, and Tab sends the business keyboard's TAB.
- **The Desktop:** both 4032s in the catalog, with Memory (32 KB, or 16 KB for the 4016), the BASIC 4 revision and
  sound; Tab in the key map. A separate 4016 entry would need number-valued catalog options, so the Memory choice
  stands for it, as in the extension.
- **The docs:** `docs/Pet.md`, the README and the extension README cover the 4032.
- **The DAP scripts:**
  - `Test-PetBasicDap.mjs` runs on BASIC 4 with both keyboards.
  - `Test-PetDap.mjs` boots a 4032 from the sources, stops in `Kernal4.asm` and at reset, and checks that
    `diskUnits: []` leaves the drive out.
  - With the 4040's ROMs, it formats a disk with `HEADER`, lists it with `DIRECTORY`, and checks that the drive comes
    by default.
- **PGO:** no refresh. The profile trains Apple II workloads only, and no Apple II, 6502 core or Desktop hot path
  changed.
- **Not done:** the extension's VS Code suite (`test:editor`) still stops where it needs IIe dumps on this machine.

## Performance

The PET runs at 1 MHz, so speed is not a concern. The 6502 core does not change. AGENTS.md's PGO rule applies only if
the PET joins the Desktop's training workloads. Phase 4 decides that and states the decision.

## Not planned

- The SuperPET's 6809 and its Waterloo languages, which would build on the CoCo's 6809. They are a later machine.
- The CBM 8050 and 8250 drives (`.d80` and `.d82`), until the 4040 works.
- The PET's IEEE-488 printers and modems.
