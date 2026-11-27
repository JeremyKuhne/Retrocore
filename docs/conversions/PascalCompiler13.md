# Apple Pascal 1.3's Compiler: conversion log

`src/Retrocore.Pascal/Sdk/Compiler/apple2-1.3/`, shipped as `Sdk/Pascal/Compiler/apple2-1.3/`: `SYSTEM.COMPILER`,
Apple Pascal 1.3's Compiler, in the SDK's [Pascal style](../PascalStyle.md). A main file, `COMPILER.TEXT`, includes
38 others in order, one of them, `SYSGLOBALS.TEXT`, from `src/Retrocore.Pascal/Sdk/System/apple2-1.3/`; the two
procedures in 6502 code are `ASSEMBLED.TEXT`, for Apple's Assembler. One build:

| Build | How | Tests |
| --- | --- | --- |
| `SYSTEM.COMPILER` on Apple Pascal 1.3's APPLE2, 39,936 bytes | compiled with APPLE2's Compiler on a 128K IIe, `ASSEMBLED.TEXT` assembled with its Assembler, the two linked with its Linker | `PascalCompilerSourceTests.CompilerKeepsItsCode` (the code's shape, without disks); `CompilerRebuildsSystemCompiler` (with the disks: the same segments) |

[The folder's README](../../src/Retrocore.Pascal/Sdk/Compiler/apple2-1.3/README.md) has the commands.

## Decisions

- **PC1. The source.** Retrocore's decompilation of `SYSTEM.COMPILER`, named privately after UCSD Pascal II.0's
  Compiler, whose listing (UCSD20) it descends from, with a comment on each declaration. That source compiled back
  to the same segments; this conversion starts from it, by script, and each step keeps the code: the code's shape
  (`PascalCodeShape`: the tokens, each name as the declaration it means, comments left out) is the same before and
  after, and the round trip gives the same segments.
- **PC2. The files.** Every file fits the strictest Editor (16,348 bytes as a disk stores it), at most about 15,000
  so there is room to edit: the main file keeps the header, the options and `PROGRAM`; the constants
  (`CONSTANTS1`, `2`), the types (`TYPES1` to `3`), the system's globals and its procedures' headings
  (`SYSGLOBALS`) and each segment's text follow in the source's order, a file split at a blank line before a
  declaration (`DECLARAT1` to `4`) or, in one long procedure, at a blank line inside it, as an include is text.
  Each file opens with a doc: what it holds, where it is included, its procedures.
- **PC3. The names.** All but the 16 names the code file keeps (`PASCALSYSTEM`, `PASCALCO` and the segments) are
  renamed, 1,367 in all, to PascalCase full words, by a script that checks each against the Compiler's rules before
  anything is written: distinct in their first 8 letters in a scope and the scopes around it, no reserved word's or
  standard identifier's key, every use still finding its declaration, and inside a WITH no field sharing a
  variable's key. One word for each concept ([below](#words)). [PascalCompiler13Renames.md](PascalCompiler13Renames.md)
  lists each.
- **PC4. Historical names.** A doc's `Also:` gives the name a document has for the thing, checked by script: 397
  from UCSD Pascal II.0's listing (UCSD20), where the private source's comment cited II.0 for the name and the
  listing's OCR text has the word, or where a constant's value and its type are both in it; 83 p-code mnemonics from
  Apple's manual (A2POSRM), the ones the SDK's interpreter cites. A name given to more than one declaration, or with
  another declaration's key, goes in a remark instead (177: "UCSD Pascal II.0 calls it LCP (UCSD20)"); one that is a
  reserved word or standard identifier (`EXIT`, `SCAN`) is never an `Also:`, as a use of it would find the
  declaration, which the lint now reports. Citations the listing doesn't confirm are left out.
- **PC5. The docs.** A declaration's comment, above it or after it on its line, is its `(** *)` doc: 1,148 docs. A
  doc after a declaration that declares one name moves above it; a group's comment over constants stays a comment
  (`(* The tokens the scanner finds. *)`). Old names in the prose are the new ones.
- **PC6. Constants.** One to a line, each with its doc, where the decompiler put several on a line. They stay
  `CONST`s (not enumerations), so the code is the same.
- **PC7. Fields.** Records laid over the same words share field names (`DataType`, `Form`, `Size`), as they are views
  of one thing. Two records' fields with one name in nested WITHs would capture each other: the round trip found one
  (`SEGNAME := NAME`, both `Name`), and the segment's field is `NameOfSegment`. The editor's model finds a field
  after a `.` by name, not by the record's type, so hover on a shared field name may show another record's.
- **PC8. OTHERWISE.** 1.3's Compiler reserves `OTHERWISE` (its IDSCAN's table, which has no `SEPARATE`), which 1.1's
  doesn't; the SDK's reserved words are now every version's, as the versions share names.
- **PC9. The assembled procedures.** `ASSEMBLED.TEXT` stays the source of Apple's 1.3 Assembler, which the Linker
  links in. Its `.PROC` and `.FUNC` names are the Pascal names in full (`SCANIDENTIFIER`), of which the Linker
  reads 8 letters; its comments use the new names. The lint checks it as text: lines, name, size.
- **PC10. The system's globals.** `SYSGLOBALS.TEXT` starts the include SYSTEM.PASCAL's source will complete: the
  globals and procedure headings the Compiler uses, as the Compiler declares them. Its types (`SystemHead`,
  `FileReference`) are the including program's for now. A Compiler's source in `Compiler/<machine>-<version>`
  includes from `System/<machine>-<version>` (`PascalIncludeFolders`), in the editor and with `--includes` given
  twice.

## Words

The words the names use for the Compiler's concepts, which the other versions' Compilers share:

| Word | What it is | II.0 |
| --- | --- | --- |
| `Token`, `Operator` | What the scanner found; a multiplicative, additive or relational token's operator | SY, OP |
| `Identifier`, `SymbolEntry` | A pointer to a symbol-table entry; the entry | CTP, IDENTIFIER |
| `Structure`, `TypeEntry` | A pointer to a type's description; the description | STP, STRUCTURE |
| `Class`, `Form` | What an identifier is; what a type is | KLASS, FORM |
| `Operand`, `OperandEntry` | What an expression just compiled is | GATTR, ATTR |
| `Followers`, `Starters` | The tokens that may follow, or start, a construct | FSYS, BEGSYS |
| `CodeCounter`, `DataCounter` | The next byte of code; the next word of data | IC, LC |
| `Emit` | Writes p-code | GEN |
| `Jump`, `JumpEntry` | A label in the code, and its record | LBP, CODELABEL |
| `Level`, `Display` | A routine's nesting level; the open scopes | LEV, DISPLAY |
| `…Code`, `…Key` | A p-code's opcode; a special standard routine's number | PC*, SPKEY |
| `Outer` | An enclosing level's (II.0's "intermediate") | LOD, STR |

Two kinds of name are avoided as a name's start, as their 8 letters are taken: `Statemen…` (the segment STATEMEN)
and `Constant…` (`ConstantClass`); names starting `Procedur`, `Function`, `Interfac` or `Segment` alone are
reserved words' keys.
