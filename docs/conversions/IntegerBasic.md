# Integer BASIC: conversion log

`src/Retrocore.Machines.Apple2/Roms/IntegerBasic/`: Steve Wozniak's Integer BASIC ($E000-$F424), and the routines
that share its three ROM chips: Wozniak and Rankin's floating point ($F425), the Mini-Assembler ($F500) and SWEET16
($F689). One root, `IntegerBasic.asm`, and two builds:

| Build | Switch | Digest test |
| --- | --- | --- |
| The ROMs (341-0001, -0002, -0003) | `FORFIX` = 0, the default | `Apple2SourceTests`, "Integer BASIC" |
| The 1983 DOS 3.3 System Master's INTBASIC | `FORFIX` = 1: two bytes of `DropOlderForLoop` | `Apple2SourceTests`, "Integer BASIC with FORFIX" (new with this conversion) |

The root asserts that `FORFIX` is 0 or 1. `FORFIX` is the SDK's switch, which C# predefines, and keeps its name.

## Sources and citations

- **IBSM**: Paul R. Santa-Maria's annotated listing, in the form Andy McFadden's SourceGen port gives it (the cc65
  text from 6502disassembly.com, as a2stuff/intbasic carries it). The port assembles with the repository's assembler
  to the ROM's $E000-$F424 byte for byte, so each of its names has an address; a name is cited where the port
  defines it at the address the build gives it (201 citations). The port adds a few names of McFadden's, mostly on
  loops: the generic ones (`Loop12`, `Return4`, `unref_...`) and the address labels Santa-Maria gave routines he did
  not name (`LE00C`, `TE801`) are generated, and dropped. The port's `MON_` names for the Monitor's locations are
  not cited; those definitions carry the Monitor's own documents.
- **A2RM78**: Apple's listings of the floating point, the Mini-Assembler and SWEET16 in the 1978 Red Book, read from
  the Internet Archive's OCR text and checked label by label (184 citations; four names are read through OCR damage:
  DIVv4, ROL/ROH and BRL for DIV4, R0L/R0H and BR1). The Mini-Assembler has no label at $F666 in the listing, so
  MINIASM is UNKN, as in the Monitor's log (Monitor.md, 6).
- **UNKN**: the names this source used before the conversion that no document gives (228): its own names for the
  routines Santa-Maria left as addresses (`BLANKIFLET`, `CHKSTRRNG` ...), the syntax table's item and rule names,
  and SWEET16's ADD16 and POP16 and register routines. Kept as the bridge for code written against the earlier source
  (Monitor.md, 6). Names with a generated number (`CMPVARNAME_3`) are dropped.
- The Monitor's locations and routines Integer BASIC uses keep the Monitor's own citations (A2RM78, A2RM79, IIEROM82,
  IIETRM85), as MonitorEntries.asm's do.

## Decisions

- I1. Every name is renamed to the style; the documents' names go in `Also:` as above. A name that clashes inside
  this assembly goes in prose: Santa-Maria's SAVE (the `SAVE` statement, as the Monitor's SAVE is `SaveRegisters`'s),
  SWEET16's ADD and POP (the floating point's ADD and the `POP` statement), and the macros' MSG, KEY and KEYEND (a
  macro carries no `Also:`).
- I2. The token routines are in the scopes `Statements`, `Functions` and `Operators`, as AppleSoft's are, each one
  scope in pieces through the ROM in address order (`.scope Statements continued`); the first piece of each carries
  its `;;` block (`Statements` in Lister.asm, `Operators` and `Functions` in Strings.asm). They are named for their
  keywords, split at words as AppleSoft's (`Statements::HLin`, `Statements::GoSub`), and since Integer BASIC gives
  each use of a keyword its own token, a statement's other parts take its name and the part (`Statements::HLinComma`,
  `Statements::HLinAt`, `Statements::PrintString`, `Statements::PrintNumber`). The commas and `AT`s that take a first
  value share `Statements::FirstValue` (GETVAL255).
- I3. Subject scopes for the rest: `Lister`, `Strings`, `Editor` (the command loop's line input and storing a line),
  `Tokenizer`, `Interpreter` (`Interpreter::RunLine`, EXECLINE, with the priority loop as its locals, since the
  variable lookup branches back into it), `Variables`, `Lines` (the run loop), `Verbs` (the priority and routine
  tables), `Messages`, `Syntax`, `Memory`, `Display` (TRACE and DSP output), `Break` (Control-C and CON's saved
  place), `Cassette`, `Float`, `MiniAssembler` and `Sweet16`. Top level: the entries and helpers several subjects use
  (`ColdEntry`, `WarmEntry`, `ColdStart`, `WarmStart`, `PrintDecimal`, `FindLine`, `PushNoun`, `GetNumber`,
  `GetByte`, `ReportError`, `MemoryFullError`, `RangeError` ...).
- I4. Integer BASIC's own page zero: `LowMemory` and `HighMemory` (LOMEM and HIMEM, the names BASIC programmers know
  from LOMEM: and HIMEM:), `ProgramStart` (PP), `VariablesEnd` (PV), `Accumulator` (ACC), `Auxiliary` (AUX),
  `CurrentLine` (PR, the address of the line running), `TokenPointer` (PX), `Pointer1` to `Pointer3`, the stacks'
  `NounStackLow`/`NounStackHigh`/`NounStackNumberHigh` and `SyntaxStackLow`/`SyntaxStackHigh`, and the `GOSUB` and
  `FOR` stacks' columns in page 1 by what they hold (`GoSubTokenLow`, `ForLimitHigh` ...), with STK_00 ... STK_D0
  in `Also:`. Flags are named for what they mean when set: `Running`, `SkippingStatement` (IFFLAG), `ReturnPending`
  (CRFLAG), `AutoNumbering`.
- I5. Equates.asm defines the Monitor's locations and routines Integer BASIC uses by the Monitor's current names, each
  `Inherit:`ing the Monitor's documentation and repeating its historical names, in the Monitor's scopes where it has
  them (`LowRes::Plot`, `Disassembler::Decode::Opcode`, `Commands::RunCommand`); `CV` stays `CV`, as the Monitor keeps
  it. It does not include ../System/IIeEquates.asm, as DOS's equates do: that file's Monitor ACC (on `SavedA`) would
  clash with Integer BASIC's ACC. `WriteCassetteWithHeader` ($FECF, `WriteCassette` + 2; WRITE0, UNKN) is the
  Monitor's cassette writer entered after it loads the header's length.
- I6. Shared values are constants in Equates.asm: the tokens the code tests or writes (`TOKEN_*`), the stacks' sizes
  (`GOSUB_STACK_DEPTH` ...), the syntax table's character format (`SYNTAX_*`), the screens' sizes, and two structs:
  `ProgramLine` (a stored line) and `VariableFields` (the bytes after a variable's name). The syntax table's item
  codes and rule numbers are prefixed sets in `Syntax` (`Syntax::ITEM_LAST`, `Syntax::RULE_EXPRESSION`); the message
  offsets are the messages' labels in `Messages` (`ldy #<Messages::TooLong`).
- I7. The verb tables and the syntax table's rule index are written with macros that assert each entry's token or
  rule number; the priorities stay numbers 0 to 15, an ordering the table's comment explains.
- I8. BASIC keywords in prose are written in backticks, as AppleSoft's sources do.
- I9. Addresses other code calls are asserted: `ColdEntry` $E000 and `WarmEntry` $E003 (the Monitor's Control-B and
  Control-C), `MemoryFullError` $E36B, `PrintDecimal` $E51B and `Statements::Load` $F0DF (Programmer's Aid),
  `Lines::RunFromStart` $E836 (DOS's CHAIN, its IBCHN), the floating point's entries, `MiniAssembler::Run` $F666,
  `Sweet16::Run` $F689 and `Sweet16::Run::WithoutSaving` $F68C (Programmer's Aid's SW16+3).
- I10. The debugger looks Integer BASIC's statement, prompt and error addresses up through
  `SymbolsWithHistoricalNames`, by the old names (RUNLOOP, WAITTOKEN, CMDPROMPT, ERRMESS, RUN, CON, STOPPED_AT, END,
  TRYLINE_END), as the AppleSoft hosts use Microsoft's (Basic.md, B7-3); every one stays in its definition's `Also:`.
  `IntegerSyntaxMatcher` (C#) mirrors the tokenizer under Santa-Maria's names, which still find the definitions.
- I11. DOS keeps its own names for Integer BASIC's addresses (IBCHN, IBLMEM ...) and links Integer BASIC's current
  definitions, as it does AppleSoft's (Basic.md, B7-1); Programmer's Aid's `Inherit:` links name the current
  definitions. DOS's `ignore=unlinked-name:PR` and `MULT` exclusions, which Integer BASIC's old PR and MULT needed, go.

## Found in the conversion

Documented in the code, not changed (the bytes stay):

- Multiplication checks for overflow only when the partial product doubles, so the last addition is unchecked
  (3 * 16000 gives -17536); `MOD`'s remainder takes the quotient's sign (7 MOD -2 is -1).
- `=`, `#`, `<>`, the comparisons and `NEXT`'s limit test subtract, so numbers more than 32767 apart give >32767
  (`FOR I = -20000 TO 20000` fails at `NEXT`); addition allows -32768, which only negating or printing reports.
- While a false `IF`'s statement is skipped, constants and strings are pushed with an extra DEX and not popped until
  the line ends, so enough of them give the noun stack's PPED AT error.
- `HIMEM:` raised with a program in memory loses the program (the copy loop's test is reversed); the unused
  `SetHighMemory` draws a `VLIN` for a value below LOMEM instead of the RANGE error; `HLIN`'s and `VLIN`'s ends are not
  checked against the screen; Control-C's check covers one character when X is $81 or more.
- After `INPUT` of numbers, `Running` is $FF whatever it was; in immediate mode (`IF ... THEN INPUT A`) the run loop
  may take the typed line for a program line. Not run on a machine (an open question, below).
- `NextTabStop` loops forever for a cursor column of $F8 or more, which a normal window never gives.
- The floating point's FIX rounds a negative number toward 0 only when the fraction's top 8 bits are nonzero; a Return
  alone at the Mini-Assembler's `!` prompt is an error.

Comments found wrong and fixed include `GETQLINE`'s outputs, which string `EQ_STR` took as which, the lister's rule
for blanks before keywords, the verb priorities' example (* runs before a + that follows it), FORDROPOLD's account of
which loop's byte a moved loop keeps, R14H's account in SWEET16, and where the Mini-Assembler's error caret lands.

## Open questions for the owner

- Q1. Rule names the grammar does not settle: `RULE_STATEMENTS_TEXT_TO_TAB` and `RULE_STATEMENTS_LIST_TO_IN` (SSTMT2
  and SSTMT3) and `RULE_NUMBER_THEN_ARRAY` (SUNUSED1, which no rule calls).
- Q2. `StashRegisters`, `RecoverRegisters` and `StashedA` ... (the two register routines at $F669 that nothing in the
  ROM calls) are top level; they belong to no family.
- Q3. Several helpers are top level only because each serves another file's subject (`CheckSubstringEnd`,
  `BlankBeforeKeyword`, `WriteKeywordToken`, `ReadNextLineByte`, `PrintErrorMessage`); they could move into
  `Strings`, `Lister`, `Tokenizer` and `Interpreter`.
- Q4. Some `Keeps: X` contracts (SetPrompt, PrintMessage, PRINT's routines) rely on the output hook keeping X, as
  Integer BASIC itself does (PrintDecimal counts in X across `CharacterOut`), though the Monitor's documentation
  promises only Y, and a hook a program installs may not keep X.
- Q5. The `Running` flag after `INPUT` in immediate mode, above.
- Q6. The Red Book's Mini-Assembler listing calls $FC1A CURSUP; MonitorEntries' `CursorUp` does not give that name.
