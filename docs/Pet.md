# The Commodore PET 2001 and 4032

Retrocore's PET is [`PetMachine`](../src/Retrocore.Machines.Commodore/PetMachine.cs): a cycle-exact NMOS 6502 with
the PET's memory map, its two 6520 PIAs and 6522 VIA, the 40x25 screen with the 2001's video timing, the
keyboard, sound on the VIA's CB2, two Datasettes and the IEEE-488 bus with 4040 and 2040 disk drives.
[`PetModel`](../src/Retrocore.Machines.Commodore/PetModel.cs) picks the board, keyboard and ROMs:

| Model | Launch `model` | What it is |
| --- | --- | --- |
| PET 2001 | `pet2001` | BASIC 1, as the 2001 shipped in 1977: the white screen and the chiclet keyboard. |
| PET 2001 with BASIC 2 | `pet2001-basic2` | Commodore's upgrade ROMs, the 2001-N's: the first BASIC whose IEEE-488 routines work with disk drives. |
| PET 4032 (or 4016) | `pet4032` | BASIC 4 with its disk commands, on the 2001-N's board without a CRTC ("thin 40"), with the graphics keyboard and a 4040 as device 8. The 4016 is the same with 16 KB. |
| PET 4032 with the business keyboard | `pet4032-business` | The same, with the business keyboard and its editor. |

This guide covers what it emulates, its ROMs and their sources, tapes and disks, and how to debug on it.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | `$0000-$7FFF` | 4, 8, 16 or 32 KB from `$0000`; BASIC programs start at `$0401`. Past the RAM, reads see `$00`. |
| Video RAM | `$8000-$83FF` | 1 KB, 40x25 characters, repeated to `$87FF`. |
| Option ROMs | `$9000-$BFFF` | Empty sockets; BASIC 4 fills `$B000-$BFFF`. |
| BASIC | `$C000-$E1E0` | BASIC 1 or 2, which runs on past `$DFFF` into the editor's chip; BASIC 4 is `$B000-$DFFF`. |
| Screen editor | `$E1E1-$E7FF` | The keyboard and screen, and the 60 Hz interrupt; BASIC 4's fills `$E000-$E7FF`. |
| I/O | `$E800-$EFFF` | Address bit 4 selects PIA 1 (`$E810`), bit 5 PIA 2 (`$E820`) and bit 6 the VIA (`$E840`). |
| Kernal | `$F000-$FFFF` | Files, the IEEE-488 bus, the cassettes, the jiffy clock and reset; BASIC 2's adds the machine-language monitor, which BASIC 4 keeps in BASIC's `$D000` chip. |

**CPU.** The 6502 runs at 1 MHz, an eighth of the 8 MHz crystal. It passes the SingleStepTests with every
undocumented opcode.

**Video.** 40x25 characters of 8x8 dots from the 2K character ROM, white on the 2001 and green on the 2001-N and the 4032. A
line is 64 cycles and a frame 260 lines, 16,640 cycles, about 60.1 a second. The retrace line, VIDEO ON, is low for
the first 3,840 cycles of each frame (vertical blanking) and high for the 200 displayed lines, whose characters are
drawn from cycle 23. Its fall interrupts through PIA 1's CB1, which drives the jiffy clock and the keyboard scan; the
VIA's PB5 reads it, and BASIC 1's editor writes to the screen only while it is low. The VIA's CA2 picks the
character set: uppercase and graphics, or the set with lowercase (`POKE 59468,14`, and back with 12). PIA 1's CA2
low blanks the screen.

**Snow.** On the 2001's board the CPU and the display share video RAM, so a CPU access while a line is drawn shows
its byte under the beam: snow. The display's frame shows it, as the scanned picture (`snow`, on by default for the
2001 and off for the later boards, which have none).

**Keyboard.** The 2001's 73-key chiclet keyboard as its 10x8 matrix, which PIA 1's PA0-PA3 select and port B reads.
The 2001-N's and the 4032's graphics keyboard is wired the same way. The symbols are on unshifted keys and the digits
on the numeric pad; SHIFT with a letter types a graphics character. The business keyboard
([`PetBusinessKey`](../src/Retrocore.Machines.Commodore/PetBusinessKey.cs)) is a typewriter's, with the digits on the
top row and their symbols shifted, TAB, ESC and REPEAT, wired to the same ten rows in other places; its matrix is the
one its editor's key table reads. Typed text holds each key for three frames, with SHIFT where a symbol needs it.

**Sound.** The VIA's CB2, which programs drive from its shift register for tones. The 2001 has no speaker of its
own; owners wired one to CB2 on the user port, as PET music programs expect.

**Datasettes.** Two Commodore C2N Datasettes, on cassette ports 1 and 2:

| | Cassette #1 | Cassette #2 |
| --- | --- | --- |
| Read | PIA 1's CA1 | The VIA's CB1 |
| Motor (low runs it) | PIA 1's CB2 | The VIA's PB4 |
| Keys (low while PLAY is down) | PIA 1's PA4 | PIA 1's PA5 |
| Write | The VIA's PB3 | The VIA's PB3 |

A tape is its pulses, each from one fall of the read line to the next, to the microsecond. The kernal's own routines
read and write them, so anything a PET could load loads. A Datasette takes:

- `.tap` images (VICE's TAP format, versions 0 and 1, at the clock their header names), which save back exactly;
- `.wav` recordings, as MAME's PET software list holds them, which save with each pulse rounded to the sample;
- `.prg` program files, made into the tape SAVE would write: each block twice after its leader, the header naming
  the program and its addresses.

The keys are the Datasette's: PLAY, RECORD (with PLAY), STOP, and rewinding. A recording is a changed tape: Save or
Save As writes it as `.tap` or `.wav`, and ejecting it asks first, as a changed disk does
([Devices.md](Devices.md#the-debug-protocol)).

**The IEEE-488 bus.** The PET controls the bus: PIA 2's port A reads the eight data lines and port B drives them, its
CA2 drives NDAC and CB2 DAV, and CA1 takes ATN. The VIA's PB0, PB6 and PB7 read NDAC, NRFD and DAV, and PB1 and PB2
drive NRFD and ATN. PIA 1's PA6 reads EOI and its CA2 drives it. Each line is open collector: low while any device
holds it low.

**Disk drives.** [`Cbm4040`](../src/Retrocore.Machines.Commodore/Cbm4040.cs) is Commodore's 4040 dual drive, built
as the board is, and the 2040 before it, the same board with DOS 1.2. It has two processors that share four 1 KB buffers. The DOS processor, a 6502, runs DOS 2.0 and talks
to the bus through two 6532 RIOTs; gates answer ATN in hardware until the DOS follows it. The controller, a 6504,
runs the 6530's ROM and drives the two mechanisms through the 6530 and a 6522.
[`Cbm4040Fdc`](../src/Retrocore.Machines.Commodore/Cbm4040Fdc.cs) is the read/write electronics. It recovers bit
cells from the flux at the speed zone's rate, finds sync marks, and frames bytes. Its GCR PROM (901467) decodes the
bytes read and encodes the bytes written. Each mechanism steps its head a half track at a time and turns its disk at
300 rpm.

- **Device numbers:** a unit can be any of 8 to 15. Add one to a free row in the Machine view, or with the launch's
  `diskUnits`, such as `[8, 9]`, and `diskModel`, `4040` (the default) or `2040`.
- **Images:** a drive takes `.d64` images, whose sectors are laid out as DOS 2.0 formats them in the four speed
  zones (21, 19, 18 and 17 sectors); `.d67` images, laid out as DOS 1 formats them (21, 20, 18 and 17 sectors); and
  `.g64` images, which keep every cell of every half track.
- **Saving:** a disk the drive has written is a changed disk. Save writes it back to its image, and Save As writes
  it as G64 or as the unit's sectors: D64 on a 4040, D67 on a 2040. A sector image holds only the sectors that read:
  any sector the drive cannot read is written as zeros, and the save names each one. DOS 1 formats a sector's header
  alone and writes its data when it first uses it, so on a D67 a sector it never wrote is zeros without a loss.
- **ROMs:** each unit runs its own ROMs. The 4040's are MAME's `c4040` set: DOS 2.0 (901468-14 to -16), the
  controller's 901466-04 and the GCR PROM 901467. The 2040's are its `c2040` set: DOS 1.2 (901468-06 and -07, at
  `$6000`, with the first socket empty), the controller's 901466-01 and the same PROM. They load from
  `driveRomDirectory`, else `romDirectory` or `RETROCORE_PET_ROMS`: the directory, its `c4040` or `c2040` folder,
  or one beside it. There are no SDK sources for the drives' ROMs, so a unit needs the dumps.
- **DOS 1** reads a disk only once the `I` command has initialized it, as `OPEN 15,8,15,"I0":CLOSE 15` does; until
  then a LOAD waits for good. DOS 2 initializes a disk itself.

BASIC 2's and 4's disk commands work through the DOS's own code:

```basic
OPEN 15,8,15,"N0:NAME,ID":CLOSE 15
SAVE "0:PROGRAM",8
LOAD "$0",8
LIST
LOAD "0:PROGRAM",8
```

The command channel takes the DOS's commands; the tests cover `N` (format), `S` (scratch), `R` (rename) and `V`
(validate). `INPUT#15` in a program reads the DOS's answer, such as `26, WRITE PROTECT ON` for a disk with its notch
covered. The drive is tested with BASIC 2 and 4; BASIC 1's kernal is not.

BASIC 4 has words for them, and a 4032 comes with a 4040 as device 8 when the drive's ROMs are found (`diskUnits: []`
leaves it out). `HEADER` and `SCRATCH` ask ARE YOU SURE? in direct mode, and `DS` and `DS$` hold the drive's last
status:

```basic
HEADER "NAME",D0,IID
DSAVE "PROGRAM"
DIRECTORY
DLOAD "PROGRAM"
PRINT DS$
```

`DIRECTORY` (or `CATALOG`) lists a disk without touching the program in memory. The others are `DOPEN`, `DCLOSE`,
`APPEND`, `RECORD` (relative files), `CONCAT`, `COPY`, `BACKUP`, `COLLECT` (validate) and `RENAME`.

## ROMs

Every ROM the PET runs is an SDK source, maintained by hand and byte-identical to the chips:

| Source | Builds |
| --- | --- |
| [`Basic/Basic1.mac`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic1.mac) | BASIC 1, `$C000-$E1E0` and a patch at `$E7F3`: 901447-01 to -04 and the start of -05. `REVISD` picks the first chip, 1 for the revised 901447-09 (the default), 0 for the original 901447-01. |
| [`Basic/Basic2.mac`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic2.mac) | BASIC 2, `$C000-$E1DD`: 901465-01 and -02 and the start of 901447-24. |
| [`Basic1/Editor1.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic1/Editor1.asm), [`Basic1/Kernal1.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic1/Kernal1.asm) | BASIC 1's screen editor (the rest of 901447-05) and kernal (901447-06 and -07). |
| [`Basic2/Editor2.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic2/Editor2.asm), [`Basic2/Kernal2.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic2/Kernal2.asm) | BASIC 2's screen editor (the rest of 901447-24) and kernal (901465-03), with the machine-language monitor. |
| [`Basic/Basic4.mac`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic4.mac) | BASIC 4, `$B000-$DFFF`, with the machine-language monitor and the disk commands' code: 901465-23 (or, with `REVISD` 0, the original 901465-19), -20 and -21. |
| [`Basic4/Editor4.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic4/Editor4.asm), [`Basic4/Kernal4.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic4/Kernal4.asm) | BASIC 4's screen editors, `BUSINESS` 0 for the graphics keyboard's 901447-29 and 1 for the business keyboard's 901474-02, and kernal (901465-22), whose jump table at `$FF93` leads to the disk commands. |
| [`CharacterGenerator.asm`](../src/Retrocore.Machines.Commodore/Roms/CharacterGenerator.asm) | The character ROMs: `ORIGINAL` 1 for the 2001's 901447-08, 0 for the 2001-N's 901447-10. |

**BASIC** is a MACRO-10 overlay on Microsoft's [`m6502.asm`](../src/Retrocore.Machines.Apple2/Roms/AppleSoft/m6502.asm),
as AppleSoft's is. BASIC 2 is that source's own Commodore build (`REALIO` 3) with three changes: long error messages,
a spare byte in NEWSTT, and PEEK reading BASIC's own ROM. BASIC 1 is an earlier Microsoft version: another page-zero
layout, no GO or NULL keyword, the code from before the fixes in the source's change log, and Commodore's patches into
the editor's chip. The revised first chip fixes STKINI, which in the original stored a return address before moving
the stack pointer, so the 60 Hz interrupt could overwrite it. BASIC runs past `$DFFF`, so each editor chip starts with
BASIC's last bytes: the end of the math package, its start-up and its sign-on.

BASIC 4 is that build moved to `$B000`, with the disk commands, `DS` and `DS$`, and Commodore's faster garbage
collector, which links each string back to its descriptor. Its `$D000` chip also holds the machine-language monitor
and the code behind the disk commands, which follows Commodore's own 1979 kernal listing. The revised `$B000` chip
differs from the original in 60 bytes: three patches, so that pi is not run as a statement, a string is taken as `DS$`
only while a disk status is held, and INPUT# takes a blank line at the end of a file instead of reading again.

**The editor and kernal** sources name BASIC's addresses as `m6502.asm` does, and the kernal's jump table at `$FFC0`
as the Commodore build calls it (`CQOPEN` to `CQCALL`), and BASIC 4's disk entries below it the same way (`CQCONC` to
`CQRDDS`). Routines take Commodore's names from its 1979 BASIC 4 kernal listing where the code is the same. Each
version's files share `Equates.asm` (page zero, pages 2
and 3, and constants) and name each other's routines through `EditorEntries.asm` and `KernalEntries.asm`;
[`PetEquates.asm`](../src/Retrocore.Machines.Commodore/Roms/PetEquates.asm) has the hardware.

**The character ROMs** are two sets of 128 characters. The 2001's chip has its second set's letters the other way
round from the 2001-N's: capitals at `$01-$1A` and lowercase at `$41-$5A`. BASIC 1's editor stores an unshifted letter
at `$01-$1A`, so on a 2001 in the lowercase set, unshifted letters show as capitals and shifted ones as lowercase.

Nothing external is needed: without dumps, both models' ROMs are built from the sources. Dumps can take their place
from a directory under MAME's names: `romDirectory`, or `RETROCORE_PET_ROMS`, in the directory itself or its
`pet2001`, `pet2001n`, `pet4016` and `pet4032b` folders. A blank `romDirectory`, as `${env:RETROCORE_PET_ROMS}` gives when the variable is
not set, names no dumps.

| Model | Files |
| --- | --- |
| PET 2001, BASIC 1 | `901447-01.h1` or `901447-09.h1`, `901447-02.h5`, `-03.h2`, `-04.h6`, `-05.h3`, `-06.h4`, `-07.h7`, and the characters `901447-08.a2` |
| BASIC 2 | `901465-01.ud6`, `901465-02.ud7`, `901447-24.ud8`, `901465-03.ud9`, and the characters `901447-10.uf10` |
| PET 4032 | `901465-23.ud5` or `901465-19.ud5`, `901465-20.ud6`, `901465-21.ud7`, `901447-29.ud8`, `901465-22.ud9`, and the characters `901447-10.uf10` |
| PET 4032, business keyboard | The same, with `901474-02.ud8` for the editor |

## Debugging

Every model is in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts it with a program, a BASIC
file, a tape or a source, and a 4032 with a disk in its 4040's drive 0. Launch configurations take `"machine": "pet"` and a `model`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "PET: hello",
    "machine": "pet",
    "model": "pet2001-basic2",
    "source": "${workspaceFolder}/hello.asm",
    "stopOnEntry": true
}
```

The ROMs run for `bootSeconds` (three seconds by default when something loads) to `READY.` before the program loads,
at `$0800` by default, so the kernal's routines are ready for `JSR $FFD2`. A `.prg` file loads where its first two
bytes say: one at `$0401` is a BASIC program, whose pointers are set as LOAD sets them and which RUN starts (`run`
false leaves it); any other is machine code, which starts at its first byte or `entryAddress`.

The options are:

- `model`: `pet2001` (BASIC 1, a white screen), `pet2001-basic2` (the default, a green screen), `pet4032` or
  `pet4032-business`;
- `basicRevision`: `revised` (the default) or `original`, BASIC 1's first chip or BASIC 4's `$B000` chip;
- `ramKilobytes`: 4, 8, 16 or 32; 8 by default, or 32 on a 4032 (16 makes it a 4016);
- `sdkRoms`: the folder of the ROM sources, such as the repository's, so breakpoints set there bind;
- `snow`: on by default on the 2001, off on the others;
- `sound`: `speaker` (the default) or `off`;
- `cassette1`, `cassette2`: a `.tap`, `.wav` or `.prg` tape, put in with PLAY down; and `fastCassette` (on by
  default), which runs as fast as it can while a tape moves;
- `diskUnits`: the device numbers of disk units on the IEEE-488 bus, such as `[8]`; `diskModel`: `4040` (the
  default) or `2040`; `disks`: `.d64`, `.d67` or `.g64` images for the first unit's drive 0, its drive 1, then the
  next unit's (without `diskUnits`, as many units as they need, from 8, and on a 4032 at least one); and
  `driveRomDirectory`, the drives' ROMs;
- `screen`: `white`, `green` or `amber`;
- `speed`: `1` (the default) runs at 1 MHz, `2`, `4` or `8` that many times as fast, and `"max"` as fast as possible.

The panel's key bar has **Stop** (Esc), **Clr** and **Reset** (Ctrl+F12 or Ctrl+Break). Home is HOME, the arrows the
cursor keys, Backspace DEL, Insert INST, and Tab the business keyboard's TAB. The PET has no reset key; Reset resets the 6502, the PIAs and the VIA,
keeping RAM, as a reset switch does, and **Machine reset** stops at the kernal's first instruction after it. **BRK**
stops at a BRK, which on BASIC 2 and 4 enters the machine-language monitor. The Drives view shows the two Datasettes with
their keys; `retro/media` takes the same requests by `device` `cassette1` or `cassette2`.

BASIC, the editor and the kernal each debug against their source when the machine runs that source's build, dumps
included. BASIC's source covers its end in the editor's chip, which the debugger shows as BASIC's memory area.

**BASIC programs.** PET BASIC programs have the BASIC thread, the program document and `basic` launches, as
AppleSoft and Color BASIC do; the [extension's README](../extension/README.md#basic-programs) describes them. The
dialect is `petbasic` (files named `*.petbasic.bas`, or with `REM retrocore petbasic`), tokenized as each ROM's CRUNCH
does: BASIC 1 skips spaces inside reserved words and has no GO, BASIC 2 crunches `GO TO` as GO and TO, and BASIC 4
adds its fifteen disk commands after GO. A file's dialect is BASIC 4, which has every word; a running machine reads a
program with its own version. Lowercase
outside strings, DATA and REM is made capitals, the PET's unshifted letters. PETSCII that cannot be typed is written
as escapes, such as `{$93}` for CLR. The BASIC thread follows NEWSTT and GONE, as for AppleSoft: BASIC 1, 2 and 4 are
the same Microsoft code, and every page-zero address comes from the running BASIC's assembly, as they keep page zero
in different places. A GOSUB takes seven bytes of the stack, a FOR eighteen, and an error's message comes from BASIC's
own error table. Comparisons give -1 for true, and AND, OR and NOT work bit by bit, as on the PET.

## Testing

| Test | Checks |
| --- | --- |
| `PetMachineTests` | Every BASIC reaches `READY.` with the right bytes free for 4 to 32 KB; a typed program with every symbol runs on each keyboard; POKE 59468 picks the character set; snow; the CB2 tone. |
| `PetOracleTests` (Conformance) | Each model against MAME from power-on, instruction by instruction, through `READY.` to the wait for a key ([`tools/PetOracle.lua`](../tools/PetOracle.lua)). MAME's 2001 has no beam, so interrupts and the editor's retrace waits are left out of the comparison. |
| `PetTapeTests` | SAVE, LOAD and VERIFY on both ports of both models; a tape built from a program file; MAME's quickload and a 1980 WAV recording; TAP and WAV kept and rounded; the Datasette's saves; and MAME loading our saved tape as TAP and WAV ([`tools/PetTapeLoad.lua`](../tools/PetTapeLoad.lua)). |
| `PetRomSourceTests` | Every chip's source by digest, and against the dumps; every model booting from the SDK's builds. |
| `PetBasicDialectTests` | Each BASIC's tokens, lines crunched byte for byte, listings that round-trip, lowercase, pointers and variables in memory, and help for every word. |
| `PetBasicConformanceTests` | Lines crunched by each ROM's own CRUNCH, run on a 6502 from the SDK's build, against the library's tokenizer; the keyword tables and page-zero pointers against the ROMs'. |
| `PetDiskTests` | A 4040 on BASIC 2: `LOAD "$0",8` lists the 2040 demo disk; a blank disk formats; programs save, load and run; `S`, `R` and `V` answer on the command channel; the disk written back as D64 and G64; write protection refuses a SAVE. On BASIC 4, with both keyboards: `DIRECTORY` lists the demo disk and keeps the program; `HEADER`, `DSAVE`, `DLOAD`, `RENAME`, `SCRATCH` and `DS$`. |
| `Pet2040DiskTests` | A 2040 on BASIC 2: MAME's DOS 1 demo disk, a G64 of the real disk, read as D67 sectors, initialized with `I` and listed as MAME lists it; a blank disk formatted as DOS 1, with programs saved, loaded and run, `S`, `R` and `V`, and the disk written back as D67. |
| `Cbm4040FdcTests` | The read/write electronics alone: every byte of a track read back in each zone, and bytes written and read back. |
| `Pet4040OracleTests` (Conformance) | The 4040's DOS processor against MAME's `c4040`: from power-on with no disk, registers and all, and through `LOAD "$0",8` of the demo disk, each ATN the PET sends in order. The 2040's against MAME's `c2040` likewise, from power-on and through the `I` command on the DOS 1 demo disk ([`tools/Pet4040Oracle.lua`](../tools/Pet4040Oracle.lua)). |
| `CommodoreDiskImageTests` | D64, D67 and G64 images round-trip, the zones' track lengths, the codec's choice of format and its losses, and DOS 1's unwritten sectors. |
| [`tools/Test-PetBasicDap.mjs`](../tools/Test-PetBasicDap.mjs) | A BASIC file on the BASIC thread on BASIC 1, 2 and 4, both 4032 keyboards: stopping on entry, stepping, a GOSUB's frame, variables and the FOR loop, the program as text, and an error. |
| [`tools/Test-PetDap.mjs`](../tools/Test-PetDap.mjs) | The debugger end to end: BASIC 2 from the sources, the screen, a breakpoint in the kernal with its call stack, the reset stop, a program recorded on tape and saved as TAP, loaded back, and a `.prg` and a source launched. With the 4040's ROMs, a blank disk on device 8 formatted, a program saved, the disk saved as D64 and listed, and a second unit added and removed; with the 2040's, a 2040 added and removed. Then a 4032 on BASIC 4 from the sources, a breakpoint in its kernal and the reset stop, and with the 4040's ROMs the drive it comes with, a disk formatted with `HEADER` and listed with `DIRECTORY`. |

The machine, tape, source and image tests and the DAP script need nothing external. The comparisons with the dumps,
with MAME's tapes and with MAME itself, and the drives' tests, which run the 4040's and 2040's ROMs, are inconclusive without
them.

The [MAME 0.264 ROM sets on archive.org](https://archive.org/download/mame-0.264-roms-non-merged/) hold the dumps
under these names, in `pet2001.zip`, `pet2001n.zip`, `pet4016.zip` and `pet4032b.zip`; MAME 0.289 is the oracle.
