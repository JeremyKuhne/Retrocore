; retrocore: style=strict
;; Floating point: the real arithmetic handlers, <FLO at Pcodes::FloatNextToTop> and <FLT at Pcodes::FloatTop>, and the
;; standard procedures <TNC at StandardProcedures::Truncate>, <RND at StandardProcedures::Round> and
;; <POT at StandardProcedures::PowerOfTen>.
;;
;; A real is 4 bytes, pushed high word first: the high word holds the sign (bit 15), an 8-bit exponent biased by
;; <REAL_BIAS> (bits 14-7), and the mantissa's top 7 bits; the low word holds its low 16 bits. The mantissa's top
;; bit, always 1, is not stored, and a real with exponent 0 is 0.0. The routines unpack reals into 6 bytes of zero
;; page (see <REAL_SIGN>) to work on them.

; Reals.

;; The exponent of 1.0, which every exponent is biased by.
REAL_BIAS = $7F

;; The exponent no result may reach: a routine whose result's exponent reaches it reports a floating point error.
REAL_EXPONENT_OVERFLOW = $FF

;; The guard byte's bit 0, which a right shift of the mantissa sets when it shifts out a 1, so the result is known
;; to be inexact.
GUARD_STICKY = $01

;; The bits of a mantissa, with its hidden 1.
MANTISSA_BITS = 24

;; The quotient bits <Pcodes::DivideReals> works out: the mantissa's and the guard byte's.
QUOTIENT_BITS = 32

;; With X = S, as TSX leaves it, the offset from <Stack> of the real on top of the stack's high byte: its sign and
;; the exponent's top 7 bits.
TOP_REAL_SIGN = 4

;; With X = S, the offset from <Stack> of the next byte of the real on top of the stack: the exponent's low bit and
;; the mantissa's top 7 bits.
TOP_REAL_EXPONENT_LOW = 3

;; The powers of ten <POT at StandardProcedures::PowerOfTen> has, 1.0E0 to 1.0E38.
POWERS_OF_TEN = 39

;; One entry of <RealMath::PowersOfTen>: a real, its high word first, as <POT at StandardProcedures::PowerOfTen> pushes
;; it.
;; Parameters:
;;   power = the power of ten it is; the entries go in order from 0
;;   high = the real's high word: the sign, the exponent and the mantissa's top 7 bits
;;   low = its low word: the mantissa's low 16 bits
.macro PowerOfTen power, high, low
    .assert * = PowersOfTen + REAL_SIZE * power, "PowersOfTen's entries are in order of their powers."
    .word high, low
.endmacro

;; The floating-point routines, which pop reals into the unpacked reals <RealMath::Right> and <RealMath::Left>, work on
;; them into <Result>, and push <Result>.
.scope RealMath

;; The right operand, unpacked: the real on top of the stack, which a handler pops first. It is the only operand of
;; <SQR at Pcodes::SquareReal>, <TNC at StandardProcedures::Truncate> and <RND at StandardProcedures::Round>.
;; Also: FPREG1 (WK11)
Right = Pointer

;; The left operand, unpacked: the real below the right one.
;; Also: FPREG2 (WK11)
Left = Buffer

;; The return address of a routine that pulls or pushes a real under it, kept while it does.
CallerReturn = Work2

;; Pops a real and unpacks it: the sign in bit 7, the exponent, the mantissa with its hidden 1 restored, and a guard
;; byte of 0.
;; In: X = the unpacked real to fill: <Right>, <Left> or <Result>
;; Keeps: X, Y
;; Also: PULLFP (WK11)
.proc PopReal
    ; Take the return address off the stack, to reach the real under it.
    pla
    sta CallerReturn
    pla
    sta CallerReturn+1

    ; Clear the guard byte, the sign and the exponent.
    lda #0
    sta REAL_GUARD,x
    sta REAL_SIGN,x
    sta REAL_EXPONENT,x

    ; The low word is the mantissa's two low bytes.
    pla
    sta REAL_MANTISSA+2,x
    pla
    sta REAL_MANTISSA+1,x

    ; The high word's low byte: its bit 7 is the exponent's low bit, and the rest the mantissa's top bits, under
    ; the hidden 1.
    pla
    rol a
    rol REAL_EXPONENT,x
    sec
    ror a
    sta REAL_MANTISSA,x

    ; Its high byte: the sign, then the exponent's top 7 bits.
    pla
    clc
    rol a
    ror REAL_SIGN,x
    ora REAL_EXPONENT,x
    sta REAL_EXPONENT,x

    ; Return past the JSR, whose address is one less than the return's.
    inc CallerReturn
    bne Return
    inc CallerReturn+1
Return:
    jmp (CallerReturn)
.endproc

;; Packs an unpacked real and pushes it, changing the unpacked real's exponent. Its guard byte is dropped, so it
;; must already be rounded.
;; In: X = the unpacked real: <Right>, <Left> or <Result>
;; Keeps: X, Y
;; Also: PUSHFP (WK11)
.proc PushReal
    ; Take the return address off the stack, to push the real under it.
    pla
    sta CallerReturn
    pla
    sta CallerReturn+1

    ; The high word's high byte: the sign, then the exponent's top 7 bits.
    lda REAL_EXPONENT,x
    clc
    ror a
    ora REAL_SIGN,x
    pha

    ; Its low byte: the exponent's low bit in place of the hidden 1.
    lda REAL_MANTISSA,x
    rol a
    ror REAL_EXPONENT,x
    ror a
    pha

    ; The low word: the mantissa's two low bytes.
    lda REAL_MANTISSA+1,x
    pha
    lda REAL_MANTISSA+2,x
    pha

    ; Return past the JSR, whose address is one less than the return's.
    inc CallerReturn
    bne Return
    inc CallerReturn+1
Return:
    jmp (CallerReturn)
.endproc

;; Takes a carry out of <Result>'s mantissa back in: when carry is set, shifts the mantissa right with the carry as its
;; top bit, keeping <GUARD_STICKY>, and raises the exponent. When the exponent reaches <REAL_EXPONENT_OVERFLOW>, it
;; drops its return address and reports <ERROR_FLOATING_POINT>.
;; In: carry = set when the mantissa overflowed
;; Keeps: X, Y
.proc ShiftResultRight
    bcc Done

    ; Shift the carry in, keeping a 1 shifted out of the guard byte as its sticky bit.
    ror Result+REAL_MANTISSA
    ror Result+REAL_MANTISSA+1
    ror Result+REAL_MANTISSA+2
    ror Result+REAL_GUARD
    bcc RaiseExponent
    lda #GUARD_STICKY
    ora Result+REAL_GUARD
    sta Result+REAL_GUARD

    ; Raise the exponent.
RaiseExponent:
    inc Result+REAL_EXPONENT
    lda #REAL_EXPONENT_OVERFLOW
    cmp Result+REAL_EXPONENT
    bne Done

    ; It overflowed: drop the return address and report the error.
    pla
    pla
    jmp ExecutionError::FloatingPoint

Done:
    rts
.endproc

;; Shifts <Result>'s mantissa left until its top bit is set, lowering the exponent a step each shift. Only the guard
;; byte's top bit is shifted into the mantissa, on the first shift. When the exponent reaches 0, it drops its return
;; address and reports <ERROR_FLOATING_POINT>.
;; Keeps: X, Y
.proc NormalizeResult
    ; Already normalized?
    lda Result+REAL_MANTISSA
    bmi Done

    ; Shift the guard byte's top bit into the mantissa.
    clc
    rol Result+REAL_GUARD

    ; Shift the mantissa left a bit.
NextShift:
    rol Result+REAL_MANTISSA+2
    rol Result+REAL_MANTISSA+1
    rol Result+REAL_MANTISSA
    bmi Normalized

    ; Lower the exponent, and shift again unless it reached 0.
    clc
    dec Result+REAL_EXPONENT
    bne NextShift
    beq Underflow

    ; The top bit is set: lower the exponent for this last shift.
Normalized:
    dec Result+REAL_EXPONENT
    bne Done

    ; It underflowed: drop the return address and report the error.
Underflow:
    pla
    pla
    jmp ExecutionError::FloatingPoint

Done:
    rts
.endproc

;; Rounds <Result>'s mantissa on its guard byte, to nearest, and to even when the guard byte is exactly half. It leaves
;; the guard byte shifted left.
;; Out: carry = set when the mantissa overflowed to 0, for <ShiftResultRight>
;; Keeps: X, Y
.proc RoundResult
    ; Is the guard byte half or more?
    clc
    rol Result+REAL_GUARD
    bcc Done

    ; Round up.
    inc Result+REAL_MANTISSA+2
    bne RoundToEven
    inc Result+REAL_MANTISSA+1
    bne RoundToEven
    inc Result+REAL_MANTISSA

    ; Exactly half: clear the low bit, rounding to even.
RoundToEven:
    lda Result+REAL_GUARD
    bne CheckOverflow
    lsr Result+REAL_MANTISSA+2
    asl Result+REAL_MANTISSA+2

    ; Did the mantissa overflow to 0?
CheckOverflow:
    lda Result+REAL_MANTISSA
    clc
    bne Done
    sec

Done:
    rts
.endproc

;; Aligns <Right> and <Left> for an addition or subtraction: shifts the smaller one's mantissa right until its exponent
;; would match the larger, keeping <GUARD_STICKY>.
;; Out: Result = the larger exponent, as its exponent
;; Keeps: Y
.proc AlignReals
    ; Take Right's exponent. Is Left's larger?
    lda Right+REAL_EXPONENT
    sta Result+REAL_EXPONENT
    sec
    sbc Left+REAL_EXPONENT
    bcs RightNotSmaller

    ; Left's is larger: take it, and shift Right by the difference.
    eor #$FF
    tax
    inx
    lda Left+REAL_EXPONENT
    sta Result+REAL_EXPONENT
NextRightShift:
    lsr Right+REAL_MANTISSA
    ror Right+REAL_MANTISSA+1
    ror Right+REAL_MANTISSA+2
    ror Right+REAL_GUARD
    bcc CountRightShift
    lda #GUARD_STICKY
    ora Right+REAL_GUARD
    sta Right+REAL_GUARD
CountRightShift:
    dex
    bne NextRightShift

    ; Right's is larger, or they are equal (as they are after shifting Right): shift Left by the difference.
RightNotSmaller:
    beq Done
    tax
NextLeftShift:
    lsr Left+REAL_MANTISSA
    ror Left+REAL_MANTISSA+1
    ror Left+REAL_MANTISSA+2
    ror Left+REAL_GUARD
    bcc CountLeftShift
    lda #GUARD_STICKY
    ora Left+REAL_GUARD
    sta Left+REAL_GUARD
CountLeftShift:
    dex
    bne NextLeftShift

Done:
    rts
.endproc

;; Adds <Right>'s and <Left>'s magnitudes into <Result>, and rounds it. The caller sets <Result>'s sign.
;; Keeps: Y
;; Also: FADD (WK11)
.proc AddMantissas
    ; Align them, and add.
    jsr AlignReals
    clc
    lda Right+REAL_GUARD
    adc Left+REAL_GUARD
    sta Result+REAL_GUARD
    lda Right+REAL_MANTISSA+2
    adc Left+REAL_MANTISSA+2
    sta Result+REAL_MANTISSA+2
    lda Right+REAL_MANTISSA+1
    adc Left+REAL_MANTISSA+1
    sta Result+REAL_MANTISSA+1
    lda Right+REAL_MANTISSA
    adc Left+REAL_MANTISSA
    sta Result+REAL_MANTISSA

    ; Take the sum's carry in, round, and take the rounding's carry in.
    jsr ShiftResultRight
    jsr RoundResult
    jsr ShiftResultRight
    rts
.endproc

;; Subtracts <Right>'s magnitude from <Left>'s, which must be no smaller, into <Result>, and normalizes and rounds it. A
;; difference whose mantissa is 0 is 0.0. The caller sets <Result>'s sign otherwise.
;; Keeps: Y
;; Also: FSUB (WK11)
.proc SubtractMantissas
    ; Align them, and subtract.
    jsr AlignReals
    sec
    lda Left+REAL_GUARD
    sbc Right+REAL_GUARD
    sta Result+REAL_GUARD
    lda Left+REAL_MANTISSA+2
    sbc Right+REAL_MANTISSA+2
    sta Result+REAL_MANTISSA+2
    lda Left+REAL_MANTISSA+1
    sbc Right+REAL_MANTISSA+1
    sta Result+REAL_MANTISSA+1
    lda Left+REAL_MANTISSA
    sbc Right+REAL_MANTISSA
    sta Result+REAL_MANTISSA

    ; A mantissa of 0, whatever the guard byte, makes 0.0.
    lda Result+REAL_MANTISSA
    bne NotZero
    lda Result+REAL_MANTISSA+1
    bne NotZero
    lda Result+REAL_MANTISSA+2
    bne NotZero
    lda #0
    sta Result+REAL_EXPONENT
    sta Result+REAL_SIGN
    rts

    ; Normalize, round, and take the rounding's carry in.
NotZero:
    jsr NormalizeResult
    jsr RoundResult
    jsr ShiftResultRight
    rts
.endproc

;; Swaps <Right>'s and <Left>'s magnitudes, if need be, so that <Left>'s is no smaller. Their signs stay; the guard
;; bytes, 0 from <PopReal>, are not swapped.
;; Out:
;;   A = the sign of the operand whose magnitude is larger (<Left>'s when they are equal)
;;   carry = set when they were not swapped
;; Also: FCMP (WK11)
.proc OrderOperands
    ; Compare the magnitudes: the exponents, then the mantissas from the top.
    lda Right+REAL_EXPONENT
    cmp Left+REAL_EXPONENT
    bcc NoSwap
    bne Swap
    lda Right+REAL_MANTISSA
    cmp Left+REAL_MANTISSA
    bcc NoSwap
    bne Swap
    lda Right+REAL_MANTISSA+1
    cmp Left+REAL_MANTISSA+1
    bcc NoSwap
    bne Swap
    lda Right+REAL_MANTISSA+2
    cmp Left+REAL_MANTISSA+2
    bcc NoSwap
    bne Swap
    lda Right+REAL_GUARD
    cmp Left+REAL_GUARD
    bcc NoSwap
    bne Swap

    ; Left's is no smaller.
NoSwap:
    lda Left+REAL_SIGN
    sec
    rts

    ; Right's is larger: swap the exponents and mantissas.
Swap:
    ldx Right+REAL_EXPONENT
    ldy Left+REAL_EXPONENT
    sty Right+REAL_EXPONENT
    stx Left+REAL_EXPONENT
    ldx Right+REAL_MANTISSA
    ldy Left+REAL_MANTISSA
    sty Right+REAL_MANTISSA
    stx Left+REAL_MANTISSA
    ldx Right+REAL_MANTISSA+1
    ldy Left+REAL_MANTISSA+1
    sty Right+REAL_MANTISSA+1
    stx Left+REAL_MANTISSA+1
    ldx Right+REAL_MANTISSA+2
    ldy Left+REAL_MANTISSA+2
    sty Right+REAL_MANTISSA+2
    stx Left+REAL_MANTISSA+2
    lda Right+REAL_SIGN
    clc
    rts
.endproc

.endscope

; Pcodes: AddReals, SubtractReals and DivideReals.
.scope Pcodes continued

;; <ADR at Pcodes::AddReals>: pops two reals and pushes their sum.
;; Also: ADR (A2POSRM, WK11)
.proc AddReals
    ; Pop the right operand, then the left.
    ldx #RealMath::Right
    jsr RealMath::PopReal
    ldx #RealMath::Left
    jsr RealMath::PopReal

    ; When either is 0.0, the sum is the other.
    lda RealMath::Right+REAL_EXPONENT
    bne RightNotZero
    ldx #RealMath::Left
    jsr RealMath::PushReal
    jmp Fetch::Skip1
RightNotZero:
    lda RealMath::Left+REAL_EXPONENT
    bne BothNotZero
    ldx #RealMath::Right
    jsr RealMath::PushReal
    jmp Fetch::Skip1

    ; The same signs: add the magnitudes, under that sign.
BothNotZero:
    lda RealMath::Right+REAL_SIGN
    eor RealMath::Left+REAL_SIGN
    bne SignsDiffer
    lda RealMath::Right+REAL_SIGN
    sta Result+REAL_SIGN
    jsr RealMath::AddMantissas
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1

    ; Different signs: subtract the smaller magnitude from the larger, under the larger's sign.
SignsDiffer:
    jsr RealMath::OrderOperands
    sta Result+REAL_SIGN
    jsr RealMath::SubtractMantissas
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc

;; <SBR at Pcodes::SubtractReals>: pops two reals and pushes the left one minus the right one.
;; Also: SBR (A2POSRM, WK11)
.proc SubtractReals
    ; Pop the right operand, then the left.
    ldx #RealMath::Right
    jsr RealMath::PopReal
    ldx #RealMath::Left
    jsr RealMath::PopReal

    ; Subtracting 0.0 leaves the left one.
    lda RealMath::Right+REAL_EXPONENT
    bne RightNotZero
    ldx #RealMath::Left
    jsr RealMath::PushReal
    jmp Fetch::Skip1

    ; From 0.0, the difference is the right one negated.
RightNotZero:
    lda RealMath::Left+REAL_EXPONENT
    bne BothNotZero
    lda RealMath::Right+REAL_SIGN
    eor #REAL_NEGATIVE
    sta RealMath::Right+REAL_SIGN
    ldx #RealMath::Right
    jsr RealMath::PushReal
    jmp Fetch::Skip1

    ; Different signs: add the magnitudes, under the left one's sign.
BothNotZero:
    lda RealMath::Right+REAL_SIGN
    eor RealMath::Left+REAL_SIGN
    beq SignsSame
    lda RealMath::Left+REAL_SIGN
    sta Result+REAL_SIGN
    jsr RealMath::AddMantissas
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1

    ; The same signs: subtract the smaller magnitude from the larger, under their sign, negated when the right
    ; one's was larger.
SignsSame:
    jsr RealMath::OrderOperands
    bcs SetSign
    eor #REAL_NEGATIVE
SetSign:
    sta Result+REAL_SIGN
    jsr RealMath::SubtractMantissas
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc

;; <DVR at Pcodes::DivideReals>: pops two reals and pushes the left one divided by the right one.
;; Also: DVR (A2POSRM, UCSD20, WK11)
.proc DivideReals

;; The trial difference's mantissa low byte, and at Difference+1 its guard byte, kept until the subtraction is known
;; to fit.
Difference = Work1

    ; Pop the right operand, then the left.
    ldx #RealMath::Right
    jsr RealMath::PopReal
    ldx #RealMath::Left
    jsr RealMath::PopReal

    ; Dividing by 0.0 is an error.
    lda RealMath::Right+REAL_EXPONENT
    bne RightNotZero
    jmp ExecutionError::DivideByZero

    ; 0.0 divided by anything is 0.0.
RightNotZero:
    lda RealMath::Left+REAL_EXPONENT
    bne BothNotZero
    lda #0
    pha
    pha
    pha
    pha
    jmp Fetch::Skip1

    ; The quotient's sign, and its exponent: the difference of theirs, biased.
BothNotZero:
    lda RealMath::Right+REAL_SIGN
    eor RealMath::Left+REAL_SIGN
    sta Result+REAL_SIGN
    lda RealMath::Left+REAL_EXPONENT
    sec
    sbc RealMath::Right+REAL_EXPONENT
    bcc Smaller

    ; Left's exponent is no smaller: the biased one must stay below REAL_EXPONENT_OVERFLOW.
    clc
    adc #REAL_BIAS
    bcs OutOfRange
    cmp #REAL_EXPONENT_OVERFLOW
    beq OutOfRange
    bcc SetExponent

    ; Left's is smaller: the biased one must stay above 0.
Smaller:
    adc #REAL_BIAS
    beq OutOfRange
    bpl SetExponent
OutOfRange:
    jmp ExecutionError::FloatingPoint
SetExponent:
    sta Result+REAL_EXPONENT

    ; Divide, a quotient bit at a time: subtract Right's mantissa from Left's when it fits, and shift it right.
    ldx #QUOTIENT_BITS
NextBit:
    sec
    lda RealMath::Left+REAL_GUARD
    sbc RealMath::Right+REAL_GUARD
    sta Difference+1
    lda RealMath::Left+REAL_MANTISSA+2
    sbc RealMath::Right+REAL_MANTISSA+2
    sta Difference
    lda RealMath::Left+REAL_MANTISSA+1
    sbc RealMath::Right+REAL_MANTISSA+1
    tay
    lda RealMath::Left+REAL_MANTISSA
    sbc RealMath::Right+REAL_MANTISSA
    bcc ShiftQuotient

    ; It fits: keep the difference, and make the bit 1.
    sta RealMath::Left+REAL_MANTISSA
    sty RealMath::Left+REAL_MANTISSA+1
    lda Difference
    sta RealMath::Left+REAL_MANTISSA+2
    lda Difference+1
    sta RealMath::Left+REAL_GUARD
    sec

    ; Shift the bit into Result's mantissa, and Right's mantissa right.
ShiftQuotient:
    rol Result+REAL_GUARD
    rol Result+REAL_MANTISSA+2
    rol Result+REAL_MANTISSA+1
    rol Result+REAL_MANTISSA
    lsr RealMath::Right+REAL_MANTISSA
    ror RealMath::Right+REAL_MANTISSA+1
    ror RealMath::Right+REAL_MANTISSA+2
    ror RealMath::Right+REAL_GUARD
    dex
    bne NextBit

    ; Normalize, round, and push the quotient.
    jsr RealMath::NormalizeResult
    jsr RealMath::RoundResult
    jsr RealMath::ShiftResultRight
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc
.endscope

; RealMath: MultiplyOperands.
.scope RealMath continued

;; Multiplies <Right> and <Left>, neither 0.0, into <Result>, and rounds it. When the product's exponent is out of
;; range, it drops its return address and reports <ERROR_FLOATING_POINT>.
;; Out:
;;   Result = the product
;;   Right = its exponent less <REAL_BIAS>, and its mantissa shifted out to 0
;; Keeps: Y
.proc MultiplyOperands
    ; The product's sign, and its exponent: the sum of theirs, which must stay in range.
    lda Right+REAL_SIGN
    eor Left+REAL_SIGN
    sta Result+REAL_SIGN
    lda Right+REAL_EXPONENT
    sec
    sbc #REAL_BIAS
    sta Right+REAL_EXPONENT
    lda Left+REAL_EXPONENT
    sec
    sbc #REAL_BIAS
    clv
    clc
    adc Right+REAL_EXPONENT
    bvc Biased

    ; It is out of range: drop the return address and report the error.
OutOfRange:
    pla
    pla
    jmp ExecutionError::FloatingPoint

    ; Bias it: it must be above 0 and below REAL_EXPONENT_OVERFLOW.
Biased:
    clc
    adc #REAL_BIAS
    beq OutOfRange
    cmp #REAL_EXPONENT_OVERFLOW
    beq OutOfRange
    sta Result+REAL_EXPONENT

    ; Clear the product.
    lda #0
    sta Result+REAL_MANTISSA
    sta Result+REAL_MANTISSA+1
    sta Result+REAL_MANTISSA+2
    sta Result+REAL_GUARD

    ; Multiply a bit of Right's mantissa at a time, from the bottom: add Left's mantissa for a 1.
    ldx #MANTISSA_BITS
NextBit:
    lsr Right+REAL_MANTISSA
    ror Right+REAL_MANTISSA+1
    ror Right+REAL_MANTISSA+2
    bcc CountBit
    clc
    lda Result+REAL_MANTISSA+2
    adc Left+REAL_MANTISSA+2
    sta Result+REAL_MANTISSA+2
    lda Result+REAL_MANTISSA+1
    adc Left+REAL_MANTISSA+1
    sta Result+REAL_MANTISSA+1
    lda Result+REAL_MANTISSA
    adc Left+REAL_MANTISSA
    sta Result+REAL_MANTISSA
CountBit:
    dex
    beq Round

    ; Shift the product right with the addition's carry, keeping GUARD_STICKY, for the next bit.
    ror Result+REAL_MANTISSA
    ror Result+REAL_MANTISSA+1
    ror Result+REAL_MANTISSA+2
    ror Result+REAL_GUARD
    bcc NextBit
    lda Result+REAL_GUARD
    ora #GUARD_STICKY
    sta Result+REAL_GUARD
    jmp NextBit

    ; Take the last addition's carry in, round, and take the rounding's carry in.
Round:
    jsr ShiftResultRight
    jsr RoundResult
    jsr ShiftResultRight
    rts
.endproc

.endscope

; Pcodes: MultiplyReals, SquareReal, AbsoluteReal and NegateReal.
.scope Pcodes continued

;; <MPR at Pcodes::MultiplyReals>: pops two reals and pushes their product.
;; Also: MPR (A2POSRM, WK11)
.proc MultiplyReals
    ; Pop the right operand, then the left.
    ldx #RealMath::Right
    jsr RealMath::PopReal
    ldx #RealMath::Left
    jsr RealMath::PopReal

    ; When either is 0.0, so is the product.
    lda RealMath::Right+REAL_EXPONENT
    beq Zero
    lda RealMath::Left+REAL_EXPONENT
    beq Zero
    bne Multiply
Zero:
    lda #0
    pha
    pha
    pha
    pha
    jmp Fetch::Skip1

    ; Multiply them, and push the product.
Multiply:
    jsr RealMath::MultiplyOperands
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc

;; <SQR at Pcodes::SquareReal>: pops a real and pushes its square.
;; Also: SQR (A2POSRM, UCSD20, WK11)
.proc SquareReal
    ; Pop it. The square of 0.0 is 0.0.
    ldx #RealMath::Right
    jsr RealMath::PopReal
    lda RealMath::Right+REAL_EXPONENT
    bne NotZero
    lda #0
    pha
    pha
    pha
    pha
    jmp Fetch::Skip1

    ; Copy it to Left, and multiply them.
NotZero:
    lda RealMath::Right+REAL_SIGN
    sta RealMath::Left+REAL_SIGN
    lda RealMath::Right+REAL_EXPONENT
    sta RealMath::Left+REAL_EXPONENT
    lda RealMath::Right+REAL_MANTISSA
    sta RealMath::Left+REAL_MANTISSA
    lda RealMath::Right+REAL_MANTISSA+1
    sta RealMath::Left+REAL_MANTISSA+1
    lda RealMath::Right+REAL_MANTISSA+2
    sta RealMath::Left+REAL_MANTISSA+2
    lda RealMath::Right+REAL_GUARD
    sta RealMath::Left+REAL_GUARD
    jsr RealMath::MultiplyOperands
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc

;; <ABR at Pcodes::AbsoluteReal>: clears the sign bit of the real on top of the stack, making it its absolute value.
;; Also: ABR (A2POSRM, UCSD20, WK11)
.proc AbsoluteReal
    ; Point X at the real's high byte, TOP_REAL_SIGN past S.
    tsx
    inx
    inx
    inx
    inx

    ; Shift the sign bit out, and a 0 in.
    asl Stack,x
    lsr Stack,x
    jmp Fetch::Skip1
.endproc

;; <NGR at Pcodes::NegateReal>: flips the sign bit of the real on top of the stack, unless it is 0.0.
;; Also: NGR (A2POSRM, UCSD20, WK11)
.proc NegateReal

;; The real's high word's low byte: the exponent's low bit, then the mantissa's top 7 bits.
ExponentLow = Pointer

;; The real's high byte, the sign and the exponent's top 7 bits, then shifted up to the exponent.
Exponent = Pointer2

    ; Put the exponent together: is it 0?
    tsx
    lda Stack+TOP_REAL_EXPONENT_LOW,x
    sta ExponentLow
    lda Stack+TOP_REAL_SIGN,x
    sta Exponent
    rol ExponentLow
    rol Exponent
    beq Done

    ; Flip the sign bit, in the high byte, TOP_REAL_SIGN past S.
    inx
    inx
    inx
    inx
    lda Stack,x
    eor #REAL_NEGATIVE
    sta Stack,x

Done:
    jmp Fetch::Skip1
.endproc
.endscope

; RealMath: PopIntegerAsReal.
.scope RealMath continued

;; Pops an integer and converts it to a real in <Result>, leaving <Result>'s guard byte as it was. It never returns for
;; -32768: its magnitude, $8000, already has bit 15 set, and the normalizing loop shifts before it tests, so it
;; shifts the bit out and loops on 0.
;; Out: Result = the integer, as a real
;; Also: FLOAT (WK11)
.proc PopIntegerAsReal

;; The integer, then its magnitude, shifted up until its top bit is 1.
Integer = Work1

    ; Take the return address off the stack, to reach the integer under it.
    pla
    sta CallerReturn
    pla
    sta CallerReturn+1

    ; Pop the integer. 0 is 0.0.
    pla
    sta Integer
    pla
    sta Integer+1
    lda Integer+1
    bne NotZero
    lda Integer
    bne NotZero
    lda #0
    sta Result+REAL_SIGN
    sta Result+REAL_EXPONENT
    sta Result+REAL_MANTISSA
    sta Result+REAL_MANTISSA+1
    sta Result+REAL_MANTISSA+2
    beq Return

    ; Take the sign, and the magnitude.
NotZero:
    lda #0
    sta Result+REAL_SIGN
    lda Integer+1
    bpl Normalize
    clc
    lda Integer
    eor #$FF
    adc #1
    sta Integer
    lda Integer+1
    eor #$FF
    adc #0
    sta Integer+1
    lda #REAL_NEGATIVE
    sta Result+REAL_SIGN

    ; Shift the magnitude up until bit 15 is 1. The exponent starts at bit 15's, and each shift lowers it.
Normalize:
    ldx #REAL_BIAS + 15
NextShift:
    dex
    asl Integer
    rol Integer+1
    bpl NextShift

    ; The exponent, and the magnitude as the mantissa's top 16 bits.
    stx Result+REAL_EXPONENT
    lda Integer+1
    sta Result+REAL_MANTISSA
    lda Integer
    sta Result+REAL_MANTISSA+1
    lda #0
    sta Result+REAL_MANTISSA+2

    ; Return past the JSR, whose address is one less than the return's.
Return:
    inc CallerReturn
    bne JumpBack
    inc CallerReturn+1
JumpBack:
    jmp (CallerReturn)
.endproc

.endscope

; Pcodes: FloatNextToTop and FloatTop.
.scope Pcodes continued

;; <FLO at Pcodes::FloatNextToTop>: converts the integer under the real on top of the stack to a real.
;; Also: FLO (A2POSRM, UCSD20, WK11)
.proc FloatNextToTop

;; The real on top of the stack, its 4 bytes as they were pulled from the top, kept while the integer under it is
;; converted.
SavedReal = Pointer2

    ; Keep the real on top.
    pla
    sta SavedReal+3
    pla
    sta SavedReal+2
    pla
    sta SavedReal+1
    pla
    sta SavedReal

    ; Convert the integer.
    jsr RealMath::PopIntegerAsReal
    ldx #Result
    jsr RealMath::PushReal

    ; Put the real back on top.
    lda SavedReal
    pha
    lda SavedReal+1
    pha
    lda SavedReal+2
    pha
    lda SavedReal+3
    pha
    jmp Fetch::Skip1
.endproc

;; <FLT at Pcodes::FloatTop>: converts the integer on top of the stack to a real.
;; Also: FLT (A2POSRM, UCSD20, WK11)
.proc FloatTop
    jsr RealMath::PopIntegerAsReal
    ldx #Result
    jsr RealMath::PushReal
    jmp Fetch::Skip1
.endproc
.endscope

; RealMath: TruncateReal.
.scope RealMath continued

;; Converts <Right> to an integer, truncating toward 0, or rounding to nearest (half away from 0) when
;; <RealMath::TruncateReal::Rounding> is not 0. When the integer does not fit 15 bits and a sign, it drops its return
;; address and reports <ERROR_FLOATING_POINT>.
;; In: TruncateReal::Rounding = 0 to truncate, or 1 to round
;; Out:
;;   TruncateReal::IntegerHigh = the integer's high byte
;;   TruncateReal::IntegerLow = its low byte
;; Also: FIX (WK11)
.proc TruncateReal

;; Whether to round: not 0 to round, 0 to truncate.
Rounding = Work1

;; The integer's high byte, out of <Right>'s mantissa.
IntegerHigh = Right + REAL_MANTISSA

;; The integer's low byte.
IntegerLow = Right + REAL_MANTISSA + 1

;; The fraction's top 8 bits, under the integer.
Fraction = Right + REAL_MANTISSA + 2

    ; The bits to shift the mantissa right, less one: none for 2^14, the largest exponent that fits.
    sec
    lda #REAL_BIAS + 14
    sbc Right+REAL_EXPONENT
    bcs InRange

    ; It is too large: drop the return address and report the error.
TooLarge:
    pla
    pla
    jmp ExecutionError::FloatingPoint

    ; Below 2^-9, every bit shifts out: it is 0.
InRange:
    tax
    cpx #MANTISSA_BITS
    bmi Shift
    lda #0
    sta IntegerHigh
    sta IntegerLow
    sta Fraction
    rts

    ; Shift the mantissa right, leaving the integer in its top 2 bytes and the fraction under it.
Shift:
    lsr IntegerHigh
    ror IntegerLow
    ror Fraction
    dex
    bpl Shift

    ; Round up when asked and the fraction is half or more; it must still fit.
    lda Rounding
    beq Sign
    lda Fraction
    bpl Sign
    inc IntegerLow
    bne Sign
    inc IntegerHigh
    bpl Sign
    jmp TooLarge

    ; Negate it for a negative real.
Sign:
    lda Right+REAL_SIGN
    bpl Done
    lda IntegerHigh
    eor #$FF
    sta IntegerHigh
    lda IntegerLow
    eor #$FF
    clc
    adc #1
    sta IntegerLow
    bcc Done
    inc IntegerHigh

Done:
    rts
.endproc

.endscope

; StandardProcedures: Round, Truncate and PowerOfTen.
.scope StandardProcedures continued

;; <RND at StandardProcedures::Round>, the standard procedure ROUND: pops a real and pushes the integer nearest it, half
;; away from 0.
;; Also: RND (A2POSRM, WK11), ROUND (UCSD20)
.proc Round
    lda #1
    sta RealMath::TruncateReal::Rounding
    ldx #RealMath::Right
    jsr RealMath::PopReal
    jsr RealMath::TruncateReal
    lda RealMath::TruncateReal::IntegerHigh
    pha
    lda RealMath::TruncateReal::IntegerLow
    pha
    jmp Fetch::Skip2
.endproc

;; <TNC at StandardProcedures::Truncate>, the standard procedure TRUNC: pops a real and pushes its integer part.
;; Also: TNC (A2POSRM, WK11), TRUNC (UCSD20)
.proc Truncate
    lda #0
    sta RealMath::TruncateReal::Rounding
    ldx #RealMath::Right
    jsr RealMath::PopReal
    jsr RealMath::TruncateReal
    lda RealMath::TruncateReal::IntegerHigh
    pha
    lda RealMath::TruncateReal::IntegerLow
    pha
    jmp Fetch::Skip2
.endproc

;; <POT at StandardProcedures::PowerOfTen>, the standard procedure PWROFTEN: pops an integer, 0 to <POWERS_OF_TEN> - 1,
;; and pushes ten to that power, from <RealMath::PowersOfTen>.
;; Also: POT (A2POSRM), PWR10 (WK11), PWROFTEN (UCSD20)
.proc PowerOfTen
    ; Pop the power. Its high byte must be 0, and its low byte below POWERS_OF_TEN; BPL tests the difference's bit
    ; 7, so 167 to 255 pass too, and read entry n mod 64: a power for 192 to 230, and the bytes past PowersOfTen for
    ; the rest.
    pla
    tax
    pla
    bne OutOfRange
    cpx #POWERS_OF_TEN
    bpl OutOfRange

    ; Push its entry, the high word first, high byte first.
    txa
    asl a
    asl a
    tax
    lda RealMath::PowersOfTen+1,x
    pha
    lda RealMath::PowersOfTen,x
    pha
    lda RealMath::PowersOfTen+3,x
    pha
    lda RealMath::PowersOfTen+2,x
    pha
    jmp Fetch::Skip2

    ; Out of range: push 0.0 and report the error.
OutOfRange:
    lda #0
    pha
    pha
    pha
    pha
    jmp ExecutionError::FloatingPoint
.endproc
.endscope

; RealMath: PowersOfTen.
.scope RealMath continued

;; The reals 1.0E0 to 1.0E38, for <POT at StandardProcedures::PowerOfTen>, each with its high word first.
;; Also: P10TBL (WK11)
PowersOfTen:
    PowerOfTen 0, $3F80, $0000
    PowerOfTen 1, $4120, $0000
    PowerOfTen 2, $42C8, $0000
    PowerOfTen 3, $447A, $0000
    PowerOfTen 4, $461C, $4000
    PowerOfTen 5, $47C3, $5000
    PowerOfTen 6, $4974, $2400
    PowerOfTen 7, $4B18, $9680
    PowerOfTen 8, $4CBE, $BC20
    PowerOfTen 9, $4E6E, $6B28
    PowerOfTen 10, $5015, $02F9
    PowerOfTen 11, $51BA, $43B7
    PowerOfTen 12, $5368, $D4A5
    PowerOfTen 13, $5511, $84E7
    PowerOfTen 14, $56B5, $E621
    PowerOfTen 15, $5863, $5FA9
    PowerOfTen 16, $5A0E, $1BCA
    PowerOfTen 17, $5BB1, $A2BC
    PowerOfTen 18, $5D5E, $0B6B
    PowerOfTen 19, $5F0A, $C723
    PowerOfTen 20, $60AD, $78EC
    PowerOfTen 21, $6258, $D727
    PowerOfTen 22, $6407, $8678
    PowerOfTen 23, $65A9, $6816
    PowerOfTen 24, $6753, $C21C
    PowerOfTen 25, $6904, $5951
    PowerOfTen 26, $6AA5, $6FA6
    PowerOfTen 27, $6C4E, $CB8F
    PowerOfTen 28, $6E01, $3F39
    PowerOfTen 29, $6FA1, $8F08
    PowerOfTen 30, $7149, $F2CA
    PowerOfTen 31, $72FC, $6F7C
    PowerOfTen 32, $749D, $C5AE
    PowerOfTen 33, $7645, $3719
    PowerOfTen 34, $77F6, $84DF
    PowerOfTen 35, $799A, $130C
    PowerOfTen 36, $7B40, $97CE
    PowerOfTen 37, $7CF0, $BDC2
    PowerOfTen 38, $7E96, $769C
.endscope
