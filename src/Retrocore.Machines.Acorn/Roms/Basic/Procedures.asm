;; BBC BASIC II: calling FNs and PROCs, errors, SOUND, ENVELOPE and WIDTH ($B112-$B4B3).
;;
;; - <CALL_FN_PROC> runs a user-defined function or procedure: it finds the DEF, by the FN and PROC list or by
;;   searching the program (<FIND_FN_PROC_DEFINITION>), passes the arguments to the parameters
;;   (<FN_PROC_PARAMETERS>), runs the body, and then gives the parameters and LOCAL variables their old values back.
;;   <PUSH_VARIABLE> keeps a variable's value on BASIC's stack for that, and <READ_VARIABLE> reads any variable's
;;   value into the accumulators.
;; - CHR$, then the error handling: <SET_ERL> finds the line an error happened in, and <BRK_HANDLER>, which BRKV points
;;   to, runs the ON ERROR text, by default <DEFAULT_ERROR_HANDLER>.
;; - The SOUND, ENVELOPE and WIDTH statements.

; Error numbers raised in this part.
ERROR_BAD_CALL = $1E                ;; error 30, "Bad call"
ERROR_ARGUMENTS = $1F               ;; error 31, "Arguments"

; The MOS calls made here.
OSBYTE_VDU_QUEUE = $DA              ;; OSBYTE &DA: read or write the number of bytes the VDU driver still expects
OSBYTE_ACKNOWLEDGE_ESCAPE = $7E     ;; OSBYTE &7E: acknowledge an ESCAPE condition
OSWORD_SOUND = $07                  ;; OSWORD 7: SOUND, with an eight-byte control block
OSWORD_ENVELOPE = $08               ;; OSWORD 8: ENVELOPE, with a fourteen-byte control block

; The workspace calling an FN or PROC uses.
FN_PROC_NAME = WORK                 ;; points one byte before the token of the FN or PROC being called; its name follows
FN_PROC_NAME_END = WORK + 2         ;; the offset from FN_PROC_NAME of the name's last character
DEF_POINTER = FP_B_OVERFLOW         ;; while searching the program, points one byte before a DEF's FN or PROC token
FN_PROC_RESTORE_COUNT = FP_B_MANTISSA + 1   ;; the parameters and LOCAL variables left to restore after a call
FN_PROC_ARGUMENTS_LEFT = SERIES_POINTER     ;; the arguments still to be given to parameters
FN_PROC_PARAMETER_COUNT = SERIES_POINTER + 1    ;; the number of parameters, the variables to restore after the call

SOUND_BLOCK = WORK                  ;; the control block SOUND and ENVELOPE build for OSWORD, &37-&44

;; Searches the program for the DEF of an FN or PROC that is not yet in its list, and adds it to the list.
;;
;; Each line whose first word, after spaces, is DEF is checked: the FN or PROC token and the name after it must match
;; the name being called, and the name must end there, not go on with another letter or digit. The new list entry
;; holds the name and the address of the text after it in the DEF line, which is where PTRA is left before the call
;; carries on at <CALL_FN_PROC_ENTER>.
;;
;; A line in the program is a carriage return (where PTRA points), the line number high byte first, the line's length
;; and its text.
;; In: FN_PROC_NAME, FN_PROC_NAME_END = the name, X = PTRB's offset after it
;; Out: PTR_A = the text after the name in the DEF line, PTR_A_OFFSET = 1
;; Uses: A, X, Y, DEF_POINTER, HEAP
;; Errors: "No such FN/PROC" at the end of the program, "No room" when the list entry does not fit
FIND_FN_PROC_DEFINITION:
    lda PAGE_HIGH
    sta PTR_A+1
    lda #$00
    sta PTR_A
FIND_FN_PROC_DEFINITION_LINE:
    ldy #$01
    lda (PTR_A),y                   ; the line number's high byte
    bmi NO_SUCH_FN_PROC             ; the end of the program
    ldy #$03
FIND_FN_PROC_DEFINITION_SPACES:
    iny
    lda (PTR_A),y
    cmp #' '
    beq FIND_FN_PROC_DEFINITION_SPACES
    cmp #TOKEN_DEF
    beq FIND_FN_PROC_DEFINITION_DEF
FIND_FN_PROC_DEFINITION_NEXT:
    ldy #$03
    lda (PTR_A),y                   ; the line's length
    clc
    adc PTR_A
    sta PTR_A
    bcc FIND_FN_PROC_DEFINITION_LINE
    inc PTR_A+1
    bcs FIND_FN_PROC_DEFINITION_LINE    ; always taken
FIND_FN_PROC_DEFINITION_DEF:
    iny
    sty PTR_A_OFFSET
    jsr GET_CHARACTER_A             ; Y = the offset of the FN or PROC token
    tya
    tax
    clc
    adc PTR_A
    ldy PTR_A+1
    bcc FIND_FN_PROC_DEFINITION_POINT
    iny
    clc
FIND_FN_PROC_DEFINITION_POINT:
    sbc #$00                        ; carry is clear: one byte before the token
    sta DEF_POINTER
    tya
    sbc #$00
    sta DEF_POINTER+1
    ldy #$00
FIND_FN_PROC_DEFINITION_COMPARE:
    iny
    inx
    lda (DEF_POINTER),y
    cmp (FN_PROC_NAME),y
    bne FIND_FN_PROC_DEFINITION_NEXT
    cpy FN_PROC_NAME_END
    bne FIND_FN_PROC_DEFINITION_COMPARE
    iny
    lda (DEF_POINTER),y
    jsr IS_NAME_CHARACTER                       ; does the name go on?
    bcs FIND_FN_PROC_DEFINITION_NEXT
    txa                             ; the offset after the name in the line
    tay
    jsr ADVANCE_PTR_A
    jsr LINK_FN_PROC
    ldx #$01                        ; the zero that ends the name
    jsr ALLOCATE_VARIABLE
    ldy #$00
    lda PTR_A                       ; then the address of the text after it
    sta (HEAP),y
    iny
    lda PTR_A+1
    sta (HEAP),y
    jsr CLAIM_HEAP
    jmp CALL_FN_PROC_ENTER

;; Raises error 30, "Bad call", for FN or PROC without a name.
BAD_CALL:
    brk
    .byte ERROR_BAD_CALL
    .byte "Bad call",0

;; FN: calls a user-defined function: FNname or FNname(arguments).
;; Out: A = EXPRESSION_TYPE = the type of the value the function's = gave, with the value in its accumulator
;; See: <CALL_FN_PROC>
FN_FUNCTION:
    lda #TOKEN_FN

;; Calls an FN or PROC, for FN and PROC_STATEMENT.
;;
;; - The 6502 stack is moved onto BASIC's stack, a byte holding the stack pointer first, so that each call starts
;;   with the 6502 stack empty and calls can nest as deep as memory allows.
;; - The token, PTRA's offset and PTRA are pushed on the 6502 stack, to return to.
;; - The name after the token is looked up in the FN or PROC list; if it is not there, <FIND_FN_PROC_DEFINITION>
;;   searches the program for its DEF. PTRA is pointed at the text after the name in the DEF.
;; - <FN_PROC_PARAMETERS> handles a bracket of parameters there. The number of variables to restore is pushed, and
;;   PTRB, and the body is run from PTRA until ENDPROC or = returns from the statement loop. LOCAL adds one to the
;;   number for each variable it makes local.
;; - The parameters and LOCAL variables get their old values back from BASIC's stack, then PTRB, PTRA and the 6502
;;   stack are restored.
;; In: A = TOKEN_FN or TOKEN_PROC, PTR_B and PTR_B_OFFSET = just past the token
;; Out: A = EXPRESSION_TYPE, for an FN the type of its result; PTR_B_OFFSET = after the call
;; Uses: X, Y, WORK..WORK+3, FN_PROC_RESTORE_COUNT
;; Errors: "Bad call", "No such FN/PROC", "Arguments", "No room", and any error in the body
;; Entry: CALL_FN_PROC_ENTER = runs the FN or PROC at PTRA with the 6502 stack already set up
;; See: <SEARCH_FN_PROC_LIST>
CALL_FN_PROC:
    sta EXPRESSION_TYPE
    tsx
    txa
    clc
    adc BASIC_STACK                 ; make room for the stack: &100 - S bytes
    jsr LOWER_BASIC_STACK
    ldy #$00
    txa
    sta (BASIC_STACK),y             ; the stack pointer first
CALL_FN_PROC_SAVE_STACK:
    inx
    iny
    lda STACK,x
    sta (BASIC_STACK),y
    cpx #$FF
    bne CALL_FN_PROC_SAVE_STACK
    txs                             ; the 6502 stack is empty
    lda EXPRESSION_TYPE
    pha
    lda PTR_A_OFFSET
    pha
    lda PTR_A
    pha
    lda PTR_A+1
    pha
    lda PTR_B_OFFSET
    tax
    clc
    adc PTR_B
    ldy PTR_B+1
    bcc CALL_FN_PROC_NAME
    iny
    clc
CALL_FN_PROC_NAME:
    sbc #$01                        ; carry is clear: two bytes back, one before the token
    sta FN_PROC_NAME
    tya
    sbc #$00
    sta FN_PROC_NAME+1
    ldy #$02
    jsr SCAN_VARIABLE_NAME_AT_Y                       ; scan the name after the token
    cpy #$02
    beq BAD_CALL                    ; no name
    stx PTR_B_OFFSET
    dey
    sty FN_PROC_NAME_END
    jsr SEARCH_FN_PROC_LIST
    bne CALL_FN_PROC_KNOWN
    jmp FIND_FN_PROC_DEFINITION
CALL_FN_PROC_KNOWN:
    ldy #$00
    lda (INT_A),y                   ; the address of the text after the name in the DEF
    sta PTR_A
    iny
    lda (INT_A),y
    sta PTR_A+1
CALL_FN_PROC_ENTER:
    lda #$00                        ; no variables to restore yet
    pha
    sta PTR_A_OFFSET
    jsr GET_CHARACTER_A
    cmp #'('
    beq FN_PROC_PARAMETERS
    dec PTR_A_OFFSET
CALL_FN_PROC_RUN:
    lda PTR_B_OFFSET
    pha
    lda PTR_B
    pha
    lda PTR_B+1
    pha
    jsr EXECUTE_STATEMENT                       ; run the body until ENDPROC or = returns
    pla
    sta PTR_B+1
    pla
    sta PTR_B
    pla
    sta PTR_B_OFFSET
    pla                             ; the variables to restore
    beq CALL_FN_PROC_RETURN
    sta FN_PROC_RESTORE_COUNT
CALL_FN_PROC_RESTORE_VARIABLES:
    jsr POP_INTEGER_TO_WORK                       ; the descriptor
    jsr ASSIGN_FROM_STACK                       ; and the old value
    dec FN_PROC_RESTORE_COUNT
    bne CALL_FN_PROC_RESTORE_VARIABLES
CALL_FN_PROC_RETURN:
    pla
    sta PTR_A+1
    pla
    sta PTR_A
    pla
    sta PTR_A_OFFSET
    pla                             ; the token
    ldy #$00
    lda (BASIC_STACK),y             ; the 6502 stack pointer
    tax
    txs
CALL_FN_PROC_RESTORE_STACK:
    iny
    inx
    lda (BASIC_STACK),y
    sta STACK,x
    cpx #$FF
    bne CALL_FN_PROC_RESTORE_STACK
    tya                             ; carry is set: drop the stack pointer and Y bytes
    adc BASIC_STACK
    sta BASIC_STACK
    bcc CALL_FN_PROC_TYPE
    inc BASIC_STACK+1
CALL_FN_PROC_TYPE:
    lda EXPRESSION_TYPE
    rts

;; Gives an FN's or PROC's parameters the values of the call's arguments, for <CALL_FN_PROC>.
;;
;; First each parameter in the DEF's bracket is found or made, and <PUSH_VARIABLE> keeps its value on BASIC's stack
;; to restore after the call. Its descriptor goes on the 6502 stack, three bytes, under the number of parameters so
;; far. Then each argument in the call's bracket is evaluated and pushed on BASIC's stack, followed by its type in the
;; top byte of an integer. When there are as many arguments as parameters, they are taken off the two stacks
;; together, last first, and assigned; a string argument must go to a string parameter and a number to a numeric
;; one. Then the body is run, at <CALL_FN_PROC_RUN>, with the number of parameters as the number of variables to
;; restore.
;; In: PTR_A, PTR_A_OFFSET = after the DEF's opening bracket, PTR_B and PTR_B_OFFSET = after the call's name, the
;;   6502 stack = 0 (the number of variables to restore) above the return information
;; Uses: A, X, Y, INT_A, WORK, FN_PROC_ARGUMENTS_LEFT, FN_PROC_PARAMETER_COUNT
;; Errors: "Arguments" when the parameters or arguments are not well formed, their numbers differ or a type does
;;   not match
FN_PROC_PARAMETERS:
    lda PTR_B_OFFSET
    pha
    lda PTR_B
    pha
    lda PTR_B+1
    pha
    jsr FIND_OR_CREATE_VARIABLE                       ; find or make the parameter
    beq FN_PROC_PARAMETERS_BAD
    lda PTR_B_OFFSET
    sta PTR_A_OFFSET
    pla
    sta PTR_B+1
    pla
    sta PTR_B
    pla
    sta PTR_B_OFFSET
    pla                             ; the parameters so far
    tax
    lda INT_A+2                     ; the descriptor
    pha
    lda INT_A+1
    pha
    lda INT_A
    pha
    inx
    txa
    pha
    jsr PUSH_VARIABLE
    jsr GET_CHARACTER_A
    cmp #','
    beq FN_PROC_PARAMETERS
    cmp #')'
    bne FN_PROC_PARAMETERS_BAD
    lda #$00                        ; no arguments yet
    pha
    jsr GET_CHARACTER_B
    cmp #'('
    bne FN_PROC_PARAMETERS_BAD
FN_PROC_PARAMETERS_ARGUMENT:
    jsr EVALUATE_EXPRESSION
    jsr PUSH_VALUE
    lda EXPRESSION_TYPE
    sta INT_A+3
    jsr PUSH_INTEGER                ; the type, in the top byte
    pla
    tax
    inx
    txa
    pha
    jsr GET_CHARACTER_B
    cmp #','
    beq FN_PROC_PARAMETERS_ARGUMENT
    cmp #')'
    bne FN_PROC_PARAMETERS_BAD
    pla                             ; the arguments, in X too
    pla                             ; the parameters
    sta FN_PROC_ARGUMENTS_LEFT
    sta FN_PROC_PARAMETER_COUNT
    cpx FN_PROC_ARGUMENTS_LEFT
    beq FN_PROC_PARAMETERS_ASSIGN

;; Raises error 31, "Arguments".
;;
;; The 6502 stack is reset to hold only what <CALL_FN_PROC> pushed, and PTRA is pulled back from it so that the error
;; is reported at the line that made the call.
FN_PROC_PARAMETERS_BAD:
    ldx #$FB                        ; the token, PTRA's offset and PTRA at &01FC-&01FF
    txs
    pla
    sta PTR_A+1
    pla
    sta PTR_A
    brk
    .byte ERROR_ARGUMENTS
    .byte "Arguments",0

;; Assigns the arguments to the parameters, for <FN_PROC_PARAMETERS>, then runs the body.
FN_PROC_PARAMETERS_ASSIGN:
    jsr POP_INTEGER                 ; the argument's type, in INT_A+3
    pla
    sta INT_A                       ; the parameter's descriptor
    pla
    sta INT_A+1
    pla
    sta INT_A+2
    bmi FN_PROC_PARAMETERS_STRING
    lda INT_A+3
    beq FN_PROC_PARAMETERS_BAD      ; a string for a number
    sta EXPRESSION_TYPE
    ldx #WORK
    jsr STORE_INT_A                 ; the descriptor, for ASSIGN_NUMBER_TO
    lda EXPRESSION_TYPE
    bpl FN_PROC_PARAMETERS_INTEGER
    jsr POP_REAL_POINTER
    jsr LOAD_FP_A
    jmp FN_PROC_PARAMETERS_NUMBER
FN_PROC_PARAMETERS_INTEGER:
    jsr POP_INTEGER
FN_PROC_PARAMETERS_NUMBER:
    jsr ASSIGN_NUMBER_TO
    jmp FN_PROC_PARAMETERS_NEXT
FN_PROC_PARAMETERS_STRING:
    lda INT_A+3
    bne FN_PROC_PARAMETERS_BAD      ; a number for a string
    jsr POP_STRING
    jsr ASSIGN_STRING
FN_PROC_PARAMETERS_NEXT:
    dec FN_PROC_ARGUMENTS_LEFT
    bne FN_PROC_PARAMETERS_ASSIGN
    lda FN_PROC_PARAMETER_COUNT     ; the variables to restore after the call
    pha
    jmp CALL_FN_PROC_RUN

;; Pushes a variable's value, then its descriptor, on BASIC's stack, so that it can be restored later; for LOCAL and
;; the parameters of FN and PROC.
;;
;; Reading an integer variable's value overwrites IntA, so its descriptor is kept in WORK meanwhile. A byte variable's
;; (type 0) is not kept, so the descriptor pushed for one is whatever WORK held.
;; In: INT_A..INT_A+2 = the variable's descriptor: the address of its value and its type
;; Out: INT_A = the descriptor
;; Uses: A, X, Y, WORK..WORK+3, FP_A..FP_A+7, STRING_BUFFER, STRING_LENGTH (the value read)
;; See: <READ_VARIABLE>, <PUSH_VALUE>
PUSH_VARIABLE:
    ldy INT_A+2
    cpy #VARIABLE_INTEGER
    bne PUSH_VARIABLE_READ
    ldx #WORK
    jsr STORE_INT_A
PUSH_VARIABLE_READ:
    jsr READ_VARIABLE
    php
    jsr PUSH_VALUE
    plp
    beq PUSH_VARIABLE_DESCRIPTOR    ; a string: IntA still holds the descriptor
    bmi PUSH_VARIABLE_DESCRIPTOR    ; a real: so does it
    ldx #WORK
    jsr LOAD_INT_A
PUSH_VARIABLE_DESCRIPTOR:
    jmp PUSH_INTEGER

;; Reads a variable's value into the accumulator for its type.
;;
;; The types are 0 for a byte (?), 4 for an integer (% or !), 5 for a real, &80 for a string at an address ($) and &81
;; for a string variable, whose value is a string information block: the string's address, the room allocated and its
;; length. A string at an address ends with a carriage return, and is at most 255 characters; an address in page zero
;; gives a string of one character instead, the address's low byte (the $ operator itself refuses such addresses with
;; "$ range").
;; In: INT_A, INT_A+1 = the address of the value, INT_A+2 = the type
;; Out: A = the type: &40 with INT_A = an integer, &FF (negative set) with FP_A = a real, or 0 (zero set) with
;;   STRING_BUFFER and STRING_LENGTH = a string
;; Uses: X, Y, WORK, WORK+1
;; Entry: READ_VARIABLE_REAL = reads a real with Y = 5, for NEXT
READ_VARIABLE:
    ldy INT_A+2
    bmi READ_VARIABLE_STRING
    beq READ_VARIABLE_BYTE
    cpy #VARIABLE_REAL
    beq READ_VARIABLE_REAL
    ldy #$03                        ; an integer, read from the top down
    lda (INT_A),y
    sta INT_A+3
    dey
    lda (INT_A),y
    sta INT_A+2
    dey
    lda (INT_A),y
    tax
    dey
    lda (INT_A),y
    sta INT_A
    stx INT_A+1
    lda #TYPE_INTEGER
    rts
READ_VARIABLE_BYTE:
    lda (INT_A),y                   ; Y = 0
    jmp LOAD_INT_A_WORD
READ_VARIABLE_REAL:
    dey
    lda (INT_A),y
    sta FP_A_MANTISSA+3
    dey
    lda (INT_A),y
    sta FP_A_MANTISSA+2
    dey
    lda (INT_A),y
    sta FP_A_MANTISSA+1
    dey
    lda (INT_A),y                   ; the top mantissa byte, whose bit 7 is the sign
    sta FP_A_SIGN
    dey
    lda (INT_A),y
    sta FP_A_EXPONENT
    sty FP_A_ROUNDING
    sty FP_A_OVERFLOW
    ora FP_A_SIGN
    ora FP_A_MANTISSA+1
    ora FP_A_MANTISSA+2
    ora FP_A_MANTISSA+3
    beq READ_VARIABLE_REAL_TOP      ; zero stays zero
    lda FP_A_SIGN
    ora #$80                        ; the mantissa's top bit, which the sign took the place of
READ_VARIABLE_REAL_TOP:
    sta FP_A_MANTISSA
    lda #TYPE_REAL
    rts
READ_VARIABLE_STRING:
    cpy #VARIABLE_STRING_AT
    beq READ_VARIABLE_ADDRESS
    ldy #$03
    lda (INT_A),y                   ; the length
    sta STRING_LENGTH
    beq READ_VARIABLE_STRING_DONE
    ldy #$01
    lda (INT_A),y
    sta WORK+1
    dey
    lda (INT_A),y
    sta WORK
    ldy STRING_LENGTH
READ_VARIABLE_STRING_LOOP:
    dey
    lda (WORK),y
    sta STRING_BUFFER,y
    tya
    bne READ_VARIABLE_STRING_LOOP
READ_VARIABLE_STRING_DONE:
    rts
READ_VARIABLE_ADDRESS:
    lda INT_A+1
    beq CHR_STR_CHARACTER           ; page zero: one character
    ldy #$00
READ_VARIABLE_ADDRESS_LOOP:
    lda (INT_A),y
    sta STRING_BUFFER,y
    eor #CARRIAGE_RETURN
    beq READ_VARIABLE_ADDRESS_END   ; A = 0
    iny
    bne READ_VARIABLE_ADDRESS_LOOP
    tya                             ; no carriage return in 256 bytes: an empty string
READ_VARIABLE_ADDRESS_END:
    sty STRING_LENGTH
    rts

;; CHR$: gives the character with an ASCII code, as a string of one character: CHR$ n.
;; Out: STRING_BUFFER, STRING_LENGTH = the string, A = 0 (a string)
;; Entry: CHR_STR_CHARACTER = makes the string from INT_A's low byte
CHR_STR_FUNCTION:
    jsr EVALUATE_INTEGER_FACTOR
CHR_STR_CHARACTER:
    lda INT_A
    jmp MAKE_CHARACTER_STRING

;; Sets ERL to the number of the line PTRA is in, for the error handler.
;;
;; It reads the program from PAGE a byte at a time, and at each carriage return that ends a line, while the next line
;; starts at or before PTRA, takes that line's number. ERL is 0 when PTRA is in the input line (page seven), for a
;; command typed without a line number.
;; Out: ERL = the line number, Y = 0
;; Uses: A, X, WORK, WORK+1
SET_ERL:
    ldy #$00
    sty ERL
    sty ERL+1
    ldx PAGE_HIGH
    stx WORK+1
    sty WORK
    ldx PTR_A+1
    cpx #>LINE_BUFFER
    beq SET_ERL_DONE
    ldx PTR_A
SET_ERL_LOOP:
    jsr READ_AND_ADVANCE_WORK                       ; the next byte of the program
    cmp #CARRIAGE_RETURN
    bne SET_ERL_CHECK
    cpx WORK                        ; is the next line past PTRA?
    lda PTR_A+1
    sbc WORK+1
    bcc SET_ERL_DONE
    jsr READ_AND_ADVANCE_WORK
    ora #$00
    bmi SET_ERL_DONE                ; the end of the program
    sta ERL+1
    jsr READ_AND_ADVANCE_WORK
    sta ERL
    jsr READ_AND_ADVANCE_WORK                       ; skip the length
SET_ERL_CHECK:
    cpx WORK
    lda PTR_A+1
    sbc WORK+1
    bcs SET_ERL_LOOP
SET_ERL_DONE:
    rts

;; BASIC's error handler: BRKV points here, and the MOS calls it after a BRK with the error at (&FD).
;;
;; It sets ERL, turns TRACE off, and runs the ON ERROR text, after resetting BASIC's stack, the FOR, REPEAT and GOSUB
;; stacks and the DATA pointer, emptying the VDU queue, acknowledging any ESCAPE, and setting OPT to &FF so that
;; unknown variables are errors again. Error 0, a fatal error such as "No room", cannot be trapped: it sets ON ERROR
;; back to <DEFAULT_ERROR_HANDLER> first. The 6502 stack is reset, and the handler's text is run as statements.
;; In: ERROR_POINTER = the error number, which the message follows
;; See: <SET_ERL>, <REPORT_STATEMENT>
BRK_HANDLER:
    jsr SET_ERL
    sty TRACE_FLAG                  ; Y = 0: TRACE off
    lda (ERROR_POINTER),y
    bne BRK_HANDLER_RUN
    lda #<DEFAULT_ERROR_HANDLER
    sta ON_ERROR
    lda #>DEFAULT_ERROR_HANDLER
    sta ON_ERROR+1
BRK_HANDLER_RUN:
    lda ON_ERROR
    sta PTR_A
    lda ON_ERROR+1
    sta PTR_A+1
    jsr RESET_STACKS
    tax                             ; A = 0
    stx PTR_A_OFFSET
    lda #OSBYTE_VDU_QUEUE           ; X = Y = 0: empty the queue
    jsr OSBYTE
    lda #OSBYTE_ACKNOWLEDGE_ESCAPE
    jsr OSBYTE
    ldx #$FF
    stx OPT
    txs
    jmp EXECUTE_STATEMENT

;; The ON ERROR text BASIC runs when a program has not set its own: a tokenised statement with no line number.
;;
;; > REPORT:IF ERL PRINT" at line ";ERL:END ELSE PRINT:END
DEFAULT_ERROR_HANDLER:
    .byte TOKEN_REPORT, ":", TOKEN_IF, TOKEN_ERL, TOKEN_PRINT, '"', " at line ", '"', ";", TOKEN_ERL, ":", TOKEN_END
    .byte TOKEN_ELSE, TOKEN_PRINT, ":", TOKEN_END, CARRIAGE_RETURN

;; SOUND: makes a sound: SOUND channel, amplitude, pitch, duration.
;;
;; The four numbers go to OSWORD 7 as two bytes each, in a block at &37.
;; Uses: A, X, Y, SOUND_BLOCK..SOUND_BLOCK+7
;; See: <SOUND_OSWORD>
SOUND_STATEMENT:
    jsr EVALUATE_INTEGER_A
    ldx #$03                        ; three numbers to push
SOUND_STATEMENT_LOOP:
    lda INT_A
    pha
    lda INT_A+1
    pha
    txa
    pha
    jsr EVALUATE_COMMA_INTEGER
    pla
    tax
    dex
    bne SOUND_STATEMENT_LOOP
    jsr CHECK_END_OF_STATEMENT_B
    lda INT_A                       ; the duration goes straight into the block
    sta SOUND_BLOCK+6
    lda INT_A+1
    sta SOUND_BLOCK+7
    ldy #OSWORD_SOUND
    ldx #$05                        ; pull six bytes
    bne SOUND_OSWORD                ; always taken

;; ENVELOPE: defines an envelope for SOUND: ENVELOPE with fourteen numbers, the envelope's number, the length of its
;; steps, three pitch changes and their step counts, and the amplitude's attack, decay, sustain and release rates and
;; target levels.
;;
;; The numbers go to OSWORD 8 as a byte each, in a block at &37.
;; Uses: A, X, Y, SOUND_BLOCK..SOUND_BLOCK+13
ENVELOPE_STATEMENT:
    jsr EVALUATE_INTEGER_A
    ldx #13                         ; thirteen numbers to push
ENVELOPE_STATEMENT_LOOP:
    lda INT_A
    pha
    txa
    pha
    jsr EVALUATE_COMMA_INTEGER
    pla
    tax
    dex
    bne ENVELOPE_STATEMENT_LOOP
    jsr CHECK_END_OF_STATEMENT_B
    lda INT_A                       ; the last goes straight into the block
    sta SOUND_BLOCK+13
    ldx #$0C                        ; pull thirteen bytes
    ldy #OSWORD_ENVELOPE

;; Pulls the numbers SOUND or ENVELOPE pushed into the control block, last first, and calls OSWORD with it.
;; In: X = the bytes to pull less one, Y = the OSWORD number
SOUND_OSWORD:
    pla
    sta SOUND_BLOCK,x
    dex
    bpl SOUND_OSWORD
    tya
    ldx #SOUND_BLOCK
    ldy #$00
    jsr OSWORD
    jmp CONTINUE_EXECUTION

;; WIDTH: sets the line length after which PRINT starts a new line: WIDTH n, where WIDTH 0 means no limit.
;;
;; BASIC keeps n - 1, so 0 becomes &FF.
WIDTH_STATEMENT:
    jsr EVALUATE_INTEGER_A
    jsr CHECK_END_OF_STATEMENT_B
    ldy INT_A
    dey
    sty WIDTH
    jmp CONTINUE_EXECUTION

;; Raises "Type mismatch", for ASSIGN_NUMBER when the value is a string; a jump within branch reach.
ASSIGN_TYPE_MISMATCH:
    jmp TYPE_MISMATCH_ERROR

;; Evaluates an expression and assigns it to the numeric variable whose descriptor is on BASIC's stack, for FOR and
;; READ; falls into <ASSIGN_NUMBER>.
EVALUATE_AND_ASSIGN:
    jsr EVALUATE_EXPRESSION

; The addresses the BASIC ROM User Guide gives for these routines.
    .assert CALL_FN_PROC_ENTER = $B1F4, "CALL_FN_PROC_ENTER moved."
    .assert PUSH_VARIABLE = $B30D, "PUSH_VARIABLE moved."
    .assert READ_VARIABLE = $B32C, "READ_VARIABLE moved."
    .assert SET_ERL = $B3C5, "SET_ERL moved."
    .assert BRK_HANDLER = $B402, "BRK_HANDLER moved."
    .assert DEFAULT_ERROR_HANDLER = $B433, "DEFAULT_ERROR_HANDLER moved."
