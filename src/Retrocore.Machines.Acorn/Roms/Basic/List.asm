;; Assigning numbers, printing characters and tokens, LISTO and LIST ($B4B4-$B694).
;;
;; - <ASSIGN_NUMBER> stores the number in IntA or FPA in a variable, given its descriptor.
;; - <PRINT_CHARACTER> prints a character, keeping <COUNT> and starting a new line at <WIDTH>;
;;   <PRINT_CHARACTER_OR_TOKEN> prints a token as its keyword, found in the keyword table; <PRINT_HEX_BYTE> and
;;   <PRINT_SPACE> are built on it.
;; - LISTO and <LIST_COMMAND>, which lists the program, adding the spaces <LISTO> asks for.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------


; The bits of <LISTO>, as <PRINT_LISTO_SPACES> tests them.
LISTO_LINE_NUMBER_SPACE = %001      ;; LISTO 1: a space after each line number
LISTO_INDENT_FOR = %010             ;; LISTO 2: two spaces of indent for each FOR loop open
LISTO_INDENT_REPEAT = %100          ;; LISTO 4: two spaces of indent for each REPEAT loop open

LIST_DEFAULT_END = $7FFF            ;; the highest line number, where LIST stops when no end is given

; LIST's work bytes.
LIST_FOR_DEPTH = FP_B_SIGN          ;; the FOR loops LIST has seen open, for LISTO's indent
LIST_REPEAT_DEPTH = FP_B_OVERFLOW   ;; the REPEAT loops LIST has seen open, for LISTO's indent
LIST_END = FP_A_MANTISSA            ;; the last line number to list, low byte first
LIST_QUOTE_FLAG = SERIES_POINTER    ;; &FF outside quotes, where tokens are expanded; &00 inside a string

; The token search's work bytes.
SEARCH_TOKEN = WORK                 ;; the token <PRINT_CHARACTER_OR_TOKEN> is looking for
SEARCH_ENTRY = WORK + 1             ;; a pointer to the keyword table entry being compared
SEARCH_SAVED_Y = WORK + 3           ;; the caller's Y, kept while searching

ERROR_NO_FOR = 32                   ;; error 32, "No FOR"

;; Pops a variable's descriptor from BASIC's stack and assigns the number in IntA or FPA to it.
;;
;; The descriptor (pushed by the caller, typically after <FIND_OR_CREATE_VARIABLE> found the variable) is the variable's
;; address and its type: 0 for a byte (?), 4 for an integer (!, or a variable ending in %) and 5 for a real. An integer
;; value is converted to a real for a real variable, and a real truncated to an integer for an integer variable; a byte
;; variable gets the low byte of the integer. A string value raises "Type mismatch".
;; In: EXPRESSION_TYPE = the value's type, INT_A or FP_A = the value, BASIC_STACK = the descriptor on top
;; Uses: A, X, Y, WORK..WORK+3, FP_A_SIGN, INT_A (when converted), FP_A (when converted)
;; Errors: 6 = "Type mismatch", for a string
;; Entry: ASSIGN_NUMBER_TO = assigns to the variable whose descriptor is already in WORK..WORK+2, without popping
;; See: <EVALUATE_AND_ASSIGN>, <STORE_FP_A_IN_VARIABLE>
ASSIGN_NUMBER:
    jsr POP_INTEGER_TO_WORK                       ; pop the descriptor into WORK..WORK+3
ASSIGN_NUMBER_TO:
    lda WORK+2
    cmp #VARIABLE_REAL
    beq ASSIGN_NUMBER_REAL
    lda EXPRESSION_TYPE
    beq ASSIGN_TYPE_MISMATCH                       ; a string: "Type mismatch"
    bpl ASSIGN_NUMBER_INTEGER
    jsr REAL_TO_INTEGER
ASSIGN_NUMBER_INTEGER:
    ldy #$00
    lda INT_A
    sta (WORK),y
    lda WORK+2
    beq ASSIGN_NUMBER_DONE          ; a byte variable takes only the low byte
    lda INT_A+1
    iny
    sta (WORK),y
    lda INT_A+2
    iny
    sta (WORK),y
    lda INT_A+3
    iny
    sta (WORK),y
ASSIGN_NUMBER_DONE:
    rts
ASSIGN_NUMBER_REAL:
    lda EXPRESSION_TYPE
    beq ASSIGN_TYPE_MISMATCH                       ; a string: "Type mismatch"
    bmi STORE_FP_A_IN_VARIABLE
    jsr INTEGER_TO_REAL
    ; Falls through into STORE_FP_A_IN_VARIABLE.

;; Packs FPA into the five bytes of a real variable: the exponent, then the mantissa most significant byte first,
;; with the sign in place of the mantissa's top bit, which is always set.
;; In: FP_A = the value, WORK/WORK+1 = the variable's address
;; Out: FP_A_SIGN = only its sign bit kept
;; Uses: A, Y
;; Keeps: X
STORE_FP_A_IN_VARIABLE:
    ldy #$00
    lda FP_A_EXPONENT
    sta (WORK),y
    iny
    lda FP_A_SIGN
    and #%10000000
    sta FP_A_SIGN
    lda FP_A_MANTISSA
    and #%01111111                  ; the mantissa's top bit becomes the sign
    ora FP_A_SIGN
    sta (WORK),y
    iny
    lda FP_A_MANTISSA+1
    sta (WORK),y
    iny
    lda FP_A_MANTISSA+2
    sta (WORK),y
    iny
    lda FP_A_MANTISSA+3
    sta (WORK),y
    rts

;; Prints a character, or a token as its keyword.
;;
;; A token (&80-&FF) is looked up in <KEYWORD_TABLE>, whose entries are each a keyword's letters, its token (the
;; first byte with bit 7 set) and a flags byte. The search compares each entry's token with A and steps
;; over the entry when it differs, so it relies on every token it is given being in the table; LIST handles the line
;; number token, &8D, itself. The keyword is then printed with <PRINT_CHARACTER>, so it counts towards <COUNT>.
;; In: A = the character or token
;; Uses: A, WORK, WORK+1..WORK+3 (for a token)
;; Keeps: X, Y
;; See: <PRINT_CHARACTER>, <LIST_COMMAND>
PRINT_CHARACTER_OR_TOKEN:
    sta SEARCH_TOKEN
    cmp #TOKEN_AND                  ; the first token
    bcc PRINT_CHARACTER             ; not a token
    lda #<KEYWORD_TABLE
    sta SEARCH_ENTRY
    lda #>KEYWORD_TABLE
    sta SEARCH_ENTRY+1
    sty SEARCH_SAVED_Y
PRINT_TOKEN_ENTRY:
    ldy #$00
PRINT_TOKEN_FIND_TOKEN:
    iny
    lda (SEARCH_ENTRY),y
    bpl PRINT_TOKEN_FIND_TOKEN      ; skip the keyword's letters
    cmp SEARCH_TOKEN
    beq PRINT_TOKEN_FOUND
    iny                             ; skip the flags byte
    tya
    sec                             ; and step to the next entry, Y + 1 bytes on
    adc SEARCH_ENTRY
    sta SEARCH_ENTRY
    bcc PRINT_TOKEN_ENTRY
    inc SEARCH_ENTRY+1
    bcs PRINT_TOKEN_ENTRY           ; always taken
PRINT_TOKEN_FOUND:
    ldy #$00
PRINT_TOKEN_LETTER:
    lda (SEARCH_ENTRY),y
    bmi PRINT_TOKEN_DONE            ; the token ends the keyword
    jsr PRINT_CHARACTER
    iny
    bne PRINT_TOKEN_LETTER          ; always taken
PRINT_TOKEN_DONE:
    ldy SEARCH_SAVED_Y
    rts

;; Prints a byte as two hexadecimal digits, counting them in <COUNT>.
;; In: A = the byte
;; Uses: A
;; Keeps: X, Y
;; Entry: PRINT_HEX_DIGIT = prints the low nibble of A (0-15) as one digit
PRINT_HEX_BYTE:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PRINT_HEX_DIGIT
    pla
    and #$0F
PRINT_HEX_DIGIT:
    cmp #10
    bcc PRINT_HEX_DIGIT_DECIMAL
    adc #'A' - '0' - 10 - 1         ; carry is set: A-F
PRINT_HEX_DIGIT_DECIMAL:
    adc #'0'
    ; Falls through into PRINT_CHARACTER.

;; Prints a character through WRCHV, keeping <COUNT>, BASIC's count of the characters on the line.
;;
;; A carriage return goes to OSWRCH and sets COUNT to zero. Before any other character, a new line is started when
;; COUNT has passed <WIDTH> (WIDTH holds the width less one, &FF for no wrapping); the character is then counted and
;; sent through WRCHV directly.
;; In: A = the character
;; Out: A = zero after a carriage return, otherwise the character
;; Keeps: X, Y
;; See: <PRINT_CHARACTER_OR_TOKEN>, <PRINT_SPACE>, <PRINT_NEWLINE>
PRINT_CHARACTER:
    cmp #CARRIAGE_RETURN
    bne PRINT_COUNTED
    jsr OSWRCH
    jmp RESET_COUNT                       ; set COUNT to zero

;; Prints a byte as two hexadecimal digits and a space.
;; In: A = the byte
;; Out: A = a space
;; Keeps: X, Y
PRINT_HEX_BYTE_SPACE:
    jsr PRINT_HEX_BYTE
    ; Falls through into PRINT_SPACE.

;; Prints a space, counting it and wrapping at <WIDTH> as <PRINT_CHARACTER> does.
;; Out: A = a space
;; Keeps: X, Y
;; Entry: PRINT_COUNTED = prints the character in A, which is not a carriage return
PRINT_SPACE:
    lda #' '
PRINT_COUNTED:
    pha
    lda WIDTH
    cmp COUNT
    bcs PRINT_COUNTED_FITS
    jsr PRINT_NEWLINE
PRINT_COUNTED_FITS:
    pla
    inc COUNT
    jmp (WRCHV)

;; Prints the spaces one of LISTO's options asks for: two for each loop open, or one after a line number.
;;
;; Nothing is printed unless the option's bit is set in <LISTO>.
;; In: A = the option's bit (one of the LISTO_ constants), X = the number of loops open, or negative for one space
;; Out: X = zero when spaces were printed for loops
;; Uses: A
;; Keeps: Y
PRINT_LISTO_SPACES:
    and LISTO
    beq PRINT_LISTO_SPACES_DONE
    txa
    beq PRINT_LISTO_SPACES_DONE
    bmi PRINT_SPACE                 ; the one space after a line number
PRINT_LISTO_SPACES_LOOP:
    jsr PRINT_SPACE
    jsr PRINT_CHARACTER             ; another space: PRINT_SPACE leaves it in A
    dex
    bne PRINT_LISTO_SPACES_LOOP
PRINT_LISTO_SPACES_DONE:
    rts

;; LISTO: sets the spaces LIST adds, as LISTO n.
;;
;; The value's low byte becomes <LISTO>: bit 0 adds a space after each line number, bit 1 indents the lines inside
;; FOR loops and bit 2 the lines inside REPEAT loops. The command is entered from <LIST_COMMAND>, which sees LISTO as
;; LIST followed by the letter O, and returns to immediate mode.
;; In: PTR_A_OFFSET = the offset of the O
;; Errors: 6 = "Type mismatch", 16 = "Syntax error"
LISTO_COMMAND:
    inc PTR_A_OFFSET                ; step over the O
    jsr EVALUATE_EXPRESSION_A
    jsr CHECK_END_OF_EXPRESSION
    jsr CONVERT_TO_INTEGER
    lda INT_A
    sta LISTO
    jmp IMMEDIATE_MODE

;; LIST: lists the program, or part of it: LIST, LIST n, LIST n, (from n), LIST ,m (to m) or LIST n,m.
;;
;; The range is given by line numbers, stored as line number tokens. A single number lists that line; a range missing
;; its start begins at the first line, and one missing its end runs to the last. Each line is printed with its
;; number in five columns, then the spaces <LISTO> asks for, then its text with tokens printed as keywords, except
;; inside strings. To indent, LIST counts the FOR, NEXT, REPEAT and UNTIL tokens as it prints them, from zero at the
;; start of the listing, so a NEXT or UNTIL is indented as the lines inside its loop are. The program is checked
;; first (a damaged one prints "Bad program" and returns to immediate mode), and listing stops at ESCAPE. LIST
;; followed by O is <LISTO_COMMAND>. LIST ends in immediate mode, so it also ends a program that uses it.
;; In: Y = the offset of the LIST token, PTR_A_OFFSET = the offset after it
;; Errors: 16 = "Syntax error", 17 = "Escape"
;; Uses: A, X, Y, INT_A, LIST_FOR_DEPTH, LIST_REPEAT_DEPTH, LIST_END, LIST_QUOTE_FLAG, FP_B_EXPONENT, FP_B_MANTISSA
LIST_COMMAND:
    iny
    lda (PTR_A),y
    cmp #'O'
    beq LISTO_COMMAND
    lda #$00
    sta LIST_FOR_DEPTH
    sta LIST_REPEAT_DEPTH
    jsr LOAD_INT_A_BYTE                       ; the start defaults to line 0
    jsr GET_LINE_NUMBER
    php
    jsr PUSH_INTEGER                ; keep the start
    lda #<LIST_DEFAULT_END
    sta INT_A
    lda #>LIST_DEFAULT_END
    sta INT_A+1
    plp
    bcc LIST_NO_START
    jsr GET_CHARACTER_A
    cmp #','
    beq LIST_READ_END
    jsr POP_INTEGER                 ; one line: it is both the start and the end
    jsr PUSH_INTEGER
    dec PTR_A_OFFSET
    bpl LIST_RANGE_READ             ; always taken
LIST_NO_START:
    jsr GET_CHARACTER_A
    cmp #','
    beq LIST_READ_END
    dec PTR_A_OFFSET
LIST_READ_END:
    jsr GET_LINE_NUMBER             ; INT_A keeps LIST_DEFAULT_END when there is none
LIST_RANGE_READ:
    lda INT_A
    sta LIST_END
    lda INT_A+1
    sta LIST_END+1
    jsr CHECK_END_OF_STATEMENT
    jsr FIND_PROGRAM_END                       ; check the program
    jsr POP_INTEGER
    jsr FIND_LINE
    lda FP_B_EXPONENT
    sta PTR_A
    lda FP_B_MANTISSA
    sta PTR_A+1
    bcc LIST_CHECK_END              ; the start line itself: INT_A is its number
    dey
    bcs LIST_READ_LINE_NUMBER       ; always taken: read the number of the next line
LIST_NEXT_LINE:
    jsr PRINT_NEWLINE
    jsr ADVANCE_PTR_A                       ; PTR_A to the line's carriage return, checking ESCAPE
LIST_READ_LINE_NUMBER:
    lda (PTR_A),y
    sta INT_A+1
    iny
    lda (PTR_A),y
    sta INT_A
    iny
    iny
    sty PTR_A_OFFSET                ; the line's text
LIST_CHECK_END:
    lda INT_A
    clc
    sbc LIST_END                    ; carry set when the line is past the end
    lda INT_A+1
    sbc LIST_END+1
    bcc LIST_LINE
    jmp IMMEDIATE_MODE              ; the end of the range, or of the program (&FF)
LIST_LINE:
    jsr PRINT_LINE_NUMBER_PADDED                       ; the line number, in five columns
    ldx #$FF
    stx LIST_QUOTE_FLAG             ; outside quotes; also one space for LISTO 1
    lda #LISTO_LINE_NUMBER_SPACE
    jsr PRINT_LISTO_SPACES
    ldx LIST_FOR_DEPTH
    lda #LISTO_INDENT_FOR
    jsr PRINT_LISTO_SPACES
    ldx LIST_REPEAT_DEPTH
    lda #LISTO_INDENT_REPEAT
    jsr PRINT_LISTO_SPACES
LIST_TEXT:
    ldy PTR_A_OFFSET
LIST_TEXT_LOOP:
    lda (PTR_A),y
    cmp #CARRIAGE_RETURN
    beq LIST_NEXT_LINE
    cmp #'"'
    bne LIST_NOT_QUOTE
    lda #$FF
    eor LIST_QUOTE_FLAG
    sta LIST_QUOTE_FLAG
    lda #'"'
LIST_PRINT_RAW:
    jsr PRINT_CHARACTER
    iny
    bne LIST_TEXT_LOOP              ; always taken
LIST_NOT_QUOTE:
    bit LIST_QUOTE_FLAG
    bpl LIST_PRINT_RAW              ; inside a string, a byte is printed as it is
    cmp #TOKEN_LINE_NUMBER
    bne LIST_NOT_LINE_NUMBER
    jsr UNPACK_LINE_NUMBER                       ; decode the line number after GOTO, GOSUB and the rest
    sty PTR_A_OFFSET
    lda #$00
    sta PRINT_FIELD_WIDTH
    jsr PRINT_LINE_NUMBER
    jmp LIST_TEXT
LIST_NOT_LINE_NUMBER:
    cmp #TOKEN_FOR
    bne LIST_NOT_FOR
    inc LIST_FOR_DEPTH
LIST_NOT_FOR:
    cmp #TOKEN_NEXT
    bne LIST_NOT_NEXT
    ldx LIST_FOR_DEPTH
    beq LIST_NOT_NEXT               ; never below zero
    dec LIST_FOR_DEPTH
LIST_NOT_NEXT:
    cmp #TOKEN_REPEAT
    bne LIST_NOT_REPEAT
    inc LIST_REPEAT_DEPTH
LIST_NOT_REPEAT:
    cmp #TOKEN_UNTIL
    bne LIST_PRINT_ITEM
    ldx LIST_REPEAT_DEPTH
    beq LIST_PRINT_ITEM             ; never below zero
    dec LIST_REPEAT_DEPTH
LIST_PRINT_ITEM:
    jsr PRINT_CHARACTER_OR_TOKEN
    iny
    bne LIST_TEXT_LOOP              ; always taken

;; Raises error 32, "No FOR": NEXT with no FOR loop open.
;; See: <NEXT_STATEMENT>
NO_FOR_ERROR:
    brk
    .byte ERROR_NO_FOR, "No ", TOKEN_FOR, 0
