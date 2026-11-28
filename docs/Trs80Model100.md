# The TRS-80 Model 100 and Tandy 102

Retrocore's Model 100 is [`Trs80Model100Machine`](../src/Retrocore.Machines.Trs80Model100/Trs80Model100Machine.cs):
an OKI 80C85, the 32 KB ROM with Microsoft BASIC and the built-in TEXT, TELCOM, ADDRSS and SCHEDL, 8 to 32 KB of
RAM, an option ROM socket, the 240x64 LCD, the keyboard, the uPD1990AC clock, and the 81C55 that ties them
together. It runs the ROM you supply, boots to its menu and runs BASIC, keeps its RAM between sessions as the
battery does, saves and loads tapes, and sounds its buzzer. This guide covers what it emulates and how to debug on
it. [The backlog](backlog/Trs80Model100.md) lists the reference documents behind the emulation and what comes next:
the serial port, the printer and the disk drive, and writing an SDK source for the ROM.

## The ROM

The ROM is Microsoft's and Tandy's, so it is not part of Retrocore. A launch finds it as:

- `rom`: the ROM's file, as a path or a name in `romDirectory`;
- otherwise in `romDirectory`, or in the folder named by `RETROCORE_TRS80M100_ROMS`, or in either's `trs80m100`,
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
| 81C55 | Ports `$B0`-`$BF` | [`Pio8155`](../src/Retrocore.Core/Machines/Chips/Pio8155.cs): ports A and B strobe the keyboard and select the LCD drivers; port A also drives the clock; port B turns the power off and drives the buzzer; port C reads the clock. Its timer can drive the buzzer. |
| LCD | Ports `$F0`-`$FF` | Ten HD44102 drivers ([`Lcd44102`](../src/Retrocore.Core/Machines/Chips/Lcd44102.cs)); even ports take instructions and give status, odd ports display data. |
| Keyboard | Ports `$E0`-`$EF` (the ROM reads `$E8`) | The 9x8 matrix ([`Trs80Model100Keyboard`](../src/Retrocore.Machines.Trs80Model100/Trs80Model100Keyboard.cs)). |
| Clock | Port A, port C, `$E0` bit 2 | The uPD1990AC ([`Rtc1990`](../src/Retrocore.Core/Machines/Chips/Rtc1990.cs)); its TP output drives RST 7.5 at 256 Hz. |
| Option ROM | `$0000`-`$7FFF` | Up to 32 KB (`optionRom`); an empty socket reads `$FF`. |

The cassette and the buzzer are connected (see [The cassette](#the-cassette) and [Sound](#sound)). The UART (`$C0`
and `$D0`), the modem (`$A0`), the printer and the bar-code wand are not yet: the UART's status reads its
transmitter empty and the power good, and the printer is never busy.

**The CPU and interrupts.** The clock's TP drives RST 7.5, whose handler at `$003C` scans the keyboard every third
time (about every 11.7 ms), blinks the cursor and counts down to the automatic power-off. TRAP, RST 6.5 and RST 5.5
are not driven yet. SID is the cassette's input, and SOD its output.

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
- `time`: the clock's start, such as `2026-11-26T09:30:00`;
- `files`: host files to put in RAM's directory, so the menu lists them (see [Files](#files));
- `cassette`: a WAV file's tape to put in the recorder (see [The cassette](#the-cassette)); `fastCassette`, true by
  default, runs the machine as fast as it can while the motor moves a tape;
- `sound`: `speaker` (the default) plays the buzzer, `off` doesn't.

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
text. The Machine view lists the ROM, the option ROM, the RAM and its image, the clock's TP, the power and the files
in RAM.

## Files

The Model 100 keeps its files in RAM: the menu lists RAM's directory, 27 entries at `$F962`, each a type, an
address and a six-letter name with its two-letter extension. `.BA` files are tokenized BASIC, `.DO` files text in CR
LF lines ending in `$1A`, and `.CO` files machine code with its start, length and entry. They lie in that order from
the bottom of RAM, so adding, changing or removing one moves those after it. Retrocore writes them as the ROM's own
`SAVE`, `SAVEM` and `OPEN` do, byte for byte.

- **At launch**, `files` lists host files: `.ba`, `.do` and `.co` files as the Model 100 holds them, BASIC text as
  `.bas` (tokenized as Model 100 BASIC; `game.model100.bas` becomes `GAME.BA`), and text as `.txt` (its lines ended
  with CR LF). The ROM runs to its menu, the files go into RAM, each replacing any of the same name in its
  place, and the menu is drawn again with them. With a `ramImage`, they are kept in it when the session ends.

  ```json
  "files": ["${workspaceFolder}/game.model100.bas", "${workspaceFolder}/notes.txt"]
  ```

- **In a RAM image**, the `retrocore` host's `--model100` command lists, copies out, adds and removes them:

  ```text
  retrocore --model100 files m100.ram [--json]
  retrocore --model100 extract m100.ram GAME.BA game.ba [--list]
  retrocore --model100 add m100.ram notes.txt [NAME.DO]
  retrocore --model100 delete m100.ram NOTES.DO
  ```

  `--list` writes a `.BA` file's listing instead of its bytes. A change is written back only when it succeeds. Like
  the ROM's `KILL`, `delete` refuses the program BASIC has open.

## The cassette

The ROM writes a tape through the 8085's SOD and reads one through SID, and port `$E0` bit 3 runs the recorder's
motor through its REM jack. A bit is one cycle: 2400 Hz for a 1 and 1200 Hz for a 0. A block is a leader of `$55`
bytes, a `$7F`, then bytes of eight bits, most significant first, each with a ninth after it. `CSAVE` writes a header
block (`$D3`, the six-character name, the length and a checksum) and a data block (`$8D`, the program and a
checksum).

Retrocore keeps a tape as its level changes, timed in the 80C85's cycles while the motor runs, and reads and writes
WAV files (8 or 16-bit PCM in, 16-bit 44.1 kHz out). The tape moves only while the motor runs. SID reads the tape's
level inverted, as MAME's driver has it, and is high with no tape playing.

- **Playing:** `cassette` in the launch, or **Insert** on the cassette in the **Drives** view, puts a WAV file's tape in.
  It plays from its start once the ROM runs the motor, as `CLOAD` does.
- **Recording:** **Record** in the **Drives** view names the WAV file to write, which is written blank at once. The
  tape takes SOD's changes while the motor runs, as `CSAVE` runs it, and is a changed tape ([Devices.md](Devices.md)):
  **Save** writes it to the file, **Eject** and **Insert** ask about it first, and the recovery journal keeps its
  half cycles across a stop or a crash. The session's end writes the RAM image, not the recording.

Checked by hand against MAME 0.264 (2026-11-27): `CLOAD` read MAME's recording of a `CSAVE`, and MAME's `CLOAD`
read Retrocore's. The tests check Retrocore's own `CSAVE` and `CLOAD` against each other, and the recording's blocks
against the format MAME's showed.

## Sound

The piezo buzzer follows port B bit 5 while bit 2 is set. With bit 2 clear, it follows the 81C55's timer output while
bit 5 is set, and keeps its level while bit 5 is clear, as MAME's driver has it. BASIC's `BEEP` and `SOUND` use the
timer. The display panel plays it while the machine runs at its own speed, as it does for the other machines.

## BASIC

Model 100 BASIC is a dialect of its own, `model100`, with `.model100.bas` source files and `' retrocore model100` as
the pragma. Its tokens are the ROM's table at `$0080`, one byte each from `$80` (`END`) to `$FF` (`'`), and
the tokenizer stores lines as the ROM stores them when they are typed:
- numbers and line numbers stay as digits;
- lowercase becomes uppercase outside strings, `DATA` and remarks;
- `?` is `PRINT`, and `GOTO` may have spaces inside it;
- `ELSE` and an apostrophe remark are stored after a colon.

`.ba` files open as listings with **Retrocore: Open as BASIC Listing**, and `--basic list` lists them; `--basic
tokenize` makes them from text, and renumbering follows `RESTORE`'s line, which the Model 100 takes. Hover help
for its words is still to come.

While BASIC is at its prompt, **Retrocore: Open BASIC Program** edits the program BASIC has open as text: a `.BA`
file after `LOAD`, or its unsaved program. Saving writes it back over that file, moving the files after it; at the
menu, in TEXT or while a program runs, it is refused. Line-by-line BASIC stepping and a `basic` launch are not offered
yet; both depend on symbol addresses from an SDK source of the ROM.

## Testing

- `Model100ChipTests`: the 8155's timer and ports, the HD44102's addressing, dummy read, status and start page, and
  the uPD1990AC's shift register, commands and TP, as their data sheets describe them.
- `Trs80Model100MachineTests`: small 8085 programs in place of the ROM drive the clock's RST 7.5 at 256 Hz, the
  keyboard matrix, the option ROM's switch, the LCD's ports, the RAM sizes and the power-off bit. They need no ROM.
- `Trs80Model100RomTests`: both ROMs boot to the menu with the bytes free MAME 0.264 shows at each RAM size (MAME's
  Tandy 102 offers only 24 and 32 KB, so its 8 and 16 are the Model 100's figures), BASIC runs what is typed, sets the clock and keeps its variables through `POWER OFF,RESUME`, and the menu's LCD dots
  match MAME's screen. They read `m100.bin` and `t102.bin` from `RETROCORE_TRS80M100_ROMS` or the external test
  data's `trs80m100-roms` folder, and are inconclusive without them.
- `Trs80Model100DebugTargetTests`: the launch's messages for a missing ROM, the RAM image across sessions, cold
  starts, a mismatched size and failed saves, the launch's files on the menu, a tape recorded and played through the
  cassette's actions, a recording as a changed tape that an eject holds back until it is saved, and the session's end
  writing the RAM image and not the recording.
- `Model100BasicTests`: the tokenizer against the bytes the ROM stored for typed lines (pinned, so they need no ROM),
  listings, renumbering, and with the ROM, its keyword table, typed lines read back, and a program written into RAM
  that BASIC runs.
- `Model100FilesTests`: files written in the order the ROM saved them lie as the ROM left them (pinned), removing and
  replacing them, programs moved and linked again, bad names and full RAM; and with the ROM, files written at the
  menu matched byte for byte against the ROM's own `SAVE`, `SAVEM` and `OPEN`, then run and read by BASIC.
- `Model100CommandTests`: the `--model100` command on a RAM image, and host files read by kind.
- `Trs80Model100CassetteTests`:
  - tapes through WAV files, the motor, SID's polarity, and the buzzer's two sources, without the ROM;
  - with the ROM, `CSAVE` decoded into MAME's blocks and loaded back with `CLOAD`, and `BEEP`'s sound.
- [`tools/Test-Trs80Model100Dap.mjs`](../tools/Test-Trs80Model100Dap.mjs): a source's breakpoint, call stack, registers
  and output, the menu, BASIC, POWER OFF and Reset, a RAM image resumed in a new session, a launch's files on the menu,
  BASIC's program read and written, a tape `CSAVE`d through the cassette's actions and `CLOAD`ed in a new launch, and
  the Tandy 102, through the debug adapter. Without the ROM it checks the
  missing-ROM messages and reports the rest skipped.
