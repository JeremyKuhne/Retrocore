;; COMMODORE PET BASIC 2
;;
;; The BASIC 2 interpreter starts at $C000 and ends in the first part of the editor ROM at $E1DD.
;; Its shared Microsoft and Commodore modules are emitted in ROM address order.

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

ROMLOC = $C000                      ;; start of the BASIC 2 ROM
SHORT_MULTIPLY_ZERO = 0             ;; use the later multiply-by-zero branch
EARLY_INPUT_EXPONENT_LIMIT = 0      ;; use the later decimal exponent limit
PRECISE_OUTPUT_LIMIT = 0            ;; use the later decimal-output threshold
ZERO_IN_HALF_CONSTANT = 1           ;; define <ZeroValue> within the half constant
WAIT_EASTER_EGG = 1                 ;; include BASIC 2's hidden WAIT message
BASIC4_OUTPUT_PADDING = 0           ;; omit BASIC 4's output patch space

; Define the shared and platform macros before emitting the interpreter.
.include "Commodore.InterpreterMacros.asm"

; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 1, "BASIC 2 requires TIME = 1."
.assert EXTIO = 1, "BASIC 2 requires EXTIO = 1."
.assert DISKO = 1, "BASIC 2 requires DISKO = 1."

; Dispatch tables, errors, command input and program editing.
.org $C000
    CommodoreDispatchTables 1, 0, 0, 0
    MemoryManagement $3E
    CommodoreErrorReady 1
    CommodoreCommandLoop 1, 1, 1, 0
    CommodoreTerminalInput 0, 0
    CommodoreTokenize 0, 0
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, 1, 1
    ClearStatement STKRTS
    ClearStorage 1, 0
    ExecutionReset 0, 0, $FA
    ListRange 0, FLNRTS
    ListLines 1, 1, 0, LINPRT, 0, READY
    ListTokens 0, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
    CommodoreStatementFetch INPUT_BUFFER_PAGE, 1, 0, 0, CHRGET
    CommodoreStatementDispatch 0, 0
    RestoreStatement
    StopAndContinue 1, 1
    RunStatement
    GosubAndGoto NEWSTT
    ReturnStatement 0, 0
    StatementScan 0, 0
    ConditionalStatements
    OnStatement
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    AssignmentStart
    TIME_STRING_ASSIGNMENT 0
    StringAssignment 0, 0

; Terminal and channel output, then READ and input.
    CommodorePrintChannels
    PrintItems TABER, 1, 0, 1
    CommodoreLineEnd INPUT_BUFFER_PAGE, 0, 0, 0
    CommodorePrintSpacing 0
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    CommodoreCharacterOutput 0, 0, 1, 1
    CommodoreInputError 0
    CommodoreChannelInput INPUT_BUFFER_PAGE
    CommodoreInputStatement 1, 2, 0, 0, 0
    VariableInput INPUT_BUFFER_PAGE, 0, 0, 0, 1, 0
    VariableInputMessages 0, 1

; Expressions, variables, arrays and strings.
    NextEntries 0, NEWSTT
    ExpressionCore 0
    OperandEvaluation 1, 1, ISFUN
    CommodoreVariableValue 0, 0, 0
    FunctionDispatch
    LogicalOperators 1
    RelationalOperators $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VariableSearch 0, 0, 1, 0, 0, 0
    LetterTest
    SimpleVariableLookup 0, 0, 0, 1, 1, 0, 0, 0
    IntegerConversionBoundary
    IntegerConversion FRMEVL, 1
    ArrayLookup 0, 0, 1
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SimpleFunctions 0
    UserFunctions 0
    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, 1
    StringAllocation 0
    StringGarbageCollection 1, 0, 0
    StringConcatenation 0
    StringFunctions 0, 0, 0, 0

; Memory access, floating point and cold startup.
    AddressConversion 1
    PeekFunction 1, 1, 0, 1
    PokeStatement
    WaitStatement WaitHiddenMessage
.include "Commodore.FloatingPoint.asm"
.include "Commodore.HistoricalNames.asm"
    CharacterReader $58
    CommodoreInitialize 0, 1, 0, 0, INPUT_BUFFER_PAGE, 0, 0
    CommodoreMemoryProbe 0, 0, 1, 0, 0, $55
    CommodoreStartProgram 1, 0, 1, 0, FREMES
    CommodoreStartMessages 0
LASTWR:

.assert * = $E1DE, "BASIC 2 must end at $E1DD in the editor ROM."
