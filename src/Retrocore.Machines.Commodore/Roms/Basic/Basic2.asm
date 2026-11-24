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

ROMLOC = $C000                      ;; start of the BASIC 2 ROM
SHORT_FMUL_ZERO = 0                 ;; use the later multiply-by-zero branch
EARLY_FIN_LIMIT = 0                 ;; use the later decimal exponent limit
PRECISE_FOUT_LIMIT = 0              ;; use the later decimal-output threshold
ZERO_AT_FHALF = 1                   ;; define <ZERO> within the half constant
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
    COMMODORE_DISPATCH_TABLES 1, 0, 0, 0
    MEMORY_MANAGEMENT $3E
    COMMODORE_ERROR_READY 1
    COMMODORE_COMMAND_LOOP 1, 1, 1, 0
    COMMODORE_TERMINAL_INPUT 0, 0
    COMMODORE_TOKENIZE 0, 0
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

; Program control, statement dispatch and assignment.
    PROGRAM_RESET 0, 0, 0, 1, 1
    CLEAR_STATEMENT STKRTS
    CLEAR_STORAGE 1, 0
    EXECUTION_RESET 0, 0, $FA
    LIST_RANGE 0, FLNRTS
    LIST_LINES 1, 1, 0, LINPRT, 0, READY
    LIST_TOKENS 0, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
    COMMODORE_STATEMENT_FETCH INPUT_BUFFER_PAGE, 1, 0, 0, CHRGET
    COMMODORE_STATEMENT_DISPATCH 0, 0
    RESTORE_DATA
    STOP_AND_CONTINUE 1, 1
    RUN_STATEMENT 0
    GOSUB_AND_GOTO NEWSTT
    RETURN_STATEMENT 0, 0
    STATEMENT_SCAN 0, 0
    CONDITIONAL_STATEMENTS
    ON_STATEMENT
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    ASSIGNMENT_START
    TIME_STRING_ASSIGNMENT 0
    STRING_ASSIGNMENT 0, 0

; Terminal and channel output, then READ and input.
    COMMODORE_PRINT_CHANNELS
    PRINT_CORE TABER, 1, 0, 1
    COMMODORE_LINE_END INPUT_BUFFER_PAGE, 0, 0, 0
    COMMODORE_PRINT_SPACING 0
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    COMMODORE_CHARACTER_OUTPUT 0, 0, 1, 1
    COMMODORE_INPUT_ERROR 0
    COMMODORE_CHANNEL_INPUT INPUT_BUFFER_PAGE
    COMMODORE_INPUT_STATEMENT 1, 2, 0, 0, 0
    VARIABLE_INPUT INPUT_BUFFER_PAGE, 0, 0, 0, 1, 0
    VARIABLE_INPUT_MESSAGES 0, 1

; Expressions, variables, arrays and strings.
    NEXT_ENTRIES 0, NEWSTT
    EXPRESSION_CORE 0
    OPERAND_EVALUATION 1, 1, ISFUN
    COMMODORE_VARIABLE_VALUE 0, 0, 0
    FUNCTION_DISPATCH
    LOGICAL_OPERATORS 1
    RELATIONAL_OPERATORS $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VARIABLE_NAME 0, 0, 1, 0, 0, 0
    LETTER_TEST
    SIMPLE_VARIABLE_LOOKUP 0, 0, 0, 1, 1, 0, 0, 0
    INTEGER_CONVERSION_BOUNDARY
    INTEGER_CONVERSION FRMEVL, 1
    ARRAY_LOOKUP 0, 0, 1
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SIMPLE_FUNCTIONS 0
    USER_FUNCTIONS 0
    STRING_FROM_NUMBER
    STRING_STORAGE INPUT_BUFFER_PAGE, 1
    STRING_ALLOCATION 0
    STRING_GARBAGE_COLLECTION 1, 0, 0
    STRING_CONCATENATION 0
    STRING_FUNCTIONS 0, 0, 0, 0

; Memory access, floating point and cold startup.
    MEMORY_ACCESS_ADDRESS 1
    MEMORY_ACCESS_PEEK 1, 1, 0, 1
    MEMORY_ACCESS_POKE
    MEMORY_ACCESS_WAIT ZSTORD
.include "Commodore.FloatingPoint.asm"
.include "Commodore.FloatAliases.asm"
.include "Commodore.InterpreterAliases.asm"
    CHARACTER_READER $58
    COMMODORE_INITIALIZE 0, 1, 0, 0, INPUT_BUFFER_PAGE, 0, 0
    COMMODORE_MEMORY_PROBE 0, 0, 1, 0, 0, $55
    COMMODORE_START_PROGRAM 1, 0, 1, 0, FREMES
    COMMODORE_START_MESSAGES 0
LASTWR:

.assert * = $E1DE, "BASIC 2 must end at $E1DD in the editor ROM."
