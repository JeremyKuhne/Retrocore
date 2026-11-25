; retrocore: style=strict
;; COMMODORE PET BASIC 1
;;
;; The BASIC 1 interpreter starts at $C000 and ends in the editor ROM at $E1E0, with one more patch at
;; $E7F3-$E7F8. Set <REVISD> to 0 for the original first ROM chip or 1 for the revised chip.
;; The independent choices below default to those chips; changing them may violate this root's fixed layout
;; or the dependencies between its editor patches and shared modules.
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

; BASIC 1's own switches the conversion renamed, likewise.
.assert .not .defined(INTIDX_USE_FRMNUM), "Predefine SUBSCRIPT_CHECKS_NUMERIC, not INTIDX_USE_FRMNUM."
.assert .not .defined(POSINT_CHECK_TYPE), "Predefine POSITIVE_INTEGER_CHECKS_TYPE, not POSINT_CHECK_TYPE."
.assert .not .defined(STRING_CLEAR_FACOV), "Predefine STRING_CLEARS_FAC_EXTENSION, not STRING_CLEAR_FACOV."
.assert .not .defined(GC_FULL_POINTER), "Predefine COLLECTOR_FULL_POINTER, not GC_FULL_POINTER."
.assert .not .defined(GC_PATCH_ARRAY_STEP), "Predefine COLLECTOR_PATCH_ARRAY_STEP, not GC_PATCH_ARRAY_STEP."
.assert .not .defined(GC_SUBTRACT_OFFSET), "Predefine COLLECTOR_SUBTRACT_OFFSET, not GC_SUBTRACT_OFFSET."
.assert .not .defined(PREAM_INDIRECT_RETURN), "Predefine STRING_PREAMBLE_INDIRECT_RETURN, not PREAM_INDIRECT_RETURN."
.assert .not .defined(PROBE_LOAD_INDEX_ZERO), "Predefine PROBE_ZERO_INDEX, not PROBE_LOAD_INDEX_ZERO."

.ifndef REVISD
;; 1 selects the revised first BASIC 1 chip.
REVISD = 1
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
;; Place terminal storage before general scratch.
TERMINAL_FIRST = 1
.endif
.ifndef FULL_STACK_TOP
;; Use the whole page-one stack.
FULL_STACK_TOP = 1
.endif
.ifndef STACK_RESERVE_19
;; Reserve 19 stack levels.
STACK_RESERVE_19 = 1
.endif
.ifndef LOCAL_TERMINAL_POSITION
;; Keep BASIC's terminal position.
LOCAL_TERMINAL_POSITION = 1
.endif
.ifndef VARIABLE_LIST_IN_LINE_NUMBER
;; Share the variable-list and input-line pointers.
VARIABLE_LIST_IN_LINE_NUMBER = 1
.endif
.ifndef CLOCK_IN_PAGE2
;; Place the clock in page two.
CLOCK_IN_PAGE2 = 1
.endif
.ifndef STATUS_IN_PAGE2
;; Place I/O status in page two.
STATUS_IN_PAGE2 = 1
.endif
.ifndef RND_TIMER_9044
;; Use the early hardware timer for <Functions::Rnd>(0).
RND_TIMER_9044 = 1
.endif
.ifndef ERROR_PADDING5
;; Retain five unused error-table bytes.
ERROR_PADDING5 = 1
.endif

; Interpreter choices retain individual early behaviors, rather than selecting a whole BASIC version.
.ifndef GO_TOKEN
;; 1 adds the GO reserved word.
GO_TOKEN = 0
.endif
.ifndef BAD_DATA_ERROR
;; 1 names the file-data error BAD DATA instead of FILE DATA.
BAD_DATA_ERROR = 1
.endif
.ifndef COMMAND_TEST_CHARACTER
;; 1 tests A explicitly after fetching the first command character.
COMMAND_TEST_CHARACTER = 0
.endif
.ifndef COMMAND_RESET_BEFORE_INSERT
;; 1 clears variables and relinks before inserting a program line.
COMMAND_RESET_BEFORE_INSERT = 0
.endif
.ifndef LINK_RETURNS
;; 1 returns from relinking instead of entering the command loop.
LINK_RETURNS = 0
.endif
.ifndef EARLY_LINE_EDIT
;; 1 retains the early line-editing entries and unconditional newline.
EARLY_LINE_EDIT = 1
.endif
.ifndef TOKENIZE_SKIP_SPACES
;; 1 skips spaces while matching reserved words.
TOKENIZE_SKIP_SPACES = 1
.endif
.ifndef NEW_CLEAR_CARRY
;; 1 clears carry before <EraseProgram> adds two to the program start.
NEW_CLEAR_CARRY = 0
.endif
.ifndef RUN_SET_ZERO
;; 1 loads zero after <ResetProgramState> positions the text pointer.
RUN_SET_ZERO = 0
.endif
.ifndef RESET_STACK_EARLY
;; 1 stores the return address before moving the stack pointer.
RESET_STACK_EARLY = 1-REVISD
.endif
.ifndef RESET_STACK_PADDING
;; 1 retains the revised reset's extra RTS and unused byte.
RESET_STACK_PADDING = REVISD
.endif
.ifndef LIST_GUARD_OFFSET
;; 1 stops <Statements::List> when a malformed line's byte offset wraps.
LIST_GUARD_OFFSET = 0
.endif
.ifndef STATEMENT_FETCH_NOP
;; 1 retains the later NOP before the direct-mode branch.
STATEMENT_FETCH_NOP = 0
.endif
.ifndef EARLY_SEPARATOR_CHECK
;; 1 checks statement separators before reading the line link.
EARLY_SEPARATOR_CHECK = 1
.endif
.ifndef SHORT_END_BRANCH
;; 1 branches directly to the end-of-program handler.
SHORT_END_BRANCH = 1
.endif
.ifndef EARLY_STATEMENT_DISPATCH
;; 1 uses the earlier statement-dispatch carry and error paths.
EARLY_STATEMENT_DISPATCH = 1
.endif
.ifndef STOP_BY_LINE_NUMBER
;; 1 has <Statements::Stop> detect direct mode by the line, not the text page.
STOP_BY_LINE_NUMBER = 0
.endif
.ifndef NULL_INCREMENT_LIMIT
;; First rejected value after incrementing the <Statements::Null> count.
NULL_INCREMENT_LIMIT = 10
.endif
.ifndef RETURN_LOW_FOR_POINTER
;; 1 has <Statements::Return>'s frame search set the low pointer byte.
RETURN_LOW_FOR_POINTER = 1
.endif
.ifndef QUOTE_BRANCH_FIRST
;; 1 tests quotes first while <Statements::Data> and <Statements::Rem> scan.
QUOTE_BRANCH_FIRST = 1
.endif
.ifndef TIME_LONG_ERROR
;; 1 uses the long jump for an invalid TI$ length.
TIME_LONG_ERROR = 1
.endif

; Output and input choices, including the independent editor-ROM patch call sites.
.ifndef PRINT_CLEAR_SPC_CARRY
;; 1 clears carry before dispatching SPC.
PRINT_CLEAR_SPC_CARRY = 0
.endif
.ifndef PRINT_NULL_PADDING
;; 1 emits the configured NULL characters after a newline.
PRINT_NULL_PADDING = 1
.endif
.ifndef PRINT_TOKEN_SPACING
;; 1 distinguishes TAB and SPC by token and uses the early space loop.
PRINT_TOKEN_SPACING = 1
.endif
.ifndef ALWAYS_SKIP_CHARACTER
;; 1 sends cursor-right as a space on every channel.
ALWAYS_SKIP_CHARACTER = 1
.endif
.ifndef INPUT_ERROR_EDITOR_PATCH
;; 1 calls the editor's <Statements::Get>/<Statements::Read> error-line helper.
INPUT_ERROR_EDITOR_PATCH = 1
.endif
.ifndef INPUT_STOP_EDITOR_PATCH
;; 1 calls the editor's stop helper for blank <Statements::Input>.
INPUT_STOP_EDITOR_PATCH = 1
.endif
.ifndef GET_POINTER_Y_FIRST
;; 1 loads the <Statements::Get> buffer pointer's high byte first.
GET_POINTER_Y_FIRST = 1
.endif
.ifndef GET_STRING_EDITOR_PATCH
;; 1 calls the editor's <Statements::Get> string helper.
GET_STRING_EDITOR_PATCH = 1
.endif

; Variable, array and string choices.
.ifndef NEXT_COUNTED_STACK
;; 1 counts through the <Statements::For> frame rather than calculating its offsets.
NEXT_COUNTED_STACK = 1
.endif
.ifndef CLOCK_EDITOR_PATCH
;; 1 uses the editor's TI and TI$ variable checks.
CLOCK_EDITOR_PATCH = 1
.endif
.ifndef SUBSCRIPT_CHECKS_NUMERIC
;; 1 evaluates subscripts with <EvaluateNumber>, 0 with <EvaluateExpression>.
SUBSCRIPT_CHECKS_NUMERIC = 1
.endif
.ifndef POSITIVE_INTEGER_CHECKS_TYPE
;; 1 checks the numeric type at <FacToNonnegativeInteger>.
POSITIVE_INTEGER_CHECKS_TYPE = 0
.endif
.ifndef ARRAY_SAVE_OFFSET_HIGH
;; 1 saves the high element-offset byte and fixes the early array bug.
ARRAY_SAVE_OFFSET_HIGH = 0
.endif
.ifndef USER_FN_LOW_CHECK
;; 1 tests the argument pointer's low byte for an undefined FN.
USER_FN_LOW_CHECK = 1
.endif
.ifndef STRING_CLEARS_FAC_EXTENSION
;; 1 clears <FacExtension> when making a temporary string.
STRING_CLEARS_FAC_EXTENSION = 0
.endif
.ifndef COLLECTOR_FULL_POINTER
;; 1 tests both bytes of the selected string descriptor pointer.
COLLECTOR_FULL_POINTER = 0
.endif
.ifndef COLLECTOR_PATCH_ARRAY_STEP
;; 1 calls the editor's array-descriptor step.
COLLECTOR_PATCH_ARRAY_STEP = 1
.endif
.ifndef COLLECTOR_SUBTRACT_OFFSET
;; 1 subtracts three to form the descriptor offset instead of masking.
COLLECTOR_SUBTRACT_OFFSET = 1
.endif
.ifndef REJECT_ZERO_SLICES
;; 1 rejects zero <Functions::Left> and <Functions::Right> counts as well as a zero <Functions::Mid> start.
REJECT_ZERO_SLICES = 1
.endif
.ifndef STRING_PREAMBLE_INDIRECT_RETURN
;; 1 returns from <Functions::SliceArguments> through the writable jump.
STRING_PREAMBLE_INDIRECT_RETURN = 1
.endif
.ifndef ASC_SHARED_LEN_JUMP
;; 1 sends <Functions::Asc> through <Functions::Len>'s numeric conversion jump.
ASC_SHARED_LEN_JUMP = 1
.endif

; Memory-access, arithmetic and startup choices.
.ifndef PEEK_PRESERVE_ADDRESS
;; 1 restores the previous <PokeAddress> address after <Functions::Peek>.
PEEK_PRESERVE_ADDRESS = 0
.endif
.ifndef PEEK_GUARD_ROM
;; 1 returns zero for protected ROM pages.
PEEK_GUARD_ROM = 1
.endif
.ifndef PEEK_PAD_GUARD
;; 1 emits eight padding bytes in <Functions::Peek>.
PEEK_PAD_GUARD = 0
.endif
.ifndef SHORT_MULTIPLY_ZERO
;; 1 uses the short multiply-by-zero branch.
SHORT_MULTIPLY_ZERO = 1
.endif
.ifndef EARLY_INPUT_EXPONENT_LIMIT
;; 1 retains the earlier decimal exponent limit.
EARLY_INPUT_EXPONENT_LIMIT = 1
.endif
.ifndef PRECISE_OUTPUT_LIMIT
;; 1 uses the earlier decimal-output threshold.
PRECISE_OUTPUT_LIMIT = 1
.endif
.ifndef ZERO_IN_HALF_CONSTANT
;; 1 defines `ZeroValue` in <Float::Half> instead of variable lookup.
ZERO_IN_HALF_CONSTANT = 0
.endif
.ifndef WAIT_EASTER_EGG
;; 1 includes the hidden WAIT message and <Statements::Wait>'s omitted-mask handler.
WAIT_EASTER_EGG = 0
.endif
.ifndef RANDOM_SEED_TAIL
;; Last byte of the character-reader template's random seed.
RANDOM_SEED_TAIL = $59
.endif
.ifndef INIT_MARK_DIRECT
;; 1 marks the current line direct during initialization.
INIT_MARK_DIRECT = 1
.endif
.ifndef INIT_LINE_WIDTH
;; 1 initializes the line width and comma-zone position.
INIT_LINE_WIDTH = 0
.endif
.ifndef INIT_DELAY_SIZE
;; 1 sets the descriptor size after clearing the flags.
INIT_DELAY_SIZE = 1
.endif
.ifndef INIT_EARLY_BUFFER_SETUP
;; 1 restores the page-zero buffer's comma and prints a newline.
INIT_EARLY_BUFFER_SETUP = 1
.endif
.ifndef PROBE_LOAD_ZERO
;; 1 explicitly loads zero before setting the initial RAM address.
PROBE_LOAD_ZERO = 1
.endif
.ifndef PROBE_ZERO_INDEX
;; 1 loads zero into Y instead of copying A.
PROBE_ZERO_INDEX = 1
.endif
.ifndef PROBE_SAVE_START
;; 1 saves the program start before probing RAM.
PROBE_SAVE_START = 0
.endif
.ifndef PROBE_STOP_AT_SCREEN
;; 1 compares the probe address with the early screen boundary.
PROBE_STOP_AT_SCREEN = 1
.endif
.ifndef PROBE_TEST_BYTE
;; First byte written when testing RAM.
PROBE_TEST_BYTE = $92
.endif
.ifndef START_CARRY_PROGRAM_START
;; 1 carries the initial program-start increment into its high byte.
START_CARRY_PROGRAM_START = 1
.endif
.ifndef START_BANNER_AFTER_FREE
;; 1 prints the early sign-on after the free-memory count.
START_BANNER_AFTER_FREE = 1
.endif

;; Start of the BASIC ROM protected by <Functions::Peek>.
;; Also: ROMLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ROM_ORIGIN = $C000

;; Omit BASIC 4's output patch space.
BASIC4_OUTPUT_PADDING = 0

; Define the shared and platform macros before emitting the interpreter.
.include "Commodore.InterpreterMacros.asm"

; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 1, "BASIC 1 requires TIME = 1."
.assert EXTIO = 1, "BASIC 1 requires EXTIO = 1."
.assert DISKO = 1, "BASIC 1 requires DISKO = 1."

.ifndef RESET_STACK_POINTER
;; Stack pointer after preserving the return address.
RESET_STACK_POINTER = <(STACK_END-$101-2*RESET_STACK_EARLY)
.endif
.assert SUBSCRIPT_CHECKS_NUMERIC = 0 || SUBSCRIPT_CHECKS_NUMERIC = 1, "SUBSCRIPT_CHECKS_NUMERIC is 0 or 1."

; Dispatch tables, errors, command input and program editing.
.org $C000
    CommodoreDispatchTables GO_TOKEN, 0, BAD_DATA_ERROR, 0
    MemoryManagement 2*STACK_LEVELS+3*ADDITIONAL_PRECISION+13
    CommodoreErrorReady 1
    CommodoreCommandLoop COMMAND_TEST_CHARACTER, COMMAND_RESET_BEFORE_INSERT, LINK_RETURNS, 0
    CommodoreTerminalInput EARLY_LINE_EDIT, 0
    CommodoreTokenize 0, TOKENIZE_SKIP_SPACES
.include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"

    ; Program control, statement dispatch and assignment.
    ProgramReset 0, 0, NEW_CLEAR_CARRY, RUN_SET_ZERO
    ClearStorage 1, 0
    ExecutionReset RESET_STACK_EARLY, RESET_STACK_PADDING, RESET_STACK_POINTER
    ListRange 0, FindLine::Done
    ListLines 1, LIST_GUARD_OFFSET, 0, Float::PrintDecimalAX, 0, ReadyForCommand
    ListTokens 0, 1, 1, 0
.include "../../Microsoft6502Basic/MsBasic.For.asm"
    CommodoreStatementFetch STATEMENT_FETCH_NOP, EARLY_SEPARATOR_CHECK, SHORT_END_BRANCH, GetNextCharacter
    CommodoreStatementDispatch EARLY_STATEMENT_DISPATCH, 0
    RestoreStatement
    StopAndContinue STOP_BY_LINE_NUMBER, 1
    NullStatement NULL_INCREMENT_LIMIT
    ClearStatement Statements::Cont::Done
    jmp ClearVariables
    RunStatement
    GosubAndGoto NextStatement
    ReturnStatement RETURN_LOW_FOR_POINTER, 0
    StatementScan QUOTE_BRANCH_FIRST, 0
    ConditionalStatements
    OnStatement
.include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
    AssignmentStart
    TimeStringAssignment TIME_LONG_ERROR
    StringAssignment 0, 0

    ; Terminal and channel output, then READ and input.
    CommodorePrintChannels
    PrintItems PrintTabOrSpace, PRINT_CLEAR_SPC_CARRY, 0, 1
    CommodoreLineEnd INPUT_BUFFER_PAGE, LOCAL_TERMINAL_POSITION, 0, PRINT_NULL_PADDING
    CommodorePrintSpacing PRINT_TOKEN_SPACING
.include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
    CommodoreCharacterOutput ALWAYS_SKIP_CHARACTER, LOCAL_TERMINAL_POSITION, 1, 1
    CommodoreInputError INPUT_ERROR_EDITOR_PATCH
    CommodoreChannelInput INPUT_BUFFER_PAGE
    CommodoreInputStatement 1, 2, 0, INPUT_STOP_EDITOR_PATCH, 0
    VariableInput INPUT_BUFFER_PAGE, 0, GET_POINTER_Y_FIRST, GET_STRING_EDITOR_PATCH, 1, 0
    VariableInputMessages 0, 1

    ; Expressions, variables, arrays and strings.
    NextEntries NEXT_COUNTED_STACK, NextStatement
    ExpressionCore 0
    OperandEvaluation 1, 1, CallFunction
    CommodoreVariableValue 0, CLOCK_EDITOR_PATCH, 0
    FunctionDispatch
    LogicalOperators 1
    RelationalOperators $FF
.include "../../Microsoft6502Basic/MsBasic.Dim.asm"
    VariableSearch 0, 0, 1, 0, 0, 0
    LetterTest
    SimpleVariableLookup 0, 1-ZERO_IN_HALF_CONSTANT, 0, 1, 1, 0, 0, 0
    IntegerConversionBoundary
.if SUBSCRIPT_CHECKS_NUMERIC
    IntegerConversion EvaluateNumber, POSITIVE_INTEGER_CHECKS_TYPE
.else
    IntegerConversion EvaluateExpression, POSITIVE_INTEGER_CHECKS_TYPE
.endif
    ArrayLookup 0, 0, ARRAY_SAVE_OFFSET_HIGH
.include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
    SimpleFunctions 0
    UserFunctions USER_FN_LOW_CHECK
    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, STRING_CLEARS_FAC_EXTENSION
    StringAllocation 0
    StringGarbageCollection COLLECTOR_FULL_POINTER, COLLECTOR_PATCH_ARRAY_STEP, COLLECTOR_SUBTRACT_OFFSET
    StringConcatenation 0
    StringFunctions REJECT_ZERO_SLICES, STRING_PREAMBLE_INDIRECT_RETURN, ASC_SHARED_LEN_JUMP, 0

    ; Memory access, floating point and cold startup.
    AddressConversion 1
    PeekFunction PEEK_PRESERVE_ADDRESS, 1, PEEK_GUARD_ROM, PEEK_PAD_GUARD
    PokeStatement
.if WAIT_EASTER_EGG
    WaitStatement WaitHiddenMessage
.else
    WaitStatement Statements::Wait::StoreMask
.endif
.include "Commodore.FloatingPoint.asm"
.include "Commodore.HistoricalNames.asm"
    CharacterReader RANDOM_SEED_TAIL
    CommodoreInitialize INIT_MARK_DIRECT, INIT_LINE_WIDTH, INIT_DELAY_SIZE, 0, INIT_EARLY_BUFFER_SETUP
    CommodoreMemoryProbe PROBE_LOAD_ZERO, PROBE_ZERO_INDEX, PROBE_SAVE_START, 0, PROBE_STOP_AT_SCREEN, PROBE_TEST_BYTE
.if START_BANNER_AFTER_FREE
    CommodoreStartProgram 1, START_CARRY_PROGRAM_START, 1, 1, 0
.else
    CommodoreStartProgram 1, START_CARRY_PROGRAM_START, 1, 0, SignOnMessage
.endif
    CommodoreStartMessages START_BANNER_AFTER_FREE
    CommodoreBasic1EditorPatches
.assert * = $E1E1, "BASIC 1's main editor spill must end at $E1E0."

.org $E7F3
    CommodoreBasic1ArrayPatch
.assert * = $E7F9, "BASIC 1's array patch must end at $E7F8."
