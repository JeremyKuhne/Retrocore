;; FUNCTIONS ($AF31-$B205)
;;
;; The arithmetic that finds an array element, the comparison of two strings, and the functions: LEN, PEEK, FRE, VAL,
;; ASC, ADR, PADDLE, STICK, PTRIG, STRIG, STR$, CHR$, RND, ABS, USR, INT, SIN, COS, ATN, LOG, CLOG, EXP and SQR, then
;; the ^ operator. Each function's routine is reached through the operator execution table once its arguments are on
;; the argument stack; it pops them, works out its value and pushes it in their place. Maintained by hand; assembles
;; byte-identically to the cartridge.

; The results the string comparison gives, as A and its flags.

FUNCTIONS_STRING_LESS = $80         ;; the first string sorts before the second (negative)
FUNCTIONS_STRING_GREATER = $01      ;; the first string sorts after the second (positive, not zero)

FUNCTIONS_PRODUCT_BITS = 16         ;; the bits of <ARRAY_MULTIPLY>'s multiplier
FUNCTIONS_LOG_TINY = FP_EXPONENT_BIAS - 5 ;; the exponent byte of positive numbers from 10^-10 up to 10^-8

;; Multiplies ZTEMP1 by 6, the bytes of an array element.
;;
;; The product's 16 bits are kept; a carry out of them is lost.
;; In: ZTEMP1 = the number
;; Out: ZTEMP1 = the number times 6
;; Uses: A, Y
;; Keeps: X
;; See: <ARRAY_MULTIPLY>
ARRAY_TIMES_SIX:
    asl ZTEMP1                      ; twice the number, kept in Y:A
    rol ZTEMP1+1
    ldy ZTEMP1+1
    lda ZTEMP1
    asl ZTEMP1                      ; four times, plus twice
    rol ZTEMP1+1

;; Adds Y:A to ZTEMP1, as an array element's address is built up.
;; In: A = the low byte, Y = the high byte, ZTEMP1 = the sum so far
;; Out: ZTEMP1 = the sum, carry = the carry out of it
;; Uses: A
;; Keeps: X, Y
ARRAY_ADD:
    clc
    adc ZTEMP1
    sta ZTEMP1
    tya
    adc ZTEMP1+1
    sta ZTEMP1+1
    rts

;; Multiplies two 16-bit numbers: an array's first subscript by its second size, or DIM's two sizes.
;;
;; A shift and add multiply of 16 rounds: each round adds the multiplicand to the product's high half when the
;; multiplier's low bit is set, then shifts the product and the multiplier, which share ZTEMP4:ZTEMP1, right a bit.
;; In: ZTEMP1 = the multiplier, FR0+4 = the multiplicand (an array value's second size)
;; Out: ZTEMP1 = the product's low 16 bits, ZTEMP4 = its high 16 bits
;; Uses: A, X, Y
;; See: <ARRAY_TIMES_SIX>, <ARRAY_ADD>
ARRAY_MULTIPLY:
    lda #$00
    sta ZTEMP4
    sta ZTEMP4+1
    ldy #FUNCTIONS_PRODUCT_BITS
ARRAY_MULTIPLY_LOOP:
    lda ZTEMP1                      ; the multiplier's next bit
    lsr A
    bcc ARRAY_MULTIPLY_SHIFT
    clc
    ldx #$FE                        ; -2: two bytes, ZTEMP4 and FR0+4, wrapping in zero page
ARRAY_MULTIPLY_ADD:
    lda ZTEMP4+2,x
    adc FR0+4+2,x
    sta ZTEMP4+2,x
    inx
    bne ARRAY_MULTIPLY_ADD
ARRAY_MULTIPLY_SHIFT:
    ldx #$03                        ; the four bytes from ZTEMP4+1 down to ZTEMP1, the add's carry coming in at the top
ARRAY_MULTIPLY_ROTATE:
    ror ZTEMP1,x
    dex
    bpl ARRAY_MULTIPLY_ROTATE
    dey
    bne ARRAY_MULTIPLY_LOOP
    rts

;; Compares the two strings on the top of the argument stack, for the string comparison operators.
;;
;; The strings compare character by character, by their codes; where one is the start of the other, the shorter sorts
;; first. Both are popped; the operator that called it pushes its result.
;; In: ARGUMENT_INDEX = the top entry: the second string, the first below it
;; Out: A = FUNCTIONS_STRING_LESS, FUNCTIONS_STRING_GREATER, or 0 when they are equal, negative = set when the first
;;   is less, zero = set when they are equal
;; Uses: X, Y, FR0, FR1, VALUE_TYPE, VALUE_NUMBER, ARGUMENT_INDEX
;; Errors: 9 (DIM error) when a string has not been DIMensioned
;; See: <COMPARE_VALUES>
COMPARE_STRINGS:
    jsr POP_ABSOLUTE_VALUE          ; the second string
    jsr FMOVE                       ; to FR1
    jsr POP_ABSOLUTE_VALUE          ; the first, in FR0
COMPARE_STRINGS_LOOP:
    ldx #FR0+2                      ; is the first string used up?
    jsr DECREMENT_LENGTH
    php
    ldx #FR1+2                      ; the second?
    jsr DECREMENT_LENGTH
    beq COMPARE_STRINGS_SECOND_ENDED
    plp
    beq COMPARE_STRINGS_LESS        ; only the first ended: it is the shorter
    ldy #$00
    lda (FR0),y
    cmp (FR1),y
    beq COMPARE_STRINGS_NEXT
    bcc COMPARE_STRINGS_LESS
COMPARE_STRINGS_GREATER:
    lda #FUNCTIONS_STRING_GREATER
    rts
COMPARE_STRINGS_LESS:
    lda #FUNCTIONS_STRING_LESS
    rts
COMPARE_STRINGS_SECOND_ENDED:
    plp
    bne COMPARE_STRINGS_GREATER     ; only the second ended
    rts                             ; both ended: equal, with A = 0 and zero set
COMPARE_STRINGS_NEXT:
    inc FR0
    bne COMPARE_STRINGS_NEXT_SECOND
    inc FR0+1
COMPARE_STRINGS_NEXT_SECOND:
    inc FR1
    bne COMPARE_STRINGS_LOOP
    inc FR1+1
    bne COMPARE_STRINGS_LOOP        ; always: a string never wraps past $FFFF

;; Counts one character off a string's length, unless it is 0.
;; In: X = the length's address in zero page (2 bytes)
;; Out: zero = set when the length was 0 and is left so, clear when it was counted down
;; Uses: A, Y
;; Keeps: X
DECREMENT_LENGTH:
    lda 0,x
    bne DECREMENT_LENGTH_LOW
    lda 1,x
    beq DECREMENT_LENGTH_DONE
    dec 1,x
DECREMENT_LENGTH_LOW:
    dec 0,x
    tay                             ; zero clear: A holds the nonzero byte read
DECREMENT_LENGTH_DONE:
    rts

;; LEN(sexp): the length of a string.
;;
;; It pops the string, which must have been DIMensioned, and returns its length, from the value's third and fourth
;; bytes, as a number.
;; In: ARGUMENT_INDEX = the top entry: the string
;; Out: ARGUMENT_INDEX = the top entry: the length
;; Uses: all
;; Errors: 9 (DIM error)
FUNCTION_LEN:
    jsr POP_ABSOLUTE_VALUE
    lda FR0+2
    ldy FR0+3

;; Pushes the 16-bit integer in Y:A as a function's numeric result.
;; In: A = the low byte, Y = the high byte
;; Out: ARGUMENT_INDEX = the top entry: the number
;; Uses: all
;; Errors: 10 (argument stack overflow)
;; Entry: RESULT_INTEGER_FR0 = takes the integer from FR0 (2 bytes), RESULT_NUMBER = pushes the number in FR0 as it is
RESULT_INTEGER:
    sta FR0
    sty FR0+1
RESULT_INTEGER_FR0:
    jsr IFP
RESULT_NUMBER:
    lda #$00                        ; a number, from no variable
    sta VALUE_TYPE
    sta VALUE_NUMBER
    jmp PUSH_VALUE

;; PEEK(aexp): the byte at an address.
;;
;; It pops the address as an integer (0-65535) and returns the byte there.
;; In: ARGUMENT_INDEX = the top entry: the address
;; Out: ARGUMENT_INDEX = the top entry: the byte
;; Uses: all
;; Errors: 3 (value error) when the address is negative or above 65535
FUNCTION_PEEK:
    jsr POP_UNSIGNED
    ldy #$00
    lda (FR0),y
    jmp RESULT_INTEGER

;; FRE(aexp): the free memory, in bytes.
;;
;; Its argument is a dummy, popped and ignored. The free memory is what lies between the top of BASIC's tables,
;; BASIC_MEMTOP, and the OS's MEMTOP below the screen.
;; In: ARGUMENT_INDEX = the top entry: the dummy
;; Out: ARGUMENT_INDEX = the top entry: the free bytes
;; Uses: all
FUNCTION_FRE:
    jsr POP_VALUE
    sec
    lda MEMTOP
    sbc BASIC_MEMTOP
    sta FR0
    lda MEMTOP+1
    sbc BASIC_MEMTOP+1
    sta FR0+1
    jmp RESULT_INTEGER_FR0

;; VAL(sexp): the number a string starts with.
;;
;; It ends the string with an EOL for the moment, reads a number from its start with the FP package's AFP, and puts
;; the string's following byte back. Anything after the number is ignored; a string that doesn't start with a number
;; is an error.
;; In: ARGUMENT_INDEX = the top entry: the string
;; Out: ARGUMENT_INDEX = the top entry: the number
;; Uses: all
;; Errors: 18 (invalid string character) when the string doesn't start with a number, 9 (DIM error)
FUNCTION_VAL:
    jsr PATCH_STRING_EOL            ; the string at INBUFF, ended with an EOL
    lda #$00
    sta CIX
    jsr AFP
    jsr RESTORE_STRING_EOL          ; restore its byte, keeping AFP's carry
    bcc RESULT_NUMBER
    jsr INVALID_STRING_CHARACTER_ERROR ; error 18, which doesn't return

;; ASC(sexp): the code of a string's first character.
;;
;; It doesn't check the length: for an empty string it returns the byte where the string's first character would be.
;; In: ARGUMENT_INDEX = the top entry: the string
;; Out: ARGUMENT_INDEX = the top entry: the character's code
;; Uses: all
;; Errors: 9 (DIM error)
FUNCTION_ASC:
    jsr POP_ABSOLUTE_VALUE
    ldy #$00
    lda (FR0),y
    jmp RESULT_INTEGER

;; ADR(sexp): the address of a string's first character.
;; In: ARGUMENT_INDEX = the top entry: the string
;; Out: ARGUMENT_INDEX = the top entry: its address
;; Uses: all
;; Errors: 9 (DIM error)
FUNCTION_ADR:
    jsr POP_ABSOLUTE_VALUE          ; the absolute address, in FR0
    jmp RESULT_INTEGER_FR0

;; PADDLE(aexp): a paddle controller's position, 0-228, from its shadow PADDL0-PADDL7.
;;
;; It and STICK, PTRIG and STRIG read a byte from the OS's shadows of the controllers, at the argument's offset from
;; the first: each loads that first shadow's offset from PADDL0 and goes to <READ_CONTROLLER>.
;; In: ARGUMENT_INDEX = the top entry: the paddle (0-7)
;; Out: ARGUMENT_INDEX = the top entry: the position
;; Uses: all
;; Errors: 3 (value error) when the argument is not 0-255
FUNCTION_PADDLE:
    lda #PADDL0 - PADDL0
    beq READ_CONTROLLER             ; always

;; STICK(aexp): a joystick's position, from its shadow STICK0-STICK3: 15 when centred, a bit clear for each
;; direction pushed.
;; In: ARGUMENT_INDEX = the top entry: the joystick (0-3)
;; Out: ARGUMENT_INDEX = the top entry: the position
;; Uses: all
;; Errors: 3 (value error) when the argument is not 0-255
FUNCTION_STICK:
    lda #STICK0 - PADDL0
    bne READ_CONTROLLER             ; always

;; PTRIG(aexp): a paddle's trigger, from its shadow PTRIG0-PTRIG7: 0 when pressed, 1 when not.
;; In: ARGUMENT_INDEX = the top entry: the paddle (0-7)
;; Out: ARGUMENT_INDEX = the top entry: the trigger
;; Uses: all
;; Errors: 3 (value error) when the argument is not 0-255
FUNCTION_PTRIG:
    lda #PTRIG0 - PADDL0
    bne READ_CONTROLLER             ; always

;; STRIG(aexp): a joystick's trigger, from its shadow STRIG0-STRIG3: 0 when pressed, 1 when not.
;; In: ARGUMENT_INDEX = the top entry: the joystick (0-3)
;; Out: ARGUMENT_INDEX = the top entry: the trigger
;; Uses: all
;; Errors: 3 (value error) when the argument is not 0-255
FUNCTION_STRIG:
    lda #STRIG0 - PADDL0

;; Returns the controller shadow at the function's offset from PADDL0 plus its argument.
;;
;; Only an argument above 255 is refused: a larger number than the controllers have reads the shadows after them.
;; In: A = the first shadow's offset from PADDL0, ARGUMENT_INDEX = the top entry: the controller's number
;; Out: ARGUMENT_INDEX = the top entry: the shadow's byte
;; Uses: all
;; Errors: 3 (value error) when the argument is not 0-255
READ_CONTROLLER:
    pha
    jsr POP_UNSIGNED
    lda FR0+1
    bne READ_CONTROLLER_ERROR
    lda FR0
    pla
    clc
    adc FR0
    tax
    lda PADDL0,x
    ldy #$00
    beq RESULT_INTEGER              ; always
READ_CONTROLLER_ERROR:
    jsr VALUE_ERROR                 ; error 3, which doesn't return

;; STR$(aexp): a number as the string PRINT would show.
;;
;; The FP package's FASC writes the number into LBUFF, its last character with bit 7 set; the function clears that
;; bit, counts the length and returns the string where it is. It isn't copied, so the next conversion that uses LBUFF
;; overwrites it: of two STR$ in one expression, both have the second's text.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the string, in LBUFF
;; Uses: all
FUNCTION_STR:
    jsr POP_VALUE
    jsr FASC
    lda INBUFF                      ; the string's address
    sta FR0
    lda INBUFF+1
    sta FR0+1
    ldy #$FF
FUNCTION_STR_FIND_END:
    iny
    lda (INBUFF),y
    bpl FUNCTION_STR_FIND_END
    and #$7F                        ; the last character, without its end bit
    sta (INBUFF),y
    iny
    sty FR0+2                       ; the length
    bne RESULT_STRING               ; always

;; CHR$(aexp): the one-character string of a character code.
;;
;; The character is kept in CHR_BUFFER, in LBUFF, so the next CHR$ or conversion overwrites it: two CHR$ in one
;; comparison compare the second with itself. Only the code's low byte is used, so CHR$(321) is "A".
;; In: ARGUMENT_INDEX = the top entry: the code
;; Out: ARGUMENT_INDEX = the top entry: the string
;; Uses: all
;; Errors: 3 (value error) when the code is negative or above 65535
FUNCTION_CHR:
    jsr POP_VALUE
    jsr CHECKED_FPI
    lda FR0
    sta CHR_BUFFER
    lda #>CHR_BUFFER
    sta FR0+1
    lda #<CHR_BUFFER
    sta FR0
    lda #$01                        ; the length
    sta FR0+2

;; Pushes the string at FR0, its length's low byte in FR0+2, as a function's result.
;;
;; The string is marked DIMensioned and its address absolute, from no variable.
;; In: FR0 = the string's address, FR0+2 = its length (0-255)
;; Out: ARGUMENT_INDEX = the top entry: the string
;; Uses: all
;; Errors: 10 (argument stack overflow)
RESULT_STRING:
    lda #$00
    sta FR0+3                       ; the length's high byte
    sta VALUE_NUMBER
    lda #VALUE_STRING | VALUE_ABSOLUTE | VALUE_DIMENSIONED
    sta VALUE_TYPE
    jmp PUSH_VALUE

;; RND(aexp): a random number from 0 up to 1.
;;
;; Its argument is a dummy, popped and ignored. It reads POKEY's RANDOM twice, for 16 random bits, and divides them
;; by 65536.
;; In: ARGUMENT_INDEX = the top entry: the dummy
;; Out: ARGUMENT_INDEX = the top entry: the random number
;; Uses: all
FUNCTION_RND:
    ldx #<RND_DIVISOR
    ldy #>RND_DIVISOR
    jsr FLD1R
    jsr POP_VALUE
    ldy RANDOM
    sty FR0
    ldy RANDOM
    sty FR0+1
    jsr IFP
    jsr CHECKED_FDIV
    jmp PUSH_VALUE

;; 65536, which <FUNCTION_RND> divides its 16 bits by.
RND_DIVISOR:
    FP_NUMBER FP_POSITIVE, 2, $06, $55, $36, $00, $00

;; ABS(aexp): a number's absolute value, by clearing its sign bit.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the absolute value
;; Uses: all
FUNCTION_ABS:
    jsr POP_VALUE
    lda FR0
    and #$7F                        ; drop FP_SIGN
    sta FR0
    jmp PUSH_VALUE

;; USR(aexp1[,aexp2...]): calls a machine language routine and returns the integer it leaves in FR0.
;;
;; The first argument is the routine's address; the rest are each made an integer (0-65535) and pushed on the 6502's
;; stack, the first argument on top, each high byte above its low byte, with their count above them all. The routine
;; must pull the count and the arguments, put its result's low byte in FR0 (212) and its high byte in FR0+1, and
;; return with RTS.
;; In: ARGUMENT_INDEX = the top entry: the last argument, the others and the address below it, COMMA_COUNT = the
;;   number of arguments after the address
;; Out: ARGUMENT_INDEX = the top entry: the routine's result
;; Uses: all
;; Errors: 3 (value error) when an argument is negative or above 65535
FUNCTION_USR:
    jsr USR_CALL
    jsr IFP
    jmp PUSH_VALUE

;; Pushes USR's arguments on the 6502's stack, their count above them, and jumps to the routine, which returns to the
;; caller of this.
;; In: ARGUMENT_INDEX = the top entry: the last argument, the others and the address below it, COMMA_COUNT = the
;;   number of arguments after the address
;; Out: FR0 = the routine's result
;; Uses: all
;; Errors: 3 (value error) when an argument is negative or above 65535
USR_CALL:
    lda COMMA_COUNT
    sta LOOP_COUNT
USR_CALL_LOOP:
    jsr POP_UNSIGNED                ; the last argument still on the argument stack
    dec LOOP_COUNT
    bmi USR_CALL_JUMP               ; that was the address
    lda FR0
    pha
    lda FR0+1
    pha
    jmp USR_CALL_LOOP
USR_CALL_JUMP:
    lda COMMA_COUNT
    pha
    jmp (FR0)

;; INT(aexp): the greatest integer not above a number, so INT(-3.5) is -4.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the integer
;; Uses: all
;; Errors: 11 (floating point overflow)
FUNCTION_INT:
    jsr POP_VALUE
    jsr FLOOR_FR0
    jmp PUSH_VALUE

;; Makes FR0 the greatest integer not above it.
;;
;; It clears the mantissa's bytes below the units; when the number is negative and a cleared byte was not zero, it
;; adds -1, with <FADD>, or else normalizes it with <FP_NORMALIZE>; it also uses what they use.
;; In: FR0 = the number
;; Out: FR0 = the integer
;; Uses: A, X, Y, FR1
;; Errors: 11 (floating point overflow)
FLOOR_FR0:
    lda FR0
    and #$7F
    sec
    sbc #FP_EXPONENT_BIAS - 1       ; the mantissa's bytes before the point
    bpl FLOOR_FR0_INTEGER_BYTES
    lda #$00                        ; none: below 1
FLOOR_FR0_INTEGER_BYTES:
    tax
    lda #$00                        ; A collects the fraction's bits
    tay
FLOOR_FR0_LOOP:
    cpx #FP_MANTISSA_BYTES
    bcs FLOOR_FR0_NEGATIVE
    ora FR0+1,x
    sty FR0+1,x
    inx
    bne FLOOR_FR0_LOOP              ; always
FLOOR_FR0_NEGATIVE:
    ldx FR0
    bpl FLOOR_FR0_NORMALIZE
    tax                             ; a negative number with a fraction?
    beq FLOOR_FR0_NORMALIZE
    ldx #FR1
    jsr ZF1
    lda #FP_SIGN | FP_EXPONENT_BIAS ; FR1 = -1
    sta FR1
    lda #$01
    sta FR1+1
    jsr CHECKED_FADD
    rts
FLOOR_FR0_NORMALIZE:
    jmp FP_NORMALIZE

.if VERSION = VERSION_A
; Rev. A's math functions test the carry each for itself. LOG and CLOG call the floating point package without
; testing for 0 first, and keep a logarithm's tiny remains, so that LOG(1) and CLOG(1) aren't quite 0.

;; SIN(aexp): the sine of an angle, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the angle
;; Out: ARGUMENT_INDEX = the top entry: the sine
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_SIN:
    jsr POP_VALUE
    jsr SINE
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; COS(aexp): the cosine of an angle, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the angle
;; Out: ARGUMENT_INDEX = the top entry: the cosine
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_COS:
    jsr POP_VALUE
    jsr COSINE
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; ATN(aexp): the arctangent of a number, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the angle
;; Uses: all
;; Errors: 3 (value error)
FUNCTION_ATN:
    jsr POP_VALUE
    jsr ARCTANGENT
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; LOG(aexp): a number's natural logarithm.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the logarithm
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_LOG:
    jsr POP_VALUE
    jsr LOG
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; CLOG(aexp): a number's common logarithm, to base 10.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the logarithm
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_CLOG:
    jsr POP_VALUE
    jsr LOG10
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; EXP(aexp): e to the power of a number.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the power
;; Uses: all
;; Errors: 3 (value error) when the result is too large
FUNCTION_EXP:
    jsr POP_VALUE
    jsr EXP
    bcs MATH_VALUE_ERROR
    bcc MATH_PUSH_RESULT            ; always

;; SQR(aexp): a number's square root.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the root
;; Uses: all
;; Errors: 3 (value error) when the number is negative
FUNCTION_SQR:
    jsr POP_VALUE
    jsr SQUARE_ROOT
    bcs MATH_VALUE_ERROR

;; Pushes FR0 as a function's result.
;; Out: ARGUMENT_INDEX = the top entry: the result
;; Uses: all
MATH_PUSH_RESULT:
    jmp PUSH_VALUE

;; Raises error 3 for a function or ^ that failed.
;; Errors: 3 (value error)
MATH_VALUE_ERROR:
    jsr VALUE_ERROR                 ; error 3, which doesn't return

;; ^: raises a number to a power, as rev. A does.
;;
;; A positive power of 0 is 0, 0^0 is 1, and a negative power of 0 an error. Otherwise the result is
;; 10^(power * CLOG(ABS(number))), made negative when the number is negative and the power an odd integer. A negative
;; number to a power that isn't an integer is an error, and so is one to a power below 1 in size, 0 among them, so
;; (-2)^0 is an error. The result is not rounded, so an integer to an integer power may come out a little short:
;; rev. B makes such a result an integer. A power of 10^10 or more is odd or even by its mantissa's last digit.
;; In: ARGUMENT_INDEX = the top entry: the power, the number below it
;; Out: ARGUMENT_INDEX = the top entry: the result
;; Uses: all
;; Errors: 3 (value error) for a negative power of 0, a negative number to a power that isn't an integer at least 1
;;   in size, or when LOG10 fails; 11 (floating point overflow) when the result is too large
OPERATOR_POWER:
    jsr POP_TWO_VALUES              ; FR0 = the number, FR1 = the power
    lda FR0
    bne POWER_NONZERO
    lda FR1                         ; 0 to a power
    beq POWER_ONE
    bpl MATH_PUSH_RESULT            ; 0 to a positive power: 0
    bmi MATH_VALUE_ERROR            ; always: 0 to a negative power
POWER_ONE:
    jmp PUSH_ONE
POWER_NONZERO:
    bpl POWER_POSITIVE_RESULT
    and #$7F                        ; a negative number: take its absolute value
    sta FR0
    lda FR1                         ; the power's bytes before the point
    and #$7F
    sec
    sbc #FP_EXPONENT_BIAS
    bmi MATH_VALUE_ERROR            ; below 1 in size
    ldx #FP_SIZE
    cmp #FP_SIZE - 1
    bcc POWER_FRACTION_BYTES
    ldy #$01                        ; all of the mantissa: no fraction to test
    bne POWER_TEST_FRACTION         ; always
POWER_FRACTION_BYTES:
    sta ZTEMP1                      ; Y = the bytes after the point, plus 1
    sec
    lda #FP_SIZE - 1
    sbc ZTEMP1
    tay
POWER_TEST_FRACTION:
    dex                             ; from the mantissa's last byte down
    dey
    beq POWER_ODD_OR_EVEN
    lda FR1,x
    bne MATH_VALUE_ERROR            ; a fraction
    beq POWER_TEST_FRACTION         ; always
POWER_ODD_OR_EVEN:
    ldy #FP_SIGN                    ; the last byte before the point: odd makes the result negative
    lda FR1,x
    lsr A
    bcs POWER_SAVE_SIGN
POWER_POSITIVE_RESULT:
    ldy #$00
POWER_SAVE_SIGN:
    tya
    pha                             ; the result's sign
    ldx #FP_SIZE - 1                ; keep the power through LOG10
POWER_PUSH_POWER:
    lda FR1,x
    pha
    dex
    bpl POWER_PUSH_POWER
    jsr LOG10
    bcs MATH_VALUE_ERROR
    ldx #$00
    ldy #FP_SIZE - 1
POWER_PULL_POWER:
    pla
    sta FR1,x
    inx
    dey
    bpl POWER_PULL_POWER
    jsr CHECKED_FMUL                ; the power times the logarithm
    jsr EXP10
    bcs POWER_OVERFLOW
    pla                             ; the sign
    bpl MATH_PUSH_RESULT
    ora FR0
    sta FR0
    bne MATH_PUSH_RESULT            ; always
POWER_OVERFLOW:
    jsr FLOATING_POINT_OVERFLOW_ERROR ; error 11, which doesn't return
.else
;; SIN(aexp): the sine of an angle, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the angle
;; Out: ARGUMENT_INDEX = the top entry: the sine
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_SIN:
    jsr POP_VALUE
    jsr SINE
    jmp MATH_RESULT

;; COS(aexp): the cosine of an angle, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the angle
;; Out: ARGUMENT_INDEX = the top entry: the cosine
;; Uses: all
;; Errors: 3 (value error) when the FP package fails
FUNCTION_COS:
    jsr POP_VALUE
    jsr COSINE
    jmp MATH_RESULT

;; ATN(aexp): the arctangent of a number, in radians or, after DEG, degrees.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the angle
;; Uses: all
;; Errors: 3 (value error)
FUNCTION_ATN:
    jsr POP_VALUE
    jsr ARCTANGENT
    jmp MATH_RESULT

;; LOG(aexp): a number's natural logarithm.
;;
;; A small positive result, from 1E-10 up to 8E-10, is taken for a rounding error's remains and made 0, so that
;; LOG(1) is 0.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the logarithm
;; Uses: all
;; Errors: 3 (value error) when the number is 0 or negative
FUNCTION_LOG:
    jsr POP_VALUE
    lda FR0
    beq MATH_VALUE_ERROR
    jsr LOG

;; Pushes a logarithm's result, or raises error 3 when the FP package failed.
;;
;; A positive result with the exponent byte FUNCTIONS_LOG_TINY and a first mantissa byte below 8, from 1E-10 up to
;; 8E-10, is taken for a rounding error's remains and becomes 0; a smaller one is kept.
;; In: FR0 = the logarithm, carry = set when the FP package failed
;; Out: ARGUMENT_INDEX = the top entry: the logarithm
;; Uses: all
;; Errors: 3 (value error) when carry is set
LOG_RESULT:
    bcs MATH_VALUE_ERROR
    lda FR0
    eor #FUNCTIONS_LOG_TINY
    bne MATH_PUSH_RESULT
    lda FR0+1
    and #$F8
    bne MATH_PUSH_RESULT
    sta FR0                         ; 0
    beq MATH_PUSH_RESULT            ; always

;; CLOG(aexp): a number's common logarithm, to base 10.
;;
;; A small positive result, from 1E-10 up to 8E-10, is taken for a rounding error's remains and made 0, so that
;; CLOG(1) is 0.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the logarithm
;; Uses: all
;; Errors: 3 (value error) when the number is 0 or negative
FUNCTION_CLOG:
    jsr POP_VALUE
    lda FR0
    beq MATH_VALUE_ERROR
    jsr LOG10
    jmp LOG_RESULT

;; EXP(aexp): e to the power of a number.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the power
;; Uses: all
;; Errors: 3 (value error) when the result is too large
FUNCTION_EXP:
    jsr POP_VALUE
    jsr EXP
    jmp MATH_RESULT

;; SQR(aexp): a number's square root.
;; In: ARGUMENT_INDEX = the top entry: the number
;; Out: ARGUMENT_INDEX = the top entry: the root
;; Uses: all
;; Errors: 3 (value error) when the number is negative
FUNCTION_SQR:
    jsr POP_VALUE
    jsr SQUARE_ROOT

;; Pushes a function's result, or raises error 3 when the routine that worked it out failed.
;; In: FR0 = the result, carry = set when it failed
;; Out: ARGUMENT_INDEX = the top entry: the result
;; Uses: all
;; Errors: 3 (value error) when carry is set
;; Entry: MATH_VALUE_ERROR = raises error 3
MATH_RESULT:
    bcc MATH_PUSH_RESULT
MATH_VALUE_ERROR:
    jsr VALUE_ERROR                 ; error 3, which doesn't return

;; ^: raises a number to a power.
;;
;; Any power of 0 but a negative one is 0, and anything to the power 0 is 1, 0^0 among them. Otherwise the result is
;; 10^(power * CLOG(ABS(number))), made negative when the number is negative and the power an odd integer. A
;; negative number to a power that isn't an integer is an error. When an integer is raised to a positive integer
;; power, the result is made an integer by raising it to the next one up if it has a fraction: the logarithms leave
;; it a little short, but the rounding is always up. A power of 10^10 or more counts as even.
;; In: ARGUMENT_INDEX = the top entry: the power, the number below it
;; Out: ARGUMENT_INDEX = the top entry: the result
;; Uses: all
;; Errors: 3 (value error) for a negative power of 0 or a negative number to a fractional power, 11 (floating point
;;   overflow) when the result is too large
OPERATOR_POWER:
    jsr POP_TWO_VALUES              ; FR0 = the number, FR1 = the power
    lda FR1
    beq POWER_ONE
    rol A                           ; carry = the power is negative
    ldy FR0
    bne POWER_NONZERO
    bcs MATH_VALUE_ERROR            ; 0 to a negative power
MATH_PUSH_RESULT:
    jmp PUSH_VALUE
POWER_ONE:
    jmp PUSH_ONE
POWER_NONZERO:
    ldx #FR0
    jsr NUMBER_HAS_FRACTION         ; carry = set when the number is an integer
    ror A                           ; to bit 7
    pha
    ldx #FR1
    jsr NUMBER_HAS_FRACTION         ; carry = set when the power is an integer; ZTEMP4 = its power of 100
    tya                             ; the number's exponent byte
    bpl POWER_POSITIVE_NUMBER
    and #$7F                        ; a negative number: take its absolute value
    sta FR0
    bcs POWER_INTEGER_POWER
    pla
    bcc MATH_VALUE_ERROR            ; always: a fractional power of a negative number
POWER_INTEGER_POWER:
    lda FR1
    bpl POWER_ODD_OR_EVEN           ; carry still set for a positive power
    clc
POWER_ODD_OR_EVEN:
    php                             ; carry = the power is a positive integer
    ldx ZTEMP4                      ; the power's last byte before the point
    cpx #FP_MANTISSA_BYTES
    bcs POWER_POSITIVE_RESULT       ; none in the mantissa: taken as even
    lda FR1+1,x
    ror A                           ; carry = its units digit is odd
    bcc POWER_POSITIVE_RESULT
    lda #FP_SIGN
    bne POWER_SAVE_SIGN             ; always
POWER_POSITIVE_NUMBER:
    lda FR1
    bpl POWER_SAVE_ROUNDING         ; carry still says whether the power is an integer
    clc
POWER_SAVE_ROUNDING:
    php                             ; carry = the power is a positive integer
POWER_POSITIVE_RESULT:
    lda #$00
POWER_SAVE_SIGN:
    pha                             ; the result's sign
    ldx #FP_SIZE - 1                ; keep the power through LOG10
POWER_PUSH_POWER:
    lda FR1,x
    pha
    dex
    bpl POWER_PUSH_POWER
    jsr LOG10
    ldx #$00
    ldy #FP_SIZE - 1
POWER_PULL_POWER:
    pla
    sta FR1,x
    inx
    dey
    bpl POWER_PULL_POWER
    jsr CHECKED_FMUL                ; the power times the logarithm
    jsr EXP10
    bcs POWER_OVERFLOW
    pla                             ; the sign
    ora FR0
    sta FR0
    plp                             ; carry = the power is a positive integer
    pla                             ; negative = the number is an integer
    bpl MATH_PUSH_RESULT
    bcc MATH_PUSH_RESULT
    ldx #FR0                        ; an integer to a positive integer power: does the result have a fraction?
    jsr NUMBER_HAS_FRACTION
    bcs MATH_PUSH_RESULT
    lda FR0
    sec
    and #$7F
    sbc #FP_EXPONENT_BIAS - 1       ; the mantissa's bytes before the point
    cmp #FP_SIZE
    bcs POWER_RESULT
    tax                             ; the last of them
    tay
    sed
    sec                             ; add 1 to the integer part
POWER_ROUND_UP:
    lda FR0,x
    adc #$00
    sta FR0,x
    dex
    bne POWER_ROUND_UP
    cld
    bcc POWER_CLEAR_FRACTION
    inc FR0                         ; carried out of the top: one more power of 100, and the mantissa 01 00 00...
    inc FR0+1
POWER_CLEAR_FRACTION:
    iny                             ; clear the bytes after the point
    cpy #FP_SIZE
    bcs POWER_RESULT
    stx FR0,y                       ; X = 0
    bcc POWER_CLEAR_FRACTION        ; always
POWER_RESULT:
    jmp PUSH_VALUE
POWER_OVERFLOW:
    jsr FLOATING_POINT_OVERFLOW_ERROR ; error 11, which doesn't return
.endif
