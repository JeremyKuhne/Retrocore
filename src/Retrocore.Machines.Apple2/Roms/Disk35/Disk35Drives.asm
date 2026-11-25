; retrocore: style=strict
;; The card's firmware: the 3.5 drives and the SWIM
;;
;; Finding the drives on the card's own port and the format of their disks, moving the head, reading a drive's
;; sense lines and giving it commands (<Drives>), and switching the SWIM between its IWM and ISM modes and between
;; GCR and MFM (<Swim>).
;;
;; A 3.5 drive is run through sixteen registers, chosen by the phase lines CA0-CA2 and the head line (SEL, the
;; card's <SelectSide0> and <SelectSide1>): a command is a register strobed with LSTRB (phase 3), and a sense line is
;; a register read back as bit 7 of the IWM's status. The Disk II's IWM switches are explained in
;; [DiskII.md](../../../../docs/DiskII.md).

; The IWM's mode and status.

;; The IWM mode the firmware uses: latched data, an asynchronous handshake, no motor-off timer, fast (2 us) cells
;; and the 8 MHz clock.
IWM_MODE = $1F

;; The mode's bits, in the status register.
IWM_MODE_MASK = $1F

;; The status register's bit 5: the drive enable (motor line) is on.
IWM_STATUS_ENABLED = $20

;; The IWM mode bit that, written 1, 0, 1, 1, switches the SWIM to the ISM.
IWM_ISM_SWITCH = $40

; The ISM's mode register.

;; Enables drive 1.
ISM_MODE_DRIVE1 = $02

;; Enables drive 2.
ISM_MODE_DRIVE2 = $04

;; Both drive enables.
ISM_MODE_DRIVES = ISM_MODE_DRIVE1 | ISM_MODE_DRIVE2

;; Starts reading or writing.
ISM_MODE_ACTION = $08

;; Writes rather than reads.
ISM_MODE_WRITE = $10

;; Back to the IWM, when cleared.
ISM_MODE_ISM = $40

;; The motor line.
ISM_MODE_MOTOR = $80

; The ISM's setup register, of which this firmware keeps a copy in SetupCopy.

;; Setup bit 1, which this card uses to select its 3.5 drives' port rather than the SmartPort bus's.
SETUP_DRIVE_PORT = $02

;; Bit 5 of the ISM's setup and mode registers, which this firmware sets for MFM and clears for GCR.
SWIM_MFM = $20

;; The ISM's phase register's high nibble: the four phase lines are outputs.
PHASE_OUTPUTS = $F0

; SwimState.

;; The disk is MFM.
SWIM_STATE_MFM = $80

;; The SWIM is in ISM mode.
SWIM_STATE_ISM = $40

; A 3.5 drive's commands: the register <Drives::SendCommand> strobes.

;; Sets the step direction inward, toward the higher tracks.
DRIVE_STEP_INWARD = $00

;; Sets the step direction outward, toward track 0.
DRIVE_STEP_OUTWARD = $01

;; Clears the disk-switched latch.
DRIVE_CLEAR_SWITCHED = $03

;; Steps the head one track.
DRIVE_STEP = $04

;; An FDHD drive reads and writes MFM.
DRIVE_MFM_MODE = $06

;; An FDHD drive reads and writes GCR.
DRIVE_GCR_MODE = $07

;; Turns the motor on.
DRIVE_MOTOR_ON = $08

;; Turns the motor off.
DRIVE_MOTOR_OFF = $09

;; Ejects the disk.
DRIVE_EJECT = $0D

; A 3.5 drive's sense lines: the register <Drives::SenseLine> reads, and what a 1 there means.

;; The step direction: 1 outward.
SENSE_STEP_DIRECTION = $00

;; No disk is in the drive.
SENSE_NO_DISK = $02

;; The step is done.
SENSE_STEP_DONE = $04

;; The drive is an FDHD.
SENSE_FDHD = $05

;; The disk can be written.
SENSE_WRITE_ENABLED = $06

;; An FDHD drive is in MFM mode.
SENSE_MFM_MODE = $07

;; The motor is off.
SENSE_MOTOR_OFF = $08

;; The head is not at track 0.
SENSE_NOT_AT_TRACK_0 = $0A

;; The drive is not ready.
SENSE_NOT_READY = $0B

;; The disk was switched (ejected or inserted) since the latch was cleared.
SENSE_SWITCHED = $0C

;; The disk is not a high-density one.
SENSE_NOT_HIGH_DENSITY = $0F

; Each drive's Sense byte.

;; The disk was switched.
DISK_SWITCHED = $80

;; There is no disk.
DISK_ABSENT = $40

;; The disk is write-protected.
DISK_PROTECTED = $20

;; The disk has one side only.
DISK_ONE_SIDED = $10

;; The motor has had its full start since the drive last had no disk.
DISK_SPUN_UP = $01

; DeviceKinds.

;; A 3.5 drive.
DEVICE_DRIVE = $01

;; The 3.5 drive is an FDHD.
DEVICE_FDHD = $02

;; A SmartPort bus device.
DEVICE_BUS = $80

; MediaKind: the disk's format, which also indexes <MediaModes> and <FormatOptions::BlockCounts>.

;; Not known.
MEDIA_UNKNOWN = $00

;; GCR 400K, one side.
MEDIA_400K = $02

;; GCR 800K.
MEDIA_800K = $04

;; GCR 800K with a 2:1 interleave.
MEDIA_800K_2_TO_1 = $06

;; MFM 720K.
MEDIA_720K = $08

;; MFM 1440K.
MEDIA_1440K = $0A

; Other values.

;; <MediaMode>'s MFM bits, 5 and 6.
MEDIA_MODE_MFM = $60

;; <DiskSides>' bit 7: the disk has two sides.
DISK_TWO_SIDES = $80

;; The interleave in an address field's format byte.
FORMAT_INTERLEAVE_MASK = $1F

;; A format byte's 2:1 interleave.
INTERLEAVE_2_TO_1 = 2

;; The address fields the format search reads before it gives up on an encoding.
ADDRESS_TRIES = 4

;; How long an FDHD drive takes to change between GCR and MFM, in 2 ms units: 22 ms.
MODE_SETTLE_TIME = 11

;; The routines that find the 3.5 drives and their disks, move the head, and read a drive's sense lines and give it
;; commands. Most take the drive in X or in <Drive>: 0 or 1.
.scope Drives

;; Finds the 3.5 drives on the card's own port: drive 1, then drive 2 if drive 1 is there. Each is identified and
;; its disk, if any, read for its format; a drive whose disk cannot be read has it ejected.
;; Out: UnitCount = the drives found (0-2), <DeviceKinds> set for each
.proc Find
    jsr Swim::UseGcr
    ldx #$00
NextDrive:
    stx SavedDrive
    stx Drive
    jsr Detect
    bcs Counted
    ora #DEVICE_DRIVE
    sta DeviceKinds,x

    ; Its disk, if it has one.
    lda #DRIVE_CLEAR_SWITCHED
    jsr SendCommand
    jsr ReadStatusLines
    bvc HasDisk
    jsr ForgetDisk
    bra DriveDone
HasDisk:
    clc
    jsr IdentifyMedia
    bcc DriveDone
    ldx SavedDrive
    jsr EjectDisk
DriveDone:
    jsr Swim::UseGcr
    ldx SavedDrive
    inx
    cpx #$02
    bcc NextDrive

    ; The last drive found is left as the SWIM's.
Counted:
    stx UnitCount
    txa
    beq Done
    dex
    jsr Release
Done:
    rts
.endproc

;; Checks that a 3.5 drive answers on a drive line: its step direction must follow the commands. Leaves the direction
;; outward.
;; In: X = the drive (0 or 1)
;; Out: carry = set if there is no drive; else A = 0 for an Apple 3.5 drive, <DEVICE_FDHD> for an FDHD (SuperDrive)
;; Keeps: X, Y
.proc Detect
    jsr Swim::SelectDrivePort
    lda Iwm::SelectDrive1,x
    bit Iwm::DataLatch
    bit Iwm::ReadMode
    bit Iwm::MotorOn

    ; The direction line must read back outward, inward, then outward.
    lda #DRIVE_STEP_OUTWARD
    jsr SendCommand
    lda #SENSE_STEP_DIRECTION
    jsr SenseLine
    bcc None
    lda #DRIVE_STEP_INWARD
    jsr SendCommand
    lda #SENSE_STEP_DIRECTION
    jsr SenseLine
    bcs None
    lda #DRIVE_STEP_OUTWARD
    jsr SendCommand
    lda #SENSE_STEP_DIRECTION
    jsr SenseLine
    bcc None

    ; Which kind.
    lda #SENSE_FDHD
    jsr SenseLine
    bcc Found
    lda #DEVICE_FDHD
    clc
    rts
None:
    sec
Found:
    rts
.endproc

;; Finds a double-density disk's format: GCR 400K or 800K from an address field's format byte and the disk's sides,
;; and on an FDHD drive MFM 720K if no GCR field reads.
;; In: X = the drive
;; Out: carry = set if no format was found; else <MediaKind>, <BlockCount>, <BlockCountHigh> and <MediaMode> set
.proc IdentifyDoubleDensity
    stx SavedDrive
    lda #ADDRESS_TRIES
    sta Retries
    jsr WaitReadyForever

    ; Read GCR address fields, following the head to the track a field names.
ReadGcr:
    stz Side
    jsr ReadAddressField
    bcc GcrFound
    lda DiskErrors
    bit #DISK_ERROR_BAD_FIELD
    bne RetryGcr
    bit #DISK_ERROR_WRONG_TRACK
    beq NotWrongTrack
    lda AddressTrack
    sta Track
RetryGcr:
    dec Retries
    bne ReadGcr
    bra TryMfm
NotWrongTrack:
    bit #DISK_ERROR_NO_FIELD
    bne TryMfm
    sec
    rts

    ; GCR: 800K, with the interleave the format byte gives, or 400K on a disk with one side.
GcrFound:
    ldx SavedDrive
    jsr ReadStatus
    ldy #MEDIA_800K
    lda LastFormatByte,x
    and #FORMAT_INTERLEAVE_MASK
    cmp #INTERLEAVE_2_TO_1
    bne CheckSides
    ldy #MEDIA_800K_2_TO_1
CheckSides:
    bit DiskSides,x
    bmi SetKind
    lda Sense,x
    ora #DISK_ONE_SIDED
    sta Sense,x
    ldy #MEDIA_400K
SetKind:
    lda FormatOptions::BlockCounts,y
    sta BlockCount,x
    lda FormatOptions::BlockCounts + 1,y
    sta BlockCountHigh,x
    lda Sense,x
    and #<(~DISK_ABSENT)
    sta Sense,x
    lda MediaMode,x
    and #$94                        ; keeps bits 7, 4 and 2
    ora MediaModes,y
    sta MediaMode,x
    sty MediaKind,x
    clc
    rts

    ; MFM 720K, on an FDHD drive put in MFM mode.
TryMfm:
    ldx SavedDrive
    lda #DEVICE_FDHD
    bit DeviceKinds,x
    beq NotMfm
    lda #DRIVE_MFM_MODE
    jsr SendCommand
    lda #MODE_SETTLE_TIME
    jsr DelayMillisecondPairs
    jsr Swim::UseMfm
    lda #SENSE_MFM_MODE
    jsr SenseLine
    bcc TryMfm
    jsr WaitReadyForever
    stz Track
    lda #ADDRESS_TRIES
    sta Retries
ReadMfm:
    stz Side
    jsr ReadAddressField
    bcc MfmFound
    lda DiskErrors
    bit #DISK_ERROR_BAD_FIELD
    bne RetryMfm
    bit #DISK_ERROR_WRONG_TRACK
    beq RetryMfm
    lda AddressTrack
    sta Track
RetryMfm:
    dec Retries
    bne ReadMfm

    ; Neither: the drive back in GCR mode.
    lda #DRIVE_GCR_MODE
    jsr SendCommand
    lda #MODE_SETTLE_TIME
    jsr DelayMillisecondPairs
NotMfm:
    jsr Swim::UseGcr
    ldx SavedDrive
    lda MediaMode,x
    and #<(~MEDIA_MODE_MFM)
    sta MediaMode,x
    sec
    rts

MfmFound:
    jsr Swim::LeaveIsm
    ldx SavedDrive
    jsr ReadStatus
    ldy #MEDIA_720K
    lda FormatOptions::BlockCounts,y
    sta BlockCount,x
    lda FormatOptions::BlockCounts + 1,y
    sta BlockCountHigh,x
    lda Sense,x
    and #<(~DISK_ABSENT)
    sta Sense,x
    lda MediaModes,y
    sta MediaMode,x
    sty MediaKind,x
    clc
    rts
.endproc

;; The <MediaMode> for each double-density <MediaKind> (2 to 8), at its even index; the odd bytes, and the $52s at $0A
;; and $0C, are not read.
MediaModes:
    .byte $00, $00, $11, $88, $11, $88, $11, $88, $32, $09, $52, $12, $52, $12

;; Finds the format of the disk in a drive: on an FDHD drive with a high-density disk, MFM 1440K; else
;; <IdentifyDoubleDensity>. The flags the caller had are put back on success, so callers clear carry first.
;; In: X = the drive, carry = clear
;; Out: carry = set with A = <ERROR_OFFLINE> (no disk) or <ERROR_IO> (unreadable); else clear, with A as it came,
;;      and <MediaKind>, <BlockCount> and <BlockCountHigh> set
.proc IdentifyMedia
    php
    pha
    stx SavedDrive
    jsr ForgetMedia
    lda #SENSE_NO_DISK
    jsr SenseLine
    bcc HasDisk
    pla
    lda #ERROR_OFFLINE
    bra Fail

    ; A high-density disk in an FDHD drive: two sides, MFM.
HasDisk:
    lda #DEVICE_FDHD
    bit DeviceKinds,x
    beq DoubleDensity
    lda #SENSE_NOT_HIGH_DENSITY
    jsr SenseLine
    bcs DoubleDensity
    lda #DISK_TWO_SIDES
    sta DiskSides,x
    lda #$54                        ; MFM, and bits 4 and 2
    ora MediaMode,x
    sta MediaMode,x
    lda Sense,x
    and #<(~DISK_ABSENT)
    sta Sense,x
    jsr Recalibrate
    jsr Swim::UseMfm
    jsr MotorOn
    stz Side
    stz Track
    jsr WaitReadyForever
    lda #ADDRESS_TRIES
    sta Retries
ReadHighDensity:
    stz Side
    jsr ReadAddressField
    bcc HighDensityFound
    lda DiskErrors
    bit #DISK_ERROR_BAD_FIELD
    bne Retry
    bit #DISK_ERROR_WRONG_TRACK
    beq Retry
    lda AddressTrack
    sta Track
Retry:
    dec Retries
    bne ReadHighDensity
    bra Unreadable
HighDensityFound:
    jsr Swim::LeaveIsm
    ldx SavedDrive
    jsr ReadStatus
    ldy #MEDIA_1440K
    lda FormatOptions::BlockCounts,y
    sta BlockCount,x
    lda FormatOptions::BlockCounts + 1,y
    sta BlockCountHigh,x
    sty MediaKind,x
    clc
Return:
    pla
    plp
    rts

    ; Otherwise a double-density disk.
DoubleDensity:
    jsr Recalibrate
    jsr MotorOn
    stz Side
    ldx SavedDrive
    jsr IdentifyDoubleDensity
    bcc Return
Unreadable:
    pla
    lda #ERROR_IO
Fail:
    plp
    sec
    rts
.endproc

;; Records that a drive has no disk, and forgets its format and its cached sectors.
;; In: X = the drive
;; Keeps: X, Y
.proc ForgetDisk
    lda #DISK_ABSENT
    sta Sense,x
    ; Falls into ForgetMedia.
.endproc

;; Forgets a drive's format: no blocks, an unknown track, the MFM bits of its <MediaMode> cleared, and its cached
;; sectors dropped.
;; In: X = the drive
;; Keeps: X, Y
.proc ForgetMedia
    stz BlockCount,x
    stz BlockCountHigh,x
    lda MediaMode,x
    and #$80
    sta MediaMode,x
    lda #$FF
    sta CurrentTrack,x
    stz MediaKind,x
    phx
    phy
    jsr Cache::Forget
    ply
    plx
    rts
.endproc

;; Turns <Drive>'s motor on, if it is off, and waits for it to come up to speed: 500 ms the first time after the
;; drive had no disk (<DISK_SPUN_UP> clear in its <Sense>), else 100 ms.
;; In: Drive = the drive, selected
.proc MotorOn
    lda #SENSE_MOTOR_OFF
    jsr SenseLine
    bcc Done
    jsr SetMode
    lda #DRIVE_MOTOR_ON
    jsr SendCommand
    ldx Drive
    lda #DISK_SPUN_UP
    bit Sense,x
    bne Started
    ora Sense,x
    sta Sense,x
    lda #MOTOR_START_TIME
    jsr DelayMillisecondPairs
Started:
    lda #MOTOR_SPEED_TIME
    jsr DelayMilliseconds
Done:
    rts
.endproc

;; The extra wait for a motor's first start, in 2 ms units: 400 ms.
MOTOR_START_TIME = 200

;; The wait for a motor to come up to speed, in ms.
MOTOR_SPEED_TIME = 100

;; On an FDHD drive, sets the drive's MFM or GCR mode to suit its disk's <MediaMode>, if it is not in it already.
;; In: Drive = the drive, selected
.proc SetMode
    ldx Drive
    lda #DEVICE_FDHD
    bit DeviceKinds,x
    beq Done
    ldy #DRIVE_MFM_MODE
    lda #MEDIA_MODE_MFM
    bit MediaMode,x
    bne CheckMode
    iny
CheckMode:
    lda #SENSE_MFM_MODE
    jsr SenseLine
    bcs InMfm
    cpy #DRIVE_GCR_MODE
    beq Done
    bra Switch
InMfm:
    cpy #DRIVE_MFM_MODE
    beq Done
Switch:
    tya
    jsr SendCommand
    lda #$07                        ; nothing uses it
Done:
    rts
.endproc

;; Steps the head a number of tracks, in the direction already set, and lets it settle.
;; In: X = the tracks, 1 or more
;; Out: X = 0
;; Keeps: Y
.proc StepTracks
    lda #DRIVE_STEP
    jsr SendCommand
    lda #SENSE_STEP_DONE
    jsr WaitSense
    dex
    bne StepTracks
    ldx #STEP_SETTLE_TIME
Settle:
    dex
    bne Settle
    rts
.endproc

;; The passes of a short loop that let the head settle after it steps.
STEP_SETTLE_TIME = $3E

;; Moves <Drive>'s head to <Track>, through the <SeekVector>.
;; Out: carry = set if the head could not find track 0
.proc Seek
    jmp SeekVector
.endproc

;; The <SeekVector>'s routine: recalibrates if the track is unknown, then steps to <Track>.
;; In: Drive = the drive, Track = the track
;; Out: carry = set if track 0 was not found; else A = 0 if the head was already there, 1 if it moved
.proc SeekTrack
    ldx Drive
    lda CurrentTrack,x
    bpl Known
    jsr Recalibrate
    bcs Done
Known:
    ldx Drive
    lda CurrentTrack,x
    sec
    sbc Track
    beq There
    ldy #DRIVE_STEP_OUTWARD
    bcs Step
    ldy #DRIVE_STEP_INWARD
    eor #$FF
    adc #1
Step:
    tax
    tya
    jsr SendCommand
    jsr StepTracks
    ldx Drive
    lda Track
    sta CurrentTrack,x
    lda #1
There:
    clc
Done:
    rts
.endproc

;; Steps <Drive>'s head out until the drive senses track 0: up to five rounds of 16 steps, each checked 16 times
;; 7 ms apart.
;; Out: carry = set if track 0 was not found (<DiskErrors> bit 1 set); A = CurrentTrack = 0, or $FF; X = <Drive>
.proc Recalibrate
    stz DiskErrors
    lda #DRIVE_STEP_OUTWARD
    jsr SendCommand
    lda #SENSE_NOT_AT_TRACK_0
    jsr SenseLine
    bcc AtTrack0
    ldy #RECALIBRATE_ROUNDS
Round:
    ldx #RECALIBRATE_STEPS
    jsr StepTracks
    ldx #RECALIBRATE_STEPS
Check:
    lda #RECALIBRATE_CHECK_TIME
    jsr DelayMilliseconds
    lda #SENSE_NOT_AT_TRACK_0
    jsr SenseLine
    bcc AtTrack0
    dex
    bne Check
    dey
    bne Round
    lda #DISK_ERROR_NO_TRACK_0
    tsb DiskErrors
    lda #$FF
    sec
    bra Store
AtTrack0:
    lda #0
    clc
Store:
    ldx Drive
    sta CurrentTrack,x
    rts
.endproc

;; The rounds of steps <Drives::Recalibrate> takes.
RECALIBRATE_ROUNDS = 5

;; The steps in each round, and the checks after it.
RECALIBRATE_STEPS = 16

;; The ms between <Drives::Recalibrate>'s checks.
RECALIBRATE_CHECK_TIME = 7

;; Selects the head for <Side> through the card's head latch.
;; In: Side = 0, or not 0 for the second side
;; Out: A = Side
;; Keeps: X, Y
.proc SelectHead
    lda Side
    beq Lower
    sta SelectSide1
    rts
Lower:
    sta SelectSide0
    rts
.endproc

.endscope

;; The routines that switch the SWIM between its IWM and ISM modes, between the 3.5 drives' port and the SmartPort
;; bus's, and between GCR and MFM. <SwimState> says which mode it is in, and <SetupCopy> holds its setup register.
.scope Swim

;; Writes the IWM's mode register until it reads back, after waiting for the drive enable to go off.
;; In: A = the mode (bits 0-4)
;; Out: Y = the mode
;; Keeps: X
.proc SetIwmMode
    bit Iwm::ReadMode
    tay
    bit Iwm::MotorOff
    bit Iwm::LoadLatch
WaitDisabled:
    lda Iwm::ReadMode
    and #IWM_STATUS_ENABLED
    bne WaitDisabled
    bra Check
Write:
    sty Iwm::WriteMode
Check:
    tya
    eor Iwm::ReadMode
    and #IWM_MODE_MASK
    bne Write
    lda #SWIM_STATE_ISM
    trb SwimState
    lda Iwm::DataLatch
    rts
.endproc

;; Loads the ISM's sixteen timing parameters for <Track>'s zone, unless they already read back: up to five tries.
;; Out: carry = set if they never matched
.proc LoadParameters
    lda Track
    cmp #TRACKS
    bcc FindZone
    lda #0
FindZone:
    ldx #$FE
NextZone:
    inx
    inx
    cmp IsmZones,x
    bcs NextZone
    lda IsmZones + 1,x
    tax
    ldy #PARAMETER_TRIES

    ; Compare the parameters, backwards from the zone's end.
Try:
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    phx
Compare:
    dex
    lda IsmParameters,x
    beq Matched
    cmp Ism::ReadParameter
    bne Load
    bra Compare
Matched:
    plx
    clc
    rts

    ; Write them, and try again.
Load:
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    plx
    phx
Write:
    pha
    pla
    dex
    lda IsmParameters,x
    beq Written
    sta Ism::WriteParameter
    bra Write
Written:
    plx
    dey
    bne Try
    sec
    rts
.endproc

;; The tracks of a 3.5 disk; a track past them is taken as track 0.
TRACKS = 80

;; The tries <Swim::LoadParameters> makes.
PARAMETER_TRIES = 5

;; <Swim::LoadParameters>' zones: the first track past each zone, and the index in <IsmParameters> just past its
;; parameters. Tracks 0-39 take the first set and 40-79 the second; the pairs after them are never reached.
IsmZones:
    .byte 40, $11
    .byte TRACKS, $22
    .byte TRACKS, $00
    .byte TRACKS, $00

;; The ISM's timing parameters, two sets of sixteen, each read backwards from its end to the 0 before it. The two are
;; the same.
IsmParameters:
    .byte $00, $3B, $57, $1B, $97, $19, $19, $2F, $2F, $1B, $1B, $18, $18, $2E, $2E, $41
    .byte $18, $00, $3B, $57, $1B, $97, $19, $19, $2F, $2F, $1B, $1B, $18, $18, $2E, $2E
    .byte $41, $18

;; Puts the SWIM into ISM mode and sets it up: the setup register 0, the mode's action, write and MFM bits off, the
;; phase lines as outputs, and the parameters; then back to IWM mode.
.proc Initialize
    stz SwimState
    stz SetupCopy
    jsr EnterIsm
    lda #$00
    sta Ism::WriteSetup
    sta SetupCopy
    lda Ism::ReadSetup
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE | SWIM_MFM
    sta Ism::ClearMode
    lda #$00
    sta Ism::WriteCrc
    lda Ism::ReadMode
    lda Ism::ReadPhase
    ora #PHASE_OUTPUTS
    sta Ism::WritePhase
    jsr LoadParameters
    jmp LeaveIsm
.endproc

;; Switches the SWIM from IWM to ISM mode, if it is not there already. If the IWM had a drive enabled, or the SWIM
;; was in ISM mode already, then enables <Drive> (a 3.5 drive, 0 or 1) and its motor line in the ISM.
;; In: Drive = the drive
;; Out: A = the ISM's mode register
;; Keeps: X, Y
.proc EnterIsm
    phx
    bit SwimState
    bvs InIsm

    ; Write the mode with its ISM bit 1, 0, 1, 1.
    bit Iwm::ReadMode
    bit Iwm::LoadLatch
    lda Iwm::ReadMode
    pha
    bit Iwm::MotorOff
    and #IWM_MODE_MASK
    ora #IWM_ISM_SWITCH
    sta Iwm::WriteMode
    eor #IWM_ISM_SWITCH
    sta Iwm::WriteMode
    eor #IWM_ISM_SWITCH
    sta Iwm::WriteMode
    sta Iwm::WriteMode
    lda #SWIM_STATE_ISM
    tsb SwimState
    pla
    bit #IWM_STATUS_ENABLED
    beq Done

    ; Enable the drive.
InIsm:
    lda Ism::ReadMode
    and #ISM_MODE_DRIVES
    cmp #ISM_MODE_DRIVES
    bne Enable
    lda #ISM_MODE_DRIVES
    sta Ism::ClearMode
Enable:
    ldx Drive
    cpx #$02
    bcs Done
    lda #ISM_MODE_DRIVES
    sta Ism::ClearMode
    lda DriveEnableBits,x
    sta Ism::SetMode
    lda #ISM_MODE_MOTOR
    sta Ism::SetMode
Done:
    plx
    lda Ism::ReadMode
    rts
.endproc

;; The ISM mode register's drive-enable bit for drives 1 and 2.
DriveEnableBits:
    .byte ISM_MODE_DRIVE1, ISM_MODE_DRIVE2

;; Switches the SWIM back to IWM mode. If the ISM had the motor line on, the IWM gets the same drive and its motor
;; line on; else it just selects <Drive>, if that is a 3.5 drive.
;; Keeps: X, Y
.proc LeaveIsm
    lda Ism::ReadMode
    pha
    lda #ISM_MODE_MOTOR | ISM_MODE_WRITE | ISM_MODE_ACTION | ISM_MODE_DRIVES
    sta Ism::ClearMode
    lda #ISM_MODE_ISM
    sta Ism::ClearMode
    pha
    pla
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    lda #SWIM_STATE_ISM
    trb SwimState
    pla
    bmi MotorWasOn

    ; Select the drive.
    phx
    ldx Drive
    cpx #$02
    bcs Restore
    bit Iwm::SelectDrive1,x
Restore:
    plx
    rts

    ; The drive the ISM had, with its motor line.
MotorWasOn:
    phx
    ldx #$00
    bit #ISM_MODE_DRIVE2
    beq Select
    ldx #$01
Select:
    bit Iwm::SelectDrive1,x
    plx
    bit Iwm::MotorOn
    rts
.endproc

;; Switches back to IWM mode if the SWIM is in ISM mode.
;; Keeps: X, Y
.proc EnsureIwm
    bit SwimState
    bvc Done
    jsr LeaveIsm
Done:
    rts
.endproc

;; Selects the 3.5 drives' port: sets <SETUP_DRIVE_PORT> in the setup register, if it is not set already.
;; Keeps: A, X, Y
.proc SelectDrivePort
    pha
    lda #SETUP_DRIVE_PORT
    bit SetupCopy
    bne Done
    jsr EnterIsm
    lda #SETUP_DRIVE_PORT
    ora Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    cmp Ism::ReadSetup              ; the result is not used
    jsr LeaveIsm
Done:
    pla
    rts
.endproc

;; Selects the SmartPort bus's port: clears <SETUP_DRIVE_PORT> in the setup register, if it is not clear already.
;; Keeps: A, X, Y
.proc SelectBusPort
    pha
    lda #SETUP_DRIVE_PORT
    bit SetupCopy
    beq Done
    jsr EnterIsm
    lda #<(~SETUP_DRIVE_PORT)
    and Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    cmp Ism::ReadSetup              ; the result is not used
    jsr LeaveIsm
Done:
    pla
    rts
.endproc

;; Readies the SWIM for MFM: <SWIM_STATE_MFM> in <SwimState>, and, if the setup copy lacks it, <SWIM_MFM> in the mode
;; and setup registers and $40 written to the ISM's CRC register.
;; Keeps: X, Y
.proc UseMfm
    lda #SWIM_STATE_MFM
    tsb SwimState
    lda #SWIM_MFM
    bit SetupCopy
    bne Done
    jsr EnterIsm
    lda #SWIM_MFM
    sta Ism::SetMode
    ora Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$40
    sta Ism::WriteCrc
    jsr LeaveIsm
Done:
    rts
.endproc

;; Readies the SWIM for GCR, at $D80B: clears <SWIM_STATE_MFM>, and, if the setup copy has it, <SWIM_MFM> in the mode
;; and setup registers, writing 0 to the ISM's CRC register; then sets the IWM's mode to <IWM_MODE>.
;; Out: Y = <IWM_MODE>
;; Keeps: X
.proc UseGcr
.assert * = $D80B, "The self-test names the card's return to GCR as $D80B."
    lda #SWIM_STATE_MFM
    trb SwimState
    lda #SWIM_MFM
    bit SetupCopy
    beq SetMode
    jsr EnterIsm
    lda #SWIM_MFM
    sta Ism::ClearMode
    lda Ism::ReadSetup
    and #<(~SWIM_MFM)
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$00
    sta Ism::WriteCrc
    jsr LeaveIsm
SetMode:
    lda #IWM_MODE
    jsr SetIwmMode
    rts
.endproc

.endscope

; Drives: the drive lines.
.scope Drives continued

;; Hands a 3.5 drive back with its motor line on: enables it and its motor line in the ISM, deselects the drives'
;; port (<SETUP_DRIVE_PORT>), and returns to IWM mode, which keeps the drive and its motor line on.
;; In: X = the drive; one past the 3.5 drives does nothing
;; Keeps: X, Y
.proc Release
    cpx #$02
    bcs Done
    stx Drive
    jsr Swim::EnterIsm
    lda Swim::DriveEnableBits,x
    ora #ISM_MODE_MOTOR
    sta Ism::SetMode
    lda #$32
Pause:
    dec a
    bne Pause
    lda Ism::ReadSetup
    and #<(~SETUP_DRIVE_PORT)
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$19
PauseAgain:
    dec a
    bpl PauseAgain
    jsr Swim::LeaveIsm
Done:
    rts
.endproc

;; Selects one of a 3.5 drive's sixteen registers: CA2, the head line, CA0 and CA1 from A's bits 0-3, with LSTRB
;; (phase 3) low.
;; In: A = the register
;; Out: A = 0
;; Keeps: X, Y
.proc SelectRegister
    bit Iwm::Phase0Off
    bit Iwm::Phase1On
    bit Iwm::Phase3Off
    bit Iwm::Phase2Off
    lsr a
    bcc Ca2Low
    bit Iwm::Phase2On
Ca2Low:
    lsr a
    bcc Side0
    bit SelectSide1
    bra Ca0
Side0:
    bit SelectSide0
Ca0:
    lsr a
    bcc Ca0Low
    bit Iwm::Phase0On
Ca0Low:
    lsr a
    bcs Done
    bit Iwm::Phase1Off
Done:
    rts
.endproc

;; Gives a 3.5 drive a command: selects the register, then pulses LSTRB.
;; In: A = the command, one of the DRIVE_ values (<DRIVE_STEP>, <DRIVE_EJECT> ...)
;; Out: A = 0
;; Keeps: X, Y
.proc SendCommand
    jsr SelectRegister
    bit Iwm::Phase3On
    bit Iwm::Phase3Off
    rts
.endproc

;; Reads one of a 3.5 drive's sense lines.
;; In: A = the sense line, one of the SENSE_ values (<SENSE_NO_DISK>, <SENSE_NOT_READY> ...)
;; Out: carry = the line, A = 0
;; Keeps: X, Y
.proc SenseLine
    jsr SelectRegister
    bit Iwm::LoadLatch
    lda Iwm::ReadMode
    and #$80
    asl a
    rts
.endproc

;; Waits up to about three quarters of a second for the drive to report ready.
;; Out: carry = set if it never did
.proc WaitReady
    lda #SENSE_NOT_READY
    jsr SenseLine
    bcc Done
    ldx #$03
    ldy #$E8
Outer:
    lda #$92
    sta WaitCount
Inner:
    bit Iwm::ReadMode
    bpl Ready
    dec WaitCount
    bne Inner
    dey
    bne Outer
    dex
    bne Outer
    sec
    rts
Ready:
    clc
Done:
    rts
.endproc

;; Waits, without a limit, for the drive to report ready.
;; Out: carry = clear, A = 0
;; Keeps: X, Y
.proc WaitReadyForever
    lda #SENSE_NOT_READY
    jsr SenseLine
    bcc Done
Wait:
    lda Iwm::ReadMode
    and #$80
    bmi Wait
    asl a
Done:
    rts
.endproc

;; Waits until a sense line is set.
;; In: A = the sense line
;; Out: carry = set, A = 0
;; Keeps: X, Y
.proc WaitSense
    jsr SenseLine
Wait:
    lda Iwm::ReadMode
    and #$80
    bpl Wait
    asl a
    rts
.endproc

;; Checks the 3.5 drives for a removed disk while the card waits, forgetting the disk of a drive that has none.
.proc Poll
    ldx #$00
    lda DeviceKinds,x
    bmi Done
    beq Done
    jsr Swim::SelectDrivePort
NextDrive:
    ldy #$0A
Pause:
    dey
    bne Pause
    jsr ReadStatus
    bvc HasDisk
    jsr ForgetDisk
HasDisk:
    inx
    cpx #$01
    bne Last
    lda DeviceKinds,x
    bmi Last
    bne NextDrive
Last:
    dex
    jsr Release
Done:
    rts
.endproc

;; Reads a drive's sense lines and answers whether it can be used.
;; In: X = the drive
;; Out: carry = set with A = <ERROR_OFFLINE> (no disk) or <ERROR_DISK_SWITCHED> (switched, extended calls only);
;;      else A = 0, or <ERROR_WRITE_PROTECTED> if the disk is write-protected; negative = the disk was switched or
;;      its format is not known, so it must be found again
.proc CheckDisk
    jsr ReadStatus
    bvc HasDisk
    php
    jsr ForgetDisk
    plp
    bpl Absent
    jsr ClearSwitched
    bcs CheckWriteProtect::Finish
Absent:
    lda #ERROR_OFFLINE
    sec
    bra CheckWriteProtect::Finish
HasDisk:
    bmi Switched
    lda MediaKind,x
    bne CheckWriteProtect
    jsr CheckWriteProtect
    bit NegativeByte
    rts
Switched:
    jsr ForgetMedia
    jsr ClearSwitched
    bcs CheckWriteProtect::Finish
    ; Falls into CheckWriteProtect.
.endproc

;; Answers whether a drive's disk is write-protected.
;; In: X = the drive
;; Out: carry = clear, A = <ERROR_WRITE_PROTECTED> if protected, else 0; negative and overflow = the drive's <Sense>
;;      bits 7 and 6
;; Keeps: X, Y
;; Entry:
;;   Finish = sets negative and overflow from the drive's <Sense> and returns; <CheckDisk> comes here
.proc CheckWriteProtect
    lda #DISK_PROTECTED
    and Sense,x
    beq Writable
    lda #ERROR_WRITE_PROTECTED
Writable:
    clc
Finish:
    bit Sense,x
    rts
.endproc

;; A $A0 for BIT: sets negative, clears overflow.
NegativeByte:
    .byte $A0

;; Clears the drive's disk-switched latch.
;; Out: carry = set with A = <ERROR_DISK_SWITCHED> for an extended call, else clear with A = 0
;; Keeps: X, Y
.proc ClearSwitched
    lda #DRIVE_CLEAR_SWITCHED
    jsr SendCommand
    lda #ERROR_DISK_SWITCHED
    sec
    bit CardCommand
    bvs Done
    lda #$00
    clc
Done:
    rts
.endproc

;; Enables a drive and its motor line and reads its sense lines into its <Sense> byte.
;; In: X = the drive
;; Out: PreviousSense = the byte before; <Sense>,X bit 7 = switched, 6 = no disk, 5 = write-protected, bits 0-4 kept;
;;      negative and overflow = bits 7 and 6, zero = set if the disk can be written; Y = 0
;; Keeps: X
.proc ReadStatus
    lda Iwm::SelectDrive1,x
    bit Iwm::MotorOn
    ; Falls into ReadStatusLines.
.endproc

;; <ReadStatus> without enabling the drive.
;; It returns what <ReadStatus> returns.
;; In: X = the drive
;; Keeps: X
.proc ReadStatusLines
    lda Sense,x
    sta PreviousSense
    and #DISK_ONE_SIDED | $0F
    ora #DISK_PROTECTED
    sta Sense,x
    ldy #$03
Loop:
    lda StatusLines - 1,y
    jsr SenseLine
    bcc Next
    lda StatusBits - 1,y
    eor Sense,x
    sta Sense,x
Next:
    dey
    bne Loop
    lda #DISK_PROTECTED
    bit Sense,x
    rts
.endproc

;; The sense lines <ReadStatusLines> reads...
StatusLines:
    .byte SENSE_WRITE_ENABLED, SENSE_NO_DISK, SENSE_SWITCHED

;; ...and the <Sense> bit each one flips when it is set.
StatusBits:
    .byte DISK_PROTECTED, DISK_ABSENT, DISK_SWITCHED

.endscope
