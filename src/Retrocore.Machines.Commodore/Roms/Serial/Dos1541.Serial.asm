; retrocore: style=strict
; COMMODORE 1541 DOS: THE SERIAL BUS ($E853-$EA6D)
.scope Serial continued

;; The IRQ's ATN case: reads VIA 1's port A to clear CA1's flag, and sets ATNPND for the idle loop.
;; Also: ATNIRQ (D1541)
.proc AtnInterrupt
    lda Via1PortAHandshake
    lda #$01
    sta AtnPending
    rts
.endproc

;; ATN: abandons what it was doing (the stack reset), releases CLK, pulls DATA and sets ATNA so the gate stops pulling
;; it, and takes the command bytes: <UNLISTEN>, <UNTALK>, its talk or listen address, a secondary address (CLOSE for
;; $Ex).
;; Entry:
;;   AtnEnded = ATN over (<CheckAtn> comes here)
;; Also: ATNSRV (D1541)
.proc HandleAtn
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
    jsr ReleaseClock
    jsr PullData
    lda Via1PortB
    ora #ATN_ACKNOWLEDGE
    sta Via1PortB

;; Until the computer releases CLK, or ATN ends.
;; Also: ATNS15 (D1541)
WaitClockReleased:
    lda Via1PortB
    bpl AtnEnded
    and #CLOCK_IN
    bne WaitClockReleased

;; A command byte, by <ReceiveByte>.
;; Also: ATN30 (D1541)
NextCommand:
    jsr ReceiveByte
    cmp #UNLISTEN
    bne NotUnlisten
    lda #$00
    sta Listening
    beq WaitAtnEnd

;; <UNTALK>?
;; Also: ATN35 (D1541)
NotUnlisten:
    cmp #UNTALK
    bne NotUntalk
    lda #$00
    sta Talking
    beq WaitAtnEnd

;; TLKADR: TLKACT set, LSNACT clear.
;; Also: ATN40 (D1541)
NotUntalk:
    cmp TalkAddress
    bne NotTalk
    lda #$01
    sta Talking
    lda #$00
    sta Listening
    beq StillAtn

;; LSNADR: LSNACT set, TLKACT clear.
;; Also: ATN45 (D1541)
NotTalk:
    cmp ListenAddress
    bne NotListen
    lda #$01
    sta Listening
    lda #$00
    sta Talking
    beq StillAtn

;; A secondary address ($60-$7F, $E0-$FF): ORGSA = it, SA its low nybble; $Ex closes the file.
;; Also: ATN50 (D1541)
NotListen:
    tax
    and #$60
    cmp #$60
    bne NotForUs
    txa
    sta SecondaryCommand
    and #$0F
    sta SecondaryAddress
    lda SecondaryCommand
    and #$F0
    cmp #$E0
    bne WaitAtnEnd
    cli
    jsr Files::Close
    sei

;; ATN still on: the next command.
;; Also: ATN95 (D1541)
StillAtn:
    bit Via1PortB
    bmi NextCommand

;; ATN over (<CheckAtn> comes here): ATNMOD and ATNA clear, then <Listen>, <Talk>, or the lines released.
;; Also: ATNS20 (D1541)
AtnEnded:
    lda #$00
    sta AtnMode
    lda Via1PortB
    and #$EF
    sta Via1PortB
    lda Listening
    beq NotListening
    jsr Listen
    jmp Idle::Loop

;; Talking: releases DATA, pulls CLK, and <Talk>.
;; Also: ATN100 (D1541)
NotListening:
    lda Talking
    beq ToBusError
    jsr ReleaseData
    jsr PullClock
    jsr Talk

;; On to <BusError>.
;; Also: ATN110 (D1541)
ToBusError:
    jmp BusError

;; Not a command for this drive: only ATNA set, so DATA is released and the computer can see no device answers.
;; Also: ATN120 (D1541)
NotForUs:
    lda #$10
    sta Via1PortB

;; Until ATN ends.
;; Also: ATN122 (D1541)
WaitAtnEnd:
    bit Via1PortB
    bpl AtnEnded
    bmi WaitAtnEnd
.endproc

;; The drive as talker: sends the read channel's bytes, each with GET's next, the last with EOI, until ATN; returns at
;; once if SA has no channel ready to talk.
;; Also: TALK (D1541)
.proc Talk
    sei
    jsr Files::FindReadChannel
    bcs NotReady

;; Each byte: CHNRDY bit 7, ready to talk?
;; Also: TALK1 (D1541)
NextByte:
    ldx Channel
    lda ChannelStatus,x
    bmi ReadyToSend

;; Returns.
;; Also: NOTLK (D1541)
NotReady:
    rts

;; Releases CLK; if DATA is already released then, it takes the EOI handshake whatever the channel says (the listing's
;; verify-error fix).
;; Also: TLK05 (D1541)
ReadyToSend:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    php
    jsr ReleaseClock
    plp
    beq EoiReleased

;; Until the listener releases DATA; EOI if CHNRDY's EOI bit is clear.
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

;; EOI: waits for DATA released...
;; Also: TLK02 (D1541)
EoiReleased:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    bne EoiReleased

;; ...and pulled again: the listener has seen the EOI.
;; Also: TLK03 (D1541)
EoiAcknowledged:
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    beq EoiAcknowledged

;; Pulls CLK and waits for DATA released: ready for the byte.
;; Also: NOEOI (D1541)
WaitReady:
    jsr PullClock
    jsr CheckAtn
    jsr ReadLines
    and #DATA_IN
    bne WaitReady
    lda #$08
    sta BitCount

;; Each bit, low first: DATA must be released, or <BusError>.
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

;; Releases CLK for the bit, waits 40 microseconds more (`SlowDown`) when <SerialNoDelay> is 0, the VIC-20's speed, then
;; pulls CLK and releases DATA (the 1540 differs, Q7).
;; Also: ISRCLK (D1541)
ClockBit:
    jsr ReleaseClock
.if DRIVE_1540
    nop
    nop
    nop
    nop
    jsr PullClock
    jsr ReleaseData
.else
    lda SerialNoDelay
    bne EndBit
    jsr SlowDown

;; Ends the bit: <PullClockAndReleaseData>, so the listener sees CLK pulled with the bit on DATA.
;; Also: ISR03 (D1541)
EndBit:
    jsr PullClockAndReleaseData
.endif
    dec BitCount
    bne NextBit

;; Until the listener pulls DATA: the byte is taken; then GET's next byte.
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

;; On to <BusError>.
;; Also: FRMERX (D1541)
ToBusError:
    jmp BusError
.endproc

;; Lets DATA go high: DATOUT clear in VIA 1's port B.
;; Also: DATHI (D1541)
.proc ReleaseData
    lda Via1PortB
    and #$FD
    sta Via1PortB
    rts
.endproc

;; Pulls DATA low: DATOUT set.
;; Also: DATLOW (D1541)
.proc PullData
    lda Via1PortB
    ora #DATA_OUT
    sta Via1PortB
    rts
.endproc

;; Pulls CLK low: CLKOUT set.
;; Also: CLKLOW (D1541)
.proc PullClock
    lda Via1PortB
    ora #CLOCK_OUT
    sta Via1PortB
    rts
.endproc

;; Lets CLK go high: CLKOUT clear.
;; Also: CLKHI (D1541)
.proc ReleaseClock
    lda Via1PortB
    and #$F7
    sta Via1PortB
    rts
.endproc

;; A = VIA 1's port B, read until two reads agree (DATIN, CLKIN and ATN set while their lines are pulled).
;; Also: DEBNC (D1541)
.proc ReadLines
    lda Via1PortB
    cmp Via1PortB
    bne ReadLines
    rts
.endproc

;; A byte from the talker, as the kernal's ACPTR: A = it; EOIFLG = 0 at EOI. Checks ATN at each wait.
;; Entry:
;;   WaitForClock = Until CLK is pulled, or VIA 1's timer 1 runs out, which is EOI
;; Also: ACPTR (D1541)
.proc ReceiveByte
    lda #$08
    sta BitCount

;; Until the talker releases CLK; then releases DATA and goes to `ReceiveBytePatch` to start the 256 microseconds timer.
;; Also: ACP00A (D1541)
WaitForTalker:
    jsr CheckAtn
    jsr ReadLines
    and #CLOCK_IN
    bne WaitForTalker
    jsr ReleaseData
    lda #$01
.if LATE_PATCHES
    jmp ReceiveBytePatch
.else
    sta Via1Timer1High
.endif

;; Until CLK is pulled, or VIA 1's timer 1 runs out, which is EOI.
;; Also: ACP00 (D1541)
WaitForClock:
    jsr CheckAtn
    lda Via1InterruptFlags
    and #$40
    bne Eoi
    jsr ReadLines
    and #CLOCK_IN
    beq WaitForClock
    bne WaitClockHigh

;; EOI: acknowledges it by pulsing DATA...
;; Also: ACP00B (D1541)
Eoi:
    jsr PullData
    ldx #$0A

;; ...for a short count...
;; Also: ACP02 (D1541)
EoiPulse:
    dex
    bne EoiPulse
    jsr ReleaseData

;; ...waits for CLK pulled, and EOIFLG = 0.
;; Also: ACP02A (D1541)
WaitClockAfterEoi:
    jsr CheckAtn
    jsr ReadLines
    and #CLOCK_IN
    beq WaitClockAfterEoi
    lda #$00
    sta MoreBytes

;; The same address as ACP03: one local, with ACP01 in its Also: (Q2).
;; Also: ACP01 (D1541), ACP03 (D1541)
WaitClockHigh:
    lda Via1PortB
.if SINGLE_BIT_READ
    eor #$01
    lsr
    and #$02
    bne WaitClockHigh
    nop
    nop
    nop
.else
    and #$04
    bne WaitClockHigh
    lda Via1PortB
    eor #$01
    lsr
.endif
    ror DataByte

;; And CLK pulled again; after eight, pulls DATA to accept the byte.
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

;; The drive as listener: PUTs each byte received into SA's write channel until ATN; with no channel ready to listen,
;; and not an OPEN ($Fx), <BusError>.
;; Also: LISTEN (D1541)
.proc Listen
    sei
    jsr Files::FindWriteChannel
    bcs NotWriting
    lda ChannelStatus,x
    ror
    bcs NextByte

;; No write channel: an OPEN's name?
;; Also: LSN15 (D1541)
NotWriting:
    lda SecondaryCommand
    and #$F0
    cmp #$F0
    beq NextByte
    jmp BusError

;; A byte, PUT.
;; Also: LSN30 (D1541)
NextByte:
    jsr ReceiveByte
    cli
    jsr Files::AcceptByte
    jmp Listen
.endproc

;; Releases DATA, CLK and ATNA (VIA 1's port B = 0) and goes to the idle loop.
;; Also: ILERR (D1541), FRMERR (D1541), ITERR (D1541)
.proc BusError
    lda #$00
    sta Via1PortB
    jmp Idle::Loop
    jmp HandleAtn
.endproc

;; In ATN mode (ATNMOD), returns while ATN is on and goes to AtnEnded when it ends; otherwise returns unless ATN is on,
;; then <HandleAtn>.
;; Also: TSTATN (D1541)
.proc CheckAtn
    lda AtnMode
    beq NotAtnMode
    lda Via1PortB
    bpl ToAtnEnded

;; Returns.
;; Also: TSTRTN (D1541)
Done:
    rts

;; Not in ATN mode: has ATN come?
;; Also: TSTA50 (D1541)
NotAtnMode:
    lda Via1PortB
    bpl Done
    jmp HandleAtn

;; On to <HandleAtn::AtnEnded>.
;; Also: TATN20 (D1541)
ToAtnEnded:
    jmp HandleAtn::AtnEnded
.endproc
.endscope
