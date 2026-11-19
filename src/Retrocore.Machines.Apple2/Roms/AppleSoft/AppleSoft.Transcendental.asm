;; Exponentiation, random numbers and transcendental functions ($EE8D-$F10A).
;;
;; These routines operate on Applesoft's floating-point accumulator <FAC> and use the five-byte packed format for
;; constants and polynomial coefficients. <LOG> and the arithmetic primitives are in the floating-point modules.
;; This module follows AppleSoft.FloatOutput.asm; its final table ends immediately before <INITAT>.


;; Group: Exponentiation and square root

;; Takes the square root of <FAC> by raising it to one half.
;; Errors: <LOG> reports an illegal quantity for a negative argument
SQR:
    jsr MOVAF
    lda #<FHALF
    ldy #>FHALF
    jsr MOVFM

;; Raises the number in ARG to the power in <FAC> and returns the result in <FAC>.
;;
;; Zero to the zero power is one. A negative base is accepted only for an integer exponent; the parity of that
;; exponent determines the sign. Otherwise the result is exp(exponent * log(base)).
;; In: zero = set when the exponent is zero
;; Errors: illegal quantity for a negative base with a noninteger exponent
FPWRT:
    beq EXP
    lda ARGEXP
    bne FPWRT1
    jmp ZEROF1

FPWRT1:
    ldx #TEMPF3
    ldy #0
    jsr MOVMF
    lda ARGSGN
    bpl FPWR1
    jsr INT
    lda #TEMPF3
    ldy #0
    jsr FCOMP
    bne FPWR1
    tya
    ldy INTEGR

FPWR1:
    jsr MOVFA1
    tya
    pha
    jsr LOG
    lda #TEMPF3
    ldy #0
    jsr FMULT
    jsr EXP
    pla
    lsr a
    bcc NEGRTS

;; Negates <FAC> unless its exponent is zero.
NEGOP:
    lda FACEXP
    beq NEGRTS
    lda FACSGN
    eor #$FF
    sta FACSGN

;; Returns without changing the result.
NEGRTS:
    rts

;; Group: Exponential approximation

;; The five-byte floating-point constant log base 2 of e.
LOGEB2:
    .byte $81, $38, $AA, $3B, $29

;; <EXP>'s polynomial: degree 7, followed by eight five-byte coefficients in evaluation order.
EXPCON:
    .byte $07                        ; polynomial degree
    .byte $71, $34, $58, $3E, $56 ; 0.000021498763697
    .byte $74, $16, $7E, $B3, $1B ; 0.00014352314036
    .byte $77, $2F, $EE, $E3, $85 ; 0.0013422634824
    .byte $7A, $1D, $84, $1C, $2A ; 0.0096140170119
    .byte $7C, $63, $59, $58, $0A ; 0.055505126860
    .byte $7E, $75, $FD, $E7, $C6 ; 0.24022638462
    .byte $80, $31, $72, $18, $10 ; 0.69314718608
    .byte $81, $00, $00, $00, $00 ; 1

;; Computes e raised to <FAC>, returning the result in <FAC>.
;;
;; It multiplies by log2(e), keeps the integer part for scaling and evaluates <EXPCON> on the reduced argument.
;; A sufficiently negative argument underflows to zero.
;; Errors: floating-point overflow when the result is too large
EXP:
    lda #<LOGEB2
    ldy #>LOGEB2
    jsr FMULT
    lda FACOV
    adc #$50
    bcc STOLD
    jsr INCRND

STOLD:
    sta OLDOV
    jsr MOVEF
    lda FACEXP
    cmp #$88
    bcc EXP1

GOMLDV:
    jsr MLDVEX

EXP1:
    jsr INT
    lda INTEGR
    clc
    adc #$81
    beq GOMLDV
    sec
    sbc #1
    pha
    ldx #5

SWAPLP:
    lda ARGEXP,x
    ldy FACEXP,x
    sta FACEXP,x
    sty ARGEXP,x
    dex
    bpl SWAPLP
    lda OLDOV
    sta FACOV
    jsr FSUBT
    jsr NEGOP
    lda #<EXPCON
    ldy #>EXPCON
    jsr POLY
    lda #0
    sta ARISGN
    pla
    jsr MLDEXP
    rts

;; Group: Polynomial evaluation

;; Evaluates X * P(X squared) for X in <FAC>.
;; In: A = low byte of coefficient table, Y = high byte of coefficient table
;; Out: FAC = polynomial result
;; See: <POLY>
POLYX:
    sta POLYPT
    sty POLYPT+1
    jsr MOV1F
    lda #TEMPF1
    jsr FMULT
    jsr POLY1
    lda #TEMPF1
    ldy #0
    jmp FMULT

;; Evaluates a polynomial at <FAC> using Horner's method.
;;
;; The table starts with the degree (the number of coefficients minus one), followed by five-byte coefficients
;; from highest power to constant.
;; In: A = low byte of table, Y = high byte of table
;; Out: FAC = polynomial result
;; Entry: POLY1 = uses the table already saved in POLYPT
POLY:
    sta POLYPT
    sty POLYPT+1

POLY1:
    jsr MOV2F
    lda (POLYPT),y
    sta DEGREE
    ldy POLYPT
    iny
    tya
    bne POLY3
    inc POLYPT+1

POLY3:
    sta POLYPT
    ldy POLYPT+1

POLY2:
    jsr FMULT
    lda POLYPT
    ldy POLYPT+1
    clc
    adc #5
    bcc POLY4
    iny

POLY4:
    sta POLYPT
    sty POLYPT+1
    jsr FADD
    lda #TEMPF2
    ldy #0
    dec DEGREE
    bne POLY2

;; Returns the current floating-point result.
RANDRT:
    rts

;; Group: Random numbers

;; Multiplier for <RND>, stored as four bytes followed by the first byte of <RADDZC>.
;;
;; The five-byte operands intentionally overlap; <RADDZC>'s fifth byte is the opcode at <RND>.
RMULZC:
    .byte $98, $35, $44, $7A

;; Addend for <RND>: four bytes followed by the first instruction byte at <RND>.
RADDZC:
    .byte $68, $28, $B1, $46

;; Implements RND using the sign of <FAC>.
;;
;; Zero returns the last value in <RNDX>; a negative argument starts a sequence from that argument. A positive
;; argument advances the saved value using <RMULZC> and <RADDZC>. The high and low mantissa bytes are exchanged,
;; the exponent is shifted into the mantissa during normalization, and the positive result is saved in <RNDX>.
;; Out: FAC = pseudorandom value
;; Entry: STRNEX = normalizes and saves the current mantissa
RND:
    jsr SIGN
    tax
    bmi RND1

QSETNR:
    lda #RNDX
    ldy #0
    jsr MOVFM
    txa
    beq RANDRT
    lda #<RMULZC
    ldy #>RMULZC
    jsr FMULT
    lda #<RADDZC
    ldy #>RADDZC
    jsr FADD

RND1:
    ldx FACLO
    lda FACHO
    sta FACLO
    stx FACHO

STRNEX:
    lda #0
    sta FACSGN
    lda FACEXP
    sta FACOV
    lda #$80
    sta FACEXP
    jsr NORMAL
    ldx #RNDX
    ldy #0

;; Stores <FAC> in the floating-point variable addressed by X and Y via <MOVMF>.
GMOVMF:
    jmp MOVMF

;; Group: Sine, cosine and tangent

;; Computes cosine of <FAC> in radians by adding pi/2 and falling into <SIN>.
COS:
    lda #<PI2
    ldy #>PI2
    jsr FADD

;; Computes sine of <FAC> in radians.
;;
;; Division by 2*pi removes whole turns; quadrant identities reduce the remaining fraction for <SINCON>.
;; <TANSGN> records a quadrant change for <TAN>.
SIN:
    jsr MOVAF
    lda #<TWOPI
    ldy #>TWOPI
    ldx ARGSGN
    jsr FDIVF
    jsr MOVAF
    jsr INT
    lda #0
    sta ARISGN
    jsr FSUBT
    lda #<FR4
    ldy #>FR4
    jsr FSUB
    lda FACSGN
    pha
    bpl SIN1
    jsr FADDH
    lda FACSGN
    bmi SIN2
    lda TANSGN
    eor #$FF
    sta TANSGN

SIN1:
    jsr NEGOP

SIN2:
    lda #<FR4
    ldy #>FR4
    jsr FADD
    pla
    bpl SIN3
    jsr NEGOP

SIN3:
    lda #<SINCON
    ldy #>SINCON

;; Evaluates the odd polynomial addressed by A and Y via <POLYX>.
GPOLYX:
    jmp POLYX

;; Computes tangent of <FAC> in radians as sine divided by cosine.
;;
;; The input and sine are saved separately; the cosine is computed from the input's magnitude and quadrant sign.
TAN:
    jsr MOV1F
    lda #0
    sta TANSGN
    jsr SIN
    ldx #TEMPF3
    ldy #0
    jsr GMOVMF
    lda #TEMPF1
    ldy #0
    jsr MOVFM
    lda #0
    sta FACSGN
    lda TANSGN
    jsr COSC
    lda #TEMPF3
    ldy #0
    jmp FDIV

;; Continues the cosine calculation using the quadrant sign in A from <TAN>.
COSC:
    pha
    jmp SIN1

;; Five-byte floating-point pi/2.
PI2:
    .byte $81, $49, $0F, $DA, $A2

;; Five-byte floating-point 2*pi.
TWOPI:
    .byte $83, $49, $0F, $DA, $A2

;; Five-byte floating-point one quarter.
FR4:
    .byte $7F, $00, $00, $00, $00

;; <SIN>'s odd-polynomial table: degree 5 for P and six five-byte coefficients for X * P(X squared).
SINCON:
    .byte $05                        ; polynomial degree
    .byte $84, $E6, $1A, $2D, $1B ; -14.381383816
    .byte $86, $28, $07, $FB, $F8 ; 42.07777095
    .byte $87, $99, $68, $89, $01 ; -76.704133676
    .byte $87, $23, $35, $DF, $E1 ; 81.605223690
    .byte $86, $A5, $5D, $E7, $28 ; -41.34170209
    .byte $83, $49, $0F, $DA, $A2 ; 6.2831853070
    ; Unused signature: "MICROSOFT!" backwards, each byte XORed with $87.
    .byte $A6, $D3, $C1, $C8, $D4, $C8, $D5, $C4, $CE, $CA

;; Group: Arctangent

;; Computes arctangent of <FAC> in radians.
;;
;; It reduces the magnitude to at most one using atan(x) = pi/2 - atan(1/x), evaluates <ATNCON>, then restores
;; the original sign.
ATN:
    lda FACSGN
    pha
    bpl ATN1
    jsr NEGOP

ATN1:
    lda FACEXP
    pha
    cmp #$81
    bcc ATN2
    lda #<FONE
    ldy #>FONE
    jsr FDIV

ATN2:
    lda #<ATNCON
    ldy #>ATNCON
    jsr POLYX
    pla
    cmp #$81
    bcc ATN3
    lda #<PI2
    ldy #>PI2
    jsr FSUB

ATN3:
    pla
    bpl ATN4
    jmp NEGOP

ATN4:
    rts

;; <ATN>'s odd-polynomial table: degree 11 for P and twelve five-byte coefficients for X * P(X squared).
ATNCON:
    .byte $0B                        ; polynomial degree
    .byte $76, $B3, $83, $BD, $D3 ; -0.0006847939119
    .byte $79, $1E, $F4, $A6, $F5 ; 0.004850942156
    .byte $7B, $83, $FC, $B0, $10 ; -0.01611170184
    .byte $7C, $0C, $1F, $67, $CA ; 0.03420963805
    .byte $7C, $DE, $53, $CB, $C1 ; -0.05427913276
    .byte $7D, $14, $64, $70, $4C ; 0.07245719654
    .byte $7D, $B7, $EA, $51, $7A ; -0.08980239538
    .byte $7D, $63, $30, $88, $7E ; 0.1109324134
    .byte $7E, $92, $44, $99, $3A ; -0.1428398077
    .byte $7E, $4C, $CC, $91, $C7 ; 0.1999991205
    .byte $7F, $AA, $AA, $AA, $13 ; -0.3333333157
    .byte $81, $00, $00, $00, $00 ; 1
