;; APPLE II APPLESOFT LOGARITHM, MULTIPLICATION AND DIVISION
;;
;; The logarithm constants precede the arithmetic routines in ROM. <LOG> reduces its argument and evaluates a
;; polynomial; multiplication and division form a mantissa in <RESHO> through <RESLO> and normalize it into <FAC>.
;; Packed operands are five bytes in the format described in AppleSoft.FloatingPoint.asm.
;;
;; Part of AppleSoft.asm; it follows AppleSoft.FloatingPoint.asm.

;; Packed floating-point constant 1.
FONE:
    .byte   $81, $00, $00, $00, $00

;; Logarithm polynomial: degree minus one, followed by four packed coefficients.
LOGCN2:
    .byte   $03
    .byte   $7F, $5E, $56, $CB, $79
    .byte   $80, $13, $9B, $0B, $64
    .byte   $80, $76, $38, $93, $16
    .byte   $82, $38, $AA, $3B, $20

;; Packed approximation to the square root of one half.
SQRHLF:
    .byte   $80, $35, $04, $F3, $34

;; Packed approximation to the square root of two.
SQRTWO:
    .byte   $81, $35, $04, $F3, $34

;; Packed floating-point constant minus one half.
NEGHLF:
    .byte   $80, $80, $00, $00, $00

;; Packed approximation to the natural logarithm of two.
LOG2:
    .byte   $80, $31, $72, $17, $F8

;; Computes the natural logarithm of <FAC>.
;;
;; It reduces <FAC> to a fractional range, evaluates a polynomial, adds the binary exponent, and multiplies by ln(2).
;; Errors: illegal argument = jumps to <FCERR> for zero or a negative argument
;; See: <LOGCN2>, <POLYX>
LOG:
    jsr     SIGN
    beq     LOGERR
    bpl     LOG1

LOGERR:
    jmp     FCERR

LOG1:
    lda     FACEXP
    sbc     #$7F                    ; save the binary exponent without its bias
    pha
    lda     #$80
    sta     FACEXP
    lda     #<SQRHLF
    ldy     #>SQRHLF
    jsr     FADD
    lda     #<SQRTWO
    ldy     #>SQRTWO
    jsr     FDIV
    lda     #<FONE
    ldy     #>FONE
    jsr     FSUB
    lda     #<LOGCN2
    ldy     #>LOGCN2
    jsr     POLYX
    lda     #<NEGHLF
    ldy     #>NEGHLF
    jsr     FADD
    pla
    jsr     FINLOG
    lda     #<LOG2
    ldy     #>LOG2

; Multiplication, unpacking and exponent handling.

;; Multiplies <FAC> by a packed number and leaves the product in <FAC>.
;;
;; Each multiplier byte is shifted through the result, adding ARG when a multiplier bit is set.
;; In: A = low byte of packed operand address, Y = high byte of packed operand address
;; Entry: FMULTT = multiplies unpacked ARG and FAC, with zero set from FACEXP and ARISGN already set
;; See: <MULDIV>, <MOVFR>
FMULT:
    jsr     CONUPK

FMULTT:
    bne     *+5                     ; skip the return jump when FAC is nonzero
    jmp     MULTRT
    jsr     MULDIV
    lda     #$00
    sta     RESHO
    sta     RESMOH
    sta     RESMO
    sta     RESLO
    lda     FACOV
    jsr     MLTPLY
    lda     FACLO
    jsr     MLTPLY
    lda     FACMO
    jsr     MLTPLY
    lda     FACMOH
    jsr     MLTPLY
    lda     FACHO
    jsr     MLTPL1
    jmp     MOVFR

;; Accumulates one byte of the multiplier, shifting the partial product right.
;; In: A = multiplier byte
;; Entry: MLTPL1 = includes the implicit high bit of the final byte
MLTPLY:
    bne     *+5                     ; a zero byte takes the whole-byte shift
    jmp     MULSHF

MLTPL1:
    lsr     a
    ora     #$80

MLTPL2:
    tay
    bcc     MLTPL3                  ; add ARG only for a set multiplier bit
    clc
    lda     RESLO
    adc     ARGLO
    sta     RESLO
    lda     RESMO
    adc     ARGMO
    sta     RESMO
    lda     RESMOH
    adc     ARGMOH
    sta     RESMOH
    lda     RESHO
    adc     ARGHO
    sta     RESHO

MLTPL3:
    ror     RESHO
    ror     RESMOH
    ror     RESMO
    ror     RESLO
    ror     FACOV
    tya
    lsr     a
    bne     MLTPL2

MULTRT:
    rts

;; Unpacks a five-byte memory operand into ARG and sets the relative sign in <ARISGN>.
;; In: A = low byte of packed operand address, Y = high byte of packed operand address
;; Out: A = FAC exponent, zero = set when FAC is zero
;; See: <MOVFM>
CONUPK:
    sta     INDEX1
    sty     INDEX1+1
    ldy     #$04
    lda     (INDEX1),y
    sta     ARGLO
    dey
    lda     (INDEX1),y
    sta     ARGMO
    dey
    lda     (INDEX1),y
    sta     ARGMOH
    dey
    lda     (INDEX1),y
    sta     ARGSGN
    eor     FACSGN
    sta     ARISGN
    lda     ARGSGN
    ora     #$80
    sta     ARGHO
    dey
    lda     (INDEX1),y
    sta     ARGEXP
    lda     FACEXP
    rts

;; Combines the exponents and signs for multiplication or division.
;;
;; A zero operand or exponent underflow discards the caller's return address and returns zero from the arithmetic
;; operation. Overflow goes to <OVERR>.
;; Entry: MLDEXP = uses the exponent already in A
MULDIV:
    lda     ARGEXP

MLDEXP:
    beq     ZEREMV
    clc
    adc     FACEXP
    bcc     TRYOFF
    bmi     GOOVER
    clc
    .byte   $2C                     ; BIT absolute skips the BPL and its displacement

TRYOFF:
    bpl     ZEREMV
    adc     #$80
    sta     FACEXP
    bne     *+5
    jmp     ZEROML
    lda     ARISGN
    sta     FACSGN
    rts

;; Handles an exceptional exponent in <EXP>, choosing overflow or zero from the sign of <FAC>.
MLDVEX:
    lda     FACSGN
    eor     #$FF
    bmi     GOOVER

ZEREMV:
    pla
    pla
    jmp     ZEROFC

GOOVER:
    jmp     OVERR

;; Multiplies <FAC> by ten, using an addition and exponent adjustments.
;; Errors: overflow = jumps to <OVERR> if the exponent wraps
MUL10:
    jsr     MOVAF
    tax
    beq     MUL10R
    clc
    adc     #$02
    bcs     GOOVER

FINML6:
    ldx     #$00
    stx     ARISGN
    jsr     FADDC
    inc     FACEXP
    beq     GOOVER

MUL10R:
    rts

;; Packed floating-point constant ten.
TENZC:
    .byte   $84, $20, $00, $00, $00

; Division and decimal scaling.

;; Divides <FAC> by ten.
;; See: <FDIVF>, <TENZC>
DIV10:
    jsr     MOVAF
    lda     #<TENZC
    ldy     #>TENZC
    ldx     #$00

;; Divides unpacked ARG by the packed number at Y:A.
;; In: A = low byte of divisor address, Y = high byte of divisor address, X = relative sign
FDIVF:
    stx     ARISGN
    jsr     MOVFM
    jmp     FDIVT

;; Divides a packed number by <FAC> and leaves the quotient in <FAC>.
;;
;; The divisor is rounded, then repeated comparisons and subtractions build the quotient a bit at a time.
;; In: A = low byte of packed dividend address, Y = high byte of packed dividend address
;; Entry: FDIVT = divides unpacked ARG by FAC, with zero set from FACEXP and ARISGN already set
;; Errors: divide by zero = jumps to <ERROR>, overflow = jumps to <OVERR>
FDIV:
    jsr     CONUPK

FDIVT:
    beq     DV0ERR
    jsr     ROUND
    lda     #$00
    sec
    sbc     FACEXP
    sta     FACEXP
    jsr     MULDIV
    inc     FACEXP
    beq     GOOVER
    ldx     #$FC
    lda     #$01

;; Builds quotient bits by comparing and subtracting the divisor from ARG.
DIVIDE:
    ; Compare the remaining dividend with the divisor, most significant byte first.
    ldy     ARGHO
    cpy     FACHO
    bne     SAVQUO
    ldy     ARGMOH
    cpy     FACMOH
    bne     SAVQUO
    ldy     ARGMO
    cpy     FACMO
    bne     SAVQUO
    ldy     ARGLO
    cpy     FACLO

SAVQUO:
    php
    rol     a
    bcc     QSHFT
    inx
    sta     RESLO,x
    beq     LD100
    bpl     DIVNRM
    lda     #$01

QSHFT:
    plp
    bcs     DIVSUB

SHFARG:
    asl     ARGLO
    rol     ARGMO
    rol     ARGMOH
    rol     ARGHO
    bcs     SAVQUO
    bmi     DIVIDE
    bpl     SAVQUO

DIVSUB:
    ; A quotient bit was set: subtract the divisor, then shift the remainder.
    tay
    lda     ARGLO
    sbc     FACLO
    sta     ARGLO
    lda     ARGMO
    sbc     FACMO
    sta     ARGMO
    lda     ARGMOH
    sbc     FACMOH
    sta     ARGMOH
    lda     ARGHO
    sbc     FACHO
    sta     ARGHO
    tya
    jmp     SHFARG

LD100:
    lda     #$40
    bne     QSHFT

DIVNRM:
    asl     a
    asl     a
    asl     a
    asl     a
    asl     a
    asl     a
    sta     FACOV
    plp
    jmp     MOVFR

;; Reports division by zero through <ERROR>.
DV0ERR:
    ldx     #ERRDV0
    jmp     ERROR
