;; DEVICES ($B90A-$BCA7)
;;
;; The errors, and the statements that work the screen, the sound and the devices. Maintained by hand; assembles
;; byte-identically to the cartridge.
;;
;; - The error entries, from <LOAD_FILE_ERROR> (21) to <MEMORY_INSUFFICIENT_ERROR> (2), and <HANDLE_ERROR>, which
;;   goes to TRAP's line or prints "ERROR- n AT LINE m"; <REPORT_AT_LINE>, which STOP shares.
;; - <STATEMENT_SETCOLOR>, <STATEMENT_SOUND>, <STATEMENT_POSITION>, <STATEMENT_COLOR>, <STATEMENT_DRAWTO>,
;;   <STATEMENT_GRAPHICS> and <STATEMENT_PLOT>; in revisions B and C, `NUMBER_HAS_FRACTION`, for ^.
;; - Character output straight through a handler: <PUT_CHARACTER>.
;; - <STATEMENT_ENTER>, <OPEN_LIST_FILE> and <OPEN_FILE_IOCB>, which open IOCB 7 on a file; <FP_TWO>, for SQR (rev. A's
;;   is in InputOutput.asm).
;; - <STATEMENT_LOAD>, <LOAD_AND_RUN>, <STATEMENT_CLOAD>, <STATEMENT_SAVE> and <STATEMENT_CSAVE>, with
;;   <LOAD_PROGRAM>, <SAVE_PROGRAM> and <TRANSFER_TABLES>; <OPEN_CASSETTE> and <OPEN_DEVICE>.
;; - <STATEMENT_XIO>, <STATEMENT_OPEN>, <STATEMENT_CLOSE>, <STATEMENT_STATUS>, <STATEMENT_NOTE>, <STATEMENT_POINT>,
;;   <STATEMENT_PUT>, <STATEMENT_GET> and <STATEMENT_LOCATE>.
;;
;; A saved program is a header of seven words, each of LOMEM to STARP less LOMEM (so the first is 0), then the tables
;; from VNTP up to STARP: the variable names, the variable values and the statement table, with the immediate line.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

DEVICES_COLOR_REGISTERS = 5         ;; SETCOLOR's registers, 0-4: COLOR0 to COLOR4
DEVICES_SOUND_VOICES = 4            ;; SOUND's voices, 0-3: POKEY's four channels
DEVICES_SKCTL_KEYBOARD = %00000011  ;; SKCTL with the keyboard scanned and debounced; two-tone and serial off
DEVICES_GRAPHICS_OPTIONS = $F0      ;; GRAPHICS' options in its number: 16 for no text window, 32 not to clear
DEVICES_RUN = $FF                   ;; LOAD_PROGRAM's flag to go on running, for RUN with a file name

; ---------------------------------------------------------------------------------------------------------------------
; The errors
; ---------------------------------------------------------------------------------------------------------------------

; Each entry adds 1 to ERROR_NUMBER, which is 0 until an error, and falls into the next, so that the entry that a
; routine calls leaves the error's number in ERROR_NUMBER when the chain reaches HANDLE_ERROR. A routine raises an
; error by calling its entry, and never comes back.

;; Raises error 21, LOAD file error: the file LOAD read is not a saved program.
;; Errors: 21 (ERR_LOAD_FILE)
LOAD_FILE_ERROR:
    inc ERROR_NUMBER
;; Raises error 20, device number larger than 7 or equal to 0, for an IOCB after #.
;; Errors: 20 (ERR_DEVICE_NUMBER)
DEVICE_NUMBER_ERROR:
    inc ERROR_NUMBER
;; Raises error 19, LOAD program too long: the program would reach MEMTOP.
;; Errors: 19 (ERR_LOAD_TOO_LONG)
LOAD_TOO_LONG_ERROR:
    inc ERROR_NUMBER
;; Raises error 18, invalid string character: VAL's string doesn't start with a number.
;; Errors: 18 (ERR_INVALID_STRING)
INVALID_STRING_CHARACTER_ERROR:
    inc ERROR_NUMBER
;; ERROR: raises error 17, garbage error, for a line stored with a syntax error.
;;
;; The line editor keeps a line it can't tokenize, after the TOKEN_ERROR token, so that it can be listed and fixed;
;; running it is the error.
;; Errors: 17 (ERR_GARBAGE)
STATEMENT_ERROR:
    inc ERROR_NUMBER
;; Raises error 16, RETURN error: a RETURN without a matching GOSUB.
;; Errors: 16 (ERR_RETURN)
RETURN_ERROR:
    inc ERROR_NUMBER
;; Raises error 15, GOSUB or FOR line deleted: RETURN or NEXT can't find the line their entry came from.
;; Errors: 15 (ERR_LINE_DELETED)
LINE_DELETED_ERROR:
    inc ERROR_NUMBER
;; Raises error 14, line too long: the line's tokens, or the syntax checker's stack, overflow.
;; Errors: 14 (ERR_LINE_TOO_LONG)
LINE_TOO_LONG_ERROR:
    inc ERROR_NUMBER
;; Raises error 13, no matching FOR statement: a NEXT without its FOR.
;; Errors: 13 (ERR_NO_FOR)
NO_MATCHING_FOR_ERROR:
    inc ERROR_NUMBER
;; Raises error 12, line not found: GOTO, GOSUB, THEN or TRAP's line doesn't exist.
;; Errors: 12 (ERR_LINE_NOT_FOUND)
LINE_NOT_FOUND_ERROR:
    inc ERROR_NUMBER
;; Raises error 11, floating point overflow/underflow: a result out of range, or a divide by zero.
;; Errors: 11 (ERR_FP_OVERFLOW)
FLOATING_POINT_OVERFLOW_ERROR:
    inc ERROR_NUMBER
;; Raises error 10, argument stack overflow: an expression too complex.
;; Errors: 10 (ERR_STACK_OVERFLOW)
ARGUMENT_STACK_OVERFLOW_ERROR:
    inc ERROR_NUMBER
;; Raises error 9, array or string DIM error: a size or subscript out of range, or a DIM missing or repeated.
;; Errors: 9 (ERR_DIM)
DIM_ERROR:
    inc ERROR_NUMBER
;; Raises error 8, input statement error: INPUT or READ found no number for a numeric variable.
;; Errors: 8 (ERR_INPUT)
INPUT_STATEMENT_ERROR:
    inc ERROR_NUMBER
;; Raises error 7, number greater than 32767: a value from 32768 to 65535 where one up to 32767 is needed.
;; Errors: 7 (ERR_NUMBER_TOO_BIG)
NUMBER_TOO_BIG_ERROR:
    inc ERROR_NUMBER
;; Raises error 6, out of data: READ ran past the last DATA.
;; Errors: 6 (ERR_OUT_OF_DATA)
OUT_OF_DATA_ERROR:
    inc ERROR_NUMBER
;; Raises error 5, string length error: beyond the string's DIMensioned length.
;; Errors: 5 (ERR_STRING_LENGTH)
STRING_LENGTH_ERROR:
    inc ERROR_NUMBER
;; Raises error 4, too many variables: a 129th variable name.
;; Errors: 4 (ERR_TOO_MANY_VARIABLES)
TOO_MANY_VARIABLES_ERROR:
    inc ERROR_NUMBER
;; Raises error 3, value error: a value out of the range it must be in.
;; Errors: 3 (ERR_VALUE)
VALUE_ERROR:
    inc ERROR_NUMBER
;; Raises error 2, memory insufficient: no room for a line, a variable, an array or a stack entry.
;; Errors: 2 (ERR_MEMORY)
MEMORY_INSUFFICIENT_ERROR:
    inc ERROR_NUMBER
    inc ERROR_NUMBER
    .assert MEMORY_INSUFFICIENT_ERROR - LOAD_FILE_ERROR = 2 * (ERR_LOAD_FILE - ERR_MEMORY), "An entry for each error."
    .assert STATEMENT_ERROR - LOAD_FILE_ERROR = 2 * (ERR_LOAD_FILE - ERR_GARBAGE), "ERROR raises error 17."

;; Handles the error in ERROR_NUMBER: goes to TRAP's line, or reports it and goes back to the line editor.
;;
;; STOPLN is set to the line being run, for CONT. With a TRAP set, the trap is taken once: TRAP is cleared, the
;; error's number is kept in ERRSAV (for PEEK(195)), and the program goes on at TRAP's line, as GOTO would. Without
;; one, BASIC prints "ERROR-" and the number, and for a program line "AT LINE" and its number, then reads the next
;; line without printing READY. CIO's errors come here with its status, 128 up, as the number.
;; In: ERROR_NUMBER = the error
;; Errors: 12 (ERR_LINE_NOT_FOUND) when TRAP's line doesn't exist, which is then reported, as TRAP is cleared
;; See: <STATEMENT_TRAP>, <CHECK_IO_STATUS>
HANDLE_ERROR:
    lda #$00                        ; stop showing control characters, for LIST
    sta DSPFLG
    jsr KEEP_STOP_LINE              ; STOPLN, and back to the screen and keyboard
    lda TRAP_LINE+1
    bmi HANDLE_ERROR_REPORT         ; no TRAP
    sta LINE_NUMBER+1
    lda TRAP_LINE
    sta LINE_NUMBER
    lda #TRAP_OFF
    sta TRAP_LINE+1
    lda ERROR_NUMBER
    sta ERRSAV
    lda #$00
    sta ERROR_NUMBER
    jmp GO_TO_LINE                  ; go to TRAP's line
HANDLE_ERROR_REPORT:
    jsr PRINT_EOL                   ; a new line
    lda #TOKEN_ERROR                ; "ERROR-" and its spaces, ERROR's name
    jsr LIST_STATEMENT_NAME
    lda ERROR_NUMBER
    sta FR0
    lda #$00
    sta FR0+1
    jsr PRINT_INTEGER
;; Ends an error's or STOP's message: prints " AT LINE" and the line's number for a program line, then goes back to
;; the line editor.
;;
;; Clears ERROR_NUMBER for the next error, and from rev. B takes INPUT and PRINT back to the screen and keyboard
;; again, as <KEEP_STOP_LINE> has already done in every revision.
;; In: STMCUR = the line that was being run
;; See: <HANDLE_ERROR>, <STATEMENT_STOP>
REPORT_AT_LINE:
    jsr GET_LINE_NUMBER_HIGH        ; the line number's high byte
    bmi REPORT_AT_LINE_DONE         ; the immediate line has none
    lda #<AT_LINE_MESSAGE
    sta NAME_POINTER
    lda #>AT_LINE_MESSAGE
    sta NAME_POINTER+1
    jsr LIST_PRINT_NAME
    ldy #LINE_NUMBER_OFFSET+1
    lda (STMCUR),y
    sta FR0+1
    dey
    lda (STMCUR),y
    sta FR0
    jsr PRINT_INTEGER
REPORT_AT_LINE_DONE:
    jsr PRINT_EOL                   ; a new line
    lda #$00
    sta ERROR_NUMBER
.if VERSION >= VERSION_B
    jsr DEFAULT_IOCBS               ; again: KEEP_STOP_LINE has done it
.endif
    jmp EDIT_LINE

;; Prints a 16-bit integer, through the output IOCB.
;;
;; It also uses what <FASC> uses.
;; In: FR0 = the integer, low byte first
;; Out: INBUFF = the text's first character, LBUFF or the byte after it
;; Uses: A, X, Y, FR0, LBUFF, NAME_POINTER, LIST_COUNT
PRINT_INTEGER:
    jsr IFP
    jsr FASC
    lda INBUFF
    sta NAME_POINTER
    lda INBUFF+1
    sta NAME_POINTER+1
.if VERSION = VERSION_A             ; rev. A calls and returns, where the later revisions jump
    jsr LIST_PRINT_NAME             ; FASC ends the text with bit 7 set, as a name
    rts
.else
    jmp LIST_PRINT_NAME             ; FASC ends the text with bit 7 set, as a name
.endif

;; " AT LINE ", ending with bit 7 set as a name does.
AT_LINE_MESSAGE:
    .byte " AT LINE", ' ' | NAME_END

; ---------------------------------------------------------------------------------------------------------------------
; The screen and the sound
; ---------------------------------------------------------------------------------------------------------------------

;; SETCOLOR: sets a colour register: SETCOLOR aexp1, aexp2, aexp3.
;;
;; aexp1 is the register, 0-4, for COLOR0 to COLOR4, the OS's shadows of the playfield and background colours;
;; aexp2 is the hue and aexp3 the luminance, stored as hue * 16 + luminance. Only the register is checked: the hue
;; and luminance are taken modulo 256 and may run into each other.
;; In: TOKEN_OFFSET = the first expression's token
;; Errors: 3 (ERR_VALUE) when the register is above 4, 7 (ERR_NUMBER_TOO_BIG) when it is from 32768
;; See: <STATEMENT_COLOR>
STATEMENT_SETCOLOR:
    jsr EVALUATE_BYTE               ; the register
    lda FR0
    cmp #DEVICES_COLOR_REGISTERS
    bcs SETCOLOR_VALUE_ERROR
    pha
    jsr EVALUATE_UNSIGNED           ; the hue, to the high nibble
    lda FR0
    asl A
    asl A
    asl A
    asl A
    pha
    jsr EVALUATE_UNSIGNED           ; the luminance
    pla
    clc
    adc FR0
    tay
    pla
    tax
    tya
    sta COLOR0,x
    rts
SETCOLOR_VALUE_ERROR:
    jsr VALUE_ERROR

;; SOUND: plays a note on one of POKEY's channels: SOUND aexp1, aexp2, aexp3, aexp4.
;;
;; aexp1 is the voice, 0-3; aexp2 the pitch, the channel's frequency divider (0-255, higher is lower); aexp3 the
;; distortion, 0-14 in even numbers, 10 for a pure tone; aexp4 the volume, 0-15, 0 for silence. The note plays until
;; another SOUND to the voice, or END, which silences them all. Every SOUND sets AUDCTL to 0 (the 64 kHz clock, the
;; channels apart) and takes SKCTL out of the cassette's two-tone mode, without updating its shadow SSKCTL.
;; In: TOKEN_OFFSET = the first expression's token
;; Errors: 3 (ERR_VALUE) when the voice is above 3, 7 (ERR_NUMBER_TOO_BIG) when it is from 32768
STATEMENT_SOUND:
    jsr EVALUATE_BYTE               ; the voice
    lda FR0
    cmp #DEVICES_SOUND_VOICES
    bcs SETCOLOR_VALUE_ERROR
    asl A                           ; its channel's offset from AUDF1: two registers each
    pha
    lda #$00
    sta AUDCTL
    lda #DEVICES_SKCTL_KEYBOARD
    sta SKCTL
    jsr EVALUATE_UNSIGNED           ; the pitch
    pla
    pha
    tax
    lda FR0
    sta AUDF1,x
    jsr EVALUATE_UNSIGNED           ; the distortion, to the high nibble
    lda FR0
    asl A
    asl A
    asl A
    asl A
    pha
    jsr EVALUATE_UNSIGNED           ; the volume
    pla
    tay
    pla
    tax
    tya
    clc
    adc FR0
    sta AUDC1,x
    rts

;; POSITION: moves the screen's cursor: POSITION aexp1, aexp2.
;;
;; aexp1 is the column, kept as 16 bits for the 320-dot graphics mode, aexp2 the row, 0-255. Nothing moves on the
;; screen until the next PRINT, PLOT or DRAWTO. DRAWTO, PLOT and LOCATE read their coordinates through it.
;; In: TOKEN_OFFSET = the first expression's token
;; Out: COLCRS = the column, ROWCRS = the row
;; Errors: 3 (ERR_VALUE) when the row is above 255, 7 (ERR_NUMBER_TOO_BIG) when it is from 32768
STATEMENT_POSITION:
    jsr EVALUATE_UNSIGNED
    lda FR0
    sta COLCRS
    lda FR0+1
    sta COLCRS+1
    jsr EVALUATE_BYTE
    lda FR0
    sta ROWCRS
    rts

;; COLOR: chooses the colour PLOT and DRAWTO draw with: COLOR aexp.
;;
;; In a graphics mode it is the colour register's number; in a text mode, the character drawn. It is taken modulo
;; 256.
;; In: TOKEN_OFFSET = the expression's token
;; Out: PLOT_COLOR = the colour
STATEMENT_COLOR:
    jsr EVALUATE_UNSIGNED
    lda FR0
    sta PLOT_COLOR
    rts

;; DRAWTO: draws a line from the cursor to a point: DRAWTO aexp1, aexp2.
;;
;; The point is the column and row, as for POSITION. The line is drawn in COLOR's colour by the screen's DRAWTO
;; command, through IOCB 6, which GRAPHICS opened; ICAX1 is set to $0C and ICAX2 to 0 for it, as the OS asks.
;; In: TOKEN_OFFSET = the first expression's token
;; Errors: those of <STATEMENT_POSITION>, and CIO's status when the screen reports one
STATEMENT_DRAWTO:
    jsr STATEMENT_POSITION
    lda PLOT_COLOR
    sta ATACHR
    lda #CDRAW
    ldx #SCREEN_IOCB
    jsr SET_IOCB_COMMAND
    lda #OREAD | OWRIT
    sta ICAX1,x
    lda #$00
    sta ICAX2,x
    jsr CALL_CIO
    jmp CHECK_IO_STATUS

;; GRAPHICS: chooses a graphics mode: GRAPHICS aexp.
;;
;; Closes IOCB 6 and opens it again on "S:" in the mode, so that the screen handler clears the screen and sets it
;; up. aexp's low four bits are the mode; adding 16 leaves out the text window at the bottom, and adding 32 keeps the
;; screen's memory uncleared. They become ICAX2 = the number and ICAX1 = reading and writing, with the text window
;; unless 16 is set, and 32 as it is.
;; In: TOKEN_OFFSET = the expression's token
;; Errors: 3 (ERR_VALUE) when aexp is negative or beyond 65535, and CIO's status when the screen reports one (such as
;;   147, not enough memory for the mode)
;; See: <OPEN_DEVICE>
STATEMENT_GRAPHICS:
    ldx #SCREEN_IOCB
    stx IOCB_NUMBER
    jsr CLOSE_IOCB                  ; close it
    jsr EVALUATE_UNSIGNED
    ldx #<SCREEN_DEVICE_NAME
    ldy #>SCREEN_DEVICE_NAME
    stx INBUFF
    sty INBUFF+1
    ldx #SCREEN_IOCB
    lda FR0
    and #DEVICES_GRAPHICS_OPTIONS
    eor #OREAD | OWRIT | OSPLIT     ; a text window unless 16 is set
    tay
    lda FR0
    jsr OPEN_DEVICE
    jmp CHECK_IO_STATUS

;; "S:", the screen's device name, ending with an EOL.
SCREEN_DEVICE_NAME:
    .byte "S:", EOL

;; PLOT: plots a point in COLOR's colour: PLOT aexp1, aexp2.
;;
;; The point is the column and row, as for POSITION; the colour is put through IOCB 6 there, which moves the cursor.
;; In: TOKEN_OFFSET = the first expression's token
;; Errors: those of <STATEMENT_POSITION>, and CIO's status when the screen reports one
STATEMENT_PLOT:
    jsr STATEMENT_POSITION
    lda PLOT_COLOR
    ldx #SCREEN_IOCB
    jmp PUT_CHARACTER_IOCB

.if VERSION = VERSION_A
    ; Unreached: ldx INPUT_IOCB, bne READ_INPUT_LINE, lda #EOL, jsr PUT_CHARACTER, which would end the screen's line
    ; before reading another.
    .byte $A6, $B4, $D0, $0E, $A9, $9B, $20, $9F, $BA

;; Reads a line for INPUT, showing the prompt first when it reads from the screen editor.
;;
;; Rev. A keeps it here; the later revisions keep it among the I/O routines.
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
.else
;; Asks whether a number has a fraction, for ^, which raises a negative number only to a whole power.
;;
;; Looks for a nonzero byte among the mantissa's bytes after those of the whole part. A number below 1, zero
;; included, counts as having one.
;; In: X = the number's address in page zero (FR0 or FR1)
;; Out: carry = set when the number is whole, clear when it has a fraction, ZTEMP4 = the index from 0 of the
;;   mantissa's last whole byte, when the number is 1 or more
;; Uses: A, X, ZTEMP1
;; Keeps: Y
;; See: <OPERATOR_POWER>
NUMBER_HAS_FRACTION:
    sec
    lda 0,x                         ; the power of 100, without the sign
    and #$7F
    sbc #FP_EXPONENT_BIAS
    bcc NUMBER_HAS_FRACTION_DONE    ; below 1
    sta ZTEMP1
    sta ZTEMP4
    txa                             ; carry is set: X + 1 + the power, the last whole byte
    adc ZTEMP1
    inx                             ; ZTEMP1 = the end of the mantissa
    inx
    inx
    inx
    inx
    inx
    stx ZTEMP1
    tax
NUMBER_HAS_FRACTION_LOOP:
    inx
    cpx ZTEMP1
    bcs NUMBER_HAS_FRACTION_DONE    ; no more bytes: whole
    lda 0,x
    beq NUMBER_HAS_FRACTION_LOOP
NUMBER_HAS_FRACTION_DONE:
    rts
.endif

; ---------------------------------------------------------------------------------------------------------------------
; Character output
; ---------------------------------------------------------------------------------------------------------------------

;; Puts a character to the output IOCB, for PRINT and LIST, calling its handler's put-byte routine directly.
;;
;; Faster than CIO: the routine is the one in the IOCB's ICPTL/ICPTH, less 1, which the OS keeps for BASIC; only the
;; auxiliary bytes are copied to the zero-page IOCB for it. A closed IOCB's routine returns CIO's status for it.
;; In: A = the character, OUTPUT_IOCB = the IOCB
;; Out: Y = the handler's status
;; Uses: A, X, IOCB_NUMBER, ICAX1Z, ICAX2Z
;; Errors: the handler's status, from 128
;; Entry: PUT_CHARACTER_IOCB = to the IOCB in X instead, for PUT and PLOT
PUT_CHARACTER:
    ldx OUTPUT_IOCB
PUT_CHARACTER_IOCB:
    pha
    jsr SET_IOCB_NUMBER
    lda ICAX1,x
    sta ICAX1Z
    lda ICAX2,x
    sta ICAX2Z
    pla
    tay
    jsr CALL_PUT_HANDLER
    tya                             ; the status
    jmp CHECK_STATUS

;; Calls the IOCB's handler's put-byte routine, by pushing its address less 1 and returning to it.
;; In: X = the IOCB's offset from IOCB 0, Y = the character
;; Out: Y = the handler's status
;; See: <PUT_CHARACTER>
CALL_PUT_HANDLER:
    lda ICPTH,x
    pha
    lda ICPTL,x
    pha
    tya
    ldy #FNCNOT                     ; the status, should the handler not set one
    rts

;; Sets the CIO command and the IOCB for the next call.
;; In: A = the command, X = the IOCB, 0-7
;; Out: X = the IOCB's offset from IOCB 0, negative = clear
;; See: <SET_IOCB_NUMBER>
SET_IOCB_COMMAND:
    sta IO_COMMAND
;; Sets the IOCB for the next CIO call.
;; In: X = the IOCB, 0-7
;; Out: X = the IOCB's offset from IOCB 0, zero = set for IOCB 0, negative = clear
;; Uses: A
SET_IOCB_NUMBER:
    stx IOCB_NUMBER
    jmp IOCB_OFFSET

; ---------------------------------------------------------------------------------------------------------------------
; ENTER, and the file IOCB
; ---------------------------------------------------------------------------------------------------------------------

;; ENTER: reads a listed program from a file, as if it were typed: ENTER filespec.
;;
;; Opens IOCB 7 on the file and makes it the line editor's input, which goes on reading lines from it until the end
;; of the file, then closes it and prints READY. The lines are added to the program in memory, replacing lines with
;; the same numbers; nothing is cleared first.
;; In: TOKEN_OFFSET = the file name's token
;; Errors: those of <OPEN_FILE_IOCB>
;; See: <CHECK_IO_STATUS_EOF>
STATEMENT_ENTER:
    lda #OREAD
    jsr OPEN_FILE_IOCB
    sta INPUT_IOCB
    jmp EDIT_LINE

;; Opens IOCB 7 on a file for writing and makes it PRINT's and LIST's output, for LIST with a file name.
;; In: TOKEN_OFFSET = the file name's token
;; Out: OUTPUT_IOCB = FILE_IOCB
;; Errors: those of <OPEN_FILE_IOCB>
;; See: <STATEMENT_LIST>
OPEN_LIST_FILE:
    lda #OWRIT
    jsr OPEN_FILE_IOCB
    sta OUTPUT_IOCB
    rts

;; Opens IOCB 7 on the file the next expression names, closing it first, for ENTER, LOAD, SAVE and LIST.
;; In: A = the open mode (ICAX1), TOKEN_OFFSET = the file name's token
;; Out: A = FILE_IOCB, X = its offset from IOCB 0, IOCB_NUMBER = FILE_IOCB, INBUFF = LBUFF
;; Errors: those of the expression, and CIO's status when the open fails
;; See: <CIO_WITH_FILE_NAME>
OPEN_FILE_IOCB:
    pha
    ldy #FILE_IOCB
    sty IOCB_NUMBER
    jsr IOCB_OFFSET
    lda #CCLOSE
    jsr CALL_CIO_A
    ldy #COPN
    sty IO_COMMAND
    pla
    ldy #$00                        ; ICAX2
    jsr CIO_WITH_FILE_NAME
    lda #FILE_IOCB
    rts

.if VERSION >= VERSION_B
;; 2.0, which SQR uses.
;; See: <SQUARE_ROOT>
FP_TWO:
    FP_NUMBER FP_POSITIVE, 0, $02, $00, $00, $00, $00
.endif

; ---------------------------------------------------------------------------------------------------------------------
; LOAD and SAVE
; ---------------------------------------------------------------------------------------------------------------------

;; Loads a program from a file and returns, for RUN with a file name, which then runs it.
;; Inherit: <STATEMENT_LOAD>
;; See: <STATEMENT_RUN>
LOAD_AND_RUN:
    lda #DEVICES_RUN
    bne STATEMENT_LOAD_OPEN         ; always
;; LOAD: replaces the program in memory with one SAVE wrote: LOAD filespec.
;;
;; Opens IOCB 7 on the file and reads the program with <LOAD_PROGRAM>, then closes the file, clears the variables
;; and prints READY.
;; In: TOKEN_OFFSET = the file name's token
;; Errors: those of <OPEN_FILE_IOCB> and <LOAD_PROGRAM>
;; See: <STATEMENT_SAVE>, <STATEMENT_CLOAD>
STATEMENT_LOAD:
    lda #$00
STATEMENT_LOAD_OPEN:
    pha
    lda #OREAD
    jsr OPEN_FILE_IOCB
    pla
;; Reads a saved program from IOCB 7, which is open: the header, then the tables.
;;
;; Each pointer from VNTP to STARP is LOMEM plus its offset in the header. LOAD_FLAG is set while the program is
;; read, so that BREAK or SYSTEM RESET starts BASIC cold rather than leave half a program. Then the variables are
;; cleared and IOCB 7 closed; to run the program, LOAD_PROGRAM returns, otherwise BASIC prints READY.
;; In: A = 0 to print READY, DEVICES_RUN to return
;; Errors: 19 (ERR_LOAD_TOO_LONG) when STARP would reach MEMTOP, 21 (ERR_LOAD_FILE) when the header's first offset
;;   isn't 0, and CIO's status when a read fails
;; See: <SAVE_PROGRAM>, <TRANSFER_TABLES>
LOAD_PROGRAM:
    pha
    lda #CGBINR
    sta IO_COMMAND
    sta LOAD_FLAG                   ; nonzero
    jsr IOCB_OFFSET
    ldy #SAVE_HEADER_SIZE           ; to LBUFF, SAVE_HEADER
    jsr CALL_CIO_LENGTH
    jsr CHECK_IO_STATUS
    lda SAVE_HEADER
    ora SAVE_HEADER+1
    bne LOAD_PROGRAM_NOT_SAVED      ; LOMEM's offset is always 0
    ldx #STARP
LOAD_PROGRAM_POINTER:
    clc                             ; LOMEM + the offset: Y low, A high
    lda LOMEM
    adc SAVE_HEADER-LOMEM,x
.if VERSION = VERSION_B
    php
    clc
    adc #$10                        ; rev. B: each pointer 16 bytes on, so a program grows by 16 at each LOAD
.elseif VERSION = VERSION_C
    php
    clc
    adc #$00                        ; does nothing: the carry is added below
.endif
    tay
    lda LOMEM+1
    adc SAVE_HEADER-LOMEM+1,x
.if VERSION >= VERSION_B
    plp                             ; rev. A adds the carry straight on
    adc #$00
.endif
    cmp MEMTOP+1
    bcc LOAD_PROGRAM_STORE
    bne LOAD_PROGRAM_TOO_LONG
    cpy MEMTOP
    bcc LOAD_PROGRAM_STORE
LOAD_PROGRAM_TOO_LONG:
    jmp LOAD_TOO_LONG_ERROR
LOAD_PROGRAM_STORE:
    sta 1,x
    sty 0,x
    dex
    dex
    cpx #VNTP
    bcs LOAD_PROGRAM_POINTER
    jsr TRANSFER_TABLES
    jsr STATEMENT_CLR               ; CLR
    lda #$00
    sta LOAD_FLAG
    pla
    beq LOAD_PROGRAM_READY
    rts
LOAD_PROGRAM_READY:
    jmp WARM_START_CLOSE
LOAD_PROGRAM_NOT_SAVED:
    lda #$00
    sta LOAD_FLAG
    jsr LOAD_FILE_ERROR

.if VERSION >= VERSION_B
;; CLOAD: loads a program from the cassette, as LOAD "C:" does but with short gaps between records: CLOAD.
;; Errors: those of <OPEN_CASSETTE> and <LOAD_PROGRAM>
;; See: <STATEMENT_CSAVE>
STATEMENT_CLOAD:
    lda #OREAD
    jsr OPEN_CASSETTE
    lda #$00
    beq LOAD_PROGRAM                ; always
.endif

;; SAVE: writes the program in memory to a file, tokenized, for LOAD: SAVE filespec.
;;
;; Opens IOCB 7 on the file and writes the program with <SAVE_PROGRAM>, which closes it.
;; In: TOKEN_OFFSET = the file name's token
;; Errors: those of <OPEN_FILE_IOCB>, and CIO's status when a write fails
;; See: <STATEMENT_LOAD>, <STATEMENT_CSAVE>
STATEMENT_SAVE:
    lda #OWRIT
    jsr OPEN_FILE_IOCB
;; Writes the program to IOCB 7, which is open: the header of LOMEM to STARP less LOMEM, then the tables.
;; Out: INBUFF = VNTP, where <TRANSFER_TABLES> leaves it
;; Errors: CIO's status when a write fails
;; See: <LOAD_PROGRAM>, <TRANSFER_TABLES>
SAVE_PROGRAM:
    lda #CPBINR
    sta IO_COMMAND
    ldx #LOMEM
SAVE_PROGRAM_HEADER:
    sec
    lda 0,x
    sbc LOMEM
    sta SAVE_HEADER-LOMEM,x
    inx
    lda 0,x
    sbc LOMEM+1
    sta SAVE_HEADER-LOMEM,x
    inx
    cpx #RUNSTK
    bcc SAVE_PROGRAM_HEADER
    jsr IOCB_OFFSET
    ldy #SAVE_HEADER_SIZE           ; from LBUFF, SAVE_HEADER
    jsr CALL_CIO_LENGTH
    jsr CHECK_IO_STATUS
;; Reads or writes the tables from VNTP to STARP through IOCB 7, then closes it.
;;
;; The length is STARP's offset in the header less 256, as the tables start after LOMEM's 256-byte token buffer.
;; In: IO_COMMAND = CGBINR or CPBINR, SAVE_HEADER = the header
;; Errors: CIO's status when the transfer fails
TRANSFER_TABLES:
    jsr IOCB_OFFSET
    lda VNTP
    sta INBUFF
    lda VNTP+1
    sta INBUFF+1
    ldy SAVE_HEADER+STARP-LOMEM+1
    dey                             ; less the token buffer's 256 bytes
    tya
    ldy SAVE_HEADER+STARP-LOMEM
    jsr CALL_CIO_LENGTH_AY
    jsr CHECK_IO_STATUS
    jmp CLOSE_IOCB

.if VERSION = VERSION_A
; Rev. A keeps CSAVE and CLOAD here, before OPEN_CASSETTE.

;; CSAVE: writes the program to the cassette, as SAVE "C:" does but with short gaps between records: CSAVE.
;; Errors: those of <OPEN_CASSETTE> and <SAVE_PROGRAM>
;; See: <STATEMENT_CLOAD>
STATEMENT_CSAVE:
    lda #OWRIT
    jsr OPEN_CASSETTE
    jmp SAVE_PROGRAM

;; CLOAD: loads a program from the cassette, as LOAD "C:" does but with short gaps between records: CLOAD.
;; Errors: those of <OPEN_CASSETTE> and <LOAD_PROGRAM>
;; See: <STATEMENT_CSAVE>
STATEMENT_CLOAD:
    lda #OREAD
    jsr OPEN_CASSETTE
    lda #$00
    jmp LOAD_PROGRAM
.endif

;; Opens IOCB 7 on the cassette, with short gaps between records, for CLOAD and CSAVE.
;; In: A = the open mode (ICAX1)
;; Out: A = FILE_IOCB, X = its offset from IOCB 0, INBUFF = LBUFF
;; Errors: CIO's status when the open fails
OPEN_CASSETTE:
.if VERSION >= VERSION_B
    nop                             ; two NOPs, doing nothing (not in rev. A)
    nop
.endif
    pha
    ldx #<CASSETTE_DEVICE_NAME
    stx INBUFF
    ldx #>CASSETTE_DEVICE_NAME
    stx INBUFF+1
    ldx #FILE_IOCB
    pla
    tay
    lda #CASSETTE_SHORT_GAPS
    jsr OPEN_DEVICE
    jsr CHECK_IO_STATUS
    lda #FILE_IOCB
    rts

;; "C:", the cassette's device name, ending with an EOL.
CASSETTE_DEVICE_NAME:
    .byte "C:", EOL

.if VERSION >= VERSION_B
;; CSAVE: writes the program to the cassette, as SAVE "C:" does but with short gaps between records: CSAVE.
;; Errors: those of <OPEN_CASSETTE> and <SAVE_PROGRAM>
;; See: <STATEMENT_CLOAD>
STATEMENT_CSAVE:
    lda #OWRIT
    jsr OPEN_CASSETTE
    bne SAVE_PROGRAM                ; always: A = FILE_IOCB
.endif

;; Opens an IOCB on the device name at INBUFF, then points INBUFF back at LBUFF.
;;
;; Doesn't check the result: the caller does, with <CHECK_IO_STATUS>.
;; In: A = ICAX2, X = the IOCB, 0-7, Y = the open mode (ICAX1), INBUFF = the name, ending with an EOL
;; Out: X = the IOCB's offset from IOCB 0, INBUFF = LBUFF
;; Uses: A, Y, IO_COMMAND, IOCB_NUMBER
OPEN_DEVICE:
    pha
    lda #COPN
    jsr SET_IOCB_COMMAND
    pla
    sta ICAX2,x
    tya
    sta ICAX1,x
    jsr CALL_CIO_BUFFER
    jmp FP_SET_INBUFF_LBUFF

; ---------------------------------------------------------------------------------------------------------------------
; The I/O statements
; ---------------------------------------------------------------------------------------------------------------------

;; XIO: sends any CIO command: XIO aexp1, #aexp2, aexp3, aexp4, filespec.
;;
;; aexp1 is the command, aexp2 the IOCB, aexp3 and aexp4 its two auxiliary bytes; the file name is given to the
;; handler, which may use it or not, as for the screen's FILL (XIO 18) and DOS's RENAME and DELETE.
;; In: TOKEN_OFFSET = the command's token
;; Errors: those of <STATEMENT_OPEN>
STATEMENT_XIO:
    jsr INTEGER_BYTE
    jmp STATEMENT_OPEN_COMMAND

;; OPEN: opens an IOCB on a device or file: OPEN #aexp1, aexp2, aexp3, filespec.
;;
;; aexp1 is the IOCB, 1-7; aexp2 the mode, ICAX1 (4 to read, 8 to write, 12 for both, 6 for a disk's directory, 9 to
;; append); aexp3 ICAX2, which the device may use.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <IOCB_FROM_HASH>, and CIO's status when the
;;   open fails
;; See: <STATEMENT_CLOSE>
STATEMENT_OPEN:
    lda #COPN
STATEMENT_OPEN_COMMAND:
    sta IO_COMMAND
    jsr IOCB_FROM_HASH              ; #aexp1
    jsr INTEGER_BYTE                ; ICAX1
    pha
    jsr INTEGER_BYTE                ; ICAX2
    tay
    pla
;; Sends the CIO command in IO_COMMAND to the IOCB with the file name the next expression gives, and checks it.
;;
;; The name's string is ended with an EOL for CIO while the command runs, and the byte after it restored.
;; In: A = ICAX1, Y = ICAX2, IO_COMMAND = the command, IOCB_NUMBER = the IOCB, TOKEN_OFFSET = the name's token
;; Out: X = the IOCB's offset from IOCB 0, INBUFF = LBUFF
;; Errors: those of the expression, and CIO's status when the command fails
CIO_WITH_FILE_NAME:
    pha
    tya
    pha
    jsr EVALUATE_EXPRESSION
    jsr PATCH_STRING_EOL            ; INBUFF = the name, with an EOL after it
    jsr IOCB_OFFSET
    pla
    sta ICAX2,x
    pla
    sta ICAX1,x
    jsr CALL_CIO_LINE
    jsr RESTORE_STRING_EOL
    jsr FP_SET_INBUFF_LBUFF
    jmp CHECK_IO_STATUS

;; CLOSE: closes an IOCB: CLOSE #aexp.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <COMMAND_HASH_IOCB>
;; See: <STATEMENT_OPEN>
STATEMENT_CLOSE:
    lda #CCLOSE
;; Sends a CIO command to the IOCB after # in the statement, and checks it.
;; In: A = the command, TOKEN_OFFSET = the # token
;; Out: X = the IOCB's offset from IOCB 0
;; Errors: those of <IOCB_FROM_HASH>, and CIO's status when the
;;   command fails
;; Entry: COMMAND_HASH_IOCB_CALL = with IO_COMMAND and the IOCB set, and the IOCB's offset in X
COMMAND_HASH_IOCB:
    sta IO_COMMAND
    jsr IOCB_FROM_HASH
COMMAND_HASH_IOCB_CALL:
    jsr CALL_CIO
    jmp CHECK_IO_STATUS

;; STATUS: reads a device's status into a variable: STATUS #aexp, avar.
;;
;; The status is CIO's, 1 for success or an error number from 128, and is not an error itself.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <IOCB_FROM_HASH>
STATEMENT_STATUS:
    jsr IOCB_FROM_HASH
    lda #CSTATUS
    jsr CALL_CIO_A
    jsr IOCB_STATUS
    jmp SET_VARIABLE_BYTE

;; NOTE: reads where a disk file is: NOTE #aexp, avar1, avar2.
;;
;; avar1 gets the sector, from ICAX3 and ICAX4, avar2 the byte in it, from ICAX5, for POINT to come back to.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <COMMAND_HASH_IOCB>
;; See: <STATEMENT_POINT>
STATEMENT_NOTE:
    lda #CNOTE
    jsr COMMAND_HASH_IOCB
    lda ICAX3,x
    ldy ICAX4,x
    jsr SET_VARIABLE_INTEGER
    jsr IOCB_OFFSET
    lda ICAX5,x
    jmp SET_VARIABLE_BYTE

;; POINT: moves a disk file to a place NOTE gave: POINT #aexp1, aexp2, aexp3.
;;
;; aexp2 is the sector, to ICAX3 and ICAX4, aexp3 the byte in it, to ICAX5.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <COMMAND_HASH_IOCB>
;; See: <STATEMENT_NOTE>
STATEMENT_POINT:
    jsr IOCB_FROM_HASH
    jsr EVALUATE_INTEGER            ; the sector
    jsr IOCB_OFFSET
    lda FR0
    sta ICAX3,x
    lda FR0+1
    sta ICAX4,x
    jsr EVALUATE_INTEGER            ; the byte
    jsr IOCB_OFFSET
    lda FR0
    sta ICAX5,x
    lda #CPOINT
    sta IO_COMMAND
.if VERSION = VERSION_A             ; rev. A jumps, where the later revisions branch, a byte shorter
    jmp COMMAND_HASH_IOCB_CALL
.else
    bne COMMAND_HASH_IOCB_CALL      ; always
.endif

;; PUT: writes one byte to an IOCB: PUT #aexp1, aexp2.
;;
;; The byte is aexp2 modulo 256, put straight through the handler as PRINT's characters are.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <IOCB_FROM_HASH> and <PUT_CHARACTER>
STATEMENT_PUT:
    jsr IOCB_FROM_HASH
    jsr EVALUATE_UNSIGNED
    lda FR0
    ldx IOCB_NUMBER
    jmp PUT_CHARACTER_IOCB

;; GET: reads one byte from an IOCB into a variable: GET #aexp, avar.
;; In: TOKEN_OFFSET = the # token
;; Errors: those of <IOCB_FROM_HASH>, and CIO's status when
;;   the read fails
;; Entry: STATEMENT_GET_BYTE = with the IOCB set and its offset in X, for LOCATE
STATEMENT_GET:
.if VERSION >= VERSION_B
    jsr FP_SET_INBUFF_LBUFF         ; rev. A reads to wherever INBUFF was left; a VAL in the # still moves it
.endif
    jsr IOCB_FROM_HASH
STATEMENT_GET_BYTE:
    lda #CGBINR
    sta IO_COMMAND
    ldy #$01                        ; one byte, to LBUFF
    jsr CALL_CIO_LENGTH
    jsr CHECK_IO_STATUS
    ldy #$00
    lda (INBUFF),y
    jmp SET_VARIABLE_BYTE

;; LOCATE: reads the colour or character at a point of the screen into a variable: LOCATE aexp1, aexp2, avar.
;;
;; Moves the cursor there, as POSITION does, and reads a byte from IOCB 6 as GET would, which moves it on. Unlike
;; rev. B's and C's GET, it doesn't point INBUFF at LBUFF first.
;; In: TOKEN_OFFSET = the first expression's token
;; Errors: those of <STATEMENT_POSITION>, and CIO's status when the read fails
STATEMENT_LOCATE:
    jsr STATEMENT_POSITION
    ldx #SCREEN_IOCB
    jsr SET_IOCB_NUMBER
    bne STATEMENT_GET_BYTE          ; always: IOCB 6's offset isn't 0
