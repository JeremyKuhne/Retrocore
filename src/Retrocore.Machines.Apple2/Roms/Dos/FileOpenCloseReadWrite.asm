; retrocore: style=strict
;; DOS 3.3 and 3.2 file manager: OPEN, CLOSE, RENAME, READ and WRITE
;;
;; Apple's FOPCLRW module, at $AB22-$ACEE where DOS runs: the file manager's requests that use a file's contents.
;; <CallFileManager::ForDos> reaches each through <FileManager::RequestHandlers>, and READ and WRITE go on through
;; <FileManager::ReadHandlers> and <FileManager::WriteHandlers>. Every request ends at <FileManager::Succeed> or one
;; of the error exits, which save the work area back into the file's buffer and return to the file manager's caller.
;;
;; <FileManager::OpenFile>, which every request on a named file starts with, works on the catalog (docs/Dos.md):
;; each catalog sector holds seven file entries, laid out as <CatalogEntry>. Reading and writing go a byte at a time
;; through <FileManager::LocateNextByte>, which keeps the right data sector in the file's data buffer, reading it,
;; or for WRITE allocating it, when the position moves into another sector.

; The file manager: opening, closing and renaming a file, and reading and writing it.
.scope FileManager continued

;; <FileControlBlock::DataRelativeSector>'s two bytes when no data sector is in the buffer: $FFFF.
NO_DATA_SECTOR = $FF

;; The OPEN request: finds or creates the file and gets it ready for reading and writing.
;; In: DosFileParameters = the request, as for <OpenFile>
;; Out: DosFileParameters::FileType = the file's type, DosFileParameters::ReturnCode = 0, or
;;   <ERROR_FILE_NOT_FOUND> with the carry clear when the file was created
;; Errors: carry = set, with DosFileParameters::ReturnCode = an ERROR_ code from <OpenFile>
;; Also: FOPEN (DOS33, DOS31)
.proc Open
    jsr OpenFile
    jmp Succeed
.endproc

;; Finds the file <DosFileParameters::Name> names in the catalog, creating it if the command may, and sets up the
;; work area for it.
;;
;; A file is created only when the command <CommandOffset> names may create files (bit 0 of its entry in the
;; command tables): for DOS's commands that is INIT, SAVE, OPEN and BSAVE, and <CallFileManager> sets the offset to
;; INIT's or LOAD's. A new file gets one sector, for an empty track/sector list, and the type in
;; <DosFileParameters::FileType>. Its name is in the catalog entry already: <FindFile> put it in the free entry it
;; found when the name was missing.
;;
;; On return the catalog sector holding the entry is in <CatalogBuffer>, and <CurrentCatalogTrack> and
;; <CurrentCatalogSector> say where it is on the disk, so the requests that change the entry can write it back with
;; <WriteCatalogSector>. LOCK, UNLOCK, RENAME, DELETE and VERIFY start with it too. Errors leave the file manager:
;; <ERROR_FILE_NOT_FOUND> when the file is missing and may not be created, or <ERROR_LANGUAGE_NOT_AVAILABLE> instead
;; while FP looks for its APPLESOFT file (<INPUT_STATE_STARTING_RAM_APPLESOFT>); <ERROR_DISK_FULL>; and the disk
;; errors of <AccessDisk>.
;; In: DosFileParameters::Name = the address of the name, 30 characters, DosFileParameters::RecordLength = the
;;   record length, 0 for 256, DosFileParameters::Volume/DosFileParameters::Drive/DosFileParameters::Slot = the
;;   disk, DosFileParameters::FileType = the type for a new file
;; Out: carry = clear, Scratch1 = the entry's offset in <CatalogBuffer::Entries>, FileControlBlock::EntryOffset = the
;;   same, DosFileParameters::FileType = the file's type, FileControlBlock::FileType = the same,
;;   DosFileParameters::ReturnCode = <ERROR_FILE_NOT_FOUND> when the file was created; the list buffer holds the
;;   first track/sector list
;; Also: DOPEN (DOS33, DOS31)
.proc OpenFile
    jsr SetUpWorkArea

    ; RWTS moves 256 bytes a sector.
    lda #>SECTOR_SIZE
    sta FileControlBlock::SectorLength + 1

    ; The record length, where 0 means 256.
    ldx DosFileParameters::RecordLength + 1
    lda DosFileParameters::RecordLength
    bne StoreRecordLength
    cpx #0
    bne StoreRecordLength
    inx

;; Stores the record length.
;; Also: F02 (DOS33, DOS31)
StoreRecordLength:
    sta FileControlBlock::RecordLength
    stx FileControlBlock::RecordLength + 1

    ; Find the file. Carry clear: found, X = its entry.
    jsr FindFile
    bcc CopyEntry

    ; Not found: X is the free entry FindFile put the name in. Create the file if the command may: bit 0 of its
    ; entry in the command tables.
    stx Scratch1
    ldx CommandOffset
    lda CommandSyntax,x
    ldx Scratch1
    lsr a
    bcs Create

    ; It may not. FP looking for the RAM Applesoft (MiscCommands.asm, EAS2) reports a missing language instead.
    lda InputState
    cmp #INPUT_STATE_STARTING_RAM_APPLESOFT
    bne ToFileNotFound
    jmp LanguageNotAvailable

;; Goes on to <FileNotFound>.
;; Also: F02A (DOS33)
ToFileNotFound:
    jmp FileNotFound

;; Creates the file: one sector, for its track/sector list, which becomes its first and current list.
;; Also: F02B (DOS33)
Create:
    lda #0
    sta CatalogBuffer::Entries + CatalogEntry::LENGTH + 1,x
    lda #1
    sta CatalogBuffer::Entries + CatalogEntry::LENGTH,x
    stx Scratch1
    jsr AllocateSector
    ldx Scratch1
    sta CatalogBuffer::Entries + CatalogEntry::LIST_SECTOR,x
    sta FileControlBlock::FirstListSector
    sta FileControlBlock::ListSector
    lda FileControlBlock::ReservedTrack
    sta CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    sta FileControlBlock::FirstListTrack
    sta FileControlBlock::ListTrack
    lda DosFileParameters::FileType
    sta CatalogBuffer::Entries + CatalogEntry::TYPE,x

    ; Write the catalog sector with the new entry, then an empty track/sector list to the new sector.
    jsr WriteCatalogSector
    jsr PointAtListBuffer
    jsr ClearSector
    jsr WriteList

    ; Report the file as not found, though it now exists.
    ldx Scratch1
    lda #ERROR_FILE_NOT_FOUND
    sta DosFileParameters::ReturnCode

;; Copies what the entry says about the file into the work area, then reads the first track/sector list.
;; Also: F03 (DOS33, DOS31)
CopyEntry:
    lda CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    sta FileControlBlock::FirstListTrack
    lda CatalogBuffer::Entries + CatalogEntry::LIST_SECTOR,x
    sta FileControlBlock::FirstListSector
    lda CatalogBuffer::Entries + CatalogEntry::TYPE,x
    sta DosFileParameters::FileType
    sta FileControlBlock::FileType
    lda CatalogBuffer::Entries + CatalogEntry::LENGTH,x
    sta FileControlBlock::SectorCount
    lda CatalogBuffer::Entries + CatalogEntry::LENGTH + 1,x
    sta FileControlBlock::SectorCount + 1
    stx FileControlBlock::EntryOffset

    ; No data sector in the buffer yet.
    lda #NO_DATA_SECTOR
    sta FileControlBlock::DataRelativeSector
    sta FileControlBlock::DataRelativeSector + 1

    ; The sectors one track/sector list covers, 122. Only the low byte is copied: the high byte is 0 from
    ; SetUpWorkArea.
    lda VtocBuffer::PairsPerList
    sta FileControlBlock::PairsPerList

    ; Read the first track/sector list.
    clc
    jmp ReadList
.endproc

;; Clears the work area and fills in the disk to use from the parameter list.
;;
;; The volume number is kept complemented in <FileControlBlock::VolumeComplement>; <AccessDisk> complements it
;; again for RWTS, so 0, any volume, is $FF here.
;; In: DosFileParameters::Volume, DosFileParameters::Drive, DosFileParameters::Slot = the disk
;; Out: FileControlBlock = zeros, but for <FileControlBlock::VolumeComplement>, <FileControlBlock::Drive>,
;;   <FileControlBlock::SlotTimes16> and FileControlBlock::VtocTrack = <VTOC_TRACK>
;; Keeps: Y
;; Also: DCBSUP (DOS33, DOS31)
.proc SetUpWorkArea
    lda #0
    tax

;; Clears the work area, a byte at a time.
;; Also: F01 (DOS33, DOS31)
ClearByte:
    sta FileControlBlock,x
    inx
    cpx #FILE_CONTROL_SIZE
    bne ClearByte

    ; The disk.
    lda DosFileParameters::Volume
    eor #$FF
    sta FileControlBlock::VolumeComplement
    lda DosFileParameters::Drive
    sta FileControlBlock::Drive
    lda DosFileParameters::Slot
    asl a
    asl a
    asl a
    asl a
    tax

;; Stores the slot times 16. Nothing refers to Apple's label.
;; Also: F01A (DOS33, DOS31)
StoreSlot:
    stx FileControlBlock::SlotTimes16
    lda #VTOC_TRACK
    sta FileControlBlock::VtocTrack
    rts
.endproc

;; The CLOSE request: writes out what waits in the file's buffers and brings the catalog entry up to date.
;;
;; The data sector and the track/sector list are written if they have changed, and the sectors still reserved on
;; the track the file was being given go back to the VTOC (<ReleaseTrack>). If anything at all was written to the
;; disk since OPEN (<WRITTEN>), the file's length in sectors goes into its catalog entry. To get the entry's sector
;; back, CLOSE reads the VTOC for the catalog's start and reads <FileControlBlock::EntryCatalogSector> catalog sectors,
;; the first from there and each next one by the link in the one before: the count <FindFile> kept when it found the
;; file, 1 for the first sector. Disk errors leave the file manager (<AccessDisk>).
;; In: FileControlBlock = the file's work area
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FCLOSE (DOS33, DOS31)
.proc Close
    jsr WriteDataIfChanged
    jsr WriteListIfChanged
    jsr ReleaseTrack

    ; Nothing written since OPEN: nothing to update.
    lda #WRITTEN
    and FileControlBlock::WriteFlags
    beq Done

    ; Read the catalog's first sector, then each next one, until the entry's. (ReadCatalogSector takes nothing in A.)
    jsr ReadVtoc
    lda #0
    clc

;; Reads the next catalog sector, counting down to the entry's.
;; Also: FC1 (DOS33, DOS31)
FindEntrySector:
    jsr ReadCatalogSector
    sec
    dec FileControlBlock::EntryCatalogSector
    bne FindEntrySector

    ; The length, into the entry, and the sector back to the disk.
    ldx FileControlBlock::EntryOffset
    lda FileControlBlock::SectorCount
    sta CatalogBuffer::Entries + CatalogEntry::LENGTH,x
    lda FileControlBlock::SectorCount + 1
    sta CatalogBuffer::Entries + CatalogEntry::LENGTH + 1,x
    jsr WriteCatalogSector

;; Succeeds.
;; Also: FC2 (DOS33, DOS31)
Done:
    jmp Succeed
.endproc

;; The RENAME request: gives the file <DosFileParameters::Name> names the name <DosFileParameters::NewName> points
;; to.
;;
;; The new name is not checked against the names already in the catalog. A locked file is refused with
;; <ERROR_FILE_LOCKED>; the errors of <OpenFile> leave the file manager too.
;; In: DosFileParameters::Name = the address of the old name, DosFileParameters::NewName = the address of the new
;;   one, 30 characters each, and the disk, as for <OpenFile>
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FRNME (DOS33, DOS31)
.proc Rename
    jsr OpenFile
    lda FileControlBlock::FileType
    bmi ToFileLocked

    ; The new name into the entry, in the catalog sector OpenFile left in the buffer, and the sector back.
    lda DosFileParameters::NewName
    sta FilePointer
    lda DosFileParameters::NewName + 1
    sta FilePointer + 1
    ldx Scratch1
    jsr StoreName
    jsr WriteCatalogSector
    jmp Succeed
.endproc

;; The READ request: goes to the routine for <DosFileParameters::Transfer> through <ReadHandlers>.
;;
;; A transfer code of <TRANSFER_COUNT> or more is refused with <ERROR_TRANSFER_RANGE>.
;; In: DosFileParameters::Transfer = the transfer, a TRANSFER_ code
;; Also: FREAD (DOS33, DOS31)
.proc Read
    lda DosFileParameters::Transfer
    cmp #TRANSFER_COUNT
    bcs ToBadTransfer

    ; Push the routine's address less 1, and "return" to it.
    asl a
    tax
    lda ReadHandlers + 1,x
    pha
    lda ReadHandlers,x
    pha
    rts
.endproc

;; Goes on to <BadTransfer>, for <Read> and <Write>, out of their branches' range.
;; Also: ERR3A (DOS33, DOS31)
ToBadTransfer:
    jmp BadTransfer

;; Goes on to <FileLocked>, for <Rename> and <Write>, out of their branches' range.
;; Also: ER10 (DOS33, DOS31)
ToFileLocked:
    jmp FileLocked

;; The WRITE request: unless the file is locked, goes to the routine for <DosFileParameters::Transfer> through
;; <WriteHandlers>.
;;
;; A locked file is refused with <ERROR_FILE_LOCKED>, and a transfer code of <TRANSFER_COUNT> or more with
;; <ERROR_TRANSFER_RANGE>.
;; In: DosFileParameters::Transfer = the transfer, a TRANSFER_ code
;; Also: FWRITE (DOS33, DOS31)
.proc Write
    lda FileControlBlock::FileType
    bmi ToFileLocked
    lda DosFileParameters::Transfer
    cmp #TRANSFER_COUNT
    bcs ToBadTransfer

    ; Push the routine's address less 1, and "return" to it.
    asl a
    tax
    lda WriteHandlers + 1,x
    pha
    lda WriteHandlers,x
    pha
    rts
.endproc

;; READ's <TRANSFER_POSITIONED_BYTE>: sets the position from <DosFileParameters::Record> and
;; <DosFileParameters::ByteOffset>, then reads one byte.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte in the record
;; Out: DosFileParameters::Data = the byte, DosFileParameters::Record/DosFileParameters::ByteOffset = its
;;   position
;; Also: RSPBYT (DOS33, DOS31)
.proc ReadByteAt
    jsr SetPosition
    ; Falls into ReadNextByte.
.endproc

;; READ's <TRANSFER_NEXT_BYTE>: reads the byte at the file's position into <DosFileParameters::Data>.
;;
;; At the end of the file the request ends with <ERROR_END_OF_DATA>.
;; Out: DosFileParameters::Data = the byte, DosFileParameters::Record/DosFileParameters::ByteOffset = its
;;   position
;; Also: RNXBYT (DOS33, DOS31)
.proc ReadNextByte
    jsr GetByte
    sta DosFileParameters::Data
    jmp Succeed
.endproc

;; READ's <TRANSFER_POSITIONED_RANGE>: sets the position from <DosFileParameters::Record> and
;; <DosFileParameters::ByteOffset>, then reads a range of bytes.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte in the record,
;;   DosFileParameters::RangeAddress = where to put the bytes, DosFileParameters::RangeLength = how many
;; Out: DosFileParameters::RangeAddress = the address after the last byte stored, DosFileParameters::RangeLength = 0
;; Also: RSPBLK (DOS33, DOS31)
.proc ReadRangeAt
    jsr SetPosition
    ; Falls into ReadNextRange.
.endproc

;; READ's <TRANSFER_NEXT_RANGE>: reads <DosFileParameters::RangeLength> bytes from the file's position into memory
;; at <DosFileParameters::RangeAddress>.
;;
;; The loop has no exit of its own: <CountDownRange> goes to <Succeed> once the count is used up, before each byte,
;; so a range of n bytes reads n. At the end of the file the request ends with <ERROR_END_OF_DATA>, with the bytes
;; before it stored. Apple's listing calls a range a block.
;; In: DosFileParameters::RangeAddress = where to put the bytes, DosFileParameters::RangeLength = how many
;; Out: DosFileParameters::RangeAddress = the address after the last byte stored, DosFileParameters::RangeLength = 0
;; Also: RNXBLK (DOS33, DOS31)
.proc ReadNextRange
    jsr CountDownRange
    jsr GetByte

    ; Held while the pointer moves from the data buffer to the caller's memory.
    pha
    jsr NextRangeByte
    ldy #0
    pla
    sta (FilePointer),y
    jmp ReadNextRange
.endproc

;; Reads the byte at the file's position and moves the position on.
;;
;; At the end of the file, a position in no sector the track/sector lists name, the request ends with
;; <ERROR_END_OF_DATA>.
;; Out: A = the byte, DosFileParameters::Record/DosFileParameters::ByteOffset = its position, FilePointer = the
;;   data buffer
;; Also: GETBYT (DOS33, DOS31)
.proc GetByte
    jsr LocateNextByte
    bcs ToEndOfData
    lda (FilePointer),y
    pha
    jsr AdvanceRecordByte
    jsr AdvanceSectorByte
    pla
    rts

;; Goes on to <EndOfData>.
;; Also: EOFIN (DOS33, DOS31)
ToEndOfData:
    jmp EndOfData
.endproc

;; WRITE's <TRANSFER_POSITIONED_BYTE>: sets the position from <DosFileParameters::Record> and
;; <DosFileParameters::ByteOffset>, then writes one byte.
;; In: DosFileParameters::Data = the byte, DosFileParameters::Record = the record number,
;;   DosFileParameters::ByteOffset = the byte in the record
;; Out: DosFileParameters::Record/DosFileParameters::ByteOffset = the byte's position
;; Also: WSPBYT (DOS33, DOS31)
.proc WriteByteAt
    jsr SetPosition
    ; Falls into WriteNextByte.
.endproc

;; WRITE's <TRANSFER_NEXT_BYTE>: writes <DosFileParameters::Data> at the file's position.
;;
;; A full disk ends the request with <ERROR_DISK_FULL>, and a disk error as <AccessDisk> says.
;; In: DosFileParameters::Data = the byte
;; Out: DosFileParameters::Record/DosFileParameters::ByteOffset = the byte's position
;; Also: WNXBYT (DOS33, DOS31)
.proc WriteNextByte
    lda DosFileParameters::Data
    jsr PutByte
    jmp Succeed
.endproc

;; WRITE's <TRANSFER_POSITIONED_RANGE>: sets the position from <DosFileParameters::Record> and
;; <DosFileParameters::ByteOffset>, then writes a range of bytes.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte in the record,
;;   DosFileParameters::RangeAddress = the bytes, DosFileParameters::RangeLength = how many, less 1
;; Out: DosFileParameters::RangeAddress = the address after the last byte written, DosFileParameters::RangeLength = 0
;; Also: WSPBLK (DOS33, DOS31)
.proc WriteRangeAt
    jsr SetPosition
    ; Falls into WriteNextRange.
.endproc

;; WRITE's <TRANSFER_NEXT_RANGE>: writes bytes from memory at <DosFileParameters::RangeAddress> at the file's
;; position.
;;
;; Unlike the read loop, this one writes a byte before it counts (<CountDownRange>), so it writes
;; <DosFileParameters::RangeLength> + 1 bytes, and callers pass the length less 1. SAVE and BSAVE pass the length itself
;; (LoadSave.asm, <Commands::WriteWord>), so they write one byte more than the length they record at the start of the
;; file. A full disk ends the request with <ERROR_DISK_FULL>, and a disk error as <AccessDisk> says.
;; In: DosFileParameters::RangeAddress = the bytes, DosFileParameters::RangeLength = how many, less 1
;; Out: DosFileParameters::RangeAddress = the address after the last byte written, DosFileParameters::RangeLength = 0
;; Also: WNXBLK (DOS33, DOS31)
.proc WriteNextRange
    jsr NextRangeByte
    ldy #0
    lda (FilePointer),y
    jsr PutByte
    jsr CountDownRange
    jmp WriteNextRange
.endproc

;; Writes a byte at the file's position and moves the position on.
;;
;; The byte goes into the data buffer, which is marked (<WRITE_DATA>) to be written to the disk before another
;; sector replaces it, or at CLOSE. When the position needs a new sector and the disk is full, the request ends with
;; <ERROR_DISK_FULL>.
;; In: A = the byte
;; Out: DosFileParameters::Record/DosFileParameters::ByteOffset = its position, FilePointer = the data buffer
;; Also: PUTBYT (DOS33, DOS31)
.proc PutByte
    pha
    jsr LocateNextByte

;; Stores the byte. Nothing refers to Apple's label.
;; Also: PB0 (DOS33, DOS31)
StoreByte:
    pla
    sta (FilePointer),y

    ; The data sector has changed.
    lda #WRITE_DATA
    ora FileControlBlock::WriteFlags
    sta FileControlBlock::WriteFlags
    jsr AdvanceRecordByte
    jmp AdvanceSectorByte
.endproc

.endscope
