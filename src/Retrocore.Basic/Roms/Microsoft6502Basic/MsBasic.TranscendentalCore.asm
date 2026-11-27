; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the square-root, power and negation routines.
.macro PowerRoutines

    .scope Functions continued

    ;; Takes the square root of <Fac> by raising it to one half.
    ;; Errors: <Functions::Log> reports an illegal quantity for a negative argument
    ;; Also: SQR (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Sqr
    jsr Float::CopyFacToArg
    lda #<Float::Half
    ldy #>Float::Half
    jsr Float::LoadFac
    ; Falls into Float::RaiseArg.
    .endproc
    .endscope

    .scope Float continued

    ;; Raises the argument accumulator to the power in <Fac> and returns the result in <Fac>.
    ;;
    ;; Any base to the zero power is one, and zero to any other power is zero. A negative base is accepted only for an
    ;; integer exponent; the parity of that exponent determines the sign. Otherwise the result is exp(exponent *
    ;; log(base)).
    ;; In: zero = set when the exponent is zero
    ;; Errors: illegal quantity for a negative base with a noninteger exponent
    ;; Also: FPWRT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc RaiseArg
    beq Functions::Exp
    lda ArgExponent
    bne NonzeroBase
    jmp SetExponentAndSign

;; Saves the power in <FloatTemporary3>; for a negative base checks the power is whole and takes its parity.
;; Also: FPWRT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NonzeroBase:
    ldx #FloatTemporary3
    ldy #0
    jsr StoreFac
    lda ArgSign
    bpl TakeLog
    jsr Functions::Int
    lda #FloatTemporary3
    ldy #0
    jsr Compare
    bne TakeLog
    tya
    ldy SmallInteger

;; <Fac> = Arg with its sign from A: positive for a negative base's whole power, so the parity negates the result,
;; and negative for a fractional power, which <Functions::Log> rejects. Then EXP(power * LOG(base)), negated for an
;; odd power.
;; Also: FPWR1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TakeLog:
    jsr CopyArgToFacWithSign
    tya
    pha
    jsr Functions::Log
    lda #FloatTemporary3
    ldy #0
    jsr MultiplyPacked
    jsr Functions::Exp
    pla
    lsr a
    bcc Negate::Done
    .endproc

    ;; Negates <Fac> unless its exponent is zero.
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: NEGOP (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Negate
    lda FacExponent
    beq Done
    lda FacSign
    eor #$FF
    sta FacSign

;; Returns without changing the result.
;; Also: NEGRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
    .endproc
    .endscope

.endmacro

;; Emits the five-byte-precision exponential routine.
.macro ExponentialRoutine

    .scope Functions continued

    ;; Computes e raised to <Fac>, returning the result in <Fac>.
    ;;
    ;; It multiplies by log2(e), keeps the integer part for scaling and evaluates <Float::ExponentialPolynomial> on the
    ;; reduced argument. A sufficiently negative argument underflows to zero.
    ;; Errors: floating-point overflow when the result is too large
    ;; Also: EXP (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Exp

    ;; Where <Functions::Exp> keeps the product's rounding byte while it splits off the integer part. The byte is
    ;; <FunctionJumpHigh>, which Microsoft's source names OLDOV here too.
    RoundingByte = FunctionJumpHigh

    lda #<Float::LogBase2OfE
    ldy #>Float::LogBase2OfE
    jsr Float::MultiplyPacked
    lda FacExtension
    adc #$50
    bcc CheckRange
    jsr Float::Round::Increment

;; Saves the rounding byte, copies <Fac> to Arg; exponent $88 or more is out of range.
;; Also: STOLD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckRange:
    sta RoundingByte
    jsr Float::CopyFacToArgUnrounded
    lda FacExponent
    cmp #$88
    bcc Reduce

;; <Float::ExponentOutOfRange>: the <ERROR_OVERFLOW> error for a large positive argument, zero for a large negative one.
;; Also: GOMLDV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
OutOfRange:
    jsr Float::ExponentOutOfRange

;; Takes the integer part (<Functions::Int>) for the power of two and keeps the fraction.
;; Also: EXP1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Reduce:
    jsr Int
    lda SmallInteger
    clc
    adc #$81
    beq OutOfRange
    sec
    sbc #1
    pha
    ldx #5

;; Exchanges <Fac> and Arg byte by byte.
;; Also: SWAPLP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SwapLoop:
    lda ArgExponent,x
    ldy FacExponent,x
    sta FacExponent,x
    sty ArgExponent,x
    dex
    bpl SwapLoop
    lda RoundingByte
    sta FacExtension
    jsr Float::SubtractFromArg
    jsr Float::Negate
    lda #<Float::ExponentialPolynomial
    ldy #>Float::ExponentialPolynomial
    jsr Float::EvaluatePolynomial
    lda #0
    sta ResultSign
    pla
    jsr Float::AddExponent
    rts
    .endproc
    .endscope

.endmacro

;; Emits the polynomial evaluators for five-byte coefficients.
.macro PolynomialRoutines

    .scope Float continued

    ;; Evaluates X * P(X squared) for X in <Fac>.
    ;; In: A = low byte of coefficient table, Y = high byte of coefficient table
    ;; Out: Fac = polynomial result
    ;; See: <Float::EvaluatePolynomial>
    ;; Also: POLYX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc EvaluateOddPolynomial
    sta PolynomialPointer
    sty PolynomialPointer+1
    jsr StoreFacInTemporary1
    lda #FloatTemporary1
    jsr MultiplyPacked
    jsr EvaluateStoredPolynomial
    lda #FloatTemporary1
    ldy #0
    jmp MultiplyPacked
    .endproc

    ;; Evaluates a polynomial at <Fac> using Horner's method.
    ;;
    ;; The table starts with the degree (the number of coefficients minus one), followed by five-byte coefficients
    ;; from highest power to constant.
    ;; In: A = low byte of table, Y = high byte of table
    ;; Out: Fac = polynomial result
    ;; Also: POLY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc EvaluatePolynomial
    sta PolynomialPointer
    sty PolynomialPointer+1
    .endproc

    ;; Uses the table already saved in <PolynomialPointer>.
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: POLY1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc EvaluateStoredPolynomial
    jsr StoreFacInTemporary2
    lda (PolynomialPointer),y
    sta PolynomialDegree
    ldy PolynomialPointer
    iny
    tya
    bne SetPointer
    inc PolynomialPointer+1

;; Stores the first coefficient's address.
;; Also: POLY3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SetPointer:
    sta PolynomialPointer
    ldy PolynomialPointer+1

;; Multiplies by the coefficient at Y:A on the first pass, and by x (<FloatTemporary2>) on later ones, and steps to
;; the next coefficient.
;; Also: POLY2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextTerm:
    jsr MultiplyPacked
    lda PolynomialPointer
    ldy PolynomialPointer+1
    clc
    adc #5
    bcc AddTerm
    iny

;; Adds the coefficient; loops <PolynomialDegree> times.
;; Also: POLY4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
AddTerm:
    sta PolynomialPointer
    sty PolynomialPointer+1
    jsr AddPacked
    lda #FloatTemporary2
    ldy #0
    dec PolynomialDegree
    bne NextTerm

;; Returns the current floating-point result.
;; Also: RANDRT (M6502)
Done:
    rts
    .endproc
    .endscope

.endmacro

;; Emits the sine, cosine and tangent routines.
.macro TrigonometricRoutines

    .scope Functions continued

    ;; Computes cosine of <Fac> in radians by adding pi/2 and falling into <Functions::Sin>.
    ;; Also: COS (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Cos
    lda #<Float::HalfPi
    ldy #>Float::HalfPi
    jsr Float::AddPacked
    .endproc

    ;; Computes sine of <Fac> in radians.
    ;;
    ;; Division by 2*pi removes whole turns; quadrant identities reduce the remaining fraction for
    ;; <Float::SinePolynomial>. <TangentSign> records a quadrant change for <Functions::Tan>.
    ;; Entry:
    ;;   Reflect = Negates <Fac> (<Float::Negate>)
    ;; Also: SIN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Sin
    jsr Float::CopyFacToArg
    lda #<Float::TwoPi
    ldy #>Float::TwoPi
    ldx ArgSign
    jsr Float::DivideArgByPacked
    jsr Float::CopyFacToArg
    jsr Int
    lda #0
    sta ResultSign
    jsr Float::SubtractFromArg
    lda #<Float::Quarter
    ldy #>Float::Quarter
    jsr Float::SubtractFromPacked
    lda FacSign
    pha
    bpl Reflect
    jsr Float::AddHalf
    lda FacSign
    bmi AddQuarter
    lda TangentSign
    eor #$FF
    sta TangentSign

;; Negates <Fac> (<Float::Negate>).
;; Also: SIN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Reflect:
    jsr Float::Negate

;; Adds Quarter; restores a negative quadrant's sign.
;; Also: SIN2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
AddQuarter:
    lda #<Float::Quarter
    ldy #>Float::Quarter
    jsr Float::AddPacked
    pla
    bpl Approximate
    jsr Float::Negate

;; Points Y:A at <Float::SinePolynomial>.
;; Also: SIN3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Approximate:
    lda #<Float::SinePolynomial
    ldy #>Float::SinePolynomial

;; Evaluates the odd polynomial addressed by A and Y via <Float::EvaluateOddPolynomial>.
;; Also: GPOLYX (M6502)
ToEvaluateOddPolynomial:
    jmp Float::EvaluateOddPolynomial
    .endproc

    ;; Computes tangent of <Fac> in radians as sine divided by cosine.
    ;;
    ;; The sine is saved; the cosine is computed from the magnitude of the reduced argument <Functions::Sin> leaves in
    ;; <FloatTemporary1>, which replaces the input stored there first, and the quadrant sign.
    ;; Also: TAN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Tan
    jsr Float::StoreFacInTemporary1
    lda #0
    sta TangentSign
    jsr Sin
    ldx #FloatTemporary3
    ldy #0
    jsr Rnd::ToStoreFac
    lda #FloatTemporary1
    ldy #0
    jsr Float::LoadFac
    lda #0
    sta FacSign
    lda TangentSign
    jsr Cosine
    lda #FloatTemporary3
    ldy #0

;; Divides the sine by the cosine through <Float::DividePacked>.
ToDividePacked:
    jmp Float::DividePacked

;; Continues the cosine calculation using the quadrant sign in A from <Functions::Tan>.
;; Also: COSC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Cosine:
    pha
    jmp Sin::Reflect
    .endproc
    .endscope

.endmacro

;; Emits the arctangent routine that uses <Float::ArctangentPolynomial>.
.macro ArctangentRoutine

    .scope Functions continued

    ;; Computes arctangent of <Fac> in radians.
    ;;
    ;; It reduces the magnitude to at most one using atan(x) = pi/2 - atan(1/x), evaluates
    ;; <Float::ArctangentPolynomial>, then restores the original sign.
    ;; Also: ATN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Atn
    lda FacSign
    pha
    bpl Positive
    jsr Float::Negate

;; Pushes the exponent; a magnitude of 1 or more takes the reciprocal (One / <Fac>).
;; Also: ATN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Positive:
    lda FacExponent
    pha
    cmp #$81
    bcc Approximate
    lda #<Float::One
    ldy #>Float::One
    jsr Float::DividePacked

;; Evaluates <Float::ArctangentPolynomial> and subtracts from <Float::HalfPi> if the reciprocal was taken.
;; Also: ATN2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Approximate:
    lda #<Float::ArctangentPolynomial
    ldy #>Float::ArctangentPolynomial
    jsr Float::EvaluateOddPolynomial
    pla
    cmp #$81
    bcc RestoreSign
    lda #<Float::HalfPi
    ldy #>Float::HalfPi
    jsr Float::SubtractFromPacked

;; Negates for a negative argument.
;; Also: ATN3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RestoreSign:
    pla
    bpl Done
    jmp Float::Negate

;; The rts.
;; Also: ATN4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
    .endproc
    .endscope

.endmacro
