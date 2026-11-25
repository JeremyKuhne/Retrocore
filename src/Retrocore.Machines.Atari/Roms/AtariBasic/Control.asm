;; CONTROL ($B6F9-$B909)
;;
;; The statements that steer a running program, and the run-time stack they keep. Maintained by hand; assembles
;; byte-identically to the cartridge.
;;
;; - <PUSH_GOSUB> puts a GOSUB entry on the run-time stack, for GOSUB, ON ... GOSUB, LIST and READ.
;; - <STATEMENT_NEXT>, <STATEMENT_RUN>, <STATEMENT_CLR>, <STATEMENT_IF>, <STATEMENT_END>, <STATEMENT_STOP>,
;;   <STATEMENT_CONT>, <STATEMENT_TRAP> and <STATEMENT_ON>.
;; - <START_LINE_NUMBER> and <START_LINE> set up a line's first statement to run.
;; - The run-time stack, from RUNSTK up to BASIC_MEMTOP: <FIND_FOR_ENTRY>, <STATEMENT_POP> (which pops an entry for
;;   NEXT and RETURN too), <PUSH_RUNSTACK>, <COPY_TO_RUNSTACK> and <COPY_FROM_RUNSTACK>.
;; - Clearing: <EMPTY_RUNSTACK>, <CLEAR_VARIABLES>, <RESET_RUN_STATE>; and <AT_STATEMENT_END>, which asks whether a
;;   statement has more tokens.
;;
;; A run-time stack entry is a header of four bytes: the token (0 for a GOSUB entry, the variable's token for a
;; FOR entry), the line number of the statement that pushed it, and the offset of that statement's token in its
;; line. A FOR entry has its limit and its step, six bytes each, below the header.

; ---------------------------------------------------------------------------------------------------------------------
; GOSUB entries
; ---------------------------------------------------------------------------------------------------------------------

;; Pushes a GOSUB entry for the statement being run, so that RETURN can come back to it.
;;
;; GOSUB, LIST and READ push one; RETURN pops it and goes back to the statement whose token the entry holds.
;; In: TOKEN_OFFSET = just past the statement's token
;; Out: RUNSTACK_ENTRY = the new entry
;; Uses: A, X, Y, STATEMENT_OFFSET
;; Errors: 2 (ERR_MEMORY) when the run-time stack meets MEMTOP
;; Entry: PUSH_GOSUB_SAVED = with STATEMENT_OFFSET already set
;; See: <STATEMENT_POP>, <STATEMENT_RETURN>
PUSH_GOSUB:
    jsr SAVE_STATEMENT_OFFSET
PUSH_GOSUB_SAVED:
    lda #RUNSTACK_GOSUB
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp PUSH_RUNSTACK_HEADER        ; FOR's push of the header
.else
    beq PUSH_RUNSTACK_HEADER        ; always: FOR's push of the header
.endif

; ---------------------------------------------------------------------------------------------------------------------
; NEXT
; ---------------------------------------------------------------------------------------------------------------------

;; NEXT: adds a FOR loop's step to its variable, and goes back to just after the FOR while the limit isn't passed.
;;
;; NEXT var pops the run-time stack until it finds var's FOR entry, dropping the entries of inner loops above it.
;; The step is added to the variable; with a positive step (or 0) the loop goes on while the variable is at most
;; the limit, with a negative step while it is at least the limit. To go on, the entry is pushed back (its bytes are
;; still there) and the program goes on from the statement after the FOR, which must still be a FOR there. When the
;; loop ends, the entry stays popped and the program goes on after NEXT.
;; In: TOKEN_OFFSET = NEXT's variable's token
;; Errors: 11 (ERR_FP_OVERFLOW), 13 (ERR_NO_FOR) when the stack runs out or a GOSUB entry comes first,
;;   15 (ERR_LINE_DELETED) when the FOR's line is gone or no longer holds the FOR
;; See: <STATEMENT_FOR>, <FIND_FOR_ENTRY>
STATEMENT_NEXT:
    ldy TOKEN_OFFSET
    lda (STMCUR),y
    sta FOR_VARIABLE
NEXT_FIND:
    jsr STATEMENT_POP
    bcs NEXT_NO_FOR                 ; the stack is empty
    beq NEXT_NO_FOR                 ; a GOSUB entry
    cmp FOR_VARIABLE
    bne NEXT_FIND                   ; an inner loop's: drop it
    ldy #FOR_STEP
    jsr COPY_FROM_RUNSTACK          ; FR1 = the step
    lda FR1
    pha                             ; the step's sign, in bit 7
    lda FOR_VARIABLE
    jsr READ_VARIABLE               ; FR0 = the variable
    jsr CHECKED_FADD                ; plus the step
    jsr STORE_VARIABLE              ; stored back
    ldy #FOR_LIMIT
    jsr COPY_FROM_RUNSTACK          ; FR1 = the limit
    pla
    bpl NEXT_UP
    jsr SUBTRACT_TO_COMPARE         ; A = the variable less the limit, its sign in bit 7
    bpl NEXT_LOOP                   ; counting down, and not below the limit
    rts
NEXT_UP:
    jsr SUBTRACT_TO_COMPARE
    beq NEXT_LOOP                   ; at the limit
    bmi NEXT_LOOP                   ; below it
NEXT_DONE:
    rts
NEXT_LOOP:
    lda #RUNSTACK_HEADER+FOR_VALUES
    jsr PUSH_RUNSTACK               ; the entry back, as it was
    jsr RETURN_TO_ENTRY             ; to the FOR's line; A = the token there
    cmp #TOKEN_FOR
.if VERSION = VERSION_A             ; rev. A branches to the error and returns, the later revisions the other way round
    bne RETURN_LINE_DELETED         ; error 15
    rts
.else
    beq NEXT_DONE
    jmp RETURN_LINE_DELETED         ; error 15
.endif
NEXT_NO_FOR:
    jsr NO_MATCHING_FOR_ERROR       ; error 13; doesn't return

.if VERSION = VERSION_A
; ---------------------------------------------------------------------------------------------------------------------
; RETURN
; ---------------------------------------------------------------------------------------------------------------------

; Rev. A keeps RETURN here, after NEXT; the later revisions keep it among the I/O routines, in another order.

;; RETURN: goes back to the statement after the GOSUB that called the subroutine.
;;
;; RETURN pops the run-time stack down to the first GOSUB entry, dropping the FOR entries of loops left inside the
;; subroutine, and goes on from the statement after the one that pushed it: a GOSUB or ON ... GOSUB, or LIST or READ,
;; which push a GOSUB entry while they search the program and come back through RETURN when done.
;; Errors: 16 (ERR_RETURN) when the stack has no GOSUB entry, 15 (ERR_LINE_DELETED) when the GOSUB's line is gone or
;;   no longer holds a GOSUB, ON, LIST or READ at the entry's place
;; See: <STATEMENT_POP>, <RETURN_TO_ENTRY>
STATEMENT_RETURN:
    jsr STATEMENT_POP
    bcs RETURN_NO_GOSUB             ; the stack is empty
    bne STATEMENT_RETURN            ; a FOR entry: drop it
    jsr RETURN_TO_ENTRY
    cmp #TOKEN_GOSUB
    beq RETURN_DONE
    cmp #TOKEN_ON
    beq RETURN_DONE
    cmp #TOKEN_LIST
    beq RETURN_DONE
    cmp #TOKEN_READ
    bne RETURN_LINE_DELETED
RETURN_DONE:
    rts
RETURN_NO_GOSUB:
    jsr RETURN_ERROR                ; error 16
;; Finds the statement that pushed the run-time stack entry just popped, to go on from the one after it.
;;
;; The next statement's offset comes from the byte before the statement's token. The caller checks the token.
;; In: LINE_NUMBER = the entry's line, RETURN_OFFSET = the offset of the statement's token in it
;; Out: STMCUR = the line, LINE_LENGTH = its length, NEXT_STATEMENT = the offset of the statement after,
;;   A = the statement's token, Y = RETURN_OFFSET
;; Uses: X, STMCUR_SAVE
;; Errors: 15 (ERR_LINE_DELETED) when the line is gone
RETURN_TO_ENTRY:
    jsr START_LINE_NUMBER
    bcs RETURN_LINE_DELETED         ; no such line
    ldy RETURN_OFFSET
    dey
    lda (STMCUR),y                  ; the offset of the statement after
    sta NEXT_STATEMENT
    iny
    lda (STMCUR),y                  ; the statement's token
    rts
;; Raises error 15 (ERR_LINE_DELETED), with STMCUR back on the line being run, for RETURN and NEXT.
;; Errors: 15 (ERR_LINE_DELETED)
RETURN_LINE_DELETED:
    jsr RESTORE_STMCUR
    jsr LINE_DELETED_ERROR          ; error 15
.endif

; ---------------------------------------------------------------------------------------------------------------------
; RUN and CLR
; ---------------------------------------------------------------------------------------------------------------------

;; RUN: runs the program from its first line, after loading it when a file is named.
;;
;; RUN "D:NAME" loads the program as LOAD does and then runs it. The run state is reset first (DATA, TRAP, the
;; trigonometry in radians, the sound off, IOCBs 1-7 closed), and the variables are cleared as CLR clears them. With
;; no program, it goes back to READY.
;; In: TOKEN_OFFSET = just past RUN's token
;; Errors: those of LOAD (<LOAD_AND_RUN>)
;; See: <STATEMENT_CLR>, <RESET_RUN_STATE>
STATEMENT_RUN:
    jsr AT_STATEMENT_END
    bcs RUN_PROGRAM                 ; no file name
    jsr LOAD_AND_RUN                ; load it, and come back here
RUN_PROGRAM:
.if VERSION >= VERSION_B
    nop                             ; an instruction that does nothing (not in rev. A)
.endif
    lda #$00
    sta LINE_NUMBER
    sta LINE_NUMBER+1
    jsr START_LINE_NUMBER           ; line 0 or the first after it
    jsr GET_LINE_NUMBER_HIGH
    bmi RUN_READY                   ; that's the immediate line: there is no program
    jsr RESET_RUN_STATE
;; CLR: clears every variable, frees the strings and arrays, and empties the run-time stack.
;;
;; Numbers become 0, and strings and arrays lose their DIMensions, so they must be DIMensioned again. READ starts
;; again from the program's first DATA.
;; Uses: A, X, Y, ZTEMP1
;; See: <CLEAR_VARIABLES>, <EMPTY_RUNSTACK>
STATEMENT_CLR:
    jsr CLEAR_VARIABLES
    jsr EMPTY_RUNSTACK
    lda #$00
    sta DATA_LINE
    sta DATA_LINE+1
    sta DATA_ELEMENT
    rts

;; Goes back to READY, closing the IOCBs, for RUN with no program and CONT with nothing to continue.
RUN_READY:
    jmp WARM_START_CLOSE

; ---------------------------------------------------------------------------------------------------------------------
; IF, END, STOP and CONT
; ---------------------------------------------------------------------------------------------------------------------

;; IF: runs the rest of the line, or goes to a line, when an expression isn't 0.
;;
;; IF aexp THEN statements runs the statements after THEN when aexp isn't 0; IF aexp THEN lineno goes to the line.
;; When aexp is 0, the rest of the line is skipped, whatever follows THEN.
;; In: TOKEN_OFFSET = the expression's first token
;; Errors: those of the expression, and of GOTO (<STATEMENT_GOTO>) for a line number
STATEMENT_IF:
    jsr EVALUATE_VALUE              ; FR0 = the condition
    lda FR0+1                       ; its first mantissa byte is 0 only for 0
    beq IF_FALSE
    jsr AT_STATEMENT_END
    bcs IF_DONE                     ; THEN ends the statement: go on with the next
    jmp STATEMENT_GOTO
.if VERSION = VERSION_A
IF_DONE:
    rts                             ; rev. A's own RTS
.endif
IF_FALSE:
    lda LINE_LENGTH
    sta NEXT_STATEMENT              ; the next statement is the next line's
.if VERSION >= VERSION_B            ; the later revisions share this RTS; rev. A has its own
IF_DONE:
.endif
    rts

;; END: stops the program, closing its files and turning off its sound, and goes back to READY.
;;
;; The line is kept in STOPLN, so CONT goes on from the next line.
;; See: <KEEP_STOP_LINE>
STATEMENT_END:
    jsr KEEP_STOP_LINE
    jmp WARM_START_CLOSE

;; STOP: stops the program with STOPPED AT LINE n, leaving its files open and its sound on, so CONT can go on.
;;
;; BREAK stops the program here too. In the immediate line, only STOPPED is printed.
;; See: <KEEP_STOP_LINE>, <STATEMENT_CONT>
STATEMENT_STOP:
    jsr KEEP_STOP_LINE
    jsr PRINT_EOL                   ; an EOL
    lda #<STOPPED_MESSAGE
    sta NAME_POINTER
    lda #>STOPPED_MESSAGE
    sta NAME_POINTER+1
    jsr LIST_PRINT_NAME
    jmp REPORT_AT_LINE              ; " AT LINE n", and back to the editor

;; Keeps the line being run in STOPLN, for CONT, and sends input and output back to the editor's IOCB 0.
;;
;; The immediate line isn't kept.
;; Out: STOPLN = the line number, unless STMCUR is the immediate line
;; Uses: A, Y, INPUT_IOCB, OUTPUT_IOCB
;; Entry: KEEP_STOP_LINE_IO = only sends input and output back to IOCB 0
KEEP_STOP_LINE:
    jsr GET_LINE_NUMBER_HIGH        ; A = the line number's high byte
    bmi KEEP_STOP_LINE_IO
    sta STOPLN+1
    dey
    lda (STMCUR),y
    sta STOPLN
KEEP_STOP_LINE_IO:
    jmp DEFAULT_IOCBS

.if VERSION = VERSION_A
;; "STOPPED ", which BASIC prints when STOP or BREAK stops the program, its last character with bit 7 set.
;;
;; Rev. A keeps it here, beside STOP; the later revisions keep it after the statement name table.
STOPPED_MESSAGE:
    NAME_TEXT "STOPPED "
.endif

;; CONT: goes on with the program from the line after the one where it stopped.
;;
;; The rest of the stopped line isn't run. When that line has been deleted, the line after it is taken as the
;; stopped line, and CONT goes on from the one after that. With no line after it, CONT goes back to READY. In a
;; program, CONT does nothing but send input and output back to IOCB 0.
;; In: STOPLN = the line where the program stopped
;; See: <STATEMENT_STOP>, <STATEMENT_END>
STATEMENT_CONT:
    jsr GET_LINE_NUMBER_HIGH
    bpl KEEP_STOP_LINE_IO           ; in a program
    lda STOPLN
    sta LINE_NUMBER
    lda STOPLN+1
    sta LINE_NUMBER+1
    jsr FIND_LINE                   ; that line, or the first after it
    jsr GET_LINE_NUMBER_HIGH
    bmi RUN_READY                   ; none: the immediate line
    jsr GET_LINE_LENGTH
    jsr ADVANCE_STMCUR              ; the next line
    jsr GET_LINE_NUMBER_HIGH
    bmi RUN_READY
    jmp START_LINE

; ---------------------------------------------------------------------------------------------------------------------
; TRAP and ON
; ---------------------------------------------------------------------------------------------------------------------

;; TRAP: sets the line that an error goes to.
;;
;; TRAP lineno sends the next error to that line, where PEEK(195) is its number; the trap is then cleared, so it is
;; set again with another TRAP. A line from 32768 up (TRAP 40000) turns the trap off.
;; In: TOKEN_OFFSET = the line number's expression
;; Out: TRAP_LINE = the line
;; Errors: 3 (ERR_VALUE) when it isn't from 0 to 65535
;; See: <HANDLE_ERROR>
STATEMENT_TRAP:
    jsr EVALUATE_UNSIGNED
    lda FR0
    sta TRAP_LINE
    lda FR0+1
    sta TRAP_LINE+1
    rts

;; ON: goes to, or calls, the line that a number picks from a list.
;;
;; ON aexp GOTO lineno,lineno... goes to the aexp'th line of the list, and ON aexp GOSUB... calls it as GOSUB does.
;; An aexp of 0, or more than the list holds, goes on with the next statement. Only the line numbers up to the one
;; picked are evaluated.
;; In: TOKEN_OFFSET = aexp's first token
;; Errors: 7 (ERR_NUMBER_TOO_BIG) when aexp or a line number is from 32768 to 65535; otherwise 3 (ERR_VALUE) when
;;   aexp isn't from 0 to 255 or a line number is negative or beyond 65535; 12 (ERR_LINE_NOT_FOUND); 2 (ERR_MEMORY)
;;   for the GOSUB entry
;; See: <STATEMENT_GOTO>, <STATEMENT_GOSUB>
STATEMENT_ON:
    jsr SAVE_STATEMENT_OFFSET
    jsr EVALUATE_BYTE               ; FR0 = aexp, 0-255
    lda FR0
    beq ON_DONE
    ldy TOKEN_OFFSET
    dey
    lda (STMCUR),y                  ; the token that ended aexp
    cmp #OP_GOTO
.if VERSION >= VERSION_B            ; rev. A keeps no flag for ON's end, as it never takes the GOSUB entry back
    php                             ; zero = GOTO
.endif
    beq ON_SET_COUNT
    jsr PUSH_GOSUB_SAVED
ON_SET_COUNT:
    lda FR0
    sta ON_COUNT
ON_SKIP:
    jsr EVALUATE_INTEGER            ; FR0 = the next line number
    dec ON_COUNT
    beq ON_GO
    jsr AT_STATEMENT_END
    bcc ON_SKIP
.if VERSION = VERSION_A
    ; Rev. A leaves ON ... GOSUB's entry on the run-time stack when the list runs out, a bug: a later RETURN comes
    ; back to the ON's line. Revs. B and C take it back.
    rts                             ; the list ran out
ON_GO:
    jmp GO_TO_FR0_LINE              ; go to the line in FR0
ON_DONE:
    rts
.else
    plp                             ; the list ran out
    beq ON_DONE
    jsr STATEMENT_POP               ; take GOSUB's entry back
ON_DONE:
    rts
ON_GO:
    plp
    jmp GO_TO_FR0_LINE              ; go to the line in FR0
.endif

; ---------------------------------------------------------------------------------------------------------------------
; Starting a line
; ---------------------------------------------------------------------------------------------------------------------

;; Finds a line by its number and sets it up to run from its first statement.
;; In: LINE_NUMBER = the line
;; Out: STMCUR = the line, or the first after it, LINE_LENGTH = its length, NEXT_STATEMENT = its first statement,
;;   carry = set when the line isn't there, STMCUR_SAVE = STMCUR before
;; Uses: A, Y
;; Entry: START_LINE = sets up the line already at STMCUR
;; See: <FIND_LINE>
START_LINE_NUMBER:
    jsr FIND_LINE
START_LINE:
    ldy #LINE_LENGTH_OFFSET
    lda (STMCUR),y
    sta LINE_LENGTH
    iny
    sty NEXT_STATEMENT              ; FIRST_STATEMENT_OFFSET
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The run-time stack
; ---------------------------------------------------------------------------------------------------------------------

;; Pops the run-time stack down to a variable's FOR entry, for FOR, which replaces it.
;;
;; The entry found is popped with every entry above it, BASIC_MEMTOP left at its start. When a GOSUB entry or the
;; stack's bottom comes first, the stack is left as it was.
;; In: A = the variable's token
;; Out: BASIC_MEMTOP = where the FOR entry was, or as it was, RUNSTACK_ENTRY = BASIC_MEMTOP as it was
;; Uses: A, X, Y, FOR_VARIABLE, LINE_NUMBER, RETURN_OFFSET
FIND_FOR_ENTRY:
    sta FOR_VARIABLE
    jsr MARK_RUNSTACK_ENTRY
FIND_FOR_ENTRY_LOOP:
    jsr STATEMENT_POP
    bcs FIND_FOR_ENTRY_NONE
    beq FIND_FOR_ENTRY_NONE         ; a GOSUB entry
    cmp FOR_VARIABLE
    beq FIND_FOR_ENTRY_DONE
    bne FIND_FOR_ENTRY_LOOP
FIND_FOR_ENTRY_NONE:
    lda RUNSTACK_ENTRY              ; put back what was popped
    sta BASIC_MEMTOP
    lda RUNSTACK_ENTRY+1
    sta BASIC_MEMTOP+1
.if VERSION = VERSION_A
    rts                             ; rev. A's own RTS
.endif
FIND_FOR_ENTRY_DONE:
    rts

;; POP: pops the run-time stack's top entry, forgetting the last GOSUB or FOR.
;;
;; As POP, it lets a program leave a subroutine or loop without RETURN or NEXT. NEXT and RETURN pop entries with it.
;; The entry's bytes stay above BASIC_MEMTOP, so a FOR entry's limit and step can still be read.
;; Out: carry = set when the stack is empty, A = the entry's token, zero = set for a GOSUB entry,
;;   LINE_NUMBER = the line that pushed it, RETURN_OFFSET = the offset of the statement's token there,
;;   BASIC_MEMTOP = the entry's start (a FOR entry's limit)
;; Uses: X, Y
STATEMENT_POP:
    lda RUNSTK+1
    cmp BASIC_MEMTOP+1
    bcc STATEMENT_POP_ENTRY
    lda RUNSTK
    cmp BASIC_MEMTOP
.if VERSION = VERSION_A             ; rev. A returns by its own SEC and RTS, and pops through POP_RUNSTACK
    bcc STATEMENT_POP_ENTRY
    sec                             ; empty
    rts
STATEMENT_POP_ENTRY:
    lda #RUNSTACK_HEADER
    jsr POP_RUNSTACK                ; the header
.else
    bcs FIND_FOR_ENTRY_DONE         ; empty: carry is set
STATEMENT_POP_ENTRY:
    lda #RUNSTACK_HEADER
    ldx #BASIC_MEMTOP
    jsr CLOSE_SPACE_A               ; the header
.endif
    ldy #RUNSTACK_OFFSET
    lda (BASIC_MEMTOP),y
    sta RETURN_OFFSET
    dey
    lda (BASIC_MEMTOP),y
    sta LINE_NUMBER+1
    dey
    lda (BASIC_MEMTOP),y
    sta LINE_NUMBER
    dey
    lda (BASIC_MEMTOP),y            ; the token
    beq STATEMENT_POP_DONE          ; a GOSUB entry
    pha
    lda #FOR_VALUES
.if VERSION = VERSION_A             ; rev. A pops through POP_RUNSTACK
    jsr POP_RUNSTACK                ; a FOR entry's limit and step
.else
    ldx #BASIC_MEMTOP
    jsr CLOSE_SPACE_A               ; a FOR entry's limit and step
.endif
    pla
STATEMENT_POP_DONE:
    clc
    rts

.if VERSION = VERSION_A
;; Pops bytes off the run-time stack, for POP: rev. A's own routine, where the later revisions call CLOSE_SPACE_A.
;; In: A = the bytes
;; Out: BASIC_MEMTOP = A bytes lower, X = 0, Y = 0
;; Uses: A, SPACE_SIZE, MOVE_LENGTH, MOVE_FROM, MOVE_TO, APPMHI
POP_RUNSTACK:
    tay
    ldx #BASIC_MEMTOP
    jmp CLOSE_SPACE
.endif

;; Pushes space for an entry on the run-time stack.
;; In: A = the entry's size
;; Out: RUNSTACK_ENTRY = the entry, BASIC_MEMTOP = above it
;; Uses: A, X, Y
;; Errors: 2 (ERR_MEMORY) when it would reach MEMTOP
PUSH_RUNSTACK:
    jsr MARK_RUNSTACK_ENTRY
    tay
    ldx #BASIC_MEMTOP
    jmp OPEN_SPACE

;; Sets RUNSTACK_ENTRY to the run-time stack's top.
;; Out: RUNSTACK_ENTRY = BASIC_MEMTOP
;; Uses: X
;; Keeps: A, Y
MARK_RUNSTACK_ENTRY:
    ldx BASIC_MEMTOP
    stx RUNSTACK_ENTRY
    ldx BASIC_MEMTOP+1
    stx RUNSTACK_ENTRY+1
    rts

;; Keeps the offset of the statement being run, for the run-time stack entry it will push.
;; Out: STATEMENT_OFFSET = TOKEN_OFFSET, just past the statement's token
;; Uses: Y
;; Keeps: A, X
SAVE_STATEMENT_OFFSET:
    ldy TOKEN_OFFSET
    sty STATEMENT_OFFSET
    rts

;; Copies a number from the zero page into the run-time stack's new entry, for FOR's limit and step.
;; In: X = the number's address, Y = its offset in the entry, RUNSTACK_ENTRY = the entry
;; Out: X, Y = past it
;; Uses: A, LOOP_COUNT
COPY_TO_RUNSTACK:
    lda #FP_SIZE
    sta LOOP_COUNT
COPY_TO_RUNSTACK_LOOP:
    lda 0,x
    sta (RUNSTACK_ENTRY),y
    inx
    iny
    dec LOOP_COUNT
    bne COPY_TO_RUNSTACK_LOOP
    rts

;; Copies a number from a popped FOR entry into FR1, for NEXT.
;; In: Y = its offset: FOR_LIMIT or FOR_STEP, BASIC_MEMTOP = the entry's values
;; Out: FR1 = the number
;; Uses: A, X, Y, LOOP_COUNT
COPY_FROM_RUNSTACK:
    lda #FP_SIZE
    sta LOOP_COUNT
    ldx #FR1
COPY_FROM_RUNSTACK_LOOP:
    lda (BASIC_MEMTOP),y
    sta 0,x
    inx
    iny
    dec LOOP_COUNT
    bne COPY_FROM_RUNSTACK_LOOP
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Clearing
; ---------------------------------------------------------------------------------------------------------------------

;; Empties the run-time stack and frees the string and array area, both of which start at STARP.
;; Out: RUNSTK, BASIC_MEMTOP, APPMHI = STARP
;; Uses: A
EMPTY_RUNSTACK:
    lda STARP
    sta RUNSTK
    sta BASIC_MEMTOP
    sta APPMHI
    lda STARP+1
    sta RUNSTK+1
    sta BASIC_MEMTOP+1
    sta APPMHI+1
    rts

;; Clears every entry in the variable value table: a number to 0, and a string or an array to undimensioned.
;;
;; Each entry keeps its type and number; its six bytes of value are zeroed, and its VALUE_DIMENSIONED bit cleared.
;; Uses: A, X, Y, ZTEMP1
CLEAR_VARIABLES:
    ldx VVTP
    stx ZTEMP1
    ldy VVTP+1
    sty ZTEMP1+1
CLEAR_VARIABLES_LOOP:
    ldx ZTEMP1+1
    cpx STMTAB+1
    bcc CLEAR_VARIABLES_ENTRY
    ldx ZTEMP1
    cpx STMTAB
    bcc CLEAR_VARIABLES_ENTRY
    rts                             ; at the statement table, the value table's end
CLEAR_VARIABLES_ENTRY:
    ldy #$00
    lda (ZTEMP1),y
    and #<~VALUE_DIMENSIONED
    sta (ZTEMP1),y
    ldy #VALUE_OFFSET
    ldx #FP_SIZE
    lda #$00
CLEAR_VARIABLES_VALUE:
    sta (ZTEMP1),y
    iny
    dex
    bne CLEAR_VARIABLES_VALUE
    lda ZTEMP1
    clc
    adc #VALUE_SIZE
    sta ZTEMP1
    lda ZTEMP1+1
    adc #$00
    sta ZTEMP1+1
    bne CLEAR_VARIABLES_LOOP        ; always: the table isn't in page 0

;; Resets what a program leaves behind, for RUN, NEW and the warm start: DATA, the error, STOPLN, TRAP, DEG,
;; BREAK, the sound and the IOCBs.
;; Out: DATA_ELEMENT, DATA_LINE, ERROR_NUMBER, STOPLN, DEGFLG = 0, TRAP_LINE+1 = $FF (no TRAP),
;;   BRKKEY = $FF (no BREAK)
;; Uses: A, X, Y, IOCB_NUMBER
;; See: <SILENCE_CLOSE_ALL>
RESET_RUN_STATE:
.if VERSION = VERSION_A
    ldy #$00                        ; rev. A clears each byte by name, without a loop
    sty STOPLN
    sty STOPLN+1
    sty ERROR_NUMBER
    sty DEGFLG                      ; radians
    sty DATA_ELEMENT
    sty DATA_LINE
    sty DATA_LINE+1
.else
    ldx #STOPLN+1-DATA_ELEMENT
    ldy #$00
RESET_RUN_STATE_LOOP:
    sty DATA_ELEMENT,x
    dex
    bpl RESET_RUN_STATE_LOOP
    sty DEGFLG                      ; radians
.endif
    dey
    sty TRAP_LINE+1
    sty BRKKEY
    jmp SILENCE_CLOSE_ALL           ; the sound off, IOCBs 1-7 closed

;; Asks whether the statement being run has nothing left but its end.
;; In: TOKEN_OFFSET = the next token
;; Out: carry = set when TOKEN_OFFSET is at the statement's end token, or past it
;; Uses: X
;; Keeps: A, Y
AT_STATEMENT_END:
    ldx TOKEN_OFFSET
    inx
    cpx NEXT_STATEMENT
    rts
