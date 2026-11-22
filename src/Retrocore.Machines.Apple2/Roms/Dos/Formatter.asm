; retrocore: style=strict
;; DOS 3.3 RWTS: formatting a disk
;;
;; RWTS's format command (<RWTS_FORMAT>), which INIT uses: it writes all 35 tracks with 16 sectors each, every sector an
;; address field (<DiskII::WriteAddressField>, WriteAddress.asm) and a data field of zeros (<DiskII::WriteDataField>,
;; WriteSector.asm), and reads each track back to check it. Between sectors it writes a gap of self-sync nibbles set by
;; <Formatter::GapLength>, which starts at 40 and is cut whenever a check finds a sector other than 0 first after the
;; end of the writing. At $BEAF-$BFB7 where DOS runs, followed by <PhysicalSectors>, the table RWTS uses to number
;; sectors. It writes no VTOC or catalog: the file manager's <FileManager::InitDisk> (FileManagerIo.asm), which calls
;; it, writes those afterwards. docs/DiskII.md explains the fields and self-sync nibbles.

;; RWTS's format command: writes every track of a disk with its address fields and empty data fields, and checks
;; each track by reading it back. <Rwts> jumps to <Formatter::Format>, which returns from RWTS.
;;
;; docs/DiskII.md explains the fields and the self-sync nibbles between them. The file manager's INIT writes the
;; VTOC and catalog afterwards.
.scope Formatter

.if DIAGNOSTIC_RWTS
;; The diagnostic build (DIAGMODE = 1) leaves the formatter out, and Apple's listing then puts the format command's
;; label on <PhysicalSectors>.
;; Also: DSKFORM (DOS33)
Format = PhysicalSectors
.else
;; The number of self-sync nibbles, less one, that the formatter writes before each sector after the first.
;;
;; <Format> starts it at 40. When the check after writing a track (<WriteTrack::Verify>) finds that sector 0 is not
;; the first to come round, the gaps were too long for the track: it cuts the gap by 1, or by 2 above 16, and
;; rewrites the track, and gives up below 5. After track 0 checks, it is cut by 2 more while it is 16 or more.
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

;; The gap's length, less one, to start with: 40 self-sync nibbles.
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

;; The gap length above which a gap is cut by 2 rather than 1, 16; also the length track 0's check leaves it below.
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
