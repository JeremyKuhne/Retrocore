# Backlog: p-code disassembly and reassembly

Status: **asked for 2026-11-13**, as the backlog to follow the decompiler ("I want a backlog of p-code
disassembly/reassembly"). Not started. [Pascal.md](../Pascal.md#decompiling) is the guide to what is built: the
decompiler, `--pascal compile` and `--pascal compare`.

A decompiled source compiles to the same code only where the Compiler's patterns cover the code. A p-code source
that assembles back to the same bytes covers everything: every code file, from any compiler or version, the system's
own programs, assembled procedures, and code no Pascal source gives. It is what `--disassemble` already does for
6502 programs (see the retrocore-disassembly skill), for p-code.

## What there is

- `PcodeDisassembler` decodes one procedure at a time from its entry to its exit, with jump table targets and case
  tables, and `--pascal disassemble` lists it with raw offsets. `PascalCodeFile` reads the segment dictionary, the
  procedure dictionaries, assembled procedures' relocation lists and units' interface text.
- `PascalCodeComparison` compares two code files by segment, ignoring the byte the Compiler skips to align an operand.
- `EmulatedPascalCompiler` compiles a source with Apple Pascal 1.1's Compiler on an emulated Apple II, in about four
  seconds, so a source's bytes can be checked against the original's. Only the Apple II's 1.1 Compiler is wired up.

## The pieces

### 1. A p-code source format

A dialect for the native assembler, or a format of its own, that says all of a code file:

- **Segments:** each segment dictionary slot: name, kind, number, machine type, version, and a unit's interface text
  (kept verbatim, as the file holds it, from its block); the intrinsic unit set; and slots that are empty.
- **Procedures:** each procedure's number, lexical level, parameter and data sizes, entry and exit, in the procedure
  dictionary's order, which need not be the order of the code; entries left as 0; procedures a system stub only
  declares.
- **P-code:** mnemonics as `--pascal disassemble` writes them, with labels for jumps; a negative jump names its jump
  table entry, and the jump table is generated or written out; `XJP`'s cases and its own `UJP`; `LDC` and `XJP`'s
  alignment byte written as it is, since it holds stale bytes (see the samples BALANCED and DISKIO).
- **Constants:** `LSA`, `LPA` and `LDC` data, as text where it is printable.
- **Assembled procedures:** 6502 code through the native assembler, with their four relocation lists.
- **Gaps:** bytes no procedure reaches, as data, so every byte of the file is said.

### 2. The disassembler

- Write the whole code file as source, every byte accounted for, as `--disassemble` does for 6502 code, and report
  what was left as data.
- Name procedures and calls: `CXP 0, 19` as `FWRITESTRING`, a unit's procedures from the library's interface text (as
  the decompiler does), `CSP` by name, and a listing's names where a `.LST.TEXT` is at hand (`PascalListing`).
- A hints file, as for 6502 disassembly, for names and comments.

### 3. The assembler

- Assemble the source back to a code file: dictionaries, jump tables, alignment, relocation lists, interface text,
  blocks. Check every sample, the system's programs and the Apple III's disks assemble byte-identically.
- Language server support: hovers for p-codes (the opcode table has a summary for each), go to definition for labels
  and procedures.

### 4. Round trips

- A test, as the 6502 disassembler has, that disassembles and reassembles every code file on the disks at hand and
  compares the bytes.
- Apple III Pascal's code (versions 4 and 6) and Apple Pascal 1.0 and 1.2 (versions 1 and 5): their Compilers differ,
  but their p-code does not, so the same source format serves.

## The decompiler's own next steps

What the decompiler does not decompile yet, found by decompiling every code file on the disks at hand:

- **System programs:** code compiled with `(*$U-*)` (SOROCGOTO, HAZELGOTO, the system's Filer, Editor, Compiler and
  Linker), which reach the system's globals and call its procedures beyond the ones a program can name.
- **`SCAN`, `IDSEARCH` and `TREESEARCH`** (`CSP SCN`, `IDS`, `TRS`), and the system's procedures past `CXP 0, 29`.
- **GOTO into a statement:** a jump the structurer cannot place at the start of a statement (LIBRARY, the Linker), and
  an FJP that leaves its statement (LIBMAP), as a GOTO out of a REPEAT's condition makes.
- **Units:** a program's own units (linked in by the Linker), a unit's variables (`LDE`, `LAE`, `STE`), and units
  other than the library's.
- **Segment procedures** are handled, but no sample has one: check them with a program written to.
- **Other Compilers:** recompiling with Apple Pascal 1.0's and 1.2's Compilers, and Apple III Pascal's on the emulated
  Apple III, so code files they wrote can be checked as 1.1's are.
- **Names from a listing:** where a compiler listing is at hand, the source's own names for procedures and variables.
