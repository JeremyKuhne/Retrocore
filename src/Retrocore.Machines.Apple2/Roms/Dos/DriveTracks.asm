; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: seeking a drive and recording where its head is
;;
;; RWTS's helpers that keep the position of each drive's head in the screen holes, one byte per slot for each
;; drive (<Drive1HalfTracks>, <Drive2HalfTracks>): <SeekTrack> and <SeekHalfTrack> move the selected drive's head
;; through <DiskII::MoveHead> and record where it went, <SetTrack> records a position without moving the head, and
;; <SlotNumber> turns slot * 16 into the slot number that indexes the records. They follow <Rwts> (Rwts2.asm in DOS
;; 3.3, Rwts32.asm in DOS 3.2), at $BE5A-$BEAE where DOS 3.3 runs ($BE3B-$BE9B in DOS 3.2).
;;
;; The two versions' helpers are the same but in places, which <DOS32> chooses: DOS 3.3's seek can show a letter in
;; the diagnostic build, and DOS 3.2's turns the stepper's phases off before it seeks, since its <DiskII::MoveHead>
;; leaves the last one on.

;; Moves the head of the selected drive to track A, and records it as that drive's position.
;;
;; When bit 0 of the DCT's <DeviceTable::WHOLE_TRACKS> is set, as for the Disk II, a track is two half-tracks: it
;; doubles A, seeks, and halves CurrentTrack again, so that CurrentTrack is the track number, which RWTS compares
;; with the track an address field gives. Otherwise A goes to <SeekHalfTrack> as it is. It also uses what
;; <DiskII::MoveHead> uses.
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
;; DOS 3.2's turns all four phases off first, as its <DiskII::MoveHead> leaves the last one on, and holds the
;; half-track in <FoundTrack>'s byte rather than <TargetHalfTrack>'s. It also uses what <DiskII::MoveHead> uses.
;; In:    A = the half-track, X = slot * 16, SelectedDrive = the drive
;; Out:   CurrentTrack = A, and the drive's byte of <Drive1HalfTracks> or <Drive2HalfTracks> A
;; Uses:  A, Y, TargetHalfTrack
;; Keeps: X
;; Also: MYSEEK2 (DOS33)
.proc SeekHalfTrack
.if DOS32

;; The half-track to seek to, held in <FoundTrack>'s byte while the phases go off and the record is read: DOS 3.2's.
Target = FoundTrack

    sta Target
    lda Phase0Off,x                 ; the four phases off
    lda Phase0Off + 2,x
    lda Phase0Off + 4,x
    lda Phase0Off + 6,x
.else
    sta TargetHalfTrack
.endif
    jsr SlotNumber
    lda Drive1HalfTracks,y
    bit SelectedDrive
    bmi HavePosition                ; drive 1
    lda Drive2HalfTracks,y

;; Notes where the head is now.
;; Also: WASD0 (DOS33)
HavePosition:
    sta CurrentTrack
.if DOS32
    lda Target
.else
    lda TargetHalfTrack
.endif
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
