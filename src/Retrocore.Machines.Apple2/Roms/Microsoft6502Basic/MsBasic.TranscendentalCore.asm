;; Emits the square-root, power and negation routines.
.macro POWER_ROUTINES

;; Takes the square root of <FAC> by raising it to one half.
;; Errors: <LOG> reports an illegal quantity for a negative argument
SQR:
    jsr MOVAF
    lda #<FHALF
    ldy #>FHALF
    jsr MOVFM

;; Raises the argument accumulator to the power in <FAC> and returns the result in <FAC>.
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

.endmacro

;; Emits the five-byte-precision exponential routine.
.macro EXP_ROUTINE

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

.endmacro

;; Emits the polynomial evaluators for five-byte coefficients.
.macro POLYNOMIAL_ROUTINES

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
;; Entry: POLY1 = uses the table already saved in <POLYPT>
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

.endmacro

;; Emits the sine, cosine and tangent routines.
.macro TRIG_ROUTINES

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

;; Divides the sine by the cosine through <FDIV>.
GFDIV:
    jmp FDIV

;; Continues the cosine calculation using the quadrant sign in A from <TAN>.
COSC:
    pha
    jmp SIN1

.endmacro

;; Emits the arctangent routine that uses <ATNCON>.
.macro ATN_ROUTINE

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

.endmacro
