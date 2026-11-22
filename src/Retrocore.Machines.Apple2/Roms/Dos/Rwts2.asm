; retrocore: style=strict ignore=unlinked-name:RWTS -- the disk layer's name in prose
;; DOS 3.3 RWTS: read or write a track and sector, part two (Apple's RWTSTWO), and the head helpers
;;
;; The rest of <Rwts>, after Rwts1.asm has started the drive and moved the head: it carries out the IOB's command.
;; For a read or write it reads address fields until it finds the sector, checking that the head is on the right
;; track and the disk has the right volume, then reads or writes the data field behind it. When it cannot find the
;; sector it moves the head again, and as a last resort recalibrates, driving the head out to track 0 to find out
;; where it is. It ends by storing the return code in the IOB and turning the motor off. The helpers after it
;; (<SeekTrack>, <SeekHalfTrack>, <SlotNumber>, <SetTrack>) keep the position of each drive's head in the screen
;; holes. At $BDAB-$BEAE where DOS runs. Formatting is in Formatter.asm.

; Rwts, part two: the command. These constants are Rwts's too.

;; The count <RetriesLeft> starts at for each seek, 48: RWTS reads up to 49 address fields before it gives up on
;; the track.
ADDRESS_TRIES = $30

;; The track a recalibration pretends the head is on, 96: half-track $C0, further in than any track, so that the
;; seek to track 0 steps the head out until it stops against track 0, wherever it was.
RECALIBRATE_TRACK = $60

;; The opcode of BIT zero page, $24, written as a byte so that the one-byte instruction after it is its operand
;; and is skipped.
BIT_ZERO_PAGE = $24

;; Carries out the IOB's command once the head is on the track: seek only, read, write or format.
;;
;; For a write the sector is split into six-bit values first, as there is no time for it between the address field
;; and the data field. Then RWTS reads address fields, at most 49 tries for the track, counting failed reads, other
;; sectors and failed data reads alike. An address field from the wrong track means the head is not where RWTS
;; thought: it records where the head really is and seeks again, up to MAX_SEEKS - 1 times; after that, or when the
;; tries run out, it recalibrates, once. A sector it cannot read ends, after the recalibration, as
;; <RWTS_DRIVE_ERROR>: this RWTS never returns <RWTS_READ_ERROR>.
;;
;; The flags pushed after reading the command (carry set to read, clear to write) stay on the stack until the
;; sector is found; <GotSector> pulls them. Its results are as for RWTS.
;; In:    X = slot * 16, the IOB as for RWTS, the drive running on the track
;; Also: TRYTRK (DOS33)
TryTrack:
    ldy #Iob::COMMAND
    lda (IobPointer),y
    beq SeekOnly                    ; seek only: done
    cmp #RWTS_FORMAT
    beq Format
    ror a                           ; bit 0 into the carry: set to read, clear to write
    php
    bcs StartTries
.if DIAGNOSTIC_RWTS
    ldy #LETTER_PRENIBBLE
    sty PreNibbleAt
.endif
    jsr DiskII::PreNibble           ; writing: split the caller's sector into HighBits and LowBits now
.if DIAGNOSTIC_RWTS
    ldy #DIAG_BLANK
    sty PreNibbleAt
.endif

;; Starts the tries for the track.
;; Also: TRYTRK2 (DOS33)
StartTries:
    ldy #ADDRESS_TRIES
    sty RetriesLeft

;; Reads the next address field.
;; Also: TRYADR (DOS33)
TryAddress:
    ldx SlotTimes16
.if DIAGNOSTIC_RWTS
    lda #LETTER_ADDRESS
    sta AddressAt
    lda #DIAG_BLANK
    sta AddressErrorAt
.endif
    jsr DiskII::ReadAddressField
.if DIAGNOSTIC_RWTS
    lda #DIAG_BLANK
    sta AddressAt
.endif
    bcc CheckTrack
.if DIAGNOSTIC_RWTS
    lda #LETTER_ADDRESS_ERROR
    sta AddressErrorAt
.endif

;; Counts a failed try, and tries again while any are left.
;; Also: TRYADR2 (DOS33)
NextTry:
    dec RetriesLeft
    bpl TryAddress

    ; Out of tries: recalibrate. Pretend the head is at half-track $C0, more than the disk has, and seek to track 0:
    ; the head steps out until it stops against track 0, wherever it was. Then seek to the track again.
;; Recalibrates, unless it has done so once already: drives the head out to track 0, then seeks the track again.
;; Also: RECAL (DOS33)
Recalibrate:
    lda CurrentTrack
    pha                             ; the track wanted
    lda #RECALIBRATE_TRACK
    jsr SetTrack
    dec RecalibrationsLeft
    beq DriveError                  ; recalibrated once already
    lda #MAX_SEEKS
    sta SeeksLeft
    lda #0
    jsr SeekTrack
    pla

;; Seeks the track wanted, in A, and starts the tries again.
;; Also: RESEEK (DOS33)
SeekAgain:
    jsr SeekTrack
    jmp StartTries

;; An address field was read: is it from the track wanted? If not, notes where the head really is and seeks again.
;; Also: RDRIGHT (DOS33)
CheckTrack:
    ldy FoundTrack
    cpy CurrentTrack
    beq RightTrack
    lda CurrentTrack
    pha                             ; the track wanted
    tya
    jsr SetTrack                    ; the track the head is really on
    pla
    dec SeeksLeft
    bne SeekAgain
    beq Recalibrate                 ; always

;; The track cannot be read: fails with <RWTS_DRIVE_ERROR>, dropping the track wanted from the stack.
;; Also: DRVERR (DOS33)
DriveError:
    pla
    lda #RWTS_DRIVE_ERROR

;; Drops the read or write flags from the stack, then fails with the return code in A.
;; Also: JMPTO1 (DOS33)
FailWithFlags:
    plp
    jmp Fail

;; The command was to seek only: done.
;; Also: GALLDONE (DOS33)
SeekOnly:
    beq Succeed                     ; always: the command was 0

;; Formats the disk: <Formatter::Format> returns from RWTS.
;; Also: FORMDSK (DOS33)
Format:
    jmp Formatter::Format

;; The right track: stores the volume found in the IOB, and checks it against the IOB's volume unless that is 0.
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

;; The right volume: is it the sector wanted? The IOB's sector is DOS's number; <PhysicalSectors> gives the number
;; in the address field.
;; Also: CORRECTVOL (DOS33)
RightVolume:
    ldy #Iob::SECTOR
    lda (IobPointer),y
    tay
    lda a:PhysicalSectors,y
    cmp FoundSector

    ; The diagnostic build counts the wrong sectors that pass, once a first sector has been found.
.if DIAGNOSTIC_RWTS
    beq GotSector
    lda #LETTER_WRONG_SECTOR
    sta WrongSectorAt
    lda SectorsSeen
    beq NotCounted
    inc SectorsMissed

;; Goes on to the next try, the wrong sector counted or not.
;; Also: NOLAT (DOS33)
NotCounted:
    jmp NextTry
.else
    bne NextTry
.endif

;; Found: reads or writes its data field.
;; Also: GOTSECT (DOS33)
GotSector:
.if DIAGNOSTIC_RWTS
    lda #DIAG_BLANK
    sta WrongSectorAt
    inc SectorsSeen
.endif
    plp                             ; carry set: read
    bcc Write
.if DIAGNOSTIC_RWTS
    lda #LETTER_READ
    sta ReadAt
    lda #DIAG_BLANK
    sta DataErrorAt
.endif
    jsr DiskII::ReadDataField
.if DIAGNOSTIC_RWTS
    lda #DIAG_BLANK
    sta ReadAt
.endif

    ; Push the reader's flags: on an error the carry is set, which says "read" again when GotSector pulls them next
    ; time.
    php
.if DIAGNOSTIC_RWTS
    bcc GoodRead
    lda #LETTER_DATA_ERROR
    sta DataErrorAt
    jmp NextTry

;; The data field was read.
;; Also: GOODREAD (DOS33)
GoodRead:
.else
    bcs NextTry
.endif

    ; Read: rebuild all 256 bytes in the caller's buffer.
    plp
    ldx #0
    stx RebuildCount
.if DIAGNOSTIC_RWTS
    lda #LETTER_POSTNIBBLE
    sta PostNibbleAt
.endif
    jsr DiskII::PostNibble
.if DIAGNOSTIC_RWTS
    lda #DIAG_BLANK
    sta PostNibbleAt
.endif
    ldx SlotTimes16

;; RWTS's exit: stores A in the IOB's return code, turns the motor off and returns, with the carry clear here or
;; set from <Fail>.
;;
;; The byte after the CLC is the opcode of BIT zero page: with the SEC that follows as its operand, it reads byte
;; $38 and skips the SEC, changing only the negative, overflow and zero flags. The success exit stores whatever A
;; holds, which is 0 only for a seek: after a read it is the sector's last byte, after a write a byte read from the
;; card. The file manager reads the return code only when the carry is set.
;; In:    A = the return code, X = slot * 16, IobPointer = the IOB
;; Out:   carry = clear here, set from Fail
;; Entry: Fail = the error exit
;; Also: ALLDONE (DOS33)
Succeed:
    clc
    .byte BIT_ZERO_PAGE             ; skips the SEC

;; RWTS's error exit: stores A in the IOB's return code, turns the motor off and returns with the carry set.
;; In:    A = the return code, X = slot * 16, IobPointer = the IOB
;; Out:   carry = set
;; Also: HNDLERR (DOS33)
Fail:
    sec
    ldy #Iob::RETURN_CODE
    sta (IobPointer),y
    lda MotorOff,x

    ; The diagnostic build shows SectorsMissed / SectorsSeen, the average number of wrong sectors before the right
    ; one, as a hex digit, and clears the ^.
.if DIAGNOSTIC_RWTS
    lda SectorsMissed
    ldy #0

;; Divides by subtracting, counting in Y.
;; Also: DIVIDE (DOS33)
Divide:
    cmp SectorsSeen
    bcc ShowAverage
    sbc SectorsSeen
    iny
    bne Divide

;; Turns the quotient's low digit into a character.
;; Also: PRTLAT (DOS33)
ShowAverage:
    tya
    and #$0F
    ora #'0' | $80                  ; "0" to "9"...
    cmp #('9' | $80) + 1
    bcc StoreDigit
    adc #'A' - '9' - 2              ; ...or "A" to "F" (the carry adds 1)

;; Shows the digit and clears the ^.
;; Also: PRTL2 (DOS33)
StoreDigit:
    sta AverageAt
    lda #DIAG_BLANK
    sta RunningAt
.endif
    rts

;; Writes the data field, from HighBits and LowBits; the data field writer fails only on a write-protected disk.
;; Also: WRIT (DOS33)
Write:
.if DIAGNOSTIC_RWTS
    lda #LETTER_WRITE
    sta WriteAt
.endif
    jsr DiskII::WriteDataField
.if DIAGNOSTIC_RWTS
    lda #DIAG_BLANK
    sta WriteAt
.endif
    bcc Succeed
    lda #RWTS_WRITE_PROTECTED
    bcs Fail                        ; always
.endproc

;; Moves the head of the selected drive to track A, and records it as that drive's position.
;;
;; When bit 0 of the DCT's <DeviceTable::WHOLE_TRACKS> is set, as for the Disk II, a track is two half-tracks: it
;; doubles A, seeks, and halves CurrentTrack again, so that CurrentTrack is the track number. Otherwise A goes to
;; <SeekHalfTrack> as it is. It also uses what <DiskII::MoveHead> uses.
;; In:    A = the track, X = slot * 16, SelectedDrive = the drive, DctPointer = the DCT
;; Out:   CurrentTrack = the track, and the drive's byte of <Drive1HalfTracks> or <Drive2HalfTracks> its half-track
;; Uses:  A, Y, TargetHalfTrack
;; Keeps: X
;; Also: MYSEEK (DOS33)
.proc SeekTrack
    pha
.if DIAGNOSTIC_RWTS
    lda #Rwts::LETTER_SEEK
    sta Rwts::SeekAt
.endif
    ldy #DeviceTable::WHOLE_TRACKS
    lda (DctPointer),y
    ror a                           ; bit 0 into the carry
    pla
    bcc SeekHalfTrack
    asl a                           ; the track's half-track
    jsr SeekHalfTrack
    lsr CurrentTrack                ; back to a track
.if DIAGNOSTIC_RWTS
    lda #Rwts::DIAG_BLANK
    sta Rwts::SeekAt
.endif
    rts
.endproc

;; Seeks the selected drive's head to half-track A from the position recorded for it, recording A as its new one.
;;
;; It also uses what <DiskII::MoveHead> uses.
;; In:    A = the half-track, X = slot * 16, SelectedDrive = the drive
;; Out:   CurrentTrack = A, and the drive's byte of <Drive1HalfTracks> or <Drive2HalfTracks> A
;; Uses:  A, Y, TargetHalfTrack
;; Keeps: X
;; Also: MYSEEK2 (DOS33)
.proc SeekHalfTrack
    sta TargetHalfTrack
    jsr SlotNumber
    lda Drive1HalfTracks,y
    bit SelectedDrive
    bmi HavePosition                ; drive 1
    lda Drive2HalfTracks,y

;; Notes where the head is now.
;; Also: WASD0 (DOS33)
HavePosition:
    sta CurrentTrack
    lda TargetHalfTrack
    bit SelectedDrive
    bmi RecordDrive1
    sta Drive2HalfTracks,y          ; where it will be
    bpl Move                        ; always

;; Records drive 1's new position.
;; Also: ISDRV1 (DOS33)
RecordDrive1:
    sta Drive1HalfTracks,y

;; Moves the head.
;; Also: GOSEEK (DOS33)
Move:
    jmp DiskII::MoveHead
.endproc

;; Turns slot * 16 in X into the slot number in Y.
;; In:    X = slot * 16
;; Out:   Y = A = the slot
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

;; Records that the head of the drive the IOB names is on track A: stores A times 2, the half-track, in the
;; drive's byte of <Drive1HalfTracks> or <Drive2HalfTracks>.
;;
;; It also sets <SelectedDrive> from the IOB's drive.
;; In:    A = the track, X = slot * 16, IobPointer = the IOB
;; Out:   SelectedDrive = bit 7 set for drive 1
;; Uses:  A, Y
;; Keeps: X
;; Entry: SetHalfTrack = stores A as it is, for the drive in SelectedDrive, with Y = the slot
;; Also: SETTRK (DOS33)
.proc SetTrack
    pha
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ror a
    ror SelectedDrive               ; bit 0 of the drive number into bit 7: set for drive 1
    jsr SlotNumber
    pla
    asl a                           ; the half-track

;; Stores half-track A for the drive in <SelectedDrive>. Nothing calls it.
;; Also: SETTRK2 (DOS33)
SetHalfTrack:
    bit SelectedDrive
    bmi Drive1
    sta Drive2HalfTracks,y
    bpl Return                      ; always

;; Stores it for drive 1.
;; Also: ONDRV1 (DOS33)
Drive1:
    sta Drive1HalfTracks,y

;; Also: SETRTS (DOS33)
Return:
    rts
.endproc
