;; EXPRESSIONS ($AB90-$AF30)
;;
;; The argument stack and the operators the expression evaluator runs: pushing and popping values, making a string's
;; or array's address absolute, evaluating to an integer, finding and storing a variable's value; the precedence
;; table; the arithmetic, comparison and logical operators and SGN; the checked calls of the floating point package;
;; assignment of numbers and strings; array elements and substrings.
;;
;; The argument stack grows up from LOMEM, eight bytes a value (VALUE_TYPE, VALUE_NUMBER and FR0's six bytes), with
;; ARGUMENT_INDEX counting its values; the operator stack grows down from LOMEM+$FF, a token a byte, with OPERATOR_INDEX
;; its top. The evaluator (<EVALUATE_EXPRESSION>) calls each operator's routine through the operator execution table
;; when the precedence table says so; the routine pops its operands, works and pushes its result. Maintained by hand;
;; assembles byte-identically to the cartridge.

; The precedence table's base: the table's entry for token 0, which falls inside FIND_VARIABLE_ENTRY's code. The
; evaluator indexes it by tokens from OPERATOR_NAMES_FIRST up only.

PRECEDENCE_BASE = PRECEDENCES - OPERATOR_NAMES_FIRST ;; the precedence table, indexed by any operator's token

;; Pops a value and makes its address absolute, for a string or an array.
;;
;; It falls into <MAKE_VALUE_ABSOLUTE>.
;; Out: VALUE_TYPE..FR0+5 = the value, its address absolute
;; Uses: A, X, Y
;; Errors: 9 = array or string DIM error, when the string or array was never DIMensioned
POP_ABSOLUTE_VALUE:
    jsr POP_VALUE

;; Makes the address of the string or array in VALUE_TYPE..FR0+5 absolute, adding STARP, unless it already is.
;;
;; A variable's value entry holds its data's offset from STARP; the value marked VALUE_ABSOLUTE holds its address.
;; In: VALUE_TYPE, FR0 = the string or array and its data's offset or address
;; Out: VALUE_TYPE = with VALUE_ABSOLUTE set, FR0 = the data's address
;; Uses: A, Y
;; Keeps: X
;; Errors: 9 = array or string DIM error, when the string or array was never DIMensioned
MAKE_VALUE_ABSOLUTE:
    lda #VALUE_ABSOLUTE
    bit VALUE_TYPE
    bne MAKE_VALUE_ABSOLUTE_DONE    ; already absolute
    ora VALUE_TYPE
    sta VALUE_TYPE
    ror A                           ; carry = VALUE_DIMENSIONED
    bcc MAKE_VALUE_ABSOLUTE_ERROR
    clc
    lda FR0
    adc STARP
    sta FR0
    tay
    lda FR0+1
    adc STARP+1
    sta FR0+1
MAKE_VALUE_ABSOLUTE_DONE:
    rts
MAKE_VALUE_ABSOLUTE_ERROR:
    jsr DIM_ERROR                   ; error 9

;; Pushes the value in VALUE_TYPE..FR0+5 on the argument stack.
;;
;; Every operator ends here with its result, and its RTS returns to the evaluator.
;; In: VALUE_TYPE..FR0+5 = the value
;; Out: ARGUMENT_INDEX = one more, negative = set
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow, when the value would reach the operator stack
PUSH_VALUE:
    inc ARGUMENT_INDEX
    lda ARGUMENT_INDEX
    asl A
    asl A
    asl A                           ; the end of the new entry
    cmp OPERATOR_INDEX
    bcs PUSH_VALUE_OVERFLOW
    tay
    dey
    ldx #VALUE_SIZE-1
PUSH_VALUE_LOOP:
    lda VALUE_TYPE,x
    sta (LOMEM),y
    dey
    dex
    bpl PUSH_VALUE_LOOP             ; X ends at $FF: negative is set
PUSH_VALUE_DONE:
    rts
PUSH_VALUE_OVERFLOW:
    jmp ARGUMENT_STACK_OVERFLOW_ERROR ; error 10

;; Evaluates the expression at TOKEN_OFFSET to an integer from 0 to 32767.
;; In: STMCUR, TOKEN_OFFSET = the expression
;; Out: FR0 = the integer (2 bytes), A = its high byte, zero = set when it is below 256
;; Uses: all
;; Errors: 3 = value error, when it is beyond 65535; 7 = number greater than 32767; and the expression's errors
EVALUATE_INTEGER:
    jsr EVALUATE_UNSIGNED
    lda FR0+1
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    bmi EVALUATE_INTEGER_ERROR
    rts
EVALUATE_INTEGER_ERROR:
.else
    bpl PUSH_VALUE_DONE
.endif
    jmp NUMBER_TOO_BIG_ERROR        ; error 7

;; Evaluates the expression at TOKEN_OFFSET to an integer from 0 to 65535, rounding it.
;; In: STMCUR, TOKEN_OFFSET = the expression
;; Out: FR0 = the integer (2 bytes), carry = clear
;; Uses: all
;; Errors: 3 = value error, when it is negative or beyond 65535; and the expression's errors
EVALUATE_UNSIGNED:
    jsr EVALUATE_EXPRESSION

;; Pops a number and makes it an integer from 0 to 65535, rounding it.
;; Out: FR0 = the integer (2 bytes), carry = clear
;; Uses: A, X, Y
;; Errors: 3 = value error, when it is negative or beyond 65535
POP_UNSIGNED:
    jsr POP_VALUE
    jmp CHECKED_FPI

;; Evaluates the expression at TOKEN_OFFSET to an integer from 0 to 255.
;; In: STMCUR, TOKEN_OFFSET = the expression
;; Out: FR0 = the integer, A = 0
;; Uses: all
;; Errors: 3 = value error, when it is beyond 255; and the expression's errors
EVALUATE_BYTE:
    jsr EVALUATE_INTEGER
    bne EVALUATE_BYTE_ERROR
    rts
EVALUATE_BYTE_ERROR:
    jsr VALUE_ERROR                 ; error 3

;; Pops the argument stack's top value into VALUE_TYPE..FR0+5.
;; Out: VALUE_TYPE..FR0+5 = the value, ARGUMENT_INDEX = one less
;; Uses: A, X, Y
POP_VALUE:
    lda ARGUMENT_INDEX
    dec ARGUMENT_INDEX
    asl A
    asl A
    asl A                           ; the end of the top entry
    tay
    dey
    ldx #VALUE_SIZE-1
POP_VALUE_LOOP:
    lda (LOMEM),y
    sta VALUE_TYPE,x
    dey
    dex
    bpl POP_VALUE_LOOP
    rts

;; Pops a binary operator's two operands: the right one into FR1, then the left one into FR0.
;; Out: VALUE_TYPE..FR0+5 = the left operand, FR1 = the right operand's number
;; Uses: A, X, Y
POP_TWO_VALUES:
    jsr POP_VALUE
    jsr FMOVE
    jmp POP_VALUE

;; Evaluates the expression at TOKEN_OFFSET and pops its value.
;; In: STMCUR, TOKEN_OFFSET = the expression
;; Out: VALUE_TYPE..FR0+5 = the value
;; Uses: all
;; Errors: the expression's errors
EVALUATE_VALUE:
    jsr EVALUATE_EXPRESSION
.if VERSION = VERSION_A             ; rev. A calls and returns, where the later revisions jump
    jsr POP_VALUE
    rts
.else
    jmp POP_VALUE
.endif

;; Stores the value in VALUE_TYPE..FR0+5 in its variable's value entry, the variable VALUE_NUMBER names.
;; In: VALUE_TYPE..FR0+5 = the value, VALUE_NUMBER = the variable
;; Out: VARIABLE_ENTRY = the variable's value entry
;; Uses: A, X, Y
STORE_VARIABLE:
    lda VALUE_NUMBER
    jsr FIND_VARIABLE_ENTRY
    ldx #$00
STORE_VARIABLE_LOOP:
    lda VALUE_TYPE,x
    sta (VARIABLE_ENTRY),y
    iny
    inx
    cpx #VALUE_SIZE
    bcc STORE_VARIABLE_LOOP
    rts

;; Finds a variable's entry in the variable value table, at VVTP plus eight times its number.
;; In: A = the variable's number, 0-127
;; Out: VARIABLE_ENTRY = the entry, Y = 0
;; Uses: A
;; Keeps: X
FIND_VARIABLE_ENTRY:
    ldy #$00
    sty VARIABLE_ENTRY+1
    asl A
    asl A
    rol VARIABLE_ENTRY+1            ; its operand byte, $9E, is the precedence table's base: see PRECEDENCE_BASE
    asl A
    rol VARIABLE_ENTRY+1
    clc
    adc VVTP
    sta VARIABLE_ENTRY
    lda VVTP+1
    adc VARIABLE_ENTRY+1
    sta VARIABLE_ENTRY+1
    rts

;; A token's two precedences in the precedence table, each 0-15: the one it has coming to the operator stack, and the
;; one it has once on the stack.
;; Parameters: incoming = the precedence coming to the stack, stacked = the precedence on the stack
.macro PRECEDENCE incoming, stacked
    .byte (incoming << 4) | stacked
.endmacro

;; The precedence table: each operator's and function's precedences, from token OPERATOR_NAMES_FIRST to FN_STRIG.
;;
;; When the evaluator reads an operator, it compares its incoming precedence with the stacked precedence of the
;; operator at the top of the operator stack. While the stacked one is at least as high, it pops that operator and
;; runs it; then it pushes the incoming operator. A stacked precedence of 0, which only the sentinel at the stack's
;; bottom has, ends the expression instead, when the incoming operator's is 0 too: every token that can't continue an
;; expression has 0. Equal precedences make an operator work from left to right; a stacked precedence lower than the
;; incoming one, from right to left, as NOT and unary minus do.
;;
;; From the highest, the levels are: the string comparisons; NOT and unary + and -; ^; * and /; + and -; the
;; numeric comparisons; AND; OR; then the assignment and the brackets, which every other operator goes over. NOT
;; binds more tightly than the comparisons, though the BASIC Reference Manual lists it below them, so NOT A=B is
;; (NOT A)=B. Rev. A ranks NOT as the manual does, below the comparisons and above AND.
;;
;; Every ( goes on the stack and lets anything go over it. ) comes to the stack with 4, popping everything above the
;; (, and stays there with 14 until the next operator runs it; its routine then runs the operators below it, the
;; array commas and the (, whose routine does the subscripts, the substring or the function. A function's name is
;; on the stack under its ( and is run the same way.
;; See: <EVALUATE_EXPRESSION>, <PRECEDENCE>
PRECEDENCES:
    PRECEDENCE 0, 0                 ; $10, the quote, which lists a string constant
    PRECEDENCE 0, 0                 ; OP_SENTINEL
    PRECEDENCE 0, 0                 ; OP_COMMA
    PRECEDENCE 0, 0                 ; OP_DOLLAR
    PRECEDENCE 0, 0                 ; TOKEN_STATEMENT_END
    PRECEDENCE 0, 0                 ; OP_SEMICOLON
    PRECEDENCE 0, 0                 ; TOKEN_LINE_END
    PRECEDENCE 0, 0                 ; OP_GOTO
    PRECEDENCE 0, 0                 ; OP_GOSUB
    PRECEDENCE 0, 0                 ; OP_TO
    PRECEDENCE 0, 0                 ; OP_STEP
    PRECEDENCE 0, 0                 ; OP_THEN
    PRECEDENCE 0, 0                 ; OP_HASH
    PRECEDENCE 8, 8                 ; OP_LE
    PRECEDENCE 8, 8                 ; OP_NE
    PRECEDENCE 8, 8                 ; OP_GE
    PRECEDENCE 8, 8                 ; OP_LT
    PRECEDENCE 8, 8                 ; OP_GT
    PRECEDENCE 8, 8                 ; OP_EQ
    PRECEDENCE 12, 12               ; OP_POWER
    PRECEDENCE 10, 10               ; OP_MULTIPLY
    PRECEDENCE 9, 9                 ; OP_ADD
    PRECEDENCE 9, 9                 ; OP_SUBTRACT
    PRECEDENCE 10, 10               ; OP_DIVIDE
.if VERSION = VERSION_A
    PRECEDENCE 7, 7                 ; OP_NOT: rev. A ranks it below the comparisons, so NOT A=B is NOT (A=B)
.else
    PRECEDENCE 13, 13               ; OP_NOT
.endif
    PRECEDENCE 5, 5                 ; OP_OR
    PRECEDENCE 6, 6                 ; OP_AND
    PRECEDENCE 15, 2                ; OP_OPEN_PAREN
    PRECEDENCE 4, 14                ; OP_CLOSE_PAREN
    PRECEDENCE 15, 1                ; OP_ASSIGN_NUMBER
    PRECEDENCE 15, 1                ; OP_ASSIGN_STRING
    PRECEDENCE 14, 14               ; OP_STRING_LE
    PRECEDENCE 14, 14               ; OP_STRING_NE
    PRECEDENCE 14, 14               ; OP_STRING_GE
    PRECEDENCE 14, 14               ; OP_STRING_LT
    PRECEDENCE 14, 14               ; OP_STRING_GT
    PRECEDENCE 14, 14               ; OP_STRING_EQ
    PRECEDENCE 13, 13               ; OP_PLUS
    PRECEDENCE 13, 13               ; OP_MINUS
    PRECEDENCE 15, 2                ; OP_STRING_PAREN
    PRECEDENCE 15, 2                ; OP_ARRAY_PAREN
    PRECEDENCE 15, 2                ; OP_DIM_ARRAY_PAREN
    PRECEDENCE 15, 2                ; OP_FUNCTION_PAREN
    PRECEDENCE 15, 2                ; OP_DIM_STRING_PAREN
    PRECEDENCE 4, 3                 ; OP_ARRAY_COMMA
    PRECEDENCE 15, 2                ; FN_STR
    PRECEDENCE 15, 2                ; FN_CHR
    PRECEDENCE 15, 2                ; FN_USR
    PRECEDENCE 15, 2                ; FN_ASC
    PRECEDENCE 15, 2                ; FN_VAL
    PRECEDENCE 15, 2                ; FN_LEN
    PRECEDENCE 15, 2                ; FN_ADR
    PRECEDENCE 15, 2                ; FN_ATN
    PRECEDENCE 15, 2                ; FN_COS
    PRECEDENCE 15, 2                ; FN_PEEK
    PRECEDENCE 15, 2                ; FN_SIN
    PRECEDENCE 15, 2                ; FN_RND
    PRECEDENCE 15, 2                ; FN_FRE
    PRECEDENCE 15, 2                ; FN_EXP
    PRECEDENCE 15, 2                ; FN_LOG
    PRECEDENCE 15, 2                ; FN_CLOG
    PRECEDENCE 15, 2                ; FN_SQR
    PRECEDENCE 15, 2                ; FN_SGN
    PRECEDENCE 15, 2                ; FN_ABS
    PRECEDENCE 15, 2                ; FN_INT
    PRECEDENCE 15, 2                ; FN_PADDLE
    PRECEDENCE 15, 2                ; FN_STICK
    PRECEDENCE 15, 2                ; FN_PTRIG
    PRECEDENCE 15, 2                ; FN_STRIG
    .assert * - PRECEDENCES = FN_STRIG - OPERATOR_NAMES_FIRST + 1, "The precedence table has every token's entry."

.if VERSION = VERSION_A
;; The + operator: the sum of the two operands. Rev. A keeps it here, with the other arithmetic operators.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now the sum
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow; 11 = floating point overflow/underflow
OPERATOR_ADD:
    jsr POP_TWO_VALUES
    jsr CHECKED_FADD
    jmp PUSH_VALUE
.endif

;; The - operator: the left operand less the right.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now the difference
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow; 11 = floating point overflow/underflow
OPERATOR_SUBTRACT:
    jsr POP_TWO_VALUES
    jsr CHECKED_FSUB
    jmp PUSH_VALUE

;; The * operator: the product of the two operands.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now the product
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow; 11 = floating point overflow/underflow
OPERATOR_MULTIPLY:
    jsr POP_TWO_VALUES
    jsr CHECKED_FMUL
    jmp PUSH_VALUE

;; The / operator: the left operand divided by the right.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now the quotient
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow; 11 = floating point overflow/underflow, dividing by zero among them
OPERATOR_DIVIDE:
    jsr POP_TWO_VALUES
    jsr CHECKED_FDIV
    jmp PUSH_VALUE

;; The unary - operator: the operand with its sign turned over, by its exponent byte's top bit; zero stays zero.
;;
;; Rev. A turns 0 over too, into a negative zero, an exponent byte of $80, which the tests of the exponent byte take
;; for a negative number: SGN(-0) is -1, and NOT -0 is 0.
;; In: ARGUMENT_INDEX = the top value or values, the operand
;; Out: ARGUMENT_INDEX = the top value, now its negative
;; Uses: A, X, Y
OPERATOR_MINUS:
    jsr POP_VALUE
    lda FR0
.if VERSION >= VERSION_B            ; rev. A negates 0 too, into a negative zero
    beq OPERATOR_MINUS_DONE         ; -0 is 0
.endif
    eor #$80
    sta FR0
OPERATOR_MINUS_DONE:
    jmp PUSH_VALUE
.if VERSION = VERSION_A

;; Unary +: does nothing, leaving its operand as it is. Rev. A gives it an RTS of its own.
;; Keeps: A, X, Y
OPERATOR_PLUS:
    rts
.endif

;; The <= operator, for numbers and strings: 1 when the left operand is at most the right, else 0.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now 1 or 0
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow, when the numbers' difference is out of range
;; See: <COMPARE_VALUES>
OPERATOR_LE:
    jsr COMPARE_VALUES
    bmi PUSH_ONE
    beq PUSH_ONE
    bpl PUSH_ZERO                   ; always

;; The <> operator, for numbers and strings: 1 when the operands differ, else 0.
;; Inherit: <OPERATOR_LE> In, Out, Uses, Errors
OPERATOR_NE:
    jsr COMPARE_VALUES
.if VERSION = VERSION_A             ; rev. A branches to the result itself, where the later revisions share OR's
    beq PUSH_ZERO
    bne PUSH_ONE                    ; always
.else
    jmp OPERATOR_OR_RESULT
.endif

;; The < operator, for numbers and strings: 1 when the left operand is less than the right, else 0.
;; Inherit: <OPERATOR_LE> In, Out, Uses, Errors
OPERATOR_LT:
    jsr COMPARE_VALUES
    bmi PUSH_ONE
    bpl PUSH_ZERO                   ; always

;; The > operator, for numbers and strings: 1 when the left operand is greater than the right, else 0.
;; Inherit: <OPERATOR_LE> In, Out, Uses, Errors
OPERATOR_GT:
    jsr COMPARE_VALUES
    bmi PUSH_ZERO
    beq PUSH_ZERO
    bpl PUSH_ONE                    ; always

;; The >= operator, for numbers and strings: 1 when the left operand is at least the right, else 0.
;; Inherit: <OPERATOR_LE> In, Out, Uses, Errors
OPERATOR_GE:
    jsr COMPARE_VALUES
    bmi PUSH_ZERO
    bpl PUSH_ONE                    ; always

;; The = operator comparing, for numbers and strings: 1 when the operands are equal, else 0.
;; Inherit: <OPERATOR_LE> In, Out, Uses, Errors
OPERATOR_EQ:
    jsr COMPARE_VALUES
.if VERSION = VERSION_A             ; rev. A branches to the result itself, where the later revisions share NOT's
    beq PUSH_ONE
    bne PUSH_ZERO                   ; always
.else
    jmp OPERATOR_NOT_RESULT
.endif

;; The AND operator: 1 when both operands are nonzero, else 0.
;;
;; It ANDs the operands' exponent bytes, which are nonzero for any number but zero, so two numbers whose exponents
;; share no bit count as false: 1 AND 0.01 is 0, the exponents being $40 and $3F.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now 1 or 0
;; Uses: A, X, Y
OPERATOR_AND:
    jsr POP_TWO_VALUES
    lda FR0
    and FR1
.if VERSION = VERSION_A             ; rev. A branches to the result itself, where the later revisions share OR's
    beq PUSH_ZERO
    bne PUSH_ONE                    ; always
.else
    jmp OPERATOR_OR_RESULT
.endif

;; The OR operator: 1 when either operand is nonzero, else 0.
;; In: ARGUMENT_INDEX = the top value or values, the two operands
;; Out: ARGUMENT_INDEX = the top value, now 1 or 0
;; Uses: A, X, Y
;; Entry: OPERATOR_OR_RESULT = pushes 1 when A is nonzero, else 0
OPERATOR_OR:
    jsr POP_TWO_VALUES
    lda FR0
    ora FR1
OPERATOR_OR_RESULT:
    beq PUSH_ZERO
    bne PUSH_ONE                    ; always

;; The NOT operator: 1 when the operand is zero, else 0.
;; In: ARGUMENT_INDEX = the top value or values, the operand
;; Out: ARGUMENT_INDEX = the top value, now 1 or 0
;; Uses: A, X, Y
;; Entry: OPERATOR_NOT_RESULT = pushes 1 when A is zero, else 0
OPERATOR_NOT:
    jsr POP_VALUE
    lda FR0
OPERATOR_NOT_RESULT:
    beq PUSH_ONE

;; Pushes the number 0, an operator's false.
;; Out: ARGUMENT_INDEX = the top value, now 0
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow
PUSH_ZERO:
    lda #$00
    tay
    beq PUSH_ONE_STORE              ; always

;; Pushes the number 1, an operator's true.
;; Out: ARGUMENT_INDEX = the top value, now 1
;; Uses: A, X, Y
;; Errors: 10 = argument stack overflow
;; Entry:
;;   PUSH_ONE_SIGNED = pushes 1 with the exponent byte in A, $C0 making it -1
;;   PUSH_ONE_STORE = pushes the number whose first two bytes are A and Y, the rest zero
;;   PUSH_ONE_DONE = pushes VALUE_TYPE..FR0+5
PUSH_ONE:
    lda #$40                        ; 1: the exponent of 100^0
PUSH_ONE_SIGNED:
    ldy #$01                        ; and the first pair of digits, 01
PUSH_ONE_STORE:
    sta FR0
    sty FR0+1
    ldx #FR0+2
    ldy #FP_SIZE-2
    jsr FP_CLEAR_BYTES
    sta VALUE_TYPE                  ; a number
PUSH_ONE_DONE:
    jmp PUSH_VALUE

;; SGN(aexp): 1 when the number is positive, -1 when it is negative, and 0 when it is 0.
;; In: ARGUMENT_INDEX = the top value or values, the number
;; Out: ARGUMENT_INDEX = the top value, now its sign
;; Uses: A, X, Y
FUNCTION_SGN:
    jsr POP_VALUE
    lda FR0
    beq PUSH_ONE_DONE               ; 0 stays 0
    bpl PUSH_ONE
    lda #$C0                        ; -1: the exponent of 100^0, negative
    bmi PUSH_ONE_SIGNED             ; always

;; Pops a comparison's two operands and compares them, numbers by subtracting, strings by <COMPARE_STRINGS>.
;;
;; The comparison operators serve numbers and strings both: the token just popped from the operator stack says
;; which.
;; In: ARGUMENT_INDEX = the two operands at the top, OPERATOR_INDEX = just past the comparison's token
;; Out: negative = set when the left operand is less, zero = set when they are equal
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow, when the numbers' difference is out of range
COMPARE_VALUES:
    ldy OPERATOR_INDEX
    dey
    lda (LOMEM),y                   ; the comparison's token
    cmp #OP_STRING_LE
    bcc COMPARE_VALUES_NUMBERS
    jmp COMPARE_STRINGS
COMPARE_VALUES_NUMBERS:
    jsr POP_TWO_VALUES

;; Subtracts FR1 from FR0 and returns the difference's exponent byte, to compare two numbers.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = the difference, A = its exponent byte, negative = set when FR0 was less, zero = set when equal
;; Uses: X, Y
;; Errors: 11 = floating point overflow/underflow
SUBTRACT_TO_COMPARE:
    jsr CHECKED_FSUB
    lda FR0
    rts

;; Adds FR1 to FR0 with the floating point package's FADD, raising error 11 when the sum is out of range.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = the sum
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow
CHECKED_FADD:
    jsr FADD
    bcs CHECKED_FP_OVERFLOW
    rts

;; Subtracts FR1 from FR0 with FSUB, raising error 11 when the difference is out of range.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = the difference
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow
CHECKED_FSUB:
    jsr FSUB
    bcs CHECKED_FP_OVERFLOW
    rts

;; Multiplies FR0 by FR1 with FMUL, raising error 11 when the product is out of range.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = the product
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow
CHECKED_FMUL:
    jsr FMUL
    bcs CHECKED_FP_OVERFLOW
    rts

;; Divides FR0 by FR1 with FDIV, raising error 11 when the quotient is out of range or FR1 is zero.
;; In: FR0, FR1 = the numbers
;; Out: FR0 = the quotient
;; Uses: A, X, Y
;; Errors: 11 = floating point overflow/underflow
CHECKED_FDIV:
    jsr FDIV
    bcs CHECKED_FP_OVERFLOW
    rts
CHECKED_FP_OVERFLOW:
    jsr FLOATING_POINT_OVERFLOW_ERROR ; error 11

;; Rounds FR0 to an integer from 0 to 65535 with FPI, raising error 3 when it is out of range.
;; In: FR0 = the number
;; Out: FR0 = the integer (2 bytes), carry = clear
;; Uses: A, X, Y
;; Errors: 3 = value error, when the number is negative or beyond 65535
CHECKED_FPI:
    jsr FPI
    bcs CHECKED_FPI_ERROR
    rts
CHECKED_FPI_ERROR:
    jsr VALUE_ERROR                 ; error 3

;; The = operator assigning a number, as in LET: stores the value in the variable, or lets an array element do it.
;;
;; When the target is a variable, the operator stack holds only its sentinel, and the routine pops the value and the
;; target and stores the value in the target's variable. When it is an array element, the element's ) and ( are
;; still on the operator stack: the routine sets ASSIGN_FLAGS bit 7 and returns, and the evaluator goes on to run them,
;; <OPERATOR_ARRAY_PAREN> storing the value in the element.
;; In: ARGUMENT_INDEX = the target, then the value, at the top
;; Out: VARIABLE_ENTRY = the variable's entry, holding the value, or ASSIGN_FLAGS = $80 for an element
;; Uses: A, X, Y
OPERATOR_ASSIGN_NUMBER:
    lda OPERATOR_INDEX
    cmp #$FF
    bne OPERATOR_ASSIGN_NUMBER_ELEMENT  ; more than the sentinel left
    jsr POP_TWO_VALUES
    ldx #FP_SIZE-1
OPERATOR_ASSIGN_NUMBER_LOOP:
    lda FR1,x                       ; the value, in the target's place
    sta FR0,x
    dex
    bpl OPERATOR_ASSIGN_NUMBER_LOOP
    jmp STORE_VARIABLE
OPERATOR_ASSIGN_NUMBER_ELEMENT:
    lda #$80
    sta ASSIGN_FLAGS
    rts

;; The , between an array's subscripts or a function's arguments: counts itself and runs the operator below it.
;;
;; It falls into <OPERATOR_CLOSE_PAREN>.
;; Out: COMMA_COUNT = one more
;; Uses: A, X, Y
OPERATOR_ARRAY_COMMA:
    inc COMMA_COUNT

;; The ) operator, and a function's (: runs the operator below it on the operator stack in its place.
;;
;; It drops its own return to the evaluator and pops the next operator, so that ) runs the commas below it and their
;; (, and a function's ( runs the function. That operator's routine returns to the evaluator.
;; In: OPERATOR_INDEX = the operator below
;; Uses: A, X, Y
OPERATOR_CLOSE_PAREN:
    ldy OPERATOR_INDEX
    pla
    pla
    jmp EXECUTE_STACKED_OPERATOR

;; The ( after an array's or a string's name in DIM or COM: reads the sizes for DIM, as <OPERATOR_ARRAY_PAREN> does.
;;
;; It falls into <OPERATOR_ARRAY_PAREN>, with ASSIGN_FLAGS bit 6 set.
;; Inherit: <OPERATOR_ARRAY_PAREN> In, Out, Uses, Errors
OPERATOR_DIM_ARRAY_PAREN:
    lda #$40
    sta ASSIGN_FLAGS

;; The ( after an array's name: the array element its subscripts name, or the element an assignment stores in.
;;
;; The subscripts count from 0 to the sizes DIM gave. The element's address is STARP, plus the array's offset, plus
;; six times the first subscript times the second size, plus the second subscript (the sizes are kept one more than
;; DIM's). When ASSIGN_FLAGS bit 7 says the element is an assignment's target, the value to assign is above the
;; subscripts on the argument stack: the routine stores it there and pushes nothing. For DIM, it stops with the
;; sizes read.
;; In:
;;   ARGUMENT_INDEX = at the top, the array, its first subscript, its second when COMMA_COUNT is 1, then the value
;;     when ASSIGN_FLAGS bit 7 is set
;;   COMMA_COUNT = 1 for two subscripts, ASSIGN_FLAGS = bit 7 for an assignment, bit 6 for DIM
;; Out:
;;   ARGUMENT_INDEX = the top value, now the element's value, unless assigning or for DIM
;;   (ZTEMP1) = the value, when assigning
;;   VALUE_TYPE..FR0+5 = for DIM, the variable's value entry
;;   ZTEMP1 = for DIM, the first size; the element's address otherwise
;;   SECOND_INDEX = for DIM, the second size or 0
;;   ASSIGN_FLAGS = 0 for DIM or an assignment
;;   COMMA_COUNT = 0
;; Uses: A, X, Y, ZTEMP3, ZTEMP4
;; Errors: 3 = value error, for a subscript beyond 65535; 9 = array or string DIM error, for a subscript of 32768 up,
;;   one beyond the array's size, or an array never DIMensioned; 10 = argument stack overflow
OPERATOR_ARRAY_PAREN:
    bit ASSIGN_FLAGS
    bpl OPERATOR_ARRAY_PAREN_SUBSCRIPTS
    lda ARGUMENT_INDEX              ; skip the value to assign for now
    sta SAVED_ARGUMENT
    dec ARGUMENT_INDEX
OPERATOR_ARRAY_PAREN_SUBSCRIPTS:
    lda #$00                        ; no second subscript: 0
    tay
    cmp COMMA_COUNT
    beq OPERATOR_ARRAY_PAREN_FIRST
    dec COMMA_COUNT
    jsr POP_UNSIGNED
    lda FR0+1
    bmi OPERATOR_ARRAY_PAREN_ERROR
    ldy FR0
OPERATOR_ARRAY_PAREN_FIRST:
    sta SECOND_INDEX+1
    sty SECOND_INDEX
    jsr POP_UNSIGNED
    lda FR0
    sta ZTEMP1
    lda FR0+1
    bmi OPERATOR_ARRAY_PAREN_ERROR
    sta ZTEMP1+1
    jsr POP_VALUE                   ; the array
    bit ASSIGN_FLAGS
    bvc OPERATOR_ARRAY_PAREN_ELEMENT
    lda #$00                        ; DIM: the sizes are read
    sta ASSIGN_FLAGS
    rts
OPERATOR_ARRAY_PAREN_ELEMENT:
    ror VALUE_TYPE                  ; carry = VALUE_DIMENSIONED
    bcs OPERATOR_ARRAY_PAREN_BOUNDS
OPERATOR_ARRAY_PAREN_ERROR:
    jsr DIM_ERROR                   ; error 9
OPERATOR_ARRAY_PAREN_BOUNDS:
    lda ZTEMP1+1                    ; the first subscript below the first size?
    cmp FR0+3
    bcc OPERATOR_ARRAY_PAREN_SECOND
    bne OPERATOR_ARRAY_PAREN_ERROR
    lda ZTEMP1
    cmp FR0+2
    bcs OPERATOR_ARRAY_PAREN_ERROR
OPERATOR_ARRAY_PAREN_SECOND:
    lda SECOND_INDEX+1              ; the second below the second size?
    cmp FR0+5
    bcc OPERATOR_ARRAY_PAREN_ADDRESS
    bne OPERATOR_ARRAY_PAREN_ERROR
    lda SECOND_INDEX
    cmp FR0+4
    bcs OPERATOR_ARRAY_PAREN_ERROR
OPERATOR_ARRAY_PAREN_ADDRESS:
    jsr ARRAY_MULTIPLY              ; the first subscript times the second size
    lda SECOND_INDEX
    ldy SECOND_INDEX+1
    jsr ARRAY_ADD                   ; plus the second subscript
    jsr ARRAY_TIMES_SIX             ; times 6
    lda FR0
    ldy FR0+1
    jsr ARRAY_ADD                   ; plus the array's offset
    lda STARP
    ldy STARP+1
    jsr ARRAY_ADD                   ; plus STARP
    bit ASSIGN_FLAGS
    bpl OPERATOR_ARRAY_PAREN_FETCH
    lda SAVED_ARGUMENT              ; assigning: back to the value, and store it
    sta ARGUMENT_INDEX
    jsr POP_VALUE
    ldy #FP_SIZE-1
OPERATOR_ARRAY_PAREN_STORE:
    lda FR0,y
    sta (ZTEMP1),y
    dey
    bpl OPERATOR_ARRAY_PAREN_STORE
    iny
    sty ASSIGN_FLAGS
    rts
OPERATOR_ARRAY_PAREN_FETCH:
    ldy #FP_SIZE-1
OPERATOR_ARRAY_PAREN_FETCH_LOOP:
    lda (ZTEMP1),y
    sta FR0,y
    dey
    bpl OPERATOR_ARRAY_PAREN_FETCH_LOOP
    iny
    sty VALUE_TYPE                  ; a number
    jmp PUSH_VALUE

;; The ( after a string's name: the substring from the first index to the last, or to the string's end.
;;
;; The indexes count from 1. Without a last index, the substring ends at the string's length; the last index may be
;; no more than the length. When ASSIGN_FLAGS bit 7 says the substring is an assignment's target, the DIMensioned
;; size takes the length's place, nothing is pushed, and the routine returns the substring's address and room for
;; <ASSIGN_STRING>, with ASSIGN_FLAGS bit 0 set when the last index was given.
;; In:
;;   ARGUMENT_INDEX = at the top, the string, its first index, its last index when COMMA_COUNT is 1
;;   COMMA_COUNT = 1 for two indexes, ASSIGN_FLAGS = bit 7 for an assignment
;; Out:
;;   ARGUMENT_INDEX = the top value, now the substring, unless assigning
;;   VALUE_TYPE..FR0+5 = the substring when assigning: FR0 its address, FR0+2 its room
;;   COMMA_COUNT = 0
;; Uses: A, X, Y, ZTEMP1
;; Errors: 3 = value error, for an index beyond 65535; 5 = string length error, for an index of 0, a last index
;;   beyond the length or the first beyond it; 9 = array or string DIM error, for a string never DIMensioned;
;;   10 = argument stack overflow
OPERATOR_STRING_PAREN:
    lda COMMA_COUNT
    beq OPERATOR_STRING_PAREN_FIRST
    jsr POP_STRING_INDEX
    sty SECOND_INDEX+1
    sta SECOND_INDEX
OPERATOR_STRING_PAREN_FIRST:
    jsr POP_STRING_INDEX
    sec
    sbc #$01                        ; the characters before the substring
    sta ZTEMP1
    tya
    sbc #$00
    sta ZTEMP1+1
    jsr POP_VALUE                   ; the string
    lda ASSIGN_FLAGS
    bpl OPERATOR_STRING_PAREN_LENGTH
    ora COMMA_COUNT
    sta ASSIGN_FLAGS
    ldy FR0+5                       ; assigning: up to the DIMensioned size
    lda FR0+4
    jmp OPERATOR_STRING_PAREN_LIMIT
OPERATOR_STRING_PAREN_LENGTH:
    lda FR0+2                       ; up to the length
    ldy FR0+3
OPERATOR_STRING_PAREN_LIMIT:
    ldx COMMA_COUNT
    beq OPERATOR_STRING_PAREN_END
    dec COMMA_COUNT
    cpy SECOND_INDEX+1              ; the last index within the limit?
    bcc OPERATOR_STRING_PAREN_ERROR
    bne OPERATOR_STRING_PAREN_LAST
    cmp SECOND_INDEX
    bcc OPERATOR_STRING_PAREN_ERROR
OPERATOR_STRING_PAREN_LAST:
    ldy SECOND_INDEX+1
    lda SECOND_INDEX
OPERATOR_STRING_PAREN_END:
    sec
    sbc ZTEMP1                      ; the substring's length
    sta FR0+2
    tax
    tya
    sbc ZTEMP1+1
    sta FR0+3
    bcc OPERATOR_STRING_PAREN_ERROR
    tay
    bne OPERATOR_STRING_PAREN_ADDRESS
    txa
    beq OPERATOR_STRING_PAREN_ERROR ; empty
OPERATOR_STRING_PAREN_ADDRESS:
    jsr MAKE_VALUE_ABSOLUTE
    clc
    lda FR0
    adc ZTEMP1
    sta FR0
    lda FR0+1
    adc ZTEMP1+1
    sta FR0+1
    bit ASSIGN_FLAGS
    bpl OPERATOR_STRING_PAREN_PUSH
    rts
OPERATOR_STRING_PAREN_PUSH:
    jmp PUSH_VALUE
OPERATOR_STRING_PAREN_ERROR:
    jsr STRING_LENGTH_ERROR         ; error 5

;; Pops a substring's index: an integer from 1 to 65535.
;; Out: A = its low byte, Y = its high byte, FR0 = the index
;; Uses: X
;; Errors: 3 = value error, when it is negative or beyond 65535; 5 = string length error, when it is 0
POP_STRING_INDEX:
    jsr POP_UNSIGNED
    lda FR0
    ldy FR0+1
    bne POP_STRING_INDEX_DONE
    tax
    beq OPERATOR_STRING_PAREN_ERROR
POP_STRING_INDEX_DONE:
    rts

;; The = operator assigning a string, as in LET: copies the string into the target string or substring.
;;
;; It falls into <ASSIGN_STRING>.
;; In: ARGUMENT_INDEX = the target, then the string, at the top
;; Inherit: <ASSIGN_STRING> Out, Uses, Errors
OPERATOR_ASSIGN_STRING:
    jsr POP_ABSOLUTE_VALUE

;; Copies a string into the assignment's target, a string variable or a substring, and sets the variable's length.
;;
;; The copy is cut to the target's room: a variable's DIMensioned size, or the room from a substring's first index.
;; Assigning to a whole variable or to a substring without a last index makes the variable's length end where the copy
;; does; with a last index, the length only grows, when the copy ends beyond it. READ and INPUT enter here too.
;; In:
;;   FR0, FR0+2 = the string to copy, its address absolute, and its length
;;   ARGUMENT_INDEX = the target variable at the top, when the operator stack holds only its sentinel
;;   OPERATOR_INDEX = the target substring's ) and (, otherwise, on the target variable and its indexes
;; Out: VARIABLE_ENTRY = the target variable's entry, with its new length
;; Uses: A, X, Y, MOVE_FROM, MOVE_TO, MOVE_LENGTH, ZTEMP3
;; Errors: 5 = string length error and 9 = array or string DIM error, for the target's indexes or a string never
;;   DIMensioned
ASSIGN_STRING:
    lda FR0
    sta MOVE_FROM
    lda FR0+1
    sta MOVE_FROM+1
    lda FR0+2
    sta MOVE_LENGTH
    ldy FR0+3
    sty MOVE_LENGTH+1
    ldy OPERATOR_INDEX
    cpy #$FF
    beq ASSIGN_STRING_VARIABLE      ; only the sentinel: a whole variable
    lda #$80                        ; a substring: run its ) and (, which return its address and room
    sta ASSIGN_FLAGS
    jsr EXECUTE_STACKED_OPERATOR
    lda FR0+3
    ldy FR0+2
    rol ASSIGN_FLAGS                ; bit 0, a last index, to bit 1; bit 7 to carry
    bcs ASSIGN_STRING_LIMIT         ; always
ASSIGN_STRING_VARIABLE:
    jsr POP_ABSOLUTE_VALUE
    lda FR0+5                       ; the room: the DIMensioned size
    ldy FR0+4
ASSIGN_STRING_LIMIT:
    cmp MOVE_LENGTH+1               ; cut the copy to the room
    bcc ASSIGN_STRING_CUT
    bne ASSIGN_STRING_MOVE
    cpy MOVE_LENGTH
    bcs ASSIGN_STRING_MOVE
ASSIGN_STRING_CUT:
    sta MOVE_LENGTH+1
    sty MOVE_LENGTH
ASSIGN_STRING_MOVE:
    clc
    lda FR0
    adc MOVE_LENGTH
    tay
    lda FR0+1
    adc MOVE_LENGTH+1
    tax
    sec
    tya
    sbc STARP                       ; the copy's end, as an offset from STARP
    sta ZTEMP3
    txa
    sbc STARP+1
    sta ZTEMP3+1
    sec                             ; MOVE_MEMORY_DOWN starts each pointer back by the length's low byte, negated
    lda #$00
    sbc MOVE_LENGTH
    sta MOVE_LENGTH
    sec
    lda MOVE_FROM
    sbc MOVE_LENGTH
    sta MOVE_FROM
    lda MOVE_FROM+1
    sbc #$00
    sta MOVE_FROM+1
    sec
    lda FR0
    sbc MOVE_LENGTH
    sta MOVE_TO
    lda FR0+1
    sbc #$00
    sta MOVE_TO+1
    jsr MOVE_MEMORY_DOWN
    lda VALUE_NUMBER                ; the target's value entry
    jsr READ_VARIABLE
    sec
    lda ZTEMP3                      ; the new length: the copy's end less the string's offset
    sbc FR0
    tay
    lda ZTEMP3+1
    sbc FR0+1
    tax
    lda #$02                        ; a substring with a last index?
    and ASSIGN_FLAGS
    beq ASSIGN_STRING_LENGTH
    lda #$00
    sta ASSIGN_FLAGS
    cpx FR0+3                       ; then only a longer length counts
    bcc ASSIGN_STRING_DONE
    bne ASSIGN_STRING_LENGTH
    cpy FR0+2
    bcs ASSIGN_STRING_LENGTH
ASSIGN_STRING_DONE:
    rts
ASSIGN_STRING_LENGTH:
    sty FR0+2
    stx FR0+3
    jmp STORE_VARIABLE
