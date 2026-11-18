;; BBC BASIC II: the functions ($AB33-$B111).
;;
;; The functions that are not mathematical, in the order of the ROM:
;;
;; - The functions that ask the MOS: ADVAL, POINT(, POS and VPOS, then SGN, LOG, RAD, DEG, PI and USR.
;; - EVAL and VAL, which read a number or an expression from a string; INT, ASC, INKEY, EOF, TRUE, NOT, INSTR( and
;;   ABS, with the negation of IntA and FPA.
;; - Reading a string item for READ and INPUT, and <EVALUATE_FACTOR>, which reads one factor of an expression: a
;;   number, a variable, a bracketed expression, a hexadecimal number, a quoted string or a function.
;; - The pseudo-variables read as functions: TIME, PAGE, TOP, LOMEM and HIMEM; FALSE, LEN and COUNT, with the
;;   routines that load IntA with a number.
;; - RND and its random number generator, ERL, ERR, INKEY's call to the MOS, GET and GET$.
;; - The string functions: LEFT$(, RIGHT$(, INKEY$, MID$(, STR$ and STRING$(.
;;
;; A function is entered from <EVALUATE_FACTOR> with PTRB's offset just past its token, and returns its value in
;; BASIC's accumulators, with the type in A: &00 and zero set for a string in StrA, &40 for an integer in IntA, and
;; &FF and negative set for a real number in FPA.

; Error numbers raised in this part.
ERROR_NO_SUCH_VARIABLE = $1A        ;; error 26, "No such variable"
ERROR_MISSING_BRACKET = $1B         ;; error 27, "Missing )"
ERROR_BAD_HEX = $1C                 ;; error 28, "Bad HEX"
ERROR_NO_SUCH_FN_PROC = $1D         ;; error 29, "No such FN/PROC"

; The MOS calls the functions make.
OSBYTE_READ_ADC = $80               ;; OSBYTE &80: read an ADC channel (X = 1-4) or a buffer's status (X negative)
OSBYTE_READ_TEXT_CURSOR = $86       ;; OSBYTE &86: read the text cursor's column into X and its row into Y
OSBYTE_CHECK_EOF = $7F              ;; OSBYTE &7F: check for the end of the file open on channel X
OSBYTE_INKEY = $81                  ;; OSBYTE &81: read a key within a time limit, or scan for a key
OSWORD_READ_PIXEL = $09             ;; OSWORD 9: read the logical colour of a pixel
OSWORD_READ_CLOCK = $01             ;; OSWORD 1: read the system clock, five bytes

STR_USES_AT_PERCENT = AT_PERCENT + 3    ;; @%'s top byte: STR$ formats numbers with @% when it is not zero

;; ADVAL: reads an analogue channel or a buffer's status: ADVAL(n).
;;
;; The number is passed to OSBYTE &80 in X: 1-4 read the analogue to digital converter's channels, 0 the fire buttons
;; and the last channel converted, and a negative number a buffer's free space or contents. The result is the 16-bit
;; value OSBYTE returns in X and Y.
;; Out: INT_A = the value, A = &40 (an integer)
ADVAL_FUNCTION:
    jsr EVALUATE_INTEGER_FACTOR
    ldx INT_A
    lda #OSBYTE_READ_ADC
    jsr OSBYTE
    txa
    jmp LOAD_INT_A_WORD

;; POINT(: reads the logical colour of a graphics point: POINT(X,Y).
;;
;; The coordinates go to OSWORD 9 in IntA's four bytes, X then Y, and the colour comes back in the fifth byte, &2E,
;; which is &FF when the point is off the screen.
;; Out: INT_A = the colour, or -1 off the screen, A = &40 (an integer)
POINT_FUNCTION:
    jsr EVALUATE_INTEGER
    jsr PUSH_INTEGER
    jsr CHECK_COMMA_B
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
    lda INT_A                       ; keep Y while X comes back
    pha
    lda INT_A+1
    pha
    jsr POP_INTEGER                 ; X into INT_A..INT_A+1; leaves Y = 0 for OSWORD
    pla
    sta INT_A+3
    pla
    sta INT_A+2
    ldx #INT_A
    lda #OSWORD_READ_PIXEL
    jsr OSWORD
    lda FP_A_SIGN                   ; the fifth byte of the block: the colour
    bmi SGN_MINUS_ONE
    jmp LOAD_INT_A_BYTE

;; POS: gives the column of the text cursor.
;; Out: INT_A = the column, A = &40 (an integer)
POS_FUNCTION:
    lda #OSBYTE_READ_TEXT_CURSOR
    jsr OSBYTE
    txa
    jmp LOAD_INT_A_BYTE

;; VPOS: gives the row of the text cursor.
;; Out: INT_A = the row, A = &40 (an integer)
VPOS_FUNCTION:
    lda #OSBYTE_READ_TEXT_CURSOR
    jsr OSBYTE
    tya
    jmp LOAD_INT_A_BYTE

;; SGN of a real number in FPA: gives -1, 0 or 1 as an integer.
;; In: FP_A = the number
;; Out: INT_A = the sign, A = &40 (an integer)
SGN_REAL:
    jsr TEST_FP_A
    beq SGN_RETURN                  ; A = 0 for zero
    bpl SGN_PLUS_ONE
    bmi SGN_MINUS_ONE               ; always taken

;; SGN: gives the sign of a number: SGN(n) is -1 when n is negative, 0 when it is zero and 1 when it is positive.
;; Out: INT_A = the sign, A = &40 (an integer)
;; Errors: "Type mismatch" for a string
;; Entry: SGN_MINUS_ONE = gives -1 (TRUE), SGN_PLUS_ONE = gives 1, SGN_RETURN = gives the integer in A
SGN_FUNCTION:
    jsr EVALUATE_FACTOR
    beq EVAL_TYPE_MISMATCH
    bmi SGN_REAL
    lda INT_A+3
    ora INT_A+2
    ora INT_A+1
    ora INT_A
    beq SGN_ZERO
    lda INT_A+3
    bpl SGN_PLUS_ONE
SGN_MINUS_ONE:
    jmp TRUE_FUNCTION
SGN_PLUS_ONE:
    lda #$01
SGN_RETURN:
    jmp LOAD_INT_A_BYTE
SGN_ZERO:
    lda #$40                        ; IntA is already zero
    rts

;; LOG: gives the common logarithm, to base 10: LOG(n).
;;
;; It takes the natural logarithm and multiplies it by 1/LN 10.
;; Out: FP_A = the logarithm, A = &FF (a real)
;; See: <LN_FUNCTION>
LOG_FUNCTION:
    jsr LN_FUNCTION
    ldy #<LOG10_E
    lda #>LOG10_E
    bne MULTIPLY_BY_CONSTANT        ; always taken

;; RAD: converts an angle in degrees to radians: RAD(n).
;; Out: FP_A = the angle in radians, A = &FF (a real)
RAD_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    ldy #<RADIANS_PER_DEGREE
    lda #>RADIANS_PER_DEGREE

;; Multiplies FPA by a packed real constant, for LOG, RAD and DEG.
;; In: Y = the constant's address low, A = its high byte, FP_A = the number
;; Out: FP_A = the product, A = &FF (a real)
;; Uses: FP_POINTER
MULTIPLY_BY_CONSTANT:
    sty FP_POINTER
    sta FP_POINTER+1
    jsr MULTIPLY_FP_A
    lda #TYPE_REAL
    rts

;; DEG: converts an angle in radians to degrees: DEG(n).
;; Out: FP_A = the angle in degrees, A = &FF (a real)
DEG_FUNCTION:
    jsr EVALUATE_REAL_FACTOR
    ldy #<DEGREES_PER_RADIAN
    lda #>DEGREES_PER_RADIAN
    bne MULTIPLY_BY_CONSTANT        ; always taken

;; PI: gives pi, 3.14159265.
;;
;; It loads pi/2 and doubles it by adding one to the exponent; TAY then sets the flags from A again, negative for a
;; real result, after INC has changed them.
;; Out: FP_A = pi, A = Y = &FF (a real)
PI_FUNCTION:
    jsr LOAD_HALF_PI
    inc FP_A_EXPONENT
    tay
    rts

;; USR: calls machine code and returns its registers: USR(address).
;;
;; As for CALL, the routine is entered with A, X and Y from the low bytes of A%, X% and Y%, and the carry from bit 0
;; of C%. When it returns, the result holds its registers: A in the low byte, then X, Y and the status register in the
;; high byte.
;; Out: INT_A = P, Y, X, A from high byte to low, A = &40 (an integer)
;; See: <CALL_STATEMENT>
USR_FUNCTION:
    jsr EVALUATE_INTEGER_FACTOR
    jsr CALL_MACHINE_CODE
    sta INT_A
    stx INT_A+1
    sty INT_A+2
    php
    pla
    sta INT_A+3
    cld                             ; in case the routine left decimal mode on
    lda #TYPE_INTEGER
    rts

;; Raises "Type mismatch", for SGN and EVAL; a jump within branch reach.
EVAL_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; EVAL: evaluates a string as an expression: EVAL(string).
;;
;; The string, with a carriage return added, is pushed on BASIC's stack and tokenised there, as if it were the middle
;; of a statement, so that PAGE and the other pseudo-variables become their function tokens, and numbers are not line
;; numbers. Then PTRB is pointed at it and the expression is evaluated. PTRB is kept on the 6502 stack meanwhile.
;; Out: A = EXPRESSION_TYPE = the type of the result, with the result in its accumulator
;; Errors: "Type mismatch" when the argument is not a string, and any error in the expression
;; Entry: EVAL_RESTORE_PTR_B = pulls PTRB's offset and address from the 6502 stack and returns the type in
;;   EXPRESSION_TYPE (VAL ends here too)
EVAL_FUNCTION:
    jsr EVALUATE_FACTOR
    bne EVAL_TYPE_MISMATCH
    inc STRING_LENGTH
    ldy STRING_LENGTH
    lda #CARRIAGE_RETURN                ; end the string with a carriage return
    sta STRING_BUFFER-1,y
    jsr PUSH_STRING
    lda PTR_B
    pha
    lda PTR_B+1
    pha
    lda PTR_B_OFFSET
    pha
    ldy BASIC_STACK                 ; the string's first character is just above its length byte
    ldx BASIC_STACK+1
    iny
    sty PTR_B
    sty WORK                        ; the tokeniser's pointer
    bne EVAL_POINTED
    inx
EVAL_POINTED:
    stx PTR_B+1
    stx WORK+1
    ldy #$FF
    sty FP_B_SIGN                   ; tokenise as the middle of a statement
    iny
    sty PTR_B_OFFSET
    jsr TOKENISE_WITHOUT_LINE_NUMBERS                       ; with numbers not taken as line numbers
    jsr EVALUATE_EXPRESSION
    jsr DROP_STRING                       ; drop the string from BASIC's stack
EVAL_RESTORE_PTR_B:
    pla
    sta PTR_B_OFFSET
    pla
    sta PTR_B+1
    pla
    sta PTR_B
    lda EXPRESSION_TYPE
    rts

;; VAL: gives the number at the start of a string: VAL(string).
;;
;; Spaces and a sign may come before the number, and anything after it is ignored. A string with no number gives 0.
;; Out: A = EXPRESSION_TYPE = &40 or &FF, with the number in IntA or FPA
;; Errors: "Type mismatch" when the argument is not a string
VAL_FUNCTION:
    jsr EVALUATE_FACTOR
    bne INT_TYPE_MISMATCH

;; Reads the number at the start of StrA, for VAL and INPUT.
;;
;; The string is ended with a zero, so that the number reader stops there, and PTRB is pointed at it while it is read.
;; Leading spaces and a + or - sign are allowed; a minus negates the number read.
;; In: STRING_BUFFER, STRING_LENGTH = the string
;; Out: A = EXPRESSION_TYPE = &40 for an integer in INT_A, or &FF for a real in FP_A
;; Keeps: PTR_B, PTR_B_OFFSET
STRING_TO_NUMBER:
    ldy STRING_LENGTH
    lda #$00
    sta STRING_BUFFER,y
    lda PTR_B
    pha
    lda PTR_B+1
    pha
    lda PTR_B_OFFSET
    pha
    lda #$00
    sta PTR_B_OFFSET
    lda #<STRING_BUFFER
    sta PTR_B
    lda #>STRING_BUFFER
    sta PTR_B+1
    jsr GET_CHARACTER_B
    cmp #'-'
    beq STRING_TO_NUMBER_MINUS
    cmp #'+'
    bne STRING_TO_NUMBER_READ
    jsr GET_CHARACTER_B
STRING_TO_NUMBER_READ:
    dec PTR_B_OFFSET
    jsr READ_NUMBER
    jmp STRING_TO_NUMBER_DONE
STRING_TO_NUMBER_MINUS:
    jsr GET_CHARACTER_B
    dec PTR_B_OFFSET
    jsr READ_NUMBER
    bcc STRING_TO_NUMBER_DONE       ; no number: zero
    jsr UNARY_MINUS_NEGATE
STRING_TO_NUMBER_DONE:
    sta EXPRESSION_TYPE
    jmp EVAL_RESTORE_PTR_B

;; INT: gives the largest integer not greater than a number: INT(n), so INT(-1.5) is -2.
;;
;; A real number is split into its integer part and its fraction; a negative number with a fraction is then one less.
;; Out: INT_A = the integer, A = &40 (an integer)
;; Errors: "Type mismatch" for a string
INT_FUNCTION:
    jsr EVALUATE_FACTOR
    beq INT_TYPE_MISMATCH
    bpl INT_RETURN                  ; already an integer
    lda FP_A_SIGN
    php
    jsr REAL_TO_FIXED
    plp
    bpl INT_TO_INT_A
    lda FP_B_MANTISSA               ; the fraction
    ora FP_B_MANTISSA+1
    ora FP_B_MANTISSA+2
    ora FP_B_MANTISSA+3
    beq INT_TO_INT_A
    jsr DECREMENT_MANTISSA
INT_TO_INT_A:
    jsr FIXED_TO_INT_A
    lda #$40
INT_RETURN:
    rts

;; Raises "Type mismatch", for VAL, INT, ASC and INSTR(; a jump within branch reach.
INT_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; ASC: gives the ASCII code of the first character of a string: ASC(string), or -1 for an empty string.
;; Out: INT_A = the code, A = &40 (an integer)
;; Errors: "Type mismatch" when the argument is not a string
;; Entry: ASC_RETURN = gives the integer in A
ASC_FUNCTION:
    jsr EVALUATE_FACTOR
    bne INT_TYPE_MISMATCH
    lda STRING_LENGTH
    beq TRUE_FUNCTION
    lda STRING_BUFFER
ASC_RETURN:
    jmp LOAD_INT_A_BYTE

;; INKEY: waits a time for a key, or tests a key: INKEY(n).
;;
;; With n from 0 to 32767, it waits up to n hundredths of a second and gives the key's ASCII code, or -1 when no key
;; was pressed. With n negative, it tests the key whose internal number is -n, giving -1 (TRUE) when it is pressed
;; and 0 when it is not.
;; Out: INT_A = the key or the result, A = &40 (an integer)
;; See: <READ_INKEY>
INKEY_FUNCTION:
    jsr READ_INKEY
    cpy #$00
    bne TRUE_FUNCTION               ; timed out, or a key scan found the key
    txa
    jmp LOAD_INT_A_WORD             ; Y = 0

;; EOF: tells whether the end of an open file has been reached: EOF#channel.
;; Out: INT_A = -1 (TRUE) at the end, 0 (FALSE) otherwise, A = &40 (an integer)
EOF_FUNCTION:
    jsr READ_HANDLE_B
    tax
    lda #OSBYTE_CHECK_EOF
    jsr OSBYTE
    txa
    beq ASC_RETURN                  ; X = 0: not at the end, so 0

;; TRUE: gives -1, the value of a true condition.
;;
;; The other functions jump here for -1.
;; Out: INT_A = -1, A = &40 (an integer)
TRUE_FUNCTION:
    lda #$FF
    sta INT_A
    sta INT_A+1
    sta INT_A+2
    sta INT_A+3
    lda #TYPE_INTEGER
    rts

;; NOT: gives the bitwise inverse of an integer: NOT n, so NOT TRUE is FALSE.
;; Out: INT_A = the inverse, A = &40 (an integer)
NOT_FUNCTION:
    jsr EVALUATE_INTEGER_FACTOR
    ldx #$03
NOT_FUNCTION_LOOP:
    lda INT_A,x
    eor #$FF
    sta INT_A,x
    dex
    bpl NOT_FUNCTION_LOOP
    lda #TYPE_INTEGER
    rts

;; INSTR(: finds one string in another: INSTR(string, search [, start]).
;;
;; It gives the position, counting from 1, of the first copy of the search string at or after the start position
;; (1 if left out, and 0 is taken as 1), or 0 if there is none. An empty search string is found at the start
;; position. The string searched is kept on BASIC's stack, the search string in StrA, and IntA holds the position
;; being tried (INT_A), the number of positions left to try (INT_A+1) and the start less one (INT_A+3); WORK points
;; to the characters being compared.
;; Out: INT_A = the position, or 0, A = &40 (an integer)
;; Uses: WORK
;; Errors: "Type mismatch" when either string is not a string, "Missing ," and "Missing )"
INSTR_FUNCTION:
    jsr EVALUATE_EXPRESSION
    bne INT_TYPE_MISMATCH
    cpx #','
    bne INSTR_MISSING_COMMA
    inc PTR_B_OFFSET
    jsr PUSH_STRING
    jsr EVALUATE_EXPRESSION
    bne INT_TYPE_MISMATCH
    lda #$01                        ; the start position if none is given
    sta INT_A
    inc PTR_B_OFFSET
    cpx #')'
    beq INSTR_SEARCH
    cpx #','
    beq INSTR_START
INSTR_MISSING_COMMA:
    jmp MISSING_COMMA_ERROR
INSTR_START:
    jsr PUSH_STRING
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
    jsr POP_STRING
INSTR_SEARCH:
    ldy #$00
    ldx INT_A
    bne INSTR_SET_START
    ldx #$01
INSTR_SET_START:
    stx INT_A
    txa
    dex
    stx INT_A+3
    clc
    adc BASIC_STACK                 ; WORK = the character at the start position
    sta WORK
    tya
    adc BASIC_STACK+1
    sta WORK+1
    lda (BASIC_STACK),y             ; the length of the string searched
    sec
    sbc INT_A+3
    bcc INSTR_TOO_SHORT
    sbc STRING_LENGTH
    bcc INSTR_TOO_SHORT
    adc #$00                        ; carry is set: the number of positions to try
    sta INT_A+1
    jsr DROP_STRING
INSTR_TRY_POSITION:
    ldy #$00
    ldx STRING_LENGTH
    beq INSTR_FOUND
INSTR_COMPARE:
    lda (WORK),y
    cmp STRING_BUFFER,y
    bne INSTR_NEXT_POSITION
    iny
    dex
    bne INSTR_COMPARE
INSTR_FOUND:
    lda INT_A
INSTR_RETURN:
    jmp LOAD_INT_A_BYTE
INSTR_TOO_SHORT:
    jsr DROP_STRING
INSTR_NOT_FOUND:
    lda #$00
    beq INSTR_RETURN                ; always taken
INSTR_NEXT_POSITION:
    inc INT_A
    dec INT_A+1
    beq INSTR_NOT_FOUND
    inc WORK
    bne INSTR_TRY_POSITION
    inc WORK+1
    bne INSTR_TRY_POSITION          ; always taken

;; Raises "Type mismatch", for ABS and unary minus; a jump within branch reach.
ABS_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; ABS: gives the absolute value of a number: ABS(n).
;; Out: A = &40 with INT_A = the value, or A = &FF with FP_A = the value
;; Errors: "Type mismatch" for a string
ABS_FUNCTION:
    jsr EVALUATE_FACTOR
    beq ABS_TYPE_MISMATCH
    bmi ABS_REAL

;; Makes the integer in IntA positive.
;; In: INT_A = the integer
;; Out: INT_A = its absolute value, A = &40 (an integer)
;; Uses: Y
ABS_INT_A:
    bit INT_A+3
    bmi NEGATE_INT_A
    bpl NEGATE_INT_A_DONE           ; always taken

;; ABS of a real number: clears FPA's sign.
ABS_REAL:
    jsr TEST_FP_A
    bpl NEGATE_FP_A_DONE            ; zero or positive already
    bmi NEGATE_FP_A_FLIP            ; always taken

;; Negates the real number in FPA, leaving zero alone.
;; In: FP_A = the number
;; Out: FP_A = its negative, A = &FF (a real)
;; Entry: NEGATE_FP_A_FLIP = changes the sign without testing for zero, NEGATE_FP_A_DONE = only returns &FF
NEGATE_FP_A:
    jsr TEST_FP_A
    beq NEGATE_FP_A_DONE
NEGATE_FP_A_FLIP:
    lda FP_A_SIGN
    eor #$80
    sta FP_A_SIGN
NEGATE_FP_A_DONE:
    lda #TYPE_REAL
    rts

;; Unary minus: evaluates the factor after a minus sign and negates it.
;; Out: A = &40 with INT_A = the value, or A = &FF with FP_A = the value
;; Errors: "Type mismatch" for a string
;; Entry: UNARY_MINUS_NEGATE = negates the number whose type is in A (STRING_TO_NUMBER uses it)
UNARY_MINUS:
    jsr EVALUATE_FACTOR_NEXT
UNARY_MINUS_NEGATE:
    beq ABS_TYPE_MISMATCH
    bmi NEGATE_FP_A

;; Negates the integer in IntA.
;; In: INT_A = the integer
;; Out: INT_A = its negative, A = &40 (an integer)
;; Uses: Y
;; Entry: NEGATE_INT_A_DONE = only returns &40
NEGATE_INT_A:
    sec
    lda #$00
    tay
    sbc INT_A
    sta INT_A
    tya
    sbc INT_A+1
    sta INT_A+1
    tya
    sbc INT_A+2
    sta INT_A+2
    tya
    sbc INT_A+3
    sta INT_A+3
NEGATE_INT_A_DONE:
    lda #TYPE_INTEGER
    rts

;; Reads a string item for READ and INPUT into StrA: a quoted string, or the characters up to a comma or the end of
;; the line.
;;
;; Spaces before the item are skipped. An item without quotes keeps everything else, spaces after it included, and
;; leaves PTRB's offset at the comma or carriage return that ends it.
;; In: PTR_B, PTR_B_OFFSET = the item
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string), PTR_B_OFFSET = after the item
;; Uses: X, Y
;; Errors: "Missing "" for a quoted string with no closing quote
;; See: <READ_QUOTED_STRING>
READ_STRING_ITEM:
    jsr GET_CHARACTER_B
    cmp #'"'
    beq READ_QUOTED_STRING
    ldx #$00
READ_STRING_ITEM_LOOP:
    lda (PTR_B),y
    sta STRING_BUFFER,x
    iny
    inx
    cmp #CARRIAGE_RETURN
    beq READ_STRING_ITEM_END
    cmp #','
    bne READ_STRING_ITEM_LOOP
READ_STRING_ITEM_END:
    dey                             ; back to the comma or carriage return
    jmp READ_QUOTED_STRING_DONE     ; which DEX then drops from the string

;; Reads a quoted string into StrA, where two quotes in a row stand for one.
;; In: PTR_B = the text, Y = the offset of the opening quote
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string), PTR_B_OFFSET = after the closing quote
;; Uses: X, Y
;; Errors: "Missing "" when the line ends before the closing quote
;; Entry: READ_QUOTED_STRING_DONE = sets the length to X - 1 and PTRB's offset to Y
READ_QUOTED_STRING:
    ldx #$00
READ_QUOTED_STRING_SKIP:
    iny
READ_QUOTED_STRING_LOOP:
    lda (PTR_B),y
    cmp #CARRIAGE_RETURN
    beq READ_QUOTED_STRING_MISSING
    iny
    sta STRING_BUFFER,x
    inx
    cmp #'"'
    bne READ_QUOTED_STRING_LOOP
    lda (PTR_B),y
    cmp #'"'
    beq READ_QUOTED_STRING_SKIP     ; "" keeps one quote and skips the other
READ_QUOTED_STRING_DONE:
    dex                             ; drop the closing quote
    stx STRING_LENGTH
    sty PTR_B_OFFSET
    lda #TYPE_STRING
    rts
READ_QUOTED_STRING_MISSING:
    jmp MISSING_QUOTE_ERROR

;; Evaluates one factor of an expression at PTRB: a number, a variable, a bracketed expression, a hexadecimal number
;; after &, a quoted string, a minus or plus sign and the factor after it, or a function.
;;
;; Spaces before the factor are skipped. The tokens from OPENIN to EOF (&8E-&C5) are functions, run through the table
;; of the routines each token runs; any other token is "No such variable". A character from . to > starts a number,
;; and anything else not handled is taken as a variable, the indirection operators ?, ! and $ included.
;;
;; A variable that does not exist is an error, unless bit 1 of OPT is clear and the name is a valid one: that is the
;; assembler's first pass, with errors off, where a label not yet defined is given the value of P%.
;; In: PTR_B, PTR_B_OFFSET = the factor
;; Out: A = the type: &00 (zero set) for a string in StrA, &40 for an integer in IntA, &FF (negative set) for a real
;;   in FPA; PTR_B_OFFSET = after the factor
;; Errors: "No such variable", "Missing )", "Bad HEX", "Missing "" and the functions' own errors
;; Entry: EVALUATE_FACTOR_NEXT = reads the next character with GET_CHARACTER_B first, EVALUATE_FACTOR_DISPATCH =
;;   evaluates the factor starting with the character in A
EVALUATE_FACTOR:
    ldy PTR_B_OFFSET
    inc PTR_B_OFFSET
    lda (PTR_B),y
    cmp #' '
    beq EVALUATE_FACTOR
    cmp #'-'
    beq UNARY_MINUS
    cmp #'"'
    beq READ_QUOTED_STRING
    cmp #'+'
    bne EVALUATE_FACTOR_DISPATCH
EVALUATE_FACTOR_NEXT:
    jsr GET_CHARACTER_B
EVALUATE_FACTOR_DISPATCH:
    cmp #TOKEN_OPENIN               ; the first function token
    bcc EVALUATE_FACTOR_NOT_FUNCTION
    cmp #TOKEN_AUTO                 ; the first token after the functions
    bcs NO_SUCH_VARIABLE
    jmp DISPATCH_TOKEN
EVALUATE_FACTOR_NOT_FUNCTION:
    cmp #'?'
    bcs EVALUATE_FACTOR_VARIABLE    ; ?, @, letters and the other tokens
    cmp #'.'
    bcs EVALUATE_FACTOR_NUMBER      ; . / 0-9 : ; < = >
    cmp #'&'
    beq READ_HEX_NUMBER
    cmp #'('
    beq EVALUATE_TO_CLOSE_BRACKET
EVALUATE_FACTOR_VARIABLE:
    dec PTR_B_OFFSET
    jsr FIND_VARIABLE
    beq EVALUATE_FACTOR_UNKNOWN
    jmp READ_VARIABLE
EVALUATE_FACTOR_NUMBER:
    jsr READ_NUMBER
    bcc NO_SUCH_VARIABLE            ; not a number after all
    rts
EVALUATE_FACTOR_UNKNOWN:
    lda OPT
    and #%00000010                  ; reporting errors?
    bne NO_SUCH_VARIABLE
    bcs NO_SUCH_VARIABLE            ; not a valid name
    stx PTR_B_OFFSET                ; skip the name

;; Loads IntA with P%, the assembler's program counter.
;;
;; The assembler uses it to give a label its value; <EVALUATE_FACTOR> falls into it for an unknown variable in the
;; assembler's first pass.
;; Out: INT_A = P%, A = &40 (an integer)
LOAD_P_PERCENT:
    lda P_PERCENT
    ldy P_PERCENT+1
    jmp LOAD_INT_A_WORD

;; Raises error 26, "No such variable".
NO_SUCH_VARIABLE:
    brk
    .byte ERROR_NO_SUCH_VARIABLE
    .byte "No such variable",0

;; Evaluates an expression that must be followed by a closing bracket, and steps past the bracket.
;;
;; <EVALUATE_FACTOR> uses it for a bracketed expression, and the functions for their last argument. TAY sets the
;; flags from the type again after INC and CPX have changed them.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out: A = Y = the type, zero = a string, negative = a real; PTR_B_OFFSET = after the bracket
;; Errors: error 27, "Missing )", and any error in the expression
EVALUATE_TO_CLOSE_BRACKET:
    jsr EVALUATE_EXPRESSION
    inc PTR_B_OFFSET
    cpx #')'
    bne EVALUATE_TO_CLOSE_BRACKET_MISSING
    tay
    rts
EVALUATE_TO_CLOSE_BRACKET_MISSING:
    brk
    .byte ERROR_MISSING_BRACKET
    .byte "Missing )",0

;; Reads a hexadecimal number after &, of up to eight digits 0-9 and A-F, into IntA.
;;
;; Each digit is shifted into IntA from the bottom; X becomes negative once a digit has been read, so an & with no
;; digits after it is an error.
;; In: PTR_B, PTR_B_OFFSET = the first digit
;; Out: INT_A = the number, A = &40 (an integer), PTR_B_OFFSET = after the digits
;; Uses: X, Y
;; Errors: error 28, "Bad HEX", when there is no digit
READ_HEX_NUMBER:
    ldx #$00
    stx INT_A
    stx INT_A+1
    stx INT_A+2
    stx INT_A+3
    ldy PTR_B_OFFSET
READ_HEX_NUMBER_LOOP:
    lda (PTR_B),y
    cmp #'0'
    bcc READ_HEX_NUMBER_END
    cmp #'9'+1
    bcc READ_HEX_NUMBER_DIGIT
    sbc #'A'-10                     ; carry is set: A-F become 10-15
    cmp #10
    bcc READ_HEX_NUMBER_END
    cmp #16
    bcs READ_HEX_NUMBER_END
READ_HEX_NUMBER_DIGIT:
    asl a                           ; the digit to the top four bits
    asl a
    asl a
    asl a
    ldx #$03
READ_HEX_NUMBER_SHIFT:
    asl a
    rol INT_A
    rol INT_A+1
    rol INT_A+2
    rol INT_A+3
    dex
    bpl READ_HEX_NUMBER_SHIFT
    iny
    bne READ_HEX_NUMBER_LOOP
READ_HEX_NUMBER_END:
    txa
    bpl READ_HEX_NUMBER_BAD         ; X = 0: no digits
    sty PTR_B_OFFSET
    lda #TYPE_INTEGER
    rts
READ_HEX_NUMBER_BAD:
    brk
    .byte ERROR_BAD_HEX
    .byte "Bad HEX",0

;; TIME: gives the system clock, in hundredths of a second.
;;
;; OSWORD 1 reads the clock's five bytes into IntA and the byte after it; the low four are the result.
;; Out: INT_A = the time, A = &40 (an integer)
;; Uses: FP_A_SIGN (the clock's fifth byte)
TIME_FUNCTION:
    ldx #INT_A
    ldy #$00
    lda #OSWORD_READ_CLOCK
    jsr OSWORD
    lda #TYPE_INTEGER
    rts

;; PAGE: gives the address where the program starts.
;; Out: INT_A = PAGE, A = &40 (an integer)
PAGE_FUNCTION:
    lda #$00
    ldy PAGE_HIGH
    jmp LOAD_INT_A_WORD

;; Raises "No such variable", for TOP when TO is not followed by P; a jump within branch reach.
TOP_NO_SUCH_VARIABLE:
    jmp NO_SUCH_VARIABLE

;; FALSE: gives 0, the value of a false condition.
;; Out: INT_A = 0, A = &40 (an integer)
FALSE_FUNCTION:
    lda #$00
    beq LOAD_INT_A_BYTE             ; always taken

;; Raises "Type mismatch", for LEN; a jump within branch reach.
LEN_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; LEN: gives the length of a string: LEN(string).
;; Out: INT_A = the length, A = &40 (an integer)
;; Errors: "Type mismatch" when the argument is not a string
LEN_FUNCTION:
    jsr EVALUATE_FACTOR
    bne LEN_TYPE_MISMATCH
    lda STRING_LENGTH

;; Loads IntA with the byte in A, from 0 to 255.
;; In: A = the number
;; Out: INT_A = the number, A = &40 (an integer)
;; Uses: Y
LOAD_INT_A_BYTE:
    ldy #$00
    beq LOAD_INT_A_WORD             ; always taken

;; TOP: gives the address of the end of the program.
;;
;; TOP has no token of its own: it is tokenised as TO (&B8) followed by P, so the routine for TO in an expression
;; checks that a P follows and steps past it.
;; Out: INT_A = TOP, A = &40 (an integer)
;; Errors: "No such variable" when TO is not followed by P
TOP_FUNCTION:
    ldy PTR_B_OFFSET
    lda (PTR_B),y
    cmp #'P'
    bne TOP_NO_SUCH_VARIABLE
    inc PTR_B_OFFSET
    lda TOP
    ldy TOP+1

;; Loads IntA with a 16-bit number from A and Y.
;; In: A = the low byte, Y = the high byte
;; Out: INT_A = the number, A = &40 (an integer)
LOAD_INT_A_WORD:
    sta INT_A
    sty INT_A+1
    lda #$00
    sta INT_A+2
    sta INT_A+3
    lda #TYPE_INTEGER
    rts

;; COUNT: gives the number of characters printed since the last new line.
;; Out: INT_A = COUNT, A = &40 (an integer)
COUNT_FUNCTION:
    lda COUNT
    jmp LOAD_INT_A_BYTE

;; LOMEM: gives the address where the variables start.
;; Out: INT_A = LOMEM, A = &40 (an integer)
LOMEM_FUNCTION:
    lda LOMEM
    ldy LOMEM+1
    jmp LOAD_INT_A_WORD

;; HIMEM: gives the address of the top of the memory BASIC uses.
;; Out: INT_A = HIMEM, A = &40 (an integer)
HIMEM_FUNCTION:
    lda HIMEM
    ldy HIMEM+1
    jmp LOAD_INT_A_WORD

;; RND(n): a random number with an argument.
;;
;; - n negative seeds the generator with n and gives n.
;; - n = 0 gives the last random number again, as a real between 0 and 1.
;; - n = 1 gives a new random real between 0 and 1.
;; - n > 1 gives a random integer from 1 to n: a new random real times n, plus one.
;; Out: A = &40 with INT_A = the number, or A = &FF with FP_A = the number
;; Errors: "Missing )"
RND_BRACKET:
    inc PTR_B_OFFSET
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
    lda INT_A+3
    bmi RND_SEED
    ora INT_A+2
    ora INT_A+1
    bne RND_RANGE
    lda INT_A
    beq RANDOM_REAL_CURRENT
    cmp #$01
    beq RANDOM_REAL
RND_RANGE:
    jsr INTEGER_TO_REAL
    jsr PUSH_REAL
    jsr RANDOM_REAL
    jsr POP_REAL_POINTER
    jsr MULTIPLY_FP_A_UNNORMALISED
    jsr NORMALISE_FP_A
    jsr REAL_TO_INTEGER
    jsr INCREMENT_INT_A
    lda #TYPE_INTEGER
    rts
RND_SEED:
    ldx #RANDOM
    jsr STORE_INT_A
    lda #$40                        ; sets the generator's 33rd bit
    sta RANDOM+4
    rts

;; RND: gives a random number: a random integer for RND alone, or what RND(n) gives.
;;
;; Without an argument, it steps the generator and returns its low 32 bits.
;; Out: A = &40 with INT_A = the number, or A = &FF with FP_A = the number
;; See: <RND_BRACKET>, <NEXT_RANDOM>
RND_FUNCTION:
    ldy PTR_B_OFFSET
    lda (PTR_B),y
    cmp #'('
    beq RND_BRACKET
    jsr NEXT_RANDOM
    ldx #RANDOM                     ; and fall into LOAD_INT_A

;; Loads IntA from four bytes of zero page.
;; In: X = the address of the low byte
;; Out: INT_A = the number, A = &40 (an integer)
LOAD_INT_A:
    lda $00,x
    sta INT_A
    lda $01,x
    sta INT_A+1
    lda $02,x
    sta INT_A+2
    lda $03,x
    sta INT_A+3
    lda #TYPE_INTEGER
    rts

;; Steps the random number generator and gives its value as a real number from 0 to 1.
;;
;; FPA's mantissa is the generator's low four bytes, the lowest first as the most significant, with an exponent of
;; &80; normalising and rounding then make it a proper number below 1.
;; Out: FP_A = the number, A = &FF (a real)
;; Uses: X, Y
;; Entry: RANDOM_REAL_CURRENT = gives the current value without stepping the generator, for RND(0)
RANDOM_REAL:
    jsr NEXT_RANDOM
RANDOM_REAL_CURRENT:
    ldx #$00
    stx FP_A_SIGN
    stx FP_A_OVERFLOW
    stx FP_A_ROUNDING
    lda #$80
    sta FP_A_EXPONENT
RANDOM_REAL_COPY:
    lda RANDOM,x
    sta FP_A_MANTISSA,x
    inx
    cpx #$04
    bne RANDOM_REAL_COPY
    jsr NORMALISE_AND_ROUND_FP_A
    lda #TYPE_REAL
    rts

;; Steps the random number generator 32 times.
;;
;; The generator is a 33-bit shift register at RANDOM, low byte first, its 33rd bit in bit 0 of RANDOM+4. Each step
;; shifts it left by one, feeding in bit 19 exclusive-ORed with bit 32.
;; Uses: A, Y, RANDOM..RANDOM+4
;; Keeps: X
NEXT_RANDOM:
    ldy #32
NEXT_RANDOM_LOOP:
    lda RANDOM+2                    ; bit 19 to bit 0
    lsr a
    lsr a
    lsr a
    eor RANDOM+4                    ; with bit 32
    ror a                           ; into the carry
    rol RANDOM
    rol RANDOM+1
    rol RANDOM+2
    rol RANDOM+3
    rol RANDOM+4
    dey
    bne NEXT_RANDOM_LOOP
    rts

;; ERL: gives the number of the line where the last error happened.
;; Out: INT_A = ERL, A = &40 (an integer)
ERL_FUNCTION:
    ldy ERL+1
    lda ERL
    jmp LOAD_INT_A_WORD

;; ERR: gives the number of the last error.
;;
;; The number is the byte after the BRK, which the MOS's error pointer at &FD points to.
;; Out: INT_A = the error number, A = &40 (an integer)
ERR_FUNCTION:
    ldy #$00
    lda (ERROR_POINTER),y
    jmp LOAD_INT_A_WORD

;; Evaluates INKEY's argument and calls OSBYTE &81 with it, for INKEY and INKEY$.
;; Out: Y = 0 with X = the key; Y = &FF when no key came in time; Y = &1B on ESCAPE; for a negative argument
;;   X = Y = &FF when the key is pressed and 0 when it is not
READ_INKEY:
    jsr EVALUATE_INTEGER_FACTOR
    lda #OSBYTE_INKEY
    ldx INT_A
    ldy INT_A+1
    jmp OSBYTE

;; GET: waits for a key and gives its ASCII code.
;; Out: INT_A = the code, A = &40 (an integer)
GET_FUNCTION:
    jsr OSRDCH
    jmp LOAD_INT_A_BYTE

;; GET$: waits for a key and gives it as a string of one character.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
GET_STR_FUNCTION:
    jsr OSRDCH

;; Makes StrA a string of one character.
;; In: A = the character
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
MAKE_CHARACTER_STRING:
    sta STRING_BUFFER
    lda #$01
    sta STRING_LENGTH
    lda #TYPE_STRING
    rts

;; LEFT$(: gives the first characters of a string: LEFT$(string, n), or the whole string when n is its length or
;; more.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Errors: "Type mismatch", "Missing ," and "Missing )"
LEFT_STR_FUNCTION:
    jsr EVALUATE_EXPRESSION
    bne LEFT_STR_TYPE_MISMATCH
    cpx #','
    bne LEFT_STR_MISSING_COMMA
    inc PTR_B_OFFSET
    jsr PUSH_STRING
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
    jsr POP_STRING
    lda INT_A
    cmp STRING_LENGTH
    bcs LEFT_STR_RETURN
    sta STRING_LENGTH
LEFT_STR_RETURN:
    lda #TYPE_STRING
    rts

;; RIGHT$(: gives the last characters of a string: RIGHT$(string, n), or the whole string when n is its length or
;; more.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Errors: "Type mismatch", "Missing ," and "Missing )"
RIGHT_STR_FUNCTION:
    jsr EVALUATE_EXPRESSION
    bne LEFT_STR_TYPE_MISMATCH
    cpx #','
    bne LEFT_STR_MISSING_COMMA
    inc PTR_B_OFFSET
    jsr PUSH_STRING
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
    jsr POP_STRING
    lda STRING_LENGTH
    sec
    sbc INT_A
    bcc RIGHT_STR_WHOLE             ; n is longer than the string
    beq RIGHT_STR_RETURN            ; n is the length: A = 0
    tax                             ; the offset of the first character kept
    lda INT_A
    sta STRING_LENGTH
    beq RIGHT_STR_RETURN            ; n = 0: an empty string, A = 0
    ldy #$00
RIGHT_STR_LOOP:
    lda STRING_BUFFER,x
    sta STRING_BUFFER,y
    inx
    iny
    dec INT_A
    bne RIGHT_STR_LOOP
RIGHT_STR_WHOLE:
    lda #$00
RIGHT_STR_RETURN:
    rts

;; INKEY$: waits a time for a key: INKEY$(n), giving the key as a string of one character, or an empty string when
;; none was pressed in n hundredths of a second.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; See: <READ_INKEY>
INKEY_STR_FUNCTION:
    jsr READ_INKEY
    txa
    cpy #$00
    beq MAKE_CHARACTER_STRING

;; Makes StrA empty.
;; Out: STRING_LENGTH = 0, A = 0 (a string)
MAKE_EMPTY_STRING:
    lda #$00
    sta STRING_LENGTH
    rts

;; Raises "Type mismatch", for LEFT$(, RIGHT$( and MID$(; a jump within branch reach.
LEFT_STR_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Raises "Missing ,", for LEFT$(, RIGHT$( and MID$(; a jump within branch reach.
LEFT_STR_MISSING_COMMA:
    jmp MISSING_COMMA_ERROR

;; MID$(: gives part of a string: MID$(string, start [, n]).
;;
;; It gives n characters from the start position, counting from 1 (0 is taken as 1), or all of them to the end when
;; n is left out or more than there are. A start past the end gives an empty string.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Uses: INT_A+2 (the offset of the start)
;; Errors: "Type mismatch", "Missing ," and "Missing )"
MID_STR_FUNCTION:
    jsr EVALUATE_EXPRESSION
    bne LEFT_STR_TYPE_MISMATCH
    cpx #','
    bne LEFT_STR_MISSING_COMMA
    jsr PUSH_STRING
    inc PTR_B_OFFSET
    jsr EVALUATE_INTEGER
    lda INT_A                       ; the start
    pha
    lda #$FF                        ; the length if none is given
    sta INT_A
    inc PTR_B_OFFSET
    cpx #')'
    beq MID_STR_SLICE
    cpx #','
    bne LEFT_STR_MISSING_COMMA
    jsr EVALUATE_TO_CLOSE_BRACKET
    jsr CONVERT_A_TO_INTEGER
MID_STR_SLICE:
    jsr POP_STRING
    pla
    tay
    clc
    beq MID_STR_OFFSET              ; a start of 0 is taken as 1
    sbc STRING_LENGTH               ; carry is clear: start - 1 - length
    bcs MAKE_EMPTY_STRING           ; the start is past the end
    dey
    tya
MID_STR_OFFSET:
    sta INT_A+2
    tax
    ldy #$00
    lda STRING_LENGTH
    sec
    sbc INT_A+2                     ; the characters from the start to the end
    cmp INT_A
    bcs MID_STR_COPY
    sta INT_A
MID_STR_COPY:
    lda INT_A
    beq MAKE_EMPTY_STRING
MID_STR_LOOP:
    lda STRING_BUFFER,x
    sta STRING_BUFFER,y
    iny
    inx
    cpy INT_A
    bne MID_STR_LOOP
    sty STRING_LENGTH
    lda #TYPE_STRING
    rts

;; STR$: converts a number to a string: STR$ n, or STR$~ n for hexadecimal.
;;
;; The string is the number as PRINT would show it, without the field width: in @%'s format when @%'s top byte is
;; not zero, otherwise in the general format with up to ten digits.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Uses: PRINT_HEX, WORK, WORK+1
;; Errors: "Type mismatch" for a string
;; See: <NUMBER_TO_STRING>
STR_STR_FUNCTION:
    jsr GET_CHARACTER_B
    ldy #$FF                        ; hexadecimal
    cmp #'~'
    beq STR_STR_EVALUATE
    ldy #$00
    dec PTR_B_OFFSET
STR_STR_EVALUATE:
    tya
    pha
    jsr EVALUATE_FACTOR
    beq STR_STR_TYPE_MISMATCH
    tay                             ; the type, for NUMBER_TO_STRING
    pla
    sta PRINT_HEX
    lda STR_USES_AT_PERCENT
    bne STR_STR_AT_PERCENT
    sta WORK                        ; the general format
    jsr NUMBER_TO_STRING_TEN_DIGITS                       ; with ten digits
    lda #TYPE_STRING
    rts
STR_STR_AT_PERCENT:
    jsr NUMBER_TO_STRING
    lda #TYPE_STRING
    rts

;; Raises "Type mismatch", for STR$ and STRING$(; a jump within branch reach.
STR_STR_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; STRING$(: gives copies of a string joined together: STRING$(n, string).
;;
;; The string is copied after itself in StrA n - 1 times; n = 0 gives an empty string.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Errors: "Type mismatch", "Missing ,", "Missing )" and "String too long" when the result is over 255 characters
STRING_STR_FUNCTION:
    jsr EVALUATE_INTEGER
    jsr PUSH_INTEGER
    jsr CHECK_COMMA_B
    jsr EVALUATE_TO_CLOSE_BRACKET
    bne STR_STR_TYPE_MISMATCH
    jsr POP_INTEGER
    ldy STRING_LENGTH
    beq STRING_STR_DONE             ; an empty string stays empty
    lda INT_A
    beq STRING_STR_EMPTY
    dec INT_A
    beq STRING_STR_DONE             ; one copy: StrA already holds it
STRING_STR_COPY:
    ldx #$00
STRING_STR_LOOP:
    lda STRING_BUFFER,x
    sta STRING_BUFFER,y
    inx
    iny
    beq STRING_STR_TOO_LONG
    cpx STRING_LENGTH
    bcc STRING_STR_LOOP
    dec INT_A
    bne STRING_STR_COPY
    sty STRING_LENGTH
STRING_STR_DONE:
    lda #TYPE_STRING
    rts
STRING_STR_EMPTY:
    sta STRING_LENGTH
    rts
STRING_STR_TOO_LONG:
    jmp STRING_TOO_LONG_ERROR

;; Raises error 29, "No such FN/PROC", when the search for a DEF reaches the end of the program.
;;
;; PTRA is pulled back from the 6502 stack first, where <CALL_FN_PROC> left the caller's, so that the error is
;; reported at the line that made the call.
;; See: <FIND_FN_PROC_DEFINITION>
NO_SUCH_FN_PROC:
    pla
    sta PTR_A+1
    pla
    sta PTR_A
    brk
    .byte ERROR_NO_SUCH_FN_PROC
    .byte "No such ",TOKEN_FN,"/",TOKEN_PROC,0

; The addresses the BASIC ROM User Guide gives for these routines.
    .assert STRING_TO_NUMBER = $AC34, "STRING_TO_NUMBER moved."
    .assert ABS_INT_A = $AD71, "ABS_INT_A moved."
    .assert NEGATE_INT_A = $AD93, "NEGATE_INT_A moved."
    .assert LOAD_INT_A_BYTE = $AED8, "LOAD_INT_A_BYTE moved."
    .assert LOAD_INT_A_WORD = $AEEA, "LOAD_INT_A_WORD moved."
    .assert LOAD_INT_A = $AF56, "LOAD_INT_A moved."
