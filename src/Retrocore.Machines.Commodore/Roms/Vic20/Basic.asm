; retrocore: style=strict
;; COMMODORE VIC-20 BASIC 2
;;
;; The VIC-20's BASIC is the PET's BASIC 2 moved to the VIC-20's kernal. It fills the BASIC chip, 901486-01 at
;; $C000-$DFFF, and goes on into the first 1148 bytes of the kernal chip, to $E47B; the kernal's own code begins at
;; $E47C. Against the PET's BASIC 2 it:
;;
;; - starts with the cold- and warm-start addresses, the first of which the kernal's start-up jumps through, and the
;;   `CBMBASIC` signature;
;; - jumps through six RAM vectors at $0300 to report errors, read and tokenize a line, list a token, run a statement
;;   and read an operand, so that a program can put its own code in front of them (<BASIC_RAM_VECTORS>);
;; - numbers its errors from 1, the kernal's first (<NUMBERED_ERRORS>), and reports the errors the kernal returns;
;; - calls the kernal for what the PET's BASIC did itself: the clock, the status, the cursor's column and the I/O base
;;   for `RND(0)`; and has its own `LOAD`, `SAVE`, `VERIFY`, `OPEN`, `CLOSE` and `SYS`, which on the PET were the
;;   kernal's (<STANDARD_KERNAL>);
;; - has a larger page-zero workspace: two conversion vectors, `TAB`'s column and the LOAD/VERIFY flag are added, and
;;   the output-suppression and line-width bytes are gone, so that from <LineNumber> on everything is three bytes
;;   higher than in the PET's;
;; - and has a few later fixes of Microsoft's: a five-byte -32768, a whole line-number compare in `GOTO`, `DATA`
;;   found after spaces, a blank `INPUT` line that ends the statement rather than the program.
;;
;; Its shared Microsoft and Commodore modules are emitted in ROM address order, as in the PET's roots. The names follow
;; the BASIC conversion's (docs/conversions/Basic.md); Commodore's names from its listing of the VIC-20's BASIC (BV20)
;; are kept in `Also:`. Under the lineage rule (docs/Bibliography.md), BV20 is cited wherever it gives a definition's
;; name at the same address or value, on the shared definitions in every build that has them as well as on the
;; VIC-20's own. A name of its own for a definition is another `Also:` name, in Commodore's files, or, for a
;; definition of the shared Microsoft modules, an alias in Commodore.HistoricalNames.asm.
;;
;; It assembles byte-identically to 901486-01 and to the first $47C bytes of 901486-06 with PAL = 0, or 901486-07 with
;; PAL = 1.

.cpu Mos6502

; The build switches the BASIC conversion renamed (decision X15). A switch predefined by its old name would be
; ignored, since an .ifndef default is not reached through Also:, so it is an error.
.assert .not .defined(BUFPAG), "Predefine INPUT_BUFFER_PAGE, not BUFPAG."
.assert .not .defined(BUFLEN), "Predefine INPUT_BUFFER_LENGTH, not BUFLEN."
.assert .not .defined(NULCMD), "Predefine NULL_COMMAND, not NULCMD."
.assert .not .defined(NUMLEV), "Predefine STACK_LEVELS, not NUMLEV."
.assert .not .defined(STKEND), "Predefine STACK_END, not STKEND."
.assert .not .defined(LOCAL_TRMPOS), "Predefine LOCAL_TERMINAL_POSITION, not LOCAL_TRMPOS."
.assert .not .defined(VARTXT_IN_LINNUM), "Predefine VARIABLE_LIST_IN_LINE_NUMBER, not VARTXT_IN_LINNUM."
.assert .not .defined(INTPRC), "Predefine INTEGER_VARIABLES, not INTPRC."
.assert .not .defined(ADDPRC), "Predefine ADDITIONAL_PRECISION, not ADDPRC."
.assert .not .defined(LNGERR), "Predefine LONG_ERRORS, not LNGERR."
.assert .not .defined(SHORT_FMUL_ZERO), "Predefine SHORT_MULTIPLY_ZERO, not SHORT_FMUL_ZERO."
.assert .not .defined(EARLY_FIN_LIMIT), "Predefine EARLY_INPUT_EXPONENT_LIMIT, not EARLY_FIN_LIMIT."
.assert .not .defined(PRECISE_FOUT_LIMIT), "Predefine PRECISE_OUTPUT_LIMIT, not PRECISE_FOUT_LIMIT."
.assert .not .defined(ZERO_AT_FHALF), "Predefine ZERO_IN_HALF_CONSTANT, not ZERO_AT_FHALF."

.ifndef PAL
;; 1 for the PAL kernal chip, 901486-07, whose checksum byte at $E475 differs; 0 for the NTSC chip, 901486-06.
PAL = 0
.endif
.assert PAL = 0 || PAL = 1, "PAL is 0 or 1."

;; Start of the BASIC ROM.
;; Also: ROMLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ROM_ORIGIN = $C000

; The workspace.
;; The input buffer's length: four of the VIC-20's 22-column lines and one character more.
;; Also: BUFLEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
INPUT_BUFFER_LENGTH = 89

;; The screen's width.
;; Also: LINLEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LINE_LENGTH = 22

;; `PRINT`'s comma zones: 11 columns, two to a line.
;; Also: CLMWID (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ZONE_WIDTH = 11

;; No line-width bytes.
LINE_WIDTH_STORAGE = 0

;; No Control-O output suppression.
OUTPUT_SUPPRESSION_FLAG = 0

;; The float-to-integer and integer-to-float vectors at $03.
CONVERSION_VECTORS = 1

;; The cursor's column read through the kernal's <KernalPlot>.
CURSOR_COLUMN_FROM_PLOT = 1

;; The VIC-20's kernal.
STANDARD_KERNAL = 1

;; The RAM vectors at $0300.
BASIC_RAM_VECTORS = 1

;; Errors numbered from 1.
NUMBERED_ERRORS = 1

; The floating-point package.
;; Use the later multiply-by-zero branch.
SHORT_MULTIPLY_ZERO = 0

;; Use the later decimal exponent limit.
EARLY_INPUT_EXPONENT_LIMIT = 0

;; Use the later decimal-output threshold.
PRECISE_OUTPUT_LIMIT = 0

;; Define <ZeroValue> within the half constant.
ZERO_IN_HALF_CONSTANT = 1

;; No hidden WAIT message.
WAIT_EASTER_EGG = 0

;; No BASIC 4 output patch space.
BASIC4_OUTPUT_PADDING = 0

;; The BASIC chip's checksum byte and patch space before `SQR`.
SQR_PATCH_SPACE = 1

;; The byte at $DF52 that makes the BASIC chip's checksum come out to $C0, its page.
BASIC_ROM_CHECKSUM = $BF

;; Line numbers printed without a space before them.
UNSPACED_LINE_NUMBERS = 1

; Define the shared and platform macros before emitting the interpreter.
.include "../Basic/Commodore.InterpreterMacros.asm"
.include "../Basic/Commodore.SharedModules.asm"

; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 1, "VIC-20 BASIC requires TIME = 1."
.assert EXTIO = 1, "VIC-20 BASIC requires EXTIO = 1."
.assert DISKO = 1, "VIC-20 BASIC requires DISKO = 1."

.org ROM_ORIGIN

;; The kernal's start-up starts BASIC through this word: <ColdStart>'s address.
BasicColdStartVector:
    .word ColdStart

;; STOP-RESTORE and BRK start BASIC warm through this word: <WarmStart>'s address.
BasicWarmStartVector:
    .word WarmStart

;; The signature after the vectors, the ROM's name.
BasicSignature:
    .byte "CBMBASIC"

    ; Dispatch tables, errors, command input and program editing.
    CommodoreDispatchTables 1, 0, 0, 0
    MemoryManagement $3E
    CommodoreErrorReady 0
    CommodoreCommandLoop 1, 1, 1, 0
    CommodoreTerminalInput 0, 1
    CommodoreTokenize 0, 0
    SharedLineSearch

    ; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, 1, 1
    ClearStatement ResetStack::Done
    ClearStorage 2, 0
    ExecutionReset 0, 0, $FA
    ListRange 0, FindLine::Done
    ListLines 1, 1, 0, Float::PrintDecimalAX, 0, ReadyForCommand
    ListTokens 0, 1, 1, 0, ListTokenVector
    SharedFor
    CommodoreStatementFetch 1, 0, 0, GetNextCharacter
    CommodoreStatementDispatch 0, 0
    RestoreStatement
    StopAndContinue 1, 0, KernalTestStopKey
    RunStatement KernalSetMessages
    GosubAndGoto NextStatement, 1
    ReturnStatement 0, 0
    StatementScan 0, 0
    ConditionalStatements
    OnStatement
    SharedLineNumber
    AssignmentStart
    TimeStringAssignment 0
    StringAssignment 0, 0

    ; Terminal and channel output, then READ and input.
    CommodorePrintChannels
    PrintItems PrintTabOrSpace, 1, 0, 1
    CommodoreLineEnd INPUT_BUFFER_PAGE, 0, 2, 0
    CommodorePrintSpacing 0
    SharedStringOutput
    CommodoreCharacterOutput 0, 0, 0, 1
    CommodoreInputError 0
    CommodoreChannelInput INPUT_BUFFER_PAGE
    CommodoreInputStatement 0, 2, 0, 0, 0, 1
    VariableInput INPUT_BUFFER_PAGE, 0, 0, 0, 1, 0, 1
    VariableInputMessages 0, 0

    ; Expressions, variables, arrays and strings.
    NextEntries 0, NextStatement, 1
    ExpressionCore 0
    OperandEvaluation 1, 1, CallFunction, OperandVector, 1
    CommodoreKernalVariableValue
    FunctionDispatch
    LogicalOperators 1
    RelationalOperators $FF
    SharedDim
    VariableSearch 0, 0, 1, 0, 1, 0
    LetterTest
    SimpleVariableLookup 0, 0, 0, 1, 1, 0, 0, 0
    IntegerConversionBoundary 1
    IntegerConversion EvaluateExpression, 1, 1
    ArrayLookup 0, 1, 1
    SharedArrayMultiplication
    SimpleFunctions 0, KernalPlot
    UserFunctions 0
    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, 1
    StringAllocation 0
    StringGarbageCollection 1, 0, 0
    StringConcatenation 0
    StringFunctions 0, 0, 0, 1

    ; Memory access, the floating-point package with the kernal calls and I/O statements after RND, and start-up.
    AddressConversion 1
    PeekFunction 1, 1, 0, 0
    PokeStatement
    WaitStatement Statements::Wait::StoreMask
.include "../Basic/Commodore.FloatingPoint.asm"
.include "../Basic/Commodore.HistoricalNames.asm"
    CommodoreKernalColdStart
    CharacterReader $58
    CommodoreKernalInitialization

;; The byte that makes the kernal chip's checksum come out to $E0, its page, counting with the end-around carry. The
;; NTSC and the 50 Hz kernals differ, so the byte does; <PAL> picks it.
;; Also: CHKE0 (BV20)
KernalRomChecksumAdjustment:
.if PAL
    .byte $E8
.else
    .byte $41
.endif

;; Relinks a program that `LOAD` read while a program ran, then restores the `DATA` pointer and the stack, keeping the
;; variables, as BASIC's `LOAD` did before. Commodore's listing dates the patch 6 March 1981: it is for a program
;; loaded at another address than it was saved from.
;; Also: PLINK (BV20)
.proc RelinkLoadedProgram
    jsr LinkProgram
    jmp ClearVariables::RestoreData
.endproc

;; The address after the interpreter's last byte, in the kernal chip, where the kernal's own code begins. `PEEK` has
;; no ROM guard, so nothing refers to it.
;; Also: LASTWR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, K4S79, HVK4)
InterpreterEnd:

.assert * = $E47C, "VIC-20 BASIC must end at $E47B in the kernal chip."
