# The Kaypro II

Retrocore's Kaypro II is [`KayproMachine`](../src/Retrocore.Machines.Kaypro/KayproMachine.cs): Non-Linear
Systems' 1982 luggable, a 2.5 MHz Z80 with 64K of RAM, an 80-by-24 green screen, a serial keyboard and two
single-sided double-density drives, running CP/M 2.2. Its monitor ROM and character generator are SDK sources, so it
needs nothing external to run; CP/M and its programs come from disk images you supply. This guide covers what it
emulates and how to debug on it, MBASIC included. [The backlog](backlog/Kaypro.md) has what comes next.

## The machine

| Part | Addresses or ports | Emulated |
| --- | --- | --- |
| Monitor ROM | `$0000`-`$07FF`, while banked in | 81-149C, from [`Kaypro2.asm`](../src/Retrocore.Machines.Kaypro/Roms/Kaypro2.asm). `$0800`-`$2FFF` reads zero then; writes there are lost. |
| Video RAM | `$3000`-`$3FFF`, while banked in | 24 lines of 80 characters, each line 128 bytes apart. |
| RAM | `$0000`-`$FFFF` | 64K. The ROM and video RAM bank over its first 16K while the system port's bit 7 is set. |
| Baud rate generators | Ports `$00` (serial), `$0C` (keyboard) | The rates are kept; the serial lines run as fast as the program reads them. |
| Z80 SIO | Ports `$04`-`$07` | Channel A the RS-232 port (what it sends is captured), channel B the keyboard. Data at `$04`/`$05`, control at `$06`/`$07`. |
| General-purpose PIO | Ports `$08`-`$0B` | Port A the Centronics printer's data. |
| FD1793 | Ports `$10`-`$13` | Status and command, track, sector and data. |
| System PIO | Ports `$1C`-`$1F` | Port A the system port. |

Each device answers in its group of four ports; every other port reads `$FF` and ignores writes.

**System port.** Bit 7 set banks the ROM and video RAM in, bit 6 set turns the drive motors off, bit 5 set selects
single density, bit 4 strobes the printer, bit 3 reads set while the printer is ready, and bits 1 and 0 select drives
B and A. The system PIO drives the bits once the ROM sets it to bit control mode; at reset the port reads `$80`, the
ROM banked in.

**Disks.** The FD1793 is the shared Western Digital controller
([`WesternDigitalFloppyDiskController`](../src/Retrocore.Machines.Chips/WesternDigitalFloppyDiskController.cs)) at 5¼-inch
timing. Its interrupt and data requests reach the Z80's NMI only while the Z80 is halted, which is how
the ROM moves each byte: `HALT`, then `INI` or `OUTI` when the NMI wakes it. The NMI vector, `$0066`, is a `RET` in
the ROM, and the ROM puts one in RAM there before it banks the ROM out to transfer. A disk is 40 tracks of ten
512-byte sectors numbered 0-9: a raw image is 204,800 bytes (`.img` or `.dsk`); IMD and DMK images hold single
density too. A Kaypro 4's double-sided images (409,600 bytes, side 1's sectors numbered 10-19) read as well. Disks
save back as raw images, IMD or DMK, an IMD or DMK image in its own layout.

**Screen.** Each character cell is 7 dots wide and 10 scanlines high, the character generator giving the middle
five dots of its top eight. The display inverts a code's bit 7 before it addresses the character generator, whose
first half is blank, so a code with bit 7 set blinks: that is the ROM's cursor. Codes `$00`-`$1F` are the Greek
letters that ESC G shows for lowercase letters.

**Keyboard.** A serial device on the SIO's channel B. Typed codes go to the SIO one at a time, each a little after
the program reads the last, so typing ahead and pasting lose nothing. The cursor keys send `$F1`-`$F4` (up, down,
left, right), which the ROM's `KEYBOARD_IN` translates to `$80`-`$83`. A `$04` the program sends the keyboard sounds
its bell.

## The SDK's sources

| Source | Covers |
| --- | --- |
| [`Kaypro2.asm`](../src/Retrocore.Machines.Kaypro/Roms/Kaypro2.asm) | The 81-149C monitor ROM: its CP/M-style entry points, the SIO and PIO set-up, the boot, the disk routines (blocking and deblocking with Digital Research's Appendix G algorithm and names), the transfer routines it copies to `$FECD`, the keyboard, serial and printer drivers and the screen driver with its escape sequences. |
| [`Kaypro2CharacterGenerator.asm`](../src/Retrocore.Machines.Kaypro/Roms/Kaypro2CharacterGenerator.asm) | The 81-146A character generator, a glyph a row of dots at a time. |
| [`Mbasic/Mbasic.asm`](../src/Retrocore.Machines.Kaypro/Roms/Mbasic/Mbasic.asm) | MBASIC 5.21 for CP/M, `$0100`-`$5FFF`, assembling to a program compatible byte for byte with MBASIC.COM. The root includes 19 modules in address order, following the modules of [GW-BASIC's MIT-licensed source](https://github.com/microsoft/GW-BASIC): the tables and variables, the interpreter, statements, evaluator, LIST, the math package, PTRGET, the console and PRINT USING, strings, the line editor, the disk files and the CP/M file layer, and start-up. Its names are Microsoft's, from GW-BASIC's source and Level2.asm, and every routine is documented; [its naming log](conversions/Mbasic.md) says which names are the SDK's own and which Microsoft names are in doubt. |

`KayproTests` pin each source by SHA-256, so the tests need no dumps, and compare them byte for byte with the dumps
in `RETROCORE_KAYPRO` (`81-149c.rom`, `81-146a.bin`, and MBASIC.COM on `MBasic.img`) when they are there.

## Launching

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Kaypro II: MBASIC",
    "machine": "kaypro2",
    "disks": ["${env:USERPROFILE}/Retrocore/kaypro/cpm22-rom149.img", "${env:USERPROFILE}/Retrocore/kaypro/MBasic.img"],
    "command": "B:MBASIC",
    "basic": "${workspaceFolder}/squares.mbasic.bas"
}
```

| Option | Does |
| --- | --- |
| `disks` | Images for drives A and B. Drive A needs a Kaypro II CP/M system disk to boot. |
| `command` | A CP/M command typed at the first prompt, such as `B:MBASIC`; `MBASIC` when the launch has `basic`. |
| `basic` | An MBASIC program, `.mbasic.bas`: once MBASIC is at its prompt the program goes into memory, and RUN starts it. |
| `romDirectory` | Chip dumps to run in place of the SDK's builds (or `RETROCORE_KAYPRO_ROMS`): `81-149c.u47` or `81-149c.rom`, and `81-146.u43` or `81-146a.bin`, in it or in its `kayproii` folder. `rom` names another monitor dump. |
| `bootSeconds` | Machine time to run the ROM before the debugger takes over (0 by default). |
| `fastDisk` | Runs unthrottled while the disk controller is busy (true by default). |

## Debugging

The CPU thread steps through the monitor ROM in `Kaypro2.asm`, including the transfer routines where the ROM copies
them, and through MBASIC in its modules under `Mbasic/`: each statement applies wherever memory holds the bytes it assembled to.
Function breakpoints take the sources' names, such as `READ`, the ROM's disk read that CP/M's BIOS calls. Retrocore
Memory has banks for the RAM under the ROM, the ROM and video RAM, so they can be read and written whichever is
banked in.

While MBASIC is in memory, a **BASIC** thread runs beside the CPU's, as on the TRS-80 and the Apple II: breakpoints
and steps by statement, the GOSUB call stack, variables (names up to 40 characters, integer, single, double and
string) and arrays, FOR loops, BASIC expression watches, and stops at RUN, errors (with MBASIC's messages; ON ERROR
GOTO's handled errors on their own filter), STOP, END, the end of the program and Ctrl-C. BASIC's memory is read
from RAM even while the BIOS has the ROM banked in.

## MBASIC files

`.mbasic.bas` files are MBASIC source. The dialect's CRUNCH and LIST are MBASIC's own: reserved words must be set
apart from names, numbers are stored in binary (line numbers, integers, singles and doubles in Microsoft's format,
`&H` and `&O` constants), `ELSE` is stored as `:ELSE`, an apostrophe as `:REM'`, and `WHILE` with a plus after it.
`MbasicOracleTests` check them against MBASIC itself on the emulated Kaypro, for lines typed at it and for the
programs on its disk. A double-precision constant that needs scaling by powers of ten can differ from MBASIC's in its
last bits, as BASIC-80's double-precision division rounds in its own way.
