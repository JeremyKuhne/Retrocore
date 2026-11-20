;; Emits the decimal input routines.
;; Parameters: limitAt120 = 1 for the earlier exponent limit, 0 for the later limit
.macro DECIMAL_INPUT limitAt120

    .assert limitAt120 = 0 || limitAt120 = 1, "limitAt120 is 0 or 1."

; Decimal text input.

;; Reads a decimal number from BASIC text into <FAC>.
;;
;; Digits are accumulated by multiplying by ten and adding; <DECCNT> counts fractional digits and <TENEXP>
;; holds the decimal exponent. An optional exponent accepts either ASCII signs or BASIC sign tokens. The final
;; scale is applied by <MUL10> or <DIV10>, then the original sign is applied.
;; In: A = first character, TXTPTR = address of first character, carry = clear if it is a digit
;; See: <CHRGET>, <FINLOG>
FIN:
    ldy #$00
    ldx #$0A

FINZLP:
    ; Clear the decimal counters, sign flags and <FAC> workspace without changing carry.
    sty DECCNT,x
    dex
    bpl FINZLP
    bcc FINDGQ
    cmp #'-'
    bne QPLUS
    stx SGNFLG
    beq FINC

QPLUS:
    cmp #'+'
    bne FIN1

FINC:
    jsr CHRGET

FINDGQ:
    bcc FINDIG

FIN1:
    cmp #'.'
    beq FINDP
    cmp #'E'
    bne FINE
    jsr CHRGET
    bcc FNEDG1
    cmp #MINUTK
    beq FINEC1
    cmp #'-'
    beq FINEC1
    cmp #PLUSTK
    beq FINEC
    cmp #'+'
    beq FINEC
    bne FINEC2

FINEC1:
    ror EXPSGN

FINEC:
    jsr CHRGET

FNEDG1:
    bcc FINEDG

FINEC2:
    bit EXPSGN
    bpl FINE
    lda #$00
    sec
    sbc TENEXP
    jmp FINE1

FINDP:
    ror DPTFLG
    bit DPTFLG
    bvc FINC

FINE:
    lda TENEXP

FINE1:
    sec
    sbc DECCNT                      ; account for digits accumulated after the decimal point
    sta TENEXP
    beq FINQNG
    bpl FINMUL

FINDIV:
    jsr DIV10
    inc TENEXP
    bne FINDIV
    beq FINQNG

FINMUL:
    jsr MUL10
    dec TENEXP
    bne FINMUL

FINQNG:
    lda SGNFLG
    bmi NEGXQS
    rts

NEGXQS:
    jmp NEGOP

FINDIG:
    pha
    bit DPTFLG
    bpl FINDG1
    inc DECCNT

FINDG1:
    jsr MUL10
    pla
    sec
    sbc #'0'
    jsr FINLOG
    jmp FINC

;; Adds the signed byte in A to <FAC>, converting it to floating point first.
;; In: A = signed byte
FINLOG:
    pha
    jsr MOVAF
    pla
    jsr FLOAT
    lda ARGSGN
    eor FACSGN
    sta ARISGN
    ldx FACEXP
    jmp FADDT

;; Accumulates a decimal exponent digit into <TENEXP>.
;;
;; With the later limit, an accumulated exponent of ten or more signals overflow when positive and becomes 100
;; when negative. With the earlier limit, an accumulated exponent of twelve or more signals overflow when positive;
;; when negative, the arithmetic uses eleven for the first term but still adds the old <TENEXP>. The resulting
;; exponent is (88 + twice the old exponent + the next digit), modulo 256.
FINEDG:
    lda TENEXP
.if limitAt120
    cmp #$0C
    bcc MLEX10
    bit EXPSGN
    bmi MLEXMI
    jmp OVERR

MLEXMI:
    lda #$0B
.else
    cmp #$0A
    bcc MLEX10
    lda #$64
    bit EXPSGN
    bmi MLEXMI
    jmp OVERR
.endif

MLEX10:
    asl a
    asl a
    clc
    adc TENEXP
    asl a
    clc
    ldy #$00
    adc (TXTPTR),y
    sec
    sbc #'0'

.if .not limitAt120
MLEXMI:
.endif
    sta TENEXP
    jmp FINEC

.endmacro
