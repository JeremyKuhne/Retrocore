; ---------------------------------------------------------------------------------------------------------------------
; GSINIT and GSREAD, more OSBYTE calls, the sound system, speech and the ROM filing system's ROM access, the keyboard
; and its translation table, *HELP, and the paged ROM service calls (&EA10-&F18D)
; ---------------------------------------------------------------------------------------------------------------------

BAD_STRING_ERROR = $FD              ;; the error number of "Bad string"

; Where GSINIT keeps what GSREAD needs.

GSREAD_FLAGS = OS_WORK              ;; bit 7 set for a quoted string; bit 6 set when a space does not end the string
GSREAD_TOP_BIT = OS_WORK + 1        ;; &80 after |!, ORed into the character GSREAD returns, otherwise 0

; The system VIA's addressable latch, written through port B: bits 0-2 pick a latch bit and bit 3 is its new value.

LATCH_HIGH = $08                    ;; port B's bit 3: the value for the latch bit
LATCH_SOUND_WRITE = $00             ;; latch bit 0, the sound chip's write enable, active low
LATCH_SPEECH_READ = $01             ;; latch bit 1, the speech processor's read select, active low
LATCH_SPEECH_WRITE = $02            ;; latch bit 2, the speech processor's write select, active low
LATCH_KEYBOARD = $03                ;; latch bit 3: low lets the CPU test keys; high lets the keyboard scan itself
LATCH_CAPS_LOCK_LED = $06           ;; latch bit 6, the CAPS LOCK light, lit when low
LATCH_SHIFT_LOCK_LED = $07          ;; latch bit 7, the SHIFT LOCK light, lit when low

; The SN76489 sound chip.

SOUND_VOLUME_REGISTER = $10         ;; a latch byte's bit 4: the byte sets the channel's attenuation, not its frequency
NOISE_CHANNEL_BUFFER = 4            ;; the buffer of sound channel 0, the noise channel; channels 1-3 use buffers 5-7

; The sound system's workspace. The sound code indexes each channel's bytes by the channel's buffer number, 4-7, so
; each name below is four bytes before the channel bytes it names: SOUND_AMPLITUDE's are at &0808-&080B.

SOUND_ACTIVE = SOUND_WORKSPACE + 0  ;; nonzero while a channel has notes queued or playing, &0804-&0807
SOUND_AMPLITUDE = SOUND_WORKSPACE + 4 ;; a channel's amplitude, &C0 (silent) to &3F (loudest)
SOUND_AMPLITUDE_PHASE = SOUND_WORKSPACE + 8 ;; a channel's amplitude envelope phase: attack 0 to release 3, 4 when done
SOUND_PITCH = SOUND_WORKSPACE + 12  ;; a channel's note's pitch, before the pitch envelope's offset
SOUND_PITCH_SECTION = SOUND_WORKSPACE + 16 ;; a channel's pitch envelope section, 0-2, 3 when done, &FF to start
SOUND_PITCH_STEPS = SOUND_WORKSPACE + 20 ;; the steps left in a channel's pitch envelope section
SOUND_DURATION = SOUND_WORKSPACE + 24 ;; a channel's note's time left, in twentieths of a second, &FF for ever
SOUND_DURATION_TICKS = SOUND_WORKSPACE + 28 ;; centiseconds left in the current twentieth of a second
SOUND_ENVELOPE = SOUND_WORKSPACE + 32 ;; the offset of a channel's envelope in ENVELOPES, or &FF for none
SOUND_STEP_TIMER = SOUND_WORKSPACE + 36 ;; centiseconds until a channel's envelopes take their next step
SOUND_SYNC_WAIT = SOUND_WORKSPACE + 40 ;; nonzero while a channel waits for others to start a note with it
SOUND_LAST_PITCH = SOUND_WORKSPACE + 44 ;; the pitch last sent to a channel
SOUND_PITCH_OFFSET = SOUND_WORKSPACE + 48 ;; what a channel's pitch envelope has added to its pitch so far
SOUND_SYNC_COUNT = SOUND_WORKSPACE + 56 ;; channels still awaited to start together, or &FF while none are gathering
SOUND_AMPLITUDE_STEP = SOUND_WORKSPACE + 57 ;; the amplitude change of the envelope phase being worked on
SOUND_AMPLITUDE_TARGET = SOUND_WORKSPACE + 58 ;; the amplitude that ends the envelope phase being worked on
SOUND_SYNC_RELEASE = SOUND_WORKSPACE + 59 ;; 1 for the centisecond in which the waiting channels start, otherwise 0
SOUND_QUARTERS = SOUND_WORKSPACE + 60 ;; the quarter semitones of the pitch being set, 0-3
SOUND_PERIOD = SOUND_WORKSPACE + 61 ;; the period being worked out, two bytes; the octave, at first
SOUND_PERIOD_STEP = SOUND_WORKSPACE + 63 ;; how much each quarter semitone takes off the period

; Values in the sound workspace.

SOUND_SILENCE = $C0                 ;; the amplitude of silence
SOUND_RELEASE_PHASE = 3             ;; the amplitude envelope's release phase
SOUND_SILENT_PHASE = 4              ;; the phase after release: the amplitude envelope has finished
SOUND_PITCH_DONE = 3                ;; the pitch section after the third: the pitch envelope has finished
SOUND_NO_ENVELOPE = $FF             ;; the envelope offset of a note with a fixed amplitude
SOUND_FOREVER = $FF                 ;; the duration of a note that lasts for ever
SOUND_TICKS = 5                     ;; the centiseconds in a twentieth of a second, the unit of a note's duration

; Where an envelope's parameters are, from its first byte in ENVELOPES, in ENVELOPE's own order.

ENVELOPE_T = 0                      ;; the step length in centiseconds; bit 7 set stops the pitch envelope repeating
ENVELOPE_PI1 = 1                    ;; the pitch change per step in each of the three sections, PI1-PI3
ENVELOPE_PN1 = 4                    ;; the steps in each of the three pitch sections, PN1-PN3
ENVELOPE_AA = 7                     ;; the amplitude change per step in attack, decay, sustain and release, AA-AR
ENVELOPE_ALA = 11                   ;; the levels that end attack and decay, ALA and ALD, then zeros for the rest

; The speech processor and the ROM filing system.

SPEECH_READ_BYTE = $10              ;; the speech processor's command to read a byte from the PHROM's address
SPEECH_LOAD_ADDRESS = $40           ;; the command that loads four bits of the PHROM address, in its low four
SERVICE_HELP = $09                  ;; the paged ROM service call for *HELP
SERVICE_RFS_INITIALISE = $0D        ;; the service call that asks a paged ROM to start giving the ROM filing system data
SERVICE_RFS_BYTE_GET = $0E          ;; the service call that asks it for the next byte
SERVICE_VECTORS_CLAIMED = $0F       ;; the service call that says a filing system has taken the vectors
FSC_NEW_FILING_SYSTEM = $06         ;; the FSCV call that warns the filing system that another is taking over
JIM_VECTOR = JIM + $FE              ;; &FDFE-&FDFF, an address in the 1 MHz bus's paged memory that reset may call

; The keyboard: internal key numbers (the Advanced User Guide's appendix C), and the keyboard status bits.

SHIFT_KEY = $00                     ;; SHIFT's internal key number
CTRL_KEY = $01                      ;; CTRL's
CAPS_LOCK_KEY = $40                 ;; CAPS LOCK's
SHIFT_LOCK_KEY = $50                ;; SHIFT LOCK's
FIRST_CHARACTER_KEY = $10           ;; the first key that gives a character, Q; below it are SHIFT, CTRL and the links
KEY_DOWN = $80                      ;; bit 7 of a key number read back from the keyboard: the key is pressed
KEY_STATUS_SHIFT = %00001000        ;; KEYBOARD_STATUS bit 3: SHIFT is pressed
KEY_STATUS_CAPS_LOCK_OFF = %00010000 ;; bit 4: CAPS LOCK is not engaged
KEY_STATUS_SHIFT_LOCK_OFF = %00100000 ;; bit 5: SHIFT LOCK is not engaged
KEY_STATUS_CTRL = %01000000         ;; bit 6: CTRL is pressed
KEY_STATUS_SHIFT_ENABLE = %10000000 ;; bit 7: SHIFT reverses an engaged lock

; The codes the keyboard translation table gives the function and editing keys.

KEY_F0 = $80                        ;; f0; f1-f9 give &81-&89
KEY_COPY = $8B                      ;; COPY
KEY_LEFT = $8C                      ;; the left cursor key
KEY_RIGHT = $8D                     ;; the right cursor key
KEY_DOWN_CURSOR = $8E               ;; the down cursor key
KEY_UP = $8F                        ;; the up cursor key

;; OSBYTE &9B: writes to the video ULA's palette register, keeping a copy in <VIDEO_ULA_PALETTE_COPY>.
;;
;; A palette entry is a logical colour in the high nibble and a physical colour in the low. The ULA takes the physical
;; colour's red, green and blue bits inverted, so the value is exclusive-ORed with 7 first, as the Advanced User
;; Guide says. Interrupts are held off so that the copy and the register agree.
;; In: X = the palette entry
;; Uses: A
;; Keeps: X, Y
;; Entry: WRITE_PALETTE_REGISTER_A = writes A instead, for the VDU driver
WRITE_PALETTE_REGISTER:
    txa
WRITE_PALETTE_REGISTER_A:
    eor #$07                        ; inverts the physical colour's three bits
    php
    sei
    sta VIDEO_ULA_PALETTE_COPY
    sta VIDEO_ULA_PALETTE
    plp
    rts

;; Starts reading a string that a space ends, as for a file name: GSINIT with carry clear. Falls into
;; <GSINIT_HANDLER>.
GSINIT_SPACE_ENDS:
    clc

;; GSINIT: skips the spaces before a string in a command line, and starts reading it with <GSREAD_HANDLER>.
;;
;; It notes in <GSREAD_FLAGS> whether the string starts with a quotation mark (bit 7), which it then steps past, and
;; whether a space is part of the string (bit 6, from carry).
;; In: TEXT_POINTER = the text's address, Y = the offset to start at, carry = set when only a carriage return or a
;;   closing quotation mark ends the string, clear when a space does too
;; Out: A = the first character after the spaces, Y = the offset of the string's first character (after any quotation
;;   mark), zero = set when there is no string (A is a carriage return)
;; Uses: GSREAD_FLAGS
;; Keeps: X
;; See: <GSREAD_HANDLER>, <GSINIT>
GSINIT_HANDLER:
    ror GSREAD_FLAGS                ; carry into bit 7, for now
    jsr SKIP_SPACES                       ; skips spaces
    iny
    cmp #'"'
    beq GSINIT_HANDLER_QUOTED       ; carry set: quoted
    dey
    clc
GSINIT_HANDLER_QUOTED:
    ror GSREAD_FLAGS                ; bit 7 = quoted, bit 6 = the caller's carry
    cmp #$0D
    rts

;; GSREAD: reads the next character of a string that <GSINIT_HANDLER> started.
;;
;; | brings in control codes and other characters: |@ and |A to |Z give 0-26 (|a to |z give the same), |[, |\, |],
;; |^, |_ and |£ give 27-31, and |{, |} and |~ give 27, 29 and 30. |? gives DELETE (127), || gives |, |" gives a
;; quotation mark, and |! sets bit 7 of the character that follows it, which may itself use |. Every other
;; character after | goes through <CTRL_CHARACTER>: one from space to > is left as it is, and one from &80 up is
;; changed as that routine changes the function keys' codes. Inside quotation marks, two quotation marks give one.
;;
;; The string ends at a carriage return, at the closing quotation mark of a quoted string, or at a space when
;; GSINIT was called with carry clear. A carriage return before the closing quotation mark, or any control character
;; in the text, is an error.
;; In: TEXT_POINTER = the text's address, Y = the offset of the next character, GSREAD_FLAGS = as GSINIT left them
;; Out: carry = set at the end of the string, A = the character (at the end, the first character after the spaces
;;   that follow), Y = the offset of the next character, overflow = set when | and a character other than |, " or ?
;;   gave the character
;; Errors: BRK error &FD, "Bad string" (<BAD_STRING>)
;; Uses: GSREAD_TOP_BIT
;; Keeps: X
;; See: <GSREAD>, <CTRL_CHARACTER>
GSREAD_HANDLER:
    lda #$00
GSREAD_HANDLER_NEXT:
    sta GSREAD_TOP_BIT
    lda (TEXT_POINTER),y
    cmp #$0D
    bne GSREAD_HANDLER_NOT_CR
    bit GSREAD_FLAGS
    bmi BAD_STRING                  ; the closing quotation mark is missing
    bpl GSREAD_HANDLER_END          ; always taken
GSREAD_HANDLER_NOT_CR:
    cmp #' '
    bcc BAD_STRING                  ; a control character
    bne GSREAD_HANDLER_NOT_SPACE
    bit GSREAD_FLAGS
    bmi GSREAD_HANDLER_PLAIN        ; quoted: the space is part of the string
    bvc GSREAD_HANDLER_END          ; a space ends the string
GSREAD_HANDLER_NOT_SPACE:
    cmp #'"'
    bne GSREAD_HANDLER_NOT_QUOTE
    bit GSREAD_FLAGS
    bpl GSREAD_HANDLER_PLAIN        ; not quoted: an ordinary character
    iny
    lda (TEXT_POINTER),y
    cmp #'"'
    beq GSREAD_HANDLER_PLAIN        ; "" gives one quotation mark
GSREAD_HANDLER_END:
    jsr SKIP_SPACES                       ; skips spaces
    sec
    rts
GSREAD_HANDLER_NOT_QUOTE:
    cmp #'|'
    bne GSREAD_HANDLER_PLAIN
    iny
    lda (TEXT_POINTER),y
    cmp #'|'
    beq GSREAD_HANDLER_PLAIN
    cmp #'"'
    beq GSREAD_HANDLER_PLAIN
    cmp #'!'
    bne GSREAD_HANDLER_ESCAPE
    iny
    lda #$80                        ; |!: bit 7 for the next character
    bne GSREAD_HANDLER_NEXT         ; always taken
GSREAD_HANDLER_ESCAPE:
    cmp #' '
    bcc BAD_STRING                  ; | before a control character
    cmp #'?'
    beq GSREAD_HANDLER_DELETE
    jsr CTRL_CHARACTER
    bit OVERFLOW_BYTE               ; sets overflow and skips the CLV
    bvs GSREAD_HANDLER_RETURN       ; always taken
GSREAD_HANDLER_DELETE:
    lda #$7F
GSREAD_HANDLER_PLAIN:
    clv
GSREAD_HANDLER_RETURN:
    iny
    ora GSREAD_TOP_BIT
    clc
    rts

;; Raises the "Bad string" error, for <GSREAD_HANDLER> and the cassette filing system's file names.
BAD_STRING:
    brk
    .byte BAD_STRING_ERROR, "Bad string", 0

;; Applies SHIFT to a character from the keyboard, giving the key's other legend.
;;
;; Letters change case, the digits 1-9 and the symbols :;,-./ give !"#$%&'()*+<=>?, and the symbols [\]^ give {|}~
;; and the other way round. _ and £ (&60) change places. Space, 0, @, DELETE and the control characters are kept,
;; and the function and cursor keys' codes, &80-&8F, gain &10.
;; In: A = the character
;; Out: A = the shifted character
;; Keeps: X, Y
;; Entry: SHIFT_CHARACTER_SWAP = exclusive-ORs A with &20, but exchanges &5F and &60; <CTRL_CHARACTER> uses it for
;;   codes from &80
SHIFT_CHARACTER:
    cmp #'0'
    beq SHIFT_CHARACTER_DONE
    cmp #'@'
    beq SHIFT_CHARACTER_DONE
    bcc SHIFT_CHARACTER_SYMBOL
    cmp #$7F
    beq SHIFT_CHARACTER_DONE
    bcs SHIFT_CHARACTER_FLIP        ; &80 and up gain &10
SHIFT_CHARACTER_SWAP:
    eor #$30
    cmp #$6F
    beq SHIFT_CHARACTER_UNDERLINE   ; it was _
    cmp #$50
    bne SHIFT_CHARACTER_SYMBOL      ; it was not £
SHIFT_CHARACTER_UNDERLINE:
    eor #$1F
SHIFT_CHARACTER_SYMBOL:
    cmp #'!'
    bcc SHIFT_CHARACTER_DONE        ; space and the control characters
SHIFT_CHARACTER_FLIP:
    eor #$10
SHIFT_CHARACTER_DONE:
    rts

;; Applies CTRL to a character: @, the letters (either case), [\]^_ and £ give 0-31.
;;
;; DELETE and the characters below @ are kept, {|}~ give 27-30, and the function and cursor keys' codes, &80-&8F,
;; gain &20 through <SHIFT_CHARACTER_SWAP>.
;; In: A = the character
;; Out: A = the control character
;; Keeps: X, Y
CTRL_CHARACTER:
    cmp #$7F
    beq CTRL_CHARACTER_DONE
    bcs SHIFT_CHARACTER_SWAP
    cmp #$60
    bne CTRL_CHARACTER_1
    lda #$5F                        ; £ gives what _ does
CTRL_CHARACTER_1:
    cmp #'@'
    bcc CTRL_CHARACTER_DONE
    and #$1F
CTRL_CHARACTER_DONE:
    rts

; "/!BOOT" and a carriage return: the command a SHIFT+BREAK runs from the ROM filing system when no paged ROM takes
; the auto-boot service call. Reset.asm names it BOOT_COMMAND, as the seven bytes before CALL_BREAK_INTERCEPT.
    .byte "/!BOOT", $0D

;; Calls the BREAK intercept, if <BREAK_INTERCEPT> holds a JMP: reset calls this twice, with carry clear before the
;; start-up message and set after it (OSBYTE &F7-&F9).
;;
;; The intercept may change anything else.
;; In: carry = clear for the first call, set for the second
;; Out: A = nonzero when there is no intercept
;; Uses: A, X, Y (the intercept's)
CALL_BREAK_INTERCEPT:
    lda BREAK_INTERCEPT
    eor #$4C                        ; JMP abs
    bne SET_TV_DONE
    jmp BREAK_INTERCEPT

;; OSBYTE &90, *TV: sets the vertical shift and interlace that the next mode change gives the 6845.
;; In: X = the vertical shift in lines, Y = 0 for interlace on or 1 for off (only bit 0 is kept)
;; Out: X = the old vertical shift, Y = the old interlace setting
;; Uses: A
SET_TV:
    lda TV_VERTICAL_ADJUST
    stx TV_VERTICAL_ADJUST
    tax
    tya
    and #$01
    ldy TV_INTERLACE
    sta TV_INTERLACE
SET_TV_DONE:
    rts

;; OSBYTE &93: writes a byte to FRED, the 1 MHz bus's page of memory-mapped devices at &FC00.
;; In: X = the offset in the page, Y = the byte
;; Out: A = the byte
;; Keeps: X, Y
WRITE_FRED:
    tya
    sta FRED,x
    rts

;; OSBYTE &95: writes a byte to JIM, the 1 MHz bus's page of paged memory at &FD00.
;; In: X = the offset in the page, Y = the byte
;; Out: A = the byte
;; Keeps: X, Y
WRITE_JIM:
    tya
    sta JIM,x
    rts

;; OSBYTE &97: writes a byte to SHEILA, the BBC's own hardware at &FE00.
;; In: X = the offset in the page, Y = the byte
;; Out: A = the byte
;; Keeps: X, Y
WRITE_SHEILA:
    tya
    sta SHEILA,x
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The sound system
; ---------------------------------------------------------------------------------------------------------------------

;; Silences a sound channel: ends its amplitude envelope and gives it the amplitude of silence. Falls into
;; <SET_AMPLITUDE>.
;; In: X = the channel's buffer number, 4-7
;; Out: Y = 0
;; Uses: A
;; Keeps: X
SILENCE_CHANNEL:
    lda #SOUND_SILENT_PHASE
    sta SOUND_AMPLITUDE_PHASE,x
    lda #SOUND_SILENCE

;; Sets a sound channel's amplitude and gives the sound chip the attenuation for it, or silence while OSBYTE &D2
;; suppresses sound.
;;
;; An amplitude is an envelope level, 0-126, less 63, so that it fits a signed byte and the envelope code can catch
;; it going out of range with the overflow flag: &C0 is silence and &3F the loudest. Each eight steps is one of the
;; chip's sixteen attenuations. Falls into <WRITE_SOUND_CHIP>.
;; In: A = the amplitude, X = the channel's buffer number, 4-7
;; Out: Y = 0
;; Uses: A
;; Keeps: X
SET_AMPLITUDE:
    sta SOUND_AMPLITUDE,x
    ldy SOUND_SUPPRESS
    beq SET_AMPLITUDE_1
    lda #SOUND_SILENCE
SET_AMPLITUDE_1:
    sec
    sbc #$40
    lsr a
    lsr a
    lsr a                           ; the low nibble is now the level, 0 (silent) to 15
    eor #$0F                        ; the attenuation, 15 (silent) to 0
    ora CHANNEL_REGISTER_BITS - NOISE_CHANNEL_BUFFER,x
    ora #SOUND_VOLUME_REGISTER

;; Writes a byte to the SN76489 sound chip over the slow data bus.
;;
;; The byte goes out on the system VIA's port A; then latch bit 0, the chip's write enable, is held low for a few
;; microseconds (the chip needs 8) and raised again. Interrupts are off meanwhile, since the interrupt code uses the
;; same port.
;; In: A = the byte, a register's latch byte (bit 7 set) or a frequency's high bits (bit 7 clear)
;; Out: Y = 0
;; Keeps: A, X
;; Entry: WRITE_SOUND_CHIP_PUSHED = for a caller that has pushed the flags this should return with
WRITE_SOUND_CHIP:
    php
WRITE_SOUND_CHIP_PUSHED:
    sei
    ldy #$FF
    sty SYS_VIA_DDRA                ; port A all outputs
    sta SYS_VIA_ORA_NH
    iny
    sty SYS_VIA_ORB                 ; Y = 0: LATCH_SOUND_WRITE low, the chip takes the byte
    ldy #$02
WRITE_SOUND_CHIP_WAIT:
    dey
    bne WRITE_SOUND_CHIP_WAIT
    ldy #LATCH_SOUND_WRITE | LATCH_HIGH
    sty SYS_VIA_ORB
    ldy #$04
WRITE_SOUND_CHIP_DELAY:
    dey
    bne WRITE_SOUND_CHIP_DELAY
    plp
    rts

;; The sound chip's register bits for each sound channel, indexed by the channel's buffer number less 4: a latch
;; byte's bit 7 and the chip channel in bits 6-5. Sound channel 0 is the noise generator, and channels 1-3 are the
;; chip's tone generators 2, 1 and 0.
;; See: <SET_AMPLITUDE>, <SET_PITCH>
CHANNEL_REGISTER_BITS:
    .byte %11100000                 ; channel 0: noise
    .byte %11000000                 ; channel 1: tone generator 2
    .byte %10100000                 ; channel 2: tone generator 1
    .byte %10000000                 ; channel 3: tone generator 0

;; Goes on to <PROCESS_SOUND>'s next channel, for its branches that cannot reach <PROCESS_SOUND_NEXT>.
NEXT_SOUND_CHANNEL:
    jmp PROCESS_SOUND_NEXT

;; Runs the sound system for a centisecond, from the 100 Hz interrupt: counts down each active channel's note,
;; starting the next when it ends, and steps the envelopes.
;;
;; The interrupt code calls this with interrupts enabled, using <SOUND_SEMAPHORE> to keep it from running twice at
;; once. Channels are taken from 3 down to 0, as buffers 7 down to 4. For each active one:
;;
;; - A note's duration counts down in twentieths of a second, <SOUND_TICKS> calls each. When it ends, or the buffer
;;   has been flushed, <NEXT_NOTE> moves the envelope to release and starts the next note when it may.
;; - Every T centiseconds (the envelope's first parameter) the envelopes take a step. The amplitude changes by the
;;   phase's AA, AD, AS or AR, kept within &C0-&3F, until it reaches the phase's level (ALA, ALD, then 0 for sustain
;;   and release); then the next phase begins. The sound chip is told only when the attenuation changes. The pitch
;;   offset changes by PI1, PI2 and PI3 for PN1, PN2 and PN3 steps, and starts again unless T's bit 7 is set.
;;
;; Before the channels, this releases the channels waiting to start a note together: when <SOUND_SYNC_COUNT> has
;; reached zero, it sets <SOUND_SYNC_RELEASE> for this call and starts gathering afresh.
;; Uses: A, X, Y
;; See: <NEXT_NOTE>, <START_NOTE>, <SET_AMPLITUDE>, <SET_PITCH>
PROCESS_SOUND:
    lda #$00
    sta SOUND_SYNC_RELEASE
    lda SOUND_SYNC_COUNT
    bne PROCESS_SOUND_START
    inc SOUND_SYNC_RELEASE          ; every channel of the group is ready
    dec SOUND_SYNC_COUNT            ; &FF: none gathering
PROCESS_SOUND_START:
    ldx #NOISE_CHANNEL_BUFFER + 4
PROCESS_SOUND_CHANNEL:
    dex
    lda SOUND_ACTIVE,x
    beq NEXT_SOUND_CHANNEL
    lda BUFFER_BUSY,x
    bmi PROCESS_SOUND_NEXT_NOTE     ; the buffer has been flushed
    lda SOUND_DURATION,x
    bne PROCESS_SOUND_DURATION
PROCESS_SOUND_NEXT_NOTE:
    jsr NEXT_NOTE
PROCESS_SOUND_DURATION:
    lda SOUND_DURATION,x
    beq PROCESS_SOUND_NOTE_OVER
    cmp #SOUND_FOREVER
    beq PROCESS_SOUND_ENVELOPE
    dec SOUND_DURATION_TICKS,x
    bne PROCESS_SOUND_ENVELOPE
    lda #SOUND_TICKS
    sta SOUND_DURATION_TICKS,x
    dec SOUND_DURATION,x
    bne PROCESS_SOUND_ENVELOPE
PROCESS_SOUND_NOTE_OVER:
    jsr NEXT_NOTE
PROCESS_SOUND_ENVELOPE:
    lda SOUND_STEP_TIMER,x
    beq PROCESS_SOUND_STEP
    dec SOUND_STEP_TIMER,x
    bne NEXT_SOUND_CHANNEL
PROCESS_SOUND_STEP:
    ldy SOUND_ENVELOPE,x
    cpy #SOUND_NO_ENVELOPE
    beq NEXT_SOUND_CHANNEL
    lda ENVELOPES + ENVELOPE_T,y
    and #$7F                        ; the step length, without the pitch envelope's bit
    sta SOUND_STEP_TIMER,x
    lda SOUND_AMPLITUDE_PHASE,x
    cmp #SOUND_SILENT_PHASE
    beq PROCESS_SOUND_PITCH
    lda SOUND_AMPLITUDE_PHASE,x
    clc
    adc SOUND_ENVELOPE,x
    tay                             ; Y = the envelope plus the phase
    lda ENVELOPES + ENVELOPE_ALA,y  ; the level that ends the phase
    sec
    sbc #63                         ; as an amplitude
    sta SOUND_AMPLITUDE_TARGET
    lda ENVELOPES + ENVELOPE_AA,y   ; the change per step
    sta SOUND_AMPLITUDE_STEP
    lda SOUND_AMPLITUDE,x
    pha
    clc
    adc SOUND_AMPLITUDE_STEP
    bvc PROCESS_SOUND_LIMIT
    rol a                           ; overflowed: carry = set when it went past the top
    lda #$3F
    bcs PROCESS_SOUND_LIMIT
    eor #$FF                        ; &C0, past the bottom
PROCESS_SOUND_LIMIT:
    sta SOUND_AMPLITUDE,x
    rol a                           ; negative = bits 7 and 6 differ: outside &C0-&3F
    eor SOUND_AMPLITUDE,x
    bpl PROCESS_SOUND_TARGET
    lda #$3F
    bcc PROCESS_SOUND_CLAMP         ; &40-&7F: too loud
    eor #$FF                        ; &80-&BF: below silence
PROCESS_SOUND_CLAMP:
    sta SOUND_AMPLITUDE,x
PROCESS_SOUND_TARGET:
    dec SOUND_AMPLITUDE_STEP        ; less one, so that a zero step counts as falling
    lda SOUND_AMPLITUDE,x
    sec
    sbc SOUND_AMPLITUDE_TARGET
    eor SOUND_AMPLITUDE_STEP
    bmi PROCESS_SOUND_CHANGED       ; still short of the level
    lda SOUND_AMPLITUDE_TARGET      ; reached or passed it: the next phase
    sta SOUND_AMPLITUDE,x
    inc SOUND_AMPLITUDE_PHASE,x
PROCESS_SOUND_CHANGED:
    pla
    eor SOUND_AMPLITUDE,x
    and #%11111000                  ; the bits that make the attenuation
    beq PROCESS_SOUND_PITCH
    lda SOUND_AMPLITUDE,x
    jsr SET_AMPLITUDE
PROCESS_SOUND_PITCH:
    lda SOUND_PITCH_SECTION,x
    cmp #SOUND_PITCH_DONE
    beq PROCESS_SOUND_NEXT
    lda SOUND_PITCH_STEPS,x
    bne PROCESS_SOUND_PITCH_STEP
    inc SOUND_PITCH_SECTION,x
    lda SOUND_PITCH_SECTION,x
    cmp #SOUND_PITCH_DONE
    bne PROCESS_SOUND_PITCH_SECTION
    ldy SOUND_ENVELOPE,x
    lda ENVELOPES + ENVELOPE_T,y
    bmi PROCESS_SOUND_NEXT          ; T's bit 7: the pitch envelope does not repeat
    lda #$00
    sta SOUND_PITCH_OFFSET,x        ; repeats from the note's own pitch
    sta SOUND_PITCH_SECTION,x
PROCESS_SOUND_PITCH_SECTION:
    lda SOUND_PITCH_SECTION,x
    clc
    adc SOUND_ENVELOPE,x
    tay
    lda ENVELOPES + ENVELOPE_PN1,y
    sta SOUND_PITCH_STEPS,x
    beq PROCESS_SOUND_NEXT          ; a section of no steps
PROCESS_SOUND_PITCH_STEP:
    dec SOUND_PITCH_STEPS,x
    lda SOUND_ENVELOPE,x
    clc
    adc SOUND_PITCH_SECTION,x
    tay
    lda ENVELOPES + ENVELOPE_PI1,y
    clc
    adc SOUND_PITCH_OFFSET,x
    sta SOUND_PITCH_OFFSET,x
    clc
    adc SOUND_PITCH,x
    jsr SET_PITCH
PROCESS_SOUND_NEXT:
    cpx #NOISE_CHANNEL_BUFFER
    beq RESET_SOUND_DONE
    jmp PROCESS_SOUND_CHANNEL

;; Silences and clears the four sound channels, at reset.
;; Out: X = 4
;; Uses: A, Y
;; See: <CLEAR_SOUND_CHANNEL>
RESET_SOUND:
    ldx #NOISE_CHANNEL_BUFFER + 4
RESET_SOUND_LOOP:
    dex
    jsr CLEAR_SOUND_CHANNEL
    cpx #NOISE_CHANNEL_BUFFER
    bne RESET_SOUND_LOOP
RESET_SOUND_DONE:
    rts

;; Ends a sound channel's note, when its time is up or its buffer has been flushed, and starts the next note when
;; it may.
;;
;; The amplitude envelope moves to release, unless it has finished. A flush, which sets the channel's <BUFFER_BUSY>
;; byte, also ends the note at once and drops the synchronisation being gathered.
;;
;; A note's synchronisation count, bits 1-0 of its first byte, is the number of other channels it starts with. The
;; first such note to come up sets <SOUND_SYNC_COUNT> to its count, and each later one counts it down; each waits,
;; with <SOUND_SYNC_WAIT> set, until the count reaches zero and <PROCESS_SOUND> sets <SOUND_SYNC_RELEASE>. A channel
;; that has no note queued goes inactive once its envelope has finished, and one without an envelope is silenced.
;; In: X = the channel's buffer number, 4-7
;; Uses: A, Y
;; Keeps: X
;; See: <NEXT_NOTE_EMPTY>, <START_NOTE>
NEXT_NOTE:
    lda SOUND_AMPLITUDE_PHASE,x
    cmp #SOUND_SILENT_PHASE
    beq NEXT_NOTE_FLUSHED
    lda #SOUND_RELEASE_PHASE
    sta SOUND_AMPLITUDE_PHASE,x
NEXT_NOTE_FLUSHED:
    lda BUFFER_BUSY,x
    beq NEXT_NOTE_SYNC
    lda #$00                        ; flushed: start afresh
    sta BUFFER_BUSY,x
    ldy #$04
NEXT_NOTE_CLEAR_SYNC:
    sta SOUND_SYNC_WAIT + NOISE_CHANNEL_BUFFER - 1,y ; every channel's
    dey
    bne NEXT_NOTE_CLEAR_SYNC
    sta SOUND_DURATION,x
    dey
    sty SOUND_SYNC_COUNT            ; &FF: none gathering
NEXT_NOTE_SYNC:
    lda SOUND_SYNC_WAIT,x
    beq NEXT_NOTE_PEEK
    lda SOUND_SYNC_RELEASE
    beq NEXT_NOTE_WAIT              ; the others are not all ready
    lda #$00
    sta SOUND_SYNC_WAIT,x
NEXT_NOTE_START:
    jmp START_NOTE

;; Silences a sound channel and clears it: no note, inactive, no synchronisation for any channel, and pitch 0 on the
;; chip. Flushing a sound channel's buffer calls this, and so does <RESET_SOUND>.
;; In: X = the channel's buffer number, 4-7
;; Uses: A, Y
;; Keeps: X
CLEAR_SOUND_CHANNEL:
    jsr SILENCE_CHANNEL             ; returns Y = 0
    tya
    sta SOUND_DURATION,x
    sta BUFFER_BUSY,x
    sta SOUND_ACTIVE,x
    ldy #$03
CLEAR_SOUND_CHANNEL_LOOP:
    sta SOUND_SYNC_WAIT + NOISE_CHANNEL_BUFFER,y ; every channel's
    dey
    bpl CLEAR_SOUND_CHANNEL_LOOP
    sty SOUND_SYNC_COUNT            ; &FF: none gathering
    bmi SET_PITCH_NOW               ; always taken, with A = 0

;; The rest of <NEXT_NOTE>, for a channel with an empty buffer: once its envelope has finished, and the buffer is
;; still empty with interrupts off, the channel goes inactive.
;; In: X = the channel's buffer number, 4-7
;; Uses: A, Y
;; Keeps: X
;; Entry:
;;   NEXT_NOTE_WAIT = leaves the channel as it is, but silences one without an envelope
;;   NEXT_NOTE_PEEK = looks at the next note in the buffer, starting it unless it must wait for other channels
NEXT_NOTE_EMPTY:
    php
    sei
    lda SOUND_AMPLITUDE_PHASE,x
    cmp #SOUND_SILENT_PHASE
    bne NEXT_NOTE_EMPTY_1
    jsr EXAMINE_BUFFER                       ; looks at buffer X: carry = set when it is empty
    bcc NEXT_NOTE_EMPTY_1
    lda #$00
    sta SOUND_ACTIVE,x
NEXT_NOTE_EMPTY_1:
    plp
NEXT_NOTE_WAIT:
    ldy SOUND_ENVELOPE,x
    cpy #SOUND_NO_ENVELOPE
    bne NEXT_NOTE_DONE
    jsr SILENCE_CHANNEL
NEXT_NOTE_DONE:
    rts
NEXT_NOTE_PEEK:
    jsr EXAMINE_BUFFER                       ; the next note's first byte, left in the buffer
    bcs NEXT_NOTE_EMPTY
    and #$03                        ; its synchronisation count
    beq NEXT_NOTE_START
    lda SOUND_SYNC_COUNT
    beq NEXT_NOTE_HOLD              ; a group is complete and starts next time: wait for the one after
    inc SOUND_SYNC_WAIT,x
    bit SOUND_SYNC_COUNT
    bpl NEXT_NOTE_COUNT
    jsr EXAMINE_BUFFER                       ; the first of a group: the others it waits for
    and #$03
    sta SOUND_SYNC_COUNT
    bpl NEXT_NOTE_HOLD              ; always taken
NEXT_NOTE_COUNT:
    dec SOUND_SYNC_COUNT
NEXT_NOTE_HOLD:
    jmp NEXT_NOTE_WAIT

;; Sets a sound channel's pitch on the chip, unless the channel already has it.
;;
;; A pitch is in quarter semitones. For the noise channel, its low four bits go to the chip as the noise control.
;; For a tone channel, the pitch's semitone within its octave picks a period from <SEMITONE_PERIODS_LOW> and
;; <SEMITONE_PERIODS_HIGH>, which hold the lowest octave's; each quarter semitone takes the semitone's step off it,
;; and each octave up halves it. Channels 2 and 3 then add 1 and 2 to the period, from <SOUND_PERIOD_OFFSETS>. The chip
;; takes the ten-bit period as a latch byte with its low four bits and a data byte with the other six.
;; In: A = the pitch, X = the channel's buffer number, 4-7
;; Uses: A, Y
;; Keeps: X
;; Entry: SET_PITCH_NOW = sets the pitch even when it is unchanged
SET_PITCH:
    cmp SOUND_LAST_PITCH,x
    beq NEXT_NOTE_DONE
SET_PITCH_NOW:
    sta SOUND_LAST_PITCH,x
    cpx #NOISE_CHANNEL_BUFFER
    bne SET_PITCH_TONE
    and #$0F
    ora CHANNEL_REGISTER_BITS - NOISE_CHANNEL_BUFFER,x
    php
    jmp SET_PITCH_LAST
SET_PITCH_TONE:
    pha
    and #$03
    sta SOUND_QUARTERS
    lda #$00
    sta SOUND_PERIOD                ; counts the octaves, for now
    pla
    lsr a
    lsr a                           ; the semitone
SET_PITCH_OCTAVE:
    cmp #12
    bcc SET_PITCH_SEMITONE
    inc SOUND_PERIOD
    sbc #12
    bne SET_PITCH_OCTAVE
SET_PITCH_SEMITONE:
    tay                             ; the semitone within the octave
    lda SOUND_PERIOD
    pha                             ; the octave
    lda SEMITONE_PERIODS_LOW,y
    sta SOUND_PERIOD
    lda SEMITONE_PERIODS_HIGH,y
    pha
    and #$03
    sta SOUND_PERIOD + 1
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    sta SOUND_PERIOD_STEP
    lda SOUND_PERIOD
    ldy SOUND_QUARTERS
    beq SET_PITCH_SHIFT
SET_PITCH_QUARTER:
    sec
    sbc SOUND_PERIOD_STEP
    bcs SET_PITCH_QUARTER_1
    dec SOUND_PERIOD + 1
SET_PITCH_QUARTER_1:
    dey
    bne SET_PITCH_QUARTER
SET_PITCH_SHIFT:
    sta SOUND_PERIOD
    pla
    tay                             ; the octave
    beq SET_PITCH_OFFSET
SET_PITCH_SHIFT_LOOP:
    lsr SOUND_PERIOD + 1
    ror SOUND_PERIOD
    dey
    bne SET_PITCH_SHIFT_LOOP
SET_PITCH_OFFSET:
    lda SOUND_PERIOD
    clc
    adc SOUND_PERIOD_OFFSETS,x                     ; 0, 1 or 2 for channels 1-3
    sta SOUND_PERIOD
    bcc SET_PITCH_WRITE
    inc SOUND_PERIOD + 1
SET_PITCH_WRITE:
    and #$0F
    ora CHANNEL_REGISTER_BITS - NOISE_CHANNEL_BUFFER,x
    php
    sei
    jsr WRITE_SOUND_CHIP            ; the latch byte, with the period's low four bits
    lda SOUND_PERIOD
    lsr SOUND_PERIOD + 1
    ror a
    lsr SOUND_PERIOD + 1
    ror a
    lsr a
    lsr a                           ; the period's high six bits
SET_PITCH_LAST:
    jmp WRITE_SOUND_CHIP_PUSHED

;; Starts the next note in a sound channel's buffer.
;;
;; A note is three bytes, as OSWORD 7 (<SOUND_COMMAND>) queues it. The first holds the envelope or amplitude in bits
;; 7-3, hold in bit 2 and the synchronisation count in bits 1-0: with bit 7 clear, bits 6-3 are the envelope number less
;; one; with it set, bits 6-3 are SOUND's amplitude plus 15, a fixed amplitude. Then come the pitch and the duration.
;;
;; A note with hold set is not played: it lets the last note's release go on for its duration. A note with an
;; envelope starts its envelopes from the beginning at the next centisecond.
;; In: X = the channel's buffer number, 4-7
;; Uses: A, Y
;; Keeps: X
START_NOTE:
    php
    sei
    jsr REMOVE_FROM_BUFFER                       ; takes the first byte
    pha
    and #$04
    beq START_NOTE_PLAY
    pla                             ; hold
    ldy SOUND_ENVELOPE,x
    cpy #SOUND_NO_ENVELOPE
    bne START_NOTE_HOLD
    jsr SILENCE_CHANNEL             ; no envelope to release
START_NOTE_HOLD:
    jsr REMOVE_FROM_BUFFER                       ; the pitch, ignored
    jsr REMOVE_FROM_BUFFER                       ; the duration
    plp
    jmp START_NOTE_DURATION
START_NOTE_PLAY:
    pla
    and #%11111000
    asl a                           ; carry = a fixed amplitude
    bcc START_NOTE_ENVELOPE         ; A = the envelope's offset in ENVELOPES
    eor #$FF
    lsr a
    sec
    sbc #$40                        ; as an amplitude
    jsr SET_AMPLITUDE
    lda #SOUND_NO_ENVELOPE
START_NOTE_ENVELOPE:
    sta SOUND_ENVELOPE,x
    lda #SOUND_TICKS
    sta SOUND_DURATION_TICKS,x
    lda #$01
    sta SOUND_STEP_TIMER,x          ; the envelopes' first step at the next centisecond
    lda #$00
    sta SOUND_PITCH_STEPS,x
    sta SOUND_AMPLITUDE_PHASE,x     ; attack
    sta SOUND_PITCH_OFFSET,x
    lda #$FF
    sta SOUND_PITCH_SECTION,x       ; the first step moves on to section 0
    jsr REMOVE_FROM_BUFFER
    sta SOUND_PITCH,x
    jsr REMOVE_FROM_BUFFER                       ; the duration
    plp
    pha
    lda SOUND_PITCH,x
    jsr SET_PITCH
    pla
START_NOTE_DURATION:
    sta SOUND_DURATION,x
    rts

;; The low bytes of the tone generators' periods for the twelve semitones of the lowest octave, from pitch 0
;; (period 1008, about 124 Hz), indexed by semitone; <SEMITONE_PERIODS_HIGH> holds the rest.
;;
;; The chip's tone is 4 MHz / 32 / the period, so a higher pitch has a smaller period.
;; See: <SET_PITCH>
SEMITONE_PERIODS_LOW:
    .byte <1008, <951, <898, <847, <800, <755, <712, <672, <635, <599, <565, <534

;; One semitone's byte in <SEMITONE_PERIODS_HIGH>.
;; Parameters:
;;   period = the semitone's period
;;   step = how much each quarter semitone above it takes off the period
;;   spare = bits 3-2, which <SET_PITCH> ignores
.macro SEMITONE period, step, spare
    .byte ((step) << 4) | ((spare) << 2) | ((period) >> 8)
.endmacro

;; The other half of <SEMITONE_PERIODS_LOW>, indexed by semitone: in bits 1-0 the period's top two bits, and in
;; bits 7-4 how much a quarter semitone takes off the period, about a quarter of the gap to the next semitone.
;; Bits 3-2 are not used.
;; See: <SET_PITCH>
SEMITONE_PERIODS_HIGH:
    SEMITONE 1008, 14, %01
    SEMITONE 951, 13, %01
    SEMITONE 898, 12, %10
    SEMITONE 847, 12, %00
    SEMITONE 800, 11, %01
    SEMITONE 755, 10, %10
    SEMITONE 712, 10, %00
    SEMITONE 672, 9, %10
    SEMITONE 635, 9, %00
    SEMITONE 599, 8, %10
    SEMITONE 565, 8, %00
    SEMITONE 534, 7, %10

; ---------------------------------------------------------------------------------------------------------------------
; The ROM filing system's ROMs and the speech processor
; ---------------------------------------------------------------------------------------------------------------------

;; Starts the ROM filing system's search over again: the next <RFS_NEXT_ROM> tries the first speech PHROM.
;; Out: A = <ROM_FS_ROM> = &EF
RFS_START_SEARCH:
    lda #$EF                        ; one before &F0, the first PHROM
    sta ROM_FS_ROM
    rts

;; Moves the ROM filing system on to its next ROM that holds files: the speech PHROMs &F0-&FF, then the paged ROMs.
;;
;; A PHROM holds files when bytes 1-4 are a zero and "(C)", which are checked against the paged ROMs' copyright
;; signature at <COPYRIGHT_SIGNATURE>; then the word at &3E in the PHROM is the address of its files. For the paged
;; ROMs, <ROM_FS_ROM> holds 15 less the ROM number (0 for ROM 15), and service call &0D asks them for it; the ROM that
;; takes the call sets ROM_FS_ROM and ROM_POINTER itself, and may skip ROM numbers that have no ROM. Falls into
;; <PHROM_FOLLOW_POINTER> for a PHROM.
;; Out: carry = clear when a ROM was found, set when there are no more
;; Uses: A, X, Y
;; See: <RFS_START_SEARCH>, <RFS_GET_BYTE>
RFS_NEXT_ROM:
    ldx #SERVICE_RFS_INITIALISE
    inc ROM_FS_ROM
    ldy ROM_FS_ROM
    bpl RFS_SERVICE                 ; on to the paged ROMs
    ldx #$00
    stx ROM_POINTER + 1
    inx
    stx ROM_POINTER                 ; address 1
    jsr PHROM_SET_ADDRESS
    ldx #$03
RFS_NEXT_ROM_CHECK:
    jsr PHROM_READ_BYTE
    cmp COPYRIGHT_SIGNATURE,x                     ; the signature is stored backwards
    bne RFS_NEXT_ROM                ; no PHROM there, or speech only
    dex
    bpl RFS_NEXT_ROM_CHECK
    lda #$3E
    sta ROM_POINTER                 ; the pointer to the files, at &003E

;; Points the speech PHROM at the address held at <ROM_POINTER> in it, for the ROM filing system and for speaking
;; words.
;;
;; The two bytes there are read low byte first, with each byte's bits in the reverse order, the form the speech
;; processor uses for addresses in its indirect commands.
;; In: ROM_POINTER = the address of the pointer, ROM_FS_ROM = the PHROM
;; Out: ROM_POINTER = the address the PHROM now has, carry = clear
;; Uses: A, X, Y
PHROM_FOLLOW_POINTER:
    jsr PHROM_SET_ADDRESS
    ldx #$FF
PHROM_FOLLOW_POINTER_BYTE:
    jsr PHROM_READ_BYTE
    ldy #$08
PHROM_FOLLOW_POINTER_BIT:
    asl a
    ror ROM_POINTER + 1,x           ; X = &FF: ROM_POINTER, then 0: ROM_POINTER+1
    dey
    bne PHROM_FOLLOW_POINTER_BIT
    inx
    beq PHROM_FOLLOW_POINTER_BYTE
    clc
    bcc PHROM_SET_ADDRESS           ; always taken

;; Reads the next byte from the ROM filing system's current ROM: from a speech PHROM through the speech processor,
;; or from a paged ROM through service call &0E.
;; Out: A/Y = the byte, carry = set when no paged ROM gave one
;; Uses: X
;; See: <RFS_NEXT_ROM>
RFS_GET_BYTE:
    ldx #SERVICE_RFS_BYTE_GET
    ldy ROM_FS_ROM
    bmi PHROM_READ_BYTE
    ldy #$FF

;; Issues a ROM filing system service call to the paged ROMs.
;; In: X = the service call, Y = its argument
;; Out: A/Y = the Y the ROMs returned, carry = clear when one took the call
;; Uses: X
RFS_SERVICE:
    php
    jsr ISSUE_SERVICE_CALL
    plp
    cmp #$01                        ; A = 0 when a ROM took it
    tya
    rts

;; Reads the byte at the speech PHROM's current address, which then moves on, with the speech processor's Read Byte
;; command.
;; Out: A/Y = the byte
;; Keeps: X
PHROM_READ_BYTE:
    php
    sei
    ldy #SPEECH_READ_BYTE
    jsr WRITE_SPEECH
    ldy #$00
    beq SPEECH_TRANSFER_PUSHED      ; always taken: read

;; OSBYTE &9E: reads a byte from the speech processor, its status, or a PHROM byte after a Read Byte command.
;; Out: Y = the byte; without a speech processor, nothing is read and Y = A
;; Uses: A
;; Keeps: X
READ_SPEECH:
    ldy #$00
    beq SPEECH_TRANSFER             ; always taken

;; Sends the speech processor a byte of a PHROM address, as two Load Address commands, low four bits first.
;; In: A = the byte
;; Uses: A, Y
;; Keeps: X
;; Entry: PHROM_LOAD_NIBBLE = sends only A's low four bits
PHROM_LOAD_BYTE:
    pha
    jsr PHROM_LOAD_NIBBLE
    pla
    ror a
    ror a
    ror a
    ror a                           ; the high four bits to the bottom
PHROM_LOAD_NIBBLE:
    and #$0F
    ora #SPEECH_LOAD_ADDRESS
    tay

;; OSBYTE &9F: writes a command or data byte to the speech processor.
;; In: Y = the byte
;; Uses: A, Y
;; Keeps: X
WRITE_SPEECH:
    tya
    ldy #$01

;; Reads or writes a byte over the slow data bus to the speech processor, with interrupts off.
;;
;; The speech processor's read or write select (latch bit 1 or 2) goes low, then the code waits for its ready line,
;; port B's bit 7, to go low, takes what is on the bus, and raises the select again. Nothing happens without a
;; speech processor (<SPEECH_PRESENT> zero).
;; In: Y = 0 to read, 1 to write, A = the byte to write
;; Out: A/Y = the byte on the bus: the one read, or A unchanged without a speech processor
;; Keeps: X
;; Entry: SPEECH_TRANSFER_PUSHED = for a caller that has pushed its flags and disabled interrupts
SPEECH_TRANSFER:
    php
    sei
SPEECH_TRANSFER_PUSHED:
    bit SPEECH_PRESENT
    bpl SPEECH_TRANSFER_DONE
    pha
    lda SPEECH_DIRECTIONS,y
    sta SYS_VIA_DDRA
    pla
    sta SYS_VIA_ORA_NH
    lda SPEECH_SELECTS,y
    sta SYS_VIA_ORB
SPEECH_TRANSFER_WAIT:
    bit SYS_VIA_ORB
    bmi SPEECH_TRANSFER_WAIT        ; until the ready line goes low
    lda SYS_VIA_ORA_NH
    pha
    lda SPEECH_DESELECTS,y
    sta SYS_VIA_ORB
    pla
SPEECH_TRANSFER_DONE:
    plp
    tay
    rts

;; Points the ROM filing system at the end of its current file, as the block header's spare bytes give it, for the
;; ROM filing system's quick search; for a PHROM, the speech processor is told the address.
;; Uses: A, Y
;; Keeps: X
RFS_SKIP_FILE:
    lda CFS_BLOCK_SPARE
    sta ROM_POINTER
    lda CFS_BLOCK_SPARE + 1
    sta ROM_POINTER + 1
    lda ROM_FS_ROM
    bpl PHROM_SET_ADDRESS_DONE      ; a paged ROM keeps its own pointer

;; Gives the speech processor the PHROM address in <ROM_POINTER> and the PHROM in <ROM_FS_ROM>.
;;
;; It sends five Load Address commands, four bits each: the address's fourteen bits, then the PHROM's number, the low
;; four bits of ROM_FS_ROM, above them.
;; Uses: A, Y
;; Keeps: X, carry
PHROM_SET_ADDRESS:
    php
    sei
    lda ROM_POINTER
    jsr PHROM_LOAD_BYTE
    lda ROM_FS_ROM
    sta OS_SCRATCH
    lda ROM_POINTER + 1
    rol a
    rol a                           ; drops the address's top two bits
    lsr OS_SCRATCH
    ror a
    lsr OS_SCRATCH
    ror a                           ; and puts the PHROM number's low two bits there
    jsr PHROM_LOAD_BYTE
    lda OS_SCRATCH
    jsr PHROM_LOAD_NIBBLE           ; the rest of the PHROM number
    plp
PHROM_SET_ADDRESS_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The keyboard
; ---------------------------------------------------------------------------------------------------------------------

;; Ends a pass of the keyboard code: while no key is held, re-enables the key-pressed interrupt and stops the timer
;; scanning the keyboard. Falls into <SET_KEYBOARD_LEDS>, which returns the flags this leaves, not the caller's.
;; Out: X = 0 when no key is held, &FF otherwise; A = the flags then: zero set and negative clear when no key is
;;   held, zero clear otherwise
END_KEYBOARD_SCAN:
    ldx #$FF
    lda LAST_KEY_PRESSED
    ora FIRST_KEY_PRESSED
    bne END_KEYBOARD_SCAN_1
    lda #$81
    sta SYS_VIA_IER                 ; enables CA2, the key-pressed interrupt
    inx
END_KEYBOARD_SCAN_1:
    stx KEYBOARD_SEMAPHORE          ; &FF while a key is held, so the timer scans; 0 otherwise

;; Lights the CAPS LOCK and SHIFT LOCK lights from <KEYBOARD_STATUS>, and leaves the keyboard scanning itself.
;;
;; The flags it was called with come back in A, and the negative and overflow flags are as they were, so the
;; KEYV entry that tests SHIFT and CTRL can return through here.
;; Out: A = the flags on entry, negative and overflow kept
;; Keeps: X, Y
SET_KEYBOARD_LEDS:
    php
    lda KEYBOARD_STATUS
    lsr a
    and #LATCH_HIGH | (KEY_STATUS_SHIFT_LOCK_OFF >> 1) ; CAPS LOCK off in bit 3, SHIFT LOCK off in bit 4
    ora #LATCH_CAPS_LOCK_LED
    sta SYS_VIA_ORB
    lsr a                           ; SHIFT LOCK off in bit 3
    ora #LATCH_SHIFT_LOCK_LED
    sta SYS_VIA_ORB
    jsr RESUME_AUTO_SCAN
    pla                             ; the flags; negative = their bit 7, the negative flag
    rts

;; The keyboard vector's default: tests SHIFT and CTRL, scans the keyboard, or handles the keyboard's interrupts.
;;
;; The entry conditions are the Advanced User Guide's:
;;
;; - carry clear, overflow clear: tests SHIFT and CTRL (<READ_SHIFT_CTRL>).
;; - carry set, overflow clear: scans the keyboard, as OSBYTE &79 (<KEYV_SCAN>).
;; - carry clear, overflow set: a key has been pressed (<KEY_PRESSED_INTERRUPT>).
;; - carry set, overflow set: the 100 Hz timer (<KEYBOARD_TIMER>).
;;
;; Both interrupt entries disable the key-pressed interrupt; <END_KEYBOARD_SCAN> enables it again when no key is
;; held.
;; In: carry, overflow = the entry, X = the key number for a scan
;; See: <KEYV>
KEYV_DEFAULT:
    bvc KEYV_DEFAULT_1
    lda #$01
    sta SYS_VIA_IER                 ; disables CA2, the key-pressed interrupt
    bcs KEYBOARD_TIMER
    jmp KEY_PRESSED_INTERRUPT
KEYV_DEFAULT_1:
    bcc READ_SHIFT_CTRL
    jmp KEYV_SCAN

;; The keyboard's work at each 100 Hz interrupt while a key is held: SHIFT and CTRL, the lock keys, two-key
;; rollover, auto-repeat, and the character for a key.
;;
;; <LAST_KEY_PRESSED> holds the most recent key and <FIRST_KEY_PRESSED> one pressed before it and still held. A key
;; number found by a scan has bit 7 clear; the next scan that still sees the key sets bit 7, so a key must be seen
;; twice before it counts. The last key is forgotten once it is seen released twice, but the first key on the first
;; scan that finds it released. A confirmed key gives its character when
;; <AUTO_REPEAT_TIMER> runs out: one centisecond after it is confirmed, then after the auto-repeat delay, then after
;; each auto-repeat period. CAPS LOCK and SHIFT LOCK change <KEYBOARD_STATUS> instead and do not repeat.
;;
;; The key's code comes from <KEY_TABLE>, then CTRL, SHIFT LOCK or CAPS LOCK (letters only) and SHIFT apply in that
;; order; when <KEY_STATUS_SHIFT_ENABLE> is clear, SHIFT has no effect while a lock has. While another key is held,
;; a key with CTRL or SHIFT gives nothing yet and tries again a centisecond later. The ESCAPE character does not
;; repeat. The character goes in the keyboard buffer unless OSBYTE &C9 has disabled the keyboard.
;;
;; Then, while there is room for another key, the keyboard is scanned for a new one, ignoring the keys already held.
;; When <FIRST_KEY_PRESSED> is free, the new key becomes the last and the old last becomes the first.
;; Uses: A, X, Y, OS_SCRATCH
;; Entry: READ_SHIFT_CTRL = KEYV with carry and overflow clear: returns with the negative flag set when CTRL is held
;;   and the overflow flag set when SHIFT is, and A holding the flags, leaving KEYBOARD_STATUS as it was
KEYBOARD_TIMER:
    inc KEYBOARD_SEMAPHORE          ; 0 while this runs: a nested timer interrupt does not scan
READ_SHIFT_CTRL:
    lda KEYBOARD_STATUS
    and #<~(KEY_STATUS_SHIFT | KEY_STATUS_CTRL)
    ldx #SHIFT_KEY
    jsr TEST_KEY
    stx OS_SCRATCH                  ; bit 7 = SHIFT, for CAPS LOCK below
    clv
    bpl KEYBOARD_TIMER_CTRL
    bit OVERFLOW_BYTE               ; overflow = SHIFT
    ora #KEY_STATUS_SHIFT
KEYBOARD_TIMER_CTRL:
    inx                             ; CTRL_KEY (bit 7 is not sent to the keyboard)
    jsr TEST_KEY
    bcc SET_KEYBOARD_LEDS           ; only testing: negative = CTRL
    bpl KEYBOARD_TIMER_KEYS
    ora #KEY_STATUS_CTRL
KEYBOARD_TIMER_KEYS:
    sta KEYBOARD_STATUS
    ldx LAST_KEY_PRESSED
    beq KEYBOARD_TIMER_TO_FIRST
    jsr TEST_KEY
    bmi KEYBOARD_TIMER_HELD
    cpx LAST_KEY_PRESSED            ; released: was it released last time too (bit 7 already clear)?
KEYBOARD_TIMER_SET_LAST:
    stx LAST_KEY_PRESSED
    bne KEYBOARD_TIMER_TO_FIRST     ; changed: wait for the next scan to confirm it
    ldx #$00                        ; released twice running
    stx LAST_KEY_PRESSED
KEYBOARD_TIMER_RETRY:
    jsr START_AUTO_REPEAT
KEYBOARD_TIMER_TO_FIRST:
    jmp KEYBOARD_TIMER_FIRST
KEYBOARD_TIMER_HELD:
    cpx LAST_KEY_PRESSED
    bne KEYBOARD_TIMER_SET_LAST     ; seen twice: now confirmed, with bit 7 set
    lda AUTO_REPEAT_TIMER
    beq KEYBOARD_TIMER_NO_CHARACTER ; not repeating
    dec AUTO_REPEAT_TIMER
    bne KEYBOARD_TIMER_NO_CHARACTER
    lda FIRST_AUTO_REPEAT           ; time for a character; the delay comes next, then the period
    sta AUTO_REPEAT_TIMER
    lda AUTO_REPEAT_PERIOD
    sta FIRST_AUTO_REPEAT
    lda KEYBOARD_STATUS
    ldx LAST_KEY_PRESSED
    cpx #SHIFT_LOCK_KEY | KEY_DOWN
    bne KEYBOARD_TIMER_CAPS_LOCK
    ora #KEY_STATUS_SHIFT_ENABLE | KEY_STATUS_CAPS_LOCK_OFF
    eor #KEY_STATUS_SHIFT_ENABLE | KEY_STATUS_SHIFT_LOCK_OFF ; SHIFT LOCK changes, CAPS LOCK goes off
KEYBOARD_TIMER_LOCKS:
    sta KEYBOARD_STATUS
    lda #$00
    sta AUTO_REPEAT_TIMER           ; the lock keys do not repeat
KEYBOARD_TIMER_NO_CHARACTER:
    jmp KEYBOARD_TIMER_FIRST
KEYBOARD_TIMER_CAPS_LOCK:
    cpx #CAPS_LOCK_KEY | KEY_DOWN
    bne KEYBOARD_TIMER_TRANSLATE
    ora #KEY_STATUS_SHIFT_ENABLE | KEY_STATUS_SHIFT_LOCK_OFF
    bit OS_SCRATCH
    bpl KEYBOARD_TIMER_TOGGLE_CAPS
    ora #KEY_STATUS_CAPS_LOCK_OFF   ; with SHIFT: CAPS LOCK on, with SHIFT enabled
    eor #KEY_STATUS_SHIFT_ENABLE
KEYBOARD_TIMER_TOGGLE_CAPS:
    eor #KEY_STATUS_SHIFT_ENABLE | KEY_STATUS_CAPS_LOCK_OFF ; without: CAPS LOCK changes, SHIFT not enabled
    jmp KEYBOARD_TIMER_LOCKS
KEYBOARD_TIMER_TRANSLATE:
    lda KEY_TABLE - KEY_DOWN,x      ; X = the key number plus &80
    bne KEYBOARD_TIMER_MODIFIERS
    lda TAB_CHARACTER               ; TAB's entry is 0
KEYBOARD_TIMER_MODIFIERS:
    ldx KEYBOARD_STATUS
    stx OS_SCRATCH                  ; shifted left to test CTRL, SHIFT LOCK, CAPS LOCK and SHIFT in turn
    rol OS_SCRATCH
    bpl KEYBOARD_TIMER_SHIFT_LOCK   ; no CTRL
    ldx FIRST_KEY_PRESSED
KEYBOARD_TIMER_WAIT:
    bne KEYBOARD_TIMER_RETRY        ; another key is held: try again in a centisecond
    jsr CTRL_CHARACTER
KEYBOARD_TIMER_SHIFT_LOCK:
    rol OS_SCRATCH
    bmi KEYBOARD_TIMER_CAPS         ; SHIFT LOCK off
    jsr SHIFT_CHARACTER
    rol OS_SCRATCH                  ; past the CAPS LOCK bit
    jmp KEYBOARD_TIMER_SHIFT_ENABLE
KEYBOARD_TIMER_CAPS:
    rol OS_SCRATCH
    bmi KEYBOARD_TIMER_SHIFT        ; CAPS LOCK off
    jsr CHECK_LETTER                       ; carry = clear for a letter
    bcs KEYBOARD_TIMER_SHIFT
    jsr SHIFT_CHARACTER             ; a capital
KEYBOARD_TIMER_SHIFT_ENABLE:
    ldx KEYBOARD_STATUS
    bpl KEYBOARD_TIMER_ESCAPE       ; a lock has acted, and SHIFT does not reverse it
KEYBOARD_TIMER_SHIFT:
    rol OS_SCRATCH
    bpl KEYBOARD_TIMER_ESCAPE       ; no SHIFT
    ldx FIRST_KEY_PRESSED
    bne KEYBOARD_TIMER_WAIT
    jsr SHIFT_CHARACTER
KEYBOARD_TIMER_ESCAPE:
    cmp ESCAPE_CHARACTER
    bne KEYBOARD_TIMER_INSERT
    ldx ESCAPE_KEY_STATUS
    bne KEYBOARD_TIMER_INSERT       ; ESCAPE is an ordinary character
    stx AUTO_REPEAT_TIMER           ; ESCAPE does not repeat
KEYBOARD_TIMER_INSERT:
    tay
    jsr KEYBOARD_INTERRUPT_WINDOW
    lda KEYBOARD_DISABLE
    bne KEYBOARD_TIMER_FIRST
    jsr INSERT_KEY                       ; puts Y in the keyboard buffer
KEYBOARD_TIMER_FIRST:
    ldx FIRST_KEY_PRESSED
    beq KEYBOARD_TIMER_FIND_KEY
    jsr TEST_KEY
    stx FIRST_KEY_PRESSED
    bmi KEYBOARD_TIMER_FIND_KEY     ; still held
    ldx #$00
    stx FIRST_KEY_PRESSED
KEYBOARD_TIMER_FIND_KEY:
    ldx FIRST_KEY_PRESSED
    bne FIND_SECOND_KEY
    ldy #LAST_KEY_PRESSED
    jsr SCAN_FOR_NEW_KEY            ; any key but the last
    bmi KEYBOARD_TIMER_DONE
    lda LAST_KEY_PRESSED
    sta FIRST_KEY_PRESSED           ; the last becomes the first
KEYBOARD_TIMER_NEW_KEY:
    stx LAST_KEY_PRESSED
    jsr START_AUTO_REPEAT
KEYBOARD_TIMER_DONE:
    jmp END_KEYBOARD_SCAN

;; KEYV's key-pressed interrupt entry: takes the key that was pressed as the last key, unless one is held already,
;; and starts the timer's scanning.
;; Uses: A, X, Y
;; Entry: FIND_SECOND_KEY = with a first key held, scans for another key as the last one, for <KEYBOARD_TIMER>
KEY_PRESSED_INTERRUPT:
    jsr TEST_KEY                    ; for its setting up of the keyboard; the result is not used
FIND_SECOND_KEY:
    lda LAST_KEY_PRESSED
    bne KEYBOARD_TIMER_DONE
    ldy #FIRST_KEY_PRESSED
    jsr SCAN_FOR_NEW_KEY            ; any key but the first
    bmi KEYBOARD_TIMER_DONE
    bpl KEYBOARD_TIMER_NEW_KEY      ; always taken

;; Starts the auto-repeat over: the next character comes at the next centisecond, then after the auto-repeat delay.
;; Uses: X
START_AUTO_REPEAT:
    ldx #$01
    stx AUTO_REPEAT_TIMER
    ldx AUTO_REPEAT_DELAY
    stx FIRST_AUTO_REPEAT
    rts

;; Tests one key, with the keyboard set for the CPU to test keys.
;;
;; The key number goes out on the slow data bus, row in bits 6-4 and column in bits 3-0, and the keyboard pulls
;; bit 7, the one input, high when that key is down. The keyboard stays in this state until <RESUME_AUTO_SCAN>.
;; In: X = the internal key number (bit 7 is ignored)
;; Out: X = the key number, with bit 7 set when the key is pressed, negative = pressed
;; Uses: Y
;; Keeps: A, carry, overflow
TEST_KEY:
    ldy #LATCH_KEYBOARD             ; low: the CPU tests keys
    sty SYS_VIA_ORB
    ldy #$7F
    sty SYS_VIA_DDRA                ; port A's bit 7 an input, the rest outputs
    stx SYS_VIA_ORA_NH
    ldx SYS_VIA_ORA_NH
    rts

;; The keyboard translation table, the character each key gives before CTRL, SHIFT and the locks, indexed by
;; internal key number (the Advanced User Guide's appendix C); OSBYTE &AC and &AD read its address.
;;
;; The keys are numbered by their row on the keyboard's matrix, in the high nibble, and their column, 0-9, in the
;; low, so each row of the table is ten bytes, &x0-&x9, at sixteen-byte intervals. <KEYBOARD_TIMER> translates only
;; keys &10 and up; row 0, which would hold SHIFT, CTRL and the links, is the code of <TEST_KEY> that comes before.
;; The six bytes between rows hold short pieces of code and data, each documented where it is.
;;
;; TAB's entry is 0, which means the character in <TAB_CHARACTER>. CAPS LOCK's and SHIFT LOCK's entries, 1 and 2,
;; are never used: the keys are handled before the table is read.
;; See: <KEY_TABLE_ADDRESS>, <SHIFT_CHARACTER>, <CTRL_CHARACTER>
KEY_TABLE = TEST_KEY + 1

.assert KEY_TABLE = $F02B, "The keyboard translation table moved."

;; One row of <KEY_TABLE>: checks that it starts where the row's key numbers put it.
;; Parameters:
;;   row = the first key number of the row, &10-&70
;;   k0 = the code for column 0, and k1-k9 for columns 1-9
.macro KEY_ROW row, k0, k1, k2, k3, k4, k5, k6, k7, k8, k9
    .assert * = KEY_TABLE + (row), "A KEY_ROW is out of place."
    .byte k0, k1, k2, k3, k4, k5, k6, k7, k8, k9
.endmacro

    ;       Q    3    4    5    f4          8    f7          -    ^    LEFT
    KEY_ROW $10, 'q', '3', '4', '5', KEY_F0 + 4, '8', KEY_F0 + 7, '-', '^', KEY_LEFT

;; OSBYTE &78: writes the keys pressed, for two-key rollover.
;; In: X = the first key, for <FIRST_KEY_PRESSED>, Y = the last, for <LAST_KEY_PRESSED>
;; Keeps: A, X, Y
WRITE_KEYS_PRESSED:
    sty LAST_KEY_PRESSED
    stx FIRST_KEY_PRESSED
    rts
    .byte $00                       ; not used

    ;       f0      W    E    T    7    I    9    0    _    DOWN
    KEY_ROW $20, KEY_F0, 'w', 'e', 't', '7', 'i', '9', '0', '_', KEY_DOWN_CURSOR

;; Jumps through <JIM_VECTOR>, for reset: when an interrupt comes in during the moment reset enables them, the
;; interrupt code leaves &7F in IRQ_A, and reset calls this to let something on the 1 MHz bus deal with it.
CALL_JIM_VECTOR:
    jmp (JIM_VECTOR)

;; Jumps to the address in <OS_SCRATCH>, for OSBYTE's dispatch: a JSR here calls it.
CALL_OS_SCRATCH:
    jmp (OS_SCRATCH)

    ;       1    2    D    R    6    U    O    P    [    UP
    KEY_ROW $30, '1', '2', 'd', 'r', '6', 'u', 'o', 'p', '[', KEY_UP

;; Calls <KEYV> with overflow set, for the keyboard's interrupt entries.
;; In: carry = set for the timer, clear for a key pressed
;; Entry: CALL_KEYV = calls KEYV with the flags as they are
CALL_KEYV_INTERRUPT:
    bit OVERFLOW_BYTE               ; sets overflow
CALL_KEYV:
    jmp (KEYV)

    ;       CAPS LOCK  A    X    F    Y    J    K    @    :    RETURN
    KEY_ROW $40, $01, 'a', 'x', 'f', 'y', 'j', 'k', '@', ':', $0D

;; The system VIA's port A data direction for a speech transfer, indexed by Y: all inputs to read, all outputs to
;; write.
;; See: <SPEECH_TRANSFER>
SPEECH_DIRECTIONS:
    .byte $00, $FF

;; The latch write that starts a speech transfer, indexed by Y: the read or write select low.
SPEECH_SELECTS:
    .byte LATCH_SPEECH_READ, LATCH_SPEECH_WRITE

;; The latch write that ends a speech transfer, indexed by Y: the read or write select high again.
SPEECH_DESELECTS:
    .byte LATCH_SPEECH_READ | LATCH_HIGH, LATCH_SPEECH_WRITE | LATCH_HIGH

    ;       SHIFT LOCK  S    C    G    H    N    L    ;    ]    DELETE
    KEY_ROW $50, $02, 's', 'c', 'g', 'h', 'n', 'l', ';', ']', $7F

;; OSBYTE &83: reads OSHWM, the page where user memory starts.
;; Out: X = 0, Y = <OSHWM>
READ_OSHWM:
    ldy OSHWM
    ldx #$00
    rts

    ;       TAB  Z    SPACE  V    B    M    ,    .    /    COPY
    KEY_ROW $60, $00, 'z', ' ', 'v', 'b', 'm', ',', '.', '/', KEY_COPY

;; Flushes the current input buffer, the keyboard's or RS-423's as <INPUT_SOURCE> says, for OSBYTE &0F.
;; Entry: GO_FLUSH_BUFFER = flushes buffer X, through <FLUSH_BUFFER>
FLUSH_INPUT_BUFFER:
    ldx INPUT_SOURCE
GO_FLUSH_BUFFER:
    jmp FLUSH_BUFFER

    ;       ESCAPE  f1          f2          f3          f5          f6          f8          f9          \    RIGHT
    KEY_ROW $70, $1B, KEY_F0 + 1, KEY_F0 + 2, KEY_F0 + 3, KEY_F0 + 5, KEY_F0 + 6, KEY_F0 + 8, KEY_F0 + 9, '\', KEY_RIGHT

;; Calls the event vector, for OSEVEN.
;; See: <EVNTV>
CALL_EVNTV:
    jmp (EVNTV)

;; OSBYTE &0F: flushes all the buffers (X = 0) or the current input buffer (X nonzero).
;;
;; Interrupts are let in between buffers.
;; In: X = which, zero = set when X is 0
;; Uses: A, X, Y
;; Entry: FLUSH_ALL_BUFFERS = flushes buffers 8 down to 0
FLUSH_BUFFERS:
    bne FLUSH_INPUT_BUFFER
FLUSH_ALL_BUFFERS:
    ldx #$08
FLUSH_ALL_BUFFERS_LOOP:
    cli
    sei
    jsr FLUSH_SPECIFIC_BUFFER
    dex
    bpl FLUSH_ALL_BUFFERS_LOOP
    ; Falls through with X = &FF, which FLUSH_SPECIFIC_BUFFER ignores.

;; OSBYTE &15: flushes buffer X, if there is one (0-8).
;; In: X = the buffer number
;; Uses: A, Y
FLUSH_SPECIFIC_BUFFER:
    cpx #$09
    bcc GO_FLUSH_BUFFER
    rts

;; *HELP: offers the command to the paged ROMs with service call 9, then prints the MOS's version.
;;
;; The version goes through <PRINT_INLINE>, which prints a string from after its JSR only when Y is nonzero, as the
;; offset of the rest of the command line is.
;; In: TEXT_POINTER = the command line, Y = the offset of what follows HELP
;; Uses: A, X, Y
HELP_COMMAND:
    ldx #SERVICE_HELP
    jsr ISSUE_SERVICE_CALL
    jsr PRINT_INLINE
    .byte $0D, "OS 1.20", $0D, 0
    rts

;; Scans the keyboard for a newly pressed key, for <KEYBOARD_TIMER> and <KEY_PRESSED_INTERRUPT>.
;; In: Y = LAST_KEY_PRESSED or FIRST_KEY_PRESSED, the zero page byte holding the key to ignore
;; Out: X/A = the key number, or &FF for none, negative = none
;; Uses: Y
;; Entry:
;;   SCAN_FROM_16 = OSBYTE &7A: scans through <KEYV> from key 16
;;   SCAN_KEYBOARD = OSBYTE &79: scans through KEYV as X says
SCAN_FOR_NEW_KEY:
    clc
SCAN_FROM_16:
    ldx #FIRST_CHARACTER_KEY
SCAN_KEYBOARD:
    bcs CALL_KEYV                   ; OSBYTE's calls arrive with carry set

;; KEYV with carry set and overflow clear: scans the keyboard, or tests one key, as OSBYTE &79 does.
;;
;; With X negative, it tests key X EOR &80. Otherwise it looks for a pressed key numbered X or more: OSBYTE's scan,
;; with carry set, takes the first it reaches, and only <SCAN_FOR_NEW_KEY>'s, with carry clear, passes over the key
;; in <LAST_KEY_PRESSED> or <FIRST_KEY_PRESSED>. It goes down the columns from 9 to 0: a pressed key in the
;; selected column raises CA2, and only then are the column's rows tested, from the lowest key number, so the key
;; found is the first of its column. Interrupts are let in between columns, so each kind of scan keeps the key number
;; it started from in its own byte of <ROLLOVER_WORK>.
;; In: X = the key number, or the key number EOR &80 to test one key, carry = set (clear for SCAN_FOR_NEW_KEY)
;; Out: X/A = the key number found, &FF for none, negative = none; for one key, X = the key with bit 7 set when it
;;   is pressed
;; Uses: Y
KEYV_SCAN:
    txa
    bpl KEYV_SCAN_MATRIX
    jsr TEST_KEY
    bcs RESUME_AUTO_SCAN            ; always taken
KEYV_SCAN_MATRIX:
    php
    bcc KEYV_SCAN_START
    ldy #OSBYTE_SCAN_SELECTOR       ; OSBYTE's byte of ROLLOVER_WORK
KEYV_SCAN_START:
    sta ROLLOVER_WORK - LAST_KEY_PRESSED,y ; the lowest key number to report, for this kind of scan
    ldx #$09
KEYV_SCAN_COLUMN:
    jsr KEYBOARD_INTERRUPT_WINDOW
    lda #$7F
    sta SYS_VIA_DDRA
    lda #LATCH_KEYBOARD             ; low: the CPU tests keys
    sta SYS_VIA_ORB
    lda #$0F
    sta SYS_VIA_ORA_NH              ; column 15, which has no keys
    lda #$01
    sta SYS_VIA_IFR                 ; clears CA2
    stx SYS_VIA_ORA_NH              ; column X
    bit SYS_VIA_IFR
    beq KEYV_SCAN_NEXT_COLUMN       ; no CA2: no key down in the column
    txa
KEYV_SCAN_ROW:
    cmp ROLLOVER_WORK - LAST_KEY_PRESSED,y
    bcc KEYV_SCAN_NEXT_ROW          ; below the first key to report
    sta SYS_VIA_ORA_NH
    bit SYS_VIA_ORA_NH
    bpl KEYV_SCAN_NEXT_ROW          ; not pressed
    plp
    php
    bcs KEYV_SCAN_DONE              ; KEYV's scan: found
    pha
    eor a:$0000,y                   ; Y = &EC or &ED: the key held already, in zero page
    asl a                           ; bit 7, a key's confirmation, does not count
    cmp #$01                        ; carry = set when it is another key
    pla
    bcs KEYV_SCAN_DONE
KEYV_SCAN_NEXT_ROW:
    clc
    adc #$10
    bpl KEYV_SCAN_ROW
KEYV_SCAN_NEXT_COLUMN:
    dex
    bpl KEYV_SCAN_COLUMN
    txa                             ; &FF: none
KEYV_SCAN_DONE:
    tax
    plp

;; Leaves the keyboard scanning itself and lets any waiting interrupt in, then falls into <RESUME_AUTO_SCAN>.
;; Out: A = X
;; Keeps: X, Y
KEYBOARD_INTERRUPT_WINDOW:
    jsr RESUME_AUTO_SCAN
    cli
    sei

;; Leaves the keyboard scanning itself: it then raises CA2, the key-pressed interrupt, when any key is down.
;; Out: A = X
;; Keeps: X, Y
RESUME_AUTO_SCAN:
    lda #LATCH_KEYBOARD | LATCH_HIGH
    sta SYS_VIA_ORB
    txa
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Selecting the cassette and ROM filing systems, and the paged ROM service calls
; ---------------------------------------------------------------------------------------------------------------------

;; OSBYTE &8C and &8D, *TAPE and *ROM: select the cassette filing system or the ROM filing system.
;;
;; Both share the cassette filing system's code, and <CFS_RFS_SWITCH> tells it which it is. *TAPE3 (X = 3) sets 300
;; baud; any other X sets 1200 baud.
;; In: A = &8C for the cassette, &8D for ROMs, X = 3 for 300 baud
;; Uses: A, X, Y
;; Entry: SELECT_TAPE_OR_ROM_1 = with A = 0 for the cassette, 1 for ROMs, for reset
SELECT_TAPE_OR_ROM:
    eor #$8C
SELECT_TAPE_OR_ROM_1:
    asl a
    sta CFS_RFS_SWITCH              ; 0 for the cassette, 2 for ROMs
    cpx #$03                        ; zero = set for 300 baud
    jmp START_TAPE_FS

;; Sets the cassette's *OPT settings to their defaults and selects the cassette filing system, for reset. Falls into
;; <START_TAPE_FS>.
;; In: zero = set for 300 baud
;; Uses: A, X, Y
RESET_TAPE_OPTIONS:
    php
    lda #$A1
    sta CFS_OPTIONS                 ; the messages and errors that *OPT 1 and 2 give by default
    lda #$19
    sta CFS_BLOCK_GAP               ; 2.5 seconds between blocks
    plp

;; Makes the cassette filing system's code the filing system: warns the old filing system, sets the cassette's speed
;; and the vectors from <FILEV> to <FSCV>, and tells the paged ROMs with service call &0F.
;; In: zero = set for 300 baud, clear for 1200
;; Uses: A, X, Y
START_TAPE_FS:
    php
    lda #FSC_NEW_FILING_SYSTEM
    jsr CALL_FSCV                       ; FSCV
    ldx #$06                        ; the 6850 divides its clock by 64: 300 baud
    plp
    beq START_TAPE_FS_1
    dex                             ; by 16: 1200 baud
START_TAPE_FS_1:
    stx FS_WORKSPACE + 6
    ldx #FSCV + 2 - FILEV
START_TAPE_FS_VECTORS:
    lda DEFAULT_VECTORS + FILEV - USERV - 1,x
    sta FILEV - 1,x
    dex
    bne START_TAPE_FS_VECTORS
    stx FS_WORKSPACE + 2
    ldx #SERVICE_VECTORS_CLAIMED
    ; Falls through into ISSUE_SERVICE_CALL.

;; OSBYTE &8F: issues a paged ROM service call to each paged ROM with a service entry, from ROM 15 down, until one
;; takes it.
;;
;; Each ROM is entered at <SERVICE_ENTRY> with A = the call, X = its own number and Y = the argument, and takes the
;; call by returning A = 0. The ROM that was selected is selected again afterwards.
;; In: X = the service call, Y = its argument
;; Out: X/A = 0 when a ROM took the call, otherwise &FF, not the call; zero = set when one took it; Y = as the ROMs
;;   left it
;; See: <ROM_TYPE_TABLE>
ISSUE_SERVICE_CALL:
    lda ROMSEL_COPY
    pha
    txa
    ldx #$0F
ISSUE_SERVICE_CALL_LOOP:
    inc ROM_TYPE_TABLE,x
    dec ROM_TYPE_TABLE,x            ; negative = bit 7, a service entry, without changing A
    bpl ISSUE_SERVICE_CALL_NEXT
    stx ROMSEL_COPY
    stx ROMSEL
    jsr SERVICE_ENTRY
    tax
    beq ISSUE_SERVICE_CALL_DONE     ; taken
    ldx ROMSEL_COPY
ISSUE_SERVICE_CALL_NEXT:
    dex
    bpl ISSUE_SERVICE_CALL_LOOP
ISSUE_SERVICE_CALL_DONE:
    pla
    sta ROMSEL_COPY
    sta ROMSEL
    txa
    rts
