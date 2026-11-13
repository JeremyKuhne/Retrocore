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

## ROMs

[`Apple1Roms`](../src/Retrocore.Machines.Apple1/Apple1Roms.cs) takes the 256-byte Monitor, the 512-byte character
generator and, for the cassette interface, its 256-byte PROM. No Apple ROM data is bundled with the library; the
tests and the SDK assemble them from the sources below.

## The ROM sources

The sources are in [`src/Retrocore.Machines.Apple1/Roms`](../src/Retrocore.Machines.Apple1/Roms), in the native
dialect, and maintained by hand. [`Apple1RomTests`](../tests/Retrocore.Tests/Apple1RomTests.cs) pins each build by
SHA-256; with dumps in `RETROCORE_APPLE1_ROMS` (default `<cache>\apple1-roms`), named `wozmon.bin` and `aci.bin`,
it also compares them byte for byte.

- [`WozMonitor.asm`](../src/Retrocore.Machines.Apple1/Roms/WozMonitor.asm) is Steve Wozniak's Monitor, with the
  names from his listing in the Apple-1 Operation Manual: `RESET`, `GETLINE`, `NEXTITEM`, `NEXTHEX`, `XAMNEXT`,
  `PRBYTE`, `PRHEX` and `ECHO`.
- [`Aci.asm`](../src/Retrocore.Machines.Apple1/Roms/Aci.asm) is the Apple Cassette Interface's PROM.
- [`CharacterGenerator.asm`](../src/Retrocore.Machines.Apple1/Roms/CharacterGenerator.asm) is the terminal's
  Signetics 2513, drawn as a `GLYPH` and seven `ROW`s of five dots each. The 2513 is a five-bit mask ROM and no dump
  is published, so the source keeps its own layout: eight bytes a character, bit 4 the leftmost dot. The first Apple
  II boards used the same chip, and the test checks every glyph against the II board's character generator.

`Apple1SdkModules` in the debugger assembles all three.

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
| `romDirectory` | `RETROCORE_APPLE1_ROMS` | Dumps to use in place of the SDK's builds: `wozmon.bin` and `aci.bin`. |
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

**Not emulated yet:**

- Apple-1 BASIC, which loads from tape to $E000;
- the RAM refresh's clock stretching.
