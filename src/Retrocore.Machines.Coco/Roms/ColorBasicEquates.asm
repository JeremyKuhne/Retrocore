;; TRS-80 COLOR COMPUTER EQUATES: HARDWARE, THE DIRECT PAGE, PAGE 1, TOKENS AND ERROR CODES
;;
;; The Color Computer's I/O locations and the RAM Color BASIC keeps, with the names Microsoft's BASIC and Spectral
;; Associates' Color BASIC Unravelled give them, then Color BASIC's tokens and error codes and the KEYWORD macro its
;; tables use. Color BASIC, Extended Color BASIC and Disk Extended Color BASIC include this file, so each name here
;; is defined and documented once. Color BASIC's routines, which ColorBasic.asm defines as labels, are in
;; ColorBasicEntries.asm for the others.

; ----------------------------------------------------------------------------------------------------------------
; Hardware
; ----------------------------------------------------------------------------------------------------------------

;; PIA 0: the keyboard, the joystick comparator and the video's sync interrupts.
;;
;; Port A, at <PIA0>, reads the keyboard's rows in bits 0-6 and the joystick comparator in bit 7; port B, at
;; <PIA0>+2, strobes the keyboard's columns. CA1 takes the VDG's HS and CB1 its FS, the 60 Hz field sync that
;; <BIRQSV> counts; both interrupt outputs drive IRQ. CA2 and CB2 select the analog multiplexer's input
;; (<SELMUX>). <INITHW> sets it up; <KEYIN> and <KEYRD> scan the keyboard and <GETJOY> reads the joysticks.
;; See: <PIA1>, <KEYIN>, <GETJOY>, <SELMUX>, <BIRQSV>
PIA0 = $FF00

;; PIA 1: the DAC, the cassette, single-bit sound, the VDG's mode and the cartridge's interrupt.
;;
;; Port A, at <PIA1>, drives the 6-bit DAC in bits 2-7 and serial output in bit 1, and reads the cassette in bit
;; 0. Port B, at <PIA1>+2, reads serial input and the printer's busy line in bit 0 and the RAM size jumper in bit
;; 2, drives single-bit sound in bit 1, and sets the VDG's mode in bits 3-7. CA2 runs the cassette motor
;; (<MOTORON>), CB2 enables sound (<SNDON>), and CB1 takes the cartridge's CART line, whose FIRQ starts a ROM pack
;; (<FIRQSV>).
;; See: <DA>, <PIA0>, <SNDBYT>, <PRINTR>, <CASIN>, <FIRQSV>
PIA1 = $FF20

;; The 6-bit DAC, PIA 1's port A bits 2-7, which plays sound and the cassette's output and finds the joysticks'
;; positions.
;;
;; <SNDBYT> writes <SINTAB>'s steps to it for the cassette, <SNDOUT> a square wave for SOUND, and <GETJOY> searches
;; with it against the comparator.
;; See: <PIA1>, <SINTAB>, <GETJOY>
DA = PIA1

;; The SAM's control bits, $FFC0-$FFDF: a write to an even address clears a bit and to the odd one after it sets
;; it.
;;
;; The bits are the VDG's mode (V0-V2), the display offset (F0-F6), the page (P1), the CPU rate (R0-R1), the
;; memory size (M0-M1) and the map type (TY). <INITHW> clears them all, then sets the display offset for the
;; text screen at <VIDRAM> and the memory size for the RAM chips the jumper names.
;; See: <INITHW>, <VIDRAM>
SAMREG = $FFC0

;; Where Extended Color BASIC's ROM starts, when one is fitted: it begins with EX.
;;
;; <COLDST> looks for EX here and, when it finds it, jumps to the ROM's start after it, $8002, so Extended BASIC
;; signs on instead.
;; See: <COLDST>
EXBAS = $8000

;; Where a ROM pack in the cartridge port starts.
;;
;; <CARTGO> jumps here when the cartridge's interrupt starts the pack (<FIRQSV>).
;; See: <CARTST>, <CARTGO>
ROMPAK = $C000

; ----------------------------------------------------------------------------------------------------------------
; The direct page
; ----------------------------------------------------------------------------------------------------------------

;; How the program stopped: negative for STOP or BREAK, positive for END.
;;
;; <NEWSTT> stores the next line's link's high byte here, zero after the last line, and <STOPIT> rotates the carry
;; into bit 7: set for STOP. <ENDPRG> then shows BREAK and the line when it is negative, and prompts with OK
;; otherwise.
;; See: <STOPIT>, <ENDPRG>, <NEWSTT>
ENDFLG = $00

;; A character that ends a scan, such as a string's closing quote; a scratch byte elsewhere.
;;
;; <STRLT3> stops at it or at <ENDCHR>; <INPRD> sets them for INPUT's items and READ's. <SKPLIN> keeps the
;; terminator outside quotes here, <LINGET> a digit, and <ANDOP> the right side's high byte, with <ENDCHR> its
;; low byte.
;; See: <ENDCHR>, <STRLT3>, <SKPLIN>
CHARAC = $01

;; A second character that ends a scan, as <CHARAC> does.
;;
;; <STRLT2> sets both to a quote; <INPRD> sets a comma here and a colon in <CHARAC>. <ANDOP> keeps the right
;; side's low byte here.
;; See: <CHARAC>, <STRLT3>
ENDCHR = $02

;; A scratch byte.
;;
;; <EDITLN> keeps the crunched line's length here, <ANDOP> zero for AND and nonzero for OR, <ARRAY> the number of
;; subscripts, and <FPDIV> the quotient's bytes still to find.
TMPLOC = $03

;; The IFs still open on the line, which an ELSE counts down.
;;
;; <IF> clears it before skipping a false condition's statements, and <SKPLIN> counts each IF it passes; an ELSE
;; belongs to this IF only when the count is back to zero.
;; See: <IF>, <SKPLIN>
IFCTR = $04

;; Nonzero while DIM makes an array.
;;
;; <DIM> passes 1 to <PTRGT2>, which stores it here; <ARRAY> then makes the array, and raises ?DD ERROR when it
;; exists. <ARRAY> keeps it, with <VALTYP> after it, across the subscripts' evaluation.
;; See: <DIM>, <ARRAY>, <VALTYP>
DIMFLG = $05

;; The type of the value just evaluated: 0 a number, in FPA0, or $FF a string, its descriptor at <FPA0>+2.
;;
;; <EVAL> clears it, <PTRGET> sets it for the variable named, and <PUTNEW> sets it for a string just made.
;; <CKTYPE> and <CKNUM> check it, and <EVLPRC> folds it into the comparison's flags so <RELOP> compares strings.
;; See: <CKTYPE>, <PTRGET>, <EVAL>, <PUTNEW>
VALTYP = $06

;; Set once string space has been collected, so that a second shortage is out of string space.
;;
;; <GETSPA> clears it, and calls <GARBAG> the first time there is not room.
;; See: <GETSPA>, <GARBAG>
GARBFL = $07

;; Nonzero to keep a variable search from finding an array, so that FOR's variable is simple.
;;
;; <FOR> sets it to $80, and <PTRGET> ORs it into the character after the name, so a ( never matches; it then
;; clears it. <RSTSTK> clears it too, and so does SOUND, for no reason the code shows.
;; See: <PTRGET>, <FOR>
ARYDIS = $08

;; Zero while READ takes values, nonzero for INPUT.
;;
;; <INPRD> sets it from A: READ enters with A nonzero. <BADINP> and <INPRD> test it to tell the two apart.
;; See: <INPRD>, <READ>, <BADINP>
INPFLG = $09

;; The relational operators a comparison asks for: bit 0 >, bit 1 =, bit 2 <.
;;
;; <EVLPRC> sets it from <TRELFL> as it applies the comparison, and <RELOP> ANDs the result's bit with it.
;; <SIN> uses it for scratch.
;; See: <TRELFL>, <RELOP>, <EVLPRC>
RELFLG = $0A

;; The next free entry in the string descriptor stack, <STRSTK>.
;;
;; <PUTNEW> pushes a descriptor there, <FRETMS> pops the last, and <RSTSTK> empties the stack. <GARBAG> collects
;; the strings of every entry below it.
;; See: <STRSTK>, <LASTPT>, <PUTNEW>, <FRETMS>
TEMPPT = $0B

;; The last entry pushed on the string descriptor stack.
;;
;; <PUTNEW> sets it, and <FRETMS> pops an entry only when it is this one.
;; See: <TEMPPT>, <PUTNEW>, <FRETMS>
LASTPT = $0D

;; A scratch pointer.
;;
;; <FNDFOR> keeps the stack entry it is looking at here, which <FOR> uses to drop an old loop; <ARRAY> keeps the
;; first element of an array it makes.
;; See: <FNDFOR>
TEMPTR = $0F

;; A second scratch pointer.
;;
;; <FNDFOR> keeps the variable of the FOR entry it is looking at here.
;; See: <FNDFOR>
TMPTR1 = $11

;; Floating point accumulator 2's mantissa, four bytes, where multiply and divide build their results.
;;
;; <FMULT> adds into it through <MULBYT>, and <FPDIV> stores the quotient's bytes; <MOVF2> then moves it into
;; FPA0. <RNDNEW> takes a byte of the product from it.
;; See: <FMULT>, <FPDIV>, <MOVF2>
FPA2 = $13

;; The stack's bottom when it was last checked for room.
;;
;; <CHKMEM> stores S here to compare with; <ARYMUL> uses it for a dimension's size.
;; See: <CHKMEM>
BOTSTK = $17

;; The start of the program, just after the zero byte before it.
;;
;; <COLDST> sets it, at $0601 on 1.0 and $0401 later. <FINDLN>, <LINKLN>, <ERASEP>, <RESTORE>, <GOTO> and the
;; cassette's <CSAVE> and <CLOAD> start from it.
;; See: <VARTAB>, <ERASEP>, <FINDLN>
TXTTAB = $19

;; The start of the simple variables, just past the program.
;;
;; <ERASEP>, <EDITLN> and a CLOAD set it as the program changes size; <CLRSTR> starts the arrays there, and
;; <PTRGET> searches the variables from it to <ARYTAB>.
;; See: <TXTTAB>, <ARYTAB>, <PTRGET>
VARTAB = $1B

;; The start of the arrays, just past the simple variables.
;;
;; <CLRSTR> sets it to <VARTAB>; <PTRGET> moves it up seven bytes for each variable it makes, and <ARRAY> searches
;; the arrays from it to <ARYEND>.
;; See: <VARTAB>, <ARYEND>, <ARRAY>
ARYTAB = $1D

;; The end of the arrays plus one: the start of free memory.
;;
;; <CLRSTR> sets it; <PTRGET> and <ARRAY> move it up as they make variables and arrays. <GETSTK> and <MEM> measure
;; the room from it to the stack.
;; See: <ARYTAB>, <GETSTK>, <MEM>
ARYEND = $1F

;; The start of string space, with the stack just below it.
;;
;; <COLDST> sets it 200 bytes below the top of RAM, and CLEAR (<CLEAR>) where the program asks. <RSTSTK> puts the
;; stack under it, and <GETSPA> raises ?OS ERROR rather than go below it.
;; See: <MEMSIZ>, <STRTAB>, <CLEAR>, <GETSPA>
FRETOP = $21

;; The start of the strings in use, which grow down from <MEMSIZ>.
;;
;; <GETSPA> moves it down to make room, <GARBAG> rebuilds it from the strings still in use, and <FRETMP> moves it up
;; when the last string made is freed. <CLRSTR> sets it to <MEMSIZ>.
;; See: <FRETOP>, <MEMSIZ>, <GETSPA>, <GARBAG>
STRTAB = $23

;; The last string made: where <MOVINS> copies a string's text.
;;
;; <GETSPA> sets it to the room it reserved, and <MOVINS> moves it past what it copies.
;; See: <GETSPA>, <MOVINS>
FRESPC = $25

;; The top of string space: the highest address BASIC uses.
;;
;; <COLDST> sets it to the top of RAM, and CLEAR (<CLEAR>) to the address the program gives. Strings grow down from
;; it.
;; See: <FRETOP>, <STRTAB>, <TOPRAM>
MEMSIZ = $27

;; The line STOP or BREAK left, for CONT.
;;
;; <ENDPRG> sets it when a program stops, and <CONT> takes it back.
;; See: <OLDPTR>, <ENDPRG>, <CONT>
OLDTXT = $29

;; The binary value of a line number, or another 16-bit number being read.
;;
;; <LINGET> builds a line number here, which <FINDLN>, <GOTO>, <EDITLN> and <LIST> use. <INPRD> keeps the
;; statement's place here while it reads an item, and <ADRBYT> keeps POKE's address.
;; See: <LINGET>, <FINDLN>
BINVAL = $2B

;; Where in the program STOP or BREAK left, for CONT: zero when the program cannot be continued.
;;
;; <ENDPRG> sets it from <TINPTR>, <RSTSTK> clears it, and <CONT> raises ?CN ERROR when it is zero.
;; See: <OLDTXT>, <TINPTR>, <CONT>
OLDPTR = $2D

;; Where the statement being run starts.
;;
;; <NEWSTT> sets it before each statement, and <STOP> when BREAK stops one; <ENDPRG> keeps it for CONT, and
;; <BADINP> goes back to it to run INPUT again after ?REDO.
;; See: <NEWSTT>, <OLDPTR>, <BADINP>
TINPTR = $2F

;; The line number of the DATA statement READ is in.
;;
;; <INPRD> sets it as READ moves from line to line, and <BADINP> reports a syntax error in that line.
;; See: <DATPTR>, <INPRD>
DATTXT = $31

;; Where READ takes its next item: just before the program at first.
;;
;; <RESTORE> sets it, and <INPRD> moves it on after READ (<RESTORE_SET>).
;; See: <DATTXT>, <RESTORE>, <READ>
DATPTR = $33

;; Where INPUT or READ is reading its values.
;;
;; <INPRD> sets it to the line typed or to <DATPTR>, and moves it on after each item.
;; See: <INPRD>
DATTMP = $35

;; The name of the variable being looked up: its first character, then its second, with bit 7 set for a string.
;;
;; <PTRGT2> builds it, and <PTRGET> and <ARRAY> search for it and store it in what they make.
;; See: <PTRGET>, <ARRAY>
VARNAM = $37

;; The value of the variable or array element just found.
;;
;; <PTRGET> and <ARRAY> set it.
;; See: <PTRGET>, <ARRAY>
VARPTR = $39

;; A variable's value, kept while an expression is evaluated for it.
;;
;; <LET>, <INPRD> and <NEXT> set it for the variable to store into, and <MOVVAR> and <LETSTR> store there. <FNDFOR>
;; looks for the FOR of the variable here, or with zero sets it to the innermost's.
;; See: <LET>, <MOVVAR>, <FNDFOR>
VARDES = $3B

;; The routine of the operator waiting on the stack.
;;
;; <EVLPRC> keeps the operator's entry here while it decides whether to apply it.
;; See: <EVLPRC>
RELPTR = $3D

;; The relational operators of the comparison being read: bit 0 >, bit 1 =, bit 2 <.
;;
;; <EVLPRC> builds it from >, = and <, and raises ?SN ERROR when one comes twice; it becomes <RELFLG> when the
;; comparison is applied. <RELOP> clears bit 0 when it compares strings.
;; See: <RELFLG>, <EVLPRC>
TRELFL = $3F

;; Scratch: a number packed in five bytes, <V40>-<V44>.
;;
;; <MOVV40> packs FPA0 here: <FADDB> keeps the number it adds a digit to, <ODDPOL> the x its polynomial multiplies
;; by, and <RND> its n. The same bytes are <V41>-<V44> to other routines.
;; See: <MOVV40>, <V41>
V40 = $40

;; Scratch, two bytes: the end a block moves up to.
;;
;; <MOVEUP> moves <V47>..<V43> up to end at it, as <EDITLN>, <PTRGET> and <GARBAG> set them. <ARRAY> keeps the
;; array it makes here, and <CRUNCH> whether it is looking for commands (0) or functions ($FF).
;; See: <MOVEUP>, <V43>, <V47>
V41 = $41

;; Scratch.
;;
;; <CRUNCH> counts the token it is trying here, and keeps the character that ends a quoted string or REM.
;; See: <CRUNCH>
V42 = $42

;; Scratch, two bytes: the end of a block to move up.
;;
;; <MOVEUP> moves the block from <V47> to it. <CRUNCH> uses <V43> as the flag that it is inside a name.
;; See: <MOVEUP>, <V41>, <V47>
V43 = $43

;; Scratch.
;;
;; <CRUNCH> sets it inside DATA, which keeps the rest of the statement as it is.
;; See: <CRUNCH>
V44 = $44

;; Scratch, two bytes: where a moved block starts now; a packed number over $45-$49.
;;
;; <MOVEUP> leaves the block's new start here. <MOVV45> packs FPA0 here for <POLY>'s x. <FIN> counts the digits
;; after the point here, <FOUT> the power of ten and then the digits before the point, and <ARYMUL> its bits.
;; See: <MOVEUP>, <MOVV45>, <POLY>
V45 = $45

;; Scratch.
;;
;; <FIN> sets it once a number's point is read.
;; See: <FIN>
V46 = $46

;; Scratch, two bytes: the start of a block to move up.
;;
;; <MOVEUP> moves the block from it; <FINDLN> leaves the line it found here. <FIN> keeps the exponent here and
;; <FOUT> the exponent it shows. <GARBAG> keeps the highest string found.
;; See: <MOVEUP>, <FINDLN>, <V48>
V47 = $47

;; Scratch, two bytes.
;;
;; <FIN> sets it for a negative exponent.
;; See: <FIN>, <V47>
V48 = $48

;; Scratch: nothing in Color BASIC uses it.
V4A = $4A

;; Scratch, two bytes: the descriptor of the string <GARBAG> moves next.
;;
;; See: <GARBAG>
V4B = $4B

;; Scratch, two bytes: a string's descriptor, kept while room is made for a copy.
;;
;; <STRINI> keeps X here, and <LETSTR>, <CAT>, <STRARG> and <SUBSTR> keep the string they are working from.
;; See: <STRINI>, <LETSTR>
V4D = $4D

;; Floating point accumulator 0's exponent: zero for the number zero, and otherwise $80 plus the power of 2.
;;
;; FPA0 is the value most routines work on: an exponent here, a four-byte mantissa at <FPA0> with its top bit set,
;; and a sign at <FP0SGN>. <MOVFM> unpacks a number into it and <MOVMF> packs it; <NORMAL> normalizes it after
;; arithmetic.
;; See: <FPA0>, <FP0SGN>, <FP1EXP>, <MOVFM>, <MOVMF>
FP0EXP = $4F

;; Floating point accumulator 0's mantissa, four bytes, normalized with bit 7 set.
;;
;; <QINT> turns it into a 32-bit integer in place, and <INTCNV> takes its low two bytes as D. A string's value is
;; its descriptor's address, at <FPA0>+2.
;; See: <FP0EXP>, <FP0SGN>, <QINT>
FPA0 = $50

;; Floating point accumulator 0's sign: bit 7 set when negative.
;;
;; <MOVFM> takes it from the packed number's top mantissa bit, and <MOVMF> puts it back. <NEGATE> flips it.
;; See: <FP0EXP>, <FPA0>, <NEGATE>
FP0SGN = $54

;; The coefficients left in a polynomial; the number's sign while <FIN> reads it.
;;
;; <POLY> counts it down. <FIN> sets it for a leading minus sign.
;; See: <POLY>, <FIN>
COEFCT = $55

;; A temporary string descriptor, five bytes: the length, a spare byte, then the text's address.
;;
;; <STRSET> fills it, and <PUTNEW> pushes it onto <STRSTK>. <RELOP> keeps the right string's length and address
;; here while it compares.
;; See: <STRSET>, <PUTNEW>, <STRSTK>
STRDES = $56

;; What fills from the left when a mantissa shifts right: zero, or $FF for a negative integer.
;;
;; <QINT> sets it while it shifts a negative number, and <SHIFTR> fills from it.
;; See: <SHIFTR>, <QINT>
FPCARY = $5B

;; Floating point accumulator 1's exponent: the second operand of arithmetic.
;;
;; <CONUPK> unpacks a number into FPA1, <MOVAF> copies FPA0 into it, and <EVLPRC> pops the left operand into it
;; before an operator's routine runs.
;; See: <FPA1>, <FP1SGN>, <FP0EXP>, <CONUPK>
FP1EXP = $5C

;; Floating point accumulator 1's mantissa, four bytes.
;;
;; <FPDIV> subtracts and shifts it as it divides; <RELOP> holds the left string's descriptor at <FPA1>+2.
;; See: <FP1EXP>, <FP1SGN>
FPA1 = $5D

;; Floating point accumulator 1's sign: bit 7 set when negative.
;;
;; See: <FP1EXP>, <FPA1>
FP1SGN = $61

;; The sign of a result: FPA0's sign EOR FPA1's.
;;
;; <CONUPK> and <EVLPRC> set it; <FPADD> adds in two's complement when it is negative, and <MULDIV> gives it to
;; the product or quotient.
;; See: <CONUPK>, <FPADD>, <MULDIV>
RESSGN = $62

;; The fifth mantissa byte, the bits below FPA0's, kept for rounding.
;;
;; <FPADD>, <FMULT> and <FPDIV> leave their extra bits here, <NORMAL> shifts them in, and <ROUND> rounds on its top
;; bit.
;; See: <NORMAL>, <ROUND>
FPSBYT = $63

;; The next coefficient of a polynomial; a scratch pointer elsewhere.
;;
;; <POLY> steps it through the coefficients. <STRLT3> leaves where a scan stopped here, <ARRAY> an element's size
;; and the index so far, and <FOUT> where the digits start.
;; See: <POLY>, <STRLT3>
COEFPT = $64

;; The line LIST shows next.
;;
;; <LIST> sets it to the range's first line and moves it through the program.
;; See: <LIST>
LSTTXT = $66

;; The line being run, or $FFFF in direct mode.
;;
;; <MAINLP> sets $FFFF, <NEWSTT> each line's number as it reaches it, and <RETURN> and <CONT> the line they go back
;; to. <REPORT> shows it after an error, and INPUT (<INPUT>) is refused in direct mode.
;; See: <NEWSTT>, <MAINLP>, <REPORT>
CURLIN = $68

;; The output device's print zone width.
;;
;; <SETPRM> sets <DEVCFW> to <DEVWID> for the device in <DEVNUM>, and <PRINTL> moves to the next zone with it.
;; See: <SETPRM>, <DEVLCF>, <PRINTL>
DEVCFW = $6A

;; The column of the output device's last print zone: a comma past it starts a new line.
;;
;; See: <SETPRM>, <DEVCFW>, <PRINTL>
DEVLCF = $6B

;; The output device's column.
;;
;; <SETPRM> sets it from the cursor or the printer's carriage; <NEWLIN>, <PRINTL> and TAB( use it.
;; See: <SETPRM>, <NEWLIN>
DEVPOS = $6C

;; The output device's line width; zero for the cassette, which has none.
;;
;; See: <SETPRM>
DEVWID = $6D

;; Nonzero when the output device is the cassette.
;;
;; <SETPRM> sets it. <PRINTL> then ends each item with a carriage return and pads no zones, and <INPRD> reads a
;; whole line as a string.
;; See: <SETPRM>, <PRINTL>
PRTDEV = $6E

;; The device for input and output: 0 the screen, -1 the cassette, -2 the printer; Disk BASIC adds its files.
;;
;; <SETDEV> sets it from a device number, LLIST (<LLIST>) to the printer, and most statements back to the screen
;; when they end. <PUTCHR> and <CONIN> go where it says.
;; See: <SETDEV>, <PUTCHR>, <CONIN>, <SETPRM>
DEVNUM = $6F

;; Nonzero once a cassette file being read has ended.
;;
;; <CONIN> sets it when no characters are left, and <LINEIN> and <MAINLP> then end the line and the load.
;; See: <CONIN>, <LINEIN>, <LDEND>
CINBFL = $70

;; $55 when <RSTVEC> holds a warm start; anything else cold starts on RESET.
;;
;; <COLDST> sets $55, and <CARTGO> clears it, so a ROM pack's RESET cold starts. <WARMCK> checks it.
;; See: <RSTVEC>, <WARMCK>
RSTFLG = $71

;; The warm start's address, whose first instruction must be NOP.
;;
;; <COLDST> points it at <BAWMST>; Extended and Disk BASIC point it at their own.
;; See: <RSTFLG>, <WARMCK>, <BAWMST>
RSTVEC = $72

;; The top of RAM.
;;
;; <COLDST> sets it after testing RAM a byte at a time, and CLEAR (<CLEAR>) cannot raise <MEMSIZ> past it.
;; See: <MEMSIZ>, <COLDST>
TOPRAM = $74

;; The cassette file's state: 0 closed, 1 open for input, 2 open for output.
;;
;; <OPENIN> and <WRHDR> open it, <CLSONE> closes it, and <CHKIN>, <CHKOUT> and <PUTCHR> check it.
;; See: <CLSONE>, <CHKIN>, <CHKOUT>
FILSTA = $78

;; The characters in the cassette buffer: left to read, or written so far.
;;
;; <RDDATA> sets it from a data block's length, <CONIN> counts it down and <PUTCHR> up; <WDATBK> writes the block
;; when it fills.
;; See: <CINPTR>, <CONIN>, <PUTCHR>
CINCTR = $79

;; Where the next character comes from, or goes to, in the cassette buffer <CASBUF>.
;;
;; See: <CINCTR>, <EMPTYB>
CINPTR = $7A

;; The cassette block's type: 0 the header, 1 data, $FF the end of the file.
;;
;; <GETBLK> reads it and <SNDBLK> writes it.
;; See: <BLKLEN>, <GETBLK>, <SNDBLK>
BLKTYP = $7C

;; The cassette block's length, 0-255.
;;
;; See: <BLKTYP>, <GETBLK>, <SNDBLK>
BLKLEN = $7D

;; The cassette block's buffer: where <GETBLK> reads and <SNDBLK> writes.
;;
;; <WRBLK> and <SEARCH> set it to <CASBUF>, and CLOAD and CSAVE to the program.
;; See: <GETBLK>, <SNDBLK>
CBUFAD = $7E

;; The cassette block's checksum: the sum of its type, length and data.
;;
;; See: <GETBLK>, <SNDBLK>
CCKSUM = $80

;; A cassette block's error: 0 none, 1 a bad checksum, 2 a byte that did not stay in RAM.
;;
;; <GETBLK> sets it, using it first to count the data bytes, and <RDBLK> returns it.
;; See: <GETBLK>, <RDBLK>
CSRERR = $81

;; The width of the cassette pulse just timed; a counter for <RDBYTE> and <CASON>.
;;
;; <RDBYTE> counts the bits of a byte here, and <CASON> the pattern of a leader found so far.
;; See: <RDBYTE>, <CASON>
CPULWD = $82

;; The time of a cassette cycle, counted in samples.
;;
;; <CASIN> counts each sample here, and <RDBIT> and <PERCMP> compare it with the limits.
;; See: <CASIN>, <RDBIT>, <CMPMID>
CPERTM = $83

;; The transition the cassette's cycles are timed from: 0 high to low, $A0 low to high.
;;
;; <CASON> sets it when it finds the leader, and <RDCYC> follows it.
;; See: <CASON>, <RDCYC>
CBTPHA = $84

;; The last <SINTAB> value written to the DAC, where the next cycle starts.
;;
;; See: <SNDBYT>, <SINTAB>
CLSTSN = $85

;; The graphics block SET, RESET and POINT work on: its bit in the character cell.
;;
;; <GRCELL> sets it.
;; See: <GRCELL>, <SET>, <RESET>, <POINT>
GRBLOK = $86

;; A key the BREAK check read, kept for INKEY$; zero when there is none.
;;
;; <ISCNTC> keeps any key but BREAK and SHIFT-@ here, and <INKEY> returns it first.
;; See: <ISCNTC>, <INKEY>
IKEYIM = $87

;; The cursor's screen address.
;;
;; <SCRCHR> writes there and moves it, <SETCUR> sets it for PRINT @, and <BLINK> blinks the character there.
;; See: <SCRCHR>, <SETCUR>, <BLINK>, <VIDRAM>
CURPOS = $88

;; Always zero: a word to load a zero from, and the value of a variable read before it is set.
;;
;; See: <PTRGET>
ZERO = $8A

;; SOUND's tone, 1-255: the half cycle's delay counts up from it.
;;
;; See: <SOUND>, <SNDOUT>
SNDTON = $8C

;; SOUND's duration, in 60ths of a second, which the 60 Hz interrupt counts down.
;;
;; See: <SOUND>, <BIRQSV>
SNDDUR = $8D

;; The cassette cycle length between 1200 and 2400 Hz: shorter is a 1.
;;
;; <COLDST> copies 18 here from <DPIMAG>.
;; See: <RDBIT>, <CMP0>, <CMP1>
CMPMID = $8F

;; The longest cassette half cycle that reads as 1200 Hz: longer is a dropout.
;;
;; See: <PERCMP>, <CMP1>
CMP0 = $90

;; The longest cassette half cycle that reads as 2400 Hz.
;;
;; See: <PERCMP>, <CMP0>
CMP1 = $91

;; The $55 bytes a cassette leader has.
;;
;; See: <WRLDR>
SYNCLN = $92

;; The cursor's blink delay: its color changes every eleventh wait.
;;
;; See: <BLINK>
BLKCNT = $94

;; The printer's baud rate constant: half a bit time in <WAITX>'s loops.
;;
;; 88 is 600 baud; 1.0 and 1.1 start it at 87.
;; See: <BAUDLY>, <PRINTR>
LPTBTD = $95

;; The printer's delay after a carriage return.
;;
;; See: <CRDLY>, <PRINTR>
LPTLND = $97

;; The printer's print zone width.
;;
;; See: <SETPRM>, <LPTLCF>
LPTCFW = $99

;; The column of the printer's last print zone.
;;
;; See: <SETPRM>, <LPTCFW>
LPTLCF = $9A

;; The printer's line width: a line that reaches it ends with the carriage return delay.
;;
;; See: <PRINTR>, <SETPRM>
LPTWID = $9B

;; The printer's carriage position.
;;
;; See: <PRINTR>, <SETPRM>
LPTPOS = $9C

;; The address EXEC runs without an argument: CLOADM's start, or ?FC ERROR at first.
;;
;; See: <EXEC>, <CLOADM>
EXECJP = $9D

;; Gets the program's next character: a routine copied into RAM at power on, from <DPIMAG>.
;;
;; It advances <CHARAD>, then reads the character as <GETCCH> does.
;;
;; Out:  A = the character, carry = set for a digit, zero = set at a statement's end
;; See: <GETCCH>, <CHARAD>, <BROMHK>
GETNCH = $9F

;; Gets the current character again, skipping spaces, as <GETNCH> does without advancing.
;;
;; Out:  A = the character, carry = set for a digit, zero = set at a statement's end
;; See: <GETNCH>, <CHARAD>, <BROMHK>
GETCCH = $A5

;; Where in the program BASIC is reading: the operand of <GETCCH>'s LDA, so the routine reads through it.
;;
;; <GETNCH> advances it; <SETPTR> and <ColorBasic:BACKUP> move it, and <NEWSTT> and the GOTO family set it.
;; See: <GETNCH>, <SETPTR>
CHARAD = $A6

;; The highest byte of a product's low bytes, below FPA2, kept for RND.
;;
;; <FMULT> stores the product's low bytes in <VAB>-<VAE>, and <RNDNEW> adds them into the next random number.
;; See: <FMULT>, <RNDNEW>
VAB = $AB

;; Inherit: <VAB>
VAC = $AC

;; Inherit: <VAB>
VAD = $AD

;; Inherit: <VAB>
VAE = $AE

; ----------------------------------------------------------------------------------------------------------------
; Page 1 and the buffers
; ----------------------------------------------------------------------------------------------------------------

;; SWI3's JMP, which <VECTRS> sends SWI3 to.
;;
;; Color BASIC leaves it; Disk BASIC uses it.
;; See: <VECTRS>
SW3VEC = $0100

;; SWI2's JMP, which <VECTRS> sends SWI2 to.
;;
;; See: <VECTRS>
SW2VEC = $0103

;; SWI's JMP, which <VECTRS> sends SWI to.
;;
;; See: <VECTRS>
SWIVEC = $0106

;; NMI's JMP, which <VECTRS> sends NMI to; Disk BASIC's controller interrupts through it.
;;
;; See: <VECTRS>
NMIVEC = $0109

;; IRQ's JMP, which <VECTRS> sends IRQ to: <BIRQSV>, the 60 Hz interrupt, until a later ROM changes it.
;;
;; <COLDST> copies the JMPs from here to the end of <COMVEC>'s first table from <PG1IMG>.
;; See: <BIRQSV>, <PG1IMG>, <VECTRS>
IRQVEC = $010C

;; FIRQ's JMP, which <VECTRS> sends FIRQ to: <FIRQSV>, which starts a ROM pack.
;;
;; See: <FIRQSV>, <PG1IMG>
FRQVEC = $010F

;; USR's JMP: ?FC ERROR in Color BASIC. Extended BASIC keeps TIMER here instead.
;;
;; See: <PG1IMG>
USRJMP = $0112

;; The random number seed, five bytes: RND's last number.
;;
;; See: <RND01>, <RNDNEW>
RVSEED = $0115

;; The keyboard's case: $FF upper, 0 lower; SHIFT-0 toggles it.
;;
;; See: <KEYIN>
CASFLG = $011A

;; The keyboard's debounce delay, in <WAITX>'s loops.
;;
;; See: <KEYIN>, <DEBDEL>
DEBVAL = $011B

;; The JMP that raises a number to a power: ?SN ERROR until Extended BASIC.
;;
;; <OPTAB>'s ^ entry goes here.
;; See: <OPTAB>, <PG1IMG>
EXPJMP = $011D

;; The command tables: ten bytes each for Color, Extended and Disk BASIC.
;;
;; Each table is the number of commands, their reserved words and their routines, then the number of functions,
;; their words and their routines. <GONE2>, <EVAL_FN>, <CRUNCH> and <DETOK> walk them, so a later ROM adds its
;; words by filling its own table.
;; See: <COMWRD>, <COMDSP>, <FUNWRD>, <FUNDSP>, <GONE2>, <CRUNCH>
COMVEC = $0120

;; Extended BASIC's USR0-USR9 addresses: ?FC ERROR, or ?SN ERROR on 1.0, until set.
;;
;; See: <COLDST>
USR0 = $013E

;; The keyboard's columns as the last scan saw them, eight bytes.
;;
;; <KEYIN> compares each column with its byte here to find a key newly pressed.
;; See: <KEYIN>
KEYBUF = $0152

;; The joysticks' positions, 0-63: right horizontal, right vertical, left horizontal, left vertical.
;;
;; <GETJOY> reads all four; <JOYSTK> returns one.
;; See: <GETJOY>, <JOYSTK>
POTVAL = $015A

;; A RAM hook: three bytes Color BASIC fills with RTS, which Extended and Disk BASIC replace with a JMP. Called by
;; OPEN.
;;
;; <COLDST> fills <RVEC0> to <RVEC24> with RTS.
;; See: <OPEN>, <COLDST>
RVEC0 = $015E

;; Inherit: <RVEC0>
;; Called by <SETDEV>, to check a device number.
RVEC1 = $0161

;; Inherit: <RVEC0>
;; Called by <SETPRM>, to set the print parameters.
RVEC2 = $0164

;; Inherit: <RVEC0>
;; Called by <PUTCHR>, for console out.
RVEC3 = $0167

;; Inherit: <RVEC0>
;; Called by <CONIN>, for console in.
RVEC4 = $016A

;; Inherit: <RVEC0>
;; Called by <CHKIN>, to check an input device.
RVEC5 = $016D

;; Inherit: <RVEC0>
;; Called by <CHKOUT>, to check an output device.
RVEC6 = $0170

;; Inherit: <RVEC0>
;; Called by <CLSALL>, to close every file.
RVEC7 = $0173

;; Inherit: <RVEC0>
;; Called by <CLSONE>, to close one file.
RVEC8 = $0176

;; Inherit: <RVEC0>
;; Called by <PRINTL>, for PRINT.
RVEC9 = $0179

;; Inherit: <RVEC0>
;; Called by <INPRD>, for INPUT.
RVEC10 = $017C

;; Inherit: <RVEC0>
;; Called by <CHKBRK>, for the BREAK check.
RVEC11 = $017F

;; Inherit: <RVEC0>
;; Called by <LINEIN>, as it reads a line.
RVEC12 = $0182

;; Inherit: <RVEC0>
;; Called by <LDEND>, as loading a program in text ends.
RVEC13 = $0185

;; Inherit: <RVEC0>
;; Called by <EOF>.
RVEC14 = $0188

;; Inherit: <RVEC0>
;; Called by <EVAL>, as it evaluates a term.
RVEC15 = $018B

;; Inherit: <RVEC0>
;; Called by <ERROR>, reserved for ON ERROR GOTO.
RVEC16 = $018E

;; Inherit: <RVEC0>
;; Called by <ERROR>, the error handler.
RVEC17 = $0191

;; Inherit: <RVEC0>
;; Called by <RUN>.
RVEC18 = $0194

;; Inherit: <RVEC0>
;; Called by <FIN>, as it reads a number.
RVEC19 = $0197

;; Inherit: <RVEC0>
;; Called by <NEWSTT>, before each statement.
RVEC20 = $019A

;; Inherit: <RVEC0>
;; Called by <GRCELL>, for SET, RESET and POINT.
RVEC21 = $019D

;; Inherit: <RVEC0>
;; Called by <CLS>.
RVEC22 = $01A0

;; Inherit: <RVEC0>
;; Called by <CRUNCH>; Extended BASIC checks for RENUM's tokens.
RVEC23 = $01A3

;; Inherit: <RVEC0>
;; Called by <DETOK>; Extended BASIC uses it for GET and PUT.
RVEC24 = $01A6

;; The string descriptor stack: eight entries of five bytes, for the strings an expression makes.
;;
;; <PUTNEW> pushes onto it at <TEMPPT>, raising ?ST ERROR when it is full, and <RSTSTK> empties it.
;; See: <TEMPPT>, <LASTPT>, <PUTNEW>, <STRDES>
STRSTK = $01A9

;; The cassette file name: its length, then the name padded with spaces to eight characters.
;;
;; <GETNAM> reads it; <WRHDR> writes it into a header, and <SEARCH> looks for it.
;; See: <GETNAM>, <SEARCH>, <CASBUF>
CFNBUF = $01D1

;; The cassette buffer, 256 bytes: a data block, or a header.
;;
;; A header holds the file's name in its first eight bytes, then its type (0 a BASIC program, 1 data, 2 machine
;; language), the text flag, the gap flag, and for machine language its start and load addresses.
;; See: <CFNBUF>, <WRHDR>, <SEARCH>, <RDDATA>
CASBUF = $01DA

;; The two bytes before the line input buffer, where <EDITLN> puts a new line's number.
;;
;; <EDITLN> copies the line into the program from <LINHDR>-2, with its link and number before the text.
;; See: <LINBUF>, <EDITLN>
LINHDR = $02DA

;; The line input buffer: <LINEIN> reads a line here, and <CRUNCH> crunches it in place.
;;
;; <DETOK> also expands a program line here for LIST.
;; See: <LINEIN>, <CRUNCH>, <DETOK>, <LBUFMX>
LINBUF = $02DC

;; The line input buffer's length, 250.
;;
;; See: <LINBUF>, <LINEIN>
LBUFMX = 250

;; Where a number is turned into text, for PRINT and STR$.
;;
;; <FOUT> writes the text from <STRBUF>+3.
;; See: <FOUT>, <STR>
STRBUF = $03D7

;; The text screen, 32 by 16 characters, $0400-$05FF.
;;
;; The screen stores text as the VDG shows it: $40-$7F normal and $00-$3F inverse, and graphics characters with
;; bit 7 set. <SCRCHR> writes it, <CLRSCN> clears it and <GRCELL> finds a graphics block in it.
;; See: <SCRCHR>, <CLRSCN>, <CURPOS>
VIDRAM = $0400

; ----------------------------------------------------------------------------------------------------------------
; Tokens and error codes
; ----------------------------------------------------------------------------------------------------------------

; Tokens: a reserved word in a program line is stored as one byte, $80 plus its place in <COMWRD>.
TK_FOR = $80                        ;; FOR
TK_GO = $81                         ;; GO, as in GOTO and GOSUB
TK_REM = $82                        ;; REM
TK_APOS = $83                       ;; ', short for REM
TK_ELSE = $84                       ;; ELSE
TK_IF = $85                         ;; IF
TK_DATA = $86                       ;; DATA
TK_PRINT = $87                      ;; PRINT
TK_ON = $88                         ;; ON
TK_INPUT = $89                      ;; INPUT
TK_END = $8A                        ;; END
TK_NEXT = $8B                       ;; NEXT
TK_DIM = $8C                        ;; DIM
TK_READ = $8D                       ;; READ
TK_RUN = $8E                        ;; RUN
TK_RESTORE = $8F                    ;; RESTORE
TK_RETURN = $90                     ;; RETURN
TK_STOP = $91                       ;; STOP
TK_POKE = $92                       ;; POKE
TK_CONT = $93                       ;; CONT
TK_LIST = $94                       ;; LIST
TK_CLEAR = $95                      ;; CLEAR
TK_NEW = $96                        ;; NEW
TK_CLOAD = $97                      ;; CLOAD
TK_CSAVE = $98                      ;; CSAVE
TK_OPEN = $99                       ;; OPEN
TK_CLOSE = $9A                      ;; CLOSE
TK_LLIST = $9B                      ;; LLIST
TK_SET = $9C                        ;; SET
TK_RESET = $9D                      ;; RESET
TK_CLS = $9E                        ;; CLS
TK_MOTOR = $9F                      ;; MOTOR
TK_SOUND = $A0                      ;; SOUND
TK_AUDIO = $A1                      ;; AUDIO
TK_EXEC = $A2                       ;; EXEC
TK_SKIPF = $A3                      ;; SKIPF
TK_TAB = $A4                        ;; TAB(
TK_TO = $A5                         ;; TO
TK_SUB = $A6                        ;; SUB, as in GOSUB
TK_THEN = $A7                       ;; THEN
TK_NOT = $A8                        ;; NOT
TK_STEP = $A9                       ;; STEP
TK_OFF = $AA                        ;; OFF
TK_PLUS = $AB                       ;; +
TK_MINUS = $AC                      ;; -
TK_TIMES = $AD                      ;; *
TK_DIVIDE = $AE                     ;; /
TK_POWER = $AF                      ;; ^
TK_AND = $B0                        ;; AND
TK_OR = $B1                         ;; OR
TK_GREATER = $B2                    ;; >
TK_EQUAL = $B3                      ;; =
TK_LESS = $B4                       ;; <

; Function tokens: $FF, then $80 plus the function's place in <FUNWRD>.
TK_SGN = $80                        ;; SGN
TK_INT = $81                        ;; INT
TK_ABS = $82                        ;; ABS
TK_USR = $83                        ;; USR
TK_RND = $84                        ;; RND
TK_SIN = $85                        ;; SIN
TK_PEEK = $86                       ;; PEEK
TK_LEN = $87                        ;; LEN
TK_STR = $88                        ;; STR$
TK_VAL = $89                        ;; VAL
TK_ASC = $8A                        ;; ASC
TK_CHR = $8B                        ;; CHR$
TK_EOF = $8C                        ;; EOF
TK_JOYSTK = $8D                     ;; JOYSTK
TK_LEFT = $8E                       ;; LEFT$
TK_RIGHT = $8F                      ;; RIGHT$
TK_MID = $90                        ;; MID$
TK_POINT = $91                      ;; POINT
TK_INKEY = $92                      ;; INKEY$
TK_MEM = $93                        ;; MEM

; Error codes: the code in B when a routine jumps to the error handler, twice the error's place in <ERRTAB>.
ERR_NF = 0                          ;; NF: NEXT without FOR
ERR_SN = 2                          ;; SN: syntax error
ERR_RG = 4                          ;; RG: RETURN without GOSUB
ERR_OD = 6                          ;; OD: out of DATA
ERR_FC = 8                          ;; FC: illegal function call
ERR_OV = 10                         ;; OV: overflow
ERR_OM = 12                         ;; OM: out of memory
ERR_UL = 14                         ;; UL: undefined line
ERR_BS = 16                         ;; BS: subscript out of range
ERR_DD = 18                         ;; DD: redimensioned array
ERR_DV0 = 20                        ;; /0: division by zero
ERR_ID = 22                         ;; ID: illegal in direct mode
ERR_TM = 24                         ;; TM: type mismatch
ERR_OS = 26                         ;; OS: out of string space
ERR_LS = 28                         ;; LS: string too long
ERR_ST = 30                         ;; ST: string formula too complex
ERR_CN = 32                         ;; CN: can't continue
ERR_FD = 34                         ;; FD: bad file data
ERR_AO = 36                         ;; AO: file already open
ERR_DN = 38                         ;; DN: device number error
ERR_IO = 40                         ;; IO: input or output error
ERR_FM = 42                         ;; FM: bad file mode
ERR_NO = 44                         ;; NO: file not open
ERR_IE = 46                         ;; IE: input past the end of a file
ERR_DS = 48                         ;; DS: direct statement in a file

;; A reserved word: its last letter with bit 7 set marks where it ends.
.macro KEYWORD word
    .repeat .strlen(word) - 1, index
    .byte .strat(word, index)
    .endrepeat
    .byte .strat(word, .strlen(word) - 1) | $80
.endmacro
