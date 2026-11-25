; retrocore: style=strict
;; Business BASIC's floating point, part one (Apple's B3MATHK): addition and subtraction, normalizing, negating,
;; and the right shifts the other operations share.
;;
;; A real variable is four bytes: the exponent, biased by $80, with 0 meaning the number is zero whatever the other
;; bytes hold; then the mantissa, high byte first, with the sign in the top bit of its first byte. The mantissa is a
;; fraction with the binary point to its left, and its leading 1, which the sign bit stands in for, is implied. The
;; bytes 84 A0 00 00 are -10: $84 is an exponent of 4, and the mantissa is binary .101, 0.625, times 16.
;;
;; BASIC's own constants and its temporaries in its own bank have a fifth byte, more mantissa; the routines that load
;; and store reals take a bank of 0 to mean the five-byte form.
;;
;; <FAC> and <ARG> hold reals unpacked: the exponent, four mantissa bytes with the leading 1 present, then the sign
;; byte, 0 for positive and $FF for negative (only its top bit counts). <FACOV>, below <FACLO>, holds the bits that are
;; rounded off; <ARISGN> holds the sign of a sum, product or quotient, <ARG>'s sign exclusive-ored with the <FAC>'s.
;; A two-operand routine takes the left operand in <ARG> and the right in the <FAC>, and leaves the result in the
;; <FAC>; the ones named for a packed operand unpack the left operand from memory first, with <Float::LoadArg>.
;;
;; This is the float package of Microsoft's 6502 BASIC, as AppleSoft has it, with five-byte constants, banks and
;; Business BASIC's rounding; its routines have AppleSoft's names where they do the same job.

; Floating point, part one: addition, normalizing and shifting.
.scope Float continued

; The formats.

;; The bias on a real's exponent: an exponent of $80 is a number from 0.5 to below 1.
EXPONENT_BIAS = $80

;; The bytes of a real unpacked in <FAC> or <ARG>: the exponent, four mantissa bytes and the sign.
UNPACKED_SIZE = 6

;; The bytes of a real in BASIC's own bank, a constant or temporary: the exponent and four mantissa bytes.
CONSTANT_SIZE = 5

; ---------------------------------------------------------------------------------------------------------------------
; Addition and subtraction
; ---------------------------------------------------------------------------------------------------------------------

;; Adds a half to <FAC>.
;; See: <Float::AddPacked>, <Float::Half>
;; Also: FADDH (BB13)
.proc AddHalf
    lda #<(Half)
    ldy #>(Half)
    jmp AddPacked
.endproc

;; Subtracts <FAC> from the five-byte real at A, Y: the <FAC> becomes that number less the <FAC>.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::SubtractFromArg>, <Float::LoadArg>
;; Also: FSUB (BB13)
.proc SubtractFromPacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into SubtractFromArg.
.endproc

;; Subtracts <FAC> from <ARG>, into the <FAC>, by negating the <FAC> and adding.
;; See: <Float::AddArg>
;; Also: FSUBT (BB13)
.proc SubtractFromArg
    lda FACSGN
    eor #$FF
    sta FACSGN
    eor ARGSGN
    sta ARISGN
    lda FACEXP                              ; with zero set for a zero FAC, as AddArg wants
    jmp AddArg
.endproc

;; Shifts the smaller operand right by more than seven bits, a byte at a time first, then joins
;; <Float::AlignAndAdd::Combine>.
;; In: X = the smaller operand's exponent's address, A = minus the count, carry = clear
;; Also: FADD5 (BB13)
.proc ShiftAndAdd
    jsr ShiftRight
    bcc AlignAndAdd::Combine                ; always
.endproc

;; Adds the five-byte real at A, Y to <FAC>.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::AddArg>, <Float::LoadArg>
;; Also: FADD (BB13)
.proc AddPacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into AddArg.
.endproc

;; Adds <ARG> to <FAC>: lines up the binary points by shifting the smaller number right, then adds the mantissas, or
;; subtracts them when the signs differ, and normalizes.
;; In: A = <FACEXP>, zero = set for a zero <FAC>, ARISGN = <ARG>'s sign exclusive-ored with the <FAC>'s
;; See: <Float::AlignAndAdd>, <Float::Normalize>
;; Also: FADDT (BB13)
.proc AddArg
    bne *+5                                 ; skip the jump for a FAC that is not zero
    jmp CopyArgToFac                        ; a zero FAC: the sum is ARG
    ldx FACOV
    stx OLDOV
    ldx #ARGEXP                             ; shift ARG, unless the FAC is the smaller
    lda ARGEXP
    ; Falls into AlignAndAdd.
.endproc

;; Adds <ARG> to <FAC>, taking A as <ARG>'s exponent; a zero exponent leaves the <FAC> as it is.
;;
;; <Float::MultiplyByTen> passes an exponent 2 above the <FAC>'s, so the <FAC>, shifted, is added as four times itself.
;; In: A = <ARG>'s exponent, X = the address of the exponent of the operand to shift if <ARG> is the smaller (<ARGEXP>)
;; Entry:
;;   Combine = adds or subtracts the operands once they are lined up, with X the shifted one and A its rounding bits
;; See: <Float::MultiplyByTen>
;; Also: FADDC (BB13)
.proc AlignAndAdd
    tay
    bne *+3                                 ; skip the return for an exponent that is not zero
    rts
    sec
    sbc FACEXP
    beq Combine                             ; the same exponent: no shift
    bcc ArgSmaller
    sty FACEXP                              ; ARG is the larger: its exponent and sign win
    ldy ARGSGN
    sty FACSGN
    eor #$FF                                ; the count, negated
    adc #0
    ldy #0
    sty OLDOV
    ldx #FAC                                ; and the FAC is the one to shift
    bne Align                               ; always

;; <ARG> is the smaller: clears <FACOV>, so that the bits shifted out of <ARG> are the only rounding bits.
;; Also: FADDA (BB13)
ArgSmaller:
    ldy #0
    sty FACOV

;; Shifts the smaller operand, at X, right by minus A bits: more than seven through <Float::ShiftAndAdd>, fewer here.
;; Also: FADD1 (BB13)
Align:
    cmp #$100-7                             ; more than 7 bits: shift bytes first
    bmi ShiftAndAdd
    tay
    lda FACOV
    lsr 1,x                                 ; the top bit becomes 0
    jsr ShiftRightByCount::ShiftLow

;; Adds the mantissas when the signs match, and subtracts the smaller from the larger when they differ.
;; In: A = the shifted operand's rounding bits
;; Also: FADD4 (BB13)
Combine:
    bit ARISGN
    bpl AddMantissas                        ; the same signs: add
    ldy #FACEXP                             ; the carry is clear
    cpx #ARGEXP
    beq Subtract
    ldy #ARGEXP

;; Subtracts the shifted operand, at X, from the other, at Y, into <FAC>; <Float::NormalizeSigned> then negates a
;; difference that came out negative.
;; Also: SUBIT (BB13)
Subtract:
    sec
    eor #$FF
    adc OLDOV
    sta FACOV
    lda 4,y
    sbc 4,x
    sta FACLO
    lda 3,y
    sbc 3,x
    sta FACMO
    lda 2,y
    sbc 2,x
    sta FACMOH
    lda 1,y
    sbc 1,x
    sta FACHO
    ; Falls into NormalizeSigned.
.endproc

;; Negates <FAC> when the carry is clear, then normalizes it.
;; In: carry = clear to negate it
;; See: <Float::Complement>, <Float::Normalize>
;; Also: FADFLT (BB13)
.proc NormalizeSigned
    bcs Normalize
    jsr Complement
    ; Falls into Normalize.
.endproc

;; Normalizes <FAC>: shifts the mantissa left until its top bit is set, lowering the exponent to match, a byte at a
;; time first. A <FAC> that is zero, or too small for the exponent, becomes zero.
;; See: <Float::SetZero>, <Float::NormalizeBits>
;; Also: NORMAL (BB13)
.proc Normalize
    ldy #0
    tya
    clc

;; Shifts the mantissa left a byte while its high byte is zero, counting the bits in A; four zero bytes make the <FAC>
;; zero.
;; Also: NORM3 (BB13)
ShiftBytes:
    ldx FACHO
    bne NormalizeBits::Test
    ldx FACHO+1
    stx FACHO
    ldx FACMOH+1
    stx FACMOH
    ldx FACMO+1
    stx FACMO
    ldx FACOV
    stx FACLO
    sty FACOV
    adc #8
    cmp #$20                                ; all four bytes zero
    bne ShiftBytes
    ; Falls into SetZero.
.endproc

;; Makes <FAC> zero, positive.
;; Keeps: X, Y
;; Also: ZEROFC (BB13)
.proc SetZero
    lda #0
    ; Falls into SetExponentAndSign.
.endproc

;; Sets <FACEXP> and <FACSGN> to A.
;; Keeps: A, X, Y
;; Also: ZEROF1 (BB13)
.proc SetExponentAndSign
    sta FACEXP
    ; Falls into SetSign.
.endproc

;; Sets <FACSGN> to A.
;; Keeps: A, X, Y
;; Also: ZEROML (BB13)
.proc SetSign
    sta FACSGN
    rts
.endproc

;; Adds the mantissas, the rounding bits too, then takes a carry out of the top into the exponent.
;; In: A = the shifted operand's rounding bits, carry = clear
;; See: <Float::NormalizeBits>
;; Also: FADD2 (BB13)
.proc AddMantissas
    adc OLDOV
    sta FACOV
    lda FACLO
    adc ARGLO
    sta FACLO
    lda FACMO
    adc ARGMO
    sta FACMO
    lda FACMOH
    adc ARGMOH
    sta FACMOH
    lda FACHO
    adc ARGHO
    sta FACHO
    jmp NormalizeBits::CheckCarry
.endproc

;; Shifts the mantissa left a bit, counting it in A, for <Float::Normalize>.
;; Entry:
;;   Test = shifts left until the top bit is set, then takes the count of bits from the exponent
;;   CheckCarry = takes a carry out of the mantissa's top, for an addition
;; Also: NORM2 (BB13)
.proc NormalizeBits
    adc #1
    asl FACOV
    rol FACLO
    rol FACMO
    rol FACMOH
    rol FACHO

;; Shifts left until the top bit is set, then takes the count of bits from the exponent.
;; Also: NORM1 (BB13)
Test:
    bpl NormalizeBits
    sec
    sbc FACEXP
    bcs SetZero                             ; below the smallest exponent: zero
    eor #$FF
    adc #1
    sta FACEXP

;; Takes a carry out of the mantissa's top: shifts it back in from the left and adds one to the exponent.
;; In: carry = set for a carry
;; Also: SQUEEZ (BB13)
CheckCarry:
    bcc ShiftInCarry::Done
    ; Falls into ShiftInCarry.
.endproc

;; Shifts the carry into the mantissa from the left and adds one to the exponent, ending the statement with OVERFLOW
;; when the exponent passes $FF.
;; Keeps: X, Y
;; Entry:
;;   Done = returns
;; Also: RNDSHF (BB13)
.proc ShiftInCarry
    inc FACEXP
    beq OverflowError
    ror FACHO
    ror FACMOH
    ror FACMO
    ror FACLO
    ror FACOV

;; Returns.
;; Also: RNDRTS (BB13)
Done:
    rts
.endproc

;; Negates <FAC>: its sign, and the mantissa and rounding bits as a two's complement.
;; Keeps: X, Y
;; Also: NEGFAC (BB13)
.proc Complement
    lda FACSGN
    eor #$FF
    sta FACSGN
    ; Falls into ComplementMantissa.
.endproc

;; Negates <FAC>'s mantissa and rounding bits as a two's complement, leaving its sign.
;;
;; X is kept in <DPTFLG>, which <Float::ReadNumber> uses for its decimal point; its own additions never negate.
;; Uses: DPTFLG
;; Keeps: X, Y
;; Also: NEGFCH (BB13)
.proc ComplementMantissa

;; Where the routine keeps X while it counts the mantissa's bytes in X.
SavedX = DPTFLG

    stx SavedX
    ldx #3                                  ; FACHO's offset to FACLO

;; Complements a byte of the mantissa, from the lowest.
;; Also: NEGFCH1 (BB13)
Loop:
    lda FACHO,x
    eor #$FF
    sta FACHO,x
    dex
    bpl Loop
    ldx SavedX
    lda FACOV
    eor #$FF
    sta FACOV
    inc FACOV
    bne IncrementMantissa::Done             ; no carry into the mantissa
    ; Falls into IncrementMantissa.
.endproc

;; Adds one to <FAC>'s mantissa.
;; Out: zero = set when the mantissa carried out of its top
;; Keeps: A, X, Y
;; Entry:
;;   Done = returns
;; Also: INCFAC (BB13)
.proc IncrementMantissa
    inc FACLO
    bne Done
    inc FACMO
    bne Done
    inc FACMOH
    bne Done
    inc FACHO

;; Returns.
;; Also: INCFRT (BB13)
Done:
    rts
.endproc

;; Ends the statement with OVERFLOW, through <ERROR>.
;; Also: OVERR (BB13)
.proc OverflowError
    ldx #ERROV
    jmp ERROR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Shifting right
; ---------------------------------------------------------------------------------------------------------------------

;; Shifts the multiplication's result, <RES>, right a byte, for a multiplier byte of zero.
;;
;; With A = 0 and carry set, <Float::ShiftRightByCount> returns after the byte; with carry clear it shifts one bit
;; more. <Float::MultiplyByte>'s zero path passes on whatever carry it was given: set after a nonzero multiplier byte,
;; clear after a zero one. So a second zero byte in a row shifts <RES> nine bits, halving the partial product so far.
;; In: A = 0
;; See: <Float::MultiplyArg>
;; Also: MULSHF (BB13)
.proc ShiftProductByte
    ldx #RESHO-1
    ldy #0
    sty BITS                                ; zeros come in
    ; Falls into ShiftRightByte.
.endproc

;; Shifts the mantissa at X+1 right a byte, filling with <BITS>, the low byte going to <FACOV>, then goes on with
;; <Float::ShiftRightByCount>.
;; In: X = the address before the mantissa
;; Also: SHFTR2 (BB13)
.proc ShiftRightByte
    ldy 4,x
    sty FACOV
    ldy 3,x
    sty 4,x
    ldy 2,x
    sty 3,x
    ldy 1,x
    sty 2,x
    ldy BITS
    sty 1,x
    ; Falls into ShiftRightByCount.
.endproc

;; Shifts the mantissa at X+1 right by minus A bits: whole bytes while eight or more bits are left, filled from
;; <BITS>, then the rest a bit at a time, with the high byte's top bit copied, so that a negative number from
;; <Float::ToLongInteger> stays negative. The bits shifted out go through <FACOV> into A.
;;
;; The carry must be clear, as <Float::ShiftRight> says; with it set, the count is one less.
;; In: X = the address before the mantissa, A = minus the count, carry = clear
;; Out: A = the bits shifted out, carry = clear
;; Entry:
;;   ShiftLow = shifts the rest of the mantissa and A right a bit, taking the carry in at the top, then goes on while
;;     Y counts up to zero
;;   Done = clears the carry and returns
;; Also: SHFTR0 (BB13)
.proc ShiftRightByCount
    adc #8
    bmi ShiftRightByte
    beq ShiftRightByte
    sbc #8                                  ; the carry is set here: A is restored
    tay
    lda FACOV
    bcs Done                                ; no bits left

;; Shifts the high byte right a bit, copying its top bit.
;; Also: SHFTR3 (BB13)
NextBit:
    asl 1,x
    bcc ShiftHigh
    inc 1,x

;; Rotates the high byte right twice: the first puts back the bit the shift took, the second shifts with the copy.
;; Also: SHFTR4 (BB13)
ShiftHigh:
    ror 1,x
    ror 1,x

;; Shifts the rest of the mantissa at X+2 right a bit, into the rounding bits in A, and loops for each count in Y.
;; Also: ROLSHF (BB13)
ShiftLow:
    ror 2,x
    ror 3,x
    ror 4,x
    ror a
    iny
    bne NextBit

;; Ends the shift with the carry clear.
;; Also: SHFTRT (BB13)
Done:
    clc
    rts
.endproc

;; Shifts the mantissa of the number at X right by minus A bits, filling with zeros.
;; In: X = the number's exponent's address (<FAC>, <ARGEXP> or the byte before <RES>), A = minus the count,
;;   carry = clear
;; Out: A = the bits shifted out, carry = clear
;; See: <Float::ShiftRightFilled>
;; Also: SHIFTR (BB13)
.proc ShiftRight
    ldy #0
    sty BITS
    ; Falls into ShiftRightFilled.
.endproc

;; Shifts as <Float::ShiftRight> does, filling whole bytes with <BITS>: <Float::ToLongInteger> fills a negative
;; number with ones.
;; Also: SHFTR1 (BB13)
.proc ShiftRightFilled
    jmp ShiftRightByCount
.endproc

.endscope
