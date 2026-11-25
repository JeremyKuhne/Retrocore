; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: formatting a disk
;;
;; RWTS's format command (<RWTS_FORMAT>), which INIT uses. DOS 3.3's writes all 35 tracks with 16 sectors each, every
;; sector an address field (<DiskII::WriteAddressField>, WriteAddress.asm) and a data field of zeros
;; (<DiskII::WriteDataField>, WriteSector.asm), and reads each track back to check it. Between sectors it writes a gap
;; of self-sync nibbles set by <Formatter::GapLength>, which starts at 40 and is cut whenever a check finds a sector
;; other than 0 first after the end of the writing. At $BEAF-$BFB7 where DOS runs, followed by `PhysicalSectors`, the
;; table RWTS uses to number sectors.
;;
;; DOS 3.2's writes 13 address fields on each track, with self-sync bytes between them, but no data fields: where
;; each sector's data field will be, it writes $FF nibbles, and <DiskII::WriteDataField> writes the data field the
;; first time the sector is written. It checks only that each track's first sector reads back. At $BE9C-$BFBA where
;; DOS 3.2 runs, followed by the 4-and-4 writer it uses (FourAndFour.asm) and a few bytes of code nothing calls.
;;
;; Neither writes a VTOC or catalog: the file manager's <FileManager::InitDisk> (FileManagerIo.asm), which calls it,
;; writes those afterwards. The two versions' formatters differ throughout, so each has its own, chosen by <DOS32>.
;; docs/DiskII.md explains the fields and self-sync nibbles.

.if DOS32

;; The formatter, which RWTS runs for <RWTS_FORMAT>: it writes every track's address fields (DOS 3.2's writes no
;; data fields) and checks that each track reads back.
.scope Formatter

;; How many self-sync bytes come before each address field: 80 on track 0, 2 more on each track after, and one
;; less each time a track is formatted again.
GapLength = SavedY

;; Formats the disk in the IOB's drive with volume <FormatVolume>, track 0 to track 34, and returns through RWTS's
;; exits, <Rwts::Succeed> and <Rwts::Fail>.
;;
;; At $BE9C where DOS runs. It moves the head to track 0 by seeking from half-track 128, far enough out to stop
;; against track 0 from anywhere. Each track starts with about ten thousand self-sync bytes, more than a turn of
;; the disk, which erase it; the end of that run is the start of the track. Then come the sectors in the order 0,
;; 10, 7, 4, 1, 11, 8, 5, 2, 12, 9, 6, 3, each three less than the one before, modulo 13: for each,
;; <Formatter::GapLength> self-sync bytes, an address field and $FF nibbles where the data field goes.
;;
;; After the track it waits, reads an address field, and expects sector 0, the first one written. If it finds no
;; address field or another sector's, it formats the track again with the gaps one byte shorter. It starts with
;; gaps of 80 and adds 2 for each track after the first.
;; In: X = slot * 16, FormatVolume = the volume, the drive running
;; Out: carry = clear (<Rwts::Succeed>)
;; Errors: carry = set with <RWTS_DRIVE_ERROR> if the disk is write-protected (found after the first track) or the
;;   gaps would fall below 16
;; Also: DSKFORM (DOS33)
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

;; The $FF nibbles of the first run where a sector's data field goes, 173; a run of 256 and one more $FF follow, 430
;; in all.
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
    lda #DiskII::FOUR_AND_FOUR_BITS
    sta FormatMask
    ldy #FIRST_GAP
;; Formats track <FormatTrack>, then the tracks after it.
;; In: Y = the gap's length, the head on the track
;; Also: FORMTRK (DOS33)
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

    ; The self-sync bytes that erase the track: $FF every 36 cycles, which writes it with one 0 bit after it.
    ; FormatSector counts the runs of 256 down to 0, the first sector's number. The bcs is always taken: no byte is
    ; above $FF.
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

    ; The address field: D5 AA B5, the volume, track, sector and their checksum in 4-and-4, and DE AA EB, each
    ; nibble 32 cycles after the one before, and a last $FF.
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
    ora #DiskII::FOUR_AND_FOUR_BITS
    jsr DiskII::WriteFieldNibble
    lda #DiskII::EPILOGUE_FIRST
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::EPILOGUE_SECOND
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::EPILOGUE_THIRD
    jsr DiskII::WriteFieldNibble::Shorter
    lda #DiskII::SELF_SYNC
    jsr DiskII::WriteFieldNibble::Shorter

    ; Where the data field goes: $FF nibbles, 32 cycles apart, 173 then 256 of them, and one more after the runs.
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

    ; GapLength - 1 passes of 26 cycles before reading back.
;; One pass of the pause.
Pause:
    pha
    pla
    nop
    nop
    bit $00
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
;; Also: FORMERR (DOS33)
Failed:
    lda #RWTS_DRIVE_ERROR
    jmp Rwts::Fail
;; All tracks formatted.
;; Also: FORMDONE (DOS33)
Finish:
    jmp Rwts::Succeed
.endproc

.endscope

; DiskII: the 4-and-4 writer and the nibble writer for address fields, which DOS 3.3 keeps with its address
; field writer.
.include "FourAndFour.asm"

; Formatter: a few bytes nothing calls.
.scope Formatter continued

;; Code nothing calls: with X = $FF it goes on to the POSITION command's handler, <Commands::Position>; otherwise it
;; returns.
;;
;; At $BFD5 where DOS runs.
;; In: X = $FF to go on
.proc LeftoverPositionCheck
    inx
    beq ToPosition
    rts
;; Jumps on to POSITION.
ToPosition:
    jmp Commands::Position
.endproc

.endscope

.else

;; RWTS's format command: writes every track of a disk with its address fields and empty data fields, and checks
;; each track by reading it back. <Rwts> jumps to <Formatter::Format>, which returns from RWTS.
;;
;; docs/DiskII.md explains the fields and the self-sync nibbles between them. The file manager's INIT writes the
;; VTOC and catalog afterwards.
.scope Formatter

.if DIAGNOSTIC_RWTS
;; The diagnostic build (DIAGNOSTIC_RWTS = 1) leaves the formatter out, and Apple's listing then puts the format
;; command's label on <PhysicalSectors>.
;; Also: DSKFORM (DOS33)
Format = PhysicalSectors
.else
;; The number of self-sync nibbles, less one, that the formatter writes before each sector after the first.
;;
;; <Format> starts it at 40. When the check after writing a track (<WriteTrack::Verify>) finds that sector 0 is not
;; the first to come round, the gaps were too long for the track: it cuts the gap by 1, or by 2 above 16, and
;; rewrites the track, and gives up below 5. After track 0 checks, it is cut by 2 more if it is still 16 or more.
;; See: <Format>, <WriteTrack>, <WriteTrack::Verify>
;; Also: NSYNC (DOS33)
GapLength = Address5High

;; Formats the disk in the IOB's slot and drive with the IOB's volume number, and turns the motor off.
;;
;; RWTS jumps here, so the RTS at the end returns from RWTS. It first records the head as being at half-track $A0,
;; further in than any track, so the first seek, to track 0, steps the head out until it stops against track 0.
;; For each track it seeks, writes and checks the track (<WriteTrack>), then finds sector 0 and reads it once more:
;; so every track's writing starts a fixed time after sector 0 of the track before has passed. It also uses what
;; the routines it calls use.
;; In:    X = slot * 16, the IOB's volume = the volume to write, the drive running
;; Out:   carry = clear on success, with the motor off and the IOB's return code not written
;; Errors: carry = set and the IOB's return code <RWTS_FORMAT_ERROR> when a track cannot be written or checked; if
;;   sector 0 cannot then be found, the return code gets whatever A holds (see <Format::FindSector0>)
;; Uses:  A, Y, FormatVolume, FormatMask, FormatTrack, FormatSector, GapLength, RetriesLeft, DiskII::HighBits,
;;   DiskII::LowBits, SectorsChecked
;; Also: DSKFORM (DOS33)
.proc Format

;; The track the head is first said to be on, 80: half-track $A0, further in than any track.
FAR_TRACK = $50

;; The gap's length, less one, to start with: 40, for 41 self-sync nibbles.
FIRST_GAP = $28

;; The count <RetriesLeft> starts at to find sector 0 after a track checks, 48: 47 tries.
SECTOR_0_TRIES = $30

    ldy #Iob::VOLUME
    lda (IobPointer),y
    sta FormatVolume
    lda #DiskII::FOUR_AND_FOUR_BITS
    sta FormatMask                  ; for WriteAddressField's timing
    ldy #DiskII::LOW_BITS_SIZE
    lda #0
    sta FormatTrack

    ; Every sector is written as 256 zeros: clear LowBits and HighBits.
;; Clears the next LowBits value.
;; Also: CLRNBUF2 (DOS33)
ClearLowBits:
    sta DiskII::LowBits-1,y
    dey
    bne ClearLowBits

;; Clears the next HighBits value.
;; Also: CLRNBUF1 (DOS33)
ClearHighBits:
    sta DiskII::HighBits,y
    dey
    bne ClearHighBits
    lda #FAR_TRACK
    jsr SetTrack                    ; pretend the head is at half-track $A0
    lda #FIRST_GAP
    sta GapLength

;; Seeks, writes and checks the next track.
;; Also: FORMTRK (DOS33)
NextTrack:
    lda FormatTrack
    jsr SeekTrack
    jsr WriteTrack

;; Fails if the track could not be written or checked. Nothing branches here.
;; Also: FORMERR1 (DOS33)
CheckWrite:
    lda #RWTS_FORMAT_ERROR
    bcs Failed
    lda #SECTOR_0_TRIES
    sta RetriesLeft

    ; Find sector 0 and read its data field. If 47 tries fail, Failed stores A as the return code, but A then holds
    ; whatever the last ReadAddressField, ReadDataField or LDA FoundSector left in it, not RWTS_FORMAT_ERROR.
;; Reads address fields until sector 0's, and reads its data field.
;; Also: FINDS0 (DOS33)
FindSector0:
    sec
    dec RetriesLeft
    beq Failed
    jsr DiskII::ReadAddressField
    bcs FindSector0
    lda FoundSector
    bne FindSector0
    jsr DiskII::ReadDataField
    bcs FindSector0

    ; The next track, up to the last.
    inc FormatTrack
    lda FormatTrack
    cmp #TRACKS_PER_DISK
    bcc NextTrack
    clc
    bcc Finish                      ; always

;; Stores A as the IOB's return code and fails.
;; Also: FORMERR (DOS33)
Failed:
    ldy #Iob::RETURN_CODE
    sta (IobPointer),y
    sec

;; Turns the motor off and returns, from RWTS.
;; Also: FORMDONE (DOS33)
Finish:
    lda MotorOff,x
    rts
.endproc

;; Writes the 16 sectors of track <FormatTrack>, then checks them (<WriteTrack::Verify>); rewrites the track until it
;; checks or cannot be fixed.
;;
;; Sector 0 comes after 129 self-sync nibbles and the others after <GapLength> + 1. Each sector is an address field
;; and a data field from <DiskII::HighBits> and <DiskII::LowBits>. It also uses what the routines it calls use.
;; In:    X = slot * 16, FormatTrack = the track, FormatVolume = the volume, GapLength = the gap, FormatMask = $AA,
;;   DiskII::HighBits = the data, DiskII::LowBits = the same, the head on the track
;; Out:   carry = clear if the track was written and checked
;; Errors: carry = set if the disk is write-protected or the track would not check
;; Uses:  A, Y, FormatSector, GapLength, RetriesLeft, SectorsChecked, AddressField
;; Keeps: X
;; Entry: Verify = checks the track without writing it
;; Also: WTRACK16 (DOS33)
.proc WriteTrack

;; The self-sync nibbles before sector 0, less one: 128.
FIRST_SYNC = 128

;; The count <RetriesLeft> starts at for the check, 48; also the value each sector's <SectorsChecked> byte starts
;; at, which is positive: not read yet.
CHECK_TRIES = $30

;; The gap length above which a gap is cut by 2 rather than 1, 16.
LONG_GAP = $10

;; The shortest gap the check accepts, 5: shorter, and the format fails.
SHORTEST_GAP = 5

    lda #0
    sta FormatSector
    ldy #FIRST_SYNC
    bne WriteSector                 ; always

;; Takes the gap for a sector after the first.
;; Also: WSECT (DOS33)
NextSector:
    ldy GapLength

;; Writes the gap, the address field and the data field.
;; Also: WSECT0 (DOS33)
WriteSector:
    jsr DiskII::WriteAddressField
    bcs Return                      ; write-protected
    jsr DiskII::WriteDataField
    bcs Return
    inc FormatSector
    lda FormatSector
    cmp #SECTORS_PER_TRACK
    bcc NextSector

;; Checks the track just written: the first address field to pass must be sector 0's, and all 16 sectors must read
;; correctly within about 48 tries.
;;
;; Writing ended just after sector 15's data field. After waiting 50 cycles for each of <GapLength>, it reads the
;; next address field. If that is not sector 0, the gaps are shortened, <GapLength> cut by 1, or by 2 while it is
;; above 16, and the track is rewritten; below 5 the format fails. Otherwise it reads sectors, marking each in
;; <SectorsChecked>, until all 16 have been read. After track 0 checks, <GapLength> is cut by 2 if it is still 16 or
;; more.
;;
;; To rewrite a track, it waits for sector 15 to pass and branches back to <WriteTrack>, so that the new sector 0
;; starts just after the old sector 15's data field.
;; In:    X = slot * 16, FormatTrack = the track, GapLength = the gap
;; Out:   carry = clear if the track checked
;; Errors: carry = set if it did not and could not be rewritten
;; Also: VTRACK (DOS33)
Verify:
    ldy #SECTORS_PER_TRACK - 1
    sty FormatSector                ; sectors still to find, less 1
    lda #CHECK_TRIES
    sta RetriesLeft

;; Marks the next sector not read yet.
;; Also: CLRFOUND (DOS33)
ClearChecked:
    sta a:SectorsChecked,y
    dey
    bpl ClearChecked

    ; 50 cycles for each of GapLength: three calls to an RTS take 36.
    ldy GapLength

;; Waits 50 cycles.
;; Also: S0DELAY (DOS33)
Pause:
    jsr Return
    jsr Return
    jsr Return
    pha
    pla
    nop
    dey
    bne Pause
    jsr DiskII::ReadAddressField
    bcs FindSector15
    lda FoundSector
    beq CheckData                   ; sector 0 first: check the data

    ; Not sector 0: shorten the gaps.
    lda #LONG_GAP
    cmp GapLength                   ; carry set if GapLength is 16 or less...
    lda GapLength
    sbc #1                          ; ...subtracting 1, else 2
    sta GapLength
    cmp #SHORTEST_GAP
    bcs FindSector15

;; Gaps this short: gives up. Nothing branches here.
;; Also: VERR (DOS33)
GiveUp:
    sec
    rts

;; Reads the next address field.
;; Also: VSECT (DOS33)
NextAddress:
    jsr DiskII::ReadAddressField
    bcs TryFailed

;; Reads its data field.
;; Also: VDATA (DOS33)
CheckData:
    jsr DiskII::ReadDataField
    bcc SectorRead

;; Counts a failed try.
;; Also: VERR1 (DOS33)
TryFailed:
    dec RetriesLeft
    bne NextAddress

    ; Find sector 15 and read its data field, then rewrite the track from there. Up to RetriesLeft tries: 256 when
    ; the check above ran out of its own.
;; Reads address fields until sector 15's, and reads its data field, to rewrite the track after it.
;; Also: S15LOC (DOS33)
FindSector15:
    jsr DiskII::ReadAddressField
    bcs NotSector15
    lda FoundSector
    cmp #SECTORS_PER_TRACK - 1
    bne NotSector15
    jsr DiskII::ReadDataField
    bcc WriteTrack

;; Counts a failed try at finding sector 15, failing when none is left.
;; Also: NOTS15 (DOS33)
NotSector15:
    dec RetriesLeft
    bne FindSector15
    sec

;; Returns; a JSR to it is a 12-cycle delay, for <Pause>.
;; Also: WEXIT2 (DOS33)
Return:
    rts

;; A sector read correctly: marks it. A sector read a second time counts as a failed try.
;; Also: SECTOK (DOS33)
SectorRead:
    ldy FoundSector
    lda a:SectorsChecked,y
    bmi TryFailed                   ; read already
    lda #$FF
    sta a:SectorsChecked,y
    dec FormatSector
    bpl NextAddress

    ; All 16 read. After track 0, shorten long gaps by 2.
    lda FormatTrack
    bne Succeed
    lda GapLength
    cmp #LONG_GAP
    bcc Return                      ; carry clear: success
    dec GapLength
    dec GapLength

;; The track checked.
;; Also: WEXIT1 (DOS33)
Succeed:
    clc
    rts
.endproc
.endif

.endscope

.if DIAGNOSTIC_RWTS = 0
;; The end of the relocator's range for RWTS proper and the formatter, from <RwtsCodeStart>, the byte after it;
;; the tables after it hold no addresses. See Relocator.asm.
;; Also: AEC2 (DOS33, DOS31)
RwtsCodeEnd:

; Formatter: the check's table.
.scope Formatter continued

;; One byte per sector while a track is checked, negative once the sector has been read.
;; Also: FOUND (DOS33)
SectorsChecked:
.if YEAR = 1983
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
.else
    ; Leftover: what the 1980 master holds here.
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
.endif

.endscope
.endif

;; The sector number on the disk (physical) for each sector number DOS asks for in the IOB (logical).
;;
;; The formatter numbers the sectors on a track 0 to 15 in order. Logical 0 and 15 keep their numbers; logical
;; sectors 14 down to 1 are physical 2, 4, ... 14, then 1, 3, ... 13: read in descending order, each comes two
;; physical sectors after the one before (three where the order wraps round), not right behind it. Programs that
;; want another order patch it. At $BFB8 where DOS runs.
;; Also: INTRLEAV (DOS33)
PhysicalSectors:
.assert MASTER || DIAGNOSTIC_RWTS || * = $BFB8, "PhysicalSectors is at $BFB8 where DOS runs."
    .byte $00, $0D, $0B, $09
    .byte $07, $05, $03, $01
    .byte $0E, $0C, $0A, $08
    .byte $06, $04, $02, $0F

.endif
