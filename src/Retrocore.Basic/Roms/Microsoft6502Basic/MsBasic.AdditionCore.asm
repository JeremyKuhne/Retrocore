; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the addition and subtraction entries that can precede platform-specific code.
.macro AdditionEntries

    .scope Float continued

    ;; Adds one half to <Fac>.
    ;; See: <Float::AddPacked>, <Float::Half>
    ;; Also: FADDH (M6502, ASTIL, AS82, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddHalf
    lda #<Half
    ldy #>Half
    jmp AddPacked
    .endproc

    ;; Subtracts <Fac> from a packed number, leaving the result in <Fac>.
    ;; In: A = low byte of packed operand address, Y = high byte of packed operand address
    ;; Also: FSUB (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SubtractFromPacked
    jsr LoadArg
    ; Falls into SubtractFromArg.
    .endproc

    ;; Subtracts <Fac> from the unpacked argument accumulator.
    ;; Also: FSUBT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SubtractFromArg
    lda FacSign
    eor #$FF
    sta FacSign
    eor ArgSign
    sta ResultSign
    lda FacExponent
    jmp AddArg
    .endproc
    .endscope

.endmacro

;; Emits floating-point addition, normalization and shifting for five-byte precision.
.macro AddAndNormalize

    .scope Float continued

    ;; The unshifted operand's extension byte while two numbers are added: <Float::AddArg> saves <FacExtension> here,
    ;; <Float::AlignAndAdd> clears it when <Fac> is the one shifted, and <Float::AddMantissas> adds it in or
    ;; <Float::AlignAndAdd::Subtract> subtracts the shifted bits from it. The byte is <FunctionJumpHigh>, which
    ;; Microsoft's source names OLDOV here too.
    UnshiftedExtension = FunctionJumpHigh

    ;; Shifts the smaller operand right through <Float::ShiftRight> (eight bits or more), then joins
    ;; <Float::AlignAndAdd::Combine>.
    ;; Also: FADD5 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ShiftAndAdd
    jsr ShiftRight
    bcc AlignAndAdd::Combine
    .endproc

    ;; Adds a packed number to <Fac>, leaving the result in <Fac>.
    ;;
    ;; The smaller mantissa is shifted to align exponents; equal signs add and opposite signs subtract. The result
    ;; is normalized, with low shifted bits retained in <FacExtension>.
    ;; In: A = low byte of packed operand address, Y = high byte of packed operand address
    ;; See: <Float::LoadArg>, <Float::Normalize>
    ;; Also: FADD (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddPacked
    jsr LoadArg
    ; Falls into AddArg.
    .endproc

    ;; Adds the unpacked argument accumulator to <Fac>, with zero set from <FacExponent> and <ResultSign> already set.
    ;; Also: FADDT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddArg
    bne *+5                         ; skip the three-byte jump when FAC is nonzero
    jmp CopyArgToFac
    ldx FacExtension
    stx UnshiftedExtension
    ldx #ArgExponent
    lda ArgExponent
    ; Falls into AlignAndAdd.
    .endproc

    ;; Aligns and adds <Fac> and the argument accumulator using A as the exponent of the second operand.
    ;;
    ;; <Float::MultiplyByTen> uses this entry after setting up the operands and their common sign.
    ;; Entry:
    ;;   Combine = Tests <ResultSign>: equal signs go to <Float::AddMantissas>, opposite signs subtract
    ;; Also: FADDC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AlignAndAdd
    tay
    beq ZERRTS
    sec
    sbc FacExponent
    beq Combine
    bcc ArgSmaller                       ; the argument accumulator has the smaller exponent
    sty FacExponent
    ldy ArgSign
    sty FacSign
    eor #$FF
    adc #$00
    ldy #$00
    sty UnshiftedExtension
    ldx #Fac
    bne Align

;; Arg has the smaller exponent: clears <FacExtension>, so the bits shifted out of Arg, returned in A, are its only
;; low bits.
;; Also: FADDA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ArgSmaller:
    ldy #$00
    sty FacExtension

;; A shift of eight bits or more goes to <Float::ShiftAndAdd>; a shorter one shifts the operand at X through
;; <Float::ShiftRight::ShiftLow>.
;; Also: FADD1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Align:
    cmp #$F9                        ; a shift of eight or more starts with whole bytes
    bmi ShiftAndAdd
    tay
    lda FacExtension
    lsr 1,x
    jsr ShiftRight::ShiftLow

;; Adds or subtracts aligned mantissas according to <ResultSign>.
;; Also: FADD4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Combine:
    bit ResultSign
    bpl AddMantissas

; Opposite signs: subtract the smaller magnitude from the larger.
;; Picks Y as the operand that was not shifted, so the shifted one (X) is subtracted from it.
;; Also: FADD3 (M6502)
OppositeSigns:
    ldy #FacExponent
    cpx #ArgExponent
    beq Subtract
    ldy #ArgExponent

;; Subtracts the operand at X from the one at Y, guard bytes first, into <Fac>'s mantissa; falls into
;; <Float::NormalizeSigned>.
;; Also: SUBIT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Subtract:
    sec
    eor #$FF
    adc UnshiftedExtension
    sta FacExtension
    lda 4,y
    sbc 4,x
    sta FacMantissa4
    lda 3,y
    sbc 3,x
    sta FacMantissa3
    lda 2,y
    sbc 2,x
    sta FacMantissa2
    lda 1,y
    sbc 1,x
    sta FacMantissa1
    .endproc

    ;; Normalizes <Fac>, negating its mantissa and sign first if carry is clear.
    ;; In: carry = clear to negate <Fac> before normalization
    ;; See: <Float::Normalize>, <Float::Complement>
    ;; Also: FADFLT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc NormalizeSigned
    bcs Normalize
    jsr Complement
    .endproc

    ;; Normalizes <Fac> after addition, multiplication or division.
    ;;
    ;; Whole zero bytes are shifted first, then individual bits. An exponent underflow produces zero. A carry out of
    ;; addition is handled where <Float::AddMantissas> joins at <Float::NormalizeBits::CheckCarry>.
    ;; See: <Float::SetZero>, <Float::ShiftInCarry>
    ;; Also: NORMAL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Normalize
    ldy #$00
    tya
    clc

;; While the top mantissa byte is zero, moves each byte up one and counts 8 in A; four zero bytes fall into
;; <Float::SetZero>.
;; Also: NORM3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ShiftBytes:
    ldx FacMantissa1
    bne NormalizeBits::Test
    ; Move whole zero bytes out of the high end before shifting individual bits.
    ldx FacMantissa2
    stx FacMantissa1
    ldx FacMantissa3
    stx FacMantissa2
    ldx FacMantissa4
    stx FacMantissa3
    ldx FacExtension
    stx FacMantissa4
    sty FacExtension
    adc #$08
    cmp #$20
    bne ShiftBytes
    .endproc

    ;; Sets the <Fac> exponent and sign to zero; its mantissa need not be cleared.
    ;; Also: ZEROFC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SetZero
    lda #$00
    .endproc

    ;; Stores A in the exponent and sign.
    ;; Also: ZEROF1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SetExponentAndSign
    sta FacExponent
    ; Falls into SetSign.
    .endproc

    ;; Stores A in the sign only.
    ;; Also: ZEROML (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SetSign
    sta FacSign
    rts
    .endproc

    ;; Equal signs: adds Arg's mantissa and the saved guard byte to <Fac>'s, then goes to
    ;; <Float::NormalizeBits::CheckCarry>.
    ;; Also: FADD2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddMantissas
    ; Equal signs: add the mantissas and their low guard bits.
    adc UnshiftedExtension
    sta FacExtension
    lda FacMantissa4
    adc ArgMantissa4
    sta FacMantissa4
    lda FacMantissa3
    adc ArgMantissa3
    sta FacMantissa3
    lda FacMantissa2
    adc ArgMantissa2
    sta FacMantissa2
    lda FacMantissa1
    adc ArgMantissa1
    sta FacMantissa1
    jmp NormalizeBits::CheckCarry
    .endproc

    ;; The bit loop: adds 1 to the shift count and shifts <Fac> (and <FacExtension>) left one bit.
    ;; Entry:
    ;;   Test = Loops until <Fac>'s top bit is set, then subtracts the count from <FacExponent>; underflow goes to
    ;;     <Float::SetZero>
    ;;   CheckCarry = A carry out of the addition (carry set) falls into <Float::ShiftInCarry>; none returns
    ;; Also: NORM2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc NormalizeBits
    adc #$01
    asl FacExtension
    rol FacMantissa4
    rol FacMantissa3
    rol FacMantissa2
    rol FacMantissa1

;; Loops until <Fac>'s top bit is set, then subtracts the count from <FacExponent>; underflow goes to
;; <Float::SetZero>.
;; Also: NORM1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Test:
    bpl NormalizeBits
    sec
    sbc FacExponent
    bcs SetZero
    eor #$FF
    adc #$01
    sta FacExponent

;; A carry out of the addition (carry set) falls into <Float::ShiftInCarry>; none returns.
;; Also: SQUEEZ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckCarry:
    bcc ShiftInCarry::Done
    .endproc

    ;; Shifts <Fac> right after a mantissa carry and increments its exponent.
    ;; Errors: overflow = jumps to <Float::OverflowError> if the exponent wraps
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: RNDSHF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ShiftInCarry
    inc FacExponent
    beq OverflowError
    ror FacMantissa1
    ror FacMantissa2
    ror FacMantissa3
    ror FacMantissa4
    ror FacExtension

;; The shared rts.
;; Also: RNDRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Complements the <Fac> sign and negates its mantissa and rounding byte.
    ;; Also: NEGFAC (M6502, AS82, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Complement
    lda FacSign
    eor #$FF
    sta FacSign
    .endproc

    ;; Negates only the mantissa and rounding byte.
    ;; Also: NEGFCH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ComplementMantissa
    lda FacMantissa1
    eor #$FF
    sta FacMantissa1
    lda FacMantissa2
    eor #$FF
    sta FacMantissa2
    lda FacMantissa3
    eor #$FF
    sta FacMantissa3
    lda FacMantissa4
    eor #$FF
    sta FacMantissa4
    lda FacExtension
    eor #$FF
    sta FacExtension
    inc FacExtension
    bne IncrementMantissa::Done
    .endproc

    ;; Increments the <Fac> mantissa, propagating a carry from its low byte.
    ;; Entry:
    ;;   Done = The shared rts
    ;; See: <Float::Round>
    ;; Also: INCFAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc IncrementMantissa
    inc FacMantissa4
    bne Done
    inc FacMantissa3
    bne Done
    inc FacMantissa2
    bne Done
    inc FacMantissa1

;; The shared rts.
;; Also: INCFRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Reports the floating-point overflow error through <ERROR>.
    ;; Also: OVERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc OverflowError
    ldx #ERROR_OVERFLOW
    jmp ERROR
    .endproc

    ; Mantissa negation, overflow, and the shared arithmetic shifter.

    ;; Shifts the multiplication result right by a byte, then continues through <Float::ShiftRight>.
    ;; In: A = 0, carry = set, so that <Float::ShiftRight> returns after the byte
    ;; Also: MULSHF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ShiftProductByte
    ldx #(Result1-1)
    .endproc

    ;; Moves the four bytes at X+1..X+4 down a byte, the low one into <FacExtension>, filling the top from
    ;; <ShiftFill>; falls into <Float::ShiftRight>.
    ;; Also: SHFTR2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ShiftRightByte
    ldy 4,x
    sty FacExtension
    ldy 3,x
    sty 4,x
    ldy 2,x
    sty 3,x
    ldy 1,x
    sty 2,x
    ldy ShiftFill
    sty 1,x
    .endproc

    ;; Shifts the four bytes at X+1 through X+4 right by the negative count in A.
    ;;
    ;; Whole-byte shifts fill from <ShiftFill>; bit shifts preserve the high byte's sign and shift low bits into A.
    ;; In: X = byte before the high byte, A = negative shift count, carry = clear
    ;; Out: A = shifted-out low bits, carry = clear
    ;; Entry:
    ;;   ShiftLow = rotates the lower three bytes and A with the carry supplied by the caller
    ;; Also: SHIFTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ShiftRight
    adc #$08
    bmi ShiftRightByte
    beq ShiftRightByte
    sbc #$08
    tay
    lda FacExtension
    bcs Done

;; Copies the top byte's bit 7 into carry so the rotate keeps the sign.
;; Also: SHFTR3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextBit:
    asl 1,x
    bcc ShiftHigh
    inc 1,x

;; Rotates the top byte right twice, the first to place the copied sign bit, the second to shift.
;; Also: SHFTR4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ShiftHigh:
    ror 1,x
    ror 1,x

;; Rotates the lower three bytes and A with the carry supplied by the caller.
;; Also: ROLSHF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ShiftLow:
    ror 2,x
    ror 3,x
    ror 4,x
    ror a

;; Counts one bit up toward zero and loops while bits remain.
;; Also: SHFTR7 (M6502)
Count:
    iny
    bne NextBit

;; Clears carry and returns.
;; Also: SHFTRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    clc
    rts
    .endproc
    .endscope

.endmacro
