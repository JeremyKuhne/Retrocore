; ---------------------------------------------------------------------------------------------------------------------
; The floating point accumulators and arithmetic (&A07B-&A6A4): reading numbers from text, testing, normalising and
; rounding FPA, loading and storing packed reals, converting between integers and reals, and adding, subtracting,
; multiplying and dividing
; ---------------------------------------------------------------------------------------------------------------------

; A real number in FPA or FPB is a sign byte, an exponent offset by &80 with a byte above it for overflow, and a
; mantissa of five bytes, the first four the significant ones, most significant first, and the fifth kept for rounding.
; The mantissa is a binary fraction from 0.5 up to 1 once normalised, with its top bit set, so the value is the
; mantissa times 2 to the power of (exponent - &80). A zero has a zero exponent and mantissa. Packed in memory at
; FP_POINTER, a real takes five bytes: the exponent, then the four significant mantissa bytes with the top bit, always
; set, replaced by the sign.

REAL_EXPONENT_BIAS = $80            ;; the offset added to a real's exponent: &81 is the exponent of 1.0

ERROR_TOO_BIG = $14                 ;; error 20, "Too big": a real too large for its result

NUMBER_POINT_SEEN = FP_WORK + 5     ;; READ_NUMBER: nonzero once the number's decimal point has been read
NUMBER_SCALE = FP_WORK + 6          ;; READ_NUMBER: the power of ten the digits read must be multiplied by
NEAREST_INTEGER = FP_WORK + 7       ;; FRACTIONAL_PART: the low byte of the integer nearest FPA, signed
MULTIPLIER = FP_WORK                ;; MULTIPLY_FP_A_UNNORMALISED: FPA's mantissa while it is multiplied, four bytes

;; Reads a number in decimal at PTRB: digits with an optional decimal point, then an optional exponent, E and a
;; signed number.
;;
;; The digits are gathered as a 40-bit integer in FPA's five mantissa bytes, the rounding byte the lowest, multiplying
;; by ten for each one; <NUMBER_SCALE> counts the power of ten to apply. Once the integer reaches &18 in its top byte,
;; a ten times larger one might not fit, so further digits are dropped: one before the point adds one to the scale,
;; one after it is ignored. A number with neither a point nor an exponent that fits in 31 bits is returned as an
;; integer in IntA. Any other is normalised into FPA and multiplied or divided by ten once for each power of the scale,
;; then rounded.
;; In: A = the first character, a digit or a point, Y = its offset from PTR_B
;; Out: carry = set when a number was read, A = &40 with the number in IntA or &FF with it in FP_A,
;;   PTR_B_OFFSET = just past the number
;; Uses: X, Y, FP_WORK, FP_WORK+5..FP_WORK+7, FP_B
;; See: <NOT_A_NUMBER>
READ_NUMBER:
    ldx #$00
    stx FP_A_MANTISSA
    stx FP_A_MANTISSA+1
    stx FP_A_MANTISSA+2
    stx FP_A_MANTISSA+3
    stx FP_A_ROUNDING
    stx NUMBER_POINT_SEEN
    stx NUMBER_SCALE
    cmp #'.'
    beq READ_NUMBER_POINT
    cmp #'9' + 1
    bcs NOT_A_NUMBER                           ; not a number: returns with carry clear
    sbc #'0' - 1                        ; carry is clear: subtracts '0'
    bmi NOT_A_NUMBER
    sta FP_A_ROUNDING                   ; the first digit, in the lowest byte
READ_NUMBER_NEXT:
    iny
    lda (PTR_B),y
    cmp #'.'
    bne READ_NUMBER_CHARACTER
READ_NUMBER_POINT:
    lda NUMBER_POINT_SEEN
    bne READ_NUMBER_END                 ; a second point ends the number
    inc NUMBER_POINT_SEEN
    bne READ_NUMBER_NEXT                ; always
READ_NUMBER_CHARACTER:
    cmp #'E'
    beq READ_NUMBER_EXPONENT
    cmp #'9' + 1
    bcs READ_NUMBER_END
    sbc #'0' - 1                        ; carry is clear: subtracts '0'
    bcc READ_NUMBER_END
    ldx FP_A_MANTISSA
    cpx #$18
    bcc READ_NUMBER_DIGIT               ; room for ten times more
    ldx NUMBER_POINT_SEEN
    bne READ_NUMBER_NEXT                ; a dropped digit after the point changes nothing
    inc NUMBER_SCALE                    ; one before it makes the number ten times larger
    bcs READ_NUMBER_NEXT                ; always: carry is still set from the CPX
READ_NUMBER_DIGIT:
    ldx NUMBER_POINT_SEEN
    beq READ_NUMBER_ADD_DIGIT
    dec NUMBER_SCALE                    ; a digit after the point is a tenth of one before it
READ_NUMBER_ADD_DIGIT:
    jsr MULTIPLY_MANTISSA_BY_TEN        ; keeps A, the digit; carry is clear
    adc FP_A_ROUNDING
    sta FP_A_ROUNDING
    bcc READ_NUMBER_NEXT
    inc FP_A_MANTISSA+3
    bne READ_NUMBER_NEXT
    inc FP_A_MANTISSA+2
    bne READ_NUMBER_NEXT
    inc FP_A_MANTISSA+1
    bne READ_NUMBER_NEXT
    inc FP_A_MANTISSA
    bne READ_NUMBER_NEXT                ; always: the top byte was below &18
READ_NUMBER_EXPONENT:
    jsr READ_EXPONENT                   ; carry is set for a negative exponent, completing its negation
    adc NUMBER_SCALE
    sta NUMBER_SCALE
READ_NUMBER_END:
    sty PTR_B_OFFSET
    lda NUMBER_SCALE
    ora NUMBER_POINT_SEEN
    beq READ_NUMBER_INTEGER             ; neither a point nor an exponent
    jsr TEST_FP_A
    beq READ_NUMBER_DONE                ; zero needs no scaling
READ_NUMBER_REAL:
    lda #REAL_EXPONENT_BIAS + 40        ; the mantissa holds a 40-bit integer
    sta FP_A_EXPONENT
    lda #$00
    sta FP_A_OVERFLOW
    sta FP_A_SIGN
    jsr NORMALISE_FP_A
    lda NUMBER_SCALE
    bmi READ_NUMBER_DIVIDE
    beq READ_NUMBER_ROUND
READ_NUMBER_MULTIPLY:
    jsr MULTIPLY_FP_A_BY_TEN
    dec NUMBER_SCALE
    bne READ_NUMBER_MULTIPLY
    beq READ_NUMBER_ROUND               ; always
READ_NUMBER_DIVIDE:
    jsr DIVIDE_FP_A_BY_TEN
    inc NUMBER_SCALE
    bne READ_NUMBER_DIVIDE
READ_NUMBER_ROUND:
    jsr ROUND_FP_A
READ_NUMBER_DONE:
    sec
    lda #$FF                            ; a real
    rts
READ_NUMBER_INTEGER:
    lda FP_A_MANTISSA+1
    sta INT_A+3
    and #$80
    ora FP_A_MANTISSA
    bne READ_NUMBER_REAL                ; more than 31 bits
    lda FP_A_ROUNDING
    sta INT_A
    lda FP_A_MANTISSA+3
    sta INT_A+1
    lda FP_A_MANTISSA+2
    sta INT_A+2
    lda #$40                            ; an integer
    sec
    rts

;; The part of <READ_EXPONENT> for a minus sign: reads the digits and returns their negative.
;; In: Y = the offset from PTR_B of the minus sign
;; Out: A = the exponent's one's complement, carry = set, so that adding A with carry adds the negative exponent,
;;   Y = just past the digits
;; Uses: FP_WORK, FP_WORK+7
READ_NEGATIVE_EXPONENT:
    jsr READ_EXPONENT_SIGNED
    eor #$FF
    sec
    rts

;; Reads a number's exponent, the signed number after its E: an optional sign and up to two digits.
;;
;; No digits give an exponent of zero, and a third digit is left unread.
;; In: Y = the offset from PTR_B of the E
;; Out: A = the exponent, or its one's complement when negative, carry = set when negative, so that adding A with carry
;;   adds the exponent, Y = just past the digits
;; Uses: FP_WORK, FP_WORK+7
;; Entry: READ_EXPONENT_SIGNED = reads the character after the one at Y as the first digit
READ_EXPONENT:
    iny
    lda (PTR_B),y
    cmp #'-'
    beq READ_NEGATIVE_EXPONENT
    cmp #'+'
    bne READ_EXPONENT_FIRST
READ_EXPONENT_SIGNED:
    iny
    lda (PTR_B),y
READ_EXPONENT_FIRST:
    cmp #'9' + 1
    bcs READ_EXPONENT_NONE
    sbc #'0' - 1                        ; carry is clear: subtracts '0'
    bcc READ_EXPONENT_NONE
    sta FP_WORK+7                       ; the first digit
    iny
    lda (PTR_B),y
    cmp #'9' + 1
    bcs READ_EXPONENT_ONE_DIGIT
    sbc #'0' - 1
    bcc READ_EXPONENT_ONE_DIGIT
    iny
    sta FP_WORK                         ; the second digit
    lda FP_WORK+7
    asl a
    asl a
    adc FP_WORK+7
    asl a                               ; the first digit times ten
    adc FP_WORK
    rts
READ_EXPONENT_ONE_DIGIT:
    lda FP_WORK+7
    clc
    rts
READ_EXPONENT_NONE:
    lda #$00
    clc
    rts

;; Adds FPB's mantissa to FPA's, all five bytes, rounding byte included.
;; In: carry = added in
;; Out: carry = the carry out of the top
;; Keeps: X, Y
;; See: <ADD_FP_B_MANTISSA_CARRY>
ADD_FP_B_MANTISSA:
    lda FP_A_ROUNDING
    adc FP_B_ROUNDING
    sta FP_A_ROUNDING
    lda FP_A_MANTISSA+3
    adc FP_B_MANTISSA+3
    sta FP_A_MANTISSA+3
    lda FP_A_MANTISSA+2
    adc FP_B_MANTISSA+2
    sta FP_A_MANTISSA+2
    lda FP_A_MANTISSA+1
    adc FP_B_MANTISSA+1
    sta FP_A_MANTISSA+1
    lda FP_A_MANTISSA
    adc FP_B_MANTISSA
    sta FP_A_MANTISSA
    rts

;; Multiplies FPA's five mantissa bytes by ten, as one 40-bit number: four times it plus it, doubled.
;;
;; <READ_NUMBER> gathers its digits with it, and the conversion of numbers to strings takes their digits from the top
;; byte with it.
;; In: carry = clear
;; Out: carry = the bit carried out of the top
;; Uses: X
;; Keeps: A, Y
MULTIPLY_MANTISSA_BY_TEN:
    pha
    ldx FP_A_MANTISSA+3
    lda FP_A_MANTISSA
    pha
    lda FP_A_MANTISSA+1
    pha
    lda FP_A_MANTISSA+2
    pha                                 ; the original value, with X, to add
    lda FP_A_ROUNDING
    asl a
    rol FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol FP_A_MANTISSA
    asl a
    rol FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol FP_A_MANTISSA                   ; times four
    adc FP_A_ROUNDING
    sta FP_A_ROUNDING
    txa
    adc FP_A_MANTISSA+3
    sta FP_A_MANTISSA+3
    pla
    adc FP_A_MANTISSA+2
    sta FP_A_MANTISSA+2
    pla
    adc FP_A_MANTISSA+1
    sta FP_A_MANTISSA+1
    pla
    adc FP_A_MANTISSA                   ; times five
    asl FP_A_ROUNDING
    rol FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol a                               ; times ten
    sta FP_A_MANTISSA
    pla
    rts

;; Tests FPA for zero and its sign, and makes a zero mantissa a true zero.
;;
;; A zero mantissa also clears the sign, the exponent and its overflow byte.
;; Out: A = 0 for zero, 1 for a positive number, the sign byte for a negative one, zero = FP_A is zero,
;;   negative = FP_A is negative
;; Keeps: X, Y
TEST_FP_A:
    lda FP_A_MANTISSA
    ora FP_A_MANTISSA+1
    ora FP_A_MANTISSA+2
    ora FP_A_MANTISSA+3
    ora FP_A_ROUNDING
    beq TEST_FP_A_ZERO
    lda FP_A_SIGN
    bne TEST_FP_A_DONE
    lda #$01
    rts
TEST_FP_A_ZERO:
    sta FP_A_SIGN
    sta FP_A_EXPONENT
    sta FP_A_OVERFLOW
TEST_FP_A_DONE:
    rts

;; Multiplies FPA by ten, as eight times it plus a quarter of that.
;;
;; It adds three to the exponent, then adds a quarter of the mantissa to itself, falling into
;; <ADD_FP_B_MANTISSA_CARRY>. The result is not rounded.
;; Uses: A, FP_B
;; Keeps: X, Y
MULTIPLY_FP_A_BY_TEN:
    clc
    lda FP_A_EXPONENT
    adc #$03                            ; times eight
    sta FP_A_EXPONENT
    bcc MULTIPLY_FP_A_BY_TEN_1
    inc FP_A_OVERFLOW
MULTIPLY_FP_A_BY_TEN_1:
    jsr COPY_FP_A_TO_FP_B
    jsr HALVE_FP_B_MANTISSA
    jsr HALVE_FP_B_MANTISSA             ; a quarter, to make ten from eight

;; Adds FPB's mantissa to FPA's, and on a carry out of the top shifts it back in, adding one to the exponent.
;; In: carry = added in
;; Uses: A
;; Keeps: X, Y
;; Entry: SHIFT_IN_MANTISSA_CARRY = only shifts in the carry, when it is set
ADD_FP_B_MANTISSA_CARRY:
    jsr ADD_FP_B_MANTISSA
SHIFT_IN_MANTISSA_CARRY:
    bcc SHIFT_IN_MANTISSA_CARRY_DONE
    ror FP_A_MANTISSA
    ror FP_A_MANTISSA+1
    ror FP_A_MANTISSA+2
    ror FP_A_MANTISSA+3
    ror FP_A_ROUNDING
    inc FP_A_EXPONENT
    bne SHIFT_IN_MANTISSA_CARRY_DONE
    inc FP_A_OVERFLOW
SHIFT_IN_MANTISSA_CARRY_DONE:
    rts

;; Copies FPA into FPB, all eight bytes.
;; Uses: A
;; Keeps: X, Y
COPY_FP_A_TO_FP_B:
    lda FP_A_SIGN
    sta FP_B_SIGN
    lda FP_A_OVERFLOW
    sta FP_B_OVERFLOW
    lda FP_A_EXPONENT
    sta FP_B_EXPONENT
    lda FP_A_MANTISSA
    sta FP_B_MANTISSA
    lda FP_A_MANTISSA+1
    sta FP_B_MANTISSA+1
    lda FP_A_MANTISSA+2
    sta FP_B_MANTISSA+2
    lda FP_A_MANTISSA+3
    sta FP_B_MANTISSA+3
    lda FP_A_ROUNDING
    sta FP_B_ROUNDING
    rts

;; Copies FPA into FPB and halves FPB's mantissa, falling into <HALVE_FP_B_MANTISSA>.
;; Uses: A
;; Keeps: X, Y
COPY_HALF_FP_A_TO_FP_B:
    jsr COPY_FP_A_TO_FP_B

;; Shifts FPB's five mantissa bytes right one bit, halving the mantissa without changing the exponent.
;; Keeps: A, X, Y
HALVE_FP_B_MANTISSA:
    lsr FP_B_MANTISSA
    ror FP_B_MANTISSA+1
    ror FP_B_MANTISSA+2
    ror FP_B_MANTISSA+3
    ror FP_B_ROUNDING
    rts

;; Divides FPA by ten, as a sixteenth of it times 1.6.
;;
;; It takes four from the exponent, then multiplies the mantissa by 1.5 and by 1.0625, which make 1.59375, and by
;; 1 + 2^-8, 1 + 2^-16 and 1 + 2^-32, which together make 256/255 to the precision kept, giving 1.6. Each step adds a
;; shifted copy of the mantissa: the first two through FPB shifted by bits, the last three by whole bytes, the last
;; only into the rounding byte, each with the bit below the copy as the carry in. The result is not rounded.
;; Uses: A, FP_B
;; Keeps: X, Y
DIVIDE_FP_A_BY_TEN:
    sec
    lda FP_A_EXPONENT
    sbc #$04                            ; a sixteenth
    sta FP_A_EXPONENT
    bcs DIVIDE_FP_A_BY_TEN_1
    dec FP_A_OVERFLOW
DIVIDE_FP_A_BY_TEN_1:
    jsr COPY_HALF_FP_A_TO_FP_B
    jsr ADD_FP_B_MANTISSA_CARRY         ; times 1.5
    jsr COPY_HALF_FP_A_TO_FP_B
    jsr HALVE_FP_B_MANTISSA
    jsr HALVE_FP_B_MANTISSA
    jsr HALVE_FP_B_MANTISSA
    jsr ADD_FP_B_MANTISSA_CARRY         ; times 1.0625
    lda #$00
    sta FP_B_MANTISSA
    lda FP_A_MANTISSA
    sta FP_B_MANTISSA+1
    lda FP_A_MANTISSA+1
    sta FP_B_MANTISSA+2
    lda FP_A_MANTISSA+2
    sta FP_B_MANTISSA+3
    lda FP_A_MANTISSA+3
    sta FP_B_ROUNDING
    lda FP_A_ROUNDING
    rol a                               ; the bit below the copy rounds it
    jsr ADD_FP_B_MANTISSA_CARRY         ; times 1 + 2^-8
    lda #$00
    sta FP_B_MANTISSA
    sta FP_B_MANTISSA+1
    lda FP_A_MANTISSA
    sta FP_B_MANTISSA+2
    lda FP_A_MANTISSA+1
    sta FP_B_MANTISSA+3
    lda FP_A_MANTISSA+2
    sta FP_B_ROUNDING
    lda FP_A_MANTISSA+3
    rol a
    jsr ADD_FP_B_MANTISSA_CARRY         ; times 1 + 2^-16
    lda FP_A_MANTISSA+1
    rol a
    lda FP_A_MANTISSA                   ; times 1 + 2^-32, into the rounding byte: falls into ADD_A_TO_MANTISSA

;; Adds A to FPA's rounding byte and carries up through the mantissa, shifting a carry out of the top back in.
;;
;; <ROUND_FP_A> rounds up with it by adding &FF with carry set, which leaves the rounding byte as it was and adds one
;; to the mantissa's lowest byte.
;; In: A = the byte to add, carry = added in
;; Uses: A
;; Keeps: X, Y
ADD_A_TO_MANTISSA:
    adc FP_A_ROUNDING
    sta FP_A_ROUNDING
    bcc ADD_A_TO_MANTISSA_DONE
    inc FP_A_MANTISSA+3
    bne ADD_A_TO_MANTISSA_DONE
    inc FP_A_MANTISSA+2
    bne ADD_A_TO_MANTISSA_DONE
    inc FP_A_MANTISSA+1
    bne ADD_A_TO_MANTISSA_DONE
    inc FP_A_MANTISSA
    bne ADD_A_TO_MANTISSA_DONE
    jmp SHIFT_IN_MANTISSA_CARRY         ; the mantissa wrapped to zero: carry is set
ADD_A_TO_MANTISSA_DONE:
    rts

;; Converts IntA to a real in FPA.
;;
;; A negative integer is negated in IntA itself, and FPA's sign set. The four bytes become the mantissa, with the
;; exponent of a 32-bit integer, then FPA is normalised.
;; In: INT_A = the integer
;; Out: FP_A = the integer as a real, zero = it is zero
;; Uses: A, X, Y, INT_A
INTEGER_TO_REAL:
    ldx #$00
    stx FP_A_ROUNDING
    stx FP_A_OVERFLOW
    lda INT_A+3
    bpl INTEGER_TO_REAL_SIGN
    jsr NEGATE_INT_A
    ldx #$FF
INTEGER_TO_REAL_SIGN:
    stx FP_A_SIGN
    lda INT_A
    sta FP_A_MANTISSA+3
    lda INT_A+1
    sta FP_A_MANTISSA+2
    lda INT_A+2
    sta FP_A_MANTISSA+1
    lda INT_A+3
    sta FP_A_MANTISSA
    lda #REAL_EXPONENT_BIAS + 32        ; the mantissa holds a 32-bit integer
    sta FP_A_EXPONENT
    jmp NORMALISE_FP_A

;; The end of <NORMALISE_FP_A> for a zero mantissa: clears the sign, the exponent and its overflow byte.
;; In: A = 0
;; Out: zero = set
;; Entry: NORMALISE_FP_A_DONE = only returns
NORMALISE_FP_A_ZERO:
    sta FP_A_SIGN
    sta FP_A_EXPONENT
    sta FP_A_OVERFLOW
NORMALISE_FP_A_DONE:
    rts

;; Converts A, a signed byte, to a real in FPA, falling into <NORMALISE_FP_A>.
;; In: A = the number, -128 to 127
;; Out: FP_A = the number as a real
;; Uses: A, X, Y
BYTE_TO_REAL:
    pha
    jsr ZERO_FP_A
    pla
    beq NORMALISE_FP_A_DONE
    bpl BYTE_TO_REAL_MAGNITUDE
    sta FP_A_SIGN                       ; bit 7 set: negative
    lda #$00
    sec
    sbc FP_A_SIGN
BYTE_TO_REAL_MAGNITUDE:
    sta FP_A_MANTISSA
    lda #REAL_EXPONENT_BIAS + 8         ; the mantissa's top byte holds an 8-bit integer
    sta FP_A_EXPONENT

;; Normalises FPA: shifts the mantissa left until its top bit is set, taking one from the exponent for each bit.
;;
;; It shifts by whole bytes while the top byte is zero, then by bits. A borrow from the exponent decrements the
;; overflow byte, which <ROUND_FP_A> then reads as an underflow. A zero mantissa makes FPA a true zero.
;; Out: zero = FP_A is zero
;; Uses: A, X, Y
NORMALISE_FP_A:
    lda FP_A_MANTISSA
    bmi NORMALISE_FP_A_DONE             ; already normalised
    ora FP_A_MANTISSA+1
    ora FP_A_MANTISSA+2
    ora FP_A_MANTISSA+3
    ora FP_A_ROUNDING
    beq NORMALISE_FP_A_ZERO
    lda FP_A_EXPONENT
NORMALISE_FP_A_BYTES:
    ldy FP_A_MANTISSA
    bmi NORMALISE_FP_A_DONE
    bne NORMALISE_FP_A_SHIFT            ; the top byte is not zero: shift by bits
    ldx FP_A_MANTISSA+1
    stx FP_A_MANTISSA
    ldx FP_A_MANTISSA+2
    stx FP_A_MANTISSA+1
    ldx FP_A_MANTISSA+3
    stx FP_A_MANTISSA+2
    ldx FP_A_ROUNDING
    stx FP_A_MANTISSA+3
    sty FP_A_ROUNDING                   ; Y is zero
    sec
    sbc #$08
    sta FP_A_EXPONENT
    bcs NORMALISE_FP_A_BYTES
    dec FP_A_OVERFLOW
    bcc NORMALISE_FP_A_BYTES            ; always
NORMALISE_FP_A_BITS:
    ldy FP_A_MANTISSA
    bmi NORMALISE_FP_A_DONE
NORMALISE_FP_A_SHIFT:
    asl FP_A_ROUNDING
    rol FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol FP_A_MANTISSA                   ; the top bit was clear, so carry is clear
    sbc #$00                            ; ... and this takes one
    sta FP_A_EXPONENT
    bcs NORMALISE_FP_A_BITS
    dec FP_A_OVERFLOW
    bcc NORMALISE_FP_A_BITS             ; always

;; Loads the packed real at FP_POINTER into FPB, unpacking its sign.
;; In: FP_POINTER = the packed real
;; Out: FP_B = the number, zero = it is zero, Y = 0
;; Uses: A
;; Keeps: X
LOAD_FP_B:
    ldy #$04
    lda (FP_POINTER),y
    sta FP_B_MANTISSA+3
    dey
    lda (FP_POINTER),y
    sta FP_B_MANTISSA+2
    dey
    lda (FP_POINTER),y
    sta FP_B_MANTISSA+1
    dey
    lda (FP_POINTER),y
    sta FP_B_SIGN                       ; bit 7 is the sign
    dey
    sty FP_B_ROUNDING
    sty FP_B_OVERFLOW
    lda (FP_POINTER),y
    sta FP_B_EXPONENT
    ora FP_B_SIGN
    ora FP_B_MANTISSA+1
    ora FP_B_MANTISSA+2
    ora FP_B_MANTISSA+3
    beq LOAD_FP_B_MANTISSA              ; zero: the mantissa's top byte is zero too
    lda FP_B_SIGN
    ora #$80                            ; the top bit the sign replaced
LOAD_FP_B_MANTISSA:
    sta FP_B_MANTISSA
    rts

;; Stores FPA in <FP_TEMP_2> and points FP_POINTER at it.
;; Out: FP_POINTER = FP_TEMP_2, Y = 4
;; Uses: A
;; Keeps: X
STORE_FP_A_TEMP_2:
    lda #<FP_TEMP_2
    bne STORE_FP_A_PAGE_FOUR            ; always

;; Stores FPA in <FP_TEMP_3> and points FP_POINTER at it.
;; Out: FP_POINTER = FP_TEMP_3, Y = 4
;; Uses: A
;; Keeps: X
STORE_FP_A_TEMP_3:
    lda #<FP_TEMP_3
    bne STORE_FP_A_PAGE_FOUR            ; always

;; Stores FPA in <FP_TEMP_1> and points FP_POINTER at it, falling into <STORE_FP_A_PAGE_FOUR>.
;; Out: FP_POINTER = FP_TEMP_1, Y = 4
;; Uses: A
;; Keeps: X
STORE_FP_A_TEMP_1:
    lda #<FP_TEMP_1

;; Points FP_POINTER at a packed real in page four and stores FPA there, falling into <STORE_FP_A>.
;; In: A = the low byte of its address
;; Out: FP_POINTER = the address, Y = 4
;; Uses: A
;; Keeps: X
STORE_FP_A_PAGE_FOUR:
    sta FP_POINTER
    lda #>FP_TEMP_1
    sta FP_POINTER+1
    .assert >FP_TEMP_1 = >FP_TEMP_4, "The packed reals in page four share a high byte."

;; Stores FPA as a packed real at FP_POINTER, its rounding byte dropped.
;;
;; The sign takes the place of the mantissa's top bit. It also clears all but bit 7 of FPA's sign byte.
;; In: FP_POINTER = where to store it
;; Out: Y = 4
;; Uses: A
;; Keeps: X
STORE_FP_A:
    ldy #$00
    lda FP_A_EXPONENT
    sta (FP_POINTER),y
    iny
    lda FP_A_SIGN
    and #$80
    sta FP_A_SIGN
    lda FP_A_MANTISSA
    and #$7F
    ora FP_A_SIGN
    sta (FP_POINTER),y
    lda FP_A_MANTISSA+1
    iny
    sta (FP_POINTER),y
    lda FP_A_MANTISSA+2
    iny
    sta (FP_POINTER),y
    lda FP_A_MANTISSA+3
    iny
    sta (FP_POINTER),y
    rts

;; Loads <FP_TEMP_1> into FPA, falling into <LOAD_FP_A>.
;; Out: FP_A = the number, zero = it is zero, FP_POINTER = FP_TEMP_1, Y = 0
;; Uses: A
;; Keeps: X
LOAD_FP_A_TEMP_1:
    jsr POINT_AT_FP_TEMP_1

;; Loads the packed real at FP_POINTER into FPA, unpacking its sign.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the number, zero = it is zero, Y = 0
;; Uses: A
;; Keeps: X
LOAD_FP_A:
    ldy #$04
    lda (FP_POINTER),y
    sta FP_A_MANTISSA+3
    dey
    lda (FP_POINTER),y
    sta FP_A_MANTISSA+2
    dey
    lda (FP_POINTER),y
    sta FP_A_MANTISSA+1
    dey
    lda (FP_POINTER),y
    sta FP_A_SIGN                       ; bit 7 is the sign
    dey
    lda (FP_POINTER),y
    sta FP_A_EXPONENT
    sty FP_A_ROUNDING
    sty FP_A_OVERFLOW
    ora FP_A_SIGN
    ora FP_A_MANTISSA+1
    ora FP_A_MANTISSA+2
    ora FP_A_MANTISSA+3
    beq LOAD_FP_A_MANTISSA              ; zero: the mantissa's top byte is zero too
    lda FP_A_SIGN
    ora #$80                            ; the top bit the sign replaced
LOAD_FP_A_MANTISSA:
    sta FP_A_MANTISSA
    rts

;; Converts FPA to an integer in IntA, truncating towards zero.
;;
;; It converts FPA to the fixed format with <REAL_TO_FIXED>, then copies the integer part to IntA.
;; Out: INT_A = the integer, FP_A_MANTISSA = the same integer, FP_B_MANTISSA = the fraction dropped
;; Uses: A
;; Entry: FIXED_TO_INT_A = only copies FPA's mantissa, already in the fixed format, to IntA
;; Errors: 20 (Too big) = the number is 2^31 or more in size
REAL_TO_INTEGER:
    jsr REAL_TO_FIXED
FIXED_TO_INT_A:
    lda FP_A_MANTISSA
    sta INT_A+3
    lda FP_A_MANTISSA+1
    sta INT_A+2
    lda FP_A_MANTISSA+2
    sta INT_A+1
    lda FP_A_MANTISSA+3
    sta INT_A
    rts

;; The part of <REAL_TO_FIXED> for a number below 0.5 in size: the integer part is zero and FPB the whole number.
;; Out: FP_A = zero, FP_B = the number, unchanged
;; Uses: A
REAL_TO_FIXED_SMALL:
    jsr COPY_FP_A_TO_FP_B
    jmp ZERO_FP_A

;; Converts FPA to the fixed format: its integer part in FPA's mantissa and its fraction in FPB's.
;;
;; The mantissa is shifted right into FPB's mantissa, by bytes and then by bits, until the exponent is that of a
;; 32-bit integer. Its four bytes are then the integer part, truncated towards zero, which is negated for a negative
;; number, and FPB's four mantissa bytes the fraction's size, as a binary fraction. A number below 0.5 in size gives an
;; integer part of zero, with FPB a copy of the number instead.
;; Out: FP_A_MANTISSA = the integer part, two's complement, most significant byte first, FP_B_MANTISSA = the fraction
;; Uses: A
;; Keeps: X, Y
;; Errors: 20 (Too big) = the number is 2^31 or more in size
REAL_TO_FIXED:
    lda FP_A_EXPONENT
    bpl REAL_TO_FIXED_SMALL
    jsr ZERO_FP_B
    jsr TEST_FP_A
    bne REAL_TO_FIXED_BITS
    beq REAL_TO_FIXED_SIGN              ; always
REAL_TO_FIXED_LOOP:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_BIAS + 32
    bcs REAL_TO_FIXED_LAST              ; at or past the exponent of a 32-bit integer
    cmp #REAL_EXPONENT_BIAS + 25
    bcs REAL_TO_FIXED_BITS              ; less than a byte to go
    adc #$08                            ; carry is clear
    sta FP_A_EXPONENT
    lda FP_B_MANTISSA+2
    sta FP_B_MANTISSA+3
    lda FP_B_MANTISSA+1
    sta FP_B_MANTISSA+2
    lda FP_B_MANTISSA
    sta FP_B_MANTISSA+1
    lda FP_A_MANTISSA+3
    sta FP_B_MANTISSA
    lda FP_A_MANTISSA+2
    sta FP_A_MANTISSA+3
    lda FP_A_MANTISSA+1
    sta FP_A_MANTISSA+2
    lda FP_A_MANTISSA
    sta FP_A_MANTISSA+1
    lda #$00
    sta FP_A_MANTISSA
    beq REAL_TO_FIXED_LOOP              ; always
REAL_TO_FIXED_BITS:
    lsr FP_A_MANTISSA
    ror FP_A_MANTISSA+1
    ror FP_A_MANTISSA+2
    ror FP_A_MANTISSA+3
    ror FP_B_MANTISSA
    ror FP_B_MANTISSA+1
    ror FP_B_MANTISSA+2
    ror FP_B_MANTISSA+3
    inc FP_A_EXPONENT
    bne REAL_TO_FIXED_LOOP              ; always

;; A jump to <TOO_BIG_ERROR> that branches can reach.
JUMP_TOO_BIG:
    jmp TOO_BIG_ERROR

;; Sets FPB to zero, all eight bytes.
;; Out: A = 0, zero = set
;; Keeps: X, Y
ZERO_FP_B:
    lda #$00
    sta FP_B_SIGN
    sta FP_B_OVERFLOW
    sta FP_B_EXPONENT
    sta FP_B_MANTISSA
    sta FP_B_MANTISSA+1
    sta FP_B_MANTISSA+2
    sta FP_B_MANTISSA+3
    sta FP_B_ROUNDING
    rts

;; The end of <REAL_TO_FIXED>, once the exponent has reached that of a 32-bit integer or passed it.
;;
;; Past it, the number was too big. At it, a negative number's integer part is negated, falling into
;; <NEGATE_MANTISSA>.
;; In: zero = the exponent is exactly that of a 32-bit integer
;; Entry: REAL_TO_FIXED_SIGN = only negates the integer part of a negative number
;; Errors: 20 (Too big) = the exponent passed it
REAL_TO_FIXED_LAST:
    bne JUMP_TOO_BIG
REAL_TO_FIXED_SIGN:
    lda FP_A_SIGN
    bpl NEGATE_MANTISSA_DONE

;; Negates FPA's four mantissa bytes as a two's complement integer.
;; Out: carry = set when the mantissa was zero
;; Uses: A
;; Keeps: X, Y
;; Entry: NEGATE_MANTISSA_DONE = only returns
NEGATE_MANTISSA:
    sec
    lda #$00
    sbc FP_A_MANTISSA+3
    sta FP_A_MANTISSA+3
    lda #$00
    sbc FP_A_MANTISSA+2
    sta FP_A_MANTISSA+2
    lda #$00
    sbc FP_A_MANTISSA+1
    sta FP_A_MANTISSA+1
    lda #$00
    sbc FP_A_MANTISSA
    sta FP_A_MANTISSA
NEGATE_MANTISSA_DONE:
    rts

;; Splits FPA into the integer nearest it and what is left, a fraction of at most a half in size.
;;
;; The integer comes from <REAL_TO_FIXED>. When the fraction is a half or more, the integer is moved one further from
;; zero and the fraction becomes its complement, of the other sign. A number below 0.5 in size is its own fraction.
;; EXP and the ^ operator use it to split off a whole power.
;; Out: FP_A = the fraction, normalised, zero = it is zero, NEAREST_INTEGER = the integer's low byte, signed
;; Uses: A, X, Y, FP_B
;; Errors: 20 (Too big) = the number is 2^31 or more in size
FRACTIONAL_PART:
    lda FP_A_EXPONENT
    bmi FRACTIONAL_PART_SPLIT           ; 0.5 or more in size
    lda #$00
    sta NEAREST_INTEGER
    jmp TEST_FP_A
FRACTIONAL_PART_SPLIT:
    jsr REAL_TO_FIXED
    lda FP_A_MANTISSA+3
    sta NEAREST_INTEGER
    jsr COPY_FP_B_MANTISSA_TO_FP_A
    lda #REAL_EXPONENT_BIAS             ; the mantissa is a fraction below 1
    sta FP_A_EXPONENT
    ldx FP_A_MANTISSA
    bpl FRACTIONAL_PART_DONE            ; below a half
    eor FP_A_SIGN                       ; the other sign
    sta FP_A_SIGN
    bpl FRACTIONAL_PART_DOWN
    inc NEAREST_INTEGER                 ; a positive number rounds up
    jmp FRACTIONAL_PART_COMPLEMENT
FRACTIONAL_PART_DOWN:
    dec NEAREST_INTEGER                 ; a negative one rounds down
FRACTIONAL_PART_COMPLEMENT:
    jsr NEGATE_MANTISSA                 ; one less the fraction
FRACTIONAL_PART_DONE:
    jmp NORMALISE_FP_A

;; Adds one to FPA's four mantissa bytes as an integer.
;; Keeps: A, X, Y
;; Errors: 20 (Too big) = the mantissa wraps to zero
INCREMENT_MANTISSA:
    inc FP_A_MANTISSA+3
    bne INCREMENT_MANTISSA_DONE
    inc FP_A_MANTISSA+2
    bne INCREMENT_MANTISSA_DONE
    inc FP_A_MANTISSA+1
    bne INCREMENT_MANTISSA_DONE
    inc FP_A_MANTISSA
    beq JUMP_TOO_BIG
INCREMENT_MANTISSA_DONE:
    rts

;; Takes one from FPA's four mantissa bytes as a two's complement integer, by negating, adding one and negating.
;;
;; INT uses it to round a negative number with a fraction down.
;; Uses: A
;; Keeps: X, Y
;; Errors: 20 (Too big) = the mantissa was 1
DECREMENT_MANTISSA:
    jsr NEGATE_MANTISSA
    jsr INCREMENT_MANTISSA
    jmp NEGATE_MANTISSA

;; Subtracts the packed real at FP_POINTER from FPA, as the negative of it less FPA, rounded.
;; In: FP_POINTER = the packed real
;; Out: FP_A = FP_A less the number, A = &FF
;; Uses: X, Y, FP_B
SUBTRACT_FROM_FP_A:
    jsr SUBTRACT_FP_A_FROM
    jmp NEGATE_FP_A

;; Exchanges FPA with the packed real at FP_POINTER, falling into <COPY_FP_B_TO_FP_A>.
;;
;; FPA's rounding byte is lost.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the number, FP_B = the number too, Y = 4
;; Uses: A
;; Keeps: X
EXCHANGE_FP_A:
    jsr LOAD_FP_B
    jsr STORE_FP_A

;; Copies FPB into FPA, all eight bytes.
;; Uses: A
;; Keeps: X, Y
;; Entry: COPY_FP_B_MANTISSA_TO_FP_A = copies only the five mantissa bytes, COPY_FP_B_TO_FP_A_DONE = only returns
COPY_FP_B_TO_FP_A:
    lda FP_B_SIGN
    sta FP_A_SIGN
    lda FP_B_OVERFLOW
    sta FP_A_OVERFLOW
    lda FP_B_EXPONENT
    sta FP_A_EXPONENT
COPY_FP_B_MANTISSA_TO_FP_A:
    lda FP_B_MANTISSA
    sta FP_A_MANTISSA
    lda FP_B_MANTISSA+1
    sta FP_A_MANTISSA+1
    lda FP_B_MANTISSA+2
    sta FP_A_MANTISSA+2
    lda FP_B_MANTISSA+3
    sta FP_A_MANTISSA+3
    lda FP_B_ROUNDING
    sta FP_A_ROUNDING
COPY_FP_B_TO_FP_A_DONE:
    rts

;; Subtracts FPA from the packed real at FP_POINTER, by negating FPA and falling into <ADD_TO_FP_A>.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the number less FP_A
;; Uses: A, X, Y, FP_B
SUBTRACT_FP_A_FROM:
    jsr NEGATE_FP_A

;; Adds the packed real at FP_POINTER to FPA, rounded.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the sum
;; Uses: A, X, Y, FP_B
;; Errors: 20 (Too big) = the sum is too large
ADD_TO_FP_A:
    jsr LOAD_FP_B
    beq COPY_FP_B_TO_FP_A_DONE          ; adding zero

;; Adds FPB to FPA, rounded.
;; Out: FP_A = the sum
;; Uses: A, X, Y
;; Errors: 20 (Too big) = the sum is too large
ADD_FP_B_TO_FP_A:
    jsr ADD_FP_B_UNROUNDED
    jmp ROUND_FP_A

;; Adds FPB to FPA without rounding.
;;
;; The number with the smaller exponent is shifted right to line up with the other, by bytes and then by bits; if it
;; would be shifted 37 bits or more it is too small to count, and the other is the sum. Mantissas of the same sign are
;; added; of opposite signs, the smaller is taken from the larger, which gives the sign, and the result normalised.
;; Out: FP_A = the sum
;; Uses: A, X, Y, FP_B
ADD_FP_B_UNROUNDED:
    jsr TEST_FP_A
    beq COPY_FP_B_TO_FP_A
    ldy #$00
    sec
    lda FP_A_EXPONENT
    sbc FP_B_EXPONENT
    beq ADD_FP_B_UNROUNDED_ALIGNED
    bcc ADD_FP_B_UNROUNDED_SHIFT_A      ; FPB is the larger
    cmp #37
    bcs COPY_FP_B_TO_FP_A_DONE          ; FPB is too small to count
    pha
    and #%00111000
    beq ADD_FP_B_UNROUNDED_B_BITS
    lsr a
    lsr a
    lsr a
    tax                                 ; whole bytes to shift
ADD_FP_B_UNROUNDED_B_BYTES:
    lda FP_B_MANTISSA+3
    sta FP_B_ROUNDING
    lda FP_B_MANTISSA+2
    sta FP_B_MANTISSA+3
    lda FP_B_MANTISSA+1
    sta FP_B_MANTISSA+2
    lda FP_B_MANTISSA
    sta FP_B_MANTISSA+1
    sty FP_B_MANTISSA
    dex
    bne ADD_FP_B_UNROUNDED_B_BYTES
ADD_FP_B_UNROUNDED_B_BITS:
    pla
    and #%00000111
    beq ADD_FP_B_UNROUNDED_ALIGNED
    tax
ADD_FP_B_UNROUNDED_B_BIT:
    lsr FP_B_MANTISSA
    ror FP_B_MANTISSA+1
    ror FP_B_MANTISSA+2
    ror FP_B_MANTISSA+3
    ror FP_B_ROUNDING
    dex
    bne ADD_FP_B_UNROUNDED_B_BIT
    beq ADD_FP_B_UNROUNDED_ALIGNED      ; always
ADD_FP_B_UNROUNDED_SHIFT_A:
    sec
    lda FP_B_EXPONENT
    sbc FP_A_EXPONENT
    cmp #37
    bcs COPY_FP_B_TO_FP_A               ; FPA is too small to count
    pha
    and #%00111000
    beq ADD_FP_B_UNROUNDED_A_BITS
    lsr a
    lsr a
    lsr a
    tax                                 ; whole bytes to shift
ADD_FP_B_UNROUNDED_A_BYTES:
    lda FP_A_MANTISSA+3
    sta FP_A_ROUNDING
    lda FP_A_MANTISSA+2
    sta FP_A_MANTISSA+3
    lda FP_A_MANTISSA+1
    sta FP_A_MANTISSA+2
    lda FP_A_MANTISSA
    sta FP_A_MANTISSA+1
    sty FP_A_MANTISSA
    dex
    bne ADD_FP_B_UNROUNDED_A_BYTES
ADD_FP_B_UNROUNDED_A_BITS:
    pla
    and #%00000111
    beq ADD_FP_B_UNROUNDED_EXPONENT
    tax
ADD_FP_B_UNROUNDED_A_BIT:
    lsr FP_A_MANTISSA
    ror FP_A_MANTISSA+1
    ror FP_A_MANTISSA+2
    ror FP_A_MANTISSA+3
    ror FP_A_ROUNDING
    dex
    bne ADD_FP_B_UNROUNDED_A_BIT
ADD_FP_B_UNROUNDED_EXPONENT:
    lda FP_B_EXPONENT
    sta FP_A_EXPONENT
ADD_FP_B_UNROUNDED_ALIGNED:
    lda FP_A_SIGN
    eor FP_B_SIGN
    bpl ADD_FP_B_UNROUNDED_SAME_SIGN
    lda FP_A_MANTISSA
    cmp FP_B_MANTISSA
    bne ADD_FP_B_UNROUNDED_COMPARED
    lda FP_A_MANTISSA+1
    cmp FP_B_MANTISSA+1
    bne ADD_FP_B_UNROUNDED_COMPARED
    lda FP_A_MANTISSA+2
    cmp FP_B_MANTISSA+2
    bne ADD_FP_B_UNROUNDED_COMPARED
    lda FP_A_MANTISSA+3
    cmp FP_B_MANTISSA+3
    bne ADD_FP_B_UNROUNDED_COMPARED
    lda FP_A_ROUNDING
    cmp FP_B_ROUNDING
    bne ADD_FP_B_UNROUNDED_COMPARED
    jmp ZERO_FP_A                       ; equal and opposite
ADD_FP_B_UNROUNDED_COMPARED:
    bcs ADD_FP_B_UNROUNDED_A_LARGER
    sec
    lda FP_B_ROUNDING
    sbc FP_A_ROUNDING
    sta FP_A_ROUNDING
    lda FP_B_MANTISSA+3
    sbc FP_A_MANTISSA+3
    sta FP_A_MANTISSA+3
    lda FP_B_MANTISSA+2
    sbc FP_A_MANTISSA+2
    sta FP_A_MANTISSA+2
    lda FP_B_MANTISSA+1
    sbc FP_A_MANTISSA+1
    sta FP_A_MANTISSA+1
    lda FP_B_MANTISSA
    sbc FP_A_MANTISSA
    sta FP_A_MANTISSA
    lda FP_B_SIGN
    sta FP_A_SIGN
    jmp NORMALISE_FP_A
ADD_FP_B_UNROUNDED_SAME_SIGN:
    clc
    jmp ADD_FP_B_MANTISSA_CARRY
ADD_FP_B_UNROUNDED_A_LARGER:
    sec
    lda FP_A_ROUNDING
    sbc FP_B_ROUNDING
    sta FP_A_ROUNDING
    lda FP_A_MANTISSA+3
    sbc FP_B_MANTISSA+3
    sta FP_A_MANTISSA+3
    lda FP_A_MANTISSA+2
    sbc FP_B_MANTISSA+2
    sta FP_A_MANTISSA+2
    lda FP_A_MANTISSA+1
    sbc FP_B_MANTISSA+1
    sta FP_A_MANTISSA+1
    lda FP_A_MANTISSA
    sbc FP_B_MANTISSA
    sta FP_A_MANTISSA
    jmp NORMALISE_FP_A
MULTIPLY_ZERO:
    rts                                 ; MULTIPLY_FP_A_UNNORMALISED's return when FPA is zero

;; Multiplies FPA by the packed real at FP_POINTER, without normalising or rounding.
;;
;; The exponents are added. FPA's mantissa moves to <MULTIPLIER>, and for each of its 32 bits, from the top, FPB's
;; mantissa is halved and, when the bit is set, added to FPA's, so the product is at least a quarter.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the product, not normalised
;; Uses: A, X, Y, FP_B, FP_WORK..FP_WORK+4
;; Entry: MULTIPLY_FP_A_BY_FP_B = multiplies FPA by FPB, both not zero
MULTIPLY_FP_A_UNNORMALISED:
    jsr TEST_FP_A
    beq MULTIPLY_ZERO
    jsr LOAD_FP_B
    bne MULTIPLY_FP_A_BY_FP_B
    jmp ZERO_FP_A
MULTIPLY_FP_A_BY_FP_B:
    clc
    lda FP_A_EXPONENT
    adc FP_B_EXPONENT
    bcc MULTIPLY_FP_A_BY_FP_B_1
    inc FP_A_OVERFLOW
    clc
MULTIPLY_FP_A_BY_FP_B_1:
    sbc #REAL_EXPONENT_BIAS - 1         ; carry is clear: takes off one bias
    sta FP_A_EXPONENT
    bcs MULTIPLY_FP_A_BY_FP_B_2
    dec FP_A_OVERFLOW
MULTIPLY_FP_A_BY_FP_B_2:
    ldx #$05
    ldy #$00
MULTIPLY_FP_A_BY_FP_B_MOVE:
    lda FP_A_MANTISSA-1,x
    sta MULTIPLIER-1,x
    sty FP_A_MANTISSA-1,x
    dex
    bne MULTIPLY_FP_A_BY_FP_B_MOVE
    lda FP_A_SIGN
    eor FP_B_SIGN
    sta FP_A_SIGN
    ldy #32
MULTIPLY_FP_A_BY_FP_B_LOOP:
    lsr FP_B_MANTISSA
    ror FP_B_MANTISSA+1
    ror FP_B_MANTISSA+2
    ror FP_B_MANTISSA+3
    ror FP_B_ROUNDING
    asl MULTIPLIER+3
    rol MULTIPLIER+2
    rol MULTIPLIER+1
    rol MULTIPLIER
    bcc MULTIPLY_FP_A_BY_FP_B_NEXT
    clc
    jsr ADD_FP_B_MANTISSA
MULTIPLY_FP_A_BY_FP_B_NEXT:
    dey
    bne MULTIPLY_FP_A_BY_FP_B_LOOP
    rts

;; Multiplies FPA by the packed real at FP_POINTER, normalised and rounded.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the product
;; Uses: A, X, Y, FP_B, FP_WORK..FP_WORK+4
;; Errors: 20 (Too big) = the product is too large
MULTIPLY_FP_A:
    jsr MULTIPLY_FP_A_UNNORMALISED

;; Normalises FPA and rounds it, falling into <ROUND_FP_A>.
;; Uses: A, X, Y
;; Errors: 20 (Too big) = the exponent overflowed
NORMALISE_AND_ROUND_FP_A:
    jsr NORMALISE_FP_A

;; Rounds FPA's mantissa to its four significant bytes, and checks the exponent.
;;
;; A rounding byte above &80 rounds up, one below rounds down, and exactly &80 sets the mantissa's lowest bit. A carry
;; out of the top is shifted back in. Then the rounding byte is cleared, and the exponent's overflow byte checked: an
;; overflow is an error, and an underflow makes FPA zero.
;; Uses: A
;; Keeps: X, Y
;; Errors: 20 (Too big) = the exponent overflowed
ROUND_FP_A:
    lda FP_A_ROUNDING
    cmp #$80
    bcc ROUND_FP_A_CHECK
    beq ROUND_FP_A_HALF
    lda #$FF                            ; with carry set, adds one to the mantissa
    jsr ADD_A_TO_MANTISSA
    jmp ROUND_FP_A_CHECK                ; over the error

;; Raises error 20, "Too big": a real too large for its result.
;;
;; It sits in the middle of <ROUND_FP_A>, which jumps over it; the code after it is ROUND_FP_A's.
TOO_BIG_ERROR:
    brk
    .byte ERROR_TOO_BIG, "Too big", 0
ROUND_FP_A_HALF:
    lda FP_A_MANTISSA+3
    ora #$01
    sta FP_A_MANTISSA+3
ROUND_FP_A_CHECK:
    lda #$00
    sta FP_A_ROUNDING
    lda FP_A_OVERFLOW
    beq ZERO_FP_A_DONE
    bpl TOO_BIG_ERROR                   ; an underflow falls into ZERO_FP_A

;; Sets FPA to zero, all eight bytes.
;; Out: A = 0, zero = set
;; Keeps: X, Y
;; Entry: ZERO_FP_A_DONE = only returns
ZERO_FP_A:
    lda #$00
    sta FP_A_SIGN
    sta FP_A_OVERFLOW
    sta FP_A_EXPONENT
    sta FP_A_MANTISSA
    sta FP_A_MANTISSA+1
    sta FP_A_MANTISSA+2
    sta FP_A_MANTISSA+3
    sta FP_A_ROUNDING
ZERO_FP_A_DONE:
    rts

;; Sets FPA to one.
;; Out: A = &81, FP_A's exponent, zero = clear, negative = set
;; Uses: Y
;; Keeps: X
ONE_FP_A:
    jsr ZERO_FP_A
    ldy #$80
    sty FP_A_MANTISSA
    iny
    sty FP_A_EXPONENT                   ; 0.5 times two
    tya
    rts
