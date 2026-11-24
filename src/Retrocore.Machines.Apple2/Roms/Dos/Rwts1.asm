; retrocore: style=strict ignore=unlinked-name:RWTS -- the disk layer's name in prose
;; DOS 3.3 RWTS: read or write a track and sector, part one (Apple's RWTSONE)
;;
;; RWTS, "read or write a track and sector", is the routine the rest of DOS calls for every disk access. The caller
;; describes the request in an IOB, laid out as <Iob>, and passes its address in A and Y. This first part starts
;; the drive: it waits for another slot's drive to stop if the slot has changed, checks whether the motor is
;; already turning, turns it on, selects the drive, moves the head to the track and, if the motor was off, waits for
;; it to come up to speed. Rwts2.asm goes on with finding the sector and reading or writing it, or formatting: the
;; two files hold one routine, <Rwts>, which Apple split in two for size. RWTS starts at $BD00 where DOS runs. The
;; file manager, and programs using the vector at $03D9, call it through <CallRwts> (BootLoader.asm), which disables
;; interrupts for the call; DOS's own IOB is <DosIob> and its DCT <DosDeviceTable> (IoBlock.asm).
;;
;; RWTS reads the IOB's slot, drive, volume, track, sector, DCT and buffer addresses and command, and writes back
;; the return code, the volume found and the slot and drive it used; it reads neither the IOB's type nor its byte
;; count. Of the DCT, the device characteristics table, it reads two of the four bytes:
;; <DeviceTable::WHOLE_TRACKS>, whose bit 0 set means each track is two half-track steps (1 for the Disk II), and
;; the high byte of <DeviceTable::MOTOR_DELAY>, the motor's start-up count ($D8 for the Disk II).
;;
;; Several values live in screen holes, at the address given plus the slot (<Drive1HalfTracks>,
;; <Drive2HalfTracks>) or at slot 0's byte (the counters); see RwtsEquates.asm. docs/DiskII.md explains the drive,
;; and docs/Dos.md the IOB.

;; The start of the relocator's range for RWTS proper and the formatter, to <RwtsCodeEnd> ($BD00-$BFA7 where DOS
;; runs). See Relocator.asm.
;; Also: ASC2 (DOS33, DOS31)
RwtsCodeStart:

; RWTS's variables, which the head helpers and the formatter share with it.

;; The half-track drive 1 of each slot's card is on, at this address plus the slot: the screen holes $0479-$047F.
;;
;; <SeekHalfTrack> reads and updates it, <SetTrack> sets it, and <Boot::Stage2> sets it to 0 for the boot drive.
;; Slot 0's byte is <CurrentTrack>.
;; See: <Drive2HalfTracks>, <SelectedDrive>
;; Also: DRV1TRK (DOS33)
Drive1HalfTracks = $0478

;; The half-track drive 2 of each slot's card is on, at this address plus the slot: the screen holes $04F9-$04FF.
;;
;; Slot 0's byte is <Rwts::SeeksLeft>.
;; See: <Drive1HalfTracks>, <SelectedDrive>
;; Also: DRV2TRK (DOS33)
Drive2HalfTracks = $04F8

;; The pointer to the caller's IOB, the block that says what <Rwts> is to do (2 bytes).
;;
;; <Rwts> stores the address it is called with, A high and Y low, here, and reads the slot, drive, track, sector,
;; command and pointers through it with (IobPointer),Y. It writes the result there too: the return code, the volume
;; found, and the slot and drive used. <SetTrack> and the formatter read it as well.
;; See: <IobPointerHigh>, <Rwts>, <Rwts::Pointers>
;; Also: IOBPL (DOS33)
IobPointer = SavedStatus

;; The high byte of <IobPointer>.
;; See: <IobPointer>
;; Also: IOBPH (DOS33)
IobPointerHigh = SavedStackPointer

;; The pointer to the DCT, the device characteristics table that the IOB names (2 bytes).
;;
;; <Rwts> copies it from the IOB with the buffer's address, through <Rwts::Pointers>, and takes the motor's start-up
;; count from the DCT; <SeekTrack> reads <DeviceTable::WHOLE_TRACKS>, whose bit 0 says that each track is two
;; half-track steps.
;; See: <Rwts::Pointers>, <Rwts::MotorCount>, <SeekTrack>
;; Also: DEVCTBL (DOS33)
DctPointer = Address1

;; Bit 7 tells which drive <Rwts> is using: set for drive 1, clear for drive 2.
;;
;; <Rwts> and <SetTrack> rotate the drive number's bit 0 into it when they select the drive. <SeekHalfTrack> tests
;; it to keep each drive's half-track in its own screen hole, <Drive1HalfTracks> or <Drive2HalfTracks>.
;; See: <SelectDrive1>, <SelectDrive2>, <SeekHalfTrack>, <Drive1HalfTracks>
;; Also: DRIVNO (DOS33)
SelectedDrive = SavedOutputY

;; The sector number in the address field just read, <AddressField>'s second byte.
;;
;; <Rwts> compares it with the IOB's sector, turned into the sector number on the disk through <PhysicalSectors>,
;; to find the sector it wants; the formatter reads it to find sectors 0 and 15.
;; See: <AddressField>, <FoundTrack>, <FoundVolume>
;; Also: SECT (DOS33)
FoundSector = AddressField + 1

;; The track number in the address field just read, <AddressField>'s third byte.
;;
;; <Rwts> compares it with the track it sought (<Rwts::CheckTrack>): when they differ, it notes where the head
;; really is and seeks again. Apple's DOS equates also call the byte BOOTSL, a name DOS 3.1 used for the boot slot.
;; See: <AddressField>, <FoundSector>, <FoundVolume>
;; Also: TRACK (DOS33), BOOTSL (DOS33, DOS31)
FoundTrack = AddressField + 2

;; The volume number in the address field just read, <AddressField>'s fourth byte.
;;
;; <Rwts> returns it in the IOB's volume found and, unless the IOB's volume is 0 (any volume), fails with a volume
;; mismatch when they differ.
;; See: <AddressField>, <FoundSector>, <FoundTrack>
;; Also: VOLUME (DOS33)
FoundVolume = AddressField + 3

;; The address fields left to read before giving up on the track: slot 0's screen-hole byte at $0578.
;;
;; <Rwts> starts it at 48 for each seek; the formatter uses it for its own tries.
;; Also: RETRYCNT (DOS33)
RetriesLeft = $0578

;; Reads, writes or formats as the IOB at A (high byte) and Y (low byte) asks, or only moves the head.
;;
;; The first part, here: if the slot is not the one used last, RWTS waits until the old slot's drive has stopped,
;; which it knows when the data latch stops changing. It then checks whether the motor of the new slot is turning,
;; the same way, and turns it on either way; a motor counts as off if the drive is not the one used last. If it was
;; off, RWTS waits 150 to 180 milliseconds before seeking and, after the seek, until the motor-on count reaches
;; zero: <Rwts::MotorCount> starts at $D8xx (from the DCT) and <DiskII::Wait> adds 1 per 100 microseconds of every wait,
;; so the seek's time counts too, and the whole start takes about a second.
;;
;; The second part is <Rwts::TryTrack> (Rwts2.asm), which carries out the command. The flags RWTS pushes after testing
;; the motor (zero set if it was off) stay on the stack until the seek is done. RWTS uses much of zero page
;; $26-$49 and the screen holes. At $BD00 where DOS runs.
;; In:    A = the IOB's address's high byte, Y = its low byte, the IOB filled in for the command
;; Out:   carry = clear, the IOB's volume found (read, write) and previous slot and drive set, X = slot * 16, the
;;   motor off
;; Errors: carry = set and the IOB's return code: <RWTS_WRITE_PROTECTED>, <RWTS_VOLUME_MISMATCH>,
;;   <RWTS_DRIVE_ERROR> or, from the formatter, <RWTS_FORMAT_ERROR>
;; Uses:  A, Y
;; Also: RWTS (DOS33)
.proc Rwts
.assert MASTER || * = $BD00, "RWTS is at $BD00 where DOS runs."

;; The slot times 16 for this call: slot 0's screen-hole byte at $05F8.
;; Also: SLOT (DOS33)
SlotTimes16 = $05F8

;; Where RWTS copies the IOB's two pointers, its DCT and buffer addresses: <DctPointer> here, then
;; <SectorBuffer>.
;;
;; The four bytes $3C-$3F take both pointers in one loop (<CopyPointers>).
;; See: <DctPointer>, <SectorBuffer>, <IobPointer>
;; Also: PTRSDEST (DOS33)
Pointers = Address1

;; The motor-on count, <MotorTime> and <MotorTimeHigh>, as one word: it counts up to 0 in steps of 100
;; microseconds.
;;
;; RWTS sets its high byte from the DCT ($D8 for the Disk II) when it starts. If the motor was off, it waits after
;; the seek until the count reaches 0, calling <DiskII::Wait>, which adds to the count; a motor started this way
;; runs about a second before RWTS reads or writes.
;; See: <MotorTime>, <MotorTimeHigh>, <DiskII::Wait>, <DctPointer>
;; Also: MONTIME (DOS33)
MotorCount = MotorTime

;; The address fields from a wrong track RWTS accepts before it recalibrates, 4: three new seeks.
;; Also: MAXSEEKS (DOS33)
MAX_SEEKS = 4

;; The seeks left before recalibrating: slot 0's byte of <Drive2HalfTracks>, $04F8.
;; Also: SEEKCNT (DOS33)
SeeksLeft = Drive2HalfTracks

;; The recalibrations left, plus 1: slot 0's screen-hole byte at $06F8.
;; Also: RECALCNT (DOS33)
RecalibrationsLeft = $06F8

;; The recalibrations RWTS allows a call, 1.
RECALIBRATIONS = 1

;; The reads of the data latch that must find it unchanged before RWTS takes a motor to be stopped, 8.
LATCH_TESTS = 8

;; The waits of <DiskII::Wait> before seeking when the motor was off, 7.
START_WAITS = 7

;; The passes of the motor wait's inner loop, about 100 cycles with the count.
DELAY_PASSES = $12

; The diagnostic build (DIAGNOSTIC_RWTS = 1) shows what RWTS is doing as inverse letters on the bottom line of the text
; screen, each at its own place: a letter appears while the step is under way and a space replaces it. The
; LETTER_ constants are a letter's screen code and the At names its address. It also counts the wrong sectors that
; pass before the right one and shows the average as a hex digit at AverageAt. The diagnostic build leaves out the
; formatter. No DOS was built with it.
.if DIAGNOSTIC_RWTS
;; A space, which clears a letter.
;; Also: SP (DOS33)
DIAG_BLANK = $A0

;; The distance between letters.
;; Also: TD (DOS33)
DIAG_GAP = 4

;; ^: RWTS is running.
;; Also: TC1 (DOS33)
LETTER_RUNNING = $1E

;; Where <LETTER_RUNNING> shows: the bottom line's first column.
;; Also: TL1 (DOS33)
RunningAt = $07D0

;; M: waiting for the motor.
;; Also: TC2 (DOS33)
LETTER_MOTOR = $0D

;; Where <LETTER_MOTOR> shows.
;; Also: TL2 (DOS33)
MotorAt = RunningAt + DIAG_GAP

;; S: seeking (<SeekTrack> shows it).
;; Also: TC3 (DOS33)
LETTER_SEEK = $13

;; Where <LETTER_SEEK> shows.
;; Also: TL3 (DOS33)
SeekAt = MotorAt + DIAG_GAP

;; A: reading an address field.
;; Also: TC4 (DOS33)
LETTER_ADDRESS = $01

;; Where <LETTER_ADDRESS> shows.
;; Also: TL4 (DOS33)
AddressAt = SeekAt + DIAG_GAP

;; L: an address field for another sector.
;; Also: TC5 (DOS33)
LETTER_WRONG_SECTOR = $0C

;; Where <LETTER_WRONG_SECTOR> shows.
;; Also: TL5 (DOS33)
WrongSectorAt = AddressAt + 1

;; E: an address field could not be read.
;; Also: TC6 (DOS33)
LETTER_ADDRESS_ERROR = $05

;; Where <LETTER_ADDRESS_ERROR> shows.
;; Also: TL6 (DOS33)
AddressErrorAt = WrongSectorAt + 1

;; P: splitting the sector to write (<DiskII::PreNibble>).
;; Also: TC7 (DOS33)
LETTER_PRENIBBLE = $10

;; Where <LETTER_PRENIBBLE> shows.
;; Also: TL7 (DOS33)
PreNibbleAt = AddressAt + DIAG_GAP

;; W: writing a data field.
;; Also: TC8 (DOS33)
LETTER_WRITE = $17

;; Where <LETTER_WRITE> shows.
;; Also: TL8 (DOS33)
WriteAt = PreNibbleAt + DIAG_GAP

;; R: reading a data field.
;; Also: TC9 (DOS33)
LETTER_READ = $12

;; Where <LETTER_READ> shows.
;; Also: TL9 (DOS33)
ReadAt = WriteAt + DIAG_GAP

;; E: a data field could not be read.
;; Also: TC10 (DOS33)
LETTER_DATA_ERROR = $05

;; Where <LETTER_DATA_ERROR> shows.
;; Also: TL10 (DOS33)
DataErrorAt = ReadAt + DIAG_GAP

;; O: rebuilding the sector read (<DiskII::PostNibble>).
;; Also: TC11 (DOS33)
LETTER_POSTNIBBLE = $0F

;; Where <LETTER_POSTNIBBLE> shows.
;; Also: TL11 (DOS33)
PostNibbleAt = DataErrorAt + DIAG_GAP

;; The sectors found since the motor started.
;; Also: SCOUNT (DOS33)
SectorsSeen = $02FE

;; The wrong sectors passed meanwhile, counted after the first sector is found.
;; Also: LCOUNT (DOS33)
SectorsMissed = $02FF

;; Where the average of wrong sectors shows.
;; Also: TL12 (DOS33)
AverageAt = PostNibbleAt + DIAG_GAP
.endif

    sty IobPointer
    sta IobPointerHigh
.if DIAGNOSTIC_RWTS
    ldy #LETTER_RUNNING
    sty RunningAt
.endif
    ldy #RECALIBRATIONS + 1
    sty RecalibrationsLeft
    ldy #MAX_SEEKS
    sty SeeksLeft

    ; The slot: the same as last time?
    ldy #Iob::SLOT_TIMES_16
    lda (IobPointer),y
    tax
    ldy #Iob::PREVIOUS_SLOT
    cmp (IobPointer),y
    beq SameSlot

    ; Another slot: note the new one in the IOB, then wait for the old slot's drive to stop turning. A stopped disk
    ; sends no pulses, so the data latch stays the same: wait until it reads the same eight times running.
    txa
    pha
    lda (IobPointer),y
    tax                             ; the old slot
    pla
    pha
    sta (IobPointer),y              ; the new slot becomes the last one used
    lda ReadMode,x                  ; read mode

;; Starts the count of unchanged reads again.
;; Also: STILLON (DOS33)
WaitForStop:
    ldy #LATCH_TESTS
    lda DataLatch,x

;; Reads the latch again: a change means the drive is still turning.
;; Also: NOTSURE (DOS33)
CompareLatch:
    cmp DataLatch,x
    bne WaitForStop                 ; it changed: still turning
    dey
    bne CompareLatch
    pla
    tax                             ; the new slot

    ; Is this slot's motor turning? Read the latch twice about 20 cycles apart, up to eight times; a change means
    ; yes.
;; The slot is the last one used, or its old drive has stopped: tests whether the motor is turning.
;; Also: SAMESLOT (DOS33)
SameSlot:
    lda ReadMode,x                  ; read mode
    lda DataLatch,x
    ldy #LATCH_TESTS

;; Reads the latch again, about 20 cycles later.
;; Also: CHKIFON (DOS33)
CheckTurning:
    lda DataLatch,x
    pha                             ; delay, for the data to change
    pla
    pha
    pla
    stx SlotTimes16
    cmp DataLatch,x
    bne MotorChecked
    dey
    bne CheckTurning

;; Notes whether the motor was turning, in the zero flag it pushes (clear if it was), and turns it on.
;; Also: ITISON (DOS33)
MotorChecked:
    php
    lda MotorOn,x

    ; Copy the DCT and buffer addresses from the IOB to DctPointer and SectorBuffer in zero page.
    ldy #Iob::DEVICE_TABLE

;; Copies the next byte of the IOB's pointers.
;; Also: PTRMOV (DOS33)
CopyPointers:
    lda (IobPointer),y
    sta Pointers - Iob::DEVICE_TABLE,y
    iny
    cpy #Iob::BUFFER + 2
    bne CopyPointers

    ; The motor-on count's high byte from the DCT; the low byte is left as it is.
    ldy #DeviceTable::MOTOR_DELAY + 1
    lda (DctPointer),y
    sta MotorCount+1

    ; The drive: the same as last time?
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ldy #Iob::PREVIOUS_DRIVE
    cmp (IobPointer),y
    beq SameDrive
    sta (IobPointer),y
    plp                             ; another drive: replace the saved flags with zero set, "the motor was off"
    ldy #0
    php

;; Selects the drive, by bit 0 of its number: 1 for drive 1.
;; Also: OK (DOS33)
SameDrive:
    ror a
    bcc Drive2
    lda SelectDrive1,x
    bcs DriveSelected               ; always

;; Selects drive 2.
;; Also: SD1 (DOS33)
Drive2:
    lda SelectDrive2,x

;; Notes the drive in <SelectedDrive>'s bit 7, set for drive 1.
;; Also: DRVSEL (DOS33)
DriveSelected:
    ror SelectedDrive

    ; If the motor was off, wait before moving the head: seven waits, the first as long as the byte the drive-select
    ; switch returned in A says, the six others 256 times 100 microseconds each.
    plp
    php
    bne GoToTrack
    ldy #START_WAITS

;; Waits once more before seeking.
;; Also: SEEKW (DOS33)
StartDelay:
    jsr DiskII::Wait
    dey
    bne StartDelay
    ldx SlotTimes16                 ; Wait used X

;; Moves the head to the IOB's track.
;; Also: NOWAIT (DOS33)
GoToTrack:
    ldy #Iob::TRACK
    lda (IobPointer),y
    jsr SeekTrack
    plp
    bne TryTrack                    ; the motor was on: go ahead
.if DIAGNOSTIC_RWTS
    ldy #LETTER_MOTOR
    sty MotorAt
    ldy #0
    sty SectorsSeen
    sty SectorsMissed
    ldy #DIAG_BLANK
    sty AverageAt
.endif

    ; The motor was off: wait until the motor-on count reaches zero. If the count has already gone past zero, the
    ; waits so far were enough.
    ldy MotorCount+1
    bpl MotorUp

;; Waits about 100 cycles and counts them, until the motor-on count reaches zero.
;; Also: MOTOF (DOS33)
WaitForMotor:
    ldy #DELAY_PASSES

;; The delay loop: with the INC and BNE, about 100 cycles a pass.
;; Also: CONWAIT (DOS33)
DelayLoop:
    dey
    bne DelayLoop
    inc MotorCount
    bne WaitForMotor
    inc MotorCount+1
    bne WaitForMotor

;; The motor is up to speed; falls into <TryTrack>.
;; Also: MOTORUP (DOS33)
MotorUp:
.if DIAGNOSTIC_RWTS
    ldy #DIAG_BLANK
    sty MotorAt
.endif
