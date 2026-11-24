; retrocore: style=strict
;; DOS 3.3 System Master: BOOT13 (1980), which boots a 13-sector disk ($1700-$1FEF)
;;
;; The binary file BOOT13 from the 1980 System Masters (680-0051-00 and 680-0051-01). DOS loads its $08F0 bytes at
;; $1700 and starts it there. It boots a 13-sector disk, DOS 3.1 to 3.2.1, with a Disk II controller whose boot ROM
;; reads only 16-sector disks: it does the work of the 13-sector ROM (Boot13.asm) and of `BOOT 1` (BootLoader.asm),
;; then enters the disk's `BOOT 2`. The 1983 master's BOOT13 (Boot13.1983.asm) is a smaller program that does the
;; same.
;;
;; It is two parts. The first page asks for the slot and loads `BOOT 1`'s pages through RWTS with an IOB of its own,
;; as `BOOT 1` would, then jumps to `BOOT 2`. From $1800 to the end is a whole 13-sector RWTS at $1800-$1FEF, laid out
;; as DOS 3.2's is at $B800-$BFEF, which `BOOT 2` never sees: it brings its own. Its routines have DOS's names.
;;
;; The RWTS is a release between DOS 3.2's and DOS 3.3's:
;;
;; - Its nibble routines, <DiskII::PreNibble> to <DiskII::PostNibble>, are DOS 3.2's; this source includes them
;;   from the DOS 3.2 modules.
;; - Its <DiskII::MoveHead> and <DiskII::Wait> are DOS 3.3's (Seek.asm, MsWait.asm), without the
;;   padding before the wait.
;; - <Rwts> itself is DOS 3.3's (Rwts1.asm, Rwts2.asm), calling the 13-sector routines, with DOS 3.2's single test
;;   of the motor (Rwts32.asm), no sector translation and the volume passed to the formatter as DOS 3.2 passes it.
;; - The formatter, <Formatter::Format>, is DOS 3.2's (Formatter.asm), with a wait loop two bytes shorter that
;;   takes as long.
;;
;; Assembles byte-identically to BOOT13 on the 680-0051-00 and 680-0051-01 masters; docs/DiskII.md explains the
;; 5-and-3 format and docs/Dos.md the boot.

.cpu Mos6502

; The DOS 3.2 modules this source includes test DOS32 where DOS 3.2 differs from DOS 3.3.
DOS32 = 1

.include "../Roms/Dos/Equates.asm"

;; Inherit: <Monitor:GetLine>
;; At $FD6A.
;; Also: GETLN (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLine = $FD6A

;; DOS's page-3 entry that gives its IOB's address: Y = the low byte, A = the high byte.
LocateIob = $03E3

;; The slot Return chooses.
DEFAULT_SLOT = 6

; Page zero, as the loader uses it.

;; The address of DOS's IOB (2 bytes), from <LocateIob>.
DosIobPointer = SlotPointer

;; The last sector to load, `BOOT 1`'s own last sector.
LastSector = $10

;; `BOOT 2`'s address, where the load ends (2 bytes).
BootEntry = $12

; `BOOT 1`'s two variables, the last bytes of the boot sector as DOS stores it (BootLoader.asm).

;; The offset of the first page `BOOT 1` loads, <Dos32:Boot::FirstPage>.
FIRST_PAGE_OFFSET = $FE

;; The offset of the last sector `BOOT 1` loads, shifted left three places, <Dos32:Boot::LastSector>.
LAST_SECTOR_OFFSET = $FF

;; The page the boot sector is read into first, below the program.
BootSector = $1600

; The IOB and DCT, laid out as DOS's are (IoBlock.asm, which this program can't include: it holds DOS's own).

;; The layout of an IOB, the block that says what <Rwts> is to do.
.struct Iob
    TYPE .byte                      ;; the IOB's type, 1
    SLOT_TIMES_16 .byte             ;; the slot times 16
    DRIVE .byte                     ;; the drive, 1 or 2
    VOLUME .byte                    ;; the volume expected, or 0 for any
    TRACK .byte                     ;; the track
    SECTOR .byte                    ;; the sector, as numbered on the disk
    DEVICE_TABLE .addr              ;; the DCT's address
    BUFFER .addr                    ;; the 256-byte buffer's address
    DATA_LENGTH .word               ;; unused
    COMMAND .byte                   ;; the command: 0 seeks, 1 reads, 2 writes, 4 formats
    RETURN_CODE .byte               ;; the error, when the carry is set
    VOLUME_FOUND .byte              ;; the volume found
    PREVIOUS_SLOT .byte             ;; the previous call's slot times 16
    PREVIOUS_DRIVE .byte            ;; the previous call's drive
.endstruct

;; The layout of a DCT, the table that describes a drive.
.struct DeviceTable
    DEVICE_TYPE .byte               ;; 0, the Disk II
    WHOLE_TRACKS .byte              ;; bit 0 set when a track is two half-track steps
    MOTOR_DELAY .word               ;; the motor's start-up count
.endstruct

; The commands and errors RWTS handles (IoBlock.asm).

;; RWTS command: reads a sector.
RWTS_READ = 1

;; RWTS command: formats the disk.
RWTS_FORMAT = 4

;; RWTS error: no address field or sector could be read on the track, or the disk cannot be formatted.
RWTS_DRIVE_ERROR = $40

;; RWTS error: the disk's volume is not the one the IOB asks for.
RWTS_VOLUME_MISMATCH = $20

;; RWTS error: the disk is write-protected.
RWTS_WRITE_PROTECTED = $10

.org $1700

;; Asks for the slot to boot from, 1 to 7 or Return for 6, and loads and enters the disk's `BOOT 2`.
;;
;; At $1700, where DOS starts it. RWTS takes DOS's last slot and drive as its own last ones, so it knows whether that
;; drive's motor may still be turning. The boot sector is read into <BootSector> to find `BOOT 1`'s first page and
;; last sector; then sectors 0 to the last of track 0 are read into the pages from the first up, as `BOOT 1` would
;; read them, and it jumps to the second page with X = slot * 16. Each read is tried until it succeeds.
.proc Start

    ; DOS's slot and drive, as the previous ones.
    jsr LocateIob
    sty DosIobPointer
    sta DosIobPointer + 1
    ldy #Iob::SLOT_TIMES_16
    lda (DosIobPointer),y
    sta BootIob + Iob::PREVIOUS_SLOT
    iny
    lda (DosIobPointer),y
    sta BootIob + Iob::PREVIOUS_DRIVE

    ; The title and the question, until the character with bit 7 set.
;; Asks again.
Ask:
    jsr Home
    ldy #$FF
;; Prints the next character.
Title:
    iny
    lda TitleText,y
    php
    ora #HIGH_BIT
    jsr CharacterOut
    plp
    bpl Title

    ; The answer: Return, or a digit from 1 to 7.
    lda #'?' | HIGH_BIT
    sta PromptCharacter
    jsr GetLine
    lda InputBuffer
    cmp #KEY_RETURN
    beq Load                        ; Return: the IOB holds slot 6 already
    cmp #'1' | HIGH_BIT
    bcc Ask
    cmp #'8' | HIGH_BIT
    bcs Ask
    asl a                           ; the digit's low four bits become the slot * 16
    asl a
    asl a
    asl a
    sta BootIob + Iob::SLOT_TIMES_16

    ; The boot sector, for `BOOT 1`'s first page and last sector.
;; Reads the boot sector, until it succeeds.
Load:
    lda #>BootIob
    ldy #<BootIob
    jsr Rwts
    bcs Load
    lda BootSector + FIRST_PAGE_OFFSET
    sta BootIob + Iob::BUFFER + 1
    sta BootEntry + 1
    inc BootEntry + 1               ; `BOOT 2` is in the second page
    lda BootSector + LAST_SECTOR_OFFSET
    lsr a
    lsr a
    lsr a
    sta LastSector

    ; Sectors 0 to the last, a page each, then `BOOT 2` with X = slot * 16.
;; Reads the next sector, until it succeeds.
Next:
    lda #>BootIob
    ldy #<BootIob
    jsr Rwts
    bcs Next
    inc BootIob + Iob::BUFFER + 1
    inc BootIob + Iob::SECTOR
    lda BootIob + Iob::SECTOR
    cmp LastSector
    beq Next
    bcc Next
    lda BootIob + Iob::SLOT_TIMES_16
    tax
    lda #0
    sta BootEntry
    jmp (BootEntry)
.endproc

;; The IOB the loader passes RWTS: read track 0 sector 0 of drive 1 in slot 6 into <BootSector>, any volume.
;;
;; The loader changes the slot, the sector and the buffer's page, and RWTS the previous slot and drive and the
;; results. It has no spare bytes.
BootIob:
    .byte 1                         ; the IOB's type
    .byte DEFAULT_SLOT * 16         ; the slot
    .byte 1                         ; the drive
    .byte 0                         ; the volume expected: any
    .byte 0                         ; the track
    .byte 0                         ; the sector
    .word BootDct                   ; the DCT
    .word BootSector                ; the buffer
    .byte 0, 0                      ; the data length, unused
    .byte RWTS_READ                 ; the command
    .byte 0                         ; the return code
    .byte 0                         ; the volume found
    .byte $C6, $FD                  ; the previous slot and drive, from DOS's IOB when the loader starts
.assert * - BootIob = .sizeof(Iob), "BootIob is an Iob."

;; The DCT: a Disk II, two half-track steps to a track, and the motor's start-up count $D8EF.
BootDct:
    .byte 0, 1
    .word $D8EF
.assert * - BootDct = .sizeof(DeviceTable), "BootDct is a DeviceTable."

;; The title and the question, in plain ASCII; the loader sets bit 7 of each, and stops after the space whose bit 7
;; is already set.
TitleText:
    .byte $0D, $0D
    .byte "           13-SECTOR BOOT UTILITY", $0D, $0D
    .byte "SLOT TO BOOT FROM (DEFAULT=6)", $A0

    ; Leftover: another copy of the question, and spaces, that nothing prints.
    .byte $0D
    .byte "SLOT TO BOOT FROM (DEFAULT=6)", $A0
    .byte $A0, $A0, $A0, $A0, $A0, $A0, $B5, $A0
.assert * = $1800, "The RWTS starts at $1800."

;; Bit 7, which the Monitor's text has set.
HIGH_BIT = $80

; The low-level routines, laid out as DOS 3.2's are from $B800, less $A000: DOS 3.2's nibble routines, included next,
; open the DiskII scope, and this program's own seek, wait, tables and 4-and-4 writer continue it.

; The RWTS, from DOS 3.2's nibble routines on, at the addresses they have in DOS 3.2's layout less $A000.
.include "../Roms/Dos/RwtsEquates.asm"
.include "../Roms/Dos/PreNibble.asm"
.include "../Roms/Dos/WriteSector.asm"
.include "../Roms/Dos/ReadData.asm"
.include "../Roms/Dos/ReadAddress.asm"
.include "../Roms/Dos/PostNibble.asm"
.assert * = $1A1E, "The seek follows the nibble routines."

; DiskII: DOS 3.3's seek and wait, then DOS 3.2's tables.
.scope DiskII continued

;; Moves the head from half-track <CurrentTrack> to half-track A, one half-track at a time: DOS 3.3's
;; (Seek.asm).
;;
;; At $1A1E. Each step turns on the next half-track's phase, waits <OnTimes>' time, turns off the phase it left and
;; waits <OffTimes>' time, both indexed by the smaller of the half-tracks moved so far and those still to go, at
;; most 11, so the head speeds up and slows down. At the end it waits 25.6 milliseconds and turns the last phase
;; off, through <SetPhase>.
;; In: A = the half-track to go to, X = slot * 16, CurrentTrack = the half-track the head is on
;; Out: CurrentTrack = TargetHalfTrack = the new half-track
;; Keeps: X
.proc MoveHead

;; The number of half-tracks the head has moved so far.
StepsMoved = LowResBase

;; The half-track the head is leaving, whose phase goes off once the next one is on.
PriorHalfTrack = LowResBaseHigh

;; The slot times 16, kept while X indexes a phase's switch; <SetPhase> uses it too.
SlotTimes16 = ScrollBaseHigh

;; The last index into <OnTimes> and <OffTimes>, which every step from there to 11 before the end uses.
LAST_STEP = 11

    stx SlotTimes16
    sta TargetHalfTrack
    cmp CurrentTrack
    beq SetPhase::Return            ; already there
    lda #0
    sta StepsMoved
;; One step: which way, and how far from the start and the end.
NextStep:
    lda CurrentTrack
    sta PriorHalfTrack
    sec
    sbc TargetHalfTrack
    beq Settle                      ; arrived
    bcs Outward
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CurrentTrack
    bcc TakeSmaller                 ; always
;; Moving out, toward track 0.
Outward:
    adc #$FE                        ; out: A - 1 (the carry is set), half-tracks still to go after this step
    dec CurrentTrack
;; The smaller of the half-tracks moved and those left.
TakeSmaller:
    cmp StepsMoved
    bcc Limit
    lda StepsMoved
;; At most <LAST_STEP>: 12 or more keeps Y as it was, 11.
Limit:
    cmp #LAST_STEP + 1
    bcs Pulse
;; Sets the index into the tables.
SetIndex:
    tay
;; The new half-track's phase on, wait, the old one's off, wait.
Pulse:
    sec
    jsr SetPhase
    lda OnTimes,y
    jsr Wait
    lda PriorHalfTrack
    clc
    jsr SetPhase::OfHalfTrack
    lda OffTimes,y
    jsr Wait
    inc StepsMoved
    bne NextStep                    ; always
;; Arrived: waits 256 times 100 microseconds for the head to settle, then turns the phase off.
Settle:
    jsr Wait                        ; A = 0
    clc
    ; Falls into SetPhase.
.endproc

;; Turns half-track <CurrentTrack>'s phase on (carry set) or off (carry clear).
;; In: carry = set for on, clear for off, MoveHead::SlotTimes16 = slot * 16
;; Out: X = slot * 16
;; Entry: OfHalfTrack = for the half-track in A
.proc SetPhase
    lda CurrentTrack
;; The phase of the half-track in A.
OfHalfTrack:
    and #PHASE_MASK
    rol a                           ; times 2, plus the carry: on or off
    ora MoveHead::SlotTimes16
    tax
    lda Phase0Off,x
    ldx MoveHead::SlotTimes16
;; <MoveHead> returns here too, when the head is already there.
Return:
    rts
.endproc

;; The four stepper phases: half-track n lines the head up under phase n mod 4.
PHASE_MASK = 3

;; Waits about A times 100 microseconds (A = 0 waits 256 times), adding A to the motor-on count, <MotorTime>.
;;
;; At $1A7B. Each pass takes 101 cycles, about 100 microseconds.
;; In: A = the time, in hundreds of microseconds
;; Out: A = 0, X = 0, carry = set
;; Keeps: Y
.proc Wait

;; The passes of the inner loop, 17, which with the rest of the outer loop make 101 cycles.
INNER_PASSES = $11

;; One pass of 100 microseconds.
NextPass:
    ldx #INNER_PASSES
;; The inner loop: 17 passes, 84 cycles.
Inner:
    dex
    bne Inner
    inc MotorTime
    bne Count
    inc MotorTimeHigh
;; Counts A down.
Count:
    sec
    sbc #1
    bne NextPass
    rts
.endproc

;; How long to wait after turning a phase on, in hundreds of microseconds, by how far into or before the end of a
;; seek the step is (<MoveHead>).
OnTimes:
    .byte 1, $30, $28, $24, $20, $1E, $1D, $1C, $1C, $1C, $1C, $1C

;; How long to wait after turning the old phase off, by the same index.
OffTimes:
    .byte $70, $2C, $26, $22, $1F, $1E, $1D, $1C, $1C, $1C, $1C, $1C

;; The table <ReadDataField> uses to turn a nibble back into its five-bit value, shifted left three places: entry n,
;; at ReadTranslate + n, for nibble n.
;;
;; At $1A00. Only the entries for the nibbles $AB to $FF are used, so the table starts on the page boundary $AB
;; bytes before the first; the entries are DOS 3.2's (MsWait.asm).
ReadTranslate = $1A00

    ; Zeros up to the first entry.
    .res ReadTranslate + $AB - *
    .byte $00, $01, $08, $10        ; $AB-$AE
    .byte $18, $02, $03, $04        ; $AF-$B2
    .byte $05, $06, $20, $28        ; $B3-$B6
    .byte $30, $07, $09, $38        ; $B7-$BA
    .byte $40, $0A, $48, $50        ; $BB-$BE
    .byte $58, $0B, $0C, $0D        ; $BF-$C2
    .byte $0E, $0F, $11, $12        ; $C3-$C6
    .byte $13, $14, $15, $16        ; $C7-$CA
    .byte $17, $19, $1A, $1B        ; $CB-$CE
    .byte $1C, $1D, $1E, $21        ; $CF-$D2
    .byte $22, $23, $24, $60        ; $D3-$D6
    .byte $68, $25, $26, $70        ; $D7-$DA
    .byte $78, $27, $80, $88        ; $DB-$DE
    .byte $90, $29, $2A, $2B        ; $DF-$E2
    .byte $2C, $2D, $2E, $2F        ; $E3-$E6
    .byte $31, $32, $33, $98        ; $E7-$EA
    .byte $A0, $34, $A8, $B0        ; $EB-$EE
    .byte $B8, $35, $36, $37        ; $EF-$F2
    .byte $39, $3A, $C0, $C8        ; $F3-$F6
    .byte $D0, $3B, $3C, $D8        ; $F7-$FA
    .byte $E0, $3E, $E8, $F0        ; $FB-$FE
    .byte $F8                       ; $FF

;; The top five bits of each of a sector's 256 bytes, in five runs of 51 and the last byte's (<PreNibble>). After a
;; read, the values are shifted left three places. Empty on the disk.
HighBits:
    .res $100

;; The low three bits of a sector's bytes, five bits to a value: three runs of 51 and the last byte's three bits
;; (<PreNibble>). Empty on the disk.
LowBits:
    .res LOW_BITS_SIZE

;; The 32 nibbles, in order: entry n is the nibble written for the five-bit value n (MsWait.asm).
WriteTranslate:
    .byte $AB, $AD, $AE, $AF, $B5, $B6, $B7, $BA
    .byte $BB, $BD, $BE, $BF, $D6, $D7, $DA, $DB
    .byte $DD, $DE, $DF, $EA, $EB, $ED, $EE, $EF
    .byte $F5, $F6, $F7, $FA, $FB, $FD, $FE, $FF

    ; Leftover: three bytes, then zeros to RWTS's page.
    .byte $1C, $1C, $1C
    .res $1D00 - *

.endscope

; RWTS's variables, which the formatter and the head helpers share with it, where DOS 3.3 keeps them.

;; The half-track drive 1 of each slot's card is on: the byte for slot n is at $0478 + n, a screen hole.
Drive1HalfTracks = $0478

;; The half-track drive 2 of each slot's card is on, at $04F8 + n.
Drive2HalfTracks = $04F8

;; The address of the caller's IOB (2 bytes).
IobPointer = SavedStatus

;; The high byte of <IobPointer>.
IobPointerHigh = SavedStackPointer

;; The address of the DCT (2 bytes), copied from the IOB.
DctPointer = Address1

;; The drive RWTS has selected: bit 7 set for drive 1, clear for drive 2.
SelectedDrive = SavedOutputY

;; The sector in the address field just read.
FoundSector = AddressField + 1

;; The track in the address field just read; <SeekHalfTrack> also borrows the byte for the half-track it seeks to.
FoundTrack = AddressField + 2

;; The volume in the address field just read.
FoundVolume = AddressField + 3

;; The address fields left to read before giving up on the track (slot 0's screen-hole byte at $0578).
RetriesLeft = $0578

;; Reads, writes or formats as the IOB at A (high byte) and Y (low byte) asks, or only moves the head.
;;
;; At $1D00. As DOS 3.3's RWTS (Rwts1.asm): if the slot is not the one used last, it waits until the old slot's
;; drive has stopped, which it knows when the data latch stops changing. Then, as DOS 3.2's does (Rwts32.asm), it
;; reads the latch once more to see whether this slot's motor is turning, and turns it on either way; a motor counts
;; as off if the drive is not the one used last. If it was off, it waits seven of <DiskII::Wait>'s times 100
;; microseconds before the seek and, after it, until the motor-on count reaches zero, without DOS 3.3's check that
;; the count is already past it.
;; In: A = the IOB's address's high byte, Y = its low byte
;; Out: carry = clear, with the IOB's <Iob::VOLUME_FOUND> = the volume found (read, write), and its
;;   <Iob::PREVIOUS_SLOT> and <Iob::PREVIOUS_DRIVE> = this slot and drive, X = slot * 16, the motor off
;; Errors: carry = set and the code in <Iob::RETURN_CODE>: <RWTS_WRITE_PROTECTED>, <RWTS_VOLUME_MISMATCH>,
;;   <RWTS_DRIVE_ERROR>
;; Entry:
;;   TryTrack = carries out the command, with the head on the track
;;   Succeed = the success exit
;;   Fail = the failure exit
.proc Rwts

;; The slot times 16 for this call (slot 0's screen-hole byte at $05F8).
SlotTimes16 = $05F8

;; Where the IOB's DCT and buffer addresses are copied (4 bytes): <DctPointer>, then <SectorBuffer>.
Pointers = DctPointer

;; The motor-on count, <MotorTime> and <MotorTimeHigh>, counting up to 0.
MotorCount = MotorTime

;; The address fields from a wrong track before RWTS recalibrates.
MAX_SEEKS = 4

;; The seeks left before recalibrating (slot 0's screen-hole byte at $04F8).
SeeksLeft = $04F8

;; The recalibrations left, plus 1 (slot 0's screen-hole byte at $06F8).
RecalibrationsLeft = $06F8

;; One more than the recalibrations RWTS allows: it counts down before it tests.
RECALIBRATIONS = 2

;; The reads in a row that must see the same latch value before a drive counts as stopped.
STOP_READS = 8

;; The waits before a seek when the motor was off: <DiskII::Wait> with whatever A holds, 25.6 milliseconds once A is
;; 0.
START_WAITS = 7

;; The passes of the delay loop, which with the count's step make about 100 cycles, 100 microseconds.
DELAY_PASSES = $12

;; The address fields read after the first before RWTS gives up: 49 tries in all.
ADDRESS_RETRIES = $30

;; The track RWTS records before it recalibrates: track 96, half-track 192, far enough beyond track 34 that the
;; seek to track 0 stops the head against the stop whatever its real place.
RECALIBRATION_TRACK = $60

    ; The caller's IOB, the counts and the slot.
    sty IobPointer
    sta IobPointerHigh
    ldy #RECALIBRATIONS
    sty RecalibrationsLeft
    ldy #MAX_SEEKS
    sty SeeksLeft
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
    lda ReadMode,x
;; Waits until the latch reads the same eight times in a row.
WaitForStop:
    ldy #STOP_READS
    lda DataLatch,x
;; Compares the latch with its last value.
CompareLatch:
    cmp DataLatch,x
    bne WaitForStop                 ; it changed: still turning
    dey
    bne CompareLatch
    pla
    tax                             ; the new slot

    ; Is this slot's motor turning? One read of the latch against the one before it.
;; The test of this slot's motor, then the motor on.
SameSlot:
    lda ReadMode,x
    lda DataLatch,x
    lda DataLatch,x
    pha                             ; delay, for the data to change
    pla
    stx SlotTimes16
    cmp DataLatch,x
    php                             ; zero clear if the motor was turning
    lda MotorOn,x

    ; Copy the DCT and buffer addresses to DctPointer and SectorBuffer, then the motor count's high byte.
    ldy #Iob::DEVICE_TABLE
;; Copies the next byte.
CopyPointers:
    lda (IobPointer),y
    sta Pointers - Iob::DEVICE_TABLE,y
    iny
    cpy #Iob::BUFFER + 2
    bne CopyPointers
    ldy #DeviceTable::MOTOR_DELAY + 1
    lda (DctPointer),y
    sta MotorCount + 1

    ; Another drive than the last: the motor counts as off.
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ldy #Iob::PREVIOUS_DRIVE
    cmp (IobPointer),y
    beq SameDrive
    sta (IobPointer),y
    plp                             ; another drive: replace the saved flags with zero set, "the motor was off"
    ldy #0
    php
;; Selects the drive: bit 0 of the drive number is 1 for drive 1.
SameDrive:
    ror a
    bcc Drive2
    lda SelectDrive1,x
    bcs DriveSelected               ; always
;; Selects drive 2.
Drive2:
    lda SelectDrive2,x
;; Notes the drive: bit 7 set for drive 1.
DriveSelected:
    ror SelectedDrive

    ; If the motor was off, wait before moving the head.
    plp
    php
    bne GoToTrack
    ldy #START_WAITS
;; One of the waits.
StartDelay:
    jsr DiskII::Wait
    dey
    bne StartDelay
    ldx SlotTimes16                 ; Wait used X
;; Seeks to the IOB's track.
GoToTrack:
    ldy #Iob::TRACK
    lda (IobPointer),y
    jsr SeekTrack
    plp
    bne TryTrack                    ; the motor was on: go ahead

    ; The motor was off: wait until the motor-on count reaches zero.
;; Counts the motor up to speed.
WaitForMotor:
    ldy #DELAY_PASSES
;; About 100 cycles a pass, with the step of the count.
DelayLoop:
    dey
    bne DelayLoop
    inc MotorCount
    bne WaitForMotor
    inc MotorCount + 1
    bne WaitForMotor
    ; Falls into TryTrack.

;; Carries out the IOB's command with the head on the track: as DOS 3.3's (Rwts2.asm), with the 13-sector routines.
;;
;; The address field's sector is compared as it is, without DOS 3.3's interleave, and the formatter gets the volume
;; in <FormatVolume>. A wrong sector costs a try against <RetriesLeft>, so running out of them recalibrates rather
;; than failing. RWTS comes here with the motor running, the head on the IOB's track, and the flags from its motor
;; test on the stack.
;; In: X = slot * 16
TryTrack:
    ldy #Iob::COMMAND
    lda (IobPointer),y
    beq SeekOnly                    ; 0: only the seek
    cmp #RWTS_FORMAT
    beq Format
    ror a                           ; carry set for 1, read; clear for 2, write
    php
    bcs StartTries
    jsr DiskII::PreNibble           ; a write: make the values first
;; Starts counting the address fields.
StartTries:
    ldy #ADDRESS_RETRIES
    sty RetriesLeft
;; Reads an address field.
TryAddress:
    ldx SlotTimes16
    jsr DiskII::ReadAddressField
    bcc CheckTrack
;; Counts a try, and tries again.
NextTry:
    dec RetriesLeft
    bpl TryAddress

    ; No good address field in 49 tries: recalibrate. SetTrack records the head at track 96 (half-track 192), so
    ; the seek to track 0 steps out far enough to stop against track 0 whatever the head's real place, then it
    ; seeks the track again. The second time this happens, it's a drive error.
;; Recalibrates, unless it has once already.
Recalibrate:
    lda CurrentTrack
    pha
    lda #RECALIBRATION_TRACK
    jsr SetTrack
    dec RecalibrationsLeft
    beq DriveError
    lda #MAX_SEEKS
    sta SeeksLeft
    lda #0
    jsr SeekTrack
    pla
;; Seeks the track again.
SeekAgain:
    jsr SeekTrack
    jmp StartTries

    ; An address field: is the head on the right track? If not, the drive's record of the track is corrected to the
    ; one read, and it seeks again, up to SeeksLeft times before recalibrating.
;; Compares the track found with the track the head should be on.
CheckTrack:
    ldy FoundTrack
    cpy CurrentTrack
    beq RightTrack
    lda CurrentTrack
    pha
    tya
    jsr SetTrack
    pla
    dec SeeksLeft
    bne SeekAgain
    beq Recalibrate                 ; always
;; A drive error.
DriveError:
    pla
    lda #RWTS_DRIVE_ERROR
;; Drops the read or write flags from the stack and fails with the error in A.
FailWithFlags:
    plp
    jmp Fail
;; Command 0, the seek alone.
SeekOnly:
    beq Succeed                     ; always
;; The formatter, with the volume to write.
Format:
    ldy #Iob::VOLUME
    lda (IobPointer),y
    sta FormatVolume
    jmp Formatter::Format

    ; The right track. The volume found goes to the IOB; it must match the one asked for, unless that is 0.
;; Checks the volume.
RightTrack:
    ldy #Iob::VOLUME
    lda (IobPointer),y
    pha
    lda FoundVolume
    ldy #Iob::VOLUME_FOUND
    sta (IobPointer),y
    pla
    beq RightVolume
    cmp FoundVolume
    beq RightVolume
    lda #RWTS_VOLUME_MISMATCH
    bne FailWithFlags               ; always

    ; The right sector? If not, on to the next address field, counting it against RetriesLeft.
;; Checks the sector.
RightVolume:
    ldy #Iob::SECTOR
    lda FoundSector
    cmp (IobPointer),y
    bne NextTry

    ; The sector is under the head: read or write its data field.
    plp
    bcc Write
    jsr DiskII::ReadDataField
    php
    bcs NextTry                     ; a bad read: try again, the carry on the stack again
    plp
    jsr DiskII::PostNibble
    ldx SlotTimes16
    ; Falls into Succeed.

;; RWTS's success exit: stores A in the IOB's return code, turns the motor off and returns with the carry clear.
;; In: A = the return code, X = slot * 16
;; Out: carry = clear
Succeed:
    clc
    .byte $24                       ; bit zero page: skips the sec
;; RWTS's failure exit: stores the error in the IOB's return code, turns the motor off and returns with the carry
;; set.
;; In: A = the error, X = slot * 16
;; Out: carry = set
Fail:
    sec
    ldy #Iob::RETURN_CODE
    sta (IobPointer),y
    lda MotorOff,x
    rts
;; Writes the data field, failing if the disk is write-protected.
Write:
    jsr DiskII::WriteDataField
    bcc Succeed
    lda #RWTS_WRITE_PROTECTED
    bcs Fail                        ; always
.endproc

;; Moves the IOB's drive's head to track A.
;;
;; A drive whose DCT's <DeviceTable::WHOLE_TRACKS> has bit 0 set takes two half-track steps a track, so the track is
;; doubled for <SeekHalfTrack> and <CurrentTrack> halved after.
;; In: A = the track, X = slot * 16, SelectedDrive = the drive
;; Out: CurrentTrack = the track, the drive's screen hole = its half-track
;; Keeps: X
.proc SeekTrack
    pha
    ldy #DeviceTable::WHOLE_TRACKS
    lda (DctPointer),y
    ror a                           ; bit 0: two steps a track
    pla
    bcc SeekHalfTrack
    asl a
    jsr SeekHalfTrack
    lsr CurrentTrack
    rts
.endproc

;; Seeks to half-track A, keeping a record of each drive's place.
;;
;; Like DOS 3.3's, and unlike DOS 3.2's, it doesn't turn the phases off first; it holds the half-track in
;; <FoundTrack>'s byte, as DOS 3.2's does, where DOS 3.3's uses <TargetHalfTrack>.
;; In: A = the half-track, X = slot * 16, SelectedDrive = the drive
;; Keeps: X
.proc SeekHalfTrack

;; The half-track to seek to, held while the record is read.
Target = FoundTrack

    sta Target
    jsr SlotNumber
    lda Drive1HalfTracks,y
    bit SelectedDrive
    bmi HavePosition
    lda Drive2HalfTracks,y
;; The head's place, from the drive's record.
HavePosition:
    sta CurrentTrack
    lda Target
    bit SelectedDrive
    bmi RecordDrive1
    sta Drive2HalfTracks,y
    bpl Move                        ; always
;; Records drive 1's new half-track.
RecordDrive1:
    sta Drive1HalfTracks,y
;; Moves the head.
Move:
    jmp DiskII::MoveHead
.endproc

;; Gives the slot number for slot * 16.
;; In: X = slot * 16
;; Out: A = Y = the slot
;; Keeps: X
.proc SlotNumber
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    rts
.endproc

;; Records that the IOB's drive's head is on track A, as a half-track in the drive's screen hole.
;; In: A = the track, X = slot * 16
;; Out: SelectedDrive = the IOB's drive
;; Keeps: X
.proc SetTrack
    pha
    ldy #Iob::DRIVE
    lda (IobPointer),y
    ror a
    ror SelectedDrive
    jsr SlotNumber
    pla
    asl a
    bit SelectedDrive
    bmi Drive1
    sta Drive2HalfTracks,y
    bpl Return                      ; always
;; Records drive 1's half-track.
Drive1:
    sta Drive1HalfTracks,y
;; Returns.
Return:
    rts
.endproc

;; The formatter, DOS 3.2's.
.scope Formatter

;; How many self-sync bytes come before each address field: 80 on track 0, 2 more on each track after, and one
;; less each time a track is formatted again.
GapLength = SavedY

;; Formats the disk in the IOB's drive with volume <FormatVolume>, track 0 to track 34, and returns through RWTS's
;; exits: DOS 3.2's (Formatter.asm).
;;
;; At $1EA0. It moves the head to track 0 by seeking from half-track 128. Each track starts with about ten thousand
;; self-sync bytes, more than a turn of the disk, which erase it; then come the 13 sectors in the order 0, 10, 7, 4,
;; 1, 11, 8, 5, 2, 12, 9, 6, 3, each with <Formatter::GapLength> self-sync bytes, an address field and $FF nibbles where
;; the data field goes. After the track it waits, reads an address field, and expects sector 0; if not, it formats
;; the track again with gaps one byte shorter. The gaps start at 80 and grow by 2 a track.
;; In: X = slot * 16, FormatVolume = the volume, the drive running
;; Out: carry = clear (<Rwts::Succeed>)
;; Errors: carry = set with <RWTS_DRIVE_ERROR> if the disk is write-protected or the gaps would fall below 16
.proc Format

;; The runs of $FF nibbles left in a sector's data area.
GapCount = SavedX

;; The half-track the head is taken to be on before the first seek: 128, beyond any track.
START_HALF_TRACK = $80

;; The self-sync bytes before each address field on track 0.
FIRST_GAP = 80

;; The shortest gap: a track that fails to read back with a shorter one fails the format.
SHORTEST_GAP = 16

;; One more than the runs of 256 self-sync bytes that erase a track after the first gap's worth: 38 runs.
ERASE_RUNS = $27

;; The $FF nibbles where a sector's data field goes, before a last run of 256: 173 in all with it, 429.
DATA_AREA_FIRST = $AD

;; The runs of $FF nibbles in a data area, the first <DATA_AREA_FIRST> long and the second 256.
DATA_AREA_RUNS = 2

;; The sectors on a track.
SECTOR_COUNT = 13

;; What each sector's number adds, modulo <SECTOR_COUNT>, to the one before it: 10, that is three less.
SECTOR_STEP = 10

;; The tracks on a disk.
TRACK_COUNT = 35

    ; Track 0, from beyond the last track.
    lda #START_HALF_TRACK
    sta CurrentTrack
    lda #0
    sta FormatTrack
    jsr DiskII::MoveHead
    lda #DiskII::ODD_BITS
    sta FormatMask
    ldy #FIRST_GAP
;; Formats track <FormatTrack>, then the tracks after it.
;; In: Y = the gap's length, the head on the track
NextTrack:
    sty GapLength
    lda #ERASE_RUNS
    sta FormatSector

    ; Write mode, $FF in the latch.
    lda LoadLatch,x
    lda ReadMode,x
    lda #DiskII::SELF_SYNC
    sta WriteMode,x
    cmp DataLatch,x
    bit $00                         ; timing

    ; The self-sync bytes that erase the track: $FF every 36 cycles. The bcs is always taken.
;; Counts a byte of the run.
Erase:
    dey
    beq EraseRun
    pha
    pla
    nop
;; Stores a self-sync byte; the way into each run of 256.
EraseByte:
    pha
    pla
    nop
    nop
    sta LoadLatch,x
    cmp DataLatch,x
    bcs Erase                       ; always
;; A run done: counts it.
EraseRun:
    dec FormatSector
    bne EraseByte

    ; Each sector: GapLength self-sync bytes, 36 cycles apart, then its address field.
    ldy GapLength
    nop
    nop
    bne FirstGapByte                ; always
;; The delay before each self-sync byte but the first.
NextGapByte:
    pha
    pla
    pha
    pla
    cmp ($00,x)                     ; timing: 6 cycles
;; The way in for a gap's first byte, 2 cycles into the delay.
FirstGapByte:
    nop
;; Stores a self-sync byte; each later sector comes back here from <Format::WrapSector>.
StoreGapByte:
    sta LoadLatch,x
    cmp DataLatch,x
    dey
    bne NextGapByte

    ; The address field: D5 AA B5, the volume, track, sector and their checksum in 4-and-4, and DE AA EB.
    lda #DiskII::PROLOGUE_FIRST
    jsr DiskII::WriteFieldNibble
    lda #DiskII::PROLOGUE_SECOND
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::ADDRESS_MARK
    jsr DiskII::WriteFieldNibble::Shorter
    lda FormatVolume
    jsr DiskII::WriteFourAndFour
    lda FormatTrack
    jsr DiskII::WriteFourAndFour
    lda FormatSector
    jsr DiskII::WriteFourAndFour
    lda FormatVolume
    eor FormatTrack
    eor FormatSector                ; the checksum, written as WriteFourAndFour would, inline
    pha
    lsr a
    ora FormatMask
    sta LoadLatch,x
    cmp DataLatch,x
    pla
    ora #DiskII::ODD_BITS
    jsr DiskII::WriteFieldNibble
    lda #DiskII::EPILOGUE_FIRST
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::EPILOGUE_SECOND
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::EPILOGUE_THIRD
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::SELF_SYNC
    jsr DiskII::WriteFieldNibble::Shorter

    ; Where the data field goes: $FF nibbles, 32 cycles apart, 173 then 256 of them.
    ldy #DATA_AREA_RUNS
    sty GapCount
    ldy #DATA_AREA_FIRST
    bne StoreDataNibble             ; always
;; Counts a nibble of the run.
NextDataNibble:
    dey
    beq DataRun
    pha
    pla
    nop
;; Stores a $FF nibble; the way in.
StoreDataNibble:
    pha
    pla
    sta LoadLatch,x
    cmp DataLatch,x
    bcs NextDataNibble              ; always
;; A run done: counts it.
DataRun:
    dec GapCount
    bne StoreDataNibble
    ldy GapLength
    clc
    bit $00                         ; timing
    sta LoadLatch,x
    lda DataLatch,x

    ; The next sector: FormatSector + 10, less 13 if that is 13 or more. Reaching 13 exactly means sector 3, the
    ; last, is done. The carry is clear, so the sbc subtracts 13.
    lda FormatSector
    adc #SECTOR_STEP
    sta FormatSector
    sbc #SECTOR_COUNT - 1
    beq TrackWritten
    bcs WrapSector
    .byte $2C                       ; bit absolute: skips the sta, keeping FormatSector + 10
;; Stores the sector number less 13, and goes on to the gap before it.
WrapSector:
    sta FormatSector
    lda #DiskII::SELF_SYNC
    jmp StoreGapByte

    ; The track is written. Back to read mode; if the disk is write-protected, that is an error now.
;; Read mode, and the write-protect test.
TrackWritten:
    pha
    pla
    ldy GapLength
    lda LoadLatch,x
    lda ReadMode,x
    bmi Failed
    dey

    ; GapLength - 1 passes of 26 cycles, as long as DOS 3.2's wait takes, in two bytes fewer.
;; One pass of the pause.
Pause:
    pha
    pla
    pha
    pla
    pha
    pla
    dey
    bne Pause

    ; The first address field read must be sector 0's.
    jsr DiskII::ReadAddressField
    bcs ShorterGaps
    lda FoundSector
    beq AdvanceTrack
;; The track again, with gaps one byte shorter, unless they are too short already.
ShorterGaps:
    ldy GapLength
    dey
    cpy #SHORTEST_GAP
    bcc Failed
    jmp NextTrack

    ; On to the next track, with two more self-sync bytes in each gap.
;; The next track, if there is one.
AdvanceTrack:
    inc FormatTrack
    lda FormatTrack
    cmp #TRACK_COUNT
    bcs Finish                      ; all 35 done
    asl a                           ; the half-track
    jsr DiskII::MoveHead
    ldy GapLength
    iny
    iny
    sty GapLength
    jmp NextTrack
;; The disk is write-protected, or a track won't read back: a drive error.
Failed:
    lda #RWTS_DRIVE_ERROR
    jmp Rwts::Fail
;; All tracks formatted.
Finish:
    jmp Rwts::Succeed
.endproc

.endscope

; DiskII: the 4-and-4 writer and the nibble writer for address fields.
.scope DiskII continued

;; The bits that make the first nibble of a 4-and-4 pair from a byte shifted right, and the second from the byte:
;; every other bit set.
ODD_BITS = $AA

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; The first nibble is the byte shifted right with every other bit set, through <FormatMask>, the zero-page byte
;; that holds $AA: an `ora` zero page takes the 3 cycles the timing needs where `ora #$AA` takes 2.
;; In: A = the byte, X = slot * 16, FormatMask = $AA, the card in write mode
;; Keeps: X, Y
.proc WriteFourAndFour
    pha
    lsr a
    ora FormatMask
    sta LoadLatch,x
    cmp DataLatch,x
    pla
    cmp ($00,x)                     ; timing: 6 cycles
    ora #ODD_BITS
    ; Falls into WriteFieldNibble.
.endproc

;; Writes the nibble in A, 32 cycles after the last store when the caller's code between them is an `lda #nibble`
;; and a `jsr` to <WriteFieldNibble::Shorter>.
;; In: A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: Shorter = 2 cycles less delay
.proc WriteFieldNibble
    nop
;; 2 cycles less delay.
Shorter:
    pha
    pla
    nop
    sta LoadLatch,x
    cmp DataLatch,x
    rts
.endproc

.endscope

    ; Zeros to the end of the file.
    .res $1FF0 - *
