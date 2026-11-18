;; DELETE, RENUMBER, AUTO, DIM, the pseudo-variables, PROC, LOCAL, ENDPROC and the graphics statements
;; ($8F31-$945A).
;;
;; - The editing commands: <DELETE_COMMAND>, <RENUMBER_COMMAND> and <AUTO_COMMAND>, which read their start and step
;;   with <READ_START_AND_STEP>.
;; - <DIM_STATEMENT>, which makes arrays and reserves bytes on the heap, and <MULTIPLY_SIZE>, which the array code in
;;   Variables.asm shares.
;; - The pseudo-variables as statements: HIMEM, LOMEM, PAGE and TIME, with CLEAR and TRACE.
;; - The helpers that evaluate an integer or a real and convert the result, which most statements use.
;; - PROC, LOCAL and ENDPROC.
;; - GCOL, COLOUR, MODE, MOVE, DRAW, PLOT and VDU, which send VDU codes through OSWRCH.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; The errors this part raises. "RENUMBER space" and "Silly" are error 0, which BASIC's BRK handler treats as fatal:
; it puts back the default ON ERROR handler, so a program cannot trap them.

ERROR_BAD_DIM = 10                  ;; "Bad DIM": a bad array name or size, or an array made twice
ERROR_DIM_SPACE = 11                ;; "DIM space": no room on the heap for the array or bytes
ERROR_NOT_LOCAL = 12                ;; "Not LOCAL": LOCAL outside a PROC or FN
ERROR_NO_PROC = 13                  ;; "No PROC": ENDPROC outside a PROC
ERROR_BAD_MODE = 25                 ;; "Bad MODE": a MODE change that would not leave room for the program

DEFAULT_LINE_STEP = 10              ;; the start and step RENUMBER and AUTO take when they are not given
DIM_REAL_CELL = 5                   ;; the bytes in a real array's cell; an integer or string array's take one fewer


LOCAL_COUNT_OFFSET = 6              ;; where the LOCAL count of the frame is above the stack pointer in a statement

OSBYTE_READ_MODE_HIMEM = $85        ;; OSBYTE &85: reads the address where a mode's screen memory would start
OSWORD_WRITE_CLOCK = $02            ;; OSWORD 2: writes the five-byte system clock that TIME reads

; The VDU codes the graphics statements send.

VDU_TEXT_COLOUR = 17                ;; VDU 17,c: COLOUR
VDU_GRAPHICS_COLOUR = 18            ;; VDU 18,k,c: GCOL
VDU_MODE = 22                       ;; VDU 22,m: MODE
VDU_PLOT = 25                       ;; VDU 25,k,x;y;: PLOT
PLOT_MOVE = 4                       ;; the PLOT number of MOVE: move to an absolute position
PLOT_DRAW = 5                       ;; the PLOT number of DRAW: draw to an absolute position in the foreground colour

; The work bytes, as these routines use them.

DELETE_LAST = WORK + 2              ;; DELETE's last line number, two bytes
RENUMBER_LINE = WORK                ;; RENUMBER's pointer to the line number at the start of a line of the program
RENUMBER_NUMBER = WORK + 2          ;; RENUMBER's next new line number, two bytes, low byte first
RENUMBER_TABLE = FP_B               ;; RENUMBER's pointer into its table of the old line numbers, above <TOP>
DIM_CELL_SIZE = FP_B_MANTISSA + 1   ;; DIM's size of one cell of the array it is making
DIM_CELLS_OFFSET = PRINT_HEX        ;; DIM's offset of the first cell in the array's value: twice the dimensions, plus 1
SIZE_MULTIPLIER = FP_B_MANTISSA + 1 ;; <MULTIPLY_SIZE>'s multiplier, two bytes, low byte first

; ---------------------------------------------------------------------------------------------------------------------
; DELETE, RENUMBER and AUTO
; ---------------------------------------------------------------------------------------------------------------------

;; DELETE: deletes a range of lines from the program, DELETE first,last.
;;
;; Both line numbers are needed. It deletes each line number from the first to the last in turn, one at a time,
;; whether the line exists or not, checking for ESCAPE after each, then goes back to immediate mode.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; See: <READ_START_AND_STEP>
DELETE_COMMAND:
    jsr GET_LINE_NUMBER
    bcc SYNTAX_ERROR_RELAY                       ; no first line number: a syntax error
    jsr PUSH_INTEGER
    jsr GET_CHARACTER_A
    cmp #','
    bne SYNTAX_ERROR_RELAY
    jsr GET_LINE_NUMBER
    bcc SYNTAX_ERROR_RELAY
    jsr CHECK_END_OF_STATEMENT
    lda INT_A
    sta DELETE_LAST
    lda INT_A+1
    sta DELETE_LAST+1
    jsr POP_INTEGER                 ; IntA = the first line number
DELETE_COMMAND_LOOP:
    jsr DELETE_LINE                       ; delete line IntA, if there is one
    jsr CHECK_ESCAPE                       ; stop on ESCAPE
    jsr INCREMENT_INT_A
    lda DELETE_LAST
    cmp INT_A
    lda DELETE_LAST+1
    sbc INT_A+1
    bcs DELETE_COMMAND_LOOP         ; until IntA is past the last
    jmp WARM_START

;; Reads the start and step of RENUMBER or AUTO: [start][,step].
;;
;; Each defaults to 10. The step must be 1-255, or it gives the "Silly" error.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; Out: INT_A = the step, BASIC_STACK = the start, pushed on BASIC's stack as an integer, PTR_A_OFFSET = after the step
;; Entry: READ_START_AND_STEP_END = steps back over the character just read and checks the statement ends
READ_START_AND_STEP:
    lda #DEFAULT_LINE_STEP
    jsr LOAD_INT_A_BYTE                       ; IntA = 10
    jsr GET_LINE_NUMBER             ; IntA = the start, if one is given
    jsr PUSH_INTEGER
    lda #DEFAULT_LINE_STEP
    jsr LOAD_INT_A_BYTE
    jsr GET_CHARACTER_A
    cmp #','
    bne READ_START_AND_STEP_END
    jsr GET_LINE_NUMBER             ; IntA = the step
    lda INT_A+1
    bne SILLY_ERROR                 ; 256 or more
    lda INT_A
    beq SILLY_ERROR                 ; zero
    inc PTR_A_OFFSET                ; undo the decrement below: no character was read after the step
READ_START_AND_STEP_END:
    dec PTR_A_OFFSET
    jmp CHECK_END_OF_STATEMENT

;; Starts a pass of RENUMBER: points <RENUMBER_TABLE> at the start of its table at <TOP> and falls into
;; <RENUMBER_FIRST_LINE>.
;; Out: RENUMBER_TABLE = TOP, RENUMBER_LINE = PAGE + 1, A = 1
RENUMBER_RESTART:
    lda TOP
    sta RENUMBER_TABLE
    lda TOP+1
    sta RENUMBER_TABLE+1

;; Points <RENUMBER_LINE> at the first line of the program: at PAGE + 1, its line number, after the carriage return
;; that a program starts with.
;; Out: RENUMBER_LINE = PAGE + 1, A = 1
RENUMBER_FIRST_LINE:
    lda PAGE_HIGH
    sta RENUMBER_LINE+1
    lda #$01
    sta RENUMBER_LINE
    rts

;; RENUMBER: renumbers the program, RENUMBER [start][,step], and the line numbers GOTO, GOSUB and the rest refer to.
;;
;; It works in three passes over the program:
;;
;; - The first copies each line's old number into a table above the program, at <TOP>, two bytes a line, high byte
;;   first. If the table would reach HIMEM, it gives the "RENUMBER space" error.
;; - The second gives each line its new number, from the start, adding the step each time.
;; - The third looks for each line number token in the program and finds its old number in the table. The table's
;;   entries are in the same order as the lines, so the line at the same position has the new number, which replaces
;;   the old. A reference to a line that does not exist is left alone, and "Failed at" and the number of the line
;;   that holds it is printed.
;;
;; It ends by going back to immediate mode.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; See: <READ_START_AND_STEP>, <NEXT_PROGRAM_LINE>
RENUMBER_COMMAND:
    jsr READ_START_AND_STEP
    ldx #RENUMBER_NUMBER
    jsr POP_INTEGER_TO              ; the start
    jsr FIND_PROGRAM_END                       ; check the program and find TOP
    jsr RENUMBER_RESTART
RENUMBER_SAVE_LOOP:
    ldy #$00
    lda (RENUMBER_LINE),y
    bmi RENUMBER_NUMBER_LINES       ; the end of the program: its high byte is &FF
    sta (RENUMBER_TABLE),y          ; copy the old number, high byte first
    iny
    lda (RENUMBER_LINE),y
    sta (RENUMBER_TABLE),y
    sec
    tya
    adc RENUMBER_TABLE              ; + 2
    sta RENUMBER_TABLE
    tax
    lda RENUMBER_TABLE+1
    adc #$00
    sta RENUMBER_TABLE+1
    cpx HIMEM
    sbc HIMEM+1
    bcs RENUMBER_SPACE_ERROR
    jsr NEXT_PROGRAM_LINE
    bcc RENUMBER_SAVE_LOOP          ; always taken: NEXT_PROGRAM_LINE returns with carry clear

;; Gives the "RENUMBER space" error: RENUMBER's table of old line numbers would reach HIMEM.
;;
;; The message has no zero of its own: the BRK of <SILLY_ERROR> that follows ends it.
RENUMBER_SPACE_ERROR:
    brk
    .byte 0, TOKEN_RENUMBER, " space"

;; Gives the "Silly" error: a RENUMBER or AUTO step of 0 or more than 255.
SILLY_ERROR:
    brk
    .byte 0, "Silly", 0

;; RENUMBER's second and third passes, part of <RENUMBER_COMMAND>.
;;
;; The second pass gives each line its new number, the third replaces the line numbers the program refers to.
;; Entry:
;;   RENUMBER_NUMBER_LOOP = numbers the line at RENUMBER_LINE and the lines after it
;;   RENUMBER_FIX_REFERENCES = the third pass
RENUMBER_NUMBER_LINES:
    jsr RENUMBER_FIRST_LINE
RENUMBER_NUMBER_LOOP:
    ldy #$00
    lda (RENUMBER_LINE),y
    bmi RENUMBER_FIX_REFERENCES     ; the end of the program
    lda RENUMBER_NUMBER+1
    sta (RENUMBER_LINE),y           ; the new number, high byte first
    lda RENUMBER_NUMBER
    iny
    sta (RENUMBER_LINE),y
    clc
    lda INT_A                       ; + the step
    adc RENUMBER_NUMBER
    sta RENUMBER_NUMBER
    lda #$00
    adc RENUMBER_NUMBER+1
    and #$7F                        ; keep the numbers below 32768
    sta RENUMBER_NUMBER+1
    jsr NEXT_PROGRAM_LINE
    bcc RENUMBER_NUMBER_LOOP        ; always taken
RENUMBER_FIX_REFERENCES:
    lda PAGE_HIGH
    sta PTR_A+1
    ldy #$00
    sty PTR_A                       ; PTRA = PAGE: the carriage return before the first line
    iny
    lda (PTR_A),y
    bmi RENUMBER_DONE               ; no program
RENUMBER_SCAN_LINE:
    ldy #$04                        ; the line's first character, after its number and length
RENUMBER_SCAN_LOOP:
    lda (PTR_A),y
    cmp #TOKEN_LINE_NUMBER
    beq RENUMBER_FOUND_REFERENCE
    iny
    cmp #CARRIAGE_RETURN
    bne RENUMBER_SCAN_LOOP
    lda (PTR_A),y                   ; the next line's number, high byte
    bmi RENUMBER_DONE               ; the end of the program
    ldy #$03
    lda (PTR_A),y                   ; the line's length
    clc
    adc PTR_A
    sta PTR_A
    bcc RENUMBER_SCAN_LINE
    inc PTR_A+1
    bcs RENUMBER_SCAN_LINE          ; always taken
RENUMBER_DONE:
    jmp WARM_START
RENUMBER_FOUND_REFERENCE:
    jsr UNPACK_LINE_NUMBER                       ; IntA = the old line number; PTR_A_OFFSET = after it
    jsr RENUMBER_RESTART
RENUMBER_LOOKUP_LOOP:
    ldy #$00
    lda (RENUMBER_LINE),y
    bmi RENUMBER_FAILED             ; the end of the program: no such line
    lda (RENUMBER_TABLE),y
    iny
    cmp INT_A+1
    bne RENUMBER_LOOKUP_NEXT
    lda (RENUMBER_TABLE),y
    cmp INT_A
    bne RENUMBER_LOOKUP_NEXT
    lda (RENUMBER_LINE),y           ; found: this line's new number
    sta FP_B_EXPONENT               ; its low byte
    dey
    lda (RENUMBER_LINE),y
    sta FP_B_MANTISSA               ; its high byte
    ldy PTR_A_OFFSET
    dey                             ; the token's last byte
    lda PTR_A
    sta WORK
    lda PTR_A+1
    sta WORK+1
    jsr ENCODE_LINE_NUMBER                       ; write the new number over the token's three bytes
RENUMBER_SCAN_ON:
    ldy PTR_A_OFFSET
    bne RENUMBER_SCAN_LOOP          ; always taken
RENUMBER_LOOKUP_NEXT:
    jsr NEXT_PROGRAM_LINE
    lda RENUMBER_TABLE
    adc #$02                        ; carry is clear
    sta RENUMBER_TABLE
    bcc RENUMBER_LOOKUP_LOOP
    inc RENUMBER_TABLE+1
    bcs RENUMBER_LOOKUP_LOOP        ; always taken
RENUMBER_FAILED:
    jsr PRINT_INLINE
    .byte "Failed at "              ; ended by the INY below, whose opcode, &C8, has its top bit set
    iny                             ; Y = 1: the line's number, high byte first
    lda (PTR_A),y
    sta INT_A+1
    iny
    lda (PTR_A),y
    sta INT_A
    jsr PRINT_LINE_NUMBER
    jsr PRINT_NEWLINE
    beq RENUMBER_SCAN_ON            ; always taken: PRINT_NEWLINE returns A = 0

;; Moves <RENUMBER_LINE> from one line of the program to the next, by the length in the line.
;; In: RENUMBER_LINE = the line's number, Y = 1
;; Out: RENUMBER_LINE = the next line's number, carry = clear
;; Uses: A, Y
NEXT_PROGRAM_LINE:
    iny
    lda (RENUMBER_LINE),y           ; the line's length
    adc RENUMBER_LINE
    sta RENUMBER_LINE
    bcc NEXT_PROGRAM_LINE_DONE
    inc RENUMBER_LINE+1
    clc
NEXT_PROGRAM_LINE_DONE:
    rts

;; AUTO: numbers the lines typed, AUTO [start][,step].
;;
;; It prints each line number and reads a line after it, then puts the line in the program, clears the variables as
;; editing the program does, and goes on to the next number. It runs until ESCAPE is pressed, which gives the
;; "Escape" error, or the line number passes 32767.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; See: <READ_START_AND_STEP>
AUTO_COMMAND:
    jsr READ_START_AND_STEP
    lda INT_A
    pha                             ; the step, which is below 256
    jsr POP_INTEGER                 ; IntA = the start
AUTO_COMMAND_LOOP:
    jsr PUSH_INTEGER
    jsr PRINT_LINE_NUMBER_PADDED                       ; print the line number in five columns
    lda #' '
    jsr READ_LINE_WITH_PROMPT                       ; print a space and read a line into the line buffer
    jsr POP_INTEGER
    jsr TOKENISE_STATEMENT                       ; tokenise it
    jsr INSERT_LINE                       ; put it in the program as line IntA
    jsr CLEAR_VARIABLES                       ; clear the variables
    pla
    pha
    clc
    adc INT_A
    sta INT_A
    bcc AUTO_COMMAND_LOOP
    inc INT_A+1
    bpl AUTO_COMMAND_LOOP
    jmp WARM_START

; ---------------------------------------------------------------------------------------------------------------------
; DIM
; ---------------------------------------------------------------------------------------------------------------------

;; Gives the "DIM space" error, from a branch that cannot reach <DIM_SPACE_ERROR>.
DIM_BYTES_NO_SPACE:
    jmp DIM_SPACE_ERROR

;; Reserves bytes on the heap for DIM name size: sets the numeric variable to the address of size + 1 bytes.
;;
;; The bytes are not cleared. A size of -1 reserves nothing, which leaves the variable holding the top of the heap.
;; The name may be a resident integer or indirection; a string gives the "Bad DIM" error. It goes on to the next item
;; of the DIM statement, if there is one.
;; In: PTR_A_OFFSET = just after the name's first character
;; See: <DIM_STATEMENT>
DIM_BYTES:
    dec PTR_A_OFFSET
    jsr FIND_OR_CREATE_VARIABLE     ; find the variable, making it if it is new
    beq BAD_DIM_ERROR               ; not a variable
    bcs BAD_DIM_ERROR               ; a string
    jsr PUSH_INTEGER                ; its descriptor
    jsr EVALUATE_INTEGER
    jsr INCREMENT_INT_A
    lda INT_A+3
    ora INT_A+2
    bne BAD_DIM_ERROR               ; less than -1, or too big
    clc
    lda INT_A
    adc HEAP
    tay
    lda INT_A+1
    adc HEAP+1
    tax
    cpy BASIC_STACK
    sbc BASIC_STACK+1
    bcs DIM_BYTES_NO_SPACE          ; it would reach BASIC's stack
    lda HEAP
    sta INT_A
    lda HEAP+1
    sta INT_A+1                     ; IntA = the address of the bytes
    sty HEAP
    stx HEAP+1
    lda #$00
    sta INT_A+2
    sta INT_A+3
    lda #$40                        ; an integer
    sta EXPRESSION_TYPE
    jsr ASSIGN_NUMBER
    jsr SET_PTR_A_OFFSET_FROM_B                       ; PTRA's offset = PTRB's
    jmp DIM_NEXT_ITEM

;; Gives the "Bad DIM" error: a bad name or size, or an array that already exists.
BAD_DIM_ERROR:
    brk
    .byte ERROR_BAD_DIM, "Bad ", TOKEN_DIM, 0

;; DIM: makes arrays and reserves memory, DIM name(size[,size...]) or DIM name size, with items separated by commas.
;;
;; An array's information block holds its name and then its value: a byte giving the offset of the first cell, which
;; is twice the number of dimensions plus 1; the number of elements in each dimension, two bytes each, one more than
;; the size given; then the cells, five bytes each for a real array and four for an integer or string array, all
;; cleared to zero. Each size must be 0-16383, or it gives the "Bad DIM" error, as does an array made twice; no room
;; on the heap gives the "DIM space" error.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword, or after the comma before the next item
;; See: <DIM_BYTES>, <MULTIPLY_SIZE>, <FIND_ARRAY_ELEMENT>
DIM_STATEMENT:
    jsr GET_CHARACTER_A
    tya
    clc
    adc PTR_A
    ldx PTR_A+1
    bcc DIM_STATEMENT_1
    inx
    clc
DIM_STATEMENT_1:
    sbc #$00                        ; carry is clear: WORK = PTRA + Y - 1, so the name is at WORK + 1
    sta WORK
    txa
    sbc #$00
    sta WORK+1
    ldx #DIM_REAL_CELL
    stx DIM_CELL_SIZE
    ldx PTR_A_OFFSET
    jsr SCAN_VARIABLE_NAME
    cpy #$01
    beq BAD_DIM_ERROR               ; no name
    cmp #'('
    beq DIM_ARRAY
    cmp #'$'
    beq DIM_STATEMENT_SUFFIX
    cmp #'%'
    bne DIM_STATEMENT_BYTES
DIM_STATEMENT_SUFFIX:
    dec DIM_CELL_SIZE               ; four bytes a cell for an integer or string array
    iny
    inx
    lda (WORK),y
    cmp #'('
    beq DIM_ARRAY
DIM_STATEMENT_BYTES:
    jmp DIM_BYTES
DIM_ARRAY:
    sty WORK+2                      ; the name's length, its "(" included
    stx PTR_A_OFFSET                ; after the "("
    jsr SEARCH_VARIABLE_LIST
    bne BAD_DIM_ERROR               ; the array exists
    jsr LINK_VARIABLE
    ldx #$01
    jsr ALLOCATE_VARIABLE           ; end the name with a zero and claim it: HEAP = the array's value
    lda DIM_CELL_SIZE
    pha
    lda #$01
    pha                             ; the offset of the next dimension's size in the value
    jsr LOAD_INT_A_BYTE                       ; IntA = 1, the product of the sizes so far
DIM_ARRAY_SUBSCRIPT_LOOP:
    jsr PUSH_INTEGER
    jsr EVALUATE_INTEGER_A                       ; IntA = the size
    lda INT_A+1
    and #$C0
    ora INT_A+2
    ora INT_A+3
    bne BAD_DIM_ERROR               ; not 0-16383
    jsr INCREMENT_INT_A             ; the number of elements
    pla
    tay
    lda INT_A
    sta (HEAP),y
    iny
    lda INT_A+1
    sta (HEAP),y
    iny
    tya
    pha
    jsr POP_AND_MULTIPLY_SIZE       ; IntA = the product of the numbers of elements
    jsr GET_CHARACTER_A
    cmp #','
    beq DIM_ARRAY_SUBSCRIPT_LOOP
    cmp #')'
    beq DIM_ARRAY_SIZE
    jmp BAD_DIM_ERROR
DIM_ARRAY_SIZE:
    pla
    sta DIM_CELLS_OFFSET
    pla
    sta SIZE_MULTIPLIER             ; the cell size
    lda #$00
    sta SIZE_MULTIPLIER+1
    jsr MULTIPLY_SIZE               ; IntA = the bytes of cells
    ldy #$00
    lda DIM_CELLS_OFFSET
    sta (HEAP),y
    adc INT_A
    sta INT_A
    bcc DIM_ARRAY_CLAIM
    inc INT_A+1
DIM_ARRAY_CLAIM:
    lda HEAP+1
    sta WORK+1
    lda HEAP
    sta WORK                        ; WORK = the array's value
    clc
    adc INT_A
    tay
    lda INT_A+1
    adc HEAP+1
    bcs DIM_SPACE_ERROR
    tax
    cpy BASIC_STACK
    sbc BASIC_STACK+1
    bcs DIM_SPACE_ERROR
    sty HEAP
    stx HEAP+1
    lda WORK
    adc DIM_CELLS_OFFSET            ; carry is clear
    tay
    lda #$00
    sta WORK                        ; WORK + Y = the first cell
    bcc DIM_ARRAY_ZERO_LOOP
    inc WORK+1
DIM_ARRAY_ZERO_LOOP:
    sta (WORK),y
    iny
    bne DIM_ARRAY_ZERO_NEXT
    inc WORK+1
DIM_ARRAY_ZERO_NEXT:
    cpy HEAP
    bne DIM_ARRAY_ZERO_LOOP
    cpx WORK+1
    bne DIM_ARRAY_ZERO_LOOP

;; Goes on to DIM's next item after a comma, or ends the statement.
;; Entry: DIM_ANOTHER = starts the next item
DIM_NEXT_ITEM:
    jsr GET_CHARACTER_A
    cmp #','
    beq DIM_ANOTHER
    jmp FINISH_STATEMENT_BACK_ONE
DIM_ANOTHER:
    jmp DIM_STATEMENT

;; Gives the "DIM space" error: no room on the heap below BASIC's stack.
DIM_SPACE_ERROR:
    brk
    .byte ERROR_DIM_SPACE, TOKEN_DIM, " space", 0

;; Adds 1 to IntA, all four bytes.
;; In: INT_A = the number
;; Out: INT_A = the number + 1
;; Keeps: A, X, Y
INCREMENT_INT_A:
    inc INT_A
    bne INCREMENT_INT_A_DONE
    inc INT_A+1
    bne INCREMENT_INT_A_DONE
    inc INT_A+2
    bne INCREMENT_INT_A_DONE
    inc INT_A+3
INCREMENT_INT_A_DONE:
    rts

;; Pops an integer from BASIC's stack into <SIZE_MULTIPLIER> and falls into <MULTIPLY_SIZE>.
;; In: INT_A = the multiplicand, BASIC_STACK = the multiplier, pushed as an integer
;; Out: INT_A = the product
;; Uses: A, X, Y, FP_B..FP_B_MANTISSA+2
POP_AND_MULTIPLY_SIZE:
    ldx #SIZE_MULTIPLIER
    jsr POP_INTEGER_TO

;; Multiplies the low 16 bits of IntA by <SIZE_MULTIPLIER>, for the size of an array or the position of an element in
;; one.
;;
;; It adds the doubled multiplicand for each bit of the multiplier, from the lowest. A carry out of the sum gives the
;; "Bad DIM" error, but the bits shifted out of the top of the doubled multiplicand are lost, so a few large products
;; wrap round instead. IntA's top two bytes are left as they were.
;; In: INT_A = the multiplicand, SIZE_MULTIPLIER = the multiplier
;; Out: INT_A = the product, low 16 bits
;; Uses: A, X, Y, SIZE_MULTIPLIER
MULTIPLY_SIZE:
    ldx #$00
    ldy #$00                        ; the product, Y low and X high
MULTIPLY_SIZE_LOOP:
    lsr SIZE_MULTIPLIER+1
    ror SIZE_MULTIPLIER
    bcc MULTIPLY_SIZE_SHIFT
    clc
    tya
    adc INT_A
    tay
    txa
    adc INT_A+1
    tax
    bcs MULTIPLY_SIZE_OVERFLOW
MULTIPLY_SIZE_SHIFT:
    asl INT_A
    rol INT_A+1
    lda SIZE_MULTIPLIER
    ora SIZE_MULTIPLIER+1
    bne MULTIPLY_SIZE_LOOP
    sty INT_A
    stx INT_A+1
    rts
MULTIPLY_SIZE_OVERFLOW:
    jmp BAD_DIM_ERROR

; ---------------------------------------------------------------------------------------------------------------------
; The pseudo-variables, CLEAR and TRACE
; ---------------------------------------------------------------------------------------------------------------------

;; HIMEM=: sets the top of the memory BASIC uses, HIMEM=address.
;;
;; BASIC's stack starts again at the new HIMEM, so anything on it is lost.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
HIMEM_STATEMENT:
    jsr EVALUATE_ASSIGNED_INTEGER
    lda INT_A
    sta HIMEM
    sta BASIC_STACK
    lda INT_A+1
    sta HIMEM+1
    sta BASIC_STACK+1
    jmp CONTINUE_EXECUTION

;; LOMEM=: sets where the variables start, LOMEM=address.
;;
;; The heap starts again there, and the variable lists are cleared, since the old variables are lost.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
LOMEM_STATEMENT:
    jsr EVALUATE_ASSIGNED_INTEGER
    lda INT_A
    sta LOMEM
    sta HEAP
    lda INT_A+1
    sta LOMEM+1
    sta HEAP+1
    jsr CLEAR_VARIABLE_LISTS                       ; clear the variable lists
    beq PAGE_STATEMENT_DONE         ; always taken: it returns A = 0

;; PAGE=: sets where the program starts, PAGE=address.
;;
;; Only the high byte is used: the program starts on a page boundary.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; Entry: PAGE_STATEMENT_DONE = goes on to the next statement, for LOMEM and CLEAR
PAGE_STATEMENT:
    jsr EVALUATE_ASSIGNED_INTEGER
    lda INT_A+1
    sta PAGE_HIGH
PAGE_STATEMENT_DONE:
    jmp CONTINUE_EXECUTION

;; CLEAR: forgets all the variables, except the resident integers, and empties BASIC's stacks.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
CLEAR_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    jsr CLEAR_VARIABLES
    beq PAGE_STATEMENT_DONE         ; always taken: it returns A = 0

;; TRACE: turns line number tracing on or off, TRACE ON, TRACE OFF or TRACE limit.
;;
;; While it is on, BASIC prints the number of each line it runs that is no higher than the limit, in square
;; brackets. TRACE ON sets a limit of at least &FF00, above every line number.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; Out: TRACE_FLAG = &FF for on or &00 for off, TRACE_LIMIT = the limit
TRACE_STATEMENT:
    jsr GET_LINE_NUMBER
    bcs TRACE_LINE                  ; a line number: the limit
    cmp #TOKEN_ON
    beq TRACE_ON
    cmp #TOKEN_OFF
    beq TRACE_OFF
    jsr EVALUATE_INTEGER_A                       ; the limit, as an expression
TRACE_LINE:
    jsr CHECK_END_OF_STATEMENT
    lda INT_A
    sta TRACE_LIMIT
    lda INT_A+1
TRACE_SET_LIMIT_HIGH:
    sta TRACE_LIMIT+1
    lda #$FF
TRACE_SET_FLAG:
    sta TRACE_FLAG
    jmp CONTINUE_EXECUTION
TRACE_ON:
    inc PTR_A_OFFSET
    jsr CHECK_END_OF_STATEMENT
    lda #$FF
    bne TRACE_SET_LIMIT_HIGH        ; always taken
TRACE_OFF:
    inc PTR_A_OFFSET
    jsr CHECK_END_OF_STATEMENT
    lda #$00
    beq TRACE_SET_FLAG              ; always taken

;; TIME=: sets the system clock, TIME=centiseconds.
;;
;; It writes IntA as the clock's low four bytes with OSWORD 2, its fifth byte, at &2E, cleared.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
TIME_STATEMENT:
    jsr EVALUATE_ASSIGNED_INTEGER
    ldx #<INT_A
    ldy #>INT_A
    sty FP_A_SIGN                   ; the clock's fifth byte, after IntA's four
    lda #OSWORD_WRITE_CLOCK
    jsr OSWORD
    jmp CONTINUE_EXECUTION

; ---------------------------------------------------------------------------------------------------------------------
; Evaluating integers and reals
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a comma at PTRB, then falls into <EVALUATE_INTEGER> for the expression after it.
;;
;; A missing comma gives the "Missing ," error.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: INT_A = the value, X = the character that ended the expression, PTR_B_OFFSET = its offset
EVALUATE_COMMA_INTEGER:
    jsr CHECK_COMMA_B

;; Evaluates the expression at PTRB as an integer.
;;
;; A real is truncated; a string gives the "Type mismatch" error.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: INT_A = the value, X = the character that ended the expression, PTR_B_OFFSET = its offset
;; See: <CONVERT_A_TO_INTEGER>
EVALUATE_INTEGER:
    jsr EVALUATE_EXPRESSION
    jmp CONVERT_A_TO_INTEGER

;; Evaluates the factor at PTRB, such as a number, variable or bracketed expression, as an integer.
;;
;; A real is truncated; a string gives the "Type mismatch" error.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: INT_A = the value, PTR_B_OFFSET = after the factor
;; Entry: CONVERT_TO_INTEGER_DONE = returns, for <CONVERT_A_TO_INTEGER> and <CONVERT_A_TO_REAL>
EVALUATE_INTEGER_FACTOR:
    jsr EVALUATE_FACTOR
    beq CONVERT_TO_INTEGER_MISMATCH
    bmi CONVERT_TO_INTEGER_REAL
CONVERT_TO_INTEGER_DONE:
    rts

;; Evaluates "= expression" at PTRA, for an assignment to a pseudo-variable, as an integer.
;; In: PTR_A, PTR_A_OFFSET = before the "="
;; Out: INT_A = the value
EVALUATE_ASSIGNED_INTEGER:
    jsr EVALUATE_EQUALS_A

;; Makes the last expression's value an integer, by the type in <EXPRESSION_TYPE>.
;; Inherit: <CONVERT_A_TO_INTEGER> Out
CONVERT_TO_INTEGER:
    lda EXPRESSION_TYPE

;; Makes a value an integer, by its type: truncates a real in FPA into IntA, and gives the "Type mismatch" error for a
;; string.
;;
;; The flags must match A, as they do after the evaluator returns or after loading A.
;; In: A = the type: &00 for a string, &40 for an integer, &FF for a real, zero = set for a string,
;;   negative = set for a real
;; Out: INT_A = the value
;; Entry:
;;   CONVERT_TO_INTEGER_REAL = truncates FPA into IntA
;;   CONVERT_TO_INTEGER_MISMATCH = gives the "Type mismatch" error
CONVERT_A_TO_INTEGER:
    beq CONVERT_TO_INTEGER_MISMATCH
    bpl CONVERT_TO_INTEGER_DONE     ; already an integer
CONVERT_TO_INTEGER_REAL:
    jmp REAL_TO_INTEGER
CONVERT_TO_INTEGER_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Evaluates the factor at PTRB as a real, converting an integer.
;; In: PTR_B, PTR_B_OFFSET = the text
;; Out: FP_A = the value, PTR_B_OFFSET = after the factor
EVALUATE_REAL_FACTOR:
    jsr EVALUATE_FACTOR

;; Makes a value a real, by its type: converts an integer in IntA into FPA, and gives the "Type mismatch" error for a
;; string.
;; In: A = the type: &00 for a string, &40 for an integer, &FF for a real, zero = set for a string,
;;   negative = set for a real
;; Out: FP_A = the value
CONVERT_A_TO_REAL:
    beq CONVERT_TO_INTEGER_MISMATCH
    bmi CONVERT_TO_INTEGER_DONE     ; already a real
    jmp INTEGER_TO_REAL

; ---------------------------------------------------------------------------------------------------------------------
; PROC, LOCAL and ENDPROC
; ---------------------------------------------------------------------------------------------------------------------

;; PROC: calls a procedure, PROCname[(parameters)].
;;
;; The call runs the procedure's statements and returns here when its ENDPROC is reached.
;; In: PTR_A, PTR_A_OFFSET = just after the PROC token
;; See: <CALL_FN_PROC>, <ENDPROC_STATEMENT>
PROC_STATEMENT:
    lda PTR_A
    sta PTR_B
    lda PTR_A+1
    sta PTR_B+1
    lda PTR_A_OFFSET
    sta PTR_B_OFFSET
    lda #TOKEN_PROC
    jsr CALL_FN_PROC
    jsr CHECK_END_OF_STATEMENT_B
    jmp CONTINUE_EXECUTION

;; Makes a LOCAL string empty, by setting its length to zero, part of <LOCAL_STATEMENT>.
LOCAL_STRING:
    ldy #$03                        ; the string's length, in its value
    lda #$00
    sta (INT_A),y
    beq LOCAL_COUNT                 ; always taken

;; LOCAL: makes variables local to the PROC or FN running, LOCAL name[,name...].
;;
;; Each variable's value is saved on BASIC's stack, to be put back when the PROC or FN returns, and the variable set
;; to zero or an empty string. The count of LOCAL variables in the call's frame on the 6502 stack goes up by one for
;; each. Outside a PROC or FN it gives the "Not LOCAL" error.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; See: <FN_PROC_STACK_LIMIT>, <PUSH_VARIABLE>
LOCAL_STATEMENT:
    tsx
    cpx #FN_PROC_STACK_LIMIT
    bcs NOT_LOCAL_ERROR             ; no PROC or FN frame
    jsr FIND_OR_CREATE_VARIABLE     ; find the variable, making it if it is new
    beq LOCAL_END                   ; not a variable
    jsr PUSH_VARIABLE                       ; save its value and descriptor on BASIC's stack
    ldy INT_A+2
    bmi LOCAL_STRING
    jsr PUSH_INTEGER
    lda #$00
    jsr LOAD_INT_A_BYTE                       ; IntA = 0; A = &40, an integer
    sta EXPRESSION_TYPE
    jsr ASSIGN_NUMBER
LOCAL_COUNT:
    tsx
    inc STACK+LOCAL_COUNT_OFFSET,x  ; one more LOCAL variable in the frame
    ldy PTR_B_OFFSET
    sty PTR_A_OFFSET
    jsr GET_CHARACTER_A
    cmp #','
    beq LOCAL_STATEMENT
    jmp FINISH_STATEMENT_BACK_ONE
LOCAL_END:
    jmp FINISH_STATEMENT

;; ENDPROC: returns from a procedure.
;;
;; It checks that a PROC's frame is on the 6502 stack, with the PROC token at its bottom, then jumps to
;; CHECK_END_OF_STATEMENT, whose RTS returns from the statement loop the PROC call ran the procedure with. Otherwise
;; it gives the "No PROC" error.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; See: <PROC_STATEMENT>, <FN_PROC_STACK_LIMIT>
ENDPROC_STATEMENT:
    tsx
    cpx #FN_PROC_STACK_LIMIT
    bcs NO_PROC_ERROR
    lda STACK+$FF                   ; the token of the call
    cmp #TOKEN_PROC
    bne NO_PROC_ERROR               ; an FN
    jmp CHECK_END_OF_STATEMENT

;; Gives the "No PROC" error: ENDPROC outside a PROC.
;;
;; The message has no zero of its own: the BRK of <NOT_LOCAL_ERROR> that follows ends it.
NO_PROC_ERROR:
    brk
    .byte ERROR_NO_PROC, "No ", TOKEN_PROC

;; Gives the "Not LOCAL" error: LOCAL outside a PROC or FN.
;;
;; The message has no zero of its own: the BRK of <BAD_MODE_ERROR> that follows ends it.
NOT_LOCAL_ERROR:
    brk
    .byte ERROR_NOT_LOCAL, "Not ", TOKEN_LOCAL

;; Gives the "Bad MODE" error: a MODE change with something on BASIC's stack, or whose screen would overlap the
;; program or the variables.
BAD_MODE_ERROR:
    brk
    .byte ERROR_BAD_MODE, "Bad ", TOKEN_MODE, 0

; ---------------------------------------------------------------------------------------------------------------------
; The graphics statements and VDU
; ---------------------------------------------------------------------------------------------------------------------

;; GCOL: sets a graphics colour and how it is plotted, GCOL action,colour, with VDU 18.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
GCOL_STATEMENT:
    jsr EVALUATE_INTEGER_A                       ; the action
    lda INT_A
    pha
    jsr EVALUATE_COMMA_INTEGER      ; the colour
    jsr CHECK_END_OF_STATEMENT_B
    lda #VDU_GRAPHICS_COLOUR
    jsr OSWRCH
    jmp SEND_PARAMETERS

;; COLOUR: sets a text colour, COLOUR colour, with VDU 17.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
COLOUR_STATEMENT:
    lda #VDU_TEXT_COLOUR
    pha
    jsr EVALUATE_INTEGER_A
    jsr CHECK_END_OF_STATEMENT
    jmp SEND_PARAMETERS

;; MODE: changes the screen mode, MODE mode, with VDU 22.
;;
;; When BASIC runs in the I/O processor, the new mode's screen memory moves HIMEM, so it first checks that BASIC's
;; stack is empty, as it is not inside a PROC or FN, and that the screen would start above the program and the
;; variables, or gives the "Bad MODE" error. It then sets HIMEM to the screen's start. Across the Tube, HIMEM is not
;; affected. It also resets COUNT, since the screen is cleared.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
MODE_STATEMENT:
    lda #VDU_MODE
    pha
    jsr EVALUATE_INTEGER_A
    jsr CHECK_END_OF_STATEMENT
    jsr READ_HIGH_ORDER_ADDRESS                       ; read the high order address
    cpx #$FF
    bne MODE_STATEMENT_SEND         ; across the Tube
    cpy #$FF
    bne MODE_STATEMENT_SEND
    lda BASIC_STACK
    cmp HIMEM
    bne BAD_MODE_ERROR              ; something is on BASIC's stack
    lda BASIC_STACK+1
    cmp HIMEM+1
    bne BAD_MODE_ERROR
    ldx INT_A
    lda #OSBYTE_READ_MODE_HIMEM
    jsr OSBYTE                      ; X and Y = where the new mode's screen would start
    cpx HEAP
    tya
    sbc HEAP+1
    bcc BAD_MODE_ERROR
    cpx TOP
    tya
    sbc TOP+1
    bcc BAD_MODE_ERROR
    stx HIMEM
    stx BASIC_STACK
    sty HIMEM+1
    sty BASIC_STACK+1
MODE_STATEMENT_SEND:
    jsr RESET_COUNT                       ; COUNT = 0

;; Sends the VDU code on the 6502 stack, then the low byte of IntA, and goes on to the next statement.
;;
;; GCOL, COLOUR and MODE jump here, GCOL having sent its code already and left its first parameter on the stack.
;; In: INT_A = the last parameter
SEND_PARAMETERS:
    pla
    jsr OSWRCH
    jsr WRITE_INT_A
    jmp CONTINUE_EXECUTION

;; MOVE: moves the graphics cursor, MOVE x,y, as PLOT 4.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
MOVE_STATEMENT:
    lda #PLOT_MOVE
    bne MOVE_DRAW                   ; always taken

;; DRAW: draws a line to a point, DRAW x,y, as PLOT 5.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; Entry: MOVE_DRAW = PLOTs with the PLOT number in A
DRAW_STATEMENT:
    lda #PLOT_DRAW
MOVE_DRAW:
    pha
    jsr EVALUATE_EXPRESSION_A                       ; x
    jmp PLOT_COORDINATES

;; PLOT: plots a point, line or triangle, PLOT k,x,y, with VDU 25,k,x;y;.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
;; Entry: PLOT_COORDINATES = takes x from the evaluator, reads ",y" and sends the VDU 25, with k on the 6502 stack
PLOT_STATEMENT:
    jsr EVALUATE_INTEGER_A                       ; k
    lda INT_A
    pha
    jsr CHECK_COMMA_B                       ; the comma
    jsr EVALUATE_EXPRESSION         ; x
PLOT_COORDINATES:
    jsr CONVERT_TO_INTEGER
    jsr PUSH_INTEGER
    jsr EVALUATE_COMMA_INTEGER      ; y
    jsr CHECK_END_OF_STATEMENT_B
    lda #VDU_PLOT
    jsr OSWRCH
    pla
    jsr OSWRCH                      ; k
    jsr POP_INTEGER_TO_WORK                       ; pop x into WORK
    lda WORK
    jsr OSWRCH
    lda WORK+1
    jsr OSWRCH
    jsr WRITE_INT_A                 ; y
    lda INT_A+1
    jsr OSWRCH
    jmp CONTINUE_EXECUTION

;; Sends the high byte of a VDU item that ended with a semicolon, part of <VDU_STATEMENT>.
VDU_STATEMENT_HIGH_BYTE:
    lda INT_A+1
    jsr OSWRCH

;; VDU: sends bytes to the VDU drivers, VDU item[,item...].
;;
;; Each item sends the low byte of its value; one followed by a semicolon sends the high byte after it, as a 16-bit
;; number. An item followed by anything else but the end of the statement starts the next item.
;; In: PTR_A, PTR_A_OFFSET = just after the keyword
VDU_STATEMENT:
    jsr GET_CHARACTER_A
VDU_STATEMENT_ITEM:
    cmp #':'
    beq VDU_STATEMENT_END
    cmp #CARRIAGE_RETURN
    beq VDU_STATEMENT_END
    cmp #TOKEN_ELSE
    beq VDU_STATEMENT_END
    dec PTR_A_OFFSET
    jsr EVALUATE_INTEGER_A
    jsr WRITE_INT_A
    jsr GET_CHARACTER_A
    cmp #','
    beq VDU_STATEMENT
    cmp #';'
    bne VDU_STATEMENT_ITEM
    beq VDU_STATEMENT_HIGH_BYTE     ; always taken
VDU_STATEMENT_END:
    jmp FINISH_STATEMENT_BACK_ONE

;; Sends the low byte of IntA to OSWRCH, through WRCHV.
;; In: INT_A = the byte, in its low byte
;; Uses: A
WRITE_INT_A:
    lda INT_A
    jmp (WRCHV)
