;; APPLESOFT: NEXT AND EXPRESSION EVALUATION
;;
;; This part follows INPUT and READ in AppleSoft.InputOutput.asm. NEXT belongs with FOR, whose stack
;; frames are created in AppleSoft.ControlFlow.asm; it is here because the ROM places it immediately before
;; the expression evaluator. The evaluator saves pending operators and operands on the machine stack.
;; <OPTAB> gives each operator its precedence and dispatch address. Relational operators accumulate a mask,
;; and string concatenation returns to the evaluator through <TSTOP>.

;; Executes NEXT, optionally naming a FOR variable and optionally continuing with a comma-separated list.
;;
;; <FNDFOR> locates the frame. The step is added to the variable and compared with the limit using the
;; step's sign; on continuation, the frame's line and text pointers restore the loop body. Otherwise the
;; frame is removed. An unmatched variable raises NEXT WITHOUT FOR.
NEXT:
    bne     GETFOR
    ldy     #$00
    beq     STXFOR

GETFOR:
    jsr     PTRGET

STXFOR:
    sta     FORPNT
    sty     FORPNT+1
    jsr     FNDFOR
    beq     HAVFOR
    ldx     #<ERRNF

ERRGO5:
    beq     ERRGO4

HAVFOR:
    txs
    ; Point at the saved step and limit within the frame in page one.
    inx
    inx
    inx
    inx
    txa
    inx
    inx
    inx
    inx
    inx
    inx
    stx     INDEX2
    ldy     #$01
    jsr     MOVFM
    tsx
    lda     $0109,x
    sta     FACSGN
    lda     FORPNT
    ldy     FORPNT+1
    jsr     FADD
    jsr     MOVVF
    ldy     #$01
    jsr     FCOMPN
    tsx
    sec
    sbc     $0109,x
    beq     LOOPDN
    lda     $010F,x
    sta     CURLIN
    lda     $0110,x
    sta     CURLIN+1
    lda     $0112,x
    sta     TXTPTR
    lda     $0111,x
    sta     TXTPTR+1

NEWSGO:
    jmp     NXTCO1

LOOPDN:
    txa
    adc     #$11
    tax
    txs
    jsr     CHRGOT
    cmp     #$2C
    bne     NEWSGO
    jsr     CHRGET
    jsr     GETFOR

;; Evaluates an expression and requires its result to be numeric.
;; In: TXTPTR = first character of the expression
;; Out: FAC = numeric result, TXTPTR = terminating character
;; Errors: TYPE MISMATCH for a string
FRMNUM:
    jsr     FRMEVL

;; Requires the current expression result to be numeric.
;; In: VALTYP = result type
;; Errors: TYPE MISMATCH for a string
CHKNUM:
    clc
    .byte   $24    ; BIT zero-page skips the next byte

;; Requires the current expression result to be a string.
;; In: VALTYP = result type
;; Errors: TYPE MISMATCH for a number
CHKSTR:
    sec

;; Checks the result type selected by carry without changing <VALTYP>.
;; In: carry = set for string or clear for numeric, VALTYP = result type
;; Out: carry = selected type on success
;; Errors: TYPE MISMATCH if the types differ
CHKVAL:
    bit     VALTYP
    bmi     DOCSTR
    bcs     CHKERR

CHKOK:
    rts

DOCSTR:
    bcs     CHKOK

CHKERR:
    ldx     #<ERRTM

ERRGO4:
    jmp     ERROR

;; Evaluates an expression with operator precedence.
;;
;; Each pending operation has its dispatch address, unpacked operand and precedence on the stack. A
;; relational mask also records the operand type so <DOREL> can compare either numbers or strings.
;; In: TXTPTR = first character of the expression
;; Out: FAC = numeric result or string descriptor pointer, VALTYP = result type, TXTPTR = terminating character
FRMEVL:
    ldx     TXTPTR
    bne     FRMEV1
    dec     TXTPTR+1

FRMEV1:
    dec     TXTPTR
    ldx     #$00
    .byte   $24    ; BIT zero-page skips the next byte

LPOPER:
    pha
    txa
    pha
    lda     #$01
    jsr     GETSTK
    jsr     EVAL
    lda     #$00
    sta     OPMASK

TSTOP:
    jsr     CHRGOT

LOPREL:
    sec
    sbc     #<GREATK
    bcc     ENDREL
    cmp     #$03
    bcs     ENDREL
    cmp     #$01
    rol     a
    eor     #$01
    eor     OPMASK
    cmp     OPMASK
    bcc     SNERR5
    sta     OPMASK
    jsr     CHRGET
    jmp     LOPREL

ENDREL:
    ldx     OPMASK
    bne     FINREL
    bcs     QOP
    adc     #<(GREATK-PLUSTK)
    bcc     QOP
    adc     VALTYP
    bne     *+5
    jmp     CAT
    adc     #$FF
    sta     INDEX
    asl     a
    adc     INDEX
    tay

QPREC:
    pla
    cmp     OPTAB,y
    bcs     QCHNUM
    jsr     CHKNUM

DOPREC:
    pha

NEGPRC:
    jsr     DOPRE1
    pla
    ldy     OPPTR
    bpl     QPREC1
    tax
    beq     QOPGO
    bne     PULSTK

FINREL:
    lsr     VALTYP
    txa
    rol     a
    ldx     TXTPTR
    bne     FINRE2
    dec     TXTPTR+1

FINRE2:
    dec     TXTPTR
    ldy     #<(PTDORL-OPTAB)
    sta     OPMASK
    bne     QPREC

QPREC1:
    cmp     OPTAB,y
    bcs     PULSTK
    bcc     DOPREC

DOPRE1:
    lda     OPTAB+2,y
    pha
    lda     OPTAB+1,y
    pha
    jsr     PUSHF1
    lda     OPMASK
    jmp     LPOPER

SNERR5:
    jmp     SNERR

;; Saves the current FAC and operator precedence for a pending operation.
PUSHF1:
    lda     FACSGN
    ldx     OPTAB,y

;; Saves the sign in A and rounded FAC on the stack, then returns through <INDEX>.
PUSHF:
    tay
    pla
    sta     INDEX
    inc     INDEX
    pla
    sta     INDEX+1
    tya
    pha

;; Saves the rounded FAC on the stack without pushing its sign, then jumps through <INDEX>.
;;
;; FOR sets <INDEX> to its continuation before entering here; <PUSHF> obtains it from the return address.
FORPSH:
    jsr     ROUND
    lda     FACLO
    pha
    lda     FACMO
    pha
    lda     FACMOH
    pha
    lda     FACHO
    pha
    lda     FACEXP
    pha
    jmp     (INDEX)

QOP:
    ldy     #$FF
    pla

QOPGO:
    beq     QOPRTS

QCHNUM:
    cmp     #$64                   ; relational precedence in OPTAB
    beq     UNPSTK
    jsr     CHKNUM

UNPSTK:
    sty     OPPTR

PULSTK:
    pla
    lsr     a
    sta     DOMASK
    pla
    sta     ARGEXP
    pla
    sta     ARGHO
    pla
    sta     ARGMOH
    pla
    sta     ARGMO
    pla
    sta     ARGLO
    pla
    sta     ARGSGN
    eor     FACSGN
    sta     ARISGN

QOPRTS:
    lda     FACEXP

UNPRTS:
    rts

;; Evaluates one operand: a number, variable, literal, parenthesized expression or function.
EVAL:
    lda     #$00
    sta     VALTYP

EVAL0:
    jsr     CHRGET
    bcs     EVAL2

EVAL1:
    jmp     FIN

EVAL2:
    jsr     ISLETC
    bcs     ISVAR

QDOT:
    cmp     #$2E
    beq     EVAL1
    cmp     #<MINUTK
    beq     DOMIN
    cmp     #<PLUSTK
    beq     EVAL0
    cmp     #$22
    bne     EVAL3

STRTXT:
    lda     TXTPTR
    ldy     TXTPTR+1
    adc     #$00
    bcc     STRTX2
    iny

STRTX2:
    jsr     STRLIT
    jmp     ST2TXT

EVAL3:
    cmp     #<NOTTK
    bne     EVAL4
    ldy     #<(NOTTAB-OPTAB)
    bne     GONPRC

;; Applies Applesoft's logical NOT: zero becomes one, and any nonzero value becomes zero.
NOTOP:
    lda     FACEXP
    bne     NOTOP1
    ldy     #$01
    .byte   $2C    ; BIT absolute skips the next two bytes

NOTOP1:
    ldy     #$00
    jmp     SNGFLT

EVAL4:
    cmp     #<FNTK
    bne     *+5
    jmp     FNDOER
    cmp     #<ONEFUN
    bcc     PARCHK
    jmp     QSTAT2

;; Requires an opening parenthesis, evaluates an expression, and requires the closing parenthesis.
PARCHK:
    jsr     CHKOPN
    jsr     FRMEVL

;; Requires and consumes a closing parenthesis.
CHKCLS:
    lda     #$29
    .byte   $2C    ; BIT absolute skips the next two bytes

;; Requires and consumes an opening parenthesis.
CHKOPN:
    lda     #$28
    .byte   $2C    ; BIT absolute skips the next two bytes

;; Requires and consumes a comma.
CHKCOM:
    lda     #$2C

;; Requires the character in A at <TXTPTR>, then advances to the next character.
;; Errors: SYNTAX if the character does not match
SYNCHR:
    ldy     #$00
    cmp     (TXTPTR),y
    bne     SNERR

CHRGO5:
    jmp     CHRGET

SNERR:
    ldx     #<ERRSN
    jmp     ERROR

DOMIN:
    ldy     #<(NEGTAB-OPTAB)

GONPRC:
    pla
    pla
    jmp     NEGPRC

;; Resolves a variable operand and loads its value, or leaves its string descriptor in FAC.
ISVAR:
    jsr     PTRGET

ISVRET:
    sta     FACMO
    sty     FACLO
    ldx     VALTYP
    beq     GOOO
    ldx     #$00
    stx     FACOV

STRRTS:
    rts

GOOO:
    ldx     INTFLG
    bpl     GOOOOO
    ldy     #$00
    lda     (FACMO),y
    tax
    iny
    lda     (FACMO),y
    tay
    txa
    jmp     GIVAYF

GOOOOO:

QSTATV:
    jmp     MOVFM

;; Evaluates SCRN's coordinates and returns the color read by the Monitor.
QSTAT1:
    jsr     CHRGET
    jsr     PLOTFN
    txa
    ldy     FIRST
    jsr     MSCRN
    tay
    jsr     SNGFLT
    jmp     CHKCLS

QSTAT2:
    cmp     #<SCRNTK
    beq     QSTAT1

;; Parses a built-in function's arguments and dispatches through <FUNDSP>.
;;
;; The string slicing functions take a string and a byte argument; their descriptors and arguments are
;; stacked for the callee. Ordinary functions take one parenthesized expression.
ISFUN:
    asl     a
    pha
    tax
    jsr     CHRGET
    cpx     #<(2*LASNUM-255)
    bcc     OKNORM
    jsr     CHKOPN
    jsr     FRMEVL
    jsr     CHKCOM
    jsr     CHKSTR
    pla
    tax
    lda     FACLO
    pha
    lda     FACMO
    pha
    txa
    pha
    jsr     GETBYT
    pla
    tay
    txa
    pha
    jmp     FINGO

OKNORM:
    jsr     PARCHK
    pla
    tay

FINGO:
    lda     FUNDSP-2*ONEFUN+256,y
    sta     JMPER+1
    lda     FUNDSP-2*ONEFUN+257,y
    sta     JMPER+2
    jsr     JMPER
    jmp     CHKNUM

;; Computes Boolean OR for two numeric operands, returning zero or one in FAC.
OROP:

;; Historical alias at the OR entry; AND dispatches to <OROP1> instead.
ANDOP:
    lda     ARGEXP
    ora     FACEXP
    bne     OROP12

;; Computes Boolean AND for two numeric operands, returning zero or one in FAC.
OROP1:
    lda     ARGEXP
    beq     OROP11
    lda     FACEXP
    bne     OROP12

OROP11:
    ldy     #$00
    .byte   $2C    ; BIT absolute skips the next two bytes

OROP12:
    ldy     #$01
    jmp     SNGFLT

;; Compares numeric or string operands and applies the relation mask to produce zero or one.
;; In: carry = set for strings or clear for numbers, DOMASK = relation mask
DOREL:
    jsr     CHKVAL
    bcs     STRCMP
    lda     ARGSGN
    ora     #$7F
    and     ARGHO
    sta     ARGHO
    lda     #<ARGEXP
    ldy     #$00
    jsr     FCOMP
    tax
    jmp     QCOMP

;; Compares the string bytes up to the shorter length, then compares their lengths if needed.
STRCMP:
    lda     #$00
    sta     VALTYP
    dec     OPMASK
    jsr     FREFAC
    sta     DSCTMP
    stx     DSCTMP+1
    sty     DSCTMP+2
    lda     ARGMO
    ldy     ARGLO
    jsr     FRETMP
    stx     ARGMO
    sty     ARGLO
    tax
    sec
    sbc     DSCTMP
    beq     STASGN
    lda     #$01
    bcc     STASGN
    ldx     DSCTMP
    lda     #$FF

STASGN:
    sta     FACSGN
    ldy     #$FF
    inx

NXTCMP:
    iny
    dex
    bne     GETCMP
    ldx     FACSGN

QCOMP:
    bmi     DOCMP
    clc
    bcc     DOCMP

GETCMP:
    lda     (ARGMO),y
    cmp     (DSCTMP+1),y
    beq     NXTCMP
    ldx     #$FF
    bcs     DOCMP
    ldx     #$01

DOCMP:
    inx
    txa
    rol     a
    and     DOMASK
    beq     GOFLOT
    lda     #$01

GOFLOT:
    jmp     FLOAT

;; Reads the paddle specified by the numeric argument and returns its value in FAC.
PDL:
    jsr     CONINT
    jsr     PREAD
    jmp     SNGFLT
