;; EXECUTION ($A87A-$AB8F)
;;
;; The heart of the running program, and the memory mover every table shares:
;;
;; - <OPEN_SPACE> and <CLOSE_SPACE> open or close space at one of the program's tables, moving that table and every
;;   one above it and their pointers, up to BASIC_MEMTOP; <MOVE_MEMORY_DOWN> is their copy, which string assignment
;;   uses too.
;; - <EXECUTE_LINE> runs the program's statements one after the other, through <STATEMENT_ROUTINES>, testing BREAK
;;   before each; <FIND_LINE> finds a line by its number, and small helpers step STMCUR and read a line's length and
;;   number.
;; - REM and DATA, BYE and DOS, the statements that do the least.
;; - <EVALUATE_EXPRESSION>, which is also LET: it reads each operand with <READ_OPERAND> onto the argument stack, and
;;   runs each operator, through <OPERATOR_ROUTINES>, once the operators after it have lower precedence.
;;
;; Maintained by hand; assembles byte-identically to the cartridge.

; ---------------------------------------------------------------------------------------------------------------------
; The memory mover
; ---------------------------------------------------------------------------------------------------------------------

;; Opens space at the start of one of the program's tables, moving it and every table above it up.
;;
;; The tables from the one whose pointer is at X up to the run-time stack move up by the space's size, and each of
;; their pointers, X's to BASIC_MEMTOP, with them; the space is left where the table began, its bytes unchanged.
;; APPMHI follows BASIC_MEMTOP, so that the OS keeps a new screen above BASIC's memory. The bytes move from the top
;; down, a page at a time, as they move up over themselves.
;; In: Y = the space's size (OPEN_SPACE), X = the address of the table's pointer, from VNTP to BASIC_MEMTOP
;; Out: NEW_SPACE = the space, the table's old start, X = 0, Y = 0
;; Uses: A, SPACE_SIZE, MOVE_LENGTH, MOVE_FROM, MOVE_TO, APPMHI, VNTP..BASIC_MEMTOP+1 (the pointers from X's)
;; Errors: ERR_MEMORY = error 2, memory insufficient, when BASIC_MEMTOP would reach MEMTOP
;; Entry: OPEN_SPACE_LONG = a size of 256 bytes or more, its high byte in A and its low byte in Y
;; See: <CLOSE_SPACE>
OPEN_SPACE:
    lda #$00
OPEN_SPACE_LONG:
    sty SPACE_SIZE
    sta SPACE_SIZE+1
.if VERSION = VERSION_A             ; rev. A adds the size from SPACE_SIZE, the later revisions from Y
    sec                             ; is BASIC_MEMTOP + the size + 1 at most MEMTOP?
    lda BASIC_MEMTOP
    adc SPACE_SIZE
.else
    tya                             ; is BASIC_MEMTOP + the size + 1 at most MEMTOP?
    sec
    adc BASIC_MEMTOP
.endif
    tay
    lda BASIC_MEMTOP+1
    adc SPACE_SIZE+1
    cmp MEMTOP+1
    bcc OPEN_SPACE_FITS
    bne OPEN_SPACE_NO_MEMORY
    cpy MEMTOP
    bcc OPEN_SPACE_FITS
    beq OPEN_SPACE_FITS
OPEN_SPACE_NO_MEMORY:
    jmp MEMORY_INSUFFICIENT_ERROR   ; error 2
OPEN_SPACE_FITS:
    sec                             ; MOVE_LENGTH = the bytes from the table to BASIC_MEMTOP
    lda BASIC_MEMTOP
    sbc 0,x
    sta MOVE_LENGTH
    lda BASIC_MEMTOP+1
    sbc 1,x
    sta MOVE_LENGTH+1
    clc                             ; MOVE_FROM = the table, in the page of its last bytes
    adc 1,x
    sta MOVE_FROM+1
    lda 0,x
    sta MOVE_FROM
    sta NEW_SPACE
    adc SPACE_SIZE                  ; MOVE_TO = MOVE_FROM + the size
    sta MOVE_TO
    lda 1,x
    sta NEW_SPACE+1
    adc SPACE_SIZE+1
    adc MOVE_LENGTH+1
    sta MOVE_TO+1
OPEN_SPACE_POINTERS:
    lda 0,x                         ; move each pointer up, carry clear
    adc SPACE_SIZE
    sta 0,x
    lda 1,x
    adc SPACE_SIZE+1
    sta 1,x
    inx
    inx
    cpx #BASIC_MEMTOP+2
    bcc OPEN_SPACE_POINTERS
    sta APPMHI+1                    ; A = BASIC_MEMTOP's new high byte
    lda BASIC_MEMTOP
    sta APPMHI
    ldx MOVE_LENGTH+1               ; X = the pages, counting the part page
    inx
    ldy MOVE_LENGTH
    bne OPEN_SPACE_NEXT             ; the part page first, from its last byte
.if VERSION = VERSION_A
    beq OPEN_SPACE_PAGE_DONE        ; always
.elseif VERSION = VERSION_B
    ; Rev. B goes straight on to the whole pages without lowering the pointers, so with no part page it copies the
    ; page past the data and leaves the lowest page where it was; rev. C fixed it.
    dex
    bne OPEN_SPACE_NEXT
    rts
.else
    nop
    beq OPEN_SPACE_PAGE_DONE        ; always
    nop                             ; never reached
.endif
OPEN_SPACE_PAGE:
    dey                             ; a whole page, from Y = $FF, a page lower
    dec MOVE_FROM+1
    dec MOVE_TO+1
OPEN_SPACE_COPY:
    lda (MOVE_FROM),y
    sta (MOVE_TO),y
OPEN_SPACE_NEXT:
    dey
    bne OPEN_SPACE_COPY
    lda (MOVE_FROM),y               ; the page's first byte
    sta (MOVE_TO),y
OPEN_SPACE_PAGE_DONE:
    dex
    bne OPEN_SPACE_PAGE
    rts

;; Closes space just below one of the program's tables, moving it and every table above it down.
;;
;; The tables from the one whose pointer is at X up to the run-time stack move down by the space's size, over the
;; space's bytes, which are the last of the table below; their pointers, X's to BASIC_MEMTOP, move with them, and
;; APPMHI follows BASIC_MEMTOP.
;; In: A = the space's size (CLOSE_SPACE_A, which rev. A lacks), X = the address of the table's pointer, from VNTP to
;;   BASIC_MEMTOP
;; Out: X = 0, Y = 0
;; Uses: A, SPACE_SIZE, MOVE_LENGTH, MOVE_FROM, MOVE_TO, APPMHI, VNTP..BASIC_MEMTOP+1 (the pointers from X's)
;; Entry:
;;   CLOSE_SPACE = Y = the size
;;   CLOSE_SPACE_LONG = a size of 256 bytes or more, its high byte in A and its low byte in Y
;; See: <OPEN_SPACE>, <MOVE_MEMORY_DOWN>
.if VERSION >= VERSION_B            ; rev. A has no CLOSE_SPACE_A
CLOSE_SPACE_A:
    tay
.endif
CLOSE_SPACE:
    lda #$00
CLOSE_SPACE_LONG:
    sty SPACE_SIZE
    sta SPACE_SIZE+1
    sec                             ; MOVE_LENGTH = the bytes from the table to BASIC_MEMTOP, its low byte negated
    lda BASIC_MEMTOP
    sbc 0,x
    eor #$FF
    tay
    iny
    sty MOVE_LENGTH
    lda BASIC_MEMTOP+1
    sbc 1,x
    sta MOVE_LENGTH+1
    lda 0,x                         ; MOVE_FROM = the table less that negated byte
    sbc MOVE_LENGTH
    sta MOVE_FROM
    lda 1,x
    sbc #$00
    sta MOVE_FROM+1
    stx MOVE_TO                     ; keep X
CLOSE_SPACE_POINTERS:
    sec                             ; move each pointer down
    lda 0,x
    sbc SPACE_SIZE
    sta 0,x
    lda 1,x
    sbc SPACE_SIZE+1
    sta 1,x
    inx
    inx
    cpx #BASIC_MEMTOP+2
    bcc CLOSE_SPACE_POINTERS
    sta APPMHI+1                    ; A = BASIC_MEMTOP's new high byte
    lda BASIC_MEMTOP
    sta APPMHI
    ldx MOVE_TO                     ; MOVE_TO = the table's new place less the same byte
    lda 0,x
    sbc MOVE_LENGTH
    sta MOVE_TO
    lda 1,x
    sbc #$00
    sta MOVE_TO+1
;; Copies memory from the bottom up, which moves it down safely over itself.
;;
;; The length's low byte is given negated, and both addresses lowered by that negated byte (when it isn't 0), so that
;; the first part page is copied with Y counting up to 0 and each whole page after it with Y from 0.
;; In:
;;   MOVE_FROM = the source less the negated low byte
;;   MOVE_TO = the destination less the negated low byte
;;   MOVE_LENGTH = the length's low byte negated, MOVE_LENGTH+1 = its high byte
;; Out: X = 0, Y = 0
;; Uses: A, MOVE_FROM+1, MOVE_TO+1
MOVE_MEMORY_DOWN:
    ldx MOVE_LENGTH+1               ; X = the pages, counting the part page
    inx
    ldy MOVE_LENGTH
    bne MOVE_MEMORY_DOWN_LOOP
.if VERSION = VERSION_A
    ; Rev. A, with no part page, steps both addresses a page on before the first page, so it skips the first page
    ; and copies one past the end; rev. B copies from the first.
    beq MOVE_MEMORY_DOWN_NEXT       ; always
.else
    dex                             ; no part page
    bne MOVE_MEMORY_DOWN_LOOP
    rts                             ; nothing to copy
.endif
MOVE_MEMORY_DOWN_PAGE:
    inc MOVE_FROM+1
    inc MOVE_TO+1
MOVE_MEMORY_DOWN_LOOP:
    lda (MOVE_FROM),y
    sta (MOVE_TO),y
    iny
    bne MOVE_MEMORY_DOWN_LOOP
.if VERSION = VERSION_A             ; rev. A goes on here when there is no part page
MOVE_MEMORY_DOWN_NEXT:
.endif
    dex
    bne MOVE_MEMORY_DOWN_PAGE
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The execution loop
; ---------------------------------------------------------------------------------------------------------------------

;; Runs the program from the line at STMCUR, statement after statement and line after line.
;;
;; Before each statement BREAK is tested, and stops the program as STOP does. Each statement's routine is reached
;; through <STATEMENT_ROUTINES> by its token, with TOKEN_OFFSET at the token after it and NEXT_STATEMENT at the
;; statement after it, and returns here; a statement that goes elsewhere (GOTO, RUN, an error) changes STMCUR and
;; comes back through EXECUTE_LINE or leaves the loop. At the end of a line the next line runs, unless the next is
;; the immediate line, which ends the program as END does; at the end of the immediate line BASIC prints READY and
;; reads the next line.
;; In: STMCUR = the line
;; Entry: EXECUTE_NEXT_STATEMENT = from the statement at NEXT_STATEMENT, in the line at STMCUR, LINE_LENGTH set
;; See: <STATEMENT_ROUTINES>, <STATEMENT_STOP>, <STATEMENT_END>
EXECUTE_LINE:
    jsr START_LINE                  ; LINE_LENGTH, and NEXT_STATEMENT at the first statement
EXECUTE_NEXT_STATEMENT:
    jsr CHECK_BREAK
.if VERSION = VERSION_A
    bne EXECUTE_BREAK               ; rev. A's CHECK_BREAK gives nonzero for BREAK
.else
    beq EXECUTE_BREAK
.endif
    ldy NEXT_STATEMENT
    cpy LINE_LENGTH
    bcs EXECUTE_END_OF_LINE
    lda (STMCUR),y                  ; the offset of the statement after this one
    sta NEXT_STATEMENT
    tya                             ; (A is not used)
    iny
    lda (STMCUR),y                  ; the statement's token
    iny
    sty TOKEN_OFFSET
    jsr EXECUTE_STATEMENT
.if VERSION >= VERSION_B            ; rev. A has no spare byte here
    nop                             ; (a byte to spare)
.endif
    jmp EXECUTE_NEXT_STATEMENT

;; Runs a statement's routine by its token, pushing its address less 1 from <STATEMENT_ROUTINES> for an RTS.
;; In: A = the statement's token
;; Uses: A, X
EXECUTE_STATEMENT:
    asl A
    tax
    lda STATEMENT_ROUTINES,x
    pha
    lda STATEMENT_ROUTINES+1,x
    pha
    rts

EXECUTE_END_OF_LINE:
    ldy #LINE_NUMBER_OFFSET+1
    lda (STMCUR),y
    bmi EXECUTE_IMMEDIATE_DONE      ; the immediate line, $8000 or more
    lda LINE_LENGTH
    jsr ADVANCE_STMCUR
    jsr GET_LINE_NUMBER_HIGH
    bpl EXECUTE_LINE
    jmp STATEMENT_END               ; the program ran into the immediate line
EXECUTE_BREAK:
    jmp STATEMENT_STOP
EXECUTE_IMMEDIATE_DONE:
    jmp WARM_START_READY            ; READY, and the next line

; ---------------------------------------------------------------------------------------------------------------------
; Lines
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the line with the number LINE_NUMBER in the statement table, or the line after where it would be.
;;
;; The search starts at the program's first line; the immediate line, numbered $8000, ends it. STMCUR is kept in
;; STMCUR_SAVE first, so that a statement can go back to its own line when the search fails.
;; In: LINE_NUMBER = the line's number
;; Out: STMCUR = the line, or the first line with a greater number, carry = clear when found, STMCUR_SAVE = STMCUR
;;   before the search
;; Uses: A, Y
;; Keeps: X
FIND_LINE:
    lda STMCUR
    sta STMCUR_SAVE
    lda STMCUR+1
    sta STMCUR_SAVE+1
    lda STMTAB+1
    ldy STMTAB
    sta STMCUR+1
    sty STMCUR
FIND_LINE_LOOP:
    ldy #LINE_NUMBER_OFFSET+1
    lda (STMCUR),y
    cmp LINE_NUMBER+1
    bcc FIND_LINE_NEXT
    bne FIND_LINE_DONE              ; past it: carry set
    dey
    lda (STMCUR),y
    cmp LINE_NUMBER
    bcc FIND_LINE_NEXT
    bne FIND_LINE_DONE
    clc                             ; found
FIND_LINE_DONE:
    rts
FIND_LINE_NEXT:
    jsr GET_LINE_LENGTH
    jsr ADVANCE_STMCUR
    jmp FIND_LINE_LOOP

;; Adds A to STMCUR, as to step to the next line by the line's length.
;;
;; Rev. A's leaves Y = STMCUR's new low byte.
;; In: A = the bytes to step
;; Out: STMCUR = STMCUR + A
;; Uses: A
;; Keeps: X, Y
ADVANCE_STMCUR:
    clc
    adc STMCUR
    sta STMCUR
.if VERSION = VERSION_A             ; rev. A leaves the low byte in Y too
    tay
.endif
    lda STMCUR+1
    adc #$00
    sta STMCUR+1
    rts

;; Reads the length of the line at STMCUR.
;; Out: A = the line's length, Y = LINE_LENGTH_OFFSET
;; Keeps: X
GET_LINE_LENGTH:
    ldy #LINE_LENGTH_OFFSET
    lda (STMCUR),y
    rts

;; Reads the high byte of the number of the line at STMCUR, negative for the immediate line.
;; Out: A = the line number's high byte, negative = set for the immediate line, Y = 1
;; Keeps: X
GET_LINE_NUMBER_HIGH:
    ldy #LINE_NUMBER_OFFSET+1
    lda (STMCUR),y
.if VERSION = VERSION_A
    rts                             ; rev. A's own RTS
.endif
;; REM and DATA: do nothing.
;;
;; REM's remark and DATA's values are kept as typed to the end of the statement (a remark to the end of the line),
;; and the statement's offset of the next statement steps over them; READ finds DATA's values for itself.
;; Keeps: A, X, Y
STATEMENT_REM:
    rts

;; BYE: leaves BASIC for the OS's blackboard, the 400 and 800's Memo Pad (or the XL's self test).
;;
;; The sound is silenced and the IOCBs closed first.
;; See: <STATEMENT_DOS>
STATEMENT_BYE:
    jsr SILENCE_CLOSE_ALL           ; silence the sound and close every IOCB
    jmp BLKBDV

;; DOS: goes to the Disk Operating System through DOSVEC, after silencing the sound and closing every IOCB.
;;
;; Without DOS booted, DOSVEC holds the OS's default, and the computer goes to Memo Pad as for BYE.
;; See: <STATEMENT_BYE>
STATEMENT_DOS:
    jsr SILENCE_CLOSE_ALL           ; silence the sound and close every IOCB
    jmp (DOSVEC)

;; Tests whether BREAK has been pressed, and if so clears it.
;;
;; Rev. A's gives the other way round: zero = clear when BREAK was pressed, then A = $FF.
;; Out: zero = set when BREAK was pressed, then A = 0 and BRKKEY = $FF
;; Uses: A, Y
;; Keeps: X
CHECK_BREAK:
.if VERSION = VERSION_A             ; rev. A gives A = $FF, not zero, for BREAK
    ldy #$00
    lda BRKKEY                      ; 0 when BREAK was pressed
    bne CHECK_BREAK_DONE            ; A = Y = 0: not pressed
    ldy #$FF                        ; $FF again
    sty BRKKEY
CHECK_BREAK_DONE:
    tya
.else
    ldy BRKKEY                      ; 0 when BREAK was pressed
    bne CHECK_BREAK_DONE
    dec BRKKEY                      ; $FF again
    tya
CHECK_BREAK_DONE:
.endif
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The execution tables
; ---------------------------------------------------------------------------------------------------------------------

;; The statements' routines by token, from TOKEN_REM to TOKEN_ERROR: each the routine's address less 1, high byte
;; first, for <EXECUTE_STATEMENT> to push for an RTS.
;;
;; Several tokens share a routine: DATA REM's, GO TO GOTO's, ? PRINT's, the implied LET LET's and DIM COM's.
STATEMENT_ROUTINES:
    .dbyt STATEMENT_REM-1           ; TOKEN_REM
    .dbyt STATEMENT_REM-1           ; TOKEN_DATA
    .dbyt STATEMENT_INPUT-1         ; TOKEN_INPUT
    .dbyt STATEMENT_COLOR-1         ; TOKEN_COLOR
    .dbyt STATEMENT_LIST-1          ; TOKEN_LIST
    .dbyt STATEMENT_ENTER-1         ; TOKEN_ENTER
    .dbyt STATEMENT_LET-1           ; TOKEN_LET
    .dbyt STATEMENT_IF-1            ; TOKEN_IF
    .dbyt STATEMENT_FOR-1           ; TOKEN_FOR
    .dbyt STATEMENT_NEXT-1          ; TOKEN_NEXT
    .dbyt STATEMENT_GOTO-1          ; TOKEN_GOTO
    .dbyt STATEMENT_GOTO-1          ; TOKEN_GO_TO
    .dbyt STATEMENT_GOSUB-1         ; TOKEN_GOSUB
    .dbyt STATEMENT_TRAP-1          ; TOKEN_TRAP
    .dbyt STATEMENT_BYE-1           ; TOKEN_BYE
    .dbyt STATEMENT_CONT-1          ; TOKEN_CONT
    .dbyt STATEMENT_COM-1           ; TOKEN_COM
    .dbyt STATEMENT_CLOSE-1         ; TOKEN_CLOSE
    .dbyt STATEMENT_CLR-1           ; TOKEN_CLR
    .dbyt STATEMENT_DEG-1           ; TOKEN_DEG
    .dbyt STATEMENT_DIM-1           ; TOKEN_DIM
    .dbyt STATEMENT_END-1           ; TOKEN_END
    .dbyt STATEMENT_NEW-1           ; TOKEN_NEW
    .dbyt STATEMENT_OPEN-1          ; TOKEN_OPEN
    .dbyt STATEMENT_LOAD-1          ; TOKEN_LOAD
    .dbyt STATEMENT_SAVE-1          ; TOKEN_SAVE
    .dbyt STATEMENT_STATUS-1        ; TOKEN_STATUS
    .dbyt STATEMENT_NOTE-1          ; TOKEN_NOTE
    .dbyt STATEMENT_POINT-1         ; TOKEN_POINT
    .dbyt STATEMENT_XIO-1           ; TOKEN_XIO
    .dbyt STATEMENT_ON-1            ; TOKEN_ON
    .dbyt STATEMENT_POKE-1          ; TOKEN_POKE
    .dbyt STATEMENT_PRINT-1         ; TOKEN_PRINT
    .dbyt STATEMENT_RAD-1           ; TOKEN_RAD
    .dbyt STATEMENT_READ-1          ; TOKEN_READ
    .dbyt STATEMENT_RESTORE-1       ; TOKEN_RESTORE
    .dbyt STATEMENT_RETURN-1        ; TOKEN_RETURN
    .dbyt STATEMENT_RUN-1           ; TOKEN_RUN
    .dbyt STATEMENT_STOP-1          ; TOKEN_STOP
    .dbyt STATEMENT_POP-1           ; TOKEN_POP
    .dbyt STATEMENT_PRINT-1         ; TOKEN_QUESTION
    .dbyt STATEMENT_GET-1           ; TOKEN_GET
    .dbyt STATEMENT_PUT-1           ; TOKEN_PUT
    .dbyt STATEMENT_GRAPHICS-1      ; TOKEN_GRAPHICS
    .dbyt STATEMENT_PLOT-1          ; TOKEN_PLOT
    .dbyt STATEMENT_POSITION-1      ; TOKEN_POSITION
    .dbyt STATEMENT_DOS-1           ; TOKEN_DOS
    .dbyt STATEMENT_DRAWTO-1        ; TOKEN_DRAWTO
    .dbyt STATEMENT_SETCOLOR-1      ; TOKEN_SETCOLOR
    .dbyt STATEMENT_LOCATE-1        ; TOKEN_LOCATE
    .dbyt STATEMENT_SOUND-1         ; TOKEN_SOUND
    .dbyt STATEMENT_LPRINT-1        ; TOKEN_LPRINT
    .dbyt STATEMENT_CSAVE-1         ; TOKEN_CSAVE
    .dbyt STATEMENT_CLOAD-1         ; TOKEN_CLOAD
    .dbyt STATEMENT_LET-1           ; TOKEN_IMPLIED_LET
    .dbyt STATEMENT_ERROR-1         ; TOKEN_ERROR
    .assert * - STATEMENT_ROUTINES = 2 * STATEMENT_COUNT, "STATEMENT_ROUTINES has a routine for each statement."

;; The operators' and functions' routines by token, from FIRST_EXECUTED (OP_LE) to FN_STRIG: each the routine's
;; address less 1, high byte first, for <EXECUTE_OPERATOR> to push for an RTS.
;;
;; The string comparisons share the number comparisons' routines, which compare either kind; the function's ( shares
;; ), DIM's string ( shares its array (, and unary + shares (, which does nothing.
OPERATOR_ROUTINES:
    .dbyt OPERATOR_LE-1             ; OP_LE
    .dbyt OPERATOR_NE-1             ; OP_NE
    .dbyt OPERATOR_GE-1             ; OP_GE
    .dbyt OPERATOR_LT-1             ; OP_LT
    .dbyt OPERATOR_GT-1             ; OP_GT
    .dbyt OPERATOR_EQ-1             ; OP_EQ
    .dbyt OPERATOR_POWER-1          ; OP_POWER
    .dbyt OPERATOR_MULTIPLY-1       ; OP_MULTIPLY
    .dbyt OPERATOR_ADD-1            ; OP_ADD
    .dbyt OPERATOR_SUBTRACT-1       ; OP_SUBTRACT
    .dbyt OPERATOR_DIVIDE-1         ; OP_DIVIDE
    .dbyt OPERATOR_NOT-1            ; OP_NOT
    .dbyt OPERATOR_OR-1             ; OP_OR
    .dbyt OPERATOR_AND-1            ; OP_AND
    .dbyt OPERATOR_OPEN_PAREN-1     ; OP_OPEN_PAREN
    .dbyt OPERATOR_CLOSE_PAREN-1    ; OP_CLOSE_PAREN
    .dbyt OPERATOR_ASSIGN_NUMBER-1  ; OP_ASSIGN_NUMBER
    .dbyt OPERATOR_ASSIGN_STRING-1  ; OP_ASSIGN_STRING
    .dbyt OPERATOR_LE-1             ; OP_STRING_LE
    .dbyt OPERATOR_NE-1             ; OP_STRING_NE
    .dbyt OPERATOR_GE-1             ; OP_STRING_GE
    .dbyt OPERATOR_LT-1             ; OP_STRING_LT
    .dbyt OPERATOR_GT-1             ; OP_STRING_GT
    .dbyt OPERATOR_EQ-1             ; OP_STRING_EQ
    .dbyt OPERATOR_PLUS-1           ; OP_PLUS
    .dbyt OPERATOR_MINUS-1          ; OP_MINUS
    .dbyt OPERATOR_STRING_PAREN-1   ; OP_STRING_PAREN
    .dbyt OPERATOR_ARRAY_PAREN-1    ; OP_ARRAY_PAREN
    .dbyt OPERATOR_DIM_ARRAY_PAREN-1    ; OP_DIM_ARRAY_PAREN
    .dbyt OPERATOR_CLOSE_PAREN-1    ; OP_FUNCTION_PAREN
    .dbyt OPERATOR_DIM_ARRAY_PAREN-1    ; OP_DIM_STRING_PAREN
    .dbyt OPERATOR_ARRAY_COMMA-1    ; OP_ARRAY_COMMA
    .dbyt FUNCTION_STR-1            ; FN_STR
    .dbyt FUNCTION_CHR-1            ; FN_CHR
    .dbyt FUNCTION_USR-1            ; FN_USR
    .dbyt FUNCTION_ASC-1            ; FN_ASC
    .dbyt FUNCTION_VAL-1            ; FN_VAL
    .dbyt FUNCTION_LEN-1            ; FN_LEN
    .dbyt FUNCTION_ADR-1            ; FN_ADR
    .dbyt FUNCTION_ATN-1            ; FN_ATN
    .dbyt FUNCTION_COS-1            ; FN_COS
    .dbyt FUNCTION_PEEK-1           ; FN_PEEK
    .dbyt FUNCTION_SIN-1            ; FN_SIN
    .dbyt FUNCTION_RND-1            ; FN_RND
    .dbyt FUNCTION_FRE-1            ; FN_FRE
    .dbyt FUNCTION_EXP-1            ; FN_EXP
    .dbyt FUNCTION_LOG-1            ; FN_LOG
    .dbyt FUNCTION_CLOG-1           ; FN_CLOG
    .dbyt FUNCTION_SQR-1            ; FN_SQR
    .dbyt FUNCTION_SGN-1            ; FN_SGN
    .dbyt FUNCTION_ABS-1            ; FN_ABS
    .dbyt FUNCTION_INT-1            ; FN_INT
    .dbyt FUNCTION_PADDLE-1         ; FN_PADDLE
    .dbyt FUNCTION_STICK-1          ; FN_STICK
    .dbyt FUNCTION_PTRIG-1          ; FN_PTRIG
    .dbyt FUNCTION_STRIG-1          ; FN_STRIG
    .assert * - OPERATOR_ROUTINES = 2 * (FN_STRIG + 1 - FIRST_EXECUTED), "OPERATOR_ROUTINES has a routine per token."

; ---------------------------------------------------------------------------------------------------------------------
; The expression evaluator
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates the expression at TOKEN_OFFSET in the line at STMCUR, leaving its value on the argument stack.
;;
;; Operands go onto the argument stack as they are read, eight bytes each, from LOMEM up. Each operator waits on the
;; operator stack, from LOMEM+$FF down, until the next operator comes: then each waiting operator whose precedence on
;; the stack (the low nibble of its entry in the precedence table) is at least the coming one's (the high nibble) is
;; run, from the top, and the coming one is pushed. A token that can't continue an expression (a comma, :, the end
;; of the line, THEN...) has precedence 0, and ends the expression once the stack is down to OP_SENTINEL.
;; Parentheses work by precedence too: ( comes onto the stack over anything and lets everything wait over it; ) runs
;; everything down to the (, waits itself, and when it runs, it runs the ( (or the function's or array's) under it.
;; In: TOKEN_OFFSET = the expression's first token
;; Out: OPERATOR_TOKEN = the token that ended the expression, TOKEN_OFFSET = just past it, ARGUMENT_INDEX = the
;;   value's entry on the argument stack
;; Errors: ERR_STACK_OVERFLOW = error 10, argument stack overflow, and the errors of the operators and functions
;; See: <OPERATOR_ROUTINES>, <READ_OPERAND>, <STATEMENT_LET>
EVALUATE_EXPRESSION:
;; LET (and an assignment without it): sets a variable to a value: LET X = 2, A$ = "TEXT", or X(I) = 1.
;;
;; The statement is an expression whose last operator is the assignment's =, OP_ASSIGN_NUMBER or OP_ASSIGN_STRING:
;; the variable is its first operand and the = runs last, storing the value.
;; Errors: ERR_STACK_OVERFLOW = error 10, argument stack overflow, and the errors of the operators and functions
;; See: <EVALUATE_EXPRESSION>
STATEMENT_LET:
    jsr INIT_EXPRESSION
EVALUATE_OPERAND:
    jsr READ_OPERAND
    bcs EVALUATE_OPERATOR
    jsr PUSH_VALUE                  ; push it on the argument stack
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp EVALUATE_OPERAND
.else
    bmi EVALUATE_OPERAND            ; always: the push ends with X = $FF
.endif
EVALUATE_OPERATOR:
    sta OPERATOR_TOKEN
    tax
    lda PRECEDENCE_BASE,x           ; its precedence coming to the stack, from the high nibble
    lsr A
    lsr A
    lsr A
    lsr A
    sta INCOMING_PRECEDENCE
EVALUATE_REDUCE:
    ldy OPERATOR_INDEX
    lda (LOMEM),y                   ; the operator waiting on top of the stack
    tax
    lda PRECEDENCE_BASE,x           ; its precedence on the stack, from the low nibble
    and #$0F
    cmp INCOMING_PRECEDENCE
    bcc EVALUATE_PUSH_OPERATOR
    tax
    beq EVALUATE_DONE               ; both 0: only OP_SENTINEL waits, and the expression has ended
;; Pops the operator on top of the operator stack and runs it, then goes on with the expression's operators.
;;
;; ) comes here to run the parenthesis under it, dropping its own return to the expression evaluator.
;; In: Y = OPERATOR_INDEX
EXECUTE_STACKED_OPERATOR:
    lda (LOMEM),y
    inc OPERATOR_INDEX
    jsr EXECUTE_OPERATOR
    jmp EVALUATE_REDUCE
EVALUATE_PUSH_OPERATOR:
    lda OPERATOR_TOKEN
    dey
    sta (LOMEM),y
    sty OPERATOR_INDEX
    jmp EVALUATE_OPERAND
.if VERSION = VERSION_A
;; ( in an expression: does nothing.
;;
;; A parenthesis has done its work by its precedence by the time it runs. Rev. A keeps it here, apart from unary +.
;; Keeps: A, X, Y
OPERATOR_OPEN_PAREN:
EVALUATE_DONE:
    rts
.endif

;; Runs an operator's or a function's routine by its token, pushing its address less 1 from <OPERATOR_ROUTINES> for
;; an RTS.
;; In: A = the token, from FIRST_EXECUTED to FN_STRIG
;; Uses: A, X
EXECUTE_OPERATOR:
    sec
    sbc #FIRST_EXECUTED
    asl A
    tax
    lda OPERATOR_ROUTINES,x
    pha
    lda OPERATOR_ROUTINES+1,x
    pha
    rts

;; Empties the expression's stacks, for a new expression: OP_SENTINEL alone on the operator stack and nothing on the
;; argument stack, with COMMA_COUNT and ASSIGN_FLAGS clear.
;; Out: Y = 0, A = OP_SENTINEL
;; Keeps: X
INIT_EXPRESSION:
    ldy #$FF
    lda #OP_SENTINEL
    sta (LOMEM),y
    sty OPERATOR_INDEX
    iny
    sty COMMA_COUNT
    sty ARGUMENT_INDEX
    sty ASSIGN_FLAGS
.if VERSION >= VERSION_B
;; ( in an expression, and unary +: do nothing.
;;
;; A parenthesis has done its work by its precedence by the time it runs, and + leaves its operand as it is.
;; Keeps: A, X, Y
OPERATOR_OPEN_PAREN:
OPERATOR_PLUS:
EVALUATE_DONE:
.endif
    rts

;; Reads the expression's next token: an operand, as a value in VALUE_TYPE..FR0+5, or an operator.
;;
;; A numeric constant is a number; a string constant becomes a DIMensioned string at its absolute address in the
;; line, its length and size the same; a variable's value is copied from its entry in the variable value table.
;; In: TOKEN_OFFSET = the token
;; Out:
;;   carry = clear for an operand, set for an operator
;;   VALUE_TYPE..FR0+5 = the operand's value, TOKEN_OFFSET = past the operand
;;   A = the operator's token, TOKEN_OFFSET = past the operator
;; Uses: X, Y, VARIABLE_ENTRY
;; See: <READ_NUMBER_CONSTANT>, <MAKE_STRING_VALUE>, <READ_VARIABLE>
READ_OPERAND:
    ldy TOKEN_OFFSET
    inc TOKEN_OFFSET
    lda (STMCUR),y
    bmi READ_VARIABLE
    cmp #TOKEN_STRING
    bcc READ_NUMBER_CONSTANT        ; TOKEN_NUMBER
    beq READ_OPERAND_STRING
    rts                             ; an operator: carry set
;; Reads the numeric constant whose token is at Y in the line at STMCUR into FR0, as a number value.
;; In: Y = the TOKEN_NUMBER token's offset
;; Out: VALUE_TYPE = 0, VALUE_NUMBER = 0, FR0 = the number, TOKEN_OFFSET = Y = past it, carry = clear
;; Uses: A, X
READ_NUMBER_CONSTANT:
    ldx #$00
READ_NUMBER_CONSTANT_LOOP:
    iny
    lda (STMCUR),y
    sta FR0,x
    inx
    cpx #FP_SIZE
    bcc READ_NUMBER_CONSTANT_LOOP
    iny
    lda #$00                        ; a number, of no variable
    tax
    beq READ_OPERAND_DONE           ; always
READ_OPERAND_STRING:
    iny
    lda (STMCUR),y                  ; its length
    ldx #STMCUR
;; Makes a string value of the characters after Y at the pointer at X: a DIMensioned string at its absolute address,
;; its length and its size both A.
;; In: A = the string's length, X = the address of a zero page pointer, Y = the string's offset from it, less 1
;; Out: VALUE_TYPE..FR0+5 = the string's value, VALUE_NUMBER = 0, TOKEN_OFFSET = Y = past the string,
;;   carry = clear
;; Uses: A, X
MAKE_STRING_VALUE:
    sta FR0+2                       ; the length
    sta FR0+4                       ; the size
    iny
    tya                             ; FR0 = the pointer + Y, the string's address
    clc
    adc 0,x
    sta FR0
    lda #$00
    sta FR0+3
    sta FR0+5
    adc 1,x
    sta FR0+1
    tya                             ; past the string
    adc FR0+2
    tay
    ldx #$00
    lda #VALUE_STRING | VALUE_ABSOLUTE | VALUE_DIMENSIONED
READ_OPERAND_DONE:
    sta VALUE_TYPE
    stx VALUE_NUMBER
    sty TOKEN_OFFSET
    clc
    rts
;; Reads a variable's value from the variable value table into VALUE_TYPE..FR0+5.
;; In: A = the variable's token or number (bit 7 is ignored)
;; Out: VALUE_TYPE..FR0+5 = its entry, VARIABLE_ENTRY = the entry's address, Y = VALUE_SIZE, carry = clear
;; Uses: A
;; Keeps: X
READ_VARIABLE:
    jsr FIND_VARIABLE_ENTRY         ; VARIABLE_ENTRY = its entry; Y = 0
READ_VARIABLE_LOOP:
    lda (VARIABLE_ENTRY),y
    sta VALUE_TYPE,y
    iny
    cpy #VALUE_SIZE
    bcc READ_VARIABLE_LOOP
    clc
    rts
