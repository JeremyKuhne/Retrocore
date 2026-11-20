;; OSCLI and the * commands, OSWRCH, the printer, the buffers and *KEY ($DF0C-$E5B2).
;;
;; - The command line interpreter, <CLIV_DEFAULT>, looks a command up in <COMMAND_TABLE> and runs the MOS's own
;;   commands, offering anything else to the paged ROMs and then to the filing system. Its helpers read spaces,
;;   commas, decimal numbers and hexadecimal addresses from the command line at <TEXT_POINTER>.
;; - The commands: *FX and the commands that are OSBYTE calls, *BASIC, *KEY, *LOAD, *SAVE and *SPOOL.
;; - OSWRCH, <WRCHV_DEFAULT>, which sends each character to the VDU driver, the printer, RS-423 and the *SPOOL file
;;   as <WRCH_DESTINATION> says, and the printer drivers behind it.
;; - The buffer calls: <INSV_DEFAULT>, <REMV_DEFAULT> and <CNPV_DEFAULT>, with <BUFFER_BASE_HIGH> describing where
;;   each of the nine buffers is; OSEVEN, <OSEVEN_HANDLER>; and the code that puts keys into the keyboard buffer,
;;   checking for ESCAPE.
;; - <READ_INPUT>, which OSRDCH uses to take the next character from the input buffer, expanding soft keys and
;;   carrying out cursor editing on the way.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

END_OF_LINE = $0D                   ;; the carriage return that ends a command line

; Command table parameters: see <COMMAND>.
COMMAND_TEXT_OFFSET = $FF           ;; a command parameter that gives its handler the text as an offset in Y

; The filing system control calls, through FSCV, that the command line interpreter makes (in A).
FSC_STAR_SLASH = $02                ;; FSCV 2: a */ command; X and Y point to the file name after the /
FSC_UNRECOGNISED_COMMAND = $03      ;; FSCV 3: a command no paged ROM claimed; X and Y point to it
FSC_STAR_RUN = $04                  ;; FSCV 4: *RUN; X and Y point to the file name
FSC_STAR_CAT = $05                  ;; FSCV 5: *CAT; X and Y point to the rest of the line
FSC_OSCLI = $08                     ;; FSCV 8: OSCLI is about to interpret a command

; The OSBYTE calls that are also * commands.
OSBYTE_STAR_CODE = $88              ;; OSBYTE &88, *CODE: calls USERV with A = 0
OSBYTE_STAR_MOTOR = $89             ;; OSBYTE &89, *MOTOR: turns the cassette motor on or off
OSBYTE_STAR_OPT = $8B               ;; OSBYTE &8B, *OPT: sets a filing system option
OSBYTE_STAR_TAPE = $8C              ;; OSBYTE &8C, *TAPE: selects the cassette filing system
OSBYTE_STAR_ROM = $8D               ;; OSBYTE &8D, *ROM: selects the ROM filing system
OSBYTE_STAR_TV = $90                ;; OSBYTE &90, *TV: sets the vertical adjustment and interlace

; The paged ROM service calls these commands issue (in X).
SERVICE_UNRECOGNISED_COMMAND = $04  ;; service call 4: an unrecognised * command, at (TEXT_POINTER),Y
SERVICE_SPOOL_EXEC_CLOSING = $10    ;; service call &10: the *SPOOL and *EXEC files are about to be closed

; Events (in Y for OSEVEN).
EVENT_OUTPUT_BUFFER_EMPTY = $00     ;; event 0: an output buffer has become empty; X = the buffer
EVENT_INPUT_BUFFER_FULL = $01       ;; event 1: an input buffer is full; X = the buffer, Y = the character lost
EVENT_CHARACTER_ENTERING = $02      ;; event 2: a character is entering the input buffer; Y = the character
EVENT_ESCAPE_DETECTED = $06         ;; event 6: an ESCAPE condition has been detected

; The buffers, by number (in X for the buffer calls).
BUFFER_KEYBOARD = $00               ;; buffer 0, the keyboard buffer
BUFFER_RS423_INPUT = $01            ;; buffer 1, the RS-423 input buffer
BUFFER_RS423_OUTPUT = $02           ;; buffer 2, the RS-423 output buffer
BUFFER_PRINTER = $03                ;; buffer 3, the printer buffer

; The bits of <WRCH_DESTINATION>, as OSBYTE 3 (*FX 3) sets them.
WRCH_TO_RS423 = %00000001           ;; send output to RS-423
WRCH_NO_VDU = %00000010             ;; do not send output to the VDU driver
WRCH_NO_PRINTER = %00000100         ;; do not send output to the printer
WRCH_ALWAYS_PRINT = %00001000       ;; send output to the printer even without VDU 2
WRCH_NO_SPOOL = %00010000           ;; do not send output to the *SPOOL file

; The printer types, <PRINTER_DESTINATION>, as OSBYTE 5 (*FX 5) sets them; 3 and above are user printers.
PRINTER_SINK = 0                    ;; printer type 0: characters for the printer are thrown away
PRINTER_PARALLEL = 1                ;; printer type 1: the parallel printer on the user VIA's port A
PRINTER_SERIAL = 2                  ;; printer type 2: the serial printer on RS-423

; The reasons a printer driver is called with, through NETV and UPTV (in A).
PRINTER_DRIVER_POLL = 0             ;; the 10 ms poll of an active printer driver
PRINTER_DRIVER_START = 1            ;; characters are waiting in a dormant driver's buffer

; The reasons OSWRCH and OSRDCH call NETV with (in A).
NETV_WRCH = 4                       ;; NETV 4: OSWRCH was called, with the character in Y
NETV_RDCH = 6                       ;; NETV 6: OSRDCH was called

; Error numbers.
ERROR_BAD_COMMAND = $FE             ;; error &FE, "Bad command"
ERROR_BAD_ADDRESS = $FC             ;; error &FC, "Bad address"
ERROR_BAD_KEY = $FB                 ;; error &FB, "Bad key"
ERROR_KEY_IN_USE = $FA              ;; error &FA, "Key in use"

; Hardware values.
PARALLEL_ACK_INTERRUPT = %10000010  ;; for USER_VIA_IER: enables CA1, the printer's acknowledge, as an interrupt
PARALLEL_STROBE_KEEP = %11110001    ;; for USER_VIA_PCR: keeps all but CA2's control bits
PARALLEL_STROBE_LOW = %00001100     ;; for USER_VIA_PCR: drives CA2, the printer's strobe, low
PARALLEL_STROBE_HIGH = %00001110    ;; for USER_VIA_PCR: drives CA2 high again
ACIA_TRANSMIT_BITS = %10011111      ;; for ACIA_CONTROL: keeps all but bits 5-6, the transmit control
ACIA_TRANSMIT_ON = %00100000        ;; for ACIA_CONTROL: RTS low and the transmit interrupt enabled

; The parts of <OSFILE_BLOCK>, the control block *LOAD and *SAVE build for OSFILE.
OSFILE_BLOCK_LOAD = OSFILE_BLOCK + 2    ;; the load address, four bytes
OSFILE_BLOCK_EXEC = OSFILE_BLOCK + 6    ;; the execution address; for *LOAD, its first byte is 0 to use the load address
OSFILE_BLOCK_START = OSFILE_BLOCK + 10  ;; *SAVE's start address, four bytes
OSFILE_BLOCK_END = OSFILE_BLOCK + 14    ;; *SAVE's end address, four bytes

; *FX's parameters while it reads them.
FX_PARAMETER_X = OS_WORK + 1        ;; the X parameter *FX passes to OSBYTE
FX_PARAMETER_Y = OS_WORK            ;; the Y parameter *FX passes to OSBYTE

;; Gives a buffer's base address: the address that its offsets, which run from <BUFFER_FIRST_OFFSET> to &FF, are
;; added to.
;; Parameters:
;;   start = the buffer's first byte
;;   size = its size in bytes
.define BUFFER_BASE(start, size) ((start) + (size) - $100)

;; Lays out an entry of <COMMAND_TABLE>: the command's name, its handler's address high byte first, and its parameter.
;;
;; The high byte comes first so that its bit 7, set for every handler in the ROM, ends the name.
;; Parameters:
;;   name = the command's name, in capitals
;;   handler = the handler's address
;;   parameter = what <SET_UP_COMMAND_REGISTERS> gives the handler in A
.macro COMMAND name, handler, parameter
    .byte name, >(handler), <(handler), parameter
.endmacro

;; The four bytes a paged ROM's copyright string begins with, a zero and "(C)", stored backwards.
;;
;; Both the reset code's search for languages and the ROM filing system's check of a ROM compare them with X counting
;; down from 3, so the zero is read first.
COPYRIGHT_SIGNATURE:
    .byte ")C(", 0
    .assert * = COMMAND_TABLE, "COMMAND_TABLE follows COPYRIGHT_SIGNATURE: CLIV_DEFAULT reads it at COMMAND_TABLE-2."

;; The command table: each of the MOS's * commands, its handler and the parameter its handler is given.
;;
;; Each entry is a <COMMAND>: the name in capitals, then the handler's address high byte first, which ends the name
;; because its bit 7 is set, then the parameter. <CLIV_DEFAULT> searches the entries in order, so an abbreviation such
;; as "*L." finds the first command it fits, *LOAD. Before calling the handler it sets up the registers from the
;; parameter (see <SET_UP_COMMAND_REGISTERS>):
;;
;; - A parameter with bit 7 clear is passed in A, with X and Y pointing to the text after the command: the FSCV call
;;   for *. *CAT and *RUN, and what the handlers of *LOAD, *SAVE, *SPOOL, *EXEC and *LINE expect.
;; - A parameter with bit 7 set is passed in A, with the text at (TEXT_POINTER),Y: an OSBYTE number for the
;;   commands that are OSBYTE calls, or <COMMAND_TEXT_OFFSET> for *FX, *HELP and *KEY.
;;
;; The last entry has no name: it is found only when the command does not start with a letter, and passes the
;; command straight to the filing system, as FSCV 3, without offering it to the paged ROMs first. A zero ends the
;; table.
;; See: <CLIV_DEFAULT>
COMMAND_TABLE:
    COMMAND ".", CALL_FSCV, FSC_STAR_CAT
    COMMAND "FX", FX_COMMAND, COMMAND_TEXT_OFFSET
    COMMAND "BASIC", BASIC_COMMAND, 0
    COMMAND "CAT", CALL_FSCV, FSC_STAR_CAT
    COMMAND "CODE", OSBYTE_COMMAND, OSBYTE_STAR_CODE
    COMMAND "EXEC", STAR_EXEC, 0
    COMMAND "HELP", HELP_COMMAND, COMMAND_TEXT_OFFSET
    COMMAND "KEY", KEY_COMMAND, COMMAND_TEXT_OFFSET
    COMMAND "LOAD", LOAD_COMMAND, 0
    COMMAND "LINE", JUMP_USERV, 1        ; USERV with A = 1
    COMMAND "MOTOR", OSBYTE_COMMAND, OSBYTE_STAR_MOTOR
    COMMAND "OPT", OSBYTE_COMMAND, OSBYTE_STAR_OPT
    COMMAND "RUN", CALL_FSCV, FSC_STAR_RUN
    COMMAND "ROM", OSBYTE_COMMAND, OSBYTE_STAR_ROM
    COMMAND "SAVE", SAVE_COMMAND, 0
    COMMAND "SPOOL", SPOOL_COMMAND, 0
    COMMAND "TAPE", OSBYTE_COMMAND, OSBYTE_STAR_TAPE
    COMMAND "TV", OSBYTE_COMMAND, OSBYTE_STAR_TV
    .byte >CALL_FSCV, <CALL_FSCV, FSC_UNRECOGNISED_COMMAND  ; a command that does not start with a letter
    .byte 0                         ; the end of the table

;; The default OSCLI: interprets a command line.
;;
;; It first tells the filing system (FSCV 8), then ignores a line that has no carriage return in its first 256
;; bytes. It skips spaces and asterisks, ignores an empty line or one starting with |, and passes a line starting
;; with / to the filing system to run (FSCV 2). Otherwise it looks the command up in <COMMAND_TABLE>, ignoring case:
;; a name matches when the text has all its letters and is not followed by another letter, and a name typed in part
;; matches when the part ends in a full stop. The handler is entered through an RTI, with the registers that
;; <SET_UP_COMMAND_REGISTERS> sets up from the entry's parameter, carry clear, and zero set when nothing follows the
;; command. A command not in the table goes to <UNRECOGNISED_COMMAND>.
;; In: X/Y = the command line, ending in a carriage return
;; Uses: A, X, Y, TEXT_POINTER, OS_WORK+2 (the offset of the command)
;; See: <COMMAND_TABLE>, <CHECK_LETTER>
CLIV_DEFAULT:
    stx TEXT_POINTER
    sty TEXT_POINTER+1
    lda #FSC_OSCLI
    jsr CALL_FSCV
    ldy #$00
CLIV_DEFAULT_FIND_END:
    lda (TEXT_POINTER),y
    cmp #END_OF_LINE
    beq CLIV_DEFAULT_ENDED
    iny
    bne CLIV_DEFAULT_FIND_END
    rts                             ; no carriage return: ignore the line
CLIV_DEFAULT_ENDED:
    ldy #$FF
CLIV_DEFAULT_SKIP_STARS:
    jsr NEXT_NON_SPACE
    beq SET_UP_COMMAND_REGISTERS_DONE
    cmp #'*'
    beq CLIV_DEFAULT_SKIP_STARS
    jsr SKIP_SPACES
    beq SET_UP_COMMAND_REGISTERS_DONE
    cmp #'|'                        ; a comment
    beq SET_UP_COMMAND_REGISTERS_DONE
    cmp #'/'
    bne CLIV_DEFAULT_SEARCH
    iny
    jsr SET_UP_COMMAND_POINTER      ; only for X/Y: the Y it loads from the table is not used
    lda #FSC_STAR_SLASH
    bne CALL_FSCV                   ; always taken

CLIV_DEFAULT_SEARCH:
    sty OS_WORK+2
    ldx #$00
    beq CLIV_DEFAULT_END_OF_WORD    ; always taken
CLIV_DEFAULT_COMPARE:
    eor COMMAND_TABLE,x
    and #%11011111                  ; ignore the difference between capitals and small letters
    bne CLIV_DEFAULT_MISMATCH
    iny
    clc
CLIV_DEFAULT_NEXT_CHARACTER:
    bcs CLIV_DEFAULT_DISPATCH       ; carry is set here only after an abbreviation
    inx
    lda (TEXT_POINTER),y
    jsr CHECK_LETTER
    bcc CLIV_DEFAULT_COMPARE
CLIV_DEFAULT_END_OF_WORD:
    lda COMMAND_TABLE,x
    bmi CLIV_DEFAULT_FOUND          ; the whole name matched
    lda (TEXT_POINTER),y
    cmp #'.'
    beq CLIV_DEFAULT_ABBREVIATED
CLIV_DEFAULT_MISMATCH:
    clc
    ldy OS_WORK+2
    dey
CLIV_DEFAULT_ABBREVIATED:
    iny
    inx
CLIV_DEFAULT_SKIP_NAME:
    inx
    lda COMMAND_TABLE-2,x
    beq UNRECOGNISED_COMMAND        ; the end of the table
    bpl CLIV_DEFAULT_SKIP_NAME
    bmi CLIV_DEFAULT_NEXT_CHARACTER ; always taken, at the handler's high byte
CLIV_DEFAULT_FOUND:
    inx
    inx
CLIV_DEFAULT_DISPATCH:
    dex                             ; X = the handler's high byte's offset
    dex
    pha                             ; the handler's address, for the RTI
    lda COMMAND_TABLE+1,x
    pha
    jsr SKIP_SPACES
    clc
    php
    jsr SET_UP_COMMAND_REGISTERS
    rti                             ; enter the handler, with carry clear and zero set at the end of the line

;; Sets up the registers for a command's handler from its parameter in <COMMAND_TABLE>.
;;
;; A parameter with bit 7 set leaves the text as an offset in Y; any other gives the text's address in X and Y.
;; In: X = the offset of the entry's handler's high byte, Y = the offset of the text after the command
;; Out:
;;   A = the parameter
;;   X/Y = the text's address, when the parameter's bit 7 is clear
;; Entry:
;;   SET_UP_COMMAND_POINTER = for any parameter
;;   POINT_AT_TEXT = sets X/Y to TEXT_POINTER plus A, and returns the Y it is given in A
SET_UP_COMMAND_REGISTERS:
    lda COMMAND_TABLE+2,x
    bmi SET_UP_COMMAND_REGISTERS_DONE
SET_UP_COMMAND_POINTER:
    tya
    ldy COMMAND_TABLE+2,x
POINT_AT_TEXT:
    clc
    adc TEXT_POINTER
    tax
    tya
    ldy TEXT_POINTER+1
    bcc SET_UP_COMMAND_REGISTERS_DONE
    iny
SET_UP_COMMAND_REGISTERS_DONE:
    rts

;; *BASIC: enters the BASIC ROM as the language.
;;
;; With no BASIC ROM fitted, the command is treated as unrecognised.
;; See: <ENTER_LANGUAGE>, <BASIC_ROM>
BASIC_COMMAND:
    ldx BASIC_ROM
    bmi UNRECOGNISED_COMMAND
    sec
    jmp ENTER_LANGUAGE

;; Passes a command the MOS does not know to the paged ROMs (service call 4), and when none claims it, to the filing
;; system (FSCV 3).
;; In: OS_WORK+2 = the offset of the command in <TEXT_POINTER>
;; See: <ISSUE_SERVICE_CALL>
UNRECOGNISED_COMMAND:
    ldy OS_WORK+2
    ldx #SERVICE_UNRECOGNISED_COMMAND
    jsr ISSUE_SERVICE_CALL
    beq SET_UP_COMMAND_REGISTERS_DONE   ; claimed
    lda OS_WORK+2
    jsr POINT_AT_TEXT
    lda #FSC_UNRECOGNISED_COMMAND
    ; Falls through into CALL_FSCV.

;; Calls the filing system control vector, FSCV; the handler of *. *CAT and *RUN.
;; In: A = the reason, X/Y = its parameters
CALL_FSCV:
    jmp (FSCV)

;; OSBYTE &8B, *OPT: sets a filing system option through FSCV 0.
;;
;; A is the OSBYTE number, &8B; doubling it leaves bit 0 clear, so A becomes 0.
;; In: A = &8B, X/Y = the option and its value
SET_FILING_SYSTEM_OPTION:
    asl a
    ; Falls through into READ_END_OF_FILE.

;; OSBYTE &7F: reads whether a file is at its end, through FSCV 1.
;;
;; A is the OSBYTE number, &7F, whose bit 0 is the reason, 1.
;; In: A = &7F, X = the file's handle
;; Out: X = nonzero at the end of the file (&40 from the cassette and ROM filing systems), otherwise 0
READ_END_OF_FILE:
    and #$01
    bpl CALL_FSCV                   ; always taken

;; Skips spaces in the command line, after stepping past the current character.
;; In: Y = the offset of the current character in <TEXT_POINTER>
;; Out: A = the next character that is not a space, Y = its offset, zero = set when it ends the line
;; Entry:
;;   SKIP_SPACES = skips spaces from the current character
;;   CHECK_END_OF_LINE = only compares A with a carriage return
NEXT_NON_SPACE:
    iny
SKIP_SPACES:
    lda (TEXT_POINTER),y
    cmp #' '
    beq NEXT_NON_SPACE
CHECK_END_OF_LINE:
    cmp #END_OF_LINE
    rts

;; Skips spaces in the command line, and when carry is set also a comma after them.
;;
;; *FX uses the carry to skip the comma after its first number, which the commands that are OSBYTE calls do not
;; have.
;; In: carry = set to skip a comma, Y = the offset in <TEXT_POINTER>
;; Out:
;;   A = the character after the spaces, or the comma
;;   Y = the offset of that character, or of the one after the comma
;;   zero = set when the line ends
;; Entry: SKIP_COMMA = always skips a comma
SKIP_SEPARATOR:
    bcc SKIP_SPACES
SKIP_COMMA:
    jsr SKIP_SPACES
    cmp #','
    bne CHECK_END_OF_LINE
    iny
    rts

;; Reads a decimal number from 0 to 255 from the command line, after any spaces.
;; In: Y = the offset in <TEXT_POINTER>
;; Out:
;;   carry = set when a number was read, clear when there was none or it was over 255
;;   X = the number
;;   A = the character after it, Y = that character's offset
;;   zero = set when that character ends the line
;;   OS_WORK+2 = the number
;; See: <READ_DIGIT>
PARSE_DECIMAL_NUMBER:
    jsr SKIP_SPACES
    jsr READ_DIGIT
    bcc NOT_A_NUMBER
PARSE_DECIMAL_NUMBER_LOOP:
    sta OS_WORK+2
    jsr NEXT_DIGIT
    bcc PARSE_DECIMAL_NUMBER_DONE
    tax                             ; the new digit
    lda OS_WORK+2                   ; times 10: times 4, plus itself, times 2
    asl a
    bcs NOT_A_NUMBER
    asl a
    bcs NOT_A_NUMBER
    adc OS_WORK+2
    bcs NOT_A_NUMBER
    asl a
    bcs NOT_A_NUMBER
    sta OS_WORK+2
    txa
    adc OS_WORK+2
    bcs NOT_A_NUMBER
    bcc PARSE_DECIMAL_NUMBER_LOOP   ; always taken
PARSE_DECIMAL_NUMBER_DONE:
    ldx OS_WORK+2
    cmp #END_OF_LINE
    sec
    rts

;; Reads a decimal digit from the command line, after stepping past the current character.
;; In: Y = the offset of the current character in <TEXT_POINTER>
;; Out: carry = set for a digit, A = its value, or the character when it is not a digit, Y = its offset
;; Entry: READ_DIGIT = reads the current character
NEXT_DIGIT:
    iny
READ_DIGIT:
    lda (TEXT_POINTER),y
    cmp #'9'+1
    bcs NOT_A_NUMBER
    cmp #'0'
    bcc NOT_A_NUMBER
    and #$0F
    rts

;; Ends a hexadecimal number: skips spaces and a comma after it, and returns carry clear.
;; In: Y = the offset in <TEXT_POINTER>
;; Out: carry = clear, A = the character after the spaces or the comma, zero = set when the line ends
;; Entry: NOT_A_NUMBER = only clears carry, the exit of the number readers that found no number
NOT_HEX_DIGIT:
    jsr SKIP_COMMA
NOT_A_NUMBER:
    clc
    rts

;; Reads a hexadecimal digit, 0-9 or A-F in either case, from the command line.
;; In: Y = the offset of the digit in <TEXT_POINTER>
;; Out:
;;   carry = set for a digit, clear when the number has ended
;;   A = the digit's value, 0-15
;;   Y = the offset after the digit, or after the spaces and comma that follow the number
;;   zero = set, when the number has ended, if the line ends there too
READ_HEX_DIGIT:
    jsr READ_DIGIT
    bcs READ_HEX_DIGIT_DONE
    and #%11011111                  ; a capital
    cmp #'F'+1
    bcs NOT_HEX_DIGIT
    cmp #'A'
    bcc NOT_HEX_DIGIT
    php
    sbc #'A'-10                     ; carry is set
    plp
READ_HEX_DIGIT_DONE:
    iny
    rts

;; The default OSWRCH: writes a character to each destination <WRCH_DESTINATION> selects.
;;
;; While Econet intercepts OSWRCH (<ECONET_WRCH_INTERCEPT>), NETV 4 is offered the character first, and keeps it
;; when it returns carry set. Otherwise the character goes, in turn:
;;
;; - to the VDU driver, unless output to it is disabled;
;; - to the printer, when the VDU driver says the printer is on (VDU 2) or *FX 3 sends everything to it;
;; - to RS-423, when it is selected and the cassette system does not have the 6850, waiting while the RS-423 output
;;   buffer is full;
;; - to the *SPOOL file, when one is open and spooling is not disabled.
;; In: A = the character
;; Keeps: A, X, Y
;; See: <VDU_DRIVER>, <PRINT_CHARACTER>
WRCHV_DEFAULT:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda STACK+3,x                   ; the caller's A
    pha                             ; a copy each destination can take
    bit ECONET_WRCH_INTERCEPT
    bpl WRCHV_DEFAULT_VDU
    tay
    lda #NETV_WRCH
    jsr CALL_NETV
    bcs WRCHV_DEFAULT_DONE
WRCHV_DEFAULT_VDU:
    clc                             ; nothing for the printer unless the VDU driver says so
    lda #WRCH_NO_VDU
    bit WRCH_DESTINATION
    bne WRCHV_DEFAULT_PRINTER
    pla
    pha
    jsr VDU_DRIVER                  ; returns carry set when the printer should have the character
WRCHV_DEFAULT_PRINTER:
    lda #WRCH_ALWAYS_PRINT
    bit WRCH_DESTINATION
    bne WRCHV_DEFAULT_PRINT
    bcc WRCHV_DEFAULT_RS423
WRCHV_DEFAULT_PRINT:
    pla
    pha
    jsr PRINT_CHARACTER
WRCHV_DEFAULT_RS423:
    lda WRCH_DESTINATION
    ror a                           ; WRCH_TO_RS423
    bcc WRCHV_DEFAULT_SPOOL
    ldy RS423_TIMEOUT
    dey
    bpl WRCHV_DEFAULT_SPOOL         ; the cassette system has the 6850
    pla
    pha
    php
    sei
    ldx #BUFFER_RS423_OUTPUT
    pha
    jsr EXAMINE_BUFFER
    bcc WRCHV_DEFAULT_INSERT
    jsr START_RS423_OUTPUT          ; the buffer was empty, so the 6850 is idle
WRCHV_DEFAULT_INSERT:
    pla
    ldx #BUFFER_RS423_OUTPUT
    jsr INSERT_OR_WAIT
    plp
WRCHV_DEFAULT_SPOOL:
    lda #WRCH_NO_SPOOL
    bit WRCH_DESTINATION
    bne WRCHV_DEFAULT_DONE
    ldy SPOOL_HANDLE
    beq WRCHV_DEFAULT_DONE
    pla
    pha
    sec
    ror CASSETTE_CRITICAL
    jsr OSBPUT
    lsr CASSETTE_CRITICAL
WRCHV_DEFAULT_DONE:
    pla
    pla
    tay
    pla
    tax
    pla
    rts

;; Sends a character to the printer, unless *FX 3 sends only VDU 1's characters to it or it is the character
;; *FX 6 says the printer ignores.
;;
;; The character is put into the printer buffer, waiting while it is full, and a dormant printer driver is
;; started. Nothing is printed when *FX 3 disables the printer.
;; In: A = the character
;; Uses: A, X, Y
;; Entry: BUFFER_PRINTER_CHARACTER = for VDU 1: skips the two checks
;; See: <SEND_TO_PRINTER>, <PRINTER_IGNORE>
PRINT_CHARACTER:
    bit WRCH_DESTINATION
    bvs PRINT_CHARACTER_DONE        ; bit 6: only VDU 1 prints
    cmp PRINTER_IGNORE
    beq PRINT_CHARACTER_DONE
BUFFER_PRINTER_CHARACTER:
    php
    sei
    tax
    lda #WRCH_NO_PRINTER
    bit WRCH_DESTINATION
    bne BUFFER_PRINTER_CHARACTER_DONE
    txa
    ldx #BUFFER_PRINTER
    jsr INSERT_OR_WAIT
    bcs BUFFER_PRINTER_CHARACTER_DONE
    bit BUFFER_BUSY+BUFFER_PRINTER
    bpl BUFFER_PRINTER_CHARACTER_DONE   ; the printer is already busy
    jsr SEND_TO_PRINTER
BUFFER_PRINTER_CHARACTER_DONE:
    plp
PRINT_CHARACTER_DONE:
    rts

;; Gives the printer the next character from the printer buffer, by printer type, or marks the printer dormant
;; when the buffer is empty.
;;
;; - Type 0 throws the buffer's characters away.
;; - Type 1, the parallel printer: puts the character on the user VIA's port A and pulses CA2, the strobe, low. The
;;   printer's acknowledge on CA1 raises the interrupt that comes back here for the next one.
;; - Type 2, the serial printer: unless the cassette system has the 6850, marks RS-423 busy and starts its transmit
;;   interrupt, which takes the characters; otherwise throws them away.
;; - Other types are user printers: their drivers are called through NETV and UPTV with A = 1.
;; In: X = 3, the printer buffer
;; Uses: A, X, Y
;; See: <PRINT_CHARACTER>, <START_USER_PRINTER>
SEND_TO_PRINTER:
    lda PRINTER_DESTINATION
    beq FLUSH_BUFFER                ; PRINTER_SINK
    cmp #PRINTER_PARALLEL
    bne SEND_TO_PRINTER_SERIAL
    jsr REMOVE_FROM_BUFFER
    ror BUFFER_BUSY+BUFFER_PRINTER  ; carry set, the buffer empty: the printer is dormant
    bmi UPDATE_ACIA_CONTROL_DONE
    ldy #PARALLEL_ACK_INTERRUPT
    sty USER_VIA_IER
    sta USER_VIA_ORA
    lda USER_VIA_PCR
    and #PARALLEL_STROBE_KEEP
    ora #PARALLEL_STROBE_LOW
    sta USER_VIA_PCR
    ora #PARALLEL_STROBE_HIGH
    sta USER_VIA_PCR
    bne UPDATE_ACIA_CONTROL_DONE           ; always taken
SEND_TO_PRINTER_SERIAL:
    cmp #PRINTER_SERIAL
    bne START_USER_PRINTER
    ldy RS423_TIMEOUT
    dey
    bpl FLUSH_BUFFER                ; the cassette system has the 6850
    lsr BUFFER_BUSY+BUFFER_PRINTER  ; the printer is active
    ; Falls through into START_RS423_OUTPUT.

;; Marks RS-423 busy and, when its input buffer has room, sets RTS low and enables the 6850's transmit interrupt.
;; Uses: A, X, Y
;; Entry: RESUME_RS423 = does not mark RS-423 busy; called when a character has been taken from the input buffer
;; See: <CHECK_RS423_INPUT_ROOM>, <SET_ACIA_TRANSMIT_CONTROL>
START_RS423_OUTPUT:
    lsr RS423_BUSY
RESUME_RS423:
    jsr CHECK_RS423_INPUT_ROOM
    bcc UPDATE_ACIA_CONTROL_DONE
    ldx #ACIA_TRANSMIT_ON
    ; Falls through into SET_ACIA_TRANSMIT_CONTROL.

;; Sets the 6850's transmit control bits, 5 and 6, which control RTS and the transmit interrupt.
;; In: X = the new bits 5-6
;; Out: X = the old control register
;; Uses: A, Y
SET_ACIA_TRANSMIT_CONTROL:
    ldy #ACIA_TRANSMIT_BITS
    ; Falls through into UPDATE_ACIA_CONTROL.

;; OSBYTE &9C: reads and writes the 6850's control register, through the copy in <ACIA_CONTROL_COPY>.
;;
;; The new value is the old one ANDed with Y, then exclusive-ORed with X.
;; In: X = the bits to change, Y = the bits to keep
;; Out: A = the new value, X = the old value
;; Uses: OS_SCRATCH
;; Keeps: Y
;; Entry: WRITE_ACIA_CONTROL = writes A to the register and its copy, then pulls the flags its caller pushed
UPDATE_ACIA_CONTROL:
    php
    sei
    tya
    stx OS_SCRATCH
    and ACIA_CONTROL_COPY
    eor OS_SCRATCH
    ldx ACIA_CONTROL_COPY
WRITE_ACIA_CONTROL:
    sta ACIA_CONTROL_COPY
    sta ACIA_CONTROL
    plp
UPDATE_ACIA_CONTROL_DONE:
    rts

;; Starts a user printer: calls the printer drivers with A = 1, and marks the printer active when the driver
;; returns carry clear.
;; Uses: A, X, Y
;; Entry: MARK_PRINTER_DORMANT = OSBYTE &7B, which the OSBYTE code calls with carry set: marks the printer dormant
;; See: <CALL_PRINTER_DRIVER>
START_USER_PRINTER:
    clc
    lda #PRINTER_DRIVER_START
    jsr CALL_PRINTER_DRIVER
MARK_PRINTER_DORMANT:
    ror BUFFER_BUSY+BUFFER_PRINTER
START_USER_PRINTER_DONE:
    rts

;; Gives an active printer driver its 10 ms poll: calls the printer drivers with A = 0.
;; Uses: A, X, Y
POLL_PRINTER_DRIVER:
    bit BUFFER_BUSY+BUFFER_PRINTER
    bmi START_USER_PRINTER_DONE     ; dormant
    lda #PRINTER_DRIVER_POLL
    ; Falls through into CALL_PRINTER_DRIVER.

;; Calls the printer drivers: first the network printer, through NETV, then the user print vector, UPTV.
;; In: A = the reason
;; Out: carry = clear when the driver is going active, for A = 1
;; Entry: CALL_PRINTER_DRIVER_FOR = passes the X given (OSBYTE 5 passes the new printer type)
;; See: <UPTV>, <NETV>
CALL_PRINTER_DRIVER:
    ldx #BUFFER_PRINTER
CALL_PRINTER_DRIVER_FOR:
    ldy PRINTER_DESTINATION
    jsr CALL_NETV
    jmp (UPTV)

;; Empties a buffer: resets a sound channel's sound, marks the buffer empty, and for the input buffers also stops a
;; soft key's expansion and abandons the VDU queue.
;; In: X = the buffer
;; Keeps: A
;; Uses: Y (for a sound channel)
;; Entry: FLUSH_BUFFER_LEAVE_CHANNEL = with carry set, does not reset a sound channel
;; See: <CLEAR_SOUND_CHANNEL>, <PURGE_BUFFER>
FLUSH_BUFFER:
    clc
FLUSH_BUFFER_LEAVE_CHANNEL:
    pha
    php
    sei
    bcs FLUSH_BUFFER_EMPTY
    lda SERIAL_ULA_RATES,x
    bpl FLUSH_BUFFER_EMPTY          ; not a sound channel's buffer
    jsr CLEAR_SOUND_CHANNEL
FLUSH_BUFFER_EMPTY:
    sec
    ror BUFFER_BUSY,x
    cpx #BUFFER_RS423_OUTPUT
    bcs FLUSH_BUFFER_PURGE
    lda #$00
    sta SOFT_KEY_LENGTH
    sta VDU_QUEUE_COUNT
FLUSH_BUFFER_PURGE:
    jsr PURGE_BUFFER
    plp
    pla
    rts

;; The default CNPV: counts the characters in a buffer, or the free space in it, or purges it.
;;
;; A buffer's offsets run from its first offset, in <BUFFER_FIRST_OFFSET>, up to &FF and round again, so a count
;; that goes negative is corrected by the buffer's size. A buffer holds one character less than its size.
;; In: X = the buffer, overflow = set to purge, carry = set to count the free space rather than the characters
;; Out: X = the count, Y = 0, when counting
;; Uses: A
CNPV_DEFAULT:
    bvc CNPV_DEFAULT_COUNT
    lda BUFFER_START,x
    sta BUFFER_END,x
    rts
CNPV_DEFAULT_COUNT:
    php
    sei
    php
    sec
    lda BUFFER_END,x
    sbc BUFFER_START,x
    bcs CNPV_DEFAULT_COUNTED
    sec
    sbc BUFFER_FIRST_OFFSET,x       ; the same as adding the buffer's size
CNPV_DEFAULT_COUNTED:
    plp
    bcc CNPV_DEFAULT_DONE
    clc
    adc BUFFER_FIRST_OFFSET,x       ; the free space is the size less the count, less one
    eor #$FF
CNPV_DEFAULT_DONE:
    ldy #$00
    tax
    plp
    rts

;; Puts a character into a buffer, waiting for room while the buffer is full.
;;
;; While it waits, <LIGHT_KEYBOARD_LEDS> lights the keyboard lights and interrupts are enabled so that the buffer can
;; empty; <SET_KEYBOARD_LEDS> restores the lights. An ESCAPE ends the wait.
;; In: A = the character, X = the buffer
;; Out: carry = clear when it was inserted, set when an ESCAPE stopped the wait
;; Uses: A, Y
INSERT_OR_WAIT:
    sei
    jsr INSERT_INTO_BUFFER
    bcc INSERT_OR_WAIT_DONE
    jsr LIGHT_KEYBOARD_LEDS
    php
    pha
    jsr SET_KEYBOARD_LEDS
    pla
    plp
    bmi INSERT_OR_WAIT_DONE         ; an ESCAPE is pending
    cli
    bcs INSERT_OR_WAIT              ; always taken
INSERT_OR_WAIT_DONE:
    rts

;; Clears an address in <OSFILE_BLOCK>.
;; In: X = the address's offset in OSFILE_BLOCK
;; Keeps: A, X, Y
CLEAR_OSFILE_ADDRESS:
    pha
    lda #$00
    sta OSFILE_BLOCK,x
    sta OSFILE_BLOCK+1,x
    sta OSFILE_BLOCK+2,x
    sta OSFILE_BLOCK+3,x
    pla
    rts

;; Adds a hexadecimal digit to the end of an address in <OSFILE_BLOCK>, shifting it left four bits.
;; In: A = the digit, X = the address's offset in OSFILE_BLOCK
;; Errors: "Bad address" when the address grows past 32 bits
;; Uses: A, OS_WORK+2
;; Keeps: X, Y
ADD_HEX_DIGIT:
    sty OS_WORK+2
    rol a                           ; the digit to the high nibble
    rol a
    rol a
    rol a
    ldy #$04
ADD_HEX_DIGIT_LOOP:
    rol a
    rol OSFILE_BLOCK,x
    rol OSFILE_BLOCK+1,x
    rol OSFILE_BLOCK+2,x
    rol OSFILE_BLOCK+3,x
    bcs BAD_ADDRESS
    dey
    bne ADD_HEX_DIGIT_LOOP
    ldy OS_WORK+2
    rts

;; *LOAD: loads a file, at the address given or at its own.
;;
;; Both build an OSFILE control block in <OSFILE_BLOCK>, with the file name's address from X/Y. *LOAD takes an
;; optional load address. *SAVE takes the start address, then the end address or + and the length, then optionally
;; the execution address, which is otherwise the start address, and the reload address, which is otherwise the start
;; address too.
;; In: X/Y = the text after the command
;; Errors: "Bad address" for an address that is not hexadecimal, "Bad command" for one missing or extra text
;; Entry: SAVE_COMMAND = *SAVE: saves memory as a file
LOAD_COMMAND:
    lda #$FF                        ; OSFILE &FF, load
SAVE_COMMAND:                       ; entered with A = 0, OSFILE 0, save
    stx TEXT_POINTER
    sty TEXT_POINTER+1
    stx OSFILE_BLOCK
    sty OSFILE_BLOCK+1
    pha
    ldx #OSFILE_BLOCK_LOAD-OSFILE_BLOCK
    jsr CLEAR_OSFILE_ADDRESS
    ldy #$FF
    sty OSFILE_BLOCK_EXEC           ; nonzero: load at the file's own address
    iny
    jsr GSINIT_SPACE_ENDS                       ; GSINIT, for a name that ends at a space
LOAD_COMMAND_SKIP_NAME:
    jsr GSREAD_HANDLER
    bcc LOAD_COMMAND_SKIP_NAME
    pla
    pha
    beq SAVE_COMMAND_ADDRESSES
    jsr READ_HEX_ADDRESS
    bcs LOAD_COMMAND_AT_ADDRESS
    beq LOAD_COMMAND_OSFILE         ; no address
    ; Falls through into BAD_ADDRESS.

;; Raises the "Bad address" error.
BAD_ADDRESS:
    brk
    .byte ERROR_BAD_ADDRESS, "Bad address", 0

;; OSBYTE &77: closes the *SPOOL and *EXEC files, unless a paged ROM claims service call &10 to do it.
;; Uses: A, X, Y
;; See: <SPOOL_COMMAND>, <CLOSE_EXEC>
CLOSE_SPOOL_AND_EXEC:
    ldx #SERVICE_SPOOL_EXEC_CLOSING
    jsr ISSUE_SERVICE_CALL
    beq SPOOL_COMMAND_DONE          ; claimed
    jsr CLOSE_EXEC                       ; close the *EXEC file
    lda #$00                        ; zero set: close the *SPOOL file and open nothing
    ; Falls through into SPOOL_COMMAND.

;; *SPOOL: closes the *SPOOL file, then opens the one named for output, if any, as the new one.
;; In: X/Y = the text after the command, zero = set when there is no file name
;; Errors: "Bad command" when the file cannot be opened
;; Uses: A, X, Y, OS_WORK+2
SPOOL_COMMAND:
    php
    sty OS_WORK+2
    ldy SPOOL_HANDLE
    sta SPOOL_HANDLE                ; A = 0
    beq SPOOL_COMMAND_OPEN
    jsr OSFIND                      ; close it
SPOOL_COMMAND_OPEN:
    ldy OS_WORK+2
    plp
    beq SPOOL_COMMAND_DONE
    lda #$80                        ; OSFIND &80: open for output
    jsr OSFIND
    tay
    beq USERV_DEFAULT
    sta SPOOL_HANDLE
SPOOL_COMMAND_DONE:
    rts

; The rest of *LOAD and *SAVE.
LOAD_COMMAND_AT_ADDRESS:
    bne USERV_DEFAULT               ; more text after the address
    inc OSFILE_BLOCK_EXEC           ; zero: load at the address given
LOAD_COMMAND_OSFILE:
    ldx #<OSFILE_BLOCK
    ldy #>OSFILE_BLOCK
    pla
    jmp OSFILE

;; Reads a hexadecimal address from the command line into <OSFILE_BLOCK>, after any spaces.
;; In: X = the address's offset in OSFILE_BLOCK, Y = the offset in <TEXT_POINTER>
;; Out:
;;   carry = set when an address was read
;;   Y = the offset after it and any spaces and comma
;;   zero = set when the line ends there
;; Errors: "Bad address" when the address is over 32 bits
;; Uses: A, OS_WORK+2
READ_HEX_ADDRESS:
    jsr SKIP_SPACES
    jsr READ_HEX_DIGIT
    bcc READ_HEX_ADDRESS_DONE
    jsr CLEAR_OSFILE_ADDRESS
READ_HEX_ADDRESS_LOOP:
    jsr ADD_HEX_DIGIT
    jsr READ_HEX_DIGIT
    bcs READ_HEX_ADDRESS_LOOP
    sec
READ_HEX_ADDRESS_DONE:
    rts

; The rest of *SAVE: the addresses.
SAVE_COMMAND_ADDRESSES:
    ldx #OSFILE_BLOCK_START-OSFILE_BLOCK
    jsr READ_HEX_ADDRESS
    bcc USERV_DEFAULT
    clv
    lda (TEXT_POINTER),y
    cmp #'+'
    bne SAVE_COMMAND_END
    bit OVERFLOW_BYTE               ; overflow set: a length, not an end address
    iny
SAVE_COMMAND_END:
    ldx #OSFILE_BLOCK_END-OSFILE_BLOCK
    jsr READ_HEX_ADDRESS
    bcc USERV_DEFAULT
    php
    bvc SAVE_COMMAND_DEFAULTS
    ldx #$FC                        ; the end address is the start plus the length
    clc
SAVE_COMMAND_ADD_LENGTH:
    lda OSFILE_BLOCK_START-$FC,x
    adc OSFILE_BLOCK_END-$FC,x
    sta OSFILE_BLOCK_END-$FC,x
    inx
    bne SAVE_COMMAND_ADD_LENGTH
SAVE_COMMAND_DEFAULTS:
    ldx #$03
SAVE_COMMAND_DEFAULTS_LOOP:
    lda OSFILE_BLOCK_START,x        ; the start address is the default execution and reload addresses
    sta OSFILE_BLOCK_EXEC,x
    sta OSFILE_BLOCK_LOAD,x
    dex
    bpl SAVE_COMMAND_DEFAULTS_LOOP
    plp
    beq LOAD_COMMAND_OSFILE
    ldx #OSFILE_BLOCK_EXEC-OSFILE_BLOCK
    jsr READ_HEX_ADDRESS
    bcc USERV_DEFAULT
    beq LOAD_COMMAND_OSFILE
    ldx #OSFILE_BLOCK_LOAD-OSFILE_BLOCK
    jsr READ_HEX_ADDRESS
    bcc USERV_DEFAULT
    beq LOAD_COMMAND_OSFILE
    ; Falls through into USERV_DEFAULT: more text follows.

;; The default USERV, which *CODE and *LINE call: raises the "Bad command" error, which the commands also raise for
;; text they cannot read.
;;
;; The message has no zero of its own: the BRK that starts <BAD_KEY> ends it.
USERV_DEFAULT:
    brk
    .byte ERROR_BAD_COMMAND, "Bad command"

;; Raises the "Bad key" error.
BAD_KEY:
    brk
    .byte ERROR_BAD_KEY, "Bad key", 0

;; *KEY: defines a soft key, or with no text after the key number, clears its definition.
;;
;; The text is read with GSREAD, so it can hold control characters written as |M and so on. The old definition is
;; deleted first; the new one is read into the free space at the end of <SOFT_KEYS> and becomes the key's.
;; In: Y = the offset of the text after the command
;; Errors: "Bad key" for a key number over 15 or a definition that does not fit, "Bad string" from <GSREAD_HANDLER>
;;   for a malformed definition such as an unterminated quotation, "Key in use" while a soft key is being expanded
;; Uses: A, X, Y, OS_WORK+2 (the key), OS_SCRATCH
;; See: <DELETE_SOFT_KEY>
KEY_COMMAND:
    jsr PARSE_DECIMAL_NUMBER
    bcc BAD_KEY
    cpx #16
    bcs BAD_KEY
    jsr SKIP_COMMA
    php
    ldx SOFT_KEYS+16                ; the free space
    tya
    pha
    jsr DELETE_SOFT_KEY
    pla
    tay
    plp
    bne KEY_COMMAND_DEFINE
    rts

;; *FX: makes an OSBYTE call, with the number and up to two parameters, in decimal and separated by commas.
;; In: Y = the offset of the text after the command
;; Errors: "Bad command" for a bad number, extra text, or an OSBYTE call nothing recognises
;; Uses: A, X, Y, OS_WORK..OS_WORK+2
;; Entry: OSBYTE_COMMAND = *CODE, *MOTOR, *OPT, *ROM, *TAPE and *TV: makes OSBYTE call A, with up to two parameters
FX_COMMAND:
    jsr PARSE_DECIMAL_NUMBER
    bcc USERV_DEFAULT
    txa
OSBYTE_COMMAND:
    pha
    lda #$00
    sta FX_PARAMETER_X
    sta FX_PARAMETER_Y
    jsr SKIP_SEPARATOR              ; carry set after *FX's number: skip a comma
    beq FX_COMMAND_CALL
    jsr PARSE_DECIMAL_NUMBER
    bcc USERV_DEFAULT
    stx FX_PARAMETER_X
    jsr SKIP_COMMA
    beq FX_COMMAND_CALL
    jsr PARSE_DECIMAL_NUMBER
    bcc USERV_DEFAULT
    stx FX_PARAMETER_Y
    jsr SKIP_SPACES
    bne USERV_DEFAULT
FX_COMMAND_CALL:
    ldy FX_PARAMETER_Y
    ldx FX_PARAMETER_X
    pla
    jsr OSBYTE
    bvs USERV_DEFAULT               ; not recognised
    rts

; The rest of *KEY: reads the definition into the free space, then gives it to the key.
KEY_COMMAND_DEFINE:
    sec                             ; the string does not end at a space
    jsr GSINIT_HANDLER
KEY_COMMAND_READ:
    jsr GSREAD_HANDLER
    bcs KEY_COMMAND_END
    inx
    beq BAD_KEY                     ; no room
    sta SOFT_KEYS,x
    bcc KEY_COMMAND_READ            ; always taken
KEY_COMMAND_END:
    bne BAD_KEY                     ; the string did not end at the end of the line
    php
    sei
    jsr DELETE_SOFT_KEY             ; the key is empty at the free space: moving the free space past the text
    ldx #16                         ; gives the text to the key
KEY_COMMAND_EMPTY_KEYS:
    cpx OS_WORK+2
    beq KEY_COMMAND_NEXT
    lda SOFT_KEYS,x                 ; another empty key at the old free space moves to the new one
    cmp SOFT_KEYS,y
    bne KEY_COMMAND_NEXT
    lda SOFT_KEYS+16
    sta SOFT_KEYS,x
KEY_COMMAND_NEXT:
    dex
    bpl KEY_COMMAND_EMPTY_KEYS
    plp
    rts

;; Finds the length of a soft key's definition: the distance from its start to the next definition's start, or to
;; the free space.
;; In: Y = the key, 0-15
;; Out: A = the length, OS_SCRATCH+1 = the length
;; Keeps: X, Y
GET_SOFT_KEY_LENGTH:
    php
    sei
    lda SOFT_KEYS+16
    sec
    sbc SOFT_KEYS,y
    sta OS_SCRATCH+1
    txa
    pha
    ldx #16
GET_SOFT_KEY_LENGTH_LOOP:
    lda SOFT_KEYS,x
    sec
    sbc SOFT_KEYS,y
    bcc GET_SOFT_KEY_LENGTH_NEXT    ; before the key's start
    beq GET_SOFT_KEY_LENGTH_NEXT
    cmp OS_SCRATCH+1
    bcs GET_SOFT_KEY_LENGTH_NEXT
    sta OS_SCRATCH+1                ; nearer than any so far
GET_SOFT_KEY_LENGTH_NEXT:
    dex
    bpl GET_SOFT_KEY_LENGTH_LOOP
    pla
    tax
    lda OS_SCRATCH+1
    plp
    rts

;; Deletes a soft key's definition and moves the key to the free space, empty.
;;
;; The definitions after the key's, up to offset X, move down over it, and the start offsets after it move down by
;; its length. The key then starts at the free space, and the free space starts where the moved text ends.
;; <KEY_COMMAND> calls it again after reading a new definition into the free space: the key is then empty and at the
;; free space, so nothing moves and only the free space's start moves past the new text. <SOFT_KEY_CONSISTENCY> is
;; &FF while the buffer changes and back to zero after, so a reset in between clears the soft keys.
;; In: X = the end of the text to keep, normally the free space's start, OS_WORK+2 = the key
;; Out: X = the free space's new start, Y = the key
;; Errors: "Key in use" while a soft key is being expanded
;; Uses: A, OS_SCRATCH, OS_SCRATCH+1
DELETE_SOFT_KEY:
    php
    sei
    txa
    pha
    ldy OS_WORK+2
    jsr GET_SOFT_KEY_LENGTH
    lda SOFT_KEYS,y
    tay                             ; Y = the key's start
    clc
    adc OS_SCRATCH+1
    tax                             ; X = the start of the definition after it
    sta OS_SCRATCH
    lda SOFT_KEY_LENGTH
    beq DELETE_SOFT_KEY_MOVE
    brk
    .byte ERROR_KEY_IN_USE, "Key in use", 0
DELETE_SOFT_KEY_MOVE:
    dec SOFT_KEY_CONSISTENCY
    pla
    sec
    sbc OS_SCRATCH
    sta OS_SCRATCH                  ; the bytes to move
    beq DELETE_SOFT_KEY_ADJUST
DELETE_SOFT_KEY_MOVE_LOOP:
    lda SOFT_KEYS+1,x
    sta SOFT_KEYS+1,y
    iny
    inx
    dec OS_SCRATCH
    bne DELETE_SOFT_KEY_MOVE_LOOP
DELETE_SOFT_KEY_ADJUST:
    tya
    pha
    ldy OS_WORK+2
    ldx #16
DELETE_SOFT_KEY_ADJUST_LOOP:
    lda SOFT_KEYS,x
    cmp SOFT_KEYS,y
    bcc DELETE_SOFT_KEY_ADJUST_NEXT
    beq DELETE_SOFT_KEY_ADJUST_NEXT
    sbc OS_SCRATCH+1                ; after the key: down by its length
    sta SOFT_KEYS,x
DELETE_SOFT_KEY_ADJUST_NEXT:
    dex
    bpl DELETE_SOFT_KEY_ADJUST_LOOP
    lda SOFT_KEYS+16
    sta SOFT_KEYS,y
    pla
    sta SOFT_KEYS+16
    tax
    inc SOFT_KEY_CONSISTENCY
    plp
    rts

;; Where each buffer is, by buffer number: the high bytes of the buffers' base addresses.
;;
;; A buffer's offsets run from its first offset in <BUFFER_FIRST_OFFSET> up to &FF, so the base is the address of
;; the buffer's end less &100, and BUFFER_START and BUFFER_END are offsets from it. The buffers are the keyboard,
;; RS-423 input, RS-423 output, the printer, the four sound channels and speech.
;; See: <BUFFER_BASE_LOW>, <POINT_AT_BUFFER>
BUFFER_BASE_HIGH:
    .hibytes BUFFER_BASE(KEYBOARD_BUFFER, 32), BUFFER_BASE(INPUT_BUFFER, 256), BUFFER_BASE(OUTPUT_BUFFER, 192)
    .hibytes BUFFER_BASE(PRINTER_BUFFER, 64), BUFFER_BASE(SOUND_BUFFERS, 16), BUFFER_BASE(SOUND_BUFFERS + 16, 16)
    .hibytes BUFFER_BASE(SOUND_BUFFERS + 32, 16), BUFFER_BASE(SOUND_BUFFERS + 48, 16), BUFFER_BASE(SPEECH_BUFFER, 64)

;; The low bytes of the buffers' base addresses, by buffer number.
;; See: <BUFFER_BASE_HIGH>
BUFFER_BASE_LOW:
    .lobytes BUFFER_BASE(KEYBOARD_BUFFER, 32), BUFFER_BASE(INPUT_BUFFER, 256), BUFFER_BASE(OUTPUT_BUFFER, 192)
    .lobytes BUFFER_BASE(PRINTER_BUFFER, 64), BUFFER_BASE(SOUND_BUFFERS, 16), BUFFER_BASE(SOUND_BUFFERS + 16, 16)
    .lobytes BUFFER_BASE(SOUND_BUFFERS + 32, 16), BUFFER_BASE(SOUND_BUFFERS + 48, 16), BUFFER_BASE(SPEECH_BUFFER, 64)

;; Each buffer's first offset, &100 less its size, by buffer number: where its offsets go after &FF.
;; See: <BUFFER_BASE_HIGH>
BUFFER_FIRST_OFFSET:
    .byte <($100 - 32), <($100 - 256), <($100 - 192), <($100 - 64)
    .byte <($100 - 16), <($100 - 16), <($100 - 16), <($100 - 16), <($100 - 64)

;; Points OS_SCRATCH at a buffer's base address.
;; In: X = the buffer
;; Out: OS_SCRATCH/OS_SCRATCH+1 = the base address
;; Uses: A
;; Keeps: X, Y
POINT_AT_BUFFER:
    lda BUFFER_BASE_LOW,x
    sta OS_SCRATCH
    lda BUFFER_BASE_HIGH,x
    sta OS_SCRATCH+1
    rts

;; OSBYTE &98: examines the next character in a buffer without removing it, through REMV.
;; In: X = the buffer
;; Out: carry = set when the buffer is empty, A = the character, Y = its offset
EXAMINE_BUFFER:
    bit OVERFLOW_BYTE
    bvs REMOVE_FROM_BUFFER_CALL     ; always taken

;; OSBYTE &91: removes the next character from a buffer, through REMV.
;; In: X = the buffer
;; Out: carry = set when the buffer was empty, A = the character, Y = the character
REMOVE_FROM_BUFFER:
    clv
REMOVE_FROM_BUFFER_CALL:
    jmp (REMV)

;; The default REMV: removes the next character from a buffer, or only examines it.
;;
;; When an output buffer becomes empty, event 0 is raised.
;; In: X = the buffer, overflow = set to examine only
;; Out:
;;   carry = set when the buffer is empty
;;   A = the character
;;   Y = the character, or when examining, its offset
;; Keeps: X
;; Uses: OS_SCRATCH
REMV_DEFAULT:
    php
    sei
    lda BUFFER_START,x
    cmp BUFFER_END,x
    beq INSV_DEFAULT_FAIL           ; empty
    tay
    jsr POINT_AT_BUFFER
    lda (OS_SCRATCH),y
    bvs REMV_DEFAULT_DONE
    pha
    iny
    tya
    bne REMV_DEFAULT_ADVANCE
    lda BUFFER_FIRST_OFFSET,x       ; round to the buffer's first offset
REMV_DEFAULT_ADVANCE:
    sta BUFFER_START,x
    cpx #BUFFER_RS423_OUTPUT
    bcc REMV_DEFAULT_REMOVED        ; an input buffer
    cmp BUFFER_END,x
    bne REMV_DEFAULT_REMOVED
    ldy #EVENT_OUTPUT_BUFFER_EMPTY
    jsr OSEVEN_HANDLER
REMV_DEFAULT_REMOVED:
    pla
    tay
REMV_DEFAULT_DONE:
    plp
    clc
    rts

;; OSEVEN: raises an event, calling EVNTV when the event is enabled.
;;
;; The event handler is called with interrupts disabled, the event number in A and the caller's A in Y.
;; In: Y = the event, A = a value for the handler
;; Out: carry = clear when the event was enabled and the handler called
;; Keeps: A, X
;; Uses: Y, OS_SCRATCH
;; See: <EVENT_ENABLE>, <EVNTV>
OSEVEN_HANDLER:
    php
    sei
    pha
    sta OS_SCRATCH
    lda EVENT_ENABLE,y
    beq INSV_DEFAULT_DISCARD        ; disabled
    tya
    ldy OS_SCRATCH
    jsr CALL_EVNTV                       ; JMP (EVNTV)
    pla
    plp
    clc
    rts

;; Raises event 2, a character entering the input buffer, and puts the character into the buffer.
;; In: Y = the character, X = the buffer
;; Out: carry = set when the buffer was full
;; Uses: A, Y
INSERT_WITH_EVENT:
    tya
    ldy #EVENT_CHARACTER_ENTERING
    jsr OSEVEN_HANDLER
    tay
    ; Falls through into INSERT_Y_INTO_BUFFER.

;; OSBYTE &8A: puts a character into a buffer, through INSV.
;; In: Y = the character, X = the buffer
;; Out: carry = set when the buffer was full
;; Uses: A, Y
INSERT_Y_INTO_BUFFER:
    tya
    ; Falls through into INSERT_INTO_BUFFER.

;; Puts a character into a buffer, through INSV.
;; In: A = the character, X = the buffer
;; Out: carry = set when the buffer was full
;; Uses: Y
INSERT_INTO_BUFFER:
    jmp (INSV)

;; The default INSV: puts a character into a buffer.
;;
;; When an input buffer is full, event 1 is raised.
;; In: A = the character, X = the buffer
;; Out: carry = set when the buffer was full
;; Keeps: A, X
;; Uses: Y, OS_SCRATCH
;; Entry:
;;   INSV_DEFAULT_DISCARD = pulls A and returns as below; the exit of <OSEVEN_HANDLER> for a disabled event
;;   INSV_DEFAULT_FAIL = pulls the flags and returns carry set; the exit of <REMV_DEFAULT> for an empty buffer
INSV_DEFAULT:
    php
    sei
    pha
    ldy BUFFER_END,x
    iny
    bne INSV_DEFAULT_CHECK_ROOM
    ldy BUFFER_FIRST_OFFSET,x       ; round to the buffer's first offset
INSV_DEFAULT_CHECK_ROOM:
    tya
    cmp BUFFER_START,x
    beq INSV_DEFAULT_FULL
    ldy BUFFER_END,x
    sta BUFFER_END,x
    jsr POINT_AT_BUFFER
    pla
    sta (OS_SCRATCH),y
    plp
    clc
    rts
INSV_DEFAULT_FULL:
    pla
    cpx #BUFFER_RS423_OUTPUT
    bcs INSV_DEFAULT_FAIL           ; an output buffer
    ldy #EVENT_INPUT_BUFFER_FULL
    jsr OSEVEN_HANDLER
    pha
INSV_DEFAULT_DISCARD:
    pla
INSV_DEFAULT_FAIL:
    plp
    sec
    rts

;; Checks whether a character is a letter, a capital or a small one.
;; In: A = the character
;; Out: carry = clear for a letter
;; Keeps: A, X, Y
CHECK_LETTER:
    pha
    and #%11011111                  ; a capital
    cmp #'A'
    bcc CHECK_LETTER_NOT
    cmp #'Z'+1
    bcc CHECK_LETTER_DONE
CHECK_LETTER_NOT:
    sec
CHECK_LETTER_DONE:
    pla
    rts

;; Puts a key into the keyboard buffer, checking for ESCAPE.
;; In: Y = the character
;; Out: carry = set when the buffer was full
;; Uses: A, X, Y
INSERT_KEY:
    ldx #BUFFER_KEYBOARD
    ; Falls through into INSERT_INPUT_CHARACTER.

;; OSBYTE &99: puts a character into an input buffer, checking for ESCAPE.
;;
;; RS-423 input is checked only when <RS423_MODE> is zero, so that RS-423 input is taken as keyboard input; a
;; character that is not ESCAPE raises event 2 first. When the character is ESCAPE and ESCAPE is enabled, it is not
;; put in the buffer: event 6 is raised, and when that event is disabled the escape flag is set. When ESCAPE is
;; disabled by *FX 200, the character is thrown away.
;; In: X = the buffer, 0 or 1, Y = the character
;; Out: carry = set when the buffer was full
;; Uses: A, Y
;; See: <INSERT_WITH_EVENT>, <SET_ESCAPE>
INSERT_INPUT_CHARACTER:
    txa
    and RS423_MODE
    bne INSERT_Y_INTO_BUFFER        ; RS-423 input that is not keyboard input
    tya
    eor ESCAPE_CHARACTER
    ora ESCAPE_KEY_STATUS
    bne INSERT_WITH_EVENT           ; not ESCAPE, or ESCAPE is an ordinary character
    lda ESCAPE_BREAK_EFFECT
    ror a                           ; bit 0: ESCAPE disabled
    tya
    bcs INSERT_INPUT_CHARACTER_DONE
    ldy #EVENT_ESCAPE_DETECTED
    jsr OSEVEN_HANDLER
    bcc INSERT_INPUT_CHARACTER_DONE
    jsr SET_ESCAPE                       ; carry set: set the escape flag
INSERT_INPUT_CHARACTER_DONE:
    clc
    rts

;; Part of <READ_INPUT>: a cursor key or COPY while the cursor keys do not edit.
;;
;; With *FX 4,1 the key's code, &87-&8B, is returned; with *FX 4,2 the keys are soft keys 11-15, taken as the codes
;; &8B-&8F by READ_INPUT_FUNCTION_CODE.
;; Entry: READ_INPUT_FUNCTION_CODE = interprets a code &80-&FF from the input buffer, kept on the stack, by
;;   <INPUT_INTERPRETATION> or <FUNCTION_KEY_STATUS>
READ_INPUT_CURSOR_KEY:
    ror a                           ; bit 0 of CURSOR_EDITING
    pla
    bcs READ_INPUT_DONE
READ_INPUT_FUNCTION_CODE:
    tya
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    eor #$04                        ; &8x-&Bx to 12-15, &Cx-&Fx to 8-11
    tay
    lda INPUT_INTERPRETATION-8,y    ; or FUNCTION_KEY_STATUS-12,y
    cmp #$01
    beq READ_INPUT_EXPAND_KEY       ; 1: expand the soft key
    pla
    bcc READ_INPUT_NEXT             ; 0: ignore the code
    and #$0F                        ; otherwise the code is that value plus the low nibble
    clc
    adc INPUT_INTERPRETATION-8,y
    clc
    rts
READ_INPUT_NOTHING_TO_COPY:
    jsr SOUND_BELL                       ; sound the bell
    pla
    tax
READ_INPUT_NEXT:
    jsr REMOVE_FROM_BUFFER
    bcs READ_INPUT_RETURN           ; empty
    pha
    cpx #BUFFER_RS423_INPUT
    bne READ_INPUT_INTERPRET
    jsr RESUME_RS423                ; room in the RS-423 input buffer again
    ldx #BUFFER_RS423_INPUT
    sec
READ_INPUT_INTERPRET:
    pla
    bcc READ_INPUT_CODE
    ldy RS423_MODE
    bne READ_INPUT_DONE             ; RS-423 input is not keyboard input: return it as it is
READ_INPUT_CODE:
    tay
    bpl READ_INPUT_DONE
    and #$0F
    cmp #$0B
    bcc READ_INPUT_FUNCTION_CODE
    adc #$7B                        ; &8B-&8F (with carry) to the cursor codes &87-&8B
    pha
    lda CURSOR_EDITING
    bne READ_INPUT_CURSOR_KEY
    lda WRCH_DESTINATION
    ror a
    ror a                           ; WRCH_NO_VDU: no cursor editing without the VDU driver
    pla
    bcs READ_INPUT_NEXT
    cmp #$87                        ; COPY
    beq READ_INPUT_COPY
    tay
    txa
    pha
    tya
    jsr MOVE_EDITING_CURSOR                       ; move the cursor
    pla
    tax
    ; Falls through into READ_INPUT.

;; Reads the next character of input: from Econet, from a soft key being expanded, or from the input buffer.
;;
;; A character from the input buffer is interpreted: codes &80-&FF are taken as <INPUT_INTERPRETATION> and
;; <FUNCTION_KEY_STATUS> say, which can expand a soft key, and while the cursor keys edit, the cursor keys move the
;; cursor and COPY gives the character under it. RS-423 input that is not keyboard input is not interpreted.
;; In: X = the input buffer, 0 or 1
;; Out: carry = clear when A holds a character, set when the buffer is empty
;; Uses: A, Y
;; Keeps: X
;; See: <GET_SOFT_KEY_LENGTH>, <COPY_CHARACTER>
READ_INPUT:
    bit ECONET_RDCH_INTERCEPT
    bpl READ_INPUT_SOFT_KEY
    lda #NETV_RDCH
    ; Falls through into CALL_NETV.

;; Calls the Econet vector, NETV.
;; In: A = the reason
CALL_NETV:
    jmp (NETV)

; The rest of READ_INPUT.
READ_INPUT_SOFT_KEY:
    lda SOFT_KEY_LENGTH
    beq READ_INPUT_NEXT
    ldy SOFT_KEY_POINTER
    lda SOFT_KEYS+1,y
    inc SOFT_KEY_POINTER
    dec SOFT_KEY_LENGTH
READ_INPUT_DONE:
    clc
READ_INPUT_RETURN:
    rts
READ_INPUT_EXPAND_KEY:
    pla
    and #$0F
    tay
    jsr GET_SOFT_KEY_LENGTH
    sta SOFT_KEY_LENGTH
    lda SOFT_KEYS,y
    sta SOFT_KEY_POINTER
    bne READ_INPUT                  ; always taken: definitions start at offset 16 or more
READ_INPUT_COPY:
    txa
    pha
    jsr COPY_CHARACTER                       ; the character under the cursor, or 0
    tay
    beq READ_INPUT_NOTHING_TO_COPY
    pla
    tax
    tya
    clc
    rts
