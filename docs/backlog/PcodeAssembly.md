# Backlog: p-code disassembly and reassembly

Status: **asked for 2026-11-13**, as the backlog to follow the decompiler ("I want a backlog of p-code
disassembly/reassembly"). **Built** the same day: `--pascal disassemble code output.asm` and `--pascal assemble`
([Pascal.md](../Pascal.md#p-code-source)); see Built. [Pascal.md](../Pascal.md#decompiling) is the guide to what is built: the
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

## Decided: p-code as macros (2026-11-13)

P-code is written with the native assembler's macros rather than as a CPU of its own:
[`Pcode.asm`](../../src/Retrocore.Pascal/Pcode.asm) defines one macro for each p-code under `.cpu Pcode`, and a
code file's source includes it and lays out the whole file itself from address 0: the segment dictionary in block 0
(`.word Segment1 / 512, Segment1End - Segment1`), each segment from a block boundary, `.scope`s for segments and
procedures, jumps to labels, jump tables and the procedure dictionary as self-relative `.word * - label`s, and the
attributes. `Pcode` is a macro-only CPU: the macros defined under its `.cpu` expand only under it, so p-code's `LDA`,
`INC`, `NOP` and `STP` leave an assembled procedure's 6502 code, under `.cpu Mos6502`, alone
([NativeAssembly.md](../NativeAssembly.md#macros)); under `.cpu Pcode` an instruction no macro writes is an error.

**The prototype** (a script, not in the repository) wrote every code file on the Apple II and Apple III disks at hand
as such a source: 63 of 69 assemble back byte-identically, among them every Compiler, Editor, Filer, Linker and
Assembler, both machines' libraries, and the samples. Of the other six, three are the system itself
(`SYSTEM.PASCAL`, twice, and `128K.PASCAL`), whose stub segments declare procedures that are elsewhere, and one is
Apple Pascal 1.2's `SYSTEM.EDITOR`, a byte off in the code the Asimov image has damaged. `PcodeAssemblyTests`
assembles P1's whole code file this way.

**Found:**

- `.if` is the preprocessor's, before addresses are known: a macro cannot test `*`. The byte `LDC` and `XJP` skip to
  reach a word is `.align 2, pad`, with the byte the code file has (the Compiler leaves a stale one there).
- In a `.byte` list, `*` is the address of that byte, so a jump's operand is `target - (* + 1)`.
- A jump back, and any jump too far for a byte, goes through the procedure's jump table: `UJPT entry` names the
  table's word, and `Attributes`, the label each procedure scope has, resolves the offset.
- `XJP`'s own `UJP` is written as its own line, with a label, because a case table's missing entries point at it.
- `.word` takes 0-$FFFF, so negative words are written `& $FFFF`; and a label cannot be defined qualified
  (`::Name:`), so each segment's start and end labels sit just outside its scope.
- `--assemble` writes the image to `$FFFF`; `--pascal assemble` should write only the code file's bytes.
- An error inside a macro names the macro's line, not the line that called it, which makes a bad p-code hard to find.

## Built

- `PcodeSourceWriter` writes a code file as source: p-code with `Pcode.asm`'s macros, assembled procedures as 6502
  code with their relocated operands and relocation lists by label, and data where it cannot read a segment.
  `--pascal disassemble code output.asm` writes it and assembles it back to check; `--pascal assemble` writes a code
  file from it, to the last byte the source writes.
- `Pcode.asm` ships as `Sdk/Pascal/Pcode.asm`; the CLI and the language server search the host's SDK folder for
  `.include <...>`.
- **Checked:** all 69 code files on the Apple Pascal 1.0, 1.1 and 1.2 and Apple III Pascal 1.1 and 1.2 disks at hand
  assemble back byte-identically; the system's stub segments (SYSTEM.PASCAL's and the `PASCALSY` stubs at the head of
  Apple III Pascal's Editor and Linker) are written as data. `PcodeAssemblyTests`.
- **Found:** a relocated operand can point inside a data word (FORMATTER's RWTS call reads its IOB pointer's high
  byte), so such a target is named from the word (`L0598 + 1`); and a target inside an instruction, as in the
  damaged code of Apple Pascal 1.2's `SYSTEM.EDITOR`, is too, in parentheses where it is subtracted.
- **Names** (the same day, "work on what is still bare"): the system's and PASCALIO's procedures by `Pcode.asm`'s
  `PASCALSY` and `PASCALIO` scopes; units' procedures from the library, with a scope the source defines for each
  unit; a call's callee and a real constant's value beside it; a listing's segment, procedure and variable names and
  its source lines; and a hints file of names and comments keyed as `pascal` breakpoints are
  ([Pascal.md](../Pascal.md#names)). `--pascal compile` writes the listing a source asks for.
- **Found:** a Pascal file's name is at most 15 letters: the Compiler writes no listing to `HILBERT.LST.TEXT`, and
  APPLE1 has room for a listing only once the Editor is off it. `PascalListing` numbered variables backwards: the
  Compiler allocates an identifier list from its last name, and parameters in stack order, so in `VAR A, B: INTEGER`
  B is the lower word; the debugger's variable names were wrong the same way.
- **Not done:** a macro's errors at the line that called it; writing to a disk image; a unit's own variables
  (`LDE`) by name.

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
- ~~Name procedures and calls~~ and ~~a hints file~~: done (see Built).

### 3. The assembler

- `--pascal assemble source code`: the native assembler with `Pcode.asm`, from address 0, writing the bytes to the
  last block (or to a disk image and a file's name). Done but for the command: the macros and `.cpu Pcode`.
- Report a macro's errors at the line that called it.
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
