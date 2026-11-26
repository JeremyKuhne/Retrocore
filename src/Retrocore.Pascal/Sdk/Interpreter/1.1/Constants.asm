; retrocore: style=strict
;; Constants: numbers with a meaning in the p-machine and its system.

; The opcodes.

;; The first opcode <OpcodeTable> has a routine for. The ones below it are <SLDC> 0-127, which <Fetch> pushes itself.
FIRST_TABLE_OPCODE = $80

; Mark stack frames.

;; The size of a mark stack frame, in bytes. A call places the procedure's frame this far, plus its data, below
;; <KP>, and its locals follow the frame.
MSCW_SIZE = 12

;; Where a mark stack frame keeps its static link: the frame of the procedure one lexical level out.
MSCW_STATIC_LINK = 0

;; The size of the word a call keeps the caller's <KP> in, just below the new frame.
KP_LINK_SIZE = 2

; Execution errors, numbered as SYSTEM.PASCAL's PRINTERR segment numbers its messages. SYSTEM.APPLE does not raise
; 7 (NIL pointer reference), 14 (Programmed HALT) or 15 (Programmed break-point).

;; Execution error 1, which SYSTEM.PASCAL prints as "Value range error".
ERROR_VALUE_RANGE = 1

;; Execution error 2, "No proc in seg-table".
ERROR_NO_PROC_IN_SEG_TABLE = 2

;; Execution error 3, "Exit from uncalled proc".
ERROR_EXIT_FROM_UNCALLED_PROC = 3

;; Execution error 4, "<Stack> overflow".
ERROR_STACK_OVERFLOW = 4

;; Execution error 5, "<RealMath::PopIntegerAsReal::Integer> overflow".
ERROR_INTEGER_OVERFLOW = 5

;; Execution error 6, "<Divide> by zero".
ERROR_DIVIDE_BY_ZERO = 6

;; Execution error 8, "Program interrupted by user".
ERROR_INTERRUPTED = 8

;; Execution error 9, "System IO error".
ERROR_SYSTEM_IO = 9

;; Execution error 10, a user I/O error, which SYSTEM.PASCAL prints with the I/O result's own message.
ERROR_USER_IO = 10

;; Execution error 11, "<ExecutionError::Unimplemented> instruction".
ERROR_UNIMPLEMENTED = 11

;; Execution error 12, "Floating point error".
ERROR_FLOATING_POINT = 12

;; Execution error 13, "String overflow".
ERROR_STRING_OVERFLOW = 13

; Memory.

;; Where a stack overflow puts <NP>, out of the error handler's way, before it reports the error.
OVERFLOW_HEAP = $6200

;; Where a stack overflow puts <KP>, so the error handler's call has room below it.
OVERFLOW_STACK = $8000

; Unpacked reals. The floating-point routines unpack a real into 6 bytes of zero page, RealMath's Right and Left or
; Result, and
; reach its parts with X = the real's address and these as offsets.

;; An unpacked real's sign, in bit 7.
REAL_SIGN = 0

;; An unpacked real's exponent.
REAL_EXPONENT = 1

;; An unpacked real's mantissa: 3 bytes, high first, with the hidden 1 bit restored.
REAL_MANTISSA = 2

;; An unpacked real's guard byte, for rounding.
REAL_GUARD = 5

; Card types, which Startup records in SlotTypes from each slot ROM's bytes at $Cn05 and $Cn07.

;; A Disk II controller.
CARD_DISK_II = 2

;; A communications card, its ACIA's registers at the slot's I/O addresses.
CARD_SERIAL = 3

;; A card with the Pascal 1.1 ID bytes, whose routines are at fixed addresses in its $C800 ROM.
CARD_PASCAL_FIXED = 4

;; A parallel printer card.
CARD_PARALLEL = 5

;; A card with the Pascal 1.1 firmware entries, its routines' offsets at $Cn0D-$Cn10.
CARD_PASCAL_FIRMWARE = 6

; I/O results, which the BIOS and the unit routines leave in X and SysIoResult.

;; No error.
IO_OK = 0

; Characters and control keys.

;; Control-G: beeps.
ASCII_BEL = $07

;; Control-H: moves the cursor left.
ASCII_BS = $08

;; Line feed.
ASCII_LF = $0A

;; Carriage return.
ASCII_CR = $0D

;; DLE, which with the count byte after it stands for a run of blanks.
ASCII_DLE = $10

;; Escape: drops the next character.
ASCII_ESC = $1B

;; Blank.
ASCII_SPACE = $20

;; Control-@, which the keyboard gives for Control-Shift-P.
CTRL_AT = $00

;; Control-A: shows the other half of the 80-column screen, and stops the view following the cursor.
CTRL_A = $01

;; Control-E: switches the upper case lock on or off.
CTRL_E = $05

;; Control-K: <ConsoleCheck> turns it into "[", which the keyboard has no key for. As output, it clears to the end of
;; the screen.
CTRL_K = $0B

;; Control-L: clears the screen.
CTRL_L = $0C

;; Control-R: shows capital letters inverse.
CTRL_R = $12

;; Control-T: locks the keyboard in upper case, and shows capital letters normally.
CTRL_T = $14

;; Control-W: upper case for the next key.
CTRL_W = $17

;; Control-Y: moves the cursor to the top left.
CTRL_Y = $19

;; Control-Z: makes the view follow the cursor.
CTRL_Z = $1A

;; Control-\: moves the cursor right.
CTRL_BACKSLASH = $1C

;; Control-], which the keyboard gives for Control-Shift-M.
CTRL_RIGHT_BRACKET = $1D

;; Control-^, which the keyboard gives for Control-Shift-N.
CTRL_CARET = $1E

;; Control-_: moves the cursor up.
CTRL_UNDERSCORE = $1F

; Units, and the requests and results of unit calls.

;; The lowest unit number.
FIRST_UNIT = 1

;; The console, which echoes what it reads: CONSOLE:.
UNIT_CONSOLE = 1

;; The console without echo: SYSTERM:.
UNIT_SYSTERM = 2

;; The graphics screen.
UNIT_GRAPHICS = 3

;; The boot disk, slot 6's drive 1.
UNIT_BOOT_DISK = 4

;; The second disk, slot 6's drive 2.
UNIT_SECOND_DISK = 5

;; The printer.
UNIT_PRINTER = 6

;; The remote line's input.
UNIT_REMOTE_IN = 7

;; The remote line's output. <UNITCLEAR at UnitIo::CspUCLEAR> and <UNITSTATUS at UnitIo::CspUSTAT> take unit 7 as this
;; one.
UNIT_REMOTE_OUT = 8

;; The highest unit number: units 9 to 12 are disks in slots 4 and 5.
LAST_UNIT = 12

;; The units the interpreter has, 0-12: <UnitTable>'s entries, and the DLE states <Initialize> clears.
UNIT_COUNT = 13

;; The size of a <UnitTable> entry.
UNIT_ENTRY_SIZE = 2

;; Bit 7 of a unit number: an attached driver's unit, its driver's number in bits 0-6.
ATTACHED_UNIT = $80

;; Read: <UNITREAD at UnitIo::CspUREAD>.
REQUEST_READ = 0

;; Write: <UNITWRITE at UnitIo::CspUWRITE>.
REQUEST_WRITE = 1

;; Clear: <UNITCLEAR at UnitIo::CspUCLEAR>.
REQUEST_CLEAR = 2

;; Status: <UNITSTATUS at UnitIo::CspUSTAT>.
REQUEST_STATUS = 4

;; I/O result 2, "illegal unit #": no such unit.
IO_BAD_UNIT = 2

;; I/O result 3, "illegal IO request": the unit cannot read, or cannot write.
IO_BAD_REQUEST = 3

;; I/O result 9, which SYSTEM.PASCAL prints as "vol not found": the unit has no device for the call.
IO_NO_DEVICE = 9

; The unit table.

;; A <UnitTable> entry for a character device, which the unit routines handle by its unit number; they test
;; its high byte.
CHARACTER_DEVICE = $FFFF

; Mark stack frames, procedure attributes and segments.

;; Where a mark stack frame keeps its dynamic link: the caller's <MP>.
MSCW_DYNAMIC_LINK = 2

;; Where a mark stack frame keeps the caller's <JTAB>.
MSCW_JTAB = 4

;; Where a mark stack frame keeps the caller's <SEG>.
MSCW_SEG = 6

;; Where a mark stack frame keeps the caller's <IPC>, the p-code after the call: where <RNP at OpRNP> returns to.
MSCW_IPC = 8

;; Where a mark stack frame keeps the 6502 stack pointer once the call has pulled the parameters, for the return to
;; put back.
MSCW_STACK = 10

;; Where a procedure's attributes keep its number, a byte: 0 for an assembled procedure.
ATTR_PROCEDURE_NUMBER = 0

;; Where a procedure's attributes keep its lexical level, a byte, negative for the system's outer block. An assembled
;; procedure keeps the number of its data segment here instead (see <LoadSegment>).
ATTR_LEXICAL_LEVEL = 1

;; Where a procedure's attributes keep a self-relative pointer to the code it starts at: the first p-code, or an
;; assembled procedure's first instruction.
ATTR_ENTER = -2

;; Where a procedure's attributes keep a self-relative pointer to its exit code, which <EXIT at CspEXIT> runs.
ATTR_EXIT = -4

;; Where a procedure's attributes keep the size of its parameters, in bytes.
ATTR_PARAMETER_SIZE = -6

;; Where a procedure's attributes keep the size of its local data, in bytes, not counting the parameters.
ATTR_DATA_SIZE = -8

;; Where a <SegmentTable> entry keeps the segment's unit, a byte.
SEGMENT_UNIT = 0

;; Where a <SegmentTable> entry keeps the segment's first block, a word: 0 for a data segment, which is not on disk.
SEGMENT_BLOCK = 2

;; Where a <SegmentTable> entry keeps the segment's size in bytes, a word.
SEGMENT_SIZE = 4

;; The size of a <SegmentTable> entry: the segment's unit, its first block and its size in bytes, a word each.
SEGMENT_TABLE_ENTRY_SIZE = 6

; Comparisons, as the comparison handlers pass them to CompareSets in Comparison.

;; The outcome equal, and the kind <EQU at OpEQU> tests for.
COMPARISON_EQUAL = 1

;; The outcome less: the lower operand is less than the top one. The kind <LES at OpLES> tests for.
COMPARISON_LESS = 2

;; The outcome greater: the lower operand is greater than the top one. The kind <GRT at OpGRT> tests for.
COMPARISON_GREATER = 4

;; The kind <LEQ at OpLEQ> tests for: less or equal.
COMPARISON_LESS_OR_EQUAL = COMPARISON_LESS | COMPARISON_EQUAL

;; The kind <GEQ at OpGEQ> tests for: greater or equal.
COMPARISON_GREATER_OR_EQUAL = COMPARISON_GREATER | COMPARISON_EQUAL

;; The kind <NEQ at OpNEQ> tests for: less or greater.
COMPARISON_NOT_EQUAL = COMPARISON_LESS | COMPARISON_GREATER

; Flags in the console and keyboard bytes.

;; <ConsoleCardFlag>'s bit 2, which <Startup> sets when the console's card initializes.
CONSOLE_CARD_READY = $04

;; <KeyboardCase>'s bit 7: <ConsoleCheck> leaves letters in upper case.
KEYBOARD_UPPER = $80

;; <KeyboardCase>'s bit 6: <KEYBOARD_UPPER> is for the next key only.
KEYBOARD_ONE_KEY = $40

;; <InverseCapitals> with bit 7 set: <PutScreen> shows capital letters inverse.
INVERSE_CAPITALS = $80

;; The columns a text page holds, and the view shows.
PAGE_COLUMNS = 40

; Packed reals.

;; A real's size on the stack, in bytes.
REAL_SIZE = 4

;; The sign bit: an unpacked real's <REAL_SIGN> byte for a negative real, and bit 7 of a packed real's high byte.
REAL_NEGATIVE = $80

; Card types not in the list above.

;; The type <Startup> records for a slot whose ROM matches no card it knows. Its loop over the known types ends at it.
CARD_UNKNOWN = 1

; 6502 opcodes the code writes or patches.

;; The 6502's JMP absolute opcode.
JMP_ABSOLUTE = $4C

;; The 6502's JMP indirect opcode.
JMP_INDIRECT = $6C

;; The 6502's LDA absolute opcode.
LDA_ABSOLUTE = $AD

;; The 6502's BEQ opcode, which <SetsEqual> ends bank 1 with: its offset is the first byte of $E000-$FFFF.
BEQ_RELATIVE = $F0

; Words.

;; The bits in a word: the rounds of a 16-bit multiplication or division.
WORD_BITS = 16
