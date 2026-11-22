; retrocore: style=strict
;; DOS 3.3 and 3.2 file manager: the catalog search, sector allocation, the position, and the exits
;;
;; Apple's FLOCSEC module, at $B1C9-$B396 where DOS runs: the file manager's lower half, part two.
;; <FileManager::FindFile> finds a file's entry in the catalog, or a free entry for a new file.
;; <FileManager::AllocateSector> hands out free sectors, <FileManager::ReleaseTrack> and
;; <FileManager::MergeFreeMap> give them back to the VTOC's free-sector map, and <FileManager::SetPosition> turns a
;; record number and byte offset into a position in the file. The routines at the end are the way out of every
;; request: <FileManager::Succeed>, and the error exits that load a return code, all ending in
;; <FileManager::Leave>, which hands the file control block back and returns to the file manager's caller.
;;
;; FileLocateNextByte.asm has the disk routines used here; FileManagerData.asm lays out the VTOC and catalog buffers
;; and the file control block. docs/Dos.md describes the VTOC, its free-sector map and the catalog.

; The file manager: the catalog search, allocation, the position and the exits.
.scope FileManager continued

;; Finds a file in the catalog by name or, failing that, claims a free catalog entry and puts the name in it.
;;
;; Reads the VTOC, then makes up to two passes along the chain of catalog sectors. <Scratch2> is 1 on the first: it
;; compares the name with each entry in use, skipping deleted ones, and stops at the first entry never used (a track
;; of 0), taking every entry after it to be unused too. <Scratch2> is 0 on the second: it starts again at the first
;; catalog sector and takes the first entry that is deleted or never used, copying the name into it in the buffer
;; only; <OpenFile> decides whether to create the file and write the sector. When the catalog has no free entry the
;; request ends with <ERROR_DISK_FULL>; disk errors leave the file manager (<AccessDisk>).
;;
;; <FileControlBlock::EntryCatalogSector> counts the catalog sectors read, 1 for the first, so that CLOSE can read
;; the entry's sector again.
;; In: DosFileParameters::Name = the address of the name, 30 characters padded with spaces
;; Out: carry = clear when found, set when a free entry now holds the name; either way X = the entry's offset in
;;   <CatalogBuffer::Entries>, Scratch1 = the same, CatalogBuffer = its catalog sector,
;;   FileControlBlock::EntryCatalogSector = that sector's place in the chain, FilePointer = the name
;; Also: FNDFIL (DOS33, DOS31)
.proc FindFile
    jsr ReadVtoc
    lda DosFileParameters::Name
    sta FilePointer
    lda DosFileParameters::Name + 1
    sta FilePointer + 1
    lda #1

;; Starts a pass: A = 1 for the first, 0 for the second. <EndOfCatalog> comes back here for the second.
;; Also: FF1 (DOS33, DOS31)
StartPass:
    sta Scratch2
    lda #0
    sta FileControlBlock::EntryCatalogSector
    clc

;; Reads the next catalog sector (the first with the carry clear).
;; Also: FF2 (DOS33, DOS31)
NextSector:
    inc FileControlBlock::EntryCatalogSector
    jsr ReadCatalogSector
    bcs EndOfCatalog
    ldx #0

;; Looks at the entry at X, kept in <Scratch1>.
;; Also: FF3 (DOS33, DOS31)
CheckEntry:
    stx Scratch1
    lda CatalogBuffer::Entries + CatalogEntry::LIST_TRACK,x
    beq NeverUsed
    bmi Deleted

    ; Compare the names: X steps through the entry's name, from its offset plus CatalogEntry::NAME.
    ldy #0
    inx
    inx

;; Compares a character.
;; Also: FF4 (DOS33, DOS31)
CompareName:
    inx
    lda (FilePointer),y
    cmp CatalogBuffer::Entries,x
    bne SkipEntry
    iny
    cpy #CATALOG_NAME_LENGTH
    bne CompareName

    ; All 30 match: found.
    ldx Scratch1
    clc
    rts

;; Steps to the next entry, or reads the next sector after the last (the carry set).
;; Also: FF5 (DOS33, DOS31)
SkipEntry:
    jsr StepEntry
    bcc CheckEntry
    bcs NextSector

;; An entry never used: the first pass ends here and starts the second, with A = 0 from the entry; the second pass
;; goes on to take the entry.
;; Also: FF6 (DOS33, DOS31)
NeverUsed:
    ldy Scratch2
    bne StartPass

;; A deleted entry: the first pass skips it, the second takes it.
;; Also: FF7 (DOS33, DOS31)
Deleted:
    ldy Scratch2
    bne SkipEntry
    ; Falls into StoreName.
.endproc

;; Copies a file name into a catalog entry in <CatalogBuffer>.
;;
;; <FindFile> falls into it to claim a free entry; <Rename> calls it to put the new name in the file's entry.
;; In: X = the entry's offset in <CatalogBuffer::Entries>, Scratch1 = the same, FilePointer = the address of the
;;   30-character name
;; Out: carry = set, X = <Scratch1>
;; Also: MVFN (DOS33, DOS31)
.proc StoreName
    ldy #0
    inx
    inx

;; Copies a character.
;; Also: FF8 (DOS33, DOS31)
CopyCharacter:
    inx
    lda (FilePointer),y
    sta CatalogBuffer::Entries,x
    iny
    cpy #CATALOG_NAME_LENGTH
    bne CopyCharacter
    ldx Scratch1
    sec
    rts
.endproc

;; Steps to the next of the seven file entries in the catalog sector.
;; In: Scratch1 = the offset of the current entry in <CatalogBuffer::Entries>
;; Out: X = the offset of the next entry, carry = set when there is none in this sector
;; Keeps: Y
;; Also: VDINC (DOS33, DOS31)
.proc StepEntry
    clc
    lda Scratch1

    ; An entry's size, .sizeof(CatalogEntry), which a forward .sizeof would take as 0 here.
    adc #CATALOG_ENTRIES_SIZE / CATALOG_ENTRY_COUNT
    tax
    cpx #CATALOG_ENTRIES_SIZE
    rts
.endproc

;; The end of the catalog, for <FindFile>: after the first pass, starts the second; after the second, the catalog
;; has no free entry, and the request ends with <ERROR_DISK_FULL>.
;; In: Scratch2 = 1 after the first pass, 0 after the second
;; Also: FF4A (DOS33, DOS31)
.proc EndOfCatalog
    lda #0
    ldy Scratch2
    bne FindFile::StartPass
    jmp DiskFull
.endproc

;; Allocates a free sector for the open file, from the track reserved for it or from a newly reserved track.
;;
;; The file manager reserves a whole track for a file at a time. It copies the track's free-sector map from the VTOC
;; into <FileControlBlock::ReservedMap>, marks the whole track used in the VTOC and writes the VTOC. Sectors are
;; then handed out from the map without touching the disk, and CLOSE gives the unused ones back (<ReleaseTrack>).
;;
;; Handing out: <FileControlBlock::ReservedSector> counts down through the sector numbers, from the number of
;; sectors less 1. Each step rotates the map's 32 bits left by one, which brings the bit of that sector out into the
;; carry: the map's first byte holds sectors 15 to 8 and its second 7 to 0, highest bit first (in DOS 3.2, 12 to 5
;; and 4 to 0). A set bit is a free sector.
;;
;; Reserving: the VTOC remembers the last track it reserved (<VtocBuffer::LastAllocatedTrack>) and the direction it
;; was moving (<VtocBuffer::AllocationDirection>, 1 or -1), and the search steps from there until it finds a track
;; with a free sector, moving away from the catalog on track 17. Running off the last track turns it round to go
;; down from track 16; reaching track 0 turns it round to go up from track 18. Reaching track 0 a second time means
;; every track has been looked at, and the request ends with <ERROR_DISK_FULL>. Track 0 is never reserved, and the
;; search never comes back to track 17. Disk errors leave the file manager (<AccessDisk>).
;; In: FileControlBlock::ReservedTrack = the reserved track, or 0 for none,
;;   FileControlBlock::ReservedSector/FileControlBlock::ReservedMap = what is left of it
;; Out: A = the sector, FileControlBlock::ReservedTrack = its track, FileControlBlock::SectorCount = one more
;; Also: GETSEC (DOS33, DOS31)
.proc AllocateSector
    lda FileControlBlock::ReservedTrack
    beq ReserveTrack

;; Tries the next sector down; below 0, the track is used up.
;; Also: GS0 (DOS33, DOS31)
NextSector:
    dec FileControlBlock::ReservedSector
    bmi TrackUsed
    clc
    ldx #FREE_MAP_BYTES_PER_TRACK

;; Rotates the map left one bit, the last byte first, so the bit leaving the first byte lands in the carry.
;; Also: GS1 (DOS33, DOS31)
RotateMap:
    rol FileControlBlock::ReservedMap - 1,x
    dex
    bne RotateMap
    bcc NextSector

    ; A free sector: one more in the file.
    inc FileControlBlock::SectorCount
    bne Found
    inc FileControlBlock::SectorCount + 1

;; Returns the sector.
;; Also: GS1A (DOS33, DOS31)
Found:
    lda FileControlBlock::ReservedSector
    rts

;; Drops the used-up track.
;; Also: CS2 (DOS33, DOS31)
TrackUsed:
    lda #0
    sta FileControlBlock::ReservedTrack

;; Reserves a new track. <Scratch3> becomes 1 once the search has turned round at track 0.
;; Also: GSS1 (DOS33, DOS31)
ReserveTrack:
    lda #0
    sta Scratch3
    jsr ReadVtoc

;; Steps to the next track in the current direction.
;; Also: GS2 (DOS33, DOS31)
NextTrack:
    clc
    lda VtocBuffer::LastAllocatedTrack
    adc VtocBuffer::AllocationDirection
    beq AtTrackZero
    cmp VtocBuffer::TrackCount
    bcc TakeTrack

    ; Past the last track: go down, from 16.
    lda #$FF
    bne TurnRound                   ; always

;; At track 0: go up, from 18, unless that was done already.
;; Also: GS3 (DOS33, DOS31)
AtTrackZero:
    lda Scratch3
    bne ToDiskFull
    lda #1
    sta Scratch3

;; Takes the new direction, A, and starts from the track beside the catalog's.
;; Also: GS4 (DOS33, DOS31)
TurnRound:
    sta VtocBuffer::AllocationDirection
    clc
    adc #VTOC_TRACK

;; Takes track A, and finds its map in the VTOC.
;; Also: GS5 (DOS33, DOS31)
TakeTrack:
    sta VtocBuffer::LastAllocatedTrack
    sta FileControlBlock::ReservedTrack

    ; Y = the track * 4, its map's offset in the VTOC's free-sector map. (The first TAY has no effect.)
    tay
    asl a
    asl a
    tay
    ldx #FREE_MAP_BYTES_PER_TRACK
    clc

;; Moves the track's map into <FileControlBlock::ReservedMap>, clearing it in the VTOC; the carry ends set if any
;; sector was free.
;; Also: GS6 (DOS33, DOS31)
MoveMap:
    lda VtocBuffer::FreeSectors + FREE_MAP_BYTES_PER_TRACK - 1,y
    sta FileControlBlock::ReservedMap - 1,x
    beq NextMapByte
    sec
    lda #0
    sta VtocBuffer::FreeSectors + FREE_MAP_BYTES_PER_TRACK - 1,y

;; Steps to the next map byte.
;; Also: GS7 (DOS33, DOS31)
NextMapByte:
    dey
    dex
    bne MoveMap

    ; Nothing free on this track: try the next.
    bcc NextTrack

    ; Write the VTOC with the track taken, and hand out from the top sector down.
    jsr WriteVtoc
    lda VtocBuffer::SectorsPerTrack
    sta FileControlBlock::ReservedSector
    bne NextSector                  ; always

;; Goes on to <DiskFull>, out of a branch's range.
;; Also: ERR9 (DOS33, DOS31)
ToDiskFull:
    jmp DiskFull
.endproc

;; Gives the sectors the file did not use on its reserved track back to the VTOC, and writes the VTOC.
;;
;; CLOSE calls it. The reservation is dropped, so the next write reserves a track again. Disk errors leave the file
;; manager (<AccessDisk>).
;; In: FileControlBlock::ReservedTrack = the reserved track, or 0 for none (then nothing happens),
;;   FileControlBlock::ReservedSector/FileControlBlock::ReservedMap = what is left of it
;; Out: FileControlBlock::ReservedTrack = 0
;; See: <AllocateSector>, <MergeFreeMap>
;; Also: FRETRK (DOS33, DOS31)
.proc ReleaseTrack
    lda FileControlBlock::ReservedTrack
    bne Release
    rts

;; Merges what is left into the VTOC read from the disk, shifting in zeros, so the sectors handed out stay in use.
;; Also: FT1 (DOS33, DOS31)
Release:
    pha
    jsr ReadVtoc
    ldy FileControlBlock::ReservedSector
    pla
    clc
    jsr MergeFreeMap
    lda #0
    sta FileControlBlock::ReservedTrack
    jmp WriteVtoc
.endproc

;; Shifts a sector map in <FileControlBlock::ReservedMap> into place and marks its sectors free in <VtocBuffer>.
;;
;; The map is rotated right once for each sector number from Y up to the number of sectors less 1, taking the carry
;; in at the top the first time. Its two callers use it two ways:
;;
;; - <ReleaseTrack>, with the carry clear and Y = <FileControlBlock::ReservedSector>, undoes <AllocateSector>'s left
;;   rotations, so that only the sectors not yet handed out are freed.
;; - <FreeSector>, for DELETE, with the map all zeros, the carry set and Y = a sector, builds a map of that one
;;   sector.
;;
;; The map is then ORed into the track's map in the VTOC buffer; the caller writes the VTOC. Track 0, the DOS image,
;; is never changed.
;; In: A = the track, Y = the sector, carry = the first bit to shift in, FileControlBlock::ReservedMap = the map
;; Out: VtocBuffer::FreeSectors = the track's map, updated
;; Also: FRESEC (DOS33, DOS31)
.proc MergeFreeMap

;; Rotates the map right once: X = 252 to 255 walks the map's four bytes, ending at 0.
;; Also: FS1 (DOS33, DOS31)
NextRotation:
    ldx #256 - FREE_MAP_BYTES_PER_TRACK

;; Rotates a byte of the map.
;; Also: FS2 (DOS33, DOS31)
RotateByte:
    ror FileControlBlock::ReservedMap - (256 - FREE_MAP_BYTES_PER_TRACK),x
    inx
    bne RotateByte
    iny
    cpy VtocBuffer::SectorsPerTrack
    bne NextRotation

    ; Y = the track * 4, its map's offset in the VTOC's free-sector map. Track 0 is left alone.
    asl a
    asl a
    tay
    beq Done
    ldx #FREE_MAP_BYTES_PER_TRACK

;; ORs a byte of the map into the VTOC's, the last first.
;; Also: FS3 (DOS33, DOS31)
MergeByte:
    lda FileControlBlock::ReservedMap - 1,x
    ora VtocBuffer::FreeSectors + FREE_MAP_BYTES_PER_TRACK - 1,y
    sta VtocBuffer::FreeSectors + FREE_MAP_BYTES_PER_TRACK - 1,y
    dey
    dex
    bne MergeByte

;; The return.
;; Also: FS4 (DOS33, DOS31)
Done:
    rts
.endproc

.if REVISION_B
;; Sets the file's position from a record number and a byte offset: record * record length + offset.
;;
;; A 16-by-16-bit shift-and-add multiply. The record number starts in <FileControlBlock::PositionSector> and
;; <FileControlBlock::PositionByte> as the multiplier; on each of 16 steps its low bit decides whether the record
;; length is added to the top half, then the whole of A, PositionSector + 1, PositionSector and PositionByte shifts
;; right, moving the product in as the multiplier moves out. The byte offset is then added. The low byte of the
;; result is the byte in the sector and the next two the relative sector; the top byte, in A, is dropped. The next
;; <LocateNextByte> reads the sector.
;;
;; The 1982 revision (<REVISION_B>) adds the CLC before the addition. Without it, as in the 1980 DOS 3.3 and in DOS 3.2,
;; the carry left by the last shift (the record number's top bit) is added too, so a record number of $8000 or more
;; lands one byte too far: with a record length of 1, any position past $7FFF. The revision also carries into the
;; relative sector's high byte with a branch, which leaves room for the CLC; two zero bytes pad it to the old length,
;; so nothing after it moves.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte offset,
;;   FileControlBlock::RecordLength = the record length
;; Out: FileControlBlock::PositionSector = the relative sector, FileControlBlock::PositionByte = the byte in it,
;;   FileControlBlock::PositionRecord = the record number, FileControlBlock::PositionRecordByte = the byte offset
;; Also: LOCSEC (DOS33, DOS31)
.proc SetPosition
    lda DosFileParameters::Record
    sta FileControlBlock::PositionByte
    sta FileControlBlock::PositionRecord
    lda DosFileParameters::Record + 1
    sta FileControlBlock::PositionSector
    sta FileControlBlock::PositionRecord + 1
    lda #0
    sta FileControlBlock::PositionSector + 1
    ldy #16

;; One step of the multiply: X holds the product's top byte while A tests the multiplier's low bit.
;; Also: LS1 (DOS33, DOS31)
MultiplyStep:
    tax
    lda FileControlBlock::PositionByte
    lsr a
    bcs AddLength
    txa
    bcc Shift                       ; always

;; Adds the record length to the top half.
;; Also: LS1A (DOS33, DOS31)
AddLength:
    clc
    lda FileControlBlock::PositionSector + 1
    adc FileControlBlock::RecordLength
    sta FileControlBlock::PositionSector + 1
    txa
    adc FileControlBlock::RecordLength + 1

;; Shifts the 32 bits right.
;; Also: LS2 (DOS33, DOS31)
Shift:
    ror a
    ror FileControlBlock::PositionSector + 1
    ror FileControlBlock::PositionSector
    ror FileControlBlock::PositionByte
    dey
    bne MultiplyStep

    ; Add the byte offset.
    clc
    lda DosFileParameters::ByteOffset
    sta FileControlBlock::PositionRecordByte
    adc FileControlBlock::PositionByte
    sta FileControlBlock::PositionByte
    lda DosFileParameters::ByteOffset + 1
    sta FileControlBlock::PositionRecordByte + 1
    adc FileControlBlock::PositionSector
    sta FileControlBlock::PositionSector
    bcc Done
    inc FileControlBlock::PositionSector + 1

;; The return.
;; Also: DONTINC (DOS33)
Done:
    rts
    .res 2, $00
.endproc
.else
;; Sets the file's position from a record number and a byte offset: record * record length + offset.
;;
;; The same as the 1982 revision's (<REVISION_B>) but for the addition, which has no CLC before it, so the carry left by
;; the last shift, the record number's top bit, is added too. A record number of $8000 or more lands one byte too
;; far: with a record length of 1, any position past $7FFF.
;; In: DosFileParameters::Record = the record number, DosFileParameters::ByteOffset = the byte offset,
;;   FileControlBlock::RecordLength = the record length
;; Out: FileControlBlock::PositionSector = the relative sector, FileControlBlock::PositionByte = the byte in it,
;;   FileControlBlock::PositionRecord = the record number, FileControlBlock::PositionRecordByte = the byte offset
;; Also: LOCSEC (DOS33, DOS31)
.proc SetPosition
    lda DosFileParameters::Record
    sta FileControlBlock::PositionByte
    sta FileControlBlock::PositionRecord
    lda DosFileParameters::Record + 1
    sta FileControlBlock::PositionSector
    sta FileControlBlock::PositionRecord + 1
    lda #0
    sta FileControlBlock::PositionSector + 1
    ldy #16

;; One step of the multiply: X holds the product's top byte while A tests the multiplier's low bit.
;; Also: LS1 (DOS33, DOS31)
MultiplyStep:
    tax
    lda FileControlBlock::PositionByte
    lsr a
    bcs AddLength
    txa
    bcc Shift                       ; always

;; Adds the record length to the top half.
;; Also: LS1A (DOS33, DOS31)
AddLength:
    clc
    lda FileControlBlock::PositionSector + 1
    adc FileControlBlock::RecordLength
    sta FileControlBlock::PositionSector + 1
    txa
    adc FileControlBlock::RecordLength + 1

;; Shifts the 32 bits right.
;; Also: LS2 (DOS33, DOS31)
Shift:
    ror a
    ror FileControlBlock::PositionSector + 1
    ror FileControlBlock::PositionSector
    ror FileControlBlock::PositionByte
    dey
    bne MultiplyStep

    ; Add the byte offset, and the carry the last shift left.
    lda DosFileParameters::ByteOffset
    sta FileControlBlock::PositionRecordByte
    adc FileControlBlock::PositionByte
    sta FileControlBlock::PositionByte
    lda DosFileParameters::ByteOffset + 1
    sta FileControlBlock::PositionRecordByte + 1
    adc FileControlBlock::PositionSector
    sta FileControlBlock::PositionSector
    lda #0
    adc FileControlBlock::PositionSector + 1
    sta FileControlBlock::PositionSector + 1
    rts
.endproc
.endif

; The exits. Each error exit loads a return code, an ERROR_ code, and goes to Fail; the command interpreter prints
; each code's message.

;; Leaves the file manager with <ERROR_LANGUAGE_NOT_AVAILABLE>.
;; Also: ERROR1 (DOS33, DOS31)
.proc LanguageNotAvailable
    lda #ERROR_LANGUAGE_NOT_AVAILABLE
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_RANGE>: the request code is out of range.
;; Also: ERROR2 (DOS33, DOS31)
.proc BadRequest
    lda #ERROR_RANGE
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_TRANSFER_RANGE>: the READ or WRITE transfer code is out of range.
;; Also: ERROR3 (DOS33, DOS31)
.proc BadTransfer
    lda #ERROR_TRANSFER_RANGE
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_WRITE_PROTECTED>. Nothing goes here: <AccessDisk> leaves with that code
;; through <Fail>.
;; Also: ERROR4 (DOS33, DOS31)
.proc WriteProtected
    lda #ERROR_WRITE_PROTECTED
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_END_OF_DATA>.
;; Also: ERROR5 (DOS33, DOS31)
.proc EndOfData
    lda #ERROR_END_OF_DATA
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_FILE_NOT_FOUND>.
;; Also: ERROR6 (DOS33, DOS31)
.proc FileNotFound
    lda #ERROR_FILE_NOT_FOUND
    bne Fail
.endproc

;; Leaves the file manager with <ERROR_DISK_FULL>, through <ReportDiskFull>, which closes the open files first.
;;
;; The jump and the NOP fill the same four bytes as the other error exits, so the routines after keep their
;; addresses.
;; Also: ERROR9 (DOS33, DOS31)
.proc DiskFull
    jmp ReportDiskFull
    nop
.endproc

;; Leaves the file manager with <ERROR_FILE_LOCKED>.
;; Also: ERRR10 (DOS33, DOS31)
.proc FileLocked
    lda #ERROR_FILE_LOCKED
    bne Fail
.endproc

;; Ends a file manager request successfully: returns to the file manager's caller with the carry clear.
;;
;; The return code is what <DosFileParameters::ReturnCode> already holds: 0, which the entry sets, or
;; <ERROR_FILE_NOT_FOUND> from <OpenFile> when it has just created the file.
;; Out: DosFileParameters::ReturnCode = the return code, carry = clear
;; Also: GOODIO (DOS33, DOS31)
.proc Succeed
    lda DosFileParameters::ReturnCode
    clc
    bcc Leave                       ; always
.endproc

;; Ends a file manager request with an error: returns to the file manager's caller with the carry set.
;; In: A = the return code, an ERROR_ code
;; Out: DosFileParameters::ReturnCode = A, carry = set
;; Also: ERRORA (DOS33, DOS31), ERRORB (DOS33, DOS31)
.proc Fail
    sec
    ; Falls into Leave.
.endproc

;; Leaves the file manager: stores the return code, copies the file control block back to the file's work area
;; (<SaveWorkArea>), and returns to whoever called the file manager by restoring the stack pointer saved on entry
;; (<EntryStack>), however deep the request was.
;;
;; It also clears $48. RWTS keeps its IOB pointer at $48 and $49, and $48 is also where the Monitor keeps the
;; processor status its G command loads (<SavedStatus>), so it is cleared rather than left holding part of an
;; address. The caller gets the result in <DosFileParameters::ReturnCode> and the carry: A, X and Y hold what the
;; copy left in them.
;; In: A = the return code, carry = set for an error
;; Out: DosFileParameters::ReturnCode = A, carry = as it was, OPTION_SLOT = <EntryStack>
;; Also: RETURN (DOS33, DOS31)
.proc Leave
    php
    sta DosFileParameters::ReturnCode
    lda #0
    sta SavedStatus
    jsr SaveWorkArea
    plp
    ldx EntryStack
    txs
    rts
.endproc

.endscope

;; The end of the relocator's range of the file manager's code, <FileManagerCodeStart> to here. The relocator
;; adjusts addresses only inside its code ranges; the buffers that follow hold none.
;; Also: EC2 (DOS33, DOS31)
FileManagerCodeEnd:
