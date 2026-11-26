; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE NMI AND THE IRQ ($FEA9-$FF89)

; The interrupts' second piece: the NMI, which VIA 1 raises for the RESTORE key and for RS-232's bits, RS-232's baud
; rate tables, and the IRQ's entry, which tells BRK from an IRQ. The IRQ's work, the jiffy routine, is the first
; piece, in Kernal.Editor.asm.

.scope Interrupts continued

;; VIA 1's CA1 interrupt bit, in <Via1InterruptFlags>: the RESTORE key, wired to CA1, was pressed.
RESTORE_INTERRUPT = %00000010

;; The cycles from the NMI's read of <Via1Timer2> to its write of <Via1Timer2High>, which reloads the timer: SBC
;; takes 2, then five instructions 4 each. The timer counts on meanwhile, so they are taken off the new count.
RELOAD_CYCLES = 22

;; The P that the IRQ or BRK pushed, seen as `StackedFlags,x` after <Irq> has pushed A, X and Y and taken S into X.
StackedFlags = $0104

;; The break flag, P's bit 4, in the P a BRK pushes; an IRQ pushes it clear.
BREAK_FLAG = %00010000

;; The target of the processor's NMI vector: turns IRQs off, so that the jiffy routine and the tape's interrupts
;; wait, and goes on through <NmiVector>, which a program may point at its own code.
;;
;; The NMI comes from VIA 1, for RESTORE and for RS-232. The default handler is <NmiHandler>.
;; Calls: <NmiVector>
;; Also: NMI (KV20, MTV)
.proc Nmi
    sei
    jmp (NmiVector)
.endproc

;; The default handler of <NmiVector>, which takes VIA 1's NMIs, the RESTORE key and RS-232's bits, and returns with
;; A, X and Y restored.
;;
;; RESTORE with a cartridge in goes to the cartridge's warm start (<CartridgeWarmStart>), and without one, if STOP is
;; down too, restores the system and warm-starts BASIC (<NmiHandler::Break>); RESTORE alone does nothing more. It
;; reads STOP through <Clock::Tick>, so each RESTORE also adds a jiffy to the clock.
;;
;; Of RS-232's interrupts, it takes one per NMI, in this order: timer 1 puts <Rs232::NextBit> on the send line and
;; works out the next (<Rs232::SendNextBit>); timer 2 samples the received bit, reloads the timer for the next bit's
;; middle and takes the bit (<Rs232::ReceiveBit>); CB1, a start bit's edge, starts timer 2 at half a bit's time from
;; <Rs232::BaudRates>. Meanwhile it turns all of VIA 1's interrupts off and then on again, which lets the VIA's NMI
;; line rise and fall again for one still pending, since the 6502 takes an NMI on the line's edge.
;;
;; If the NMI is from none of these, from an interrupt of VIA 1's the kernal never turns on (CA2, CB2 or the shift
;; register), it goes to <NmiHandler::Return> with the saved enable byte still on the stack, so the registers and the
;; return address come back one byte off, and it leaves every interrupt off. A baud rate of 0 in <Rs232::Control>
;; reads the two bytes before <Rs232::BaudRates>, the last two instructions of <NmiHandler::Return>, and one of 12
;; to 15 reads the code after the table.
;; Entry:
;;   Break = the default of <BreakVector>, and RESTORE with STOP: restores the RAM vectors, the I/O and the screen,
;;     and warm-starts BASIC through <BasicWarmStart>; it does not return
;;   Return = restores Y, X and A and returns from the interrupt; the tape's interrupt routines end here too
;; Also: NNMI (KV20)
.proc NmiHandler
    pha
    txa
    pha
    tya
    pha

    ; Only VIA 1's interrupts, those turned on.
    lda Via1InterruptFlags
    bpl ToReturn
    and Via1InterruptEnable
    tax
    and #RESTORE_INTERRUPT
    beq Rs232Bits

    ; RESTORE: a cartridge's warm start, if there is one.
    jsr Startup::FindCartridge
    bne StopKey
    jmp (CartridgeWarmStart)

;; RESTORE without a cartridge: only with STOP down does the warm start follow.
;; Also: NNMI19 (KV20)
StopKey:
    bit Via1PortAHandshake          ; clears CA1's flag
    jsr Clock::Tick
    jsr KernalTestStopKey
    bne ToReturn

;; The default of <BreakVector>, and RESTORE with STOP: restores the RAM vectors, the I/O and the screen, and
;; warm-starts BASIC.
;; Also: TIMB (KV20)
Break:
    jsr Startup::RestoreVectors
    jsr Startup::InitializeIo
    jsr Editor::Initialize
    jmp (BasicWarmStart)

;; RS-232's NMIs. The interrupts turned on are saved, to be turned on again, and all are turned off meanwhile; then
;; timer 1's, sending. (Named so as not to shadow the Rs232 scope.)
;; Also: NNMI20 (KV20)
Rs232Bits:
    lda Via1InterruptEnable
    ora #VIA_INTERRUPTS_ON
    pha
    lda #VIA_INTERRUPTS_ALL
    sta Via1InterruptEnable
    txa
    and #Rs232::SEND_INTERRUPT
    beq ReceiveTimer

    ; Timer 1: the bit goes out, the timer's flag is cleared, the interrupts back on, and the next bit worked out.
    lda #Rs232::SEND_LINE_LOW_CONTROL
    ora Rs232::NextBit
    sta Via1PeripheralControl
    lda Via1Timer1                  ; clears timer 1's flag
    pla
    sta Via1InterruptEnable
    jsr Rs232::SendNextBit

;; On to <NmiHandler::Return>.
;; Also: NMIRTN (KV20)
ToReturn:
    jmp Return

;; Timer 2: samples the received bit, and reloads the timer to reach the next bit's middle, one bit time from this
;; one, less the cycles the reload takes.
;; Also: NNMI30 (KV20)
ReceiveTimer:
    txa
    and #Rs232::RECEIVE_INTERRUPT
    beq StartBitEdge
    lda Via1PortB
    and #Rs232::RECEIVED_DATA
    sta Rs232::ReceivedBit
    lda Via1Timer2                  ; clears timer 2's flag
    sbc #RELOAD_CYCLES              ; 22, or 23 with carry clear as the interrupted code left it
    adc Rs232::BitTime
    sta Via1Timer2
    lda Via1Timer2High
    adc Rs232::BitTime+1
    sta Via1Timer2High
    pla
    sta Via1InterruptEnable
    jsr Rs232::ReceiveBit
    jmp Return

;; CB1's edge, a start bit: timer 2 is started to reach its middle.
;; Also: NNMI40 (KV20)
StartBitEdge:
    txa
    and #Rs232::START_BIT_INTERRUPT
    beq Return
    lda Rs232::Control
    and #Rs232::CONTROL_BAUD_RATE
    bne SetBaudTimer                ; to the next instruction either way

;; Half a bit's time from <Rs232::BaudRates>, for the baud rate's code; then timer 2's interrupt on, CB1's off, and
;; the bits to count.
;; Also: NNMI42 (KV20)
SetBaudTimer:
    asl a
    tax
    lda Rs232::BaudRates-2,x
    sta Via1Timer2
    lda Rs232::BaudRates-1,x
    sta Via1Timer2High
    lda Via1PortB                   ; clears CB1's flag
    pla
    ora #Rs232::RECEIVE_INTERRUPT
    and #<~Rs232::START_BIT_INTERRUPT
    sta Via1InterruptEnable
    ldx Rs232::WordBits
    stx Rs232::ReceiveBitCount

;; Restores Y, X and A, as the NMI handler or the kernal's IRQ entry pushed them, and returns from the interrupt.
;; The tape's interrupt routines end here too.
;; Also: NMIRTI (KV20), PREND (KV20)
Return:
    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.endscope

.scope Rs232 continued

;; Half a bit's time, in clock cycles, for each of the baud rates <Control> can ask for, 50 to 3600 (codes 1 to 11),
;; less <START_BIT_LATENCY>: where the NMI starts timer 2 at a start bit's edge, so that it samples the start bit at
;; its middle. <Open> works the bit time, <BitTime>, out from it.
;;
;; The clock differs with the television standard, 1022727 Hz on an NTSC VIC-20 and 1108405 Hz on a <PAL> one, so
;; each has its own table. Commodore's figures are rounded: the clock over twice the baud rate misses some by up
;; to 3, so each entry is written as Commodore's figure.
;; Also: BAUDO (KV20)
BaudRates:
.if PAL
    .word 11082 - START_BIT_LATENCY ; 50 baud
    .word 7388 - START_BIT_LATENCY  ; 75
    .word 5037 - START_BIT_LATENCY  ; 110
    .word 4117 - START_BIT_LATENCY  ; 134.5
    .word 3694 - START_BIT_LATENCY  ; 150
    .word 1847 - START_BIT_LATENCY  ; 300
    .word 924 - START_BIT_LATENCY   ; 600
    .word 462 - START_BIT_LATENCY   ; 1200
    .word 308 - START_BIT_LATENCY   ; 1800
    .word 231 - START_BIT_LATENCY   ; 2400
    .word 154 - START_BIT_LATENCY   ; 3600
.else
    .word 10230 - START_BIT_LATENCY ; 50 baud
    .word 6820 - START_BIT_LATENCY  ; 75
    .word 4650 - START_BIT_LATENCY  ; 110
    .word 3800 - START_BIT_LATENCY  ; 134.5
    .word 3410 - START_BIT_LATENCY  ; 150
    .word 1705 - START_BIT_LATENCY  ; 300
    .word 853 - START_BIT_LATENCY   ; 600
    .word 426 - START_BIT_LATENCY   ; 1200
    .word 284 - START_BIT_LATENCY   ; 1800
    .word 213 - START_BIT_LATENCY   ; 2400
    .word 142 - START_BIT_LATENCY   ; 3600
.endif
.endscope

.scope Interrupts continued

;; The target of the processor's IRQ vector, which BRK shares: saves A, X and Y, then goes on through <BreakVector>
;; for a BRK, or through <IrqVector> for an IRQ, telling them apart by the break flag in the P the processor pushed.
;;
;; The kernal's IRQ handlers end by restoring Y, X and A and returning from the interrupt, as
;; <NmiHandler::Return> does. The default IRQ handler is <Jiffy>, sixty times a second; the default for BRK is
;; <NmiHandler::Break>.
;; Calls: <BreakVector>, <IrqVector>
;; Also: PULS (KV20)
.proc Irq
    pha
    txa
    pha
    tya
    pha
    tsx
    lda StackedFlags,x
    and #BREAK_FLAG
    beq NotBreak
    jmp (BreakVector)

;; An IRQ: through <IrqVector>.
;; Also: PULS1 (KV20)
NotBreak:
    jmp (IrqVector)
.endproc

.endscope
