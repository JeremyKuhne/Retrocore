; retrocore: style=strict
; COMMODORE 1541 DOS: THE SERIAL BUS ($E853-$EA6D)

; The serial bus as the drive sees it: the other end of the VIC-20 kernal's (Kernal.Serial.asm), so the routines that
; do the same step take its names. The computer talks to the drive in two ways. Under ATN every device listens, and the
; bytes are commands: LISTEN or TALK with a device number, UNLISTEN, UNTALK, and a secondary address that names a
; channel (<HandleAtn>). With ATN released the addressed device is the talker, which sends a channel's bytes
; (<Talk>), or the listener, which takes the bytes the computer sends (<Listen>); both clock them a bit at a time
; through <ReceiveByte> or Talk's own loop, checking ATN at every wait (<CheckAtn>). The lines are on VIA 1's port B:
; <ReleaseData>, <PullData>, <ReleaseClock>, <PullClock> and <ReadLines> work them. This first piece holds all of
; those; the speed routines of the 1541 and -05's patch are in pieces of their own at the ROM's end.

.scope Serial continued

; The bits and counts the bus code names.

;; The bits in a byte, each clocked on its own.
BITS_PER_BYTE = 8

;; <Via1InterruptFlags>' bit 6: VIA 1's timer 1 has run out.
TIMER_1_DONE = %01000000

;; Timer 1's high byte for the EOI wait: at least $0100 counts, 256 cycles, about a quarter of a millisecond, the low
;; byte being whatever was last latched. A talker that waits longer than that before it sends marks the byte as the last
;; (EOI, End Or Identify).
EOI_TIMER_HIGH = $01

;; The passes of the loop that holds DATA pulled to acknowledge an EOI, 5 cycles each.
EOI_PULSE_PASSES = 10

; The command bytes under ATN that are secondary addresses.

;; The bits that mark a command byte as a secondary address: $60 to $7F for a data channel, $E0 to $FF for a CLOSE or an
;; OPEN, whose high bit is set as well.
SECONDARY_MARK = $60

;; The secondary address's number, in its low nybble.
SECONDARY_NUMBER_MASK = $0F

;; The secondary address's kind, in its high nybble: $60 a data channel, <SECONDARY_CLOSE> or <SECONDARY_OPEN>.
SECONDARY_KIND_MASK = $F0

;; The kind that closes the channel.
SECONDARY_CLOSE = $E0

;; The kind that opens the channel; the bytes that follow are the file name.
SECONDARY_OPEN = $F0

;; The IRQ's ATN case, called by the controller's interrupt: reads <Via1PortAHandshake>, which clears CA1's flag, and
;; sets <AtnPending> for the idle loop to serve.
;; Keeps: X, Y
;; Also: ATNIRQ (D1541)
.proc AtnInterrupt
    lda Via1PortAHandshake
    lda #$01
    sta AtnPending
    rts
.endproc

;; Serves ATN: the computer is sending commands. It abandons what the drive was doing, restarting the stack, answers
;; that a device is here, and takes the command bytes: <UNLISTEN> and <UNTALK>, the drive's own listen and talk
;; addresses, and a secondary address, which for a CLOSE ($Ex) closes the channel at once. When ATN ends it goes on as
;; it was told: <Listen>, or <Talk>, or, with nothing addressed, to <BusError>.
;;
;; It is reached by a jump, from the idle loop when <AtnPending> is set and from <CheckAtn> when a wait finds ATN
;; pulled, and never returns: every way out ends in <Idle::Loop>, or in this routine again at the next ATN.
;; Entry:
;;   AtnEnded = ATN is over, which <CheckAtn> finds in the middle of a receive while the commands are being taken
;; Also: ATNSRV (D1541)
.proc HandleAtn
    ; Abandons the work in hand: no ATN pending, no one addressed, the stack restarted and no EOI seen.
    sei
    lda #$00
    sta AtnPending
    sta Listening
    sta Talking
    ldx #Controller::OVERFLOW_SIZE
    txs
    lda #$80
    sta MoreBytes
    sta AtnMode

    ; Answers: CLK released, DATA pulled to say a device is here, and ATNA set, which gives the program the control of
    ; DATA that the hardware keeps while ATN is pulled and ATNA is clear.
    jsr ReleaseClock
    jsr PullData
    lda Via1PortB
    ora #ATN_ACKNOWLEDGE
    sta Via1PortB

;; Waits for the computer to release CLK, which says that it is sending; or for ATN to end.
;; Also: ATNS15 (D1541)
WaitClockReleased:
    lda Via1PortB
    bpl AtnEnded
    and #CLOCK_IN
    bne WaitClockReleased

;; Takes a command byte, sent under ATN, with <ReceiveByte>.
;; Also: ATN30 (D1541)
NextCommand:
    jsr ReceiveByte
    cmp #UNLISTEN
    bne NotUnlisten
    lda #$00
    sta Listening
    beq WaitAtnEnd

;; Is it <UNTALK>, which stops the talker?
;; Also: ATN35 (D1541)
NotUnlisten:
    cmp #UNTALK
    bne NotUntalk
    lda #$00
    sta Talking
    beq WaitAtnEnd

;; Is it the drive's talk address? Then it is to talk, and no longer to listen.
;; Also: ATN40 (D1541)
NotUntalk:
    cmp TalkAddress
    bne NotTalk
    lda #$01
    sta Talking
    lda #$00
    sta Listening
    beq StillAtn

;; Is it the drive's listen address? Then it is to listen, and no longer to talk.
;; Also: ATN45 (D1541)
NotTalk:
    cmp ListenAddress
    bne NotListen
    lda #$01
    sta Listening
    lda #$00
    sta Talking
    beq StillAtn

;; Is it a secondary address? Any byte with <SECONDARY_MARK>'s bits is: $60 to $7F or $E0 to $FF. Its number is kept as
;; <SecondaryAddress> and the whole byte as <SecondaryCommand>, and a CLOSE closes the channel now, with interrupts on.
;; Any other secondary address is the last command byte, so the wait for ATN's end follows. The listing warns that the
;; close may not return in time for that wait.
;; Also: ATN50 (D1541)
NotListen:
    tax
    and #SECONDARY_MARK
    cmp #SECONDARY_MARK
    bne NotForUs
    txa
    sta SecondaryCommand
    and #SECONDARY_NUMBER_MASK
    sta SecondaryAddress
    lda SecondaryCommand
    and #SECONDARY_KIND_MASK
    cmp #SECONDARY_CLOSE
    bne WaitAtnEnd
    cli
    jsr Files::Close
    sei

;; Is ATN still pulled? Then another command byte follows.
;; Also: ATN95 (D1541)
StillAtn:
    bit Via1PortB
    bmi NextCommand

;; ATN has ended: the commands are done, so the drive does what it was told. It leaves ATN mode and releases ATNA, which
;; returns the control of DATA to the hardware, then goes to <Listen> if it was addressed to listen. <Listen> never
;; returns, so the jump after it is not reached.
;; Also: ATNS20 (D1541)
AtnEnded:
    lda #$00
    sta AtnMode
    lda Via1PortB
    and #$FF - ATN_ACKNOWLEDGE
    sta Via1PortB
    lda Listening
    beq NotListening
    jsr Listen
    jmp Idle::Loop

;; Was it addressed to talk? Then it releases DATA, pulls CLK, which tells the computer that it is not yet sending, and
;; becomes the talker, <Talk>, which returns when the channel has nothing more to send.
;; Also: ATN100 (D1541)
NotListening:
    lda Talking
    beq ToBusError
    jsr ReleaseData
    jsr PullClock
    jsr Talk

;; Nothing addressed, or the talker has finished: releases the lines and goes idle, through <BusError>.
;; Also: ATN110 (D1541)
ToBusError:
    jmp BusError

;; A byte that is not for this drive: no listen, talk or secondary address of its own. Only ATNA stays set, so DATA is
;; released, and with no other device pulling it the computer finds that no one answers.
;; Also: ATN120 (D1541)
NotForUs:
    lda #ATN_ACKNOWLEDGE
    sta Via1PortB

;; Waits for ATN to end, with no more command bytes taken.
;; Also: ATN122 (D1541)
WaitAtnEnd:
    bit Via1PortB
    bpl AtnEnded
    bmi WaitAtnEnd
.endproc

;; The drive as talker, once it is addressed to talk: sends the bytes of the channel that the secondary address names,
;; each with the next one got from the file, and the last with EOI, until ATN comes. It returns when that secondary
;; address has no channel ready to talk or the channel has no more to send; ATN, or a bus error, leaves for <HandleAtn>
;; or <BusError> instead.
;;
;; Interrupts are off, except across <Files::NextByte>, which can wait for a disk job that the controller's interrupt
;; runs.
;; In: SecondaryAddress = the channel's secondary address, as <Files::FindReadChannel> takes it
;; Also: TALK (D1541)
.proc Talk
    sei
    jsr Files::FindReadChannel
    bcs NotReady

;; Each byte: is the channel ready to talk, its <ChannelStatus> bit 7 set?
;; Also: TALK1 (D1541)
NextByte:
    ldx Channel
    lda ChannelStatus,x
    bmi ReadyToSend

;; Nothing to send: returns.
;; Also: NOTLK (D1541)
NotReady:
    rts

;; Starts a byte. CLK is pulled; it reads DATA, and releases CLK, which tells the listeners that the talker is ready to
;; send. If DATA was already released then, it goes to the EOI handshake whatever the channel says: the listing's fix,
;; added to correct a verify error.
;; Also: TLK05 (D1541)
ReadyToSend:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    php
    jsr ReleaseClock
    plp
    beq EoiReleased

;; Waits for the listeners to release DATA, which says that they are ready for the byte. If <CHANNEL_MORE> is set in the
;; channel's <ChannelStatus>, more bytes follow and this one goes without EOI, at <WaitReady>; if it is clear this is
;; the last byte, and the EOI handshake follows.
;; Also: TALK2 (D1541)
WaitListener:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    bne WaitListener
    ldx Channel
    lda ChannelStatus,x
    and #CHANNEL_MORE
    bne WaitReady

;; The EOI: by holding CLK released for longer than the listener waits, the talker marks the byte as the last. The
;; listener answers by pulsing DATA, so this waits first for DATA to be released...
;; Also: TLK02 (D1541)
EoiReleased:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    bne EoiReleased

;; ...and then for it to be pulled again, which is the acknowledgement.
;; Also: TLK03 (D1541)
EoiAcknowledged:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    beq EoiAcknowledged

;; Pulls CLK, and waits for the listeners to release DATA again: they are ready for the first bit.
;; Also: NOEOI (D1541)
WaitReady:
    jsr PullClock
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    bne WaitReady
    lda #BITS_PER_BYTE
    sta BitCount

;; Each bit, low bit first. DATA must be released at this point: if a listener holds it, the bus is in error and it goes
;; to <BusError>. The bit goes out on DATA, released for a 1, from the channel's byte, which is shifted down through the
;; carry.
;; Also: ISR01 (D1541)
NextBit:
    jsr ReadLines
    and #DATA_IN
    bne ToBusError
    ldx Channel
    lda ChannelByte,x
    ror
    sta ChannelByte,x
    bcs BitOne
    jsr PullData
    bne ClockBit

;; A 1: DATA released.
;; Also: ISRHI (D1541)
BitOne:
    jsr ReleaseData

;; Clocks the bit: releases CLK, which says that DATA now holds it.
;;
;; The 1541 then holds it for 40 microseconds more (`SlowDown`) when <SerialNoDelay> is 0, the VIC-20's speed, and not
;; when it is nonzero, the 64's; and pulls CLK and releases DATA again (`PullClockAndReleaseData`). The 1540 has neither
;; the speed test nor the delay.
;; Also: ISRCLK (D1541)
ClockBit:
    jsr ReleaseClock
.if DRIVE_1540
    ; The 1540's one speed: four NOPs, then CLK pulled and DATA released.
    nop
    nop
    nop
    nop
    jsr PullClock
    jsr ReleaseData
.else
    ; The 1541 tests the speed: with <SerialNoDelay> nonzero it goes straight on to the end of the bit.
    lda SerialNoDelay
    bne EndBit
    jsr SlowDown

;; Ends the bit with <PullClockAndReleaseData>: CLK pulled and DATA released, so the next bit can be set up.
;; Also: ISR03 (D1541)
EndBit:
    jsr PullClockAndReleaseData
.endif
    dec BitCount
    bne NextBit

;; The byte is out. Waits for a listener to pull DATA, which accepts it; then gets the file's next byte, with interrupts
;; on, and sends it from the top.
;; Also: ISR04 (D1541)
WaitAccepted:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    beq WaitAccepted
    cli
    jsr Files::NextByte
    sei
    jmp NextByte

;; A bus error: on to <BusError>.
;; Also: FRMERX (D1541)
ToBusError:
    jmp BusError
.endproc

;; Releases DATA: clears its output bit in <Via1PortB>, so that the line is pulled up.
;; Out: A = the port B value written
;; Keeps: X, Y
;; Also: DATHI (D1541)
.proc ReleaseData
    lda Via1PortB
    and #$FF - DATA_OUT
    sta Via1PortB
    rts
.endproc

;; Pulls DATA low: sets its output bit in <Via1PortB>.
;; Out: A = the port B value written, zero = clear, which <Talk> takes as an always branch
;; Keeps: X, Y
;; Also: DATLOW (D1541)
.proc PullData
    lda Via1PortB
    ora #DATA_OUT
    sta Via1PortB
    rts
.endproc

;; Pulls CLK low: sets its output bit in <Via1PortB>.
;; Out: A = the port B value written, zero = clear
;; Keeps: X, Y
;; Also: CLKLOW (D1541)
.proc PullClock
    lda Via1PortB
    ora #CLOCK_OUT
    sta Via1PortB
    rts
.endproc

;; Releases CLK: clears its output bit in <Via1PortB>, so that the line is pulled up.
;; Out: A = the port B value written
;; Keeps: X, Y
;; Also: CLKHI (D1541)
.proc ReleaseClock
    lda Via1PortB
    and #$FF - CLOCK_OUT
    sta Via1PortB
    rts
.endproc

;; Reads the lines steadily: reads <Via1PortB> until two reads in a row agree. A bit is set while its line is pulled:
;; <DATA_IN>, <CLOCK_IN> and, in bit 7, ATN.
;; Out: A = the port B value
;; Keeps: X, Y
;; Also: DEBNC (D1541)
.proc ReadLines
    lda Via1PortB
    cmp Via1PortB
    bne ReadLines
    rts
.endproc

;; Receives a byte from the talker, as the computer's own receive does from its end: for each of eight bits waits for
;; CLK released, which says that DATA holds the bit, and shifts it in, low bit first. A talker that holds CLK back for
;; more than about 256 microseconds before the first bit marks the byte as the last (EOI), which is acknowledged by
;; pulsing DATA and clears <MoreBytes>. Every wait calls <CheckAtn>, so an ATN that comes (or ends, in ATN mode) leaves
;; this routine for good.
;; Out: A = the byte, MoreBytes = 0 when the byte was sent with EOI (it is not set here)
;; Keeps: Y
;; Entry:
;;   WaitForClock = Waits for CLK to be pulled, or for the timer to run out, which is an EOI (`ReceiveBytePatch` returns
;;     here)
;; Also: ACPTR (D1541)
.proc ReceiveByte
    lda #BITS_PER_BYTE
    sta BitCount

;; Waits for the talker to release CLK, which says that it is ready to send; answers by releasing DATA, and starts timer
;; 1 for the wait for the first bit, with <EOI_TIMER_HIGH>. -05 and -06 start it in a patch (`ReceiveBytePatch`).
;; Also: ACP00A (D1541)
WaitForTalker:
    jsr CheckAtn
    jsr ReadLines
    and #CLOCK_IN
    bne WaitForTalker
    jsr ReleaseData
    lda #EOI_TIMER_HIGH
.if LATE_PATCHES
    ; -05 and -06: the patch first waits for DATA to read released, so that every listener is ready, then starts the
    ; timer (loading the same value again) and returns to WaitForClock.
    jmp ReceiveBytePatch
.else
    ; Before -05: the timer starts at once.
    sta Via1Timer1High
.endif

;; Waits for CLK to be pulled, which starts the first bit, unless timer 1 runs out first: the talker took too long, and
;; this is an EOI.
;; Also: ACP00 (D1541)
WaitForClock:
    jsr CheckAtn
    lda Via1InterruptFlags
    and #TIMER_1_DONE
    bne Eoi
    jsr ReadLines
    and #CLOCK_IN
    beq WaitForClock
    bne WaitClockHigh

;; An EOI. Acknowledges it by pulling DATA...
;; Also: ACP00B (D1541)
Eoi:
    jsr PullData
    ldx #EOI_PULSE_PASSES

;; ...for a short count...
;; Also: ACP02 (D1541)
EoiPulse:
    dex
    bne EoiPulse
    jsr ReleaseData

;; ...then releases it, waits for the talker to pull CLK, and records the EOI in <MoreBytes>, which is 0 when the byte
;; is the last.
;; Also: ACP02A (D1541)
WaitClockAfterEoi:
    jsr CheckAtn
    jsr ReadLines
    and #CLOCK_IN
    beq WaitClockAfterEoi
    lda #$00
    sta MoreBytes

;; Each bit: waits for the talker to release CLK, which says that DATA now holds the bit, and shifts it into <DataByte>,
;; from the top, so that after eight the first bit is the lowest. The first bit comes here from <WaitForClock>, or after
;; an EOI; the others from <WaitClockLow>.
;;
;; In -01 and the 1540 the CLK wait and the DATA read are two reads. From -02 on one read gives both: the DATA bit goes
;; into the carry as the CLK bit is tested, so the bit is the one that was there when CLK was released.
;; Also: ACP01 (D1541), ACP03 (D1541)
WaitClockHigh:
    lda Via1PortB
.if SINGLE_BIT_READ
    ; Port B's bit 0 is DATA, pulled for a 0, so it is inverted and shifted into the carry, and bit 2, CLK, moves to
    ; bit 1 to be tested, while the line is pulled. The three NOPs are padding, filling what the two-read form needs.
    eor #DATA_IN
    lsr
    and #CLOCK_IN >> 1
    bne WaitClockHigh
    nop
    nop
    nop
.else
    ; Two reads: CLK released first, then DATA on its own, inverted and moved into the carry.
    and #CLOCK_IN
    bne WaitClockHigh
    lda Via1PortB
    eor #DATA_IN
    lsr
.endif
    ror DataByte

;; Waits for the talker to pull CLK again, which ends the bit; after the eighth, accepts the byte by pulling DATA and
;; returns it.
;; Also: ACP03A (D1541)
WaitClockLow:
    jsr CheckAtn
    jsr ReadLines
    and #CLOCK_IN
    beq WaitClockLow
    dec BitCount
    bne WaitClockHigh
    jsr PullData
    lda DataByte
    rts
.endproc

;; The drive as listener, once it is addressed to listen: receives each byte the computer sends, and hands it to
;; <Files::AcceptByte>, for the channel the secondary address names. If there is no channel to listen to, and the
;; secondary address is not an OPEN (<SECONDARY_OPEN>), whose bytes are the name of the file, it is a bus error.
;;
;; It never returns: it loops for each byte, and leaves through <BusError> or, when ATN comes, <HandleAtn>.
;; In: SecondaryAddress = the channel's secondary address, SecondaryCommand = the whole byte
;; Also: LISTEN (D1541)
.proc Listen
    sei
    jsr Files::FindWriteChannel
    bcs NotWriting
    lda ChannelStatus,x
    ror
    bcs NextByte

;; No write channel, or not ready to listen (<ChannelStatus> bit 0 clear): is it an OPEN?
;; Also: LSN15 (D1541)
NotWriting:
    lda SecondaryCommand
    and #SECONDARY_KIND_MASK
    cmp #SECONDARY_OPEN
    beq NextByte
    jmp BusError

;; Receives a byte, and, with interrupts on, hands it to <Files::AcceptByte>; then starts again with the next, which
;; looks for the channel again.
;; Also: LSN30 (D1541)
NextByte:
    jsr ReceiveByte
    cli
    jsr Files::AcceptByte
    jmp Listen
.endproc

;; How the drive gives up on the bus: releases DATA, CLK and ATNA, by clearing <Via1PortB>, and goes to the idle loop.
;; The computer sees the lines released and takes it as a device error. The stack is not restarted; the next ATN does
;; that. It is reached by a jump, or a call that does not return, from the talker, the listener and the error channel's
;; routines.
;; Also: ILERR (D1541), FRMERR (D1541), ITERR (D1541)
.proc BusError
    lda #$00
    sta Via1PortB
    jmp Idle::Loop

    ; Not reached: the listing's ATNLOW, a jump to HandleAtn that nothing uses. It keeps its bytes.
    jmp HandleAtn
.endproc

;; Checks ATN, for every wait in the bus code, and acts on a change at once. In ATN mode (<AtnMode>), taking the
;; commands, it returns while ATN is pulled and goes to <HandleAtn::AtnEnded> when it ends; otherwise it returns while
;; ATN is released and goes to <HandleAtn> when it is pulled, which drops the caller.
;; Keeps: X, Y
;; Also: TSTATN (D1541)
.proc CheckAtn
    lda AtnMode
    beq NotAtnMode
    lda Via1PortB
    bpl ToAtnEnded

;; Nothing changed: returns.
;; Also: TSTRTN (D1541)
Done:
    rts

;; Not in ATN mode: is ATN pulled? Then the computer is sending commands.
;; Also: TSTA50 (D1541)
NotAtnMode:
    lda Via1PortB
    bpl Done
    jmp HandleAtn

;; ATN has ended: on to <HandleAtn::AtnEnded>.
;; Also: TATN20 (D1541)
ToAtnEnded:
    jmp HandleAtn::AtnEnded
.endproc
.endscope
