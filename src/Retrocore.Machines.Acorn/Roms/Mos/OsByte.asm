; ---------------------------------------------------------------------------------------------------------------------
; OSBYTE and OSWORD (&E5B3-&EA0F): the dispatch table, BYTEV and WORDV's default handlers, and the calls behind them
; that live here
; ---------------------------------------------------------------------------------------------------------------------

; The ranges of OSBYTE and OSWORD numbers the dispatch table covers.

LOW_OSBYTE_LIMIT = $16              ;; one past the last OSBYTE of the first run, &00-&15
FIRST_HIGH_OSBYTE = $75             ;; the first OSBYTE of the second run, &75-&A0
LAST_HIGH_OSBYTE = $A0              ;; the last OSBYTE of the second run
FIRST_VARIABLE_OSBYTE = $A6         ;; the first OSBYTE that reads and writes an OS variable, &A6-&FF
OSWORD_LIMIT = $0E                  ;; one past the last OSWORD the MOS handles, &00-&0D
FIRST_USER_OSWORD = $E0             ;; the first OSWORD passed to USERV, &E0-&FF

; Service calls and Econet vector codes. The two OS calls use the same number for both, so one register serves both.

SERVICE_UNRECOGNISED_OSBYTE = 7     ;; the paged ROM service call, and NETV code, for an unrecognised OSBYTE
SERVICE_UNRECOGNISED_OSWORD = 8     ;; the paged ROM service call, and NETV code, for an unrecognised OSWORD
NET_LINE_ENTERED = $0D              ;; the NETV code that says OSWORD 0 has read a line

; The buffer numbers this part uses.

RS423_INPUT_BUFFER_NUMBER = 1       ;; the RS-423 input buffer
PRINTER_BUFFER_NUMBER = 3           ;; the printer buffer
FIRST_SOUND_BUFFER_NUMBER = 4       ;; the buffer of sound channel 0; channels 1-3 follow
SPEECH_BUFFER_NUMBER = 8            ;; the speech buffer

; The serial ULA's bits, as SERIAL_ULA describes them.

SERIAL_TRANSMIT_RATE = %00000111    ;; the serial ULA's transmit baud rate bits
SERIAL_RECEIVE_RATE = %00111000     ;; the serial ULA's receive baud rate bits
SERIAL_RS423 = %01000000            ;; the serial ULA's bit that selects RS-423 rather than the cassette

; The characters OSWORD 0 treats specially.

LINE_BELL = $07                     ;; the character OSWORD 0 echoes when the line is full
LINE_CANCEL = $15                   ;; CTRL-U, which deletes the whole line
LINE_RETURN = $0D                   ;; RETURN, which ends the line
LINE_DELETE = $7F                   ;; DELETE, which deletes the last character

OS_VERSION_ERROR = $F7              ;; the error number of OSBYTE 0's "OS 1.20" error

; OSWORD 0's parameters, copied out of its parameter block.

LINE_MAX_LENGTH = LINE_INPUT_WORK   ;; the longest line OSWORD 0 accepts
LINE_MIN_CHARACTER = LINE_INPUT_WORK + 1 ;; the lowest character OSWORD 0 keeps in the line
LINE_MAX_CHARACTER = LINE_INPUT_WORK + 2 ;; the highest character OSWORD 0 keeps in the line

;; The OSBYTE and OSWORD dispatch table: the address of each call's handler, which <BYTEV_DEFAULT> and
;; <WORDV_DEFAULT> jump to.
;;
;; The table is indexed by a call number mapped onto it: OSBYTE &00-&15 take entries 0-&15, OSBYTE &75-&A0 entries
;; &16-&41, every OSBYTE &A6-&FF the one entry at &42 (<READ_WRITE_OS_VARIABLE>), OSWORD &E0-&FF the entry at &43
;; (<JUMP_USERV>), and OSWORD &00-&0D entries &44-&51. The names are the Advanced User Guide's.
;; See: <BYTEV_DEFAULT>, <WORDV_DEFAULT>, <DISPATCH_OS_CALL>
OSBYTE_ROUTINES:
    .word IDENTIFY_OS_VERSION           ; &00 Identify operating system version
    .word WRITE_OS_VARIABLE_F0          ; &01 User OSBYTE call, read/write location &281
    .word SELECT_INPUT_STREAM           ; &02 Select input stream
    .word WRITE_OS_VARIABLE_E9          ; &03 Select output stream
    .word WRITE_OS_VARIABLE_E9          ; &04 Enable/disable cursor editing
    .word SELECT_PRINTER_TYPE           ; &05 Select printer destination
    .word WRITE_OS_VARIABLE_F0          ; &06 Set character ignored by printer
    .word SET_RECEIVE_BAUD              ; &07 Set RS423 baud rate for receiving data
    .word SET_TRANSMIT_BAUD             ; &08 Set RS423 baud rate for data transmission
    .word SET_FLASH_MARK_DURATION       ; &09 Set flashing colour mark state duration
    .word SET_FLASH_SPACE_DURATION      ; &0A Set flashing colour space state duration
    .word SET_AUTO_REPEAT_DELAY         ; &0B Set keyboard auto-repeat delay interval
    .word SET_AUTO_REPEAT_PERIOD        ; &0C Set keyboard auto-repeat rate
    .word DISABLE_EVENT                 ; &0D Disable events
    .word ENABLE_EVENT                  ; &0E Enable events
    .word FLUSH_BUFFERS                         ; &0F Flush selected buffer class
    .word SELECT_ADC_CHANNELS           ; &10 Select ADC channels to be sampled
    .word START_ADC_CONVERSION                         ; &11 Force an ADC conversion
    .word RESET_SOFT_KEYS               ; &12 Reset soft keys
    .word WAIT_FOR_VSYNC                ; &13 Wait for vertical sync
    .word EXPLODE_FONT                         ; &14 Explode soft character RAM allocation
    .word FLUSH_SPECIFIC_BUFFER                         ; &15 Flush specific buffer
    .assert * - OSBYTE_ROUTINES = 2 * LOW_OSBYTE_LIMIT, "OSBYTE &00-&15 have an entry each."

;; The dispatch table's entries for OSBYTE &75-&A0, part of <OSBYTE_ROUTINES>.
HIGH_OSBYTE_ROUTINES:
    .word READ_VDU_STATUS               ; &75 Read VDU status
    .word REFLECT_KEYBOARD_STATUS       ; &76 Reflect keyboard status in LEDs
    .word CLOSE_SPOOL_AND_EXEC                         ; &77 Close any SPOOL or EXEC files
    .word WRITE_KEYS_PRESSED                         ; &78 Write current keys pressed information
    .word SCAN_KEYBOARD                         ; &79 Perform keyboard scan
    .word SCAN_FROM_16                         ; &7A Perform keyboard scan from 16 (&10)
    .word MARK_PRINTER_DORMANT                         ; &7B Inform OS, printer driver going dormant
    .word CLEAR_ESCAPE                  ; &7C Clear ESCAPE condition
    .word SET_ESCAPE                    ; &7D Set ESCAPE condition
    .word ACKNOWLEDGE_ESCAPE            ; &7E Acknowledge detection of ESCAPE condition
    .word READ_END_OF_FILE                         ; &7F Check for EOF on an open file
    .word READ_ADC_OR_BUFFER            ; &80 Read ADC channel or get buffer status
    .word READ_KEY_WITH_TIME_LIMIT      ; &81 Read key with time limit
    .word READ_HIGH_ORDER_ADDRESS       ; &82 Read machine high order address
    .word READ_OSHWM                         ; &83 Read top of OS RAM address (OSHWM)
    .word READ_HIMEM                         ; &84 Read bottom of display RAM address (HIMEM)
    .word READ_MODE_HIMEM                         ; &85 Read bottom of display address for a given MODE
    .word READ_TEXT_CURSOR                         ; &86 Read text cursor position (POS and VPOS)
    .word READ_CHARACTER                         ; &87 Read character at cursor position
    .word CALL_USER_CODE                ; &88 Perform *CODE
    .word SET_CASSETTE_MOTOR            ; &89 Perform *MOTOR
    .word INSERT_Y_INTO_BUFFER                         ; &8A Insert value into buffer
    .word SET_FILING_SYSTEM_OPTION                         ; &8B Perform *OPT
    .word SELECT_TAPE_OR_ROM                         ; &8C Perform *TAPE
    .word SELECT_TAPE_OR_ROM                         ; &8D Perform *ROM
    .word ENTER_LANGUAGE                         ; &8E Enter language ROM
    .word ISSUE_SERVICE_CALL                         ; &8F Issue paged ROM service request
    .word SET_TV                         ; &90 Perform *TV
    .word REMOVE_FROM_BUFFER                         ; &91 Get character from buffer
    .word READ_FRED                     ; &92 Read from FRED, 1 MHz bus
    .word WRITE_FRED                         ; &93 Write to FRED, 1 MHz bus
    .word READ_JIM                      ; &94 Read from JIM, 1 MHz bus
    .word WRITE_JIM                         ; &95 Write to JIM, 1 MHz bus
    .word READ_SHEILA                   ; &96 Read from SHEILA, mapped I/O
    .word WRITE_SHEILA                         ; &97 Write to SHEILA, mapped I/O
    .word EXAMINE_BUFFER                         ; &98 Examine buffer status
    .word INSERT_INPUT_CHARACTER                         ; &99 Insert character into input buffer
    .word WRITE_VIDEO_ULA_CONTROL       ; &9A Write to video ULA control register and copy
    .word WRITE_PALETTE_REGISTER                         ; &9B Write to video ULA palette register and copy
    .word UPDATE_ACIA_CONTROL                         ; &9C Read/write 6850 control register and copy
    .word FAST_BPUT                     ; &9D Fast Tube BPUT
    .word READ_SPEECH                         ; &9E Read from speech processor
    .word WRITE_SPEECH                         ; &9F Write to speech processor
    .word READ_VDU_VARIABLE             ; &A0 Read VDU variable value
    .assert * - HIGH_OSBYTE_ROUTINES = 2 * (LAST_HIGH_OSBYTE + 1 - FIRST_HIGH_OSBYTE), "OSBYTE &75-&A0 have entries."

;; The dispatch table's entry for every OSBYTE &A6-&FF, part of <OSBYTE_ROUTINES>.
VARIABLE_OSBYTE_ROUTINE:
    .word READ_WRITE_OS_VARIABLE        ; &A6-&FF Read/write an OS variable

;; The dispatch table's entry for every OSWORD &E0-&FF, part of <OSBYTE_ROUTINES>.
USER_OSWORD_ROUTINE:
    .word JUMP_USERV                    ; OSWORD &E0-&FF, passed to USERV

;; The dispatch table's entries for OSWORD &00-&0D, part of <OSBYTE_ROUTINES>.
OSWORD_ROUTINES:
    .word READ_LINE                     ; &00 Read line from currently selected input into memory
    .word READ_SYSTEM_CLOCK             ; &01 Read system clock
    .word WRITE_SYSTEM_CLOCK            ; &02 Write system clock
    .word READ_INTERVAL_TIMER           ; &03 Read interval timer
    .word WRITE_INTERVAL_TIMER          ; &04 Write interval timer
    .word READ_IO_MEMORY                ; &05 Read byte of I/O processor memory
    .word WRITE_IO_MEMORY               ; &06 Write byte of I/O processor memory
    .word SOUND_COMMAND                 ; &07 Perform a SOUND command
    .word DEFINE_ENVELOPE               ; &08 Define an ENVELOPE
    .word READ_PIXEL                         ; &09 Read pixel value
    .word READ_CHARACTER_DEFINITION                         ; &0A Read character definition
    .word READ_PALETTE                         ; &0B Read palette value for a given logical colour
    .word WRITE_PALETTE                         ; &0C Write palette value for a given logical colour
    .word READ_GRAPHICS_CURSORS                         ; &0D Read previous and current graphics cursor positions
    .assert * - OSWORD_ROUTINES = 2 * OSWORD_LIMIT, "OSWORD &00-&0D have an entry each."

;; OSBYTE &88: performs *CODE, calling USERV with A = 0.
;;
;; The user's routine gets the call's X and Y.
;; In: X, Y = the parameters for the user's routine
;; Out: A = 0
;; Entry: JUMP_USERV = jumps through USERV with A unchanged, for OSWORD &E0-&FF
;; See: <USERV>
CALL_USER_CODE:
    lda #$00
JUMP_USERV:
    jmp (USERV)

;; OSBYTE &7E: acknowledges an escape, clearing the escape flag.
;;
;; When an escape is pending and <ESCAPE_EFFECTS> is zero, the acknowledgement also has its side effects: it resets
;; the paged mode line count, closes any *EXEC file and flushes every buffer, with interrupts enabled. The routine
;; then falls into <CLEAR_ESCAPE>.
;; Out: X = &FF when an escape was pending, otherwise 0
;; Uses: A
ACKNOWLEDGE_ESCAPE:
    ldx #$00
    bit ESCAPE_FLAG
    bpl CLEAR_ESCAPE                    ; no escape to acknowledge
    lda ESCAPE_EFFECTS
    bne ACKNOWLEDGE_ESCAPE_1            ; the side effects are turned off
    cli
    sta PAGED_LINES                     ; A = 0
    jsr STAR_EXEC                           ; A = 0: close any *EXEC file
    jsr FLUSH_ALL_BUFFERS                           ; flush every buffer
ACKNOWLEDGE_ESCAPE_1:
    ldx #$FF

;; OSBYTE &7C: clears the escape flag, then falls into <SET_ESCAPE> to tell the Tube.
CLEAR_ESCAPE:
    clc

;; OSBYTE &7D: sets the escape flag, or with carry clear clears it, and passes the escape across the Tube when one is
;; fitted.
;;
;; OSBYTE &7D arrives with carry set, as every OSBYTE does.
;; In: carry = the new escape state: set for an escape
;; See: <TUBE_ESCAPE>
SET_ESCAPE:
    ror ESCAPE_FLAG                     ; carry into bit 7
    bit TUBE_PRESENT
    bmi SET_ESCAPE_TUBE
    rts
SET_ESCAPE_TUBE:
    jmp TUBE_ESCAPE

;; OSBYTE &89: performs *MOTOR, turning the cassette motor on or off.
;;
;; It sets bit 7 of the serial ULA's control register and its copy, then joins <WRITE_SERIAL_ULA>.
;; In: X = 0 to turn the motor off, 1 to turn it on
;; Out: X, Y = the serial ULA's previous setting
;; Uses: A
SET_CASSETTE_MOTOR:
    lda SERIAL_ULA_COPY
    tay
    rol a
    cpx #$01                            ; carry = X is not 0
    ror a                               ; ... into bit 7, the motor
    bvc WRITE_SERIAL_ULA                ; always: OSBYTE calls arrive with overflow clear

;; OSBYTE &08: sets the RS-423 transmit baud rate.
;;
;; It loads the mask for the transmit bits exclusive-ORed with &3F, the form <SET_RECEIVE_BAUD> expects in A, and
;; falls into it.
;; In: X = the rate: 1 for 75 baud up to 8 for 19200, or 0 for the default of 9600
;; Out: X, Y = the serial ULA's previous setting
;; Uses: A, OS_SCRATCH
SET_TRANSMIT_BAUD:
    lda #SERIAL_RECEIVE_RATE            ; exclusive-ORed with &3F: the transmit bits

;; OSBYTE &07: sets the RS-423 receive baud rate.
;;
;; OSBYTE 7's own number, exclusive-ORed with &3F, gives the receive bits' mask, &38, and the &38 that
;; <SET_TRANSMIT_BAUD> loads gives the transmit bits', &07. The new bits come from <SERIAL_ULA_RATES>. Bit 6, which
;; selects RS-423, is set unless <CASSETTE_RS423_SELECT> says the cassette has the serial ULA. A rate of 9 or more
;; changes nothing.
;; In: A = 7, X = the rate: 1 for 75 baud up to 8 for 19200, or 0 for the default of 9600
;; Out: X, Y = the serial ULA's previous setting
;; Uses: A, OS_SCRATCH
SET_RECEIVE_BAUD:
    eor #SERIAL_TRANSMIT_RATE | SERIAL_RECEIVE_RATE
    sta OS_SCRATCH                      ; the bits to change
    ldy SERIAL_ULA_COPY
    cpx #$09
    bcs RETURN_Y_IN_X                   ; not a rate
    and SERIAL_ULA_RATES,x
    sta OS_SCRATCH+1                    ; their new value
    tya
    ora OS_SCRATCH
    eor OS_SCRATCH                      ; clear the bits to change
    ora OS_SCRATCH+1
    ora #SERIAL_RS423
    eor CASSETTE_RS423_SELECT

;; Writes the serial ULA's control register and its copy.
;; In: A = the new setting, Y = a value to return in X
;; Out: X = Y
;; Entry: RETURN_Y_IN_X = only copies Y to X, RETURN_A_IN_X = only copies A to X
;; Keeps: Y
WRITE_SERIAL_ULA:
    sta SERIAL_ULA_COPY
    sta SERIAL_ULA
RETURN_Y_IN_X:
    tya
RETURN_A_IN_X:
    tax
    rts

;; OSBYTE &09: sets the duration of the flashing colours' mark state, the first named colours, in fiftieths of a
;; second.
;;
;; OSBYTE calls &00-&15 arrive with Y = 0, so this one writes the second period, <SPACE_PERIOD> at &0253, which the
;; vertical sync interrupt loads when it changes the video ULA's flash bit to 0. It then joins
;; <SET_FLASH_SPACE_DURATION> with carry clear.
;; In: X = the duration, or 0 for ever, Y = 0
;; Out: X, Y = the previous duration
;; Uses: A
SET_FLASH_MARK_DURATION:
    iny
    clc

;; OSBYTE &0A: sets the duration of the flashing colours' space state, the second named colours, in fiftieths of a
;; second.
;;
;; It writes <MARK_PERIOD> at &0252 (Y = 0), which the vertical sync interrupt loads when it changes the video ULA's
;; flash bit to 1. When flashing has stopped, with <FLASH_COUNTER> at zero, it restarts it from this state: the
;; count becomes the new duration and the flash bit becomes carry, set for OSBYTE &0A and clear for OSBYTE 9.
;; In: X = the duration, or 0 for ever, Y = the period's offset from MARK_PERIOD, carry = the state it sets
;; Out: X, Y = the previous duration
;; Uses: A
;; See: <MARK_PERIOD>, <SPACE_PERIOD>, <FLASH_COUNTER>
SET_FLASH_SPACE_DURATION:
    lda MARK_PERIOD,y
    pha
    txa
    sta MARK_PERIOD,y
    pla
    tay
    lda FLASH_COUNTER
    bne SET_FLASH_SPACE_DURATION_1      ; still flashing
    stx FLASH_COUNTER
    lda VIDEO_ULA_CONTROL_COPY
    php
    ror a
    plp
    rol a                               ; carry into bit 0, the flash state
    sta VIDEO_ULA_CONTROL_COPY
    sta VIDEO_ULA_CONTROL
SET_FLASH_SPACE_DURATION_1:
    bvc RETURN_Y_IN_X                   ; always: OSBYTE calls arrive with overflow clear

;; OSBYTE &02: selects the input stream, the keyboard or RS-423, and whether RS-423 may receive.
;;
;; Bit 7 of the 6850's control register enables its receive interrupt. When that changes, reading the data register
;; discards any byte already received.
;; In: X = 0 for the keyboard with RS-423 disabled, 1 for RS-423, or 2 for the keyboard with RS-423 enabled
;; Out: X = the previous input source
;; Uses: A, Y
;; See: <INPUT_SOURCE>, <ACIA_CONTROL_COPY>
SELECT_INPUT_STREAM:
    txa
    and #$01                            ; 1 for RS-423
    pha
    lda ACIA_CONTROL_COPY
    rol a
    cpx #$01                            ; carry = X is not 0
    ror a                               ; ... into bit 7, the receive interrupt
    cmp ACIA_CONTROL_COPY
    php
    sta ACIA_CONTROL_COPY
    sta ACIA_CONTROL
    jsr RESUME_RS423                           ; set RTS from the room in the input buffer
    plp
    beq SELECT_INPUT_STREAM_1
    bit ACIA_DATA                       ; discard any byte received
SELECT_INPUT_STREAM_1:
    ldx INPUT_SOURCE
    pla
    sta INPUT_SOURCE
    rts

;; OSBYTE &0D: disables an event.
;;
;; OSBYTE &00-&15 arrive with Y = 0, which is the disabled state; the routine joins <ENABLE_EVENT> with it.
;; In: X = the event number, Y = 0
;; Out: X, Y = the event's previous state, 0 when disabled
;; Uses: A
DISABLE_EVENT:
    tya

;; OSBYTE &0E: enables an event, by storing its own OSBYTE number, which is nonzero.
;; In: A = the new state, nonzero to enable, X = the event number
;; Out: X, Y = the event's previous state, 0 when disabled; for an event number of 10 or more, X = A
;; Uses: A
;; See: <EVENT_ENABLE>
ENABLE_EVENT:
    cpx #$0A
    bcs RETURN_A_IN_X                   ; there are only events 0-9
    ldy EVENT_ENABLE,x
    sta EVENT_ENABLE,x
    bvc RETURN_Y_IN_X                   ; always: OSBYTE calls arrive with overflow clear

;; OSBYTE &10: selects how many ADC channels are converted, and starts converting the highest.
;;
;; A nonzero X starts a conversion through <START_ADC_CONVERSION> with Y = 0, which also clears <ADC_LAST_CHANNEL>. X =
;; 0 stops the conversions.
;; In: X = the highest channel to convert, 1-4, or 0 for none, Y = 0, zero = set when X is 0
;; Out: X = the previous highest channel
;; Uses: A, Y
;; See: <ADC_MAX_CHANNEL>
SELECT_ADC_CHANNELS:
    beq SELECT_ADC_CHANNELS_1           ; zero comes from the dispatcher's LDX
    jsr START_ADC_CONVERSION
SELECT_ADC_CHANNELS_1:
    lda ADC_MAX_CHANNEL
    stx ADC_MAX_CHANNEL
    tax
    rts

;; OSBYTE &81: reads a key within a time limit, or with a negative Y tests a key or the keyboard.
;;
;; With Y positive it reads a character through OSRDCH's time-limited entry, <READ_KEY_TIMED>, with interrupts enabled.
;; With Y negative, X is the negative INKEY number: exclusive-ORing it with &7F gives the key number exclusive-ORed with
;; &80 that KEYV's scan (as OSBYTE &79, with the OSBYTE's carry set) takes.
;; In: X, Y = the time limit in centiseconds, low byte first, or Y = &FF and X = the negative INKEY number
;; Out: X = the character and Y = 0, or Y = &1B for an escape or &FF for a timeout; for a key test X and Y are &FF
;;   when the key is pressed, otherwise 0
;; Uses: A
;; See: <READ_HIGH_ORDER_ADDRESS>
READ_KEY_WITH_TIME_LIMIT:
    tya
    bmi READ_KEY_WITH_TIME_LIMIT_SCAN
    cli
    jsr READ_KEY_TIMED
    bcs READ_KEY_WITH_TIME_LIMIT_1      ; timed out or escape: return A in Y
    tax
    lda #$00
READ_KEY_WITH_TIME_LIMIT_1:
    tay
    rts
READ_KEY_WITH_TIME_LIMIT_SCAN:
    txa
    eor #$7F
    tax
    jsr CALL_KEYV                           ; KEYV: carry set, overflow clear, scans as OSBYTE &79
    rol a                               ; carry = the key is pressed

;; OSBYTE &82: reads the machine high order address, &FFFF in the I/O processor.
;;
;; Other routines use it to return &FFFF or 0 by carry: OSBYTE calls arrive with carry set.
;; In: carry = set for &FFFF, clear for 0
;; Out: X, Y = &FF, or 0
;; Keeps: A
READ_HIGH_ORDER_ADDRESS:
    ldx #$FF
    ldy #$FF
    bcs READ_HIGH_ORDER_ADDRESS_1
    inx
    iny
READ_HIGH_ORDER_ADDRESS_1:
    rts

;; OSBYTE &80 for a buffer: counts the characters in an input buffer or the spaces left in an output buffer.
;; In: X = &FF minus the buffer number: &FF for the keyboard buffer down to &F7 for the speech buffer
;; Out: X, Y = the count, low byte first
;; Uses: A
;; See: <READ_ADC_OR_BUFFER>, <CNPV>
READ_BUFFER_STATUS:
    txa
    eor #$FF
    tax
    cpx #$02                            ; carry = an output buffer, so count the spaces

;; Counts a buffer's characters or spaces through CNPV.
;; In: X = the buffer number, carry = clear to count the characters, set to count the spaces
;; Out: X, Y = the count, low byte first
;; Uses: A
;; See: <CNPV>, <PURGE_BUFFER>
COUNT_BUFFER:
    clv
    bvc CALL_CNPV                       ; always

;; Purges a buffer through CNPV.
;; In: X = the buffer number
;; Entry: CALL_CNPV = jumps through CNPV with overflow as the caller set it
;; See: <CNPV>, <COUNT_BUFFER>
PURGE_BUFFER:
    bit OVERFLOW_BYTE                   ; overflow set: purge
CALL_CNPV:
    jmp (CNPV)

;; Says whether the RS-423 input buffer has room above the handshake level, so RTS can let more in.
;; Out: carry = set when the free space is at least <RS423_HANDSHAKE>
;; Uses: A, X, Y
CHECK_RS423_INPUT_ROOM:
    sec
    ldx #RS423_INPUT_BUFFER_NUMBER
    jsr COUNT_BUFFER                    ; the spaces left
    cpy #$01
    bcs CHECK_RS423_INPUT_ROOM_DONE     ; 256 or more
    cpx RS423_HANDSHAKE
CHECK_RS423_INPUT_ROOM_DONE:
    rts

;; OSBYTE &80: reads an ADC channel's last conversion, the fire buttons, or a buffer's status.
;;
;; X = 5-&7F returns &FFFF through <READ_HIGH_ORDER_ADDRESS>.
;; In: X = 1-4 for a channel, 0 for the fire buttons, or negative for a buffer (<READ_BUFFER_STATUS>), zero = set
;;   when X is 0, negative = set when X is negative
;; Out: X, Y = the channel's 16-bit value, low byte first; or for X = 0, X = the fire buttons in bits 0-1 and
;;   Y = the channel last converted, or 0
;; Uses: A
READ_ADC_OR_BUFFER:
    bmi READ_BUFFER_STATUS              ; negative and zero come from the dispatcher's LDX
    beq READ_FIRE_BUTTONS
    cpx #$05
    bcs READ_HIGH_ORDER_ADDRESS         ; carry set: &FFFF
    ldy ADC_HIGH_BYTES-1,x
    lda ADC_LOW_BYTES-1,x
    tax
    rts

;; OSBYTE &80 with X = 0: reads the joystick fire buttons and the ADC channel last converted, which it clears.
;; In: X = 0
;; Out: X = the fire buttons, bits 0 and 1 set while pressed, Y = the channel last converted, or 0
;; Uses: A
READ_FIRE_BUTTONS:
    lda SYS_VIA_ORB
    ror a
    ror a
    ror a
    ror a                               ; bits 4-5, the buttons, to bits 0-1
    eor #$FF                            ; they read 0 when pressed
    and #$03
    ldy ADC_LAST_CHANNEL
    stx ADC_LAST_CHANNEL
    tax
    rts

;; The default OSBYTE handler, which BYTEV points to: finds the call in <OSBYTE_ROUTINES> and runs it.
;;
;; OSBYTE &00-&15 take Y = 0 whatever the caller passed, so their handlers can use OS_Y as the mask that leaves an
;; OS variable's old value out. OSBYTE &16-&74 and &A1-&A5 are unrecognised, and are offered to the paged ROMs.
;;
;; Every handler is entered with A = the OSBYTE number, X and Y = the call's (also in OS_X and OS_Y), carry set,
;; overflow clear (unless bit 6 of <ECONET_OS_INTERCEPT> is set) and zero and negative set from X, interrupts
;; disabled. It returns X and Y to the caller with carry, and the caller's A comes back unchanged.
;; In: A = the OSBYTE number, X, Y = its parameters
;; Out: X, Y = its results, carry = as the handler returns it, overflow = set for a call nothing recognized
;; Keeps: A
;; See: <WORDV_DEFAULT>, <OSBYTE_ROUTINES>, <DISPATCH_OS_CALL>
BYTEV_DEFAULT:
    pha
    php
    sei
    sta OS_A
    stx OS_X
    sty OS_Y
    ldx #SERVICE_UNRECOGNISED_OSBYTE
    cmp #FIRST_HIGH_OSBYTE
    bcc BYTEV_DEFAULT_LOW
    cmp #LAST_HIGH_OSBYTE + 1
    bcc BYTEV_DEFAULT_HIGH
    cmp #FIRST_VARIABLE_OSBYTE
    bcc UNRECOGNISED_OS_CALL
    clc

;; Indexes the dispatch table's OS variable entry (carry clear) or its USERV entry (carry set), then dispatches.
;;
;; The entry that follows OSBYTE &A0's is number &A1 less the offset BYTEV_DEFAULT_HIGH subtracts.
;; In: carry = clear for OSBYTE &A6-&FF, set for OSWORD &E0-&FF, X = the unrecognised call's service number, Y = the
;;   call's Y
BYTEV_DEFAULT_VARIABLE:
    lda #LAST_HIGH_OSBYTE + 1
    adc #$00

;; Indexes the dispatch table for OSBYTE &75-&A0, then dispatches.
;; In: A = the OSBYTE number, X = the unrecognised call's service number, Y = the call's Y
BYTEV_DEFAULT_HIGH:
    sec
    sbc #FIRST_HIGH_OSBYTE - (HIGH_OSBYTE_ROUTINES - OSBYTE_ROUTINES) / 2

;; Doubles a dispatch table index into an offset, then dispatches an OSBYTE.
;; In: A = the index, X = the unrecognised call's service number, Y = the call's Y
BYTEV_DEFAULT_INDEX:
    asl a
    sec                                 ; an OSBYTE

;; Runs an OSBYTE or OSWORD handler from <OSBYTE_ROUTINES>, after letting Econet intercept it.
;;
;; When bit 7 of <ECONET_OS_INTERCEPT> is set, NETV is called first with A = 7 or 8, the same number as the service
;; call; when it returns with overflow set the call is not made. An OSBYTE handler gets A = the OSBYTE number and Y
;; the call's Y; an OSWORD handler gets A = the first byte of the parameter block and Y = 0. Both get X = OS_X and
;; carry set. The exit, <OS_CALL_EXIT>, returns the handler's carry in the caller's flags.
;; In: A = the entry's offset in OSBYTE_ROUTINES, X = 7 for an OSBYTE or 8 for an OSWORD, Y = the call's Y,
;;   carry = set for an OSBYTE, clear for an OSWORD; the stack holds the caller's A and flags
;; Out: X, Y = the handler's results, carry = the handler's carry
;; Keeps: A
;; Entry: OS_CALL_EXIT = returns to the caller with carry and X and Y as they are
;; See: <BYTEV_DEFAULT>, <WORDV_DEFAULT>, <NETV>
DISPATCH_OS_CALL:
    sty OS_Y
    tay
    bit ECONET_OS_INTERCEPT
    bpl DISPATCH_OS_CALL_1
    txa                                 ; the NETV code
    clv
    jsr CALL_NETV                           ; NETV
    bvs OS_CALL_EXIT                    ; Econet took the call
DISPATCH_OS_CALL_1:
    lda OSBYTE_ROUTINES+1,y
    sta OS_SCRATCH+1
    lda OSBYTE_ROUTINES,y
    sta OS_SCRATCH
    lda OS_A
    ldy OS_Y
    bcs DISPATCH_OS_CALL_2              ; an OSBYTE
    ldy #$00
    lda (OS_X),y                        ; an OSWORD: the parameter block's first byte
DISPATCH_OS_CALL_2:
    sec
    ldx OS_X
    jsr CALL_OS_SCRATCH                           ; JMP (OS_SCRATCH)
OS_CALL_EXIT:
    ror a                               ; the handler's carry into bit 7
    plp                                 ; the caller's flags
    rol a                               ; ... and back into carry
    pla                                 ; the caller's A
    clv
    rts

;; Indexes the dispatch table for OSBYTE &00-&15, giving them Y = 0, or treats OSBYTE &16-&74 as unrecognised.
;; In: A = the OSBYTE number, X = 7
BYTEV_DEFAULT_LOW:
    ldy #$00
    cmp #LOW_OSBYTE_LIMIT
    bcc BYTEV_DEFAULT_INDEX

;; Offers an unrecognised OSBYTE or OSWORD to the paged ROMs, as service call 7 or 8.
;;
;; When a ROM claims it, the call returns with the ROM's X from OS_X and its Y. Otherwise it returns with overflow
;; set. <OFFER_OS_CALL_TO_ROMS> is where a handler that turns its call down jumps, with its return address on the
;; stack: the two PHPs here stand in for that address, so both paths pull two bytes.
;; In: X = 7 for an OSBYTE or 8 for an OSWORD; the stack holds the caller's A and flags
;; Out: overflow = set when no ROM claimed the call, X, Y = a claiming ROM's results
;; Keeps: A
;; Entry: OFFER_OS_CALL_TO_ROMS = from a handler, dropping its return address
;; See: <ISSUE_SERVICE_CALL>
UNRECOGNISED_OS_CALL:
    php
    php
OFFER_OS_CALL_TO_ROMS:
    pla
    pla
    jsr ISSUE_SERVICE_CALL                           ; issue service call X
    bne UNRECOGNISED_OS_CALL_UNCLAIMED
    ldx OS_X
    jmp OS_CALL_EXIT
UNRECOGNISED_OS_CALL_UNCLAIMED:
    plp
    pla
    bit OVERFLOW_BYTE                   ; overflow set: unrecognised
    rts

;; Says whether the cassette filing system should print its messages.
;;
;; It keeps quiet while <CASSETTE_CRITICAL> is set, talks while cataloguing, and otherwise follows the message bit
;; of the current options, which the cassette code keeps in the high nibble of &BB (FS_SCRATCH+11).
;; Out: A = 0 and zero = set to keep quiet; otherwise A = &08 when cataloguing, or the options' message bit (&80)
CHECK_CFS_MESSAGES:
    lda CASSETTE_CRITICAL
    bmi RETURN_A_ZERO
    lda #$08                            ; cataloguing
    and CFS_STATUS
    bne CHECK_CFS_MESSAGES_DONE
    lda #$88
    and FS_SCRATCH+11
CHECK_CFS_MESSAGES_DONE:
    rts

;; The default OSWORD handler, which WORDV points to: finds the call in <OSBYTE_ROUTINES> and runs it.
;;
;; OSWORD &E0-&FF go to USERV with the registers unchanged; &0E-&DF are offered to the paged ROMs as service call 8.
;; Each handler is entered with A = the parameter block's first byte, X = OS_X, Y = 0, carry set and the block's
;; address in OS_X and OS_Y. The OSWORD number is in OS_A.
;; In: A = the OSWORD number, X, Y = the parameter block's address, low byte first
;; Out: carry = as the handler returns it, overflow = set for a call nothing recognized
;; Keeps: A
;; See: <BYTEV_DEFAULT>, <OSBYTE_ROUTINES>, <DISPATCH_OS_CALL>
WORDV_DEFAULT:
    pha
    php
    sei
    sta OS_A
    stx OS_X
    sty OS_Y
    ldx #SERVICE_UNRECOGNISED_OSWORD
    cmp #FIRST_USER_OSWORD
    bcs BYTEV_DEFAULT_VARIABLE          ; carry set: the USERV entry
    cmp #OSWORD_LIMIT
    bcs UNRECOGNISED_OS_CALL
    adc #(OSWORD_ROUTINES - OSBYTE_ROUTINES) / 2
    asl a
    bcc DISPATCH_OS_CALL                ; always, with carry clear: an OSWORD

;; OSWORD &05: reads a byte of the I/O processor's memory.
;; In: OS_X/OS_Y = the parameter block: the address in its first two bytes, the byte returned in its fifth
;; Out: A = the byte
;; Uses: X, Y, OS_SCRATCH
READ_IO_MEMORY:
    jsr GET_IO_ADDRESS
    lda (OS_SCRATCH-1,x)                ; X = 1: (OS_SCRATCH)
    sta (OS_X),y
    rts

;; OSWORD &06: writes a byte of the I/O processor's memory.
;; In: OS_X/OS_Y = the parameter block: the address in its first two bytes, the byte to write in its fifth
;; Out: A = 0
;; Uses: X, Y, OS_SCRATCH
;; Entry: RETURN_A_ZERO = only returns A = 0
WRITE_IO_MEMORY:
    jsr GET_IO_ADDRESS
    lda (OS_X),y
    sta (OS_SCRATCH-1,x)                ; X = 1: (OS_SCRATCH)
RETURN_A_ZERO:
    lda #$00
    rts

;; Takes OSWORD 5 or 6's address from its parameter block into OS_SCRATCH.
;;
;; It returns X = 1 so the caller can reach the address as (OS_SCRATCH-1,X) while Y indexes the block.
;; In: A = the address's low byte, the block's first byte, Y = 0
;; Out: OS_SCRATCH = the address, Y = 4, the data byte's offset in the block, X = 1
;; Uses: A
;; Entry: GET_IO_ADDRESS_1 = only sets X to 1
GET_IO_ADDRESS:
    sta OS_SCRATCH
    iny
    lda (OS_X),y
    sta OS_SCRATCH+1
    ldy #$04
GET_IO_ADDRESS_1:
    ldx #$01
    rts

;; OSBYTE &00: identifies the operating system version: X = 1 for OS 1.20, or with X = 0 the error "OS 1.20".
;; In: X = 0 for the error, otherwise the version number is returned, zero = set when X is 0
;; Out: X = 1
IDENTIFY_OS_VERSION:
    bne GET_IO_ADDRESS_1                ; zero comes from the dispatcher's LDX
    brk
    .byte OS_VERSION_ERROR
    .byte "OS 1.20",0

;; OSWORD &07: performs a SOUND command, queueing a note on a sound channel, or passes a speech command on.
;;
;; The parameter block holds the channel, amplitude, pitch and duration, two bytes each. A channel of &FFxx sends a
;; command to the speech system (<SPEECH_COMMAND>); one of &2000 or more is offered to the paged ROMs as an
;; unrecognised OSWORD. Otherwise the channel is &HSFN: N the channel, F nonzero to flush it first, S the
;; synchronization count and H nonzero to hold. Each note takes three bytes of the channel's buffer: the first
;; packs the sync count in bits 0-1, the hold bit in bit 2 and (amplitude - 1) * 8 above them, which is an envelope's
;; number less one in bits 3-6 or, with bit 7 set, a volume of -15 to 0 plus 15; then the pitch and the duration.
;; It waits while the buffer is full, unless an escape is pending.
;; In: OS_X/OS_Y = the parameter block, A = the channel's low byte, Y = 0
;; Uses: A, X, Y, OS_SCRATCH
;; See: <SOUND_BELL>, <READ_SOUND_PARAMETER>, <INSERT_OR_WAIT>
SOUND_COMMAND:
    iny
    lda (OS_X),y                        ; the channel's high byte
    cmp #$FF
    beq SPEECH_COMMAND
    cmp #$20
    ldx #SERVICE_UNRECOGNISED_OSWORD
    bcs OFFER_OS_CALL_TO_ROMS
    dey
    jsr READ_SOUND_PARAMETER            ; N, and carry = F
    ora #FIRST_SOUND_BUFFER_NUMBER
    tax
    bcc SOUND_COMMAND_1
    jsr FLUSH_BUFFER_LEAVE_CHANNEL                           ; flush the channel
    ldy #$01
SOUND_COMMAND_1:
    jsr READ_SOUND_PARAMETER            ; S, and carry = H
    sta OS_SCRATCH
    php
    ldy #$06
    lda (OS_X),y                        ; the duration
    pha
    ldy #$04
    lda (OS_X),y                        ; the pitch
    pha
    ldy #$02
    lda (OS_X),y                        ; the amplitude
    rol a                               ; times two, plus the hold bit
    sec
    sbc #$02
    asl a
    asl a
    ora OS_SCRATCH                      ; the sync count
    jsr INSERT_OR_WAIT                           ; queue it, waiting for room
    bcc QUEUE_NOTE_REST

;; Abandons a SOUND or speech command whose buffer stayed full until an escape, dropping what it had stacked, and
;; returns through <READ_VDU_STATUS>.
SOUND_COMMAND_ABANDON:
    pla
    pla
    plp

;; OSBYTE &75: reads the VDU status byte.
;; Out: X = <VDU_STATUS>
READ_VDU_STATUS:
    ldx VDU_STATUS
    rts

;; Sounds the bell, for VDU 7: queues a note from the bell's OS variables.
;;
;; <BELL_AMPLITUDE> is kept in the form of a note's first byte, so it is queued as it is.
;; Uses: A, X, Y
;; See: <BELL_CHANNEL>, <BELL_AMPLITUDE>, <BELL_PITCH>, <BELL_DURATION>, <SOUND_COMMAND>
SOUND_BELL:
    php
    sei
    lda BELL_CHANNEL
    and #$07
    ora #FIRST_SOUND_BUFFER_NUMBER
    tax
    lda BELL_AMPLITUDE
    jsr INSERT_INTO_BUFFER                           ; INSV
    lda BELL_DURATION
    pha
    lda BELL_PITCH
    pha

;; Marks a sound channel active, then queues the note's pitch and duration from the stack.
;; In: X = the channel's buffer, 4-7; the stack holds the pitch, then the duration, then the flags to restore
QUEUE_NOTE_REST:
    sec
    ror SOUND_WORKSPACE,x               ; bit 7 of the channel's byte at &0804-&0807
    bmi QUEUE_LAST_TWO_BYTES            ; always

;; OSWORD &07 with a channel of &FFxx: queues a three-byte speech command, the channel's low byte then the
;; amplitude's high and low bytes, in the speech buffer.
;; In: OS_X/OS_Y = the parameter block, Y = 1
;; Uses: A, X, Y
SPEECH_COMMAND:
    php
    iny
    lda (OS_X),y
    pha
    iny
    lda (OS_X),y
    pha
    ldy #$00
    lda (OS_X),y
    ldx #SPEECH_BUFFER_NUMBER
    jsr INSERT_OR_WAIT                           ; queue it, waiting for room
    bcs SOUND_COMMAND_ABANDON
    ror BUFFER_BUSY+SPEECH_BUFFER_NUMBER ; carry clear: the buffer is not empty

;; Queues two bytes from the stack in buffer X, then restores the flags under them.
;; In: X = the buffer; the stack holds the two bytes, then the flags
;; Uses: A, Y
QUEUE_LAST_TWO_BYTES:
    pla
    jsr INSERT_INTO_BUFFER                           ; INSV
    pla
    jsr INSERT_INTO_BUFFER                           ; INSV
    plp
    rts

;; OSWORD &08: defines an ENVELOPE.
;;
;; Envelope n takes the sixteen bytes at <ENVELOPES> + (n - 1) * 16: the parameter block's thirteen parameters,
;; then three zeros. Envelopes 5-16 lie in the output buffer's space.
;; In: A = the envelope number, 1-16, the block's first byte, carry = set; OS_X/OS_Y = the parameter block
;; Uses: A, X, Y
DEFINE_ENVELOPE:
    sbc #$01
    asl a
    asl a
    asl a
    asl a
    ora #$0F                            ; the envelope's last byte
    tax
    lda #$00
    ldy #$10
DEFINE_ENVELOPE_LOOP:
    cpy #$0E
    bcs DEFINE_ENVELOPE_STORE           ; the last three bytes are 0
    lda (OS_X),y
DEFINE_ENVELOPE_STORE:
    sta ENVELOPES,x
    dex
    dey
    bne DEFINE_ENVELOPE_LOOP
    rts

;; Reads a byte of a SOUND command's channel number.
;; In: Y = the byte's offset in the parameter block
;; Out: A = its bits 0-1, carry = set when its high nibble is nonzero, Y = Y + 1
READ_SOUND_PARAMETER:
    lda (OS_X),y
    cmp #$10
    and #$03
    iny
    rts

;; OSWORD &03: reads the interval timer into the parameter block, low byte first.
;; In: OS_X/OS_Y = the parameter block
;; Uses: A, X, Y
;; See: <INTERVAL_TIMER>
READ_INTERVAL_TIMER:
    ldx #INTERVAL_TIMER - (CLOCK_A - 5)
    bne READ_CLOCK_COPY                 ; always

;; OSWORD &01: reads the system clock into the parameter block, low byte first.
;; In: OS_X/OS_Y = the parameter block
;; Uses: A, X, Y
;; See: <CLOCK_A>, <TIMER_SWITCH>
READ_SYSTEM_CLOCK:
    ldx TIMER_SWITCH                    ; 5 or 10, the current copy

;; Copies five bytes, stored high byte first, into the parameter block low byte first.
;;
;; The offsets count from five bytes before CLOCK_A, so 5 is <CLOCK_A>, 10 <CLOCK_B> and 15 <INTERVAL_TIMER>.
;; In: X = the offset, OS_X/OS_Y = the parameter block
;; Uses: A, X, Y
;; Entry: READ_CLOCK_COPY_DONE = only returns
READ_CLOCK_COPY:
    ldy #$04
READ_CLOCK_COPY_LOOP:
    lda CLOCK_A-5,x
    sta (OS_X),y
    inx
    dey
    bpl READ_CLOCK_COPY_LOOP
READ_CLOCK_COPY_DONE:
    rts

;; OSWORD &04: writes the interval timer from the parameter block, low byte first.
;; In: OS_X/OS_Y = the parameter block, carry = set
;; Uses: A, X, Y
WRITE_INTERVAL_TIMER:
    lda #INTERVAL_TIMER - (CLOCK_A - 5)
    bne WRITE_CLOCK_COPY                ; always

;; OSWORD &02: writes the system clock from the parameter block, low byte first.
;;
;; It writes the copy that is not current, then makes it current, so the interrupt never updates a half-written
;; clock.
;; In: OS_X/OS_Y = the parameter block
;; Uses: A, X, Y
;; See: <CLOCK_A>, <TIMER_SWITCH>
WRITE_SYSTEM_CLOCK:
    lda TIMER_SWITCH
    eor #$0F                            ; 5 and 10 swap
    clc

;; Copies five bytes from the parameter block, low byte first, into a clock stored high byte first.
;; In: A = the offset, as <READ_CLOCK_COPY> takes it, carry = clear to make it the current clock
;; Uses: A, X, Y
WRITE_CLOCK_COPY:
    pha
    tax
    ldy #$04
WRITE_CLOCK_COPY_LOOP:
    lda (OS_X),y
    sta CLOCK_A-5,x
    inx
    dey
    bpl WRITE_CLOCK_COPY_LOOP
    pla
    bcs READ_CLOCK_COPY_DONE            ; the interval timer
    sta TIMER_SWITCH
    rts

;; OSWORD &00: reads a line from the current input stream into memory.
;;
;; Characters are echoed through OSWRCH. DELETE removes the last character and CTRL-U the whole line; RETURN or an
;; escape ends it. A character outside the block's range is echoed but not kept, and once the line is full only
;; RETURN is kept: anything else gets a bell. While the VDU driver is collecting a control code's parameters,
;; characters are echoed without being kept. On RETURN the routine prints a new line and tells NETV (code &0D).
;; In: OS_X/OS_Y = the parameter block: the buffer's address, the maximum length, then the lowest and highest
;;   characters to keep
;; Out: Y = the line's length, not counting its RETURN, carry = set when an escape ended it
;; Uses: A, X
;; See: <INPUT_BUFFER_POINTER>, <LINE_INPUT_WORK>
READ_LINE:
    ldy #$04
READ_LINE_PARAMETERS:
    lda (OS_X),y
    sta LINE_MAX_LENGTH-2,y
    dey
    cpy #$02
    bcs READ_LINE_PARAMETERS
    lda (OS_X),y
    sta INPUT_BUFFER_POINTER+1
    dey
    sty PAGED_LINES                     ; Y = 0
    lda (OS_X),y
    sta INPUT_BUFFER_POINTER
    cli
    bcc READ_LINE_NEXT                  ; always: carry is clear from the CPY
READ_LINE_BELL:
    lda #LINE_BELL
READ_LINE_REJECT:
    dey                                 ; with the INY, leaves Y where it was
READ_LINE_ACCEPT:
    iny
READ_LINE_ECHO:
    jsr OSWRCH
READ_LINE_NEXT:
    jsr OSRDCH
    bcs READ_LINE_EXIT                  ; escape
    tax
    lda WRCH_DESTINATION
    ror a
    ror a                               ; carry = bit 1, the VDU driver disabled
    txa
    bcs READ_LINE_CHARACTER
    ldx VDU_QUEUE_COUNT
    bne READ_LINE_ECHO                  ; a VDU parameter
READ_LINE_CHARACTER:
    cmp #LINE_DELETE
    bne READ_LINE_NOT_DELETE
    cpy #$00
    beq READ_LINE_NEXT                  ; nothing to delete
    dey
    bcs READ_LINE_ECHO                  ; always: carry is set from the CMP
READ_LINE_NOT_DELETE:
    cmp #LINE_CANCEL
    bne READ_LINE_STORE
    tya
    beq READ_LINE_NEXT
    lda #LINE_DELETE
READ_LINE_ERASE:
    jsr OSWRCH
    dey
    bne READ_LINE_ERASE
    beq READ_LINE_NEXT                  ; always
READ_LINE_STORE:
    sta (INPUT_BUFFER_POINTER),y
    cmp #LINE_RETURN
    beq READ_LINE_END
    cpy LINE_MAX_LENGTH
    bcs READ_LINE_BELL                  ; full
    cmp LINE_MIN_CHARACTER
    bcc READ_LINE_REJECT
    cmp LINE_MAX_CHARACTER
    beq READ_LINE_ACCEPT
    bcc READ_LINE_ACCEPT
    bcs READ_LINE_REJECT                ; always
READ_LINE_END:
    jsr OSNEWL
    jsr CALL_NETV                           ; NETV, with A = &0D from OSNEWL: the line is entered
READ_LINE_EXIT:
    lda ESCAPE_FLAG
    rol a                               ; carry = escape
    rts

;; OSBYTE &05: selects the printer type, once the printer buffer has emptied.
;;
;; It waits, with interrupts let in between checks, until the printer buffer is empty, giving up if an escape is
;; pending. It then tells the user print routine (UPTV, A = 5) and writes <PRINTER_DESTINATION> through
;; <WRITE_OS_VARIABLE_F0>.
;; In: A = 5, X = the printer type
;; Out: X = the previous printer type, Y = <PRINTER_IGNORE>
;; Uses: A
;; See: <UPTV>, <CALL_PRINTER_DRIVER_FOR>
SELECT_PRINTER_TYPE:
    cli
    sei
    bit ESCAPE_FLAG
    bmi READ_WRITE_OS_VARIABLE_DONE
    bit BUFFER_BUSY+PRINTER_BUFFER_NUMBER
    bpl SELECT_PRINTER_TYPE             ; not empty yet
    jsr CALL_PRINTER_DRIVER_FOR                           ; tell the printer driver
    ldy #$00
    sty OS_Y

;; OSBYTE &01 and &06: write the OS variable that OSBYTE &F0 + A reads, <USER_FLAG> or <PRINTER_IGNORE>.
;; In: A = the OSBYTE number, X = the new value, OS_Y = 0
;; Out: X = the previous value, Y = the next variable's value
WRITE_OS_VARIABLE_F0:
    ora #$F0
    bne SET_OS_VARIABLE                 ; always

;; OSBYTE &0C: sets the keyboard auto-repeat period, or with X = 0 resets the period and the delay to their
;; defaults, 8 and 50 centiseconds.
;;
;; It then joins <SET_AUTO_REPEAT_DELAY>, whose arithmetic turns &0C into &C5, <AUTO_REPEAT_PERIOD>'s OSBYTE.
;; In: A = &0C, X = the period in centiseconds, zero = set when X is 0, carry = set, OS_Y = 0
;; Out: X = the previous period, Y = the next variable's value
SET_AUTO_REPEAT_PERIOD:
    bne SET_AUTO_REPEAT_DELAY           ; zero comes from the dispatcher's LDX
    ldx #$32
    stx AUTO_REPEAT_DELAY
    ldx #$08

;; OSBYTE &0B: sets the keyboard auto-repeat delay, writing <AUTO_REPEAT_DELAY>, the variable OSBYTE &C4 reads.
;;
;; With carry set, adding &CF and then &E9 adds &B9, taking &0B to &C4 and &0C to &C5.
;; In: A = &0B or &0C, X = the delay in centiseconds, carry = set, OS_Y = 0
;; Out: X = the previous value, Y = the next variable's value
SET_AUTO_REPEAT_DELAY:
    adc #$CF

;; OSBYTE &03 and &04: write the OS variable that OSBYTE &E9 + A reads, <WRCH_DESTINATION> or <CURSOR_EDITING>.
;; In: A = the OSBYTE number, X = the new value, OS_Y = 0
;; Out: X = the previous value, Y = the next variable's value
WRITE_OS_VARIABLE_E9:
    clc
    adc #$E9

;; Writes an OS variable: new = (old AND OS_Y) EOR X.
;; In: A = the OSBYTE number that reads the variable, &A6-&FF, X = the value to exclusive-OR, OS_Y = the mask
;; Out: X = the previous value, Y = the next variable's value
SET_OS_VARIABLE:
    stx OS_X

;; OSBYTE &A6-&FF: read and write an OS variable: new = (old AND Y) EOR X.
;; In: A = the OSBYTE number, OS_X = X, OS_Y = Y
;; Out: X = the previous value, Y = the next variable's value
;; Entry: READ_WRITE_OS_VARIABLE_DONE = only returns
;; See: <OS_VARIABLES>
READ_WRITE_OS_VARIABLE:
    tay
    lda OS_VARIABLES,y
    tax
    and OS_Y
    eor OS_X
    sta OS_VARIABLES,y
    lda OS_VARIABLES+1,y
    tay
READ_WRITE_OS_VARIABLE_DONE:
    rts

;; The serial ULA's settings for the baud rates OSBYTE 7 and 8 take, and a flag for each buffer.
;;
;; The table is indexed by the rate number, 0 (the default, 9600 baud) and 1-8 (75 to 19200 baud): bits 0-2 and
;; 3-5 hold the rate in the serial ULA's transmit and receive fields, and <SET_RECEIVE_BAUD> takes the field it
;; needs. Indexed by buffer number instead, bit 7 marks the four sound channels' buffers, 4-7, which
;; <FLUSH_BUFFER_LEAVE_CHANNEL> treats specially when it flushes one. Bit 6 is set in every entry.
;; See: <SERIAL_ULA>
SERIAL_ULA_RATES:
    .byte %01100100                     ; 0: 9600 baud; buffer 0, the keyboard
    .byte %01111111                     ; 1: 75 baud; buffer 1, RS-423 input
    .byte %01011011                     ; 2: 150 baud; buffer 2, RS-423 output
    .byte %01101101                     ; 3: 300 baud; buffer 3, the printer
    .byte %11001001                     ; 4: 1200 baud; buffer 4, sound channel 0
    .byte %11110110                     ; 5: 2400 baud; buffer 5, sound channel 1
    .byte %11010010                     ; 6: 4800 baud; buffer 6, sound channel 2
    .byte %11100100                     ; 7: 9600 baud; buffer 7, sound channel 3
    .byte %01000000                     ; 8: 19200 baud; buffer 8, speech

;; OSBYTE &13: waits for the next vertical sync, then falls into <READ_VDU_VARIABLE>.
;;
;; The vertical sync interrupt decrements <CFS_TIMEOUT>, so the routine waits, letting interrupts in, until it
;; changes.
;; In: X = a VDU variable's offset, for the fall into READ_VDU_VARIABLE
;; Uses: A, X, Y
WAIT_FOR_VSYNC:
    lda CFS_TIMEOUT
WAIT_FOR_VSYNC_LOOP:
    cli
    sei
    cmp CFS_TIMEOUT
    beq WAIT_FOR_VSYNC_LOOP

;; OSBYTE &A0: reads a VDU variable and the one after it.
;;
;; The VDU variables start at &0300, with <GRAPHICS_WINDOW>.
;; In: X = the variable's offset from &0300
;; Out: X = the variable, Y = the next byte
;; Uses: A
READ_VDU_VARIABLE:
    ldy GRAPHICS_WINDOW+1,x
    lda GRAPHICS_WINDOW,x
    tax
    rts

;; OSBYTE &12: resets the soft keys, so every key's string is empty.
;;
;; Each key's start offset, and the free space pointer after them, becomes &10, the start of the strings. The
;; buffer is marked inconsistent while it is being changed.
;; Out: X = 0
;; Uses: A
;; See: <SOFT_KEYS>, <SOFT_KEY_CONSISTENCY>
RESET_SOFT_KEYS:
    lda #$10
    sta SOFT_KEY_CONSISTENCY
    ldx #$00
RESET_SOFT_KEYS_LOOP:
    sta SOFT_KEYS,x
    inx
    bne RESET_SOFT_KEYS_LOOP
    stx SOFT_KEY_CONSISTENCY
    rts

;; OSBYTE &76: reflects the keyboard status in the keyboard LEDs, and tests CTRL and SHIFT.
;;
;; With carry set, as OSBYTE calls arrive, it first lights both LEDs (<LIGHT_KEYBOARD_LEDS>). Unless an escape is
;; pending, it then calls KEYV to test SHIFT and CTRL, which sets the LEDs from <KEYBOARD_STATUS> and returns its
;; flags in A, so rotating A gives CTRL in carry and SHIFT in negative.
;; In: carry = set to light both LEDs first
;; Out: carry = set when CTRL is pressed, negative = set when SHIFT is pressed; with an escape pending, carry clear
;;   and negative set
;; Uses: A, X, Y
;; See: <KEYV>
REFLECT_KEYBOARD_STATUS:
    php
    sei
    lda #$40                            ; becomes &80 if an escape is pending: negative
    jsr LIGHT_KEYBOARD_LEDS
    bmi REFLECT_KEYBOARD_STATUS_DONE
    clc
    clv
    jsr CALL_KEYV                           ; KEYV: test SHIFT and CTRL
REFLECT_KEYBOARD_STATUS_DONE:
    plp
    rol a
    rts

;; With carry set, lights the CAPS LOCK and SHIFT LOCK LEDs, by writing 0 to the addressable latch's bits 7 and 6;
;; then tests for an escape.
;; In: carry = set to light the LEDs
;; Out: negative = set when an escape is pending
;; Uses: Y
;; Keeps: A, X
LIGHT_KEYBOARD_LEDS:
    bcc LIGHT_KEYBOARD_LEDS_ESCAPE
    ldy #$07                            ; latch bit 7, SHIFT LOCK's LED, low: lit
    sty SYS_VIA_ORB
    dey                                 ; latch bit 6, CAPS LOCK's LED
    sty SYS_VIA_ORB
LIGHT_KEYBOARD_LEDS_ESCAPE:
    bit ESCAPE_FLAG
    rts

;; Writes the system VIA's port B, setting a bit of the addressable latch, with interrupts disabled.
;; In: A = the latch bit's number in bits 0-2 and its new value in bit 3
;; Keeps: A, X, Y
WRITE_SYSTEM_LATCH:
    php
    sei
    sta SYS_VIA_ORB
    plp
    rts

;; OSBYTE &9A: writes the video ULA's control register and its copy.
;;
;; Writing it restarts the flash count from <SPACE_PERIOD>.
;; In: X = the new value
;; Uses: A
;; Keeps: X, Y
;; Entry: SET_VIDEO_ULA_CONTROL = takes the value in A
;; See: <VIDEO_ULA_CONTROL>, <VIDEO_ULA_CONTROL_COPY>
WRITE_VIDEO_ULA_CONTROL:
    txa
SET_VIDEO_ULA_CONTROL:
    php
    sei
    sta VIDEO_ULA_CONTROL_COPY
    sta VIDEO_ULA_CONTROL
    lda SPACE_PERIOD
    sta FLASH_COUNTER
    plp
    rts
