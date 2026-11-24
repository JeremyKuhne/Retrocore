; retrocore: style=strict
;; COMMODORE PET BASIC 4
;;
;; The BASIC 4 interpreter and its monitor and disk-command extension occupy $B000-$DFFF.
;; Set <REVISD> to 0 for the original $B000 ROM chip or 1 for the revised chip.
;;
;; It assembles byte-identically to Commodore's chips: `PetRomSourceTests` checks every build against their digests.

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

.ifndef REVISD
;; 1 selects the revised $B000 BASIC 4 chip.
REVISD = 1
.endif
.assert REVISD = 0 || REVISD = 1, "REVISD is 0 or 1."

.ifndef DISK_STATUS_STRING
;; Reserve the disk-status string descriptor.
DISK_STATUS_STRING = 1
.endif
.ifndef LINE_WIDTH_STORAGE
;; Omit the later interpreter's line-width storage.
LINE_WIDTH_STORAGE = 0
.endif
.ifndef EXTENDED_DISK_VECTORS
;; Include the disk-command vectors.
EXTENDED_DISK_VECTORS = 1
.endif

;; Start of the BASIC 4 ROM.
;; Also: ROMLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ROM_ORIGIN = $B000

;; Use the later multiply-by-zero branch.
SHORT_MULTIPLY_ZERO = 0

;; Use the later decimal exponent limit.
EARLY_INPUT_EXPONENT_LIMIT = 0

;; Use the later decimal-output threshold.
PRECISE_OUTPUT_LIMIT = 0

;; Define <ZeroValue> within the half constant.
ZERO_IN_HALF_CONSTANT = 1

;; Omit BASIC 2's hidden WAIT message.
WAIT_EASTER_EGG = 0

;; Include BASIC 4's output patch space.
BASIC4_OUTPUT_PADDING = 1

; Define the shared interpreter, linked-string collector and BASIC 4 extension.
.include "Commodore.InterpreterMacros.asm"

; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 1, "BASIC 4 requires TIME = 1."
.assert EXTIO = 1, "BASIC 4 requires EXTIO = 1."
.assert DISKO = 1, "BASIC 4 requires DISKO = 1."

.include "Commodore.StringGarbageCollection.asm"
.include "Commodore.Basic4Extension.asm"

; Dispatch tables, errors, command input and program editing.
.org $B000
    CommodoreDispatchTables 1, 1, 0, 1
    MemoryManagement $3E
    CommodoreErrorReady 0
    CommodoreCommandLoop 1, 1, 1, 1
    CommodoreTerminalInput 0, 1
    CommodoreTokenize 1, 0
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

    ; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, 1, 1
    ClearStatement ResetStack::Done
    ClearStorage 1, 1
    ExecutionReset 0, 0, $FA
    ListRange 0, FindLine::Done
    ListLines 1, 1, 0, Float::PrintDecimalAX, 0, ReadyForCommand
    ListTokens 1, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
.if REVISD
    CommodoreStatementFetch 0, 0, 0, FetchStatementCharacter
.else
    CommodoreStatementFetch 0, 0, 0, GetNextCharacter
.endif
    CommodoreStatementDispatch 0, 1
    RestoreStatement
    StopAndContinue 1, 0
    RunStatement
    GosubAndGoto NextStatement
    ReturnStatement 0, 0
    StatementScan 0, 0
    ConditionalStatements
    OnStatement
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    AssignmentStart
    TimeStringAssignment 0
    StringAssignment 1, 1
    StringLinkAdjust REVISD

    ; Terminal and channel output, then READ and input.
    CommodorePrintChannels
    PrintItems PrintTabOrSpace, 1, 0, 1
    CommodoreLineEnd INPUT_BUFFER_PAGE, 0, 1, 0
    CommodorePrintSpacing 0
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    CommodoreCharacterOutput 0, 0, 0, 0
    CommodoreInputError 0
    CommodoreChannelInput INPUT_BUFFER_PAGE
    CommodoreInputStatement 0, 3, REVISD, 0, 1
    VariableInput INPUT_BUFFER_PAGE, 0, 0, 0, 1, 0
    VariableInputMessages 0, 0

    ; Expressions, variables, arrays and linked strings.
    NextEntries 0, NextStatement
    ExpressionCore 1
    OperandEvaluation 1, 1, CallFunction
    CommodoreBasic4OperandSplit REVISD
    CommodoreVariableValue 1, 0, 1
    FunctionDispatch
    LogicalOperators 1
    RelationalOperators $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VariableSearch 0, 0, 1, 0, 1, 1
    LetterTest
    SimpleVariableLookup 0, 0, 0, 1, 1, 1, 1, 0
    IntegerConversionBoundary
    IntegerConversion EvaluateExpression, 1
    ArrayLookup 0, 1, 1
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SimpleFunctions 0
    UserFunctions 0
    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, 1
    StringAllocation 1
    LinkedStringGarbageCollection
    StringConcatenation 1
    StringFunctions 0, 0, 0, 1

    ; Memory access, floating point, startup and the BASIC 4 extension.
    AddressConversion 1
    PeekFunction 1, 1, 0, 0
    PokeStatement
    WaitStatement Statements::Wait::StoreMask
.include "Commodore.FloatingPoint.asm"
.include "Commodore.HistoricalNames.asm"
    CharacterReader $58
    CommodoreInitialize 0, 0, 0, 1, 0
    CommodoreMemoryProbe 0, 0, 1, 1, 0, $55
    CommodoreStartProgram 0, 0, 0, 0, Basic4SignOnMessage
    CommodoreStartMessages 0

;; The address after the interpreter's last byte, where the monitor and disk-command extension begin. BASIC 4's `PEEK`
;; has no ROM guard, so nothing refers to it; the extension checks the same address itself.
;; Also: LASTWR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, K4S79, HVK4)
InterpreterEnd:
    CommodoreBasic4Extension REVISD
.assert * = $E000, "BASIC 4 must end at $DFFF."
