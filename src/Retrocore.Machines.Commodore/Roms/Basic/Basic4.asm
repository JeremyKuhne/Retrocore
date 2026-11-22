;; COMMODORE PET BASIC 4
;;
;; The BASIC 4 interpreter and its monitor and disk-command extension occupy $B000-$DFFF.
;; Set <REVISD> to 0 for the original $B000 ROM chip or 1 for the revised chip.

.cpu Mos6502

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
SHORT_FMUL_ZERO = 0                 ;; use the later multiply-by-zero branch
EARLY_FIN_LIMIT = 0                 ;; use the later decimal exponent limit
PRECISE_FOUT_LIMIT = 0              ;; use the later decimal-output threshold
ZERO_AT_FHALF = 1                   ;; define <ZERO> within the half constant
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
    MEMORY_MANAGEMENT $3E
    COMMODORE_ERROR_READY 0
    COMMODORE_COMMAND_LOOP 1, 1, 1, 1
    COMMODORE_TERMINAL_INPUT 0, 1
    COMMODORE_TOKENIZE 1, 0
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

; Program control, statement dispatch and assignment.
    PROGRAM_RESET 0, 0, 0, 1, 1
    CLEAR_STATEMENT STKRTS
    CLEAR_STORAGE 1, 1
    EXECUTION_RESET 0, 0, $FA
    LIST_RANGE 0, FLNRTS
    LIST_LINES 1, 1, 0, LINPRT, 0, READY
    LIST_TOKENS 1, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
.if REVISD
    COMMODORE_STATEMENT_FETCH BUFPAG, 0, 0, 0, GONEGT
.else
    COMMODORE_STATEMENT_FETCH BUFPAG, 0, 0, 0, CHRGET
.endif
    COMMODORE_STATEMENT_DISPATCH 0, 1
    RESTORE_DATA
    STOP_AND_CONTINUE 1, 0
    RUN_STATEMENT 0
    GOSUB_AND_GOTO NEWSTT
    RETURN_STATEMENT 0, 0
    STATEMENT_SCAN 0, 0
    CONDITIONAL_STATEMENTS
    ON_STATEMENT
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    ASSIGNMENT_START
    TIME_STRING_ASSIGNMENT 0
    STRING_ASSIGNMENT 1, 1
    STRING_LINK_ADJUST REVISD

; Terminal and channel output, then READ and input.
    COMMODORE_PRINT_CHANNELS
    PRINT_CORE TABER, 1, 0, 1
    COMMODORE_LINE_END BUFPAG, 0, 1, 0
    COMMODORE_PRINT_SPACING 0
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    COMMODORE_CHARACTER_OUTPUT 0, 0, 0, 0
    COMMODORE_INPUT_ERROR 0
    COMMODORE_CHANNEL_INPUT BUFPAG
    COMMODORE_INPUT_STATEMENT 0, 3, REVISD, 0, 1
    VARIABLE_INPUT BUFPAG, 0, 0, 0, 1, 0
    VARIABLE_INPUT_MESSAGES 0, 0

; Expressions, variables, arrays and linked strings.
    NEXT_ENTRIES 0, NEWSTT
    EXPRESSION_CORE 1
    OPERAND_EVALUATION 1, 1, ISFUN
    COMMODORE_BASIC4_OPERAND_SPLIT REVISD
    COMMODORE_VARIABLE_VALUE 1, 0, 1
    FUNCTION_DISPATCH
    LOGICAL_OPERATORS 1
    RELATIONAL_OPERATORS $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VARIABLE_NAME 0, 0, 1, 0, 1, 1
    LETTER_TEST
    SIMPLE_VARIABLE_LOOKUP 0, 0, 0, 1, 1, 1, 1, 0
    INTEGER_CONVERSION_BOUNDARY
    INTEGER_CONVERSION FRMEVL, 1
    ARRAY_LOOKUP 0, 1, 1
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SIMPLE_FUNCTIONS 0
    USER_FUNCTIONS 0
    STRING_FROM_NUMBER
    STRING_STORAGE BUFPAG, 1
    STRING_ALLOCATION 1
    LINKED_STRING_GARBAGE_COLLECTION
    STRING_CONCATENATION 1
    STRING_FUNCTIONS 0, 0, 0, 1

; Memory access, floating point, startup and the BASIC 4 extension.
    MEMORY_ACCESS_ADDRESS 1
    MEMORY_ACCESS_PEEK 1, 1, 0, 0
    MEMORY_ACCESS_POKE
    MEMORY_ACCESS_WAIT STORDO
.include "Commodore.FloatingPoint.asm"
.include "Commodore.FloatAliases.asm"
.include "Commodore.InterpreterAliases.asm"
    CHARACTER_READER $58
    COMMODORE_INITIALIZE 0, 0, 0, 0, BUFPAG, 1, 0
    COMMODORE_MEMORY_PROBE 0, 0, 1, 1, 0, $55
    COMMODORE_START_PROGRAM 0, 0, 0, 0, SIGNON
    COMMODORE_START_MESSAGES 0
LASTWR:
    COMMODORE_BASIC4_EXTENSION REVISD
.assert * = $E000, "BASIC 4 must end at $DFFF."
