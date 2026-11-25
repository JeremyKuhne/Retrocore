;; SERIAL I/O, SIO ($E944-$EDE9)
;;
;; SIOINV's initialization and SIOV's serial bus driver, which every handler that talks to a device on the bus (the
;; disk, the printer, the cassette) calls with the device control block at DDEVIC filled in.
;;
;; - For a bus device, <SIO_MAIN> sends the four-byte command frame (CDEVIC-CAUX2) with the command line asserted,
;;   and waits for ACK; it sends the data frame, if any, and waits for ACK again; then it waits for COMPLETE (or
;;   ERROR) and receives the data frame, if any. Each frame is its bytes and a checksum, their sum with end-around
;;   carry. The command frame is tried up to 14 times (CRETRY), and the whole command twice (DRETRY).
;; - The bytes go out and come in through POKEY's serial interrupts: <SIO_OUTPUT_NEEDED> (VSEROR),
;;   <SIO_OUTPUT_FINISHED> (VSEROC) and <SIO_INPUT_READY> (VSERIN). The caller waits for their flags, with system
;;   timer 1 as the timeout (<SIO_START_TIMER>, <SIO_TIMEOUT>) and BREAK as the way out (<SIO_BREAK>).
;; - For the cassette (DDEVIC = $60, CASFLG set), <SIO_CASSETTE> runs the motor, writes or skips the leader, and sends
;;   or receives one record with no command, acknowledgement or retry. Before receiving it measures the tape's baud
;;   rate from the record's two $55 bytes (<SIO_MEASURE_BAUD>), with TIMER1, TIMER2 and VCOUNT.
;; - While SOUNDR is nonzero, POKEY's channels play the serial traffic: channel 4 for the bus, and the two tones as
;;   well for the cassette.
;;
;; The OS User's Manual describes the protocol and the variables (section 9 and appendix L). The source is maintained
;; by hand and assembles byte-identically to rev. A, rev. B and the PAL OS.
;;
;; Rev. B tests for a frame's end with one 16-bit comparison instead of rev. A's two 8-bit ones, and sets TIMFLG only
;; once system timer 1 has been set. The PAL OS times the cassette's leaders and measures its baud rate for 50 Hz
;; frames of 312 lines.

; The device and the protocol.

SIO_COMMAND_RETRIES = 13            ;; CRETRY's start: the command frame is sent up to 14 times
SIO_DEVICE_RETRIES = 1              ;; DRETRY's start: the whole command is tried twice
SIO_ACK = 'A'                       ;; the device's acknowledgement of a frame
SIO_COMPLETE = 'C'                  ;; the device's report that the command has completed
SIO_ERROR = 'E'                     ;; the device's report that the command failed
SIO_ACK_TIMEOUT = 2                 ;; how long a device has to acknowledge a frame, in vertical blanks
SIO_SYSTEM_TIMER_1 = 1              ;; SETVBV's number for system timer 1, CDTMV1

; POKEY's set-up for the serial port and the noise.

SIO_BUS_DIVIDER = $0028             ;; AUDF3/AUDF4's divider for the bus's 19,200 baud
SIO_CASSETTE_DIVIDER = $05CC        ;; AUDF3/AUDF4's divider for the cassette's 600 baud
SIO_AUDCTL = $28                    ;; AUDCTL: channel 3 clocked at 1.79 MHz and joined to channel 4
SIO_MARK_DIVIDER = 5                ;; AUDF1's divider for the cassette's mark tone, 5327 Hz
SIO_SPACE_DIVIDER = 7               ;; AUDF2's divider for the cassette's space tone, 3995 Hz
SIO_AUDC_NOISY = $A8                ;; a pure tone at volume 8, for channels that play the serial traffic
SIO_AUDC_QUIET = $A0                ;; a pure tone at volume 0
SIO_SKCTL_KEYBOARD = $03            ;; SKCTL's keyboard debounce and scanning, with the serial port idle
SIO_SKCTL_KEEP = $07                ;; SKCTL's bits kept from SSKCTL: the keyboard and the paddles' scan
SIO_SKCTL_TWO_TONE = $08            ;; SKCTL's two-tone mode: channels 1 and 2 send the cassette's mark and space
SIO_SKCTL_RECEIVE = $10             ;; SKCTL's serial mode for receiving, asynchronous at channel 4's rate
SIO_SKCTL_SEND = $20                ;; SKCTL's serial mode for sending, clocked by channel 4
SIO_SKSTAT_OVERRUN = $20            ;; SKSTAT's bit 5, 0 after a serial input overrun
SIO_SKSTAT_INPUT = $10              ;; SKSTAT's bit 4, the serial input line's level

; POKEY's serial interrupts, in IRQEN and POKMSK.

SIO_IRQ_SERIAL = IRQ_SERIAL_INPUT | IRQ_SERIAL_OUTPUT | IRQ_SERIAL_DONE ;; the three serial interrupts

; The PIA's control values for the cassette motor (PACTL) and the command line (PBCTL).

SIO_LINE_OFF = $3C                  ;; CA2 or CB2 an output held high: the motor stopped, the command line released
SIO_LINE_ON = $34                   ;; CA2 or CB2 an output held low: the motor running, the command line asserted

; The cassette's leader and baud rate. The leaders are counted in vertical blanks, so the PAL OS, at 50 a second
; rather than 60, counts five sixths as many for the same time; and a PAL frame has 312 lines, not 262, so VCOUNT
; counts 156 line pairs a frame, not 131. A line pair lasts about as long on both, so the dividers stay the same.

.if VERSION = VERSION_PAL
SIO_WRITE_LEADER = 150              ;; the tone written before a record with normal gaps, in vertical blanks (3 s)
SIO_WRITE_SHORT_LEADER = 13         ;; the tone written before a record with short gaps
SIO_READ_LEADER = 100               ;; the tape skipped before reading a record with normal gaps (2 s)
SIO_READ_SHORT_LEADER = 8           ;; the tape skipped before reading a record with short gaps
SIO_LINE_PAIRS = 156                ;; the line pairs in a frame, as VCOUNT counts them (PAL)
.else
SIO_WRITE_LEADER = 180              ;; the tone written before a record with normal gaps, in vertical blanks (3 s)
SIO_WRITE_SHORT_LEADER = 15         ;; the tone written before a record with short gaps
SIO_READ_LEADER = 120               ;; the tape skipped before reading a record with normal gaps (2 s)
SIO_READ_SHORT_LEADER = 10          ;; the tape skipped before reading a record with short gaps
SIO_LINE_PAIRS = 131                ;; the line pairs in a frame, as VCOUNT counts them (NTSC)
.endif
SIO_LEADER_BYTE = $55               ;; each of a record's first two bytes, alternate bits for the baud measurement
SIO_BAUD_EDGES = 10                 ;; the input's changes timed for the baud rate: ten bits
SIO_VBLANK_LINE = $7C               ;; the VCOUNT at which the vertical blank counts RTCLOK up
SIO_DIVIDER_STEP = 11               ;; the divider's change for each line pair the ten bits take
SIO_BAUD_FIRST_COUNT = 88           ;; the line-pair count of <SIO_BAUD_TABLE>'s first entry
SIO_POKEY_OFFSET = 7                ;; what POKEY adds to a 1.79 MHz channel's divider

;; SIOINV: initializes SIO, at power-up and SYSTEM RESET: stops the cassette motor, releases the command line, sets
;; POKEY's serial port idle with the keyboard scanning, and makes serial I/O noisy.
;; Out: SOUNDR = 3, SSKCTL = 3
;; Uses: A
;; Keeps: X, Y
;; See: <SIOINV>, <SIO_MAIN>
SIO_INIT:
    lda #SIO_LINE_OFF
    sta PACTL
    lda #SIO_LINE_OFF
    sta PBCTL
    lda #SIO_SKCTL_KEYBOARD
    sta SSKCTL
    sta SOUNDR                      ; 3, nonzero: noisy
    sta SKCTL
    rts

;; SIOV: runs the command in the device control block (DDEVIC-DAUX2) on its serial bus device, or on the cassette.
;;
;; The command frame goes out with the command line asserted, and is sent again, up to <SIO_COMMAND_RETRIES> more
;; times, until the device acknowledges it. For a write (DSTATS bit 7) the data frame from DBUFLO/DBUFHI, DBYTLO/DBYTHI
;; long, follows, and must be acknowledged too. Then the device has DTIMLO seconds to answer COMPLETE or ERROR, and
;; for a read (DSTATS bit 6) to send the data frame. A failure tries the whole command once more
;; (<SIO_DEVICE_RETRIES>). The cassette goes to <SIO_CASSETTE> instead. Interrupts run throughout, with CRITIC set
;; to keep the vertical blank short; BREAK ends the command at once through <SIO_BREAK>.
;; In: DDEVIC..DAUX2 = the command, DSTATS = $80 to send data, $40 to receive it, 0 for neither
;; Out: Y = the status, DSTATS = the status, negative = set on an error
;; Uses: A, X, CDEVIC..TEMP, CRETRY, DRETRY, ERRFLG, TSTAT, STATUS, CASFLG
;; Errors: DSTATS = TIMOUT, DNACK, DERROR, FRMERR, OVRRUN, CHKERR or BRKABT
;; Entry:
;;   SIO_MAIN_DONE = stops the serial interrupts and the noise and returns STATUS, for the cassette and BREAK
;; See: <SIOV>, <SIO_CASSETTE>, <SIO_SEND_AND_WAIT>, <SIO_RECEIVE_FRAME>
SIO_MAIN:
    tsx
    stx STACKP                      ; for SIO_BREAK to return from anywhere
    lda #1
    sta CRITIC
    lda DDEVIC
    cmp #CASSETTE_ID
    bne SIO_MAIN_BUS
    jmp SIO_CASSETTE
SIO_MAIN_BUS:
    lda #0
    sta CASFLG
    lda #SIO_DEVICE_RETRIES
    sta DRETRY
SIO_MAIN_RETRY_COMMAND:
    lda #SIO_COMMAND_RETRIES
    sta CRETRY
SIO_MAIN_SEND_COMMAND:
    lda #<SIO_BUS_DIVIDER
    sta AUDF3
    lda #>SIO_BUS_DIVIDER
    sta AUDF4
    clc
    lda DDEVIC
    adc DUNIT
    adc #$FF                        ; less 1: drive 1 is the device ID itself
    sta CDEVIC
    lda DCOMND
    sta CCOMND
    lda DAUX1
    sta CAUX1
    lda DAUX2
    sta CAUX2
    clc
    lda #<CDEVIC                    ; the command frame, CDEVIC-CAUX2
    sta BUFRLO
    adc #TEMP - CDEVIC
    sta BFENLO
    lda #>CDEVIC
    sta BUFRHI
    sta BFENHI
    lda #SIO_LINE_ON
    sta PBCTL                       ; asserts the command line
    jsr SIO_SEND_AND_WAIT
    lda ERRFLG
    bne SIO_MAIN_COMMAND_FAILED     ; NAK, ERROR or a bad byte
    tya
    bne SIO_MAIN_ACKNOWLEDGED       ; Y = 0 when nothing came
SIO_MAIN_COMMAND_FAILED:
    dec CRETRY
    bpl SIO_MAIN_SEND_COMMAND
    jmp SIO_MAIN_RETRY
SIO_MAIN_ACKNOWLEDGED:
    lda DSTATS
    bpl SIO_MAIN_AWAIT_COMPLETE     ; nothing to send
    lda #SIO_COMMAND_RETRIES
    sta CRETRY                      ; a data frame that goes unanswered sends the command again
    jsr SIO_SET_BUFFER
    jsr SIO_SEND_AND_WAIT
    beq SIO_MAIN_COMMAND_FAILED
SIO_MAIN_AWAIT_COMPLETE:
    jsr SIO_DEVICE_TIMEOUT
    lda #0
    sta ERRFLG                      ; forgets a NAK of the data frame, which then times out here
    jsr SIO_AWAIT_RESPONSE
    beq SIO_MAIN_CHECK_ERROR        ; timed out
    bit DSTATS
    bvs SIO_MAIN_RECEIVE_DATA
    lda ERRFLG
    bne SIO_MAIN_RETRY
    beq SIO_MAIN_DONE
SIO_MAIN_RECEIVE_DATA:
    jsr SIO_SET_BUFFER
    jsr SIO_RECEIVE_FRAME           ; the data frame follows ERROR as well as COMPLETE
SIO_MAIN_CHECK_ERROR:
    lda ERRFLG
    beq SIO_MAIN_CHECK_STATUS
    lda TSTAT                       ; ERROR's status rather than the data frame's
    sta STATUS
SIO_MAIN_CHECK_STATUS:
    lda STATUS
    cmp #SUCCES
    beq SIO_MAIN_DONE
SIO_MAIN_RETRY:
    dec DRETRY
    bmi SIO_MAIN_DONE
    jmp SIO_MAIN_RETRY_COMMAND
SIO_MAIN_DONE:
    jsr SIO_STOP
    lda #0
    sta CRITIC
    ldy STATUS
    sty DSTATS
    rts

;; Receives the device's one-byte answer to a frame or a command into TEMP, and judges it.
;;
;; ACK and COMPLETE are success. ERROR sets STATUS to DERROR and anything else to DNACK; those, and a bad byte, set
;; ERRFLG. A timeout leaves ERRFLG as it was.
;; In: CDTMV1 = the time allowed, running
;; Out: Y = $FF when a byte came, 0 when it timed out, STATUS = the status, TSTAT = the status
;; Uses: A, X, ERRFLG, TEMP
;; See: <SIO_AWAIT_RESPONSE>, <SIO_RECEIVE_FRAME>
SIO_GET_RESPONSE:
    lda #0
    sta ERRFLG
    clc
    lda #<TEMP                      ; a one-byte frame at TEMP
    sta BUFRLO
    adc #1
    sta BFENLO
    lda #>TEMP
    sta BUFRHI
    sta BFENHI
    lda #$FF
    sta NOCKSM                      ; with no checksum
    jsr SIO_RECEIVE_FRAME
    ldy #$FF
    lda STATUS
    cmp #SUCCES
    bne SIO_GET_RESPONSE_FAILED
    lda TEMP
    cmp #SIO_ACK
    beq SIO_GET_RESPONSE_DONE
    cmp #SIO_COMPLETE
    beq SIO_GET_RESPONSE_DONE
    cmp #SIO_ERROR
    bne SIO_GET_RESPONSE_NAK
    lda #DERROR
    sta STATUS
    bne SIO_GET_RESPONSE_FAILED
SIO_GET_RESPONSE_NAK:
    lda #DNACK                      ; NAK, or a byte that means nothing
    sta STATUS
SIO_GET_RESPONSE_FAILED:
    lda STATUS
    cmp #TIMOUT
    beq SIO_GET_RESPONSE_TIMED_OUT
    lda #$FF
    sta ERRFLG
    bne SIO_GET_RESPONSE_DONE
SIO_GET_RESPONSE_TIMED_OUT:
    ldy #0
SIO_GET_RESPONSE_DONE:
    lda STATUS
    sta TSTAT
    rts

;; Sends the frame from BUFRLO/BUFRHI to BFENLO/BFENHI, then its checksum, and waits until the last bit is out.
;;
;; It sends the first byte; <SIO_OUTPUT_NEEDED> and <SIO_OUTPUT_FINISHED> send the rest and set XMTDON. There is no
;; timeout, but BREAK ends the command through <SIO_BREAK>.
;; In: BUFRLO/BUFRHI = the frame, BFENLO/BFENHI = its end
;; Out: STATUS = SUCCES
;; Uses: A, X, Y, CHKSUM, CHKSNT, XMTDON
;; See: <SIO_SEND_ENABLE>, <SIO_OUTPUT_NEEDED>, <SIO_OUTPUT_FINISHED>
SIO_SEND_FRAME:
    lda #SUCCES
    sta STATUS
    jsr SIO_SEND_ENABLE
    ldy #0
    sty CHKSUM
    sty CHKSNT
    sty XMTDON
    lda (BUFRLO),y
    sta SEROUT
    sta CHKSUM
SIO_SEND_FRAME_WAIT:
    lda BRKKEY
    bne SIO_SEND_FRAME_CHECK
    jmp SIO_BREAK
SIO_SEND_FRAME_CHECK:
    lda XMTDON
    beq SIO_SEND_FRAME_WAIT
    jsr SIO_STOP
    rts

;; The serial output needed interrupt's handler (VSEROR): sends the frame's next byte, adding it to the checksum, then
;; the checksum, then enables the output finished interrupt.
;;
;; The IRQ handler has pushed A, which the routine pulls before its RTI.
;; Keeps: X, Y
;; See: <VSEROR>, <SIO_SEND_FRAME>, <SIO_OUTPUT_FINISHED>
SIO_OUTPUT_NEEDED:
    tya
    pha
    inc BUFRLO
    bne SIO_OUTPUT_NEEDED_CHECK_END
    inc BUFRHI
SIO_OUTPUT_NEEDED_CHECK_END:
.if VERSION = VERSION_B
    lda BUFRLO                      ; BUFRLO/BUFRHI less BFENLO/BFENHI: carry = clear before the end
    cmp BFENLO
    lda BUFRHI
    sbc BFENHI
.else
    lda BUFRHI                      ; rev. A: the high bytes, then the low
    cmp BFENHI
    bcc SIO_OUTPUT_NEEDED_NEXT_BYTE
    lda BUFRLO
    cmp BFENLO
.endif
    bcc SIO_OUTPUT_NEEDED_NEXT_BYTE
    lda CHKSNT
    bne SIO_OUTPUT_NEEDED_FINISH
    lda CHKSUM
    sta SEROUT
    lda #$FF
    sta CHKSNT
    bne SIO_OUTPUT_NEEDED_RETURN
SIO_OUTPUT_NEEDED_FINISH:
    lda POKMSK
    ora #IRQ_SERIAL_DONE
    sta POKMSK
    sta IRQEN
SIO_OUTPUT_NEEDED_RETURN:
    pla
    tay
    pla
    rti
SIO_OUTPUT_NEEDED_NEXT_BYTE:
    ldy #0
    lda (BUFRLO),y
    sta SEROUT
    clc
    adc CHKSUM
    adc #0                          ; the end-around carry
    sta CHKSUM
    jmp SIO_OUTPUT_NEEDED_RETURN

;; The serial output finished interrupt's handler (VSEROC): once the checksum has gone, sets XMTDON and disables the
;; interrupt.
;;
;; The IRQ handler has pushed A, which the routine pulls before its RTI.
;; Keeps: X, Y
;; See: <VSEROC>, <SIO_SEND_FRAME>
SIO_OUTPUT_FINISHED:
    lda CHKSNT
    beq SIO_OUTPUT_FINISHED_RETURN
    sta XMTDON
    lda POKMSK
    and #<(~IRQ_SERIAL_DONE)
    sta POKMSK
    sta IRQEN
SIO_OUTPUT_FINISHED_RETURN:
    pla
    rti

;; Receives a frame into BUFRLO/BUFRHI to BFENLO/BFENHI, and its checksum unless NOCKSM is set, and releases the
;; command line.
;;
;; <SIO_INPUT_READY> takes the bytes and sets RECVDN. For the cassette, the checksum goes on from the leader bytes
;; <SIO_MEASURE_BAUD> stored.
;; In: BUFRLO/BUFRHI = the buffer, BFENLO/BFENHI = its end, CDTMV1 = the time allowed, running
;; Out: STATUS = the status
;; Uses: A, X, Y, CHKSUM, BUFRFL, RECVDN
;; Errors: STATUS = TIMOUT, FRMERR, OVRRUN or CHKERR
;; See: <SIO_RECEIVE_ENABLE>, <SIO_INPUT_READY>, <SIO_TIMED_OUT>
SIO_RECEIVE_FRAME:
    lda #0
    ldy CASFLG
    bne SIO_RECEIVE_FRAME_START
    sta CHKSUM
SIO_RECEIVE_FRAME_START:
    sta BUFRFL
    sta RECVDN
    lda #SUCCES
    sta STATUS
    jsr SIO_RECEIVE_ENABLE
    lda #SIO_LINE_OFF
    sta PBCTL                       ; releases the command line
SIO_RECEIVE_FRAME_WAIT:
    lda BRKKEY
    bne SIO_RECEIVE_FRAME_CHECK
    jmp SIO_BREAK
SIO_RECEIVE_FRAME_CHECK:
    lda TIMFLG
    beq SIO_TIMED_OUT
    lda RECVDN
    beq SIO_RECEIVE_FRAME_WAIT
    rts

;; Reports a timeout.
;; Out: STATUS = TIMOUT
;; Uses: A
;; Keeps: X, Y
SIO_TIMED_OUT:
    lda #TIMOUT
    sta STATUS
    rts

;; The serial input ready interrupt's handler (VSERIN): stores the byte received and adds it to the checksum, or, when
;; the frame is in, compares it with the checksum; records frame errors and overruns.
;;
;; Once the last byte is in it sets RECVDN; without a checksum (NOCKSM) at once, clearing NOCKSM, and otherwise when
;; the checksum byte arrives, setting BUFRFL until then.
;;
;; The IRQ handler has pushed A, which the routine pulls before its RTI.
;; Keeps: X, Y
;; Errors: STATUS = FRMERR, OVRRUN or CHKERR
;; See: <VSERIN>, <SIO_RECEIVE_FRAME>
SIO_INPUT_READY:
    tya
    pha
    lda SKSTAT
    sta SKREST                      ; clears the error bits for the next byte
    bmi SIO_INPUT_READY_OVERRUN     ; bit 7 clear: a frame error
    ldy #FRMERR
    sty STATUS
SIO_INPUT_READY_OVERRUN:
    and #SIO_SKSTAT_OVERRUN
    bne SIO_INPUT_READY_CHECK_FULL
    ldy #OVRRUN
    sty STATUS
SIO_INPUT_READY_CHECK_FULL:
    lda BUFRFL
    beq SIO_INPUT_READY_STORE
    lda SERIN                       ; the checksum
    cmp CHKSUM
    beq SIO_INPUT_READY_RECEIVED
    ldy #CHKERR
    sty STATUS
SIO_INPUT_READY_RECEIVED:
    lda #$FF
    sta RECVDN
SIO_INPUT_READY_RETURN:
    pla
    tay
    pla
    rti
SIO_INPUT_READY_STORE:
    lda SERIN
    ldy #0
    sta (BUFRLO),y
    clc
    adc CHKSUM
    adc #0                          ; the end-around carry
    sta CHKSUM
    inc BUFRLO
    bne SIO_INPUT_READY_CHECK_END
    inc BUFRHI
SIO_INPUT_READY_CHECK_END:
.if VERSION = VERSION_B
    lda BUFRLO                      ; BUFRLO/BUFRHI less BFENLO/BFENHI: carry = clear before the end
    cmp BFENLO
    lda BUFRHI
    sbc BFENHI
.else
    lda BUFRHI                      ; rev. A: the high bytes, then the low
    cmp BFENHI
    bcc SIO_INPUT_READY_RETURN
    lda BUFRLO
    cmp BFENLO
.endif
    bcc SIO_INPUT_READY_RETURN
    lda NOCKSM
    beq SIO_INPUT_READY_FULL
    lda #0
    sta NOCKSM
    beq SIO_INPUT_READY_RECEIVED
SIO_INPUT_READY_FULL:
    lda #$FF
    sta BUFRFL
    bne SIO_INPUT_READY_RETURN

;; Points SIO's buffer at the device control block's: BUFRLO/BUFRHI at DBUFLO/DBUFHI, BFENLO/BFENHI DBYTLO/DBYTHI
;; bytes on.
;; Out: BUFRLO/BUFRHI, BFENLO/BFENHI
;; Uses: A
;; Keeps: X, Y
SIO_SET_BUFFER:
    clc
    lda DBUFLO
    sta BUFRLO
    adc DBYTLO
    sta BFENLO
    lda DBUFHI
    sta BUFRHI
    adc DBYTHI
    sta BFENHI
    rts

;; Reads or writes one cassette record, for <SIO_MAIN>.
;;
;; A write starts the motor with the mark tone playing, waits out the leader, and sends the record at 600 baud. A read
;; starts the motor, skips the leader's time, measures the record's baud rate and receives it, within DTIMLO seconds.
;; DAUX2 bit 7 asks for short gaps: shorter leaders, and the motor left running afterward.
;; In: DSTATS = bit 7 set to write, DAUX2 = bit 7 set for short gaps, DBUFLO..DBYTHI = the record
;; Out: Y = the status, DSTATS = the status, negative = set on an error
;; See: <SIO_MAIN>, <SIO_MEASURE_BAUD>
SIO_CASSETTE:
    lda DSTATS
    bpl SIO_CASSETTE_READ
    lda #<SIO_CASSETTE_DIVIDER
    sta AUDF3
    lda #>SIO_CASSETTE_DIVIDER
    sta AUDF4
    jsr SIO_SEND_ENABLE             ; the mark tone, for the leader
    ldy #SIO_WRITE_SHORT_LEADER
    lda DAUX2
    bmi SIO_CASSETTE_WRITE_LEADER
    ldy #SIO_WRITE_LEADER
SIO_CASSETTE_WRITE_LEADER:
    ldx #0
    jsr SIO_START_TIMER
    lda #SIO_LINE_ON
    sta PACTL                       ; starts the motor
SIO_CASSETTE_WRITE_WAIT:
    lda TIMFLG
    bne SIO_CASSETTE_WRITE_WAIT
    jsr SIO_SET_BUFFER
    jsr SIO_SEND_FRAME
    jmp SIO_CASSETTE_DONE
SIO_CASSETTE_READ:
    lda #$FF
    sta CASFLG
    ldy #SIO_READ_SHORT_LEADER
    lda DAUX2
    bmi SIO_CASSETTE_READ_LEADER
    ldy #SIO_READ_LEADER
SIO_CASSETTE_READ_LEADER:
    ldx #0
    jsr SIO_START_TIMER
    lda #SIO_LINE_ON
    sta PACTL                       ; starts the motor
SIO_CASSETTE_READ_WAIT:
    lda TIMFLG
    bne SIO_CASSETTE_READ_WAIT
    jsr SIO_SET_BUFFER
    jsr SIO_DEVICE_TIMEOUT
    jsr SIO_START_TIMER
    jsr SIO_MEASURE_BAUD
    jsr SIO_RECEIVE_FRAME
SIO_CASSETTE_DONE:
    lda DAUX2
    bmi SIO_CASSETTE_EXIT           ; short gaps: the motor keeps running
    lda #SIO_LINE_OFF
    sta PACTL                       ; stops the motor
SIO_CASSETTE_EXIT:
    jmp SIO_MAIN_DONE

;; System timer 1's routine while SIO waits (CDTMA1): clears TIMFLG, which ends the wait as a timeout.
;; Out: TIMFLG = 0
;; Uses: A
;; Keeps: X, Y
;; See: <SIO_START_TIMER>
SIO_TIMEOUT:
    lda #0
    sta TIMFLG
    rts

;; SENDEV: sets POKEY up to send: the serial mode, the cassette's two tones when DDEVIC is the cassette, the serial
;; output needed interrupt, and the noise.
;; Uses: A, X, Y, SSKCTL, POKMSK
;; See: <SENDEV>, <SIO_ENABLE_INTERRUPTS>, <SIO_SEND_FRAME>
SIO_SEND_ENABLE:
    lda #SIO_SKCTL_KEEP
    and SSKCTL
    ora #SIO_SKCTL_SEND
    ldy DDEVIC
    cpy #CASSETTE_ID
    bne SIO_SEND_ENABLE_SET
    ora #SIO_SKCTL_TWO_TONE
    ldy #SIO_SPACE_DIVIDER
    sty AUDF2
    ldy #SIO_MARK_DIVIDER
    sty AUDF1
SIO_SEND_ENABLE_SET:
    sta SSKCTL
    sta SKCTL
    lda #<(~SIO_IRQ_SERIAL)
    and POKMSK
    ora #IRQ_SERIAL_OUTPUT
    jmp SIO_ENABLE_INTERRUPTS

;; Sets POKEY up to receive: the serial mode, its error bits cleared, the serial input ready interrupt, and the noise.
;; Uses: A, X, Y, SSKCTL, POKMSK
;; See: <SIO_ENABLE_INTERRUPTS>, <SIO_RECEIVE_FRAME>
SIO_RECEIVE_ENABLE:
    lda #SIO_SKCTL_KEEP
    and SSKCTL
    ora #SIO_SKCTL_RECEIVE
    sta SSKCTL
    sta SKCTL
    sta SKREST
    lda #<(~SIO_IRQ_SERIAL)
    and POKMSK
    ora #IRQ_SERIAL_INPUT

;; Enables the serial interrupts given, and sets the sound channels to play the traffic while SOUNDR is nonzero:
;; channel 4 always, and channels 1 and 2 (the tones) for the cassette; channel 3 stays silent.
;; In: A = POKMSK's new value
;; Uses: A, X, Y, POKMSK
SIO_ENABLE_INTERRUPTS:
    sta POKMSK
    sta IRQEN
    lda #SIO_AUDCTL
    sta AUDCTL
    ldx #AUDC4 - AUDC1
    lda #SIO_AUDC_NOISY
    ldy SOUNDR
    bne SIO_ENABLE_INTERRUPTS_LOOP
    lda #SIO_AUDC_QUIET
SIO_ENABLE_INTERRUPTS_LOOP:
    sta AUDC1,x
    dex
    dex
    bpl SIO_ENABLE_INTERRUPTS_LOOP
    lda #SIO_AUDC_QUIET
    sta AUDC3
    ldy DDEVIC
    cpy #CASSETTE_ID
    beq SIO_ENABLE_INTERRUPTS_DONE
    sta AUDC1
    sta AUDC2
SIO_ENABLE_INTERRUPTS_DONE:
    rts

;; Disables the serial interrupts and silences the four sound channels.
;; Uses: A, X, POKMSK
;; Keeps: Y
SIO_STOP:
    nop
    lda #<(~SIO_IRQ_SERIAL)
    and POKMSK
    sta POKMSK
    sta IRQEN
    ldx #AUDC4 - AUDC1
    lda #0
SIO_STOP_LOOP:
    sta AUDC1,x
    dex
    dex
    bpl SIO_STOP_LOOP
    rts

;; Converts the device's timeout, DTIMLO in seconds, to vertical blanks for <SIO_START_TIMER>: DTIMLO times 64.
;; Out: X = the high byte, Y = the low byte
;; Uses: A
SIO_DEVICE_TIMEOUT:
    lda DTIMLO
    ror a
    ror a
    tay
    and #$3F                        ; DTIMLO / 4
    tax
    tya
    ror a
    and #$C0                        ; DTIMLO * 64, low byte
    tay
    rts

    ; Unused: a copy of the serial interrupts' vectors, as in the start-up's vector table; nothing reads it.
    .word SIO_INPUT_READY, SIO_OUTPUT_NEEDED, SIO_OUTPUT_FINISHED

;; Sends a frame after a short pause and waits for the device's answer.
;; In: BUFRLO/BUFRHI = the frame, BFENLO/BFENHI = its end
;; Out: Y = $FF when a byte came, 0 when it timed out, A = Y, zero = set when it timed out, TEMP = the answer
;; Uses: X, STATUS, TSTAT, ERRFLG
;; See: <SIO_SEND_FRAME>, <SIO_GET_RESPONSE>
SIO_SEND_AND_WAIT:
    ldx #1
SIO_SEND_AND_WAIT_DELAY:
    ldy #$FF
SIO_SEND_AND_WAIT_DELAY_INNER:
    dey
    bne SIO_SEND_AND_WAIT_DELAY_INNER
    dex
    bne SIO_SEND_AND_WAIT_DELAY
    jsr SIO_SEND_FRAME
    ldy #SIO_ACK_TIMEOUT
    ldx #0

;; Waits for the device's one-byte answer, with a timeout.
;; In: X = the time allowed in vertical blanks, high byte, Y = its low byte
;; Out: Y = $FF when a byte came, 0 when it timed out, A = Y, zero = set when it timed out, TEMP = the answer
;; Uses: X, STATUS, TSTAT, ERRFLG
;; See: <SIO_GET_RESPONSE>
SIO_AWAIT_RESPONSE:
    jsr SIO_START_TIMER
    jsr SIO_GET_RESPONSE
    tya
    rts

;; Turns the leader's timing into POKEY's divider for the tape's baud rate.
;;
;; TIMER1 and TIMER2 hold VCOUNT and RTCLOK's low byte at the start and the end of <SIO_BAUD_EDGES> changes of the
;; input. Their difference in line pairs, from 88 up, indexes <SIO_BAUD_TABLE> in steps of eight, and the remainder
;; interpolates, adding <SIO_DIVIDER_STEP> for each; the result is less <SIO_POKEY_OFFSET>.
;; In: A = VCOUNT at the end, Y = RTCLOK+2 at the end, TIMER1 = the start
;; Out: Y = the divider's low byte, A = its high byte
;; Uses: X, TIMER1, TIMER2, TEMP1, ADDCOR
;; See: <SIO_MEASURE_BAUD>, <SIO_ADJUST_LINE>
SIO_COMPUTE_BAUD:
    sta TIMER2
    sty TIMER2+1
    jsr SIO_ADJUST_LINE
    sta TIMER2
    lda TIMER1
    jsr SIO_ADJUST_LINE
    sta TIMER1
    lda TIMER2
    sec
    sbc TIMER1
    sta TEMP1                       ; the line pairs' difference
    lda TIMER2+1
    sec
    sbc TIMER1+1
    tay                             ; the frames' difference
    lda #<(-SIO_LINE_PAIRS)
SIO_COMPUTE_BAUD_FRAMES:
    clc
    adc #SIO_LINE_PAIRS
    dey
    bpl SIO_COMPUTE_BAUD_FRAMES     ; A = the frames times SIO_LINE_PAIRS
    clc
    adc TEMP1
    tay                             ; the line pairs the edges took
    lsr a
    lsr a
    lsr a
    asl a
    sec
    sbc #2 * SIO_BAUD_FIRST_COUNT / 8
    tax                             ; the table's entry for the count's eight
    tya
    and #7
    tay
    lda #<(-SIO_DIVIDER_STEP)
SIO_COMPUTE_BAUD_INTERPOLATE:
    clc
    adc #SIO_DIVIDER_STEP
    dey
    bpl SIO_COMPUTE_BAUD_INTERPOLATE ; A = the remainder times 11
    ldy #0
    sty ADDCOR
    sec
    sbc #SIO_POKEY_OFFSET
    bpl SIO_COMPUTE_BAUD_ADD
    dec ADDCOR                      ; the high byte of a negative correction
SIO_COMPUTE_BAUD_ADD:
    clc
    adc SIO_BAUD_TABLE,x
    tay
    lda ADDCOR
    adc SIO_BAUD_TABLE+1,x
    rts

;; Counts a VCOUNT from where the vertical blank counts RTCLOK up, so that line pairs and RTCLOK's frames line up.
;; In: A = VCOUNT
;; Out: A = the line pairs since <SIO_VBLANK_LINE>, 0 to <SIO_LINE_PAIRS> less 1
;; Keeps: X, Y
SIO_ADJUST_LINE:
    cmp #SIO_VBLANK_LINE
    bmi SIO_ADJUST_LINE_BEFORE
    sec
    sbc #SIO_VBLANK_LINE
    rts
SIO_ADJUST_LINE_BEFORE:
    clc
    adc #SIO_LINE_PAIRS - SIO_VBLANK_LINE
    rts

;; Measures the cassette's baud rate from the start of a record, sets POKEY to it, and starts the record's buffer
;; and checksum with the two leader bytes it has used.
;;
;; With interrupts disabled, it waits for the input to go to 0 (the first $55's start bit), times
;; <SIO_BAUD_EDGES> changes of the input with VCOUNT and RTCLOK, computes CBAUDL/CBAUDH through
;; <SIO_COMPUTE_BAUD>, and then lets nine more changes pass, to the end of the second $55. It stores $55 twice in
;; the buffer and $AA in CHKSUM, and resets the serial port for the record's third byte.
;; In: BUFRLO/BUFRHI = the record's buffer, CDTMV1 = the time allowed, running
;; Out: CBAUDL/CBAUDH = the divider, BUFRLO/BUFRHI = 2 bytes on, CHKSUM = $AA, STATUS = TIMOUT on a timeout
;; Uses: A, X, Y, TIMER1, TIMER2, TEMP1, TEMP3, SAVIO, ADDCOR
;; See: <SIO_CASSETTE>, <SIO_COMPUTE_BAUD>
SIO_MEASURE_BAUD:
    lda BRKKEY
    bne SIO_MEASURE_BAUD_START
    jmp SIO_BREAK
SIO_MEASURE_BAUD_START:
    sei
    lda TIMFLG
    bne SIO_MEASURE_BAUD_LEVEL
    beq SIO_MEASURE_BAUD_TIMED_OUT
SIO_MEASURE_BAUD_LEVEL:
    lda SKSTAT
    and #SIO_SKSTAT_INPUT
    bne SIO_MEASURE_BAUD            ; still the mark of the leader
    sta SAVIO
    ldx VCOUNT
    ldy RTCLOK+2
    stx TIMER1
    sty TIMER1+1
    ldx #1
    stx TEMP3                       ; two stages: the timed changes, then the rest
    ldy #SIO_BAUD_EDGES
SIO_MEASURE_BAUD_EDGE:
    lda BRKKEY
    beq SIO_BREAK
    lda TIMFLG
    bne SIO_MEASURE_BAUD_CHECK_EDGE
SIO_MEASURE_BAUD_TIMED_OUT:
    cli
    jmp SIO_TIMED_OUT
SIO_MEASURE_BAUD_CHECK_EDGE:
    lda SKSTAT
    and #SIO_SKSTAT_INPUT
    cmp SAVIO
    beq SIO_MEASURE_BAUD_EDGE
    sta SAVIO
    dey
    bne SIO_MEASURE_BAUD_EDGE
    dec TEMP3
    bmi SIO_MEASURE_BAUD_DONE
    lda VCOUNT
    ldy RTCLOK+2
    jsr SIO_COMPUTE_BAUD
    sty CBAUDL
    sta CBAUDH
    ldy #2 * 10 - 1 - SIO_BAUD_EDGES ; the rest of the two bytes' 19 changes, to the last stop bit
    bne SIO_MEASURE_BAUD_EDGE
SIO_MEASURE_BAUD_DONE:
    lda CBAUDL
    sta AUDF3
    lda CBAUDH
    sta AUDF4
    lda #0
    sta SKCTL                       ; resets the serial port
    lda SSKCTL
    sta SKCTL
    lda #SIO_LEADER_BYTE            ; Y = 0
    sta (BUFRLO),y
    iny
    sta (BUFRLO),y
    lda #2 * SIO_LEADER_BYTE
    sta CHKSUM
    clc
    lda BUFRLO
    adc #2
    sta BUFRLO
    lda BUFRHI
    adc #0
    sta BUFRHI
    cli
    rts

;; Ends the command when BREAK has been pressed: silences POKEY, stops the motor, releases the command line and returns
;; BRKABT from <SIO_MAIN> with the stack as it was there.
;; Out: STATUS = BRKABT, BRKKEY = $FF
;; See: <SIO_MAIN>
SIO_BREAK:
    jsr SIO_STOP
    lda #SIO_LINE_OFF
    sta PACTL
    sta PBCTL
    lda #BRKABT
    sta STATUS
    ldx STACKP
    txs
    dec BRKKEY                      ; 0 to $FF: the BREAK is taken
    cli
    jmp SIO_MAIN_DONE

;; Starts system timer 1 for SIO's timeout: TIMFLG is set now, and <SIO_TIMEOUT> clears it when the time is up.
;;
;; Rev. B sets TIMFLG after SETVBV has set the timer; rev. A set it first, so a timer 1 still running from before,
;; reaching zero just then, could clear the new flag and end the wait at once.
;; In: X = the time in vertical blanks, high byte, Y = its low byte
;; Out: TIMFLG = 1
;; Uses: A, X, CDTMA1, CDTMV1
;; Keeps: Y
;; See: <SIO_TIMEOUT>, <SETVBV>
SIO_START_TIMER:
    lda #<SIO_TIMEOUT
    sta CDTMA1
    lda #>SIO_TIMEOUT
    sta CDTMA1+1
.if VERSION = VERSION_B
    lda #SIO_SYSTEM_TIMER_1
    sei
    jsr SETVBV
    lda #1
    sta TIMFLG
.else
    lda #SIO_SYSTEM_TIMER_1         ; also TIMFLG's 1
    sta TIMFLG
    sei
    jsr SETVBV
.endif
    cli
    rts

;; The dividers for the tape's baud rate, by the line pairs ten bits take: 88, 96, ... 176, about 11.4 a line pair.
;; See: <SIO_COMPUTE_BAUD>
SIO_BAUD_TABLE:
    .word $03E8, $0443, $049E, $04F9, $0554, $05AF, $060A, $0665, $06C0, $071A, $0775, $07D0

.if VERSION = VERSION_B
    ; Unused: two bytes nothing reads, where rev. B's code came out two bytes shorter.
    .byte $24, $85
.endif
    .assert * = $EDEA, "Every build's SIO ends at $EDEA, where the disk handler starts."
