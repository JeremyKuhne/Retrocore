# Backlog: Apple Pascal

Status: **asked for 2026-11-13** ("implement Apple III Pascal support", designed with Apple II Pascal in mind). Plan
first, then code files and p-code, then the debugger's p-machine, then booting and running both.

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

- A Pascal language and grammar for `.TEXT` sources in the extension.
- Named variables, from the compiler's listing, which gives each declaration's offset.
- Writing Pascal volumes and SOS volumes, with the media library ([Media.md](Media.md)).
- Apple Pascal 1.3, and Apple III Pascal 1.0.

## Order

1, 2, 3 for the Apple III, 4 for the Apple III, then 3 and 4 for the Apple II. Each step ends with its tests
passing: the ones that need no files in CI, and the disk tests where the disks are.
