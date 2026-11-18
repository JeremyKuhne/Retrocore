;; MBASIC 5.21: STORAGE: BASIC'S VARIABLES AND MESSAGES
;;
;; The interpreter's own variables, at $0774-$0C3F, with the values MBASIC.COM starts them at, and the four
;; messages after them, to $0C4F. GW-BASIC declares them in GWDATA.ASM, nearly in this order; LINLEN, the
;; terminal's width, is in GWRAM.ASM there. Unlike a ROM BASIC, MBASIC needs no copy of initial values: they are
;; part of the program, and INIT sets the rest from the command line and CP/M.
;;
;; In order:
;;
;; - The output and console state: USRTAB, NULCNT, the printer's position and widths (LPTPOS, LPTSIZ) and the
;;   terminal's (LINLEN, CLMLST), and Control-O's CNTOFL.
;; - The pointers to the program's memory (TOPMEM, TXTTAB) and the current line (CURLIN).
;; - The disk files: PTRFIL, the file being read or written, MAXFIL and FILPTR, the files' data blocks, and the
;;   CP/M file control block FILNAM.
;; - The line buffers: KBUF, which CRUNCH fills, and BUF, the line typed.
;; - The interpreter's state, from TTYPOS and VALTYP to DEFTBL, much as in every Microsoft BASIC: string space
;;   (MEMSIZ, FRETOP, TEMPST), the program's memory (VARTAB, ARYTAB, STREND), errors (ERRLIN, ONELIN) and CONT
;;   (OLDLIN, OLDTXT).
;; - The user-defined functions' parameters (PRMSTK to FUNACT), FOR and NEXT, OPTION BASE, CHAIN and MERGE.
;; - The math package's accumulators: FAC, with DFACLO and FACLO below it, and ARG, then FOUT's buffer FBUFFR.

; The output and console.

;; The address each USR function calls, USR0 to USR9; DEF USR sets them, and each starts at the illegal function
;; call error.
USRTAB:
    .word FCERR, FCERR, FCERR, FCERR, FCERR
    .word FCERR, FCERR, FCERR, FCERR, FCERR
NULCNT:         .byte 1                 ;; the number of nulls printed after a carriage return; NULL sets it
CHARC:          .byte 0                 ;; the key the Control-C check read and kept, to be read next; zero when none
ERRFLG:         .byte 0                 ;; the last error's code, which EDIT uses after a syntax error
    .byte 0                         ; nothing refers to this byte (GW-BASIC's LPTLST)
LPTPOS:         .byte 0                 ;; the printer's carriage position, for LPOS and LPRINT's commas
PRTFLG:         .byte 0                 ;; nonzero while output goes to the printer (LPRINT, LLIST)
NLPPOS:         .byte 112               ;; the last printer column where a comma starts a new print zone
LPTSIZ:         .byte 132               ;; the printer's width; WIDTH LPRINT sets it, and 255 is no limit
LINLEN:         .byte 80                ;; the terminal's width, where PRINT starts a new line; WIDTH sets it
CLMLST:         .byte 56                ;; the last terminal column where a comma starts a new print zone
RUBSW:          .byte 0                 ;; nonzero while the line editor is echoing deleted characters, after a backslash
CNTOFL:         .byte 0                 ;; nonzero while Control-O suppresses output; INPUT, READY and errors clear it
PTRFIL:         .word 0                 ;; the data block of the file being read or written, or zero for the console

; The program's memory.

TOPMEM:         .word $60A3             ;; the top of the stack, below string space; INIT and CLEAR set it
CURLIN:         .word $FFFE             ;; the line being run: $FFFF in direct mode, $FFFE while INIT runs a program
TXTTAB:         .word $6040             ;; the program's first line; INIT sets it above the files' buffers
OVERRI:         .word OVRMSG            ;; the message the overflow routine prints: OVRMSG, or DIVMSG for a division by zero

; The disk files.

RUNFLG:         .byte 0                 ;; nonzero when LOAD or RUN is to run the program once loaded (RUN, LOAD ,R)
MAXSAV:         .byte 0                 ;; MAXFIL, saved while LOAD sets it to zero to keep the files open
RNDWRT:         .byte 0                 ;; nonzero when the random file's sector routine writes the sector, zero to read it
    .byte 0                         ; nothing refers to this byte
FILPT0:         .word 0                 ;; file 0's data block, which LOAD, SAVE, MERGE and the rest use

;; Each file's data block, 0 to 15, of which INIT allocates MAXFIL after file 0's; file 0 is the program's.
FILPTR:
    .res 32
MAXFIL:         .byte 0                 ;; the highest file number, which /F: sets (3 when not given)
NAMCNT:         .byte 0                 ;; the number of characters in the variable name being looked up past its first two

;; The characters of the variable name being looked up past its first two, which PTRGET compares.
NAMBUF:
    .res 38
NAMTMP:         .word 0                 ;; PTRGET's work word while it saves a long name

;; The CP/M file control block's first 16 bytes that NAME uses for the new name: the BDOS rename reads the old
;; name here and the new one in FILNAM, 16 bytes on.
FILNA2:
    .res 16
FILNAM:         .byte 0                 ;; the CP/M file control block of the file being opened: its drive, 0 for the current one
FILNM:          .res 8                  ;; the file name, padded with spaces
FILEXT:         .res 3                  ;; the file name's extension, padded with spaces
FILNAM_EXTENT:  .byte 0                 ;; the file control block's extent, cleared before an open or a directory search
    .res 20                         ; the rest of the file control block
CPMVRN:         .byte 0                 ;; CP/M's version, from BDOS function 12: zero before CP/M 2
CPMREA:         .byte 0                 ;; the BDOS function that reads a random record: 33, or a sequential read before CP/M 2
CPMWRI:         .byte 0                 ;; the BDOS function that writes a random record: 34, or a sequential write before CP/M 2

; The line buffers.

KBUFCOLON:      .byte ':'               ;; a colon before KBUF, where the crunched line's text pointer starts

;; The crunch buffer: CRUNCH turns BUF's line into tokens here.
KBUF:
    .res 318
BUFMIN:         .byte ','               ;; a comma before BUF, for INPUT, whose data pointer always starts on a comma

;; The line typed, from INLIN, which a direct statement runs from and INPUT reads; it must be below DSCTMP.
BUF:
    .res 258
ENDBUF:         .byte 0                 ;; the byte after BUF, where INLIN stops a long line

; The interpreter's state.

TTYPOS:         .byte 0                 ;; the terminal's cursor column, for POS, TAB and commas
DIMFLG:         .byte 0                 ;; nonzero while PTRGET looks up an array for DIM
VALTYP:         .byte 0                 ;; the type of the value in FAC: 2 integer, 3 string, 4 single, 8 double
DORES:          .byte 0                 ;; nonzero while CRUNCH copies a DATA statement's words unchanged
DONUM:          .byte 0                 ;; CRUNCH's numbers: 0 converted, 1 as line numbers, -1 none (in a variable name)
CONTXT:         .word 0                 ;; the text pointer after a constant, which CHRGTR returns to after it
CONSAV:         .byte 0                 ;; the token of the constant CHRGTR has just scanned
CONTYP:         .byte 0                 ;; the constant's type, as in VALTYP
CONLO:          .word 0                 ;; the constant's value: an integer, a single's low mantissa, or a double's low bytes
CONHI:          .word 0                 ;; a single constant's high mantissa byte and exponent, or a double's middle bytes
    .res 4                          ; the rest of a double constant, to its exponent
MEMSIZ:         .word 0                 ;; the top of string space, the highest byte BASIC uses
TEMPPT:         .word 0                 ;; the next free descriptor in TEMPST

;; The temporary string descriptors, ten of three bytes: a string's length and address.
TEMPST:
    .res 30
DSCTMP:         .byte 0                 ;; the descriptor of the string a string function builds: its length
DSCPTR:         .word 0                 ;; the address in DSCTMP: where the string being built is
FRETOP:         .word 0                 ;; the bottom of the strings in string space, its free space below
TEMP3:          .word 0                 ;; a work word: FRMEVL, FOUT, user functions, arrays, garbage collection
TEMP8:          .word 0                 ;; a work word for garbage collection, and INIT's pointer to the file to run
ENDFOR:         .word 0                 ;; the text pointer after a FOR statement
DATLIN:         .word 0                 ;; the line of the DATA statement being read, for an error in it
SUBFLG:         .byte 0                 ;; nonzero when PTRGET is not to take a subscript: FOR and user functions
FLGINP:         .byte 0                 ;; nonzero for READ, zero for INPUT
TEMP:           .word 0                 ;; a work word: NEWSTT's text pointer for INPUT and Control-C, LET's variable for FOR
PTRFLG:         .byte 0                 ;; nonzero when line numbers in the program have been turned into pointers
AUTFLG:         .byte 0                 ;; nonzero while AUTO numbers lines
AUTLIN:         .word 0                 ;; the line number AUTO offers next
AUTINC:         .word 0                 ;; AUTO's increment
SAVTXT:         .word 0                 ;; the text pointer NEWSTT saves at each statement, for RESUME
SAVSTK:         .word 0                 ;; the stack pointer NEWSTT saves at each statement, which an error restores
ERRLIN:         .word 0                 ;; ERL: the line of the last error
DOT:            .word 0                 ;; the current line for EDIT and LIST, ".": the last listed, typed or in error
ERRTXT:         .word 0                 ;; the text pointer of the last error, for RESUME
ONELIN:         .word 0                 ;; the ON ERROR GOTO line's text, or zero when errors are not trapped
ONEFLG:         .byte 0                 ;; nonzero while an error trap routine runs
TEMP2:          .word 0                 ;; a work word FRMEVL keeps across operators: FOUT, user functions, arrays
OLDLIN:         .word 0                 ;; the line STOP, END or Control-C stopped in, for CONT
OLDTXT:         .word 0                 ;; the text pointer of the statement to run next, for CONT
VARTAB:         .word 0                 ;; the simple variables, after the program
ARYTAB:         .word 0                 ;; the arrays, after the simple variables
STREND:         .word 0                 ;; the end of the arrays: the first free byte
DATPTR:         .word 0                 ;; the next DATA item; RESTORE sets it before the program

;; Each letter's default type, A to Z, as in VALTYP: CLEAR sets them to single, and DEFSTR, DEFINT, DEFSNG and DEFDBL
;; change them.
DEFTBL:
    .res 26

; The user-defined functions' parameters.

PRMSTK:         .word 0                 ;; the previous parameter block on the stack, for garbage collection
PRMLEN:         .word 0                 ;; the number of bytes in PARM1

;; The active function's parameters, which PTRGET searches before the simple variables.
PARM1:
    .res 100
PRMPRV:         .word 0                 ;; the previous parameter block, PRMSTK at first, for garbage collection
PRMLN2:         .word 0                 ;; the number of bytes in PARM2

;; The parameters of the function being called, built here before they become PARM1.
PARM2:
    .res 100
PRMFLG:         .byte 0                 ;; nonzero while PTRGET searches PARM1, before the simple variables
ARYTA2:         .byte 0                 ;; where PTRGET's simple search stops, ARYTAB or the end of PARM1; garbage collection's pointer
ARYTA2_HI:      .byte 0                 ;; ARYTA2's high byte
NOFUNS:         .byte 0                 ;; zero when no user function is active, so PTRGET need not search PARM1
TEMP9:          .word 0                 ;; garbage collection's pointer through the parameter blocks; CHAIN's work word
FUNACT:         .word 0                 ;; the number of user functions active

; FOR and NEXT, OPTION BASE.

INPPAS:         .byte 0                 ;; zero while INPUT checks its line on the first pass, nonzero while it assigns it
NXTTXT:         .word 0                 ;; the text pointer at the start of a NEXT
NXTFLG:         .byte 0                 ;; zero while FOR uses NEXT's code to check for a loop to skip

;; FOR's start value, single precision, kept until the limit and step have been evaluated, as ANSI requires.
FVALSV:
    .res 4
NXTLIN:         .word 0                 ;; the line being scanned for a NEXT or a WEND
OPTVAL:         .byte 0                 ;; OPTION BASE: the lowest subscript, 0 or 1
OPTFLG:         .byte 0                 ;; nonzero once OPTION BASE has run, which may not run twice
    .res 30                         ; nothing refers to these bytes

; CALL, LIST and INPUT, CHAIN and MERGE.

TEMPA:          .byte 0                 ;; a work byte: LIST's spacing flag, INPUT;'s no-return flag; with TEMPA_HI, CALL's address and FIELD's length
TEMPA_HI:       .byte 0                 ;; TEMPA's high byte, INPUT's flag: nonzero to print "? " after the prompt
SAVFRE:         .word 0                 ;; FRETOP, saved by CHAIN
MAXREC:         .word 0                 ;; the longest random record, which INIT sets from /S:, 128 when not given
PROFLG:         .byte 0                 ;; nonzero when a protected program has been loaded
MRGFLG:         .byte 0                 ;; nonzero while CHAIN MERGE runs
MDLFLG:         .byte 0                 ;; nonzero while CHAIN MERGE ... DELETE runs
CMEPTR:         .word 0                 ;; the line after the last one CHAIN's DELETE removes
CMSPTR:         .word 0                 ;; the first line CHAIN's DELETE removes
CHNFLG:         .byte 0                 ;; nonzero while CHAIN runs
CHNLIN:         .word 0                 ;; the line CHAIN starts the new program at, or zero for its first

;; The first SWAP variable's value, up to double precision.
SWPTMP:
    .res 8
TRCFLG:         .byte 0                 ;; nonzero while TRON traces line numbers

; The math package.

FAC_ROUND_BYTE: .byte 0                 ;; the accumulator's extra low byte, kept for rounding
DFACLO:         .word 0                 ;; the double precision accumulator's low bytes, below FACLO
DFAC_MID:       .word 0                 ;; the double precision accumulator's third and fourth bytes
FACLO:          .word 0                 ;; the accumulator: an integer, a string's descriptor, or a single's low mantissa
FACHI:          .byte 0                 ;; the sign and high bits of the accumulator's mantissa
FAC:            .byte 0                 ;; the accumulator's exponent: zero when the number is zero
FAC_SIGN_TEMP:  .byte 0                 ;; a work byte after the accumulator: the result's sign, complemented, during arithmetic
FLGOVC:         .byte 0                 ;; how an overflow prints: 0 always, 1 once (for INPUT), then 2
OVCSTR:         .byte 0                 ;; FLGOVC as FIN left it, so INPUT can tell a number overflowed
FOUFIX:         .byte 0                 ;; bit 7 set for FOUT's second pass, which writes a number that fits without an exponent
ARG_ROUND_BYTE: .byte 0                 ;; the second accumulator's extra low byte

;; The second accumulator's low bytes, for double precision.
ARGLO:
    .res 6
ARGHI:          .byte 0                 ;; the sign and high bits of the second accumulator's mantissa
ARG:            .byte 0                 ;; the second accumulator's exponent

;; FOUT's buffer, where a number is written as text; the last three bytes are FMULT's work bytes.
FBUFFR:
    .res 43

; The messages.

INTXT:          .byte " in "            ;; after an error's message in a program, before its line, ending at NULSTR
NULSTR:         .byte 0                 ;; INTXT's zero, which is also an empty string's descriptor: a length of zero
REDDY:          .byte "Ok", $0D, $0A, 0 ;; the prompt in direct mode
BRKTXT:         .byte "Break", 0        ;; the message when Control-C stops a program
