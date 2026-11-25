;; THE CASSETTE HANDLER (C:)
;;
;; The routines behind CASETV's vectors, RBLOKV's block read and CSOPIV's open for reading. The handler reads and
;; writes the tape in records of 128 data bytes, kept in CASBUF after SIO's two speed bytes and a control byte: $FC
;; for a full record, $FA for the last, partial one, whose last byte counts its data, and $FE for the end of the file.
;; Opening beeps once to read and twice to write, waits for a key, then starts the motor and lets the leader go by
;; or writes it. Closing a written file writes what is left and the end-of-file record, and stops the motor.

; The cassette's serial bus ID, its commands and its record.

CASSETTE_READ = 'R'                 ;; read a record
CASSETTE_WRITE = 'W'                ;; write a record
CASSETTE_FULL = $FC                 ;; the control byte of a record with 128 data bytes
CASSETTE_PARTIAL = $FA              ;; the control byte of the last record, whose last byte counts its data bytes
CASSETTE_END = $FE                  ;; the control byte of the end-of-file record, whose data are zeros
CASSETTE_DATA_SIZE = 128            ;; the data bytes in a record
CASSETTE_RECORD_SIZE = 131          ;; a record as CASBUF holds it: speed bytes, control byte and data
CASSETTE_CONTROL = CASBUF+2         ;; the record's control byte
CASSETTE_DATA = CASBUF+3            ;; the record's data bytes
CASSETTE_COUNT = CASSETTE_DATA+CASSETTE_DATA_SIZE-1 ;; a partial record's last byte, its count of data bytes
CASSETTE_TIMEOUT = 35               ;; the timeout for a record, in seconds

; The cassette's timing and its motor. The times are counted in vertical blanks, so the PAL OS, with 50 a second
; rather than 60, counts five sixths as many for the same time.

.if VERSION = VERSION_PAL
CASSETTE_READ_WAIT = $01E0          ;; the vertical blanks to let the leader go by when reading, about 10 seconds
CASSETTE_WRITE_LEADER = $03C0       ;; the vertical blanks of leader written, about 20 seconds
CASSETTE_BEEP_TIME = 25             ;; the vertical blanks of a beep, half a second
CASSETTE_BEEP_GAP = 8               ;; the vertical blanks between two beeps
.else
CASSETTE_READ_WAIT = $0240          ;; the vertical blanks to let the leader go by when reading, about 10 seconds
CASSETTE_WRITE_LEADER = $0480       ;; the vertical blanks of leader written, about 20 seconds
CASSETTE_BEEP_TIME = 30             ;; the vertical blanks of a beep, half a second
CASSETTE_BEEP_GAP = 10              ;; the vertical blanks between two beeps
.endif
CASSETTE_MOTOR_ON = $34             ;; PACTL with CA2 low: the motor on
CASSETTE_MOTOR_OFF = $3C            ;; PACTL with CA2 high: the motor off
CASSETTE_BEEP_DELAY = $F0           ;; the loops in half a cycle of the beep's tone

;; Initializes the cassette handler: sets the baud rate, CBAUDL/CBAUDH, to 600 baud.
;; Out: A = >SIO_CASSETTE_DIVIDER
;; Keeps: X, Y
;; Entry: CASSETTE_SPECIAL = returns at once, for SPECIAL, which the cassette lacks: Y is CIO's FNCNOT
CASSETTE_INIT:
    lda #<SIO_CASSETTE_DIVIDER
    sta CBAUDL
    lda #>SIO_CASSETTE_DIVIDER
    sta CBAUDH
CASSETTE_SPECIAL:
    rts

;; The cassette's OPEN: opens the tape for reading or writing, as ICAX1Z says.
;;
;; ICAX2Z picks the gaps between records, kept in FTYPE: negative for short ones, written and read without stopping
;; the motor. An open mode that is neither reading nor writing returns with CIO's FNCNOT, where the OS User's Manual
;; says NVALID.
;; In: ICAX1Z = the open mode, OREAD or OWRIT, ICAX2Z = the gaps' type
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, FTYPE, WMODE, FEOF, BPTR, BLIM, FREQ, PACTL, CDTMV3, CDTMF3, AUDF3, AUDF4, DDEVIC, SSKCTL, SKCTL, POKMSK
;; Errors: Y = BRKABT for BREAK, or the keyboard's status
;; See: <CASSETTE_OPEN_READ>, <CASSETTE_OPEN_WRITE>
CASSETTE_OPEN:
    lda ICAX2Z
    sta FTYPE
    lda ICAX1Z
    and #OREAD | OWRIT
    cmp #OREAD
    beq CASSETTE_OPEN_READ
    cmp #OWRIT
    beq CASSETTE_OPEN_WRITE
    rts                                 ; Y = FNCNOT, from CIO

;; Opens the tape for reading, through CSOPIV: beeps once, waits for a key, then starts the motor and waits about 10
;; seconds for the leader to go by.
;;
;; The buffer is left empty, so the first get reads a record. BREAK isn't tested during the wait.
;; In: FTYPE = the gaps' type
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, WMODE, FEOF, BPTR, BLIM, FREQ, CDTMV3, CDTMF3, PACTL
;; Errors: Y = the keyboard's status: BRKABT for BREAK
;; Entry: CASSETTE_OPEN_BREAK = ends an open for BREAK, with Y = BRKABT and BRKKEY set again,
;;   CASSETTE_OPEN_FAILED = ends an open that failed, with Y = the status
;; See: <CSOPIV>, <CASSETTE_BEEP>
CASSETTE_OPEN_READ:
    lda #$00
    sta WMODE
    sta FEOF
    lda #$01                            ; one beep
    jsr CASSETTE_BEEP
    bmi CASSETTE_OPEN_FAILED
    lda #CASSETTE_MOTOR_ON
    sta PACTL
    ldy #<CASSETTE_READ_WAIT
    ldx #>CASSETTE_READ_WAIT
    lda #$03                            ; system timer 3
    sta CDTMF3                          ; nonzero until the timer runs out
    jsr SETVBV
CASSETTE_OPEN_READ_WAIT:
    lda CDTMF3
    bne CASSETTE_OPEN_READ_WAIT
    lda #CASSETTE_DATA_SIZE
    sta BPTR
    sta BLIM                            ; the buffer is used up
    jmp CASSETTE_OPEN_DONE
CASSETTE_OPEN_BREAK:
    ldy #BRKABT
    dec BRKKEY                          ; 0 to $FF: BREAK is taken
CASSETTE_OPEN_FAILED:
    lda #$00
    sta WMODE
    rts

;; Opens the tape for writing: beeps twice, waits for a key, then starts the motor and writes about 20 seconds of
;; leader.
;;
;; SENDEV puts POKEY in two-tone mode, so the leader is the mark tone, at the baud rate set in AUDF3/AUDF4.
;; In: FTYPE = the gaps' type
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, WMODE, BPTR, FREQ, PACTL, AUDF3, AUDF4, DDEVIC, CDTMV3, CDTMF3, SSKCTL, SKCTL, POKMSK (SENDEV)
;; Errors: Y = BRKABT for BREAK, or the keyboard's status
;; Entry: CASSETTE_OPEN_DONE = ends an open that succeeded, with Y = SUCCES
;; See: <CASSETTE_BEEP>, <SENDEV>
CASSETTE_OPEN_WRITE:
    lda #$80
    sta WMODE
    lda #$02                            ; two beeps
    jsr CASSETTE_BEEP
    bmi CASSETTE_OPEN_FAILED
    lda #<SIO_CASSETTE_DIVIDER
    sta AUDF3
    lda #>SIO_CASSETTE_DIVIDER
    sta AUDF4
    lda #CASSETTE_ID
    sta DDEVIC
    jsr SENDEV
    lda #CASSETTE_MOTOR_ON
    sta PACTL
    lda #$03                            ; system timer 3
    ldx #>CASSETTE_WRITE_LEADER
    ldy #<CASSETTE_WRITE_LEADER
    jsr SETVBV
    lda #$FF
    sta CDTMF3                          ; nonzero until the timer runs out
CASSETTE_OPEN_WRITE_WAIT:
    lda BRKKEY
    beq CASSETTE_OPEN_BREAK
    lda CDTMF3
    bne CASSETTE_OPEN_WRITE_WAIT
    lda #$00
    sta BPTR                            ; the buffer is empty
CASSETTE_OPEN_DONE:
    ldy #SUCCES
    rts

;; The cassette's GET: returns the next byte of the file, reading a record when the buffer is used up.
;; Out: A = the byte, Y = the status, negative = set on an error or at the end of the file
;; Uses: X, BPTR, BLIM, FEOF, DDEVIC..DAUX2
;; Errors: Y = EOFERR at the end of the file, or SIO's status
;; Entry: CASSETTE_GET_DONE = returns, for <CASSETTE_READ_BLOCK>'s errors
;; See: <CASSETTE_READ_BLOCK>
CASSETTE_GET:
    lda FEOF
    bmi CASSETTE_READ_BLOCK_EOF
    ldx BPTR
    cpx BLIM
    beq CASSETTE_READ_BLOCK             ; the buffer is used up
    lda CASSETTE_DATA,x
    inc BPTR
    ldy #SUCCES
CASSETTE_GET_DONE:
    rts

;; Reads a record into CASBUF, through RBLOKV, then returns its first byte as <CASSETTE_GET> does.
;;
;; A full record holds 128 bytes and a partial one as many as its last byte says. An end-of-file record sets FEOF, and
;; every get after it returns EOFERR. A partial record that counts 0 bytes is passed over to the next record.
;; In: FTYPE = the gaps' type
;; Out: A = the byte, Y = the status, negative = set on an error or at the end of the file
;; Uses: X, BPTR, BLIM, FEOF, DDEVIC..DAUX2
;; Errors: Y = EOFERR at the end of the file, or SIO's status
;; Entry: CASSETTE_READ_BLOCK_EOF = returns EOFERR, for <CASSETTE_GET>
;; See: <RBLOKV>, <CASSETTE_SIO>
CASSETTE_READ_BLOCK:
    lda #CASSETTE_READ
    jsr CASSETTE_SIO
    tya
    bmi CASSETTE_GET_DONE               ; an error
    lda #$00
    sta BPTR
    ldx #CASSETTE_DATA_SIZE
    lda CASSETTE_CONTROL
    cmp #CASSETTE_END
    beq CASSETTE_READ_BLOCK_END
    cmp #CASSETTE_PARTIAL
    bne CASSETTE_READ_BLOCK_LIMIT
    ldx CASSETTE_COUNT
CASSETTE_READ_BLOCK_LIMIT:
    stx BLIM
    jmp CASSETTE_GET
CASSETTE_READ_BLOCK_END:
    dec FEOF                            ; 0 to $FF
CASSETTE_READ_BLOCK_EOF:
    ldy #EOFERR
    rts

;; The cassette's PUT: adds a byte to the record in CASBUF, writing it as a full record when it holds 128 bytes.
;; In: A = the byte
;; Out: Y = SUCCES, or the status when a record was written, negative = set on an error
;; Uses: A, X, BPTR, DDEVIC..DAUX2
;; Errors: Y = SIO's status
;; See: <CASSETTE_WRITE_RECORD>
CASSETTE_PUT:
    ldx BPTR
    sta CASSETTE_DATA,x
    inc BPTR
    ldy #SUCCES
    cpx #CASSETTE_DATA_SIZE-1
    beq CASSETTE_PUT_RECORD             ; the record is full
    rts
CASSETTE_PUT_RECORD:
    lda #CASSETTE_FULL
    jsr CASSETTE_WRITE_RECORD
    lda #$00
    sta BPTR
    rts

;; The cassette's STATUS, which has nothing to tell.
;; Out: Y = SUCCES
;; Keeps: A, X
CASSETTE_STATUS:
    ldy #SUCCES
    rts

;; The cassette's CLOSE: after writing, writes what is left in a partial record and then the end-of-file record; then
;; stops the motor.
;;
;; A partial record's unused bytes are whatever the buffer held. An error writing it skips the end-of-file record.
;; In: WMODE = negative when writing
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, CASBUF, DDEVIC..DAUX2
;; Errors: Y = SIO's status
;; See: <CASSETTE_WRITE_RECORD>
CASSETTE_CLOSE:
    lda WMODE
    bmi CASSETTE_CLOSE_WRITE
    ldy #SUCCES
CASSETTE_CLOSE_MOTOR_OFF:
    lda #CASSETTE_MOTOR_OFF
    sta PACTL
    rts
CASSETTE_CLOSE_WRITE:
    ldx BPTR
    beq CASSETTE_CLOSE_END              ; nothing left
    stx CASSETTE_COUNT
    lda #CASSETTE_PARTIAL
    jsr CASSETTE_WRITE_RECORD
    bmi CASSETTE_CLOSE_MOTOR_OFF        ; an error
CASSETTE_CLOSE_END:
    ldx #CASSETTE_DATA_SIZE-1
    lda #$00
CASSETTE_CLOSE_CLEAR:
    sta CASSETTE_DATA,x
    dex
    bpl CASSETTE_CLOSE_CLEAR
    lda #CASSETTE_END
    jsr CASSETTE_WRITE_RECORD
    jmp CASSETTE_CLOSE_MOTOR_OFF

;; Beeps the console speaker a number of times, then waits for a key, the prompt to set up the tape.
;;
;; Each beep is half a second of a tone made by toggling CONSOL's speaker bit in a delay loop, timed by RTCLOK, and the
;; beeps are a sixth of a second apart. The key comes from the keyboard handler's GET.
;; In: A = the number of beeps
;; Out: Y = the keyboard's status, A = Y, negative = set on an error
;; Uses: X, FREQ, CONSOL
;; Errors: Y = BRKABT for BREAK
;; See: <CASSETTE_WAIT_KEY>
CASSETTE_BEEP:
    sta FREQ
CASSETTE_BEEP_NEXT:
    lda RTCLOK+2
    clc
    adc #CASSETTE_BEEP_TIME
    tax                                 ; when the beep ends
CASSETTE_BEEP_CYCLE:
    lda #$FF
    sta CONSOL                          ; the speaker's bit high
    lda #$00
    ldy #CASSETTE_BEEP_DELAY
CASSETTE_BEEP_HIGH:
    dey
    bne CASSETTE_BEEP_HIGH
    sta CONSOL                          ; low
    ldy #CASSETTE_BEEP_DELAY
CASSETTE_BEEP_LOW:
    dey
    bne CASSETTE_BEEP_LOW
    cpx RTCLOK+2
    bne CASSETTE_BEEP_CYCLE
    dec FREQ
    beq CASSETTE_BEEP_KEY
    txa
    clc
    adc #CASSETTE_BEEP_GAP
    tax                                 ; when the gap ends
CASSETTE_BEEP_GAP_WAIT:
    cpx RTCLOK+2
    bne CASSETTE_BEEP_GAP_WAIT
    beq CASSETTE_BEEP_NEXT              ; always
CASSETTE_BEEP_KEY:
    jsr CASSETTE_WAIT_KEY
    tya
    rts

;; Waits for a key through the keyboard handler's GET, whose address less 1 it pushes from KEYBDV and returns to.
;; Out: A = the key, Y = the status: BRKABT for BREAK
;; See: <KEYBDV>
CASSETTE_WAIT_KEY:
    lda KEYBDV+5                        ; the GET vector, less 1
    pha
    lda KEYBDV+4
    pha
    rts

;; Reads or writes a record of CASBUF through SIO, with the gaps FTYPE asks for.
;; In: A = CASSETTE_READ or CASSETTE_WRITE, FTYPE = the gaps' type
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, DDEVIC..DAUX2
;; Errors: Y = SIO's status
;; See: <SIOV>
CASSETTE_SIO:
    sta DCOMND
    lda #>CASSETTE_RECORD_SIZE
    sta DBYTHI
    lda #<CASSETTE_RECORD_SIZE
    sta DBYTLO
    lda #>CASBUF
    sta DBUFHI
    lda #<CASBUF
    sta DBUFLO
    lda #CASSETTE_ID
    sta DDEVIC
    lda #$00
    sta DUNIT
    lda #CASSETTE_TIMEOUT
    sta DTIMLO
    lda DCOMND
    ldy #DCB_RECEIVE
    cmp #CASSETTE_READ
    beq CASSETTE_SIO_DIRECTION
    ldy #DCB_SEND
CASSETTE_SIO_DIRECTION:
    sty DSTATS
    lda FTYPE
    sta DAUX2
    jsr SIOV
    rts

;; Writes CASBUF's record with its speed bytes and the control byte given.
;; In: A = the control byte, CASSETTE_FULL, CASSETTE_PARTIAL or CASSETTE_END
;; Out: Y = the status, negative = set on an error
;; Uses: A, X, CASBUF..CASBUF+2, DDEVIC..DAUX2
;; Errors: Y = SIO's status
;; See: <CASSETTE_SIO>
CASSETTE_WRITE_RECORD:
    sta CASSETTE_CONTROL
    lda #SIO_LEADER_BYTE
    sta CASBUF
    sta CASBUF+1
    lda #CASSETTE_WRITE
    jsr CASSETTE_SIO
    rts
