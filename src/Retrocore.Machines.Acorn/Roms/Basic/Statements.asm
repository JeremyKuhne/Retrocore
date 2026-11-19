;; LET and assignment, PRINT, CLG, CLS and CALL ($8BE4-$8F30).
;;
;; - <LET_STATEMENT> assigns to a variable; <ASSIGN_STRING> stores a string in a string variable, claiming space on the
;;   heap when its old space is too small, or at an address ($X); <ASSIGN_FROM_STACK> puts back a value saved on
;;   BASIC's stack, for LOCAL and the parameters of PROCs and FNs.
;; - <PRINT_STATEMENT> and its items: `'`, TAB, SPC, `~`, `,` and `;`, numbers padded to @%'s field width, and PRINT#,
;;   which writes values to a file.
;; - <CLG_STATEMENT>, <CLS_STATEMENT> and <CALL_STATEMENT>, with <CALL_MACHINE_CODE>, which USR shares.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; Error numbers.
ERROR_TYPE_MISMATCH = $06           ;; error 6, "Type mismatch"
ERROR_NO_ROOM = $00                 ;; error 0, "No room": the heap has met BASIC's stack
ERROR_MISSING_QUOTE = $09           ;; error 9, 'Missing "'

; The VDU codes these statements send.
VDU_CLEAR_TEXT = 12                 ;; VDU 12: CLS, clears the text window
VDU_CLEAR_GRAPHICS = 16             ;; VDU 16: CLG, clears the graphics window
VDU_MOVE_TEXT_CURSOR = 31           ;; VDU 31,x,y: moves the text cursor, for TAB(x,y)

STRING_SPARE = 8                    ;; the bytes a string of eight or more characters is given beyond its length

; The parameter block CALL builds in StrA's buffer.
CALL_PARAMETER_COUNT = STRING_BUFFER    ;; the number of parameters, followed by three bytes for each
CALL_BLOCK_OFFSET = STRING_BUFFER + $FF ;; the offset of the last byte CALL has written in the block

; ---------------------------------------------------------------------------------------------------------------------
; LET and assignment
; ---------------------------------------------------------------------------------------------------------------------

;; LET: assigns a value to a variable: LET var = expression.
;;
;; An assignment without LET comes here from <IMPLIED_LET>. A variable that does not exist is made. The value must be
;; of the variable's kind: a string for a string, a number for a number, which is converted between integer and real
;; as needed; otherwise "Type mismatch". "Syntax error" when no variable follows LET, and "Mistake" when no = follows
;; the variable.
;; Entry: LET_ASSIGN = with the variable found: its descriptor in INT_A, zero clear, carry set for a string
LET_STATEMENT:
    jsr FIND_OR_CREATE_VARIABLE
    beq LET_SYNTAX_ERROR
LET_ASSIGN:
    bcc LET_NUMBER
    jsr PUSH_INTEGER                ; keep the descriptor
    jsr EVALUATE_EQUALS                       ; the = and the expression
    lda EXPRESSION_TYPE
    bne TYPE_MISMATCH_ERROR
    jsr POP_ASSIGN_STRING
    jmp CONTINUE_EXECUTION
LET_NUMBER:
    jsr PUSH_INTEGER                ; keep the descriptor
    jsr EVALUATE_EQUALS                       ; the = and the expression
    lda EXPRESSION_TYPE
    beq TYPE_MISMATCH_ERROR
    jsr ASSIGN_NUMBER
    jmp CONTINUE_EXECUTION
LET_SYNTAX_ERROR:
    jmp SYNTAX_ERROR

;; Raises error 6, "Type mismatch": a string where a number is needed, or a number where a string is.
TYPE_MISMATCH_ERROR:
    brk
    .byte ERROR_TYPE_MISMATCH
    .byte "Type mismatch",0

;; Pops a string variable's descriptor from BASIC's stack and assigns StrA to it.
;; Inherit: <ASSIGN_STRING>
;; In: BASIC_STACK = the descriptor, as PUSH_INTEGER left it, STRING_BUFFER/STRING_LENGTH = the string
POP_ASSIGN_STRING:
    jsr POP_INTEGER
;; Assigns StrA, the string at <STRING_BUFFER>, to the string variable or the address INT_A describes.
;;
;; A string variable's value is its string information block: the string's address (two bytes), the bytes allocated
;; to it and its current length. When the new string does not fit in the space allocated, new space is claimed at the
;; top of the heap: the string's length, or for a string of eight characters or more its length plus eight (at most
;; 255), so that it can grow a little without moving. If the old space is itself at the top of the heap, it is
;; extended there instead of being left behind. "No room" when the heap would reach BASIC's stack.
;;
;; For $X, the string is stored at the address with a carriage return after it.
;; In:
;;   INT_A = the address of the variable's string information block, or the address for $X
;;   INT_A+2 = <VARIABLE_STRING> for a variable, <VARIABLE_STRING_AT> for $X
;;   STRING_BUFFER/STRING_LENGTH = the string
;; Uses: A, X, Y, INT_A+2, INT_A+3, HEAP
ASSIGN_STRING:
    lda INT_A+2
    cmp #VARIABLE_STRING_AT
    beq ASSIGN_STRING_AT_ADDRESS
    ldy #$02
    lda (INT_A),y                   ; the bytes allocated
    cmp STRING_LENGTH
    bcs ASSIGN_STRING_COPY          ; it fits
    lda HEAP                        ; the new space's address: the top of the heap
    sta INT_A+2
    lda HEAP+1
    sta INT_A+3
    lda STRING_LENGTH
    cmp #STRING_SPARE
    bcc ASSIGN_STRING_SIZE
    adc #STRING_SPARE-1             ; carry is set: adds STRING_SPARE
    bcc ASSIGN_STRING_SIZE
    lda #$FF
ASSIGN_STRING_SIZE:
    clc
    pha
    tax                             ; X = the bytes to claim
    lda (INT_A),y                   ; is the old space at the top of the heap?
    ldy #$00
    adc (INT_A),y
    eor HEAP
    bne ASSIGN_STRING_CLAIM
    iny
    adc (INT_A),y
    eor HEAP+1
    bne ASSIGN_STRING_CLAIM
    sta INT_A+3                     ; zero: keep the old address
    txa                             ; claim only the bytes the old space lacks
    iny
    sec
    sbc (INT_A),y
    tax
ASSIGN_STRING_CLAIM:
    txa
    clc
    adc HEAP
    tay
    lda HEAP+1
    adc #$00
    cpy BASIC_STACK
    tax
    sbc BASIC_STACK+1
    bcs NO_ROOM_ERROR
    sty HEAP
    stx HEAP+1
    pla
    ldy #$02
    sta (INT_A),y                   ; the bytes allocated
    dey
    lda INT_A+3                     ; zero when the space was extended in place: no heap is in page 0
    beq ASSIGN_STRING_COPY
    sta (INT_A),y                   ; the new address
    dey
    lda INT_A+2
    sta (INT_A),y
ASSIGN_STRING_COPY:
    ldy #$03
    lda STRING_LENGTH
    sta (INT_A),y                   ; the current length
    beq ASSIGN_STRING_DONE
    dey
    dey
    lda (INT_A),y
    sta INT_A+3
    dey
    lda (INT_A),y
    sta INT_A+2
ASSIGN_STRING_LOOP:
    lda STRING_BUFFER,y
    sta (INT_A+2),y
    iny
    cpy STRING_LENGTH
    bne ASSIGN_STRING_LOOP
ASSIGN_STRING_DONE:
    rts
ASSIGN_STRING_AT_ADDRESS:
    jsr TERMINATE_STRING                       ; a carriage return after StrA; Y = its length
    cpy #$00
    beq ASSIGN_STRING_AT_LAST       ; an empty string: A is the carriage return
ASSIGN_STRING_AT_LOOP:
    lda STRING_BUFFER,y
    sta (INT_A),y
    dey
    bne ASSIGN_STRING_AT_LOOP
    lda STRING_BUFFER
ASSIGN_STRING_AT_LAST:
    sta (INT_A),y
    rts

;; Raises error 0, "No room": the heap has run into BASIC's stack.
NO_ROOM_ERROR:
    brk
    .byte ERROR_NO_ROOM
    .byte "No room",0

;; Pops a value from BASIC's stack into the variable at <WORK>, putting back a value LOCAL or a parameter saved.
;;
;; The value is of the variable's own type: a byte, an integer or a real is copied as it is; a string is copied into the
;; variable's present space, which is assumed to be big enough, and its length set; a string at an address ($X) is
;; copied there with a carriage return after it.
;; In:
;;   WORK = the variable's value, or the address for $X
;;   WORK+2 = the type: <VARIABLE_BYTE>, <VARIABLE_INTEGER>, <VARIABLE_REAL>, <VARIABLE_STRING> or
;;     <VARIABLE_STRING_AT>
;;   BASIC_STACK = the value, a string as its length and then its characters
;; Out: BASIC_STACK = above the value
;; Uses: A, X, Y, WORK+2, WORK+3
ASSIGN_FROM_STACK:
    lda WORK+2
    cmp #VARIABLE_STRING_AT
    beq ASSIGN_FROM_STACK_AT_ADDRESS
    bcc ASSIGN_FROM_STACK_NUMBER
    ldy #$00                        ; a string variable
    lda (BASIC_STACK),y
    tax                             ; X = the length
    beq ASSIGN_FROM_STACK_LENGTH
    lda (WORK),y                    ; carry is set: WORK+2 = the string's address less one
    sbc #$01
    sta WORK+2
    iny
    lda (WORK),y
    sbc #$00
    sta WORK+3
ASSIGN_FROM_STACK_STRING_LOOP:
    lda (BASIC_STACK),y
    sta (WORK+2),y
    iny
    dex
    bne ASSIGN_FROM_STACK_STRING_LOOP
ASSIGN_FROM_STACK_LENGTH:
    lda (BASIC_STACK,x)             ; X is zero: the length
    ldy #$03
ASSIGN_FROM_STACK_STORE_LAST:
    sta (WORK),y
    jmp DROP_STRING                       ; drop the string from the stack
ASSIGN_FROM_STACK_AT_ADDRESS:
    ldy #$00
    lda (BASIC_STACK),y
    tax
    beq ASSIGN_FROM_STACK_AT_END
ASSIGN_FROM_STACK_AT_LOOP:
    iny
    lda (BASIC_STACK),y
    dey
    sta (WORK),y
    iny
    dex
    bne ASSIGN_FROM_STACK_AT_LOOP
ASSIGN_FROM_STACK_AT_END:
    lda #CARRIAGE_RETURN
    bne ASSIGN_FROM_STACK_STORE_LAST ; always taken
ASSIGN_FROM_STACK_NUMBER:
    ldy #$00
    lda (BASIC_STACK),y
    sta (WORK),y
    iny
    cpy WORK+2
    bcs ASSIGN_FROM_STACK_DROP      ; a byte
    lda (BASIC_STACK),y
    sta (WORK),y
    iny
    lda (BASIC_STACK),y
    sta (WORK),y
    iny
    lda (BASIC_STACK),y
    sta (WORK),y
    iny
    cpy WORK+2
    bcs ASSIGN_FROM_STACK_DROP      ; an integer
    lda (BASIC_STACK),y
    sta (WORK),y
    iny
ASSIGN_FROM_STACK_DROP:
    tya                             ; drop the bytes copied
    clc
    jmp DROP_STACK_BYTES

; ---------------------------------------------------------------------------------------------------------------------
; PRINT
; ---------------------------------------------------------------------------------------------------------------------

;; PRINT#: writes values to a file: PRINT# channel, expression, ...
;;
;; Each value is written as its type byte (&00 string, &40 integer, &FF real, or &80 for ASN's or ATN's negative
;; result, as <EXPRESSION_TYPE> holds it) and then its bytes in reverse order: an integer's four bytes, most
;; significant first; a real's five bytes, packed, from the last; a string's length and then its characters, from the
;; last. INPUT# reads them back.
;; In: PTR_A_OFFSET = just past the #
PRINT_TO_FILE:
    dec PTR_A_OFFSET
    jsr READ_HANDLE_A                       ; Y = the channel
PRINT_TO_FILE_LOOP:
    tya
    pha
    jsr GET_CHARACTER_B
    cmp #','
    bne PRINT_TO_FILE_END
    jsr EVALUATE_EXPRESSION
    jsr STORE_FP_A_TEMP_1                       ; pack FPA at FP_TEMP_1, in case it is a real
    pla
    tay
    lda EXPRESSION_TYPE
    jsr OSBPUT
    tax
    beq PRINT_TO_FILE_STRING
    bmi PRINT_TO_FILE_REAL
    ldx #$03
PRINT_TO_FILE_INTEGER:
    lda INT_A,x
    jsr OSBPUT
    dex
    bpl PRINT_TO_FILE_INTEGER
    bmi PRINT_TO_FILE_LOOP          ; always taken
PRINT_TO_FILE_REAL:
    ldx #$04
PRINT_TO_FILE_REAL_LOOP:
    lda FP_TEMP_1,x
    jsr OSBPUT
    dex
    bpl PRINT_TO_FILE_REAL_LOOP
    bmi PRINT_TO_FILE_LOOP          ; always taken
PRINT_TO_FILE_STRING:
    lda STRING_LENGTH
    jsr OSBPUT
    tax
    beq PRINT_TO_FILE_LOOP
PRINT_TO_FILE_STRING_LOOP:
    lda STRING_BUFFER-1,x
    jsr OSBPUT
    dex
    bne PRINT_TO_FILE_STRING_LOOP
    beq PRINT_TO_FILE_LOOP          ; always taken
PRINT_TO_FILE_END:
    pla
    sty PTR_A_OFFSET
    jmp FINISH_STATEMENT

;; Ends PRINT with a new line, the items not having ended with `;`.
PRINT_END_NEWLINE:
    jsr PRINT_NEWLINE
PRINT_END:
    jmp FINISH_STATEMENT_BACK_ONE

;; `;`: prints the next item with no padding, or ends PRINT without a new line.
PRINT_SEMICOLON:
    lda #$00
    sta PRINT_FIELD_WIDTH
    sta PRINT_HEX
    jsr GET_CHARACTER_A
    cmp #':'
    beq PRINT_END
    cmp #CARRIAGE_RETURN
    beq PRINT_END
    cmp #TOKEN_ELSE
    beq PRINT_END
    bne PRINT_ITEM                  ; always taken

;; PRINT: prints its items: PRINT [#channel,] [items], the items strings, numbers and the separators.
;;
;; - A number is printed in decimal by the format in @%, padded on the left to @%'s field width (its low byte); after
;;   `~`, in hexadecimal.
;; - `,` moves on to the next field: to the next multiple of the field width, unless the cursor is at one already
;;   (COUNT 0, 10 or 20 with a width of 10), where it prints no spaces and stays.
;; - `;` prints the next item with no padding, and at the end stops the new line PRINT ends with.
;; - `'` starts a new line; TAB(x) moves to column x, starting a new line first if the cursor is past it; TAB(x,y)
;;   moves the cursor to x,y; SPC n prints n spaces.
;; - A string in quotes, or any string expression, is printed as it is.
;;
;; `,` puts @%'s field width and decimal back, `;` sets the field width to 0 and decimal, and `'`, TAB and SPC leave
;; both as they were, so PRINT ~15'15 prints both numbers in hexadecimal. The items end at a colon, a carriage return
;; or ELSE, with a new line unless the last was `;`.
;; See: <PRINT_TO_FILE>, <NUMBER_TO_STRING>
PRINT_STATEMENT:
    jsr GET_CHARACTER_A
    cmp #'#'
    beq PRINT_TO_FILE
    dec PTR_A_OFFSET
    jmp PRINT_RESET_FORMAT
PRINT_COMMA:
    lda AT_PERCENT                  ; the field width
    beq PRINT_RESET_FORMAT
    lda COUNT                       ; carry is set: A = COUNT MOD width - width
PRINT_COMMA_MODULO:
    beq PRINT_RESET_FORMAT
    sbc AT_PERCENT
    bcs PRINT_COMMA_MODULO
    tay                             ; Y = minus the spaces to the next field
PRINT_COMMA_PAD:
    jsr PRINT_SPACE
    iny
    bne PRINT_COMMA_PAD
PRINT_RESET_FORMAT:
    clc                             ; decimal
    lda AT_PERCENT
    sta PRINT_FIELD_WIDTH
PRINT_SET_HEX:
    ror PRINT_HEX                   ; the carry: set after ~, clear for decimal
PRINT_NEXT_ITEM:
    jsr GET_CHARACTER_A
    cmp #':'
    beq PRINT_END_NEWLINE
    cmp #CARRIAGE_RETURN
    beq PRINT_END_NEWLINE
    cmp #TOKEN_ELSE
    beq PRINT_END_NEWLINE
PRINT_ITEM:
    cmp #'~'
    beq PRINT_SET_HEX               ; carry is set
    cmp #','
    beq PRINT_COMMA
    cmp #';'
    beq PRINT_SEMICOLON
    jsr PRINT_SPACING_ITEM
    bcc PRINT_NEXT_ITEM
    lda PRINT_FIELD_WIDTH           ; keep the format: the expression may PRINT, in an FN
    pha
    lda PRINT_HEX
    pha
    dec PTR_B_OFFSET
    jsr EVALUATE_EXPRESSION
    pla
    sta PRINT_HEX
    pla
    sta PRINT_FIELD_WIDTH
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    tya
    beq PRINT_STRA                  ; a string
    jsr NUMBER_TO_STRING
    lda PRINT_FIELD_WIDTH
    sec
    sbc STRING_LENGTH
    bcc PRINT_STRA
    beq PRINT_STRA
    tay                             ; Y = the spaces to pad with
PRINT_PAD_NUMBER:
    jsr PRINT_SPACE
    dey
    bne PRINT_PAD_NUMBER
PRINT_STRA:
    lda STRING_LENGTH
    beq PRINT_NEXT_ITEM
    ldy #$00
PRINT_STRA_LOOP:
    lda STRING_BUFFER,y
    jsr PRINT_CHARACTER
    iny
    cpy STRING_LENGTH
    bne PRINT_STRA_LOOP
    beq PRINT_NEXT_ITEM             ; always taken

;; Raises "Missing ,": TAB( with a second argument not after a comma.
TAB_MISSING_COMMA:
    jmp MISSING_COMMA_ERROR
;; TAB(x,y): moves the text cursor to column x, row y, with VDU 31.
;;
;; It does not change COUNT.
;; In: INT_A = x, A = the character after it, PTR_B_OFFSET = just past it
PRINT_TAB_XY:
    cmp #','
    bne TAB_MISSING_COMMA
    lda INT_A
    pha
    jsr EVALUATE_TO_CLOSE_BRACKET                       ; y and the )
    jsr CONVERT_A_TO_INTEGER
    lda #VDU_MOVE_TEXT_CURSOR
    jsr OSWRCH
    pla
    jsr OSWRCH
    jsr WRITE_INT_A                       ; y
    jmp PRINT_SPACING_DONE
;; TAB(: moves to a column by printing spaces, or with TAB(x,y), to a position on the screen.
;;
;; Only x's low byte is used, so TAB(256) is TAB(0). TAB(x) prints spaces up to column x, counting by COUNT; when the
;; cursor is already past x, it starts a new line and prints x spaces.
;; In: PTR_B, PTR_B_OFFSET = just past TAB(
PRINT_TAB:
    jsr EVALUATE_INTEGER
    jsr GET_CHARACTER_B
    cmp #')'
    bne PRINT_TAB_XY
    lda INT_A                       ; carry is set
    sbc COUNT
    beq PRINT_SPACING_DONE
    tay
    bcs PRINT_SPACES_LOOP           ; Y = the spaces to column x
    jsr PRINT_NEWLINE
    beq PRINT_SPACES                ; always taken: PRINT_NEWLINE returns A = 0
;; SPC: prints the number of spaces that follows, a factor, taking only its low byte: SPC 256 prints none and SPC 257
;; one.
;; In: PTR_B, PTR_B_OFFSET = just past SPC
;; Entry:
;;   PRINT_SPACES = prints as many spaces as INT_A's low byte, none for zero
;;   PRINT_SPACES_LOOP = prints Y spaces, Y not zero
PRINT_SPC:
    jsr EVALUATE_INTEGER_FACTOR
PRINT_SPACES:
    ldy INT_A
    beq PRINT_SPACING_DONE
PRINT_SPACES_LOOP:
    jsr PRINT_SPACE
    dey
    bne PRINT_SPACES_LOOP
    beq PRINT_SPACING_DONE          ; always taken
;; `'`: starts a new line.
PRINT_APOSTROPHE:
    jsr PRINT_NEWLINE
PRINT_SPACING_DONE:
    clc
    ldy PTR_B_OFFSET
    sty PTR_A_OFFSET
    rts

;; Prints a spacing item of PRINT or INPUT: `'`, TAB or SPC.
;;
;; PTRB is set to PTRA, so that the item's argument is read through PTRB; PTRA is moved past the item.
;; In: A = the item's first character, PTR_A_OFFSET = just past it
;; Out: carry = clear when it was a spacing item and has been printed, set when it is something else
;; Uses: A (when the item is printed), X, Y
PRINT_SPACING_ITEM:
    ldx PTR_A
    stx PTR_B
    ldx PTR_A+1
    stx PTR_B+1
    ldx PTR_A_OFFSET
    stx PTR_B_OFFSET
    cmp #$27                        ; `'`
    beq PRINT_APOSTROPHE
    cmp #TOKEN_TAB
    beq PRINT_TAB
    cmp #TOKEN_SPC
    beq PRINT_SPC
    sec
PRINT_SPACING_ITEM_DONE:
    rts

;; Prints an item of INPUT's prompt: `'`, TAB, SPC or a string in quotes.
;;
;; In the string, two quotes print one.
;; In: PTR_A, PTR_A_OFFSET = the item
;; Out: carry = clear when it was printed, set when it is something else, A = its first character when carry is set
;; Uses: X, Y
PRINT_PROMPT_ITEM:
    jsr GET_CHARACTER_A
    jsr PRINT_SPACING_ITEM
    bcc PRINT_SPACING_ITEM_DONE
    cmp #'"'
    beq PRINT_QUOTED_NEXT
    sec
    rts
;; Raises error 9, 'Missing "': a string with no closing quote.
MISSING_QUOTE_ERROR:
    brk
    .byte ERROR_MISSING_QUOTE
    .byte "Missing ",'"',0
;; Prints a string in quotes, a doubled quote as one, from a character of it.
;; In: A = the character to print first, PTR_B,Y = it
;; Entry: PRINT_QUOTED_NEXT = starts at the opening quote, PTR_B,Y, without printing it
;; Out: PTR_B_OFFSET = just past the closing quote, PTR_A_OFFSET = the same, carry = clear
PRINT_QUOTED_CHARACTER:
    jsr PRINT_CHARACTER
PRINT_QUOTED_NEXT:
    iny
    lda (PTR_B),y
    cmp #CARRIAGE_RETURN
    beq MISSING_QUOTE_ERROR
    cmp #'"'
    bne PRINT_QUOTED_CHARACTER
    iny
    sty PTR_B_OFFSET
    lda (PTR_B),y
    cmp #'"'
    bne PRINT_SPACING_DONE
    beq PRINT_QUOTED_CHARACTER      ; always taken: a doubled quote

; ---------------------------------------------------------------------------------------------------------------------
; CLG, CLS and CALL
; ---------------------------------------------------------------------------------------------------------------------

;; CLG: clears the graphics window to the graphics background colour, with VDU 16.
CLG_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    lda #VDU_CLEAR_GRAPHICS
    bne CLEAR_SCREEN                ; always taken

;; CLS: clears the text window to the text background colour, with VDU 12, and sets COUNT to zero.
;; Entry: CLEAR_SCREEN = sends the VDU code in A, and goes on with the next statement
CLS_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    jsr RESET_COUNT
    lda #VDU_CLEAR_TEXT
CLEAR_SCREEN:
    jsr OSWRCH
    jmp CONTINUE_EXECUTION

;; CALL: calls machine code: CALL address [, variable, ...].
;;
;; The variables' descriptors are passed in a parameter block at &0600, <CALL_PARAMETER_COUNT>: the number of
;; parameters, then for each its address (two bytes, low first) and its type (one byte): 0 for a byte (?X), 4 for an
;; integer (!X or X%), 5 for a real, &80 for a string at an address ($X) and &81 for a string variable, whose address
;; is that of its string information block (the string's address, the bytes allocated and its length). A, X and Y are
;; loaded from A%, X% and Y%, and the carry from bit 0 of C%. The code returns with RTS; decimal mode is cleared after
;; it. A name that is not a variable raises "No such variable".
;; See: <CALL_MACHINE_CODE>
CALL_STATEMENT:
    jsr EVALUATE_EXPRESSION_A
    jsr CONVERT_TO_INTEGER
    jsr PUSH_INTEGER                ; keep the address
    ldy #$00
    sty CALL_PARAMETER_COUNT
CALL_PARAMETER:
    sty CALL_BLOCK_OFFSET
    jsr GET_CHARACTER_B
    cmp #','
    bne CALL_GO
    ldy PTR_B_OFFSET
    jsr FIND_VARIABLE_B
    beq CALL_NO_SUCH_VARIABLE
    ldy CALL_BLOCK_OFFSET
    iny
    lda INT_A                       ; the parameter's address
    sta STRING_BUFFER,y
    iny
    lda INT_A+1
    sta STRING_BUFFER,y
    iny
    lda INT_A+2                     ; its type
    sta STRING_BUFFER,y
    inc CALL_PARAMETER_COUNT
    jmp CALL_PARAMETER
CALL_GO:
    dec PTR_B_OFFSET
    jsr CHECK_END_OF_STATEMENT_B
    jsr POP_INTEGER                 ; the address
    jsr CALL_MACHINE_CODE
    cld
    jmp CONTINUE_EXECUTION
CALL_NO_SUCH_VARIABLE:
    jmp NO_SUCH_VARIABLE

;; Calls the machine code at INT_A, with A, X and Y loaded from A%, X% and Y%, and the carry from bit 0 of C%.
;;
;; The code returns to this routine's caller with its RTS. CALL and USR use it.
;; In: INT_A = the address
;; Out: A = as the code leaves it, X = likewise, Y = likewise, the flags likewise
CALL_MACHINE_CODE:
    lda C_PERCENT
    lsr a
    lda A_PERCENT
    ldx X_PERCENT
    ldy Y_PERCENT
    jmp (INT_A)

;; Raises "Syntax error": a jump within branch range of the statements that follow.
SYNTAX_ERROR_RELAY:
    jmp SYNTAX_ERROR
