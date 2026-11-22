; MICROSOFT 6502 BASIC: EXPRESSION EVALUATION
;
; EXPRESSION_CORE carryReturn
;   carryReturn = 1 carries the saved <PUSHF> return address across a page; 0 preserves the earlier behavior.
; The stack layout here uses five-byte floating-point values.

.macro EXPRESSION_CORE carryReturn
    .assert carryReturn = 0 || carryReturn = 1, "carryReturn must be 0 or 1."

;; Evaluates an expression with operator precedence.
;;
;; Each pending operation has its dispatch address, unpacked operand and precedence on the stack. A
;; relational mask also records the operand type so <DOREL> can compare either numbers or strings.
;; In: TXTPTR = first character of the expression
;; Out: FAC = numeric result or string descriptor pointer, VALTYP = result type, TXTPTR = terminating character
FRMEVL:
    ldx TXTPTR
    bne FRMEV1
    dec TXTPTR+1

FRMEV1:
    dec TXTPTR
    ldx #$00
    .byte $24                   ; BIT zero-page skips the next byte

LPOPER:
    pha
    txa
    pha
    lda #$01
    jsr GETSTK
    jsr EVAL
    lda #$00
    sta OPMASK

TSTOP:
    jsr CHRGOT

LOPREL:
    sec
    sbc #<GREATK
    bcc ENDREL
    cmp #$03
    bcs ENDREL
    cmp #$01
    rol a
    eor #$01
    eor OPMASK
    cmp OPMASK
    bcc SNERR5
    sta OPMASK
    jsr CHRGET
    jmp LOPREL

ENDREL:
    ldx OPMASK
    bne FINREL
    bcs QOP
    adc #<(GREATK-PLUSTK)
    bcc QOP
    adc VALTYP
    bne *+5
    jmp CAT
    adc #$FF
    sta INDEX1
    asl a
    adc INDEX1
    tay

QPREC:
    pla
    cmp OPTAB,y
    bcs QCHNUM
    jsr CHKNUM

DOPREC:
    pha

NEGPRC:
    jsr DOPRE1
    pla
    ldy OPPTR
    bpl QPREC1
    tax
    beq QOPGO
    bne PULSTK

FINREL:
    lsr VALTYP
    txa
    rol a
    ldx TXTPTR
    bne FINRE2
    dec TXTPTR+1

FINRE2:
    dec TXTPTR
    ldy #<(PTDORL-OPTAB)
    sta OPMASK
    bne QPREC

QPREC1:
    cmp OPTAB,y
    bcs PULSTK
    bcc DOPREC

DOPRE1:
    lda OPTAB+2,y
    pha
    lda OPTAB+1,y
    pha
    jsr PUSHF1
    lda OPMASK
    jmp LPOPER

SNERR5:
    jmp SNERR

;; Saves the current <FAC> and operator precedence for a pending operation.
PUSHF1:
    lda FACSGN
    ldx OPTAB,y

;; Saves the sign in A and rounded <FAC> on the stack, then returns through <INDEX1>.
;;
;; The earlier entry increments only the return address's low byte. The later entry also carries into
;; its high byte when that increment crosses a page.
PUSHF:
    tay
    pla
    sta INDEX1
.if .not carryReturn
    inc INDEX1
.endif
    pla
    sta INDEX1+1
    tya
    pha
.if carryReturn
    inc INDEX1
    bne FORPSH
    inc INDEX1+1
.endif

;; Saves the rounded <FAC> on the stack without pushing its sign, then jumps through <INDEX1>.
;;
;; FOR sets <INDEX1> to its continuation before entering here; <PUSHF> obtains it from the return address.
FORPSH:
    jsr ROUND
    lda FACLO
    pha
    lda FACMO
    pha
    lda FACMOH
    pha
    lda FACHO
    pha
    lda FACEXP
    pha
    jmp (INDEX1)

QOP:
    ldy #$FF
    pla

QOPGO:
    beq QOPRTS

QCHNUM:
    cmp #$64                    ; relational precedence in OPTAB
    beq UNPSTK
    jsr CHKNUM

UNPSTK:
    sty OPPTR

PULSTK:
    pla
    lsr a
    sta DOMASK
    pla
    sta ARGEXP
    pla
    sta ARGHO
    pla
    sta ARGMOH
    pla
    sta ARGMO
    pla
    sta ARGLO
    pla
    sta ARGSGN
    eor FACSGN
    sta ARISGN

QOPRTS:
    lda FACEXP

UNPRTS:
    rts
.endmacro
