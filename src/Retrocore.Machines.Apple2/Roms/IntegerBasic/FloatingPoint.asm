; retrocore: style=strict ignore=unlinked-name:BASIC -- BASIC is the language, not its entry point
;; Integer BASIC: Wozniak and Rankin's floating point ($F425-$F4FF)
;;
;; Steve Wozniak and Roy Rankin's floating-point arithmetic, which shares the Integer BASIC chips; Integer BASIC
;; itself never calls it. It adds, subtracts, multiplies and divides 32-bit numbers, and converts 16-bit integers to
;; and from them. The last two routines, <Float::ShiftTowardInteger> and <Float::ToInteger>, come after the
;; Mini-Assembler, at $F63D (MiniAssembler.asm).
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978), kept as each definition's historical names.
;; Part of IntegerBasic.asm; it follows Operators.asm, at $F425.

;; Wozniak and Rankin's floating-point package: two accumulators in page zero and the routines that work on them.
;;
;; A number is 4 bytes: an exponent, biased by <Float::EXPONENT_BIAS> (so $80 means 2^0), then a 24-bit two's
;; complement mantissa, high byte first, with the binary point after its top two bits. A normalized mantissa has its
;; top two bits different, so its size is from 1 up to 2. FP1 (<Float::Exponent1> and <Float::Mantissa1>) holds the
;; first operand and the result, and FP2 (<Float::Exponent2> and <Float::Mantissa2>) the second. <Float::Extension>
;; extends <Float::Mantissa1> while multiplying and dividing.
;;
;; The page-zero bytes are $F3-$FF, which Integer BASIC uses too (for <AutoIncrement>, <AutoNumbering>, <GoSubIndex>
;; and others), so a program can use the package only while BASIC is not running. On overflow the routines jump to
;; <Float::OverflowJump>, in page 3, where the program puts a JMP to its handler.
.scope Float

; The package's numbers.

;; What the exponent byte adds to the power of 2, so that $80 is 2^0 and a byte below $80 a negative power.
EXPONENT_BIAS = $80

;; The exponent of a 16-bit integer in the mantissa's top two bytes: 2^14, as the binary point is after the
;; mantissa's top two bits. <Float::FromInteger> starts from it, and <Float::ToInteger> shifts down to it.
INTEGER_EXPONENT = EXPONENT_BIAS + 14

;; The bytes of a mantissa.
MANTISSA_BYTES = 3

;; The bytes of a number: the exponent and the mantissa.
NUMBER_BYTES = 1 + MANTISSA_BYTES

;; The mantissa's top two bits: they differ in a normalized mantissa.
TOP_TWO_BITS = $C0

;; The steps of a division, one quotient bit each; a multiplication takes one more.
DIVIDE_STEPS = 23

; The package's page zero.

;; How many operands <Float::MakeOperandsPositive> made positive: its low bit is set when one of the two was
;; negative, so that the product or quotient must be negated.
;;
;; <Float::MakeOperandsPositive> shifts it left and <Float::PositiveAndSwap> adds 1 for each negative operand it makes
;; positive; <Float::FinishMultiplyDivide> shifts the bit out to decide.
;; Also: SIGN (A2RM78)
SignCount = $F3

;; FP2's exponent, biased by <Float::EXPONENT_BIAS>.
;; Also: X2 (A2RM78)
Exponent2 = $F4

;; FP2's mantissa (3 bytes, high byte first): the second operand.
;; Also: M2 (A2RM78)
Mantissa2 = $F5

;; FP1's exponent, biased by <Float::EXPONENT_BIAS>.
;; Also: X1 (A2RM78)
Exponent1 = $F8

;; FP1's mantissa (3 bytes, high byte first): the first operand and the result.
;;
;; <Float::FromInteger> takes a 16-bit integer in its first two bytes, high byte first, and <Float::ToInteger> leaves
;; one there.
;; Also: M1 (A2RM78)
Mantissa1 = $F9

;; The extension of <Float::Mantissa1> (4 bytes): <Float::Swap> leaves a copy of a mantissa here, and
;; <Float::Multiply> shifts the multiplier through it while <Float::Divide> holds the divisor in it.
;; Also: E (A2RM78)
Extension = $FC

;; Where the floating-point routines jump on overflow: a JMP the program using them stores in page 3.
;;
;; It is the same location as AppleSoft's ampersand jump.
;; See: <Float::Overflow>
;; Also: OVLOC (A2RM78)
OverflowJump = $03F5

;; Adds the mantissas: <Mantissa1> = <Mantissa1> + <Mantissa2>.
;; Out: carry = the carry out of the high bytes, overflow = set when the signed sum overflowed, X = $FF
;; Uses: A
;; Keeps: Y
;; Also: ADD (A2RM78)
.proc AddMantissas
    clc
    ldx #MANTISSA_BYTES - 1

;; Also: ADD1 (A2RM78)
NextByte:
    lda Mantissa1,x
    adc Mantissa2,x
    sta Mantissa1,x
    dex
    bpl NextByte
    rts
.endproc

;; Prepares for multiplying or dividing: makes both mantissas positive and counts the negative ones in
;; <Float::SignCount>.
;;
;; It calls <Float::PositiveAndSwap> for FP1, which swaps the accumulators, then falls into it for the other, which
;; swaps them back. A negative operand is negated and normalized, so its exponent may change.
;; Out: A = <Exponent2>, Y = <Exponent1>, X = 0, carry = set, Extension..Extension+2 = <Mantissa1>
;; Errors: jumps to <Float::OverflowJump> when an operand of -2 with the largest exponent is made positive
;; Also: MD1 (A2RM78)
.proc MakeOperandsPositive
    asl SignCount
    jsr PositiveAndSwap
    ; Falls into PositiveAndSwap.
.endproc

;; Makes <Float::Mantissa1> positive, adding 1 to <Float::SignCount> if it was negative, then swaps FP1 and FP2 with
;; the carry set.
;; Out: A = the new <Exponent2>, Y = the new <Exponent1>, X = 0, carry = set,
;;   Extension..Extension+2 = the new <Mantissa1>
;; Errors: jumps to <Float::OverflowJump> as <Float::Negate> does
;; Also: ABSWAP (A2RM78)
.proc PositiveAndSwap
    bit Mantissa1
    bpl Positive
    jsr Negate
    inc SignCount

;; Sets the carry for the multiply or divide that follows.
;; Also: ABSWAP1 (A2RM78)
Positive:
    sec
    ; Falls into Swap.
.endproc

;; Exchanges FP1 and FP2, leaving in <Float::Extension> a copy of the mantissa that moves to FP1.
;;
;; X counts 4 to 1, from the mantissas' low bytes to the exponents. Each byte that moves to FP1 is stored again on the
;; next pass at <Extension>-1,X: <Extension>+2 down to <Extension>. <Extension>+3 gets Y.
;; In: Y = what to store at <Extension>+3
;; Out: A = the new <Exponent2>, Y = the new <Exponent1>, X = 0, Extension..Extension+2 = the new <Mantissa1>
;; Keeps: carry
;; Also: SWAP (A2RM78)
.proc Swap
    ldx #NUMBER_BYTES

;; Also: SWAP1 (A2RM78)
NextByte:
    sty Extension - 1,x
    lda Exponent1 - 1,x
    ldy Exponent2 - 1,x
    sty Exponent1 - 1,x
    sta Exponent2 - 1,x
    dex
    bne NextByte
    rts
.endproc

;; Converts the 16-bit integer in <Mantissa1> (high byte) and <Mantissa1>+1 to floating point in FP1.
;;
;; At $F451. The exponent starts at <Float::INTEGER_EXPONENT>, the scale of an integer in the mantissa's top 16 bits,
;; and normalizing adjusts it. <Mantissa1>+2 is taken as the fraction: 0 for a whole number.
;; In: Mantissa1, Mantissa1+1 = the integer, Mantissa1+2 = its fraction
;; Out: Exponent1/Mantissa1 = the number
;; Keeps: X, Y
;; Also: FLOAT (A2RM78)
.proc FromInteger
.assert * = $F451, "Float::FromInteger must stay at $F451, where programs call FLOAT."
    lda #INTEGER_EXPONENT
    sta Exponent1
    ; Falls into Normalize.
.endproc

;; Normalizes FP1: shifts the mantissa left, one less in the exponent each time, until its top two bits differ or the
;; exponent reaches 0.
;;
;; A mantissa of 0 is shifted until the exponent is 0, which is how the package's 0 ends up with an exponent of 0.
;; Out: Exponent1/Mantissa1 = the number, normalized
;; Keeps: X, Y
;; Entry:
;;   CheckExponent = returns at once when the exponent is already 0
;; Also: NORM1 (A2RM78)
.proc Normalize

    ; Mantissa1 less $C0 is negative exactly when its top two bits differ ($40 to $BF).
    lda Mantissa1
    cmp #TOP_TWO_BITS
    bmi Done
    dec Exponent1
    asl Mantissa1 + 2
    rol Mantissa1 + 1
    rol Mantissa1

;; Normalizes unless the exponent is 0.
;; Also: NORM (A2RM78)
CheckExponent:
    lda Exponent1
    bne Normalize

;; Also: RTS1 (A2RM78)
Done:
    rts
.endproc

;; Subtracts: FP1 = FP2 - FP1.
;;
;; At $F468. It negates FP1 and adds.
;; Out: Exponent1/Mantissa1 = the difference
;; Errors: jumps to <Float::OverflowJump> on overflow
;; Entry:
;;   Align = aligns the operands, then adds: <Float::Add> enters here until the exponents agree
;; See: <Float::Add>, <Float::Negate>
;; Also: FSUB (A2RM78)
.proc Subtract
.assert * = $F468, "Float::Subtract must stay at $F468, where programs call FSUB."
    jsr Negate

;; Swaps the operands or shifts FP1 right, as <Float::Align> does, then adds.
;; Also: SWPALGN (A2RM78)
Align:
    jsr Float::Align
    ; Falls into Add.
.endproc

;; Adds: FP1 = FP1 + FP2.
;;
;; At $F46E. While the exponents differ, the operand with the smaller one goes to FP1 and is shifted right
;; (<Float::Align>); then the mantissas are added and the sum normalized. A sum that overflows is shifted back right,
;; with the carry as its sign.
;; Out: Exponent1/Mantissa1 = the sum
;; Errors: jumps to <Float::OverflowJump> on overflow
;; Entry:
;;   Finish = normalizes the mantissa, or after a signed overflow shifts it right with the carry as its sign:
;;     <Float::Negate> ends here
;; See: <Float::Subtract>, <Float::AddMantissas>, <Float::Normalize>
;; Also: FADD (A2RM78)
.proc Add
.assert * = $F46E, "Float::Add must stay at $F46E, where programs call FADD."
    lda Exponent2
    cmp Exponent1
    bne Subtract::Align
    jsr AddMantissas

;; Normalizes, or after a signed overflow shifts the mantissa right with the carry as its sign.
;; Also: ADDEND (A2RM78)
Finish:
    bvc Normalize::CheckExponent
    bvs ShiftRight::ShiftInCarry
.endproc

;; Aligns the operands for adding: swaps them if FP2's exponent is the smaller, otherwise shifts FP1 right one place.
;; In: carry = set when <Exponent2> is not below <Exponent1>, as a compare of the two leaves it
;; Also: ALGNSWP (A2RM78)
.proc Align
    bcc Swap
    ; Falls into ShiftRight.
.endproc

;; Shifts FP1 right one place, arithmetically (the sign stays), adding 1 to the exponent.
;;
;; The six bytes shifted are <Mantissa1> and the first three of <Extension>, so the bit shifted out of the mantissa
;; goes into the extension, and the carry is the bit shifted out of <Extension>+2.
;; Out: X = 0, carry = the bit shifted out
;; Keeps: Y
;; Errors: jumps to <Float::OverflowJump> when the exponent passes $FF
;; Entry:
;;   ShiftInCarry = shifts in the carry as the top bit instead of the sign
;;   KeepExponent = shifts in the carry, without changing the exponent: <Float::Multiply> enters here
;; Also: RTAR (A2RM78)
.proc ShiftRight
    lda Mantissa1
    asl a

;; Shifts in the carry as the top bit, adding 1 to the exponent.
;; Also: RTLOG (A2RM78)
ShiftInCarry:
    inc Exponent1
    beq Overflow

;; Shifts in the carry as the top bit, without changing the exponent.
;; Also: RTLOG1 (A2RM78)
KeepExponent:
    ; X runs from -6 to -1: Extension+3-6 wraps round page zero to Mantissa1.
    ldx #$100 - 2 * MANTISSA_BYTES

;; Also: ROR1 (A2RM78)
NextByte:
    ror Extension + 3,x
    inx
    bne NextByte
    rts
.endproc

;; Multiplies: FP1 = FP1 x FP2.
;;
;; At $F48C. The exponents are added (<Float::SetResultExponent>). The multiplier, a copy of FP1's mantissa in
;; <Float::Extension>, is shifted right a bit at a time, together with the product in <Float::Mantissa1>, and the
;; multiplicand, FP2's mantissa, is added into the product when the bit shifted out is 1. 24 steps give the top 24
;; bits of the product, which is negated if one operand was negative.
;; Out: Exponent1/Mantissa1 = the product
;; Errors: jumps to <Float::OverflowJump> on overflow; an underflow gives 0
;; See: <Float::MakeOperandsPositive>, <Float::SetResultExponent>, <Float::FinishMultiplyDivide>
;; Also: FMUL (A2RM78)
.proc Multiply
.assert * = $F48C, "Float::Multiply must stay at $F48C, where programs call FMUL."
    jsr MakeOperandsPositive
    adc Exponent1
    jsr SetResultExponent
    clc

;; One step: shifts the product and the multiplier right, and adds the multiplicand when the bit was 1.
;; Also: MUL1 (A2RM78)
Step:
    jsr ShiftRight::KeepExponent
    bcc NextStep
    jsr AddMantissas

;; Also: MUL2 (A2RM78)
NextStep:
    dey
    bpl Step
    ; Falls into FinishMultiplyDivide.
.endproc

;; Ends multiplying or dividing: normalizes the result, after negating it if the low bit of <Float::SignCount> is set.
;; Errors: jumps to <Float::OverflowJump> as <Float::Negate> does
;; Entry:
;;   NormalizeOrNegate = normalizes, or with the carry set negates first: <Float::SetResultExponent> enters here with
;;     the carry clear
;; Also: MDEND (A2RM78)
.proc FinishMultiplyDivide
    lsr SignCount

;; Normalizes, or negates first when the carry is set.
;; Also: NORMX (A2RM78)
NormalizeOrNegate:
    bcc Normalize::CheckExponent
    ; Falls into Negate.
.endproc

;; Negates FP1's mantissa (two's complement), then normalizes it.
;;
;; The branch at the end is always taken (X is 0), into <Float::Add::Finish>, which also handles negating -2 ($800000),
;; whose negation overflows: it is shifted right with the exponent one more.
;; Out: Exponent1/Mantissa1 = the number negated
;; Keeps: Y
;; Errors: jumps to <Float::OverflowJump> when -2 with the largest exponent is negated
;; Also: FCOMPL (A2RM78)
.proc Negate
    sec
    ldx #MANTISSA_BYTES

;; Subtracts one byte of the mantissa from 0, from the low byte up: X runs from 3 to 1.
;; Also: COMPL1 (A2RM78)
NextByte:
    lda #0
    sbc Mantissa1 - 1,x
    sta Mantissa1 - 1,x
    dex
    bne NextByte
    beq Add::Finish
.endproc

;; Divides: FP1 = FP2 / FP1.
;;
;; At $F4B2. The exponents are subtracted (<Float::SetResultExponent>). Each of the 23 steps subtracts the divisor,
;; FP1's mantissa copied into <Float::Extension>, from the dividend, FP2's mantissa, keeping the difference if it
;; is not negative, shifts the result bit into the quotient in <Float::Mantissa1>, and shifts the dividend left.
;; Out: Exponent1/Mantissa1 = the quotient
;; Errors: jumps to <Float::OverflowJump> on overflow, which a divisor that is not normalized (0 among them) also
;;   causes; an underflow gives 0
;; See: <Float::MakeOperandsPositive>, <Float::SetResultExponent>, <Float::FinishMultiplyDivide>
;; Also: FDIV (A2RM78)
.proc Divide
.assert * = $F4B2, "Float::Divide must stay at $F4B2, where programs call FDIV."
    jsr MakeOperandsPositive
    sbc Exponent1
    jsr SetResultExponent

;; One step: the dividend less the divisor, pushed a byte at a time from the low byte.
;; Also: DIV1 (A2RM78)
Step:
    sec
    ldx #MANTISSA_BYTES - 1

;; Also: DIV2 (A2RM78)
SubtractByte:
    lda Mantissa2,x
    sbc Extension,x
    pha
    dex
    bpl SubtractByte

    ; X runs from -3 to -1 over the dividend, from its high byte.
    ldx #$100 - MANTISSA_BYTES

;; Takes a byte of the difference back, and keeps it as the dividend's when the divisor fitted.
;; Also: DIV3 (A2RM78)
NextByte:
    pla
    bcc SkipByte
    sta Mantissa2 + MANTISSA_BYTES,x

;; Also: DIV4 (A2RM78)
SkipByte:
    inx
    bne NextByte

    ; The carry, set when the divisor fitted, is the quotient's next bit; then the dividend moves left.
    rol Mantissa1 + 2
    rol Mantissa1 + 1
    rol Mantissa1
    asl Mantissa2 + 2
    rol Mantissa2 + 1
    rol Mantissa2
    bcs Overflow
    dey
    bne Step
    beq FinishMultiplyDivide
.endproc

;; Sets the result's exponent for multiplying or dividing, and clears <Float::Mantissa1> for the result.
;;
;; The biased exponents' sum or difference carries the bias once too many or too few: with the carry set, a
;; positive A is the exponent less the bias and a negative one an overflow; with the carry clear, a negative A is the
;; exponent plus the bias and a positive one an underflow. On an underflow it drops its caller's return address and
;; returns 0 from <Float::Multiply> or <Float::Divide> instead: the mantissa of 0 is normalized until the exponent is 0.
;; In: A = the exponents' sum or difference, carry and negative = as the add or subtract left them, X = 0
;; Out: Exponent1 = the exponent, Mantissa1 = 0, Y = 23, the steps of a division
;; Errors: jumps to <Float::OverflowJump> on overflow
;; Also: MD2 (A2RM78)
.proc SetResultExponent
    stx Mantissa1 + 2
    stx Mantissa1 + 1
    stx Mantissa1
    bcs CheckOverflow
    bmi Store

    ; An underflow: 0 from the caller's caller.
    pla
    pla
    bcc FinishMultiplyDivide::NormalizeOrNegate

;; Stores the exponent, with the bias exclusive-ORed back.
;; Also: MD3 (A2RM78)
Store:
    eor #EXPONENT_BIAS
    sta Exponent1
    ldy #DIVIDE_STEPS
    rts

;; After a carry: an overflow unless the exponent is positive.
;; Also: OVCHK (A2RM78)
CheckOverflow:
    bpl Store
    ; Falls into Overflow.
.endproc

;; An overflow: jumps to the program's handler at <Float::OverflowJump>.
;; Also: OVFL (A2RM78)
.proc Overflow
    jmp OverflowJump
.endproc

.endscope

    ; Unused bytes, up to the Mini-Assembler at $F500.
    .res $F500 - *, $FF
