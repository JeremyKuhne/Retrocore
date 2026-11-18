;; NEXT, FOR, GOSUB, RETURN, GOTO, ON, INPUT, RESTORE, READ and UNTIL ($B695-$BBE3).
;;
;; - FOR and NEXT, with the FOR stack's 15-byte entries (<FOR_STACK>), for integer and real control variables.
;; - GOSUB and RETURN, with the GOSUB stack; GOTO; ON ERROR and ON ERROR OFF; ON ... GOTO and ON ... GOSUB, with
;;   ELSE. They find their line with <GET_TARGET_LINE>, and go to it with <JUMP_TO_LINE>.
;; - INPUT# and INPUT, with its prompts and INPUT LINE.
;; - RESTORE, READ and the search for DATA items, <FIND_DATA_ITEM>; and UNTIL, the end of REPEAT's loop.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; The fields of a FOR stack entry, by their offsets.
FOR_ENTRY_VARIABLE = 0              ;; the control variable's address, two bytes
FOR_ENTRY_TYPE = 2                  ;; the control variable's type: 0 (byte), 4 (integer) or 5 (real)
FOR_ENTRY_STEP = 3                  ;; the STEP: an integer in four bytes, low first, or a packed real in five
FOR_ENTRY_LIMIT = 8                 ;; the TO limit, laid out as the STEP is
FOR_ENTRY_LOOP = 13                 ;; the text to loop back to, the statement after the FOR, two bytes
FOR_ENTRY_SIZE = 15                 ;; the size of an entry
FOR_STACK_ENTRIES = 10              ;; the most FOR loops that can be open

TOP_FOR_ENTRY = FOR_STACK - FOR_ENTRY_SIZE  ;; the top entry, indexed by <FOR_LEVEL>, which points past it

GOSUB_STACK_SIZE = GOSUB_STACK_HIGH - GOSUB_STACK_LOW   ;; the most GOSUBs that can be open: 26

; Where GOTO, GOSUB, ON and RESTORE find their line.
TARGET_LINE = FP_B_EXPONENT         ;; the line <FIND_LINE> found: the address of its length byte, low byte first

; INPUT's work bytes, and INPUT#'s.
INPUT_FLAGS = SERIES_POINTER        ;; bit 7: print a ? before reading; bit 6: INPUT LINE
INPUT_FIELD = SERIES_POINTER + 1    ;; the offset in the typed line of the next field, &FF to read a new line
INPUT_FILE_HANDLE = SERIES_POINTER  ;; the file handle INPUT# reads from

; Error numbers.
ERROR_CANT_MATCH_FOR = 33           ;; error 33, "Can't Match FOR"
ERROR_FOR_VARIABLE = 34             ;; error 34, "FOR variable"
ERROR_TOO_MANY_FORS = 35            ;; error 35, "Too many FORs"
ERROR_NO_TO = 36                    ;; error 36, "No TO"
ERROR_TOO_MANY_GOSUBS = 37          ;; error 37, "Too many GOSUBs"
ERROR_NO_GOSUB = 38                 ;; error 38, "No GOSUB"
ERROR_ON_SYNTAX = 39                ;; error 39, "ON syntax"
ERROR_ON_RANGE = 40                 ;; error 40, "ON range"
ERROR_NO_SUCH_LINE = 41             ;; error 41, "No such line"
ERROR_OUT_OF_DATA = 42              ;; error 42, "Out of DATA"
ERROR_NO_REPEAT = 43                ;; error 43, "No REPEAT"
ERROR_TOO_MANY_REPEATS = 44         ;; error 44, "Too many REPEATs"

    .assert FOR_STACK + FOR_STACK_ENTRIES * FOR_ENTRY_SIZE <= REPEAT_STACK_LOW, "FOR_STACK fits below the REPEAT stack."
    .assert GOSUB_STACK_HIGH + GOSUB_STACK_SIZE = STRING_BUFFER, "The GOSUB stack ends page five."

;; NEXT: ends a FOR loop's pass, NEXT, NEXT v or NEXT v,w,...
;;
;; With a variable, entries are taken off the FOR stack until the top one is that variable's loop; without one, the
;; top entry is used. The STEP is added to the control variable, which is then compared with the limit: while it has
;; not passed the limit (is not greater for a positive STEP, not less for a negative one), the program continues at
;; the statement after the FOR. Otherwise the entry is taken off the stack, and a comma after the variable starts
;; the next NEXT. An integer loop adds and compares four bytes even for a byte variable (?).
;;
;; A name that is not an existing numeric variable is a "Syntax error".
;; Errors: 32 = "No FOR", 33 = "Can't Match FOR", 16 = "Syntax error", 17 = "Escape"
;; See: <FOR_STATEMENT>, <FOR_STACK>
NEXT_STATEMENT:
    jsr FIND_VARIABLE_A
    bne NEXT_NAMED
    ldx FOR_LEVEL
    beq NO_FOR_ERROR
    bcs NEXT_STEP                   ; no name: the top loop
NEXT_SYNTAX_ERROR:
    jmp SYNTAX_ERROR
NEXT_NAMED:
    bcs NEXT_SYNTAX_ERROR           ; a string variable
    ldx FOR_LEVEL
    beq NO_FOR_ERROR
NEXT_MATCH_LOOP:
    lda INT_A
    cmp TOP_FOR_ENTRY+FOR_ENTRY_VARIABLE,x
    bne NEXT_DROP_ENTRY
    lda INT_A+1
    cmp TOP_FOR_ENTRY+FOR_ENTRY_VARIABLE+1,x
    bne NEXT_DROP_ENTRY
    lda INT_A+2
    cmp TOP_FOR_ENTRY+FOR_ENTRY_TYPE,x
    beq NEXT_STEP
NEXT_DROP_ENTRY:
    txa
    sec
    sbc #FOR_ENTRY_SIZE
    tax
    stx FOR_LEVEL
    bne NEXT_MATCH_LOOP
    brk                             ; no loop has this variable
    .byte ERROR_CANT_MATCH_FOR, "Can't Match ", TOKEN_FOR, 0
NEXT_STEP:
    lda TOP_FOR_ENTRY+FOR_ENTRY_VARIABLE,x
    sta INT_A
    lda TOP_FOR_ENTRY+FOR_ENTRY_VARIABLE+1,x
    sta INT_A+1
    ldy TOP_FOR_ENTRY+FOR_ENTRY_TYPE,x
    cpy #VARIABLE_REAL
    beq NEXT_REAL
    ldy #$00                        ; carry is clear: the type is below 5
    lda (INT_A),y
    adc TOP_FOR_ENTRY+FOR_ENTRY_STEP,x
    sta (INT_A),y
    sta WORK
    iny
    lda (INT_A),y
    adc TOP_FOR_ENTRY+FOR_ENTRY_STEP+1,x
    sta (INT_A),y
    sta WORK+1
    iny
    lda (INT_A),y
    adc TOP_FOR_ENTRY+FOR_ENTRY_STEP+2,x
    sta (INT_A),y
    sta WORK+2
    iny
    lda (INT_A),y
    adc TOP_FOR_ENTRY+FOR_ENTRY_STEP+3,x
    sta (INT_A),y
    tay                             ; Y = the new value's top byte
    lda WORK                        ; compare the new value with the limit
    sec
    sbc TOP_FOR_ENTRY+FOR_ENTRY_LIMIT,x
    sta WORK
    lda WORK+1
    sbc TOP_FOR_ENTRY+FOR_ENTRY_LIMIT+1,x
    sta WORK+1
    lda WORK+2
    sbc TOP_FOR_ENTRY+FOR_ENTRY_LIMIT+2,x
    sta WORK+2
    tya
    sbc TOP_FOR_ENTRY+FOR_ENTRY_LIMIT+3,x
    ora WORK
    ora WORK+1
    ora WORK+2
    beq NEXT_LOOP_BACK              ; equal to the limit: once more
    ; Carry is set when the value is above the limit, unsigned. Bit 7 of the value's, the limit's and the STEP's top
    ; bytes together say whether that is the answer: it is turned round when the value and the limit differ in sign,
    ; and again for a negative STEP.
    tya
    eor TOP_FOR_ENTRY+FOR_ENTRY_STEP+3,x
    eor TOP_FOR_ENTRY+FOR_ENTRY_LIMIT+3,x
    bpl NEXT_INTEGER_TEST
    bcs NEXT_LOOP_BACK
    bcc NEXT_LOOP_DONE              ; always taken
NEXT_INTEGER_TEST:
    bcs NEXT_LOOP_DONE
NEXT_LOOP_BACK:
    ldy TOP_FOR_ENTRY+FOR_ENTRY_LOOP,x
    lda TOP_FOR_ENTRY+FOR_ENTRY_LOOP+1,x
    sty PTR_A
    sta PTR_A+1
    jsr RESET_PTR_A_OFFSET                       ; the statement's start, checking ESCAPE
    jmp EXECUTE_STATEMENT
NEXT_LOOP_DONE:
    lda FOR_LEVEL                   ; take the entry off the stack
    sec
    sbc #FOR_ENTRY_SIZE
    sta FOR_LEVEL
    ldy PTR_B_OFFSET
    sty PTR_A_OFFSET
    jsr GET_CHARACTER_A
    cmp #','
    bne NEXT_END
    jmp NEXT_STATEMENT              ; NEXT v,w: the next variable
NEXT_REAL:
    jsr READ_VARIABLE_REAL                       ; load the variable into FPA; Y = 5 is its length
    lda FOR_LEVEL
    clc
    adc #<(FOR_ENTRY_STEP - FOR_ENTRY_SIZE)
    sta FP_POINTER
    lda #>FOR_STACK
    sta FP_POINTER+1
    jsr ADD_TO_FP_A                       ; add the STEP
    lda INT_A
    sta WORK
    lda INT_A+1
    sta WORK+1
    jsr STORE_FP_A_IN_VARIABLE
    lda FOR_LEVEL
    sta EXPRESSION_TYPE             ; so that the comparison's LDX EXPRESSION_TYPE gives X = FOR_LEVEL
    clc
    adc #<(FOR_ENTRY_LIMIT - FOR_ENTRY_SIZE)
    sta FP_POINTER
    lda #>FOR_STACK
    sta FP_POINTER+1
    jsr COMPARE_REAL_AT_POINTER                       ; compare with the limit: carry set when below it
    beq NEXT_LOOP_BACK
    lda TOP_FOR_ENTRY+FOR_ENTRY_STEP+1,x    ; the STEP's sign
    bmi NEXT_REAL_NEGATIVE_STEP
    bcs NEXT_LOOP_BACK
    bcc NEXT_LOOP_DONE              ; always taken
NEXT_REAL_NEGATIVE_STEP:
    bcc NEXT_LOOP_BACK
    bcs NEXT_LOOP_DONE              ; always taken
NEXT_END:
    jmp FINISH_STATEMENT_BACK_ONE

;; Raises error 34, "FOR variable": FOR's control variable is missing or a string.
;;
;; The message has no zero of its own: the BRK that starts <TOO_MANY_FORS_ERROR> ends it.
FOR_VARIABLE_ERROR:
    brk
    .byte ERROR_FOR_VARIABLE, TOKEN_FOR, " variable"

;; Raises error 35, "Too many FORs": ten FOR loops are already open.
;;
;; Its BRK ends the message of <FOR_VARIABLE_ERROR>, and its own message has no zero: the BRK that starts
;; <NO_TO_ERROR> ends it.
TOO_MANY_FORS_ERROR:
    brk
    .byte ERROR_TOO_MANY_FORS, "Too many ", TOKEN_FOR, "s"

;; Raises error 36, "No TO": FOR without a TO. Its BRK ends the message of <TOO_MANY_FORS_ERROR>.
NO_TO_ERROR:
    brk
    .byte ERROR_NO_TO, "No ", TOKEN_TO, 0

;; FOR: starts a FOR loop, FOR v = start TO limit, or FOR v = start TO limit STEP step.
;;
;; The control variable is set to the start, and an entry pushed on <FOR_STACK> with the variable's descriptor, the
;; STEP (1 when none is given), the limit and the address of the statement after the FOR, where NEXT loops back to.
;; The limit and the STEP are kept as integers for an integer or byte variable and as packed reals for a real one.
;; The loop body always runs at least once.
;; Errors: 34 = "FOR variable", 4 = "Mistake" (no =), 35 = "Too many FORs", 36 = "No TO", 6 = "Type mismatch",
;;   16 = "Syntax error"
;; See: <NEXT_STATEMENT>
FOR_STATEMENT:
    jsr FIND_OR_CREATE_VARIABLE
    beq FOR_VARIABLE_ERROR          ; no variable
    bcs FOR_VARIABLE_ERROR          ; a string variable
    jsr PUSH_INTEGER                ; the descriptor, for the assignment
    jsr EXPECT_EQUALS                       ; the =
    jsr EVALUATE_AND_ASSIGN                       ; v = start; WORK..WORK+2 = the descriptor
    ldy FOR_LEVEL
    cpy #FOR_STACK_ENTRIES * FOR_ENTRY_SIZE
    bcs TOO_MANY_FORS_ERROR
    lda WORK
    sta FOR_STACK+FOR_ENTRY_VARIABLE,y
    lda WORK+1
    sta FOR_STACK+FOR_ENTRY_VARIABLE+1,y
    lda WORK+2
    sta FOR_STACK+FOR_ENTRY_TYPE,y
    tax
    jsr GET_CHARACTER_B
    cmp #TOKEN_TO
    bne NO_TO_ERROR
    cpx #VARIABLE_REAL
    beq FOR_REAL
    jsr EVALUATE_INTEGER                       ; the limit, as an integer
    ldy FOR_LEVEL
    lda INT_A
    sta FOR_STACK+FOR_ENTRY_LIMIT,y
    lda INT_A+1
    sta FOR_STACK+FOR_ENTRY_LIMIT+1,y
    lda INT_A+2
    sta FOR_STACK+FOR_ENTRY_LIMIT+2,y
    lda INT_A+3
    sta FOR_STACK+FOR_ENTRY_LIMIT+3,y
    lda #1                          ; the STEP when there is none
    jsr LOAD_INT_A_BYTE
    jsr GET_CHARACTER_B
    cmp #TOKEN_STEP
    bne FOR_SAVE_INTEGER_STEP       ; Y = the offset of that character, to read again
    jsr EVALUATE_INTEGER
    ldy PTR_B_OFFSET
FOR_SAVE_INTEGER_STEP:
    sty PTR_A_OFFSET
    ldy FOR_LEVEL
    lda INT_A
    sta FOR_STACK+FOR_ENTRY_STEP,y
    lda INT_A+1
    sta FOR_STACK+FOR_ENTRY_STEP+1,y
    lda INT_A+2
    sta FOR_STACK+FOR_ENTRY_STEP+2,y
    lda INT_A+3
    sta FOR_STACK+FOR_ENTRY_STEP+3,y
FOR_SAVE_LOOP:
    jsr MOVE_TO_NEXT_STATEMENT                       ; PTR_A to the next statement
    ldy FOR_LEVEL
    lda PTR_A
    sta FOR_STACK+FOR_ENTRY_LOOP,y
    lda PTR_A+1
    sta FOR_STACK+FOR_ENTRY_LOOP+1,y
    clc
    tya
    adc #FOR_ENTRY_SIZE
    sta FOR_LEVEL
    jmp EXECUTE_STATEMENT
FOR_REAL:
    jsr EVALUATE_EXPRESSION         ; the limit, as a real
    jsr CONVERT_A_TO_REAL
    lda FOR_LEVEL
    clc
    adc #FOR_ENTRY_LIMIT
    sta FP_POINTER
    lda #>FOR_STACK
    sta FP_POINTER+1
    jsr STORE_FP_A
    jsr ONE_FP_A                    ; the STEP when there is none
    jsr GET_CHARACTER_B
    cmp #TOKEN_STEP
    bne FOR_SAVE_REAL_STEP
    jsr EVALUATE_EXPRESSION
    jsr CONVERT_A_TO_REAL
    ldy PTR_B_OFFSET
FOR_SAVE_REAL_STEP:
    sty PTR_A_OFFSET
    lda FOR_LEVEL
    clc
    adc #FOR_ENTRY_STEP
    sta FP_POINTER
    lda #>FOR_STACK
    sta FP_POINTER+1
    jsr STORE_FP_A
    jmp FOR_SAVE_LOOP

;; GOSUB: calls a subroutine, GOSUB n, where n can be an expression.
;;
;; The address of the end of the GOSUB statement is pushed on the GOSUB stack, for RETURN, and the program goes on
;; at line n.
;; Errors: 41 = "No such line", 37 = "Too many GOSUBs", 16 = "Syntax error", 6 = "Type mismatch"
;; Entry: GOSUB_TO_LINE = with the line already found in <TARGET_LINE> (ON ... GOSUB)
;; See: <RETURN_STATEMENT>, <GET_TARGET_LINE>
GOSUB_STATEMENT:
    jsr GET_TARGET_LINE
GOSUB_TO_LINE:
    jsr CHECK_END_OF_STATEMENT
    ldy GOSUB_LEVEL
    cpy #GOSUB_STACK_SIZE
    bcs TOO_MANY_GOSUBS_ERROR
    lda PTR_A
    sta GOSUB_STACK_LOW,y
    lda PTR_A+1
    sta GOSUB_STACK_HIGH,y
    inc GOSUB_LEVEL
    bcc JUMP_TO_LINE                ; always taken

;; Raises error 37, "Too many GOSUBs": 26 GOSUBs are already open.
;;
;; The message has no zero of its own: the BRK that starts <NO_GOSUB_ERROR> ends it.
TOO_MANY_GOSUBS_ERROR:
    brk
    .byte ERROR_TOO_MANY_GOSUBS, "Too many ", TOKEN_GOSUB, "s"

;; Raises error 38, "No GOSUB": RETURN with no GOSUB open. Its BRK ends the message of <TOO_MANY_GOSUBS_ERROR>.
NO_GOSUB_ERROR:
    brk
    .byte ERROR_NO_GOSUB, "No ", TOKEN_GOSUB, 0

;; RETURN: returns from a subroutine, continuing after the last GOSUB.
;; Errors: 38 = "No GOSUB", 16 = "Syntax error"
;; See: <GOSUB_STATEMENT>
RETURN_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    ldx GOSUB_LEVEL
    beq NO_GOSUB_ERROR
    dec GOSUB_LEVEL
    ldy GOSUB_STACK_LOW-1,x
    lda GOSUB_STACK_HIGH-1,x
    sty PTR_A
    sta PTR_A+1
    jmp CONTINUE_EXECUTION

;; GOTO: goes to a line, GOTO n, where n can be an expression.
;; Errors: 41 = "No such line", 16 = "Syntax error", 6 = "Type mismatch"
;; See: <GET_TARGET_LINE>, <JUMP_TO_LINE>
GOTO_STATEMENT:
    jsr GET_TARGET_LINE
    jsr CHECK_END_OF_STATEMENT
    ; Falls through into JUMP_TO_LINE.

;; Goes on with the program at the line <FIND_LINE> found, printing its number first when TRACE is on.
;; In: TARGET_LINE = the line's length byte, INT_A = its number, PTR_A_OFFSET = 1
;; Entry: CONTINUE_AT = goes on at PTR_A_OFFSET in the text at A (high) and Y (low)
;; See: <TRACE_LINE_NUMBER>
JUMP_TO_LINE:
    lda TRACE_FLAG
    beq JUMP_TO_LINE_UNTRACED
    jsr TRACE_LINE_NUMBER
JUMP_TO_LINE_UNTRACED:
    ldy TARGET_LINE
    lda TARGET_LINE+1
CONTINUE_AT:
    sty PTR_A
    sta PTR_A+1
    jmp EXECUTE_STATEMENT

;; ON ERROR OFF: makes errors run BASIC's own handler again, <DEFAULT_ERROR_HANDLER>, which reports the error and
;; stops the program.
;; Errors: 16 = "Syntax error"
ON_ERROR_OFF_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    lda #<DEFAULT_ERROR_HANDLER
    sta ON_ERROR
    lda #>DEFAULT_ERROR_HANDLER
    sta ON_ERROR+1
    jmp CONTINUE_EXECUTION

;; ON ERROR: sets the statements an error runs, ON ERROR statements, or ON ERROR OFF.
;;
;; The rest of the line is the handler: <ON_ERROR> is pointed at it and the line is skipped, to be run when an
;; error happens.
;; In: PTR_A_OFFSET = the offset after the ERROR token
ON_ERROR_STATEMENT:
    jsr GET_CHARACTER_A
    cmp #TOKEN_OFF
    beq ON_ERROR_OFF_STATEMENT
    ldy PTR_A_OFFSET
    dey
    jsr ADVANCE_PTR_A                       ; PTR_A to the handler's first character
    lda PTR_A
    sta ON_ERROR
    lda PTR_A+1
    sta ON_ERROR+1
    jmp SKIP_LINE

;; Raises error 39, "ON syntax": ON's value is not followed by GOTO or GOSUB.
ON_SYNTAX_ERROR:
    brk
    .byte ERROR_ON_SYNTAX, TOKEN_ON, " syntax", 0

;; ON: chooses a line by a number, ON n GOTO a,b,... or ON n GOSUB a,b,..., either followed by ELSE statements;
;; or ON ERROR.
;;
;; For n from 1 to the number of lines in the list, the program goes to (or calls) the n'th line; each can be an
;; expression. Any other n goes to the ELSE part, which is run as IF's ELSE is: a line number goes to that line,
;; anything else runs the statements after it. Without an ELSE it is an "ON range" error. After an ON GOSUB, RETURN
;; comes back to the end of the statement.
;; Errors: 39 = "ON syntax", 40 = "ON range", 41 = "No such line", 37 = "Too many GOSUBs", 6 = "Type mismatch"
;; See: <ON_ERROR_STATEMENT>, <GET_TARGET_LINE>
ON_STATEMENT:
    jsr GET_CHARACTER_A
    cmp #TOKEN_ERROR
    beq ON_ERROR_STATEMENT
    dec PTR_A_OFFSET
    jsr EVALUATE_EXPRESSION_A                       ; n; X = the character after it
    jsr CONVERT_A_TO_INTEGER
    ldy PTR_B_OFFSET
    iny
    sty PTR_A_OFFSET                ; after the GOTO or GOSUB
    cpx #TOKEN_GOTO
    beq ON_SELECT
    cpx #TOKEN_GOSUB
    bne ON_SYNTAX_ERROR
ON_SELECT:
    txa
    pha                             ; keep GOTO or GOSUB
    lda INT_A+1
    ora INT_A+2
    ora INT_A+3
    bne ON_OUT_OF_RANGE             ; above 255, or negative
    ldx INT_A
    beq ON_OUT_OF_RANGE
    dex
    beq ON_TARGET                   ; the first line in the list
    ldy PTR_A_OFFSET
ON_COUNT_LOOP:
    lda (PTR_A),y                   ; skip n-1 commas
    iny
    cmp #CARRIAGE_RETURN
    beq ON_OUT_OF_RANGE
    cmp #':'
    beq ON_OUT_OF_RANGE
    cmp #TOKEN_ELSE
    beq ON_OUT_OF_RANGE
    cmp #','
    bne ON_COUNT_LOOP
    dex
    bne ON_COUNT_LOOP
    sty PTR_A_OFFSET
ON_TARGET:
    jsr GET_TARGET_LINE
    pla
    cmp #TOKEN_GOSUB
    beq ON_GOSUB
    jsr RESET_PTR_A_OFFSET                       ; check ESCAPE; PTR_A_OFFSET = 1 for the line
    jmp JUMP_TO_LINE
ON_GOSUB:
    ldy PTR_A_OFFSET
ON_GOSUB_SKIP:
    lda (PTR_A),y                   ; skip the rest of the list, and any ELSE part, to the statement's end
    iny
    cmp #CARRIAGE_RETURN
    beq ON_GOSUB_END
    cmp #':'
    bne ON_GOSUB_SKIP
ON_GOSUB_END:
    dey
    sty PTR_A_OFFSET
    jmp GOSUB_TO_LINE
ON_OUT_OF_RANGE:
    ldy PTR_A_OFFSET
    pla                             ; drop GOTO or GOSUB
ON_FIND_ELSE:
    lda (PTR_A),y
    iny
    cmp #TOKEN_ELSE
    beq ON_ELSE
    cmp #CARRIAGE_RETURN
    bne ON_FIND_ELSE
    brk                             ; no ELSE
    .byte ERROR_ON_RANGE, TOKEN_ON, " range", 0
ON_ELSE:
    sty PTR_A_OFFSET
    jmp GOTO_LINE_OR_STATEMENT

;; Reads the line number after GOTO, GOSUB, ON and RESTORE, and finds the line.
;;
;; The number is a line number token or an expression, whose value is taken modulo &8000.
;; In: PTR_A_OFFSET = the number's offset
;; Out: TARGET_LINE = the line's length byte, INT_A = its number, PTR_A_OFFSET = after the number, Y = 2
;; Errors: 41 = "No such line", 6 = "Type mismatch"
;; Entry: FIND_TARGET_LINE = finds the line whose number is in INT_A
;; See: <FIND_LINE>, <GET_LINE_NUMBER>
GET_TARGET_LINE:
    jsr GET_LINE_NUMBER
    bcs FIND_TARGET_LINE
    jsr EVALUATE_EXPRESSION_A
    jsr CONVERT_A_TO_INTEGER
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    lda INT_A+1
    and #%01111111                  ; line numbers have 15 bits
    sta INT_A+1
FIND_TARGET_LINE:
    jsr FIND_LINE
    bcs NO_SUCH_LINE_ERROR
    rts

;; Raises error 41, "No such line".
NO_SUCH_LINE_ERROR:
    brk
    .byte ERROR_NO_SUCH_LINE, "No such line", 0

;; Raises "Type mismatch" for INPUT#: the value in the file is not of the variable's kind.
INPUT_FILE_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Raises "Syntax error" for INPUT#: there is no variable after a comma.
INPUT_FILE_SYNTAX_ERROR:
    jmp SYNTAX_ERROR

;; Ends INPUT#, at the character it read last.
;; In: Y = that character's offset
INPUT_FILE_DONE:
    sty PTR_A_OFFSET
    jmp FINISH_STATEMENT

;; INPUT#: reads values from a file into variables, INPUT# channel, v, w, ...
;;
;; Each value in the file is a type byte followed by the value, as PRINT# writes it: &00 and a string's length, then
;; its characters last first; &40 and an integer, most significant byte first; or &FF and a packed real, its last
;; byte first. A string goes only into a string variable, and a number into a numeric one, converted as it is
;; assigned.
;; In: PTR_A_OFFSET = the offset after the # (INPUT_STATEMENT has read it)
;; Errors: 6 = "Type mismatch", 16 = "Syntax error", 45 = "Missing #", and the filing system's errors
;; See: <INPUT_STATEMENT>
INPUT_FILE_STATEMENT:
    dec PTR_A_OFFSET                ; back to the #
    jsr READ_HANDLE_A                       ; read #channel: Y = the handle
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    sty INPUT_FILE_HANDLE
INPUT_FILE_LOOP:
    jsr GET_CHARACTER_A
    cmp #','
    bne INPUT_FILE_DONE
    lda INPUT_FILE_HANDLE
    pha
    jsr FIND_OR_CREATE_VARIABLE
    beq INPUT_FILE_SYNTAX_ERROR
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    pla
    sta INPUT_FILE_HANDLE
    php                             ; carry set for a string variable
    jsr PUSH_INTEGER                ; the descriptor, for the assignment
    ldy INPUT_FILE_HANDLE
    jsr OSBGET                      ; the value's type
    sta EXPRESSION_TYPE
    plp
    bcc INPUT_FILE_NUMBER
    lda EXPRESSION_TYPE
    bne INPUT_FILE_TYPE_MISMATCH
    jsr OSBGET
    sta STRING_LENGTH
    tax
    beq INPUT_FILE_ASSIGN_STRING
INPUT_FILE_STRING_LOOP:
    jsr OSBGET                      ; the characters come last first
    sta STRING_BUFFER-1,x
    dex
    bne INPUT_FILE_STRING_LOOP
INPUT_FILE_ASSIGN_STRING:
    jsr POP_ASSIGN_STRING
    jmp INPUT_FILE_LOOP
INPUT_FILE_NUMBER:
    lda EXPRESSION_TYPE
    beq INPUT_FILE_TYPE_MISMATCH
    bmi INPUT_FILE_REAL
    ldx #$03
INPUT_FILE_INTEGER_LOOP:
    jsr OSBGET                      ; most significant byte first
    sta INT_A,x
    dex
    bpl INPUT_FILE_INTEGER_LOOP
    bmi INPUT_FILE_ASSIGN_NUMBER    ; always taken
INPUT_FILE_REAL:
    ldx #$04
INPUT_FILE_REAL_LOOP:
    jsr OSBGET                      ; the packed real's last byte first
    sta FP_TEMP_1,x
    dex
    bpl INPUT_FILE_REAL_LOOP
    jsr LOAD_FP_A_TEMP_1                       ; FPA = FP_TEMP_1
INPUT_FILE_ASSIGN_NUMBER:
    jsr ASSIGN_NUMBER
    jmp INPUT_FILE_LOOP

;; Ends INPUT when no variable follows, dropping the flags it kept on the stack.
INPUT_DONE:
    pla
    pla
    jmp FINISH_STATEMENT

;; INPUT: reads values typed at the keyboard into variables, INPUT [LINE] prompts and variables; or INPUT#.
;;
;; Between the variables, strings in quotes, TAB(, SPC and ' are printed as PRINT prints them, as a prompt, and a
;; variable after a prompt always reads a new line. Each line typed is split into fields at its commas, and each
;; variable takes the next field, reading a new line when they run out (printing ? first, unless a prompt came
;; straight before the variable); a field in quotes can hold commas. A string variable takes the field's text, and a
;; numeric one its value as VAL would read it, so text that is not a number gives zero. INPUT LINE gives each
;; variable a whole line, commas, quotes and spaces included.
;; In: PTR_A_OFFSET = the offset after the INPUT token
;; Errors: 17 = "Escape", 9 = Missing " (a prompt's string not closed), 16 = "Syntax error"
;; See: <INPUT_FILE_STATEMENT>, <READ_LINE_TO_STRING>
INPUT_STATEMENT:
    jsr GET_CHARACTER_A
    cmp #'#'
    beq INPUT_FILE_STATEMENT
    cmp #TOKEN_LINE
    beq INPUT_SET_LINE              ; carry is set for INPUT LINE
    dec PTR_A_OFFSET
    clc
INPUT_SET_LINE:
    ror INPUT_FLAGS                 ; INPUT LINE into bit 7, and then bit 6
    lsr INPUT_FLAGS
    lda #$FF
    sta INPUT_FIELD                 ; read a line for the first variable
INPUT_ITEM:
    jsr PRINT_PROMPT_ITEM                       ; print a prompt item: carry clear if there was one
    bcs INPUT_SET_QUESTION
INPUT_PROMPT_LOOP:
    jsr PRINT_PROMPT_ITEM
    bcc INPUT_PROMPT_LOOP
    ldx #$FF
    stx INPUT_FIELD                 ; after a prompt, always read a new line
    clc
INPUT_SET_QUESTION:
    php                             ; bit 7 = carry: a ? when no prompt came just before
    asl INPUT_FLAGS
    plp
    ror INPUT_FLAGS
    cmp #','
    beq INPUT_ITEM
    cmp #';'
    beq INPUT_ITEM
    dec PTR_A_OFFSET
    lda INPUT_FLAGS
    pha
    lda INPUT_FIELD
    pha
    jsr FIND_OR_CREATE_VARIABLE
    beq INPUT_DONE
    pla
    sta INPUT_FIELD
    pla
    sta INPUT_FLAGS
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    php                             ; carry set for a string variable
    bit INPUT_FLAGS
    bvs INPUT_READ_LINE             ; INPUT LINE: always a new line
    lda INPUT_FIELD
    cmp #$FF
    bne INPUT_READ_FIELD            ; another field in the line already typed
INPUT_READ_LINE:
    bit INPUT_FLAGS
    bpl INPUT_GET_LINE
    lda #'?'
    jsr PRINT_CHARACTER
INPUT_GET_LINE:
    jsr READ_LINE_TO_STRING                       ; read a line into StrA; A = 0, Y = its length
    sty STRING_LENGTH
    asl INPUT_FLAGS                 ; no ? for the fields that follow
    clc
    ror INPUT_FLAGS
    bit INPUT_FLAGS
    bvs INPUT_ASSIGN                ; INPUT LINE: the whole line is the value
INPUT_READ_FIELD:
    sta PTR_B_OFFSET
    lda #<STRING_BUFFER
    sta PTR_B
    lda #>STRING_BUFFER
    sta PTR_B+1
    jsr READ_STRING_ITEM                       ; the field, into StrA
INPUT_FIND_COMMA:
    jsr GET_CHARACTER_B
    cmp #','
    beq INPUT_NEXT_FIELD
    cmp #CARRIAGE_RETURN
    bne INPUT_FIND_COMMA
    ldy #$FE                        ; the last field: &FF, a new line next time
INPUT_NEXT_FIELD:
    iny
    sty INPUT_FIELD
INPUT_ASSIGN:
    plp
    bcs INPUT_ASSIGN_STRING
    jsr PUSH_INTEGER                ; the descriptor
    jsr STRING_TO_NUMBER
    jsr ASSIGN_NUMBER
    jmp INPUT_ITEM
INPUT_ASSIGN_STRING:
    lda #$00
    sta EXPRESSION_TYPE
    jsr ASSIGN_STRING
    jmp INPUT_ITEM

;; RESTORE: makes READ start again at the first DATA of the program, RESTORE, or at line n, RESTORE n.
;;
;; <DATA_POINTER> is set to the start of the program, or to the text of line n; READ looks for DATA from there.
;; Errors: 41 = "No such line", 16 = "Syntax error"
;; See: <READ_STATEMENT>
RESTORE_STATEMENT:
    ldy #$00
    sty TARGET_LINE                 ; PAGE, for RESTORE alone
    ldy PAGE_HIGH
    sty TARGET_LINE+1
    jsr GET_CHARACTER_A
    dec PTR_A_OFFSET
    cmp #':'
    beq RESTORE_SET
    cmp #CARRIAGE_RETURN
    beq RESTORE_SET
    cmp #TOKEN_ELSE
    beq RESTORE_SET
    jsr GET_TARGET_LINE
    ldy #1
    jsr ADVANCE_LINE_POINTER                       ; past the length byte, to the line's text
RESTORE_SET:
    jsr CHECK_END_OF_STATEMENT
    lda TARGET_LINE
    sta DATA_POINTER
    lda TARGET_LINE+1
    sta DATA_POINTER+1
    jmp CONTINUE_EXECUTION

;; Goes on to READ's next variable after a comma, or ends READ.
READ_NEXT_ITEM:
    jsr GET_CHARACTER_A
    cmp #','
    beq READ_STATEMENT
    jmp FINISH_STATEMENT_BACK_ONE

;; READ: reads DATA items into variables, READ v, w, ...
;;
;; Each variable takes the next DATA item, found by <FIND_DATA_ITEM>. A numeric item is evaluated as an expression;
;; a string item is its text, up to a comma or the end of the line, or its quoted text. <DATA_POINTER> is left at
;; the end of the item for the next READ.
;; Errors: 42 = "Out of DATA", 6 = "Type mismatch", 16 = "Syntax error"
;; See: <RESTORE_STATEMENT>
READ_STATEMENT:
    jsr FIND_OR_CREATE_VARIABLE
    beq READ_NEXT_ITEM              ; no variable
    bcs READ_STRING
    jsr FIND_DATA_ITEM
    jsr PUSH_INTEGER                ; the descriptor
    jsr EVALUATE_AND_ASSIGN                       ; evaluate the item at PTR_B and assign it
    jmp READ_SAVE_POINTER
READ_STRING:
    jsr FIND_DATA_ITEM
    jsr PUSH_INTEGER
    jsr READ_STRING_ITEM                       ; the item, into StrA; A = 0, a string
    sta EXPRESSION_TYPE
    jsr POP_ASSIGN_STRING
READ_SAVE_POINTER:
    clc
    lda PTR_B_OFFSET
    adc PTR_B
    sta DATA_POINTER
    lda PTR_B+1
    adc #$00
    sta DATA_POINTER+1
    jmp READ_NEXT_ITEM

;; Finds the next DATA item from <DATA_POINTER>, pointing PTRB at it.
;;
;; At a comma, the item follows it. Otherwise the search goes on to the end of the line, then line by line for one
;; that starts with DATA; its first item follows the token. Text at the pointer that is neither a comma nor the end
;; of a line, as after RESTORE to a line that is not DATA, is skipped to the next comma or the end of the line.
;; In: PTR_B_OFFSET = READ's offset, after the variable
;; Out: PTR_B, PTR_B_OFFSET = the item, PTR_A_OFFSET = READ's offset
;; Errors: 42 = "Out of DATA", at the end of the program
;; Uses: A, X, Y
FIND_DATA_ITEM:
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    lda DATA_POINTER
    sta PTR_B
    lda DATA_POINTER+1
    sta PTR_B+1
    ldy #$00
    sty PTR_B_OFFSET
    jsr GET_CHARACTER_B
    cmp #','
    beq FIND_DATA_DONE
    cmp #TOKEN_DATA
    beq FIND_DATA_DONE
    cmp #CARRIAGE_RETURN
    beq FIND_DATA_LINE
FIND_DATA_SKIP:
    jsr GET_CHARACTER_B
    cmp #','
    beq FIND_DATA_DONE
    cmp #CARRIAGE_RETURN
    bne FIND_DATA_SKIP
FIND_DATA_LINE:
    ; PTR_B + PTR_B_OFFSET - 1 is the carriage return before the line: PTR_B moves on a line at a time, the
    ; offset staying the same.
    ldy PTR_B_OFFSET
    lda (PTR_B),y                   ; the line number's high byte
    bmi OUT_OF_DATA_ERROR           ; &FF: the end of the program
    iny
    iny
    lda (PTR_B),y
    tax                             ; the line's length
FIND_DATA_SKIP_SPACES:
    iny
    lda (PTR_B),y
    cmp #' '
    beq FIND_DATA_SKIP_SPACES
    cmp #TOKEN_DATA
    beq FIND_DATA_FOUND
    txa
    clc
    adc PTR_B
    sta PTR_B
    bcc FIND_DATA_LINE
    inc PTR_B+1
    bcs FIND_DATA_LINE              ; always taken

;; Raises error 42, "Out of DATA": READ found no more DATA items.
;;
;; The message has no zero of its own: the BRK that starts <NO_REPEAT_ERROR> ends it.
OUT_OF_DATA_ERROR:
    brk
    .byte ERROR_OUT_OF_DATA, "Out of ", TOKEN_DATA

;; Raises error 43, "No REPEAT": UNTIL with no REPEAT open. Its BRK ends the message of <OUT_OF_DATA_ERROR>.
NO_REPEAT_ERROR:
    brk
    .byte ERROR_NO_REPEAT, "No ", TOKEN_REPEAT, 0

;; Finishes <FIND_DATA_ITEM> at the DATA token that starts a line.
;; In: Y = the token's offset
FIND_DATA_FOUND:
    iny
    sty PTR_B_OFFSET
FIND_DATA_DONE:
    rts

;; UNTIL: ends a pass of a REPEAT loop, UNTIL condition.
;;
;; While the condition is FALSE (zero), the program goes back to the statement after the REPEAT, leaving the loop on
;; the REPEAT stack; when it is TRUE, the loop is taken off and the program goes on after the UNTIL.
;; Errors: 43 = "No REPEAT", 6 = "Type mismatch", 16 = "Syntax error"
;; See: <REPEAT_STATEMENT>
UNTIL_STATEMENT:
    jsr EVALUATE_EXPRESSION_A
    jsr CHECK_END_OF_EXPRESSION
    jsr CONVERT_TO_INTEGER
    ldx REPEAT_LEVEL
    beq NO_REPEAT_ERROR
    lda INT_A
    ora INT_A+1
    ora INT_A+2
    ora INT_A+3
    beq UNTIL_LOOP_BACK
    dec REPEAT_LEVEL
    jmp CONTINUE_EXECUTION
UNTIL_LOOP_BACK:
    ldy REPEAT_STACK_LOW-1,x
    lda REPEAT_STACK_HIGH-1,x
    jmp CONTINUE_AT

;; Raises error 44, "Too many REPEATs": twenty REPEAT loops are already open.
;; See: <REPEAT_STATEMENT>
TOO_MANY_REPEATS_ERROR:
    brk
    .byte ERROR_TOO_MANY_REPEATS, "Too many ", TOKEN_REPEAT, "s", 0
