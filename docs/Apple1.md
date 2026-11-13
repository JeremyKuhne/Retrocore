# The Apple-1

Retrocore's Apple-1 is [`Apple1Machine`](../src/Retrocore.Machines.Apple1/Apple1Machine.cs): a cycle-exact 6502
with the Apple-1's memory map, its 6821 PIA, the video terminal and keyboard behind it, and optionally the Apple
Cassette Interface. This guide covers what it emulates, its ROMs and their sources, and how to debug on it.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | $0000-$0FFF, or $0000-$1FFF | 4K as shipped, or 8K (`RamKilobytes`). |
| RAM | $E000-$EFFF | The 4K bank where BASIC loads and runs (`HighRam`, on by default). |
| Cassette interface | $C000-$C1FF | The ACI: its tape flip-flop and input at $C000-$C0FF, its PROM at $C100 (`CassetteInterface`, on by default). |
| PIA | $D010-$D013 | KBD, KBDCR, DSP and DSPCR, repeated through $D000-$DFFF wherever address bit 4 is set. |
| Monitor | $FF00-$FFFF | The Monitor's two 256x4 PROMs, which see only the low byte of the address, so they fill $F000-$FFFF. |

Every other address reads its own high byte, the last byte most instructions that reach it fetched.

**CPU.** The NMOS 6502 runs at 1.0227 MHz (1,022,727 Hz), the 14.31818 MHz crystal divided by fourteen. The
clock stretching the board uses to refresh its dynamic RAM is not emulated.

**PIA.** The 6821 has both ports, their direction and control registers, the C1 flags and edges, and C2 as an
output in its handshake, pulse and manual modes. Its interrupt outputs are not connected, as on the board. RESET
resets the PIA with the 6502.

**Keyboard.** Port A reads the key, with PA7 held high, so every key has bit 7 set; the keyboard strobes CA1. The
keyboard has no lowercase, so typing a lowercase letter types its capital. Typed characters wait in a queue, and
each is strobed once the program has read the last and a millisecond has passed.

**Terminal.** The terminal is not memory the 6502 can see: it keeps 24 lines of 40 characters in shift registers
and takes characters one at a time from port B. A write to DSP takes CB2 low, which the terminal latches and shows
on PB7 (busy). It can only write at the cursor, once a frame as the beam passes the cursor's cell, so it takes the
character then and pulses CB1, which ends the handshake. A character therefore waits up to a frame (about 16.7
ms), and output runs at about 60 characters a second.

The terminal stores six bits a character, the address of a character in its Signetics 2513: ASCII bits 0-4 with
bit 6 inverted above them. So lowercase shows as uppercase, and a character is written only when bit 5 or 6 is
set, which drops the control characters. Return blanks the rest of the line, so a Return at the start of a line
leaves a blank one; that is why the Monitor's output has a blank line before each address it shows. A line wraps
at 40 characters, and the line after the last scrolls the screen up. The cursor is the 2513's `@` blinking with a
space; here it changes every 16 frames. `ClearScreen` is the keyboard's CLEAR SCREEN switch.

**Cassette.** The ACI times the half cycles of the tape's square wave in software, so a tape
([`Apple1Tape`](../src/Retrocore.Machines.Apple1/Apple1Tape.cs)) is the length of each half cycle in 6502
cycles. Tapes come from and go to WAV files (8 or 16-bit PCM, the first channel; written as a 16-bit square
wave), and `Apple1Tape.FromData` makes the recording the ACI's W command would make of some bytes. The interface
has no motor control: a tape plays from the moment it is loaded, and records each change of the output while it
is loaded to record.

To load a tape, start the ACI from the Monitor with `C100R`, then give the range at its `*` prompt:

```text
\
C100R

C100: A9*
E000.EFFFR
```

`E000.EFFFW` writes that range instead, after a leader of about ten seconds. Several commands can share a line,
and Return goes back to the Monitor.

## Apple-1 BASIC

Steve Wozniak's BASIC for the Apple-1 came on cassette and runs in the 4K bank at $E000: `E000.EFFFR` at the
cassette interface's prompt loads it, `E000R` starts it with an empty program, and `E2B3R` starts it again keeping
the program. It is the first form of the Apple II's Integer BASIC, which kept its layout and code:

- 16-bit integers, -32767 to 32767, and strings with `DIM`, `LEN(` and substrings such as `A$(2,3)`;
- a name is a letter and an optional digit (`A`, `B7`), or a letter and `$` for a string;
- the statements `LET` (or none), `PRINT`, `INPUT`, `IF ... THEN`, `GOTO`, `GOSUB`/`RETURN`, `FOR`/`NEXT`, `DIM`,
  `REM`, `END`, `POKE`, `CALL` and `TAB`, and the functions `PEEK`, `RND`, `SGN` and `ABS`; GOSUBs and FOR loops
  nest 8 deep;
- the commands `LIST`, `RUN`, `DEL`, `SCR` (Integer BASIC's `NEW`), `CLR`, `AUTO`, `HIMEM=` and `LOMEM=`;
  Control-D ends `AUTO`;
- several statements to a line only in a numbered line, separated by colons;
- any key typed while a program runs stops it, `STOPPED AT` its line.

Its tokenizer checks a line's syntax as it is typed, so a stored program never has a syntax error. The cold start
puts LOMEM at $0800 and HIMEM at $1000, for a 4K machine; `HIMEM=8192` gives an 8K machine its upper 4K, moving the
program up with it.

Some keywords are left from a version that was still growing. `COLOR=`, `PLOT` and `HLIN` are accepted, but the
Apple-1 has no graphics: `COLOR=` does nothing, and `PLOT` and `HLIN` run other statements' routines. The operands
`COLOR`, `HIMEM` and `LOMEM`, the command `OFF` and `USR(` have no working routine; using them runs into other
code.

## ROMs

[`Apple1Roms`](../src/Retrocore.Machines.Apple1/Apple1Roms.cs) takes the 256-byte Monitor, the 512-byte character
generator and, for the cassette interface, its 256-byte PROM. No Apple ROM data is bundled with the library; the
tests and the SDK assemble them, and Apple-1 BASIC, from the sources below.

## The ROM sources

The sources are in [`src/Retrocore.Machines.Apple1/Roms`](../src/Retrocore.Machines.Apple1/Roms), in the native
dialect, and maintained by hand. [`Apple1RomTests`](../tests/Retrocore.Tests/Apple1RomTests.cs) pins each build by
SHA-256; with dumps in `RETROCORE_APPLE1_ROMS` (default `<cache>\apple1-roms`), named `wozmon.bin`, `aci.bin`
and `basic.bin`, it also compares them byte for byte.

- [`WozMonitor.asm`](../src/Retrocore.Machines.Apple1/Roms/WozMonitor.asm) is Steve Wozniak's Monitor, with the
  names from his listing in the Apple-1 Operation Manual: `RESET`, `GETLINE`, `NEXTITEM`, `NEXTHEX`, `XAMNEXT`,
  `PRBYTE`, `PRHEX` and `ECHO`.
- [`Aci.asm`](../src/Retrocore.Machines.Apple1/Roms/Aci.asm) is the Apple Cassette Interface's PROM.
- [`CharacterGenerator.asm`](../src/Retrocore.Machines.Apple1/Roms/CharacterGenerator.asm) is the terminal's
  Signetics 2513, drawn as a `GLYPH` and seven `ROW`s of five dots each. The 2513 is a five-bit mask ROM and no dump
  is published, so the source keeps its own layout: eight bytes a character, bit 4 the leftmost dot. The first Apple
  II boards used the same chip, and the test checks every glyph against the II board's character generator.

- [`Basic/Basic.asm`](../src/Retrocore.Machines.Apple1/Roms/Basic/Basic.asm) is Apple-1 BASIC, in twelve modules
  that follow the Apple II's [Integer BASIC source](../src/Retrocore.Machines.Apple2/Roms/IntegerBasic) and its
  names wherever the two share code; Apple-1 BASIC's own routines (its line input, `COUT`, the variable lookup,
  `HIMEM=`) are named for what they do. Several versions of the BASIC tape were passed around; this one writes the
  display at $D0F2, and the copies most replicas use write $D012, the same register.

`Apple1SdkModules` in the debugger assembles them all. [`Apple1BasicTests`](../tests/Retrocore.Tests/Apple1BasicTests.cs)
runs BASIC on the machine: loading it from a WAV tape through the cassette interface, programs, `LIST`, errors and
a key that stops a program. It also checks the editor's Apple-1 BASIC dialect against the tokens BASIC stores and
the text its `LIST` prints.

## Debugging

The VS Code extension lists the Apple-1 in the Run and Debug dropdown and in **Retrocore: Start Machine…**; a
launch configuration names it with `"machine": "apple1"`. Its options are:

| Option | Default | |
| --- | --- | --- |
| `ramKilobytes` | 4 | RAM from $0000: 4 or 8. |
| `highRam` | true | The 4K bank at $E000. |
| `cassetteInterface` | true | The Apple Cassette Interface. |
| `cassette` | | A `.wav` tape, which plays from the start of the session. |
| `fastCassette` | true | Run unthrottled while a tape plays or records. |
| `screen` | `green` | The monitor: `green`, `white` (black and white) or `amber`. The display panel's **Screen** changes it. |
| `loadBasic` | true | Apple-1 BASIC in the $E000 bank at power-on, as if its tape had been loaded; `E000R` starts it. Needs `highRam`. |
| `basic` | | An Apple-1 BASIC file (`.apple1.bas`, or `REM retrocore apple1` on its first line) to load and run. |
| `romDirectory` | `RETROCORE_APPLE1_ROMS` | Dumps to use in place of the SDK's builds: `wozmon.bin`, `aci.bin` and `basic.bin`. |
| `bootSeconds` | 0.05 with a program | How long the Monitor runs before a program loads, setting up the PIA. |

`WozMonitor.asm` and `Aci.asm` debug as ROM modules, so a breakpoint on `ECHO` stops as each character goes to
the terminal, and stepping into a call from a program goes into the Monitor's source. A program (`source` or
`program`) loads at $0300 unless the launch says otherwise, and can print through `ECHO` ($FFEF) and go back to
the Monitor with `JMP GETLINE` ($FF1F). The exception filters are **Machine reset** (at power-on, and at each
RESET after) and **BRK instructions**.

The display panel takes keys: **Backspace** types the back arrow (`_`), which the Monitor takes as a backspace,
**Escape** types ESC, and **Ctrl+F12** or **Ctrl+Break** presses RESET. The key bar has **Esc**, **Reset** and
**Clear Screen** (the debug host's `apple1/clearScreen` request). The cassette's row in Retro Devices inserts a
WAV tape, records one (saved when it is ejected) and ejects it, as the `retro/media` request does.
[`Test-Apple1Dap.mjs`](../tools/Test-Apple1Dap.mjs) runs the debugger through all of this.

**Debugging Apple-1 BASIC.** A `basic` launch starts BASIC, puts the file's program in, and types `RUN`. The
**BASIC** thread then debugs it by statement, as for the other BASICs:
- breakpoints and stepping in the file's own lines;
- a GOSUB's caller below it in the call stack;
- the variables and FOR loops, and watches in BASIC's arithmetic;
- Set Next Statement;
- the program in memory, read and written as text.

`Basic.asm`'s modules debug as source in the $E000 bank while BASIC is there. The exception filters add **BASIC
errors** and **Program stops**: a key typed while the program runs stops it as `A key in` its line.
[`Test-Apple1BasicDap.mjs`](../tools/Test-Apple1BasicDap.mjs) runs the debugger through these.

**Not emulated yet:** the RAM refresh's clock stretching.
