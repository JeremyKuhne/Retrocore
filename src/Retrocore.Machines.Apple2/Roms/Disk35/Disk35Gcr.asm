; retrocore: style=strict
;; The card's firmware: GCR address and data fields
;;
;; How the card finds, reads and writes a sector on an Apple 3.5 disk, which is written in GCR (group code
;; recording): each sector is an address field (D5 AA 96, five 6-and-2 nibbles, DE AA) and a data field (D5 AA AD,
;; the sector number, 12 tag bytes and 512 data bytes packed three bytes to four nibbles, three checksum bytes, DE
;; AA). [DiskII.md](../../../../docs/DiskII.md) explains nibbles, marks and the 6-and-2 encoding, which the 3.5 disk
;; shares with the Disk II's 16-sector disks. <ReadAddressField>, <ReadDataField> and <WriteDataField> choose
;; between this file's routines and the MFM ones in Disk35Mfm.asm; the GCR routines are reached through the
;; page-zero vectors (<ReadAddressVector> and the rest), which control calls can point elsewhere.
;;
;; The read and write loops count cycles: at the card's 2 MHz a GCR byte arrives about every 32 cycles, and some
;; reads and writes in the middle of a group take or give a byte without waiting for the IWM's handshake, because
;; the loop's own cycles leave the byte there. A change to these loops' instructions would break that.

; The 3.5 drive's registers this file reads (see <Drives::SenseLine>).

;; The drive register that gives the read data; <Drives::SelectHead> then picks the head.
REGISTER_READ_DATA = $01

; GCR.

;; The lowest valid 6-and-2 disk byte: <GcrDecode> holds the values of $96-$FF.
FIRST_DISK_BYTE = $96

;; How long <ReadGcrAddressField> looks for an address mark: this many times 256 disk bytes.
ADDRESS_SEARCH_PAGES = $08

;; One more than the disk bytes <ReadGcrDataField> looks at for the data mark: it counts down before each byte.
DATA_MARK_SEARCH = $19

;; The tag bytes of a GCR sector, which come before its 512 data bytes.
TAG_BYTE_COUNT = 12

;; The last index of the three nibble lanes (<NibbleLane1>, <NibbleLane2> and <NibbleLane3>): a sector is 175 groups of
;; three bytes, stored from this index down to 1 (the third lane has one byte fewer, from one less).
LAST_GROUP = $AF

;; The groups the 12 tag bytes take, at the lanes' top.
TAG_GROUPS = 4

;; The last group of the data bytes, below the tags.
LAST_DATA_GROUP = LAST_GROUP - TAG_GROUPS

; How a IIgs host reports, in WriteProgress, its copy of a block it writes into the card while the card
; nibblizes it.

;; The host is copying the block's second half.
PROGRESS_SECOND_HALF = $C1

;; How long <NibblizeSector> waits, in 5-cycle loops, when the host has only started the first half.
FIRST_HALF_DELAY = $C8

;; Finds the next sector's address field, by GCR or by MFM as the disk is.
;; Out: carry = set if no good field for the wanted track and side was read, with <DiskErrors> saying why
;;      (<DISK_ERROR_NO_FIELD>, <DISK_ERROR_WRONG_TRACK>, <DISK_ERROR_BAD_FIELD> or <DISK_ERROR_WRONG_SIDE>);
;;      <AddressTrack>, <AddressSector>, <AddressSide> and AddressFormat = the field read
.proc ReadAddressField
    bit SwimState
    bpl Gcr
    jmp ReadMfmAddressField
Gcr:
    jmp ReadAddressVector
.endproc

;; The routine <ReadAddressVector> normally goes to: reads a GCR address field (D5 AA 96, the track, sector, side,
;; format and checksum, DE AA), looking through about 2048 disk bytes for its mark.
;;
;; The side field's bit 0 is the track's bit 6 (tracks 64-79), and its bit 5 the side. The format byte's bit 5 says
;; the disk has two sides, which goes to <DiskSides> for the drive, as the format byte goes to <LastFormatByte>, even
;; when the field is for another track or side.
;; Out: carry = set if no good field for <Track> and <Side> was read, with DiskErrors = <DISK_ERROR_NO_FIELD>,
;;      <DISK_ERROR_WRONG_TRACK> (the drive's <CurrentTrack> then holds the track found), <DISK_ERROR_BAD_FIELD>
;;      or <DISK_ERROR_WRONG_SIDE>; <AddressChecksum> to AddressTrack = the field read
.proc ReadGcrAddressField
    jsr SelectReadHead
    stz DiskErrors
    lda Iwm::DataLatch
    lda Iwm::ReadMode
    lda #ADDRESS_SEARCH_PAGES
    sta WorkPointer
    ldy #$00

    ; The mark, D5 AA 96, compared from the end of AddressMark down.
FirstMarkByte:
    ldx #$02
NextByte:
    dey
    bne Wait
    dec WorkPointer
    beq NotFound
Wait:
    lda Iwm::DataLatch
    bpl Wait
    cmp AddressMark,x
    bne FirstMarkByte
    dex
    bpl NextByte

    ; The five fields, the track first, into AddressTrack down to AddressChecksum; with the checksum they XOR to 0.
    ldx #$04
    stz HeaderChecksum
NextField:
    ldy Iwm::DataLatch
    bpl NextField
    lda GcrDecode - FIRST_DISK_BYTE,y
    sta AddressChecksum,x
    eor HeaderChecksum
    sta HeaderChecksum
    dex
    bpl NextField
    tay
    bne BadField

    ; The epilogue, DE AA.
WaitEpilogue1:
    ldx Iwm::DataLatch
    bpl WaitEpilogue1
    cpx Epilogue + 2
    bne BadField
WaitEpilogue2:
    ldx Iwm::DataLatch
    bpl WaitEpilogue2
    cpx Epilogue + 1
    bne BadField

    ; What the format byte says of the disk.
    ldx Drive
    lda AddressFormat
    sta LastFormatByte,x
    and #$20
    asl a
    asl a
    sta DiskSides,x

    ; The side, then the track, with its bit 6 from the side field's bit 0.
    lda AddressSide
    eor Side
    lsr a
    bne WrongSide
    lda AddressTrack
    bcc CheckTrack
    ora #$40
CheckTrack:
    cmp Track
    beq Found
    ldx Drive
    sta CurrentTrack,x
    lda #DISK_ERROR_WRONG_TRACK
    bra Fail
Found:
    clc
    rts
WrongSide:
    lda #DISK_ERROR_WRONG_SIDE
    bra Fail
NotFound:
    lda #DISK_ERROR_NO_FIELD
    bra Fail
BadField:
    lda #DISK_ERROR_BAD_FIELD
Fail:
    tsb DiskErrors
    sec
    rts
.endproc

    ; The entries of GcrDecode for disk bytes $8F-$95, which are never valid. Bytes $80-$8E would index the end of
    ; ReadGcrAddressField's code; they never come from a good disk.
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; The 6-and-2 GCR decode table: the six-bit value of each disk byte from $96 to $FF, read as
;; `GcrDecode - FIRST_DISK_BYTE,x` with the disk byte in X. A byte that is not a valid nibble holds a value of $80
;; or more. The table starts $96 bytes after a page boundary (the `.assert` below checks it), so
;; the indexed reads never cross a page, which would cost the read loops a cycle.
GcrDecode:
    .byte $00, $01, $98, $99, $02, $03, $9C, $04, $05, $06, $A0, $A1, $A2, $A3, $A4, $A5
    .byte $07, $08, $A8, $A9, $AA, $09, $0A, $0B, $0C, $0D, $B0, $B1, $0E, $0F, $10, $11
    .byte $12, $13, $B8, $14, $15, $16, $17, $18, $19, $1A, $C0, $C1, $C2, $C3, $C4, $C5
    .byte $C6, $C7, $C8, $C9, $CA, $1B, $CC, $1C, $1D, $1E, $D0, $D1, $D2, $1F, $D4, $D5
    .byte $20, $21, $D8, $22, $23, $24, $25, $26, $27, $28, $E0, $E1, $E2, $E3, $E4, $29
    .byte $2A, $2B, $E8, $2C, $2D, $2E, $2F, $30, $31, $32, $F0, $F1, $33, $34, $35, $36
    .byte $37, $38, $F8, $39, $3A, $3B, $3C, $3D, $3E, $3F
.assert <(GcrDecode - FIRST_DISK_BYTE) = 0, "GcrDecode's reads must not cross a page."

;; Selects the drive's read-data register for <Side>'s head and puts the IWM in read mode.
;; Keeps: X, Y
.proc SelectReadHead
    lda #REGISTER_READ_DATA
    jsr Drives::SenseLine
    jsr Drives::SelectHead
    bit Iwm::DataLatch
    bit Iwm::ReadMode
    rts
.endproc

;; Reads the data field after an address field, by GCR or by MFM as the disk is, into the pages at <BufferPointer> and
;; <SecondBufferPointer>.
;; Out: carry = set if it failed, with <DiskErrors> saying why (<DISK_ERROR_NO_FIELD>, <DISK_ERROR_BAD_EPILOGUE> or
;;      <DISK_ERROR_BAD_CHECKSUM>; nothing for an MFM data mark not found)
.proc ReadDataField
    bit SwimState
    bpl Gcr
    jmp ReadMfmDataField
Gcr:
    jmp ReadDataVector
.endproc

;; The routine <ReadDataVector> normally goes to: reads a GCR data field (D5 AA AD, the sector number, 12 tag bytes
;; to <TagBytes> and 512 data bytes, three checksum bytes, DE AA) into the pages at <BufferPointer> and
;; <SecondBufferPointer>, whose low bytes must be 0: it fills each page until its low byte comes round to 0 again.
;;
;; Each group of four nibbles is the three bytes' high bits, then their low six bits. The three checksums
;; (<Checksum0>-Checksum2) are rotated and added as the bytes come, each byte being stored XORed with one of them;
;; the field's own checksum bytes then XOR them to 0.
;; In: AddressSector = the sector of the address field just read
;; Out: carry = set if it failed, with DiskErrors = <DISK_ERROR_NO_FIELD> (no mark, or another sector's field),
;;      <DISK_ERROR_BAD_CHECKSUM>, or <DISK_ERROR_BAD_EPILOGUE> (which alone is a failure too)
.proc ReadGcrDataField
    stz Checksum2
    stz Checksum1
    stz Checksum0
    stz DiskErrors
    ldy #DATA_MARK_SEARCH

    ; The mark, D5 AA AD.
FirstMarkByte:
    ldx #$02
NextMarkByte:
    dey
    beq NotFound
WaitMark:
    lda Iwm::DataLatch
    bpl WaitMark
    cmp DataMark,x
    bne FirstMarkByte
    dex
    bpl NextMarkByte

    ; The sector number, which must be the address field's.
    ldy #TAG_BYTE_COUNT
WaitSector:
    ldx Iwm::DataLatch
    bpl WaitSector
    lda GcrDecode - FIRST_DISK_BYTE,x
    eor AddressSector
    beq Tags
NotFound:
    lda #DISK_ERROR_NO_FIELD
    jmp Fail

    ; The 12 tag bytes, the last first, to TagBytes.
Tags:
    clc
NextTagGroup:
    ldx Iwm::DataLatch
    bpl NextTagGroup
    adc Checksum0
    cmp #$80
    rol a
    sta Checksum0
    lda GcrDecode - FIRST_DISK_BYTE,x
    sta Work0
WaitTag1:
    ldx Iwm::DataLatch
    bpl WaitTag1
    lda GcrDecode - FIRST_DISK_BYTE,x
    ldx Work0
    ora GcrHighBits1,x
    eor Checksum0
    sta TagBytes - 1,y
    dey
    adc Checksum2
    sta Checksum2
WaitTag2:
    ldx Iwm::DataLatch
    bpl WaitTag2
    lda GcrDecode - FIRST_DISK_BYTE,x
    ldx Work0
    ora GcrHighBits2,x
    eor Checksum2
    sta TagBytes - 1,y
    dey
    adc Checksum1
    sta Checksum1
WaitTag3:
    ldx Iwm::DataLatch
    bpl WaitTag3
    lda GcrDecode - FIRST_DISK_BYTE,x
    ldx Work0
    ora GcrHighBits3,x
    eor Checksum1
    sta TagBytes - 1,y
    dey
    bne NextTagGroup
    bra FirstPageGroup

    ; The first 256 data bytes, to BufferPointer's page. The groups go on across the two pages.
FirstPageByte2:
    ldx Iwm::DataLatch
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits2,y
    eor Checksum2
    sta (BufferPointer)
    inc BufferPointer
    adc Checksum1
    sta Checksum1
WaitFirstPageByte3:
    ldx Iwm::DataLatch
    bpl WaitFirstPageByte3
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits3,y
    eor Checksum1
    sta (BufferPointer)
    inc BufferPointer
FirstPageGroup:
    ldx Iwm::DataLatch
    bpl FirstPageGroup
    adc Checksum0
    cmp #$80
    rol a
    sta Checksum0
    ldy GcrDecode - FIRST_DISK_BYTE,x
WaitFirstPageByte1:
    ldx Iwm::DataLatch
    bpl WaitFirstPageByte1
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits1,y
    eor Checksum0
    sta (BufferPointer)
    adc Checksum2
    sta Checksum2
    inc BufferPointer
    bne FirstPageByte2

    ; The group that crosses into the second page.
    ldx Iwm::DataLatch
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits2,y
    eor Checksum2
    sta (SecondBufferPointer)
    adc Checksum1
    sta Checksum1
    inc SecondBufferPointer
    nop

    ; The second 256 data bytes, to SecondBufferPointer's page.
SecondPageByte3:
    ldx Iwm::DataLatch
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits3,y
    eor Checksum1
    sta (SecondBufferPointer)
    inc SecondBufferPointer
SecondPageGroup:
    ldx Iwm::DataLatch
    bpl SecondPageGroup
    adc Checksum0
    cmp #$80
    rol a
    sta Checksum0
    ldy GcrDecode - FIRST_DISK_BYTE,x
WaitSecondPageByte1:
    ldx Iwm::DataLatch
    bpl WaitSecondPageByte1
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits1,y
    eor Checksum0
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    adc Checksum2
    sta Checksum2
WaitSecondPageByte2:
    ldx Iwm::DataLatch
    bpl WaitSecondPageByte2
    lda GcrDecode - FIRST_DISK_BYTE,x
    ora GcrHighBits2,y
    eor Checksum2
    sta (SecondBufferPointer)
    adc Checksum1
    sta Checksum1
    inc SecondBufferPointer
    bne SecondPageByte3

    ; The checksum bytes: their high bits, then the three, each XORed into its checksum. Work0 and Work1, which
    ; follow ChecksumHighBits, give the next two bytes' high bits through ChecksumHighBits,x.
    ldx Iwm::DataLatch
    ldy GcrDecode - FIRST_DISK_BYTE,x
    lda GcrHighBits3,y
    sta Work0
    lda GcrHighBits2,y
    sta Work1
    lda GcrHighBits1,y
    ldx #$02
NextChecksum:
    ldy Iwm::DataLatch
    bpl NextChecksum
    ora GcrDecode - FIRST_DISK_BYTE,y
    eor Checksum0,x
    sta Checksum0,x
    lda ChecksumHighBits,x
    dex
    bpl NextChecksum

    ; The epilogue, DE AA.
    ldx #$02
NextEpilogueByte:
    lda Iwm::DataLatch
    bpl NextEpilogueByte
    cmp Epilogue,x
    bne BadEpilogue
    dex
    bne NextEpilogueByte
    bra CheckSums
BadEpilogue:
    lda #DISK_ERROR_BAD_EPILOGUE
    tsb DiskErrors

    ; Good checksums leave carry set only for a bad epilogue.
CheckSums:
    lda Checksum2
    ora Checksum1
    ora Checksum0
    bne BadChecksum
    lda DiskErrors
    cmp #$01
    rts
BadChecksum:
    lda #DISK_ERROR_BAD_CHECKSUM
Fail:
    tsb DiskErrors
    sec
    rts
.endproc
.assert Work0 = ChecksumHighBits + 1 && Work1 = ChecksumHighBits + 2, "Work0 and Work1 follow ChecksumHighBits."

;; Nibblizes a sector for <WriteDataField>, keeping the tag bytes that <ReadWriteTagged> has put in the three lanes' top
;; groups.
;; Falls into the middle of <NibblizeSector>.
.proc NibblizeSectorWithTags
    ldx #LAST_GROUP
    bra NibblizeSector::FromGroup
.endproc

;; Nibblizes the sector at BufferPointer's two pages for <WriteDataField>, with zero tag bytes: splits it into the
;; three lanes (<NibbleLane1>, <NibbleLane2> and <NibbleLane3>), each byte XORed with a running checksum, and works out
;; the three checksums. For an MFM disk, which needs no nibbles, it only points <SecondBufferPointer> at the second
;; page.
;;
;; On a IIgs host, which writes the block into the card while the card nibblizes it, it waits for <WriteProgress> to
;; say the host has started, and each time it finishes a page of the block before the host has finished
;; (<PROGRESS_DONE>) it starts again from the beginning: at once if the host is on the second half, else once the
;; host has finished. It fills the three nibble lanes, and leaves the last group in <Nibble0>,
;; <Nibble1> and <Nibble2>, with its high bits in <NibbleHighBits>, for <WriteGcrDataField> to start with.
;; In: BufferPointer = the block
;; Out: Checksum0, Checksum1 and Checksum2 = the checksums, ChecksumHighBits = their high bits
;; Entry:
;;   FromGroup = with X = the last group to fill (tags kept above it), from <NibblizeSectorWithTags>
.proc NibblizeSector
    ldx #TAG_GROUPS
ClearTag:
    stz NibbleLane1 + LAST_DATA_GROUP,x
    stz NibbleLane2 + LAST_DATA_GROUP,x
    stz NibbleLane3 + LAST_DATA_GROUP - 1,x
    dex
    bne ClearTag
    ldx #LAST_DATA_GROUP
FromGroup:
    bit SwimState
    bpl Gcr

    ; MFM: the second half is the next page.
    lda BufferPointer + 1
    inc a
    sta SecondBufferPointer + 1
    lda BufferPointer
    sta SecondBufferPointer
    rts

    ; GCR: SecondBufferPointer's page keeps the first page, for a start again.
Gcr:
    stx NibbleStart
    lda BufferPointer + 1
    sta SecondBufferPointer + 1

    ; On a IIgs, waits for the host to start the block.
WaitForHost:
    lda WriteProgress
    bpl Start
    cmp #PROGRESS_DONE
    beq HostDone
    cmp #PROGRESS_SECOND_HALF
    beq Start
    cmp #PROGRESS_STARTED
    bne WaitForHost
    ldy #FIRST_HALF_DELAY
Delay:
    dey
    bne Delay
    bra Start
HostDone:
    stz WriteProgress

    ; Three bytes a group, from the top group down, into lanes 3, 1 and 2.
Start:
    stz Checksum2
    stz Checksum1
    stz Checksum0
    clc
    ldy #$00
    bra Lane1
Lane3:
    lda (BufferPointer),y
    eor Checksum1
    sta NibbleLane3,x
    eor Checksum1
    adc Checksum0
    cmp #$80
    rol a
    sta Checksum0
    iny
    bne Lane1
    inc BufferPointer + 1
    lda WriteProgress
    bpl Lane1
    eor #PROGRESS_DONE
    bne PageBeforeHost
Lane1:
    lda (BufferPointer),y
    eor Checksum0
    sta NibbleLane1,x
    eor Checksum0
    adc Checksum2
    sta Checksum2
    iny
    bne Lane2
    inc BufferPointer + 1
    lda WriteProgress
    bpl Lane2
    eor #PROGRESS_DONE
    bne PageBeforeHost
Lane2:
    lda (BufferPointer),y
    eor Checksum2
    sta NibbleLane2,x
    eor Checksum2
    adc Checksum1
    sta Checksum1
    iny
    bne NextGroup
    inc BufferPointer + 1
    lda WriteProgress
    bpl NextGroup
    eor #PROGRESS_DONE
    beq NextGroup

    ; A page done before the host: start again, at once if it is on the second half, else once it is done.
PageBeforeHost:
    cmp #PROGRESS_SECOND_HALF ^ PROGRESS_DONE
    beq Restart
    lda #PROGRESS_DONE
WaitDone:
    cmp WriteProgress
    bne WaitDone
    stz WriteProgress
Restart:
    lda SecondBufferPointer + 1
    sta BufferPointer + 1
    ldx NibbleStart
    bra Start
NextGroup:
    dex
    bne Lane3

    ; The checksums' high bits, packed two each.
    lda Checksum0
    lsr a
    lsr a
    eor Checksum1
    and #$30
    eor Checksum1
    lsr a
    lsr a
    eor Checksum2
    and #$3C
    eor Checksum2
    lsr a
    lsr a
    sta ChecksumHighBits

    ; The top group, which WriteGcrDataField writes first, and its high bits.
    lda NibbleLane1 + LAST_GROUP
    sta Nibble0
    asl a
    rol NibbleHighBits
    asl a
    rol NibbleHighBits
    lda NibbleLane2 + LAST_GROUP
    sta Nibble1
    asl a
    rol NibbleHighBits
    asl a
    rol NibbleHighBits
    lda NibbleLane3 + LAST_GROUP - 1
    sta Nibble2
    asl a
    rol NibbleHighBits
    asl a
    rol NibbleHighBits
    rts
.endproc

;; Writes a data field after an address field, by GCR or by MFM as the disk is.
;; Out: carry = set if it failed (a GCR underrun; an MFM write always returns carry clear)
.proc WriteDataField
    bit SwimState
    bpl Gcr
    jmp WriteMfmDataField
Gcr:
    jmp WriteDataVector
.endproc

;; The routine <WriteDataVector> normally goes to: writes a GCR data field from what <NibblizeSector> left: a
;; self-sync group, D5 AA AD, the sector number, the nibbles of the three lanes with their high bits, the checksums
;; and DE AA, then waits for the IWM to finish and goes back to reading.
;; In: AddressSector = the sector; the lanes, checksums, <Nibble0>-Nibble2 and <NibbleHighBits> from <NibblizeSector>
;; Out: carry = set if the IWM underran, with DiskErrors = <DISK_ERROR_UNDERRUN>
.proc WriteGcrDataField
    bit Iwm::LoadLatch
    lda #$FF
    sta Iwm::WriteMode
    stz DiskErrors

    ; The sync group (3F CF F3 FC FF, from SyncBytes) and D5 AA AD, from the end of SyncBytes down through DataMark.
    ldx #$07
NextMarkByte:
    lda DataMark,x
WaitMark:
    bit Iwm::DataLatch
    bpl WaitMark
    sta Iwm::LoadLatch
    dex
    bpl NextMarkByte

    ; The sector number.
    ldy AddressSector
    lda GcrEncodeTable,y
WaitSector:
    bit Iwm::DataLatch
    bpl WaitSector
    sta Iwm::LoadLatch

    ; Each group: its high bits, then lanes 1, 2 and 3, the first group without lane 3.
    ldx #LAST_GROUP - 1
    bra HighBits
Lane3:
    ldy Nibble2
    lda NibbleLane3,x
    sta Nibble2
    asl a
    rol NibbleHighBits
    asl a
    lda GcrEncodeTable,y
    sta Iwm::LoadLatch
    rol NibbleHighBits
HighBits:
    ldy NibbleHighBits
    lda GcrEncodeTable,y
WaitHighBits:
    bit Iwm::DataLatch
    bpl WaitHighBits
    sta Iwm::LoadLatch
    ldy Nibble0
    lda NibbleLane1,x
    sta Nibble0
    asl a
    rol NibbleHighBits
    asl a
    rol NibbleHighBits
    lda GcrEncodeTable,y
    sta Iwm::LoadLatch
    ldy Nibble1
    lda NibbleLane2,x
    sta Nibble1
    asl a
    rol NibbleHighBits
    asl a
    rol NibbleHighBits
    lda GcrEncodeTable,y
    sta Iwm::LoadLatch
    dex
    cpx #$FF
    bne Lane3

    ; ChecksumHighBits, then Checksum2, Checksum1 and Checksum0.
    ldx #$03
NextChecksum:
    ldy Checksum0,x
    lda GcrEncodeTable,y
WaitChecksum:
    bit Iwm::DataLatch
    bpl WaitChecksum
    sta Iwm::LoadLatch
    dex
    bpl NextChecksum

    ; DE AA and a pad byte.
    ldx #$02
NextEpilogueByte:
    lda Epilogue,x
WaitEpilogue:
    bit Iwm::DataLatch
    bpl WaitEpilogue
    sta Iwm::LoadLatch
    dex
    bpl NextEpilogueByte

    ; The handshake's bit 6 is clear after an underrun; it clears too once the last byte is out.
    lda #$40
    and Iwm::DataLatch
    eor #$40
    tsb DiskErrors
WaitWritten:
    bit Iwm::DataLatch
    bvs WaitWritten
    bit Iwm::ReadMode
    lda DiskErrors
    cmp #$01
    rts
.endproc
.assert SyncBytes = DataMark + 4, "WriteGcrDataField writes SyncBytes and DataMark as one run."
.assert DISK_ERROR_UNDERRUN = $40, "The underrun is the handshake's bit 6."
