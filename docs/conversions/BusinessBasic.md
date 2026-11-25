# Business BASIC: conversion log

`src/Retrocore.Machines.Apple3/Roms/BusinessBasic/`: Apple's Business BASIC for the Apple III, the `SOS.INTERP` of the
Business BASIC 1.23 disk, in 33 files that follow Apple's 1.3 source and its file names. It is the first Apple III
source converted to the maintained style. One root, `BusinessBasic.asm`, and four builds:

| Build | Switches | Digest test (BusinessBasicSourceTests) |
| --- | --- | --- |
| Business BASIC 1.23, byte for byte with the disk's `SOS.INTERP` | `VERSION` = 123, the default | `InterpreterMatchesItsDigest` (and `InterpreterMatchesTheDisk` with the disk) |
| Apple's 1.3 listing as printed (no binary is known) | `VERSION` = 130 | `ListingMatchesItsDigest` |
| 1.3's run-time variant, the listing's `BASIC.RT` | `VERSION` = 130, `RUNTIME` = 1 | `RunTimeBuildMatchesItsDigest` (new with this conversion) |
| 1.3's debugger variant, the listing's `BASIC.D`, loading at $3A00 | `VERSION` = 130, `DEBUG` = 1 | `DebugBuildMatchesItsDigest` (new with this conversion) |

The root asserts these four and no other: `VERSION` is 123 or 130, `DEBUG` and `RUNTIME` are 0 or 1, at most one of
them is set, and either needs `VERSION` = 130. The two new digests were computed from the unconverted source before any
name changed. `VERSION`, `DEBUG` and `RUNTIME` keep their names: `DEBUG` and `RUNTIME` are Apple's (the listing's
`BASIC.TEXT`, `BASIC.RT.TEXT` and `BASIC.D.TEXT` set them), and `VERSION` is the SDK's.

The owner's decision for this pass: Business BASIC is converted as its own source. Its float package is not folded into
the shared Microsoft modules ([Basic.md](Basic.md)); routines that do the same job as the converted AppleSoft and
Microsoft modules' take the same current names, and what could later be shared is listed
[below](#same-job-same-name-what-could-be-shared).

## Sources and citations

- **BB13**: Apple /// Business BASIC 1.3 Source Code Listing, Apple's source files as David Craig reformatted and
  merged them into one listing (1997), from apple3.org. The SDK's source was typed from it, so its names were Apple's.
  Checked by script against the PDF's text: of the 2,313 names the source defined, every one but the SDK's `VERSION`
  is defined at column 0 of the listing (a label, with or without a colon, or an `EQU`), and in the same file. Every
  renamed definition cites BB13 for its old name: 2,312 citations. 23 of them are 1.3-only names (the program
  selector's), which the 1.23 build doesn't assemble; they cite BB13 where they are defined.
- The listing's text stays out of the repository (ConvertingSources.md, step 2); only names and facts came from it.
- No Microsoft or AppleSoft document is cited: Business BASIC's code reached Apple through AppleSoft, but the names
  were checked only against Apple's own listing. Where a routine has a Microsoft lineage, the same current name is the
  bridge ([Same job, same name](#same-job-same-name-what-could-be-shared)).

## How it was done

The inventory (2,317 definitions, 2,313 names, by script), then the citation check above. The source was split by
subject into nine groups of files, each converted by its own agent in its own copy, with one shared brief: the rules
of ConvertingSources.md, the scopes several files share, the conventions below, and "same job, same name" checked by
`grep` against the converted AppleSoft and Microsoft modules' `Also:` names. Old names resolve through `Also:`
anywhere in an assembly, so each group referred to the others' definitions by their old names meanwhile, and every
build stayed byte-identical after every step. Integration then merged the groups' constants, settled the names the
groups clashed on, rewrote every cross-file reference and link to the current name by script, opened each shared
scope in its first file (removing the shim), and rewrapped the comments.

## Decisions

The cross-cutting ones were set in the brief, following the precedents (Monitor.md, Basic.md, IntegerBasic.md); the
rest were settled at integration. Each follows a rule already in ConvertingSources.md unless it says otherwise.

- BB1. Every name is renamed to the style, with Apple's name in `Also:` (BB13). No name is dropped: Apple's numbered
  labels (`FADD5`, `NORM3`) are documented names, so each is a well-named local with its `Also:`. Two old names on one
  byte stay two definitions where they do different jobs (scoped aliases), and one where they are the same thing
  (`INDEX` and `INDEX1` are `Pointer1`).
- BB2. Same job, same name: a routine or location that does what a converted AppleSoft or Microsoft definition does
  takes its current name and scope (FADDH `Float::AddHalf`, PTRGET `FindVariable`, NEWSTT `NextStatement`, GONE
  `ExecuteStatement`, CHRGET `GetNextCharacter`, TXTTAB `ProgramStart`, FAC `Fac`). Where Business BASIC changed the
  job (banks, long integers, five-byte constants), it has its own name. The table's "AppleSoft name" column marks the
  669 rows that share a name.
- BB3. Scopes. Shared, in pieces through the files in Apple's order, each opened in its first file with its `;;`
  block: `Statements`, `Functions`, `Operators`, `Float`, `Strings`, `Variables`. Subject scopes: `Tokenizer`,
  `Console`, `Handlers` (ON ERR, ON KBD, ON EOF#), `SosCalls` (the parameter lists), `ProgramPrefix` (1.3 only),
  `Lister`, `Output`, `Memory` (banked-pointer arithmetic), `Random` (RND's generator), `LongInteger`, `Hexadecimal`,
  `Modules` (invokable modules), `Segments` (SOS memory segments), `PrintUsing`, `Files`, `Directory` (CATALOG). Top
  level: the shared page zero and tables, the error entries, and the widely called entries AppleSoft has at top level
  (`GetNextCharacter`, `EvaluateExpression`, `FindVariable`, `ReportError`, `CommandLoop`, `ColdStart` ...).
- BB4. Statements, functions and operators are named for their keywords split at words, as AppleSoft's are
  (`Statements::GoSub`, `Statements::OnErr`, `Functions::Conv`). Where the keyword's name would hide a scope or
  another statement it has a word more: `READ#` is `Statements::ReadFile` (`READ` is `Statements::Read`), `OUTPUT#`
  `Statements::OutputFile` (inside `Statements`, `Output` would hide the `Output` scope), and `PRINT USING` is
  `PrintUsing::Statement`. `DEL` (token $DA, deleting program lines) is `Statements::Del`, and `DELETE` (token $C6,
  deleting a file) is `Statements::Delete`.
- BB5. Locations PascalCase, values UPPER_SNAKE. A pointer `Name`'s X-byte is `NameXByte` (TXTTABB is
  `ProgramStartXByte`), and the X-byte offset is `X_BYTE_OFFSET` (SYSPAG). `Arg` and `ArgExponent` are two labels, as
  `Fac` and `FacExponent` are, so prose about the second accumulator reads right.
- BB6. Shared values are prefixed constants, in the equates' files (B3Invok.asm, ZpgEqus.asm, B3Resvb.asm): `SOS_*`
  (call numbers), `SOS_ERROR_*`, `FILE_TYPE_*`, `TOKEN_*` (one prefix for both keyword tables, so `TOKEN_TAB` and
  `TOKEN_END` are both $80, in different tables), `ERROR_*` (BASIC's error numbers), `VALUE_TYPE_*` (`ValueType`'s
  values, one set where four groups had each defined some), `STRING_TYPE_*`, `CHARACTER_*`. Constants one subject uses
  are in its scope.
- BB7. Layouts are structs (37), among them `FileControlBlock`, `InterpreterHeader`, the SOS calls' parameter lists in
  `SosCalls`, the FOR entry and the linker's records; the bytes that hold one are tied to it by `.assert`s.
- BB8. Fall-throughs into another file are asserted: `TakeOperator` into `Operators::Apply` (B3InpuF.asm into
  B3EvalG.asm), `Variables::CreateArray` into `Variables::InitializeArray` (B3DimnH.asm into B3UdefI.asm). QINT is one
  `.proc`, `Float::ToLongInteger`, across B3MathL.asm and B3FinpM.asm, as DOS's RWTS spans its two files.
- BB9. A scoped name that hid a top-level one was renamed at integration (ConvertingSources.md's shadowing rule), for
  example `PrintUsing::FormatString` (not `PrintString`), `Hexadecimal::ReportIllegalQuantity`, `SavedFileType`
  (TYPSAV, beside `SosCalls::FileType`), `OutputFileNumber` (FILNO); and a constant defined twice became one.
- BB10. EDASM's `DCI` directive is the macro `TextEndingHigh`, in the root; a macro carries no `Also:`, so its
  comment names DCI.
- BB11. The debug host looks Business BASIC's addresses up through `SymbolsWithHistoricalNames`, by Apple's names
  (MAIN, NEWSTT, GONE, ERROR, RUN, CONT, STOP2, ENDCON, ERRTAB, BASICBNK), and the dialect tests the tables and tokens
  (RESLST, RESL2, OPTAB, REMTK ...), so each stays in its definition's `Also:`; `BASICEND`, which the digest tests use,
  too. `tools/Test-Apple3Dap.mjs` sets its breakpoint on `.proc ExecuteStatement`. C# comments and the docs name the
  current definitions, with Apple's names in parentheses where a reader holding the listing needs them.

## Same job, same name: what could be shared

Candidates for folding into the shared Microsoft modules later, as the float package's group found them by reading
the code (each needs the build switches the modules' README describes, and a per-module comparison):

- **Byte for byte the same code, labels aside:** `Float::AddHalf`, the adder (FSUBT, FADDT, FADD1/FADD4/SUBIT, FADFLT,
  FADD2), `Float::Normalize`, the zeroing entries, the rounding and complement routines, the right shifter's body,
  `Float::MultiplyArg`'s loop, `Float::MultiplyByTen` and `DivideByTen`, the moves between Fac and Arg,
  `SIGN`/`SGN`/`ABS`/`INT`, the 16-bit floats, and the constants (one, LOG's, the square roots, -0.5, ten, a half); in
  the transcendentals, EXP, SIN, COS, ATN, the polynomial evaluators and their tables.
- **The same job, different code:** the routines that load and store with a bank (CONUPK, MOVFM, MOVMF and the five-byte
  forms), FADDC's return, the right shifter's entry (`Float::ShiftRight` here; Microsoft's `ShiftRight` is this source's
  `Float::ShiftRightByCount`, so sharing needs one name for both), QINT, the comparison (by subtraction here), FIN and
  FOUT (six digits, `e` accepted, Business BASIC's constants), FPWRT (`Float::RaiseArg`, saving ARG around the
  comparison), TAN (banks), POLY1 (the table's X-byte), the division (FDIVT's zero test and DIVNRM's rotates) and MULSHF
  (it clears the shift fill).
- **Business BASIC's own:** RND (a Lehmer generator on long integers), long integers, PRINT USING, files, modules and
  the banked memory.

## Found in the conversion

Documented in the code, not changed (the bytes stay). Found by reading; none was run.

- **Arithmetic:** `CONV&` of a real of 2^56 or more is wrong (it loads from Arg without setting Y); negating -(2^63)
  gives -(2^63) with no error; `RND(-2147483647)` sets the seed to 0, after which every `RND` is 0; QINT doesn't check
  its range (an exponent of $A0 or more gives a wrong result); `STR$` doesn't round to a variable's precision as `PRINT`
  does, so the two can show different digits; long-integer comparison is wrong when the top bytes differ by $80 or more
  (known).
- **The evaluator and memory:** backing the text pointer up from the first byte of a 32K window leaves page $01
  (`BackUpTextPointer` fixes the pointer the wrong way); the long-integer `NOT` test calls a routine with X unset, and
  works while X's bit 7 is clear; `ReadLineNumber`'s 64000 check misses $BA in the high byte (Microsoft's quirk).
- **Strings and modules:** `INSTR` with a start of 0 finds nothing; more than eight `@` arguments to `PERFORM` write
  past their buffer; the routine table's caller doubles the number with ASL, so numbers 128 and up call the routine
  128 below; a failed `INVOKE` leaves the released segment's number, so `PERFORM` and `EXFN.` search released memory;
  a module with no procedures goes round 256 times.
- **PRINT USING:** an empty literal prints 256 bytes; engineering notation fills one place (known), and leaves a zero
  byte in a floating sign's place for a positive number without `+`; with a fixed sign and `$` both, the digit
  overwrites the `$`; two routines read up to two places past the 20 digits.
- **Files:** only closing a file clears its changed flag, so after the first `WRITE#` every move to another record
  writes the record in hand back; `REC` on a text file divides by the record length last used.

Comments found wrong and fixed include TEMPF1 and TEMPF2's ("the fifth byte"; they are five-byte temporaries), XBLKS,
BITS, the WINDOW bytes, RNFLG, CMDFLG and SOS call $65's in the equates, and others each group lists in its part of the
work. The closing review found more that were wrong on main already, among them `DEF FN`'s argument (a typed argument is
a syntax error, so the overwrite docs/BusinessBasic.md described can't happen), `PRINT USING`'s separators, `OPEN`'s
access codes, SOS's error flags (negative and zero, not carry), and the sine and EXP constants' decimal values (now
Microsoft's correct ones, as the shared modules give them).

## Verification

- **Bytes:** every build after every step, by script, compared with the unconverted source's whole output; and the
  four digest tests.
- **Lint:** `; retrocore: style=strict` on all 33 files; `InterpreterDocumentationIsClean`, which lints the default
  build, passes, and it was also run with the root's defaults set to each of the three 1.3 builds, clean in each
  (the lint reads one build, so links in 1.3-only code were checked that way);
  `EveryRepositorySourceIsCleanInTheEditor` and `SdkDocumentationIsClean`.
- **Names:** Business BASIC joins `ConvertedSourcesUseCurrentNames`, which passes: code in the converted files uses
  current names. The debug host and `BusinessBasicDialectTests` look names up through `SymbolsWithHistoricalNames`;
  the DAP script, the C# comments and the docs name the current definitions.
- **Contracts:** one debugger run of Business BASIC 1.23 (from apple3.org's disk image, kept out of the repository)
  with contract checking on, on the final code. A program typed at the prompt exercised arithmetic and the
  transcendental functions, long integers (`*`, `DIV`, `MOD`, `CONV$`), the string functions and `SUB$`, `HEX$`,
  `PRINT USING`, a text file (`CREATE`, `PRINT#`, `INPUT#`), a data file (`WRITE#`, `READ#`), `UNLOCK` and `DELETE`,
  `FRE`, and the disk's `VOLUMES.INV` module (`INVOKE`, `PERFORM`). A false `Keeps: X` added to `FindVariable` in a
  copy of the source, as a control, was reported every time it returned (164 times), and nothing else was: none of
  the source's 93 `Keeps:` contracts was broken on the paths the run took. Not exercised: the 1.3, run-time and
  debugger builds (no binary or disk exists for them), `CHAIN`, `EXEC`, `OUTPUT#`, `CATALOG`'s other stages, events
  (`ON KBD`, `ON EOF#`), `ON ERR`, the module routine table's entries, and every error path but the ones the run hit.
- **With the disk:** `InterpreterMatchesTheDisk` passes (the 1.23 build is byte for byte the disk's `SOS.INTERP`),
  and `tools/Test-Apple3Dap.mjs` (a breakpoint on `ExecuteStatement` as `HELLO` runs) and
  `tools/Test-BusinessBasicDap.mjs` pass. The tests that also need MAME's Apple III ROM set were skipped.

## Open questions

For the owner; each is as recommended unless the owner decides otherwise.

- BBQ1. `ON ERR` is `Statements::OnErr`, by the keyword's words, as AppleSoft's is; `OnError` reads better.
- BBQ2. `PROGPREFIX$`'s routines are `ProgPrefix`, by the keyword; `ProgramPrefix` (the scope's name) reads better.
- BBQ3. OLDOV and SIZE take AppleSoft's names, `FunctionJumpHigh` and `CollectorOffset`, though nothing here uses SIZE;
  the float code names its own use of OLDOV's byte, the unshifted operand's rounding byte, `Float::UnshiftedExtension`,
  as the shared modules do.
- BBQ4. `STKEND` is `STACK_END`, though it is a stack pointer's value, not an address.
- BBQ5. `CHARACTER_SCREEN_ON` (15) comes from the source's comments, not checked against SOS's console documentation.
- BBQ6. `Modules::OtherPointer` (POINT2) serves as a dictionary entry, a record and a value; a better name is welcome.
- BBQ7. The long-integer operators are `LongInteger::Add` ... `LongInteger::Compare`, called after the type check,
  rather than in `Operators`.

## Rename table

One row per old name, by file group in Apple's order, in source order within each: 2,312 rows. **Old** is Apple's
name (BB13), **New** the definition's full path, **Kind** what it is, **Builds** the builds that define it ("1.3" is the
three 1.3 builds), **AppleSoft name** the converted AppleSoft or Microsoft name where the job is the same (BB2), and
**Reason** one line from the code.

### B3Invok.asm, ZpgEqus.asm, B3Resvb.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| SCRT | SOS_CREATE | constant | all |  | SOS's `CREATE`: makes a file or directory. |
| SDST | SOS_DESTROY | constant | all |  | SOS's `DESTROY`: deletes a file. |
| SRNM | SOS_RENAME | constant | all |  | SOS's `RENAME`: renames a file. |
| SSFI | SOS_SET_FILE_INFO | constant | all |  | SOS's `SET_FILE_INFO`: sets a file's type, access and dates. |
| SGFI | SOS_GET_FILE_INFO | constant | all |  | SOS's `GET_FILE_INFO`: reads a file's type, access, size and dates. |
| SVLM | SOS_VOLUME | constant | all |  | SOS's `VOLUME`: reads the name and size of the volume in a device. |
| SETPREF | SOS_SET_PREFIX | constant | all |  | SOS's `SET_PREFIX`: sets the prefix that partial pathnames start from. |
| GETPREF | SOS_GET_PREFIX | constant | all |  | SOS's `GET_PREFIX`: reads the prefix. |
| SOPN | SOS_OPEN | constant | all |  | SOS's `OPEN`: opens a file and gives its reference number. |
| SNWL | SOS_NEWLINE | constant | all |  | SOS's `NEWLINE`: makes a `READ` stop at a character, such as a carriage return. |
| SRED | SOS_READ | constant | all |  | SOS's `READ`. |
| SWRT | SOS_WRITE | constant | all |  | SOS's `WRITE`. |
| SCLS | SOS_CLOSE | constant | all |  | SOS's `CLOSE`. |
| SFLS | SOS_FLUSH | constant | all |  | SOS's `FLUSH`: writes a file's buffer out. |
| SSTM | SOS_SET_MARK | constant | all |  | SOS's `SET_MARK`: moves to a place in a file. |
| SGTM | SOS_GET_MARK | constant | all |  | SOS's `GET_MARK`: reads the place in a file. |
| SSTE | SOS_SET_EOF | constant | all |  | SOS's `SET_EOF`: sets a file's length. |
| SGTE | SOS_GET_EOF | constant | all |  | SOS's `GET_EOF`: reads a file's length. |
| SSLVL | SOS_SET_LEVEL | constant | all |  | SOS's `SET_LEVEL`: sets the file level, which `CLOSE` and `FLUSH` of reference number 0 go by. |
| SGLVL | SOS_GET_LEVEL | constant | all |  | SOS's `GET_LEVEL`: reads the file level. |
| SDSTAT | SOS_DEVICE_STATUS | constant | all |  | SOS's `D_STATUS`: reads a device's status. |
| SDCNT | SOS_DEVICE_CONTROL | constant | all |  | SOS's `D_CONTROL`: sends a device a control request. |
| SDGDN | SOS_GET_DEVICE_NUMBER | constant | all |  | SOS's `GET_DEV_NUM`: gives a device's number from its name. |
| MREQ | SOS_REQUEST_SEGMENT | constant | all |  | SOS's `REQUEST_SEG`: takes a segment of memory. |
| MFND | SOS_FIND_SEGMENT | constant | all |  | SOS's `FIND_SEG`: finds a free segment of memory of a size, and takes it. |
| MCHG | SOS_CHANGE_SEGMENT | constant | all |  | SOS's `CHANGE_SEG`: makes a segment longer or shorter. |
| MRLS | SOS_RELEASE_SEGMENT | constant | all |  | SOS's `RELEASE_SEG`: gives a segment back. |
| GETCLOK | SOS_GET_TIME | constant | all |  | SOS's `GET_TIME`: reads the clock. |
| CLDSTRT | SOS_TERMINATE | constant | all |  | SOS's `TERMINATE`, which `BYE` makes: SOS ends the interpreter and asks for the system to be restarted. |
| SEBDP | SOS_ERROR_BAD_PATH | constant | all |  | SOS's error: a bad pathname. |
| SEFNO | SOS_ERROR_BAD_REFERENCE_NUMBER | constant | all |  | SOS's error: a bad reference number, which BASIC calls file not open. |
| SEFNF | SOS_ERROR_FILE_NOT_FOUND | constant | all |  | SOS's error: file not found. |
| SEDFU | SOS_ERROR_DISK_FULL | constant | all |  | SOS's error: the disk is full. |
| SEEOF | SOS_ERROR_END_OF_FILE | constant | all |  | SOS's error: the end of the file. |
| SEMEM | SOS_ERROR_OUT_OF_MEMORY | constant | all |  | SOS's error: out of memory. |
| SENBK | SOS_ERROR_NOT_BLOCK_DEVICE | constant | all |  | SOS's error: not a block device. |
| PRGTY | FILE_TYPE_BASIC_PROGRAM | constant | all |  | The file type of a BASIC program. |
| TXTTYP | FILE_TYPE_TEXT | constant | all |  | The file type of a text file. |
| BINTIP | FILE_TYPE_BASIC_DATA | constant | all |  | The file type of a BASIC data file. |
| UNKNTY | FILE_TYPE_UNKNOWN | constant | all |  | The file type of a file of no known type. |
| PCODTYP | FILE_TYPE_PASCAL_CODE | constant | all |  | The file type of a Pascal code file, as `INVOKE` loads. |
| XRFNM | FileControlBlock::REFERENCE_NUMBER | field | all |  | The file's SOS reference number, 0 while the file is not open. |
| XUID | FileControlBlock::TYPE_AND_ACCESS | field | all |  | The file's type, a FILE_TYPE_ code such as <FILE_TYPE_TEXT>, in bits 0-3; bit 4 set to read it, bit 5 to |
| XBUFPT | FileControlBlock::BUFFER | field | all |  | The file's buffer: its X-byte, then its address's high byte. |
| XBUFOFS | FileControlBlock::BUFFER_OFFSET | field | all |  | How far into the buffer the next item is. It starts at 0 for each record: SOS's mark does the rest. |
| XRNUM | FileControlBlock::RECORD_NUMBER | field | all |  | The record number. |
| XRECL | FileControlBlock::RECORD_LENGTH | field | all |  | The record length, 512 unless the file says otherwise; for a volume's directory, `CATALOG` keeps the volume's |
| XFLGS | FileControlBlock::FLAGS | field | all |  | The file's state: bit 7 set for a buffer changed and not yet written. |
| XSEGNM | FileControlBlock::SEGMENT | field | all |  | The number of the buffer's memory segment, 0 for none, as for a directory `CATALOG` reads. |
| XBLKS | FileControlBlock::BLOCKS_USED | field | all |  | For a volume's directory, the count of the volume's blocks in use, which `CATALOG`'s summary line gives. |
| FCBLEN | FILE_CONTROL_BLOCK_SIZE | constant | all |  | The length of a file control block. |
| DDINT | DATA_ITEM_INTEGER | constant | all |  | An integer: two bytes follow. |
| DDFP | DATA_ITEM_REAL | constant | all |  | A real: four bytes follow. |
| DDLNT | DATA_ITEM_LONG_INTEGER | constant | all |  | A long integer: eight bytes follow. |
| DDSTR | DATA_ITEM_STRING | constant | all |  | A string: its length follows, then the characters. |
| DDMXSTR | DATA_ITEM_LONGEST_STRING | constant | all |  | A string of 255 characters, which follow with no length. |
| DDEOR | DATA_ITEM_END_OF_RECORD | constant | all |  | The end of a record, zero as SOS expects. |
| STKEND | STACK_END | constant | all | STACK_END | Where the stack pointer starts when BASIC resets its stack. |
| EOFSIZ | END_OF_FILE_HANDLERS_SIZE | constant | all |  | The size of <EndOfFileHandlers>: three bytes for each of files 1-10 and `ON KBD`. |
| B3PRT1 | LoadAddress | location | all (one definition per build) |  | Where SOS.INTERP's code loads: lower, for the debugger build. |
| SELFLG | SELECTOR_SIGNATURE | constant | all |  | The value 1.3's program selector leaves in locations 0 and 1, to say it started BASIC. |
| NUMLEV | STACK_LEVELS | constant | all | STACK_LEVELS | The stack levels BASIC keeps free. |
| TEMPTYP | STRING_TYPE_TEMPORARY | constant | all |  | A string's type byte: a temporary. |
| ARYTYP | STRING_TYPE_ARRAY_ELEMENT | constant | all |  | A string's type byte: an array element's. |
| SIMTYP | STRING_TYPE_SIMPLE_VARIABLE | constant | all |  | A string's type byte: a simple variable's. |
| MINPG | POINTER_PAGE_FIRST | constant | all |  | The lowest high byte of a pointer through a bank pair. |
| MAXPG | POINTER_PAGE_LIMIT | constant | all |  | One past the highest high byte of a pointer through a bank pair. |
| INFOSIZ | STRING_INFORMATION_SIZE | constant | all |  | The bytes of information after each string in string space: its type byte and the pointer back to its variable. |
| STRSIZ | DESCRIPTOR_SIZE | constant | all | DESCRIPTOR_SIZE | The size of a string descriptor: the length, then the address. |
| NUMTMP | TEMPORARY_COUNT | constant | all | TEMPORARY_COUNT | The count of string temporaries in <TemporaryDescriptors>. |
| CHARAC | Delimiter | location | all | Delimiter | A character that ends the string being scanned, such as a quote or a comma. |
| INTEGR | SmallInteger | alias | all | SmallInteger | A one-byte integer, from <QINT>. |
| ENDCHR | EndDelimiter | location | all | EndDelimiter | The other character that ends the string being scanned. |
| DSCRPT | DataItemDescriptor | alias | all |  | A data file item's descriptor, such as <DATA_ITEM_INTEGER>, in `READ#` and `WRITE#`. |
| COUNT | Counter | location | all | Counter | A counter for any routine that needs one. |
| DIMFLG | Dimensioning | location | all | Dimensioning | Whether the variable being looked up is being dimensioned by `DIM`. |
| KIMY | KeptY | alias | all |  | A place to keep Y, or another count or flag, for a while. |
| VALTYP | ValueType | location | all | ValueType | The type of the value just evaluated: 0 for a real or an integer, $40 for a long integer, $FF for a string. |
| INTFLG | IntegerType | location | all | IntegerType | Bit 7 set when the variable just found or the value just evaluated is an integer (a % variable). |
| DORES | TokenizeState | location | all | TokenizeState | While a line is crunched into tokens, whether keywords are crunched: bit 7 set stops it until the next colon, and |
| GARBFL | CollectionState | alias | all | CollectionState | Whether a garbage collection was tried while looking for string space. |
| XSAV | SavedX | alias | all |  | A place to keep X for a while. |
| SUBFLG | SubscriptMode | location | all | SubscriptMode | Nonzero when the variable being looked up may not be subscripted, as for a function's name in `DEF FN` and `FN`. |
| YSAVE | SavedY | location | all |  | A place to keep Y, or another byte, for a while. |
| INPFLG | InputMode | location | all | InputMode | Which statement is taking values: `INPUT`, `GET` or `READ`; `LIST` and the long-integer routines use it too. |
| TANSGN | TangentSign | location | all | TangentSign | The sign of the tangent while `TAN` works. |
| ANYNUM | DigitsSeen | alias | all |  | While <FIN> reads a number, whether any digits were seen. |
| FILNO | OutputFileNumber | location | all |  | The output file: OutputFile is where output goes now, OutputFile+1 where it goes between statements. |
| INFLNO | ExecFile | location | all |  | The reference number of the `EXEC` file, 0 when `EXEC` is not running. |
| SVFLNO | CurrentFileNumber | location | all |  | The file number of the file operation in progress. |
| JMPER | FunctionJump | location | all | FunctionJump | A JMP, through which BASIC calls a routine whose address it puts in FunctionJump+1 and FunctionJump+2. |
| DELTA | MoveDistance | location | all |  | How far a block of memory moves, for the move routines, with its X-byte at <MoveDistanceXByte>. |
| VARNAM | VariableSizes | location | all |  | Used by the variable search, <PTRGET>: the value's size for the variable's type, then the size of the variable's |
| VARPNT | VariablePointer | location | all | VariablePointer | The address of the value of the variable <PTRGET> just found or made, with its X-byte at <VariablePointerXByte>. |
| OPPTR | OperatorPointer | location | all | OperatorPointer | A pointer that nothing here names directly; its other names are used. |
| VARTXT | VariableListPointer | alias | all | VariableListPointer | A pointer into a list of variables, as `INPUT` and `READ` go through it. |
| DOMASK | RelationMask | alias | all | RelationMask | The relational operators found: bit 0 >, bit 1 =, bit 2 <. |
| DEFPNT | FunctionPointer | location | all | FunctionPointer | A pointer used by `DEF FN` and `FN`, with its X-byte at <FunctionPointerXByte>. |
| GRBPNT | CollectorDistance | alias | all |  | How far strings move down in a garbage collection: the free bytes found so far. |
| SLEFT | WindowLeft | location | all |  | `WINDOW`'s left column, while it works. |
| FCBNDX | FileControlBlockIndex | alias | all |  | The offset of the current file's control block in <FileControlBlocks>. |
| SWIDTH | WindowRight | location | all |  | `WINDOW`'s right column, while it works; Apple named it for the width. |
| SBOTTOM | WindowBottom | location | all |  | `WINDOW`'s bottom line, while it works. |
| STOPS | WindowTop | location | all |  | `WINDOW`'s top line, while it works. |
| TRMPOS | TerminalPosition | location | all | TerminalPosition | The column the console's output has reached. |
| LINNUM | LineNumber | location | all | LineNumber | A line number, as <LINGET> reads it or `GOTO` looks for it. |
| TEMPPT | NextTemporary | location | all | NextTemporary | The address in zero page of the next free string temporary in <TemporaryDescriptors>. |
| LASTPT | LastTemporary | location | all | LastTemporary | The address of the string temporary used last. |
| TEMPST | TemporaryDescriptors | location | all | TemporaryDescriptors | The string temporaries: <TEMPORARY_COUNT> descriptors of <DESCRIPTOR_SIZE> bytes, for strings that are parts of an |
| INDEX1 | Pointer1 | location | all | Pointer1 | A general pointer, with its X-byte at <Pointer1XByte>. |
| INDEX | Pointer1 | location | all | Pointer1 | A general pointer, with its X-byte at <Pointer1XByte>. |
| INDEX2 | Pointer2 | location | all | Pointer2 | A second general pointer, with its X-byte at <Pointer2XByte>. |
| TXTTAB | ProgramStart | location | all | ProgramStart | The start of the program, with its X-byte at <ProgramStartXByte>. |
| VARTAB | VariablesStart | location | all | VariablesStart | The start of the simple variables, just past the arrays, with its X-byte at <VariablesStartXByte>. |
| SMVARS | VariablesStart | location | all |  | The start of the simple variables, just past the arrays, with its X-byte at <VariablesStartXByte>. |
| ARYTAB | ArraysStart | location | all | ArraysStart | The start of the arrays, just past the program, with its X-byte at <ArraysStartXByte>. |
| STREND | VariablesEnd | location | all |  | The end of the simple variables, the first free byte above them, with its X-byte at <VariablesEndXByte>. |
| FRETOP | StringsBottom | location | all | StringsBottom | The bottom of the strings in use, with its X-byte at <StringsBottomXByte>: a new string is taken from just below |
| INVTAB | ModulesStart | location | all |  | The start of the memory `INVOKE` loads modules into, with its X-byte at <ModulesStartXByte>. |
| PROCTAB | ModulesEnd | location | all |  | The end of the invokable modules' memory, below which `INVOKE` builds the table of their procedures, with its |
| FRESPC | NewString | location | all | NewString | The string <GETSPA> just made room for, with its X-byte at <NewStringXByte>. |
| MEMSIZ | MemoryTop | location | all | MemoryTop | The top of the strings' memory, `HIMEM`, with its X-byte at <MemoryTopXByte>. |
| HIMEM | MemoryTop | location | all |  | The top of the strings' memory, `HIMEM`, with its X-byte at <MemoryTopXByte>. |
| CURLIN | CurrentLine | location | all | CurrentLine | The number of the line running; its high byte is $FF for a statement typed without a line number. |
| OLDLIN | StoppedLine | location | all | StoppedLine | The number of the line at which the program stopped, for `CONT`, or was interrupted. |
| POKER | PokeAddress | alias | all | PokeAddress | A 16-bit address, for `PEEK`, `POKE` and the like. |
| OLDTXT | StoppedText | location | all | StoppedText | Where the program stopped, for `CONT`: the statement to run next, with its X-byte at <StoppedTextXByte>. |
| DATLIN | DataLine | location | all | DataLine | The number of the line of the `DATA` statement `READ` is in, for errors. |
| DATPTR | DataPointer | location | all | DataPointer | Where `READ` takes its next value, with its X-byte at <DataPointerXByte>. |
| INPPTR | InputPointer | location | all | InputPointer | Where `INPUT` or `READ` takes its next value, with its X-byte at <InputPointerXByte>. |
| FDECPT | PowerTablePointer | alias | all | PowerTablePointer | The place in the table of powers of ten <FOUT> has reached. |
| FORPNT | AssignedVariable | location | all | AssignedVariable | The variable `FOR` or `LET` is assigning to, with its X-byte at <AssignedVariableXByte>. |
| LSTPNT | ListOffset | alias | all | ListOffset | The place in a keyword's name `LIST` has reached. |
| TKNSAV | ListToken | alias | all |  | The token `LIST` is printing. |
| TYPSAV | SavedFileType | alias | all |  | The file's type, in the file commands. |
| DSCPNT | DescriptorPointer | location | all | DescriptorPointer | A pointer to a string descriptor, with its X-byte at <DescriptorPointerXByte>. |
| FOUR6 | CollectorStep | location | all | CollectorStep | The size of a string descriptor, <DESCRIPTOR_SIZE>, kept here for the garbage collector; other routines use it |
| SIZE | CollectorOffset | alias | all | CollectorOffset | A size, in <FunctionJump>'s address bytes. |
| OLDOV | FunctionJumpHigh | alias | all | FunctionJumpHigh | The overflow byte of the earlier multiplication step, in <FunctionJump>'s address bytes. |
| TEMPF3 | FloatTemporary3 | alias | all | FloatTemporary3 | A third temporary for a packed real, five bytes, which run over <FunctionPointer> and the `WINDOW` bytes from |
| TEMPF1 | FloatTemporary1 | location | all | FloatTemporary1 | A temporary for a packed real, five bytes: this one, then <DestinationEnd>'s and <DataBufferPointer>'s. |
| HIGHDS | DestinationEnd | location | all | DestinationEnd | Where a block move puts its highest byte, with its X-byte at <DestinationEndXByte>. |
| PTR1 | LongOperand1Pointer | alias | all |  | The first long-integer operand, for the long-integer routines, which <LPTRS> points at <Fac>. |
| NDXPTR | DataBufferPointer | location | all |  | Where `READ#` and `WRITE#` are in a data file's buffer, with its X-byte at <DataBufferPointerXByte>. |
| HIGHTR | SourceEnd | location | all | SourceEnd | The highest byte a block move moves, with its X-byte at <SourceEndXByte>. |
| PTR2 | LongOperand2Pointer | alias | all |  | The second long-integer operand, which <LPTRS> points at <ArgExponent>. |
| TEMPF2 | FloatTemporary2 | location | all | FloatTemporary2 | A second temporary for a packed real, five bytes: this one, then <DestinationStart>'s and <SourceStart>'s. |
| LENSAV | DataItemLength | alias | all |  | The length of a data file item, in `READ#` and `WRITE#`. |
| LOWDS | DestinationStart | location | all | DestinationStart | Where a block move's last byte went, with its X-byte at <DestinationStartXByte>. |
| LOWTR | SourceStart | location | all | SourceStart | The lowest byte a block move moves, with its X-byte at <SourceStartXByte>; the line <FNDLIN> found. |
| PTR3 | LongResultPointer | alias | all |  | Where a long-integer routine puts its result, which <LPTRS> points at <Fac>. |
| SRCHPT | VariableSearchPointer | alias | all |  | The variable entry the variable search is looking at. |
| ARYPNT | ArrayPointer | alias | all | ArrayPointer | A pointer used in building an array. |
| GRBTOP | CollectorTop | alias | all | CollectorTop | A pointer used by the garbage collector. |
| DECCNT | DigitCount | alias | all | DigitCount | While <FOUT> works, the count of digits before the decimal point. |
| TENEXP | DecimalExponent | alias | all | DecimalExponent | While <FIN> works, the power of ten so far. |
| DPTFLG | DecimalPointSeen | alias | all | DecimalPointSeen | While <FIN> works, whether a decimal point has been read. |
| EXPSGN | ExponentSign | alias | all | ExponentSign | While <FIN> works, the sign of the exponent. |
| FAC | Fac | location | all | Fac | The floating-point accumulator: the exponent, four bytes of mantissa, and the sign. |
| FACEXP | FacExponent | location | all | FacExponent | The accumulator's exponent, 0 for the value zero. |
| FACHO | FacMantissa1 | location | all | FacMantissa1 | The accumulator's mantissa, its highest byte. |
| FACMOH | FacMantissa2 | location | all | FacMantissa2 | The accumulator's mantissa, its second byte. |
| FACT | FacDecimalDigits | alias | all |  | Where a decimal value's digits start, for `PRINT USING` and the long integers' conversions. |
| FACMO | FacMantissa3 | location | all | FacMantissa3 | The accumulator's mantissa, its third byte, with its X-byte at <FacMantissa3XByte> for when it holds a pointer. |
| FACLO | FacMantissa4 | location | all | FacMantissa4 | The accumulator's mantissa, its lowest byte. |
| FACSGN | FacSign | location | all | FacSign | The accumulator's sign while it is unpacked: 0 for positive, $FF for negative. |
| SGNFLG | InputSign | location | all | InputSign | The sign of the number <FIN> is reading. |
| DEGREE | PolynomialDegree | alias | all | PolynomialDegree | The count of terms while a polynomial is worked out. |
| DSCTMP | NewDescriptor | alias | all | NewDescriptor | Where a string temporary's descriptor is built. |
| INDICE | ArrayIndex | alias | all | ArrayIndex | The integer <QINT> leaves. |
| CNTDIGS | DigitsLeft | location | all |  | How many more digits <FIN> takes before it rounds, at ten. |
| ARGEXP | ArgExponent | location | all | ArgExponent | The argument's exponent: the argument is a second floating-point value, laid out like <Fac>. |
| ARG | Arg | location | all | ArgExponent | The argument's exponent: the argument is a second floating-point value, laid out like <Fac>. |
| ARGHO | ArgMantissa1 | location | all | ArgMantissa1 | The argument's mantissa, its highest byte. |
| ARGMOH | ArgMantissa2 | location | all | ArgMantissa2 | The argument's mantissa, its second byte. |
| ARGMO | ArgMantissa3 | location | all | ArgMantissa3 | The argument's mantissa, its third byte, with its X-byte at <ArgMantissa3XByte>. |
| ARGLO | ArgMantissa4 | location | all | ArgMantissa4 | The argument's mantissa, its lowest byte. |
| ARGSGN | ArgSign | location | all | ArgSign | The argument's sign: 0 for positive, $FF for negative. |
| ARISGN | ResultSign | location | all | ResultSign | The sign of the result: the accumulator's and the argument's signs combined. |
| RESHO | Result1 | location | all | Result1 | The result of a multiplication or division, its highest byte; for the long integers, the first of eight. |
| RES | Result1 | location | all | Result1 | The result of a multiplication or division, its highest byte; for the long integers, the first of eight. |
| RESMOH | Result2 | location | all | Result2 | The result's second byte. |
| RESMO | Result3 | location | all | Result3 | The result's third byte. |
| RESLO | Result4 | location | all | Result4 | The result's lowest byte. |
| ADDEND | Addend | alias | all | Addend | A temporary of <UMULT>'s. |
| TEMP | Temporary | location | all |  | A temporary for any routine; for the long integers, the result's fifth byte. |
| FACOV | FacExtension | location | all | FacExtension | The accumulator's rounding byte, below its lowest. |
| STRNG1 | StringPointer | alias | all | StringPointer | A pointer to a string or its descriptor. |
| FBUFPT | NumberBufferPointer | location | all | NumberBufferPointer | Where <FOUT> has reached in <NumberBuffer>. |
| BUFPTR | TokenizePointer | alias | all | TokenizePointer | Where <CRUNCH> has reached in <InputBuffer>. |
| STRNG2 | SecondStringPointer | alias | all | SecondStringPointer | A second pointer to a string or its descriptor. |
| POLYPT | PolynomialPointer | alias | all | PolynomialPointer | The coefficients of the polynomial being worked out. |
| CURTOL | LinearIndex | alias | all | LinearIndex | The array's size so far, in `DIM` and the variable search. |
| TRFLAG | TraceMode | location | all | TraceMode | Bit 7 set while `TRACE` is on. |
| TEMPFOR | ForVariableType | location | all |  | The type flags of a `FOR` loop's variable, as <FNDFOR> looks for its loop on the stack. |
| ERRTO | OnErrorText | location | all | OnErrorText | Where `ON ERR` goes: the statement after it, with its X-byte at <OnErrorTextXByte>, then (at OnErrorText+3) its |
| ERRLIN | ErrorLine | location | all | ErrorLine | The number of the line the last error happened in, which `ERRLIN` gives. |
| ERRPOS | ErrorText | location | all | ErrorText | The statement the last error happened in, for `RESUME`, with its X-byte at <ErrorTextXByte>; zero there means no |
| ERRNUM | ErrorCode | location | all | ErrorCode | The number of the last error, which `ERR` gives: an ERROR_ number, or 255 for a Control-C. |
| ERRFLG | OnErrorActive | location | all | OnErrorActive | Bit 7 set while `ON ERR` is on. |
| REMSTK | StatementStack | location | all | StatementStack | The stack pointer BASIC goes back to after an error. |
| RNFLG | StartupDone | location | all |  | Nonzero once BASIC has reached its prompt or `RUN` or `CHAIN` has loaded a program; until then, 1.3's errors |
| NOUNPT | OperandStackTop | location | all |  | The top of <OperandStack>, the expression evaluator's operand stack. |
| VRBPT | OperatorStackTop | location | all |  | The top of <OperatorStack>, the expression evaluator's operator stack. |
| HEADER | StringInformationPointer | location | all |  | A pointer to the information bytes after a string, with its X-byte at <StringInformationPointerXByte>. |
| PNTSAV | ListSavedPointer | location | all |  | A place for `LIST` to keep a pointer. |
| LVLCNT | IfDepth | location | all |  | The `IF`s still to be matched while an `ELSE` is looked for. |
| QUOTE | InQuotes | alias | all |  | Whether the text being scanned is inside quotes. |
| TMPPTR | VariableNamePointer | location | all |  | The variable name the variable search is reading, with its X-byte at <VariableNamePointerXByte>. |
| STRFLG | StringFlag | location | all |  | A string flag: <FRMEVL> clears it, and nothing reads it. |
| INVPNT | ModuleLoadPointer | location | all |  | Where `INVOKE` loads the next module, with its X-byte at <ModuleLoadPointerXByte>. |
| NPOINTS | PointerParameterCount | location | all |  | `INVOKE`'s and `PERFORM`'s count of pointer parameters; it must survive the expression evaluator. |
| NPARAMS | ParameterWordCount | location | all |  | `PERFORM`'s count of parameter words; it must survive the expression evaluator. |
| PROCFLG | ProcedureKind | location | all |  | What kind of routine `INVOKE` or `PERFORM` is looking for; it must survive the expression evaluator. |
| IOFLG | FileAccessMode | alias | all |  | Whether a file statement reads or writes. |
| KEYSTROK | PendingEvents | location | all |  | Bit 7 set when a key was pressed, bit 6 when Control-C was; the handlers set them and the statement loop checks |
| MLTPLR | Multiplier | location | all |  | Work space for 16-bit multiplication and division: the multiplier, or the quotient. |
| RSLT | Product | alias | all |  | The product. |
| RMNDR | Remainder | location | all |  | The remainder of the division. |
| MLTPLR2 | Multiplicand | location | all |  | The multiplicand, or the divisor. |
| QUOTNT | Quotient | alias | all |  | The quotient. |
| DVDND | Dividend | alias | all |  | The dividend. |
| DVSR | Divisor | alias | all |  | The divisor. |
| BITS | ShiftFill | location | all | ShiftFill | The byte a whole-byte right shift fills with: 0, or $FF to extend a negative number's sign. |
| TXTPTR | TextPointer | location | all | TextPointer | Where the program or line is being read, with its X-byte at <TextPointerXByte>: the operand of the LDA in |
| CHRGET | GetNextCharacter | routine | all | GetNextCharacter | Takes the next character of the program or the line, skipping spaces. |
| CHRGOT | GetCurrentCharacter | routine | all | GetCurrentCharacter | Takes the character at <TextPointer> again, without moving on, skipping spaces. |
| RNDX | RandomValue | location | all | RandomValue | The random number generator's state, which `RND` works from; <INIT> seeds it from the system's counters. |
| NAMPNT | ExfnNameOffset | location | all |  | Where the name of the routine `EXFN` calls starts in <NameBuffer>, for an `EXFN` inside another. |
| CMDFLG | ProgramLoading | location | all |  | Set from when `RUN` or `CHAIN` opens a program file until the statement loop starts its first statement; 1.3 |
| DISPATCH | ModuleCallJump | location | all |  | A JMP to <SWCHGO>, through which a module calls a routine of BASIC's by its number in <ModuleRoutineNumber>. |
| PASSAREG | ModuleRoutineNumber | location | all |  | The number of the routine of BASIC's a module calls through <ModuleCallJump>: its place in <JMPRTAB>. |
| BANKPNT | ReferencePointers | location | all |  | Pointers to the variables a module was passed by reference, each with its X-byte at <ReferencePointersXByte>. |
| CRUDBUF | WorkPage | location | all |  | BASIC's work page. |
| SAFE | PerformSavedReturn | location | all |  | The return address `PERFORM`'s caller left, kept here while the module runs, then the bank that was switched in. |
| RAMLOC | SegmentStart | location | all |  | The start of the memory segment SOS gave BASIC, with its X-byte in <SegmentStartXByte>. |
| RAMLOCB | SegmentStartXByte | location | all |  | The X-byte of <SegmentStart>. |
| VRBSTK | OperatorStack | location | all |  | The expression evaluator's operator stack: each operator's number and its precedence (with the operand's type). |
| EOFPTRS | EndOfFileHandlers | location | all |  | Where each file's `ON EOF#` goes, three bytes for each file from 1, the last for `ON KBD`: the X-byte, then the |
| EOFLINS | EndOfFileHandlerLines | location | all |  | The line number of each <EndOfFileHandlers> entry's handler, at the same offset. |
| FCB | FileControlBlocks | location | all |  | The control blocks of files 1-10, <FILE_CONTROL_BLOCK_SIZE> bytes each. |
| CATFCB | CatalogControlBlock | location | all |  | The control block `CATALOG` reads the directory through, as file 11. |
| INVBNK | ModulesXByte | location | all |  | The X-byte of the invokable modules' bank pair. |
| BASICBNK | BasicBank | location | all |  | BASIC's own bank, from the bank register when BASIC started. |
| ISARA | ArrayElementFound | location | all |  | Bit 7 set when the variable just found is an array element. |
| NOUNSTK | OperandStack | location | all |  | The expression evaluator's operand stack. |
| SOSLOC | SosError | location | all |  | The SOS error code for a SOS CALL error. |
| OUTREC | OutputRecordLength | location | all |  | The right margin `LIST` wraps at, which `OUTREC` sets and gives; 0 turns wrapping off. |
| INDENT | ListIndent | location | all |  | How many spaces `LIST` indents each `FOR` loop's lines, which `INDENT` sets and gives. |
| EOFSV | EndOfFileNumber | location | all |  | The number of the file that last reached its end, which `EOF` gives. |
| GOBASIC | InterpreterEntry | routine | all |  | The first byte SOS loads: a jump to <INIT>, where SOS starts the interpreter. |
| SELECTOR | StartedBySelector | location | 1.3 |  | Zero when BASIC was started from the disk, so it runs HELLO, or not zero when 1.3's program selector started it. |
| PROGPATH | ProgramPath | location | 1.3 |  | The pathname of the program the selector chose, with its length first; then just its prefix. |
| SOSPATH | SosPrefix | location | 1.3 |  | SOS's own prefix, with its length first, which BASIC goes back to for its own files. |
| NAMBUF | NameBuffer | location | all |  | A pathname or a routine's name, as a file command or `PERFORM` reads it, with its length first. |
| CATBUF | CatalogBuffer | location | all |  | `CATALOG`'s line buffer, and the buffer GET_PREFIX fills. |
| LENUM | LongTextLength | location | all |  | The length of the long integer <LOUT> wrote as text in <LongText>. |
| BCDSTR | UsingDigits | location | all |  | The digits of a number for `PRINT USING`, one to a byte; <FOUT>'s output buffer, <NumberBuffer>, is in its upper |
| NUMSTR | LongText | alias | all |  | A long integer as text, as <LOUT> writes it. |
| FBUFFR | NumberBuffer | alias | all | NumberBuffer | <FOUT>'s output: a number as text, ending in a zero. |
| LOFBUF | NumberBufferPrefix | alias | all | NumberBufferPrefix | The byte before <NumberBuffer>. |
| PREBUF | PrefixBufferEnd | alias | all |  | An end of a buffer for `PREFIX$`, which nothing uses. |
| BUF | InputBuffer | location | all | AppleSoft::InputBuffer | The input line: the line typed, or read from a file, which <CRUNCH> then turns into tokens in place. |
| KEYSAVE | LastKey | location | all |  | The last key read, which `KBD` gives. |
| STMDSP | StatementTable | table | all | StatementTable | Each statement's routine, less one, by its token from `END` ($80) to `NEW` ($E0): the statement loop pushes the |
| RESTBL | ValueWordTable | table | all |  | The routines of the keywords that give a value without parentheses, by token from `FRE` (<TOKEN_FRE>) to |
| FUNDSP | FunctionTable | table | all | FunctionTable | The functions' routines, by their tokens in <ExtendedReservedWords> from `SGN(` (<TOKEN_FIRST_FUNCTION>) to |
| PRECTB | PrecedenceTable | table | all |  | Each operator's precedence, higher binding tighter, by the operator's number less one. |
| OPDSPT | OperatorRoutineTable | table | all |  | The routines for the operators on reals and integers, two bytes each in operator order: the relational operators' |
| RELNUM | OPERATOR_RELATIONAL_ENTRY | constant | all |  | The relational operators' entry, the first. |
| NUMDSP | OPERATOR_LONG_ROUTINES | constant | all |  | The offset of the long-integer routines, and of + for a string. |
| SYSPAG | X_BYTE_OFFSET | constant | all |  | From a pointer's address to its X-byte: $1600, plus 1 for the high byte. |
| VARNAMB | VariableSizesXByte | location | all |  | <VariableSizes>' X-byte. |
| VARPNTB | VariablePointerXByte | location | all |  | <VariablePointer>'s X-byte: the bank of the variable just found. |
| DEFPNTB | FunctionPointerXByte | location | all |  | <FunctionPointer>'s X-byte. |
| INDEX1B | Pointer1XByte | location | all |  | <Pointer1>'s X-byte. |
| INDEXB | Pointer1XByte | location | all |  | <Pointer1>'s X-byte. |
| INDEX2B | Pointer2XByte | location | all |  | <Pointer2>'s X-byte. |
| TXTTABB | ProgramStartXByte | location | all |  | <ProgramStart>'s X-byte: the bank of the program's start. |
| VARTABB | VariablesStartXByte | location | all |  | <VariablesStart>' X-byte: the bank of the simple variables' start. |
| SMVARSB | VariablesStartXByte | location | all |  | <VariablesStart>' X-byte: the bank of the simple variables' start. |
| ARYTABB | ArraysStartXByte | location | all |  | <ArraysStart>' X-byte: the bank of the arrays' start. |
| STRENDB | VariablesEndXByte | location | all |  | <VariablesEnd>' X-byte: the bank of the variables' end. |
| FRETOPB | StringsBottomXByte | location | all |  | <StringsBottom>' X-byte: the bank of the strings' bottom. |
| FRESPCB | NewStringXByte | location | all |  | <NewString>'s X-byte. |
| MEMSIZB | MemoryTopXByte | location | all |  | <MemoryTop>'s X-byte: the bank of the strings' top. |
| HIMEMB | MemoryTopXByte | location | all |  | <MemoryTop>'s X-byte: the bank of the strings' top. |
| OLDTXTB | StoppedTextXByte | location | all |  | <StoppedText>'s X-byte. |
| DATPTRB | DataPointerXByte | location | all |  | <DataPointer>'s X-byte. |
| INPPTRB | InputPointerXByte | location | all |  | <InputPointer>'s X-byte. |
| DSCPNTB | DescriptorPointerXByte | location | all |  | <DescriptorPointer>'s X-byte. |
| HIGHDSB | DestinationEndXByte | location | all |  | <DestinationEnd>'s X-byte. |
| NDXPTRB | DataBufferPointerXByte | location | all |  | <DataBufferPointer>'s X-byte. |
| HIGHTRB | SourceEndXByte | location | all |  | <SourceEnd>'s X-byte. |
| LOWDSB | DestinationStartXByte | location | all |  | <DestinationStart>'s X-byte. |
| LOWTRB | SourceStartXByte | location | all |  | <SourceStart>'s X-byte. |
| PTR1B | LongOperand1PointerXByte | location | all |  | <LongOperand1Pointer>'s X-byte. |
| PTR2B | LongOperand2PointerXByte | location | all |  | <LongOperand2Pointer>'s X-byte. |
| PTR3B | LongResultPointerXByte | location | all |  | <LongResultPointer>'s X-byte. |
| FACB | FacXByte | location | all |  | The X-byte of <Fac> and <FacMantissa1> as a pointer. |
| FACMOB | FacMantissa3XByte | location | all |  | The X-byte of <FacMantissa3> and <FacMantissa4> as a pointer. |
| ARGMOB | ArgMantissa3XByte | location | all |  | The X-byte of <ArgMantissa3> and <ArgMantissa4> as a pointer. |
| HEADERB | StringInformationPointerXByte | location | all |  | <StringInformationPointer>'s X-byte. |
| DSCTMPB | NewDescriptorXByte | location | all |  | The X-byte of the string address in <NewDescriptor>, which follows its length. |
| VARTXTB | VariableListPointerXByte | location | all |  | <VariableListPointer>'s X-byte. |
| TXTPTRB | TextPointerXByte | location | all |  | <TextPointer>'s X-byte: the bank of the text <GetNextCharacter> reads. |
| TMPPTRB | VariableNamePointerXByte | location | all |  | <VariableNamePointer>'s X-byte. |
| SRCHPTB | VariableSearchPointerXByte | location | all |  | <VariableSearchPointer>'s X-byte. |
| ARYPNTB | ArrayPointerXByte | location | all |  | <ArrayPointer>'s X-byte. |
| STRNG1B | StringPointerXByte | location | all |  | <StringPointer>'s X-byte. |
| STRNG2B | SecondStringPointerXByte | location | all |  | <SecondStringPointer>'s X-byte. |
| FORPNTB | AssignedVariableXByte | location | all |  | <AssignedVariable>'s X-byte. |
| DECCNTB | DigitCountXByte | location | all |  | <DigitCount>'s X-byte. |
| GRBTOPB | CollectorTopXByte | location | all |  | <CollectorTop>'s X-byte. |
| DELTAB | MoveDistanceXByte | location | all |  | The bank part of <MoveDistance>, how many bank pairs a block moves. |
| BANKPNTB | ReferencePointersXByte | location | all |  | The X-byte of <ReferencePointers>' first pointer. |
| PROCTABB | ModulesEndXByte | location | all |  | <ModulesEnd>' X-byte. |
| INVTABB | ModulesStartXByte | location | all |  | <ModulesStart>' X-byte. |
| POLYPTB | PolynomialPointerXByte | location | all |  | <PolynomialPointer>'s X-byte. |
| INVPNTB | ModuleLoadPointerXByte | location | all |  | <ModuleLoadPointer>'s X-byte. |
| ERRTOB | OnErrorTextXByte | location | all |  | The X-byte of `ON ERR`'s statement address in <OnErrorText>. |
| ERRPOSB | ErrorTextXByte | location | all |  | The X-byte of the last error's statement address in <ErrorText>. |
| TMERR | TypeMismatchError | routine | all |  | Ends the statement with a `TYPE MISMATCH` error. |
| ENDTK | TOKEN_END | token | all | TOKEN_END | The token of `END`, the first one-byte token. |
| FORTK | TOKEN_FOR | token | all | TOKEN_FOR | The token of `FOR`. |
| INPTKN | TOKEN_INPUT | token | all |  | The token of `INPUT`. |
| OUTTKN | TOKEN_OUTPUT | token | all |  | The token of `OUTPUT`. |
| OPENTK | TOKEN_OPEN | token | all |  | The token of `OPEN`. |
| TEXTTK | TOKEN_TEXT | token | all |  | The token of `TEXT`. |
| INVOKTK | TOKEN_INVOKE | token | all |  | The token of `INVOKE`. |
| FRETK | TOKEN_FRE | token | all |  | The token of `FRE`, the first of the words that give a value with no parentheses, through <ValueWordTable>. |
| HPOSTK | TOKEN_HPOS | token | all |  | The token of `HPOS`. |
| VPOSTK | TOKEN_VPOS | token | all |  | The token of `VPOS`. |
| ERRLINTK | TOKEN_ERRLIN | token | all |  | The token of `ERRLIN`. |
| ERRTK | TOKEN_ERR | token | all |  | The token of `ERR`. |
| KBDTK | TOKEN_KBD | token | all |  | The token of `KBD`. |
| EOFTK | TOKEN_EOF | token | all |  | The token of `EOF`. |
| EXFNSTK | TOKEN_EXFN_INTEGER | token | all |  | The token of `EXFN%.`, the integer form of `EXFN.`. |
| POPTKN | TOKEN_POP | token | all |  | The token of `POP`, the first past the words of <ValueWordTable>. |
| SCALETK | TOKEN_SCALE | token | all |  | The token of `SCALE(`. |
| GOTOTK | TOKEN_GOTO | token | all | TOKEN_GOTO | The token of `GOTO`. |
| IFTOKN | TOKEN_IF | token | all |  | The token of `IF`. |
| GOSUTK | TOKEN_GOSUB | token | all | TOKEN_GOSUB | The token of `GOSUB`. |
| REMTK | TOKEN_REM | token | all | TOKEN_REM | The token of `REM`. |
| LDTKN | TOKEN_LOAD | token | all |  | The token of `LOAD`, the first of the file commands, whose file names <CRUNCH> leaves as typed. |
| RENMTK | TOKEN_RENAME | token | all |  | The token of `RENAME`. |
| CATATK | TOKEN_CATALOG | token | all |  | The token of `CATALOG`. |
| DSKCOMS | TOKEN_LAST_FILE_COMMAND | token | all |  | The last of the file commands' tokens, $D3, which has no keyword. |
| DATATK | TOKEN_DATA | token | all | TOKEN_DATA | The token of `DATA`. |
| IMAGETK | TOKEN_IMAGE | token | all |  | The token of `IMAGE`. |
| CATTK | TOKEN_CAT | token | all |  | The token of `CAT`. |
| PRINTK | TOKEN_PRINT | token | all | TOKEN_PRINT | The token of `PRINT`. |
| ELSETK | TOKEN_ELSE | token | all |  | The token of `ELSE`. |
| SCRATK | TOKEN_NEW | token | all | TOKEN_NEW | The token of `NEW`, the last one-byte token. |
| RESLST | ReservedWords | table | all | ReservedWords | The keywords with one-byte tokens, from $80 to $E0, each with the last character's bit 7 set. |
| TABTK | TOKEN_TAB | token | all | TOKEN_TAB | The token of `TAB(`, the first two-byte token after <TOKEN_ESCAPE>. |
| TOTK | TOKEN_TO | token | all | TOKEN_TO | The token of `TO`. |
| SPCTK | TOKEN_SPC | token | all | TOKEN_SPC | The token of `SPC(`. |
| USINGTK | TOKEN_USING | token | all |  | The token of `USING`. |
| THENTK | TOKEN_THEN | token | all | TOKEN_THEN | The token of `THEN`. |
| ATTKN | TOKEN_AT | token | all |  | $85, a token named for `AT`, which has no keyword. |
| MODTK | TOKEN_MOD | token | all |  | The token of `MOD`. |
| STEPTK | TOKEN_STEP | token | all | TOKEN_STEP | The token of `STEP`. |
| ANDTK | TOKEN_AND | token | all |  | The token of `AND`. |
| ORTK | TOKEN_OR | token | all |  | The token of `OR`. |
| EXTKN | TOKEN_EXTENSION | token | all |  | The token of `EXTENSION`. |
| DIVTK | TOKEN_DIV | token | all |  | The token of `DIV`. |
| FNTK | TOKEN_FN | token | all | TOKEN_FN | The token of `FN`. |
| NOTTK | TOKEN_NOT | token | all | TOKEN_NOT | The token of `NOT`. |
| ASTKN | TOKEN_AS | token | all |  | The token of `AS`. |
| ONEFUN | TOKEN_FIRST_FUNCTION | token | all | TOKEN_FIRST_FUNCTION | The token of `SGN(`, the first function's; <FunctionTable>'s index starts here. |
| STRTK | TOKEN_STR | token | all |  | The token of `STR$(`. |
| HEXTK | TOKEN_HEX | token | all |  | The token of `HEX$(`. |
| CHRTK | TOKEN_CHR | token | all |  | The token of `CHR$(`. |
| LENTK | TOKEN_LEN | token | all |  | The token of `LEN(`. |
| DEXPTK | TOKEN_DEXP | token | all |  | $CA, a token Apple named DEXP, which has no keyword and which nothing uses. |
| DLOGTK | TOKEN_DLOG | token | all |  | $CB, a token Apple named DLOG, which has no keyword and which nothing uses. |
| CONVTK | TOKEN_CONV | token | all |  | The token of `CONV(`. |
| LASNUM | TOKEN_LAST_SIMPLE_FUNCTION | token | all | TOKEN_LAST_SIMPLE_FUNCTION | The token of `CONV%(`, the last function with one argument; the functions after it take more. |
| INSTRTK | TOKEN_INSTR | token | all |  | The token of `INSTR(`, the last. |
| RESL2 | ExtendedReservedWords | table | all |  | The keywords with two-byte tokens, <TOKEN_ESCAPE> and then $80-$D3, each with the last character's bit 7 set. |
| RELNOT | OPERATOR_NUMBER_OFFSET | constant | all |  | Added to an operator's place in <OperatorSymbols> to give its number. |
| OPTAB | OperatorSymbols | table | all |  | The operators, as the expression evaluator looks for them: the relational characters, then ^, `AND`, `OR`, `MOD`, |
| RELOPS | OPERATOR_LAST_RELATIONAL | constant | all |  | 7, the highest relational operator's number. |
| ENDOP | OPERATOR_END | constant | all |  | 17, the number of the end of the expression. |
| NUMOPS | OPERATOR_COUNT | constant | all |  | 13, the count of entries in <OperatorSymbols>. |
| ERRNF | ERROR_NEXT_WITHOUT_FOR | error | all | ERROR_NEXT_WITHOUT_FOR | `NEXT WITHOUT FOR`. |
| ERRSN | ERROR_SYNTAX | error | all | ERROR_SYNTAX | `SYNTAX`. |
| ERRRG | ERROR_RETURN_WITHOUT_GOSUB | error | all | ERROR_RETURN_WITHOUT_GOSUB | `RETURN WITHOUT GOSUB`. |
| ERROD | ERROR_OUT_OF_DATA | error | all | ERROR_OUT_OF_DATA | `OUT OF DATA`. |
| ERRFC | ERROR_ILLEGAL_QUANTITY | error | all | ERROR_ILLEGAL_QUANTITY | `ILLEGAL QUANTITY`. |
| ERROV | ERROR_OVERFLOW | error | all | ERROR_OVERFLOW | `OVERFLOW`. |
| ERROM | ERROR_OUT_OF_MEMORY | error | all | ERROR_OUT_OF_MEMORY | `OUT OF MEMORY`. |
| ERRUS | ERROR_UNDEFINED_STATEMENT | error | all | ERROR_UNDEFINED_STATEMENT | `UNDEF'D STATEMENT`. |
| ERRBS | ERROR_BAD_SUBSCRIPT | error | all | ERROR_BAD_SUBSCRIPT | `BAD SUBSCRIPT`. |
| ERRNG | ERROR_RANGE | error | all |  | `RANGE`. |
| ERRIN | ERROR_INVOKE | error | all |  | `INVOKE`. |
| ERRSK | ERROR_STACK_OVERFLOW | error | all |  | `STACK OVERFLOW`. |
| ERRDD | ERROR_REDIMENSIONED_ARRAY | error | all | ERROR_REDIMENSIONED_ARRAY | `REDIM'D ARRAY`. |
| ERRDV0 | ERROR_DIVISION_BY_ZERO | error | all | ERROR_DIVISION_BY_ZERO | `DIVISION BY ZERO`. |
| ERRID | ERROR_ILLEGAL_DIRECT | error | all | ERROR_ILLEGAL_DIRECT | `ILLEGAL DIRECT`. |
| ERRTM | ERROR_TYPE_MISMATCH | error | all | ERROR_TYPE_MISMATCH | `TYPE MISMATCH`. |
| ERRLS | ERROR_STRING_TOO_LONG | error | all | ERROR_STRING_TOO_LONG | `STRING TOO LONG`. |
| ERRST | ERROR_FORMULA_TOO_COMPLEX | error | all | ERROR_FORMULA_TOO_COMPLEX | `FORMULA TOO COMPLEX`. |
| ERRCN | ERROR_CANT_CONTINUE | error | all | ERROR_CANT_CONTINUE | `CAN'T CONTINUE`. |
| ERRUF | ERROR_UNDEFINED_FUNCTION | error | all | ERROR_UNDEFINED_FUNCTION | `UNDEF'D FUNCTION`. |
| ERRVA | ERROR_VARIABLE | error | all |  | `VARIABLE`. |
| SSSSSS | ERROR_SOS_CALL | error | all |  | `SOS CALL`: a SOS error with no message of its own, its code in <SosError>. |
| ERRFB | ERROR_FILES_BUSY | error | all |  | `FILES BUSY`. |
| ERRNS | ERROR_NOT_SOS | error | all |  | `NOT SOS`. |
| ERRIO | ERROR_IO | error | all |  | `I/O`. |
| ERRCR | ERROR_FILE_TOO_LARGE | error | all |  | `FILE TOO LARGE`. |
| ERRWP | ERROR_WRITE_PROTECT | error | all |  | `WRITE PROTECT`. |
| ERRDS | ERROR_DISK_SWITCHED | error | all |  | `DISK SWITCHED`. |
| ERRBP | ERROR_BAD_PATH | error | all |  | `BAD PATH`. |
| ERRFN | ERROR_FILE_NOT_FOUND | error | all |  | `FILE NOT FOUND`. |
| ERRPN | ERROR_PATH_NOT_FOUND | error | all |  | `PATH NOT FOUND`. |
| ERRVN | ERROR_VOLUME_NOT_FOUND | error | all |  | `VOLUME NOT FOUND`. |
| ERRDF | ERROR_DUPLICATE_FILE | error | all |  | `DUPLICATE FILE`. |
| ERRFU | ERROR_DISK_FULL | error | all |  | `DISK FULL`. |
| ERRFL | ERROR_FILE_LOCKED | error | all |  | `FILE LOCKED`. |
| ERRNO | ERROR_FILE_NOT_OPEN | error | all |  | `FILE NOT OPEN`. |
| ERRDO | ERROR_DEVICE_DISCONNECTED | error | all |  | `DEVICE DISCONNECTED`. |
| ERRDU | ERROR_RESOURCE_UNAVAILABLE | error | all |  | `RESOURCE UNAVAILABLE`. |
| ERRFD | ERROR_DIRECTORY_FULL | error | all |  | `DIRECTORY FULL`. |
| ERRDV | ERROR_DUPLICATE_VOLUME | error | all |  | `DUPLICATE VOLUME`. |
| ERRTAB | ErrorMessages | table | all | ErrorMessages | The error messages, each with the last character's bit 7 set, in the order of their numbers from 1. |
| ERR | ErrorSuffix | location | all | ErrorSuffix | " ERROR" and a bell, which follow every error message, ending in a zero. |
| RTMSG | RunTimeEndMessage | location | all |  | The run-time build's message after a program ends, asking for the space bar before BASIC starts again. |
| INTXT | LineNumberPrefix | location | all | LineNumberPrefix | " IN ", between an error message and its line number. |
| BRKTXT | BreakMessage | location | all | BreakMessage | The message for Control-C, with the screen turned back on and a bell. |
| ERRTBL | SosErrors | table | all |  | Pairs of a SOS error code and the BASIC error <SERROR> gives for it, in rising order of the code, ending with $FF. |
| ERRTABB | ERROR_MESSAGES_X_BYTE | error | all |  | The X-byte for <ErrorMessages> and the other messages. |
| RESLSTB | RESERVED_WORDS_X_BYTE | constant | all |  | The X-byte for <ReservedWords> and <ExtendedReservedWords>. |
| NUMSTRB | LONG_TEXT_X_BYTE | constant | all |  | The X-byte for <LongText>. |
| CON1MB | MINUS_ONE_X_BYTE | constant | all |  | The X-byte for <CON1M>, -1. |
| FHALFB | HALF_X_BYTE | constant | all |  | The X-byte for <FHALF>, one half. |
| SQR0B | LOG_CONSTANTS_X_BYTE | constant | all |  | The X-byte for <SQR0_5> and `LOG`'s other constants. |
| TEN_CB | TEN_X_BYTE | constant | all |  | The X-byte for <TEN_C>, ten, and for <FDIVF>'s divisor. |
| INTXTB | LINE_NUMBER_PREFIX_X_BYTE | constant | all |  | The X-byte for <LineNumberPrefix>. |
| N_MILB | NUMBER_LIMITS_X_BYTE | constant | all |  | The X-byte for <N_0999> and <N_9999>, the limits <FOUT> scales a number between. |
| TEMPF3B | FLOAT_TEMPORARY3_X_BYTE | constant | all |  | The X-byte for <FloatTemporary3>, in zero page. |
| RNDXB | RANDOM_VALUE_X_BYTE | constant | all |  | The X-byte for <RandomValue>, in zero page. |

### Initial.asm, B3MainC.asm, Extras.asm, SosStuf.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| INITAT | CharacterReaderTemplate | routine | all | CharacterReaderTemplate | The model of <CHRGET> and the random number seed, which <ColdStart> copies to zero page; this copy never runs |
| CHSGET | CharacterReaderTemplate | routine | all | CharacterReaderTemplate | The model of <CHRGET> and the random number seed, which <ColdStart> copies to zero page; this copy never runs |
| CHSGOT | CharacterReaderTemplate::GetCurrent | local | all | CharacterReaderTemplate::GetCurrent (CHZGOT) | Reads the character at <TXTPTR> again, without stepping first |
| CHSRT | CharacterReaderTemplate::Done | local | all | CharacterReaderTemplate::Done (CHZRTS) | Returns, with the seed after it |
| INIT | ColdStart | routine | all | ColdStart | BASIC's cold start, where SOS starts the interpreter: sets up memory, zero page and the console, then runs ... |
| NOTSEL | ColdStart::ClearZeroPage | local | all |  | Clears zero page and its X-bytes, then carries on with the start |
| MOVCHG | ColdStart::CopyCharacterReader | local | all | ColdStart::CopyCharacterReader | Copies <CharacterReaderTemplate> and the seed to <CHRGET> and <RNDX>, last byte first, clearing their X-bytes |
| nopgm1 | ColdStart::ReportDirect | local | 1.3 |  | Reports the SOS error in A as a direct command's, for 1.3's selector |
| SELLO | ColdStart::RunSelected | local | 1.3 |  | Runs the program the selector named, as <ColdStart::RunHello> runs `HELLO` |
| nopgm | ColdStart::NoProgramName | local | runtime |  | The selector named no program: the run-time version reports FILE NOT FOUND |
| nopgm | ColdStart::NoProgramName | local | 1.3 except runtime |  | The selector named no program: carries on as without the selector |
| BOOTRUN | ColdStart::RunHello | local | all |  | Runs `HELLO` if it is there; otherwise goes to the prompt, or, in the run-time version, reports the error |
| INITCNS | Console::Initialize | routine | all |  | Opens .CONSOLE and sets it up: copies its reference number and device number into BASIC's console parameter... |
| FUK2 | Console::Initialize::Failed | local | all |  | Ends with the SOS error of one of the calls |
| SICHRS | Console::SignOn | data | all |  | The sign-on <Console::Initialize> writes: console codes that set the screen up, then BASIC's name, version ... |
| SICLEN | Console::SIGN_ON_LENGTH | constant | all |  | The sign-on's length |
| P1INIT | ResetInterpreter | routine | all |  | Resets BASIC's state for a new program: no files, an empty program, nothing to report |
| FORSIZ | FOR_FRAME_SIZE | constant | all | FOR_FRAME_SIZE | The bytes a `FOR` entry takes on the stack |
| FNDFOR | FindForFrame | routine | all | FindForFrame | Finds the `FOR` entry for the variable in <FORPNT> on the stack, or the topmost `FOR` entry when <FORPNT> i... |
| FFLOOP | FindForFrame::NextFrame | local | all | FindForFrame::NextFrame | Checks the stack entry at X: stops at one that isn't a `FOR` |
| CMPFOR | FindForFrame::Compare | local | all | FindForFrame::Compare | Compares the entry's variable and type with <FORPNT> and <TEMPFOR> |
| ADDFRS | FindForFrame::SkipFrame | local | all | FindForFrame::SkipFrame | Steps to the next entry down the stack |
| FFRTS | FindForFrame::Done | local | all | FindForFrame::Done | Returns |
| BLTU | MoveRangeUp | routine | all | MoveRangeUp | Moves a block of memory up, after checking with <CheckFreeMemory> that its new top is below the strings, an... |
| BLTUC | MoveRangeUp::Unchecked | entry | all | MoveRangeUp::Unchecked | Moves the block: whole pages while a page or more is left, then the rest |
| MV256 | MoveRangeUp::MovePage | local | all |  | Moves the top page of what is left down from <HIGHTR> to <HIGHDS>, lowering both by a page |
| BLK2 | MoveRangeUp::CopyPage | local | all |  | Copies a page, from the top down |
| MVEND | MoveRangeUp::MoveRest | local | all |  | Moves the last part of a page, from <LOWTR>, lowering <HIGHDS> to its start |
| MVDONE | MoveRangeUp::Done | local | all |  | Returns |
| SUB256 | SubtractPage | routine | all |  | Lowers the three-byte pointer at X by a page, keeping its page in range |
| MVDWN | CloseGap | routine | all |  | Closes a gap: moves the memory from <INDEX1> up to <STREND> down to <LOWTR>, then adds <DELTA> to <VARTAB>,... |
| MVDWN0 | CloseGap::CheckEnd | local | all |  | Stops the loop when <INDEX1> reaches <STREND> |
| MVDWN1 | CloseGap::MoveByte | local | all |  | Moves a byte and steps both pointers, keeping their pages in range |
| MVDWN4 | CloseGap::StepDestination | local | all |  | Steps <LOWTR> |
| MVDWN3 | CloseGap::RestoreDestination | local | all |  | Gets <LOWTR> back, then adjusts the pointers |
| MVDWN2 | CloseGap::AdjustPointers | entry | all |  | Adds <DELTA> to the pointer at <VARTAB>-1+X, then to those below it |
| MVUP | OpenGap | routine | all |  | Opens a gap: moves the memory from <LOWTR> up to <STREND> up by <DELTA>, and adds <DELTA> to <STREND>, <ARY... |
| GETSTK | CheckStack | routine | all | CheckStack | Checks that the stack has room for A more two-byte entries, beyond the levels every routine may use |
| REASON | CheckFreeMemory | routine | all | CheckFreeMemory | Checks that an address is below <FRETOP>, the bottom of the strings, collecting the strings' garbage once i... |
| TRYMOR | CheckFreeMemory::Collect | local | all | CheckFreeMemory::Collect | Collects the strings' garbage and checks again |
| REASAV | CheckFreeMemory::SaveScratch | local | all | CheckFreeMemory::SaveScratch | Pushes Y, then <HIGHDS> through <LOWTR>+1, eleven bytes |
| REASTO | CheckFreeMemory::RestoreScratch | local | all | CheckFreeMemory::RestoreScratch | Pulls <HIGHDS> through <LOWTR>+1 back |
| REARTS | CheckFreeMemory::Done | local | all | CheckFreeMemory::Done | Returns |
| OSERR | StackOverflowError | routine | all |  | Ends with STACK OVERFLOW |
| OMERR | ReportOutOfMemory | routine | all | ReportOutOfMemory | Ends with OUT OF MEMORY |
| ERROR | ReportError | routine | all | ReportError | Reports error X: through `ON ERR` when the program has it in force, otherwise with a message, then goes bac... |
| ERRORR | ReportError::NameDone | local | 1.3 |  | Gets the error number back, after the program's name |
| FREALL | ReportError::FreeTemporaries | local | all |  | Frees each string temporary in use, and its string |
| DNTTRAP | ReportError::Untrapped | local | all |  | Prints error X's message and goes back to the prompt |
| FINDHERR | ReportError::FindMessage | local | all |  | Counts X down to the message in <ERRTAB> |
| CHECKHER | ReportError::SkipMessage | local | all |  | Skips one message: its last character has bit 7 set |
| GOTHER | ReportError::PrintMessage | local | all |  | Prints the message, through its last character |
| ERRFIN | ReportMessage | routine | all | ReportMessage | Prints a message, then ` IN ` and the line when a program was running, ends the line, closes any `EXEC` fil... |
| READY | ReadyForCommand | routine | all | ReadyForCommand | Goes back to the prompt after a program ends or stops, or after an error: writes out all files' buffers wit... |
| READY1 | ReadyForCommand::WaitForSpace | local | runtime |  | Waits for the space bar |
| READYGO | ReadyForCommand::Restart | local | runtime |  | Starts SOS again |
| MAIN | CommandLoop | routine | all | CommandLoop | The prompt: reads a line, then runs it at once or, when it starts with a line number, puts it into the program |
| MAIN1 | CommandLoop::EditLine | local | all | CommandLoop::EditLine (MS macro) | Puts a numbered line into the program: deletes any old line with its number first |
| NODEL | CommandLoop::InsertLine | local | all | CommandLoop::InsertLine | Inserts the new line, unless it is empty |
| STOLOP | CommandLoop::CopyLine | local | all | CommandLoop::CopyLine (NODEL1) | Copies the line, from <BUF>-3, into the gap, last byte first |
| FINI | CommandLoop::ResetAndPrompt | local | all |  | Resets the program's state after an edit, then goes back to the prompt |
| INLIN | InputLine | routine | all | InputLine | Reads a line into <BUF> with no prompt, for `INPUT` |
| INLINB | InputLine::WithPrompt | entry | all | InputLine::WithPrompt (INLIN1) | Reads a line after printing the prompt in X, or none for zero |
| GDBUFS | InputLine::Terminate | entry | all | InputLine::Terminate | Ends the line in <BUF> with a zero at X and returns <BUF>-1 for <TXTPTR> |
| GCRNCHED | Tokenizer::ToFinish | routine | all |  | Goes to <Tokenize::Finish> at the line's end, for <Tokenize>'s branch |
| CRUNCH | Tokenize | routine | all | Tokenize | Tokenizes the line in <BUF> in place, from <TXTPTR> on, and points <TXTPTR> at <BUF>-1 to run it |
| CLOOP | Tokenize::NextInput | local | all |  | Starts on the next input character, at the top of the keyword list |
| ONCRNC | Tokenize::TokenizeAgain | local | all |  | Turns tokenizing back on: A, a colon or comma, has bits 7 and 6 clear |
| CL1 | Tokenize::Classify | local | all |  | Copies the character, drops a space, or looks for a keyword |
| SHORT1 | Tokenize::CheckQuestion | local | all |  | Turns `?` into `PRINT` and keeps other punctuation and digits |
| GNMTCH | Tokenize::ToNextKeyword | local | all |  | Goes to <Tokenize::NextKeyword> for the branches |
| NPRNT | Tokenize::SearchKeywords | local | all |  | Compares the input from X with the keyword at <FAC> |
| NPR2 | Tokenize::TryKeyword | local | all |  | Starts the comparison again, with the next keyword |
| NPR3 | Tokenize::CompareNext | local | all |  | Compares the next input character, skipping spaces |
| NSPC | Tokenize::UpperCase | local | all |  | Makes a lower-case letter upper case |
| NSP2 | Tokenize::CompareCharacter | local | all |  | Compares the character with the keyword's |
| YMTCH | Tokenize::CheckBefore | local | all |  | Takes the keyword when a separator comes before it too |
| STUFIT | Tokenize::StoreToken | local | all |  | Stores A in the tokens, with the token after <TWO_BYTE_TOKEN> for a two-byte token |
| NESC | Tokenize::KeepIndex | local | all |  | Keeps the output index |
| NXCHR | Tokenize::Advance | local | all |  | Steps to the next input character, after checking whether the token just stored turns tokenizing off |
| ITDIR | Tokenize::CheckOpen | local | all |  | Checks `OPEN`, `INVOKE` and the disk commands, and `IMAGE` and `CAT` |
| ITDIR1 | Tokenize::CheckDiskCommand | local | all |  | Checks `INVOKE` and the disk commands |
| ITDIR15 | Tokenize::CopyToColon | local | all |  | Copies up to the colon: bits 7 and 6 of <DORES> set |
| ITDIR2 | Tokenize::CopyToCommaOrColon | local | all |  | Copies up to the next comma or colon after a disk command (bit 6 clear), or up to the colon after `IMAGE` a... |
| GCLOOP | Tokenize::ToNextInput | local | all |  | Goes back to <Tokenize::NextInput> |
| REMIT | Tokenize::CopyRemark | local | all |  | Copies the rest of the line after `REM` |
| DOQUOT | Tokenize::CopyUntil | local | all |  | Copies characters unchanged up to the one in A, or the line's end |
| DOQ2 | Tokenize::CopyCharacter | local | all |  | Copies a character |
| NOMTCH | Tokenize::NextKeyword | local | all |  | Steps to the next keyword in the list, or stores the character as it is when there are no more |
| FNDNXT | Tokenize::SkipKeyword | local | all |  | Skips the rest of this keyword, then adds its length to <FAC> |
| FND2 | Tokenize::CheckListEnd | local | all |  | Keeps the token number and checks for the list's end |
| CRNCHED | Tokenize::Finish | local | all |  | Ends the tokens with two zeros and points <TXTPTR> at <BUF>-1 |
| GNPR2 | Tokenize::ToTryKeyword | local | all |  | Goes to <Tokenize::TryKeyword> for the branch |
| CKSEP | Tokenizer::IsSeparator | routine | all |  | Tells whether a character separates words: anything but a letter, a digit or a period does |
| CKRT1 | Tokenizer::IsSeparator::Separator | local | all |  | Returns with carry clear: a separator |
| CKRTS | Tokenizer::IsSeparator::Done | local | all |  | Returns |
| FNDLIN | FindLine | routine | all | FindLine | Finds the line numbered <LINNUM>, or where it would go |
| FNDLNC0 | FindLine::FromLine | entry | all |  | Searches from the line at Y, X and A |
| FNDLNC1 | FindLine::FromPage | entry | all |  | Searches from the X-byte in <LOWTRB>, the page in X and the low byte in A |
| FNDLNC | FindLine::FromAddress | entry | all | FindLine::FromAddress | Searches from the line at <LOWTR>, with its low byte in A |
| AFFRTS | FindLine::NextLine | local | all | FindLine::NextLine | Steps <LOWTR> to the next line, by this one's length in X |
| FLINRT | FindLine::NotFound | local | all | FindLine::NotFound | Returns with carry clear: not found |
| FLNRTS | FindLine::Done | local | all | FindLine::Done | Returns |
| SCRATH | Statements::New | routine | all | Statements::New | The `NEW` statement: deletes the program and its variables, closing all files |
| SCRTCH | EraseProgram | routine | all | EraseProgram | Deletes the program and its variables: closes all files, resets BASIC's state with <ResetInterpreter>, then... |
| RUNC | ResetProgramState | routine | all | ResetProgramState | Gets ready to run the program from its start, for `RUN`: points <TXTPTR> before the first line, marks <CURL... |
| CLEAR | Statements::Clear | routine | all | Statements::Clear | The `CLEAR` statement: closes all files and clears the variables, the strings and the stack |
| CLEARC | ClearVariables | routine | all | ClearVariables | Closes all files and clears the variables, arrays and strings, `ERR`, `ERRLIN`, `KBD` and `EOF`, then takes... |
| CLEARL | ClearVariables::KeepFiles | entry | all |  | Clears without closing the files |
| FLOAD | ClearVariables::RestoreData | entry | all | ClearVariables::RestoreData | Takes back all memory with <EXPAND>, points `DATA` at the program's start with <RESTOR>, and resets the stack |
| STKINI | ResetStack | routine | all | ResetStack | Empties the stack, keeping only the caller's return address, and resets the formula evaluator's stacks |
| STKRTS | ResetStack::Done | entry | all | ResetStack::Done | Returns |
| STXTPT | RewindTextPointer | routine | all | RewindTextPointer | Points <TXTPTR> at the byte before the program, writing the zero there, then turns off the program's handle... |
| CLEARONS | ClearHandlers | routine | all |  | Turns off `ON KBD`, `ON EOF` and `ON ERR`, clears any key waiting in <KEYSTROK>, and leaves nothing for `RE... |
| CLEOFS | ClearHandlers::ClearNext | local | all |  | Clears <EOFPTRS>, from the top |
| SOUTREC | Statements::OutRec | routine | all |  | The `OUTREC = n` statement: sets <OUTREC>, `LIST`'s right margin |
| SINDENT | Statements::Indent | routine | all |  | The `INDENT = n` statement: sets <INDENT>, the spaces `LIST` indents each `FOR` loop by |
| CHKBYT | Statements::GetEqualsByte | routine | all |  | Reads `=` and a number from 0 to 255, for the statements that set a value |
| HTAB | Statements::HPos | routine | all | Statements::HTab (keyword HTAB) | The `HPOS = n` statement: moves the cursor to column n, counting from 1, and records it in <TRMPOS> |
| TOOBIG | Statements::ToIllegalQuantity | routine | all |  | Ends with ILLEGAL QUANTITY, for `TAB(0)` |
| HTABB | Statements::MoveToColumn | routine | all |  | Moves the cursor to the column after `=`, for <Statements::HPos> |
| VTAB | Statements::VPos | routine | all | Statements::VTab (keyword VTAB) | The `VPOS = n` statement: moves the cursor to line n, counting from 1 |
| VWINDER | Console::SendCodeAndPosition | routine | all |  | Sends a console code and its argument, counting from 1, which the console counts from 0 |
| SETNORM | Statements::Normal | routine | all | Statements::Normal | The `NORMAL` statement: sets normal video |
| INVERSE | Statements::Inverse | routine | all | Statements::Inverse | The `INVERSE` statement: sets inverse video |
| SETTRACE | Statements::Trace | routine | all | Statements::Trace | The `TRACE` statement: sets bit 7 of <TRFLAG>, so the statement fetcher prints each line's number as it runs |
| TRACEOFF | Statements::NoTrace | routine | all | Statements::NoTrace | The `NOTRACE` statement: clears bit 7 of <TRFLAG> |
| RTSBCK | Statements::NoTrace::Done | entry | all |  | Returns |
| ONERR | Statements::OnErr | routine | all | Statements::OnErr | The `ON ERR statements` statement: makes the statements after `ERR`, to the end of the line, the program's ... |
| HNDLERR | TrapError | routine | all | TrapError | Runs the `ON ERR` handler: <ReportError> comes here when bit 7 of <ERRFLG> is set |
| RESUME | Statements::Resume | routine | all | Statements::Resume | The `RESUME` statement: runs the statement that failed again, from <ERRPOS> in line <ERRLIN> |
| RSM2 | Statements::Resume::Done | local | all |  | Returns, to the statement fetcher |
| TRYESC | MatchTwoByteToken | routine | all |  | Tests whether the program has a two-byte token, <TWO_BYTE_TOKEN> and A, at <TXTPTR>, and steps over the fir... |
| TRY2 | MatchTwoByteToken::Reread | local | all |  | Reads the character at <TXTPTR> again, keeping the flags |
| MSTESC | RequireTwoByteToken | routine | all |  | Requires the two-byte token <TWO_BYTE_TOKEN> and A next, and steps past it |
| ONKBD | Statements::OnKbd | routine | all |  | The `ON KBD statements` statement: makes the statements after `KBD` the handler for a key pressed while the... |
| ONEOF | Statements::OnEof | routine | all |  | The `ON EOF#n statements` statement: makes the statements after the file number the handler for reaching th... |
| ONEOF2 | Statements::OnEof::SetHandler | entry | all |  | Records handler X: where the statements start, relative to <TXTTAB>, in <EOFPTRS>, and the line in <EOFLINS... |
| RELTXT | Handlers::ToggleOffset | routine | all |  | Turns <TXTPTR> into an offset from <TXTTAB>, or such an offset back into an address |
| OFF | Statements::Off | routine | all |  | The `OFF` statement: `OFF KBD`, `OFF EOF#n` or `OFF ERR` turns that handler off |
| RTS999 | Statements::Off::Done | local | all |  | Returns |
| OFFKBD | Statements::OffKbd | routine | all |  | `OFF KBD`: turns the console's any-key event off and clears handler <Handlers::KEYBOARD> |
| OFFEOF | Statements::OffEof | routine | all |  | `OFF EOF#n`: turns the file's `ON EOF#` handler off |
| OFFEOF2 | Statements::OffEof::ClearHandler | entry | all |  | Clears handler X in <EOFPTRS> |
| CHKEOF | Handlers::EndOfFile | routine | all |  | Goes to the `ON EOF#` handler of the file in <SVFLNO>, which reached its end, or ends with OUT OF DATA when... |
| CKEOF2 | Handlers::EndOfFile::GoToHandler | entry | all |  | Goes to handler X/3 in <EOFPTRS>, or ends with OUT OF DATA when there is none |
| GIVOD | Handlers::EndOfFile::NoHandler | local | all |  | Ends with OUT OF DATA |
| KEYHIT | Handlers::KeyPressed | routine | all |  | Calls the `ON KBD` handler as a `GOSUB`: the statement fetcher comes here when bit 7 of <KEYSTROK> says the... |
| BLOWDEL | Statements::ToSyntaxError | routine | all |  | Ends with SYNTAX, for <Statements::Del> |
| DELETE | Statements::Del | routine | all | Statements::Del (keyword DEL) | The `DELETE first[,last]` statement: deletes a line, or the lines from first to last, from the program |
| RNGERR | Statements::Del::ReportRange | entry | all |  | Ends with RANGE |
| RNGOK | Statements::Del::RangeChecked | local | all |  | Reads the range's end and deletes the lines |
| DELOK | Statements::Del::ReadLast | local | all |  | Reads the last line's number |
| JSONEL | Statements::Del::FindEnd | local | all |  | Finds the first line after the range, and moves what follows it down to the range's start |
| MSETTXT | Statements::Text | routine | all | Statements::Text | The `TEXT` statement: puts the console back in its text mode, with the whole screen, normal video and the s... |
| TXTOUT | Statements::Text::NextCode | local | all |  | Writes <Statements::TextCodes> to the console, up to its zero |
| TXTRTS | Statements::Text::Done | entry | all |  | Returns |
| HOME | Statements::Home | routine | all |  | The `HOME` statement: clears the viewport and puts the cursor at its top left |
| TXTCHRS | Statements::TextCodes | data | all |  | The console codes `TEXT` writes, ending in a zero: 80-column text mode with the cursor off, the text option... |
| OPNCNST | Console::OpenParameters | location | all |  | OPEN's parameter list for .CONSOLE: the name <Console::Name>, the reference number back in <Console::Refere... |
| CONSRFN | Console::Reference | location | all |  | The console's reference number, from OPEN; <Console::Initialize> copies it into the console's other lists |
| CONSFN | Console::Name | data | all |  | The console's name, `.CONSOLE`, with its length first |
| SINIT | Console::WriteParameters | location | all |  | WRITE's parameter list for text to the console, first the sign-on: the console's reference number, the text... |
| SPRNTPL | Console::WriteAddress | location | all |  | The text's address, in <Console::WriteParameters> |
| OUTSTRL | Console::WriteLength | location | all |  | The text's length, in <Console::WriteParameters> |
| ISNLTB | Console::NewlineParameters | location | all |  | NEWLINE's parameter list: the console's reads end at a carriage return |
| RDCTC | Console::KeyParameters | location | all |  | READ's parameter list for one key, into <KEYSAVE>: the console's or, while `EXEC` runs, the `EXEC` file's r... |
| GETREF | Console::KeyReference | location | all |  | The reference number <Console::KeyParameters> reads from |
| RFLUSH | Console::FlushAllParameters | location | all |  | FLUSH's parameter list: one parameter, reference number 0, which flushes every open file |
| RNDGOT | Console::KeyTransferred | location | all |  | READ's count of bytes read, in <Console::KeyParameters>, which BASIC ignores |
| SCHRTB | Console::CharacterParameters | location | all |  | WRITE's parameter list for one character, <Console::Character>, to the console |
| OUTCHAR | Console::Character | location | all |  | The character <Console::CharacterParameters> writes |
| SLINTB | Console::LineParameters | location | all |  | READ's parameter list for a line from the console into <BUF>, up to <INALLWD> characters |
| SNOCHRS | Console::LineLength | location | all |  | The count of characters <Console::LineParameters>'s READ returned |
| DINIT | Console::ResetParameters | location | all |  | D_CONTROL's parameter list for <Console::CONTROL_RESET>, which resets the console |
| INDN | Console::ResetDevice | location | all |  | The console's device number, in <Console::ResetParameters>; <Console::Initialize> copies it from <Console::... |
| DGCN | Console::DeviceNumberParameters | location | all |  | GET_DEV_NUM's parameter list for .CONSOLE, which returns its device number in <Console::Device> |
| OTDN | Console::Device | location | all |  | The console's device number, from GET_DEV_NUM |
| DKBD | Console::AnyKeyParameters | location | all |  | D_CONTROL's parameter list for <Console::CONTROL_ANY_KEY>, the any-key event, from <Console::AnyKeyEvent> |
| INDN3 | Console::AnyKeyDevice | location | all |  | The console's device number, in <Console::AnyKeyParameters> |
| KBDKEY | Console::AnyKeyEvent | location | all |  | The any-key event: its priority (0 turns it off), its ID, the handler <Console::AnyKeyHandler> and its bank... |
| KBDBNK | Console::AnyKeyBank | location | all |  | The bank of <Console::AnyKeyHandler>, set to BASIC's own bank at start |
| DCNTR | Console::AttentionParameters | location | all |  | D_CONTROL's parameter list for <Console::CONTROL_ATTENTION>, the attention event, from <Console::AttentionE... |
| INDN2 | Console::AttentionDevice | location | all |  | The console's device number, in <Console::AttentionParameters> |
| DCCPRI | Console::AttentionEvent | location | all |  | The attention event: its priority (0 turns it off), its ID, the handler <Console::AttentionHandler>, its ba... |
| DCNTBNK | Console::AttentionBank | location | all |  | The bank of <Console::AttentionHandler>, set to BASIC's own bank at start |
| DFLUSH | Console::FlushTypeAheadParameters | location | all |  | D_CONTROL's parameter list for <Console::CONTROL_FLUSH_TYPE_AHEAD>, which empties the type-ahead buffer |
| INDN6 | Console::FlushTypeAheadDevice | location | all |  | The console's device number, in <Console::FlushTypeAheadParameters> |
| DECHO | Console::EchoParameters | location | all |  | D_CONTROL's parameter list for <Console::CONTROL_ECHO>, which sets the echo flags from <Console::EchoFlags> |
| INDN4 | Console::EchoDevice | location | all |  | The console's device number, in <Console::EchoParameters> |
| ECHOFLG | Console::EchoFlags | location | all |  | The echo flags for <Console::EchoParameters>: <Console::ECHO_ON> echoes keys to the screen, 0 does not |
| REDCUR | Console::CursorParameters | location | all |  | D_STATUS's parameter list for <Console::STATUS_CURSOR>, the cursor's position, into <Console::CursorColumn>... |
| INDN5 | Console::CursorDevice | location | all |  | The console's device number, in <Console::CursorParameters> |
| CURX | Console::CursorColumn | location | all |  | The cursor's column, from <Console::CursorParameters> |
| CURY | Console::CursorLine | location | all |  | The cursor's line, from <Console::CursorParameters> |
| CTCOFF | Console::AttentionOff | routine | all |  | Turns the attention event off, so CONTROL-C reads as a key, then arms it with <Console::AttentionOn>'s call |
| CTCON | Console::AttentionOn | routine | all |  | Arms the attention event from <Console::AttentionEvent>, then gives it <Console::EVENT_PRIORITY> again for ... |
| KBDEVNT | Console::AnyKeyHandler | routine | all |  | The any-key event's handler: sets <Console::KEY_SEEN> in <KEYSTROK> and reads the key |
| CTCEVNT | Console::AttentionHandler | routine | all |  | The attention event's handler: sets <Console::CONTROL_C_SEEN> in <KEYSTROK> for CONTROL-C and reads the key... |
| DOAGET | Console::ReadKey | routine | all |  | Reads one key into <KEYSAVE> with echo and CONTROL-C off, from <Console::KeyReference>'s file |
| ECHOON | Console::EchoOn | routine | all |  | Turns the console's echo on, then arms the attention event again |
| ECHOFF | Console::EchoOff | routine | all |  | Turns the console's echo off, then arms the attention event again |
| GOSOS | SosCalls::Call | routine | all |  | Makes the SOS call <SosCalls::SetUp> chose, with the parameters in <SosCalls::Parameters> |
| SCN | SosCalls::Call::Number | local | all |  | The call number the BRK makes, which <SosCalls::SetUp> sets |
| SOSRTS | SosCalls::Call::Done | entry | all |  | Returns |
| SOSTBL | SosCalls::Parameters | location | all |  | The parameter list every file call shares: the count, which <SosCalls::SetUp> sets, then the parameters |
| PTHPTR | SosCalls::Pathname | location | all |  | The first parameter: a pathname's address, or a reference number |
| RWRFNM | SosCalls::Reference | alias | all |  | The file's reference number, for `READ`, `WRITE` and the mark calls |
| NWLNB | SosCalls::NewlineEnabled | alias | all |  | NEWLINE's on-or-off flag |
| SBFPTR | SosCalls::Buffer | alias | all |  | READ's and WRITE's buffer address |
| BASE | SosCalls::MarkBase | alias | all |  | SET_MARK's base: from the start, the mark or the end |
| OUTMRK | SosCalls::Mark | alias | all |  | The mark or end of file a call returns |
| ISRCHMD | SosCalls::SearchMode | alias | all |  | FIND_SEG's search mode |
| ISEGID | SosCalls::SegmentId | alias | all |  | FIND_SEG's segment ID |
| SEGNUM | SosCalls::ReleasedSegment | alias | all |  | RELEASE_SEG's segment number |
| JMODE | SosCalls::JoystickMode | alias | all |  | The joystick call's mode |
| CRTLST | SosCalls::CreateOptions | location | all |  | The second parameter: CREATE's option list's address, or another call's |
| NWPTHNM | SosCalls::NewPathname | alias | all |  | RENAME's new pathname |
| FLSTPTR | SosCalls::InformationAddress | alias | all |  | The file information list's address |
| REFOUT | SosCalls::OpenedReference | alias | all |  | The reference number OPEN returns |
| OPNLST | SosCalls::OpenOptions | alias | all |  | OPEN's option list's address |
| NLCHR | SosCalls::NewlineCharacter | alias | all |  | NEWLINE's character |
| INBYTES | SosCalls::Request | alias | all |  | The count `READ` or `WRITE` moves |
| DSPLMNT | SosCalls::Displacement | alias | all |  | SET_MARK's displacement |
| IOPGCN | SosCalls::PageCount | alias | all |  | FIND_SEG's page count |
| INLNGTH | SosCalls::CreateOptionsLength | location | all |  | The third parameter: CREATE's option list's length |
| OPNLNGTH | SosCalls::OpenOptionsLength | location | all |  | OPEN's option list's length |
| OUTBYTES | SosCalls::Transferred | alias | all |  | The count `READ` really moved |
| BSBNKP | SosCalls::SegmentBase | alias | all |  | FIND_SEG's base bank and page |
| OSEGNM | SosCalls::SegmentNumber | location | all |  | FIND_SEG's segment number |
| CRTTBL | SosCalls::NewFileOptions | location | all |  | CREATE's option list: the file type, the auxiliary type and the storage type, a <SosCalls::FileOptions> |
| INFLID | SosCalls::NewFileType | location | all |  | The file type CREATE gives the file |
| INAUXID | SosCalls::NewFileAuxType | location | all |  | The auxiliary type CREATE gives the file; BASIC puts a data file's record length here |
| INSTRTYP | SosCalls::NewFileStorageType | location | all |  | The storage type CREATE gives the file: a seedling |
| INEOF | SosCalls::NewFileEnd | location | all |  | CREATE's end of file, which BASIC never sets |
| FATRB | SosCalls::FileAccess | location | all |  | GET_FILE_INFO's and SET_FILE_INFO's information list, a <SosCalls::FileInformation>: the access bits first |
| FID | SosCalls::FileType | location | all |  | The file's type |
| FAUX | SosCalls::FileAuxType | location | all |  | The file's auxiliary type |
| FSTYP | SosCalls::FileStorageType | location | all |  | The file's storage type |
| FEOF | SosCalls::FileEnd | location | all |  | The file's end, four bytes |
| FBLKS | SosCalls::FileBlocks | location | all |  | The file's count of blocks |
| INREQ | SosCalls::OpenAccess | location | all |  | OPEN's option list: the access requested, 1 to read, from `LOAD`, or 2 to read and write, from `SAVE` |
| HELF | SosCalls::HelloInformation | location | all |  | GET_FILE_INFO's parameter list for `HELLO`, which tells <ColdStart> whether there is a program to run |
| HELCN | SosCalls::HelloName | data | all |  | `HELLO`, the program BASIC runs at start, with a zero after |
| GETFI | SosCalls::GetFileInfo | routine | all |  | Gets a file's information into <SosCalls::FileAccess>, after <GETFISET> sets the call up |
| SETGO | SosCalls::MakeFileCall | routine | all |  | Makes a file call from <SosCalls::Parameters>, ending the statement with the error, if any |
| SETUP | SosCalls::SetUp | routine | all |  | Sets <SosCalls::Call> up for a file call: its number, and its parameter count in <SosCalls::Parameters> |
| NOWRTS | SosCalls::SetUp::Done | entry | all |  | Returns |
| CRT | SosCalls::CALL_CREATE | constant | all |  | CREATE's index |
| DST | SosCalls::CALL_DESTROY | constant | all |  | DESTROY's index |
| RNM | SosCalls::CALL_RENAME | constant | all |  | RENAME's index |
| SFI | SosCalls::CALL_SET_FILE_INFO | constant | all |  | SET_FILE_INFO's index |
| GFI | SosCalls::CALL_GET_FILE_INFO | constant | all |  | GET_FILE_INFO's index |
| OPN | SosCalls::CALL_OPEN | constant | all |  | OPEN's index |
| NWL | SosCalls::CALL_NEWLINE | constant | all |  | NEWLINE's index |
| RED | SosCalls::CALL_READ | constant | all |  | READ's index |
| WRT | SosCalls::CALL_WRITE | constant | all |  | WRITE's index |
| CLS | SosCalls::CALL_CLOSE | constant | all |  | CLOSE's index |
| STM | SosCalls::CALL_SET_MARK | constant | all |  | SET_MARK's index |
| GTM | SosCalls::CALL_GET_MARK | constant | all |  | GET_MARK's index |
| RLS | SosCalls::CALL_RELEASE_SEG | constant | all |  | RELEASE_SEG's index |
| FND | SosCalls::CALL_FIND_SEG | constant | all |  | FIND_SEG's index |
| STE | SosCalls::CALL_SET_EOF | constant | all |  | SET_EOF's index |
| PDL | SosCalls::CALL_JOYSTICK | constant | all |  | The joystick call's index |
| SCNUMT | SosCalls::CallNumbers | table | all |  | The SOS call number of each file call, by its index |
| PCNTT | SosCalls::ParameterCounts | table | all |  | The parameter count of each file call, in <SosCalls::CallNumbers>'s order |
| SPROGPFX | ProgramPrefix::StripFileName | routine | 1.3 |  | Strips the file name from <PROGPATH>, leaving the prefix up to its last slash |
| PRGLP | ProgramPrefix::StripFileName::FindSlash | local | 1.3 |  | Steps back to the last slash |
| PRGRTS | ProgramPrefix::StripFileName::Done | entry | 1.3 |  | Returns |
| SETSOS | ProgramPrefix::UseSos | routine | 1.3 |  | Sets SOS's prefix back to BASIC's, from <SOSPATH> |
| SETPROG | ProgramPrefix::UseProgram | routine | 1.3 |  | Sets SOS's prefix to the program's, from <PROGPATH>; after `RUN` or `CHAIN`, it takes the new program's first |
| SETPFX | ProgramPrefix::Set | routine | 1.3 |  | Sets SOS's prefix to the pathname <ProgramPrefix::Pathname> points to, ending the statement with an error if it fails |
| MPERR | ProgramPrefix::Set::Failed | entry | 1.3 |  | Ends the statement with the prefix call's error |
| FILSOS | ProgramPrefix::SaveSos | routine | 1.3 |  | Copies SOS's prefix into <SOSPATH>, through <CATBUF> |
| FILPROG | ProgramPrefix::TakeFromName | routine | 1.3 |  | Takes the program's prefix from the name in <NAMBUF> when it is a full pathname (starting with `.` or `/`),... |
| FILPROG2 | ProgramPrefix::TakeFromName::CopyPathname | local | 1.3 |  | Copies the full pathname in <NAMBUF> into <PROGPATH> and strips its file name |
| FILPROG1 | ProgramPrefix::TakeFromName::Taken | local | 1.3 |  | Clears <CMDFLG>: the prefix is taken |
| COPYSOS | ProgramPrefix::CopySosToProgram | routine | 1.3 |  | Copies SOS's prefix from <SOSPATH> to <PROGPATH>, for a program run without the selector |
| CNVTPFX1 | ProgramPrefix::ToVolumeName | routine | 1.3 |  | Makes <PROGPATH> name the volume rather than the device: sets it as SOS's prefix and reads the prefix back,... |
| SHFTPFX | ProgramPrefix::Pathname | location | 1.3 |  | The pathname's address, for <ProgramPrefix::Set> and <ProgramPrefix::ToVolumeName>, then GET_PREFIX's buffer length |

### B3ListD.asm, B3GotoE.asm, B3InpuF.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| LIST | Statements::List | routine | all | Statements::List | The `LIST` statement: lists the program, or the lines in a range, turning tokens back into words. |
| LXZYQ | Statements::List::ToProgramEnd | local | all |  | Lists to the end of the program: sets the last line's number to $FFxx. |
| GOLS1 | Statements::List::CheckRange | local | all |  | Reads the rest of the range: a terminator lists the one line, a dash, comma or `TO` reads the last line's number. |
| LSTOK | Statements::List::ReadLastLine | local | all |  | Reads the last line's number after the dash, comma or `TO`; nothing there lists to the end. |
| LSTEND | Statements::List::StartListing | local | all | Statements::List::StartListing | Starts the listing at the line <FNDLIN> found, through <VARNAM>. |
| LIST4 | Statements::List::NextLine | local | all | Statements::List::NextLine | Lists the line at <VARNAM>, unless it is past the last line asked for or the program has ended. |
| TSTDUN | Statements::List::CheckPastEnd | local | all | Statements::List::CheckPastEnd | Ends the listing when the line's number is past the last one's. |
| TYPLIN | Statements::List::ListLine | local | all | Statements::List::ListLine | Prints the line number and the indentation, then the text. |
| PLOOP1 | Statements::List::IndentLevel | local | all |  | Prints <DELTA>+1 spaces, once for each of <INDENT>'s spaces per level. |
| PLOOP0 | Statements::List::IndentSpace | local | all |  | Prints one space of the level's indentation. |
| PLOOP3 | Statements::List::SetMargin | local | all |  | Notes the column the text starts in, as the margin for wrapped text. |
| PLOOP5 | Statements::List::CheckQuote | local | all |  | Prints a character of the line, or starts a quoted string at a quote. |
| PLOOP | Statements::List::ListCharacter | local | all | Statements::List::ListCharacter | Prints a character of the line. |
| PLOOP2 | Statements::List::NextByte | local | all | Statements::List::NextByte | Takes the line's next byte: a zero ends the line. |
| PLOOP8 | Statements::List::NextLineLink | local | all |  | Moves <VARNAM> past the line's zero to the next line's link, into the next bank past <MAXPG>, and lists it. |
| GETNXTW | Statements::List::NextTableByte | local | all | Statements::List::NextTableByte | Reads the next byte of a reserved-word list, through the pointer in <FAC>. |
| LSTRTS | Statements::List::Done | local | all |  | Returns, for the listing's branches. |
| GREEDY | Statements::List::Finish | local | all | Statements::List::Finish | Ends the listing with a RETURN. |
| PLOOP7 | Statements::List::QuotedString | local | all |  | Prints a quoted string as it is, up to its closing quote or the end of the line. |
| QPLOP | Statements::List::CheckToken | local | all | Statements::List::CheckToken | Prints a character, or a token as its reserved word. |
| NOTSPEC0 | Statements::List::Outdent | local | all |  | Takes a level away for each of `NEXT`'s variables, never below zero. |
| NOTSPEC2 | Statements::List::FindComma | local | all |  | Looks for another of `NEXT`'s variables, after a comma, up to the end of the statement. |
| NOTSPEC3 | Statements::List::ReloadToken | local | all |  | Takes `NEXT`'s token back. |
| NOTSPEC4 | Statements::List::PointAtWords | local | all |  | Points <FAC> at the reserved words: <RESLST> for a one-byte token, <RESL2> for an escape token's second byte. |
| NRMTKN | Statements::List::CountWords | local | all |  | Finds the token's word in the list: the token's number, less <FIRST_TOKEN>, counts the words to pass. |
| RESRCH | Statements::List::FindWord | local | all | Statements::List::FindWord | Counts down the words to pass; at zero, the word is found. |
| RESCR1 | Statements::List::SkipWord | local | all | Statements::List::SkipWord | Passes one word, up to its last character's set bit 7. |
| PRIT25 | Statements::List::SpaceBefore | local | all |  | Decides whether a space goes before the word, from what comes before the token. |
| PRIT26 | Statements::List::CheckPrevious | local | all |  | Looks at the byte before the token: carry is set for a colon or a token. |
| PRIT27 | Statements::List::SpaceUnlessCarry | local | all |  | Prints the space before the word unless carry says not to. |
| PRIT3 | Statements::List::ListWord | local | all | Statements::List::ListWord | Prints the word, then its last character without bit 7. |
| PRFINIS | Statements::List::LastCharacter | local | all |  | Prints the word's last character, then a space when the word ends in a letter and a token, a letter, a digit or a |
| PRF2 | Statements::List::SpaceAfter | local | all |  | Prints the space after the word. |
| JPL2 | Statements::List::AfterToken | local | all |  | Goes on with the byte after the token. |
| PNTREL | Variables::SimpleVariableOffset | routine | all |  | Turns the variable pointer in <FORPNT> into an offset from the simple variables' start, <SMVARS>, or back again. |
| PNTRL1 | Variables::SimpleVariableOffset::OfPointerAtX | entry | all |  | Takes the pointer at the zero-page address in X, and returns with X = <KIMY>. |
| FOR | Statements::For | routine | all | Statements::For | The `FOR` statement: assigns the loop variable its first value and puts the loop's entry, a <ForEntry>, on the stack. |
| NOTOL | Statements::For::BuildFrame | local | all | Statements::For::BuildFrame | Builds the new entry, starting with the text pointer and line number <PushGoSubEntryHere> pushes, then reads `TO` |
| LDFONE | Statements::For::ReadStep | local | all | Statements::For::ReadStep | Pushes the rest of the entry: the step (1 when there is no `STEP`) and its sign, the variable's offset, its type and |
| ONEON | Statements::For::PushStep | local | all | Statements::For::PushStep | Pushes the step and its sign, then the variable's offset, type and <FORTK>. |
| NEWSTT | NextStatement | routine | all | NextStatement | The statement loop: runs the next statement, from where <TXTPTR> stands. |
| NWSTT | NextStatement::SavePlace | entry | all |  | Keeps <TXTPTR> in <OLDTXT> for `CONT`, without checking for a terminator. |
| DIRCON | NextStatement::CheckEvents | entry | all |  | Takes a pending CONTROL-C or key, then moves to the next statement, or the next line's at the end of a line. |
| CHKPGE | NextStatement::KeepPageInRange | local | all |  | Brings <TXTPTR>'s page back below <MAXPG>, moving it into the next bank. |
| GONE | ExecuteStatement | routine | all | ExecuteStatement | Runs the statement after <TXTPTR>, tracing it first when `TRACE` is on, then goes on to the next. |
| GOFORIT | ExecuteStatement::Dispatch | local | all |  | Reads the statement's first byte and runs it. |
| NEWRET | ExecuteStatement::StatementReturn | alias | all |  | The return address <ExecuteStatement::Dispatch>'s JSR pushes, the byte before the JMP back to <NextStatement>. |
| SNERR1 | ExecuteStatement::ToSyntaxError | local | all | CheckStatementSeparator::ToSyntaxError | Ends the statement with a syntax error. |
| ISAKEY | ExecuteStatement::ToKeyHandler | local | all |  | Runs the `ON KBD` line for a key. |
| ISCTRLC | ExecuteStatement::ToBreak | local | all |  | Stops the program for CONTROL-C, through <HandleBreak>, which does not come back. |
| GONE3 | DispatchStatement | routine | all | DispatchStatement | Runs a statement: a token from `END` to `NEW` goes to its handler from <STMDSP>, anything else is a `LET`. |
| INTERM | DispatchStatement::ToEndOfProgram | entry | all | ExecuteStatement::ToEndOfProgram | Ends the program at a zero link, as `END` does. |
| GLET | DispatchStatement::ToLet | local | all | DispatchStatement::ToLet | Runs a statement without a keyword as `LET`. |
| RESTOR | Statements::Restore | routine | all | Statements::Restore | The `RESTORE` statement: points <DATPTR> at the zero before the program, so `READ` starts at the first `DATA` again. |
| RESFIN | Statements::Restore::SetDataPointer | entry | all | Statements::Restore::SetDataPointer | Sets <DATPTR>; `READ` comes here with where its data ended. |
| ISCRTS | Statements::Restore::Done | entry | all | Statements::Restore::Done | Returns, for branches. |
| ISCNTC | HandleBreak | routine | all | HandleBreak | Stops the program for CONTROL-C, with BREAK, or goes to `ON ERR`'s line with error <ERROR_BREAK>. |
| ISCNTC2 | HandleBreak::WithFlags | entry | all |  | Takes the flags in A; `INPUT` comes here with <CONTROL_C> for a CONTROL-C typed at its prompt. |
| ISRESET | HandleBreak::Stop | local | all |  | Stops with BREAK, printing to the console. |
| END | Statements::End | routine | all | Statements::End | The `END` statement: stops the program without a message. |
| STOP | Statements::Stop | routine | all | Statements::Stop | The `STOP` statement: stops the program with BREAK. |
| STOP2 | Statements::StopOrEnd | routine | all | Statements::StopOrEnd | Stops the program: keeps <TXTPTR> and <CURLIN> in <OLDTXT> and <OLDLIN> for `CONT` (not for a direct line), then goes |
| DIRIS | Statements::StopOrEnd::DiscardReturn | local | all | Statements::StopOrEnd::DiscardReturn | Drops the return address to <NextStatement>. |
| ENDCON | Statements::StopOrEnd::Finish | entry | all | Statements::StopOrEnd::Finish | Goes to <READY>, through BREAK's message when carry is set. |
| GORDY | Statements::StopOrEnd::ToReady | local | all | Statements::StopOrEnd::ToReady | Goes to <READY>. |
| CONT | Statements::Cont | routine | all | Statements::Cont | The `CONT` statement: goes on from where `STOP`, `END`, CONTROL-C or an error stopped the program. |
| CONTRT | Statements::Cont::Done | entry | all | Statements::Cont::Done | Returns, for the statements' checks. |
| COLD | Statements::Bye | routine | all |  | The `BYE` statement: closes the files and leaves BASIC through SOS's TERMINATE call. |
| COLD1 | Statements::Bye::CloseAndTerminate | entry | all |  | Closes the files and terminates. |
| RUN | Statements::Run | routine | all | Statements::Run | The `RUN` statement: runs the program from its start, from a line (`RUN n` or `RUN ,n`), or loads a program first. |
| RUNL2 | Statements::Run::AfterComma | local | all |  | Runs from the line after the comma. |
| RUNL | Statements::Run::FromLine | local | all |  | Clears the variables and the stack (<CLEARC> resets it, taking <NextStatement>'s return address), then goes to the |
| PSHTXT | PushGoSubEntry | routine | all |  | Puts a <GoSubEntry> on the stack, below the caller's return address and the one above it, after checking for room. |
| PSHTXT2 | PushGoSubEntry::WithoutRoomCheck | entry | all |  | Does not check for room. |
| PSHTRT | PushGoSubEntry::Done | entry | all |  | Returns, for branches. |
| PSHTXT3 | PushGoSubEntryHere | routine | all |  | Pushes a <GoSubEntry> at the caller's own level, without checking for room; `FOR` uses it. |
| PSHTXT4 | PushGoSubEntryHereChecked | routine | all |  | Pushes a <GoSubEntry> at the caller's own level, after checking for room; `ON KBD` uses it. |
| GOSUB | Statements::GoSub | routine | all | Statements::GoSub | The `GOSUB` statement: puts a <GoSubEntry> on the stack, then goes to the line as `GOTO` does. |
| RUNC2 | Statements::GoSub::Transfer | entry | all | Statements::GoSub::Transfer | Goes to the line whose number is at <TXTPTR>, returning to <NextStatement> to run it. |
| GOTO | Statements::GoTo | routine | all | Statements::GoTo | The `GOTO` statement: points <TXTPTR> at the zero before the line with the number given, so <NextStatement> runs it. |
| GOTOB | Statements::GoTo::ToLineNumber | entry | all |  | Finds the line numbered <LINNUM> and points <TXTPTR> at the zero before its link. |
| LUK4IT | Statements::GoTo::SearchFromStart | entry | all | Statements::GoTo::SearchFromStart | Searches from the program's first line. |
| LUKALL | Statements::GoTo::Search | local | all | Statements::GoTo::Search | Searches from the line at A, X, Y (low, high, bank), then points <TXTPTR> one byte before the line found. |
| GORTS | Statements::GoTo::Done | local | all | Statements::GoTo::Done | Returns, for the statements here. |
| DATAIS | Statements::Data | routine | all |  | The `DATA` statement: in a program, passes over the statement as `REM` does; in a direct line, an error. |
| RETURN | Statements::Return | routine | all | Statements::Return | The `RETURN` statement, and `POP`: takes the newest <GoSubEntry> off the stack, with any `FOR` entries above it. |
| USERR | Statements::Return::UndefinedStatement | entry | all | Statements::Return::UndefinedStatement | Ends the statement with UNDEF'D STATEMENT. |
| RETU1 | Statements::Return::RestoreCaller | local | all | Statements::Return::RestoreCaller | Takes the entry off: the stack is cut to it, which drops <NextStatement>'s return address and the `FOR` entries, and |
| DATA | SkipStatement | routine | all |  | Moves <TXTPTR> to the end of the statement: a colon or the line's zero, outside quotes. |
| ADDON | AdvanceTextPointer | routine | all | AdvanceTextPointer | Adds Y to <TXTPTR>, into the next bank past <MAXPG>. |
| REMRTS | AdvanceTextPointer::Done | entry | all | AdvanceTextPointer::Done | Returns, for the skips; a statement returns from here to <NextStatement>. |
| SNERR2 | AdvanceTextPointer::ToSyntaxError | entry | all | Statements::Return::ToSyntaxError | Ends the statement with a syntax error. |
| REM | Statements::Rem | routine | all | Statements::Rem | The `REM` statement: moves <TXTPTR> to the end of the line. |
| DATAN | FindStatementEnd | routine | all | FindStatementEnd | Finds the end of the statement: a colon or a zero, outside quotes. |
| REMN | FindLineEnd | routine | all | FindLineEnd | Finds the end of the line: its zero. |
| EXCHQT | FindLineEnd::SwapDelimiters | local | all | FindLineEnd::SwapDelimiters | Swaps the end characters, at the start and at each quote. |
| REMER | FindLineEnd::NextCharacter | local | all | FindLineEnd::NextCharacter | Scans for a zero or <ENDCHR>, swapping at each quote. |
| DOPOP | Statements::PopFinish | routine | all | Statements::PopFinish | Ends `POP`: drops the rest of the <GoSubEntry> and goes on after `POP`. |
| ONGOTO | Statements::On | routine | all | Statements::On | The `ON` statement: `ON ERR`, `ON KBD` and `ON EOF#` go to their own handlers; otherwise `ON n GOTO` or |
| ONGOTO2 | Statements::On::ReadIndex | local | all |  | Reads n and the `GOTO` or `GOSUB` after it. |
| SNERR3 | Statements::On::RequireGoto | entry | all | Statements::On::RequireGoto | Ends the statement with a syntax error unless A is `GOTO`'s token. |
| ONGLOP | Statements::On::NextEntry | local | all | Statements::On::NextEntry | Counts n down, passing a line number for each step; at zero, goes to the line that follows. |
| DOONGT | Statements::On::GoToEntry | local | all |  | Reads the line number after <TXTPTR> and goes to it through <Statements::GoTo::ToLineNumber>. |
| ONGLP1 | Statements::On::SkipEntry | local | all | Statements::On::SkipEntry | Passes a line number of the list, and goes on at a comma; at the list's end, `ON` does nothing. |
| ONGRTS | Statements::On::Done | entry | all | Statements::On::Done | Returns, for `ON` and <ReadLineNumber>. |
| GOERR | Statements::On::ToOnError | local | all |  | `ON ERR`. |
| GOKBD | Statements::On::ToOnKeyboard | local | all |  | `ON KBD`. |
| LINGET | ReadLineNumber | routine | all | ReadLineNumber | Reads a line number, 0 to 63999, from the text into <LINNUM>; with no digit there, LINNUM is 0. |
| MORLIN | ReadLineNumber::NextDigit | local | all | ReadLineNumber::NextDigit | Adds a digit to <LINNUM>, unless the character is not a digit. |
| NXTLGC | ReadLineNumber::NextCharacter | local | all | ReadLineNumber::NextCharacter | Reads the next character. |
| LET | Statements::Let | routine | all | Statements::Let | The `LET` statement, and any statement without a keyword: evaluates the formula after `=` and assigns it. |
| LETP2 | AssignFac | routine | all |  | Assigns the value in the <FAC> to the variable at <FORPNT>, as `LET` does; the disk statements and `INPUT` use it. |
| LETP3 | AssignFac::ByType | entry | all |  | Assigns by the value's type: a string through <AssignString>, a long integer through <StoreLongInteger>, a real or |
| QINTGR | StoreNumber | routine | all | StoreNumber | Stores the <FAC> in the variable at <FORPNT>: a real as it is, an integer rounded to two bytes, high byte first. |
| COPFLT | StoreNumber::ToPackFac | local | all | StoreNumber::ToPackFac | Stores the <FAC> as a real, through <MOVVF>. |
| BMOVVF | Statements::LetLongInteger | routine | all |  | Stores a long integer, dropping <INTFLG> from the stack. |
| BMOVF1 | StoreLongInteger | routine | all |  | Stores the long integer in the <FAC> in the variable at <FORPNT>, through <STFACT>. |
| COPSTR | Statements::LetString | routine | all | Statements::LetString | Assigns a string, dropping <INTFLG> from the stack. |
| INPCOM | AssignString | routine | all | AssignString | Assigns the string whose descriptor <FACMO> points to, to the string variable at <FORPNT>. |
| COPY | AssignString::CopyCharacters | local | all | StoreString::CopyCharacters | Copies a variable's string to new room, making the copy a temporary. |
| COPY_M | AssignString::MoveCharacters | entry | all |  | Moves the string into the room and makes its temporary descriptor. |
| COPY_C | AssignString::StoreDescriptor | local | all |  | Frees the temporary descriptor (not its string) and the variable's old string, then copies the descriptor in. |
| COPY_S | AssignString::CopyDescriptor | local | all |  | Copies the descriptor's three bytes into the variable. |
| FIXBAK | AssignString::SetBackPointer | entry | all |  | Points the string's information bytes back at its variable. |
| LETRTS | AssignString::Done | local | all |  | Returns, for `LET`. |
| RELPTR | Variables::VariableOffset | routine | all |  | Turns the variable pointer in <FORPNT> into an offset: from <ARYTAB> for an array element, otherwise from the simple |
| RELPTR2 | Variables::VariableOffset::ArrayElement | entry | all |  | Takes <FORPNT> as an array element's. |
| ISSIMP | Variables::VariableOffset::Simple | local | all |  | Makes a simple variable's offset. |
| GOTRELA | Variables::VariableOffset::Done | local | all |  | Returns. |
| VAERR | Variables::VariableOffset::VariableError | entry | all |  | Ends the statement with the VARIABLE error. |
| STRDON | Statements::PrintStringItem | routine | all | Statements::PrintStringItem | Prints a string, then goes on with `PRINT`'s list. |
| NEWCHR | Statements::PrintNextItem | routine | all | Statements::PrintNextItem | Goes on with `PRINT`'s list at the current character. |
| PRINT | Statements::PrintList | routine | all | Statements::Print | Prints `PRINT`'s list: values, `TAB(` and `SPC(`, with commas and semicolons between; a list that does not end in a |
| PRINTC | Statements::PrintList::Item | entry | all | Statements::Print::Item | Prints the rest of the list after a comma, a semicolon, `TAB(` or `SPC(`, where a terminator ends the line without |
| ISBIN | Statements::PrintList::Real | local | all |  | Prints a real, through <FOUT>'s text. |
| CRDO | PrintNewline | routine | all | PrintNewline | Ends the output line: a RETURN, then a line feed when the output goes to the console or another device rather than |
| DOLF | PrintNewline::LineFeed | local | all |  | Prints the line feed. |
| DOLFRT | PrintNewline::ResetColumn | local | all |  | Sets the column back to 0 and takes X and Y back. |
| PRTRTS | PrintNewline::Return | entry | all | PrintNewline::Return | Returns, for `PRINT`. |
| PRTRTS1 | Output::FreePrintedString | routine | all |  | Frees the string just printed, if it was one. |
| COMPRT | PrintComma | routine | all | PrintComma | Moves to the next column of 16, past the current one. |
| TABER | PrintTabOrSpace | routine | all | PrintTabOrSpace | Does `TAB(n)`, which moves to column n (1 first) when the output is short of it, or `SPC(n)`, which prints n spaces. |
| XSPAC | PrintSpaces | routine | all | PrintSpaces::CountInX | Prints X spaces, then goes on with `PRINT`'s list. |
| XSPAC2 | PrintSpaces::Next | local | all | PrintSpaces::Next | Counts the spaces down. |
| NOTABR | PrintSpaces::ContinuePrint | entry | all | PrintSpaces::ContinuePrint | Goes on with the list after its separator. |
| XSPAC1 | PrintSpaces::One | entry | all | PrintSpaces::One | Prints a space and counts it. |
| STROUT | PrintText | routine | all | PrintText | Prints a string that ends in a zero, making a temporary for it. |
| STRPRT | PrintString | routine | all | PrintString | Prints the string whose descriptor <FACMO> points to, then frees it if it is a temporary. |
| STRPR3 | Output::WriteString | routine | all |  | Prints X characters from <INDEX>, to the console or the output file, with one SOS WRITE through <SINIT>. |
| GOOUT | Output::WriteString::Write | local | all |  | Counts the characters into <TRMPOS> and makes the WRITE. |
| STRPR4 | Output::WriteString::Finish | local | all |  | Frees the string, if it was one. |
| OUTSPC | PrintSpace | routine | all | PrintSpace | Prints a space. |
| OUTQST | PrintQuestionMark | routine | all | PrintQuestionMark | Prints a question mark. |
| OUTDO | PrintCharacter | routine | all | PrintCharacter | Prints the character in A, to the console or the output file, and counts it in <TRMPOS>. |
| OTDOER | PrintCharacter::WriteError | entry | all |  | Ends the statement with the WRITE's error. |
| OUTLOC | PrintCharacter::Send | local | all | PrintCharacter::Send | Prints the character on the console. |
| DOPRINT | Statements::Print | routine | all |  | The `PRINT` statement: `PRINT# n;` to a file, `PRINT USING`, or `PRINT` to the console. |
| GPRNT | Statements::Print::CheckUsing | local | all |  | Takes `PRINT USING`, or the plain list. |
| GPR3 | Statements::Print::List | local | all |  | Prints the list. |
| GPRNT2 | Statements::Print::ReadColumn | local | all |  | Reads the cursor's column into <TRMPOS> when the output goes to the console. |
| GPR4 | Statements::Print::ToCheckUsing | local | all |  | Goes on with `PRINT USING` or the list. |
| STROUTR | Output::PrintTextDirect | routine | all |  | Prints a string that ends in a zero, as it is, without the string routines; the length must be under 256. |
| STRLUP | Output::PrintTextDirect::Count | local | all |  | Counts to the zero. |
| ROUTSPC | Lister::WrapSpace | routine | all |  | Prints a space as <Lister::WrapCharacter> does. |
| ROUTDO | Lister::WrapCharacter | routine | all |  | Prints a character for `LIST`, first wrapping the line when the output has reached <OUTREC>'s width. |
| TSTTAB | Lister::WrapCharacter::Indent | local | all |  | Prints spaces up to the margin. |
| ROUTDONE | Lister::WrapCharacter::Print | local | all |  | Prints the character. |
| TRMNOK | HandleBadInput | routine | all | HandleBadInput | Handles a data item that does not end in a comma or the end: `INPUT` asks again, `READ` and `GET` end with SYNTAX |
| SNERR4 | HandleBadInput::ToSyntaxError | entry | all | HandleBadInput::ToSyntaxError | Ends the statement with a syntax error. |
| TRMNO2 | DiscardAndRetryInput | routine | all | DiscardAndRetryInput | Drops the byte <AssignVariableList::ConvertNumber> pushed, then asks again. |
| TRMNO1 | RetryInput | routine | all | RetryInput | Asks again for `INPUT`'s line: `INPUT#` from a file ends with TYPE MISMATCH, and with `ON ERR` the program goes to |
| DOAGIN | RetryInput::PrintReenter | entry | all | RetryInput | Prints ?REENTER and runs the `INPUT` statement again from its start. |
| DOAG2 | RewindInputStatement | routine | all |  | Points <TXTPTR> back at the statement's start, from <OLDTXT>. |
| GTRTS | RewindInputStatement::Done | entry | all |  | Returns, for `INPUT`. |
| GET | Statements::Get | routine | all | Statements::Get | The `GET` statement: reads one key, without echo, into each variable of its list, from the console, the <EXEC> file |
| GOTREF | Statements::Get::StartLoop | local | all |  | Starts the variable loop with no data, the zero at <BUF>+1, so each variable reads a key. |
| INPUT | Statements::Input | routine | all | Statements::Input | The `INPUT` statement: prints a prompt, reads a line from the console, or from a file after `#n;`, and assigns its |
| INPAOK | Statements::Input::PrintPrompt | local | all |  | Checks the comma or semicolon after the prompt, prints the prompt, and reads the line. |
| NOTQT0 | Statements::Input::CheckFile | local | all |  | Takes `INPUT# n;` from a file, or prints the `?` prompt. |
| NOTQTI | Statements::Input::QuestionPrompt | local | all |  | Prints the `?` prompt. |
| NOTQTII | Statements::Input::ReadInputLine | local | all |  | Reads `INPUT`'s line from the console into <BUF>, with a comma before it. |
| QINLIN | PromptAndInputLine | routine | all | PromptAndInputLine | Prints `?` and reads a line from the console, so a second `?` follows `INPUT`'s. |
| READ | Statements::Read | routine | all | Statements::Read | The `READ` statement: assigns the items of the program's `DATA` statements to the variables of the list, from |
| READON | Statements::Read::StartLoop | local | all |  | Starts `READ`'s variable loop. |
| INPCON | AssignInputList | routine | all | AssignInputList | Starts `INPUT`'s variable loop. |
| INPCO1 | AssignVariableList | routine | all | AssignVariableList | Assigns an item of the data to each variable of `INPUT`'s, `GET`'s or `READ`'s list. |
| INLOOP | AssignVariableList::NextVariable | local | all | AssignVariableList::NextVariable | Takes the next variable of the list; for `INPUT` and `GET`, the last one takes the data with no terminators. |
| INLP2 | AssignVariableList::SwitchToData | local | all |  | Moves <TXTPTR> to the data, keeping the list's place in <VARTXT>, and takes the next item; at the end of the data, |
| QDATA | AssignVariableList::SourceEmpty | local | all | AssignVariableList::SourceEmpty | Gets more data: `READ` looks for the next `DATA`, `INPUT` reads another line from its file or the console. |
| QD11 | AssignVariableList::AskForMore | local | all |  | Asks for more with `??`. |
| DATBK | AssignVariableList::SetCursor | local | all | AssignVariableList::SetCursor | Points <TXTPTR> at the new line. |
| DATBK1 | AssignVariableList::NextValue | local | all | AssignVariableList::NextValue | Takes the item after the separator: a number, or a string. |
| NOTERMS | AssignVariableList::NoDelimiters | local | all |  | Takes the string up to the data's end, with no terminators. |
| DTLP1 | AssignVariableList::ToSearchData | local | all |  | Goes on looking for `READ`'s next `DATA` statement. |
| SETQUT | AssignVariableList::SetDelimiters | local | all | AssignVariableList::SetDelimiters | Chooses the string's terminators: a quote for a quoted string, a comma otherwise, none for the last variable of |
| RESETC | AssignVariableList::StringAtCursor | local | all | AssignVariableList::StringAtCursor | Starts the string at <TXTPTR> itself. |
| NOWGET | AssignVariableList::MakeString | local | all | AssignVariableList::MakeString | Makes a string of the item and assigns it. |
| NOWGE1 | AssignVariableList::HaveAddress | local | all | AssignVariableList::HaveAddress | Makes the string, moves <TXTPTR> past it and assigns it. |
| NUMINS | AssignVariableList::ConvertNumber | local | all | AssignVariableList::ConvertNumber | Takes a number: an empty `INPUT` line, or an `INPUT` item with no digits, asks again. |
| NUMINS2 | AssignVariableList::ReadNumber | local | all |  | Reads the number, a long integer through <LINP> or a real through <FIN>. |
| NUMINS3 | AssignVariableList::StoreValue | local | all |  | Stores the number as a real or an integer, as the variable is. |
| STRDN2 | AssignVariableList::CheckTerminator | local | all | AssignVariableList::CheckTerminator | Checks what ends the item, a terminator or a comma, then keeps the data's place and takes the next variable. |
| TRMOK | AssignVariableList::TerminatorOk | local | all | AssignVariableList::TerminatorOk | Keeps the data's place in <INPPTR>, goes back to the list, and takes the next variable or ends. |
| NUMBCD | AssignVariableList::ReadLongInteger | local | all |  | Reads a long integer and stores it. |
| MAYBAD | AssignVariableList::EmptyNumber | local | all | AssignVariableList::EmptyNumber | Handles a missing number: `INPUT` asks again; `READ` and `GET` go on to read it. |
| DATLOP | AssignVariableList::SearchData | entry | all | AssignVariableList::SearchData | Looks for the next `DATA` statement, from <TXTPTR>, keeping its line number in <DATLIN>. |
| NOWLIN | AssignVariableList::CheckStatement | local | all | AssignVariableList::CheckStatement | Checks the statement's first byte for `DATA`, and takes its first item when it is. |
| VAREND | AssignVariableList::ListDone | entry | all | AssignVariableList::ListDone | Ends the variable loop: `READ` keeps its place in <DATPTR>; `INPUT` and `GET` check that the data is used up. |
| VARY0 | AssignVariableList::CheckExtra | local | all | AssignVariableList::CheckExtra | Checks for data left over. |
| INPVAR0 | AssignVariableList::PrintExtraIgnored | local | all |  | Prints ?EXTRA IGNORED and the line. |
| INPRTS | AssignVariableList::RestoreOutput | local | all |  | Sends output back to its usual place, after `INPUT#`. |
| SVTXT | SaveTextPointer | routine | all |  | Keeps <TXTPTR> in <VARTXT>. |
| RSTTXT | RestoreTextPointer | routine | all |  | Sets <TXTPTR> back from <VARTXT>. |
| EXIGNT | ExtraIgnoredMessage | local | all | ExtraIgnoredMessage | The message for data left over, ending in a zero. |
| TRYAGN | RetryMessage | local | all | RetryMessage | The message asking for `INPUT`'s line again, ending in a zero. |
| CHANGTP | ConvertKey | routine | all |  | Turns `GET`'s string into the variable's type: a real through <VAL>, a long integer through <STR2LNG>. |
| ISSTRIN | ConvertKey::IsString | local | all |  | Returns: a string variable takes the string as it is. |
| ISLONG | ConvertKey::ToLongInteger | local | all |  | Turns the string into a long integer. |
| NEXT | Statements::Next | routine | all | Statements::Next | The `NEXT` statement: adds the step to the loop's variable, and goes back after the `FOR` unless the variable has |
| GETFOR | Statements::Next::WithVariable | local | all | Statements::Next::WithVariable | Finds the loop variable's offset and type, the key of its `FOR` entry. |
| STXFOR | Statements::Next::SearchFrame | local | all | Statements::Next::SearchFrame | Finds the `FOR` entry. |
| HAVFOR | Statements::Next::AddStep | local | all | Statements::Next::AddStep | Cuts the stack to the entry, then adds the step to the variable's value. |
| HAVFLT | Statements::Next::RealVariable | local | all |  | Takes a real variable's value into <ARG>. |
| HAVSUM | Statements::Next::AddAndCompare | local | all |  | Adds, compares with the limit, stores the new value, and loops or ends. |
| NEWSGO | Statements::Next::ToNextStatement | local | all | Statements::Next::ToNextStatement | Goes on with the statement after the `FOR`. |
| LOOPDN | Statements::Next::EndLoop | local | all | Statements::Next::EndLoop | Takes the entry off the stack; after a comma, goes on with the next variable. |
| FRMNUM | EvaluateNumber | routine | all | EvaluateNumber | Evaluates a numeric formula. |
| CHKNUM | RequireNumber | routine | all | RequireNumber | Checks that the value is a number: a string or a long integer is a TYPE MISMATCH. |
| CHKSTR | RequireString | routine | all | RequireString | Checks that the value is a string: anything else is a TYPE MISMATCH. |
| CHKOK | RequireString::Done | local | all | RequireType::Done | Returns, for the checks. |
| DOCSTR | RequireString::IsString | local | all | RequireType::IsString | Passes a string when a string is wanted. |
| CHKERR | RequireString::Mismatch | entry | all | RequireType::Mismatch | Ends the statement with TYPE MISMATCH. |
| FRMEVL | EvaluateExpression | routine | all | EvaluateExpression | Evaluates a formula: values joined by operators, taken in order of precedence. |
| FRMEVL1A | EvaluateExpression::KeepingStacks | entry | all |  | Keeps both stacks as they are, so a formula in parentheses (from <DOPAR>) stacks on the one outside it. |
| FRMEVL1 | EvaluateExpression::NextOperand | local | all | EvaluateExpression::NextOperand | Takes a value, then the operator after it: a character of <OPTAB>, or an escape token's second byte; anything else |
| EVALRET | EvaluateExpression::OperandReturn | alias | all |  | The return address <EvaluateExpression::NextOperand>'s JSR pushes, which <RESTNAM> checks for after a function. |
| FNDOPR | EvaluateExpression::FindOperator | local | all |  | Looks the operator up in <OPTAB>, from its end. |
| NOOPR | EvaluateExpression::NoOperator | local | all |  | Takes the end of the formula as the operator. |
| FOUNDOP | EvaluateExpression::FoundOperator | local | all |  | Moves past the escape token's first byte, and gathers the relational operators into <DOMASK>. |
| FOP2 | EvaluateExpression::CheckRelation | local | all |  | Takes a relational operator's characters, or goes on with another operator. |
| GTRLOP | EvaluateExpression::NextRelation | local | all | EvaluateExpression::NextRelation | Adds a relational character's bit to <DOMASK>; the same one twice is a syntax error. |
| NOGTRL | EvaluateExpression::EndRelations | local | all | EvaluateExpression::EndRelations | Ends the relational operator: its bits are its number. |
| FRMEVLZ | EvaluateExpression::WithOperator | entry | all |  | Goes on with the operator in A; B3EvalG.asm comes back here after doing one. |
| NOTREL | EvaluateExpression::ComparePrecedence | local | all | EvaluateExpression::ComparePrecedence | Does the pending operator first when its precedence is at least the new one's; otherwise pushes the new one and its |
| NT1 | EvaluateExpression::KeepVerbTop | local | all |  | Keeps the verb stack's new top, unless it has grown too deep. |
| STKOK | EvaluateExpression::PushOperand | local | all | EvaluateExpression::PushOperand | Pushes the <FAC> on the noun stack, nine bytes. |
| PSHFAC | EvaluateExpression::PushFacByte | local | all |  | Copies the <FAC>'s eight bytes, then <FACMOB> under them. |
| SNERR5 | EvaluateExpression::ToSyntaxError | local | all | EvaluateExpression::ToSyntaxError | Ends the statement with a syntax error. |
| EXPRDN2 | EvaluateExpression::CheckResultType | local | all |  | Ends the formula, checking its type against the one wanted. |
| EXPRDN3 | EvaluateExpression::Return | local | all |  | Returns, for <EvaluateExpression>. |
| DOLAST | EvaluateExpression::PopOperand | local | all | EvaluateExpression::PopOperand | Does the pending operator: pulls its left operand off the noun stack into <ARG> and the operator off the verb stack, |
| PLLARG | EvaluateExpression::PullArgByte | local | all |  | Copies the eight bytes into <ARG>, then <FACMOB>'s byte into <ARGMOB>. |
| CANTFIX | EvaluateExpression::ToTypeMismatch | local | all |  | Ends the statement with TYPE MISMATCH. |
| GETOP | EvaluateExpression::TakeOperator | local | all |  | Takes the operator's number into A and <DOMASK>, for B3EvalG.asm's dispatch. |

### B3EvalG.asm, StrUtils.asm, B3FreeR.asm, B3DimnH.asm, B3UdefI.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| NOTDBLP | Operators::Apply::NotLongInteger | local | all |  | Works out the sign of a real product or quotient, for the operator's routine. |
| RDY2GO | Operators::Apply::Dispatch | local | all |  | Calls the operator's routine, with A = the <FAC>'s exponent and zero set for a zero <FAC>, as the routines... |
| FRMEV3 | Operators::Apply::Continue | entry | all |  | Pulls the operator that ended the operand back off the stack and goes on with the formula at <FRMEVLZ>. |
| ASTRNG | Operators::Apply::StringOperands | local | all |  | Takes a binary operator on two strings: `+` concatenates them and a relational operator compares them; any... |
| EVALER | Operators::Apply::ToSyntaxError | entry | all |  | Ends the statement with a syntax error. |
| PLUSOK | Operators::Apply::JoinStrings | local | all |  | Concatenates the two strings, then goes on with the formula. |
| EVAL | EvaluateOperand | routine | all | EvaluateOperand | Evaluates one operand from the program text into the <FAC>: a number, a string, a variable, a function's... |
| ACONSTNT | EvaluateOperand::ReadConstant | local | all |  | Reads a numeric constant: a long integer with <LINP> when <VALTYP> is above <VALUE_TYPE_ANY>, or a real... |
| RLBNY | EvaluateOperand::ReadReal | local | all |  | Reads a real constant with <FIN>, ending the statement with a syntax error when it has no digits. |
| EVAL1 | EvaluateOperand::NotDigit | local | all |  | Takes an operand that does not start with a digit: an escape token, a reserved word, a variable, a period,... |
| NOVAR | EvaluateOperand::NotVariable | local | all |  | Takes an operand that is not a variable: a constant that starts with a period, a unary plus, which is... |
| STRTXT | ReadQuotedString | routine | all | ReadQuotedString | Makes a temporary string of the literal after the quote at <TXTPTR>, then moves TXTPTR past its closing quote. |
| STRTX2 | ReadQuotedString::HaveAddress | local | all | ReadQuotedString::HaveAddress | Makes the literal at A, Y and bank X a temporary string, then moves <TXTPTR> past it. |
| NOTDO | Operators::Not | routine | all | Operators::Not (evaluates the next operand itself, so binds tighter than AppleSoft's) | Takes `NOT`, evaluating the one operand that follows: gives 1 when it is zero, or 0 when it is not, as a long |
| RLONE | Operators::Not::ReturnOne | local | all |  | Gives 1, for a zero operand, as a real. |
| EVAL3 | EvaluateMinusOrParentheses | routine | all |  | Takes a unary minus, or else expects a formula in parentheses. |
| PARC22 | EvaluateEscapeToken | routine | all |  | Takes an escape token: reads the byte after it and moves <TXTPTR> past both, then goes to <CallFunction>... |
| PARC23 | EvaluateReservedWord | routine | all |  | Takes a reserved word that gives a value with no arguments, such as `ERR` or `TIME$`, through <RESTBL>;... |
| VPOS | ReadCursorPosition | routine | all |  | Reads the cursor's position from the console into <CURX> and <CURY>, with a SOS D_STATUS call. |
| DOERRLN | Functions::ErrLin | routine | all |  | The value of `ERRLIN`: the line number of the last error, from <ERRLIN>. |
| GIVOUTREC | Functions::OutRec | routine | all |  | The value of `OUTREC`: the column at which `LIST` wraps its lines (0 for none), from <OUTREC>. |
| GIVINDENT | Functions::Indent | routine | all |  | The value of `INDENT`: the indent `LIST` uses, from <INDENT>. |
| GIVKBD | Functions::Kbd | routine | all |  | The value of `KBD`: the last key read on an interrupt, from <KEYSAVE>. |
| GIVEOF | Functions::Eof | routine | all |  | The value of `EOF`: the file number of the last end of file, from <EOFSV>. |
| GIVERR | Functions::Err | routine | all |  | The value of `ERR`: the number of the last error, from <ERRNUM>. |
| BCDTSTR | Operators::NotLongInteger | routine | all |  | Finishes `NOT` for a long integer: 1 when all eight bytes of the <FAC> are zero, 0 otherwise. |
| ISFALS | Operators::NotLongInteger::ReturnOne | local | all |  | Gives 1 as a long integer, for a zero operand. |
| DOMIN | ApplyMinus | routine | all | ApplyMinus (evaluates the next operand itself) | Takes a unary minus, evaluating the one operand that follows and negating it, as a long integer or a real. |
| CHGSGN | ApplyMinus::NegateReal | local | all |  | Negates the real in the <FAC>. |
| SNERR6 | ApplyMinus::ToSyntaxError | entry | all |  | Ends the statement with a syntax error. |
| DOPAR | EvaluateSubexpression | routine | all |  | Evaluates a formula that ends at a closing parenthesis or another delimiter, keeping the operators before it. |
| PARCHK | EvaluateParenthesized | routine | all | EvaluateParenthesized | Evaluates a formula in parentheses. |
| PARCHK2 | EvaluateParenthesized::AfterOpen | entry | all |  | Evaluates a formula and its closing parenthesis. |
| CHKCLS | CheckCloseParenthesis | routine | all | CheckCloseParenthesis | Checks for a closing parenthesis and moves past it, or ends the statement with a syntax error. |
| CHKSMC | CheckSemicolon | routine | all |  | Checks for a semicolon and moves past it, or ends the statement with a syntax error. |
| CHKEQL | CheckEquals | routine | all |  | Checks for an equals sign and moves past it, or ends the statement with a syntax error. |
| CHKPND | CheckNumberSign | routine | all |  | Checks for a number sign and moves past it, or ends the statement with a syntax error. |
| CHKOPN | CheckOpenParenthesis | routine | all | CheckOpenParenthesis | Checks for an opening parenthesis and moves past it, or ends the statement with a syntax error. |
| CHKCOM | CheckComma | routine | all | CheckComma | Checks for a comma and moves past it, or ends the statement with a syntax error. |
| SYNCHR | CheckCharacter | routine | all | CheckCharacter | Checks that the character at <TXTPTR> is A and moves past it, or ends the statement with a syntax error. |
| CMPLXERR | FormulaTooComplexError | routine | all |  | Ends the statement with FORMULA TOO COMPLEX. |
| SNERR | SyntaxError | routine | all | SyntaxError | Ends the statement with SYNTAX <ERROR>. |
| ISVAR | EvaluateVariable | routine | all | EvaluateVariable | Takes a variable's value into the <FAC>; an array that does not exist yet is not made. |
| ISVRET2 | EvaluateVariable::AtAddress | entry | all |  | Takes the value of the variable at A, Y and bank X into the <FAC>, by its type: a long integer's eight... |
| DBLVAR | EvaluateVariable::LongIntegerVariable | local | all |  | Copies a long integer variable's eight bytes into the <FAC>. |
| DECTPT | BackUpTextPointer | routine | all |  | Moves <TXTPTR> back one character. |
| DECTP1 | BackUpTextPointer::SamePage | local | all |  | Steps the low byte back. |
| GOOO | LoadNumericVariable | routine | all | LoadNumericVariable | Takes a real or an integer variable's value into the FAC. |
| GOOO2 | LoadNumericVariable::FloatInteger | entry | all |  | Floats an integer variable, its high byte first, into the <FAC>. |
| GOOOOO | LoadNumericVariable::NotInteger | local | all | LoadNumericVariable::NotInteger | Unpacks a real variable into the <FAC>. |
| ISFUN | CallFunction | routine | all | CallFunction | Takes a function's escape token: `FN`, `NOT`, or a function from <FUNDSP>. |
| GOODFUN | CallFunction::Builtin | local | all |  | Reads the arguments of a function from <FUNDSP> and calls it. |
| NORMFUN | CallFunction::SkipComma | local | all |  | Moves past the comma before the byte argument. |
| NORMFN2 | CallFunction::ReadByteArgument | local | all |  | Reads the byte argument, then calls the function with it on the stack. |
| OKNORM | CallFunction::OneArgument | local | all | CallFunction::OneArgument | Reads a one-argument function's argument in parentheses, of the type the function takes, then calls it. |
| ISASTRNG | CallFunction::StringArgument | local | all |  | Wants a string argument. |
| ISABIN | CallFunction::NumericArgument | local | all |  | Wants a numeric argument, then reads the argument. |
| FINGO | CallFunction::Dispatch | local | all | CallFunction::Dispatch | Calls the function from <FUNDSP>. |
| OROP | Operators::Or | routine | all | Operators::Or | Takes `OR`, giving 1 when either real is nonzero, 0 otherwise. |
| ANDOP | Operators::And | routine | all | Operators::And (AppleSoft's And has no old name of its own) | Takes `AND`, giving 1 when both reals are nonzero, 0 otherwise. |
| GIVE0 | Operators::And::LoadFalse | entry | all | Operators::And::LoadFalse | Gives 0 as a real. |
| GIVE1 | Operators::And::LoadTrue | entry | all | Operators::And::LoadTrue | Gives 1 as a real. |
| DOREL | ApplyRelation | routine | all | ApplyRelation | Compares <ARG> with the <FAC>, reals or strings, and gives 1 when the relation in <DOMASK> holds, 0 when not. |
| STRCMP | ApplyRelation::CompareStrings | local | all | ApplyRelation::CompareStrings | Compares two strings. |
| STASGN | ApplyRelation::SetLengthOrder | local | all | ApplyRelation::SetLengthOrder | Keeps the result the lengths give, for when the shorter string matches the start of the longer. |
| NXTCMP | ApplyRelation::NextByte | local | all | ApplyRelation::NextByte | Compares the next character, or takes the lengths' result when there are no more. |
| QCOMP | ApplyRelation::NumberResult | local | all | ApplyRelation::NumberResult | Turns a comparison result in X, -1, 0 or 1, into the relation's bit, with the carry set for -1. |
| GETCMP | ApplyRelation::CompareByte | local | all | ApplyRelation::CompareByte | Compares one character of the two strings. |
| DOCMP | ApplyRelation::ApplyMask | local | all | ApplyRelation::ApplyMask | Turns the comparison's result into 1 or 0 by the relation in <DOMASK>. |
| GOFLOT | ApplyRelation::FreeStrings | local | all |  | Frees the two strings' space after a string comparison, then floats the result. |
| GFLOT1 | ApplyRelation::ToFloat | local | all |  | Floats the comparison's result, 1 or 0. |
| GETSPA | Strings::ReserveSpace | routine | all | Strings::ReserveSpace | Takes room for a string of A characters, and its information bytes, from the bottom of string space. |
| TRYAG0 | Strings::ReserveSpace::Try | local | all |  | Tries again to take the room for the length on the stack. |
| TRYAG1 | Strings::ReserveSpace::KeepInformation | local | all |  | Keeps the information bytes' address and takes the characters' room below them. |
| TRYAG4 | Strings::ReserveSpace::CheckRoom | local | all |  | Collects garbage when the room would reach <STREND>. |
| TRYAG5 | Strings::ReserveSpace::CheckDistance | local | all |  | Takes the room, unless string space would grow past 64K below <HIMEM>: two X-byte steps of 32K. |
| STRRT2 | Strings::ReserveSpace::Done | local | all |  | Returns. |
| GARBAG | Strings::ReserveSpace::Collect | local | all | Strings::ReserveSpace::Collect | Packs the strings and tries again; the second time round, first asks SOS for more memory. |
| GARBA1 | Strings::ReserveSpace::CollectAndRetry | local | all |  | Packs the strings, then tries again. |
| GARBA2 | Strings::CollectGarbage | routine | all | Strings::CollectGarbage | Packs the strings in use up against <HIMEM>, so that the free space is all below them, and sets <FRETOP>... |
| GMOVPTR | Strings::CollectGarbage::TakeString | local | all |  | Takes the string whose information bytes <DECCNT> points to: one in use has its descriptor adjusted, a... |
| GRELSIM | Strings::CollectGarbage::SimpleVariable | local | all |  | Finds a simple variable's descriptor from <VARTAB>. |
| GARBREL | Strings::CollectGarbage::FindDescriptor | local | all |  | Works out the descriptor's address from the base, <VARTAB> or <ARYTAB>, and the offset in <HEADER>. |
| GRBCMP2 | Strings::CollectGarbage::MoveDescriptor | local | all |  | Moves the string's descriptor up by <GRBPNT> bytes, closer to <HIMEM>. |
| SUBYSAV | Strings::CollectGarbage::AddFree | local | all |  | Adds a free string and its information bytes to <GRBPNT>. |
| SUBYS2 | Strings::CollectGarbage::StepPastText | local | all |  | Steps <DECCNT> down past the string's characters. |
| GSUBINF | Strings::CollectGarbage::CheckBoundary | local | all |  | Where free space and strings in use meet, marks the top of the run of strings to move, or moves the run. |
| GSUBIN1 | Strings::CollectGarbage::MoveRun | local | all |  | Moves the run of strings in use, from <LOWTR> up to <HIGHTR>, to just under <HIGHDS>. |
| GSUBIN2 | Strings::CollectGarbage::NextString | local | all |  | Goes on to the next string down. |
| GSUBIN3 | Strings::CollectGarbage::CheckBottom | local | all |  | Goes on to the string below A, Y and bank X, or ends at <FRETOP>, moving the last run of strings in use. |
| GMOVCHK | Strings::CollectGarbage::PointAtInformation | local | all |  | Points <DECCNT> at the next string's information bytes. |
| GSUBIN4 | Strings::CollectGarbage::SetPointer | local | all |  | Sets <DECCNT> and takes the next string. |
| GRBLTUC | Strings::CollectGarbage::MoveLastRun | local | all |  | Moves the last run of strings in use up. |
| GRBDON | Strings::CollectGarbage::Finish | local | all |  | Sets <FRETOP> to the lowest string, and ends the collection. |
| GFINDTEMP | Strings::CollectGarbage::FindTemporary | local | all |  | Finds the temporary descriptor in <TEMPST> that points to this string, and adjusts it; a temporary string that |
| GARBTEMP | Strings::CollectGarbage::CheckTemporary | local | all |  | Tries the temporary descriptor at <HEADER>: is its string's end this string's information bytes? |
| DVARTS | Strings::CollectGarbage::NextTemporaryDescriptor | local | all |  | Steps to the next temporary descriptor. |
| NOTEMP | Strings::CollectGarbage::NoTemporary | local | all |  | Ends the statement with a VARIABLE error: a temporary string that no temporary descriptor points to. |
| CONCAT | Strings::Concatenate | routine | all | Strings::Concatenate | Concatenates two strings into a new temporary string, freeing their temporaries. |
| SIZEOK | Strings::Concatenate::LengthOk | local | all | Strings::Concatenate::LengthOk | Takes room for the joined string, and copies the left string into it. |
| CAT10 | Strings::Concatenate::CopyRight | local | all |  | Copies the right string after it, frees both temporaries and makes the result's. |
| CAT11 | Strings::ReleaseOperands | routine | all |  | Frees the <FAC>'s and <ARG>'s strings, if they are the last temporaries. |
| MAKREL | Strings::SubtractFromHighMemory | routine | all |  | Turns <INDEX> from a distance below <HIMEM> into an address, or back: it is <HIMEM> less <INDEX> either way. |
| MOVINS | Strings::CopyString | routine | all | Strings::CopyString | Copies the string whose descriptor <STRNG1> points to into the room at <FRESPC>. |
| MOVDO | Strings::CopyBytes | routine | all | Strings::CopyBytes | Copies A bytes from <INDEX> to <FRESPC>, last byte first. |
| MOVLP | Strings::CopyBytes::Loop | local | all | Strings::CopyBytes::Loop | Copies one byte. |
| MVSTRT | Strings::CopyBytes::Done | local | all | Strings::CopyBytes::Done | Returns. |
| FREFAC | Strings::ReleaseFac | routine | all | Strings::ReleaseFac | Frees the temporary descriptor of the <FAC>'s string, if it is the last temporary, and finds the string,... |
| FRETMP | Strings::ReleaseDescriptor | routine | all | Strings::ReleaseDescriptor | Frees a temporary descriptor, if it is the last one made, and finds its string. |
| NOTNOW | Strings::FindFromDescriptor | routine | all |  | Finds the string whose descriptor <INDEX> points to. |
| FREFC1 | Strings::FreeFacIfReleased | routine | all |  | Finds the <FAC>'s string again and frees its space when the zero flag says to. |
| FRENOW | Strings::FreeSpaceIfReleased | routine | all |  | Frees a string's space, when the zero flag says its temporary descriptor was freed. |
| FRESPA | Strings::FreeSpace | routine | all |  | Marks a string's space free, unless the string is empty. |
| FRETMS | Strings::ReleaseTemporary | routine | all | Strings::ReleaseTemporary | Frees the temporary descriptor at A, Y, if it is the last one made. |
| FRERTS | Strings::ReleaseTemporary::Done | entry | all | Strings::ReleaseTemporary::Done | Returns. |
| NOTFAC | Strings::FindFacString | routine | all |  | Finds the <FAC>'s string from its descriptor, without freeing anything, returning as |
| NOTNW2 | Strings::FindFromDescriptorAt | routine | all |  | Finds the string whose descriptor is at A, Y and bank X, without freeing anything, returning as |
| TSTFRE | Strings::MarkFree | routine | all |  | Marks a string's space free, for the garbage collector to reclaim. |
| FREIT1 | Strings::MarkFree::Loop | local | all |  | Writes the length, then two zeros, into the information bytes at (<HEADER>). |
| FIXSBC | Memory::NormalizeAfterSubtract | routine | all |  | Brings a page back into range after a subtract that may have borrowed. |
| FIXSB2 | Memory::NormalizePage | routine | all |  | Brings a page back into range, one X-byte step's $80 pages up or down, without looking at the carry. |
| FIXADC | Memory::NormalizeAfterAdd | routine | all |  | Brings a page back into range after an add that may have carried. |
| FIXYAX | Memory::SubtractPageCount | routine | all |  | Subtracts a count of pages from an X-byte and page, the high half of taking a 16-bit offset, packed by |
| FIXXY | Memory::PreviousPage | routine | all |  | Steps an X-byte and page pointer back a page. |
| FIXYX | Memory::WrapPage | routine | all |  | Brings a page past the X-byte's window down through the next X-byte. |
| FIXRTSX | Memory::WrapPage::Done | entry | all |  | Returns. |
| FIXAYX | Memory::PageDifference | routine | all |  | Finishes the difference of two banked pointers as a 16-bit count of pages. |
| FIXAY | Memory::PackPages | routine | all |  | Packs an X-byte and page into one 16-bit count of pages, X-byte * $80 + page. |
| FIXYA | Memory::UnpackPages | routine | all |  | Unpacks a count of pages in A, as a string descriptor holds its address, into an X-byte and page. |
| IF | Statements::If | routine | all | Statements::If | The `IF` statement: runs what follows `THEN` or `GOTO` when the condition is true, or what follows the... |
| OKGOTO | Statements::If::Test | local | all | Statements::If::Test | Tests the condition: a long integer by all its bytes, a real by its exponent. |
| EXPBYTC | Statements::If::TestReal | local | all |  | Tests a real condition: an exponent of 0 is a zero. |
| ISATRUE | Statements::If::Branch | local | all |  | Runs `THEN`'s part when the condition is true, or else looks for the `ELSE`. |
| ELSE1 | Statements::If::FindElse | local | all |  | Scans the line for the `ELSE` that matches the `IF`, through Y; with none, goes on at the next line. |
| NOTEOL | Statements::If::CheckToken | local | all |  | Counts an `IF` or `ELSE` in the scan; at the matching `ELSE`, goes on after it. |
| PLSONE | Statements::If::NestedIf | local | all |  | Counts a nested `IF`, whose `ELSE` must be passed over. |
| DOCOND | Statements::IfTrue | routine | all | Statements::IfTrue | Runs what follows `THEN` or `GOTO`: a line number goes to that line; anything else runs as statements. |
| DOCOND1 | Statements::IfTrue::ToGoTo | entry | all |  | Goes to the line number at <TXTPTR>. |
| DOCO | Statements::IfTrue::ToExecuteStatement | entry | all | Statements::IfTrue::ToExecuteStatement | Runs the statement at <TXTPTR>, dropping <NEWSTT>'s return address and backing <TXTPTR> up so <NWSTT> reads it |
| WINDOW | Statements::Window | routine | all |  | The `WINDOW` statement: `WINDOW x1,y1 TO x2,y2` sets the console's viewport to that rectangle. |
| NOTIN | Statements::Window::SortLines | local | all |  | Takes the second line and puts the larger line at the bottom. |
| WINDER | Statements::Window::SetViewport | local | all |  | Sends the console the codes that set the viewport, then moves the cursor to the bottom line. |
| DOITOUT | SendCoordinate | routine | all |  | Sends a column or line counted from 1 to the console as one counted from 0; 0 stays 0. |
| DIM3 | Statements::DimNextArray | routine | all | Statements::DimNextArray | `DIM`'s loop: after each array, a comma brings the next one. |
| DIM | Statements::Dim | routine | all | Statements::Dim | The `DIM` statement: makes each array named, sized by its subscripts. |
| PTRGET | FindVariable | routine | all | FindVariable | Reads the variable name at <TXTPTR> and finds its value, making the variable when it does not exist. |
| PTREVL | FindVariable::ForExpression | entry | all |  | With X nonzero, an array not found is not made: <VARPNT> points to a zero (<ZERO>) instead, as the expression |
| PTRGT1 | FindVariable::WithDimensionFlag | entry | all | FindVariable::WithDimensionFlag | Takes <DIMFLG> from X; <Statements::Dim> enters here. |
| PTRGT2 | FindVariable::KeepDimensionFlag | entry | all | FindVariable::KeepDimensionFlag | Takes <DIMFLG>, <DORES> and SUBFLG as they are; `FN`'s name and `DEF`'s argument enter here with SUBFLG set. |
| WRDERR | FindVariable::ToSyntaxError | local | all |  | Ends the statement with SYNTAX <ERROR>, for a variable name that is not one. |
| PTRGT3 | FindVariable::ValidFirst | entry | all | FindVariable::ValidFirst | Starts with a letter: notes where the name starts, in <LOWDS> and <TMPPTR>, and reads to its end. |
| EATEM | FindVariable::SkipRest | local | all | FindVariable::SkipRest | Skips the name's letters, digits and periods. |
| GOTTYP | FindVariable::TypeCharacter | local | all |  | Turns the type character into an index in <Variables::ValueSizes>, refusing one on an `FN` name, and steps... |
| REAL | FindVariable::LookUpType | local | all |  | Looks up the type's value size and type byte, and works out the name's length. |
| NTREAL | FindVariable::KeepLength | local | all |  | Keeps the name's length plus 1 in <FOUR6>, and sets an `FN` name's type. |
| YSTORE | FindVariable::StoreType | local | all |  | Keeps the type byte in <VALTYP>, then goes to the array search for a name followed by `(`, unless <SUBFLG>... |
| GARRAY | FindVariable::ToFindArray | local | all |  | Goes to the array search. |
| SPLVAR | FindVariable::NoParenthesis | local | all |  | Not followed by `(`: with <SUBFLG> bit 6 alone, still an array; otherwise a simple variable. |
| SIMVAR | FindVariable::SearchScalars | local | all |  | Searches the simple variable table, from <SMVARS> to <STREND>, for the name and type; makes the variable... |
| STXLOP | FindVariable::SetEntryHigh | local | all |  | Keeps the entry's page in <SRCHPT> and checks it against <STREND>, the table's end. |
| SRCHLP | FindVariable::CheckEnd | local | all |  | Keeps the entry's low byte in <SRCHPT> and checks it against <STREND>. |
| PNTER3 | FindVariable::CompareEntry | local | all |  | Compares the name in the program with this entry's, upper-casing the program's letters. |
| COMPAR | FindVariable::CompareName | local | all |  | Compares the next character of the name. |
| NOT2BIG | FindVariable::CompareCharacter | local | all |  | Compares the character, in upper case, with the entry's. |
| TYPCHK | FindVariable::CheckType | local | all |  | At the name's end, or the first difference: the entry matches when its type byte is here and the name's length |
| FINUP | FindVariable::PointAtValue | entry | all |  | Points <VARPNT> at the value: the entry's address plus A plus carry, going on through the next X-byte past... |
| CMPLTE | FindVariable::StoreValuePointer | local | all |  | Stores <VARPNT> and its X-byte. |
| MYMYMY | FindVariable::SetIntegerFlag | entry | all |  | Turns an integer's type byte into INTFLG = $80 with VALTYP = 0, as the expression evaluator wants. |
| PTRRTS | FindVariable::Done | local | all |  | Returns. |
| GONEXT | FindVariable::Advance | local | all |  | Steps <SRCHPT> past this entry, by its length byte, and searches on. |
| ISLETC | IsLetter | routine | all | IsLetter | Tells whether a character is a letter, upper or lower case. |
| ISLRTS | IsLetter::Done | local | all | IsLetter::Done | Returns. |
| ADDVAR | Variables::Create | routine | all |  | Makes a simple variable at <STREND>, the table's end: the length byte, the name in upper case, the type... |
| GOARND | Variables::Create::SetNewEnd | local | all |  | Moves <STREND> past the new entry, if there is room, and writes the entry. |
| TILOOP | Variables::Create::ClearValue | local | all |  | Zeroes the value, from its last byte down, then writes the type byte. |
| TGHTLP | Variables::Create::CopyName | local | all |  | Copies the name from the program into the entry, from its last character down, upper-casing it. |
| ALDONE | Variables::Create::Finish | local | all |  | Points <VARPNT> at the new value, past the length byte, the name and the type byte. |
| VALTAB | Variables::ValueSizes | table | all |  | Each type's value size in bytes, by the index the type character gives: a real (no character), `!`, `"`,... |
| VALTB2 | Variables::TypeBytes | table | all |  | Each type's type byte, in <Variables::ValueSizes>'s order: a real's <VALUE_TYPE_REAL>, `!`'s <TYPE_BYTE>,... |
| PUSHF | PushSignedFac | routine | all | EvaluateExpression::PushSignedFac (here outside the evaluator, so top level) | Pushes A, then the rounded <FAC>, under the caller's return: `FOR` keeps its `STEP` this way. |
| FORPSH | PushFac | routine | all | EvaluateExpression::PushFac (here outside the evaluator, so top level) | Pushes the rounded <FAC>, five bytes with the exponent on top, then jumps to INDEX1. |
| FMAPTR | Variables::ElementsStart | routine | all | Variables::ElementsStart | Points ARYPNT at an array's elements: past the entry's head and two bytes for each of COUNT dimensions. |
| FMPTR1 | Variables::ElementsStart::SizesPlus | entry | all |  | Points <ARYPNT> A bytes past an array's sizes, which start one past the count of dimensions. |
| FMPTR2 | Variables::ElementsStart::CountPlus | entry | all |  | Points <ARYPNT> A bytes plus carry past an array's count of dimensions. |
| JSRGM | Variables::ElementsStart::Store | local | all | Variables::ElementsStart::Store | Stores <ARYPNT> and its X-byte. |
| N32768 | MinimumInteger | table | all | MinimumInteger | -32768 as a packed real, for <FacToInteger>'s check. |
| INTIDX | EvaluateSubscript | routine | all | EvaluateSubscript | Evaluates a subscript: the formula after the current character, as an integer 0-32767. |
| POSINT | FacToNonnegativeInteger | routine | all | FacToNonnegativeInteger | Makes the <FAC> a 16-bit integer, refusing a negative number. |
| AYINT | FacToInteger | routine | all | FacToInteger | Makes the <FAC> a signed 16-bit integer, -32768 to 32767, rounding it by adding one half first. |
| NONONO | FacToInteger::FailUnlessEqual | entry | all | FacToInteger::FailUnlessEqual | Goes on when zero is set; otherwise an ILLEGAL QUANTITY error. |
| QINTGO | FacToInteger::RoundToInteger | local | all |  | Adds one half and makes the <FAC> an integer. |
| ISARY | Variables::FindArray | routine | all | Variables::FindArray | Finds an array, or makes it, and points <VARPNT> at the element the subscripts name. |
| INDLOP | Variables::FindArray::NextSubscript | local | all | Variables::FindArray::NextSubscript | Evaluates each subscript and slips it on the stack under the type byte and <DIMFLG>. |
| STRTSRCH | Variables::FindArray::Search | local | all |  | Searches the array table, from <ARYTAB> to <VARTAB>, for the name and type. |
| LOPFDA | Variables::FindArray::CheckEnd | local | all | Variables::FindArray::CheckEnd | Points <LOWTR> at the next entry, and ends the search at <VARTAB>. |
| LOPFDV | Variables::FindArray::CompareName | local | all | Variables::FindArray::CompareName | Compares the name in the program with this entry's, upper-casing the program's letters. |
| NMLOOP | Variables::FindArray::NextCharacter | local | all |  | Compares the next character of the name. |
| NOT2SML | Variables::FindArray::CompareCharacter | local | all |  | Compares the character, in upper case, with the entry's. |
| CHKTYP | Variables::FindArray::CheckType | local | all |  | The entry matches when its type byte is here and the name's length agrees. |
| NOGOT | Variables::FindArray::NextArray | local | all |  | Steps <LOWTR> past this entry, by its two-byte length, and searches on. |
| BSERR | BadSubscriptError | routine | all | BadSubscriptError | Ends the statement with BAD SUBSCRIPT. |
| FCERR | IllegalQuantityError | routine | all | IllegalQuantityError | Ends the statement with ILLEGAL QUANTITY. |
| ERRGO3 | IllegalQuantityError::ToError | entry | all | IllegalQuantityError::ToError | Ends the statement with the error in X. |
| GOTARY | Variables::ArrayFound | routine | all | Variables::ArrayFound | Found the array: in `DIM`, a REDIM'D ARRAY error; otherwise checks the count of subscripts and finds the... |
| GOGETM | Variables::ArrayFound::CheckDimensions | local | all |  | Checks that the array has as many dimensions as there are subscripts (BAD SUBSCRIPT otherwise), then finds the |
| NOTFFD | Variables::ArrayNotFound | routine | all |  | Not found. From an expression (<DORES> set), the array is not made: the subscripts are dropped and... |
| NOTFONE | Variables::ArrayNotFound::DropSubscript | local | all |  | Drops a subscript from the stack. |
| NOTFF2 | Variables::CreateArray | routine | all |  | Makes the array at <VARTAB>, the array table's end, moving the simple variable table up to make room. |
| SIZLOP | Variables::CreateArray::NextDimension | local | all |  | Multiplies <CURTOL> by each dimension's size. |
| NOTDIM | Variables::CreateArray::SizeFromHighest | local | all |  | Makes the dimension's size, one more than its highest subscript, in Y (low) and X (high). |
| NOVFLW | Variables::CreateArray::Multiply | local | all |  | Multiplies <CURTOL> by the size, then takes the next dimension; past the last, adds the head's size. |
| ALGOOD | Variables::CreateArray::KeepHigh | local | all |  | Keeps the size's high byte. |
| GOODIE | Variables::CreateArray::MoveSimpleVariables | local | all |  | Moves the simple variable table, from <VARTAB> to <STREND>, up by the entry's size, which moves <STREND>. |
| INDLP1 | Variables::InitializeArray::WriteSize | local | all |  | Writes each dimension's size, high byte first: one more than its subscript in `DIM`, or 11. |
| NTDIMD | Variables::InitializeArray::StoreSize | local | all |  | Stores the size's two bytes, high byte first. |
| NAMLOP | Variables::InitializeArray::CopyName | local | all |  | Copies the name from the program into the entry, upper-casing it, then writes the type byte and the count of |
| ZERITA | Variables::InitializeArray::ClearLoop | local | all | Variables::CreateArray::ClearLoop (here in InitializeArray, B3UdefI.asm's half of making an array) | Zeroes the elements, from <ARYPNT> up to <VARTAB>, the start of the simple variables. |
| CHKUPR | Variables::InitializeArray::CheckEnd | local | all |  | Goes on until <VARTAB>; then returns in `DIM`, and otherwise finds the element. |
| GETDEF | Variables::ElementAddress | routine | all | Variables::ElementAddress | Points VARPNT at the element the subscripts on the stack name, checking each against its dimension's size. |
| INLPNM | Variables::ElementAddress::NextSubscript | local | all | Variables::ElementAddress::NextSubscript | Takes the next subscript off the stack and checks it is below its dimension's size. |
| BSERR7 | Variables::ElementAddress::ToBadSubscriptError | local | all | Variables::ElementAddress::ToBadSubscriptError | Ends the statement with BAD SUBSCRIPT. |
| OMERR1 | Variables::ElementAddress::ToOutOfMemoryError | entry | all | Variables::ElementAddress::ToOutOfMemoryError | Ends the statement with OUT OF MEMORY, for <Variables::MultiplyUnsigned>. |
| INLPN2 | Variables::ElementAddress::SkipLow | local | all | Variables::ElementAddress::SkipLow | Steps Y past the size's high byte, for a subscript whose high byte is below it. |
| INLPN1 | Variables::ElementAddress::InBounds | local | all | Variables::ElementAddress::InBounds | Multiplies the offset by this dimension's size and adds the subscript; an offset of zero just takes it. |
| ADDIND | Variables::ElementAddress::AddSubscript | local | all | Variables::ElementAddress::AddSubscript | Adds the subscript's high byte, and goes on to the next subscript; past the last, works out the element's... |
| DIMRTS2 | Variables::ElementAddress::SetArrayFlags | entry | all |  | Sets <VARPNTB> and <ISARA> ($80, an array element), then finishes as <FindVariable::SetIntegerFlag> does. |
| DIMRTS1 | Variables::ElementAddress::ToSetIntegerFlag | entry | all |  | Finishes the variable search in <FindVariable::SetIntegerFlag>, which sorts out an integer's type. |
| UMULT | Variables::MultiplyUnsigned | routine | all | Variables::MultiplyUnsigned (AppleSoft's UMULTD; its UMULT loads the bound first) | Multiplies CURTOL by a 16-bit number, for array sizes and offsets. |
| UMULTC | Variables::MultiplyUnsigned::NextBit | local | all | Variables::MultiplyUnsigned::NextBit | Doubles the product, then adds the number when the next bit of <CURTOL>, from the top, is set. |
| UMLCNT | Variables::MultiplyUnsigned::CountBit | local | all | Variables::MultiplyUnsigned::CountBit | Counts the bits down. |
| UMLRTS | Variables::MultiplyUnsigned::Done | entry | all | Variables::MultiplyUnsigned::Done | Returns. |
| NOFREF | Functions::Fre | routine | all | Functions::Fre (AppleSoft's FRE; its NOFREF is a local) | The `FRE` function: collects the strings' garbage, then gives the bytes free between <STREND> and <FRETOP>. |
| GIVAYF | ReturnSignedWord | routine | all | ReturnSignedWord | Puts a signed 16-bit integer in the FAC as a real. |
| POS | Functions::HPos | routine | all |  | The `HPOS` function: the cursor's column, counting from 1 (AppleSoft's POS counts from 0). |
| VPOS2 | Functions::HPos::CountFromOne | entry | all |  | Adds 1, to count from 1 as `TAB` and `HTAB` do, and gives Y as a real. |
| SNGFLT | ReturnByte | routine | all | ReturnByte | Puts Y, 0-255, in the FAC as a real. |
| DOVPOS | Functions::VPos | routine | all |  | The `VPOS` function: the cursor's line, counting from 1. |
| ERRDIR | RejectDirectMode | routine | all | RejectDirectMode | Refuses a statement in direct mode, where <CURLIN>'s high byte is $FF. |
| ERRGUF | RejectDirectMode::UndefinedFunction | entry | all | RejectDirectMode::UndefinedFunction | Ends the statement with UNDEF'D FUNCTION. |
| DEF | Statements::Def | routine | all | Statements::Def | The `DEF` statement: notes the formula's address and the argument variable in the function's entry, and... |
| GETFNM | ReadFunctionName | routine | all | ReadFunctionName | Reads `FN` and the function's name, finding or making its entry. |
| GETFN1 | ReadFunctionName::AfterFn | entry | all |  | Finds or makes the entry of the function named at <TXTPTR>. |
| FNDOER | Functions::Fn | routine | all | Functions::Fn | Evaluates `FN`: puts the argument's value in the argument variable, evaluates the function's formula, then... |
| NOFUN | Functions::Fn::ToUndefinedFunction | local | all |  | Ends the statement with UNDEF'D FUNCTION. |
| DEFSTF | Functions::Fn::SaveArgument | local | all | Functions::Fn::SaveArgument | Pushes the argument variable's old value, four bytes. |
| DEFFIN | PopToFunctionPointer | routine | all | PopToFunctionPointer | Pulls X+1 bytes off the stack into DEFPNT's bytes 0 up: `DEF`'s entry, or `FN`'s argument variable's old... |
| DEFLOP | PopToFunctionPointer::Loop | local | all |  | Stores the next byte. |

### B3MathK.asm, B3MathL.asm, B3FinpM.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| FADDH | Float::AddHalf | routine | all | Float::AddHalf | Adds a half to FAC |
| FSUB | Float::SubtractFromPacked | routine | all | Float::SubtractFromPacked | Subtracts FAC from the five-byte real at A, Y: the FAC becomes that number less the FAC; differs from Microsoft's: sets X = 0, BASIC's bank, for LoadArg first |
| FSUBT | Float::SubtractFromArg | routine | all | Float::SubtractFromArg | Subtracts FAC from ARG, into the FAC, by negating the FAC and adding |
| FADD5 | Float::ShiftAndAdd | routine | all | Float::ShiftAndAdd | Shifts the smaller operand right by more than seven bits, a byte at a time first, then joins |
| FADD | Float::AddPacked | routine | all | Float::AddPacked | Adds the five-byte real at A, Y to FAC; differs from Microsoft's: sets X = 0, BASIC's bank, for LoadArg first |
| FADDT | Float::AddArg | routine | all | Float::AddArg | Adds ARG to FAC: lines up the binary points by shifting the smaller number right, then adds the mantissas, or |
| FADDC | Float::AlignAndAdd | routine | all | Float::AlignAndAdd | Adds ARG to FAC, taking A as ARG's exponent; a zero exponent leaves the FAC as it is; differs from Microsoft's: returns with BNE/RTS where Microsoft branches to ZERRTS |
| FADDA | Float::AlignAndAdd::ArgSmaller | local | all | Float::AlignAndAdd::ArgSmaller | ARG is the smaller: clears FACOV, so that the bits shifted out of ARG are the only rounding bits |
| FADD1 | Float::AlignAndAdd::Align | local | all | Float::AlignAndAdd::Align | Shifts the smaller operand, at X, right by minus A bits: more than seven through Float::ShiftAndAdd, fewer... |
| FADD4 | Float::AlignAndAdd::Combine | entry | all | Float::AlignAndAdd::Combine | Adds the mantissas when the signs match, and subtracts the smaller from the larger when they differ |
| SUBIT | Float::AlignAndAdd::Subtract | local | all | Float::AlignAndAdd::Subtract | Subtracts the shifted operand, at X, from the other, at Y, into FAC; Float::NormalizeSigned then negates a |
| FADFLT | Float::NormalizeSigned | routine | all | Float::NormalizeSigned | Negates FAC when the carry is clear, then normalizes it |
| NORMAL | Float::Normalize | routine | all | Float::Normalize | Normalizes FAC: shifts the mantissa left until its top bit is set, lowering the exponent to match, a byte at a |
| NORM3 | Float::Normalize::ShiftBytes | local | all | Float::Normalize::ShiftBytes | Shifts the mantissa left a byte while its high byte is zero, counting the bits in A; four zero bytes make... |
| ZEROFC | Float::SetZero | routine | all | Float::SetZero | Makes FAC zero, positive |
| ZEROF1 | Float::SetExponentAndSign | routine | all | Float::SetExponentAndSign | Sets FACEXP and FACSGN to A |
| ZEROML | Float::SetSign | routine | all | Float::SetSign | Sets FACSGN to A |
| FADD2 | Float::AddMantissas | routine | all | Float::AddMantissas | Adds the mantissas, the rounding bits too, then takes a carry out of the top into the exponent |
| NORM2 | Float::NormalizeBits | routine | all | Float::NormalizeBits | Shifts the mantissa left a bit, counting it in A, for Float::Normalize |
| NORM1 | Float::NormalizeBits::Test | entry | all | Float::NormalizeBits::Test | Shifts left until the top bit is set, then takes the count of bits from the exponent |
| SQUEEZ | Float::NormalizeBits::CheckCarry | entry | all | Float::NormalizeBits::CheckCarry | Takes a carry out of the mantissa's top: shifts it back in from the left and adds one to the exponent |
| RNDSHF | Float::ShiftInCarry | routine | all | Float::ShiftInCarry | Shifts the carry into the mantissa from the left and adds one to the exponent, ending the statement with... |
| RNDRTS | Float::ShiftInCarry::Done | entry | all | Float::ShiftInCarry::Done | Returns |
| NEGFAC | Float::Complement | routine | all | Float::Complement | Negates FAC: its sign, and the mantissa and rounding bits as a two's complement |
| NEGFCH | Float::ComplementMantissa | routine | all | Float::ComplementMantissa | Negates FAC's mantissa and rounding bits as a two's complement, leaving its sign; differs from Microsoft's: a loop over the mantissa, keeping X in DPTFLG; Microsoft unrolls it |
| NEGFCH1 | Float::ComplementMantissa::Loop | local | all |  | Complements a byte of the mantissa, from the lowest |
| INCFAC | Float::IncrementMantissa | routine | all | Float::IncrementMantissa | Adds one to FAC's mantissa |
| INCFRT | Float::IncrementMantissa::Done | entry | all | Float::IncrementMantissa::Done | Returns |
| OVERR | Float::OverflowError | routine | all | Float::OverflowError | Ends the statement with OVERFLOW, through ERROR |
| MULSHF | Float::ShiftProductByte | routine | all | Float::ShiftProductByte | Shifts the multiplication's result, RES, right a byte, for a multiplier byte of zero; differs from Microsoft's: also clears BITS |
| SHFTR2 | Float::ShiftRightByte | routine | all | Float::ShiftRightByte | Shifts the mantissa at X+1 right a byte, filling with BITS, the low byte going to FACOV, then goes on with |
| SHFTR0 | Float::ShiftRightByCount | routine | all |  | Shifts the mantissa at X+1 right by minus A bits: whole bytes while eight or more bits are left, filled from; Microsoft's SHIFTR body, under its own name here (SHIFTR clears BITS first) |
| SHFTR3 | Float::ShiftRightByCount::NextBit | local | all | Float::ShiftRight::NextBit | Shifts the high byte right a bit, copying its top bit |
| SHFTR4 | Float::ShiftRightByCount::ShiftHigh | local | all | Float::ShiftRight::ShiftHigh | Rotates the high byte right twice: the first puts back the bit the shift took, the second shifts with the copy |
| ROLSHF | Float::ShiftRightByCount::ShiftLow | entry | all | Float::ShiftRight::ShiftLow | Shifts the rest of the mantissa at X+2 right a bit, into the rounding bits in A, and loops for each count in Y |
| SHFTRT | Float::ShiftRightByCount::Done | entry | all | Float::ShiftRight::Done | Ends the shift with the carry clear |
| SHIFTR | Float::ShiftRight | routine | all | Float::ShiftRight | Shifts the mantissa of the number at X right by minus A bits, filling with zeros; differs from Microsoft's: clears BITS, then jumps to the shift (ShiftRightByCount), which is Microsoft's SHIFTR body |
| SHFTR1 | Float::ShiftRightFilled | routine | all |  | Shifts as Float::ShiftRight does, filling whole bytes with BITS: Float::ToLongInteger fills a negative; Business BASIC's: the shift with the fill in BITS, for QINT |
| FONE | Float::One | data | all | Float::One | 1.0 |
| LOGCN2 | Float::LogPolynomial | data | all | Float::LogPolynomial | The polynomial Functions::Log uses for the base-2 logarithm of its fraction, in odd powers: the count of... |
| SQR0_5 | Float::SquareRootOfHalf | data | all | Float::SquareRootOfHalf | The square root of 0.5 |
| SQR2_0 | Float::SquareRootOfTwo | data | all | Float::SquareRootOfTwo | The square root of 2 |
| NEGHLF | Float::MinusHalf | data | all | Float::MinusHalf | -0.5 |
| LOG2 | Float::LogOfTwo | data | all | Float::LogOfTwo | The natural logarithm of 2 |
| LOG | Functions::Log | routine | all | Functions::Log | Gives `LOG`, the natural logarithm of FAC; differs from Microsoft's: loads X with SQR0B before falling into FMULT |
| LOGERR | Functions::Log::ToIllegalQuantity | local | all | Functions::Log::ToIllegalQuantity | Ends the statement with ILLEGAL QUANTITY |
| LOG1 | Functions::Log::Reduce | local | all | Functions::Log::Reduce | Takes the logarithm of a positive FAC: keeps its exponent as n and makes it a fraction from 0.5 to 1 |
| FMULT | Float::MultiplyPacked | routine | all | Float::MultiplyPacked | Multiplies FAC by the five-byte real at A, Y; differs from Microsoft's: sets X = 0, BASIC's bank, for LoadArg first |
| FMULTT | Float::MultiplyArg | routine | all | Float::MultiplyArg | Multiplies FAC by ARG, into the FAC: ARG's mantissa times each byte of the FAC's, the rounding byte first, |
| MLTPLY | Float::MultiplyByte | routine | all | Float::MultiplyByte | Adds ARG times the multiplier byte in A into RES, shifting RES right a bit for each of its bits; a zero byte |
| MLTPL1 | Float::MultiplyByte::NonZero | entry | all | Float::MultiplyByte::NonZero | Multiplies by a non-zero byte, with a marker bit above it to count the eight bits |
| MLTPL2 | Float::MultiplyByte::NextBit | local | all | Float::MultiplyByte::NextBit | Adds ARG to RES when the bit shifted out is set |
| MLTPL3 | Float::MultiplyByte::Shift | local | all | Float::MultiplyByte::Shift | Shifts RES right a bit, into FACOV, and goes on while bits are left |
| MULTRT | Float::MultiplyByte::Done | entry | all | Float::MultiplyByte::Done | Returns |
| CONUPK | Float::LoadArg | routine | all | Float::LoadArg | Unpacks a real from memory into ARG: five bytes from BASIC's own bank, or a variable's four from another; differs from Microsoft's: takes the bank in X; a variable (bank not 0) has no fifth byte |
| MULDIV | Float::CombineExponents | routine | all | Float::CombineExponents | Adds ARG's exponent to FAC's for a multiplication or division, and sets the result's sign |
| MLDEXP | Float::AddExponent | routine | all | Float::AddExponent | Adds the exponent in A to FAC's, as Float::CombineExponents does |
| TRYOFF | Float::AddExponent::NoCarry | local | all | Float::AddExponent::NoCarry | Takes a sum with no carry: below $80 is too small; otherwise takes off the bias |
| MLDVEX | Float::ExponentOutOfRange | routine | all | Float::ExponentOutOfRange | For a result whose exponent is out of range: too large when FAC is positive, and zero when it is negative |
| ZEREMV | Float::Underflow | routine | all | Float::Underflow | Makes FAC zero and returns from the routine that called the exponent check |
| GOOVER | Float::ToOverflowError | routine | all | Float::ToOverflowError | Ends the statement with OVERFLOW |
| MUL10 | Float::MultiplyByTen | routine | all | Float::MultiplyByTen | Multiplies FAC by 10: four times itself, plus itself, doubled |
| MUL10R | Float::MultiplyByTen::Done | entry | all | Float::AddScaledArgAndDouble::Done | Returns |
| TEN_C | Float::Ten | data | all | Float::Ten | 10.0 |
| DIV10 | Float::DivideByTen | routine | all | Float::DivideByTen | Divides FAC by 10 |
| FDIVF | Float::DivideArgByPacked | routine | all | Float::DivideArgByPacked | Divides ARG by the five-byte real at A, Y, giving the quotient the sign in X; differs from Microsoft's: loads the divisor with LoadFac, bank TEN_CB |
| FDIV | Float::DividePacked | routine | all | Float::DividePacked | Divides the five-byte real at A, Y by FAC, into the FAC; differs from Microsoft's: sets X = 0, BASIC's bank, for LoadArg first |
| FDIVT | Float::DivideArg | routine | all | Float::DivideArg | Divides ARG by FAC, into the FAC, a bit of the quotient at a time; a zero FAC ends the statement with; differs from Microsoft's: BNE/JMP to the error, and DIVNRM rotates where Microsoft shifts |
| NO0ERR | Float::DivideArg::NotZero | local | all |  | Divides by a FAC that is not zero: rounds it, subtracts its exponent from ARG's, and sets the marker bit that |
| DIVIDE | Float::DivideArg::Compare | local | all | Float::DivideArg::Compare | Compares ARG's mantissa with FAC's, the divisor |
| SAVQUO | Float::DivideArg::SaveBit | local | all | Float::DivideArg::SaveBit | Shifts the comparison's result, as the next bit of the quotient, into A; each full byte goes to RES, and... |
| QSHFT | Float::DivideArg::TestSubtract | local | all | Float::DivideArg::TestSubtract | Subtracts the divisor when it went into ARG, then shifts ARG left a bit |
| SHFARG | Float::DivideArg::ShiftDividend | local | all | Float::DivideArg::ShiftDividend | Shifts ARG left a bit, then compares again; a bit carried out of ARG's top means the divisor goes in, and... |
| DIVSUB | Float::DivideArg::Subtract | local | all | Float::DivideArg::Subtract | Subtracts the divisor from ARG |
| LD100 | Float::DivideArg::LastBits | local | all | Float::DivideArg::LastBits | Sets the marker bit for the last two bits of the quotient |
| DIVNRM | Float::DivideArg::Finish | local | all | Float::DivideArg::Finish | Puts the last two bits of the quotient at the top of FACOV, then moves the quotient into FAC; differs from Microsoft's: three RORs and an AND where Microsoft has six ASLs; same result |
| DV0ERR | Float::DivideArg::DivisionByZero | local | all | Float::DivideArg::DivisionByZero | Ends the statement with DIVISION BY ZERO, through ERROR |
| MOVFR | Float::NormalizeResult | routine | all | Float::NormalizeResult | Moves the result of a multiplication or division, RES, into FAC's mantissa and normalizes it |
| MOVFM | Float::LoadFac | routine | all | Float::LoadFac | Unpacks a real from memory into FAC: five bytes from BASIC's own bank, or a variable's four from another; differs from Microsoft's: takes the bank in X; a variable has no fifth byte |
| MOV2F | Float::StoreFacInTemporary2 | routine | all | Float::StoreFacInTemporary2 | Packs FAC into TEMPF2, five bytes; differs from Microsoft's: passes bank 0 in A, through MOV1F |
| MOV1F | Float::StoreFacInTemporary1 | routine | all | Float::StoreFacInTemporary1 | Packs FAC into TEMPF1, five bytes; differs from Microsoft's: passes bank 0 in A |
| MOVVF | Float::StoreFacInVariable | routine | all | Float::StoreFacInVariable | Packs FAC into the variable FORPNT points to; differs from Microsoft's: passes FORPNT's bank in A |
| MOVMF | Float::StoreFac | routine | all | Float::StoreFac | Rounds FAC and packs it into memory: five bytes in BASIC's own bank, or a variable's four, rounded to three; differs from Microsoft's: takes the bank in A; a variable gets four bytes, rounded by ROUNDER |
| FOURBYT | Float::StoreFac::AtPointer | entry | all |  | Stores FAC's five or four bytes at INDEX1 |
| FURBYT | Float::StoreFac::ToVariable | local | all |  | Rounds FAC to a variable's three mantissa bytes, then stores the first four bytes |
| ROUNDER | Float::RoundForVariable | routine | all |  | Rounds FAC to the three mantissa bytes a variable keeps, to the nearest, a half to even, and clears FACLO; Business BASIC's: round to a variable's 24 bits, half to even |
| RONDRTS | Float::RoundForVariable::ClearLow | local | all |  | Clears FACLO |
| MOVFA | Float::CopyArgToFac | routine | all | Float::CopyArgToFac | Moves ARG into FAC |
| MOVFA1 | Float::CopyArgToFacWithSign | routine | all | Float::CopyArgToFacWithSign | Moves ARG's exponent and mantissa into FAC, with A as its sign |
| MOVFAL | Float::CopyArgToFacWithSign::Loop | local | all | Float::CopyArgToFacWithSign::Loop | Moves a byte, from the lowest |
| MOVAF | Float::CopyFacToArg | routine | all | Float::CopyFacToArg | Rounds FAC and copies it, with its sign, into ARG |
| MOVEF | Float::CopyFacToArgUnrounded | routine | all | Float::CopyFacToArgUnrounded | Copies FAC, with its sign, into ARG without rounding it |
| MOVAFL | Float::CopyFacToArgUnrounded::Loop | local | all | Float::CopyFacToArgUnrounded::Loop | Copies a byte, from the sign down |
| ROUND | Float::Round | routine | all | Float::Round | Rounds FAC's mantissa by the top bit of FACOV, taking a carry out of the top into the exponent; differs from Microsoft's: JSR RNDSHF and RTS where Microsoft jumps |
| INCRND | Float::Round::Increment | entry | all | Float::Round::Increment | Adds one to FAC's mantissa, taking a carry out of the top into the exponent |
| RONRTS | Float::Round::Done | entry | all |  | Returns |
| SIGN | Float::GetSign | routine | all | Float::GetSign | Gives FAC's sign |
| FCSIGN | Float::GetSign::FromSignByte | entry | all | Float::GetSign::FromSignByte | Gives the sign of FACSGN, as a non-zero FAC's |
| FCOMPS | Float::GetSign::FromBit7 | entry | all | Float::GetSign::FromBit7 | Gives 1 or $FF by the top bit of A |
| SIGNRT | Float::GetSign::Done | entry | all | Float::GetSign::Done | Returns |
| SGN | Functions::Sgn | routine | all | Functions::Sgn | Gives `SGN`, replacing FAC with its sign: -1, 0 or 1 |
| FLOAT | Float::ConvertSignedByte | routine | all | Float::ConvertSignedByte | Floats the signed byte in A into FAC |
| FLOATS | Float::ConvertSignedWord | routine | all | Float::ConvertSignedWord | Floats the signed 16-bit number in FACHO and FACHO+1, high byte first, into FAC |
| FLOATC | Float::ConvertWord | routine | all | Float::ConvertWord | Floats the number in FACHO and FACHO+1 into FAC, negating it when the carry is clear |
| ABS | Functions::Abs | routine | all | Functions::Abs | Gives `ABS`, making FAC positive |
| FCOMPARG | Float::CompareArg | routine | all |  | Compares ARG with FAC, taking them as equal when they match to 24 bits; Business BASIC's: the relational operators' compare, 24 bits |
| FCOMPA1 | Float::CompareArgWithin | routine | all |  | Compares ARG with FAC, as Float::CompareArg does, with Float::MatchBits bits that must match; Business BASIC's: compare by subtracting, with KIMY bits |
| PHFAC34 | Float::CompareArgWithin::SaveFac | local | all |  | Saves FAC on the stack |
| PHFAC35 | Float::CompareArgWithin::RestoreFac | local | all |  | Restores FAC from the stack |
| NTEQU36 | Float::CompareArgWithin::Unequal | local | all |  | Gives the result by the difference's sign |
| ISEQU37 | Float::CompareArgWithin::Equal | local | all |  | Gives 0, equal |
| FCOMPN | Float::CompareAtPointer2 | routine | all | Float::CompareAtPointer2 | Compares a five-byte real in BASIC's own bank, at INDEX2's low byte and the page in Y, with FAC, for `NEXT`; differs from Microsoft's: loads INDEX2 and bank 0, then falls into FCOMP (Microsoft's order is the reverse) |
| FCOMP | Float::Compare | routine | all | Float::Compare | Compares the real at A, Y with FAC, taking them as equal when they match to 32 bits; differs from Microsoft's: subtracts through FCOMPA1 and calls 32 matching bits equal; bank in X |
| QINT | Float::ToLongInteger | routine | all | Float::ToLongInteger | Turns FAC into a signed 32-bit integer in FACHO, FACMOH, FACMO and FACLO, high byte first: the greatest; differs from Microsoft's: clears BITS itself, and goes on with SHFTR1 and QINT1 by JMP |
| QISHFT | Float::ToLongInteger::Shift | local | all | Float::ToLongInteger::Shift | Shifts the integer into place: eight bits or more with Float::ShiftRightFilled, which shifts whole bytes... |
| QINT1 | Float::ToLongInteger::ShortShift | local | all | Float::ToLongInteger::ShortShift | Shifts FAC's mantissa right a few places, keeping a negative number's sign bits; differs from Microsoft's: ends with JMP ROLSHF where Microsoft has JSR, STY BITS, RTS |
| INT | Functions::Int | routine | all | Functions::Int | Gives `INT`: the greatest integer not above FAC |
| CLRFAC | Float::ClearMantissa | routine | all | Float::ClearMantissa | Zeros FAC's mantissa, for Float::ToLongInteger's zero |
| INTRTS | Float::ClearMantissa::Done | entry | all | Float::ClearMantissa::Done | Returns |
| FIN | Float::ReadNumber | routine | all | Float::ReadNumber | Reads a real from the text at TXTPTR into FAC; differs from Microsoft's: calls CHRGOT first; nine digits after the period; e or E; no sign tokens; ANYNUM |
| FINZLP | Float::ReadNumber::ClearLoop | local | all | Float::ReadNumber::ClearLoop | Zeros DECCNT and the bytes after it, leaving the carry from CHRGOT |
| QPLUS | Float::ReadNumber::CheckPlus | local | all | Float::ReadNumber::CheckPlus | Skips a plus sign |
| FINC | Float::ReadNumber::NextCharacter | local | all | Float::ReadNumber::NextCharacter | Takes the next character; after the ninth digit past the period, skips the remaining digits |
| FINDGQ | Float::ReadNumber::TestDigit | local | all | Float::ReadNumber::TestDigit | Takes a digit |
| FIN1 | Float::ReadNumber::CheckPoint | local | all | Float::ReadNumber::CheckPoint | Takes a character other than a digit: a period, an exponent, or the number's end |
| FINEC1 | Float::ReadNumber::NegativeExponent | local | all | Float::ReadNumber::NegativeExponent | Notes a negative exponent |
| FINEC | Float::ReadNumber::NextExponentCharacter | entry | all | Float::ReadNumber::NextExponentCharacter | Takes the exponent's next character |
| FNEDG1 | Float::ReadNumber::TestExponentDigit | local | all | Float::ReadNumber::TestExponentDigit | Takes an exponent digit |
| FINEC2 | Float::ReadNumber::ExponentDone | local | all | Float::ReadNumber::ExponentDone | Ends the exponent, negating it when its sign was minus |
| FINDP | Float::ReadNumber::DecimalPoint | local | all | Float::ReadNumber::DecimalPoint | Takes the period, with nine digits after it; a second period ends the number |
| FINE | Float::ReadNumber::EndOfNumber | local | all | Float::ReadNumber::EndOfNumber | Ends the number: scales FAC by the power of ten, then gives it its sign |
| FINE1 | Float::ReadNumber::AdjustExponent | local | all | Float::ReadNumber::AdjustExponent | Scales FAC by 10 to the power of A less DECCNT |
| FINDIV | Float::ReadNumber::DivideLoop | local | all | Float::ReadNumber::DivideLoop | Divides FAC by 10 for each negative power |
| FINMUL | Float::ReadNumber::MultiplyLoop | local | all | Float::ReadNumber::MultiplyLoop | Multiplies FAC by 10 for each positive power |
| FINQNG | Float::ReadNumber::ApplySign | local | all | Float::ReadNumber::ApplySign | Checks for digits and gives FAC its sign |
| NEGXQS | Float::ReadNumber::ToNegate | local | all | Float::ReadNumber::ToNegate | Negates FAC for a minus sign |
| BADNMB | Float::ReadNumber::NoDigits | local | all |  | Marks the number as having no digits, setting ANYNUM to $FF; Business BASIC's: no digits sets ANYNUM to $FF |
| FINED1 | Float::ReadNumber::SkipDigit | local | all |  | Skips a digit past the ninth after the period |
| FINEND | Float::ReadNumber::SkipDigits | local | all |  | Skips the remaining digits, then takes the next character |
| FINDIG | Float::ReadNumber::Digit | local | all | Float::ReadNumber::Digit | Takes a digit: FAC = FAC * 10 + the digit, counting it when after the period |
| FINDG1 | Float::ReadNumber::AddDigit | local | all | Float::ReadNumber::AddDigit | Multiplies FAC by 10 and adds the digit |
| FINLOG | Float::AddSignedByte | routine | all | Float::AddSignedByte | Adds a small integer to FAC |
| FINEDG | Float::AccumulateExponentDigit | routine | all | Float::AccumulateExponentDigit | Takes an exponent digit for Float::ReadNumber: TENEXP = TENEXP * 10 + the digit, with no more than two digits |
| MLEX10 | Float::AccumulateExponentDigit::TimesTen | local | all | Float::AccumulateExponentDigit::TimesTen | Multiplies the exponent by 10 and adds the digit |
| MLEXMI | Float::AccumulateExponentDigit::ClampNegative | local | all | Float::AccumulateExponentDigit::ClampNegative | Keeps the new exponent and takes the next character |
| N_0999 | Float::LowerOutputLimit | data | all | Float::LowerOutputLimit | The real 99999.94998: Float::FormatFac multiplies by 10 until the number is above it; differs from Microsoft's: 99999.94998, for six digits |
| N_9999 | Float::UpperOutputLimit | data | all | Float::UpperOutputLimit | The real 999999.5: Float::FormatFac divides by 10 until the number is no more than it. (Apple's comment says; differs from Microsoft's: 999999.5, for six digits |
| N_MIL | Float::Million | data | all |  | The real 1000000, which brings a number below 1 up for Float::FormatFac; a million, where Microsoft has a billion |
| INPRT | Float::PrintInLineNumber | routine | all | Float::PrintInLineNumber | Prints " IN " and the current line number, after an error message; differs from Microsoft's: prints through STROUTR, with the bank in X |
| LINPRT | Float::PrintDecimalAX | routine | all | Float::PrintDecimalAX | Prints a 16-bit number from 0 to 65535, such as a line number, with no space before it; differs from Microsoft's: calls FOUT and STROUTR inline (no PrintFac) |
| FOUT | Float::FormatFac | routine | all | Float::FormatFac | Writes FAC as text in FBUFFR, rounded first to a variable's precision and then to six significant digits; differs from Microsoft's: rounds to a variable's precision (ROUNDER) first; six digits, not nine |
| FOUTC | Float::FormatFacAtOffset | routine | all | Float::FormatFacAtOffset | Writes FAC as text from FBUFFR + Y - 1, as Float::FormatFac does but without rounding the FAC to a variable's; differs from Microsoft's: six digits, not nine |
| FOUT1_1 | Float::FormatFacAtOffset::SignDone | local | all | Float::FormatFacAtOffset::SignDone | Makes FAC positive and checks for zero; differs from Microsoft's: Microsoft's source has no label here |
| FOUT37 | Float::FormatFacAtOffset::ScaleUpSmall | local | all | Float::FormatFacAtOffset::ScaleUpSmall | Multiplies a number below 1 by a million first |
| FOUT7 | Float::FormatFacAtOffset::SetScale | local | all | Float::FormatFacAtOffset::SetScale | Sets the power of ten so far |
| FOUT4 | Float::FormatFacAtOffset::CheckUpper | local | all | Float::FormatFacAtOffset::CheckUpper | Brings the number to 999999.5 or below, dividing by 10 |
| FOUT3 | Float::FormatFacAtOffset::CheckLower | local | all | Float::FormatFacAtOffset::CheckLower | Brings the number above 99999.95, multiplying by 10 |
| FOUT38 | Float::FormatFacAtOffset::MultiplyUp | local | all | Float::FormatFacAtOffset::MultiplyUp | Multiplies by 10, counting the power down |
| FOUT9 | Float::FormatFacAtOffset::DivideDown | local | all | Float::FormatFacAtOffset::DivideDown | Divides by 10, counting the power up |
| FOUT5 | Float::FormatFacAtOffset::RoundHalf | local | all | Float::FormatFacAtOffset::RoundHalf | Rounds to the nearest integer |
| BIGGES | Float::FormatFacAtOffset::ConvertInteger | local | all | Float::FormatFacAtOffset::ConvertInteger | Takes the six-digit integer and decides where the period goes and whether there is an exponent |
| FOUTPI | Float::FormatFacAtOffset::UseExponent | local | all | Float::FormatFacAtOffset::UseExponent | Sets the carry for the subtract |
| FOUT6 | Float::FormatFacAtOffset::SetExponent | local | all | Float::FormatFacAtOffset::SetExponent | Sets the exponent to write, then writes a leading period, or `.0`, when no digit comes before it |
| FOUT39 | Float::FormatFacAtOffset::LeadingPoint | local | all | Float::FormatFacAtOffset::LeadingPoint | Writes the period before the digits, and a 0 after it for a number below 0.1 |
| FOUT16 | Float::FormatFacAtOffset::SavePosition | local | all | Float::FormatFacAtOffset::SavePosition | Keeps the place in the text |
| FOUT8 | Float::FormatFacAtOffset::FirstPower | local | all | Float::FormatFacAtOffset::FirstPower | Writes the six digits, one for each power of ten in Float::PowersOfTen |
| FOUT2 | Float::FormatFacAtOffset::AddPower | local | all | Float::FormatFacAtOffset::AddPower | Takes one digit: adds the power of ten (subtracting for the negative ones) until the number's sign changes, |
| FOUT41 | Float::FormatFacAtOffset::Carried | local | all | Float::FormatFacAtOffset::Carried | Goes on adding until the sign changes |
| FOUT40 | Float::FormatFacAtOffset::DigitFound | local | all | Float::FormatFacAtOffset::DigitFound | Turns the count into the digit: for a power that was subtracted, the count less one; for one added, 10 less it |
| FOUTYP | Float::FormatFacAtOffset::StoreDigit | local | all | Float::FormatFacAtOffset::StoreDigit | Writes the digit, and the period after it when its place comes |
| STXBUF | Float::FormatFacAtOffset::SavePointer | local | all | Float::FormatFacAtOffset::SavePointer | Keeps the place in the text and flips the direction for the next power |
| FOUT11 | Float::FormatFacAtOffset::TrimZeros | local | all | Float::FormatFacAtOffset::TrimZeros | Drops trailing zeros, and the period if it ends the number |
| FOUT12 | Float::FormatFacAtOffset::Exponent | local | all | Float::FormatFacAtOffset::Exponent | Writes the exponent, if any: `E`, its sign and two digits |
| FOUT14 | Float::FormatFacAtOffset::StoreExponentSign | local | all | Float::FormatFacAtOffset::StoreExponentSign | Writes `E`, the sign and the exponent's two digits |
| FOUT15 | Float::FormatFacAtOffset::ExponentTens | local | all | Float::FormatFacAtOffset::ExponentTens | Counts the exponent's tens in X |
| FOUT19 | Float::FormatFacAtOffset::StoreZero | local | all | Float::FormatFacAtOffset::StoreZero | Writes the one character in A, for zero |
| FOUT17 | Float::FormatFacAtOffset::Terminate | local | all | Float::FormatFacAtOffset::Terminate | Ends the text with a zero |
| FOUT20 | Float::FormatFacAtOffset::ReturnBuffer | local | all | Float::FormatFacAtOffset::ReturnBuffer | Returns the text's address |
| FHALF | Float::Half | data | all | Float::Half | The real 0.5, five bytes, the last four shared with ZeroValue |
| ZERO | ZeroValue | data | all | ZeroValue | Eight zero bytes: a real or long integer 0, which an element of an array that does not exist reads as,; differs from Microsoft's: eight zero bytes, for a real or a long integer |
| FOUTBL | Float::PowersOfTen | table | all | Float::PowersOfTen | The powers of ten for Float::FormatFac's digits, as 32-bit integers, most significant byte first: -100000,...; differs from Microsoft's: six powers for six digits, not nine |
| FDCEND | Float::PowersOfTenEnd | table | all | Float::PowersOfTenEnd | The end of Float::PowersOfTen; differs from Microsoft's: after six powers |
| SQR | Functions::Sqr | routine | all | Functions::Sqr | Gives `SQR`: the square root of FAC, as FAC ^ 0.5; differs from Microsoft's: loads 0.5 with the bank in X |
| FPWRT | Float::RaiseArg | routine | all | Float::RaiseArg | The `^` operator: ARG to the power of FAC, as `EXP(FAC * LOG(ARG))`; differs from Microsoft's: saves ARG around FCOMP, which overwrites it; banks |
| FPWRT1 | Float::RaiseArg::NonzeroBase | local | all | Float::RaiseArg::NonzeroBase | Saves the power, and checks a negative base's power is an integer |
| FPLP1 | Float::RaiseArg::SaveArg | local | all |  | Saves ARG, which Float::Compare overwrites |
| FPLP3 | Float::RaiseArg::SetBaseSign | local | all |  | Takes the base's sign from A and restores ARG |
| FPLP2 | Float::RaiseArg::RestoreArg | local | all |  | Restores a byte of ARG |
| FPWR1 | Float::RaiseArg::TakeLog | local | all | Float::RaiseArg::TakeLog | Works out `EXP(power * LOG(base))`, then negates it for an odd power |
| NEGOP | Float::Negate | routine | all | Float::Negate | Negates FAC, unless it is zero |
| NEGRTS | Float::Negate::Done | entry | all | Float::Negate::Done | Returns |
| GOTOEXP | Float::ToExp | routine | all |  | Gives EXP(0), 1, for a zero power |

### B3Expon.asm, LongInt.asm, B3DmpyT.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| LOGEB2 | Float::LogBase2OfE | data | all | Float::LogBase2OfE | The real 1.4426950407, log2(e), which turns a power of e into a power of 2. |
| EXPCON | Float::ExponentialPolynomial | table | all | Float::ExponentialPolynomial | Functions::Exp's polynomial: 2^x for x from 0 to 1, as eight coefficients (a degree of 7), highest power first; they follow the series of e^(x ln 2). |
| EXP | Functions::Exp | routine | all | Functions::Exp | The `EXP` function: e to the power of FAC. |
| STOLD | Functions::Exp::CheckRange | local | all | Functions::Exp::CheckRange | Keeps the product's extra low byte, biased by $50, while the product is copied to ARG unrounded; an exponent of $88 or more is a y of 128 or more in size. |
| GOMLDV | Functions::Exp::OutOfRange | local | all | Functions::Exp::OutOfRange | Gives an overflow error, or 0 for a negative FAC, and returns from `EXP` (MLDVEX). |
| EXP1 | Functions::Exp::Reduce | local | all | Functions::Exp::Reduce | Splits y into its integer part (INT), the scale, and its fraction, and raises 2 to the fraction. |
| SWAPLP | Functions::Exp::SwapLoop | local | all | Functions::Exp::SwapLoop | Exchanges FAC and ARG, exponent to sign: FAC = y again, ARG = `INT(y)`. |
| POLYX | Float::EvaluateOddPolynomial | routine | all | Float::EvaluateOddPolynomial | Evaluates an odd polynomial of FAC: x * P(x^2), for `SIN`, `ATN` and `LOG`. |
| POLY | Float::EvaluatePolynomial | routine | all | Float::EvaluatePolynomial | Evaluates a polynomial of FAC by Horner's rule. |
| POLY1 | Float::EvaluateStoredPolynomial | routine | all | Float::EvaluateStoredPolynomial | Evaluates the polynomial at POLYPT with x in FAC, as Float::EvaluatePolynomial does. |
| POLY3 | Float::EvaluateStoredPolynomial::SetPointer | local | all | Float::EvaluateStoredPolynomial::SetPointer | Points POLYPT at the first coefficient. |
| POLY2 | Float::EvaluateStoredPolynomial::NextTerm | local | all | Float::EvaluateStoredPolynomial::NextTerm | Multiplies by the coefficient at Y and A on the first pass, and by x (TEMPF2) on later ones, and steps to the next coefficient. |
| POLY4 | Float::EvaluateStoredPolynomial::AddTerm | local | all | Float::EvaluateStoredPolynomial::AddTerm | Adds the next coefficient, once for each degree. |
| RMOD_C | Random::Modulus | data | all |  | The long integer 2^31-1, the generator's modulus. |
| RMUL_C | Random::LehmerMultiplier | data | all |  | The long integer 16807, the generator's multiplier. |
| RSMAL_C | Random::Scale | data | all |  | The real 2^-31, which scales the seed to a number between 0 and 1. |
| RND | Functions::Rnd | routine | all |  | The RND function, but a Lehmer generator on long integers, not Microsoft's; same keyword only. |
| RNDMAK | Functions::Rnd::Next | local | all |  | Takes the next number. |
| GETRND | Functions::Rnd::ReturnSeed | local | all |  | Gives the seed as a real between 0 and 1. |
| RNDONE | Random::LoadSeed | routine | all |  | Loads the seed, RNDX, into FAC as a long integer. |
| RNDIT | Random::Advance | routine | all |  | Puts the seed in RNDX through the generator once. |
| RNDAT | Random::AdvanceFac | routine | all |  | Puts the long integer in FAC through the generator, storing the result in RNDX: FAC * 16807 `MOD` (2^31-1). |
| COS | Functions::Cos | routine | all | Functions::Cos | The `COS` function: the cosine of FAC, in radians, as `SIN(x + pi/2)`. |
| SIN | Functions::Sin | routine | all | Functions::Sin | The `SIN` function: the sine of FAC, in radians. |
| SIN1 | Functions::Sin::Reflect | entry | all | Functions::Sin::Reflect | Negates FAC (NEGOP), the start of the fold. |
| SIN2 | Functions::Sin::AddQuarter | local | all | Functions::Sin::AddQuarter | Adds 1/4 and gives the folded fraction the quarter's sign. |
| SIN3 | Functions::Sin::Approximate | local | all | Functions::Sin::Approximate | Evaluates the sine polynomial on the folded fraction. |
| TAN | Functions::Tan | routine | all | Functions::Tan | The `TAN` function: the tangent of FAC, in radians, as the sine over the cosine. |
| COSC | Functions::Tan::Cosine | local | all | Functions::Tan::Cosine | Finishes the cosine through Functions::Sin's fold, with the sign in A. |
| PI2 | Float::HalfPi | data | all | Float::HalfPi | The real 1.5707963267, pi/2. |
| TWOPI | Float::TwoPi | data | all | Float::TwoPi | The real 6.283185307, 2 * pi. |
| FR4 | Float::Quarter | data | all | Float::Quarter | The real 0.25, a quarter turn. |
| SINCON | Float::SinePolynomial | table | all | Float::SinePolynomial | `SIN`'s polynomial: sin(2 * pi * x) for x from -1/4 to 1/4, as an odd polynomial of six coefficients (a degree of 5), highest power first. |
| ATN | Functions::Atn | routine | all | Functions::Atn | The `ATN` function: the arctangent of FAC, in radians. |
| ATN1 | Functions::Atn::Positive | local | all | Functions::Atn::Positive | Takes the reciprocal of an x of 1 or more (an exponent of $81 or more). |
| ATN2 | Functions::Atn::Approximate | local | all | Functions::Atn::Approximate | Evaluates the arctangent polynomial, then takes it from pi/2 if the reciprocal was taken. |
| ATN3 | Functions::Atn::RestoreSign | local | all | Functions::Atn::RestoreSign | Gives the result the argument's sign. |
| ATN4 | Functions::Atn::Done | local | all | Functions::Atn::Done | Returns. |
| ATNCON | Float::ArctangentPolynomial | table | all | Float::ArctangentPolynomial | `ATN`'s polynomial: the arctangent of x for x from 0 to 1, as an odd polynomial of twelve coefficients (a degree of 11), highest power first; they are close to the series x - x^3/3 + x^5/5 - ... |
| LINP | LongInteger::ReadNumber | routine | all |  | Reads a long integer from the text at TXTPTR into FAC. |
| LZFAC1 | LongInteger::ReadNumber::ClearLoop | local | all |  | Zeros FAC and ARG. |
| LISNUM | LongInteger::ReadNumber::TakeDigit | local | all |  | Takes a digit into FAC: FAC = FAC * 10 + the digit. |
| LTRYN2 | LongInteger::ReadNumber::NextCharacter | local | all |  | Goes on to the next character, taking it if it is a digit. |
| LTRYDOT | LongInteger::ReadNumber::CheckFraction | local | all |  | Rounds by the fraction after a period, if any: up from a first digit above 5, or of 5 with any other digit after it. |
| LTRYN3 | LongInteger::ReadNumber::SeekNonzeroDigit | local | all |  | After a 5, looks for a digit other than 0, which rounds up; with none, the number rounds to even. |
| LROUNDUP | LongInteger::ReadNumber::RoundUp | local | all |  | Rounds up, then skips the fraction's other digits. |
| LNUMSCN | LongInteger::ReadNumber::SkipFraction | local | all |  | Skips the fraction's remaining digits. |
| LRNDEVN | LongInteger::ReadNumber::RoundToEven | local | all |  | Rounds exactly half to the even integer: up when FAC is odd. |
| LNUMDON | LongInteger::ReadNumber::ApplySign | local | all |  | Ends the number, negating it for a minus sign. |
| LTWSCOMP | LongInteger::NegateFac | routine | all |  | Negates FAC. |
| LTWSONE | LongInteger::NegateFac::ComplementLoop | local | all |  | Complements FAC's bytes, before LongInteger::IncrementFac adds one. |
| LINCFAC | LongInteger::IncrementFac | routine | all |  | Adds one to FAC. |
| LTWSCO2 | LongInteger::IncrementFac::IncrementLoop | local | all |  | Increments FAC's bytes from the lowest while each carries. |
| LOVINP | LongInteger::IncrementFac::ToOverflowError | entry | all |  | Ends with an overflow error. |
| LDONE | LongInteger::IncrementFac::Done | entry | all |  | Returns. |
| LTIMES10 | LongInteger::MultiplyFacByTen | routine | all |  | Multiplies FAC by 10, as FAC * 2 + FAC * 8, and leaves LongInteger::PointAtOperands's pointers set. |
| FACTOARG | LongInteger::CopyFacToArg | routine | all |  | Copies FAC to ARG. |
| FAC2AR2 | LongInteger::CopyFacToArg::CopyLoop | local | all |  | Copies FAC's bytes to ARG, from the last. |
| LSGNPOS | LongInteger::MakeOperandsPositive | routine | all |  | Makes the two operands positive for a multiply or divide, noting the result's sign. |
| LSGNP2 | LongInteger::MakeOperandsPositive::SecondOperand | local | all |  | Makes the second operand positive. |
| LSGNP3 | LongInteger::MakeOperandsPositive::Done | local | all |  | Returns. |
| LRESPOS | LongInteger::ReturnProduct | routine | all |  | Moves a product from RES to FAC with its sign, or ends with an overflow error when it grew past RES. |
| LRESDIV | LongInteger::ReturnQuotient | routine | all |  | Moves a quotient from RES to FAC with its sign. |
| LRESDV | LongInteger::ReturnResult | routine | all |  | Moves a result from (PTR3) to FAC, negating it first when INPFLG says the result is negative. |
| LRESP2 | LongInteger::ReturnResult::Copy | local | all |  | Copies the eight bytes. |
| LRES2F2 | LongInteger::ReturnResult::CopyLoop | local | all |  | Copies a byte, from the last. |
| LZIPRES | LongInteger::ClearResult | routine | all |  | Zeros RES and the overflow byte below it. |
| LZIP2 | LongInteger::ClearResult::ClearLoop | local | all |  | Zeros a byte, from the last. |
| STFACT | LongInteger::StoreFac | routine | all |  | Stores FAC as a long integer in memory. |
| STFAC2 | LongInteger::StoreFac::StoreLoop | local | all |  | Stores a byte, from the last. |
| LPTRS | LongInteger::PointAtOperands | routine | all |  | Points PTR1 and PTR3 at FAC and PTR2 at ARG, all in zero page, for FAC = FAC op ARG. |
| LADD | LongInteger::Add | routine | all |  | The `+` operator for long integers: FAC = ARG + FAC. |
| LADDPTR | LongInteger::AddAt | routine | all |  | Adds two long integers: (PTR3) = (PTR1) + (PTR2). |
| LADD2 | LongInteger::AddAt::AddLoop | local | all |  | Adds a byte, from the last. |
| LOVERR | LongInteger::OverflowError | routine | all |  | Ends the statement with an overflow error. |
| LSUBB | LongInteger::SubtractUnchecked | routine | all |  | Subtracts with the pointers set: FAC = ARG - FAC, with no overflow check. |
| LSUBER | LongInteger::SubtractAt | routine | all |  | Subtracts two long integers: (PTR3) = (PTR2) - (PTR1), with no overflow check. |
| LSUB2 | LongInteger::SubtractAt::SubtractLoop | local | all |  | Subtracts a byte, from the last. |
| LSUB | LongInteger::Subtract | routine | all |  | The `-` operator for long integers: FAC = ARG - FAC. |
| TWOSCOMP | LongInteger::NegateAt | routine | all |  | Negates a long integer in zero page. |
| LEORIT | LongInteger::NegateAt::ComplementLoop | local | all |  | Complements the bytes, from the first. |
| INCPTR2 | LongInteger::NegateAt::IncrementLoop | local | all |  | Adds one, from the last byte, while each carries. |
| INCRT2 | LongInteger::NegateAt::Done | local | all |  | Returns. |
| LMULT | LongInteger::Multiply | routine | all |  | The `*` operator for long integers: FAC = ARG * FAC. |
| LMULT1 | LongInteger::Multiply::Row | local | all |  | Multiplies the row's byte of FAC by each byte of ARG. |
| LMULT2 | LongInteger::Multiply::Column | local | all |  | Multiplies the row's byte by one byte of ARG, unless it is zero. |
| LMULT3 | LongInteger::Multiply::NextRow | local | all |  | Moves on to the next byte of FAC, a byte higher in RES. |
| LMULTBYT | LongInteger::MultiplyBytes | routine | all |  | Multiplies the byte at (PTR1) by the byte at (PTR2) and adds the 16-bit product into RES at (PTR3). |
| LMULTB2 | LongInteger::MultiplyBytes::BitLoop | local | all |  | Adds the multiplicand for each 1 bit of the multiplier, shifting the product right. |
| LMULTB3 | LongInteger::MultiplyBytes::ShiftProduct | local | all |  | Shifts the product right a bit, with the carry from the add. |
| LMULTOV | LongInteger::MultiplyBytes::ToOverflowError | local | all |  | Ends with an overflow error. |
| LMULTB4 | LongInteger::MultiplyBytes::CarryLoop | local | all |  | Carries into the bytes above, as far as RES-1. |
| LMULTBR | LongInteger::MultiplyBytes::Done | local | all |  | Returns. |
| LSHFTL | LongInteger::ShiftLeft | routine | all |  | Shifts a long integer in zero page left one bit, a 0 in. |
| LSHFTLC | LongInteger::ShiftLeftWithCarry | routine | all |  | Shifts a long integer in zero page left one bit, the carry in. |
| LSHFT2 | LongInteger::ShiftLeftWithCarry::RotateLoop | local | all |  | Rotates a byte, from the last. |
| LSHFTR | LongInteger::ShiftRight | routine | all |  | Shifts a long integer in zero page right one bit, a 0 in. |
| LSHFTR2 | LongInteger::ShiftRight::RotateLoop | local | all |  | Rotates a byte, from the first. |
| LSHLEIGT | LongInteger::ShiftFacLeftByte | routine | all |  | Shifts FAC left eight bits, a byte at a time. |
| LSHLE2 | LongInteger::ShiftFacLeftByte::MoveLoop | local | all |  | Moves a byte up. |
| LDIVER | LongInteger::DivideMagnitudes | routine | all |  | Divides the magnitude of ARG by that of FAC, the work of `DIV`, `/` and `MOD`. |
| LDECYSAV | LongInteger::DivideMagnitudes::ShiftQuotient | local | all |  | Shifts the quotient bit in the carry into RES, once a subtraction has been made, and the dividend left. |
| LRESOK | LongInteger::DivideMagnitudes::ShiftDividend | local | all |  | Shifts the dividend left. |
| LDIVCOM | LongInteger::DivideMagnitudes::Step | local | all |  | Compares the dividend with the divisor and subtracts it when it fits, until the steps are done. |
| LGOTRES | LongInteger::DivideMagnitudes::Done | local | all |  | Returns. |
| LDIVT | LongInteger::Divide | routine | all |  | The `/` operator for long integers: FAC = ARG / FAC, rounded to the nearest integer, an exact half to the even one. |
| LINCBYT | LongInteger::Divide::IncrementLoop | local | all |  | Adds one to the quotient in RES, from the last byte. |
| LNOROUND | LongInteger::Divide::Finish | local | all |  | Moves the quotient to FAC with its sign. |
| LNRMFAC | LongInteger::NormalizeFac | routine | all |  | Shifts FAC left until its top 1 bit is bit 62, counting the shifts. |
| LDIVE2 | LongInteger::NormalizeFac::ByteLoop | local | all |  | Shifts a byte at a time while the top byte is zero. |
| LDIVE3 | LongInteger::NormalizeFac::BitLoop | local | all |  | Shifts a bit at a time until bit 6 of the top byte is set. |
| LDIVTOFAR | LongInteger::NormalizeFac::TooFar | local | all |  | Shifts the one bit right that went too far. |
| LDIVOK | LongInteger::NormalizeFac::Done | local | all |  | Returns. |
| LCOMP | LongInteger::CompareMagnitudes | routine | all |  | Compares ARG with FAC as unsigned numbers. |
| LCMP2 | LongInteger::CompareMagnitudes::FromByte | entry | all |  | Compares from the byte at X on. |
| LCMP3 | LongInteger::CompareMagnitudes::Done | local | all |  | Returns. |
| LDIV | LongInteger::Div | routine | all |  | The `DIV` operator for long integers: FAC = ARG / FAC, the fraction dropped. |
| LREM | LongInteger::Mod | routine | all |  | The `MOD` operator for long integers: FAC = the remainder of ARG / FAC. |
| LREM2 | LongInteger::Mod::ShiftBack | local | all |  | Shifts the remainder back right KIMY + 1 bits. |
| LORALL | LongInteger::IsZero | routine | all |  | Tells whether a long integer is zero, by ORing its bytes. |
| LORAL2 | LongInteger::IsZero::OrLoop | local | all |  | ORs in a byte, from the last, stopping at the first nonzero one. |
| LGOTOR | LongInteger::IsZero::Done | local | all |  | Returns. |
| LUNPACK | LongInteger::FacToDigits | routine | all |  | Turns FAC's long integer into decimal digits in NUMSTR, for LongInteger::FormatFac and `PRINT USING`. |
| LCONVBCD | LongInteger::FacToDigits::ConvertBit | local | all |  | Converts one bit: shifts it out of FAC and doubles the decimal number with the bit added. |
| LADDBCD | LongInteger::FacToDigits::DoubleLoop | local | all |  | Doubles a byte of the decimal number with the carry, from the last. |
| LABCD2 | LongInteger::FacToDigits::CopyLoop | local | all |  | Copies the decimal number to FACT, where UUNPACK reads it. |
| LZIPARG | LongInteger::ClearArg | routine | all |  | Zeros ARG and the two bytes after it, RES-1 and RES. |
| LZIPAR2 | LongInteger::ClearArg::ClearLoop | local | all |  | Zeros a byte, from the last. |
| LOUT | LongInteger::FormatFac | routine | all |  | Writes FAC's long integer as text in NUMSTR: a minus sign if negative, then the digits, then a zero. |
| LLOOKLUP | LongInteger::FormatFac::NextDigit | local | all |  | Takes the next digit, ending when there are no more. |
| LOUT5 | LongInteger::FormatFac::WriteDigit | local | all |  | Writes a digit as its character. |
| LOUT3 | LongInteger::FormatFac::WriteSign | local | all |  | Writes a minus sign before the first digit of a negative number. |
| LLOKLUP | LongInteger::FormatFac::WriteFirstDigit | local | all |  | Takes the first digit back to write it. |
| LISZERO | LongInteger::FormatFac::Finish | local | all |  | Ends the text with a zero, keeping at least the one character, `0`. |
| LONGST0 | LongInteger::SetFacToZero | routine | all |  | Sets FAC to the long integer 0. |
| LONGST | LongInteger::SetFacToZero::FillLoop | local | all |  | Fills FAC's bytes up to X with A. |
| LONGST1 | LongInteger::SetFacToOne | routine | all |  | Sets FAC to the long integer 1. |
| LDFACT | LongInteger::LoadFac | routine | all |  | Loads a long integer from memory into FAC. |
| DMOVFM | LongInteger::LoadFac | routine | all |  | A second label on LDFACT (the same address): loads a long integer into FAC. |
| LDFAC2 | LongInteger::LoadFac::LoadLoop | local | all |  | Loads a byte, from the last. |
| CONV2FLT | Functions::Conv | routine | all |  | The `CONV` function: the FAC's value as a real. |
| LMAKFLT | LongInteger::ToReal | routine | all |  | Converts FAC's long integer to a real. |
| CONV2RTS | LongInteger::ToReal::Done | entry | all |  | Returns. |
| STR2FLT | LongInteger::StringToReal | routine | all |  | Reads a string as a real, as `VAL` does, for Functions::Conv. |
| CONV2LNG | Functions::ConvLong | routine | all |  | The `CONV&` function: the FAC's value as a long integer. |
| PASSABIT | Functions::ConvLong::MoveBit | local | all |  | Moves the integer's bits from the real's mantissa into ARG, one at a time. |
| GTFACNA | Functions::ConvLong::Finish | local | all |  | Moves the magnitude in ARG to FAC and gives it the real's sign. |
| ASLFAC | LongInteger::ShiftRealLeft | routine | all |  | Shifts the real FAC's mantissa left one bit, FACOV included. |
| CONV2RT2 | LongInteger::ShiftRealLeft::Done | entry | all |  | Returns. |
| STR2LNG | LongInteger::StringToLong | routine | all |  | Reads a string as a long integer, through `VAL`'s code (VALSTR) with LongInteger::ReadNumber. |
| CONV2INT | Functions::ConvInteger | routine | all |  | The `CONV%` function: the FAC's value rounded to an integer, as a real. |
| QINTRN | Float::RoundToInteger | routine | all |  | Rounds the real FAC to the nearest integer, a half upward, as `INT(x + .5)` does. |
| CONV2STR | Functions::ConvString | routine | all |  | The `CONV$` function: the FAC's value as a string, as `STR$` writes it. |
| CONWASL | Functions::ConvString::FromLong | local | all |  | Makes a long integer's text a string. |
| LAND | LongInteger::And | routine | all |  | The `AND` operator for long integers: 1 when ARG and FAC are both nonzero, else 0. |
| LGIVM1 | LongInteger::SetFacToTruth | routine | all |  | Sets FAC to 1 when the zero flag is clear, or to 0 when it is set. |
| LGIVM0 | LongInteger::SetFacToTruth::ToSetFacToZero | entry | all |  | Sets FAC to 0. |
| LONGOR | LongInteger::Or | routine | all |  | The `OR` operator for long integers: 1 when ARG or FAC is nonzero, else 0. |
| LDOCOMP | LongInteger::Compare | routine | all |  | The relational operators for long integers: 1 when the comparison of ARG with FAC holds, else 0. |
| LISL | LongInteger::Compare::Less | local | all |  | ARG is less than FAC. |
| LISEQ | LongInteger::Compare::Equal | local | all |  | ARG equals FAC. |
| LISG | LongInteger::Compare::Greater | local | all |  | ARG is greater than FAC. |
| DECER | Functions::Ten | routine | all |  | The `TEN` function: the value of a string of hexadecimal digits, as a 16-bit signed integer. |
| STARTAT0 | Functions::Ten::FillZeros | local | all |  | Fills the four-character work area at RES with zeros. |
| PUTINUM | Functions::Ten::CopyCharacters | local | all |  | Copies up to four characters from the string's end into RES, right-aligned. |
| GOTANUM | Functions::Ten::Convert | local | all |  | Converts the four characters at RES into FACMO (the high byte) and FACLO, two digits a byte. |
| GETAHEX | Functions::Ten::ConvertByte | local | all |  | Converts two characters, low digit first, into one byte of the result. |
| DNNIB | Hexadecimal::DigitValue | routine | all |  | Turns one hexadecimal character into its value, 0 to 15, stepping Y back first. |
| DECDN | Hexadecimal::DigitValue::Done | local | all |  | Returns the digit's value. |
| HEXS | Functions::Hex | routine | all |  | The `HEX$` function: a 16-bit number as four hexadecimal digits. |
| MAKHEX | Functions::Hex::WriteByte | local | all |  | Writes one byte of the number as two digits, right to left. |
| DONIB | Hexadecimal::Digit | routine | all |  | Turns a value from 0 to 15 into its hexadecimal digit. |
| GOTNIB | Hexadecimal::Digit::Done | local | all |  | Returns the digit. |
| QNERR | Hexadecimal::ReportIllegalQuantity | routine | all |  | Ends the statement with an illegal quantity error. |
| SWAP | Statements::Swap | routine | all |  | The `SWAP` statement: exchanges the values of two variables of the same type, simple or array elements. |
| MISERR | Statements::Swap::ToTypeMismatch | entry | all |  | Ends the statement with a type mismatch error (CHKERR). |
| SWAP1 | Statements::Swap::SameType | local | all |  | Checks the value types match, then takes the first variable's address back into INDEX1. |
| TRNSFR | Statements::Swap::Exchange | local | all |  | Exchanges Y + 1 bytes between (INDEX1) and (VARPNT). |
| ONEISGD | Statements::Swap::FirstHasText | local | all |  | The first descriptor's string has text: exchanges info bytes if the second's has too, or else rebuilds the first's back pointer. |
| MAKNUL | Statements::Swap::RebuildBackPointer | local | all |  | Points the string in INDEX's descriptor back at that descriptor, from the descriptor address and array flag on the stack (FIXBAK). |
| OLDSWAP | Statements::Swap::BothHaveText | local | all |  | Both strings have text: exchanges their three info bytes, so each points back at its new descriptor. |
| SWPRTS | Statements::Swap::Done | local | all |  | Returns. |
| TRNS | Strings::SwapPointers | routine | all |  | Exchanges the pointers INDEX and VARPNT, banks included, for `SWAP`. |
| INCNDX | Strings::PointAtInfoBytes | routine | all |  | Points INDEX past a string's text, at its info bytes, from the descriptor it points to. |
| INCNDRTS | Strings::PointAtInfoBytes::Done | local | all |  | Returns. |

### StrngStuf.asm, Invoke.asm, Invoke1.asm, BasicEnd.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| STRS | Functions::Str | routine | all | Functions::Str | The `STR$` function: the characters `PRINT` would give for the number in the <FAC>, as a string. |
| STRINI | Strings::AllocateForFac | routine | all | Strings::AllocateForFac | Takes space for a string of A characters, with FACMO's descriptor as the one it is made from. |
| STRIN2 | Strings::AllocateForFac::ForDescriptor | entry | all |  | Takes the descriptor's address from X and Y, its bank already in DSCPNTB. |
| STRSPA | Strings::Allocate | routine | all | Strings::Allocate | Takes space for a string of A characters in string space and builds its descriptor in DSCTMP. |
| STRMVLP | Strings::Allocate::MarkTemporary | local | all |  | Zeroes the descriptor's address in the bytes after the string, then gives them <TEMPTYP>'s type. |
| STRRT3 | Strings::Allocate::Done | local | all |  | Returns. |
| STRLIT | Strings::FromText | routine | all | Strings::FromText | Makes a string of the literal at Y,A (bank X), which ends at a quote or a zero, and gives it as the result. |
| STRLT2 | Strings::FromTextUntil | routine | all | Strings::FromTextUntil | Makes a string of the characters at Y,A (bank X), up to a zero or the character in <CHARAC> or <ENDCHR>, and gives |
| STRGET | Strings::FromTextUntil::Scan | local | all | Strings::FromTextUntil::Scan | Counts the characters up to the end. |
| STRFIN | Strings::FromTextUntil::AtDelimiter | local | all | Strings::FromTextUntil::AtDelimiter | Ended by <CHARAC> or <ENDCHR>: a quote leaves carry set, so <STRNG2> goes past it. |
| STRFI1 | Strings::FromTextUntil::AtZero | entry | all | Strings::FromTextUntil::AtZero | Ended otherwise: <STRNG2> stays at the ending character. |
| STRFI2 | Strings::FromTextUntil::SetLength | local | all | Strings::FromTextUntil::SetLength | Keeps the count and sets <STRNG2> at the end, plus carry. |
| STRST2 | Strings::FromTextUntil::StoreEnd | local | all |  | Stores the end page (AppleSoft's STRST2, CheckPage, also picks copying; here it always copies) |
| STRCP | Strings::CopyText | routine | all | Strings::FromTextUntil::CopyText (a local there) | Its own proc: other files and JMPRTAB call it |
| PUTNEW | Strings::PushTemporary | routine | all | Strings::PushTemporary | Copies <DSCTMP> into the next free temporary descriptor and points FACMO to it: the result is a string. |
| PUTNW1 | Strings::PushTemporary::Store | local | all | Strings::PushTemporary::Store | Stores the descriptor and moves <TEMPPT> on. |
| PREFIXS | Functions::Prefix | routine | all |  | The `PREFIX$` function: SOS's prefix, as a string. |
| GOTITNOW | Functions::Prefix::MakeString | entry | all |  | Makes a string of the A characters at <CATBUF>+2 and gives it as the result. |
| TIMES | Functions::Time | routine | all |  | The `TIME$` function: the time from SOS's clock, as `HH:MM:SS`. |
| DATES | Functions::Date | routine | all |  | The `DATE$` function: the date from SOS's clock, as `YY/MM/DD`. |
| DATE01 | Functions::Date::ReadClock | entry | all |  | Reads SOS's clock and makes a string of three pairs of digits from offset Y, each followed by the separator in A, |
| DATE02 | Functions::Date::CopyPair | local | all |  | Copies a pair down to X and adds the separator; X never passes Y, so the copy is safe in place. |
| PREFIXSET | Statements::Prefix | routine | all |  | The `PREFIX$` statement, `PREFIX$ = pathname`: sets SOS's prefix. |
| JSERROR | Statements::Prefix::ToSosError | entry | all |  | Ends the statement with the SOS error. |
| PROGPFXS | Functions::ProgPrefix | routine | 1.3 |  | 1.3's `PROGPREFIX$` function: the program's prefix, PROGPATH, as a string. |
| PROGPFX | Statements::ProgPrefix | routine | 1.3 |  | 1.3's `PROGPREFIX$` statement, `PROGPREFIX$ = pathname`: sets the program's prefix. |
| PROGPFX1 | Statements::ProgPrefix::EndsInSlash | local | 1.3 |  | Keeps the name as the program's prefix. |
| INSTR | Functions::InStr | routine | all |  | The `INSTR` function, `INSTR(source, target, start)`: the position of target in source, from start on, or 0. |
| TRYAGM | Functions::InStr::TryPosition | local | all |  | Tries target at each position from <TEMP> to <KIMY>. |
| INMAT2 | Functions::InStr::CompareNext | local | all |  | Compares the next character. |
| INNOTIT | Functions::InStr::NextPosition | local | all |  | Moves on to the next position. |
| NMTCH2 | Functions::InStr::NotFound | local | all |  | Not found: gives 0. |
| GIVMZERO | Functions::InStr::NotFound | local | all |  | Not found: gives 0. |
| GIVMIT | Functions::InStr::ReturnPosition | local | all |  | Gives Y+1 as a number, after freeing both strings if they are temporaries. |
| SUBLEFT | Statements::Sub | routine | all |  | The `SUB$` statement, `SUB$(var, start, length) = string`: writes string's characters over var's from start on, up |
| FAKEIT | Statements::Sub::NoLength | local | all |  | No length: 255, all of the string. |
| SUBFUC | Statements::Sub::ToIllegalQuantityError | local | all |  | Ends the statement with ILLEGAL QUANTITY. |
| SUBLNK1 | Statements::Sub::FillSpaces | local | all |  | Fills the new string with spaces, from Y down to 1, then the first. |
| GOTITTY | Statements::Sub::Fits | local | all |  | Fits: <INDEX2>, var's distance below <HIMEM>, becomes the address. |
| GOTABS | Statements::Sub::AtAddress | local | all |  | Points <INDEX2> at the first character to replace. |
| GOTABS1 | Statements::Sub::CopyCharacters | local | all |  | Copies <DELTA> characters of the string over var's. |
| SUBMOV | Statements::Sub::CopyNext | local | all |  | Copies the next character. |
| SBMV2 | Statements::Sub::CheckCount | local | all |  | Copies another while Y is below <DELTA>. |
| FRECNOW | Strings::FreeFacTemporary | routine | all |  | Frees the string in <FACMO> if it is a temporary. |
| RELINX | Strings::DistanceToAddress | routine | all |  | Turns INDEX2 from a distance below <HIMEM> into an address: <HIMEM> less it, across banks. |
| CHRS | Functions::Chr | routine | all | Functions::Chr | The `CHR$` function: a string of one character, the argument's (0-255). |
| LEFTS | Functions::Left | routine | all | Functions::Left | The `LEFT$` function: the string's first n characters, or all of it when it is shorter. |
| RLEFT | Functions::Slice | routine | all | Functions::Slice | Makes the result of `LEFT$`, `RIGHT$` and `MID$`: X characters from offset A, or all of the string when carry is |
| RLEFT1 | Functions::Slice::PushStart | local | all | Functions::Slice::PushStart | Pushes the offset. |
| RLEFT2 | Functions::Slice::CountInX | entry | all | Functions::Slice::CountInX | Takes the length from X. |
| RLEFT3 | Functions::Slice::CountInA | entry | all | Functions::Slice::CountInA | Copies A characters from the string, from the offset on the stack, into a new string, frees the old one if it is a |
| PULMOR | Functions::Slice::Copy | local | all | Functions::Slice::Copy | Copies the characters, frees the old string and gives the new one. |
| RIGHTS | Functions::Right | routine | all | Functions::Right | The `RIGHT$` function: the string's last n characters, or all of it when it is shorter. |
| MIDS | Functions::Mid | routine | all | Functions::Mid | The `MID$` function, `MID$(string, start, length)`: length characters from start on (all the rest when length is |
| MID2 | Functions::Mid::HaveLength | local | all | Functions::Mid::HaveLength | Works out the offset and the length to copy. |
| PREAM | Functions::SliceArguments | routine | all | Functions::SliceArguments | Checks the closing parenthesis and takes the arguments of `LEFT$`, `RIGHT$` and `MID$` off the stack, from under |
| LEN | Functions::Len | routine | all | Functions::Len | The `LEN` function: the string's length, freeing it if it is a temporary. |
| LEN0 | Functions::Len::FreeArgument | entry | all |  | Frees the string at DSCPNT if it is a temporary. |
| FRETNOW | Strings::FreeTemporary | routine | all |  | Frees the string whose descriptor is at Y,A (bank X), if it is a temporary. |
| LEN1 | Functions::FindArgument | routine | all |  | Finds the argument without freeing it (AppleSoft's LEN1 frees), so its own name |
| ASC | Functions::Asc | routine | all | Functions::Asc (keyword; -1 for empty here) | The `ASC` function: the code of the string's first character, or -1 for an empty string. |
| GOFUC | Functions::ToIllegalQuantityError | routine | all | Functions::ToIllegalQuantityError | Ends the statement with ILLEGAL QUANTITY, for the string functions and the byte conversions. |
| GTBYTC | SkipAndEvaluateByte | routine | all | SkipAndEvaluateByte | Moves past the current character, then reads a formula as a byte, 0-255. |
| GETBYT | EvaluateByte | routine | all | EvaluateByte | Reads a formula as a byte, 0-255. |
| CONINT | ConvertToByte | routine | all | ConvertToByte | Makes the <FAC> a byte, 0-255. |
| VAL | Functions::Val | routine | all | Functions::Val | The `VAL` function: the number the string's characters spell, as `INPUT` would read it. |
| VALSTR | Functions::ParseStringWith | routine | all |  | Calls the routine at Y,A with <TXTPTR> at the string's characters, then puts <TXTPTR> back. |
| ST2TXT | SetTextPointer | routine | all | SetTextPointer | Puts TXTPTR back from STRNG2. |
| VALRTS | SetTextPointer::Done | entry | all | SetTextPointer::Done | Returns. |
| GIVM1 | Functions::ReturnMinusOne | routine | all |  | Puts -1 in the FAC: `ASC`'s answer for an empty string. |
| CON1M | Functions::MinusOne | data | all |  | -1 as a packed real: the exponent, then the sign over the mantissa. |
| GETABYT | EvaluateSignedByte | routine | all |  | Reads a formula as a signed byte, -128 to 127. |
| GETADR | ConvertToAddress | routine | all | ConvertToAddress | Makes the <FAC> a 16-bit address in POKER, for `PEEK`, `POKE` and the like. |
| OFFSST | Modules::Target | alias | all |  | The address a self-relative pointer gives, from <Modules::FollowPointer>, or the word a relocation fixes. |
| PROCPNT | Modules::WalkPointer | alias | all |  | The walking pointer: down the code's dictionaries, then along the records. |
| SWPPNT | Modules::AddendPointer | alias | all |  | The zero-page pointer whose value <Modules::ApplyRelocations> adds: <Modules::CodeStart> or <HIGHTR>. |
| TEMPTR | Modules::RelocationsLeft | alias | all |  | <Modules::ApplyRelocations>'s count of words left to relocate. |
| POINT1 | Modules::CodeStart | alias | all |  | The start of the module's code. |
| POINT1B | Modules::CodeStartXByte | alias | all |  | <Modules::CodeStart>'s X-byte. |
| POINT2 | Modules::OtherPointer | alias | all |  | A second pointer: into the procedure dictionary, to a record, or a value. |
| POINT2B | Modules::OtherPointerXByte | alias | all |  | <Modules::OtherPointer>'s X-byte. |
| PROCPNTB | Modules::WalkPointerXByte | alias | all |  | <Modules::WalkPointer>'s X-byte. |
| OFFSSTB | Modules::TargetXByte | alias | all |  | <Modules::Target>'s X-byte. |
| SWPPNTB | Modules::AddendPointerXByte | alias | all |  | <Modules::AddendPointer>'s X-byte, 0 to read the zero page directly. |
| INERROM | Modules::ToOutOfMemoryError | routine | all |  | Ends the statement with an out-of-memory error: there is no room for a module's first block. |
| DOINVO | Modules::Load | routine | all |  | Loads, relocates and links each module the statement names, then moves the records kept up against the code. |
| DOFILE | Modules::LoadFile | routine | all |  | Loads the next module, or ends with <Modules::MoveRecordsUp> at the statement's end. |
| MARKLOW | Modules::LoadFile::RoundUpToBlock | local | all |  | Rounds the mark's page up to a block, and sets the mark there. |
| DOAPROC | Modules::RelocateProcedure | routine | all |  | Relocates one procedure: puts its entry point's address in its procedure dictionary entry, then applies its |
| DOLIB | Modules::ResolveProcedures | routine | all |  | Linking's first pass: replaces the procedure number in each .PROC, .FUNC and .DEF record with that procedure's |
| DOPAS1 | Modules::ResolveProcedures::TakeRecord | local | all |  | Takes the record at <WalkPointer> in the first pass. |
| DOPA13 | Modules::ResolveProcedures::SkipReferences | entry | all |  | Moves WalkPointer past a .REF record's list of references, the count at offset 12 rounded up to 8 words, so that |
| DOPA12 | Modules::ResolveProcedures::SkipReferenceRecord | local | all |  | Skips a .REF record in the first pass. |
| DOPA11 | Modules::ResolveProcedures::ResolveNumber | local | all |  | Replaces a .PROC's, .FUNC's or .DEF's procedure number, at offset 10, with the procedure's entry point. |
| DOPA14 | Modules::ResolveProcedures::Advance | local | all |  | Moves on to the next record in the first pass. |
| DOPAS2 | Modules::LinkReferences | routine | all |  | Linking's second pass: for each .REF record, finds the .DEF of the same name and adds the label's offset in the |
| DOPA20 | Modules::LinkReferences::TakeRecord | local | all |  | Takes the record at <WalkPointer> in the second pass. |
| DOPA22 | Modules::LinkReferences::CheckType | local | all |  | Takes a record of type A. |
| DOPA29 | Modules::LinkReferences::Skip | local | all |  | Moves on to the next record in the second pass. |
| DOPA25 | Modules::LinkReferences::AddOffset | local | all |  | Adds the .DEF's offset in the code to each word the .REF record at OtherPointer lists, then moves past the list. |
| DOPA27 | Modules::LinkReferences::AddToWord | local | all |  | Adds the label's offset to the next referring word. |
| DOPAS3 | Modules::CompactRecords | routine | all |  | Compacts the module's records in place, keeping only its .PROC and .FUNC records, then loads the next module, with |
| DOPA31 | Modules::CompactRecords::CheckRecord | local | all |  | Keeps the record at <WalkPointer> if it is a .PROC or .FUNC. |
| DOPA32 | Modules::CompactRecords::Skip | local | all |  | Moves on to the next record, or at the end loads the next module. |
| DOPA37 | Modules::CompactRecords::KeepRecord | local | all |  | Copies the 16-byte record at <WalkPointer> down to <OtherPointer>, and moves <OtherPointer> past it. |
| DOPA38 | Modules::CompactRecords::CopyByte | local | all |  | Copies the next byte, from the last. |
| DOCRNCH | Modules::MoveRecordsUp | routine | all |  | Moves the records kept, from <INVTAB> to <INVPNT>, up against the lowest module's code, so the free memory left is |
| DEC2PROC | Modules::StepBack | routine | all |  | Moves <Modules::WalkPointer> down two bytes, to the next word of a dictionary or attribute table. |
| MAKESUR0 | Modules::CheckNoRelocations | routine | all |  | Moves <Modules::WalkPointer> down to the next word, which must be zero (an empty relocation list BASIC can't apply), |
| INVERROR | Modules::InvokeError | routine | all |  | Ends the statement with the `INVOKE` error, <ERRIN>: a module BASIC can't load or link. |
| DOAREL | Modules::ApplyRelocations | routine | all |  | Applies one relocation list of the attribute table at <Modules::WalkPointer>: adds the word |
| DOARE0 | Modules::ApplyRelocations::NextHigh | local | all |  | Counts down the count's high byte, at each 256 words. |
| DOARE1 | Modules::ApplyRelocations::NextWord | local | all |  | Relocates the next word. |
| DOARTS | Modules::ApplyRelocations::Done | local | all |  | Returns. |
| RELPROC | Modules::FollowPointer | routine | all |  | Moves <Modules::WalkPointer> down to the next word and follows it as a self-relative pointer. |
| ADDPROC | Modules::AddToWalkPointer | routine | all |  | Adds A to <Modules::WalkPointer>. |
| NXTPROC | Modules::NextRecord | routine | all |  | Moves <Modules::WalkPointer> to the next 16-byte linker record and loads its type. |
| PERFORM | Statements::Perform | routine | all |  | The `PERFORM` statement: calls a procedure an invoked module defines with .PROC, passing the arguments in |
| PERFEXF | Modules::CallByName | routine | all |  | Reads a procedure's or function's name and arguments, finds it, and calls it through <Modules::CallModule>. |
| PERFE1 | Modules::CallByName::FillName | local | all |  | Fills the next byte of the name. |
| PERERR | Modules::CallByName::ToSyntaxError | local | all |  | Ends the statement with a syntax error: no name. |
| PERFE05 | Modules::CallByName::ToFind | local | all |  | Goes to <Find>, out of a branch's reach. |
| PERFE2 | Modules::CallByName::NextCharacter | local | all |  | Reads the name's next character. |
| PERFE3 | Modules::CallByName::TakeCharacter | local | all |  | Takes the character in A. |
| PERFE35 | Modules::CallByName::AddCharacter | local | all |  | Adds a letter or digit to the name, in upper case. |
| PERFE4 | Modules::CallByName::ReadArgument | local | all |  | Reads one argument and pushes it. |
| PERINT1 | Modules::CallByName::IntegerArgument | local | all |  | Pushes an integer argument, after its `%`. |
| PERLONG1 | Modules::CallByName::LongArgument | local | all |  | Pushes a long-integer argument, after its `&`. |
| PERLNG1 | Modules::CallByName::PushLongByte | local | all |  | Pushes the next byte of the long integer. |
| PERVAL1 | Modules::CallByName::AddressArgument | local | all |  | Pushes a variable's address, after its `@`, and puts it with its bank byte in <BANKPNT>. |
| PERVAL2 | Modules::CallByName::CountWords | local | all |  | Adds the argument's words to <NPARAMS>, then reads the next argument after a comma, or ends at the closing |
| PERFE6 | Modules::CallByName::SkipEnd | local | all |  | Skips the character that ended the name or the arguments. |
| PERFE5 | Modules::CallByName::Find | local | all |  | Finds the routine by name and type, checks its count of parameter words, and calls it. |
| PTMOK | Modules::CallByName::CallFound | local | all |  | Calls the routine found, from the entry point in its record, with room for a function's result. |
| EXFNS | Functions::ExFnInteger | routine | all |  | The `EXFN%.` function: calls a .FUNC and takes the integer it leaves on the stack, low byte on top. |
| PERFEX1 | Modules::StartFunction | routine | all |  | Starts an `EXFN.` or `EXFN%.`: a .FUNC, its name 8 bytes further on in <NAMBUF> than the call around it. |
| EXFN | Functions::ExFn | routine | all |  | The `EXFN.` function: calls a .FUNC and takes the real it leaves on the stack, in the order a real argument is |
| RESTNAM | Modules::FinishFunction | routine | all |  | Finishes a function call: checks the stack, frees the name's place in <NAMBUF>, and backs <TXTPTR> up one character |
| PERFERR | Modules::ToUndefinedFunctionError | routine | all |  | Ends the statement with an undefined-function error. |
| PERFIND | Modules::FindRecord | routine | all |  | Finds the linker record of type <PROCFLG> whose 8-character name matches the one at <Modules::OtherPointer>, |
| PERFI01 | Modules::FindRecord::CheckRecord | local | all |  | Takes the record of type A. |
| PERFI02 | Modules::FindRecord::CheckType | local | all |  | Compares the name when the type is <PROCFLG>. |
| PERFI06 | Modules::FindRecord::CompareName | local | all |  | Compares the name, from its last character. |
| PERFI04 | Modules::FindRecord::Skip | local | all |  | Moves on to the next record. |
| PERFI05 | Modules::FindRecord::Done | local | all |  | Returns. |
| INVERR1 | Modules::ToOutOfMemoryErrorForInvoke | routine | all |  | Ends the statement with an out-of-memory error, for <Statements::Invoke>. |
| INVOKE | Statements::Invoke | routine | all |  | The `INVOKE` statement: replaces the invoked modules with the ones the statement names, or with none. |
| INVOK1 | Statements::Invoke::CheckNames | local | all |  | Loads the modules named, or with no name releases them all. |
| INVOK3 | Statements::Invoke::AddSizes | local | all |  | Adds up the files' sizes, in pages, in <BANKPNT> (pages) and <BANKPNT>+1 (bytes). |
| INVOK4 | Statements::Invoke::AddSize | local | all |  | Opens the next file, adds its size less the first block, and closes it again. |
| INVEXP1 | Statements::Invoke::Reclaim | local | all |  | Takes back all the memory SOS gives, and ends the statement. |
| INVEXP2 | Statements::Invoke::ReleaseAll | local | all |  | Marks nothing invoked, then takes the memory back. |
| TRYSEG | Segments::FindForBasic | routine | all |  | Finds the largest free segment for BASIC's program and data, anywhere in memory, and sets <RAMLOC> and <MEMSIZ> |
| SEGTAB1 | Segments::ReleaseModulesList | data | all |  | RELEASE_SEG's parameter list for the invoked modules' segment. |
| SEGNUMB | Segments::ModulesSegment | data | all |  | The invoked modules' segment number, 0 when nothing is invoked. |
| SEGTAB2 | Segments::FindModulesList | data | all |  | FIND_SEG's parameter list for the invoked modules: within one bank, the modules' ID and <Segments::ModulesPages> |
| PGCNT2 | Segments::ModulesPages | data | all |  | The pages the invoked modules need. |
| BASPTR | Segments::ModulesBase | data | all |  | The modules' segment's base: its bank, then its page. |
| LIMPTR | Segments::ModulesLimit | data | all |  | The modules' segment's limit: its bank, then its page. |
| SEGNUM2 | Segments::FoundModulesSegment | data | all |  | The modules' segment number, from FIND_SEG. |
| SEGTAB3 | Segments::ShrinkModulesList | data | all |  | CHANGE_SEG's parameter list that gives the modules' unused pages back from the segment's base. |
| SEGNUM3 | Segments::ShrinkModulesSegment | data | all |  | The modules' segment number, for <Segments::ShrinkModulesList>. |
| PGECNT | Segments::ShrinkModulesPages | data | all |  | The pages <Segments::ShrinkModulesList> gives back. |
| SEGTAB4 | Segments::ReserveList | data | all |  | REQUEST_SEG's parameter list that reserves bank 0's $2000-$21FF, which BASIC's bank-switched pointers can't |
| SEGNUM4 | Segments::ReservedSegment | data | all |  | The reserved segment's number. |
| SEGTAB5 | Segments::ShrinkBasicList | data | all |  | CHANGE_SEG's parameter list that gives pages back from the top of BASIC's segment, for <Segments::Shrink>. |
| SEGNUM5 | Segments::ShrinkBasicSegment | data | all |  | BASIC's segment number, set by <Segments::FindForBasic>. |
| SEGSIZ5 | Segments::ShrinkBasicPages | data | all |  | The pages <Segments::Shrink> gives back. |
| SEGTAB6 | Segments::GrowBasicList | data | all |  | CHANGE_SEG's parameter list that adds pages to the top of BASIC's segment, for <Segments::Grow>. |
| SEGNUM6 | Segments::GrowBasicSegment | data | all |  | BASIC's segment number, set by <Segments::FindForBasic>. |
| SEGSIZ6 | Segments::GrowBasicPages | data | all |  | The pages <Segments::Grow> asks for; when SOS can't give them, it leaves the most it can here. |
| SEGTAB7 | Segments::FindBasicList | data | all |  | FIND_SEG's parameter list for BASIC's program and data: across banks, BASIC's ID and $FFFF pages, which fails and |
| BASBNK | Segments::BasicBase | data | all |  | BASIC's segment's base: its bank, then its page. |
| LIMBNK | Segments::BasicLimit | data | all |  | BASIC's segment's limit: its bank, then its page. |
| SEGNUM7 | Segments::FoundBasicSegment | data | all |  | BASIC's segment number, from FIND_SEG. |
| PREFTAB | Functions::PrefixList | data | all |  | GET_PREFIX's parameter list, into <CATBUF>+1, for `PREFIX$` and 1.3's prefix handling. |
| DATETAB | Functions::TimeList | data | all |  | GET_TIME's parameter list, into <CATBUF>+2, for `DATE$` and `TIME$`. |
| PREFTB2 | Statements::SetPrefixList | data | all |  | SET_PREFIX's parameter list, from the pathname in <NAMBUF>, for `PREFIX$ =`. |
| PREFTB3 | Statements::CatalogPrefixList | data | all |  | GET_PREFIX's parameter list, into <NAMBUF>, up to 128 bytes, for `CATALOG`. |
| SCRUNCH | Segments::Shrink | routine | all |  | Gives free memory back to SOS: moves the strings and buffers, from <FRETOP> to <HIMEM>, down by A pages, or by all |
| SCRUN0 | Segments::Shrink::Fewer | local | all |  | Takes A pages. |
| SCRUN1 | Segments::Shrink::Move | local | all |  | Moves the strings and buffers down by <INDEX2> pages and gives the pages to SOS. |
| EXPAND | Segments::Grow | routine | all |  | Takes memory back from SOS: grows BASIC's segment by A pages, or by as many as SOS gives when A is 0, and moves the |
| EXPAN0 | Segments::Grow::SetCount | local | all |  | Asks for A pages, Y above 256. |
| EXPAN1 | Segments::Grow::Ask | local | all |  | Grows BASIC's segment by <GrowBasicPages> pages, trying again with SOS's count until it works. |
| EXPAN2 | Segments::Grow::MoveUp | local | all |  | Moves the strings and buffers up by the pages SOS gave, to the new <HIMEM>. |
| SWCHGO | Modules::CallBasic | routine | all |  | Calls one of BASIC's routines for an invokable module, by its number in <PASSAREG>, with BASIC's bank switched in, |
| BCALERR | Modules::CallBasic::ToIllegalQuantityError | entry | all |  | Ends the statement with ILLEGAL QUANTITY. |
| JUMPDO | Modules::CallModule | routine | all |  | Calls the module routine whose address `PERFORM` or `EXFN.` put in <JMPER>, with the modules' bank switched in, |
| ZZZZZ | CodeEnd | location | all |  | The end of BASIC's code. |
| BASICEND | BasicEnd | location | debug |  | The end of BASIC, with the memory up to $A200+$1559 kept for the debugger. |
| BASICEND | BasicEnd | location | all but debug |  | The end of BASIC, which the header's length runs up to. |

### B3Pru1.asm, B3Pru2.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| DELIM | PrintUsing::SpecCharacter | location | all |  | The spec character ReadFormatCharacter found, as the image gives it (upper or lower case); `9` while it reads a count. |
| REP | PrintUsing::RepeatCount | location | all |  | The spec character's count: the repeat count before it, or the run of the same character. |
| DIGB4DPT | PrintUsing::DigitsBeforePoint | location | all |  | The count of digit positions before the decimal point. |
| DIGAFDPT | PrintUsing::DigitsAfterPoint | location | all |  | The count of digit positions after the decimal point. |
| SAVLEN | PrintUsing::TextLength | location | all |  | The length of a literal, or of the string to print. |
| SPECTYP | PrintUsing::SpecType | location | all |  | The spec's type: SPEC_NUMBER, FIELD_STRING, FIELD_LITERAL, or SPEC_END when none was found. |
| DIGCTR | PrintUsing::DigitCounter | location | all |  | While a spec is scanned, the digit positions counted but not yet put in the mask; while a number is edited, the count of digits NextDigit has taken. |
| DIGEXP | PrintUsing::DigitPower | location | all |  | The power of ten of the digit the editor wants. |
| USVSTRL | PrintUsing::StringLength | location | all |  | The string's length, kept while its spec is found. |
| DPTNDX | PrintUsing::PointIndex | location | all |  | The decimal point's index in the mask, NO_INDEX for none. |
| NMASK | PrintUsing::DigitClass | location | all |  | The digit class so far: FIELD_ZERO_FILLED, FIELD_SPACE_FILLED or FIELD_COMMAS, 0 for none. |
| EXPADJ | PrintUsing::ExponentAdjustment | location | all |  | The editor's adjustment to the exponent, for engineering notation. |
| EMASK | PrintUsing::SpecParts | location | all |  | The spec's parts: PARTS_DIGITS, and the codes of the editing characters it has (FIELD_SIGN, with PARTS_PLUS for +, FIELD_DOLLAR, FIELD_EXPONENT and FIELD_POINT). |
| FLTMSK | PrintUsing::FloatingSymbols | location | all |  | The floating symbols: FLOAT_ASTERISKS, FLOAT_DOLLAR, FLOAT_SIGN and FLOAT_DOLLAR_AFTER_SIGN. |
| LITRLCH | PrintUsing::LiteralText | location | all |  | The text X or / prints: a space, or a return and a line feed. |
| SPCB4DIG | PrintUsing::FirstDigitPlace | location | all |  | In engineering notation, the mask index of the first digit. |
| MASKPT | PrintUsing::MaskPointer | alias | all |  | The edit mask, MASK_SIZE bytes of string space from GETSPA, with its X-byte at FRESPCB. |
| VSPEC | PrintUsing::ValueSpecSeen | location | all |  | $FF once a spec has taken a value, so the image may start over. |
| ENDFLG | PrintUsing::EndingSeparator | alias | all |  | How the statement ends: 0 with a new line, a semicolon without one. |
| MSKNDX | PrintUsing::MaskIndex | location | all |  | The index of the mask's last byte, NO_INDEX while it is empty; the editor makes it the mask's length. |
| SPCPTR | PrintUsing::ImagePointer | location | all |  | The image's address, with its X-byte at ImagePointerXByte. |
| SPCPTRH | PrintUsing::ImagePointerHigh | location | all |  | The image's address's high byte. |
| SPCNDX | PrintUsing::ImageIndex | location | all |  | The index of the image's character last read. |
| SPCLEN | PrintUsing::ImageLength | location | all |  | The image's length, 1 to 255. |
| TENZNDX | PrintUsing::UnitsIndex | location | all |  | The mask index of the units digit, NO_INDEX for none. |
| CMACTR | PrintUsing::CommaCounter | location | all |  | The editor's count of digits since a comma. |
| HALF | PrintUsing::NextHalf | location | all |  | Which half of a decimal byte UnpackDecimal takes next: bit 7 set for the high digit. |
| CMAFILL | PrintUsing::FillCharacter | location | all |  | The character for leading zeros, with FILL_COMMAS set to put in commas. |
| SPCPTRB | PrintUsing::ImagePointerXByte | location | all |  | The image's X-byte: its bank. |
| STRTYP | VALUE_TYPE_STRING | constant | all |  | VALTYP for a string, and PTRGET's type for a string variable; one shared set with the other value types (moved to ZpgEqus at integration). |
| ZTYP | PrintUsing::FIELD_ZERO_FILLED | constant | all |  | Z's digit class: leading zeros printed. The lowest class, and the class of every digit after the point. |
| CMATYP | PrintUsing::FIELD_COMMAS | constant | all |  | &'s digit class: leading zeros as spaces, with commas put in. The highest class. |
| DTYP | PrintUsing::FIELD_SPACE_FILLED | constant | all |  | #'s digit class: leading zeros as spaces. |
| MSKLEN | PrintUsing::MASK_SIZE | constant | all |  | The edit mask's size, the widest number field. |
| PRUSING | PrintUsing::Statement | routine | all |  | `PRINT USING`: prints each expression through the next number or string spec of the image, with the literals between. |
| ULITRL | PrintUsing::Statement::TakeLiteral | local | all |  | Takes the image from a string literal, which may not be empty. |
| ULITS | PrintUsing::Statement::LiteralLoop | local | all |  | Takes the literal's next character. |
| ULITX | PrintUsing::Statement::CheckQuote | local | all |  | Ends the literal at its closing quote. |
| ULITE | PrintUsing::Statement::LiteralEnd | local | all |  | Keeps the literal's length; an empty one, or the statement's end after it, is a syntax error. |
| USNERR | PrintUsing::ToSyntaxError | routine | all |  | Ends the statement with a syntax error. |
| UIMERR | PrintUsing::NoImageError | routine | all |  | Ends the statement with an undefined-statement error: the line is not an `IMAGE` statement, or the image is empty. |
| UIMAGE | PrintUsing::TakeImageStatement | routine | all |  | Takes the image from the `IMAGE` statement at the line number in the program text, the rest of its line. |
| UGOTSPT | PrintUsing::StartList | routine | all |  | Starts on the expressions after the image's semicolon; an image that is empty or starts with a comma is a syntax error. |
| USKPNXT | PrintUsing::StartList::SkipSeparator | entry | all |  | Skips a comma or semicolon between the expressions. |
| UNXTEXP | PrintUsing::NextExpression | routine | all |  | Takes the next expression; at the statement's end, or a semicolon, prints the image's last literals. |
| UNXTEXC | PrintUsing::NextExpression::CheckSeparator | local | all |  | Skips a comma, ends at a semicolon, or evaluates the next expression. |
| UTAILS | PrintUsing::Finish | routine | all |  | Ends the statement: prints the literals left before the next number or string spec, then a new line unless a semicolon ended it. A number or string spec found there, with no value for it, is a type mismatch. |
| UEVAL | PrintUsing::Evaluate | routine | all |  | Evaluates the next expression, or `SCALE(n, expression)`, and makes it ready to print: a number as decimal digits in BCDSTR, a string as its pointer and length. |
| UNOSCALE | PrintUsing::Evaluate::NoScale | local | all |  | Evaluates an expression of any type. |
| UGOTNUM | PrintUsing::Evaluate::Prepare | local | all |  | Makes the value ready by its type: a string's pointer to INDEX and its length to StringLength, a long integer's digits by LUNPACK, or a real's from FOUT's text. |
| UDTYPE | PrintUsing::Evaluate::UnpackLong | local | all |  | Unpacks a long integer's digits into BCDSTR, its exponent to FACEXP. |
| UNTYPE | PrintUsing::Evaluate::UnpackReal | local | all |  | Turns a real into decimal digits in BCDSTR, from DIGITS_START, through FOUT's text; its exponent less 1, times 2, plus 1 when negative, goes to FACEXP. |
| STRBCD0 | PrintUsing::Evaluate::CopyDigit | local | all |  | Copies FOUT's digits, skipping the point, a minus and leading zeros, up to the first other character. |
| STRBCD1 | PrintUsing::Evaluate::SkipCharacter | local | all |  | Goes on to FOUT's next character. |
| STRBCD2 | PrintUsing::Evaluate::DigitsDone | local | all |  | Fills the places after the digits with zeros, up to DIGITS_END. |
| STRBCD3 | PrintUsing::Evaluate::ZeroLoop | local | all |  | Writes the next zero. |
| USTKSAV | PrintUsing::Evaluate::RestorePlace | local | all |  | Takes the image's place and the scale back off the stack, then finds the value's spec. |
| UNXTSPC | PrintUsing::FindValueSpec | routine | all |  | Prints the literals up to the next number or string spec; at the image's end starts over from its first spec, unless no spec in it takes a value, which is a type mismatch. |
| UVSPEC | PrintUsing::FindValueSpec::CheckType | local | all |  | Checks the value's type against the spec's, then prints it. |
| UTMERR2 | PrintUsing::FindValueSpec::FreeMaskThenTypeMismatch | local | all |  | Frees the mask, then ends the statement with a type mismatch. |
| UTMERR | PrintUsing::FindValueSpec::ToTypeMismatchError | entry | all |  | Ends the statement with a type mismatch. |
| UDOLITS | PrintUsing::PrintLiterals | routine | all |  | Clears the mask, scans the next spec, and prints it when it is a literal, until a number or string spec or the image's end. |
| UBLKMSK | PrintUsing::PrintLiterals::ClearMask | local | all |  | Clears the mask's next byte, from the last. |
| UDOXIT | PrintUsing::PrintLiterals::Done | local | all |  | Returns. |
| ULITOUT | PrintUsing::PrintLiterals::PrintLiteral | local | all |  | Prints a literal, unless the spec was a string's. |
| UREPEAT | PrintUsing::PrintLiterals::Repeat | local | all |  | Prints the literal at LOWTR, TextLength bytes, RepeatCount times, then goes on to the next spec. |
| UOUTLP | PrintUsing::PrintLiterals::OutputLoop | local | all |  | Prints the literal's next byte. |
| USTRVAR | PrintUsing::FormatString | routine | all |  | Prints a string through its spec, cut to the field's width or padded with spaces: A puts the spaces after it, C half before, and R all before; then takes the next expression. |
| USFITS | PrintUsing::FormatString::Fits | local | all |  | Prints the spaces before a string shorter than its field. |
| UEATME | PrintUsing::FormatString::PadBefore | local | all |  | Prints A spaces, counting them off the width. |
| ULSPCS | PrintUsing::FormatString::PadBeforeLoop | local | all |  | Prints the next space. |
| UEXACT | PrintUsing::FormatString::CopyText | local | all |  | Prints the string's TextLength characters, then spaces to the field's end. |
| UEXACT2 | PrintUsing::FormatString::TextLoop | local | all |  | Prints the string's next character. |
| UNULL | PrintUsing::FormatString::PadAfter | local | all |  | Prints spaces to the field's end. |
| UFILL3 | PrintUsing::FormatString::PadAfterLoop | local | all |  | Prints the next space, or frees the string at the field's end. |
| UNUMVAR | PrintUsing::PrintNumber | routine | all |  | Prints a number through its mask, then takes the next expression. |
| UFREMSK | PrintUsing::FreeMaskThenNext | routine | all |  | Frees the mask and takes the next expression. |
| UFRESTR | PrintUsing::FreeStringThenNext | routine | all |  | Frees the string, if it was a temporary one, and the mask, then takes the next expression. |
| UFRESPC | PrintUsing::FreeMask | routine | all |  | Frees the mask's MASK_SIZE bytes of string space. |
| UREGET | PrintUsing::SkipSpace | routine | all |  | Drops ReadNonSpace's saved status and reads on past a space. |
| UGETCHR | PrintUsing::ReadNonSpace | routine | all |  | Reads the image's next character other than a space, and classifies it as ClassifyCharacter does. |
| UGETCH | PrintUsing::ReadNext | routine | all |  | Moves ImageIndex to the image's next character, and classifies it as ClassifyCharacter does. |
| IGOTCH | PrintUsing::ClassifyCharacter | routine | all |  | Classifies the image's character at ImageIndex. |
| UGETCKL | PrintUsing::ClassifyCharacter::InImage | local | all |  | Reads the character, or the end past the image's length. |
| UGETCKD | PrintUsing::ClassifyCharacter::CheckDigit | local | all |  | Sets carry clear for a digit. |
| UGETNE | PrintUsing::ClassifyCharacter::SetZero | local | all |  | Sets zero for 0, the end. |
| UGETEND | PrintUsing::ClassifyCharacter::Done | local | all |  | Returns with overflow clear. |
| UGETVS | PrintUsing::ClassifyCharacter::Letter | local | all |  | Returns an upper-case letter with overflow set and carry set. |
| UATOMSK | PrintUsing::AddToMask | routine | all |  | Adds A to the mask. |
| USYERR | PrintUsing::AddToMask::ToSyntaxError | entry | all |  | Ends the statement with a syntax error. |
| UDOMASK | PrintUsing::PutDigitsInMask | routine | all |  | Puts the digit positions counted in DigitCounter into the mask as zeros, and sets DigitsBeforePoint or DigitsAfterPoint to their count. |
| UNOTZ | PrintUsing::PutDigitsInMask::BeforePoint | local | all |  | Counts the digits before the point. |
| UAFDPT | PrintUsing::PutDigitsInMask::CountDigits | local | all |  | Sets the count, and checks the room for commas. |
| UANYSIZ | PrintUsing::PutDigitsInMask::AddZeros | local | all |  | Puts the digits into the mask. |
| UDOMSKL | PrintUsing::PutDigitsInMask::ZeroLoop | local | all |  | Puts the next digit into the mask. |
| UDONT | PrintUsing::PutDigitsInMask::Done | local | all |  | Returns. |
| IMSYNCK | PrintUsing::ScanSpec | routine | all |  | Scans the image's next spec, checking its syntax, and builds a number spec's edit mask at MaskPointer, or points LOWTR and TextLength at a literal's text. |
| UQSCAN | PrintUsing::ScanSpec::QuoteLoop | local | all |  | Counts the literal's characters up to its closing quote; with none, it is a syntax error. |
| UCHEKCM | PrintUsing::CheckSpecEnd | routine | all |  | Returns when the spec ends at a comma or the image's end, or ends the statement with a syntax error. |
| USNERRL | PrintUsing::CheckSpecEnd::ToSyntaxError | entry | all |  | Ends the statement with a syntax error. |
| UCRLIT | PrintUsing::NewLineLiteral | routine | all |  | Makes / a literal of a return and a line feed, then checks the spec's end. |
| USPLIT | PrintUsing::NewLineLiteral::SpaceLiteral | entry | all |  | Makes X a literal of a space. |
| UNUMTYP | PrintUsing::NumberSpec | routine | all |  | Starts a number spec: takes **, which must be exactly two, for asterisk fill. |
| UDOLAR | PrintUsing::TakeDollar | routine | all |  | Takes a $, or returns when A is not one: $$ floats; one $ floats after ** or a floating sign, and otherwise goes into the mask. A second $ in the spec, or $$ after another floating symbol, is a syntax error. |
| UCK1DL | PrintUsing::TakeDollar::Single | local | all |  | Takes a single $. |
| UDLFLT | PrintUsing::TakeDollar::Floating | local | all |  | Marks a floating $, after a floating sign or not, and reserves its place in the mask. |
| USTDLR | PrintUsing::TakeDollar::Fixed | local | all |  | Puts a fixed $ into the mask. |
| UXDLR | PrintUsing::TakeDollar::Next | local | all |  | Reads the spec's next character, which must be there. |
| UDOLLR | PrintUsing::TakeLeadingSign | routine | all |  | Takes a $ and then a leading sign: ++ or -- floats; one sign floats after another floating symbol, and otherwise goes into the mask. Then a $ after the sign. |
| UCK1SIN | PrintUsing::TakeLeadingSign::Single | local | all |  | Takes a single sign. |
| UFLTSIN | PrintUsing::TakeLeadingSign::Floating | local | all |  | Marks a floating sign and reserves its place in the mask. |
| UNSERR | PrintUsing::TakeLeadingSign::ToSyntaxError | entry | all |  | Ends the statement with a syntax error. |
| USETSIN | PrintUsing::TakeLeadingSign::Fixed | local | all |  | Puts a fixed leading sign into the mask. |
| UXSIN | PrintUsing::TakeLeadingSign::Next | local | all |  | Reads the spec's next character, which must be there. |
| UTRYDL2 | PrintUsing::TakeLeadingSign::DollarAfterSign | local | all |  | Takes a $ after the sign. |
| UTRYDIG | PrintUsing::TakeDigits | routine | all |  | Takes a run of digit positions, counting them in DigitCounter and noting the field's digit class and fill. |
| UB4DPT | PrintUsing::TakeDigits::BeforePoint | local | all |  | Sets the fill for leading zeros from the class, or keeps **'s asterisk, with the comma bit for &. |
| USETCMA | PrintUsing::TakeDigits::SetFill | local | all |  | Adds the comma bit and sets the fill. |
| UXNMASK | PrintUsing::TakeDigits::SetClass | local | all |  | Sets the class. |
| UXMORE | PrintUsing::TakeDigits::More | entry | all |  | Reads the spec's next character, or finishes the spec at its end. |
| UBLDMK | PrintUsing::TakePoint | routine | all |  | Puts the digits counted into the mask, then takes a decimal point, which must be single and the spec's only one. |
| USGNCK | PrintUsing::TakeTrailingSign | routine | all |  | Takes a trailing sign, which must be single and the spec's only one. |
| UCKEXP | PrintUsing::TakeExponent | routine | all |  | Takes the exponent, EEE or EEEE, which must end the spec; anything else is a syntax error. |
| UEEE | PrintUsing::TakeExponent::Mark | local | all |  | Marks the exponent and puts its E's into the mask. |
| UEEELP | PrintUsing::TakeExponent::MaskLoop | local | all |  | Puts the next E into the mask. |
| UENOFLT | PrintUsing::TakeExponent::CheckFloating | local | all |  | Checks the floating symbols the count allows. |
| UENDERR | PrintUsing::RequireSpecCharacter | routine | all |  | Reads the spec's next character, which must be there. |
| UCKDEND | PrintUsing::NextSpecCharacter | routine | all |  | Reads the spec's next character, or at its end finishes the spec with FinishNumberSpec. |
| UNXTGET | PrintUsing::NextSpecCharacter::Read | entry | all |  | Reads the spec's next character. |
| UDIGEND | PrintUsing::FinishNumberSpec | routine | all |  | Finishes a number spec: puts the last digits into the mask, and returns to ScanSpec's caller with SpecType SPEC_NUMBER, dropping the return address of the routine that called this one. |
| UCKXIT | PrintUsing::FinishNumberSpec::Accept | local | all |  | Marks the spec a number's and returns past the caller. |
| USTERR | PrintUsing::FreeMaskThenSyntaxError | routine | all |  | Frees the mask, then ends the statement with a syntax error. |
| UGETDL | PrintUsing::ReadFormatCharacter | routine | all |  | Takes the next format character from the image, with its repeat count, and returns its type from FormatTypes. |
| UCOMA | PrintUsing::ReadFormatCharacter::SkipCommas | local | all |  | Skips commas, or at the image's end returns to the caller's caller. |
| UGOT1 | PrintUsing::ReadFormatCharacter::Take | local | all |  | Takes a digit of the count, or goes on to a format character. |
| UG1STD | PrintUsing::ReadFormatCharacter::AddDigit | local | all |  | Adds a digit to the count: RepeatCount times 10, plus the digit. |
| UIQERR | PrintUsing::ReadFormatCharacter::FreeMaskThenIllegalQuantity | local | all |  | Frees the mask and ends the statement with an illegal quantity error. |
| UGNXTC | PrintUsing::ReadFormatCharacter::NextCharacter | local | all |  | Takes the next character of the image. |
| UGVAL | PrintUsing::ReadFormatCharacter::Back | local | all |  | Backs up so the character that ended the field is read again by the next call. |
| UGEND | PrintUsing::ReadFormatCharacter::LookUp | local | all |  | Looks the format character up in FormatCharacters, in upper case, and returns its type. |
| UVALOOP | PrintUsing::ReadFormatCharacter::SearchLoop | local | all |  | Compares the next entry, from the last. |
| UGERRX | PrintUsing::ReadFormatCharacter::FreeMaskThenSyntaxError | local | all |  | Frees the mask and ends the statement with a syntax error. |
| UGETND | PrintUsing::ReadFormatCharacter::Found | local | all |  | Returns the type of the format character found at Y. |
| UDLCHR | PrintUsing::ReadFormatCharacter::FormatCharacter | local | all |  | Takes a format character: the first, the one after a count, or another of a run. |
| U1STDL | PrintUsing::ReadFormatCharacter::First | local | all |  | Takes the first format character, with a count of 1. |
| USETDL | PrintUsing::ReadFormatCharacter::Record | local | all |  | Records the format character; a quote ends the reading, as a literal follows it. |
| UDLCK | PrintUsing::ReadFormatCharacter::Run | local | all |  | Counts another of the same format character, or ends the field at a different one. |
| DLMTBL | PrintUsing::FormatCharacters | table | all |  | The format characters, in upper case; FormatTypes gives each one's type. |
| STYPTBL | PrintUsing::FormatTypes | table | all |  | Each format character's type, in FormatCharacters' order: the FIELD_ codes, or for a digit its class. |
| DLMCNT | PrintUsing::FORMAT_CHARACTER_COUNT | constant | all |  | The number of format characters. |
| FILLTABL | PrintUsing::FillCharacters | table | all |  | The fill character for the places before the point, by digit class less FIELD_ZERO_FILLED: `0` for Z, a space for #, a space for the class between, which no character has, and a space for &. |
| CMATBL | PrintUsing::CommaFlags | table | all |  | The comma flag, by digit class less FIELD_ZERO_FILLED: FILL_COMMAS for &, which puts commas in. |
| UUNPACK | PrintUsing::UnpackDecimal | routine | all |  | Unpacks the decimal mantissa in FACT into BCDSTR, one digit a byte from DIGITS_START: DIGIT_COUNT digits, then a 0. |
| UHLOOP | PrintUsing::UnpackDecimal::Loop | local | all |  | Takes the next digit. |
| UPUSELOW | PrintUsing::UnpackDecimal::LowDigit | local | all |  | Takes the low digit; the next byte's high digit comes next. |
| UPUSEA | PrintUsing::UnpackDecimal::Digit | local | all |  | Stores the digit, or drops a leading zero. |
| UGTABYT | PrintUsing::UnpackDecimal::Store | local | all |  | Stores the digit. |
| UNUMEDIT | PrintUsing::FormatNumber | routine | all |  | Writes a number into its field of the mask, as the image asks, and prints it. |
| UROKNOW | PrintUsing::FormatNumber::InRange | local | all |  | Fills in a fixed sign, then edits the field: with an exponent at FormatScientific, otherwise here. |
| UNOSBC1 | PrintUsing::FormatNumber::Quarter | local | all |  | Takes a quarter of the count: the places the commas take. |
| UNOCMAS | PrintUsing::FormatNumber::RoundFixed | local | all |  | Rounds the number at the last decimal place shown and checks the digits before the point fit. |
| UTOOBIG | PrintUsing::FormatNumber::TooBig | local | all |  | Fills the field with `!`, for a number that doesn't fit, and prints it. |
| UEXLOOP | PrintUsing::FormatNumber::TooBigLoop | local | all |  | Fills the next place, from the last. |
| UEXDONE | PrintUsing::FormatNumber::TooBigDone | local | all |  | Prints the field. |
| UDOLEFT | PrintUsing::FormatNumber::WriteWhole | local | all |  | Writes the digits before the point, right to left from the units place, with a comma every three digits when asked; the units place shows 0 for a number below 1. |
| ULEFTLP | PrintUsing::FormatNumber::WholeLoop | local | all |  | Writes the next place, from the units. |
| UDOADIG | PrintUsing::FormatNumber::PlaceDigit | local | all |  | Puts in a comma first, every three digits. |
| UINCMA | PrintUsing::FormatNumber::CountComma | local | all |  | Counts the digit toward the next comma. |
| USTALFT | PrintUsing::FormatNumber::StoreWhole | local | all |  | Stores the digit. |
| UDOISGN | PrintUsing::FormatNumber::MinusSign | local | all |  | Puts a minus sign before a negative number whose image has no sign, in a spare digit place; with no place for it the number doesn't fit. |
| UDOFLTS | PrintUsing::FormatNumber::FloatingSigns | local | all |  | Writes the floating `$` and sign before the digits, right to left in the order the image gave them, from the bits of FloatingSymbols: FLOAT_DOLLAR_AFTER_SIGN, FLOAT_SIGN, then FLOAT_DOLLAR. |
| UNODL1 | PrintUsing::FormatNumber::CheckSign | local | all |  | Writes a floating sign: `-` for a negative number, `+` for a positive one when the image asks for one. |
| USTORMI | PrintUsing::FormatNumber::StoreSign | local | all |  | Stores the sign. |
| USKPSI | PrintUsing::FormatNumber::SignDone | local | all |  | Goes on to a floating $ before the sign. |
| UNOSIGN | PrintUsing::FormatNumber::CheckDollar | local | all |  | Writes a floating $ before the sign, or with none. |
| UDOFILL | PrintUsing::FormatNumber::FillLeft | local | all |  | Fills the digit places left before the number with the fill character: a space, `0` or `*`. |
| UFILLP | PrintUsing::FormatNumber::FillLoop | local | all |  | Fills the next place, until one that is not a digit place. |
| URIGHTS | PrintUsing::FormatNumber::WriteFraction | entry | all |  | Writes the digits after the point: the number's own places, or with an exponent its next digits. |
| URITLOP | PrintUsing::FormatNumber::FractionLoop | local | all |  | Writes the next place. |
| UEXPTYP | PrintUsing::FormatNumber::NextOfDigits | local | all |  | Takes the next of the number's digits, for a field with an exponent. |
| UDIGRIT | PrintUsing::FormatNumber::StoreFraction | local | all |  | Stores the digit. |
| UDOEXP | PrintUsing::FormatNumber::WriteExponent | local | all |  | Writes the exponent at the image's first E: an upper-case E, the exponent's sign, and two digits, or one when the image has only three Es; an exponent that needs two digits there doesn't fit. |
| UDOEXP1 | PrintUsing::FormatNumber::FindE | local | all |  | Looks for the first E. |
| USBCLP | PrintUsing::FormatNumber::TensLoop | local | all |  | Counts the tens. |
| UGOTHI | PrintUsing::FormatNumber::Units | local | all |  | Takes the units, and checks the room for two digits. |
| UDO1STD | PrintUsing::FormatNumber::TwoDigits | local | all |  | Writes the tens digit. |
| UDO2NDD | PrintUsing::FormatNumber::UnitsDigit | local | all |  | Writes the units digit. |
| USENDIT | PrintUsing::FormatNumber::PrintField | local | all |  | Prints the field: the mask, MaskIndex characters, as a string. |
| MINSGN | PrintUsing::EXPONENT_MIN | constant | all |  | The smallest exponent a field takes, -99. |
| MAXSGN | PrintUsing::EXPONENT_MAX | constant | all |  | The largest exponent a field takes, 99. |
| UEEEDIT | PrintUsing::FormatScientific | routine | all |  | Writes a number into a field with an exponent: `.DDDE+EE` with no places before the point, `D.DDDE+EE` with one, or engineering notation with three. |
| UDOSCI1 | PrintUsing::FormatScientific::WholeDigits | local | all |  | Writes DigitsBeforePoint digits, then those after the point. |
| UDOSCI0 | PrintUsing::FormatScientific::NoWholePlaces | local | all |  | With no places before the point, the exponent is one higher. |
| UDOSCI2 | PrintUsing::FormatScientific::ToWriteFraction | local | all |  | Writes the digits after the point. |
| UENGNOT | PrintUsing::FormatScientific::Engineering | local | all |  | Engineering notation: lowers the exponent to a multiple of three, which leaves one to three digits before the point, and puts the floating sign and the fill character in the places left before them. |
| UMOD3LP | PrintUsing::FormatScientific::ModLoop | local | all |  | Adds 3 to a negative exponent until it is not. |
| UCHKMD3 | PrintUsing::FormatScientific::CheckMod | local | all |  | Takes 3 off until the remainder is below 3. |
| UGOTMOD | PrintUsing::FormatScientific::GotMod | local | all |  | Lowers the exponent by the remainder, which is the count of digits before the point less one. |
| USTORM | PrintUsing::FormatScientific::StoreSign | local | all |  | Stores the floating sign. |
| UDOEFIL | PrintUsing::FormatScientific::Fill | local | all |  | Fills the place before the digits, or the sign. |
| UDOEFLL | PrintUsing::FormatScientific::FillLoop | local | all |  | Fills the place, then finds it filled. |
| UDODIGS | PrintUsing::FormatScientific::Digits | local | all |  | Writes the digits from the place in FirstDigitPlace. |
| UGET10X | PrintUsing::DigitAtPower | routine | all |  | Returns the number's digit for a power of ten, in ASCII. |
| UGETITA | PrintUsing::DigitAtPower::AtIndex | entry | all |  | Takes the digit's index from the first in A. |
| UNODIGT | PrintUsing::DigitAtPower::Done | local | all |  | Returns. |
| UUSEIT | PrintUsing::DigitAtPower::Read | local | all |  | Reads the digit. |
| UGETNSD | PrintUsing::NextDigit | routine | all |  | Returns the number's next digit, counting from the first with DigitCounter, in ASCII. |
| USGNSCN | PrintUsing::FillFixedSign | routine | all |  | Fills in the image's fixed sign by the number's: a `+` becomes `+` or `-`, a `-` becomes a space or `-`. |
| USIGNLP | PrintUsing::FillFixedSign::Loop | local | all |  | Looks at the mask's next place. |
| UDOMSIN | PrintUsing::FillFixedSign::Minus | local | all |  | Makes a `-` a space for a positive number. |
| USTASIN | PrintUsing::FillFixedSign::Store | local | all |  | Stores the sign, `-` for a negative number. |
| USGNRTS | PrintUsing::FillFixedSign::Done | local | all |  | Returns. |
| UEXPLS1 | PrintUsing::RaiseExponent | routine | all |  | Adds one to the exponent in FACEXP when carry is set, then puts its size in TENEXP. |
| UABSEXP | PrintUsing::RaiseExponent::Magnitude | entry | all |  | Puts the exponent's size in TENEXP. |
| USTATEN | PrintUsing::RaiseExponent::Store | local | all |  | Stores the size. |
| UCVTX | PrintUsing::PowerToIndex | routine | all |  | Turns a power of ten into its digit's index in BCDSTR, counting from DIGITS_START. |
| UROUNDI | PrintUsing::RoundAtPower | routine | all |  | Rounds the number at a power of ten: if that place's digit is 5 or more, it becomes 0 and one is carried into the places before it. |
| UROUNDA | PrintUsing::RoundAtPower::AtIndex | entry | all |  | Rounds at the place with index X. |
| UROUNDL | PrintUsing::RoundAtPower::CarryLoop | local | all |  | Carries into the place before. |
| UROUNDB | PrintUsing::RoundAtPower::AddCarry | local | all |  | Adds the carry to the place, in decimal. |
| UROUNDX | PrintUsing::RoundAtPower::NoCarryOut | local | all |  | Returns with carry clear: the exponent stands. |
| UROUNDO | PrintUsing::RoundAtPower::CarryOut | local | all |  | Makes the number 1 after a carry out of its first digit, the other places now 0, and returns with carry set. |

### DiskStuf1.asm, DiskStuf2.asm, DisCmds.asm, FileStuf.asm, Catalog.asm

| Old | New | Kind | Builds | AppleSoft name | Reason |
| --- | --- | --- | --- | --- | --- |
| INALLWD | READ_LINE_LIMIT | constant | all |  | The most characters a line read asks SOS for; a line this long is cancelled. |
| INPUTLIN | ReadLine | routine | all |  | Prints a prompt, then reads a line into <BUF> from the console or, while `EXEC` runs, from the `EXEC` file. |
| ILM | ReadLine::FromConsole | entry | all |  | Reads the line from the console, or from the `EXEC` file while one is open. |
| IL4 | ReadLine::CheckLength | entry | all |  | Cancels a line that filled the whole read, or finishes it. |
| CLR2EOL | ReadLine::ClearRestOfLine | local | all |  | Clears the rest of the screen line and starts the next: the control code, a carriage return and a line feed. |
| PRNACHAR | WriteConsoleCharacter | routine | all |  | Writes one character to the console with SOS's `WRITE`, ending the statement if the write fails. |
| DSEXEC | Files::ReadExecLine | routine | all |  | Reads a line from the `EXEC` file through <SLINTB>, putting the console's reference number back afterwards. |
| EXCCLS | Files::CloseExecFile | routine | all |  | Closes the `EXEC` file and stops `EXEC`, then ends the statement with the error that stopped it unless it was the |
| FUK1 | Files::CloseExecFile::ToReportSosError | entry | all |  | Ends the statement with the SOS error in A. |
| TYP | Functions::Typ | routine | all |  | The `TYP` function: what the next item read from a file will be. |
| TYP1 | Functions::Typ::NextItem | local | all |  | Looks at the next item's descriptor, reading on past the end of a record that held items. |
| TYP2 | Functions::Typ::Classify | local | all |  | Gives the descriptor's `TYP` number. |
| RTNVAL | Functions::ReturnByteValue | routine | all |  | Returns A as `TYP`'s or another function's value. |
| REC | Functions::Rec | routine | all |  | The `REC` function: the number of the record a file is at. |
| GTREC | Functions::Rec::ReturnRecord | local | all |  | Returns the record number in the file's control block as `REC`'s value. |
| NOTOPN | Files::NotOpenError | routine | all |  | Ends the statement with SOS's file-not-open error. |
| GETRN | Files::RecordFromMark | routine | all |  | Sets a file's record number from its mark: the mark (from `GET_MARK`) divided by <DVSR>. |
| GTRN0 | Files::RecordFromMark::CopyMark | local | all |  | Copies the mark's bytes. |
| GETRN1 | Files::RecordFromEnd | routine | all |  | Sets a file's record number from its end of file, as <RecordFromMark> does from the mark: the end of file in |
| GTRN2 | Files::RecordFromEnd::CopyEnd | local | all |  | Copies the end of file's bytes. |
| GTRN3 | Files::RecordFromEnd::DivideByLength | entry | all |  | Divides the position by the record length into the record number. |
| DCLOSE | Statements::Close | routine | all |  | The `CLOSE` statement: closes the file given, or with no file number every file. |
| CLSDONE | Statements::Close::Finish | entry | all |  | Ends the statement with the write error <Files::CloseFile> kept in <SUBFLG>, if there was one, and clears it. |
| CLSALL | Files::CloseAll | routine | all |  | Closes every open file, 10 down to 1, then ends the statement with a write error if closing one gave one. |
| CLSA1 | Files::CloseAll::NextFile | local | all |  | Closes the file whose number less one is in A, if it is open. |
| CLSAL2 | Files::CloseAll::Skip | local | all |  | Steps to the file before. |
| CLOSEM | Files::CloseFile | routine | all |  | Closes one file: writes its record if it was changed, frees its buffer, clears its control block and closes it. |
| DNTCLS | Files::CloseFile::WriteBack | local | all |  | Writes the record back, keeping a write error, then frees the buffer. |
| CLOSEM2 | Files::CloseControlBlock | routine | all |  | Closes a file in SOS and clears its control block. |
| CLS3 | Files::CloseControlBlock::Clear | local | all |  | Clears the control block's next byte. |
| CLSEND | Files::CloseSosFile | routine | all |  | Closes the file whose reference number is in <RWRFNM>, ending the statement if `CLOSE` fails. |
| GTFLNO | Files::TakeFileNumber | routine | all |  | Takes a file number, `#` and an expression, from the statement and finds its control block. |
| GTFLNO0 | Files::TakeFileNumber::FromNumber | entry | all |  | Takes the file number in X. |
| GTFLNO1 | Files::TakeFileNumber::FromIndex | entry | all |  | Takes the file number less one in X. |
| FCBMUL | Files::TakeFileNumber::Multiply | local | all |  | Adds the number in once for each byte of a control block. |
| BADBOY1 | Files::ToIllegalQuantityError | routine | all |  | Ends the statement with an illegal quantity error. |
| PDLHNDL | Functions::Pdl | routine | all |  | The `PDL` function: reads an axis of a joystick, 0-255, with SOS's `JOYSTICK` call. |
| READJOY | Functions::ReadJoystick | routine | all |  | Makes the `JOYSTICK` call with the mode in <JMODE> and returns one byte of its result as the function's value. |
| BUTTON | Functions::Button | routine | all |  | The `BUTTON` function: reads a joystick's switch, 255 when it is pressed and 0 when not. |
| GETNAME | Files::TakeName | routine | all |  | Takes a file name from the statement into <NAMBUF>, with its length first as SOS wants it, and points <PTHPTR> at |
| GETNAM2 | Files::TakeName::AtIndex | entry | all |  | Takes the name's place in X. |
| GTNM | Files::TakeName::NextCharacter | local | all |  | Copies the name's next character as typed. |
| GOTNAM | Files::TakeName::EndOfName | local | all |  | Steps the text pointer over a name taken as typed. |
| GOTN2 | Files::SetNameLength | routine | all |  | Puts the name's length before it in <NAMBUF>, at the place in <FORPNT>, and points <PTHPTR> at it. |
| GOTN22 | Files::SetNameLength::AtY | entry | all |  | Takes the place in Y. |
| DFRD | Files::TakeNameExpression | routine | all |  | Takes the name as a string expression and copies it into <NAMBUF>, freeing the string if it was a temporary one. |
| DFRD2 | Files::TakeNameExpression::CopyCharacter | local | all |  | Copies the string's next character. |
| DFRD3 | Files::TakeNameExpression::Copied | local | all |  | Frees the string. |
| RTSQ7 | Files::TakeNameExpression::Return | entry | all |  | Returns; <TakeFileAndRecord> branches here. |
| FILNUM | Files::TakeFileAndRecord | routine | all |  | Takes `#n` and, after a comma, a record number from a file statement; with a record number, writes out the record |
| RPOSN | Files::LoadRecord | routine | all |  | Moves a file to the record in its control block and, for a data file whose open is complete, reads the record into |
| READ25 | Files::LoadRecord::EndOfFile | local | all |  | Leaves an empty record at the end of the file. |
| RDGE | Files::LoadRecord::Done | local | all |  | Returns. |
| DUMSHIT | Files::ToNotOpenError | routine | all |  | Ends the statement with a file-not-open error, for <PrepareTextFile>'s branch. |
| PREBIN | Files::PrepareDataFile | routine | all |  | Checks, before a binary read or write, that the file is open and holds binary data, as <PrepareTextFile> does |
| PRETXT | Files::PrepareTextFile | routine | all |  | Checks, before a text read or write, that the file is open and holds text. |
| GTTYP1 | Files::PrepareTextFile::RecordType | local | all |  | Records the type asked for in the file's control block, after the reference number is restored. |
| FINOPN | Files::PrepareTextFile::FinishOpen | local | all |  | Finishes the open: moves the file to its record, which reads it. |
| CKTYP | Files::PrepareTextFile::CheckType | local | all |  | Ends the statement with a type mismatch unless the file's type is the one in <TYPSAV>. |
| ERTYP | Files::ReportTypeMismatch | routine | all |  | Ends the statement with a type mismatch error. |
| DOPEN | Statements::Open | routine | all |  | The `OPEN` statement: `OPEN #n [AS INPUT \| AS OUTPUT \| AS EXTENSION], name [, record length]`. |
| DOP2 | Statements::Open::TakeMode | local | all |  | Looks for `AS INPUT`, `AS OUTPUT` or `AS EXTENSION`. |
| AS1 | Statements::Open::TryOutput | local | all |  | Takes `AS OUTPUT` or `AS EXTENSION`, after `AS INPUT` was looked for. |
| AS2 | Statements::Open::TryExtension | local | all |  | Takes `AS EXTENSION`. |
| AS3 | Statements::Open::CheckMode | local | all |  | Ends the statement with a syntax error unless one of the modes followed `AS`, then steps over it. |
| NOTAS | Statements::Open::SetMode | local | all |  | Takes the mode into the control block and `OPEN`'s access (<Files::OPEN_READ> for `INPUT`, otherwise any or to |
| GVERR | Statements::Open::ToSyntaxError | local | all |  | Ends the statement with a syntax error. |
| GVTT | Statements::Open::WrongType | local | all |  | Closes a file of the wrong type and ends the statement with a type mismatch. |
| NOTAS2 | Statements::Open::OpenFile | local | all |  | Opens the file, creating it when it may, and fills in its control block. |
| OPG2 | Statements::Open::AddType | local | all |  | Adds the file's type to the control block and takes its record length, the auxiliary type, |
| RNDYSLAB | Statements::Open::CheckText | local | all |  | Sends a text file to <TextFile>; any other file gets a buffer. |
| OPLP | Statements::Open::GetBuffer | local | all |  | Gets a buffer for a record from SOS with `FIND_SEG`, anywhere in memory, and if SOS has none frees that many pages |
| OPGD1 | Statements::Open::FindSegment | local | all |  | Makes the `FIND_SEG` call for Y pages. |
| GTDIR | Statements::Open::ToDirectory | local | all |  | Opens a directory as a catalog. |
| OPSHIT | Statements::Open::ToReportSosError | local | all |  | Ends the statement with the SOS error in A. |
| GTTXT | Statements::Open::TextFile | local | all |  | Sets new-line mode on a text file and marks it as having no buffer. |
| OPGOOD | Statements::Open::Opened | local | all |  | Records the buffer and its segment in the control block, then, `AS EXTENSION`, moves the file to its end. |
| OPGOT | Statements::Open::ReadLast | local | all |  | Reads the last record and sets the buffer's offset to the place in <RMNDR>. |
| NOEXT | Statements::Open::CopyName | local | all |  | Copies the file's name, with its length first, from <NAMBUF> to the start of its buffer, unless it is a text file. |
| NOX2 | Statements::Open::NextByte | local | all |  | Copies the name's next byte. |
| XYZZY | Statements::Open::Done | local | all |  | Returns. |
| TXTEXT | Statements::Open::TextAtEnd | local | all |  | Sets a text file's mark to its end (`SET_MARK` from the end of file, by 0), then goes on as <CopyName>. |
| TE1 | Statements::Open::ClearPosition | local | all |  | Clears the base and the four-byte displacement, from the top. |
| OPNPRTB | Files::OpenNamed | routine | all |  | Opens the file named in the statement, for `INVOKE`, `LOAD`, `SAVE`, `CATALOG` and `OPEN`, creating it when it |
| OPNP2 | Files::OpenNamed::WithName | entry | all |  | Takes the name already in <PTHPTR>, the access in <INREQ> and the type in <TYPSAV>. |
| OPPP2 | Files::OpenNamed::NotFound | local | all |  | Creates the file when `GET_FILE_INFO` didn't find it and the access isn't read only; any other error ends the |
| OPNP3 | Files::OpenNamed::Open | local | all |  | Makes the `OPEN` call with the access in <INREQ>. |
| OPNRTS | Files::OpenNamed::Opened | local | all |  | Copies the new reference number into <RWRFNM> for the calls that follow. |
| CMPLAIN | Files::OpenNamed::ToReportSosError | local | all |  | Ends the statement with the SOS error in A. |
| GETNDX | Files::PointAtItem | routine | all |  | Points <NDXPTR> at the file buffer's current byte: the buffer's address plus the offset in the record. |
| TSTFTX | Files::EndMarkFits | routine | all |  | Tests whether one more byte, the end-of-record mark, fits in the record. |
| TSTFIT | Files::ItemFits | routine | all |  | Tests whether an item of A bytes fits in the rest of the record. |
| UPOFS | Files::AdvanceOffset | routine | all |  | Moves the file buffer's offset past the item just read or written, by <LENSAV> bytes. |
| MUL | Files::Multiply | routine | all |  | Multiplies <MLTPLR> by <MLTPLR2>, 16 bits by 16, into the 32-bit product at <RSLT>. |
| MUL2 | Files::Multiply::NextBit | local | all |  | Adds the multiplicand into the high word when the multiplier's low bit is 1. |
| MUL3 | Files::Multiply::AddByte | local | all |  | Adds one byte of the multiplicand. |
| MUL4 | Files::Multiply::Shift | local | all |  | Shifts the 32-bit product right. |
| MUL5 | Files::Multiply::ShiftByte | local | all |  | Shifts one byte of the product. |
| DIV | Files::Divide | routine | all |  | Divides the 32-bit <DVDND> by <DVSR>, giving a 16-bit quotient in <QUOTNT> and the remainder in <RMNDR>. |
| DIV2 | Files::Divide::NextBit | local | all |  | Shifts the dividend left and takes the divisor off when it fits. |
| DIV3 | Files::Divide::Count | local | all |  | Counts the step. |
| VREAL | VALUE_TYPE_REAL | constant | all |  | <VALTYP> of a real number. |
| VLNT | VALUE_TYPE_LONG_INTEGER | constant | all |  | <VALTYP> of a long integer. |
| VSTR | VALUE_TYPE_STRING | constant | all |  | <VALTYP> of a string. |
| VINT | Files::VALUE_TYPE_INTEGER | constant | all |  | An integer, in <DescriptorValueTypes>; bit 3 tells `READ#` to set <INTFLG>. |
| DTABLE | Files::Descriptors | table | all |  | The descriptor byte of each kind of item in a data file: integer, real, long integer, string, 255-character string |
| VTABLE | Files::DescriptorValueTypes | table | all |  | The <VALTYP> of each descriptor in <Descriptors>, at the same index; both kinds of string are $FF, and the |
| TBLLEN | Files::DESCRIPTOR_LAST | constant | all |  | The last index of <Descriptors> and <DescriptorValueTypes>. |
| TYPFNT | Files::DescriptorTypNumbers | table | all |  | What the `TYP` function gives for each descriptor in <Descriptors>: 2 for an integer, 1 a real, 3 a long integer, |
| CHAIN | Statements::Chain | routine | all |  | `CHAIN`: runs another program, keeping the variables; `CHAIN name [, line]`. |
| FRUN | Files::StartProgram | routine | all |  | Starts the program from its beginning, or from the line in <LINNUM> when that is not 0. |
| LDRUN | Files::OpenProgramToRun | routine | all |  | Opens the program file `RUN` or `CHAIN` names, for reading, then reads the line number after a comma, if any. |
| DATSALL | Files::OpenProgramToRun::NoLine | local | all |  | Sets the line to start at to 0, for the program's beginning. |
| DREAD | Statements::ReadFile | routine | all |  | `READ#`: reads items from a data file's record into variables; `READ# file [, record] [; variables]`. |
| RDRTS | Statements::ReadFile::Return | local | all |  | Returns. |
| DRD1 | Statements::ReadFile::NextItem | local | all |  | Takes the comma before the next variable, or ends at the statement's end. |
| DRD2 | Statements::ReadFile::ReadItem | local | all |  | Reads the item at the buffer's offset, moving to the next record at an end-of-record mark. |
| ODERR | Statements::ReadFile::ToEndOfData | entry | all |  | Ends the data: goes to the end-of-file handling in <CHKEOF>. |
| DRDNXT | Statements::ReadFile::NextRecordOrEnd | local | all |  | At an end-of-record mark, moves to the next record, unless the mark is the record's first byte, which ends the |
| DRD3 | Statements::ReadFile::TakeItem | local | all |  | Takes a numeric item into the numeric variable next in the statement; a string item goes to <ReadFileString>. |
| DRD5 | Statements::ReadFile::Assign | local | all |  | Assigns the value to the variable, as the variable's type. |
| DRD6 | Statements::ReadFile::StepOver | entry | all |  | Moves past the item just read, and to the next record when the item ends this one. |
| DRD7 | Statements::ReadFile::ToNextItem | local | all |  | Goes on to the next variable. |
| NTLNT | Statements::ReadFile::ToReal | local | all |  | Converts the value to a real for a real or integer variable. |
| MSMTCH | Files::ToTypeMismatchError | routine | all |  | Ends the statement with a type mismatch. |
| MYPTRGET | FindVariableToAssign | routine | all |  | Finds a variable as <PTRGET> does, and puts its address in <FORPNT> as well, for the statements that assign to it. |
| RDSTRI | Statements::ReadFileString | routine | all |  | Reads a string item into the string variable next in the statement, for `READ#`. |
| NTMXSTR | Statements::ReadFileString::TakeLength | local | all |  | Takes the string's length from the byte after its descriptor. |
| DWRITE | Statements::Write | routine | all |  | `WRITE#`: writes expressions as items into a data file's record; `WRITE# file [, record] [; expressions]`. |
| WRRTS | Statements::Write::Return | local | all |  | Returns. |
| DWR1 | Statements::Write::NextItem | local | all |  | Takes the comma before the next expression, or ends at the statement's end. |
| DWR2 | Statements::Write::TakeItem | local | all |  | Evaluates the next expression. |
| DWR3 | Statements::Write::Place | local | all |  | Starts a record by writing it whole, when the item is the first in it. |
| DWR4 | Statements::Write::CheckFit | local | all |  | Moves to the next record when the item doesn't fit in this one, unless it would fit in none. |
| NXREC | Statements::Write::ToNextRecord | local | all |  | Writes the record back and moves to the next. |
| DNTFIT | Statements::Write::TooLong | local | all |  | Goes to the end-of-file handling for an item too long for any record. |
| ITFITS | Statements::Write::Store | local | all |  | Stores the descriptor and the value's bytes in the buffer. |
| ITF1 | Statements::Write::CopyValue | local | all |  | Copies the value's next byte. |
| DATDON | Statements::Write::Stored | local | all |  | Moves past the item and marks the buffer changed, with the end-of-record mark after it when it fits. |
| GODWR1 | Statements::Write::FreeString | local | all |  | Frees a string's temporary, and goes on to the next expression. |
| SETOUT | Files::MarkChanged | routine | all |  | Marks the file's buffer as changed, to be written back: <FLAG_CHANGED> in the control block's flags. |
| CALCLEN | Files::ItemLength | routine | all |  | Works out an item's length in the file from its descriptor: the descriptor and the value, with a string's length |
| CANUM | Files::ItemLength::Number | local | all |  | Takes a number's length from its descriptor. |
| ADJLEN | Files::ItemLength::AddOne | local | all |  | Adds the descriptor's byte. |
| GOTLEN | Files::ItemLength::Done | local | all |  | Keeps the length. |
| GETXPR | Files::EvaluateItem | routine | all |  | Evaluates `WRITE#`'s next expression and works out its descriptor, pointing <VARPNT> at the bytes to write. |
| NOTINT | Files::EvaluateItem::NotInteger | local | all |  | Goes back to the expression's start, to evaluate it. |
| GETX2 | Files::EvaluateItem::Evaluate | local | all |  | Evaluates the expression and points <VARPNT> at its bytes. |
| GTX3 | Files::EvaluateItem::SetPointer | local | all |  | Points <VARPNT> at the bytes, then packs a real. |
| NTINT2 | Files::EvaluateItem::NotIntegerItem | local | all |  | Clears <INTFLG>: the item is no integer. |
| NTINT3 | Files::ItemDescriptor | routine | all |  | Works out the descriptor for <VALTYP> and <INTFLG>: an integer's, else the type's in <DescriptorValueTypes>, with a |
| GTDSC1 | Files::ItemDescriptor::Search | local | all |  | Looks the type up in <DescriptorValueTypes>, from the end. |
| NTDONE | Files::ItemDescriptor::Matched | local | all |  | Gives a string shorter than 255 characters <DDSTR>, the descriptor before. |
| GOTDSC | Files::ItemDescriptor::Found | local | all |  | Takes the descriptor at the index. |
| ERRMIS | Files::ItemDescriptor::ToTypeMismatchError | local | all |  | Ends the statement with a type mismatch. |
| TSTIN | Files::CheckReadAccess | routine | all |  | Checks that the file may be read, as <CheckWriteAccess> does for writing. |
| TSTOUT | Files::CheckWriteAccess | routine | all |  | Checks that the file may be written, ending the statement with a type mismatch if not. |
| TSTRTS | Files::CheckWriteAccess::Return | local | all |  | Returns. |
| GETVAL | Files::DescriptorType | routine | all |  | Finds a descriptor in <Descriptors> and gives its type from <DescriptorValueTypes>; an unknown descriptor is a type |
| GTVAL1 | Files::DescriptorType::Search | local | all |  | Compares the descriptor with the next entry, from the end. |
| BADMD | Files::DescriptorType::ToTypeMismatchError | entry | all |  | Ends the statement with a type mismatch. |
| GOTVAL | Files::DescriptorType::Found | local | all |  | Gives the descriptor's type. |
| OUTPUT | Statements::OutputFile | routine | all |  | `OUTPUT#`: sends `PRINT`'s output to a text file, or back to the console; `OUTPUT# file`, 0 for the console. |
| OUTRTS | Statements::OutputFile::Return | entry | all |  | Returns. |
| EXEC | Statements::Exec | routine | all |  | `EXEC`: closes any `EXEC` file and opens the named text file for BASIC to take its input from. |
| EXEC2 | Statements::Exec::OpenFile | local | all |  | Opens the named file. |
| EXRTS | Files::SetNewlineMode | routine | all |  | Turns SOS's new-line mode on, at a carriage return, for a text file, closing it with the error if that fails. |
| CLTERR | Files::CloseWithError | routine | all |  | Closes the file in <RWRFNM>, then ends the statement with the SOS error in A. |
| DSKLIN | Files::ReadTextLine | routine | all |  | Reads a line for `INPUT#` from the text file in <FILNO> into <BUF>, or the next catalog line from a directory opened |
| DSKEOF | Files::ReadTextLine::ReadFailed | entry | all |  | Takes a failed read: the end of the file goes to `ON EOF#`'s handling in <CHKEOF>; any other error ends the |
| NMOR | Files::ReadTextLine::ToEndOfFile | local | all |  | Goes to the end-of-file handling in <CHKEOF>. |
| DSKLRT | Files::ReadTextLine::DropReturn | local | all |  | Drops the carriage return that ends the line. |
| DSKLRT1 | Files::ReadTextLine::Finish | local | all |  | Ends the line in <BUF>. |
| LINCAT | Files::ReadTextLine::CatalogLine | local | all |  | Makes the next catalog line with <Directory::NextLine> and copies it to <BUF>, as `INPUT#` reads from a directory. |
| MVCATL | Files::ReadTextLine::CopyLine | local | all |  | Copies the line's next byte. |
| CREATE | Statements::Create | routine | all |  | `CREATE`: makes a file; `CREATE name, CATALOG\|TEXT\|DATA [, size]`. |
| CR1 | Statements::Create::NotCatalog | local | all |  | Takes `TEXT`. |
| CR2 | Statements::Create::NotText | local | all |  | Takes `DATA`. |
| CR3 | Statements::Create::CheckWord | local | all |  | Ends the statement with a syntax error unless a word gave a type, then takes the size and makes the file. |
| CRSNR | Statements::Create::ToSyntaxError | local | all |  | Ends the statement with a syntax error. |
| CRTDO | Files::CreateFile | routine | all |  | Makes the file named at <PTHPTR> as an ordinary file of no size, of the type in <INFLID>. |
| CRTDO2 | Files::CreateWithOptions | routine | all |  | Makes the file named at <PTHPTR> from <CRTTBL>: its type, auxiliary type, storage type and first end of file; |
| BYTBLOCK | Files::ProgramPartSize | data | all |  | The most bytes one `READ` or `WRITE` of the program moves, $7FFF, as four bytes for <SubtractPart>'s 32-bit |
| SAVE | Statements::Save | routine | all |  | `SAVE`: writes the program to a BASIC program file (type $09), making it if need be; `SAVE name`. |
| DSP0LUP | Statements::Save::ClearDisplacement | local | all |  | Clears the displacement's next byte. |
| OPENIT | Files::OpenOfType | routine | all |  | Opens the named file through <OpenNamed>, and closes it with a type mismatch unless its type is the one asked for. |
| DOLOAD | Files::OpenAndLoadProgram | routine | all |  | Opens the named BASIC program for reading and loads it through <LoadProgram>. |
| DOLD2 | Files::LoadProgram | routine | all |  | Loads the program from the open file in <RWRFNM> into memory at <TXTTAB>, setting <ARYTAB> to its end, and closes |
| SVLP1 | Files::LoadProgram::TakeBanks | local | all |  | Takes 64K at a time off the length, as a bank and a bank's pages. |
| SVLP2 | Files::LoadProgram::AddRest | local | all |  | Adds the rest to <TXTTAB> and checks the end is below <MEMSIZ>. |
| SVLDPP | Files::LoadProgram::Fits | local | all |  | Sets <ARYTAB> to the program's end and reads the program. |
| NBP | Files::WrongTypeError | routine | all |  | Closes the file, then ends the statement with a type mismatch: the file is not of the type asked for, such as a |
| SLRTS | Files::TransferDone | routine | all |  | Returns, for <ReadBlock>'s branch. |
| OUTOFM | Files::ToOutOfMemoryError | routine | all |  | Ends the statement with an out-of-memory error. |
| LOAD | Statements::Load | routine | all |  | `LOAD`: loads a BASIC program and returns to the prompt; `LOAD name`. |
| RDWRT | Files::ReadOrWriteBlock | routine | all |  | Reads or writes the next part of the program, by <TransferDirection>: <TRANSFER_READ> for `LOAD`, 0 for `SAVE`. |
| SVWRT | Files::WriteBlock | routine | all |  | Writes from the parameters in <SOSTBL>; an error closes the file and ends the statement. |
| LDRED | Files::ReadBlock | routine | all |  | Reads from the parameters in <SOSTBL>, or writes from them when entered from <WriteBlock>; an error closes the |
| SAVE1 | Files::TransferProgram | routine | all |  | Reads or writes the program's bytes from <INDEX> on, in parts of at most <ProgramPartSize> bytes, until the length |
| LOOPAGIN | Files::TransferProgram::FullPart | local | all |  | Moves a full part and takes it off the length. |
| somewhere | Files::TransferProgram::LastParts | local | all |  | Under 64K left: moves a full part while more than one is left, then the rest. |
| LOOP1 | Files::ProgramLengthFromEnd | routine | all |  | Sets the program's length in <LengthLeft> from the end of file in <FEOF>, less the two bytes before the program. |
| LOOP1A | Files::ProgramLengthFromEnd::CopyByte | local | all |  | Copies the end of file's next byte. |
| RENAME | Statements::Rename | routine | all |  | `RENAME`: renames a file; `RENAME old, new`. Both names go in <NAMBUF>, the new one after the old. |
| UNLOCK | Statements::Unlock | routine | all |  | `UNLOCK`: lets a file be read, written, renamed and destroyed (<Files::FILE_ACCESS_UNLOCKED>); `UNLOCK name`. |
| LOCK | Statements::Lock | routine | all |  | `LOCK`: lets a file only be read (<Files::FILE_ACCESS_LOCKED>); `LOCK name`. |
| DDELETE | Statements::Delete | routine | all |  | `DELETE`: destroys a file; `DELETE name`. |
| PGMLEN | Files::ProgramLength | routine | all |  | Works out the program's length, <ARYTAB> less <TXTTAB>, as a 32-bit number in <LengthLeft>. |
| PGMLEN1 | Files::ProgramLength::Clear | local | all |  | Clears the next byte. |
| PGMLEN2 | Files::ProgramLength::StorePages | local | all |  | Stores the pages' count. |
| PGMLEN3 | Files::ProgramLength::NextBank | local | all |  | Adds a bank's pages for each bank more. |
| SZRTS | Files::ProgramLength::Done | local | all |  | Returns. |
| DOSUB | Files::SubtractPart | routine | all |  | Takes <ProgramPartSize> from the length in <LengthLeft>, after a part of the program has been moved. |
| LOOP | Files::SubtractPart::NextByte | local | all |  | Subtracts the next byte. |
| GRECLN | Files::TakeRecordLength | routine | all |  | Reads an optional record length after a comma into <INAUXID>, <DEFAULT_RECORD_LENGTH> when there is none. |
| BUMSIZ | Files::TakeRecordLength::BadLength | local | all |  | Ends the statement with an illegal quantity error. |
| GRC2 | Files::TakeRecordLength::Store | local | all |  | Keeps the record length. |
| GRCRTS | Files::TakeRecordLength::Done | local | all |  | Returns. |
| WRTRCD2 | Files::WriteRecordOrFail | routine | all |  | Writes the file's record back if it changed, ending the statement on an error. |
| IDNUMR | Files::WriteRecordOrFail::NoError | entry | all |  | Returns with A = 0 and zero set: no error. |
| WRTRCD | Files::WriteRecord | routine | all |  | Writes the file's buffer back to its record when it has changed: the items, and the end-of-record mark when the |
| IDNUM2 | Files::WriteRecord::SetCount | local | all |  | Sets the count: the offset, and one more for the end mark. |
| NXRCD | Files::NextRecord | routine | all |  | Moves to the file's next record: writes the current one back if it changed, then positions to the next and reads |
| NXR2 | Files::NextRecord::Load | local | all |  | Moves to the record and reads it. |
| SETPARMS | Files::SetRecordTransfer | routine | all |  | Sets <SOSTBL> up to read or write the file's whole record through its buffer, with the buffer's offset at 0. |
| SERROR | ReportSosError | routine | all |  | Ends the statement with BASIC's error for the SOS error in A, from <ERRTBL>. |
| FNDAER1 | ReportSosError::Search | local | all |  | Compares the code with the table's next entry. |
| FOUNAR1 | ReportSosError::Found | local | all |  | Gives BASIC's error for the entry found. |
| GETFISET | Files::PrepareGetFileInfo | routine | all |  | Sets <SOSTBL> up for `GET_FILE_INFO` into <FATRB>, all 11 bytes of it; the caller makes the call. |
| SETDSP | Files::RecordPosition | routine | all |  | Works out the start of the file's current record, the record number times the record length, as the displacement |
| QTIP | Files::RecordPosition::CopyPosition | local | all |  | Copies the product's next byte. |
| PPRTS | Files::RecordPosition::Return | entry | all |  | Returns; <SeekRecord> branches here. |
| POSREC | Files::SeekRecord | routine | all |  | Moves the file's mark to the start of its current record. |
| PSRERR | Files::SeekRecord::EndOfData | local | all |  | Leaves an empty record and goes to the end-of-file handling. |
| CTPL | Directory::EntryBuffer | location | all |  | Where each read of the directory goes, in the name buffer. |
| CATALOG | Statements::Catalog | routine | all |  | `CATALOG`: lists a directory, or the prefix's when no name is given; `CATALOG [name]`. |
| ISANAM | Statements::Catalog::Named | local | all |  | Opens the directory named. |
| CG0 | Statements::Catalog::Opened | local | all |  | Checks the file is a directory. |
| CG1 | Statements::Catalog::ClearBlock | local | all |  | Clears the catalog's control block and sets it up. |
| CG2 | Statements::Catalog::NextLine | local | all |  | Prints the next line, until the catalog is done. |
| CATERR | Statements::Catalog::NotDirectory | local | all |  | Closes the file and ends the statement with SOS's bad path error, <SEBDP>. |
| CATDON | Statements::Catalog::Done | local | all |  | Prints a blank line and closes the directory. |
| SETCAT | Directory::Prepare | routine | all |  | Sets a control block up to read a directory as catalog lines: a read-only text file, at stage 0, with no buffer |
| NTROOT | Directory::Prepare::Done | local | all |  | Returns. |
| NCLN | Directory::NextLine | routine | all |  | Makes the catalog's next line in <CATBUF>, by the stage in the control block's flags. |
| NCL1 | Directory::NextLine::Blank | local | all |  | Fills the line with spaces. |
| NCL2 | Directory::NextLine::Dispatch | local | all |  | Goes to the stage's routine, through an RTS. |
| CTDP | Directory::Stages | table | all |  | Each stage's routine, less one, for <NextLine>'s RTS. |
| CATL1 | Directory::NameLine | routine | all |  | Makes the catalog's first line from the directory's header: its name, its creation date in parentheses, and its |
| CL12 | Directory::NameLine::CopyName | local | all |  | Copies the name, from its end. |
| TPL | Directory::NameLine::CopyVersion | local | all |  | Copies the version's digits, then finishes through <CheckDone>. |
| CBL | Directory::BlankLine | routine | all |  | Moves to the next stage, leaving the line blank. |
| TPRTS | Directory::CheckDone | routine | all |  | Tells whether the catalog is done: the stage has reached <STAGE_DONE>. |
| CHDG | Directory::HeadingLine | routine | all |  | Makes the headings line, which its line feed follows with a blank one. |
| CHD2 | Directory::HeadingLine::Copy | local | all |  | Copies the headings, from their end. |
| HDMSG | Directory::Headings | data | all |  | The catalog's headings, and a line feed for a blank line after them. |
| HDGLEN | Directory::HEADINGS_LENGTH | constant | all |  | The length of <Headings>. |
| CMP | Directory::FileLine | routine | all |  | Makes the line for the directory's next file: its access, type, blocks, name, the dates and times it was modified |
| NTLKD | Directory::FileLine::NotLocked | local | all |  | Shows nothing for full access, `+` for anything but read only. |
| STUFACS | Directory::FileLine::StoreAccess | local | all |  | Stores the access's mark. |
| ALLOK | Directory::FileLine::CopyName | local | all |  | Copies the name, then the type's name. |
| CMP1 | Directory::FileLine::NameCharacter | local | all |  | Copies the name's next character, from its end. |
| CMP2 | Directory::FileLine::TypeName | local | all |  | Copies the type's name from <TypeNames>. |
| FORNFILE | Directory::FileLine::OtherType | local | all |  | Writes a type beyond <TypeNames> as `TYP=` and two hex digits, or `PRO=` from $E0, through <OtherTypeText> and |
| FRNLP2 | Directory::FileLine::HexDigit | local | all |  | Makes a hex digit. |
| FRNLP1 | Directory::FileLine::StoreDigit | local | all |  | Stores the digit in both texts. |
| FRNFL | Directory::FileLine::CopyOtherType | local | all |  | Copies the text for the type. |
| ISPRO | Directory::FileLine::StoreTypeCharacter | local | all |  | Stores the text's next character. |
| NOWEOF | Directory::FileLine::EndOfFile | local | all |  | Writes the end of file, as a long integer through <LOUT>. |
| OEOF | Directory::FileLine::CopyEndOfFile | local | all |  | Copies the end of file's next digit, and its 0. |
| NMREOF | Directory::FileLine::Blocks | local | all |  | Writes the blocks used, right-aligned in five columns with zeros to the left. |
| CNTLN | Directory::FileLine::FindLastDigit | local | all |  | Finds the last digit. |
| MVBCNT | Directory::FileLine::CopyBlocks | local | all |  | Copies the digits, from the last. |
| ZBC | Directory::FileLine::PadZeros | local | all |  | Pads the columns to the left with zeros. |
| CMP3 | Directory::FileLine::Dates | local | all |  | Writes the dates and times. |
| CEND | Directory::SummaryLine | routine | all |  | Makes a volume directory's summary line: its blocks free, used and in total. |
| CEN2 | Directory::SummaryLine::CopyWords | local | all |  | Copies the summary's words, from their end. |
| CEND2 | Directory::SummaryLine::NoSummary | local | all |  | Moves the stage on, twice without a summary. |
| FRNTYP | Directory::OtherTypeText | data | all |  | The text for a SOS file type beyond <TypeNames>; <FileLine::OtherType> writes its two hex digits in for each such |
| PROTYP | Directory::ProDosTypeText | data | all |  | The text for a ProDOS file type, $E0 and up; <FileLine::OtherType> writes its two hex digits in for each such file. |
| TYPTB | Directory::TypeNames | table | all |  | The six-character name of each SOS file type, 0 to 21. |
| RDCAT | Directory::ReadEntry | routine | all |  | Reads the directory's next file entry, <FileEntry>, into <EntryBuffer>. |
| RDCAT3 | Directory::ReadEntry::ReadFull | local | all |  | Reads the entry. |
| RDCAT2 | Directory::ReadBytes | routine | all |  | Reads A bytes of the directory into <EntryBuffer>, and moves the control block's offset past them. |
| NMCAT | Directory::ReadBytes::EndOfDirectory | entry | all |  | Returns with carry set: the end of the directory. |
| OKCAT | Directory::ReadBytes::Read | local | all |  | Moves the offset past the bytes read. |
| CTR2 | Directory::ReadBytes::ToCloseWithError | local | all |  | Closes the directory and ends the statement with the error. |
| GENDATE | Directory::WriteDate | routine | all |  | Writes a SOS date into <CATBUF> as MM/DD/YY, from column Y. |
| G2DIGS | Directory::WriteTwoDigits | routine | all |  | Writes a number from 0 to 99 as two digits into <CATBUF>, A columns after the column in <DigitColumn>. |
| AZERH | Directory::WriteTwoDigits::LeadingZero | local | all |  | Puts a 0 before a one-digit number. |
| GENTIME | Directory::WriteTime | routine | all |  | Writes a SOS time into <CATBUF> as HH:MM, from column Y. |
| DONUM | Directory::WriteNumber | routine | all |  | Writes a 16-bit number into <CATBUF>, from column X. |
| DONUM2 | Directory::WriteNumber::CopyDigit | local | all |  | Copies the next digit. |
| DONUMR | Directory::WriteNumber::Done | local | all |  | Returns. |
| SMMSG | Directory::Summary | data | all |  | The summary line's words; <SummaryLine> puts the numbers after them. |
| SUMML | Directory::SUMMARY_LENGTH | constant | all |  | The length of <Summary>. |
| JMPRTAB | ModuleRoutines | table | all |  | The routines BASIC lends invokable modules and `PERFORM`, by number: <SWCHGO> calls entry n for routine n. |
