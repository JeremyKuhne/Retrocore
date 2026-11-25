; retrocore: style=strict
;; The card's firmware: formatting
;;
;; SmartPort FORMAT for the 3.5 drives: <FormatDisk> writes every track of the disk, 80 cylinders of one or two sides,
;; and reads each back before going on. A GCR track (400K and 800K) is written through the IWM byte by byte: sync
;; groups, then each sector's address field and an empty data field, in the order <Format::MakeInterleave> gives. An
;; MFM track (720K and 1440K) is written through the ISM's FIFO, as a PC's controller writes it: the gaps, the index
;; mark, then each sector's ID field and an empty data field. [DiskII.md](../../../../docs/DiskII.md) explains GCR
;; nibbles and address and data fields. FORMAT, the GCR track writer and its verifier go through page-zero vectors
;; (<FormatVector>, <WriteTrackVector>, <VerifyVector>), so a control call can replace them.

;; The formatter's routines and tables: the command, the track writers and what they share. The three routines the
;; page-zero vectors reach (<FormatDisk>, <WriteGcrTrack>, <VerifyGcrTrack>) are top level, between its pieces.
.scope Format

; The format kinds in <FormatKind>, which SETFORMAT chooses; 0 is the drive's default.

;; 400K: GCR on one side.
KIND_400K = $02

;; 720K: MFM, 9 sectors a track. Kinds below it are GCR.
KIND_720K = $08

;; 1440K: MFM, 18 sectors a track.
KIND_1440K = $0A

;; The second 1440K kind FORMATOPTIONS lists.
KIND_1440K_ALTERNATE = $0C

; The values the formatter writes.

;; <MediaMode>'s value for a 720K MFM disk being formatted.
MEDIA_MODE_720K = $20

;; <MediaMode>'s value for a 1440K MFM disk being formatted.
MEDIA_MODE_1440K = $40

;; <MfmGap> for 720K: the $4E bytes between sectors.
GAP_720K = $50

;; <MfmGap> for 1440K.
GAP_1440K = $65

;; The interleave a 1440K format starts with.
INTERLEAVE_1440K = $02

;; The interleave the formatter goes back to after a format.
DEFAULT_INTERLEAVE = $04

;; The cylinders of a 3.5 disk.
CYLINDERS = 80

;; The tries for each side of a track.
TRIES = $03

;; SmartPort FORMAT ($03) and ProDOS's format: goes through <FormatVector>, normally to <FormatDisk>.
.proc Command
    jmp FormatVector
.endproc

.endscope

;; Formats <Drive>'s disk, in the kind SETFORMAT chose or the drive's default (800K GCR, or on an FDHD drive 1440K MFM
;; for a high-density disk), reading each track back, then finds the new disk's format. A disk that fails is ejected.
;; Only Apple 3.5 drives call <FormatHook>, whose carry set refuses the format.
;; Out: carry = clear, ErrorCode = 0, or <ERROR_BAD_COMMAND> for the controller, <ERROR_OFFLINE>,
;;      <ERROR_DISK_SWITCHED> or <ERROR_WRITE_PROTECTED> from <Drives::CheckDisk>, <ERROR_BAD_CONTROL> for a kind the
;; drive or
;;      disk cannot take, <ERROR_IO> for a track that fails, or <Drives::IdentifyMedia>'s error for the formatted disk
.proc FormatDisk
    .using Format

    ; The controller, unit 0, has no disk.
    lda #ERROR_BAD_COMMAND
    ldx Drive
    bmi Fail

    ; A disk that can be written.
    jsr Cache::Forget
    lda #DRIVE_CLEAR_SWITCHED
    jsr Drives::SendCommand
    jsr Swim::UseGcr
    ldx Drive
    jsr Drives::CheckDisk
    bcc Checked
Fail:
    jmp SetError
Checked:
    bne Fail                        ; write-protected
    lda #DISK_TWO_SIDES
    sta DiskSides,x

    ; An FDHD drive can write MFM; an Apple 3.5 drive only GCR, and asks the hook.
    lda #DEVICE_FDHD
    bit DeviceKinds,x
    bne FdhdDrive
    lda FormatKind,x
    beq AskHook
    cmp #KIND_720K
    bcs BadKind
AskHook:
    jsr CallHook
    bcs BadKind
    bra Start

    ; Calls FormatHook, which ColdStart points at an RTS.
CallHook:
    jmp (FormatHook)

    ; An FDHD drive: 720K or GCR on a double-density disk, 1440K on a high-density one.
FdhdDrive:
    lda #SENSE_NOT_HIGH_DENSITY
    jsr Drives::SenseLine
    bcc HighDensity
    ldy FormatKind,x
    cpy #KIND_720K
    bne NotMfm
    lda #GAP_720K
    sta MfmGap
    lda #MEDIA_MODE_720K
    sta MediaMode,x
    bra Mfm
NotMfm:
    cpy #KIND_720K
    bcc Start
BadKind:
    lda #ERROR_BAD_CONTROL
    bra Fail
HighDensity:
    lda #MEDIA_MODE_1440K
    sta MediaMode,x
    lda #INTERLEAVE_1440K
    sta Interleave
    lda #GAP_1440K
    sta MfmGap
    ldx Drive
    lda FormatKind,x
    beq Mfm
    cmp #KIND_1440K
    beq Mfm
    cmp #KIND_1440K_ALTERNATE
    bne BadKind
Mfm:
    jsr Swim::UseMfm
    stz NibbleHighBits
    stz Nibble0

    ; The head to track 0, and the interleave and sides SETFORMAT chose.
Start:
    jsr Cache::Forget
    jsr Drives::MotorOn
    jsr Drives::Recalibrate
    bcs Failed
    jsr Drives::WaitReady
    bcs Failed
    ldy Drive
    ldx FormatKind,y
    beq FirstTrack
    lda FormatInterleave,y
    sta Interleave
    cpx #KIND_400K
    bne FirstTrack
    stz TwoSided

    ; Each side of each track, written and read back, with up to three tries.
FirstTrack:
    stz Side
    stz Track
NextSide:
    lda #TRIES
    sta Retries
Try:
    jsr Format::WriteTrack
    bcs Failed
    jsr Format::VerifyTrack
    bcc Verified
    jsr CountRetry
    bcc Try
    bra Failed
Verified:
    bit TwoSided
    bmi OtherSide
    lda #SIDE_SECOND
    sta Side
    jsr Format::WipeSecondSide
OtherSide:
    lda #SIDE_SECOND
    eor Side
    sta Side
    bne NextSide
    inc Track
    lda Track
    cmp #CYLINDERS
    bcc NextSide

    ; Done: the defaults back, and the new disk's format found.
    stz Side
    stz Track
    ldx Drive
    jsr Format::ForgetChoice
    jsr Drives::Recalibrate
    clc
    jsr Drives::IdentifyMedia
    bcs Eject
    rts

    ; A failure ejects the disk.
Failed:
    lda #ERROR_IO
Eject:
    pha
    ldx Drive
    jsr Format::ForgetChoice
    jsr EjectDisk
    pla
    jmp SetError
.endproc

; The formatter: the choices, the track writers' dispatch and the second side's wipe.
.scope Format continued

;; Forgets SETFORMAT's choice for a drive: the next FORMAT writes the defaults, two sides with interleave 4.
;; In: X = the drive
;; Keeps: X, Y
.proc ForgetChoice
    lda FormatKind,x
    beq Done
    lda #DISK_TWO_SIDES
    sta TwoSided
    lda #DEFAULT_INTERLEAVE
    sta Interleave
    stz FormatInterleave,x
    stz FormatKind,x
Done:
    rts
.endproc

;; The byte <Format::WipeSecondSide> writes.
WIPE_BYTE = $BB

;; Writes about a track's length of $BB bytes over the second side, for a single-sided GCR format; does nothing on
;; an MFM disk. It writes at the drive's speed for <Track>'s zone, so the side holds nothing a read could take for
;; a sector.
.proc WipeSecondSide
    bit SwimState
    bmi Done

    ; The count for Track's zone (16 tracks each).
    lda Track
    lsr a
    lsr a
    lsr a
    and #$0E
    sta Scratch
    jsr SelectReadHead
    ldx Scratch
    lda WipeLengths + 1,x
    tay
    lda WipeLengths,x
    tax

    ; Writing starts with the first byte, then one each time the IWM can take it.
    lda #WIPE_BYTE
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
Wait:
    bit Iwm::DataLatch
    bpl Wait
    sta Iwm::LoadLatch
    dex
    bne Wait
    dey
    bne Wait
    bit Iwm::ReadMode
    bit Iwm::DataLatch
Done:
    rts
.endproc

;; Each zone's count for <Format::WipeSecondSide>, a word whose low byte counts first: the wipe writes 1 + low +
;; 256 * (high - 1) bytes.
WipeLengths:
    .word $2594, $2274, $1F54, $1C34, $1914

;; Writes a whole track: an MFM disk's through <Format::WriteMfmTrack>, a GCR disk's through <WriteTrackVector>,
;; normally <WriteGcrTrack>.
;; Out: carry = set if it failed
.proc WriteTrack
    bit SwimState
    bpl Gcr
    jmp Format::WriteMfmTrack
Gcr:
    jmp WriteTrackVector
.endproc

.endscope

;; Writes a GCR track, the routine <WriteTrackVector> normally reaches: sync groups, then each sector's address
;; field and an empty data field (703 encoded zeros: the 12 tag bytes, the 512 data bytes and the checksum), in
;; the order <Format::MakeInterleave> builds. The first track of each zone waits first for the drive to reach the
;; zone's speed.
;; Out: carry = set if the IWM ran out of bytes to write (<DiskErrors> bit 6)
.proc WriteGcrTrack
;; The sync groups before the first sector.
FIRST_SYNC_GROUPS = $C8

;; The sync groups before each later sector.
SYNC_GROUPS = $0A

;; The bytes of a sync group: <SyncBytes>.
SYNC_GROUP_LENGTH = 5

;; The bytes of the address field's mark, from its last: <AddressMark>.
ADDRESS_MARK_LENGTH = 4

;; The address field's bytes, <AddressChecksum> through <AddressTrack>.
ADDRESS_FIELD_LENGTH = 5

;; The bytes from <DataMark> to the address field's epilogue: DE AA, $FF, a sync group, $FF, D5 AA AD, written last
;; first.
DATA_LEAD_LENGTH = $0C

;; The epilogue's DE AA.
EPILOGUE_LENGTH = 2

;; A zero, encoded.
ENCODED_ZERO = $96

;; The IWM's handshake bit that is clear once it has run out of bytes to write.
ISM_HANDSHAKE_NO_UNDERRUN = $40

    jsr Drives::Seek
    jsr Format::MakeAddressField
    jsr Drives::WaitReadyForever
    stz DiskErrors

    ; The first track of a zone, on side 0: a wait for the new speed.
    lda Side
    bne Start
    lda Track
    and #$0F
    bne Start
    lda Track
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda Format::ZoneDelays,x
    jsr DelayMillisecondPairs

    ; Writing starts with $FF; 200 sync groups lead the first sector, 10 each of the others.
Start:
    jsr SelectReadHead
    lda SectorsPerTrack
    sta SectorCount
    ldy #FIRST_SYNC_GROUPS
    lda #$FF
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
NextSector:
    ldx #SYNC_GROUP_LENGTH - 1
SyncByte:
    lda SyncBytes,x
WaitSync:
    bit Iwm::DataLatch
    bpl WaitSync
    sta Iwm::LoadLatch
    dex
    bpl SyncByte
    dey
    bne NextSector

    ; The address field: its mark, then track, sector, side, format and checksum, each encoded.
    ldx #ADDRESS_MARK_LENGTH - 1
MarkByte:
    lda AddressMark,x
WaitMark:
    bit Iwm::DataLatch
    bpl WaitMark
    sta Iwm::LoadLatch
    dex
    bpl MarkByte
    ldx #ADDRESS_FIELD_LENGTH - 1
AddressByte:
    ldy AddressChecksum,x
    lda GcrEncodeTable,y
WaitAddress:
    bit Iwm::DataLatch
    bpl WaitAddress
    sta Iwm::LoadLatch
    dex
    bpl AddressByte

    ; The address field's epilogue, a sync group and the data field's mark, which lie in that order in page zero.
    ldx #DATA_LEAD_LENGTH - 1
LeadByte:
    lda DataMark,x
WaitLead:
    bit Iwm::DataLatch
    bpl WaitLead
    sta Iwm::LoadLatch
    dex
    bpl LeadByte

    ; The data field: the sector, then 703 encoded zeros ($EB + 2 * $EA).
    ldx AddressSector
    lda GcrEncodeTable,x
WaitSector:
    bit Iwm::DataLatch
    bpl WaitSector
    sta Iwm::LoadLatch
    ldx #$03
    ldy #$EB
    bra Zero
NextRun:
    ldy #$EA
Zero:
    lda #ENCODED_ZERO
WaitZero:
    bit Iwm::DataLatch
    bpl WaitZero
    sta Iwm::LoadLatch
    dey
    bne Zero
    dex
    bne NextRun

    ; Its epilogue.
    ldx #EPILOGUE_LENGTH - 1
EpilogueByte:
    lda Epilogue + 1,x
WaitEpilogue:
    bit Iwm::DataLatch
    bpl WaitEpilogue
    sta Iwm::LoadLatch
    dex
    bpl EpilogueByte

    ; The next sector, from the end of InterleaveMap; its checksum changes by the sector.
    dec SectorCount
    beq Finish
    lda AddressSector
    eor AddressChecksum
    ldy SectorCount
    ldx InterleaveMap - 1,y
    stx AddressSector
    eor AddressSector
    ldy #$FF
    sty Iwm::LoadLatch
    sta AddressChecksum
    ldy #SYNC_GROUPS
    jmp NextSector

    ; An underrun so far (bit 6 of the handshake clear) is an error; then a last $FF, and the wait for it to go out.
Finish:
    lda #ISM_HANDSHAKE_NO_UNDERRUN
    and Iwm::DataLatch
    eor #ISM_HANDSHAKE_NO_UNDERRUN
    tsb DiskErrors
WaitLast:
    lda Iwm::DataLatch
    bpl WaitLast
    lda #$FF
    sta Iwm::LoadLatch
WaitEmpty:
    bit Iwm::DataLatch
    bvs WaitEmpty
    bit Iwm::ReadMode
    lda DiskErrors
    cmp #1
    rts
.endproc

.assert SyncBytes = DataMark + 4 && Epilogue = SyncBytes + 5, "WriteGcrTrack writes DataMark through Epilogue + 2."

; The formatter's GCR zone waits and verifier.
.scope Format continued

;; Each GCR zone's wait, in pairs of milliseconds (<DelayMillisecondPairs>), before its first track is written: 300
;; ms for the first, 50 for the others.
ZoneDelays:
    .byte $96, $19, $19, $19, $19

;; Reads back each sector of the track just written, through <VerifyVector>, normally <VerifyGcrTrack>.
;; Out: carry = set if a sector failed
.proc VerifyTrack
    jmp VerifyVector
.endproc

.endscope

;; Reads each sector of a GCR track once, the routine <VerifyVector> normally reaches, into the transfer buffer.
;; Out: carry = set if an address or data field could not be read, or a sector was out of range or seen twice
.proc VerifyGcrTrack
    jsr DelayMillisecond
    lda #<TransferBuffer
    sta BufferPointer
    sta SecondBufferPointer
    lda #>TransferBuffer
    sta BufferPointer + 1
    sta SecondBufferPointer + 1
    jsr SelectReadHead

    ; No sector seen yet.
    ldx SectorsPerTrack
    stx SectorCount
Clear:
    stz SectorFlags,x
    dex
    bpl Clear

    ; Each sector, once.
NextSector:
    jsr ReadAddressField
    bcs Failed
    ldx AddressSector
    cpx SectorsPerTrack
    bcs Bad
    lda SectorFlags,x
    bmi Bad
    lda #$FF
    sta SectorFlags,x
    jsr ReadDataField
    bcs Failed
    dec SectorCount
    bne NextSector
    clc
    rts
Bad:
    jsr Swim::EnsureIwm
Failed:
    sec
    rts
.endproc

; The formatter's address fields, interleave and MFM tracks.
.scope Format continued

;; <AddressSide>'s bit for the second side.
SIDE_BIT = $20

;; <AddressSide>'s bit for tracks 64 and up, which <AddressTrack>'s six bits cannot hold.
SIDE_HIGH_TRACK = $01

;; Works out a GCR track's sectors and interleave, and its first address field: sector 0, with the side, the
;; format byte (the interleave, with $20 for two sides) and the checksum.
.proc MakeAddressField
    lda Track
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda BlockMap::ZoneSectors,x
    sta SectorsPerTrack
    jsr Format::MakeInterleave
    lda Track
    and #$3F
    sta AddressTrack
    stz AddressSector

    ; The side byte: bit 0 for tracks 64 and up, bit 5 for the second side.
    lda Track
    and #$40
    beq LowTrack
    inc a
LowTrack:
    ldx Side
    beq FirstSide
    ora #SIDE_BIT
FirstSide:
    sta AddressSide

    ; The format byte, then the checksum of the four (the sector is 0).
    lda Interleave
    bit TwoSided
    bpl OneSide
    ora #MFM_FORMAT_TWO_SIDES
OneSide:
    sta AddressFormat
    eor AddressSide
    eor AddressTrack
    sta AddressChecksum
    rts
.endproc

;; Builds <InterleaveMap>: the track's sectors in the order they are written, read from the map's end. Each next sector
;; is <Interleave> places before the last, wrapping, on the next free place. An interleave of 0 becomes 1, and one
;; past the sectors less 2 is cut to that.
;; Out: carry = clear
;; Entry:
;;   Return = returns; <Format::WriteMfmTrack> branches here with carry set when the drive is not ready
.proc MakeInterleave
    lda Interleave
    bne Limit
    lda #1
    sta Interleave
Limit:
    lda SectorsPerTrack
    dec a
    dec a
    cmp Interleave
    bcs Clear
    sta Interleave

    ; Every place free ($FF).
Clear:
    ldx SectorsPerTrack
    inx
    lda #$FF
ClearPlace:
    sta InterleaveMap,x
    dex
    bpl ClearPlace

    ; Sector 0 at the end, then each next one Interleave places before, on a free place.
    ldx SectorsPerTrack
    dex
    ldy #0
Place:
    tya
    sta InterleaveMap,x
    iny
    cpy SectorsPerTrack
    beq Done
    txa
    sec
    sbc Interleave
    tax
Wrap:
    bpl Free
    txa
    clc
    adc SectorsPerTrack
    tax
Free:
    bit InterleaveMap,x
    bmi Place
    dex
    bra Wrap
Done:
    clc
Return:
    rts
.endproc

; The MFM track.

;; The ISM's handshake bit for the sense line.
ISM_HANDSHAKE_SENSE = $08

;; <Ism::WritePhase>'s value with every phase line an output and low.
PHASES_LOW = $F0

;; <Ism::WritePhase>'s value with every phase line an output, phase 2 high.
PHASES_PHASE2 = $F4

;; The index mark.
MFM_INDEX_ID = $FC

;; The ID field's mark.
MFM_ADDRESS_ID = $FE

;; An ID field's size code for 512-byte sectors.
MFM_SIZE_512 = $02

;; The zeros before each mark.
MFM_SYNC_ZEROS = $0C

;; The marks' sync bytes.
MFM_SYNC_MARKS = $03

;; The gap after the index (gap 4a), less the byte before it.
MFM_INDEX_GAP = $4F

;; The gap after the index mark (gap 1).
MFM_GAP1 = $32

;; The gap after an ID field (gap 2).
MFM_GAP2 = $16

;; <DiskErrors> for an error the ISM reported.
WRITE_ERROR = $34

;; <DiskErrors> for a track whose end did not come.
WRITE_TIMEOUT = $35

;; Writes an MFM track through the ISM: gap bytes until the sense line has gone low and high again, the index gap
;; and mark, then each sector's ID field (cylinder, side, sector from 1, size) and an empty data field, each with
;; its CRC, then gap bytes until the sense line, with phase 2 high, reads 1. The first track waits 600 ms first.
;; Out: carry = set if the drive was not ready, the ISM reported an error (DiskErrors = $34) or a wait ran out
;;      (DiskErrors = $35); else DiskErrors = 0
.proc WriteMfmTrack
;; <UnitWithHighBit>, borrowed: negative for 720K, which is double density.
DoubleDensity = UnitWithHighBit

    jsr Drives::Seek

    ; 9 sectors for 720K, 18 for 1440K.
    stz DoubleDensity
    lda #MFM_1440_SECTORS
    ldx Drive
    ldy FormatKind,x
    cpy #Format::KIND_720K
    bne Sectors
    lda #MFM_720_SECTORS
    dec DoubleDensity
Sectors:
    sta SectorsPerTrack
    sta SectorCount
    jsr Format::MakeInterleave
    jsr Drives::WaitReady
    bcs Format::MakeInterleave::Return
    lda Track
    bne Ready
    lda Side
    bne Ready
    lda #$96
    jsr DelayMillisecondPairs
    lda #$96
    jsr DelayMillisecondPairs

    ; The ISM ready to write, with an empty FIFO; the first sector is 1.
Ready:
    jsr SelectReadHead
    jsr Swim::EnterIsm
    bit Ism::ReadError
    lda #ISM_MODE_WRITE | ISM_MODE_ACTION
    sta Ism::ClearMode
    lda #ISM_MODE_WRITE
    sta Ism::SetMode
    lda #ISM_MODE_CLEAR_FIFO
    sta Ism::SetMode
    sta Ism::ClearMode
    sta AddressSector
    bit Ism::ReadError

    ; Gap bytes while the sense line reads 1, then while it reads 0, each wait limited.
    ldy #$34
    ldx #$35
    bit DoubleDensity
    bpl StartWrite
    ldy #$9A
    ldx #$1A
StartWrite:
    lda #MFM_GAP
    sta Ism::WriteData
    sta Ism::WriteData
    lda #ISM_MODE_ACTION
    sta Ism::SetMode
WaitLow:
    bit Ism::ReadHandshake
    bpl WaitLow
    beq Low
    lda #MFM_GAP
    sta Ism::WriteData
    lda #ISM_HANDSHAKE_SENSE
    dey
    bne WaitLow
    dex
    bne WaitLow
    jmp Timeout
Low:
    lda #MFM_GAP
    sta Ism::WriteData
    lda #ISM_HANDSHAKE_SENSE
WaitHigh:
    bit Ism::ReadHandshake
    bpl WaitHigh
    bne High
    lda #MFM_GAP
    sta Ism::WriteData
    lda #ISM_HANDSHAKE_SENSE
    dey
    bne WaitHigh
    dex
    bne WaitHigh
    jmp Timeout

    ; The index gap, 12 zeros, the index mark and the gap after it.
High:
    lda #MFM_GAP
    sta Ism::WriteData
    lda #PHASES_LOW
    sta Ism::WritePhase
    ldx #MFM_INDEX_GAP
    lda #MFM_GAP
IndexGap:
    bit Ism::ReadHandshake
    bpl IndexGap
    sta Ism::WriteData
    dex
    bne IndexGap
    ldx #MFM_SYNC_ZEROS
IndexZeros:
    bit Ism::ReadHandshake
    bpl IndexZeros
    stz Ism::WriteData
    dex
    bne IndexZeros
    ldx #MFM_SYNC_MARKS
IndexSync:
    bit Ism::ReadHandshake
    bpl IndexSync
    lda #MFM_INDEX_MARK
    sta Ism::WriteMark
    dex
    bne IndexSync
IndexMark:
    bit Ism::ReadHandshake
    bpl IndexMark
    lda #MFM_INDEX_ID
    sta Ism::WriteData
    ldx #MFM_GAP1
    lda #MFM_GAP
Gap1:
    bit Ism::ReadHandshake
    bpl Gap1
    sta Ism::WriteData
    dex
    bne Gap1
    bra IdZeros

    ; Each later sector starts with the gap after a data field (gap 3).
NextSector:
    ldx MfmGap
    lda #MFM_GAP
Gap3:
    bit Ism::ReadHandshake
    bpl Gap3
    sta Ism::WriteData
    dex
    bne Gap3

    ; The ID field: 12 zeros, three A1 marks, FE, the cylinder, side, sector and size, and its CRC.
IdZeros:
    ldx #MFM_SYNC_ZEROS
IdZero:
    bit Ism::ReadHandshake
    bpl IdZero
    stz Ism::WriteData
    dex
    bne IdZero
    ldx #MFM_SYNC_MARKS
IdSync:
    bit Ism::ReadHandshake
    bpl IdSync
    lda #MFM_MARK
    sta Ism::WriteMark
    dex
    bne IdSync
IdMark:
    bit Ism::ReadHandshake
    bpl IdMark
    lda #MFM_ADDRESS_ID
    sta Ism::WriteData
    lda Track
IdCylinder:
    bit Ism::ReadHandshake
    bpl IdCylinder
    sta Ism::WriteData
    lda #0
    ldx Side
    beq IdSide
    inc a
IdSide:
    bit Ism::ReadHandshake
    bpl IdSide
    sta Ism::WriteData
    lda AddressSector
IdSector:
    bit Ism::ReadHandshake
    bpl IdSector
    sta Ism::WriteData
IdSize:
    bit Ism::ReadHandshake
    bpl IdSize
    lda #MFM_SIZE_512
    sta Ism::WriteData
IdCrc:
    bit Ism::ReadHandshake
    bpl IdCrc
    stz Ism::WriteCrc

    ; The gap after it (gap 2).
    ldx #MFM_GAP2
    lda #MFM_GAP
Gap2:
    bit Ism::ReadHandshake
    bpl Gap2
    sta Ism::WriteData
    dex
    bne Gap2

    ; The data field: 12 zeros, three A1 marks, FB, 512 zeros and its CRC.
    ldx #MFM_SYNC_ZEROS
DataZero:
    bit Ism::ReadHandshake
    bpl DataZero
    stz Ism::WriteData
    dex
    bne DataZero
    ldx #MFM_SYNC_MARKS
DataSync:
    bit Ism::ReadHandshake
    bpl DataSync
    lda #MFM_MARK
    sta Ism::WriteMark
    dex
    bne DataSync
DataMarkByte:
    bit Ism::ReadHandshake
    bpl DataMarkByte
    lda #MFM_DATA_ID
    sta Ism::WriteData
    ldx #0
    lda #0
FirstPage:
    bit Ism::ReadHandshake
    bpl FirstPage
    sta Ism::WriteData
    dex
    bne FirstPage
SecondPage:
    bit Ism::ReadHandshake
    bpl SecondPage
    sta Ism::WriteData
    dex
    bne SecondPage
DataCrc:
    bit Ism::ReadHandshake
    bpl DataCrc
    stz Ism::WriteCrc

    ; The next sector, from the end of InterleaveMap, numbered from 1.
    dec SectorCount
    beq Finish
    ldy SectorCount
    lda InterleaveMap - 1,y
    inc a
    sta AddressSector
    jmp NextSector

    ; Five gap bytes, then gap bytes until the sense line, with phase 2 high, reads 1, for up to 1024 bytes.
Finish:
    lda #4
    sta Scratch
    ldx #5
EndGap:
    bit Ism::ReadHandshake
    bpl EndGap
    lda #MFM_GAP
    sta Ism::WriteData
    dex
    bne EndGap
    ldy #0
    lda #PHASES_PHASE2
    sta Ism::WritePhase
    ldx #MFM_GAP
WaitEnd:
    lda Ism::ReadHandshake
    bpl WaitEnd
    stx Ism::WriteData
    bit #ISM_HANDSHAKE_SENSE
    bne End
    dey
    bne WaitEnd
    dec Scratch
    bne WaitEnd
    bra Timeout

    ; The result, from the handshake's error bit; the write stopped and the SWIM back to the IWM.
End:
    and #ISM_HANDSHAKE_ERROR
    beq Written
    lda #WRITE_ERROR
    sec
    bra Result
Written:
    lda #0
    clc
Result:
    sta DiskErrors
    php
    lda #ISM_MODE_WRITE | ISM_MODE_ACTION
    sta Ism::ClearMode
    jsr Swim::LeaveIsm
    plp
    rts
Timeout:
    lda #WRITE_TIMEOUT
    sec
    bra Result
.endproc

.endscope
