; B3INPUF: INPUT, GET and READ, which share one loop over their variables; NEXT; the type checks FRMNUM, CHKNUM and
; CHKSTR; and the first half of FRMEVL, the formula evaluator, up to taking an operator off its stack (B3EvalG.asm
; goes on from there).
;
; INPUT, GET and READ tell themselves apart by INPFLG: 0 for INPUT, $40 for GET, $98 for READ. Each keeps the place
; in its data in INPPTR (with its bank in INPPTRB), pointing at the separator before the next item, and the place in
; the statement's variable list in VARTXT while TXTPTR reads the data.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; INPUT, GET and READ
; ---------------------------------------------------------------------------------------------------------------------

;; Handles a data item that does not end in a comma or the end: INPUT asks again, READ and GET end with SYNTAX ERROR.
;;
;; READ's error names the DATA statement's line, from <DATLIN>.
TRMNOK:
    lda INPFLG
    beq TRMNO1                              ; INPUT
    bpl SNERR4                              ; GET
    lda DATLIN
    ldy DATLIN+1
    sta CURLIN
    sty CURLIN+1

;; Ends the statement with a syntax error.
SNERR4:
    jmp SNERR

;; Drops the byte <NUMINS> pushed, then asks again.
TRMNO2:
    pla

;; Asks again for INPUT's line: INPUT# from a file ends with TYPE MISMATCH, and with ON ERR the program goes to its line
;; with error 254.
TRMNO1:
    bit FILNO                               ; from the console?
    bmi *+5
    jmp TMERR
    bit ERRFLG                              ; ON ERR on?
    bpl DOAGIN
    ldy CURLIN+1
    iny
    beq DOAGIN
    ldx #254                                ; the error for a bad answer to INPUT
    jmp ERROR

;; Prints ?REENTER and runs the INPUT statement again from its start.
DOAGIN:
    lda #<(TRYAGN)
    ldx #0
    ldy #>(TRYAGN)
    jsr STROUT
    jsr DOAG2
    pla                                     ; NEWSTT's return address: NWSTT, which
    pla                                     ; needs no terminator, runs INPUT again
    jmp NWSTT

;; Points <TXTPTR> back at the statement's start, from <OLDTXT>.
DOAG2:
    lda OLDTXT
    ldy OLDTXT+1
    ldx OLDTXTB
    stx TXTPTRB
    sta TXTPTR
    sty TXTPTR+1

;; An RTS for INPUT.
GTRTS:
    rts

;; The GET statement: reads one key, without echo, into each variable of its list, from the console, the EXEC file
;; while EXEC runs, or a file after `#n;`.
;;
;; A numeric variable takes the key's value as VAL would give it.
;; In: A = the character after GET, flags as <CHRGOT> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <DOAGET>, <INLP2>
GET:
    jsr ERRDIR
    ldx INFLNO                              ; EXEC's file, if it runs
    bne *+5
    ldx SLINTB+1                            ; else the console's
    stx GETREF
    cmp #'#'
    bne GOTREF
    jsr GTFLNO
    sta GETREF
    jsr CHKSMC

;; Starts the variable loop with no data, the zero at BUF+1, so each variable reads a key.
GOTREF:
    ldx #<(BUF+1)
    ldy #>(BUF+1)
    lda #$80                                ; no terminators
    sta QUOTE
    lda #0
    sta YSAVE                               ; the data's bank byte
    sta BUF+1
    sta BUF
    lda #64                                 ; INPFLG for GET
    jmp INPCO1

;; The INPUT statement: prints a prompt, reads a line from the console, or from a file after `#n;`, and assigns its
;; items to the variables of the list.
;;
;; The prompt is the string given, or `?`. Items are separated by commas; the last variable, when a string, takes the
;; rest of the line, commas and all. When the line runs out, `??` asks for more. CONTROL-C at the start of the line
;; stops the program, where CONT runs the INPUT again.
;; In: A = the character after INPUT, flags as <CHRGOT> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <INLOOP>, <TRMNOK>, <VAREND>
INPUT:
    jsr ERRDIR
    jsr CHRGOT
    cmp #34                                 ; a prompt?
    bne NOTQT0
    jsr STRTXT
    jsr CHRGOT
    cmp #$2C
    beq INPAOK
    lda #59                                 ; not a comma: it must be a semicolon

;; Checks the comma or semicolon after the prompt, prints the prompt, and reads the line.
INPAOK:
    jsr SYNCHR
    jsr STRPRT
    jmp NOTQTII

;; Takes INPUT# n; from a file, or prints the `?` prompt.
NOTQT0:
    cmp #'#'
    bne NOTQTI
    ror IOFLG
    jsr FILNUM
    jsr CHRGOT
    cmp #$3B
    bne GTRTS                               ; no semicolon: NEWSTT gives the syntax error
    lda SVFLNO
    sta FILNO
    jsr CHRGET
    jsr DSKLIN
    lda #44                                 ; a comma before the line, as the separator
    sta BUF-1
    jmp INPCON

;; Prints the `?` prompt.
NOTQTI:
    jsr OUTQST

;; Reads INPUT's line from the console into <BUF>, with a comma before it.
NOTQTII:
    ldx #0
    stx QUOTE                               ; commas end items
    dex
    stx FILNO                               ; from the console
    lda #44
    sta BUF-1
    jsr INLIN
    lda BUF
    cmp #$03                                ; CONTROL-C at the start?
    bne INPCON
    jsr DOAG2                               ; so CONT runs the INPUT again
    lda #3
    jmp ISCNTC2

;; Prints `?` and reads a line from the console, so a second `?` follows INPUT's.
QINLIN:
    jsr OUTQST
    jmp INLIN

;; The READ statement: assigns the items of the program's DATA statements to the variables of the list, from
;; <DATPTR> on; READ# reads from a file instead.
;; In: A = the character after READ, flags as <CHRGOT> sets them
;; Errors: OUT OF DATA when the DATA statements run out, SYNTAX ERROR for a bad item (on the DATA's line)
;; See: <DATLOP>, <DREAD>, <RESTOR>
READ:
    ldx DATPTRB
    stx YSAVE
    ldx DATPTR
    ldy DATPTR+1
    cmp #'#'
    bne READON
    jmp DREAD

;; Starts READ's variable loop.
READON:
    lda #0
    sta QUOTE
    lda #$98                                ; INPFLG for READ
    .byte 44                                ; BIT abs, which skips the next LDA

;; Starts INPUT's variable loop.
INPCON:
    lda #0

;; Starts the variable loop with the flag and the data's place.
;; In: A = INPFLG's value, X, Y = the data's place (low, high), YSAVE = its bank
INPCO1:
    sta INPFLG
    stx INPPTR
    ldx YSAVE
    stx INPPTRB
    sty INPPTR+1

;; Takes the next variable of the list; for INPUT and GET, the last one takes the data with no terminators.
INLOOP:
    jsr MYPTRGET                            ; the variable's address in FORPNT
    bit INPFLG
    bmi INLP2                               ; READ
    jsr CHRGOT
    bne INLP2
    lda #$80                                ; the last variable: no terminators
    sta QUOTE

;; Moves <TXTPTR> to the data, keeping the list's place in <VARTXT>, and takes the next item; at the end of the data,
;; GET reads a key, READ finds the next DATA statement, and INPUT reads another line.
INLP2:
    jsr SVTXT
    ldx INPPTR
    ldy INPPTR+1
    lda INPPTRB
    sta TXTPTRB
    stx TXTPTR
    sty TXTPTR+1
    ldy #0
    lda (TXTPTR),Y                          ; the separator, or the data's end
    bne DATBK1
    bit INPFLG
    bvc QDATA
    jsr DOAGET                              ; GET: a key into KEYSAVE
    ldx #<(KEYSAVE)
    ldy #>(KEYSAVE)
    stx STRNG1
    sty STRNG1+1
    lda #0
    sta STRNG1B
    lda VALTYP
    pha
    ldy RNDGOT                              ; the count read: one
    jsr STRCP
    pla
    sta VALTYP
    jsr CHANGTP
    jsr LETP2
    jmp STRDN2

;; Gets more data: READ looks for the next DATA, INPUT reads another line from its file or the console.
QDATA:
    bmi DTLP1                               ; READ
    bit FILNO
    bmi QD11                                ; the console
    jsr DSKLIN
    jmp DATBK

;; Asks for more with `??`.
QD11:
    jsr OUTQST
    jsr QINLIN

;; Points <TXTPTR> at the new line.
;; In: X, Y = the line's place (low, high)
DATBK:
    stx TXTPTR
    lda INPPTRB
    sta TXTPTRB
    sty TXTPTR+1

;; Takes the item after the separator: a number, or a string.
DATBK1:
    ldy #1
    jsr ADDON                               ; past the separator
    bit VALTYP
    bpl NUMINS                              ; a number
    bit INPFLG
    bvc SETQUT
    inx                                     ; GET (never here: its data stays the zero)
    stx TXTPTR

;; Takes the string up to the data's end, with no terminators.
NOTERMS:
    lda #0
    sta CHARAC
    beq RESETC

;; Goes on looking for READ's next DATA statement.
DTLP1:
    jmp DATLOP

;; Chooses the string's terminators: a quote for a quoted string, a comma otherwise, none for the last variable of
;; INPUT.
SETQUT:
    ldy #0
    lda (TXTPTR),Y
    sta CHARAC
    bit QUOTE
    bmi NOTERMS
    cmp #34                                 ; a quote: the string is inside it
    beq NOWGET
    lda #44
    sta CHARAC

;; Starts the string at <TXTPTR> itself.
RESETC:
    clc

;; Makes a string of the item and assigns it.
;; In: A = ENDCHR's terminator, carry = set to start after TXTPTR (past a quote)
NOWGET:
    sta ENDCHR
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    adc #0
    bcc NOWGE1
    iny
    cpy #MAXPG
    bcc *+5
    inx
    ldy #MINPG

;; Makes the string, moves TXTPTR past it and assigns it.
NOWGE1:
    jsr STRLT2
    jsr ST2TXT
    jsr INPCOM
    jmp STRDN2

;; Takes a number: an empty INPUT line, or an INPUT item with no digits, asks again.
;; In: overflow = set for a long integer, as VALTYP's BIT sets it
NUMINS:
    pha
    lda BUF
    beq MAYBAD                              ; an empty line

;; Reads the number, a long integer through <LINP> or a real through <FIN>.
NUMINS2:
    pla
    bvs NUMBCD                              ; a long integer
    jsr FIN
    bit INPFLG
    bvs NUMINS3                             ; GET
    bmi NUMINS3                             ; READ
    pha
    lda ANYNUM
    bmi MAYBAD                              ; no digits
    pla

;; Stores the number as a real or an integer, as the variable is.
NUMINS3:
    lda INTFLG
    jsr QINTGR

;; Checks what ends the item, a terminator or a comma, then keeps the data's place and takes the next variable.
STRDN2:
    jsr CHRGOT
    beq TRMOK
    cmp #44                                 ; a comma?
    beq *+5
    jmp TRMNOK

;; Keeps the data's place in <INPPTR>, goes back to the list, and takes the next variable or ends.
TRMOK:
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    sta INPPTR
    stx INPPTRB
    sty INPPTR+1
    jsr RSTTXT
    jsr CHRGOT
    beq VAREND
    jsr CHKCOM
    jmp INLOOP

;; Reads a long integer and stores it.
NUMBCD:
    jsr LINP
    jsr BMOVF1
    jmp STRDN2

;; Handles a missing number: INPUT asks again; READ and GET go on to read it.
;;
;; The empty-line test reads BUF even for READ, whose data is elsewhere, so READ comes here for nothing at times.
MAYBAD:
    lsr ANYNUM
    lda INPFLG
    bne NUMINS2
    jmp TRMNO2

;; Looks for the next DATA statement, from <TXTPTR>, keeping its line number in <DATLIN>.
;; Errors: OUT OF DATA at the program's end
DATLOP:
    jsr DATAN                               ; the statement's end
    iny
    tax
    bne NOWLIN                              ; a colon: the next statement is on this line
    ldx #ERROD
    lda (TXTPTR),Y                          ; the next line's link
    bne *+5
    jmp ERROR
    iny
    lda (TXTPTR),Y                          ; the line number's low byte
    sta DATLIN
    iny
    lda (TXTPTR),Y                          ; and its high byte
    iny
    sta DATLIN+1

;; Checks the statement's first byte for DATA, and takes its first item when it is.
NOWLIN:
    lda (TXTPTR),Y
    tax
    jsr ADDON
    cpx #DATATK
    bne DATLOP
    jsr CHRGET
    jsr DECTPT
    jmp DATBK1

;; Ends the variable loop: READ keeps its place in <DATPTR>; INPUT and GET check that the data is used up.
;;
;; Data left over prints ?EXTRA IGNORED through <ERRFIN>, which ends at <READY>; with ON ERR the program goes to its
;; line with error 253 instead.
VAREND:
    lda #0
    sta QUOTE
    lda INPPTR
    ldy INPPTR+1
    ldx INPPTRB
    bit INPFLG
    bpl VARY0
    jmp RESFIN                              ; READ

;; Checks for data left over.
VARY0:
    ldy #0
    lda (INPPTR),Y                          ; the end should be a zero
    beq INPRTS
    jsr INPRTS
    bit ERRFLG                              ; ON ERR on?
    bpl INPVAR0
    ldx #253                                ; the error for data left over
    ldy CURLIN+1
    iny
    beq INPVAR0
    jmp ERROR

;; Prints ?EXTRA IGNORED and the line.
INPVAR0:
    lda #<(EXIGNT)
    ldx #0
    ldy #>(EXIGNT)
    jmp ERRFIN

;; Sends output back to its usual place, after INPUT#.
INPRTS:
    lda FILNO+1
    sta FILNO
    rts

;; Keeps <TXTPTR> in <VARTXT>.
;; Uses: A, X, Y
;; See: <RSTTXT>
SVTXT:
    lda TXTPTR
    ldy TXTPTR+1
    ldx TXTPTRB
    stx VARTXTB
    sta VARTXT
    sty VARTXT+1
    rts

;; Sets <TXTPTR> back from <VARTXT>.
;; Uses: A
;; See: <SVTXT>
RSTTXT:
    lda VARTXT
    sta TXTPTR
    lda VARTXT+1
    sta TXTPTR+1
    lda VARTXTB
    sta TXTPTRB
    rts

;; The message for data left over, ending in a zero.
EXIGNT:
    .byte "?EXTRA IGNORED"
    .byte 0

;; The message asking INPUT's line again, ending in a zero.
TRYAGN:
    .byte "?REENTER"
    .byte 13, 10, 0

;; Turns GET's string into the variable's type: a real through <VAL>, a long integer through <STR2LNG>.
;; In: VALTYP = the variable's type
CHANGTP:
    bit VALTYP
    bmi ISSTRIN
    bvs ISLONG
    jmp VAL

;; An RTS: a string variable takes the string as it is.
ISSTRIN:
    rts

;; Turns the string into a long integer.
ISLONG:
    jmp STR2LNG

; ---------------------------------------------------------------------------------------------------------------------
; NEXT
; ---------------------------------------------------------------------------------------------------------------------

;; The NEXT statement: adds the step to the loop's variable, and goes back after the FOR unless the variable has passed
;; the limit.
;;
;; NEXT alone takes the newest FOR entry; NEXT with variables takes each one's entry in turn, dropping the newer FOR
;; entries above it. The loop ends when the comparison of the new value with the limit (1 for greater, 0 for equal, $FF
;; for less) equals the step's sign; then the entry comes off the stack. See <FOR> for the entry's layout.
;; In: A = the character after NEXT, zero = set for a terminator
;; Errors: NEXT WITHOUT FOR when there is no entry for the variable
;; See: <FOR>, <FNDFOR>
NEXT:
    bne GETFOR
    ldy #0
    sty FORPNT+1
    sty FORPNT
    beq STXFOR                              ; FORPNT zero: the newest entry

;; Finds the loop variable's offset and type, the key of its FOR entry.
GETFOR:
    jsr MYPTRGET
    jsr RELPTR
    lda ISARA
    rol
    lda INTFLG
    adc #0                                  ; an array element into bit 0
    sta TEMPFOR
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY
    sta FORPNT+1

;; Finds the FOR entry.
STXFOR:
    jsr FNDFOR
    beq HAVFOR
    ldx #ERRNF
    jmp ERROR

;; Cuts the stack to the entry, then adds the step to the variable's value.
;; In: X = the entry's place on the stack
HAVFOR:
    lda #$FE                                ; the packed offset's bank byte
    sta FORPNTB
    txs
    txa
    clc
    adc #5                                  ; the step, at the entry's fifth byte
    tay
    adc #6
    sta INDEX2                              ; the limit, for FCOMPN
    tya
    ldy #1                                  ; in page 1
    ldx #0
    jsr MOVFM                               ; the step into the FAC
    tsx
    lda 257+7+2,X                           ; the step's sign
    sta FACSGN
    jsr RELPTR                              ; the offset back into the variable's address
    bit INTFLG
    bpl HAVFLT
    jsr MOVAF                               ; an integer: the step into ARG
    lda FORPNT
    sta FACMO
    lda FORPNT+1
    sta FACMO+1
    lda FORPNTB
    sta FACMOB
    jsr GOOO2                               ; and the variable into the FAC
    jmp HAVSUM

;; Takes a real variable's value into ARG.
HAVFLT:
    ldy FORPNT+1
    ldx FORPNTB
    lda FORPNT
    jsr CONUPK

;; Adds, compares with the limit, stores the new value, and loops or ends.
HAVSUM:
    lda ARGSGN
    eor FACSGN
    sta ARISGN
    lda FACEXP                              ; zero set for a zero FAC
    jsr FADDT
    ldy #1
    jsr FCOMPN                              ; with the limit
    pha
    bit INTFLG
    jsr QINTGR                              ; store it as LET does
    pla
    tsx
    sec
    sbc 257+7+2,X                           ; less the step's sign
    beq LOOPDN                              ; equal: the loop is done
    lda 257+12+3,X
    sta CURLIN
    lda 257+13+3,X
    sta CURLIN+1
    lda 257+16+3,X                          ; the FOR statement's end, an offset from TXTTAB
    clc
    adc TXTTAB
    sta TXTPTR
    lda 257+15+3,X
    adc TXTTAB+1
    ldy TXTTABB
    jsr FIXADC
    sta TXTPTR+1
    tya
    adc 257+14+3,X
    sta TXTPTRB

;; Goes on with the statement after the FOR.
NEWSGO:
    jmp NEWSTT

;; Takes the entry off the stack; after a comma, goes on with the next variable.
;;
;; The JSR to GETFOR stands in for <NEWSTT>'s return address, which <FNDFOR> passes over; GETFOR does not return.
;; In: carry = set
LOOPDN:
    txa
    adc #16+3                               ; FORSIZ, with the carry
    tax
    txs
    jsr CHRGOT
    cmp #44                                 ; a comma?
    bne NEWSGO
    jsr CHRGET
    jsr GETFOR

; ---------------------------------------------------------------------------------------------------------------------
; Type checks
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a numeric formula.
;; In: TXTPTR = the formula's first character
;; Out: FAC = the value
;; Errors: TYPE MISMATCH for a string or a long integer
;; See: <DOPAR>, <CHKNUM>
FRMNUM:
    lda #0
    sta VALTYP                              ; a real wanted
    jsr DOPAR

;; Checks that the value is a number: a string or a long integer is a TYPE MISMATCH.
;; Uses: carry
;; See: <CHKSTR>
CHKNUM:
    clc
    .byte 36                                ; BIT zp, which skips CHKSTR's SEC

;; Checks that the value is a string: anything else is a TYPE MISMATCH.
;; Uses: carry
;; See: <CHKNUM>
CHKSTR:
    sec
    bit VALTYP
    bmi DOCSTR
    bvs CHKERR                              ; a long integer passes neither
    bcs CHKERR

;; An RTS for the checks.
CHKOK:
    rts
    bvc CHKERR                              ; never reached

;; Passes a string when a string is wanted.
DOCSTR:
    bcs CHKOK

;; Ends the statement with TYPE MISMATCH.
CHKERR:
    ldx #ERRTM
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; The formula evaluator
;
; FRMEVL keeps two stacks. The verb stack, VRBSTK, holds two bytes for each pending operator: its number, then its
; left operand's type (bits 7-6) with its precedence (bits 5-0); VRBPT is the index past the top. A zero precedence
; at the bottom, or where DOPAR starts a formula in parentheses, stops operators from below. The noun stack, NOUNSTK,
; holds each pending left operand, nine bytes: FACMOB, then the eight bytes from FACEXP; NOUNPT is the index of the
; top's last byte.
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a formula: values joined by operators, taken in order of precedence.
;;
;; The precedences, high to low: ^ (8); * / DIV MOD (6); + - (5); the relational operators (4); AND (3); OR (2).
;; A relational operator is any of the characters less-than, equals and greater-than, each at most once, combined as
;; bits: greater-than 1, equals 2, less-than 4.
;; In: TXTPTR = the formula's first character, VALTYP = the type wanted ($20 for any)
;; Out: the FAC = the value, VALTYP = its type, TXTPTR = the character after the formula
;; Errors: TYPE MISMATCH when the result is not the type wanted, FORMULA TOO COMPLEX past 15 pending operators,
;;   SYNTAX ERROR for a relational operator given twice
;; See: <EVAL>, <DOPAR>, <DOLAST>
FRMEVL:
    lda #0
    sta NAMPNT
    sta NOUNPT
    sta VRBSTK+1                            ; the bottom's zero precedence
    sta STRFLG
    sta INTFLG
    lda #2
    sta VRBPT

;; Inherit: <FRMEVL>
;; Keeps both stacks as they are, so a formula in parentheses (from <DOPAR>) stacks on the one outside it.
FRMEVL1A:
    lda VALTYP                              ; the type wanted, checked at the end
    pha
    jsr DECTPT                              ; back one, for EVAL's CHRGET

;; Takes a value, then the operator after it: a character of <OPTAB>, or an escape token's second byte; anything else
;; ends the formula.
FRMEVL1:
    jsr EVAL
EVALRET = *-1                               ;; the return address FRMEVL1's JSR pushes, which Invoke.asm checks for
    jsr CHRGOT
    ldy #0
    ldx #NUMOPS
    cmp #$80
    bcc FNDOPR                              ; a character
    cmp #$FF
    bne NOOPR                               ; another token: not an operator
    iny
    lda (TXTPTR),Y                          ; the escape token's second byte

;; Looks the operator up in <OPTAB>, from its end.
FNDOPR:
    cmp OPTAB-1,X
    beq FOUNDOP
    dex
    bne FNDOPR

;; Takes the end of the formula as the operator.
NOOPR:
    ldx #NUMOPS
    dey

;; Moves past the escape token's $FF, and gathers the relational operators into DOMASK.
;; In: X = the operator's place in OPTAB, Y = 1 for an escape token
FOUNDOP:
    pha
    clc
    txa
    adc #RELNOT                             ; past the combined relational operators' numbers
    tax
    pla
    dey
    bmi FOP2
    jsr CHRGET                              ; the escape token's $FF

;; Takes a relational operator's characters, or goes on with another operator.
FOP2:
    cpx #RELOPS+1
    bcs NOTREL
    ldx #0
    stx DOMASK

;; Adds a relational character's bit to DOMASK; the same one twice is a syntax error.
GTRLOP:
    cmp #'>'+1
    bcs NOGTRL
    cmp #'<'
    bcc NOGTRL
    eor #$3F                                ; > 1, = 2, < 3
    cmp #3
    adc #0                                  ; and < 4
    eor DOMASK
    cmp DOMASK                              ; the bit must be new
    bcc SNERR5
    sta DOMASK
    jsr CHRGET
    jmp GTRLOP

;; Ends the relational operator: its bits are its number.
NOGTRL:
    jsr DECTPT
    lda DOMASK

;; Goes on with the operator in A; B3EvalG.asm comes back here after doing one.
FRMEVLZ:
    tax

;; Does the pending operator first when its precedence is at least the new one's; otherwise pushes the new one and its
;; left operand, and takes the next value.
;; In: X = the operator's number
NOTREL:
    ldy VRBPT
    lda VRBSTK-1,Y
    and #$3F                                ; the pending operator's precedence
    cmp PRECTB-1,X
    bcs DOLAST
    lda VALTYP
    and #$C0
    ora PRECTB-1,X
    sta VRBSTK+1,Y                          ; type and precedence
    txa
    sta VRBSTK,Y                            ; the operator
    iny
    iny
    cmp #ENDOP
    bne NT1
    lda VRBSTK-3,Y                          ; the formula's end over the bottom's zero: done
    beq EXPRDN2

;; Keeps the verb stack's new top, unless it has grown too deep.
NT1:
    sty VRBPT
    cpy #$20
    bcc STKOK
    jmp CMPLXERR

;; Pushes the FAC on the noun stack, nine bytes.
STKOK:
    lda NOUNPT
    adc #9                                  ; carry is clear
    sta NOUNPT
    tay
    ldx #7

;; Copies the FAC's eight bytes, then FACMOB under them.
PSHFAC:
    lda FACEXP,X
    sta NOUNSTK-1,Y
    dey
    dex
    bpl PSHFAC
    lda FACMOB
    sta NOUNSTK-1,Y
    jmp FRMEVL1

;; Ends the statement with a syntax error.
SNERR5:
    jmp SNERR

;; Ends the formula, checking its type against the one wanted.
EXPRDN2:
    pla                                     ; the type wanted
    cmp #$20
    beq EXPRDN3                             ; any
    eor VALTYP
    bne CANTFIX

;; An RTS for FRMEVL.
EXPRDN3:
    rts

;; Does the pending operator: pulls its left operand off the noun stack into ARG and the operator off the verb stack,
;; checking that the two operands' types agree; B3EvalG.asm goes on to do it.
;; In: X = the new operator, carry = set
;; Errors: TYPE MISMATCH when the operands' types differ
DOLAST:
    txa
    pha                                     ; the new operator, for later
    lda NOUNPT
    tay
    sbc #9
    sta NOUNPT
    ldx #8

;; Copies the eight bytes into ARG, then FACMOB's byte into ARGMOB.
PLLARG:
    lda NOUNSTK-1,Y
    sta ARG-1,X
    dey
    dex
    bne PLLARG
    lda NOUNSTK-1,Y
    sta ARGMOB
    ldy VRBPT
    dey
    dey
    sty VRBPT
    lda VRBSTK+1,Y
    and #$C0                                ; the left operand's type
    sta TEMP
    lda VALTYP
    and #$C0
    eor TEMP
    beq GETOP

;; Ends the statement with TYPE MISMATCH.
CANTFIX:
    jmp CHKERR

;; Takes the operator's number into A and DOMASK, for B3EvalG.asm's dispatch.
GETOP:
    lda VRBSTK,Y
    sta DOMASK
