; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: moving the head
;;
;; <DiskII::MoveHead> steps the head from half-track to half-track, speeding up and slowing down with the
;; <DiskII::OnTimes> and <DiskII::OffTimes> delays (MsWait.asm). In DOS 3.3 it calls <DiskII::SetPhase> to turn the
;; stepper's phases on and off, and turns the last one off when it arrives; DOS 3.2's turns the phases on and off
;; itself and leaves the last one on, for <SeekHalfTrack> to turn off before the next seek. At $B9A0-$B9FC where DOS
;; 3.3 runs ($BA1E-$BA7E in DOS 3.2). docs/DiskII.md explains the stepper motor.
;;
;; The two versions' head movers differ in places, which <DOS32> chooses; SetPhase is DOS 3.3's alone.

; DiskII: the head's stepper.
.scope DiskII continued

;; The four stepper phases: half-track n lines the head up under phase n mod 4.
PHASE_MASK = 3

;; Moves the head from half-track CurrentTrack to half-track A, one half-track at a time.
;;
;; Each half-track lines the head up under one of the stepper's four phases, half-track n under phase n mod 4. A
;; step turns on the phase for the next half-track, waits <OnTimes>' time, turns off the phase it left and waits
;; <OffTimes>' time. Both tables are indexed by Y, the smaller of the half-tracks moved so far and those still to go
;; after this step, at most 11: the first steps and the last are slow and those between fast, so the head speeds up
;; and slows down. <Wait> adds the time spent waiting to <MotorTime>, the count RWTS uses to know when a motor it
;; started is up to speed.
;;
;; At the end, DOS 3.3's waits 25.6 milliseconds for the head to settle and falls into <SetPhase> to turn the last
;; phase off. DOS 3.2's waits 25.5 milliseconds and leaves the last phase on; <SeekHalfTrack> turns the phases off
;; before the next seek.
;; In:    A = the half-track to go to, X = slot * 16, CurrentTrack = the half-track the head is on
;; Out:   CurrentTrack = TargetHalfTrack = the new half-track; in DOS 3.3, all phases off (unless the head was
;;   already there)
;; Uses:  A, Y, TargetHalfTrack, MotorTime, MotorTimeHigh
;; Keeps: X
;; Also: SEEK (DOS33, DOS31)
.proc MoveHead

;; The number of half-tracks the head has moved so far, counted up from 0, which indexes <OnTimes> and <OffTimes>
;; while it is the smaller.
;; Also: TRKCNT (DOS33, DOS31)
StepsMoved = LowResBase

;; The half-track the head is leaving, whose phase goes off once the next one is on.
;; Also: PRIOR (DOS33, DOS31)
PriorHalfTrack = LowResBaseHigh

;; The slot times 16, kept while X indexes a phase's switch; the phase number times 2 added to it reaches
;; <Phase0Off> or <Phase0On> for that phase.
;; Also: SLOTTEMP (DOS33, DOS31)
SlotTimes16 = ScrollBaseHigh

.if DOS32
;; The wait at the end, in hundreds of microseconds, for the head to settle: DOS 3.2's.
SETTLE_TIME = $FF
.endif

.if DOS32
    sta TargetHalfTrack
    cmp CurrentTrack
    beq Return                      ; already there
    stx SlotTimes16
.else
    stx SlotTimes16
    sta TargetHalfTrack
    cmp CurrentTrack
    beq SetPhase::Return            ; already there
.endif
    lda #0
    sta StepsMoved

;; Takes the next step, or stops when the head has arrived.
;; Also: SEEK2 (DOS33, DOS31)
NextStep:
    lda CurrentTrack
    sta PriorHalfTrack              ; the half-track being left
    sec
    sbc TargetHalfTrack
    beq Settle                      ; arrived
    bcs Outward
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CurrentTrack
    bcc TakeSmaller                 ; always

;; Moving out, toward track 0: the half-tracks still to go after this step.
;; Also: OUT (DOS33, DOS31)
Outward:
    adc #$FE                        ; A - 1 (the carry is set)
    dec CurrentTrack

;; Takes the smaller of the half-tracks moved and those left.
;; Also: MINTST (DOS33, DOS31)
TakeSmaller:
    cmp StepsMoved
    bcc Limit
    lda StepsMoved

;; Keeps Y at the tables' last entry, 11, once the smaller is 12 or more. DOS 3.3 leaves Y as it was, already 11;
;; DOS 3.2 loads 11.
;; Also: MAXTST (DOS33, DOS31)
Limit:
    cmp #TIMES_COUNT
.if DOS32
    bcc SetIndex
    lda #TIMES_COUNT - 1
.else
    bcs Pulse                       ; 12 or more: Y as it was, 11
.endif

;; Takes the smaller as the tables' index. Nothing branches here in DOS 3.3; the 1978 code did.
;; Also: STEP (DOS33, DOS31)
SetIndex:
    tay
.if DOS32

    ; A phase's switches are Phase0Off + phase * 2 (off) and the address after it (on). The new half-track's
    ; phase on, then the old one's off.
    lda CurrentTrack
    and #PHASE_MASK
    asl a
    ora SlotTimes16
    tax
    lda Phase0On,x
    lda a:OnTimes,y
    jsr Wait
    lda PriorHalfTrack
    and #PHASE_MASK
    asl a
    ora SlotTimes16
    tax
    lda Phase0Off,x
    lda a:OffTimes,y
    jsr Wait
.else

;; Turns the new half-track's phase on, waits, turns the old one off and waits.
;; Also: STEP2 (DOS33)
Pulse:
    sec
    jsr SetPhase                    ; the new half-track's phase on
    lda a:OnTimes,y
    jsr Wait
    lda PriorHalfTrack
    clc
    jsr SetPhase::OfHalfTrack       ; the old one's off
    lda a:OffTimes,y
    jsr Wait
.endif
    inc StepsMoved
    bne NextStep                    ; always

;; Arrived: waits for the head to settle. In DOS 3.3, A = 0: 256 times 100 microseconds; then the phase goes off.
;; Also: SEEKEND (DOS33, DOS31)
Settle:
.if DOS32
    lda #SETTLE_TIME
    jsr Wait
    ldx SlotTimes16

;; Returns, also when the head is already on the half-track.
;; Also: SEEKRTS (DOS33), SEEKXIT (DOS31)
Return:
    rts
.else
    jsr Wait
    clc
    ; Falls into SetPhase.
.endif
.endproc

.if DOS32 = 0

;; Turns the stepper phase for half-track CurrentTrack on (carry set) or off (carry clear).
;;
;; The phase's switches are <Phase0Off> + phase * 2 (off) and the address after (on), so the phase number shifted
;; left with the carry coming in as bit 0 picks the switch.
;; In:    carry = set for on, clear for off, CurrentTrack = the half-track, MoveHead::SlotTimes16 = slot * 16
;; Out:   X = MoveHead::SlotTimes16
;; Uses:  A
;; Keeps: Y
;; Entry: OfHalfTrack = for half-track A rather than CurrentTrack
;; Also: SETPHASE (DOS33)
.proc SetPhase
    lda CurrentTrack

;; Turns the phase of half-track A on or off.
;; Also: CLRPHASE (DOS33)
OfHalfTrack:
    and #PHASE_MASK                 ; the phase
    rol a                           ; times 2, plus the carry: on or off
    ora MoveHead::SlotTimes16
    tax
    lda Phase0Off,x
    ldx MoveHead::SlotTimes16

;; Returns; <MoveHead> also returns here when the head is already on the half-track.
;; Also: SEEKRTS (DOS33), SEEKXIT (DOS31)
Return:
    rts
.endproc

.endif

.endscope
