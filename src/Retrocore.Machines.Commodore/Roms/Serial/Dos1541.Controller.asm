; retrocore: style=strict
; COMMODORE 1541 DOS: THE DRIVE CONTROLLER ($F259-$FE84)
;
; The controller's side of the job queue. VIA 2's timer 1 interrupts every 58 x 256 cycles, 14.848 ms at 1 MHz, and
; each interrupt runs one pass (ScanJobs): it turns the motor on, steps the head toward a job's track, or serves a job
; on the head's track, finding its sector's header and then reading, writing, verifying or seeking, or running a
; buffer's code, as the format does. A job ends with its result in its queue byte: 1 for success, or 2 to 11 or $0F,
; which the DOS reports as messages 20 to 29 and 74. Each pass ends in EndPass (a jump job's buffer code may return
; without it), which restarts the timer at its first instructions, then runs the motor's timers and the stepper, so the
; next interrupt comes a whole period after that point and every time counted in interrupts here is a minimum.
;
; A sector is two blocks on the disk, each after a sync (ten or more 1 bits, which no run of GCR codes makes). The
; header holds the block ID $08, a checksum, the sector, the track, the disk ID and two padding bytes; the data block
; the block ID $07, 256 bytes, a checksum and two padding bytes. Both are written in GCR (group code recording): each
; nibble as a 5-bit code, so that 4 bytes take 5 and a data block's 260 take 325. A data block's GCR is built in, and
; read into, the job's buffer and the top of the stack page, the overflow buffer.

; The controller's routines and tables; its variables and constants open the scope in Dos1541.Equates.asm.
.scope Controller continued

; The drive's lines in DriveControl, VIA 2's port B.

;; <DriveControl>'s stepper phase, bits 0-1: one up steps the head half a track inward, one down half a track outward.
DRIVE_PHASE = %00000011

;; <DriveControl>'s bit 2, set to run the spindle motor.
DRIVE_MOTOR = %00000100

;; <DriveControl>'s bit 3, the drive's LED.
DRIVE_LED = %00001000

;; <DriveControl>'s bit 4, the write-protect sense: set when the disk can be written, clear when it is protected.
DRIVE_WRITABLE = %00010000

;; <DriveControl>'s bits 5-6, the density: the bit rate for the track's zone, 3 for tracks 1-17 down to 0 for 31-35.
DRIVE_DENSITY = %01100000

; The states in DriveStatus.

;; <DriveStatus>' bit 7: the motor is coming up to speed, and jobs wait for <MotorTimer>.
STATE_SPINNING_UP = %10000000

;; <DriveStatus>' bit 6: the head is stepping, or settling after its steps, and jobs wait.
STATE_STEPPING = %01000000

;; <DriveStatus>' bit 5: the motor is on.
STATE_ON = %00100000

;; <DriveStatus>' bit 4: the motor is running out its timeout, after which it stops.
STATE_TIMING_OUT = %00010000

;; Sets the controller up at start-up, and runs its first pass.
;;
;; VIA 2's port B gets its directions (the stepper, motor, LED and density out; the write-protect sense and sync in),
;; with the motor and the LED off. CA1 takes its falling edge, CA2 goes high, which lets byte-ready set the 6502's V
;; flag (the listing's comment says it disables it), and CB2 high, reading. Timer 1 runs free at <IRQ_PERIOD> x 256
;; cycles, and its interrupt is the only one VIA 2 gives. Then no drive is active, no format is under way, the block IDs
;; are set (<HeaderId> $08, <DataId> $07), and the stepper is at rest (<EndPass::StepIdle>), with
;; <MinimumAccelerationSteps> 200 and <AccelerationSteps> and <AccelerationFactor> 4.
;;
;; It has no `RTS`: it falls into <ScanJobs>, so start-up runs one pass of the controller, which returns.
;; Also: CNTINT (D1541)
.proc Initialize
    ; Port B: the drive's outputs, all off but the density.
    lda #DRIVE_PHASE | DRIVE_MOTOR | DRIVE_LED | DRIVE_DENSITY
    sta Via2DirectionB
    and #$FF - DRIVE_LED - DRIVE_MOTOR - DRIVE_PHASE
    sta DriveControl

    ; The control lines: byte-ready on, and the head reading.
    lda Via2PeripheralControl
    and #$FE                        ; CA1 on its falling edge
    ora #$0E                        ; CA2 high: byte-ready sets V
    ora #$E0                        ; CB2 high: reading
    sta Via2PeripheralControl

    ; Timer 1 running free from its latch, port A latched.
    lda #$41
    sta Via2AuxiliaryControl
    lda #$00
    sta Via2Timer1Latch
    lda #IRQ_PERIOD
    sta Via2Timer1LatchHigh
    sta Via2Timer1High

    ; Timer 1's interrupt, and no other.
    lda #$7F
    sta Via2InterruptEnable
    lda #$C0                        ; timer 1: clears its flag, then enables it
    sta Via2InterruptFlags
    sta Via2InterruptEnable

    ; No drive active and no format under way.
    lda #$FF
    sta ActiveDrive
    sta FormatTrack

    ; The block IDs, and the stepper at rest.
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
    .assert * = ScanJobs, "Initialize has no RTS: it must fall into ScanJobs."
    ; Falls into ScanJobs.
.endproc

;; One pass of the controller, which the timer's interrupt calls: finds a job, and turns the motor on, steps toward the
;; job's track or serves a job on the head's track.
;;
;; It saves the stack pointer for <FinishJob>, which comes back to <ScanJobs::Rescan> after each job so that one pass
;; can serve several, clears the timer's interrupt and lets byte-ready set V. The first pending job (bit 7 of its queue
;; byte set), from job 5 down, decides what happens: a jump job runs its buffer at once; a job for drive 1, which the
;; 1541 does not have, fails; with the motor off, it is turned on; while it spins up or the head steps, nothing.
;; Otherwise the first job for the drive on the head's track, or any while the track is unknown, is served by its type
;; (a bump, an execute job, or <Seek> and the handlers it chains to), and with none there the head is sent toward the
;; track of the lowest-numbered job. Every path ends in <EndPass>, which returns from the pass, or in a buffer's code.
;; In: JobQueue = the jobs, JobHeaders = their tracks and sectors
;; Out: JobQueue = the result codes of the jobs served
;; Errors: a job for drive 1 ends with $0F (message 74, DRIVE NOT READY); the handlers' errors
;; Entry:
;;   Rescan = scans the queue again, as <FinishJob> does after each job
;; Also: LCC (D1541)
.proc ScanJobs
    ; The stack, for FinishJob; the timer's interrupt cleared; byte-ready on.
    tsx
    stx SavedStack
    lda Via2Timer1                  ; reading it clears the interrupt
    lda Via2PeripheralControl
    ora #$0E                        ; CA2 high: byte-ready sets V
    sta Via2PeripheralControl

;; Scans the queue again from job 5 down; <FinishJob> comes back here after each job, with the stack reset.
;; Also: TOP (D1541)
Rescan:
    ldy #JOB_COUNT-1

;; Looks at job Y. A jump job runs its buffer at once, whatever the motor and the head are doing.
;; Also: CONT10 (D1541)
FindJob:
    lda a:JobQueue,y
    bpl NextJob
    cmp #JOB_JUMP
    bne CheckDrive
    tya
    jmp JumpToBuffer

;; A job for drive 1 ends with $0F, no drive (message 74).
;; Also: CONT30 (D1541)
CheckDrive:
    and #$01                        ; the drive
    beq CheckCurrentDrive
    sty JobIndex
    lda #$0F                        ; no drive
    jmp FinishJob

;; With the motor not on for the job's drive (<ActiveDrive>), turns it on and ends the pass, leaving it to spin up.
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

;; Ends the pass while the motor is spinning up or the head is stepping (<DriveStatus>' bits 7 and 6).
;; Also: CONT40 (D1541)
CheckReady:
    lda DriveStatus
    bmi ToEndPass
    asl
    bpl ScanTrack

;; Ends the pass.
;; Also: CONT50 (D1541)
ToEndPass:
    jmp EndPass

;; The next job down; with none pending, ends the pass.
;; Also: CONT20 (D1541)
NextJob:
    dey
    bpl FindJob
    jmp EndPass

;; The motor is up to speed and the head still: <DriveStatus> = on alone, which also ends a timeout under way. Looks at
;; every job, from 5 down, for one on the head's track.
;; Also: QUE (D1541)
ScanTrack:
    lda #STATE_ON
    sta DriveStatus
    ldy #JOB_COUNT-1
    sty JobIndex

;; Loads job <JobIndex>; a pending one is checked.
;; Also: QUE10 (D1541)
ScanTrackNext:
    jsr LoadJob
    bmi CheckTrack

;; The next job down. With none on the head's track, sends the head toward the track of <SeekJob>, the last job found
;; off it, which is the lowest-numbered: <Steps> = twice the distance, in half-tracks, positive inward; <DriveStatus> =
;; stepping; and <HeadTrack> = that track already. The pass ends in <EndPass>, where <EndPass::CheckStepping> runs
;; <EndPass::StepIdle> and takes the first step; the rest follow in the passes after.
;; Also: QUE05 (D1541)
ScanTrackLoop:
    dec JobIndex
    bpl ScanTrackNext
    ldy SeekJob
    jsr LoadJob::JobInY
    lda SeekDistance
    sta Steps
    asl Steps
    lda #STATE_ON | STATE_STEPPING
    sta DriveStatus
    lda (HeaderPointer),y
    sta HeadTrack
    jmp EndPass

;; A job for this drive is on track when the head's track is unknown (0) or is the job's. Otherwise its distance
;; (<SeekDistance>, the job's track less the head's) and its number (<SeekJob>) are kept.
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

;; Serves the job: keeps its track (<JobTrack>), finds the track's zone, which gives <SectorCount> from
;; <SectorsPerTrack> and the density bits, and goes by the job's type.
;; Also: GOTU (D1541)
OnTrack:
    ldx #$04
    lda (HeaderPointer),y
    sta JobTrack

;; Counts X down past each zone limit in <ZoneLimits> the track reaches: X = 3 for tracks 1-17, 2 for 18-24, 1 for 25-30
;; and 0 for 31-35.
;; Also: GOTU10 (D1541)
FindZone:
    cmp ZoneLimits-1,x
    dex
    bcs FindZone
    lda SectorsPerTrack,x
    sta SectorCount

    ; The zone, 0 to 3, is the density, in bits 5-6.
    txa
    asl
    asl
    asl
    asl
    asl
    sta Work
    lda DriveControl
    and #$FF - DRIVE_DENSITY
    ora Work
    sta DriveControl

    ; By the job's type: a bump, an execute job, or one that reads the disk.
    ldx Drive
    lda JobCode
    cmp #JOB_CODE_BUMP
    beq Bump
    cmp #JOB_CODE_EXECUTE
    beq Execute
    jmp Seek

;; An execute job, on its track: runs its buffer's code.
;; Also: EX (D1541)
Execute:
    lda JobIndex

;; Jumps to the start of buffer A (<Buffers> + A x 256). The code there ends the job itself, through <FinishJob>, or
;; ends the pass through <EndPass>.
;; Also: EX2 (D1541)
JumpToBuffer:
    clc
    adc #>Buffers
    sta DataPointer+1
    lda #$00
    sta DataPointer
    jmp (DataPointer)

;; A bump: sets the phase to 0 and the head stepping 92 half-tracks outward (<Steps> = -92), which brings it against the
;; stop at track 1 from anywhere, with <HeadTrack> = 1, and finishes the job with 1 at once; the pass ends in <EndPass>,
;; where <EndPass::CheckStepping> runs <EndPass::StepIdle> and takes the first step, and the rest follow in the passes
;; after.
;; Also: BMP (D1541)
Bump:
    lda #STATE_ON | STATE_STEPPING
    sta DriveStatus
    lda DriveControl
    and #$FF - DRIVE_PHASE
    sta DriveControl
    lda #$A4                        ; -92
    sta Steps
    lda #$01
    sta HeadTrack
    jmp FinishJob
.endproc

;; Loads job <JobIndex>: when it is pending, its type, its header and its buffer.
;;
;; Job n's header is at <JobHeaders> + 2n (the listing's "4/12" patch made headers 2 bytes, track and sector, so there
;; is one `ASL` where there were two) and its buffer at <Buffers> + $100 x n.
;; In: JobIndex = the job, 0 to 5
;; Out: A = its queue byte, negative = pending, Y = 0, DataPointer = 0 in its low byte; when pending, JobCode = its type
;;   ($00 read to $60 execute, the top bit and the drive removed), HeaderPointer = its header, DataPointer+1 = its
;;   buffer's page
;; Keeps: X
;; Entry:
;;   JobInY = the same for job Y, leaving <JobIndex> alone
;; Also: SETJB (D1541)
.proc LoadJob
    ldy JobIndex

;; The same for job Y.
;; Also: SETJB1 (D1541)
JobInY:
    lda a:JobQueue,y
    pha
    bpl Finish

    ; Pending: its type, then its header and buffer.
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

;; Clears <DataPointer>'s low byte and Y, and returns the queue byte.
;; Also: SETJ10 (D1541)
Finish:
    ldy #$00
    sty DataPointer
    pla
    rts
.endproc

;; Serves a job on the head's track that reads the disk: reads headers until one checks, notes the track the head is on,
;; finishes a seek job, and checks the disk's ID for the others, which go on to <ChooseSector>.
;;
;; A write comes back here after it is written, turned into a verify, so the sector is checked when it comes round
;; again. It never returns: every path ends in <FinishJob> or goes on to <ChooseSector>.
;; In: JobCode = the job's type, ActiveDrive = its drive, DiskId = the disk's ID
;; Errors: the job ends with 2 (message 20, READ ERROR) when 90 syncs bring no header, 3 (21) when no sync comes within
;;   20 ms, 9 (27) for a header whose checksum is wrong, and 11 (29, DISK ID MISMATCH) for another disk's ID
;; Entry:
;;   JobDone = finishes the job with 1, success, as <Verify> and <SectorSeek> do
;; Also: SEAK (D1541)
.proc Seek
    ldx #$5A                        ; 90 tries
    stx Scratch
    ldx #$00
    lda #$52                        ; a header's first GCR byte
    sta HeaderGcr

;; Waits for a sync and checks the byte after it for $52, the first GCR byte of a header (its block ID, $08).
;; Also: SEEK10 (D1541)
FindHeader:
    jsr WaitForSync
    bvc *                           ; waits for byte-ready, which sets V
    clv
    lda DiskData
    cmp HeaderGcr
    bne NotHeader

;; Reads the header's next 7 GCR bytes into <HeaderGcr> and decodes them; the last two, the padding's, are not needed.
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

;; The header's ID, track, sector and checksum must give 0 when exclusive-ORed, or the job ends with 9.
;; Also: SEEK30 (D1541)
Checksum:
    eor a:LastHeader,y
    dey
    bpl Checksum
    cmp #$00
    bne HeaderChecksumError

    ; A good header says where the head is.
    ldx ActiveDrive
    lda LastHeader+2
    sta HeadTrack,x

    ; A seek job takes the ID; the others must match it.
    lda JobCode
    cmp #$30                        ; a seek job
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

;; Not a header: tries the next sync, and after 90 ends the job with 2, header not found (<FinishJob> does not return).
;; Also: SEEK20 (D1541)
NotHeader:
    dec Scratch
    bne FindHeader
    lda #$02
    jsr FinishJob

;; A seek job: copies the header's ID into <DiskId> (the listing's "harris fix"), which is how initializing a disk
;; learns its ID, and finishes with 1.
;; Also: ESEEK (D1541)
SeekJob:
    lda LastHeader
    sta DiskId
    lda LastHeader+1
    sta DiskId+1

;; Finishes the job with 1, success.
;; Also: DONE (D1541)
JobDone:
    lda #$01
    .byte OPCODE_BIT                ; skips IdMismatch's LDA, so A stays 1

;; Finishes with 11, the disk's ID mismatched.
;; Also: BADID (D1541)
IdMismatch:
    lda #$0B
    .byte OPCODE_BIT                ; skips HeaderChecksumError's LDA

;; Finishes with 9, a header checksum error.
;; Also: CSERR (D1541)
HeaderChecksumError:
    lda #$09
    jmp FinishJob
.endproc

;; Of the jobs for the active drive on this track, picks the one whose sector comes soonest after <UpcomingSector>, two
;; past the header just read, and serves it through <Read> and the handlers it chains to.
;;
;; A read is taken while its sector is under <READ_DISTANCE> (6) sectors away, and any other type (a write, a verify, a
;; sector seek) only from <WRITE_DISTANCE_MIN> to <WRITE_DISTANCE_MAX> - 1 (9 to 11) away, which leaves time for the
;; buffer to be encoded before its sector comes round. With none in its window, the pass ends, and a later pass tries
;; again. It never returns.
;; In: LastHeader = the header just read, JobTrack = the track, SectorCount = its sectors
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

;; <UpcomingSector> = the header's sector + 2, wrapped; X = $FF, none chosen yet.
;; Also: L460 (D1541)
SetNext:
    sta UpcomingSector
    ldx #JOB_COUNT-1
    stx JobIndex
    ldx #$FF

;; A pending job for this drive and track: its sector's distance from <UpcomingSector>, wrapped. An execute job compares
;; its type, $60, instead, which no window takes, so it is never chosen here.
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

;; Takes the job if it is nearer than the best so far (<BestDistance>) and inside its type's window.
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

;; The best so far: <BestDistance>, X = its job, and its buffer in <DataPointer>, which <Dispatch> sets again.
;; Also: DOITT (D1541)
Best:
    sta BestDistance
    lda JobIndex
    tax
    adc #>Buffers
    sta DataPointer+1
    bne NextJob

;; A read: under <READ_DISTANCE> sectors away.
;; Also: TSTRDJ (D1541)
ReadWindow:
    pla
    cmp #READ_DISTANCE
    bcc Best

;; The next job down; at the end, with none chosen (X = $FF), ends the pass.
;; Also: L470 (D1541)
NextJob:
    dec JobIndex
    bpl CheckJob
    txa
    bpl Dispatch
    jmp EndPass

;; Loads the chosen job and serves it, A = its type.
;; Also: L490 (D1541)
Dispatch:
    stx JobIndex
    jsr LoadJob
    lda JobCode
    jmp Read
.endproc

;; Decodes the header read into <HeaderGcr> into <LastHeader>: the disk's ID, the track, the sector and the checksum.
;;
;; The first 8 GCR bytes are enough: the two after them, which <Seek> does not read, hold only the padding. A code that
;; is not GCR is not caught; it decodes to a wrong byte, which the header's checksum may show.
;; In: HeaderGcr = the header's first 8 GCR bytes
;; Out: LastHeader = the ID (in <DiskId>'s order), the track, the sector and the checksum
;; Keeps: DataPointer
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

;; Serves a job if it is a read, else passes it on to <Write>: reads the sector's data block into the buffer, decodes it
;; and checks it.
;;
;; The block's GCR goes to the buffer (256 bytes) and to the overflow buffer from byte 186 (70, one more than the block
;; has), and <DecodeBlock> makes the buffer's 256 bytes of it. It never returns.
;; In: A = <JobCode>, the job's type; DataPointer = its buffer
;; Errors: the job ends with 4 (message 22, READ ERROR) when the block's ID is not a data block's, 5 (23) when its
;;   checksum is wrong, and with <FindHeader>'s and <WaitForSync>'s errors, 2 (20) and 3 (21)
;; Also: REED (D1541)
.proc Read
    cmp #$00
    beq Start
    jmp Write

;; Finds the sector's header, then the sync of its data block.
;; Also: READ01 (D1541)
Start:
    jsr FindData

;; The first 256 GCR bytes, into the buffer.
;; Also: READ11 (D1541)
ReadBuffer:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    lda DiskData
    sta (DataPointer),y
    iny
    bne ReadBuffer
    ldy #255 - OVERFLOW_SIZE

;; The other 70, into the overflow buffer from byte 186 to the page's end.
;; Also: READ20 (D1541)
ReadOverflow:
    bvc *
    clv
    lda DiskData
    sta OverflowBuffer,y
    iny
    bne ReadOverflow

    ; Decodes it; a block ID other than DataId ends the job with 4.
    jsr DecodeBlock
    lda BlockId
    cmp DataId
    beq CheckBlock
    lda #$04
    jmp FinishJob

;; A data block: compares its checksum with the buffer's, and ends the job with 5 when they differ.
;; Also: READ28 (D1541)
CheckBlock:
    jsr BlockChecksum
    cmp Checksum
    beq ReadOk
    lda #$05
    .byte OPCODE_BIT                ; skips ReadOk's LDA, so A stays 5

;; Finishes the job with 1, success.
;; Also: READ40 (D1541)
ReadOk:
    lda #$01
    jmp FinishJob
.endproc

;; Finds the job's header and then the sync of its data block, ready for the block's first byte.
;; In: HeaderPointer = the job's header, Drive = its drive
;; Out: Y = 0, overflow = clear
;; Errors: the job ends with 2 (message 20, READ ERROR) when no header is found, 3 (21) when no sync comes within 20 ms
;; Also: DSTRT (D1541)
.proc FindData
    jsr FindHeader
    jmp WaitForSync
.endproc

;; Finds the job's header: builds the header it should be, encodes it, and compares the 8 GCR bytes after each sync with
;; it.
;;
;; The 8 bytes hold the block ID, the checksum, the sector, the track, the ID and the first padding byte's high nibble,
;; which is 0 both in the $0F the format writes and in the 0 encoded here.
;; In: HeaderPointer = the job's header (its track and sector), Drive = its drive, DiskId = the drive's disk ID
;; Out: LastHeader = the header, HeaderGcr = the header in GCR, Y = 8, with the head past the 8 bytes
;; Errors: the job ends with 2 (message 20, READ ERROR) when 90 syncs bring no match, and 3 (21) when no sync comes
;;   within 20 ms
;; Entry:
;;   ToFinishJob = ends the job with the code in A, through <FinishJob>
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

    ; The checksum, the exclusive OR of the four.
    lda #$00
    eor LastHeader
    eor LastHeader+1
    eor LastHeader+2
    eor LastHeader+3
    sta LastHeader+4

    ; Encoded, then looked for, 90 syncs at most.
    jsr EncodeHeader
    ldx #$5A                        ; 90 tries

;; Waits for the next sync.
;; Also: SRCH20 (D1541)
NextSync:
    jsr WaitForSync
    ldy #$00

;; Compares the next GCR byte with <HeaderGcr>'s; all 8 alike is the header.
;; Also: SRCH25 (D1541)
Compare:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    lda DiskData
    cmp a:HeaderGcr,y
    bne Mismatch
    iny
    cpy #$08
    bne Compare
    rts

;; Not this header: tries the next sync, and after 90 ends the job with 2.
;; Also: SRCH30 (D1541)
Mismatch:
    dex
    bne NextSync
    lda #$02

;; Ends the job with the code in A; <WaitForSync> branches here on its timeout, with 3.
;; Also: ERR (D1541)
ToFinishJob:
    jmp FinishJob
.endproc

;; Waits for a sync, for up to 20 ms by VIA 1's timer 1; the next byte-ready is then the first byte after it.
;; Out: Y = 0, overflow = clear
;; Errors: the job ends with 3 (message 21, READ ERROR) when no sync comes in time
;; Keeps: X
;; Also: SYNC (D1541)
.proc WaitForSync
    ; VIA 1's timer 1 from $D0xx: its high byte's bit 7 clears about 20 ms later.
    lda #$D0
    sta Via1Timer1High
    lda #$03

;; Polls the timer and the sync line (<DriveControl>'s bit 7, clear during a sync); at the sync, reads the port to clear
;; its latch.
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

;; Serves a job if it is a write, else passes it on to <Verify>: writes the buffer to the sector's data block, then
;; makes the job a verify.
;;
;; It takes the buffer's checksum, fails if the disk is write-protected, encodes the buffer and finds the header. After
;; the header's last 2 GCR bytes and <HEADER_GAP> - 4 bytes of its gap (<FindHeader> returns after 8 of the header's
;; 10), it switches the head to writing and writes the data block's sync (<SYNC_LENGTH> $FF bytes) and its 325 GCR
;; bytes, the overflow buffer's 69 first. Then it switches back to reading, decodes the buffer back to binary, turns the
;; job's queue byte from a write into a verify and goes back to <Seek>, which compares the sector with the buffer when
;; it comes round again. It never returns.
;; In: A = <JobCode>, the job's type; DataPointer = its buffer
;; Errors: the job ends with 8 (message 26, WRITE PROTECT ON) on a protected disk, and with <FindHeader>'s and
;;   <WaitForSync>'s errors, 2 (20) and 3 (21)
;; Also: WRIGHT (D1541)
.proc Write
    cmp #$10
    beq WriteJob
    jmp Verify

;; <Checksum> = the buffer's checksum; a write-protected disk ends the job with 8.
;; Also: WRT05 (D1541)
WriteJob:
    jsr BlockChecksum
    sta Checksum
    lda DriveControl
    and #DRIVE_WRITABLE
    bne NotProtected
    lda #$08
    jmp FinishJob

;; Encodes the buffer and finds the header.
;; Also: WRT10 (D1541)
NotProtected:
    jsr EncodeBlock
    jsr FindHeader
    ldx #HEADER_GAP-2

;; Counts <HEADER_GAP> - 2 byte-readies (9 from 901229-03 on, 8 in -01, -02 and the 1540), which are the header's last 2
;; GCR bytes and <HEADER_GAP> - 4 of the gap's bytes, then switches VIA 2's port A to output and the head to writing,
;; and starts the sync. The format writes the gap as <HEADER_GAP> - 2 bytes (<WriteTrack::WriteHeaderGap>), so the data
;; block's sync starts 2 bytes before the gap ends.
;; Also: WRT20 (D1541)
SkipGap:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    dex
    bne SkipGap

    ; Port A out, and CB2 low: the head writes.
    lda #$FF
    sta Via2DirectionA
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl

    ; The sync's first byte.
    lda #$FF
    ldx #SYNC_LENGTH
    sta DiskData
    clv

;; The sync, <SYNC_LENGTH> $FF bytes.
;; Also: WRTSNC (D1541)
WriteSync:
    bvc *
    clv
    dex
    bne WriteSync
    ldy #256 - OVERFLOW_SIZE

;; The 69 GCR bytes in the overflow buffer, from byte 187, first.
;; Also: WRT30 (D1541)
WriteOverflow:
    lda OverflowBuffer,y
    bvc *
    clv
    sta DiskData
    iny
    bne WriteOverflow

;; Then the 256 in the buffer. When the last has gone, back to reading; the buffer is decoded, and the job made a
;; verify.
;; Also: WRT40 (D1541)
WriteBuffer:
    lda (DataPointer),y
    bvc *
    clv
    sta DiskData
    iny
    bne WriteBuffer

    ; Waits for the last byte to go out; then CB2 high and port A in, reading.
    bvc *
    lda Via2PeripheralControl
    ora #$E0
    sta Via2PeripheralControl
    lda #$00
    sta Via2DirectionA

    ; The buffer back to binary, and the job a verify ($90 to $A0, the drive bit kept).
    jsr DecodeWriteImage
    ldy JobIndex
    lda a:JobQueue,y
    eor #$30                        ; a write becomes a verify
    sta a:JobQueue,y
    jmp Seek
.endproc

;; Computes the checksum of the buffer at <DataPointer>: the exclusive OR of its 256 bytes.
;; In: DataPointer = the buffer
;; Out: A = the checksum, Y = 0
;; Keeps: X
;; Also: CHKBLK (D1541)
.proc BlockChecksum
    lda #$00
    tay

;; Takes in the next byte.
;; Also: CHKB10 (D1541)
Loop:
    eor (DataPointer),y
    iny
    bne Loop
    rts
.endproc

;; Decodes a buffer left as a write image, by <EncodeBlock>, back to its 256 bytes, in place.
;;
;; The image is the overflow buffer's 69 GCR bytes and then the buffer's 256. The first bytes decoded fill the overflow
;; buffer behind the GCR being read, and the rest the buffer's start; then the buffer's part moves up 69 bytes and the
;; overflow buffer's is copied in below it, so the bytes are in order. The checksum and the padding are dropped, and
;; nothing is checked.
;; In: DataPointer+1 = the buffer's page
;; Out: BlockId = the block ID, BufferIsGcr = 0, DataPointer = the buffer
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
    lda #256 - OVERFLOW_SIZE
    sta GcrIndex
    sta ByteIndex

    ; The first group: the block ID and the first three bytes.
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

;; Decodes groups into the overflow buffer until its index passes the page's end.
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

;; The group that crosses into the buffer: its last two bytes go to the buffer's start.
;; Also: WTOB50 (D1541)
CrossToBuffer:
    lda BinaryBytes+2
    sta (DataPointer),y
    iny
    lda BinaryBytes+3
    sta (DataPointer),y
    iny
    sty ByteIndex

;; Decodes groups into the buffer, until 187 bytes are there.
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
    cpy #256 - OVERFLOW_SIZE
    bcc NextBufferGroup

    ; The buffer's 187 bytes go up 69, to the end.
    lda #OVERFLOW_SIZE
    sta SavedPointer
    lda DataPointer+1
    sta SavedPointer+1
    ldy #256 - OVERFLOW_SIZE - 1

;; Moves the buffer's bytes 0 to 186 up 69, from the top down, making room below them.
;; Also: WTOB55 (D1541)
MoveUp:
    lda (DataPointer),y
    sta (SavedPointer),y
    dey
    bne MoveUp
    lda (DataPointer),y
    sta (SavedPointer),y
    ldx #256 - OVERFLOW_SIZE

;; Copies the 69 bytes in the overflow buffer to the buffer's start, and clears <BufferIsGcr> (X is 0).
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

;; Serves a job if it is a verify, else passes it on to <SectorSeek>: compares the sector's data block with the buffer
;; encoded.
;;
;; It compares the overflow buffer's 69 GCR bytes and the buffer's first 253, all but the last three, which hold the
;; padding and the end of the checksum's code. A write becomes a verify, so this is how a write is checked. The buffer
;; is left in GCR, for <FinishJob> to decode. It never returns.
;; In: A = <JobCode>, the job's type; DataPointer = its buffer
;; Errors: the job ends with 7 (message 25, WRITE ERROR) at a difference, and with <FindHeader>'s and <WaitForSync>'s
;;   errors, 2 (20) and 3 (21)
;; Also: VRFY (D1541)
.proc Verify
    cmp #$20
    beq VerifyJob
    jmp SectorSeek

;; Takes the checksum, encodes the buffer, and finds the data block.
;; Also: VRF10 (D1541)
VerifyJob:
    jsr BlockChecksum
    sta Checksum
    jsr EncodeBlock
    jsr FindData
    ldy #256 - OVERFLOW_SIZE

;; Compares the overflow buffer's 69 bytes.
;; Also: VRF15 (D1541)
CompareOverflow:
    lda OverflowBuffer,y
    bvc *                           ; waits for byte-ready, which sets V
    clv
    eor DiskData
    bne Mismatch
    iny
    bne CompareOverflow

;; Then the buffer's, up to byte 252; all alike, the job finishes with 1.
;; Also: VRF30 (D1541)
CompareBuffer:
    lda (DataPointer),y
    bvc *
    clv
    eor DiskData
    bne Mismatch
    iny
    cpy #$FD                        ; not the last three
    bne CompareBuffer
    jmp Seek::JobDone

;; Finishes with 7, a verify error.
;; Also: VRF20 (D1541)
Mismatch:
    lda #$07
    jmp FinishJob
.endproc

;; Serves the job types left, a sector seek: finds the job's header and finishes with 1. It never returns.
;; Errors: those of <FindHeader> and <WaitForSync>, 2 (message 20) and 3 (21)
;; Also: SECTSK (D1541)
.proc SectorSeek
    jsr FindHeader
    jmp Seek::JobDone
.endproc

;; Encodes the 4 bytes in <BinaryBytes> as 5 GCR bytes in the buffer at <DataPointer>, from <GcrIndex>, each nibble as
;; its code from <GcrCodes>.
;;
;; When the index passes the page's end after the fourth byte, the fifth goes to <SavedPointer>'s page. The write
;; images' layout, 69 bytes at the top of the overflow buffer, makes that the only place a group crosses.
;; In: BinaryBytes = the 4 bytes, DataPointer = the buffer, GcrIndex = the index of the first GCR byte, SavedPointer+1 =
;;   the page to go on in
;; Out: GcrIndex = the index after the group
;; Also: PUT4BG (D1541)
.proc EncodeGroup
    lda #$00
    sta GcrGroup+1
    sta GcrGroup+4
    ldy GcrIndex

    ; GCR byte 1: the first code and the second's first 3 bits.
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

    ; Byte 2: the second code's last 2 bits, the third code and the fourth's first bit.
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

    ; Byte 3: the fourth code's last 4 bits and the fifth's first 4.
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

    ; Byte 4: the fifth code's last bit, the sixth code and the seventh's first 2 bits.
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

;; The fifth GCR byte, in <SavedPointer>'s page if the index passed the end: the seventh code's last 3 bits and the
;; eighth code.
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

;; The 16 five-bit GCR codes, by the nibble they stand for.
;;
;; In any run of them, no more than two 0 bits come together and no more than eight 1 bits, so the read logic always
;; sees a change of the magnetic flux soon enough and no byte reads as a sync (ten 1 bits or more).
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

;; Encodes the buffer at <DataPointer> as a data block's write image: the block ID (<DataId>), the 256 bytes, <Checksum>
;; and two padding 0s, 260 bytes as 325 GCR bytes, 69 in the overflow buffer from byte 187 and 256 in the buffer itself.
;;
;; It works in place, the GCR filling the buffer behind the bytes still to be read. <BufferIsGcr> is set, so that
;; <FinishJob> decodes the buffer again.
;; In: DataPointer+1 = the buffer's page, Checksum = the buffer's checksum
;; Out: BufferIsGcr = nonzero, DataPointer = the buffer
;; Also: BINGCR (D1541)
.proc EncodeBlock
    lda #$00
    sta DataPointer
    sta SavedPointer
    sta ByteIndex
    lda #256 - OVERFLOW_SIZE
    sta GcrIndex
    sta BufferIsGcr
    lda DataPointer+1
    sta SavedPointer+1
    lda #>OverflowBuffer
    sta DataPointer+1

    ; The first group: the block ID and the buffer's first three bytes.
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

;; Encodes the four bytes taken and takes the next four, until the buffer's last.
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

;; The last group, the buffer's last byte, the checksum and two 0s, encoded by <EncodeGroup>, which returns.
;; Also: BING20 (D1541)
Trailer:
    lda Checksum
    sta BinaryBytes+1
    lda #$00
    sta BinaryBytes+2
    sta BinaryBytes+3
    jmp EncodeGroup
.endproc

;; Decodes 5 GCR bytes in the buffer at <DataPointer>, from <GcrIndex>, into the 4 bytes in <BinaryBytes>.
;;
;; It splits the 40 bits into eight 5-bit codes in <GcrGroup> and looks them up in <GcrHighNibbles> and <GcrLowNibbles>.
;; A code that is not GCR gives $FF, ORed into the byte, and is not reported: only a checksum shows it (the listing's
;; GCRERR is never set). When the index passes the page's end, after the first byte or the fourth (the read and write
;; images' layouts make those the only places), it goes on in <NextPage> from <NextIndex>.
;; In: DataPointer = the buffer, GcrIndex = the index of the first GCR byte, NextPage/NextIndex = where to go on
;; Out: BinaryBytes = the 4 bytes, GcrIndex = the index after the group
;; Also: GET4GB (D1541)
.proc DecodeGroup
    ldy GcrIndex

    ; GCR byte 1: the first code and the second's first 3 bits.
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

;; The second GCR byte, in <NextPage> if the index passed the end: the second code's last 2 bits, the third code and the
;; fourth's first bit.
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

    ; Byte 3: the fourth code's last 4 bits and the fifth's first 4.
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

    ; Byte 4: the fifth code's last bit, the sixth code and the seventh's first 2 bits.
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

;; The fifth, likewise: the seventh code's last 3 bits and the eighth code. Then each pair of codes makes a byte.
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

    ; Each pair of codes, high nibble and low, makes a byte.
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

;; For each 5-bit code, the nibble it stands for in a byte's high half; $FF for the 16 codes that are not GCR, which
;; decode to a wrong byte unnoticed.
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

;; For each 5-bit code, the nibble it stands for in a byte's low half; $FF for the codes that are not GCR.
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

;; Decodes a data block's read image into the buffer: the buffer's 256 GCR bytes and the overflow buffer's from byte
;; 186, back to the block ID, the 256 bytes and the checksum.
;;
;; It works in place, each byte behind the GCR being read, and stops at the checksum, so the padding and the last GCR
;; byte read are left alone. Nothing checks the codes; <Read> checks the block ID and the checksum.
;; In: DataPointer+1 = the buffer's page
;; Out: BlockId = the block ID, Checksum = the checksum read, DataPointer+1 = the buffer's page
;; Also: GCRBIN (D1541)
.proc DecodeBlock
    lda #$00
    sta GcrIndex
    sta SavedPointer
    sta ByteIndex
    lda #>OverflowBuffer
    sta NextPage
    lda #255 - OVERFLOW_SIZE
    sta NextIndex
    lda DataPointer+1
    sta SavedPointer+1

    ; The first group: the block ID and the first three bytes.
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

;; Decodes the next group into the buffer, until its last byte.
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

;; Keeps the checksum, the last group's second byte, and points <DataPointer> back at the buffer.
;; Also: GCRB20 (D1541)
Finish:
    lda BinaryBytes+1
    sta Checksum
    lda SavedPointer+1
    sta DataPointer+1
    rts
.endproc

;; Encodes <LastHeader> as a header's GCR in <HeaderGcr>, for <FindHeader> to compare: the block ID (<HeaderId>), the
;; checksum, the sector, the track, the ID's two bytes (its second first) and two 0s, 8 bytes as 10.
;; In: LastHeader = the ID, the track, the sector and the checksum; DataPointer = 0 in its low byte
;; Keeps: DataPointer
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

;; Ends job <JobIndex> with the code in A, then scans the queue again; it never returns.
;;
;; The code replaces the job's queue byte: 1 for success, 2 to 11 and $0F for errors, which the DOS reports as messages
;; 20 to 29 and 74. A buffer left in GCR (<BufferIsGcr>) is decoded back first. The motor's timeout starts, and the
;; stack goes back to where <ScanJobs> found it, which drops whatever the job's handler had pushed, before
;; <ScanJobs::Rescan>.
;; In: A = the result code, JobIndex = the job, DataPointer = its buffer
;; Also: ERRR (D1541)
.proc FinishJob
    ; The result replaces the job; a buffer left in GCR is decoded.
    ldy JobIndex
    sta a:JobQueue,y
    lda BufferIsGcr
    beq Restart
    jsr DecodeWriteImage

;; Starts the motor's timeout, resets the stack and scans the queue again.
;; Also: ERRR10 (D1541)
Restart:
    jsr MotorTimeout
    ldx SavedStack
    txs
    jmp ScanJobs::Rescan
.endproc

;; Turns the motor on: <DriveStatus> = on and spinning up, and <MotorTimer> = 60 interrupts, at least 0.89 s, before
;; jobs are served (the listing's comment says 1.5 s).
;; Keeps: X, Y
;; Also: TURNON (D1541)
.proc MotorOn
    lda #STATE_ON | STATE_SPINNING_UP
    sta DriveStatus
    lda DriveControl
    ora #DRIVE_MOTOR
    sta DriveControl
    lda #$3C                        ; 60 interrupts
    sta MotorTimer
    rts
.endproc

;; Starts the motor's timeout: sets <DriveStatus>' timing-out bit and <MotorTimer> = 255. <FinishJob> calls this inside
;; a pass whose <EndPass> already counts it down, so the motor stops 254 interrupts later, at least 3.77 s (254 x 14.848
;; ms), unless a job comes first.
;;
;; <MotorOffVector>, the ROM's word at $FFE8, points here. Its load of <ActiveDrive> into X is left from the dual drive;
;; nothing uses it.
;; Out: X = <ActiveDrive>
;; Keeps: Y
;; Also: TRNOFF (D1541)
.proc MotorTimeout
    ldx ActiveDrive                 ; left from the dual drive
    lda DriveStatus
    ora #STATE_TIMING_OUT
    sta DriveStatus
    lda #$FF                        ; 255 interrupts
    sta MotorTimer
    rts
.endproc

;; Ends each pass of the controller, and returns from it.
;;
;; It restarts the timer, so the next interrupt comes <IRQ_PERIOD> x 256 cycles (14.848 ms) from here and every time
;; counted in passes is a minimum. It notes a change of the write-protect sense in <DiskChanged> (a disk going in or
;; out), and takes a half-track step the DOS asks for in <StepRequest> (<Jobs::StepHead>). With the motor on, it counts
;; down the spin-up or the timeout, stopping the motor at the timeout's end, and runs the stepper's state in
;; <StepperState>. Last it turns byte-ready off and returns to <ScanJobs>' caller.
;; Entry:
;;   StepIdle = the stepper's state at rest, which <Initialize> sets
;; Also: END (D1541)
.proc EndPass
    ; The next interrupt a whole period from here.
    lda Via2Timer1LatchHigh
    sta Via2Timer1High

    ; A change of the write-protect sense is a disk going in or out.
    lda DriveControl
    and #DRIVE_WRITABLE
    cmp LastWriteProtect
    sta LastWriteProtect
    beq CheckHeadOffset
    lda #$01
    sta DiskChanged

;; A step the DOS asked for: 1 (in) or $FF (out) in <StepRequest> is taken now and answered with 2, which
;; <Jobs::StepHead> waits for; a 2 still there at the next pass is cleared to 0, as the DOS clears it too.
;; Also: END002 (D1541)
CheckHeadOffset:
    lda StepRequest
    beq CheckMotor
    cmp #$02
    bne OffsetStep
    lda #$00
    sta StepRequest
    beq CheckMotor

;; <Steps> = the step, and <StepRequest> = 2, taken.
;; Also: END003 (D1541)
OffsetStep:
    sta Steps
    lda #$02
    sta StepRequest
    jmp Step

;; Nothing more without an active drive, or while the motor is only on, with no spin-up, timeout or step.
;; Also: END40 (D1541)
CheckMotor:
    ldx ActiveDrive
    bmi ToDone
    lda DriveStatus
    tay
    cmp #STATE_ON
    bne CountDown

;; Ends the pass.
;; Also: END33X (D1541)
ToDone:
    jmp Done

;; Counts <MotorTimer> down; at 0 the spin-up, or the timeout, is over.
;; Also: END10 (D1541)
CountDown:
    dec MotorTimer
    bne CheckStepping
    tya
    bpl CheckTimeout
    and #$FF - STATE_SPINNING_UP
    sta DriveStatus

;; At the end of a timeout: the motor off, no active drive, and <DriveStatus> = 0.
;; Also: END20 (D1541)
CheckTimeout:
    and #STATE_TIMING_OUT
    beq CheckStepping
    lda DriveControl
    and #$FF - DRIVE_MOTOR
    sta DriveControl
    lda #$FF
    sta ActiveDrive
    lda #$00
    sta DriveStatus
    beq ToDone

;; Runs the stepper only while <DriveStatus> says it is stepping.
;; Also: END30 (D1541)
CheckStepping:
    tya
    and #STATE_STEPPING
    bne RunStepState
    jmp Done

;; Jumps to the stepper's state, <StepperState>.
;; Also: END30X (D1541)
RunStepState:
    jmp (StepperState)

;; The stepper's state at rest, which starts a move: one shorter than <MinimumAccelerationSteps> takes a step each pass
;; (<StepShort>), and a longer one would be accelerated. That never happens with the ROM's settings: <Steps> is a signed
;; byte, so a move is at most 128 half-tracks, and <MinimumAccelerationSteps> is 200, unless a program lowers it.
;; Also: INACT (D1541)
StepIdle:
    lda Steps
    bpl CheckDistance
    eor #$FF
    clc
    adc #$01

;; Compares the move's length with <MinimumAccelerationSteps>.
;; Also: INAC10 (D1541)
CheckDistance:
    cmp MinimumAccelerationSteps
    bcs Accelerated
    lda #<StepShort
    sta StepperState
    lda #>StepShort
    sta StepperState+1
    bne Step

;; <RunSteps> = the length less twice <AccelerationSteps>, and <StepCountdown> = <AccelerationSteps>; the next state is
;; <StepAccelerate>.
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

;; One half-track step toward <Steps>' sign, counting it: the phase up, inward, for a positive count (<StepIn>), and
;; down, outward, for a negative one (the listing's STPOUT, not referenced).
;; Also: DOSTEP (D1541)
Step:
    lda Steps
    bpl StepIn
    inc Steps
    ldx DriveControl
    dex
    jmp SetPhase

;; A step each pass until <Steps> is 0, then the settle: 5 passes, at least 74 ms (the listing's comment says 40 ms).
;; Also: SHORT (D1541)
StepShort:
    lda Steps
    bne Step
    lda #<StepSettle
    sta StepperState
    lda #>StepSettle
    sta StepperState+1
    lda #$05                        ; 5 passes to settle
    sta StepCountdown
    jmp Done

;; Counts the settle down, then clears <DriveStatus>' stepping bit and goes back to <StepIdle>.
;; Also: SETLE (D1541)
StepSettle:
    dec StepCountdown
    bne Done
    lda DriveStatus
    and #$FF - STATE_STEPPING
    sta DriveStatus
    lda #<StepIdle
    sta StepperState
    lda #>StepIdle
    sta StepperState+1
    jmp Done

;; One step inward: counts <Steps> down and moves the phase up.
;; Also: STPIN (D1541)
StepIn:
    dec Steps
    ldx DriveControl
    inx

;; Puts X's low two bits in <DriveControl>'s phase bits.
;; Also: STP (D1541)
SetPhase:
    txa
    and #DRIVE_PHASE
    sta Scratch
    lda DriveControl
    and #$FF - DRIVE_PHASE
    ora Scratch
    sta DriveControl
    jmp Done

;; Accelerating: shortens the wait for the next interrupt by <AccelerationFactor> x 256 cycles and steps,
;; <AccelerationSteps> times; then <StepRun>. Never reached with the ROM's <MinimumAccelerationSteps>.
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

;; Takes a step.
;; Also: SSA10 (D1541)
ToStep:
    jmp Step

;; Steps once a pass, <RunSteps> times; then <StepDecelerate>.
;; Also: SSRUN (D1541)
StepRun:
    dec RunSteps
    bne ToStep
    lda #<StepDecelerate
    sta StepperState
    lda #>StepDecelerate
    sta StepperState+1
    bne ToStep

;; Decelerating: lengthens the wait by <AccelerationFactor> x 256 cycles and steps, <AccelerationSteps> times; then the
;; settle.
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
    lda #$05                        ; 5 passes to settle
    sta StepCountdown

;; Turns byte-ready off (CA2 low) and returns from the pass.
;; Also: END33 (D1541)
Done:
    lda Via2PeripheralControl
    and #$FD                        ; CA2 low: byte-ready off
    sta Via2PeripheralControl
    rts
.endproc

;; The format, run as an execute job on buffer 3 (<Commands::Format> puts a `JMP` to it at $0600), on each pass where
;; the job's header track is the head's track and the head is still (while the head steps, <ScanJobs> ends the pass at
;; <ScanJobs::CheckReady>), a track at a time, until it finishes; <FormatTrack> says where it has got to.
;;
;; The first time (<FormatTrack> negative) it bumps the head to track 1, allows 10 errors for the whole format
;; (<FormatRetries>), starts the track's measuring at 4000 bytes (<SegmentLength>) and ends the pass. After that it
;; sends the head to <FormatTrack> by putting it in the job's header, and once there it fails on a write-protected disk,
;; then erases and measures the track. It writes <SegmentLength> bytes of sync and as many of $55, times the two with
;; VIA 1's timer 1 at 100 microseconds, and adjusts <SegmentLength> until they match, half the track each; then it
;; counts the bytes of the $55 half, so that <TrackLength> is the track's length in bytes. Falls into <WriteTrack>.
;; In: JobIndex = 3, HeaderPointer = the job's header, Drive = the drive
;; Errors: through <FormatError>, 8 on a write-protected disk, <FORMAT_NO_SYNC> when a segment does not end and
;;   <FORMAT_TRACK_TOO_LONG> when the count passes 65535; the job ends with 3 (message 21) when no sync comes in time
;; Also: FORMT (D1541)
.proc Format
    ; The first time, a bump to track 1, and the format's error count and first length.
    lda FormatTrack
    bpl Started
    ldx Drive
    lda #STATE_ON | STATE_STEPPING
    sta DriveStatus,x
    lda #$01
    sta HeadTrack,x
    sta FormatTrack
    lda #$A4                        ; -92
    sta Steps
    lda DriveControl
    and #$FF - DRIVE_PHASE
    sta DriveControl
    lda #$0A                        ; 10 errors
    sta FormatRetries
    lda #<4000
    sta SegmentLength
    lda #>4000
    sta SegmentLength+1
    jmp EndPass

;; Puts <FormatTrack> in the job's header, so that <ScanJobs> steps there, and ends the pass, unless the head is there.
;; Also: L213 (D1541)
Started:
    ldy #$00
    cmp (HeaderPointer),y
    beq OnTrack
    sta (HeaderPointer),y
    jmp EndPass

;; On the track: a write-protected disk is format error 8.
;; Also: L214 (D1541)
OnTrack:
    lda DriveControl
    and #DRIVE_WRITABLE
    bne MeasureTrack
    lda #$08
    jmp FormatError

;; Fills the track with sync, then writes <SegmentLength> bytes of sync and as many of $55, and starts VIA 1's timer 1
;; running free at 100 microseconds.
;; Also: TOPP (D1541)
MeasureTrack:
    jsr EraseWithSync
    jsr WriteCount
    lda #$55
    sta DiskData
    jsr WriteCount
    jsr EndWrite
    jsr WaitForSync

    ; VIA 1's timer 1 running free, 100 cycles a tick ($62 + 2).
    lda #$40                        ; free-running
    ora Via1AuxiliaryControl
    sta Via1AuxiliaryControl
    lda #$62
    sta Via1Timer1Latch
    lda #$00
    sta Via1Timer1LatchHigh
    sta Via1Timer1High
    ldy #$00
    ldx #$00

;; Waits for a sync...
;; Also: FWAIT (D1541)
WaitSync:
    bit DriveControl
    bmi WaitSync

;; ...and for its end, the start of the $55 segment.
;; Also: FWAIT2 (D1541)
WaitData:
    bit DriveControl
    bpl WaitData

;; Counts the $55 segment's ticks in X and Y, until a sync; 65536 ticks is format error <FORMAT_NO_SYNC>.
;; Also: F000 (D1541)
NextDataTick:
    lda Via1Timer1

;; Waits for the next tick, or the sync that ends the segment.
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

;; <Temporary2> = the $55 segment's ticks; then it counts the sync's.
;; Also: F005 (D1541)
TimeSync:
    stx Temporary2
    sty Temporary2+1
    ldx #$00
    ldy #$00

;; Counts the sync's ticks until it ends; 65536 is <FORMAT_NO_SYNC> too.
;; Also: F006 (D1541)
NextSyncTick:
    lda Via1Timer1

;; Waits for the next tick, or the sync's end.
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

;; <Temporary1> = the sync's ticks less the $55 segment's, and X and Y = its size.
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

;; Under 4 ticks apart, 400 microseconds, is close enough.
;; Also: F013 (D1541)
CheckClose:
    tya
    bne Adjust
    cpx #$04
    bcc CountBytes

;; Otherwise <SegmentLength> gets twice the difference added (the listing's comment says half), and the track is
;; measured again.
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

;; Counts the bytes of the $55 segment by their byte-readys, until the sync; 65536 is format error
;; <FORMAT_TRACK_TOO_LONG>.
;; Also: COUNT (D1541)
CountBytes:
    ldx #$00
    ldy #$00
    clv

;; Counts a byte.
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

;; <TrackLength> = twice the count, the track's length in bytes, its high byte first; VIA 1's timer 1 goes back to one
;; shot.
;; Also: CNT20 (D1541)
Counted:
    txa
    asl
    sta TrackLength+1
    tya
    rol
    sta TrackLength
    lda #$BF                        ; one shot again
    and Via1AuxiliaryControl
    sta Via1AuxiliaryControl
    .assert * = WriteTrack, "Format must fall into WriteTrack."
    ; Falls into WriteTrack.
.endproc

;; Writes the track <Format> measured: sizes the gap after each sector, builds every sector's header and one data block,
;; and writes them all, from wherever the disk is. Falls into <VerifyTrack>.
;;
;; Each sector is counted as 358 bytes (256 + $66, where the listing's comment works out 85) besides the gap after it, a
;; few more than its syncs, header, header gap and data block take. The gap is what <TrackLength> leaves over them,
;; shared out, and must be at least <MIN_SECTOR_GAP>. The headers are built in buffer 0, 8 bytes each, and the data
;; block in buffer 2 (<WriteTrack::FillData>); both are encoded, the headers' GCR gathered at buffer 0's start, 10 bytes
;; each. The track is written as $55 for more than a turn, then straight on, each sector: a sync, the header, the
;; header's gap, a sync, the data block and the gap.
;; In: TrackLength = the track's length in bytes, SectorCount = its sectors, FormatTrack = the track, DiskId = the ID
;; Errors: through <FormatError>, <FORMAT_TRACK_TOO_SHORT> when the sectors do not fit and <FORMAT_GAP_TOO_SMALL> when
;;   the gap is under <MIN_SECTOR_GAP>
;; Also: DS08 (D1541)
.proc WriteTrack
    ; The bytes the sectors take, 358 each: Y pages and A bytes.
    lda #$66                        ; 102, and a page
    sta SectorGap
    ldx SectorCount
    ldy #$00
    tya

;; Adds a sector's 358 bytes to the total in Y and A: 102 here...
;; Also: DS10 (D1541)
AddSector:
    clc
    adc SectorGap
    bcc NextSector
    iny

;; ...and a page; then the next sector. The spare is then <TrackLength> less the total.
;; Also: DS14 (D1541)
NextSector:
    iny
    dex
    bne AddSector

    ; The spare, the track's length less that, low byte first.
    eor #$FF
    sec
    adc #$00
    clc
    adc TrackLength+1
    bcs SpareHigh
    dec TrackLength

;; The spare's high byte; less than nothing is format error <FORMAT_TRACK_TOO_SHORT>.
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

;; Divides the spare by <SectorCount>, the quotient in X.
;; Also: DS17 (D1541)
Divide:
    tay
    txa
    ldx #$00

;; Takes <SectorCount> off again.
;; Also: DS20 (D1541)
DivideLoop:
    sec
    sbc SectorCount
    bcs CountQuotient
    dey
    bmi HaveGap

;; Counts it.
;; Also: DS22 (D1541)
CountQuotient:
    inx
    bne DivideLoop

;; <SectorGap> = the quotient, the gap after each data block; under <MIN_SECTOR_GAP> is format error
;; <FORMAT_GAP_TOO_SMALL>.
;; Also: DS30 (D1541)
HaveGap:
    stx SectorGap
    cpx #MIN_SECTOR_GAP
    bcs GapOk
    lda #FORMAT_GAP_TOO_SMALL
    jmp FormatError

;; <GapRemainder> = the remainder, which nothing reads; then the headers, from sector 0.
;; Also: DS32 (D1541)
GapOk:
    clc
    adc SectorCount
    sta GapRemainder
    lda #$00
    sta FormatSector
    ldy #$00
    ldx Drive

;; Sector <FormatSector>'s header in buffer 0, 8 bytes: <HeaderId>, the checksum, the sector, the track, the ID's two
;; bytes (the second first) and two $0F; the checksum is the exclusive OR of the four between.
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

    ; The checksum, into the header's second byte.
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

    ; The headers' length, for ShiftBufferUp; then the data block.
    tya
    pha
.if DRIVE_1540
    ; The 1540: X stays the drive, 0, so the whole block is 0s.
    nop
.else
    ; The 1541: X and A are the drive plus 1, so the block is $01s after its first byte.
    inx
.endif
    txa

;; Fills buffer 2, the data block every sector gets, from byte X to the end with A: in the 1541 bytes 1 to 255 with $01,
;; though the listing's comment says zero, leaving byte 0 as it was; in the 1540 all 256 with 0.
;; Also: CRTDAT (D1541)
FillData:
    sta Buffer2,x
    inx
    bne FillData

    ; The headers to GCR: the first 69 bytes land in the overflow buffer, so the rest
    ; move up 69 and those are copied in below them, 10 bytes a header from the start.
    lda #>Buffer0
    sta DataPointer+1
    jsr EncodeHeaders
    pla
    tay
    dey
    jsr ShiftBufferUp
    jsr CopyOverflow

    ; The data block to GCR, its checksum first.
    lda #>Buffer2
    sta DataPointer+1
    jsr BlockChecksum
    sta Checksum
    jsr EncodeBlock

    ; Then the track is erased with $55, and written from sector 0's header.
    lda #$00
    sta HeaderPointer
    jsr EraseTrack

;; Writes the next sector, starting with its header's sync, <SYNC_LENGTH> bytes (the listing's comment says 4).
;; Also: WRTSYN (D1541)
WriteSector:
    lda #$FF
    sta DiskData
    ldx #SYNC_LENGTH

;; Waits out the sync's bytes.
;; Also: WRTS10 (D1541)
WriteHeaderSync:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    dex
    bne WriteHeaderSync
    ldx #$0A                        ; a header's 10 GCR bytes
    ldy HeaderPointer

;; The header's 10 GCR bytes, from buffer 0 at <HeaderPointer>.
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

;; The header's gap, <HEADER_GAP> - 2 bytes of $55 (9 from 901229-03 on, 8 in -01, -02 and the 1540).
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

;; The data block's sync.
;; Also: DBSYNC (D1541)
WriteDataSync:
    bvc *
    clv
    sta DiskData
    dex
    bne WriteDataSync
    ldx #256 - OVERFLOW_SIZE

;; The data block's first 69 GCR bytes, from the overflow buffer.
;; Also: WRTS40 (D1541)
WriteOverflow:
    bvc *
    clv
    lda OverflowBuffer,x
    sta DiskData
    inx
    bne WriteOverflow
    ldy #$00

;; Its other 256, from buffer 2.
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

;; The gap after it, <SectorGap> bytes of $55. Then the next sector, and after the last, two more bytes out and back to
;; reading.
;; Also: WGP2 (D1541)
WriteDataGap:
    bvc *
    clv
    sta DiskData
    dex
    bne WriteDataGap

    ; The next header, 10 bytes on.
    lda HeaderPointer
    clc
    adc #$0A
    sta HeaderPointer
    dec FormatSector
    bne WriteSector

    ; The last two bytes out, then back to reading.
    bvc *
    clv
    bvc *
    clv
    jsr EndWrite
    .assert * = VerifyTrack, "WriteTrack must fall into VerifyTrack."
    ; Falls into VerifyTrack.
.endproc

;; Reads the track just written and compares every sector with what was written; then sends the head on to the next
;; track for the next pass, or ends the format after track 35.
;;
;; It starts at whatever sync comes first and expects sector 0's header, so the 200 tries (<VerifyRetries>), one for
;; each sync that does not match, also cover the wait for sector 0; a mismatch starts again from sector 0. A header's 10
;; GCR bytes and the data block's first 321 are compared, all but the last 4 (bytes 321 to 324), which hold the last
;; data byte's final 2 bits, the whole checksum and the padding. It has no name in the listing: its first instruction,
;; at $FD27, comes before <VerifyTrack::Restart>.
;; In: SectorCount = the track's sectors, FormatTrack = the track, Buffer0 = the headers in GCR, 10 bytes each,
;;   Buffer2 = the data block's GCR after its first 69, which are in <OverflowBuffer>
;; Errors: through <FormatError>, <FORMAT_VERIFY_FAILED> after 200 mismatches; the job ends with 3 (message 21) when no
;;   sync comes within 20 ms
.proc VerifyTrack
    ; 200 tries, for the whole track.
    lda #$C8                        ; 200
    sta VerifyRetries

;; Starts again at sector 0: <DataPointer> = its header's GCR in buffer 0, and <FormatSector> = <SectorCount> to go.
;; Also: COMP (D1541)
Restart:
    lda #$00
    sta DataPointer
    lda #>Buffer0
    sta DataPointer+1
    lda SectorCount
    sta FormatSector

;; Waits for the next sync.
;; Also: CMPR10 (D1541)
NextHeader:
    jsr WaitForSync
    ldx #$0A                        ; a header's 10 GCR bytes
    ldy #$00

;; Compares the 10 GCR bytes after it with the header written; alike, the next header's are 10 bytes on.
;; Also: CMPR15 (D1541)
CompareHeader:
    bvc *                           ; waits for byte-ready, which sets V
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

;; A mismatch: starts again, and after 200 is format error <FORMAT_VERIFY_FAILED>.
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
    ldy #256 - OVERFLOW_SIZE

;; Compares its first 69 GCR bytes, from the overflow buffer.
;; Also: TST05 (D1541)
CompareOverflow:
    bvc *
    clv
    lda DiskData
    cmp OverflowBuffer,y
    bne Mismatch
    iny
    bne CompareOverflow
    ldx #$FC                        ; 252

;; Then the next 252, from buffer 2. Then the next sector, and after the last, the next track (<FormatTrack> + 1) for
;; the next pass, until all 35 are done.
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
    cmp #$24                        ; past track 35
    bcs Finished
    jmp EndPass

;; All 35 tracks: no format under way, <BufferIsGcr> cleared so that <FinishJob> does not decode the write image
;; (<DataPointer>+1 is <Buffer0>'s page here, so it would decode the overflow buffer and buffer 0's page into buffer 0),
;; and the job finished with 1.
;; Also: FMTEND (D1541)
Finished:
    lda #$FF
    sta FormatTrack
    lda #$00
    sta BufferIsGcr
    lda #$01
    jmp FinishJob
.endproc

;; Switches the head to writing and writes sync, $FF, for 10240 bytes, more than a turn of the disk, leaving it writing.
;; Out: DiskData = $FF, still being written
;; Also: SYNCLR (D1541)
.proc EraseWithSync
    ; CB2 low and port A out: the head writes.
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl
    lda #$FF
    sta Via2DirectionA
    sta DiskData
    ldx #$28                        ; 40 pages
    ldy #$00

;; Counts the bytes.
;; Also: SYC10 (D1541)
Loop:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    dey
    bne Loop
    dex
    bne Loop
    rts
.endproc

;; Writes <SegmentLength> more bytes of what the head is writing (256 more when its low byte is 0).
;; In: SegmentLength = the count, DiskData = the byte
;; Also: WRTNUM (D1541)
.proc WriteCount
    ldx SegmentLength
    ldy SegmentLength+1

;; Counts the bytes.
;; Also: WRTN10 (D1541)
Loop:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    dex
    bne Loop
    dey
    bpl Loop
    rts
.endproc

;; A format error, code A: while errors are left in <FormatRetries> (10 for the whole format, the tenth ending it), ends
;; the pass, and the next pass tries the track again; at the last, ends the format and finishes the job with A, which
;; <Commands::Format> reports as message 21, READ ERROR, whatever the code. It never returns.
;; In: A = the code
;; Also: FMTERR (D1541)
.proc FormatError
    dec FormatRetries
    beq GiveUp
    jmp EndPass

;; No format under way (<FormatTrack> = $FF), <BufferIsGcr> cleared, and the job finished with A.
;; Also: FMTE10 (D1541)
GiveUp:
    ldy #$FF
    sty FormatTrack
    iny
    sty BufferIsGcr
    jmp FinishJob
.endproc

;; Moves buffer 0's bytes 0 to Y up <OVERFLOW_SIZE> bytes, from the top down, to make room for the overflow buffer's.
;; In: Y = the last byte to move
;; Keeps: X
;; Also: MOVUP (D1541)
.proc ShiftBufferUp
    lda Buffer0,y
    sta Buffer0 + OVERFLOW_SIZE,y
    dey
    bne ShiftBufferUp
    lda Buffer0
    sta Buffer0 + OVERFLOW_SIZE
    rts
.endproc

;; Copies the overflow buffer's 69 GCR bytes, from its byte 187, to the start of the buffer at <DataPointer>.
;; In: DataPointer = the buffer
;; Keeps: X
;; Also: MOVOVR (D1541)
.proc CopyOverflow
    ldy #OVERFLOW_SIZE - 1

;; Copies the next byte, from the top down.
;; Also: MOVO10 (D1541)
Loop:
    lda OverflowBuffer + 256 - OVERFLOW_SIZE,y
    sta (DataPointer),y
    dey
    bpl Loop
    rts
.endproc

;; Switches the head back to reading (CB2 high) and VIA 2's port A to input.
;; Keeps: X, Y
;; Also: KILL (D1541)
.proc EndWrite
    lda Via2PeripheralControl
    ora #$E0
    sta Via2PeripheralControl
    lda #$00
    sta Via2DirectionA
    rts
.endproc

;; Switches the head to writing and writes $55 for 10240 bytes, more than a turn of the disk, leaving it writing $55.
;; Out: DiskData = $55, still being written
;; Also: CLEAR (D1541)
.proc EraseTrack
    ; CB2 low and port A out: the head writes.
    lda Via2PeripheralControl
    and #$1F
    ora #$C0
    sta Via2PeripheralControl
    lda #$FF
    sta Via2DirectionA
    lda #$55
    sta DiskData
    ldx #$28                        ; 40 pages
    ldy #$00

;; Counts the bytes.
;; Also: CLER10 (D1541)
Loop:
    bvc *                           ; waits for byte-ready, which sets V
    clv
    dey
    bne Loop
    dex
    bne Loop
    rts
.endproc

;; Encodes the format's headers, all 256 bytes of the buffer at <DataPointer> with no block ID, as 320 GCR bytes: 69 in
;; the overflow buffer from byte 187 and the rest in the buffer from its start.
;; In: DataPointer+1 = the buffer's page
;; Out: DataPointer = the buffer
;; Also: FBTOG (D1541)
.proc EncodeHeaders
    lda #$00
    sta DataPointer
    sta SavedPointer
    sta ByteIndex
    lda #256 - OVERFLOW_SIZE
    sta GcrIndex
    lda DataPointer+1
    sta SavedPointer+1
    lda #>OverflowBuffer
    sta DataPointer+1

;; Takes the next four bytes, and encodes them unless they are the last.
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

;; Encodes the last four, returning through <EncodeGroup>.
;; Also: FBG15 (D1541)
LastGroup:
    jmp EncodeGroup
.endproc

;; The IRQ handler, which the ROM's IRQ vector points to: passes ATN (VIA 1's CA1) to <Serial::AtnInterrupt>, and VIA
;; 2's timer 1 to <ScanJobs>, a pass of the controller.
;; Keeps: A, X, Y
;; Also: SYSIRQ (D1541)
.proc Interrupt
    ; A, X and Y kept; ATN first.
    pha
    txa
    pha
    tya
    pha
    lda Via1InterruptFlags
    and #$02                        ; CA1, ATN
    beq CheckTimer
    jsr Serial::AtnInterrupt

;; VIA 2's timer 1, its interrupt flag's bit 6, runs a pass of the controller.
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
