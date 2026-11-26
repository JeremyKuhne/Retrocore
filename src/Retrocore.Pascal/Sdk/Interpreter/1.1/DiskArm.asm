; retrocore: style=strict
;; The Disk II driver's arm and timing, the sector prenibbling, and <DiskInit>, which checks for a Disk II.

; The arm's timing.

;; The steps from a move's start or end over which <StepArm> speeds up and slows down: <StepOnTimes> and <StepOffTimes>
;; have an entry for each.
STEP_RAMP = 8

;; The count of <DiskWait>'s delay loop, which makes each of its units about 100 microseconds.
WAIT_LOOP_COUNT = $11

;; Steps the arm from <ArmPosition> to a half-track, a phase at a time, speeding up and slowing down by <StepOnTimes>
;; and <StepOffTimes>, and then turns its phase off.
;; In: A = the half-track, X = the slot times 16
;; Out: ArmPosition = the half-track
;; Keeps: X
.proc StepArm

;; The half-track the arm is stepping from.
OldPosition = DiskTemp

;; The steps taken so far.
StepsTaken = DiskTemp2

    ; Nothing to do if the arm is there.
    stx StepSlot
    sta StepTarget
    cmp ArmPosition
    beq Return
    lda #0
    sta StepsTaken

    ; Step a half-track nearer, unless there.
NextStep:
    lda ArmPosition
    sta OldPosition
    sec
    sbc StepTarget
    beq Arrived
    bcs StepDown
    eor #$FF
    inc ArmPosition
    bcc Ramp
StepDown:
    adc #$FE
    dec ArmPosition

    ; Y = the steps from the move's start or end, whichever is nearer, up to STEP_RAMP - 1.
Ramp:
    cmp StepsTaken
    bcc CheckRamp
    lda StepsTaken
CheckRamp:
    cmp #STEP_RAMP
    bcs SwitchPhases
    tay

    ; Turn the new half-track's phase on and, once it has held, the old one's off.
SwitchPhases:
    sec
    jsr SwitchArmPhase
    lda StepOnTimes,y
    jsr DiskWait
    lda OldPosition
    clc
    jsr SwitchPhase
    lda StepOffTimes,y
    jsr DiskWait
    inc StepsTaken
    bne NextStep

    ; Let the arm settle for 256 units, with A = 0, then turn its phase off.
Arrived:
    jsr DiskWait
    clc

;; Turns the phase for <ArmPosition>'s half-track on or off.
;; In: carry = set for on, StepSlot = the slot times 16
;; Out: X = <StepSlot>
SwitchArmPhase:
    lda ArmPosition

;; Turns the phase for a half-track on or off: phase A AND 3.
;; In: A = the half-track, carry = set for on, StepSlot = the slot times 16
;; Out: X = <StepSlot>
SwitchPhase:
    and #3
    rol a
    ora StepSlot
    tax
    lda DiskPhase0Off,x
    ldx StepSlot
Return:
    rts
.endproc

;; Waits about A times 100 microseconds, counting <MotorTimer> up once each 100.
;; In: A = the units to wait, 0 for 256
;; Out: A = 0, X = 0
;; Keeps: Y
.proc DiskWait
    ; Wait a unit.
    ldx #WAIT_LOOP_COUNT
Delay:
    dex
    bne Delay

    ; Count it.
    inc MotorTimer
    bne Counted
    inc MotorTimer+1
Counted:
    sec
    sbc #1
    bne DiskWait
    rts
.endproc

;; The <DiskWait> units <StepArm> holds a new phase on before it turns the old one off, by its steps from the move's
;; start or end.
StepOnTimes:
    .byte $01, $30, $28, $24, $20, $1E, $1D, $1C
    .assert * - StepOnTimes = STEP_RAMP, "StepOnTimes has an entry for each step of the ramp."

;; The <DiskWait> units <StepArm> waits after turning the old phase off, by the same steps.
StepOffTimes:
    .byte $70, $2C, $26, $22, $1F, $1E, $1D, $1C
    .assert * - StepOffTimes = STEP_RAMP, "StepOffTimes has an entry for each step of the ramp."

;; Splits the 256 bytes at <SectorPointer> for <WriteSector>: their top six bits into <ScratchBuffer>, and their low bit
;; pairs, three to a byte and each with its bits swapped, into <TwoBitParts>.
;;
;; <TwoBitParts>,X gets the pairs of bytes $55 - X, $AB - X and $101 - X (bytes 0 and 1 again for X = 1 and 0, which
;; the third pass's 84 bytes leave over), in bits 2-3, 4-5 and 6-7.
.proc PrenibbleSector
    ; Clear TwoBitParts.
    ldy #TWO_BIT_BYTES
    lda #0
Clear:
    sta TwoBitParts-1,y
    dey
    bne Clear

    ; A pass over 86 bytes, X from the last of TwoBitParts down.
NextPass:
    ldx #TWO_BIT_BYTES - 1
NextByte:
    lda (SectorPointer),y
    and #HIGH_SIX_BITS
    sta ScratchBuffer,y

    ; Shift the byte's low two bits into the top of its TwoBitParts byte, bit 0 above bit 1.
    eor (SectorPointer),y
    iny
    cmp #2
    ora TwoBitParts,x
    ror a
    ror a
    sta TwoBitParts,x
    dex
    bpl NextByte

    ; Three passes, until Y has wrapped round to 2.
    cpy #<(3 * TWO_BIT_BYTES)
    bne NextPass
    rts
.endproc

;; The slot times 16 for each pair of drive numbers: drives 0-1 are in slot 6, 2-3 in slot 5 and 4-5 in slot 4.
DriveSlots:
    .byte 6 * 16, 5 * 16, 4 * 16
    .assert * - DriveSlots = DRIVE_PAIRS, "DriveSlots has a slot for each drive pair."

;; BIOS call 7: checks that a drive's slot holds a Disk II.
;; In: A = the drive number
;; Out: X = 0 and zero = set when it does, or else X = <DISK_ERROR_NO_DRIVE>
;; Keeps: Y
.proc DiskInit
    ; The drive pair.
    lsr a

;; Checks that a drive pair's slot holds a Disk II.
;; In: A = the drive pair, 0-2 for slots 6, 5 and 4
;; Out: X = 0 and zero = set when it does, or else X = <DISK_ERROR_NO_DRIVE>
;; Keeps: Y
CheckDrivePair:
    cmp #DRIVE_PAIRS
    bcs NoDrive

    ; X = 3 - the pair, so that SlotTypes+2,X is slot (6 - the pair)'s entry, at SlotTypes + the slot - 1.
    .assert DRIVE_PAIRS = 3 && MAIN_DISK_SLOT - 1 - DRIVE_PAIRS = 2, "DiskInit turns a pair into its slot."
    eor #DRIVE_PAIRS
    tax
    lda SlotTypes + MAIN_DISK_SLOT - 1 - DRIVE_PAIRS,x
    eor #CARD_DISK_II
    tax
    beq Done

NoDrive:
    ldx #DISK_ERROR_NO_DRIVE
Done:
    rts
.endproc
