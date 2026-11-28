; retrocore: style=strict
; COMMODORE 1541 DOS: THE SIDE SECTORS AND THE RELATIVE FILES ($DDF1-$E4FB)
; The buffer flush, the first piece of Files in this file.
.scope Files continued

;; Writes the active buffer back to its block if it is dirty, and waits for the write to finish. A clean buffer is left
;; alone.
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
; The first piece of Relative: the active buffer's link and where it starts.
.scope Relative continued

;; Puts <Track> and <Sector> in the active buffer as its link, its first two bytes, and marks the buffer dirty
;; (<MarkDirty>, Q2).
;; In: Track, Sector = the block the link names
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

;; Reads the active buffer's link into <Track> and <Sector>, leaving the buffer's pointer alone.
;; Out: Track, Sector = the link, BufferPointer = the buffer's start, Y = 1
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

;; Makes the active buffer the file's last block: track link 0, and sector link <ChannelNextRecord> less 1, the place of
;; its last byte in use.
;; Out: BufferPointer = the buffer's start, Y = 1
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

;; Points <BufferPointer> at the start of the active buffer.
;; Out: BufferPointer = the buffer's start, A = 0, Y = 0, X = twice the buffer's number
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
; More of Files: the block read and write starters, and the buffer's header.
.scope Files continued

;; Finds the read channel for <SecondaryAddress> (<Files::FindReadChannel>), without looking at whether it found one,
;; and falls into <GetBufferBlock>.
;; In: SecondaryAddress = the channel's secondary address
;; Also: CURBLK (D1541)
.proc GetChannelBlock
    jsr FindReadChannel
    .assert * = GetBufferBlock, "GetChannelBlock must fall into GetBufferBlock."
    ; Falls into <GetBufferBlock>.
.endproc

;; Reads the block the active buffer holds, from its job header, into <Track> and <Sector>.
;; Out: Track, Sector = the block, JobNumber = the buffer's number
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

;; Starts writing the active buffer to the block at <Track> and <Sector>, through <StartBlockJob>; the caller waits
;; (<Jobs::Wait>).
;; In: Track, Sector = the block
;; Also: WRTAB (D1541)
.proc WriteBlock
    lda #JOB_WRITE
    sta JobCommand
    bne StartBlockJob
.endproc

;; Starts reading the block at <Track> and <Sector> into the active buffer, through <StartBlockJob>; the caller waits
;; (<Jobs::Wait>).
;; In: Track, Sector = the block
;; Also: RDAB (D1541)
.proc ReadBlock
    lda #JOB_READ
    sta JobCommand
    bne StartBlockJob
.endproc

;; Starts writing the active buffer out to the block its header names, whether or not it is dirty (<Flush> tests that
;; first), and clears its dirty bit (<StartBlockJob::ClearDirty>); the caller waits (<Jobs::Wait>).
;; Also: WRTOUT (D1541)
.proc WriteBuffer
    lda #JOB_WRITE
    sta JobCommand
    bne StartBlockJob::ClearDirty

    ; Nothing reaches these three instructions: the listing's RDIN, which would read the active buffer from its header
    ; (Q4).
    lda #JOB_READ
    sta JobCommand
    bne StartBlockJob::ClearDirty
.endproc
.endscope
; More of Relative: the side-sector buffer's read and write starters.
.scope Relative continued

;; Starts writing the side-sector buffer to the block its header names; the caller waits (<Jobs::Wait>). It branches to
;; <ReadSideSector::SetCommand>, which takes the command from A.
;; Also: WRTSS (D1541)
.proc WriteSideSector
    lda #JOB_WRITE
    sta JobCommand
    bne ReadSideSector::SetCommand
.endproc

;; Starts reading the side-sector buffer from the block its header names; the caller waits (<Jobs::Wait>). It falls into
;; SetCommand, and from there starts the job through <Files::StartBlockJob::Start> (Q3).
;; Entry:
;;   SetCommand = the job command in A, the channel's side-sector buffer taken into X
;; Also: RDSS (D1541)
.proc ReadSideSector
    lda #JOB_READ

;; Puts the command in A in <JobCommand>, takes the channel's side-sector buffer into X and, if the channel has one,
;; starts the job (<Files::StartBlockJob::Start>). <WriteSideSector> branches here, and <ReadSideSector> falls into it.
;; A channel with none has $FF, which is negative, so the branch is not taken and the routine falls on into
;; <Files::StartBlockJob>, which would use the active buffer's header instead.
;; In: A = <JOB_READ> or <JOB_WRITE>
;; Also: RDS5 (D1541)
SetCommand:
    sta JobCommand
    ldx Channel
    lda ChannelSideSector,x
    tax
    bpl Files::StartBlockJob::Start
    .assert * = Files::StartBlockJob, "ReadSideSector must fall into StartBlockJob when it has no buffer."
    ; Falls into <Files::StartBlockJob> when the channel has no side-sector buffer.
.endproc
.endscope
; More of Files: the tail the block starters share, and reading a buffer's link.
.scope Files continued

;; The tail of the block-job starters (Q3): sets the active buffer's header from <Track> and <Sector>, and notes the
;; drive in its <LastJobs> entry...
;; Entry:
;;   ClearDirty = ...clears the buffer's dirty bit (<MarkClean>), X = the buffer...
;;   Start = ...and starts the job in <JobCommand> on buffer X, with its last job's drive (<Jobs::StartOnLastDrive>)
;; In: JobCommand = the job, <Track>, <Sector> = the block, DriveNumber = the drive
;; Also: SJ10 (D1541)
.proc StartBlockJob
    jsr Jobs::SetHeader
    jsr GetActiveBuffer
    tax
    lda DriveNumber
    sta LastJobs,x

;; ...clears its dirty bit (<MarkClean>) and takes the buffer's number into X...
;; Also: SJ20 (D1541)
ClearDirty:
    jsr MarkClean
    jsr GetActiveBuffer
    tax

;; ...and starts the job in <JobCommand> on buffer X, with the drive of its last job (<Jobs::StartOnLastDrive>).
;; Also: SJ30 (D1541)
Start:
    jmp Jobs::StartOnLastDrive
.endproc

;; Reads the active buffer's link into <Track> and <Sector> through its pointer, which is left at 2, past the link.
;; Out: Track, Sector = the link
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
; More of Relative: buffer copying and clearing, and the side sectors' pointers, positioning and block counts.
.scope Relative continued

;; Copies A bytes (counting down) from the start of buffer Y to the start of buffer X. A count of 1 to 129 copies that
;; many bytes; 0 and 130 to 255 copy one, as the loop ends with `bpl` (Q11). Its one caller copies 16.
;; In: A = the count, Y = the source buffer's number, X = the destination's
;; Uses: A, Y, Temporary, Temporary1, Temporary2, Temporary3
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

;; Fills buffer A with zeros.
;; In: A = the buffer's number
;; Out: A = 0, Y = 0
;; Keeps: X
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

;; Points <BufferPointer> at the start of the channel's side-sector buffer and reads the side sector's own number from
;; it (its byte 2).
;; Out: A = the number of the side sector in the buffer, BufferPointer = the buffer's start, X = the buffer, Y = 2
;; Also: SSSET (D1541)
.proc GetSideSectorNumber
    lda #$00
    jsr PointAtSideSector
    ldy #$02
    lda (BufferPointer),y
    rts
.endproc

;; Points <BufferPointer> at byte A of the channel's side-sector buffer.
;; In: A = the offset
;; Out: BufferPointer = the buffer's start plus A, X = the buffer's number
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

;; Points <BufferPointer>, and the side-sector buffer's own pointer (<BufferPositions>), at byte A of the buffer.
;; In: A = the offset
;; Out: BufferPointer, BufferPositions = the buffer's start plus A, A = the offset, X = twice the buffer's number
;; Keeps: Y
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

;; Puts the side sector <SideSectorNumber> in its buffer, reading it if it exists and is not there, and points at entry
;; <SideSectorIndex>. Past the file's end it points at the file's last entry instead (<SeekEnd>).
;; In: SideSectorNumber, SideSectorIndex = the side sector and the entry wanted
;; Out: overflow = clear when the entry exists and is pointed at, set when it is past the file's end
;; Errors: 67 ILLEGAL TRACK OR SECTOR, when the side sectors' links do not make sense (<SideSectorError>)
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

;; Past the end: points at the last entry (<SeekEnd>), V set.
;; Also: SSP10 (D1541)
OutOfRange:
    jsr SeekEnd
    bit BitOverflow
    rts

;; In the file: the pointer at <SideSectorIndex>, V clear.
;; Also: SSP20 (D1541)
InRange:
    lda SideSectorIndex
    jsr SetSideSectorPointer
    bit BitNeither
    rts
.endproc

;; Reads a side sector into buffer A and waits. Its track and sector are at (<BufferPointer>),Y, and it is on the drive
;; of the channel in X.
;; In: A = the buffer's number, X = the channel, <BufferPointer>, Y = where the track and sector are
;; Out: JobNumber = the buffer
;; Also: IBRD (D1541)
.proc ReadLinkedSideSector
    sta JobNumber
    lda #JOB_READ
    bne StartJob

    ; Nothing reaches these three instructions: the listing's IBWT, which would write a side sector (Q4).
    sta JobNumber
    lda #JOB_WRITE

;; The command, with the drive from the channel's file type, into <JobCommand>, and the track and sector into the
;; buffer's header; then <Jobs::Run::Repeat> starts the job and waits. Only <ReadLinkedSideSector>'s first path reaches
;; it: the write path before it is dead code (Q4).
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

;; Gets the side-sector buffer's pointer, with <BufferPointer> there (<Files::GetPointer::OfBuffer>).
;; Out: A = the pointer's low byte, <BufferPointer>
;; Also: GSSPNT (D1541)
.proc GetSideSectorPointer
    ldx Channel
    lda ChannelSideSector,x
    jmp Files::GetPointer::OfBuffer
.endproc

;; The body of the loop (Q5): adds 120 to the count for each whole side sector. Callers enter after it, at Start.
;; Entry:
;;   Start = adds to the count in <Temporary1> and <Temporary2> 120 for each of X side sectors, half of <Temporary3>
;;     (the entries) and <Temporary4> (the side sectors' own blocks): a file's block count. Falls into <AddToCount>.
;; In: X = the number of side sectors, Temporary1/Temporary2 = the count so far, Temporary3 = the entries,
;;   Temporary4 = the side sectors' blocks
;; Out: Temporary1/Temporary2 = the count
;; Also: SCAL1 (D1541)
.proc CountBlocks
    lda #POINTERS_PER_SIDE_SECTOR
    jsr AddToCount

;; Where callers enter: counts X down, adding 120 for each, then the entries and the side sectors' blocks.
;; Also: SSCALC (D1541)
Start:
    dex
    bpl CountBlocks
    lda Temporary3
    lsr
    jsr AddToCount
    lda Temporary4
    .assert * = AddToCount, "CountBlocks must fall into AddToCount."
    ; Falls into <AddToCount>.
.endproc

;; Adds A to the two-byte count in <Temporary1> and <Temporary2>.
;; In: A = the amount
;; Out: Temporary1, Temporary2 = the count plus A
;; Also: ADDT12 (D1541)
.proc AddToCount
    clc
    adc Temporary1
    sta Temporary1
    bcc Done
    inc Temporary2

;; No carry out of the low byte.
;; Also: ADDRTS (D1541)
Done:
    rts
.endproc

;; Tests whether entry <SideSectorIndex> of side sector <SideSectorNumber> is in the buffer and used.
;; In: SideSectorNumber, SideSectorIndex = the entry
;; Out: negative = set when the entry is past the file's end, overflow = set when the side sector exists but is not in
;; the buffer
;;
;; The three exits are: N and V clear, the entry is in the buffer and used; N clear, V set, that side sector exists but
;; is not in the buffer; N set, past the end, with V clear if the side sector is in the buffer (and set if it has no
;; link).
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

;; Another side sector: looks for its link in the buffer's table of side sectors (byte 4 on). Leaves <BufferPointer> at
;; $xx04 and Y = twice the number, ready for <ReadLinkedSideSector>.
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

;; The number is 6 or more, or has no link: past the end.
;; Also: ST30 (D1541)
NoSuchSideSector:
    bit BitBoth
    rts

;; It exists, but is not in the buffer.
;; Also: ST40 (D1541)
Exists:
    bit BitOverflow
    rts
.endproc
.endscope
; More of Files: the channel's active and inactive buffers.
.scope Files continued

;; Gets the active buffer of the current channel: <ChannelBuffer>'s byte if its top bit is clear, else
;; <ChannelSecondBuffer>'s, with the dirty bit taken off.
;; Out: A = the buffer's number, negative = set if it has none (Q1), X = Channel
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

;; As <GetActiveBuffer>, and notes where the buffer's byte is, for writing it back, and its dirty bit.
;; Out: A = the buffer's number, ActiveBufferSlot = the index of its byte in the channel tables, Temporary1 = the byte
;;
;; Negative and overflow come from the byte's bits 7 and 6; overflow is the dirty bit.
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

;; Gets the inactive buffer of the current channel, the byte with bit 7 set.
;; Out: A = the byte, zero = set if it has none ($FF), X = Channel
;; Also: GETINA (D1541)
.proc GetInactiveBuffer
    ldx Channel
    lda ChannelBuffer,x
    bmi Test
    lda ChannelSecondBuffer,x

;; Compares with $FF, the byte for none.
;; Also: GI10 (D1541)
Test:
    cmp #$FF
    rts
.endproc

;; Puts buffer A, with bit 7 set, in the slot the active buffer is not in.
;; In: A = the buffer's number
;; Also: PUTINA (D1541)
.proc SetInactiveBuffer
    ldx Channel
    ora #$80
    ldy ChannelBuffer,x
    bpl SecondSlot
    sta ChannelBuffer,x
    rts

;; The first slot is the active one: into the second.
;; Also: PI1 (D1541)
SecondSlot:
    sta ChannelSecondBuffer,x
    rts
.endproc
.endscope
; More of Relative: moving between records, writing and reading a relative channel, and finding a record's end.
.scope Relative continued

;; Moves the channel to its next record. The record number goes up, and if the record starts in the next block the
;; buffers move on (<NextBuffer>). The record's first byte goes into <DataByte>, <ChannelNextRecord> is put past the
;; record and its last byte is found (<FindRecordEnd>). At the file's end it sets the last-record flag and gives a
;; carriage return.
;; Entry:
;;   CheckEnd = with A the next record's place and carry set if it is in the next block (<SeekRecord> enters here)
;; In: Channel, ChannelRecord = the channel and its record
;; Out: DataByte = the record's first byte, or <CARRIAGE_RETURN> at the file's end
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

;; <ChannelNextRecord> 0 means there is no next record (the listing's comment says the opposite; Q10). Otherwise, if the
;; pointer is at or past <ChannelNextRecord>, the next record starts in the next block, and <NextBuffer> gets that block
;; first.
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

;; Puts the pointer at the record's start, its first byte into <DataByte>, and reckons the place after it
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

;; With A the next record's place and carry set if it is in the next block: in the last block (track link 0) that place
;; is the file's end; otherwise it is stored in <ChannelNextRecord>. <SeekRecord> enters here.
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

;; ...and the channel's last character at its pointer, and <DataByte> a carriage return.
;; Also: NXTR40 (D1541)
AtEnd:
    jsr Files::BufferIndexes
    lda BufferPositions,x
    sta ChannelLastByte,y
    lda #CARRIAGE_RETURN
    sta DataByte
    rts

;; The last record ends at the last block's end: its end found, and the next record's place 0.
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

;; ...into <ChannelNextRecord>, and on to <FindRecordEnd>. Called with `jsr` inside the routine, and fallen into.
;; Also: NXTR35 (D1541)
SetNext:
    ldx Channel
    sta ChannelNextRecord,x
    jmp FindRecordEnd
.endproc

;; Goes on to the next block of a relative file. It writes the active buffer if it is dirty, swaps to the other buffer,
;; which the read-ahead filled, and reads the block there now if the last job on it was a write. Then it starts reading
;; the block after into the buffer it left: that read-ahead only on the clean path, since after a write it returns once
;; the needed block is in.
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

;; Puts <DataByte> in the active buffer at its pointer and marks the buffer dirty. At the record's end
;; (<ChannelNextRecord>) it sets the overflow flag, and at the block's end it goes on to <NextBuffer>.
;; In: DataByte = the byte
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

;; The next place (past the link if the block ended): is it the record's end?
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

;; Moves the pointer on, to <NextBuffer> if it wraps.
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

;; Takes a byte sent to a relative channel. It puts the byte in the record, adding blocks first past the file's end. At
;; EOI it fills the record's rest with zeros, moves to the next record, and reports 51 RECORD OVERFLOW if it was too
;; long. A byte past the record's end without EOI is dropped.
;; In: DataByte = the byte, MoreBytes = 0 at EOI
;; Errors:
;;   51 = RECORD OVERFLOW (<ERROR_RECORD_OVERFLOW>), reported at EOI after a record that was too long
;;   52, 50, 67 and 72 = FILE TOO LARGE, RECORD NOT PRESENT, ILLEGAL SYSTEM TRACK OR SECTOR and DISK FULL, when adding
;;     blocks ends in error (<AddBlocks>)
;; Also: WRTREL (D1541)
.proc WriteByte
    lda #RELATIVE_LAST_RECORD+RELATIVE_OVERFLOW
    jsr Files::TestFlag
    bne FlagSet

;; Puts <DataByte> (<PutByte>); jumped to after <Extend>. Then at EOI the record is ended.
;; Also: WR10 (D1541)
Put:
    lda DataByte
    jsr PutByte
    lda MoreBytes
    beq EndRecord
    rts

;; EOI after an overflow: the overflow error into <PendingError>.
;; Also: WR30 (D1541)
CheckOverflow:
    lda #RELATIVE_OVERFLOW
    jsr Files::TestFlag
    beq EndRecord
    lda #ERROR_RECORD_OVERFLOW
    sta PendingError

;; Fills the record's rest (<FillRecord>), moves to the next (<ReadByte::LoadNextRecord>), and reports the error in
;; <PendingError> or OK.
;; Also: WR40 (D1541)
EndRecord:
    jsr FillRecord
    jsr ReadByte::LoadNextRecord
    lda PendingError
    beq Ok
    jmp Commands::Fail

;; No error: <Errors::SetOk>.
;; Also: WR45 (D1541)
Ok:
    jmp Errors::SetOk

;; The last-record or overflow flag is set: past the last record, extend the file; otherwise drop the byte.
;; Also: WR50 (D1541)
FlagSet:
    and #RELATIVE_LAST_RECORD
    bne Extend
    lda MoreBytes
    beq CheckOverflow
    rts

;; Past the last record: <AddBlocks>, keeping <DataByte>, then the flag off and on to <Put>.
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

;; Puts zeros in the rest of the record, until the record overflows and the record is full.
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

;; Sets the channel's flag that the file changed (<RELATIVE_DIRTY>) and the active buffer's dirty bit (Q2).
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
; More of Files: clearing the active buffer's dirty bit.
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
; More of Relative: reading a byte, the last side sector, the P command, positioning, and extending the file.
.scope Relative continued

;; Readies a relative channel's next byte in <ChannelByte>, with EOI on the record's last. At a record's end it readies
;; the next record's first byte; past the file's end it reports 50 RECORD NOT PRESENT.
;; Entry:
;;   ReadAtPointer = the byte at the active buffer's pointer, readied
;;   LoadNextRecord = <NextRecord>, then its first byte readied
;;   NoRecord = past the end
;; Errors: 50 RECORD NOT PRESENT (<ERROR_RECORD_NOT_PRESENT>), after a carriage return with EOI is readied
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

;; ...into <ChannelByte>, ready, or with EOI if it is the record's last (<ChannelLastByte>).
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

;; Past the end: a carriage return with EOI, and 50 RECORD NOT PRESENT. It does not return.
;; Also: RD05 (D1541)
NoRecord:
    ldx Channel
    lda #CARRIAGE_RETURN
    sta ChannelByte,x
    lda #CHANNEL_RANDOM_LAST
    sta ChannelStatus,x
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Commands::Fail                  ; does not return
.endproc

;; Sets the channel's last character, <ChannelLastByte>, to the place of the record's last nonzero byte, looking in the
;; next buffer first if the record runs into it; an all-zero record ends at its first byte.
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

;; The bytes to look at, the record size, in <Work2> (<Work1>, the record's last place, <ChannelNextRecord> - 1 or $FF
;; if it ends the block, is set before).
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

;; Into <ChannelLastByte>.
;; Also: SETL40 (D1541)
Store:
    ldx Channel
    sta ChannelLastByte,x
    rts
.endproc

;; Looks back from byte <Work1> of the active buffer, down to byte 2 and for at most <Work2> bytes, for one that is not
;; zero.
;; In: Work1 = the place to start, Work2 = how many bytes to look at
;; Out: carry = set if found, with A = its place
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

;; Not found: carry clear.
;; Also: FNDL30 (D1541)
NotFound:
    dec Work2
    clc
    rts

;; Found: carry set, A = its place.
;; Also: FNDL20 (D1541)
Found:
    tya
    sec
    rts
.endproc

;; Finds the file's last side sector from the link table and puts it in the buffer, with <SideSectorNumber> its number,
;; and <SideSectorIndex> and the pointer at its last entry: the last data block.
;; Errors: 67 ILLEGAL TRACK OR SECTOR (<SideSectorError>), when the side sectors' links are not in order
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

;; ...until one is used: that side sector is the last, and is read if it is not the one in the buffer.
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

;; Ends a command with error 67, ILLEGAL TRACK OR SECTOR: the side sectors do not make sense. The error is
;; <ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR> (the listing wrote $67; Q9, Q10). It does not return.
;; Errors: 67 ILLEGAL TRACK OR SECTOR
;; Also: BREAK (D1541)
.proc SideSectorError
    lda #ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR
    jsr Errors::Abort
    ; Does not return.
.endproc

;; The P command (Q8): sets the channel on the secondary address in the command to the record and byte given, through
;; the side sectors. The command buffer holds the secondary address at 1, the record number at 2 and 3 and the byte
;; offset at 4. Past the end it reports 50 RECORD NOT PRESENT, and 51 RECORD OVERFLOW for a byte past the record's size.
;; Errors: 70 NO CHANNEL, 64 FILE TYPE MISMATCH, 50 RECORD NOT PRESENT, 51 RECORD OVERFLOW, 67 ILLEGAL TRACK OR SECTOR
;; Also: RECORD (D1541)
.proc PositionCommand
    jsr Commands::Prepare
    lda CommandBuffer+1
    sta SecondaryAddress
    jsr Files::FindReadChannel
    bcc HaveChannel
    lda #ERROR_NO_CHANNEL
    jsr Commands::Fail                  ; does not return

;; The channel found (else 70 NO CHANNEL); its flags cleared. It is a relative file, or 64 FILE TYPE MISMATCH.
;; Also: R20 (D1541)
HaveChannel:
    lda #RELATIVE_LAST_RECORD+RELATIVE_OVERFLOW
    jsr Files::ClearFlag
    jsr Files::ChannelType
    beq IsRelative
    lda #ERROR_FILE_TYPE_MISMATCH
    jsr Commands::Fail                  ; does not return

;; A relative file: the drive, record number and ready state set; then the offset.
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
    sta PendingError
    lda #$00

;; Sets the offset in the record: A, the command's offset less 1 (0 if it gave none or 1) when that is inside the
;; record, else 0 after 51 RECORD OVERFLOW is noted in <PendingError>. Then finds the record and its side sector
;; (<FindRecord>, <PositionSideSector>). The listing labelled this address twice, R35 (reached with an offset inside the
;; record) and R40 (reached with offset 0 or 1); it is one label here (Q7).
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

;; Ends the command (<Commands::Finish>), which reports the error in <PendingError> if there is one.
;; Also: R60 (D1541)
Done:
    jmp Commands::Finish
.endproc

;; With the side sector placed, puts the record's block in the active buffer (<LoadBlocks>), the pointer at
;; <BlockOffset>, <ChannelNextRecord> past the record, and the record's first wanted byte readied
;; (<ReadByte::ReadAtPointer>).
;; In: BufferPointer = the side-sector entry for the record's block, <BlockOffset>, <RecordOffset>
;; Errors: 67 ILLEGAL TRACK OR SECTOR (<SideSectorError>), if the record size is under <RecordOffset>
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

;; The record's end: <BlockOffset> + the record size - <RecordOffset>, plus 2 if it runs into the next block. (A size
;; under the offset cannot happen: <SideSectorError>.)
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

    ; Nothing reaches these two instructions, which would end the command with 51 RECORD OVERFLOW (Q4).
    lda #ERROR_RECORD_OVERFLOW
    jsr Commands::Fail
.endproc

;; Makes the active buffer hold the data block the side-sector pointer names, and the other buffer the block after. If
;; the block is already there nothing is read. If the wanted block is the buffer's next, it swaps buffers and jumps to
;; <Files::FreeInactiveBuffer>, which frees the old one and reads nothing after. Else it reads. The listing's "yes!" is
;; on the branch for the block not being there (Q10).
;; In: BufferPointer = the side-sector entry (the block's track and sector)
;; Also: POSBUF (D1541)
.proc LoadBlocks
    lda BufferPointer
    sta Work3
    lda BufferPointer+1
    sta Work4
    jsr IsInBuffer
    bne NotLoaded
    rts

;; Not in the buffer: writes it if dirty (<Files::Flush>) and takes its link. If that is 0 (the last block) it goes to
;; <ReadWanted>; else, if the block wanted is that link, it swaps and frees the old buffer
;; (<Files::FreeInactiveBuffer>), reading nothing.
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

;; Not the next: frees the inactive buffer (<Files::FreeInactiveBuffer>)...
;; Also: P75 (D1541)
NotNext:
    jsr Files::FreeInactiveBuffer

;; ...and reads the block wanted, and the one after into the other buffer (<Files::StartDoubleRead>).
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

;; Tests whether the active buffer holds the block named at (<Work3>): its header's block (<Files::GetBufferBlock>),
;; then <IsSameBlock>.
;; In: Work3 = the address of the track and sector wanted
;; Out: zero = set if it does
;; Also: BHERE (D1541)
.proc IsInBuffer
    jsr Files::GetBufferBlock
    .assert * = IsSameBlock, "IsInBuffer must fall into IsSameBlock."
    ; Falls into <IsSameBlock>.
.endproc

;; Tests whether <Track> and <Sector> are the block named at (<Work3>).
;; In: Track, Sector, Work3 = the address of the track and sector to compare with
;; Out: zero = set if they are the same
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

;; Makes the active buffer a block of empty records: zeros after the link, with $FF at each record's start, from
;; <ChannelNextRecord> (where the last record ended in the block before). It leaves <ChannelNextRecord> at the last
;; record's place, or 0 if it ends the block.
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

;; Each record in the block: $FF at its start (the listing's comment says a carriage return; Q10).
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

;; Reckons the next record's place: <ChannelNextRecord> + the record size; 0 gives 2.
;; In: Channel
;; Out: A = the place, carry = set if that is in the next block, X = Channel
;;
;; In the next block the place is moved past the link; exactly the block's end gives 2 with zero set.
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

;; Extends the file to the record wanted. It counts the blocks and side sectors needed against the free blocks, then
;; adds blocks of empty records, with new side sectors as they fill, and writes the BAM, and ends at the record
;; (<SeekRecord>).
;; Entry:
;;   CheckRoom = with the end found (<Commands::CopyRelative>, the C command's code, enters here)
;; Errors: 52 FILE TOO LARGE, 50 RECORD NOT PRESENT
;; Also: ADDREL (D1541)
.proc AddBlocks
    ; Finds the file's end and loads its last block, with a second buffer to build the new blocks in.
    jsr Files::SetDriveFromBuffer
    jsr SeekEnd
    jsr LoadBlocks
    jsr Files::AddSecondBuffer

    ; Notes the end (<Work1> = its entry, <Work0> = its side sector), clears the one-block flag in <Work2>, and finds
    ; the record wanted from the start of its block.
    lda SideSectorIndex
    sta Work1
    lda SideSectorNumber
    sta Work0
    lda #$00
    sta Work2
    lda #$00
    sta RecordOffset
    jsr FindRecord

;; With the end found: counts the free blocks (<Bam::CopyFreeBlocks>) and what is needed.
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

;; 52 FILE TOO LARGE: more than 6 side sectors, or not enough free blocks. It does not return.
;; Also: AR20 (D1541)
TooBig:
    lda #ERROR_FILE_TOO_LARGE
    jsr Commands::Fail                  ; does not return

;; The entries needed...
;; Also: AR25 (D1541)
CountNeeded:
    lda SideSectorIndex
    sec
    sbc Work1
    bcs CountSideSectors
    sbc #SIDE_SECTOR_POINTERS-1
    clc

;; ...and the side sectors, into <CountBlocks::Start>; <Work2> set if it is one block.
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

;; Against the free blocks (<BlockTotal>).
;; Also: AR35 (D1541)
CompareFree:
    cmp BlockTotal+1
    bcc LinkNext
    bne TooBig
    lda BlockTotal
    cmp Temporary1
    bcc TooBig

;; Room: <ChannelNextRecord> from the last block's sector link, and a new block linked to it.
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

;; The entry put (<PutSideSectorByte>); on while blocks remain.
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

;; Still not in the file: 50 RECORD NOT PRESENT. It does not return.
;; Also: AR70 (D1541)
NoRecord:
    lda #RELATIVE_LAST_RECORD
    jsr Files::SetFlag
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Commands::Fail                  ; does not return
.endproc

;; Starts a side sector in a new block. It copies the link table into it, adds itself to the table, writes it, makes it
;; the side-sector buffer, links the old one to it, and adds it to every earlier side sector's table.
;; Also: NEWSS (D1541)
.proc NewSideSector
    ; Allocates the block, and copies the link table into a cleared buffer for the new side sector.
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

    ; Writes the old side sector's number plus 1, and the new block's track and sector, into the new side sector's
    ; buffer, noting where its entries go.
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

    ; Its own link 0 and last byte in use, written; then it becomes the channel's side-sector buffer.
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

    ; The old side sector, kept in the other buffer, links to it.
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
