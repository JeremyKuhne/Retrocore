# Backlog: debugging BASIC programs

Status: **two steps left: Level I and disk images.** AppleSoft, Integer BASIC and Level II are done: the library
([`Retrocore.Basic`](../../src/Retrocore.Basic)), the command line, the machine-program editor with import and
export, the language support, the BASIC thread, BASIC variables, and workspace files with labels and the `basic`
launch. The [extension README](../../extension/README.md) describes them. Each dialect is a class behind one
interface (`BasicDialect`), so the steps below add a dialect and a file source without changing the debugger or
the editor.

## Level I

Level I BASIC is the Model I's first ROM, Palo Alto Tiny BASIC, with an SDK source
([`Level1.asm`](../../src/Retrocore.Machines.Trs80/Roms/Level1.asm)). It keeps a program differently from the
Microsoft BASICs: lines are stored as text, with the abbreviations as typed (`P.` for `PRINT`), and the variables
are fixed (`A` to `Z`, `A$`, `B$` and one array). Today the `retrocore-level1` language id and the `.level1.bas`
extension exist, but a Level I document only says it is not supported yet.

What it takes:

- **The dialect:** reading and writing the program image (a line number and the line's text), the keywords and
  their abbreviations for highlighting and help, and the hooks (statement start, current line, GOSUB and FOR
  stacks, errors) named from `Level1.asm`.
- **The editor and files:** the machine-program editor, text import and export, and Level I's `CSAVE` tapes.
- **The BASIC thread and variables:** stops, steps and GOSUB frames as the other dialects have them; its scopes
  are the fixed variables, `A$`, `B$` and the array.
- **Language support:** a grammar, diagnostics, navigation, hover, completion and renumber, as Level II has.

## Disk images

Import and export of programs as files on disk images, once the media library has filesystems and writes
([Media.md](Media.md), steps 3 to 5):

| Machine | Files |
| --- | --- |
| Apple II family | AppleSoft and Integer BASIC files on DOS 3.3 and ProDOS disks |
| Model I | Disk BASIC files on TRSDOS and NEWDOS/80 disks |

The **Import** and **Export** commands gain a disk image as a source and a destination, beside text listings,
tokenized files and tapes.

## Color BASIC

The Color Computer 1 and 2's Color, Extended and Disk Extended Color BASIC get what Level II has: the program as a
document behind the panel's BASIC button, import and export, the BASIC thread with its stops, steps, GOSUB frames
and variables, the `basic` launch, and language support. Their ROMs are SDK sources
([`ColorBasic.asm`](../../src/Retrocore.Machines.Coco/Roms/ColorBasic.asm), `ExtendedBasic.asm` and
`DiskBasic.asm`), so the hooks are named from them. The CoCo 3's Super Extended BASIC follows once its source is
built ([CocoRomSources.md](CocoRomSources.md), stage 4).

**Status:** steps 1-3 built 2026-11-12, awaiting review. Two things the plan did not foresee: a string's descriptor
has a spare byte before its address, and a string array's elements are five bytes; and a GOSUB takes seven bytes of
the stack, its entry over the statement loop's return, which RETURN returns through. Cassette import and export
(decision 6) are still to do.

### Decisions

1. **One dialect, `colorbasic`, at three levels.** The three BASICs share one token table, each adding to it: Color
   BASIC's commands from `$80` and functions from `$FF $80`, Extended BASIC's after them, and Disk BASIC's after
   those. A machine crunches with the words its ROMs know, so a word Disk BASIC adds stays text on a machine
   without the disk controller, as the ROM leaves it. Files are `.colorbasic.bas`, and the display name follows the
   ROMs: Color BASIC, Extended Color BASIC or Disk Extended Color BASIC.
2. **Two-byte function tokens.** `BasicDialect` learns a prefix byte (`$FF`) for a second keyword table, for
   crunching, listing and the language support. The other dialects have none.
3. **Big-endian memory.** The 6809 keeps line links, line numbers, pointers and string addresses high byte first.
   `BasicDialect` says its byte order, and the program, variables, current line and the BASIC thread's stack reads
   follow it.
4. **Statements start at `GONE2`.** Color BASIC's own loop, Extended BASIC's `XVEC20` and Disk BASIC 1.1's `DVEC20`
   all run each statement through it, so one breakpoint serves all three. The prompt is `OKPRMT`, the stops are
   `STOP`, `END`, BREAK and running off the program's end, and errors are taken at `ERROR` with B's code, named from
   the three ROMs' error tables. Color BASIC has no `ON ERROR`, so no error is handled.
5. **Variables as AppleSoft's.** Color BASIC keeps AppleSoft's layout: two name bytes, then a five-byte number or
   a string descriptor, and arrays with their sizes; only the byte order differs.
6. **Tapes later.** Import and export start with text listings and the crunched program image; `CSAVE`'s cassette
   blocks follow as their own step, with the media library.

### Steps

1. **The dialect and the program:** the token tables, crunching as `CRUNCH` does, listing as `LIST` does, the
   byte order, and the program document behind the BASIC button, with import and export of listings. Tests round-trip
   programs through the ROMs from source, typed in and read back.
2. **The BASIC thread:** `BasicRom` from the SDK's symbols, statement breakpoints, steps, GOSUB frames and FOR
   loops from BASIC's stack, errors, and the variables view. `tools/Test-CocoDap.mjs` debugs a program.
3. **The `basic` launch and language support:** `.colorbasic.bas` files launch on a CoCo 1 or 2, with highlighting,
   diagnostics, hover and completion from `Keywords.txt`, as Level II has.

## Later

The CoCo 3's Super Extended BASIC, once its source is built.
