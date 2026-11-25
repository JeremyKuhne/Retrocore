;; INPUT AND OUTPUT, AND THE LAST FUNCTIONS ($BCA8-$BFFF)
;;
;; BASIC's ways into CIO, the I/O errors, and the routines left over at the cartridge's top. Maintained by hand;
;; assembles byte-identically to the cartridge.
;;
;; - The IOCBs: <IOCB_FROM_HASH> reads a statement's #n, <IOCB_OFFSET> and <IOCB_STATUS> find the IOCB in
;;   IOCB_NUMBER, <CHECK_IO_STATUS> turns a CIO error into BASIC's, <CLOSE_IOCB> closes one, <CALL_CIO_LINE> and its
;;   entries call CIO, <INTEGER_BYTE> reads a byte-sized argument, <SET_VARIABLE_INTEGER> stores a result in a
;;   variable.
;; - <SILENCE_CLOSE_ALL> and <DEFAULT_IOCBS>, for the warm start and the end of a program; <PRINT_READY> and
;;   <PRINT_EOL>; <PATCH_STRING_EOL> and <RESTORE_STRING_EOL>, which end a string with an EOL for the OS to read.
;; - <STATEMENT_RETURN>, with <RETURN_TO_ENTRY>, which NEXT shares; <PROMPT_INPUT_LINE> and <READ_INPUT_LINE>, which
;;   read a line for INPUT and the line editor; and + (<OPERATOR_ADD>).
;; - BASIC's own trigonometry and square root, which the floating point package lacks: <SINE> and <COSINE> with
;;   <SIN_COEFFICIENTS>, <ARCTANGENT> and <SQUARE_ROOT>.
;; - The cartridge's header, <CARTRIDGE_HEADER>, at CARTCS.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; The polynomials, in coefficients.
IO_SIN_COEFFICIENT_COUNT = 6        ;; the coefficients of <SIN_COEFFICIENTS>

IO_SQR_STEPS = 7                    ;; the most Newton's method steps <SQUARE_ROOT> takes

;; Emits a string's characters last first.
;; Parameters: text = the string
.macro IO_BACKWARDS text
    .repeat .strlen(text), index
    .byte .strat(text, .strlen(text) - 1 - index)
    .endrepeat
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The IOCBs
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a statement's "#n": skips the # token, evaluates the IOCB's number, and finds its IOCB.
;;
;; Only the number's low byte counts, and only its low nibble picks the IOCB: #16 reaches IOCB 0 and #257 IOCB 1,
;; though IOCB_NUMBER keeps the number's low byte.
;; In: TOKEN_OFFSET = the # token
;; Out: IOCB_NUMBER = the number, X = the IOCB's offset from IOCB 0 (the number times 16), zero = IOCB 0
;; Uses: A, Y, FR0, TOKEN_OFFSET
;; Errors: 20 (ERR_DEVICE_NUMBER) for 0, or 8 to 15; 3 (ERR_VALUE) or 7 (ERR_NUMBER_TOO_BIG) for a number not from
;;   0 to 32767
;; See: <IOCB_OFFSET>
IOCB_FROM_HASH:
    jsr NEXT_INTEGER_BYTE
    sta IOCB_NUMBER
    beq IOCB_DEVICE_NUMBER_ERROR    ; #0 is the screen editor's, which BASIC keeps to itself
;; Finds the IOCB of the number in IOCB_NUMBER.
;; In: IOCB_NUMBER = the IOCB's number
;; Out: X = the IOCB's offset from IOCB 0, the number times 16, A = X, zero = IOCB 0
;; Keeps: Y
;; Errors: 20 (ERR_DEVICE_NUMBER) for a number from 8 to 15
IOCB_OFFSET:
    lda IOCB_NUMBER
    asl A
    asl A
    asl A
    asl A
    tax
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    bmi IOCB_DEVICE_NUMBER_ERROR    ; a number from 8 to 15 sets bit 7
    rts
.else
    bpl IO_DONE                     ; a number from 8 to 15 sets bit 7
.endif
IOCB_DEVICE_NUMBER_ERROR:
    jsr DEVICE_NUMBER_ERROR         ; error 20
;; Checks the status of the last CIO call on the IOCB in IOCB_NUMBER, and raises a CIO error as BASIC's.
;;
;; A status below 128 returns. Any error first turns DSPFLG off. BREAK (BRKABT) clears BRKKEY, leaving the break for
;; the execution loop to stop the program, and returns; but during LOAD (LOAD_FLAG set) the program is half read, and
;; BASIC starts cold. The end of the file (EOFERR) on IOCB 7 while the line editor reads (PROMPT = PROMPT_EDITOR) is
;; the end of ENTER's file: IOCB 7 is closed and BASIC says READY. Any other error closes IOCB 7 if it was the IOCB,
;; puts input and output back on the screen editor, and goes to the error handler with the status as the error's
;; number.
;; In: IOCB_NUMBER = the IOCB
;; Out: X = the IOCB's offset from IOCB 0, A = its status
;; Uses: Y
;; Errors: the status, 128 or more, as the error number; 20 (ERR_DEVICE_NUMBER) for IOCB 8 to 15
;; Entry: CHECK_STATUS = with the status in A and its negative flag
;; See: <HANDLE_ERROR>
CHECK_IO_STATUS:
    jsr IOCB_STATUS
CHECK_STATUS:
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    bmi CHECK_STATUS_ERROR
    rts                             ; no error
CHECK_STATUS_ERROR:
.else
    bpl IO_DONE                     ; no error
.endif
    ldy #$00
    sty DSPFLG
    cmp #BRKABT
    bne CHECK_IO_STATUS_ERROR
    sty BRKKEY                      ; 0: BREAK is still pending
    lda LOAD_FLAG
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    beq CHECK_IO_STATUS_BREAK
    jmp CARTRIDGE_START             ; a cut-short LOAD starts cold
CHECK_IO_STATUS_BREAK:
    rts
.else
    beq IO_DONE
    jmp CARTRIDGE_START             ; a cut-short LOAD starts cold
.endif
CHECK_IO_STATUS_ERROR:
    ldy IOCB_NUMBER
    cmp #EOFERR
    beq CHECK_IO_STATUS_EOF
CHECK_IO_STATUS_RAISE:
    sta ERROR_NUMBER
    cpy #FILE_IOCB
    bne CHECK_IO_STATUS_REPORT
    jsr CLOSE_IOCB
CHECK_IO_STATUS_REPORT:
    jsr DEFAULT_IOCBS
    jmp HANDLE_ERROR
CHECK_IO_STATUS_EOF:
    cpy #FILE_IOCB
    bne CHECK_IO_STATUS_RAISE
    ldx #PROMPT_EDITOR
    cpx PROMPT
    bne CHECK_IO_STATUS_RAISE       ; INPUT # reached the end of the file
    jsr CLOSE_IOCB                  ; ENTER has read the whole file
    jmp WARM_START_SCREEN

;; Closes the IOCB in IOCB_NUMBER, unless it is IOCB 0.
;; In: IOCB_NUMBER = the IOCB
;; Out: X = the IOCB's offset from IOCB 0, Y = CIO's status
;; Uses: A
;; Errors: 20 (ERR_DEVICE_NUMBER) for IOCB 8 to 15
CLOSE_IOCB:
    jsr IOCB_OFFSET
    beq IO_DONE                     ; never the screen editor's
    lda #CCLOSE
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp CALL_CIO_A
.else
    bne CALL_CIO_A                  ; always
.endif

;; Finds the IOCB in IOCB_NUMBER and reads its status.
;; In: IOCB_NUMBER = the IOCB
;; Out: X = the IOCB's offset from IOCB 0, A = its status (ICSTA), negative = an error
;; Keeps: Y
;; Errors: 20 (ERR_DEVICE_NUMBER) for IOCB 8 to 15
IOCB_STATUS:
    jsr IOCB_OFFSET
    lda ICSTA,x
IO_DONE:
    rts

;; Skips a token, then evaluates the expression after it as an integer and gives its low byte.
;;
;; For a "#n" or a statement's argument that must be from 0 to 255; numbers past 255 are not refused.
;; In: TOKEN_OFFSET = the token before the expression
;; Out: A = the integer's low byte, FR0 = the integer (2 bytes)
;; Uses: X, Y, TOKEN_OFFSET
;; Errors: 3 (ERR_VALUE) or 7 (ERR_NUMBER_TOO_BIG) for a number not from 0 to 32767
;; Entry: INTEGER_BYTE = with TOKEN_OFFSET at the expression
NEXT_INTEGER_BYTE:
    inc TOKEN_OFFSET
INTEGER_BYTE:
    jsr EVALUATE_INTEGER
    lda FR0
    rts

;; Calls CIO with the command in IO_COMMAND, the buffer at INBUFF and a length of 255 bytes, for a line.
;;
;; INBUFF is normally LBUFF, which holds 96 bytes; a longer line runs on over the floating point package's
;; scratch registers and into page 6.
;; In: X = the IOCB's offset from IOCB 0, IO_COMMAND = the command, INBUFF = the buffer
;; Out: Y = CIO's status, negative = an error
;; Uses: A
;; Entry:
;;   CALL_CIO_LENGTH = with Y = the length, below 256
;;   CALL_CIO_LENGTH_AY = with A = the length's high byte and Y its low byte
;;   CALL_CIO_BUFFER = with the length already in the IOCB
;;   CALL_CIO = with the buffer and its length already in the IOCB
;;   CALL_CIO_A = with A = the command, which IO_COMMAND does not keep
;; See: <CHECK_IO_STATUS>
CALL_CIO_LINE:
    ldy #$FF
    bne CALL_CIO_LENGTH             ; always
    .byte $A0, $00                  ; unreached: ldy #0, a length of 0
CALL_CIO_LENGTH:
    lda #$00
CALL_CIO_LENGTH_AY:
    sta ICBLH,x
    tya
    sta ICBLL,x
CALL_CIO_BUFFER:
    lda INBUFF+1
    ldy INBUFF
    sta ICBAH,x
    tya
    sta ICBAL,x
CALL_CIO:
    lda IO_COMMAND
CALL_CIO_A:
    sta ICCOM,x
.if VERSION = VERSION_A
    jsr CIOV                        ; rev. A calls CIO and returns, where the later revisions jump to it
    rts
.else
    jmp CIOV
.endif

;; Stores a byte as a number in the variable that the statement names next, as STATUS, NOTE and GET do.
;; In: A = the byte, TOKEN_OFFSET = the variable's token
;; Uses: A, X, Y, FR0, VALUE_TYPE, VALUE_NUMBER, VARIABLE_ENTRY, TOKEN_OFFSET
;; Entry: SET_VARIABLE_INTEGER = with A = an integer's low byte and Y = its high byte
SET_VARIABLE_BYTE:
    ldy #$00
SET_VARIABLE_INTEGER:
    pha
    tya
    pha
    jsr EVALUATE_VALUE              ; the variable, for its number
    pla
    sta FR0+1
    pla
    sta FR0
    jsr IFP
    jmp STORE_VARIABLE

; ---------------------------------------------------------------------------------------------------------------------
; Starting over
; ---------------------------------------------------------------------------------------------------------------------

;; Silences the sound and closes IOCBs 1 to 7, for the warm start and when a program ends.
;;
;; The loop clears POKEY's audio registers from AUDC1 to AUDC4 but stops short of AUDF1, which AUDC1's volume of 0
;; leaves silent anyway.
;; Out: IOCB_NUMBER = 0
;; Uses: A, X, Y
SILENCE_CLOSE_ALL:
    lda #$00
    ldx #AUDC4-AUDF1
SILENCE_CLOSE_ALL_SOUND:
    sta AUDF1,x
    dex
    bne SILENCE_CLOSE_ALL_SOUND
    ldy #FILE_IOCB
    sty IOCB_NUMBER
SILENCE_CLOSE_ALL_CLOSE:
    jsr CLOSE_IOCB
    dec IOCB_NUMBER
    bne SILENCE_CLOSE_ALL_CLOSE
    rts

.if VERSION >= VERSION_B
;; Puts INPUT, PRINT and LIST back on the screen editor, IOCB 0.
;; Out: INPUT_IOCB = 0, OUTPUT_IOCB = 0, A = 0
;; Keeps: X, Y
DEFAULT_IOCBS:
    lda #$00
    sta INPUT_IOCB
    sta OUTPUT_IOCB
    rts
.endif

;; Prints READY on a line of its own, through the output IOCB.
;; In: OUTPUT_IOCB = the IOCB
;; Uses: A, X, Y, CIX
;; See: <READY_TEXT>
PRINT_READY:
    ldx #READY_TEXT_SIZE-1
PRINT_READY_LOOP:
    stx CIX
    lda READY_TEXT,x
    jsr PUT_CHARACTER
    ldx CIX
    dex
    bpl PRINT_READY_LOOP
    rts

;; The text <PRINT_READY> prints, last character first: an EOL, READY and an EOL. <PRINT_EOL> prints its first.
READY_TEXT:
    .byte EOL
    IO_BACKWARDS "READY"
    .byte EOL
READY_TEXT_SIZE = * - READY_TEXT    ;; the bytes of <READY_TEXT>

;; Prints an EOL through the output IOCB, ending the line.
;; In: OUTPUT_IOCB = the IOCB
;; Uses: A, X, Y, CIX
PRINT_EOL:
    ldx #$00
    beq PRINT_READY_LOOP            ; always: READY_TEXT's first byte only

.if VERSION = VERSION_A
;; Puts INPUT, PRINT and LIST back on the screen editor, IOCB 0. Rev. A keeps it here, after PRINT_EOL.
;; Out: INPUT_IOCB = 0, OUTPUT_IOCB = 0, A = 0
;; Keeps: X, Y
DEFAULT_IOCBS:
    lda #$00
    sta INPUT_IOCB
    sta OUTPUT_IOCB
    rts
.endif

;; Pops a string and puts an EOL after it, so that the OS or the floating point package can read it as a line.
;;
;; For a device's file name, XIO's and VAL's strings. The byte the EOL replaces is kept, for <RESTORE_STRING_EOL>; a
;; string of 256 characters or more is cut to 255.
;; In: ARGUMENT_INDEX = the string's entry, the argument stack's top
;; Out: INBUFF = the string's address, PATCHED_CHARACTER = the byte after it, PATCHED_INDEX = its index from INBUFF,
;;   EOL_PATCHED = nonzero
;; Uses: A, X, Y, VALUE_TYPE, VALUE_NUMBER, FR0, ARGUMENT_INDEX
;; Errors: 9 (ERR_DIM) when the string has not been DIMensioned
PATCH_STRING_EOL:
    jsr POP_ABSOLUTE_VALUE
    lda FR0
    sta INBUFF
    lda FR0+1
    sta INBUFF+1
    ldy FR0+2                       ; the length's low byte
    ldx FR0+3
    beq PATCH_STRING_EOL_AT
    ldy #$FF
PATCH_STRING_EOL_AT:
    lda (INBUFF),y
    sta PATCHED_CHARACTER
    sty PATCHED_INDEX
    lda #EOL
    sta (INBUFF),y
    sta EOL_PATCHED
    rts

;; Puts back the byte that <PATCH_STRING_EOL> replaced with an EOL.
;; In: INBUFF = the string, PATCHED_CHARACTER = the byte, PATCHED_INDEX = its index
;; Out: EOL_PATCHED = 0
;; Uses: A, Y
;; Keeps: X
RESTORE_STRING_EOL:
    ldy PATCHED_INDEX
    lda PATCHED_CHARACTER
    sta (INBUFF),y
    lda #$00
    sta EOL_PATCHED
    rts

.if VERSION = VERSION_A
    .byte $20                       ; rev. A: a leftover byte, unused
.else
; ---------------------------------------------------------------------------------------------------------------------
; RETURN
; ---------------------------------------------------------------------------------------------------------------------

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
    beq RETURN_TO_ENTRY_DONE
    cmp #TOKEN_ON
    beq RETURN_TO_ENTRY_DONE
    cmp #TOKEN_LIST
    beq RETURN_TO_ENTRY_DONE
    cmp #TOKEN_READ
    beq RETURN_TO_ENTRY_DONE
;; Raises error 15 (ERR_LINE_DELETED), with STMCUR back on the line being run, for RETURN and NEXT.
;; Errors: 15 (ERR_LINE_DELETED)
RETURN_LINE_DELETED:
    jsr RESTORE_STMCUR
    jsr LINE_DELETED_ERROR          ; error 15
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
RETURN_TO_ENTRY_DONE:
    rts

    ; Unreached: ldx INPUT_IOCB, bne READ_INPUT_LINE, lda #EOL, jsr PUT_CHARACTER, which would end the screen's line
    ; before reading another.
    .byte $A6, $B4, $D0, $0E, $A9, $9B, $20, $99, $BA

; ---------------------------------------------------------------------------------------------------------------------
; Reading a line
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a line for INPUT, showing the prompt first when it reads from the screen editor.
;; In: INPUT_IOCB = the IOCB, PROMPT = the prompt, INBUFF = the buffer
;; Out: INBUFF = the line, ending with an EOL
;; Uses: A, X, Y, CIX, IOCB_NUMBER, IO_COMMAND
;; Errors: those of <CHECK_IO_STATUS>
;; Entry: READ_INPUT_LINE = without the prompt, for the line editor
PROMPT_INPUT_LINE:
    ldx INPUT_IOCB
    bne READ_INPUT_LINE
    lda PROMPT
    jsr PUT_CHARACTER
READ_INPUT_LINE:
    ldx INPUT_IOCB
    lda #CGTXTR
    jsr SET_IOCB_COMMAND
    jsr CALL_CIO_LINE
    jmp CHECK_IO_STATUS

; ---------------------------------------------------------------------------------------------------------------------
; +
; ---------------------------------------------------------------------------------------------------------------------

;; +: adds two numbers.
;;
;; Pops the two operands, adds them and pushes the sum.
;; Errors: 11 (ERR_FP_OVERFLOW) when the sum is out of range
OPERATOR_ADD:
    jsr POP_TWO_VALUES
    jsr CHECKED_FADD
    jmp PUSH_VALUE
.endif

; ---------------------------------------------------------------------------------------------------------------------
; SIN and COS
; ---------------------------------------------------------------------------------------------------------------------

SINE_FAIL:
    sec
    rts

;; Gives the sine of FR0, in radians, or in degrees when DEGFLG says so, for SIN.
;;
;; The angle is divided by a quarter turn (<QUADRANT_RADIANS> or <QUADRANT_DEGREES>), and the whole quarter turns
;; are counted modulo 4 in FCHRFLG, with the angle's sign: from 4 (counting as 0) for a positive angle, 2 for a
;; negative one, as sin(-x) is -sin(x), and 1 for COS, as cos(x) is sin(x + pi/2). What is left is z, from 0 to 1;
;; in an odd quarter turn (FCHRFLG's bit 0) it becomes 1 - z, and the sine is z times <SIN_COEFFICIENTS>' polynomial
;; in z squared, negated in the third and fourth quarter turns (bit 1).
;;
;; Taking the whole quarter turns off leaves the mantissa's last byte in them, except for an angle of a million
;; quarter turns or more, so that the remainder loses its last two digits.
;; In: FR0 = the angle, DEGFLG = 0 for radians, 6 for degrees
;; Out: FR0 = its sine, carry = clear
;; Uses: A, X, Y, FR1, FCHRFLG, DIGRT, FPSCR (PLYEVL's too)
;; Errors: carry = set for an angle of 100,000,000 quarter turns or more, or when a step is out of range
;; See: <COSINE>, <FUNCTION_SIN>
SINE:
    lda #4                          ; no quarter turns
    bit FR0
    bpl SINE_REDUCE_ANGLE
    lda #2                          ; two: negate
    bne SINE_REDUCE_ANGLE           ; always
;; Gives the cosine of FR0, in radians, or in degrees when DEGFLG says so, for COS: the sine a quarter turn on.
;; Inherit: <SINE>
;; Out: FR0 = its cosine, carry = clear
;; See: <SINE>, <FUNCTION_COS>
COSINE:
    lda #1                          ; one quarter turn
SINE_REDUCE_ANGLE:
    sta FCHRFLG
    lda FR0
    and #FP_SIGN ^ $FF
    sta FR0
    lda #<QUADRANT_RADIANS
    clc
    adc DEGFLG                      ; or QUADRANT_DEGREES
    tax
    ldy #>QUADRANT_RADIANS
    jsr FLD1R
    jsr FDIV                        ; FR0 = the angle in quarter turns
    bcc SINE_WHOLE_TURNS
    rts
SINE_WHOLE_TURNS:
    lda FR0
    and #FP_SIGN ^ $FF
    sec
    sbc #FP_EXPONENT_BIAS
    bmi SINE_REFLECT                ; less than one quarter turn
    cmp #4
    bpl SINE_FAIL                   ; 100^4 quarter turns or more
    tax
    lda FR0+1,x                     ; the mantissa byte of the units and tens
    sta DIGRT
    and #$10                        ; an odd tens digit counts 10, or 2 modulo 4
    beq SINE_ADD_QUADRANTS
    lda #2
SINE_ADD_QUADRANTS:
    clc
    adc DIGRT
    and #3                          ; the whole quarter turns, modulo 4
    adc FCHRFLG
    sta FCHRFLG
    stx DIGRT
    jsr FMOVE
    ldx DIGRT
    lda #$00
SINE_CLEAR_FRACTION:
    sta FR1+2,x                     ; FR1 = the whole quarter turns, but FR1+5 is left for an exponent below 3
    inx
    cpx #3
    bcc SINE_CLEAR_FRACTION
    jsr FSUB                        ; FR0 = the fraction of a quarter turn
SINE_REFLECT:
    lsr FCHRFLG
    bcc SINE_POLYNOMIAL
    jsr FMOVE                       ; an odd quarter turn: z = 1 - z
    ldx #<TRIG_ONE
    ldy #>TRIG_ONE
    jsr FLD0R
    jsr FSUB
SINE_POLYNOMIAL:
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep z
    jsr FMOVE
    jsr FMUL
    bcs SINE_FAIL
    lda #IO_SIN_COEFFICIENT_COUNT
    ldx #<SIN_COEFFICIENTS
    ldy #>SIN_COEFFICIENTS
    jsr PLYEVL
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD1R
    jsr FMUL                        ; times z
    lsr FCHRFLG
    bcc SINE_DONE
    clc
    lda FR0                         ; negate, unless it is 0
    beq SINE_DONE
    eor #FP_SIGN
    sta FR0
SINE_DONE:
    rts

;; The sine's polynomial, highest power first: sin(z * pi/2) is z times these in z squared, for z from 0 to 1.
;;
;; Its last coefficient, pi/2, is <QUADRANT_RADIANS>.
;; See: <SINE>
SIN_COEFFICIENTS:
    FP_NUMBER FP_NEGATIVE, -3, $03, $55, $14, $99, $39 ; -0.00000355149939
    FP_NUMBER FP_POSITIVE, -2, $01, $60, $44, $27, $52 ; 0.000160442752
    FP_NUMBER FP_NEGATIVE, -2, $46, $81, $75, $43, $55 ; -0.004681754355
    FP_NUMBER FP_POSITIVE, -1, $07, $96, $92, $62, $39 ; 0.0796926239
    FP_NUMBER FP_NEGATIVE, -1, $64, $59, $64, $08, $67 ; -0.6459640867
;; pi/2, 1.57079632, a quarter turn in radians: <SINE>'s divisor, and <SIN_COEFFICIENTS>' last coefficient.
QUADRANT_RADIANS:
    FP_NUMBER FP_POSITIVE, 0, $01, $57, $07, $96, $32
    .assert * - SIN_COEFFICIENTS = IO_SIN_COEFFICIENT_COUNT * FP_SIZE, "SIN's polynomial has 6 coefficients."

;; 90, a quarter turn in degrees, which <SINE> reaches as QUADRANT_RADIANS plus DEGFLG.
QUADRANT_DEGREES:
    FP_NUMBER FP_POSITIVE, 0, $90, $00, $00, $00, $00
    .assert QUADRANT_DEGREES - QUADRANT_RADIANS = 6, "DEG's DEGFLG of 6 picks 90 for SIN and COS."
    .assert >QUADRANT_RADIANS = >QUADRANT_DEGREES, "Both quarter turns are in one page."

;; pi/180, 0.0174532925, the radians in a degree, which <ARCTANGENT> divides by for DEG.
RADIANS_PER_DEGREE:
    FP_NUMBER FP_POSITIVE, -1, $01, $74, $53, $29, $25

;; 1.0, for <SINE>'s 1 - z.
TRIG_ONE:
    FP_NUMBER FP_POSITIVE, 0, $01, $00, $00, $00, $00

; ---------------------------------------------------------------------------------------------------------------------
; ATN
; ---------------------------------------------------------------------------------------------------------------------

;; Gives the arctangent of FR0, in radians, or in degrees when DEGFLG says so, for ATN.
;;
;; Below 1 in size, the arctangent is x times the floating point package's polynomial (ATN_COEFFICIENTS) in x
;; squared. From 1, it is pi/4 plus the arctangent of (|x| - 1) / (|x| + 1), with x's sign. The add's carry is not
;; checked.
;; In: FR0 = x, DEGFLG = 0 for radians, 6 for degrees
;; Out: FR0 = its arctangent
;; Uses: A, X, Y, FR1, FCHRFLG, DIGRT, FPSCR (PLYEVL's and FP_DIFFERENCE_OVER_SUM's too)
;; Errors: carry = set when a step is out of range
;; See: <FUNCTION_ATN>
ARCTANGENT:
    lda #$00
    sta FCHRFLG                     ; the sign to put back
    sta DIGRT                       ; nonzero to add pi/4
    lda FR0
    and #FP_SIGN ^ $FF
    cmp #FP_EXPONENT_BIAS
    bmi ARCTANGENT_POLYNOMIAL       ; less than 1 in size
    lda FR0
    and #FP_SIGN
    sta FCHRFLG
    inc DIGRT
    lda #FP_SIGN ^ $FF
    and FR0
    sta FR0
    ldx #<(ATN_COEFFICIENTS + (ATN_COEFFICIENT_COUNT - 1) * FP_SIZE) ; the last coefficient, 1.0
    ldy #>(ATN_COEFFICIENTS + (ATN_COEFFICIENT_COUNT - 1) * FP_SIZE)
    jsr FP_DIFFERENCE_OVER_SUM      ; (x - 1) / (x + 1)
ARCTANGENT_POLYNOMIAL:
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep z
    jsr FMOVE
    jsr FMUL
    bcs ARCTANGENT_DONE
    lda #ATN_COEFFICIENT_COUNT
    ldx #<ATN_COEFFICIENTS
    ldy #>ATN_COEFFICIENTS
    jsr PLYEVL
    bcs ARCTANGENT_DONE
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD1R
    jsr FMUL                        ; times z
    bcs ARCTANGENT_DONE
    lda DIGRT
    beq ARCTANGENT_DEGREES
    ldx #<FP_PI_OVER_4
    ldy #>FP_PI_OVER_4
    jsr FLD1R
    jsr FADD
    lda FCHRFLG
    ora FR0
    sta FR0
ARCTANGENT_DEGREES:
    lda DEGFLG
    beq ARCTANGENT_DONE
    ldx #<RADIANS_PER_DEGREE
    ldy #>RADIANS_PER_DEGREE
    jsr FLD1R
    jsr FDIV
ARCTANGENT_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; SQR
; ---------------------------------------------------------------------------------------------------------------------

SQUARE_ROOT_FAIL:
    sec
    rts

;; Gives the square root of FR0, for SQR.
;;
;; The number is scaled by an even power of 10 to y, from 0.01 to 1, and the root of y found by Newton's method:
;; from a first guess of y(2 - y), each step adds (y/g - g) / 2 to the guess g, stopping when that is 0 or after
;; seven steps. The root of the scale, a power of 10, multiplies the result back.
;;
;; When the seven steps run out, the result is the guess before the last step, which is lost. The divides in the
;; steps are not checked, and the clearing of FR1's mantissa runs on into FR2's first byte.
;; In: FR0 = the number
;; Out: FR0 = its square root
;; Uses: A, X, Y, FR1, FR2, DIGRT, ESIGN, FPSCR, FPSCR1
;; Errors: carry = set for a negative number, or when the last multiply is out of range
;; See: <FUNCTION_SQR>
SQUARE_ROOT:
    lda #$00
    sta DIGRT                       ; the scale's exponent byte, 0 when not scaled
    lda FR0
    bmi SQUARE_ROOT_FAIL
    cmp #FP_EXPONENT_BIAS - 1
    beq SQUARE_ROOT_GUESS           ; from 0.01 to 1 already
    clc
    adc #$01
    sta DIGRT
    sta FR1                         ; FR1 = 100 to the power after the number's
    lda #$01
    sta FR1+1
    ldx #FP_SIZE - 2
    lda #$00
SQUARE_ROOT_CLEAR_SCALE:
    sta FR1+2,x                     ; FR1+2 to FR1+6, one byte past FR1
    dex
    bpl SQUARE_ROOT_CLEAR_SCALE
    jsr FDIV                        ; FR0 = y
SQUARE_ROOT_GUESS:
    lda #IO_SQR_STEPS - 1
    sta ESIGN                       ; the steps left
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep y
    jsr FMOVE
    ldx #<FP_TWO
    ldy #>FP_TWO
    jsr FLD0R
    jsr FSUB
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD1R
    jsr FMUL                        ; the first guess, y(2 - y)
SQUARE_ROOT_STEP:
    ldx #<FPSCR1
    ldy #>FPSCR1
    jsr FST0R                       ; keep the guess
    jsr FMOVE
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD0R
    jsr FDIV                        ; y / g
    ldx #<FPSCR1
    ldy #>FPSCR1
    jsr FLD1R
    jsr FSUB                        ; less g
    ldx #<FP_HALF
    ldy #>FP_HALF
    jsr FLD1R
    jsr FMUL                        ; halved
    lda FR0
    beq SQUARE_ROOT_SCALE           ; no change: done
    ldx #<FPSCR1
    ldy #>FPSCR1
    jsr FLD1R
    jsr FADD                        ; the next guess
    dec ESIGN
    bpl SQUARE_ROOT_STEP
SQUARE_ROOT_SCALE:
    ldx #<FPSCR1
    ldy #>FPSCR1
    jsr FLD0R
    lda DIGRT
    beq SQUARE_ROOT_DONE
    sec
    sbc #FP_EXPONENT_BIAS
    clc
    ror A                           ; half the scale's power of 100, modulo 128
    clc
    adc #FP_EXPONENT_BIAS
    and #FP_SIGN ^ $FF
    sta FR1
    lda DIGRT
    ror A                           ; an odd power of 100 has a root of 10 times a whole power
    lda #$01
    bcc SQUARE_ROOT_MANTISSA
    lda #$10
SQUARE_ROOT_MANTISSA:
    sta FR1+1
    ldx #FP_SIZE - 2
    lda #$00
SQUARE_ROOT_CLEAR_ROOT:
    sta FR1+2,x                     ; FR1+2 to FR1+6, one byte past FR1
    dex
    bpl SQUARE_ROOT_CLEAR_ROOT
    jsr FMUL
SQUARE_ROOT_DONE:
.if VERSION >= VERSION_B
;; The cartridge's initialization routine, which the OS calls at start-up through CARTAD: SQR's last RTS, doing
;; nothing.
CARTRIDGE_INIT:
.endif
    rts

.if VERSION = VERSION_A
;; 2.0, for <SQUARE_ROOT>'s first guess. Rev. A keeps it here; the later revisions keep it among the devices'
;; routines.
FP_TWO:
    FP_NUMBER FP_POSITIVE, 0, $02, $00, $00, $00, $00

    ; Rev. A: leftover bytes, unused.
    .byte $30, $30, $20, $20, $60, $70, $70, $00, $00, $00, $00, $30, $30, $3C, $7C, $7C
    .byte $7C, $64, $64, $67, $E7, $C0, $C0, $80, $80, $E0, $E0, $00, $00, $00, $00, $30
    .byte $30, $38, $38, $38, $38, $FC, $EC, $EC, $0C, $04, $06, $06, $02, $03, $03, $00
    .byte $00, $00, $00, $30, $30, $30, $B0, $B0, $D8, $F8, $78, $38, $18, $18, $18, $10
    .byte $10, $1C, $1C, $00, $00, $00, $00, $30, $30, $30, $30, $30, $30, $30, $30, $20
    .byte $E0, $E0, $80, $80, $00, $00, $00, $00, $00, $00, $00, $CC, $B8, $A4, $90, $A0

;; The cartridge's initialization routine, which the OS calls at start-up through CARTAD: an RTS of its own in rev.
;; A, doing nothing.
CARTRIDGE_INIT:
    rts
.endif

; ---------------------------------------------------------------------------------------------------------------------
; The cartridge header
; ---------------------------------------------------------------------------------------------------------------------

.if VERSION = VERSION_B
    .byte $00, $00
    .byte ",7inner"                 ; rev. B: leftover bytes, unused
.endif
    .res CARTCS - *, $00            ; unused

;; The left cartridge's header, which the OS reads at start-up: BASIC starts at its cold start, after booting the
;; disk.
CARTRIDGE_HEADER:
    .assert * = CARTCS, "The header is at CARTCS."
    .word CARTRIDGE_START           ; CARTCS: the start address, the cold start
    .assert * = CART, "CART follows CARTCS."
    .byte $00                       ; CART: 0, a cartridge is present
    .assert * = CARTFG, "CARTFG follows CART."
    .byte CART_BOOT_DISK | CART_RUN ; CARTFG: boot the disk, then run the cartridge
    .assert * = CARTAD, "CARTAD follows CARTFG."
    .word CARTRIDGE_INIT            ; CARTAD: the initialization address
