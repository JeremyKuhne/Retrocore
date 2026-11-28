; retrocore: style=strict
; COMMODORE 1541 DOS: CHANNELS, BUFFERS, THE JOB QUEUE AND OPEN AND CLOSE ($CE0E-$DDF0)
.scope Relative continued

;; For the channel's record (`recl`/`rech`, `rs`) and `recptr`: the byte's place in the file, divided by 254 for its
;; block (`relptr`, the remainder plus 2 for the link) and by 120 for its side sector (`ssnum`) and entry (`ssind`, 16
;; plus twice the remainder).
;; Also: FNDREL (D1541)
.proc FindRecord
    jsr FindOffset
    jsr DivideBy254
    lda Accumulator+1
    sta BlockOffset
    jsr DivideBy120
    inc BlockOffset
    inc BlockOffset
    lda Product
    sta SideSectorNumber
    lda Accumulator+1
    asl
    clc
    adc #$10
    sta SideSectorIndex
    rts
.endproc

;; `Relative::Product` = (record - 1) * `rs` + `recptr`: the byte's offset in the file's data. Records 0 and 1 are both
;; the first.
;; Also: MULPLY (D1541)
.proc FindOffset
    jsr ClearProduct
    sta Accumulator+3
    ldx Channel
    lda ChannelRecord,x
    sta Accumulator+1
    lda ChannelRecordHigh,x
    sta Accumulator+2
    bne CountFromZero
    lda Accumulator+1
    beq Multiply

;; Takes 1 from the record number.
;; Also: MUL25 (D1541)
CountFromZero:
    lda Accumulator+1
    sec
    sbc #$01
    sta Accumulator+1
    bcs Multiply
    dec Accumulator+2

;; The record size into `temp`, the multiplier.
;; Also: MUL50 (D1541)
Multiply:
    lda ChannelRecordSize,x
    sta Temporary

;; Each bit of the size, low first: a 1 adds the shifted record number to `Relative::Product`.
;; Also: MUL100 (D1541)
NextBit:
    lsr Temporary
    bcc Double
    jsr AddToProduct

;; Doubles the record number for the next bit.
;; Also: MUL200 (D1541)
Double:
    jsr Relative::Double
    lda Temporary
    bne NextBit
    lda RecordOffset
    clc
    adc Product
    sta Product
    bcc Done
    inc Product+1
    bne Done
    inc Product+2

;; `recptr` added: done.
;; Also: MUL400 (D1541)
Done:
    rts
.endproc

;; Divides `Relative::Product` by 254 (bytes in a block): quotient in `Relative::Product`, remainder in
;; `Relative::Accumulator`+1. Skips <DivideBy120>'s load with a `BIT` (Q6).
;; Also: DIV254 (D1541)
.proc DivideBy254
    lda #$FE
    .byte OPCODE_BIT
.endproc

;; Divides `Relative::Product` by 120 (entries in a side sector), or by the divisor in A from <DivideBy254>: subtracts
;; whole 256s (or 128s), adding the 2 (or 8) each leaves over back in, until what is left is under 256.
;; Also: DIV120 (D1541)
.proc DivideBy120
    lda #$78
    sta Temporary
    ldx #$03

;; Swaps `Relative::Product` with `Relative::Accumulator`+1-3: the dividend into the accumulator.
;; Also: DIV100 (D1541)
Swap:
    lda Accumulator,x
    pha
    lda Product-1,x
    sta Accumulator,x
    pla
    sta Product-1,x
    dex
    bne Swap
    jsr ClearProduct

;; Each step: the accumulator divided by 256...
;; Also: DIV150 (D1541)
NextStep:
    ldx #$00

;; ...a byte at a time, leaving the low byte in `Relative::Accumulator`.
;; Also: DIV200 (D1541)
ShiftDown:
    lda Accumulator+1,x
    sta Accumulator,x
    inx
    cpx #$04
    bcc ShiftDown
    lda #$00
    sta Accumulator+3
    bit Temporary
    bmi AddQuotient
    asl Accumulator
    php
    lsr Accumulator
    plp
    jsr RotateLeft

;; Adds the step's quotient to `Relative::Product`, and makes it the leftover: times 2 for 254, times 8 for 120.
;; Also: DIV300 (D1541)
AddQuotient:
    jsr AddToProduct
    jsr Double
    bit Temporary
    bmi AddRemainder
    jsr Quadruple

;; Adds the low byte back in.
;; Also: DIV400 (D1541)
AddRemainder:
    lda Accumulator
    clc
    adc Accumulator+1
    sta Accumulator+1
    bcc TestSize
    inc Accumulator+2
    bne TestSize
    inc Accumulator+3

;; Another step while what is left is 256 or more.
;; Also: DIV500 (D1541)
TestSize:
    lda Accumulator+3
    ora Accumulator+2
    bne NextStep
    lda Accumulator+1
    sec
    sbc Temporary
    bcc Done
    inc Product
    bne SetRemainder
    inc Product+1
    bne SetRemainder
    inc Product+2

;; Under 256 but not under the divisor: one more in `Relative::Product`, the divisor off the remainder.
;; Also: DIV600 (D1541)
SetRemainder:
    sta Accumulator+1

;; Done.
;; Also: DIV700 (D1541)
Done:
    rts
.endproc

;; `Relative::Product`'s three bytes = 0; returns A = 0.
;; Also: ZERRES (D1541)
.proc ClearProduct
    lda #$00
    sta Product
    sta Product+1
    sta Product+2
    rts
.endproc

;; `Relative::Accumulator`+1-3 times 4; falls into <Double>.
;; Also: ACCX4 (D1541)
.proc Quadruple
    jsr Double
.endproc

;; `Relative::Accumulator`+1-3 times 2: clears carry and falls into <RotateLeft>.
;; Also: ACCX2 (D1541)
.proc Double
    clc
.endproc

;; Rotates `Relative::Accumulator`+1-3 left through carry.
;; Also: ACC200 (D1541)
.proc RotateLeft
    rol Accumulator+1
    rol Accumulator+2
    rol Accumulator+3
    rts
.endproc

;; `Relative::Product` += `Relative::Accumulator`+1-3.
;; Also: ADDRES (D1541)
.proc AddToProduct
    clc
    ldx #$FD

;; Each byte, X counting up from $FD.
;; Also: ADD100 (D1541)
NextByte:
    lda Product+3,x
    adc Accumulator+4,x
    sta Product+3,x
    inx
    bne NextByte
    rts
.endproc
.endscope
.scope Files continued

;; LRUINT: LRUTBL, the channels in order of use, = 0-3 and the BAM's index (BLINDX).
;; Also: LRUINT (D1541)
.proc ResetUseOrder
    ldx #$00

;; Each entry.
;; Also: LRUILP (D1541)
Loop:
    txa
    sta LeastRecentlyUsed,x
    inx
    cpx #COMMAND_CHANNEL
    bne Loop
    lda #BAM_CHANNEL
    sta LeastRecentlyUsed,x
    rts
.endproc

;; LRUUPD: moves LINDX to LRUTBL's end, the most recently used, shifting the others down; LRUTBL is reset when LINDX is
;; not in it.
;; Also: LRUUPD (D1541)
.proc MarkMostRecent
    ldy #COMMAND_CHANNEL
    ldx Channel

;; Each entry, from the end, until LINDX's.
;; Also: LRULP1 (D1541)
Loop:
    lda a:LeastRecentlyUsed,y
    stx LeastRecentlyUsed,y
    cmp Channel
    beq Done
    dey
    bmi ResetUseOrder
    tax
    jmp Loop

;; Returns.
;; Also: LRUEXT (D1541)
Done:
    rts
.endproc

;; DBLBUF: makes the channel's other buffer active and waits for its job; a channel with one buffer gets a second (error
;; 70, NO CHANNEL, if none), into which the block linked next is read first, except while writing. Relative files (part
;; 5) use it throughout.
;; Entry:
;;   NoBuffers = Error 70, NO CHANNEL (<AddSecondBuffer> comes here too)
;; Also: DBLBUF (D1541)
.proc SwapBuffers
    jsr MarkMostRecent
    jsr GetInactiveBuffer
    bne Swap
    jsr SetDriveFromBuffer
    jsr GetBuffer
    bmi NoBuffers
    jsr SetInactiveBuffer
    lda Track
    pha
    lda Sector
    pha
    lda #$01
    jsr PeekByte
    sta Sector
    lda #$00
    jsr PeekByte
    sta Track
    beq LastBlock
    jsr ChannelType
    beq ReadAhead
    jsr TestWriteJob
    bne ReadAhead
    jsr FlipBuffers
    jmp RestoreBlock

;; Relative, or reading: the swap, and a read of the linked block into the new active buffer.
;; Also: DBL05 (D1541)
ReadAhead:
    jsr FlipBuffers
    jsr ReadBlock

;; TRACK and SECTOR back.
;; Also: DBL08 (D1541)
RestoreBlock:
    pla
    sta Sector
    pla
    sta Track
    jmp Wait

;; No link: TRACK and SECTOR back, and the swap alone.
;; Also: DBL10 (D1541)
LastBlock:
    pla
    sta Sector
    pla
    sta Track

;; Swaps the two.
;; Also: DBL15 (D1541)
Swap:
    jsr FlipBuffers

;; Waits for the active buffer's job.
;; Also: DBL20 (D1541)
Wait:
    jsr GetActiveBuffer
    tax
    jmp Jobs::Wait

;; Error 70, NO CHANNEL (<AddSecondBuffer> comes here too).
;; Also: DBL30 (D1541)
NoBuffers:
    lda #ERROR_NO_CHANNEL
    jmp Commands::Fail
.endproc

;; DBSET: as <SwapBuffers> without the swap: the channel is marked used and gets an inactive buffer if it has none
;; (addrel, part 5, calls it).
;; Also: DBSET (D1541)
.proc AddSecondBuffer
    jsr MarkMostRecent
    jsr GetInactiveBuffer
    bne Done
    jsr GetBuffer
    bmi SwapBuffers::NoBuffers
    jsr SetInactiveBuffer

;; Returns.
;; Also: DBS10 (D1541)
Done:
    rts
.endproc

;; TGLBUF: flips bit 7 of BUF0 and BUF1 for LINDX, so the inactive buffer becomes the active one.
;; Also: TGLBUF (D1541)
.proc FlipBuffers
    ldx Channel
    lda ChannelBuffer,x
    eor #$80
    sta ChannelBuffer,x
    lda ChannelSecondBuffer,x
    eor #$80
    sta ChannelSecondBuffer,x
    rts
.endproc

;; PIBYTE: <AcceptByte> for the internal write channel (SA 18), its LED on; a relative file's overflow flag is cleared
;; first (the copy command uses it).
;; Also: PIBYTE (D1541)
.proc AcceptInternalByte
    ldx #INTERNAL_WRITE_SECONDARY
    stx SecondaryAddress
    jsr FindWriteChannel
    jsr TurnOnActivityLed
    jsr ChannelType
    bcc ToChannel
    lda #RELATIVE_OVERFLOW
    jsr ClearFlag

;; On to <AcceptByte>'s command or file path, by SA.
;; Also: PBYTE (D1541)
ToChannel:
    lda SecondaryAddress
    cmp #COMMAND_SECONDARY
    beq AcceptByte::ToCommand
    bne AcceptByte::ToFile
.endproc

;; PUT: takes DATA, the byte the bus received, for channel ORGSA: secondary address 15's go into the command buffer
;; (CMDWAT set at the last, EOIFLG 0), others into the file: sequential, relative (WRTREL) or direct.
;; Entry:
;;   ToFile = A file's byte, by type (<AcceptInternalByte> enters here)
;;   ToCommand = Into the command buffer, unless it is full (<AcceptInternalByte> enters here)
;; Also: PUT (D1541)
.proc AcceptByte
    lda SecondaryCommand
    and #$8F
    cmp #COMMAND_SECONDARY
    bcs ToCommand

;; A file's byte, by type (<AcceptInternalByte> enters here).
;; Also: L40 (D1541)
ToFile:
    jsr ChannelType
    bcs NotSequential
    lda DataByte
    jmp WriteByte

;; Relative: WRTREL.
;; Also: L41 (D1541)
NotSequential:
    bne Direct
    jmp Relative::WriteByte

;; Direct: stored, and the next byte made ready (<NextByte::RandomAtPointer>).
;; Also: L46 (D1541)
Direct:
    lda DataByte
    jsr PutByte
    ldy Channel
    jmp NextByte::RandomAtPointer

;; Into the command buffer, unless it is full (<AcceptInternalByte> enters here).
;; Also: L42 (D1541)
ToCommand:
    lda #COMMAND_CHANNEL
    sta Channel
    jsr GetPointer
    cmp #<CommandBuffer+COMMAND_LENGTH_MAX+1
    beq CheckEnd
    lda DataByte
    jsr PutByte

;; EOIFLG not yet 0: more to come.
;; Also: L50 (D1541)
CheckEnd:
    lda MoreBytes
    beq CommandReady
    rts

;; The last byte: CMDWAT up, a command to run.
;; Also: L45 (D1541)
CommandReady:
    inc CommandWaiting
    rts
.endproc

;; PUTBYT: A into the active buffer at its pointer, which moves on; Z set when that filled the buffer. Error 61, FILE
;; NOT OPEN, with no active buffer.
;; Entry:
;;   IntoBuffer = Stores the byte on the stack into buffer A (PutSideSectorByte enters here for the side sec
;; Also: PUTBYT (D1541)
.proc PutByte
    pha
    jsr GetActiveBuffer
    bpl IntoBuffer
    pla
    lda #ERROR_FILE_NOT_OPEN
    jmp Commands::Fail

;; Stores the byte on the stack into buffer A (PutSideSectorByte enters here for the side sector's buffer).
;; Also: PUTB1 (D1541)
IntoBuffer:
    asl
    tax
    pla
    sta (BufferPositions,x)
    inc BufferPositions,x
    rts
.endproc
.endscope
.scope Commands continued

;; The I command (the command table's entry): parses the drive and initializes it.
;; Also: INTDRV (D1541)
.proc Initialize
    jsr ParseDriveOnly
    jsr Bam::InitializeDrive
    jmp Finish
.endproc
.endscope
.scope Bam continued

;; ITRIAL: gives the BAM its buffer if it has none (error 70, NO CHANNEL), and runs a seek job to the directory track,
;; which reads a header's disk ID into HEADER; A = the job's result.
;; Also: ITRIAL (D1541)
.proc SeekHeader
    jsr ChannelIndex
    tay
    ldx ChannelBuffer,y
    cpx #$FF
    bne Seek
    pha
    jsr Files::GetBuffer
    tax
    bpl Buffered
    lda #ERROR_NO_CHANNEL
    jsr Errors::Recover

;; The buffer, marked inactive, as the BAM's.
;; Also: IT20 (D1541)
Buffered:
    pla
    tay
    txa
    ora #$80
    sta a:ChannelBuffer,y

;; JOBNUM = it, the job's header 18/0, and the seek.
;; Also: IT30 (D1541)
Seek:
    txa
    and #$0F
    sta JobNumber
    ldx #$00
    stx Sector
    ldx DirectoryTrack
    stx Track
    jsr Jobs::SetHeader::ForBuffer
    lda #JOB_SEEK
    jmp Jobs::Run
.endproc

;; INITDR: forgets the BAM images and closes the drive's channels, seeks, then keeps the disk's ID (DSKID), reads the
;; BAM (18/0) and its DOS version (DSKVER), clears WPSW and NODRV, and falls into <CountFreeBlocks>.
;; Also: INITDR (D1541)
.proc InitializeDrive
    jsr ForgetImages
    jsr Files::FreeDriveChannels
    jsr SeekHeader
    ldx DriveNumber
    lda #$00
    sta BamDirty,x
    txa
    asl
    tax
    lda LastHeader
    sta DiskId,x
    lda LastHeader+1
    sta DiskId+1,x
    jsr Jobs::Read
    lda JobNumber
    asl
    tax
    lda #$02
    sta BufferPositions,x
    lda (BufferPositions,x)
    ldx DriveNumber
    sta DiskVersion,x
    lda #$00
    sta DiskChanged,x
    sta NoDrive,x
.endproc

;; NFCALC: NDBL/NDBH = the free blocks in the BAM, the directory track's left out (<BuildEmpty> jumps here).
;; Also: NFCALC (D1541)
.proc CountFreeBlocks
    jsr SetPointer
    ldy #$04
    lda #$00
    tax

;; Each track's count.
;; Also: NUMF1 (D1541)
Add:
    clc
    adc (BamPointer),y
    bcc NextTrack
    inx

;; Four bytes on; track 18's entry ($48) skipped.
;; Also: NUMF2 (D1541)
NextTrack:
    iny
    iny
    iny
    iny
    cpy #$48
    beq NextTrack
    cpy #$90
    bne Add
    pha
    txa
    ldx DriveNumber
    sta FreeBlocksHigh,x
    pla
    sta FreeBlocks,x
    rts
.endproc
.endscope
.scope Files continued

;; STRRD: reads the block at TRACK and SECTOR into the active buffer and waits; TRACK and SECTOR = its link.
;; Also: STRRD (D1541)
.proc StartRead
    jsr Jobs::SetHeader
    jsr ReadFileBlock
    jsr Jobs::Wait
    jsr GetByte
    sta Track
    jsr GetByte
    sta Sector
    rts
.endproc

;; STRDBL: <StartRead>, then, when the file goes on, a read of its next block into a second buffer (record, part 5,
;; calls it).
;; Also: STRDBL (D1541)
.proc StartDoubleRead
    jsr StartRead
    lda Track
    bne ReadNext
    rts

;; The second buffer, and the read started in it.
;; Also: STR1 (D1541)
ReadNext:
    jsr SwapBuffers
    jsr Jobs::SetHeader
    jsr ReadFileBlock
    jmp SwapBuffers
.endproc

;; RDBUF: starts a read job on the active buffer; its header (track and sector) is already set by the caller, unlike
;; <Files::ReadBlock> (RDAB, part 5), which sets it. The buffer pointer is zeroed; X = the buffer on return.
;; Also: RDBUF (D1541)
.proc ReadFileBlock
    lda #JOB_READ
    bne WriteFileBlock::Start
.endproc

;; WRTBUF: starts a write job on the active buffer; its header is already set by the caller, unlike <Files::WriteBlock>
;; (WRTAB, part 5). The buffer pointer is zeroed and, for types below relative, the channel's block count (NBKL/NBKH)
;; goes up; X = the buffer on return.
;; Entry:
;;   Start = CMD = A, the job started (SETLJB), the pointer 0
;; Also: WRTBUF (D1541)
.proc WriteFileBlock
    lda #JOB_WRITE

;; CMD = A, the job started (SETLJB), the pointer 0; for types below relative the channel's block count (NBKL/NBKH) goes
;; up. X = the buffer (<ReadFileBlock> enters here).
;; Also: STRTIT (D1541)
Start:
    sta JobCommand
    jsr GetActiveBuffer
    tax
    jsr Jobs::StartOnLastDrive
    txa
    pha
    asl
    tax
    lda #$00
    sta BufferPositions,x
    jsr ChannelType
    cmp #TYPE_RELATIVE
    bcs Done
    inc ChannelBlocks,x
    bne Done
    inc ChannelBlocksHigh,x

;; X = the buffer.
;; Also: WRTC1 (D1541)
Done:
    pla
    tax
    rts
.endproc

;; FNDRCH: LINDX and X = the read channel of SA (SA 15's is the error channel's); carry set when it has none.
;; Also: FNDRCH (D1541)
.proc FindReadChannel
    lda SecondaryAddress
    cmp #LAST_SECONDARY+1
    bcc InRange
    and #$0F

;; SA 15 reads the error channel (SA 16).
;; Also: FNDC20 (D1541)
InRange:
    cmp #COMMAND_SECONDARY
    bne Lookup
    lda #MESSAGE_SECONDARY

;; LINTAB's entry: bit 7 clear for a read channel.
;; Also: FNDC25 (D1541)
Lookup:
    tax
    sec
    lda SecondaryChannels,x
    bmi Done
    and #$0F
    sta Channel
    tax
    clc

;; Returns.
;; Also: FNDC30 (D1541)
Done:
    rts
.endproc

;; FNDWCH: LINDX and X = the write channel of SA (LINTAB bit 7, or bit 6 for a relative file's); carry set when it has
;; none.
;; Also: FNDWCH (D1541)
.proc FindWriteChannel
    lda SecondaryAddress
    cmp #LAST_SECONDARY+1
    bcc Lookup
    and #$0F

;; LINTAB's entry, by its two top bits.
;; Also: FNDW13 (D1541)
Lookup:
    tax
    lda SecondaryChannels,x
    tay
    asl
    bcc ReadOnly
    bmi None

;; LINDX = it; carry clear.
;; Also: FNDW10 (D1541)
Found:
    tya
    and #$0F
    sta Channel
    tax
    clc
    rts

;; Bit 7 clear: a write channel only if bit 6 is set.
;; Also: FNDW15 (D1541)
ReadOnly:
    bmi Found

;; Carry set.
;; Also: FNDW20 (D1541)
None:
    sec
    rts
.endproc

;; TYPFIL: A = the channel's file type (FILTYP's bits 1-3), compared with the relative type: Z set for relative, carry
;; set for relative or above.
;; Also: TYPFIL (D1541)
.proc ChannelType
    ldx Channel
    lda ChannelFileType,x
    lsr
    and #$07
    cmp #TYPE_RELATIVE
    rts
.endproc

;; GETPRE: X = the active buffer's BUFTAB index, Y = LINDX (the relative files' routines use it).
;; Also: GETPRE (D1541)
.proc BufferIndexes
    jsr GetActiveBuffer
    asl
    tax
    ldy Channel
    rts
.endproc

;; GETBYT: A = the active buffer's next byte; Z set when it was the buffer's last, or, in the file's last block, the
;; byte at LSTCHR (the pointer then goes to 0).
;; Also: GETBYT (D1541)
.proc GetByte
    jsr BufferIndexes
    lda ChannelLastByte,y
    beq NotLastBlock
    lda (BufferPositions,x)
    pha
    lda BufferPositions,x
    cmp ChannelLastByte,y
    bne Next
    lda #$FF
    sta BufferPositions,x

;; Pointer on.
;; Also: GETB2 (D1541)
Next:
    pla
    inc BufferPositions,x
    rts

;; No LSTCHR: Z set when the pointer wraps.
;; Also: GETB1 (D1541)
NotLastBlock:
    lda (BufferPositions,x)
    inc BufferPositions,x
    rts
.endproc

;; RDBYT: A and DATA = the file's next byte; at a buffer's end the next block is made active and the one after it
;; started; with the file's last byte CHNRDY gets EOI.
;; Also: RDBYT (D1541)
.proc ReadByte
    jsr GetByte
    bne Done
    sta DataByte
    lda ChannelLastByte,y
    beq NextBlock
    lda #CHANNEL_TALK_LAST
    sta a:ChannelStatus,y
    lda DataByte
    rts

;; The other buffer: its link, and a read of the block after into this one.
;; Also: RD1 (D1541)
NextBlock:
    jsr SwapBuffers
    lda #$00
    jsr SetPointer
    jsr GetByte
    cmp #$00
    beq LastBlock
    sta Track
    jsr GetByte
    sta Sector
    jsr SwapBuffers
    jsr SetDriveFromBuffer
    jsr Jobs::SetHeader
    jsr ReadFileBlock
    jsr SwapBuffers
    lda DataByte

;; Returns.
;; Also: RD3 (D1541)
Done:
    rts

;; Link track 0: LSTCHR = the last byte's place.
;; Also: RD4 (D1541)
LastBlock:
    jsr GetByte
    ldy Channel
    sta ChannelLastByte,y
    lda DataByte
    rts
.endproc

;; WRTBYT: A into the file; when the buffer is full it goes out (NextBlock).
;; Entry:
;;   NextBlock = Allocates the next block, links the full buffer to it and starts its write, and swaps to t
;; Also: WRTBYT (D1541)
.proc WriteByte
    jsr PutByte
    beq NextBlock
    rts

;; Allocates the next block, links the full buffer to it and starts its write, and swaps to the other buffer, its
;; pointer 2 (<Append> enters here).
;; Also: WRT0 (D1541)
NextBlock:
    jsr SetDriveFromBuffer
    jsr Bam::AllocateNext
    lda #$00
    jsr SetPointer
    lda Track
    jsr PutByte
    lda Sector
    jsr PutByte
    jsr WriteFileBlock
    jsr SwapBuffers
    jsr Jobs::SetHeader
    lda #$02
    jmp SetPointer
.endproc

;; INCPTR: moves the active buffer's pointer, and DIRBUF, on by A.
;; Also: INCPTR (D1541), INCPNT (D1541)
.proc AdvancePointer
    sta Temporary
    jsr GetPointer
    clc
    adc Temporary
    sta BufferPositions,x
    sta BufferPointer
    rts
.endproc

;; SETDRN: DRVNUM = the drive of the active buffer's last job (LSTJOB).
;; Also: SETDRN (D1541)
.proc SetDriveFromBuffer
    jsr GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    sta DriveNumber
    rts
.endproc

;; GETWCH: <GetReadChannel> for a write channel (carry set).
;; Also: GETWCH (D1541)
.proc GetWriteChannel
    sec
    bcs GetReadChannel::Allocate
.endproc

;; GETRCH: frees SA's channel, gives SA a new one (LINDX, LINTAB; bit 7 for writing) and A buffers (BUF0, BUF1); SS
;; cleared. Error 70, NO CHANNEL, the buffers released, when they run out.
;; Entry:
;;   Allocate = Carry set for a write channel (<GetWriteChannel> enters here)
;;   NoBuffer = Releases the buffers and gives error 70, NO CHANNEL (<OpenReadChannel> and <OpenWriteChannel> 
;; Also: GETRCH (D1541)
.proc GetReadChannel
    clc

;; Carry set for a write channel (<GetWriteChannel> enters here).
;; Also: GETR2 (D1541)
Allocate:
    php
    sta Temporary
    jsr FreeChannel
    jsr AllocateChannel
    sta Channel
    ldx SecondaryAddress
    plp
    bcc SetEntry
    ora #$80

;; LINTAB for SA = the channel.
;; Also: GETR55 (D1541)
SetEntry:
    sta SecondaryChannels,x
    and #$3F
    tay
    lda #$FF
    sta a:ChannelBuffer,y
    sta a:ChannelSecondBuffer,y
    sta a:ChannelSideSector,y
    dec Temporary
    bmi Done
    jsr GetBuffer
    bpl Second

;; Releases the buffers and gives error 70, NO CHANNEL (<OpenReadChannel> and <OpenWriteChannel> come here without a
;; side-sector buffer).
;; Also: GBERR (D1541)
NoBuffer:
    jsr ReleaseBuffers
    lda #ERROR_NO_CHANNEL
    jmp Commands::Fail

;; BUF0 = the first; the second if wanted.
;; Also: GETR5 (D1541)
Second:
    sta a:ChannelBuffer,y
    dec Temporary
    bmi Done
    jsr GetBuffer
    bmi NoBuffer
    sta a:ChannelSecondBuffer,y

;; Returns.
;; Also: GETR4 (D1541)
Done:
    rts
.endproc

;; FRECHN: frees SA's channel, unless SA is 15: LINTAB cleared, CHNRDY 0, its buffers released and its index free in
;; LINUSE.
;; Also: FRECHN (D1541)
.proc FreeChannel
    lda SecondaryAddress
    cmp #COMMAND_SECONDARY
    bne Free
    rts

;; FRECO: the channel's release; FRERD and FREWRT are its other names here, in Also:.
;; Also: FRECO (D1541), FRERD (D1541), FREWRT (D1541)
Free:
    ldx SecondaryAddress
    lda SecondaryChannels,x
    cmp #$FF
    beq Done
    and #$3F
    sta Channel
    lda #$FF
    sta SecondaryChannels,x
    ldx Channel
    lda #$00
    sta ChannelStatus,x
    jsr ReleaseBuffers
    ldx Channel
    lda #$01

;; The channel's bit in LINUSE.
;; Also: REL15 (D1541)
Shift:
    dex
    bmi SetFree
    asl
    bne Shift

;; Set: free.
;; Also: REL10 (D1541)
SetFree:
    ora FreeChannels
    sta FreeChannels

;; Returns.
;; Also: FRE25 (D1541)
Done:
    rts
.endproc

;; RELBUF: frees the channel's buffers, BUF0, BUF1 and SS, each slot cleared.
;; Also: RELBUF (D1541)
.proc ReleaseBuffers
    ldx Channel
    lda ChannelBuffer,x
    cmp #$FF
    beq Second
    pha
    lda #$FF
    sta ChannelBuffer,x
    pla
    jsr FreeBuffer

;; BUF1.
;; Also: REL1 (D1541)
Second:
    ldx Channel
    lda ChannelSecondBuffer,x
    cmp #$FF
    beq SideSector
    pha
    lda #$FF
    sta ChannelSecondBuffer,x
    pla
    jsr FreeBuffer

;; SS.
;; Also: REL2 (D1541)
SideSector:
    ldx Channel
    lda ChannelSideSector,x
    cmp #$FF
    beq Done
    pha
    lda #$FF
    sta ChannelSideSector,x
    pla
    jsr FreeBuffer

;; Returns.
;; Also: REL3 (D1541)
Done:
    rts
.endproc

;; GETBUF: a free buffer (from the second byte of BUFUSE, then the first, else stolen); once its job is done, JOBS and
;; LSTJOB = DRVNUM and its pointer 2. A and X = it, N set (A = $FF) if none; Y kept.
;; Also: GETBUF (D1541)
.proc GetBuffer
    tya
    pha
    ldy #$01
    jsr FindFreeBuffer
    bpl Found
    dey
    jsr FindFreeBuffer
    bpl Found
    jsr StealBuffer
    tax
    bmi Done

;; Waits for its job, then sets it up.
;; Also: GBF1 (D1541)
Found:
    lda JobQueue,x
    bmi Found
    lda DriveNumber
    sta JobQueue,x
    sta LastJobs,x
    txa
    asl
    tay
    lda #$02
    sta a:BufferPositions,y

;; Y back; A = X.
;; Also: GBF2 (D1541)
Done:
    pla
    tay
    txa
    rts
.endproc

;; FNDBUF: the first free buffer in BUFUSE's byte Y, marked used; X = it (8 more for byte 1), or minus.
;; Entry:
;;   Return = Returns (<FreeInactiveBuffer> ends here when there is nothing to free)
;; Also: FNDBUF (D1541)
.proc FindFreeBuffer
    ldx #$07

;; Each bit, from 7.
;; Also: FB1 (D1541)
Loop:
    lda BuffersInUse,y
    and BitMasks,x
    beq Found
    dex
    bpl Loop
    rts

;; The bit set.
;; Also: FB2 (D1541)
Found:
    lda BuffersInUse,y
    eor BitMasks,x
    sta BuffersInUse,y
    txa
    dey
    bmi SetX
    clc
    adc #$08

;; X = it.
;; Also: FB3 (D1541)
SetX:
    tax

;; Returns (<FreeInactiveBuffer> ends here when there is nothing to free).
;; Also: FRI20 (D1541)
Return:
    rts
.endproc

;; FREIAC: frees the channel's inactive buffer, if it has one (record, part 5, calls it); falls into <FreeBuffer>.
;; Also: FREIAC (D1541)
.proc FreeInactiveBuffer
    ldx Channel
    lda ChannelBuffer,x
    bmi Found
    txa
    clc
    adc #CHANNEL_COUNT+1
    tax
    lda ChannelBuffer,x
    bpl FindFreeBuffer::Return

;; A buffer, if not empty: its slot cleared.
;; Also: FRI10 (D1541)
Found:
    cmp #$FF
    beq FindFreeBuffer::Return
    pha
    lda #$FF
    sta ChannelBuffer,x
    pla
.endproc

;; FREBUF: marks buffer A free in BUFUSE.
;; Also: FREBUF (D1541)
.proc FreeBuffer
    and #$0F
    tay
    iny
    ldx #$10

;; Rotates BUFUSE's 16 bits once round, the buffer's bit cleared on the way.
;; Also: FREB1 (D1541)
Loop:
    ror BuffersInUse+1
    ror BuffersInUse
    dey
    bne Next
    clc

;; The count.
;; Also: FREB2 (D1541)
Next:
    dex
    bpl Loop
    rts
.endproc

;; CLRCHN: frees the channels of secondary addresses 14 down to 1 (the new command calls it).
;; Also: CLRCHN (D1541)
.proc FreeAllChannels
    lda #COMMAND_SECONDARY-1
    sta SecondaryAddress

;; Each one.
;; Also: CLRC1 (D1541)
Loop:
    jsr FreeChannel
    dec SecondaryAddress
    bne Loop
    rts
.endproc

;; CLDCHN: frees each channel, SA 14 down to 0, whose active buffer's last job was for DRVNUM.
;; Also: CLDCHN (D1541)
.proc FreeDriveChannels
    lda #COMMAND_SECONDARY-1
    sta SecondaryAddress

;; Each secondary address.
;; Also: CLSD (D1541)
Next:
    ldx SecondaryAddress
    lda SecondaryChannels,x
    cmp #$FF
    beq Skip
    and #$3F
    sta Channel
    jsr GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    cmp DriveNumber
    bne Skip
    jsr FreeChannel

;; The next.
;; Also: CLD2 (D1541)
Skip:
    dec SecondaryAddress
    bpl Next
    rts
.endproc

;; STLBUF: takes an inactive buffer, from the least recently used channel on (LRUTBL), whose job finished without error,
;; clearing its slot. A = it, minus if none.
;; Also: STLBUF (D1541)
.proc StealBuffer
    lda Temporary
    pha
    ldy #$00

;; Each channel's BUF0.
;; Also: STL05 (D1541)
EachChannel:
    ldx LeastRecentlyUsed,y
    lda ChannelBuffer,x
    bpl OtherSlot
    cmp #$FF
    bne Inactive

;; Its BUF1.
;; Also: STL10 (D1541)
OtherSlot:
    txa
    clc
    adc #CHANNEL_COUNT+1
    tax
    lda ChannelBuffer,x
    bpl NextChannel
    cmp #$FF
    bne Inactive

;; The next in LRUTBL.
;; Also: STL20 (D1541)
NextChannel:
    iny
    cpy #CHANNEL_COUNT-1
    bcc EachChannel
    ldx #$FF
    bne Done

;; An inactive buffer: T0 = its slot.
;; Also: STL30 (D1541)
Inactive:
    stx Temporary
    and #$3F
    tax

;; Its job done; one with an error is passed over.
;; Also: STL40 (D1541)
WaitJob:
    lda JobQueue,x
    bmi WaitJob
    cmp #$02
    bcc Take
    ldx Temporary
    cpx #CHANNEL_COUNT+1
    bcc OtherSlot
    bcs NextChannel

;; Its slot cleared.
;; Also: STL50 (D1541)
Take:
    ldy Temporary
    lda #$FF
    sta a:ChannelBuffer,y

;; T0 back; A = the buffer.
;; Also: STL60 (D1541)
Done:
    pla
    sta Temporary
    txa
    rts
.endproc

;; FNDLNX: the first free channel index in LINUSE, marked used; A = it. Error 70, NO CHANNEL, if none.
;; Also: FNDLNX (D1541)
.proc AllocateChannel
    ldy #$00
    lda #$01

;; Each bit.
;; Also: FND10 (D1541)
Loop:
    bit FreeChannels
    bne Found
    iny
    asl
    bne Loop
    lda #ERROR_NO_CHANNEL
    jmp Commands::Fail

;; Marked used.
;; Also: FND30 (D1541)
Found:
    eor #$FF
    and FreeChannels
    sta FreeChannels
    tya
    rts
.endproc

;; GBYTE: the next byte of SA's read channel, its LED on; A = it (the copy command uses it).
;; Also: GBYTE (D1541)
.proc ReadChannelByte
    jsr FindReadChannel
    jsr TurnOnActivityLed
    jsr NextByte
    ldx Channel
    lda ChannelByte,x
    rts
.endproc

;; GET: puts channel LINDX's next byte in CHNDAT and sets CHNRDY, for the bus to send: from a relative record (RDREL),
;; the error channel, the directory listing, a file or a direct buffer. After the last byte only a direct channel goes
;; on.
;; Entry:
;;   NextRandom = The pointer on, then the byte (the block commands enter here)
;;   RandomAtPointer = The byte at the pointer into CHNDAT, CHNRDY with EOI at LSTCHR (<AcceptByte> and the block c
;;   ErrorEnd = The last
;;   ErrorReady = CHNRDY = ready to talk (the memory-read command enters here)
;; Also: GET (D1541)
.proc NextByte
    ldx Channel
    jsr ChannelType
    bne NotRelative
    jmp Relative::ReadByte

;; Not relative: SA 15 is the error channel.
;; Also: GET00 (D1541)
NotRelative:
    lda SecondaryAddress
    cmp #COMMAND_SECONDARY
    beq ErrorChannel
    lda ChannelStatus,x
    and #CHANNEL_MORE
    bne More
    jsr ChannelType
    cmp #TYPE_DIRECT
    bne NotReady
    lda #CHANNEL_RANDOM
    sta ChannelStatus,x
    jmp RandomByte

;; The last byte went with EOI: CHNRDY = not ready.
;; Also: GET0 (D1541)
NotReady:
    lda #CHANNEL_NOT_READY
    sta ChannelStatus,x
    rts

;; Not after EOI: SA 0, a load, is the listing or the file; others by type.
;; Also: GET1 (D1541)
More:
    lda SecondaryAddress
    beq Load
    jsr ChannelType
    cmp #TYPE_RELATIVE
    bcc Sequential

;; A direct or user channel's next byte; after the last the pointer wraps.
;; Also: RNDGET (D1541)
RandomByte:
    jsr BufferIndexes
    lda BufferPositions,x
    cmp ChannelLastByte,y
    bne NextRandom
    lda #$00
    sta BufferPositions,x

;; The pointer on, then the byte (the block commands enter here).
;; Also: RNGET1 (D1541)
NextRandom:
    inc BufferPositions,x

;; The byte at the pointer into CHNDAT, CHNRDY with EOI at LSTCHR (<AcceptByte> and the block commands enter here).
;; Also: RNGET2 (D1541)
RandomAtPointer:
    lda (BufferPositions,x)
    sta ChannelByte,y
    lda BufferPositions,x
    cmp ChannelLastByte,y
    bne RandomDone
    lda #CHANNEL_RANDOM_LAST
    sta a:ChannelStatus,y

;; Returns.
;; Also: RNGET3 (D1541)
RandomDone:
    rts

;; <ReadByte>.
;; Also: SEQGET (D1541)
Sequential:
    jsr ReadByte

;; CHNDAT = A.
;; Also: GET3 (D1541)
Store:
    ldx Channel
    sta ChannelByte,x
    rts

;; DIRLST set: the listing's next byte.
;; Also: GET6 (D1541)
Load:
    lda ListingActive
    beq Sequential
    jsr Directory::NextListingByte
    jmp Store

;; The error channel: after the message's last byte, a RETURN with EOI, and the error reset to 00, OK.
;; Also: GETERC (D1541)
ErrorChannel:
    jsr GetPointer
    cmp #<ErrorBuffer-1
    bne ErrorByte
    lda BufferPointer+1
    cmp #>ErrorBuffer
    bne ErrorByte
    lda #CARRIAGE_RETURN
    sta DataByte
    jsr Errors::StopFlashing
    lda #$00
    jsr Errors::SetMessageWithoutBlock
    dec CommandPointer+2
    lda #CHANNEL_TALK_LAST
    bne SetError

;; The message's next byte.
;; Also: GE10 (D1541)
ErrorByte:
    jsr GetByte
    sta DataByte
    bne ErrorReady

;; The last: the pointer back before ERRBUF, so a RETURN comes next (the memory-read command enters here).
;; Also: GE15 (D1541)
ErrorEnd:
    lda #<ErrorBuffer-1
    jsr SetPointer
    lda #>ErrorBuffer
    sta BufferPositions+1,x

;; CHNRDY = ready to talk (the memory-read command enters here).
;; Also: GE20 (D1541)
ErrorReady:
    lda #CHANNEL_TALK

;; The error channel's CHNRDY and CHNDAT.
;; Also: GE30 (D1541)
SetError:
    sta ChannelStatus+MESSAGE_CHANNEL
    lda DataByte
    sta ChannelByte+MESSAGE_CHANNEL
    rts
.endproc

;; NXTBUF: the file's next block, when the active buffer links to one, through <ReadByte>; Z set when there is none.
;; Also: NXTBUF (D1541)
.proc FollowLink
    jsr GetActiveBuffer
    asl
    tax
    lda #$00
    sta BufferPositions,x
    lda (BufferPositions,x)
    beq Done
    dec BufferPositions,x
    jmp ReadByte

;; Returns.
;; Also: NXTB1 (D1541)
Done:
    rts
.endproc
.endscope
.scope Jobs continued

;; DRTRD: reads TRACK and SECTOR into buffer JOBNUM and waits.
;; Also: DRTRD (D1541)
.proc ReadTrackSector
    lda #JOB_READ
    bne WriteTrackSector::Start
.endproc

;; DRTWRT: writes buffer JOBNUM to TRACK and SECTOR and waits.
;; Entry:
;;   Start = The job for DRVNUM, its header set, run and waited for (DOIT2)
;; Also: DRTWRT (D1541)
.proc WriteTrackSector
    lda #JOB_WRITE

;; The job for DRVNUM, its header set, run and waited for (DOIT2); <ReadTrackSector> enters here.
;; Also: DRT (D1541)
Start:
    ora DriveNumber
    sta JobCommand
    lda JobNumber
    jsr SetHeader::ForBuffer
    ldx JobNumber
    jmp Run::Repeat
.endproc
.endscope
.scope Files continued

;; OPNIRD: opens the internal read channel (SA 17) on TRACK and SECTOR as a sequential file, its pointer 2.
;; Entry:
;;   WithType = Of type A (the utility loader enters here)
;; Also: OPNIRD (D1541)
.proc OpenInternalRead
    lda #$01

;; Of type A (the utility loader enters here).
;; Also: OPNTYP (D1541)
WithType:
    sta FileType
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr OpenReadChannel
    lda #$02
    jmp SetPointer
.endproc

;; OPNIWR: opens the internal write channel (SA 18).
;; Also: OPNIWR (D1541)
.proc OpenInternalWrite
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jmp OpenWriteChannel
.endproc
.endscope
.scope Directory continued

;; NXDRBK: allocates the directory's next block (three sectors on, on track 18), links the current one to it and writes
;; it, then clears the buffer for the new block, link 0/$FF.
;; Also: NXDRBK (D1541)
.proc NewBlock
    jsr Files::GetChannelBlock
    lda #$01
    sta Temporary
    lda SectorInterleave
    pha
    lda #$03
    sta SectorInterleave
    jsr Bam::AllocateNext::Search
    pla
    sta SectorInterleave
    lda #$00
    jsr Files::SetPointer
    lda Track
    jsr Files::PutByte
    lda Sector
    jsr Files::PutByte
    jsr Files::WriteFileBlock
    jsr Jobs::Wait
    lda #$00
    jsr Files::SetPointer

;; Zeros to the buffer's end.
;; Also: NXDB1 (D1541)
Clear:
    jsr Files::PutByte
    bne Clear
    jsr Files::PutByte
    lda #$FF
    jmp Files::PutByte
.endproc
.endscope
.scope Files continued

;; SETPNT: the active buffer's pointer, and DIRBUF, = A.
;; Also: SETPNT (D1541)
.proc SetPointer
    sta Temporary
    jsr GetActiveBuffer
    asl
    tax
    lda BufferPositions+1,x
    sta BufferPointer+1
    lda Temporary
    sta BufferPositions,x
    sta BufferPointer
    rts
.endproc

;; FREICH: frees the internal read and write channels (SA 17 and 18).
;; Also: FREICH (D1541)
.proc FreeInternalChannels
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr FreeChannel
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jmp FreeChannel
.endproc

;; GETPNT: DIRBUF = the active buffer's pointer; A = its low byte.
;; Entry:
;;   OfBuffer = The same for buffer A (ssutil, part 5, enters here)
;;   OfBuffer = SETDIR
;; Also: GETPNT (D1541)
.proc GetPointer
    jsr GetActiveBuffer

;; SETDIR: a second name at OfBuffer's address; in its Also:.
;; Also: SETDIR (D1541), GP1 (D1541)
OfBuffer:
    asl
    tax
    lda BufferPositions+1,x
    sta BufferPointer+1
    lda BufferPositions,x
    sta BufferPointer
    rts
.endproc

;; DRDBYT: A = byte A of the active buffer, its pointer unchanged.
;; Also: DRDBYT (D1541)
.proc PeekByte
    sta Temporary+2
    jsr GetActiveBuffer
    tax
    lda BufferPages,x
    sta Temporary+3
    ldy #$00
    lda (Temporary+2),y
    rts
.endproc
.endscope
.scope Jobs continued

;; A = `CMD` plus the drive bit of buffer X's last job (`LSTJOB`); falls into <Start>.
;; Also: SETLJB (D1541)
.proc StartOnLastDrive
    lda LastJobs,x
    and #$01
    ora JobCommand
.endproc

;; Checks job X's track against `MAXTRK`, and for a write the disk version against `VERNUM` and the sector against
;; MAXSEC; falls into <TrackSectorError> when they are bad, branches to <Queue> when good.
;; Also: SETJOB (D1541)
.proc Start
    pha
    stx JobNumber
    txa
    asl
    tax
    lda JobHeaders+1,x
    sta JobCommand
    lda JobHeaders,x
    beq TrackSectorError
    cmp TrackLimit
    bcs TrackSectorError
    tax
    pla
    pha
    and #$F0
    cmp #JOB_WRITE
    bne Queue
    pla
    pha
    lsr
    bcs SecondDriveVersion
    lda DiskVersion
    bcc CheckVersion

;; A = drive 1's `DSKVER`.
;; Also: SJB2 (D1541)
SecondDriveVersion:
    lda DiskVersion+1

;; A version of 0 (none read yet) passes; any other must be `VERNUM`.
;; Also: SJB3 (D1541)
CheckVersion:
    beq CheckSector
    cmp FormatType
    bne VersionError

;; The sector must be below the track's MAXSEC.
;; Also: SJB4 (D1541)
CheckSector:
    txa
    jsr SectorsOnTrack
    cmp JobCommand
    beq TrackSectorError
    bcs Queue
.endproc

;; Copies the job's header to `TRACK` and `SECTOR` for the message and reports 66, ILLEGAL TRACK OR SECTOR, through
;; CMDER2.
;; Entry:
;;   Report = Reports 66 with `TRACK` and `SECTOR` as they are
;; Also: TSERR (D1541)
.proc TrackSectorError
    jsr LoadTrackSector

;; Reports 66 with `TRACK` and `SECTOR` as they are; <CheckTrackSector> branches here.
;; Also: TSER1 (D1541)
Report:
    lda #ERROR_ILLEGAL_TRACK_SECTOR
    jmp Errors::Abort
.endproc

;; `TRACK` and `SECTOR` = job `JOBNUM`'s header (two bytes a job since the 4/12 patch).
;; Also: HED2TS (D1541)
.proc LoadTrackSector
    lda JobNumber
    asl
    tax
    lda JobHeaders,x
    sta Track
    lda JobHeaders+1,x
    sta Sector
    rts
.endproc

;; Checks `TRACK` (1 to `MAXTRK`-1) and `SECTOR` (below MAXSEC); returns if good, else reports 66.
;; Also: TSCHK (D1541)
.proc CheckTrackSector
    lda Track
    beq TrackSectorError::Report
    cmp TrackLimit
    bcs TrackSectorError::Report
    jsr SectorsOnTrack
    cmp Sector
    beq TrackSectorError::Report
    bcc TrackSectorError::Report
    rts
.endproc

;; Reports 73 (`CBMV2`), the disk's DOS version is not this one's, for a write; NEW jumps here too.
;; Also: VNERR (D1541)
.proc VersionError
    jsr LoadTrackSector
    lda #ERROR_DOS_VERSION
    jmp Errors::Abort
.endproc

;; Start's tail, reached by branch with the command on the stack: stores it in `CMD`, `JOBS` and `LSTJOB` for job
;; `JOBNUM`, which starts the job.
;; Also: SJB1 (D1541)
.proc Queue
    ldx JobNumber
    pla
    sta JobCommand
    sta JobQueue,x
    sta LastJobs,x
    rts
.endproc

;; Reads the job's sector and waits: A = `READ`, then branches to <Run>.
;; Also: DOREAD (D1541)
.proc Read
    lda #JOB_READ
    bne Run
.endproc

;; Writes the job's sector and waits: A = `WRITE`; falls into <Run>.
;; Also: DOWRIT (D1541)
.proc Write
    lda #JOB_WRITE
.endproc

;; Runs job type A on drive `DRVNUM` for job `JOBNUM` and waits; falls into <Wait>.
;; Entry:
;;   WithDrive = Runs command A, which already has its drive bit, for job X
;;   Repeat = Runs `CMD` again for job X, after a caller has set a new header
;; Also: DOJOB (D1541)
.proc Run
    ora DriveNumber
    ldx JobNumber

;; Runs command A, which already has its drive bit, for job X.
;; Also: DOIT (D1541)
WithDrive:
    sta JobCommand

;; Runs `CMD` again for job X, after a caller has set a new header.
;; Also: DOIT2 (D1541)
Repeat:
    lda JobCommand
    jsr Start
.endproc

;; Polls job X until it is done, recovering from its errors, then clears `JOBRTN`; A = the job's code.
;; Also: WATJOB (D1541)
.proc Wait
    jsr Poll
    bcs Wait
    pha
    lda #$00
    sta JobErrorReturn
    pla
    rts
.endproc

;; Carry set while job X is still running; carry clear when it is done, after recovering from an error, or with the
;; error returned when `JOBRTN` bit 7 asks for that.
;; Also: TSTJOB (D1541)
.proc Poll
    lda JobQueue,x
    bmi Busy
    cmp #$02
    bcc Finished
    cmp #$08
    beq NotRetried
    cmp #$0B
    beq NotRetried
    cmp #$0F
    bne Recover

;; Write protect (8), ID mismatch (11) and no drive (15) are not retried: returned if `JOBRTN` asks, else reported.
;; Also: TJ10 (D1541)
NotRetried:
    bit JobErrorReturn
    bmi Finished
    jmp ReportError

;; Carry clear: done.
;; Also: OK (D1541)
Finished:
    clc
    rts

;; Carry set: still running.
;; Also: NOTYET (D1541)
Busy:
    sec
    rts

;; Error recovery: selects the job's drive and its LED mask, and retries the job `REVCNT` times.
;; Also: RECOV (D1541)
Recover:
    tya
    pha
    lda DriveNumber
    pha
    lda LastJobs,x
    and #$01
    sta DriveNumber
    tay
    lda LedMasks,y
    sta ErrorLed
    jsr Retry
    cmp #$02
    bcs RetriesFailed
    jmp Restore

;; Keeps the job's type, and turns a write into a sector seek (`SECSEK`) for the rest of the recovery, so nothing is
;; written while the head is off.
;; Also: REC01 (D1541)
RetriesFailed:
    lda LastJobs,x
    and #$F0
    pha
    cmp #JOB_WRITE
    bne TryOffsets
    lda DriveNumber
    ora #JOB_SECTOR_SEEK
    sta LastJobs,x

;; Unless `REVCNT` bit 6 turns them off, retries with the head offset by each entry of `OFFSET` in turn.
;; Also: REC0 (D1541)
TryOffsets:
    bit Retries
    bvs CheckBump
    lda #$00
    sta OffsetIndex
    sta TotalOffset

;; Moves the head by the next offset, keeps the total in `TOFF`, and retries; a 0 ends the table.
;; Also: REC1 (D1541)
NextOffset:
    ldy OffsetIndex
    lda TotalOffset
    sec
    sbc RecoveryOffsets,y
    sta TotalOffset
    lda RecoveryOffsets,y
    jsr OffsetHead
    inc OffsetIndex
    jsr Retry
    cmp #$02
    bcc Recentre
    ldy OffsetIndex
    lda RecoveryOffsets,y
    bne NextOffset

;; Moves the head back by the total offset.
;; Also: REC3 (D1541)
Recentre:
    lda TotalOffset
    jsr OffsetHead
    lda JobQueue,x
    cmp #$02
    bcc Recovered

;; `REVCNT` bit 7 clear: tries a bump.
;; Also: REC5 (D1541)
CheckBump:
    bit Retries
    bpl Bump

;; Recovery failed: restores a write job in `LSTJOB`.
;; Also: QUIT (D1541)
Fail:
    pla
    cmp #JOB_WRITE
    bne ReportError
    ora DriveNumber
    sta LastJobs,x

;; Reports the job's code as a DOS error through ERROR, which does not return.
;; Also: QUIT2 (D1541)
ReportError:
    lda JobQueue,x
    jsr Errors::JobError

;; Returns the error if `JOBRTN` asks; else queues a bump on the drive.
;; Also: REC7 (D1541)
Bump:
    pla
    bit JobErrorReturn
    bmi Restore
    pha
    lda #JOB_BUMP
    ora DriveNumber
    sta JobQueue,x

;; Waits for the bump, then retries the job once more.
;; Also: REC8 (D1541)
WaitBump:
    lda JobQueue,x
    bmi WaitBump
    jsr Retry
    cmp #$02
    bcs Fail

;; The job, or its sector seek, worked: a write is put back and retried for real.
;; Also: REC9 (D1541)
Recovered:
    pla
    cmp #JOB_WRITE
    bne Restore
    ora DriveNumber
    sta LastJobs,x
    jsr Retry
    cmp #$02
    bcs ReportError

;; Restores `DRVNUM` and Y; A = the job's code, carry clear.
;; Also: REC95 (D1541)
Restore:
    pla
    sta DriveNumber
    pla
    tay
    lda JobQueue,x
    clc
    rts
.endproc

;; Moves the head A half-tracks, inward for positive (the listing's comments have the directions reversed), one
;; <StepHead> at a time.
;; Also: HEDOFF (D1541)
.proc OffsetHead
    cmp #$00
    beq Done
    bmi StepOut

;; One half-track inward (Y = 1).
;; Also: HOF1 (D1541)
StepIn:
    ldy #$01
    jsr StepHead
    sec
    sbc #$01
    bne StepIn
    beq Done

;; One half-track outward (Y = $FF).
;; Also: HOF2 (D1541)
StepOut:
    ldy #$FF
    jsr StepHead
    clc
    adc #$01
    bne StepOut

;; Returns.
;; Also: HOF3 (D1541)
Done:
    rts
.endproc

;; Puts Y (1 in, $FF out) in the drive's `PHASE` for the controller's EndPass to step, waits until it takes it, and
;; clears it; keeps A.
;; Also: MOVHED (D1541)
.proc StepHead
    pha
    tya
    ldy DriveNumber
    sta StepRequest,y

;; Waits for the controller to change `PHASE`.
;; Also: MH10 (D1541)
Wait:
    cmp StepRequest,y
    beq Wait
    lda #$00
    sta StepRequest,y
    pla
    rts
.endproc

;; Requeues the last job (`LSTJOB`) up to `REVCNT` & $3F times, flashing the drive's LED each try, until it works;
;; leaves the LED on; A = the code.
;; Also: DOREC (D1541)
.proc Retry
    lda Retries
    and #$3F
    tay

;; Toggles the LED and requeues the job.
;; Also: DOREC1 (D1541)
Again:
    lda ErrorLed
    eor DriveControl
    sta DriveControl
    lda LastJobs,x
    sta JobQueue,x

;; Waits for the job; below 2 is success.
;; Also: DOREC2 (D1541)
Wait:
    lda JobQueue,x
    bmi Wait
    cmp #$02
    bcc Done
    dey
    bne Again

;; Turns the LED back on and returns the code.
;; Also: DOREC3 (D1541)
Done:
    pha
    lda ErrorLed
    ora DriveControl
    sta DriveControl
    pla
    rts
.endproc

;; Sets the active buffer's job header (GETACT) to `TRACK` and `SECTOR`.
;; Entry:
;;   ForBuffer = The same for buffer A
;; Also: SETHDR (D1541)
.proc SetHeader
    jsr Files::GetActiveBuffer

;; The same for buffer A. Leaves X = `DRVNUM` x 2, which is what is left of the ID copy the 4/12 patch commented out.
;; Also: SETH (D1541)
ForBuffer:
    asl
    tay
    lda Track
    sta a:JobHeaders,y
    lda Sector
    sta a:JobHeaders+1,y
    lda DriveNumber
    asl
    tax
    rts
.endproc
.endscope
.scope Directory continued

;; ADDFIL: writes the directory entry for the file being opened: in the first deleted slot, or a new block when there is
;; none; type (a relative file's already closed), first track and sector, name, side sector and record size. The tables
;; and the channel's DSEC/DIND get its place.
;; Also: ADDFIL (D1541)
.proc AddEntry
    lda SecondaryAddress
    pha
    lda Channel
    pha
    lda Sector
    pha
    lda Track
    pha
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr Files::GetChannelBlock
    lda FileType
    pha
    lda FileNameDrive
    and #$01
    sta DriveNumber
    ldx JobNumber
    eor LastJobs,x
    lsr
    bcc SameDrive
    ldx #$01
    stx FreeEntryIndex
    jsr Search
    beq NewBlock
    bne WriteEntry

;; The last search's sector is the drive's: its first deleted slot, read in if need be.
;; Also: AF08 (D1541)
SameDrive:
    lda FreeEntrySector
    beq SearchOn
    cmp Sector
    beq WriteEntry
    sta Sector
    jsr Jobs::ReadTrackSector
    jmp WriteEntry

;; No deleted slot noted: the search goes on for one.
;; Also: AF10 (D1541)
SearchOn:
    lda #$01
    sta FreeEntryIndex
    jsr Search::Next
    bne WriteEntry

;; None: a new block, its first slot.
;; Also: AF15 (D1541)
NewBlock:
    jsr Directory::NewBlock
    lda Sector
    sta FreeEntrySector
    lda #$02
    sta FreeEntryIndex

;; The entry at DELIND.
;; Also: AF20 (D1541)
WriteEntry:
    lda FreeEntryIndex
    jsr Files::SetPointer
    pla
    sta FileType
    cmp #TYPE_RELATIVE
    bne StoreType
    ora #$80

;; The type.
;; Also: AF25 (D1541)
StoreType:
    jsr Files::PutByte
    pla
    sta FileNameTrack
    jsr Files::PutByte
    pla
    sta FileNameSector
    jsr Files::PutByte
    jsr Files::GetActiveBuffer
    tay
    lda FileNameStart
    tax
    lda #$10
    jsr Commands::CopyName
    ldy #$10
    lda #$00

;; Bytes 16-26 cleared.
;; Also: AF30 (D1541)
ClearRest:
    sta (BufferPointer),y
    iny
    cpy #$1B
    bcc ClearRest
    lda FileType
    cmp #TYPE_RELATIVE
    bne WriteBlock
    ldy #$10
    lda SideSectorTrack
    sta (BufferPointer),y
    iny
    lda SideSectorSector
    sta (BufferPointer),y
    iny
    lda RecordSize
    sta (BufferPointer),y

;; The sector written; the variables back.
;; Also: AF50 (D1541)
WriteBlock:
    jsr Jobs::WriteTrackSector
    pla
    sta Channel
    tax
    pla
    sta SecondaryAddress
    lda FreeEntrySector
    sta FileNameEntrySector
    sta ChannelEntrySector,x
    lda FreeEntryIndex
    sta FileNameEntryIndex
    sta ChannelEntryIndex,x
    lda FileType
    sta FileNamePattern
    lda DriveNumber
    sta FileNameDrive
    rts
.endproc
.endscope
.scope Files continued

;; OPEN, for a secondary address other than 15: parses the name sent, finds it in the directory, and opens a channel for
;; it by mode and type: "*" loads the last program, "$" the directory, "#" a direct channel; else read, write, replace
;; (@), append or modify.
;; Also: OPEN (D1541)
.proc Open
    lda SecondaryAddress
    sta SavedSecondary
    jsr Commands::Prepare
    stx CommandNumber
    ldx CommandBuffer
    lda SavedSecondary
    bne NotLastProgram
    cpx #'*'
    bne NotLastProgram
    lda LastProgramTrack
    beq NoLastProgram
    sta Track
    lda LastProgramDrive
    sta DriveNumber
    sta FileNameDrive
    lda #TYPE_PROGRAM
    sta FileNamePattern
    lda LastProgramSector
    sta Sector
    jsr TurnOnActivityLed
    jsr OpenReadChannel
    lda #TYPE_PROGRAM+TYPE_PROGRAM
    ora DriveNumber

;; FILTYP = A; the command ends. (The store indexes with Y, which the read leaves as the channel; the code loads X.)
;; Also: ENDRD (D1541)
SetType:
    ldx Channel
    sta a:ChannelFileType,y
    jmp Commands::Finish

;; "$": the directory.
;; Also: OP021 (D1541)
NotLastProgram:
    cpx #'$'
    bne NotDirectory
    lda SavedSecondary
    bne DirectoryAsFile
    jmp LoadDirectory

;; Not SA 0: the directory as a sequential file.
;; Also: OP04 (D1541)
DirectoryAsFile:
    jsr Commands::ParseDriveOnly
    lda DirectoryTrack
    sta Track
    lda #$00
    sta Sector
    jsr OpenReadChannel
    lda DriveNumber
    ora #TYPE_SEQUENTIAL+TYPE_SEQUENTIAL
    jmp SetType

;; "#": a direct channel (the block command's).
;; Also: OP041 (D1541)
NotDirectory:
    cpx #'#'
    bne ParseName
    jmp OpenDirect

;; No program loaded yet: drive 0 initialized, and its first program.
;; Also: OP0415 (D1541)
NoLastProgram:
    lda #TYPE_PROGRAM
    sta MatchType
    lda #$00
    sta DriveNumber
    sta LastDrive
    jsr Bam::InitializeDrive

;; The name, after a colon if there is one.
;; Also: OP042 (D1541)
ParseName:
    jsr Commands::FindColon
    bne HasColon
    ldx #$00
    beq SetName

;; More than a drive before it is error 30, SYNTAX ERROR.
;; Also: OP049 (D1541)
HasColon:
    txa
    beq BeforeColon
    lda #ERROR_SYNTAX
    jmp Commands::Fail

;; Back to the drive number, if any.
;; Also: OP10 (D1541)
BeforeColon:
    dey
    beq SetName
    dey

;; FILTBL; the name parsed and looked up; then the type and mode, if given.
;; Also: OP20 (D1541)
SetName:
    sty FileNameStart
    lda #$8D
    jsr Commands::ScanFor
    inx
    stx SecondStreamEnd
    jsr Commands::SetFirstDrive
    jsr Directory::ChooseDrives
    jsr Directory::FindFile::First
    ldx #$00
    stx RecordSize
    stx Mode
    stx FileType
    inx
    cpx FirstStreamEnd
    bcs SetMode
    jsr ParseTypeAndMode
    inx
    cpx FirstStreamEnd
    bcs SetMode
    cpy #TYPE_RELATIVE
    beq SetRecordSize
    jsr ParseTypeAndMode

;; SA back; SA 0 or 1, a load or save, is read or write mode, program type.
;; Also: OP40 (D1541)
SetMode:
    ldx SavedSecondary
    stx SecondaryAddress
    cpx #$02
    bcs DefaultType
    stx Mode
    lda #$40
    sta BamWriteDeferred
    lda FileType
    bne ByMode
    lda #TYPE_PROGRAM
    sta FileType

;; The type given, else the file's, else sequential.
;; Also: OP45 (D1541)
DefaultType:
    lda FileType
    bne ByMode
    lda FileNamePattern
    and #TYPE_MASK
    sta FileType
    lda FileNameTrack
    bne ByMode
    lda #TYPE_SEQUENTIAL
    sta FileType

;; Write mode, or read.
;; Also: OP50 (D1541)
ByMode:
    lda Mode
    cmp #MODE_WRITE
    beq ForWrite
    jmp ForRead

;; A relative file: REC; one not there is opened for writing.
;; Also: OP60 (D1541)
SetRecordSize:
    ldy FileNameStart,x
    lda CommandBuffer,y
    sta RecordSize
    lda FileNameTrack
    bne SetMode
    lda #MODE_WRITE
    sta Mode
    bne SetMode

;; A pattern or an existing file needs @; a file not closed has its entry deleted first.
;; Also: OP75 (D1541)
ForWrite:
    lda FileNamePattern
    and #$80
    tax
    bne Exists
    lda #$20
    bit FileNamePattern
    beq CheckExists
    jsr Directory::DeleteEntry
    jmp OpenWrite

;; A closed entry: there, it needs @; not there, it is written.
;; Also: OP80 (D1541)
CheckExists:
    lda FileNameTrack
    bne Exists
    jmp OpenWrite

;; There: error 63, FILE EXISTS, unless @; for a pattern, error 33.
;; Also: OP81 (D1541)
Exists:
    lda CommandBuffer
    cmp #'@'
    beq Replace
    txa
    bne PatternName
    lda #ERROR_FILE_EXISTS
    jmp Commands::Fail

;; Error 33, SYNTAX ERROR (a pattern).
;; Also: OP815 (D1541)
PatternName:
    lda #ERROR_INVALID_NAME
    jmp Commands::Fail

;; @: same type, not relative; a write channel, and the old entry marked for replace, with the new chain's start in
;; bytes 26-27.
;; Also: OP82 (D1541)
Replace:
    lda FileNamePattern
    and #TYPE_MASK
    cmp FileType
    bne TypeMismatch
    cmp #TYPE_RELATIVE
    beq TypeMismatch
    jsr OpenWriteChannel
    lda Channel
    sta WriteChannel
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr FindReadChannel
    lda EntryOffset
    jsr SetPointer
    ldy #$00
    lda (BufferPointer),y
    ora #$20
    sta (BufferPointer),y
    ldy #$1A
    lda Track
    sta (BufferPointer),y
    iny
    lda Sector
    sta (BufferPointer),y
    ldx WriteChannel
    lda FileNameEntrySector
    sta ChannelEntrySector,x
    lda FileNameEntryIndex
    sta ChannelEntryIndex,x
    jsr GetChannelBlock
    jsr Jobs::WriteTrackSector
    jmp OpenWrite::Finish

;; Reading: error 62, FILE NOT FOUND, if not there.
;; Also: OP90 (D1541)
ForRead:
    lda FileNameTrack
    bne Found
    lda #ERROR_FILE_NOT_FOUND
    jmp Commands::Fail

;; Unless modifying, a file not closed is error 60, WRITE FILE OPEN.
;; Also: OP100 (D1541)
Found:
    lda Mode
    cmp #MODE_MODIFY
    beq CheckType
    lda #$20
    bit FileNamePattern
    beq CheckType
    lda #ERROR_FILE_OPEN
    jmp Commands::Fail

;; Its type must be the one asked.
;; Also: OP110 (D1541)
CheckType:
    lda FileNamePattern
    and #TYPE_MASK
    cmp FileType
    beq TypeMatches

;; Error 64, FILE TYPE MISMATCH.
;; Also: OP115 (D1541)
TypeMismatch:
    lda #ERROR_FILE_TYPE_MISMATCH
    jmp Commands::Fail

;; Append (not relative): the entry marked not closed, and written.
;; Also: OP120 (D1541)
TypeMatches:
    ldy #$00
    sty SecondStreamStart
    ldx Mode
    cpx #MODE_APPEND
    bne ReadIt
    cmp #TYPE_RELATIVE
    beq TypeMismatch
    lda (BufferPointer),y
    and #$4F
    sta (BufferPointer),y
    lda SecondaryAddress
    pha
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr GetChannelBlock
    jsr Jobs::WriteTrackSector
    pla
    sta SecondaryAddress

;; <OpenRead>; append goes on to <Append>.
;; Also: OP125 (D1541)
ReadIt:
    jsr OpenRead
    lda Mode
    cmp #MODE_APPEND
    bne OpenWrite::Finish
    jsr Append
    jmp Commands::Finish
.endproc

;; OPREAD: opens a read channel on the file found (F2PTR's entry): side sector and record size from the entry (error 50,
;; RECORD NOT PRESENT, if REC differs), and DSEC/DIND its place.
;; Also: OPREAD (D1541)
.proc OpenRead
    ldy #$13
    lda (BufferPointer),y
    sta SideSectorTrack
    iny
    lda (BufferPointer),y
    sta SideSectorSector
    iny
    lda (BufferPointer),y
    ldx RecordSize
    sta RecordSize
    txa
    beq OpenChannel
    cmp RecordSize
    beq OpenChannel
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Commands::Fail

;; The channel on its first block.
;; Also: OP130 (D1541)
OpenChannel:
    ldx SecondStreamStart
    lda FileNameTrack,x
    sta Track
    lda FileNameSector,x
    sta Sector
    jsr OpenReadChannel
    ldy Channel
    ldx SecondStreamStart
    lda FileNameEntrySector,x
    sta ChannelEntrySector,y
    lda FileNameEntryIndex,x
    sta ChannelEntryIndex,y
    rts
.endproc

;; OPWRIT: opens a write channel on the drive of the name and adds its directory entry; falls into Finish.
;; Entry:
;;   Finish = A load or save keeps the file's start (PRGTRK, PRGSEC, PRGDRV) for "*"
;; Also: OPWRIT (D1541)
.proc OpenWrite
    lda FileNameDrive
    and #$01
    sta DriveNumber
    jsr OpenWriteChannel
    jsr Directory::AddEntry

;; A load or save keeps the file's start (PRGTRK, PRGSEC, PRGDRV) for "*"; the command ends (<Open> enters here).
;; Also: OPFIN (D1541)
Finish:
    lda SecondaryAddress
    cmp #$02
    bcs Done
    jsr GetBufferBlock
    lda Track
    sta LastProgramTrack
    lda DriveNumber
    sta LastProgramDrive
    lda Sector
    sta LastProgramSector

;; On to ENDSAV.
;; Also: OPF1 (D1541)
Done:
    jmp Commands::Finish::KeepBamFlag
.endproc

;; CKTM: the parameter at FILTBL,X sets MODE (MODLST: R W A M) and TYPE (TPLST: D S P U L), if it is one.
;; Also: CKTM (D1541)
.proc ParseTypeAndMode
    ldy FileNameStart,x
    lda CommandBuffer,y
    ldy #MODE_COUNT

;; Each mode letter.
;; Also: CKM1 (D1541)
Mode:
    dey
    bmi NoMode
    cmp FileModes,y
    bne Mode
    sty Files::Mode

;; Then the types.
;; Also: CKM2 (D1541)
NoMode:
    ldy #TYPE_COUNT

;; Each type letter.
;; Also: CKT1 (D1541)
Type:
    dey
    bmi Done
    cmp OpenTypeLetters,y
    bne Type
    sty FileType

;; Returns.
;; Also: CKT2 (D1541)
Done:
    rts
.endproc

;; APPEND: reads to the file's last block, then makes the channel a write channel at its end, a new block when the last
;; is full.
;; Also: APPEND (D1541)
.proc Append
    jsr Commands::GetInternalByte::AnyChannel
    lda #RELATIVE_LAST_RECORD
    jsr TestFlag
    beq Append
    jsr ReadLink
    ldx Sector
    inx
    txa
    bne SetEnd
    jsr WriteByte::NextBlock
    lda #$02

;; The pointer; CHNRDY ready to listen, LINTAB marked for writing.
;; Also: AP30 (D1541)
SetEnd:
    jsr SetPointer
    ldx Channel
    lda #CHANNEL_LISTEN
    sta ChannelStatus,x
    lda #$80
    ora Channel
    ldx SecondaryAddress
    sta SecondaryChannels,x
    rts
.endproc

;; LOADIR: <Open>'s "$" with SA 0: parses the pattern ("$", "$0", "$:name") and starts the listing (StartListing), its
;; first byte ready.
;; Also: LOADIR (D1541)
.proc LoadDirectory
    lda #Commands::LOAD_STRUCTURE
    sta CommandNumber
    lda #$00
    ldx CommandLength
    dex
    beq AllFiles
    dex
    bne ByName
    lda CommandBuffer+1
    jsr Commands::DriveDigit
    bmi ByName

;; No name: the pattern "*".
;; Also: LD02 (D1541)
AllFiles:
    sta FileNameDrive
    inc FirstStreamEnd
    inc SecondStreamEnd
    inc FileNameStart
    lda #$80
    sta FileNamePattern
    lda #'*'
    sta CommandBuffer
    sta CommandBuffer+1
    bne Search

;; A name, after a colon or not.
;; Also: LD03 (D1541)
ByName:
    jsr Commands::FindColon
    bne SetName
    jsr Commands::Prepare::ClearTables
    ldy #$03

;; FILTBL; the name parsed, on both drives.
;; Also: LD05 (D1541)
SetName:
    dey
    dey
    sty FileNameStart
    jsr Commands::ParseNames::Equals
    jsr Commands::TakeType
    jsr Commands::SetDrives

;; The drives, the header, the first match, the listing.
;; Also: LD10 (D1541)
Search:
    jsr Directory::ChooseDrives
    jsr Directory::HeaderLine
    jsr Directory::FindFile::First
    jsr Directory::StartListing
    jsr GetByte
    ldx Channel
    sta ChannelByte,x
    lda DriveNumber
    sta LastDrive
    ora #$04
    sta ChannelFileType,x
    lda #$00
    sta CommandPointer
    rts
.endproc

;; CLOSE: closes SA's channel: SA 0 the listing (and the internal channels), SA 15 every channel; after SA 2-15 the
;; command status is reported (ENDCMD, or the last error).
;; Also: CLOSE (D1541)
.proc Close
    lda #$00
    sta BamWriteDeferred
    lda SecondaryAddress
    bne NotLoad
    lda #$00
    sta ListingActive
    jsr FreeChannel

;; The internal channels.
;; Also: CLS05 (D1541)
FreeInternal:
    jmp FreeInternalChannels

;; Not SA 0: SA 15 closes every channel; others their own, SA 1 the internal ones too.
;; Also: CLS10 (D1541)
NotLoad:
    cmp #COMMAND_SECONDARY
    beq CommandChannel
    jsr CloseChannel
    lda SecondaryAddress
    cmp #$02
    bcc FreeInternal
    lda ErrorFlash
    bne Error
    jmp Commands::Finish

;; The last command's error.
;; Also: CLS15 (D1541)
Error:
    jmp Commands::Finish::NoMessage

;; SA 15: SA 14 down to 0, each closed.
;; Also: CLSALL (D1541)
CommandChannel:
    lda #COMMAND_SECONDARY-1
    sta SecondaryAddress

;; The next.
;; Also: CLS20 (D1541)
Next:
    jsr CloseChannel
    dec SecondaryAddress
    bpl Next
    lda ErrorFlash
    bne AllError
    jmp Commands::Finish

;; The last command's error.
;; Also: CLS25 (D1541)
AllError:
    jmp Commands::Finish::NoMessage
.endproc

;; CLSCHN: closes SA's channel by type: a direct one writes the BAM, a relative one goes to part 5's routines, a write
;; channel writes its last block and closes its entry; then it is freed.
;; Also: CLSCHN (D1541)
.proc CloseChannel
    ldx SecondaryAddress
    lda SecondaryChannels,x
    cmp #$FF
    bne Open
    rts

;; The channel, by type.
;; Also: CLSC28 (D1541)
Open:
    and #$0F
    sta Channel
    jsr ChannelType
    cmp #TYPE_DIRECT
    beq WriteBam
    cmp #TYPE_RELATIVE
    beq RelativeFile
    jsr FindWriteChannel
    bcs Free
    jsr CloseWrite
    jsr Directory::CloseEntry

;; BAM out (<Bam::WriteForChannel>).
;; Also: CLSC30 (D1541)
WriteBam:
    jsr Bam::WriteForChannel

;; <FreeChannel>.
;; Also: CLSC31 (D1541)
Free:
    jmp FreeChannel

;; A relative file (shared with part 5): its record written, its last side sector found, the block count worked out; a
;; changed file closes its entry. Named so as not to shadow Relative.
;; Also: CLSREL (D1541)
RelativeFile:
    jsr Flush
    jsr SwapBuffers
    jsr Relative::SeekEnd
    ldx SideSectorNumber
    stx Temporary4
    inc Temporary4
    lda #$00
    sta Temporary1
    sta Temporary2
    lda SideSectorIndex
    sec
    sbc #SIDE_SECTOR_POINTERS-2
    sta Temporary3
    jsr Relative::CountBlocks::Start
    ldx Channel
    lda Temporary1
    sta ChannelBlocks,x
    lda Temporary2
    sta ChannelBlocksHigh,x
    lda #RELATIVE_DIRTY
    jsr TestFlag
    beq RelativeDone
    jsr Directory::CloseEntry

;; <FreeChannel>.
;; Also: CLSR1 (D1541)
RelativeDone:
    jmp FreeChannel
.endproc

;; CLSWRT: writes a sequential file's last block: a file with nothing in it gets a RETURN; an empty buffer gives the
;; block before it back; the link 0 and the last byte's place, written and waited for.
;; Also: CLSWRT (D1541)
.proc CloseWrite
    ldx Channel
    lda ChannelBlocks,x
    ora ChannelBlocksHigh,x
    bne NotEmpty
    jsr GetPointer
    cmp #$02
    bne NotEmpty
    lda #CARRIAGE_RETURN
    jsr PutByte

;; The buffer's pointer.
;; Also: CLSW10 (D1541)
NotEmpty:
    jsr GetPointer
    cmp #$02
    bne SetLast
    jsr SwapBuffers
    ldx Channel
    lda ChannelBlocks,x
    bne CountDown
    dec ChannelBlocksHigh,x

;; One block fewer.
;; Also: CLSW15 (D1541)
CountDown:
    dec ChannelBlocks,x
    lda #$00

;; The last byte's place = pointer - 1.
;; Also: CLSW20 (D1541)
SetLast:
    sec
    sbc #$01
    pha
    lda #$00
    jsr SetPointer
    jsr PutByte
    pla
    jsr PutByte
    jsr WriteFileBlock
    jsr Jobs::Wait
    jmp SwapBuffers
.endproc
.endscope
.scope Directory continued

;; CLSDIR: closes a written file's directory entry (DSEC, DIND): closed bit set, block count; a replace (@) swaps in the
;; new chain and deletes the old (error 67 if it has none).
;; Also: CLSDIR (D1541)
.proc CloseEntry
    ldx Channel
    stx WriteChannel
    lda SecondaryAddress
    pha
    lda ChannelEntrySector,x
    sta Sector
    lda ChannelEntryIndex,x
    sta EntryOffset
    lda ChannelFileType,x
    and #$01
    sta DriveNumber
    lda DirectoryTrack
    sta Track
    jsr Files::GetActiveBuffer
    pha
    sta JobNumber
    jsr Jobs::ReadTrackSector
    ldy #$00
    lda BufferPages,x
    sta Work0+1
    lda EntryOffset
    sta Work0
    lda (Work0),y
    and #$20
    beq NotReplace
    jsr Files::ChannelType
    cmp #TYPE_RELATIVE
    beq SetBlocks
    lda (Work0),y
    and #$8F
    sta (Work0),y
    iny
    lda (Work0),y
    sta Track
    sty Temporary+2
    ldy #$1B
    lda (Work0),y
    pha
    dey
    lda (Work0),y
    bne Swap
    sta Track
    pla
    sta Sector
    lda #$67
    jsr Errors::Abort

;; The new chain's start into the entry, bytes 26-27 cleared, and the old chain deleted.
;; Also: CLSD4 (D1541)
Swap:
    pha
    lda #$00
    sta (Work0),y
    iny
    sta (Work0),y
    pla
    ldy Temporary+2
    sta (Work0),y
    iny
    lda (Work0),y
    sta Sector
    pla
    sta (Work0),y
    jsr Bam::FreeChain
    jmp SetBlocks

;; Closed bit set.
;; Also: CLSD5 (D1541)
NotReplace:
    lda (Work0),y
    and #$0F
    ora #$80
    sta (Work0),y

;; The block count, the sector written, SA and LINDX back.
;; Also: CLSD6 (D1541)
SetBlocks:
    ldx WriteChannel
    ldy #$1C
    lda ChannelBlocks,x
    sta (Work0),y
    iny
    lda ChannelBlocksHigh,x
    sta (Work0),y
    pla
    tax
    lda #JOB_WRITE
    ora DriveNumber
    jsr Jobs::Run::WithDrive
    pla
    sta SecondaryAddress
    jmp Files::FindWriteChannel
.endproc
.endscope
.scope Files continued

;; OPNRCH: a read channel with one buffer for TRACK and SECTOR, FILTYP from TYPE; the first block read and its first
;; byte ready. A relative file (shared with part 5) gets read-write, its record size, its side sector read and its first
;; record.
;; Entry:
;;   FirstRecord = NR = 2, the first record set up, TRACK and SECTOR back (<OpenWriteChannel> enters here for a
;; Also: OPNRCH (D1541)
.proc OpenReadChannel
    lda #$01
    jsr GetReadChannel
    jsr ResetPointers
    lda FileType
    pha
    asl
    ora DriveNumber
    sta ChannelFileType,x
    jsr StartRead
    ldx Channel
    lda Track
    bne NotLast
    lda Sector
    sta ChannelLastByte,x

;; In the last block LSTCHR = the link's sector, the last byte's place.
;; Also: OR10 (D1541)
NotLast:
    pla
    cmp #TYPE_RELATIVE
    bne Sequential
    ldy SecondaryAddress
    lda SecondaryChannels,y
    ora #$40
    sta SecondaryChannels,y
    lda RecordSize
    sta ChannelRecordSize,x
    jsr GetBuffer
    bpl SideSector
    jmp GetReadChannel::NoBuffer

;; SS = the buffer; side sector read.
;; Also: OR20 (D1541)
SideSector:
    ldx Channel
    sta ChannelSideSector,x
    ldy SideSectorTrack
    sty Track
    ldy SideSectorSector
    sty Sector
    jsr Jobs::SetHeader::ForBuffer
    jsr Relative::ReadSideSector
    jsr Jobs::Wait

;; NR = 2, the first record set up, TRACK and SECTOR back (<OpenWriteChannel> enters here for a new relative file).
;; Also: OROW (D1541)
FirstRecord:
    ldx Channel
    lda #$02
    sta ChannelNextRecord,x
    lda #$00
    jsr SetPointer
    jsr Relative::ReadByte::LoadNextRecord
    jmp GetBufferBlock

;; The first byte into CHNDAT, ready to talk.
;; Also: OR30 (D1541)
Sequential:
    jsr ReadByte
    ldx Channel
    sta ChannelByte,x
    lda #CHANNEL_TALK
    sta ChannelStatus,x
    rts
.endproc

;; INITP: both buffers' pointers 2, BUF1 inactive, NBKL/NBKH and LSTCHR 0.
;; Also: INITP (D1541)
.proc ResetPointers
    ldx Channel
    lda ChannelBuffer,x
    asl
    tay
    lda #$02
    sta a:BufferPositions,y
    lda ChannelSecondBuffer,x
    ora #$80
    sta ChannelSecondBuffer,x
    asl
    tay
    lda #$02
    sta a:BufferPositions,y
    lda #$00
    sta ChannelBlocks,x
    sta ChannelBlocksHigh,x
    lda #$00
    sta ChannelLastByte,x
    rts
.endproc

;; OPNWCH: a write channel with one buffer on the first free block, ready to listen. A relative file (shared with part
;; 5) gets its first side sector and its first block of empty records written.
;; Also: OPNWCH (D1541)
.proc OpenWriteChannel
    jsr Bam::AllocateFirst
    lda #$01
    jsr GetWriteChannel
    jsr Jobs::SetHeader
    jsr ResetPointers
    ldx Channel
    lda FileType
    pha
    asl
    ora DriveNumber
    sta ChannelFileType,x
    pla
    cmp #TYPE_RELATIVE
    beq RelativeFile
    lda #CHANNEL_LISTEN
    sta ChannelStatus,x
    rts

;; Read-write, its record size, a side-sector buffer.
;; Also: OW10 (D1541)
RelativeFile:
    ldy SecondaryAddress
    lda SecondaryChannels,y
    and #$3F
    ora #$40
    sta SecondaryChannels,y
    lda RecordSize
    sta ChannelRecordSize,x
    jsr GetBuffer
    bpl SideSector
    jmp GetReadChannel::NoBuffer

;; The side sector: its block, its header (link, last byte, number, record size, its own place), the first data block;
;; written; then empty records.
;; Also: OW20 (D1541)
SideSector:
    ldx Channel
    sta ChannelSideSector,x
    jsr Relative::ClearBuffer
    jsr Bam::AllocateNext
    lda Track
    sta SideSectorTrack
    lda Sector
    sta SideSectorSector
    ldx Channel
    lda ChannelSideSector,x
    jsr Jobs::SetHeader::ForBuffer
    lda #$00
    jsr Relative::SetSideSectorPointer
    lda #$00
    jsr Relative::PutSideSectorByte
    lda #SIDE_SECTOR_POINTERS+1
    jsr Relative::PutSideSectorByte
    lda #$00
    jsr Relative::PutSideSectorByte
    lda RecordSize
    jsr Relative::PutSideSectorByte
    lda Track
    jsr Relative::PutSideSectorByte
    lda Sector
    jsr Relative::PutSideSectorByte
    lda #SIDE_SECTOR_POINTERS
    jsr Relative::SetSideSectorPointer
    jsr GetBufferBlock
    lda Track
    jsr Relative::PutSideSectorByte
    lda Sector
    jsr Relative::PutSideSectorByte
    jsr Relative::WriteSideSector
    jsr Jobs::Wait
    lda #$02
    jsr SetPointer
    ldx Channel
    sec
    lda #$00
    sbc ChannelRecordSize,x
    sta ChannelNextRecord,x
    jsr Relative::FillEmptyRecords
    jsr Relative::EndLink
    jsr WriteBuffer
    jsr Jobs::Wait
    jsr Bam::WriteForChannel
    jmp OpenReadChannel::FirstRecord
.endproc
.endscope
.scope Relative continued

;; PUTSS: A into the side sector's buffer at its pointer (through <PutByte>); in opnchnl, but the side sectors' (addrel,
;; part 5, uses it).
;; Also: PUTSS (D1541)
.proc PutSideSectorByte
    pha
    ldx Channel
    lda ChannelSideSector,x
    jmp Files::PutByte::IntoBuffer
.endproc
.endscope
.scope Files continued

;; SCFLG: sets FILTYP's flag bits A with carry set, clears them with carry clear. Nothing calls it; kept as a routine,
;; its comment says so.
;; Also: SCFLG (D1541)
.proc SetOrClearFlag
    bcc ClearFlag
.endproc

;; SETFLG: sets bits A in the channel's FILTYP (the relative files' flags).
;; Also: SETFLG (D1541)
.proc SetFlag
    ldx Channel
    ora ChannelFileType,x
    bne ClearFlag::Store
.endproc

;; CLRFLG: clears bits A in the channel's FILTYP.
;; Entry:
;;   Store = FILTYP = A (<SetFlag> ends here)
;; Also: CLRFLG (D1541)
.proc ClearFlag
    ldx Channel
    eor #$FF
    and ChannelFileType,x

;; FILTYP = A (<SetFlag> ends here).
;; Also: CLRF10 (D1541)
Store:
    sta ChannelFileType,x
    rts
.endproc

;; TSTFLG: A = the channel's FILTYP and A; Z set when the bits are clear.
;; Also: TSTFLG (D1541)
.proc TestFlag
    ldx Channel
    and ChannelFileType,x
    rts
.endproc

;; TSTWRT: Z set when the active buffer's last job was a write.
;; Also: TSTWRT (D1541)
.proc TestWriteJob
    jsr GetActiveBuffer
    tax
    lda LastJobs,x
    and #$F0
    cmp #$90
    rts
.endproc

;; TSTCHN: carry clear when a channel (SA 0-15) has the entry found open: the same drive and directory place (DSEC,
;; DIND) as ENTFND's; X = ENTFND, Y = the channel.
;; Also: TSTCHN (D1541)
.proc TestEntryOpen
    ldx #$00

;; Each SA.
;; Also: TSTC20 (D1541)
Next:
    stx Temporary+2
    lda SecondaryChannels,x
    cmp #$FF
    bne Compare

;; Not it: the next.
;; Also: TSTC30 (D1541)
Skip:
    ldx Temporary+2
    inx
    cpx #LAST_SECONDARY-2
    bcc Next
    rts

;; Drive, DSEC and DIND against the entry's.
;; Also: TSTC40 (D1541)
Compare:
    stx Temporary+2
    and #$3F
    tay
    lda a:ChannelFileType,y
    and #$01
    sta Temporary+1
    ldx EntryFound
    lda FileNameDrive,x
    and #$01
    cmp Temporary+1
    bne Skip
    lda ChannelEntrySector,y
    cmp FileNameEntrySector,x
    bne Skip
    lda ChannelEntryIndex,y
    cmp FileNameEntryIndex,x
    bne Skip
    clc
    rts
.endproc
.endscope
