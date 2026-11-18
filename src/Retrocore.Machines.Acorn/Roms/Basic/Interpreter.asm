;; The tokeniser, reading the text, the start-up and immediate mode, and the statement loop ($8821-$8BE3).
;;
;; - A few helpers the assembler shares: <EVALUATE_INTEGER_A>, the steps that move <OPCODE> to another addressing
;;   mode's column, and EQUB, EQUW, EQUD and EQUS (<ASSEMBLE_EQU>).
;; - The tokeniser, <TOKENISE_LINE>, which replaces each keyword in a line with its token, and each line number
;;   that follows GOTO and the other keywords that take one with <TOKEN_LINE_NUMBER> and three packed bytes
;;   (<ENCODE_LINE_NUMBER>).
;; - <GET_CHARACTER_A> and <GET_CHARACTER_B>, which read the next character that is not a space through PTRA and
;;   PTRB.
;; - OLD, END, STOP and NEW, the cold and warm starts, and immediate mode, which reads a line, tokenises it, and either
;;   puts it into the program or runs it.
;; - The statement loop: <CONTINUE_EXECUTION> moves from statement to statement and line to line, <EXECUTE_STATEMENT>
;;   runs one through the token tables, and <IMPLIED_LET> handles a statement that starts with a variable, a `*`
;;   command, `=` returning from an FN, or `[` starting the assembler.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

PROMPT = '>'                        ;; the prompt immediate mode prints before reading a line

; Error numbers.
ERROR_MISSING_COMMA = $05           ;; error 5, "Missing ,"
ERROR_STOP = $00                    ;; error 0, "STOP"
ERROR_NO_FN = $07                   ;; error 7, "No FN"

; The tokeniser's pointers, in WORK, and its state, in FPB's bytes, which it does not otherwise need.
TOKENISE_TEXT = WORK                ;; the tokeniser's pointer to the character it is looking at; Y stays zero
KEYWORD_POINTER = WORK + 2          ;; the tokeniser's pointer into the keyword table, or into the line it moves

;; The tokeniser's "middle of statement" flag: zero at the start of a statement, &FF in the middle of one.
;;
;; At the start of a statement a `*` ends tokenising, leaving the rest of the line for OSCLI, and a pseudo-variable
;; such as PTR or TIME is given its statement token.
TOKENISE_MIDDLE = FP_B_SIGN

TOKENISE_LINE_NUMBERS = FP_B_OVERFLOW   ;; the tokeniser's line number flag: non-zero while numbers are line numbers
KEYWORD_FLAGS = FP_B_EXPONENT       ;; the flag byte of the keyword the tokeniser has just found
LINE_NUMBER_VALUE = FP_B_EXPONENT   ;; the line number being tokenised, two bytes, low byte first

; ---------------------------------------------------------------------------------------------------------------------
; The assembler's helpers
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates an expression at PTRA as an integer, and moves PTRA past it.
;;
;; A real result is converted to an integer; a string is a "Type mismatch".
;; Out: INT_A = the integer, PTR_A_OFFSET = just past the expression
;; Uses: A, X, Y, PTR_B, PTR_B_OFFSET
;; Entry: SET_PTR_A_OFFSET_FROM_B = only moves PTRA's offset to PTRB's
EVALUATE_INTEGER_A:
    jsr EVALUATE_EXPRESSION_A
    jsr CONVERT_A_TO_INTEGER
SET_PTR_A_OFFSET_FROM_B:
    ldy PTR_B_OFFSET
    sty PTR_A_OFFSET
    rts

;; Adds 12 to <OPCODE>, moving it three columns along the 6502's opcode table to another addressing mode.
;;
;; It calls <ADD_8_TO_OPCODE>, which calls <ADD_4_TO_OPCODE> and then falls into it, so that each step adds 4.
;; Uses: A
;; Entry:
;;   ADD_8_TO_OPCODE = adds 8
;;   ADD_4_TO_OPCODE = adds 4
ADD_12_TO_OPCODE:
    jsr ADD_8_TO_OPCODE
ADD_8_TO_OPCODE:
    jsr ADD_4_TO_OPCODE
ADD_4_TO_OPCODE:
    lda OPCODE
    clc
    adc #$04
    sta OPCODE
    rts

;; Assembles EQUB, EQUW, EQUD or EQUS: puts a byte, a word, a double word or a string into the code.
;;
;; The assembler has read "EQU"; this reads the letter after it. A number is evaluated as an integer, moved down a byte
;; so that its bytes start at <OPCODE>, and stored low byte first as an instruction's bytes are. A string is stored
;; from <STRING_BUFFER>. It raises "Syntax error" for any other letter, and "Type mismatch" when EQUS's expression is
;; not a string.
;; In: PTR_A, PTR_A_OFFSET = the letter after EQU
;; See: <ASSEMBLER_STORE>
ASSEMBLE_EQU:
    ldx #$01                        ; EQUB: one byte
    ldy PTR_A_OFFSET
    inc PTR_A_OFFSET
    lda (PTR_A),y
    cmp #'B'
    beq ASSEMBLE_EQU_NUMBER
    inx                             ; EQUW: two bytes
    cmp #'W'
    beq ASSEMBLE_EQU_NUMBER
    ldx #$04                        ; EQUD: four bytes
    cmp #'D'
    beq ASSEMBLE_EQU_NUMBER
    cmp #'S'
    beq ASSEMBLE_EQUS
    jmp SYNTAX_ERROR
ASSEMBLE_EQU_NUMBER:
    txa
    pha
    jsr EVALUATE_INTEGER_A
    ldx #OPCODE                     ; copy IntA a byte down, to OPCODE..OPCODE+3
    jsr STORE_INT_A
    pla
    tay                             ; Y = the number of bytes to store
ASSEMBLE_EQU_STORE:
    jmp ASSEMBLER_STORE
ASSEMBLE_EQU_MISMATCH:
    jmp TYPE_MISMATCH_ERROR
ASSEMBLE_EQUS:
    lda OPT                         ; keep OPT across evaluating the string
    pha
    jsr EVALUATE_EXPRESSION_A
    bne ASSEMBLE_EQU_MISMATCH       ; not a string
    pla
    sta OPT
    jsr SET_PTR_A_OFFSET_FROM_B
    ldy #$FF                        ; Y negative: store the string in StrA
    bne ASSEMBLE_EQU_STORE          ; always taken

; ---------------------------------------------------------------------------------------------------------------------
; The tokeniser
; ---------------------------------------------------------------------------------------------------------------------

;; Replaces the start of the text at <TOKENISE_TEXT> with a token, moving the rest of the line down to close the gap.
;;
;; The text being replaced, a keyword or a line number, is Y+1 characters long; the token takes its first byte.
;; In: A = the token, Y = the length of the text it replaces, less one, TOKENISE_TEXT = the text
;; Out: Y = the offset of the carriage return that now ends the line, carry = set
;; Uses: A, KEYWORD_POINTER
REPLACE_WITH_TOKEN:
    pha
    clc
    tya
    adc TOKENISE_TEXT
    sta KEYWORD_POINTER
    ldy #$00
    tya
    adc TOKENISE_TEXT+1
    sta KEYWORD_POINTER+1
    pla
    sta (TOKENISE_TEXT),y
REPLACE_WITH_TOKEN_LOOP:
    iny
    lda (KEYWORD_POINTER),y
    sta (TOKENISE_TEXT),y
    cmp #CARRIAGE_RETURN
    bne REPLACE_WITH_TOKEN_LOOP
    rts

;; Tokenises a line number: reads its decimal digits and replaces them with <TOKEN_LINE_NUMBER> and three bytes.
;;
;; The digits are read up to the first character that is not one. A number of 32768 or more is not a line number, and
;; is left as it is. Otherwise the digits are replaced with the token, the rest of the line is moved up three bytes to
;; make room, and the routine falls into <ENCODE_LINE_NUMBER> to write the number after the token.
;; In: A = the first digit, Y = 0, TOKENISE_TEXT = the first digit's address
;; Out:
;;   carry = set when the number was too big and has been left as digits, clear when it was tokenised
;;   TOKENISE_TEXT = the last of the three bytes, when tokenised
;;   Y = 0
;; Uses: A, X, KEYWORD_POINTER, LINE_NUMBER_VALUE
TOKENISE_LINE_NUMBER:
    and #$0F
    sta LINE_NUMBER_VALUE
    sty LINE_NUMBER_VALUE+1         ; Y is zero
TOKENISE_LINE_NUMBER_DIGIT:
    iny
    lda (TOKENISE_TEXT),y
    cmp #'9'+1
    bcs TOKENISE_LINE_NUMBER_INSERT
    cmp #'0'
    bcc TOKENISE_LINE_NUMBER_INSERT
    and #$0F
    pha
    ldx LINE_NUMBER_VALUE+1         ; multiply by ten: four times, plus itself, times two
    lda LINE_NUMBER_VALUE
    asl a
    rol LINE_NUMBER_VALUE+1
    bmi TOKENISE_LINE_NUMBER_TOO_BIG
    asl a
    rol LINE_NUMBER_VALUE+1
    bmi TOKENISE_LINE_NUMBER_TOO_BIG
    adc LINE_NUMBER_VALUE
    sta LINE_NUMBER_VALUE
    txa
    adc LINE_NUMBER_VALUE+1
    asl LINE_NUMBER_VALUE
    rol a
    bmi TOKENISE_LINE_NUMBER_TOO_BIG
    bcs TOKENISE_LINE_NUMBER_TOO_BIG
    sta LINE_NUMBER_VALUE+1
    pla                             ; add the digit
    adc LINE_NUMBER_VALUE
    sta LINE_NUMBER_VALUE
    bcc TOKENISE_LINE_NUMBER_DIGIT
    inc LINE_NUMBER_VALUE+1
    bpl TOKENISE_LINE_NUMBER_DIGIT
    pha                             ; for the PLA below to take off
TOKENISE_LINE_NUMBER_TOO_BIG:
    pla
    ldy #$00
    sec
    rts
TOKENISE_LINE_NUMBER_INSERT:
    dey
    lda #TOKEN_LINE_NUMBER
    jsr REPLACE_WITH_TOKEN
    lda TOKENISE_TEXT               ; carry is set: this adds 3
    adc #$02
    sta KEYWORD_POINTER
    lda TOKENISE_TEXT+1
    adc #$00
    sta KEYWORD_POINTER+1
TOKENISE_LINE_NUMBER_OPEN_GAP:
    lda (TOKENISE_TEXT),y
    sta (KEYWORD_POINTER),y
    dey
    bne TOKENISE_LINE_NUMBER_OPEN_GAP
    ldy #$03
;; Writes a line number as the three bytes that follow <TOKEN_LINE_NUMBER>, and moves the text pointer to the last.
;;
;; Each byte keeps six bits of the number, with bits 7 and 6 set to %01 so that it lies in &40-&7F, where it can be
;; neither a token nor a control character such as the carriage return that ends a line:
;;
;; - the first byte holds the top two bits of each byte of the number: bit 5 is bit 7 of the low byte, bit 4 bit 6
;;   inverted, bit 3 bit 7 of the high byte and bit 2 bit 6 inverted;
;; - the second byte holds the low six bits of the low byte;
;; - the third byte holds the low six bits of the high byte.
;;
;; The two inverted bits are those that the decoder, <GET_LINE_NUMBER>, shifts into bit 6 before it exclusive-ORs them
;; with the second and third bytes, whose bit 6 is always set. Line 10 becomes &8D &54 &4A &40. Bit 7 of the number
;; must be clear: line numbers are less than 32768. RENUMBER uses this to rewrite the numbers in place.
;; In: LINE_NUMBER_VALUE = the line number, TOKENISE_TEXT,Y = the third byte (the token is at Y-3)
;; Out: TOKENISE_TEXT = advanced by three, Y = 0, carry = clear
;; Uses: A
ENCODE_LINE_NUMBER:
    lda LINE_NUMBER_VALUE+1
    ora #%01000000
    sta (TOKENISE_TEXT),y
    dey
    lda LINE_NUMBER_VALUE
    and #%00111111
    ora #%01000000
    sta (TOKENISE_TEXT),y
    dey
    lda LINE_NUMBER_VALUE
    and #%11000000
    sta LINE_NUMBER_VALUE
    lda LINE_NUMBER_VALUE+1
    and #%11000000
    lsr a
    lsr a
    ora LINE_NUMBER_VALUE
    lsr a
    lsr a
    eor #%01010100                  ; set bit 6 and invert the two bit 6s
    sta (TOKENISE_TEXT),y
    jsr ADVANCE_WORK
    jsr ADVANCE_WORK
    jsr ADVANCE_WORK
    ldy #$00
;; Returns with carry clear: shared by the character tests below.
;; Out: carry = clear
RETURN_CARRY_CLEAR:
    clc
    rts

;; Tests whether a character can be part of a variable's name: a letter, a digit, `_` or the pound sign.
;;
;; The characters &5F-&7A count, so lower case letters, `_` and the pound sign (&60) do.
;; In: A = the character
;; Out: carry = set when it can be part of a name
;; Keeps: A, X, Y
;; Entry: IS_DIGIT = tests for a digit only
IS_NAME_CHARACTER:
    cmp #'z'+1
    bcs RETURN_CARRY_CLEAR
    cmp #'_'
    bcs IS_NAME_CHARACTER_YES
    cmp #'Z'+1
    bcs RETURN_CARRY_CLEAR
    cmp #'A'
    bcs IS_NAME_CHARACTER_YES
IS_DIGIT:
    cmp #'9'+1
    bcs RETURN_CARRY_CLEAR
    cmp #'0'
IS_NAME_CHARACTER_YES:
    rts

;; Tests whether a character can be part of a number: a digit or a decimal point.
;; In: A = the character
;; Out: carry = set for a digit or a point
;; Keeps: A, X, Y
IS_DIGIT_OR_POINT:
    cmp #'.'
    bne IS_DIGIT
    rts

;; Reads the byte at <WORK> and moves WORK on by one.
;;
;; The tokeniser steps through a line by moving WORK, with Y kept at zero; SET_ERL and PRINT_INLINE step through text
;; the same way.
;; In: WORK = the byte, Y = 0
;; Out: A = the byte
;; Keeps: X, Y
;; Entry: ADVANCE_WORK = only moves WORK on
READ_AND_ADVANCE_WORK:
    lda (WORK),y
ADVANCE_WORK:
    inc WORK
    bne ADVANCE_WORK_DONE
    inc WORK+1
ADVANCE_WORK_DONE:
    rts

;; Moves <WORK> on by one and reads the byte it then points to.
;; In: Y = 0
;; Out: A = the byte, negative = its bit 7, zero = set for a zero byte
;; Keeps: X, Y
ADVANCE_WORK_AND_READ:
    jsr ADVANCE_WORK
    lda (WORK),y
    rts

;; Tokenises a line from the start of a statement, with line numbers left as they are.
;; Inherit: <TOKENISE_LINE>
;; Entry: TOKENISE_WITHOUT_LINE_NUMBERS = keeps TOKENISE_MIDDLE as it is; Y must be zero
TOKENISE_STATEMENT:
    ldy #$00
    sty TOKENISE_MIDDLE
TOKENISE_WITHOUT_LINE_NUMBERS:
    sty TOKENISE_LINE_NUMBERS
;; Tokenises a line in place: replaces each keyword with its token, and each line number after a keyword that takes
;; one with <TOKEN_LINE_NUMBER> and three bytes.
;;
;; The line is read with <TOKENISE_TEXT> moving along it and Y kept at zero, up to its carriage return. Two flags
;; carry the state: <TOKENISE_MIDDLE>, clear at the start of a statement, and <TOKENISE_LINE_NUMBERS>, set while a
;; number is a line number.
;;
;; - Spaces and commas are passed over, leaving the state as it is, so "GOTO 10, 20" (ON ... GOTO) tokenises both.
;; - A hexadecimal number after `&` and a string in quotes are passed over whole.
;; - A colon starts a new statement and clears both flags.
;; - At the start of a statement, a `*` ends tokenising, leaving the command for OSCLI.
;; - A number is tokenised by <TOKENISE_LINE_NUMBER> while TOKENISE_LINE_NUMBERS is set, leaving the state as it is.
;;   Any other number, or one too big to be a line number, is passed over, and puts the tokeniser in the middle of a
;;   statement with line numbers off.
;; - A word starting with a capital from A to W is looked up in the keyword table, which is in alphabetical order of
;;   first letters, with each keyword followed by its token and a flag byte. An abbreviation, a keyword's first letters
;;   and a full stop, matches the first entry in the table it fits. A word that is not a keyword, or that starts with
;;   X, Y, Z or a small letter, is a name, and is passed over whole so that no keyword is found inside it.
;; - Any other character puts the tokeniser in the middle of a statement, with line numbers off.
;;
;; When a keyword is found its flag byte steers what happens, the bits taken in this order:
;;
;; - <KEYWORD_CONDITIONAL>, bit 0: if a letter, digit, `_` or £ follows, the word is a name, not this keyword, and
;;   is passed over whole (so TIMER is a variable);
;; - <KEYWORD_PSEUDO_VARIABLE>, bit 6: at the start of a statement, the token is &40 higher, giving PTR, PAGE, TIME,
;;   LOMEM and HIMEM their statement tokens;
;; - <KEYWORD_MID_STATEMENT>, bit 1: the middle of a statement follows, with line numbers off;
;; - <KEYWORD_START_STATEMENT>, bit 2: the start of a statement follows (after THEN and ELSE, say), with line numbers
;;   off;
;; - <KEYWORD_SKIP_NAME>, bit 3: a name follows, which is passed over (FN and PROC);
;; - <KEYWORD_LINE_NUMBERS>, bit 4: line numbers follow (GOTO, GOSUB, RESTORE, THEN, AUTO, LIST and others); this
;;   comes after bits 1 and 2, so THEN can set both bits 2 and 4;
;; - <KEYWORD_REST_OF_LINE>, bit 5: tokenising stops, leaving the rest of the line as it is (REM and DATA).
;; In: TOKENISE_TEXT = the line, Y = 0, TOKENISE_MIDDLE = the state to start in, TOKENISE_LINE_NUMBERS = likewise
;; Out: TOKENISE_TEXT = where tokenising stopped, Y = 0
;; Uses: A, X, KEYWORD_POINTER, KEYWORD_FLAGS, LINE_NUMBER_VALUE
;; See: <KEYWORD_TABLE>, <IMMEDIATE_MODE>
TOKENISE_LINE:
    lda (TOKENISE_TEXT),y
    cmp #CARRIAGE_RETURN
    beq ADVANCE_WORK_DONE           ; the end of the line: return
    cmp #' '
    bne TOKENISE_NOT_SPACE
TOKENISE_NEXT:
    jsr ADVANCE_WORK
    bne TOKENISE_LINE               ; always taken: ADVANCE_WORK leaves zero clear
TOKENISE_NOT_SPACE:
    cmp #'&'
    bne TOKENISE_NOT_HEX
TOKENISE_HEX_LOOP:
    jsr ADVANCE_WORK_AND_READ
    jsr IS_DIGIT
    bcs TOKENISE_HEX_LOOP
    cmp #'A'
    bcc TOKENISE_LINE
    cmp #'F'+1
    bcc TOKENISE_HEX_LOOP
    bcs TOKENISE_LINE               ; always taken
TOKENISE_NOT_HEX:
    cmp #'"'
    bne TOKENISE_NOT_STRING
TOKENISE_STRING_LOOP:
    jsr ADVANCE_WORK_AND_READ
    cmp #'"'
    beq TOKENISE_NEXT
    cmp #CARRIAGE_RETURN
    bne TOKENISE_STRING_LOOP
    rts
TOKENISE_NOT_STRING:
    cmp #':'
    bne TOKENISE_NOT_COLON
    sty TOKENISE_MIDDLE
    sty TOKENISE_LINE_NUMBERS
    beq TOKENISE_NEXT               ; always taken
TOKENISE_NOT_COLON:
    cmp #','
    beq TOKENISE_NEXT
    cmp #'*'
    bne TOKENISE_NOT_STAR
    lda TOKENISE_MIDDLE
    bne TOKENISE_SYMBOL
    rts                             ; a * command: leave the rest of the line for OSCLI
TOKENISE_NOT_STAR:
    cmp #'.'
    beq TOKENISE_SKIP_NUMBER
    jsr IS_DIGIT
    bcc TOKENISE_NOT_NUMBER
    ldx TOKENISE_LINE_NUMBERS
    beq TOKENISE_SKIP_NUMBER
    jsr TOKENISE_LINE_NUMBER
    bcc TOKENISE_NEXT_FAR
TOKENISE_SKIP_NUMBER:
    lda (TOKENISE_TEXT),y
    jsr IS_DIGIT_OR_POINT
    bcc TOKENISE_OPERAND_DONE
    jsr ADVANCE_WORK
    jmp TOKENISE_SKIP_NUMBER
TOKENISE_OPERAND_DONE:
    ldx #$FF                        ; the middle of a statement, with line numbers off
    stx TOKENISE_MIDDLE
    sty TOKENISE_LINE_NUMBERS
    jmp TOKENISE_LINE
TOKENISE_LATE_LETTER:
    jsr IS_NAME_CHARACTER
    bcc TOKENISE_SYMBOL
TOKENISE_SKIP_NAME:
    ldy #$00
TOKENISE_SKIP_NAME_LOOP:
    lda (TOKENISE_TEXT),y
    jsr IS_NAME_CHARACTER
    bcc TOKENISE_OPERAND_DONE
    jsr ADVANCE_WORK
    jmp TOKENISE_SKIP_NAME_LOOP
TOKENISE_NOT_NUMBER:
    cmp #'A'
    bcs TOKENISE_WORD
TOKENISE_SYMBOL:
    ldx #$FF                        ; the middle of a statement, with line numbers off
    stx TOKENISE_MIDDLE
    sty TOKENISE_LINE_NUMBERS
TOKENISE_NEXT_FAR:
    jmp TOKENISE_NEXT
TOKENISE_WORD:
    cmp #'X'                        ; no keyword starts with X, Y, Z or a small letter
    bcs TOKENISE_LATE_LETTER
    ldx #<KEYWORD_TABLE
    stx KEYWORD_POINTER
    ldx #>KEYWORD_TABLE
    stx KEYWORD_POINTER+1
TOKENISE_KEYWORD_ENTRY:
    cmp (KEYWORD_POINTER),y
    bcc TOKENISE_SKIP_NAME_LOOP     ; past the keywords with this first letter: a name
    bne TOKENISE_KEYWORD_SKIP
TOKENISE_KEYWORD_MATCH:
    iny
    lda (KEYWORD_POINTER),y
    bmi TOKENISE_KEYWORD_FOUND      ; the token: every letter matched
    cmp (TOKENISE_TEXT),y
    beq TOKENISE_KEYWORD_MATCH
    lda (TOKENISE_TEXT),y
    cmp #'.'
    beq TOKENISE_KEYWORD_ABBREVIATED
TOKENISE_KEYWORD_SKIP:
    iny
    lda (KEYWORD_POINTER),y
    bpl TOKENISE_KEYWORD_SKIP
    cmp #TOKEN_WIDTH                ; the last keyword searched; the entries after it are for LIST
    bne TOKENISE_KEYWORD_NEXT
    bcs TOKENISE_SKIP_NAME          ; always taken: not a keyword
TOKENISE_KEYWORD_ABBREVIATED:
    iny
TOKENISE_KEYWORD_FIND_TOKEN:
    lda (KEYWORD_POINTER),y
    bmi TOKENISE_KEYWORD_FOUND
    inc KEYWORD_POINTER
    bne TOKENISE_KEYWORD_FIND_TOKEN
    inc KEYWORD_POINTER+1
    bne TOKENISE_KEYWORD_FIND_TOKEN ; always taken
TOKENISE_KEYWORD_NEXT:
    sec                             ; move past the token and the flag byte
    iny
    tya
    adc KEYWORD_POINTER
    sta KEYWORD_POINTER
    bcc TOKENISE_KEYWORD_RETRY
    inc KEYWORD_POINTER+1
TOKENISE_KEYWORD_RETRY:
    ldy #$00
    lda (TOKENISE_TEXT),y
    jmp TOKENISE_KEYWORD_ENTRY
TOKENISE_KEYWORD_FOUND:
    tax                             ; X = the token
    iny
    lda (KEYWORD_POINTER),y
    sta KEYWORD_FLAGS
    dey                             ; Y = the length of the keyword in the text
    lsr a                           ; bit 0: not a keyword if a name continues
    bcc TOKENISE_KEYWORD_ACCEPT
    lda (TOKENISE_TEXT),y
    jsr IS_NAME_CHARACTER
    bcs TOKENISE_SKIP_NAME
TOKENISE_KEYWORD_ACCEPT:
    txa
    bit KEYWORD_FLAGS               ; bit 6: a pseudo-variable
    bvc TOKENISE_KEYWORD_INSERT
    ldx TOKENISE_MIDDLE
    bne TOKENISE_KEYWORD_INSERT
    clc                             ; at the start of a statement: the statement token
    adc #$40
TOKENISE_KEYWORD_INSERT:
    dey
    jsr REPLACE_WITH_TOKEN
    ldy #$00
    ldx #$FF
    lda KEYWORD_FLAGS
    lsr a
    lsr a                           ; bit 1: the middle of a statement follows
    bcc TOKENISE_FLAG_START
    stx TOKENISE_MIDDLE
    sty TOKENISE_LINE_NUMBERS
TOKENISE_FLAG_START:
    lsr a                           ; bit 2: the start of a statement follows
    bcc TOKENISE_FLAG_FN_PROC
    sty TOKENISE_MIDDLE
    sty TOKENISE_LINE_NUMBERS
TOKENISE_FLAG_FN_PROC:
    lsr a                           ; bit 3: pass over the name that follows
    bcc TOKENISE_FLAG_LINE_NUMBERS
    pha
    iny
TOKENISE_FN_PROC_NAME:
    lda (TOKENISE_TEXT),y
    jsr IS_NAME_CHARACTER
    bcc TOKENISE_FN_PROC_NAME_END
    jsr ADVANCE_WORK
    jmp TOKENISE_FN_PROC_NAME
TOKENISE_FN_PROC_NAME_END:
    dey
    pla
TOKENISE_FLAG_LINE_NUMBERS:
    lsr a                           ; bit 4: line numbers follow
    bcc TOKENISE_FLAG_REM
    stx TOKENISE_LINE_NUMBERS
TOKENISE_FLAG_REM:
    lsr a                           ; bit 5: leave the rest of the line
    bcs GET_CHARACTER_B_DONE        ; return
    jmp TOKENISE_NEXT

; ---------------------------------------------------------------------------------------------------------------------
; Reading the text
; ---------------------------------------------------------------------------------------------------------------------

;; Reads the next character that is not a space from the text at PTRB, moving PTRB's offset past it.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: A = the character, Y = its offset, PTR_B_OFFSET = just past it
;; Keeps: X
;; See: <GET_CHARACTER_A>
GET_CHARACTER_B:
    ldy PTR_B_OFFSET
    inc PTR_B_OFFSET
    lda (PTR_B),y
    cmp #' '
    beq GET_CHARACTER_B
GET_CHARACTER_B_DONE:
    rts

;; Reads the next character that is not a space from the text at PTRA, moving PTRA's offset past it.
;; In: PTR_A, PTR_A_OFFSET = the text
;; Out: A = the character, Y = its offset, PTR_A_OFFSET = just past it
;; Keeps: X
;; See: <GET_CHARACTER_B>
GET_CHARACTER_A:
    ldy PTR_A_OFFSET
    inc PTR_A_OFFSET
    lda (PTR_A),y
    cmp #' '
    beq GET_CHARACTER_A
    rts

;; Raises error 5, "Missing ,".
MISSING_COMMA_ERROR:
    brk
    .byte ERROR_MISSING_COMMA
    .byte "Missing ,",0

;; Reads a comma at PTRB, raising "Missing ," if the next character that is not a space is anything else.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: A = the comma, PTR_B_OFFSET = just past it
;; Keeps: X
CHECK_COMMA_B:
    jsr GET_CHARACTER_B
    cmp #','
    bne MISSING_COMMA_ERROR
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The start-up, immediate mode and the statement loop
; ---------------------------------------------------------------------------------------------------------------------

;; OLD: brings back the program NEW removed, if nothing has overwritten it since.
;;
;; NEW leaves the program in place, but marks it empty with &FF in the high byte of the first line's number. OLD puts
;; back a zero there, which suits any first line numbered below 256, then finds the end of the program again, which
;; reports "Bad program" if it is not a program, and clears the variables.
;; See: <NEW_COMMAND>
OLD_COMMAND:
    jsr CHECK_END_OF_STATEMENT      ; leaves Y = 1
    lda PAGE_HIGH
    sta WORK+1
    lda #$00
    sta WORK
    sta (WORK),y                    ; the high byte of the first line's number
    jsr FIND_PROGRAM_END
    bne WARM_START                  ; always taken

;; END: ends the program and returns to immediate mode.
;;
;; It first finds the end of the program again, setting TOP, which also checks the program and reports "Bad program"
;; if it is damaged.
END_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    jsr FIND_PROGRAM_END
    bne IMMEDIATE_MODE              ; always taken

;; STOP: stops the program with error 0, "STOP", which reports the line it stopped in.
STOP_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    brk
    .byte ERROR_STOP
    .byte "STOP",0

;; NEW: removes the program and clears the variables.
;;
;; The program is not wiped: only its first line is marked as the end, which OLD can undo.
;; See: <COLD_START>, <OLD_COMMAND>
NEW_COMMAND:
    jsr CHECK_END_OF_STATEMENT
;; Starts BASIC with no program: puts an empty program at PAGE, turns TRACE off, clears the variables and enters
;; immediate mode.
;;
;; An empty program is a carriage return and the end marker, &FF, where a line's number would start; TOP is the byte
;; after them.
;;
;; Immediate mode resets ON ERROR, reads a line into <LINE_BUFFER> after the `>` prompt, and falls into
;; <EXECUTE_LINE> to put it in the program or run it.
;; Entry:
;;   WARM_START = clears the variables and enters immediate mode, keeping the program
;;   IMMEDIATE_MODE = enters immediate mode, keeping the program and the variables
COLD_START:
    lda #CARRIAGE_RETURN
    ldy PAGE_HIGH
    sty TOP+1
    ldy #$00
    sty TOP
    sty TRACE_FLAG
    sta (TOP),y
    lda #$FF                        ; the end of the program
    iny
    sta (TOP),y
    iny
    sty TOP
WARM_START:
    jsr CLEAR_VARIABLES
IMMEDIATE_MODE:
    ldy #>LINE_BUFFER
    sty PTR_A+1
    ldy #<LINE_BUFFER
    sty PTR_A
    lda #<DEFAULT_ERROR_HANDLER
    sta ON_ERROR
    lda #>DEFAULT_ERROR_HANDLER
    sta ON_ERROR+1
    lda #PROMPT
    jsr READ_LINE_WITH_PROMPT
;; Runs the text at PTRA as immediate mode does: tokenises it, and either puts it into the program, when it starts with
;; a line number, or runs it.
;;
;; It first resets what a new run needs: ON ERROR's default, the assembler's options, the 6502 stack and BASIC's
;; stacks. Putting a numbered line into the program clears the variables. RUN enters here with PTRA at PAGE, whose
;; carriage return starts the program: the statement loop then finds the end of a line and moves on into the first
;; line.
;; In: PTR_A = the text, ending with a carriage return
EXECUTE_LINE:
    lda #<DEFAULT_ERROR_HANDLER
    sta ON_ERROR
    lda #>DEFAULT_ERROR_HANDLER
    sta ON_ERROR+1
    ldx #$FF                        ; OPT, the line number flag and the stack pointer all start at &FF
    stx OPT
    stx TOKENISE_LINE_NUMBERS       ; a number at the start of the line is a line number
    txs
    jsr RESET_STACKS                       ; returns A = 0
    tay
    lda PTR_A
    sta TOKENISE_TEXT
    lda PTR_A+1
    sta TOKENISE_TEXT+1
    sty TOKENISE_MIDDLE
    sty PTR_A_OFFSET
    jsr TOKENISE_LINE
    jsr GET_LINE_NUMBER
    bcc EXECUTE_LINE_RUN
    jsr INSERT_LINE
    jmp WARM_START
EXECUTE_LINE_RUN:
    jsr GET_CHARACTER_A
    cmp #TOKEN_AUTO                 ; the commands, and the statements after them
    bcs DISPATCH_TOKEN
    bcc IMPLIED_LET                 ; always taken

;; Returns to immediate mode at the end of a line typed in it.
IMMEDIATE_MODE_RELAY:
    jmp IMMEDIATE_MODE

;; `[`: starts the assembler.
ENTER_ASSEMBLER:
    jmp ASSEMBLER_START

;; `=`: returns from an FN with the value of the expression that follows.
;;
;; FN_FUNCTION moves the 6502 stack onto BASIC's stack and pushes the FN token first, so &01FF holds it while an FN
;; runs. Without it there is no FN to return from: error 7, "No FN". The result goes back with the end of the
;; statement checked, by returning from the statement loop the FN started.
RETURN_FROM_FN:
    tsx
    cpx #FN_PROC_STACK_LIMIT
    bcs NO_FN_ERROR
    lda STACK+$FF
    cmp #TOKEN_FN
    bne NO_FN_ERROR
    jsr EVALUATE_EXPRESSION_A
    jmp CHECK_END_OF_EXPRESSION
;; Raises error 7, "No FN".
NO_FN_ERROR:
    brk
    .byte ERROR_NO_FN
    .byte "No ",TOKEN_FN,0

;; Runs a statement that does not start with a keyword or a variable's name: `=`, `*`, `[`, or an empty statement.
;;
;; Anything else raises "Syntax error" from <CHECK_END_OF_STATEMENT>.
;; In: PTR_A_OFFSET = just past the statement's first character
STATEMENT_NOT_VARIABLE:
    ldy PTR_A_OFFSET
    dey
    lda (PTR_A),y
    cmp #'='
    beq RETURN_FROM_FN
    cmp #'*'
    beq STAR_COMMAND
    cmp #'['
    beq ENTER_ASSEMBLER
    bne FINISH_STATEMENT_BACK_ONE   ; always taken

;; `*`: passes the rest of the line to OSCLI, then goes on with the next line.
;; In: Y = the offset of the `*`
STAR_COMMAND:
    jsr ADVANCE_PTR_A                       ; PTRA = the `*`
    ldx PTR_A
    ldy PTR_A+1
    jsr OSCLI
;; Skips the rest of the line, then goes on with the next line: for REM, DATA and DEF, and for ELSE reached while
;; running a line.
;;
;; At the end of a line typed in immediate mode it returns to immediate mode; at the end of the program it ends.
;; Entry:
;;   END_OF_STATEMENT_LINE = goes on from the end of a statement, A = the carriage return or ELSE that ended it
SKIP_LINE:
    lda #CARRIAGE_RETURN
    ldy PTR_A_OFFSET
    dey
SKIP_LINE_LOOP:
    iny
    cmp (PTR_A),y
    bne SKIP_LINE_LOOP
END_OF_STATEMENT_LINE:
    cmp #TOKEN_ELSE                 ; ELSE ends the part of the line IF ran
    beq SKIP_LINE
    lda PTR_A+1
    cmp #>LINE_BUFFER
    beq IMMEDIATE_MODE_RELAY
    jsr MOVE_TO_NEXT_LINE                       ; the next line, tracing it
    bne EXECUTE_STATEMENT           ; always taken

;; Checks for the end of a statement, after stepping back over the character just read, then goes on with the next
;; statement.
;;
;; A statement that has read one character past its end comes here; one that has not comes to FINISH_STATEMENT.
;; Anything but a colon, a carriage return or ELSE at the end of the statement raises "Syntax error".
;; Entry: FINISH_STATEMENT = checks for the end of a statement at PTR_A_OFFSET
FINISH_STATEMENT_BACK_ONE:
    dec PTR_A_OFFSET
FINISH_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
;; Goes on with the next statement: the statement loop.
;;
;; After CHECK_END_OF_STATEMENT, PTRA points to what ended the statement. A colon starts the next statement on the same
;; line; ELSE skips the rest of the line; a carriage return moves on to the next line, or back to immediate mode.
;; Statements usually end by jumping here. Escape is checked by CHECK_END_OF_STATEMENT, once a statement.
;; In: PTR_A = the colon, carriage return or ELSE that ended the statement
;; Entry:
;;   EXECUTE_STATEMENT = runs the statement at PTR_A, PTR_A_OFFSET
;;   DISPATCH_TOKEN = runs the routine for the token in A, for a statement or a function
CONTINUE_EXECUTION:
    ldy #$00
    lda (PTR_A),y
    cmp #':'
    bne END_OF_STATEMENT_LINE
EXECUTE_STATEMENT:
    ldy PTR_A_OFFSET
    inc PTR_A_OFFSET
    lda (PTR_A),y
    cmp #' '
    beq EXECUTE_STATEMENT
    cmp #TOKEN_PTR_STATEMENT        ; the statements: the commands do not run in a program
    bcc IMPLIED_LET
DISPATCH_TOKEN:
    tax
    lda ROUTINE_LOW_BY_TOKEN,x      ; the token's routine
    sta WORK
    lda ROUTINE_HIGH_BY_TOKEN,x
    sta WORK+1
    jmp (WORK)
;; Runs a statement that does not start with a statement's token: an assignment without LET, or another statement
;; <STATEMENT_NOT_VARIABLE> handles.
;;
;; A variable that does not exist yet is made, with its value zero, and the statement is read again as a LET, which
;; then finds it. LET_STATEMENT follows: this falls into it.
;; In: Y = the offset of the statement's first character, PTR_A_OFFSET = just past it
IMPLIED_LET:
    ldx PTR_A
    stx PTR_B
    ldx PTR_A+1
    stx PTR_B+1
    sty PTR_B_OFFSET
    jsr FIND_VARIABLE
    bne LET_ASSIGN                  ; it exists
    bcs STATEMENT_NOT_VARIABLE      ; not a variable's name
    stx PTR_B_OFFSET
    jsr EXPECT_EQUALS                       ; check for the =
    jsr LINK_VARIABLE
    ldx #$05                        ; zero the name's end and the value: 5 bytes, or 6 for a real
    cpx INT_A+2
    bne IMPLIED_LET_CLEAR
    inx
IMPLIED_LET_CLEAR:
    jsr ALLOCATE_VARIABLE
    dec PTR_A_OFFSET
