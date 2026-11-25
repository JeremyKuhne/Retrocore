;; ATARI 810 DISK DRIVE FIRMWARE ($0800-$0FFF), REVISIONS B AND C
;;
;; The 2K ROM of the 810's own computer: a 6507 at 500 kHz with no interrupts, a 6532 RIOT (its 128 bytes of RAM, its
;; timer and its two ports), 128 bytes of 6810 RAM and an FD1771 floppy controller. It answers the computer's SIO
;; command frames for its drive number: Status ('S'), Read ('R'), Put ('P'), Write with verify ('W') and Format ('!'),
;; on single-sided disks of 40 tracks of 18 sectors of 128 bytes, numbered 1 to 720 from track 0's first sector.
;;
;; The firmware does by hand what most drives leave to their controller:
;;
;; - The serial bus: it shifts each bit in and out through the RIOT's port B at 19,200 baud, 26 cycles a bit.
;; - The head: the RIOT's port B drives the stepper's four phases, two at a time. Nothing tells the drive where track 0
;;   is, so it steps out past the stop to find it, and it parks the head on track 39 when it's idle.
;; - The index: the FD1771's index input is the RIOT's interrupt, so the timer, not the disk's index hole, tells the
;;   controller when to give up on a sector and when to start writing a track.
;; - The FD1771's data bus is inverted, so every value written to or read from its registers is the complement of what
;;   it sees, and the bytes on the disk are the complement of the computer's. The source writes each command and mark
;;   as the controller sees it, complemented where it's stored (<(~FDC_READ_SECTOR)). The firmware keeps its track and
;;   sector numbers in that form too: HEAD_TRACK, TARGET_TRACK and TARGET_SECTOR hold the complement of the number.
;;
;; The firmware runs from $0800 on reset. Between commands it relies, in its RAM, only on the head's track, the status
;; block, its own flags (DRIVE_FLAGS) and RUN_ON_COUNT. After each command that runs the motor it keeps the motor
;; running for two of the FD1771's Restores (see RUN_ON), polling the bus all the while, parks the head and turns the
;; motor off.
;;
;; VERSION selects the build: VERSION_C (the default) for revision C, the most common, and VERSION_B for revision B,
;; the earlier. They differ only in the order a format writes each track's sectors (FORMAT_ORDER), revision B's
;; spacing each sector 13 after the one before and revision C's 9 or 10, and in the direction its verify reads them
;; back (FORMAT_VERIFY_NEXT), every fourth sector: revision C from sector 1 up, revision B from sector 17 down.
;;
;; Two bugs both revisions have:
;;
;; - The dispatch accepts the command $4F ('O') as Write, since it tests for the range from $4F, not from 'P', and
;;   $4F's low bits are 'W''s.
;; - Only a Write that reaches its check clears FLAG_VERIFY. After one that is refused or fails before the check, the
;;   next Put verifies too, and the next Format, which shares the flag's bit (FLAG_BAD_SECTORS), ends with Error.
;;
;; Maintained by hand; each build assembles byte-identically to its ROM.

.cpu Mos6502

VERSION_B = 2                       ;; revision B, the earlier (12 sectors between consecutive ones on a track)
VERSION_C = 3                       ;; revision C, the most common (8 or 9 sectors between)

.ifndef VERSION
VERSION = VERSION_C
.endif
.assert VERSION = VERSION_B || VERSION = VERSION_C, "VERSION is VERSION_B or VERSION_C."

; The FD1771, at $0000-$0003 through an inverted data bus.

FDC_STATUS = $0000                  ;; read: the FD1771's status, complemented
FDC_COMMAND = $0000                 ;; written: a command for the FD1771, complemented
FDC_TRACK = $0001                   ;; the FD1771's track register, complemented
FDC_SECTOR = $0002                  ;; the FD1771's sector register, complemented
FDC_DATA = $0003                    ;; the FD1771's data register, complemented

; The FD1771's commands, as it sees them.

FDC_RESTORE = $00                   ;; Restore: step out until track 0, at the fastest rate; only a timer here
FDC_SEEK = $13                      ;; Seek from the track register to the data register, at the slowest rate; a timer
FDC_READ_SECTOR = $88               ;; Read Sector: one sector, its length from its ID field
FDC_WRITE_SECTOR = $A8              ;; Write Sector: one sector, its length from its ID field, with a normal data mark
FDC_FORCE_INTERRUPT = $D0           ;; Force Interrupt, with no interrupt: ends the command in progress
FDC_WRITE_TRACK = $F4               ;; Write Track, after the head settling delay

FDC_NOT_FOUND = $10                 ;; the status bit for a sector whose ID field wasn't found

; The bytes Write Track gives meaning to, as the FD1771 sees them.

FDC_GAP = $00                       ;; a gap byte, which the format writes as $FF (FDC_DATA is complemented)
FDC_DATA_FILL = $FF                 ;; each data byte of a formatted sector, which the computer reads as $00
FDC_INDEX_MARK = $FC                ;; the index address mark
FDC_ID_MARK = $FE                   ;; an ID field's address mark
FDC_DATA_MARK = $FB                 ;; a data field's address mark
FDC_CRC = $F7                       ;; writes the field's two CRC bytes
FDC_SECTOR_LENGTH = $00             ;; an ID field's length code for 128 bytes
FDC_SIDE = $00                      ;; an ID field's side

; The 6810's 128 bytes, at $0080-$00FF.

BUFFER = $0080                      ;; a sector's 128 bytes, received, read, written or sent; a format's bad sectors

ORDER_POINTER = BUFFER+$60          ;; a format's pointer into FORMAT_ORDER, low byte then high byte
FORMAT_SECTOR = BUFFER+$62          ;; the sector a format writes next, complemented
FORMAT_TRACK = BUFFER+$63           ;; the track a format is writing, complemented

; The 6532's 128 bytes, at $0180-$01FF. The stack starts at $01FF.

FRAME_DEVICE = $0181                ;; the command frame's device: '1' to '4' for drives 1 to 4
FRAME_COMMAND = $0182               ;; the command frame's command
FRAME_AUX1 = $0183                  ;; the command frame's first auxiliary byte: the sector's low byte
FRAME_AUX2 = $0184                  ;; the command frame's second auxiliary byte: the sector's high byte
FRAME_CHECKSUM = $0185              ;; the command frame's checksum
FRAME_SIZE = 5                      ;; the bytes in a command frame, its checksum included
SEND_BYTE = $0186                   ;; the byte being sent, shifted out from bit 0
DATA_CHECKSUM = $0187               ;; a data frame's checksum, received or about to be sent
STEP_PHASES = $01CD                 ;; STEP's work: the stepper's next phases
HEAD_TRACK = $01CE                  ;; the track the head is on, complemented ($FF is track 0)
PARK_STEPS = $01CF                  ;; the steps left to park the head on track 39

DRIVE_STATUS = $01D0                ;; the status block's first byte: the drive's status (STATUS_...)
CONTROLLER_STATUS = $01D1           ;; the status block's second: the FD1771's last status, complemented
STATUS_TIMEOUT = $01D2              ;; the status block's third: the timeout the OS gives a format
STATUS_UNUSED = $01D3               ;; the status block's fourth, always 0
STATUS_CHECKSUM = $01D4             ;; the status block's checksum, for the frame
STATUS_SIZE = 4                     ;; the bytes in the status block

SAVED_AUX2 = $01D7                  ;; FRAME_AUX2 as the command frame had it; nothing reads it
SAVED_AUX1 = $01D8                  ;; FRAME_AUX1 as the command frame had it; nothing reads it
TARGET_TRACK = $01DA                ;; the track of the command's sector, complemented
TARGET_SECTOR = $01DB               ;; the command's sector on its track (1-18), complemented
DRIVE_FLAGS = $01DD                 ;; the firmware's flags (FLAG_...)
RECEIVE_END = $01DE                 ;; the index in the frame where RECEIVE_BYTES or CHECKSUM_BYTES stops
DELAY_COUNT = $01DF                 ;; DELAY's count; CHECK_RESULT keeps Y here across a recalibration
VERIFY_TRIES = $01E0                ;; a format's verify: the tries left for the sector
BAD_SECTOR_INDEX = $01E1            ;; a format's verify: where in BUFFER the next bad sector's number goes
NUMBER_SECTOR = $01E2               ;; SECTOR_NUMBER's work: the sector on its track
NUMBER_TRACK2 = $01E3               ;; SECTOR_NUMBER's work: the track, times 2
NUMBER_HIGH = $01E4                 ;; SECTOR_NUMBER's work: the number's high byte
COMMAND_VECTOR = $01E8              ;; DISPATCH's jump into COMMAND_TABLE
COMMAND_INDEX = $01EA               ;; DISPATCH's work: the command's low three bits
RUN_ON_COUNT = $01EB                ;; the Restores left before the motor stops, less one

; The 6532's registers, at $0380-$039F.

RIOT_PORTA = $0380                  ;; port A (PA_...)
RIOT_DDRA = $0381                   ;; port A's directions: 1 for an output
RIOT_PORTB = $0382                  ;; port B (PB_...)
RIOT_DDRB = $0383                   ;; port B's directions: 1 for an output
RIOT_EDGE_OFF = $0384               ;; written: PA7's edge detect, on a falling edge with its interrupt off
RIOT_TIMER_IRQ_OFF = $0394          ;; read: the timer, clearing its interrupt and turning it off
RIOT_FLAGS = $0395                  ;; read: the interrupt flags, the timer's in bit 7
RIOT_TIMER_IRQ_ON = $039C           ;; read: the timer, clearing its interrupt and leaving it on
RIOT_TIMER_64 = $039E               ;; written: starts the timer counting every 64 cycles, with its interrupt
RIOT_TIMER_1024 = $039F             ;; written: starts the timer counting every 1,024 cycles, with its interrupt

; Port A's lines.

PA_DRQ = $80                        ;; input: the FD1771's DRQ, 1 when it has a byte or wants one (N after a BIT)
PA_INTRQ = $40                      ;; input: the FD1771's INTRQ, 1 when its command has ended (V after a BIT)
PA_WRITE_PROTECT = $10              ;; input: 1 when the disk is write-protected
PA_HIGH = $08                       ;; output, always 1; nothing on a stock 810 uses it
PA_DRIVE_A = $04                    ;; input: the drive-number switch A, 1 for drives 1 and 2
PA_MOTOR = $02                      ;; output: 1 runs the spindle motor
PA_DRIVE_B = $01                    ;; input: the drive-number switch B, 1 for drives 1 and 4
PA_OUTPUTS = PA_HIGH|PA_MOTOR       ;; port A's outputs

; Port B's lines.

PB_DATA_IN = $80                    ;; input: the computer's serial data out, complemented (N after a BIT)
PB_COMMAND = $40                    ;; input: the bus's command line, 1 while it's asserted (V after a BIT)
PB_PHASES = $3C                     ;; outputs: the stepper's phases 4 (PB5) to 1 (PB2), two adjacent ones at a time
PB_PHASE4 = $20                     ;; output: the stepper's phase 4
PB_PHASE1 = $04                     ;; output: the stepper's phase 1
PB_POWER = $02                      ;; input: 0 while the computer is on
PB_DATA_OUT = $01                   ;; output while sending: the drive's serial data to the computer

TRACK0_PHASES = $24                 ;; the phases that hold the head on track 0 and every fourth track from it
TRACK39_PHASES = $30                ;; the phases that hold the head on track 39, where it's parked

; The drive status (DRIVE_STATUS), as a Status command returns it.

STATUS_BAD_COMMAND = $01            ;; a command frame was refused
STATUS_BAD_DATA = $02               ;; a data frame's checksum was wrong
STATUS_FAILED = $04                 ;; an operation on the disk failed
;; The status's write-protect bit: set at reset if the disk is protected, and by a Put, Write or Format that fails for
;; it. Whatever sets the whole status clears it: the motor's wait in every Read, Put, Write and Format that reaches
;; the disk (MOTOR_READY), a refused frame and a data frame with a bad checksum.
STATUS_WRITE_PROTECTED = $08
;; The motor was running when a command or Status last set the status, so the first Status after a run-on can report
;; it on; reset clears it with the motor running.
STATUS_MOTOR_ON = $10

; The firmware's flags (DRIVE_FLAGS).

FLAG_COMPUTER_OFF = $01             ;; the computer was off at the last poll
FLAG_BAD_FRAME = $02                ;; the command frame's checksum was wrong
FLAG_MOTOR_STARTING = $04           ;; the motor stopped, or the drive was reset, since MOTOR_READY last waited for it
FLAG_VERIFY = $08                   ;; a write is a Write, which verifies
FLAG_BAD_SECTORS = $08              ;; a format's verify found a bad sector
FLAG_POLL_ONCE = $20                ;; POLL returns when no command is waiting, rather than waiting for one
FLAG_COMMAND_DELAY = $40            ;; POLL waits 105 ms for the command line to settle; nothing sets it
FLAG_RECEIVING = $80                ;; a command frame is being received; nothing reads it

; The bus.

SIO_ACK = 'A'                       ;; the acknowledgement of a frame
SIO_NAK = 'N'                       ;; the refusal of a frame
SIO_COMPLETE = 'C'                  ;; the command succeeded
SIO_ERROR = 'E'                     ;; the command failed

COMMAND_FORMAT = '!'                ;; format the disk, returning the bad sectors' numbers
COMMAND_PUT = 'P'                   ;; write a sector
COMMAND_READ = 'R'                  ;; read a sector
COMMAND_STATUS = 'S'                ;; return the 4-byte status block
COMMAND_WRITE = 'W'                 ;; write a sector and read it back to check it

; The disk.

TRACKS = 40                         ;; tracks on a disk
PARK_TRACK = 39                     ;; the track the head is parked on
SECTORS = 18                        ;; sectors on a track
SECTOR_SIZE = 128                   ;; bytes in a sector
LAST_SECTOR = TRACKS*SECTORS        ;; the highest sector number, 720
FORMAT_TIMEOUT = $E0                ;; the timeout the OS gives a format, in its units of about a second: 224
BAD_SECTORS_END = $FF               ;; both bytes of the word that ends a format's list of bad sectors
BAD_SECTORS_FULL = SECTOR_SIZE-2    ;; where the list of bad sectors ends when it's full: 63 sectors

; Times: DELAY's units of 256 loops (2.56 ms), the RIOT's 64-cycle units (128 us) and its 1,024-cycle units (2 ms).

DELAY_COMPUTER_ON = $29             ;; DELAY's wait for the computer to come up: 105 ms
DELAY_SPIN_UP = $50                 ;; DELAY's wait for the motor to start: 205 ms
DELAY_FORMAT_STEP = $02             ;; DELAY's wait before a format steps to the next track: 5 ms
STEP_TIME = $29                     ;; the RIOT's time for one step: 5.2 ms
SETTLE_TIME = $50                   ;; the RIOT's time for the head to settle after a seek: 10.2 ms
INDEX_TIME = $0D                    ;; the RIOT's time to a format's index pulse: 27 ms
TRIES = 4                           ;; the tries a read or write gets
FORMAT_VERIFY_TRIES = 2             ;; the tries a format's verify gives each sector

;; A sector number in FORMAT_ORDER, complemented.
;; Parameters: number = the sector, 1 to 18
.macro SECTOR number
    .byte <(~(number))
.endmacro

.org $0800

;; Starts the drive on reset: sets up the RIOT and the FD1771, runs the motor, steps the head out 40 times to find
;; track 0, and goes to COMMAND_DONE, which parks it on track 39 and stops the motor.
;;
;; The drive status keeps only its write-protect bit, now the sensor's, and the computer is taken to be off until a
;; poll sees it on.
RESET:
    cld
    lda #PA_OUTPUTS
    sta RIOT_PORTA                      ; the motor on
    sta RIOT_DDRA
    ldx #PB_PHASES
    stx RIOT_DDRB                       ; PB0 an input until the drive sends
    stx RIOT_EDGE_OFF
    ldx #$00
    stx RIOT_PORTB                      ; the phases off
    lda #<(~FDC_FORCE_INTERRUPT)
    sta FDC_COMMAND
    lda #FLAG_COMPUTER_OFF|FLAG_MOTOR_STARTING
    sta DRIVE_FLAGS
    lda #FORMAT_TIMEOUT
    sta STATUS_TIMEOUT
    lda #$00
    sta STATUS_UNUSED
    jsr SPIN_UP
    ldy #TRACKS-1                       ; 40 steps
    jsr RECALIBRATE
    sty FDC_TRACK                       ; Y = 0: the FD1771's track register is 255
    dey
    sty FDC_SECTOR
    jsr KEEP_WRITE_PROTECT
    jsr WRITE_PROTECT_STATUS
    ldx #$01
    stx RUN_ON_COUNT                    ; two Restores

;; Ends every command that runs (a refused one goes back to POLL instead): resets the stack, counts the steps to park
;; the head on track 39, waits out RUN_ON's Restores while polling the bus (the motor running on, if it's running),
;; parks the head, and stops the motor to wait for the next command.
;; See: <RUN_ON>, <PARK>, <POLL>
COMMAND_DONE:
    ldx #$FF
    txs
    lda #<(~PARK_TRACK)
    jsr SEEK_DISTANCE
    sty PARK_STEPS

;; Runs the motor on after a command: issues the FD1771 a Restore and polls the bus until it ends. With no stepper or
;; track 0 sensor wired to the controller, the Restore is only a timer: it steps nothing, and ends when the controller
;; gives up on finding track 0. Restores run until RUN_ON_COUNT, less one after each, goes negative; then PARK steps
;; the head to track 39.
;;
;; MOTOR_ON sets the count to 1, for two Restores, and the run-on leaves it at $FF. Status doesn't run the motor, so a
;; Status that comes after a run-on has ended gets one Restore and leaves the count one lower; the 128th such Status
;; in a row finds it at $80, which goes to $7F and runs 129 Restores.
;; See: <COMMAND_DONE>
RUN_ON:
    lda #<(~FDC_RESTORE)
    sta FDC_COMMAND
    lda #FLAG_POLL_ONCE
    jmp RUN_ON_WAIT

    .res $086F-*, $00

;; The order a format writes each track's sectors in, after sector 18, which is written first: complemented, as the
;; firmware keeps sector numbers. Revision C writes the odd sectors and then the even ones, so that the next of two
;; sectors in a row passes the head with 8 or 9 sectors between (8 after an odd sector, 9 after an even one), in the
;; time the computer takes to ask for it; revision B writes every 7th, which leaves 12 between.
;; See: <WRITE_TRACK>
FORMAT_ORDER:
.if VERSION = VERSION_B
    SECTOR 7
    SECTOR 14
    SECTOR 3
    SECTOR 10
    SECTOR 17
    SECTOR 6
    SECTOR 13
    SECTOR 2
    SECTOR 9
    SECTOR 16
    SECTOR 5
    SECTOR 12
    SECTOR 1
    SECTOR 8
    SECTOR 15
    SECTOR 4
    SECTOR 11
.else
    SECTOR 1
    SECTOR 3
    SECTOR 5
    SECTOR 7
    SECTOR 9
    SECTOR 11
    SECTOR 13
    SECTOR 15
    SECTOR 17
    SECTOR 2
    SECTOR 4
    SECTOR 6
    SECTOR 8
    SECTOR 10
    SECTOR 12
    SECTOR 14
    SECTOR 16
.endif
.assert * = $0880, "WRITE_TRACK's pointer ends the table when its low byte reaches $80."

;; Waits for one of RUN_ON's Restores to end, polling the bus all the while. A command that arrives and runs ends at
;; COMMAND_DONE, which starts the run-on again; a refused frame, or one for another drive, comes back here.
;; In: A = FLAG_POLL_ONCE
;; See: <RUN_ON>
RUN_ON_WAIT:
    jsr SET_FLAGS
RUN_ON_POLL:
    bit RIOT_PORTA
    bvs RUN_ON_NEXT                     ; the Restore has ended
    jsr POLL
    jmp RUN_ON_POLL
RUN_ON_NEXT:
    dec RUN_ON_COUNT
    bpl RUN_ON

;; Parks the head: steps it in to track 39, PARK_STEPS times, polling the bus between steps, then stops the motor and
;; the stepper and waits for a command.
;; See: <MOTOR_OFF>
PARK:
    ldx #$80                            ; in
    ldy PARK_STEPS
    beq MOTOR_OFF
    jsr STEP
    sty PARK_STEPS
    jsr POLL
PARK_WAIT:
    lda RIOT_FLAGS
    bpl PARK_WAIT                       ; the step's time
    bmi PARK

;; Stops the motor and the stepper, and waits for a command. A Read, Put, Write or Format then waits for the motor to
;; come up to speed before it uses the disk (MOTOR_READY).
;; See: <POLL>
MOTOR_OFF:
    lda #PA_HIGH
    sta RIOT_PORTA                      ; the motor off
    lda #$00
    sta RIOT_PORTB                      ; the phases off
    lda #<(~FLAG_POLL_ONCE)
    jsr CLEAR_FLAGS
    lda #FLAG_MOTOR_STARTING
    jsr SET_FLAGS
    jmp POLL                            ; never returns: a command that runs ends at COMMAND_DONE

;; Checks the command frame's sector number, from 1 to 720.
;; Out: carry = set if the number is out of range
;; Uses: A, X
CHECK_SECTOR:
    ldx FRAME_AUX2
    lda FRAME_AUX1
    beq CHECK_SECTOR_LOW_ZERO
CHECK_SECTOR_HIGH:
    cpx #>LAST_SECTOR+1
    bcs CHECK_SECTOR_BAD                ; 768 or more
    cmp #<(LAST_SECTOR+1)
    bcs CHECK_SECTOR_HIGH_PAGE
CHECK_SECTOR_GOOD:
    clc
    rts
CHECK_SECTOR_LOW_ZERO:
    cpx #$00
    bne CHECK_SECTOR_HIGH
CHECK_SECTOR_BAD:
    sec
    rts
CHECK_SECTOR_HIGH_PAGE:
    cpx #>LAST_SECTOR
    beq CHECK_SECTOR_BAD                ; 721 to 767
    jmp CHECK_SECTOR_GOOD

    .byte $60                           ; unreached

;; Waits A times 256 loops of Y, about 2.56 ms each (A = 0 waits 256).
;; In: A = the count, Y = where the first loop starts (0 for a whole one)
;; Out: Y = 0
;; Uses: DELAY_COUNT
;; Keeps: X
DELAY:
    sta DELAY_COUNT
DELAY_LOOP:
    dey
    bne DELAY_LOOP
    dec DELAY_COUNT
    bne DELAY_LOOP
    rts

;; Steps the head one track, by turning the stepper's phases on one, and starts the RIOT's timer for the step's time.
;; A caller waits for the timer's flag before the next step.
;;
;; X gives the direction: STEP increments it, and steps in toward track 39 if the result is negative, out toward track
;; 0 if not, so a caller sets it once to $80 for in or to a value from $00 for out and calls repeatedly. HEAD_TRACK
;; follows the head.
;; In: X = the direction, Y = the steps left
;; Out: X incremented, Y decremented, zero = set and negative = clear when Y reaches 0, negative = set when it reaches
;;      $FF
;; Uses: A, STEP_PHASES
STEP:
    lda #STEP_TIME
    sta RIOT_TIMER_64
    lda RIOT_PORTB
    and #PB_PHASES
    inx
    bmi STEP_IN
    inc HEAD_TRACK                      ; out: one track less
    lsr a
    sta STEP_PHASES
    and #PB_PHASE1>>1                   ; phase 1 shifted out of the phases
    beq STEP_SAME
    lda #PB_PHASE4                      ; round to phase 4
    ora STEP_PHASES
    bpl STEP_SET
STEP_IN:
    dec HEAD_TRACK                      ; in: one track more
    asl a
    sta STEP_PHASES
    and #PB_PHASE4<<1                   ; phase 4 shifted out of the phases
    beq STEP_SAME
    lda #PB_PHASE1                      ; round to phase 1
    ora STEP_PHASES
    bpl STEP_SET
STEP_SAME:
    lda STEP_PHASES
STEP_SET:
    sta RIOT_PORTB
    dey
    rts

;; Read ('R'): reads a sector and sends it after Complete, or after Error if it couldn't be read in TRIES tries. A
;; sector number out of range is refused.
;; See: <READ_SECTOR>, <CHECK_RESULT>
COMMAND_READ_SECTOR:
    jsr CHECK_SECTOR
    bcs READ_REFUSE
    jsr ACKNOWLEDGE
    jsr MOTOR_ON
    jsr SPIN_UP
    jsr POSITION

;; Reads the sector the FD1771 is set up for into BUFFER, until the controller ends the command; then checks the
;; result and tries again, or sends the frame.
;; In: X = $FF, Y = the tries left
READ_SECTOR:
    lda #<(~FDC_READ_SECTOR)
    sta FDC_COMMAND
READ_SECTOR_WAIT:
    bvs READ_SECTOR_DONE                ; INTRQ: the command has ended
    lda RIOT_TIMER_IRQ_ON               ; clears the index pulse
READ_SECTOR_BYTE:
    bit RIOT_PORTA
    bpl READ_SECTOR_WAIT                ; no DRQ
    lda FDC_DATA
    inx
    sta BUFFER,x
    bpl READ_SECTOR_BYTE
READ_SECTOR_DONE:
    jsr CHECK_RESULT
    bcs READ_SECTOR_FAILED

;; Sends Complete and the 128 bytes of BUFFER as a data frame, and ends the command.
;; See: <SEND_FRAME>
SEND_COMPLETE_FRAME:
    lda #SIO_COMPLETE

;; Sends A and the 128 bytes of BUFFER as a data frame with its checksum, and ends the command.
;; In: A = SIO_COMPLETE or SIO_ERROR
;; See: <COMMAND_DONE>
SEND_FRAME:
    sta SEND_BYTE
    jsr BUFFER_CHECKSUM
    sta DATA_CHECKSUM
    jsr DRIVE_LINE
    jsr SEND_BUFFER
    jmp COMMAND_DONE

READ_SECTOR_FAILED:
    bne READ_SECTOR                     ; tries left

;; Sends Error and the 128 bytes of BUFFER as a data frame, and ends the command.
;; See: <SEND_FRAME>
SEND_ERROR_FRAME:
    lda #SIO_ERROR
    jmp SEND_FRAME

READ_REFUSE:
    jmp REFUSE

    .byte $AD                           ; unreached

;; Checks how the FD1771's command ended, keeping its status for a Status command, and gets the controller ready to
;; try again.
;;
;; On an error, the third try (Y = 2) that couldn't find the sector recalibrates first: it steps out to track 0 and
;; back to the sector's track. A failure sets STATUS_FAILED; a success clears it.
;; In: Y = the tries left, this one included
;; Out: carry = set on an error, Y = the tries left after this one, zero = set if none are, X = $FF
;; Uses: A
;; See: <FDC_RESTART>
CHECK_RESULT:
    lda FDC_STATUS
    sta CONTROLLER_STATUS
    eor #$FF
    bne CHECK_RESULT_ERROR
    clc
    lda #<(~STATUS_FAILED)
    jsr MASK_STATUS
CHECK_RESULT_RESTART:
    jsr FDC_RESTART
    dey
    rts
CHECK_RESULT_ERROR:
    cpy #$02
    bne OPERATION_FAILED
    and #FDC_NOT_FOUND
    beq OPERATION_FAILED
    sty DELAY_COUNT                     ; SPIN_UP doesn't wait now, so DELAY_COUNT keeps Y
    jsr SPIN_UP
    ldy #TRACKS+3                       ; 44 steps
    jsr RECALIBRATE
    lda TARGET_TRACK
    jsr SEEK_DISTANCE
    jsr SEEK
    ldy DELAY_COUNT

;; Marks the operation failed: sets STATUS_FAILED, then gets the controller ready to try again, as CHECK_RESULT does.
;; In: Y = the tries left, this one included
;; Out: carry = set, Y = the tries left after this one, zero = set if none are, X = $FF
;; Uses: A
;; See: <CHECK_RESULT>
OPERATION_FAILED:
    lda #STATUS_FAILED
    jsr ADD_STATUS
    sec
    jmp CHECK_RESULT_RESTART

;; Format ('!'): steps out to track 0, writes the 40 tracks, then reads each sector back, track 39 to track 0, and
;; sends the list of the bad sectors' numbers, ended by $FFFF, after Complete, or after Error if there were any. A
;; write-protected disk sends Error with an empty list.
;; See: <WRITE_TRACK>, <FORMAT_VERIFY>
COMMAND_FORMAT_DISK:
    jsr ACKNOWLEDGE
    jsr MOTOR_ON
    jsr SPIN_UP
    ldy #TRACKS+3                       ; 44 steps
    jsr RECALIBRATE
    jsr PREPARE
    lda RIOT_PORTA
    and #PA_WRITE_PROTECT
    beq FORMAT_TRACKS
    lda #STATUS_WRITE_PROTECTED
    jsr ADD_STATUS
    jmp FORMAT_FAILED
FORMAT_TRACKS:
    lda #<(~0)
    sta FORMAT_TRACK
    jsr WRITE_TRACK
FORMAT_NEXT:
    dec FORMAT_TRACK
    lda FORMAT_TRACK
    cmp #<(~TRACKS)
    beq FORMAT_WRITTEN
    ldx #$80                            ; in
    jsr FORMAT_STEP_AND_WRITE
    jmp FORMAT_NEXT
FORMAT_WRITTEN:
    jmp FORMAT_VERIFY

    .byte $B0, $00                      ; unreached

;; Steps the head in to the next track and formats it.
;; In: X = $80, FORMAT_TRACK = the track, complemented
;; See: <WRITE_TRACK>
FORMAT_STEP_AND_WRITE:
    jsr FORMAT_STEP

;; Formats the track under the head: writes its 18 sectors, sector 18 first and then FORMAT_ORDER's, each with its ID
;; field and 128 bytes that read as $00, and ends the command with a Force Interrupt, keeping what was written.
;;
;; The RIOT's timer gives the FD1771 the index pulse it waits for to start writing, 27 ms after the command, then is
;; started again for half a second, so that no other pulse comes before the track is written. If the controller ends
;; the command itself, the format has failed.
;; In: FORMAT_TRACK = the track, complemented
;; Out: X = $FF
;; Uses: A, Y, ORDER_POINTER, FORMAT_SECTOR
;; See: <FORMAT_FAILED>
WRITE_TRACK:
    lda #<(FORMAT_ORDER-1)
    sta ORDER_POINTER
    lda #>FORMAT_ORDER
    sta ORDER_POINTER+1
    lda RIOT_TIMER_IRQ_OFF              ; no index pulse yet
    lda #<(~SECTORS)
    sta FORMAT_SECTOR                   ; sector 18 first
    ldy #<(~FDC_GAP)
    ldx #<(~FDC_GAP)
    lda #<(~FDC_WRITE_TRACK)
    sta FDC_COMMAND
    jsr WRITE_BYTE                      ; the first byte, before the index
    lda #INDEX_TIME
    sta RIOT_TIMER_1024
    ldy #$FF
    jsr WRITE_REPEAT                    ; 255 gap bytes, from the index
    stx RIOT_TIMER_1024                 ; X = $FF: half a second
    ldy #<(~FDC_INDEX_MARK)
    jsr WRITE_BYTE
    ldy #11
    jsr WRITE_REPEAT
WRITE_TRACK_SECTOR:
    ldy #6
    jsr WRITE_REPEAT
    ldy #<(~FDC_ID_MARK)
    jsr WRITE_BYTE
    ldy FORMAT_TRACK
    jsr WRITE_BYTE
    ldy #<(~FDC_SIDE)
    jsr WRITE_BYTE
    ldy FORMAT_SECTOR
    jsr WRITE_BYTE
    ldy #<(~FDC_SECTOR_LENGTH)
    jsr WRITE_BYTE
    ldy #<(~FDC_CRC)
    jsr WRITE_BYTE
    ldy #17
    jsr WRITE_REPEAT
    ldy #<(~FDC_DATA_MARK)
    jsr WRITE_BYTE
    ldy #SECTOR_SIZE
    ldx #<(~FDC_DATA_FILL)
    jsr WRITE_REPEAT
    ldy #<(~FDC_CRC)
    jsr WRITE_BYTE
    ldy #9
    ldx #<(~FDC_GAP)
    jsr WRITE_REPEAT
    jsr WRITE_BYTE                      ; Y = 0: the FD1771 writes $FF
    inc ORDER_POINTER
    bmi WRITE_TRACK_END                 ; past the table
    jsr WRITE_BYTE
    lda (ORDER_POINTER+1,x)             ; X = $FF: (ORDER_POINTER)
    sta FORMAT_SECTOR
    jmp WRITE_TRACK_LAST
WRITE_TRACK_ENDED:
    bvs FORMAT_FAILED
WRITE_TRACK_LAST:
    bit RIOT_PORTA
    bpl WRITE_TRACK_ENDED
    sty FDC_DATA
    jmp WRITE_TRACK_SECTOR
WRITE_TRACK_END:
    lda #<(~FDC_FORCE_INTERRUPT)
    sta FDC_COMMAND
    rts

WRITE_REPEAT_ENDED:
    bvs FORMAT_FAILED

;; Writes Y copies of X to the FD1771 as it asks for them; if the controller ends the command, the format has failed.
;; In: X = the byte, complemented, Y = the count (0 for 256)
;; Out: Y = 0
;; Keeps: A, X
;; See: <WRITE_TRACK>
WRITE_REPEAT:
    bit RIOT_PORTA
    bpl WRITE_REPEAT_ENDED
    stx FDC_DATA
    dey
    bne WRITE_REPEAT
    rts

WRITE_BYTE_ENDED:
    bvs FORMAT_FAILED

;; Writes Y to the FD1771 when it asks for it; if the controller ends the command, the format has failed.
;; In: Y = the byte, complemented
;; Keeps: A, X, Y
;; See: <WRITE_TRACK>
WRITE_BYTE:
    bit RIOT_PORTA
    bpl WRITE_BYTE_ENDED
    sty FDC_DATA
    rts

;; Fails a format: sends Error with an empty list of bad sectors, keeping the FD1771's status.
;; See: <SEND_FAILED>
FORMAT_FAILED:
    ldx #BAD_SECTORS_END
    stx BUFFER
    stx BUFFER+1
    lda FDC_STATUS
    sta CONTROLLER_STATUS
    jmp SEND_FAILED

;; A format's verify: reads back each track's sectors, from track 39 to track 0, and lists each sector that can't be
;; read in FORMAT_VERIFY_TRIES tries in BUFFER.
;;
;; Each track is read every fourth sector, so that each passes the head soon after the last: revision C reads 1, 5,
;; 9, 13, 17, 4, 8, 12, 16, 3, 7, 11, 15, 2, 6, 10, 14, 18, and revision B 17, 13, 9, 5, 1, 15, 11, 7, 3, 16, 12, 8,
;; 4, 18, 14, 10, 6, 2.
;; See: <FORMAT_END>, <VERIFY_BAD_SECTOR>
FORMAT_VERIFY:
    ldx #$00
    stx BAD_SECTOR_INDEX
FORMAT_VERIFY_TRACK:
    lda HEAD_TRACK
    sta FDC_TRACK
.if VERSION = VERSION_B
    lda #<(~17)
.else
    lda #<(~1)
.endif
FORMAT_VERIFY_SECTOR:
    sta TARGET_SECTOR
    sta FDC_SECTOR
    ldy #FORMAT_VERIFY_TRIES
    sty VERIFY_TRIES
FORMAT_VERIFY_TRY:
    jsr READ_TO_CHECK
    ldy #$01
    jsr CHECK_RESULT
    bcs FORMAT_VERIFY_FAILED

;; Goes on to the next sector of a format's verify, then to the next track out, or ends the format after track 0.
;; In: TARGET_SECTOR = the sector just read, complemented
;; See: <FORMAT_VERIFY>
FORMAT_VERIFY_NEXT:
    lda TARGET_SECTOR
.if VERSION = VERSION_B
    clc
    adc #4                              ; 4 back
    bne FORMAT_VERIFY_NEXT_1
    lda #<(~16)                         ; after 3
FORMAT_VERIFY_NEXT_1:
    cmp #<(~0)
    bne FORMAT_VERIFY_NEXT_2
    lda #<(~18)                         ; after 4
FORMAT_VERIFY_NEXT_2:
    cmp #<(~(-3))
    bne FORMAT_VERIFY_NEXT_3
    lda #<(~15)                         ; after 1
FORMAT_VERIFY_NEXT_3:
    cmp #<(~(-2))                       ; after 2: the track is done
.else
    sec
    sbc #4                              ; 4 on
    cmp #<(~21)
    bne FORMAT_VERIFY_NEXT_1
    lda #<(~4)                          ; after 17
FORMAT_VERIFY_NEXT_1:
    cmp #<(~20)
    bne FORMAT_VERIFY_NEXT_2
    lda #<(~3)                          ; after 16
FORMAT_VERIFY_NEXT_2:
    cmp #<(~19)
    bne FORMAT_VERIFY_NEXT_3
    lda #<(~2)                          ; after 15
FORMAT_VERIFY_NEXT_3:
    cmp #<(~22)                         ; after 18: the track is done
.endif
    bne FORMAT_VERIFY_SECTOR
    lda HEAD_TRACK
    cmp #<(~0)
    beq FORMAT_VERIFY_DONE
    ldx #$00                            ; out
    ldy #$01
    jsr SEEK
    jmp FORMAT_VERIFY_TRACK
FORMAT_VERIFY_DONE:
    jmp FORMAT_END
FORMAT_VERIFY_FAILED:
    dec VERIFY_TRIES
    bne FORMAT_VERIFY_TRY
    ldx BAD_SECTOR_INDEX
    jmp VERIFY_BAD_SECTOR

;; Adds STATUS_MOTOR_ON to the drive status if the motor is running.
;; Uses: A
;; Keeps: X, Y
ADD_MOTOR_STATUS:
    lda RIOT_PORTA
    lsr a
    lsr a                               ; carry = PA_MOTOR
    lda #STATUS_MOTOR_ON
    bcs ADD_STATUS
    lda #$00

;; Sets the drive status's bits in A.
;; In: A = the bits
;; Keeps: X, Y
ADD_STATUS:
    ora DRIVE_STATUS
    sta DRIVE_STATUS
    rts

;; Sets the drive status to A.
;; In: A = the status
;; Keeps: X, Y
SET_STATUS:
    pha
    lda #$00
    and DRIVE_STATUS
    sta DRIVE_STATUS
    pla
    jmp ADD_STATUS

    .byte $60                           ; unreached

;; Sets the firmware's flags in A.
;; In: A = the flags
;; Keeps: X, Y
SET_FLAGS:
    ora DRIVE_FLAGS
    sta DRIVE_FLAGS
    rts

;; Clears the firmware's flags that are clear in A.
;; In: A = the flags to keep
;; Keeps: X, Y
CLEAR_FLAGS:
    and DRIVE_FLAGS
    sta DRIVE_FLAGS
    rts

;; Clears the drive status's bits but STATUS_WRITE_PROTECTED, as at reset and after a Status command has sent it.
;; Keeps: X, Y
KEEP_WRITE_PROTECT:
    lda #STATUS_WRITE_PROTECTED

;; Clears the drive status's bits that are clear in A.
;; In: A = the bits to keep
;; Keeps: X, Y
MASK_STATUS:
    and DRIVE_STATUS
    sta DRIVE_STATUS
    rts

;; Receives bytes from the computer into the command frame's bytes from X, until X reaches RECEIVE_END: waits for each
;; start bit, then samples the 8 bits every 26 cycles. The line is complemented, so each byte is complemented back
;; during the next byte's start bit, and the last after the loop.
;; In: X = the first byte's index from FRAME_DEVICE, RECEIVE_END = the index after the last
;; Out: X = RECEIVE_END
;; Uses: A, Y
RECEIVE_BYTES:
    lda RIOT_PORTB
    bpl RECEIVE_BYTES                   ; no start bit
    txa
    beq RECEIVE_BYTES_FIRST
    lda FRAME_DEVICE-1,x
    eor #$FF
    sta FRAME_DEVICE-1,x                ; the last byte, complemented back
RECEIVE_BYTES_START:
    nop
    nop
    nop
    ldy #$78                            ; 8 bits
RECEIVE_BYTES_BIT:
    nop
    nop
    nop
    nop
    lda RIOT_PORTB
    rol a
    ror FRAME_DEVICE,x
    iny
    bpl RECEIVE_BYTES_BIT
    inx
    cpx RECEIVE_END
    bne RECEIVE_BYTES
    lda FRAME_DEVICE-1,x
    eor #$FF
    sta FRAME_DEVICE-1,x
    rts
RECEIVE_BYTES_FIRST:
    nop                                 ; as long as complementing a byte
    nop
    nop
    jmp RECEIVE_BYTES_START

;; Waits 5 ms and steps the head one track, for a format.
;; In: X = the direction, as STEP takes it
;; See: <STEP>
FORMAT_STEP:
    lda #DELAY_FORMAT_STEP
    jsr DELAY
    jsr STEP
    rts

;; Receives a data frame from the computer: 128 bytes into BUFFER, then its checksum into DATA_CHECKSUM. Like
;; RECEIVE_BYTES, each byte is complemented back during the next one's start bit.
;; Out: X = 7
;; Uses: A, Y, RECEIVE_END
;; See: <RECEIVE_BYTES>
RECEIVE_DATA_FRAME:
    ldx #$00
    ldy #DATA_CHECKSUM+1-FRAME_DEVICE
    sty RECEIVE_END
RECEIVE_DATA_FRAME_BYTE:
    lda RIOT_PORTB
    bpl RECEIVE_DATA_FRAME_BYTE         ; no start bit
    txa
    beq RECEIVE_DATA_FRAME_FIRST
    lda BUFFER-1,x
    eor #$FF
    sta BUFFER-1,x
RECEIVE_DATA_FRAME_START:
    nop
    nop
    nop
    ldy #$78                            ; 8 bits
RECEIVE_DATA_FRAME_BIT:
    nop
    nop
    nop
    lda BUFFER                          ; for time
    lda RIOT_PORTB
    rol a
    ror BUFFER,x
    iny
    bpl RECEIVE_DATA_FRAME_BIT
    inx
    bpl RECEIVE_DATA_FRAME_NEXT
    ldx #DATA_CHECKSUM-FRAME_DEVICE
    jsr RECEIVE_BYTES                   ; complements SEND_BYTE first, which is free
    lda BUFFER+SECTOR_SIZE-1-(DATA_CHECKSUM+1-FRAME_DEVICE),x
    eor #$FF
    sta BUFFER+SECTOR_SIZE-1-(DATA_CHECKSUM+1-FRAME_DEVICE),x ; the last byte, complemented back
    rts
RECEIVE_DATA_FRAME_NEXT:
    nop                                 ; as long as the branch
    jmp RECEIVE_DATA_FRAME_BYTE
RECEIVE_DATA_FRAME_FIRST:
    nop                                 ; as long as complementing a byte
    nop
    nop
    jmp RECEIVE_DATA_FRAME_START

;; Adds up the command frame's bytes from X to before RECEIVE_END, with each carry added back in, the SIO checksum,
;; and compares the sum with the byte after them.
;; In: X = the first byte's index from FRAME_DEVICE, RECEIVE_END = the index after the last
;; Out: A = the checksum, zero = set if the byte after matches, X = RECEIVE_END
;; Keeps: Y
CHECKSUM_BYTES:
    lda #$00
    clc
CHECKSUM_BYTES_NEXT:
    adc FRAME_DEVICE,x
    php
    inx
    cpx RECEIVE_END
    beq CHECKSUM_BYTES_DONE
    plp
    jmp CHECKSUM_BYTES_NEXT
CHECKSUM_BYTES_DONE:
    plp
    adc #$00
    cmp FRAME_DEVICE,x
    rts

;; Turns the command frame's sector number, 1 to 720, into its track (0-39) and its sector on the track (1-18), into
;; TARGET_TRACK and TARGET_SECTOR, complemented.
;;
;; It divides by 16, the number being 16 x q + r, then takes 16 back into r until 2 x q is less than r: the number is
;; then 18 x q + (r - 2 x q), with the sector from 1 to 18.
;; Uses: A, X, FRAME_AUX1, FRAME_AUX2, SAVED_AUX1, SAVED_AUX2
SECTOR_POSITION:
    lda FRAME_AUX2
    sta SAVED_AUX2
    lda FRAME_AUX1
    sta SAVED_AUX1
    ldx #$04
SECTOR_POSITION_SHIFT:
    ror FRAME_AUX2
    ror a
    dex
    bne SECTOR_POSITION_SHIFT
    ror FRAME_AUX2
    ldx #$04
SECTOR_POSITION_REMAINDER:
    lsr FRAME_AUX2
    dex
    bne SECTOR_POSITION_REMAINDER       ; FRAME_AUX2 = r, A = q
SECTOR_POSITION_TRY:
    asl a
    cmp FRAME_AUX2
    bcs SECTOR_POSITION_LESS
    sta FRAME_AUX1
    lsr a
    eor #$FF
    sta TARGET_TRACK
    sec
    lda FRAME_AUX2
    sbc FRAME_AUX1
    eor #$FF
    sta TARGET_SECTOR
    rts
SECTOR_POSITION_LESS:
    lsr a
    tax
    dex
    lda #16
    clc
    adc FRAME_AUX2
    sta FRAME_AUX2
    txa
    jmp SECTOR_POSITION_TRY

;; Works out the steps from the head's track to another, and their direction.
;; In: A = the track, complemented
;; Out: Y = the steps, X = the direction, as STEP takes it: $00 out or $80 in, zero = set if Y is 0
;; Uses: A
SEEK_DISTANCE:
    ldx #$00
    ldy #$00
    sec
    sbc HEAD_TRACK
    beq SEEK_DISTANCE_DONE
    bpl SEEK_DISTANCE_COUNT
    ldx #$80
    eor #$FF
    clc
    adc #$01
SEEK_DISTANCE_COUNT:
    tay
SEEK_DISTANCE_DONE:
    rts

;; Sets STATUS_WRITE_PROTECTED in the drive status if the disk is write-protected, and clears it if not.
;; Uses: A
;; Keeps: X, Y
WRITE_PROTECT_STATUS:
    lda RIOT_PORTA
    and #PA_WRITE_PROTECT
    beq WRITE_PROTECT_STATUS_CLEAR
    lda #STATUS_WRITE_PROTECTED
    jsr ADD_STATUS
    rts
WRITE_PROTECT_STATUS_CLEAR:
    lda #<(~STATUS_WRITE_PROTECTED)
    jsr MASK_STATUS
    rts

;; Starts the motor if it's stopped: turns it on and starts the FD1771 on a Seek of 12 steps at its slowest rate,
;; which, with nothing wired to its stepper, times the motor's spin-up for MOTOR_READY. Each command that runs the
;; motor resets RUN_ON_COUNT for the run-on afterward.
;; Uses: A
;; Keeps: X, Y
;; See: <MOTOR_READY>, <RUN_ON>
MOTOR_ON:
    lda RIOT_PORTA
    lsr a
    lsr a                               ; carry = PA_MOTOR
    bcs MOTOR_ON_COUNT
    lda #PA_OUTPUTS
    sta RIOT_PORTA                      ; the motor on
    sta FDC_DATA                        ; the Seek's destination, 245
    lda #<(~233)
    sta FDC_TRACK
    lda #<(~FDC_SEEK)
    sta FDC_COMMAND
MOTOR_ON_COUNT:
    lda #$01
    sta RUN_ON_COUNT
    rts

;; Waits for the motor to come up to speed if FLAG_MOTOR_STARTING says it may not be: waits for the FD1771's command
;; to end: MOTOR_ON's Seek when the motor was started from rest, and otherwise whatever the FD1771 is running, a
;; run-on's Restore, or nothing, when INTRQ is still set from the last. Then sets the drive status to STATUS_MOTOR_ON
;; alone.
;; Uses: A
;; Keeps: X, Y
;; See: <MOTOR_ON>
MOTOR_READY:
    lda DRIVE_FLAGS
    lsr a
    lsr a
    lsr a                               ; carry = FLAG_MOTOR_STARTING
    bcc MOTOR_READY_STATUS
MOTOR_READY_WAIT:
    bit RIOT_PORTA
    bvc MOTOR_READY_WAIT                ; the Seek hasn't ended
    lda #<(~FLAG_MOTOR_STARTING)
    jsr CLEAR_FLAGS
MOTOR_READY_STATUS:
    lda #STATUS_MOTOR_ON
    jsr SET_STATUS
    rts

;; Waits for the computer to drop the command line, then acknowledges the command frame.
;; Uses: A, X, Y
;; See: <SEND_ACK>
ACKNOWLEDGE:
    bit RIOT_PORTB
    bvs ACKNOWLEDGE

;; Sends Acknowledge.
;; Uses: A, X, Y
SEND_ACK:
    lda #SIO_ACK

;; Sends a byte to the computer.
;; In: A = the byte
;; Uses: A, X, Y
SEND_ONE:
    sta SEND_BYTE
    jsr DRIVE_LINE
    jsr SEND_SERIAL
    jsr RELEASE_LINE
    rts

;; Finds track 0: holds the head on track 0's phases, then steps it out Y+1 times, more than enough to bring it up
;; against the stop from anywhere, and waits about 50 ms for it to settle. HEAD_TRACK is then track 0.
;; In: Y = the steps, less one
;; Out: Y = 0
;; Uses: A, X
RECALIBRATE:
    ldx #TRACK0_PHASES
    stx RIOT_PORTB
RECALIBRATE_STEP:
    jsr STEP
    bmi RECALIBRATE_SETTLE
RECALIBRATE_WAIT:
    lda RIOT_FLAGS
    bpl RECALIBRATE_WAIT                ; the step's time
    jmp RECALIBRATE_STEP
RECALIBRATE_SETTLE:
    sty HEAD_TRACK                      ; $FF: track 0
    txa
    ldx #20
RECALIBRATE_DELAY:
    dey
    bne RECALIBRATE_DELAY
    dex
    bne RECALIBRATE_DELAY
    tax
    rts

;; Polls the bus: watches the computer's power, and receives a command frame when the command line is asserted. A
;; frame for this drive runs its command, which ends at COMMAND_DONE; a refused one comes back here.
;;
;; With FLAG_POLL_ONCE set, it returns when no command is waiting; otherwise it waits for one. When the computer comes
;; on, it waits 105 ms first.
;; Uses: A, X, Y
;; See: <DISPATCH>
POLL:
    lda RIOT_PORTB
    lsr a
    lsr a                               ; carry = PB_POWER
    bcs POLL_COMPUTER_OFF
    lda DRIVE_FLAGS
    lsr a                               ; carry = FLAG_COMPUTER_OFF
    bcs POLL_COMPUTER_ON
    bit RIOT_PORTB
    bvc POLL_IDLE                       ; no command
    bit DRIVE_FLAGS
    bvc POLL_RECEIVE                    ; no FLAG_COMMAND_DELAY
    lda #DELAY_COMPUTER_ON
    jsr DELAY
    bit RIOT_PORTB
    bvs POLL_RECEIVE
POLL_IDLE:
    lda DRIVE_FLAGS
    and #FLAG_POLL_ONCE|FLAG_COMMAND_DELAY
    bne POLL_RETURN
    jmp POLL
POLL_RETURN:
    rts
POLL_COMPUTER_ON:
    lda #DELAY_COMPUTER_ON
    jsr DELAY
    lda #<(~FLAG_COMPUTER_OFF)
    jsr CLEAR_FLAGS
    jmp POLL
POLL_COMPUTER_OFF:
    lda #FLAG_COMPUTER_OFF
    jsr SET_FLAGS
    jmp POLL_IDLE

;; Receives a command frame and checks its checksum, then runs it if it's for this drive, whose number the switches
;; on PA2 and PA0 give: '1' with both, '2' with PA2's, '3' with neither and '4' with PA0's. A frame for another drive
;; is let pass: the poll waits for the command line to drop.
;; See: <DISPATCH>
POLL_RECEIVE:
    lda #FLAG_RECEIVING
    jsr SET_FLAGS
    ldx #$00
    lda #FRAME_SIZE
    sta RECEIVE_END
    jsr RECEIVE_BYTES
    ldx #$00
    dec RECEIVE_END
    jsr CHECKSUM_BYTES
    beq POLL_DRIVE
    lda #FLAG_BAD_FRAME
    jsr SET_FLAGS
POLL_DRIVE:
    ldx #'4'
    lda RIOT_PORTA
    and #PA_DRIVE_A|PA_DRIVE_B
    beq POLL_DRIVE_3
    cmp #PA_DRIVE_A
    beq POLL_DRIVE_2
    cmp #PA_DRIVE_B
    beq POLL_DRIVE_4
    dex
POLL_DRIVE_2:
    dex
POLL_DRIVE_3:
    dex
POLL_DRIVE_4:
    cpx FRAME_DEVICE
    beq POLL_RUN
POLL_OTHER_DRIVE:
    bit RIOT_PORTB
    bvs POLL_OTHER_DRIVE                ; the command line is still asserted
    lda #<(~(FLAG_RECEIVING|FLAG_BAD_FRAME))
    jsr CLEAR_FLAGS
    jmp POLL
POLL_RUN:
    jsr DISPATCH
    jmp POLL

;; Status ('S'): acknowledges, then sends Complete and the 4-byte status block as a data frame: the drive status, the
;; FD1771's last status, the format timeout and 0. Afterward the drive status keeps only its write-protect bit and
;; the motor's.
;; See: <COMMAND_DONE>
COMMAND_STATUS_BLOCK:
    jsr SEND_ACK
    ldx #DRIVE_STATUS-FRAME_DEVICE
    ldy #DRIVE_STATUS+STATUS_SIZE-FRAME_DEVICE
    sty RECEIVE_END
    jsr CHECKSUM_BYTES
    sta STATUS_CHECKSUM
    lda #SIO_COMPLETE
    sta SEND_BYTE
    jsr DRIVE_LINE
    ldx #$80-STATUS_SIZE-2
    jsr SEND_SERIAL
COMMAND_STATUS_BLOCK_NEXT:
    ldy DRIVE_STATUS-($80-STATUS_SIZE-1),x
    sty SEND_BYTE
    jsr SEND_SERIAL_A
    bpl COMMAND_STATUS_BLOCK_NEXT
    jsr RELEASE_LINE
    jsr KEEP_WRITE_PROTECT
    jsr ADD_MOTOR_STATUS
    jmp COMMAND_DONE

;; Turns a track and a sector on it into the sector's number, 18 x the track + the sector, and stores it in BUFFER
;; at X, low byte first, for a format's list of bad sectors.
;; In: HEAD_TRACK = the track, complemented, TARGET_SECTOR = the sector, complemented, X = the index in BUFFER
;; Out: X = the index of the high byte
;; Uses: A, Y
SECTOR_NUMBER:
    ldy #$00
    sty NUMBER_HIGH
    lda TARGET_SECTOR
    eor #$FF
    sta NUMBER_SECTOR
    lda HEAD_TRACK
    eor #$FF
    asl a
    sta NUMBER_TRACK2
    asl a
    asl a
    rol NUMBER_HIGH
    asl a
    rol NUMBER_HIGH                     ; 16 x the track
    adc NUMBER_TRACK2
    tay
    lda #$00
    adc NUMBER_HIGH
    jmp SECTOR_NUMBER_STORE

;; Runs the command frame's command, or refuses it for a bad checksum or an unknown command; Read, Put and Write go to
;; REFUSE themselves for a sector number out of range. The commands from $4F to $57 go through COMMAND_TABLE by their
;; low three bits.
;; See: <COMMAND_TABLE>, <REFUSE>
DISPATCH:
    lda DRIVE_FLAGS
    lsr a
    lsr a                               ; carry = FLAG_BAD_FRAME
    bcs REFUSE
    lda FRAME_COMMAND
    cmp #COMMAND_PUT-1                  ; a bug: 'O' passes too, and runs as Write
    bcc DISPATCH_FORMAT
    cmp #COMMAND_WRITE+1
    bcs DISPATCH_FORMAT
    and #$07
    sta COMMAND_INDEX
    asl a
    adc COMMAND_INDEX
    adc #<COMMAND_TABLE
    sta COMMAND_VECTOR
    lda #$00
    adc #>COMMAND_TABLE
    sta COMMAND_VECTOR+1
    jmp (COMMAND_VECTOR)
DISPATCH_FORMAT:
    cmp #COMMAND_FORMAT
    beq DISPATCH_FORMAT_DISK

;; Refuses the command frame: sets the drive status to STATUS_BAD_COMMAND and the motor's bit, waits for the command
;; line to drop and sends Not Acknowledge.
;; Uses: A, X, Y
REFUSE:
    lda #STATUS_BAD_COMMAND
    jsr SET_STATUS
    jsr ADD_MOTOR_STATUS
REFUSE_WAIT:
    bit RIOT_PORTB
    bvs REFUSE_WAIT
    lda #SIO_NAK
    jsr SEND_ONE
    lda #<(~FLAG_BAD_FRAME)
    jsr CLEAR_FLAGS
    rts

DISPATCH_FORMAT_DISK:
    jmp COMMAND_FORMAT_DISK

    .byte $01                           ; unreached

;; Ends SECTOR_NUMBER: adds the sector to the track's part and stores the number.
;; In: Y = 18 x the track's low byte, A = its high byte, X = the index in BUFFER
;; Out: X = the index of the high byte
;; Uses: A, NUMBER_HIGH
;; See: <SECTOR_NUMBER>
SECTOR_NUMBER_STORE:
    sta NUMBER_HIGH
    tya
    clc
    adc NUMBER_SECTOR
    sta BUFFER,x
    lda #$00
    adc NUMBER_HIGH
    inx
    sta BUFFER,x
    rts

;; Adds up BUFFER's 128 bytes with each carry added back in, the SIO checksum, and compares the sum with
;; DATA_CHECKSUM.
;; Out: A = the checksum, zero = set if DATA_CHECKSUM matches, X = $80
;; Keeps: Y
BUFFER_CHECKSUM:
    lda #$00
    tax
    clc
BUFFER_CHECKSUM_NEXT:
    adc BUFFER,x
    inx
    bpl BUFFER_CHECKSUM_NEXT
    adc #$00
    cmp DATA_CHECKSUM
    rts

;; Takes the serial data line: makes PB0 an output, first latching the level the line has, so it doesn't glitch.
;; Uses: X
;; Keeps: A, Y
DRIVE_LINE:
    ldx RIOT_PORTB
    stx RIOT_PORTB
    ldx RIOT_DDRB
    inx
    stx RIOT_DDRB
    rts

;; Sends SEND_BYTE, then BUFFER's 128 bytes and DATA_CHECKSUM as a data frame, and lets the line go.
;; In: SEND_BYTE = the byte before the frame, DATA_CHECKSUM = the frame's checksum
;; Uses: A, X, Y
SEND_BUFFER:
    ldx #$FF
    jsr SEND_SERIAL
SEND_BUFFER_NEXT:
    ldy BUFFER,x
    sty SEND_BYTE
    jsr SEND_SERIAL_A
    bpl SEND_BUFFER_NEXT
    ldy DATA_CHECKSUM
    sty SEND_BYTE
    jsr SEND_SERIAL_A

;; Lets the serial data line go: makes PB0 an input again.
;; Uses: X
;; Keeps: A, Y
RELEASE_LINE:
    ldx RIOT_DDRB
    dex
    stx RIOT_DDRB
    rts

;; Sends SEND_BYTE on the serial data line, which DRIVE_LINE has taken: a start bit, the 8 bits from bit 0, and a stop
;; bit, 26 cycles each, for 19,200 baud.
;; Out: X incremented, negative = set if X is $80 or more
;; Uses: A, Y, SEND_BYTE
SEND_SERIAL:
    lda RIOT_PORTB

;; Sends SEND_BYTE, as SEND_SERIAL does, with port B already in A.
;; In: A = port B
;; See: <SEND_SERIAL>
SEND_SERIAL_A:
    and #<(~PB_DATA_OUT)
    sta RIOT_PORTB                      ; the start bit
    ldy #$78                            ; 8 bits
    bit BUFFER                          ; for time
SEND_SERIAL_BIT:
    bit BUFFER
    nop
    nop
    lsr a
    ror SEND_BYTE
    rol a
    sta RIOT_PORTB
    iny
    bpl SEND_SERIAL_BIT
    lsr a
    sec
    rol a
    nop
    nop
    nop
    nop
    nop
    nop
    sta RIOT_PORTB                      ; the stop bit
    inx
    rts

;; Ends a format: ends the list of bad sectors with $FFFF and sends it after Complete, or after Error if there were
;; any.
;; See: <SEND_FRAME>
FORMAT_END:
    lda #BAD_SECTORS_END
    ldx BAD_SECTOR_INDEX
    sta BUFFER,x
    inx
    sta BUFFER,x
    lda DRIVE_FLAGS
    and #FLAG_BAD_SECTORS
    bne FORMAT_END_BAD
    jmp SEND_COMPLETE_FRAME
FORMAT_END_BAD:
    lda #<(~FLAG_BAD_SECTORS)
    jsr CLEAR_FLAGS

;; Sets STATUS_FAILED, and sends Error and BUFFER as a data frame.
;; See: <SEND_ERROR_FRAME>
SEND_FAILED:
    lda #STATUS_FAILED
    jsr ADD_STATUS
    jmp SEND_ERROR_FRAME

;; Lists a sector a format's verify couldn't read, and goes on to the next, or ends the format when the list is full.
;; In: X = BAD_SECTOR_INDEX
;; See: <SECTOR_NUMBER>, <FORMAT_END>
VERIFY_BAD_SECTOR:
    lda #FLAG_BAD_SECTORS
    jsr SET_FLAGS
    jsr SECTOR_NUMBER
    inx
    stx BAD_SECTOR_INDEX
    cpx #BAD_SECTORS_FULL
    bne VERIFY_BAD_SECTOR_NEXT
    jmp FORMAT_END
VERIFY_BAD_SECTOR_NEXT:
    jmp FORMAT_VERIFY_NEXT

;; The commands from 'P' to 'W', by their low three bits; those the drive doesn't know are refused. 'O' ($4F), which
;; DISPATCH lets through, lands on 'W''s entry.
;; See: <DISPATCH>
COMMAND_TABLE:
    jmp COMMAND_PUT_SECTOR              ; 'P'
    jmp REFUSE                          ; 'Q'
    jmp COMMAND_READ_SECTOR             ; 'R'
    jmp COMMAND_STATUS_BLOCK            ; 'S'
    jmp REFUSE                          ; 'T'
    jmp REFUSE                          ; 'U'
    jmp REFUSE                          ; 'V'
    jmp COMMAND_WRITE_SECTOR            ; 'W' and 'O'

;; Put ('P') and Write ('W'): receives the data frame and acknowledges it, or refuses it for a wrong checksum, then
;; writes it to the sector in TRIES tries and, for a Write, reads it back to check it. Sends Complete, or Error if
;; the disk is write-protected or the write or its check failed.
;; See: <COMMAND_PUT_SECTOR>, <VERIFY_WRITE>
PUT_SECTOR:
    jsr ACKNOWLEDGE
    jsr MOTOR_ON
    jsr RECEIVE_DATA_FRAME
    jsr BUFFER_CHECKSUM
    bne PUT_SECTOR_BAD_DATA
    jsr SEND_ACK
    jsr SPIN_UP
    jsr POSITION
    lda RIOT_PORTA
    and #PA_WRITE_PROTECT
    bne PUT_SECTOR_PROTECTED
PUT_SECTOR_TRY:
    lda #<(~FDC_WRITE_SECTOR)
    sta FDC_COMMAND
PUT_SECTOR_FIND:
    bvs PUT_SECTOR_DONE                 ; INTRQ: the command has ended
    lda RIOT_TIMER_IRQ_ON               ; clears the index pulse
    bit RIOT_PORTA
    bmi PUT_SECTOR_BYTE                 ; DRQ: the sector is found
    jmp PUT_SECTOR_FIND
PUT_SECTOR_ENDED:
    bvs PUT_SECTOR_DONE
PUT_SECTOR_WAIT:
    bit RIOT_PORTA
    bpl PUT_SECTOR_ENDED
PUT_SECTOR_BYTE:
    inx
    lda BUFFER,x
    sta FDC_DATA
    jmp PUT_SECTOR_WAIT
PUT_SECTOR_DONE:
    jsr CHECK_RESULT
    lda #SIO_ERROR
    bcs PUT_SECTOR_FAILED
    lda DRIVE_FLAGS
    and #FLAG_VERIFY
    beq PUT_SECTOR_COMPLETE
    jsr VERIFY_WRITE
    bcc PUT_SECTOR_COMPLETE
    lda #SIO_ERROR
    bcs PUT_SECTOR_SEND
PUT_SECTOR_COMPLETE:
    lda #SIO_COMPLETE
PUT_SECTOR_RESULT:
    jmp PUT_SECTOR_SEND
PUT_SECTOR_BAD_DATA:
    lda #STATUS_BAD_DATA|STATUS_MOTOR_ON
    jsr SET_STATUS
    lda #SIO_NAK
PUT_SECTOR_SEND:
    jsr SEND_ONE
    jmp COMMAND_DONE
PUT_SECTOR_PROTECTED:
    lda #STATUS_FAILED|STATUS_WRITE_PROTECTED
    jsr ADD_STATUS
    lda #SIO_ERROR
    jmp PUT_SECTOR_SEND

;; Steps the head Y times in X's direction, waiting each step's time but the last's, then waits 10 ms for it to
;; settle.
;; In: X = the direction, as STEP takes it, Y = the steps, zero = set if there are none
;; Out: Y = 0, X incremented once a step
;; Uses: A
;; See: <STEP>
SEEK:
    beq SEEK_DONE
SEEK_STEP:
    jsr STEP
    beq SEEK_SETTLE
SEEK_WAIT:
    lda RIOT_FLAGS
    bpl SEEK_WAIT                       ; the step's time
    jmp SEEK_STEP
SEEK_SETTLE:
    lda #SETTLE_TIME
    sta RIOT_TIMER_64
SEEK_SETTLE_WAIT:
    lda RIOT_FLAGS
    bpl SEEK_SETTLE_WAIT
SEEK_DONE:
    rts

;; Write ('W'): a Put that reads the sector back to check it.
;; See: <PUT_SECTOR>
COMMAND_WRITE_SECTOR:
    lda #FLAG_VERIFY
    jsr SET_FLAGS

;; Put ('P'): writes a sector, as PUT_SECTOR describes. A sector number out of range is refused.
;; See: <PUT_SECTOR>
COMMAND_PUT_SECTOR:
    jsr CHECK_SECTOR
    bcs PUT_REFUSE
    jmp PUT_SECTOR
PUT_REFUSE:
    jmp REFUSE

PUT_SECTOR_FAILED:
    cpy #$00
    beq PUT_SECTOR_GIVE_UP
    jmp PUT_SECTOR_TRY                  ; tries left
PUT_SECTOR_GIVE_UP:
    beq PUT_SECTOR_RESULT               ; A = SIO_ERROR

;; Finds the command's sector: works out its track and sector, turns the stepper on again if it's off (the head is
;; parked on track 39), seeks the track, waits for the motor, and sets the FD1771 up for the sector.
;; Out: X = $FF, Y = TRIES
;; Uses: A
;; See: <SECTOR_POSITION>, <PREPARE>
POSITION:
    jsr SECTOR_POSITION
    lda RIOT_PORTB
    and #PB_PHASES
    bne POSITION_SEEK
    lda #TRACK39_PHASES
    sta RIOT_PORTB
POSITION_SEEK:
    lda TARGET_TRACK
    jsr SEEK_DISTANCE
    jsr SEEK

;; Waits for the motor, then sets the FD1771 up for TARGET_TRACK and TARGET_SECTOR, with TRIES tries.
;; Out: X = $FF, Y = TRIES
;; Uses: A
;; See: <MOTOR_READY>, <FDC_RESTART>
PREPARE:
    jsr MOTOR_READY
    ldy #TRIES

;; Gets the FD1771 ready for a command: ends the one in progress, waits about 2.5 ms, sets its track and sector
;; registers to TARGET_TRACK and TARGET_SECTOR, and starts the RIOT's timer for half a second, after which its
;; interrupt gives the controller the index pulses that make it give up on a sector it can't find.
;; Out: X = $FF, overflow = clear, for BIT's INTRQ
;; Uses: A
;; Keeps: Y
FDC_RESTART:
    lda #<(~FDC_FORCE_INTERRUPT)
    sta FDC_COMMAND
    ldx #$FF
FDC_RESTART_WAIT:
    dex
    bne FDC_RESTART_WAIT
    lda TARGET_TRACK
    sta FDC_TRACK
    lda TARGET_SECTOR
    sta FDC_SECTOR
    clv
    dex
    stx RIOT_TIMER_1024
    rts

;; Reads a sector for a format's verify, the head's track and TARGET_SECTOR, throwing its bytes away.
;; Uses: A, X
;; See: <FORMAT_VERIFY>
READ_TO_CHECK:
    jsr FDC_RESTART
    lda HEAD_TRACK
    sta FDC_TRACK
    lda #<(~FDC_READ_SECTOR)
    sta FDC_COMMAND
READ_TO_CHECK_WAIT:
    bvs READ_TO_CHECK_DONE              ; INTRQ: the command has ended
    lda RIOT_TIMER_IRQ_ON               ; clears the index pulse
READ_TO_CHECK_BYTE:
    bit RIOT_PORTA
    bpl READ_TO_CHECK_WAIT              ; no DRQ
    lda FDC_DATA
    jmp READ_TO_CHECK_BYTE
READ_TO_CHECK_DONE:
    rts

;; Checks a Write: reads the sector back and compares it with BUFFER, in two tries if the read itself fails. A
;; difference fails at once. Clears FLAG_VERIFY.
;;
;; It counts in Y the tries after this one, from 1, where Read and Put count this one too, and tries again while
;; CHECK_RESULT leaves Y not negative; so, like FORMAT_VERIFY, which gives each try Y = 1, it never recalibrates.
;; Out: carry = set if the check failed
;; Uses: A, X, Y
VERIFY_WRITE:
    jsr FDC_RESTART
    ldy #$01                            ; two tries
VERIFY_WRITE_TRY:
    inx
    lda #<(~FDC_READ_SECTOR)
    sta FDC_COMMAND
VERIFY_WRITE_WAIT:
    bvs VERIFY_WRITE_DONE               ; INTRQ: the command has ended
    lda RIOT_TIMER_IRQ_ON               ; clears the index pulse
VERIFY_WRITE_BYTE:
    bit RIOT_PORTA
    bpl VERIFY_WRITE_WAIT               ; no DRQ
    lda FDC_DATA
    cmp BUFFER,x
    bne VERIFY_WRITE_DIFFERENT
    inx
    bne VERIFY_WRITE_BYTE
VERIFY_WRITE_DONE:
    jsr CHECK_RESULT
    bcc VERIFY_WRITE_END
    bpl VERIFY_WRITE_TRY                ; a try left
VERIFY_WRITE_END:
    lda #<(~FLAG_VERIFY)
    jsr CLEAR_FLAGS
    rts
VERIFY_WRITE_DIFFERENT:
    jsr OPERATION_FAILED
    jmp VERIFY_WRITE_END

;; Waits 205 ms for a motor started from rest to come up to speed before the head is stepped.
;; Uses: A, Y
;; Keeps: X
SPIN_UP:
    lda DRIVE_FLAGS
    and #FLAG_MOTOR_STARTING
    beq SPIN_UP_DONE
    lda #DELAY_SPIN_UP
    jsr DELAY
SPIN_UP_DONE:
    rts

    .res $0FFA-*, $00

; The 6507's vectors. It has no interrupts, so only a BRK would take the last.

    .word $0000                         ; NMI, unused
    .word RESET                         ; reset
    .word RESET                         ; IRQ and BRK
