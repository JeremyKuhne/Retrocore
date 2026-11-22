; retrocore: style=strict
;; DOS 3.2 RWTS: the head mover, the wait, and the nibble-to-value table ($BA1E-$BAFF where DOS runs)
;;
;; <DiskII::MoveHead> steps the head from half-track to half-track, speeding up and slowing down with the
;; <DiskII::OnTimes> and <DiskII::OffTimes> delays, and <DiskII::Wait> is the delay they use, which also counts
;; time for the motor's start. After them comes the used end of <DiskII::ReadTranslate>, the table that turns a
;; nibble back into its five-bit value. docs/DiskII.md explains the stepper motor.

; DiskII: the head mover, the wait and their tables, and the nibble-to-value table.
.scope DiskII continued

;; The four stepper phases: half-track n lines the head up under phase n mod 4.
PHASE_MASK = 3

;; Moves the head from half-track <CurrentTrack> to half-track A, one half-track at a time.
;;
;; At $BA1E where DOS runs. A step turns on the phase for the next half-track, waits <OnTimes>' time, turns off
;; the phase it left and waits <OffTimes>' time. Both tables are indexed by Y, the smaller of the half-tracks moved
;; so far and those still to go after this step, at most 11: the first steps and the last are slow and those
;; between fast, so the head speeds up and slows down. At the end it waits 25.5 milliseconds for the head to
;; settle, leaving the last phase on; <SeekHalfTrack> turns the phases off before the next seek. <Wait> adds the
;; time spent waiting to <MotorTime>, the count RWTS uses to know when a motor it started is up to speed.
;; In: A = the half-track to go to, X = slot * 16, CurrentTrack = the half-track the head is on
;; Out: CurrentTrack = TargetHalfTrack = the new half-track
;; Keeps: X
;; Also: SEEK (DOS33, DOS31)
.proc MoveHead

;; The number of half-tracks the head has moved so far.
;; Also: TRKCNT (DOS33, DOS31)
StepsMoved = LowResBase

;; The half-track the head is leaving, whose phase goes off once the next one is on.
;; Also: PRIOR (DOS33, DOS31)
PriorHalfTrack = LowResBaseHigh

;; The slot times 16, kept while X indexes a phase's switch.
;; Also: SLOTTEMP (DOS33, DOS31)
SlotTimes16 = ScrollBaseHigh

;; The last index into <OnTimes> and <OffTimes>, which every step from there to 11 before the end uses.
LAST_STEP = 11

;; The wait at the end, in hundreds of microseconds, for the head to settle.
SETTLE_TIME = $FF

    sta TargetHalfTrack
    cmp CurrentTrack
    beq Return                      ; already there
    stx SlotTimes16
    lda #0
    sta StepsMoved
;; One step: which way, and how far from the start and the end.
;; Also: SEEK2 (DOS33, DOS31)
NextStep:
    lda CurrentTrack
    sta PriorHalfTrack
    sec
    sbc TargetHalfTrack
    beq Settle                      ; arrived
    bcs Outward
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CurrentTrack
    bcc TakeSmaller                 ; always
;; Moving out, toward track 0.
;; Also: OUT (DOS33, DOS31)
Outward:
    adc #$FE                        ; out: A - 1 (the carry is set), half-tracks still to go after this step
    dec CurrentTrack
;; The smaller of the half-tracks moved and those left.
;; Also: MINTST (DOS33, DOS31)
TakeSmaller:
    cmp StepsMoved
    bcc Limit
    lda StepsMoved
;; At most <LAST_STEP>.
;; Also: MAXTST (DOS33, DOS31)
Limit:
    cmp #LAST_STEP + 1
    bcc SetIndex
    lda #LAST_STEP
;; Also: STEP (DOS33, DOS31)
SetIndex:
    tay

    ; A phase's switches are Phase0Off + phase * 2 (off) and the address after it (on). The new half-track's
    ; phase on, then the old one's off.
    lda CurrentTrack
    and #PHASE_MASK
    asl a
    ora SlotTimes16
    tax
    lda Phase0On,x
    lda OnTimes,y
    jsr Wait
    lda PriorHalfTrack
    and #PHASE_MASK
    asl a
    ora SlotTimes16
    tax
    lda Phase0Off,x
    lda OffTimes,y
    jsr Wait
    inc StepsMoved
    bne NextStep                    ; always
;; Arrived: waits for the head to settle.
;; Also: SEEKEND (DOS33, DOS31)
Settle:
    lda #SETTLE_TIME
    jsr Wait
    ldx SlotTimes16
;; Also: SEEKRTS (DOS33), SEEKXIT (DOS31)
Return:
    rts
.endproc

;; Waits about A times 100 microseconds (A = 0 waits 256 times), adding A to the motor-on count, <MotorTime>.
;;
;; At $BA7F where DOS runs. Each pass of the outer loop takes 101 cycles, about 100 microseconds at the Apple II's
;; 1.02 MHz. The relocator's first range of RWTS's code ends at its last byte, the `rts`: <Wait::LowLevelCodeEnd>.
;; In: A = the time, in hundreds of microseconds
;; Out: A = 0, X = 0, carry = set
;; Keeps: Y
;; Also: MSWAIT (DOS33, DOS31)
.proc Wait

;; The passes of the inner loop, 17, which with the rest of the outer loop make 101 cycles.
INNER_PASSES = $11

;; One pass of 100 microseconds: the inner loop, then a step of the motor-on count and of A.
NextPass:
    ldx #INNER_PASSES
;; The inner loop: 17 passes, 84 cycles.
;; Also: MSW1 (DOS33, DOS31)
Inner:
    dex
    bne Inner
    inc MotorTime
    bne Count
    inc MotorTimeHigh
;; Counts A down.
;; Also: MSW2 (DOS33, DOS31)
Count:
    sec
    sbc #1
    bne NextPass
;; The end of the relocator's first range of RWTS's code, <LowLevelCodeStart> to here: the range leaves out this
;; last `rts`, which has no address to adjust. At $BA8F where DOS runs.
;; Also: AEC1 (DOS33, DOS31)
LowLevelCodeEnd:
    rts
.endproc

;; How long to wait after turning a phase on, in hundreds of microseconds, by the step's index: how far into or
;; before the end of a seek the step is (<MoveHead>).
;;
;; At $BA90 where DOS runs; the 1978 values.
;; Also: ONTABLE (DOS33, DOS31)
OnTimes:
    .byte 1, $30, $28
    .byte $24, $20, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C

;; How long to wait after turning the old phase off, by the same index.
;; Also: OFFTABLE (DOS33, DOS31)
OffTimes:
    .byte $70, $2C, $26
    .byte $22, $1F, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C

;; The table <ReadDataField> uses to turn a nibble back into its five-bit value, shifted left three places: entry
;; n, at ReadTranslate + n, for nibble n.
;;
;; At $BA00 where DOS runs. Only the entries for the 32 nibbles $AB to $FF are used, so the table starts in the
;; middle of RWTS's code, on the page boundary $AB bytes before the first, and the code indexes it from the page's
;; start so that each look-up takes 4 cycles. The table's entries for bytes that are not nibbles hold other
;; values, which nothing uses. They are the 1978 table's. Apple's listing names the page's high byte XP.
;; Also: DNIBL (DOS33, DOS31)
ReadTranslate = * & $FF00

    ; Three bytes before the first nibble's entry, unused.
    .byte $00, $00, $00
.assert * = ReadTranslate + $AB, "ReadTranslate's first entry, for nibble $AB, follows the tables."
    .byte $00, $01, $08, $10        ; $AB-$AE
    .byte $18, $02, $03, $04        ; $AF-$B2
    .byte $05, $06, $20, $28        ; $B3-$B6
    .byte $30, $07, $09, $38        ; $B7-$BA
    .byte $40, $0A, $48, $50        ; $BB-$BE
    .byte $58, $0B, $0C, $0D        ; $BF-$C2
    .byte $0E, $0F, $11, $12        ; $C3-$C6
    .byte $13, $14, $15, $16        ; $C7-$CA
    .byte $17, $19, $1A, $1B        ; $CB-$CE
    .byte $1C, $1D, $1E, $21        ; $CF-$D2
    .byte $22, $23, $24, $60        ; $D3-$D6
    .byte $68, $25, $26, $70        ; $D7-$DA
    .byte $78, $27, $80, $88        ; $DB-$DE
    .byte $90, $29, $2A, $2B        ; $DF-$E2
    .byte $2C, $2D, $2E, $2F        ; $E3-$E6
    .byte $31, $32, $33, $98        ; $E7-$EA
    .byte $A0, $34, $A8, $B0        ; $EB-$EE
    .byte $B8, $35, $36, $37        ; $EF-$F2
    .byte $39, $3A, $C0, $C8        ; $F3-$F6
    .byte $D0, $3B, $3C, $D8        ; $F7-$FA
    .byte $E0, $3E, $E8, $F0        ; $FB-$FE
    .byte $F8                       ; $FF

.endscope
