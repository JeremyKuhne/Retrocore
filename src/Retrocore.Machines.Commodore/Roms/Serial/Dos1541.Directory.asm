; retrocore: style=strict
; COMMODORE 1541 DOS: THE DIRECTORY LISTING, VALIDATE, NEW AND THE BAM ($EC9E-$F258)
.scope Directory continued

;; STDIR: the directory as a BASIC program, through a read channel with one buffer: load address $0401, the header line
;; (drive and disk name), then lines of entries until the buffer is full; each line is 32 bytes, so a buffer holds
;; eight.
;; Entry:
;;   FillBuffer = The next lines, from GETNAM, until the buffer fills or the listing ends (<NextListingByte> e
;; Also: STDIR (D1541)
.proc StartListing
    lda #$00
    sta SecondaryAddress
    lda #$01
    jsr Files::GetReadChannel
    lda #$00
    jsr Files::SetPointer
    ldx Channel
    lda #$00
    sta ChannelLastByte,x
    jsr Files::GetActiveBuffer
    tax
    lda DriveNumber
    sta LastJobs,x
    lda #$01
    jsr Files::PutByte
    lda #$04
    jsr Files::PutByte
    lda #$01
    jsr Files::PutByte
    jsr Files::PutByte
    lda BlockTotal
    jsr Files::PutByte
    lda #$00
    jsr Files::PutByte
    jsr PutLineText
    jsr Files::GetActiveBuffer
    asl
    tax
    dec BufferPositions,x
    dec BufferPositions,x
    lda #$00
    jsr Files::PutByte

;; The next lines, from GETNAM, until the buffer fills or the listing ends (<NextListingByte> enters here for the next
;; buffer).
;; Also: DIR1 (D1541)
FillBuffer:
    lda #$01
    jsr Files::PutByte
    jsr Files::PutByte
    jsr NextLine
    bcc LastLine
    lda BlockTotal
    jsr Files::PutByte
    lda BlockTotal+1
    jsr Files::PutByte
    jsr PutLineText
    lda #$00
    jsr Files::PutByte
    bne FillBuffer

;; The pointer 0, DIRLST and CHNRDY ready to talk; A = DATA.
;; Also: DIR10 (D1541)
BufferFull:
    jsr Files::GetActiveBuffer
    asl
    tax
    lda #$00
    sta BufferPositions,x
    lda #CHANNEL_TALK
    ldy Channel
    sta ListingActive
    sta a:ChannelStatus,y
    lda DataByte
    rts

;; The BLOCKS FREE line, the program's end (three zeros), LSTCHR its last byte.
;; Also: DIR3 (D1541)
LastLine:
    lda BlockTotal
    jsr Files::PutByte
    lda BlockTotal+1
    jsr Files::PutByte
    jsr PutLineText
    jsr Files::GetActiveBuffer
    asl
    tax
    dec BufferPositions,x
    dec BufferPositions,x
    lda #$00
    jsr Files::PutByte
    jsr Files::PutByte
    jsr Files::PutByte
    jsr Files::GetActiveBuffer
    asl
    tay
    lda a:BufferPositions,y
    ldx Channel
    sta ChannelLastByte,x
    dec ChannelLastByte,x
    jmp BufferFull
.endproc

;; MOVBUF: NAMBUF's 27 bytes, a line's text, into the buffer.
;; Also: MOVBUF (D1541)
.proc PutLineText
    ldy #$00

;; Each byte.
;; Also: MOVB1 (D1541)
Loop:
    lda ListingLine,y
    jsr Files::PutByte
    iny
    cpy #$1B
    bne Loop
    rts
.endproc

;; GETDIR: A = the listing's next byte; at a buffer's end, EOI if it is the last, else the buffer filled again.
;; Also: GETDIR (D1541)
.proc NextListingByte
    jsr Files::GetByte
    beq BufferEnd
    rts

;; DATA = it.
;; Also: GETD3 (D1541)
BufferEnd:
    sta DataByte
    ldy Channel
    lda ChannelLastByte,y
    beq Refill
    lda #CHANNEL_TALK_LAST
    sta a:ChannelStatus,y
    lda DataByte
    rts

;; The next lines, A kept.
;; Also: GD1 (D1541)
Refill:
    pha
    jsr StartListing::FillBuffer
    pla
    rts
.endproc

;; VERDIR: the V command (the command table's entry): initializes the drive, builds a new BAM with every block free,
;; marks used the directory's blocks and each closed file's (and its side sectors'), deletes entries not closed, and
;; writes the BAM.
;; Also: VERDIR (D1541), VALDAT (D1541)
.proc Validate
    jsr Commands::ParseDriveOnly
    jsr Bam::InitializeDrive
    lda #$40
    sta BamWriteDeferred
    jsr Bam::BuildEmpty
    lda #$00
    sta FreeEntryIndex
    jsr Search
    bne CheckEntry

;; The directory's own chain (18/0), then the BAM written.
;; Also: VD10 (D1541)
Finish:
    lda #$00
    sta Sector
    lda DirectoryTrack
    sta Track
    jsr MarkChain
    lda #$00
    sta BamWriteDeferred
    jsr Bam::WriteIfDirty
    jmp Commands::Finish

;; The file's start; a relative file's side sectors first.
;; Also: VD15 (D1541)
ClosedFile:
    iny
    lda (BufferPointer),y
    pha
    iny
    lda (BufferPointer),y
    pha
    ldy #$13
    lda (BufferPointer),y
    beq DataBlocks
    sta Track
    iny
    lda (BufferPointer),y
    sta Sector
    jsr MarkChain

;; The data chain.
;; Also: VD17 (D1541)
DataBlocks:
    pla
    sta Sector
    pla
    sta Track
    jsr MarkChain

;; The next entry (<Search::Again>).
;; Also: VD20 (D1541)
NextFile:
    jsr Search::Again
    beq Finish

;; Closed: its blocks; not closed: its entry deleted.
;; Also: VD25 (D1541)
CheckEntry:
    ldy #$00
    lda (BufferPointer),y
    bmi ClosedFile
    jsr DeleteEntry
    jmp NextFile
.endproc

;; VMKBAM: marks used in the BAM each block of the chain from TRACK and SECTOR, through the internal read channel.
;; Also: VMKBAM (D1541)
.proc MarkChain
    jsr Jobs::CheckTrackSector
    jsr Bam::FlushAndMarkUsed
    jsr Files::OpenInternalRead

;; The block's link.
;; Also: MRK2 (D1541)
Next:
    lda #$00
    jsr Files::SetPointer
    jsr Files::GetByte
    sta Track
    jsr Files::GetByte
    sta Sector
    lda Track
    bne Mark
    jmp Files::FreeChannel

;; Marked, and on to it.
;; Also: MRK1 (D1541)
Mark:
    jsr Bam::FlushAndMarkUsed
    jsr Files::FollowLink
    jmp Next
.endproc
.endscope
.scope Commands continued

;; N: the drive (not given: 33 SYNTAX ERROR); with an ID, the disk formatted (channels cleared, <Format>, the BAM
;; zeroed); without, only the directory cleared, on a disk of this format. Then a new BAM with the name, ID, DOS version
;; and format, the BAM's and first directory block marked used and written, and an empty first directory block. Then
;; <Finish>. (Reached through the command table.)
;; Also: NEW (D1541)
.proc New
    jsr SetFirstDrive
    lda FileNameDrive
    bpl Drive
    lda #ERROR_INVALID_NAME
    jmp Fail

;; DRVNUM and the LEDs; the ID, after the ',', into DSKID if given.
;; Also: N101 (D1541)
Drive:
    and #$01
    sta DriveNumber
    jsr TurnOnActivityLed
    lda DriveNumber
    asl
    tax
    ldy FileNameStart+1
    cpy CommandLength
    beq Clear
    lda CommandBuffer,y
    sta DiskId,x
    lda CommandBuffer+1,y
    sta DiskId+1,x
    jsr Files::FreeAllChannels
    lda #$01
    sta Track
.if REVISION = 6
    jsr FormatPatch
.else
    jsr Format
.endif
    jsr Bam::ZeroBuffer
    jmp Build

;; No ID: the directory cleared (INITDR), and the disk's format must be VERNUM's, else 73 (VNERR).
;; Also: N108 (D1541)
Clear:
    jsr Bam::InitializeDrive
    ldx DriveNumber
    lda DiskVersion,x
    cmp FormatType
    beq Build
    jmp Jobs::VersionError

;; The new BAM (NEWMAP), the name (<CopyName>, 27 places), the ID, '2' and VERNUM into the BAM sector, the BAM and
;; directory blocks used; the BAM and the empty directory block written, and the BAM read back.
;; Also: N110 (D1541)
Build:
    jsr Bam::BuildEmpty
    lda JobNumber
    tay
    asl
    tax
    lda DiskNameOffset
    sta BufferPositions,x
    ldx FileNameStart
    lda #$1B
    jsr CopyName
    ldy #$12
    ldx DriveNumber
    lda FormatType
    sta DiskVersion,x
    txa
    asl
    tax
    lda DiskId,x
    sta (BufferPointer),y
    iny
    lda DiskId+1,x
    sta (BufferPointer),y
    iny
    iny
    lda #DOS_VERSION+48
    sta (BufferPointer),y
    iny
    lda FormatType
    sta (BufferPointer),y
    ldy #$02
    sta (BamPointer),y
    lda DirectoryTrack
    sta Track
    jsr Bam::MarkUsed
    lda #$01
    sta Sector
    jsr Bam::MarkUsed
    jsr Bam::WriteIfDirty
    jsr Bam::ZeroBuffer
    ldy #$01
    lda #$FF
    sta (BamPointer),y
    jsr Jobs::WriteTrackSector
    dec Sector
    jsr Jobs::ReadTrackSector
    jmp Finish
.endproc
.endscope
.scope Bam continued

;; NEWMAP: builds a new BAM in its buffer, every block free: link 18/1, each track's count and bits from
;; <SectorsOnTrack>; then <CountFreeBlocks>. NEWMPV is its second name, in Also:.
;; Also: NEWMAP (D1541), NEWMPV (D1541)
.proc BuildEmpty
    jsr ForgetImages
    ldy #$00
    lda #$12
    sta (BamPointer),y
    iny
    tya
    sta (BamPointer),y
    iny
    iny
    iny

;; A track's count.
;; Also: NM10 (D1541)
NextTrack:
    lda #$00
    sta Temporary
    sta Temporary1
    sta Temporary2
    tya
    lsr
    lsr
    jsr SectorsOnTrack
    sta (BamPointer),y
    iny
    tax

;; One bit for each sector.
;; Also: NM20 (D1541)
SetBits:
    sec
    rol Temporary
    rol Temporary1
    rol Temporary2
    dex
    bne SetBits

;; The three bytes.
;; Also: NM30 (D1541)
StoreBits:
    lda Temporary,x
    sta (BamPointer),y
    iny
    inx
    cpx #$03
    bcc StoreBits
    cpy #$90
    bcc NextTrack
    jmp CountFreeBlocks
.endproc

;; MAPOUT: DRVNUM = the drive of the active buffer's last job; falls into <WriteIfDirty>.
;; Also: MAPOUT (D1541)
.proc WriteForChannel
    jsr Files::GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    sta DriveNumber
.endproc

;; SCRBAM: when MDIRTY says DRVNUM's BAM changed, puts its track images back, checks each track's count against its bits
;; (<CheckTrackCount>) and writes the BAM block.
;; Also: SCRBAM (D1541)
.proc WriteIfDirty
    ldy DriveNumber
    lda BamDirty,y
    bne Dirty
    rts

;; MDIRTY cleared; the images back.
;; Also: SB10 (D1541)
Dirty:
    lda #$00
    sta BamDirty,y
    jsr SetPointer
    lda DriveNumber
    asl
    pha
    jsr PutImage
    pla
    clc
    adc #$01
    jsr PutImage
    lda Track
    pha
    lda #$01
    sta Track

;; Each track's count.
;; Also: SB20 (D1541)
CheckTrack:
    asl
    asl
    sta BamPointer
    jsr CheckTrackCount
    inc Track
    lda Track
    cmp TrackLimit
    bcc CheckTrack
    pla
    sta Track
    jmp Jobs::Write
.endproc

;; SETBPT: BMPNT = the BAM's buffer, read in if need be.
;; Also: SETBPT (D1541)
.proc SetPointer
    jsr ChannelIndex
    tax
    jsr ReadIfNeeded
    ldx JobNumber
    lda BufferPages,x
    sta BamPointer+1
    lda #$00
    sta BamPointer
    rts
.endproc

;; NUMFRE: NBTEMP = DRVNUM's free blocks (NDBL, NDBH), for the listing and the messages.
;; Also: NUMFRE (D1541)
.proc CopyFreeBlocks
    ldx DriveNumber
    lda FreeBlocks,x
    sta BlockTotal
    lda FreeBlocksHigh,x
    sta BlockTotal+1
    rts
.endproc

;; WFREE: <FlushPending>, then <MarkFree>. Nothing calls it; kept as a routine, its comment says so.
;; Also: WFREE (D1541)
.proc FlushAndMarkFree
    jsr FlushPending
.endproc

;; FRETS: marks TRACK and SECTOR free in the BAM: its bit set, its track's count and NDBL/NDBH up; already free, carry
;; set. A block on the directory track branches to <MarkUsed>'s count down (USE10), which skips the borrow (NDBL = 0
;; leaves NDBH unchanged: the count is off by 256) and falls into CheckFull, so under 3 free blocks it can raise error
;; 72, DISK FULL: a slip, documented, not changed.
;; Also: FRETS (D1541)
.proc MarkFree
    jsr FindBit
    sec
    bne Done
    lda (BamPointer),y
    ora BitMasks,x
    sta (BamPointer),y
    jsr MarkDirty
    ldy Temporary
    clc
    lda (BamPointer),y
    adc #$01
    sta (BamPointer),y
    lda Track
    cmp DirectoryTrack
    beq MarkUsed::CountDown
    inc FreeBlocks,x
    bne Done
    inc FreeBlocksHigh,x

;; FRE10: returns; FRERTS is its second name, in Also:.
;; Also: FRE10 (D1541), FRERTS (D1541)
Done:
    rts
.endproc

;; DTYBAM: MDIRTY for DRVNUM set.
;; Also: DTYBAM (D1541)
.proc MarkDirty
    ldx DriveNumber
    lda #$01
    sta BamDirty,x
    rts
.endproc

;; WUSED: <FlushPending>, then <MarkUsed>.
;; Also: WUSED (D1541)
.proc FlushAndMarkUsed
    jsr FlushPending
.endproc

;; USEDTS: marks TRACK and SECTOR used in the BAM (Z set, nothing done, if it was): its bit cleared, its track's count
;; and, off the directory track, NDBL/NDBH down; fewer than three blocks left sets error 72, DISK FULL.
;; Entry:
;;   CountDown = NDBL down (<MarkFree> comes here for the directory track)
;; Also: USEDTS (D1541)
.proc MarkUsed
    jsr FindBit
    beq Done
    lda (BamPointer),y
    eor BitMasks,x
    sta (BamPointer),y
    jsr MarkDirty
    ldy Temporary
    lda (BamPointer),y
    sec
    sbc #$01
    sta (BamPointer),y
    lda Track
    cmp DirectoryTrack
    beq CheckFull
    lda FreeBlocks,x
    bne CountDown
    dec FreeBlocksHigh,x

;; NDBL down (<MarkFree> comes here for the directory track).
;; Also: USE10 (D1541)
CountDown:
    dec FreeBlocks,x

;; Fewer than three left: DISK FULL (ERRMSG).
;; Also: USE20 (D1541)
CheckFull:
    lda FreeBlocksHigh,x
    bne Done
    lda FreeBlocks,x
    cmp #$03
    bcs Done
    lda #ERROR_DISK_FULL
    jsr Errors::SetMessage

;; Returns.
;; Also: USERTS (D1541)
Done:
    rts
.endproc

;; FREUSE: the track's image selected; Y = the byte of SECTOR's bit, X its number, A = it: Z set when used.
;; Entry:
;;   InImage = From the image index in TEMP (<FindFreeSector> enters here)
;; Also: FREUSE (D1541)
.proc FindBit
    jsr SelectTrack
    tya
    sta Temporary

;; From the image index in TEMP (<FindFreeSector> enters here).
;; Also: FREUS3 (D1541)
InImage:
    lda Sector
    lsr
    lsr
    lsr
    sec
    adc Temporary
    tay
    lda Sector
    and #$07
    tax
    lda (BamPointer),y
    and BitMasks,x
    rts
.endproc
.endscope

;; 1, 2, 4 ... 128: bit X's mask; the BAM's routines and the buffer allocation (BUFUSE) use it, so top level.
;; Also: BMASK (D1541)
BitMasks:
    .byte $01, $02, $04, $08, $10, $20, $40, $80
.scope Bam continued

;; FIXBAM: writes the BAM now if WBAM's bit 7 marks a write pending and bit 6 is not holding writes back; WBAM cleared.
;; Also: FIXBAM (D1541)
.proc FlushPending
    lda #$FF
    bit BamWriteDeferred
    beq Done
    bpl Done
    bvs Done
    lda #$00
    sta BamWriteDeferred
    jmp Jobs::Write

;; Returns.
;; Also: FBAM10 (D1541)
Done:
    rts
.endproc

;; CLRBAM: the BAM's buffer, all 256 bytes, cleared (the new command).
;; Also: CLRBAM (D1541)
.proc ZeroBuffer
    jsr SetPointer
    ldy #$00
    tya

;; Each byte.
;; Also: CLB1 (D1541)
Loop:
    sta (BamPointer),y
    iny
    bne Loop
    rts
.endproc

;; SETBAM: BMPNT = the image of TRACK's four BAM bytes (count and bits), swapped in from the buffer when neither of
;; DRVNUM's images has it; UBAM notes the one used. Y = 0. Error 74, DRIVE NOT READY, for a drive with no disk.
;; Also: SETBAM (D1541)
.proc SelectTrack
    lda Temporary
    pha
    lda Temporary1
    pha
    ldx DriveNumber
    lda NoDrive,x
    beq HaveDrive
    lda #ERROR_DRIVE_NOT_READY
    jsr Errors::Recover

;; TBAM's two entries for the drive.
;; Also: SBM10 (D1541)
HaveDrive:
    jsr ChannelIndex
    sta Temporary
    txa
    asl
    sta Temporary1
    tax
    lda Track
    cmp ImageTracks,x
    beq InImage
    inx
    stx Temporary1
    cmp ImageTracks,x
    beq InImage
    jsr SwapIn

;; UBAM and BMPNT.
;; Also: SBM30 (D1541)
InImage:
    lda Temporary1
    ldx DriveNumber
    sta LastImage,x
    asl
    asl
    clc
    adc #<Images
    sta BamPointer
    lda #>Images
    adc #$00
    sta BamPointer+1
    ldy #$00
    pla
    sta Temporary1
    pla
    sta Temporary
    rts
.endproc

;; SWAP: puts the image used less recently back in the BAM buffer and copies TRACK's bytes into it (clearing them in the
;; buffer); the BAM is written at once unless WBAM holds writes, when bit 7 marks one pending.
;; Also: SWAP (D1541)
.proc SwapIn
    ldx Temporary
    jsr ReadIfNeeded
    lda DriveNumber
    tax
    asl
    ora LastImage,x
    eor #$01
    and #$03
    sta Temporary1
    jsr PutImage
    lda JobNumber
    asl
    tax
    lda Track
    asl
    asl
    sta BufferPositions,x
    lda Temporary1
    asl
    asl
    tay

;; Each of the four bytes.
;; Also: SWAP3 (D1541)
Copy:
    lda (BufferPositions,x)
    sta Images,y
    lda #$00
    sta (BufferPositions,x)
    inc BufferPositions,x
    iny
    tya
    and #$03
    bne Copy
    ldx Temporary1
    lda Track
    sta ImageTracks,x
    lda BamWriteDeferred
    bne Pending
    jmp Jobs::Write

;; WBAM's bit 7.
;; Also: SWAP4 (D1541)
Pending:
    ora #$80
    sta BamWriteDeferred
    rts
.endproc

;; PUTBAM: image A back into the BAM buffer at its track's place, the image and its TBAM cleared; nothing for an empty
;; one.
;; Also: PUTBAM (D1541)
.proc PutImage
    tay
    lda ImageTracks,y
    beq Done
    pha
    lda #$00
    sta ImageTracks,y
    lda JobNumber
    asl
    tax
    pla
    asl
    asl
    sta BufferPositions,x
    tya
    asl
    asl
    tay

;; Each of the four bytes.
;; Also: SWAP1 (D1541)
Copy:
    lda Images,y
    sta (BufferPositions,x)
    lda #$00
    sta Images,y
    inc BufferPositions,x
    iny
    tya
    and #$03
    bne Copy

;; Returns.
;; Also: SWAP2 (D1541)
Done:
    rts
.endproc

;; CLNBAM: TBAM's two entries for DRVNUM cleared: no track images.
;; Also: CLNBAM (D1541)
.proc ForgetImages
    lda DriveNumber
    asl
    tax
    lda #$00
    sta ImageTracks,x
    inx
    sta ImageTracks,x
    rts
.endproc

;; REDBAM: with X the BAM's index, reads the BAM (18/0) into a buffer of its own (inactive, so it can be stolen) when it
;; has none (error 70, NO CHANNEL); JOBNUM = its buffer.
;; Also: REDBAM (D1541)
.proc ReadIfNeeded
    lda ChannelBuffer,x
    cmp #$FF
    bne InMemory
    txa
    pha
    jsr Files::GetBuffer
    tax
    bpl Got
    lda #ERROR_NO_CHANNEL
    jsr Commands::Fail

;; The buffer, as the BAM's, and the read.
;; Also: RBM10 (D1541)
Got:
    stx JobNumber
    pla
    tay
    txa
    ora #$80
    sta a:ChannelBuffer,y
    asl
    tax
    lda DirectoryTrack
    sta JobHeaders,x
    lda #$00
    sta JobHeaders+1,x
    jmp Jobs::Read

;; JOBNUM = its buffer.
;; Also: RBM20 (D1541)
InMemory:
    and #$0F
    sta JobNumber
    rts
.endproc

;; BAM2A: A = the BAM's index into BUF0 and BUF1 for DRVNUM: BLINDX's second slot for drive 0, its first for drive 1.
;; Also: BAM2A (D1541)
.proc ChannelIndex
    lda #BAM_CHANNEL
    ldx DriveNumber
    bne Done
    clc
    adc #CHANNEL_COUNT+1

;; Returns.
;; Also: B2X10 (D1541)
Done:
    rts
.endproc

;; BAM2X: X = <ChannelIndex>.
;; Also: BAM2X (D1541)
.proc ChannelIndexInX
    jsr ChannelIndex
    tax
    rts
.endproc

;; NXTTS: allocates the free block after the active buffer's TRACK and SECTOR: on that track SECINC sectors on, else
;; outward from track 18 on the same side, then the other side; error 72, DISK FULL, when none is left. WBAM holds the
;; BAM's writes. Relative files (part 5) use it.
;; Entry:
;;   Search = NXT1
;;   Search = NXTDS
;; Also: NXTTS (D1541)
.proc AllocateNext
    jsr Files::GetBufferBlock
    lda #$03
    sta Temporary
    lda #$01
    ora BamWriteDeferred
    sta BamWriteDeferred

;; NXTDS: from TRACK and SECTOR, with TEMP passes (NewBlock enters here for the directory track); in Also: with NXT1.
;; Also: NXTDS (D1541), NXT1 (D1541)
Search:
    lda Temporary
    pha
    jsr SelectTrack
    pla
    sta Temporary
    lda (BamPointer),y
    bne NextSector
    lda Track
    cmp DirectoryTrack
    beq DiskFull
    bcc Downward
    inc Track
    lda Track
    cmp TrackLimit
    bne Search
    ldx DirectoryTrack
    dex
    stx Track
    lda #$00
    sta Sector
    dec Temporary
    bne Search

;; Error 72, DISK FULL.
;; Also: NXTERR (D1541)
DiskFull:
    lda #ERROR_DISK_FULL
    jsr Commands::Fail

;; Below track 18: down a track; past track 1, from track 19.
;; Also: NXT2 (D1541)
Downward:
    dec Track
    bne Search
    ldx DirectoryTrack
    inx
    stx Track
    lda #$00
    sta Sector
    dec Temporary
    bne Search
    beq DiskFull

;; SECINC sectors on, wrapping inside the track.
;; Also: FNDNXT (D1541)
NextSector:
    lda Sector
    clc
    adc SectorInterleave
    sta Sector
    lda Track
    jsr SectorsOnTrack
    sta LastSector
    sta JobCommand
    cmp Sector
    bcs FindSector
    sec
    lda Sector
    sbc LastSector
    sta Sector
    beq FindSector
    dec Sector

;; The first free from there.
;; Also: FNDN0 (D1541)
FindSector:
    jsr FindFreeSector
    beq FromStart

;; Marked used.
;; Also: FNDN1 (D1541)
Use:
    jmp FlushAndMarkUsed

;; From sector 0; none means the count was wrong (error 71).
;; Also: FNDN2 (D1541)
FromStart:
    lda #$00
    sta Sector
    jsr FindFreeSector
    bne Use
    jmp AllocateFirst::DirectoryError
.endproc

;; INTTS: allocates a file's first block on the free track nearest the directory's, below first (17, 19, 16, 20 ...),
;; from sector 0; error 67 past the last track.
;; Entry:
;;   DirectoryError = Error 71, DIR ERROR
;;   DirectoryError = FND2
;; Also: INTTS (D1541)
.proc AllocateFirst
    lda #$01
    ora BamWriteDeferred
    sta BamWriteDeferred
    lda Work0
    pha
    lda #$01
    sta Work0

;; Track 18 - R0.
;; Also: ITS1 (D1541)
Below:
    lda DirectoryTrack
    sec
    sbc Work0
    sta Track
    bcc Above
    beq Above
    jsr SelectTrack
    lda (BamPointer),y
    bne FindSector

;; Track 18 + R0, R0 up.
;; Also: ITS2 (D1541)
Above:
    lda DirectoryTrack
    clc
    adc Work0
    sta Track
    inc Work0
    cmp TrackLimit
    bcc CheckAbove
    lda #ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR
    jsr Errors::Abort

;; Free blocks there, or the next pair.
;; Also: ITS3 (D1541)
CheckAbove:
    jsr SelectTrack
    lda (BamPointer),y
    beq Below

;; R0 back; the first free sector, marked used.
;; Also: FNDSEC (D1541)
FindSector:
    pla
    sta Work0
    lda #$00
    sta Sector
    jsr FindFreeSector
    beq DirectoryError
    jmp FlushAndMarkUsed

;; FND2: a second name at DirectoryError's address; in its Also:.
;; Also: FND2 (D1541), DERR (D1541)
DirectoryError:
    lda #ERROR_DIRECTORY
    jsr Errors::Abort
.endproc

;; GETSEC: with TRACK's count checked, the first free sector from SECTOR on: SECTOR = it, Z clear; Z set when none.
;; Also: GETSEC (D1541)
.proc FindFreeSector
    jsr SelectTrack
    tya
    pha
    jsr CheckTrackCount
    lda Track
    jsr SectorsOnTrack
    sta LastSector
    pla
    sta Temporary

;; Each sector below the track's last.
;; Also: GS10 (D1541)
Loop:
    lda Sector
    cmp LastSector
    bcs None
    jsr FindBit::InImage
    bne Done
    inc Sector
    bne Loop

;; A = 0.
;; Also: GS20 (D1541)
None:
    lda #$00

;; Returns.
;; Also: GS30 (D1541)
Done:
    rts
.endproc

;; AVCK: counts the bits set in the selected track's three bytes; error 71, DIR ERROR, when its count byte differs.
;; Also: AVCK (D1541)
.proc CheckTrackCount
    lda Temporary
    pha
    lda #$00
    sta Temporary
    ldy BamEntrySize
    dey

;; Each byte, from the third.
;; Also: AC10 (D1541)
Byte:
    ldx #$07

;; Each bit.
;; Also: AC20 (D1541)
Bit:
    lda (BamPointer),y
    and BitMasks,x
    beq NextBit
    inc Temporary

;; The bit count.
;; Also: AC30 (D1541)
NextBit:
    dex
    bpl Bit
    dey
    bne Byte
    lda (BamPointer),y
    cmp Temporary
    bne Mismatch
    pla
    sta Temporary
    rts

;; Error 71.
;; Also: AC40 (D1541)
Mismatch:
    lda #ERROR_DIRECTORY
    jsr Errors::Abort
.endproc
.endscope

;; MAXSEC: A = the sectors on track A, from the zones (TRKNUM, NUMSEC); Jobs check a track and sector with it and the
;; BAM's routines size a track, so top level (not <Controller::SectorCount>, SECTR, the zero-page count for the job's
;; track).
;; Also: MAXSEC (D1541)
.proc SectorsOnTrack
    ldx ZoneCount

;; Each zone's first track, from the last.
;; Also: MAX1 (D1541)
Zone:
    cmp ZoneLimits-1,x
    dex
    bcs Zone
    lda SectorsPerTrack,x
    rts
.endproc
.scope Commands continued

;; A Commands routine: called before running code in the drive; a stub (RTS), its signal to the controller commented out
;; (Q9).
;; Also: KILLP (D1541)
.proc DisableProtection
    rts
.endproc
.endscope
