;; COMMODORE PET BASIC 1
;;
;; The BASIC 1 interpreter starts at $C000 and ends in the editor ROM at $E1E0, with one more patch at
;; $E7F3-$E7F8. Set <REVISD> to 0 for the original first ROM chip or 1 for the revised chip.
;; The independent choices below default to those chips; changing them may violate this root's fixed layout
;; or the dependencies between its editor patches and shared modules.

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
REVISD = 1                          ;; 1 selects the revised first BASIC 1 chip
.endif
.assert REVISD = 0 || REVISD = 1, "REVISD is 0 or 1."

; Workspace changes are independent so their layout can be reused by another variant.
.ifndef INPUT_BUFFER_PAGE
;; Input buffer page: 0 for page zero or 2 for page two.
;; Also: BUFPAG (M6502, CBM4S79, HV2, HV4, HV4R)
INPUT_BUFFER_PAGE = 0
.endif
.ifndef INPUT_BUFFER_LENGTH
;; Input buffer length in bytes.
;; Also: BUFLEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
INPUT_BUFFER_LENGTH = 80
.endif
.ifndef NULL_COMMAND
;; 1 reserves the `NULL` count byte; BASIC 1 has the code but no `NULL` token.
;; Also: NULCMD (M6502)
NULL_COMMAND = 1
.endif
.ifndef TERMINAL_FIRST
TERMINAL_FIRST = 1                  ;; place terminal storage before general scratch
.endif
.ifndef FULL_STACK_TOP
FULL_STACK_TOP = 1                  ;; use the whole page-one stack
.endif
.ifndef STACK_RESERVE_19
STACK_RESERVE_19 = 1                ;; reserve 19 stack levels
.endif
.ifndef LOCAL_TERMINAL_POSITION
LOCAL_TERMINAL_POSITION = 1         ;; keep BASIC's terminal position
.endif
.ifndef VARIABLE_LIST_IN_LINE_NUMBER
VARIABLE_LIST_IN_LINE_NUMBER = 1    ;; share the variable-list and input-line pointers
.endif
.ifndef CLOCK_IN_PAGE2
CLOCK_IN_PAGE2 = 1                  ;; place the clock in page two
.endif
.ifndef STATUS_IN_PAGE2
STATUS_IN_PAGE2 = 1                 ;; place I/O status in page two
.endif
.ifndef RND_TIMER_9044
RND_TIMER_9044 = 1                  ;; use the early hardware timer for <Functions::Rnd>(0)
.endif
.ifndef ERROR_PADDING5
ERROR_PADDING5 = 1                  ;; retain five unused error-table bytes
.endif

; Interpreter choices retain individual early behaviors, rather than selecting a whole BASIC version.
.ifndef GO_TOKEN
GO_TOKEN = 0                        ;; 1 adds the GO reserved word
.endif
.ifndef BAD_DATA_ERROR
BAD_DATA_ERROR = 1                  ;; 1 names the file-data error BAD DATA instead of FILE DATA
.endif
.ifndef COMMAND_TEST_CHARACTER
COMMAND_TEST_CHARACTER = 0          ;; 1 tests A explicitly after fetching the first command character
.endif
.ifndef COMMAND_RESET_BEFORE_INSERT
COMMAND_RESET_BEFORE_INSERT = 0     ;; 1 clears variables and relinks before inserting a program line
.endif
.ifndef LINK_RETURNS
LINK_RETURNS = 0                    ;; 1 returns from relinking instead of entering the command loop
.endif
.ifndef EARLY_LINE_EDIT
EARLY_LINE_EDIT = 1                 ;; 1 retains the early line-editing entries and unconditional newline
.endif
.ifndef TOKENIZE_SKIP_SPACES
TOKENIZE_SKIP_SPACES = 1            ;; 1 skips spaces while matching reserved words
.endif
.ifndef NEW_CLEAR_CARRY
NEW_CLEAR_CARRY = 0                 ;; 1 clears carry before <EraseProgram> adds two to the program start
.endif
.ifndef RUN_SET_ZERO
RUN_SET_ZERO = 0                    ;; 1 loads zero after <ResetProgramState> positions the text pointer
.endif
.ifndef RESET_STACK_EARLY
RESET_STACK_EARLY = 1-REVISD        ;; 1 stores the return address before moving the stack pointer
.endif
.ifndef RESET_STACK_PADDING
RESET_STACK_PADDING = REVISD        ;; 1 retains the revised reset's extra RTS and unused byte
.endif
.ifndef LIST_GUARD_OFFSET
LIST_GUARD_OFFSET = 0               ;; 1 stops <Statements::List> when a malformed line's byte offset wraps
.endif
.ifndef STATEMENT_FETCH_NOP
STATEMENT_FETCH_NOP = 0             ;; 1 retains the later NOP before the direct-mode branch
.endif
.ifndef EARLY_SEPARATOR_CHECK
EARLY_SEPARATOR_CHECK = 1           ;; 1 checks statement separators before reading the line link
.endif
.ifndef SHORT_END_BRANCH
SHORT_END_BRANCH = 1                ;; 1 branches directly to the end-of-program handler
.endif
.ifndef EARLY_STATEMENT_DISPATCH
EARLY_STATEMENT_DISPATCH = 1        ;; 1 uses the earlier statement-dispatch carry and error paths
.endif
.ifndef STOP_BY_LINE_NUMBER
STOP_BY_LINE_NUMBER = 0             ;; 1 has <Statements::Stop> detect direct mode by the line, not the text page
.endif
.ifndef NULL_INCREMENT_LIMIT
NULL_INCREMENT_LIMIT = 10           ;; first rejected value after incrementing the <Statements::Null> count
.endif
.ifndef RETURN_LOW_FOR_POINTER
RETURN_LOW_FOR_POINTER = 1          ;; 1 has <Statements::Return>'s frame search set the low pointer byte
.endif
.ifndef QUOTE_BRANCH_FIRST
QUOTE_BRANCH_FIRST = 1              ;; 1 tests quotes first while <Statements::Data> and <Statements::Rem> scan
.endif
.ifndef TIME_LONG_ERROR
TIME_LONG_ERROR = 1                 ;; 1 uses the long jump for an invalid TI$ length
.endif

; Output and input choices, including the independent editor-ROM patch call sites.
.ifndef PRINT_CLEAR_SPC_CARRY
PRINT_CLEAR_SPC_CARRY = 0           ;; 1 clears carry before dispatching SPC
.endif
.ifndef PRINT_NULL_PADDING
PRINT_NULL_PADDING = 1              ;; 1 emits the configured NULL characters after a newline
.endif
.ifndef PRINT_TOKEN_SPACING
PRINT_TOKEN_SPACING = 1             ;; 1 distinguishes TAB and SPC by token and uses the early space loop
.endif
.ifndef ALWAYS_SKIP_CHARACTER
ALWAYS_SKIP_CHARACTER = 1           ;; 1 sends cursor-right as a space on every channel
.endif
.ifndef INPUT_ERROR_EDITOR_PATCH
INPUT_ERROR_EDITOR_PATCH = 1        ;; 1 calls the editor's <GET>/<Statements::Read> error-line helper
.endif
.ifndef INPUT_STOP_EDITOR_PATCH
INPUT_STOP_EDITOR_PATCH = 1         ;; 1 calls the editor's stop helper for blank <INPUT>
.endif
.ifndef GET_POINTER_Y_FIRST
GET_POINTER_Y_FIRST = 1             ;; 1 loads the <GET> buffer pointer's high byte first
.endif
.ifndef GET_STRING_EDITOR_PATCH
GET_STRING_EDITOR_PATCH = 1         ;; 1 calls the editor's <GET> string helper
.endif

; Variable, array and string choices.
.ifndef NEXT_COUNTED_STACK
NEXT_COUNTED_STACK = 1              ;; 1 counts through the <Statements::For> frame rather than calculating its offsets
.endif
.ifndef CLOCK_EDITOR_PATCH
CLOCK_EDITOR_PATCH = 1              ;; 1 uses the editor's TI and TI$ variable checks
.endif
.ifndef INTIDX_USE_FRMNUM
INTIDX_USE_FRMNUM = 1               ;; 1 evaluates subscripts with <EvaluateNumber>, 0 with <EvaluateExpression>
.endif
.ifndef POSINT_CHECK_TYPE
POSINT_CHECK_TYPE = 0               ;; 1 checks the numeric type at <FacToNonnegativeInteger>
.endif
.ifndef ARRAY_SAVE_OFFSET_HIGH
ARRAY_SAVE_OFFSET_HIGH = 0          ;; 1 saves the high element-offset byte and fixes the early array bug
.endif
.ifndef USER_FN_LOW_CHECK
USER_FN_LOW_CHECK = 1               ;; 1 tests the argument pointer's low byte for an undefined FN
.endif
.ifndef STRING_CLEAR_FACOV
STRING_CLEAR_FACOV = 0              ;; 1 clears <FACOV> when making a temporary string
.endif
.ifndef GC_FULL_POINTER
GC_FULL_POINTER = 0                 ;; 1 tests both bytes of the selected string descriptor pointer
.endif
.ifndef GC_PATCH_ARRAY_STEP
GC_PATCH_ARRAY_STEP = 1             ;; 1 calls the editor's array-descriptor step
.endif
.ifndef GC_SUBTRACT_OFFSET
GC_SUBTRACT_OFFSET = 1              ;; 1 subtracts three to form the descriptor offset instead of masking
.endif
.ifndef REJECT_ZERO_SLICES
;; 1 rejects zero <Functions::Left> and <Functions::Right> counts as well as a zero <Functions::Mid> start.
REJECT_ZERO_SLICES = 1
.endif
.ifndef PREAM_INDIRECT_RETURN
PREAM_INDIRECT_RETURN = 1           ;; 1 returns from <Functions::SliceArguments> through the writable jump
.endif
.ifndef ASC_SHARED_LEN_JUMP
ASC_SHARED_LEN_JUMP = 1             ;; 1 sends <Functions::Asc> through <Functions::Len>'s numeric conversion jump
.endif

; Memory-access, arithmetic and startup choices.
.ifndef PEEK_PRESERVE_ADDRESS
PEEK_PRESERVE_ADDRESS = 0           ;; 1 restores the previous <POKER> address after <Functions::Peek>
.endif
.ifndef PEEK_GUARD_ROM
PEEK_GUARD_ROM = 1                  ;; 1 returns zero for protected ROM pages
.endif
.ifndef PEEK_PAD_GUARD
PEEK_PAD_GUARD = 0                  ;; 1 emits eight padding bytes in <Functions::Peek>
.endif
.ifndef SHORT_MULTIPLY_ZERO
SHORT_MULTIPLY_ZERO = 1             ;; 1 uses the short multiply-by-zero branch
.endif
.ifndef EARLY_INPUT_EXPONENT_LIMIT
EARLY_INPUT_EXPONENT_LIMIT = 1      ;; 1 retains the earlier decimal exponent limit
.endif
.ifndef PRECISE_OUTPUT_LIMIT
PRECISE_OUTPUT_LIMIT = 1            ;; 1 uses the earlier decimal-output threshold
.endif
.ifndef ZERO_IN_HALF_CONSTANT
ZERO_IN_HALF_CONSTANT = 0           ;; 1 defines `ZeroValue` in <Float::Half> instead of variable lookup
.endif
.ifndef WAIT_EASTER_EGG
WAIT_EASTER_EGG = 0                 ;; 1 includes the hidden WAIT message and <Statements::Wait>'s omitted-mask handler
.endif
.ifndef RANDOM_SEED_TAIL
RANDOM_SEED_TAIL = $59              ;; last byte of the character-reader template's random seed
.endif
.ifndef INIT_MARK_DIRECT
INIT_MARK_DIRECT = 1                ;; 1 marks the current line direct during initialization
.endif
.ifndef INIT_LINE_WIDTH
INIT_LINE_WIDTH = 0                 ;; 1 initializes the line width and comma-zone position
.endif
.ifndef INIT_DELAY_SIZE
INIT_DELAY_SIZE = 1                 ;; 1 sets the descriptor size after clearing the flags
.endif
.ifndef INIT_EARLY_BUFFER_SETUP
INIT_EARLY_BUFFER_SETUP = 1         ;; 1 restores the page-zero buffer's comma and prints a newline
.endif
.ifndef PROBE_LOAD_ZERO
PROBE_LOAD_ZERO = 1                 ;; 1 explicitly loads zero before setting the initial RAM address
.endif
.ifndef PROBE_LOAD_INDEX_ZERO
PROBE_LOAD_INDEX_ZERO = 1           ;; 1 loads zero into Y instead of copying A
.endif
.ifndef PROBE_SAVE_START
PROBE_SAVE_START = 0                ;; 1 saves the program start before probing RAM
.endif
.ifndef PROBE_STOP_AT_SCREEN
PROBE_STOP_AT_SCREEN = 1            ;; 1 compares the probe address with the early screen boundary
.endif
.ifndef PROBE_TEST_BYTE
PROBE_TEST_BYTE = $92               ;; first byte written when testing RAM
.endif
.ifndef START_CARRY_PROGRAM_START
START_CARRY_PROGRAM_START = 1       ;; 1 carries the initial program-start increment into its high byte
.endif
.ifndef START_BANNER_AFTER_FREE
START_BANNER_AFTER_FREE = 1         ;; 1 prints the early sign-on after the free-memory count
.endif

ROMLOC = $C000                      ;; start of the BASIC ROM protected by <Functions::Peek>
BASIC4_OUTPUT_PADDING = 0           ;; omit BASIC 4's output patch space

; Define the shared and platform macros before emitting the interpreter.
.include "Commodore.InterpreterMacros.asm"

; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 1, "BASIC 1 requires TIME = 1."
.assert EXTIO = 1, "BASIC 1 requires EXTIO = 1."
.assert DISKO = 1, "BASIC 1 requires DISKO = 1."

.ifndef RESET_STACK_POINTER
RESET_STACK_POINTER = <(STACK_END-$101-2*RESET_STACK_EARLY) ;; stack pointer after preserving the return address
.endif
.assert INTIDX_USE_FRMNUM = 0 || INTIDX_USE_FRMNUM = 1, "INTIDX_USE_FRMNUM is 0 or 1."

; Dispatch tables, errors, command input and program editing.
.org $C000
    COMMODORE_DISPATCH_TABLES GO_TOKEN, 0, BAD_DATA_ERROR, 0
    MemoryManagement 2*STACK_LEVELS+3*ADDITIONAL_PRECISION+13
    COMMODORE_ERROR_READY 1
    COMMODORE_COMMAND_LOOP COMMAND_TEST_CHARACTER, COMMAND_RESET_BEFORE_INSERT, LINK_RETURNS, 0
    COMMODORE_TERMINAL_INPUT EARLY_LINE_EDIT, 0
    COMMODORE_TOKENIZE 0, TOKENIZE_SKIP_SPACES
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, NEW_CLEAR_CARRY, RUN_SET_ZERO
    ClearStorage 1, 0
    ExecutionReset RESET_STACK_EARLY, RESET_STACK_PADDING, RESET_STACK_POINTER
    ListRange 0, FLNRTS
    ListLines 1, LIST_GUARD_OFFSET, 0, LINPRT, 0, READY
    ListTokens 0, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
    COMMODORE_STATEMENT_FETCH INPUT_BUFFER_PAGE, STATEMENT_FETCH_NOP, EARLY_SEPARATOR_CHECK, SHORT_END_BRANCH, CHRGET
    COMMODORE_STATEMENT_DISPATCH EARLY_STATEMENT_DISPATCH, 0
    RestoreStatement
    StopAndContinue STOP_BY_LINE_NUMBER, 1
    NullStatement NULL_INCREMENT_LIMIT
    ClearStatement CONTRT
    jmp CLEARC
    RunStatement
    GosubAndGoto NEWSTT
    ReturnStatement RETURN_LOW_FOR_POINTER, 0
    StatementScan QUOTE_BRANCH_FIRST, 0
    ConditionalStatements
    OnStatement
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    AssignmentStart
    TIME_STRING_ASSIGNMENT TIME_LONG_ERROR
    StringAssignment 0, 0

; Terminal and channel output, then READ and input.
    COMMODORE_PRINT_CHANNELS
    PrintItems TABER, PRINT_CLEAR_SPC_CARRY, 0, 1
    COMMODORE_LINE_END INPUT_BUFFER_PAGE, LOCAL_TERMINAL_POSITION, 0, PRINT_NULL_PADDING
    COMMODORE_PRINT_SPACING PRINT_TOKEN_SPACING
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    COMMODORE_CHARACTER_OUTPUT ALWAYS_SKIP_CHARACTER, LOCAL_TERMINAL_POSITION, 1, 1
    COMMODORE_INPUT_ERROR INPUT_ERROR_EDITOR_PATCH
    COMMODORE_CHANNEL_INPUT INPUT_BUFFER_PAGE
    COMMODORE_INPUT_STATEMENT 1, 2, 0, INPUT_STOP_EDITOR_PATCH, 0
    VariableInput INPUT_BUFFER_PAGE, 0, GET_POINTER_Y_FIRST, GET_STRING_EDITOR_PATCH, 1, 0
    VariableInputMessages 0, 1

; Expressions, variables, arrays and strings.
    NextEntries NEXT_COUNTED_STACK, NEWSTT
    ExpressionCore 0
    OperandEvaluation 1, 1, ISFUN
    COMMODORE_VARIABLE_VALUE 0, CLOCK_EDITOR_PATCH, 0
    FunctionDispatch
    LogicalOperators 1
    RelationalOperators $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VariableSearch 0, 0, 1, 0, 0, 0
    LetterTest
    SimpleVariableLookup 0, 1-ZERO_IN_HALF_CONSTANT, 0, 1, 1, 0, 0, 0
    IntegerConversionBoundary
.if INTIDX_USE_FRMNUM
    IntegerConversion FRMNUM, POSINT_CHECK_TYPE
.else
    IntegerConversion FRMEVL, POSINT_CHECK_TYPE
.endif
    ArrayLookup 0, 0, ARRAY_SAVE_OFFSET_HIGH
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SimpleFunctions 0
    UserFunctions USER_FN_LOW_CHECK
    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, STRING_CLEAR_FACOV
    StringAllocation 0
    StringGarbageCollection GC_FULL_POINTER, GC_PATCH_ARRAY_STEP, GC_SUBTRACT_OFFSET
    StringConcatenation 0
    StringFunctions REJECT_ZERO_SLICES, PREAM_INDIRECT_RETURN, ASC_SHARED_LEN_JUMP, 0

; Memory access, floating point and cold startup.
    AddressConversion 1
    PeekFunction PEEK_PRESERVE_ADDRESS, 1, PEEK_GUARD_ROM, PEEK_PAD_GUARD
    PokeStatement
.if WAIT_EASTER_EGG
    WaitStatement WaitHiddenMessage
.else
    WaitStatement STORDO
.endif
.include "Commodore.FloatingPoint.asm"
.include "Commodore.HistoricalNames.asm"
    CharacterReader RANDOM_SEED_TAIL
    COMMODORE_INITIALIZE INIT_MARK_DIRECT, INIT_LINE_WIDTH, INIT_DELAY_SIZE, LOCAL_TERMINAL_POSITION, INPUT_BUFFER_PAGE, 0, INIT_EARLY_BUFFER_SETUP
    COMMODORE_MEMORY_PROBE PROBE_LOAD_ZERO, PROBE_LOAD_INDEX_ZERO, PROBE_SAVE_START, 0, PROBE_STOP_AT_SCREEN, PROBE_TEST_BYTE
.if START_BANNER_AFTER_FREE
    COMMODORE_START_PROGRAM 1, START_CARRY_PROGRAM_START, 1, 1, 0
.else
    COMMODORE_START_PROGRAM 1, START_CARRY_PROGRAM_START, 1, 0, FREMES
.endif
    COMMODORE_START_MESSAGES START_BANNER_AFTER_FREE
    COMMODORE_BASIC1_EDITOR_PATCHES
.assert * = $E1E1, "BASIC 1's main editor spill must end at $E1E0."

.org $E7F3
    COMMODORE_BASIC1_ARRAY_PATCH
.assert * = $E7F9, "BASIC 1's array patch must end at $E7F8."
