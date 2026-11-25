;; THE EDITOR ($A000-$A2E0)
;;
;; BASIC's start and its line editor: the cold start and NEW, which empty every table; the warm start, which keeps
;; the program; READY; then the loop that reads each line, tokenizes it statement by statement, and stores it in the
;; statement table, deletes it, or runs it. With it the line number's tokens, the syntax checker's engine, which
;; runs a statement's rule from the syntax tables, and the routine that writes each token. Maintained by hand;
;; assembles byte-identically to the cartridge.

; The editor's own values.

EDITOR_INVERSE = %10000000          ;; set in a character to show it in inverse video, marking a syntax error
EDITOR_TAB_WIDTH = 10               ;; PTABW from the cold start and NEW: a comma in PRINT tabs to every tenth column
EDITOR_EXPRESSION_CODE = $05        ;; the lowest syntax code that matches an expression; $04 below it returns

;; Starts BASIC, the cartridge's start address, where the OS comes after power-up and after SYSTEM RESET.
;;
;; SYSTEM RESET keeps the program and comes to the warm start. Power-up, or a SYSTEM RESET while LOAD was reading a
;; program (which leaves the tables half loaded), starts cold, as NEW.
;; In: LOAD_FLAG = nonzero while a LOAD was reading, WARMST = 0 on power-up
;; See: <COLD_START>, <WARM_START>
CARTRIDGE_START:
    lda LOAD_FLAG
    bne COLD_START
    lda WARMST
    bne WARM_START
;; Starts BASIC cold: resets the 6502 stack, then empties the program as <STATEMENT_NEW> does.
COLD_START:
    ldx #$FF
    txs
    cld
;; NEW: erases the program in memory, and its variables, and gives READY.
;;
;; LOMEM is set from the OS's MEMLO again, then every table is emptied 256 bytes above it, past the token output
;; buffer: the variable name table holds only its dummy zero byte, and the statement table only the empty immediate
;; line, line IMMEDIATE_LINE with no statements. PRINT's tab width goes back to 10. The warm start follows, which
;; clears the run state and closes every file.
;; Errors: 2 (memory insufficient), if MEMLO leaves no room for the tables
;; See: <WARM_START>
STATEMENT_NEW:
    ldx MEMLO
    ldy MEMLO+1
    stx LOMEM
    sty LOMEM+1
    lda #$00
    sta EOL_PATCHED
    sta LOAD_FLAG
    iny                             ; one page up, past the token output buffer
    txa
    ldx #VNTP                       ; every pointer from VNTP to BASIC_MEMTOP: the tables are empty
STATEMENT_NEW_LOOP:
    sta 0,x
    inx
    sty 0,x
    inx
    cpx #BASIC_MEMTOP+2
    bcc STATEMENT_NEW_LOOP
    ldx #VVTP                       ; a byte for the name table's dummy zero, at VNTD
    ldy #$01
    jsr OPEN_SPACE
    ldx #STARP                      ; and three for the immediate line, at STMCUR
    ldy #FIRST_STATEMENT_OFFSET
    jsr OPEN_SPACE
    lda #$00
    tay
    sta (VNTD),y
    sta (STMCUR),y                  ; the immediate line's number, IMMEDIATE_LINE
    iny
    lda #>IMMEDIATE_LINE
    sta (STMCUR),y
    iny
    lda #FIRST_STATEMENT_OFFSET     ; its length: no statements
    sta (STMCUR),y
    lda #EDITOR_TAB_WIDTH
    sta PTABW
;; Starts BASIC warm, keeping the program: clears the run state, closes every file and gives READY.
;;
;; The run state is READ's place, the error, STOPLN, DEG, TRAP and BREAK (<RESET_RUN_STATE>, which closes the files
;; itself too, so they are closed twice).
;; Entry:
;;   WARM_START_CLOSE = silences the sound and closes IOCBs 1-7, then READY: the end of a program
;;   WARM_START_SCREEN = INPUT and PRINT go back to IOCB 0, a string's EOL is restored, then READY
;;   WARM_START_READY = prints READY, then edits: the end of an immediate line
;; See: <EDIT_LINE>
WARM_START:
    jsr RESET_RUN_STATE
WARM_START_CLOSE:
    jsr SILENCE_CLOSE_ALL
WARM_START_SCREEN:
    jsr DEFAULT_IOCBS
    lda EOL_PATCHED
    beq WARM_START_READY
    jsr RESTORE_STRING_EOL
WARM_START_READY:
    jsr PRINT_READY
;; The line editor: reads a line from the editor or ENTER's file, tokenizes it, and stores, deletes or runs it.
;;
;; A line with a number goes into the statement table in number order, replacing the line with that number; a number
;; alone deletes it. A line without one is the immediate line, which replaces the last one, after the program's lines,
;; and runs at once. A blank line, or one read after BREAK was pressed, is ignored. A line number of 32768 or more
;; makes the line immediate, read again from its start.
;;
;; Each statement is tokenized into the token output buffer at LOMEM: the offset of the next statement, the token
;; its name matched in the statement name table, then the tokens its rule writes, checked by <CHECK_SYNTAX>. When a
;; statement fails, the character where the checker got furthest is shown in inverse video (an inverse space when it
;; was the end of the line), and the line is stored as one TOKEN_ERROR statement holding the text as typed, listed
;; at once, so that it can be edited; the variables that the line added are taken out of the tables again.
;;
;; The line is stored by opening or closing space at the place of the old line, through the memory mover, and copying
;; the tokens there. The editor never returns; it comes back here for each line, with a fresh 6502 stack, and starts
;; cold if a LOAD was cut short by an error.
;; In: INPUT_IOCB = the IOCB to read, LOAD_FLAG = nonzero after a LOAD was cut short
;; Errors: 2 (memory insufficient), 3 (value error) for a negative line number, 4 (too many variables), 14 (line
;;   too long)
;; Entry:
;;   EDIT_LINE_STATEMENT = the next statement, with CIX at its first character
;;   EDIT_LINE_COPY_NEXT = copies the line from CIX as typed to its end, ending the line
;; See: <READ_LINE_NUMBER>, <CHECK_SYNTAX>, <WRITE_TOKEN>, <SYNTAX_END_STATEMENT>, <SYNTAX_REST_OF_LINE>
EDIT_LINE:
    lda LOAD_FLAG
    bne CARTRIDGE_START             ; the program is half loaded: start cold
    ldx #$FF
    txs
    jsr FP_SET_INBUFF_LBUFF
    lda #PROMPT_EDITOR
    sta PROMPT
    jsr READ_INPUT_LINE             ; read the line into LBUFF
    jsr CHECK_BREAK                 ; BREAK was pressed: ignore it
.if VERSION = VERSION_A
    bne EDIT_LINE                   ; rev. A's CHECK_BREAK gives nonzero for BREAK
.else
    beq EDIT_LINE
.endif
    lda #$00
    sta CIX
    sta ERROR_INDEX
    sta TOKEN_INDEX
    sta EDIT_FLAGS
    sta OPERATOR_SEARCHED
    sta OPERATOR_FOUND
    sta NEW_VARIABLES
    lda VNTD
    sta SAVED_VNTD
    lda VNTD+1
    sta SAVED_VNTD+1
    jsr FP_SKIP_SPACES
    jsr READ_LINE_NUMBER
    jsr WRITE_TOKEN                 ; a place for the line's length
    lda FR0+1
    bpl EDIT_LINE_TEXT
    sta EDIT_FLAGS                  ; bit 7: the immediate line
EDIT_LINE_TEXT:
    jsr FP_SKIP_SPACES
    ldy CIX
    sty STATEMENT_START             ; where an error line's text starts
    lda (INBUFF),y
    cmp #EOL
    bne EDIT_LINE_STATEMENT
    bit EDIT_FLAGS
    bmi EDIT_LINE                   ; a blank line
    jmp EDIT_LINE_DELETE            ; a line number alone
EDIT_LINE_STATEMENT:
    lda TOKEN_INDEX
    sta NEXT_STATEMENT
    jsr WRITE_TOKEN                 ; a place for the next statement's offset
    jsr FP_SKIP_SPACES
    lda #>STATEMENT_NAMES
    ldy #<STATEMENT_NAMES
    ldx #STATEMENT_NAME_OFFSET
    jsr SEARCH_NAMES
    stx CIX
    lda ENTRY_NUMBER                ; the statement's token
    jsr WRITE_TOKEN
    jsr FP_SKIP_SPACES
    jsr CHECK_SYNTAX
    bcc EDIT_LINE_STATEMENT_END
    ldy ERROR_INDEX                 ; a syntax error: mark where
    lda (INBUFF),y
    cmp #EOL
    bne EDIT_LINE_MARK_ERROR
    iny                             ; at the end of the line: move the EOL on, and mark a space
    sta (INBUFF),y
    dey
    lda #' '
EDIT_LINE_MARK_ERROR:
    ora #EDITOR_INVERSE
    sta (INBUFF),y
    lda #EDIT_ERROR
    ora EDIT_FLAGS
    sta EDIT_FLAGS
    ldy STATEMENT_START             ; the whole line again, as one statement
    sty CIX
    ldx #FIRST_STATEMENT_OFFSET
    stx NEXT_STATEMENT
    inx
    stx TOKEN_INDEX
    lda #TOKEN_ERROR
EDIT_LINE_COPY:
    jsr WRITE_TOKEN
EDIT_LINE_COPY_NEXT:
    ldy CIX
    lda (INBUFF),y
    inc CIX
    cmp #EOL
    bne EDIT_LINE_COPY
    jsr WRITE_TOKEN                 ; the EOL too
EDIT_LINE_STATEMENT_END:
    lda TOKEN_INDEX                 ; the next statement's offset
    ldy NEXT_STATEMENT
    sta (LOMEM),y
    ldy CIX                         ; did the statement end the line?
    dey
    lda (INBUFF),y
    cmp #EOL
    bne EDIT_LINE_STATEMENT
    ldy #LINE_LENGTH_OFFSET
    lda TOKEN_INDEX
    sta (LOMEM),y
    jsr FIND_LINE                   ; find the line, or the place for it
    lda #$00                        ; the old line's length, or 0
    bcs EDIT_LINE_RESIZE
    jsr GET_LINE_LENGTH
EDIT_LINE_RESIZE:
    sec
    sbc TOKEN_INDEX
    beq EDIT_LINE_STORE             ; the same length
    bcs EDIT_LINE_SHRINK
    eor #$FF                        ; longer: open the difference at STMCUR
    tay
    iny
    ldx #STMCUR
    jsr OPEN_SPACE
    lda NEW_SPACE                   ; STMCUR moved up with the tables: back to the space
    sta STMCUR
    lda NEW_SPACE+1
    sta STMCUR+1
    bne EDIT_LINE_STORE             ; always: no table is in page zero
EDIT_LINE_SHRINK:
.if VERSION = VERSION_A
    pha                             ; shorter: close the difference at the old line's end (rev. A's ADVANCE_STMCUR
    jsr ADVANCE_STMCUR              ; changes Y, so the size waits on the stack)
    pla
    tay
.else
    tay                             ; shorter: close the difference at the old line's end
    jsr ADVANCE_STMCUR
.endif
    ldx #STMCUR
    jsr CLOSE_SPACE
EDIT_LINE_STORE:
    ldy TOKEN_INDEX
EDIT_LINE_STORE_LOOP:
    dey
    lda (LOMEM),y
    sta (STMCUR),y
    tya
    bne EDIT_LINE_STORE_LOOP
    bit EDIT_FLAGS
    bvc EDIT_LINE_STORED
    lda NEW_VARIABLES               ; an error: take out the line's new variables' value entries
    asl A
    asl A
    asl A
.if VERSION = VERSION_A
    tay                             ; rev. A has no CLOSE_SPACE_A
    ldx #STMTAB
    jsr CLOSE_SPACE
.else
    ldx #STMTAB
    jsr CLOSE_SPACE_A
.endif
    sec                             ; and their names
    lda VNTD
    sbc SAVED_VNTD
    tay
    lda VNTD+1
    sbc SAVED_VNTD+1
    ldx #VNTD
    jsr CLOSE_SPACE_LONG
    bit EDIT_FLAGS                  ; then list the line
    bpl EDIT_LINE_LIST_NUMBERED
    jsr LIST_STATEMENTS
    jmp EDIT_LINE
EDIT_LINE_LIST_NUMBERED:
    jsr LIST_LINE
EDIT_LINE_NEXT:
    jmp EDIT_LINE
EDIT_LINE_STORED:
    bpl EDIT_LINE_NEXT
    jmp EXECUTE_LINE                ; run the immediate line
EDIT_LINE_DELETE:
    jsr FIND_LINE
    bcs EDIT_LINE_NEXT              ; no such line
    jsr GET_LINE_LENGTH
.if VERSION = VERSION_A
    pha                             ; rev. A's ADVANCE_STMCUR changes Y
    jsr ADVANCE_STMCUR
    pla
    tay
.else
    tay
    jsr ADVANCE_STMCUR
.endif
    ldx #STMCUR
    jsr CLOSE_SPACE
    jmp EDIT_LINE
;; Reads the line number at the start of the line and writes it as the line's first two tokens.
;;
;; A line without a number is the immediate line, numbered IMMEDIATE_LINE; so is one whose number is 32768 or more,
;; which is then read again from its start.
;; In: INBUFF = the line, CIX = its first character after any spaces
;; Out: LINE_NUMBER = the line number, FR0+1 = A = its high byte, CIX = after the number, or 0 for the immediate line
;; Errors: 3 (value error), for a negative number or one of 65536 or more; 14 (line too long)
;; Uses: A, X, Y, FR0, TOKEN_INDEX
READ_LINE_NUMBER:
    jsr AFP
    bcc READ_LINE_NUMBER_INTEGER
READ_LINE_NUMBER_IMMEDIATE:
    lda #<IMMEDIATE_LINE
    sta CIX
    ldy #>IMMEDIATE_LINE
    bmi READ_LINE_NUMBER_STORE      ; always
READ_LINE_NUMBER_INTEGER:
    jsr CHECKED_FPI
    ldy FR0+1
    bmi READ_LINE_NUMBER_IMMEDIATE
    lda FR0
READ_LINE_NUMBER_STORE:
    sty LINE_NUMBER+1
    sta LINE_NUMBER
    jsr WRITE_TOKEN
    lda LINE_NUMBER+1
    sta FR0+1
    jmp WRITE_TOKEN
;; Checks a statement against its rule in the syntax tables, writing its tokens.
;;
;; The checker walks the rule's codes (see the SYNTAX_ codes): it matches tokens in the input, calls other rules and
;; syntax routines, and writes tokens to the token output buffer as it goes. Each rule it calls, by SYNTAX_CALL, a
;; relative code or an expression code, gets an entry on the syntax stack holding the input's and output's indexes
;; at the rule's start and the place in the caller to come back to. A rule ends, matched, at the first SYNTAX_OR or
;; SYNTAX_RETURN it reaches. A code that fails skips the rule's codes to the next SYNTAX_OR, which starts the next
;; alternative from the rule's start again (ERROR_INDEX keeping the furthest place the input reached), or to its
;; SYNTAX_RETURN, which fails the rule and so the code that called it, in the caller.
;;
;; A relative code from $80 calls the rule at its own address plus the code less SYNTAX_BIAS. Codes $05-$0C and
;; SYNTAX_EXPRESSION call the expression's rule, <RULE_EXPRESSION>. A syntax routine returns carry clear when it
;; matched; <SYNTAX_END_STATEMENT> and <SYNTAX_REST_OF_LINE> end the statement themselves, leaving the checker by
;; resetting the 6502 stack.
;; In: NAME_POINTER = the statement's entry in the statement name table, whose first word is its rule's address less
;;   1, CIX = the statement's first character after its name, TOKEN_INDEX = the place for its next token
;; Out: carry = clear when the statement matched, CIX = after it, TOKEN_INDEX = after its tokens
;; Errors: carry = set for a syntax error, ERROR_INDEX = the furthest index in the line reached; 14 (line too long),
;;   when the syntax stack overflows or the tokens pass 256 bytes
;; Uses: A, X, Y, SYNTAX_POINTER, SYNTAX_STACK_INDEX, SYNTAX_STACK
;; See: <READ_SYNTAX_CODE>, <WRITE_TOKEN>
CHECK_SYNTAX:
    ldy #$01                        ; the bottom entry: the rule's address less 1, and where the statement starts
    lda (NAME_POINTER),y
    sta SYNTAX_POINTER+1
    sta SYNTAX_STACK_RULE+1
    dey
    lda (NAME_POINTER),y
    sta SYNTAX_POINTER
    sta SYNTAX_STACK_RULE
.if VERSION = VERSION_A
    lda #$00                        ; rev. A loads the 0 that Y already is
    sta SYNTAX_STACK_INDEX
.else
    sty SYNTAX_STACK_INDEX
.endif
    lda TOKEN_INDEX
    sta SYNTAX_STACK_OUTPUT
    lda CIX
    sta SYNTAX_STACK_INPUT
CHECK_SYNTAX_NEXT:
    jsr READ_SYNTAX_CODE
    bmi CHECK_SYNTAX_RELATIVE
    cmp #SYNTAX_ROUTINE
    bcc CHECK_SYNTAX_CALL           ; carry clear: a rule
    bne CHECK_SYNTAX_OTHER
    jsr CHECK_SYNTAX_CALL           ; carry set: call the routine, which returns here
.if VERSION = VERSION_A
    bcc CHECK_SYNTAX_NEXT           ; rev. A tests the result here, as CHECK_SYNTAX_RESULT does
    jmp CHECK_SYNTAX_FAIL
.else
    jmp CHECK_SYNTAX_RESULT
.endif
CHECK_SYNTAX_OTHER:
    cmp #EDITOR_EXPRESSION_CODE
    bcc CHECK_SYNTAX_RETURN         ; carry clear: the rule matched
    jsr CHECK_SYNTAX_CODE
.if VERSION = VERSION_A
    bcc CHECK_SYNTAX_NEXT           ; rev. A tests the result here, as CHECK_SYNTAX_RESULT does
    jmp CHECK_SYNTAX_FAIL
.else
    jmp CHECK_SYNTAX_RESULT
.endif
CHECK_SYNTAX_RELATIVE:
    sec                             ; the code less SYNTAX_BIAS, less 1 for the pointer's pre-increment
.if VERSION = VERSION_A
    ldx #$00                        ; rev. A clears X, which READ_SYNTAX_CODE already has
.endif
    sbc #SYNTAX_BIAS+1
    bcs CHECK_SYNTAX_RELATIVE_ADD   ; X = 0 from READ_SYNTAX_CODE: forward
    ldx #$FF                        ; backward
CHECK_SYNTAX_RELATIVE_ADD:
    clc
    adc SYNTAX_POINTER
    pha
    txa
    adc SYNTAX_POINTER+1
    pha
    jmp CHECK_SYNTAX_PUSH
;; Reads the word after a SYNTAX_CALL or SYNTAX_ROUTINE code, an address less 1, and calls the rule or the routine.
;;
;; A rule's address goes on the 6502 stack for <CHECK_SYNTAX_PUSH>; a routine's address is pushed high byte first,
;; so that the RTS here enters it, and it returns to the caller of this.
;; In: carry = clear for a rule, set for a routine, SYNTAX_POINTER = the code
;; Out: SYNTAX_POINTER = the word's last byte
CHECK_SYNTAX_CALL:
    jsr READ_SYNTAX_CODE
    pha
    jsr READ_SYNTAX_CODE
    pha
    bcc CHECK_SYNTAX_PUSH
    pla                             ; a routine: swap the bytes for the RTS
    tay
    pla
    tax
    tya
    pha
    txa
    pha
CHECK_SYNTAX_DONE:
    rts
CHECK_SYNTAX_PUSH:
    ldx SYNTAX_STACK_INDEX          ; a new entry for the rule, as it starts
    inx
    inx
    inx
    inx
    beq CHECK_SYNTAX_TOO_LONG
    stx SYNTAX_STACK_INDEX
    lda CIX
    sta SYNTAX_STACK_INPUT,x
    lda TOKEN_INDEX
    sta SYNTAX_STACK_OUTPUT,x
    lda SYNTAX_POINTER
    sta SYNTAX_STACK_RULE,x
    lda SYNTAX_POINTER+1
    sta SYNTAX_STACK_RULE+1,x
    pla                             ; the rule's address less 1, high byte on top
    sta SYNTAX_POINTER+1
    pla
    sta SYNTAX_POINTER
    jmp CHECK_SYNTAX_NEXT
CHECK_SYNTAX_TOO_LONG:
    jmp LINE_TOO_LONG_ERROR
CHECK_SYNTAX_RETURN:
    ldx SYNTAX_STACK_INDEX          ; the rule ends, matched or failed by carry
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    bne CHECK_SYNTAX_RETURN_CALLER
    rts                             ; the statement's rule
CHECK_SYNTAX_RETURN_CALLER:
.else
    beq CHECK_SYNTAX_DONE           ; the statement's rule
.endif
    lda SYNTAX_STACK_RULE,x         ; back in the caller
    sta SYNTAX_POINTER
    lda SYNTAX_STACK_RULE+1,x
    sta SYNTAX_POINTER+1
    dex
    dex
    dex
    dex
    stx SYNTAX_STACK_INDEX
CHECK_SYNTAX_RESULT:
    bcs CHECK_SYNTAX_FAIL
    jmp CHECK_SYNTAX_NEXT
CHECK_SYNTAX_FAIL:
    jsr READ_SYNTAX_CODE            ; skip to the rule's next SYNTAX_OR or its SYNTAX_RETURN
    bmi CHECK_SYNTAX_FAIL
    cmp #SYNTAX_OR
    bcs CHECK_SYNTAX_FAIL_CONTROL
    jsr STEP_SYNTAX_POINTER         ; a call's word
    jsr STEP_SYNTAX_POINTER
    bne CHECK_SYNTAX_FAIL           ; always
CHECK_SYNTAX_FAIL_CONTROL:
    cmp #SYNTAX_RETURN
    beq CHECK_SYNTAX_RETURN         ; carry set: the rule failed
    bcs CHECK_SYNTAX_FAIL
    lda CIX                         ; the next alternative: keep the furthest place reached
    cmp ERROR_INDEX
    bcc CHECK_SYNTAX_ALTERNATIVE
    sta ERROR_INDEX
CHECK_SYNTAX_ALTERNATIVE:
    ldx SYNTAX_STACK_INDEX          ; and start again where the rule did
    lda SYNTAX_STACK_INPUT,x
    sta CIX
    lda SYNTAX_STACK_OUTPUT,x
    sta TOKEN_INDEX
    jmp CHECK_SYNTAX_NEXT
;; Steps the syntax checker's place to the next byte of the syntax tables.
;; Out: SYNTAX_POINTER = the next byte, zero = clear
;; Keeps: A, X, Y, carry
STEP_SYNTAX_POINTER:
    inc SYNTAX_POINTER
    bne STEP_SYNTAX_POINTER_DONE
    inc SYNTAX_POINTER+1
STEP_SYNTAX_POINTER_DONE:
    rts
;; Steps to the syntax tables' next byte and reads it.
;; Out: A = the code, SYNTAX_POINTER = its address, X = 0, negative = set for a relative code
;; Keeps: Y, carry
;; See: <STEP_SYNTAX_POINTER>
READ_SYNTAX_CODE:
    jsr STEP_SYNTAX_POINTER
    ldx #$00
    lda (SYNTAX_POINTER,x)
    rts
;; Matches a syntax code from EDITOR_EXPRESSION_CODE up: a token, SYNTAX_TOKEN, SYNTAX_REPLACE or an expression.
;;
;; A token from SYNTAX_FIRST_TOKEN up is matched against the input after its spaces, and SYNTAX_TOKEN's following token
;; without skipping them, both by <MATCH_OPERATOR>; SYNTAX_REPLACE replaces the token just written with its following
;; byte. The expression codes call the expression's rule instead, dropping this routine's return.
;; In: A = the code, SYNTAX_POINTER = its address
;; Out: carry = clear when it matched, SYNTAX_POINTER = the code's last byte
CHECK_SYNTAX_CODE:
    cmp #SYNTAX_REPLACE
    beq CHECK_SYNTAX_REPLACE
    bcs MATCH_OPERATOR
.if VERSION >= VERSION_B
    cmp #SYNTAX_TOKEN               ; rev. A has no SYNTAX_TOKEN: its $0D is an expression's code
    bne CHECK_SYNTAX_EXPRESSION
    jsr STEP_SYNTAX_POINTER
    jmp MATCH_OPERATOR_HERE
.endif
CHECK_SYNTAX_EXPRESSION:
    pla
    pla
    lda #<(RULE_EXPRESSION-1)
    pha
    lda #>(RULE_EXPRESSION-1)
    pha
    jmp CHECK_SYNTAX_PUSH
CHECK_SYNTAX_REPLACE:
    jsr STEP_SYNTAX_POINTER
    ldy #$00
    lda (SYNTAX_POINTER),y
    ldy TOKEN_INDEX
    dey
    sta (LOMEM),y
    clc
CHECK_SYNTAX_REPLACE_DONE:
    rts
;; Writes a token to the token output buffer at LOMEM.
;; In: A = the token, TOKEN_INDEX = its place
;; Out: TOKEN_INDEX = the next place, Y = the token's place
;; Errors: 14 (line too long), when the line's tokens pass 256 bytes
;; Keeps: A, X
WRITE_TOKEN:
    ldy TOKEN_INDEX
    sta (LOMEM),y
    inc TOKEN_INDEX
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    beq WRITE_TOKEN_TOO_LONG
    rts
WRITE_TOKEN_TOO_LONG:
.else
    bne CHECK_SYNTAX_REPLACE_DONE
.endif
    jmp LINE_TOO_LONG_ERROR
;; A syntax routine that ends the statement where the input is, so that a new statement starts there: after IF's
;; THEN, when a statement follows it.
;;
;; The checker is left behind by resetting the 6502 stack; the statement's tokens are kept as written, and the next
;; statement is tokenized from CIX.
;; In: CIX = the next statement's first character, TOKEN_INDEX = the place for its first token
;; See: <EDIT_LINE>
SYNTAX_END_STATEMENT:
    ldx #$FF
    txs
    lda TOKEN_INDEX
    ldy NEXT_STATEMENT
    sta (LOMEM),y
    jmp EDIT_LINE_STATEMENT
;; A syntax routine that copies the rest of the line as typed, with its EOL, ending the line: REM's and DATA's text.
;;
;; The checker is left behind by resetting the 6502 stack.
;; In: CIX = the text's first character
;; See: <EDIT_LINE>
SYNTAX_REST_OF_LINE:
    ldx #$FF
    txs
    jmp EDIT_LINE_COPY_NEXT
