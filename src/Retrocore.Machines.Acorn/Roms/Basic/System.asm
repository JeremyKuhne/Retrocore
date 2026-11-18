;; REPEAT, reading lines, editing the program, RUN, BASIC's stack, loading and saving, the file statements and REPORT
;; ($BBE4-$BFFF).
;;
;; - REPEAT, and the routines that read a line from the keyboard with OSWORD 0, into <LINE_BUFFER> for immediate
;;   mode or into StrA for INPUT.
;; - Editing the program: <DELETE_LINE> and <INSERT_LINE>, which move the program in memory to take a line out or
;;   make room for one, and <FIND_PROGRAM_END>, which follows the lines to set TOP and reports "Bad program".
;; - RUN, and <CLEAR_VARIABLES> and <RESET_STACKS>, which CLEAR, RUN, NEW and the error handler share.
;; - BASIC's stack, which grows down from HIMEM towards the heap: pushing and popping integers, reals and strings,
;;   and <LOWER_BASIC_STACK>, which makes room on it and reports "No room" when it would meet the heap.
;; - The file statements: OSCLI, SAVE, LOAD and CHAIN, which build an OSFILE control block in zero page, and PTR#,
;;   EXT#, BPUT#, BGET#, OPENIN, OPENOUT, OPENUP and CLOSE#, which read a file handle after a #.
;; - <PRINT_INLINE> and REPORT.
;;
;; A program is kept at PAGE as a run of lines. PAGE holds a carriage return, and each line follows the carriage
;; return that ends the one before it: its number, high byte first, its length, its tokenised text and a carriage
;; return. The length counts all of these, from the number's high byte to the carriage return, so a pointer at the
;; carriage return before a line moves to the carriage return that ends it when the length is added. A line number
;; with bit 7 of its high byte set, &FF after the last line, ends the program, and TOP is the byte after that &FF.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------


ERROR_MISSING_HASH = $2D            ;; error &2D (45), "Missing #": a file statement without its # and handle

; The OS calls this part makes, by their numbers in A.
OSWORD_READ_LINE = $00              ;; OSWORD 0: reads a line from the input stream into memory
OSBYTE_READ_HIGH_ORDER_ADDRESS = $82 ;; OSBYTE &82: reads the high word of the I/O processor's addresses into X, Y
OSFILE_SAVE = $00                   ;; OSFILE 0: saves memory as a file, described by the control block
OSFILE_LOAD = $FF                   ;; OSFILE &FF: loads a file
OSARGS_READ_PTR = $00               ;; OSARGS 0, with a handle: reads the file's sequential pointer, PTR#
OSARGS_WRITE_PTR = $01              ;; OSARGS 1, with a handle: sets the file's sequential pointer
OSARGS_READ_EXT = $02               ;; OSARGS 2, with a handle: reads the file's length, EXT#
OSFIND_CLOSE = $00                  ;; OSFIND 0: closes the file whose handle is in Y, or all files when Y is 0
OSFIND_OPENIN = $40                 ;; OSFIND &40: opens a file for input
OSFIND_OPENOUT = $80                ;; OSFIND &80: opens a new file for output
OSFIND_OPENUP = $C0                 ;; OSFIND &C0: opens a file for input and output

; The OSWORD 0 control block the line readers build in the work bytes, &37-&3B.
LINE_INPUT_BLOCK = WORK             ;; the control block: first, the address to put the line at
LINE_INPUT_MAX_LENGTH = WORK + 2    ;; the most characters the line may have
LINE_INPUT_LOWEST = WORK + 3        ;; the lowest character code put in the line; lower ones are ignored
LINE_INPUT_HIGHEST = WORK + 4       ;; the highest character code put in the line
LINE_INPUT_LENGTH = $EE             ;; 238 characters: the longest line BASIC reads

; The OSFILE control block SAVE, LOAD and CHAIN build in the work bytes, &37-&48.
FILE_BLOCK = WORK                   ;; the control block: first, the address of the file name, ending with a return
FILE_BLOCK_LOAD = WORK + 2          ;; the load address, four bytes, low byte first
FILE_BLOCK_EXEC = WORK + 6          ;; the execution address; for a load, its low byte is 0 to load at FILE_BLOCK_LOAD
FILE_BLOCK_START = WORK + 10        ;; for a save, the address of the first byte saved, four bytes
FILE_BLOCK_END = WORK + 14          ;; for a save, the address after the last byte saved, four bytes

; <INSERT_LINE>'s work bytes.
NEW_LINE_TEXT = FP_B_SIGN           ;; a pointer to the text of the line being inserted, in <LINE_BUFFER>
NEW_LINE_LENGTH = FP_B_MANTISSA + 1 ;; the length of the line being inserted, as the program stores it

; ---------------------------------------------------------------------------------------------------------------------
; REPEAT
; ---------------------------------------------------------------------------------------------------------------------

;; REPEAT: starts a loop that runs until the condition after an UNTIL is TRUE. Syntax: REPEAT.
;;
;; Moves PTRA to the REPEAT token, with the offset 1 just past it, and pushes that position on the REPEAT stack for
;; UNTIL to go back to, then carries on with the next statement. Up to 20 loops can be open; a 21st raises "Too
;; many REPEATs" (error 44) at <TOO_MANY_REPEATS_ERROR>.
;; In:    Y = the offset of the REPEAT token from <PTR_A>
;; See:   <UNTIL_STATEMENT>
REPEAT_STATEMENT:
    ldx REPEAT_LEVEL
    cpx #REPEAT_STACK_HIGH - REPEAT_STACK_LOW
    bcs TOO_MANY_REPEATS_ERROR                       ; "Too many REPEATs"
    jsr ADVANCE_PTR_A                       ; PTRA to the token, the offset to 1, and check for Escape
    lda PTR_A
    sta REPEAT_STACK_LOW,x
    lda PTR_A+1
    sta REPEAT_STACK_HIGH,x
    inc REPEAT_LEVEL
    jmp EXECUTE_STATEMENT

; ---------------------------------------------------------------------------------------------------------------------
; Reading a line, and printing a new line
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a line from the keyboard into StrA, for INPUT.
;;
;; The characters go to <STRING_BUFFER>, ending with a carriage return; the caller stores the length in
;; <STRING_LENGTH>.
;; Out:   Y = the number of characters read, without the carriage return, COUNT = 0, A = 0
;; Uses:  X, WORK..WORK+4
;; See:   <READ_LINE>
READ_LINE_TO_STRING:
    ldy #<STRING_BUFFER
    lda #>STRING_BUFFER
    bne READ_LINE                   ; always taken

;; Prints a prompt and reads a line from the keyboard into <LINE_BUFFER>, for immediate mode and AUTO.
;; In:    A = the prompt character
;; Out:   Y = the number of characters read, without the carriage return, COUNT = 0, A = 0
;; Uses:  X, WORK..WORK+4
;; See:   <READ_LINE>
READ_LINE_WITH_PROMPT:
    jsr PRINT_CHARACTER
    ldy #<LINE_BUFFER
    lda #>LINE_BUFFER

;; Reads a line from the keyboard with OSWORD 0, then zeroes COUNT.
;;
;; Builds OSWORD 0's control block at <LINE_INPUT_BLOCK>: up to 238 characters, from space to &FF, so control
;; characters are left out of the line. The line ends with a carriage return. Escape raises "Escape" (error 17).
;; In:    Y/A = the address to read the line into, low byte in Y
;; Out:   Y = the number of characters read, without the carriage return, COUNT = 0, A = 0
;; Uses:  X, WORK..WORK+4
READ_LINE:
    sty LINE_INPUT_BLOCK
    sta LINE_INPUT_BLOCK+1
    lda #LINE_INPUT_LENGTH
    sta LINE_INPUT_MAX_LENGTH
    lda #' '
    sta LINE_INPUT_LOWEST
    ldy #$FF
    sty LINE_INPUT_HIGHEST
    iny                             ; Y = 0, the control block's high byte
    ldx #LINE_INPUT_BLOCK
    tya                             ; A = OSWORD_READ_LINE
    jsr OSWORD
    bcc RESET_COUNT                 ; carry set: the line ended with Escape
    jmp ESCAPE_ERROR                       ; "Escape"

;; Starts a new line: prints a carriage return and line feed with OSNEWL and zeroes COUNT.
;;
;; Falls into <RESET_COUNT>.
;; Out:   A = 0, COUNT = 0
;; Keeps: X, Y
PRINT_NEWLINE:
    jsr OSNEWL

;; Zeroes COUNT, the number of characters printed since the last new line.
;; Out:   A = 0, zero = set, COUNT = 0
;; Keeps: X, Y
RESET_COUNT:
    lda #$00
    sta COUNT
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Editing the program
; ---------------------------------------------------------------------------------------------------------------------

;; Deletes a line from the program, moving the lines after it down over it.
;;
;; <FIND_LINE> finds the line. The rest of the program, from the carriage return that ends the line to the end
;; marker, is copied down to the carriage return before it, a line at a time: the copy stops at each carriage
;; return, then copies the next line's number and length with <MOVE_PROGRAM_BYTE> before going on with its text,
;; and stops at the end marker. TOP is left at the byte after the end marker.
;; In:    INT_A..INT_A+1 = the line's number
;; Out:   carry = clear when the line was deleted, set when there is no such line, TOP = the end of the program,
;;        FP_B_EXPONENT..FP_B_MANTISSA = the carriage return before the deleted line, or before the first line with a
;;        greater number when there was none
;; Uses:  A, Y, WORK..WORK+1
;; Keeps: X
DELETE_LINE:
    jsr FIND_LINE
    bcs DELETE_LINE_RETURN          ; no such line
    lda FP_B_EXPONENT               ; FIND_LINE points at the length byte: back 3 to the return before the line
    sbc #$02                        ; (carry clear: 3)
    sta WORK
    sta FP_B_EXPONENT
    sta TOP
    lda FP_B_MANTISSA
    sbc #$00
    sta WORK+1
    sta TOP+1
    sta FP_B_MANTISSA
    ldy #$03
    lda (WORK),y                    ; the line's length
    clc
    adc WORK                        ; WORK, the source: the return that ends the line
    sta WORK
    bcc DELETE_LINE_MOVE
    inc WORK+1
DELETE_LINE_MOVE:
    ldy #$00                        ; TOP, the destination: the return before the line
DELETE_LINE_TEXT:
    lda (WORK),y
    sta (TOP),y
    cmp #CARRIAGE_RETURN
    beq DELETE_LINE_END_OF_LINE
DELETE_LINE_NEXT:
    iny
    bne DELETE_LINE_TEXT
    inc WORK+1
    inc TOP+1
    bne DELETE_LINE_TEXT            ; always taken
DELETE_LINE_END_OF_LINE:
    iny
    bne DELETE_LINE_NUMBER
    inc WORK+1
    inc TOP+1
DELETE_LINE_NUMBER:
    lda (WORK),y                    ; the next line's number, high byte
    sta (TOP),y
    bmi DELETE_LINE_DONE            ; the end marker
    jsr MOVE_PROGRAM_BYTE           ; the number's low byte
    jsr MOVE_PROGRAM_BYTE           ; the length
    jmp DELETE_LINE_NEXT
DELETE_LINE_DONE:
    jsr ADVANCE_TOP                 ; carry set from the compare: TOP past the end marker
    clc
DELETE_LINE_RETURN:
    rts

;; Copies the next byte of the program for <DELETE_LINE>.
;; In:    WORK = the source, TOP = the destination, Y = the offset of the byte before
;; Out:   Y = the offset of the byte copied, A = the byte, WORK+1 and TOP+1 advanced when Y wrapped
;; Keeps: X
MOVE_PROGRAM_BYTE:
    iny
    bne MOVE_PROGRAM_BYTE_COPY
    inc TOP+1
    inc WORK+1
MOVE_PROGRAM_BYTE_COPY:
    lda (WORK),y
    sta (TOP),y
    rts

;; Puts a typed line into the program, replacing any line with the same number; a line with no text only deletes.
;;
;; <DELETE_LINE> first takes out any line with that number, leaving FP_B_EXPONENT..FP_B_MANTISSA at the carriage
;; return the new line goes after. If the line has text, TOP is raised by the line's length and checked against
;; HIMEM; the program from that carriage return to the old TOP is then moved up, a byte at a time from the top
;; down, and the line's number, length and text, with its carriage return, are written into the gap.
;;
;; When the line does not fit, the old line with that number has already been deleted. <FIND_PROGRAM_END> puts TOP
;; back, <CLEAR_VARIABLES> clears the variables, and the error is "LINE space" (error 0).
;; In:    Y = the offset in <LINE_BUFFER> of the line's text, after its number, INT_A..INT_A+1 = the line number
;; Out:   TOP = the new end of the program
;; Uses:  A, X, Y, WORK..WORK+3, FP_B..FP_B_MANTISSA+1
;; See:   <DELETE_LINE>
INSERT_LINE:
    sty NEW_LINE_TEXT
    jsr DELETE_LINE
    ldy #>LINE_BUFFER
    sty NEW_LINE_TEXT+1
    ldy #$00
    lda #CARRIAGE_RETURN
    cmp (NEW_LINE_TEXT),y
    beq INSERT_LINE_DONE            ; no text: the line is only deleted
INSERT_LINE_MEASURE:
    iny
    cmp (NEW_LINE_TEXT),y
    bne INSERT_LINE_MEASURE
    iny                             ; the text and its return, and three bytes for the number and the length
    iny
    iny
    sty NEW_LINE_LENGTH
    inc NEW_LINE_LENGTH
    lda TOP                         ; WORK+2: the old TOP, the first byte to move
    sta WORK+2
    lda TOP+1
    sta WORK+3
    jsr ADVANCE_TOP                 ; carry set from the compare: TOP up by the line's length
    sta WORK                        ; WORK: the new TOP, where that byte goes
    lda TOP+1
    sta WORK+1
    dey                             ; Y = 0
    lda HIMEM
    cmp TOP
    lda HIMEM+1
    sbc TOP+1
    bcs INSERT_LINE_MOVE_UP         ; the new TOP is no higher than HIMEM
    jsr FIND_PROGRAM_END
    jsr CLEAR_VARIABLES
    brk
    .byte $00
    .byte TOKEN_LINE, " space", 0
INSERT_LINE_MOVE_UP:
    lda (WORK+2),y
    sta (WORK),y
    tya
    bne INSERT_LINE_NEXT
    dec WORK+3                      ; Y goes from 0 to &FF: down a page
    dec WORK+1
INSERT_LINE_NEXT:
    dey
    tya                             ; carry set: the address of the byte just moved
    adc WORK+2
    ldx WORK+3
    bcc INSERT_LINE_COMPARE
    inx
INSERT_LINE_COMPARE:
    cmp FP_B_EXPONENT
    txa
    sbc FP_B_MANTISSA
    bcs INSERT_LINE_MOVE_UP         ; until it is below the return the line goes after
    sec
    ldy #$01
    lda INT_A+1
    sta (FP_B_EXPONENT),y           ; the line number, high byte first
    iny
    lda INT_A
    sta (FP_B_EXPONENT),y
    iny
    lda NEW_LINE_LENGTH
    sta (FP_B_EXPONENT),y
    jsr ADVANCE_LINE_POINTER_BY_Y   ; carry set: 4, to where the text goes
    ldy #$FF
INSERT_LINE_TEXT:
    iny
    lda (NEW_LINE_TEXT),y
    sta (FP_B_EXPONENT),y
    cmp #CARRIAGE_RETURN
    bne INSERT_LINE_TEXT
INSERT_LINE_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; RUN, CLEAR and resetting the stacks
; ---------------------------------------------------------------------------------------------------------------------

;; RUN: clears the variables and runs the program from its first line. Syntax: RUN.
;;
;; Falls into <RUN_PROGRAM>.
RUN_STATEMENT:
    jsr CHECK_END_OF_STATEMENT

;; Clears the variables and the stacks and runs the program at PAGE from the start, for RUN and CHAIN.
;;
;; Sets PTRA to PAGE, the carriage return before the first line, and enters the interpreter at <EXECUTE_LINE>, which
;; resets ON ERROR and the 6502 stack and goes on from there into the program's first line.
RUN_PROGRAM:
    jsr CLEAR_VARIABLES
    lda PAGE_HIGH
    sta PTR_A+1
    stx PTR_A                       ; X = 0
    jmp EXECUTE_LINE

;; Clears the variables, the FN and PROC lists and the stacks, the work CLEAR does.
;;
;; Sets LOMEM and the heap's top to TOP, so that the variables are forgotten, then resets the stacks and the DATA
;; pointer with <RESET_STACKS> and empties the variable lists with <CLEAR_VARIABLE_LISTS>, into which it falls. The
;; resident integers @% and A% to Z% are kept.
;; Out:   A = 0, X = 0, zero = set
;; Keeps: Y
CLEAR_VARIABLES:
    lda TOP
    sta LOMEM
    sta HEAP
    lda TOP+1
    sta LOMEM+1
    sta HEAP+1
    jsr RESET_STACKS

;; Empties the variable lists and the FN and PROC lists, by zeroing their heads at <VARIABLE_LISTS>.
;; Out:   A = 0, X = 0, zero = set
;; Keeps: Y
CLEAR_VARIABLE_LISTS:
    ldx #$80                        ; &0480-&04FF, from the top down
    lda #$00
CLEAR_VARIABLE_LISTS_LOOP:
    sta VARIABLE_LISTS-1,x
    dex
    bne CLEAR_VARIABLE_LISTS_LOOP
    rts

;; Empties BASIC's stack and the REPEAT, FOR and GOSUB stacks, and sets the DATA pointer back to PAGE.
;; Out:   A = 0
;; Keeps: X, Y
RESET_STACKS:
    lda PAGE_HIGH
    sta DATA_POINTER+1
    lda HIMEM
    sta BASIC_STACK
    lda HIMEM+1
    sta BASIC_STACK+1
    lda #$00
    sta REPEAT_LEVEL
    sta FOR_LEVEL
    sta GOSUB_LEVEL
    sta DATA_POINTER
    rts

; ---------------------------------------------------------------------------------------------------------------------
; BASIC's stack
; ---------------------------------------------------------------------------------------------------------------------

;; Pushes FPA on BASIC's stack as a packed real number, five bytes: the exponent, then the mantissa, most
;; significant byte first, with the sign in its top bit.
;;
;; Raises "No room" (error 0) if the stack would reach the heap.
;; In:    FP_A = the number
;; Out:   Y = 4
;; Uses:  A, FP_A_SIGN (left with only its sign bit)
;; Keeps: X
PUSH_REAL:
    lda BASIC_STACK
    sec
    sbc #$05
    jsr LOWER_BASIC_STACK
    ldy #$00
    lda FP_A_EXPONENT
    sta (BASIC_STACK),y
    iny
    lda FP_A_SIGN
    and #$80
    sta FP_A_SIGN
    lda FP_A_MANTISSA
    and #$7F                        ; the sign takes the mantissa's top bit, which is always set
    ora FP_A_SIGN
    sta (BASIC_STACK),y
    iny
    lda FP_A_MANTISSA+1
    sta (BASIC_STACK),y
    iny
    lda FP_A_MANTISSA+2
    sta (BASIC_STACK),y
    iny
    lda FP_A_MANTISSA+3
    sta (BASIC_STACK),y
    rts

;; Takes the packed real number on top of BASIC's stack off it, and points FP_POINTER at it.
;;
;; The number is not loaded into FPA: its five bytes stay where they were, just below the stack, for the caller to
;; use through FP_POINTER, as an operand of the floating point routines, before anything else is pushed.
;; Out:   FP_POINTER = the number
;; Uses:  A
;; Keeps: X, Y
POP_REAL_POINTER:
    lda BASIC_STACK
    clc
    sta FP_POINTER
    adc #$05
    sta BASIC_STACK
    lda BASIC_STACK+1
    sta FP_POINTER+1
    adc #$00
    sta BASIC_STACK+1
    rts

;; Pushes the value in the accumulator of the type in A on BASIC's stack: StrA, FPA or IntA.
;; In:    A = the type: zero for a string, negative for a real, otherwise an integer, with the flags set from it
;; Out:   Y = the offset of the last byte written
;; Uses:  A
;; Keeps: X
;; Entry: PUSH_INTEGER = pushes IntA, four bytes, low byte first
PUSH_VALUE:
    beq PUSH_STRING
    bmi PUSH_REAL
PUSH_INTEGER:
    lda BASIC_STACK
    sec
    sbc #$04
    jsr LOWER_BASIC_STACK
    ldy #$03
    lda INT_A+3
    sta (BASIC_STACK),y
    dey
    lda INT_A+2
    sta (BASIC_STACK),y
    dey
    lda INT_A+1
    sta (BASIC_STACK),y
    dey
    lda INT_A
    sta (BASIC_STACK),y
    rts

;; Pushes StrA on BASIC's stack: its length byte, then its characters above it.
;;
;; Raises "No room" (error 0) if the stack would reach the heap.
;; In:    STRING_BUFFER = the characters, STRING_LENGTH = the length
;; Out:   Y = 0
;; Uses:  A
;; Keeps: X
PUSH_STRING:
    clc                             ; down by the length and one more, for the length byte
    lda BASIC_STACK
    sbc STRING_LENGTH
    jsr LOWER_BASIC_STACK
    ldy STRING_LENGTH
    beq PUSH_STRING_LENGTH
PUSH_STRING_LOOP:
    lda STRING_BUFFER-1,y
    sta (BASIC_STACK),y
    dey
    bne PUSH_STRING_LOOP
PUSH_STRING_LENGTH:
    lda STRING_LENGTH
    sta (BASIC_STACK),y
    rts

;; Pops the string on top of BASIC's stack into StrA.
;;
;; Copies the characters to <STRING_BUFFER> and the length to <STRING_LENGTH>, then falls into <DROP_STRING>.
;; Out:   STRING_BUFFER, STRING_LENGTH = the string
;; Uses:  A, Y
;; Keeps: X
POP_STRING:
    ldy #$00
    lda (BASIC_STACK),y
    sta STRING_LENGTH
    beq DROP_STRING
    tay
POP_STRING_LOOP:
    lda (BASIC_STACK),y
    sta STRING_BUFFER-1,y
    dey
    bne POP_STRING_LOOP

;; Takes the string on top of BASIC's stack off it without reading it.
;; Out:   Y = 0
;; Uses:  A
;; Keeps: X
;; Entry: DROP_STACK_BYTES = raises the stack pointer by A plus the carry
DROP_STRING:
    ldy #$00
    lda (BASIC_STACK),y
    sec                             ; the length, and one for the length byte
DROP_STACK_BYTES:
    adc BASIC_STACK
    sta BASIC_STACK
    bcc DROP_INTEGER_RETURN
    inc BASIC_STACK+1
    rts

;; Pops the integer on top of BASIC's stack into IntA.
;;
;; Falls into <DROP_INTEGER>.
;; Out:   INT_A = the integer, Y = 0
;; Uses:  A
;; Keeps: X
POP_INTEGER:
    ldy #$03
    lda (BASIC_STACK),y
    sta INT_A+3
    dey
    lda (BASIC_STACK),y
    sta INT_A+2
    dey
    lda (BASIC_STACK),y
    sta INT_A+1
    dey
    lda (BASIC_STACK),y
    sta INT_A

;; Takes the integer on top of BASIC's stack off it without reading it.
;; Uses:  A
;; Keeps: X, Y
DROP_INTEGER:
    clc
    lda BASIC_STACK
    adc #$04
    sta BASIC_STACK
    bcc DROP_INTEGER_RETURN
    inc BASIC_STACK+1
DROP_INTEGER_RETURN:
    rts

;; Pops the integer on top of BASIC's stack into WORK..WORK+3.
;;
;; Falls into <POP_INTEGER_TO>.
;; Out:   WORK..WORK+3 = the integer, low byte first, X = WORK, Y = 0
;; Uses:  A
POP_INTEGER_TO_WORK:
    ldx #WORK

;; Pops the integer on top of BASIC's stack into four bytes of zero page.
;; In:    X = the zero page address to put it at, low byte first
;; Out:   Y = 0
;; Uses:  A
;; Keeps: X
POP_INTEGER_TO:
    ldy #$03
    lda (BASIC_STACK),y
    sta $03,x
    dey
    lda (BASIC_STACK),y
    sta $02,x
    dey
    lda (BASIC_STACK),y
    sta $01,x
    dey
    lda (BASIC_STACK),y
    sta $00,x
    clc
    lda BASIC_STACK
    adc #$04
    sta BASIC_STACK
    bcc DROP_INTEGER_RETURN
    inc BASIC_STACK+1
    rts

;; Lowers BASIC's stack pointer to make room for up to 255 bytes, and checks that it stays above the heap.
;;
;; The caller subtracts the number of bytes from the pointer's low byte and passes the result, and the borrow, here.
;; If the stack pointer would then be below the top of the heap, HEAP, the error is "No room" (error 0), at
;; <NO_ROOM_ERROR>; the pointer may come down to HEAP itself.
;; In:    A = the stack pointer's new low byte, carry = clear to take one from its high byte as well
;; Out:   BASIC_STACK = the lowered stack pointer, Y = its high byte
;; Keeps: A, X
LOWER_BASIC_STACK:
    sta BASIC_STACK
    bcs LOWER_BASIC_STACK_CHECK
    dec BASIC_STACK+1
LOWER_BASIC_STACK_CHECK:
    ldy BASIC_STACK+1
    cpy HEAP+1
    bcc LOWER_BASIC_STACK_NO_ROOM
    bne LOWER_BASIC_STACK_DONE
    cmp HEAP
    bcc LOWER_BASIC_STACK_NO_ROOM
LOWER_BASIC_STACK_DONE:
    rts
LOWER_BASIC_STACK_NO_ROOM:
    jmp NO_ROOM_ERROR                       ; "No room"

;; Stores IntA in four bytes of zero page, low byte first.
;; In:    X = the zero page address, INT_A = the value
;; Uses:  A
;; Keeps: X, Y
STORE_INT_A:
    lda INT_A
    sta $00,x
    lda INT_A+1
    sta $01,x
    lda INT_A+2
    sta $02,x
    lda INT_A+3
    sta $03,x
    rts

;; Adds Y to the line pointer at FP_B_EXPONENT..FP_B_MANTISSA, the pointer <FIND_LINE> leaves.
;; In:    Y = the number to add
;; Out:   Y = 1
;; Uses:  A
;; Keeps: X
;; Entry: ADVANCE_LINE_POINTER_BY_Y = adds Y plus the carry
ADVANCE_LINE_POINTER:
    clc
ADVANCE_LINE_POINTER_BY_Y:
    tya
    adc FP_B_EXPONENT
    sta FP_B_EXPONENT
    bcc ADVANCE_LINE_POINTER_DONE
    inc FP_B_MANTISSA
ADVANCE_LINE_POINTER_DONE:
    ldy #$01
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Loading the program, and finding its end
; ---------------------------------------------------------------------------------------------------------------------

;; Loads a program at PAGE, for LOAD and CHAIN, then checks it and sets TOP.
;;
;; Evaluates the file name with <SET_UP_FILE_BLOCK>, which sets the load address to PAGE, sets the execution
;; address's low byte to zero so that OSFILE loads at that address, and calls OSFILE &FF. It falls into
;; <FIND_PROGRAM_END>.
;; Out:   TOP = the end of the program loaded, Y = 1, zero = clear
;; Uses:  A, X, WORK..FP_B_EXPONENT
LOAD_PROGRAM:
    jsr SET_UP_FILE_BLOCK
    tay                             ; A = 0: Y, the control block's high byte
    lda #OSFILE_LOAD
    sty FILE_BLOCK_EXEC
    ldx #FILE_BLOCK
    jsr OSFILE

;; Sets TOP to the end of the program at PAGE, following the lines' lengths, and checks that the program is sound.
;;
;; Each line must follow a carriage return and have a length that is not zero. If one does not, the program is
;; reported as "Bad program", which is a message and not an error: it is printed with <PRINT_INLINE> and BASIC goes
;; back to immediate mode. When the end marker is found, TOP is set to the byte after it, through <ADVANCE_TOP>,
;; into which this falls. Callers rely on zero being clear at the end, to branch always.
;; Out:   TOP = the end of the program, Y = 1, zero = clear
;; Uses:  A
;; Keeps: X
FIND_PROGRAM_END:
    lda PAGE_HIGH
    sta TOP+1
    ldy #$00
    sty TOP
    iny
FIND_PROGRAM_END_LOOP:
    dey                             ; Y = 0: the carriage return before the line
    lda (TOP),y
    cmp #CARRIAGE_RETURN
    bne BAD_PROGRAM
    iny
    lda (TOP),y                     ; the line number's high byte
    bmi FIND_PROGRAM_END_FOUND      ; the end marker
    ldy #$03
    lda (TOP),y                     ; the line's length
    beq BAD_PROGRAM
    clc
    jsr ADVANCE_TOP_BY_A            ; TOP to the carriage return that ends the line
    bne FIND_PROGRAM_END_LOOP       ; always taken: Y = 1
FIND_PROGRAM_END_FOUND:
    iny                             ; Y = 2: TOP is the return before the end marker
    clc

;; Adds Y, and the carry, to TOP.
;;
;; <FIND_PROGRAM_END>, <DELETE_LINE> and <INSERT_LINE> use it to move TOP over a line or past the end marker.
;; In:    Y = the number to add, carry = set to add one more
;; Out:   A = TOP's new low byte, Y = 1, zero = clear
;; Keeps: X
;; Entry: ADVANCE_TOP_BY_A = adds A, and the carry, instead
ADVANCE_TOP:
    tya
ADVANCE_TOP_BY_A:
    adc TOP
    sta TOP
    bcc ADVANCE_TOP_DONE
    inc TOP+1
ADVANCE_TOP_DONE:
    ldy #$01
    rts

;; Prints "Bad program" and goes back to immediate mode, for <FIND_PROGRAM_END>.
;;
;; The NOP after the message ends it for <PRINT_INLINE>, since its bit 7 is set, and is the instruction that runs
;; next.
BAD_PROGRAM:
    jsr PRINT_INLINE
    .byte CARRIAGE_RETURN, "Bad program", CARRIAGE_RETURN
    nop
    jmp IMMEDIATE_MODE

; ---------------------------------------------------------------------------------------------------------------------
; Strings for the OS, OSCLI, SAVE, LOAD and CHAIN
; ---------------------------------------------------------------------------------------------------------------------

;; Points WORK at StrA and ends the string with a carriage return, as the OS calls want a file name or command.
;;
;; Falls into <TERMINATE_STRING>.
;; Out:   WORK = STRING_BUFFER, Y = STRING_LENGTH, A = a carriage return
;; Keeps: X
POINT_AT_STRING:
    lda #<STRING_BUFFER
    sta WORK
    lda #>STRING_BUFFER
    sta WORK+1

;; Puts a carriage return after the string in StrA.
;; Out:   Y = STRING_LENGTH, A = a carriage return
;; Keeps: X
TERMINATE_STRING:
    ldy STRING_LENGTH
    lda #CARRIAGE_RETURN
    sta STRING_BUFFER,y
    rts

;; OSCLI: passes a string to the MOS's command line interpreter. Syntax: OSCLI string.
;;
;; Unlike a line starting with *, the command can be built by an expression, such as OSCLI "KEY0 "+A$.
OSCLI_STATEMENT:
    jsr EVALUATE_OS_STRING
    ldx #<STRING_BUFFER
    ldy #>STRING_BUFFER
    jsr OSCLI
    jmp CONTINUE_EXECUTION

;; Raises "Type mismatch" (error 6) for <EVALUATE_OS_STRING>, when the expression is not a string.
EVALUATE_OS_STRING_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Evaluates a string expression at PTRA for an OS call, and checks that the statement ends after it.
;;
;; The string is left in StrA, ending with a carriage return, with WORK pointing at it. Anything other than a string
;; raises "Type mismatch" (error 6), and anything after it but the end of the statement "Syntax error".
;; Out:   STRING_BUFFER = the string, WORK = STRING_BUFFER, PTR_A moved past the statement, Y = 1
;; Uses:  A, X, PTR_B
EVALUATE_OS_STRING:
    jsr EVALUATE_EXPRESSION_A
    bne EVALUATE_OS_STRING_MISMATCH ; not a string
    jsr POINT_AT_STRING
    jmp CHECK_END_OF_EXPRESSION

;; Evaluates a file name and starts an OSFILE control block for it at <FILE_BLOCK>, loading at PAGE.
;;
;; Sets the block's file name address to StrA and its load address to PAGE in the I/O processor's memory, the
;; high word from <READ_HIGH_ORDER_ADDRESS>, which this falls into.
;; Out:   FILE_BLOCK..FILE_BLOCK_LOAD+3 set, A = 0, X/Y = the high word of addresses
;; See:   <EVALUATE_OS_STRING>
SET_UP_FILE_BLOCK:
    jsr EVALUATE_OS_STRING
    dey                             ; Y = 0: PAGE's low byte
    sty FILE_BLOCK_LOAD
    lda PAGE_HIGH
    sta FILE_BLOCK_LOAD+1

;; Reads the high word of the I/O processor's addresses with OSBYTE &82 and puts it in the load address of
;; <FILE_BLOCK>.
;;
;; The word is &FFFF in a BBC Micro without a second processor, so that addresses refer to its own memory.
;; Out:   X = the low byte of the word, Y = its high byte, FILE_BLOCK_LOAD+2..FILE_BLOCK_LOAD+3 = the word, A = 0
READ_HIGH_ORDER_ADDRESS:
    lda #OSBYTE_READ_HIGH_ORDER_ADDRESS
    jsr OSBYTE
    stx FILE_BLOCK_LOAD+2
    sty FILE_BLOCK_LOAD+3
    lda #$00
    rts

;; SAVE: saves the program as a file. Syntax: SAVE "name".
;;
;; Finds TOP with <FIND_PROGRAM_END>, then saves PAGE to TOP with OSFILE 0. The load address is PAGE and the
;; execution address &8023, BASIC's start-up code at <BASIC_START>, both in the I/O processor's memory.
SAVE_COMMAND:
    jsr FIND_PROGRAM_END
    lda TOP
    sta FILE_BLOCK_END
    lda TOP+1
    sta FILE_BLOCK_END+1
    lda #<BASIC_START
    sta FILE_BLOCK_EXEC
    lda #>BASIC_START
    sta FILE_BLOCK_EXEC+1
    lda PAGE_HIGH
    sta FILE_BLOCK_START+1
    jsr SET_UP_FILE_BLOCK
    stx FILE_BLOCK_EXEC+2           ; the high word of each address
    sty FILE_BLOCK_EXEC+3
    stx FILE_BLOCK_START+2
    sty FILE_BLOCK_START+3
    stx FILE_BLOCK_END+2
    sty FILE_BLOCK_END+3
    sta FILE_BLOCK_START            ; A = 0: PAGE's low byte
    tay                             ; Y = 0, the control block's high byte; A = OSFILE_SAVE
    ldx #FILE_BLOCK
    jsr OSFILE
    jmp CONTINUE_EXECUTION

;; LOAD: loads a program, replacing the one in memory, and clears the variables. Syntax: LOAD "name".
LOAD_COMMAND:
    jsr LOAD_PROGRAM
    jmp WARM_START

;; CHAIN: loads a program and runs it. Syntax: CHAIN "name".
CHAIN_STATEMENT:
    jsr LOAD_PROGRAM
    jmp RUN_PROGRAM

; ---------------------------------------------------------------------------------------------------------------------
; The file statements and functions
; ---------------------------------------------------------------------------------------------------------------------

;; PTR#: moves a file's sequential pointer. Syntax: PTR#handle=value.
;;
;; Sets it with OSARGS 1, from IntA. The value must be a number: a string raises "Type mismatch" (error 6).
PTR_STATEMENT:
    jsr READ_HANDLE_A
    pha
    jsr EVALUATE_EQUALS                       ; "=" and the value, to the end of the statement
    jsr CONVERT_TO_INTEGER                       ; as an integer
    pla
    tay
    ldx #INT_A
    lda #OSARGS_WRITE_PTR
    jsr OSARGS
    jmp CONTINUE_EXECUTION

;; EXT#: gives the length of an open file. Syntax: EXT#handle.
;;
;; Falls into <PTR_FUNCTION> with the carry set, which makes its OSARGS call 2 instead of 0.
;; Out:   INT_A = the length, A = &40, an integer
EXT_FUNCTION:
    sec

;; PTR#: gives the position of a file's sequential pointer. Syntax: PTR#handle.
;;
;; The two ROLs turn the carry into OSARGS's reason: 0 to read the pointer, 2 to read the length for EXT#. The
;; expression evaluator calls this with the carry clear, from its compare of the token.
;; In:    carry = clear for PTR#, set for EXT#
;; Out:   INT_A = the value, A = &40, an integer
PTR_FUNCTION:
    lda #$00
    rol a
    rol a                           ; OSARGS_READ_PTR, or OSARGS_READ_EXT from the carry
    pha
    jsr READ_HANDLE_B
    ldx #INT_A
    pla
    jsr OSARGS
    lda #$40                        ; an integer
    rts

;; BPUT#: writes a byte to a file. Syntax: BPUT#handle,value.
;;
;; Writes the low byte of the value with OSBPUT.
BPUT_STATEMENT:
    jsr READ_HANDLE_A
    pha
    jsr CHECK_COMMA_B                       ; ","
    jsr EVALUATE_EXPRESSION_AND_END                       ; the value, to the end of the statement
    jsr CONVERT_TO_INTEGER                       ; as an integer
    pla
    tay
    lda INT_A
    jsr OSBPUT
    jmp CONTINUE_EXECUTION

;; BGET#: reads a byte from a file. Syntax: BGET#handle.
;; Out:   INT_A = the byte, A = &40, an integer
BGET_FUNCTION:
    jsr READ_HANDLE_B
    jsr OSBGET
    jmp LOAD_INT_A_BYTE

;; OPENIN: opens a file for input and gives its handle, or 0 when it cannot be opened. Syntax: OPENIN "name".
;; Out:   INT_A = the handle, A = &40, an integer
OPENIN_FUNCTION:
    lda #OSFIND_OPENIN
    bne OPEN_FILE                   ; always taken

;; OPENOUT: opens a new file for output and gives its handle. Syntax: OPENOUT "name".
;; Out:   INT_A = the handle, A = &40, an integer
OPENOUT_FUNCTION:
    lda #OSFIND_OPENOUT
    bne OPEN_FILE                   ; always taken

;; OPENUP: opens a file for input and output and gives its handle, or 0 when it cannot be opened. Syntax:
;; OPENUP "name".
;;
;; Falls into <OPEN_FILE>.
;; Out:   INT_A = the handle, A = &40, an integer
OPENUP_FUNCTION:
    lda #OSFIND_OPENUP

;; Opens the file named by the factor at PTRB with OSFIND, for OPENIN, OPENOUT and OPENUP, and returns its handle.
;;
;; The name must be a string: anything else raises "Type mismatch" (error 6).
;; In:    A = the OSFIND reason
;; Out:   INT_A = the handle, A = &40, an integer
OPEN_FILE:
    pha
    jsr EVALUATE_FACTOR
    bne OPEN_FILE_MISMATCH          ; not a string
    jsr TERMINATE_STRING
    ldx #<STRING_BUFFER
    ldy #>STRING_BUFFER
    pla
    jsr OSFIND
    jmp LOAD_INT_A_BYTE
OPEN_FILE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR                       ; "Type mismatch"

;; CLOSE#: closes a file, or every open file when the handle is 0. Syntax: CLOSE#handle.
CLOSE_STATEMENT:
    jsr READ_HANDLE_A
    jsr CHECK_END_OF_STATEMENT_B
    ldy INT_A
    lda #OSFIND_CLOSE
    jsr OSFIND
    jmp CONTINUE_EXECUTION

;; Reads a # and a file handle from the statement at PTRA, for the file statements.
;;
;; Copies PTRA to PTRB and falls into <READ_HANDLE_B>.
;; Out:   A = Y = the handle, the low byte of INT_A
;; Uses:  X
READ_HANDLE_A:
    lda PTR_A_OFFSET
    sta PTR_B_OFFSET
    lda PTR_A
    sta PTR_B
    lda PTR_A+1
    sta PTR_B+1

;; Reads a # and a file handle at PTRB: the next character, after any spaces, must be #, and the factor after it a
;; number.
;;
;; A missing # raises "Missing #" (error 45), and a string after it "Type mismatch" (error 6).
;; Out:   A = Y = the handle, the low byte of INT_A
;; Uses:  X
READ_HANDLE_B:
    jsr GET_CHARACTER_B
    cmp #'#'
    bne MISSING_HASH
    jsr EVALUATE_INTEGER_FACTOR                       ; the handle, as an integer
    ldy INT_A
    tya
    rts

;; Raises "Missing #" (error 45), for <READ_HANDLE_B>.
MISSING_HASH:
    brk
    .byte ERROR_MISSING_HASH
    .byte "Missing #",0

;; Prints the text that follows the JSR to it, and returns to the first byte after the text with bit 7 set.
;;
;; The text is in the code, after the JSR. It is printed with OSASCI, so a carriage return also moves to a new line,
;; up to the first byte with bit 7 set. That byte is not printed: it is the first instruction run after the call,
;; which carries on there with a JMP, so it must be an opcode with bit 7 set. Each caller chooses that instruction.
;; Uses:  A, Y, WORK..WORK+1
;; Keeps: X
PRINT_INLINE:
    pla                             ; the return address: the last byte of the JSR
    sta WORK
    pla
    sta WORK+1
    ldy #$00
    beq PRINT_INLINE_NEXT           ; always taken
PRINT_INLINE_LOOP:
    jsr OSASCI
PRINT_INLINE_NEXT:
    jsr ADVANCE_WORK_AND_READ                       ; WORK up by one and the byte there
    bpl PRINT_INLINE_LOOP
    jmp (WORK)

;; REPORT: prints the message of the last error. Syntax: REPORT.
;;
;; Starts a new line, then prints the message after the error number of the BRK that <ERROR_POINTER> points to,
;; up to its zero, expanding any tokens in it, such as the LINE of "LINE space".
REPORT_STATEMENT:
    jsr CHECK_END_OF_STATEMENT
    jsr PRINT_NEWLINE
    ldy #$01                        ; past the error number
REPORT_STATEMENT_LOOP:
    lda (ERROR_POINTER),y
    beq REPORT_STATEMENT_DONE
    jsr PRINT_CHARACTER_OR_TOKEN
    iny
    bne REPORT_STATEMENT_LOOP
REPORT_STATEMENT_DONE:
    jmp CONTINUE_EXECUTION

;; Seven bytes at the end of the ROM, after the last routine: a zero, "Roger" and a zero.
;;
;; Nothing in the ROM refers to them.
UNREFERENCED_END_BYTES:
    .byte 0, "Roger", 0
    .assert * = $C000, "BASIC fills the ROM to &BFFF."

; The BASIC ROM User Guide documents these routines at these addresses, for programs that call them.
    .assert PRINT_NEWLINE = $BC25, "The BASIC ROM User Guide documents PRINT_NEWLINE at &BC25."
    .assert DELETE_LINE = $BC2D, "The BASIC ROM User Guide documents DELETE_LINE at &BC2D."
    .assert INSERT_LINE = $BC8D, "The BASIC ROM User Guide documents INSERT_LINE at &BC8D."
    .assert RUN_PROGRAM = $BD14, "The BASIC ROM User Guide documents RUN_PROGRAM at &BD14."
    .assert CLEAR_VARIABLES = $BD20, "The BASIC ROM User Guide documents CLEAR_VARIABLES at &BD20."
    .assert RESET_STACKS = $BD3A, "The BASIC ROM User Guide documents RESET_STACKS at &BD3A."
    .assert FIND_PROGRAM_END = $BE6F, "The BASIC ROM User Guide documents FIND_PROGRAM_END at &BE6F."
    .assert PRINT_INLINE = $BFCF, "The BASIC ROM User Guide documents PRINT_INLINE at &BFCF."
