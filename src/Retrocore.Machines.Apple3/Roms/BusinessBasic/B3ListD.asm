; B3LISTD: LIST, which turns the program's tokens back into text; FOR, which puts a loop's entry on the stack; the
; statement fetcher NEWSTT, which runs the program one statement at a time; and RESTORE, STOP, END, CONT, BYE, RUN and
; the GOSUB entry's push.
;
; A program line in memory is a one-byte link (the line's length, from this byte to the next line's link), the line
; number (low byte, high byte), the tokenized text, and a zero. A zero link ends the program, and a zero stands just
; before the first line, at TXTTAB-1. Pointers into the program carry a bank byte at their address plus SYSPAG, as
; TXTPTR does in TXTPTRB, and keep their page in MINPG to MAXPG-1 ($02-$81). Pages $82 and up of one bank are the same
; memory as pages $02 and up of the next, so a pointer may run past MAXPG and still read the right byte; the code
; brings it back into range where a line starts.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; LIST
; ---------------------------------------------------------------------------------------------------------------------

;; The LIST statement: lists the program, or the lines in a range, turning tokens back into words.
;;
;; The range is `LIST`, `LIST n`, `LIST n-`, `LIST -m` or `LIST n-m`, where a comma or TO may stand for the dash.
;; Each line is printed as a space, its number, <INDENT> spaces times one more than the FORs open, and its
;; text; text wraps at <OUTREC> to the column the text started in. A FOR adds a level for the lines after it and each
;; variable of a NEXT takes one away. CONTROL-C stops the listing with BREAK.
;; In: A = the character after LIST, flags as <CHRGOT> sets them
;; Uses: A, X, Y, LINNUM, LOWTR, VARNAM, DELTA, FAC, FORPNT, INPFLG
;; See: <ROUTDO>, <QPLOP>, <FNDLIN>
LIST:
    php                                     ; zero set: nothing follows LIST
    ldx #0
    stx DELTA                               ; no FOR open yet
    jsr LINGET                              ; the first line's number, or 0
    jsr FNDLIN                              ; LOWTR = the first line at or after it
    plp
    bne GOLS1

;; Lists to the end of the program: sets the last line's number to $FFxx.
LXZYQ:
    lda #255
    sta LINNUM+1

;; Reads the rest of LIST's range: a terminator lists the one line, a dash, comma or TO reads the last line's number.
GOLS1:
    jsr CHRGOT
    beq LSTEND                              ; only one number: the last is the first
    cmp #'-'
    beq LSTOK
    cmp #$2C
    beq LSTOK
    lda #TOTK
    jsr TRYESC
    beq LSTOK
    jmp SNERR

;; Reads the last line's number after the dash, comma or TO; nothing there lists to the end.
LSTOK:
    jsr CHRGET
    beq LXZYQ
    jsr LINGET
    jsr CHRGOT
    bne LSTRTS                              ; more after it: NEWSTT gives the syntax error

;; Starts the listing at the line <FNDLIN> found, through <VARNAM>.
LSTEND:
    lda LOWTR
    sta VARNAM
    lda LOWTR+1
    sta VARNAM+1
    lda LOWTRB
    sta VARNAMB

;; Lists the line at <VARNAM>, unless it is past the last line asked for or the program has ended.
;; In: VARNAM = the line's link byte, LINNUM = the last line to list
LIST4:
    ldy #0
    lda (VARNAM),Y                          ; a zero link ends the program
    beq GREEDY
    bit KEYSTROK                            ; CONTROL-C?
    bvc *+5
    jmp ISCNTC
    jsr CRDO
    iny
    lda (VARNAM),Y                          ; the line number's low byte
    tax
    iny
    lda (VARNAM),Y                          ; and its high byte
    cmp LINNUM+1
    bne TSTDUN
    cpx LINNUM
    beq TYPLIN

;; Ends the listing when the line's number is past the last one's.
;; In: carry = set when the line is past the last
TSTDUN:
    bcs LSTRTS

;; Prints the line number and the indentation, then the text.
;; In: X, A = the line number (low, high), Y = 2
TYPLIN:
    sty LSTPNT
    pha
    jsr ROUTSPC                             ; a space before the number
    pla
    jsr LINPRT
    ldx INDENT
    beq PLOOP3

;; Prints DELTA+1 spaces, once for each of <INDENT>'s spaces per level.
PLOOP1:
    ldy DELTA

;; Prints one space of the level's indentation.
PLOOP0:
    jsr OUTSPC
    dey
    bpl PLOOP0
    dex
    bne PLOOP1

;; Notes the column the text starts in, as the margin for wrapped text.
;;
;; A still holds what the output left, which <PLOOP5> prints: a space after the indentation, or, with no
;; indentation, the 0 that SOS's WRITE left after the line number.
PLOOP3:
    ldy TRMPOS                              ; the margin for ROUTDO's wrap
    sty DELTA+1
    ldy LSTPNT

;; Prints a character of the line, or starts a quoted string at a quote.
;; In: A = the character, Y = its index in the line
PLOOP5:
    cmp #'"'
    beq PLOOP7

;; Prints a character of the line.
PLOOP:
    jsr ROUTDO

;; Takes the line's next byte: a zero ends the line.
PLOOP2:
    iny
    lda (VARNAM),Y
    bne QPLOP                               ; not the end: a character or a token

;; Moves <VARNAM> past the line's zero to the next line's link, into the next bank past MAXPG, and lists it.
PLOOP8:
    sec                                     ; the zero's index, plus one
    tya
    adc VARNAM
    sta VARNAM
    bcc LIST4
    ldx VARNAM+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG                              ; page $82 is the next bank's page $02
    inc VARNAMB
    stx VARNAM+1
    jmp LIST4

;; Reads the next byte of a reserved-word list, through the pointer in FAC.
;;
;; The lists lie in BASIC's own bank, so the page can go up without the bank.
;; In: Y = the index of the byte before
;; Out: A = the byte, negative = set for a word's last character
GETNXTW:
    iny
    bne *+4
    inc FAC+1
    lda (FAC),Y

;; An RTS for LIST's branches.
LSTRTS:
    rts

;; Ends the listing with a RETURN.
GREEDY:
    jmp CRDO

;; Prints a quoted string as it is, up to its closing quote or the end of the line.
PLOOP7:
    jsr ROUTDO
    iny
    lda (VARNAM),Y
    beq PLOOP8
    cmp #'"'
    bne PLOOP7
    beq PLOOP

;; Prints a character, or a token as its reserved word.
;;
;; A token is one byte, $80-$FE, for a word of <RESLST>, or $FF and a second byte for a word of <RESL2>. A space goes
;; before the word unless it starts the line or follows a token or a colon (or, for an escape token, unless it is a
;; function); a space goes after a word that ends in a letter when a token, a letter, a digit or a period follows.
;; FOR and NEXT change the indentation of the lines after them in DELTA.
;; In: A = the byte, negative = set for a token, Y = its index in the line
;; See: <GETNXTW>, <CKSEP>
QPLOP:
    bpl PLOOP5                              ; a character
    cmp #FORTK
    bne *+4
    inc DELTA                               ; FOR: one level more
    cmp #FORTK+1                            ; NEXT?
    bne NOTSPEC4
    sty YSAVE

;; Takes a level away for each of NEXT's variables, never below zero.
NOTSPEC0:
    dec DELTA
    bpl NOTSPEC2
    inc DELTA

;; Looks for another of NEXT's variables, after a comma, up to the end of the statement.
NOTSPEC2:
    iny
    lda (VARNAM),Y
    beq NOTSPEC3
    cmp #':'
    beq NOTSPEC3
    cmp #','
    beq NOTSPEC0
    bne NOTSPEC2

;; Takes NEXT's token back.
NOTSPEC3:
    ldy YSAVE
    lda (VARNAM),Y

;; Points FAC at the reserved words: <RESLST> for a one-byte token, <RESL2> for an escape token's second byte.
;;
;; FAC is set a page below the list, as <GETNXTW>'s first INY takes Y from $FF to 0 and carries into the page.
NOTSPEC4:
    ldx #<(RESLST)
    stx FAC
    ldx #>(RESLST-256)
    stx FAC+1
    ldx #RESLSTB
    stx FACB
    tax
    inx                                     ; INPFLG = 0 for an escape token, negative for another
    stx INPFLG
    cmp #$FF
    bne NRMTKN
    iny
    lda (VARNAM),Y                          ; the escape token's second byte
    ldx #<(RESL2)
    stx FAC
    ldx #>(RESL2-256)
    stx FAC+1
    ldx #RESLSTB
    stx FACB

;; Finds the token's word in the list: the token's number, less $80, counts the words to pass.
;; In: A = the token, Y = the index of its last byte in the line
NRMTKN:
    sec
    sbc #128
    tax
    stx TKNSAV
    sty LSTPNT
    ldy #255                                ; GETNXTW's first INY makes it 0

;; Counts down the words to pass; at zero, the word is found.
RESRCH:
    dex
    bmi PRIT25

;; Passes one word, up to its last character's set bit 7.
RESCR1:
    jsr GETNXTW
    bpl RESCR1
    bmi RESRCH

;; Decides whether a space goes before the word, from what comes before the token.
;;
;; A token at the line's start (index 3) takes none; nor does one after a colon or a token, nor an escape token for a
;; function (SGN( on in <RESL2>).
PRIT25:
    lda LSTPNT
    cmp #3                                  ; the first byte of the line's text
    beq PRIT3
    tya                                     ; the word's index in the list
    pha
    ldy LSTPNT
    dey
    bit INPFLG                              ; an escape token?
    bmi PRIT26
    dey                                     ; yes: look before its $FF
    lda TKNSAV
    cmp #ONEFUN-$80                         ; a function: no space
    bcs PRIT27

;; Looks at the byte before the token: carry is set for a colon or a token.
PRIT26:
    lda (VARNAM),Y
    cmp #':'
    beq PRIT27
    asl                                     ; bit 7 into carry: a token

;; Prints the space before the word unless carry says not to.
;; In: carry = set for no space
PRIT27:
    pla
    tay
    bcs PRIT3
    jsr ROUTSPC

;; Prints the word, then its last character without bit 7.
PRIT3:
    jsr GETNXTW
    bmi PRFINIS
    jsr ROUTDO
    jmp PRIT3

;; Prints the word's last character, then a space when the word ends in a letter and a token, a letter, a digit or a
;; period follows.
PRFINIS:
    and #$7F
    jsr ROUTDO
    ldy LSTPNT
    iny
    cmp #'A'                                ; ends in a symbol, as in PR# or CHR$(: no space
    bcc JPL2
    lda (VARNAM),Y
    bmi PRF2                                ; a token follows
    jsr CKSEP
    bcc JPL2                                ; a separator follows

;; Prints the space after the word.
PRF2:
    jsr ROUTSPC

;; Goes on with the byte after the token.
JPL2:
    dey
    jmp PLOOP2

; ---------------------------------------------------------------------------------------------------------------------
; FOR
; ---------------------------------------------------------------------------------------------------------------------

;; Turns the variable pointer in <FORPNT> into an offset from the simple variables' start, <SMVARS>, or back again.
;;
;; The offset is SMVARS less the address, so the same subtraction undoes it. Loops and string back pointers keep
;; offsets, which stay right when the variable table moves.
;; Out: FORPNT, FORPNT+1, FORPNTB = the offset (or the address)
;; Uses: A, Y, KIMY
;; See: <RELPTR>, <PNTRL1>
PNTREL:
    stx KIMY
    ldx #FORPNT

;; Inherit: <PNTREL>
;; Takes the pointer at the zero-page address in X.
;; In: X = the zero-page address of the pointer
PNTRL1:
    lda SMVARS
    sec
    sbc 0,X
    sta 0,X
    lda SMVARS+1
    sbc 1,X
    ldy SMVARSB
    jsr FIXSBC
    sta 1,X
    tya
    sbc SYSPAG,X                            ; the pointer's bank byte
    sta SYSPAG,X
    ldx KIMY
    rts

;; The FOR statement: assigns the loop variable its first value and puts the loop's entry on the stack.
;;
;; The entry is <FORSIZ> (20) bytes, from the top of the stack down:
;;
;; - FORTK;
;; - the variable's type: bit 7 set for an integer, bit 0 for an array element (as in TEMPFOR);
;; - the variable's offset (low, high), from <RELPTR>, packed to 16 bits;
;; - the step, five bytes, unpacked, from <PUSHF>;
;; - the step's sign: 1 for positive, 0 for zero, $FF for negative;
;; - the limit, five bytes, packed with its sign in bit 7 of the first mantissa byte;
;; - the FOR's line number (low, high);
;; - the text pointer to the FOR statement's end, as an offset from <TXTTAB> (bank, high, low).
;;
;; An entry for the same variable already on the stack is taken out; the newer FOR entries above it move up to close
;; the gap and stay.
;; FOR then falls into <NEWSTT>; the loop's body runs at least once, as <NEXT> makes the test.
;; In: A = the character after FOR, flags as <CHRGOT> sets them
;; See: <NEXT>, <FNDFOR>, <LDFONE>
FOR:
    jsr LET
    lda VALTYP
    beq *+5
    jmp TMERR                               ; only a real or an integer
    lda ISARA
    rol
    lda INTFLG
    adc #0                                  ; an array element into bit 0
    sta TEMPFOR
    jsr RELPTR
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY
    sta FORPNT+1
    cpy #$FE                                ; the offset must fit in 16 bits
    bcs *+5
    jmp OVERR
    jsr FNDFOR
    bne NOTOL                               ; no loop on this variable yet
    lda #1                                  ; take its entry out: move the stack above it up FORSIZ bytes
    sta HIGHDSB
    sta HIGHTRB
    sta LOWTRB
    sta HIGHDS+1
    sta HIGHTR+1
    sta LOWTR+1
    inx
    stx HIGHTR
    txa
    clc
    adc #FORSIZ
    sta HIGHDS
    tsx
    stx LOWTR
    jsr BLTUC
    tsx
    txa
    clc
    adc #FORSIZ
    tax
    txs

;; Builds the new entry, starting with the text pointer and line number <PSHTXT3> pushes, then reads TO and the limit.
NOTOL:
    pla                                     ; NEWSTT's return address: FOR falls into NEWSTT instead
    pla
    lda #10
    jsr GETSTK                              ; room for 20 bytes
    jsr SVTXT
    jsr DATA                                ; TXTPTR to the FOR statement's end
    jsr PSHTXT3
    pla                                     ; the GOSUB entry's token: not a FOR entry's
    jsr RSTTXT
    lda #TOTK
    jsr MSTESC
    jsr CHKNUM
    jsr FRMNUM                              ; the limit
    lda FACSGN                              ; pack the sign into the mantissa
    ora #127
    and FACHO
    sta FACHO
    lda #<(LDFONE)
    ldy #>(LDFONE)
    sta INDEX1
    sty INDEX1+1
    jmp FORPSH                              ; push the limit and go on at LDFONE

;; Pushes the rest of FOR's entry: the step (1 when there is no STEP) and its sign, the variable's offset, its type
;; and FORTK, then falls into <NEWSTT>.
LDFONE:
    lda #<(FONE)
    ldy #>(FONE)
    ldx #0
    jsr MOVFM
    lda #STEPTK
    jsr TRYESC
    bne ONEON
    jsr CHRGET
    jsr FRMNUM                              ; the step

;; Pushes the step and its sign, then the variable's offset, type and FORTK.
ONEON:
    jsr SIGN
    jsr PUSHF
    lda FORPNT+1
    pha
    lda FORPNT
    pha
    lda TEMPFOR
    pha
    lda #FORTK
    pha

; ---------------------------------------------------------------------------------------------------------------------
; The statement fetcher
; ---------------------------------------------------------------------------------------------------------------------

;; The statement fetcher: runs the next statement, from where <TXTPTR> stands.
;;
;; On entry TXTPTR points at the terminator of the statement just run: a colon, or the zero that ends a line (for a
;; GOTO, the zero before the line's link). Anything else is a syntax error. In a program, <OLDTXT> and <OLDTXTB> take
;; TXTPTR, the place to go on from for CONT. At a zero, the next line's link is read at TXTPTR+1: a zero link ends the
;; program (or the direct line) at <READY>; otherwise the line number at TXTPTR+2 goes into <CURLIN> and TXTPTR moves
;; to TXTPTR+3, the number's high byte, so <CHRGET> reads the text's first byte. When the page reaches <MAXPG>,
;; TXTPTRB goes up by one and the page down by MAXPG-MINPG. CURLIN's high byte is $FF while a direct line runs.
;;
;; CONTROL-C (bit 6 of <KEYSTROK>) stops the program, and a key with ON KBD (bit 7) goes to its line, before the next
;; statement.
;; See: <GONE>, <NWSTT>, <GONE3>
NEWSTT:
    lda #0
    sta CMDFLG                              ; no RUN or CHAIN pending
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: BASIC's own prefix again
.endif
    tsx
    stx REMSTK                              ; the stack to go back to on an error
    lda FILNO+1                             ; output back to its usual place
    sta FILNO
    jsr CHRGOT
    bne SNERR1                              ; no terminator
    ldx CURLIN+1
    inx
    beq DIRCON                              ; a direct line: no CONT

;; Inherit: <NEWSTT>
;; Does not check for a terminator; RETURN, CONT and INPUT's retry come here.
NWSTT:
    lda TXTPTR
    ldy TXTPTR+1
    sta OLDTXT
    sty OLDTXT+1
    lda TXTPTRB
    sta OLDTXTB

;; Takes a pending CONTROL-C or key, then moves to the next statement, or the next line's at the end of a line.
DIRCON:
    bit KEYSTROK
    bvs ISCTRLC                             ; bit 6: CONTROL-C
    bmi ISAKEY                              ; bit 7: a key for ON KBD
    ldy #0
    lda (TXTPTR),Y
    bne GONE                                ; a colon: the next statement is on this line
    iny
    lda (TXTPTR),Y                          ; the next line's link
    clc
    beq INTERM                              ; zero: the program has ended
    iny
    lda (TXTPTR),Y
    sta CURLIN
    iny
    lda (TXTPTR),Y
    sta CURLIN+1
    tya
    adc TXTPTR                              ; TXTPTR to the number's high byte
    sta TXTPTR
    bcc CHKPGE
    inc TXTPTR+1

;; Brings TXTPTR's page back below <MAXPG>, moving it into the next bank.
CHKPGE:
    lda TXTPTR+1
    cmp #MAXPG
    bcc GONE
    inc TXTPTRB
    sbc #MAXPG-MINPG
    sta TXTPTR+1

;; Runs the statement after <TXTPTR>, tracing it first when TRACE is on.
;;
;; With TRACE, every statement of a program (not of a direct line) prints `#` and its line number and a space.
;; The statement's handler is called with <NEWRET> on the stack, which returns to NEWSTT.
;; In: TXTPTR = the byte before the statement, CURLIN = its line number
;; See: <GONE3>
GONE:
    tsx
    stx REMSTK
    bit TRFLAG
    bpl GOFORIT
    ldx CURLIN+1
    inx
    beq GOFORIT                             ; a direct line is not traced
    lda #'#'
    jsr OUTDO
    ldx CURLIN
    lda CURLIN+1
    jsr LINPRT
    jsr OUTSPC

;; Reads the statement's first byte and runs it.
GOFORIT:
    jsr CHRGET
    jsr GONE3
NEWRET = *-1                                ;; the return address GOFORIT's JSR pushes, back to NEWSTT
    jmp NEWSTT

;; Ends the statement with a syntax error.
SNERR1:
    jmp SNERR

;; Runs the ON KBD line for a key.
ISAKEY:
    jmp KEYHIT

;; Stops the program for CONTROL-C, through <ISCNTC>, which does not come back here.
ISCTRLC:
    jsr ISCNTC

;; Runs a statement: a token from END to NEW goes to its handler from <STMDSP>, anything else is a LET.
;;
;; The handler is reached through an RTS, after <CHRGET>, with the statement's next character in A and the flags set
;; as CHRGET sets them.
;; In: A = the statement's first byte, flags as <CHRGET> sets them
GONE3:
    beq ISCRTS                              ; an empty statement
; Carry is already set: CHRGET sets it for anything but a digit, and a digit is a syntax error, as it should be.
    sbc #ENDTK
    ldx #TEMPST                             ; no string temporaries in use
    stx TEMPPT
    bcc GLET                                ; not a token: a LET
    cmp #SCRATK-ENDTK+1
    bcs SNERR1                              ; a token that is not a statement
    asl
    tay
    lda STMDSP+1,Y
    pha
    lda STMDSP,Y
    pha                                     ; the handler's address, less one
    jmp CHRGET

;; Ends the program at a zero link, as END does.
;; In: carry = clear
INTERM:
    beq ENDCON

;; Runs a statement without a keyword as LET.
GLET:
    jmp LET

; ---------------------------------------------------------------------------------------------------------------------
; RESTORE, STOP, END, CONT and BYE
; ---------------------------------------------------------------------------------------------------------------------

;; The RESTORE statement: points <DATPTR> at the zero before the program, so READ starts at the first DATA again.
;;
;; The borrow out of the page goes through <FIXYX>, which only checks the top of the range: a program starting at the
;; start of page MINPG would leave DATPTR in page 1, below the usual range (the same byte, by the banks' overlap).
RESTOR:
    sec
    ldx TXTTABB
    lda TXTTAB
    sbc #1
    ldy TXTTAB+1
    bcs RESFIN
    dey
    jsr FIXYX

;; Sets <DATPTR>; READ comes here with where its data ended.
;; In: A, Y, X = the pointer (low, high, bank)
RESFIN:
    sta DATPTR
    stx DATPTRB
    sty DATPTR+1

;; An RTS for branches.
ISCRTS:
    rts

;; Stops the program for CONTROL-C, with BREAK, or goes to ON ERR's line with error 255.
;;
;; When the any-key flag is set too, or in a direct line, ON ERR is passed over.
;; See: <STOP2>, <HNDLERR>, <ISCNTC2>
ISCNTC:
    lda KEYSTROK

;; Inherit: <ISCNTC>
;; Takes the flags in A; INPUT comes here with 3 for a CONTROL-C typed at its prompt.
;; In: A = <KEYSTROK>'s flags
ISCNTC2:
    and #$BF                                ; CONTROL-C taken
    sta KEYSTROK
    ldx #$FF                                ; the break's error number
    cmp #$80
    bcs ISRESET
    ldy CURLIN+1
    iny
    beq ISRESET                             ; a direct line: no ON ERR
    dey
    sty ERRLIN+1
    stx ERRNUM
    ldy CURLIN
    sty ERRLIN
    bit ERRFLG                              ; ON ERR on?
    bpl *+5
    jmp HNDLERR

;; Stops with BREAK, printing to the console.
ISRESET:
    stx FILNO
    sec
    bcs STOP2                               ; always

;; The END statement: stops the program without a message.
END:
    clc

;; The STOP statement: stops the program with BREAK.
;; In: A = the character after the keyword, zero = set for a terminator, carry = set for BREAK (CHRGET sets it after
;;   STOP; END clears it)
STOP:
    bne CONTRT                              ; not a terminator: NEWSTT gives the syntax error

;; Stops the program: keeps <TXTPTR> and <CURLIN> in <OLDTXT> and <OLDLIN> for CONT (not for a direct line), then
;; goes to <READY>, with BREAK and its line first when carry is set.
;; In: carry = set to print BREAK
STOP2:
    lda #255
    sta FILNO                               ; output to the console
    sta FILNO+1
    lda TXTPTR
    ldy TXTPTR+1
    ldx CURLIN+1
    inx
    beq DIRIS
    sta OLDTXT
    sty OLDTXT+1
    lda TXTPTRB
    sta OLDTXTB
    lda CURLIN
    ldy CURLIN+1
    sta OLDLIN
    sty OLDLIN+1

;; Drops the return address to <NEWSTT>.
DIRIS:
    pla
    pla

;; Goes to <READY>, through BREAK's message when carry is set.
;; In: carry = set to print BREAK
ENDCON:
    bcc GORDY
    brk                                     ; empty the type-ahead buffer
    .byte SDCNT
    .word DFLUSH
    jsr CRDO
    lda #<(BRKTXT)
    ldx #0
    ldy #>(BRKTXT)
    jmp ERRFIN

;; Goes to <READY>.
GORDY:
    jmp READY

;; The CONT statement: goes on from where STOP, END, CONTROL-C or an error stopped the program.
;;
;; It runs only in a direct line (in a program it does nothing). It clears <KEYSTROK>, sets the any-key event again,
;; and goes on at <OLDTXT> on line <OLDLIN>. A zero <OLDTXTB> means there is nothing to go on with: CAN'T CONTINUE.
;; Entering or changing a line clears it.
;; In: zero = set for a terminator after CONT
;; See: <STOP2>, <NWSTT>
CONT:
    bne CONTRT
    ldx CURLIN+1
    inx
    bne CONTRT                              ; in a program: nothing
    stx KEYSTROK
    brk
    .byte SDCNT
    .word DKBD
    ldx #ERRCN
    ldy OLDTXTB
    bne *+5
    jmp ERROR                               ; nothing to continue
    lda OLDTXT
    sta TXTPTR
    sty TXTPTRB
    lda OLDTXT+1
    sta TXTPTR+1
    lda OLDLIN
    ldy OLDLIN+1
    sta CURLIN
    sty CURLIN+1
    pla                                     ; NEWSTT's return address
    pla
    jmp NWSTT

;; An RTS for the statements' checks.
CONTRT:
    rts

;; The BYE statement: closes the files and restarts the Apple III through SOS's COLD_START.
;;
;; Each call's parameter list is the call itself, starting at its BRK, a zero: no parameters. COLD_START takes none;
;; CLOSE wants one, so SOS refuses that call, which matters little, as <CLSALL> has closed BASIC's files.
COLD:
    jsr CHRGOT
    beq COLD1
    jmp SNERR

;; Closes the files and restarts.
COLD1:
    jsr CLSALL
    brk
    .byte SCLS
    .word *-2
    brk
    .byte CLDSTRT
    .word *-2                               ; never returns

; ---------------------------------------------------------------------------------------------------------------------
; RUN and the GOSUB entry
; ---------------------------------------------------------------------------------------------------------------------

;; The RUN statement: runs the program from its start, from a line (`RUN n` or `RUN ,n`), or loads a program first.
;;
;; Each clears the variables and the stack. `RUN pathname` loads the program, turns TRACE off and runs it through
;; <FRUN>.
;; In: A = the character after RUN, flags as <CHRGOT> sets them
;; See: <RUNC>, <RUNC2>
RUN:
    bne *+5
    jmp RUNC                                ; RUN alone: from the start
    bcc RUNL                                ; a digit: from that line
    cmp #$2C
    beq RUNL2
    jsr LDRUN                               ; a pathname
    lda #1
    sta RNFLG
    jsr DOLD2
    jsr CLEARC
.if VERSION >= 130
    jsr CNVTPFX1                            ; 1.3: name the program's prefix by its volume
.endif
    lsr TRFLAG                              ; TRACE off
    jmp FRUN

;; Runs from the line after RUN's comma.
RUNL2:
    jsr CHKCOM

;; Clears the variables and the stack (<CLEARC> resets it, taking NEWSTT's return address), then goes to the line.
RUNL:
    jsr CLEARC
    jsr RUNC2
    jmp NEWSTT

;; Puts a GOSUB entry on the stack, below the caller's return address and the one above it, after checking for room.
;;
;; The entry is six bytes, from the top of the stack down: GOSUTK, the line number (low, high), and the text pointer
;; as an offset from <TXTTAB> (bank, high, low). For GOSUB, the second return address is <NEWRET>, so the entry goes
;; under it; FOR and ON KBD call through <PSHTXT3> and <PSHTXT4>, so the entry goes at their own level.
;; In: TXTPTR = where RETURN goes on from, CURLIN = the line
;; Uses: A, X, Y, INDEX, PNTSAV
;; See: <RETURN>, <FOR>
PSHTXT:
    lda #4
    jsr GETSTK

;; Inherit: <PSHTXT>
;; Does not check for room.
PSHTXT2:
    pla                                     ; the return address
    sta PNTSAV
    pla
    tax
    pla                                     ; and the one above it
    sta INDEX
    pla
    sta INDEX+1
    sec                                     ; TXTPTR, less TXTTAB
    lda TXTPTR
    sbc TXTTAB
    pha
    lda TXTPTR+1
    sbc TXTTAB+1
    ldy TXTPTRB
    jsr FIXSBC
    pha
    tya
    sbc TXTTABB
    pha
    lda CURLIN+1
    pha
    lda CURLIN
    pha
    lda #GOSUTK
    pha
    lda INDEX+1                             ; the return addresses back on top
    pha
    lda INDEX
    pha
    txa
    pha
    lda PNTSAV
    pha

;; An RTS for branches.
PSHTRT:
    rts

;; Pushes a GOSUB entry at the caller's own level, without checking for room; FOR uses it.
;; See: <PSHTXT2>
PSHTXT3:
    jsr PSHTXT2
    rts

;; Pushes a GOSUB entry at the caller's own level; ON KBD uses it.
;; See: <PSHTXT>, <KEYHIT>
PSHTXT4:
    jsr PSHTXT
    rts
