# Microsoft 6502 BASIC

`m6502.asm` is Microsoft's BASIC 1.1 6502 source from
[microsoft/BASIC-M6502](https://github.com/microsoft/BASIC-M6502), retained unchanged. Its LF-normalized SHA-256 is
`F3EC99C91DEDB8EB3441DED866F45797BB3E03ED26567A253E24CECF23CD63AC`.
The native shared `MsBasic.*.asm` modules are derived from this MIT-licensed source; the original `LICENSE` is kept
beside it.

The AppleSoft and Commodore PET MACRO-10 overlays refer to this shared base. Apple's native `AppleSoft.asm`
includes floating-point and interpreter code from the `MsBasic.*.asm` modules here; Apple-specific I/O,
graphics and command code remains under `AppleSoft`.

The repository keeps this folder in `src/Retrocore.Basic/Roms`; the SDK ships it as `Sdk/Roms/Microsoft6502Basic`,
beside `Sdk/Roms/AppleSoft` and `Sdk/Roms/Pet`. The debug host and editor resolve both layouts. The overlays name
the repository path and use the SDK's shared folder when shipped. AppleSoft's native includes use the SDK-relative
path, so the shipped listing also assembles with a plain file resolver. When using `FileAssemblySourceResolver`
directly on the repository's native root, add this folder to `AssemblyOptions.IncludePaths`.

`MsBasic.Switches.asm` defines common Microsoft configuration values. `REALIO` defaults to 4 for Apple;
Commodore selects 3. Native modules require integer arrays, five-byte floating point and long errors.
`TIME` is only partially wired: `MsBasic.FloatOutput.asm`, used by AppleSoft, passes it to the time-output
code and table; the PET floating-point composition supplies those choices directly. It does not enable or
disable clock support throughout the interpreter. `EXTIO` and `DISKO` are legacy configuration metadata in
the native sources and do not select code. Changing any of these three values is not a way to build a fully
different I/O configuration; platform modules and the interpreter macro arguments make those choices.
The shipped AppleSoft root requires `TIME=0`, `EXTIO=0` and `DISKO=0`; each PET BASIC root requires
`TIME=1`, `EXTIO=1` and `DISKO=1`. The roots assert these values and reject alternate overrides rather
than silently implying a different configuration. Those assertions do not apply to a custom root:
it can supply its own values and independently compose the appropriate clock, channel, disk and
time-output macros.

`MsBasic.FloatConstants.asm` defines macros for the five-byte `ADDPRC=1` constants and polynomial tables shared
by AppleSoft and all three PET BASIC versions. A native variant can emit each block where its ROM needs it.
`MsBasic.AdditionCore.asm` supplies addition, normalization and shifting. `MsBasic.Logarithm.asm` provides the
shared `LOG` routine, which must immediately precede `FMULT` because it falls through to that routine.
`MsBasic.ArithmeticCore.asm` supplies multiplication and division,
including the short zero-result branch used by PET BASIC 1; `MsBasic.MovementCore.asm` supplies the movement and
rounding routines. `MsBasic.ConversionCore.asm` supplies sign, comparison and integer conversion;
`MsBasic.DecimalInputCore.asm` supplies decimal input with either exponent limit;
`MsBasic.OutputCore.asm` supplies decimal output with either positive-sign convention; and
`MsBasic.TranscendentalCore.asm` provides power, exponential, polynomial evaluation and trigonometric routines.
`MsBasic.RandomCore.asm` provides the random-number generator, including the PET timer-seeding variant.

The interpreter modules also retain each variant's original bytes:

| Module | Selection |
| --- | --- |
| `MsBasic.ArrayMultiplication.asm` | Shared unsigned array multiplication, with no switches. |
| `MsBasic.Arrays.asm` | Array lookup and allocation, selecting existing-array support, allocation-counter initialization and the early offset bug independently. |
| `MsBasic.Assignment.asm` | `ASSIGNMENT_START` supplies LET and the `INPCOM` entry. `STRING_ASSIGNMENT` selects optional platform hooks for a disk-status source and linked-string collection. |
| `MsBasic.CharacterReader.asm` | The uppercase-letter test and `CHARACTER_READER` template. The latter takes seed byte `$59` for BASIC 1, `$58` for AppleSoft and BASIC 2/4; startup copies only the first four seed bytes. |
| `MsBasic.ExpressionCore.asm` | `EXPRESSION_CORE 1` carries a `PUSHF` return address across a page, as BASIC 4 does; AppleSoft and BASIC 1/2 use `0`. |
| `MsBasic.OperandEvaluation.asm` | Shared operand and function dispatch, with independent choices for the PI token and Boolean or signed 16-bit logical operators. |
| `MsBasic.VariableInput.asm` | Shared READ and GET/INPUT variable processing, with independent buffer, channel, character-mask and retry choices. |
| `MsBasic.VariableLookup.asm` | Variable-name parsing and scalar lookup, with independent choices for reserved names, zero storage, caller checks and linked-array fixups. |
| `MsBasic.Dim.asm` | Shared comma-separated DIM statement entry before each variant's variable lookup. |
| `MsBasic.Lister.asm` | Shared LIST range parsing, line walking and token expansion, with independently selected vendor and revision behaviors. |
| `MsBasic.Print.asm` | Shared PRINT expression and separator dispatch, retaining each variant's carry and numeric-output behavior. |
| `MsBasic.StringOutput.asm` | Shared output of quote- or zero-terminated text and descriptor-addressed strings. |
| `MsBasic.StringConversion.asm` | Shared STR$ and output-buffer-to-string entries. |
| `MsBasic.StringConcatenation.asm` | Concatenation, backward string moves and temporary release, independently selecting linked or unlinked release. |
| `MsBasic.StringGarbageCollection.asm` | Classic repeated-scan collector with independent descriptor-pointer and array-step choices. |
| `MsBasic.StringStorage.asm` | Shared literal scanning and temporary descriptors, with independent buffer-page and FAC-overflow choices. |
| `MsBasic.StringStorage.Classic.asm`, `MsBasic.StringStorage.Linked.asm` | Select the classic allocator or BASIC 4's linked-string allocator; the collectors remain platform-specific. |
| `MsBasic.For.asm` | Shared FOR frame setup falls through to the platform's next-statement entry. |
| `MsBasic.IntegerConversion.asm` | Shared subscript and signed-integer conversion independently selects the evaluator and type check. The boundary prefix must immediately precede the routine: its fifth comparison byte is the next instruction's opcode. |
| `MsBasic.LineNumber.asm` | Shared decimal line-number parsing accepts values below 64000. |
| `MsBasic.LineSearch.asm` | Shared linked-program search returns the matching line or insertion point. |
| `MsBasic.MemoryAccess.asm` | `MEMORY_ACCESS_ADDRESS` selects negative-address rejection; `MEMORY_ACCESS_PEEK` independently selects address preservation, save order, ROM guarding and padding; `MEMORY_ACCESS_WAIT` takes the omitted-mask branch target. |
| `MsBasic.MemoryManagement.asm` | `MEMORY_MANAGEMENT` takes the stack reserve: `$36` for AppleSoft and BASIC 1, `$3E` for BASIC 2/4. BASIC 1 calculates it as `2*STACK_LEVELS+3*ADDPRC+13`; the macro asserts the required contiguous page-zero scratch layout. |
| `MsBasic.Next.asm` | AppleSoft and BASIC 1 count through the FOR frame; BASIC 2/4 calculate its offsets. The caller also supplies the platform's next-statement entry. |
| `MsBasic.OperatorTable.asm` | AppleSoft uses `OPERATOR_TABLE 1, 1, OROP1`; PET uses `OPERATOR_TABLE 0, 0, ANDOP`. Power/negation and NOT precedences are independent. |
| `MsBasic.ProgramTransfers.asm` | Shared RESTORE, STOP, CONT, RUN, GOSUB, GOTO and RETURN entries. The caller selects direct-mode detection, output suppression, the next-statement target, RETURN's FOR-pointer byte and optional POP handling independently. |
| `MsBasic.ProgramReset.asm` | Shared NEW, CLEAR, NULL, stack reset and text-pointer setup; independent choices preserve platform side effects and BASIC 1's original or revised stack reset. |
| `MsBasic.Relational.asm` | Shared numeric and string comparisons; AppleSoft uses `$01` for true, PET uses `$FF`. |
| `MsBasic.SimpleFunctions.asm` | Shared FRE, POS and integer-to-floating-point entries; `SIMPLE_FUNCTIONS 1` retains AppleSoft's extra carry set, PET uses `0`. |
| `MsBasic.StatementFlow.asm` | Shared DATA/REM scanning and IF/ON dispatch; the scanner independently selects BASIC 1's quote-branch order and AppleSoft's POP unwind entry. |
| `MsBasic.StringFunctions.asm` | Shared CHR$, slicing, LEN, ASC, byte conversion and VAL, with independent choices for slice errors, preamble return, LEN/ASC dispatch and VAL's terminator. |
| `MsBasic.UserFunctions.asm` | `USER_FUNCTIONS 1` retains BASIC 1's low-byte undefined-function check; AppleSoft and BASIC 2/4 use the corrected high-byte check (`0`). |

The memory-access macros use these settings (PEEK's arguments are address preservation, high-byte-first save,
ROM guard and padding):

| Variant | `MEMORY_ACCESS_ADDRESS` | `MEMORY_ACCESS_PEEK` | Omitted WAIT mask |
| --- | --- | --- | --- |
| AppleSoft | `0` | `1, 0, 0, 0` | `ZSTORD`, an alias of `STORDO` |
| PET BASIC 1 | `1` | `0, 1, 1, 0` | `STORDO` |
| PET BASIC 2 | `1` | `1, 1, 0, 1` | `ZSTORD`, its hidden-message extension |
| PET BASIC 4 | `1` | `1, 1, 0, 0` | `STORDO` |

`STRING_FUNCTIONS` takes the zero-slice check, indirect preamble return, shared LEN/ASC jump and VAL terminator
choices in that order. AppleSoft uses `1, 0, 0, 0`; PET BASIC 1 uses `1, 1, 1, 0`, BASIC 2 uses `0, 0, 0, 0`,
and BASIC 4 uses `0, 0, 0, 1`.

`STRING_STORAGE` takes the input-buffer page and whether to clear `FACOV`: AppleSoft uses `2, 0`, PET BASIC 1
uses `0, 0`, and BASIC 2/4 use `2, 1`. Follow it with `STRING_ALLOCATION 1` for BASIC 4's linked allocator,
or `0` for the other variants.

After the matching collector, `STRING_CONCATENATION 0` emits `CAT` through `FRETMS` for AppleSoft and PET
BASIC 1/2; BASIC 4 uses `STRING_CONCATENATION 1` and supplies its `STRADJ` link helper. Follow either with
the variant's `STRING_FUNCTIONS` invocation. The linked-release switch is independent of allocator and
collector selection, but those choices must agree on the representation used by the running interpreter.
The macro requires `EVAL`, `CHKSTR`, `ERROR`, `STRINI`, `PUTNEW`, `TSTOP`, `ERRLS`, `FACMO`, `FACLO`,
`STRNG1`, `DSCPNT`, `INDEX`, `FRESPC`, `FRETOP`, `LASTPT`, `TEMPPT` and `STRSIZ` from its caller.

`PRINT_CORE` takes the TAB handler and independent choices for clearing carry before SPC and comma, and for
printing a separate trailing space after numbers. AppleSoft uses `TABER` (enhanced) or `LINCH1` (earlier),
then `1, 1, 0`; PET BASIC 1 uses `TABER, 0, 0, 1`, and BASIC 2/4 use `TABER, 1, 0, 1`.

The program-reset macros take the independent side effects documented in the source:

| Variant | `PROGRAM_RESET` | `CLEAR_STORAGE` | `EXECUTION_RESET` | `STOP_AND_CONTINUE` |
| --- | --- | --- | --- | --- |
| AppleSoft | `1, 1, 1, 0, 1` | `0, 0` | `0, 0, $F8` | `1, 0` |
| PET BASIC 1 original | `0, 0, 0, 0, 0` | `1, 0` | `1, 0, $FC` | `0, 1` |
| PET BASIC 1 revised | `0, 0, 0, 0, 0` | `1, 0` | `0, 1, $FE` | `0, 1` |
| PET BASIC 2 | `0, 0, 0, 1, 1` | `1, 0` | `0, 0, $FA` | `1, 1` |
| PET BASIC 4 | `0, 0, 0, 1, 1` | `1, 1` | `0, 0, $FA` | `1, 0` |

PET BASIC 1 also retains `NULL_STATEMENT 10` even though its reserved-word table has no NULL token. Its
increment-before-comparison accepts values 0 through 8 and, through byte wraparound, 255.

### BASIC 1's independent choices

The [BASIC 1 root](../../../Retrocore.Machines.Commodore/Roms/Basic/Basic1.asm) gives each choice below an
overridable `.ifndef` default. Supply symbols before including the root, or pass their values to the named
macro parameters when composing another variant. Values are 0 or 1 unless stated otherwise. The existing
workspace switches are documented in `Commodore.Equates.asm`; the root also uses `LOCAL_TERMINAL_POSITION` for output
and initialization and derives `GETSTK`'s reserve from `STACK_LEVELS`. `RESET_STACK_POINTER`, `RANDOM_SEED_TAIL`
and `PROBE_TEST_BYTE` are bytes; `NULL_INCREMENT_LIMIT` is 2 through 255.

| Choice | BASIC 1 default | Macro parameter or effect |
| --- | --- | --- |
| `GO_TOKEN` | 0 | `COMMODORE_DISPATCH_TABLES` `goToken`: emit GO in the word table. |
| `BAD_DATA_ERROR` | 1 | `COMMODORE_DISPATCH_TABLES` `badData`: say BAD DATA, not FILE DATA. |
| `COMMAND_TEST_CHARACTER` | 0 | `COMMODORE_COMMAND_LOOP` `testCharacter`: explicitly test the fetched character. |
| `COMMAND_RESET_BEFORE_INSERT` | 0 | `COMMODORE_COMMAND_LOOP` `resetBeforeInsert`: clear and relink before insertion. |
| `LINK_RETURNS` | 0 | `COMMODORE_COMMAND_LOOP` `linkReturns`: return from relinking instead of entering the prompt. |
| `EARLY_LINE_EDIT` | 1 | `COMMODORE_TERMINAL_INPUT` `earlyDelete`: keep early editor entries and their newline. |
| `TOKENIZE_SKIP_SPACES` | 1 | `COMMODORE_TOKENIZE` `skipKeywordSpaces`: allow spaces within reserved words. |
| `NEW_CLEAR_CARRY` | 0 | `PROGRAM_RESET` `clearCarry`: clear carry before adding two. |
| `RUN_SET_ZERO` | 0 | `PROGRAM_RESET` `runSetsZero`: load zero after positioning the text pointer. |
| `RESET_STACK_EARLY` | `1-REVISD` | `EXECUTION_RESET` `earlyStack`: store the return address before moving the stack pointer. |
| `RESET_STACK_PADDING` | `REVISD` | `EXECUTION_RESET` `paddedReturn`: retain the revised reset's extra RTS and unused byte. |
| `RESET_STACK_POINTER` | `<(STACK_END-$101-2*RESET_STACK_EARLY)` | `EXECUTION_RESET` `stackTop`: byte loaded into the stack pointer. |
| `LIST_GUARD_OFFSET` | 0 | `LIST_LINES` `guardOffset`: stop if a malformed line's index wraps. |
| `STATEMENT_FETCH_NOP` | 0 | `COMMODORE_STATEMENT_FETCH` `spareByte`: insert the later NOP. |
| `EARLY_SEPARATOR_CHECK` | 1 | `COMMODORE_STATEMENT_FETCH` `earlySeparators`: check separators before the link. |
| `SHORT_END_BRANCH` | 1 | `COMMODORE_STATEMENT_FETCH` `shortEnd`: branch directly to end-of-program. |
| `EARLY_STATEMENT_DISPATCH` | 1 | `COMMODORE_STATEMENT_DISPATCH` `earlyDispatch`: use the early carry and error paths. |
| `STOP_BY_LINE_NUMBER` | 0 | `STOP_AND_CONTINUE` `lineNumberDirect`: detect direct mode by line number instead of text page. |
| `NULL_INCREMENT_LIMIT` | 10 | `NULL_STATEMENT` `incrementedLimit`: first rejected incremented NULL count. |
| `RETURN_LOW_FOR_POINTER` | 1 | `RETURN_STATEMENT` `searchLow`: set the low instead of high FOR-pointer byte. |
| `QUOTE_BRANCH_FIRST` | 1 | `STATEMENT_SCAN` `quoteFirst`: branch on a quote before a non-quote. |
| `TIME_LONG_ERROR` | 1 | `TIME_STRING_ASSIGNMENT` `longLengthError`: use the long invalid-length jump. |
| `PRINT_CLEAR_SPC_CARRY` | 0 | `PRINT_CORE` `clearSpaceCarry`: clear carry before SPC dispatch. |
| `PRINT_NULL_PADDING` | 1 | `COMMODORE_LINE_END` `nullPadding`: print the configured NULLs after a newline. |
| `PRINT_TOKEN_SPACING` | 1 | `COMMODORE_PRINT_SPACING` `tokenDispatch`: select TAB/SPC by token and use the early space loop. |
| `ALWAYS_SKIP_CHARACTER` | 1 | `COMMODORE_CHARACTER_OUTPUT` `alwaysSkip`: send cursor-right on all channels. |
| `INPUT_ERROR_EDITOR_PATCH` | 1 | `COMMODORE_INPUT_ERROR` `editorPatch`: use the editor's error-line helper. |
| `INPUT_STOP_EDITOR_PATCH` | 1 | `COMMODORE_INPUT_STATEMENT` `editorPatch`: use the editor's blank-INPUT stop helper. |
| `GET_POINTER_Y_FIRST` | 1 | `VARIABLE_INPUT` `getPointerYFirst`: load GET's buffer-pointer high byte first. |
| `GET_STRING_EDITOR_PATCH` | 1 | `VARIABLE_INPUT` `patchedGetString`: use the editor's GET string helper. |
| `NEXT_COUNTED_STACK` | 1 | `NEXT_ENTRIES` `countedStack`: count through the FOR frame rather than compute offsets. |
| `CLOCK_EDITOR_PATCH` | 1 | `COMMODORE_VARIABLE_VALUE` `clockPatch`: use the editor's TI and TI$ checks. |
| `INTIDX_USE_FRMNUM` | 1 | `INTEGER_CONVERSION` `evaluateEntry`: use FRMNUM, or FRMEVL when 0. |
| `POSINT_CHECK_TYPE` | 0 | `INTEGER_CONVERSION` `checkType`: check the numeric type at POSINT. |
| `ARRAY_SAVE_OFFSET_HIGH` | 0 | `ARRAY_LOOKUP` `saveOffsetHigh`: retain the corrected high offset byte. |
| `USER_FN_LOW_CHECK` | 1 | `USER_FUNCTIONS` `earlyCheck`: check the argument pointer's low instead of high byte. |
| `STRING_CLEAR_FACOV` | 0 | `STRING_STORAGE` `clearFacOverflow`: clear FACOV when making a temporary. |
| `GC_FULL_POINTER` | 0 | `STRING_GARBAGE_COLLECTION` `fullDescriptorPointer`: test both descriptor-pointer bytes. |
| `GC_PATCH_ARRAY_STEP` | 1 | `STRING_GARBAGE_COLLECTION` `patchedArrayStep`: call the editor's array-step helper. |
| `GC_SUBTRACT_OFFSET` | 1 | `STRING_GARBAGE_COLLECTION` `subtractDescriptorOffset`: subtract three instead of masking. |
| `REJECT_ZERO_SLICES` | 1 | `STRING_FUNCTIONS` `rejectZeroSlices`: reject zero LEFT$/RIGHT$ counts. |
| `PREAM_INDIRECT_RETURN` | 1 | `STRING_FUNCTIONS` `indirectReturn`: return through the writable jump. |
| `ASC_SHARED_LEN_JUMP` | 1 | `STRING_FUNCTIONS` `sharedLenJump`: share LEN's conversion jump. |
| `PEEK_PRESERVE_ADDRESS` | 0 | `MEMORY_ACCESS_PEEK` `preserveAddress`: restore the prior POKE/WAIT address. |
| `PEEK_GUARD_ROM` | 1 | `MEMORY_ACCESS_PEEK` `guardRom`: return zero for protected ROM pages. |
| `PEEK_PAD_GUARD` | 0 | `MEMORY_ACCESS_PEEK` `padGuard`: emit eight padding bytes. |
| `SHORT_FMUL_ZERO` | 1 | `FLOAT_ARITHMETIC` `shortZeroBranch`: use the short zero-result branch. |
| `EARLY_FIN_LIMIT` | 1 | `DECIMAL_INPUT` `limitAt120`: use the earlier exponent limit. |
| `PRECISE_FOUT_LIMIT` | 1 | `OUTPUT_CONSTANTS`: use the 999,999,999.5 upper threshold. |
| `ZERO_AT_FHALF` | 0 | Define ZERO in FHALF when 1, or emit it at `SIMPLE_VARIABLE_LOOKUP` when 0. |
| `WAIT_EASTER_EGG` | 0 | Emit the hidden WAIT routine and signature, and route the omitted-mask branch to it. |
| `RANDOM_SEED_TAIL` | `$59` | `CHARACTER_READER` `seedTail`: the random seed's last byte. |
| `INIT_MARK_DIRECT` | 1 | `COMMODORE_INITIALIZE` `markDirect`: mark the current line direct. |
| `INIT_LINE_WIDTH` | 0 | `COMMODORE_INITIALIZE` `lineWidth`: initialize the width and comma-zone position. |
| `INIT_DELAY_SIZE` | 1 | `COMMODORE_INITIALIZE` `delayedSize`: set descriptor size after clearing flags. |
| `INIT_EARLY_BUFFER_SETUP` | 1 | `COMMODORE_INITIALIZE` `earlyBufferSetup`: restore the comma and print a newline. |
| `PROBE_LOAD_ZERO` | 1 | `COMMODORE_MEMORY_PROBE` `explicitZero`: load zero before setting the RAM address. |
| `PROBE_LOAD_INDEX_ZERO` | 1 | `COMMODORE_MEMORY_PROBE` `explicitIndex`: load Y with zero rather than copy A. |
| `PROBE_SAVE_START` | 0 | `COMMODORE_MEMORY_PROBE` `saveProgramStart`: save TXTTAB before probing. |
| `PROBE_STOP_AT_SCREEN` | 1 | `COMMODORE_MEMORY_PROBE` `screenStop`: compare against the early screen boundary. |
| `PROBE_TEST_BYTE` | `$92` | `COMMODORE_MEMORY_PROBE` `probeByte`: first value written when testing RAM. |
| `START_CARRY_PROGRAM_START` | 1 | `COMMODORE_START_PROGRAM` `carryProgramStart`: carry the start increment into the high byte. |
| `START_BANNER_AFTER_FREE` | 1 | Select the early sign-on both in `COMMODORE_START_PROGRAM` and `COMMODORE_START_MESSAGES`. |

These are individual source choices, not a promise that every combination is a valid BASIC 1 ROM. The root
still asserts its exact editor-spill and patch addresses; a length-changing selection can fail those assertions,
and compensating lengths do not make an altered image stock. Relinking before insertion requires `LINK_RETURNS`.
The early separator and dispatch choices must agree in this composition, and the later dispatch also needs the
GO token. The fixed editor-patch block supplies helpers referenced by several choices: for example, disabling
`INPUT_ERROR_EDITOR_PATCH` duplicates its GETDTL definition, while disabling `CLOCK_EDITOR_PATCH` removes
entries the fixed patch needs. A new variant may instead compose the macros with its own matching helpers and
layout. Changing workspace or string-representation choices likewise requires compatible consumers.

The [Commodore floating-point module](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.FloatingPoint.asm)
composes these macros in PET ROM order, including BASIC 2's WAIT message and BASIC 4's checksum and padding. Its
caller supplies the external symbols. Tests compare the complete
`FADDH`-to-`INITAT` region, including its editor-ROM spill, against all five PET overlay builds.

The [Commodore platform definitions](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.Platform.asm)
include the workspace, dispatch, assignment and channel I/O macros without emitting bytes. The
[workspace](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.Equates.asm) defines PET RAM and system
entry addresses and documents the independent switches for BASIC 1, 2 and 4; its default is BASIC 2. The shared
math package also assembles against these equates for every PET revision.
The [dispatch tables](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.DispatchTables.asm) emit the
statement and function vectors, the shared operator table, reserved words and messages. Their independent choices
select GO, disk commands, the early file-data message and single-CR messages; the workspace's `ERROR_PADDING5`
selects the early error-table padding. Tests compare the tables and error offsets against every PET overlay.
The [clock-string assignment](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.TimeAssignment.asm)
goes between `ASSIGNMENT_START` and `STRING_ASSIGNMENT`. BASIC 4's
[string-assignment hooks](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.StringAssignment.asm)
handle the mutable disk-status string and linked collector. Tests compose these with the shared assignment code
and compare its complete `LET`-to-`PRINTN` region against all five PET overlay builds.
[Channel output](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.ChannelPrint.asm) supplies PRINT#,
CMD, input-line completion, newlines, print spacing and character output. Its options preserve BASIC 1's
NULL padding and SPC(0) behavior and BASIC 4's channel-dependent line feed and unsuppressed output.
[Channel input](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.ChannelInput.asm) supplies malformed-input
handling, GET, INPUT, INPUT# and channel release, selecting the page-zero or page-two input buffer independently.
[BASIC 4's operand split](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.Basic4Patches.asm) preserves
the checksum, reserved patch space and revised-ROM fixes before variable-value handling.
[BASIC 1's editor patches](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.Basic1Patches.asm) retain
its input, clock, terminal-position and array-descriptor fixes in the editor ROM.
[Variable evaluation](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.VariableEvaluation.asm) handles
the PET clock and status variables, including BASIC 1's clock patches and BASIC 4's disk status.
[Initialization](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.Initialization.asm) sets the workspace,
probes RAM and prints the variant's sign-on before entering BASIC.
[Statement dispatch](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.StatementDispatch.asm) preserves
the early separator checks, GO handling, BASIC 4 disk-token gap and revised PI-token fix.
[Linked string collection](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.StringGarbageCollection.asm)
provides BASIC 4's single-pass collector; AppleSoft and BASIC 1/2 use the shared classic collector.

The [BASIC 1](../../../Retrocore.Machines.Commodore/Roms/Basic/Basic1.asm),
[BASIC 2](../../../Retrocore.Machines.Commodore/Roms/Basic/Basic2.asm) and
[BASIC 4](../../../Retrocore.Machines.Commodore/Roms/Basic/Basic4.asm) roots compose the shared interpreter and
Commodore modules into their ROMs, including BASIC 1 and 2's editor-ROM spill and BASIC 1's separate editor patch.
PET uses these native roots by default; `basicSource: "macro10"` selects the retained overlays.
