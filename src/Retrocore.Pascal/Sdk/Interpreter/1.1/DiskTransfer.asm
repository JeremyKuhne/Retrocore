; retrocore: style=strict
;; The Disk II driver's BIOS calls, and its transfers: a track at a time, in the order the sectors pass the head.

; The Disk II driver's requests and errors.

;; <DiskCommand> for a read: what <DiskRead> passes <DiskTransfer>.
DISK_READ = 1

;; <DiskCommand> for a write: what <DiskWrite> passes <DiskTransfer>.
DISK_WRITE = 2

;; The error <DiskTransfer> returns for a block of 512 or more, or a drive number whose high byte is not 0.
DISK_ERROR_BAD_REQUEST = 8

;; The error for a drive whose slot does not hold a Disk II, or whose disk is not turning.
DISK_ERROR_NO_DRIVE = 9

;; The error for a write to a write-protected disk.
DISK_ERROR_WRITE_PROTECTED = $10

;; The error for a disk whose volume is not <WantedVolume>.
DISK_ERROR_WRONG_VOLUME = $20

;; The error for a track on which <TransferTrack> does not find all its sectors, even after recalibrating.
DISK_ERROR_NOT_FOUND = $40

; The disk's layout.

;; The bytes in a sector: one 256-byte page.
SECTOR_SIZE = 256

;; The sectors on a track. A track holds 8 of Pascal's 512-byte blocks.
SECTORS_PER_TRACK = 16

;; The tracks on a disk.
DISK_TRACKS = 35

; The drives.

;; The slot of drives 0 and 1, which <ResetDiskState> sets up. <DriveSlots> gives drives 2-3 slot 5, and 4-5 slot 4.
MAIN_DISK_SLOT = 6

;; The drive pairs <DriveSlots> has a slot for.
DRIVE_PAIRS = 3

;; What a slot is added to for drive 2's entry in <ArmTracks>, and <DriveIndex>.
DRIVE2_INDEX = $80

;; The interrupt-disable bit in the 6502's P register.
INTERRUPT_DISABLE = $04

; TransferTrack's timing and retries.

;; The <DiskWait> units, about 100 microseconds each, a write waits from turning on a stopped motor before it writes:
;; about a second. <TransferTrack> starts <MotorTimer> at its negative, and the wait ends when <MotorTimer> reaches 0.
MOTOR_START_UNITS = 10001

;; The <DiskWait> calls <TransferTrack> waits through, after turning on a motor that was stopped, before it seeks.
STOPPED_MOTOR_WAITS = 8

;; The count of <TransferTrack>'s own delay loop, which makes each <MotorTimer> step about 100 microseconds, as
;; <DiskWait>'s does.
MOTOR_LOOP_COUNT = $12

;; The wrong-track address fields <TransferTrack> takes, seeking again after each, before it recalibrates.
SEEK_RETRIES = 10

;; The rounds of looking for a track's sectors <TransferTrack> makes: the first, and one after recalibrating.
RECALIBRATIONS = 2

;; The address fields <TransferTrack> reads in a round before it gives the round up.
ADDRESS_TRIES = $80

;; The half-track a recalibration takes the arm to be at before it seeks track 0: 96 (track 48), more than a
;; disk's 70, so the arm is stepped all the way to its stop.
RECALIBRATE_HALF_TRACK = $60

;; What <SectorDone> holds for a sector that has been read or written.
SECTOR_DONE = $FF

;; What <PreparedSector> holds when no sector's data is ready to write.
NO_PREPARED_SECTOR = $FF

;; The interrupt-disable flag of <DiskTransfer>'s caller, its P register AND <INTERRUPT_DISABLE>, kept while a
;; transfer runs with interrupts off so that <DiskPoll> can give it back.
DiskSavedIrq:
    .res 1

;; Runs <ConsoleCheck> during a disk wait with the disk caller's interrupt-disable flag, then disables interrupts
;; again.
;; Keeps: A, X, Y, P
.proc DiskPoll
    ; Keep the flags and A.
    php
    pha

    ; Give back the caller's interrupt-disable flag while ConsoleCheck runs.
    lda DiskSavedIrq
    pha
    plp
    nop
    sei
    jsr ConsoleCheck

    ; Restore A and the flags.
    pla
    plp
    rts
.endproc

;; Startup's disk setup: selects drive 1 in <MAIN_DISK_SLOT>, accepts any volume, records the slot's two arms at
;; track 0, and records drive 1 of the slot as the drive last used.
.proc ResetDiskState
    ; Select drive 1.
    lda DiskSelect1 + MAIN_DISK_SLOT * 16

    ; Accept any volume, and take both arms to be at track 0.
    ldy #0
    sty WantedVolume
    sty ArmTracks + MAIN_DISK_SLOT
    sty ArmTracks + DRIVE2_INDEX + MAIN_DISK_SLOT

    ; Record drive 1 in the slot as the drive last used.
    iny
    sty CurrentDrive
    lda #MAIN_DISK_SLOT * 16
    sta CurrentSlot
    rts
.endproc

;; BIOS call 5: writes blocks to a disk, with <DiskTransfer>.
;; In: Stack = <DiskTransfer>'s parameters, under the return address
;; Out: X = 0, or an error as <DiskTransfer> returns it
.proc DiskWrite
    ldy #DISK_WRITE
    bne DiskTransfer
.endproc

;; BIOS call 6: reads blocks from a disk, with <DiskTransfer>, which it falls into.
;; In: Stack = <DiskTransfer>'s parameters, under the return address
;; Out: X = 0, or an error as <DiskTransfer> returns it
.proc DiskRead
    ldy #DISK_READ
.endproc

;; Pulls a disk call's parameters from under its return address and reads or writes the blocks, a track at a
;; time with <TransferTrack>.
;;
;; A block is two sectors. A read's last, partial page goes through <ScratchBuffer>, so that only its bytes reach
;; the buffer; a write writes whole pages.
;;
;; In:
;;   Y = <DISK_READ> or <DISK_WRITE>
;;   Stack = under the return address, these words, each low byte first: the block number, the byte count, the
;;     buffer's address, the drive number (0-5) and the control word, which is dropped
;; Out:
;;   X = 0, or <DISK_ERROR_BAD_REQUEST>, <DISK_ERROR_NO_DRIVE> when the drive's slot does not hold a Disk II, or
;;     the error <TransferTrack> leaves in <DiskError>
.proc DiskTransfer

;; The block number's low byte, while the track and the first sector are worked out from it.
BlockLow = PartialBytes

    ; Keep the command, and the return address.
    sty DiskCommand
    pla
    sta DiskReturn
    pla
    sta DiskReturn+1

    ; The block's first sector in its track: the block number times 2, modulo SECTORS_PER_TRACK.
    pla
    sta BlockLow
    asl a
    and #SECTORS_PER_TRACK - 1
    sta FirstSector

    ; Its track: the block number divided by 8, from bits 8 and 3-7. Bits 9-15 must be 0.
    pla
    lsr a
    sta BlockHigh
    lda BlockLow
    ror a
    lsr a
    lsr a
    sta DiskTrack

    ; The pages: the byte count's high byte, plus 1 for a partial page. A read keeps the partial page's bytes; a
    ; write writes the whole page.
    pla
    sta PartialBytes
    cmp #1
    pla
    adc #0
    dey
    beq KeepPartial
    dey
    sty PartialBytes
KeepPartial:
    sta PagesLeft

    ; The buffer, where a read's partial page is copied to as well.
    pla
    sta DiskBuffer
    sta PartialDest
    pla
    sta DiskBuffer+1

    ; The drive: bit 0 picks drive 1 or 2, and the rest the slot.
    pla
    lsr a
    tay
    lda #1
    adc #0
    sta DiskDrive
    lda DriveSlots,y
    sta DiskSlot

    ; The drive number's high byte, and the control word, which is dropped.
    pla
    tax
    pla
    pla

    ; Refuse a block of 512 or more, or a drive number of 256 or more.
    txa
    ldx #DISK_ERROR_BAD_REQUEST
    ora BlockHigh
    bne Return

    ; Refuse a slot without a Disk II.
    tya
    jsr DiskInit::CheckDrivePair
    bne Return

    ; Nothing to transfer?
    lda PagesLeft
    beq Success

    ; Mark every sector of the track as still to do.
NextTrack:
    ldy #SECTORS_PER_TRACK - 1
    lda #0
ClearDone:
    sta SectorDone,y
    dey
    bpl ClearDone

    ; This track's sectors: the rest of the track from FirstSector, or the pages left if fewer.
    lda #SECTORS_PER_TRACK
    sec
    sbc FirstSector
    cmp PagesLeft
    bcc SetSectors
    lda PagesLeft
SetSectors:
    sta TrackSectors
    sta SectorsLeft

    ; Transfer the track with interrupts disabled, keeping the caller's interrupt-disable flag for DiskPoll.
    php
    pla
    and #INTERRUPT_DISABLE
    sta DiskSavedIrq
    sei
    jsr TransferTrack

    ; Give the flag back, keeping TransferTrack's carry, and stop on an error.
    php
    pla
    ora DiskSavedIrq
    pha
    plp
    ldx DiskError
    bcs Return

    ; Go on to the next track, from its first sector, and the pages after this track's.
    lda #0
    sta FirstSector
    inc DiskTrack
    lda DiskBuffer+1
    adc TrackSectors
    sta DiskBuffer+1
    lda PagesLeft
    sec
    sbc TrackSectors
    sta PagesLeft
    bne NextTrack

    ; Copy a read's partial page from ScratchBuffer.
    ldy PartialBytes
    beq Success
CopyPartial:
    dey
    lda ScratchBuffer,y
    sta (PartialDest),y
    tya
    bne CopyPartial

Success:
    ldx #0

    ; Return to the caller.
Return:
    lda DiskReturn+1
    pha
    lda DiskReturn
    pha
    rts
.endproc

;; Selects <DiskSlot>'s drive <DiskDrive> with its motor on, seeks <DiskTrack>, and reads or writes the track's
;; sectors in the transfer in the order they pass the head, seeking again on the wrong track and recalibrating
;; when lost.
;;
;; Pascal's sectors are interleaved 2:1: the disk's sector n holds the track's page n / 2 for even n, and
;; 8 + n / 2 for odd n. A write prepares each sector's data while the sector before it passes.
;;
;; Out:
;;   carry = set on an error
;;   DiskError = with carry set, <DISK_ERROR_NO_DRIVE> when no disk is turning, <DISK_ERROR_WRITE_PROTECTED>,
;;     <DISK_ERROR_WRONG_VOLUME> or <DISK_ERROR_NOT_FOUND>; with carry clear, <SECTOR_DONE>, left in A
.proc TransferTrack
    ; Start the retry counts.
    ldy #RECALIBRATIONS
    sty Recalibrations
    ldy #SEEK_RETRIES
    sty SeekRetries

    ; A new slot: wait for the last slot's disk to stop turning.
    ldx DiskSlot
    cpx CurrentSlot
    beq SameSlot
    ldx CurrentSlot
WaitForStop:
    jsr DiskPoll
    jsr CheckSpinning
    bne WaitForStop
    ldx DiskSlot
    stx CurrentSlot

    ; Keep whether the disk is turning, and turn the motor on. A new drive counts as not turning.
SameSlot:
    jsr CheckSpinning
    php
    lda DiskMotorOn,x
    lda DiskDrive
    cmp CurrentDrive
    beq SelectDrive
    sta CurrentDrive
    plp
    ldy #0
    php

    ; Select the drive.
SelectDrive:
    and #1
    eor #1
    ora DiskSlot
    tay
    cmp DiskSelect1,y

    ; DriveIndex: the slot, from slot times 16, plus DRIVE2_INDEX for drive 2.
    lsr a
    php
    lsr a
    lsr a
    plp
    ror a
    sta DriveIndex

    ; Start MotorTimer, for a write's wait.
    lda #<($10000 - MOTOR_START_UNITS)
    sta MotorTimer
    lda #>($10000 - MOTOR_START_UNITS)
    sta MotorTimer+1

    ; A motor that was stopped: wait about 200 milliseconds before seeking. The first DiskWait waits A = $D8 units,
    ; left from MotorTimer's high byte, and the rest 256.
    plp
    php
    bne Seek
    ldy #STOPPED_MOTOR_WAITS
SpinUp:
    jsr DiskWait
    dey
    bne SpinUp
    ldx DiskSlot

    ; Seek the track.
Seek:
    lda DiskTrack
    jsr SeekTrack

    ; A motor that was stopped: a write first waits for MotorTimer to reach 0, about a second from when the motor
    ; started.
    plp
    bne FindSectors
    lda DiskCommand
    cmp #DISK_WRITE
    bne CheckTurning
WaitForSpeed:
    ldy #MOTOR_LOOP_COUNT
Delay:
    dey
    bne Delay
    inc MotorTimer
    bne WaitForSpeed
    jsr DiskPoll
    inc MotorTimer+1
    bne WaitForSpeed

    ; Is the disk turning now?
CheckTurning:
    jsr CheckSpinning
    bne FindSectors
    lda #DISK_ERROR_NO_DRIVE
    bne Fail

    ; Keep the command in carry on the stack, set for a read, for the rest of the track.
FindSectors:
    lda DiskCommand
    ror a
    php
    lda #NO_PREPARED_SECTOR
    sta PreparedSector

    ; Start a round of reading address fields.
NewRound:
    ldy #ADDRESS_TRIES
    sty AddressTries

    ; Read the next address field, if the round has any left.
NextAddress:
    dec AddressTries
    bmi Recalibrate
    jsr DiskPoll
    ldx DiskSlot
    jsr ReadAddressField
    bcs NextAddress

    ; On the right track?
    lda AddressTrack
    cmp ArmPosition
    beq RightTrack

    ; No: record where the arm is, and seek the track again from there, until SEEK_RETRIES runs out.
    ldy DriveIndex
    asl a
    sta ArmTracks,y
    lda ArmPosition
    dec SeekRetries
    bne Reseek

    ; Recalibrate, if there is a round left: step the arm back to its stop at track 0, and seek the track again.
Recalibrate:
    dec Recalibrations
    beq NotFound
    lda ArmPosition
    pha
    lda #SEEK_RETRIES
    sta SeekRetries
    lda #RECALIBRATE_HALF_TRACK
    ldy DriveIndex
    sta ArmTracks,y
    lda #0
    jsr SeekTrack
    pla
Reseek:
    jsr SeekTrack
    jmp NewRound

    ; Give up with an error, dropping the command.
NotFound:
    lda #DISK_ERROR_NOT_FOUND
DropAndFail:
    plp
Fail:
    jmp Error

    ; Never reached: a JMP to the success exit.
    jmp Success

    ; The right track: check the volume, unless any will do.
RightTrack:
    lda WantedVolume
    pha
    lda AddressVolume
    sta LastVolume
    pla
    beq VolumeChecked
    cmp AddressVolume
    beq VolumeChecked
    lda #DISK_ERROR_WRONG_VOLUME
    bne DropAndFail

    ; A write: write this sector if its data is ready, or else prepare the next sector's while it comes round,
    ; unless that one is ready already.
VolumeChecked:
    plp
    php
    bcs CheckSector
    lda AddressSector
    cmp PreparedSector
    beq Write
    clc
    adc #1
    and #SECTORS_PER_TRACK - 1
    cmp PreparedSector
    beq NextAddress
    sta AddressSector

    ; Is the sector still to do?
CheckSector:
    ldy AddressSector
    lda SectorDone,y
    beq Interleave
    jmp NextAddress

    ; The sector's page in the track, by the interleave.
Interleave:
    tya
    lsr a
    bcc InTransfer
    ora #SECTORS_PER_TRACK / 2

    ; Its page in the transfer, from FirstSector: skip a page before the transfer or after it.
InTransfer:
    sec
    sbc FirstSector
    bcc Continue
    tay
    clc
    adc DiskBuffer+1
    iny
    cpy PagesLeft
    bcc WholePage
    bne Continue

    ; A read's partial last page goes to ScratchBuffer, and is copied to its place at the end.
    ldy PartialBytes
    beq WholePage
    sta PartialDest+1
    .assert <ScratchBuffer = 0, "A partial page is read to the start of ScratchBuffer's page."
    ldy #0
    lda #>ScratchBuffer
    bcs SetPointer

WholePage:
    ldy DiskBuffer
SetPointer:
    sty SectorPointer
    sta SectorPointer+1

    ; A read reads the sector now; a write prepares its data, for when the sector next comes round.
    plp
    php
    bcs Read
    jsr PrenibbleSector
    ldx DiskSlot
    lda AddressSector
    sta PreparedSector
Continue:
    jmp NextAddress

Read:
    jsr ReadSector
    bcs Continue

    ; Mark the sector done, and stop when the track's sectors are.
Transferred:
    ldy AddressSector
    .assert SECTOR_DONE = NO_PREPARED_SECTOR, "TransferTrack stores one value as both marks."
    lda #SECTOR_DONE
    sta SectorDone,y
    sta PreparedSector
    dec SectorsLeft
    bne Continue
    plp

    ; Leave with carry clear on success or set on an error, and the error in DiskError, turning the motor off.
Success:
    clc
    .byte $24                 ; BIT zero page: skips the next instruction for the code falling in
Error:
    sec
    sta DiskError
    lda DiskMotorOff,x
    rts

    ; Write the sector whose data is ready.
Write:
    jsr WriteSector
    bcc Transferred

    ; Write-protected: drop the command, and leave with the error.
    pla
    lda #DISK_ERROR_WRITE_PROTECTED
    bcs Error
.endproc

;; Turns the stepper phases off and moves the arm of the drive at <DriveIndex> to a track, from where <ArmTracks>
;; has it.
;; In: A = the track, X = the slot times 16
;; Out: ArmPosition = the track, ArmTracks,DriveIndex = its half-track
;; Keeps: X
.proc SeekTrack
    ; Turn every phase off.
    asl a
    pha
    lda DiskPhase0Off,x
    lda DiskPhase1Off,x
    lda DiskPhase2Off,x
    lda DiskPhase3Off,x

    ; Move the arm from its half-track to the track's, recording the new one.
    ldy DriveIndex
    lda ArmTracks,y
    sta ArmPosition
    pla
    sta ArmTracks,y
    jsr StepArm

    ; Make the half-track a track.
    lsr ArmPosition
    rts
.endproc
