; retrocore: style=strict
;; DOS 3.2 RWTS: read or write a track and sector ($BD00-$BE9B where DOS runs)
;;
;; RWTS, "read or write a track and sector", is the routine the rest of DOS calls for every disk access. The caller
;; describes the request in an IOB, laid out as <Iob>, and passes its address in A and Y. RWTS starts the drive: it
;; waits for another slot's drive to stop if the slot has changed, checks whether the motor is already turning,
;; turns it on, selects the drive, moves the head to the track and, if the motor was off, waits for it to come up
;; to speed. Then it reads address fields until it finds the sector, and reads or writes its data field, or it
;; formats the disk (<Formatter::Format>, Formatter32.asm). The file manager, and programs using the vector at
;; $03D9, call it through <CallRwts> (BootLoader32.asm), which disables interrupts for the call; DOS's own IOB is
;; <DosIob> and its DCT <DosDeviceTable>. docs/Dos.md explains the IOB, and docs/DiskII.md the drive.
;;
;; This is DOS 3.3's RWTS (its Rwts1.asm and Rwts2.asm) as it was before DOS 3.3 changed it: the names are DOS
;; 3.3's where the code is the same. DOS 3.2 differs in a few places. It reads the sector number the IOB gives as
;; the number on the disk, with no translation. It checks once, not eight times, whether the motor is turning; it
;; reads the motor's start-up count from both of the DCT's bytes; it recalibrates only once; and its formatter is
;; part of RWTS's code rather than a module of its own. RWTS reads the IOB's bytes from <Iob::SLOT_TIMES_16> to
;; <Iob::PREVIOUS_DRIVE> but the byte count, and writes the return code, the volume found and the previous slot and
;; drive; it reads the DCT's <DeviceTable::WHOLE_TRACKS> and both bytes of <DeviceTable::MOTOR_DELAY>.
;;
;; Several values live in screen holes, at the address given plus the slot (<Drive1HalfTracks>,
;; <Drive2HalfTracks>) or at slot 0's byte (the counters); see RwtsEquates.asm.

;; The start of the relocator's range of RWTS's code from here to <RwtsCodeLast>: RWTS, the formatter and the patches
;; after it, $BD00-$BFFE where DOS runs. See Relocator.asm.
;; Also: ASC2 (DOS33, DOS31)
RwtsCodeStart:

; RWTS's variables, which the formatter and the head helpers share with it.

;; The half-track drive 1 of each slot's card is on: the table's byte for slot n is at $0478 + n, a screen hole.
;;
;; <SeekHalfTrack> reads and updates it, <SetTrack> sets it, and `BOOT 2` clears the boot slot's.
;; Also: DRV1TRK (DOS33)
Drive1HalfTracks = $0478

;; The half-track drive 2 of each slot's card is on, at $04F8 + n.
;; Also: DRV2TRK (DOS33)
Drive2HalfTracks = $04F8

;; The address of the caller's IOB (2 bytes), which RWTS reads and writes through.
;; Also: IOBPL (DOS33)
IobPointer = SavedStatus

;; The high byte of <IobPointer>.
;; Also: IOBPH (DOS33)
IobPointerHigh = SavedStackPointer

;; The address of the DCT (2 bytes), copied from the IOB's <Iob::DEVICE_TABLE>.
;; Also: DEVCTBL (DOS33)
DctPointer = Address1

;; The drive RWTS has selected: bit 7 set for drive 1, clear for drive 2.
;; Also: DRIVNO (DOS33)
SelectedDrive = SavedOutputY

;; The sector number in the address field just read, <AddressField>'s second byte.
;;
;; DOS 3.2's RWTS compares it with the IOB's sector as it is, since its sector numbers are the ones on the disk.
;; Also: SECT (DOS33)
FoundSector = AddressField + 1

;; The track number in the address field just read.
;;
;; <SeekHalfTrack> also borrows the byte to hold the half-track it seeks to.
;; Also: TRACK (DOS33)
FoundTrack = AddressField + 2

;; The volume number in the address field just read.
;; Also: VOLUME (DOS33)
FoundVolume = AddressField + 3

;; The address fields, and in DOS 3.2 the seeks too, left before RWTS gives up on the track (slot 0's screen-hole
;; byte at $0578).
;; Also: RETRYCNT (DOS33)
RetriesLeft = $0578

;; Reads, writes, seeks or formats as the IOB at A and Y says.
;;
;; At $BD00 where DOS runs. If the slot differs from the last call's, it first waits for the old slot's drive to
;; stop: the data latch changes while a disk turns, so it waits until eight reads in a row see the same value.
;; Then the same test, once, on this slot tells whether its motor is already on; the answer stays on the stack, in
;; the zero flag, until after the seek, and a change of drive counts as off. A motor that was off gets its start-up
;; time: <Rwts::MotorCount> starts at the DCT's count and counts up to zero, and the time <DiskII::MoveHead> spends
;; counts toward it.
;; In: A = the IOB's address's high byte, Y = its low byte
;; Out: carry = clear on success, with the IOB's <Iob::RETURN_CODE> = A (see <Rwts::Succeed>) and, after a read,
;;   the sector in the IOB's buffer
;; Errors: carry = set, with the IOB's <Iob::RETURN_CODE> = the error: <RWTS_WRITE_PROTECTED>, <RWTS_VOLUME_MISMATCH>,
;;   <RWTS_DRIVE_ERROR> or <RWTS_READ_ERROR>
;; Entry:
;;   TryTrack = carries out the command, with the head on the track
;;   Succeed = the success exit
;;   Fail = the failure exit
;; Also: RWTS (DOS33)
.proc Rwts
.assert MASTER || * = $BD00, "RWTS is at $BD00 where DOS runs."

;; The slot times 16 for this call (slot 0's screen-hole byte at $05F8).
;; Also: SLOT (DOS33)
SlotTimes16 = $05F8

;; Where the IOB's <Iob::DEVICE_TABLE> and <Iob::BUFFER> are copied (4 bytes): <DctPointer>, then
;; <SectorBuffer>.
;; Also: PTRSDEST (DOS33)
Pointers = DctPointer

;; The motor-on count, <MotorTime> and <MotorTimeHigh>: it counts up to 0 in steps of 100 microseconds.
;;
;; DOS 3.2's RWTS sets both bytes from the DCT's <DeviceTable::MOTOR_DELAY>, $D8EF for the Disk II, before it
;; seeks. If the motor was off, it then counts the rest up to 0 itself (<Rwts::WaitForMotor>); <DiskII::Wait>,
;; called while seeking, has already added the seek's time.
;; Also: MONTIME (DOS33)
MotorCount = MotorTime

;; The recalibrations left (slot 0's screen-hole byte at $04F8, its <Drive2HalfTracks> byte): RWTS sets it to 1, so
;; that it recalibrates once.
;; Also: RECALCNT (DOS33)
RecalibrationsLeft = $04F8

;; The reads in a row that must see the same latch value before a drive counts as stopped.
STOP_READS = 8

;; The passes of the delay loop, which with the count's step make about 100 cycles, 100 microseconds.
DELAY_PASSES = $12

;; The address fields read after the first before RWTS gives up on finding the sector: 49 tries in all.
ADDRESS_RETRIES = $30

;; The track RWTS records before it recalibrates: track 96, half-track 192, far enough beyond track 34 that the
;; seek to track 0 stops the head against the stop whatever its real place.
RECALIBRATION_TRACK = $60

    ; The caller's IOB and slot.
    sty IobPointer
    sta IobPointerHigh
    ldy #Iob::SLOT_TIMES_16
    lda (IobPointer),y
    tax
    sty RecalibrationsLeft          ; Y = 1: one recalibration
    ldy #Iob::PREVIOUS_SLOT
    cmp (IobPointer),y
    beq SameSlot

    ; Another slot: note the new one as the previous, then wait until the old slot's drive has stopped.
    txa
    pha
    lda (IobPointer),y
    tax                             ; X = the old slot, to watch
    pla
    pha
    sta (IobPointer),y
    lda ReadMode,x
;; Waits until the latch reads the same eight times in a row.
;; Also: STILLON (DOS33)
WaitForStop:
    ldy #STOP_READS
    lda DataLatch,x
;; Also: NOTSURE (DOS33)
CompareLatch:
    cmp DataLatch,x
    bne WaitForStop                 ; it changed: still turning
    dey
    bne CompareLatch
    pla
    tax

    ; Is this slot's motor on? The latch is read, and read again a few cycles later: a turning disk changes it.
;; The test of this slot's motor, then the motor on.
;; Also: SAMESLOT (DOS33)
SameSlot:
    lda ReadMode,x
    lda DataLatch,x
    lda DataLatch,x
    pha
    pla
    stx SlotTimes16
    cmp DataLatch,x
    php                             ; zero set if the motor is off
    lda MotorOn,x

    ; The IOB's DCT and buffer addresses to Pointers: the DCT's to DctPointer, the buffer's to SectorBuffer.
    ldy #Iob::DEVICE_TABLE
;; Also: PTRMOV (DOS33)
CopyPointers:
    lda (IobPointer),y
    sta Pointers - Iob::DEVICE_TABLE,y
    iny
    cpy #Iob::BUFFER + 2
    bne CopyPointers

    ; If the drive isn't the last call's, it is recorded, and the motor counts as off.
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ldy #Iob::PREVIOUS_DRIVE
    cmp (IobPointer),y
    beq SameDrive
    sta (IobPointer),y
    plp
    ldy #0                          ; zero set: off
    php
;; Selects the drive: drive 1 sets the carry.
;; Also: OK (DOS33)
SameDrive:
    ror a
    lda SelectDrive1,x
    bcs DriveSelected
    lda SelectDrive2,x
;; Also: DRVSEL (DOS33)
DriveSelected:
    ror SelectedDrive

    ; The start-up count, from the DCT's motor delay, then the seek to the IOB's track, the byte after.
    ldy #DeviceTable::MOTOR_DELAY
    lda (DctPointer),y
    sta MotorCount
    iny
    lda (DctPointer),y
    sta MotorCount + 1
    iny
.assert Iob::TRACK = DeviceTable::MOTOR_DELAY + 2, "The IOB's track follows the DCT's motor delay's offset."
    lda (IobPointer),y
    jsr SeekTrack
    plp
    bne TryTrack                    ; the motor was on

    ; The motor was off: waits for MotorCount to count up to 0, 100 microseconds a step.
;; Also: MOTOF (DOS33)
WaitForMotor:
    ldy #DELAY_PASSES
;; Also: CONWAIT (DOS33)
DelayLoop:
    dey
    bne DelayLoop
    inc MotorCount
    bne WaitForMotor
    inc MotorCount + 1
    bne WaitForMotor
    ; Falls into TryTrack.

;; Carries out the IOB's command with the head on the track: 0 seeks only, 4 formats, odd reads and even writes.
;;
;; A write's sector is prepared first, while nothing is waiting; the carry, set to read or clear to write, waits on
;; the stack. A wrong track costs a try, as a bad address field does.
;; In: X = slot * 16, the motor test's flags on the stack
;; Also: TRYTRK (DOS33)
TryTrack:
    ldy #Iob::COMMAND
    lda (IobPointer),y
    beq SeekOnly
    cmp #RWTS_FORMAT
    beq Format
    ror a
    php
    bcs StartTries
    jsr DiskII::PreNibble
;; Also: TRYTRK2 (DOS33)
StartTries:
    ldy #ADDRESS_RETRIES
    sty RetriesLeft
;; Also: TRYADR (DOS33)
TryAddress:
    ldx SlotTimes16
    jsr DiskII::ReadAddressField
    bcc CheckTrack
;; Also: TRYADR2 (DOS33)
NextTry:
    dec RetriesLeft
    bpl TryAddress

    ; No good address field in 49 tries: recalibrates. SetTrack records the head at track 96 (half-track 192), so
    ; the seek to track 0 steps out far enough to stop against track 0 whatever the head's real place, then it
    ; seeks the track again. The second time this happens, it is a drive error.
;; Also: RECAL (DOS33)
Recalibrate:
    lda CurrentTrack
    pha
    lda #RECALIBRATION_TRACK
    jsr SetTrack
    dec RecalibrationsLeft
    bne DriveError
    lda #0
    jsr SeekTrack
    pla
;; Also: RESEEK (DOS33)
SeekAgain:
    jsr SeekTrack
    jmp StartTries

    ; An address field: is the head on the right track? If not, the drive's record of the track is corrected to
    ; the one read, and it seeks again, counting the seeks against RetriesLeft too.
;; Also: RDRIGHT (DOS33)
CheckTrack:
    ldy FoundTrack
    cpy CurrentTrack
    beq RightTrack
    lda CurrentTrack
    pha
    tya
    jsr SetTrack
    pla
    dec RetriesLeft
    bpl SeekAgain
    bmi NextTry                     ; always: on to recalibrating
;; Also: DRVERR (DOS33)
DriveError:
    pla
    lda #RWTS_DRIVE_ERROR
;; Drops the read or write flags from the stack and fails with the error in A.
;; Also: JMPTO1 (DOS33)
FailWithFlags:
    plp
    jmp Fail
;; Also: GALLDONE (DOS33)
SeekOnly:
    beq Succeed                     ; always
;; Also: FORMDSK (DOS33)
Format:
    ldy #Iob::VOLUME
    lda (IobPointer),y
    sta FormatVolume                ; the volume to write
    jmp Formatter::Format

    ; The right track. The volume found goes to the IOB; it must match the one asked for, unless that is 0.
;; Also: RTTRK (DOS33)
RightTrack:
    ldy #Iob::VOLUME
    lda (IobPointer),y
    pha
    lda FoundVolume
    ldy #Iob::VOLUME_FOUND
    sta (IobPointer),y
    pla
    beq RightVolume
    cmp FoundVolume
    beq RightVolume
    lda #RWTS_VOLUME_MISMATCH
    bne FailWithFlags               ; always

    ; The right sector? If not, on to the next address field; after RetriesLeft of them, a read error.
;; Also: CORRECTVOL (DOS33)
RightVolume:
    ldy #Iob::SECTOR
    lda FoundSector
    cmp (IobPointer),y
    beq GotSector
    dec RetriesLeft
    bpl TryAddress
    lda #RWTS_READ_ERROR
    bne FailWithFlags               ; always

    ; The sector is under the head: reads or writes its data field.
;; Also: GOTSECT (DOS33)
GotSector:
    plp
    bcc Write
    jsr DiskII::ReadDataField
    php
    bcs NextTry                     ; a bad read: tries again, the carry on the stack again
    plp
    jsr DiskII::PostNibble
    ldx SlotTimes16
    ; Falls into Succeed.

;; RWTS's success exit: stores A in the IOB's return code, turns the motor off and returns with the carry clear.
;;
;; `.byte $24` is the opcode of `bit` zero page: with the `sec` that follows as its operand, it reads byte $38 and
;; skips the `sec`, changing only the negative, overflow and zero flags. It stores whatever A holds, which is 0
;; only for a seek: after a read it is the sector's last byte, after a write a byte read from the card. The file
;; manager reads the return code only when the carry is set. The formatter ends here too.
;; In: A = the return code, X = slot * 16
;; Out: carry = clear
;; Also: ALLDONE (DOS33)
Succeed:
    clc
    .byte $24                       ; bit $38: skips the sec
;; RWTS's failure exit: stores the error in the IOB's return code, turns the motor off and returns with the carry
;; set.
;; In: A = the error, X = slot * 16
;; Out: carry = set
;; Also: HNDLERR (DOS33)
Fail:
    sec
    ldy #Iob::RETURN_CODE
    sta (IobPointer),y
    lda MotorOff,x
    rts
;; Writes the data field, failing if the disk is write-protected.
;; Also: WRIT (DOS33)
Write:
    jsr DiskII::WriteDataField
    bcc Succeed
    lda #RWTS_WRITE_PROTECTED
    bcs Fail                        ; always
.endproc

;; Seeks the drive in <SelectedDrive> to track A, for a drive whose DCT says a track is one step or two.
;;
;; With two half-tracks to a track (the Disk II), the track is doubled for <SeekHalfTrack> and <CurrentTrack>
;; halved afterwards, so that RWTS can compare it with the track an address field gives.
;; In: A = the track, X = slot * 16, DctPointer = the DCT, SelectedDrive = the drive
;; Out: CurrentTrack = the track
;; Keeps: X
;; Also: MYSEEK (DOS33)
.proc SeekTrack
    pha
    ldy #DeviceTable::WHOLE_TRACKS
    lda (DctPointer),y
    ror a                           ; bit 0: two steps a track
    pla
    bcc SeekHalfTrack
    asl a
    jsr SeekHalfTrack
    lsr CurrentTrack
    rts
.endproc

;; Seeks to half-track A, keeping a record of each drive's place.
;;
;; All four phases go off first. The drive's record, <Drive1HalfTracks> or <Drive2HalfTracks> plus the slot,
;; becomes <CurrentTrack> for <DiskII::MoveHead> and then the new half-track.
;; In: A = the half-track, X = slot * 16, SelectedDrive = the drive
;; Keeps: X
;; Also: MYSEEK2 (DOS33)
.proc SeekHalfTrack

;; The half-track to seek to, held in <FoundTrack>'s byte while the phases go off and the record is read.
Target = FoundTrack

    ; The four phases off.
    sta Target
    lda Phase0Off,x
    lda Phase0Off + 2,x
    lda Phase0Off + 4,x
    lda Phase0Off + 6,x

    ; Where the head is, from the drive's record.
    jsr SlotNumber
    lda Drive1HalfTracks,y
    bit SelectedDrive
    bmi HavePosition
    lda Drive2HalfTracks,y
;; Also: WASD0 (DOS33)
HavePosition:
    sta CurrentTrack

    ; The record becomes the new half-track.
    lda Target
    bit SelectedDrive
    bmi RecordDrive1
    sta Drive2HalfTracks,y
    bpl Move                        ; always
;; Also: ISDRV1 (DOS33)
RecordDrive1:
    sta Drive1HalfTracks,y
;; Also: GOSEEK (DOS33)
Move:
    jmp DiskII::MoveHead
.endproc

;; Gives the slot number: slot * 16 shifted right four places.
;; In: X = slot * 16
;; Out: A = Y = the slot
;; Keeps: X
;; Also: XTOY (DOS33)
.proc SlotNumber
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    rts
.endproc

;; Records the IOB's drive as being on track A, without moving it: the half-track, track * 2, goes in its
;; <Drive1HalfTracks> or <Drive2HalfTracks> byte.
;; In: A = the track, X = slot * 16
;; Out: SelectedDrive = the IOB's drive
;; Keeps: X
;; Also: SETTRK (DOS33)
.proc SetTrack
    pha
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ror a
    ror SelectedDrive
    jsr SlotNumber
    pla
    asl a
    bit SelectedDrive
    bmi Drive1
    sta Drive2HalfTracks,y
    bpl Return                      ; always
;; Also: ONDRV1 (DOS33)
Drive1:
    sta Drive1HalfTracks,y
;; Also: SETRTS (DOS33)
Return:
    rts
.endproc
