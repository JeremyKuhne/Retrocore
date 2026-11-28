; retrocore: style=strict
; COMMODORE 1541 DOS: THE DRIVE CONTROLLER ($F259-$FE84)
.scope Controller continued

;; Sets up VIA 2 (port B's directions; motor off, LED off; CA2 high, which enables byte-ready, though the listing's
;; comment says it disables it; timer 1 free-running at 58 x 256 cycles with its interrupt), the block IDs (`HBID` 8,
;; `DBID` 7), the stepper (`NXTST` = StepIdle, `MINSTP` 200, `AS`, `AF` 4), no drive and no format; falls into
;; <ScanJobs>.
;; Also: CNTINT (D1541)
.proc Initialize
    lda #$6F
    sta Via2DirectionB
    and #$F0
    sta DriveControl
    lda Via2PeripheralControl
    and #$FE
    ora #$0E
    ora #$E0
    sta Via2PeripheralControl
    lda #$41
    sta Via2AuxiliaryControl
    lda #$00
    sta Via2Timer1Latch
    lda #IRQ_PERIOD
    sta Via2Timer1LatchHigh
    sta Via2Timer1High
    lda #$7F
    sta Via2InterruptEnable
    lda #$C0
    sta Via2InterruptFlags
    sta Via2InterruptEnable
    lda #$FF
    sta ActiveDrive
    sta FormatTrack
    lda #$08
    sta HeaderId
    lda #$07
    sta DataId
    lda #<EndPass::StepIdle
    sta StepperState
    lda #>EndPass::StepIdle
    sta StepperState+1
    lda #$C8
    sta MinimumAccelerationSteps
    lda #$04
    sta AccelerationSteps
    lda #$04
    sta AccelerationFactor
.endproc

;; One pass of the controller: saves the stack for <FinishJob>, clears the timer's interrupt (END restarts it), enables
;; byte-ready, and finds a job. Starts the motor, steps toward the job's track, or dispatches the job on this track;
;; ends in <EndPass>.
;; Entry:
;;   Rescan = Scans the queue from job 5 down for the first job (bit 7 set)
;; Also: LCC (D1541)
.proc ScanJobs
    tsx
    stx SavedStack
    lda Via2Timer1
    lda Via2PeripheralControl
    ora #$0E
    sta Via2PeripheralControl

;; Scans the queue from job 5 down for the first job (bit 7 set); <FinishJob> comes back here after each job.
;; Also: TOP (D1541)
Rescan:
    ldy #JOB_COUNT-1

;; Scans the queue for a job (jobs count down from the last); a jump job (`JUMPC`) runs its buffer at once, motor or
;; not.
;; Also: CONT10 (D1541)
FindJob:
    lda a:JobQueue,y
    bpl NextJob
    cmp #JOB_JUMP
    bne CheckDrive
    tya
    jmp JumpToBuffer

;; Drive 1 fails the job with $0F, no drive.
;; Also: CONT30 (D1541)
CheckDrive:
    and #$01
    beq CheckCurrentDrive
    sty JobIndex
    lda #$0F
    jmp FinishJob

;; A drive not yet active (`CDRIVE`) is turned on, and the pass ends to let it spin up.
;; Also: CONT35 (D1541)
CheckCurrentDrive:
    tax
    sta Drive
    cmp ActiveDrive
    beq CheckReady
    jsr MotorOn
    lda Drive
    sta ActiveDrive
    jmp EndPass

;; Waits while `DRVST` says spinning up (bit 7) or stepping (bit 6).
;; Also: CONT40 (D1541)
CheckReady:
    lda DriveStatus
    bmi ToEndPass
    asl
    bpl ScanTrack

;; Jumps on to <EndPass>.
;; Also: CONT50 (D1541)
ToEndPass:
    jmp EndPass

;; The next job; none found ends the pass.
;; Also: CONT20 (D1541)
NextJob:
    dey
    bpl FindJob
    jmp EndPass

;; `DRVST` = running; scans every job for one on the head's track (`DRVTRK`).
;; Also: QUE (D1541)
ScanTrack:
    lda #$20
    sta DriveStatus
    ldy #JOB_COUNT-1
    sty JobIndex

;; Loads job `JOBN`; a pending one is checked.
;; Also: QUE10 (D1541)
ScanTrackNext:
    jsr LoadJob
    bmi CheckTrack

;; The next lower job. With none on the track, steps toward the track of the lowest-numbered job seen (`NXTJOB`):
;; `STEPS` = twice the distance, `DRVST` = stepping, `DRVTRK` = its track.
;; Also: QUE05 (D1541)
ScanTrackLoop:
    dec JobIndex
    bpl ScanTrackNext
    ldy SeekJob
    jsr LoadJob::JobInY
    lda SeekDistance
    sta Steps
    asl Steps
    lda #$60
    sta DriveStatus
    lda (HeaderPointer),y
    sta HeadTrack
    jmp EndPass

;; For the active drive's job: an unknown head track (0) or the job's track is on track; otherwise its distance
;; (`NXTRK`) and number (`NXTJOB`) are kept.
;; Also: QUE20 (D1541)
CheckTrack:
    and #$01
    cmp Drive
    bne ScanTrackLoop
    lda HeadTrack
    beq OnTrack
    sec
    sbc (HeaderPointer),y
    beq OnTrack
    eor #$FF
    sta SeekDistance
    inc SeekDistance
    lda JobIndex
    sta SeekJob
    jmp ScanTrackLoop

;; Finds the track's zone in `TRKNUM`, sets `SECTR` from `NUMSEC` and the density bits in `DSKCNT`, and dispatches by
;; job type.
;; Also: GOTU (D1541)
OnTrack:
    ldx #$04
    lda (HeaderPointer),y
    sta JobTrack

;; Counts down the zone boundaries.
;; Also: GOTU10 (D1541)
FindZone:
    cmp ZoneLimits-1,x
    dex
    bcs FindZone
    lda SectorsPerTrack,x
    sta SectorCount
    txa
    asl
    asl
    asl
    asl
    asl
    sta Work
    lda DriveControl
    and #$9F
    ora Work
    sta DriveControl
    ldx Drive
    lda JobCode
    cmp #JOB_CODE_BUMP
    beq Bump
    cmp #JOB_CODE_EXECUTE
    beq Execute
    jmp Seek

;; An execute job (`EXECD`), once on its track: runs its buffer.
;; Also: EX (D1541)
Execute:
    lda JobIndex

;; Jumps to the start of buffer A ($0300 + A x 256), which ends the job itself, through <FinishJob> or <EndPass>.
;; Also: EX2 (D1541)
JumpToBuffer:
    clc
    adc #>Buffers
    sta DataPointer+1
    lda #$00
    sta DataPointer
    jmp (DataPointer)

;; A bump: 92 half-tracks outward against the stop (`STEPS` = -92) with `DRVTRK` = 1, and the job finished with 1.
;; Also: BMP (D1541)
Bump:
    lda #$60
    sta DriveStatus
    lda DriveControl
    and #$FC
    sta DriveControl
    lda #$A4
    sta Steps
    lda #$01
    sta HeadTrack
    jmp FinishJob
.endproc

;; Job `JOBN`: if pending, `JOB` = its type ($00 read to $60 execute), `HDRPNT` = its header, `BUFPNT` = its buffer;
;; returns the queue byte, N set if pending, Y = 0.
;; Entry:
;;   JobInY = The same for job Y
;; Also: SETJB (D1541)
.proc LoadJob
    ldy JobIndex

;; The same for job Y.
;; Also: SETJB1 (D1541)
JobInY:
    lda a:JobQueue,y
    pha
    bpl Finish
    and #$78
    sta JobCode
    tya
    asl
    adc #<JobHeaders
    sta HeaderPointer
    tya
    clc
    adc #>Buffers
    sta DataPointer+1

;; Clears `BUFPNT`'s low byte and Y, and returns the queue byte.
;; Also: SETJ10 (D1541)
Finish:
    ldy #$00
    sty DataPointer
    pla
    rts
.endproc

;; Reads headers (up to 90) until one checks: sets `DRVTRK` from it, finishes a seek job, checks the disk ID, then goes
;; to <ChooseSector>. A write comes back here to become its verify.
;; Entry:
;;   JobDone = Finishes the job with 1, success
;; Also: SEAK (D1541)
.proc Seek
    ldx #$5A
    stx Scratch
    ldx #$00
    lda #$52
    sta HeaderGcr

;; Waits for a sync and the header's first GCR byte, $52.
;; Also: SEEK10 (D1541)
FindHeader:
    jsr WaitForSync
    bvc *
    clv
    lda DiskData
    cmp HeaderGcr
    bne NotHeader

;; Reads the header's other 7 GCR bytes into `STAB`, then decodes them.
;; Also: SEEK15 (D1541)
ReadHeader:
    bvc *
    clv
    lda DiskData
    sta HeaderGcr+1,x
    inx
    cpx #$07
    bne ReadHeader
    jsr DecodeHeader
    ldy #$04
    lda #$00

;; The header's five bytes must XOR to 0, else error 9.
;; Also: SEEK30 (D1541)
Checksum:
    eor a:LastHeader,y
    dey
    bpl Checksum
    cmp #$00
    bne HeaderChecksumError
    ldx ActiveDrive
    lda LastHeader+2
    sta HeadTrack,x
    lda JobCode
    cmp #$30
    beq SeekJob
    lda ActiveDrive
    asl
    tay
    lda a:DiskId,y
    cmp LastHeader
    bne IdMismatch
    lda a:DiskId+1,y
    cmp LastHeader+1
    bne IdMismatch
    jmp ChooseSector

;; Not a header: tries again, and after 90 fails with 2, header not found.
;; Also: SEEK20 (D1541)
NotHeader:
    dec Scratch
    bne FindHeader
    lda #$02
    jsr FinishJob

;; A seek job copies the header's ID into `DSKID` (the "harris fix"), which is how the DOS learns a disk's ID, and
;; finishes.
;; Also: ESEEK (D1541)
SeekJob:
    lda LastHeader
    sta DiskId
    lda LastHeader+1
    sta DiskId+1

;; Finishes the job with 1, success; skips the next load with $2C.
;; Also: DONE (D1541)
JobDone:
    lda #$01
    .byte OPCODE_BIT

;; Finishes with 11, disk ID mismatch; skips the next load with $2C.
;; Also: BADID (D1541)
IdMismatch:
    lda #$0B
    .byte OPCODE_BIT

;; Finishes with 9, header checksum error.
;; Also: CSERR (D1541)
HeaderChecksumError:
    lda #$09
    jmp FinishJob
.endproc

;; Of the active drive's jobs on this track, picks the one whose sector comes soonest after the next but one. A read
;; must be within `RDMAX` (6) sectors, and a write, verify or sector seek `WRTMIN` to `WRTMAX`-1 (9 to 11). Loads it and
;; goes to <Read>; none ends the pass.
;; Also: WSECT (D1541)
.proc ChooseSector
    lda #$7F
    sta BestDistance
    lda LastHeader+3
    clc
    adc #$02
    cmp SectorCount
    bcc SetNext
    sbc SectorCount

;; `NEXTS` = the header's sector + 2, wrapped.
;; Also: L460 (D1541)
SetNext:
    sta UpcomingSector
    ldx #JOB_COUNT-1
    stx JobIndex
    ldx #$FF

;; A pending job on this drive and track: its distance from `NEXTS`, wrapped.
;; Also: L480 (D1541)
CheckJob:
    jsr LoadJob
    bpl NextJob
    sta Work
    and #$01
    cmp ActiveDrive
    bne NextJob
    ldy #$00
    lda (HeaderPointer),y
    cmp JobTrack
    bne NextJob
    lda JobCode
    cmp #JOB_CODE_EXECUTE
    beq CompareDistance
    ldy #$01
    sec
    lda (HeaderPointer),y
    sbc UpcomingSector
    bpl CompareDistance
    clc
    adc SectorCount

;; Keeps the job if it is nearer than the best so far (`CSECT`) and inside its type's window.
;; Also: L465 (D1541)
CompareDistance:
    cmp BestDistance
    bcs NextJob
    pha
    lda JobCode
    beq ReadWindow
    pla
    cmp #WRITE_DISTANCE_MIN
    bcc NextJob
    cmp #WRITE_DISTANCE_MAX
    bcs NextJob

;; The best so far: `CSECT`, X = its job, `BUFPNT` = its buffer.
;; Also: DOITT (D1541)
Best:
    sta BestDistance
    lda JobIndex
    tax
    adc #>Buffers
    sta DataPointer+1
    bne NextJob

;; A read: within 6 sectors.
;; Also: TSTRDJ (D1541)
ReadWindow:
    pla
    cmp #READ_DISTANCE
    bcc Best

;; The next lower job.
;; Also: L470 (D1541)
NextJob:
    dec JobIndex
    bpl CheckJob
    txa
    bpl Dispatch
    jmp EndPass

;; Loads the chosen job and goes to <Read> with its type.
;; Also: L490 (D1541)
Dispatch:
    stx JobIndex
    jsr LoadJob
    lda JobCode
    jmp Read
.endproc

;; Decodes the 8 GCR bytes in `STAB` into `HEADER` (ID, ID, track, sector, checksum); keeps `BUFPNT`.
;; Also: CNVBIN (D1541)
.proc DecodeHeader
    lda DataPointer
    pha
    lda DataPointer+1
    pha
    lda #<HeaderGcr
    sta DataPointer
    lda #>HeaderGcr
    sta DataPointer+1
    lda #$00
    sta GcrIndex
    jsr DecodeGroup
    lda BinaryBytes+3
    sta LastHeader+2
    lda BinaryBytes+2
    sta LastHeader+3
    lda BinaryBytes+1
    sta LastHeader+4
    jsr DecodeGroup
    lda BinaryBytes
    sta LastHeader+1
    lda BinaryBytes+1
    sta LastHeader
    pla
    sta DataPointer+1
    pla
    sta DataPointer
    rts
.endproc

;; A = job type: anything but a read goes on to <Write>. Reads the sector's 326 GCR bytes into the buffer and the
;; overflow buffer, decodes them, and checks the block ID (error 4) and checksum (error 5).
;; Also: REED (D1541)
.proc Read
    cmp #$00
    beq Start
    jmp Write

;; Finds the sector's header and then its data block's sync.
;; Also: READ01 (D1541)
Start:
    jsr FindData

;; The first 256 GCR bytes, into the buffer.
;; Also: READ11 (D1541)
ReadBuffer:
    bvc *
    clv
    lda DiskData
    sta (DataPointer),y
    iny
    bne ReadBuffer
    ldy #$BA

;; The rest, into the overflow buffer from $01BA.
;; Also: READ20 (D1541)
ReadOverflow:
    bvc *
    clv
    lda DiskData
    sta OverflowBuffer,y
    iny
    bne ReadOverflow
    jsr DecodeBlock
    lda BlockId
    cmp DataId
    beq CheckBlock
    lda #$04
    jmp FinishJob

;; A data block: compares the checksum; a mismatch finishes with 5, skipping the next load with $2C.
;; Also: READ28 (D1541)
CheckBlock:
    jsr BlockChecksum
    cmp Checksum
    beq ReadOk
    lda #$05
    .byte OPCODE_BIT

;; Finishes with 1.
;; Also: READ40 (D1541)
ReadOk:
    lda #$01
    jmp FinishJob
.endproc

;; Finds the job's header, then the data block's sync.
;; Also: DSTRT (D1541)
.proc FindData
    jsr FindHeader
    jmp WaitForSync
.endproc

;; Builds the job's header (the drive's `DSKID`, its track and sector, the checksum), encodes it, and reads up to 90
;; headers until one matches all 8 GCR bytes; else finishes with 2.
;; Entry:
;;   ToFinishJob = Jumps on to <FinishJob>
;; Also: SRCH (D1541)
.proc FindHeader
    lda Drive
    asl
    tax
    lda DiskId,x
    sta LastHeader
    lda DiskId+1,x
    sta LastHeader+1
    ldy #$00
    lda (HeaderPointer),y
    sta LastHeader+2
    iny
    lda (HeaderPointer),y
    sta LastHeader+3
    lda #$00
    eor LastHeader
    eor LastHeader+1
    eor LastHeader+2
    eor LastHeader+3
    sta LastHeader+4
    jsr EncodeHeader
    ldx #$5A

;; Waits for the next sync.
;; Also: SRCH20 (D1541)
NextSync:
    jsr WaitForSync
    ldy #$00

;; Compares the next GCR byte with `STAB`.
;; Also: SRCH25 (D1541)
Compare:
    bvc *
    clv
    lda DiskData
    cmp a:HeaderGcr,y
    bne Mismatch
    iny
    cpy #$08
    bne Compare
    rts

;; Not this header: tries the next.
;; Also: SRCH30 (D1541)
Mismatch:
    dex
    bne NextSync
    lda #$02

;; Jumps on to <FinishJob>; <WaitForSync> branches here on its timeout with 3.
;; Also: ERR (D1541)
ToFinishJob:
    jmp FinishJob
.endproc

;; Waits up to 20 ms (VIA 1's timer 1, `TIMER1`) for the end of a sync, else finishes the job with 3, no sync; clears
;; the latch and V; Y = 0.
;; Also: SYNC (D1541)
.proc WaitForSync
    lda #$D0
    sta Via1Timer1High
    lda #$03

;; Polls the timer and the sync bit.
;; Also: SYNC10 (D1541)
Wait:
    bit Via1Timer1High
    bpl FindHeader::ToFinishJob
    bit DriveControl
    bmi Wait
    lda DiskData
    clv
    ldy #$00
    rts
.endproc

;; A = job type: anything but a write goes on to <Verify>. Fails with 8 if the disk is protected. Otherwise encodes the
;; buffer, finds the header, waits out the header gap, and writes 5 sync bytes and the 325 GCR bytes. Then it decodes
;; the buffer again and turns the job into a verify for <Seek>.
;; Also: WRIGHT (D1541)
.proc Write
    cmp #$10
    beq WriteJob
    jmp Verify

;; `CHKSUM` = the buffer's checksum; checks the write-protect sense.
;; Also: WRT05 (D1541)
WriteJob:
    jsr BlockChecksum
    sta Checksum
    lda DriveControl
    and #$10
    bne NotProtected
    lda #$08
    jmp FinishJob

;; Encodes the buffer and finds the header.
;; Also: WRT10 (D1541)
NotProtected:
    jsr EncodeBlock
    jsr FindHeader
    ldx #HEADER_GAP-2

;; Waits 9 bytes (`GAP1`-2) past the header, then switches the port to output and the head to writing.
;; Also: WRT20 (D1541)
SkipGap:
    bvc *
    clv
    dex
    bne SkipGap
    lda #$FF
    sta Via2DirectionA
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl
    lda #$FF
    ldx #SYNC_LENGTH
    sta DiskData
    clv

;; Five $FF bytes, the data block's sync (`NUMSYN`).
;; Also: WRTSNC (D1541)
WriteSync:
    bvc *
    clv
    dex
    bne WriteSync
    ldy #$BB

;; The 69 GCR bytes in the overflow buffer, first.
;; Also: WRT30 (D1541)
WriteOverflow:
    lda OverflowBuffer,y
    bvc *
    clv
    sta DiskData
    iny
    bne WriteOverflow

;; The 256 in the buffer; then back to reading, decodes, and makes the job a verify.
;; Also: WRT40 (D1541)
WriteBuffer:
    lda (DataPointer),y
    bvc *
    clv
    sta DiskData
    iny
    bne WriteBuffer
    bvc *
    lda Via2PeripheralControl
    ora #$E0
    sta Via2PeripheralControl
    lda #$00
    sta Via2DirectionA
    jsr DecodeWriteImage
    ldy JobIndex
    lda a:JobQueue,y
    eor #$30
    sta a:JobQueue,y
    jmp Seek
.endproc

;; A = the XOR of the buffer's 256 bytes; Y = 0.
;; Also: CHKBLK (D1541)
.proc BlockChecksum
    lda #$00
    tay

;; XORs the next byte.
;; Also: CHKB10 (D1541)
Loop:
    eor (DataPointer),y
    iny
    bne Loop
    rts
.endproc

;; Decodes the write image in place (overflow buffer first, then the buffer), `BID` = its block ID. Moves the result up
;; and the decoded start in from the overflow buffer, so the buffer is binary again, and clears `GCRFLG`.
;; Also: WTOBIN (D1541)
.proc DecodeWriteImage
    lda #$00
    sta SavedPointer
    sta DataPointer
    sta NextIndex
    lda DataPointer+1
    sta NextPage
    lda #>OverflowBuffer
    sta DataPointer+1
    sta SavedPointer+1
    lda #$BB
    sta GcrIndex
    sta ByteIndex
    jsr DecodeGroup
    lda BinaryBytes
    sta BlockId
    ldy ByteIndex
    lda BinaryBytes+1
    sta (SavedPointer),y
    iny
    lda BinaryBytes+2
    sta (SavedPointer),y
    iny
    lda BinaryBytes+3
    sta (SavedPointer),y
    iny
    sty ByteIndex

;; Decodes groups into the overflow buffer until it fills.
;; Also: WTOB14 (D1541)
NextOverflowGroup:
    jsr DecodeGroup
    ldy ByteIndex
    lda BinaryBytes
    sta (SavedPointer),y
    iny
    lda BinaryBytes+1
    sta (SavedPointer),y
    iny
    beq CrossToBuffer
    lda BinaryBytes+2
    sta (SavedPointer),y
    iny
    lda BinaryBytes+3
    sta (SavedPointer),y
    iny
    sty ByteIndex
    bne NextOverflowGroup

;; The group that crosses into the buffer.
;; Also: WTOB50 (D1541)
CrossToBuffer:
    lda BinaryBytes+2
    sta (DataPointer),y
    iny
    lda BinaryBytes+3
    sta (DataPointer),y
    iny
    sty ByteIndex

;; Decodes groups into the buffer up to byte 187.
;; Also: WTOB53 (D1541)
NextBufferGroup:
    jsr DecodeGroup
    ldy ByteIndex
    lda BinaryBytes
    sta (DataPointer),y
    iny
    lda BinaryBytes+1
    sta (DataPointer),y
    iny
    lda BinaryBytes+2
    sta (DataPointer),y
    iny
    lda BinaryBytes+3
    sta (DataPointer),y
    iny
    sty ByteIndex
    cpy #$BB
    bcc NextBufferGroup
    lda #$45
    sta SavedPointer
    lda DataPointer+1
    sta SavedPointer+1
    ldy #$BA

;; Moves the buffer's bytes up 69, from the top.
;; Also: WTOB55 (D1541)
MoveUp:
    lda (DataPointer),y
    sta (SavedPointer),y
    dey
    bne MoveUp
    lda (DataPointer),y
    sta (SavedPointer),y
    ldx #$BB

;; Copies the overflow buffer's bytes to the buffer's start.
;; Also: WTOB57 (D1541)
MoveOverflow:
    lda OverflowBuffer,x
    sta (DataPointer),y
    iny
    inx
    bne MoveOverflow
    stx BufferIsGcr
    rts
.endproc

;; A = job type: anything but a verify goes on to <SectorSeek>. Encodes the buffer and compares it with the sector's
;; data block, all but the 2 off bytes; a difference finishes with 7.
;; Also: VRFY (D1541)
.proc Verify
    cmp #$20
    beq VerifyJob
    jmp SectorSeek

;; Computes the checksum, encodes, and finds the data block.
;; Also: VRF10 (D1541)
VerifyJob:
    jsr BlockChecksum
    sta Checksum
    jsr EncodeBlock
    jsr FindData
    ldy #$BB

;; Compares the overflow buffer's 69 bytes.
;; Also: VRF15 (D1541)
CompareOverflow:
    lda OverflowBuffer,y
    bvc *
    clv
    eor DiskData
    bne Mismatch
    iny
    bne CompareOverflow

;; Compares the buffer's bytes up to $FD.
;; Also: VRF30 (D1541)
CompareBuffer:
    lda (DataPointer),y
    bvc *
    clv
    eor DiskData
    bne Mismatch
    iny
    cpy #$FD
    bne CompareBuffer
    jmp Seek::JobDone

;; Finishes with 7, verify error.
;; Also: VRF20 (D1541)
Mismatch:
    lda #$07
    jmp FinishJob
.endproc

;; The job type left, sector seek (`SECSEK`): finds the job's header and finishes with 1.
;; Also: SECTSK (D1541)
.proc SectorSeek
    jsr FindHeader
    jmp Seek::JobDone
.endproc

;; Encodes the 4 bytes in `BTAB` as 5 GCR bytes at `BUFPNT`+`GCRPNT`, moving to the buffer `SAVPNT` names when the index
;; wraps.
;; Also: PUT4BG (D1541)
.proc EncodeGroup
    lda #$00
    sta GcrGroup+1
    sta GcrGroup+4
    ldy GcrIndex
    lda BinaryBytes
    and #$F0
    lsr
    lsr
    lsr
    lsr
    tax
    lda GcrCodes,x
    asl
    asl
    asl
    sta GcrGroup
    lda BinaryBytes
    and #$0F
    tax
    lda GcrCodes,x
    ror
    ror GcrGroup+1
    ror
    ror GcrGroup+1
    and #$07
    ora GcrGroup
    sta (DataPointer),y
    iny
    lda BinaryBytes+1
    and #$F0
    lsr
    lsr
    lsr
    lsr
    tax
    lda GcrCodes,x
    asl
    ora GcrGroup+1
    sta GcrGroup+1
    lda BinaryBytes+1
    and #$0F
    tax
    lda GcrCodes,x
    rol
    rol
    rol
    rol
    sta GcrGroup+2
    rol
    and #$01
    ora GcrGroup+1
    sta (DataPointer),y
    iny
    lda BinaryBytes+2
    and #$F0
    lsr
    lsr
    lsr
    lsr
    tax
    lda GcrCodes,x
    clc
    ror
    ora GcrGroup+2
    sta (DataPointer),y
    iny
    ror
    and #$80
    sta GcrGroup+3
    lda BinaryBytes+2
    and #$0F
    tax
    lda GcrCodes,x
    asl
    asl
    and #$7C
    ora GcrGroup+3
    sta GcrGroup+3
    lda BinaryBytes+3
    and #$F0
    lsr
    lsr
    lsr
    lsr
    tax
    lda GcrCodes,x
    ror
    ror GcrGroup+4
    ror
    ror GcrGroup+4
    ror
    ror GcrGroup+4
    and #$03
    ora GcrGroup+3
    sta (DataPointer),y
    iny
    bne LastByte
    lda SavedPointer+1
    sta DataPointer+1

;; The fifth GCR byte; `GCRPNT` advances.
;; Also: BING35 (D1541)
LastByte:
    lda BinaryBytes+3
    and #$0F
    tax
    lda GcrCodes,x
    ora GcrGroup+4
    sta (DataPointer),y
    iny
    sty GcrIndex
    rts
.endproc

;; The 16 five-bit GCR codes, one per nibble value.
;; Also: BGTAB (D1541)
GcrCodes:
    .byte $0A
    .byte $0B
    .byte $12
    .byte $13
    .byte $0E
    .byte $0F
    .byte $16
    .byte $17
    .byte $09
    .byte $19
    .byte $1A
    .byte $1B
    .byte $0D
    .byte $1D
    .byte $1E
    .byte $15

;; Encodes the block ID (`DBID`), the buffer, `CHKSUM` and two 0 off bytes (260 bytes) as the 325-byte write image: 69
;; bytes in the overflow buffer, then the buffer itself. Sets `GCRFLG`.
;; Also: BINGCR (D1541)
.proc EncodeBlock
    lda #$00
    sta DataPointer
    sta SavedPointer
    sta ByteIndex
    lda #$BB
    sta GcrIndex
    sta BufferIsGcr
    lda DataPointer+1
    sta SavedPointer+1
    lda #>OverflowBuffer
    sta DataPointer+1
    lda DataId
    sta BinaryBytes
    ldy ByteIndex
    lda (SavedPointer),y
    sta BinaryBytes+1
    iny
    lda (SavedPointer),y
    sta BinaryBytes+2
    iny
    lda (SavedPointer),y
    sta BinaryBytes+3
    iny

;; Encodes the next four bytes.
;; Also: BING07 (D1541)
NextGroup:
    sty ByteIndex
    jsr EncodeGroup
    ldy ByteIndex
    lda (SavedPointer),y
    sta BinaryBytes
    iny
    beq Trailer
    lda (SavedPointer),y
    sta BinaryBytes+1
    iny
    lda (SavedPointer),y
    sta BinaryBytes+2
    iny
    lda (SavedPointer),y
    sta BinaryBytes+3
    iny
    bne NextGroup

;; The last data byte, the checksum and the off bytes.
;; Also: BING20 (D1541)
Trailer:
    lda Checksum
    sta BinaryBytes+1
    lda #$00
    sta BinaryBytes+2
    sta BinaryBytes+3
    jmp EncodeGroup
.endproc

;; Decodes 5 GCR bytes at `BUFPNT`+`GCRPNT` into 4 in `BTAB`, moving to `NXTBF` at `NXTPNT` when the index wraps; bad
;; codes are not checked.
;; Also: GET4GB (D1541)
.proc DecodeGroup
    ldy GcrIndex
    lda (DataPointer),y
    and #CODE1
    lsr
    lsr
    lsr
    sta GcrGroup
    lda (DataPointer),y
    and #CODE2_HIGH
    asl
    asl
    sta GcrGroup+1
    iny
    bne SecondByte
    lda NextPage
    sta DataPointer+1
    ldy NextIndex

;; The second GCR byte, after a possible change of buffer.
;; Also: XX05 (D1541)
SecondByte:
    lda (DataPointer),y
    and #CODE2_LOW
    rol
    rol
    rol
    ora GcrGroup+1
    sta GcrGroup+1
    lda (DataPointer),y
    and #CODE3
    lsr
    sta GcrGroup+2
    lda (DataPointer),y
    and #CODE4_HIGH
    asl
    asl
    asl
    asl
    sta GcrGroup+3
    iny
    lda (DataPointer),y
    and #CODE4_LOW
    lsr
    lsr
    lsr
    lsr
    ora GcrGroup+3
    sta GcrGroup+3
    lda (DataPointer),y
    and #CODE5_HIGH
    asl
    sta GcrGroup+4
    iny
    lda (DataPointer),y
    and #CODE5_LOW
    clc
    rol
    rol
    and #$01
    ora GcrGroup+4
    sta GcrGroup+4
    lda (DataPointer),y
    and #CODE6
    lsr
    lsr
    sta GcrGroup+5
    lda (DataPointer),y
    and #CODE7_HIGH
    asl
    asl
    asl
    sta GcrGroup+6
    iny
    bne FifthByte
    lda NextPage
    sta DataPointer+1
    ldy NextIndex

;; The fifth, likewise; then the tables give the nibbles.
;; Also: XX06 (D1541)
FifthByte:
    lda (DataPointer),y
    and #CODE7_LOW
    rol
    rol
    rol
    rol
    ora GcrGroup+6
    sta GcrGroup+6
    lda (DataPointer),y
    and #CODE8
    sta GcrGroup+7
    iny
    sty GcrIndex
    ldx GcrGroup
    lda GcrHighNibbles,x
    ldx GcrGroup+1
    ora GcrLowNibbles,x
    sta BinaryBytes
    ldx GcrGroup+2
    lda GcrHighNibbles,x
    ldx GcrGroup+3
    ora GcrLowNibbles,x
    sta BinaryBytes+1
    ldx GcrGroup+4
    lda GcrHighNibbles,x
    ldx GcrGroup+5
    ora GcrLowNibbles,x
    sta BinaryBytes+2
    ldx GcrGroup+6
    lda GcrHighNibbles,x
    ldx GcrGroup+7
    ora GcrLowNibbles,x
    sta BinaryBytes+3
    rts
.endproc

;; For each five-bit code, its nibble in the high half; $FF for the 16 that are not GCR.
;; Also: GCRHI (D1541)
GcrHighNibbles:
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $80
    .byte $00
    .byte $10
    .byte $FF
    .byte $C0
    .byte $40
    .byte $50
    .byte $FF
    .byte $FF
    .byte $20
    .byte $30
    .byte $FF
    .byte $F0
    .byte $60
    .byte $70
    .byte $FF
    .byte $90
    .byte $A0
    .byte $B0
    .byte $FF
    .byte $D0
    .byte $E0
    .byte $FF

;; The same in the low half.
;; Also: GCRLO (D1541)
GcrLowNibbles:
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $FF
    .byte $08
    .byte $00
    .byte $01
    .byte $FF
    .byte $0C
    .byte $04
    .byte $05
    .byte $FF
    .byte $FF
    .byte $02
    .byte $03
    .byte $FF
    .byte $0F
    .byte $06
    .byte $07
    .byte $FF
    .byte $09
    .byte $0A
    .byte $0B
    .byte $FF
    .byte $0D
    .byte $0E
    .byte $FF

;; Decodes a read image (the buffer, then the overflow buffer from $01BA) into the buffer: `BID` = the block ID,
;; `CHKSUM` = the checksum read.
;; Also: GCRBIN (D1541)
.proc DecodeBlock
    lda #$00
    sta GcrIndex
    sta SavedPointer
    sta ByteIndex
    lda #>OverflowBuffer
    sta NextPage
    lda #$BA
    sta NextIndex
    lda DataPointer+1
    sta SavedPointer+1
    jsr DecodeGroup
    lda BinaryBytes
    sta BlockId
    ldy ByteIndex
    lda BinaryBytes+1
    sta (SavedPointer),y
    iny
    lda BinaryBytes+2
    sta (SavedPointer),y
    iny
    lda BinaryBytes+3
    sta (SavedPointer),y
    iny

;; Decodes the next group.
;; Also: GCRB10 (D1541)
NextGroup:
    sty ByteIndex
    jsr DecodeGroup
    ldy ByteIndex
    lda BinaryBytes
    sta (SavedPointer),y
    iny
    beq Finish
    lda BinaryBytes+1
    sta (SavedPointer),y
    iny
    lda BinaryBytes+2
    sta (SavedPointer),y
    iny
    lda BinaryBytes+3
    sta (SavedPointer),y
    iny
    bne NextGroup

;; Keeps the checksum and restores `BUFPNT`.
;; Also: GCRB20 (D1541)
Finish:
    lda BinaryBytes+1
    sta Checksum
    lda SavedPointer+1
    sta DataPointer+1
    rts
.endproc

;; Encodes `HEADER` with `HBID` (block ID, checksum, sector, track, ID, ID, 0, 0) as the 10 GCR bytes in `STAB`, which
;; <FindHeader> compares.
;; Also: CONHDR (D1541)
.proc EncodeHeader
    lda DataPointer+1
    sta SavedPointer+1
    lda #>HeaderGcr
    sta DataPointer+1
    lda #<HeaderGcr
    sta GcrIndex
    lda HeaderId
    sta BinaryBytes
    lda LastHeader+4
    sta BinaryBytes+1
    lda LastHeader+3
    sta BinaryBytes+2
    lda LastHeader+2
    sta BinaryBytes+3
    jsr EncodeGroup
    lda LastHeader+1
    sta BinaryBytes
    lda LastHeader
    sta BinaryBytes+1
    lda #$00
    sta BinaryBytes+2
    sta BinaryBytes+3
    jsr EncodeGroup
    lda SavedPointer+1
    sta DataPointer+1
    rts
.endproc

;; Ends job `JOBN` with code A (1 success, 2-15 errors) in its queue byte. Decodes a buffer left in GCR, starts the
;; motor's timeout, resets the stack to <ScanJobs>' and rescans.
;; Also: ERRR (D1541)
.proc FinishJob
    ldy JobIndex
    sta a:JobQueue,y
    lda BufferIsGcr
    beq Restart
    jsr DecodeWriteImage

;; Starts the timeout, resets the stack, and goes back to <ScanJobs>.
;; Also: ERRR10 (D1541)
Restart:
    jsr MotorTimeout
    ldx SavedStack
    txs
    jmp ScanJobs::Rescan
.endproc

;; Starts the motor: `DRVST` = on and spinning up, `ACLTIM` = 60 ticks (at least 0.89 s; the listing says 1.5 s).
;; Also: TURNON (D1541)
.proc MotorOn
    lda #$A0
    sta DriveStatus
    lda DriveControl
    ora #$04
    sta DriveControl
    lda #$3C
    sta MotorTimer
    rts
.endproc

;; Sets `DRVST`'s timeout bit and `ACLTIM` = 255 ticks (at least 3.78 s), after which <EndPass> stops the motor;
;; <MotorOffVector>, the word at $FFE8 before the user command table, points here too.
;; Also: TRNOFF (D1541)
.proc MotorTimeout
    ldx ActiveDrive
    lda DriveStatus
    ora #$10
    sta DriveStatus
    lda #$FF
    sta MotorTimer
    rts
.endproc

;; Ends each pass. Restarts the tick, notes a change of the write-protect sense (`WPSW`) and takes a half-track step the
;; DOS asked for in `PHASE`. Counts down the spin-up and timeout (stopping the motor when it ends) and runs the
;; stepper's state in `NXTST`; disables byte-ready and returns.
;; Entry:
;;   StepIdle = The stepper's start state
;; Also: END (D1541)
.proc EndPass
    lda Via2Timer1LatchHigh
    sta Via2Timer1High
    lda DriveControl
    and #$10
    cmp LastWriteProtect
    sta LastWriteProtect
    beq CheckHeadOffset
    lda #$01
    sta DiskChanged

;; `PHASE` 1 or $FF: steps once and sets it to 2, which StepHead waits for; StepHead then clears the 2 to 0 (MOVHED).
;; Also: END002 (D1541)
CheckHeadOffset:
    lda StepRequest
    beq CheckMotor
    cmp #$02
    bne OffsetStep
    lda #$00
    sta StepRequest
    beq CheckMotor

;; `STEPS` = the offset; steps.
;; Also: END003 (D1541)
OffsetStep:
    sta Steps
    lda #$02
    sta StepRequest
    jmp Step

;; Nothing to do without an active drive, or when it is only running.
;; Also: END40 (D1541)
CheckMotor:
    ldx ActiveDrive
    bmi ToDone
    lda DriveStatus
    tay
    cmp #$20
    bne CountDown

;; Jumps on to <Done>.
;; Also: END33X (D1541)
ToDone:
    jmp Done

;; Counts `ACLTIM` down; at 0 the spin-up ends.
;; Also: END10 (D1541)
CountDown:
    dec MotorTimer
    bne CheckStepping
    tya
    bpl CheckTimeout
    and #$7F
    sta DriveStatus

;; At the end of the timeout: motor off, no active drive, `DRVST` = 0.
;; Also: END20 (D1541)
CheckTimeout:
    and #$10
    beq CheckStepping
    lda DriveControl
    and #$FB
    sta DriveControl
    lda #$FF
    sta ActiveDrive
    lda #$00
    sta DriveStatus
    beq ToDone

;; Steps only while `DRVST` says stepping.
;; Also: END30 (D1541)
CheckStepping:
    tya
    and #$40
    bne RunStepState
    jmp Done

;; Jumps to the stepper's state, `NXTST`.
;; Also: END30X (D1541)
RunStepState:
    jmp (StepperState)

;; The stepper's start state: a move shorter than `MINSTP` steps one at a time (always, since `STEPS` is a signed byte,
;; at most 128, and the ROM's `MINSTP` is 200); a longer one is accelerated.
;; Also: INACT (D1541)
StepIdle:
    lda Steps
    bpl CheckDistance
    eor #$FF
    clc
    adc #$01

;; Compares the move's length with `MINSTP`.
;; Also: INAC10 (D1541)
CheckDistance:
    cmp MinimumAccelerationSteps
    bcs Accelerated
    lda #<StepShort
    sta StepperState
    lda #>StepShort
    sta StepperState+1
    bne Step

;; `RSTEPS` = the length less twice `AS`, `ACLSTP` = `AS`; next state <StepAccelerate>.
;; Also: INAC20 (D1541)
Accelerated:
    sbc AccelerationSteps
    sbc AccelerationSteps
    sta RunSteps
    lda AccelerationSteps
    sta StepCountdown
    lda #<StepAccelerate
    sta StepperState
    lda #>StepAccelerate
    sta StepperState+1

;; One half-track toward `STEPS`' sign: inward for positive, outward for negative (the listing's unreferenced STPOUT).
;; Also: DOSTEP (D1541)
Step:
    lda Steps
    bpl StepIn
    inc Steps
    ldx DriveControl
    dex
    jmp SetPhase

;; One step a tick until `STEPS` is 0, then settles for 5 ticks (at least 74 ms; the listing says 40 ms).
;; Also: SHORT (D1541)
StepShort:
    lda Steps
    bne Step
    lda #<StepSettle
    sta StepperState
    lda #>StepSettle
    sta StepperState+1
    lda #$05
    sta StepCountdown
    jmp Done

;; Counts the settle down, then clears `DRVST`'s stepping bit and goes back to <StepIdle>.
;; Also: SETLE (D1541)
StepSettle:
    dec StepCountdown
    bne Done
    lda DriveStatus
    and #$BF
    sta DriveStatus
    lda #<StepIdle
    sta StepperState
    lda #>StepIdle
    sta StepperState+1
    jmp Done

;; Counts `STEPS` down and advances the phase, moving the head inward.
;; Also: STPIN (D1541)
StepIn:
    dec Steps
    ldx DriveControl
    inx

;; Puts X's low two bits in `DSKCNT`'s phase bits.
;; Also: STP (D1541)
SetPhase:
    txa
    and #$03
    sta Scratch
    lda DriveControl
    and #$FC
    ora Scratch
    sta DriveControl
    jmp Done

;; Shortens this tick by `AF` and steps, `AS` times; then <StepRun>. Unused with the ROM's `MINSTP`.
;; Also: SSACL (D1541)
StepAccelerate:
    sec
    lda Via2Timer1LatchHigh
    sbc AccelerationFactor
    sta Via2Timer1High
    dec StepCountdown
    bne ToStep
    lda AccelerationSteps
    sta StepCountdown
    lda #<StepRun
    sta StepperState
    lda #>StepRun
    sta StepperState+1

;; Jumps on to <Step>.
;; Also: SSA10 (D1541)
ToStep:
    jmp Step

;; Steps at the normal tick `RSTEPS` times; then <StepDecelerate>.
;; Also: SSRUN (D1541)
StepRun:
    dec RunSteps
    bne ToStep
    lda #<StepDecelerate
    sta StepperState
    lda #>StepDecelerate
    sta StepperState+1
    bne ToStep

;; Lengthens the tick by `AF` and steps, `AS` times; then settles.
;; Also: SSDEC (D1541)
StepDecelerate:
    lda Via2Timer1LatchHigh
    clc
    adc AccelerationFactor
    sta Via2Timer1High
    dec StepCountdown
    bne ToStep
    lda #<StepSettle
    sta StepperState
    lda #>StepSettle
    sta StepperState+1
    lda #$05
    sta StepCountdown

;; Disables byte-ready (CA2 low) and returns.
;; Also: END33 (D1541)
Done:
    lda Via2PeripheralControl
    and #$FD
    sta Via2PeripheralControl
    rts
.endproc

;; The format, run as an execute job (FORMAT's `JMP` at $0600) on every pass until it finishes. The first time it bumps
;; to track 1 and sets 10 errors (`CNT`) and a first track length of 4000 (`NUM`). After that it steps to `FTNUM`,
;; checks write protect, and erases and measures the track. Falls into <WriteTrack>.
;; Also: FORMT (D1541)
.proc Format
    lda FormatTrack
    bpl Started
    ldx Drive
    lda #$60
    sta DriveStatus,x
    lda #$01
    sta HeadTrack,x
    sta FormatTrack
    lda #$A4
    sta Steps
    lda DriveControl
    and #$FC
    sta DriveControl
    lda #$0A
    sta FormatRetries
    lda #$A0
    sta SegmentLength
    lda #$0F
    sta SegmentLength+1
    jmp EndPass

;; Puts `FTNUM` in the job's header, so <ScanJobs> steps there, unless the head is there.
;; Also: L213 (D1541)
Started:
    ldy #$00
    cmp (HeaderPointer),y
    beq OnTrack
    sta (HeaderPointer),y
    jmp EndPass

;; Fails with 8 if the disk is protected.
;; Also: L214 (D1541)
OnTrack:
    lda DriveControl
    and #$10
    bne MeasureTrack
    lda #$08
    jmp FormatError

;; Fills the track with sync, writes `NUM` sync bytes and `NUM` $55 bytes, and times the two segments with VIA 1's timer
;; 1 at 100 microseconds.
;; Also: TOPP (D1541)
MeasureTrack:
    jsr EraseWithSync
    jsr WriteCount
    lda #$55
    sta DiskData
    jsr WriteCount
    jsr EndWrite
    jsr WaitForSync
    lda #$40
    ora Via1AuxiliaryControl
    sta Via1AuxiliaryControl
    lda #$62
    sta Via1Timer1Latch
    lda #$00
    sta Via1Timer1LatchHigh
    sta Via1Timer1High
    ldy #$00
    ldx #$00

;; Waits for sync.
;; Also: FWAIT (D1541)
WaitSync:
    bit DriveControl
    bmi WaitSync

;; Waits for its end.
;; Also: FWAIT2 (D1541)
WaitData:
    bit DriveControl
    bpl WaitData

;; Counts the $55 segment in 100 microseconds ticks, failing with `TOLONG` (2) at 65536.
;; Also: F000 (D1541)
NextDataTick:
    lda Via1Timer1

;; Waits for the tick or a sync.
;; Also: F001 (D1541)
WaitDataTick:
    bit DriveControl
    bpl TimeSync
    lda Via1InterruptFlags
    asl
    bpl WaitDataTick
    inx
    bne NextDataTick
    iny
    bne NextDataTick
    lda #FORMAT_NO_SYNC
    jmp FormatError

;; Keeps the count in `T2`; counts the sync segment.
;; Also: F005 (D1541)
TimeSync:
    stx Temporary2
    sty Temporary2+1
    ldx #$00
    ldy #$00

;; Counts a tick of the sync, failing with `TOLONG` at 65536.
;; Also: F006 (D1541)
NextSyncTick:
    lda Via1Timer1

;; Waits for the tick or the sync's end.
;; Also: F007 (D1541)
WaitSyncTick:
    bit DriveControl
    bmi Compare
    lda Via1InterruptFlags
    asl
    bpl WaitSyncTick
    inx
    bne NextSyncTick
    iny
    bne NextSyncTick
    lda #FORMAT_NO_SYNC
    jmp FormatError

;; `T1` = the sync's time less the data's.
;; Also: F009 (D1541)
Compare:
    sec
    txa
    sbc Temporary2
    tax
    sta Temporary1
    tya
    sbc Temporary2+1
    tay
    sta Temporary1+1
    bpl CheckClose
    eor #$FF
    tay
    txa
    eor #$FF
    tax
    inx
    bne CheckClose
    iny

;; A difference under 4 ticks is close enough.
;; Also: F013 (D1541)
CheckClose:
    tya
    bne Adjust
    cpx #$04
    bcc CountBytes

;; `NUM` += twice the difference (the listing's comment says half), and measures again.
;; Also: F014 (D1541)
Adjust:
    asl Temporary1
    rol Temporary1+1
    clc
    lda Temporary1
    adc SegmentLength
    sta SegmentLength
    lda Temporary1+1
    adc SegmentLength+1
    sta SegmentLength+1
    jmp MeasureTrack

;; Counts the bytes of the $55 segment, failing with `TOMANY` (3) at 65536.
;; Also: COUNT (D1541)
CountBytes:
    ldx #$00
    ldy #$00
    clv

;; Counts a byte-ready until the sync.
;; Also: CNT10 (D1541)
CountLoop:
    lda DriveControl
    bpl Counted
    bvc CountLoop
    clv
    inx
    bne CountLoop
    iny
    bne CountLoop
    lda #FORMAT_TRACK_TOO_LONG
    jmp FormatError

;; `TRAL` = twice the count, the track's length in bytes; stops the timer's free-running mode.
;; Also: CNT20 (D1541)
Counted:
    txa
    asl
    sta TrackLength+1
    tya
    rol
    sta TrackLength
    lda #$BF
    and Via1AuxiliaryControl
    sta Via1AuxiliaryControl
.endproc

;; Fallen into from <Format>. Sizes the gap after each data block from `TRAL` (102 bytes a sector plus 256, then the
;; rest shared out). Builds every sector's header in buffer 0 and a zero data block in buffer 2, encodes both, and
;; writes the track, every sector's sync, header, gap, sync and data. Falls into <VerifyTrack>.
;; Also: DS08 (D1541)
.proc WriteTrack
    lda #$66
    sta SectorGap
    ldx SectorCount
    ldy #$00
    tya

;; Adds one sector's 358 bytes to the total.
;; Also: DS10 (D1541)
AddSector:
    clc
    adc SectorGap
    bcc NextSector
    iny

;; Counts a page and the next sector.
;; Also: DS14 (D1541)
NextSector:
    iny
    dex
    bne AddSector
    eor #$FF
    sec
    adc #$00
    clc
    adc TrackLength+1
    bcs SpareHigh
    dec TrackLength

;; The spare's high byte; negative fails with `TOBIG` (4).
;; Also: DS15 (D1541)
SpareHigh:
    tax
    tya
    eor #$FF
    sec
    adc #$00
    clc
    adc TrackLength
    bpl Divide
    lda #FORMAT_TRACK_TOO_SHORT
    jmp FormatError

;; Divides the spare by `SECTR`.
;; Also: DS17 (D1541)
Divide:
    tay
    txa
    ldx #$00

;; Subtracts `SECTR` again.
;; Also: DS20 (D1541)
DivideLoop:
    sec
    sbc SectorCount
    bcs CountQuotient
    dey
    bmi HaveGap

;; Counts the quotient.
;; Also: DS22 (D1541)
CountQuotient:
    inx
    bne DivideLoop

;; `DTRCK` = the gap; under `GAP2` (4) fails with `TOSMAL` (5).
;; Also: DS30 (D1541)
HaveGap:
    stx SectorGap
    cpx #MIN_SECTOR_GAP
    bcs GapOk
    lda #FORMAT_GAP_TOO_SMALL
    jmp FormatError

;; `REMDR` = the remainder.
;; Also: DS32 (D1541)
GapOk:
    clc
    adc SectorCount
    sta GapRemainder
    lda #$00
    sta FormatSector
    ldy #$00
    ldx Drive

;; Sector `SECT`'s header in buffer 0: `HBID`, checksum, sector, track, the two ID bytes and two $0F, 8 bytes each.
;; Also: MAK10 (D1541)
MakeHeader:
    lda HeaderId
    sta Buffer0,y
    iny
    iny
    lda FormatSector
    sta Buffer0,y
    iny
    lda FormatTrack
    sta Buffer0,y
    iny
    lda DiskId+1,x
    sta Buffer0,y
    iny
    lda DiskId,x
    sta Buffer0,y
    iny
    lda #$0F
    sta Buffer0,y
    iny
    sta Buffer0,y
    iny
    lda #$00
    eor Buffer0-6,y
    eor Buffer0-5,y
    eor Buffer0-4,y
    eor Buffer0-3,y
    sta Buffer0-7,y
    inc FormatSector
    lda FormatSector
    cmp SectorCount
    bcc MakeHeader
    tya
    pha
.if DRIVE_1540
    nop
.else
    inx
.endif
    txa

;; Fills buffer 2, the data block every sector gets, from byte X on with A: X and A are DRIVE plus 1, so 1 (the `INX`,
;; `TXA` before it), and the block is bytes of `$01` after byte 0, though the listing's comment says zero; the 1540 has
;; a `NOP` for that `INX` and zeroes all 256 bytes (Q7).
;; Also: CRTDAT (D1541)
FillData:
    sta Buffer2,x
    inx
    bne FillData
    lda #>Buffer0
    sta DataPointer+1
    jsr EncodeHeaders
    pla
    tay
    dey
    jsr ShiftBufferUp
    jsr CopyOverflow
    lda #>Buffer2
    sta DataPointer+1
    jsr BlockChecksum
    sta Checksum
    jsr EncodeBlock
    lda #$00
    sta HeaderPointer
    jsr EraseTrack

;; Writes the next sector, starting with five sync bytes (the listing says 4).
;; Also: WRTSYN (D1541)
WriteSector:
    lda #$FF
    sta DiskData
    ldx #SYNC_LENGTH

;; Waits out the sync bytes.
;; Also: WRTS10 (D1541)
WriteHeaderSync:
    bvc *
    clv
    dex
    bne WriteHeaderSync
    ldx #$0A
    ldy HeaderPointer

;; The header's 10 GCR bytes.
;; Also: WRTS20 (D1541)
WriteHeader:
    bvc *
    clv
    lda Buffer0,y
    sta DiskData
    iny
    dex
    bne WriteHeader
    ldx #HEADER_GAP-2

;; 9 $55 bytes (`GAP1`-2; 8 before 901229-03).
;; Also: WRTS30 (D1541)
WriteHeaderGap:
    bvc *
    clv
    lda #$55
    sta DiskData
    dex
    bne WriteHeaderGap
    lda #$FF
    ldx #SYNC_LENGTH

;; The data block's five sync bytes.
;; Also: DBSYNC (D1541)
WriteDataSync:
    bvc *
    clv
    sta DiskData
    dex
    bne WriteDataSync
    ldx #$BB

;; The 69 GCR bytes in the overflow buffer.
;; Also: WRTS40 (D1541)
WriteOverflow:
    bvc *
    clv
    lda OverflowBuffer,x
    sta DiskData
    inx
    bne WriteOverflow
    ldy #$00

;; The 256 in buffer 2.
;; Also: WRTS50 (D1541)
WriteData:
    bvc *
    clv
    lda (DataPointer),y
    sta DiskData
    iny
    bne WriteData
    lda #$55
    ldx SectorGap

;; `DTRCK` $55 bytes; then the next header, and after the last, back to reading.
;; Also: WGP2 (D1541)
WriteDataGap:
    bvc *
    clv
    sta DiskData
    dex
    bne WriteDataGap
    lda HeaderPointer
    clc
    adc #$0A
    sta HeaderPointer
    dec FormatSector
    bne WriteSector
    bvc *
    clv
    bvc *
    clv
    jsr EndWrite
.endproc

;; Reads the track just written back and compares it with what was written, 200 tries; then the next track, or the end
;; of the format.
.proc VerifyTrack
    lda #$C8
    sta VerifyRetries

;; <VerifyTrack> starts just before, at $FD27, with 200 tries (`TRYS`). Points at the first GCR header in buffer 0 and
;; counts `SECTR` sectors.
;; Also: COMP (D1541)
Restart:
    lda #$00
    sta DataPointer
    lda #>Buffer0
    sta DataPointer+1
    lda SectorCount
    sta FormatSector

;; Waits for a sync.
;; Also: CMPR10 (D1541)
NextHeader:
    jsr WaitForSync
    ldx #$0A
    ldy #$00

;; Compares the 10 GCR bytes with the header written.
;; Also: CMPR15 (D1541)
CompareHeader:
    bvc *
    clv
    lda DiskData
    cmp (DataPointer),y
    bne Mismatch
    iny
    dex
    bne CompareHeader
    clc
    lda DataPointer
    adc #$0A
    sta DataPointer
    jmp CompareData

;; Starts over, and after 200 fails with `NOTFND` (6).
;; Also: CMPR20 (D1541)
Mismatch:
    dec VerifyRetries
    bne Restart
    lda #FORMAT_VERIFY_FAILED
    jmp FormatError

;; Waits for the data block's sync.
;; Also: TSTDAT (D1541)
CompareData:
    jsr WaitForSync
    ldy #$BB

;; Compares the overflow buffer's 69 bytes.
;; Also: TST05 (D1541)
CompareOverflow:
    bvc *
    clv
    lda DiskData
    cmp OverflowBuffer,y
    bne Mismatch
    iny
    bne CompareOverflow
    ldx #$FC

;; Compares buffer 2's bytes, all but the last 4 GCR bytes; the next sector, or the next track (`FTNUM`) and the end of
;; the pass, until track 35.
;; Also: TST10 (D1541)
CompareBuffer:
    bvc *
    clv
    lda DiskData
    cmp Buffer2,y
    bne Mismatch
    iny
    dex
    bne CompareBuffer
    dec FormatSector
    bne NextHeader
    inc FormatTrack
    lda FormatTrack
    cmp #$24
    bcs Finished
    jmp EndPass

;; All 35 tracks: clears `FTNUM` and `GCRFLG` and finishes with 1.
;; Also: FMTEND (D1541)
Finished:
    lda #$FF
    sta FormatTrack
    lda #$00
    sta BufferIsGcr
    lda #$01
    jmp FinishJob
.endproc

;; Writes sync for 10240 bytes, more than a track, and leaves the head writing.
;; Also: SYNCLR (D1541)
.proc EraseWithSync
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl
    lda #$FF
    sta Via2DirectionA
    sta DiskData
    ldx #$28
    ldy #$00

;; Counts the bytes.
;; Also: SYC10 (D1541)
Loop:
    bvc *
    clv
    dey
    bne Loop
    dex
    bne Loop
    rts
.endproc

;; Writes the byte in the port `NUM` times.
;; Also: WRTNUM (D1541)
.proc WriteCount
    ldx SegmentLength
    ldy SegmentLength+1

;; Counts the bytes.
;; Also: WRTN10 (D1541)
Loop:
    bvc *
    clv
    dex
    bne Loop
    dey
    bpl Loop
    rts
.endproc

;; A format error A: while errors are left in `CNT` (10 for the whole format), ends the pass to retry the track; at the
;; last, clears the format and finishes with A.
;; Also: FMTERR (D1541)
.proc FormatError
    dec FormatRetries
    beq GiveUp
    jmp EndPass

;; Clears `FTNUM` and `GCRFLG`, and finishes the job.
;; Also: FMTE10 (D1541)
GiveUp:
    ldy #$FF
    sty FormatTrack
    iny
    sty BufferIsGcr
    jmp FinishJob
.endproc

;; Moves buffer 0's bytes 0 to Y up 69, from the top down.
;; Also: MOVUP (D1541)
.proc ShiftBufferUp
    lda Buffer0,y
    sta Buffer0+69,y
    dey
    bne ShiftBufferUp
    lda Buffer0
    sta Buffer0+69
    rts
.endproc

;; Copies the 69 GCR bytes from the overflow buffer to the start of the buffer at `BUFPNT`.
;; Also: MOVOVR (D1541)
.proc CopyOverflow
    ldy #$44

;; Copies the next byte, from the top.
;; Also: MOVO10 (D1541)
Loop:
    lda $01BB,y
    sta (DataPointer),y
    dey
    bpl Loop
    rts
.endproc

;; Switches the head back to reading and the port to input.
;; Also: KILL (D1541)
.proc EndWrite
    lda Via2PeripheralControl
    ora #$E0
    sta Via2PeripheralControl
    lda #$00
    sta Via2DirectionA
    rts
.endproc

;; Switches to writing and writes $55 for 10240 bytes, more than a track, leaving the head writing.
;; Also: CLEAR (D1541)
.proc EraseTrack
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl
    lda #$FF
    sta Via2DirectionA
    lda #$55
    sta DiskData
    ldx #$28
    ldy #$00

;; Counts the bytes.
;; Also: CLER10 (D1541)
Loop:
    bvc *
    clv
    dey
    bne Loop
    dex
    bne Loop
    rts
.endproc

;; Encodes the buffer at `BUFPNT` (the format's headers) as GCR with no block ID, into the overflow buffer and then the
;; buffer.
;; Also: FBTOG (D1541)
.proc EncodeHeaders
    lda #$00
    sta DataPointer
    sta SavedPointer
    sta ByteIndex
    lda #$BB
    sta GcrIndex
    lda DataPointer+1
    sta SavedPointer+1
    lda #>OverflowBuffer
    sta DataPointer+1

;; Takes the next four bytes and encodes them.
;; Also: FBG10 (D1541)
NextGroup:
    ldy ByteIndex
    lda (SavedPointer),y
    sta BinaryBytes
    iny
    lda (SavedPointer),y
    sta BinaryBytes+1
    iny
    lda (SavedPointer),y
    sta BinaryBytes+2
    iny
    lda (SavedPointer),y
    sta BinaryBytes+3
    iny
    beq LastGroup
    sty ByteIndex
    jsr EncodeGroup
    jmp NextGroup

;; Encodes the last and returns through <EncodeGroup>.
;; Also: FBG15 (D1541)
LastGroup:
    jmp EncodeGroup
.endproc

;; The IRQ handler: saves A, X and Y; ATN (VIA 1's CA1) goes to ATNIRQ, and VIA 2's timer 1 runs a pass of <ScanJobs>.
;; Also: SYSIRQ (D1541)
.proc Interrupt
    pha
    txa
    pha
    tya
    pha
    lda Via1InterruptFlags
    and #$02
    beq CheckTimer
    jsr Serial::AtnInterrupt

;; Tests VIA 2's timer 1 flag.
;; Also: IRQ10 (D1541)
CheckTimer:
    lda Via2InterruptFlags
    asl
    bpl Restore
    jsr ScanJobs

;; Restores Y, X and A, and returns from the interrupt.
;; Also: IRQ20 (D1541)
Restore:
    pla
    tay
    pla
    tax
    pla
    rti
.endproc
.endscope
