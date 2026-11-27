; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: RS-232 ($EFA3-$F173)

; RS-232's sending and receiving, its channels and its buffers. Opening the device is in Kernal.Channels.asm, and
; the NMI that times the bits, with the baud rate tables, in Kernal.Interrupts.asm.
;
; The VIC-20 has no serial chip: the kernal makes RS-232 in software on the user port, VIA 1's port B, and programs
; it as if it were a 6551 ACIA, through Control and Command, which OPEN copies from the file name. Bits go out
; on CB2 and come in on PB0, at TTL levels; a 1 (mark) is high, and a byte starts with a 0 (space), the start bit.
; VIA 1's interrupts are the NMI, which the RESTORE key shares: timer 1, free-running at the bit time, sends each
; bit; CB1, wired to the received data, takes the start bit's falling edge; and timer 2 then samples each bit at its
; middle. Each direction has a 256-byte ring buffer that OPEN takes from the top of memory. With x-line handshaking
; (Command's bit 0), the user port's other lines are used too: RTS (PB1) and DTR (PB2) out, DCD (PB4), CTS (PB6) and
; DSR (PB7) in.

.scope Rs232 continued

; VIA 1's interrupts that RS-232 runs on, as <Via1InterruptEnable> and <Via1InterruptFlags> have them.

;; Timer 1's interrupt: an NMI each bit time while a byte is being sent.
SEND_INTERRUPT = %01000000

;; Timer 2's interrupt: an NMI in the middle of each bit being received.
RECEIVE_INTERRUPT = %00100000

;; CB1's interrupt: an NMI at the falling edge of the received data, the start of a byte.
START_BIT_INTERRUPT = %00010000

; The user port's lines in <Via1PortB>. CTS (bit 6) and DSR (bit 7) are tested with BIT, through overflow and
; negative.

;; Bit 0, in: the received data.
RECEIVED_DATA = %00000001

;; Bit 1, out: RTS, Request To Send.
REQUEST_TO_SEND = %00000010

;; Bit 2, out: DTR, Data Terminal Ready.
DATA_TERMINAL_READY = %00000100

; The bits being sent.

;; <NextBit> for a 1: bit 5, the bit of <Via1PeripheralControl> that turns CB2, the send line, from low to high.
SEND_LINE_HIGH = %00100000

;; <Via1PeripheralControl> with the send line, CB2, low, for a 0; the NMI ORs <NextBit> into it. CA2 is high, which
;; keeps the cassette motor off, and CB1 and CA1 interrupt on falling edges.
SEND_LINE_LOW_CONTROL = %11001110

;; A 1, as the bit being sent is kept in X: $FF for a 1 and 0 for a 0, so that ANDing it with a bit gives that bit
;; or nothing.
BIT_ONE = $FF

; The bits of <Control> and <Command>, as a 6551's registers have them.

;; <Control>'s bits 0-3: the baud rate, 1 to 11 for 50 to 3600 baud, an index into <BaudRates>.
CONTROL_BAUD_RATE = %00001111

;; <Control>'s bit 5, the word length's low bit: set for 7 or 5 data bits. Bit 6, which code tests through
;; overflow, is set for 6 or 5; bit 7, tested through negative, asks for two stop bits.
CONTROL_WORD_LENGTH_LOW = %00100000

;; <Command>'s bit 5: a parity bit is sent and checked. Bits 6 and 7, tested through overflow and negative, pick it:
;; 0 and 0 odd, 1 and 0 even, 0 and 1 mark (always 1), 1 and 1 space (always 0).
COMMAND_PARITY = %00100000

;; <Command>'s bit 4: half duplex, sending and receiving in turn. Bit 0, tested by shifting it into carry, is x-line
;; handshaking.
COMMAND_HALF_DUPLEX = %00010000

;; <WordBits> for an 8-bit word, the longest: the data bits plus one.
LONGEST_WORD_BITS = 9

; The bits of <Status>, RS-232's status, which BASIC's ST reads for device 2.

;; Bit 0: a received byte's parity bit was wrong.
STATUS_PARITY_ERROR = %00000001

;; Bit 1: a received byte's stop bit was a 0.
STATUS_FRAME_ERROR = %00000010

;; Bit 2: a byte came in with the input buffer full, and was lost.
STATUS_OVERRUN = %00000100

;; Bit 4: CTS, Clear To Send, was missing when a byte was to be sent.
STATUS_NO_CTS = %00010000

;; Bit 6: DSR, Data Set Ready, was missing.
STATUS_NO_DSR = %01000000

;; Bit 7: a break, a byte and its stop bit all 0s, came in.
STATUS_BREAK = %10000000

;; Works out the next bit to send, for the NMI to put on the line at the next tick of timer 1: called from the NMI
;; just after it has sent <NextBit>.
;;
;; The bits of a byte are the start bit (which <StartByte> sets), the data bits from the low bit up, the parity bit
;; <Command> asks for, and one or two stop bits as <Control> says. <SendBitCount> counts them down: from <WordBits>
;; to 0 through the data bits, then negative for the stop bits, and at 0 again the next byte starts, through
;; <StartByte>. The data bits' parity builds up in <SendParity>, as $00 or $FF.
;; In: SendBitCount = the bits left, SendByte = the data bits not yet sent, SendParity = their parity so far
;; Out: NextBit = 0 or <SEND_LINE_HIGH>
;; Also: RSTRAB (KV20)
.proc SendNextBit
    lda SendBitCount
    beq StartByte
    bmi StopBit

    ; A data bit, from the low bit up. The count's last pass shifts out the bit past the word, for the parity bit.
    lsr SendByte
    ldx #0
    bcc Parity
    dex

;; Adds the bit to the parity; after the data, goes on to the parity bit.
;; Also: RST005 (KV20)
Parity:
    txa
    eor SendParity
    sta SendParity
    dec SendBitCount
    beq ParityBit

;; Sets <NextBit> from the bit in X.
;; Also: RSTEXT (KV20)
SetBit:
    txa
    and #SEND_LINE_HIGH
    sta NextBit
    rts

;; After the data, the parity bit <Command> asks for: none, odd, even, mark or space. X is a 0 here, which becomes
;; a 1 at <SendNextBit::Flip>, but only if the byte's bits past the word are 0s: the count's last shift takes the
;; next bit, and adds it to the parity too, so a word shorter than 8 bits needs its unused bits clear.
;; Also: RST010 (KV20)
ParityBit:
    lda #COMMAND_PARITY
    bit Command
    beq NoParity
    bmi Fixed
    bvs Even

    ; Odd: a 1 when the data has an even number of 1s.
    lda SendParity
    bne StopBits

;; The bit is a 1.
;; Also: RSWEXT (KV20)
Flip:
    dex

;; The parity bit, then one or two stop bits, as <Control>'s bit 7 says.
;; Also: RSPEXT (KV20)
StopBits:
    dec SendBitCount
    lda Control
    bpl SetBit
    dec SendBitCount
    bne SetBit                      ; always: the count is negative

;; No parity: the first stop bit, a 1, takes the parity bit's place.
;; Also: RSPNO (KV20)
NoParity:
    inc SendBitCount
    bne Flip                        ; always: the count is now 1

;; Even: a 1 when the data has an odd number of 1s.
;; Also: RST030 (KV20)
Even:
    lda SendParity
    beq StopBits
    bne Flip

;; Mark, always a 1, or space, always a 0.
;; Also: RST040 (KV20)
Fixed:
    bvs StopBits
    bvc Flip

;; A stop bit: a 1.
;; Also: RST050 (KV20)
StopBit:
    inc SendBitCount
    ldx #BIT_ONE
    bne SetBit
.endproc

;; Starts the next byte from the output buffer: a start bit, with the parity and the count reset, or, with the
;; buffer empty, an end to sending.
;;
;; With x-line handshaking (<Command>'s bit 0) it first needs DSR and CTS, else it reports the one missing in
;; <Status> and stops sending. It reads them from <Via2PortB>, though: VIA 2's port B is the keyboard's column lines,
;; and the user port is <Via1PortB>, where <SelectOutput> reads them. *Mapping the VIC* takes this for a slip (it says
;; the code checks the wrong VIA port); as written, the test depends on the keyboard column last selected.
;; In: OutputStart = the next byte's index, OutputEnd = the end's, WordBits = the bits to count
;; Out: NextBit = 0, the start bit, SendBitCount = <WordBits>, SendByte = the byte, OutputStart = the next index
;; Errors: Status = <STATUS_NO_DSR> or <STATUS_NO_CTS> ORed in, and sending stopped
;; Also: RSTBGN (KV20)
.proc StartByte
    lda Command
    lsr a
    bcc NoHandshake
    bit Via2PortB
    bpl SendError
    bvc SendError::ClearToSendLost

;; The parity cleared, a start bit next, and the word's bits to count; then the byte, if there is one.
;; Also: RST060 (KV20)
NoHandshake:
    lda #0
    sta SendParity
    sta NextBit
    ldx WordBits
    stx SendBitCount
    ldy OutputStart
    cpy OutputEnd
    beq SendError::StopSending
    lda (OutputBuffer),y
    sta SendByte
    inc OutputStart
    rts
.endproc

;; Reports DSR missing: ORs <STATUS_NO_DSR> into <Status>, and stops sending by turning timer 1's interrupt off.
;; Out: A = <SEND_INTERRUPT>
;; Keeps: X, Y
;; Entry:
;;   ClearToSendLost = reports CTS missing, <STATUS_NO_CTS>, instead
;;   StopSending = only stops sending (<StartByte> comes here when the buffer is empty)
;; Also: DSRERR (KV20)
.proc SendError
    lda #STATUS_NO_DSR
    .byte OPCODE_BIT                ; skips ClearToSendLost's LDA

;; CTS missing: <STATUS_NO_CTS>.
;; Also: CTSERR (KV20)
ClearToSendLost:
    lda #STATUS_NO_CTS
    ora Status
    sta Status

;; Turns timer 1's interrupt off: nothing more is sent.
;; Also: RSODNE (KV20)
StopSending:
    lda #SEND_INTERRUPT
    sta Via1InterruptEnable
    rts
.endproc

;; Works out <WordBits>, the bits counted for a word, from <Control>'s word length: the data bits plus one, so 9, 8,
;; 7 or 6 for 8, 7, 6 or 5 data bits.
;; In: Control = the word length in bits 5 and 6
;; Out: X = the bits
;; Keeps: Y
;; Also: BITCNT (KV20)
.proc CountWordBits
    ldx #LONGEST_WORD_BITS
    lda #CONTROL_WORD_LENGTH_LOW
    bit Control
    beq NotSeven
    dex

;; Bit 6 takes two more off.
;; Also: BIT010 (KV20)
NotSeven:
    bvc Done
    dex
    dex

;; Returns.
;; Also: BIT020 (KV20)
Done:
    rts
.endproc

;; Takes one received bit, called from the NMI in the middle of each bit with it in <ReceivedBit>: the start bit
;; checked, a data bit shifted into <ReceivedByte>, the byte stored, its parity bit checked, its stop bits checked.
;;
;; <ReceiveBitCount> counts the bits down from <WordBits>, set at the start bit's edge: at 0, after the data bits,
;; the byte goes into the input buffer and the bit is the parity bit (or with no parity the first stop bit), and
;; then it goes negative for the stop bits. A byte that ends, well or not, waits for the next start bit
;; (<ReceiveBit::Rearm>). Errors go into <Status>: a full buffer, a wrong parity bit, a 0 stop bit (a break if the
;; byte is all 0s, else a frame error).
;;
;; The parity check looks wrong. <ReceivedParity> builds up the data bits' parity, but RS-232's code never clears
;; it, so each byte starts from the last byte's, or from what the tape last left in the same byte (the tape reader
;; zeroes it as <Tape::LoadChecksum>, and checksums into it). And from 0, the check would report a byte whose
;; parity is right: with odd parity, data and parity bit together with an odd number of 1s set
;; <STATUS_PARITY_ERROR>, and an even number pass.
;; In: ReceivedBit = the bit, 0 or 1, WaitingForStart = nonzero for the start bit
;; Entry:
;;   Rearm = waits for the next start bit: CB1's interrupt on, timer 2's off
;; Also: RSRCVR (KV20)
.proc ReceiveBit
    ldx WaitingForStart
    bne StartBit
    dec ReceiveBitCount
    beq StoreByte
    bmi StopBit

    ; A data bit: into the parity, and into the byte from the top.
    lda ReceivedBit
    eor ReceivedParity
    sta ReceivedParity
    lsr ReceivedBit
    ror ReceivedByte

;; Returns.
;; Also: RSREXT (KV20)
Return:
    rts

;; No parity bit: this bit is the first stop bit.
;; Also: RSR018 (KV20)
NoParity:
    dec ReceiveBitCount

;; A stop bit must be a 1; a 0 is a break or a frame error. With two stop bits (<Control>'s bit 7, into carry), the
;; first returns, and the second waits for the next byte.
;; Also: RSR020 (KV20)
StopBit:
    lda ReceivedBit
    beq CheckStop
    lda Control
    asl a
    lda #1
    adc ReceiveBitCount
    bne Return

;; Waits for the next start bit: CB1's interrupt on, with <WaitingForStart> set, and timer 2's off.
;; Also: RSRABL (KV20)
Rearm:
    lda #VIA_INTERRUPTS_ON | START_BIT_INTERRUPT
    sta Via1InterruptEnable
    sta WaitingForStart
    lda #RECEIVE_INTERRUPT
    sta Via1InterruptEnable
    rts

;; The start bit's middle: still a 1 there was noise, so wait again; a 0 starts the byte.
;; Also: RSRTRT (KV20)
StartBit:
    lda ReceivedBit
    bne Rearm
    sta WaitingForStart
    rts

;; The data bits are in: the byte goes in at <InputEnd>, unless the buffer is full.
;; Also: RSR030 (KV20)
StoreByte:
    ldy InputEnd
    iny
    cpy InputStart
    beq Overrun
    sty InputEnd
    dey
    lda ReceivedByte
    ldx WordBits

;; Shifts a shorter word down to bit 0, since its bits came in at the top.
;; Also: RSR031 (KV20)
Align:
    cpx #LONGEST_WORD_BITS
    beq Store
    lsr a
    inx
    bne Align                       ; always

;; Into the buffer; then the parity bit, as <Command> asks.
;; Also: RSR032 (KV20)
Store:
    sta (InputBuffer),y
    lda #COMMAND_PARITY
    bit Command
    beq NoParity
    bmi Return                      ; mark or space: not checked

    ; Odd or even: the parity bit with the data's.
    lda ReceivedBit
    eor ReceivedParity
    beq Even
    bvs Return
    .byte OPCODE_BIT                ; skips Even's BVC, to the error

;; Data and parity bit with an even number of 1s.
;; Also: RSR050 (KV20)
Even:
    bvc Return
    lda #STATUS_PARITY_ERROR
    .byte OPCODE_BIT                ; skips the LDAs below

;; The buffer is full: <STATUS_OVERRUN>, and the byte is lost.
;; Also: RECERR (KV20)
Overrun:
    lda #STATUS_OVERRUN
    .byte OPCODE_BIT

;; A break: <STATUS_BREAK>.
;; Also: BREAKE (KV20)
Break:
    lda #STATUS_BREAK
    .byte OPCODE_BIT

;; A frame error: <STATUS_FRAME_ERROR>. Every error ORs its bit into <Status> here and waits for the next byte.
;; Also: FRAMEE (KV20)
FrameError:
    lda #STATUS_FRAME_ERROR
    ora Status
    sta Status
    jmp Rearm

;; A 0 stop bit: a break if the byte is all 0s, otherwise a frame error.
;; Also: RSR060 (KV20)
CheckStop:
    lda ReceivedByte
    bne FrameError
    beq Break
.endproc

;; LOAD and SAVE on device 2, which RS-232 cannot do: ILLEGAL DEVICE NUMBER.
;; Errors: carry = set, A = <KERNAL_ERROR_ILLEGAL_DEVICE>
;; Also: RS232 (KV20)
.proc NoLoadOrSave
    jmp Channels::Error::IllegalDevice
.endproc

;; CHKOUT's work for device 2: makes RS-232 the output, and with x-line handshaking makes the line ready to send.
;;
;; With x-line handshaking (<Command>'s bit 0), it needs DSR. If RTS is already raised it is done; otherwise it
;; waits for the receiver to stop, then for CTS to drop, raises RTS and waits for CTS. Losing DSR on the way reports
;; it through <SendError>, which also stops sending.
;;
;; The receiver's wait looks endless: it waits for timer 2's and CB1's interrupts both to be off, but the receiver
;; turns CB1's on again after every byte (<ReceiveBit::Rearm>), and RTS is low only after <SelectInput> has turned it
;; on. Only <Pause>, <Channels::Close> for the RS-232 file and <Startup::InitializeIo> (at start-up, and for STOP with
;; RESTORE) turn both off; the NMI never leaves both off, since at a start bit it turns CB1's off and timer 2's on.
;; In: A = the device, 2
;; Out: OutputDevice = A, carry = clear
;; Errors: Status = <STATUS_NO_DSR> ORed in, with carry still clear
;; Keeps: X, Y
;; Entry:
;;   DsrError = reports DSR missing through <SendError> and returns with carry clear (<SelectInput> comes here too)
;; Also: CKO232 (KV20)
.proc SelectOutput
    sta OutputDevice
    lda Command
    lsr a
    bcc Done

    ; Negative = DSR, zero = RTS low.
    lda #REQUEST_TO_SEND
    bit Via1PortB
    bpl DsrError
    bne Done

;; Until nothing is being received.
;; Also: CKO020 (KV20)
WaitInputDone:
    lda Via1InterruptEnable
    and #RECEIVE_INTERRUPT | START_BIT_INTERRUPT
    bne WaitInputDone

;; Until CTS is off; then RTS raised.
;; Also: CKO030 (KV20)
WaitClearToSendOff:
    bit Via1PortB
    bvs WaitClearToSendOff
    lda Via1PortB
    ora #REQUEST_TO_SEND
    sta Via1PortB

;; Waits for CTS, as long as DSR holds.
;; Also: CKO040 (KV20)
WaitClearToSend:
    bit Via1PortB
    bvs Done
    bmi WaitClearToSend

;; DSR missing: <SendError>.
;; Also: CKDSRX (KV20)
DsrError:
    jsr SendError

;; Carry clear.
;; Also: CKO100 (KV20)
Done:
    clc
    rts
.endproc

;; CHROUT's work for device 2: puts A in the output buffer, waiting while the buffer is full, and starts sending if
;; nothing is being sent.
;;
;; The wait for room has no limit: it ends only as the NMI sends bytes, so with sending stopped and the buffer full it
;; would never end.
;; In: A = the byte
;; Also: BSO232 (KV20)
.proc CharacterOut
    ldy OutputEnd
    iny
    cpy OutputStart
    beq CharacterOut
    sty OutputEnd
    dey
    sta (OutputBuffer),y
    bit Via1InterruptEnable
    bvc StartSender                 ; overflow = timer 1's interrupt, so sending
    rts

;; Starts timer 1 at the bit time, free-running, with its interrupt on, and the first byte.
;; Also: BSO110 (KV20)
StartSender:
    lda BitTime
    sta Via1Timer1
    lda BitTime+1
    sta Via1Timer1High
    lda #VIA_INTERRUPTS_ON | SEND_INTERRUPT
    sta Via1InterruptEnable
    jmp StartByte
.endproc

;; CHKIN's work for device 2: makes RS-232 the input, and turns the receiver on to wait for a start bit.
;;
;; With x-line handshaking and half duplex (<Command>'s bits 0 and 4), it needs DSR. If RTS is already low it is
;; done, without turning the receiver on; otherwise it waits for sending to end, drops RTS, waits for the carrier,
;; and turns the receiver on. Otherwise it turns the receiver on unless it is already receiving.
;;
;; The carrier's wait tests <DATA_TERMINAL_READY>, bit 2, DTR, which is an output that OPEN raised, so it ends at
;; once; DCD, the carrier, is bit 4.
;; In: A = the device, 2
;; Out: InputDevice = A, carry = clear
;; Errors: Status = <STATUS_NO_DSR> ORed in, with carry still clear
;; Keeps: X, Y
;; Also: CKI232 (KV20)
.proc SelectInput
    sta InputDevice
    lda Command
    lsr a
    bcc FullDuplex
    and #COMMAND_HALF_DUPLEX >> 1
    beq FullDuplex

    ; Negative = DSR, zero = RTS low.
    lda #REQUEST_TO_SEND
    bit Via1PortB
    bpl SelectOutput::DsrError
    beq Done

;; Until nothing is being sent; then RTS dropped.
;; Also: CKI010 (KV20)
WaitOutputDone:
    bit Via1InterruptEnable
    bvs WaitOutputDone
    lda Via1PortB
    and #<~REQUEST_TO_SEND
    sta Via1PortB

;; Until the carrier, as the code tests it.
;; Also: CKI020 (KV20)
WaitCarrier:
    lda Via1PortB
    and #DATA_TERMINAL_READY
    beq WaitCarrier

;; CB1's interrupt on: the receiver waits for a start bit.
;; Also: CKI080 (KV20)
EnableStartBit:
    lda #VIA_INTERRUPTS_ON | START_BIT_INTERRUPT
    sta Via1InterruptEnable

;; Carry clear.
;; Also: CKI090 (KV20)
Done:
    clc
    rts

;; Turns the receiver on unless it is already on, waiting or receiving.
;; Also: CKI100 (KV20)
FullDuplex:
    lda Via1InterruptEnable
    and #RECEIVE_INTERRUPT | START_BIT_INTERRUPT
    beq EnableStartBit
    clc
    rts
.endproc

;; CHRIN's and GETIN's work for device 2: the next byte from the input buffer, or 0 if it is empty.
;; Out: A = the byte, or 0
;; Keeps: X
;; Also: BSI232 (KV20)
.proc CharacterIn
    ldy InputStart
    cpy InputEnd
    beq Empty
    lda (InputBuffer),y
    inc InputStart
    rts

;; A = 0.
;; Also: BSI010 (KV20)
Empty:
    lda #0
    rts
.endproc

;; Before the serial bus or the tape, whose timing its NMIs would upset: waits for RS-232 to finish sending and
;; receiving, then turns its start bit's interrupt off, so that no new byte is received.
;;
;; The test for no interrupts at all never passes: a 6522 reads its interrupt enable register's bit 7 as 1.
;; Keeps: A, X, Y
;; Also: RSP232 (KV20)
.proc Pause
    pha
    lda Via1InterruptEnable
    beq Done                        ; never: bit 7 reads as 1

;; Until timers 1 and 2 are idle: nothing being sent or received.
;; Also: RSPOFF (KV20)
WaitDone:
    lda Via1InterruptEnable
    and #SEND_INTERRUPT | RECEIVE_INTERRUPT
    bne WaitDone
    lda #START_BIT_INTERRUPT        ; bit 7 clear: off
    sta Via1InterruptEnable

;; Restores A.
;; Also: RSPOK (KV20)
Done:
    pla
    rts
.endproc

.endscope
