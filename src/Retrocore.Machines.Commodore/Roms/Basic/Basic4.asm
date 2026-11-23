;; COMMODORE PET BASIC 4
;;
;; The BASIC 4 interpreter and its monitor and disk-command extension occupy $B000-$DFFF.
;; Set <REVISD> to 0 for the original $B000 ROM chip or 1 for the revised chip.

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
REVISD = 1                          ;; 1 selects the revised $B000 BASIC 4 chip
.endif
.assert REVISD = 0 || REVISD = 1, "REVISD is 0 or 1."

.ifndef DISK_STATUS_STRING
DISK_STATUS_STRING = 1              ;; reserve the disk-status string descriptor
.endif
.ifndef LINE_WIDTH_STORAGE
LINE_WIDTH_STORAGE = 0              ;; omit the later interpreter's line-width storage
.endif
.ifndef EXTENDED_DISK_VECTORS
EXTENDED_DISK_VECTORS = 1           ;; include the disk-command vectors
.endif

ROMLOC = $B000                      ;; start of the BASIC 4 ROM
SHORT_MULTIPLY_ZERO = 0             ;; use the later multiply-by-zero branch
EARLY_INPUT_EXPONENT_LIMIT = 0      ;; use the later decimal exponent limit
PRECISE_OUTPUT_LIMIT = 0            ;; use the later decimal-output threshold
ZERO_IN_HALF_CONSTANT = 1           ;; define <ZeroValue> within the half constant
WAIT_EASTER_EGG = 0                 ;; omit BASIC 2's hidden WAIT message
BASIC4_OUTPUT_PADDING = 1           ;; include BASIC 4's output patch space

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
    COMMODORE_DISPATCH_TABLES 1, 1, 0, 1
    MemoryManagement $3E
    COMMODORE_ERROR_READY 0
    COMMODORE_COMMAND_LOOP 1, 1, 1, 1
    COMMODORE_TERMINAL_INPUT 0, 1
    COMMODORE_TOKENIZE 1, 0
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, 1, 1
    ClearStatement STKRTS
    ClearStorage 1, 1
    ExecutionReset 0, 0, $FA
    ListRange 0, FLNRTS
    ListLines 1, 1, 0, LINPRT, 0, READY
    ListTokens 1, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
.if REVISD
    COMMODORE_STATEMENT_FETCH INPUT_BUFFER_PAGE, 0, 0, 0, GONEGT
.else
    COMMODORE_STATEMENT_FETCH INPUT_BUFFER_PAGE, 0, 0, 0, CHRGET
.endif
    COMMODORE_STATEMENT_DISPATCH 0, 1
    RestoreStatement
    StopAndContinue 1, 0
    RunStatement
    GosubAndGoto NEWSTT
    ReturnStatement 0, 0
    StatementScan 0, 0
    ConditionalStatements
    OnStatement
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    ASSIGNMENT_START
    TIME_STRING_ASSIGNMENT 0
    STRING_ASSIGNMENT 1, 1
    STRING_LINK_ADJUST REVISD

; Terminal and channel output, then READ and input.
    COMMODORE_PRINT_CHANNELS
    PrintItems TABER, 1, 0, 1
    COMMODORE_LINE_END INPUT_BUFFER_PAGE, 0, 1, 0
    COMMODORE_PRINT_SPACING 0
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    COMMODORE_CHARACTER_OUTPUT 0, 0, 0, 0
    COMMODORE_INPUT_ERROR 0
    COMMODORE_CHANNEL_INPUT INPUT_BUFFER_PAGE
    COMMODORE_INPUT_STATEMENT 0, 3, REVISD, 0, 1
    VARIABLE_INPUT INPUT_BUFFER_PAGE, 0, 0, 0, 1, 0
    VARIABLE_INPUT_MESSAGES 0, 0

; Expressions, variables, arrays and linked strings.
    NextEntries 0, NEWSTT
    EXPRESSION_CORE 1
    OPERAND_EVALUATION 1, 1, ISFUN
    COMMODORE_BASIC4_OPERAND_SPLIT REVISD
    COMMODORE_VARIABLE_VALUE 1, 0, 1
    FUNCTION_DISPATCH
    LOGICAL_OPERATORS 1
    RelationalOperators $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VARIABLE_NAME 0, 0, 1, 0, 1, 1
    LetterTest
    SIMPLE_VARIABLE_LOOKUP 0, 0, 0, 1, 1, 1, 1, 0
    IntegerConversionBoundary
    IntegerConversion FRMEVL, 1
    ARRAY_LOOKUP 0, 1, 1
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SimpleFunctions 0
    UserFunctions 0
    STRING_FROM_NUMBER
    STRING_STORAGE INPUT_BUFFER_PAGE, 1
    STRING_ALLOCATION 1
    LINKED_STRING_GARBAGE_COLLECTION
    STRING_CONCATENATION 1
    STRING_FUNCTIONS 0, 0, 0, 1

; Memory access, floating point, startup and the BASIC 4 extension.
    AddressConversion 1
    PeekFunction 1, 1, 0, 0
    PokeStatement
    WaitStatement STORDO
.include "Commodore.FloatingPoint.asm"
.include "Commodore.HistoricalNames.asm"
.include "Commodore.InterpreterAliases.asm"
    CharacterReader $58
    COMMODORE_INITIALIZE 0, 0, 0, 0, INPUT_BUFFER_PAGE, 1, 0
    COMMODORE_MEMORY_PROBE 0, 0, 1, 1, 0, $55
    COMMODORE_START_PROGRAM 0, 0, 0, 0, SIGNON
    COMMODORE_START_MESSAGES 0
LASTWR:
    COMMODORE_BASIC4_EXTENSION REVISD
.assert * = $E000, "BASIC 4 must end at $DFFF."
