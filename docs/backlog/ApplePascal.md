# Backlog: Apple Pascal

Status: **asked for 2026-11-13** ("implement Apple III Pascal support", designed with Apple II Pascal in mind). Built
for both machines, every version at hand: see Built. Apple Pascal 1.3, which no allowed host had, and writing Pascal
(Apple II) volumes are what remain. [Pascal.md](../Pascal.md) is the user guide.

Apple Pascal is UCSD Pascal II.1 for the Apple II (Apple Pascal 1.0-1.3) and the Apple III (Apple III Pascal
1.0-1.2). A program is compiled to p-code, the instruction set of a stack machine, and a 6502 interpreter runs it.
Both machines share the p-code, the code file format and most of the operating system, which is itself p-code
(`SYSTEM.PASCAL`). They differ in what is under the p-machine:

| | Apple II | Apple III |
| --- | --- | --- |
| Interpreter | `SYSTEM.APPLE`, loaded into the language card | `SOS.INTERP`, a SOS interpreter file |
| Files | Pascal volumes: a flat directory in blocks 2-5 | SOS volumes, through SOS's file calls |
| Code file version | 2 (II.1) | 4 (1.1) and 6 (1.2) |
| Memory | 64K: the language card holds the interpreter | Banks; the interpreter sits below `$B800` in the system bank |

So everything above the interpreter is written once, and each machine supplies its interpreter's addresses and its
file system.

## What there is

**Disks** (in `RETROCORE_APPLE3_DISKS` and `RETROCORE_APPLE2_PASCAL_DISKS`), from apple3.org and the Asimov mirror:

| Image | SHA-256 | What it is |
| --- | --- | --- |
| `Apple3Pascal1.1Disk1.dsk` | `97918dd4…6089` | /PASCAL1: SOS 1.3, `SOS.INTERP`, `SYSTEM.PASCAL`, the Filer, `SYSTEM.LIBRARY` |
| `Apple3Pascal1.1Disk2.dsk` | `5799c691…2837` | /PASCAL2: the Editor, Compiler, Assembler and Linker |
| `Apple3Pascal1.1Disk3.dsk` | `fa65123d…937c` | /PASCAL3: utilities and the full `SYSTEM.LIBRARY` |
| `Apple3Pascal1.2UpdateDisk1.dsk`, `…Disk2.dsk` | `05319655…daaf`, `334710c2…2ab9` | 1.2's interpreter, system and tools |
| `UCSD Pascal 1.1_0.dsk` … `1.1_3.dsk` | `4e6b4792…cf4b`, `d6e7509a…4229`, `88b67683…1adf`, `86141693…3058` | Apple Pascal 1.1: APPLE0-APPLE3, with sample programs as source and code |
| `UCSD Pascal 1.2_0.DSK` … `1.2_3.DSK` | `6f8fd3bd…16ab`, `25daeefe…1da0`, `6576fccb…9f21`, `488bc4bd…d275` | Apple Pascal 1.2 |

**Already in Retrocore:** `SosVolume` reads SOS volumes, and `SosDriverCodeFile` reads a Pascal code file with one
native segment (Titan's RAM disk driver). Apple III Pascal 1.1 boots on the emulator, edits, compiles with a
listing, and runs the program.

## Built

Built 2026-11-13:

- **Media:** `SectorDiskReader`, `PascalVolume`, `PascalCodeFile` (with `SosDriverCodeFile` on it) and
  `PascalTextFile`; `PascalMediaTests`. A procedure whose dictionary entry leads outside its segment is left out:
  the system segment stubs at the head of Apple III Pascal's Editor and Linker only declare procedures, and Apple
  Pascal 1.1's `PASCALSY` lists 57 in a segment that holds fewer.
- **P-code:** `Retrocore.Pascal`'s opcode table and `PcodeDisassembler`, and `--pascal`; `PcodeTests`. Every p-code
  procedure on the 1.1 disks and both Apple III versions decodes, with every jump landing on a p-code: the code on
  Apple III Pascal's disks (versions 4 and 6) uses no opcode II.1 lacks. An `XJP`'s missing cases point at its own
  `UJP`. The unnamed initialization segment in `SYSTEM.PASCAL` jumps into its jump table, and decoding stops there.
  Apple Pascal 1.2's `SYSTEM.EDITOR` on the Asimov image has damaged code in `COPYFILE.1` (from `$055A`).
- **Booting and running:** `Apple3PascalTests` and `Apple2PascalTests` boot, list the boot disk in the Filer, and
  edit, compile with a listing and run a program, reading its code file and listing back from the disk.
  - **Found:** the Apple III's keyboard sent control characters without CONTROL, so SOS made CONTROL-C a C
    (fixed, `Apple3BusTests.ControlCharacterHoldsControl`).
  - On the Apple II, CONTROL-C replaces the keys queued before it, as BASIC needs, so a test types it alone; and
    keys queued faster than a typist can lose some while the Editor scrolls, so the test types a line at a time.
- **The debugger's p-machine:** `PascalInterpreter`, `PascalMachine` and `PascalCodeLibrary`, `PascalRuntime` on
  each Apple target, and the Pascal thread (`DebugSession.PascalThread.cs`); checked by the `FramesReadFromTheMarkStack`
  tests and `tools/Test-PascalDap.mjs` on both machines.
  - **The interpreters, as found:** both keep BASE, MP, JTAB, SEG and IPC at `$50-$59`, and fetch with
    `LDA ($58),Y` (Apple III Pascal 1.1 at `$870E`, with zero page at `$1A00`; Apple Pascal 1.1 at `$D255`). An MSCW
    is 12 bytes: the static and dynamic links, the caller's JTAB, SEG and IPC, the 6502 stack pointer, and on the
    Apple III the caller's code X-byte. Locals follow it, local n at MSCW + 10 + 2n.
  - The interpreter is found by its fetch's bytes, so other versions should be found too, but only 1.1 is checked.
  - `WozDisk.Version` counts changes, so code files the Compiler writes while the machine runs are found.
- **Not done** in that round: line breakpoints, named variables, the 1.2 versions, the IIe and a language for
  sources; all but Apple III Pascal 1.2 are built in the next.

Built 2026-11-13, the second round:

- **Writable disks:** an Apple disk's write protection can come off (the Retro Devices view, a saved machine, or
  `retro/device` with `writeProtect`), so the Editor and Compiler can save in a debug session. Writes stay in memory.
- **Listings:** `PascalListing` reads a compiler listing: each line's segment, procedure, depth or declaration and
  offset, the segments' and procedures' names, and the words of declared variables where their types' sizes are
  known; `PascalListingTests`.
- **Source lines:** breakpoints in `.pas`, `.pascal` and `.text` sources bind through `NAME.LST.TEXT`, on a disk in a
  drive (read again when it changes) or beside the source, to the first p-code of the line's statement. Frames show
  source lines and procedure names; Step Over and Step Into go by line. `Test-PascalDap.mjs` compiles HELLO in the
  debugger, stops at its line 9 in a host copy, steps, and stops there again on the loop's next pass.
- **Variables:** named, with values as their types read, in Locals and Globals and on hover.
- **The extension:** `retrocore-pascal` for `.pas` and `.pascal`, with a grammar and gutter breakpoints;
  `pascalGrammar.test.ts`.
- **Versions:** Apple Pascal 1.2 boots, compiles and runs on the II Plus and the IIe, and 1.1 on the IIe
  (`Apple2PascalTests`); 1.2's interpreter fetches at `$D266`, with the same registers and mark stack.
- **Found:**
  - Apple Pascal's interpreter uses both of the language card's `$D000` banks, so the debugger looks for it in each.
  - On both machines, keys pasted faster than a typist types can be lost while the Editor scrolls: SOS's and
    Apple Pascal's type-ahead overflows. The tests type a line at a time, and the guide says to paste in pieces.
- **Not done:** Apple III Pascal 1.2, whose disks are updates to copy onto 1.1's (that needs SOS volumes the media
  library can write); `.TEXT` files open as plain text unless associated with `retrocore-pascal`; pacing pasted
  text to what the program takes.

Built 2026-11-13, the third round:

- **Every version at hand:** Apple Pascal 1.0 on the II Plus and Apple III Pascal 1.0 boot, compile and run, and
  their frames read (`Apple2PascalTests`, `Apple3PascalTests`). 1.0's R(un) runs no code its C(ompile) wrote, so
  the tests X(ecute) it; its Compiler leaves the code file open when it also writes a listing, so 1.0 compiles
  without one; and Apple III Pascal 1.0's first disk has its known damaged Filer.
- **SOS volumes written:** `SosVolumeBuilder` lays out a 140K volume (boot blocks, directory, bitmap, seedlings and
  saplings), and `--pascal sos` builds one from other disks' files (`SosVolumeTests`).
- **Apple III Pascal 1.2** boots from disks built from 1.1's and the update's, compiles and runs HELLO (code
  version 6), and its frames read. Its larger `SYSTEM.PASCAL` leaves no room on the boot disk for 1.1's Filer and
  Library, so they go on the second. Its Editor asks `Edit what file?` and its Quit asks `Write to what file?`.
- **Saving disks:** an Apple drive's `save` writes its disk to its image or another, as WOZ or as sectors in either
  order; the Retro Devices view's **Save to Its Image** and **Save Disk As...**. `Test-PascalDap.mjs` saves the
  disk the Compiler wrote both ways and lists HELLO.CODE on each.
- **Paced pasting:** on the Apple II and III, `retro/type` keys go in a typist's pace apart (30,000 cycles a key and
  300,000 a line on the II, twice that on the III), so the Editor takes a pasted program whole.
- **`.text` sources** open as Apple Pascal.
- **Not done:** Apple Pascal 1.3 (no image on an allowed host), writing Pascal volumes for the Apple II, and SOS
  trees (files over 128K, which a 140K disk barely needs).

Built 2026-11-13, the fourth round (asked for: "a disassembler for Apple II/III compiled Pascal", then "Decompile to
Pascal, ideally to something that can be recompiled into the exact same p-code"):

- **Decompiler:** `PascalDecompiler` and `--pascal decompile`: a code file back to Pascal that the Compiler compiles to
  the same code ([Pascal.md](../Pascal.md#decompiling)). Units are named from `PascalLibrary`, the library's
  interface text.
- **Checking it:** `EmulatedPascalCompiler` and `--pascal compile` run Apple Pascal 1.1's Compiler on an emulated
  Apple II with the source as the workfile (`PascalTextFile.Write`, `PascalVolume.WriteFile`), in about four seconds;
  `PascalCodeComparison` and `--pascal compare` compare code files. Apple's own sources on APPLE3 recompile to their
  code files, but for BALANCED's and DISKIO's alignment bytes, which hold stale bytes and are not compared.
- **Round trips:** the nine samples with sources and BINDER, without one, recompile to the same code
  (`PascalDecompilerTests`).
- **Found:** the Compiler allocates an identifier list from its last name, gives a function's result the first two
  words, initializes units in the reverse of USES and files in the reverse of their declarations, keeps a WITH's
  record (but a whole variable's) in a temporary, reaches a record variable's fields by their own offsets, writes
  negative constants as their magnitude and NGI, folds no constant expression, and passes FILE OF records' sizes in
  words; an untyped FILE is 40 words, a TEXT 301.
- **Not done:** see [PcodeAssembly.md](PcodeAssembly.md), the backlog of p-code disassembly and reassembly, with the
  decompiler's own next steps.

## The pieces

### 1. Media: volumes, sectors and code files

- `SectorDisk.Decode`: WOZ tracks back to a 16-sector image, so files can be read from a disk the machine wrote.
- `PascalVolume`: the Apple II's Pascal file system, read-only: the volume header and files in blocks 2-5, each a
  run of blocks with its kind and the bytes in its last block.
- `PascalCodeFile`: a code file of either machine:
  - the segment dictionary: up to 16 segments, each with its block, length, name, kind, text address, number,
    machine type and version;
  - each segment's procedure dictionary: per procedure its number, lexical level, entry and exit, parameter and
    data sizes;
  - an assembled procedure's relocation lists;
  - the interface text of a unit.
- `SosDriverCodeFile` reads its segment through `PascalCodeFile`.
- **Command:** `--pascal catalog disk` and `--pascal extract disk NAME output` for both volume kinds, as `--dos` does
  for DOS, and `--pascal segments file` for a code file's segments and procedures.

### 2. P-code

- The II.1 p-code: 256 opcodes, with their operand forms (unsigned and signed bytes, "big" one-or-two-byte
  numbers, words, word-aligned constants and case tables, and the standard procedure numbers of `CSP`).
- A p-code disassembler for a procedure: it follows the code from the entry, names the jump table's targets
  (negative `FJP`/`UJP` offsets) and the case tables of `XJP`, and lists the procedure's exit.
- **Command:** `--pascal disassemble file [segment[:procedure]]`. A native (6502) procedure goes to the 6502
  disassembler, with its relocated words marked.
- **Checked:** every p-code procedure in every code file on the disks decodes from its entry to its exit, and every
  jump lands on an instruction. If Apple III Pascal's versions 4 and 6 add opcodes, they are found this way.

### 3. Booting and running

- Apple III Pascal 1.1 and 1.2 boot, and the Filer, Editor, Compiler and a program run. `Apple3PascalTests` pins
  that.
- **Found already:** the Apple III's keyboard sent a control character without CONTROL held, so SOS's console
  turned CONTROL-C into a C. The panel's Ctrl+letter had the same problem under SOS.
- Apple Pascal 1.1 and 1.2 boot on a 64K Apple II Plus and a IIe, which need the language card.

### 4. The debugger's p-machine

The interpreter keeps the p-machine's registers in zero page:

| Register | What it is |
| --- | --- |
| IPC | the address of the next p-code |
| SP | the evaluation stack |
| MP | the current procedure's mark stack control word (MSCW): its static and dynamic links, the caller's IPC, segment and jump table |
| BASE | the outer block's MSCW, for global variables |
| SEG, JTAB | the current segment's procedure dictionary and the procedure's attributes |

The interpreter's fetch is where each p-code starts, as `GONE` is for a BASIC statement. For each interpreter
(`SOS.INTERP` 1.1 and 1.2, `SYSTEM.APPLE` 1.1 and 1.2) a small description names the fetch address and the zero-page
registers, found by its bytes, as `SosDriverModules` finds a driver.

- **The Pascal thread:** a DAP thread beside the CPU's, as BASIC has:
  - its frames are the MSCW chain, each named by segment and procedure, such as `HELLO.1 + $0012`, with the
    procedure's p-code disassembled where no source is known;
  - stepping goes by p-code, over a call, and out to the caller's MSCW.
- **Breakpoints:**
  - a function breakpoint `pascal HELLO.1` on a procedure's entry, and `pascal HELLO.1+$12` on an offset;
  - line breakpoints in a `.TEXT` source, from the compiler's listing: each listed line gives its segment,
    procedure, lexical level and p-code offset.
- **Variables:** the frame's parameters and locals as words, read from the MSCW, and the globals from BASE.
- **Loaded code:** segments move as the system reads them in, so the thread finds a procedure's code from the
  segment table each time it stops, never from a remembered address.

### 5. Later

- ~~A Pascal language and grammar in the extension~~ and ~~named variables~~: built in the second round.
- ~~SOS volumes~~, ~~saving a disk~~, ~~paced pasting~~ and ~~Apple III Pascal 1.0~~: built in the third round.
- Writing Pascal volumes, with the media library ([Media.md](Media.md)).
- Apple Pascal 1.3.

## Order

1, 2, 3 for the Apple III, 4 for the Apple III, then 3 and 4 for the Apple II. Each step ends with its tests
passing: the ones that need no files in CI, and the disk tests where the disks are.
