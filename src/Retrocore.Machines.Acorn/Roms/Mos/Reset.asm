; ---------------------------------------------------------------------------------------------------------------------
; Constants for the reset code and the interrupt handlers
; ---------------------------------------------------------------------------------------------------------------------

OPCODE_RTI = $40                    ;; the 6502's RTI, which reset puts at <NMI_ROUTINE> so that an NMI returns at once

; How much of page two each kind of reset restores from <DEFAULT_VECTORS>, and what it clears.

DEFAULTS_POWER_ON = LANGUAGE_ROM + 1 - USERV    ;; power on restores &0200-&028C, up to <LANGUAGE_ROM>
DEFAULTS_HARD_BREAK = PRINTER_IGNORE + 1 - USERV ;; a hard BREAK restores &0200-&0286, up to <PRINTER_IGNORE>
DEFAULTS_SOFT_BREAK = CURSOR_EDITING + 1 - USERV ;; a soft BREAK restores &0200-&027D, up to <CURSOR_EDITING>

; The hardware set-up.

RESET_SYS_VIA_IER = $F2             ;; enables timer 1, timer 2, CB1 (the ADC) and CA1 (vertical sync)
RESET_SYS_VIA_PCR = $04             ;; CA1 on a falling edge, CA2 (the keyboard) on a rising edge, CB1 and CB2 falling
RESET_SYS_VIA_ACR = $60             ;; timer 1 free running, timer 2 counting pulses on PB6 (the speech processor)
TIMER_100HZ_LATCH = 9998            ;; timer 1's latch: an interrupt every 10,000 cycles at 1 MHz, 100 a second
RESET_USER_VIA_PCR = $0E            ;; CA1 (the printer's acknowledge) on a falling edge, CA2 (its strobe) held high
RESET_ADC_COMMAND = $0E             ;; a 12-bit conversion of channel 2, which reset starts
TUBE_TEST_FLAGS = $81               ;; written to the Tube's status register to set its flag in bit 0, if there is one
RESET_FIRST_KEY = $62               ;; SPACE's internal key number, which reset records as the first key held
BREAK_KEY_CODE = $CA                ;; the code of soft key 10, the BREAK key, which reset puts in the keyboard buffer
ERROR_NO_LANGUAGE = $F9             ;; error &F9, "Language?", when no paged ROM is a language and there is no Tube

; Where the start-up banner's parts are in <STARTUP_BANNER>, which <PRINT_BANNER_TEXT> prints.

BANNER_TITLE = STARTUP_BANNER       ;; a carriage return and "BBC Computer "
BANNER_16K = STARTUP_BANNER + 15    ;; "16K" and a bell
BANNER_32K = STARTUP_BANNER + 20    ;; "32K" and a bell
BANNER_END = STARTUP_BANNER + 25    ;; a backspace and two carriage returns, which end the banner
BOOT_COMMAND = CALL_BREAK_INTERCEPT - 7 ;; "/!BOOT" and a carriage return, which SHIFT+BREAK runs without a boot ROM

; Paged ROM service calls, the events, and the buffers that the interrupt handlers use.

SERVICE_ABSOLUTE_WORKSPACE = $01    ;; service call &01: absolute workspace claim
SERVICE_PRIVATE_WORKSPACE = $02     ;; service call &02: private workspace claim
SERVICE_AUTO_BOOT = $03             ;; service call &03: auto-boot
SERVICE_UNRECOGNISED_IRQ = $05      ;; service call &05: unrecognised interrupt
SERVICE_BRK = $06                   ;; service call &06: break, a BRK has been executed
SERVICE_TUBE_POST_INIT = $FE        ;; service call &FE: Tube system post initialisation
SERVICE_TUBE_MAIN_INIT = $FF        ;; service call &FF: Tube system main initialisation

EVENT_ADC_COMPLETE = 3              ;; event 3: an ADC conversion is complete
EVENT_VSYNC = 4                     ;; event 4: the start of vertical sync
EVENT_INTERVAL_TIMER = 5            ;; event 5: the interval timer has crossed zero
EVENT_RS423_ERROR = 7               ;; event 7: an RS-423 receive error

RS423_INPUT_BUFFER_ID = 1           ;; the RS-423 input buffer's number
RS423_OUTPUT_BUFFER_ID = 2          ;; the RS-423 output buffer's number
PRINTER_BUFFER_ID = 3               ;; the printer buffer's number
SPEECH_BUFFER_ID = 8                ;; the speech buffer's number

PRINTER_TYPE_PARALLEL = 1           ;; <PRINTER_DESTINATION> for the parallel (Centronics) printer port
PRINTER_TYPE_SERIAL = 2             ;; <PRINTER_DESTINATION> for a printer on RS-423

; The 6522 VIAs' interrupt flag and enable bits.

VIA_FLAG_CA2 = $01                  ;; CA2: the keyboard, on the system VIA
VIA_FLAG_CA1 = $02                  ;; CA1: vertical sync on the system VIA, the printer's acknowledge on the user VIA
VIA_FLAG_CB1 = $10                  ;; CB1: the ADC's end of conversion, on the system VIA
VIA_FLAG_T2 = $20                   ;; timer 2: the speech processor, on the system VIA
VIA_FLAG_T1 = $40                   ;; timer 1: the 100 Hz clock, on the system VIA
VIA_FLAGS_ALL = $7F                 ;; every flag, to clear them all or (with bit 7 clear) disable every interrupt

; The 6850 ACIA.

ACIA_RECEIVE_ERRORS = $3A           ;; carrier lost, framing, overrun and parity, in the status shifted right one
ACIA_RTS_HIGH = $40                 ;; control bits 5-6 for RTS high (input held off) and no transmit interrupt
ACIA_RTS_LOW = $00                  ;; control bits 5-6 for RTS low (input allowed) and no transmit interrupt
RS423_TIMEOUT_START = $E7           ;; -25 for <RS423_TIMEOUT>: RS-423 keeps the 6850 for half a second

RDCH_CHARACTER = OS_WORK + 2        ;; OSRDCH's wait: &FF with a time limit (INKEY) or 0, then the character read

; ---------------------------------------------------------------------------------------------------------------------
; The default vectors and OS variables
; ---------------------------------------------------------------------------------------------------------------------

;; A two-byte default in page two: checks that it lands where <RESET>'s copy puts the location.
;; Parameters:
;;   location = the page-two location the value is for
;;   value = its default
.macro DEFAULT_WORD location, value
    .assert * - DEFAULT_VECTORS = (location) - USERV, "A DEFAULT_WORD is out of place."
    .word value
.endmacro

;; A one-byte default in page two: checks that it lands where <RESET>'s copy puts the location.
;; Parameters:
;;   location = the page-two location the value is for
;;   value = its default
.macro DEFAULT_BYTE location, value
    .assert * - DEFAULT_VECTORS = (location) - USERV, "A DEFAULT_BYTE is out of place."
    .byte value
.endmacro

;; The default contents of page two from &0200 to &028C: the 27 vectors, then the OS variables (<OS_VARIABLE_DEFAULTS>).
;;
;; <RESET> copies the table to <USERV> onward: all of it on power on, the vectors and the variables up to
;; <PRINTER_IGNORE> on a hard BREAK, and up to <CURSOR_EDITING> on a soft BREAK. The vectors the MOS does not
;; handle (OSGBPB, the event, user print, Econet and VDU vectors, and the three spares) point at <UNUSED_VECTOR>,
;; which returns. Keyboard.asm copies the filing system vectors' part again when it selects the cassette filing
;; system.
;; See: <RESET>, <DEFAULTS_POWER_ON>, <DEFAULTS_HARD_BREAK>, <DEFAULTS_SOFT_BREAK>
DEFAULT_VECTORS:
    DEFAULT_WORD USERV, USERV_DEFAULT
    DEFAULT_WORD BRKV, BRKV_DEFAULT
    DEFAULT_WORD IRQ1V, IRQ1V_DEFAULT
    DEFAULT_WORD IRQ2V, IRQ2V_DEFAULT
    DEFAULT_WORD CLIV, CLIV_DEFAULT
    DEFAULT_WORD BYTEV, BYTEV_DEFAULT
    DEFAULT_WORD WORDV, WORDV_DEFAULT
    DEFAULT_WORD WRCHV, WRCHV_DEFAULT
    DEFAULT_WORD RDCHV, RDCHV_DEFAULT
    DEFAULT_WORD FILEV, FILEV_DEFAULT
    DEFAULT_WORD ARGSV, ARGSV_DEFAULT
    DEFAULT_WORD BGETV, BGETV_DEFAULT
    DEFAULT_WORD BPUTV, BPUTV_DEFAULT
    DEFAULT_WORD GBPBV, UNUSED_VECTOR
    DEFAULT_WORD FINDV, FINDV_DEFAULT
    DEFAULT_WORD FSCV, FSCV_DEFAULT
    DEFAULT_WORD EVNTV, UNUSED_VECTOR
    DEFAULT_WORD UPTV, UNUSED_VECTOR
    DEFAULT_WORD NETV, UNUSED_VECTOR
    DEFAULT_WORD VDUV, UNUSED_VECTOR
    DEFAULT_WORD KEYV, KEYV_DEFAULT
    DEFAULT_WORD INSV, INSV_DEFAULT
    DEFAULT_WORD REMV, REMV_DEFAULT
    DEFAULT_WORD CNPV, CNPV_DEFAULT
    DEFAULT_WORD IND1V, UNUSED_VECTOR
    DEFAULT_WORD IND2V, UNUSED_VECTOR
    DEFAULT_WORD IND3V, UNUSED_VECTOR

;; The OS variables' defaults, for &0236-&028C, the tail of <DEFAULT_VECTORS>.
;;
;; The locations the MOS does not use (OSBYTE &EE-&F0 and &FA-&FB) are zero. <OVERFLOW_BYTE>, the default for
;; <USER_VIA_IRQ_MASK>, is also the byte that BIT uses to set overflow.
;; See: <DEFAULT_VECTORS>
OS_VARIABLE_DEFAULTS:
    DEFAULT_WORD OS_VARIABLES_ADDRESS, OS_VARIABLES
    DEFAULT_WORD EXTENDED_VECTORS_ADDRESS, EXTENDED_VECTORS
    DEFAULT_WORD ROM_TABLE_ADDRESS, ROM_TYPE_TABLE
    DEFAULT_WORD KEY_TABLE_ADDRESS, KEY_TABLE
    DEFAULT_WORD VDU_VARIABLES_ADDRESS, GRAPHICS_WINDOW ; the VDU variables begin with the graphics window
    DEFAULT_BYTE CFS_TIMEOUT, $00
    DEFAULT_BYTE INPUT_SOURCE, $00              ; the keyboard
    DEFAULT_BYTE KEYBOARD_SEMAPHORE, $FF
    DEFAULT_BYTE PRIMARY_OSHWM, $00             ; set later in reset, after the workspace claims
    DEFAULT_BYTE OSHWM, $00
    DEFAULT_BYTE RS423_MODE, $01
    DEFAULT_BYTE FONT_EXPLOSION, $00
    DEFAULT_BYTE CFS_RFS_SWITCH, $00            ; the cassette filing system
    DEFAULT_BYTE VIDEO_ULA_CONTROL_COPY, $00
    DEFAULT_BYTE VIDEO_ULA_PALETTE_COPY, $00
    DEFAULT_BYTE BRK_ROM, $00
    DEFAULT_BYTE BASIC_ROM, $FF                 ; none until the ROM survey finds BASIC
    DEFAULT_BYTE ADC_CHANNEL, $04
    DEFAULT_BYTE ADC_MAX_CHANNEL, $04
    DEFAULT_BYTE ADC_CONVERSION, $00            ; the default, 12 bits
    DEFAULT_BYTE RS423_BUSY, $FF                ; RS-423 free
    DEFAULT_BYTE ACIA_CONTROL_COPY, $56         ; divide by 64, 8 data bits, no parity, 1 stop bit, RTS high
    DEFAULT_BYTE FLASH_COUNTER, 25
    DEFAULT_BYTE MARK_PERIOD, 25                ; half a second
    DEFAULT_BYTE SPACE_PERIOD, 25
    DEFAULT_BYTE AUTO_REPEAT_DELAY, 50          ; half a second
    DEFAULT_BYTE AUTO_REPEAT_PERIOD, 8
    DEFAULT_BYTE EXEC_HANDLE, $00
    DEFAULT_BYTE SPOOL_HANDLE, $00
    DEFAULT_BYTE ESCAPE_BREAK_EFFECT, $00
    DEFAULT_BYTE KEYBOARD_DISABLE, $00
    DEFAULT_BYTE KEYBOARD_STATUS, %00100000     ; SHIFT LOCK off, CAPS LOCK on
    DEFAULT_BYTE RS423_HANDSHAKE, 9
    DEFAULT_BYTE RS423_SUPPRESS, $00
    DEFAULT_BYTE CASSETTE_RS423_SELECT, $00
    DEFAULT_BYTE ECONET_OS_INTERCEPT, $00
    DEFAULT_BYTE ECONET_RDCH_INTERCEPT, $00
    DEFAULT_BYTE ECONET_WRCH_INTERCEPT, $00
    DEFAULT_BYTE SPEECH_SUPPRESS, $50           ; the speech processor's SPEAK command: speech allowed
    DEFAULT_BYTE SOUND_SUPPRESS, $00
    DEFAULT_BYTE BELL_CHANNEL, 3
    DEFAULT_BYTE BELL_AMPLITUDE, $90
    DEFAULT_BYTE BELL_PITCH, 100
    DEFAULT_BYTE BELL_DURATION, 6
    DEFAULT_BYTE STARTUP_MESSAGE_BOOT, %10000001 ; the start-up message shown, bit 0 set
    DEFAULT_BYTE SOFT_KEY_LENGTH, $00
    DEFAULT_BYTE PAGED_LINES, $00
    DEFAULT_BYTE VDU_QUEUE_COUNT, $00
    DEFAULT_BYTE TAB_CHARACTER, $09
    DEFAULT_BYTE ESCAPE_CHARACTER, $1B
    DEFAULT_BYTE INPUT_INTERPRETATION + 0, $01  ; &C0-&CF: the soft keys
    DEFAULT_BYTE INPUT_INTERPRETATION + 1, $D0  ; &D0-&DF, &E0-&EF and &F0-&FF: themselves
    DEFAULT_BYTE INPUT_INTERPRETATION + 2, $E0
    DEFAULT_BYTE INPUT_INTERPRETATION + 3, $F0
    DEFAULT_BYTE FUNCTION_KEY_STATUS + 0, $01   ; &80-&8F: the soft keys
    DEFAULT_BYTE FUNCTION_KEY_STATUS + 1, $80
    DEFAULT_BYTE FUNCTION_KEY_STATUS + 2, $90
    DEFAULT_BYTE FUNCTION_KEY_STATUS + 3, $00   ; &B0-&BF: ignored
    DEFAULT_BYTE ESCAPE_KEY_STATUS, $00
    DEFAULT_BYTE ESCAPE_EFFECTS, $00

;; The default for <USER_VIA_IRQ_MASK>, &FF, which is also the byte that `BIT OVERFLOW_BYTE` tests to set the
;; overflow flag (and negative) without changing a register.
OVERFLOW_BYTE:
    DEFAULT_BYTE USER_VIA_IRQ_MASK, $FF
    DEFAULT_BYTE ACIA_IRQ_MASK, $FF
    DEFAULT_BYTE SYS_VIA_IRQ_MASK, $FF
    DEFAULT_BYTE TUBE_PRESENT, $00
    DEFAULT_BYTE SPEECH_PRESENT, $00
    DEFAULT_BYTE WRCH_DESTINATION, $00
    DEFAULT_BYTE CURSOR_EDITING, $00            ; the end of what a soft BREAK restores
    DEFAULT_BYTE CURSOR_EDITING + 1, $00        ; &027E-&0280 (OSBYTE &EE-&F0), not used by the MOS
    DEFAULT_BYTE CURSOR_EDITING + 2, $00
    DEFAULT_BYTE CURSOR_EDITING + 3, $00
    DEFAULT_BYTE USER_FLAG, $00
    DEFAULT_BYTE SERIAL_ULA_COPY, $64           ; RS-423 selected, the cassette motor off
    DEFAULT_BYTE TIMER_SWITCH, 5
    DEFAULT_BYTE SOFT_KEY_CONSISTENCY, $FF      ; makes reset clear the soft keys
    DEFAULT_BYTE PRINTER_DESTINATION, PRINTER_TYPE_PARALLEL
    DEFAULT_BYTE PRINTER_IGNORE, $0A            ; line feed; the end of what a hard BREAK restores
    DEFAULT_BYTE BREAK_INTERCEPT + 0, $00       ; not a JMP, so no intercept
    DEFAULT_BYTE BREAK_INTERCEPT + 1, $00
    DEFAULT_BYTE BREAK_INTERCEPT + 2, $00
    DEFAULT_BYTE BREAK_INTERCEPT + 3, $00       ; &028A-&028B (OSBYTE &FA-&FB), not used by the MOS
    DEFAULT_BYTE BREAK_INTERCEPT + 4, $00
    DEFAULT_BYTE LANGUAGE_ROM, $FF              ; none
    .assert * - DEFAULT_VECTORS = DEFAULTS_POWER_ON, "DEFAULT_VECTORS ends at LANGUAGE_ROM."

; ---------------------------------------------------------------------------------------------------------------------
; Reset
; ---------------------------------------------------------------------------------------------------------------------

;; Starts the machine on power on and on BREAK, where the 6502's reset vector points, and enters a language.
;;
;; The BREAK key resets the 6502 and the user VIA but not the system VIA, so the system VIA's interrupt enable
;; register tells the two apart: it reads &80 after power on, as its bit 7 always reads set, and shifted left past
;; that bit it is zero only then. A BREAK with CTRL held is a hard BREAK and one without is a soft BREAK; OSBYTE &FD
;; reads which it was from <LAST_BREAK> (1 power on, 2 hard, 0 soft). In order, reset:
;;
;; - On power on, or on any BREAK once OSBYTE &C8 has set bit 1 of <ESCAPE_BREAK_EFFECT> (with bits 2-7 clear),
;;   clears memory from &0400 up and finds the top of RAM: on a 16K machine &4000 up is a copy of &0000 up, so the
;;   clearing stops when a write to &4001 clears &0001.
;; - Reads the startup option links and CTRL from the keyboard. Power on and a hard BREAK store the links in
;;   <STARTUP_OPTIONS>.
;; - Clears page two from &0290 (from the interval timer, &029C, on a soft BREAK), setting &02CE-&02FF to &FF, and
;;   clears &E2-&FF; then restores the vectors and OS variables from <DEFAULT_VECTORS>, as much as the reset calls
;;   for.
;; - Sets up the VIAs, the 100 Hz timer, the 6850 and the serial ULA, silences the sound generator, and clears the
;;   soft keys if they were left inconsistent.
;; - Surveys the paged ROMs into <ROM_TYPE_TABLE> and notes BASIC in <BASIC_ROM>, then looks for a speech
;;   processor.
;; - Starts the VDU driver in the mode the links select, puts the BREAK key's soft key code in the keyboard buffer,
;;   makes the first BREAK intercept call, selects the cassette filing system, and looks for a Tube.
;; - Offers the paged ROMs service calls &01 and &02 to place their workspace, which sets OSHWM, then &FE.
;; - Prints the banner, makes the second BREAK intercept call, and offers service call &03, auto-boot, with Y = 0
;;   when SHIFT is held (or not held, when the links reverse SHIFT+BREAK). When no ROM takes it, a boot selects the
;;   ROM filing system and runs !BOOT, and otherwise reset selects the cassette filing system.
;; - Re-enters the current language after a soft BREAK, and otherwise the highest-numbered ROM that is a language.
;;   With none, and no Tube, it stops with error &F9, "Language?".
;;
;; Entry:
;;   RESET_SELECT_TAPE = selects the cassette filing system and enters a language; <BRKV_DEFAULT> goes here after
;;     printing an error
;; See: <DEFAULT_VECTORS>, <ENTER_LANGUAGE>, <LAST_BREAK>, <STARTUP_OPTIONS>, <BREAK_INTERCEPT>
RESET:
    lda #OPCODE_RTI                 ; an NMI returns at once until a filing system claims it
    sta NMI_ROUTINE
    sei
    cld
    ldx #$FF
    txs
    lda SYS_VIA_IER                 ; &80 after power on: bit 7 always reads set, and shifting it out leaves zero
    asl a
    pha                             ; kept for telling power on from BREAK below
    beq RESET_CLEAR_MEMORY
    lda ESCAPE_BREAK_EFFECT
    lsr a
    cmp #$01                        ; OSBYTE &C8 with 2 or 3: BREAK clears memory as power on does
    bne RESET_HARDWARE
    lsr a                           ; A = 0, to clear with
RESET_CLEAR_MEMORY:
    ldx #$04                        ; from &0400, with X counting the pages
    stx $01
    sta $00
    tay
RESET_CLEAR_MEMORY_LOOP:
    sta ($00),y
    cmp $01                         ; the pointer's own high byte cleared: the write reached &0001 through &4001
    beq RESET_MEMORY_SIZED
    iny
    bne RESET_CLEAR_MEMORY_LOOP
    iny                             ; Y goes on from 1, so the first byte of each later page is not cleared
    inx
    inc $01
    bpl RESET_CLEAR_MEMORY_LOOP     ; up to &7FFF on a 32K machine
RESET_MEMORY_SIZED:
    stx AVAILABLE_RAM               ; &40 for 16K, &80 for 32K
    stx SOFT_KEY_CONSISTENCY        ; nonzero, so the soft keys are cleared below

; Read the startup option links and CTRL, keys 9 down to 1 on the keyboard's first row.
RESET_HARDWARE:
    ldx #$0F                        ; port B bits 0-3 drive the addressable latch
    stx SYS_VIA_DDRB
RESET_LATCH_LOOP:
    dex
    stx SYS_VIA_ORB                 ; sets latch bits 6 down to 0 high, ending with the sound chip's write enable
    cpx #$09
    bcs RESET_LATCH_LOOP
    inx                             ; X = 9
RESET_LINKS_LOOP:
    txa
    jsr TEST_KEY                       ; reads key X: bit 7 of X set when it is pressed
    cpx #$80
    ror IRQ_A                       ; nine keys through eight bits: key 9 ends in carry
    tax
    dex
    bne RESET_LINKS_LOOP
    stx LAST_BREAK                  ; 0, a soft BREAK, until shown otherwise
    rol IRQ_A                       ; carry = CTRL; IRQ_A holds links 2-9 in bits 7-0
    jsr SET_KEYBOARD_LEDS                       ; the keyboard lights; returns the flags it was called with in A
    ror a                           ; carry = CTRL again, from those flags' bit 0
    ldx #<(INTERVAL_TIMER - USERV)  ; a soft BREAK clears page two from the interval timer
    ldy #DEFAULTS_POWER_ON
    pla
    beq RESET_POWER_ON
    ldy #DEFAULTS_SOFT_BREAK
    bcc RESET_CLEAR_PAGE_TWO        ; BREAK without CTRL: a soft BREAK
    ldy #DEFAULTS_HARD_BREAK
    inc LAST_BREAK                  ; 2, a hard BREAK
RESET_POWER_ON:
    inc LAST_BREAK                  ; 1, power on
    lda IRQ_A
    eor #$FF                        ; a fitted link reads as a pressed key, and gives a clear bit
    sta STARTUP_OPTIONS
    ldx #<(TV_VERTICAL_ADJUST - USERV)  ; power on and a hard BREAK clear it from &0290
RESET_CLEAR_PAGE_TWO:
    lda #$00
RESET_CLEAR_PAGE_TWO_LOOP:
    cpx #<(SOUND_SEMAPHORE - USERV) ; the semaphore and the buffer, CFS and OSFILE workspace start as &FF
    bcc RESET_CLEAR_PAGE_TWO_STORE
    lda #$FF
RESET_CLEAR_PAGE_TWO_STORE:
    sta USERV,x
    inx
    bne RESET_CLEAR_PAGE_TWO_LOOP
    sta USER_VIA_DDRA               ; &FF: the printer port is all outputs
    txa
    ldx #CFS_STATUS
RESET_CLEAR_ZERO_PAGE:
    sta $00,x                       ; clears &E2-&FF
    inx
    bne RESET_CLEAR_ZERO_PAGE
RESET_COPY_DEFAULTS:
    lda DEFAULT_VECTORS - 1,y
    sta USERV - 1,y
    dey
    bne RESET_COPY_DEFAULTS
    lda #RESET_FIRST_KEY
    sta FIRST_KEY_PRESSED
    jsr RESTORE_ACIA                       ; resets the 6850 and restores its control register
    lda #VIA_FLAGS_ALL
    inx                             ; X = 1: each VIA's IER, then X = 0: its IFR
RESET_DISABLE_VIAS:
    sta SYS_VIA_IFR,x               ; disables every interrupt, then clears every flag
    sta USER_VIA_IFR,x
    dex
    bpl RESET_DISABLE_VIAS
    cli                             ; lets an interrupt still pending from elsewhere be taken
    sei
    bit IRQ_A
    bvc RESET_SET_UP_VIAS
    jsr CALL_JIM_VECTOR                       ; an interrupt in the CLI-SEI window left &7F in IRQ_A: JIM's turn
RESET_SET_UP_VIAS:
    ldx #RESET_SYS_VIA_IER
    stx SYS_VIA_IER
    ldx #RESET_SYS_VIA_PCR
    stx SYS_VIA_PCR
    lda #RESET_SYS_VIA_ACR
    sta SYS_VIA_ACR
    lda #<TIMER_100HZ_LATCH         ; also the user VIA's PCR and an ADC command
    .assert <TIMER_100HZ_LATCH = RESET_USER_VIA_PCR, "One value sets timer 1, the user VIA and the ADC."
    .assert <TIMER_100HZ_LATCH = RESET_ADC_COMMAND, "One value sets timer 1, the user VIA and the ADC."
    sta SYS_VIA_T1LL
    sta USER_VIA_PCR
    sta ADC_COMMAND
    cmp USER_VIA_PCR
    beq RESET_START_TIMER
    inc USER_VIA_IRQ_MASK           ; no user VIA answers: &FF becomes 0, so the MOS ignores its interrupts
RESET_START_TIMER:
    lda #>TIMER_100HZ_LATCH
    sta SYS_VIA_T1LH
    sta SYS_VIA_T1CH                ; starts timer 1
    jsr RESET_SOUND                       ; silences the sound generator
    lda SERIAL_ULA_COPY
    and #$7F                        ; the cassette motor off
    jsr WRITE_SERIAL_ULA                       ; writes the serial ULA and its copy; returns X = Y = 0
    ldx SOFT_KEY_CONSISTENCY
    beq RESET_SURVEY_ROMS
    jsr RESET_SOFT_KEYS                       ; clears the soft keys; returns X = 0

; Survey the paged ROMs, X from 0 to 15. A ROM counts when it has a copyright string; a ROM whose first kilobyte is
; the same as a higher-numbered socket's is taken for a copy of it and left out.
RESET_SURVEY_ROMS:
    jsr SELECT_ROM
    ldx #$03
    ldy COPYRIGHT_OFFSET
RESET_CHECK_COPYRIGHT:
    lda LANGUAGE_ENTRY,y            ; the zero and "(C)", compared from the zero
    cmp COPYRIGHT_SIGNATURE,x
    bne RESET_SKIP_ROM
    iny
    dex
    bpl RESET_CHECK_COPYRIGHT
    ldx ROMSEL_COPY
    ldy ROMSEL_COPY
RESET_FIND_COPY:
    iny
    cpy #$10
    bcs RESET_RECORD_ROM
    tya                             ; the pointer is &7F00 + (&FF - Y), so (pointer),Y starts at &7FFF
    eor #$FF
    sta OS_SCRATCH
    lda #$7F
    sta OS_SCRATCH+1
RESET_COMPARE_ROMS:
    sty ROMSEL                      ; ROMSEL alone: ROMSEL_COPY stays X
    lda (OS_SCRATCH),y
    stx ROMSEL
    cmp (OS_SCRATCH),y
    bne RESET_FIND_COPY
    inc OS_SCRATCH
    bne RESET_COMPARE_ROMS
    inc OS_SCRATCH+1
    lda OS_SCRATCH+1
    cmp #$84                        ; up to &83FF + Y
    bcc RESET_COMPARE_ROMS
RESET_SKIP_ROM:
    ldx ROMSEL_COPY
    bpl RESET_NEXT_ROM              ; always taken
RESET_RECORD_ROM:
    lda ROM_TYPE
    sta ROM_TYPE_TABLE,x
    and #$8F                        ; no service entry and processor type 0: BASIC
    bne RESET_NEXT_ROM
    stx BASIC_ROM
RESET_NEXT_ROM:
    inx
    cpx #$10
    bcc RESET_SURVEY_ROMS

; A speech processor holds PB7 low.
    bit SYS_VIA_ORB
    bmi RESET_START_VDU
    dec SPEECH_PRESENT              ; &FF
RESET_SPEECH_LOOP:
    ldy #$FF                        ; sixteen &FF bytes, X counting down from 16
    jsr WRITE_SPEECH                       ; writes Y to the speech processor
    dex
    bne RESET_SPEECH_LOOP
    stx SYS_VIA_T2CL                ; timer 2 counts the speech processor's interrupts from 0
    stx SYS_VIA_T2CH
RESET_START_VDU:
    lda STARTUP_OPTIONS             ; bits 0-2, the mode
    jsr INITIALIZE_VDU                       ; starts the VDU driver
    ldy #BREAK_KEY_CODE
    jsr INSERT_KEY                       ; puts Y in the keyboard buffer
    jsr CALL_BREAK_INTERCEPT                       ; the BREAK intercept's first call
    jsr RESET_TAPE_OPTIONS                       ; selects the cassette filing system
    lda #TUBE_TEST_FLAGS
    sta TUBE_R1_STATUS
    lda TUBE_R1_STATUS
    ror a
    bcc RESET_CLAIM_WORKSPACE       ; bit 0 did not stay set: no Tube
    ldx #SERVICE_TUBE_MAIN_INIT
    jsr ISSUE_SERVICE_CALL                       ; offers service call X; returns zero when a ROM took it
    bne RESET_CLAIM_WORKSPACE
    dec TUBE_PRESENT                ; &FF
RESET_CLAIM_WORKSPACE:
    ldy #>$0E00                     ; absolute workspace starts at &0E00
    ldx #SERVICE_ABSOLUTE_WORKSPACE
    jsr ISSUE_SERVICE_CALL
    ldx #SERVICE_PRIVATE_WORKSPACE  ; private workspace from the top of the absolute workspace
    jsr ISSUE_SERVICE_CALL
    sty PRIMARY_OSHWM
    sty OSHWM
    ldx #SERVICE_TUBE_POST_INIT
    ldy TUBE_PRESENT
    jsr ISSUE_SERVICE_CALL                       ; A = 0 when a ROM took it, which hides the banner
    and STARTUP_MESSAGE_BOOT
    bpl RESET_AUTO_BOOT
    ldy #<(BANNER_TITLE - 1)
    jsr PRINT_BANNER_TEXT
    lda LAST_BREAK
    beq RESET_END_BANNER            ; a soft BREAK leaves the memory size out
    ldy #<(BANNER_32K - 1)
    bit AVAILABLE_RAM
    bmi RESET_PRINT_MEMORY
    ldy #<(BANNER_16K - 1)
RESET_PRINT_MEMORY:
    jsr PRINT_BANNER_TEXT
RESET_END_BANNER:
    ldy #<(BANNER_END - 1)
    jsr PRINT_BANNER_TEXT
RESET_AUTO_BOOT:
    sec
    jsr CALL_BREAK_INTERCEPT                       ; the BREAK intercept's second call
    jsr REFLECT_KEYBOARD_STATUS                       ; OSBYTE &76; returns negative = SHIFT held
    php
    pla
    lsr a                           ; the negative flag to bit 3
    lsr a
    lsr a
    lsr a
    eor STARTUP_OPTIONS             ; bit 3 clear reverses SHIFT+BREAK
    and #$08
    tay                             ; 0 to boot, 8 not to
    ldx #SERVICE_AUTO_BOOT
    jsr ISSUE_SERVICE_CALL
    beq RESET_CHOOSE_LANGUAGE       ; a filing system ROM took it
    tya
    bne RESET_SELECT_TAPE
    lda #$8D                        ; OSBYTE &8D, *ROM
    jsr SELECT_TAPE_OR_ROM
    ldx #<BOOT_COMMAND
    ldy #>BOOT_COMMAND
    dec STARTUP_MESSAGE_BOOT        ; flips bit 0 while !BOOT runs (see BRKV_DEFAULT)
    jsr OSCLI
    inc STARTUP_MESSAGE_BOOT
    bne RESET_CHOOSE_LANGUAGE       ; always taken
RESET_SELECT_TAPE:
    lda #$00                        ; OSBYTE &8C, *TAPE, with X = 0
    tax
    jsr SELECT_TAPE_OR_ROM_1
RESET_CHOOSE_LANGUAGE:
    lda LAST_BREAK
    bne RESET_FIND_LANGUAGE
    ldx LANGUAGE_ROM                ; a soft BREAK re-enters the current language
    bpl RESET_ENTER_LANGUAGE
RESET_FIND_LANGUAGE:
    ldx #$0F
RESET_FIND_LANGUAGE_LOOP:
    lda ROM_TYPE_TABLE,x
    rol a                           ; bit 6, a language entry, to negative
    bmi RESET_ENTER_LANGUAGE
    dex
    bpl RESET_FIND_LANGUAGE_LOOP
    lda #$00                        ; no language: A = 0 tells the Tube so
    bit TUBE_PRESENT
    bmi ENTER_LANGUAGE_TUBE
    brk
    .byte ERROR_NO_LANGUAGE, "Language?", 0
RESET_ENTER_LANGUAGE:
    clc
    ; Falls into ENTER_LANGUAGE.

;; OSBYTE &8E: enters the language in a paged ROM, printing its title, or passes it to the Tube.
;;
;; It records the ROM in <LANGUAGE_ROM>, so that a soft BREAK and a BRK re-enter it, selects it, prints its title,
;; and leaves <ERROR_POINTER> on the zero after the title: the zero before the version string, or before the
;; copyright string when there is none. Then it enters the ROM at &8000 with A = 1, or the Tube host code with A = 1
;; when a Tube is fitted. *BASIC comes here with carry set, reset with carry clear; the carry is passed on.
;; In: X = the ROM, carry = passed to the language
;; Entry:
;;   ENTER_LANGUAGE_TUBE = enters the Tube host code with A as given
;; See: <RESET>, <LANGUAGE_ENTRY>, <TUBE_CODE>
ENTER_LANGUAGE:
    php
    stx LANGUAGE_ROM
    jsr SELECT_ROM
    lda #>ROM_TITLE
    ldy #<(ROM_TITLE - 1)
    jsr PRINT_TEXT_IN_PAGE          ; returns Y on the title's zero
    sty ERROR_POINTER
    jsr OSNEWL
    jsr OSNEWL
    plp
    lda #$01                        ; a normal language start
    bit TUBE_PRESENT
    bmi ENTER_LANGUAGE_TUBE
    jmp LANGUAGE_ENTRY
ENTER_LANGUAGE_TUBE:
    jmp TUBE_CODE

; ---------------------------------------------------------------------------------------------------------------------
; Paged ROMs
; ---------------------------------------------------------------------------------------------------------------------

;; OSRDRM: reads a byte from a paged ROM, then selects the ROM that was selected before.
;; In: Y = the ROM, ROM_POINTER = the address in it
;; Out: A = the byte
;; Uses: X, Y
;; See: <OSRDRM>, <SELECT_ROM>
OSRDRM_HANDLER:
    ldx ROMSEL_COPY
    sty ROMSEL_COPY
    sty ROMSEL
    ldy #$00
    lda (ROM_POINTER),y
    ; Falls into SELECT_ROM.

;; Selects a paged ROM, in the ROM select latch and in its copy.
;; In: X = the ROM
;; Keeps: A, X, Y
;; See: <ROMSEL>, <ROMSEL_COPY>
SELECT_ROM:
    stx ROMSEL_COPY
    stx ROMSEL
    rts

; ---------------------------------------------------------------------------------------------------------------------
; BRK and the interrupts
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a BRK or an interrupt, where the 6502's IRQ/BRK vector points.
;;
;; An interrupt goes to <IRQ1V>, with A in <IRQ_A> and nothing else saved. A BRK sets <ERROR_POINTER> to the byte
;; after the BRK, the error number, records the ROM selected in <BRK_ROM> and the stack pointer in <OS_X>, offers the
;; paged ROMs service call &06, selects the current language's ROM again, and goes to <BRKV> with interrupts enabled
;; and A and X as they were at the BRK.
;; In: A = as the interrupted code left it
;; See: <BRKV_DEFAULT>, <IRQ1V_DEFAULT>
IRQ_ENTRY:
    sta IRQ_A
    pla
    pha
    and #$10                        ; the B flag in the stacked P: a BRK
    bne IRQ_ENTRY_BRK
    jmp (IRQ1V)
IRQ_ENTRY_BRK:
    txa
    pha
    tsx
    lda STACK+3,x                   ; the return address, which is two bytes after the BRK
    cld
    sec
    sbc #$01
    sta ERROR_POINTER
    lda STACK+4,x
    sbc #$00
    sta ERROR_POINTER+1
    lda ROMSEL_COPY
    sta BRK_ROM
    stx OS_X
    ldx #SERVICE_BRK
    jsr ISSUE_SERVICE_CALL
    ldx LANGUAGE_ROM
    jsr SELECT_ROM
    pla
    tax
    lda IRQ_A
    cli
    jmp (BRKV)

;; The MOS's BRK handler, for when no language has claimed <BRKV>: prints the error message and enters a language
;; again.
;;
;; When bit 0 of <STARTUP_MESSAGE_BOOT> is set it locks up instead, after printing. Reset clears that bit while it
;; runs a ROM filing system !BOOT, so with the default an error there carries on, and an error with no language
;; anywhere else stops the machine.
;; In: ERROR_POINTER = the error number, followed by the message and a zero
;; See: <IRQ_ENTRY>, <RESET>
BRKV_DEFAULT:
    ldy #$00
    jsr PRINT_TEXT                  ; the message, after the error number
    lda STARTUP_MESSAGE_BOOT
    ror a
BRKV_DEFAULT_LOCK:
    bcs BRKV_DEFAULT_LOCK
    jsr OSNEWL
    jsr OSNEWL
    jmp RESET_SELECT_TAPE

;; Part of <IRQ1V_DEFAULT>: the 6850 can transmit but RS-423 has nothing to send, so stops transmitting.
;;
;; It marks RS-423 free in <RS423_BUSY>, then writes the 6850's control register with the transmit interrupt off,
;; and with RTS high, holding off input, when receive interrupts are off or the input buffer is nearly full, and RTS
;; low otherwise.
;; Entry:
;;   IRQ_RS423_RTS_HIGH = sets RTS high
;;   IRQ_RS423_SET_RTS = sets the control register's transmit bits to X
;; See: <IRQ_RS423_RECEIVE>, <RS423_HANDSHAKE>
IRQ_RS423_IDLE:
    sec
    ror RS423_BUSY                  ; bit 7 set: free
    bit ACIA_CONTROL_COPY
    bpl IRQ_RS423_RTS_HIGH          ; receive interrupts off
    jsr CHECK_RS423_INPUT_ROOM                       ; carry = set while the input buffer has room
    ldx #ACIA_RTS_LOW
    bcs IRQ_RS423_SET_RTS
IRQ_RS423_RTS_HIGH:
    ldx #ACIA_RTS_HIGH
IRQ_RS423_SET_RTS:
    jmp SET_ACIA_TRANSMIT_CONTROL

;; Part of <IRQ1V_DEFAULT>: takes a character RS-423 has received.
;;
;; A receive error raises event 7 instead. A character is dropped while <RS423_SUPPRESS> is nonzero, and otherwise
;; goes into the RS-423 input buffer (which may make it an escape), and RTS goes high if the buffer is now nearly
;; full.
;; In: A = the 6850's status, masked by ACIA_IRQ_MASK and shifted right one
;; See: <IRQ_RS423_IDLE>, <RS423_HANDSHAKE>
IRQ_RS423_RECEIVE:
    ldy ACIA_DATA
    and #ACIA_RECEIVE_ERRORS
    bne IRQ_RS423_ERROR
    ldx RS423_SUPPRESS
    bne IRQ_RS423_RECEIVE_DONE
    inx                             ; X = 1, the RS-423 input buffer
    .assert RS423_INPUT_BUFFER_ID = 1, "The RS-423 input buffer is 1."
    jsr INSERT_INPUT_CHARACTER                       ; puts Y in buffer X
    jsr CHECK_RS423_INPUT_ROOM
    bcc IRQ_RS423_RTS_HIGH
IRQ_RS423_RECEIVE_DONE:
    rts

;; The MOS's interrupt handler, where <IRQ1V> points: finds which device interrupted and services it.
;;
;; It saves A, X and Y on the stack and pushes the address of <IRQ1V_EXIT>, so that each device's code ends with an
;; RTS that restores them and returns from the interrupt. It looks at the devices in this order, servicing the first
;; whose interrupt it finds and whose bit the masks in <ACIA_IRQ_MASK>, <SYS_VIA_IRQ_MASK> and <USER_VIA_IRQ_MASK>
;; allow:
;;
;; - The 6850: for the cassette filing system, the cassette code; for RS-423, a received character, a lost carrier
;;   (event 7), or the next character to send from the RS-423 output buffer or, for a serial printer, the printer
;;   buffer.
;; - The system VIA: vertical sync (the CFS and RS-423 timeouts, the flashing colours, event 4); timer 2, the speech
;;   processor; timer 1, the 100 Hz tick; CB1, the end of an ADC conversion; and CA2, a key pressed.
;; - The user VIA: CA1, the parallel printer's acknowledge, which sends it the next character.
;;
;; An interrupt it does not recognize goes to the paged ROMs as service call &05, and then, if none takes it, to
;; <IRQ2V> with the registers restored.
;;
;; The 100 Hz tick updates the clock and the interval timer (event 5), counts down the INKEY timer, runs the sound
;; system's envelopes with interrupts enabled, feeds the speech processor, polls the 6850 and the printer, runs the
;; keyboard's timer entry, and picks up an ADC conversion that has finished.
;;
;; Entry:
;;   IRQ1V_ACIA = services the 6850; the 100 Hz tick calls it with overflow set to poll RS-423, which skips the
;;     receive interrupt, and it returns
;; See: <IRQ_ENTRY>, <IRQ2V_DEFAULT>, <FEED_SPEECH>, <START_ADC_CHANNEL>
IRQ1V_DEFAULT:
    cld
    lda IRQ_A
    pha
    txa
    pha
    tya
    pha
    lda #>(IRQ1V_EXIT - 1)          ; an RTS from here on returns from the interrupt
    pha
    lda #<(IRQ1V_EXIT - 1)
    pha
    clv
IRQ1V_ACIA:
    lda ACIA_STATUS
    bvs IRQ1V_ACIA_OWNER            ; polling
    bpl IRQ1V_SYSTEM_VIA            ; bit 7 clear: not the 6850
IRQ1V_ACIA_OWNER:
    ldx RS423_TIMEOUT
    dex
    bmi IRQ_RS423                   ; RS-423 has the 6850
    bvs IRQ1V_RETURN
    jmp CASSETTE_INTERRUPT                       ; the cassette filing system's interrupt
IRQ_RS423_CARRIER:
    ldy ACIA_DATA                   ; reading the data clears the interrupt
    rol a                           ; the status shifted right one again, as event 7 takes it
    asl a
IRQ_RS423_ERROR:
    tax                             ; X = the status, A = the character
    tya
    ldy #EVENT_RS423_ERROR
    jmp OSEVEN_HANDLER
IRQ_RS423_TRANSMIT:
    ldx #RS423_OUTPUT_BUFFER_ID
    jsr REMOVE_FROM_BUFFER                       ; takes a byte from buffer X; carry = set when it is empty
    bcc IRQ_RS423_SEND
    lda PRINTER_DESTINATION
    cmp #PRINTER_TYPE_SERIAL
    bne IRQ_RS423_IDLE
    inx                             ; the printer buffer
    .assert PRINTER_BUFFER_ID = RS423_OUTPUT_BUFFER_ID + 1, "The printer buffer follows RS-423's."
    jsr REMOVE_FROM_BUFFER
    ror BUFFER_BUSY + PRINTER_BUFFER_ID ; bit 7 set when it is empty
    bmi IRQ_RS423_IDLE
IRQ_RS423_SEND:
    sta ACIA_DATA
    lda #RS423_TIMEOUT_START
    sta RS423_TIMEOUT
IRQ1V_RETURN:
    rts
IRQ_RS423:
    and ACIA_IRQ_MASK
    lsr a                           ; carry = receive data full
    bcc IRQ_RS423_NOT_RECEIVE
    bvs IRQ_RS423_NOT_RECEIVE       ; polling
    ldy ACIA_CONTROL_COPY
    bmi IRQ_RS423_RECEIVE           ; receive interrupts on
IRQ_RS423_NOT_RECEIVE:
    lsr a                           ; transmit data empty to bit 7, carrier lost to carry
    ror a
    bcs IRQ_RS423_CARRIER
    bmi IRQ_RS423_TRANSMIT
    bvs IRQ1V_RETURN                ; polling
IRQ1V_UNRECOGNISED:
    ldx #SERVICE_UNRECOGNISED_IRQ
    jsr ISSUE_SERVICE_CALL
    beq IRQ1V_RETURN                ; a ROM took it
    pla                             ; drops the address of IRQ1V_EXIT
    pla
    pla
    tay
    pla
    tax
    pla
    sta IRQ_A
    jmp (IRQ2V)
IRQ1V_SYSTEM_VIA:
    lda SYS_VIA_IFR
    bpl IRQ1V_USER_VIA
    and SYS_VIA_IRQ_MASK
    and SYS_VIA_IER
    ror a
    ror a                           ; carry = CA1, vertical sync
    bcc IRQ1V_NOT_VSYNC
    dec CFS_TIMEOUT
    lda RS423_TIMEOUT
    bpl IRQ1V_FLASH
    inc RS423_TIMEOUT
IRQ1V_FLASH:
    lda FLASH_COUNTER
    beq IRQ1V_VSYNC_EVENT           ; not flashing
    dec FLASH_COUNTER
    bne IRQ1V_VSYNC_EVENT
    ldx MARK_PERIOD                 ; the count for the colours it changes to: the mark period when bit 0 was clear
    lda VIDEO_ULA_CONTROL_COPY
    lsr a
    bcc IRQ1V_FLASH_TOGGLE
    ldx SPACE_PERIOD
IRQ1V_FLASH_TOGGLE:
    rol a
    eor #$01                        ; the video ULA's flash bit
    jsr SET_VIDEO_ULA_CONTROL                       ; writes the video ULA's control register and its copy
    stx FLASH_COUNTER
IRQ1V_VSYNC_EVENT:
    ldy #EVENT_VSYNC
    jsr OSEVEN_HANDLER
    lda #VIA_FLAG_CA1
    jmp IRQ1V_CLEAR_FLAG
IRQ1V_USER_VIA:
    lda USER_VIA_IFR
    bpl IRQ1V_UNRECOGNISED
    and USER_VIA_IRQ_MASK
    and USER_VIA_IER
    ror a
    ror a                           ; carry = CA1, the printer's acknowledge
    bcc IRQ1V_UNRECOGNISED
    ldy PRINTER_DESTINATION
    dey
    .assert PRINTER_TYPE_PARALLEL = 1, "The parallel printer is type 1."
    bne IRQ1V_UNRECOGNISED
    lda #VIA_FLAG_CA1
    sta USER_VIA_IFR                ; clears the flag
    sta USER_VIA_IER                ; and disables the interrupt until the next character
    ldx #PRINTER_BUFFER_ID
    jmp SEND_TO_PRINTER                       ; sends the printer the next character
IRQ1V_NOT_VSYNC:
    rol a                           ; back to the flags as read, then two more:
    rol a                           ; negative = timer 2, carry = timer 1
    rol a
    rol a
    bpl IRQ1V_TIMER1
    lda #VIA_FLAG_T2
    ldx #$00
    sta SYS_VIA_IFR
    stx SYS_VIA_T2CH                ; timer 2 counts from 0 again, so the next pulse on PB6 interrupts
    ; Falls into FEED_SPEECH.

;; Moves commands from the speech buffer to the speech processor, meant to be up to four of them.
;;
;; The pass counter in OS_SCRATCH+1 does not hold: each byte taken from the buffer goes through <POINT_AT_BUFFER>,
;; which leaves the speech buffer's base high byte, &09, there, so the shift after a command leaves 4, never 0. It
;; goes on until the buffer is empty or, for a command from 1 up, the speech processor is talking.
;; Each command in the buffer is three bytes: the command, then an address, high byte first. A command of 0 sends
;; the address's two bytes, low byte first; a command from 1 to &7F waits until the speech processor stops talking,
;; then sends itself and the two bytes. Commands from &80 speak from a PHROM: &80-&BF load the address into
;; it, &C0-&FF double the address (a word number) and look it up, and both then send the command in
;; <SPEECH_SUPPRESS>, normally SPEAK, and stop.
;; Uses: A, X, Y, ROM_FS_ROM, ROM_POINTER, OS_SCRATCH+1
;; See: <SPEECH_BUFFER>, <SPEECH_PRESENT>
FEED_SPEECH:
    ldx #SPEECH_BUFFER_ID           ; also meant as the pass counter, 8, 4, 2, 1; REMV leaves &09 here, so it is not
    .assert SPEECH_BUFFER_ID = 8, "FEED_SPEECH starts its pass counter at the speech buffer's number."
    stx OS_SCRATCH+1
FEED_SPEECH_LOOP:
    jsr EXAMINE_BUFFER                       ; looks at the next byte of buffer X without taking it
    ror BUFFER_BUSY + SPEECH_BUFFER_ID
    bmi FEED_SPEECH_DONE            ; empty
    tay
    beq FEED_SPEECH_COMMAND
    jsr READ_SPEECH                       ; reads the speech processor's status
    bmi FEED_SPEECH_DONE            ; still talking
FEED_SPEECH_COMMAND:
    jsr REMOVE_FROM_BUFFER
    sta ROM_FS_ROM                  ; the command
    jsr REMOVE_FROM_BUFFER
    sta ROM_POINTER+1
    jsr REMOVE_FROM_BUFFER
    sta ROM_POINTER
    ldy ROM_FS_ROM
    beq FEED_SPEECH_BYTES
    bpl FEED_SPEECH_WRITE_COMMAND
    bit ROM_FS_ROM
    bvs FEED_SPEECH_WORD
    jsr PHROM_SET_ADDRESS                       ; loads the address into the PHROM
    bvc FEED_SPEECH_SPEAK           ; always taken
FEED_SPEECH_WORD:
    asl ROM_POINTER
    rol ROM_POINTER+1
    jsr PHROM_FOLLOW_POINTER
FEED_SPEECH_SPEAK:
    ldy SPEECH_SUPPRESS
    jmp WRITE_SPEECH                       ; writes Y to the speech processor
FEED_SPEECH_WRITE_COMMAND:
    jsr WRITE_SPEECH
FEED_SPEECH_BYTES:
    ldy ROM_POINTER
    jsr WRITE_SPEECH
    ldy ROM_POINTER+1
    jsr WRITE_SPEECH
    lsr OS_SCRATCH+1                ; &09 from POINT_AT_BUFFER shifts to 4: never zero after a command
    bne FEED_SPEECH_LOOP
FEED_SPEECH_DONE:
    rts

;; Part of <IRQ1V_DEFAULT>: the system VIA's timer 1, the 100 Hz tick, then its CB1 and CA2 interrupts.
;; In: A = the system VIA's flags shifted, carry = timer 1
;; Entry:
;;   IRQ1V_ADC = reads the finished ADC conversion and starts the next
;;   IRQ1V_CLEAR_FLAG = clears the system VIA's flags in A and returns
IRQ1V_TIMER1:
    bcc IRQ1V_NOT_TIMER1
    lda #VIA_FLAG_T1
    sta SYS_VIA_IFR
    lda TIMER_SWITCH                ; X = the current clock, Y = the other, both counting from the low byte
    tax
    eor #$0F                        ; 5 and 10 swap
    pha
    tay
IRQ1V_CLOCK_LOOP:
    lda CLOCK_A - 1,x               ; the current clock plus one (carry is set) into the other
    adc #$00
    sta CLOCK_A - 1,y
    dex
    beq IRQ1V_CLOCK_DONE
    dey
    bne IRQ1V_CLOCK_LOOP
IRQ1V_CLOCK_DONE:
    pla
    sta TIMER_SWITCH                ; the other copy is current
    ldx #$05
IRQ1V_INTERVAL_LOOP:
    inc INTERVAL_TIMER - 1,x
    bne IRQ1V_INKEY_TIMER
    dex
    bne IRQ1V_INTERVAL_LOOP
    ldy #EVENT_INTERVAL_TIMER
    jsr OSEVEN_HANDLER
IRQ1V_INKEY_TIMER:
    lda INKEY_TIMER                 ; counts down to zero and stops there
    bne IRQ1V_INKEY_LOW
    lda INKEY_TIMER+1
    beq IRQ1V_ENVELOPES
    dec INKEY_TIMER+1
IRQ1V_INKEY_LOW:
    dec INKEY_TIMER
IRQ1V_ENVELOPES:
    bit SOUND_SEMAPHORE
    bpl IRQ1V_POLL_SPEECH           ; an earlier tick is still in the sound system
    inc SOUND_SEMAPHORE             ; 0: busy
    cli
    jsr PROCESS_SOUND                       ; the sound system's tick, with interrupts enabled
    sei
    dec SOUND_SEMAPHORE             ; &FF: free
IRQ1V_POLL_SPEECH:
    bit BUFFER_BUSY + SPEECH_BUFFER_ID
    bmi IRQ1V_POLL_DEVICES
    jsr READ_SPEECH
    eor #%10100000                  ; not talking, or the FIFO low but not empty
    cmp #%01100000
    bcc IRQ1V_POLL_DEVICES
    jsr FEED_SPEECH
IRQ1V_POLL_DEVICES:
    bit OVERFLOW_BYTE
    jsr IRQ1V_ACIA                  ; with overflow set, a poll
    lda LAST_KEY_PRESSED
    ora FIRST_KEY_PRESSED
    and KEYBOARD_SEMAPHORE
    beq IRQ1V_POLL_PRINTER
    sec
    jsr CALL_KEYV_INTERRUPT                       ; KEYV with carry and overflow set: the keyboard's timer entry
IRQ1V_POLL_PRINTER:
    jsr POLL_PRINTER_DRIVER
    bit ADC_STATUS
    bvs IRQ1V_ADC                   ; bit 6 set: the ADC is not busy
    rts
IRQ1V_NOT_TIMER1:
    rol a                           ; negative = CB1, the ADC's end of conversion
    bpl IRQ1V_NOT_ADC
IRQ1V_ADC:
    ldx ADC_CHANNEL                 ; 1-4, or 0 for none
    beq IRQ1V_ADC_DONE
    lda ADC_LOW
    sta ADC_LOW_BYTES - 1,x
    lda ADC_HIGH
    sta ADC_HIGH_BYTES - 1,x
    stx ADC_LAST_CHANNEL
    ldy #EVENT_ADC_COMPLETE
    jsr OSEVEN_HANDLER
    dex                             ; the next channel down, or from the top again
    bne IRQ1V_ADC_NEXT
    ldx ADC_MAX_CHANNEL
IRQ1V_ADC_NEXT:
    jsr START_ADC_CHANNEL
IRQ1V_ADC_DONE:
    lda #VIA_FLAG_CB1
IRQ1V_CLEAR_FLAG:
    sta SYS_VIA_IFR
    rts
IRQ1V_NOT_ADC:
    rol a                           ; negative = CA2, a key pressed; carry clear
    rol a
    rol a
    rol a
    bpl IRQ1V_NOT_KEYBOARD
    jsr CALL_KEYV_INTERRUPT                       ; KEYV with carry clear and overflow set: a key pressed
    lda #VIA_FLAG_CA2
    bne IRQ1V_CLEAR_FLAG            ; always taken
IRQ1V_NOT_KEYBOARD:
    jmp IRQ1V_UNRECOGNISED

;; Ends an interrupt that <IRQ1V_DEFAULT> handled: restores Y, X and A and returns from the interrupt.
;;
;; IRQ1V_DEFAULT pushes this address less one, so the RTS that ends each device's code comes here. It falls into
;; <IRQ2V_DEFAULT>.
IRQ1V_EXIT:
    pla
    tay
    pla
    tax
    pla
    sta IRQ_A
    ; Falls into IRQ2V_DEFAULT.

;; The default for <IRQ2V>, the interrupts nothing recognized: restores A and returns from the interrupt.
;; In: IRQ_A = A at the interrupt
IRQ2V_DEFAULT:
    lda IRQ_A
    rti

; ---------------------------------------------------------------------------------------------------------------------
; The ADC
; ---------------------------------------------------------------------------------------------------------------------

;; OSBYTE &11: starts an ADC conversion, setting <ADC_LAST_CHANNEL> from Y.
;;
;; The conversion is 8 or 12 bits as <ADC_CONVERSION> says, 12 for its default of 0.
;; In: X = the channel, 1-4 (more is taken as 4), Y = the value for ADC_LAST_CHANNEL
;; Uses: A, X, Y
;; Entry:
;;   START_ADC_CHANNEL = only starts the conversion
;; See: <ADC_COMMAND>, <ADC_CHANNEL>
START_ADC_CONVERSION:
    sty ADC_LAST_CHANNEL
START_ADC_CHANNEL:
    cpx #$05
    bcc START_ADC_SET_CHANNEL
    ldx #$04
START_ADC_SET_CHANNEL:
    stx ADC_CHANNEL
    ldy ADC_CONVERSION              ; 8 gives bit 3 clear, 12 and 0 give it set: 12 bits
    dey
    tya
    and #$08
    clc
    adc ADC_CHANNEL
    sbc #$00                        ; carry is clear: less one, for the uPD7002's channels 0-3
    sta ADC_COMMAND
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Printing text and OSRDCH
; ---------------------------------------------------------------------------------------------------------------------

;; Prints a string from the page that holds <STARTUP_BANNER>, up to and including its zero.
;; In: Y = the string's offset in the page, less one
;; Out: Y = the zero's offset, A = 0, X = 0
;; Uses: ERROR_POINTER
;; Entry:
;;   PRINT_TEXT_IN_PAGE = prints from page A instead
;;   PRINT_TEXT = prints from ERROR_POINTER + Y + 1
;; See: <OSASCI>
PRINT_BANNER_TEXT:
    lda #>STARTUP_BANNER
    .assert >BANNER_END = >STARTUP_BANNER, "The start-up banner is in one page."
PRINT_TEXT_IN_PAGE:
    sta ERROR_POINTER+1
    lda #$00
    sta ERROR_POINTER
PRINT_TEXT:
    iny
    lda (ERROR_POINTER),y
    jsr OSASCI
    tax
    bne PRINT_TEXT
    rts

;; OSBYTE &81 with a time limit: reads a character, waiting no longer than the time given.
;; In: X/Y = the time limit in centiseconds, low byte in X
;; Out: A = the character, carry = set on an escape (A = &1B) or when the time ran out (A = &FF)
;; Keeps: X, Y
;; See: <RDCHV_DEFAULT>, <INKEY_TIMER>
READ_KEY_TIMED:
    stx INKEY_TIMER
    sty INKEY_TIMER+1
    lda #$FF                        ; bit 6 set: wait with a time limit
    bne READ_INPUT_CHARACTER        ; always taken

;; OSRDCH, the default for <RDCHV>: reads a character from the *EXEC file, the keyboard or RS-423.
;;
;; While a *EXEC file is open the character comes from it; at its end the file is closed. Otherwise it waits for
;; a character from the input buffer that <INPUT_SOURCE> selects, or an escape.
;; Out: A = the character, carry = set on an escape (A = &1B)
;; Keeps: X, Y
;; See: <OSRDCH>, <READ_KEY_TIMED>
RDCHV_DEFAULT:
    lda #$00                        ; wait for ever
READ_INPUT_CHARACTER:
    sta RDCH_CHARACTER
    txa
    pha
    tya
    pha
    ldy EXEC_HANDLE
    beq READ_INPUT_CHARACTER_WAIT
    sec
    ror CASSETTE_CRITICAL           ; the cassette filing system keeps quiet
    jsr OSBGET
    php
    lsr CASSETTE_CRITICAL
    plp
    bcc READ_INPUT_CHARACTER_FOUND
    lda #$00                        ; the end of the file: closes it
    sta EXEC_HANDLE
    jsr OSFIND
READ_INPUT_CHARACTER_WAIT:
    bit ESCAPE_FLAG
    bmi READ_INPUT_CHARACTER_ESCAPE
    ldx INPUT_SOURCE
    jsr READ_INPUT                       ; takes a character from buffer X; carry = clear when there was one
    bcc READ_INPUT_CHARACTER_FOUND
    bit RDCH_CHARACTER
    bvc READ_INPUT_CHARACTER_WAIT   ; no time limit
    lda INKEY_TIMER
    ora INKEY_TIMER+1
    bne READ_INPUT_CHARACTER_WAIT
    bcs READ_INPUT_CHARACTER_DONE   ; always taken: out of time, A = &FF
READ_INPUT_CHARACTER_ESCAPE:
    sec
    lda #$1B
READ_INPUT_CHARACTER_FOUND:
    sta RDCH_CHARACTER
READ_INPUT_CHARACTER_DONE:
    pla
    tay
    pla
    tax
    lda RDCH_CHARACTER
    rts
