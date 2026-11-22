; retrocore: style=strict
;; DOS 3.3 and 3.2 file manager: INIT, and reading and writing a file's sectors
;;
;; Apple's FMTRWIO module, at $AE8E-$AFF6 where DOS runs: the INIT request, which formats a disk and gives it an
;; empty VTOC and catalog and a copy of DOS, and the routines that move an open file's sectors between its buffers
;; and the disk. Each disk access goes through <FileManager::AccessDisk>, which fills in DOS's IOB, <DosIob>, from
;; the work area and calls RWTS.
;;
;; An open file has three buffers, which the parameter list points to and <FileManager::PointAtWorkArea>,
;; <FileManager::PointAtListBuffer> and <FileManager::PointAtDataBuffer> select: the work area, the current
;; track/sector list and the current data sector. The work area's <FileManager::FileControlBlock::WriteFlags> say
;; which buffers have changed since they were read: <WRITE_LIST> and <WRITE_DATA>. A track/sector list
;; (docs/Dos.md) is laid out as <TrackSectorList>: the next list's track and sector, the relative sector its first
;; pair stands for, and 122 pairs of track and sector, one for each data sector in turn.

; The file manager: INIT, and the list and data sectors.
.scope FileManager continued

;; The number of tracks DOS's own image takes at the start of every disk, tracks 0 to 2; INIT leaves them out of
;; the free sectors.
DOS_TRACKS = 3

;; The INIT request: formats the disk, writes a fresh VTOC and an empty catalog, and writes DOS to tracks 0 to 2.
;;
;; The new VTOC is the VTOC buffer as it stands, from the last VTOC DOS read (or as DOS was loaded), with the volume
;; number and the allocation start changed and the free-sector map rebuilt: tracks 3 to 34 free but for track 17,
;; 16 sectors each (13 in DOS 3.2). Only the map is cleared, so the catalog's track and sector, the number of tracks
;; and sectors and the rest come from that buffer. The catalog is track 17's sectors 15 down to 1 (12 down to 1 in
;; DOS 3.2), each linked to the one below and the last to nothing; sector 0 is the VTOC. Disk errors leave the file
;; manager (<AccessDisk>).
;; In: DosFileParameters::ImagePage = the first page of the DOS image to write, DosFileParameters::Volume = the
;;   volume number, DosFileParameters::Drive/DosFileParameters::Slot = the disk
;; Out: DosFileParameters::ReturnCode = 0
;; Also: FFMT (DOS33, DOS31)
.proc InitDisk
    jsr SetUpWorkArea

    ; Format every track.
    lda #RWTS_FORMAT
    jsr AccessDisk::Preset

    ; The VTOC: the volume, and the last track allocated, the catalog's, so that allocation starts next to it and
    ; moves up the tracks.
    lda FileControlBlock::VolumeComplement
    eor #$FF
    sta VtocBuffer::Volume
    lda #VTOC_TRACK
    sta VtocBuffer::LastAllocatedTrack
    lda #1
    sta VtocBuffer::AllocationDirection

    ; Zero the free-sector map, to the end of the sector: every sector in use.
    ldx #Vtoc::FREE_SECTORS
    lda #0

;; Clears a byte of the map.
;; Also: NT1 (DOS33, DOS31)
ClearBitMap:
    sta VtocBuffer,x
    inx
    bne ClearBitMap

    ; Free tracks 3 to 34 but 17: EmptyTrackMap, backward, into each track's four bytes.
    ldx #DOS_TRACKS * FREE_MAP_BYTES_PER_TRACK

;; Frees the next track, until the last.
;; Also: NT2 (DOS33, DOS31)
NextTrack:
    cpx #TRACKS_PER_DISK * FREE_MAP_BYTES_PER_TRACK
    beq VtocWritten
    ldy #FREE_MAP_BYTES_PER_TRACK - 1

;; Copies a byte of the empty track's map.
;; Also: NT3 (DOS33, DOS31)
CopyTrackMap:
    lda EmptyTrackMap,y
    sta VtocBuffer::FreeSectors,x
    inx
    dey
    bpl CopyTrackMap

    ; Skip the catalog's track.
    cpx #VTOC_TRACK * FREE_MAP_BYTES_PER_TRACK
    bne NextTrack
    ldx #(VTOC_TRACK + 1) * FREE_MAP_BYTES_PER_TRACK
    bne NextTrack                   ; always

;; Writes the VTOC, then starts the catalog.
;; Also: NT4 (DOS33, DOS31)
VtocWritten:
    jsr WriteVtoc

    ; The catalog: the buffer zeroed, then for each sector from 15 (DOS 3.2: 12) down to 1 the link to the sector
    ; below.
    ldx #0
    txa

;; Clears a byte of the catalog buffer.
;; Also: NT5 (DOS33, DOS31)
ClearCatalog:
    sta CatalogBuffer,x
    inx
    bne ClearCatalog
    jsr SetCatalogBuffer

    ; Y = the sector the first one written links to, 14 (DOS 3.2: 11).
    lda #VTOC_TRACK
    ldy VtocBuffer::SectorsPerTrack
    dey
    dey
    sta DosIob::Track

;; Sets the link's track: the catalog's, and 0 for the last sector.
;; Also: NT6 (DOS33, DOS31)
SetLinkTrack:
    sta CatalogBuffer::NextTrack

;; Writes the sector above Y, linked to sector Y.
;; Also: NT7 (DOS33, DOS31)
NextLink:
    sty CatalogBuffer::NextSector
    iny
    sty DosIob::Sector
    lda #RWTS_WRITE
    jsr AccessDisk::Preset

    ; Sector 1, the last, has been written once Y goes below 0. Sector 1's link is track 0, sector 0: the end.
    ldy CatalogBuffer::NextSector
    dey
    bmi WriteDos
    bne NextLink
    tya
    beq SetLinkTrack                ; always

;; Writes the DOS image at <DosFileParameters::ImagePage> to tracks 0 to 2.
;; Also: NT8 (DOS33, DOS31)
WriteDos:
    jsr Boot::PrepareWrite
    jsr Boot::WriteDos
    jmp Succeed
.endproc

;; Points <FilePointer> at the open file's work area, from <DosFileParameters::WorkArea>.
;; Out: FilePointer = the work area, X = 0
;; Keeps: Y
;; Also: MVFCBP (DOS33, DOS31)
.proc PointAtWorkArea
    ldx #0
    beq PointAtBuffer               ; always
.endproc

;; Points <FilePointer> at the open file's track/sector list buffer, from <DosFileParameters::ListBuffer>.
;; Out: FilePointer = the list buffer
;; Keeps: Y
;; Also: MVFCBD (DOS33, DOS31)
.proc PointAtListBuffer
    ldx #DosFileParameters::ListBuffer - DosFileParameters::WorkArea
    bne PointAtBuffer               ; always
.endproc

;; Points <FilePointer> at the open file's data sector buffer, from <DosFileParameters::DataBuffer>.
;; Out: FilePointer = the data buffer
;; Keeps: Y
;; Also: MVFCBS (DOS33, DOS31)
.proc PointAtDataBuffer
    ldx #DosFileParameters::DataBuffer - DosFileParameters::WorkArea
    ; Falls into PointAtBuffer.
.endproc

;; Points <FilePointer> at one of the open file's buffers: the address at <DosFileParameters::WorkArea> + X.
;; In: X = 0 for the work area, 2 for the list buffer, 4 for the data buffer
;; Out: FilePointer = the buffer
;; Keeps: X, Y
;; Also: MVF1 (DOS33, DOS31)
.proc PointAtBuffer
    lda DosFileParameters::WorkArea,x
    sta FilePointer
    lda DosFileParameters::WorkArea + 1,x
    sta FilePointer + 1
    rts
.endproc

;; Writes the data buffer to its sector if it has changed (<WRITE_DATA>).
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; Out: FileControlBlock::WriteFlags = <WRITE_DATA> clear
;; Also: WRSECT (DOS33, DOS31)
.proc WriteDataIfChanged
    bit FileControlBlock::WriteFlags
    bvs WriteData
    rts
.endproc

;; Writes the data buffer to its sector, and clears <WRITE_DATA>.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; Out: FileControlBlock::WriteFlags = <WRITE_DATA> clear
;; Also: WRSGO (DOS33, DOS31)
.proc WriteData
    jsr SetDataBuffer
    lda #RWTS_WRITE
    jsr AccessDisk
    lda #<~WRITE_DATA
    and FileControlBlock::WriteFlags
    sta FileControlBlock::WriteFlags
    rts
.endproc

;; Writes the track/sector list buffer to its sector if it has changed (<WRITE_LIST>).
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; Out: FileControlBlock::WriteFlags = <WRITE_LIST> clear
;; Also: WRFDIR (DOS33, DOS31)
.proc WriteListIfChanged
    lda FileControlBlock::WriteFlags
    bmi WriteList
    rts
.endproc

;; Writes the track/sector list buffer to its sector, and clears <WRITE_LIST>.
;;
;; <OpenFile> and <ReadList> call it to write a new list. Disk errors leave the file manager (<AccessDisk>).
;; Out: FileControlBlock::WriteFlags = <WRITE_LIST> clear
;; Also: WRFDGO (DOS33, DOS31)
.proc WriteList
    jsr SetListBuffer
    lda #RWTS_WRITE
    jsr AccessDisk
    lda #<~WRITE_LIST
    and FileControlBlock::WriteFlags
    sta FileControlBlock::WriteFlags
    rts
.endproc

;; Points RWTS's buffer at the track/sector list buffer, and gets the current list's track and sector.
;; Out: DosIob::Buffer = the list buffer, X = <FileControlBlock::ListTrack>, Y = <FileControlBlock::ListSector>
;; Also: MVFDBA (DOS33, DOS31)
.proc SetListBuffer
    lda DosFileParameters::ListBuffer
    sta DosIob::Buffer
    lda DosFileParameters::ListBuffer + 1
    sta DosIob::Buffer + 1
    ldx FileControlBlock::ListTrack
    ldy FileControlBlock::ListSector
    rts
.endproc

;; Reads the file's first track/sector list (carry clear), or the next one (carry set), into the list buffer.
;;
;; The list in the buffer is written first if it has changed. When there is no next list and the request is WRITE,
;; a sector is allocated for one: the old list is linked to it and written, and the new one, empty but for the
;; relative sector its first pair stands for, is written to the disk. Either way the work area learns the range of
;; relative sectors the list covers. A full disk ends the request with <ERROR_DISK_FULL>, and disk errors leave the
;; file manager too (<AccessDisk>).
;; In: carry = clear for the first list, at <FileControlBlock::FirstListTrack>/<FileControlBlock::FirstListSector>; set
;;   for the one the list in the buffer links to
;; Out: carry = clear, FilePointer = the list buffer, FileControlBlock::ListTrack/FileControlBlock::ListSector = the
;;   list's track and sector, FileControlBlock::ListFirstSector = the relative sector of its first pair,
;;   FileControlBlock::ListEndSector = the one after its last
;; Errors: carry = set when there is no next list and the request is not WRITE
;; Also: RDFDIR (DOS33, DOS31)
.proc ReadList
    php
    jsr WriteListIfChanged
    jsr SetListBuffer
    jsr PointAtListBuffer
    plp
    bcs Next

    ; The first list.
    ldx FileControlBlock::FirstListTrack
    ldy FileControlBlock::FirstListSector
    jmp StartRead

;; The list the one in the buffer links to; track 0 means this was the last.
;; Also: RFDNXT (DOS33, DOS31)
Next:
    ldy #TrackSectorList::NEXT_TRACK
    lda (FilePointer),y
    beq NoNext
    tax
    iny
    lda (FilePointer),y
    tay
    jmp StartRead

;; No next list: the end, unless the request is WRITE.
;; Also: RFDNL (DOS33, DOS31)
NoNext:
    lda DosFileParameters::Request
    cmp #REQUEST_WRITE
    beq AddList
    sec
    rts

;; Writing past the last list: links the old list to a new sector, writes it, and starts an empty list there.
;; Also: RFDNL1 (DOS33, DOS31)
AddList:
    jsr AllocateSector
    ldy #TrackSectorList::NEXT_SECTOR
    sta (FilePointer),y
    pha
    dey
    lda FileControlBlock::ReservedTrack
    sta (FilePointer),y
    pha
    jsr WriteList
    jsr ClearSector

    ; The new list's first pair follows the old list's last.
    ldy #TrackSectorList::FIRST_SECTOR
    lda FileControlBlock::ListEndSector
    sta (FilePointer),y
    iny
    lda FileControlBlock::ListEndSector + 1
    sta (FilePointer),y

    ; Write it to the new sector.
    pla
    tax
    pla
    tay
    lda #RWTS_WRITE
    bne Transfer                    ; always

;; Reads the list at track X, sector Y.
;; Also: RFDIO1 (DOS33, DOS31)
StartRead:
    lda #RWTS_READ

;; Reads or writes the list at track X, sector Y, as A says, and makes it the current list.
;; Also: RFDIO2 (DOS33, DOS31)
Transfer:
    stx FileControlBlock::ListTrack
    sty FileControlBlock::ListSector
    jsr AccessDisk

;; The relative sectors this list covers: <FileControlBlock::ListFirstSector> up to
;; <FileControlBlock::ListEndSector>, <FileControlBlock::PairsPerList> (122) further on. Nothing refers to Apple's
;; label.
;; Also: RDFDC (DOS33, DOS31)
SetRange:
    ldy #TrackSectorList::FIRST_SECTOR
    lda (FilePointer),y
    sta FileControlBlock::ListFirstSector
    clc
    adc FileControlBlock::PairsPerList
    sta FileControlBlock::ListEndSector
    iny
    lda (FilePointer),y
    sta FileControlBlock::ListFirstSector + 1
    adc FileControlBlock::PairsPerList + 1
    sta FileControlBlock::ListEndSector + 1
    clc
    rts
.endproc

;; Reads the data sector at <FileControlBlock::DataTrack> and <FileControlBlock::DataSector> into the file's data
;; buffer.
;;
;; Disk errors leave the file manager (<AccessDisk>).
;; In: FileControlBlock::DataTrack, FileControlBlock::DataSector = the sector
;; Also: RDSECT (DOS33, DOS31)
.proc ReadData
    jsr SetDataBuffer
    lda #RWTS_READ
    jmp AccessDisk
.endproc

;; Points RWTS's buffer at the data buffer, and gets the data sector's track and sector.
;; Out: DosIob::Buffer = the data buffer, X = <FileControlBlock::DataTrack>, Y = <FileControlBlock::DataSector>
;; Entry:
;;   SetBuffer = sets DosIob::Buffer from A (high) and Y (low) instead; nothing uses it
;; Also: MVSBA (DOS33, DOS31)
.proc SetDataBuffer
    ldy DosFileParameters::DataBuffer
    lda DosFileParameters::DataBuffer + 1

;; Sets RWTS's buffer from A and Y. Nothing refers to Apple's label.
;; In: A = the buffer's high byte, Y = its low byte
;; Also: MSB1 (DOS33, DOS31)
SetBuffer:
    sty DosIob::Buffer
    sta DosIob::Buffer + 1
    ldx FileControlBlock::DataTrack
    ldy FileControlBlock::DataSector
    rts
.endproc

.endscope
