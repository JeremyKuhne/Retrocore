# The BBC Micro

Retrocore's BBC Micro is [`BbcMachine`](../src/Retrocore.Machines.Acorn/BbcMachine.cs): a cycle-exact NMOS 6502 at 2
MHz with the Model B's or Model A's memory map, video in all eight modes, keyboard, sound, analogue port, cassette and,
on the Model B, the Intel 8271 disk interface. This guide covers what it emulates, its ROMs, and how to debug on it.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | `&0000-&7FFF` | 32 KB on the Model B; the Model A's 16 KB answers twice. |
| Paged ROM | `&8000-&BFFF` | The ROM in the socket ROMSEL selects: four sockets, ROMs 0-3, repeated through ROMs 4-15. BASIC II is in socket 3 and DNFS 1.20 in socket 0. |
| MOS | `&C000-&FBFF`, `&FF00-&FFFF` | MOS 1.20. |
| FRED and JIM | `&FC00-&FDFF` | The 1 MHz bus's pages, with nothing fitted. |
| SHEILA | `&FE00-&FEFF` | The 6845 CRTC, the 6850 ACIA, the serial ULA, the station number, the video ULA, ROMSEL, the system and user VIAs, the 8271, the ADC; the Econet ADLC and the Tube read as absent. |

**CPU.** The 6502 runs at 2 MHz, and an access to the 1 MHz bus or most of SHEILA stretches its cycle by one or two
2 MHz cycles, by phase, as the board does. Every instruction matches MAME's `bbcb` from power-on to BASIC's prompt
and through a DFS catalogue, outside interrupts.

**Video.** The 6845 makes the timing and addresses, and the video ULA the pixels and palette, in modes 0-6, with
flashing colours, the cursor and the hardware's screen wrap for scrolling. Mode 7 is the SAA5050: colour and graphics
codes, separated and held graphics, double height, flashing and the character rounding. The frame is 704x576 with
its border, interlaced fields on alternate rows.

**Keyboard.** The 10 x 8 matrix through the slow data bus, with CAPS LOCK and SHIFT LOCK, the startup links (mode 7
and the DFS by default) and BREAK, which resets the CPU and the user VIA only, so the MOS can tell it from power-on.

**Sound.** The SN76489's three tones and noise, in stereo at 48 kHz.

**Tape.** The serial ULA and the 6850 at 1200 and 300 baud, with the motor relay. `.uef` tapes play at the tone
level through the MOS's own cassette filing system, and record; a file with an `.inf` file beside it goes on a tape
as the MOS would save it.

**Disks.** The 8271 at the level of commands and data bytes, with its timing and NMI-driven transfers, and two
drives of 40 or 80 tracks. `.ssd` images are one side; a `.dsd` image's second side is drive 2 or 3. Changed disks
and tapes save back to their images, or to another, from the Drives view.

## ROMs

Every ROM the machine runs is an SDK source, maintained by hand and byte-identical to the ROM:

| Source | ROM |
| --- | --- |
| [`Mos.asm`](../src/Retrocore.Machines.Acorn/Roms/Mos.asm) | MOS 1.20, with its workspace in `MosEquates.asm`. |
| [`BbcBasic.asm`](../src/Retrocore.Machines.Acorn/Roms/BbcBasic.asm) | BBC BASIC II, with its workspace and tokens in `BasicEquates.asm`. |
| [`Dnfs.asm`](../src/Retrocore.Machines.Acorn/Roms/Dnfs.asm) | DNFS 1.20: the Acorn DFS and the Econet filing system, with their workspace in `DnfsEquates.asm`. |
| [`Saa5050.asm`](../src/Retrocore.Machines.Acorn/Roms/Saa5050.asm) | The SAA5050's 96 characters, drawn as rows of dots. |

The paged ROMs name the MOS calls they make through `MosEntries.asm`, whose entries inherit the MOS's documentation.

Nothing external is needed: without dumps, the ROMs are built from the sources, and debugging steps into them. Dumps
can still take their place, from a directory of dumps under MAME's names: `romDirectory`, or `RETROCORE_BBC_ROMS`,
in the directory itself or its `bbcb`, `bbc_acorn8271` and `saa5050` folders. A ROM the directory lacks is built
from its source. A blank `romDirectory`, as `${env:RETROCORE_BBC_ROMS}` gives when the variable is not set, names no
dumps.

| ROM | File |
| --- | --- |
| MOS 1.20 | `os12.rom` |
| BASIC II | `basic2.rom` |
| DNFS 1.20 | `dnfs120.rom` |
| SAA5050 | `saa5050` |

## Debugging

The Model B and Model A are in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts them with a
program, a BASIC file, a tape or a disk. Launch configurations take `"machine": "bbc"` and a `model`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "BBC Micro: 6502 sample",
    "machine": "bbc",
    "model": "bbcb",
    "source": "${workspaceFolder}/sample/bbc/hello.asm",
    "stopOnEntry": true
}
```

The MOS and BASIC run for `bootSeconds` (two seconds by default) before the program loads at `&2000`, so the screen
and the vectors are in place for [the sample](../sample/bbc/hello.asm)'s `JSR OSASCI`.

The options are:

- `model`: `bbcb` (the default) or `bbca`;
- `diskInterface`: the 8271 and DNFS on the Model B, on by default;
- `disks`: SSD or DSD images for drives 0 and 1;
- `cassette` and `fastCassette` (on by default): a `.uef` tape, or a file with an `.inf` file beside it;
- `romDirectory` and `sdkRoms`: the dumps, and the folder of the ROM sources, such as the repository's, so
  breakpoints set there bind;
- `sound`: `speaker` (the default) or `off`;
- `speed`: `1` (the default) runs at 2 MHz, `2`, `4` or `8` that many times as fast, and `"max"` as fast as
  possible.

The panel's key bar has **Escape** (Esc), **Copy** (End), **Shift Lock** (Scroll Lock), **f0**-**f9** and **Break**
(Ctrl+F12 or Ctrl+Break); the cursor keys are the arrows, DELETE is Backspace, and £ types the BBC's £. Shift with
Break (Shift+click, or Ctrl+Shift+F12) is SHIFT-BREAK, which boots the disk in drive 0, and Start Machine boots a disk
image the same way, with the launch's `boot`. In Retrocore Desktop, F1-F9 and F10 are f1-f9 and f0, Scroll Lock is
SHIFT LOCK, and Ctrl+Shift+F12 is SHIFT-BREAK.
**Machine reset** stops at the MOS's first instruction after BREAK. The **BRK instructions** filter stops at each
error the MOS, BASIC or the DFS raises, and names it. The Drives view shows the cassette and the drives, and
inserts, records, ejects and saves media; `retro/media` takes the same requests.

**What the debugger knows about the BBC Micro.**

- Each paged ROM socket is its own memory area: a breakpoint in `BbcBasic.asm` or `Dnfs.asm` stops only while ROMSEL
  has that ROM paged in, and stepping follows the MOS as it pages ROMs in and out.
- The call stack follows `JSR`, `BRK` and interrupts on the 6502's stack; the Variables view lists A, X, Y, S, P and
  PC, and the **Zero page** memory scope.
- The code DNFS copies into RAM and runs there, its NMI routines at `&0D00` and the Tube host code, shows as
  disassembly rather than source.

**BBC BASIC.** BBC BASIC II programs have the BASIC thread, the program document and `basic` launches, as AppleSoft
and Color BASIC do; the [extension's README](../extension/README.md#basic-programs) describes them. Files are
`.bbcbasic.bas`, or a `.bas` whose first line is `REM retrocore bbcbasic`.

- The program is tokenised as BASIC II's tokeniser does: keywords only in capitals, abbreviations with a full stop,
  line numbers after `GOTO`, `GOSUB`, `THEN`, `ELSE` and the like packed as `&8D` and three bytes, and the spaces
  typed after a line number kept, so a line lists as it was typed. Words are case-sensitive, so `print` is a name.
- Statements start at `EXECUTE_STATEMENT`, which also skips the spaces before a statement, and which IF, THEN and
  ELSE enter part way along a line; a breakpoint on a line stops at its first statement, and the statements after
  THEN belong to the IF.
- BASIC keeps no current line number: the line is the one PTRA is in. FOR, REPEAT and GOSUB have their own stacks in
  page five. A PROC or FN moves the 6502's stack onto BASIC's stack and starts it afresh, so the debugger follows the
  calls as they are made: the BASIC call stack shows each GOSUB, PROC and FN with the line it was made from, and Step
  Over and Step Out step over them.
- The Variables view lists the resident integers A%-Z% that are not zero, then each variable list's variables in the
  order BASIC made them, the arrays (the last subscript varying fastest), the FOR loops and BASIC's memory: PAGE to
  TOP, the heap from LOMEM, and BASIC's stack below HIMEM. Watch expressions and conditions take BASIC's operators,
  string functions and indirections (`?&70`, `!addr`, `$addr` and `A%?1`), reading memory as BASIC does, and setting
  a variable or a string writes it as BASIC would.
- In a `.bbcbasic.bas` file, the assembler between `[` and `]` highlights its mnemonics, registers, labels and `\`
  comments, and what it skips: everything after an implied instruction, a register or the shifts' `A`, and a `;` or `\`
  after an operand. Its mnemonics, registers and skipped text are not variables to rename or find; its labels and the
  names in its operands are. Another BASIC's word, such as `HOME`, is a variable like any other, as BBC BASIC keeps names whole;
  it is warned of only as a statement of its own, where BASIC stops with Mistake.
- STOP is error 0, and a program that runs off its last line returns to the prompt; BBC BASIC has no CONT.

## Testing

| Test | Checks |
| --- | --- |
| `BbcMachineTests` | Both models' banners, the DFS found, a typed program, every mode's text through hardware scrolling, colours, sound, BREAK and CTRL-BREAK, the analogue port. |
| `Crtc6845Tests`, `Sn76489Tests` | The shared 6845 and SN76489. |
| `BbcTapeTests`, `AcornTapeTests` | The Welcome tape's catalogue and introduction, `SAVE` and `LOAD` at both speeds through UEF, `.inf` files, RS-423. |
| `BbcDiskTests`, `AcornDiskImageTests` | The Welcome disk's catalogue, `SAVE`, `LOAD`, `*BACKUP`, `*COMPACT`, formatting and verifying, SHIFT-BREAK, a DSD's second side, and saving as SSD. |
| `BbcMosSourceTests`, `BbcBasicSourceTests`, `BbcDnfsSourceTests`, `BbcSaa5050SourceTests` | Each source by digest and against the dump, a machine running from each build, and the documentation lint. |
| `BbcBasicDialectTests` | The keyword table against BASIC II's, line numbers packed and unpacked, lines typed on a Model B stored as the dialect tokenises them and listed as typed, a program written into memory listing and running, and a SAVEd program's image read and written back. |
| `BbcOracleTests` (Conformance) | Instruction traces against MAME's `bbcb` through [`tools/BbcOracle.lua`](../tools/BbcOracle.lua): from power-on to BASIC's prompt, and a DFS catalogue. |
| [`tools/Test-BbcDap.mjs`](../tools/Test-BbcDap.mjs) | The debugger end to end: stepping from the sample into `Mos.asm` and out, a breakpoint in `BbcBasic.asm` that a typed PRINT stops at, a BBC BASIC file on the BASIC thread (stepping, a PROC's frame, variables and the FOR loop, watch expressions, setting a string, Step Out, STOP and the program as text), the reset stop, a BASIC file on the Model A, and the Model B saving a program to an SSD that saves to its image; the last parts on the dumps when they are there and otherwise on the sources. |

What each test needs:

- **Nothing outside the repository:** the sources' digests and documentation lint, `Crtc6845Tests`,
  `Sn76489Tests`, `AcornTapeTests`, `AcornDiskImageTests`, `BbcBasicDialectTests` (on the ROMs built from the
  sources), and the DAP script, which runs on the built ROMs when the dumps are missing. These are what CI runs.
- **MAME's `bbcb` ROM set** (`RETROCORE_BBC_ROMS`): `BbcMachineTests`, the tape and disk tests that use its machine,
  the source tests that compare with the dumps or run a machine from each build. Without it they are inconclusive,
  not passed.
- **MAME's `bbcb_cass` and `bbcb_flop` software lists** (in `bbc-media`): the cases on the Welcome tape and disk.
- **MAME itself:** `BbcOracleTests`.
