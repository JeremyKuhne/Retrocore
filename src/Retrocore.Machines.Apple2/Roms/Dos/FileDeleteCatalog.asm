; retrocore: style=strict
;; DOS 3.3 and 3.2 file manager: LOCK, UNLOCK, POSITION, VERIFY, DELETE and CATALOG, and the work area's copies
;;
;; Apple's FDELCAT module, at $ACEF-$AE8D where DOS runs: the file manager's requests that work on a file as a
;; whole, which <CallFileManager::ForDos> reaches through <FileManager::RequestHandlers>, and the two routines that
;; move a file's work area between the file's DOS buffer and <FileManager::FileControlBlock>:
;; <FileManager::LoadWorkArea> at every entry and <FileManager::SaveWorkArea> at every exit.
;;
;; A catalog entry is laid out as <CatalogEntry>: the track and sector of the file's first track/sector list, the
;; type with <FILE_LOCKED> set when the file is locked, the name and the length in sectors. docs/Dos.md describes
;; the catalog and the track/sector lists.

; The file manager: locking, positioning, verifying, deleting, the catalog, and the work area.
.scope FileManager continued

;; The lines CATALOG prints before it first waits for a key, the heading's among them.
CATALOG_FIRST_PAGE_LINES = 22

;; The lines CATALOG prints before each later wait.
CATALOG_PAGE_LINES = 21

;; <DosFileParameters::Volume>'s value for any volume, which <FileControlBlock::VolumeComplement> holds
;; complemented.
ANY_VOLUME = 0

;; The LOCK request: sets <FILE_LOCKED> in the type in the file's catalog entry, which stops WRITE, RENAME and
;; DELETE.
;;
;; The errors of <OpenFile> leave the file manager.
;; In: DosFileParameters::Name = the address of the name, and the disk, as for <OpenFile>
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FLOCK (DOS33, DOS31)
.proc Lock
    lda #FILE_LOCKED
    sta Scratch3
    bne ChangeLock                  ; always
.endproc

;; The UNLOCK request: clears <FILE_LOCKED> in the type in the file's catalog entry.
;;
;; The errors of <OpenFile> leave the file manager.
;; In: DosFileParameters::Name = the address of the name, and the disk, as for <OpenFile>
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FUNLCK (DOS33, DOS31)
.proc Unlock
    lda #0
    sta Scratch3
    ; Falls into ChangeLock.
.endproc

;; Gives the file's type the lock bit in <Scratch3>, for <Lock> and <Unlock>, and writes the catalog sector back.
;;
;; <OpenFile> leaves the entry's catalog sector in <CatalogBuffer> and its offset in <Scratch1>.
;; In: Scratch3 = <FILE_LOCKED> or 0, DosFileParameters::Name = the address of the name, and the disk
;; Out: DosFileParameters::ReturnCode = 0
;; Also: LCKGO (DOS33, DOS31)
.proc ChangeLock
    jsr OpenFile
    ldx Scratch1
    lda CatalogBuffer::Entries + CatalogEntry::TYPE,x
    and #<~FILE_LOCKED
    ora Scratch3
    sta CatalogBuffer::Entries + CatalogEntry::TYPE,x
    jsr WriteCatalogSector
    ; Falls into ToSucceed.
.endproc

;; Goes on to <Succeed>: the end of <ChangeLock>, which <Verify> branches to.
;; Also: GOGOOD (DOS33)
ToSucceed:
    jmp Succeed

;; The POSITION request: sets the file's position from the record number and the byte offset, ready for the next
;; READ or WRITE. Nothing is read from the disk until then.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte in the record
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FPOSTN (DOS33, DOS31)
.proc Position
    jsr SetPosition
    jmp Succeed
.endproc

;; The VERIFY request: reads every data sector of the file, to show that each can be read.
;;
;; It steps <FileControlBlock::PositionSector> from the file's first sector and lets <LocateNextByte> read each
;; one, until a sector the track/sector lists don't name: the end of the file, or the first gap in a random-access
;; file. The errors of <OpenFile>, and disk errors (<AccessDisk>), leave the file manager.
;; In: DosFileParameters::Name = the address of the name, and the disk, as for <OpenFile>
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FVAR (DOS33, DOS31)
.proc Verify
    jsr OpenFile

;; Reads the next sector, until one is not in the file.
;; Also: VAR1 (DOS33, DOS31)
NextSector:
    jsr LocateNextByte
    bcs ToSucceed
    inc FileControlBlock::PositionSector
    bne NextSector
    inc FileControlBlock::PositionSector + 1
    jmp NextSector
.endproc

;; The DELETE request: removes a file from the catalog and gives its sectors back to the VTOC.
;;
;; The catalog entry is marked deleted, <ENTRY_DELETED> in its track byte, and the track it held is kept in the
;; name's last character. Then each track/sector list is read in turn: every data sector it names, and the list's
;; own sector, are marked free in the VTOC in memory, which is written once at the end. A locked file is refused with
;; <ERROR_FILE_LOCKED>; the errors of <OpenFile>, and disk errors (<AccessDisk>), leave the file manager.
;; In: DosFileParameters::Name = the address of the name, and the disk, as for <OpenFile>
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FDEL (DOS33, DOS31)
.proc Delete
    jsr OpenFile

;; Refuses a locked file.
;; Also: FD2 (DOS33, DOS31)
CheckLocked:
    ldx Scratch1
    lda CatalogBuffer::Entries + CatalogEntry::TYPE,x
    bpl MarkDeleted
    jmp FileLocked

;; Marks the entry deleted, keeping the first list's track over the name's last character, and writes the catalog
;; sector.
;; Also: FD3 (DOS33, DOS31)
MarkDeleted:
    ldx Scratch1
    lda CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    sta FileControlBlock::FirstListTrack
    sta CatalogBuffer::Entries + CatalogEntry::NAME + CATALOG_NAME_LENGTH - 1,x
    lda #ENTRY_DELETED
    sta CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    ldy CatalogBuffer::Entries + CatalogEntry::LIST_SECTOR,x
    sty FileControlBlock::FirstListSector
    jsr WriteCatalogSector

    ; The first list, then (carry set) each next one.
    clc

;; Reads the next track/sector list, and frees the sectors it names.
;; Also: FD4 (DOS33, DOS31)
NextList:
    jsr ReadList
    bcs Finish
    jsr PointAtListBuffer
    ldy #TrackSectorList::PAIRS

;; Frees the pair's sector, unless its track is 0 (no sector) or $80 or more.
;; Also: FD5 (DOS33, DOS31)
NextPair:
    sty Scratch1
    lda (FilePointer),y
    bmi SkipPair
    beq SkipPair
    pha
    iny
    lda (FilePointer),y
    tay
    pla
    jsr FreeSector

;; Steps to the next pair, until Y wraps past the last.
;; Also: FD6 (DOS33, DOS31)
SkipPair:
    ldy Scratch1
    iny
    iny
    bne NextPair

    ; Then the list's own sector.
    lda FileControlBlock::ListTrack
    ldy FileControlBlock::ListSector
    jsr FreeSector
    sec
    bcs NextList                    ; always

;; Writes the VTOC, with every sector freed, once the last list is done.
;; Also: FD7 (DOS33, DOS31)
Finish:
    jsr WriteVtoc
    jmp Succeed
.endproc

;; Marks one sector free in the VTOC in memory.
;;
;; <MergeFreeMap> builds the sector's bit in <FileControlBlock::ReservedMap> and merges it into the track's map in
;; the VTOC; then the reservation is cleared, with <FileControlBlock::ReservedSector> and
;; <FileControlBlock::ReservedTrack>, so the next sector starts from nothing. DOS 3.3 clears all four map bytes, as many
;; as a track of 32 sectors would need; DOS 3.2 the first two, enough for its tracks of 13 sectors.
;; In: A = the track, Y = the sector
;; Also: FDSUB (DOS33, DOS31)
.proc FreeSector
    sec
    jsr MergeFreeMap

    ; Clear the reservation.
    lda #0
.if DOS32
    ldx #FileControlBlock::ReservedMap + 1 - FileControlBlock::ReservedSector
.else
    ldx #FileControlBlock::ReservedMap + FREE_MAP_BYTES_PER_TRACK - 1 - FileControlBlock::ReservedSector
.endif

;; Clears a byte of the reservation, the last first.
;; Also: FDS1 (DOS33, DOS31)
ClearMap:
    sta FileControlBlock::ReservedSector,x
    dex
    bpl ClearMap
    rts
.endproc

;; The CATALOG request: prints the disk's volume number and a line for each file in the catalog.
;;
;; Each line is a "*" for a locked file or a space, the type's letter, the length in sectors as three digits, and
;; the name. Output goes through <CharacterOut>, and so through DOS's output hook, and <NewLine> waits for a key each
;; time a screenful has been printed. The volume asked for is set to any, and the number printed is the one RWTS
;; found on the disk. Disk errors leave the file manager (<AccessDisk>).
;; In: DosFileParameters::Drive, DosFileParameters::Slot = the disk
;; Out: DosFileParameters::ReturnCode = 0, DosFileParameters::Volume = the disk's volume number
;; Also: RDIR (DOS33, DOS31)
.proc Catalog
    jsr SetUpWorkArea
    lda #ANY_VOLUME ^ $FF
    sta FileControlBlock::VolumeComplement

    ; The VTOC, for the catalog's first track and sector.
    jsr ReadVtoc
    lda #CATALOG_FIRST_PAGE_LINES
    sta Scratch2

    ; The heading: "DISK VOLUME", stored backward, and the volume number.
    jsr NewLine
    jsr NewLine
    ldx #VOLUME_MESSAGE_LAST

;; Prints the heading's characters, from the last stored.
;; Also: RD0 (DOS33, DOS31)
PrintHeading:
    lda VolumeMessage,x
    jsr CharacterOut
    dex
    bpl PrintHeading

    ; X is $FF, but PrintNumber looks only at the low byte. The volume is the one RWTS read from the disk.
    stx ParsedNumber + 1
    lda DosIob::VolumeFound
    sta ParsedNumber
    jsr PrintNumber
    jsr NewLine
    jsr NewLine

    ; The first catalog sector, then each next one.
    clc

;; Reads the next catalog sector.
;; Also: RD1 (DOS33, DOS31)
NextCatalogSector:
    jsr ReadCatalogSector
    bcs Done
    ldx #0

;; Stops at an entry never used, the end of the catalog, and skips a deleted one.
;; Also: RD2 (DOS33, DOS31)
ShowEntry:
    stx Scratch1
    lda CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    beq Done
    bmi SkipEntry

    ; A "*" when locked, or a space.
    ldy #' ' | $80
    lda CatalogBuffer::Entries + CatalogEntry::TYPE,x
    bpl PrintLock
    ldy #'*' | $80

;; Prints the lock's character.
;; Also: RD2A (DOS33, DOS31)
PrintLock:
    tya
    jsr CharacterOut

    ; The type's letter. A type has one bit set, or none for a text file: find the highest of bits 6 to 0, as Y = 7
    ; to 1, and print TypeLetters,Y, or T when no bit is set (Y = 0).
    lda CatalogBuffer::Entries + CatalogEntry::TYPE,x
    and #<~FILE_LOCKED
    ldy #7
    asl a

;; Shifts the type left until its highest bit leaves.
;; Also: RD2B (DOS33, DOS31)
FindTypeBit:
    asl a
    bcs PrintType
    dey
    bne FindTypeBit

;; Prints the type's letter, then the length in sectors.
;; Also: RD2C (DOS33, DOS31)
PrintType:
    lda TypeLetters,y
    jsr CharacterOut
    lda #' ' | $80
    jsr CharacterOut

    ; Three digits: a length of 256 or more is shown less a multiple of 256.
    lda CatalogBuffer::Entries + CatalogEntry::LENGTH,x
    sta ParsedNumber
    lda CatalogBuffer::Entries + CatalogEntry::LENGTH + 1,x
    sta ParsedNumber + 1
    jsr PrintNumber
    lda #' ' | $80
    jsr CharacterOut

    ; X to the name.
    inx
    inx
    inx
    ldy #CATALOG_NAME_LENGTH - 1

;; Prints the name's characters.
;; Also: RD3 (DOS33, DOS31)
PrintName:
    lda CatalogBuffer::Entries,x
    jsr CharacterOut
    inx
    dey
    bpl PrintName

;; Ends the line. Nothing refers to Apple's label.
;; Also: RD3A (DOS33, DOS31)
EndLine:
    jsr NewLine

;; Steps to the next entry, or the next sector after the last.
;; Also: RD4 (DOS33, DOS31)
SkipEntry:
    jsr StepEntry
    bcc ShowEntry
    bcs NextCatalogSector

;; Succeeds.
;; Also: RD5 (DOS33, DOS31)
Done:
    jmp Succeed
.endproc

;; Prints a carriage return for CATALOG, and waits for a key when the screen is full.
;;
;; <Scratch2> counts the lines left: <CATALOG_FIRST_PAGE_LINES> for the first screen, which holds the heading, then
;; <CATALOG_PAGE_LINES>.
;; In: Scratch2 = the lines left on the screen
;; Out: Scratch2 = the lines left after this one
;; Also: PRCR (DOS33, DOS31)
.proc NewLine
    lda #KEY_RETURN
    jsr CharacterOut
    dec Scratch2
    bne Done
    jsr ReadKey
    lda #CATALOG_PAGE_LINES
    sta Scratch2

;; The return.
;; Also: PRCR1 (DOS33, DOS31)
Done:
    rts
.endproc

;; Prints the low byte of <ParsedNumber> as three decimal digits, with leading zeros.
;;
;; Each digit is counted by subtracting its power of ten, from <PowersOfTen>, while the low byte is not less than
;; it. Only the low byte is compared, so a number of 256 or more prints as itself less a multiple of 256.
;; In: ParsedNumber = the number
;; Out: ParsedNumber = what is left after the digits
;; Also: PRNUM (DOS33, DOS31)
.proc PrintNumber
    ; Hundreds, tens and ones: the index of each digit's power of ten.
    ldy #2

;; Starts a digit, kept on the stack, at 0.
;; Also: PRN1 (DOS33, DOS31)
NextDigit:
    lda #0
    pha

;; Subtracts the digit's power of ten while it fits, counting.
;; Also: PRN2 (DOS33, DOS31)
Subtract:
    lda ParsedNumber
    cmp PowersOfTen,y
    bcc PrintDigit
    sbc PowersOfTen,y
    sta ParsedNumber
    lda ParsedNumber + 1
    sbc #0
    sta ParsedNumber + 1

    ; The carry is set here: one more.
    pla
    adc #0
    pha
    jmp Subtract

;; Prints the digit, "0" to "9".
;; Also: PRN3 (DOS33, DOS31)
PrintDigit:
    pla
    ora #'0' | $80
    jsr CharacterOut
    dey
    bpl NextDigit
    rts
.endproc

;; Copies the open file's work area from its DOS buffer into <FileControlBlock>, and clears the return code.
;;
;; <CallFileManager::ForDos> calls it at every entry, so <DosFileParameters::WorkArea> must point at a 45-byte work
;; area for every request, even those that use no file.
;; In: DosFileParameters::WorkArea = the address of the file's work area
;; Out: carry = clear, DosFileParameters::ReturnCode = 0, FilePointer = the work area
;; Also: CLCFCB (DOS33, DOS31)
.proc LoadWorkArea
    jsr PointAtWorkArea
    ldy #0
    sty DosFileParameters::ReturnCode

;; Copies a byte.
;; Also: CF3 (DOS33, DOS31)
CopyByte:
    lda (FilePointer),y
    sta FileControlBlock,y
    iny
    cpy #FILE_CONTROL_SIZE
    bne CopyByte
    clc
    rts
.endproc

;; Copies <FileControlBlock> back into the open file's work area, keeping the file manager's state for the next
;; request. <Leave> calls it on every exit.
;; In: DosFileParameters::WorkArea = the address of the file's work area
;; Out: FilePointer = the work area
;; Also: RTNFCB (DOS33, DOS31)
.proc SaveWorkArea
    jsr PointAtWorkArea
    ldy #0

;; Copies a byte.
;; Also: RF1 (DOS33, DOS31)
CopyByte:
    lda FileControlBlock,y
    sta (FilePointer),y
    iny
    cpy #FILE_CONTROL_SIZE
    bne CopyByte
    rts
.endproc

.endscope
