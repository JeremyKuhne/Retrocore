# The TRS-80 Model I

Retrocore's Model I is [`Trs80Machine`](../src/Retrocore.Machines.Trs80/Trs80Machine.cs): a T-state-exact Z80
with the Model I's memory map, video, keyboard and cassette, and optionally the Expansion Interface with its
clock interrupt, extra RAM and floppy disk controller. This guide covers what it emulates, its ROMs and their
sources, and how to debug on it.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| ROM | $0000-$2FFF (Level I $0000-$0FFF) | Level II 1.2 or 1.3, or Level I. |
| Expansion Interface | $37E0-$37FF | The interrupt latch ($37E0: bit 7 the 40 Hz clock, which a read clears; bit 6 the disk controller), drive select ($37E1), cassette select, the printer ($37E8) and the FD1771 ($37EC-$37EF). |
| Keyboard | $3800-$3BFF | The 8x8 matrix; address bits 0-7 select rows. |
| Video | $3C00-$3FFF | 64x16 text, or 32x16 in wide mode, with 2x3 block graphics for codes $80-$BF. |
| RAM | from $4000 | 4K to 48K; more than 16K needs the Expansion Interface. |
| Port $FF | | Cassette output and motor, and 32-column mode; reads return the cassette input. |

**CPU.** The Z80 runs at 1.774 MHz (1,774,080 Hz). It passes the SingleStepTests at every T-state, ZEXDOC,
ZEXALL and the FUSE tests, including the undocumented flags and MEMPTR.

**Interrupts.** The Expansion Interface interrupts at 40 Hz (every 44,352 T-states) and on disk controller
events. Level II leaves interrupts disabled; disk operating systems use them.

**Video.** A frame is 264 lines of 112 T-states. The display reads video RAM as the beam reaches each character
row, so programs that change the screen mid-frame show it. A stock Model I has no bit 6 in video RAM, so the
circuit reads it as the inverse of bit 5. The lowercase modification adds the seventh bit. Radio Shack's kit
also replaced the character generator with one whose lowercase letters have true descenders, so a lowercase
machine draws with the kit's font (`characterGenerator: "kit"`, the default with `lowercase`). Level II writes uppercase letters
without bit 6, as codes `$00`-`$1F`, and the kit's font repeats the uppercase letters there. `"stock"` keeps the
MCM6670P, whose own lowercase letters at `$60`-`$7F` sit raised, as on a lowercase conversion that kept it.

With `snow` on, the scanned picture shows the Model I's "snow". Video RAM shares its data bus with the
video circuit, which draws one of a line's 64 characters each T-state. A CPU read or write while the beam
draws a character puts the CPU's byte on that bus, so that character's scanline shows the CPU's byte instead.

**Keyboard.** A typed character presses its key, holds it 40 ms and releases it for 60 ms. Level II 1.3 rereads
a new key after 19 ms to debounce it, then pauses about 50 ms before it scans again, so shorter timing would lose
doubled letters. BASIC also does not scan the keyboard while it carries out a command, so a script that types
should wait for `READY` before typing the next command. An uppercase letter is typed as its key alone, and a
lowercase letter with shift, which Level II reads as the lowercase code; ` is shift and @. Level I reads shift and a
letter as its control code, so on Level I every letter is typed as its key alone, and ` has no key. Unlike the Model
I's Level II, Level II on the Model III and 4, and the DOSes of the Model III, 4 and 4P, type uppercase with shift
([Typed and pasted text](Trs80Model3And2.md#typed-and-pasted-text)).

**Cassette.** Level II records 500 baud and Level I 250 baud pulse cells, to and from CAS images. A CAS image
drops the silences between blocks. Playback therefore holds a pulse while the ROM still has an unread one,
which recreates the pause after the file name that CLOAD needs. The machine's timing is the tape's real speed,
but the debugger runs as fast as it can while the cassette motor runs (`fastCassette`, on by default), so a
tape loads or saves in a fraction of its playing time.

Neither Level reads the other's tapes: a Level I tape in Level II plays to its end with nothing loaded. The CAS image
does not say its speed, but its first recording says which BASIC wrote it. After the leader of zero bytes and the
`$A5` sync byte, Level II's `CSAVE` writes three `$D3` bytes (`ST_CSAVE` in `Level2.asm`), a `SYSTEM` tape has the
`$55` that begins its header, then a six-character name and its first `$3C` block, and Level I writes its block's start and end addresses, high bytes first
(`TAPE_WRITE_BLOCK` in `Level1.asm`). A tape put in a machine whose ROM cannot read it still goes in, and the debug
console and the cassette's row in the Drives view say so, for example: *This tape was recorded by Level I BASIC
(250 baud); Level II can't read it. Switch the ROM to Level I.* The row also says what a tape holds: a Level I tape,
a Level II BASIC program or a Level II SYSTEM tape. A tape that is none of these gets no warning.

**Disks.** The FD1771 runs Types I-IV commands with their step rates, verify, rotational sector search,
byte-timed DRQ, lost data, record-not-found and record types. Read address, read and write track, force
interrupt and the 3-second motor timeout are emulated too. Four drives take JV1, JV3, DMK or IMD images, and a disk
the DOS changes saves back to its image in its own format, or as another, when the debugger is asked to save it
([Devices.md](Devices.md#the-debug-protocol)).

Double-sided drives take their side select from bit 3 of the select latch at `$37E1`, which is also drive 3's
select. Bit 3 with drive 0, 1 or 2 selects side 1 of that drive, so a Model I with double-sided drives has
three of them.

A doubler adds a WD1791 for double density beside the FD1771:

| `doubler` | Selects double density | Selects single density |
| --- | --- | --- |
| `percom` | `$FF` written to the command register | `$FE` |
| `tandy` (Radio Shack's) | `$80` written to the sector register | `$A0` |
| `both` | either | either |

NEWDOS/80 probes for the Percom doubler. The Radio Shack doubler's side select (`$40`, `$60`) and write
precompensation (`$C0`, `$E0`) values change nothing that the emulated disk sees.

## ROMs

Without dumps, the debugger assembles the ROMs from the SDK's sources, which are byte-identical to them. A
launch can supply ROM dumps instead, in `romDirectory` or `RETROCORE_TRS80_ROMS` (default
`%USERPROFILE%\Retrocore\trs80-roms\extract`, or under `RETROCORE_CACHE`), named as MAME names them:

| File | ROM |
| --- | --- |
| `rom-a.z1`, `rom-b.z2`, `rom-c.z3` | Level II 1.2 (checksums AE60, DA45, 40BA). |
| `rom-a_alt.z1`, `rom-b_alt.z2`, `rom-c_alt.z3` | Level II 1.3 (B078, DA45, 4006). |
| `level1.rom` | Level I. |
| `mcm6670p.z29` | The character generator. |

1.3 asks `MEM SIZE?` and shows `R/S L2 BASIC`; 1.2 asks `MEMORY SIZE?` and shows `RADIO SHACK LEVEL II BASIC`.
1.3 also added the keyboard debounce, fixed the cassette timing, and limited TAB to 127.

## The ROM sources

[`Level2.asm`](../src/Retrocore.Machines.Trs80/Roms/Level2.asm), [`Level1.asm`](../src/Retrocore.Machines.Trs80/Roms/Level1.asm)
and [`CharacterGenerator.asm`](../src/Retrocore.Machines.Trs80/Roms/CharacterGenerator.asm) are native-dialect
sources. They are maintained by hand, and
[`Trs80RomSourceTests`](../tests/Retrocore.Tests/Trs80RomSourceTests.cs) pins each build by SHA-256.

[`CharacterGeneratorKit.asm`](../src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm) is the lowercase
kit's font. No dump of the kit's chip is known, so it follows xtrs's reconstruction (`trs_chars.c`, CG 2): Tim
Mann made it from the MCM6674 data sheet and memory, and Ulrich Müller checked and corrected it against a real
Model I. `tools\Fetch-Trs80Font.ps1` fetches that file at a pinned commit into
`%USERPROFILE%\Retrocore\trs80-fonts\xtrs`, and the test then compares the two glyph for glyph. xtrs's
stock set matches the MCM6670P dump in every glyph but `a`.

**Level II.** `REVISION` selects 13 (the default) or 12, and the two revisions differ in 32 `.if` blocks. The
source is organized as:

- the restarts and documented ROM calls: `KBD_SCAN`, `DISPLAY_CHAR`, `PRINTER_CHAR`, `KBLINE`, `KBWAIT`,
  `DELAY`;
- the device drivers and the `RAM_VECTORS` that the cold start copies to $4000, with a `DCB` macro per device;
- the keyword list (a `KEYWORD` macro, with `TK_` token constants);
- the statement and function dispatch tables (`ST_` and `FN_` handlers, or `HOOK_` for Disk BASIC's vectors);
- the error codes (`ERR_` constants, with the `LD E,ERR_xx` at each error entry);
- Microsoft BASIC itself.

Routines that are Microsoft's keep Microsoft's names, such as `FRMEVL`, `PUSHF`, `FNDFOR` and `STROUT`, where the
code is plainly that routine. Others have descriptive names, such as `CASSETTE_SELECT_ARG` or `ERASE_PROGRAM`,
with a one-line summary above them, and inner labels are named after their routine (`NAME_1`, `NAME_2`).

**Level I** follows Li-Chen Wang's Palo Alto Tiny BASIC, and keeps his names: `TSTC`, `OUTC`, `EXPR`, `COMP`,
`IGNBLK`, `FINISH`, `TSTV`, `EXEC`, `PRTSTG` and so on. Its keyword tables use `ENTRY` and `DEFAULT` macros,
and `TSTC 'c', label` writes the inline character test.

**The character generator** draws each character with a `GLYPH` and seven `ROW`s of dots.

The sources are maintained by hand, and assemble byte for byte to the ROMs.

## Debugging

Level II and Level I are in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts either with a
program, a tape or a BASIC file, and Level II with a disk too, all without a launch.json; the extension README's
[Starting a machine](../extension/README.md#starting-a-machine) explains both.

The ROM and the memory are settings of the machine, in Start Machine's options and the Machine view's **Settings**:

- **ROM**: Level II BASIC 1.3 (the default), Level II BASIC 1.2 or Level I BASIC, the `rom` and `revision` options.
  Changed while the machine is off, the tape stays in; Level I, which has no disks, takes out the disks and the disk
  controller; and the memory becomes the new ROM's unless a size was chosen. A machine Start Machine starts from a disk
  keeps Level II, and one that runs a BASIC file that names its dialect, by its name (`.level1.bas`) or its first line,
  keeps the ROM whose BASIC that is; a plain `.bas` goes into whichever BASIC the ROM has. While it runs, the Machine view's ROM row
  (or the ROM setting) offers to change it: after asking, since what is only in the machine's memory is lost, it
  stops the session, sets the ROM as it would off, and starts the machine again with its tape.
- **Memory**: 4, 16, 32 or 48 KB, `ramKilobytes`. 32 and 48 KB bring the Expansion Interface, and taking the
  interface out brings the memory down to 16 KB. Left out, it is 48 KB with the interface, else 16 KB, or 4 KB for
  Level I; Level I Model Is were sold with 4 KB or 16 KB, and Level I finds its memory's top by probing, so
  `PRINT MEM` gives 3583 bytes free in 4 KB and 15871 in 16 KB.
- **Expansion Interface**: on by default with Level II, off with Level I.

Launch configurations take `"machine": "trs80-model1"`. To boot Level II with its source:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Model I: boot Level II",
    "machine": "trs80-model1",
    "sdkRoms": "${workspaceFolder}/src/Retrocore.Machines.Trs80/Roms",
    "stopOnEntry": false
}
```

**Machine reset**, on by default in the Breakpoints view, stops as the machine powers on, at the first instruction
in `Level2.asm`. Continue, and press ENTER at `MEM SIZE?` in the display panel; the machine sizes its RAM (about
two seconds) and shows `READY`. `sdkRoms` makes breakpoints set in the repository's copy of the source bind, such
as a function breakpoint on `READY`.

The reset button (**Reset** on the panel's key bar, **Ctrl+F12** or **Ctrl+Break**) raises the Z80's non-maskable interrupt, as
it does with and without the Expansion Interface. Level II's handler, `NMI` at `$0066`, boots a disk when the disk
controller answers and otherwise restarts BASIC with the program kept. **Machine reset** stops there.

To debug a Z80 program, such as [the sample](../sample/trs80/hello.asm):

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Model I: Z80 sample",
    "machine": "trs80-model1",
    "source": "${workspaceFolder}/sample/trs80/hello.asm",
    "stopOnEntry": true
}
```

The ROM boots for `bootSeconds` (one second by default) before the program loads at `$7000`, so the RAM vectors
and device control blocks its ROM calls use are in place. Stepping into `CALL DISPLAY_CHAR` goes into
`Level2.asm`, and stepping out comes back.

The other options are:

- `rom`: `level2` or `level1`;
- `revision`: `1.2` or `1.3`;
- `romDirectory`: the dumps;
- `ramKilobytes`, `expansionInterface`, `diskController`, `lowercase` and `doubler` (`none`, `percom`, `tandy`
  or `both`);
- `characterGenerator`: `stock` or `kit` (the default with `lowercase`);
- `snow`: show video snow (off by default);
- `screen`: the monitor, `green` (the default), `white` (black and white) or `amber`, which lights the dots in
  that phosphor's color. The display panel's **Screen** changes it while debugging;
- `cassette`, `fastCassette` (on by default) and `disks`;
- `speed`: `1` (the default) runs at 1.774 MHz, `2`, `4` or `8` that many times as fast, and `"max"` as fast as
  possible. The display panel's **Speed** changes it while debugging.

The disk controller is on by default only when disks are given, since with a controller and no disk the ROM
waits for a disk to boot.

**Media.** The Drives view in VS Code shows the cassette and the drives with their media, head and
activity, and inserts, records, ejects and write-protects through the `retro/device` request
([Devices.md](Devices.md)). The TRS-80 commands insert, record and eject tapes, and insert and eject disks,
through the older `retro/media` request:

```json
{ "device": "cassette", "action": "record", "path": "program.cas" }
{ "device": "disk", "action": "insert", "drive": 0, "path": "newdos.dsk" }
```

A recording is saved to its path when the tape is ejected.

**Level II BASIC** debugs on its own BASIC thread: breakpoints and stepping by statement (with inline breakpoints
after colons), GOSUBs in the call stack, `FOR` loops, single, double, integer and string variables and arrays, and
Level II expressions. A `basic` launch takes a `.level2.bas` file (or one with `' retrocore level2` or
`REM retrocore level2`), with optional labels in place of line numbers. **Retrocore: Open BASIC Program** edits the
program in memory, and imports and exports `.cas` tapes, listings and tokenized files.

**Level I BASIC** has the BASIC thread too, from `Level1.asm`'s symbols: **BASIC program start** stops where RUN
starts and CONT resumes, line breakpoints and steps go by statement (Level I's colons, and abbreviations such as `P.`
for PRINT, read as `EXEC` reads them), GOSUBs are in the call stack, and the Variables view shows A to Z, A$ and B$,
the array A(n) counting down from the top of memory, and the FOR loops. Level I keeps no tokens: a line is its number
and its text as typed, from `$4200` to `TXTUNF`, so a `.level1.bas` file (or one with `REM retrocore level1`) reads
as the program lists. Its errors, HOW?, WHAT? and SORRY, stop as **BASIC errors**, except a mistyped answer to INPUT,
which asks again and counts as handled. An error in a DATA item that READ is taking does not stop: Level I has no
current line while it reads the item, and reports the error with none. Not every Level I tape is a BASIC program: one whose block does not start at
`$4200`, as the Eliza tape's starts at `$41FE` to load over CLOAD's return address and start its machine code, is
memory, which Import refuses, and debugs at the Z80 level against `Level1.asm`. A `basic` launch with `"rom":
"level1"` takes a `.level1.bas` file (or one with `REM retrocore level1`, or a plain `.bas`), with optional labels in
place of line numbers: Level I starts at `READY`, the program goes into memory, and RUN stops at its first statement
with `stopOnEntry`. A Level II file is refused, as Level I cannot load it.

**What the debugger knows about the Z80.**

- The call stack follows `CALL`, taken conditional calls, `RST` and interrupts. It checks each frame's return
  address on the stack, so a routine that drops its return address or returns elsewhere ends its frame.
  Level II's `RST $08` returns past its inline byte.
- Step out stops when the stack returns to the caller's, wherever the routine returns.
- The Variables view lists every register, including the pairs, the alternates, I and R, and the `$4000-$40FF`
  **Communication region** memory scope. Expressions name registers (`HL`, `IX`), and `[addr]` and `[addr].w`
  read memory.
- A `CALL` or `RST` line shows its latest call's cycles, in T-states.
- `Keeps:` sections name Z80 registers by their letters and flags by their words (`HL`, `C`, `carry`), so
  `C` is always the register.

## Testing

| Test | Checks |
| --- | --- |
| `Trs80MachineTests`, `Trs80DiskTests`, `Trs80CassetteTests` | The machine, with test ROMs assembled in the tests. |
| `Trs80RomTests` | Level II and Level I boot. CSAVE and CLOAD round-trip, 1.3 takes typed lines, and NEWDOS/80 boots from JV1 and JV3. |
| `Level1DialectTests` | Level I's program, as typed into the SDK's Level I ROM, read back and written in; its variables and numbers, written as its PRINT writes them; its FOR loops from `LOPVAR` and the stack; its statements, abbreviations and line references; and its CSAVE tapes, a machine-code block refused. |
| `Trs80TapeContentsTests` | Which BASIC a tape is for, from Level II's and Level I's own recordings, the cassette's warning for the other Level's tapes, and Level I's `PRINT MEM` in 4K and 16K. |
| `Trs80OracleTests` (Conformance) | The same keystrokes on our machine and on MAME, through [`tools/Trs80Oracle.lua`](../tools/Trs80Oracle.lua). The screens must match, and so must the BASIC program bytes; each keystroke must fire within 0.025 s, a frame and a margin, after its time, fractional seconds included. |
| `Trs80RomSourceTests` | The ROM sources, by digest and against the dumps. |
| [`tools/Test-Trs80Dap.mjs`](../tools/Test-Trs80Dap.mjs) | The debugger end to end: boot, a ROM-source breakpoint with the call stack, a cassette round trip, stepping from a program into the ROM source, a NEWDOS/80 boot, the warning for a tape of the other Level, in a launch and from a saved machine, and Level I's BASIC thread: RUN's start, steps, a line breakpoint in a GOSUB, its variables, STOP and a Level I tape round trip. |

Tests that need dumps, MAME or a DOS image are inconclusive without them. The DAP script needs none, since its
ROMs come from the SDK sources.
