; retrocore: style=strict
;; Integer arithmetic and <CHK at OpCHK>: the handlers for <ABI at OpABI>, <ADI at OpADI>, <NGI at OpNGI>,
;; <SBI at OpSBI>, <MPI at OpMPI>, <SQI at OpSQI>, <DVI at OpDVI> and <MODI at OpMODI>, the multiply and divide they
;; share with the array handlers, and <CHK at OpCHK>, the range check.

;; <ABI at OpABI>: replaces the integer on top of the stack with its absolute value.
.proc OpABI
    ; Pop the integer: X = its low byte, A = its high byte.
    pla
    tax
    pla
    bmi Negative

    ; Positive: push it back as it was.
    pha
    txa
    pha
    jmp Fetch::Skip1

    ; Negative: push its two's complement.
Negative:
    tay
    clc
    txa
    eor #$FF
    adc #1
    tax
    tya
    eor #$FF
    adc #0
    pha
    txa
    pha
    jmp Fetch::Skip1
.endproc

;; <ADI at OpADI>: pops two integers and pushes their sum.
.proc OpADI

;; The integer that was on top.
Addend = Pointer

    ; Pop the top integer.
    pla
    sta Addend
    pla
    sta Addend+1

    ; Pop the one below it: Y = its low byte, X = its high byte.
    pla
    tay
    pla
    tax

    ; Add, and push the sum.
    tya
    clc
    adc Addend
    tay
    txa
    adc Addend+1
    pha
    tya
    pha
    jmp Fetch::Skip1
.endproc

;; <NGI at OpNGI>: replaces the integer on top of the stack with its two's complement.
.proc OpNGI
    ; Negate the low byte, keeping it in X.
    pla
    eor #$FF
    clc
    adc #1
    tax

    ; Negate the high byte with the carry, and push the result.
    pla
    eor #$FF
    adc #0
    pha
    txa
    pha
    jmp Fetch::Skip1
.endproc

;; <SBI at OpSBI>: pops two integers and pushes the lower one less the top one.
.proc OpSBI

;; The integer that was on top, which is subtracted.
Subtrahend = Pointer

    ; Pop the top integer.
    pla
    sta Subtrahend
    pla
    sta Subtrahend+1

    ; Pop the one below it: Y = its low byte, X = its high byte.
    pla
    tay
    pla
    tax

    ; Subtract, and push the difference.
    tya
    sec
    sbc Subtrahend
    tay
    txa
    sbc Subtrahend+1
    pha
    tya
    pha
    jmp Fetch::Skip1
.endproc

;; Multiplies two 16-bit numbers into a 32-bit product, by 16 rounds of shifting the multiplier right and adding the
;; multiplicand to the product's high word for each 1 bit, then shifting the product right.
;; In: Multiplicand = one number, Multiplier = the other
;; Out: Product = the product's low word, ProductHigh = its high word, Multiplier = destroyed
;; Keeps: Y
.proc Multiply

;; The number added in for each 1 bit of <Multiplier>.
Multiplicand = Work2

;; The number whose bits are shifted out, low bit first.
Multiplier = Work3

;; The product's low word, which the product's bits are shifted into.
Product = Work4

;; The product's high word, which the multiplicand is added to.
ProductHigh = Address

    ; Clear the high word. The low word's old bits are all shifted out.
    lda #0
    sta ProductHigh+1
    sta ProductHigh
    ldx #WORD_BITS

    ; Shift the multiplier's next bit out, and add the multiplicand to the high word if it is 1.
NextBit:
    ror Multiplier+1
    ror Multiplier
    bcc Shift
    lda ProductHigh
    clc
    adc Multiplicand
    sta ProductHigh
    lda ProductHigh+1
    adc Multiplicand+1
    sta ProductHigh+1

    ; Shift the 32-bit product right, with the addition's carry as its new top bit.
Shift:
    ror ProductHigh+1
    ror ProductHigh
    ror Product+1
    ror Product
    dex
    bne NextBit
    rts
.endproc

;; <MPI at OpMPI>: pops two integers and pushes the low word of their product.
;;
;; The low word is the same for signed numbers as for unsigned ones, so it multiplies them as they are, except that
;; when both are negative it negates both first, which leaves the low word as it was.
.proc OpMPI
    ; Pop the top integer as the multiplier. Is it negative?
    pla
    sta Multiply::Multiplier
    pla
    sta Multiply::Multiplier+1
    bmi MultiplierNegative

    ; No: pop the other as the multiplicand, and multiply.
    pla
    sta Multiply::Multiplicand
    pla
    sta Multiply::Multiplicand+1
    jmp Calculate

    ; Yes: pop the multiplicand. If it is positive too, multiply.
MultiplierNegative:
    pla
    sta Multiply::Multiplicand
    pla
    sta Multiply::Multiplicand+1
    bpl Calculate

    ; Both are negative: negate both.
    lda Multiply::Multiplier
    eor #$FF
    clc
    adc #1
    sta Multiply::Multiplier
    lda Multiply::Multiplier+1
    eor #$FF
    adc #0
    sta Multiply::Multiplier+1
    lda Multiply::Multiplicand
    eor #$FF
    clc
    adc #1
    sta Multiply::Multiplicand
    lda Multiply::Multiplicand+1
    eor #$FF
    adc #0
    sta Multiply::Multiplicand+1

    ; Multiply, and push the product's low word.
Calculate:
    jsr Multiply
    lda Multiply::Product+1
    pha
    lda Multiply::Product
    pha
    jmp Fetch::Skip1
.endproc

;; <SQI at OpSQI>: replaces the integer on top of the stack with the low word of its square, by pushing a copy and
;; running <MPI at OpMPI>.
.proc OpSQI
    ; Push a copy of the integer on top.
    tsx
    lda Stack+2,x
    pha
    lda Stack+1,x
    pha
    jmp OpMPI
.endproc

;; Divides one integer by another: makes both positive, remembering whether the quotient is negative, and divides
;; the magnitudes by shifting the divisor right a bit each round and subtracting it where it fits. A dividend
;; below 256 takes 8 rounds, and any other 16. Reports <ERROR_DIVIDE_BY_ZERO> when the divisor is 0.
;; In: Divisor = the divisor, Remainder = the dividend
;; Out:
;;   Quotient = the magnitudes' quotient
;;   Remainder = the magnitudes' remainder
;;   QuotientSign = 0 when the quotient is positive, nonzero when it must be negated
;;   Divisor = destroyed
.proc Divide

;; The divisor, made positive; then the high word of the 32-bit divisor that is shifted right.
Divisor = Work1

;; The dividend, made positive, which the divisor is subtracted from, leaving the remainder.
Remainder = Work2

;; 1 added for a negative divisor and 1 taken for a negative dividend: 0 when the signs agree.
QuotientSign = Work3

;; The quotient, which a bit is shifted into each round.
Quotient = Work4

;; The low word of the 32-bit divisor that is shifted right: the divisor times a power of 2, tried against the
;; remainder once the high word is 0.
Trial = Address

    ; Clear the sign, the trial divisor and the quotient.
    ldy #0
    sty QuotientSign
    sty Trial
    sty Trial+1
    sty Quotient
    sty Quotient+1

    ; A divisor of 0 is an error.
    lda Divisor
    bne DivisorSign
    lda Divisor+1
    bne DivisorSign
    jmp ExecutionError::DivideByZero

    ; Make the divisor positive, counting its sign.
DivisorSign:
    lda Divisor+1
    bpl DividendSign
    lda Divisor
    eor #$FF
    clc
    adc #1
    sta Divisor
    lda Divisor+1
    eor #$FF
    adc #0
    sta Divisor+1
    inc QuotientSign

    ; Make the dividend positive, counting its sign.
DividendSign:
    lda Remainder+1
    bpl Compare
    lda Remainder
    eor #$FF
    clc
    adc #1
    sta Remainder
    lda Remainder+1
    eor #$FF
    adc #0
    sta Remainder+1
    dec QuotientSign

    ; If the dividend is less than the divisor, the quotient is 0 and the remainder is the dividend, which this
    ; copies onto itself.
Compare:
    sec
    lda Remainder
    sbc Divisor
    lda Remainder+1
    sbc Divisor+1
    bcs SetUpShift
    sty Quotient
    sty Quotient+1
    lda Remainder
    sta Remainder
    lda Remainder+1
    sta Remainder+1
    rts

    ; The 32-bit divisor is Divisor:Trial, the divisor times 65536, for 16 rounds. A dividend below 256 has a
    ; divisor below 256 too: make it the divisor times 256 instead, Divisor+1 being 0, for 8 rounds.
SetUpShift:
    clc
    ldx #WORD_BITS
    lda Remainder+1
    bne Round
    lda Divisor
    sta Trial+1
    lda Divisor+1
    sta Divisor
    ldx #8

    ; Shift the 32-bit divisor right a bit. While its high word is not 0, it is too big: the quotient's bit is 0.
Round:
    clc
    ror Divisor+1
    bne ShiftHighLow
    ror Divisor
    bne ShiftLow

    ; The high word is 0: finish the shift, and subtract the trial divisor if it fits.
TryTrial:
    ror Trial+1
    ror Trial
    lda Remainder
    sec
    sbc Trial
    tay
    lda Remainder+1
    sbc Trial+1
    bcc QuotientBit

    ; It fits: keep the difference, and shift a 1 into the quotient. The high word stays 0 from now on.
    sta Remainder+1
    sty Remainder
    sec
    rol Quotient
    rol Quotient+1
    dex
    clc
    bne TryTrial
    rts

    ; Finish the shift of a divisor whose high word is not 0.
ShiftHighLow:
    ror Divisor
ShiftLow:
    ror Trial+1
    ror Trial
    clc

    ; Shift the round's bit, carry, into the quotient.
QuotientBit:
    rol Quotient
    rol Quotient+1
    dex
    bne Round
    rts
.endproc

;; <DVI at OpDVI>: pops a divisor and a dividend below it, and pushes their quotient, rounded toward 0.
.proc OpDVI
    ; Pop the divisor and the dividend, and divide.
    pla
    sta Divide::Divisor
    pla
    sta Divide::Divisor+1
    pla
    sta Divide::Remainder
    pla
    sta Divide::Remainder+1
    jsr Divide

    ; Negate the quotient if the signs differed.
    lda Divide::QuotientSign
    beq Push
    lda Divide::Quotient
    eor #$FF
    clc
    adc #1
    sta Divide::Quotient
    lda Divide::Quotient+1
    eor #$FF
    adc #0
    sta Divide::Quotient+1

    ; Push the quotient.
Push:
    lda Divide::Quotient+1
    pha
    lda Divide::Quotient
    pha
    jmp Fetch::Skip1
.endproc

;; <MODI at OpMODI>: pops a divisor and a dividend below it, and pushes the remainder of their magnitudes, which is
;; never negative.
.proc OpMODI
    ; Pop the divisor and the dividend, and divide.
    pla
    sta Divide::Divisor
    pla
    sta Divide::Divisor+1
    pla
    sta Divide::Remainder
    pla
    sta Divide::Remainder+1
    jsr Divide

    ; Push the remainder.
    lda Divide::Remainder+1
    pha
    lda Divide::Remainder
    pha
    jmp Fetch::Skip1
.endproc

;; <CHK at OpCHK>: pops an upper and a lower bound, and reports <ERROR_VALUE_RANGE> unless the integer below them, which
;; it leaves on the stack, is between them, the bounds included.
.proc OpCHK

;; The upper bound, which was on top.
Upper = Pointer

;; The lower bound.
Lower = Pointer2

;; A copy of the integer being checked.
Value = ProcedureNumber

    ; Pop the bounds, and copy the integer below them.
    pla
    sta Upper
    pla
    sta Upper+1
    pla
    sta Lower
    pla
    sta Lower+1
    tsx
    lda Stack+1,x
    sta Value
    lda Stack+2,x
    sta Value+1

    ; Is it at least the lower bound? If the signs differ, it is when it is positive.
    eor Lower+1
    bmi LowerSigns
    lda Lower+1
    cmp Value+1
    bcc CheckUpper
    bne OutOfRange
    lda Value
    cmp Lower
    bcs CheckUpper
    bcc OutOfRange
LowerSigns:
    lda Value+1
    bmi OutOfRange

    ; Is it at most the upper bound? If the signs differ, it is when it is negative.
CheckUpper:
    lda Upper+1
    eor Value+1
    bmi UpperSigns
    lda Value+1
    cmp Upper+1
    bcc InRange
    bne OutOfRange
    lda Upper
    cmp Value
    bcs InRange
    bcc OutOfRange
UpperSigns:
    lda Value+1
    bpl OutOfRange

InRange:
    jmp Fetch::Skip1

OutOfRange:
    jmp ExecutionError::ValueRange
.endproc
