; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits sign, comparison and integer conversion routines for five-byte precision.
.macro SignAndIntegerRoutines

    ; Sign and integer-to-floating-point conversion.

    .scope Float continued

    ;; Returns the sign of <Fac> as -1, 0 or 1 in A.
    ;; Out: A = $FF for negative, 0 for zero or 1 for positive
    ;; Entry:
    ;;   FromSignByte = Takes the sign from <FacSign> without testing the exponent
    ;;   FromBit7 = Returns $FF if bit 7 of A is set, else 1
    ;; Also: SIGN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc GetSign
    lda FacExponent
    beq Done

;; Takes the sign from <FacSign> without testing the exponent.
;; Also: FCSIGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FromSignByte:
    lda FacSign

;; Returns $FF if bit 7 of A is set, else 1.
;; Also: FCOMPS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FromBit7:
    rol a
    lda #$FF
    bcs Done
    lda #$01

;; The shared rts.
;; Also: SIGNRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

    .scope Functions continued

    ;; Replaces <Fac> with its sign as a floating-point number.
    ;; See: <Float::GetSign>, <Float::ConvertSignedByte>
    ;; Also: SGN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Sgn
    jsr Float::GetSign
    ; Falls into ConvertSignedByte.
    .endproc
    .endscope

    .scope Float continued

    ;; Converts the signed byte in A to floating point in <Fac>.
    ;; In: A = signed byte
    ;; See: <Float::ConvertSignedWord>
    ;; Also: FLOAT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ConvertSignedByte
    sta FacMantissa1
    lda #$00
    sta FacMantissa2
    ldx #$88
    .endproc

    ;; Converts the signed 16-bit integer in <FacMantissa1> and <FacMantissa2> to floating point.
    ;;
    ;; The lower two mantissa bytes are cleared and the signed value is normalized using X as the initial exponent.
    ;; In: FacMantissa1 = high byte of integer, FacMantissa2 = low byte of integer, X = initial biased exponent
    ;; Also: FLOATS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ConvertSignedWord
    lda FacMantissa1
    eor #$FF
    rol a
    .endproc

    ;; Takes the sign complement in carry.
    ;; Also: FLOATC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ConvertWord
    lda #$00
    sta FacMantissa4
    sta FacMantissa3
    .endproc

    ;; Uses A for the sign and rounding byte.
    ;; Also: FLOATB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ConvertMantissa
    stx FacExponent
    sta FacExtension
    sta FacSign
    jmp NormalizeSigned
    .endproc
    .endscope

    .scope Functions continued

    ;; Makes <Fac> nonnegative by clearing the high bit of its sign byte.
    ;; Also: ABS (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Abs
    lsr FacSign
    rts

    ; Comparison and floating-point-to-integer conversion.
    .endproc
    .endscope

    .scope Float continued

    ;; Compares <Fac> to a packed number and returns an ordering byte in A.
    ;;
    ;; After the exponent and upper mantissa bytes match, it subtracts <FacMantissa4> and bit 7 of <FacExtension> from
    ;; the packed low byte. The zero result is tested without checking the borrow: if the packed low byte is $00,
    ;; <FacMantissa4> is $FF and bit 7 of <FacExtension> is set, this last subtraction wraps to zero and the routine
    ;; reports equality.
    ;; In: A = low byte of packed operand address, Y = high byte of packed operand address
    ;; Out: A = normally 1 if <Fac> is greater, 0 if equal, $FF if less
    ;; Also: FCOMP (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Compare
    sta Pointer2
    .endproc

    ;; As <Float::Compare>, with the operand's low byte already in <Pointer2> and its high byte in Y.
    ;; Also: FCOMPN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CompareAtPointer2
    sty Pointer2+1
    ldy #$00
    lda (Pointer2),y
    iny
    tax
    beq GetSign
    lda (Pointer2),y
    eor FacSign
    bmi GetSign::FromSignByte

;; Signs agree: compares exponents, then mantissa bytes, the last against <FacMantissa4> and <FacExtension>'s bit 7.
;; Also: FOUTCP (M6502)
SameSign:
    cpx FacExponent
    bne Unequal
    lda (Pointer2),y
    ora #$80
    cmp FacMantissa1
    bne Unequal
    iny
    lda (Pointer2),y
    cmp FacMantissa2
    bne Unequal
    iny
    lda (Pointer2),y
    cmp FacMantissa3
    bne Unequal
    iny
    lda #$7F
    cmp FacExtension
    lda (Pointer2),y
    sbc FacMantissa4
    beq ToLongInteger::Done

;; Turns the carry of the unequal byte and <FacSign> into the order: inverts <FacSign> when <Fac> is larger.
;; Also: FCOMPC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Unequal:
    lda FacSign
    bcc ToSignFromBit7
    eor #$FF

;; Jumps on to <Float::GetSign::FromBit7>.
;; Also: FCOMPD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToSignFromBit7:
    jmp GetSign::FromBit7
    .endproc

    ;; Aligns <Fac>'s mantissa to a four-byte integer in <FacMantissa1> through <FacMantissa4>.
    ;;
    ;; A negative value first has its mantissa and guard byte negated by <Float::ComplementMantissa>; the subsequent
    ;; right shifts use sign extension, with <ShiftFill> supplying whole-byte fill. The exponent and sign are not
    ;; converted into an integer representation. <Functions::Int> uses this intermediate integer to construct the
    ;; floating-point greatest integer. Magnitudes outside the signed four-byte range are not checked.
    ;; Entry:
    ;;   Done = The shared rts
    ;; See: <Functions::Int>, <Float::ShiftRight>
    ;; Also: QINT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ToLongInteger
    lda FacExponent
    beq ClearMantissa
    sec
    sbc #$A0
    bit FacSign
    bpl Shift
    tax
    lda #$FF
    sta ShiftFill
    jsr ComplementMantissa
    txa

;; A long shift goes through <Float::ShiftRight>, then restores Bits from Y.
;; Also: QISHFT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Shift:
    ldx #Fac
    cmp #$F9
    bpl ShortShift
    jsr ShiftRight
    sty ShiftFill

;; The shared rts.
;; Also: QINTRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts

;; Fewer than eight bits: puts <FacSign>'s bit back in the top byte and shifts through <Float::ShiftRight::ShiftLow>.
;; Also: QINT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ShortShift:
    tay
    lda FacSign
    and #$80
    lsr FacMantissa1                       ; restore the sign bit before shifting the remaining bytes
    ora FacMantissa1
    sta FacMantissa1
    jsr ShiftRight::ShiftLow
    sty ShiftFill
    rts
    .endproc
    .endscope

    .scope Functions continued

    ;; Replaces <Fac> with the greatest integer not greater than <Fac>.
    ;;
    ;; For exponents below $A0, <Float::ToLongInteger> aligns the signed integer and this routine normalizes it back to
    ;; floating point; the integer's low byte is also saved in <SmallInteger>. Values with an exponent at least $A0
    ;; already have no fractional bits at <Fac> precision.
    ;; See: <Float::ToLongInteger>
    ;; Also: INT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Int
    lda FacExponent
    cmp #$A0
    bcs Float::ClearMantissa::Done
    jsr Float::ToLongInteger
    sty FacExtension
    lda FacSign
    sty FacSign
    eor #$80
    rol a
    lda #$A0
    sta FacExponent
    lda FacMantissa4
    sta SmallInteger
    jmp Float::NormalizeSigned
    .endproc
    .endscope

    .scope Float continued

    ;; Clears the <Fac> mantissa and Y when the exponent is zero.
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: CLRFAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ClearMantissa
    sta FacMantissa1
    sta FacMantissa2
    sta FacMantissa3
    sta FacMantissa4
    tay

;; The shared rts.
;; Also: INTRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

.endmacro
