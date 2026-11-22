; retrocore: style=strict
;; DOS 3.2 RWTS: the formatter ($BE9C-$BFDB where DOS runs)
;;
;; <Formatter::Format> formats all 35 tracks for INIT, which RWTS reaches with <RWTS_FORMAT> (Rwts32.asm). Each
;; track gets 13 address fields with self-sync bytes between them, but no data fields: where each sector's data
;; field will be, it writes $FF nibbles, and <DiskII::WriteDataField> writes the data field the first time the
;; sector is written. INIT then writes DOS, the VTOC and the catalog. DOS 3.3's formatter, in a module of its own,
;; writes data fields and checks every sector. After the formatter come the 4-and-4 writer it uses, a piece of the
;; DiskII scope, and a few bytes of code nothing calls. docs/DiskII.md explains the fields and self-sync bytes.

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
Failed:
    lda #RWTS_DRIVE_ERROR
    jmp Rwts::Fail
;; All tracks formatted.
Finish:
    jmp Rwts::Succeed
.endproc

.endscope

; DiskII: the 4-and-4 writer and the nibble writer for address fields, which DOS 3.3 keeps with its other
; low-level routines.
.scope DiskII continued

;; The bits that make the first nibble of a 4-and-4 pair from a byte shifted right, and the second from the byte:
;; every other bit set.
ODD_BITS = $AA

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; At $BFBB where DOS runs. The first nibble is the byte shifted right with every other bit set, through
;; <FormatMask>, the zero-page byte that holds $AA: an `ora` zero page takes the 3 cycles the timing needs where
;; `ora #$AA` takes 2.
;; In: A = the byte, X = slot * 16, FormatMask = $AA, the card in write mode
;; Keeps: X, Y
;; Also: WBYTE (DOS33)
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
;;
;; At $BFCA where DOS runs.
;; In: A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: Shorter = 2 cycles less delay
;; Also: WNIBLA (DOS33)
.proc WriteFieldNibble
    nop
;; Also: WNIBLB2 (DOS33)
Shorter:
    pha
    pla
    nop
    sta LoadLatch,x
    cmp DataLatch,x
    rts
.endproc

.endscope

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
