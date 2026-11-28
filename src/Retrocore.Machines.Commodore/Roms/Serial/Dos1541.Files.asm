; retrocore: style=strict
; COMMODORE 1541 DOS: CHANNELS, BUFFERS, THE JOB QUEUE AND OPEN AND CLOSE ($CE0E-$DDF0)

; The relative files' arithmetic: where a record lies in its file, by multiplying and dividing.
.scope Relative continued

;; Works out where the current channel's record lies in its relative file: its block, and the side sector and entry that
;; list that block.
;;
;; The record's byte offset in the file's data (<FindOffset>) is divided by 254, the data bytes in a block: the
;; remainder, plus 2 for the block's link, is the place in the block (<BlockOffset>). The quotient, the block's number,
;; is divided by 120, the blocks a side sector lists: the quotient is the side sector (<SideSectorNumber>), and the
;; remainder, doubled and added to 16, the entry in it (<SideSectorIndex>).
;; In: Channel = the channel, ChannelRecord = the record, ChannelRecordSize = its size, RecordOffset = the byte in it
;; Out: BlockOffset, SideSectorNumber, SideSectorIndex
;; Uses: A, X, Product, Accumulator, Temporary
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

;; Multiplies out where the current channel's record starts: (record - 1) x record size + <RecordOffset>, the byte's
;; offset in the file's data. Records 0 and 1 are both the first, offset 0.
;;
;; It is a shift-and-add multiplication: each bit of the record size, low first, adds the record number, doubled once
;; for each bit passed, to the product.
;; In: Channel = the channel, ChannelRecord = the record, ChannelRecordSize = its size, RecordOffset = the byte in it
;; Out: Product = the offset, three bytes
;; Uses: A, X, Accumulator, Temporary
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

;; The record size into <Temporary>, the multiplier.
;; Also: MUL50 (D1541)
Multiply:
    lda ChannelRecordSize,x
    sta Temporary

;; Each bit of the size, low first: a 1 adds the shifted record number to <Product>.
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

;; The byte in the record is added: done.
;; Also: MUL400 (D1541)
Done:
    rts
.endproc

;; Divides <Product> by 254, the data bytes in a block: the quotient goes into <Product>, the remainder into
;; <Accumulator>+1.
;;
;; It loads the divisor and skips <DivideBy120>'s own load of 120 with a BIT, which is why <DivideBy120> must follow
;; (D-P5-Q6).
;; In: Product = the dividend, three bytes
;; Out: Product = the quotient, Accumulator+1 = the remainder
;; Uses: A, X, Accumulator, Temporary
;; Also: DIV254 (D1541)
.proc DivideBy254
    lda #$FE
    .byte OPCODE_BIT                ; skips DivideBy120's LDA #120, so the divisor stays 254
    .assert * = DivideBy120, "DivideBy254's BIT must take DivideBy120's first instruction as its operand."
.endproc

;; Divides <Product> by 120, the blocks a side sector lists, or by the 254 that <DivideBy254> has already stored: the
;; quotient goes into <Product>, the remainder into <Accumulator>+1.
;;
;; Each pass moves the dividend's whole 256s (or, for 120, its 128s) into the quotient and adds back what they were
;; short of the divisor, 2 each (or 8), until under 256 is left; the divisor is then taken off once more if it fits.
;; In: Product = the dividend, three bytes
;; Out: Product = the quotient, Accumulator+1 = the remainder
;; Uses: A, X, Accumulator, Temporary
;; Also: DIV120 (D1541)
.proc DivideBy120
    lda #$78
    sta Temporary
    ldx #$03

;; Swaps <Product> with <Accumulator>+1-3: the dividend into the accumulator.
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

;; ...a byte at a time, leaving the low byte in <Accumulator>.
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

;; Adds the step's quotient to <Product>, and makes it the leftover: times 2 for 254, times 8 for 120.
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

;; Under 256 but not under the divisor: one more in <Product>, the divisor off the remainder.
;; Also: DIV600 (D1541)
SetRemainder:
    sta Accumulator+1

;; Done.
;; Also: DIV700 (D1541)
Done:
    rts
.endproc

;; Clears <Product>'s three bytes.
;; Out: A = 0, Product = 0
;; Keeps: X, Y
;; Also: ZERRES (D1541)
.proc ClearProduct
    lda #$00
    sta Product
    sta Product+1
    sta Product+2
    rts
.endproc

;; Multiplies <Accumulator>+1 to +3 by 4, by doubling twice.
;; Out: carry = the bit shifted out of the top byte
;; Uses: A
;; Also: ACCX4 (D1541)
.proc Quadruple
    jsr Double
    ; Falls into Double.
    .assert * = Double, "Quadruple must be followed by Double."
.endproc

;; Multiplies <Accumulator>+1 to +3 by 2: clears carry, then rotates them left through it.
;; Out: carry = the bit shifted out of the top byte
;; Also: ACCX2 (D1541)
.proc Double
    clc
    ; Falls into RotateLeft.
    .assert * = RotateLeft, "Double must be followed by RotateLeft."
.endproc

;; Rotates <Accumulator>+1 to +3 left through carry, as a 24-bit shift.
;; In: carry = the bit that enters the low byte
;; Out: carry = the bit shifted out of the top byte
;; Also: ACC200 (D1541)
.proc RotateLeft
    rol Accumulator+1
    rol Accumulator+2
    rol Accumulator+3
    rts
.endproc

;; Adds <Accumulator>+1 to +3 to <Product>, a byte at a time, as a 24-bit sum.
;; Out: carry = set when the sum overflows three bytes, X = 0
;; Uses: A
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
; Channels and buffers: the order of use, double buffering, and the bytes a channel receives.
.scope Files continued

;; Starts the list of channels in order of use afresh: channels 0 to 3, and the BAM's channel last, five entries, which
;; <StealBuffer> reads.
;; Out: X = <COMMAND_CHANNEL>
;; Uses: A
;; Keeps: Y
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

;; Makes the current channel the most recently used, by moving it to the end of <LeastRecentlyUsed> and shifting the
;; others down. A channel the list does not hold resets it (<ResetUseOrder>), which ends the routine.
;; In: Channel = the channel
;; Uses: A, X, Y
;; Also: LRUUPD (D1541)
.proc MarkMostRecent
    ldy #COMMAND_CHANNEL
    ldx Channel

;; Each entry, from the end, until <Channel>'s.
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

;; Makes the current channel's other buffer the active one, and waits for that buffer's job.
;;
;; A channel with one buffer first gets a second, error 70 if none is free. The block the active buffer links to is then
;; read into the second buffer, so that it is ready, unless the buffer was last written (a file being written only
;; swaps) or the file's last block has no link. Relative files use this throughout.
;; In: Channel = the channel
;; Out: A = the job's result code
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no buffer is free for the second one
;; Keeps: Track, Sector
;; Entry:
;;   NoBuffers = Reports error 70, NO CHANNEL (<AddSecondBuffer> comes here too)
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

;; The saved track and sector are put back.
;; Also: DBL08 (D1541)
RestoreBlock:
    pla
    sta Sector
    pla
    sta Track
    jmp Wait

;; No link: <Track> and <Sector> back, and the swap alone.
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

;; Marks the current channel as used and gives it an inactive buffer if it has none: <SwapBuffers> without the swap.
;; Relative files (<Relative::AddBlocks>) use it.
;; In: Channel = the channel
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no buffer is free
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

;; Swaps which of the current channel's two buffers is the active one, by flipping the inactive flag, bit 7, of both
;; buffer numbers.
;; In: Channel = the channel
;; Out: X = the channel
;; Uses: A
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

;; Takes a byte for the internal write channel, secondary address 18, and turns the drive's LED on. A relative file's
;; overflow flag is cleared first, which the copy command relies on.
;; In: DataByte = the byte
;; Uses: A, X, Y, SecondaryAddress
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

;; On to <AcceptByte>'s command or file path, by secondary address.
;; Also: PBYTE (D1541)
ToChannel:
    lda SecondaryAddress
    cmp #COMMAND_SECONDARY
    beq AcceptByte::ToCommand
    bne AcceptByte::ToFile
.endproc

;; Takes the byte the bus has received for the current secondary address. Bytes for secondary address 15 go into the
;; command buffer, until it is full, and the last of them (<MoreBytes> clear) tells the main loop a command is waiting.
;; Other bytes go into the file: a sequential file's, a relative file's record or a direct channel's buffer.
;; In: DataByte = the byte, SecondaryCommand = the secondary address as the bus received it, MoreBytes = 0 for the last
;;   byte
;; Entry:
;;   ToFile = A file's byte, by type (<AcceptInternalByte> enters here)
;;   ToCommand = Into the command buffer, unless it is full (<AcceptInternalByte> enters here)
;; Uses: A, X, Y
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

;; Relative: <Relative::WriteByte>.
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

;; <MoreBytes> is not yet 0: more bytes are to come.
;; Also: L50 (D1541)
CheckEnd:
    lda MoreBytes
    beq CommandReady
    rts

;; The last byte: <CommandWaiting> up, a command to run.
;; Also: L45 (D1541)
CommandReady:
    inc CommandWaiting
    rts
.endproc

;; Stores a byte in the active buffer at its pointer, and moves the pointer on.
;; In: A = the byte
;; Out: zero = set when the pointer wrapped to 0, the buffer being full, X = twice the buffer's number
;; Errors: error 61, <ERROR_FILE_NOT_OPEN>, when the channel has no active buffer
;; Entry:
;;   IntoBuffer = Stores the byte on the stack into buffer A (<Relative::PutSideSectorByte>, the side sector's writer,
;;     enters here)
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
; The I command, which the directory's initialize does the work of.
.scope Commands continued

;; The I command, in the command table: parses the drive number and initializes that drive, which ends the command.
;; Also: INTDRV (D1541)
.proc Initialize
    jsr ParseDriveOnly
    jsr Bam::InitializeDrive
    jmp Finish
.endproc
.endscope
; Initializing a drive's BAM: the seek that reads the disk's ID, and the count of free blocks.
.scope Bam continued

;; Gives the BAM its buffer if it has none, and seeks to the directory track, which reads the disk's ID into
;; <LastHeader>.
;; Out: A = the job's result code
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no buffer is free
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

;; The buffer becomes the job, with the header 18/0, and the seek is run.
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

;; Initializes the current drive: forgets its BAM images, closes its channels, seeks the directory track and keeps the
;; disk's ID, reads the BAM, notes its DOS version, and clears the drive's changed and not-ready flags.
;; In: DriveNumber = the drive
;; Errors: any a job's error gives
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
    ; Falls into CountFreeBlocks.
    .assert * = CountFreeBlocks, "InitializeDrive must be followed by CountFreeBlocks."
.endproc

;; Counts the blocks the BAM shows free, leaving out the directory track's, into <FreeBlocks> and <FreeBlocksHigh> for
;; the drive. <Bam::BuildEmpty> jumps here after it builds a BAM.
;; In: DriveNumber = the drive
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
; Reading and writing file blocks, and finding and moving the bytes of a secondary address's channel.
.scope Files continued

;; Reads the block at <Track> and <Sector> into the active buffer, waits for it, and leaves its link in <Track> and
;; <Sector>.
;; In: Track, Sector = the block
;; Out: Track, Sector = the block's link; Track is 0 for the file's last block
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

;; Reads a file's block as <StartRead> does and, when the file goes on, starts the read of its next block into a second
;; buffer. Relative files use it.
;; In: Track, Sector = the block
;; Out: Track, Sector = the first block's link
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

;; Starts a read job on the active buffer. Its header, the track and sector, is the caller's to set already, unlike
;; <ReadBlock>'s. The buffer's pointer is zeroed.
;; Out: X = the buffer
;; Also: RDBUF (D1541)
.proc ReadFileBlock
    lda #JOB_READ
    bne WriteFileBlock::Start
.endproc

;; Starts a write job on the active buffer. Its header is the caller's to set already, unlike <WriteBlock>'s. The
;; buffer's pointer is zeroed and, for a channel of a type below relative, the channel's block count goes up.
;; Out: X = the buffer
;; Entry:
;;   Start = Starts the job in A on the active buffer, with the same effects (<ReadFileBlock> enters here)
;; Also: WRTBUF (D1541)
.proc WriteFileBlock
    lda #JOB_WRITE

;; Starts the job in A on the active buffer and zeroes its pointer; for types below relative the channel's block count
;; (<ChannelBlocks>) goes up. X = the buffer (<ReadFileBlock> enters here).
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

;; Finds the channel a secondary address reads: its number goes into <Channel>. Secondary address 15 reads the error
;; channel; addresses above 18 are taken modulo 16.
;; In: SecondaryAddress = the secondary address
;; Out: carry = set when the address has no read channel; clear, with Channel and X = the channel, when it has
;; Uses: A
;; Also: FNDRCH (D1541)
.proc FindReadChannel
    lda SecondaryAddress
    cmp #LAST_SECONDARY+1
    bcc InRange
    and #$0F

;; secondary address 15 reads the error channel (secondary address 16).
;; Also: FNDC20 (D1541)
InRange:
    cmp #COMMAND_SECONDARY
    bne Lookup
    lda #MESSAGE_SECONDARY

;; The secondary address's entry in <SecondaryChannels>: bit 7 is clear for a read channel.
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

;; Finds the channel a secondary address writes: bit 7 of its entry in <SecondaryChannels> marks a write channel, and
;; bit 6 a relative file's, which is written too. Addresses above 18 are taken modulo 16.
;; In: SecondaryAddress = the secondary address
;; Out: carry = set when the address has no write channel; clear, with Channel and X = the channel, when it has
;; Uses: A, Y
;; Also: FNDWCH (D1541)
.proc FindWriteChannel
    lda SecondaryAddress
    cmp #LAST_SECONDARY+1
    bcc Lookup
    and #$0F

;; The secondary address's entry in <SecondaryChannels>, by its two top bits.
;; Also: FNDW13 (D1541)
Lookup:
    tax
    lda SecondaryChannels,x
    tay
    asl
    bcc ReadOnly
    bmi None

;; The channel is found: <Channel> = it, and carry is clear.
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

;; Gets the current channel's file type, and compares it with the relative type.
;; In: Channel = the channel
;; Out: A = the file type, X = the channel, zero = set for relative, carry = set for relative or above
;; Also: TYPFIL (D1541)
.proc ChannelType
    ldx Channel
    lda ChannelFileType,x
    lsr
    and #$07
    cmp #TYPE_RELATIVE
    rts
.endproc

;; Gets the indexes the byte routines use: the active buffer's place in the pointer table, and the channel. The relative
;; files' routines use it too.
;; In: Channel = the channel
;; Out: X = twice the active buffer's number, Y = the channel
;; Uses: A
;; Also: GETPRE (D1541)
.proc BufferIndexes
    jsr GetActiveBuffer
    asl
    tax
    ldy Channel
    rts
.endproc

;; Takes the next byte of the active buffer, and moves its pointer on. In a file's last block, whose last byte's place
;; is known (<ChannelLastByte>), the pointer goes to 0 after that byte, so the zero flag marks it as the buffer's end
;; does.
;; In: Channel = the channel
;; Out: A = the byte, zero = set when the pointer reached 0: the buffer's last byte, or the file's, X = twice the
;;   buffer's number, Y = the channel
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

;; No <ChannelLastByte>: Z set when the pointer wraps.
;; Also: GETB1 (D1541)
NotLastBlock:
    lda (BufferPositions,x)
    inc BufferPositions,x
    rts
.endproc

;; Reads a sequential file's next byte. At a buffer's end the next block becomes the active one and the block after it
;; is started reading; with the file's last byte the channel is marked as ready to send it with EOI.
;; In: Channel = the channel
;; Out: A = the byte
;; Errors: any a read job's error gives
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

;; Link track 0: <ChannelLastByte> = the last byte's place.
;; Also: RD4 (D1541)
LastBlock:
    jsr GetByte
    ldy Channel
    sta ChannelLastByte,y
    lda DataByte
    rts
.endproc

;; Writes a byte into a file. When the buffer fills, it goes out: a next block is allocated, linked and started writing.
;; In: A = the byte
;; Errors: error 72, <ERROR_DISK_FULL>, when no block is free
;; Entry:
;;   NextBlock = Allocates the next block, links the full buffer to it, starts its write and swaps to the other
;;     buffer with its pointer at 2 (<Append> enters here)
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

;; Moves the active buffer's pointer on, and <BufferPointer> with it.
;; In: A = the amount
;; Out: A = the new pointer, X = twice the buffer's number
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

;; Sets the current drive to the one the active buffer's last job was for.
;; Out: DriveNumber = the drive, X = the buffer
;; Uses: A
;; Also: SETDRN (D1541)
.proc SetDriveFromBuffer
    jsr GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    sta DriveNumber
    rts
.endproc

;; Allocates a write channel: <GetReadChannel> with carry set.
;; In: A = the number of buffers wanted, 0 to 2
;; Errors: error 70, <ERROR_NO_CHANNEL>
;; Also: GETWCH (D1541)
.proc GetWriteChannel
    sec
    bcs GetReadChannel::Allocate
.endproc

;; Frees the secondary address's old channel and gives it a new one, with the buffers asked for. <SecondaryChannels>
;; records it, with bit 7 set for a write channel, and the channel's buffer slots are emptied.
;; In: A = the number of buffers wanted, 0 to 2, SecondaryAddress = the secondary address, carry = set for a write
;;   channel
;; Out: Channel = the channel
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no channel or buffer is free; the buffers taken are released
;; Entry:
;;   Allocate = Carry set for a write channel (<GetWriteChannel> enters here)
;;   NoBuffer = Releases the buffers and reports error 70 (<OpenReadChannel> and <OpenWriteChannel> come here when they
;;     have no buffer for the side sector)
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

;; The secondary address's entry in <SecondaryChannels> = the channel.
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

;; The first buffer is the channel's <ChannelBuffer>; the second, if wanted, comes next.
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

;; Frees a secondary address's channel, except for 15's, which is never freed: its entry is cleared, its status set not
;; ready, its buffers released and its place marked free in <FreeChannels>.
;; In: SecondaryAddress = the secondary address
;; Uses: A, X, Channel
;; Also: FRECHN (D1541)
.proc FreeChannel
    lda SecondaryAddress
    cmp #COMMAND_SECONDARY
    bne Free
    rts

;; Releases the channel, whether it was a read or a write channel.
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

;; The channel's bit in <FreeChannels>.
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

;; Frees the current channel's buffers, its two data buffers and its side sector's, and empties their slots.
;; In: Channel = the channel
;; Uses: A, X, Y
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

;; The second buffer.
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

;; Takes a free buffer, looking in the second byte of <BuffersInUse> first, then the first, and stealing an inactive one
;; (<StealBuffer>) when none is free. Once the buffer's last job is done it is given the current drive's, and its
;; pointer is set to 2.
;; In: DriveNumber = the drive
;; Out: A, X = the buffer's number, negative (A = $FF) when there is none
;; Keeps: Y
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

;; Finds the first free buffer in a byte of <BuffersInUse> and marks it used.
;; In: Y = 0 for buffers 0 to 7, 1 for buffers 8 to 15
;; Out: X = the buffer's number, negative when the byte has none free
;; Uses: A, Y
;; Entry:
;;   Return = The return, which <FreeInactiveBuffer> ends at when there is nothing to free
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

;; Frees the current channel's inactive buffer, if it has one, which empties its slot. Relative files use it.
;; In: Channel = the channel
;; Uses: A, X, Y
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
    ; Falls into FreeBuffer.
    .assert * = FreeBuffer, "FreeInactiveBuffer must be followed by FreeBuffer."
.endproc

;; Marks a buffer free in <BuffersInUse>, by rotating its 16 bits once round and clearing the buffer's on the way.
;; In: A = the buffer's number
;; Uses: A, X, Y
;; Also: FREBUF (D1541)
.proc FreeBuffer
    and #$0F
    tay
    iny
    ldx #$10

;; Rotates <BuffersInUse>'s 16 bits once round, the buffer's bit cleared on the way.
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

;; Frees the channels of secondary addresses 14 down to 1. The NEW command uses it.
;; Uses: A, X, Y, SecondaryAddress
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

;; Frees every channel, of secondary addresses 14 down to 0, whose active buffer's last job was for the current drive.
;; In: DriveNumber = the drive
;; Uses: A, X, Y, SecondaryAddress, Channel
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

;; Takes an inactive buffer from a channel, trying the least recently used channels first (<LeastRecentlyUsed>). Only a
;; buffer whose job finished without an error is taken; its slot is emptied.
;; Out: A = the buffer's number, negative (A = $FF) when there is none
;; Keeps: Temporary
;; Also: STLBUF (D1541)
.proc StealBuffer
    lda Temporary
    pha
    ldy #$00

;; Each channel's <ChannelBuffer>.
;; Also: STL05 (D1541)
EachChannel:
    ldx LeastRecentlyUsed,y
    lda ChannelBuffer,x
    bpl OtherSlot
    cmp #$FF
    bne Inactive

;; Its <ChannelSecondBuffer>.
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

;; The next in <LeastRecentlyUsed>.
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

;; Finds the first free channel in <FreeChannels> and marks it used.
;; Out: A = the channel
;; Errors: error 70, <ERROR_NO_CHANNEL>, when all are used
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

;; Takes the next byte of a secondary address's read channel, with the drive's LED on. The copy command uses it.
;; In: SecondaryAddress = the secondary address
;; Out: A = the byte
;; Also: GBYTE (D1541)
.proc ReadChannelByte
    jsr FindReadChannel
    jsr TurnOnActivityLed
    jsr NextByte
    ldx Channel
    lda ChannelByte,x
    rts
.endproc

;; Makes the current channel's next byte ready for the bus to send: <ChannelByte> gets it and <ChannelStatus> says it is
;; ready. A relative file's comes from its record, the error channel's from the message, a directory listing's from the
;; listing, and a file's from its block, or the direct channel's buffer. After the last byte only a direct channel goes
;; on.
;; In: Channel = the channel, SecondaryAddress = the secondary address
;; Entry:
;;   NextRandom = Moves the pointer on, then takes the byte (the block commands enter here)
;;   RandomAtPointer = Takes the byte at the pointer, and marks it the last at the channel's last byte (<AcceptByte> and
;;     the block commands enter here)
;;   ErrorEnd = The message's last byte went: the pointer goes back before the message, so that a RETURN comes next
;;   ErrorReady = Marks the channel ready to talk (the memory-read command enters here)
;; Also: GET (D1541)
.proc NextByte
    ldx Channel
    jsr ChannelType
    bne NotRelative
    jmp Relative::ReadByte

;; Not relative: secondary address 15 is the error channel.
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

;; The last byte went with EOI: the channel is marked not ready.
;; Also: GET0 (D1541)
NotReady:
    lda #CHANNEL_NOT_READY
    sta ChannelStatus,x
    rts

;; Not after EOI: secondary address 0, a load, is the listing or the file; others by type.
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

;; The byte at the pointer goes into <ChannelByte>, and the channel is marked ready, with EOI at <ChannelLastByte>
;; (<AcceptByte> and the block commands enter here).
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

;; A sequential file's byte, through <ReadByte>.
;; Also: SEQGET (D1541)
Sequential:
    jsr ReadByte

;; The byte in A goes into <ChannelByte>.
;; Also: GET3 (D1541)
Store:
    ldx Channel
    sta ChannelByte,x
    rts

;; With the directory listing active, the listing's next byte.
;; Also: GET6 (D1541)
Load:
    lda ListingActive
    beq Sequential
    jsr Directory::NextListingByte
    jmp Store

;; The error channel: after the message's last byte comes a RETURN with EOI, and the error is reset to 00, OK.
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

;; The message's last byte went: the pointer goes back before <ErrorBuffer>, so a RETURN comes next (the memory-read
;; command enters here).
;; Also: GE15 (D1541)
ErrorEnd:
    lda #<ErrorBuffer-1
    jsr SetPointer
    lda #>ErrorBuffer
    sta BufferPositions+1,x

;; The channel is marked ready to talk (the memory-read command enters here).
;; Also: GE20 (D1541)
ErrorReady:
    lda #CHANNEL_TALK

;; The error channel's <ChannelStatus> and <ChannelByte>.
;; Also: GE30 (D1541)
SetError:
    sta ChannelStatus+MESSAGE_CHANNEL
    lda DataByte
    sta ChannelByte+MESSAGE_CHANNEL
    rts
.endproc

;; Moves to the file's next block when the active buffer links to one, through <ReadByte>.
;; Out: zero = set when there is no next block
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
; Reading and writing a given track and sector.
.scope Jobs continued

;; Reads <Track> and <Sector> into the buffer of <JobNumber>, and waits for it.
;; In: JobNumber = the job, Track, Sector = the block
;; Also: DRTRD (D1541)
.proc ReadTrackSector
    lda #JOB_READ
    bne WriteTrackSector::Start
.endproc

;; Writes the buffer of <JobNumber> to <Track> and <Sector>, and waits for it.
;; In: JobNumber = the job, Track, Sector = the block
;; Entry:
;;   Start = Runs the job in A for the current drive, with its header set, and waits (<ReadTrackSector> enters here)
;; Also: DRTWRT (D1541)
.proc WriteTrackSector
    lda #JOB_WRITE

;; The job for <DriveNumber>, its header set, run and waited for; <ReadTrackSector> enters here.
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
; Opening the DOS's own internal channels.
.scope Files continued

;; Opens the internal read channel, secondary address 17, on <Track> and <Sector> as a file, and sets its pointer to 2.
;; In: Track, Sector = the first block
;; Entry:
;;   WithType = Opens it as a file of the type in A (the utility loader enters here)
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

;; Opens the internal write channel, secondary address 18.
;; Also: OPNIWR (D1541)
.proc OpenInternalWrite
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jmp OpenWriteChannel
.endproc
.endscope
; Adding a block to the directory.
.scope Directory continued

;; Adds a block to the directory: allocates the next block, three sectors on from the last on track 18, links the
;; current one to it and writes it, then clears the buffer for the new block, whose link is 0 and $FF.
;; Errors: error 72, DISK FULL, when no block is free
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
; Buffer pointers, and freeing the internal channels.
.scope Files continued

;; Sets the active buffer's pointer, and <BufferPointer> with it.
;; In: A = the pointer
;; Out: A = the pointer, X = twice the buffer's number
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

;; Frees the internal read and write channels, secondary addresses 17 and 18.
;; Uses: A, X, Y, SecondaryAddress
;; Also: FREICH (D1541)
.proc FreeInternalChannels
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr FreeChannel
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jmp FreeChannel
.endproc

;; Sets <BufferPointer> to the active buffer's pointer.
;; Out: A = its low byte, X = twice the buffer's number
;; Entry:
;;   OfBuffer = The same for the buffer in A (the side sector routines enter here)
;; Also: GETPNT (D1541)
.proc GetPointer
    jsr GetActiveBuffer

;; Loads the pointer of the buffer in A, not the active buffer's: <BufferPointer> gets its position and its page.
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

;; Reads a byte of the active buffer, without moving its pointer.
;; In: A = the byte's place in the buffer
;; Out: A = the byte, X = the buffer, Y = 0
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
; The job queue: checking and starting a job, waiting for it, and recovering from its errors.
.scope Jobs continued

;; Starts job X's command <JobCommand> on the drive of that job's last job. It sets the command's drive bit and falls
;; into <Start>.
;; In: X = the job, JobCommand = the command
;; Also: SETLJB (D1541)
.proc StartOnLastDrive
    lda LastJobs,x
    and #$01
    ora JobCommand
    ; Falls into Start.
    .assert * = Start, "StartOnLastDrive must be followed by Start."
.endproc

;; Starts a job: checks its header against the disk and queues its command. The header's track must be 1 to the last
;; track, and its sector below the track's count; a write's disk must also be of this DOS's version, or none is read
;; yet. <JobCommand> holds the header's sector while it is checked.
;; In: A = the command, with its drive bit, X = the job
;; Out: JobNumber = the job
;; Errors: error 66, <ERROR_ILLEGAL_TRACK_SECTOR>, for a bad header; error 73, <ERROR_DOS_VERSION>, for a write to
;;   a disk of another version
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

;; A = drive 1's <DiskVersion>.
;; Also: SJB2 (D1541)
SecondDriveVersion:
    lda DiskVersion+1

;; A version of 0 (none read yet) passes; any other must be <FormatType>.
;; Also: SJB3 (D1541)
CheckVersion:
    beq CheckSector
    cmp FormatType
    bne VersionError

;; The sector must be below the track's the track's sector count.
;; Also: SJB4 (D1541)
CheckSector:
    txa
    jsr SectorsOnTrack
    cmp JobCommand
    beq TrackSectorError
    bcs Queue
    ; Falls into TrackSectorError.
    .assert * = TrackSectorError, "Start must be followed by TrackSectorError."
.endproc

;; Reports error 66, ILLEGAL TRACK OR SECTOR, for the job's header, which goes into <Track> and <Sector> for the
;; message. It ends in <Errors::Abort>, which does not return.
;; Errors: error 66, <ERROR_ILLEGAL_TRACK_SECTOR>
;; Entry:
;;   Report = Reports error 66 with <Track> and <Sector> as they are
;; Also: TSERR (D1541)
.proc TrackSectorError
    jsr LoadTrackSector

;; Reports 66 with <Track> and <Sector> as they are; <CheckTrackSector> branches here.
;; Also: TSER1 (D1541)
Report:
    lda #ERROR_ILLEGAL_TRACK_SECTOR
    jmp Errors::Abort
.endproc

;; Sets <Track> and <Sector> to the header of <JobNumber>'s job, a track and a sector byte per job.
;; In: JobNumber = the job
;; Out: Track, Sector = its header
;; Uses: A, X
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

;; Checks <Track>, 1 to the last track, and <Sector>, below the track's sector count, and returns if they are good.
;; In: Track, Sector = the block
;; Errors: error 66, <ERROR_ILLEGAL_TRACK_SECTOR>
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

;; Reports error 73 (the disk's DOS version is not this one's) for the job's header. NEW jumps here too.
;; Errors: error 73, <ERROR_DOS_VERSION>
;; Also: VNERR (D1541)
.proc VersionError
    jsr LoadTrackSector
    lda #ERROR_DOS_VERSION
    jmp Errors::Abort
.endproc

;; The tail of <Start>, reached by a branch with the command on the stack: puts the command in <JobCommand> and for job
;; <JobNumber> in the job queue and in its last-job entry, which starts the job.
;; In: JobNumber = the job, the stack = the command
;; Also: SJB1 (D1541)
.proc Queue
    ldx JobNumber
    pla
    sta JobCommand
    sta JobQueue,x
    sta LastJobs,x
    rts
.endproc

;; Reads the job's sector and waits, by branching to <Run> with the read command.
;; In: JobNumber = the job, Track, Sector = the block
;; Also: DOREAD (D1541)
.proc Read
    lda #JOB_READ
    bne Run
.endproc

;; Writes the job's sector and waits: <Run> with the write command.
;; In: JobNumber = the job, Track, Sector = the block
;; Also: DOWRIT (D1541)
.proc Write
    lda #JOB_WRITE
    ; Falls into Run.
    .assert * = Run, "Write must be followed by Run."
.endproc

;; Runs the job command in A, for the current drive and <JobNumber>'s job, and waits for it. It falls into <Wait>.
;; In: A = the command, without its drive bit, DriveNumber = the drive, JobNumber = the job
;; Out: A = the job's result code
;; Errors: the job's error, reported through <Errors::JobError>, unless <JobErrorReturn> bit 7 asks for it returned
;; Entry:
;;   WithDrive = Runs command A, which has its drive bit already, for job X
;;   Repeat = Runs <JobCommand> again for job X, after the caller has set a new header
;; Also: DOJOB (D1541)
.proc Run
    ora DriveNumber
    ldx JobNumber

;; Runs command A, which already has its drive bit, for job X.
;; Also: DOIT (D1541)
WithDrive:
    sta JobCommand

;; Runs <JobCommand> again for job X, after a caller has set a new header.
;; Also: DOIT2 (D1541)
Repeat:
    lda JobCommand
    jsr Start
    ; Falls into Wait.
    .assert * = Wait, "Run must be followed by Wait."
.endproc

;; Waits for job X to finish, recovering from its errors, and then clears <JobErrorReturn>.
;; In: X = the job
;; Out: A = the job's result code
;; Errors: the job's error, reported through <Errors::JobError>, unless <JobErrorReturn> bit 7 asks for it returned
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

;; Tests job X once, recovering from its error if it has one.
;; In: X = the job
;; Out: carry = set while the job is still running, clear when it is done, A = the job's result code
;; Errors: the job's error, reported through <Errors::JobError>, unless <JobErrorReturn> bit 7 asks for it returned
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

;; Write protect (8), ID mismatch (11) and no drive (15) are not retried: returned if <JobErrorReturn> asks, else
;; reported.
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

;; Error recovery: selects the job's drive and its LED mask, and retries the job <Retries> times.
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

;; Keeps the job's type, and turns a write into a sector seek (<JOB_SECTOR_SEEK>) for the rest of the recovery, so
;; nothing is written while the head is off.
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

;; Unless <Retries> bit 6 turns them off, retries with the head offset by each entry of <RecoveryOffsets> in turn.
;; Also: REC0 (D1541)
TryOffsets:
    bit Retries
    bvs CheckBump
    lda #$00
    sta OffsetIndex
    sta TotalOffset

;; Moves the head by the next offset, keeps the total in <TotalOffset>, and retries; a 0 ends the table.
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

;; <Retries> bit 7 clear: tries a bump.
;; Also: REC5 (D1541)
CheckBump:
    bit Retries
    bpl Bump

;; Recovery failed: restores a write job in <LastJobs>.
;; Also: QUIT (D1541)
Fail:
    pla
    cmp #JOB_WRITE
    bne ReportError
    ora DriveNumber
    sta LastJobs,x

;; Reports the job's code as a DOS error through <Errors::JobError>, which does not return.
;; Also: QUIT2 (D1541)
ReportError:
    lda JobQueue,x
    jsr Errors::JobError

;; Returns the error if <JobErrorReturn> asks; else queues a bump on the drive.
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

;; Restores <DriveNumber> and Y; A = the job's code, carry clear.
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

;; Moves the head by half-tracks, one <StepHead> at a time: inward for a positive count, outward for a negative one (the
;; listing's comments have the directions the other way).
;; In: A = the half-tracks, signed
;; Out: A = 0
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

;; Asks the controller for one half-track step, by putting it in the drive's <StepRequest> for the end of the pass to
;; act on, and waits until the controller has taken it.
;; In: Y = 1 to step in, $FF to step out
;; Keeps: A
;; Also: MOVHED (D1541)
.proc StepHead
    pha
    tya
    ldy DriveNumber
    sta StepRequest,y

;; Waits for the controller to change <StepRequest>.
;; Also: MH10 (D1541)
Wait:
    cmp StepRequest,y
    beq Wait
    lda #$00
    sta StepRequest,y
    pla
    rts
.endproc

;; Requeues the job's last command up to <Retries> bits 0 to 5 times, flashing the drive's LED on each try, until it
;; works, and leaves the LED on.
;; In: X = the job
;; Out: A = the job's result code
;; Uses: Y
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

;; Sets the active buffer's job header to <Track> and <Sector>.
;; In: Track, Sector = the block
;; Out: X = twice the current drive
;; Entry:
;;   ForBuffer = The same for buffer A. It leaves X = twice <DriveNumber>, what is left of the disk ID copy the 4/12
;;     patch commented out
;; Also: SETHDR (D1541)
.proc SetHeader
    jsr Files::GetActiveBuffer

;; The same for buffer A. Leaves X = <DriveNumber> x 2, which is what is left of the ID copy the 4/12 patch commented
;; out.
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
; Writing a new file's directory entry.
.scope Directory continued

;; Writes the directory entry for the file being opened, in the first deleted slot or, when there is none, in a new
;; block: its type, first track and sector, name, side sector and record size. The file name table and the channel then
;; hold its place in the directory.
;; In: Track, Sector = the file's first block, FileType = its type, SecondaryAddress = its secondary address, Channel =
;;   its channel
;; Out: FileNameTrack, FileNameSector = the file's first block, FileNameEntrySector, FileNameEntryIndex, and the
;;   channel's ChannelEntrySector, ChannelEntryIndex = the entry's place
;; Keeps: Channel, SecondaryAddress
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

;; The entry at <FreeEntryIndex>.
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
; OPEN and CLOSE.
.scope Files continued

;; OPEN, for a secondary address other than 15: takes the name sent, looks it up in the directory and opens a channel
;; for it, by the mode and type the name gives. "*" loads the last program, "$" the directory and "#" a direct channel;
;; anything else is read, write, replace (with "@"), append or modify. The command ends through <Commands::Finish>.
;; In: SecondaryAddress = the secondary address, CommandBuffer = the name, as sent
;; Errors: error 30, <ERROR_SYNTAX>, for more than a drive before the colon; error 33, <ERROR_INVALID_NAME>, for a
;;   pattern to write; error 50, <ERROR_RECORD_NOT_PRESENT>, for a record size that differs; error 60,
;;   <ERROR_FILE_OPEN>, for a file not closed; error 62, <ERROR_FILE_NOT_FOUND>, for a file to read that is not there;
;;   error 63, <ERROR_FILE_EXISTS>; error 64, <ERROR_FILE_TYPE_MISMATCH>; and any the directory search or the channel's
;;   opening gives
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

;; Stores the file type in A, and ends the command. (The store indexes with Y, which the read leaves as the channel; the
;; code loads X, which has the channel too.)
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

;; Not secondary address 0: the directory as a sequential file.
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

;; The name is parsed into the file name tables and looked up; then the type and mode, if given.
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

;; secondary address back; secondary address 0 or 1, a load or save, is read or write mode, program type.
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

;; A relative file: its record size follows; one that is not there is opened for writing.
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

;; Opens the file for reading; append then goes on to <Append>.
;; Also: OP125 (D1541)
ReadIt:
    jsr OpenRead
    lda Mode
    cmp #MODE_APPEND
    bne OpenWrite::Finish
    jsr Append
    jmp Commands::Finish
.endproc

;; Opens a read channel on the file the search found: the side sector and record size from its directory entry, and the
;; entry's place for the channel. A record size given that differs from the entry's is an error.
;; In: BufferPointer = the entry, SecondStreamStart = the name's place in the file name tables, RecordSize = the size
;;   asked, 0 for none
;; Errors: error 50, <ERROR_RECORD_NOT_PRESENT>, when the record size differs
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

;; Opens a write channel on the drive of the name, and adds its directory entry; it falls into the end of <Open>.
;; Entry:
;;   Finish = A load or save keeps the file's start, for "*" to load the last program, and the command ends (<Open>
;;     enters here)
;; Also: OPWRIT (D1541)
.proc OpenWrite
    lda FileNameDrive
    and #$01
    sta DriveNumber
    jsr OpenWriteChannel
    jsr Directory::AddEntry

;; A load or save keeps the file's start (<LastProgramTrack>, <LastProgramSector>, <LastProgramDrive>) for "*"; the
;; command ends (<Open> enters here).
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

;; On to the command's end.
;; Also: OPF1 (D1541)
Done:
    jmp Commands::Finish::KeepBamFlag
.endproc

;; Reads one parameter of the name, after its first, as a mode letter (R, W, A, M) or a file type letter, and sets the
;; mode or the type if it is one.
;; In: X = the parameter's place in the file name tables
;; Out: Files::Mode, FileType = set when the letter is one
;; Uses: A, Y
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

;; Prepares to append to a file: reads on to its last block, then turns the channel into a write channel at the file's
;; end, in a new block if the last is full.
;; Errors: any a read job's error gives
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

;; The pointer; <ChannelStatus> ready to listen, <SecondaryChannels> marked for writing.
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

;; Opens the directory for a load, secondary address 0: parses the pattern ("$", "$0" or "$:name") and starts the
;; listing, leaving its first byte ready.
;; In: CommandBuffer = the command, CommandLength = its length
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

;; The name is parsed into the file name tables, for both drives.
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

;; CLOSE: closes a secondary address's channel. Address 0 closes the directory listing and the internal channels, 1 the
;; internal channels too, and 15 every channel. Of those from 2 up, the command's status is reported at the end: the
;; last error, or the command's end. The command ends through <Commands::Finish>.
;; In: SecondaryAddress = the secondary address
;; Errors: any a write channel's last block gives
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

;; Not secondary address 0: secondary address 15 closes every channel; others their own, secondary address 1 the
;; internal ones too.
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

;; secondary address 15: secondary address 14 down to 0, each closed.
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

;; Closes a secondary address's channel by its type: a direct channel writes the BAM, a relative file goes through its
;; own steps, and a write channel writes its last block and closes its directory entry. The channel is then freed.
;; In: SecondaryAddress = the secondary address
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

;; The BAM is written out, through <Bam::WriteForChannel>.
;; Also: CLSC30 (D1541)
WriteBam:
    jsr Bam::WriteForChannel

;; The channel is then freed.
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

;; The channel is then freed.
;; Also: CLSR1 (D1541)
RelativeDone:
    jmp FreeChannel
.endproc

;; Writes a sequential file's last block: a file with nothing in it gets a RETURN, and an empty last buffer gives its
;; block back. The link is set to 0, with the last byte's place, and the block is written and waited for.
;; In: Channel = the channel
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
; Closing a written file's directory entry.
.scope Directory continued

;; Closes a written file's directory entry: sets its closed bit and block count. A replace (the entry's replace bit)
;; swaps the new chain in and deletes the old one.
;; In: Channel = the channel, SecondaryAddress = the secondary address
;; Errors: error 67, <ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR>, when a replaced file has no new chain
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
    lda #ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR
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

;; The block count, the sector written, secondary address and <Channel> back.
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
; Opening the channels: reading, writing, and the flags and tests they and the relative files use.
.scope Files continued

;; Opens a read channel with one buffer on <Track> and <Sector>, of file type <FileType>; the first block is read and
;; its first byte made ready. A relative file also gets read-write mode, its record size, its side sector read and its
;; first record.
;; In: Track, Sector = the first block, FileType = the type, RecordSize = the record size for a relative file,
;;   SecondaryAddress = the secondary address
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no channel or buffer is free
;; Entry:
;;   FirstRecord = Sets the first record up, and <Track> and <Sector> back (<OpenWriteChannel> enters here for a new
;;     relative file)
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

;; In the last block <ChannelLastByte> = the link's sector, the last byte's place.
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

;; The next record is 2, the first record is set up, and <Track> and <Sector> are put back (<OpenWriteChannel> enters
;; here for a new relative file).
;; Also: OROW (D1541)
FirstRecord:
    ldx Channel
    lda #$02
    sta ChannelNextRecord,x
    lda #$00
    jsr SetPointer
    jsr Relative::ReadByte::LoadNextRecord
    jmp GetBufferBlock

;; The first byte into <ChannelByte>, ready to talk.
;; Also: OR30 (D1541)
Sequential:
    jsr ReadByte
    ldx Channel
    sta ChannelByte,x
    lda #CHANNEL_TALK
    sta ChannelStatus,x
    rts
.endproc

;; Sets both of the current channel's buffers' pointers to 2, makes its second buffer inactive and zeroes its block
;; count and last byte's place.
;; In: Channel = the channel
;; Uses: A, X, Y
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

;; Opens a write channel with one buffer on the first free block, ready to listen. A relative file also gets its first
;; side sector, and its first block of empty records, written.
;; In: FileType = the type, RecordSize = the record size for a relative file, SecondaryAddress = the secondary address,
;;   DriveNumber = the drive
;; Errors: error 70, <ERROR_NO_CHANNEL>, when no channel or buffer is free; error 72, <ERROR_DISK_FULL>
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
; The side sector's byte writer, which the ROM keeps with the open code.
.scope Relative continued

;; Puts a byte into the side sector's buffer at its pointer, through <Files::PutByte>. The code of the open routines
;; holds it, though the side sector routines are its users.
;; In: A = the byte
;; Out: zero = set when the pointer wrapped to 0
;; Also: PUTSS (D1541)
.proc PutSideSectorByte
    pha
    ldx Channel
    lda ChannelSideSector,x
    jmp Files::PutByte::IntoBuffer
.endproc
.endscope
; The channel's file type flags, and the tests the channels need.
.scope Files continued

;; Sets or clears the flag bits in A in the channel's file type: carry set sets them, carry clear clears them. Nothing
;; calls it; it stays because the ROM has it, and falls into <SetFlag> when carry is set.
;; In: A = the bits, carry = set to set them, clear to clear them
;; Also: SCFLG (D1541)
.proc SetOrClearFlag
    bcc ClearFlag
    ; Falls into SetFlag.
    .assert * = SetFlag, "SetOrClearFlag must be followed by SetFlag."
.endproc

;; Sets bits A in the current channel's file type, which holds the relative files' flags.
;; In: A = the bits
;; Uses: A, X
;; Also: SETFLG (D1541)
.proc SetFlag
    ldx Channel
    ora ChannelFileType,x
    bne ClearFlag::Store
.endproc

;; Clears bits A in the current channel's file type, which holds the relative files' flags.
;; In: A = the bits
;; Uses: A, X
;; Entry:
;;   Store = Stores A in the file type (<SetFlag> ends here)
;; Also: CLRFLG (D1541)
.proc ClearFlag
    ldx Channel
    eor #$FF
    and ChannelFileType,x

;; Stores A in the file type (<SetFlag> ends here).
;; Also: CLRF10 (D1541)
Store:
    sta ChannelFileType,x
    rts
.endproc

;; Tests bits A of the current channel's file type.
;; In: A = the bits
;; Out: A = the file type ANDed with them, zero = set when they are clear, X = the channel
;; Also: TSTFLG (D1541)
.proc TestFlag
    ldx Channel
    and ChannelFileType,x
    rts
.endproc

;; Tests whether the active buffer's last job was a write.
;; Out: zero = set for a write
;; Uses: A, X
;; Also: TSTWRT (D1541)
.proc TestWriteJob
    jsr GetActiveBuffer
    tax
    lda LastJobs,x
    and #$F0
    cmp #$90
    rts
.endproc

;; Looks for a channel, of secondary address 0 up, that has the directory entry found open: the same drive, and the same
;; directory place.
;; In: EntryFound = the entry's place in the file name tables
;; Out: carry = clear when a channel has it, with Y = the channel, set when none has it
;; Also: TSTCHN (D1541)
.proc TestEntryOpen
    ldx #$00

;; Each secondary address.
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

;; The channel's drive, entry sector and entry index against the entry's.
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
