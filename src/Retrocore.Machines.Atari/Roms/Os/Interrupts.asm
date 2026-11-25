;; INTERRUPTS AND THE VERTICAL BLANK ($E6D5-$E943)
;;
;; INTINV's interrupt set-up; the IRQ handler, which finds the interrupt's cause among POKEY's IRQST bits, the PIA's
;; two interrupt lines and BRK, and jumps through its page-two vector; the NMI handler, which tells a display list
;; interrupt, SYSTEM RESET and the vertical blank apart; the vertical blank itself (SYSVBV), with its exit (XITVBV);
;; and SETVBV, which sets a timer or a vertical blank vector safely. Maintained by hand; it assembles byte-identically
;; to rev. A, rev. B and the PAL OS.
;;
;; Rev. B rewrote the IRQ handler as a scan of a table, which gave the BREAK key a vector of its own (BRKKY) and
;; fixed rev. A's timer 4, which never reached VTIMR4, and its BRK test, which read the wrong flags. Its vertical blank
;; enables IRQs later, and its SETVBV waits for the end of a scan line instead of turning the NMIs off.

; ---------------------------------------------------------------------------------------------------------------------
; Constants for the interrupt handlers
; ---------------------------------------------------------------------------------------------------------------------


; Where rev. B's IRQ handler starts its scan of <IRQ_SOURCE_BITS>, and the one source it takes only when enabled.

IRQ_SCAN_FIRST = 6                  ;; serial output needed; serial input ready, entry 7, is tested before the scan
IRQ_SERIAL_DONE_ENTRY = 5           ;; serial output finished, which stays pending while nothing is being sent

IRQ_JUMP = $028C                    ;; rev. B's IRQ jump vector, and its place for A while it tests for BRK


; The 6502's status register, as an interrupt pushes it.

CPU_FLAG_BREAK = %00010000          ;; the break flag: set when BRK, not an IRQ, pushed it
CPU_FLAG_INTERRUPT = %00000100      ;; the interrupt flag: set while IRQs are masked

VBLANK_STACKED_P = $0104            ;; with X = S after the NMI handler's pushes, the interrupted code's P is here,X

; The PIA's control registers, as INTINV sets them: CA2 and CB2 outputs held high (the cassette motor off and the
; serial bus's command line not asserted), and the CA1 and CB1 interrupts disabled.

PIA_SELECT_DIRECTION = $38          ;; bit 2 clear: PORTA or PORTB reaches the port's data direction register
PIA_SELECT_PORT = $3C               ;; bit 2 set: PORTA or PORTB reaches the port itself

; The vertical blank's settings.

ATTRACT_NORMAL_MASK = $FE           ;; DRKMSK without attract mode: the colours at full brightness
ATTRACT_DIM_MASK = $F6              ;; DRKMSK in attract mode: bit 3 of each colour's brightness cleared
SKSTAT_KEY_HELD = %00000100         ;; SKSTAT's bit that is 0 while a key is held
KEY_REPEAT_PERIOD = 6               ;; vertical blanks between auto-repeated keys
CONSOL_SPEAKER = %00001000          ;; CONSOL's speaker bit, written set to leave the speaker at rest
SETVBV_DELAY = 5                    ;; rev. B's delay loop's count after WSYNC, to carry SETVBV past the NMI's point
SETVBV_REV_A = $E912                ;; rev. A's SET_VBLANK_VECTOR, where rev. B keeps a JMP to its own

;; Sets up the interrupt hardware: enables the vertical blank NMI (and no display list interrupts) and makes both of
;; the PIA's ports inputs, with the cassette motor off, the serial bus's command line high and the PIA's interrupts
;; disabled.
;;
;; INTINV jumps here, at power-up and SYSTEM RESET.
;; Uses: A
;; Keeps: X, Y
;; See: <INTINV>
INIT_INTERRUPTS:
    lda #NMI_VBLANK
    sta NMIEN
    lda #PIA_SELECT_DIRECTION
    sta PACTL
    sta PBCTL
    lda #$00                        ; every line an input, for the joysticks
    sta PORTA
    sta PORTB
    lda #PIA_SELECT_PORT
    sta PACTL
    sta PBCTL
    rts

;; Where the 6502's IRQ vector points: every IRQ, and BRK, goes on through VIMIRQ, normally to <IRQ_HANDLER>.
IRQ_ENTRY:
    jmp (VIMIRQ)

.if VERSION = VERSION_B

;; The POKEY interrupts the IRQ handler scans, by IRQST bit, from the last entry down; <IRQ_SOURCE_VECTORS> holds
;; each one's vector.
;;
;; The scan starts at entry 6, since <IRQ_HANDLER> tests serial input ready first, so entry 7 is never read. Rev. B
;; only: rev. A tests each source in turn.
;; See: <IRQ_HANDLER>, <IRQ_SOURCE_VECTORS>
IRQ_SOURCE_BITS:
    .byte IRQ_BREAK                 ; 0
    .byte IRQ_KEY                   ; 1
    .byte IRQ_TIMER_4               ; 2
    .byte IRQ_TIMER_2               ; 3
    .byte IRQ_TIMER_1               ; 4
    .byte IRQ_SERIAL_DONE           ; 5
    .byte IRQ_SERIAL_OUTPUT         ; 6
    .byte IRQ_SERIAL_INPUT          ; 7, not scanned

;; The page-two vector of each interrupt in <IRQ_SOURCE_BITS>, as an offset from VDSLST.
;;
;; BREAK goes through BRKKY, rev. B's vector for it, which points at <BREAK_KEY_HANDLER>.
;; See: <IRQ_HANDLER>, <IRQ_SOURCE_BITS>
IRQ_SOURCE_VECTORS:
    .byte BRKKY - VDSLST
    .byte VKEYBD - VDSLST
    .byte VTIMR4 - VDSLST
    .byte VTIMR2 - VDSLST
    .byte VTIMR1 - VDSLST
    .byte VSEROC - VDSLST
    .byte VSEROR - VDSLST
    .byte VSERIN - VDSLST

;; The OS's IRQ handler, VIMIRQ's default: finds one pending interrupt, clears it, and jumps through its vector.
;;
;; Serial input ready comes first, as the most urgent. Then the other POKEY interrupts in <IRQ_SOURCE_BITS> from
;; serial output needed down to BREAK, where serial output finished counts only while POKMSK enables it; a POKEY
;; interrupt is cleared by writing IRQEN with its bit clear, then POKMSK again. Then the PIA's CA1 (the serial bus's
;; proceed line, to VPRCED) and CB1 (its interrupt line, to VINTER), each cleared by reading its port. Last, a BRK
;; goes to VBREAK. Each vector is entered with the interrupted A on the stack, so its handler ends PLA, RTI; with
;; nothing found, the handler returns at once. One interrupt is handled each time, so several pending ones each
;; raise the IRQ again.
;; Calls: VSERIN, VSEROR, VSEROC, VTIMR1, VTIMR2, VTIMR4, VKEYBD, BRKKY, VPRCED, VINTER, VBREAK
;; See: <IRQ_ENTRY>, <IRQ_SOURCE_BITS>, <IRQ_SOURCE_VECTORS>
IRQ_HANDLER:
    pha
    lda IRQST
    and #IRQ_SERIAL_INPUT
    bne IRQ_HANDLER_SCAN            ; not pending
    lda #IRQ_SERIAL_INPUT ^ $FF     ; clear it
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VSERIN)
IRQ_HANDLER_SCAN:
    txa
    pha
    ldx #IRQ_SCAN_FIRST
IRQ_HANDLER_LOOP:
    lda IRQ_SOURCE_BITS,x
    cpx #IRQ_SERIAL_DONE_ENTRY
    bne IRQ_HANDLER_TEST
    and POKMSK                      ; serial output finished only counts when enabled
    beq IRQ_HANDLER_NEXT
IRQ_HANDLER_TEST:
    bit IRQST
    beq IRQ_HANDLER_FOUND           ; its bit is 0: pending
IRQ_HANDLER_NEXT:
    dex
    bpl IRQ_HANDLER_LOOP
    jmp IRQ_HANDLER_PIA
IRQ_HANDLER_FOUND:
    eor #$FF                        ; clear just this interrupt
    sta IRQEN
    lda POKMSK
    sta IRQEN
    lda IRQ_SOURCE_VECTORS,x
    tax
    lda VDSLST,x
    sta IRQ_JUMP
    lda VDSLST+1,x
    sta IRQ_JUMP+1
    pla
    tax
    jmp (IRQ_JUMP)

.else

;; The OS's IRQ handler, VIMIRQ's default: finds one pending interrupt, clears it, and jumps through its vector.
;;
;; Rev. A tests the POKEY interrupts one at a time, in this order: serial output needed, serial input ready, serial
;; output finished (only while POKMSK enables it), timers 1, 2 and 4, a key and BREAK. Each is cleared by writing
;; IRQEN with its bit clear, then POKMSK again. Timer 4 is cleared but never reaches VTIMR4: the handler goes on
;; testing. BREAK has no vector: the handler goes straight on into <BREAK_KEY_HANDLER>. Then the PIA's CA1 (to
;; VPRCED) and CB1 (to VINTER), and last a BRK, to VBREAK; but the BRK test looks at a copy of P pushed by PHP, whose
;; break bit is always set, so any IRQ nothing else claimed goes to VBREAK too. Each vector is entered with the
;; interrupted A on the stack, so its handler ends PLA, RTI.
;; Calls: VSEROR, VSERIN, VSEROC, VTIMR1, VTIMR2, VKEYBD, VPRCED, VINTER, VBREAK
;; See: <IRQ_ENTRY>, <BREAK_KEY_HANDLER>
IRQ_HANDLER:
    pha
    lda #IRQ_SERIAL_OUTPUT
    bit IRQST
    bne IRQ_HANDLER_INPUT           ; not pending
    lda #IRQ_SERIAL_OUTPUT ^ $FF    ; clear it
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VSEROR)
IRQ_HANDLER_INPUT:
    lda #IRQ_SERIAL_INPUT
    bit IRQST
    bne IRQ_HANDLER_DONE
    lda #IRQ_SERIAL_INPUT ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VSERIN)
IRQ_HANDLER_DONE:
    lda #IRQ_SERIAL_DONE
    bit POKMSK
    beq IRQ_HANDLER_TIMER_1         ; serial output finished only counts when enabled
    bit IRQST
    bne IRQ_HANDLER_TIMER_1
    lda #IRQ_SERIAL_DONE ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VSEROC)
IRQ_HANDLER_TIMER_1:
    lda IRQST
    ror a                           ; carry = timer 1's bit
    bcs IRQ_HANDLER_TIMER_2
    lda #IRQ_TIMER_1 ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VTIMR1)
IRQ_HANDLER_TIMER_2:
    ror a
    bcs IRQ_HANDLER_TIMER_4
    lda #IRQ_TIMER_2 ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VTIMR2)
IRQ_HANDLER_TIMER_4:
    ror a
    bcs IRQ_HANDLER_KEY
    lda #IRQ_TIMER_4 ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN                       ; and no jump through VTIMR4: on to the key
IRQ_HANDLER_KEY:
    bit IRQST                       ; overflow = the key's bit, negative = BREAK's
    bvs IRQ_HANDLER_BREAK
    lda #IRQ_KEY ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN
    jmp (VKEYBD)
IRQ_HANDLER_BREAK:
    bmi IRQ_HANDLER_PIA
    lda #IRQ_BREAK ^ $FF
    sta IRQEN
    lda POKMSK
    sta IRQEN

.endif

;; The BREAK key's handler: notes the key in BRKKEY and clears the start/stop flag, the cursor's inhibit flag and
;; attract mode.
;;
;; In rev. B it is BRKKY's default, which <IRQ_HANDLER> jumps through; rev. A has no BRKKY, and its IRQ handler goes
;; straight on into it. The IRQ handler leaves the interrupted A on the stack, which this pulls.
;; Out: BRKKEY = 0
;; Uses: SSFLAG, CRSINH, ATRACT
;; See: <IRQ_HANDLER>
BREAK_KEY_HANDLER:
    lda #$00
    sta BRKKEY
    sta SSFLAG
    sta CRSINH
    sta ATRACT
    pla
    rti

IRQ_HANDLER_PIA:
.if VERSION = VERSION_B
    pla                             ; X back, as the scan found nothing
    tax
.endif
    bit PACTL
    bpl IRQ_HANDLER_PORT_B          ; no CA1 interrupt
    lda PORTA                       ; reading the port clears it
    jmp (VPRCED)
IRQ_HANDLER_PORT_B:
    bit PBCTL
    bpl IRQ_HANDLER_BRK             ; no CB1 interrupt
    lda PORTB
    jmp (VINTER)
IRQ_HANDLER_BRK:
.if VERSION = VERSION_B
    pla                             ; hold A while looking at the stacked P
    sta IRQ_JUMP
    pla
    pha
    and #CPU_FLAG_BREAK
    beq IRQ_HANDLER_RETURN
    lda IRQ_JUMP
    pha
    jmp (VBREAK)
IRQ_HANDLER_RETURN:
    lda IRQ_JUMP                    ; push A back, to share the PLA, RTI below
    pha
.else
    php                             ; rev. A: this P, not the stacked one, and PHP always sets the break bit
    pla
    and #CPU_FLAG_BREAK
    beq IGNORE_IRQ                  ; never taken
    jmp (VBREAK)
.endif

;; Returns from an IRQ, pulling the A that the IRQ handler pushed: the default of VPRCED, VINTER, VBREAK, VTIMR1,
;; VTIMR2 and VTIMR4.
IGNORE_IRQ:
    pla

;; Returns from an NMI at once: VDSLST's default.
IGNORE_NMI:
    rti

;; The 6502's NMI handler: jumps through VDSLST for a display list interrupt, to WARMSV for SYSTEM RESET, and
;; otherwise, for the vertical blank, pushes A, X and Y and jumps through VVBLKI.
;; Calls: VDSLST, VVBLKI
;; See: <SYSTEM_VBLANK>, <WARMSV>
NMI_HANDLER:
    bit NMIST
    bpl NMI_HANDLER_NOT_DLI
    jmp (VDSLST)
NMI_HANDLER_NOT_DLI:
    pha
    lda NMIST
    and #NMI_RESET
    beq NMI_HANDLER_VBLANK
    jmp WARMSV
NMI_HANDLER_VBLANK:
    txa
    pha
    tya
    pha
    sta NMIRES
    jmp (VVBLKI)

;; The OS's vertical blank, VVBLKI's default, which SYSVBV jumps to: counts the clock, runs attract mode and the
;; timers, copies the shadow registers to the hardware and back, repeats keys, and reads the controllers.
;;
;; Stage 1 always runs: RTCLOK counts up, ATRACT counts up each 256 frames, DRKMSK and COLRSH follow attract mode,
;; and system timer 1 counts down, calling through CDTMA1 at zero. Stage 2 is skipped, straight to <EXIT_VBLANK>,
;; during a critical section (CRITIC nonzero) or when the interrupted code had IRQs masked. It reads the light pen,
;; writes the display list, DMA, priority, colour (with attract mode), character set and character control shadows
;; to the hardware, re-enables IRQs, counts system timer 2 (calling through CDTMA2) and timers 3-5 (clearing their
;; flags), counts down the keyboard's debounce, auto-repeats a held key into CH, and reads the joysticks, the paddles
;; and their triggers into their shadows. It ends through VVBLKD, whose default is <EXIT_VBLANK>.
;;
;; Rev. A enables IRQs as soon as stage 2 starts; rev. B waits until the colours, so the light pen, display list, DMA
;; and priority are copied with IRQs still masked. <NMI_HANDLER> enters with A, X and Y pushed, which <EXIT_VBLANK>
;; pulls.
;; Calls: CDTMA1, CDTMA2, VVBLKD
;; See: <SYSVBV>, <XITVBV>, <SET_VBLANK_VECTOR>
SYSTEM_VBLANK:
    inc RTCLOK+2
    bne SYSTEM_VBLANK_ATTRACT
    inc ATRACT
    inc RTCLOK+1
    bne SYSTEM_VBLANK_ATTRACT
    inc RTCLOK
SYSTEM_VBLANK_ATTRACT:
    lda #ATTRACT_NORMAL_MASK
    ldx #$00
    ldy ATRACT
    bpl SYSTEM_VBLANK_DIM
    sta ATRACT                      ; $FE: keeps ATRACT negative, so it can't count past $FF to 0
    ldx RTCLOK+1                    ; the colours drift as the clock counts
    lda #ATTRACT_DIM_MASK
SYSTEM_VBLANK_DIM:
    sta DRKMSK
    stx COLRSH
    ldx #0                          ; timer 1
    jsr COUNT_DOWN_TIMER
    bne SYSTEM_VBLANK_CRITICAL
    jsr CALL_TIMER_1
SYSTEM_VBLANK_CRITICAL:
    lda CRITIC
    bne SYSTEM_VBLANK_SKIP
    tsx
    lda VBLANK_STACKED_P,x
    and #CPU_FLAG_INTERRUPT
    beq SYSTEM_VBLANK_STAGE_2
SYSTEM_VBLANK_SKIP:
    jmp EXIT_VBLANK
SYSTEM_VBLANK_STAGE_2:
.if VERSION != VERSION_B
    cli                             ; IRQs may come from here on
.endif
    lda PENV
    sta LPENV
    lda PENH
    sta LPENH
    lda SDLSTH
    sta DLISTH
    lda SDLSTL
    sta DLISTL
    lda SDMCTL
    sta DMACTL
    lda GPRIOR
    sta PRIOR
    .assert COLBK - COLPM0 = CONSOL_SPEAKER, "The colour loop starts at the speaker bit."
.if VERSION = VERSION_B
    ldx #CONSOL_SPEAKER             ; also the last colour's index, COLBK's
    stx CONSOL
.else
    lda #CONSOL_SPEAKER
    sta CONSOL
    ldx #COLBK - COLPM0
.endif
SYSTEM_VBLANK_COLOURS:
.if VERSION = VERSION_B
    cli                             ; IRQs may come from here on (repeated each time round)
.endif
    lda PCOLR0,x
    eor COLRSH
    and DRKMSK
    sta COLPM0,x
    dex
    bpl SYSTEM_VBLANK_COLOURS
    lda CHBAS
    sta CHBASE
    lda CHACT
    sta CHACTL
    ldx #CDTMV2 - CDTMV1
    jsr COUNT_DOWN_TIMER
    bne SYSTEM_VBLANK_TIMERS
    jsr CALL_TIMER_2
SYSTEM_VBLANK_TIMERS:
    ldx #CDTMV2 - CDTMV1
SYSTEM_VBLANK_TIMER_LOOP:
    inx                             ; timers 3, 4 and 5
    inx
    lda CDTMV1,x
    ora CDTMV1+1,x
    beq SYSTEM_VBLANK_TIMER_NEXT    ; not running
    jsr COUNT_DOWN_TIMER
    sta CDTMF3 - (CDTMV3 - CDTMV1),x ; the timer's flag: 0 at zero, $FF while it counts
SYSTEM_VBLANK_TIMER_NEXT:
    cpx #CDTMV5 - CDTMV1
    bne SYSTEM_VBLANK_TIMER_LOOP
    lda SKSTAT
    and #SKSTAT_KEY_HELD
    beq SYSTEM_VBLANK_REPEAT        ; the debounce counts only while no key is held
    lda KEYDEL
    beq SYSTEM_VBLANK_REPEAT
    dec KEYDEL
SYSTEM_VBLANK_REPEAT:
    lda SRTIMR
    beq SYSTEM_VBLANK_STICKS
    lda SKSTAT
    and #SKSTAT_KEY_HELD
    bne SYSTEM_VBLANK_STOP_REPEAT   ; the key was let go
    dec SRTIMR
    bne SYSTEM_VBLANK_STICKS
    lda #KEY_REPEAT_PERIOD
    sta SRTIMR
    lda KBCODE                      ; the key again
    sta CH
SYSTEM_VBLANK_STICKS:
    ldy #PORTB - PORTA
    ldx #STICK3 - STICK0
SYSTEM_VBLANK_STICK_LOOP:
    lda PORTA,y                     ; the high nibble is the odd joystick, the low nibble the even
    lsr A
    lsr A
    lsr A
    lsr A
    sta STICK0,x
    dex
    lda PORTA,y
    and #$0F
    sta STICK0,x
    dex
    dey
    bpl SYSTEM_VBLANK_STICK_LOOP
    ldx #STRIG3 - STRIG0
SYSTEM_VBLANK_TRIGGER_LOOP:
    lda TRIG0,x
    sta STRIG0,x
    lda POT0,x
    sta PADDL0,x
    lda POT4,x
    sta PADDL4,x
    dex
    bpl SYSTEM_VBLANK_TRIGGER_LOOP
    sta POTGO                       ; start reading the paddles again
    ldx #PTRIG6 - PTRIG0
    ldy #STICK3 - STICK0
SYSTEM_VBLANK_PADDLE_LOOP:
    lda STICK0,y                    ; a paddle pair's triggers are its port's left and right lines
    lsr A
    lsr A
    lsr A                           ; carry = bit 2, the even paddle's; A = bit 3, the odd paddle's
    sta PTRIG1,x
    lda #$00
    rol A
    sta PTRIG0,x
    dex
    dex
    dey
    bpl SYSTEM_VBLANK_PADDLE_LOOP
    jmp (VVBLKD)
SYSTEM_VBLANK_STOP_REPEAT:
    lda #$00
    sta SRTIMR
    beq SYSTEM_VBLANK_STICKS

;; Calls system timer 1's routine, through CDTMA1, when the timer reaches zero.
;; See: <SYSTEM_VBLANK>
CALL_TIMER_1:
    jmp (CDTMA1)

;; Calls system timer 2's routine, through CDTMA2, when the timer reaches zero.
;; See: <SYSTEM_VBLANK>
CALL_TIMER_2:
    jmp (CDTMA2)

;; Counts a system timer down by one, unless it is already zero.
;; In: X = the timer's offset from CDTMV1 (0, 2, 4, 6 or 8)
;; Out: A = 0 when the timer reached zero on this call, $FF otherwise, zero = set when it reached zero
;; Uses: Y
;; Keeps: X
;; See: <SYSTEM_VBLANK>
COUNT_DOWN_TIMER:
    ldy CDTMV1,x
    bne COUNT_DOWN_TIMER_LOW
    ldy CDTMV1+1,x
    beq COUNT_DOWN_TIMER_RUNNING    ; already zero
    dec CDTMV1+1,x
COUNT_DOWN_TIMER_LOW:
    dec CDTMV1,x
    bne COUNT_DOWN_TIMER_RUNNING
    ldy CDTMV1+1,x
    bne COUNT_DOWN_TIMER_RUNNING
    lda #$00
    rts
COUNT_DOWN_TIMER_RUNNING:
    lda #$FF
    rts

.if VERSION = VERSION_B

;; Sets a system timer or a vertical blank vector, which SETVBV jumps to, so that no vertical blank sees half of it.
;;
;; It waits for the end of a scan line with WSYNC, then a few cycles more, past the point in the next line where ANTIC
;; raises the vertical blank's NMI, before storing both bytes. Item n's word is at VIMIRQ + 2n. Rev. A turned the
;; NMIs off instead, and had to run a vertical blank it had missed itself; rev. B's wait never stops the NMIs, so no
;; vertical blank or display list interrupt is lost, and it is shorter.
;; In: A = the item: 1-5 for CDTMV1-CDTMV5, 6 for VVBLKI, 7 for VVBLKD, X = the value's high byte, Y = its low byte
;; Out: X = A times two
;; Uses: A, INTEMP
;; Keeps: Y
;; See: <SETVBV>, <SYSTEM_VBLANK>
SET_VBLANK_VECTOR:
    asl A
    sta INTEMP
    txa
    ldx #SETVBV_DELAY
    sta WSYNC
SET_VBLANK_VECTOR_DELAY:
    dex
    bne SET_VBLANK_VECTOR_DELAY
    ldx INTEMP
    sta VIMIRQ+1,x
    tya
    sta VIMIRQ,x
    rts

.else

;; Sets a system timer or a vertical blank vector, which SETVBV jumps to, so that no vertical blank sees half of it.
;;
;; Rev. A turns the NMIs off through NMIEN while it stores both bytes, then turns the vertical blank's back on (and
;; leaves display list interrupts off). ANTIC raises the NMI only as the vertical blank starts, so if one began
;; meanwhile (NMIST says so) it runs the vertical blank itself: it pushes a return to its RTS and P, as an interrupt
;; would, and three stand-ins for the A, X and Y the NMI handler pushes, and jumps through VVBLKI. Item n's word is
;; at VIMIRQ + 2n.
;; In: A = the item: 1-5 for CDTMV1-CDTMV5, 6 for VVBLKI, 7 for VVBLKD, X = the value's high byte, Y = its low byte
;; Out: X = A times two; but after a missed vertical blank, A, X and Y = $3D, the low byte of the return
;; Uses: A, X, Y, INTEMP
;; Calls: VVBLKI
;; See: <SETVBV>, <SYSTEM_VBLANK>
SET_VBLANK_VECTOR:
    asl A
    sta INTEMP
    lda #$00
    sta NMIEN                       ; no NMIs while both bytes change
    txa
    ldx INTEMP
    sta VIMIRQ+1,x
    tya
    sta VIMIRQ,x
    lda #NMI_VBLANK
    sta NMIEN
    bit NMIST
    bvc SET_VBLANK_VECTOR_DONE      ; no vertical blank began meanwhile
    lda #>SET_VBLANK_VECTOR_DONE    ; the return, for the vertical blank's RTI
    pha
    lda #<SET_VBLANK_VECTOR_DONE
    pha
    php
    pha                             ; for the Y, X and A that EXIT_VBLANK pulls
    pha
    pha
    jmp (VVBLKI)
SET_VBLANK_VECTOR_DONE:
    rts

.endif

;; Ends the vertical blank, which XITVBV jumps to and VVBLKD's default: pulls the Y, X and A that the NMI handler
;; pushed and returns from the interrupt.
;; See: <XITVBV>, <SYSTEM_VBLANK>
EXIT_VBLANK:
    pla
    tay
    pla
    tax
    pla
    rti

.if VERSION = VERSION_B
    ; Not reached: font bytes like the ROM's own letters A-H (the end of A, then B to G, then the start of H), with
    ; B's middle three bytes replaced by a JMP to SET_VBLANK_VECTOR at rev. A's SET_VBLANK_VECTOR, so that a program
    ; that called rev. A's routine there, rather than through SETVBV, still sets its vector.
    .byte $66, $66, $7E, $66, $00, $00, $7C
    .assert * = SETVBV_REV_A, "Rev. B's JMP is at rev. A's SET_VBLANK_VECTOR."
    jmp SET_VBLANK_VECTOR
    .byte $66, $7C, $00, $00, $3C, $66
    .byte $60, $60, $66, $3C, $00, $00, $78, $6C, $66, $66, $6C, $78, $00, $00, $7E, $60
    .byte $7C, $60, $60, $7E, $00, $00, $7E, $60, $7C, $60, $60, $60, $00, $00, $3E, $60
    .byte $60, $6E, $66, $3E, $00, $00, $66, $66, $7E
.else
    .assert SET_VBLANK_VECTOR = SETVBV_REV_A, "Rev. A's SET_VBLANK_VECTOR is at $E912."
.endif
    .assert * = $E944, "Every build's interrupt handlers end at $E944, where SIO starts."
