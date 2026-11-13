; B3EVALG: the second half of the formula evaluator. The end of FRMEVL's operator step, EVAL for a single value
; (a constant, a variable, a string literal, a function, a reserved-word value, NOT, unary minus or a formula in
; parentheses), the syntax checks such as CHKCOM, the function dispatch, AND and OR, and the relational operators
; for numbers and strings.
;
; As the evaluator holds them, VALTYP is 0 for a real, $40 for a long integer and $FF for a string; $20 before a
; formula asks for any type. A real or an integer variable's value is a real in the FAC, unpacked; a long integer
; is eight bytes from FAC, two's complement, high byte first; a string is a pointer to its descriptor in FACMO,
; FACMO+1 and FACMOB.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; FRMEVL's operator step, continued
; ---------------------------------------------------------------------------------------------------------------------

; FRMEVL's DOLAST, in B3InpuF.asm, has the operator in A and its relational bits in DOMASK. Each relational operator
; maps to the first dispatch entry, the others to an entry each; a long integer's entries follow the reals' in
; OPDSPT, NUMDSP bytes on.
    sec
    sbc #6
    cmp #1
    bpl *+4
    lda #1
    asl
    tax
    bit VALTYP                              ; a string or a long integer needs more care
    bmi ASTRNG
    clc
    bvc NOTDBLP                             ; a real
    adc #NUMDSP                             ; a long integer: use the long-integer entries
    tax
    bcc RDY2GO
NOTDBLP:
    lda ARGSGN                              ; the sign of a product or quotient
    eor FACSGN
    sta ARISGN
RDY2GO:
    lda OPDSPT-2,X
    sta JMPER+1
    lda OPDSPT-1,X
    sta JMPER+2
    lda FACEXP                              ; with zero set for a zero FAC
    jsr JMPER

;; Pulls the next operator back off the stack and goes on with the formula in <FRMEVL>.
FRMEV3:
    pla
    jmp FRMEVLZ

;; Takes a binary operator on two strings: + concatenates them and a relational operator compares them; any other is
;; a syntax error.
;; See: <CONCAT>, <DOREL>
ASTRNG:
    cmp #NUMDSP                             ; +?
    beq PLUSOK
    cmp #2*RELNUM                           ; a relational operator?
    beq NOTDBLP

;; Ends the statement with a syntax error.
EVALER:
    jmp SNERR

;; Concatenates the two strings, then goes on with the formula.
;; See: <CONCAT>
PLUSOK:
    jsr CONCAT
    jmp FRMEV3

; ---------------------------------------------------------------------------------------------------------------------
; One value
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates one value from the program text into the <FAC>: a number, a string, a variable, a function's result, or a
;; formula in parentheses.
;;
;; A digit or a period starts a constant, which is read as a long integer when <VALTYP> asks for one (or for a string,
;; which gives a type mismatch later), and as a real otherwise.
;; In: TXTPTR = the character before the value, VALTYP = the type the formula wants
;; Out: FAC = the value, VALTYP = its type, TXTPTR = the value's last character
;; See: <FRMEVL>, <ISVAR>, <ISFUN>
EVAL:
    jsr CHRGET
    bcs EVAL1                               ; not a digit

;; Reads a numeric constant: a long integer with <LINP> when <VALTYP> is above $20, or a real with <FIN>.
ACONSTNT:
    lda VALTYP
    cmp #$21
    bcc RLBNY
    jmp LINP

;; Reads a real constant with <FIN>, ending the statement with a syntax error when it has no digits.
RLBNY:
    lda #0
    sta VALTYP
    jsr FIN
    bit ANYNUM                              ; $FF when FIN found no digits
    bmi EVALER
    rts

;; Takes a value that does not start with a digit: an escape token, a reserved word, a variable, a period, a plus, a
;; string literal, a minus or an opening parenthesis.
EVAL1:
    cmp #$FF                                ; an escape token: a function, FN or NOT
    beq PARC22
    cmp #$80                                ; a reserved word
    bcs PARC23
    jsr ISLETC
    bcc NOVAR
    jmp ISVAR

;; Takes a value that is not a variable: a constant that starts with a period, a unary plus, which is skipped, a
;; string literal, or <EVAL3>'s minus and parenthesis.
NOVAR:
    cmp #'.'
    beq ACONSTNT
    cmp #'+'
    beq EVAL
    cmp #34                                 ; a quote
    bne EVAL3

;; Makes a temporary string of the literal after the quote at <TXTPTR>, then moves TXTPTR past its closing quote.
;; See: <STRLIT>, <ST2TXT>
STRTXT:
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    adc #0                                  ; the carry is set: one past the quote
    bcc STRTX2
    iny
    cpy #MAXPG
    bcc *+5
    inx
    ldy #MINPG

;; Makes the literal at A, Y and bank X a temporary string, then moves <TXTPTR> past it.
STRTX2:
    jsr STRLIT
    jmp ST2TXT

;; Takes NOT, evaluating the one value that follows: gives 1 when it is zero, or 0 when it is not, as a long integer
;; for a long integer and as a real otherwise.
;;
;; NOT applies to the next value alone, not to a formula. A string is not caught here: its <VALTYP> takes the long
;; integer's path.
;; See: <BCDTSTR>
NOTDO:
    jsr DECTPT                              ; so EVAL's CHRGET reads the value's first character
    jsr EVAL
    bit VALTYP
    bvc *+5
    jmp BCDTSTR                             ; a long integer
    lda FACEXP
    beq RLONE
    ldy #0
    .byte 44                                ; BIT abs, which skips RLONE's LDY

;; Gives 1 for <NOTDO> as a real.
RLONE:
    ldy #1
    jmp SNGFLT

;; Takes a unary minus, or else expects a formula in parentheses.
;; See: <DOMIN>, <PARCHK>
EVAL3:
    cmp #'-'
    beq DOMIN
    jmp PARCHK

;; Takes an escape token: reads the byte after it and moves <TXTPTR> past both, then goes to <ISFUN> with the byte.
PARC22:
    jsr CHRGET
    tax
    jsr CHRGET
    txa
    jmp ISFUN

;; Takes a reserved word that gives a value with no arguments, such as ERR or TIME$, through <RESTBL>; any other
;; reserved word is a syntax error.
;; In: A = the token
;; See: <RESTBL>
PARC23:
    cmp #FRETK
    bcc SNERR6
    cmp #POPTKN
    bcs SNERR6
    asl
    tax
    jsr CHRGET
    lda RESTBL-FRETK-FRETK+256,X            ; the token less FRETK, times two
    sta JMPER+1
    lda RESTBL-FRETK-FRETK+257,X
    sta JMPER+2
    jmp JMPER

;; Reads the cursor's position from the console into <CURX> and <CURY>.
;; Out: Y = the cursor's line, from <CURY>
;; See: <REDCUR>, <DOVPOS>, <POS>
VPOS:
    brk
    .byte SDSTAT
    .word REDCUR
    ldy CURY
    rts

;; Gives the value of ERRLIN, the line number of the last error, from <ERRLIN>.
DOERRLN:
    lda ERRLIN+1
    ldy ERRLIN
    sta FACHO
    sty FACHO+1
    ldx #$90
    sec                                     ; positive
    jmp FLOATC

;; Gives the value of OUTREC, the column at which LIST wraps its lines (0 for none), from <OUTREC>.
GIVOUTREC:
    ldy OUTREC
    jmp SNGFLT

;; Gives the value of INDENT, the indent LIST uses, from <INDENT>.
GIVINDENT:
    ldy INDENT
    jmp SNGFLT

;; Gives the value of KBD, the last key read on an interrupt, from <KEYSAVE>.
GIVKBD:
    ldy KEYSAVE
    jmp SNGFLT

;; Gives the value of EOF, the file number of the last end of file, from <EOFSV>.
GIVEOF:
    ldy EOFSV
    .byte 44                                ; BIT abs, which skips GIVERR's LDY

;; Gives the value of ERR, the number of the last error, from <ERRNUM>.
GIVERR:
    ldy ERRNUM
    jmp SNGFLT

;; Finishes NOT for a long integer: 1 when all eight bytes of the <FAC> are zero, 0 otherwise.
;; See: <NOTDO>, <LORALL>
BCDTSTR:
    lda #<(FAC)
    ldy #>(FAC)
    jsr LORALL
    beq ISFALS
    jmp LONGST0

;; Gives 1 as a long integer, for <BCDTSTR>.
ISFALS:
    jmp LONGST1

;; Takes a unary minus, evaluating the one value that follows and negating it, as a long integer or a real.
;;
;; A string is not caught here: its <VALTYP> takes the long integer's path.
;; See: <LTWSCOMP>, <NEGOP>
DOMIN:
    jsr EVAL
    bit VALTYP
    bvc CHGSGN                              ; a real
    jmp LTWSCOMP

;; Negates the real in the FAC.
CHGSGN:
    jmp NEGOP

;; Ends the statement with a syntax error.
SNERR6:
    jmp SNERR

; ---------------------------------------------------------------------------------------------------------------------
; Parentheses and syntax checks
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a formula that ends at a closing parenthesis or another delimiter, keeping the operators before it.
;;
;; A zero precedence on the verb stack stops <FRMEVL> from taking an operator from outside the parentheses.
;; In: TXTPTR = the formula's first character, VALTYP = the type wanted
;; Out: FAC = the value, VALTYP = its type
;; See: <FRMEVL1A>, <CMPLXERR>
DOPAR:
    lda #0
    ldy VRBPT
    iny
    sta VRBSTK,Y                            ; precedence 0
    iny
    sty VRBPT
    cpy #$20                                ; too deep
    bcs CMPLXERR
    jsr FRMEVL1A
    dec VRBPT
    dec VRBPT
    rts

;; Evaluates a formula in parentheses.
;; In: TXTPTR = the opening parenthesis
;; See: <DOPAR>, <CHKCLS>
PARCHK:
    jsr CHKOPN

;; Evaluates a formula and its closing parenthesis.
;; See: <PARCHK>
PARCHK2:
    jsr DOPAR

;; Checks for a closing parenthesis and moves past it, or ends the statement with a syntax error.
;; See: <SYNCHR>
CHKCLS:
    lda #41
    .byte 44                                ; BIT abs, which skips the next LDA

;; Checks for a semicolon and moves past it, or ends the statement with a syntax error.
CHKSMC:
    lda #$3B
    .byte 44                                ; BIT abs, which skips the next LDA

;; Checks for an equals sign and moves past it, or ends the statement with a syntax error.
CHKEQL:
    lda #'='
    .byte 44                                ; BIT abs, which skips the next LDA

;; Checks for a number sign and moves past it, or ends the statement with a syntax error.
CHKPND:
    lda #'#'
    .byte 44                                ; BIT abs, which skips the next LDA

;; Checks for an opening parenthesis and moves past it, or ends the statement with a syntax error.
CHKOPN:
    lda #40
    .byte 44                                ; BIT abs, which skips the next LDA

;; Checks for a comma and moves past it, or ends the statement with a syntax error.
CHKCOM:
    lda #44

;; Checks that the character at <TXTPTR> is A and moves past it, or ends the statement with a syntax error.
;; In: A = the character
;; Out: A = the next character, as from <CHRGET>
SYNCHR:
    ldy #0
    cmp (TXTPTR),Y
    bne SNERR
    jmp CHRGET

;; Ends the statement with FORMULA TOO COMPLEX.
CMPLXERR:
    ldx #ERRST
    jmp ERROR

;; Ends the statement with SYNTAX ERROR.
SNERR:
    ldx #ERRSN
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a variable's value into the <FAC>; an array that does not exist yet is not made.
;; See: <PTREVL>, <ISVRET2>
ISVAR:
    ldx #$FF
    jsr PTREVL
    ldx VARPNTB

;; Takes the value of the variable at A, Y and bank X into the <FAC>, by its type: a long integer's eight bytes, a
;; real, an integer floated to a real, or, for a string, the pointer to its descriptor.
;; In: A, Y = the variable's address, X = its bank, VALTYP and INTFLG = its type
;; Out: FACMO, FACMO+1, FACMOB = the variable's address
;; See: <DMOVFM>, <MOVFM>, <GIVAYF>
ISVRET2:
    sta FACMO
    sty FACMO+1
    stx FACMOB
    bit VALTYP
    bvc GOOO                                ; a real or an integer
    bpl DBLVAR                              ; a long integer
    ldx #0                                  ; a string: FACMO points to its descriptor
    stx FACOV
    rts

;; Copies a long integer variable's eight bytes into the FAC.
DBLVAR:
    jmp DMOVFM

;; Moves <TXTPTR> back one character, keeping the page in the range banked pointers use.
;; Uses: A, Y
;; Keeps: X
DECTPT:
    txa
    pha
    lda TXTPTR
    bne DECTP1                              ; the page stays
    dec TXTPTR+1
    ldx TXTPTRB
    ldy TXTPTR+1
    jsr FIXYX
    stx TXTPTRB
    sty TXTPTR+1
DECTP1:
    dec TXTPTR
    pla
    tax
    rts

;; Takes a real or an integer variable's value into the FAC.
;; See: <GOOO2>, <MOVFM>
GOOO:
    bit INTFLG
    bpl GOOOOO

;; Floats an integer variable, its high byte first, into the FAC.
;; See: <GIVAYF>
GOOO2:
    ldy #0
    lda (FACMO),Y
    tax
    iny
    lda (FACMO),Y
    tay
    txa
    jmp GIVAYF

;; Unpacks a real variable into the FAC.
GOOOOO:
    jmp MOVFM

; ---------------------------------------------------------------------------------------------------------------------
; Functions
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a function's escape token: FN, NOT, or a function from <FUNDSP>.
;;
;; A function before <LENTK> takes a number, one up to <CONVTK> a string, and CONV and its kin any type; each reads its
;; argument in parentheses. Those past <LASNUM> (LEFT$, RIGHT$, MID$ and INSTR) take a string, then INSTR another, then
;; a byte; <GOODFUN> pushes their strings' descriptor pointers and the byte for the function to pull, and the function
;; checks for its closing parenthesis.
;; In: A = the byte after the escape token, TXTPTR = the character after it
;; See: <FUNDSP>, <FNDOER>, <NOTDO>
ISFUN:
    cmp #ONEFUN
    bcs GOODFUN
    cmp #FNTK
    bne *+5
    jmp FNDOER
    cmp #NOTTK
    bne SNERR
    jmp NOTDO

;; Reads the arguments of a function from <FUNDSP> and calls it.
;;
;; For LEFT$, RIGHT$, MID$ and INSTR, the stack holds, from the top: the byte argument, then the descriptor pointer of
;; each string, low byte, high byte and bank, the last string first. INSTR's byte is 1 when it is left out.
;; See: <ISFUN>, <FINGO>
GOODFUN:
    asl
    pha
    tax
    cpx #2*LASNUM-256+1
    bcc OKNORM                              ; one argument
    lda #$FF
    sta VALTYP
    jsr DOPAR                               ; the string
    jsr CHKCOM
    pla                                     ; the function
    tax
    lda FACMOB
    pha
    lda FACMO+1
    pha
    lda FACMO
    pha
    txa
    pha                                     ; on the stack, as the arguments may hold functions too
    cmp #2*INSTRTK-256
    bne NORMFN2
    lda #$FF                                ; INSTR: the string to look for
    sta VALTYP
    jsr DOPAR
    pla
    tax
    lda FACMOB
    pha
    lda FACMO+1
    pha
    lda FACMO
    pha
    txa
    pha
    jsr CHRGOT
    cmp #','
    beq NORMFUN
    ldx #1                                  ; no start: 1
    bne *+8                                 ; always, to the PLA after GETBYT

;; Moves past the comma before the byte argument.
NORMFUN:
    jsr CHRGET

;; Reads the byte argument, then calls the function with it on the stack.
NORMFN2:
    jsr GETBYT
    pla
    tay
    txa
    pha
    jmp FINGO

;; Reads a one-argument function's argument in parentheses, of the type the function takes, then calls it.
OKNORM:
    cpx #2*LENTK-256
    bcc ISABIN                              ; a number
    cpx #2*CONVTK-256
    bcc ISASTRNG                            ; a string
    lda #$20                                ; CONV and its kin: any type
    .byte 44                                ; BIT abs, which skips the next LDA

;; Sets <VALTYP> for a string argument, for <OKNORM>.
ISASTRNG:
    lda #$FF
    .byte 44                                ; BIT abs, which skips the next LDA

;; Sets <VALTYP> for a numeric argument, then reads it, for <OKNORM>.
ISABIN:
    lda #0
    sta VALTYP
    jsr PARCHK2
    pla
    tay

;; Calls the function from <FUNDSP>.
;; In: Y = the function's token times two
FINGO:
    lda FUNDSP-ONEFUN-ONEFUN+256,Y
    sta JMPER+1
    lda FUNDSP-ONEFUN-ONEFUN+257,Y
    sta JMPER+2
    jmp JMPER

; ---------------------------------------------------------------------------------------------------------------------
; Logical and relational operators
; ---------------------------------------------------------------------------------------------------------------------

;; Takes OR, giving 1 when either real is non-zero, 0 otherwise.
;; In: ARG, FAC = the operands
OROP:
    lda ARGEXP
    ora FACEXP
    bne GIVE1

;; Takes AND, giving 1 when both reals are non-zero, 0 otherwise.
;; In: ARG, FAC = the operands
ANDOP:
    lda ARGEXP
    beq GIVE0
    lda FACEXP
    bne GIVE1

;; Gives 0 as a real.
GIVE0:
    ldy #0
    .byte 44                                ; BIT abs, which skips GIVE1's LDY

;; Gives 1 as a real.
GIVE1:
    ldy #1
    jmp SNGFLT

;; Compares <ARG> with the <FAC>, reals or strings, and gives 1 when the relation in <DOMASK> holds, 0 when not.
;;
;; <DOMASK> has a bit for each part of the operator: 1 for greater, 2 for equal and 4 for less. Strings compare
;; character by character, and a shorter string that matches the start of a longer one is less. Both strings'
;; temporaries are freed.
;; In: ARG = the left operand, FAC = the right one
;; Out: FAC = 1 or 0, as a real, VALTYP = 0
;; See: <FCOMPARG>, <FREFAC>
DOREL:
    bit VALTYP
    bmi STRCMP
    jsr FCOMPARG
    tax
    jmp QCOMP

;; Compares two strings for <DOREL>.
STRCMP:
    jsr FREFAC                              ; the right string
    php                                     ; whether its temporary was freed
    sta DSCTMP                              ; its length
    stx DSCTMP+1
    sty DSCTMP+1+1
    lda INDEXB
    sta DSCTMPB
    lda ARGMO
    ldy ARGMO+1                             ; the left string
    ldx ARGMOB
    jsr FRETMP
    php
    stx ARGMO
    sty ARGMO+1
    ldx INDEXB
    stx ARGMOB
    tax
    pha                                     ; its length
    sec
    sbc DSCTMP                              ; which is longer?
    beq STASGN
    lda #1                                  ; the left is shorter: less
    bcc STASGN
    ldx DSCTMP                              ; the left is longer: compare the right's length
    lda #$100-1

;; Keeps the result the lengths give, for when the shorter string matches the start of the longer.
STASGN:
    sta FACSGN
    ldy #255
    inx

;; Compares the next character, or takes the lengths' result when there are no more.
NXTCMP:
    iny
    dex
    bne GETCMP
    ldx FACSGN

;; Turns a comparison result in X, -1, 0 or 1, into the relation's bit, with the carry set for -1.
QCOMP:
    bmi DOCMP                               ; the carry is set for -1
    clc
    bcc DOCMP                               ; always

;; Compares one character of the two strings.
GETCMP:
    lda (ARGMO),Y
    cmp (DSCTMP+1),Y
    beq NXTCMP
    ldx #$100-1                             ; the left is greater
    bcs DOCMP
    ldx #1                                  ; the left is less

;; Turns the comparison's result into 1 or 0 by the relation in <DOMASK>, freeing the strings' temporaries.
;; In: X = $FF when the left is greater, 0 when equal, 1 when less, carry = set for $FF
DOCMP:
    inx                                     ; -1, 0 and 1 become bits 1, 2 and 4
    txa
    rol
    and DOMASK
    beq GOFLOT
    lda #1

;; Frees the two strings' temporaries after a string comparison, then floats the result.
GOFLOT:
    bit VALTYP
    bpl GFLOT1                              ; numbers
    sta FOUR6                               ; the result
    lda #0
    sta VALTYP
    pla                                     ; the left string's length
    ldx ARGMO
    ldy ARGMO+1
    stx INDEX
    sty INDEX+1
    ldx ARGMOB
    stx INDEXB
    plp                                     ; whether the left's temporary was freed
    jsr FRENOW
    plp                                     ; whether the right's was
    jsr FREFC1
    lda FOUR6

;; Floats the comparison's result, 1 or 0.
GFLOT1:
    jmp FLOAT
