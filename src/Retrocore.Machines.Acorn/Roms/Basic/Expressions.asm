;; The expression evaluator, its operators, and converting numbers to strings ($9B1D-$A07A).
;;
;; An expression is evaluated by one routine for each level of precedence, each calling the one below it for its
;; operands, from the loosest to the tightest binding:
;;
;; - <EVALUATE_EXPRESSION>: OR and EOR;
;; - <EVALUATE_AND>: AND;
;; - <EVALUATE_RELATION>: =, <>, <, <=, > and >=, which give TRUE (-1) or FALSE (0);
;; - <EVALUATE_SUM>: + and -, and + joining strings;
;; - <EVALUATE_TERM>: *, /, MOD and DIV;
;; - <EVALUATE_POWER>: ^;
;; - EVALUATE_FACTOR: a number, a variable, a function, a string, a unary operator or a bracketed expression.
;;
;; Each level returns its value in the accumulators, IntA, FPA or StrA, with its type in A, and the first character
;; after it, spaces skipped, in X, with <PTR_B_OFFSET> just past that character. The levels below the top leave the
;; flags from their last test of X (<EVALUATE_POWER> returns straight after a CPX), not from the type. Only the top,
;; <EVALUATE_EXPRESSION>, sets the flags from the type (zero for a string, negative for a real) with a TAY, keeps it
;; in EXPRESSION_TYPE, and steps <PTR_B_OFFSET> back onto X's character.
;;
;; A level's loop looks at X for one of its operators; while it finds one it pushes the left operand on BASIC's
;; stack, evaluates the right with the level below and combines the two. The operators of a level work from left to
;; right, and only one relation is taken. Integers are kept as integers where they can be, and the operation is done
;; in reals as soon as either operand is real.
;;
;; The second half of the file converts a number to the characters PRINT and STR$ show, in StrA:
;; <NUMBER_TO_STRING>, with the formats @% selects, and <HEX_TO_STRING>.

; Error numbers.
ERROR_STRING_TOO_LONG = $13         ;; error 19, "String too long": a string of more than 255 characters

; The parts of @% that <NUMBER_TO_STRING> reads; its low byte, the field width, is PRINT's.
AT_PERCENT_DIGITS = AT_PERCENT + 1  ;; @%'s second byte: the number of digits, or of decimal places in fixed format
AT_PERCENT_FORMAT = AT_PERCENT + 2  ;; @%'s third byte: the format, one of the NUMBER_FORMAT_ values

; The formats @% selects.
NUMBER_FORMAT_GENERAL = 0           ;; general format: only the digits needed, E notation if very large or small
NUMBER_FORMAT_EXPONENT = 1          ;; exponent format: always E notation, with a set number of digits
NUMBER_FORMAT_FIXED = 2             ;; fixed format: a set number of decimal places
MAXIMUM_DIGITS = 10                 ;; the most digits a number is shown with, and the number when @% asks for none

; The work bytes <NUMBER_TO_STRING> gives a purpose of its own.
FORMAT_TYPE = WORK                  ;; the format being used, one of the NUMBER_FORMAT_ values
FORMAT_DIGITS = WORK + 1            ;; the number of significant digits still to put in the string

;; The number of digits @% asked for, kept while <FORMAT_DIGITS> is worked out; later, the number of digits still to
;; come before the decimal point.
FORMAT_POINT = SERIES_POINTER + 1

FORMAT_EXPONENT = FP_WORK + 6       ;; the power of ten the number is scaled by: its exponent in E notation

; The work bytes the 16-bit integer multiply gives a purpose of their own.
MULTIPLY_FACTOR = WORK + 2          ;; the multiplier, two bytes, shifted out a bit at a time
MULTIPLY_PRODUCT = FP_B_EXPONENT    ;; the product, four bytes, low byte first; <DIVIDE_REMAINDER> is the same bytes

; Exponents of real numbers that <NUMBER_TO_STRING> compares with; a real's exponent is &80 more than the power of two
; that its mantissa, a fraction from 0.5 up to 1, is multiplied by.
REAL_EXPONENT_ONE = $81             ;; the exponent of numbers from 1 up to 2
REAL_EXPONENT_FIVE = $83            ;; the exponent of numbers from 4 up to 8, 5 among them
REAL_EXPONENT_TEN = $84             ;; the exponent of numbers from 8 up to 16, 10 among them
REAL_MANTISSA_TEN = $A0             ;; the top byte of 10's mantissa (with REAL_EXPONENT_TEN), and of 5's
REAL_EXPONENT_POWER_LIMIT = $87     ;; the exponent of numbers from 64 up to 128: ^ takes no integer part from these

;; Copies PTRA to PTRB, then evaluates the expression there.
;;
;; It falls into <EVALUATE_EXPRESSION>.
;; In: PTR_A, PTR_A_OFFSET = the expression
;; Inherit: <EVALUATE_EXPRESSION> Out
;; Uses: all
EVALUATE_EXPRESSION_A:
    lda PTR_A
    sta PTR_B
    lda PTR_A+1
    sta PTR_B+1
    lda PTR_A_OFFSET
    sta PTR_B_OFFSET

;; Evaluates the expression at PTRB, of any type: the expression evaluator's top level, for OR and EOR.
;;
;; OR and EOR take integers, real operands being made integers, and work on all 32 bits. Every expression, of any
;; type, passes through this level.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, <TYPE_STRING>, <TYPE_INTEGER> or <TYPE_REAL>, with the value in StrA, IntA or FPA
;;   zero = set for a string
;;   negative = set for a real
;;   EXPRESSION_TYPE = the type
;;   X = the first character after the expression, spaces skipped
;;   PTR_B_OFFSET = that character
;; Uses: all
;; Errors: Type mismatch, and the errors of the operators and functions in the expression
EVALUATE_EXPRESSION:
    jsr EVALUATE_AND
EVALUATE_EXPRESSION_LOOP:
    cpx #TOKEN_OR
    beq OR_OPERATOR
    cpx #TOKEN_EOR
    beq EOR_OPERATOR
    dec PTR_B_OFFSET                ; back to the character in X
    tay
    sta EXPRESSION_TYPE
    rts

;; OR: the bitwise OR of two integers; part of <EVALUATE_EXPRESSION>.
;;
;; It evaluates the right operand at PTRB, combines it with the left, in the accumulators, and goes back to the loop.
;; Entry: EVALUATE_EXPRESSION_NEXT = drops the left operand from BASIC's stack and goes back to the loop with an
;;   integer
OR_OPERATOR:
    jsr PUSH_THEN_EVALUATE_AND
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the right operand as an integer
    ldy #$03
OR_OPERATOR_LOOP:
    lda (BASIC_STACK),y
    ora a:INT_A,y
    sta a:INT_A,y
    dey
    bpl OR_OPERATOR_LOOP
EVALUATE_EXPRESSION_NEXT:
    jsr DROP_INTEGER                       ; drop the left operand
    lda #TYPE_INTEGER
    bne EVALUATE_EXPRESSION_LOOP    ; always taken

;; EOR: the bitwise exclusive OR of two integers; part of <EVALUATE_EXPRESSION>.
EOR_OPERATOR:
    jsr PUSH_THEN_EVALUATE_AND
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the right operand as an integer
    ldy #$03
EOR_OPERATOR_LOOP:
    lda (BASIC_STACK),y
    eor a:INT_A,y
    sta a:INT_A,y
    dey
    bpl EOR_OPERATOR_LOOP
    bmi EVALUATE_EXPRESSION_NEXT    ; always taken

;; Makes the value in the accumulators an integer and pushes it on BASIC's stack, then evaluates the AND level at
;; PTRB, for the right operand of OR or EOR.
;;
;; It falls into <EVALUATE_AND>.
;; In: A = the value's type, in the accumulators
;; Inherit: <EVALUATE_AND> Out
;; Uses: all
;; Errors: Type mismatch when the value is a string
PUSH_THEN_EVALUATE_AND:
    tay
    jsr CONVERT_A_TO_INTEGER
    jsr PUSH_INTEGER

;; Evaluates the AND level at PTRB: relations joined by AND, the bitwise AND of two integers.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, with the value in the accumulators
;;   X = the first character after it, spaces skipped
;;   PTR_B_OFFSET = just past that character
;; Uses: all
EVALUATE_AND:
    jsr EVALUATE_RELATION
EVALUATE_AND_LOOP:
    cpx #TOKEN_AND
    beq AND_OPERATOR
    rts
AND_OPERATOR:
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the left operand as an integer
    jsr PUSH_INTEGER
    jsr EVALUATE_RELATION
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the right operand as an integer
    ldy #$03
AND_OPERATOR_LOOP:
    lda (BASIC_STACK),y
    and a:INT_A,y
    sta a:INT_A,y
    dey
    bpl AND_OPERATOR_LOOP
    jsr DROP_INTEGER                       ; drop the left operand
    lda #TYPE_INTEGER
    bne EVALUATE_AND_LOOP           ; always taken

;; Evaluates the relation level at PTRB: a sum, or two sums compared by =, <>, <, <=, > or >=.
;;
;; A comparison gives the integer TRUE (-1) or FALSE (0). <COMPARE_VALUES> compares the two, and each operator turns
;; its flags into the answer. A relation is not followed by another: the next operator is returned in X.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, with the value in the accumulators
;;   X = the first character after it, spaces skipped
;;   PTR_B_OFFSET = just past that character
;; Uses: all
;; Errors: Type mismatch when a string is compared with a number
EVALUATE_RELATION:
    jsr EVALUATE_SUM
    cpx #'>'+1
    bcs EVALUATE_RELATION_DONE
    cpx #'<'
    bcs RELATION_OPERATOR           ; "<", "=" or ">"
EVALUATE_RELATION_DONE:
    rts
RELATION_OPERATOR:
    beq LESS_THAN_OPERATOR
    cpx #'>'
    beq GREATER_THAN_OPERATOR
    tax                             ; "=": TRUE when equal
    jsr COMPARE_VALUES
    bne RELATION_FALSE
RELATION_TRUE:
    dey                             ; Y = &FF, from the 0 COMPARE_VALUES leaves
RELATION_FALSE:
    sty INT_A                       ; Y = 0 when entered here
    sty INT_A+1
    sty INT_A+2
    sty INT_A+3
    lda #TYPE_INTEGER
    rts
LESS_THAN_OPERATOR:
    tax
    ldy PTR_B_OFFSET
    lda (PTR_B),y
    cmp #'='
    beq LESS_OR_EQUAL_OPERATOR
    cmp #'>'
    beq NOT_EQUAL_OPERATOR
    jsr COMPARE_VALUES_X            ; "<": TRUE when the left is the smaller
    bcc RELATION_TRUE
    bcs RELATION_FALSE              ; always taken
LESS_OR_EQUAL_OPERATOR:
    inc PTR_B_OFFSET
    jsr COMPARE_VALUES_X
    beq RELATION_TRUE
    bcc RELATION_TRUE
    bcs RELATION_FALSE              ; always taken
NOT_EQUAL_OPERATOR:
    inc PTR_B_OFFSET
    jsr COMPARE_VALUES_X
    bne RELATION_TRUE
    beq RELATION_FALSE              ; always taken
GREATER_THAN_OPERATOR:
    tax
    ldy PTR_B_OFFSET
    lda (PTR_B),y
    cmp #'='
    beq GREATER_OR_EQUAL_OPERATOR
    jsr COMPARE_VALUES_X            ; ">": TRUE when the left is the greater
    beq RELATION_FALSE
    bcs RELATION_TRUE
    bcc RELATION_FALSE              ; always taken
GREATER_OR_EQUAL_OPERATOR:
    inc PTR_B_OFFSET
    jsr COMPARE_VALUES_X
    bcs RELATION_TRUE
    bcc RELATION_FALSE              ; always taken

;; Raises error 19, "String too long": a string would have more than 255 characters.
STRING_TOO_LONG_ERROR:
    brk
    .byte ERROR_STRING_TOO_LONG
    .byte "String too long", 0

;; +, with strings: joins the left string, in StrA, to the next power at PTRB; part of <EVALUATE_SUM>.
;;
;; The left string is pushed on BASIC's stack while the right is evaluated into StrA. The right string is then moved
;; up in StrA to make room, and the left one copied back from the stack in front of it.
;; Errors: Type mismatch when the right operand is a number, String too long
CONCATENATE:
    jsr PUSH_STRING
    jsr EVALUATE_POWER
    tay
    bne SUM_TYPE_MISMATCH
    clc
    stx WORK                        ; keep the next operator
    ldy #$00
    lda (BASIC_STACK),y             ; the left string's length
    adc STRING_LENGTH
    bcs STRING_TOO_LONG_ERROR
    tax
    pha
    ldy STRING_LENGTH
CONCATENATE_MOVE:
    lda STRING_BUFFER-1,y           ; move the right string up, last character first
    sta STRING_BUFFER-1,x
    dex
    dey
    bne CONCATENATE_MOVE
    jsr POP_STRING                  ; the left string to the start of StrA; Y = 0
    pla
    sta STRING_LENGTH
    ldx WORK
    tya                             ; A = TYPE_STRING
    beq EVALUATE_SUM_LOOP           ; always taken

;; Evaluates the sum level at PTRB: terms joined by + and -, or strings joined by +.
;;
;; Integers are added and subtracted in 32 bits, with no check for overflow. When either operand is real both are
;; made real.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, with the value in the accumulators
;;   X = the first character after it, spaces skipped
;;   PTR_B_OFFSET = just past that character
;; Uses: all
;; Errors: Type mismatch when a string is added to a number or subtracted, String too long
EVALUATE_SUM:
    jsr EVALUATE_TERM
EVALUATE_SUM_LOOP:
    cpx #'+'
    beq PLUS_OPERATOR
    cpx #'-'
    beq MINUS_OPERATOR
    rts
PLUS_OPERATOR:
    tay
    beq CONCATENATE
    bmi ADD_REALS
    jsr PUSH_THEN_EVALUATE_TERM
    tay
    beq SUM_TYPE_MISMATCH
    bmi ADD_INTEGER_AND_REAL
    ldy #$00                        ; the integer on the stack plus IntA
    clc
    lda (BASIC_STACK),y
    adc INT_A
    sta INT_A
    iny
    lda (BASIC_STACK),y
    adc INT_A+1
    sta INT_A+1
    iny
    lda (BASIC_STACK),y
    adc INT_A+2
    sta INT_A+2
    iny
    lda (BASIC_STACK),y
    adc INT_A+3
EVALUATE_SUM_INTEGER:
    sta INT_A+3
    clc                             ; drop the left operand
    lda BASIC_STACK
    adc #$04
    sta BASIC_STACK
    lda #TYPE_INTEGER
    bcc EVALUATE_SUM_LOOP
    inc BASIC_STACK+1
    bcs EVALUATE_SUM_LOOP           ; always taken

;; Raises Type mismatch for <EVALUATE_SUM>, from within reach of its branches.
SUM_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; +, with a real left operand: adds the next term at PTRB to it; part of <EVALUATE_SUM>.
;; Entry:
;;   ADD_REALS_POP = adds the real on BASIC's stack to FPA
;;   EVALUATE_SUM_REAL = goes back to the sum's loop with a real, the next operator in EXPRESSION_TYPE
ADD_REALS:
    jsr PUSH_REAL
    jsr EVALUATE_TERM
    tay
    beq SUM_TYPE_MISMATCH
    stx EXPRESSION_TYPE             ; keep the next operator
    bmi ADD_REALS_POP
    jsr INTEGER_TO_REAL
ADD_REALS_POP:
    jsr POP_REAL_POINTER
    jsr ADD_TO_FP_A                       ; FPA = the left operand + FPA
EVALUATE_SUM_REAL:
    ldx EXPRESSION_TYPE
    lda #TYPE_REAL
    bne EVALUATE_SUM_LOOP           ; always taken

;; +, with an integer left operand on BASIC's stack and a real right one in FPA; part of <EVALUATE_SUM>.
ADD_INTEGER_AND_REAL:
    stx EXPRESSION_TYPE             ; keep the next operator
    jsr POP_INTEGER
    jsr PUSH_REAL
    jsr INTEGER_TO_REAL
    jmp ADD_REALS_POP

;; -: subtracts the next term at PTRB from the left operand; part of <EVALUATE_SUM>.
MINUS_OPERATOR:
    tay
    beq SUM_TYPE_MISMATCH
    bmi SUBTRACT_REALS
    jsr PUSH_THEN_EVALUATE_TERM
    tay
    beq SUM_TYPE_MISMATCH
    bmi SUBTRACT_REAL_FROM_INTEGER
    sec                             ; the integer on the stack less IntA
    ldy #$00
    lda (BASIC_STACK),y
    sbc INT_A
    sta INT_A
    iny
    lda (BASIC_STACK),y
    sbc INT_A+1
    sta INT_A+1
    iny
    lda (BASIC_STACK),y
    sbc INT_A+2
    sta INT_A+2
    iny
    lda (BASIC_STACK),y
    sbc INT_A+3
    jmp EVALUATE_SUM_INTEGER

;; -, with a real left operand: subtracts the next term at PTRB from it; part of <EVALUATE_SUM>.
SUBTRACT_REALS:
    jsr PUSH_REAL
    jsr EVALUATE_TERM
    tay
    beq SUM_TYPE_MISMATCH
    stx EXPRESSION_TYPE             ; keep the next operator
    bmi SUBTRACT_REALS_POP
    jsr INTEGER_TO_REAL
SUBTRACT_REALS_POP:
    jsr POP_REAL_POINTER
    jsr SUBTRACT_FP_A_FROM                       ; FPA = the left operand - FPA
    jmp EVALUATE_SUM_REAL

;; -, with an integer left operand on BASIC's stack and a real right one in FPA; part of <EVALUATE_SUM>.
SUBTRACT_REAL_FROM_INTEGER:
    stx EXPRESSION_TYPE             ; keep the next operator
    jsr POP_INTEGER
    jsr PUSH_REAL
    jsr INTEGER_TO_REAL
    jsr POP_REAL_POINTER
    jsr SUBTRACT_FROM_FP_A                       ; FPA = FPA - the right operand
    jmp EVALUATE_SUM_REAL

;; *, as real numbers: the parts of <MULTIPLY_OPERATOR> for an operand that is real or too large to multiply as an
;; integer.
;;
;; This entry has an integer left operand on BASIC's stack and an integer right one in IntA. The others:
;; Entry:
;;   MULTIPLY_INTEGER_BY_REAL = an integer left operand on BASIC's stack, a real right one in FPA
;;   MULTIPLY_LEFT_TO_REAL = an integer left operand in IntA, not yet made real; evaluates the right
;;   MULTIPLY_REALS = a real left operand in FPA; evaluates the right
;;   MULTIPLY_REALS_POP = multiplies FPA by the real on BASIC's stack, the next operator in EXPRESSION_TYPE
MULTIPLY_RIGHT_TO_REAL:
    jsr INTEGER_TO_REAL
MULTIPLY_INTEGER_BY_REAL:
    jsr POP_INTEGER
    jsr PUSH_REAL
    jsr INTEGER_TO_REAL
    jmp MULTIPLY_REALS_POP
MULTIPLY_LEFT_TO_REAL:
    jsr INTEGER_TO_REAL
MULTIPLY_REALS:
    jsr PUSH_REAL
    jsr EVALUATE_POWER
    stx EXPRESSION_TYPE             ; keep the next operator
    tay
    jsr CONVERT_A_TO_REAL                       ; the right operand as a real
MULTIPLY_REALS_POP:
    jsr POP_REAL_POINTER
    jsr MULTIPLY_FP_A                       ; FPA = FPA * the left operand
    lda #TYPE_REAL
    ldx EXPRESSION_TYPE
    jmp EVALUATE_TERM_LOOP

;; Raises Type mismatch for <MULTIPLY_OPERATOR>, from within reach of its branches.
MULTIPLY_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; *: multiplies the left operand by the next power at PTRB; part of <EVALUATE_TERM>.
;;
;; Two integers that both fit in 16 bits, signed, are multiplied as integers: their magnitudes by shifting and adding,
;; to a 32-bit product, then the sign is applied. Anything else is multiplied as real numbers, so a product of larger
;; integers is real.
MULTIPLY_OPERATOR:
    tay
    beq MULTIPLY_TYPE_MISMATCH
    bmi MULTIPLY_REALS
    lda INT_A+3                     ; is the left operand a 16-bit signed number? its top two bytes are the same,
    cmp INT_A+2
    bne MULTIPLY_LEFT_TO_REAL
    tay
    beq MULTIPLY_LEFT_SIGN
    cmp #$FF                        ; &00 or &FF,
    bne MULTIPLY_LEFT_TO_REAL
MULTIPLY_LEFT_SIGN:
    eor INT_A+1                     ; and the sign of the low 16 bits
    bmi MULTIPLY_LEFT_TO_REAL
    jsr PUSH_THEN_EVALUATE_POWER
    stx EXPRESSION_TYPE             ; keep the next operator
    tay
    beq MULTIPLY_TYPE_MISMATCH
    bmi MULTIPLY_INTEGER_BY_REAL
    lda INT_A+3                     ; the same test for the right operand
    cmp INT_A+2
    bne MULTIPLY_RIGHT_TO_REAL
    tay
    beq MULTIPLY_RIGHT_SIGN
    cmp #$FF
    bne MULTIPLY_RIGHT_TO_REAL
MULTIPLY_RIGHT_SIGN:
    eor INT_A+1
    bmi MULTIPLY_RIGHT_TO_REAL
    lda INT_A+3
    pha
    jsr ABS_INT_A                       ; the right operand's magnitude
    ldx #MULTIPLY_FACTOR
    jsr STORE_INT_A                 ; is the multiplier
    jsr POP_INTEGER
    pla
    eor INT_A+3
    sta RESULT_SIGN
    jsr ABS_INT_A                       ; the left operand's magnitude is the multiplicand, in IntA
    ldy #$00                        ; the product, low byte first, in Y, X, MULTIPLY_PRODUCT+2 and MULTIPLY_PRODUCT+3
    ldx #$00
    sty MULTIPLY_PRODUCT+2
    sty MULTIPLY_PRODUCT+3
MULTIPLY_LOOP:
    lsr MULTIPLY_FACTOR+1
    ror MULTIPLY_FACTOR
    bcc MULTIPLY_SHIFT
    clc                             ; the multiplier's bit is set: add the multiplicand
    tya
    adc INT_A
    tay
    txa
    adc INT_A+1
    tax
    lda MULTIPLY_PRODUCT+2
    adc INT_A+2
    sta MULTIPLY_PRODUCT+2
    lda MULTIPLY_PRODUCT+3
    adc INT_A+3
    sta MULTIPLY_PRODUCT+3
MULTIPLY_SHIFT:
    asl INT_A
    rol INT_A+1
    rol INT_A+2
    rol INT_A+3
    lda MULTIPLY_FACTOR
    ora MULTIPLY_FACTOR+1
    bne MULTIPLY_LOOP
    sty MULTIPLY_PRODUCT
    stx MULTIPLY_PRODUCT+1
    lda RESULT_SIGN
    php

;; Loads a 32-bit integer result from zero page into IntA, makes it negative when the flags on the stack say so,
;; and goes back to <EVALUATE_TERM>'s loop; the end of *, MOD and DIV.
;; In: the flags pushed with negative set for a negative result, EXPRESSION_TYPE = the next operator
;; Entry: LOAD_SIGNED_RESULT_X = loads the result at X instead of <MULTIPLY_PRODUCT>
LOAD_SIGNED_RESULT:
    ldx #MULTIPLY_PRODUCT                    ; also <DIVIDE_REMAINDER>, for MOD
LOAD_SIGNED_RESULT_X:
    jsr LOAD_INT_A
    plp
    bpl LOAD_SIGNED_RESULT_DONE
    jsr NEGATE_INT_A
LOAD_SIGNED_RESULT_DONE:
    ldx EXPRESSION_TYPE
    jmp EVALUATE_TERM_LOOP

;; Joins <MULTIPLY_OPERATOR>, from within reach of <EVALUATE_TERM>'s branch.
EVALUATE_TERM_MULTIPLY:
    jmp MULTIPLY_OPERATOR

;; Pushes the integer in IntA on BASIC's stack, then evaluates the term level at PTRB, for the right operand of + or
;; -.
;;
;; It falls into <EVALUATE_TERM>.
;; In: INT_A = the left operand
;; Inherit: <EVALUATE_TERM> Out
;; Uses: all
PUSH_THEN_EVALUATE_TERM:
    jsr PUSH_INTEGER

;; Evaluates the term level at PTRB: powers joined by *, /, MOD and DIV.
;;
;; / always gives a real. MOD and DIV make both operands integers and divide them with <DIVIDE_INTEGERS>: DIV gives
;; the quotient, rounded towards zero, and MOD the remainder, which has the sign of the left operand.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, with the value in the accumulators
;;   X = the first character after it, spaces skipped
;;   PTR_B_OFFSET = just past that character
;; Uses: all
;; Errors: Type mismatch when an operand is a string, Division by zero, and the floating point errors
;; Entry: EVALUATE_TERM_LOOP = looks at the operator in X, with the value so far in the accumulators and its type in A
EVALUATE_TERM:
    jsr EVALUATE_POWER
EVALUATE_TERM_LOOP:
    cpx #'*'
    beq EVALUATE_TERM_MULTIPLY
    cpx #'/'
    beq DIVIDE_OPERATOR
    cpx #TOKEN_MOD
    beq MOD_OPERATOR
    cpx #TOKEN_DIV
    beq DIV_OPERATOR
    rts

;; /: divides the left operand by the next power at PTRB, as real numbers; part of <EVALUATE_TERM>.
DIVIDE_OPERATOR:
    tay
    jsr CONVERT_A_TO_REAL                       ; the left operand as a real
    jsr PUSH_REAL
    jsr EVALUATE_POWER
    stx EXPRESSION_TYPE             ; keep the next operator
    tay
    jsr CONVERT_A_TO_REAL                       ; the right operand as a real
    jsr POP_REAL_POINTER
    jsr DIVIDE_BY_FP_A                       ; FPA = the left operand / FPA
    ldx EXPRESSION_TYPE
    lda #TYPE_REAL
    bne EVALUATE_TERM_LOOP          ; always taken

;; MOD: the remainder of dividing the left operand by the next power at PTRB; part of <EVALUATE_TERM>.
MOD_OPERATOR:
    jsr DIVIDE_INTEGERS
    lda DIVIDEND_SIGN               ; the remainder has the dividend's sign
    php
    jmp LOAD_SIGNED_RESULT

;; DIV: the quotient of dividing the left operand by the next power at PTRB; part of <EVALUATE_TERM>.
DIV_OPERATOR:
    jsr DIVIDE_INTEGERS
    rol DIVIDE_QUOTIENT             ; shift in the quotient's last bit
    rol DIVIDE_QUOTIENT+1
    rol DIVIDE_QUOTIENT+2
    rol DIVIDE_QUOTIENT+3
    bit RESULT_SIGN
    php
    ldx #DIVIDE_QUOTIENT
    jmp LOAD_SIGNED_RESULT_X

;; Pushes the integer in IntA on BASIC's stack, then evaluates the power level at PTRB, for the right operand of
;; *, MOD or DIV.
;;
;; It falls into <EVALUATE_POWER>.
;; In: INT_A = the left operand
;; Inherit: <EVALUATE_POWER> Out
;; Uses: all
PUSH_THEN_EVALUATE_POWER:
    jsr PUSH_INTEGER

;; Evaluates the power level at PTRB: factors joined by ^, which raises a number to a power.
;;
;; ^ always gives a real. For x^y it splits y into an integer part n and a fraction f, and works out x^n by repeated
;; multiplication and x^f as EXP(f * LN x), multiplying the two. When y is 64 or more in size, n is taken as 0 and
;; the whole of y as the fraction.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   A = the value's type, with the value in the accumulators
;;   X = the first character after it, spaces skipped
;;   PTR_B_OFFSET = just past that character
;; Uses: all
;; Errors: Type mismatch when an operand is a string, and the floating point errors
EVALUATE_POWER:
    jsr EVALUATE_FACTOR
EVALUATE_POWER_LOOP:
    pha
EVALUATE_POWER_SPACE:
    ldy PTR_B_OFFSET
    inc PTR_B_OFFSET
    lda (PTR_B),y
    cmp #' '
    beq EVALUATE_POWER_SPACE
    tax                             ; the next character
    pla
    cpx #'^'
    beq POWER_OPERATOR
    rts
POWER_OPERATOR:
    tay
    jsr CONVERT_A_TO_REAL                       ; x, the left operand, as a real
    jsr PUSH_REAL
    jsr EVALUATE_REAL_FACTOR                       ; y, the next factor, as a real
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_POWER_LIMIT
    bcs POWER_LARGE
    jsr FRACTIONAL_PART                       ; FPA = the fraction f, FP_WORK+7 = the integer part n
    bne POWER_FRACTION
    jsr POP_REAL_POINTER                    ; no fraction: x^n alone
    jsr LOAD_FP_A
    lda FP_WORK+7
    jsr RAISE_TO_POWER                       ; FPA = x^n
    lda #TYPE_REAL
    bne EVALUATE_POWER_LOOP         ; always taken
POWER_FRACTION:
    jsr STORE_FP_A_TEMP_3                       ; keep f in FP_TEMP_3
    lda BASIC_STACK                 ; x, still on the stack
    sta FP_POINTER
    lda BASIC_STACK+1
    sta FP_POINTER+1
    jsr LOAD_FP_A
    lda FP_WORK+7
    jsr RAISE_TO_POWER                       ; FPA = x^n
POWER_FRACTION_PART:
    jsr STORE_FP_A_TEMP_2                       ; keep x^n in FP_TEMP_2
    jsr POP_REAL_POINTER
    jsr LOAD_FP_A                   ; FPA = x
    jsr LN_FP_A                       ; LN x
    jsr MULTIPLY_BY_FP_TEMP_3                       ; * f
    jsr EXP_FP_A                       ; EXP of that is x^f
    jsr POINT_AT_FP_TEMP_2
    jsr MULTIPLY_FP_A                       ; * x^n
    lda #TYPE_REAL
    bne EVALUATE_POWER_LOOP         ; always taken
POWER_LARGE:
    jsr STORE_FP_A_TEMP_3                       ; y is all fraction: keep it in FP_TEMP_3
    jsr ONE_FP_A                    ; and x^n is 1
    bne POWER_FRACTION_PART         ; always taken

;; Puts a number in StrA in hexadecimal, as PRINT ~ and STR$~ show it, for <NUMBER_TO_STRING>.
;;
;; A real number is made an integer first. The 32 bits are written as up to eight hexadecimal digits with no leading
;; zeros, at the end of StrA.
;; In: Y = the number's type, with the number in IntA or FPA, STRING_LENGTH = the characters already in StrA
;; Out: STRING_BUFFER, STRING_LENGTH = the string
;; Uses: A, X, Y, DIGIT_BUFFER..DIGIT_BUFFER+7, FP_B_SIGN
HEX_TO_STRING:
    tya
    bpl HEX_TO_STRING_INTEGER
    jsr REAL_TO_INTEGER
HEX_TO_STRING_INTEGER:
    ldx #$00
    ldy #$00
HEX_TO_STRING_SPLIT:
    lda a:INT_A,y                   ; each byte of IntA into two digits, least significant first
    pha
    and #$0F
    sta DIGIT_BUFFER,x
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    inx
    sta DIGIT_BUFFER,x
    inx
    iny
    cpy #$04
    bne HEX_TO_STRING_SPLIT
HEX_TO_STRING_FIRST:
    dex                             ; find the first digit that is not zero, but keep the last
    beq HEX_TO_STRING_DIGIT
    lda DIGIT_BUFFER,x
    beq HEX_TO_STRING_FIRST
HEX_TO_STRING_DIGIT:
    lda DIGIT_BUFFER,x
    cmp #10
    bcc HEX_TO_STRING_ASCII
    adc #'A'-'0'-10-1               ; carry is set: 10-15 become "A"-"F"
HEX_TO_STRING_ASCII:
    adc #'0'
    jsr APPEND_CHARACTER
    dex
    bpl HEX_TO_STRING_DIGIT
    rts

;; Part of <NUMBER_TO_STRING>: a real number that is not zero, whose sign is put in the string first.
;;
;; A minus sign is put in StrA for a negative number, and FPA's sign byte is set to the "-" too, whose bit 7 is
;; clear, so that FPA is positive from here on. It then makes the number 1 or more, multiplying it by ten as many
;; times as it needs.
;; Entry: NUMBER_TO_STRING_SCALE_UP = scales the number in FPA so that it is 1 or more
NUMBER_TO_STRING_NONZERO:
    bpl NUMBER_TO_STRING_SCALE_UP
    lda #'-'
    sta FP_A_SIGN                   ; "-" has bit 7 clear: FPA is now positive
    jsr APPEND_CHARACTER
NUMBER_TO_STRING_SCALE_UP:
    lda FP_A_EXPONENT
    cmp #REAL_EXPONENT_ONE
    bcs NUMBER_TO_STRING_SCALE_DOWN ; 1 or more
    jsr MULTIPLY_FP_A_BY_TEN                       ; FPA * 10
    dec FORMAT_EXPONENT
    jmp NUMBER_TO_STRING_SCALE_UP

;; Converts a number to the characters PRINT and STR$ show for it, in StrA, in the format @% selects.
;;
;; The third byte of @% chooses the format: <NUMBER_FORMAT_GENERAL> (or any value above 2), <NUMBER_FORMAT_EXPONENT>
;; or <NUMBER_FORMAT_FIXED>. Its second byte is the number of significant digits, from 1 to 10, or in fixed format the
;; number of decimal places; 0 means 10, or no decimal places in fixed format. When PRINT_HEX is set the number goes
;; to <HEX_TO_STRING> instead.
;;
;; The number is made real, and its sign put in the string. It is scaled to be from 1 up to 10, by multiplying or
;; dividing by ten and counting the power of ten in <FORMAT_EXPONENT>. It is rounded by adding half a unit of the last
;; digit to be shown, and rescaled if that makes it 10. Its mantissa is then shifted so that its top four bits are
;; the digit before the point, and each digit is taken from there in turn, the rest being multiplied by ten for the
;; next. Then:
;;
;; - In general format, the trailing zeros and a trailing point are removed. The number is shown with E notation when
;;   its power of ten is as many as the digits or more, or below -1; numbers from 0.01 up to 0.1 are shown with the
;;   leading zeros instead.
;; - In exponent format there is always one digit before the point, and the E part is padded with spaces to four
;;   characters, so that numbers line up.
;; - In fixed format, a number that would need more than ten significant digits is shown in general format instead.
;; In:
;;   Y = the number's type, <TYPE_INTEGER> or <TYPE_REAL>, with the number in IntA or FPA
;;   AT_PERCENT_DIGITS, AT_PERCENT_FORMAT = the format
;;   PRINT_HEX = bit 7 set for hexadecimal
;; Out: STRING_BUFFER, STRING_LENGTH = the string
;; Uses: A, X, Y, FP_A..FP_A_ROUNDING, FP_B..FP_B_ROUNDING, WORK..WORK+3, FORMAT_EXPONENT, FORMAT_POINT,
;;   EXPRESSION_TYPE, FP_TEMP_1, DIGIT_BUFFER..DIGIT_BUFFER+7
;; Entry: NUMBER_TO_STRING_TEN_DIGITS = converts with ten digits, in the format the caller has put in FORMAT_TYPE,
;;   as STR$ does in general format
NUMBER_TO_STRING:
    ldx AT_PERCENT_FORMAT
    cpx #NUMBER_FORMAT_FIXED+1
    bcc NUMBER_TO_STRING_FORMAT
    ldx #NUMBER_FORMAT_GENERAL      ; any other format is general
NUMBER_TO_STRING_FORMAT:
    stx FORMAT_TYPE
    lda AT_PERCENT_DIGITS
    beq NUMBER_TO_STRING_NO_DIGITS
    cmp #MAXIMUM_DIGITS
    bcs NUMBER_TO_STRING_TEN_DIGITS
    bcc NUMBER_TO_STRING_DIGITS     ; always taken
NUMBER_TO_STRING_NO_DIGITS:
    cpx #NUMBER_FORMAT_FIXED
    beq NUMBER_TO_STRING_DIGITS     ; fixed format with no decimal places
NUMBER_TO_STRING_TEN_DIGITS:
    lda #MAXIMUM_DIGITS
NUMBER_TO_STRING_DIGITS:
    sta FORMAT_DIGITS
    sta FORMAT_POINT
    lda #$00
    sta STRING_LENGTH
    sta FORMAT_EXPONENT
    bit PRINT_HEX
    bmi HEX_TO_STRING
    tya
    bmi NUMBER_TO_STRING_REAL
    jsr INTEGER_TO_REAL
NUMBER_TO_STRING_REAL:
    jsr TEST_FP_A
    bne NUMBER_TO_STRING_NONZERO
    lda FORMAT_TYPE                 ; zero
    bne NUMBER_TO_STRING_ZERO
    lda #'0'                        ; in general format, just "0"
    jmp APPEND_CHARACTER
NUMBER_TO_STRING_ZERO:
    jmp NUMBER_TO_STRING_LAYOUT

;; Part of <NUMBER_TO_STRING>: rounding made the number 10, so it starts again as 1 with the power of ten one more.
;; Entry:
;;   NUMBER_TO_STRING_SCALE_DOWN = scales the number in FPA, 1 or more, so that it is below 10; A = its exponent
;;   NUMBER_TO_STRING_ROUND = rounds the number, from 1 up to 10, to the digits to be shown
NUMBER_TO_STRING_CARRY:
    jsr ONE_FP_A
    bne NUMBER_TO_STRING_RESCALE    ; always taken
NUMBER_TO_STRING_SCALE_DOWN:
    cmp #REAL_EXPONENT_TEN
    bcc NUMBER_TO_STRING_ROUND      ; below 8
    bne NUMBER_TO_STRING_DIVIDE     ; 16 or more
    lda FP_A_MANTISSA
    cmp #REAL_MANTISSA_TEN
    bcc NUMBER_TO_STRING_ROUND      ; below 10
NUMBER_TO_STRING_DIVIDE:
    jsr DIVIDE_FP_A_BY_TEN                       ; FPA / 10
NUMBER_TO_STRING_RESCALE:
    inc FORMAT_EXPONENT
    jmp NUMBER_TO_STRING_SCALE_UP
NUMBER_TO_STRING_ROUND:
    lda FP_A_ROUNDING               ; the rounding byte, which storing FPA loses
    sta EXPRESSION_TYPE
    jsr STORE_FP_A_TEMP_1                       ; keep the number in FP_TEMP_1
    lda FORMAT_POINT                ; the digits asked for
    sta FORMAT_DIGITS
    ldx FORMAT_TYPE
    cpx #NUMBER_FORMAT_FIXED
    bne NUMBER_TO_STRING_HALF
    adc FORMAT_EXPONENT             ; carry is set: fixed format shows the places + the power of ten + 1 digits
    bmi NUMBER_TO_STRING_AS_ZERO    ; too small to show a digit
    sta FORMAT_DIGITS
    cmp #MAXIMUM_DIGITS+1
    bcc NUMBER_TO_STRING_HALF
    lda #MAXIMUM_DIGITS             ; too many digits: general format instead
    sta FORMAT_DIGITS
    lda #NUMBER_FORMAT_GENERAL
    sta FORMAT_TYPE
NUMBER_TO_STRING_HALF:
    jsr ZERO_FP_A                   ; FPA = 5
    lda #REAL_MANTISSA_TEN
    sta FP_A_MANTISSA
    lda #REAL_EXPONENT_FIVE
    sta FP_A_EXPONENT
    ldx FORMAT_DIGITS
    beq NUMBER_TO_STRING_ADD_HALF
NUMBER_TO_STRING_HALF_LOOP:
    jsr DIVIDE_FP_A_BY_TEN                       ; divided by ten for each digit: half a unit of the last digit
    dex
    bne NUMBER_TO_STRING_HALF_LOOP
NUMBER_TO_STRING_ADD_HALF:
    jsr POINT_AT_FP_TEMP_1
    jsr LOAD_FP_B                   ; FPB = the number, from FP_TEMP_1
    lda EXPRESSION_TYPE
    sta FP_B_ROUNDING               ; with its rounding byte
    jsr ADD_FP_B_UNROUNDED                       ; FPA = the number + FPA
NUMBER_TO_STRING_ALIGN:
    lda FP_A_EXPONENT               ; shift until the digit before the point is the mantissa's top four bits
    cmp #REAL_EXPONENT_TEN
    bcs NUMBER_TO_STRING_ALIGNED
    ror FP_A_MANTISSA
    ror FP_A_MANTISSA+1
    ror FP_A_MANTISSA+2
    ror FP_A_MANTISSA+3
    ror FP_A_ROUNDING
    inc FP_A_EXPONENT
    bne NUMBER_TO_STRING_ALIGN      ; always taken
NUMBER_TO_STRING_ALIGNED:
    lda FP_A_MANTISSA
    cmp #REAL_MANTISSA_TEN
    bcs NUMBER_TO_STRING_CARRY      ; rounded up to 10
    lda FORMAT_DIGITS
    bne NUMBER_TO_STRING_POINT

;; Part of <NUMBER_TO_STRING>: where the decimal point goes, then the digits and the E part.
;;
;; This entry is for zero, in exponent or fixed format, or a fixed-format number that rounds to no digits.
;; Entry:
;;   NUMBER_TO_STRING_AS_ZERO = shows zero, in fixed format, with its decimal places
;;   NUMBER_TO_STRING_POINT = places the point for the rounded number in FPA
;; In: A = the format for zero, or 0 for a fixed-format number with no digits
NUMBER_TO_STRING_LAYOUT:
    cmp #NUMBER_FORMAT_EXPONENT
    beq NUMBER_TO_STRING_SET_POINT  ; zero in exponent format: one digit before the point
NUMBER_TO_STRING_AS_ZERO:
    jsr ZERO_FP_A
    lda #$00
    sta FORMAT_EXPONENT
    lda FORMAT_POINT                ; the places, and one digit before the point
    sta FORMAT_DIGITS
    inc FORMAT_DIGITS
NUMBER_TO_STRING_POINT:
    lda #$01
    cmp FORMAT_TYPE
    beq NUMBER_TO_STRING_SET_POINT  ; exponent format: one digit before the point
    ldy FORMAT_EXPONENT
    bmi NUMBER_TO_STRING_SMALL
    cpy FORMAT_DIGITS
    bcs NUMBER_TO_STRING_SET_POINT  ; too large for the digits: E notation, one digit before the point
    lda #$00                        ; no E part
    sta FORMAT_EXPONENT
    iny                             ; the power of ten + 1 digits before the point
    tya
    bne NUMBER_TO_STRING_SET_POINT  ; always taken
NUMBER_TO_STRING_SMALL:
    lda FORMAT_TYPE                 ; below 1
    cmp #NUMBER_FORMAT_FIXED
    beq NUMBER_TO_STRING_LEADING_ZEROS
    lda #$01
    cpy #$FF
    bne NUMBER_TO_STRING_SET_POINT  ; general format below 0.1: E notation, one digit before the point
NUMBER_TO_STRING_LEADING_ZEROS:
    lda #'0'
    jsr APPEND_CHARACTER
    lda #'.'
    jsr APPEND_CHARACTER
    lda #'0'
NUMBER_TO_STRING_ZERO_LOOP:
    inc FORMAT_EXPONENT             ; a zero for each power of ten below -1, leaving no E part
    beq NUMBER_TO_STRING_NO_POINT
    jsr APPEND_CHARACTER
    bne NUMBER_TO_STRING_ZERO_LOOP  ; always taken
NUMBER_TO_STRING_NO_POINT:
    lda #$80                        ; more than the digits: the point is already in the string
NUMBER_TO_STRING_SET_POINT:
    sta FORMAT_POINT
NUMBER_TO_STRING_DIGIT_LOOP:
    jsr APPEND_MANTISSA_DIGIT
    dec FORMAT_POINT
    bne NUMBER_TO_STRING_NEXT_DIGIT
    lda #'.'
    jsr APPEND_CHARACTER
NUMBER_TO_STRING_NEXT_DIGIT:
    dec FORMAT_DIGITS
    bne NUMBER_TO_STRING_DIGIT_LOOP
    ldy FORMAT_TYPE
    dey
    beq NUMBER_TO_STRING_EXPONENT   ; exponent format: always an E part
    dey
    beq NUMBER_TO_STRING_CHECK_EXPONENT ; fixed format
    ldy STRING_LENGTH               ; general format: remove trailing zeros
NUMBER_TO_STRING_TRIM:
    dey
    lda STRING_BUFFER,y
    cmp #'0'
    beq NUMBER_TO_STRING_TRIM
    cmp #'.'
    beq NUMBER_TO_STRING_TRIMMED    ; and the point, when nothing is left after it
    iny
NUMBER_TO_STRING_TRIMMED:
    sty STRING_LENGTH
NUMBER_TO_STRING_CHECK_EXPONENT:
    lda FORMAT_EXPONENT
    beq NUMBER_TO_STRING_DONE
NUMBER_TO_STRING_EXPONENT:
    lda #'E'
    jsr APPEND_CHARACTER
    lda FORMAT_EXPONENT
    bpl NUMBER_TO_STRING_EXPONENT_DIGITS
    lda #'-'
    jsr APPEND_CHARACTER
    sec
    lda #$00
    sbc FORMAT_EXPONENT
NUMBER_TO_STRING_EXPONENT_DIGITS:
    jsr APPEND_DECIMAL_BYTE
    lda FORMAT_TYPE
    beq NUMBER_TO_STRING_DONE       ; general format is not padded
    lda #' '                        ; exponent format: pad the E part to four characters
    ldy FORMAT_EXPONENT
    bmi NUMBER_TO_STRING_PAD        ; the "-" takes the place of one space
    jsr APPEND_CHARACTER
NUMBER_TO_STRING_PAD:
    cpx #$00
    bne NUMBER_TO_STRING_DONE       ; two digits: no more spaces
    jmp APPEND_CHARACTER
NUMBER_TO_STRING_DONE:
    rts

;; Puts the digit in the top four bits of FPA's mantissa at the end of StrA, then multiplies the rest of the mantissa
;; by ten, bringing the next digit to the top.
;; In: FP_A_MANTISSA = the digit in its top four bits
;; Uses: A, X, FP_A_MANTISSA..FP_A_ROUNDING
APPEND_MANTISSA_DIGIT:
    lda FP_A_MANTISSA
    lsr a
    lsr a
    lsr a
    lsr a
    jsr APPEND_DIGIT
    lda FP_A_MANTISSA
    and #$0F
    sta FP_A_MANTISSA
    jmp MULTIPLY_MANTISSA_BY_TEN

;; Puts a number from 0 to 99 at the end of StrA in decimal, with no leading zero.
;; In: A = the number
;; Out: X = its tens digit
;; Uses: A
APPEND_DECIMAL_BYTE:
    ldx #$FF
    sec
APPEND_DECIMAL_BYTE_TENS:
    inx
    sbc #10
    bcs APPEND_DECIMAL_BYTE_TENS
    adc #10                         ; the units
    pha
    txa
    beq APPEND_DECIMAL_BYTE_UNITS
    jsr APPEND_DIGIT
APPEND_DECIMAL_BYTE_UNITS:
    pla

;; Puts a decimal digit at the end of StrA.
;;
;; It falls into <APPEND_CHARACTER>.
;; In: A = the digit, 0-9
;; Out: A = the digit's character
;; Keeps: X, Y
APPEND_DIGIT:
    ora #'0'

;; Puts a character at the end of StrA.
;; In: A = the character, STRING_LENGTH = the characters already in StrA
;; Out: STRING_LENGTH = one more
;; Uses: FP_B_SIGN
;; Keeps: A, X, Y
APPEND_CHARACTER:
    stx FP_B_SIGN
    ldx STRING_LENGTH
    sta STRING_BUFFER,x
    ldx FP_B_SIGN
    inc STRING_LENGTH
    rts

;; Returns from <READ_NUMBER>, which reads a number at PTRB, when the text there does not start a number.
;; In: X = 0
;; Out: carry = clear: no number, A = &FF
;; Uses: FP_A_ROUNDING
NOT_A_NUMBER:
    clc
    stx FP_A_ROUNDING
    jsr TEST_FP_A
    lda #$FF
    rts

; Entry points the BASIC ROM User Guide gives BASIC II's addresses for, for machine code that calls them.
    .assert EVALUATE_EXPRESSION_A = $9B1D, "the BASIC ROM User Guide documents EVALUATE_EXPRESSION_A at &9B1D"
    .assert EVALUATE_EXPRESSION = $9B29, "the BASIC ROM User Guide documents EVALUATE_EXPRESSION at &9B29"
    .assert NUMBER_TO_STRING = $9EDF, "the BASIC ROM User Guide documents NUMBER_TO_STRING at &9EDF"
