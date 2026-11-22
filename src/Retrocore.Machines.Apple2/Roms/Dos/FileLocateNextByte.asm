; retrocore: style=strict
;; DOS 3.3 and 3.2 file manager: the VTOC and catalog sectors, the calls to RWTS, and the next byte of a file
;;
;; Apple's FLOCNXB module, at $AFF7-$B1C8 where DOS runs: the file manager's lower half, part one. It reads and
;; writes the VTOC and the catalog sectors, turns a request for a sector into a call to RWTS (<FileManager::AccessDisk>,
;; which also turns RWTS's errors into the file manager's), and finds the byte at a file's position:
;; <FileManager::LocateNextByte> brings in the right track/sector list and data sector, and allocates new ones when a
;; write runs past the end of the file. Small helpers advance the position and walk a caller's range of bytes.
;;
;; The requests that call it are in FileOpenCloseReadWrite.asm and FileDeleteCatalog.asm; reading and writing the
;; track/sector list and data sector buffers is in FileManagerIo.asm; sector allocation, the catalog search and the
;; exits are in FileLocateSector.asm; the buffers and the file control block are in FileManagerData.asm. docs/Dos.md
;; describes the VTOC, the catalog and track/sector lists.

; The file manager: the VTOC, the catalog, RWTS, and the position.
.scope FileManager continued

;; <Iob::TYPE>'s value, which every IOB holds.
IOB_TYPE = 1

;; Reads the VTOC, track <FileControlBlock::VtocTrack> sector 0, into <VtocBuffer>.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; In: FileControlBlock::VtocTrack = the VTOC's track,
;;   FileControlBlock::SlotTimes16/FileControlBlock::Drive/FileControlBlock::VolumeComplement = the disk
;; Out: VtocBuffer = the VTOC
;; Also: RDVTOC (DOS33, DOS31)
.proc ReadVtoc
    lda #RWTS_READ
    bne TransferVtoc                ; always
.endproc

;; Writes <VtocBuffer> back to track <FileControlBlock::VtocTrack> sector 0.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; In: VtocBuffer = the VTOC, FileControlBlock::VtocTrack = its track,
;;   FileControlBlock::SlotTimes16/FileControlBlock::Drive/FileControlBlock::VolumeComplement = the disk
;; Also: WRVTOC (DOS33, DOS31)
.proc WriteVtoc
    lda #RWTS_WRITE
    ; Falls into TransferVtoc.
.endproc

;; Reads or writes <VtocBuffer>, at track <FileControlBlock::VtocTrack> sector 0.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; In: A = <RWTS_READ> or <RWTS_WRITE>, FileControlBlock::VtocTrack = the VTOC's track, and the disk
;; Also: VTIO (DOS33, DOS31)
.proc TransferVtoc
    ldy VtocAddress
    sty DosIob::Buffer
    ldy VtocAddress + 1
    sty DosIob::Buffer + 1
    ldx FileControlBlock::VtocTrack
    ldy #0
    jmp AccessDisk
.endproc

;; Reads a catalog sector into <CatalogBuffer>: the first one, or the one after the sector in the buffer.
;;
;; The VTOC must be in its buffer for the first sector, since it says where the catalog starts. Each catalog sector
;; holds the track and sector of the next (<CatalogBuffer::NextTrack>, <CatalogBuffer::NextSector>); a track of 0
;; ends the chain. Disk errors leave the file manager (<AccessDisk>).
;; In: carry = clear for the first catalog sector, set for the next one
;; Out: carry = clear, CatalogBuffer = the sector, CurrentCatalogTrack/CurrentCatalogSector = where it came from;
;;   carry = set when there is no next sector, with the buffer unchanged
;; Also: RDVDIR (DOS33, DOS31)
.proc ReadCatalogSector
    php
    jsr SetCatalogBuffer
    plp
    bcs Next

;; The first sector, where the VTOC says. The branch is always taken for a valid VTOC, whose catalog is never on
;; track 0; with track 0 there it falls into <Next> and follows the buffer's old link. Nothing refers to Apple's label.
;; Also: RVDC (DOS33, DOS31)
First:
    ldy VtocBuffer::CatalogSector
    ldx VtocBuffer::CatalogTrack
    bne ReadIt

;; The sector the one in the buffer links to; track 0 is the end of the catalog.
;; Also: RVDA (DOS33, DOS31)
Next:
    ldx CatalogBuffer::NextTrack
    bne Linked
    sec
    rts

;; Takes the linked sector.
;; Also: RDVC (DOS33, DOS31)
Linked:
    ldy CatalogBuffer::NextSector

;; Reads track X, sector Y, remembering where for <WriteCatalogSector>.
;; Also: RVDGO (DOS33, DOS31)
ReadIt:
    stx CurrentCatalogTrack
    sty CurrentCatalogSector
    lda #RWTS_READ
    jsr AccessDisk
    clc
    rts
.endproc

;; Writes <CatalogBuffer> back to the sector it was read from.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; In: CatalogBuffer = the catalog sector, CurrentCatalogTrack/CurrentCatalogSector = where it came from
;; Also: WRVDIR (DOS33, DOS31)
.proc WriteCatalogSector
    jsr SetCatalogBuffer
    ldx CurrentCatalogTrack
    ldy CurrentCatalogSector
    lda #RWTS_WRITE
    jmp AccessDisk
.endproc

;; Points RWTS's buffer at <CatalogBuffer>.
;; Out: DosIob::Buffer = <CatalogBuffer>
;; Keeps: X, Y
;; Also: MVVDBA (DOS33, DOS31)
.proc SetCatalogBuffer
    lda CatalogBufferAddress
    sta DosIob::Buffer
    lda CatalogBufferAddress + 1
    sta DosIob::Buffer + 1
    rts
.endproc

;; Reads, writes or formats through RWTS, for the slot, drive and volume in the file control block.
;;
;; Fills in the rest of <DosIob> from the file control block and calls <CallRwts>; the caller sets the buffer,
;; <DosIob::Buffer>, first. A write also sets <WRITTEN> in <FileControlBlock::WriteFlags>, which tells CLOSE that the
;; disk has changed and the catalog's sector count needs updating: it ORs in the command, <RWTS_WRITE>, which is the
;; same bit. The volume is kept complemented (<SetUpWorkArea> stores it that way) and complemented back here, so RWTS
;; gets the volume the caller asked for, 0 meaning any.
;;
;; It does not return on an error: it leaves the file manager through <Fail> with <ERROR_VOLUME_MISMATCH>,
;; <ERROR_WRITE_PROTECTED> or, for any other error, <ERROR_IO>.
;; In: A = the RWTS command, <RWTS_READ>, <RWTS_WRITE> or <RWTS_FORMAT>, X = the track, Y = the sector, DosIob::Buffer =
;;   the buffer
;; Out: DosFileParameters::Volume = the volume RWTS found on the disk, DosIob::Volume = $FF
;; Entry:
;;   Preset = with the track and sector already in <DosIob::Track> and <DosIob::Sector>
;; Also: DCBIO (DOS33, DOS31)
.proc AccessDisk
    stx DosIob::Track
    sty DosIob::Sector

;; Calls RWTS with the track and sector already in <DosIob>; <InitDisk> calls it.
;; In: A = the RWTS command, DosIob::Track/DosIob::Sector = the sector, DosIob::Buffer = the buffer
;; Also: DCBIO2 (DOS33, DOS31)
Preset:
    sta DosIob::Command
    cmp #RWTS_WRITE
    bne SetDisk

    ; A write: A is RWTS_WRITE, the same bit as WRITTEN.
    ora FileControlBlock::WriteFlags
    sta FileControlBlock::WriteFlags

;; Fills in the disk and the length, and calls RWTS.
;; Also: DCBIO1 (DOS33, DOS31)
SetDisk:
    lda FileControlBlock::VolumeComplement
    eor #$FF
    sta DosIob::Volume
    lda FileControlBlock::SlotTimes16
    sta DosIob::SlotTimes16
    lda FileControlBlock::Drive
    sta DosIob::Drive
    lda FileControlBlock::SectorLength
    sta DosIob::DataLength
    lda FileControlBlock::SectorLength + 1
    sta DosIob::DataLength + 1
    lda #IOB_TYPE
    sta DosIob::Type
    ldy IobAddress
    lda IobAddress + 1
    jsr CallRwts

    ; The volume RWTS found, for the caller (CATALOG prints it).
    lda DosIob::VolumeFound
    sta DosFileParameters::Volume
    lda #$FF
    sta DosIob::Volume
    bcs DiskError
    rts

;; Turns RWTS's error into a file manager return code, and leaves.
;; Also: BADIO (DOS33, DOS31)
DiskError:
    lda DosIob::ReturnCode
    ldy #ERROR_VOLUME_MISMATCH
    cmp #RWTS_VOLUME_MISMATCH
    beq ToFail
    ldy #ERROR_WRITE_PROTECTED
    cmp #RWTS_WRITE_PROTECTED
    beq ToFail
    ldy #ERROR_IO

;; Leaves with the code in Y.
;; Also: BD2 (DOS33, DOS31)
ToFail:
    tya
    jmp Fail
.endproc

;; Brings the byte at the file's position into reach, reading its sector into the data buffer.
;;
;; The position is a relative sector (<FileControlBlock::PositionSector>, counting from 0 at the start of the file)
;; and a byte in it (<FileControlBlock::PositionByte>). If that sector is already in the buffer
;; (<FileControlBlock::DataRelativeSector>), nothing is read. Otherwise the buffer is written back if it has changed,
;; and the track/sector list that covers the sector is found: each list covers <FileControlBlock::PairsPerList> (122)
;; sectors, from <FileControlBlock::ListFirstSector> up to but not including <FileControlBlock::ListEndSector>. A
;; sector before the list in memory makes <ReadList> start again from the file's first list; one after it follows
;; the chain. The sector's track and sector are then taken from the list. A track of 0 means the sector was never
;; written: a read ends there, at the end of the file, while a write allocates a new sector for it
;; (<AllocateDataSector>), and <ReadList> likewise adds a new list when a write runs past the last one. A full disk
;; and disk errors leave the file manager.
;; In: FileControlBlock::PositionSector = the relative sector, FileControlBlock::PositionByte = the byte in it,
;;   DosFileParameters::Request = the request, where <REQUEST_WRITE> allocates
;; Out: carry = clear, FilePointer = the data buffer, Y = the byte's offset in it; carry = set at the end of the
;;   file, when not writing
;; Also: LOCNXB (DOS33, DOS31)
.proc LocateNextByte
    lda FileControlBlock::PositionSector
    cmp FileControlBlock::DataRelativeSector
    bne ChangeSector
    lda FileControlBlock::PositionSector + 1
    cmp FileControlBlock::DataRelativeSector + 1
    beq PointAtByte

;; Another sector: writes the old one back if it has changed.
;; Also: LNB1 (DOS33, DOS31)
ChangeSector:
    jsr WriteDataIfChanged

;; Whether the list in memory covers the sector: it must not be below the list's first sector (carry clear, so
;; <ReadList> goes back to the first list)...
;; Also: LNB2 (DOS33, DOS31)
CheckLow:
    lda FileControlBlock::PositionSector + 1
    cmp FileControlBlock::ListFirstSector + 1
    bcc OtherList
    bne CheckHigh
    lda FileControlBlock::PositionSector
    cmp FileControlBlock::ListFirstSector
    bcc OtherList

;; ...and must be below the list's end (carry set, so <ReadList> reads the next list).
;; Also: LNB3 (DOS33, DOS31)
CheckHigh:
    lda FileControlBlock::PositionSector + 1
    cmp FileControlBlock::ListEndSector + 1
    bcc FindPair
    bne OtherList
    lda FileControlBlock::PositionSector
    cmp FileControlBlock::ListEndSector
    bcc FindPair

;; Reads the file's first list (carry clear) or the next one (carry set), and checks it; no more lists is the end
;; of the file.
;; Also: LNB4 (DOS33, DOS31)
OtherList:
    jsr ReadList
    bcc CheckLow
    rts

;; Finds the sector's pair in the list: (PositionSector - ListFirstSector) * 2 + <TrackSectorList::PAIRS>. The
;; difference is under 122, so only the low bytes matter, and the ASL leaves the carry clear for the ADC.
;; Also: LNB6 (DOS33, DOS31)
FindPair:
    sec
    lda FileControlBlock::PositionSector
    sbc FileControlBlock::ListFirstSector
    asl a
    adc #TrackSectorList::PAIRS
    tay
    jsr PointAtListBuffer

    ; The sector's track. None: allocate one if writing, else it is the end of the file.
    lda (FilePointer),y
    bne ReadSector
    lda DosFileParameters::Request
    cmp #REQUEST_WRITE
    beq Allocate
    sec
    rts

;; Allocates a sector for the write.
;; Also: LNB7A (DOS33, DOS31)
Allocate:
    jsr AllocateDataSector
    jmp Remember

;; Reads the sector the pair names.
;; Also: LNB7 (DOS33, DOS31)
ReadSector:
    sta FileControlBlock::DataTrack
    iny
    lda (FilePointer),y
    sta FileControlBlock::DataSector
    jsr ReadData

;; Records the relative sector as the one in the buffer.
;; Also: LNBCON (DOS33, DOS31)
Remember:
    lda FileControlBlock::PositionSector
    sta FileControlBlock::DataRelativeSector
    lda FileControlBlock::PositionSector + 1
    sta FileControlBlock::DataRelativeSector + 1

;; Points at the byte: the data buffer, and Y = the byte in it.
;; Also: LNB8 (DOS33, DOS31)
PointAtByte:
    jsr PointAtDataBuffer
    ldy FileControlBlock::PositionByte
    clc
    rts
.endproc

;; Allocates a new data sector for the track/sector pair at Y, and gives the file an empty buffer for it.
;;
;; Records the new track and sector in the list and in <FileControlBlock::DataTrack> and
;; <FileControlBlock::DataSector>, clears the data buffer, and marks both the list and the data sector to be written
;; (<WRITE_LIST>, <WRITE_DATA>). A full disk and disk errors leave the file manager (<AllocateSector>).
;; In: Y = the pair's offset in the list buffer, FilePointer = the list buffer
;; Out: FilePointer = the data buffer, all zeros
;; Also: GNWSEC (DOS33, DOS31)
.proc AllocateDataSector
    sty Scratch2
    jsr AllocateSector

    ; The pair: the sector, then the track.
    ldy Scratch2
    iny
    sta (FilePointer),y
    sta FileControlBlock::DataSector
    dey
    lda FileControlBlock::ReservedTrack
    sta (FilePointer),y
    sta FileControlBlock::DataTrack

    ; An empty data sector, and both buffers changed.
    jsr PointAtDataBuffer
    jsr ClearSector
    lda #WRITE_LIST | WRITE_DATA
    ora FileControlBlock::WriteFlags
    sta FileControlBlock::WriteFlags
    rts
.endproc

;; Reports the position of the byte just moved, then advances the position in the record by one byte.
;;
;; Copies the record and the byte in it (<FileControlBlock::PositionRecord>, <FileControlBlock::PositionRecordByte>)
;; to the parameter list, so the caller sees where the byte it read or wrote was. Then counts the byte; reaching the
;; record length (<FileControlBlock::RecordLength>) starts the next record at byte 0. <AdvanceSectorByte> advances
;; the sector position to match.
;; Out: DosFileParameters::Record/DosFileParameters::ByteOffset = the old position,
;;   FileControlBlock::PositionRecord/FileControlBlock::PositionRecordByte = the new one
;; Keeps: A
;; Also: INCRRB (DOS33, DOS31)
.proc AdvanceRecordByte
    ldx FileControlBlock::PositionRecord
    stx DosFileParameters::Record
    ldx FileControlBlock::PositionRecord + 1
    stx DosFileParameters::Record + 1
    ldx FileControlBlock::PositionRecordByte
    ldy FileControlBlock::PositionRecordByte + 1
    stx DosFileParameters::ByteOffset
    sty DosFileParameters::ByteOffset + 1

    ; YX = the byte in the record, plus 1.
    inx
    bne CheckRecordEnd
    iny

;; At the record length: byte 0 of the next record.
;; Also: INCR1 (DOS33, DOS31)
CheckRecordEnd:
    cpy FileControlBlock::RecordLength + 1
    bne Store
    cpx FileControlBlock::RecordLength
    bne Store
    ldx #0
    ldy #0
    inc FileControlBlock::PositionRecord
    bne Store
    inc FileControlBlock::PositionRecord + 1

;; Stores the byte in the record.
;; Also: INCR2 (DOS33, DOS31)
Store:
    stx FileControlBlock::PositionRecordByte
    sty FileControlBlock::PositionRecordByte + 1
    rts
.endproc

;; Advances the file's position by one byte: the next byte of the sector, or the first of the next sector.
;; Out: FileControlBlock::PositionByte = the byte in the sector, FileControlBlock::PositionSector = the relative
;;   sector
;; Keeps: A, X, Y
;; Also: INCSCB (DOS33, DOS31)
.proc AdvanceSectorByte
    inc FileControlBlock::PositionByte
    bne Done
    inc FileControlBlock::PositionSector
    bne Done
    inc FileControlBlock::PositionSector + 1

;; The return.
;; Also: INCS2 (DOS33, DOS31)
Done:
    rts
.endproc

;; Points <FilePointer> at the next byte of the caller's range, and advances <DosFileParameters::RangeAddress>.
;; In: DosFileParameters::RangeAddress = the next byte of the caller's range
;; Out: FilePointer = that byte's address, DosFileParameters::RangeAddress = the one after it
;; Keeps: A
;; Also: MIBDA (DOS33, DOS31)
.proc NextRangeByte
    ldy DosFileParameters::RangeAddress
    ldx DosFileParameters::RangeAddress + 1
    sty FilePointer
    stx FilePointer + 1
    inc DosFileParameters::RangeAddress
    bne Done
    inc DosFileParameters::RangeAddress + 1

;; The return.
;; Also: MIB1 (DOS33, DOS31)
Done:
    rts
.endproc

;; Counts down a range transfer's length, and ends the request when it was already 0.
;;
;; While <DosFileParameters::RangeLength> is not 0 it is decremented and the routine returns; when it is 0, it goes
;; on to <Succeed>, leaving the file manager. READ calls it before each byte and WRITE after each, so a range of n
;; bytes reads n and writes n + 1.
;; In: DosFileParameters::RangeLength = the bytes left
;; Out: DosFileParameters::RangeLength = one fewer
;; Keeps: A
;; Also: DTBLN (DOS33, DOS31)
.proc CountDownRange
    ldy DosFileParameters::RangeLength
    bne CountLow
    ldx DosFileParameters::RangeLength + 1
    beq Finished
    dec DosFileParameters::RangeLength + 1

;; Decrements the low byte.
;; Also: DTB1 (DOS33, DOS31)
CountLow:
    dec DosFileParameters::RangeLength
    rts

;; The range is done.
;; Also: DTB2 (DOS33, DOS31)
Finished:
    jmp Succeed
.endproc

.endscope
