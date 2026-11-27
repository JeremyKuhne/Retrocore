; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE SERIAL BUS ($EE14-$EFA2)

; The serial bus's main part: the commands, sending and receiving a byte, and the line routines. Its three line
; routines in the patch area at $E4A0 (ReleaseData, PullData and ReadLines) are the first piece.
;
; The bus is Commodore's serial version of the PET's IEEE-488, for the disk drives and printers (devices 4 to 31).
; It has three shared lines, ATN, CLK and DATA, each pulled up: any device may pull a line low, and it is high only
; while every device has released it. The VIC-20 drives ATN from VIA 1's port A bit 7, CLK from VIA 2's CA2 and
; DATA from VIA 2's CB2, each through an inverter, and reads CLK and DATA back on VIA 1's port A bits 0 and 1.
;
; A byte goes from the talker, which holds CLK, to the listeners, which hold DATA. The talker releases CLK when it
; is ready to send, and the listeners release DATA when they are ready to take it. Then, for each of the eight bits,
; low bit first, the talker puts the bit on DATA (released for a 1) and releases CLK while it is valid; at the end
; each listener pulls DATA within a millisecond to accept the byte. A talker that waits longer than about 200
; microseconds before the first bit marks the byte as the last (EOI, End Or Identify), and the listener answers by
; pulsing DATA. While ATN is pulled, every device listens, and the bytes are commands: LISTEN or TALK with a device
; number, a secondary address, or UNLISTEN or UNTALK.

.scope Serial continued

; The commands, sent under ATN.

;; The LISTEN command, ORed with the device number: the device is to take the bytes that follow.
COMMAND_LISTEN = $20

;; The TALK command, ORed with the device number: the device is to send.
COMMAND_TALK = $40

;; The UNLISTEN command: every listener stops listening.
COMMAND_UNLISTEN = $3F

;; The UNTALK command: the talker stops talking.
COMMAND_UNTALK = $5F

; The lines' bits.

;; <Via2PeripheralControl>'s bit 1, CA2's level while CA2 is a manual output: set, the inverter pulls CLK low.
CLOCK_OUT = %00000010

;; <Via2PeripheralControl>'s bit 5, CB2's level while CB2 is a manual output: set, the inverter pulls DATA low.
DATA_OUT = %00100000

; The timing.

;; <Via2InterruptFlags>' bit 5: VIA 2's timer 2 has run out.
TIMER_2_DONE = %00100000

;; Timer 2's high byte for a wait of about a millisecond: at least $0400 counts, 1024 cycles, the low byte being
;; whatever was last latched.
MILLISECOND_TIMER_HIGH = $04

;; Timer 2's high byte for the EOI wait: at least $0100 counts, 256 cycles, about a quarter of a millisecond. A
;; talker that waits longer than that before it sends marks the byte as the last.
EOI_TIMER_HIGH = $01

;; The bits in a byte, each clocked on its own.
BITS_PER_BYTE = 8

;; The passes of <ReleaseLines>' delay loop, 5 cycles each: with the code around it, about 60 cycles.
RELEASE_DELAY = 11

;; Sends the TALK command for the device in A, under ATN, so that it sends to the VIC-20; ATN stays pulled.
;;
;; It skips <Listen>'s first instruction to share its code: the byte waiting in <BufferedCharacter> goes first, with
;; EOI, then the command. Follow it with <SendTalkSecondary>, or with <TurnAround> when there is no secondary
;; address.
;;
;; Commodore's listing and *Mapping the VIC* name it TALK (KV20, MTV), the name of <KernalTalk>.
;; In: A = the device, 4 to 31
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when a device does not answer
;; Keeps: X, Y
.proc Talk
    ora #COMMAND_TALK
    .byte OPCODE_BIT                ; skips Listen's ORA, so the command stays TALK
    .assert * = Listen, "Talk's BIT must take Listen's first instruction as its operand."
.endproc

;; Sends the LISTEN command for the device in A, under ATN, so that it takes the bytes that follow; ATN stays
;; pulled.
;;
;; It first waits for RS-232 to finish (<Rs232::Pause>), whose interrupts would upset the bus's timing, and sends any
;; byte still waiting in <BufferedCharacter>, with EOI, since it was the last of what went before. Follow it with
;; <SendSecondary>, or release ATN with <ReleaseAtn>.
;; In: A = the device, 4 to 31
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when a device does not answer
;; Keeps: X, Y
;; Entry:
;;   SendCommand = sends the command in A as it is (<Unlisten> and <Untalk> come here)
;; Also: LISTN (KV20)
.proc Listen
    ora #COMMAND_LISTEN
    jsr Rs232::Pause

;; Sends the command in A, first sending a byte still waiting, with EOI.
;; Also: LIST1 (KV20, MTV)
SendCommand:
    pha
    bit CharacterWaiting
    bpl NoneWaiting

    ; The byte waiting goes with EOI, and then nothing waits.
    sec
    ror EndOfFile
    jsr SendBufferedByte
    lsr CharacterWaiting
    lsr EndOfFile

;; Puts the command in <BufferedCharacter> and releases DATA.
;;
;; The compare that follows was meant to release CLK too before UNLISTEN, but <ReleaseData> has just loaded A with
;; VIA 2's peripheral control, so A is never <COMMAND_UNLISTEN> and CLK stays pulled. Nothing is lost: CLK would be
;; pulled again at once, and <Unlisten> releases every line when the command is sent.
;; Also: LIST2 (KV20)
NoneWaiting:
    pla
    sta BufferedCharacter
    jsr ReleaseData
    cmp #COMMAND_UNLISTEN           ; A is VIA 2's peripheral control here, not the command
    bne PullAtn
    jsr ReleaseClock

;; Pulls ATN, so that every device listens for the command.
;; Also: LIST5 (KV20)
PullAtn:
    lda Via1PortA
    ora #VIA1_SERIAL_ATN
    sta Via1PortA
    ; Falls into SendCommandByte.
.endproc

;; Sends <BufferedCharacter> as the first byte under ATN: pulls CLK, releases DATA and gives the devices a
;; millisecond to answer ATN by pulling DATA.
;; In: BufferedCharacter = the byte, EndOfFile = bit 7 set to send it with EOI
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when a device does not answer
;; Keeps: X, Y
;; Also: ISOURA (KV20)
.proc SendCommandByte
    jsr PullClock
    jsr ReleaseData
    jsr WaitOneMillisecond
    ; Falls into SendBufferedByte.
.endproc

;; Sends <BufferedCharacter> to the listeners, with EOI if <EndOfFile>'s bit 7 is set, with interrupts off meanwhile.
;;
;; It finds no device when DATA is high (no listener holds it), waits for the listeners to be ready, clocks the eight
;; bits out, low bit first, and waits up to a millisecond for a listener to accept the byte. It ends with interrupts
;; on, on every path, and <BufferedCharacter> shifted out (a byte of 1s).
;; In: BufferedCharacter = the byte, EndOfFile = bit 7 set to send it with EOI
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> ORed in with no device, both timeout bits when a listener pulls DATA
;;   during the byte or does not accept it; the lines are then released
;; Keeps: X, Y
;; Also: ISOUR (KV20)
.proc SendBufferedByte
    sei

    ; DATA still high with it released: no device is listening.
    jsr ReleaseData
    jsr ReadLines
    lsr a
    bcs BusError

    ; Ready to send: CLK released. With EOI, the listeners must see the wait first.
    jsr ReleaseClock
    bit EndOfFile
    bpl WaitReady

;; EOI: waits for the listeners to release DATA, ready for the byte, and then hold back, so they see the wait...
;; Also: ISR02 (KV20)
EoiReleased:
    jsr ReadLines
    lsr a
    bcc EoiReleased

;; ...and for a listener to pull DATA again, which acknowledges the EOI.
;; Also: ISR03 (KV20)
EoiAcknowledged:
    jsr ReadLines
    lsr a
    bcs EoiAcknowledged

;; Waits for the listeners to release DATA, ready for the byte, then pulls CLK to start it.
;; Also: NOEOI (KV20)
WaitReady:
    jsr ReadLines
    lsr a
    bcc WaitReady
    jsr PullClock
    lda #BITS_PER_BYTE
    sta BitCount

;; Each bit, low bit first. DATA must be released when a bit starts: a listener pulling it is a timeout.
;; Also: ISR01 (KV20)
NextBit:
    lda Via1PortA
    cmp Via1PortA
    bne NextBit                     ; until two reads agree
    lsr a
    lsr a                           ; carry = DATA
    bcc BusError::Timeout
    ror BufferedCharacter
    bcs BitOne
    jsr PullData
    bne ClockBit                    ; always: PullData leaves A nonzero

;; A 1: DATA released.
;; Also: ISRHI (KV20)
BitOne:
    jsr ReleaseData

;; Releases CLK while the bit is valid, then in one write releases DATA and pulls CLK for the next.
;; Also: ISRCLK (KV20)
ClockBit:
    jsr ReleaseClock
    nop
    nop
    nop
    nop
    lda Via2PeripheralControl
    and #<~DATA_OUT
    ora #CLOCK_OUT
    sta Via2PeripheralControl
    dec BitCount
    bne NextBit
    lda #MILLISECOND_TIMER_HIGH
    sta Via2Timer2High

;; Waits up to a millisecond for a listener to pull DATA, which accepts the byte.
;; Also: ISR04 (KV20)
WaitAccepted:
    lda Via2InterruptFlags
    and #TIMER_2_DONE
    bne BusError::Timeout
    jsr ReadLines
    lsr a
    bcs WaitAccepted
    cli
    rts
.endproc

;; The serial routines' error exit for a device that is not there: ORs <STATUS_DEVICE_NOT_PRESENT> into <IoStatus>,
;; turns interrupts on and releases every line, with carry clear.
;;
;; The routines report a failed transfer in <IoStatus> alone, never in carry, so that the channel routines can go on
;; and test the status when the commands are done.
;; In: A = the status bits, at <BusError::SetStatus>
;; Out: carry = clear
;; Keeps: X, Y
;; Entry:
;;   Timeout = ORs in both timeout bits, <STATUS_WRITE_TIMEOUT> and <STATUS_READ_TIMEOUT>: a listener did not answer
;;   SetStatus = ORs in the bits in A (<ReceiveByte> comes here with <STATUS_READ_TIMEOUT>)
;; Also: NODEV (KV20)
.proc BusError
    lda #STATUS_DEVICE_NOT_PRESENT
    .byte OPCODE_BIT                ; skips Timeout's LDA

;; ORs in both timeout bits: a listener did not answer. Commodore's listing calls it a framing error.
;; Also: FRMERR (KV20)
Timeout:
    lda #STATUS_WRITE_TIMEOUT | STATUS_READ_TIMEOUT

;; ORs the bits in A into <IoStatus> and releases the lines.
;; Also: CSBERR (KV20)
SetStatus:
    jsr Channels::ReadStatus::SetStatus
    cli
    clc
    bcc ReleaseLines
.endproc

;; Sends a secondary address after <Listen>, still under ATN, and then releases ATN.
;;
;; The secondary address picks the device's channel: $60 ORed with it for data, $E0 to close the channel and $F0 to
;; open it; the caller makes the byte.
;; In: A = the secondary address byte
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when the device does not answer
;; Keeps: X, Y
;; Also: SECND (KV20)
.proc SendSecondary
    sta BufferedCharacter
    jsr SendCommandByte
    ; Falls into ReleaseAtn.
.endproc

;; Releases ATN, ending the commands.
;; Out: A = VIA 1's port A without ATN, which the channel routines take as nonzero
;; Keeps: X, Y, carry
;; Also: SCATN (KV20, MTV)
.proc ReleaseAtn
    lda Via1PortA
    and #<~VIA1_SERIAL_ATN
    sta Via1PortA
    rts
.endproc

;; Sends a secondary address after <Talk>, still under ATN, and then makes the device the talker with
;; <TurnAround>.
;;
;; Commodore's listing and *Mapping the VIC* name it TKSA (KV20, MTV), the name of <KernalSendTalkSecondary>.
;; In: A = the secondary address byte, $60 ORed with the channel
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when the device does not answer
;; Keeps: X, Y
.proc SendTalkSecondary
    sta BufferedCharacter
    jsr SendCommandByte
    ; Falls into TurnAround.
.endproc

;; Makes the device that was told to talk the talker: the VIC-20 pulls DATA as a listener, releases ATN and CLK,
;; and waits for the device to pull CLK, which it holds as the talker.
;;
;; It has no timeout: it waits for as long as CLK stays high.
;; Out: carry = clear
;; Keeps: X, Y
;; Also: TKATN (KV20)
.proc TurnAround
    sei
    jsr PullData
    jsr ReleaseAtn
    jsr ReleaseClock

;; Waits for the talker to pull CLK low.
;; Also: TKATN1 (KV20)
WaitForTalker:
    jsr ReadLines
    bcs WaitForTalker
    cli
    rts
.endproc

;; Sends a byte to the listeners, one byte late: it keeps A in <BufferedCharacter> and sends the byte kept before,
;; so that the last byte, still kept at <Unlisten>, can go with EOI.
;;
;; Commodore's listing and *Mapping the VIC* name it CIOUT (KV20, MTV), the name of <KernalSendByte>.
;; In: A = the byte
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when the earlier byte is not taken
;; Keeps: A, X, Y
.proc SendByte
    bit CharacterWaiting
    bmi SendPrevious

    ; The first byte only waits.
    sec
    ror CharacterWaiting
    bne Buffer                      ; always: CharacterWaiting is $80 or more

;; Sends the byte already waiting.
;; Also: CI2 (KV20)
SendPrevious:
    pha
    jsr SendBufferedByte
    pla

;; Keeps A in <BufferedCharacter>, until the next byte or <Unlisten>.
;; Also: CI4 (KV20)
Buffer:
    sta BufferedCharacter
    clc
    rts
.endproc

;; Sends the UNTALK command, under ATN, and releases every line: the talker stops.
;;
;; It pulls CLK and ATN itself, then skips <Unlisten>'s first instruction to send its own command through
;; <Listen::SendCommand>.
;;
;; Commodore's listing and *Mapping the VIC* name it UNTLK (KV20, MTV), the name of <KernalUntalk>.
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when no device answers
;; Keeps: X, Y
.proc Untalk
    jsr PullClock
    lda Via1PortA
    ora #VIA1_SERIAL_ATN
    sta Via1PortA
    lda #COMMAND_UNTALK
    .byte OPCODE_BIT                ; skips Unlisten's LDA, so the command stays UNTALK
    .assert * = Unlisten, "Untalk's BIT must take Unlisten's first instruction as its operand."
.endproc

;; Sends the UNLISTEN command, under ATN, after the byte still waiting, with EOI, and releases every line: the
;; listeners stop.
;;
;; Commodore's listing and *Mapping the VIC* name it UNLSN (KV20, MTV), the name of <KernalUnlisten>.
;; Out: carry = clear
;; Errors: IoStatus = <STATUS_DEVICE_NOT_PRESENT> or both timeout bits ORed in when no device answers
;; Keeps: X, Y
.proc Unlisten
    lda #COMMAND_UNLISTEN
    jsr Listen::SendCommand
    ; Falls into ReleaseLines.
.endproc

;; Releases ATN, waits about 60 microseconds, and releases CLK and DATA, leaving the bus idle.
;; Keeps: X, Y, carry
;; Entry:
;;   ClockAndData = leaves ATN as it is: the wait, then CLK and DATA (<ReceiveByte> comes here)
;; Also: DLABYE (KV20)
.proc ReleaseLines
    jsr ReleaseAtn

;; The wait, then CLK and DATA released.
;; Also: DLADLH (KV20)
ClockAndData:
    txa
    ldx #RELEASE_DELAY

;; The wait.
;; Also: DLAD00 (KV20)
Delay:
    dex
    bne Delay
    tax
    jsr ReleaseClock
    jmp ReleaseData
.endproc

;; Receives a byte from the talker, with interrupts off meanwhile.
;;
;; It releases CLK, waits for the talker to release CLK (ready to send), and releases DATA (ready to take it). If the
;; talker then waits more than 256 counts of timer 2 before pulling CLK, the byte is the last: it ORs
;; <STATUS_END_OF_FILE> into <IoStatus>, acknowledges by pulsing DATA and waits again. Each bit is read when the
;; talker releases CLK, low bit first, and at the end it pulls DATA to accept the byte; if <IoStatus> has any bit set
;; by then, as after EOI, it releases CLK and DATA again.
;;
;; Commodore's listing and *Mapping the VIC* name it ACPTR (KV20, MTV), the name of <KernalReceiveByte>.
;; Out: A = the byte, carry = clear
;; Errors: IoStatus = <STATUS_READ_TIMEOUT> ORed in when the talker does not send after the EOI wait; the lines are
;;   then released and A is not a byte
;; Keeps: X, Y
.proc ReceiveByte
    sei
    lda #0
    sta BitCount                    ; 0 until the EOI wait has been seen
    jsr ReleaseClock

;; Waits for the talker to release CLK, then releases DATA: ready for the byte.
;; Also: ACP00A (KV20)
WaitForTalker:
    jsr ReadLines
    bcc WaitForTalker
    jsr ReleaseData

;; Times the talker's wait, 256 counts at least.
;; Also: EOIACP (KV20)
StartTimer:
    lda #EOI_TIMER_HIGH
    sta Via2Timer2High

;; Until the talker pulls CLK or the time is up.
;; Also: ACP00 (KV20)
WaitForClock:
    lda Via2InterruptFlags
    and #TIMER_2_DONE
    bne TimedOut
    jsr ReadLines
    bcs WaitForClock
    bcc ReadBits

;; Out of time a second time: a read timeout.
;; Also: ACP00B (KV20)
TimedOut:
    lda BitCount
    beq Eoi
    lda #STATUS_READ_TIMEOUT
    jmp BusError::SetStatus

;; Out of time the first time: EOI. Acknowledges it by pulsing DATA, and waits for the byte again.
;; Also: ACP00C (KV20)
Eoi:
    jsr PullData
    jsr ReleaseLines::ClockAndData
    lda #STATUS_END_OF_FILE
    jsr Channels::ReadStatus::SetStatus
    inc BitCount
    bne StartTimer                  ; always: BitCount is now 1

;; The talker has pulled CLK: eight bits follow.
;; Also: ACP01 (KV20)
ReadBits:
    lda #BITS_PER_BYTE
    sta BitCount

;; Each bit, as the talker releases CLK: DATA, into <ReceivedByte>'s top.
;; Also: ACP03 (KV20)
WaitClockHigh:
    lda Via1PortA
    cmp Via1PortA
    bne WaitClockHigh               ; until two reads agree
    lsr a                           ; carry = CLK
    bcc WaitClockHigh
    lsr a                           ; carry = DATA
    ror ReceivedByte

;; And CLK pulled again, before the next bit.
;; Also: ACP03A (KV20)
WaitClockLow:
    lda Via1PortA
    cmp Via1PortA
    bne WaitClockLow
    lsr a
    bcs WaitClockLow
    dec BitCount
    bne WaitClockHigh

    ; Accepts the byte; after EOI, or any other status, releases the lines again.
    jsr PullData
    lda IoStatus
    beq Done
    jsr ReleaseLines::ClockAndData

;; Returns the byte, with interrupts on.
;; Also: ACP04 (KV20)
Done:
    lda ReceivedByte
    cli
    clc
    rts
.endproc

;; Releases CLK, letting it go high unless a device holds it: clears <CLOCK_OUT>, so VIA 2's CA2 goes low and the
;; inverter stops pulling.
;; Keeps: X, Y, carry
;; Also: CLKHI (KV20)
.proc ReleaseClock
    lda Via2PeripheralControl
    and #<~CLOCK_OUT
    sta Via2PeripheralControl
    rts
.endproc

;; Pulls CLK low: sets <CLOCK_OUT>, so VIA 2's CA2 goes high and the inverter pulls the line.
;; Keeps: X, Y, carry
;; Also: CLKLO (KV20)
.proc PullClock
    lda Via2PeripheralControl
    ora #CLOCK_OUT
    sta Via2PeripheralControl
    rts
.endproc

;; Waits about a millisecond on VIA 2's timer 2.
;; Keeps: X, Y, carry
;; Also: W1MS (KV20)
.proc WaitOneMillisecond
    lda #MILLISECOND_TIMER_HIGH
    sta Via2Timer2High

;; Until the timer runs out.
;; Also: W1MS1 (KV20)
Wait:
    lda Via2InterruptFlags
    and #TIMER_2_DONE
    beq Wait
    rts
.endproc

.endscope
