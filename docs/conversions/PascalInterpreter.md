# Apple Pascal 1.1's interpreter: conversion log

`src/Retrocore.Pascal/Sdk/Interpreter/1.1/`, shipped as `Sdk/Pascal/Interpreter/1.1/`: `SYSTEM.APPLE`, Apple Pascal
1.1's 6502 interpreter, which runs the p-code in the language card. One root, `SYSTEM.APPLE.asm`, with its linker
configuration, `SYSTEM.APPLE.cfg`, and one build:

| Build | Switches | Digest test |
| --- | --- | --- |
| `SYSTEM.APPLE` on Apple Pascal 1.1's APPLE1 and APPLE3 (the same file), 16,384 bytes | none | `PascalInterpreterSourceTests.InterpreterMatchesItsDigest` |

The file is the language card's 16K in three pieces, which the configuration writes in this order: bank 2 at `$D000`
(the BIOS's drivers), `$E000`-`$FFFF`, and bank 1 at `$D000` (the core). Restart copies itself and Initialize from
`$F275`-`$F674` to `$6800`-`$6BFF`, and Initialize runs there, from `$6827` (`.logicalorg`).

## Where it came from

The source was disassembled and converted to the maintained style privately in 2025: files by subject, `.proc` and
`.scope` structure, named constants, a `;;` block above every definition and `Keeps:` worked out from the code, every
file under `; retrocore: style=strict`. Its names were its own, taken from the code, not from any document. Steps 2 to
5 of [ConvertingSources.md](../ConvertingSources.md) had not been done; this conversion does them. It comes in
unchanged first (`b190b20`), so the bytes prove each step after.

## Sources and citations

1,851 definitions (1,001 labels, 850 equates; 970 in scopes), listed by script from the assembler's debug output with
each one's address and bank. After the conversion, 591 definitions carry 733 old names:

- **WK11** (427): Willi Kusche's 292-page disassembly of 1.1, read from the PDF's text layer, a typed listing with
  addresses and bytes. Kusche had no original listing and merged in what he found; many of his BIOS names are
  Apple's (A2PBIOS). His listing is conditional for five versions of the runtime and lists Initialize where it is
  loaded, so `$F29C`-`$F674` is mapped to `$6827`-`$6BFF`, where it runs (Restart runs where it is loaded; his
  listing's ORIG build, which is 1.1's, jumps there), and its line order gives the bank (bank 2 is its
  second `ORG $D000`).
  - A code label is cited where his address column gives it at the address and bank the build gives the definition.
  - A label with no address of its own takes the next line's only when code follows it directly; a data map's
    (`DSECT`) labels have no address, and are cited only through the instructions that use them.
  - A name for a byte in zero page or memory is cited where his instruction and ours at the same address use it and
    our symbol: his operand's value comes from the instruction's bytes, and our symbol is the one defined in the routine
    that holds the instruction. Where he gives one byte several names, each goes on our alias for that use; where one
    of his names serves several of our aliases, it goes on the byte.
  - Not cited: his generated names, the sequential `INTxx`, `INUxx`, `INVxx`, `INWxx`, `INXxx` and `INZxx`, `A` and an
    address (`A62`, `ABDE0`, `AF21F`, `NBF11`, `S2A90`) and his macros' locals (`CLB`, `SBB`, `BB`, `BL`, `BNB`);
    `P0BASE`; and `ENDCCT` and `DOH1E`'s second definition, which his listing defines twice.
- **A2POSRM** (191): Apple's *Operating System Reference Manual*, from the Internet Archive's OCR text, and the scan's
  pages where the OCR is illegible. The registers (Appendix A), SYSCOM's fields, the mark stack's fields (figure 6),
  the execution errors (XINVNDX ... XS2LONG), the procedure attributes, and the p-codes and standard procedures, each
  checked by its number against `Pcode.asm` and `OpcodeTable` or `CspTable`.
- **A2PBIOS** (152): Barry Haynes's *ATTACH-BIOS Document for Apple II Pascal 1.1* (Apple, January 1980), whose text
  layer is clean. Its excerpts of Apple's BIOS source are matched to the build instruction for instruction (SAVERET is
  `BiosCall`, UDRWIS `AttachedDriver`, CONCK `ConsoleCheck`), and its equates by address (WPTR `$BF19` is
  `TypeAheadIn`). A name it gives only in prose or a comment is not cited.
- **UCSD20** (154): UCSD's II.0 system source listings. SYSCOMREC's offsets are computed from its declaration,
  allocating each identifier list backward as its own comment says; the Compiler's p-code and standard-procedure
  comments by their numbers; the mark stack (MSCW), segment description and directory entry records by their fields.
- **UCSD20IO** (31): UCSD's II.0 I/O System: the unit numbers, the unit calls and the BIOS entry points, matched by
  function (Apple's printer read does nothing, and it puts DISKWRITE before DISKREAD).

Not cited: SofTech's *Internal Architecture Guide* (1981), which describes Version IV, a different p-machine; Apple's
1.2 *Device and Interrupt Support Tools Manual* (PI8); and the low-confidence matches below. The documents stay out of
the repository; only names and facts come in.

Where the documents disagree with 1.1: SYSCOM is II.0's up to its segment table, which Apple makes 32 entries long
where II.0's has 16 (288 bytes against 192); Apple's mark stack frame adds MSSP at offset 10, where II.0 has its
locals; II.0 writes LCA, AND, MOD and NOT for LSA, LAND, MODI and LNOT; II.0 has one remote unit (8) and nothing at 3 or
7, where Apple has graphics at 3 and splits remote into 7 and 8. The manual misprints five standard procedures'
numbers (TNC 22, RND 23, MRK 31, RLS 32 and POT 35, where `CspTable`, `Pcode.asm` and II.0 agree on 23, 24, 32, 33 and
36), GRTREAL as GTRREAL, and BOMBIPC as BOMIPC. The standard procedures are cited at their right numbers; the manual's
misprinted names, GTRREAL and BOMIPC, are cited as it prints them, beside BOMBIPC from UCSD20.

## Decisions

Settled by the owner on the rename table's review.

- PI1. Kusche's disassembly is cited (WK11), as IBSM is for Integer BASIC; his generated names are not.
- PI2. The p-code handlers are in a `Pcodes` scope, in pieces through the files (`.scope Pcodes continued`, each
  with a `;` line saying what it holds), as BASIC's `Statements` are, named in full words for what the p-code does:
  `Pcodes::AddIntegers` (ADI), `Pcodes::ShortLoadLocal` (SLDL), `Pcodes::LogicalAnd` (LAND). The p-code's mnemonic is
  the handler's old name, and the assembler takes it beside `Pcode.asm`'s macro of the same name. FJP and UJP keep
  their `Jump` scope, which they share (`Jump::IfFalse`, `Jump::Always`).
- PI3. The standard procedures are in a `StandardProcedures` scope the same way: `StandardProcedures::UnitRead`
  (UREAD), `StandardProcedures::MoveLeftOrRight` (MVL and MVR, one routine for both).
- PI4. The p-machine's registers are named for what they point to: BASE `GlobalFrame`, MP `LocalFrame`, JTAB
  `JumpTable`, SEG `ProcedureDictionary`, IPC `InstructionPointer` (`ProgramCounter` is `IIeEquates.asm`'s), NP
  `HeapTop`, KP `ProgramStackTop`. The debugger's frame still shows them by UCSD's names.
- PI5. SYSCOM is a `.struct SyscomRecord`, all 288 bytes, and the words the interpreter reaches by address are a
  `Syscom` scope built from its offsets (`Syscom::IoResult = Start + SyscomRecord::IO_RESULT`), as DOS's X3. The
  old names go on the words; the fields reached only by offset, through `SyscomPointer` (the console's keys), and
  those nothing uses carry their own. JTAB and SEG are the registers' old names, so SYSCOM's copies give them in prose;
  so does `SyscomPointer`, which A2PBIOS calls SYSCOM.
- PI6. The mark stack frame is a `.struct MarkStack`, whose fields carry MSSTAT ... MSSP; MSCW, the record's own
  name, is in prose (an `Also:` on a named struct names nothing).
- PI7. The execution errors' numbers are the `ERROR_*` constants, which carry XINVNDX ... XS2LONG; the reporting
  entries carry Kusche's labels (ERR1, OOMERR ...), and `Unimplemented` the p-codes it runs for, EFJ and NFJ. SYSTEM.PASCAL's handler, EXECERROR, is named in prose on
  the call to it.
- PI8. Only 1.1's documents and those of the system it descends from are cited. 1.2's device manual is added if 1.2's
  or 1.3's interpreter joins the SDK. The private conversion's names are not historical: no `Also:` keeps them.
- PI9. The source is in `src/Retrocore.Pascal/Sdk/Interpreter/1.1`, its file names as they were; the private
  repository's scripts, traces and `check.sh` stay there, and the tests replace `check.sh`.
- PI10. Verified by the digest, the disk and the lint; the contract run is described under *Verification*.

## Settled during the conversion

- **Shadowing.** A scoped name must not shadow a top-level one, so: the standard procedure RSEG is
  `StandardProcedures::ReleaseSegment` and the routine it calls, which gives back one use of a segment, is
  `ReleaseSegmentUse`; MPR is `Pcodes::MultiplyReals` and the helper it and SQR call is `RealMath::MultiplyOperands`;
  SYSCOM's copies of the registers are `Syscom::SavedGlobalFrame` ... `Syscom::SavedProcedureDictionary`, and its
  MEMTOP is `Syscom::StackTop`, beside the top-level `MemoryTop` it holds. The digest caught the one place this went
  wrong: `StandardProcedures::ReleaseSegment` called itself until the helper was renamed.
- **Layouts.** A segment table entry is a `.struct SegmentEntry` (CODEUNIT, DISKADDR, CODELENG; CODEDESC, UCSD's
  name for the last two together, in prose), and a directory entry a `.struct DirectoryEntry` (DFIRSTBLK, DTID and
  DVID; DIRENTRY in prose). Initialize's `SEGMENT_TABLE_BLOCK` was a second definition of a segment entry's block, and
  is `SegmentEntry::BLOCK`. A segment dictionary entry stays a size, `DICTIONARY_ENTRY_SIZE` (SEGDESC; DISKINFO, the array, in prose).
- **SyscomExtra** was described as 32 bytes after SYSCOM. With SYSCOM 288 bytes long, they are its own last 32, which
  Initialize clears after the first 256: `Syscom::Rest`, and `SYSCOM_EXTRA_SIZE` is `.sizeof(SyscomRecord) - 256`.
- **Clashes inside the assembly** go in prose: IDS on `IdSearch` (the standard procedure's), Kusche's NOTK on
  `WordsN` (A2PBIOS's label in `ConsoleCheck`), and A2PBIOS's CH, BAS2L and BAS2H, the Monitor's names in
  `IIeEquates.asm`. A2PBIOS's TEMP2 is `CardPointer`'s high byte, in prose. Old names on the shared `IIeEquates.asm`
  (Kusche's KBD, LCBNK1 ...) are not added there: those switches carry Apple's own documents' names.
- **The review** found names placed by a local's bare name on another routine's local of the same name (HCKSUM,
  FPRETA, NB8, PCDSIZ, TJTPTR, HSLOT1, SEGNO), and names a pattern for generated ones had dropped (BUFF6B, BUFF2B,
  FREAD1, READAF, READDF), and Restart's MINITC, lost to Initialize's mapping. Each was placed again by its address
  or the instructions that use it. UCSD's MAXSEG is the last segment, 15, not the count, and Apple's DISKINFO the dictionary's entries, not an entry's size: both are in prose. Apple's
  DISKNUM and READTBL start at unit 1, a word above ours, and SLTTYPS at a slot 0, a byte below ours; they stay on
  our tables, as the rename table's review settled, with the difference in prose.
- **Locals that a document names** got a `;;` summary to carry the `Also:`; where a step heading said what happens
  at the label, the summary replaces it.
- **The lint** bounded a routine by the next documented routine above its address, so in banked code another bank's
  routine could fall between a routine and its own local (`CardInit`, in bank 2, between bank 1's `LoadStringAddress`
  and its `SkipCharacters`). A `.proc`'s own local is now inside it by scope
  (`DocumentationTests.ProcEntriesAreItsLocals`).
- **Old names in prose**, by script: what remains is the BIOS and SYSCOM as concepts, Pascal's own procedure names
  (UNITREAD, NEW, MARK), p-code mnemonics, the names of the documents' records (MISCINFO), and the sentences that give
  an old name as history.

## Found in the conversion

The private conversion found these, each described where it happens:

- `ConsoleStatus` reports `TypeAheadIn - TypeAheadOut` without allowing for wrap-around: the count is wrong once
  the buffer has wrapped (it is still nonzero exactly when keys are waiting).
- Letters with no reserved words make `IdSearch` compare 256 entries from `NoWords`, out of step with the real
  entries and past the end of bank 2.
- FLO and FLT of -32768 never return: `PopIntegerAsReal` shifts the magnitude's top bit out before it tests.
- POT checks its power with a signed compare, so 167-255 pass as well as 0-38.
- Initialize gives DiskInit the unit number, 4, rather than unit 4's drive, so slot 4 is the one checked; the result
  is not used.
- UNITCLEAR of unit 3 resets the graphics screen but returns I/O result 9; UNITCLEAR and UNITSTATUS treat unit 7 as
  unit 8, and UNITREAD and UNITWRITE do not.
- A parallel printer card must be in slot 1.
- `$6AF2`-`$6BFF` (inside Initialize's copy) is never run.

The checks against the documents found:

- `CopiedTable` (`$BF56`-`$BF7F`), which the private notes left open, fills the area A2PBIOS gives to "FORTRAN
  PROTECTION"; what its bytes are for is still not known.
- RANDL and RANDH (`PollCount`) are the seed of the random-number function, which code outside SYSTEM.APPLE reads.

## Verification

- **Bytes:** `PascalInterpreterSourceTests.InterpreterMatchesItsDigest` (SHA-256 of the 16K, no disk needed) after
  every step, and `InterpreterMatchesTheDisk` against `SYSTEM.APPLE` on `UCSD Pascal 1.1_1.dsk` and `1.1_3.dsk` in
  `RETROCORE_APPLE2_PASCAL_DISKS` (Inconclusive without them).
- **Lint:** `InterpreterDocumentationIsClean`, with the IIe's SDK modules beside it for the links `IIeEquates.asm`
  makes, and `EveryRepositorySourceIsCleanInTheEditor`.
- **Contracts:** not run. The debug host finds the interpreter in the language card by its fetch loop, and loads none
  of this source's symbols, so its `Keeps:` cannot be checked in a debugger run yet; that needs the host to load the
  source as a banked module. This conversion changed no contract: the `Keeps:` are the private conversion's, worked out
  from the code.
