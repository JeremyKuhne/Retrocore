;; CONVERSION ($D800-$DA43)
;;
;; The floating point package's conversions between its numbers and text or integers: AFP reads a number from the
;; text at INBUFF, FASC writes FR0 as text into LBUFF, IFP turns a 16-bit integer into a number and FPI rounds a
;; number to a 16-bit integer. Maintained by hand; assembles byte-identically to the chip.

; The conversions' own values.

AFP_NO_POINT = $FF                  ;; DIGRT while AFP has not met a decimal point
FASC_END_BIT = $80                  ;; the bit FASC sets in its text's last character

;; Reads a number from text, the OS User's Manual's ASCII to floating point conversion.
;;
;; Spaces before the number are skipped. The number is an optional sign, digits with at most one decimal point,
;; and an optional exponent: E, an optional sign and one or two digits. AFP stops at the first character that can't
;; continue the number. Only the first nine significant digits count; later ones are dropped, not rounded. An E that
;; no exponent follows isn't part of the number.
;;
;; The manual doesn't say so, but CIX isn't restored when the text doesn't start a number: it's left past the characters
;; tried. And when the exponent comes to zero once the dropped digits are counted (as in 1E0), CIX is left on the E,
;; though the number is right.
;; In: INBUFF = the text, CIX = the index in it of the number's first character, or of spaces before it
;; Out: FR0 = the number, CIX = the index of the first character after the number, carry = clear
;; Errors: carry = set if the first character after the spaces can't start a number, or the number is too large
;; Uses: A, X, Y, FRE, FRX, EEXP, NSIGN, ESIGN, FCHRFLG, DIGRT
;; See: <FASC>, <IFP>
AFP:
    jsr FP_SKIP_SPACES                      ; skip the spaces
    jsr FP_CHECK_NUMBER                      ; does a number start here?
    bcs AFP_NOT_NUMBER
    ldx #EEXP                       ; clear EEXP, NSIGN, ESIGN and FCHRFLG
    ldy #FCHRFLG - EEXP + 1
    jsr FP_CLEAR_BYTES
    ldx #AFP_NO_POINT
    stx DIGRT
    jsr ZFR0                        ; the mantissa starts at zero
    beq AFP_FIRST_CHARACTER         ; always: ZFR0 returns zero
AFP_NEXT_CHARACTER:
    lda #$FF                        ; past the first character, a sign ends the number
    sta FCHRFLG
AFP_FIRST_CHARACTER:
    jsr FP_READ_CHARACTER
    bcs AFP_NOT_DIGIT
    pha
    ldx FR0+1                       ; nine digits already?
    bne AFP_EXTRA_DIGIT
    jsr FP_SHIFT_FR0_DIGIT                      ; no: shift the digit into the mantissa's last place
    pla
    ora FR0+5
    sta FR0+5
    ldx DIGRT                       ; count it if it's after the point
    bmi AFP_NEXT_CHARACTER
    inx
    stx DIGRT
    bne AFP_NEXT_CHARACTER          ; always
AFP_EXTRA_DIGIT:
    pla                             ; drop the digit
    ldx DIGRT
    bpl AFP_EXTRA_DONE
    inc EEXP                        ; before the point, it still makes the number ten times larger
AFP_EXTRA_DONE:
    jmp AFP_NEXT_CHARACTER
AFP_NOT_NUMBER:
    rts
AFP_NOT_DIGIT:
    cmp #'.'
    beq AFP_POINT
    cmp #'E'
    beq AFP_EXPONENT
    ldx FCHRFLG                     ; a sign only starts the number
    bne AFP_END
    cmp #'+'
    beq AFP_NEXT_CHARACTER
    cmp #'-'
    beq AFP_SIGN                    ; to the next line either way
AFP_SIGN:
    sta NSIGN                       ; nonzero: negative
    beq AFP_NEXT_CHARACTER          ; always: FP_CHECK_NUMBER lets no other first character through
AFP_POINT:
    ldx DIGRT                       ; a second point ends the number
    bpl AFP_END
    inx                             ; no digits after the point yet
    stx DIGRT
    beq AFP_NEXT_CHARACTER          ; always
AFP_EXPONENT:
    lda CIX                         ; where to come back to if no exponent follows
    sta FRX
    jsr FP_READ_CHARACTER
    bcs AFP_EXPONENT_SIGN_CHARACTER
AFP_EXPONENT_DIGITS:
    tax                             ; A = the exponent's first digit
    lda EEXP                        ; keep the dropped digits' count
    pha
    stx EEXP
    jsr FP_READ_CHARACTER
    bcs AFP_EXPONENT_SIGN
    pha                             ; a second digit: EEXP = EEXP * 10 + the digit
    lda EEXP
    asl A
    sta EEXP
    asl A
    asl A
    adc EEXP
    sta EEXP
    pla
    clc
    adc EEXP
    sta EEXP
    ldy CIX                         ; step past one more character, which AFP_END steps back over
    jsr FP_READ_CHARACTER_ADVANCE
AFP_EXPONENT_SIGN:
    lda ESIGN
    beq AFP_ADD_EXPONENT
    lda EEXP                        ; negate the exponent
    eor #$FF
    clc
    adc #$01
    sta EEXP
AFP_ADD_EXPONENT:
    pla                             ; add the dropped digits' count
    clc
    adc EEXP
    sta EEXP
    bne AFP_END                     ; zero falls into the code below and leaves CIX on the E
AFP_EXPONENT_SIGN_CHARACTER:
    cmp #'+'
    beq AFP_EXPONENT_AFTER_SIGN
    cmp #'-'
    bne AFP_NO_EXPONENT
    sta ESIGN                       ; nonzero: negative
AFP_EXPONENT_AFTER_SIGN:
    jsr FP_READ_CHARACTER
    bcc AFP_EXPONENT_DIGITS
AFP_NO_EXPONENT:
    lda FRX                         ; the E isn't part of the number
    sta CIX
AFP_END:
    dec CIX                         ; back onto the character that ended the number
    lda EEXP                        ; the power of ten, less the digits after the point
    ldx DIGRT
    bmi AFP_HALVE_EXPONENT
    beq AFP_HALVE_EXPONENT
    sec
    sbc DIGRT
AFP_HALVE_EXPONENT:
    pha                             ; halve it, keeping its sign, for a power of 100
    rol A
    pla
    ror A
    sta EEXP
    bcc AFP_SET_EXPONENT
    jsr FP_SHIFT_FR0_DIGIT                      ; odd: one more digit's shift makes up the 10
AFP_SET_EXPONENT:
    lda EEXP                        ; the mantissa is an integer: 100^4 times a fraction
    clc
    adc #FP_EXPONENT_BIAS + 4
    sta FR0
    jsr FP_NORMALIZE
    bcs AFP_DONE
    ldx NSIGN
    beq AFP_POSITIVE
    lda FR0
    ora #FP_SIGN
    sta FR0
AFP_POSITIVE:
    clc
AFP_DONE:
    rts

;; Writes FR0 as text in LBUFF, the OS User's Manual's floating point to ASCII conversion.
;;
;; Numbers from 0.01 up to 10^10 are written plainly (123.45, 0.05); others in E notation with a sign and two
;; exponent digits (1.5E+12, 2.5E-05). Trailing zeros after the point, and the point when nothing follows it, are
;; left out. A negative number starts with a minus sign, and zero is a single 0. The text can start just before
;; LBUFF, at LBPR1 or LBPR2.
;; In: FR0 = the number
;; Out: INBUFF = the text's first character, its last character having bit 7 set (no end of line follows)
;; Uses: A, X, Y, CIX, EEXP, ZTEMP4, LBPR1, LBPR2, LBUFF
;; Keeps: FR0
;; See: <AFP>
FASC:
    jsr FP_SET_INBUFF_LBUFF                      ; INBUFF = LBUFF
    lda #'0'                        ; a zero before LBUFF, for a number below 1
    sta LBPR2
    lda FR0
    beq FASC_ZERO
    and #<~FP_SIGN
    cmp #FP_EXPONENT_BIAS - 1       ; 0.01 up to 10^10 are written plainly
    bcc FASC_E_NOTATION
    cmp #FP_EXPONENT_BIAS + 5
    bcs FASC_E_NOTATION
    sec                             ; the point goes after the mantissa's first A-1 bytes
    sbc #FP_EXPONENT_BIAS - 1
    jsr FP_WRITE_DIGITS
    jsr FP_FIND_LAST_DIGIT
    ora #FASC_END_BIT
    sta LBUFF,x
    lda LBUFF
    cmp #'.'
    beq FASC_FRACTION
    jmp FASC_SKIP_ZERO
FASC_FRACTION:
    jsr FP_DECREMENT_INBUFF                      ; start at LBPR2's zero
    jmp FASC_SIGN
FASC_ZERO:
    lda #'0' | FASC_END_BIT
    sta LBUFF
    rts
FASC_E_NOTATION:
    lda #1                          ; the point after the first byte: dd.dddddddd
    jsr FP_WRITE_DIGITS
    jsr FP_FIND_LAST_DIGIT
    inx
    stx CIX                         ; the text's length
    lda FR0                         ; the power of ten of the first byte
    asl A
    sec
    sbc #FP_EXPONENT_BIAS * 2
    ldx LBUFF                       ; one digit before the point is written as d.ddd
    cpx #'0'
    beq FASC_WRITE_EXPONENT
    ldx LBUFF+1                     ; two: move the point left one place
    ldy LBUFF+2
    stx LBUFF+2
    sty LBUFF+1
    ldx CIX                         ; with the point trimmed away, it comes back
    cpx #2
    bne FASC_NEXT_POWER
    inc CIX
FASC_NEXT_POWER:
    clc
    adc #1
FASC_WRITE_EXPONENT:
    sta EEXP
    lda #'E'
    ldy CIX
    jsr FP_WRITE_CHARACTER
    sty CIX
    lda EEXP
    bpl FASC_PLUS
    lda #0                          ; negate it
    sec
    sbc EEXP
    sta EEXP
    lda #'-'
    bne FASC_EXPONENT_SIGN          ; always
FASC_PLUS:
    lda #'+'
FASC_EXPONENT_SIGN:
    jsr FP_WRITE_CHARACTER
    ldx #0                          ; X = the tens
    lda EEXP
FASC_TENS:
    sec
    sbc #10
    bcc FASC_UNITS
    inx
    bne FASC_TENS                   ; always
FASC_UNITS:
    clc
    adc #10
    pha
    txa
    jsr FP_WRITE_DIGIT
    pla
    ora #FASC_END_BIT
    jsr FP_WRITE_DIGIT
FASC_SKIP_ZERO:
    lda LBUFF                       ; skip a leading zero, the first byte's tens
    cmp #'0'
    bne FASC_SIGN
    clc
    lda INBUFF
    adc #1
    sta INBUFF
    lda INBUFF+1
    adc #0
    sta INBUFF+1
FASC_SIGN:
    lda FR0
    bpl FASC_DONE
    jsr FP_DECREMENT_INBUFF                      ; a minus sign before the text
    ldy #0
    lda #'-'
    sta (INBUFF),y
FASC_DONE:
    rts

;; Turns an unsigned 16-bit integer into a number, the OS User's Manual's integer to floating point conversion.
;;
;; The integer's bits are shifted, high bit first, into a BCD integer in FR0+1..FR0+3 that doubles at each bit.
;; In: FR0/FR0+1 = the integer, 0-65535
;; Out: FR0 = the number, carry = clear
;; Uses: A, X, Y, FRE, ZTEMP4
;; See: <FPI>, <AFP>
IFP:
    lda FR0                         ; ZTEMP4 = the integer, high byte first
    sta ZTEMP4+1
    lda FR0+1
    sta ZTEMP4
    jsr ZFR0
    sed
    ldy #16                         ; the bits
IFP_BIT:
    asl ZTEMP4+1                    ; carry = the next bit
    rol ZTEMP4
    ldx #3                          ; FR0+3 to FR0+1 = FR0+1..FR0+3 * 2 + the bit
IFP_DOUBLE:
    lda FR0,x
    adc FR0,x
    sta FR0,x
    dex
    bne IFP_DOUBLE
    dey
    bne IFP_BIT
    cld
    lda #FP_EXPONENT_BIAS + 2       ; FR0+1 holds the ten thousands: 100^2
    sta FR0
    jmp FP_NORMALIZE

;; Rounds a number to an unsigned 16-bit integer, the OS User's Manual's floating point to integer conversion.
;;
;; The digits before the point are gathered one by one into ZTEMP4, high byte first, and the first digit after them
;; rounds. Two cases differ from the manual: 65535.5 up to 65536 gives 0 without an error, since the rounding's carry
;; is lost; and a number below 0.01 rounds by its first digit, so 0.005 gives 1.
;; In: FR0 = the number
;; Out: FR0/FR0+1 = the integer, carry = clear
;; Errors: carry = set if the number is negative or 65536 or more
;; Uses: A, X, Y, FR0, FRX, ZTEMP1, ZTEMP3, ZTEMP4
;; See: <IFP>, <FASC>
FPI:
    lda #0
    sta ZTEMP4
    sta ZTEMP4+1
    lda FR0
    bmi FPI_ERROR
    cmp #FP_EXPONENT_BIAS + 3       ; 10^6 and above never fit
    bcs FPI_ERROR
    sec
    sbc #FP_EXPONENT_BIAS
    bcc FPI_ROUND                   ; below 1: no digits before the point
    adc #0                          ; two digits for each byte before the point
    asl A
    sta ZTEMP1
FPI_DIGIT:
    jsr FP_DOUBLE_ZTEMP4                      ; ZTEMP4 = ZTEMP4 * 10, through * 2 kept in ZTEMP3
    bcs FPI_ERROR
    lda ZTEMP4
    sta ZTEMP3
    lda ZTEMP4+1
    sta ZTEMP3+1
    jsr FP_DOUBLE_ZTEMP4
    bcs FPI_ERROR
    jsr FP_DOUBLE_ZTEMP4
    bcs FPI_ERROR
    clc
    lda ZTEMP4+1
    adc ZTEMP3+1
    sta ZTEMP4+1
    lda ZTEMP4
    adc ZTEMP3
    sta ZTEMP4
    bcs FPI_ERROR
    jsr FP_TAKE_FR0_DIGIT                      ; plus the next digit
    clc
    adc ZTEMP4+1
    sta ZTEMP4+1
    lda ZTEMP4
    adc #0
    bcs FPI_ERROR
    sta ZTEMP4
    dec ZTEMP1
    bne FPI_DIGIT
FPI_ROUND:
    jsr FP_TAKE_FR0_DIGIT                      ; round by the next digit
    cmp #5
    bcc FPI_RESULT
    clc
    lda ZTEMP4+1
    adc #1
    sta ZTEMP4+1
    lda ZTEMP4
    adc #0                          ; a carry out of here is lost
    sta ZTEMP4
FPI_RESULT:
    lda ZTEMP4+1
    sta FR0
    lda ZTEMP4
    sta FR0+1
    clc
    rts
FPI_ERROR:
    sec
    rts
