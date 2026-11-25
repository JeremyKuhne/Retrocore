; retrocore: style=strict
;; The card's firmware: MFM address and data fields
;;
;; How the card reads and writes a sector on an MFM disk (720K or 1440K, on an FDHD drive), through the SWIM's ISM,
;; which finds the marks, decodes the bits and checks the CRC itself. An MFM sector is an ID field (A1 A1 A1 FE, the
;; track, side, sector from 1 and size code, a two-byte CRC) and a data field (A1 A1 A1 FB, 512 bytes, a CRC), and a
;; track starts with an index mark (C2 C2 C2 FC). Each A1 and C2 is a mark: a byte written with a clock bit missing,
;; which the ISM reads through <Ism::ReadMark>. <ReadAddressField>, <ReadDataField> and <WriteDataField> come here
;; when <SwimState> says the disk is MFM.

; The ISM's mode bits (<Ism::SetMode>, <Ism::ClearMode>, <Ism::ReadMode>) these routines use.

;; Clears the FIFO, when set and cleared again.
ISM_MODE_CLEAR_FIFO = $01

; The ISM's handshake bits (<Ism::ReadHandshake>) these routines test by mask.

;; The CRC so far is not zero: after a field's two CRC bytes, a bad field.
ISM_HANDSHAKE_CRC_ERROR = $02

;; The error register (<Ism::ReadError>) is not zero.
ISM_HANDSHAKE_ERROR = $20

; MFM marks and bytes.

;; The mark byte of the ID and data fields' A1 A1 A1.
MFM_MARK = $A1

;; The mark byte of the index mark's C2 C2 C2.
MFM_INDEX_MARK = $C2

;; The byte after a data field's marks.
MFM_DATA_ID = $FB

;; The gap byte written after a data field.
MFM_GAP = $4E

;; The zero bytes written before a data field's marks, as its sync.
MFM_SYNC_LENGTH = 12

;; The ID field's format byte, as <AddressFormat> holds it: the size code with bit 5, as a GCR format byte has for a
;; two-sided disk.
MFM_FORMAT_TWO_SIDES = $20

;; How many delay loops <WriteMfmDataField> waits after the field, before leaving the ISM.
WRITE_SETTLE_LOOPS = $78

;; Reads an MFM ID field through the ISM (A1 A1 A1 FE, the track, side, sector, size code, CRC), skipping index marks;
;; it gives up when the ISM reads no byte for about 65536 polls.
;;
;; A good field for another track or side fails as <ReadGcrAddressField>'s does. A field read for the wanted track
;; and side leaves the SWIM in ISM mode, for <ReadMfmDataField>; every failure leaves it in IWM mode.
;; Out: carry = set if no good field for <Track> and <Side> was read, with DiskErrors = <DISK_ERROR_NO_FIELD>,
;;      <DISK_ERROR_WRONG_TRACK> (the drive's <CurrentTrack> then holds the track found), <DISK_ERROR_BAD_FIELD> (a
;;      CRC error) or <DISK_ERROR_WRONG_SIDE>; <AddressTrack>, <AddressSide> (0 or $20), <AddressSector> (from 0) and
;;      AddressFormat = the field read; <HeaderChecksum> and Checksum0 = its CRC bytes, Checksum1 = the error register
;;      and Checksum2 = the handshake after them
.proc ReadMfmAddressField
    jsr SelectReadHead
    stz DiskErrors
    jsr Swim::EnterIsm
    ldy #$FF
    sty WorkPointer
    bra StartReading

    ; After a C2 mark: two more and FC, an index mark, to skip.
IndexMark:
    ldx #$02
    ldy #$FF
WaitIndexMark:
    bit Ism::ReadHandshake
    bmi CheckIndexMark
    dey
    bmi WaitIndexMark
    bra StartReading
CheckIndexMark:
    lda Ism::ReadMark
    cmp MfmIndexMark,x
    bne StartReading
    dex
    bpl WaitIndexMark

    ; Restarts the ISM reading: clears its errors and its FIFO, then sets the action bit.
StartReading:
    bit Ism::ReadError
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    lda #ISM_MODE_CLEAR_FIFO
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError
    lda #ISM_MODE_ACTION
    sta Ism::SetMode

    ; The first byte: an A1 starts an ID field, a C2 an index mark, and anything else starts again.
WaitFirstByte:
    bit Ism::ReadHandshake
    bmi FirstByte
    dey
    bne WaitFirstByte
    dec WorkPointer
    bne WaitFirstByte
    lda #DISK_ERROR_NO_FIELD
    jmp Fail
FirstByte:
    lda Ism::ReadMark
    cmp #MFM_MARK
    beq IdMark
    cmp #MFM_INDEX_MARK
    beq IndexMark
    bra StartReading

    ; Two more A1s and FE.
IdMark:
    ldy #$FF
    ldx #$02
WaitIdMark:
    bit Ism::ReadHandshake
    bmi CheckIdMark
    dey
    bmi WaitIdMark
    bra StartReading
CheckIdMark:
    lda Ism::ReadMark
    cmp MfmIdMark,x
    bne StartReading
    dex
    bpl WaitIdMark

    ; The track, the side (0 or $20), the sector from 0, and the size code as a format byte.
WaitTrack:
    bit Ism::ReadHandshake
    bpl WaitTrack
    lda Ism::ReadData
    sta AddressTrack
WaitSide:
    bit Ism::ReadHandshake
    bpl WaitSide
    lda #$00
    ldy Ism::ReadData
    beq StoreSide
    lda #$20
StoreSide:
    sta AddressSide
WaitSector:
    bit Ism::ReadHandshake
    bpl WaitSector
    lda Ism::ReadData
    dec a
    sta AddressSector
WaitSize:
    bit Ism::ReadHandshake
    bpl WaitSize
    lda #MFM_FORMAT_TWO_SIDES
    ora Ism::ReadData
    sta AddressFormat

    ; The CRC; the handshake after it says whether it was good.
WaitCrc1:
    bit Ism::ReadHandshake
    bpl WaitCrc1
    lda Ism::ReadData
    sta HeaderChecksum
WaitCrc2:
    lda Ism::ReadHandshake
    bpl WaitCrc2
    ldy Ism::ReadData
    sty Checksum0
    ldy Ism::ReadError
    sty Checksum1
    sta Checksum2
    and #ISM_HANDSHAKE_CRC_ERROR | ISM_HANDSHAKE_ERROR
    bne BadField

    ; Stops reading, and checks the side and the track.
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    ldx Drive
    lda #$80
    sta DiskSides,x
    lda AddressSide
    beq CheckSide
    lda #$20
CheckSide:
    eor Side
    bne WrongSide
    lda AddressTrack
    cmp Track
    beq Found
    sta CurrentTrack,x
    lda #DISK_ERROR_WRONG_TRACK
    bra Fail
BadField:
    lda #DISK_ERROR_BAD_FIELD
Fail:
    tsb DiskErrors
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    lda Ism::ReadError
    jsr Swim::LeaveIsm
    sec
    rts
Found:
    clc
    rts
WrongSide:
    lda #DISK_ERROR_WRONG_SIDE
    bra Fail
.endproc

; The marks after the first byte, each read from the end of its table down. The ID mark's table is two bytes:
; its third byte read, the last A1, is the data mark table's first byte.

;; The index mark after its first C2: C2 C2 FC, from the end.
MfmIndexMark:
    .byte $FC, MFM_INDEX_MARK, MFM_INDEX_MARK

;; The ID mark after its first A1: A1 A1 FE, from the end, the last byte read being <MfmDataMark>'s first.
MfmIdMark:
    .byte $FE, MFM_MARK

;; The data mark after its first A1: A1 A1 FB, from the fourth byte down to the second.
MfmDataMark:
    .byte MFM_MARK, MFM_DATA_ID, MFM_MARK, MFM_MARK, MFM_MARK
.assert MfmDataMark = MfmIdMark + 2, "The ID mark's last byte is the data mark table's first."

;; Reads an MFM data field through the ISM (A1 A1 A1 FB, 512 bytes, the CRC) into the pages at <BufferPointer> and
;; <SecondBufferPointer>, whose low bytes must be 0: it fills each page until its low byte comes round to 0 again.
;; It starts where <ReadMfmAddressField> left the ISM, and leaves the SWIM in IWM mode.
;; Out: carry = set if it failed: DiskErrors = <DISK_ERROR_BAD_CHECKSUM> with the error bit added for a CRC error,
;;      and unchanged when the data mark was not found; else DiskErrors = 0. <HeaderChecksum> and Checksum0 = the CRC
;;      bytes, Checksum1 = the error register and Checksum2 = the handshake after them
.proc ReadMfmDataField
    bit Ism::ReadError
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    lda #ISM_MODE_CLEAR_FIFO
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError
    lda #ISM_MODE_ACTION
    sta Ism::SetMode

    ; The first A1, within 128 polls.
    ldy #$80
NextPoll:
    dey
    bne WaitMark
NotFound:
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    jsr Swim::LeaveIsm
    sec
    rts
WaitMark:
    bit Ism::ReadHandshake
    bpl NextPoll
    lda Ism::ReadMark
    cmp #MFM_MARK
    bne NextPoll

    ; A1 A1 FB, each within 20 polls.
    ldx #$03
    ldy #$14
WaitRestOfMark:
    bit Ism::ReadHandshake
    bmi CheckMark
    dey
    bpl WaitRestOfMark
    bra NotFound
CheckMark:
    lda Ism::ReadMark
    cmp MfmDataMark,x
    bne NotFound
    dex
    bne WaitRestOfMark

    ; The data, two bytes at a time as the FIFO fills: 256 to each page.
FirstPage:
    bit Ism::ReadHandshake
    bvc FirstPage
    lda Ism::ReadData
    ldx Ism::ReadData
    sta (BufferPointer)
    inc BufferPointer
    txa
    sta (BufferPointer)
    inc BufferPointer
    bne FirstPage
SecondPage:
    bit Ism::ReadHandshake
    bvc SecondPage
    lda Ism::ReadData
    ldx Ism::ReadData
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    txa
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    bne SecondPage

    ; The CRC; the handshake after it says whether it was good.
WaitCrc1:
    bit Ism::ReadHandshake
    bpl WaitCrc1
    lda Ism::ReadData
    sta HeaderChecksum
WaitCrc2:
    lda Ism::ReadHandshake
    bpl WaitCrc2
    ldy Ism::ReadData
    sty Checksum0
    ldy Ism::ReadError
    sty Checksum1
    sta Checksum2
    and #ISM_HANDSHAKE_CRC_ERROR | ISM_HANDSHAKE_ERROR
    bne BadCrc
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    stz DiskErrors
    jsr Swim::LeaveIsm
    clc
    rts
BadCrc:
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    jsr Swim::LeaveIsm
    lda #DISK_ERROR_BAD_CHECKSUM
    ora DiskErrors
    sta DiskErrors
    sec
    rts
.endproc

;; Writes an MFM data field through the ISM from the pages at <BufferPointer> and <SecondBufferPointer>: 12 zero bytes,
;; A1 A1 A1 FB, the 512 bytes, the CRC the ISM works out, and four gap bytes; then waits for the FIFO to empty, stops,
;; waits about 0.6 ms more, and leaves the SWIM in IWM mode.
;;
;; It never reports a failure: when the handshake shows an error, it only keeps the error register in Checksum1,
;; and returns carry clear all the same.
;; Out: carry = clear
.proc WriteMfmDataField
    ; The four phase lines driven low (bits 4-7 make them outputs), then the ISM set to write, its FIFO cleared.
    lda #$F0
    sta Ism::WritePhase
    bit Ism::ReadError
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode
    lda #ISM_MODE_WRITE
    sta Ism::SetMode
    lda #ISM_MODE_CLEAR_FIFO
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError

    ; A pause of 36 rounds of three handshake reads.
    ldy #$24
Pause:
    lda Ism::ReadHandshake
    lda Ism::ReadHandshake
    lda Ism::ReadHandshake
    dey
    bne Pause

    ; The sync: two zeros in the FIFO, then the action bit starts the write, and ten more.
    stz Ism::WriteData
    stz Ism::WriteData
    lda #ISM_MODE_ACTION
    sta Ism::SetMode
    ldx #MFM_SYNC_LENGTH - 2
NextSyncByte:
    bit Ism::ReadHandshake
    bpl NextSyncByte
    stz Ism::WriteData
    dex
    bne NextSyncByte

    ; A1 A1 A1 FB.
    ldx #$03
NextMark:
    bit Ism::ReadHandshake
    bpl NextMark
    lda #MFM_MARK
    sta Ism::WriteMark
    dex
    bne NextMark
WaitDataId:
    bit Ism::ReadHandshake
    bpl WaitDataId
    lda #MFM_DATA_ID
    sta Ism::WriteData

    ; The 512 bytes.
    ldy #$00
FirstPage:
    lda (BufferPointer),y
WaitFirstPage:
    bit Ism::ReadHandshake
    bpl WaitFirstPage
    sta Ism::WriteData
    iny
    bne FirstPage
SecondPage:
    lda (SecondBufferPointer),y
WaitSecondPage:
    bit Ism::ReadHandshake
    bpl WaitSecondPage
    sta Ism::WriteData
    iny
    bne SecondPage

    ; The CRC, and the gap.
WaitCrc:
    bit Ism::ReadHandshake
    bpl WaitCrc
    stz Ism::WriteCrc
    ldx #$04
    lda #MFM_GAP
NextGapByte:
    ldy Ism::ReadHandshake
    bpl NextGapByte
    sta Ism::WriteData
    dex
    bne NextGapByte

    ; Waits for the FIFO to have room for two bytes, that is to be empty, then stops.
WaitEmpty:
    bit Ism::ReadHandshake
    bvc WaitEmpty
    lda #ISM_MODE_ACTION | ISM_MODE_WRITE
    sta Ism::ClearMode

    ; The error register, if the last handshake shows an error; carry stays clear.
    tya
    and #ISM_HANDSHAKE_ERROR
    clc
    beq Settle
    lda Ism::ReadError
    sta Checksum1
Settle:
    php
    ldx #WRITE_SETTLE_LOOPS
SettleLoop:
    bne Next
Next:
    nop
    dex
    bne SettleLoop
    jsr Swim::LeaveIsm
    plp
    rts
.endproc
