;; THE CARD'S FIRMWARE: MFM ADDRESS AND DATA FIELDS

;; Reads an MFM ID field through the ISM (A1 A1 A1 FE, track, side, sector, size, CRC).
READADDRESSMFM:
    jsr SELECTREADHEAD
    stz DiskErrors
    jsr ENTERISM
    ldy #$FF
    sty WorkPointer
    bra READADDRESSMFM_4
READADDRESSMFM_1:
    ldx #$02
    ldy #$FF
READADDRESSMFM_2:
    bit Ism::ReadHandshake
    bmi READADDRESSMFM_3
    dey
    bmi READADDRESSMFM_2
    bra READADDRESSMFM_4
READADDRESSMFM_3:
    lda Ism::ReadMark
    cmp MFMINDEXMARK,X
    bne READADDRESSMFM_4
    dex
    bpl READADDRESSMFM_2
READADDRESSMFM_4:
    bit Ism::ReadError
    lda #$18
    sta Ism::ClearMode
    lda #$01
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError
    lda #$08
    sta Ism::SetMode
READADDRESSMFM_5:
    bit Ism::ReadHandshake
    bmi READADDRESSMFM_6
    dey
    bne READADDRESSMFM_5
    dec WorkPointer
    bne READADDRESSMFM_5
    lda #$01
    jmp READADDRESSMFM_FAIL
READADDRESSMFM_6:
    lda Ism::ReadMark
    cmp #$A1
    beq READADDRESSMFM_7
    cmp #$C2
    beq READADDRESSMFM_1
    bra READADDRESSMFM_4
READADDRESSMFM_7:
    ldy #$FF
    ldx #$02
READADDRESSMFM_8:
    bit Ism::ReadHandshake
    bmi READADDRESSMFM_9
    dey
    bmi READADDRESSMFM_8
    bra READADDRESSMFM_4
READADDRESSMFM_9:
    lda Ism::ReadMark
    cmp MFMIDMARK,X
    bne READADDRESSMFM_4
    dex
    bpl READADDRESSMFM_8
READADDRESSMFM_10:
    bit Ism::ReadHandshake
    bpl READADDRESSMFM_10
    lda Ism::ReadData
    sta AddressTrack
READADDRESSMFM_11:
    bit Ism::ReadHandshake
    bpl READADDRESSMFM_11
    lda #$00
    ldy Ism::ReadData
    beq READADDRESSMFM_12
    lda #$20
READADDRESSMFM_12:
    sta AddressSide
READADDRESSMFM_13:
    bit Ism::ReadHandshake
    bpl READADDRESSMFM_13
    lda Ism::ReadData
    dec A
    sta AddressSector
READADDRESSMFM_14:
    bit Ism::ReadHandshake
    bpl READADDRESSMFM_14
    lda #$20
    ora Ism::ReadData
    sta AddressFormat
READADDRESSMFM_15:
    bit Ism::ReadHandshake
    bpl READADDRESSMFM_15
    lda Ism::ReadData
    sta HeaderChecksum
READADDRESSMFM_16:
    lda Ism::ReadHandshake
    bpl READADDRESSMFM_16
    ldy Ism::ReadData
    sty Checksum0
    ldy Ism::ReadError
    sty Checksum1
    sta Checksum2
    and #$22
    bne READADDRESSMFM_18
    lda #$18
    sta Ism::ClearMode
    ldx Drive
    lda #$80
    sta DiskSides,X
    lda AddressSide
    beq READADDRESSMFM_17
    lda #$20
READADDRESSMFM_17:
    eor Side
    bne READADDRESSMFM_20
    lda AddressTrack
    cmp Track
    beq READADDRESSMFM_19
    sta CurrentTrack,X
    lda #$04
    bra READADDRESSMFM_FAIL
READADDRESSMFM_18:
    lda #$20
READADDRESSMFM_FAIL:
    tsb DiskErrors
    lda #$18
    sta Ism::ClearMode
    lda Ism::ReadError
    jsr LEAVEISM
    sec
    rts
READADDRESSMFM_19:
    clc
    rts
READADDRESSMFM_20:
    lda #$28
    bra READADDRESSMFM_FAIL

;; The MFM index mark (C2 C2 FC), read last byte first.
MFMINDEXMARK:
    .byte $FC, $C2, $C2

;; The ID mark (A1 A1 FE), last byte first.
MFMIDMARK:
    .byte $FE, $A1

;; The data mark (A1 A1 FB) and its first A1, last byte first.
MFMDATAMARK:
    .byte $A1, $FB, $A1, $A1, $A1

;; Reads an MFM data field through the ISM (A1 A1 A1 FB, 512 bytes, CRC).
READDATAMFM:
    bit Ism::ReadError
    lda #$18
    sta Ism::ClearMode
    lda #$01
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError
    lda #$08
    sta Ism::SetMode
    ldy #$80
READDATAMFM_1:
    dey
    bne READDATAMFM_3
READDATAMFM_2:
    lda #$18
    sta Ism::ClearMode
    jsr LEAVEISM
    sec
    rts
READDATAMFM_3:
    bit Ism::ReadHandshake
    bpl READDATAMFM_1
    lda Ism::ReadMark
    cmp #$A1
    bne READDATAMFM_1
    ldx #$03
    ldy #$14
READDATAMFM_4:
    bit Ism::ReadHandshake
    bmi READDATAMFM_5
    dey
    bpl READDATAMFM_4
    bra READDATAMFM_2
READDATAMFM_5:
    lda Ism::ReadMark
    cmp MFMDATAMARK,X
    bne READDATAMFM_2
    dex
    bne READDATAMFM_4
READDATAMFM_6:
    bit Ism::ReadHandshake
    bvc READDATAMFM_6
    lda Ism::ReadData
    ldx Ism::ReadData
    sta (BufferPointer)
    inc BufferPointer
    txa
    sta (BufferPointer)
    inc BufferPointer
    bne READDATAMFM_6
READDATAMFM_7:
    bit Ism::ReadHandshake
    bvc READDATAMFM_7
    lda Ism::ReadData
    ldx Ism::ReadData
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    txa
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    bne READDATAMFM_7
READDATAMFM_8:
    bit Ism::ReadHandshake
    bpl READDATAMFM_8
    lda Ism::ReadData
    sta HeaderChecksum
READDATAMFM_9:
    lda Ism::ReadHandshake
    bpl READDATAMFM_9
    ldy Ism::ReadData
    sty Checksum0
    ldy Ism::ReadError
    sty Checksum1
    sta Checksum2
    and #$22
    bne READDATAMFM_10
    lda #$18
    sta Ism::ClearMode
    stz DiskErrors
    jsr LEAVEISM
    clc
    rts
READDATAMFM_10:
    lda #$18
    sta Ism::ClearMode
    jsr LEAVEISM
    lda #$10
    ora DiskErrors
    sta DiskErrors
    sec
    rts

;; Writes an MFM data field through the ISM.
WRITEDATAMFM:
    lda #$F0
    sta Ism::WritePhase
    bit Ism::ReadError
    lda #$18
    sta Ism::ClearMode
    lda #$10
    sta Ism::SetMode
    lda #$01
    sta Ism::SetMode
    sta Ism::ClearMode
    bit Ism::ReadError
    ldy #$24
WRITEDATAMFM_1:
    lda Ism::ReadHandshake
    lda Ism::ReadHandshake
    lda Ism::ReadHandshake
    dey
    bne WRITEDATAMFM_1
    stz Ism::WriteData
    stz Ism::WriteData
    lda #$08
    sta Ism::SetMode
    ldx #$0A
WRITEDATAMFM_2:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_2
    stz Ism::WriteData
    dex
    bne WRITEDATAMFM_2
    ldx #$03
WRITEDATAMFM_3:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_3
    lda #$A1
    sta Ism::WriteMark
    dex
    bne WRITEDATAMFM_3
WRITEDATAMFM_4:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_4
    lda #$FB
    sta Ism::WriteData
    ldy #$00
WRITEDATAMFM_5:
    lda (BufferPointer),Y
WRITEDATAMFM_6:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_6
    sta Ism::WriteData
    iny
    bne WRITEDATAMFM_5
WRITEDATAMFM_7:
    lda (SecondBufferPointer),Y
WRITEDATAMFM_8:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_8
    sta Ism::WriteData
    iny
    bne WRITEDATAMFM_7
WRITEDATAMFM_9:
    bit Ism::ReadHandshake
    bpl WRITEDATAMFM_9
    stz Ism::WriteCrc
    ldx #$04
    lda #$4E
WRITEDATAMFM_10:
    ldy Ism::ReadHandshake
    bpl WRITEDATAMFM_10
    sta Ism::WriteData
    dex
    bne WRITEDATAMFM_10
WRITEDATAMFM_11:
    bit Ism::ReadHandshake
    bvc WRITEDATAMFM_11
    lda #$18
    sta Ism::ClearMode
    tya
    and #$20
    clc
    beq WRITEDATAMFM_12
    lda Ism::ReadError
    sta Checksum1
WRITEDATAMFM_12:
    php
    ldx #$78
WRITEDATAMFM_13:
    bne WRITEDATAMFM_14
WRITEDATAMFM_14:
    nop
    dex
    bne WRITEDATAMFM_13
    jsr LEAVEISM
    plp
    rts
