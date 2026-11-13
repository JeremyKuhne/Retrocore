; ZPG.EQUS: BASIC's zero page, the X-bytes of its pointers, its work area in page $1E, the start of SOS.INTERP with
; the buffers that come before the code, and the dispatch tables for statements, functions and operators.
;
; BASIC is a SOS interpreter: its zero page is page $1A, and the X-byte page that goes with it is page $16. An
; indirect access through a zero-page pointer, such as LDA (TXTTAB),Y, takes its bank from the pointer's X-byte, the
; byte SYSPAG ($1601) past the pointer's own address. Each pointer's X-byte has the pointer's name with a B after it:
; TXTTAB's is TXTTABB.
;
; A pointer into the program and its data is three bytes: the address's low and high bytes in zero page, and the
; X-byte, $80 plus the bank pair. Through bank pair $80+n, addresses $0000-$7FFF are bank n's $2000-$9FFF and
; addresses from $8000 are the next bank's. BASIC keeps the high byte from MINPG to MAXPG-1 ($02-$81): pages 0 and 1
; of a bank pair can't be reached this way, so a pointer that passes page $81 goes on at page $02 of the next bank
; pair (one more in the X-byte), the same memory. FIXADC and FIXSBC keep pointers in that form after arithmetic.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Sizes and the load address
; ---------------------------------------------------------------------------------------------------------------------

STKEND = $FE                                ;; where the stack pointer starts when BASIC resets its stack
EOFSIZ = 33                                 ;; the size of EOFPTRS: three bytes for each of files 1-10 and ON KBD
.if DEBUG
B3PRT1 = $3A00                              ;; where SOS.INTERP's code loads: lower, for the debugger build
.else
.if VERSION = 123
B3PRT1 = $5200                              ;; where SOS.INTERP's code loads
.else
B3PRT1 = $5000                              ;; where SOS.INTERP's code loads
.endif
.endif
; BASIC runs from its load address up to $B7FF.

; ---------------------------------------------------------------------------------------------------------------------
; Zero page
; ---------------------------------------------------------------------------------------------------------------------

    .dum 0
SELFLG = $EE                                ;; the value 1.3's program selector leaves in locations 0 and 1
NUMLEV = 19                                 ;; the stack levels BASIC keeps free
TEMPTYP = 1                                 ;; a string's type byte: a temporary
ARYTYP = $81                                ;; a string's type byte: an array element's
SIMTYP = $41                                ;; a string's type byte: a simple variable's
MINPG = 2                                   ;; the lowest high byte of a pointer through a bank pair
MAXPG = $82                                 ;; one past the highest high byte of a pointer through a bank pair
INFOSIZ = 3                                 ;; the bytes of information after each string in string space
STRSIZ = 3                                  ;; the size of a string descriptor: the length, then the address
NUMTMP = 4                                  ;; the count of string temporaries in TEMPST
    jmp INIT                                ; Nothing is assembled here: locations 0-2 are left free

; This storage changes as BASIC runs; none of it could be in ROM.

;; A character that ends the string being scanned, such as a quote or a comma.
;; See: <ENDCHR>
CHARAC:
    .res 1
INTEGR = CHARAC                             ;; a one-byte integer, from QINT

;; The other character that ends the string being scanned.
;; See: <CHARAC>
ENDCHR:
    .res 1
DSCRPT = ENDCHR                             ;; a data file item's descriptor, such as DDINT, in READ# and WRITE#

;; A counter for any routine that needs one.
COUNT:
    .res 1

;; Whether the variable being looked up is being dimensioned by DIM.
;;
;; It must come just before <VALTYP>.
DIMFLG:
    .res 1
KIMY = DIMFLG                               ;; a place to keep Y, or another count, for a while

;; The type of the value just evaluated: 0 for a real or an integer, $40 for a long integer, $FF for a string.
;;
;; An integer reads as 0 here, with <INTFLG> set. Bit 7 set means a string and bit 6 set a long integer, which the
;; code tests with BIT.
;; See: <INTFLG>
VALTYP:
    .res 1

;; Bit 7 set when the variable just found or the value just evaluated is an integer (a % variable).
INTFLG:
    .res 1

;; While a line is crunched into tokens, whether keywords are crunched: bit 7 set stops it until the next colon, and
;; bit 6 clear until the next comma.
;;
;; DATA and some file commands set it so their unquoted text stays as typed.
;; See: <CRUNCH>
DORES:
    .res 1
GARBFL = DORES                              ;; whether a garbage collection was tried while looking for string space
XSAV = DORES                                ;; a place to keep X for a while

;; Nonzero when the variable being looked up may not be subscripted, as for a function's name in DEF FN and FN.
SUBFLG:
    .res 1

;; A place to keep Y, or another byte, for a while.
YSAVE:
    .res 1

;; Which statement is taking values: INPUT, GET or READ; LIST uses it too.
INPFLG:
    .res 1

;; The sign of the tangent while TAN works.
TANSGN:
    .res 1
ANYNUM = TANSGN                             ;; while FIN reads a number, whether any digits were seen

;; The output file: FILNO is where output goes now, FILNO+1 where it goes between statements.
;;
;; $FF in either means the console; PRINT# and the like set FILNO for one statement.
FILNO:
    .res 2

;; The reference number of the EXEC file, 0 when EXEC is not running.
INFLNO:
    .res 1

;; The file number of the file operation in progress.
SVFLNO:
    .res 1

;; A JMP, through which BASIC calls a routine whose address it puts in JMPER+1 and JMPER+2.
;;
;; <P1INIT> stores the JMP opcode.
;; See: <JUMPDO>, <SWCHGO>
JMPER:
    jmp 60000

;; How far a block of memory moves, for the move routines, with its X-byte at <DELTAB>.
DELTA:
    .res 2

;; Used by the variable search, <PTRGET>: the value's size for the variable's type, then the size of the variable's
;; entry.
VARNAM:
    .res 2

;; The address of the value of the variable <PTRGET> just found or made, with its X-byte at <VARPNTB>.
VARPNT:
    .res 2

;; A pointer that nothing here names directly; its other names are used.
OPPTR:
    .res 2
VARTXT = OPPTR                              ;; a pointer into a list of variables, as INPUT and READ go through it
DOMASK = TANSGN                             ;; the relational operators found: bit 0 >, bit 1 =, bit 2 <

;; A pointer used by DEF FN and FN, with its X-byte at <DEFPNTB>.
DEFPNT:
    .res 2
GRBPNT = DEFPNT                             ;; how far strings move down in a garbage collection

;; The text window's left column.
;; See: <SWIDTH>, <SBOTTOM>, <STOPS>
SLEFT:
    .byte 0
FCBNDX = SLEFT                              ;; the offset of the current file's control block in FCB

;; The text window's width.
SWIDTH:
    .byte 0

;; The text window's bottom line.
SBOTTOM:
    .byte 0

;; The text window's top line.
STOPS:
    .byte 0

;; The column the console's output has reached.
TRMPOS:
    .res 1

;; A line number, as LINGET reads it or GOTO looks for it.
LINNUM:
    .word 0

;; The address in zero page of the next free string temporary in <TEMPST>.
TEMPPT:
    .res 1

;; The address of the string temporary used last.
LASTPT:
    .res 2

;; The string temporaries: <NUMTMP> descriptors of <STRSIZ> bytes, for strings that are parts of an expression.
TEMPST:
    .res STRSIZ*NUMTMP

;; A general pointer, with its X-byte at <INDEX1B>.
INDEX1:
    .res 2
INDEX = INDEX1                              ;; another name for INDEX1

;; A second general pointer, with its X-byte at <INDEX2B>.
INDEX2:
    .res 2

; ---------------------------------------------------------------------------------------------------------------------
; The program, the variables and the strings
;
; From low memory up: the program from TXTTAB, the arrays from ARYTAB, the simple variables from VARTAB to STREND,
; free memory, then the strings, which grow down from MEMSIZ; FRETOP is the lowest. INVOKE's modules take a segment
; of their own, from INVTAB to PROCTAB.
;
; A simple variable's entry is its length (one byte), its name, a type byte, then its value: 4 bytes for a real, 2
; for an integer, 8 for a long integer. A string variable's value is the string's length and a two-byte pointer.
; An array's entry has its name and type, the count of dimensions, two bytes for each dimension's size, then the
; values. Each string in string space is followed by INFOSIZ bytes: a type byte (TEMPTYP, SIMTYP or ARYTYP) and a
; pointer back to the variable's descriptor, which the garbage collector uses.
; ---------------------------------------------------------------------------------------------------------------------

;; The start of the program, with its X-byte at <TXTTABB>.
;;
;; The first line starts here. Each line is one byte of length, which is the offset to the next line, the two-byte
;; line number, the line's tokens, then a zero; a length of zero ends the program. The byte before TXTTAB is always
;; zero, which <STXTPT> sees to. <INIT> sets TXTTAB one byte into the memory segment SOS gives BASIC.
;; See: <ARYTAB>, <FNDLIN>
TXTTAB:
    .res 2

;; The start of the simple variables, just past the arrays, with its X-byte at <VARTABB>.
;;
;; <CLEARC> sets it to <ARYTAB>, so that there are no variables, and it moves up when an array is made.
;; See: <SMVARS>, <STREND>
VARTAB:
    .res 2
SMVARS = VARTAB                             ;; the start of the simple variables, which the variable search uses

;; The start of the arrays, just past the program, with its X-byte at <ARYTABB>.
;;
;; It moves with the end of the program, as lines are entered and deleted or a program is loaded.
ARYTAB:
    .res 2

;; The end of the simple variables, the first free byte above them, with its X-byte at <STRENDB>.
;;
;; A new simple variable is added here; <CLEARC> sets it to <ARYTAB>.
STREND:
    .res 2

;; The bottom of the strings in use, with its X-byte at <FRETOPB>: a new string is taken from just below it.
;;
;; <CLEARC> sets it to <MEMSIZ>, freeing every string.
;; See: <GETSPA>, <FRESPC>
FRETOP:
    .res 2

;; The start of the memory INVOKE loads modules into, with its X-byte at <INVTABB>.
;; See: <PROCTAB>, <INVPNT>
INVTAB:
    .res 2

;; The end of the invokable modules' memory, below which INVOKE builds the table of their procedures, with its X-byte
;; at <PROCTABB>.
;; See: <INVTAB>
PROCTAB:
    .res 2

;; The string <GETSPA> just made room for, with its X-byte at <FRESPCB>.
FRESPC:
    .res 2

;; The top of the strings' memory, with its X-byte at <MEMSIZB>.
MEMSIZ:
    .res 2

; ---------------------------------------------------------------------------------------------------------------------
; Line numbers and pointers into the program
; ---------------------------------------------------------------------------------------------------------------------

HIMEM = MEMSIZ                              ;; another name for MEMSIZ, the top of the strings' memory

;; The number of the line running; its high byte is $FF for a statement typed without a line number.
CURLIN:
    .res 2

;; The number of the line at which the program stopped, for CONT, or was interrupted.
OLDLIN:
    .res 2
POKER = LINNUM                              ;; another name for LINNUM

;; Where the program stopped, for CONT: the statement to run next, with its X-byte at <OLDTXTB>.
OLDTXT:
    .res 2

;; The number of the line of the DATA statement READ is in, for errors.
DATLIN:
    .res 2

;; Where READ takes its next value, with its X-byte at <DATPTRB>.
;;
;; RESTORE points it at the zero before the program's first line.
DATPTR:
    .res 2

;; Where INPUT or READ takes its next value, with its X-byte at <INPPTRB>.
INPPTR:
    .res 2
FDECPT = VARPNT                             ;; the place in the table of powers of ten FOUT has reached

;; The variable FOR or LET is assigning to, with its X-byte at <FORPNTB>.
FORPNT:
    .res 2
LSTPNT = FORPNT                             ;; the place in a keyword's name LIST has reached
TKNSAV = FORPNT+1                           ;; the token LIST is printing
TYPSAV = OLDLIN+1                           ;; the file's type, in the file commands

;; A pointer to a string descriptor, with its X-byte at <DSCPNTB>.
DSCPNT:
    .res 2
    .res 1                                  ; The fifth byte of TEMPF3

;; The size of a string descriptor, <STRSIZ>, kept here for the garbage collector; other routines use it as a
;; temporary.
FOUR6:
    .byte STRSIZ
SIZE = JMPER+1                              ;; a size, in JMPER's address bytes
OLDOV = JMPER+2                             ;; the overflow byte of the earlier multiplication step
TEMPF3 = DEFPNT                             ;; a third temporary for a packed real, five bytes

;; The fifth byte of the packed real temporary that starts at <HIGHDS>.
TEMPF1:
    .byte 0

;; Where a block move puts its highest byte, with its X-byte at <HIGHDSB>.
;; See: <BLTU>
HIGHDS:
    .res 2
PTR1 = HIGHDS                               ;; another name for HIGHDS, for the long-integer routines

;; Where READ# and WRITE# are in a data file's buffer, with its X-byte at <NDXPTRB>.
NDXPTR:
    .res 2

;; The highest byte a block move moves, with its X-byte at <HIGHTRB>.
HIGHTR:
    .res 2
PTR2 = HIGHTR                               ;; another name for HIGHTR, for the long-integer routines

;; The fifth byte of the packed real temporary that starts at <HIGHTR>.
TEMPF2:
    .byte 0
LENSAV = TEMPF2                             ;; the length of a data file item, in READ# and WRITE#

;; Where a block move's last byte went, with its X-byte at <LOWDSB>.
LOWDS:
    .res 2

;; The lowest byte a block move moves, with its X-byte at <LOWTRB>; the line <FNDLIN> found.
LOWTR:
    .res 2
PTR3 = LOWDS                                ;; another name for LOWDS, for the long-integer routines
SRCHPT = HIGHTR                             ;; the variable entry the variable search is looking at
ARYPNT = HIGHDS                             ;; a pointer used in building an array
GRBTOP = LOWTR                              ;; a pointer used by the garbage collector
DECCNT = LOWDS                              ;; while FOUT works, the count of digits before the decimal point
TENEXP = LOWDS+1                            ;; while FIN works, the power of ten so far
DPTFLG = LOWTR                              ;; while FIN works, whether a decimal point has been read
EXPSGN = LOWTR+1                            ;; while FIN works, the sign of the exponent

; ---------------------------------------------------------------------------------------------------------------------
; The floating-point accumulator, its argument, and the arithmetic
; ---------------------------------------------------------------------------------------------------------------------

;; The floating-point accumulator, FAC: the exponent, four bytes of mantissa, and the sign.
;;
;; Expressions are worked out here; the second operand is in <ARG>. An integer or long integer uses the same bytes.
;; See: <ARG>
FAC:

;; The FAC's exponent, 0 for the value zero.
FACEXP:
    .byte 0

;; The FAC's mantissa, its highest byte.
FACHO:
    .byte 0

;; The FAC's mantissa, its second byte.
FACMOH:
    .byte 0
FACT = FACMOH                               ;; another name for FACMOH, where a decimal value's digits start

;; The FAC's mantissa, its third byte, with its X-byte at <FACMOB> for when it holds a pointer.
FACMO:
    .byte 0

;; The FAC's mantissa, its lowest byte.
FACLO:
    .byte 0

;; The FAC's sign while it is unpacked: 0 for positive, $FF for negative.
FACSGN:
    .byte 0

;; The sign of the number FIN is reading.
SGNFLG:
    .byte 0
DEGREE = SGNFLG                             ;; the count of terms while a polynomial is worked out
DSCTMP = FAC                                ;; where a string temporary's descriptor is built
INDICE = FACMO                              ;; the integer QINT leaves
    .res 3                                  ; The rest of the FAC, for its longer forms

;; How many more digits FIN takes before it rounds, at ten.
CNTDIGS:
    .byte 0
    .byte 0                                 ; Unused

;; The argument's exponent.
;; See: <ARG>
ARGEXP:
    .byte 0

;; The argument's mantissa, its highest byte.
ARGHO:
    .byte 0

;; The argument's mantissa, its second byte.
ARGMOH:
    .byte 0
ARG = ARGEXP                                ;; the argument: a second floating-point value, laid out like FAC

;; The argument's mantissa, its third byte, with its X-byte at <ARGMOB>.
ARGMO:
    .byte 0

;; The argument's mantissa, its lowest byte.
ARGLO:
    .byte 0

;; The argument's sign: 0 for positive, $FF for negative.
ARGSGN:
    .byte 0

;; The sign of the result: the FAC's and the argument's signs combined.
ARISGN:
    .byte 0
    .byte 0
    .byte 0

;; The result of a multiplication or division, its highest byte.
RESHO:
    .res 1

;; The result's second byte.
RESMOH:
    .res 1

;; The result's third byte.
RESMO:
    .res 1

;; The result's lowest byte.
RESLO:
    .res 1
ADDEND = RESMO                              ;; a temporary of UMULT's

;; The byte below the result; also a temporary for any routine.
TEMP:
    .byte 0
RES = RESHO                                 ;; the result of a multiplication or division

;; The FAC's rounding byte, below its lowest.
FACOV:
    .byte 0
    .res 3
STRNG1 = ARISGN                             ;; a pointer to a string or its descriptor

;; Where FOUT has reached in <FBUFFR>.
FBUFPT:
    .res 2
BUFPTR = FBUFPT                             ;; where CRUNCH has reached in BUF
STRNG2 = FBUFPT                             ;; a second pointer to a string or its descriptor
POLYPT = FBUFPT                             ;; the coefficients of the polynomial being worked out
CURTOL = FBUFPT                             ;; the array's size so far, in DIM and the variable search

; ---------------------------------------------------------------------------------------------------------------------
; Running the program
; ---------------------------------------------------------------------------------------------------------------------

;; Bit 7 set while TRACE is on.
TRFLAG:
    .res 1

;; The type flags of a FOR loop's variable, as <FNDFOR> looks for its loop on the stack.
TEMPFOR:
    .res 1

;; Where ONERR GOTO goes: the statement after it, with its X-byte at <ERRTOB>, then (at ERRTO+3) its line number.
;; See: <ONERR>, <HNDLERR>
ERRTO:
    .res 5

;; The number of the line the last error happened in, which ERRLIN gives.
ERRLIN:
    .res 2

;; The statement the last error happened in, for RESUME, with its X-byte at <ERRPOSB>; zero there means no error yet.
;; See: <RESUME>
ERRPOS:
    .res 3

;; The number of the last error, which ERR gives: its place in <ERRTAB>, or 255 for a CONTROL-C.
ERRNUM:
    .res 1

;; Bit 7 set while ONERR GOTO is on.
ERRFLG:
    .res 1

;; The stack pointer BASIC goes back to after an error.
REMSTK:
    .res 1

;; Whether a program has run since BASIC started.
RNFLG:
    .res 1

;; The top of <NOUNSTK>, the expression evaluator's operand stack.
NOUNPT:
    .res 1

;; The top of <VRBSTK>, the expression evaluator's operator stack.
VRBPT:
    .res 1

;; A pointer to the information bytes after a string, with its X-byte at <HEADERB>.
HEADER:
    .res 2

;; A place for LIST to keep a pointer.
PNTSAV:
    .word 0

;; The depth of nested IF ... THEN ... ELSE.
LVLCNT:
    .res 1
QUOTE = LVLCNT                              ;; whether the text being scanned is inside quotes

;; The variable name the variable search is reading, with its X-byte at <TMPPTRB>.
TMPPTR:
    .word 0

;; A string flag: <FRMEVL> clears it, and nothing reads it.
STRFLG:
    .byte 0

;; Where INVOKE loads the next module, with its X-byte at <INVPNTB>.
INVPNT:
    .res 2

;; INVOKE's and PERFORM's count of pointer parameters; it must survive the expression evaluator.
NPOINTS:
    .byte 0

;; PERFORM's count of parameter bytes; it must survive the expression evaluator.
NPARAMS:
    .byte 0

;; What kind of routine INVOKE or PERFORM is looking for; it must survive the expression evaluator.
PROCFLG:
    .byte 0
IOFLG = NPOINTS                             ;; whether a file statement reads or writes

;; Bit 7 set when a key was pressed, bit 6 when CONTROL-C was; the handlers set them and the statement loop checks
;; them before each statement.
;; See: <KBDEVNT>, <CTCEVNT>
KEYSTROK:
    .byte 0

;; Work space for 16-bit multiplication and division: the multiplier, or the quotient.
;;
;; MLTPLR, RMNDR and MLTPLR2 must stay together and in this order.
MLTPLR:
    .word 0
RSLT = MLTPLR                               ;; the product

;; The remainder of the division.
RMNDR:
    .word 0

;; The multiplicand, or the divisor.
MLTPLR2:
    .word 0
QUOTNT = MLTPLR                             ;; the quotient
DVDND = MLTPLR                              ;; the dividend
DVSR = MLTPLR2                              ;; the divisor

;; A count for the shift routines.
BITS:
    .byte 0
    .res 5

;; Takes the next character of the program or the line, skipping spaces.
;;
;; <INIT> copies the routine here from <CHSGET>; what is assembled here only sets out the addresses. The character is
;; read with an absolute LDA whose address, <TXTPTR>, is the instruction's own operand in zero page. The Apple III
;; extends an access whose address is read from zero page, so this LDA reads through <TXTPTRB>'s bank like an
;; indirect one would.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon), carry = clear for a digit
;; Entry: CHRGOT = takes the character at TXTPTR again, without moving on
CHRGET:
    inc CHRGET+7
    bne CHRGOT
    inc CHRGET+8
CHRGOT:
    lda 60000
TXTPTR = CHRGOT+1                           ;; where the program or line is being read, with its X-byte at TXTPTRB
    .res 15                                 ; The rest of the routine

;; The random number generator's state, which RND works from; <INIT> seeds it from the system's counters.
RNDX:
    .res 8

;; Where the name of the routine EXFN calls starts in <NAMBUF>, for an EXFN inside another.
NAMPNT:
    .byte 0

;; Set while RUN or CHAIN is running a program from a file.
CMDFLG:
    .byte 0
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; The invokable modules' zero page
;
; These locations are where Pascal's run time keeps the same things, so that a module assembled by the Pascal
; assembler can call back into BASIC.
; ---------------------------------------------------------------------------------------------------------------------

    .dum $E4

;; A JMP to <SWCHGO>, through which a module calls a routine of BASIC's by its number in <PASSAREG>.
DISPATCH:
    .res 3

;; The number of the routine of BASIC's a module calls through <DISPATCH>: its place in <JMPRTAB>.
PASSAREG:
    .byte 0

;; Pointers to the variables a module was passed by reference, each with its X-byte at <BANKPNTB>.
BANKPNT:
    .res 16
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; Page $1E
;
; The page below BASIC's stack, which BASIC takes for its own work space. The stack is page $01 of its zero page,
; from STKEND down.
; ---------------------------------------------------------------------------------------------------------------------

    .dum 255
CRUDBUF = $1E00                             ;; BASIC's work page
    .dend
    .dum CRUDBUF
    jmp SWCHGO                              ; Three bytes set out as a JMP to SWCHGO, which nothing here writes
    .byte 0

;; The return address PERFORM's caller left, kept here while the module runs, then the bank that was switched in.
;; See: <JUMPDO>
SAFE:
    .byte 0, 0, 0

;; The start of the memory segment SOS gave BASIC, with its X-byte in <RAMLOCB>.
;; See: <TRYSEG>
RAMLOC:
    .word 0

;; The X-byte of <RAMLOC>.
RAMLOCB:
    .byte 0

;; The expression evaluator's operator stack: each operator's number and its precedence (with the operand's type).
;; See: <VRBPT>
VRBSTK:
    .res 32

;; Where each file's ON EOF# goes, three bytes for each file from 1, the last for ON KBD: the X-byte, then the
;; address, made relative to <TXTTAB>.
;;
;; An entry whose first byte is zero has no handler.
;; See: <ONEOF>, <CHKEOF>, <EOFLINS>
EOFPTRS:
    .res EOFSIZ

;; The line number of each <EOFPTRS> entry's handler, at the same offset.
EOFLINS:
    .res EOFSIZ-1

;; The control blocks of files 1-10, <FCBLEN> bytes each.
;; See: <XRFNM>
FCB:
    .res FCBLEN*10

;; The control block CATALOG reads the directory through, as file 11.
CATFCB:
    .res FCBLEN

;; The X-byte of the invokable modules' bank pair.
INVBNK:
    .byte 0

;; BASIC's own bank, from the bank register when BASIC started.
BASICBNK:
    .byte 0

;; Bit 7 set when the variable just found is an array element.
ISARA:
    .byte 0

;; The expression evaluator's operand stack.
;; See: <NOUNPT>
NOUNSTK:
    .res 128

;; The SOS error code for a SOS CALL error.
;; See: <SERROR>
SOSLOC:
    .byte 0

;; The right margin LIST wraps at, which OUTREC sets and gives; 0 turns wrapping off.
OUTREC:
    .byte 0

;; How many spaces LIST indents each FOR loop's lines, which INDENT sets and gives.
INDENT:
    .byte 0

;; The number of the file that last reached its end, which EOF gives.
EOFSV:
    .res 1
    .dend

; ---------------------------------------------------------------------------------------------------------------------
; SOS.INTERP's header and buffers
; ---------------------------------------------------------------------------------------------------------------------

    .org B3PRT1-$0E
    .byte "SOS NTRP"                        ; The label SOS looks for in an interpreter
    .word 0000                              ; No more header
    .word B3PRT1                            ; The load address
    .word BASICEND-GOBASIC                  ; The length

;; The first byte SOS loads: a jump to <INIT>, where SOS starts the interpreter.
GOBASIC:
    jmp INIT
.if VERSION >= 130

;; Zero when BASIC was started from the disk, so it runs HELLO, or not zero when 1.3's program selector started it.
SELECTOR:
    .byte 0

;; The pathname of the program the selector chose, with its length first; then just its prefix.
;; See: <SETPROG>
PROGPATH:
    .byte 0
    .res 80, 0

;; SOS's own prefix, with its length first, which BASIC goes back to for its own files.
;; See: <SETSOS>
SOSPATH:
    .byte 0
    .res 80, 0
.endif

;; A pathname or a routine's name, as a file command or PERFORM reads it, with its length first.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
NAMBUF:
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
    .res 128
.endif
    .byte 80                                ; CATBUF's length, for GET_PREFIX

;; CATALOG's line buffer, and the buffer GET_PREFIX fills.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
CATBUF:
.if VERSION = 123
    .byte $B0, $A0, $AD, $80, $AD, $A0, $80, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $EE
    .byte $A0, $A0, $F2, $A0, $AD, $A0, $A0, $AD, $A0, $B7, $A0, $A0, $A0, $F9, $AD, $A0
    .byte $CE, $AD, $A0, $A0, $E8, $A0, $F4, $A0, $AD, $AD, $A0, $AD, $A0, $A0, $A0, $A0
    .byte $B0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $F4
    .byte $AD, $B0, $E9, $AD, $AD, $A0, $A0, $AD, $A0, $AA, $EE, $A0, $A0, $E5, $A0, $F2
.else
    .res 80
.endif

;; The length of the long integer <LOUT> wrote as text in <NUMSTR>.
LENUM:
    .byte 0

;; The digits of a number for PRINT USING, one to a byte; FOUT's output buffer, <FBUFFR>, is in its upper part.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
BCDSTR:
.if VERSION = 123
    .byte $81, $AD, $A0, $F4, $A0, $A0, $A0, $EE, $A0, $A0, $FC, $A0, $F4, $A0, $F0, $FC
    .byte $A0, $80, $AD, $A0, $A0, $AD, $A0, $A0, $A0, $AD, $A0, $A0, $B0, $AA, $A0, $A0
    .byte $A0, $A0, $A0, $A0, $C5, $AD, $A0, $E1, $AD, $AD, $A0, $A0, $AD, $A0, $B5, $F2
.else
    .res 48
.endif
NUMSTR = BCDSTR                             ;; a long integer as text, as LOUT writes it
FBUFFR = BCDSTR+28                          ;; FOUT's output: a number as text, ending in a zero
LOFBUF = FBUFFR-1                           ;; the byte before FBUFFR
.if VERSION = 123
    .byte $AD, $AD, $AA                     ; The new line's length and number go here
.else
    .res 3                                  ; The new line's length and number go here
.endif
PREBUF = LOFBUF                             ;; an end of a buffer for PREFIX$, which nothing uses

;; The input line: the line typed, or read from a file, which CRUNCH then turns into tokens in place.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; See: <SLINTB>
BUF:
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
    .res 256
.endif

;; The last key read, which KBD gives.
;; See: <DOAGET>
KEYSAVE:
    .byte 13

; ---------------------------------------------------------------------------------------------------------------------
; Dispatch tables
; ---------------------------------------------------------------------------------------------------------------------

;; Each statement's routine, less one, by its token from END ($80) to NEW ($E0): the statement loop pushes the address
;; and returns to it.
;;
;; A keyword that isn't a statement, such as FRE or a token with no keyword, gives a syntax error (<SNERR>). Some
;; keywords share a routine: POP's is RETURN's, CAT's is CATALOG's, and IMAGE and ELSE are skipped like REM.
;; See: <RESLST>, <RESTBL>
STMDSP:
    .word END-1
    .word FOR-1
    .word NEXT-1
    .word INPUT-1
    .word OUTPUT-1
    .word DIM-1
    .word READ-1
    .word DWRITE-1
    .word DOPEN-1
    .word DCLOSE-1
    .word SNERR-1
    .word MSETTXT-1
    .word SNERR-1
    .word COLD-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word WINDOW-1
    .word INVOKE-1
    .word PERFORM-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word HTAB-1                            ; HPOS as a statement
    .word VTAB-1                            ; VPOS as a statement
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word PREFIXSET-1                       ; PREFIX$ as a statement
    .word SNERR-1
    .word SNERR-1
    .word SOUTREC-1
    .word SINDENT-1
.if VERSION >= 130
    .word PROGPFX-1
.else
    .word SNERR-1
.endif
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word RETURN-1                          ; POP
    .word HOME-1
.if DEBUG
    .word $A1FF                             ; The debugger's command, in the debugger build
.else
    .word SNERR-1
.endif
    .word SUBLEFT-1
    .word OFF-1
    .word SETTRACE-1
    .word TRACEOFF-1
    .word SETNORM-1
    .word INVERSE-1
    .word SNERR-1
    .word RESUME-1
    .word SNERR-1
    .word LET-1
    .word GOTO-1
    .word IF-1
    .word RESTOR-1
    .word SWAP-1
    .word GOSUB-1
    .word RETURN-1
    .word REM-1
    .word STOP-1
    .word ONGOTO-1
    .word SNERR-1
    .word LOAD-1
    .word SAVE-1
    .word DDELETE-1                         ; DELETE, of a file
    .word RUN-1
    .word RENAME-1
    .word LOCK-1
    .word UNLOCK-1
    .word CREATE-1
    .word EXEC-1
    .word CHAIN-1
    .word SNERR-1
    .word SNERR-1
    .word SNERR-1
    .word CATALOG-1
    .word SNERR-1
    .word SNERR-1
    .word DATAIS-1
    .word REM-1                             ; IMAGE
    .word CATALOG-1                         ; CAT
    .word DEF-1
    .word SNERR-1
    .word DOPRINT-1
    .word DELETE-1                          ; DEL, of program lines
    .word REM-1                             ; ELSE
    .word CONT-1
    .word LIST-1
    .word CLEAR-1
    .word GET-1
    .word SCRATH-1                          ; NEW

;; The routines of the keywords that give a value without parentheses, by token from FRE (<FRETK>) to PROGPREFIX$,
;; which <PARC23> jumps to.
;;
;; FRE's routine (<NOFREF>) comes first; then HPOS, VPOS, ERRLIN, ERR, KBD, EOF, TIME$, DATE$, PREFIX$, EXFN.,
;; EXFN%., OUTREC and INDENT, and in 1.3 PROGPREFIX$.
RESTBL:
    .word NOFREF
    .word POS                               ; HPOS
    .word DOVPOS
    .word DOERRLN
    .word GIVERR
    .word GIVKBD
    .word GIVEOF
    .word TIMES
    .word DATES
    .word PREFIXS
    .word EXFN
    .word EXFNS
    .word GIVOUTREC
    .word GIVINDENT
.if VERSION >= 130
    .word PROGPFXS
.endif

;; The functions' routines, by their tokens in <RESL2> from SGN( (<ONEFUN>) to INSTR( (<INSTRTK>).
;;
;; A token with no function, and USR, which Business BASIC doesn't have, give a syntax error.
FUNDSP:
    .word SGN
    .word INT
    .word ABS
    .word SNERR                             ; No USR
    .word TYP
    .word REC
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word PDLHNDL
    .word BUTTON
    .word SQR
    .word RND
    .word LOG
    .word EXP
    .word COS
    .word SIN
    .word TAN
    .word ATN
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word SNERR
    .word STRS
    .word HEXS
    .word CHRS
    .word LEN
    .word VAL
    .word ASC
    .word DECER                             ; TEN
    .word SNERR
    .word SNERR
    .word CONV2FLT                          ; CONV
    .word CONV2LNG                          ; CONV&
    .word CONV2STR                          ; CONV$
    .word CONV2INT                          ; CONV%
    .word LEFTS
    .word RIGHTS
    .word MIDS
    .word INSTR

;; Each operator's precedence, higher binding tighter, by the operator's number less one.
;;
;; The numbers are those <FRMEVL> gives: the relational operators first (the combinations of less, equal and
;; greater), then <OPTAB>'s operators from ^ on, and the end of the expression last.
;; See: <OPTAB>
PRECTB:
    .byte 4, 4, 4, 4                        ; The relational operators
    .byte 4, 4, 4
    .byte 8, 3, 2, 6                        ; ^ AND OR MOD
    .byte 6, 6, 6, 5                        ; DIV / * -
    .byte 5, 1                              ; + and the end of the expression

;; The routines for the operators on reals and integers, two bytes each in operator order: the relational operators'
;; routine first, then ^, AND, OR, MOD, DIV, /, *, - and +; the routines for long integers follow at <NUMDSP>.
;;
;; MOD and DIV give a type mismatch on reals. String operands may take only the relational operators and +.
;; See: <FRMEVL>
OPDSPT:
    .word DOREL
RELNUM = 1                                  ;; the relational operators' entry, the first
    .word FPWRT
    .word ANDOP
    .word OROP
    .word TMERR
    .word TMERR
    .word FDIVT
    .word FMULTT
    .word FSUBT
    .word FADDT
NUMDSP = *-OPDSPT                           ;; the offset of the long-integer routines, and of + for a string
    .word LDOCOMP
    .word TMERR                             ; ^ on long integers
    .word LAND
    .word LONGOR
    .word LREM
    .word LDIV
    .word LDIVT
    .word LMULT
    .word LSUB
    .word LADD

; ---------------------------------------------------------------------------------------------------------------------
; X-bytes
;
; Each name is the X-byte of the pointer whose name it ends: the extension byte that picks the bank for an indirect
; access through that pointer.
; ---------------------------------------------------------------------------------------------------------------------

SYSPAG = $1601                              ;; from a pointer's address to its X-byte: $1600, plus 1 for the high byte
VARNAMB = VARNAM+SYSPAG                     ;; VARNAM's X-byte
VARPNTB = VARPNT+SYSPAG                     ;; VARPNT's X-byte: the bank of the variable just found
DEFPNTB = DEFPNT+SYSPAG                     ;; DEFPNT's X-byte
INDEXB = INDEX+SYSPAG                       ;; INDEX's X-byte
INDEX1B = INDEX1+SYSPAG                     ;; INDEX1's X-byte
INDEX2B = INDEX2+SYSPAG                     ;; INDEX2's X-byte
TXTTABB = TXTTAB+SYSPAG                     ;; TXTTAB's X-byte: the bank of the program's start
VARTABB = VARTAB+SYSPAG                     ;; VARTAB's X-byte: the bank of the simple variables' start
ARYTABB = ARYTAB+SYSPAG                     ;; ARYTAB's X-byte: the bank of the arrays' start
STRENDB = STREND+SYSPAG                     ;; STREND's X-byte: the bank of the variables' end
FRETOPB = FRETOP+SYSPAG                     ;; FRETOP's X-byte: the bank of the strings' bottom
FRESPCB = FRESPC+SYSPAG                     ;; FRESPC's X-byte
MEMSIZB = MEMSIZ+SYSPAG                     ;; MEMSIZ's X-byte: the bank of the strings' top
HIMEMB = HIMEM+SYSPAG                       ;; HIMEM's X-byte, the same byte as MEMSIZB
OLDTXTB = OLDTXT+SYSPAG                     ;; OLDTXT's X-byte
DATPTRB = DATPTR+SYSPAG                     ;; DATPTR's X-byte
INPPTRB = INPPTR+SYSPAG                     ;; INPPTR's X-byte
DSCPNTB = DSCPNT+SYSPAG                     ;; DSCPNT's X-byte
HIGHDSB = HIGHDS+SYSPAG                     ;; HIGHDS's X-byte
NDXPTRB = NDXPTR+SYSPAG                     ;; NDXPTR's X-byte
HIGHTRB = HIGHTR+SYSPAG                     ;; HIGHTR's X-byte
LOWDSB = LOWDS+SYSPAG                       ;; LOWDS's X-byte
LOWTRB = LOWTR+SYSPAG                       ;; LOWTR's X-byte
PTR1B = PTR1+SYSPAG                         ;; PTR1's X-byte
PTR2B = PTR2+SYSPAG                         ;; PTR2's X-byte
PTR3B = PTR3+SYSPAG                         ;; PTR3's X-byte
FACB = FAC+SYSPAG                           ;; the X-byte of FAC and FAC+1 as a pointer
FACMOB = FACMO+SYSPAG                       ;; the X-byte of FACMO and FACLO as a pointer
ARGMOB = ARGMO+SYSPAG                       ;; the X-byte of ARGMO and ARGLO as a pointer
HEADERB = HEADER+SYSPAG                     ;; HEADER's X-byte
DSCTMPB = DSCTMP+SYSPAG+1                   ;; the X-byte of the string address in DSCTMP, which follows its length
VARTXTB = VARTXT+SYSPAG                     ;; VARTXT's X-byte
TXTPTRB = TXTPTR+SYSPAG                     ;; TXTPTR's X-byte: the bank of the text CHRGET reads
TMPPTRB = TMPPTR+SYSPAG                     ;; TMPPTR's X-byte
SRCHPTB = SRCHPT+SYSPAG                     ;; SRCHPT's X-byte
SMVARSB = SMVARS+SYSPAG                     ;; SMVARS's X-byte, the same byte as VARTABB
ARYPNTB = ARYPNT+SYSPAG                     ;; ARYPNT's X-byte
STRNG1B = STRNG1+SYSPAG                     ;; STRNG1's X-byte
STRNG2B = STRNG2+SYSPAG                     ;; STRNG2's X-byte
FORPNTB = FORPNT+SYSPAG                     ;; FORPNT's X-byte
DECCNTB = DECCNT+SYSPAG                     ;; DECCNT's X-byte
GRBTOPB = GRBTOP+SYSPAG                     ;; GRBTOP's X-byte
DELTAB = DELTA+SYSPAG                       ;; the bank part of DELTA, how many bank pairs a block moves
BANKPNTB = BANKPNT+SYSPAG                   ;; the X-byte of BANKPNT's first pointer
PROCTABB = PROCTAB+SYSPAG                   ;; PROCTAB's X-byte
INVTABB = INVTAB+SYSPAG                     ;; INVTAB's X-byte
POLYPTB = POLYPT+SYSPAG                     ;; POLYPT's X-byte
INVPNTB = INVPNT+SYSPAG                     ;; INVPNT's X-byte
ERRTOB = ERRTO+SYSPAG                       ;; the X-byte of ONERR GOTO's statement address in ERRTO
ERRPOSB = ERRPOS+SYSPAG                     ;; the X-byte of the last error's statement address in ERRPOS
