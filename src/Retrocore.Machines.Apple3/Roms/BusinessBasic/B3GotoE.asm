; B3GOTOE: GOSUB, GOTO, RETURN and POP, ON ... GOTO and ON ... GOSUB, the skips for DATA and REM, LINGET's line-number
; reader, LET with its string assignment, and PRINT with the output routines under it: OUTDO, STROUT, CRDO, and
; ROUTDO, LIST's output with its wrap.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; GOSUB, GOTO and RETURN
; ---------------------------------------------------------------------------------------------------------------------

;; The GOSUB statement: puts a GOSUB entry on the stack, then goes to the line as GOTO does.
;;
;; The entry, from <PSHTXT>, holds TXTPTR after the line number, where RETURN goes on, and the current <CURLIN>. It
;; goes under <NEWRET>, the return address to <NEWSTT>.
;; In: A = the character after GOSUB, flags as <CHRGOT> sets them
;; See: <RETURN>, <GOTO>
GOSUB:
    jsr SVTXT                               ; TXTPTR at the line number
    jsr CHRGOT
    jsr LINGET                              ; pass the number
    jsr PSHTXT
    jsr RSTTXT                              ; back to the number, for GOTO

;; Goes to the line whose number is at <TXTPTR>, returning to <NEWSTT> to run it.
RUNC2:
    jsr CHRGOT
    jsr GOTO
    rts

;; The GOTO statement: points <TXTPTR> at the zero before the line with the number given, so <NEWSTT> runs it.
;;
;; When more follows the number, GOTO does nothing and NEWSTT gives the syntax error.
;; In: A = the character after GOTO, flags as <CHRGOT> sets them
;; Errors: UNDEF'D STATEMENT when there is no such line
;; See: <GOTOB>
GOTO:
    jsr LINGET
    jsr CHRGOT
    bne PSHTRT

;; Finds the line numbered <LINNUM> and points <TXTPTR> at the zero before its link.
;;
;; A line after the current one is looked for from the next line on; any other, from the program's start (always, in
;; a direct line, whose <CURLIN> is $FFxx).
;; In: LINNUM = the line number, TXTPTR = in the current line
;; Uses: A, X, Y, LOWTR
;; See: <FNDLNC0>
GOTOB:
    jsr REMN                                ; Y = the end of the line
    lda CURLIN
    cmp LINNUM
    lda CURLIN+1
    sbc LINNUM+1
    bcs LUK4IT                              ; not later than this line: from the start
    tya                                     ; the next line's link: TXTPTR + Y + 1
    ldy TXTPTRB
    sec
    adc TXTPTR
    ldx TXTPTR+1
    bcc LUKALL
    inx
    cpx #MAXPG
    bcc LUKALL
    iny                                     ; page $82 is the next bank's page $02
    ldx #MINPG
    bne LUKALL
    bcs LUKALL                              ; never reached

;; Searches from the program's first line.
LUK4IT:
    lda TXTTAB
    ldx TXTTAB+1
    ldy TXTTABB

;; Searches from the line at A, X, Y (low, high, bank), then points <TXTPTR> one byte before the line found.
LUKALL:
    jsr FNDLNC0
    bcc USERR                               ; no such line
    lda LOWTR
    sbc #1
    sta TXTPTR
    lda LOWTR+1
    sbc #0
    ldy LOWTRB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc #0
    sta TXTPTRB

;; An RTS for the statements here.
GORTS:
    rts

;; The DATA statement: in a program, passes over the statement as REM does; in a direct line, an error.
DATAIS:
    jsr ERRDIR
    bne REM                                 ; always

;; The RETURN statement, and POP: takes the newest GOSUB entry off the stack, with any FOR entries above it.
;;
;; RETURN goes on from the entry's text pointer, after the GOSUB, on its line; POP goes on after itself. Both share
;; this handler, and Y, <GONE3>'s index into <STMDSP>, tells them apart.
;; In: Y = the statement's index in STMDSP, times two, zero = set for a terminator
;; Errors: RETURN WITHOUT GOSUB when no GOSUB entry is under the FOR entries
;; See: <GOSUB>, <PSHTXT>, <FNDFOR>
RETURN:
    bne GORTS                               ; more follows: NEWSTT gives the syntax error
    lda #255
    sta TEMPFOR                             ; matches no FOR entry
    jsr FNDFOR
    cmp #GOSUTK
    beq RETU1
    ldx #ERRRG
    .byte 44                                ; BIT abs, which skips the next LDX

;; Ends the statement with UNDEF'D STATEMENT.
USERR:
    ldx #ERRUS
    jmp ERROR

;; Takes the GOSUB entry off: the stack is cut to it, which drops NEWSTT's return address and the FOR entries, and
;; RETURN's <CURLIN> and <TXTPTR> come from it.
;; In: X = the entry's place on the stack
RETU1:
    txs
    pla                                     ; GOSUTK
    pla                                     ; the line number's low byte
    cpy #<(POPTKN*2)
    beq DOPOP
    sta CURLIN
    pla
    sta CURLIN+1
    pla
    sta TXTPTRB                             ; the offset's bank
    clc
    pla
    tay                                     ; its high byte
    pla                                     ; its low byte
    adc TXTTAB
    sta TXTPTR
    tya
    adc TXTTAB+1
    ldy TXTTABB
    jsr FIXADC
    sta TXTPTR+1
    tya
    adc TXTPTRB
    sta TXTPTRB
    jmp NWSTT

;; Moves <TXTPTR> to the end of the statement: a colon or the line's zero, outside quotes.
;; Out: A = the terminator
;; See: <DATAN>, <ADDON>
DATA:
    jsr DATAN

;; Adds Y to <TXTPTR>, into the next bank past MAXPG.
;; In: Y = the count to add
ADDON:
    tya
    clc
    adc TXTPTR
    sta TXTPTR
    bcc REMRTS
    lda TXTPTR+1
    adc #0
    ldy TXTPTRB
    jsr FIXADC
    sty TXTPTRB
    sta TXTPTR+1

;; An RTS for the skips; a statement returns from here to <NEWSTT>.
REMRTS:
    rts

;; Ends the statement with a syntax error.
SNERR2:
    jmp SNERR

;; The REM statement: moves <TXTPTR> to the end of the line.
REM:
    jsr REMN
    beq ADDON                               ; always

;; Finds the end of the statement: a colon or a zero, outside quotes.
;; In: TXTPTR = where to start
;; Out: Y = the terminator's index from TXTPTR, A = the terminator, zero = set
;; Uses: CHARAC, ENDCHR
;; See: <REMN>
DATAN:
    ldx #':'
    .byte 44                                ; BIT abs, which skips REMN's LDX

;; Finds the end of the line: its zero.
;;
;; CHARAC and ENDCHR hold the two characters that end the scan besides the zero; a quote swaps them, so inside quotes
;; only the zero ends it.
;; In: TXTPTR = where to start
;; Out: Y = the zero's index from TXTPTR, A = 0, zero = set
;; Uses: CHARAC, ENDCHR
;; See: <DATAN>
REMN:
    ldx #0
    stx CHARAC
    ldy #0
    sty ENDCHR

;; Swaps the end characters, at the start and at each quote.
EXCHQT:
    lda ENDCHR
    ldx CHARAC
    sta CHARAC
    stx ENDCHR

;; Scans for a zero or ENDCHR, swapping at each quote.
REMER:
    lda (TXTPTR),Y
    beq REMRTS
    cmp ENDCHR
    beq REMRTS
    iny
    cmp #34                                 ; a quote?
    bne REMER
    beq EXCHQT

;; Ends POP: drops the rest of the GOSUB entry and goes on after POP.
DOPOP:
    pla
    pla
    pla
    pla
    jmp NEWSTT

; ---------------------------------------------------------------------------------------------------------------------
; ON ... GOTO and ON ... GOSUB
; ---------------------------------------------------------------------------------------------------------------------

;; The ON statement: ON ERR, ON KBD and ON EOF# go to their own handlers; otherwise ON n GOTO or ON n GOSUB goes to the
;; nth line of the list.
;;
;; An n of 0, or past the list's end, goes on with the next statement.
;; In: A = the character after ON, flags as <CHRGOT> sets them
;; See: <ONERR>, <ONKBD>, <ONEOF>
ONGOTO:
    cmp #ERRTK
    beq GOERR
    cmp #KBDTK
    beq GOKBD
    cmp #EOFTK
    bne ONGOTO2
    jmp ONEOF

;; Reads n and the GOTO or GOSUB after it.
ONGOTO2:
    jsr GETBYT                              ; n into FACLO
    pha                                     ; the token after it
    cmp #GOSUTK
    beq ONGLOP

;; Ends the statement with a syntax error unless A is GOTO's token.
SNERR3:
    cmp #GOTOTK
    bne SNERR2

;; Counts n down, passing a line number for each step; at zero, goes to the line that follows.
ONGLOP:
    dec FACLO
    bne ONGLP1
    pla
    cmp #GOSUTK
    bne DOONGT
    jsr SVTXT
    jsr DATA                                ; GOSUB's entry goes on after the statement
    jsr PSHTXT
    jsr RSTTXT
    jsr DOONGT
    rts

;; Reads the line number after TXTPTR and goes to it through <GOTOB>.
DOONGT:
    jsr CHRGET                              ; the token or the comma
    jsr LINGET
    jmp GOTOB

;; Passes a line number of the list, and goes on at a comma; at the list's end, ON does nothing.
ONGLP1:
    jsr CHRGET
    jsr LINGET
    cmp #44                                 ; a comma?
    beq ONGLOP
    pla

;; An RTS for ON and LINGET.
ONGRTS:
    rts

;; ON ERR.
GOERR:
    jmp ONERR

;; ON KBD.
GOKBD:
    jmp ONKBD

; ---------------------------------------------------------------------------------------------------------------------
; Line numbers
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a line number, 0 to 63999, from the text into <LINNUM>; with no digit there, LINNUM is 0.
;; In: A = the character at TXTPTR, carry = clear for a digit, as <CHRGOT> leaves them
;; Out: LINNUM = the number, TXTPTR = the character after it, A = that character, flags as <CHRGET> sets them
;; Errors: SYNTAX ERROR for 64000 or more
;; Uses: X, CHARAC, INDEX
LINGET:
    ldx #0
    stx LINNUM
    stx LINNUM+1

;; Adds a digit to <LINNUM>, unless the character is not a digit.
MORLIN:
    bcs ONGRTS
    sbc #'0'-1                              ; carry is clear
    sta CHARAC
    lda LINNUM+1
    sta INDEX
    cmp #25                                 ; 6400 or more would pass 63999
    bcs SNERR3
    lda LINNUM                              ; LINNUM times 10: times 4, plus itself, times 2
    asl
    rol INDEX
    asl
    rol INDEX
    adc LINNUM
    sta LINNUM
    lda INDEX
    adc LINNUM+1
    sta LINNUM+1
    asl LINNUM
    rol LINNUM+1
    lda LINNUM
    adc CHARAC
    sta LINNUM
    bcc NXTLGC
    inc LINNUM+1

;; Reads the next character.
NXTLGC:
    jsr CHRGET
    jmp MORLIN

; ---------------------------------------------------------------------------------------------------------------------
; LET
; ---------------------------------------------------------------------------------------------------------------------

;; The LET statement, and any statement without a keyword: evaluates the formula after `=` and assigns it.
;; In: TXTPTR = before the variable's name
;; Errors: TYPE MISMATCH, from <FRMEVL>, when the formula's type is not the variable's
;; See: <LETP2>, <INPCOM>
LET:
    jsr MYPTRGET                            ; the variable's address in FORPNT
    jsr CHKEQL
    lda INTFLG
    pha
    lda ISARA
    pha
    jsr FRMEVL
    jmp LETP3

;; Assigns the value in the FAC to the variable at <FORPNT>, as LET does; the disk statements and INPUT use it.
;; In: FORPNT, FORPNTB = the variable, VALTYP, INTFLG, ISARA = its type, the FAC = the value
LETP2:
    lda INTFLG
    pha
    lda ISARA
    pha

;; Assigns by the value's type: a string through <INPCOM>, a long integer through <STFACT>, a real or an integer
;; through <QINTGR>, taking ISARA and INTFLG back off the stack.
LETP3:
    pla
    sta ISARA
    bit VALTYP
    bmi COPSTR                              ; a string
    bvs BMOVVF                              ; a long integer
    pla
    sta INTFLG

;; Stores the FAC in the variable at <FORPNT>: a real as it is, an integer rounded to two bytes, high byte first.
;; In: negative = set for an integer, as INTFLG sets it
QINTGR:
    bpl COPFLT
    jsr ROUND
    jsr AYINT
    ldy #0
    lda FACMO
    sta (FORPNT),Y
    iny
    lda FACLO
    sta (FORPNT),Y
    rts

;; Stores the FAC as a real.
COPFLT:
    jmp MOVVF

;; Stores a long integer, dropping INTFLG from the stack.
BMOVVF:
    pla

;; Stores the long integer in the FAC in the variable at <FORPNT>.
BMOVF1:
    ldx FORPNTB
    lda FORPNT
    ldy FORPNT+1
    jmp STFACT

;; Assigns a string, dropping INTFLG from the stack.
COPSTR:
    pla

;; Assigns the string whose descriptor <FACMO> points to, to the string variable at <FORPNT>.
;;
;; A variable's string is copied to new room; a temporary's (one in BASIC's own bank, FACMOB zero) is taken over. The
;; variable's old string is freed, the descriptor copied in, and the string's information bytes, at <HIGHDS>, are set
;; to point back at the variable: its type ($41 for a simple variable, $81 for an array element) and its offset from
;; <RELPTR>. An empty string gets no back pointer.
;; In: FACMO, FACMOB = the descriptor, FORPNT, FORPNTB = the variable, ISARA = negative for an array element
;; Errors: VARIABLE error when the offset does not fit in 16 bits
INPCOM:
    ldy FACMOB                              ; zero for a temporary
    bne COPY
    lda FACMO
    ldy FACMO+1
    ldx FACMOB
    jmp COPY_C

;; Copies a variable's string to new room, making the copy a temporary.
COPY:
    ldy #0
    lda (FACMO),Y                           ; the length
    jsr STRINI

;; Moves the string into the room and makes its temporary descriptor.
COPY_M:
    lda DSCPNT
    ldy DSCPNT+1
    ldx DSCPNTB
    sta STRNG1
    sty STRNG1+1
    stx STRNG1B
    jsr MOVINS
    jsr PUTNEW
    lda FACMO
    ldy FACMO+1
    ldx FACMOB

;; Frees the temporary descriptor (not its string) and the variable's old string, then copies the descriptor in.
;; In: A, Y, X = the descriptor (low, high, bank)
COPY_C:
    sta DSCPNT
    stx DSCPNTB
    sty DSCPNT+1
    jsr FRETMS
    lda FORPNT
    ldy FORPNT+1
    ldx FORPNTB
    jsr NOTNW2                              ; the old string into INDEX
    jsr FRESPA
    ldy #$2

;; Copies the descriptor's three bytes into the variable.
COPY_S:
    lda (DSCPNT),Y
    sta (FORPNT),Y
    dey
    bpl COPY_S
    tax                                     ; the length
    beq LETRTS                              ; empty: no back pointer

;; Points the string's information bytes back at its variable.
FIXBAK:
    jsr RELPTR
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY                               ; the offset, packed to 16 bits
    cpy #$FF
    bcc VAERR
    ldy #2
    sta (HIGHDS),Y
    dey
    lda FORPNT
    sta (HIGHDS),Y
    txa                                     ; ISARA, as RELPTR leaves X
    bmi *+5
    lda #SIMTYP
    .byte 44                                ; BIT abs, which skips the LDA
    lda #ARYTYP
    dey
    sta (HIGHDS),Y

;; An RTS for LET.
LETRTS:
    rts

;; Turns the variable pointer in <FORPNT> into an offset: from <ARYTAB> for an array element, otherwise from the
;; simple variables' start through <PNTREL>.
;;
;; An offset is the table's start less the address, so the same subtraction turns it back into the address.
;; In: ISARA = negative for an array element
;; Out: X = ISARA, FORPNT, FORPNT+1, FORPNTB = the offset
;; Errors: OUT OF MEMORY when an array element's offset passes 64K
;; See: <RELPTR2>, <FIXBAK>
RELPTR:
    ldx ISARA
    bpl ISSIMP

;; Inherit: <RELPTR>
;; Takes FORPNT as an array element's.
RELPTR2:
    lda ARYTAB
    sec
    sbc FORPNT
    sta FORPNT
    lda ARYTAB+1
    sbc FORPNT+1
    ldy ARYTABB
    jsr FIXSBC
    sta FORPNT+1
    tya
    sbc FORPNTB
    sta FORPNTB
    bcc GOTRELA                             ; a borrow, as there should be
    jmp OMERR

;; Makes a simple variable's offset.
ISSIMP:
    jsr PNTREL

;; An RTS for RELPTR.
GOTRELA:
    rts

;; Ends the statement with the VARIABLE error.
VAERR:
    ldx #ERRVA
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; PRINT
; ---------------------------------------------------------------------------------------------------------------------

;; Prints a string, then goes on with PRINT's list.
STRDON:
    jsr STRPRT

;; Goes on with PRINT's list at the current character.
NEWCHR:
    jsr CHRGOT

;; Prints PRINT's list: values, TAB( and SPC(, with commas and semicolons between; a list that does not end in a comma
;; or semicolon ends with a RETURN.
;;
;; A comma moves to the next column of 16; a semicolon prints nothing.
;; In: A = the character at TXTPTR, flags as <CHRGOT> sets them
;; See: <DOPRINT>, <PRINTC>
PRINT:
    beq CRDO

;; Prints the rest of the list after a comma, a semicolon, TAB( or SPC(, where a terminator ends the line without a
;; RETURN.
PRINTC:
    beq PRTRTS
    lda #TABTK
    jsr TRYESC
    beq TABER
    lda #SPCTK
    jsr TRYESC
    clc                                     ; carry clear for SPC(
    beq TABER
    cmp #44                                 ; a comma?
    beq COMPRT
    cmp #59                                 ; a semicolon?
    bne *+5
    jmp NOTABR
    lda #$20                                ; any type will do
    sta VALTYP
    jsr FRMEVL
    bit VALTYP
    bmi STRDON                              ; a string
    bvc ISBIN                               ; a real
    jsr LOUT                                ; a long integer, as text in NUMSTR
    lda #<(NUMSTR)
    sta INDEX
    lda #>(NUMSTR)
    sta INDEX+1
    lda #NUMSTRB
    sta INDEXB
    ldx LENUM
    jsr STRPR3
    beq NEWCHR                              ; always

;; Prints a real, through <FOUT>'s text.
ISBIN:
    jsr FOUT
    jsr STRLIT
    jmp STRDON

;; Ends the output line: a RETURN, then a line feed when the output goes to the console or another device rather than
;; a disk file; <TRMPOS> goes back to 0.
;; Uses: A, TEMP, KIMY
CRDO:
    lda #13
    jsr OUTDO
    stx TEMP
    sty KIMY
    ldx FILNO
    bmi DOLF                                ; the console
    jsr GTFLNO1
    lda FCB,Y                               ; bit 7 set for a device
    bpl DOLFRT                              ; a disk file: no line feed

;; Prints the line feed.
DOLF:
    lda #10
    jsr OUTDO

;; Sets the column back to 0 and takes X and Y back.
DOLFRT:
    ldx #0
    stx TRMPOS
    ldx TEMP
    ldy KIMY

;; An RTS for PRINT.
PRTRTS:
    rts

;; Frees the string just printed, if it was one.
;; In: VALTYP = the printed value's type
PRTRTS1:
    bit VALTYP
    bpl PRTRTS
    jmp FRECNOW

;; Moves to the next column of 16, past the current one.
;; In: carry = set, as the comma's compare leaves it
COMPRT:
    lda TRMPOS
    adc #$0F
    and #$F0
; A check against the window's width is left out here.
    sec
    sbc TRMPOS
    tax
    jmp XSPAC1

;; Does TAB(n), which moves to column n (1 first) when the output is short of it, or SPC(n), which prints n spaces.
;; In: carry = set for TAB(, clear for SPC(
;; Errors: ILLEGAL QUANTITY for TAB(0)
TABER:
    php
    jsr GTBYTC                              ; n into X
    stx TEMP
    jsr CHKCLS
    jsr DECTPT                              ; back one, for NOTABR's CHRGET
    plp
    ldx TEMP
    bcc XSPAC                               ; SPC(
    bne *+5
    jmp TOOBIG
    dex
    txa
    sbc TRMPOS
    bcc NOTABR                              ; already past it
    tax

;; Prints X spaces, then goes on with the list.
XSPAC:
    inx

;; Counts the spaces down.
XSPAC2:
    dex
    bne XSPAC1

;; Goes on with the list after its separator.
NOTABR:
    jsr CHRGET
    jmp PRINTC

;; Prints a space and counts it.
XSPAC1:
    jsr OUTSPC
    bne XSPAC2

;; Prints a string that ends in a zero, making a temporary for it.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <STROUTR>
STROUT:
    jsr STRLIT

;; Prints the string whose descriptor <FACMO> points to, then frees it if it is a temporary.
STRPRT:
    jsr NOTFAC
    tax

;; Prints X characters from <INDEX>, to the console or the output file, with one SOS WRITE through <SINIT>.
;;
;; SINIT's reference number is the console's; for a file, the file's goes in for the call and the console's comes back.
;; The WRITE's buffer address is INDEX itself, a zero-page pointer, which SOS reads with its bank byte.
;; In: X = the length, INDEX, INDEXB = the string, VALTYP = negative for a string to free afterwards
STRPR3:
    stx OUTSTRL
    txa
    beq STRPR4
    ldy SINIT+1                             ; the console's reference number
    bit FILNO
    bmi GOOUT                               ; the console
    pha
    ldx FILNO
    jsr GTFLNO1
    jsr PRETXT
    jsr TSTOUT
    lda FCB,Y                               ; the file's reference number
    ldy SINIT+1
    sta SINIT+1
    pla

;; Counts the characters into <TRMPOS> and makes the WRITE.
GOOUT:
    clc
    adc TRMPOS
    sta TRMPOS
    lda #<(INDEX)
    sta SPRNTPL
    lda #>(INDEX)
    sta SPRNTPL+1
    brk
    .byte SWRT
    .word SINIT
    sty SINIT+1                             ; the console's reference number back
    bne OTDOER

;; Frees the string, if it was one.
STRPR4:
    jmp PRTRTS1

;; Prints a space.
;; See: <OUTDO>
OUTSPC:
    lda #$20
    .byte 44                                ; BIT abs, which skips the next LDA

;; Prints a question mark.
;; See: <OUTDO>
OUTQST:
    lda #'?'

;; Prints the character in A, to the console or the output file, and counts it in <TRMPOS>.
;;
;; A file's character goes out with a one-byte SOS WRITE through <SCHRTB>, with the file's reference number put in
;; for the call.
;; In: A = the character, FILNO = the output file, negative for the console
;; Out: A = the character
;; See: <PRNACHAR>
OUTDO:
    inc TRMPOS
    bit FILNO
    bmi OUTLOC                              ; the console
    sta OUTCHAR
    txa
    pha
    tya
    pha
    lda #3
    sta SCHRTB
    ldx FILNO
    jsr GTFLNO1
    jsr PRETXT
    jsr TSTOUT
    lda FCB,Y
    ldy SCHRTB+1
    sta SCHRTB+1
    brk
    .byte SWRT
    .word SCHRTB
    sty SCHRTB+1
    bne OTDOER
    pla
    tay
    pla
    tax
    lda OUTCHAR
    rts

;; Ends the statement with the WRITE's error.
OTDOER:
    jmp SERROR

;; Prints the character on the console.
OUTLOC:
    jmp PRNACHAR

;; The PRINT statement: PRINT# n; to a file, PRINT USING, or PRINT to the console.
;;
;; For the console, the cursor's column is read first, so commas and TAB( count from where the cursor is.
;; In: A = the character after PRINT, flags as <CHRGOT> sets them
;; See: <PRINT>, <PRUSING>
DOPRINT:
    cmp #'#'
    bne GPRNT2
    lsr IOFLG
    jsr FILNUM
    lda SVFLNO
    sta FILNO
    jsr CHRGOT
    beq GPR3                                ; nothing more
    cmp #$3B                                ; a semicolon?
    bne GPRNT
    jsr SYNCHR

;; Takes PRINT USING, or the plain list.
GPRNT:
    lda #USINGTK
    jsr TRYESC
    bne GPR3
    jsr PRUSING
    rts

;; Prints the list.
GPR3:
    jsr CHRGOT
    jmp PRINT

;; Reads the cursor's column into <TRMPOS> when the output goes to the console.
GPRNT2:
    bit FILNO
    bpl GPR4                                ; to a file: leave TRMPOS
    jsr VPOS
    lda CURX
    sta TRMPOS

;; Goes on with PRINT USING or the list.
GPR4:
    jmp GPRNT

;; Prints a string that ends in a zero, as it is, without the string routines; the length must be under 256.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <STROUT>
STROUTR:
    sta INDEX
    sty INDEX+1
    stx INDEXB
    ldy #$FF

;; Counts to the zero.
STRLUP:
    iny
    lda (INDEX),Y
    bne STRLUP
    tya
    tax
    lda #0                                  ; nothing to free
    sta VALTYP
    jmp STRPR3

; ---------------------------------------------------------------------------------------------------------------------
; LIST's output
; ---------------------------------------------------------------------------------------------------------------------

;; Prints a space as <ROUTDO> does.
ROUTSPC:
    lda #' '

;; Prints a character for LIST, first wrapping the line when the output has reached <OUTREC>'s width.
;;
;; A wrapped line goes on after spaces to the column in DELTA+1, where the listed line's text started. OUTREC 0 turns
;; the wrap off.
;; In: A = the character, DELTA+1 = the margin
;; Errors: RANGE ERROR when the margin leaves no room in the width
;; See: <LIST>, <OUTDO>
ROUTDO:
    pha
    lda OUTREC
    beq ROUTDONE                            ; no wrap
    clc
    sbc TRMPOS                              ; OUTREC less TRMPOS, less one
    beq *+4
    bcs ROUTDONE                            ; room left
    jsr CRDO

;; Prints spaces up to the margin.
TSTTAB:
    jsr OUTSPC
    lda DELTA+1
    cmp TRMPOS
    bcs TSTTAB
    cmp OUTREC
    bcc *+5
    jmp RNGERR

;; Prints the character.
ROUTDONE:
    pla
    jmp OUTDO
