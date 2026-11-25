# The Atari 400 and 800

Retrocore's Atari is [`AtariMachine`](../src/Retrocore.Machines.Atari/AtariMachine.cs): a 6502 sharing its bus
with ANTIC, cycle by cycle, with GTIA, POKEY and the PIA, the 400's and 800's memory maps and cartridge slots, the 410
Program Recorder and up to four disk drives on the serial bus. Every ROM it runs is an SDK source, so it runs with
nothing external. This guide covers what it emulates, its ROMs, and how to debug on it.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | `$0000-$BFFF` | 8 to 48 KB in 8 KB steps: 48 KB on the 800 by default, 16 KB on the 400. A cartridge covers the RAM under it. |
| Right cartridge | `$8000-$9FFF` | The 800's second slot, 8 KB. |
| Left cartridge | `$A000-$BFFF` | 8 KB, or 16 KB from `$8000`; Atari BASIC by default. |
| GTIA | `$D000-$D01F` | Players and missiles, colors and priorities, collisions, the console keys and the triggers. |
| POKEY | `$D200-$D20F` | Four sound channels, the timers, the keyboard, the serial port and the paddles. |
| PIA | `$D300-$D303` | The joystick ports, and the serial bus's command and motor lines. |
| ANTIC | `$D400-$D40F` | The display list, DMA, WSYNC, VCOUNT, the light pen and the NMIs. |
| Floating point ROM | `$D800-$DFFF` | The floating point package. |
| OS ROM | `$E000-$FFFF` | The character set and the OS, rev. A, rev. B or the PAL OS. |

**CPU.** The NMOS 6502 runs at 1.79 MHz (NTSC) or 1.77 MHz (PAL). ANTIC takes whole cycles for its display and
memory refresh DMA, and holds the CPU's RDY line from a write to `WSYNC` to the next line's end.

**Video.** ANTIC runs its display list line by line, with every character and map mode, fine scrolling and display
list interrupts; GTIA (or the earlier CTIA) draws the playfield, players and missiles as the beam reaches them. The
frame is 376 by 240, the picture and its overscan.

**Keyboard.** The 400's and 800's keys, with SHIFT, CONTROL and the inverse and Atari keys, START, SELECT and OPTION,
BREAK, and SYSTEM RESET, which is an NMI the OS takes as a warm start.

**Sound.** POKEY's four channels and the console speaker, through the TV.

**Serial bus.** SIO at 19,200 baud, with the command line, motor control and the proceed and interrupt lines.
The 410 Program Recorder plays and records `.cas` tapes at 600 baud. The disk drives are 810s at the hardware level,
each its own 6507, 6532 and FD1771 running the 810's firmware on a 288 rpm disk, or drives that answer SIO commands at
the command level. They read and write `.atr` and `.xfd` images. A binary load file (`.xex`) boots from a disk, or
a tape, built for it.

**Cartridges.** 8K and 16K cartridges, the 800's right cartridge, and the bank-switched kinds a `.car` header names:
Williams, Express, Diamond, OSS, XEGS and Atarimax.

## ROMs

The ROMs are SDK sources, each assembling byte-identically to its chip, with `;;` documentation and IntelliSense:

| Source | Covers |
| --- | --- |
| [`Os.asm`](../src/Retrocore.Machines.Atari/Roms/Os.asm) | The OS, `$E000-$FFFF`: rev. B by default, rev. A and the PAL OS as `VERSION` builds; its character set is [`Os/CharacterSet.asm`](../src/Retrocore.Machines.Atari/Roms/Os/CharacterSet.asm). |
| [`FloatingPoint.asm`](../src/Retrocore.Machines.Atari/Roms/FloatingPoint.asm) | The floating point package, `$D800-$DFFF`. |
| [`AtariBasic.asm`](../src/Retrocore.Machines.Atari/Roms/AtariBasic.asm) | Atari BASIC, `$A000-$BFFF`: rev. C by default, rev. B and rev. A as `VERSION` builds. |
| [`Atari810.asm`](../src/Retrocore.Machines.Atari/Roms/Atari810.asm) | The 810 disk drive's firmware: revision C by default, revision B as a `VERSION` build. |

Without dumps, the debugger and the tests build the ROMs from these sources. With `romDirectory` (or
`RETROCORE_ATARI_ROMS`), they load MAME's `a800` or `a800pal` chips instead (`co12399b.rom`, `co12499b.rom`,
`co14599b.rom`, ...); the 810's firmware from an `atari810` folder beside them; and Atari BASIC as `basic-revc.rom`
(or `-reva`, `-revb`) in the directory or its `basic` folder. A ROM the directory lacks is built from its source.

## Debugging

Launch with `"machine": "atari800"`. The options:

| Option | Values |
| --- | --- |
| `model` | `atari800` (the default) or `atari400`. |
| `video` | `ntsc` (the default) or `pal`, which runs the PAL OS. |
| `os` | `b` (the default) or `a`. |
| `chip` | `gtia` (the default) or `ctia`. |
| `ramKilobytes` | 8 to 48 in 8 KB steps. |
| `basicCartridge` | `c` (the default), `b`, `a` or `none`: Atari BASIC's revision in the left slot. |
| `cartridge`, `rightCartridge` | A cartridge image for the left slot, which then holds no BASIC, or the 800's right slot (an 8 KB `.rom`, or a `.car` of the right-slot type). |
| `diskDrives`, `diskDrive` | 0 to 4 drives, by default as many as `disks` names, or 1 for an `executable`; `atari810` (the default) or `sio`. |
| `disks` | `.atr` and `.xfd` images, or an `.xex`, for D1: to D4:. |
| `executable` | An `.xex`, which boots from drive 1. |
| `cassette` | A `.cas` tape, or an `.xex` on a tape that boots it. |
| `sound` | `speaker` (the default) or `off`. |
| `fastCassette` | Whether the machine runs flat out while the tape moves; on by default. |

A 6502 `source` or `program` loads once the OS and BASIC have run for two seconds, so CIO and the screen are set up:
[`sample/atari/hello.asm`](../sample/atari/hello.asm) prints through CIO.

The OS, the floating point package and the cartridges are memory areas of their own, so `Os.asm`'s, `FloatingPoint.asm`'s
and `AtariBasic.asm`'s breakpoints stop only where their ROM is, and a cartridge's only while it is in its slot. A
dump that isn't one of the sources' builds debugs without them.

**Atari BASIC.** A `basic` file (`.atari.bas`, or a `.bas` whose first line is `REM retrocore atari`) loads into BASIC's
tables and RUNs, on the BASIC thread, as for the other BASICs: breakpoints on lines, stepping by statement, GOSUBs in
the call stack, and the variables, arrays and FOR loops read from the variable value table and the run-time stack.
The dialect tokenizes as the ROM does, by its own syntax tables (see
[`AtariBasicSyntax`](../src/Retrocore.Basic/AtariBasicSyntax.cs)), so the program in memory is byte for byte what typing
it would make, its variables numbered in the order the file names them. LIST's spacing and FASC's numbers are the ROM's.
An error stops at its statement with its number and message, unless TRAP takes it.

**Keys.** The display panel types ATASCII: Backspace is BACK S, Home CLEAR, and the arrows are the cursor keys. Its
buttons hold START, SELECT, OPTION, BREAK and SYSTEM RESET for a tenth of a second. The debugger's reset (Ctrl+F12)
powers the machine off and on.

## Testing

`AtariMachineTests`, `PokeyTests`, `AtariTimingTests`, `AtariDiskTests`, `Atari810Tests`, `AtariTapeTests` and
`AtariCartridgeTests` cover the machine. `AtariOsSourceTests`, `AtariFloatingPointSourceTests`, `AtariBasicSourceTests`
and `Atari810SourceTests` pin each source's builds by digest, compare them with dumps when they are there, lint them,
and run the machine on the SDK's builds alone. `AtariBasicDialectTests` checks the dialect against the ROM running on
the machine. `AtariOracleTests` compares traces with MAME's when `RETROCORE_MAME` names it.

[`tools/Test-AtariDap.mjs`](../tools/Test-AtariDap.mjs) runs the debugger on the SDK's sources with nothing external:
an Atari BASIC file on the BASIC thread, breakpoints in the modules of `AtariBasic.asm` and `Os.asm`, an `.xex`, a disk booted
through the 810, and the 6502 sample.
