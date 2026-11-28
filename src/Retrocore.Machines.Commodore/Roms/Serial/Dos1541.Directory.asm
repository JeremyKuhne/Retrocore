; retrocore: style=strict
; COMMODORE 1541 DOS: THE DIRECTORY LISTING, VALIDATE, NEW AND THE BAM ($EC9E-$F258)

; The part of the DOS that reads the disk as a directory and as a map of its blocks. The directory is listed as a BASIC
; program, which LOAD "$" reads like any file; V and N rebuild the block allocation map (the BAM, the first sector of
; track 18, which holds a free-or-used bit for every sector) from the directory or from nothing; and the BAM's own
; routines allocate, free and count blocks.
;
; The BAM sector holds, after its link to the directory's first block (18/1) and the format letter in its third byte,
; four bytes for each track from 1 to 35: the track's count of free sectors, then three bytes of bits, one bit a
; sector, set when the sector is free. The disk's name, ID and format follow from <DiskNameOffset>. The code works on
; one track's four bytes at a time, an image of them held outside the BAM's buffer, two images for each drive.

.scope Directory continued

; The listing's program.

;; Where the listing loads, written in its first two bytes as a program file's load address does: $0401 is where BASIC
;; keeps its program on a PET (an unexpanded VIC-20 uses $1001), and LOAD "$" relocates the listing anyway.
LISTING_LOAD_ADDRESS = $0401

;; Each byte of a line's link word, which so reads $0101: a placeholder, since the drive cannot know where the computer
;; will put the line. BASIC links the lines again after the load.
LINK_PLACEHOLDER = $01

; The directory's blocks and entries.

;; The directory's track, 18, which <DirectoryTrack> holds as well.
DIRECTORY_TRACK = 18

;; The sector of the directory's first block, which the BAM sector links to.
FIRST_SECTOR = 1

;; The second byte of the link in a chain's last block: the offset of its last byte. $FF is a full block, which is how
;; an empty directory block is written.
LAST_BYTE_OFFSET = $FF

;; The offset in a directory entry of its relative file's first side sector's track, which the sector follows. It is 0
;; for a file that is not relative.
ENTRY_SIDE_SECTOR_TRACK = $13

;; Lists the directory as a BASIC program for LOAD "$", through a read channel with one buffer.
;;
;; The program's first two bytes are its load address, <LISTING_LOAD_ADDRESS>. Then each line is a link word
;; (<LINK_PLACEHOLDER>), its line number, the line's 27 bytes of text from <ListingLine> and a 0, 32 bytes with the line
;; number's two bytes, so a buffer holds eight lines. The first line is the disk's header, with the drive as its number,
;; which <Files::LoadDirectory> has built with <HeaderLine>; the others come from <NextLine>, until the BLOCKS FREE
;; line, then the three zero bytes that end the program. The header's text is two bytes shorter than the others', which
;; makes room for the load address, so the first buffer holds eight lines as well.
;; In: BlockTotal = the header line's number, ListingLine = its text, with the first matching entry already found
;; Out: A = <DataByte>, the channel's first buffer full, or holding all of the listing, with its pointer at 0, the
;;   listing active and the channel ready to talk
;; Errors: 70, NO CHANNEL, when no channel or buffer is free
;; Entry:
;;   FillBuffer = fills the active buffer with the next lines, from the next entry (<NextListingByte> enters here for
;;     each buffer after the first)
;; Also: STDIR (D1541)
.proc StartListing
    ; The channel, with one buffer, for secondary address 0.
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

    ; The load address, then the header line: the placeholder link, the drive as its number, and its text.
    lda #<LISTING_LOAD_ADDRESS
    jsr Files::PutByte
    lda #>LISTING_LOAD_ADDRESS
    jsr Files::PutByte
    lda #LINK_PLACEHOLDER
    jsr Files::PutByte
    jsr Files::PutByte
    lda BlockTotal
    jsr Files::PutByte
    lda #$00
    jsr Files::PutByte
    jsr PutLineText

    ; The header's text ends two bytes sooner, where the 0 that ends the line goes.
    jsr Files::GetActiveBuffer
    asl
    tax
    dec BufferPositions,x
    dec BufferPositions,x
    lda #$00
    jsr Files::PutByte

;; Puts the lines of the next entries into the active buffer, until it is full or the entries end.
;;
;; <Files::PutByte> sets zero when it fills the buffer, so a line's last byte, the 0, ends the loop at the end of the
;; eighth line.
;; Also: DIR1 (D1541)
FillBuffer:
    ; A line: its placeholder link, then the next entry's line number, which is its block count, and its text.
    lda #LINK_PLACEHOLDER
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

;; Makes the filled buffer ready to read: its pointer goes back to 0, the listing is marked active and the channel is
;; ready to talk, and A is <DataByte>. The buffer is full, or has the end of the listing in it.
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

;; Puts in the last line, BLOCKS FREE with the drive's free blocks as its number, then the program's end, three zeros:
;; the line's own, and the zero link that no next line follows. The channel's last byte is the one before the buffer's
;; pointer, so reading stops there, with EOI. Ends in <BufferFull>.
;; Also: DIR3 (D1541)
LastLine:
    lda BlockTotal
    jsr Files::PutByte
    lda BlockTotal+1
    jsr Files::PutByte
    jsr PutLineText

    ; This line's text, too, ends two bytes sooner, where its 0 goes, then the end of the program.
    jsr Files::GetActiveBuffer
    asl
    tax
    dec BufferPositions,x
    dec BufferPositions,x
    lda #$00
    jsr Files::PutByte
    jsr Files::PutByte
    jsr Files::PutByte

    ; The last byte's place, which ChannelLastByte keeps for the channel.
    jsr Files::GetActiveBuffer
    asl
    tay
    lda a:BufferPositions,y
    ldx Channel
    sta ChannelLastByte,x
    dec ChannelLastByte,x
    jmp BufferFull
.endproc

;; Puts the 27 bytes of the listing line's text, from <ListingLine>, into the active buffer.
;; Out: Y = <LISTING_TEXT_LENGTH>
;; Errors: 61, FILE NOT OPEN, when there is no active buffer
;; Also: MOVBUF (D1541)
.proc PutLineText
    ldy #$00

;; Puts each byte.
;; Also: MOVB1 (D1541)
Loop:
    lda ListingLine,y
    jsr Files::PutByte
    iny
    cpy #LISTING_TEXT_LENGTH
    bne Loop
    rts
.endproc

;; Gives the listing's next byte, from the active buffer, and when that was the buffer's last, makes the buffer ready
;; for the lines after it.
;;
;; At the end of the last buffer the channel's status becomes <CHANNEL_TALK_LAST>, so the byte goes out with EOI; before
;; it, <StartListing::FillBuffer> refills the buffer, whose pointer has wrapped to 0.
;; Out: A = the byte
;; Errors: 61, FILE NOT OPEN, with no active buffer, and the errors of reading the directory for the next lines
;; Also: GETDIR (D1541)
.proc NextListingByte
    jsr Files::GetByte
    beq BufferEnd
    rts

;; The byte was the buffer's last: if the listing ends in this buffer, its status says the byte is the last, and
;; otherwise the next lines are put in.
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

;; Puts the next lines in the buffer, and gives the byte again.
;; Also: GD1 (D1541)
Refill:
    pha
    jsr StartListing::FillBuffer
    pla
    rts
.endproc

;; The V command: the BAM is rebuilt from the directory. It marks every block free, then used for the directory's own
;; blocks and for each closed file's, and for a relative file's side sectors too. An entry of a file that was never
;; closed is deleted, so its blocks stay free. Then the BAM is written.
;;
;; The command ends by jumping to <Commands::Finish>, which returns to the caller (to <Commands::Fail> if an error is
;; held).
;; Errors: 66, ILLEGAL TRACK OR SECTOR, for a file's first block, or its first side sector, that is not on the disk
;; Also: VERDIR (D1541), VALDAT (D1541)
.proc Validate
    ; The drive, and a BAM with every block free, written only when the work is done.
    jsr Commands::ParseDriveOnly
    jsr Bam::InitializeDrive
    lda #Bam::WRITE_HOLD
    sta BamWriteDeferred
    jsr Bam::BuildEmpty

    ; The first entry in use, if any.
    lda #$00
    sta FreeEntryIndex
    jsr Search
    bne CheckEntry

;; Marks the directory's own chain, which starts with the BAM sector, 18/0, then writes the BAM and ends the command.
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

;; Marks a closed file's blocks. A relative file's side sectors come first, found by the entry's own pointer to them;
;; the file's first block's track and sector are kept on the stack meanwhile.
;; Also: VD15 (D1541)
ClosedFile:
    ; The file's first track and sector, from the entry.
    iny
    lda (BufferPointer),y
    pha
    iny
    lda (BufferPointer),y
    pha

    ; A relative file has a side sector chain to mark.
    ldy #ENTRY_SIDE_SECTOR_TRACK
    lda (BufferPointer),y
    beq DataBlocks
    sta Track
    iny
    lda (BufferPointer),y
    sta Sector
    jsr MarkChain

;; Marks the file's chain of data blocks.
;; Also: VD17 (D1541)
DataBlocks:
    pla
    sta Sector
    pla
    sta Track
    jsr MarkChain

;; Goes on to the next entry in use, and finishes when there are none.
;; Also: VD20 (D1541)
NextFile:
    jsr Search::Again
    beq Finish

;; Marks a closed file, whose type byte has bit 7 set; deletes the entry of any other.
;; Also: VD25 (D1541)
CheckEntry:
    ldy #$00
    lda (BufferPointer),y
    bmi ClosedFile
    jsr DeleteEntry
    jmp NextFile
.endproc

;; Marks as used in the BAM each block of the chain that starts at <Track> and <Sector>, following the links, which it
;; reads through the internal read channel.
;;
;; The first block is checked to be on the disk. A block's link ends the chain with a track of 0; marking does not
;; notice a block that was already used, so the chain is followed whatever it finds. Ends by jumping to
;; <Files::FreeChannel>, which frees the channel again.
;; In: Track = the first block's track, Sector = its sector
;; Out: Track = 0, Sector = the last link's second byte
;; Errors: 66, ILLEGAL TRACK OR SECTOR, when the first block is not on the disk
;; Also: VMKBAM (D1541)
.proc MarkChain
    jsr Jobs::CheckTrackSector
    jsr Bam::FlushAndMarkUsed
    jsr Files::OpenInternalRead

;; Reads the link of the block the channel is at: its first two bytes, the next block's track and sector.
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

;; Marks the block the link names, and follows the link to it.
;; Also: MRK1 (D1541)
Mark:
    jsr Bam::FlushAndMarkUsed
    jsr Files::FollowLink
    jmp Next
.endproc
.endscope

; The N command, which formats a disk or clears one's directory.
.scope Commands continued

; The disk label, at <DiskNameOffset> in the BAM sector.

;; The disk label's length: the name, padded with shifted spaces, the ID, and the DOS version and format letters, with
;; shifted spaces to this length.
DISK_LABEL_LENGTH = 27

;; The offset of the ID in the disk label: after the 16 characters of the name and two shifted spaces. A shifted space,
;; the version '2' and the format letter follow it.
LABEL_ID_OFFSET = $12

;; The N command: formats a disk and gives it a name, or clears the directory of a disk with the same format.
;;
;; A command with no ':' fails in the parser with 34, SYNTAX ERROR (no name); a ':' alone means drive 0. (The 33 the
;; code checks for, a name whose drive was not given, cannot happen: after the ':' the drive is always found.) With an
;; ID after the name, the disk is formatted: every channel is freed, <Format> runs, and the BAM's buffer is cleared.
;; Without one, only the directory is cleared, on a disk that has this DOS's format (73 otherwise). Either way a new BAM
;; follows, with the name and ID, the DOS version and the format letter. Its own sector and the directory's first are
;; marked used, the BAM is written, and an empty directory block is written to 18/1. Then the BAM is read back, and the
;; command ends by jumping to <Finish>, which returns to the caller.
;; In: CommandBuffer = the command, with the drive, the name and the ID
;; Errors: 73 when no ID is given and the disk's format is not <FormatType>,
;;   and the errors of <Format>, which a failed format reports
;; Also: NEW (D1541)
.proc New
    ; The drive: the command takes only the first name, and must name a drive.
    jsr SetFirstDrive
    lda FileNameDrive
    bpl Drive
    lda #ERROR_INVALID_NAME
    jmp Fail

;; Takes the drive's number from the command, turns on its LED, and looks for the ID after the name's comma: with one,
;; the ID goes to <DiskId> for the drive.
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

    ; The ID, two characters, for the drive.
    lda CommandBuffer,y
    sta DiskId,x
    lda CommandBuffer+1,y
    sta DiskId+1,x

    ; The format, which needs every channel closed, from track 1, then the BAM's buffer cleared.
    jsr Files::FreeAllChannels
    lda #$01
    sta Track
.if REVISION = 6
    ; -06 calls the format through its patch, which first sets the controller's format track to $FF, for no format
    ; under way.
    jsr FormatPatch
.else
    ; The other builds call the format directly.
    jsr Format
.endif
    jsr Bam::ZeroBuffer
    jmp Build

;; No ID: only the directory is cleared, by initializing the drive, and the disk's format must be the DOS's, else error
;; 73, which <Jobs::VersionError> reports.
;; Also: N108 (D1541)
Clear:
    jsr Bam::InitializeDrive
    ldx DriveNumber
    lda DiskVersion,x
    cmp FormatType
    beq Build
    jmp Jobs::VersionError

;; Writes a new BAM and an empty first directory block. The BAM has every block free, the name in the disk label
;; (<DISK_LABEL_LENGTH> bytes), then the ID, the DOS version, '2', and the format letter after it in the label, and the
;; format letter again in the BAM sector's third byte. The BAM sector and the directory's first block are marked used,
;; the BAM is written, and the BAM's buffer is cleared and written to 18/1 as the empty directory block, linked to
;; nothing. The BAM is then read back into its buffer.
;; Also: N110 (D1541)
Build:
    ; A new BAM, and the name in the label: the buffer's pointer goes to the label, then the name is copied there.
    jsr Bam::BuildEmpty
    lda JobNumber
    tay
    asl
    tax
    lda DiskNameOffset
    sta BufferPositions,x
    ldx FileNameStart
    lda #DISK_LABEL_LENGTH
    jsr CopyName

    ; The drive's format, and the ID, the DOS version and the format letter in the label.
    ldy #LABEL_ID_OFFSET
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
    lda #DOS_VERSION+'0'
    sta (BufferPointer),y
    iny
    lda FormatType
    sta (BufferPointer),y

    ; The format letter in the BAM sector too, and the BAM's own sector and the directory's first block used.
    ldy #Bam::FORMAT_OFFSET
    sta (BamPointer),y
    lda DirectoryTrack
    sta Track
    jsr Bam::MarkUsed
    lda #Directory::FIRST_SECTOR
    sta Sector
    jsr Bam::MarkUsed
    jsr Bam::WriteIfDirty

    ; An empty directory block, a full block that links to nothing, written to the directory's first block, then the
    ; BAM read back.
    jsr Bam::ZeroBuffer
    ldy #$01
    lda #Directory::LAST_BYTE_OFFSET
    sta (BamPointer),y
    jsr Jobs::WriteTrackSector
    dec Sector
    jsr Jobs::ReadTrackSector
    jmp Finish
.endproc
.endscope

; The BAM's building and writing, the images of its tracks' entries, and marking a block used or free.
.scope Bam continued

; The BAM sector's layout.

;; The offset of the disk's format letter in the BAM sector, after the link.
FORMAT_OFFSET = 2

;; The offset in the BAM sector where the tracks' entries end: 35 entries of four bytes after the first four bytes.
ENTRIES_END = $90

;; The bytes of a track's bits in its entry, one bit a sector, set when the sector is free.
BITS_BYTES = 3

; What <BamWriteDeferred>'s bits mean.

;; <BamWriteDeferred>'s bit 7: a BAM write is waiting, which <FlushPending> may do.
WRITE_PENDING = $80

;; <BamWriteDeferred>'s bit 6: <FlushPending> is not to write the BAM, as when <Directory::Validate> is changing it
;; block by block.
WRITE_HOLD = $40

;; The bit the allocation routines set in <BamWriteDeferred> while they work, so that swapping a track's image into the
;; BAM's buffer does not write the buffer at once, but sets <WRITE_PENDING> for later.
WRITE_DEFERRED = $01

; The BAM's buffer, as the channel tables hold it.

;; A <ChannelBuffer> entry that has no buffer.
NO_BUFFER = $FF

;; A <ChannelBuffer> entry's bit 7: the buffer is inactive, so it may be taken for another use.
BUFFER_INACTIVE = $80

;; The part of a <ChannelBuffer> entry that is the buffer's number.
BUFFER_NUMBER_MASK = $0F

; The allocation.

;; The passes <AllocateNext>'s search may make: each time it runs off the end of one side of the directory into the
;; other, it counts one in <Temporary>, and at 0 it gives up with DISK FULL.
SEARCH_PASSES = 3

;; The free blocks below which <MarkUsed> reports DISK FULL: two or fewer.
DISK_FULL_LIMIT = 3

;; Builds a new BAM in the BAM's buffer, with every block of every track free, the link to the directory's first block
;; and no images of its entries.
;;
;; Each track's entry is its count of free sectors, from <SectorsOnTrack>, and three bytes of bits with one bit set for
;; each of those sectors. Ends by jumping to <CountFreeBlocks>, which counts them for the drive.
;; In: BamPointer = the BAM's buffer, as <SetPointer> gives it
;; Errors: those of <CountFreeBlocks>
;; Also: NEWMAP (D1541), NEWMPV (D1541)
.proc BuildEmpty
    ; No images, and the link to the directory's first block, 18/1; Y is left at 4, the first track's entry.
    jsr ForgetImages
    ldy #$00
    lda #Directory::DIRECTORY_TRACK
    sta (BamPointer),y
    iny
    tya
    sta (BamPointer),y
    iny
    iny
    iny

;; Starts a track's entry, with Y at it: its three bytes of bits cleared, and its count of free sectors stored, from the
;; track, which is Y divided by four.
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

;; Sets one bit for each of the track's sectors, in the three bytes of <Temporary>, low bit first.
;; Also: NM20 (D1541)
SetBits:
    sec
    rol Temporary
    rol Temporary1
    rol Temporary2
    dex
    bne SetBits

;; Stores the three bytes of bits after the count, with X from 0 to 2, and goes on to the next track, until the entries
;; end.
;; Also: NM30 (D1541)
StoreBits:
    lda Temporary,x
    sta (BamPointer),y
    iny
    inx
    cpx #BITS_BYTES
    bcc StoreBits
    cpy #ENTRIES_END
    bcc NextTrack
    jmp CountFreeBlocks
.endproc

;; Writes the BAM of the drive that the active buffer's last job used, as <WriteIfDirty> does.
;; Also: MAPOUT (D1541)
.proc WriteForChannel
    jsr Files::GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    sta DriveNumber
    .assert * = WriteIfDirty, "WriteForChannel falls into WriteIfDirty."
    ; Falls into WriteIfDirty.
.endproc

;; Writes the drive's BAM when it has changed: the track images go back into the BAM's buffer, each track's count is
;; checked against its bits, and the buffer is written. Does nothing when it has not.
;;
;; Ends by jumping to <Jobs::Write>.
;; In: DriveNumber = the drive
;; Errors: 71, DIR ERROR, when a track's count differs from its bits; 70, NO CHANNEL, when the BAM has no buffer
;; Also: SCRBAM (D1541)
.proc WriteIfDirty
    ldy DriveNumber
    lda BamDirty,y
    bne Dirty
    rts

;; Clears the drive's flag, finds the BAM's buffer, and puts both of the drive's images back into it.
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

;; Checks the count of each track, from 1: its entry is four bytes at the track times four in the buffer.
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

;; Points <BamPointer> to the start of the drive's BAM buffer, reading the BAM into one if it has none.
;; Out: BamPointer = the buffer, JobNumber = its number
;; Errors: 70, NO CHANNEL, when the BAM has no buffer and none is free
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

;; Copies the drive's count of free blocks into <BlockTotal>, for the directory listing and the messages.
;; Out: BlockTotal = the count, low byte then high
;; Keeps: Y
;; Also: NUMFRE (D1541)
.proc CopyFreeBlocks
    ldx DriveNumber
    lda FreeBlocks,x
    sta BlockTotal
    lda FreeBlocksHigh,x
    sta BlockTotal+1
    rts
.endproc

;; Does what <FlushPending> does, then frees the block as <MarkFree> does. Nothing calls it: it is the entry of
;; <MarkFree> that the listing has with a flush first, as <FlushAndMarkUsed> has for <MarkUsed>, and the ROM carries its
;; three bytes.
;; In: Track = the block's track, Sector = its sector
;; Errors: those of <FlushPending> and <MarkFree>
;; Also: WFREE (D1541)
.proc FlushAndMarkFree
    jsr FlushPending
    .assert * = MarkFree, "FlushAndMarkFree falls into MarkFree."
    ; Falls into MarkFree.
.endproc

;; Marks a block free in the BAM: its bit is set, its track's count goes up and, off the directory track, so does the
;; drive's count of free blocks. A block that is free already is left alone.
;;
;; A block on the directory track is a slip, documented and not changed: it branches to <MarkUsed::CountDown> instead,
;; which takes one from the free blocks, where it should leave the count. That count down does not borrow (when the low
;; byte is 0 the high byte stays, so the count is off by 256), and it falls into <MarkUsed::CheckFull>, so with fewer
;; than three blocks left, freeing a block on the directory track can set error 72, DISK FULL.
;; In: Track = the block's track, Sector = its sector
;; Out: carry = set when the block was free already and nothing was done; after a block is freed it is what the
;;   compare left (on the directory's track, <MarkUsed::CheckFull>'s), so it should not be used
;; Errors: <SelectTrack>'s errors; its recovery path sets no message
;; Also: FRETS (D1541)
.proc MarkFree
    jsr FindBit
    sec
    bne Done

    ; The bit set, the BAM marked changed, and the track's count up.
    lda (BamPointer),y
    ora BitMasks,x
    sta (BamPointer),y
    jsr MarkDirty
    ldy Temporary
    clc
    lda (BamPointer),y
    adc #$01
    sta (BamPointer),y

    ; The drive's count of free blocks up, 16 bits, except for the directory track (see above).
    lda Track
    cmp DirectoryTrack
    beq MarkUsed::CountDown
    inc FreeBlocks,x
    bne Done
    inc FreeBlocksHigh,x

;; Returns.
;; Also: FRE10 (D1541), FRERTS (D1541)
Done:
    rts
.endproc

;; Sets the drive's flag that its BAM has changed.
;; Out: X = <DriveNumber>
;; Keeps: Y
;; Also: DTYBAM (D1541)
.proc MarkDirty
    ldx DriveNumber
    lda #$01
    sta BamDirty,x
    rts
.endproc

;; Does what <FlushPending> does, then marks the block used as <MarkUsed> does.
;; In: Track = the block's track, Sector = its sector
;; Errors: those of <FlushPending> and <MarkUsed>
;; Also: WUSED (D1541)
.proc FlushAndMarkUsed
    jsr FlushPending
    .assert * = MarkUsed, "FlushAndMarkUsed falls into MarkUsed."
    ; Falls into MarkUsed.
.endproc

;; Marks a block used in the BAM: its bit is cleared, its track's count goes down and, off the directory track, so does
;; the drive's count of free blocks. A block that is used already is left alone. With fewer than <DISK_FULL_LIMIT>
;; blocks left, whichever block it was, it sets error 72, DISK FULL, which the error channel reports while the command
;; goes on.
;; In: Track = the block's track, Sector = its sector
;; Out: zero = set when the block was used already and nothing was done; after a block is marked it is what the count's
;;   last compare left, so it says nothing
;; Errors: <SelectTrack>'s errors; its recovery path sets no message; error 72 is set as a message, not ended with
;; Entry:
;;   CountDown = takes one from the drive's count of free blocks (<MarkFree> enters here for the directory track)
;;   CheckFull = checks the count, as it does after counting down
;; Also: USEDTS (D1541)
.proc MarkUsed
    jsr FindBit
    beq Done

    ; The bit cleared, the BAM marked changed, and the track's count down.
    lda (BamPointer),y
    eor BitMasks,x
    sta (BamPointer),y
    jsr MarkDirty
    ldy Temporary
    lda (BamPointer),y
    sec
    sbc #$01
    sta (BamPointer),y

    ; The drive's count of free blocks down, 16 bits, except for the directory track.
    lda Track
    cmp DirectoryTrack
    beq CheckFull
    lda FreeBlocks,x
    bne CountDown
    dec FreeBlocksHigh,x

;; Takes one from the drive's count of free blocks, the low byte only: <MarkFree> enters here for the directory track,
;; and does not borrow.
;; Also: USE10 (D1541)
CountDown:
    dec FreeBlocks,x

;; Checks that three or more blocks are free, or sets error 72, DISK FULL.
;; Also: USE20 (D1541)
CheckFull:
    lda FreeBlocksHigh,x
    bne Done
    lda FreeBlocks,x
    cmp #DISK_FULL_LIMIT
    bcs Done
    lda #ERROR_DISK_FULL
    jsr Errors::SetMessage

;; Returns.
;; Also: USERTS (D1541)
Done:
    rts
.endproc

;; Finds where a sector's bit is in the BAM: the track's image is made current, and its byte and bit found.
;;
;; The image's first byte is the track's count, and the bits follow, so the sector's byte is its sector divided by 8,
;; plus 1.
;; In: Track = the track, Sector = the sector
;; Out: BamPointer = the track's image, Y = the offset in it of the byte with the sector's bit, X = the bit's number,
;;   Temporary = the offset of the track's count, 0, A = the byte's value at that bit: zero set when the sector is used
;; Errors: <SelectTrack>'s errors; its recovery path sets no message
;; Entry:
;;   InImage = takes the image as it is, with <BamPointer> and <Temporary> set (<FindFreeSector> enters here for each
;;     sector of a track)
;; Also: FREUSE (D1541)
.proc FindBit
    jsr SelectTrack
    tya
    sta Temporary

;; Finds the bit of the sector in <Sector>, in the image that <BamPointer> is at, whose count is at <Temporary>.
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

;; The eight single-bit masks, 1 to 128, by the bit's number. The BAM's routines test and flip a sector's bit with them,
;; and so does the buffer allocation (<Files::FindFreeBuffer>), so the table is not in either family.
;; Also: BMASK (D1541)
BitMasks:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

; The BAM's writes, its buffer and images, and the search for a block to allocate.
.scope Bam continued

;; Writes the BAM now, if a write is pending and writes are not held back, clearing <BamWriteDeferred> for it.
;;
;; <BamWriteDeferred>'s bit 7, <WRITE_PENDING>, says a write is waiting, and bit 6, <WRITE_HOLD>, holds it back; a byte
;; of 0, or with only the lower bits, is not a write. Ends by jumping to <Jobs::Write>.
;; Out: BamWriteDeferred = 0 when it wrote
;; Also: FIXBAM (D1541)
.proc FlushPending
    ; A is $FF so that zero means the byte is 0 (BIT only tests); zero says nothing is set, negative that a write is
    ; pending, and overflow that it is held back.
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

;; Clears the BAM's buffer, all 256 bytes, for the N command.
;; Out: BamPointer = the buffer, A = 0, Y = 0
;; Errors: 70, NO CHANNEL, when the BAM has no buffer and none is free
;; Also: CLRBAM (D1541)
.proc ZeroBuffer
    jsr SetPointer
    ldy #$00
    tya

;; Clears each byte.
;; Also: CLB1 (D1541)
Loop:
    sta (BamPointer),y
    iny
    bne Loop
    rts
.endproc

;; Makes the image of the track's entry current and points <BamPointer> to it. The drive keeps two images of its BAM's
;; track entries, outside the BAM buffer, four bytes each, and <LastImage> notes the one used last; when neither has the
;; track, <SwapIn> brings it in.
;; In: Track = the track, DriveNumber = the drive
;; Out: BamPointer = the track's image, Y = 0, LastImage = the image's number
;; Errors: 70, NO CHANNEL, when the BAM has no buffer and none is free. A drive with no disk (<NoDrive> set) goes to
;;   <Errors::Recover> with 74 in A, which ends the command without setting that error's message
;; Keeps: Temporary, Temporary1
;; Also: SETBAM (D1541)
.proc SelectTrack
    ; Temporary and Temporary1 are saved.
    lda Temporary
    pha
    lda Temporary1
    pha
    ldx DriveNumber
    lda NoDrive,x
    beq HaveDrive
    lda #ERROR_DRIVE_NOT_READY
    jsr Errors::Recover

;; Finds the BAM's channel index and the drive's two images, <Temporary> and <Temporary1> kept for them, and looks for
;; the track among them.
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

;; Notes the image used as the drive's last and points <BamPointer> to it, the images being four bytes each, and puts
;; <Temporary> and <Temporary1> back.
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

;; Brings the track's four bytes of the BAM into an image, in place of the one used less recently, which goes back to
;; the BAM's buffer. The track's bytes in the buffer are cleared as they are taken. Then the buffer is written, unless
;; <BamWriteDeferred> is not 0, when the write is only marked pending.
;; In: Track = the track, Temporary = the BAM's channel index (<ChannelIndex>)
;; Out: Temporary1 = the image's number, ImageTracks = the track for it
;; Errors: 70, NO CHANNEL, when the BAM has no buffer and none is free
;; Also: SWAP (D1541)
.proc SwapIn
    ; The BAM's buffer, and the image to replace: the drive's other one than was used last.
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

    ; The buffer's pointer to the track's four bytes, and the image's offset in Y.
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

;; Moves each of the four bytes into the image, clearing it in the buffer.
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

    ; The image's track, and the buffer written unless writes are deferred.
    ldx Temporary1
    lda Track
    sta ImageTracks,x
    lda BamWriteDeferred
    bne Pending
    jmp Jobs::Write

;; The write is left for later: <WRITE_PENDING> is set.
;; Also: SWAP4 (D1541)
Pending:
    ora #WRITE_PENDING
    sta BamWriteDeferred
    rts
.endproc

;; Puts an image back into the BAM's buffer, at its track's place, and empties the image and its track. An image with no
;; track, which is empty, is left alone.
;; In: A = the image's number, 0 to 3, JobNumber = the BAM's buffer
;; Also: PUTBAM (D1541)
.proc PutImage
    tay
    lda ImageTracks,y
    beq Done

    ; The track cleared, and the buffer's pointer to the track's place, four bytes a track.
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

;; Moves each of the four bytes into the buffer, clearing it in the image.
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

;; Forgets the drive's two images: their tracks are cleared, so nothing is put back for them.
;; In: DriveNumber = the drive
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

;; Reads the BAM into a buffer, when it has none.
;;
;; The buffer is one that may be taken for another use, being marked inactive. The sector read is the directory track's
;; first.
;; In: X = the BAM's channel index (<ChannelIndex>)
;; Out: JobNumber = the BAM's buffer
;; Errors: 70, NO CHANNEL, when no buffer is free
;; Also: REDBAM (D1541)
.proc ReadIfNeeded
    lda ChannelBuffer,x
    cmp #NO_BUFFER
    bne InMemory
    txa
    pha
    jsr Files::GetBuffer
    tax
    bpl Got
    lda #ERROR_NO_CHANNEL
    jsr Commands::Fail

;; The buffer is the BAM's, marked inactive, and the BAM is read into it.
;; Also: RBM10 (D1541)
Got:
    stx JobNumber
    pla
    tay
    txa
    ora #BUFFER_INACTIVE
    sta a:ChannelBuffer,y
    asl
    tax
    lda DirectoryTrack
    sta JobHeaders,x
    lda #$00
    sta JobHeaders+1,x
    jmp Jobs::Read

;; The BAM has its buffer already: its number is the entry's low bits.
;; Also: RBM20 (D1541)
InMemory:
    and #BUFFER_NUMBER_MASK
    sta JobNumber
    rts
.endproc

;; Gives the BAM's place in <ChannelBuffer> and <ChannelSecondBuffer> for the drive.
;;
;; The BAM's buffer is the seventh entry of one table or the other: <BAM_CHANNEL> for drive 1, and for drive 0 the
;; second table's, <CHANNEL_COUNT> + 1 on, since that table follows the first by seven bytes.
;; In: DriveNumber = the drive
;; Out: A = the index, X = <DriveNumber>
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

;; Gives the BAM's channel index in X, as <ChannelIndex> gives it in A.
;; Out: A = X = the index
;; Also: BAM2X (D1541)
.proc ChannelIndexInX
    jsr ChannelIndex
    tax
    rts
.endproc

;; Allocates the free block after the active buffer's block, for a file that grows: the next sector in the same track,
;; the interleave on from the block's, or else the next track outward from the block's that has one.
;;
;; The search is on the block's track first, then tracks outward from it, on the side of the directory it is, to track 1
;; or the last track, then the other side from the directory's neighbour outward. The block is marked used. The BAM's
;; writes are deferred, <BamWriteDeferred>'s bit 0, so the caller writes it. Relative files use it.
;; Out: Track = the block's track, Sector = its sector
;; Errors: 72, DISK FULL, when no track has a free block; 71, DIR ERROR, when the BAM counts a free block that the bits
;;   do not show; and <SelectTrack>'s errors
;; Entry:
;;   Search = looks from <Track> and <Sector> as they stand, with <Temporary> the passes to make, <SEARCH_PASSES> for a
;;     file (<Directory::NewBlock> enters here for a directory block)
;; Also: NXTTS (D1541)
.proc AllocateNext
    ; The block's track and sector, the passes to make, and the BAM's writes deferred.
    jsr Files::GetBufferBlock
    lda #SEARCH_PASSES
    sta Temporary
    lda #WRITE_DEFERRED
    ora BamWriteDeferred
    sta BamWriteDeferred

;; Looks at the track for a free block, going to others: the track is the directory's, none free is DISK FULL, a track
;; below it goes down to track 1, then up from the directory's neighbour, a track above goes up to the last, then down
;; from the neighbour; each change of side costs a pass.
;; Also: NXTDS (D1541), NXT1 (D1541)
Search:
    ; The track's image, with Temporary, the passes, kept; its count of free sectors says whether it has any.
    lda Temporary
    pha
    jsr SelectTrack
    pla
    sta Temporary
    lda (BamPointer),y
    bne NextSector

    ; None here. The directory track, with none, is a full disk; tracks below it go down, above it go up.
    lda Track
    cmp DirectoryTrack
    beq DiskFull
    bcc Downward
    inc Track
    lda Track
    cmp TrackLimit
    bne Search

    ; Past the last track: the directory's neighbour below, from sector 0, and a pass used.
    ldx DirectoryTrack
    dex
    stx Track
    lda #$00
    sta Sector
    dec Temporary
    bne Search

;; Ends the command with error 72, DISK FULL.
;; Also: NXTERR (D1541)
DiskFull:
    lda #ERROR_DISK_FULL
    jsr Commands::Fail

;; A track below the directory's: the next one down, and past track 1 the directory's neighbour above, from sector 0,
;; and a pass used; with none left, DISK FULL.
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

;; The track has a free block. The next sector is the interleave on from the block's, past the track's last sector
;; wrapping to the start of the track. The track's count of sectors goes in <LastSector>, and in <JobCommand>, which the
;; listing also sets here and nothing reads.
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

;; Looks for a free sector from there on.
;; Also: FNDN0 (D1541)
FindSector:
    jsr FindFreeSector
    beq FromStart

;; Marks the sector used, which ends the routine.
;; Also: FNDN1 (D1541)
Use:
    jmp FlushAndMarkUsed

;; No free sector from there to the track's end: looks again from sector 0, and none there either, when the count said
;; there was one, is a directory error, 71.
;; Also: FNDN2 (D1541)
FromStart:
    lda #$00
    sta Sector
    jsr FindFreeSector
    bne Use
    jmp AllocateFirst::DirectoryError
.endproc

;; Allocates the first block of a new file: the free block of the track nearest the directory's, from sector 0. The
;; tracks are tried in turn below the directory first and then above it, 17, 19, 16, 20 and on, those that do not exist
;; skipped. The block is marked used.
;;
;; The BAM's writes are deferred, <BamWriteDeferred>'s bit 0, so the caller writes it.
;; Out: Track = the block's track, Sector = its sector
;; Errors: 67, ILLEGAL TRACK OR SECTOR, when the tracks above the directory's run out; 71, DIR ERROR, when the
;;   BAM counts a free block that the bits do not show; and <SelectTrack>'s errors
;; Keeps: Work0
;; Entry:
;;   DirectoryError = ends the command with error 71 (<AllocateNext::FromStart> jumps here)
;; Also: INTTS (D1541)
.proc AllocateFirst
    ; The BAM's writes deferred, and the distance from the directory's track, in Work0, 1 to begin with.
    lda #WRITE_DEFERRED
    ora BamWriteDeferred
    sta BamWriteDeferred
    lda Work0
    pha
    lda #$01
    sta Work0

;; The track below the directory's by the distance, if there is one, and when its count is not 0 the search is done.
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

;; The track above the directory's by the distance, which then grows by one; past the last track, error 67.
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

;; With free blocks there, the search is done; without, the next distance, below first.
;; Also: ITS3 (D1541)
CheckAbove:
    jsr SelectTrack
    lda (BamPointer),y
    beq Below

;; Gives <Work0> back, and takes the track's first free sector, which is marked used.
;; Also: FNDSEC (D1541)
FindSector:
    pla
    sta Work0
    lda #$00
    sta Sector
    jsr FindFreeSector
    beq DirectoryError
    jmp FlushAndMarkUsed

;; Ends the command with error 71, DIR ERROR: the BAM counted a free block that the track's bits do not show. Reached
;; when a search for a free sector of a track that has one finds none.
;; Also: FND2 (D1541), DERR (D1541)
DirectoryError:
    lda #ERROR_DIRECTORY
    jsr Errors::Abort
.endproc

;; Finds the first free sector of the track from a sector on, after checking that the track's count agrees with its
;; bits.
;; In: Track = the track, Sector = the first sector to look at
;; Out: Sector = the free sector, zero = clear; or, with none, A = 0 and zero = set
;; Errors: 71, DIR ERROR, when the track's count differs from its bits; and <SelectTrack>'s errors
;; Also: GETSEC (D1541)
.proc FindFreeSector
    ; The track's image, and its count checked against its bits, then the track's last sector.
    jsr SelectTrack
    tya
    pha
    jsr CheckTrackCount
    lda Track
    jsr SectorsOnTrack
    sta LastSector
    pla
    sta Temporary

;; Looks at each sector below the track's last, from <Sector>, until a bit says free.
;; Also: GS10 (D1541)
Loop:
    lda Sector
    cmp LastSector
    bcs None
    jsr FindBit::InImage
    bne Done
    inc Sector
    bne Loop

;; No sector is free: A is 0, which sets zero.
;; Also: GS20 (D1541)
None:
    lda #$00

;; Returns.
;; Also: GS30 (D1541)
Done:
    rts
.endproc

;; Checks that the number of bits set in the track's entry is its count.
;; In: BamPointer = the track's entry, or its image
;; Out: Y = 0
;; Errors: 71, DIR ERROR, when the count differs
;; Keeps: Temporary
;; Also: AVCK (D1541)
.proc CheckTrackCount
    ; Temporary is saved, then counts the bits of the entry's bytes, from the last to the first after the count.
    lda Temporary
    pha
    lda #$00
    sta Temporary
    ldy BamEntrySize
    dey

;; Counts the bits of each byte, from the last.
;; Also: AC10 (D1541)
Byte:
    ldx #$07

;; Counts a bit of the byte, from bit 7.
;; Also: AC20 (D1541)
Bit:
    lda (BamPointer),y
    and BitMasks,x
    beq NextBit
    inc Temporary

;; On to the next bit, and then the next byte, down to the count.
;; Also: AC30 (D1541)
NextBit:
    dex
    bpl Bit
    dey
    bne Byte

    ; Y is 0, at the count: it must equal the bits.
    lda (BamPointer),y
    cmp Temporary
    bne Mismatch
    pla
    sta Temporary
    rts

;; Ends the command with error 71, DIR ERROR.
;; Also: AC40 (D1541)
Mismatch:
    lda #ERROR_DIRECTORY
    jsr Errors::Abort
.endproc
.endscope

;; Gives the number of sectors on a track, from its zone: the zones are those of <ZoneLimits>, and <SectorsPerTrack> has
;; each one's count, 21 on tracks 1 to 17, 19 on 18 to 24, 18 on 25 to 30 and 17 on 31 to 35. Jobs check a track and
;; sector with it, and the BAM's routines size a track, so it is not in either family. It is not
;; <Controller::SectorCount>, the zero page count of the job's track that the controller keeps.
;; In: A = the track, 1 to 35
;; Out: A = the sectors on the track, X = the zone's number
;; Keeps: Y
;; Also: MAXSEC (D1541)
.proc SectorsOnTrack
    ldx ZoneCount

;; Goes through the zones from the one of tracks 1 to 17 outward, comparing with <ZoneLimits> from its last byte (18,
;; 25, 31, 36), each the first track past its zone, until the track is below one.
;; Also: MAX1 (D1541)
Zone:
    cmp ZoneLimits-1,x
    dex
    bcs Zone
    lda SectorsPerTrack,x
    rts
.endproc

; A routine the commands call.
.scope Commands continued

;; Does nothing and returns. The block, memory-write, memory-execute and utility-loader commands (every M command but
;; M-R) call it before they run code in the drive. Its name in the listing, KILLP, is "kill protection", and the listing
;; keeps as comments the code that told the controller, by a flag it cleared when it had taken it, to do that; the stub
;; has only the RTS.
;; Also: KILLP (D1541)
.proc DisableProtection
    rts
.endproc
.endscope
