;; ATARI 400/800 FLOATING POINT PACKAGE: ARITHMETIC ($DA44-$DD3F)
;;
;; Clearing a register (ZFR0, ZF1), the four operations (FADD, FSUB, FMUL, FDIV), and the helpers they and the
;; conversions share: normalizing a result and checking its range, shifting a mantissa by bytes or digits, the
;; six-byte BCD additions FMUL and FDIV repeat, and the text helpers AFP and FASC use to read and write numbers.
;;
;; The package works in decimal: each operation adds or subtracts the BCD mantissas with the 6502's decimal mode, and
;; FMUL and FDIV multiply and divide by repeated addition and subtraction, one digit at a time. Nothing rounds: digits
;; shifted out of a mantissa are dropped.

; ---------------------------------------------------------------------------------------------------------------------
; Constants for the arithmetic
; ---------------------------------------------------------------------------------------------------------------------

; The shape of a number, as OsEquates.asm describes it.

FP_EXPONENT_TOO_LARGE = $71         ;; the smallest exponent byte out of range, 100^49 (1E98): an overflow
FP_EXPONENT_SMALLEST = $0F          ;; the smallest exponent byte kept, 100^-49 (1E-98); smaller results become 0

; The characters AFP reads and FASC writes.

FP_SPACE = ' '                      ;; the space AFP skips before a number
FP_POINT = '.'                      ;; the decimal point
FP_PLUS = '+'                       ;; the plus sign
FP_MINUS = '-'                      ;; the minus sign
FP_ZERO_DIGIT = '0'                 ;; the digit 0; the digits 0-9 follow it

FP_DIGITS_LAST = 10                 ;; LBUFF's last index after <FP_WRITE_DIGITS>: ten digits and a point

;; Clears FR0, making it zero.
;;
;; It loads FR0's address and falls into <ZF1>.
;; Out: FR0 = 0, A = 0, X = FR0+6, Y = 0, zero = set
;; Keeps: carry
;; See: <ZF1>
ZFR0:
    ldx #FR0

;; Clears the floating point number at X in zero page, making it zero.
;; In: X = the number's address in zero page
;; Out: the six bytes at X = 0, A = 0, X = past the number, Y = 0, zero = set
;; Keeps: carry
;; See: <ZFR0>, <FP_CLEAR_BYTES>
ZF1:
    ldy #FP_SIZE

;; Clears a run of bytes in zero page.
;; In: X = the first byte's address, Y = how many bytes (1-256, 0 for 256)
;; Out: the bytes = 0, A = 0, X = past the last byte, Y = 0, zero = set
;; Keeps: carry
FP_CLEAR_BYTES:
    lda #$00
FP_CLEAR_BYTES_LOOP:
    sta 0,x
    inx
    dey
    bne FP_CLEAR_BYTES_LOOP
    rts

;; Points INBUFF at LBUFF, where FASC writes its text.
;; Out: INBUFF = LBUFF
;; Uses: A
;; Keeps: X, Y
FP_SET_INBUFF_LBUFF:
    lda #>LBUFF
    sta INBUFF+1
    lda #<LBUFF
    sta INBUFF
    rts

;; Doubles the 16-bit number in ZTEMP4, stored high byte first, for FPI.
;; In: ZTEMP4 = the high byte, ZTEMP4+1 = the low byte
;; Out: ZTEMP4 = doubled, carry = set when it overflowed
;; Keeps: A, X, Y
FP_DOUBLE_ZTEMP4:
    clc
    rol ZTEMP4+1
    rol ZTEMP4
    rts

;; Subtracts FR1 from FR0.
;;
;; It turns FR1's sign over and falls into <FADD>.
;; In: FR0 = the number to subtract from, FR1 = the number to subtract
;; Out: FR0 = FR0 - FR1, carry = clear when the result is in range
;; Errors: carry = set when the result is out of range (1E98 or more)
;; Uses: A, X, Y, FR1, FRE, ZTEMP3, ZTEMP4
;; See: <FADD>
FSUB:
    lda FR1
    eor #$80                        ; the sign
    sta FR1

;; Adds FR1 to FR0.
;;
;; The larger number goes to FR0 (the two swap when FR1's exponent is larger), and FR1's mantissa shifts right by
;; the difference in exponents to line its digits up; when they differ by five or more, FR1 is too small to matter
;; and FR0 is the result. Numbers of the same sign then add, a carry out shifting the sum a byte right; numbers of
;; different signs subtract, a borrow meaning FR1 was larger, so the difference is negated and its sign turned over.
;; <FP_NORMALIZE> then normalizes the result and checks its range. The digits shifted out of FR1 are dropped, not
;; rounded.
;; In: FR0, FR1 = the numbers to add
;; Out: FR0 = FR0 + FR1, carry = clear when the result is in range
;; Errors: carry = set when the result is out of range (1E98 or more)
;; Uses: A, X, Y, FR1 (shifted, or swapped with FR0), FRE, ZTEMP3, ZTEMP4
;; See: <FSUB>
FADD:
    lda FR1
    and #$7F
    sta ZTEMP4                      ; FR1's exponent without its sign
    lda FR0
    and #$7F
    sec
    sbc ZTEMP4                      ; how many bytes FR1 is below FR0
    bpl FADD_ALIGN
    ldx #FP_SIZE-1          ; FR1 is the larger: swap them
FADD_SWAP:
    lda FR0,x
    ldy FR1,x
    sta FR1,x
    tya
    sta FR0,x
    dex
    bpl FADD_SWAP
    bmi FADD                        ; always
FADD_ALIGN:
    beq FADD_ALIGNED
    cmp #FP_MANTISSA_BYTES
    bcs FADD_NORMALIZE              ; FR1 is too small to change FR0
    jsr FP_SHIFT_FR1_RIGHT
FADD_ALIGNED:
    sed
    lda FR0
    eor FR1
    bmi FADD_SUBTRACT               ; the signs differ
    ldx #FP_MANTISSA_BYTES-1
    clc
FADD_ADD:
    lda FR0+1,x
    adc FR1+1,x
    sta FR0+1,x
    dex
    bpl FADD_ADD
    cld
    bcs FADD_CARRY
FADD_NORMALIZE:
    jmp FP_NORMALIZE
FADD_CARRY:
    lda #$01                        ; the sum reached 100: shift it a byte right
    jsr FP_SHIFT_FR0_RIGHT
    lda #$01                        ; ... and bring the carry in as its first byte
    sta FR0+1
    jmp FP_NORMALIZE
FADD_SUBTRACT:
    ldx #FP_MANTISSA_BYTES-1
    sec
FADD_SUBTRACT_LOOP:
    lda FR0+1,x
    sbc FR1+1,x
    sta FR0+1,x
    dex
    bpl FADD_SUBTRACT_LOOP
    bcc FADD_NEGATE                 ; a borrow: FR1's mantissa was the larger
    cld
    jmp FP_NORMALIZE
FADD_NEGATE:
    lda FR0
    eor #$80                        ; the result takes FR1's sign
    sta FR0
    sec
    ldx #FP_MANTISSA_BYTES-1
FADD_NEGATE_LOOP:
    lda #$00                        ; the ten's complement: 0 - the mantissa
    sbc FR0+1,x
    sta FR0+1,x
    dex
    bpl FADD_NEGATE_LOOP
    cld
    jmp FP_NORMALIZE

;; Multiplies FR0 by FR1.
;;
;; The product builds up in the twelve bytes of FR0 and FRE, with FR0's mantissa in FRE: for each of its five bytes,
;; from the last, FR1 is added as many times as the byte's low digit and ten times FR1 (in FR2) as many times as its
;; high digit, then the twelve bytes shift a byte right, dropping the byte just used. <FP_NORMALIZE_FRE> then
;; normalizes the product, dropping the digits beyond ten.
;;
;; An exponent that does not fit in seven bits is an error even when the product is tiny, so a product below about
;; 1E-130 gives carry set rather than zero; one between that and 1E-98 becomes zero.
;; In: FR0, FR1 = the numbers to multiply
;; Out: FR0 = FR0 * FR1, carry = clear when the result is in range
;; Errors: carry = set when the result is out of range
;; Uses: A, X, Y, FR1 (its sign cleared), FR2, FRE, FRX, EEXP, NSIGN, ZTEMP1, ZTEMP4
;; See: <FDIV>
FMUL:
    lda FR0
    beq FMUL_OK                     ; 0 times anything is FR0's 0
    lda FR1
    beq FMUL_ZERO
    jsr FP_MUL_DIV_SIGN
    sec
    sbc #FP_EXPONENT_BIAS
    sec
    adc FR1                         ; the exponents' sum, plus one for the product's extra byte
    bmi FMUL_ERROR
    jsr FP_MUL_DIV_SETUP
FMUL_BYTE:
    lda FRE+5                       ; the multiplier's last byte
    and #$0F
    sta ZTEMP1+1
FMUL_LOW_DIGIT:
    dec ZTEMP1+1
    bmi FMUL_HIGH
    jsr FP_ADD_FR1_TO_FR0
    jmp FMUL_LOW_DIGIT
FMUL_HIGH:
    lda FRE+5
    lsr A
    lsr A
    lsr A
    lsr A
    sta ZTEMP1+1
FMUL_HIGH_DIGIT:
    dec ZTEMP1+1
    bmi FMUL_NEXT_BYTE
    jsr FP_ADD_FR2_TO_FR0
    jmp FMUL_HIGH_DIGIT
FMUL_NEXT_BYTE:
    jsr FP_SHIFT_PRODUCT_RIGHT
    dec ZTEMP1
    bne FMUL_BYTE
FMUL_DONE:
    lda EEXP                        ; FDIV ends here too
    sta FR0
    jmp FP_NORMALIZE_FRE
FMUL_ZERO:
    jsr ZFR0
FMUL_OK:
    clc
    rts
FMUL_ERROR:
    sec
    rts

;; Divides FR0 by FR1.
;;
;; The dividend's mantissa goes to FRE and the quotient builds up in FR0, a byte at a time in FR0+5: ten times the
;; divisor (in FR2) is subtracted from FRE until it borrows, counting the high digit, then the divisor itself,
;; counting the low digit, each borrow added back. FR0 and FRE then shift a byte left together for the next byte.
;; After six bytes <FP_NORMALIZE_FRE> normalizes the quotient, dropping the digits beyond ten.
;;
;; As in <FMUL>, an exponent that does not fit in seven bits is an error even when the quotient is tiny.
;; In: FR0 = the dividend, FR1 = the divisor
;; Out: FR0 = FR0 / FR1, carry = clear when the result is in range
;; Errors: carry = set when FR1 is zero or the result is out of range
;; Uses: A, X, Y, FR1 (its sign cleared), FR2, FRE, FRX, EEXP, NSIGN, ZTEMP1, ZTEMP4
;; See: <FMUL>
FDIV:
    lda FR1
    beq FMUL_ERROR                  ; dividing by zero
    lda FR0
    beq FMUL_OK                     ; 0 divided by anything is FR0's 0
    jsr FP_MUL_DIV_SIGN
    sec
    sbc FR1
    clc
    adc #FP_EXPONENT_BIAS           ; the exponents' difference
    bmi FMUL_ERROR
    jsr FP_MUL_DIV_SETUP
    inc ZTEMP1                      ; six quotient bytes
    jmp FDIV_HIGH_DIGIT
FDIV_NEXT_BYTE:
    ldx #$00                        ; shift FR0 and FRE a byte left, FR1's cleared exponent coming in
FDIV_SHIFT:
    lda FR0+1,x
    sta FR0,x
    inx
    cpx #2*FP_SIZE
    bne FDIV_SHIFT
FDIV_HIGH_DIGIT:
    ldy #FP_SIZE-1
    sec
    sed
FDIV_SUBTRACT_FR2:
    lda FRE,y
    sbc FR2,y
    sta FRE,y
    dey
    bpl FDIV_SUBTRACT_FR2
    cld
    bcc FDIV_LOW
    inc FR0+5
    bne FDIV_HIGH_DIGIT             ; always
FDIV_LOW:
    jsr FP_ADD_FR2_TO_FRE           ; undo the subtraction that borrowed
    asl FR0+5                       ; the count is the high digit
    asl FR0+5
    asl FR0+5
    asl FR0+5
FDIV_LOW_DIGIT:
    ldy #FP_SIZE-1
    sec
    sed
FDIV_SUBTRACT_FR1:
    lda FRE,y
    sbc FR1,y
    sta FRE,y
    dey
    bpl FDIV_SUBTRACT_FR1
    cld
    bcc FDIV_BYTE_DONE
    inc FR0+5
    bne FDIV_LOW_DIGIT              ; always
FDIV_BYTE_DONE:
    jsr FP_ADD_FR1_TO_FRE           ; undo the subtraction that borrowed
    dec ZTEMP1
    bne FDIV_NEXT_BYTE
    jsr FP_SHIFT_PRODUCT_RIGHT
    jmp FMUL_DONE

;; Reads AFP's next character from INBUFF at CIX, as a digit's value when it is one.
;; In: INBUFF = the text, CIX = the character's index
;; Out: A = the digit's value (carry clear) or the character (carry set), CIX = Y = past the character
;; Entry: FP_READ_CHARACTER_ADVANCE = only advances CIX, to Y + 1
;; Keeps: X
FP_READ_CHARACTER:
    jsr FP_TEST_DIGIT
    ldy CIX
    bcc FP_READ_CHARACTER_ADVANCE
    lda (INBUFF),y
FP_READ_CHARACTER_ADVANCE:
    iny
    sty CIX
    rts

;; Skips the spaces in INBUFF at CIX.
;; In: INBUFF = the text, CIX = where to start
;; Out: CIX = Y = the first character that is not a space
;; Uses: A
;; Keeps: X
FP_SKIP_SPACES:
    ldy CIX
    lda #FP_SPACE
FP_SKIP_SPACES_LOOP:
    cmp (INBUFF),y
    bne FP_SKIP_SPACES_DONE
    iny
    bne FP_SKIP_SPACES_LOOP
FP_SKIP_SPACES_DONE:
    sty CIX
    rts

;; Tells whether the character in INBUFF at CIX is a digit.
;; In: INBUFF = the text, CIX = the character's index
;; Out: carry = clear for a digit, A = the digit's value (when a digit), Y = CIX
;; Keeps: X
FP_TEST_DIGIT:
    ldy CIX
    lda (INBUFF),y
    sec
    sbc #FP_ZERO_DIGIT
    bcc FP_CHECK_NUMBER_NOT_DIGIT
    cmp #10
    rts

;; Tells whether the text in INBUFF at CIX starts a number, for AFP.
;;
;; A number starts with a digit, a point and a digit, or a sign followed by either. When it does, CIX is put back;
;; when it doesn't, CIX is left past the characters looked at.
;; In: INBUFF = the text, CIX = where it starts
;; Out: carry = clear when a number starts there, CIX = unchanged when it does
;; Uses: A, Y
;; Keeps: X
FP_CHECK_NUMBER:
    lda CIX
    pha
    jsr FP_READ_CHARACTER
    bcc FP_CHECK_NUMBER_YES
    cmp #FP_POINT
    beq FP_CHECK_NUMBER_POINT
    cmp #FP_PLUS
    beq FP_CHECK_NUMBER_SIGN
    cmp #FP_MINUS
    beq FP_CHECK_NUMBER_SIGN
FP_CHECK_NUMBER_NO:
    pla                             ; drop the saved CIX
FP_CHECK_NUMBER_NOT_DIGIT:
    sec
    rts
FP_CHECK_NUMBER_SIGN:
    jsr FP_READ_CHARACTER
    bcc FP_CHECK_NUMBER_YES
    cmp #FP_POINT
    bne FP_CHECK_NUMBER_NO
FP_CHECK_NUMBER_POINT:
    jsr FP_READ_CHARACTER
    bcc FP_CHECK_NUMBER_YES
    bcs FP_CHECK_NUMBER_NO          ; always
FP_CHECK_NUMBER_YES:
    pla
    sta CIX
    clc
    rts

;; Shifts FR2's mantissa a digit left, for FR1 times ten in <FP_MUL_DIV_SETUP>.
;; In: FR2 = the number
;; Out: FR2+1..FR2+5 = shifted, a 0 coming in last, FRX = the digit shifted out in its low four bits
;; Uses: X, Y
;; Keeps: A
FP_SHIFT_FR2_DIGIT:
    ldx #FR2+1
    bne FP_SHIFT_DIGIT              ; always

;; Shifts FR0's mantissa a digit left.
;; In: FR0 = the number
;; Out: FR0+1..FR0+5 = shifted, a 0 coming in last, FRX = the digit shifted out in its low four bits
;; Entry: FP_SHIFT_DIGIT = shifts the five bytes at X
;; Uses: X, Y
;; Keeps: A
FP_SHIFT_FR0_DIGIT:
    ldx #FR0+1
FP_SHIFT_DIGIT:
    ldy #$04                        ; four bits
FP_SHIFT_DIGIT_LOOP:
    clc
    rol 4,x
    rol 3,x
    rol 2,x
    rol 1,x
    rol 0,x
    rol FRX
    dey
    bne FP_SHIFT_DIGIT_LOOP
    rts

;; Normalizes FR0 and checks its range: every operation's result passes through here.
;;
;; It clears FRE's first byte and joins <FP_NORMALIZE_FRE>. FADD's results come here, with no digits beyond FR0.
;; In: FR0 = the result
;; Out: FR0 = normalized, or 0, carry = clear when in range
;; Errors: carry = set when FR0 is 1E98 or more
;; Entry: FP_NORMALIZE_FRE = normalizes FR0 with FRE's first byte as its next two digits
;; Uses: A, X, Y, FRE
FP_NORMALIZE:
    ldx #$00
    stx FRE
FP_NORMALIZE_FRE:
    ldx #FP_MANTISSA_BYTES-1        ; shift up to four bytes
    lda FR0
    beq FP_NORMALIZE_OK             ; zero
FP_NORMALIZE_BYTE:
    lda FR0+1
    bne FP_NORMALIZE_RANGE
    ldy #$00                        ; a zero first byte: shift the mantissa and FRE's first byte a byte left
FP_NORMALIZE_SHIFT:
    lda FR0+2,y
    sta FR0+1,y
    iny
    cpy #FP_MANTISSA_BYTES
    bcc FP_NORMALIZE_SHIFT
    dec FR0
    dex
    bne FP_NORMALIZE_BYTE
    lda FR0+1
    bne FP_NORMALIZE_RANGE
    sta FR0                         ; still zero: the result is 0
    clc
    rts
FP_NORMALIZE_RANGE:
    lda FR0
    and #$7F
    cmp #FP_EXPONENT_TOO_LARGE
    bcc FP_NORMALIZE_SMALL
    rts                             ; an overflow, with carry set
FP_NORMALIZE_SMALL:
    cmp #FP_EXPONENT_SMALLEST
    bcs FP_NORMALIZE_OK
    jsr ZFR0                        ; too small: an underflow to 0
FP_NORMALIZE_OK:
    clc
    rts

;; Shifts FR0's mantissa right by whole bytes, raising its exponent to match.
;; In: A = how many bytes (1-255)
;; Out: FR0 = shifted, zeros coming in first, the bytes shifted out dropped
;; Uses: A, X, Y, ZTEMP3, ZTEMP4
;; See: <FP_SHIFT_FR1_RIGHT>
FP_SHIFT_FR0_RIGHT:
    ldx #FR0
    bne FP_SHIFT_RIGHT              ; always

;; Shifts FR1's mantissa right by whole bytes, raising its exponent to match, to line it up with FR0's in FADD.
;; In: A = how many bytes (1-255)
;; Out: FR1 = shifted, zeros coming in first, the bytes shifted out dropped
;; Entry: FP_SHIFT_RIGHT = shifts the number at X in zero page
;; Uses: A, X, Y, ZTEMP3, ZTEMP4
FP_SHIFT_FR1_RIGHT:
    ldx #FR1
FP_SHIFT_RIGHT:
    stx ZTEMP3
    sta ZTEMP4                      ; the bytes left to shift
    sta ZTEMP4+1                    ; ... and what to add to the exponent
FP_SHIFT_RIGHT_LOOP:
    ldy #FP_MANTISSA_BYTES-1
FP_SHIFT_RIGHT_BYTE:
    lda 4,x
    sta 5,x
    dex
    dey
    bne FP_SHIFT_RIGHT_BYTE
    lda #$00
    sta 5,x                         ; the first mantissa byte
    ldx ZTEMP3
    dec ZTEMP4
    bne FP_SHIFT_RIGHT_LOOP
    lda 0,x
    clc
    adc ZTEMP4+1
    sta 0,x
    rts

;; Shifts the twelve bytes of FR0 and FRE a byte right, for FMUL and FDIV.
;; In: FR0, FRE = the product or quotient
;; Out: FR0..FRE+5 = shifted, FR0 = 0, the last byte of FRE dropped
;; Uses: A, X
;; Keeps: Y
FP_SHIFT_PRODUCT_RIGHT:
    ldx #2*FP_SIZE-2
FP_SHIFT_PRODUCT_RIGHT_LOOP:
    lda FR0,x
    sta FR0+1,x
    dex
    bpl FP_SHIFT_PRODUCT_RIGHT_LOOP
    lda #$00
    sta FR0
    rts

;; Writes FR0's ten digits to LBUFF as text, with a decimal point among them, for FASC.
;;
;; The digits are left unchanged: FASC trims and marks them afterwards. Once the point is written, ZTEMP4 counts on
;; down from the point's character code, so it is never written again.
;; In: FR0 = the number, A = how many mantissa bytes (digit pairs) come before the point (0-5)
;; Out: LBUFF = the ten digits and the point, Y = 11, X = 5
;; Uses: A, ZTEMP4
;; See: <FP_FIND_LAST_DIGIT>
FP_WRITE_DIGITS:
    sta ZTEMP4                      ; the digit pairs before the point
    ldx #$00
    ldy #$00
FP_WRITE_DIGITS_LOOP:
    jsr FP_WRITE_POINT
    sec
    sbc #$01
    sta ZTEMP4
    lda FR0+1,x
    lsr A
    lsr A
    lsr A
    lsr A
    jsr FP_WRITE_DIGIT
    lda FR0+1,x
    and #$0F
    jsr FP_WRITE_DIGIT
    inx
    cpx #FP_MANTISSA_BYTES
    bcc FP_WRITE_DIGITS_LOOP

;; Writes the decimal point to LBUFF at Y when its time has come, for <FP_WRITE_DIGITS>.
;; In: ZTEMP4 = 0 when the point is due, Y = where to write it
;; Out: A = ZTEMP4, or the point when written, Y = past it when written
;; Keeps: X
FP_WRITE_POINT:
    lda ZTEMP4
    bne FP_WRITE_POINT_DONE
    lda #FP_POINT
    jsr FP_WRITE_CHARACTER
FP_WRITE_POINT_DONE:
    rts

;; Writes a digit to LBUFF at Y as its character.
;; In: A = the digit (0-9), Y = where to write it
;; Out: Y = past it, A = the character
;; Keeps: X
FP_WRITE_DIGIT:
    ora #FP_ZERO_DIGIT

;; Writes a character to LBUFF at Y.
;; In: A = the character, Y = where to write it
;; Out: Y = past it
;; Keeps: A, X
FP_WRITE_CHARACTER:
    sta LBUFF,y
    iny
    rts

;; Finds the last character of FASC's number in LBUFF, ignoring trailing zeros and a point with nothing after it.
;;
;; It looks back from index 10, the last of <FP_WRITE_DIGITS>' eleven characters. A point found first means every
;; digit after it was a zero, and the digit before it is the last.
;; In: LBUFF = the digits and point <FP_WRITE_DIGITS> wrote
;; Out: X = the last character's index, A = that character
;; Keeps: Y
FP_FIND_LAST_DIGIT:
    ldx #FP_DIGITS_LAST
FP_FIND_LAST_DIGIT_LOOP:
    lda LBUFF,x
    cmp #FP_POINT
    beq FP_FIND_LAST_DIGIT_POINT
    cmp #FP_ZERO_DIGIT
    bne FP_FIND_LAST_DIGIT_DONE
    dex
    bne FP_FIND_LAST_DIGIT_LOOP
FP_FIND_LAST_DIGIT_POINT:
    dex
    lda LBUFF,x
FP_FIND_LAST_DIGIT_DONE:
    rts

;; Takes FR0's first digit off, shifting the rest up a digit, for FPI to read the integer part a digit at a time.
;; In: FR0 = the number
;; Out: A = the digit taken, FR0+1..FR0+5 = shifted a digit left
;; Uses: X, Y, FRX
;; See: <FP_SHIFT_FR0_DIGIT>
FP_TAKE_FR0_DIGIT:
    jsr FP_SHIFT_FR0_DIGIT
    lda FRX
    and #$0F
    rts

;; Moves INBUFF back a byte, for FASC to put a character before its text.
;; In: INBUFF = the pointer
;; Out: INBUFF = one less
;; Uses: A
;; Keeps: X, Y
FP_DECREMENT_INBUFF:
    sec
    lda INBUFF
    sbc #$01
    sta INBUFF
    lda INBUFF+1
    sbc #$00
    sta INBUFF+1
    rts

;; Works out the sign of FMUL's or FDIV's result and strips FR1's.
;; In: FR0, FR1 = the operands
;; Out: NSIGN = the result's sign in bit 7, FR1 = without its sign, A = FR0's exponent without its sign
;; Keeps: X, Y
FP_MUL_DIV_SIGN:
    lda FR0
    eor FR1
    and #$80
    sta NSIGN
    asl FR1
    lsr FR1
    lda FR0
    and #$7F
    rts

;; Sets FMUL and FDIV up: the result's exponent, the operands' mantissas, and FR1 times ten.
;;
;; The mantissas become twelve-digit numbers in six bytes, their exponent bytes cleared, for the six-byte BCD
;; additions and subtractions: FR0's goes to FRE, FR1's stays, and ten times it goes to FR2.
;; In: A = the result's exponent without its sign, NSIGN = its sign, FR0, FR1 = the operands
;; Out: EEXP = the result's exponent byte, FRE = FR0's mantissa, FR1 = its mantissa, FR2 = ten times FR1,
;;   FR0 = 0, ZTEMP1 = 5
;; Uses: A, X, Y, FRX
FP_MUL_DIV_SETUP:
    ora NSIGN
    sta EEXP
    lda #$00
    sta FR0
    sta FR1
    jsr FP_COPY_FR1_TO_FR2
    jsr FP_SHIFT_FR2_DIGIT
    lda FRX
    and #$0F
    sta FR2                         ; the digit shifted out leads
    lda #FP_MANTISSA_BYTES
    sta ZTEMP1                      ; the bytes to multiply or divide
    jsr FP_COPY_FR0_TO_FRE
    jsr ZFR0
    rts

;; Adds FR1 to FR0 as six-byte BCD numbers, for FMUL.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = FR0 + FR1
;; Uses: A, X, Y, ZTEMP4
FP_ADD_FR1_TO_FR0:
    ldx #FR0+5
    bne FP_ADD_FR1                  ; always

;; Adds FR2 to FR0 as six-byte BCD numbers, for FMUL.
;; In: FR0, FR2 = the numbers
;; Out: FR0 = FR0 + FR2
;; Uses: A, X, Y, ZTEMP4
FP_ADD_FR2_TO_FR0:
    ldx #FR0+5
    bne FP_ADD_FR2                  ; always

;; Adds FR1 to FRE as six-byte BCD numbers, for FDIV.
;; In: FRE, FR1 = the numbers
;; Out: FRE = FRE + FR1
;; Entry: FP_ADD_FR1 = adds FR1 to the six bytes ending at X
;; Uses: A, X, Y, ZTEMP4
FP_ADD_FR1_TO_FRE:
    ldx #FRE+5
FP_ADD_FR1:
    ldy #FR1+5
    bne FP_ADD_NUMBERS              ; always

;; Adds FR2 to FRE as six-byte BCD numbers, for FDIV.
;;
;; The addition runs in decimal mode, from the last byte to the first, and drops a carry out of the first.
;; In: FRE, FR2 = the numbers
;; Out: FRE = FRE + FR2
;; Entry: FP_ADD_FR2 = adds FR2 to the six bytes ending at X, FP_ADD_NUMBERS = adds the six bytes ending at Y to
;;   the six bytes ending at X
;; Uses: A, X, Y, ZTEMP4
FP_ADD_FR2_TO_FRE:
    ldx #FRE+5
FP_ADD_FR2:
    ldy #FR2+5
FP_ADD_NUMBERS:
    lda #FP_SIZE-1
    sta ZTEMP4
    clc
    sed
FP_ADD_NUMBERS_LOOP:
    lda 0,x
    adc 0,y
    sta 0,x
    dex
    dey
    dec ZTEMP4
    bpl FP_ADD_NUMBERS_LOOP
    cld
    rts

;; Copies FR1 to FR2.
;; Out: FR2 = FR1, Y = $FF
;; Uses: A
;; Keeps: X
FP_COPY_FR1_TO_FR2:
    ldy #FP_SIZE-1
FP_COPY_FR1_TO_FR2_LOOP:
    lda FR1,y
    sta FR2,y
    dey
    bpl FP_COPY_FR1_TO_FR2_LOOP
    rts

;; Copies FR0 to FRE.
;; Out: FRE = FR0, Y = $FF
;; Uses: A
;; Keeps: X
FP_COPY_FR0_TO_FRE:
    ldy #FP_SIZE-1
FP_COPY_FR0_TO_FRE_LOOP:
    lda FR0,y
    sta FRE,y
    dey
    bpl FP_COPY_FR0_TO_FRE_LOOP
    rts
