; retrocore: style=strict
;; APPLESOFT: BUILD CONSTANTS, WORKSPACE AND MACHINE ADDRESSES
;;
;; These equates name existing RAM and ROM locations; they allocate no workspace. Some shared modules use the
;; configuration constants, but changing them alone does not regenerate the whole listing. <ROM_ORIGIN> and
;; <RAM_ORIGIN> describe the original build, not runtime limits.
;;
;; The two-byte pointers <ProgramStart>, <VariablesStart>, <ArraysStart> and <ArraysEnd> delimit the program, the
;; simple variables, the arrays and free memory in ascending order. Strings occupy the high end of memory down to
;; <StringsBottom>, below <MemoryTop>. Most zero-page storage is reused: aliases below name the same bytes for
;; different phases, and writing one alias overwrites the others. Monitor and graphics locations overlap other
;; scratch as noted.
;;
;; The names follow the assembly style guide. Each definition lists Microsoft's name and Apple's as its historical
;; names, so the sources that still use them assemble unchanged. Microsoft's NCMWID, the print-zone limit, is not
;; defined: its one use stores <MemoryTop>'s high byte into <StringsBottom>'s, and is written that way.

.org $0000

; Final Microsoft build configuration.
;; Microsoft build target: 4 selects Apple II I/O.
REALIO = $04
.include "../Microsoft6502Basic/MsBasic.Switches.asm"
.include "../Microsoft6502Basic/MsBasic.Layouts.asm"
.include "../Microsoft6502Basic/MsBasic.Families.asm"

;; Microsoft build switch for the `NULL` command.
;; Also: NULCMD (M6502)
NULL_COMMAND = $00

;; Microsoft build switch for the `GET` command.
;; Also: GETCMD (M6502)
GET_COMMAND = $01

;; Microsoft build switch for the hardware rotate instruction.
;; Also: RORSW (M6502)
ROTATE_INSTRUCTION = $01

;; Microsoft build switch for ROM-resident BASIC.
;; Also: ROMSW (M6502)
ROM_RESIDENT = $01

;; Microsoft build's print-zone width.
;; Also: CLMWID (M6502)
ZONE_WIDTH = $0E

;; Microsoft build switch for long initialization.
;; Also: LONGI (M6502)
LONG_INITIALIZATION = $01

;; Microsoft build's upper stack limit.
;; Also: STKEND (M6502)
STACK_END = $01FB

;; Microsoft build's input buffer page.
;; Also: BUFPAG (M6502)
INPUT_BUFFER_PAGE = $02

;; Microsoft build's terminal line width.
;; Also: LINLEN (M6502)
LINE_LENGTH = $28

;; Microsoft build's input buffer length.
;; Also: BUFLEN (M6502)
INPUT_BUFFER_LENGTH = $F0

;; Microsoft build's ROM origin.
;; Also: ROMLOC (M6502)
ROM_ORIGIN = $D000

;; Microsoft build switch for KIM ROM.
;; Also: KIMROM (M6502)
KIM_ROM = $00

;; Microsoft build's RAM origin.
;; Also: RAMLOC (M6502)
RAM_ORIGIN = $2A00

;; Monitor character-input entry used by `GET`.
;; Also: CZGETL (M6502)
GetCharacter = $FD0C

;; Generic Microsoft stack reserve in two-byte levels; Apple uses a different reserve in <CheckStack>.
;; Also: NUMLEV (M6502)
STACK_LEVELS = $17

;; Number of temporary string descriptors.
;; Also: NUMTMP (M6502)
TEMPORARY_COUNT = $03

;; Control-O, the output-suppression character.
;; Also: CONTW (M6502)
SUPPRESS_OUTPUT_KEY = $0F

; Page-zero entry vectors and general interpreter scratch.
;; Page-zero restart jump, initialized to <MAIN>.
;; Also: START (M6502, ASTIL)
RestartJump = $00

;; Page-zero jump initialized to <STROUT>.
;; Also: RDYJSR (M6502, ASTIL)
PrintStringJump = $03

;; Page-zero vector for floating-point to signed-integer conversion.
;; Also: ADRAYI (M6502, ASTIL)
FloatToIntegerVector = $06

;; Page-zero vector for signed-integer to floating-point conversion.
;; Also: ADRGAY (M6502, ASTIL)
IntegerToFloatVector = $08

;; Writable jump vector used by `USR`.
;; Also: USRPOK (M6502, ASTIL)
UserVector = $0A

;; Delimiter character, shared with <SmallInteger>.
;; Also: CHARAC (M6502, ASTIL)
Delimiter = $0D

;; One-byte integer result, sharing <Delimiter>.
;; Also: INTEGR (M6502)
SmallInteger = $0D

;; Second delimiter character.
;; Also: ENDCHR (M6502, ASTIL)
EndDelimiter = $0E

;; General counter.
;; Also: COUNT (M6502, ASTIL)
Counter = $0F

;; Array-dimensioning flag: set while `DIM` is defining arrays.
;; Also: DIMFLG (M6502, ASTIL), KIMY (M6502)
Dimensioning = $10

;; Value-type flag, negative for a string and clear for a number.
;; Also: VALTYP (M6502, ASTIL)
ValueType = $11

;; Integer-variable type flag.
;; Also: INTFLG (M6502, ASTIL)
IntegerType = $12

;; Tokenizer flag suppressing reserved-word recognition in `DATA`, shared with <CollectionState>.
;; Also: DORES (M6502)
TokenizeState = $13

;; String allocation and garbage-collection flag, sharing <TokenizeState>.
;; Also: GARBFL (M6502, ASTIL)
CollectionState = $13

;; Flag suppressing subscripted-variable recognition for `FOR` and user functions.
;; Also: SUBFLG (M6502, ASTIL)
SubscriptMode = $14

;; Distinguishes `INPUT` from `READ`.
;; Also: INPFLG (M6502, ASTIL)
InputMode = $15

;; Tangent sign scratch, shared with <RelationMask>.
;; Also: TANSGN (M6502, ASTIL)
TangentSign = $16

;; Output-suppression flag in the Microsoft source, sharing <CollectorStep>.
;; Also: CNTWFL (M6502)
OutputSuppressed = $8F

;; Terminal position alias of <CH>.
;; Also: TRMPOS (M6502)
TerminalPosition = $24

; Temporary descriptors, arithmetic scratch and dynamic-memory pointers.
;; Two-byte line number during input, shared with <PokeAddress>.
;; Also: LINNUM (M6502, ASTIL)
LineNumber = $50

;; Page-zero pointer to the next free temporary string descriptor.
;; Also: TEMPPT (M6502)
NextTemporary = $52

;; Two-byte pointer to the last-used temporary descriptor.
;; Also: LASTPT (M6502, ASTIL)
LastTemporary = $53

;; Three consecutive three-byte temporary string descriptors.
;; Also: TEMPST (M6502, ASTIL)
TemporaryDescriptors = $55

;; Two-byte index scratch.
;; Also: INDEX1 (M6502), INDEX (M6502, ASTIL)
Pointer1 = $5E

;; Second two-byte index scratch.
;; Also: INDEX2 (M6502, ASTIL)
Pointer2 = $60

;; High byte of multiplication or division result scratch.
;; Also: RESHO (M6502), RESULT (AS82), RES (ASTIL)
Result1 = $62

;; Next byte of multiplication or division result scratch.
;; Also: RESMOH (M6502)
Result2 = $63

;; Middle byte of result scratch, shared with <Addend>.
;; Also: RESMO (M6502)
Result3 = $64

;; Low byte of multiplication or division result scratch.
;; Also: RESLO (M6502)
Result4 = $65

;; Multiplication addend scratch, sharing <Result3>.
;; Also: ADDEND (M6502)
Addend = $64

;; Two-byte pointer to the first program line.
;; Also: TXTTAB (M6502), TEXTAB (ASTIL)
ProgramStart = $67

;; Two-byte pointer to the simple variables after the program.
;; Also: VARTAB (M6502, ASTIL)
VariablesStart = $69

;; Two-byte pointer to the first array after the simple variables.
;; Also: ARYTAB (M6502, ASTIL)
ArraysStart = $6B

;; Two-byte pointer to the end of array and simple-variable storage.
;; Also: STREND (M6502, ASTIL)
ArraysEnd = $6D

;; Two-byte pointer to the bottom of allocated string space.
;; Also: FRETOP (M6502, ASTIL)
StringsBottom = $6F

;; Two-byte pointer to a newly allocated string.
;; Also: FRESPC (M6502, ASTIL)
NewString = $71

;; Two-byte upper limit of BASIC's string storage.
;; Also: MEMSIZ (M6502, ASTIL)
MemoryTop = $73

;; Two-byte current line number; its high byte is $FF for direct execution.
;; Also: CURLIN (M6502, ASTIL, AS82)
CurrentLine = $75

;; Two-byte saved line number for `CONT`.
;; Also: OLDLIN (M6502, ASTIL)
StoppedLine = $77

;; Two-byte `POKE` address scratch, sharing <LineNumber>.
;; Also: POKER (M6502)
PokeAddress = $50

;; Two-byte saved text pointer for `CONT`.
;; Also: OLDTXT (M6502, ASTIL)
StoppedText = $79

;; Two-byte line number of the current `DATA` statement.
;; Also: DATLIN (M6502, ASTIL)
DataLine = $7B

;; Two-byte pointer into `DATA` for `READ`.
;; Also: DATPTR (M6502, ASTIL, AS82)
DataPointer = $7D

;; Two-byte pointer into input for `INPUT` or `READ`.
;; Also: INPPTR (M6502, ASTIL)
InputPointer = $7F

; Variable, expression, transfer and floating-point scratch; aliases overlap.
;; Two-byte encoded variable name.
;; Also: VARNAM (M6502, ASTIL)
VariableName = $81

;; Two-byte pointer to a variable's value, shared with <PowerTablePointer>.
;; Also: VARPNT (M6502, ASTIL)
VariablePointer = $83

;; Power-of-ten table pointer for numeric output, sharing <VariablePointer>.
;; Also: FDECPT (M6502)
PowerTablePointer = $83

;; Two-byte `FOR` or assignment variable pointer, shared with <ListOffset> and `WAIT` masks.
;; Also: FORPNT (M6502, ASTIL, AS82)
AssignedVariable = $85

;; `LIST`'s saved index into the line it is listing, sharing <AssignedVariable>.
;; Also: LSTPNT (M6502)
ListOffset = $85

;; `WAIT` AND mask, sharing the first byte of <AssignedVariable>.
;; Also: ANDMSK (M6502)
WaitAndMask = $85

;; `WAIT` exclusive-OR mask, sharing the second byte of <AssignedVariable>.
;; Also: EORMSK (M6502)
WaitXorMask = $86

;; Two-byte pointer to an <OperatorTable> entry, shared with <VariableListPointer>.
;; Also: OPPTR (M6502, ASTIL), LASTOP (AS82)
OperatorPointer = $87

;; Two-byte variable-text pointer, sharing <OperatorPointer>.
;; Also: VARTXT (M6502)
VariableListPointer = $87

;; Current relational-operator mask.
;; Also: OPMASK (M6502, ASTIL)
OperatorMask = $89

;; Relation-operation mask, sharing <TangentSign>.
;; Also: DOMASK (M6502)
RelationMask = $16

;; Two-byte function-definition pointer, shared with <CollectorPointer> and <FloatTemporary3>.
;; Also: DEFPNT (M6502, ASTIL), TEMP3 (ASTIL)
FunctionPointer = $8A

;; Two-byte garbage-collection pointer, sharing <FunctionPointer>.
;; Also: GRBPNT (M6502)
CollectorPointer = $8A

;; Two-byte pointer to a string descriptor.
;; Also: DSCPNT (M6502, ASTIL), DSCPTR (AS82)
DescriptorPointer = $8C

;; Garbage collector's descriptor size scratch, sharing <OutputSuppressed>.
;; Also: FOUR6 (M6502, ASTIL)
CollectorStep = $8F

;; Writable page-zero jump instruction; the function dispatcher stores its target in the next two bytes.
;; Also: JMPER (M6502, ASTIL), JMPADRS (AS82)
FunctionJump = $90

;; The string collector's descriptor-offset scratch, sharing the first operand byte of <FunctionJump>.
;; Also: SIZE (M6502)
CollectorOffset = $91

;; The second operand byte of <FunctionJump>, which the floating-point code borrows: while adding, the extension
;; (rounding) byte of the operand that is not shifted, the shifted one's being in <FacExtension>; `EXP` keeps its
;; rounding byte here.
;; Also: OLDOV (M6502), EXTRASY (AS82)
FunctionJumpHigh = $92

;; Packed floating-point temporary, sharing <FunctionPointer>.
;; Also: TEMPF3 (M6502)
FloatTemporary3 = $8A

;; Packed floating-point temporary overlapping transfer scratch.
;; Also: TEMPF1 (M6502, ASTIL), TEMP1 (ASTIL)
FloatTemporary1 = $93

;; Two-byte end of the destination block for <MoveRangeUp>, shared with <ArrayPointer>.
;; Also: HIGHDS (M6502, ASTIL, AS82), ARRYPT (ASTIL)
DestinationEnd = $94

;; Two-byte end of the source block for <MoveRangeUp>.
;; Also: HIGHTR (M6502, ASTIL)
SourceEnd = $96

;; Packed floating-point temporary overlapping transfer scratch.
;; Also: TEMPF2 (M6502, ASTIL), TEMP2 (ASTIL)
FloatTemporary2 = $98

;; Transfer scratch, shared with decimal-conversion scratch <DigitCount>.
;; Also: LOWDS (M6502, ASTIL)
DestinationStart = $99

;; Two-byte start of the source block for <MoveRangeUp>, shared with <CollectorTop>.
;; Also: LOWTR (M6502, ASTIL)
SourceStart = $9B

;; Two-byte array-building pointer, sharing <DestinationEnd>.
;; Also: ARYPNT (M6502)
ArrayPointer = $94

;; Two-byte garbage-collection pointer, sharing <SourceStart>.
;; Also: GRBTOP (M6502)
CollectorTop = $9B

;; Decimal digit-count scratch, sharing <DestinationStart>.
;; Also: DECCNT (M6502)
DigitCount = $99

;; Decimal exponent scratch, sharing <DestinationStart>+1.
;; Also: TENEXP (M6502)
DecimalExponent = $9A

;; Decimal-point flag, sharing <SourceStart>.
;; Also: DPTFLG (M6502)
DecimalPointSeen = $9B

;; Decimal exponent sign flag, sharing <SourceStart>+1.
;; Also: EXPSGN (M6502, AS82)
ExponentSign = $9C

;; Floating-point accumulator, also descriptor scratch <NewDescriptor>.
;; Also: FAC (M6502, ASTIL)
Fac = $9D

;; Floating-point accumulator exponent.
;; Also: FACEXP (M6502)
FacExponent = $9D

;; High mantissa byte of <Fac>.
;; Also: FACHO (M6502)
FacMantissa1 = $9E

;; Second mantissa byte of <Fac>.
;; Also: FACMOH (M6502)
FacMantissa2 = $9F

;; Third mantissa byte of <Fac>, shared with <ArrayIndex>.
;; Also: FACMO (M6502)
FacMantissa3 = $A0

;; Low mantissa byte of <Fac>.
;; Also: FACLO (M6502)
FacMantissa4 = $A1

;; Unpacked sign of <Fac>.
;; Also: FACSGN (M6502, AS82)
FacSign = $A2

;; The sign of the number being read: set by a leading minus, tested to negate it at the end. Shared with
;; <PolynomialDegree>.
;; Also: SGNFLG (M6502), SNGFLG (ASTIL)
InputSign = $A3

;; Polynomial degree counter, sharing <InputSign>.
;; Also: DEGREE (M6502)
PolynomialDegree = $A3

;; Temporary string descriptor built in <Fac>.
;; Also: DSCTMP (M6502, ASTIL)
NewDescriptor = $9D

;; Integer conversion scratch, sharing <FacMantissa3>.
;; Also: INDICE (M6502)
ArrayIndex = $A0

;; The fill byte for whole-byte right shifts: 0, or $FF to extend a sign.
;; Also: BITS (M6502, ASTIL)
ShiftFill = $A4

;; Floating-point argument exponent.
;; Also: ARGEXP (M6502), ARG (ASTIL)
ArgExponent = $A5

;; High mantissa byte of the floating-point argument.
;; Also: ARGHO (M6502)
ArgMantissa1 = $A6

;; Second mantissa byte of the floating-point argument.
;; Also: ARGMOH (M6502)
ArgMantissa2 = $A7

;; Third mantissa byte of the floating-point argument.
;; Also: ARGMO (M6502)
ArgMantissa3 = $A8

;; Low mantissa byte of the floating-point argument.
;; Also: ARGLO (M6502)
ArgMantissa4 = $A9

;; Unpacked sign of the floating-point argument.
;; Also: ARGSGN (M6502)
ArgSign = $AA

;; Arithmetic result-sign scratch, shared with <StringPointer>.
;; Also: ARISGN (M6502)
ResultSign = $AB

;; Floating-point accumulator overflow byte.
;; Also: FACOV (M6502)
FacExtension = $AC

;; Two-byte string or descriptor pointer, sharing <ResultSign>.
;; Also: STRNG1 (M6502, ASTIL)
StringPointer = $AB

;; Two-byte pointer into the numeric output buffer, shared with <TokenizePointer>, <SecondStringPointer>,
;; <PolynomialPointer> and <LinearIndex>.
;; Also: FBUFPT (M6502, ASTIL)
NumberBufferPointer = $AD

;; Two-byte tokenizer buffer pointer, sharing <NumberBufferPointer>.
;; Also: BUFPTR (M6502)
TokenizePointer = $AD

;; Two-byte string or descriptor pointer, sharing <NumberBufferPointer>.
;; Also: STRNG2 (M6502)
SecondStringPointer = $AD

;; Two-byte polynomial-coefficient pointer, sharing <NumberBufferPointer>.
;; Also: POLYPT (M6502)
PolynomialPointer = $AD

;; Two-byte linear array index, sharing <NumberBufferPointer>.
;; Also: CURTOL (M6502)
LinearIndex = $AD

; Character-fetch code copied to page zero, random state and page-one output buffer.
;; Page-zero character-fetch entry copied from <CharacterReaderTemplate>.
;; Also: CHRGET (M6502, ASTIL, ASRM78)
GetNextCharacter = $B1

;; Page-zero entry to fetch the current character without first incrementing <TextPointer>; it skips spaces.
;; Also: CHRGOT (M6502, ASTIL)
GetCurrentCharacter = $B7

;; Two-byte operand of the load in <GetCurrentCharacter>, the current text pointer.
;; Also: TXTPTR (M6502)
TextPointer = $B8

;; Character classification entry in the page-zero <GetNextCharacter> code.
;; Also: QNUM (M6502)
ClassifyCharacter = $BE

;; Return in the page-zero <GetNextCharacter> code.
;; Also: CHRRTS (M6502)
CharacterReaderReturn = $C8

;; Five-byte floating-point random-number state.
;; Also: RNDX (M6502, ASTIL)
RandomValue = $C9

;; Low byte immediately preceding <NumberBuffer> at the page boundary.
;; Also: LOFBUF (M6502)
NumberBufferPrefix = $FF

;; Numeric output buffer in page one, below the stack.
;; Also: FBUFFR (M6502, ASTIL)
NumberBuffer = $0100

; AppleSoft's own workspace: hi-res graphics, ONERR, and the display and program state.
;; Low byte of the shape or hi-res clear pointer.
;; Also: SHAPEL (UNKN), SHAPE (ASTIL)
ShapePointer = $1A

;; High byte of <ShapePointer>.
;; Also: SHAPEH (UNKN)
ShapePointerHigh = $1B

;; Hi-res color byte being drawn.
;; Also: HCOLR2 (UNKN), HCOLOR1 (ASTIL)
HighResColorByte = $1C

;; Hi-res line step count.
;; Also: HCOUNT (UNKN), COUNTH (ASTIL)
HighResLineCount = $1D

;; Two-byte saved program end.
;; Also: PRGEND (ASTIL, AS82)
ProgramEnd = $AF

;; Two-byte hi-res line X distance.
;; Also: HGRDX (UNKN), DX (ASTIL)
HighResDeltaX = $D0

;; Hi-res line Y distance.
;; Also: HGRDY (UNKN), DY (ASTIL)
HighResDeltaY = $D2

;; Hi-res line quadrant.
;; Also: HGRQUA (UNKN), QDRNT (ASTIL)
HighResQuadrant = $D3

;; Hi-res line error term.
;; Also: HGRE (UNKN)
HighResError = $D4

;; Run-only flag; bit 7 prevents listing and editing.
;; Also: LOCK (UNKN), RNONLY (ASTIL)
RunOnly = $D6

;; `ONERR` flag; bit 7 indicates an active handler.
;; Also: ERRFLG (ASTIL, AS82)
OnErrorActive = $D8

;; Two-byte line number of the last error.
;; Also: ERRLIN (ASTIL, AS82)
ErrorLine = $DA

;; Two-byte text pointer at the last error.
;; Also: ERRPOS (ASTIL, AS82)
ErrorText = $DC

;; Last error code.
;; Also: ERRNUM (ASTIL, AS82)
ErrorCode = $DE

;; Stack pointer at the last error.
;; Also: ERRSTK (ASTIL), NXDIM (AS82)
ErrorStack = $DF

;; Two-byte current hi-res X coordinate.
;; Also: HGRX (UNKN), XO (ASTIL)
HighResX = $E0

;; Current hi-res Y coordinate.
;; Also: HGRY (UNKN), YO (ASTIL)
HighResY = $E2

;; Hi-res color byte.
;; Also: HCOLR1 (UNKN)
HighResColor = $E4

;; Hi-res byte index in the row.
;; Also: HNDX (ASTIL)
HighResByteIndex = $E5

;; Hi-res page high byte, $20 or $40.
;; Also: HPAG (ASTIL)
HighResPage = $E6

;; Shape scale.
;; Also: HSCALE (UNKN)
ShapeScale = $E7

;; Two-byte shape-table address.
;; Also: SHPTBL (UNKN), SHAPX (ASTIL)
ShapeTable = $E8

;; Shape collision count.
;; Also: COLCNT (UNKN), COLLSN (ASTIL)
CollisionCount = $EA

;; Lo-res plotting scratch.
;; Also: FIRST (ASTIL)
LowResFirst = $F0

;; Output delay, represented as 256 minus `SPEED`.
;; Also: SPEEDZ (UNKN), SPDBYT (ASTIL)
OutputDelay = $F1

;; `TRACE` flag, enabled when bit 7 is set.
;; Also: TRCFLG (UNKN), TRFLAG (ASTIL)
TraceMode = $F2

;; Flashing text mask.
;; Also: FLASHB (UNKN), ORMASK (ASTIL)
FlashMask = $F3

;; Two-byte text pointer saved for `RESUME`.
;; Also: TXTPSV (UNKN), ERRTO (ASTIL)
OnErrorText = $F4

;; Two-byte line number saved for `RESUME`.
;; Also: CURLSV (UNKN)
OnErrorLine = $F6

;; Stack pointer saved before a statement.
;; Also: REMSTK (ASTIL)
StatementStack = $F8

;; Shape rotation.
;; Also: HROT (UNKN), ROTBYT (ASTIL)
ShapeRotation = $F9

;; Writable jump vector for the & statement.
;; Also: AMPERV (UNKN)
AmpersandJump = $03F5

; AppleSoft's copies of the Monitor's, the IIe's and the firmware's names, which keep their names until AppleSoft
; includes IIeEquates.asm and MonitorEntries.asm (decision X10). Microsoft's LINWID names $25, which is the
; Monitor's CV and not a width; it is not defined.
;; Monitor line-input entry used by the Microsoft build.
CQINLN = $FD67

;; Monitor prompt character location.
CQPRMP = $33

;; Monitor character-input entry.
CQINCH = $FD0C

;; Monitor cassette-write entry in the Microsoft build.
CQCOUT = $FECD

;; Monitor cassette-read entry in the Microsoft build.
CQCSIN = $FEFD

;; Line input and tokenization buffer in page two.
BUF = $0200

;; Monitor character-output entry.
OUTCH = $FDED

;; Monitor text window's left edge.
WNDLFT = $20

;; Monitor text window width.
WNDWDT = $21

;; Monitor text window's top edge.
WNDTOP = $22

;; Monitor text window's bottom edge.
WNDBTM = $23

;; Monitor cursor column, shared with <TerminalPosition>.
CH = $24

;; Monitor cursor row.
CV = $25

;; Low byte of the Monitor lo-res graphics base address.
GBASL = $26

;; High byte of <GBASL>.
GBASH = $27

;; Low byte of the Monitor text row base address.
BASL = $28

;; High byte of <BASL>.
BASH = $29

;; Monitor lo-res horizontal line endpoint.
H2 = $2C

;; Monitor lo-res vertical line endpoint.
V2 = $2D

;; Monitor lo-res color mask.
MASK = $2E

;; Monitor length scratch.
LENGTH = $2F

;; Monitor lo-res color.
COLOR = $30

;; Monitor mode scratch.
MODE = $31

;; Monitor normal, inverse or flashing text mask.
INVFLG = $32

;; Monitor prompt character.
PROMPT = $33

;; Monitor Y-register scratch.
YSAV = $34

;; Additional Monitor Y-register scratch.
YSAV1 = $35

;; Low byte of the Monitor character-output vector.
CSWL = $36

;; High byte of <CSWL>.
CSWH = $37

;; Low byte of the Monitor character-input vector.
KSWL = $38

;; High byte of <KSWL>.
KSWH = $39

;; Low byte of the Monitor program counter.
PCL = $3A

;; High byte of <PCL>.
PCH = $3B

;; Low byte of the Monitor first address parameter.
A1L = $3C

;; High byte of <A1L>.
A1H = $3D

;; Low byte of the Monitor second address parameter.
A2L = $3E

;; High byte of <A2L>.
A2H = $3F

;; Low byte of the Monitor third address parameter.
A3L = $40

;; High byte of <A3L>.
A3H = $41

;; Low byte of the Monitor fourth address parameter.
A4L = $42

;; High byte of <A4L>.
A4H = $43

;; Low byte of the Monitor fifth address parameter.
A5L = $44

;; High byte of <A5L>.
A5H = $45

;; Monitor saved X register.
XREG = $46

;; Monitor saved Y register.
YREG = $47

;; Monitor saved processor status.
STATUS = $48

;; Low byte of the Monitor keyboard timing counter.
RNDL = $4E

;; High byte of <RNDL>.
RNDH = $4F

;; 80-column firmware horizontal cursor position.
OURCH = $057B


; Hardware switches and Monitor or firmware entry points, which X10 decides.
;; Keyboard data soft switch.
KBD = $C000

;; Select slot ROMs at $C100-$CFFF on the IIe.
SETSLO = $C006

;; Select internal ROM at $C100-$CFFF on the IIe.
SETINT = $C007

;; IIe 80-column display status, in bit 7.
RD80VI = $C01F

;; Select graphics display.
TXTCLR = $C050

;; Select text display.
TXTSET = $C051

;; Select full-screen graphics.
MIXCLR = $C052

;; Select mixed text and graphics.
MIXSET = $C053

;; Select display page one.
LOWSCR = $C054

;; Select display page two.
HISCR = $C055

;; Select lo-res graphics.
LORES = $C056

;; Select hi-res graphics.
HIRES = $C057

;; Monitor lo-res plot entry.
MPLOT = $F800

;; Monitor lo-res horizontal line entry.
HLINE = $F819

;; Monitor lo-res vertical line entry.
VLINE = $F828

;; Monitor lo-res color entry.
SETCOL = $F864

;; Monitor lo-res screen-read entry.
MSCRN = $F871

;; Monitor paddle-read entry.
PREAD = $FB1E

;; Monitor text-mode entry.
SETTXT = $FB39

;; Monitor graphics-mode entry.
SETGR = $FB40

;; Monitor vertical-tab entry.
TABV = $FB5B

;; Monitor home and clear-screen entry.
HOME = $FC58

;; Monitor delay entry.
MWAIT = $FCA8

;; Monitor cassette bit-read entry.
RD2BIT = $FCFA

;; Monitor line-input entry.
GETLN = $FD6A

;; Monitor input-slot selection entry.
INPORT = $FE8B

;; Monitor output-slot selection entry.
OUTPOR = $FE95

;; Monitor cassette-write entry.
MWRITE = $FECD

;; Monitor cassette-read entry.
MREAD = $FEFD

;; Enhanced IIe internal firmware at $C500.
C5ROM = $C500
.org $D000
