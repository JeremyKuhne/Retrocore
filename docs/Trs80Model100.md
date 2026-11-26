# The TRS-80 Model 100 and Tandy 102

Retrocore's Model 100 is [`Trs80Model100Machine`](../src/Retrocore.Machines.Trs80Model100/Trs80Model100Machine.cs):
an OKI 80C85, the 32 KB ROM with Microsoft BASIC and the built-in TEXT, TELCOM, ADDRSS and SCHEDL, 8 to 32 KB of
RAM, an option ROM socket, the 240x64 LCD, the keyboard, the uPD1990AC clock, and the 81C55 that ties them
together. It runs the ROM you supply, boots to its menu and runs BASIC, and keeps its RAM between sessions as the
battery does. This guide covers what it emulates and how to debug on it. [The backlog](backlog/Trs80Model100.md) has
the sources behind it and what comes next: files, the cassette, the serial port and the disk drive, and the ROM as
an SDK source.

## The ROM

The ROM is Microsoft's and Tandy's, so it is not part of Retrocore. A launch finds it as:

- `rom`: the ROM's file, as a path or a name in `romDirectory`;
- otherwise in `romDirectory`, or in the folder `RETROCORE_TRS80M100_ROMS` names, or in either's `trs80m100`,
  `tandy102` or `trs80m100-roms` folder, under MAME's names, `m100rom.m12` for the Model 100 and `m102rom.m12` for
  the Tandy 102, or as `m100.bin` (`m100rom.bin`) and `t102.bin` (`t102_rom.bin`, `m102rom.bin`).

`model` picks which: `100` (the default) or `102`. The dumps known here are the US Model 100's (CRC32 `730a3611`)
and the US Tandy 102's (`08e9f89c`), as MAME has them; other 32 KB ROMs, such as the regional and Y2K-patched ones,
run as well.

## The machine

| Part | Addresses or ports | Emulated |
| --- | --- | --- |
| CPU | | The 80C85 at 2.4576 MHz, state for state ([`Retrocore.Cpu.I8080`](../src/Retrocore.Cpu.I8080)). |
| ROM | `$0000`-`$7FFF` | The main ROM, or the option ROM while port `$E0` bit 0 is set. |
| RAM | `$8000`-`$FFFF` | 8, 16, 24 or 32 KB (`ramKilobytes`, 32 by default), filled down from `$FFFF`. Addresses below it read `$FF` and lose writes. |
| 81C55 | Ports `$B0`-`$BF` | [`Pio8155`](../src/Retrocore.Core/Machines/Chips/Pio8155.cs): ports A and B strobe the keyboard and select the LCD drivers; port A also drives the clock; port B turns the power off; port C reads the clock. Its timer runs but drives nothing yet. |
| LCD | Ports `$F0`-`$FF` | Ten HD44102 drivers ([`Lcd44102`](../src/Retrocore.Core/Machines/Chips/Lcd44102.cs)); even ports take instructions and give status, odd ports display data. |
| Keyboard | Ports `$E0`-`$EF` (the ROM reads `$E8`) | The 9x8 matrix ([`Trs80Model100Keyboard`](../src/Retrocore.Machines.Trs80Model100/Trs80Model100Keyboard.cs)). |
| Clock | Port A, port C, `$E0` bit 2 | The uPD1990AC ([`Rtc1990`](../src/Retrocore.Core/Machines/Chips/Rtc1990.cs)); its TP output drives RST 7.5 at 256 Hz. |
| Option ROM | `$0000`-`$7FFF` | Up to 32 KB (`optionRom`); an empty socket reads `$FF`. |

The UART (`$C0` and `$D0`), the modem (`$A0`), the cassette, the beeper, the printer and the bar-code wand are not
connected yet: the UART's status reads its transmitter empty and the power good, and the printer is never busy.

**The CPU and interrupts.** The clock's TP drives RST 7.5, whose handler at `$003C` scans the keyboard every third
time (about every 11.7 ms), blinks the cursor and counts down to the automatic power-off. TRAP, RST 6.5 and RST 5.5
are not driven yet. SID, the cassette's input, reads high.

**The LCD.** Ten HD44102 column drivers, five across the top half of the panel and five across the bottom. Each holds
four pages of 50 columns of 8 dots, bit 0 the top dot; the rightmost two show 40 of their columns. Port A's bits
select drivers 0-7 and port B's bits 0 and 1 drivers 8 and 9, and several can be selected at once. An instruction
byte sets the page (bits 6-7) and column (bits 0-5), turns the display on or off, picks counting up or down, or sets
the start page; each data byte moves on a column. The first read after setting an address is a dummy, as on the
chip. The ROM keeps a copy of the screen's 40x8 characters at `$FE00`-`$FF3F`, which the debugger shows as the text.

**The keyboard.** A key pulls its row low in a read of port `$E0`-`$EF` (the ROM reads `$E8`) while its column is strobed low; column 8, from port B
bit 0, holds SHIFT, CTRL, GRPH, CODE, NUM, CAPS LOCK and PAUSE/BREAK. Typed keys are held for 50 ms and released for
50 ms, since the ROM takes a key once it has seen it on two scans in a row. For its first second or so after a cold
start the ROM ignores the keyboard, though its menu shows sooner.

**The clock.** The uPD1990AC counts seconds to month and the day of the week; the year is the ROM's, in RAM. A
command on C0-C2 is taken when STB rises; the register commands and the TP commands are held apart, as NEC's data
sheet has it. A cold start sets it to January 1 (the menu shows "Jan 01,1900"); `time` starts the chip at a time of
your choosing (the host's by default) when the machine is built, which a cold start then clears but a warm start
from a RAM image shows.

**Power.** Software turns the power off with port B bit 4 (BASIC's `POWER OFF`, or the automatic power-off): the CPU
stops, the panel goes blank, and RAM and the clock go on. The debugger's Reset does what the power switch and the
RESET button both do: the CPU starts at `$0000` with the devices reset, the ROM finds RAM valid, and it comes back
to the menu, or to where it was after `POWER OFF,RESUME`.

## Debugging

`"machine": "trs80-model100"` debugs a Model 100 or Tandy 102 with the same source debugging, cycle counts, memory
view and breakpoints as the other machines:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Model 100",
    "machine": "trs80-model100",
    "romDirectory": "${userHome}/Retrocore/trs80m100-roms",
    "ramImage": "${workspaceFolder}/m100.ram"
}
```

- `model`: `100` or `102`;
- `rom`, `romDirectory`: the ROM, as above;
- `ramKilobytes`: 8, 16, 24 or 32;
- `optionRom`: an option ROM's file;
- `ramImage`: a file that keeps the RAM between sessions, as the battery does. When it exists, it is loaded before
  the power comes on, and the ROM carries on where it was; when it does not, the machine starts cold. The RAM is
  saved to it as the session ends or another launch replaces the machine, through a file beside it, so a save that
  fails leaves the old image and can be tried again. The CPU's state is not kept, as it is not when the power goes;
- `coldStart`: start from empty RAM even when `ramImage` exists;
- `time`: the clock's start, such as `2026-11-26T09:30:00`.

A `source` or `program` loads at `$E000` by default, once the ROM has had 3 seconds to set up its RAM
(`bootSeconds`), and can call the ROM: `RST 4` writes the character in A to the screen. The call stack follows
`CALL`, `RST`, and the 8085's TRAP and RST 5.5, 6.5 and 7.5, which push the program counter with no opcode fetch,
so a breakpoint in a program shows the RST 7.5 handler's interruptions above it. The registers are the 8085's, with
its flags by name.

**Keys.** Typed keys are ASCII, with Ctrl and a letter for CTRL; the arrows are the codes the ROM gives them (28-31),
and Pause is PAUSE; 8, 9 and 13 (Ctrl+H, I and M) are DEL, TAB and ENTER. The display panel's buttons are F1-F8,
LABEL, PRINT, PASTE, PAUSE and BREAK (PAUSE/BREAK with SHIFT), since VS Code keeps its F keys; the Desktop takes
F1-F8 from the keyboard.

**The display** is the LCD, a pixel to a dot, in its dark dots on a gray-green ground, and the ROM's screen copy as
text. The Machine view lists the ROM, the option ROM, the RAM and its image, the clock's TP and the power.

## Testing

- `Model100ChipTests`: the 8155's timer and ports, the HD44102's addressing, dummy read, status and start page, and
  the uPD1990AC's shift register, commands and TP, as their data sheets describe them.
- `Trs80Model100MachineTests`: small 8085 programs in place of the ROM drive the clock's RST 7.5 at 256 Hz, the
  keyboard matrix, the option ROM's switch, the LCD's ports, the RAM sizes and the power-off bit. They need no ROM.
- `Trs80Model100RomTests`: both ROMs boot to the menu with the bytes free MAME 0.264 shows at each RAM size (MAME's
  Tandy 102 offers only 24 and 32 KB, so its 8 and 16 are the Model 100's figures), BASIC runs what is typed, sets the clock and keeps its variables through `POWER OFF,RESUME`, and the menu's LCD dots
  match MAME's screen. They read `m100.bin` and `t102.bin` from `RETROCORE_TRS80M100_ROMS` or the external test
  data's `trs80m100-roms` folder, and are inconclusive without them.
- `Trs80Model100DebugTargetTests`: the launch's messages for a missing ROM, and the RAM image across sessions, cold
  starts, a mismatched size and failed saves.
- [`tools/Test-Trs80Model100Dap.mjs`](../tools/Test-Trs80Model100Dap.mjs): a source's breakpoint, call stack,
  registers and output, the menu, BASIC, POWER OFF and Reset, a RAM image resumed in a new session, and the Tandy
  102, through the debug adapter. Without the ROM it checks the missing-ROM messages and reports the rest skipped.
