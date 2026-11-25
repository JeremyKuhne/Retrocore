;; PRINT'S OUTPUT, LPRINT, LIST, FOR, GOSUB AND GOTO ($B48F-$B6F8)
;;
;; - <PRINT_CHARACTER>, which writes PRINT's characters and counts them for the commas' tab stops, and
;;   <STATEMENT_LPRINT>, which PRINTs to the printer.
;; - <STATEMENT_LIST> and the lister it shares with the line editor and the error report: <LIST_FIND_NAME> finds an
;;   entry in a name table, <LIST_PRINT_NAME> prints a name, <LIST_LINE> lists a line and <LIST_STATEMENT> one of
;;   its statements, turning each token back into the text it stands for.
;; - <STATEMENT_FOR>, which pushes its loop on the run-time stack, and <STATEMENT_GOSUB> and <STATEMENT_GOTO>, with
;;   <GO_TO_LINE>, which ON, IF and TRAP also go through.
;;
;; Maintained by hand; assembles byte-identically to the cartridge.

;; Prints a character for PRINT, with bit 7 cleared, counting it in PRINT_COLUMN for the commas' tab stops.
;;
;; Bit 7 is cleared because FASC marks the last character of a number's text with it.
;; In: A = the character, OUTPUT_IOCB = the IOCB to write
;; Uses: A, X, Y, PRINT_COLUMN, IOCB_NUMBER
;; Entry: PRINT_CHARACTER_UNMASKED = prints A as it is, for a string's characters, which may be inverse
;; See: <PUT_CHARACTER>
PRINT_CHARACTER:
    and #$7F
PRINT_CHARACTER_UNMASKED:
    inc PRINT_COLUMN
    jmp PUT_CHARACTER

;; LPRINT: prints its items on the printer: LPRINT items, as PRINT does.
;;
;; Opens IOCB 7 on "P:" for writing, makes it the output IOCB, runs PRINT on the rest of the statement and closes the
;; IOCB again. PRINT puts the output back on the screen as it ends.
;; Errors: those of opening P: and of PRINT's items
;; See: <STATEMENT_PRINT>, <LPRINT_DEVICE>
STATEMENT_LPRINT:
    lda #<LPRINT_DEVICE
    sta INBUFF
    lda #>LPRINT_DEVICE
    sta INBUFF+1
    ldx #FILE_IOCB
    stx OUTPUT_IOCB
    lda #$00                        ; no second auxiliary byte
    ldy #OWRIT
    jsr OPEN_DEVICE                 ; open IOCB 7 on P:
    jsr CHECK_IO_STATUS             ; stop on its error
    jsr STATEMENT_PRINT             ; PRINT the items
    jmp CLOSE_IOCB                  ; close IOCB 7

;; The printer's device name, which LPRINT opens.
LPRINT_DEVICE:
    .byte "P:", EOL

;; LIST: lists the program, or part of it: LIST [file,] [first [, last]].
;;
;; With no line numbers, every line is listed; with one, that line; with two, the lines from the first to the last.
;; A string first argument names a file or device ("P:" for the printer, "C:" for the cassette), which is opened on
;; IOCB 7 for writing and gets the listing instead of the screen; a listing to a file can be read back by ENTER.
;; BREAK stops the listing. While listing, DSPFLG is set, so that the control characters in strings and REMs show as
;; characters instead of moving the cursor.
;;
;; Listing moves STMCUR through the program, so LIST first pushes a GOSUB entry for itself (<PUSH_GOSUB>), and ends by
;; going to RETURN (<STATEMENT_RETURN>), which finds LIST's line again and goes on after the statement.
;; Errors: 3 (ERR_VALUE) or 7 (ERR_NUMBER_TOO_BIG) for a line number that is out of range, 2 (ERR_MEMORY) when the
;;   run-time stack can't grow, and those of opening the file
;; See: <LIST_LINE>
STATEMENT_LIST:
    ldy #$00                        ; list from line 0
    sty LINE_NUMBER
    sty LINE_NUMBER+1
    dey                             ; to line 32767
    sty LIST_LAST_LINE
    lda #$7F
    sta LIST_LAST_LINE+1
    sta DSPFLG                      ; show control characters
    lda #EOL
    jsr PUT_CHARACTER
    jsr PUSH_GOSUB                  ; RETURN comes back here
LIST_ARGUMENTS:
    ldy TOKEN_OFFSET
    iny
    cpy NEXT_STATEMENT
    bcs LIST_FIND_FIRST             ; no more arguments
    lda TOKEN_OFFSET
    pha
    jsr EVALUATE_VALUE              ; a string or a number?
    pla
    sta TOKEN_OFFSET
    lda VALUE_TYPE
    bpl LIST_LINE_NUMBERS
    jsr OPEN_LIST_FILE              ; open the file and write to it
    jmp LIST_ARGUMENTS
LIST_LINE_NUMBERS:
    jsr EVALUATE_INTEGER            ; the first line; A = its high byte
    sta LINE_NUMBER+1
    lda FR0
    sta LINE_NUMBER
    ldy TOKEN_OFFSET
    cpy NEXT_STATEMENT
    beq LIST_SET_LAST               ; one number: the last is the first
    jsr EVALUATE_INTEGER            ; the last line
LIST_SET_LAST:
    lda FR0
    sta LIST_LAST_LINE
    lda FR0+1
    sta LIST_LAST_LINE+1
LIST_FIND_FIRST:
    jsr FIND_LINE                   ; STMCUR = the first line at or after LINE_NUMBER
LIST_LOOP:
    jsr GET_LINE_NUMBER_HIGH
    bmi LIST_DONE                   ; the immediate line: no more of the program
    ldy #LINE_NUMBER_OFFSET+1
    lda (STMCUR),y
    cmp LIST_LAST_LINE+1
    bcc LIST_THIS_LINE
    bne LIST_DONE
    dey
    lda (STMCUR),y
    cmp LIST_LAST_LINE
    bcc LIST_THIS_LINE
    bne LIST_DONE
LIST_THIS_LINE:
    jsr LIST_LINE
    jsr CHECK_BREAK
.if VERSION = VERSION_A
    bne LIST_DONE                   ; BREAK: rev. A's CHECK_BREAK gives nonzero
.else
    beq LIST_DONE                   ; BREAK
.endif
    jsr GET_LINE_LENGTH             ; on to the next line
    jsr ADVANCE_STMCUR
    jmp LIST_LOOP
LIST_DONE:
    lda OUTPUT_IOCB
    beq LIST_RETURN
    jsr CLOSE_IOCB                  ; close the file
    lda #$00
    sta OUTPUT_IOCB
LIST_RETURN:
    sta DSPFLG                      ; A = 0: obey control characters again
    jmp STATEMENT_RETURN

;; Finds an entry in a name table, by its number.
;;
;; Each entry of the table is NAME_OFFSET bytes of something else (the statement name table's syntax rule address),
;; then a name whose last character has bit 7 set. Entries are counted from 0.
;; In: A/Y = the table's address, high and low, X = the bytes before each entry's name, ENTRY_NUMBER = the entry
;; Out: NAME_POINTER = the entry's name
;; Uses: A, Y, NAME_OFFSET, ENTRY_NUMBER
;; Keeps: X
;; See: <LIST_PRINT_NAME>
LIST_FIND_NAME:
    stx NAME_OFFSET
    jsr LIST_SET_NAME_POINTER
LIST_FIND_NAME_LOOP:
    ldy NAME_OFFSET
    dec ENTRY_NUMBER
    bmi LIST_ADVANCE_NAME           ; this entry: point past the bytes before its name
LIST_FIND_NAME_SKIP:
    lda (NAME_POINTER),y
    bmi LIST_FIND_NAME_NEXT
    iny
    bne LIST_FIND_NAME_SKIP
LIST_FIND_NAME_NEXT:
    iny
    jsr LIST_ADVANCE_NAME           ; past this entry
    jmp LIST_FIND_NAME_LOOP

;; Moves NAME_POINTER on by Y bytes.
;; In: Y = the bytes
;; Out: NAME_POINTER = moved on
;; Uses: A, Y
;; Entry: LIST_SET_NAME_POINTER = sets NAME_POINTER to A/Y, high and low
LIST_ADVANCE_NAME:
    clc
    tya
    adc NAME_POINTER
    sta NAME_POINTER
    tay
    lda NAME_POINTER+1
    adc #$00
LIST_SET_NAME_POINTER:
    sta NAME_POINTER+1
    sty NAME_POINTER
    rts

;; Prints the name or message at NAME_POINTER, which ends with a character that has bit 7 set.
;;
;; Each character is printed with bit 7 cleared, except EOL, which is printed as it is and ends the name (the end of
;; a line's name in the operator name table). A last character of $80 alone is not printed, so an empty name prints
;; nothing.
;; In: NAME_POINTER = the name, OUTPUT_IOCB = the IOCB to write
;; Out: A = the name's last character, bit 7 set
;; Uses: X, Y, LIST_COUNT, IOCB_NUMBER
;; See: <PUT_CHARACTER>
LIST_PRINT_NAME:
    ldy #$FF
    sty LIST_COUNT
LIST_PRINT_NAME_LOOP:
    inc LIST_COUNT
    ldy LIST_COUNT
    lda (NAME_POINTER),y
    pha
    cmp #EOL
    beq LIST_PRINT_NAME_PUT
    and #$7F
    beq LIST_PRINT_NAME_NEXT        ; the $80 of an empty name
LIST_PRINT_NAME_PUT:
    jsr PUT_CHARACTER
LIST_PRINT_NAME_NEXT:
    pla
    bpl LIST_PRINT_NAME_LOOP
    rts

;; Prints the name at NAME_POINTER with a space before and after it, as an operator that is a word lists.
;; In: NAME_POINTER = the name, OUTPUT_IOCB = the IOCB to write
;; Uses: A, X, Y, LIST_COUNT, IOCB_NUMBER
;; Entry: LIST_NAME_SPACE = prints only the space after it, as a line number or a statement's name lists
;; See: <LIST_PRINT_NAME>
LIST_SPACED_NAME:
    lda #' '
    jsr PUT_CHARACTER
LIST_NAME_SPACE:
    jsr LIST_PRINT_NAME
    lda #' '
    jmp PUT_CHARACTER

;; Lists the line at STMCUR: its number, a space, and its statements.
;;
;; The listing ends with an EOL, which is the name of the line's last token, TOKEN_LINE_END.
;; In: STMCUR = the line, OUTPUT_IOCB = the IOCB to write
;; Uses: A, X, Y, FR0, INBUFF, NAME_POINTER, NAME_OFFSET, ENTRY_NUMBER, LIST_COUNT, LINE_LENGTH, NEXT_STATEMENT,
;;   TOKEN_OFFSET, VALUE_TYPE, VALUE_NUMBER, IOCB_NUMBER
;; Entry: LIST_STATEMENTS = lists only the statements, for the immediate line
;; See: <LIST_STATEMENT>
LIST_LINE:
    ldy #LINE_NUMBER_OFFSET
    lda (STMCUR),y
    sta FR0
    iny
    lda (STMCUR),y
    sta FR0+1
    jsr IFP
    jsr FASC                        ; the line number as text
    lda INBUFF
    sta NAME_POINTER
    lda INBUFF+1
    sta NAME_POINTER+1
    jsr LIST_NAME_SPACE
LIST_STATEMENTS:
    ldy #LINE_LENGTH_OFFSET
    lda (STMCUR),y
    sta LINE_LENGTH
    iny
LIST_STATEMENTS_LOOP:
    lda (STMCUR),y                  ; the offset of the statement after this one
    sta NEXT_STATEMENT
    iny
    sty TOKEN_OFFSET                ; this statement's token
    jsr LIST_STATEMENT
    ldy NEXT_STATEMENT
    cpy LINE_LENGTH
    bcc LIST_STATEMENTS_LOOP
    rts

;; Lists the statement at TOKEN_OFFSET in the line at STMCUR: its name, a space, and its tokens as text.
;;
;; An implied LET lists without a name. REM, DATA and a line with a syntax error (TOKEN_ERROR) keep their text as it
;; was typed, which is printed as it is; every other statement's tokens are turned back into text: a variable's name,
;; from the variable name table; a numeric constant, as FASC writes it; a string constant, in quotes; an operator's or
;; a function's name, from the operator name table. An operator that is a word (NOT, AND, TO, THEN...) has a space
;; on each side. The ( that follows an array variable is not printed, as the array's name ends with its own (.
;;
;; The statement ends where the next begins (NEXT_STATEMENT): <LIST_TOKEN> returns from this routine there.
;; In: STMCUR = the line, TOKEN_OFFSET = the statement's token, NEXT_STATEMENT = the next statement's offset,
;;   OUTPUT_IOCB = the IOCB to write
;; Uses: A, X, Y, FR0, INBUFF, NAME_POINTER, NAME_OFFSET, ENTRY_NUMBER, LIST_COUNT, TOKEN_OFFSET, VALUE_TYPE,
;;   VALUE_NUMBER, IOCB_NUMBER
;; See: <LIST_STATEMENT_NAME>, <LIST_FIND_NAME>
LIST_STATEMENT:
    jsr LIST_TOKEN
    cmp #TOKEN_IMPLIED_LET
    beq LIST_TOKENS
    jsr LIST_STATEMENT_NAME
    jsr LIST_TOKEN
    cmp #TOKEN_ERROR
    beq LIST_STATEMENT_TEXT
    cmp #TOKEN_INPUT
    bcs LIST_TOKENS                 ; not REM or DATA
LIST_STATEMENT_TEXT:
    jsr LIST_NEXT_TOKEN             ; the text as it was typed
    jsr PUT_CHARACTER
    jmp LIST_STATEMENT_TEXT
LIST_TOKENS:
    jsr LIST_NEXT_TOKEN
    bpl LIST_NOT_VARIABLE
    and #$7F                        ; a variable: its number
    sta ENTRY_NUMBER
    ldx #$00
    lda VNTP+1
    ldy VNTP
    jsr LIST_FIND_NAME
    jsr LIST_PRINT_NAME
    cmp #'(' | NAME_END
    bne LIST_TOKENS
    jsr LIST_NEXT_TOKEN             ; an array: skip the ( token
    jmp LIST_TOKENS
LIST_NOT_VARIABLE:
    cmp #TOKEN_STRING
    beq LIST_STRING
    bcs LIST_OPERATOR
    jsr READ_NUMBER_CONSTANT        ; a number: FR0 = it, TOKEN_OFFSET past it
    dec TOKEN_OFFSET                ; on its last byte
    jsr FASC
    lda INBUFF
    sta NAME_POINTER
    lda INBUFF+1
    sta NAME_POINTER+1
LIST_TOKEN_NAME:
    jsr LIST_PRINT_NAME
    jmp LIST_TOKENS
LIST_STRING:
    jsr LIST_NEXT_TOKEN             ; the length
    sta LIST_COUNT
    lda #'"'
    jsr PUT_CHARACTER
    lda LIST_COUNT
    beq LIST_STRING_END
LIST_STRING_LOOP:
    jsr LIST_NEXT_TOKEN
    jsr PUT_CHARACTER
    dec LIST_COUNT
    bne LIST_STRING_LOOP
LIST_STRING_END:
    lda #'"'
    jsr PUT_CHARACTER
    jmp LIST_TOKENS
LIST_OPERATOR:
    sec
    sbc #OPERATOR_NAMES_FIRST
    sta ENTRY_NUMBER
    ldx #$00
    lda #>OPERATOR_NAMES
    ldy #<OPERATOR_NAMES
    jsr LIST_FIND_NAME
    jsr LIST_TOKEN
    cmp #FN_STR
    bcs LIST_TOKEN_NAME             ; a function: just its name
    ldy #$00
    lda (NAME_POINTER),y
    and #$7F
    jsr TEST_LETTER_IN_A
    bcs LIST_TOKEN_NAME             ; not a word: just its name
    jsr LIST_SPACED_NAME
    jmp LIST_TOKENS

;; Reads the statement's next token, for the lister, or ends the statement's listing.
;;
;; When the statement has no more tokens, this returns from the routine that called the routine that called it: from
;; <LIST_STATEMENT>.
;; In: STMCUR = the line, TOKEN_OFFSET = the last token read, NEXT_STATEMENT = the end of the statement
;; Out: A = the token, Y = TOKEN_OFFSET, the token's offset, negative = the token's bit 7
;; Entry: LIST_TOKEN = reads the token at TOKEN_OFFSET again
LIST_NEXT_TOKEN:
    inc TOKEN_OFFSET
LIST_TOKEN:
    ldy TOKEN_OFFSET
    cpy NEXT_STATEMENT
    bcs LIST_TOKEN_END
    lda (STMCUR),y
    rts
LIST_TOKEN_END:
    pla                             ; drop the return address into the lister
    pla
    rts

;; Prints a statement's name, from the statement name table, and a space.
;;
;; The error report prints "ERROR-" and its spaces this way, as TOKEN_ERROR's name.
;; In: A = the statement's token, OUTPUT_IOCB = the IOCB to write
;; Uses: A, X, Y, NAME_POINTER, NAME_OFFSET, ENTRY_NUMBER, LIST_COUNT, IOCB_NUMBER
;; See: <STATEMENT_NAMES>
LIST_STATEMENT_NAME:
    sta ENTRY_NUMBER
    ldx #$02                        ; the syntax rule's address comes before each name
    lda #>STATEMENT_NAMES
    ldy #<STATEMENT_NAMES
    jsr LIST_FIND_NAME
    jmp LIST_NAME_SPACE

;; FOR: starts a loop: FOR var = start TO limit [STEP step], which NEXT closes.
;;
;; The variable is assigned the start, then the limit and the step (1 when there is no STEP) are pushed on the
;; run-time stack with a header: the variable's token, the line's number and the offset of the FOR statement's
;; token, so that NEXT can come back after it. The limit is at offset 0 of the 12 bytes, the step at offset 6.
;;
;; A loop already on the stack for the same variable is taken off first, with every entry above it, so that leaving a
;; loop by GOTO and starting it again does not fill the stack. The search stops at the first GOSUB entry: a loop
;; outside the subroutine stays.
;; Errors: 2 (ERR_MEMORY) when the run-time stack can't grow, and those of the expressions
;; See: <FIND_FOR_ENTRY>, <PUSH_RUNSTACK_HEADER>
STATEMENT_FOR:
    jsr SAVE_STATEMENT_OFFSET       ; STATEMENT_OFFSET = this statement's
    jsr EVALUATE_EXPRESSION         ; var = start
    lda VALUE_NUMBER
    ora #TOKEN_VARIABLE             ; the variable's token
    pha
    jsr FIND_FOR_ENTRY              ; take off its earlier loop
    lda #FOR_VALUES
    jsr PUSH_RUNSTACK
    jsr EVALUATE_VALUE              ; the limit
    ldx #FR0
    ldy #$00
    jsr COPY_TO_RUNSTACK
    jsr ZFR0                        ; the step is 1 by default
    lda #$01
    sta FR0+1
    lda #$40
    sta FR0
    jsr AT_STATEMENT_END
    bcs FOR_PUSH_STEP               ; no STEP
    jsr EVALUATE_VALUE              ; the step
FOR_PUSH_STEP:
    ldx #FR0
    ldy #FP_SIZE
    jsr COPY_TO_RUNSTACK
    pla
;; Pushes a run-time stack entry's header: a token, the current line's number, and the offset of the statement's
;; token.
;;
;; GOSUB and the other statements that RETURN goes back to (ON ... GOSUB, LIST and READ) push 0; RETURN tells them
;; apart by the statement's own token. FOR pushes its variable's token.
;; In: A = the token, STMCUR = the line, STATEMENT_OFFSET = the offset just after the statement's token
;; Out: RUNSTACK_ENTRY = the header
;; Uses: A, X, Y
;; Errors: 2 (ERR_MEMORY) when the run-time stack can't grow
;; See: <PUSH_RUNSTACK>, <STATEMENT_POP>
PUSH_RUNSTACK_HEADER:
    pha
    lda #RUNSTACK_HEADER
    jsr PUSH_RUNSTACK
    pla
    ldy #$00
    sta (RUNSTACK_ENTRY),y          ; the token
    lda (STMCUR),y
    iny
    sta (RUNSTACK_ENTRY),y          ; the line's number
    lda (STMCUR),y
    iny
    sta (RUNSTACK_ENTRY),y
    ldx STATEMENT_OFFSET
    dex
    txa
    iny
    sta (RUNSTACK_ENTRY),y          ; the statement token's offset
    rts

;; GOSUB: calls a subroutine: GOSUB line, which RETURN ends.
;;
;; Pushes a GOSUB entry on the run-time stack, then goes to the line as GOTO does. When the line is not found, the
;; entry stays on the stack.
;; Errors: 12 (ERR_LINE_NOT_FOUND), 2 (ERR_MEMORY) when the run-time stack can't grow, and those of the expression
;; See: <PUSH_GOSUB>, <STATEMENT_RETURN>
STATEMENT_GOSUB:
    jsr PUSH_GOSUB
;; GOTO and GO TO: goes to a line: GOTO line, where the line may be any expression.
;; Errors: 12 (ERR_LINE_NOT_FOUND), 3 (ERR_VALUE) or 7 (ERR_NUMBER_TOO_BIG) for a line number out of range
;; Entry: GO_TO_FR0_LINE = goes to the line in FR0, for ON
STATEMENT_GOTO:
    jsr EVALUATE_INTEGER
GO_TO_FR0_LINE:
    lda FR0+1
    sta LINE_NUMBER+1
    lda FR0
    sta LINE_NUMBER
;; Goes to a line: runs the program from its first statement.
;;
;; Called by a statement, which jumps here: the return address into the execution loop is dropped, and the loop starts
;; again at the line (<EXECUTE_LINE>). When the line is not found, STMCUR goes back to the line being run, so that the
;; error report names it.
;; In: LINE_NUMBER = the line
;; Errors: 12 (ERR_LINE_NOT_FOUND)
;; See: <FIND_LINE>
GO_TO_LINE:
    jsr FIND_LINE
    bcs GO_TO_LINE_NOT_FOUND
    pla
    pla
    jmp EXECUTE_LINE
GO_TO_LINE_NOT_FOUND:
    jsr RESTORE_STMCUR
    jsr LINE_NOT_FOUND_ERROR        ; error 12; never returns
;; Puts STMCUR back where it was before the last line search.
;; In: STMCUR_SAVE = STMCUR before the search
;; Out: STMCUR = it
;; Uses: A
;; Keeps: X, Y
;; See: <FIND_LINE>
RESTORE_STMCUR:
    lda STMCUR_SAVE
    sta STMCUR
    lda STMCUR_SAVE+1
    sta STMCUR+1
    rts
