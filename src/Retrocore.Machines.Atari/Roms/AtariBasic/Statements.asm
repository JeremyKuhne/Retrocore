;; STATEMENTS ($B206-$B48E)
;;
;; - <STATEMENT_DIM>, which is also COM, gives arrays and strings their space at the end of the string and array area.
;; - <STATEMENT_POKE>, <STATEMENT_DEG>, <STATEMENT_RAD> and <STATEMENT_RESTORE>.
;; - <STATEMENT_READ> finds the next DATA element and <STATEMENT_INPUT> reads a line; both then share <INPUT_ITEM>,
;;   which reads each value from the text into the next variable of the statement.
;; - <STATEMENT_PRINT> writes numbers and strings, with its commas' tab stops and its #.
;;
;; Maintained by hand; assembles byte-identically to the cartridge.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

STATEMENTS_TEN_DIGITS = $10         ;; FR0+1 from here up: the mantissa's first digit is not 0, so it has ten digits

; ---------------------------------------------------------------------------------------------------------------------
; DIM and COM
; ---------------------------------------------------------------------------------------------------------------------

;; DIM and COM: give arrays and strings their sizes: DIM A(n), B(n,m), C$(n), ... COM is the same statement.
;;
;; Each item is an expression whose "(" is the syntax checker's DIM form (<OP_DIM_ARRAY_PAREN>,
;; <OP_DIM_STRING_PAREN>), which leaves the variable's value entry in VALUE_TYPE and FR0 and the sizes in ZTEMP1 and
;; SECOND_INDEX instead of finding an element. An array of n by m gets (n+1)*(m+1) numbers of six bytes, its entry
;; holding n+1 and m+1; a string of n characters gets n bytes, its entry holding a length of 0 and a size of n. The
;; space is opened at the end of the string and array area, below the run-time stack, and the entry gets its offset
;; from STARP and the dimensioned bit.
;;
;; Only the result's bit 15 is checked: an array of 65536 bytes or more wraps to its size's low 16 bits.
;; Errors: 9 (ERR_DIM) for a variable already dimensioned, a size from 32768, an array size of 32767, an array whose
;;   bytes have bit 15 set, or a string of 0 characters; 3 (ERR_VALUE) for a negative size or one beyond 65535;
;;   2 (ERR_MEMORY) when the space does not fit below MEMTOP
;; Entry: STATEMENT_COM = COM
;; Uses: A, X, Y, FR0, ZTEMP1, ZTEMP4, SECOND_INDEX, VARIABLE_ENTRY, MOVE_FROM, MOVE_TO, MOVE_LENGTH,
;;   SPACE_SIZE, NEW_SPACE, VALUE_TYPE, ARGUMENT_INDEX, OPERATOR_INDEX
;; See: <OPEN_SPACE_LONG>, <STORE_VARIABLE>
STATEMENT_DIM:
STATEMENT_COM:
    ldy TOKEN_OFFSET
    cpy NEXT_STATEMENT
    bcc DIM_VARIABLE                ; another item
    rts
DIM_VARIABLE:
    jsr EVALUATE_EXPRESSION         ; the variable and its sizes
    lda VALUE_TYPE
    ror A                           ; carry = VALUE_DIMENSIONED
    bcc DIM_MARK
DIM_REFUSE:
    jsr DIM_ERROR                   ; error 9
DIM_MARK:
    sec                             ; put the type back with VALUE_DIMENSIONED set
    rol A
    sta VALUE_TYPE
    bmi DIM_STRING
    ldy ZTEMP1                      ; the first size plus 1, in the entry and to multiply
    ldx ZTEMP1+1
    iny
    bne DIM_FIRST_SIZE
    inx
    bmi DIM_REFUSE                  ; 32767 is too many
DIM_FIRST_SIZE:
    sty FR0+2
    stx FR0+3
    sty ZTEMP1
    stx ZTEMP1+1
    ldy SECOND_INDEX                ; the second size plus 1
    ldx SECOND_INDEX+1
    iny
    bne DIM_SECOND_SIZE
    inx
    bmi DIM_REFUSE
DIM_SECOND_SIZE:
    sty FR0+4
    stx FR0+5
    jsr ARRAY_MULTIPLY              ; ZTEMP1 = the elements
    jsr ARRAY_TIMES_SIX             ; times six bytes
    ldy ZTEMP1
    lda ZTEMP1+1
    bmi DIM_REFUSE
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp DIM_OPEN
.else
    bpl DIM_OPEN                    ; always
.endif
DIM_STRING:
    lda #$00                        ; the string's length is 0
    sta FR0+2
    sta FR0+3
    ldy ZTEMP1                      ; and its size the DIM's
    sty FR0+4
    lda ZTEMP1+1
    sta FR0+5
    bne DIM_OPEN
    cpy #$00
    beq DIM_REFUSE                  ; no characters
DIM_OPEN:
    ldx #RUNSTK                     ; open A/Y bytes where the run-time stack begins
    jsr OPEN_SPACE_LONG
    sec                             ; the entry holds the space's offset from STARP
    lda NEW_SPACE
    sbc STARP
    sta FR0
    lda NEW_SPACE+1
    sbc STARP+1
    sta FR0+1
    jsr STORE_VARIABLE              ; store the entry in the variable value table
    jmp STATEMENT_DIM

; ---------------------------------------------------------------------------------------------------------------------
; POKE, DEG, RAD and RESTORE
; ---------------------------------------------------------------------------------------------------------------------

;; POKE: stores a byte in memory: POKE address, value.
;;
;; Both are rounded to integers; the value's low byte is stored.
;; Errors: 3 (ERR_VALUE) for an address out of 0-65535 or a value out of 0-255, except 7 (ERR_NUMBER_TOO_BIG) for
;;   a value of 32768-65535
;; Uses: A, X, Y, FR0, POKE_ADDRESS
STATEMENT_POKE:
    jsr EVALUATE_UNSIGNED           ; the address
    lda FR0
    sta POKE_ADDRESS
    lda FR0+1
    sta POKE_ADDRESS+1
    jsr EVALUATE_BYTE               ; the value, 0-255
    lda FR0
    ldy #$00
    sta (POKE_ADDRESS),y
    rts

;; DEG: makes SIN, COS and ATN work in degrees.
;; Out: DEGFLG = <DEGFLG_DEGREES>
;; Uses: A
;; See: <STATEMENT_RAD>
STATEMENT_DEG:
    lda #DEGFLG_DEGREES
.if VERSION = VERSION_A
    sta DEGFLG                      ; rev. A's own store and RTS
    rts
.else
    bne RAD_SET_DEGFLG              ; always
.endif

;; RAD: makes SIN, COS and ATN work in radians, as they do after RUN, NEW or the cold start.
;; Out: DEGFLG = <DEGFLG_RADIANS>
;; Uses: A
;; See: <STATEMENT_DEG>
STATEMENT_RAD:
    lda #DEGFLG_RADIANS
RAD_SET_DEGFLG:
    sta DEGFLG
    rts

;; RESTORE: makes the next READ start at a line's first DATA element: RESTORE [line].
;;
;; Without a line, READ starts again at the program's first line. The line need not exist: READ looks for DATA from
;; the first line at or after it.
;; Out: DATA_LINE = the line, DATA_ELEMENT = 0
;; Errors: 3 (ERR_VALUE) or 7 (ERR_NUMBER_TOO_BIG) for a line number out of 0-32767
;; Uses: A, X, Y, FR0
STATEMENT_RESTORE:
    lda #$00
    sta DATA_ELEMENT
    jsr AT_STATEMENT_END            ; is there a line number?
    bcc RESTORE_LINE
    tay                             ; no: line 0; always zero, as A is 0
    beq RESTORE_SET
RESTORE_LINE:
    jsr EVALUATE_INTEGER
    lda FR0+1
    ldy FR0
RESTORE_SET:
    sta DATA_LINE+1
    sty DATA_LINE
    rts

; ---------------------------------------------------------------------------------------------------------------------
; READ and INPUT
; ---------------------------------------------------------------------------------------------------------------------

;; READ: assigns the next DATA elements to variables: READ var, var, ...
;;
;; READ keeps its place as a line number, DATA_LINE, and an element in that line, DATA_ELEMENT. It saves where it is
;; as a GOSUB entry on the run-time stack, finds the first line at or after DATA_LINE, points INBUFF at that line,
;; then pops the entry again by RETURN (which accepts an entry made from READ), so that STMCUR is back at READ's own
;; line while INBUFF stays on the data. It then scans the lines from there, statement by statement, for a DATA
;; statement with an element it has not read, skipping the elements before DATA_ELEMENT, and reads from there with
;; <INPUT_ITEM>.
;;
;; A DATA element is text up to a comma or the end of the line: a number for a numeric variable, any characters for
;; a string. The immediate line is scanned too, as the last, so a DATA statement typed with a READ in the same
;; immediate line is read.
;; Errors: 6 (ERR_OUT_OF_DATA) when no DATA is left, 8 (ERR_INPUT) for an element that is not a number read into a
;;   numeric variable, and the string assignment's errors
;; Uses: A, X, Y, INBUFF, CIX, ZTEMP1, DATA_LINE, DATA_ELEMENT, READ_FLAG, LINE_NUMBER, RUNSTACK_ENTRY, STMCUR_SAVE,
;;   VALUE_TYPE, ARGUMENT_INDEX, OPERATOR_INDEX
;; See: <STATEMENT_RESTORE>, <PUSH_GOSUB>, <STATEMENT_RETURN>
STATEMENT_READ:
    lda TOKEN_OFFSET
    pha
    jsr PUSH_GOSUB                  ; keep READ's place as a GOSUB entry
    lda DATA_LINE                   ; find the DATA line
    sta LINE_NUMBER
    lda DATA_LINE+1
    sta LINE_NUMBER+1
    jsr FIND_LINE
    lda STMCUR                      ; read the text from it
    sta INBUFF
    lda STMCUR+1
    sta INBUFF+1
    jsr STATEMENT_RETURN            ; and go back to READ's line by RETURN
    pla
    sta TOKEN_OFFSET
READ_SCAN_LINE:
    ldy #$00                        ; the line at INBUFF: its number and length
    sty CIX
    jsr READ_TEXT_CHARACTER
    sta DATA_LINE
    jsr READ_TEXT_NEXT
    sta DATA_LINE+1
    jsr READ_TEXT_NEXT
    sta ZTEMP1                      ; the line's length
READ_SCAN_STATEMENT:
    jsr READ_TEXT_NEXT
    sta ZTEMP1+1                    ; the next statement's offset
    jsr READ_TEXT_NEXT              ; the statement's token
.if VERSION = VERSION_A             ; rev. A compares, leaving A nonzero, and clears ZTEMP1 itself below
    cmp #TOKEN_DATA
.else
    eor #TOKEN_DATA
.endif
    beq READ_DATA_FOUND             ; A = 0 from rev. B
    ldy ZTEMP1+1
    cpy ZTEMP1
    bcs READ_LINE_SCANNED           ; no statement follows
    dey                             ; READ_TEXT_NEXT steps onto it
    sty CIX
    bcc READ_SCAN_STATEMENT         ; always
READ_LINE_SCANNED:
    sty CIX                         ; CIX = the line's last byte, as at the end of a DATA
    dec CIX
READ_NEXT_LINE:
    ldy #LINE_NUMBER_OFFSET+1
    lda (INBUFF),y
    bmi READ_OUT_OF_DATA            ; that was the immediate line
    sec                             ; INBUFF = the next line, past CIX
    lda CIX
    adc INBUFF
    sta INBUFF
    lda #$00
    sta DATA_ELEMENT                ; from its first element
    adc INBUFF+1
    sta INBUFF+1
    bcc READ_SCAN_LINE              ; always
READ_DATA_FOUND:
.if VERSION = VERSION_A             ; rev. A loads the 0 that the later revisions have in A already
    lda #$00
.endif
    sta ZTEMP1                      ; count its elements from 0
READ_FIND_ELEMENT:
    lda ZTEMP1
    cmp DATA_ELEMENT
    bcs READ_ELEMENT                ; at the one to read
READ_SKIP_ELEMENT:
    jsr READ_TEXT_NEXT              ; skip one, to its comma or the end of the line
    bne READ_SKIP_ELEMENT
    bcs READ_NEXT_LINE              ; the end of the line: none left here
    inc ZTEMP1
    bne READ_FIND_ELEMENT           ; always
READ_ELEMENT:
    lda #READ_FROM_DATA
    sta READ_FLAG
    inc CIX                         ; past the token or the comma
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp INPUT_ITEM
.else
    bcs INPUT_ITEM                  ; always
.endif

;; Steps CIX on to the next character of READ's DATA or INPUT's line, and tells whether it ends an item.
;; In: INBUFF = the text, CIX = the index of the character before
;; Out: CIX = the character's index, Y = CIX, A = the character, zero = set for a comma or EOL, carry = set for EOL
;;   and clear for a comma (meaningless when zero is clear)
;; Keeps: X
;; See: <READ_TEXT_CHARACTER>
READ_TEXT_NEXT:
    inc CIX
;; Reads the character at CIX of READ's DATA or INPUT's line, and tells whether it ends an item.
;; In: INBUFF = the text, CIX = the index of the character
;; Out: Y = CIX, A = the character, zero = set for a comma or EOL, carry = set for EOL and clear for a comma
;;   (meaningless when zero is clear)
;; Keeps: X
;; See: <READ_TEXT_NEXT>
READ_TEXT_CHARACTER:
    ldy CIX
    lda (INBUFF),y
    cmp #','
    clc
    beq READ_TEXT_DONE
    cmp #EOL
READ_TEXT_DONE:
    rts

;; Raises error 6, out of data, for READ.
READ_OUT_OF_DATA:
    jsr OUT_OF_DATA_ERROR           ; error 6; does not return

;; INPUT: reads values typed at the keyboard, or from a file, into variables: INPUT [#iocb{,|;}] var, var, ...
;;
;; Without #, INPUT prints "?" and reads a line from the screen editor; with #, it reads a record from that IOCB
;; without a prompt. The line's values are separated by commas and go to the variables in turn; a string takes the
;; rest of the line, commas and all. When the line runs out before the variables do, INPUT reads another line; values
;; left over when the variables run out are ignored. BREAK while INPUT waits stops the program, as STOP does.
;; Errors: 8 (ERR_INPUT) for a value that is not a number read into a numeric variable; CIO's errors
;; Uses: A, X, Y, INBUFF, CIX, ZTEMP1, PROMPT, READ_FLAG, INPUT_IOCB, VALUE_TYPE, ARGUMENT_INDEX, OPERATOR_INDEX
;; See: <STATEMENT_READ>, <PROMPT_INPUT_LINE>
STATEMENT_INPUT:
    lda #'?'
    sta PROMPT
    jsr READ_OPERAND                ; carry = set for a #, an operator token
    dec TOKEN_OFFSET                ; back to it, or to the first variable
    bcc INPUT_LINE
    jsr NEXT_INTEGER_BYTE           ; the IOCB, leaving TOKEN_OFFSET past the , or ;
    sta INPUT_IOCB
INPUT_LINE:
    jsr FP_SET_INBUFF_LBUFF         ; read the line into LBUFF
    jsr PROMPT_INPUT_LINE
.if VERSION = VERSION_A             ; rev. A tests BREAK in a routine of its own
    jsr INPUT_CHECK_BREAK
.else
    jsr CHECK_BREAK
    beq INPUT_BREAK
.endif
    ldy #$00                        ; not READ, from the line's start
    sty READ_FLAG
    sty CIX
;; Reads a value from the text at INBUFF, CIX into each of the statement's variables, for READ and INPUT.
;;
;; A number is read by AFP and must end at a comma or the end of the line. A string is the text up to the end of the
;; line, or for READ to a comma, assigned as a string constant would be. After each, READ counts the DATA element
;; and goes on to the next line's DATA at the end of a line; INPUT reads another line.
;; In: INBUFF = the text, CIX = the index of the value, TOKEN_OFFSET = the offset of the variable's token, READ_FLAG
;;   = <READ_FROM_DATA> for READ, 0 for INPUT
;; Out: INBUFF = LBUFF, INPUT_IOCB = 0
;; Errors: 8 (ERR_INPUT) for a value that is not a number read into a numeric variable
;; Uses: A, X, Y, CIX, ZTEMP1, DATA_ELEMENT, VALUE_TYPE, ARGUMENT_INDEX, OPERATOR_INDEX
INPUT_ITEM:
    jsr READ_OPERAND                ; the variable's entry
    inc TOKEN_OFFSET                ; past the comma after it
    lda VALUE_TYPE
    bmi INPUT_STRING
    jsr AFP
    bcs INPUT_NOT_NUMBER
    jsr READ_TEXT_CHARACTER         ; the number must end the item
    bne INPUT_NOT_NUMBER
    jsr STORE_VARIABLE              ; store it in the variable
    jmp INPUT_NEXT_ITEM
.if VERSION = VERSION_A
;; Stops the program, as STOP does, when BREAK was pressed while INPUT waited: rev. A's own routine for INPUT.
;; Uses: A, Y
INPUT_CHECK_BREAK:
    jsr CHECK_BREAK
    bne INPUT_BREAK                 ; rev. A's CHECK_BREAK gives nonzero for BREAK
    rts
.endif
INPUT_BREAK:
    jmp STATEMENT_STOP              ; STOP
INPUT_NOT_NUMBER:
    lda #$00
    sta INPUT_IOCB
    jsr INPUT_STATEMENT_ERROR       ; error 8; does not return
INPUT_STRING:
    jsr INIT_EXPRESSION             ; the variable goes on a fresh argument stack, as an assignment's target
    jsr PUSH_VALUE
    dec CIX                         ; ZTEMP1 = the index before the string
    lda CIX
    sta ZTEMP1
    ldx #$FF
INPUT_STRING_LENGTH:
    inx                             ; X = the string's length
    jsr READ_TEXT_NEXT
    bne INPUT_STRING_LENGTH
    bcs INPUT_STRING_ASSIGN         ; the end of the line ends any string
    bit READ_FLAG
    bvc INPUT_STRING_LENGTH         ; a comma ends only READ's
INPUT_STRING_ASSIGN:
    ldy ZTEMP1
    lda TOKEN_OFFSET                ; which the string constant's value sets
    pha
    txa
    ldx #INBUFF                     ; the text as a string value, as if a constant
    jsr MAKE_STRING_VALUE
    pla
    sta TOKEN_OFFSET
    jsr ASSIGN_STRING               ; assign it
INPUT_NEXT_ITEM:
    bit READ_FLAG
    bvc INPUT_NEXT_VARIABLE
    inc DATA_ELEMENT                ; READ: one more element read
    jsr AT_STATEMENT_END
    bcs INPUT_DONE                  ; no more variables
    jsr READ_TEXT_CHARACTER
    bcc INPUT_AFTER_COMMA
    jmp READ_NEXT_LINE              ; the DATA's end: look for the next
INPUT_NEXT_VARIABLE:
    jsr AT_STATEMENT_END
    bcc INPUT_MORE
INPUT_DONE:
    jsr FP_SET_INBUFF_LBUFF
    lda #$00
    sta INPUT_IOCB
    rts
INPUT_MORE:
    jsr READ_TEXT_CHARACTER
    bcc INPUT_AFTER_COMMA
    jmp INPUT_LINE                  ; the line's end: read another
INPUT_AFTER_COMMA:
    inc CIX
    jmp INPUT_ITEM

; ---------------------------------------------------------------------------------------------------------------------
; PRINT
; ---------------------------------------------------------------------------------------------------------------------

;; PRINT (or ?): writes numbers and strings to the screen, or to a file: PRINT [#iocb{,|;}] [item {,|;} ...].
;;
;; A number is written as FASC writes it, with at most nine significant digits: a tenth is dropped, not rounded. A
;; string is written as it is. A ";" writes nothing; a "," moves on to the next tab stop, a multiple of PTABW at
;; least two columns on, writing spaces. Unless the statement ends with a "," or ";", an EOL follows. With #, the
;; output goes to that IOCB, and the separator after the number is an item like any other: "," writes spaces
;; there too.
;;
;; Rev. A writes all ten digits FASC gives. It decides on the EOL by the byte before the statement's end, which is
;; the last byte of a constant when the statement ends with one, so that a number whose last byte is $12 or $15
;; (PRINT 1.00000015) ends the line without an EOL; rev. B looks at the token after each separator instead.
;;
;; The column counts from the statement's start, not the screen's, and LPRINT comes here with IOCB 7.
;; Out: OUTPUT_IOCB = 0
;; Errors: CIO's, from the output
;; Uses: A, X, Y, FR0, CIX, INBUFF, PRINT_COLUMN, TAB_STOP, VALUE_TYPE, ARGUMENT_INDEX, OPERATOR_INDEX
;; See: <PRINT_CHARACTER>, <STATEMENT_LPRINT>
STATEMENT_PRINT:
    lda PTABW
    sta TAB_STOP
    lda #$00
    sta PRINT_COLUMN
PRINT_ITEM:
    ldy TOKEN_OFFSET
    lda (STMCUR),y
    cmp #OP_COMMA
    beq PRINT_COMMA
.if VERSION = VERSION_A             ; rev. A goes to its end of the line at once, without the later revisions' JMP
    cmp #TOKEN_LINE_END
    beq PRINT_END_LINE
    cmp #TOKEN_STATEMENT_END
    beq PRINT_END_LINE
.else
    cmp #TOKEN_LINE_END
    beq PRINT_LINE_END
    cmp #TOKEN_STATEMENT_END
    beq PRINT_LINE_END
.endif
    cmp #OP_SEMICOLON
    beq PRINT_SEPARATOR
    cmp #OP_HASH
    beq PRINT_IOCB
    jsr EVALUATE_EXPRESSION         ; an expression
    jsr POP_VALUE
    dec TOKEN_OFFSET                ; back to the token that ended it
    bit VALUE_TYPE
    bmi PRINT_STRING
.if VERSION >= VERSION_B            ; rev. A prints all ten digits
    lda FR0+1
    cmp #STATEMENTS_TEN_DIGITS
    bcc PRINT_NUMBER
    lda FR0+5                       ; drop the tenth digit
    and #$F0
    sta FR0+5
.endif
PRINT_NUMBER:
    jsr FASC
    lda #$00
    sta CIX
PRINT_NUMBER_LOOP:
    ldy CIX                         ; to the character with bit 7 set
    lda (INBUFF),y
    pha
    inc CIX
    jsr PRINT_CHARACTER
    pla
    bpl PRINT_NUMBER_LOOP
    bmi PRINT_ITEM                  ; always
PRINT_STRING:
    jsr MAKE_VALUE_ABSOLUTE         ; FR0 = its address, FR0+2 = its length
    lda #$00
    sta CIX
PRINT_STRING_LOOP:
    lda FR0+2                       ; count the length down
    bne PRINT_STRING_CHARACTER
    dec FR0+3
    bmi PRINT_ITEM
PRINT_STRING_CHARACTER:
    dec FR0+2
    ldy CIX
    lda (FR0),y
    inc CIX
    bne PRINT_STRING_OUTPUT
    inc FR0+1                       ; the next page
PRINT_STRING_OUTPUT:
    jsr PRINT_CHARACTER_UNMASKED
    jmp PRINT_STRING_LOOP
PRINT_COMMA:
    ldy PRINT_COLUMN                ; the first tab stop at least two columns on
    iny
    cpy TAB_STOP
    bcc PRINT_PAD
    clc
    lda PTABW
    adc TAB_STOP
    sta TAB_STOP
    bcc PRINT_COMMA
PRINT_PAD:
    ldy PRINT_COLUMN
    cpy TAB_STOP
    bcs PRINT_SEPARATOR
    lda #' '
    jsr PRINT_CHARACTER
    jmp PRINT_PAD
.if VERSION >= VERSION_B            ; rev. A has no JMP here
PRINT_LINE_END:
    jmp PRINT_END_LINE
.endif
PRINT_IOCB:
    jsr NEXT_INTEGER_BYTE           ; the IOCB
    sta OUTPUT_IOCB
    dec TOKEN_OFFSET                ; back to its separator, which is printed
    jmp PRINT_ITEM
PRINT_SEPARATOR:
    inc TOKEN_OFFSET
.if VERSION = VERSION_A             ; rev. A decides on the EOL by the byte before the end
    jmp PRINT_ITEM
PRINT_END_LINE:
    ldy TOKEN_OFFSET                ; the byte before the end
    dey
    lda (STMCUR),y
    cmp #OP_SEMICOLON
    beq PRINT_DONE                  ; a , or ; at the end: no EOL
    cmp #OP_COMMA
    beq PRINT_DONE
.else
    ldy TOKEN_OFFSET
    lda (STMCUR),y
    cmp #TOKEN_LINE_END
    beq PRINT_DONE                  ; a , or ; at the end: no EOL
    cmp #TOKEN_STATEMENT_END
    beq PRINT_DONE
    jmp PRINT_ITEM
PRINT_END_LINE:
.endif
    lda #EOL
    jsr PRINT_CHARACTER_UNMASKED
PRINT_DONE:
    lda #$00
    sta OUTPUT_IOCB
    rts
