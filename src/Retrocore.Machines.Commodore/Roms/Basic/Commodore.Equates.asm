; retrocore: style=strict
;; COMMODORE BASIC: WORKSPACE AND SYSTEM ENTRIES
;;
;; These are addresses in RAM and the kernal jump table, not allocations or addresses of BASIC ROM routines.
;; Including this file emits no bytes and does not change the origin. The RAM code at <GetNextCharacter> is copied
;; there by initialization; the ROM copy and the rest of the interpreter still need their own labels.
;;
;; The defaults describe BASIC 2. For either BASIC 1 revision, set <INPUT_BUFFER_PAGE>=0,
;; <INPUT_BUFFER_LENGTH>=80, <NULL_COMMAND>=1, <FULL_STACK_TOP>=1, <STACK_RESERVE_19>=1, <TERMINAL_FIRST>=1,
;; <LOCAL_TERMINAL_POSITION>=1, <VARIABLE_LIST_IN_LINE_NUMBER>=1, <CLOCK_IN_PAGE2>=1, <STATUS_IN_PAGE2>=1,
;; <RND_TIMER_9044>=1 and <ERROR_PADDING5>=1 before including this file. For either BASIC 4 revision, set
;; <DISK_STATUS_STRING>=1, <LINE_WIDTH_STORAGE>=0 and <EXTENDED_DISK_VECTORS>=1 instead. For the VIC-20, set
;; <INPUT_BUFFER_LENGTH>=89, <LINE_LENGTH>=22, <ZONE_WIDTH>=11, <LINE_WIDTH_STORAGE>=0, <OUTPUT_SUPPRESSION_FLAG>=0,
;; <CONVERSION_VECTORS>=1, <CURSOR_COLUMN_FROM_PLOT>=1, <STANDARD_KERNAL>=1, <BASIC_RAM_VECTORS>=1 and
;; <NUMBERED_ERRORS>=1. The chip revisions change code, not this workspace. Layouts that overlap kernal storage are
;; rejected.
;;
;; The layout follows the <REALIO>=3 build of Microsoft's m6502.asm with the Basic1.mac, Basic2.mac and Basic4.mac
;; overlays. The names follow the assembly style guide; each definition lists Microsoft's name and those of
;; Commodore's listing and the reconstructions as its historical names, so the sources that still use them
;; assemble unchanged. The tokens and error offsets are defined with their tables in Commodore.DispatchTables.asm;
;; only <TOKEN_PI>, which has no spelling there, is here.

.cpu Mos6502

; Microsoft configuration values used to place the workspace.
;; Microsoft build target: 3 selects Commodore I/O.
REALIO = 3
.include "../../Microsoft6502Basic/MsBasic.Switches.asm"
.include "../../Microsoft6502Basic/MsBasic.Layouts.asm"
.include "../../Microsoft6502Basic/MsBasic.Families.asm"

.ifndef INPUT_BUFFER_PAGE
;; Input buffer page: 0 for page zero or 2 for page two.
;; Also: BUFPAG (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
INPUT_BUFFER_PAGE = 2
.endif
.ifndef INPUT_BUFFER_LENGTH
;; Input buffer length in bytes.
;; Also: BUFLEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
INPUT_BUFFER_LENGTH = 81
.endif
.ifndef NULL_COMMAND
;; 1 reserves the `NULL` count byte; BASIC 1 has the code but no `NULL` token.
;; Also: NULCMD (M6502)
NULL_COMMAND = 0
.endif

; Independent changes in the terminal, interpreter and operating-system workspaces.
.ifndef TERMINAL_FIRST
;; 1 places terminal storage before general scratch, including a page-zero buffer.
TERMINAL_FIRST = 0
.endif
.ifndef FULL_STACK_TOP
;; 1 allows the stack to reach the top of page one instead of $01FB.
FULL_STACK_TOP = 0
.endif
.ifndef STACK_RESERVE_19
;; 1 makes the stack check reserve 19 levels instead of 23.
STACK_RESERVE_19 = 0
.endif
.ifndef LOCAL_TERMINAL_POSITION
;; 1 reserves BASIC's own cursor position and names the early editor column.
LOCAL_TERMINAL_POSITION = 0
.endif
.ifndef LINE_WIDTH_STORAGE
;; 1 reserves the line-width and last-print-zone bytes.
LINE_WIDTH_STORAGE = 1
.endif
.ifndef DISK_STATUS_STRING
;; 1 replaces output suppression with the three-byte disk-status descriptor.
DISK_STATUS_STRING = 0
.endif
.ifndef VARIABLE_LIST_IN_LINE_NUMBER
;; 1 shares the variable-list pointer with the input line number.
VARIABLE_LIST_IN_LINE_NUMBER = 0
.endif
.ifndef CLOCK_IN_PAGE2
;; 1 places the three-byte clock at $0200 rather than in page zero.
CLOCK_IN_PAGE2 = 0
.endif
.ifndef STATUS_IN_PAGE2
;; 1 places the I/O status byte at $020C rather than in page zero.
STATUS_IN_PAGE2 = 0
.endif
.ifndef RND_TIMER_9044
;; 1 makes RND(0) read from $9044 instead of the VIA at $E844.
RND_TIMER_9044 = 0
.endif
.ifndef ERROR_PADDING5
;; 1 includes BASIC 1's five unused bytes in the long error table.
ERROR_PADDING5 = 0
.endif
.ifndef EXTENDED_DISK_VECTORS
;; 1 includes the disk-command jump table below $FFC0.
EXTENDED_DISK_VECTORS = 0
.endif

; The VIC-20's switches, which the modules read too.
.include "Commodore.Switches.asm"

.ifndef STACK_LEVELS
.if STACK_RESERVE_19
;; Stack reserve, counted in two-byte levels.
;;
;; The documents give NUMLEV as 23, the other builds' value: BASIC 1's reconstructions (HV1, HV1R) write this build's
;; 54-byte reserve as 23 levels plus eight bytes, where this build adds three and thirteen to nineteen levels.
;; Also: NUMLEV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
STACK_LEVELS = 19
.else
;; Stack reserve, counted in two-byte levels.
;; Also: NUMLEV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
STACK_LEVELS = 23
.endif
.endif
.ifndef STACK_END
.if FULL_STACK_TOP
;; Upper stack limit.
;; Also: STKEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
STACK_END = $01FF
.else
;; Upper stack limit.
;; Also: STKEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
STACK_END = $01FB
.endif
.endif

.assert INPUT_BUFFER_PAGE = 0 || INPUT_BUFFER_PAGE = 2, "INPUT_BUFFER_PAGE is 0 or 2."
.assert INPUT_BUFFER_LENGTH > 0 && INPUT_BUFFER_LENGTH <= 255, "INPUT_BUFFER_LENGTH is 1 through 255."
.assert NULL_COMMAND = 0 || NULL_COMMAND = 1, "NULL_COMMAND is 0 or 1."
.assert INTEGER_VARIABLES = 1 && ADDITIONAL_PRECISION = 1, "The PET workspace uses integer arrays and five-byte floats."
.assert STACK_END >= $0100 && STACK_END <= $01FF, "STACK_END is in page one."
.assert STACK_LEVELS > 0, "STACK_LEVELS is positive."
.assert TERMINAL_FIRST = 0 || TERMINAL_FIRST = 1, "TERMINAL_FIRST is 0 or 1."
.assert FULL_STACK_TOP = 0 || FULL_STACK_TOP = 1, "FULL_STACK_TOP is 0 or 1."
.assert STACK_RESERVE_19 = 0 || STACK_RESERVE_19 = 1, "STACK_RESERVE_19 is 0 or 1."
.assert LOCAL_TERMINAL_POSITION = 0 || LOCAL_TERMINAL_POSITION = 1, "LOCAL_TERMINAL_POSITION is 0 or 1."
.assert LINE_WIDTH_STORAGE = 0 || LINE_WIDTH_STORAGE = 1, "LINE_WIDTH_STORAGE is 0 or 1."
.assert DISK_STATUS_STRING = 0 || DISK_STATUS_STRING = 1, "DISK_STATUS_STRING is 0 or 1."
.assert VARIABLE_LIST_IN_LINE_NUMBER = 0 || VARIABLE_LIST_IN_LINE_NUMBER = 1, "VARIABLE_LIST_IN_LINE_NUMBER is 0 or 1."
.assert CLOCK_IN_PAGE2 = 0 || CLOCK_IN_PAGE2 = 1, "CLOCK_IN_PAGE2 is 0 or 1."
.assert STATUS_IN_PAGE2 = 0 || STATUS_IN_PAGE2 = 1, "STATUS_IN_PAGE2 is 0 or 1."
.assert RND_TIMER_9044 = 0 || RND_TIMER_9044 = 1, "RND_TIMER_9044 is 0 or 1."
.assert ERROR_PADDING5 = 0 || ERROR_PADDING5 = 1, "ERROR_PADDING5 is 0 or 1."
.assert EXTENDED_DISK_VECTORS = 0 || EXTENDED_DISK_VECTORS = 1, "EXTENDED_DISK_VECTORS is 0 or 1."
.assert CURSOR_COLUMN_FROM_PLOT = 0 || LOCAL_TERMINAL_POSITION + TERMINAL_FIRST = 0, "PLOT needs the later layout."
.assert OUTPUT_SUPPRESSION_FLAG = 1 || TERMINAL_FIRST = 0, "BASIC 1's workspace keeps the output-suppression flag."
.assert STANDARD_KERNAL = 0 || CLOCK_IN_PAGE2 + STATUS_IN_PAGE2 = 0, "The standard kernal has its own clock and status."
.assert STANDARD_KERNAL = 0 || EXTENDED_DISK_VECTORS = 0, "The standard kernal has no disk-command jump table."

; Sizes and terminal constants from the Microsoft build.
;; Number of temporary string descriptors.
;; Also: NUMTMP (M6502)
TEMPORARY_COUNT = 3

.ifndef LINE_LENGTH
;; Default terminal line width.
;; Also: LINLEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LINE_LENGTH = 40
.endif

.ifndef ZONE_WIDTH
;; Width of a print zone.
;; Also: CLMWID (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ZONE_WIDTH = 10
.endif

;; Column beyond which there are no more print zones. No code uses it: the VIC-20's listing (BV20) leaves its NCMPOS at
;; the 40-column screen's 30.
;; Also: NCMPOS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LAST_COMMA_COLUMN = ((LINE_LENGTH / ZONE_WIDTH) - 1) * ZONE_WIDTH

;; Control-O, the output-suppression character.
;; Also: CONTW (M6502)
SUPPRESS_OUTPUT_KEY = 15

;; The PET's token for pi, a character of its own.
;; Also: PI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TOKEN_PI = 255

;; Microsoft build's initial RAM location, not the current memory limit.
;; Also: RAMLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RAM_ORIGIN = $0400

; The writable USR jump is followed either by the terminal block or by general scratch.
;; Three-byte writable jump used by `USR`.
;; Also: USRPOK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
UserVector = $00
.if CONVERSION_VECTORS
;; The address of the routine that converts <Fac> to a signed two-byte integer in A and Y, high byte first, for machine
;; code to call: start-up points it at <FacToSignedWord>.
;; Also: ADRAY1 (BV20)
FloatToIntegerVector = UserVector + 3

;; The address of the routine that converts the signed two-byte integer in A and Y, high byte first, to a number in
;; <Fac>, for machine code to call: start-up points it at <ReturnSignedWord>.
;; Also: ADRAY2 (BV20)
IntegerToFloatVector = FloatToIntegerVector + 2
.endif
.if TERMINAL_FIRST
;; Current logical channel number.
;; Also: CHANNL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20), CHANL (K4S79, HVK4)
CurrentChannel = UserVector + 3
.else
;; Current logical channel number, after the flags.
;; Also: CHANNL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20), CHANL (K4S79, HVK4)
CurrentChannel = TangentSign + 1 + 3 * DISK_STATUS_STRING + OUTPUT_SUPPRESSION_FLAG * (1 - DISK_STATUS_STRING)
.endif
.if NULL_COMMAND
;; Number of `NULL` characters to print.
;; Also: NULCNT (M6502, HV1, HV1R)
NullCount = CurrentChannel + 1
.endif
.if LOCAL_TERMINAL_POSITION
;; BASIC's own terminal position.
;; Also: TRMPOS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TerminalPosition = CurrentChannel + 1 + NULL_COMMAND

;; Early screen editor's cursor column, used when <TerminalPosition> wraps.
;; Also: CQPNTR (UNKN)
EditorCursorColumn = $E2
.elseif CURSOR_COLUMN_FROM_PLOT
;; The cursor's column, which `TAB` reads through <KernalPlot> and keeps here while it evaluates its argument.
;; Also: TRMPOS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TerminalPosition = EndDelimiter + 1
.else
;; Screen editor's terminal position.
;; Also: TRMPOS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TerminalPosition = $C6
.endif
.if LINE_WIDTH_STORAGE
;; Stored terminal line width.
;; Also: LINWID (M6502, HV2)
LineWidth = CurrentChannel + 1 + NULL_COMMAND + LOCAL_TERMINAL_POSITION

;; Stored last print-zone column.
;; Also: NCMWID (M6502), NCMWFL (HV2)
LastCommaColumn = LineWidth + 1
.endif
;; Two-byte input line number, shared with <PokeAddress>.
;; Also: LINNUM (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
LineNumber = CurrentChannel + 1 + NULL_COMMAND + LOCAL_TERMINAL_POSITION + 2 * LINE_WIDTH_STORAGE
.if INPUT_BUFFER_PAGE = 0
;; Page-zero input buffer after the line-number and comma bytes.
;; Also: BUF (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
InputBuffer = LineNumber + 2
.else
;; Page-two input and tokenization buffer.
;; Also: BUF (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
InputBuffer = INPUT_BUFFER_PAGE * 256
.endif
;; Page base used when indexing the input buffer.
;; Also: BUFOFS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
INPUT_BUFFER_BASE = INPUT_BUFFER_PAGE * 256

; General scratch and flags; aliases deliberately share their storage.
.if TERMINAL_FIRST
.if INPUT_BUFFER_PAGE = 0
;; Delimiter character after the page-zero input buffer.
;; Also: CHARAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Delimiter = InputBuffer + INPUT_BUFFER_LENGTH
.else
;; Delimiter character after the terminal block.
;; Also: CHARAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Delimiter = LineNumber + 2
.endif
.else
;; Delimiter character after the `USR` jump and any conversion vectors.
;; Also: CHARAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Delimiter = UserVector + 3 + 4 * CONVERSION_VECTORS
.endif
;; One-byte integer result, sharing <Delimiter>.
;; Also: INTEGR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SmallInteger = Delimiter

;; Second delimiter character.
;; Also: ENDCHR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
EndDelimiter = Delimiter + 1

.if STANDARD_KERNAL
;; 0 while `LOAD` runs, 1 while `VERIFY` does: the mode <KernalLoad> is called with, and how BASIC finishes.
;; Also: VERCK (BV20)
LoadVerifyFlag = EndDelimiter + 1 + CURSOR_COLUMN_FROM_PLOT
.endif

;; General counter.
;; Also: COUNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Counter = EndDelimiter + 1 + CURSOR_COLUMN_FROM_PLOT + STANDARD_KERNAL

;; Array-dimensioning flag: set while `DIM` is defining arrays.
;; Also: DIMFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20), KIMY (M6502)
Dimensioning = Counter + 1

;; Value type: zero for numeric, $FF for string.
;; Also: VALTYP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ValueType = Dimensioning + 1

;; Integer-variable type flag.
;; Also: INTFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
IntegerType = ValueType + 1

;; Tokenizer flag suppressing reserved words in `DATA`, shared with <CollectionState>.
;; Also: DORES (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TokenizeState = IntegerType + 1

;; Garbage-collection flag sharing <TokenizeState>.
;; Also: GARBFL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CollectionState = TokenizeState

;; Suppresses subscripted-variable recognition.
;; Also: SUBFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SubscriptMode = TokenizeState + 1

;; Distinguishes `INPUT` from `READ`.
;; Also: INPFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
InputMode = SubscriptMode + 1

;; Tangent sign scratch, shared with <RelationMask>.
;; Also: TANSGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TangentSign = InputMode + 1
.if DISK_STATUS_STRING
;; Three-byte DS$ disk-status string descriptor.
;; Also: DSDESC (CBM4S79, K4S79, HV4, HV4R, HVK4)
DiskStatusDescriptor = TangentSign + 1
.elseif OUTPUT_SUPPRESSION_FLAG
;; Output-suppression flag.
;; Also: CNTWFL (M6502, HV1, HV1R, HV2)
OutputSuppressed = TangentSign + 1
.endif

; Three temporary descriptors, arithmetic scratch and dynamic-memory pointers.
.if TERMINAL_FIRST
.if DISK_STATUS_STRING
;; Page-zero pointer to the next free temporary descriptor.
;; Also: TEMPPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextTemporary = DiskStatusDescriptor + 3
.else
;; Page-zero pointer to the next free temporary descriptor.
;; Also: TEMPPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextTemporary = OutputSuppressed + 1
.endif
.else
.if INPUT_BUFFER_PAGE = 0
;; Page-zero pointer to the next free temporary descriptor.
;; Also: TEMPPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextTemporary = InputBuffer + INPUT_BUFFER_LENGTH
.else
;; Page-zero pointer to the next free temporary descriptor.
;; Also: TEMPPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextTemporary = LineNumber + 2
.endif
.endif
;; Two-byte pointer to the last-used temporary descriptor.
;; Also: LASTPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LastTemporary = NextTemporary + 1

;; Three consecutive three-byte temporary string descriptors.
;; Also: TEMPST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TemporaryDescriptors = LastTemporary + 2

;; Two-byte index scratch.
;; Also: INDEX1 (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20), INDEX (M6502, CBM4S79, HV1, HV1R, HV2,
;;   HV4, HV4R, BV20)
Pointer1 = TemporaryDescriptors + DESCRIPTOR_SIZE * TEMPORARY_COUNT

;; Second two-byte index scratch.
;; Also: INDEX2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Pointer2 = Pointer1 + 2

;; High byte of multiplication or division result scratch.
;; Also: RESHO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Result1 = Pointer2 + 2

;; Second byte of multiplication or division result scratch.
;; Also: RESMOH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Result2 = Result1 + 1

;; Third result byte, shared with <Addend>.
;; Also: RESMO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Result3 = Result2 + 1

;; Low byte of multiplication or division result scratch.
;; Also: RESLO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Result4 = Result3 + 1

;; Multiplication addend scratch, sharing <Result3>.
;; Also: ADDEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Addend = Result3

;; Two-byte pointer to the first program line, after the result overflow byte.
;; Also: TXTTAB (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
ProgramStart = Result4 + 2

;; Two-byte pointer to simple variables after the program.
;; Also: VARTAB (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
VariablesStart = ProgramStart + 2

;; Two-byte pointer to arrays after the simple variables.
;; Also: ARYTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArraysStart = VariablesStart + 2

;; Two-byte pointer to the end of variable and array storage.
;; Also: STREND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArraysEnd = ArraysStart + 2

;; Two-byte pointer to the bottom of allocated string space.
;; Also: FRETOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
StringsBottom = ArraysEnd + 2

;; Two-byte pointer to a newly allocated string.
;; Also: FRESPC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NewString = StringsBottom + 2

;; Two-byte upper limit of BASIC's string storage.
;; Also: MEMSIZ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
MemoryTop = NewString + 2

;; Current two-byte line number; its high byte is $FF for direct execution.
;; Also: CURLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CurrentLine = MemoryTop + 2

;; Two-byte line number saved for `CONT`.
;; Also: OLDLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
StoppedLine = CurrentLine + 2

;; Two-byte `POKE` and WAIT address scratch, sharing <LineNumber>.
;; Also: POKER (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
PokeAddress = LineNumber

;; Two-byte text pointer saved for `CONT`.
;; Also: OLDTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
StoppedText = StoppedLine + 2

;; Two-byte line number of the current `DATA` statement.
;; Also: DATLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DataLine = StoppedText + 2

;; Two-byte pointer into `DATA` for `READ`.
;; Also: DATPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DataPointer = DataLine + 2

;; Two-byte pointer into input for `INPUT` or `READ`.
;; Also: INPPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
InputPointer = DataPointer + 2

; Variable, expression and transfer scratch.
;; Two-byte encoded variable name.
;; Also: VARNAM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
VariableName = InputPointer + 2

;; Two-byte pointer to a variable's value, shared with <PowerTablePointer>.
;; Also: VARPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
VariablePointer = VariableName + 2

;; Power-of-ten table pointer for numeric output, sharing <VariablePointer>.
;; Also: FDECPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
PowerTablePointer = VariablePointer

;; Two-byte `FOR` or assignment pointer, also used for the WAIT masks.
;; Also: FORPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
AssignedVariable = VariablePointer + 2

;; `LIST`'s saved index into the line it is listing, sharing <AssignedVariable>.
;; Also: LSTPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ListOffset = AssignedVariable

;; WAIT AND mask, sharing the first byte of <AssignedVariable>.
;; Also: ANDMSK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
WaitAndMask = AssignedVariable

;; WAIT exclusive-OR mask, sharing the second byte of <AssignedVariable>.
;; Also: EORMSK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
WaitXorMask = AssignedVariable + 1

;; Two-byte pointer to the current operator table entry.
;; Also: OPPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
OperatorPointer = AssignedVariable + 2
.if VARIABLE_LIST_IN_LINE_NUMBER
;; Variable-list pointer sharing <LineNumber>.
;; Also: VARTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
VariableListPointer = LineNumber
.else
;; Variable-list pointer sharing <OperatorPointer>.
;; Also: VARTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
VariableListPointer = OperatorPointer
.endif
;; Current relational-operator mask.
;; Also: OPMASK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
OperatorMask = OperatorPointer + 2

;; Relation-operation mask, sharing <TangentSign>.
;; Also: DOMASK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RelationMask = TangentSign

;; Two-byte function-definition pointer, shared with <CollectorPointer> and <FloatTemporary3>.
;; Also: DEFPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FunctionPointer = OperatorMask + 1

;; Garbage-collection pointer, sharing <FunctionPointer>.
;; Also: GRBPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CollectorPointer = FunctionPointer

;; Two-byte pointer to a string descriptor.
;; Also: DSCPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DescriptorPointer = FunctionPointer + 2

;; Garbage collector's descriptor-size scratch, after the extra temporary byte.
;; Also: FOUR6 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CollectorStep = DescriptorPointer + 3

;; Writable three-byte jump whose operand bytes are <CollectorOffset> and <FunctionJumpHigh>.
;; Also: JMPER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FunctionJump = CollectorStep + 1

;; The string collector's descriptor-offset scratch, sharing the first operand byte of <FunctionJump>.
;; Also: SIZE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CollectorOffset = FunctionJump + 1

;; The second operand byte of <FunctionJump>, which the floating-point code borrows: while adding, the extension
;; (rounding) byte of the operand that is not shifted, the shifted one's being in <FacExtension>; `EXP` keeps its
;; rounding byte here.
;; Also: OLDOV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FunctionJumpHigh = FunctionJump + 2

;; Five-byte floating-point temporary overlapping <FunctionPointer> and <DescriptorPointer>.
;; Also: TEMPF3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FloatTemporary3 = FunctionPointer

;; Five-byte floating-point temporary overlapping transfer scratch.
;; Also: TEMPF1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FloatTemporary1 = FunctionJump + 3

;; Two-byte end of the destination block, shared with <ArrayPointer>.
;; Also: HIGHDS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DestinationEnd = FloatTemporary1 + 1

;; Two-byte end of the source block.
;; Also: HIGHTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SourceEnd = DestinationEnd + 2

;; Five-byte floating-point temporary overlapping transfer scratch.
;; Also: TEMPF2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FloatTemporary2 = SourceEnd + 2

;; Two-byte transfer scratch, shared with <DigitCount> and <DecimalExponent>.
;; Also: LOWDS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DestinationStart = FloatTemporary2 + 1

;; Two-byte start of the source block, shared with <CollectorTop>.
;; Also: LOWTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SourceStart = DestinationStart + 2

;; Two-byte array-building pointer, sharing <DestinationEnd>.
;; Also: ARYPNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArrayPointer = DestinationEnd

;; Two-byte garbage-collection pointer, sharing <SourceStart>.
;; Also: GRBTOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CollectorTop = SourceStart

;; Decimal digit-count scratch, sharing <DestinationStart>.
;; Also: DECCNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DigitCount = DestinationStart

;; Decimal exponent scratch, sharing the second byte of <DestinationStart>.
;; Also: TENEXP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DecimalExponent = DestinationStart + 1

;; Decimal-point flag, sharing the first byte of <SourceStart>.
;; Also: DPTFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DecimalPointSeen = SourceStart

;; Decimal exponent sign flag, sharing the second byte of <SourceStart>.
;; Also: EXPSGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20), EPSGN (BV20)
ExponentSign = SourceStart + 1

; Unpacked floating-point accumulators and reused string scratch.
;; Floating-point accumulator, also descriptor scratch <NewDescriptor>.
;; Also: FAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Fac = SourceStart + 2

;; Exponent of <Fac>.
;; Also: FACEXP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacExponent = Fac

;; High mantissa byte of <Fac>.
;; Also: FACHO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacMantissa1 = FacExponent + 1

;; Second mantissa byte of <Fac>.
;; Also: FACMOH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacMantissa2 = FacMantissa1 + 1

;; Third mantissa byte of <Fac>, shared with <ArrayIndex>.
;; Also: FACMO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacMantissa3 = FacMantissa2 + 1

;; Low mantissa byte of <Fac>.
;; Also: FACLO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacMantissa4 = FacMantissa3 + 1

;; Unpacked sign of <Fac>.
;; Also: FACSGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacSign = FacMantissa4 + 1

;; The sign of the number being read: set by a leading minus, tested to negate it at the end. Shared with
;; <PolynomialDegree>.
;; Also: SGNFLG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
InputSign = FacSign + 1

;; Polynomial degree counter, sharing <InputSign>.
;; Also: DEGREE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
PolynomialDegree = InputSign

;; Temporary string descriptor built in <Fac>.
;; Also: DSCTMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NewDescriptor = Fac

;; Integer-conversion scratch, sharing <FacMantissa3>.
;; Also: INDICE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArrayIndex = FacMantissa3

;; The fill byte for whole-byte right shifts: 0, or $FF to extend a sign.
;; Also: BITS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ShiftFill = InputSign + 1

;; Floating-point argument exponent.
;; Also: ARGEXP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgExponent = ShiftFill + 1

;; High mantissa byte of the floating-point argument.
;; Also: ARGHO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgMantissa1 = ArgExponent + 1

;; Second mantissa byte of the floating-point argument.
;; Also: ARGMOH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgMantissa2 = ArgMantissa1 + 1

;; Third mantissa byte of the floating-point argument.
;; Also: ARGMO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgMantissa3 = ArgMantissa2 + 1

;; Low mantissa byte of the floating-point argument.
;; Also: ARGLO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgMantissa4 = ArgMantissa3 + 1

;; Unpacked sign of the floating-point argument.
;; Also: ARGSGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArgSign = ArgMantissa4 + 1

;; Arithmetic result-sign scratch, shared with <StringPointer>.
;; Also: ARISGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ResultSign = ArgSign + 1

;; Floating-point accumulator overflow byte.
;; Also: FACOV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FacExtension = ResultSign + 1

;; Two-byte string or descriptor pointer, sharing <ResultSign> and <FacExtension>.
;; Also: STRNG1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20), STRNGI (BV20)
StringPointer = ResultSign

;; Two-byte numeric-output pointer, shared with <TokenizePointer>, <SecondStringPointer>, <PolynomialPointer> and
;; <LinearIndex>.
;; Also: FBUFPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NumberBufferPointer = FacExtension + 1

;; Two-byte tokenizer buffer pointer, sharing <NumberBufferPointer>.
;; Also: BUFPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TokenizePointer = NumberBufferPointer

;; Two-byte string or descriptor pointer, sharing <NumberBufferPointer>.
;; Also: STRNG2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SecondStringPointer = NumberBufferPointer

;; Two-byte polynomial-coefficient pointer, sharing <NumberBufferPointer>.
;; Also: POLYPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
PolynomialPointer = NumberBufferPointer

;; Two-byte linear array index, sharing <NumberBufferPointer>.
;; Also: CURTOL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LinearIndex = NumberBufferPointer

; Addresses of code and data copied into RAM, followed by the page-one output buffer.
;; Character-fetch entry in the code copied to page zero.
;; Also: CHRGET (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
GetNextCharacter = NumberBufferPointer + 2

;; Fetch entry that does not first increment <TextPointer>; it skips spaces.
;; Also: CHRGOT (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
GetCurrentCharacter = GetNextCharacter + 6

;; Two-byte load operand in <GetCurrentCharacter>, the current BASIC text pointer.
;; Also: TXTPTR (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
TextPointer = GetCurrentCharacter + 1

;; Character-classification entry in the copied <GetNextCharacter> code.
;; Also: QNUM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ClassifyCharacter = GetCurrentCharacter + 7

;; Return instruction in the copied <GetNextCharacter> code.
;; Also: CHRRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CharacterReaderReturn = ClassifyCharacter + 10

;; Five-byte packed random-number state.
;; Also: RNDX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RandomValue = CharacterReaderReturn + 1

;; Byte immediately before <NumberBuffer>, usable by `STR$` output.
;; Also: LOFBUF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NumberBufferPrefix = $FF

;; Sixteen-byte numeric output buffer at the bottom of page one.
;; Also: FBUFFR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NumberBuffer = NumberBufferPrefix + 1
.assert RandomValue + 5 <= NumberBufferPrefix, "The page-zero workspace must not overlap NumberBufferPrefix."

; Operating-system state and RND(0)'s read addresses.
.if CLOCK_IN_PAGE2
;; Three-byte clock in the early kernal's page-two workspace.
;;
;; BASIC 4's kernal listings (K4S79, HVK4) call it `TIME` at its page-zero location, a name the builds give a switch.
;; Also: CQTIMR (M6502), CTIMR (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
JiffyClock = $0200
.elseif STANDARD_KERNAL
;; Three-byte clock in the standard kernal's page zero. BASIC reads and sets it through <KernalReadClock> and
;; <KernalSetClock>.
;;
;; The PET's kernal listings (K4S79, HVK4) call the PET's clock, at $8D, `TIME`, a name the builds give a switch.
;; Also: CQTIMR (M6502), CTIMR (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
JiffyClock = $A0
.else
;; Three-byte clock in page zero.
;;
;; The kernal listings (K4S79, HVK4) call it `TIME`, a name the builds give a switch.
;; Also: CQTIMR (M6502), CTIMR (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
JiffyClock = $8D
.endif
.if STATUS_IN_PAGE2
;; I/O status byte in the early kernal's page-two workspace.
;;
;; BASIC 4's kernal listings call it `SATUS` at its page-zero location.
;; Also: CQSTAT (M6502), CSTAT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), SATUS (K4S79, HVK4)
IoStatus = $020C
.elseif STANDARD_KERNAL
;; I/O status byte in the standard kernal's page zero. BASIC reads it through <KernalReadStatus>.
;;
;; Also: CQSTAT (M6502), CSTAT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), SATUS (K4S79, HVK4)
IoStatus = $90
.else
;; I/O status byte in page zero.
;;
;; Also: CQSTAT (M6502), CSTAT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), SATUS (K4S79, HVK4)
IoStatus = $96
.endif
.if RND_TIMER_9044
;; RND(0) reads here and at offsets 1, 4 and 5, not the VIA timer.
;; Also: CQHTIM (M6502), CHTIM (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), TIL (K4S79, HVK4)
RandomTimer = $9044
.else
;; RND(0) reads the VIA timer registers at offsets 0, 1, 4 and 5.
;; Also: CQHTIM (M6502), CHTIM (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), TIL (K4S79, HVK4)
RandomTimer = $E844
.endif
.if CLOCK_IN_PAGE2 = 0
.assert RandomValue + 5 <= JiffyClock, "The BASIC workspace must not overlap the page-zero clock."
.endif
.if STATUS_IN_PAGE2 = 0
.assert RandomValue + 5 <= IoStatus, "The BASIC workspace must not overlap the page-zero I/O status."
.endif
.if LOCAL_TERMINAL_POSITION
.assert RandomValue + 5 <= EditorCursorColumn, "The BASIC workspace must not overlap the editor's cursor column."
.elseif CURSOR_COLUMN_FROM_PLOT = 0
.assert RandomValue + 5 <= TerminalPosition, "The BASIC workspace must not overlap the editor's terminal position."
.endif
.if INPUT_BUFFER_PAGE = 2
.if CLOCK_IN_PAGE2
.assert InputBuffer + INPUT_BUFFER_LENGTH <= JiffyClock || InputBuffer >= JiffyClock + 3, "Clock in the input buffer."
.endif
.if STATUS_IN_PAGE2
.assert InputBuffer + INPUT_BUFFER_LENGTH <= IoStatus || InputBuffer > IoStatus, "I/O status in the input buffer."
.endif
.endif
.assert STACK_END - NumberBuffer > 2 * STACK_LEVELS + 16, "STACK_LEVELS's stack reserve must fit above NumberBuffer."

.if BASIC_RAM_VECTORS
; BASIC's RAM vectors at $0300: six of BASIC's routines jump through these, so a program can put its own in front of
; them. Start-up points each at the ROM's routine, the `Default` entry of the routine that jumps through it.
;; Where <ReportError> goes, with the error's number in X.
;; Also: IERROR (BV20)
ErrorVector = $0300

;; Where <CommandLoop> goes to read the next line typed.
;; Also: IMAIN (BV20)
CommandLoopVector = ErrorVector + 2

;; Where <Tokenize> goes to turn a typed line's keywords into tokens.
;; Also: ICRNCH (BV20)
TokenizeVector = CommandLoopVector + 2

;; Where `LIST` goes to print a character or token of a program line.
;; Also: IQPLOP (BV20)
ListTokenVector = TokenizeVector + 2

;; Where <ExecuteStatement> goes to run the statement at the text pointer.
;; Also: IGONE (BV20)
StatementVector = ListTokenVector + 2

;; Where <EvaluateOperand> goes to read an operand: a number, a variable, a function or a bracketed expression.
;; Also: IEVAL (BV20)
OperandVector = StatementVector + 2

;; The accumulator `SYS` loads before it calls, and keeps when the routine returns.
;; Also: SAREG (BV20)
SysAccumulator = OperandVector + 2

;; The X register `SYS` loads before it calls, and keeps when the routine returns.
;; Also: SXREG (BV20)
SysX = SysAccumulator + 1

;; The Y register `SYS` loads before it calls, and keeps when the routine returns.
;; Also: SYREG (BV20)
SysY = SysX + 1

;; The status register `SYS` loads before it calls, and keeps when the routine returns.
;; Also: SPREG (BV20)
SysStatus = SysY + 1
.endif

.if STANDARD_KERNAL
; The standard kernal's jump table, the entries BASIC calls, named for what they do. Their contracts are the kernal's;
; the old names are BASIC's (BV20) and Microsoft's.
;; Sets which messages the kernal prints: bit 7 of A for the control messages, bit 6 for the errors.
;; Also: SETMSG (BV20)
KernalSetMessages = $FF90

;; The bit of <KernalSetMessages>' mode that turns on the control messages, such as SEARCHING and LOADING, which BASIC
;; wants in direct mode.
KERNAL_CONTROL_MESSAGES = $80

;; Returns the top of the RAM for BASIC in X/Y, with carry set, or sets it from X/Y, with carry clear.
KernalMemoryTop = $FF99

;; Returns the bottom of the RAM for BASIC in X/Y, with carry set, or sets it from X/Y, with carry clear.
KernalMemoryBottom = $FF9C

;; Returns the status of the last input or output in A.
;; Also: READST (BV20)
KernalReadStatus = $FFB7

;; Sets the logical file number (A), the device (X) and the secondary address (Y) for OPEN, LOAD and SAVE.
KernalSetFile = $FFBA

;; Sets the file name for OPEN, LOAD and SAVE: A characters at X/Y.
KernalSetFileName = $FFBD

;; Opens the logical file that <KernalSetFile> and <KernalSetFileName> described; carry set on an error, code in A.
KernalOpen = $FFC0

;; Closes logical file A; carry set on an error, code in A.
KernalClose = KernalOpen + 3

;; Makes logical file X the input channel; carry set on an error, code in A.
KernalSelectInput = KernalClose + 3

;; Makes logical file X the output channel; carry set on an error, code in A.
KernalSelectOutput = KernalSelectInput + 3

;; Puts input back to the keyboard and output to the screen.
;; Also: CQCCHN (M6502), CCCHN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), CLSCHN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
KernalResetChannels = KernalSelectOutput + 3

;; Reads a character from the input channel into A; carry set on an error, code in A.
;; Also: CQINCH (M6502), CINCH (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalCharacterIn = KernalResetChannels + 3

;; Writes the character in A to the output channel; carry set on an error, code in A.
KernalCharacterOut = KernalCharacterIn + 3

;; Loads (A = 0) or verifies (A = 1) the file <KernalSetFile> and <KernalSetFileName> described, at X/Y when the
;; secondary address is 0; returns the end address in X/Y, or carry set on an error, code in A.
KernalLoad = KernalCharacterOut + 3

;; Saves memory from the address in the zero-page pair at A up to X/Y; carry set on an error, code in A.
KernalSave = KernalLoad + 3

;; Sets the jiffy clock from A (the lowest byte), X and Y (the highest).
;; Also: SETTIM (BV20)
KernalSetClock = KernalSave + 3

;; Reads the jiffy clock into A (the lowest byte), X and Y (the highest).
;; Also: RDTIM (BV20)
KernalReadClock = KernalSetClock + 3

;; Tests the STOP key: zero set while it is down. BASIC calls it through <CheckStop>.
KernalTestStopKey = KernalReadClock + 3

;; Gets a character from the input channel without waiting, 0 when there is none; carry set on an error, code in A.
;; BASIC calls it through <GetCharacter>.
KernalGetInput = KernalTestStopKey + 3

;; Forgets every open file and resets the channels.
;; Also: CQCALL (M6502), CCALL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CloseAllFiles = KernalGetInput + 3

;; Reads the cursor's row and column into X and Y, with carry set, or moves the cursor there, with carry clear.
;; Also: PLOT (BV20)
KernalPlot = $FFF0

;; Returns the address of the I/O, the first VIA's, in X/Y.
;; Also: RDBAS (BV20)
KernalIoBase = $FFF3

;; What RS-232's OPEN and CLOSE return in A, with carry set, after moving the top of memory to X/Y for their buffers:
;; not an error, but a signal that BASIC's own top has moved.
KERNAL_MEMORY_TOP_MOVED = $F0

;; <IoStatus>: bytes that `VERIFY` found different (and, on tape, bytes that both copies of a block had wrong).
STATUS_SECOND_PASS_ERROR = $10

;; The Datasette's device number, the default for `LOAD`, `SAVE` and `OPEN`.
DEVICE_TAPE = 1

;; The screen's device number; this and the devices above it are not tape or RS-232.
DEVICE_SCREEN = 3

;; The offset, from the address <KernalIoBase> returns, of the first VIA's timer 1 counter, whose two bytes `RND(0)`
;; reads.
VIA_TIMER1_LOW = 4

;; The offset of the first VIA's timer 2 counter, whose two bytes `RND(0)` also reads.
VIA_TIMER2_LOW = 8
.else
; PET kernal jump table, named as Microsoft's BASIC calls its entries.
;; Execute BASIC's OPEN.
;; Also: CQOPEN (M6502), COPEN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalOpen = $FFC0

;; Execute BASIC's CLOSE.
;; Also: CQCLOS (M6502), CCLOS (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalClose = KernalOpen + 3

;; Select a logical channel for input.
;; Also: CQOIN (M6502), COIN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalSelectInput = KernalClose + 3

;; Select a logical channel for output.
;; Also: CQOOUT (M6502), COOUT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalSelectOutput = KernalSelectInput + 3

;; Restore the default input and output channels.
;; Also: CQCCHN (M6502), CCCHN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), CLSCHN (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
KernalResetChannels = KernalSelectOutput + 3

;; Read a character from the current input.
;;
;; BASIC 4's source and reconstructions (CBM4S79, HV4, HV4R) also call it `INCHR`, which in BASIC 1 and 2 is BASIC's
;; own label for another routine; the lineage rule would give the name to those builds too, so it stays in prose.
;; Also: CQINCH (M6502), CINCH (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalCharacterIn = KernalResetChannels + 3

;; Write a character to the current output.
;; Also: OUTCH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalCharacterOut = KernalCharacterIn + 3

;; Execute BASIC's LOAD.
;; Also: CQLOAD (M6502), CLOAD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalLoad = KernalCharacterOut + 3

;; Execute BASIC's SAVE.
;; Also: CQSAVE (M6502), CSAVE (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalSave = KernalLoad + 3

;; Execute BASIC's VERIFY.
;; Also: CQVERF (M6502), CVERF (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalVerify = KernalSave + 3

;; Execute BASIC's SYS.
;; Also: CQSYS (M6502), CSYS (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalSys = KernalVerify + 3

;; Test the `STOP` key.
;; Also: ISCNTC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckStop = KernalSys + 3

;; Get one character for BASIC's `GET`.
;; Also: CZGETL (M6502), CGETL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
GetCharacter = CheckStop + 3

;; Close all open channels.
;; Also: CQCALL (M6502), CCALL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CloseAllFiles = GetCharacter + 3
.endif

.if EXTENDED_DISK_VECTORS
; BASIC 4's jump table (CBM4S79, HV4, HV4R) names these entries CONCAT, DOPEN, DCLOSE, RECORD, FORMAT, COLECT, BACKUP,
; DCOPY, APPEND, DSAVE, DLOAD, DCAT, RENAME, SCRATC and READDS. DCAT, SCRATC and READDS are cited on their entries;
; the overlay and the kernal listings give the other twelve to BASIC's handlers, so they are named only in prose,
; here and, for DCOPY, on <KernalCopy>.

;; Concatenate two files.
;; Also: CQCONC (UNKN)
KernalConcat = KernalOpen - 45

;; Open a disk file.
;; Also: CQDOPN (UNKN)
KernalDiskOpen = KernalConcat + 3

;; Close disk files.
;; Also: CQDCLS (UNKN)
KernalDiskClose = KernalDiskOpen + 3

;; Position a relative record.
;; Also: CQRECD (UNKN)
KernalRecord = KernalDiskClose + 3

;; Prepare disk media.
;; Also: CQFORM (UNKN)
KernalHeader = KernalRecord + 3

;; Validate the disk block allocation map.
;; Also: CQCOLL (UNKN)
KernalCollect = KernalHeader + 3

;; Copy a whole disk.
;; Also: CQBACK (UNKN)
KernalBackup = KernalCollect + 3

;; Copy a file. BASIC 4's jump table (CBM4S79, HV4, HV4R) calls this entry DCOPY, a name the overlay gives
;; `Statements::Copy`, so it is named here only in prose.
;; Also: CQCOPY (UNKN)
KernalCopy = KernalBackup + 3

;; Open a file to append.
;; Also: CQAPND (UNKN)
KernalAppend = KernalCopy + 3

;; Save a BASIC program to disk.
;; Also: CQDSAV (UNKN)
KernalDiskSave = KernalAppend + 3

;; Load a BASIC program from disk.
;; Also: CQDLOD (UNKN)
KernalDiskLoad = KernalDiskSave + 3

;; List a disk directory.
;; Also: CQDCAT (UNKN), DCAT (CBM4S79, HV4, HV4R)
KernalDirectory = KernalDiskLoad + 3

;; Rename a disk file.
;; Also: CQRENM (UNKN)
KernalRename = KernalDirectory + 3

;; Scratch a disk file.
;; Also: CQSCRA (UNKN), SCRATC (CBM4S79, HV4, HV4R)
KernalScratch = KernalRename + 3

;; Read the disk status.
;; Also: CQRDDS (UNKN), READDS (CBM4S79, HV4, HV4R)
KernalReadDiskStatus = KernalScratch + 3
.endif
