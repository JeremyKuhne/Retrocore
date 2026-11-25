; retrocore: style=strict
;; Business BASIC: `EXP`, `RND`, `COS`, `SIN`, `TAN` and `ATN`, and the polynomial evaluators they use
;;
;; The constants here are reals in their packed, five-byte form: an exponent byte, then four bytes of mantissa with the
;; sign in the top bit (the mantissa's own top bit is always 1, so it is left out). A constant in BASIC's own bank is
;; read with all five bytes; a variable keeps only the first four.
;;
;; `EXP`, `COS`, `SIN`, `TAN`, `ATN` and the polynomial evaluators are Microsoft's, as AppleSoft has them, and carry
;; the same names; `RND` is Business BASIC's own, a Lehmer generator on long integers. Apple's listing calls this file
;; B3EXPON.
;;
;; Part of BusinessBasic.asm.

; `EXP`: its constants.
.scope Float continued

;; The bytes of a real in its packed form: the exponent and four bytes of mantissa.
PACKED_SIZE = 4 + 1

;; The real 1.4426950407, log2(e), which turns a power of e into a power of 2.
;; Also: LOGEB2 (BB13)
LogBase2OfE:
    .byte $81, $38, $AA, $3B, $29

;; <Functions::Exp>'s polynomial: 2^x for x from 0 to 1, as eight coefficients (a degree of 7), highest power first;
;; they follow the series of e^(x ln 2).
;; See: <Float::EvaluatePolynomial>
;; Also: EXPCON (BB13)
ExponentialPolynomial:
    .byte 7                                 ; the degree
    .byte $71, $34, $58, $3E, $56           ; 0.0000214987636, for x^7
    .byte $74, $16, $7E, $B3, $1B           ; 0.00014352314036, for x^6
    .byte $77, $2F, $EE, $E3, $85           ; 0.0013422634824, for x^5
    .byte $7A, $1D, $84, $1C, $2A           ; 0.0096140170119, for x^4
    .byte $7C, $63, $59, $58, $0A           ; 0.055505126860, for x^3
    .byte $7E, $75, $FD, $E7, $C6           ; 0.24022638462, for x^2
    .byte $80, $31, $72, $18, $10           ; 0.69314718608, ln 2, for x
    .byte $81, $00, $00, $00, $00           ; 1.0
.assert * - ExponentialPolynomial = 1 + 8 * PACKED_SIZE, "EXP's polynomial is a degree and eight coefficients."

.endscope

; `EXP`.
.scope Functions continued

;; The `EXP` function: e to the power of <FAC>.
;;
;; e^x is 2^y, with y = x * log2(e). The integer part of y becomes the result's exponent, and
;; <Float::ExponentialPolynomial> gives 2 to the power of the fraction. A y of 128 or more in size is an overflow error
;; when positive and gives 0 when negative; an integer part of 127 is an overflow error too.
;; In: FAC = x
;; Out: FAC = e^x
;; Errors: ERROV = the result is too large
;; See: <LOG>, <FPWRT>
;; Also: EXP (BB13)
.proc Exp
    lda #<(Float::LogBase2OfE)
    ldy #>(Float::LogBase2OfE)
    jsr FMULT
    lda FACOV
    adc #$50
    bcc CheckRange
    jsr INCRND                              ; round the product up

;; Keeps the product's extra low byte, biased by $50, while the product is copied to <ARG> unrounded; an exponent of
;; $88 or more is a y of 128 or more in size.
;; Also: STOLD (BB13)
CheckRange:
    sta OLDOV
    jsr MOVEF
    lda FACEXP
    cmp #$88                                ; y of 128 or more in size
    bcc Reduce

;; Gives an overflow error, or 0 for a negative <FAC>, and returns from `EXP` (<MLDVEX>).
;; Also: GOMLDV (BB13)
OutOfRange:
    jsr MLDVEX

;; Splits y into its integer part (<INT>), the scale, and its fraction, and raises 2 to the fraction.
;; Also: EXP1 (BB13)
Reduce:
    jsr INT
    lda INTEGR                              ; the integer part's low byte
    clc
    adc #$81
    beq OutOfRange                          ; 127: too large
    sec
    sbc #1
    pha                                     ; the scale, as an exponent byte
    ldx #FACSGN - FACEXP

;; Exchanges <FAC> and <ARG>, exponent to sign: <FAC> = y again, <ARG> = `INT(y)`.
;; Also: SWAPLP (BB13)
SwapLoop:
    lda ARGEXP,X
    ldy FACEXP,X
    sta FACEXP,X
    sty ARGEXP,X
    dex
    bpl SwapLoop
    lda OLDOV
    sta FACOV
    jsr FSUBT                               ; INT(y) - y
    jsr NEGOP                               ; y - INT(y), from 0 to 1
    lda #<(Float::ExponentialPolynomial)
    ldy #>(Float::ExponentialPolynomial)
    jsr Float::EvaluatePolynomial
    lda #0
    sta ARISGN
    pla
    jsr MLDEXP                              ; add the scale to the exponent
    rts                                     ; a JSR, not a JMP: MLDEXP's underflow drops a return address
.endproc

.endscope

; Polynomials.
.scope Float continued

;; Evaluates an odd polynomial of <FAC>: x * P(x^2), for `SIN`, `ATN` and `LOG`.
;;
;; The table is a degree byte, then degree + 1 packed coefficients, highest power first, so the terms run from
;; x^(2 * degree + 1) down to x.
;; In: FAC = x, A = the table's low byte, Y = its high byte
;; Out: FAC = the polynomial's value
;; Uses: TEMPF1, TEMPF2, POLYPT, DEGREE
;; See: <Float::EvaluatePolynomial>
;; Also: POLYX (BB13)
.proc EvaluateOddPolynomial
    sta POLYPT
    sty POLYPT+1
    jsr MOV1F                               ; x into TEMPF1
    lda #TEMPF1
    jsr FMULT                               ; x^2
    jsr EvaluateStoredPolynomial
    lda #TEMPF1
    ldy #>(TEMPF1)
    jmp FMULT                               ; times x
.endproc

;; Evaluates a polynomial of <FAC> by Horner's rule.
;;
;; The table is a degree byte, then degree + 1 packed coefficients, highest power first, in BASIC's own bank.
;; In: FAC = x, A = the table's low byte, Y = its high byte
;; Out: FAC = the polynomial's value
;; Uses: TEMPF2, POLYPT, DEGREE
;; See: <Float::EvaluateOddPolynomial>
;; Also: POLY (BB13)
.proc EvaluatePolynomial
    sta POLYPT
    sty POLYPT+1
    ; Falls into EvaluateStoredPolynomial.
.endproc

;; Evaluates the polynomial at <POLYPT> with x in <FAC>, as <Float::EvaluatePolynomial> does.
;; In: FAC = x, POLYPT = the table
;; Out: FAC = the polynomial's value
;; Also: POLY1 (BB13)
.proc EvaluateStoredPolynomial
    jsr MOV2F                               ; x into TEMPF2; Y = 0
    sty POLYPTB                             ; the table is in bank 0
    lda (POLYPT),Y
    sta DEGREE
    ldy POLYPT
    iny
    tya
    bne SetPointer
    inc POLYPT+1

;; Points <POLYPT> at the first coefficient.
;; Also: POLY3 (BB13)
SetPointer:
    sta POLYPT
    ldy POLYPT+1

;; Multiplies by the coefficient at Y and A on the first pass, and by x (<TEMPF2>) on later ones, and steps to the
;; next coefficient.
;; Also: POLY2 (BB13)
NextTerm:
    jsr FMULT
    lda POLYPT
    ldy POLYPT+1
    clc
    adc #PACKED_SIZE
    bcc AddTerm
    iny

;; Adds the next coefficient, once for each degree.
;; Also: POLY4 (BB13)
AddTerm:
    sta POLYPT
    sty POLYPT+1
    jsr FADD
    lda #TEMPF2                             ; x, for the next multiply
    ldy #>(TEMPF2)
    dec DEGREE
    bne NextTerm
    rts
.endproc

.endscope

;; The random number generator behind `RND`: the Lehmer "minimal standard".
;;
;; The seed, a long integer in <RNDX>, is multiplied by 16807 and reduced modulo 2^31-1, and `RND` gives the new seed
;; times 2^-31, between 0 and 1. (Apple's comments describe Microsoft's older generator, which swapped bytes of the
;; mantissa.) A seed of 0 or of a multiple of 2^31-1 becomes 0 and stays 0, so every `RND` after it gives 0.
.scope Random

;; The long integer 2^31-1, the generator's modulus.
;; Also: RMOD_C (BB13)
Modulus:
    .byte 0, 0, 0, 0
    .byte $7F, $FF, $FF, $FF

;; The long integer 16807, the generator's multiplier.
;; Also: RMUL_C (BB13)
Multiplier:
    .byte 0, 0, 0, 0
    .byte 0, 0, $41, $A7

;; The real 2^-31, which scales the seed to a number between 0 and 1.
;; Also: RSMAL_C (BB13)
Scale:
    .byte $62, $00, 0, 0
    .byte 0

.endscope

; `RND`.
.scope Functions continued

;; The `RND` function: the next pseudo-random number, between 0 and 1.
;;
;; `RND(0)` repeats the last number. A negative argument starts a new sequence from it: its mantissa, with the exponent
;; forced between $90 and $9F, becomes the seed, which is put through the generator three times. A positive argument
;; puts the seed through once. An argument whose seed is 2^31-1 (`RND(-2147483647)`) makes the seed 0, and every `RND`
;; after it 0, until a negative argument seeds it again.
;; In: FAC = the argument
;; Out: FAC = the number, VALTYP = 0
;; See: <Random>, <RNDX>
;; Also: RND (BB13)
.proc Rnd

;; The exponent a negative argument's mantissa is given: from $90 to $9F, 2^15 to 2^31.
SEED_EXPONENT = $90

;; The bits of the argument's exponent kept in <SEED_EXPONENT>'s place.
SEED_EXPONENT_BITS = $1F

    lda FACEXP
    beq ReturnSeed
    bit FACSGN
    bpl Next
    lsr FACSGN                              ; positive
    and #SEED_EXPONENT_BITS
    ora #SEED_EXPONENT
    sta FACEXP
    jsr Functions::ConvLong
    jsr Random::AdvanceFac                  ; the argument as the seed
    jsr Random::Advance

;; Takes the next number.
;; Also: RNDMAK (BB13)
Next:
    jsr Random::Advance

;; Gives the seed as a real between 0 and 1.
;; Also: GETRND (BB13)
ReturnSeed:
    jsr Random::LoadSeed
    jsr LongInteger::ToReal
    lda #<(Random::Scale)
    ldy #>(Random::Scale)
    ldx #0
    jmp FMULT
.endproc

.endscope

; The generator's steps.
.scope Random continued

;; Loads the seed, <RNDX>, into <FAC> as a long integer.
;; Out: FAC = the seed
;; Also: RNDONE (BB13)
.proc LoadSeed
    lda #RNDX
    ldy #>(RNDX)
    ldx #RNDXB
    jmp LongInteger::LoadFac
.endproc

;; Puts the seed in <RNDX> through the generator once.
;; Out: FAC = the new seed, RNDX = the new seed
;; Also: RNDIT (BB13)
.proc Advance
    jsr LoadSeed
    ; Falls into AdvanceFac.
.endproc

;; Puts the long integer in <FAC> through the generator, storing the result in <RNDX>: <FAC> * 16807 `MOD` (2^31-1).
;; In: FAC = the long integer, from 0 to 2^31
;; Out: FAC = the new seed, RNDX = the new seed
;; Uses: ARG, RES
;; Also: RNDAT (BB13)
.proc AdvanceFac
    jsr LongInteger::CopyFacToArg
    lda #<(Multiplier)
    ldy #>(Multiplier)
    ldx #RNDXB
    jsr LongInteger::LoadFac
    jsr LongInteger::Multiply
    jsr LongInteger::CopyFacToArg
    lda #<(Modulus)
    ldy #>(Modulus)
    ldx #0
    jsr LongInteger::LoadFac
    jsr LongInteger::Mod
    lda #RNDX
    ldy #>(RNDX)
    ldx #RNDXB
    jmp LongInteger::StoreFac
.endproc

.endscope

; `COS`, `SIN` and `TAN`.
.scope Functions continued

;; The `COS` function: the cosine of <FAC>, in radians, as `SIN(x + pi/2)`.
;; See: <Functions::Sin>
;; Also: COS (BB13)
.proc Cos
    lda #<(Float::HalfPi)
    ldy #>(Float::HalfPi)
    jsr FADD
    ; Falls into Sin.
.endproc

;; The `SIN` function: the sine of <FAC>, in radians.
;;
;; The angle is divided by 2 * pi and its integer part dropped, leaving a fraction of a turn. Symmetries fold that into
;; the quarter turn from -1/4 to 1/4, which <Float::SinePolynomial> takes. In the second and third quarters it flips
;; <TANSGN>, for `TAN`.
;; In: FAC = the angle
;; Out: FAC = the sine, TEMPF1 = the folded fraction of a turn
;; Entry:
;;   Reflect = negates <FAC>, then goes on with the fold; <Functions::Tan> enters here for the cosine
;; See: <Functions::Cos>, <Functions::Tan>, <Float::EvaluateOddPolynomial>
;; Also: SIN (BB13)
.proc Sin
    jsr MOVAF
    lda #<(Float::TwoPi)
    ldy #>(Float::TwoPi)
    ldx ARGSGN
    jsr FDIVF                               ; turns
    jsr MOVAF
    jsr INT
    lda #0
    sta ARISGN
    jsr FSUBT                               ; the fraction of a turn
    lda #<(Float::Quarter)
    ldy #>(Float::Quarter)
    jsr FSUB                                ; 1/4 - the fraction
    lda FACSGN
    pha
    bpl Reflect                             ; the first quarter
    jsr FADDH
    lda FACSGN
    bmi AddQuarter
    lda TANSGN
    eor #$FF
    sta TANSGN                              ; the second and third quarters

;; Negates <FAC> (<NEGOP>), the start of the fold.
;; Also: SIN1 (BB13)
Reflect:
    jsr NEGOP

;; Adds 1/4 and gives the folded fraction the quarter's sign.
;; Also: SIN2 (BB13)
AddQuarter:
    lda #<(Float::Quarter)
    ldy #>(Float::Quarter)
    jsr FADD
    pla
    bpl Approximate
    jsr NEGOP

;; Evaluates the sine polynomial on the folded fraction.
;; Also: SIN3 (BB13)
Approximate:
    lda #<(Float::SinePolynomial)
    ldy #>(Float::SinePolynomial)
    jmp Float::EvaluateOddPolynomial
.endproc

;; The `TAN` function: the tangent of <FAC>, in radians, as the sine over the cosine.
;;
;; After <Functions::Sin>, the folded fraction it leaves in <TEMPF1> is folded again through Cosine to give the cosine,
;; with <TANSGN> as its sign. <TEMPF1> is read back with <TEMPF3B> as its X-byte, which is <TEMPF1>'s too: both are
;; in zero page.
;; In: FAC = the angle
;; Out: FAC = the tangent
;; Errors: ERRDV0 = the cosine is zero
;; See: <Functions::Sin>
;; Also: TAN (BB13)
.proc Tan
    jsr MOV1F
    lda #0
    sta TANSGN
    jsr Sin
    ldx #TEMPF3
    lda #TEMPF3B
    ldy #>(TEMPF3)
    jsr MOVMF                               ; the sine into TEMPF3
    lda #TEMPF1
    ldx #TEMPF3B
    ldy #>(TEMPF1)
    jsr MOVFM                               ; the folded fraction from Sin
    lda #0
    sta FACSGN
    lda TANSGN
    jsr Cosine
    lda #TEMPF3
    ldy #>(TEMPF3)
    jmp FDIV                                ; the sine over the cosine

;; Finishes the cosine through <Functions::Sin>'s fold, with the sign in A.
;; In: FAC = the folded fraction's size, A = bit 7 set to negate the result
;; Also: COSC (BB13)
Cosine:
    pha
    jmp Sin::Reflect
.endproc

.endscope

; `SIN`'s constants.
.scope Float continued

;; The real 1.5707963267, pi/2.
;; Also: PI2 (BB13)
HalfPi:
    .byte $81, $49, $0F, $DA, $A2

;; The real 6.283185307, 2 * pi.
;; Also: TWOPI (BB13)
TwoPi:
    .byte $83, $49, $0F, $DA, $A2

;; The real 0.25, a quarter turn.
;; Also: FR4 (BB13)
Quarter:
    .byte $7F, $00, $00, $00, 0

;; `SIN`'s polynomial: sin(2 * pi * x) for x from -1/4 to 1/4, as an odd polynomial of six coefficients (a degree of
;; 5), highest power first.
;;
;; The ten bytes after it are Microsoft's signature, which no code reads.
;; See: <Float::EvaluateOddPolynomial>
;; Also: SINCON (BB13)
SinePolynomial:
    .byte 5                                 ; the degree
    .byte $84, $E6, $1A, $2D, $1B           ; -14.381383816, for x^11
    .byte $86, $28, $07, $FB, $F8           ; 42.07777095, for x^9
    .byte $87, $99, $68, $89, $01           ; -76.704133676, for x^7
    .byte $87, $23, $35, $DF, $E1           ; 81.605223690, for x^5
    .byte $86, $A5, $5D, $E7, $28           ; -41.34170209, for x^3
    .byte $83, $49, $0F, $DA, $A2           ; 6.2831853070, 2 * pi, for x
.assert * - SinePolynomial = 1 + 6 * PACKED_SIZE, "SIN's polynomial is a degree and six coefficients."

    ; Microsoft's signature, hidden here as in its other BASICs: "MICROSOFT!" backward, each byte exclusive-ored with
    ; $87. Nothing reads it.
    .byte $A6, $D3, $C1, $C8, $D4, $C8, $D5, $C4, $CE, $CA

.endscope

; `ATN`.
.scope Functions continued

;; The `ATN` function: the arctangent of <FAC>, in radians.
;;
;; Uses `ATN(-x) = -ATN(x)` to work on a positive x, and `ATN(x) = pi/2 - ATN(1/x)` to bring an x of 1 or more below 1,
;; where <Float::ArctangentPolynomial> takes it.
;; In: FAC = x
;; Out: FAC = the angle, from -pi/2 to pi/2
;; See: <Float::EvaluateOddPolynomial>
;; Also: ATN (BB13)
.proc Atn
    lda FACSGN
    pha                                     ; the sign, for the end
    bpl Positive
    jsr NEGOP

;; Takes the reciprocal of an x of 1 or more (an exponent of $81 or more).
;; Also: ATN1 (BB13)
Positive:
    lda FACEXP
    pha                                     ; the size, for the end
    cmp #$81
    bcc Approximate                         ; below 1
    lda #<(FONE)
    ldy #>(FONE)
    jsr FDIV                                ; 1/x

;; Evaluates the arctangent polynomial, then takes it from pi/2 if the reciprocal was taken.
;; Also: ATN2 (BB13)
Approximate:
    lda #<(Float::ArctangentPolynomial)
    ldy #>(Float::ArctangentPolynomial)
    jsr Float::EvaluateOddPolynomial
    pla
    cmp #$81
    bcc RestoreSign                         ; x was below 1
    lda #<(Float::HalfPi)
    ldy #>(Float::HalfPi)
    jsr FSUB                                ; pi/2 - the result

;; Gives the result the argument's sign.
;; Also: ATN3 (BB13)
RestoreSign:
    pla
    bpl Done
    jmp NEGOP

;; Returns.
;; Also: ATN4 (BB13)
Done:
    rts
.endproc

.endscope

; `ATN`'s constants.
.scope Float continued

;; `ATN`'s polynomial: the arctangent of x for x from 0 to 1, as an odd polynomial of twelve coefficients (a degree of
;; 11), highest power first; they are close to the series x - x^3/3 + x^5/5 - ...
;; See: <Float::EvaluateOddPolynomial>
;; Also: ATNCON (BB13)
ArctangentPolynomial:
    .byte $0B                               ; the degree
    .byte $76, $B3, $83, $BD, $D3           ; -0.0006847939119, for x^23
    .byte $79, $1E, $F4, $A6, $F5           ; 0.004850942156, for x^21
    .byte $7B, $83, $FC, $B0, $10           ; -0.01611170184, for x^19
    .byte $7C, $0C, $1F, $67, $CA           ; 0.03420963805, for x^17
    .byte $7C, $DE, $53, $CB, $C1           ; -0.05427913276, for x^15
    .byte $7D, $14, $64, $70, $4C           ; 0.07245719654, for x^13
    .byte $7D, $B7, $EA, $51, $7A           ; -0.08980239538, for x^11
    .byte $7D, $63, $30, $88, $7E           ; 0.1109324134, for x^9
    .byte $7E, $92, $44, $99, $3A           ; -0.1428398077, for x^7
    .byte $7E, $4C, $CC, $91, $C7           ; 0.1999991205, for x^5
    .byte $7F, $AA, $AA, $AA, $13           ; -0.3333333157, for x^3
    .byte $81, $00, $00, $00, $00           ; 1.0, for x
.assert * - ArctangentPolynomial = 1 + 12 * PACKED_SIZE, "ATN's polynomial is a degree and twelve coefficients."

.endscope
