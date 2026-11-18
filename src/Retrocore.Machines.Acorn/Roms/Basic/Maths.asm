; ---------------------------------------------------------------------------------------------------------------------
; The mathematical functions and their constants (&A6A5-&AB32): division and 1/x, TAN, SQR, LN, the series evaluator,
; ACS, ASN, ATN, COS, SIN and EXP, and raising to a whole power
; ---------------------------------------------------------------------------------------------------------------------

ERROR_NEGATIVE_ROOT = $15           ;; error 21, "-ve root": SQR of a negative number
ERROR_LOG_RANGE = $16               ;; error 22, "Log range": LN or LOG of zero or a negative number
ERROR_ACCURACY_LOST = $17           ;; error 23, "Accuracy lost": SIN, COS or TAN of an angle of 2^23 or more
ERROR_EXP_RANGE = $18               ;; error 24, "Exp range": EXP of 89.5 or more

SERIES_COUNT = FP_WORK + 5          ;; EVALUATE_CONTINUED_FRACTION: the coefficients still to add
QUADRANT = FP_WORK + 7              ;; SIN, COS and TAN: the quarter turns taken off the angle; bits 0 and 1 count
QUOTIENT = FP_WORK                  ;; DIVIDE_FP_A_BY_FP_B: the quotient's four bytes as they are made

;; Lays out a packed real from its parts: the bytes of <PACKED_REAL>.
;; Parameters:
;;   exponent = the power of two, -128 to 127
;;   magnitude = the mantissa as a 32-bit fraction with its top bit set
;;   negative = 1 for a negative number, 0 for a positive one
.macro PACKED_REAL_BYTES exponent, magnitude, negative
    .assert ((magnitude) & $80000000) != 0, "A packed real's mantissa has its top bit set."
    .byte REAL_EXPONENT_BIAS + (exponent), (((magnitude) >> 24) & $7F) | ((negative) << 7)
    .byte ((magnitude) >> 16) & $FF, ((magnitude) >> 8) & $FF, (magnitude) & $FF
.endmacro

;; Lays out a packed real: its exponent, then its four mantissa bytes with the sign in place of the top bit.
;;
;; The value is the mantissa, as a binary fraction from 0.5 up to 1, times 2 to the power of the exponent. The
;; exponent byte is offset by &80, and the mantissa's top bit, always set, is replaced by the sign.
;; Parameters:
;;   exponent = the power of two, -128 to 127
;;   mantissa = the mantissa as a 32-bit fraction with its top bit set, negated for a negative number
.macro PACKED_REAL exponent, mantissa
    PACKED_REAL_BYTES exponent, ((mantissa) * (1 - 2 * ((mantissa) < 0))), ((mantissa) < 0)
.endmacro

;; Sets FPA to its reciprocal, 1 divided by it.
;; Out: FP_A = 1 / FP_A, FP_TEMP_1 = FP_A as it was
;; Uses: A, X, Y, FP_B, FP_POINTER, FP_WORK..FP_WORK+3
;; Errors: 18 (Division by zero) = FP_A is zero
RECIPROCAL_FP_A:
    jsr STORE_FP_A_TEMP_1
    jsr ONE_FP_A
    bne DIVIDE_FP_A                     ; always: ONE_FP_A leaves A = &81

;; Divides the packed real at FP_POINTER by FPA.
;; In: FP_POINTER = the packed real
;; Out: FP_A = the number divided by FP_A
;; Uses: A, X, Y, FP_B, FP_WORK..FP_WORK+3
;; Errors: 18 (Division by zero) = FP_A is zero, 20 (Too big) = the quotient is too large
DIVIDE_BY_FP_A:
    jsr TEST_FP_A
    beq JUMP_DIVISION_BY_ZERO
    jsr COPY_FP_A_TO_FP_B
    jsr LOAD_FP_A
    bne DIVIDE_FP_A_BY_FP_B
    rts                                 ; zero divided by anything is zero

;; A jump to the "Division by zero" error that branches can reach.
JUMP_DIVISION_BY_ZERO:
    jmp DIVISION_BY_ZERO_ERROR

;; TAN: the tangent of an angle in radians, as in TAN(X).
;;
;; It reduces the angle to within a quarter turn of zero with <REDUCE_ANGLE>, then divides the sine by the cosine, both
;; found from the reduced angle by <SIN_QUADRANT>, the cosine with the quadrant one more.
;; Out: FP_A = the tangent, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_4, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Errors: 23 (Accuracy lost) = the angle is 2^23 or more in size
TAN_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    jsr REDUCE_ANGLE
    lda QUADRANT
    pha
    jsr POINT_AT_FP_TEMP_4
    jsr STORE_FP_A                      ; the reduced angle
    inc QUADRANT
    jsr SIN_QUADRANT                    ; the cosine
    jsr POINT_AT_FP_TEMP_4
    jsr EXCHANGE_FP_A                   ; keep the cosine, take back the angle
    pla
    sta QUADRANT
    jsr SIN_QUADRANT                    ; the sine
    jsr POINT_AT_FP_TEMP_4
    jsr DIVIDE_FP_A
    lda #$FF                            ; a real
    rts

;; Divides FPA by the packed real at FP_POINTER, normalised and rounded.
;; In: FP_POINTER = the packed real
;; Out: FP_A = FP_A divided by the number
;; Uses: A, X, Y, FP_B, FP_WORK..FP_WORK+3
;; Errors: 18 (Division by zero) = the number is zero, 20 (Too big) = the quotient is too large
DIVIDE_FP_A:
    jsr TEST_FP_A
    beq ZERO_FP_A_DONE                  ; zero divided by anything is zero
    jsr LOAD_FP_B
    beq JUMP_DIVISION_BY_ZERO

;; Divides FPA by FPB, normalised and rounded.
;;
;; The exponents are subtracted. The quotient is made a bit at a time by long division of the mantissas: 32 bits into
;; <QUOTIENT>, then seven more into the rounding byte, and the result normalised and rounded.
;; Out: FP_A = FP_A divided by FP_B
;; Uses: A, X, Y, FP_WORK..FP_WORK+3
;; Errors: 20 (Too big) = the quotient is too large
DIVIDE_FP_A_BY_FP_B:
    lda FP_A_SIGN
    eor FP_B_SIGN
    sta FP_A_SIGN
    sec
    lda FP_A_EXPONENT
    sbc FP_B_EXPONENT
    bcs DIVIDE_FP_A_BY_FP_B_1
    dec FP_A_OVERFLOW
    sec
DIVIDE_FP_A_BY_FP_B_1:
    adc #REAL_EXPONENT_BIAS             ; carry is set: the bias and one more, as the quotient's first bit is worth 1
    sta FP_A_EXPONENT
    bcc DIVIDE_FP_A_BY_FP_B_2
    inc FP_A_OVERFLOW
    clc
DIVIDE_FP_A_BY_FP_B_2:
    ldx #32
DIVIDE_FP_A_BY_FP_B_LOOP:
    bcs DIVIDE_FP_A_BY_FP_B_SUBTRACT    ; a bit shifted out of the top: the remainder is larger
    lda FP_A_MANTISSA
    cmp FP_B_MANTISSA
    bne DIVIDE_FP_A_BY_FP_B_COMPARED
    lda FP_A_MANTISSA+1
    cmp FP_B_MANTISSA+1
    bne DIVIDE_FP_A_BY_FP_B_COMPARED
    lda FP_A_MANTISSA+2
    cmp FP_B_MANTISSA+2
    bne DIVIDE_FP_A_BY_FP_B_COMPARED
    lda FP_A_MANTISSA+3
    cmp FP_B_MANTISSA+3
DIVIDE_FP_A_BY_FP_B_COMPARED:
    bcc DIVIDE_FP_A_BY_FP_B_NEXT        ; the remainder is smaller: a zero bit
DIVIDE_FP_A_BY_FP_B_SUBTRACT:
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
    sec                                 ; a one bit
DIVIDE_FP_A_BY_FP_B_NEXT:
    rol QUOTIENT+3
    rol QUOTIENT+2
    rol QUOTIENT+1
    rol QUOTIENT
    asl FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol FP_A_MANTISSA
    dex
    bne DIVIDE_FP_A_BY_FP_B_LOOP
    ldx #$07
DIVIDE_FP_A_BY_FP_B_ROUNDING_LOOP:
    bcs DIVIDE_FP_A_BY_FP_B_ROUNDING_SUBTRACT
    lda FP_A_MANTISSA
    cmp FP_B_MANTISSA
    bne DIVIDE_FP_A_BY_FP_B_ROUNDING_COMPARED
    lda FP_A_MANTISSA+1
    cmp FP_B_MANTISSA+1
    bne DIVIDE_FP_A_BY_FP_B_ROUNDING_COMPARED
    lda FP_A_MANTISSA+2
    cmp FP_B_MANTISSA+2
    bne DIVIDE_FP_A_BY_FP_B_ROUNDING_COMPARED
    lda FP_A_MANTISSA+3
    cmp FP_B_MANTISSA+3
DIVIDE_FP_A_BY_FP_B_ROUNDING_COMPARED:
    bcc DIVIDE_FP_A_BY_FP_B_ROUNDING_NEXT
DIVIDE_FP_A_BY_FP_B_ROUNDING_SUBTRACT:
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
    sec
DIVIDE_FP_A_BY_FP_B_ROUNDING_NEXT:
    rol FP_A_ROUNDING
    asl FP_A_MANTISSA+3
    rol FP_A_MANTISSA+2
    rol FP_A_MANTISSA+1
    rol FP_A_MANTISSA
    dex
    bne DIVIDE_FP_A_BY_FP_B_ROUNDING_LOOP
    asl FP_A_ROUNDING                   ; the seven bits to the top of the rounding byte
    lda QUOTIENT+3
    sta FP_A_MANTISSA+3
    lda QUOTIENT+2
    sta FP_A_MANTISSA+2
    lda QUOTIENT+1
    sta FP_A_MANTISSA+1
    lda QUOTIENT
    sta FP_A_MANTISSA
    jmp NORMALISE_AND_ROUND_FP_A

;; Raises error 21, "-ve root": SQR of a negative number.
NEGATIVE_ROOT_ERROR:
    brk
    .byte ERROR_NEGATIVE_ROOT, "-ve root", 0

;; SQR: the square root of a number, as in SQR(2).
;;
;; It starts from a guess with half the exponent and the same mantissa, then improves it five times by Newton's
;; method, taking the mean of the guess and the number divided by it.
;; Out: FP_A = the square root, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_2, FP_WORK..FP_WORK+3, FP_WORK+7
;; Entry: SQR_FP_A = takes the number in FPA
;; Errors: 21 (-ve root) = the number is negative
SQR_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
SQR_FP_A:
    jsr TEST_FP_A
    beq SQR_FP_A_DONE                   ; the root of zero is zero
    bmi NEGATIVE_ROOT_ERROR
    jsr STORE_FP_A_TEMP_1               ; the number
    lda FP_A_EXPONENT
    lsr a
    adc #REAL_EXPONENT_BIAS / 2         ; with the bit shifted out: half the exponent, offset by &80
    sta FP_A_EXPONENT
    lda #$05
    sta FP_WORK+7                       ; the steps to take
    jsr POINT_AT_FP_TEMP_2
SQR_FP_A_LOOP:
    jsr STORE_FP_A                      ; the guess, in FP_TEMP_2
    lda #<FP_TEMP_1
    sta FP_POINTER
    jsr DIVIDE_BY_FP_A                  ; the number divided by the guess
    lda #<FP_TEMP_2
    sta FP_POINTER
    jsr ADD_TO_FP_A
    dec FP_A_EXPONENT                   ; halved
    dec FP_WORK+7
    bne SQR_FP_A_LOOP
SQR_FP_A_DONE:
    lda #$FF                            ; a real
    rts

;; Points FP_POINTER at <FP_TEMP_4>.
;; Out: FP_POINTER = FP_TEMP_4
;; Uses: A
;; Keeps: X, Y
POINT_AT_FP_TEMP_4:
    lda #<FP_TEMP_4
    bne POINT_AT_PAGE_FOUR              ; always

;; Points FP_POINTER at <FP_TEMP_2>.
;; Out: FP_POINTER = FP_TEMP_2
;; Uses: A
;; Keeps: X, Y
POINT_AT_FP_TEMP_2:
    lda #<FP_TEMP_2
    bne POINT_AT_PAGE_FOUR              ; always

;; Points FP_POINTER at <FP_TEMP_3>.
;; Out: FP_POINTER = FP_TEMP_3
;; Uses: A
;; Keeps: X, Y
POINT_AT_FP_TEMP_3:
    lda #<FP_TEMP_3
    bne POINT_AT_PAGE_FOUR              ; always

;; Points FP_POINTER at <FP_TEMP_1>, falling into <POINT_AT_PAGE_FOUR>.
;; Out: FP_POINTER = FP_TEMP_1
;; Uses: A
;; Keeps: X, Y
POINT_AT_FP_TEMP_1:
    lda #<FP_TEMP_1

;; Points FP_POINTER at a packed real in page four.
;; In: A = the low byte of its address
;; Out: FP_POINTER = the address
;; Uses: A
;; Keeps: X, Y
POINT_AT_PAGE_FOUR:
    sta FP_POINTER
    lda #>FP_TEMP_1
    sta FP_POINTER+1
    rts

;; LN: the natural logarithm of a number, as in LN(10).
;;
;; The number is split into a power of two, n, and a mantissa y from about 0.707 to 1.414, so that t = y - 1 is small.
;; Then ln(y) = t + t^2 times <LN_SERIES> evaluated at t, and the logarithm is that plus n times ln 2.
;; Out: FP_A = the logarithm, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_4, FP_WORK..FP_WORK+5, SERIES_POINTER
;; Entry: LN_FP_A = takes the number in FPA
;; Errors: 22 (Log range) = the number is zero or negative
LN_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
LN_FP_A:
    jsr TEST_FP_A
    beq LOG_RANGE_ERROR
    bpl LN_FP_A_POSITIVE
LOG_RANGE_ERROR:
    brk
    .byte ERROR_LOG_RANGE, "Log range", 0
LN_FP_A_POSITIVE:
    jsr ZERO_FP_B
    ldy #$80
    sty FP_B_SIGN
    sty FP_B_MANTISSA
    iny
    sty FP_B_EXPONENT                   ; FPB = -1
    ldx FP_A_EXPONENT
    beq LN_FP_A_HIGH
    lda FP_A_MANTISSA
    cmp #$B5                            ; about 0.707, a half of the square root of two
    bcc LN_FP_A_SCALE                   ; a low mantissa is doubled: y = 2m
LN_FP_A_HIGH:
    inx                                 ; a high one is kept: y = m, one more power of two
    dey
LN_FP_A_SCALE:
    txa
    pha                                 ; the exponent, for n
    sty FP_A_EXPONENT
    jsr ADD_FP_B_TO_FP_A                ; t = y - 1
    lda #<FP_TEMP_4
    jsr STORE_FP_A_PAGE_FOUR
    lda #<LN_SERIES
    ldy #>LN_SERIES
    jsr EVALUATE_CONTINUED_FRACTION
    jsr POINT_AT_FP_TEMP_4
    jsr MULTIPLY_FP_A
    jsr MULTIPLY_FP_A                   ; times t^2
    jsr ADD_TO_FP_A                     ; plus t: ln(y)
    jsr STORE_FP_A_TEMP_1
    pla
    sec
    sbc #REAL_EXPONENT_BIAS + 1         ; n
    jsr BYTE_TO_REAL
    lda #<LN_2
    sta FP_POINTER
    lda #>LN_2
    sta FP_POINTER+1
    jsr MULTIPLY_FP_A
    jsr POINT_AT_FP_TEMP_1
    jsr ADD_TO_FP_A
    lda #$FF                            ; a real
    rts

;; log e, the base ten logarithm of e: 0.4342944819. LOG multiplies the natural logarithm by it.
LOG10_E:
    PACKED_REAL -1, $DE5BD8AA           ; 0.4342944819
    .assert LOG10_E = $A869, "LOG_FUNCTION loads LOG10_E from $A869."

;; ln 2, the natural logarithm of two: 0.6931471806.
LN_2:
    PACKED_REAL 0, $B17217F8            ; 0.6931471806

;; The coefficients of the continued fraction for LN (<EVALUATE_CONTINUED_FRACTION>): the count less one, then the
;; coefficients, innermost first.
;;
;; At t, it gives (ln(1 + t) - t) / t^2, which starts -1/2 + t/3.
LN_SERIES:
    .byte 7 - 1                         ; seven coefficients
    PACKED_REAL -6, $9238A50B           ; 0.008924637961
    PACKED_REAL 8, $F90E9FF3            ; 249.0571281
    PACKED_REAL -4, $AAAC3FB5           ; 0.04166817556
    PACKED_REAL 6, $B401A27A            ; 45.00159636
    PACKED_REAL -1, $E38E37EC           ; 0.4444444156
    PACKED_REAL 2, $BFFFFFC1            ; 2.999999941
    PACKED_REAL -1, -$FFFFFFFF          ; -0.4999999999
    .assert * - LN_SERIES = 1 + 7 * 5, "LN_SERIES has seven coefficients."

;; Evaluates a series of coefficients at FPA, as a continued fraction.
;;
;; The table's first byte is the number of coefficients less one, and five-byte packed reals follow. The value starts
;; as the first coefficient, then for each of the others it becomes that coefficient plus x divided by the value, so a
;; table c0, c1, ... cn gives cn + x / (... + x / (c1 + x / c0)).
;; In: A = the table's address, low byte, Y = its high byte, FP_A = x
;; Out: FP_A = the value, FP_TEMP_1 = x
;; Uses: A, X, Y, FP_B, FP_POINTER, SERIES_POINTER, FP_WORK..FP_WORK+5
;; Errors: 18 (Division by zero) = a value on the way is zero
EVALUATE_CONTINUED_FRACTION:
    sta SERIES_POINTER
    sty SERIES_POINTER+1
    jsr STORE_FP_A_TEMP_1
    ldy #$00
    lda (SERIES_POINTER),y
    sta SERIES_COUNT
    inc SERIES_POINTER
    bne EVALUATE_SERIES_FIRST
    inc SERIES_POINTER+1
EVALUATE_SERIES_FIRST:
    lda SERIES_POINTER
    sta FP_POINTER
    lda SERIES_POINTER+1
    sta FP_POINTER+1
    jsr LOAD_FP_A
EVALUATE_SERIES_LOOP:
    jsr POINT_AT_FP_TEMP_1
    jsr DIVIDE_BY_FP_A                  ; x divided by the value
    clc
    lda SERIES_POINTER
    adc #$05
    sta SERIES_POINTER
    sta FP_POINTER
    lda SERIES_POINTER+1
    adc #$00
    sta SERIES_POINTER+1
    sta FP_POINTER+1
    jsr ADD_TO_FP_A                     ; plus the next coefficient
    dec SERIES_COUNT
    bne EVALUATE_SERIES_LOOP
    rts

;; ACS: the arc-cosine of a number, in radians, as in ACS(0.5): pi/2 less its arc-sine.
;; Out: FP_A = the angle, 0 to pi, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Errors: 21 (-ve root) = the number is more than 1 in size
ACS_FUNCTION:
    jsr ASN_FUNCTION
    jmp HALF_PI_LESS_FP_A

;; ASN: the arc-sine of a number, in radians, as in ASN(0.5).
;;
;; It is ATN of x / SQR(1 - x^2), or pi/2 when that is infinite. A negative number is made positive and its result
;; negated.
;; Out: FP_A = the angle, -pi/2 to pi/2, A = &FF, or &80 for a negative angle
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Errors: 21 (-ve root) = the number is more than 1 in size
ASN_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    jsr TEST_FP_A
    bpl ASN_POSITIVE
    lsr FP_A_SIGN                       ; positive
    jsr ASN_POSITIVE
    jmp MAKE_FP_A_NEGATIVE
ASN_POSITIVE:
    jsr STORE_FP_A_TEMP_3
    jsr ROOT_ONE_LESS_SQUARE
    jsr TEST_FP_A
    beq LOAD_HALF_PI                    ; ASN 1 is pi/2
    jsr POINT_AT_FP_TEMP_3
    jsr DIVIDE_BY_FP_A
    jmp ATN_FP_A

;; Loads pi/2 into FPA. PI uses it, and doubles it.
;; Out: FP_A = pi/2, A = &FF, FP_POINTER = HALF_PI
;; Uses: Y
;; Keeps: X
;; Entry: TRIG_RETURN_REAL = only returns A = &FF
LOAD_HALF_PI:
    jsr POINT_AT_HALF_PI
    jsr LOAD_FP_A
TRIG_RETURN_REAL:
    lda #$FF                            ; a real
    rts

;; ATN: the arc-tangent of a number, in radians, as in ATN(1).
;;
;; A negative number is made positive and its result negated.
;; Out: FP_A = the angle, -pi/2 to pi/2, A = &FF, or &80 for a negative angle
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER
;; Entry: ATN_FP_A = takes the number in FPA, MAKE_FP_A_NEGATIVE = makes FPA negative, returning A = &80
ATN_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
ATN_FP_A:
    jsr TEST_FP_A
    beq TRIG_RETURN_REAL                ; ATN 0 is 0
    bpl ATN_POSITIVE
    lsr FP_A_SIGN                       ; positive
    jsr ATN_POSITIVE
MAKE_FP_A_NEGATIVE:
    lda #$80
    sta FP_A_SIGN
    rts

;; The arc-tangent of a positive FPA. Below 1 it is <ATN_BELOW_ONE>; from 1 up, pi/2 less the arc-tangent of 1/x,
;; falling into <HALF_PI_LESS_FP_A>.
;; Out: FP_A = the angle, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER
ATN_POSITIVE:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_BIAS + 1
    bcc ATN_BELOW_ONE
    jsr RECIPROCAL_FP_A
    jsr ATN_BELOW_ONE

;; Sets FPA to pi/2 less FPA, taking off pi/2 in two parts for accuracy.
;; Out: FP_A = pi/2 - FP_A, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER
HALF_PI_LESS_FP_A:
    jsr POINT_AT_MINUS_HALF_PI_COARSE
    jsr ADD_TO_FP_A
    jsr POINT_AT_HALF_PI_ADJUSTMENT
    jsr ADD_TO_FP_A                     ; FPA - pi/2
    jmp NEGATE_FP_A                           ; negated

;; The arc-tangent of FPA from 0 up to 1: x times <ATN_SERIES> evaluated at x - 1/2.
;;
;; Below 2^-14 the arc-tangent is the number itself.
;; Out: FP_A = the angle, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER
ATN_BELOW_ONE:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_BIAS - 13
    bcc TRIG_RETURN_REAL                ; too small to change
    jsr STORE_FP_A_TEMP_3
    jsr ZERO_FP_B
    lda #$80
    sta FP_B_EXPONENT
    sta FP_B_MANTISSA
    sta FP_B_SIGN                       ; FPB = -0.5
    jsr ADD_FP_B_TO_FP_A
    lda #<ATN_SERIES
    ldy #>ATN_SERIES
    jsr EVALUATE_CONTINUED_FRACTION
    jsr MULTIPLY_BY_FP_TEMP_3
    lda #$FF                            ; a real
    rts

;; The coefficients of the continued fraction for ATN (<EVALUATE_CONTINUED_FRACTION>): the count less one, then the
;; coefficients, innermost first.
;;
;; At u = x - 1/2, it gives ATN(x) / x, for x from 0 up to 1. Its last coefficient is 2 ATN(1/2).
ATN_SERIES:
    .byte 10 - 1                        ; ten coefficients
    PACKED_REAL 5, -$A359E867           ; -20.4189003
    PACKED_REAL 0, $9C9D0736            ; 0.6117710597
    PACKED_REAL 0, $D7BB78DF            ; 0.842704348
    PACKED_REAL 0, -$CA9A0E83           ; -0.7914132185
    PACKED_REAL 4, -$8CBBCA6E           ; -8.795847349
    PACKED_REAL 1, -$959606DE           ; -1.168640955
    PACKED_REAL 1, $8AC76C52            ; 1.084210911
    PACKED_REAL -1, $FDAD90A1           ; 0.4954648205
    PACKED_REAL 2, -$FB62572F           ; -3.927877232
    PACKED_REAL 0, $ED63382C            ; 0.9272952182
    .assert * - ATN_SERIES = 1 + 10 * 5, "ATN_SERIES has ten coefficients."

;; COS: the cosine of an angle in radians, as in COS(PI): the sine of the angle a quarter turn on.
;; Out: FP_A = the cosine, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Errors: 23 (Accuracy lost) = the angle is 2^23 or more in size
COS_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    jsr REDUCE_ANGLE
    inc QUADRANT
    jmp SIN_QUADRANT

;; SIN: the sine of an angle in radians, as in SIN(PI/2), falling into <SIN_QUADRANT>.
;; Out: FP_A = the sine, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Errors: 23 (Accuracy lost) = the angle is 2^23 or more in size
SIN_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    jsr REDUCE_ANGLE

;; The sine of an angle given as a reduced angle and a number of quarter turns.
;;
;; In the third and fourth quarters, the sine is the negative of that in the first and second.
;; In: FP_A = the reduced angle, -pi/4 to pi/4, QUADRANT = the quarter turns to add
;; Out: FP_A = the sine, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER, QUADRANT
SIN_QUADRANT:
    lda QUADRANT
    and #%00000010
    beq SIN_OR_COS_REDUCED
    jsr SIN_OR_COS_REDUCED
    jmp NEGATE_FP_A                           ; negated

;; The sine of a reduced angle, or its cosine when bit 0 of QUADRANT is set, falling into <ROOT_ONE_LESS_SQUARE>
;; for the cosine.
;; In: FP_A = the reduced angle, -pi/4 to pi/4, QUADRANT = bit 0 set for the cosine
;; Out: FP_A = the sine or cosine, A = &FF, QUADRANT = shifted right one bit
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1..FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER
SIN_OR_COS_REDUCED:
    lsr QUADRANT
    bcc SIN_REDUCED
    jsr SIN_REDUCED                     ; the cosine is the root of 1 - sin^2

;; Sets FPA to the square root of 1 - FPA^2: the cosine of an angle from its sine, or the reverse.
;; Out: FP_A = the root, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_2, FP_WORK..FP_WORK+3, FP_WORK+7
;; Errors: 21 (-ve root) = FP_A is more than 1 in size
ROOT_ONE_LESS_SQUARE:
    jsr STORE_FP_A_TEMP_1
    jsr MULTIPLY_FP_A
    jsr STORE_FP_A
    jsr ONE_FP_A
    jsr SUBTRACT_FROM_FP_A
    jmp SQR_FP_A

;; The sine of a reduced angle r: r times <SIN_SERIES> evaluated at r^2.
;; In: FP_A = the angle, -pi/4 to pi/4
;; Out: FP_A = the sine, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_3, FP_WORK..FP_WORK+5, SERIES_POINTER
SIN_REDUCED:
    jsr STORE_FP_A_TEMP_3
    jsr MULTIPLY_FP_A
    lda #<SIN_SERIES
    ldy #>SIN_SERIES
    jsr EVALUATE_CONTINUED_FRACTION
    jmp MULTIPLY_BY_FP_TEMP_3

;; Reduces an angle to within an eighth of a turn of zero by taking off a whole number of quarter turns.
;;
;; The quarter turns are the angle divided by pi/2, rounded to the nearest whole number, n. The angle less n times
;; pi/2 is found in two steps, with pi/2 as a coarse part and a small adjustment, so that few bits of the angle are
;; lost.
;; In: FP_A = the angle, in radians
;; Out: FP_A = the angle less n times pi/2, QUADRANT = n's low byte
;; Uses: A, X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_2
;; Errors: 23 (Accuracy lost) = the angle is 2^23 or more in size
REDUCE_ANGLE:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_BIAS + 24
    bcs ACCURACY_LOST_ERROR
    jsr STORE_FP_A_TEMP_1               ; the angle
    jsr POINT_AT_HALF_PI
    jsr LOAD_FP_B
    lda FP_A_SIGN
    sta FP_B_SIGN
    dec FP_B_EXPONENT                   ; pi/4, of the angle's sign
    jsr ADD_FP_B_TO_FP_A
    jsr DIVIDE_FP_A                     ; (angle + pi/4) / (pi/2)
    jsr REAL_TO_FIXED                   ; n, truncated towards zero
    lda FP_A_MANTISSA+3
    sta QUADRANT
    ora FP_A_MANTISSA+2
    ora FP_A_MANTISSA+1
    ora FP_A_MANTISSA
    beq REDUCE_ANGLE_NONE
    lda #REAL_EXPONENT_BIAS + 32
    sta FP_A_EXPONENT
    ldy #$00
    sty FP_A_ROUNDING
    lda FP_A_MANTISSA
    sta FP_A_SIGN
    bpl REDUCE_ANGLE_NORMALISE
    jsr NEGATE_MANTISSA
REDUCE_ANGLE_NORMALISE:
    jsr NORMALISE_FP_A                  ; n as a real
    jsr STORE_FP_A_TEMP_2
    jsr POINT_AT_MINUS_HALF_PI_COARSE
    jsr MULTIPLY_FP_A
    jsr POINT_AT_FP_TEMP_1
    jsr ADD_TO_FP_A                     ; the angle less n times the coarse part
    jsr STORE_FP_A
    jsr POINT_AT_FP_TEMP_2
    jsr LOAD_FP_A
    jsr POINT_AT_HALF_PI_ADJUSTMENT
    jsr MULTIPLY_FP_A
    jsr POINT_AT_FP_TEMP_1
    jmp ADD_TO_FP_A                     ; ... less n times the adjustment
REDUCE_ANGLE_NONE:
    jmp LOAD_FP_A_TEMP_1                ; n is zero: the angle as it was

;; Raises error 23, "Accuracy lost": SIN, COS or TAN of an angle too large to reduce.
ACCURACY_LOST_ERROR:
    brk
    .byte ERROR_ACCURACY_LOST, "Accuracy lost", 0

;; Points FP_POINTER at <MINUS_HALF_PI_COARSE>.
;; Out: FP_POINTER = MINUS_HALF_PI_COARSE
;; Uses: A
;; Keeps: X, Y
POINT_AT_MINUS_HALF_PI_COARSE:
    lda #<MINUS_HALF_PI_COARSE
    bne POINT_AT_MATHS_CONSTANT         ; always

;; Points FP_POINTER at <HALF_PI_ADJUSTMENT>, falling into <POINT_AT_MATHS_CONSTANT>.
;; Out: FP_POINTER = HALF_PI_ADJUSTMENT
;; Uses: A
;; Keeps: X, Y
POINT_AT_HALF_PI_ADJUSTMENT:
    lda #<HALF_PI_ADJUSTMENT

;; Points FP_POINTER at one of the constants in the page with pi/2.
;; In: A = the low byte of its address
;; Out: FP_POINTER = the address
;; Uses: A
;; Keeps: X, Y
POINT_AT_MATHS_CONSTANT:
    sta FP_POINTER
    lda #>HALF_PI
    sta FP_POINTER+1
    rts

;; Points FP_POINTER at <HALF_PI>.
;; Out: FP_POINTER = HALF_PI
;; Uses: A
;; Keeps: X, Y
POINT_AT_HALF_PI:
    lda #<HALF_PI
    bne POINT_AT_MATHS_CONSTANT         ; always taken: the constants follow, not code
    .assert >MINUS_HALF_PI_COARSE = >HALF_PI, "POINT_AT_MATHS_CONSTANT's constants share a page."
    .assert >HALF_PI_ADJUSTMENT = >HALF_PI, "POINT_AT_MATHS_CONSTANT's constants share a page."

;; -pi/2 to only 12 significant bits, -1.57080078125, so that small multiples of it are exact. REDUCE_ANGLE and
;; HALF_PI_LESS_FP_A add it, then <HALF_PI_ADJUSTMENT>.
MINUS_HALF_PI_COARSE:
    PACKED_REAL 1, -$C9100000           ; -1.57080078125

;; What <MINUS_HALF_PI_COARSE> lacks of -pi/2: 4.454455111E-6.
HALF_PI_ADJUSTMENT:
    PACKED_REAL -17, $95777A61          ; 4.454455111E-6

;; pi/2: 1.570796327.
HALF_PI:
    PACKED_REAL 1, $C90FDAA2            ; 1.570796327

;; pi/180, the radians in a degree: 0.01745329252. RAD multiplies by it.
RADIANS_PER_DEGREE:
    PACKED_REAL -5, $8EFA3512           ; 0.01745329252
    .assert RADIANS_PER_DEGREE = $AA68, "RAD_FUNCTION loads RADIANS_PER_DEGREE from $AA68."

;; 180/pi, the degrees in a radian: 57.29577951. DEG multiplies by it.
DEGREES_PER_RADIAN:
    PACKED_REAL 6, $E52EE0D3            ; 57.29577951
    .assert DEGREES_PER_RADIAN = $AA6D, "DEG_FUNCTION loads DEGREES_PER_RADIAN from $AA6D."

;; The coefficients of the continued fraction for SIN (<EVALUATE_CONTINUED_FRACTION>): the count less one, then the
;; coefficients, innermost first.
;;
;; At r^2, it gives SIN(r) / r, which starts 1 - r^2/6, for r from -pi/4 to pi/4.
SIN_SERIES:
    .byte 6 - 1                         ; six coefficients
    PACKED_REAL 4, -$8AEA0C1B           ; -8.682140451
    PACKED_REAL 4, $9ABEBB2B            ; 9.671565216
    PACKED_REAL 4, $B74555AB            ; 11.4544274
    PACKED_REAL 2, -$D555577C           ; -3.333333846
    PACKED_REAL 3, -$C0000005           ; -6.000000009
    PACKED_REAL 1, $80000000            ; 1
    .assert * - SIN_SERIES = 1 + 6 * 5, "SIN_SERIES has six coefficients."

;; EXP: e raised to the power of a number, as in EXP(1).
;;
;; The number is split into the nearest whole number n and a fraction f of at most a half in size. The result is e^n,
;; by repeated multiplication, times e^f from <EXP_SERIES>, falling into <MULTIPLY_BY_FP_TEMP_3> for the product. From
;; -89.5 down the result is zero.
;; Out: FP_A = the power, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_TEMP_3, FP_WORK..FP_WORK+7, SERIES_POINTER
;; Entry: EXP_FP_A = takes the number in FPA
;; Errors: 24 (Exp range) = the number is 89.5 or more
EXP_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
EXP_FP_A:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_BIAS + 7
    bcc EXP_FP_A_IN_RANGE               ; below 64
    bne EXP_FP_A_OUT_OF_RANGE           ; 128 or more
    ldy FP_A_MANTISSA
    cpy #$B3                            ; 89.5
    bcc EXP_FP_A_IN_RANGE
EXP_FP_A_OUT_OF_RANGE:
    lda FP_A_SIGN
    bpl EXP_RANGE_ERROR
    jsr ZERO_FP_A                       ; too small to show
    lda #$FF                            ; a real
    rts
EXP_RANGE_ERROR:
    brk
    .byte ERROR_EXP_RANGE, "Exp range", 0
EXP_FP_A_IN_RANGE:
    jsr FRACTIONAL_PART
    jsr EXP_FRACTION
    jsr STORE_FP_A_TEMP_3               ; e^f
    lda #<EULER_E
    sta FP_POINTER
    lda #>EULER_E
    sta FP_POINTER+1
    jsr LOAD_FP_A
    lda NEAREST_INTEGER
    jsr RAISE_TO_POWER                  ; e^n

;; Multiplies FPA by <FP_TEMP_3>, normalised and rounded.
;; Out: FP_A = the product, A = &FF, FP_POINTER = FP_TEMP_3
;; Uses: X, Y, FP_B, FP_WORK..FP_WORK+4
;; Errors: 20 (Too big) = the product is too large
MULTIPLY_BY_FP_TEMP_3:
    jsr POINT_AT_FP_TEMP_3
    jsr MULTIPLY_FP_A
    lda #$FF                            ; a real
    rts

;; Sets FPA to e^FPA with <EXP_SERIES>, for FPA at most a half in size.
;; Out: FP_A = the power, A = &FF
;; Uses: X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_WORK..FP_WORK+5, SERIES_POINTER
EXP_FRACTION:
    lda #<EXP_SERIES
    ldy #>EXP_SERIES
    jsr EVALUATE_CONTINUED_FRACTION
    lda #$FF                            ; a real
    rts

;; e, the base of natural logarithms: 2.718281828.
EULER_E:
    PACKED_REAL 2, $ADF85458            ; 2.718281828

;; The coefficients of the continued fraction for EXP (<EVALUATE_CONTINUED_FRACTION>): the count less one, then the
;; coefficients, innermost first.
;;
;; At f, it gives e^f, which starts 1 + f/(1 - f/2), for f from -0.5 to 0.5.
EXP_SERIES:
    .byte 8 - 1                         ; eight coefficients
    PACKED_REAL 3, -$E020865B           ; -7.003970316
    PACKED_REAL 2, -$805393B8           ; -2.005101137
    PACKED_REAL 3, $A00006A1            ; 5.000003161
    PACKED_REAL 2, $80002163            ; 2.00000796
    PACKED_REAL 2, -$C0000002           ; -3.000000002
    PACKED_REAL 2, -$8000000C           ; -2.000000011
    PACKED_REAL 1, $80000000            ; 1
    PACKED_REAL 1, $80000000            ; 1
    .assert * - EXP_SERIES = 1 + 8 * 5, "EXP_SERIES has eight coefficients."

;; Raises FPA to a whole power, -128 to 127, by repeated multiplication.
;;
;; A negative power raises the reciprocal to the positive one. EXP and the ^ operator use it.
;; In: A = the power, signed
;; Out: FP_A = the result
;; Uses: A, X, Y, FP_B, FP_POINTER, FP_TEMP_1, FP_WORK..FP_WORK+4
;; Errors: 18 (Division by zero) = FP_A is zero and the power negative, 20 (Too big) = the result is too large
RAISE_TO_POWER:
    tax
    bpl RAISE_TO_POWER_POSITIVE
    dex
    txa
    eor #$FF                            ; the power's size
    pha
    jsr RECIPROCAL_FP_A
    pla
RAISE_TO_POWER_POSITIVE:
    pha
    jsr STORE_FP_A_TEMP_1
    jsr ONE_FP_A
RAISE_TO_POWER_LOOP:
    pla
    beq RAISE_TO_POWER_DONE
    sec
    sbc #$01
    pha
    jsr MULTIPLY_FP_A
    jmp RAISE_TO_POWER_LOOP
RAISE_TO_POWER_DONE:
    rts
