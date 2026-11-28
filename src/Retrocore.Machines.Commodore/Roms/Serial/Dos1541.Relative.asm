; retrocore: style=strict
; COMMODORE 1541 DOS: THE SIDE SECTORS AND THE RELATIVE FILES ($DDF1-$E4FB)
.scope Files continued

;; Writes the active buffer back to its block if it is dirty, and waits.
;; Also: SCRUB (D1541)
.proc Flush
    jsr GetActiveBufferState
    bvc Clean
    jsr WriteBuffer
    jsr Jobs::Wait

;; Clean, or written.
;; Also: SCR1 (D1541)
Clean:
    rts
.endproc
.endscope
.scope Relative continued

;; `track` and `sector` into the active buffer's link, its first two bytes; marks it dirty with <MarkDirty> (Q2).
;; Also: SETLNK (D1541)
.proc SetLink
    jsr PointAtBuffer
    lda Track
    sta (BufferPointer),y
    iny
    lda Sector
    sta (BufferPointer),y
    jmp MarkDirty
.endproc

;; The active buffer's link into `track` and `sector`, leaving its pointer alone.
;; Also: GETLNK (D1541)
.proc GetLink
    jsr PointAtBuffer
    lda (BufferPointer),y
    sta Track
    iny
    lda (BufferPointer),y
    sta Sector
    rts
.endproc

;; Makes the active buffer the file's last block: track link 0, and the sector link `nr` - 1, the last byte used.
;; Also: NULLNK (D1541)
.proc EndLink
    jsr PointAtBuffer
    lda #$00
    sta (BufferPointer),y
    iny
    ldx Channel
    lda ChannelNextRecord,x
    tax
    dex
    txa
    sta (BufferPointer),y
    rts
.endproc

;; `dirbuf` = the active buffer's start; Y = 0.
;; Also: SET00 (D1541)
.proc PointAtBuffer
    jsr Files::GetActiveBuffer
    asl
    tax
    lda BufferPositions+1,x
    sta BufferPointer+1
    lda #$00
    sta BufferPointer
    ldy #$00
    rts
.endproc
.endscope
.scope Files continued

;; Finds the channel for `sa` (`Files::FindReadChannel`), and falls into <GetBufferBlock>.
;; Also: CURBLK (D1541)
.proc GetChannelBlock
    jsr FindReadChannel
.endproc

;; The block the active buffer holds, from its job header, into `track` and `sector`; `jobnum` = the buffer.
;; Also: GETHDR (D1541)
.proc GetBufferBlock
    jsr GetActiveBuffer
    sta JobNumber
    asl
    tay
    lda a:JobHeaders,y
    sta Track
    lda a:JobHeaders+1,y
    sta Sector
    rts
.endproc

;; Starts writing the active buffer to the block at `track` and `sector` (<StartBlockJob>); the caller waits.
;; Also: WRTAB (D1541)
.proc WriteBlock
    lda #JOB_WRITE
    sta JobCommand
    bne StartBlockJob
.endproc

;; Starts reading the block at `track` and `sector` into the active buffer; the caller waits.
;; Also: RDAB (D1541)
.proc ReadBlock
    lda #JOB_READ
    sta JobCommand
    bne StartBlockJob
.endproc

;; Starts writing the channel's active buffer out to the block its header names, whether or not it is dirty (SCRUB,
;; `Files::Flush`, tests that first), and clears its dirty bit (<StartBlockJob::ClearDirty>); the caller waits.
;; Also: WRTOUT (D1541)
.proc WriteBuffer
    lda #JOB_WRITE
    sta JobCommand
    bne StartBlockJob::ClearDirty
    lda #JOB_READ
    sta JobCommand
    bne StartBlockJob::ClearDirty
.endproc
.endscope
.scope Relative continued

;; Starts writing the side-sector buffer to its header's block; branches to <ReadSideSector>'s SetCommand.
;; Also: WRTSS (D1541)
.proc WriteSideSector
    lda #JOB_WRITE
    sta JobCommand
    bne ReadSideSector::SetCommand
.endproc

;; Starts reading the side-sector buffer from its header's block, falling into SetCommand and from there, for an
;; allocated buffer, StartBlockJob::Start (Q3).
;; Entry:
;;   SetCommand = The command into `cmd`
;; Also: RDSS (D1541)
.proc ReadSideSector
    lda #JOB_READ

;; The command into `cmd`; X = the channel's side-sector buffer. <WriteSideSector> branches here, and <ReadSideSector>
;; falls into it.
;; Also: RDS5 (D1541)
SetCommand:
    sta JobCommand
    ldx Channel
    lda ChannelSideSector,x
    tax
    bpl Files::StartBlockJob::Start
.endproc
.endscope
.scope Files continued

;; The starters' tail (Q3): sets the active buffer's header from `track` and `sector`, and its drive in `lstjob`...
;; Entry:
;;   ClearDirty = ...clears its dirty bit (<MarkClean>), X = the buffer
;;   Start = ...and starts the job in `cmd` on buffer X, with the drive in `lstjob` (`Jobs::StartOnLast
;; Also: SJ10 (D1541)
.proc StartBlockJob
    jsr Jobs::SetHeader
    jsr GetActiveBuffer
    tax
    lda DriveNumber
    sta LastJobs,x

;; ...clears its dirty bit (<MarkClean>), X = the buffer...
;; Also: SJ20 (D1541)
ClearDirty:
    jsr MarkClean
    jsr GetActiveBuffer
    tax

;; ...and starts the job in `cmd` on buffer X, with the drive in `lstjob` (`Jobs::StartOnLastDrive`).
;; Also: SJ30 (D1541)
Start:
    jmp Jobs::StartOnLastDrive
.endproc

;; The active buffer's link into `track` and `sector`, read through its pointer, which is left at 2.
;; Also: RDLNK (D1541)
.proc ReadLink
    lda #$00
    jsr SetPointer
    jsr GetByte
    sta Track
    jsr GetByte
    sta Sector
    rts
.endproc
.endscope
.scope Relative continued

;; Copies A bytes (counting down) from the start of buffer Y to the start of buffer X; a count of 1 to 129 copies that
;; many bytes; 0 or 130 to 255 copies one, as its loop ends with `bpl` (Q11). Its one caller copies 16.
;; Also: B0TOB0 (D1541)
.proc CopyBuffer
    pha
    lda #$00
    sta Temporary
    sta Temporary+2
    lda BufferPages,y
    sta Temporary+1
    lda BufferPages,x
    sta Temporary+3
    pla
    tay
    dey

;; Each byte, last first.
;; Also: B02 (D1541)
NextByte:
    lda (Temporary),y
    sta (Temporary+2),y
    dey
    bpl NextByte
    rts
.endproc

;; Fills buffer A with zeros; returns A and Y = 0.
;; Also: CLRBUF (D1541)
.proc ClearBuffer
    tay
    lda BufferPages,y
    sta Temporary+1
    lda #$00
    sta Temporary
    tay

;; Each of the 256 bytes.
;; Also: CB10 (D1541)
NextByte:
    sta (Temporary),y
    iny
    bne NextByte
    rts
.endproc

;; `dirbuf` = the start of the side-sector buffer; A = the number of the side sector in it (its byte 2).
;; Also: SSSET (D1541)
.proc GetSideSectorNumber
    lda #$00
    jsr PointAtSideSector
    ldy #$02
    lda (BufferPointer),y
    rts
.endproc

;; `dirbuf` = byte A of the side-sector buffer; X = that buffer.
;; Also: SSDIR (D1541)
.proc PointAtSideSector
    sta BufferPointer
    ldx Channel
    lda ChannelSideSector,x
    tax
    lda BufferPages,x
    sta BufferPointer+1
    rts
.endproc

;; `dirbuf` and the side-sector buffer's `buftab` pointer = byte A of it.
;; Also: SETSSP (D1541)
.proc SetSideSectorPointer
    pha
    jsr PointAtSideSector
    pha
    txa
    asl
    tax
    pla
    sta BufferPositions+1,x
    pla
    sta BufferPositions,x
    rts
.endproc

;; Puts the side sector `ssnum` in its buffer, reading it if it exists and is not there, pointing at entry `ssind`: V
;; clear. Past the file's end: points at its last entry (<SeekEnd>), V set.
;; Also: SSPOS (D1541)
.proc PositionSideSector
    jsr TestSideSector
    bmi OutOfRange
    bvc InRange
    ldx Channel
    lda ChannelSideSector,x
    jsr ReadLinkedSideSector
    jsr TestSideSector
    bpl InRange

;; Past the end: <SeekEnd>, V set.
;; Also: SSP10 (D1541)
OutOfRange:
    jsr SeekEnd
    bit BitOverflow
    rts

;; The pointer at `ssind`, V clear.
;; Also: SSP20 (D1541)
InRange:
    lda SideSectorIndex
    jsr SetSideSectorPointer
    bit BitNeither
    rts
.endproc

;; Reads into buffer A the side sector whose track and sector are at (`dirbuf`),Y, on the drive of the channel in X
;; (`lindx`), and waits.
;; Also: IBRD (D1541)
.proc ReadLinkedSideSector
    sta JobNumber
    lda #JOB_READ
    bne StartJob
    sta JobNumber
    lda #JOB_WRITE

;; The command with the drive (from `filtyp`) into `cmd`, the track and sector into the buffer's header, then
;; `Jobs::Run::Repeat` starts it and waits.
;; Also: IBOP (D1541)
StartJob:
    pha
    lda ChannelFileType,x
    and #$01
    sta DriveNumber
    pla
    ora DriveNumber
    sta JobCommand
    lda (BufferPointer),y
    sta Track
    iny
    lda (BufferPointer),y
    sta Sector
    lda JobNumber
    jsr Jobs::SetHeader::ForBuffer
    ldx JobNumber
    jmp Jobs::Run::Repeat
.endproc

;; A = the side-sector buffer's pointer, with `dirbuf` there (through `Files::GetPointer::OfBuffer`).
;; Also: GSSPNT (D1541)
.proc GetSideSectorPointer
    ldx Channel
    lda ChannelSideSector,x
    jmp Files::GetPointer::OfBuffer
.endproc

;; The loop's body, before its entry (Q5): adds 120 to `t1`/`t2` for each whole side sector.
;; Entry:
;;   Start = Where callers enter
;; Also: SCAL1 (D1541)
.proc CountBlocks
    lda #POINTERS_PER_SIDE_SECTOR
    jsr AddToCount

;; Where callers enter: adds to `t1`/`t2` 120 for each of X side sectors, half `t3` (the entries), and `t4` (the side
;; sectors' own blocks): a file's block count. Falls into <AddToCount>.
;; Also: SSCALC (D1541)
Start:
    dex
    bpl CountBlocks
    lda Temporary3
    lsr
    jsr AddToCount
    lda Temporary4
.endproc

;; `t1`/`t2` += A.
;; Also: ADDT12 (D1541)
.proc AddToCount
    clc
    adc Temporary1
    sta Temporary1
    bcc Done
    inc Temporary2

;; No carry.
;; Also: ADDRTS (D1541)
Done:
    rts
.endproc

;; Is entry `ssind` of side sector `ssnum` in the buffer and used? N clear, V clear: yes. N clear, V set: that side
;; sector exists but is not in the buffer. N set: past the end, V clear if the side sector is in the buffer.
;; Also: SSTEST (D1541)
.proc TestSideSector
    jsr GetSideSectorNumber
    cmp SideSectorNumber
    bne NotLoaded
    ldy SideSectorIndex
    lda (BufferPointer),y
    beq PastEnd
    bit BitNeither
    rts

;; In the buffer, but the entry is empty: past the end.
;; Also: ST10 (D1541)
PastEnd:
    bit BitNegative
    rts

;; Another side sector: looks for its link in the buffer's table of side sectors (byte 4 on); leaves `dirbuf` at $xx04
;; and Y = 2 * `ssnum` for <ReadLinkedSideSector>.
;; Also: ST20 (D1541)
NotLoaded:
    lda SideSectorNumber
    cmp #SIDE_SECTOR_COUNT
    bcs NoSuchSideSector
    asl
    tay
    lda #$04
    sta BufferPointer
    lda (BufferPointer),y
    bne Exists

;; `ssnum` is 6 or more, or has no link: past the end.
;; Also: ST30 (D1541)
NoSuchSideSector:
    bit BitBoth
    rts

;; It exists, not in the buffer.
;; Also: ST40 (D1541)
Exists:
    bit BitOverflow
    rts
.endproc
.endscope
.scope Files continued

;; A = the channel `lindx`'s active buffer (`buf0`, else `buf1`), its dirty bit off; X = `lindx`; N set if it has none
;; (Q1).
;; Also: GETACT (D1541)
.proc GetActiveBuffer
    ldx Channel
    lda ChannelBuffer,x
    bpl StripDirty
    lda ChannelSecondBuffer,x

;; Takes the dirty bit off.
;; Also: GA1 (D1541)
StripDirty:
    and #$BF
    rts
.endproc

;; As <GetActiveBuffer>, with `lbused` = the index of its `buf0`/`buf1` byte (for writing back), and V = its dirty bit;
;; clobbers `t1`.
;; Also: GAFLGS (D1541)
.proc GetActiveBufferState
    ldx Channel
    stx ActiveBufferSlot
    lda ChannelBuffer,x
    bpl TestFlags
    txa
    clc
    adc #CHANNEL_COUNT+1
    sta ActiveBufferSlot
    lda ChannelSecondBuffer,x

;; The buffer number, with N and V from the byte's top bits.
;; Also: GA3 (D1541)
TestFlags:
    sta Temporary1
    and #$1F
    bit Temporary1
    rts
.endproc

;; A = the channel's inactive buffer byte (the one with bit 7 set); Z set if it has none ($FF).
;; Also: GETINA (D1541)
.proc GetInactiveBuffer
    ldx Channel
    lda ChannelBuffer,x
    bmi Test
    lda ChannelSecondBuffer,x

;; Compares with $FF.
;; Also: GI10 (D1541)
Test:
    cmp #$FF
    rts
.endproc

;; Buffer A, with bit 7 set, into the slot of `buf0`/`buf1` the active buffer is not in.
;; Also: PUTINA (D1541)
.proc SetInactiveBuffer
    ldx Channel
    ora #$80
    ldy ChannelBuffer,x
    bpl SecondSlot
    sta ChannelBuffer,x
    rts

;; `buf0` is active: into `buf1`.
;; Also: PI1 (D1541)
SecondSlot:
    sta ChannelSecondBuffer,x
    rts
.endproc
.endscope
.scope Relative continued

;; Moves the channel to its next record: the record number up, the buffers on if the record starts in the next block,
;; its first byte into `data`, `nr` past it, and its last byte found (<FindRecordEnd>); at the file's end sets the
;; last-record flag and gives a carriage return.
;; Entry:
;;   CheckEnd = With A the next record's place and carry set if it is in the next block
;; Also: NXTREC (D1541)
.proc NextRecord
    lda #RELATIVE_OVERFLOW
    jsr Files::ClearFlag
    lda #RELATIVE_LAST_RECORD
    jsr Files::TestFlag
    bne AtEnd
    ldx Channel
    inc ChannelRecord,x
    bne CheckNext
    inc ChannelRecordHigh,x

;; `nr` 0 means there is no next record (the listing's comment says the opposite; Q10). Past `nr` in this buffer:
;; <NextBuffer>.
;; Also: NXTR15 (D1541)
CheckNext:
    ldx Channel
    lda ChannelNextRecord,x
    beq SetLastRecord
    jsr Files::GetPointer
    ldx Channel
    cmp ChannelNextRecord,x
    bcc ReadFirstByte
    jsr NextBuffer

;; The pointer to `nr`, the record's first byte into `data`, the overflow flag cleared, the next `nr` reckoned
;; (<AddRecordSize>).
;; Also: NXTR20 (D1541)
ReadFirstByte:
    ldx Channel
    lda ChannelNextRecord,x
    jsr Files::SetPointer
    lda (BufferPositions,x)
    sta DataByte
    lda #RELATIVE_OVERFLOW
    jsr Files::ClearFlag
    jsr AddRecordSize

;; With A the next record's place and carry set if it is in the next block: in the last block (track link 0) that is the
;; end; otherwise `nr` = A. <SeekRecord> enters here.
;; Also: NXOUT (D1541)
CheckEnd:
    pha
    bcc NotLast
    lda #$00
    jsr Files::PeekByte
    bne NotLast
    pla
    cmp #$02
    beq EndsAtBlock

;; Sets the last-record flag...
;; Also: NXTR45 (D1541)
SetLastRecord:
    lda #RELATIVE_LAST_RECORD
    jsr Files::SetFlag

;; ...the channel's last character at its pointer, and `data` a carriage return.
;; Also: NXTR40 (D1541)
AtEnd:
    jsr Files::BufferIndexes
    lda BufferPositions,x
    sta ChannelLastByte,y
    lda #CARRIAGE_RETURN
    sta DataByte
    rts

;; The last record ends at the last block's end: its end found, then `nr` = 0.
;; Also: NXTR50 (D1541)
EndsAtBlock:
    jsr SetNext
    ldx Channel
    lda #$00
    sta ChannelNextRecord,x
    rts

;; Not the end: A back...
;; Also: NXTR30 (D1541)
NotLast:
    pla

;; ...into `nr`, and on to <FindRecordEnd>. Called with `jsr` inside the routine, and fallen into.
;; Also: NXTR35 (D1541)
SetNext:
    ldx Channel
    sta ChannelNextRecord,x
    jmp FindRecordEnd
.endproc

;; On to the next block: writes the active buffer if dirty, swaps to the other buffer (which the read-ahead filled),
;; reads the block there now if its last job was a write, and starts reading the block after into the buffer it left
;; (that read-ahead only on the clean path: after a write it returns once the needed block is in).
;; Also: NRBUF (D1541)
.proc NextBuffer
    jsr Files::SetDriveFromBuffer
    jsr Files::ReadLink
    jsr Files::GetActiveBufferState
    bvc Clean
    jsr Files::WriteBuffer
    jsr Files::SwapBuffers
    lda #$02
    jsr Files::SetPointer
    jsr Files::TestWriteJob
    bne Done
    jsr Files::ReadBlock
    jmp Jobs::Wait

;; Clean: swaps without writing.
;; Also: NRBU50 (D1541)
Clean:
    jsr Files::SwapBuffers
    jsr Files::TestWriteJob
    bne ReadAhead
    jsr Files::ReadBlock
    jsr Jobs::Wait

;; Starts reading the following block into the inactive buffer, unless this is the last.
;; Also: NRBU70 (D1541)
ReadAhead:
    jsr Files::ReadLink
    lda Track
    beq Done
    jsr Files::SwapBuffers
    jsr Files::ReadBlock
    jsr Files::SwapBuffers

;; Done.
;; Also: NRBU20 (D1541)
Done:
    rts
.endproc

;; `data` into the active buffer at its pointer, marking it dirty; at the record's end (`nr`) sets the overflow flag,
;; and at the block's end goes on to <NextBuffer>.
;; Also: RELPUT (D1541)
.proc PutByte
    jsr MarkDirty
    jsr Files::GetActiveBuffer
    asl
    tax
    lda DataByte
    sta (BufferPositions,x)
    ldy BufferPositions,x
    iny
    bne CompareEnd
    ldy Channel
    lda a:ChannelNextRecord,y
    beq Overflow
    ldy #$02

;; The next place (past the link if the block ended): is it `nr`?
;; Also: RELP05 (D1541)
CompareEnd:
    tya
    ldy Channel
    cmp a:ChannelNextRecord,y
    bne Advance

;; It is: the overflow flag.
;; Also: RELP07 (D1541)
Overflow:
    lda #RELATIVE_OVERFLOW
    jmp Files::SetFlag

;; The pointer on; <NextBuffer> if it wraps.
;; Also: RELP10 (D1541)
Advance:
    inc BufferPositions,x
    bne Done
    jsr NextBuffer

;; Done.
;; Also: RELP20 (D1541)
Done:
    rts
.endproc

;; A byte sent to a relative channel: puts it in the record, adding blocks first past the file's end; at EOI fills the
;; record's rest with zeros, moves to the next record, and reports 51 RECORD OVERFLOW if it was too long. A byte past
;; the record's end without EOI is dropped.
;; Also: WRTREL (D1541)
.proc WriteByte
    lda #RELATIVE_LAST_RECORD+RELATIVE_OVERFLOW
    jsr Files::TestFlag
    bne FlagSet

;; Puts `data` (<PutByte>); jumped to after <Extend>.
;; Also: WR10 (D1541)
Put:
    lda DataByte
    jsr PutByte
    lda MoreBytes
    beq EndRecord
    rts

;; EOI after an overflow: the overflow error into `PendingError`.
;; Also: WR30 (D1541)
CheckOverflow:
    lda #RELATIVE_OVERFLOW
    jsr Files::TestFlag
    beq EndRecord
    lda #ERROR_RECORD_OVERFLOW
    sta ErrorFlash

;; Fills the record's rest (<FillRecord>), moves to the next (<ReadByte::LoadNextRecord>), and reports `PendingError` or
;; OK.
;; Also: WR40 (D1541)
EndRecord:
    jsr FillRecord
    jsr ReadByte::LoadNextRecord
    lda ErrorFlash
    beq Ok
    jmp Commands::Fail

;; No error: `Errors::SetOk`.
;; Also: WR45 (D1541)
Ok:
    jmp Errors::SetOk

;; The last-record or overflow flag is set.
;; Also: WR50 (D1541)
FlagSet:
    and #RELATIVE_LAST_RECORD
    bne Extend
    lda MoreBytes
    beq CheckOverflow
    rts

;; Past the last record: <AddBlocks>, keeping `data`, then the flag off and <Put>.
;; Also: WR60 (D1541)
Extend:
    lda DataByte
    pha
    jsr AddBlocks
    pla
    sta DataByte
    lda #RELATIVE_LAST_RECORD
    jsr Files::ClearFlag
    jmp Put
.endproc

;; Puts zeros until the record overflows: its rest cleared.
;; Also: CLREC (D1541)
.proc FillRecord
    lda #RELATIVE_OVERFLOW
    jsr Files::TestFlag
    bne Done
    lda #$00
    sta DataByte
    jsr PutByte
    jmp FillRecord

;; Done.
;; Also: CLR10 (D1541)
Done:
    rts
.endproc

;; Sets the channel's `dyfile` flag (the file changed) and the active buffer's dirty bit (Q2).
;; Also: SDIRTY (D1541)
.proc MarkDirty
    lda #RELATIVE_DIRTY
    jsr Files::SetFlag
    jsr Files::GetActiveBufferState
    ora #$40
    ldx ActiveBufferSlot
    sta ChannelBuffer,x
    rts
.endproc
.endscope
.scope Files continued

;; Clears the active buffer's dirty bit (Q2).
;; Also: CDIRTY (D1541)
.proc MarkClean
    jsr GetActiveBufferState
    and #$BF
    ldx ActiveBufferSlot
    sta ChannelBuffer,x
    rts
.endproc
.endscope
.scope Relative continued

;; Readies a relative channel's next byte in `chndat`, with EOI on the record's last; at a record's end, the next
;; record's first; past the file's end, 50 RECORD NOT PRESENT.
;; Entry:
;;   ReadAtPointer = The byte at the active buffer's pointer, readied
;;   LoadNextRecord = <NextRecord>, then its first byte readied
;;   NoRecord = Past the end
;; Also: RDREL (D1541)
.proc ReadByte
    lda #RELATIVE_LAST_RECORD
    jsr Files::TestFlag
    bne NoRecord
    jsr Files::BufferIndexes
    lda BufferPositions,x
    cmp ChannelLastByte,y
    beq LoadNextRecord
    inc BufferPositions,x
    bne Load
    jsr NextBuffer

;; The byte at the active buffer's pointer, readied. <SeekRecord> enters here.
;; Also: RD15 (D1541)
ReadAtPointer:
    jsr Files::BufferIndexes

;; Loads the byte...
;; Also: RD20 (D1541)
Load:
    lda (BufferPositions,x)

;; ...into `chndat`, ready, or with EOI if it is the record's last (`lstchr`).
;; Also: RD25 (D1541)
Store:
    sta ChannelByte,y
    lda #CHANNEL_RANDOM
    sta a:ChannelStatus,y
    lda BufferPositions,x
    cmp ChannelLastByte,y
    beq LastByte
    rts

;; The record's last: EOI.
;; Also: RD30 (D1541)
LastByte:
    lda #CHANNEL_RANDOM_LAST
    sta a:ChannelStatus,y
    rts

;; <NextRecord>, then its first byte readied.
;; Also: RD40 (D1541)
LoadNextRecord:
    jsr NextRecord
    jsr Files::BufferIndexes
    lda DataByte
    jmp Store

;; Past the end: a carriage return with EOI, and 50 RECORD NOT PRESENT.
;; Also: RD05 (D1541)
NoRecord:
    ldx Channel
    lda #CARRIAGE_RETURN
    sta ChannelByte,x
    lda #CHANNEL_RANDOM_LAST
    sta ChannelStatus,x
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Commands::Fail
.endproc

;; Sets the channel's last character (`lstchr`) to the record's last nonzero byte, looking in the next buffer first if
;; the record runs into it; an all-zero record ends at its first byte.
;; Also: SETLST (D1541)
.proc FindRecordEnd
    ldx Channel
    lda ChannelNextRecord,x
    sta Work1
    dec Work1
    cmp #$02
    bne GetSize
    lda #$FF
    sta Work1

;; `r2` = `rs`, the bytes to look at (`r1`, the record's last place, `nr` - 1 or $FF if it ends the block, is set in
;; SETLST before it).
;; Also: SETL01 (D1541)
GetSize:
    lda ChannelRecordSize,x
    sta Work2
    jsr Files::GetPointer
    ldx Channel
    cmp Work1
    bcc SearchThis
    beq SearchThis
    jsr Files::SwapBuffers
    jsr FindLastNonzero
    bcc NotInNext
    ldx Channel
    sta ChannelLastByte,x
    jmp Files::SwapBuffers

;; Nothing in the next buffer: back, from the block's end.
;; Also: SETL05 (D1541)
NotInNext:
    jsr Files::SwapBuffers
    lda #$FF
    sta Work1

;; Looks in the active buffer.
;; Also: SETL10 (D1541)
SearchThis:
    jsr FindLastNonzero
    bcs Store
    jsr Files::GetPointer

;; Into `lstchr`.
;; Also: SETL40 (D1541)
Store:
    ldx Channel
    sta ChannelLastByte,x
    rts
.endproc

;; Looks back from byte `r1` of the active buffer, down to byte 2 and for at most `r2` bytes, for one not zero: carry
;; set and A its place if found.
;; Also: FNDLST (D1541)
.proc FindLastNonzero
    jsr PointAtBuffer
    ldy Work1

;; Each byte.
;; Also: FNDL10 (D1541)
Loop:
    lda (BufferPointer),y
    bne Found
    dey
    cpy #$02
    bcc NotFound
    dec Work2
    bne Loop

;; Carry clear.
;; Also: FNDL30 (D1541)
NotFound:
    dec Work2
    clc
    rts

;; Carry set, A = its place.
;; Also: FNDL20 (D1541)
Found:
    tya
    sec
    rts
.endproc

;; Puts the file's last side sector in its buffer, found from the link table, with `ssnum` its number and `ssind` and
;; the pointer at its last entry: the last data block.
;; Also: SSEND (D1541)
.proc SeekEnd
    jsr GetSideSectorNumber
    sta SideSectorNumber
    lda #$04
    sta BufferPointer
    ldy #SIDE_SECTOR_POINTERS-6
    bne TestLink

;; Back a link...
;; Also: SE10 (D1541)
PreviousLink:
    dey
    dey
    bmi SideSectorError

;; ...until one is used: that side sector is the last; read if not the one in the buffer.
;; Also: SE20 (D1541)
TestLink:
    lda (BufferPointer),y
    beq PreviousLink
    tya
    lsr
    cmp SideSectorNumber
    beq LastSideSector
    sta SideSectorNumber
    ldx Channel
    lda ChannelSideSector,x
    jsr ReadLinkedSideSector

;; Its own link must be 0 (else <SideSectorError>); its byte 1, the last used, less 1, is the last entry.
;; Also: SE30 (D1541)
LastSideSector:
    ldy #$00
    sty BufferPointer
    lda (BufferPointer),y
    bne SideSectorError
    iny
    lda (BufferPointer),y
    tay
    dey
    sty SideSectorIndex
    tya
    jmp SetSideSectorPointer
.endproc

;; Error 67, ILLEGAL TRACK OR SECTOR: the side sectors do not make sense. Loads `$67` where `systs` names it (Q9, Q10).
;; Also: BREAK (D1541)
.proc SideSectorError
    lda #$67
    jsr Errors::Abort
.endproc

;; The P command (Q8): sets the channel on the secondary address in the command to the record and byte given, through
;; the side sectors; 50 RECORD NOT PRESENT past the end, 51 RECORD OVERFLOW for a byte past the record's size.
;; Also: RECORD (D1541)
.proc PositionCommand
    jsr Commands::Prepare
    lda CommandBuffer+1
    sta SecondaryAddress
    jsr Files::FindReadChannel
    bcc HaveChannel
    lda #ERROR_NO_CHANNEL
    jsr Commands::Fail

;; The channel found (else 70 NO CHANNEL); its flags cleared.
;; Also: R20 (D1541)
HaveChannel:
    lda #RELATIVE_LAST_RECORD+RELATIVE_OVERFLOW
    jsr Files::ClearFlag
    jsr Files::ChannelType
    beq IsRelative
    lda #ERROR_FILE_TYPE_MISMATCH
    jsr Commands::Fail

;; A relative file (else 64 FILE TYPE MISMATCH): the drive, record number and ready state set.
;; Also: R30 (D1541)
IsRelative:
    lda ChannelFileType,x
    and #$01
    sta DriveNumber
    lda CommandBuffer+2
    sta ChannelRecord,x
    lda CommandBuffer+3
    sta ChannelRecordHigh,x
    ldx Channel
    lda #CHANNEL_RANDOM
    sta ChannelStatus,x
    lda CommandBuffer+4
    beq SetOffset
    sec
    sbc #$01
    beq SetOffset
    cmp ChannelRecordSize,x
    bcc SetOffset
    lda #ERROR_RECORD_OVERFLOW
    sta ErrorFlash
    lda #$00

;; Sets the offset in the record: A, the command's offset less 1 (0 if it gave none or 1) when that is inside the
;; record, else 0 after 51 RECORD OVERFLOW is noted in <ErrorFlash>. Then finds the record and its side sector
;; (<Files::FindRecord>, <PositionSideSector>). The listing labelled this address twice, R35 (reached with an offset
;; inside the record) and R40 (reached with offset 0 or 1); it is one label here (Q7).
;; Also: R35 (D1541), R40 (D1541)
SetOffset:
    sta RecordOffset
    jsr FindRecord
    jsr PositionSideSector
    bvc Found
    lda #RELATIVE_LAST_RECORD
    jsr Files::SetFlag
    jmp ReadByte::NoRecord

;; In the file: <SeekRecord>.
;; Also: R50 (D1541)
Found:
    jsr SeekRecord
    lda #RELATIVE_LAST_RECORD
    jsr Files::TestFlag
    beq Done
    jmp ReadByte::NoRecord

;; `Commands::Finish`.
;; Also: R60 (D1541)
Done:
    jmp Commands::Finish
.endproc

;; With the side sector placed: the record's block into the active buffer (<LoadBlocks>), the pointer to `relptr`, `nr`
;; past the record, and its first wanted byte readied (<ReadByte::ReadAtPointer>).
;; Also: POSITN (D1541)
.proc SeekRecord
    jsr LoadBlocks
    lda BlockOffset
    jsr Files::SetPointer
    ldx Channel
    lda ChannelRecordSize,x
    sec
    sbc RecordOffset
    bcs SetNext
    jmp SideSectorError

;; The record's end: `relptr` + `rs` - `recptr`, plus 2 if it runs into the next block. (`rs` under `recptr` cannot
;; happen: <SideSectorError>.)
;; Also: P2 (D1541)
SetNext:
    clc
    adc BlockOffset
    bcc CheckEnd
    adc #$01
    sec

;; <NextRecord::CheckEnd>, then ReadAtPointer.
;; Also: P30 (D1541)
CheckEnd:
    jsr NextRecord::CheckEnd
    jmp ReadByte::ReadAtPointer
    lda #ERROR_RECORD_OVERFLOW
    jsr Commands::Fail
.endproc

;; Makes the active buffer hold the data block the side-sector pointer names, and the other buffer the block after:
;; nothing if it is there; if the wanted block is the buffer's next, a swap (`dblbuf`) and a jump to FreeInactiveBuffer,
;; which frees the old buffer and reads nothing after; else a read. The listing's "yes!" is on the branch for not there
;; (Q10).
;; Also: POSBUF (D1541)
.proc LoadBlocks
    lda BufferPointer
    sta Work3
    lda BufferPointer+1
    sta Work4
    jsr IsInBuffer
    bne NotLoaded
    rts

;; Not in the buffer: writes it if dirty (Flush), takes its link; if that is 0 (last block) goes to <ReadWanted>, else
;; is the block wanted that link? If so, swaps and frees the old buffer (`Files::FreeInactiveBuffer`), reading nothing.
;; Also: P10 (D1541)
NotLoaded:
    jsr Files::Flush
    jsr GetLink
    lda Track
    beq ReadWanted
    jsr IsSameBlock
    bne NotNext
    jsr Files::SwapBuffers
    jmp Files::FreeInactiveBuffer

;; Not the next: frees the inactive buffer (`Files::FreeInactiveBuffer`)...
;; Also: P75 (D1541)
NotNext:
    jsr Files::FreeInactiveBuffer

;; ...and reads the block wanted, and the one after into the other buffer (`Files::StartDoubleRead`).
;; Also: P80 (D1541)
ReadWanted:
    ldy #$00
    lda (Work3),y
    sta Track
    iny
    lda (Work3),y
    sta Sector
    jmp Files::StartDoubleRead
.endproc

;; Z set if the active buffer holds the block named at (`r3`): its header's block (GetBufferBlock), then <IsSameBlock>.
;; Also: BHERE (D1541)
.proc IsInBuffer
    jsr Files::GetBufferBlock
    ; Falls into <IsSameBlock>.
.endproc

;; Z set if `track` and `sector` are the block named at (`r3`).
;; Also: BHERE2 (D1541)
.proc IsSameBlock
    ldy #$00
    lda (Work3),y
    cmp Track
    beq TestSector
    rts

;; The track matches: the sector.
;; Also: BH10 (D1541)
TestSector:
    iny
    lda (Work3),y
    cmp Sector
    rts
.endproc

;; Makes the active buffer a block of empty records: zeros after the link, with $FF at each record's start, from `nr`
;; (where the last record ended in the block before); `nr` left at the last record's place, or 0 if it ends the block.
;; Also: NULBUF (D1541)
.proc FillEmptyRecords
    jsr PointAtBuffer
    ldy #$02
    lda #$00

;; Each byte from 2 to the block's end.
;; Also: NB10 (D1541)
ClearByte:
    sta (BufferPointer),y
    iny
    bne ClearByte
    jsr AddRecordSize

;; Each record in the block: $FF at its start.
;; Also: NB20 (D1541)
MarkRecord:
    sta ChannelNextRecord,x
    tay
    lda #$FF
    sta (BufferPointer),y
    jsr AddRecordSize
    bcc MarkRecord
    bne Done
    lda #$00
    sta ChannelNextRecord,x

;; Done.
;; Also: NB30 (D1541)
Done:
    rts
.endproc

;; A = `nr` + `rs`, the next record's place; carry set if that is in the next block, where it is moved past the link
;; (exactly the block's end gives 2 with Z set). `nr` 0 gives 2.
;; Also: ADDNR (D1541)
.proc AddRecordSize
    ldx Channel
    lda ChannelNextRecord,x
    sec
    beq NextBlock
    clc
    adc ChannelRecordSize,x
    bcc Done
    bne NextBlock
    lda #$02
    bit BitZero
    rts

;; In the next block: 2 more, for its link.
;; Also: AN05 (D1541)
NextBlock:
    adc #$01
    sec

;; Done.
;; Also: AN10 (D1541)
Done:
    rts
.endproc

;; Extends the file to the record wanted: counts the blocks and side sectors needed against the free blocks (52 FILE TOO
;; LARGE), then adds blocks of empty records, with new side sectors as they fill, and the BAM written; ends at the
;; record (<SeekRecord>).
;; Entry:
;;   CheckRoom = With the end found
;; Also: ADDREL (D1541)
.proc AddBlocks
    jsr Files::SetDriveFromBuffer
    jsr SeekEnd
    jsr LoadBlocks
    jsr Files::AddSecondBuffer
    lda SideSectorIndex
    sta Work1
    lda SideSectorNumber
    sta Work0
    lda #$00
    sta Work2
    lda #$00
    sta RecordOffset
    jsr FindRecord

;; With the end found: counts the free blocks (`Bam::CopyFreeBlocks`) and what is needed. The relative-file copy in
;; `rename` enters here.
;; Also: ADDR1 (D1541)
CheckRoom:
    jsr Bam::CopyFreeBlocks
    ldy Channel
    ldx ChannelRecordSize,y
    dex
    txa
    clc
    adc BlockOffset
    bcc SetPointer
    inc SideSectorIndex
    inc SideSectorIndex
    bne SetPointer
    inc SideSectorNumber
    lda #SIDE_SECTOR_POINTERS
    sta SideSectorIndex

;; The side-sector pointer past the file's last entry.
;; Also: AR10 (D1541)
SetPointer:
    lda Work1
    clc
    adc #$02
    jsr SetSideSectorPointer
    lda SideSectorNumber
    cmp #SIDE_SECTOR_COUNT
    bcc CountNeeded

;; 52 FILE TOO LARGE: more than 6 side sectors, or not enough free blocks.
;; Also: AR20 (D1541)
TooBig:
    lda #ERROR_FILE_TOO_LARGE
    jsr Commands::Fail

;; The entries needed...
;; Also: AR25 (D1541)
CountNeeded:
    lda SideSectorIndex
    sec
    sbc Work1
    bcs CountSideSectors
    sbc #SIDE_SECTOR_POINTERS-1
    clc

;; ...and the side sectors, into <CountBlocks>; `r2` set if it is one block.
;; Also: AR30 (D1541)
CountSideSectors:
    sta Temporary3
    lda SideSectorNumber
    sbc Work0
    sta Temporary4
    ldx #$00
    stx Temporary1
    stx Temporary2
    tax
    jsr CountBlocks::Start
    lda Temporary2
    bne CompareFree
    ldx Temporary1
    dex
    bne CompareFree
    inc Work2

;; Against the free blocks (`nbtemp`).
;; Also: AR35 (D1541)
CompareFree:
    cmp BlockTotal+1
    bcc LinkNext
    bne TooBig
    lda BlockTotal
    cmp Temporary1
    bcc TooBig

;; Room: `nr` from the last block's sector link, and a new block linked to it.
;; Also: AR40 (D1541)
LinkNext:
    lda #$01
    jsr Files::PeekByte
    clc
    adc #$01
    ldx Channel
    sta ChannelNextRecord,x
    jsr Bam::AllocateNext
    jsr SetLink
    lda Work2
    bne LastBlock
    jsr Files::WriteBuffer

;; Each new block but the last: in the other buffer, linked to one more new block, filled with empty records.
;; Also: AR45 (D1541)
NextBlock:
    jsr Files::SwapBuffers
    jsr Jobs::SetHeader
    jsr Bam::AllocateNext
    jsr SetLink
    jsr FillEmptyRecords
    jmp WriteAndRecord

;; The last new block: empty records, link ended (<EndLink>).
;; Also: AR50 (D1541)
LastBlock:
    jsr Files::SwapBuffers
    jsr Jobs::SetHeader
    jsr FillEmptyRecords
    jsr EndLink

;; Writes the block and puts its track and sector in the side sector, starting a new side sector (<NewSideSector>) if
;; that one is full.
;; Also: AR55 (D1541)
WriteAndRecord:
    jsr Files::WriteBuffer
    jsr GetLink
    lda Track
    pha
    lda Sector
    pha
    jsr Files::GetBufferBlock
    lda Sector
    pha
    lda Track
    pha
    jsr GetSideSectorPointer
    tax
    bne PutEntry
    jsr NewSideSector
    lda #SIDE_SECTOR_POINTERS
    jsr SetSideSectorPointer
    inc Work0

;; The entry put (`Relative::PutSideSectorByte`); on while blocks remain.
;; Also: AR60 (D1541)
PutEntry:
    pla
    jsr PutSideSectorByte
    pla
    jsr PutSideSectorByte
    pla
    sta Sector
    pla
    sta Track
    beq Finish
    lda Work0
    cmp SideSectorNumber
    bne NextBlock
    jsr GetSideSectorPointer
    cmp SideSectorIndex
    bcc NextBlock
    beq LastBlock

;; Ends the side sector (link 0, its last byte), writes it and the BAM, and finds the record again.
;; Also: AR65 (D1541)
Finish:
    jsr GetSideSectorPointer
    pha
    lda #$00
    jsr PointAtSideSector
    lda #$00
    tay
    sta (BufferPointer),y
    iny
    pla
    sec
    sbc #$01
    sta (BufferPointer),y
    jsr WriteSideSector
    jsr Jobs::Wait
    jsr Bam::WriteForChannel
    jsr FindRecord
    jsr Files::SwapBuffers
    jsr PositionSideSector
    bvs NoRecord
    jmp SeekRecord

;; Still not in the file: 50 RECORD NOT PRESENT.
;; Also: AR70 (D1541)
NoRecord:
    lda #RELATIVE_LAST_RECORD
    jsr Files::SetFlag
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Commands::Fail
.endproc

;; Starts a side sector in a new block: copies the link table into it, adds itself to the table, writes it, makes it the
;; side-sector buffer, links the old one to it, and adds it to every earlier side sector's table.
;; Also: NEWSS (D1541)
.proc NewSideSector
    jsr Bam::AllocateNext
    jsr Files::SwapBuffers
    jsr Files::Flush
    jsr Files::GetActiveBuffer
    pha
    jsr ClearBuffer
    ldx Channel
    lda ChannelSideSector,x
    tay
    pla
    tax
    lda #SIDE_SECTOR_POINTERS
    jsr CopyBuffer
    lda #$00
    jsr PointAtSideSector
    ldy #$02
    lda (BufferPointer),y
    pha
    lda #$00
    jsr Files::SetPointer
    pla
    clc
    adc #$01
    sta (BufferPointer),y
    asl
    adc #$04
    sta Work3
    tay
    sec
    sbc #$02
    sta Work4
    lda Track
    sta Work1
    sta (BufferPointer),y
    iny
    lda Sector
    sta Work2
    sta (BufferPointer),y
    ldy #$00
    tya
    sta (BufferPointer),y
    iny
    lda #SIDE_SECTOR_POINTERS+1
    sta (BufferPointer),y
    lda #SIDE_SECTOR_POINTERS
    jsr Files::SetPointer
    jsr Files::WriteBlock
    jsr Jobs::Wait
    ldx Channel
    lda ChannelSideSector,x
    pha
    jsr Files::GetActiveBufferState
    ldx Channel
    sta ChannelSideSector,x
    pla
    ldx ActiveBufferSlot
    sta ChannelBuffer,x
    lda #$00
    jsr Files::SetPointer
    ldy #$00
    lda Track
    sta (BufferPointer),y
    iny
    lda Sector
    sta (BufferPointer),y
    jmp AddToTable

;; The side sector before, read into the active buffer...
;; Also: NS40 (D1541)
ReadEarlier:
    jsr Files::GetActiveBuffer
    ldx Channel
    jsr ReadLinkedSideSector
    lda #$00
    jsr Files::SetPointer

;; ...the new side sector's track and sector put in its table, and written; on while earlier ones remain.
;; Also: NS50 (D1541)
AddToTable:
    dec Work4
    dec Work4
    ldy Work3
    lda Work1
    sta (BufferPointer),y
    iny
    lda Work2
    sta (BufferPointer),y
    jsr Files::WriteBuffer
    jsr Jobs::Wait
    ldy Work4
    cpy #$03
    bcs ReadEarlier
    jmp Files::SwapBuffers
.endproc
.endscope
