;; Line numbers, the end of a statement, IF, printing line numbers, finding lines, integer division and comparisons
;; ($97DD-$9B1C).
;;
;; - <GET_LINE_NUMBER> unpacks the three-byte line number that follows <TOKEN_LINE_NUMBER> in a program.
;; - <CHECK_END_OF_STATEMENT> checks that a statement ends where it should, at a colon, a carriage return or ELSE, and
;;   moves PTRA on to the next statement; <MOVE_TO_NEXT_STATEMENT> and <MOVE_TO_NEXT_LINE> step to the next
;;   statement or line, tracing line numbers when TRACE is on.
;; - <EVALUATE_EQUALS> evaluates the "= expression" that ends assignments to the pseudo-variables.
;; - <IF_STATEMENT>, <TRACE_LINE_NUMBER> and <PRINT_LINE_NUMBER>.
;; - <FIND_LINE>, which looks a line up in the program.
;; - <DIVIDE_INTEGERS>, the long division behind DIV and MOD, and <COMPARE_VALUES>, the comparison behind the
;;   relational operators.
;; - The "Mistake", "Syntax error", "Escape" and "Division by zero" errors.

; Error numbers.
ERROR_MISTAKE = $04                 ;; error 4, "Mistake": an assignment with no "="
ERROR_SYNTAX = $10                  ;; error 16, "Syntax error"
ERROR_ESCAPE = $11                  ;; error 17, "Escape": ESCAPE was pressed
ERROR_DIVISION_BY_ZERO = $12        ;; error 18, "Division by zero"

; The work bytes these routines give a purpose of their own.
FIND_LINE_POINTER = FP_B_EXPONENT   ;; <FIND_LINE>'s pointer into the program, two bytes
DIGIT_BUFFER = FP_B_MANTISSA + 1    ;; the digits of a number being printed, least significant first, up to eight
DIVIDE_QUOTIENT = WORK + 2          ;; the dividend, four bytes, shifted out as the quotient is shifted in
DIVIDE_REMAINDER = FP_B_EXPONENT    ;; the remainder of a division, four bytes, low byte first
RESULT_SIGN = WORK                  ;; bit 7 set when a product or quotient is negative
DIVIDEND_SIGN = WORK + 1            ;; bit 7 set when a dividend is negative, and so its remainder

;; Skips a space, then joins <GET_LINE_NUMBER> to look again.
GET_LINE_NUMBER_SPACE:
    inc PTR_A_OFFSET

;; Reads a line number packed after <TOKEN_LINE_NUMBER>, at PTRA, as GOTO, GOSUB, RESTORE and THEN have them.
;;
;; The tokeniser packs a line number into three bytes after the token, each in the range &40-&7F so that none of them
;; can be read as a token, a space or the end of a line. The first byte holds the top two bits of both bytes of the
;; number (the low byte's at bits 4-5, the high byte's at bits 2-3), and the second and third the low six bits of the
;; low and high bytes. Each byte has its bit 6 inverted against the others, which the exclusive ORs here undo.
;; In: PTR_A, PTR_A_OFFSET = the text, which may start with spaces
;; Out:
;;   carry = set when a line number was found, clear when the text does not start with one
;;   INT_A, INT_A+1 = the line number, when found; the top two bytes of IntA are not changed
;;   PTR_A_OFFSET = just past the line number, or at the first character after the spaces when there is none
;; Uses: A, X, Y
;; Entry: UNPACK_LINE_NUMBER = unpacks the line number whose token is at offset Y from PTRA
GET_LINE_NUMBER:
    ldy PTR_A_OFFSET
    lda (PTR_A),y
    cmp #' '
    beq GET_LINE_NUMBER_SPACE
    cmp #TOKEN_LINE_NUMBER
    bne GET_LINE_NUMBER_NONE
UNPACK_LINE_NUMBER:
    iny
    lda (PTR_A),y                   ; the first byte: the top two bits of each byte of the number
    asl a
    asl a
    tax                             ; keep it shifted twice: the high byte's top bits are two places further on
    and #%11000000                  ; the low byte's top two bits
    iny
    eor (PTR_A),y                   ; with the low byte's low six bits
    sta INT_A
    txa
    asl a
    asl a                           ; the high byte's top two bits, and nothing below them
    iny
    eor (PTR_A),y                   ; with the high byte's low six bits
    sta INT_A+1
    iny
    sty PTR_A_OFFSET
    sec
    rts
GET_LINE_NUMBER_NONE:
    clc
    rts

;; Copies PTRA to PTRB, then evaluates an "= expression" that must end the statement, as in PAGE=, TIME= and the
;; other pseudo-variables.
;;
;; It falls into <EVALUATE_EQUALS>.
;; In: PTR_A, PTR_A_OFFSET = the text just after the name assigned to
;; Out:
;;   EXPRESSION_TYPE = the value's type, with the value in the accumulators, as <EVALUATE_EXPRESSION> leaves them
;;   PTR_A = the end of the statement, with PTR_A_OFFSET = 1, just past it
;; Uses: all
EVALUATE_EQUALS_A:
    lda PTR_A
    sta PTR_B
    lda PTR_A+1
    sta PTR_B+1
    lda PTR_A_OFFSET
    sta PTR_B_OFFSET

;; Evaluates an "= expression" at PTRB that must end the statement, then moves PTRA to the next statement.
;;
;; Spaces may come before the "=". PTRB must have the same base as PTRA, as it does after <EVALUATE_EQUALS_A>, since
;; the end of the statement is found from PTRB's offset but read and stepped over at PTRA.
;; In: PTR_B, PTR_B_OFFSET = the text before the "="
;; Out:
;;   EXPRESSION_TYPE = the value's type, with the value in the accumulators, as <EVALUATE_EXPRESSION> leaves them
;;   PTR_A = the end of the statement, with PTR_A_OFFSET = 1, just past it
;; Uses: all
;; Errors: Mistake when there is no "=", Syntax error when the statement goes on after the expression, Escape
EVALUATE_EQUALS:
    ldy PTR_B_OFFSET
    inc PTR_B_OFFSET
    lda (PTR_B),y
    cmp #' '
    beq EVALUATE_EQUALS
    cmp #'='
    beq EVALUATE_EXPRESSION_AND_END

;; Raises error 4, "Mistake": an assignment's "=" is missing.
;;
;; Its message has no zero of its own: the BRK of <SYNTAX_ERROR>, which follows it, ends it.
MISTAKE_ERROR:
    brk
    .byte ERROR_MISTAKE
    .byte "Mistake"                 ; ended by the BRK that follows

;; Raises error 16, "Syntax error".
;;
;; Its message has no zero of its own: the BRK of <ESCAPE_ERROR>, which follows it, ends it. Its own BRK ends the
;; message of <MISTAKE_ERROR> before it.
SYNTAX_ERROR:
    brk
    .byte ERROR_SYNTAX
    .byte "Syntax error"            ; ended by the BRK that follows

;; Raises error 17, "Escape": ESCAPE was pressed.
;;
;; Its BRK is also the zero that ends the message of <SYNTAX_ERROR> before it.
;; See: <CHECK_ESCAPE>
ESCAPE_ERROR:
    brk
    .byte ERROR_ESCAPE
    .byte "Escape", 0

;; Reads the next character after spaces at PTRB, which must be "=".
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: A = the "=", PTR_B_OFFSET = just past it
;; Uses: Y
;; Errors: Mistake when the character is not "="
EXPECT_EQUALS:
    jsr GET_CHARACTER_B
    cmp #'='
    bne MISTAKE_ERROR
    rts

;; Evaluates an expression at PTRB that must end the statement, then moves PTRA to the next statement.
;;
;; It falls into <CHECK_END_OF_EXPRESSION>. As there, PTRB must have the same base as PTRA.
;; In: PTR_B, PTR_B_OFFSET = the expression
;; Out:
;;   EXPRESSION_TYPE = the value's type, with the value in the accumulators, as <EVALUATE_EXPRESSION> leaves them
;;   PTR_A = the end of the statement, with PTR_A_OFFSET = 1, just past it
;; Uses: all
;; Errors: Syntax error when the statement goes on after the expression, Escape
EVALUATE_EXPRESSION_AND_END:
    jsr EVALUATE_EXPRESSION

;; Checks that the character <EVALUATE_EXPRESSION> stopped at ends the statement, and moves PTRA on to the next.
;;
;; PTRB must have the same base as PTRA, since the character's offset at PTRB is added to PTRA. It joins
;; <CHECK_END_OF_STATEMENT> at its check of the character.
;; In: X = the character after the expression, PTR_B_OFFSET = its offset
;; Out: PTR_A = the character that ends the statement, PTR_A_OFFSET = 1, Y = 1
;; Uses: A
;; Errors: Syntax error when the character does not end a statement, Escape
CHECK_END_OF_EXPRESSION:
    txa
    ldy PTR_B_OFFSET
    jmp CHECK_END_OF_STATEMENT_DELIMITER

;; Checks that the statement ends at PTRB's offset, read from PTRA, and moves PTRA on to the next statement.
;;
;; PTRB must have the same base as PTRA.
;; In: PTR_B_OFFSET = the offset in the text at PTR_A to check, which may start with spaces
;; Out: PTR_A = the character that ends the statement, PTR_A_OFFSET = 1, Y = 1
;; Uses: A
;; Errors: Syntax error, Escape
CHECK_END_OF_STATEMENT_B:
    ldy PTR_B_OFFSET
    jmp CHECK_END_OF_STATEMENT_Y

;; Checks that the statement ends at PTRA, after any spaces, and moves PTRA on to the next statement.
;;
;; A statement ends at a colon, at the carriage return that ends the line, or at ELSE. PTRA's base is moved to the
;; character that ends the statement, and its offset set to 1, just past it. Every statement passes through here, so
;; it is also where a running program notices ESCAPE.
;; In: PTR_A, PTR_A_OFFSET = the text
;; Out:
;;   PTR_A = the character that ends the statement
;;   PTR_A_OFFSET = 1
;;   Y = 1
;; Uses: A
;; Errors: Syntax error when anything else comes first, Escape when ESCAPE has been pressed
;; Entry:
;;   CHECK_END_OF_STATEMENT_Y = checks from offset Y instead
;;   CHECK_END_OF_STATEMENT_DELIMITER = checks the character in A, at offset Y, without skipping spaces
;;   ADVANCE_PTR_A = moves PTRA's base on by Y, then sets the offset to 1 and checks for ESCAPE
;;   RESET_PTR_A_OFFSET = sets PTRA's offset to 1 and checks for ESCAPE
;;   CHECK_ESCAPE = raises the Escape error when ESCAPE has been pressed
CHECK_END_OF_STATEMENT:
    ldy PTR_A_OFFSET
CHECK_END_OF_STATEMENT_Y:
    dey
CHECK_END_OF_STATEMENT_SPACE:
    iny
    lda (PTR_A),y
    cmp #' '
    beq CHECK_END_OF_STATEMENT_SPACE
CHECK_END_OF_STATEMENT_DELIMITER:
    cmp #':'
    beq ADVANCE_PTR_A
    cmp #CARRIAGE_RETURN
    beq ADVANCE_PTR_A
    cmp #TOKEN_ELSE
    bne SYNTAX_ERROR
ADVANCE_PTR_A:
    clc
    tya
    adc PTR_A
    sta PTR_A
    bcc RESET_PTR_A_OFFSET
    inc PTR_A+1
RESET_PTR_A_OFFSET:
    ldy #$01
    sty PTR_A_OFFSET
CHECK_ESCAPE:
    bit ESCAPE_FLAG
    bmi ESCAPE_ERROR
MOVE_TO_NEXT_STATEMENT_DONE:
    rts

;; Moves PTRA to the next statement to run: the one after a colon, or the first of the next line.
;;
;; It checks the end of the current statement with <CHECK_END_OF_STATEMENT>. After a colon there is nothing more to
;; do. Otherwise the statement ended the line: in the input line, an immediate statement, that is the end of the
;; work and BASIC goes back to <IMMEDIATE_MODE>; in a program it falls into <MOVE_TO_NEXT_LINE>. ELSE is taken as the
;; end of the line, as the rest of a line after ELSE is not run.
;; In: PTR_A, PTR_A_OFFSET = the end of a statement, which may start with spaces
;; Out: PTR_A = the next statement's base, PTR_A_OFFSET = 1
;; Uses: A, X, Y
;; Errors: Syntax error, Escape
MOVE_TO_NEXT_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    dey
    lda (PTR_A),y                   ; the character that ended it
    cmp #':'
    beq MOVE_TO_NEXT_STATEMENT_DONE
    lda PTR_A+1
    cmp #>LINE_BUFFER
    beq MOVE_TO_NEXT_LINE_END_OF_PROGRAM    ; the end of an immediate line: back to the prompt

;; Moves PTRA to the start of the next line of the program, printing its number first when TRACE is on.
;;
;; In a program each line is held as a carriage return, the line number high byte first, a length and the text; the
;; program ends with a line number whose high byte has bit 7 set. At the end of the program BASIC goes back to
;; <IMMEDIATE_MODE>.
;; In: PTR_A, Y = the carriage return that ends the current line
;; Out: PTR_A = the next line's length byte, PTR_A_OFFSET = 1, the first character of its text
;; Uses: A, X, Y
;; Entry: MOVE_TO_NEXT_LINE_RETURN = an RTS that <TRACE_LINE_NUMBER> shares
MOVE_TO_NEXT_LINE:
    iny
    lda (PTR_A),y                   ; the next line number's high byte
    bmi MOVE_TO_NEXT_LINE_END_OF_PROGRAM
    lda TRACE_FLAG
    beq MOVE_TO_NEXT_LINE_ENTER
    tya
    pha
    iny
    lda (PTR_A),y                   ; the low byte
    pha
    dey
    lda (PTR_A),y                   ; the high byte
    tay
    pla
    jsr LOAD_INT_A_WORD                       ; IntA = the line number
    jsr TRACE_LINE_NUMBER
    pla
    tay
MOVE_TO_NEXT_LINE_ENTER:
    iny
    sec
    tya
    adc PTR_A                       ; past the line number to its length byte
    sta PTR_A
    bcc MOVE_TO_NEXT_LINE_1
    inc PTR_A+1
MOVE_TO_NEXT_LINE_1:
    ldy #$01
    sty PTR_A_OFFSET
MOVE_TO_NEXT_LINE_RETURN:
    rts
MOVE_TO_NEXT_LINE_END_OF_PROGRAM:
    jmp IMMEDIATE_MODE

;; Raises Type mismatch for <IF_STATEMENT>, from within reach of its branch.
IF_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; IF: runs the rest of the line when a condition is true, or the part after ELSE when it is false.
;;
;; The syntax is IF condition [THEN] statements [ELSE statements], where a line number may stand for the statements
;; after THEN or ELSE, as a GOTO. The condition is a number: zero is false and anything else is true; a real number
;; is made an integer first. When it is false the line is searched for an ELSE token, and when there is none the
;; program goes on at the next line.
;; In: PTR_A, PTR_A_OFFSET = the condition
;; Uses: all
;; Errors: Type mismatch when the condition is a string, No such line
;; Entry: GOTO_LINE_OR_STATEMENT = goes to the line whose number is at PTRA, as GOTO does, or runs the statement there
;;   when there is no line number
IF_STATEMENT:
    jsr EVALUATE_EXPRESSION_A
    beq IF_TYPE_MISMATCH
    bpl IF_INTEGER
    jsr REAL_TO_INTEGER
IF_INTEGER:
    ldy PTR_B_OFFSET
    sty PTR_A_OFFSET
    lda INT_A
    ora INT_A+1
    ora INT_A+2
    ora INT_A+3
    beq IF_FALSE
    cpx #TOKEN_THEN
    beq IF_THEN
IF_RUN_STATEMENT:
    jmp EXECUTE_STATEMENT
IF_THEN:
    inc PTR_A_OFFSET
GOTO_LINE_OR_STATEMENT:
    jsr GET_LINE_NUMBER
    bcc IF_RUN_STATEMENT
    jsr FIND_TARGET_LINE
    jsr RESET_PTR_A_OFFSET
    jmp JUMP_TO_LINE
IF_FALSE:
    ldy PTR_A_OFFSET
IF_FIND_ELSE:
    lda (PTR_A),y
    cmp #CARRIAGE_RETURN
    beq IF_NO_ELSE
    iny
    cmp #TOKEN_ELSE
    bne IF_FIND_ELSE
    sty PTR_A_OFFSET
    beq GOTO_LINE_OR_STATEMENT      ; always taken: zero is still set from finding ELSE
IF_NO_ELSE:
    jmp END_OF_STATEMENT_LINE

;; Prints a line number for TRACE, as "[number] ", when it is below the limit TRACE set.
;; In: INT_A, INT_A+1 = the line number
;; Uses: A, X, Y, INT_A, INT_A+1, PRINT_FIELD_WIDTH, WORK, DIGIT_BUFFER..DIGIT_BUFFER+4
;; See: <TRACE_LIMIT>
TRACE_LINE_NUMBER:
    lda INT_A
    cmp TRACE_LIMIT
    lda INT_A+1
    sbc TRACE_LIMIT+1
    bcs MOVE_TO_NEXT_LINE_RETURN            ; at or above the limit: not traced
    lda #'['
    jsr PRINT_CHARACTER
    jsr PRINT_LINE_NUMBER
    lda #']'
    jsr PRINT_CHARACTER
    jmp PRINT_SPACE

;; Prints the 16-bit number in IntA in decimal, with no spaces before it.
;;
;; It finds each digit by subtracting the power of ten for it as many times as it goes, using
;; <POWERS_OF_TEN_LOW> and <POWERS_OF_TEN_HIGH>, then prints them without leading zeros, after spaces that make the
;; number up to the field width. The width is kept in <PRINT_FIELD_WIDTH>, which is changed.
;; In: INT_A, INT_A+1 = the number
;; Uses: A, X, Y, INT_A, INT_A+1, PRINT_FIELD_WIDTH, WORK, DIGIT_BUFFER..DIGIT_BUFFER+4
;; Entry: PRINT_LINE_NUMBER_PADDED = prints the number right-justified in five characters, as LIST does
PRINT_LINE_NUMBER:
    lda #$00
    beq PRINT_LINE_NUMBER_WIDTH     ; always taken
PRINT_LINE_NUMBER_PADDED:
    lda #$05
PRINT_LINE_NUMBER_WIDTH:
    sta PRINT_FIELD_WIDTH
    ldx #$04                        ; from the ten thousands down to the units
PRINT_LINE_NUMBER_DIGIT:
    lda #$00
    sta DIGIT_BUFFER,x
    sec
PRINT_LINE_NUMBER_SUBTRACT:
    lda INT_A
    sbc POWERS_OF_TEN_LOW,x
    tay
    lda INT_A+1
    sbc POWERS_OF_TEN_HIGH,x
    bcc PRINT_LINE_NUMBER_NEXT
    sta INT_A+1
    sty INT_A
    inc DIGIT_BUFFER,x
    bne PRINT_LINE_NUMBER_SUBTRACT  ; always taken: no digit passes 6
PRINT_LINE_NUMBER_NEXT:
    dex
    bpl PRINT_LINE_NUMBER_DIGIT
    ldx #$05
PRINT_LINE_NUMBER_FIRST:
    dex                             ; find the first digit that is not zero, but keep the units
    beq PRINT_LINE_NUMBER_PAD
    lda DIGIT_BUFFER,x
    beq PRINT_LINE_NUMBER_FIRST
PRINT_LINE_NUMBER_PAD:
    stx WORK                        ; the number of digits less one
    lda PRINT_FIELD_WIDTH
    beq PRINT_LINE_NUMBER_PRINT
    sbc WORK                        ; carry is clear: the width less the number of digits
    beq PRINT_LINE_NUMBER_PRINT
    tay
PRINT_LINE_NUMBER_SPACE:
    jsr PRINT_SPACE
    dey
    bne PRINT_LINE_NUMBER_SPACE
PRINT_LINE_NUMBER_PRINT:
    lda DIGIT_BUFFER,x
    ora #'0'
    jsr PRINT_CHARACTER
    dex
    bpl PRINT_LINE_NUMBER_PRINT
    rts

;; The low bytes of 1, 10, 100, 1000 and 10000, the powers of ten <PRINT_LINE_NUMBER> divides by.
;;
;; Indexed by the digit's place, 0 for the units; <POWERS_OF_TEN_HIGH> holds the high bytes.
POWERS_OF_TEN_LOW:
    .byte <1, <10, <100, <1000, <10000

;; Looks for a line in the program by its number.
;;
;; The search starts at PAGE and steps from line to line by their length bytes until it reaches a line whose number
;; is the one wanted or higher. The end of the program's marker, whose high byte is &FF, stops it.
;; In: INT_A, INT_A+1 = the line number
;; Out:
;;   carry = clear when the line was found, set when it was not
;;   FIND_LINE_POINTER = when found, the line's length byte, which PTRA can take with an offset of 1 to run the line;
;;     when not, the carriage return before the first line with a higher number, where the line would go
;;   Y = 2
;; Uses: A
FIND_LINE:
    ldy #$00
    sty FIND_LINE_POINTER
    lda PAGE_HIGH
    sta FIND_LINE_POINTER+1
FIND_LINE_LOOP:
    ldy #$01
    lda (FIND_LINE_POINTER),y       ; the line number's high byte
    cmp INT_A+1
    bcs FIND_LINE_HIGH
FIND_LINE_NEXT:
    ldy #$03
    lda (FIND_LINE_POINTER),y       ; carry is clear: add the length to step to the next line
    adc FIND_LINE_POINTER
    sta FIND_LINE_POINTER
    bcc FIND_LINE_LOOP
    inc FIND_LINE_POINTER+1
    bcs FIND_LINE_LOOP              ; always taken
FIND_LINE_HIGH:
    bne FIND_LINE_DONE              ; a higher number: not found
    ldy #$02
    lda (FIND_LINE_POINTER),y       ; the low byte
    cmp INT_A
    bcc FIND_LINE_NEXT
    bne FIND_LINE_DONE
    tya                             ; found: carry is set, so this adds 3, to the length byte
    adc FIND_LINE_POINTER
    sta FIND_LINE_POINTER
    bcc FIND_LINE_DONE
    inc FIND_LINE_POINTER+1
    clc
FIND_LINE_DONE:
    ldy #$02
    rts

;; Raises error 18, "Division by zero".
;;
;; The zero that ends its message is the first byte of <POWERS_OF_TEN_HIGH>, which follows it.
DIVISION_BY_ZERO_ERROR:
    brk
    .byte ERROR_DIVISION_BY_ZERO
    .byte "Division by zero"        ; ended by the first byte of the table that follows

;; The high bytes of 1, 10, 100, 1000 and 10000, the powers of ten <PRINT_LINE_NUMBER> divides by.
;;
;; Indexed by the digit's place, as <POWERS_OF_TEN_LOW> is. Its first byte, the high byte of 1, is also the zero that
;; ends the message of <DIVISION_BY_ZERO_ERROR>.
POWERS_OF_TEN_HIGH:
    .byte >1                        ; also the zero that ends "Division by zero"
    .byte >10, >100, >1000, >10000

;; Divides two integers, for DIV and MOD: the left operand by the next factor at PTRB.
;;
;; Both operands are made integers and their magnitudes divided, 32 bits by 32, by shifting the dividend out into the
;; remainder a bit at a time and subtracting the divisor wherever it goes; each bit of the quotient is shifted into the
;; dividend's place as it moves out. Leading zero bits of the dividend are skipped first. The signs are kept for the
;; caller to apply: DIV's quotient is negative when the signs differ, and MOD's remainder takes the dividend's sign.
;; One dividend is wrong: &80000000 (-2147483648) keeps its magnitude's one set bit in bit 31, which the skip of
;; leading zeros shifts out unseen, so with any divisor both the quotient and the remainder are 0 (&80000000 MOD 3
;; is 0, not -2).
;; In:
;;   A = the type of the left operand, the dividend, in the accumulators, with the flags set from it
;;   PTR_B, PTR_B_OFFSET = the divisor's factor
;; Out:
;;   DIVIDE_QUOTIENT = the quotient of the magnitudes, without its last bit, which is in carry for the caller to
;;     shift in
;;   DIVIDE_REMAINDER = the remainder of the magnitudes
;;   RESULT_SIGN = bit 7 set when the quotient is negative
;;   DIVIDEND_SIGN = bit 7 set when the remainder is negative
;;   EXPRESSION_TYPE = the character after the divisor, which <EVALUATE_POWER> returned in X
;;   Y = 0
;; Uses: A, X, INT_A, BASIC_STACK (used and restored)
;; Errors: Type mismatch when either operand is a string, Division by zero
DIVIDE_INTEGERS:
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the dividend as an integer
    lda INT_A+3
    pha
    jsr ABS_INT_A                       ; its magnitude
    jsr PUSH_THEN_EVALUATE_POWER
    stx EXPRESSION_TYPE             ; keep the next operator
    tay
    jsr CONVERT_A_TO_INTEGER                       ; the divisor as an integer
    pla
    sta DIVIDEND_SIGN
    eor INT_A+3
    sta RESULT_SIGN
    jsr ABS_INT_A                       ; the divisor's magnitude
    ldx #DIVIDE_QUOTIENT
    jsr POP_INTEGER_TO              ; the dividend; Y = 0
    sty DIVIDE_REMAINDER
    sty DIVIDE_REMAINDER+1
    sty DIVIDE_REMAINDER+2
    sty DIVIDE_REMAINDER+3
    lda INT_A+3
    ora INT_A
    ora INT_A+1
    ora INT_A+2
    beq DIVISION_BY_ZERO_ERROR
    ldy #32                         ; the bits of the dividend
DIVIDE_INTEGERS_SKIP_ZEROS:
    dey
    beq DIVIDE_INTEGERS_DONE        ; a dividend of zero: the results are zero
    asl DIVIDE_QUOTIENT
    rol DIVIDE_QUOTIENT+1
    rol DIVIDE_QUOTIENT+2
    rol DIVIDE_QUOTIENT+3
    bpl DIVIDE_INTEGERS_SKIP_ZEROS  ; until its top bit is set
DIVIDE_INTEGERS_LOOP:
    rol DIVIDE_QUOTIENT             ; shift the last quotient bit in and the dividend's next bit out
    rol DIVIDE_QUOTIENT+1
    rol DIVIDE_QUOTIENT+2
    rol DIVIDE_QUOTIENT+3
    rol DIVIDE_REMAINDER            ; into the remainder
    rol DIVIDE_REMAINDER+1
    rol DIVIDE_REMAINDER+2
    rol DIVIDE_REMAINDER+3
    sec
    lda DIVIDE_REMAINDER
    sbc INT_A
    pha
    lda DIVIDE_REMAINDER+1
    sbc INT_A+1
    pha
    lda DIVIDE_REMAINDER+2
    sbc INT_A+2
    tax
    lda DIVIDE_REMAINDER+3
    sbc INT_A+3
    bcc DIVIDE_INTEGERS_NO_SUBTRACT ; the divisor does not go: the quotient bit is 0
    sta DIVIDE_REMAINDER+3
    stx DIVIDE_REMAINDER+2
    pla
    sta DIVIDE_REMAINDER+1
    pla
    sta DIVIDE_REMAINDER
    bcs DIVIDE_INTEGERS_NEXT        ; always taken, with the quotient bit, 1, in carry
DIVIDE_INTEGERS_NO_SUBTRACT:
    pla
    pla
DIVIDE_INTEGERS_NEXT:
    dey
    bne DIVIDE_INTEGERS_LOOP
DIVIDE_INTEGERS_DONE:
    rts

;; Compares an integer on BASIC's stack with a real number in FPA, as reals; part of <COMPARE_VALUES>.
;; In: X = the character after the right operand
COMPARE_INTEGER_WITH_REAL:
    stx EXPRESSION_TYPE
    jsr POP_INTEGER
    jsr PUSH_REAL
    jsr INTEGER_TO_REAL
    jsr COPY_FP_A_TO_FP_B           ; FPB = the left operand
    jsr POP_REAL_POINTER
    jsr LOAD_FP_A                   ; FPA = the right operand
    jmp COMPARE_FP_B_WITH_FP_A

;; Compares two real numbers, the left in FPA and the right the next sum at PTRB; part of <COMPARE_VALUES>.
COMPARE_REALS:
    jsr PUSH_REAL
    jsr EVALUATE_SUM
    stx EXPRESSION_TYPE             ; keep the next operator
    tay
    jsr CONVERT_A_TO_REAL                       ; the right operand as a real
    jsr POP_REAL_POINTER                    ; FP_POINTER = the left operand, still in place on the stack

;; Compares the real number at <FP_POINTER> with FPA, as FOR's NEXT does with its limit.
;;
;; The number at FP_POINTER is the left operand and FPA the right. It compares the signs, then the exponents and the
;; mantissas byte by byte, turning the answer round when both are negative.
;; In: FP_POINTER = the left operand, FP_A = the right operand, EXPRESSION_TYPE = the value to return in X
;; Out:
;;   zero = set when the two are equal
;;   carry = set when the left operand is the greater or they are equal, clear when it is the smaller
;;   X = EXPRESSION_TYPE
;;   Y = 0
;; Uses: A, FP_B
;; Entry: COMPARE_FP_B_WITH_FP_A = compares FPB, as the left operand, with FPA
COMPARE_REAL_AT_POINTER:
    jsr LOAD_FP_B
COMPARE_FP_B_WITH_FP_A:
    ldx EXPRESSION_TYPE
    ldy #$00
    lda FP_B_SIGN
    and #$80
    sta FP_B_SIGN
    lda FP_A_SIGN
    and #$80
    cmp FP_B_SIGN
    bne COMPARE_REALS_DONE          ; the signs differ: carry is set when the left one is positive
    lda FP_B_EXPONENT
    cmp FP_A_EXPONENT
    bne COMPARE_REALS_DIFFERENT
    lda FP_B_MANTISSA
    cmp FP_A_MANTISSA
    bne COMPARE_REALS_DIFFERENT
    lda FP_B_MANTISSA+1
    cmp FP_A_MANTISSA+1
    bne COMPARE_REALS_DIFFERENT
    lda FP_B_MANTISSA+2
    cmp FP_A_MANTISSA+2
    bne COMPARE_REALS_DIFFERENT
    lda FP_B_MANTISSA+3
    cmp FP_A_MANTISSA+3
    bne COMPARE_REALS_DIFFERENT
COMPARE_REALS_DONE:
    rts
COMPARE_REALS_DIFFERENT:
    ror a                           ; carry, set when the left magnitude is greater, to bit 7
    eor FP_B_SIGN                   ; turned round when both are negative
    rol a                           ; and back to carry
    lda #$01                        ; zero clear: not equal
    rts

;; Raises Type mismatch for <COMPARE_VALUES>, from within reach of its branches.
COMPARE_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Compares the value in the accumulators with the next sum at PTRB, for the relational operators.
;;
;; Numbers are compared as integers when both are integers, otherwise as reals; strings are compared character by
;; character by their codes, and when one is the start of the other the shorter is the smaller. The left operand is
;; pushed on BASIC's stack while the right is evaluated, and dropped afterwards.
;; In:
;;   A = the type of the left operand, in the accumulators
;;   PTR_B, PTR_B_OFFSET = the right operand
;; Out:
;;   zero = set when the two are equal
;;   carry = set when the left operand is the greater or they are equal, clear when it is the smaller
;;   X = the character after the right operand
;;   Y = 0
;; Uses: all
;; Errors: Type mismatch when a string is compared with a number
;; Entry: COMPARE_VALUES_X = takes the left operand's type from X
COMPARE_VALUES_X:
    txa
COMPARE_VALUES:
    beq COMPARE_STRINGS
    bmi COMPARE_REALS
    jsr PUSH_INTEGER
    jsr EVALUATE_SUM
    tay
    beq COMPARE_TYPE_MISMATCH
    bmi COMPARE_INTEGER_WITH_REAL
    lda INT_A+3                     ; compare as unsigned numbers with the sign bits inverted
    eor #$80
    sta INT_A+3
    sec
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
    ldy #$00
    eor #$80
    sbc INT_A+3
    ora INT_A                       ; zero when every byte of the difference is zero
    ora INT_A+1
    ora INT_A+2
    php
    clc                             ; drop the left operand
    lda #$04
    adc BASIC_STACK
    sta BASIC_STACK
    bcc COMPARE_INTEGERS_DONE
    inc BASIC_STACK+1
COMPARE_INTEGERS_DONE:
    plp
    rts

;; Compares a string on BASIC's stack with the next sum at PTRB; part of <COMPARE_VALUES>.
;;
;; The string on the stack is its length byte, then its characters; the right operand is in StrA.
COMPARE_STRINGS:
    jsr PUSH_STRING
    jsr EVALUATE_SUM
    tay
    bne COMPARE_TYPE_MISMATCH
    stx WORK                        ; keep the next operator
    ldx STRING_LENGTH
    ldy #$00
    lda (BASIC_STACK),y
    sta WORK+2                      ; the left string's length
    cmp STRING_LENGTH
    bcs COMPARE_STRINGS_SHORTER
    tax
COMPARE_STRINGS_SHORTER:
    stx WORK+3                      ; the shorter length: the characters both have
    ldy #$00
COMPARE_STRINGS_LOOP:
    cpy WORK+3
    beq COMPARE_STRINGS_LENGTHS
    iny
    lda (BASIC_STACK),y
    cmp STRING_BUFFER-1,y
    beq COMPARE_STRINGS_LOOP
    bne COMPARE_STRINGS_DONE        ; always taken
COMPARE_STRINGS_LENGTHS:
    lda WORK+2                      ; the same as far as the shorter goes: compare the lengths
    cmp STRING_LENGTH
COMPARE_STRINGS_DONE:
    php
    jsr DROP_STRING                       ; drop the left string
    ldx WORK
    plp
    rts

; Entry points the BASIC ROM User Guide gives BASIC II's addresses for, for machine code that calls them.
    .assert CHECK_END_OF_STATEMENT = $9857, "the BASIC ROM User Guide documents CHECK_END_OF_STATEMENT at &9857"
    .assert PRINT_LINE_NUMBER = $991F, "the BASIC ROM User Guide documents PRINT_LINE_NUMBER at &991F"
    .assert PRINT_LINE_NUMBER_PADDED = $9923, "the BASIC ROM User Guide documents PRINT_LINE_NUMBER_PADDED at &9923"
    .assert FIND_LINE = $9970, "the BASIC ROM User Guide documents FIND_LINE at &9970"
