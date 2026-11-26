; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE TAPE ($F7AF-$FD21)
;
; How the kernal records on the Datasette. The tape holds a square wave: the write line (VIA 2's PB3) is toggled at
; the end of each half of a pulse, and the read line (VIA 2's CA1) interrupts once a pulse, at its falling edge. A
; pulse, one cycle of the wave, is short, long or a marker (longer still). A bit is two pulses, its dipole: a 0 is a
; short then a long, a 1 a long then a short. A byte is a marker followed by a long, its eight bits from bit 0, and a
; parity bit that makes the number of 1s odd. A block is a leader of short pulses, nine countdown bytes ($89 down to
; $81 in the first copy, $09 to $01 in the second), the data, a checksum byte (the exclusive or of the data), one more
; marker to end it and a trailer of 80 short pulses. Every block is written twice, the second copy straight after the
; first's trailer, so a byte the first copy got wrong can be taken from the second.
;
; A file is a header block, the tape buffer with the file's type, addresses and name, then the data: a program's
; memory as one block, or a data file's buffers, one block each.

.scope Tape continued

; The header's layout in the tape buffer.

;; Where a header's file name starts in the tape buffer: after its type (byte 0) and its start and end addresses
;; (bytes 1 to 4).
HEADER_NAME = 5

;; How many characters of a header's name FOUND prints: the name a file was saved with can be longer, padded with
;; spaces to the buffer's end.
FOUND_NAME_LENGTH = 16

; Writing: the leaders and the pulses' lengths.

;; A header's leader, in <ShortCountHigh>'s counts: 106 times about 256 short pulses, to bring the tape up to speed
;; before a file.
HEADER_LEADER = $69

;; A data block's leader, in <ShortCountHigh>'s counts: 21 times about 256 short pulses.
DATA_LEADER = 20

;; The short pulses after each copy of a block, its trailer; the second copy's countdown follows straight on.
TRAILER_LENGTH = 80

;; How many countdown bytes come before a block's data, 9 down to 1.
COUNTDOWN_LENGTH = 9

;; Every block is written twice; <BlockCount> counts the copies down from this.
BLOCK_COPIES = 2

;; The bit set in the first copy's countdown bytes and clear in the second's, so that a reader can tell them apart.
FIRST_COPY = $80

;; Half a short pulse: timer 2's count, to which the interrupt's own time adds.
SHORT_HALF = 96

;; Half a long pulse: timer 2's count.
LONG_HALF = 176

;; Half a marker pulse, the longest: timer 2's count.
MARKER_HALF = 256 + 16

;; Half a leader's short pulse: timer 2's count. It is larger than <SHORT_HALF>, presumably because <WriteLeader>
;; runs fewer instructions before it sets the timer than <WriteData> does, so the two come out about the same length.
LEADER_HALF = 120

; Reading: the pulses' lengths, in units of 4 cycles, and the timeouts.

;; A pulse no longer than this (plus <TimeCorrection>) is noise, and is not counted.
NOISE_LIMIT = 60

;; From the noise limit to the longest short pulse; each limit adds <TimeCorrection> once more.
SHORT_STEP = 48

;; From the longest short pulse to the longest long one.
LONG_STEP = 38

;; From the longest long pulse to the longest marker; a pulse longer still is an error.
MARKER_STEP = 44

;; How far below its limit a short or a long pulse's ideal length is: <TimingAdjust> adds up each pulse's distance
;; from its ideal.
IDEAL_MARGIN = 19

;; The short pulses (more than long ones) since the last byte that make block sync: a leader.
SYNC_SHORTS = 16

;; Timer 1's time after a data bit's last edge, for <SetTimeout>: a little longer than the next bit takes.
BIT_TIMEOUT = 218

;; Timer 1's time after the parity bit's last edge, for <SetTimeout>.
PARITY_TIMEOUT = 166

;; The base of timer 1's time after a marker, for <SetTimeout>: the marker's own length is taken off it.
MARKER_TIMEOUT = 147

;; <FirstPassErrors> must be at most this for another bad byte's address to be logged: 31 addresses of two bytes,
;; <BadBytes> to $013D.
BAD_BYTES_LIMIT = 61

;; <SetTimeout> reads timer 2 only once its low byte is at least this, so that the high byte it reads next goes with it.
TIMER_ROLLOVER_MARGIN = 21

;; Timer 2 is started again from $FFFF at each edge, so the count it has gone down by is the pulse's length.
PULSE_TIMER_START = $FF

;; <ReadMode>'s bit 7: passing over bytes until the next leader.
READ_IGNORE = $80

;; <ReadMode>'s bit 6: storing (or verifying) the block's data.
READ_LOADING = $40

;; A countdown byte's count, 9 to 1, in its low bits; <ReadMode> counts the rest of the countdown in the same bits.
COUNTDOWN_COUNT = $0F

; The interrupt handlers, numbered for <SetIrqVector> as their places in <InterruptHandlers>, from 8.

;; <WriteLeader>, the leader's and trailer's handler.
LEADER_HANDLER = 8

;; <WriteData>, the data's handler.
DATA_HANDLER = 10

;; <ReadInterrupt>, the read's handler.
READ_HANDLER = 14

; The VIAs.

;; Timer 2's interrupt bit: while writing, the end of each half pulse.
TIMER2_INTERRUPT = %00100000

;; VIA 2's PB3, the cassette's write line.
WRITE_LINE = %00001000

;; VIA 1's PA6, the cassette's sense line: low while one of the Datasette's keys is down.
CASSETTE_SENSE = %01000000

;; VIA 1's peripheral control bits that make CA2 an output held low, which runs the cassette motor.
MOTOR_OUTPUT = %00001100

;; The bit that, with <MOTOR_OUTPUT>, holds CA2 high instead, which stops the motor.
MOTOR_STOP = %00000010

;; <Run>'s delay for the motor's start: this many passes of this many loops, about a third of a second.
MOTOR_DELAY = $FF

; The tape's names for shared bytes.

;; Reading: the bit's first pulse, 0 for a short and 1 for a long, to compare with the second; the screen editor's
;; <Editor::Character>.
FirstPulse = Editor::Character

;; Writing: the exclusive or of the block's bytes so far, written after them as the checksum; the screen editor's
;; <Editor::Character>.
WriteChecksum = Editor::Character

;; Reading: the pulse's length, in units of 4 cycles, while <ReadInterrupt> classifies it (<Temporary>).
PulseLength = Temporary

;; Reads blocks until a header: a program's, a fixed program's or a data file's, or the end of the tape. With messages
;; on, prints FOUND and the first 16 characters of the header's name.
;;
;; Every block is read as a load, whatever <VerifyFlag> says, and <VerifyFlag> is put back after each. Data blocks,
;; and blocks of any other type, are passed over.
;; In: TapeBuffer = the tape buffer
;; Out: carry = clear, X = the header's type (<TAPE_PROGRAM>, <TAPE_PROGRAM_FIXED> or <TAPE_DATA_HEADER>), the header in
;;   the tape buffer
;; Errors: carry = set at the end of the tape (A = <TAPE_END_OF_TAPE>) or for STOP (A = <VerifyFlag>, 0 or 1)
;; Keeps: VerifyFlag
;; Also: FAH (KV20, MTV)
.proc FindHeader
    ; The next block, as a load: a header is never verified.
    lda VerifyFlag
    pha
    jsr ReadHeader
    pla
    sta VerifyFlag
    bcs Done

    ; Its first byte is its type.
    ldy #0
    lda (TapeBuffer),y
    cmp #TAPE_END_OF_TAPE
    beq Done                        ; carry set by the equal compare
    cmp #TAPE_PROGRAM
    beq Found
    cmp #TAPE_PROGRAM_FIXED
    beq Found
    cmp #TAPE_DATA_HEADER
    bne FindHeader

;; A header: X = its type; FOUND and its name, when <MessageMode> lets the control messages through.
;; Also: FAH50 (KV20)
Found:
    tax
    bit MessageMode
    bpl Success
    ldy #Channels::FoundMessage-Channels::Messages
    jsr Channels::PrintControlMessage::Always
    ldy #HEADER_NAME

;; Prints the header's first 16 characters of name.
;; Also: FAH55 (KV20)
PrintName:
    lda (TapeBuffer),y
    jsr KernalCharacterOut
    iny
    cpy #HEADER_NAME + FOUND_NAME_LENGTH
    bne PrintName

;; Returns carry clear, for a header.
;; Also: FAH45 (KV20)
Success:
    clc
    dey

;; Returns.
;; Also: FAH40 (KV20)
Done:
    rts
.endproc

;; Writes a header of type A: the tape buffer filled with the type, the start and end addresses and the file name,
;; padded with spaces, written as a block with a long leader. <Tape::LoadAddress> and <EndAddress> are the file's
;; addresses on entry and again on return; the block is written from the buffer meanwhile.
;;
;; When <TapeBuffer> no longer points at a buffer (<BufferAddress>), nothing is written, and carry comes back clear.
;; In: A = the header's type, Tape::LoadAddress = the file's start, EndAddress = its end, FileName = the name,
;;   FileNameLength = its length, TapeBuffer = the tape buffer
;; Out: carry = clear, A = 0
;; Errors: carry = set if STOP was pressed (A = 0)
;; Keeps: Tape::LoadAddress, Tape::LoadAddressHigh, EndAddress, EndAddressHigh
;; Also: TAPEH (KV20, MTV)
.proc WriteHeader
    sta Temporary1
    jsr BufferAddress
    bcc Done

    ; The file's addresses are kept on the stack while the buffer's are in their place.
    lda LoadAddressHigh
    pha
    lda LoadAddress
    pha
    lda EndAddressHigh
    pha
    lda EndAddress
    pha
    ldy #TAPE_BUFFER_SIZE-1
    lda #' '

;; Fills the buffer with spaces, from its end down to byte 1.
;; Also: BLNK2 (KV20)
Blank:
    sta (TapeBuffer),y
    dey
    bne Blank

    ; The type, then the start and end addresses.
    lda Temporary1
    sta (TapeBuffer),y
    iny
    lda LoadAddress
    sta (TapeBuffer),y
    iny
    lda LoadAddressHigh
    sta (TapeBuffer),y
    iny
    lda EndAddress
    sta (TapeBuffer),y
    iny
    lda EndAddressHigh
    sta (TapeBuffer),y
    iny
    sty Temporary2
    ldy #0
    sty Temporary1

;; Copies the file name after the addresses: <Temporary1> indexes the name, <Temporary2> the buffer.
;; Also: TH20 (KV20)
CopyName:
    ldy Temporary1
    cpy FileNameLength
    beq Write
    lda (FileName),y
    ldy Temporary2
    sta (TapeBuffer),y
    inc Temporary1
    inc Temporary2
    bne CopyName

;; Writes the buffer as a block, with the header's long leader, then puts the file's addresses back.
;; Also: TH30 (KV20)
Write:
    jsr BufferBounds
    lda #HEADER_LEADER
    sta ShortCountHigh
    jsr WriteBlock::WithLeader
    tay
    pla
    sta EndAddress
    pla
    sta EndAddressHigh
    pla
    sta LoadAddress
    pla
    sta LoadAddressHigh
    tya

;; Returns.
;; Also: TH40 (KV20)
Done:
    rts
.endproc

;; Loads the tape buffer's address, and checks that there is one: a <TapeBuffer> whose high byte is 0 or 1 (in zero
;; page or the stack) means a program has taken the buffer away, and the tape routines then do nothing.
;; In: TapeBuffer = the tape buffer
;; Out: X = its low byte, Y = its high byte, carry = clear if the buffer has been taken away
;; Keeps: A
;; Also: ZZZ (KV20)
.proc BufferAddress
    ldx TapeBuffer
    ldy TapeBuffer+1
    cpy #>InputBuffer
    rts
.endproc

;; Sets <Tape::LoadAddress> and <EndAddress> to the tape buffer's start and its end (plus one), to read or write the
;; buffer as a block.
;; In: TapeBuffer = the tape buffer
;; Out: Tape::LoadAddress = the buffer's start, EndAddress = its end, X = its low byte, Y = its high byte
;; Also: LDAD1 (KV20, MTV)
.proc BufferBounds
    jsr BufferAddress
    txa
    sta LoadAddress
    clc
    adc #TAPE_BUFFER_SIZE
    sta EndAddress
    tya
    sta LoadAddressHigh
    adc #0
    sta EndAddressHigh
    rts
.endproc

;; Reads headers until one whose name starts with the current file name: the name's characters are compared with the
;; header's first ones, so a name of no length matches the first header found.
;; In: FileName = the name, FileNameLength = its length
;; Out: carry = clear, X = the header's type, the header in the tape buffer
;; Errors: carry = set as <FindHeader> reports it: at the end of the tape or for STOP
;; Keeps: VerifyFlag
;; Also: FAF (KV20)
.proc FindFile
    jsr FindHeader
    bcs Done
    ldy #HEADER_NAME
    sty Temporary2
    ldy #0
    sty Temporary1

;; Compares each character of the name: <Temporary1> indexes the name, <Temporary2> the header.
;; Also: FAF20 (KV20)
Compare:
    cpy FileNameLength
    beq Found
    lda (FileName),y
    ldy Temporary2
    cmp (TapeBuffer),y
    bne FindFile
    inc Temporary1
    inc Temporary2
    ldy Temporary1
    bne Compare

;; Returns carry clear, for the file.
;; Also: FAF30 (KV20)
Found:
    clc

;; Returns.
;; Also: FAF40 (KV20)
Done:
    rts
.endproc

;; Moves <BufferIndex> to the next byte of the tape buffer, for the channel routines' reads and writes.
;; In: BufferIndex = the byte last used
;; Out: Y = the new index, carry = set when it has reached the buffer's end, X = <TapeBuffer>'s low byte
;; Keeps: A
;; Also: JTP20 (KV20, MTV)
.proc NextBufferByte
    jsr BufferAddress
    inc BufferIndex
    ldy BufferIndex
    cpy #TAPE_BUFFER_SIZE
    rts
.endproc

;; Waits for the Datasette's PLAY: prints PRESS PLAY ON TAPE (whatever <MessageMode> says) and waits until a key is
;; down, then prints OK. Returns at once, printing nothing, when a key is already down.
;;
;; The cassette's sense line cannot tell PLAY from the other keys, so any key that closes it ends the wait.
;; Out: carry = clear
;; Errors: carry = set if STOP was pressed (A = 0, the channels reset by <KernalTestStopKey>)
;; Entry:
;;   Prompt = prints message Y (<WaitForRecord>'s) instead, and waits the same way
;; Also: CSTE1 (KV20)
.proc WaitForPlay
    jsr KeysDown
    beq KeysDown::Done
    ldy #Channels::PressPlayMessage-Channels::Messages

;; Prints message Y, and waits; <WaitForRecord> enters here with its own.
;; Also: CS30 (KV20)
Prompt:
    jsr Channels::PrintControlMessage::Always

;; Watches STOP and the cassette's keys; then OK.
;; Also: CS40 (KV20)
Wait:
    jsr CheckStop
    jsr KeysDown
    bne Wait
    ldy #Channels::OkMessage-Channels::Messages
    jmp Channels::PrintControlMessage::Always
.endproc

;; Checks the Datasette's keys: the cassette's sense line, VIA 1's PA6, is low while one is down. It reads the line a
;; second time before it decides, so a key must still be down.
;; Out: zero = set while a key is down, carry = clear, A = <CASSETTE_SENSE>
;; Keeps: X, Y
;; Entry:
;;   Done = returns carry clear (the prompts return through it when a key is already down)
;; Also: CS10 (KV20, MTV)
.proc KeysDown
    lda #CASSETTE_SENSE
    bit Via1PortA
    bne Done
    bit Via1PortA

;; Returns carry clear (the prompts return through it when a key is already down).
;; Also: CS25 (KV20)
Done:
    clc
    rts
.endproc

;; Waits for the Datasette's RECORD and PLAY, as <WaitForPlay> does for PLAY: prints PRESS RECORD & PLAY ON TAPE and
;; waits until a key is down. The sense line cannot tell whether RECORD is down too.
;; Out: carry = clear
;; Errors: carry = set if STOP was pressed (A = 0)
;; Also: CSTE2 (KV20)
.proc WaitForRecord
    jsr KeysDown
    beq KeysDown::Done
    ldy #Channels::PressRecordMessage-Channels::Messages
    bne WaitForPlay::Prompt         ; always: the message's offset is not 0
.endproc

;; Reads a block into the tape buffer, as a load: clears <IoStatus> and <VerifyFlag>, sets the buffer's bounds and
;; falls into <ReadBlock>.
;; In: TapeBuffer = the tape buffer
;; Out: carry = clear, A = 0, the block in the tape buffer, IoStatus = the read's errors
;; Errors: carry = set if STOP was pressed (A = 0), IoStatus = the block's errors, as <ReadBlock> reports them
;; Also: RBLK (KV20, MTV)
.proc ReadHeader
    lda #0
    sta IoStatus
    sta VerifyFlag
    jsr BufferBounds
.endproc

;; Reads a block to <Tape::LoadAddress> up to <EndAddress>, or verifies memory against it: asks for PLAY, then runs
;; <ReadInterrupt> until both copies are read, or the second is not needed.
;; In: Tape::LoadAddress = where the block goes, EndAddress = its end, VerifyFlag = 1 to verify
;; Out: carry = clear, A = 0, IoStatus = the read's errors
;; Errors: carry = set if STOP was pressed (A = 0), IoStatus = <STATUS_SHORT_BLOCK>, <STATUS_LONG_BLOCK>,
;;   <STATUS_SECOND_PASS_ERROR> or <STATUS_CHECKSUM_ERROR>
;; Also: TRD (KV20)
.proc ReadBlock
    jsr WaitForPlay
    bcs WriteBlock::Begin

    ; Nothing found yet: waiting for a countdown, no sync, no errors logged.
    sei
    lda #0
    sta ReadMode
    sta SyncFound
    sta TimeCorrection
    sta FirstPassErrors
    sta SecondPassErrors
    sta ByteMarkerSeen

    ; CA1's edges, through the read's handler.
    lda #VIA_INTERRUPTS_ON | VIA_INTERRUPT_CA1
    ldx #READ_HANDLER
    bne Run                         ; always
.endproc

;; Writes the tape buffer as a block: sets its bounds and falls into <WriteBlock>.
;; In: TapeBuffer = the tape buffer
;; Out: carry = clear, A = 0
;; Errors: carry = set if STOP was pressed (A = 0)
;; Also: WBLK (KV20, MTV)
.proc WriteBuffer
    jsr BufferBounds
.endproc

;; Writes <Tape::LoadAddress> up to <EndAddress> as a block, twice, with a data block's leader: asks for RECORD and
;; PLAY first.
;; In: Tape::LoadAddress = the block's start, EndAddress = its end (plus one)
;; Out: carry = clear, A = 0
;; Errors: carry = set if STOP was pressed (A = 0)
;; Entry:
;;   WithLeader = with the leader the caller has put in <ShortCountHigh> (<WriteHeader>'s is longer)
;;   Begin = with carry set, returns (<ReadBlock> comes here when STOP ended its prompt); clear, starts writing
;; Also: TWRT (KV20)
.proc WriteBlock
    lda #DATA_LEADER
    sta ShortCountHigh

;; With the leader the caller has put in <ShortCountHigh> (<WriteHeader>'s is longer).
;; Also: TWRT2 (KV20)
WithLeader:
    jsr WaitForRecord

;; With carry set (STOP at the prompt), returns; <ReadBlock> comes here for that too. Otherwise starts writing:
;; timer 2's interrupts, through the leader's handler.
;; Also: TWRT3 (KV20)
Begin:
    bcs CheckStop::ReleaseIrq
    sei
    lda #VIA_INTERRUPTS_ON | TIMER2_INTERRUPT
    ldx #LEADER_HANDLER
.endproc

;; Runs a tape operation: takes the IRQ over (keeping the vector in <SavedIrq>), turns the motor on, and waits until
;; the handler has finished and put the vector back (<Finish>), or STOP is pressed.
;;
;; While it waits, VIA 2's timer 1 flag ticks the jiffy clock. It clears the flag by reading VIA 1's timer 1
;; (<Via1Timer1>), not VIA 2's that it tested, so the clock may be ticked on every pass while VIA 2's flag stays set,
;; as it can while writing. It compares only the vector's high byte, which the tape's handlers ($F98E-$FCA8) never
;; share with the kernal's IRQ, $EABF.
;; In: A = the VIA 2 interrupts to turn on, X = the handler (<READ_HANDLER> or <LEADER_HANDLER>),
;;   interrupt = set (masked)
;; Out: carry = clear, A = 0
;; Errors: carry = set if STOP was pressed (A = 0)
;; Also: TAPE (KV20, MTV)
.proc Run
    ; VIA 2's interrupts off, the jiffy's too, then the operation's on.
    ldy #VIA_INTERRUPTS_ALL
    sty Via2InterruptEnable
    sta Via2InterruptEnable
    jsr Rs232::Pause

    ; The IRQ vector kept, and pointed at the handler.
    lda IrqVector
    sta SavedIrq
    lda IrqVector+1
    sta SavedIrq+1
    jsr SetIrqVector

    ; Two copies, a new byte.
    lda #BLOCK_COPIES
    sta BlockCount
    jsr NewByte

    ; The motor on: CA2 low, and CassetteMotorMode set so that the jiffy IRQ leaves it alone.
    lda Via1PeripheralControl
    and #<(~MOTOR_STOP)
    ora #MOTOR_OUTPUT
    sta Via1PeripheralControl
    sta CassetteMotorMode
    ldx #MOTOR_DELAY

;; A delay while the motor comes up to speed.
;; Also: TP32 (KV20)
Delay:
    ldy #MOTOR_DELAY

;; The delay's inner loop.
;; Also: TP35 (KV20)
DelayInner:
    dey
    bne DelayInner
    dex
    bne Delay

    ; Timer 2 started (with whatever A holds as its high byte): writing, its first interrupt begins the leader.
    sta Via2Timer2High
    cli

;; Waits until the IRQ vector is back, watching STOP and keeping the jiffy clock.
;; Also: TP40 (KV20)
WaitDone:
    lda SavedIrq+1
    cmp IrqVector+1
    clc
    beq CheckStop::ReleaseIrq
    jsr CheckStop
    lda Via2InterruptFlags
    and #VIA_INTERRUPT_TIMER1
    beq WaitDone
    lda Via1Timer1
    jsr Clock::Tick
    jmp WaitDone
.endproc

;; Stops the tape if STOP is down: <Finish>es the operation and returns from the routine that called this one, to its
;; caller, with carry set. Otherwise returns at once with carry clear.
;;
;; The STOP test (<KernalTestStopKey>) also resets the channels and empties the keyboard buffer when STOP is down.
;; Out: carry = clear, A = <StopKeyRow>, when STOP is not down
;; Errors: carry = set, A = 0, when STOP stopped the tape: the return skips the caller
;; Entry:
;;   ReleaseIrq = marks <SavedIrq> as holding no vector (its high byte 0), A = 0, carry as it was (<Run> and
;;     <WriteBlock> return through it)
;; Also: TSTOP (KV20, MTV)
.proc CheckStop
    jsr KernalTestStopKey
    clc
    bne Done
    jsr Finish
    sec

    ; The caller's return address dropped, so the rts goes to its caller.
    pla
    pla

;; Marks <SavedIrq> as holding no vector (its high byte 0); A = 0, carry as it was. <Run> and <WriteBlock> return
;; through it.
;; Also: STOP3 (KV20)
ReleaseIrq:
    lda #0
    sta SavedIrq+1

;; Returns.
;; Also: STOP4 (KV20)
Done:
    rts
.endproc

;; Sets VIA 2's timer 1 to run out when the next bit (or the marker's end) is overdue: (X + 5 times
;; <TimeCorrection>) times 4 cycles after <ReadInterrupt> started timer 2 again, just after the edge. It works from
;; timer 2's count: timer 2 started from $FFFF, so its count plus the time is the time left.
;;
;; It ends with interrupts on, so the rest of the handler that called it can itself be interrupted.
;; In: X = the time, in units of 4 cycles, TimeCorrection = the correction for the tape's speed (signed)
;; Out: interrupt = clear (enabled)
;; Keeps: Y
;; Also: STT1 (KV20, MTV)
.proc SetTimeout
    ; X plus 5 times the correction.
    stx Temporary
    lda TimeCorrection
    asl a
    asl a
    clc
    adc TimeCorrection
    clc
    adc Temporary
    sta Temporary
    lda #0
    bit TimeCorrection
    bmi Scale
    rol a

;; Times four: A and <Temporary> are the time in cycles, high and low.
;; Also: STT2 (KV20)
Scale:
    asl Temporary
    rol a
    asl Temporary
    rol a
    tax

;; Waits while timer 2's low byte is about to roll over, so that its high byte read next goes with it; then timer 1 =
;; timer 2's count plus the time.
;; Also: STT3 (KV20)
WaitTimer:
    lda Via2Timer2
    cmp #TIMER_ROLLOVER_MARGIN
    bcc WaitTimer
    adc Temporary
    sta Via2Timer1
    txa
    adc Via2Timer2High
    sta Via2Timer1High
    cli
    rts
.endproc

;; The IRQ handler while reading: times each pulse on VIA 2's timer 2, classifies it as noise, a short, a long or a
;; marker, pairs the pulses into bits and the bits into bytes, and hands each byte to the byte handler (from
;; <HandleByte at ReadInterrupt::HandleByte>), which follows the block's countdown, stores or verifies its data, and
;; checks it.
;;
;; The first byte of a block (the countdown) is found by block sync, <SYNC_SHORTS> short pulses from a leader, then
;; byte sync, the first marker after it. The first copy's bad bytes are logged in <BadBytes>, and only they are taken
;; from the second copy. Errors go to <IoStatus>. When the block is done, <Finish> puts the IRQ vector back, which ends
;; <Run>'s wait.
;;
;; It runs from the kernal's IRQ entry, which has pushed A, X and Y, while <IrqVector> points here, and
;; <Interrupts::NmiHandler::Return> ends it, pulling them back. Its low byte's subtraction from timer 2 uses whatever
;; carry the interrupted code left, so a length can be one count off.
;; Also: READ (KV20, MTV)
.proc ReadInterrupt
    ; The time since the last edge: timer 2's count from $FFFF, read until its high byte holds still.
    ldx Via2Timer2High
    ldy #PULSE_TIMER_START
    tya
    sbc Via2Timer2
    cpx Via2Timer2High
    bne ReadInterrupt
    stx Temporary
    tax

    ; Timer 2 started again for the next pulse; the length's high byte worked out.
    sty Via2Timer2
    sty Via2Timer2High
    tya
    sbc Temporary

    ; The length in units of 4 cycles, in PulseLength (bits above the low byte are dropped).
    stx PulseLength
    lsr a
    ror PulseLength
    lsr a
    ror PulseLength

    ; Noise is passed over; reading port A with its handshake clears CA1's interrupt.
    lda TimeCorrection
    clc
    adc #NOISE_LIMIT
    bit Via2PortAHandshake
    cmp PulseLength
    bcs CheckTimer
    ldx ByteMarkerSeen
    beq ClassifyPulse
    jmp FinishByte

;; Classifies the pulse by its length: a short (X = 0), a long (X = 1), or a marker, against limits that each add
;; <TimeCorrection> once more. After the parity bit, any pulse is taken as a marker.
;; Also: RJDJ (KV20)
ClassifyPulse:
    ldx BitCount
    bmi ToLongLong
    ldx #0
    adc #SHORT_STEP
    adc TimeCorrection
    cmp PulseLength
    bcs Short
    inx
    adc #LONG_STEP
    adc TimeCorrection
    cmp PulseLength
    bcs One
    adc #MARKER_STEP
    adc TimeCorrection
    cmp PulseLength
    bcc SetError

;; On to <LongLong>, out of a branch's reach.
;; Also: JRAD2 (KV20)
ToLongLong:
    jmp LongLong

;; A pulse longer than a marker: once byte sync is found, the byte's <ReadError> is set.
;; Also: SRER (KV20)
SetError:
    lda SyncFound
    beq CheckTimer
    sta ReadError
    bne CheckTimer                  ; always

;; A short pulse: <ZeroesCount> up.
;; Also: RADX2 (KV20)
Short:
    inc ZeroesCount
    bcs Servo                       ; always: the compare set carry

;; A long pulse: <ZeroesCount> down.
;; Also: RADL (KV20)
One:
    dec ZeroesCount

;; Adds the pulse's distance from its ideal (its limit less <IDEAL_MARGIN>) to <TimingAdjust>, and moves to the
;; dipole's other pulse. After the first, keeps its kind in <FirstPulse>.
;; Also: RAD5 (KV20)
Servo:
    sec
    sbc #IDEAL_MARGIN
    sbc PulseLength
    adc TimingAdjust
    sta TimingAdjust
    lda Dipole
    eor #1
    sta Dipole
    beq SecondHalf
    stx FirstPulse

;; Once byte sync is found, checks whether timer 1 has run out, the bit's time up. Then the bit ends with what came, X
;; as its second pulse (a pulse out of range has set <ReadError>); after the parity bit, on to <LongLong>, for the
;; marker.
;; Also: RDBK (KV20)
CheckTimer:
    lda SyncFound
    beq Return
    bit Via2InterruptFlags
    bvc Return
    lda #0
    sta Dipole
    lda BitCount
    bpl DataBit
    bmi ToLongLong                  ; always

;; After the parity bit: timer 1 set for the marker, and the parity, over the nine bits' second pulses, must come to
;; 0, or the byte's <ReadError> is set.
;; Also: RADP (KV20)
CheckParity:
    ldx #PARITY_TIMEOUT
    jsr SetTimeout
    lda Parity
    bne SetError

;; Returns from the interrupt.
;; Also: RADBK (KV20)
Return:
    jmp Interrupts::NmiHandler::Return

;; The dipole's second pulse: moves <TimeCorrection> one step by <TimingAdjust>'s sign, down for pulses that came
;; short, up for long ones.
;; Also: RAD3 (KV20)
SecondHalf:
    lda TimingAdjust
    beq CompareHalves
    bmi Slower
    dec TimeCorrection
    .byte $2C                       ; bit absolute: skips the inc

;; The pulses came long: each limit later.
;; Also: ROUT2 (KV20)
Slower:
    inc TimeCorrection

;; Compares the dipole's two pulses. Unlike, they are a data bit. Two longs are an error; two shorts are a leader, and
;; <SYNC_SHORTS> of them more than longs set <BlockSync>.
;; Also: ROUT1 (KV20)
CompareHalves:
    lda #0
    sta TimingAdjust
    cpx FirstPulse
    bne DataBit
    txa
    bne SetError
    lda ZeroesCount
    bmi CheckTimer
    cmp #SYNC_SHORTS
    bcc CheckTimer
    sta BlockSync
    bcs CheckTimer                  ; always

;; A data bit: the second pulse added to the parity; once byte sync is found, the first pulse's kind (the bit's value)
;; shifted into <ByteBuffer>, and timer 1 set for the next bit. The ninth is the parity bit.
;; Also: RAD4 (KV20)
DataBit:
    txa
    eor Parity
    sta Parity
    lda SyncFound
    beq Return
    dec BitCount
    bmi CheckParity
    lsr FirstPulse
    ror ByteBuffer
    ldx #BIT_TIMEOUT
    jsr SetTimeout
    jmp Interrupts::NmiHandler::Return

;; A marker-length pulse: with block sync but not yet byte sync, the marker that starts the block; otherwise see
;; <EndOfByte>.
;; Also: RAD2 (KV20)
LongLong:
    lda BlockSync
    beq EndOfByte
    lda SyncFound
    beq ByteMarker

;; Within a byte's bits, a marker-length pulse is taken as a long; after the parity bit, it is the next byte's marker.
;; (On the way to <One>, A holds <BitCount>, not a limit, so <Servo> adds a wrong distance to <TimingAdjust>.)
;; Also: RAD2Y (KV20)
EndOfByte:
    lda BitCount
    bpl One

;; A marker: timer 1 set from its length, and the next edge (the marker's long) finishes the byte. The first marker
;; after a leader is byte sync: timer 1's interrupt goes on, and the nothing read before it is marked bad.
;; Also: RAD2X (KV20)
ByteMarker:
    lsr PulseLength
    lda #MARKER_TIMEOUT
    sec
    sbc PulseLength
    adc TimeCorrection
    asl a
    tax
    jsr SetTimeout
    inc ByteMarkerSeen
    lda SyncFound
    bne PassByte
    lda BlockSync
    beq ReturnFromMarker
    sta ReadError
    lda #0
    sta BlockSync
    lda #VIA_INTERRUPTS_ON | VIA_INTERRUPT_TIMER1
    sta Via2InterruptEnable
    sta SyncFound

;; Keeps <BlockSync> in <BlockSyncSaved> for the byte handler. Block sync while synchronized is the next leader, the
;; block's end: byte sync is dropped, and timer 1's interrupt goes off.
;; Also: RADQ2 (KV20)
PassByte:
    lda BlockSync
    sta BlockSyncSaved
    beq HandBack
    lda #0
    sta SyncFound
    lda #VIA_INTERRUPT_TIMER1
    sta Via2InterruptEnable

;; Hands the byte just read on: <OutputCharacter> = it, <ByteErrors> = its errors and short pulses counted.
;; Also: RADK (KV20)
HandBack:
    lda ByteBuffer
    sta OutputCharacter
    lda ReadError
    ora ZeroesCount
    sta ByteErrors

;; Returns; the byte is handled at the marker's next edge.
;; Also: RDBK2 (KV20)
ReturnFromMarker:
    jmp Interrupts::NmiHandler::Return

;; The edge after a marker: a new byte begins, timer 1 is set for its first bit, and the byte handed on is handled.
;; While copies are left, <CopiesLeft> follows <BlockCount>.
;; Also: RADJ (KV20)
FinishByte:
    jsr NewByte
    sta ByteMarkerSeen
    ldx #BIT_TIMEOUT
    jsr SetTimeout
    lda BlockCount
    beq HandleByte
    sta CopiesLeft

;; The byte handler, by <ReadMode>: passing over bytes until a leader (<READ_IGNORE>), loading (<READ_LOADING>),
;; counting the countdown down (a count), or waiting for the countdown (0).
;;
;; Passing over: a leader means a countdown comes next. Without one, after the first copy (<BlockCount> 1), the bytes
;; go on past the block's end: <STATUS_LONG_BLOCK>.
;; Also: RD15 (KV20)
HandleByte:
    lda #COUNTDOWN_COUNT
    bit ReadMode
    bpl Mode
    lda BlockSyncSaved
    bne WaitForSync
    ldx BlockCount
    dex
    bne Exit
    lda #STATUS_LONG_BLOCK
    jsr Channels::ReadStatus::SetStatus
    bne Exit                        ; always: the status is not 0

;; A leader: waits for the countdown.
;; Also: RD12 (KV20)
WaitForSync:
    lda #0
    sta ReadMode

;; Returns from the interrupt.
;; Also: RD10 (KV20)
Exit:
    jmp Interrupts::NmiHandler::Return

;; Not passing over: loading, counting down, or waiting for the countdown. A good byte while waiting is the
;; countdown's first; its bit 7 says which copy it is, against <CopiesLeft> (even for the first copy, odd for the
;; second).
;; Also: RD20 (KV20)
Mode:
    bvs Loading
    bne Countdown
    lda BlockSyncSaved
    bne Exit
    lda ByteErrors
    bne Exit
    lda CopiesLeft
    lsr a
    lda OutputCharacter
    bmi CheckBlock
    bcc IgnoreBytes
    clc

;; Carry set here is the wrong copy, passed over; the right one's count goes into <ReadMode>.
;; Also: RD22 (KV20)
CheckBlock:
    bcs IgnoreBytes
    and #COUNTDOWN_COUNT
    sta ReadMode

;; Counts the countdown down (its later bytes are not checked); at its end, loading begins, at <Tape::LoadAddress>.
;; Also: RD200 (KV20)
Countdown:
    dec ReadMode
    bne Exit
    lda #READ_LOADING
    sta ReadMode
    jsr ResetAddress
    lda #0
    sta LoadChecksum
    beq Exit                        ; always

;; Not the copy wanted: passes over bytes until the next leader.
;; Also: RD40 (KV20)
IgnoreBytes:
    lda #READ_IGNORE
    sta ReadMode
    bne Exit                        ; always

;; While loading, a leader in the data means the block ended early, <STATUS_SHORT_BLOCK>, and the next countdown is
;; waited for.
;; Also: RD60 (KV20)
Loading:
    lda BlockSyncSaved
    beq CheckEnd
    lda #STATUS_SHORT_BLOCK
    jsr Channels::ReadStatus::SetStatus
    lda #0
    jmp SetMode

;; At <EndAddress>, the block is done (the byte is its checksum). Otherwise, on the first copy, a verify that finds
;; memory different marks the byte bad.
;; Also: RD70 (KV20)
CheckEnd:
    jsr CompareAddresses
    bcc BeforeEnd
    jmp BlockEnd
BeforeEnd:
    ldx CopiesLeft
    dex
    beq SecondPass
    lda VerifyFlag
    beq LogError
    ldy #0
    lda OutputCharacter
    cmp (StartAddress),y
    beq LogError
    lda #1
    sta ByteErrors

;; The first copy: a bad byte's address is logged in <BadBytes>, while the log has room (<BAD_BYTES_LIMIT>); a bad
;; byte past it is <STATUS_SECOND_PASS_ERROR> at once. The byte is stored either way.
;; Also: RD80 (KV20)
LogError:
    lda ByteErrors
    beq StoreByte
    ldx #BAD_BYTES_LIMIT
    cpx FirstPassErrors
    bcc SecondPassError
    ldx FirstPassErrors
    lda StartAddressHigh
    sta BadBytes+1,x
    lda StartAddress
    sta BadBytes,x
    inx
    inx
    stx FirstPassErrors
    jmp StoreByte

;; The second copy: only the next logged address is taken again; verifying, it is compared with memory instead.
;; Also: RD58 (KV20)
SecondPass:
    ldx SecondPassErrors
    cpx FirstPassErrors
    beq Advance
    lda StartAddress
    cmp BadBytes,x
    bne Advance
    lda StartAddressHigh
    cmp BadBytes+1,x
    bne Advance
    inc SecondPassErrors
    inc SecondPassErrors
    lda VerifyFlag
    beq CheckRetry
    lda OutputCharacter
    ldy #0
    cmp (StartAddress),y
    beq Advance
    iny
    sty ByteErrors

;; A byte the second copy also got wrong is a second pass error; a good one is stored.
;; Also: RD52 (KV20)
CheckRetry:
    lda ByteErrors
    beq StoreByte

;; <IoStatus> gets <STATUS_SECOND_PASS_ERROR>.
;; Also: RD55 (KV20)
SecondPassError:
    lda #STATUS_SECOND_PASS_ERROR
    jsr Channels::ReadStatus::SetStatus
    bne Advance                     ; always: the status is not 0

;; Stores the byte at <StartAddress>, unless verifying.
;; Also: RD59 (KV20)
StoreByte:
    lda VerifyFlag
    bne Advance
    tay
    lda OutputCharacter
    sta (StartAddress),y

;; On to the next address; only an address that wraps to $0000 falls into the block's end.
;; Also: RD90 (KV20)
Advance:
    jsr NextAddress
    bne ToReturn

;; The block's end: passes over bytes until the next leader.
;; Also: RD160 (KV20)
BlockEnd:
    lda #READ_IGNORE

;; <ReadMode> = A; one copy fewer in <BlockCount> (not below 0).
;; Also: RD161 (KV20)
SetMode:
    sta ReadMode
    ldx BlockCount
    dex
    bmi NextPass
    stx BlockCount

;; A copy fewer left in <CopiesLeft>; with none, the read is done. With no bad bytes on the first copy, <BlockCount>
;; goes to 0: the second copy is still read through, but nothing is taken from it.
;; Also: RD167 (KV20)
NextPass:
    dec CopiesLeft
    beq AllRead
    lda FirstPassErrors
    bne ToReturn
    sta BlockCount
    beq ToReturn                    ; always

;; Both copies read: <Finish> stops the tape and puts the IRQ vector back, and the checksum is worked out over memory.
;; Also: RD175 (KV20)
AllRead:
    jsr Finish
    jsr ResetAddress
    ldy #0
    sty LoadChecksum

;; The exclusive or of every byte in memory from <Tape::LoadAddress> to <EndAddress>, against the block's checksum,
;; the last byte read; a difference is <STATUS_CHECKSUM_ERROR>. Verifying, memory was not loaded, so this checks it.
;; MTV spells VPRTY.
;; Also: VPRTY (KV20)
Checksum:
    lda (StartAddress),y
    eor LoadChecksum
    sta LoadChecksum
    jsr NextAddress
    jsr CompareAddresses
    bcc Checksum
    lda LoadChecksum
    eor OutputCharacter
    beq ToReturn
    lda #STATUS_CHECKSUM_ERROR
    jsr Channels::ReadStatus::SetStatus

;; On to the interrupt's end.
;; Also: RD180 (KV20)
ToReturn:
    jmp Interrupts::NmiHandler::Return
.endproc

;; Points <StartAddress> back at the block's start, <Tape::LoadAddress>.
;; In: Tape::LoadAddress = the block's start
;; Out: StartAddress = it, A = its low byte
;; Keeps: X, Y
;; Also: RD300 (KV20, MTV)
.proc ResetAddress
    lda LoadAddressHigh
    sta StartAddressHigh
    lda LoadAddress
    sta StartAddress
    rts
.endproc

;; Clears the counters for a new byte: 8 bits to come, the first pulse of a dipole, no error, even parity and no
;; pulses counted. Writing, the last two clear <MarkerLongWritten> and <MarkerOneWritten>.
;; Out: A = 0, zero = set, BitCount = 8, Dipole = 0, ReadError = 0, Parity = 0, ZeroesCount = 0
;; Keeps: X, Y
;; Also: NEWCH (KV20, MTV)
.proc NewByte
    lda #8
    sta BitCount
    lda #0
    sta Dipole
    sta ReadError
    sta Parity
    sta ZeroesCount
    rts
.endproc

;; Writes half a pulse: starts timer 2, whose interrupt ends the half, and toggles the cassette's write line. The half
;; is a short's or a long's by <OutputCharacter>'s bit 0 (0 short, 1 long). The line starts low, so it is low again
;; when a pulse is done.
;; In: OutputCharacter = the bit in bit 0
;; Out: zero = set when the line went low (the pulse is done), A = the line's bit, X = 0
;; Keeps: Y
;; Entry:
;;   Long = a long's half, whatever the bit
;;   Time = a half of A counts
;;   TimeHigh = a half of X times 256 plus A counts; X is kept
;; Also: WRITE (KV20, MTV)
.proc WritePulse
    lda OutputCharacter
    lsr a
    lda #SHORT_HALF
    bcc Time

;; A long's half, whatever the bit.
;; Also: WRTW (KV20)
Long:
    lda #LONG_HALF

;; A half of A counts.
;; Also: WRT1 (KV20)
Time:
    ldx #0

;; A half of X times 256 plus A counts.
;; Also: WRTX (KV20)
TimeHigh:
    sta Via2Timer2
    stx Via2Timer2High
    lda Via2PortB
    eor #WRITE_LINE
    sta Via2PortB
    and #WRITE_LINE
    rts
.endproc

;; The IRQ handler while writing a block's bytes, at each half pulse's end. Each byte is a marker and a long, then its
;; eight bits from bit 0 and a parity bit that makes the number of 1s odd, each bit a dipole of two pulses, the second
;; the complement of the first. The countdown comes first, then the data, then the checksum.
;;
;; The routine's first part, which <DataByte at WriteData::DataByte> comes to past the checksum, marks the block's
;; end in <StartAddressHigh>'s bit 7: the next marker is the last, and the trailer follows it. It runs from the
;; kernal's IRQ entry, which has pushed A, X and Y, while <IrqVector> points at <Interrupt at WriteData::Interrupt>,
;; and each path ends through <Interrupts::NmiHandler::Return>, pulling them back.
;; Entry:
;;   Interrupt = the vector's target: the marker's halves, then the bits'
;; Also: WRTL3 (KV20)
.proc WriteData
    sec
    ror StartAddressHigh
    bmi Return                      ; always

;; The vector's target: the marker's halves first, then the long's, then the bits'. Past the block's end, the
;; marker's second half goes on to <BlockDone>.
;; Also: WRTN (KV20)
Interrupt:
    lda MarkerLongWritten
    bne NotLong
    lda #<MARKER_HALF
    ldx #>MARKER_HALF
    jsr WritePulse::TimeHigh
    bne Return
    inc MarkerLongWritten
    lda StartAddressHigh
    bpl Return
    jmp BlockDone

;; The long after the marker.
;; Also: WRTN1 (KV20)
NotLong:
    lda MarkerOneWritten
    bne DataBit
    jsr WritePulse::Long
    bne Return
    inc MarkerOneWritten
    bne Return                      ; always

;; A bit: its dipole's two pulses, the second with <OutputCharacter>'s bit 0 turned over, which is added to the parity.
;; Also: WRTN2 (KV20)
DataBit:
    jsr WritePulse
    bne Return
    lda Dipole
    eor #1
    sta Dipole
    beq NextBit
    lda OutputCharacter
    eor #1
    sta OutputCharacter
    and #1
    eor Parity
    sta Parity

;; Returns from the interrupt.
;; Also: WRT3 (KV20)
Return:
    jmp Interrupts::NmiHandler::Return

;; The next bit; after the eighth the parity bit, and after that a new byte.
;; Also: WRT2 (KV20)
NextBit:
    lsr OutputCharacter
    dec BitCount
    lda BitCount
    beq ParityBit
    bpl Return

;; A new byte: from the countdown while it lasts (clearing the checksum), then the data. Interrupts go back on.
;; Also: WRTS (KV20)
NextByte:
    jsr NewByte
    cli
    lda SyncCountdown
    beq DataByte
    ldx #0
    stx WriteChecksum
    dec SyncCountdown
    ldx BlockCount
    cpx #BLOCK_COPIES
    bne CountByte
    ora #FIRST_COPY

;; A countdown byte, 9 to 1, with <FIRST_COPY> set on the first copy.
;; Also: WRT61 (KV20)
CountByte:
    sta OutputCharacter
    bne Return                      ; always

;; At <EndAddress>, the checksum is next, marked by one past <StartAddressHigh>; past it, the block's end.
;; Also: WRT6 (KV20)
DataByte:
    jsr CompareAddresses
    bcc FetchByte
    bne WriteData
    inc StartAddressHigh
    lda WriteChecksum
    sta OutputCharacter
    bcs Return                      ; always

;; The next data byte, added to the checksum. Only an address that wraps to $0000 falls into <ParityBit>.
;; Also: WRT7 (KV20)
FetchByte:
    ldy #0
    lda (StartAddress),y
    sta OutputCharacter
    eor WriteChecksum
    sta WriteChecksum
    jsr NextAddress
    bne Return

;; The parity bit: 1 when the byte's 1s are even, so that they come out odd.
;; Also: WRT4 (KV20)
ParityBit:
    lda Parity
    eor #1
    sta OutputCharacter

;; On to the interrupt's end.
;; Also: WRTBK (KV20)
ToReturn:
    jmp Interrupts::NmiHandler::Return

;; A copy is written. After the last, the motor goes off first, so the last trailer goes out as the tape stops.
;; Also: WRNC (KV20)
BlockDone:
    dec BlockCount
    bne Trailer
    jsr MotorOff

;; The trailer: <TRAILER_LENGTH> short pulses through <WriteLeader>.
;; Also: WREND (KV20)
Trailer:
    lda #TRAILER_LENGTH
    sta ShortCountLow
    ldx #LEADER_HANDLER
    sei
    jsr SetIrqVector
    bne ToReturn                    ; always: the handler's high byte is not 0
.endproc

;; The IRQ handler while writing a leader or a trailer of short pulses, counted in <ShortCountLow> and
;; <ShortCountHigh>. At its end, the data's handler takes over with a new countdown, or after the last copy's trailer
;; <AllWritten> ends the operation.
;;
;; <ShortCountLow> is not set for a leader, so its first count runs from what the byte holds (0 after a tape
;; operation, so 256). It runs from the kernal's IRQ entry, as <WriteData> does.
;; Also: WRTZ (KV20, MTV)
.proc WriteLeader
    ; A pulse; each 256 a new byte's counters for the data.
    lda #LEADER_HALF
    jsr WritePulse::Time
    bne WriteData::ToReturn
    dec ShortCountLow
    bne WriteData::ToReturn
    jsr NewByte
    dec ShortCountHigh
    bpl WriteData::ToReturn

    ; The leader done: the data's handler, ShortCountHigh at 0 for the trailer.
    ldx #DATA_HANDLER
    jsr SetIrqVector
    cli
    inc ShortCountHigh
    lda BlockCount
    beq Tape::AllWritten

    ; A copy to write: from its start, after the countdown.
    jsr ResetAddress
    ldx #COUNTDOWN_LENGTH
    stx SyncCountdown
    bne WriteData::NextByte         ; always
.endproc

;; Ends a tape operation: the motor off, VIA 2's interrupts and timers back as the jiffy interrupt has them, the
;; write line low, and the IRQ vector put back from <SavedIrq> if it holds one. Interrupts are masked meanwhile, and
;; the status register is put back.
;; In: SavedIrq = the vector to put back, or a high byte of 0 for none
;; Out: IrqVector = the vector kept in <SavedIrq>, if any
;; Keeps: X, Y, P
;; Also: TNIF (KV20, MTV)
.proc Finish
    php
    sei
    jsr MotorOff
    lda #VIA_INTERRUPTS_ALL
    sta Via2InterruptEnable
    lda #<(~WRITE_LINE)
    sta Via2PortB
    lda #VIA_TIMER1_FREE_RUNNING
    sta Via2AuxiliaryControl
    jsr Startup::InitializeIo::StartJiffyTimer

    ; The vector, if one was kept.
    lda SavedIrq+1
    beq Done
    sta IrqVector+1
    lda SavedIrq
    sta IrqVector

;; Puts the status register back and returns.
;; Also: TNIQ (KV20)
Done:
    plp
    rts
.endproc

;; The last trailer is written: <Finish>es the operation, then ends the interrupt. <WriteLeader> comes here after the
;; last copy, though it sits after <Finish> in the ROM.
;; Also: STKY (KV20)
.proc AllWritten
    jsr Finish
    beq WriteData::ToReturn         ; always: Finish puts back the zero flag from BlockCount's test
.endproc

;; Points <IrqVector> at the tape's handler X names in <InterruptHandlers>: <LEADER_HANDLER>, <DATA_HANDLER>, 12 for
;; the kernal's own IRQ, or <READ_HANDLER>.
;; In: X = the handler's number
;; Out: IrqVector = the handler, A = its high byte, zero = clear
;; Keeps: X, Y
;; Also: BSIV (KV20)
.proc SetIrqVector
    lda InterruptHandlers-LEADER_HANDLER,x
    sta IrqVector
    lda InterruptHandlers+1-LEADER_HANDLER,x
    sta IrqVector+1
    rts
.endproc

;; Turns the cassette motor off: VIA 1's CA2 held high.
;; Out: A = VIA 1's peripheral control
;; Keeps: X, Y
;; Also: TNOF (KV20)
.proc MotorOff
    lda Via1PeripheralControl
    ora #MOTOR_OUTPUT | MOTOR_STOP
    sta Via1PeripheralControl
    rts
.endproc

;; Compares <StartAddress> with <EndAddress>: SAVE and the tape's read and write use it to find the end of a block.
;; In: StartAddress = the address reached, EndAddress = the end
;; Out: carry = set when <StartAddress> has reached <EndAddress>, zero = set when the high bytes' difference is 0
;;   (at the end itself, clear past it)
;; Keeps: X, Y
;; Also: CMPSTE (KV20)
.proc CompareAddresses
    sec
    lda StartAddress
    sbc EndAddress
    lda StartAddressHigh
    sbc EndAddressHigh
    rts
.endproc

;; Moves <StartAddress> up one.
;; In: StartAddress = the address
;; Out: StartAddress = the next, zero = set only when it wrapped to $0000
;; Keeps: A, X, Y, carry
;; Also: INCSAL (KV20)
.proc NextAddress
    inc StartAddress
    bne Done
    inc StartAddressHigh

;; Returns.
;; Also: INCR (KV20)
Done:
    rts
.endproc

.endscope
