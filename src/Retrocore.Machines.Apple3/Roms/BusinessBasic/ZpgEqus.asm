; retrocore: style=strict
;; ZpgEqus: BASIC's zero page, its work page, the header, the buffers and the dispatch tables
;;
;; BASIC's zero page, the X-bytes of its pointers, its work area in page $1E, the start of SOS.INTERP with the buffers
;; that come before the code, and the dispatch tables for statements, functions and operators.
;;
;; BASIC is a SOS interpreter: its zero page is page $1A, and the X-byte page that goes with it is page $16. An
;; indirect access through a zero-page pointer, such as an LDA through <ProgramStart>, takes its bank from the pointer's
;; X-byte, the byte <X_BYTE_OFFSET> ($1601) past the pointer's own address. Each pointer's X-byte has the pointer's
;; name with XByte after it: <ProgramStart>'s is <ProgramStartXByte>.
;;
;; A pointer into the program and its data is three bytes: the address's low and high bytes in zero page, and the
;; X-byte, $80 plus the bank pair. Through bank pair $80+n, addresses $0000-$7FFF are bank n's $2000-$9FFF and
;; addresses from $8000 are the next bank's. BASIC keeps the high byte from <POINTER_PAGE_FIRST> to
;; <POINTER_PAGE_LIMIT>-1 ($02-$81): pages 0 and 1 of a bank pair can't be reached this way, so a pointer that passes
;; page $81 goes on at page $02 of the next bank pair (one more in the X-byte), the same memory.
;; <Memory::NormalizeAfterAdd> and <Memory::NormalizeAfterSubtract> keep pointers in that form after arithmetic.
;;
;; Much of zero page has several names, one for each job the byte does at a different time: writing one overwrites
;; the others.
;;
;; The names say what each location is; Apple's names from its Business BASIC 1.3 listing are in each one's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; Sizes and the load address
; ---------------------------------------------------------------------------------------------------------------------

;; Where the stack pointer starts when BASIC resets its stack.
;; Also: STKEND (BB13)
STACK_END = $FE

;; The size of <EndOfFileHandlers>: three bytes for each of files 1-10 and `ON KBD`.
;; Also: EOFSIZ (BB13)
END_OF_FILE_HANDLERS_SIZE = 3 * (FILE_COUNT + 1)
.assert END_OF_FILE_HANDLERS_SIZE = 33, "Three bytes for each of 10 files and ON KBD."

.if DEBUG
;; Where SOS.INTERP's code loads: lower, for the debugger build.
;; Also: B3PRT1 (BB13)
LoadAddress = $3A00
.else
.if VERSION = 123
;; Where SOS.INTERP's code loads.
;; Also: B3PRT1 (BB13)
LoadAddress = $5200
.else
;; Where SOS.INTERP's code loads.
;; Also: B3PRT1 (BB13)
LoadAddress = $5000
.endif
.endif
; BASIC runs from its load address up to $B7FF.

;; The value 1.3's program selector leaves in locations 0 and 1, to say it started BASIC.
;; Also: SELFLG (BB13)
SELECTOR_SIGNATURE = $EE

;; The stack levels BASIC keeps free.
;; Also: NUMLEV (BB13)
STACK_LEVELS = 19

; The values of <ValueType>, the type of the value just evaluated.

;; <ValueType> for a real, or for an integer, which <IntegerType> tells apart; a formula of numbers asks for it, and it
;; marks a value as nothing to free.
;; Also: VREAL (BB13)
VALUE_TYPE_REAL = 0

;; <ValueType> before a formula that may give any type: a type the evaluator is never left with.
VALUE_TYPE_ANY = $20

;; <ValueType> for a long integer: bit 6, which `BIT` of <ValueType> copies into the overflow flag.
;; Also: VLNT (BB13)
VALUE_TYPE_LONG_INTEGER = $40

;; <ValueType> for a string: bit 7, which `BIT` of <ValueType> copies into the negative flag; <FindVariable>'s type for
;; a string variable too.
;; Also: STRTYP (BB13), VSTR (BB13)
VALUE_TYPE_STRING = $FF

; The type byte after each string in string space, which says what holds the string.

;; A string's type byte: a temporary.
;; Also: TEMPTYP (BB13)
STRING_TYPE_TEMPORARY = 1

;; A string's type byte: an array element's.
;; Also: ARYTYP (BB13)
STRING_TYPE_ARRAY_ELEMENT = $81

;; A string's type byte: a simple variable's.
;; Also: SIMTYP (BB13)
STRING_TYPE_SIMPLE_VARIABLE = $41

;; The lowest high byte of a pointer through a bank pair.
;; Also: MINPG (BB13)
POINTER_PAGE_FIRST = 2

;; One past the highest high byte of a pointer through a bank pair.
;; Also: MAXPG (BB13)
POINTER_PAGE_LIMIT = $82

;; The bytes of information after each string in string space: its type byte and the pointer back to its variable.
;; Also: INFOSIZ (BB13)
STRING_INFORMATION_SIZE = 3

;; The size of a string descriptor: the length, then the address.
;; Also: STRSIZ (BB13)
DESCRIPTOR_SIZE = 3

;; The count of string temporaries in <TemporaryDescriptors>.
;; Also: NUMTMP (BB13)
TEMPORARY_COUNT = 4

;; The size of <OperatorStack>.
OPERATOR_STACK_SIZE = 32

;; The size of <OperandStack>.
OPERAND_STACK_SIZE = 128

;; The characters each of 1.3's pathname buffers holds, after its length byte.
PATH_BUFFER_SIZE = 80

;; The size of <NameBuffer>.
NAME_BUFFER_SIZE = 128

;; The size of <CatalogBuffer>.
CATALOG_BUFFER_SIZE = 80

;; The size of <UsingDigits>.
USING_DIGITS_SIZE = 48

;; The size of <InputBuffer>.
INPUT_BUFFER_SIZE = 256

; The characters the console and the messages use.

;; The bell.
CHARACTER_BELL = 7

;; A line feed.
CHARACTER_LINE_FEED = 10

;; A return.
CHARACTER_RETURN = 13

;; Control-O, the console's code that turns the screen back on (the SOS console driver's control code $0F, in
;; Sos/Drivers/Console/ConsFctn.asm).
CHARACTER_SCREEN_ON = 15

; ---------------------------------------------------------------------------------------------------------------------
; Zero page
; ---------------------------------------------------------------------------------------------------------------------

    .dum 0
    jmp ColdStart                           ; Nothing is assembled here: locations 0-2 are left free

; This storage changes as BASIC runs; none of it could be in ROM.

;; A character that ends the string being scanned, such as a quote or a comma.
;; See: <EndDelimiter>
;; Also: CHARAC (BB13)
Delimiter:
    .res 1

;; A one-byte integer: the low byte of <Functions::Int>'s result.
;; Also: INTEGR (BB13)
SmallInteger = Delimiter

;; The other character that ends the string being scanned.
;; See: <Delimiter>
;; Also: ENDCHR (BB13)
EndDelimiter:
    .res 1

;; A data file item's descriptor, such as <DATA_ITEM_INTEGER>, in `READ#` and `WRITE#`.
;; Also: DSCRPT (BB13)
DataItemDescriptor = EndDelimiter

;; A counter for any routine that needs one.
;; Also: COUNT (BB13)
Counter:
    .res 1

;; Whether the variable being looked up is being dimensioned by `DIM`.
;;
;; It must come just before <ValueType>.
;; Also: DIMFLG (BB13)
Dimensioning:
    .res 1

;; A place to keep Y, or another count or flag, for a while.
;; Also: KIMY (BB13)
KeptY = Dimensioning

;; The type of the value just evaluated: 0 for a real or an integer, $40 for a long integer, $FF for a string.
;;
;; An integer reads as 0 here, with <IntegerType> set. Bit 7 set means a string and bit 6 set a long integer, which
;; the code tests with BIT.
;; See: <IntegerType>
;; Also: VALTYP (BB13)
ValueType:
    .res 1

;; Bit 7 set when the variable just found or the value just evaluated is an integer (a % variable).
;; Also: INTFLG (BB13)
IntegerType:
    .res 1

;; While a line is crunched into tokens, whether keywords are crunched: bit 7 set stops it until the next colon, and
;; bit 6 clear until the next comma.
;;
;; `DATA` and some file commands set it so their unquoted text stays as typed.
;; See: <Tokenize>
;; Also: DORES (BB13)
TokenizeState:
    .res 1

;; Whether a garbage collection was tried while looking for string space.
;; Also: GARBFL (BB13)
CollectionState = TokenizeState

;; A place to keep X for a while.
;; Also: XSAV (BB13)
SavedX = TokenizeState

;; Nonzero when the variable being looked up may not be subscripted, as for a function's name in `DEF FN` and `FN`.
;; Also: SUBFLG (BB13)
SubscriptMode:
    .res 1

;; A place to keep Y, or another byte, for a while.
;; Also: YSAVE (BB13)
SavedY:
    .res 1

;; Which statement is taking values: `INPUT`, `GET` or `READ`; `LIST` and the long-integer routines use it too.
;; Also: INPFLG (BB13)
InputMode:
    .res 1

;; The sign of the tangent while `TAN` works.
;; Also: TANSGN (BB13)
TangentSign:
    .res 1

;; While <Float::ReadNumber> reads a number, whether any digits were seen.
;; Also: ANYNUM (BB13)
DigitsSeen = TangentSign

;; The output file: OutputFileNumber is where output goes now, OutputFileNumber+1 where it goes between statements.
;;
;; $FF in either means the console; `PRINT#` and the like set OutputFileNumber for one statement.
;; Also: FILNO (BB13)
OutputFileNumber:
    .res 2

;; The reference number of the `EXEC` file, 0 when `EXEC` is not running.
;; Also: INFLNO (BB13)
ExecFile:
    .res 1

;; The file number of the file operation in progress.
;; Also: SVFLNO (BB13)
CurrentFileNumber:
    .res 1

;; A JMP, through which BASIC calls a routine whose address it puts in FunctionJump+1 and FunctionJump+2.
;;
;; <ResetInterpreter> stores the JMP opcode. Apple's listing also names FunctionJump+1 SIZE, for AppleSoft's garbage
;; collector; nothing in Business BASIC uses that name, so it is left out (as DOS's unused MULT is).
;; See: <Modules::CallModule>, <Modules::CallBasic>
;; Also: JMPER (BB13)
FunctionJump:
    jmp 60000

;; How far a block of memory moves, for the move routines, with its X-byte at <MoveDistanceXByte>.
;; Also: DELTA (BB13)
MoveDistance:
    .res 2

;; Used by the variable search, <FindVariable>: the value's size for the variable's type, then the size of the
;; variable's entry.
;;
;; Microsoft's BASICs keep the variable's name here; Business BASIC's names are longer, and are compared where they
;; are.
;; Also: VARNAM (BB13)
VariableSizes:
    .res 2

;; The address of the value of the variable <FindVariable> just found or made, with its X-byte at
;; <VariablePointerXByte>.
;; Also: VARPNT (BB13)
VariablePointer:
    .res 2

;; A pointer that nothing here names directly; its other names are used.
;; Also: OPPTR (BB13)
OperatorPointer:
    .res 2

;; A pointer into a list of variables, as `INPUT` and `READ` go through it.
;; Also: VARTXT (BB13)
VariableListPointer = OperatorPointer

;; The relational operators found: bit 0 >, bit 1 =, bit 2 <.
;; Also: DOMASK (BB13)
RelationMask = TangentSign

;; A pointer used by `DEF FN` and `FN`, with its X-byte at <FunctionPointerXByte>.
;; Also: DEFPNT (BB13)
FunctionPointer:
    .res 2

;; How far strings move down in a garbage collection: the free bytes found so far.
;; Also: GRBPNT (BB13)
CollectorDistance = FunctionPointer

;; `WINDOW`'s left column, while it works.
;;
;; <WindowLeft>, <WindowRight>, <WindowBottom> and <WindowTop> are only `WINDOW`'s work space, which
;; <FloatTemporary3> runs over.
;; Also: SLEFT (BB13)
WindowLeft:
    .byte 0

;; The offset of the current file's control block in <FileControlBlocks>.
;; Also: FCBNDX (BB13)
FileControlBlockIndex = WindowLeft

;; `WINDOW`'s right column, while it works; Apple named it for the width.
;; Also: SWIDTH (BB13)
WindowRight:
    .byte 0

;; `WINDOW`'s bottom line, while it works.
;; Also: SBOTTOM (BB13)
WindowBottom:
    .byte 0

;; `WINDOW`'s top line, while it works.
;; Also: STOPS (BB13)
WindowTop:
    .byte 0

;; The column the console's output has reached.
;; Also: TRMPOS (BB13)
TerminalPosition:
    .res 1

;; A line number, as <ReadLineNumber> reads it or `GOTO` looks for it.
;; Also: LINNUM (BB13)
LineNumber:
    .word 0

;; The address in zero page of the next free string temporary in <TemporaryDescriptors>.
;; Also: TEMPPT (BB13)
NextTemporary:
    .res 1

;; The address of the string temporary used last.
;; Also: LASTPT (BB13)
LastTemporary:
    .res 2

;; The string temporaries: <TEMPORARY_COUNT> descriptors of <DESCRIPTOR_SIZE> bytes, for strings that are parts of an
;; expression.
;; Also: TEMPST (BB13)
TemporaryDescriptors:
    .res DESCRIPTOR_SIZE * TEMPORARY_COUNT

;; A general pointer, with its X-byte at <Pointer1XByte>.
;; Also: INDEX1 (BB13), INDEX (BB13)
Pointer1:
    .res 2

;; A second general pointer, with its X-byte at <Pointer2XByte>.
;; Also: INDEX2 (BB13)
Pointer2:
    .res 2

; ---------------------------------------------------------------------------------------------------------------------
; The program, the variables and the strings
;
; From low memory up: the program from ProgramStart, the arrays from ArraysStart, the simple variables from
; VariablesStart to VariablesEnd, free memory, then the strings, which grow down from MemoryTop; StringsBottom is the
; lowest. INVOKE's modules take a segment of their own, from ModulesStart to ModulesEnd.
;
; A simple variable's entry is its length (one byte), its name, a type byte, then its value: 4 bytes for a real, 2
; for an integer, 8 for a long integer. A string variable's value is the string's length and a two-byte pointer.
; An array's entry has its name and type, the count of dimensions, two bytes for each dimension's size, then the
; values. Each string in string space is followed by STRING_INFORMATION_SIZE bytes: a type byte (a STRING_TYPE_
; value) and a pointer back to the variable's descriptor, which the garbage collector uses.
; ---------------------------------------------------------------------------------------------------------------------

;; The start of the program, with its X-byte at <ProgramStartXByte>.
;;
;; The first line starts here. Each line is one byte of length, which is the offset to the next line, the two-byte
;; line number, the line's tokens, then a zero; a length of zero ends the program. The byte before ProgramStart is
;; always zero, which <RewindTextPointer> sees to. <ColdStart> sets ProgramStart one byte into the memory segment SOS
;; gives BASIC.
;; See: <ArraysStart>, <FindLine>
;; Also: TXTTAB (BB13)
ProgramStart:
    .res 2

;; The start of the simple variables, just past the arrays, with its X-byte at <VariablesStartXByte>.
;;
;; <ClearVariables> sets it to <ArraysStart>, so that there are no variables, and it moves up when an array is made.
;; Apple's listing also calls it SMVARS, the name its variable search uses.
;; See: <VariablesEnd>
;; Also: VARTAB (BB13), SMVARS (BB13)
VariablesStart:
    .res 2

;; The start of the arrays, just past the program, with its X-byte at <ArraysStartXByte>.
;;
;; It moves with the end of the program, as lines are entered and deleted or a program is loaded.
;; Also: ARYTAB (BB13)
ArraysStart:
    .res 2

;; The end of the simple variables, the first free byte above them, with its X-byte at <VariablesEndXByte>.
;;
;; A new simple variable is added here; <ClearVariables> sets it to <ArraysStart>. In Microsoft's BASICs, which keep the
;; arrays above the simple variables, the same pointer is the end of the arrays.
;; Also: STREND (BB13)
VariablesEnd:
    .res 2

;; The bottom of the strings in use, with its X-byte at <StringsBottomXByte>: a new string is taken from just below
;; it.
;;
;; <ClearVariables> sets it to <MemoryTop>, freeing every string.
;; See: <Strings::ReserveSpace>, <NewString>
;; Also: FRETOP (BB13)
StringsBottom:
    .res 2

;; The start of the memory `INVOKE` loads modules into, with its X-byte at <ModulesStartXByte>.
;; See: <ModulesEnd>, <ModuleLoadPointer>
;; Also: INVTAB (BB13)
ModulesStart:
    .res 2

;; The end of the invokable modules' memory, below which `INVOKE` builds the table of their procedures, with its
;; X-byte at <ModulesEndXByte>.
;; See: <ModulesStart>
;; Also: PROCTAB (BB13)
ModulesEnd:
    .res 2

;; The string <Strings::ReserveSpace> just made room for, with its X-byte at <NewStringXByte>.
;; Also: FRESPC (BB13)
NewString:
    .res 2

;; The top of the strings' memory, `HIMEM`, with its X-byte at <MemoryTopXByte>.
;; Also: MEMSIZ (BB13), HIMEM (BB13)
MemoryTop:
    .res 2

; ---------------------------------------------------------------------------------------------------------------------
; Line numbers and pointers into the program
; ---------------------------------------------------------------------------------------------------------------------

;; The number of the line running; its high byte is $FF for a statement typed without a line number.
;; Also: CURLIN (BB13)
CurrentLine:
    .res 2

;; The number of the line at which the program stopped, for `CONT`, or was interrupted.
;; Also: OLDLIN (BB13)
StoppedLine:
    .res 2

;; A 16-bit address, for `PEEK`, `POKE` and the like.
;; Also: POKER (BB13)
PokeAddress = LineNumber

;; Where the program stopped, for `CONT`: the statement to run next, with its X-byte at <StoppedTextXByte>.
;; Also: OLDTXT (BB13)
StoppedText:
    .res 2

;; The number of the line of the `DATA` statement `READ` is in, for errors.
;; Also: DATLIN (BB13)
DataLine:
    .res 2

;; Where `READ` takes its next value, with its X-byte at <DataPointerXByte>.
;;
;; `RESTORE` points it at the zero before the program's first line.
;; Also: DATPTR (BB13)
DataPointer:
    .res 2

;; Where `INPUT` or `READ` takes its next value, with its X-byte at <InputPointerXByte>.
;; Also: INPPTR (BB13)
InputPointer:
    .res 2

;; The place in the table of powers of ten <Float::FormatFac> has reached.
;; Also: FDECPT (BB13)
PowerTablePointer = VariablePointer

;; The variable `FOR` or `LET` is assigning to, with its X-byte at <AssignedVariableXByte>.
;; Also: FORPNT (BB13)
AssignedVariable:
    .res 2

;; The place in a keyword's name `LIST` has reached.
;; Also: LSTPNT (BB13)
ListOffset = AssignedVariable

;; The token `LIST` is printing.
;; Also: TKNSAV (BB13)
ListToken = AssignedVariable + 1

;; The file's type, in the file commands.
;; Also: TYPSAV (BB13)
SavedFileType = StoppedLine + 1

;; A pointer to a string descriptor, with its X-byte at <DescriptorPointerXByte>.
;; Also: DSCPNT (BB13)
DescriptorPointer:
    .res 2
    .res 1                                  ; Unused: Apple's listing keeps it for TEMPF3, as Microsoft's layout had

;; The size of a string descriptor, <DESCRIPTOR_SIZE>, kept here for the garbage collector; other routines use it
;; as a temporary.
;; Also: FOUR6 (BB13)
CollectorStep:
    .byte DESCRIPTOR_SIZE

;; The last of <FunctionJump>'s address bytes, which the float code borrows: in addition the unshifted operand's
;; rounding byte (<Float::UnshiftedExtension>), and in `EXP` the rounding byte of its first multiplication.
;; Also: OLDOV (BB13)
FunctionJumpHigh = FunctionJump + 2

;; A third temporary for a packed real, five bytes, which run over <FunctionPointer> and the `WINDOW` bytes from
;; <WindowLeft>.
;; Also: TEMPF3 (BB13)
FloatTemporary3 = FunctionPointer

;; A temporary for a packed real, five bytes: this one, then <DestinationEnd>'s and <DataBufferPointer>'s.
;; Also: TEMPF1 (BB13)
FloatTemporary1:
    .byte 0

;; Where a block move puts its highest byte, with its X-byte at <DestinationEndXByte>.
;; See: <MoveRangeUp>
;; Also: HIGHDS (BB13)
DestinationEnd:
    .res 2

;; The first long-integer operand, for the long-integer routines, which <LongInteger::PointAtOperands> points at <Fac>.
;; Also: PTR1 (BB13)
LongOperand1Pointer = DestinationEnd

;; Where `READ#` and `WRITE#` are in a data file's buffer, with its X-byte at <DataBufferPointerXByte>.
;; Also: NDXPTR (BB13)
DataBufferPointer:
    .res 2

;; The highest byte a block move moves, with its X-byte at <SourceEndXByte>.
;; Also: HIGHTR (BB13)
SourceEnd:
    .res 2

;; The second long-integer operand, which <LongInteger::PointAtOperands> points at <ArgExponent>.
;; Also: PTR2 (BB13)
LongOperand2Pointer = SourceEnd

;; A second temporary for a packed real, five bytes: this one, then <DestinationStart>'s and <SourceStart>'s.
;; Also: TEMPF2 (BB13)
FloatTemporary2:
    .byte 0

;; The length of a data file item, in `READ#` and `WRITE#`.
;; Also: LENSAV (BB13)
DataItemLength = FloatTemporary2

;; Where a block move's last byte went, with its X-byte at <DestinationStartXByte>.
;; Also: LOWDS (BB13)
DestinationStart:
    .res 2

;; The lowest byte a block move moves, with its X-byte at <SourceStartXByte>; the line <FindLine> found.
;; Also: LOWTR (BB13)
SourceStart:
    .res 2

;; Where a long-integer routine puts its result, which <LongInteger::PointAtOperands> points at <Fac>.
;; Also: PTR3 (BB13)
LongResultPointer = DestinationStart

;; The variable entry the variable search is looking at.
;; Also: SRCHPT (BB13)
VariableSearchPointer = SourceEnd

;; A pointer used in building an array.
;; Also: ARYPNT (BB13)
ArrayPointer = DestinationEnd

;; A pointer used by the garbage collector.
;; Also: GRBTOP (BB13)
CollectorTop = SourceStart

;; While <Float::FormatFac> works, the count of digits before the decimal point.
;; Also: DECCNT (BB13)
DigitCount = DestinationStart

;; While <Float::ReadNumber> works, the power of ten so far.
;; Also: TENEXP (BB13)
DecimalExponent = DestinationStart + 1

;; While <Float::ReadNumber> works, whether a decimal point has been read.
;; Also: DPTFLG (BB13)
DecimalPointSeen = SourceStart

;; While <Float::ReadNumber> works, the sign of the exponent.
;; Also: EXPSGN (BB13)
ExponentSign = SourceStart + 1

; ---------------------------------------------------------------------------------------------------------------------
; The floating-point accumulator, its argument, and the arithmetic
; ---------------------------------------------------------------------------------------------------------------------

;; The floating-point accumulator: the exponent, four bytes of mantissa, and the sign.
;;
;; Expressions are worked out here: a two-operand operation, real or long integer, takes its left operand in <Arg>
;; and its right here, and leaves the result here. An integer or long integer uses the same bytes.
;; Also: FAC (BB13)
Fac:

;; The accumulator's exponent, 0 for the value zero.
;; Also: FACEXP (BB13)
FacExponent:
    .byte 0

;; The accumulator's mantissa, its highest byte.
;; Also: FACHO (BB13)
FacMantissa1:
    .byte 0

;; The accumulator's mantissa, its second byte.
;; Also: FACMOH (BB13)
FacMantissa2:
    .byte 0

;; Where a decimal value's digits start, for `PRINT USING` and the long integers' conversions.
;; Also: FACT (BB13)
FacDecimalDigits = FacMantissa2

;; The accumulator's mantissa, its third byte, with its X-byte at <FacMantissa3XByte> for when it holds a pointer.
;; Also: FACMO (BB13)
FacMantissa3:
    .byte 0

;; The accumulator's mantissa, its lowest byte.
;; Also: FACLO (BB13)
FacMantissa4:
    .byte 0

;; The accumulator's sign while it is unpacked: 0 for positive, $FF for negative.
;; Also: FACSGN (BB13)
FacSign:
    .byte 0

;; The sign of the number <Float::ReadNumber> is reading.
;; Also: SGNFLG (BB13)
InputSign:
    .byte 0

;; The count of terms while a polynomial is worked out.
;; Also: DEGREE (BB13)
PolynomialDegree = InputSign

;; Where a string temporary's descriptor is built.
;; Also: DSCTMP (BB13)
NewDescriptor = Fac

;; The integer <Float::ToLongInteger> leaves.
;; Also: INDICE (BB13)
ArrayIndex = FacMantissa3
    .res 3                                  ; The rest of the accumulator, for its longer forms

;; How many more digits <Float::ReadNumber> takes before it rounds, at ten.
;; Also: CNTDIGS (BB13)
DigitsLeft:
    .byte 0
    .byte 0                                 ; Unused

;; The argument: a second floating-point accumulator, laid out like <Fac>, which holds the left operand of a
;; two-operand routine.
;; Also: ARG (BB13)
Arg:

;; The argument's exponent.
;; Also: ARGEXP (BB13)
ArgExponent:
    .byte 0

;; The argument's mantissa, its highest byte.
;; Also: ARGHO (BB13)
ArgMantissa1:
    .byte 0

;; The argument's mantissa, its second byte.
;; Also: ARGMOH (BB13)
ArgMantissa2:
    .byte 0

;; The argument's mantissa, its third byte, with its X-byte at <ArgMantissa3XByte>.
;; Also: ARGMO (BB13)
ArgMantissa3:
    .byte 0

;; The argument's mantissa, its lowest byte.
;; Also: ARGLO (BB13)
ArgMantissa4:
    .byte 0

;; The argument's sign: 0 for positive, $FF for negative.
;; Also: ARGSGN (BB13)
ArgSign:
    .byte 0

;; The sign of the result: the accumulator's and the argument's signs combined.
;; Also: ARISGN (BB13)
ResultSign:
    .byte 0
    .byte 0
    .byte 0                                 ; The byte below Result1, which catches a long integer's overflow

;; The result of a multiplication or division, its highest byte; for the long integers, the first of eight.
;; Also: RESHO (BB13), RES (BB13)
Result1:
    .res 1

;; The result's second byte.
;; Also: RESMOH (BB13)
Result2:
    .res 1

;; The result's third byte.
;; Also: RESMO (BB13)
Result3:
    .res 1

;; The result's lowest byte.
;; Also: RESLO (BB13)
Result4:
    .res 1

;; A temporary of <Variables::MultiplyUnsigned>'s.
;; Also: ADDEND (BB13)
Addend = Result3

;; A temporary for any routine; for the long integers, the result's fifth byte.
;; Also: TEMP (BB13)
Temporary:
    .byte 0

;; The accumulator's rounding byte, below its lowest.
;; Also: FACOV (BB13)
FacExtension:
    .byte 0
    .res 3

;; A pointer to a string or its descriptor.
;; Also: STRNG1 (BB13)
StringPointer = ResultSign

;; Where <Float::FormatFac> has reached in <NumberBuffer>.
;; Also: FBUFPT (BB13)
NumberBufferPointer:
    .res 2

;; Where <Tokenize> has reached in <InputBuffer>.
;; Also: BUFPTR (BB13)
TokenizePointer = NumberBufferPointer

;; A second pointer to a string or its descriptor.
;; Also: STRNG2 (BB13)
SecondStringPointer = NumberBufferPointer

;; The coefficients of the polynomial being worked out.
;; Also: POLYPT (BB13)
PolynomialPointer = NumberBufferPointer

;; The array's size so far, in `DIM` and the variable search.
;; Also: CURTOL (BB13)
LinearIndex = NumberBufferPointer

; ---------------------------------------------------------------------------------------------------------------------
; Running the program
; ---------------------------------------------------------------------------------------------------------------------

;; Bit 7 set while `TRACE` is on.
;; Also: TRFLAG (BB13)
TraceMode:
    .res 1

;; The type flags of a `FOR` loop's variable, as <FindForFrame> looks for its loop on the stack.
;; Also: TEMPFOR (BB13)
ForVariableType:
    .res 1

;; Where `ON ERR` goes: the statement after it, with its X-byte at <OnErrorTextXByte>, then (at OnErrorText+3) its
;; line number; OnErrorText+2 is unused.
;; See: <Statements::OnErr>, <TrapError>
;; Also: ERRTO (BB13)
OnErrorText:
    .res 5

;; The number of the line the last error happened in, which `ERRLIN` gives.
;; Also: ERRLIN (BB13)
ErrorLine:
    .res 2

;; The statement the last error happened in, for `RESUME`, with its X-byte at <ErrorTextXByte>; zero there means no
;; error yet.
;; See: <Statements::Resume>
;; Also: ERRPOS (BB13)
ErrorText:
    .res 3

;; The number of the last error, which `ERR` gives: an ERROR_ number, or 255 for a Control-C.
;; Also: ERRNUM (BB13)
ErrorCode:
    .res 1

;; Bit 7 set while `ON ERR` is on.
;; Also: ERRFLG (BB13)
OnErrorActive:
    .res 1

;; The stack pointer BASIC goes back to after an error.
;; Also: REMSTK (BB13)
StatementStack:
    .res 1

;; Nonzero once BASIC has reached its prompt or `RUN` or `CHAIN` has loaded a program; until then, 1.3's errors
;; first name the program the selector started.
;; Also: RNFLG (BB13)
StartupDone:
    .res 1

;; The top of <OperandStack>, the expression evaluator's operand stack.
;; Also: NOUNPT (BB13)
OperandStackTop:
    .res 1

;; The top of <OperatorStack>, the expression evaluator's operator stack.
;; Also: VRBPT (BB13)
OperatorStackTop:
    .res 1

;; A pointer to the information bytes after a string, with its X-byte at <StringInformationPointerXByte>.
;; Also: HEADER (BB13)
StringInformationPointer:
    .res 2

;; A place for `LIST` to keep a pointer.
;; Also: PNTSAV (BB13)
ListSavedPointer:
    .word 0

;; The `IF`s still to be matched while an `ELSE` is looked for.
;; Also: LVLCNT (BB13)
IfDepth:
    .res 1

;; Whether the text being scanned is inside quotes.
;; Also: QUOTE (BB13)
InQuotes = IfDepth

;; The variable name the variable search is reading, with its X-byte at <VariableNamePointerXByte>.
;; Also: TMPPTR (BB13)
VariableNamePointer:
    .word 0

;; A string flag: <EvaluateExpression> clears it, and nothing reads it.
;; Also: STRFLG (BB13)
StringFlag:
    .byte 0

;; Where `INVOKE` loads the next module, with its X-byte at <ModuleLoadPointerXByte>.
;; Also: INVPNT (BB13)
ModuleLoadPointer:
    .res 2

;; `INVOKE`'s and `PERFORM`'s count of pointer parameters; it must survive the expression evaluator.
;; Also: NPOINTS (BB13)
PointerParameterCount:
    .byte 0

;; `PERFORM`'s count of parameter words (two bytes each); it must survive the expression evaluator.
;; Also: NPARAMS (BB13)
ParameterWordCount:
    .byte 0

;; What kind of routine `INVOKE` or `PERFORM` is looking for; it must survive the expression evaluator.
;; Also: PROCFLG (BB13)
ProcedureKind:
    .byte 0

;; Whether a file statement reads or writes.
;; Also: IOFLG (BB13)
FileAccessMode = PointerParameterCount

;; Bit 7 set when a key was pressed, bit 6 when Control-C was; the handlers set them and the statement loop checks
;; them before each statement.
;; See: <Console::AnyKeyHandler>, <Console::AttentionHandler>
;; Also: KEYSTROK (BB13)
PendingEvents:
    .byte 0

;; Work space for 16-bit multiplication and division: the multiplier, or the quotient.
;;
;; <Multiplier>, <Remainder> and <Multiplicand> must stay together and in this order.
;; Also: MLTPLR (BB13)
Multiplier:
    .word 0

;; The product.
;; Also: RSLT (BB13)
Product = Multiplier

;; The remainder of the division.
;; Also: RMNDR (BB13)
Remainder:
    .word 0

;; The multiplicand, or the divisor.
;; Also: MLTPLR2 (BB13)
Multiplicand:
    .word 0

;; The quotient.
;; Also: QUOTNT (BB13)
Quotient = Multiplier

;; The dividend.
;; Also: DVDND (BB13)
Dividend = Multiplier

;; The divisor.
;; Also: DVSR (BB13)
Divisor = Multiplicand

;; The byte a whole-byte right shift fills with: 0, or $FF to extend a negative number's sign.
;; Also: BITS (BB13)
ShiftFill:
    .byte 0
    .res 5

;; Where the program or line is being read, with its X-byte at <TextPointerXByte>: the operand of the LDA in
;; <GetCurrentCharacter>, seven bytes into the routine.
;; Also: TXTPTR (BB13)
TextPointer = * + 7

;; Takes the next character of the program or the line, skipping spaces.
;;
;; <ColdStart> copies the routine here from <CharacterReaderTemplate>; what is assembled here only sets out the
;; addresses. The character is read with an absolute LDA whose address, <TextPointer>, is the instruction's own operand
;; in zero page. The Apple III extends an access whose address is read from zero page, so this LDA reads through
;; <TextPointerXByte>'s bank like an indirect one would.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon), carry = clear for a digit
;; Also: CHRGET (BB13)
.proc GetNextCharacter
    inc TextPointer
    bne GetCurrentCharacter
    inc TextPointer+1
    ; Falls into GetCurrentCharacter.
.endproc

;; Takes the character at <TextPointer> again, without moving on, skipping spaces.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon), carry = clear for a digit
;; Also: CHRGOT (BB13)
.proc GetCurrentCharacter
    lda 60000
    .res 15                                 ; The rest of the routine
.endproc
.assert TextPointer = GetCurrentCharacter + 1, "TextPointer is the LDA's operand."

;; The random number generator's state, which `RND` works from; <ColdStart> seeds it from the system's counters.
;; Also: RNDX (BB13)
RandomValue:
    .res 8

;; Where the name of the routine `EXFN` calls starts in <NameBuffer>, for an `EXFN` inside another.
;; Also: NAMPNT (BB13)
ExfnNameOffset:
    .byte 0

;; Set from when `RUN` or `CHAIN` opens a program file until the statement loop starts its first statement; 1.3
;; takes it as the sign to use the new program's prefix.
;; Also: CMDFLG (BB13)
ProgramLoading:
    .byte 0
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; The invokable modules' zero page
;
; These locations are where Pascal's run time keeps the same things, so that a module assembled by the Pascal
; assembler can call back into BASIC.
; ---------------------------------------------------------------------------------------------------------------------

    .dum $E4

;; A JMP to <Modules::CallBasic>, through which a module calls a routine of BASIC's by its number in
;; <ModuleRoutineNumber>.
;; Also: DISPATCH (BB13)
ModuleCallJump:
    .res 3

;; The number of the routine of BASIC's a module calls through <ModuleCallJump>: its place in <ModuleRoutines>.
;; Also: PASSAREG (BB13)
ModuleRoutineNumber:
    .byte 0

;; Pointers to the variables a module was passed by reference, each with its X-byte at <ReferencePointersXByte>.
;; Also: BANKPNT (BB13)
ReferencePointers:
    .res 16
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; Page $1E
;
; Page $1E, above BASIC's stack, which BASIC takes for its own work space. The stack is page $1B, the page after its
; zero page ($1A), which the 6502 reaches as page $01 while that zero page is in use; BASIC resets the stack pointer to
; STACK_END.
; ---------------------------------------------------------------------------------------------------------------------

    .dum 255
;; BASIC's work page.
;; Also: CRUDBUF (BB13)
WorkPage = $1E00
    .dend
    .dum WorkPage
    jmp Modules::CallBasic                  ; A JMP to Modules::CallBasic; nothing here writes it
    .byte 0

;; The return address `PERFORM`'s caller left, kept here while the module runs, then the bank that was switched in.
;; See: <Modules::CallModule>
;; Also: SAFE (BB13)
PerformSavedReturn:
    .byte 0, 0, 0

;; The start of the memory segment SOS gave BASIC, with its X-byte in <SegmentStartXByte>.
;; See: <Segments::FindForBasic>
;; Also: RAMLOC (BB13)
SegmentStart:
    .word 0

;; The X-byte of <SegmentStart>.
;; Also: RAMLOCB (BB13)
SegmentStartXByte:
    .byte 0

;; The expression evaluator's operator stack: each operator's number and its precedence (with the operand's type).
;; See: <OperatorStackTop>
;; Also: VRBSTK (BB13)
OperatorStack:
    .res OPERATOR_STACK_SIZE

;; Where each file's `ON EOF#` goes, three bytes for each file from 1, the last for `ON KBD`: the X-byte, then the
;; address, made relative to <ProgramStart>.
;;
;; An entry whose first byte is zero has no handler.
;; See: <Statements::OnEof>, <Handlers::EndOfFile>, <EndOfFileHandlerLines>
;; Also: EOFPTRS (BB13)
EndOfFileHandlers:
    .res END_OF_FILE_HANDLERS_SIZE

;; The line number of each <EndOfFileHandlers> entry's handler, at the same offset.
;; Also: EOFLINS (BB13)
EndOfFileHandlerLines:
    .res END_OF_FILE_HANDLERS_SIZE - 1

;; The control blocks of files 1-10, <FILE_CONTROL_BLOCK_SIZE> bytes each.
;; See: <FileControlBlock>
;; Also: FCB (BB13)
FileControlBlocks:
    .res FILE_CONTROL_BLOCK_SIZE * FILE_COUNT

;; The control block `CATALOG` reads the directory through, as file 11.
;; Also: CATFCB (BB13)
CatalogControlBlock:
    .res FILE_CONTROL_BLOCK_SIZE

;; The X-byte of the invokable modules' bank pair.
;; Also: INVBNK (BB13)
ModulesXByte:
    .byte 0

;; BASIC's own bank, from the bank register when BASIC started.
;; Also: BASICBNK (BB13)
BasicBank:
    .byte 0

;; Bit 7 set when the variable just found is an array element.
;; Also: ISARA (BB13)
ArrayElementFound:
    .byte 0

;; The expression evaluator's operand stack.
;; See: <OperandStackTop>
;; Also: NOUNSTK (BB13)
OperandStack:
    .res OPERAND_STACK_SIZE

;; The SOS error code for a SOS CALL error.
;; See: <ReportSosError>
;; Also: SOSLOC (BB13)
SosError:
    .byte 0

;; The right margin `LIST` wraps at, which `OUTREC` sets and gives; 0 turns wrapping off.
;; Also: OUTREC (BB13)
OutputRecordLength:
    .byte 0

;; How many spaces `LIST` indents each `FOR` loop's lines, which `INDENT` sets and gives.
;; Also: INDENT (BB13)
ListIndent:
    .byte 0

;; The number of the file that last reached its end, which `EOF` gives.
;; Also: EOFSV (BB13)
EndOfFileNumber:
    .res 1
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; SOS.INTERP's header and buffers
; ---------------------------------------------------------------------------------------------------------------------

;; The header SOS reads at the start of an interpreter's file, the bytes before its load address.
.struct InterpreterHeader
    LABEL .res 8                            ;; "SOS NTRP", the label SOS looks for in an interpreter
    EXTRA_LENGTH .word                      ;; the length of more header after this, 0 for none
    LOAD_ADDRESS .word                      ;; where the code loads
    CODE_LENGTH .word                       ;; the code's length
.endstruct

    .org LoadAddress - .sizeof(InterpreterHeader)

;; SOS.INTERP's header.
InterpreterFileHeader:
    .byte "SOS NTRP"
    .word 0000                              ; No more header
    .word LoadAddress
    .word BasicEnd - InterpreterEntry
.assert * - InterpreterFileHeader = .sizeof(InterpreterHeader), "The header is SOS's."
.assert * = LoadAddress, "The code starts at the load address."

;; The first byte SOS loads: a jump to <ColdStart>, where SOS starts the interpreter.
;; Also: GOBASIC (BB13)
.proc InterpreterEntry
    jmp ColdStart
.endproc
.if VERSION >= 130

;; Zero when BASIC was started from the disk, so it runs HELLO, or not zero when 1.3's program selector started it.
;; Also: SELECTOR (BB13)
StartedBySelector:
    .byte 0

;; The pathname of the program the selector chose, with its length first; then just its prefix.
;; See: <ProgramPrefix::UseProgram>
;; Also: PROGPATH (BB13)
ProgramPath:
    .byte 0
    .res PATH_BUFFER_SIZE, 0

;; SOS's own prefix, with its length first, which BASIC goes back to for its own files.
;; See: <ProgramPrefix::UseSos>
;; Also: SOSPATH (BB13)
SosPrefix:
    .byte 0
    .res PATH_BUFFER_SIZE, 0
.endif

;; A pathname or a routine's name, as a file command or `PERFORM` reads it, with its length first.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; Also: NAMBUF (BB13)
NameBuffer:
.if VERSION = 123
    .byte $A0, $E5, $C4, $A0, $A0, $A0, $A0, $FC, $A0, $A0, $D0, $A0, $80, $A0, $AD, $83
    .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $FF, $A0, $A0, $FF, $A0, $E5
    .byte $F0, $A0, $EC, $81, $AD, $AD, $A0, $AD, $A0, $A0, $A0, $BE, $A0, $FC, $A0, $A0
    .byte $A0, $F0, $FC, $A0, $80, $A0, $A0, $A0, $AD, $A0, $A0, $A0, $AD, $A0, $A0, $AD
    .byte $A0, $A0, $8F, $A0, $B1, $A0, $A0, $A0, $A0, $A0, $A0, $AD, $A0, $A0, $A0, $F3
    .byte $B0, $A0, $E5, $A0, $A0, $AD, $ED, $AD, $AA, $A0, $E5, $A0, $A0, $AD, $A0, $AD
    .byte $AD, $AD, $A0, $A0, $A0, $A0, $A0, $B2, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
    .byte $AD, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $D5, $A0, $F2, $A0, $A0
.else
    .res NAME_BUFFER_SIZE
.endif
.assert * - NameBuffer = NAME_BUFFER_SIZE, "The name buffer's size."
    .byte CATALOG_BUFFER_SIZE               ; CatalogBuffer's length, for GET_PREFIX

;; `CATALOG`'s line buffer, and the buffer GET_PREFIX fills.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; Also: CATBUF (BB13)
CatalogBuffer:
.if VERSION = 123
    .byte $B0, $A0, $AD, $80, $AD, $A0, $80, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $EE
    .byte $A0, $A0, $F2, $A0, $AD, $A0, $A0, $AD, $A0, $B7, $A0, $A0, $A0, $F9, $AD, $A0
    .byte $CE, $AD, $A0, $A0, $E8, $A0, $F4, $A0, $AD, $AD, $A0, $AD, $A0, $A0, $A0, $A0
    .byte $B0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $F4
    .byte $AD, $B0, $E9, $AD, $AD, $A0, $A0, $AD, $A0, $AA, $EE, $A0, $A0, $E5, $A0, $F2
.else
    .res CATALOG_BUFFER_SIZE
.endif
.assert * - CatalogBuffer = CATALOG_BUFFER_SIZE, "The catalog buffer's size."

;; The length of the long integer <LongInteger::FormatFac> wrote as text in <LongText>.
;; Also: LENUM (BB13)
LongTextLength:
    .byte 0

;; The digits of a number for `PRINT USING`, one to a byte; <Float::FormatFac>'s output buffer, <NumberBuffer>, is in
;; its upper part.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; Also: BCDSTR (BB13)
UsingDigits:
.if VERSION = 123
    .byte $81, $AD, $A0, $F4, $A0, $A0, $A0, $EE, $A0, $A0, $FC, $A0, $F4, $A0, $F0, $FC
    .byte $A0, $80, $AD, $A0, $A0, $AD, $A0, $A0, $A0, $AD, $A0, $A0, $B0, $AA, $A0, $A0
    .byte $A0, $A0, $A0, $A0, $C5, $AD, $A0, $E1, $AD, $AD, $A0, $A0, $AD, $A0, $B5, $F2
.else
    .res USING_DIGITS_SIZE
.endif
.assert * - UsingDigits = USING_DIGITS_SIZE, "The digits buffer's size."

;; A long integer as text, as <LongInteger::FormatFac> writes it.
;; Also: NUMSTR (BB13)
LongText = UsingDigits

;; <Float::FormatFac>'s output: a number as text, ending in a zero.
;; Also: FBUFFR (BB13)
NumberBuffer = UsingDigits + 28

;; The byte before <NumberBuffer>.
;; Also: LOFBUF (BB13)
NumberBufferPrefix = NumberBuffer - 1
.if VERSION = 123
    .byte $AD, $AD, $AA                     ; The new line's length and number go here
.else
    .res 3                                  ; The new line's length and number go here
.endif

;; An end of a buffer for `PREFIX$`, which nothing uses.
;; Also: PREBUF (BB13)
PrefixBufferEnd = NumberBufferPrefix

;; The input line: the line typed, or read from a file, which <Tokenize> then turns into tokens in place.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; See: <Console::LineParameters>
;; Also: BUF (BB13)
InputBuffer:
.if VERSION = 123
    .byte $A0, $FF, $A0, $A0, $A0, $E9, $A0, $E7, $A0, $FC, $A0, $AD, $B0, $A0, $AD, $8F
    .byte $A0, $A0, $8F, $A0, $A0, $A0, $B2, $A0, $A0, $A0, $A0, $A0, $B1, $A0, $A0, $A0
    .byte $A0, $A0, $AD, $B0, $A0, $AD, $8F, $A0, $A0, $FF, $A0, $AA, $A0, $FC, $A0, $A0
    .byte $A0, $F5, $F2, $A0, $F0, $A0, $AD, $F0, $AD, $AD, $A0, $A0, $A0, $A0, $A0, $A0
    .byte $A0, $A0, $A0, $A0, $A0, $A0, $F2, $A0, $AD, $A0, $A0, $AD, $A0, $A0, $A0, $A0
    .byte $A0, $A0, $AD, $B0, $FC, $AD, $E1, $A0, $E7, $A0, $E9, $A0, $AD, $AD, $A0, $AD
    .byte $AD, $A0, $A0, $B1, $B0, $A0, $A0, $A0, $A0, $A0, $F2, $A0, $EE, $A0, $A0, $AD
    .byte $AD, $A0, $A0, $AD, $AD, $ED, $80, $A0, $E7, $8F, $FC, $A0, $A0, $A0, $A0, $A0
    .byte $AD, $A0, $A0, $AD, $AD, $A0, $A0, $8F, $A0, $A0, $C5, $A0, $AA, $A0, $A0, $A0
    .byte $A0, $A0, $AA, $A0, $A0, $A0, $A0, $AD, $A0, $A0, $AD, $FF, $AD, $A0, $9E, $A0
    .byte $A0, $A0, $D3, $B3, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $AD, $F0, $A0, $A0, $80
    .byte $A0, $A0, $A0, $F0, $A0, $A0, $A0, $A0, $E5, $A0, $A0, $EC, $A0, $AD, $A0, $A0
    .byte $AD, $A0, $D3, $A0, $A0, $A0, $FC, $AD, $A0, $A0, $AD, $B0, $A0, $CE, $A0, $FC
    .byte $AD, $AD, $AD, $AA, $AD, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $B1, $A0, $A0
    .byte $A0, $A0, $A0, $A0, $B3, $A0, $A0, $A0, $F3, $AD, $A0, $BE, $A0, $A0, $CC, $A0
    .byte $F2, $80, $A0, $C1, $A0, $AD, $A0, $A0, $AD, $AD, $A0, $A0, $AD, $A0, $CE, $8F
.else
    .res INPUT_BUFFER_SIZE
.endif
.assert * - InputBuffer = INPUT_BUFFER_SIZE, "The input buffer's size."

;; The last key read, which `KBD` gives.
;; See: <Console::ReadKey>
;; Also: KEYSAVE (BB13)
LastKey:
    .byte CHARACTER_RETURN

; ---------------------------------------------------------------------------------------------------------------------
; Dispatch tables
; ---------------------------------------------------------------------------------------------------------------------

;; Each statement's routine, less one, by its token from `END` ($80) to `NEW` ($E0): the statement loop pushes the
;; address and returns to it.
;;
;; A keyword that isn't a statement, such as `FRE` or a token with no keyword, gives a syntax error (<SyntaxError>).
;; Some keywords share a routine: `POP`'s is `RETURN`'s, `CAT`'s is `CATALOG`'s, and `IMAGE` and `ELSE` are skipped like
;; `REM`.
;; See: <ReservedWords>, <ValueWordTable>
;; Also: STMDSP (BB13)
StatementTable:
    .word Statements::End-1                 ; $80 END
    .word Statements::For-1                 ; $81 FOR
    .word Statements::Next-1                ; $82 NEXT
    .word Statements::Input-1               ; $83 INPUT
    .word Statements::OutputFile-1          ; $84 OUTPUT
    .word Statements::Dim-1                 ; $85 DIM
    .word Statements::Read-1                ; $86 READ
    .word Statements::Write-1               ; $87 WRITE
    .word Statements::Open-1                ; $88 OPEN
    .word Statements::Close-1               ; $89 CLOSE
    .word SyntaxError-1                     ; $8A
    .word Statements::Text-1                ; $8B TEXT
    .word SyntaxError-1                     ; $8C
    .word Statements::Bye-1                 ; $8D BYE
    .word SyntaxError-1                     ; $8E
    .word SyntaxError-1                     ; $8F
    .word SyntaxError-1                     ; $90
    .word SyntaxError-1                     ; $91
    .word SyntaxError-1                     ; $92
    .word Statements::Window-1              ; $93 WINDOW
    .word Statements::Invoke-1              ; $94 INVOKE
    .word Statements::Perform-1             ; $95 PERFORM
    .word SyntaxError-1                     ; $96
    .word SyntaxError-1                     ; $97
    .word SyntaxError-1                     ; $98 FRE
    .word Statements::HPos-1                ; $99 HPOS, as a statement
    .word Statements::VPos-1                ; $9A VPOS, as a statement
    .word SyntaxError-1                     ; $9B ERRLIN
    .word SyntaxError-1                     ; $9C ERR
    .word SyntaxError-1                     ; $9D KBD
    .word SyntaxError-1                     ; $9E EOF
    .word SyntaxError-1                     ; $9F TIME$
    .word SyntaxError-1                     ; $A0 DATE$
    .word Statements::Prefix-1              ; $A1 PREFIX$, as a statement
    .word SyntaxError-1                     ; $A2 EXFN.
    .word SyntaxError-1                     ; $A3 EXFN%.
    .word Statements::OutRec-1              ; $A4 OUTREC
    .word Statements::Indent-1              ; $A5 INDENT
.if VERSION >= 130
    .word Statements::ProgPrefix-1          ; $A6 PROGPREFIX$
.else
    .word SyntaxError-1                     ; $A6
.endif
    .word SyntaxError-1                     ; $A7
    .word SyntaxError-1                     ; $A8
    .word SyntaxError-1                     ; $A9
    .word SyntaxError-1                     ; $AA
    .word SyntaxError-1                     ; $AB
    .word SyntaxError-1                     ; $AC
    .word Statements::Return-1              ; $AD POP
    .word Statements::Home-1                ; $AE HOME
.if DEBUG
    .word $A1FF                             ; $AF, the debugger's command, in the debugger build
.else
    .word SyntaxError-1                     ; $AF
.endif
    .word Statements::Sub-1                 ; $B0 SUB$(
    .word Statements::Off-1                 ; $B1 OFF
    .word Statements::Trace-1               ; $B2 TRACE
    .word Statements::NoTrace-1             ; $B3 NOTRACE
    .word Statements::Normal-1              ; $B4 NORMAL
    .word Statements::Inverse-1             ; $B5 INVERSE
    .word SyntaxError-1                     ; $B6 SCALE(
    .word Statements::Resume-1              ; $B7 RESUME
    .word SyntaxError-1                     ; $B8
    .word Statements::Let-1                 ; $B9 LET
    .word Statements::GoTo-1                ; $BA GOTO
    .word Statements::If-1                  ; $BB IF
    .word Statements::Restore-1             ; $BC RESTORE
    .word Statements::Swap-1                ; $BD SWAP
    .word Statements::GoSub-1               ; $BE GOSUB
    .word Statements::Return-1              ; $BF RETURN
    .word Statements::Rem-1                 ; $C0 REM
    .word Statements::Stop-1                ; $C1 STOP
    .word Statements::On-1                  ; $C2 ON
    .word SyntaxError-1                     ; $C3
    .word Statements::Load-1                ; $C4 LOAD
    .word Statements::Save-1                ; $C5 SAVE
    .word Statements::Delete-1              ; $C6 DELETE, of a file
    .word Statements::Run-1                 ; $C7 RUN
    .word Statements::Rename-1              ; $C8 RENAME
    .word Statements::Lock-1                ; $C9 LOCK
    .word Statements::Unlock-1              ; $CA UNLOCK
    .word Statements::Create-1              ; $CB CREATE
    .word Statements::Exec-1                ; $CC EXEC
    .word Statements::Chain-1               ; $CD CHAIN
    .word SyntaxError-1                     ; $CE
    .word SyntaxError-1                     ; $CF
    .word SyntaxError-1                     ; $D0
    .word Statements::Catalog-1             ; $D1 CATALOG
    .word SyntaxError-1                     ; $D2
    .word SyntaxError-1                     ; $D3
    .word Statements::Data-1                ; $D4 DATA
    .word Statements::Rem-1                 ; $D5 IMAGE
    .word Statements::Catalog-1             ; $D6 CAT
    .word Statements::Def-1                 ; $D7 DEF
    .word SyntaxError-1                     ; $D8
    .word Statements::Print-1               ; $D9 PRINT
    .word Statements::Del-1                 ; $DA DEL, of program lines
    .word Statements::Rem-1                 ; $DB ELSE
    .word Statements::Cont-1                ; $DC CONT
    .word Statements::List-1                ; $DD LIST
    .word Statements::Clear-1               ; $DE CLEAR
    .word Statements::Get-1                 ; $DF GET
    .word Statements::New-1                 ; $E0 NEW
.assert * - StatementTable = 2 * (TOKEN_NEW - TOKEN_END + 1), "A routine for each one-byte token."

;; The routines of the keywords that give a value without parentheses, by token from `FRE` (<TOKEN_FRE>) to
;; `PROGPREFIX$`, which <EvaluateReservedWord> jumps to.
;;
;; `FRE`'s routine (<Functions::Fre>) comes first; then `HPOS`, `VPOS`, `ERRLIN`, `ERR`, `KBD`, `EOF`, `TIME$`, `DATE$`,
;; `PREFIX$`, `EXFN.`, `EXFN%.`, `OUTREC` and `INDENT`, and in 1.3 `PROGPREFIX$`.
;; Also: RESTBL (BB13)
ValueWordTable:
    .word Functions::Fre                    ; $98 FRE
    .word Functions::HPos                   ; $99 HPOS
    .word Functions::VPos                   ; $9A VPOS
    .word Functions::ErrLin                 ; $9B ERRLIN
    .word Functions::Err                    ; $9C ERR
    .word Functions::Kbd                    ; $9D KBD
    .word Functions::Eof                    ; $9E EOF
    .word Functions::Time                   ; $9F TIME$
    .word Functions::Date                   ; $A0 DATE$
    .word Functions::Prefix                 ; $A1 PREFIX$
    .word Functions::ExFn                   ; $A2 EXFN.
    .word Functions::ExFnInteger            ; $A3 EXFN%.
    .word Functions::OutRec                 ; $A4 OUTREC
    .word Functions::Indent                 ; $A5 INDENT
.if VERSION >= 130
    .word Functions::ProgPrefix             ; $A6 PROGPREFIX$
.endif

;; The functions' routines, by their tokens in <ExtendedReservedWords> from `SGN(` (<TOKEN_FIRST_FUNCTION>) to
;; `INSTR(` (<TOKEN_INSTR>).
;;
;; A token with no function, and `USR`, which Business BASIC doesn't have, give a syntax error.
;; Also: FUNDSP (BB13)
FunctionTable:
    .word Functions::Sgn                    ; $9D SGN(
    .word Functions::Int                    ; $9E INT(
    .word Functions::Abs                    ; $9F ABS(
    .word SyntaxError                       ; $A0, USR's place, which Business BASIC doesn't have
    .word Functions::Typ                    ; $A1 TYP(
    .word Functions::Rec                    ; $A2 REC(
    .word SyntaxError                       ; $A3
    .word SyntaxError                       ; $A4
    .word SyntaxError                       ; $A5
    .word SyntaxError                       ; $A6
    .word SyntaxError                       ; $A7
    .word SyntaxError                       ; $A8
    .word SyntaxError                       ; $A9
    .word SyntaxError                       ; $AA
    .word SyntaxError                       ; $AB
    .word SyntaxError                       ; $AC
    .word Functions::Pdl                    ; $AD PDL(
    .word Functions::Button                 ; $AE BUTTON(
    .word Functions::Sqr                    ; $AF SQR(
    .word Functions::Rnd                    ; $B0 RND(
    .word Functions::Log                    ; $B1 LOG(
    .word Functions::Exp                    ; $B2 EXP(
    .word Functions::Cos                    ; $B3 COS(
    .word Functions::Sin                    ; $B4 SIN(
    .word Functions::Tan                    ; $B5 TAN(
    .word Functions::Atn                    ; $B6 ATN(
    .word SyntaxError                       ; $B7
    .word SyntaxError                       ; $B8
    .word SyntaxError                       ; $B9
    .word SyntaxError                       ; $BA
    .word SyntaxError                       ; $BB
    .word SyntaxError                       ; $BC
    .word SyntaxError                       ; $BD
    .word SyntaxError                       ; $BE
    .word SyntaxError                       ; $BF
    .word SyntaxError                       ; $C0
    .word SyntaxError                       ; $C1
    .word SyntaxError                       ; $C2
    .word Functions::Str                    ; $C3 STR$(
    .word Functions::Hex                    ; $C4 HEX$(
    .word Functions::Chr                    ; $C5 CHR$(
    .word Functions::Len                    ; $C6 LEN(
    .word Functions::Val                    ; $C7 VAL(
    .word Functions::Asc                    ; $C8 ASC(
    .word Functions::Ten                    ; $C9 TEN(
    .word SyntaxError                       ; $CA
    .word SyntaxError                       ; $CB
    .word Functions::Conv                   ; $CC CONV(
    .word Functions::ConvLong               ; $CD CONV&(
    .word Functions::ConvString             ; $CE CONV$(
    .word Functions::ConvInteger            ; $CF CONV%(
    .word Functions::Left                   ; $D0 LEFT$(
    .word Functions::Right                  ; $D1 RIGHT$(
    .word Functions::Mid                    ; $D2 MID$(
    .word Functions::InStr                  ; $D3 INSTR(
.assert * - FunctionTable = 2 * (TOKEN_INSTR - TOKEN_FIRST_FUNCTION + 1), "A routine for each function's token."

;; Each operator's precedence, higher binding tighter, by the operator's number less one.
;;
;; The numbers are those <EvaluateExpression> gives: the relational operators first (the combinations of less, equal and
;; greater), then <OperatorSymbols>' operators from ^ on, and the end of the expression last.
;; See: <OperatorSymbols>
;; Also: PRECTB (BB13)
PrecedenceTable:
    .byte 4, 4, 4, 4                        ; The relational operators
    .byte 4, 4, 4
    .byte 8, 3, 2, 6                        ; ^ AND OR MOD
    .byte 6, 6, 6, 5                        ; DIV / * -
    .byte 5, 1                              ; + and the end of the expression

;; The routines for the operators on reals and integers, two bytes each in operator order: the relational operators'
;; routine first, then ^, `AND`, `OR`, `MOD`, `DIV`, /, *, - and +; the routines for long integers follow, at
;; <OPERATOR_LONG_ROUTINES>.
;;
;; `MOD` and `DIV` give a type mismatch on reals. String operands may take only the relational operators and +.
;; See: <EvaluateExpression>
;; Also: OPDSPT (BB13)
OperatorRoutineTable:
    .word ApplyRelation

;; The relational operators' entry, the first.
;; Also: RELNUM (BB13)
OPERATOR_RELATIONAL_ENTRY = 1
    .word Float::RaiseArg                   ; ^
    .word Operators::And                    ; AND
    .word Operators::Or                     ; OR
    .word TypeMismatchError                 ; MOD, on reals
    .word TypeMismatchError                 ; DIV, on reals
    .word Float::DivideArg                  ; /
    .word Float::MultiplyArg                ; *
    .word Float::SubtractFromArg            ; -
    .word Float::AddArg                     ; +

;; The offset of the long-integer routines, and of + for a string.
;; Also: NUMDSP (BB13)
OPERATOR_LONG_ROUTINES = * - OperatorRoutineTable
    .word LongInteger::Compare              ; The relational operators
    .word TypeMismatchError                 ; ^ on long integers
    .word LongInteger::And                  ; AND
    .word LongInteger::Or                   ; OR
    .word LongInteger::Mod                  ; MOD
    .word LongInteger::Div                  ; DIV
    .word LongInteger::Divide               ; /
    .word LongInteger::Multiply             ; *
    .word LongInteger::Subtract             ; -
    .word LongInteger::Add                  ; +

; ---------------------------------------------------------------------------------------------------------------------
; X-bytes
;
; Each is the X-byte of the pointer it is named for: the extension byte that picks the bank for an indirect access
; through that pointer.
; ---------------------------------------------------------------------------------------------------------------------

;; From a pointer's address to its X-byte: $1600, plus 1 for the high byte.
;;
;; Code that clears or reads the X-byte page indexes from it, as `sta X_BYTE_OFFSET,X`.
;; Also: SYSPAG (BB13)
X_BYTE_OFFSET = $1601

;; <VariableSizes>' X-byte.
;; Also: VARNAMB (BB13)
VariableSizesXByte = VariableSizes + X_BYTE_OFFSET

;; <VariablePointer>'s X-byte: the bank of the variable just found.
;; Also: VARPNTB (BB13)
VariablePointerXByte = VariablePointer + X_BYTE_OFFSET

;; <FunctionPointer>'s X-byte.
;; Also: DEFPNTB (BB13)
FunctionPointerXByte = FunctionPointer + X_BYTE_OFFSET

;; <Pointer1>'s X-byte.
;; Also: INDEX1B (BB13), INDEXB (BB13)
Pointer1XByte = Pointer1 + X_BYTE_OFFSET

;; <Pointer2>'s X-byte.
;; Also: INDEX2B (BB13)
Pointer2XByte = Pointer2 + X_BYTE_OFFSET

;; <ProgramStart>'s X-byte: the bank of the program's start.
;; Also: TXTTABB (BB13)
ProgramStartXByte = ProgramStart + X_BYTE_OFFSET

;; <VariablesStart>' X-byte: the bank of the simple variables' start.
;; Also: VARTABB (BB13), SMVARSB (BB13)
VariablesStartXByte = VariablesStart + X_BYTE_OFFSET

;; <ArraysStart>' X-byte: the bank of the arrays' start.
;; Also: ARYTABB (BB13)
ArraysStartXByte = ArraysStart + X_BYTE_OFFSET

;; <VariablesEnd>' X-byte: the bank of the variables' end.
;; Also: STRENDB (BB13)
VariablesEndXByte = VariablesEnd + X_BYTE_OFFSET

;; <StringsBottom>' X-byte: the bank of the strings' bottom.
;; Also: FRETOPB (BB13)
StringsBottomXByte = StringsBottom + X_BYTE_OFFSET

;; <NewString>'s X-byte.
;; Also: FRESPCB (BB13)
NewStringXByte = NewString + X_BYTE_OFFSET

;; <MemoryTop>'s X-byte: the bank of the strings' top.
;; Also: MEMSIZB (BB13), HIMEMB (BB13)
MemoryTopXByte = MemoryTop + X_BYTE_OFFSET

;; <StoppedText>'s X-byte.
;; Also: OLDTXTB (BB13)
StoppedTextXByte = StoppedText + X_BYTE_OFFSET

;; <DataPointer>'s X-byte.
;; Also: DATPTRB (BB13)
DataPointerXByte = DataPointer + X_BYTE_OFFSET

;; <InputPointer>'s X-byte.
;; Also: INPPTRB (BB13)
InputPointerXByte = InputPointer + X_BYTE_OFFSET

;; <DescriptorPointer>'s X-byte.
;; Also: DSCPNTB (BB13)
DescriptorPointerXByte = DescriptorPointer + X_BYTE_OFFSET

;; <DestinationEnd>'s X-byte.
;; Also: HIGHDSB (BB13)
DestinationEndXByte = DestinationEnd + X_BYTE_OFFSET

;; <DataBufferPointer>'s X-byte.
;; Also: NDXPTRB (BB13)
DataBufferPointerXByte = DataBufferPointer + X_BYTE_OFFSET

;; <SourceEnd>'s X-byte.
;; Also: HIGHTRB (BB13)
SourceEndXByte = SourceEnd + X_BYTE_OFFSET

;; <DestinationStart>'s X-byte.
;; Also: LOWDSB (BB13)
DestinationStartXByte = DestinationStart + X_BYTE_OFFSET

;; <SourceStart>'s X-byte.
;; Also: LOWTRB (BB13)
SourceStartXByte = SourceStart + X_BYTE_OFFSET

;; <LongOperand1Pointer>'s X-byte.
;; Also: PTR1B (BB13)
LongOperand1PointerXByte = LongOperand1Pointer + X_BYTE_OFFSET

;; <LongOperand2Pointer>'s X-byte.
;; Also: PTR2B (BB13)
LongOperand2PointerXByte = LongOperand2Pointer + X_BYTE_OFFSET

;; <LongResultPointer>'s X-byte.
;; Also: PTR3B (BB13)
LongResultPointerXByte = LongResultPointer + X_BYTE_OFFSET

;; The X-byte of <Fac> and <FacMantissa1> as a pointer.
;; Also: FACB (BB13)
FacXByte = Fac + X_BYTE_OFFSET

;; The X-byte of <FacMantissa3> and <FacMantissa4> as a pointer.
;; Also: FACMOB (BB13)
FacMantissa3XByte = FacMantissa3 + X_BYTE_OFFSET

;; The X-byte of <ArgMantissa3> and <ArgMantissa4> as a pointer.
;; Also: ARGMOB (BB13)
ArgMantissa3XByte = ArgMantissa3 + X_BYTE_OFFSET

;; <StringInformationPointer>'s X-byte.
;; Also: HEADERB (BB13)
StringInformationPointerXByte = StringInformationPointer + X_BYTE_OFFSET

;; The X-byte of the string address in <NewDescriptor>, which follows its length.
;; Also: DSCTMPB (BB13)
NewDescriptorXByte = NewDescriptor + X_BYTE_OFFSET + 1

;; <VariableListPointer>'s X-byte.
;; Also: VARTXTB (BB13)
VariableListPointerXByte = VariableListPointer + X_BYTE_OFFSET

;; <TextPointer>'s X-byte: the bank of the text <GetNextCharacter> reads.
;; Also: TXTPTRB (BB13)
TextPointerXByte = TextPointer + X_BYTE_OFFSET

;; <VariableNamePointer>'s X-byte.
;; Also: TMPPTRB (BB13)
VariableNamePointerXByte = VariableNamePointer + X_BYTE_OFFSET

;; <VariableSearchPointer>'s X-byte.
;; Also: SRCHPTB (BB13)
VariableSearchPointerXByte = VariableSearchPointer + X_BYTE_OFFSET

;; <ArrayPointer>'s X-byte.
;; Also: ARYPNTB (BB13)
ArrayPointerXByte = ArrayPointer + X_BYTE_OFFSET

;; <StringPointer>'s X-byte.
;; Also: STRNG1B (BB13)
StringPointerXByte = StringPointer + X_BYTE_OFFSET

;; <SecondStringPointer>'s X-byte.
;; Also: STRNG2B (BB13)
SecondStringPointerXByte = SecondStringPointer + X_BYTE_OFFSET

;; <AssignedVariable>'s X-byte.
;; Also: FORPNTB (BB13)
AssignedVariableXByte = AssignedVariable + X_BYTE_OFFSET

;; <DigitCount>'s X-byte.
;; Also: DECCNTB (BB13)
DigitCountXByte = DigitCount + X_BYTE_OFFSET

;; <CollectorTop>'s X-byte.
;; Also: GRBTOPB (BB13)
CollectorTopXByte = CollectorTop + X_BYTE_OFFSET

;; The bank part of <MoveDistance>, how many bank pairs a block moves.
;; Also: DELTAB (BB13)
MoveDistanceXByte = MoveDistance + X_BYTE_OFFSET

;; The X-byte of <ReferencePointers>' first pointer.
;; Also: BANKPNTB (BB13)
ReferencePointersXByte = ReferencePointers + X_BYTE_OFFSET

;; <ModulesEnd>' X-byte.
;; Also: PROCTABB (BB13)
ModulesEndXByte = ModulesEnd + X_BYTE_OFFSET

;; <ModulesStart>' X-byte.
;; Also: INVTABB (BB13)
ModulesStartXByte = ModulesStart + X_BYTE_OFFSET

;; <PolynomialPointer>'s X-byte.
;; Also: POLYPTB (BB13)
PolynomialPointerXByte = PolynomialPointer + X_BYTE_OFFSET

;; <ModuleLoadPointer>'s X-byte.
;; Also: INVPNTB (BB13)
ModuleLoadPointerXByte = ModuleLoadPointer + X_BYTE_OFFSET

;; The X-byte of `ON ERR`'s statement address in <OnErrorText>.
;; Also: ERRTOB (BB13)
OnErrorTextXByte = OnErrorText + X_BYTE_OFFSET

;; The X-byte of the last error's statement address in <ErrorText>.
;; Also: ERRPOSB (BB13)
ErrorTextXByte = ErrorText + X_BYTE_OFFSET
