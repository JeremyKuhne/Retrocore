;; THE CARD'S FIRMWARE: GCR ADDRESS AND DATA FIELDS

;; Finds the next sector's address field, by GCR or MFM.
;; Out:   carry = set if none was read: DiskErrors bit 0 = no field, 2 = the wrong track, 5 = a bad field,
;;        or $28 = the wrong side; else AddressTrack, AddressSector, AddressSide, AddressFormat set
READADDRESS:
    bit SwimState
    bpl READADDRESS_1
    jmp READADDRESSMFM
READADDRESS_1:
    jmp ReadAddressVector

;; The ReadAddressVector routine: reads a GCR address field (D5 AA 96, five fields, DE AA).
ReadGcrAddressField:
    jsr SELECTREADHEAD
    stz DiskErrors
    lda Iwm::DataLatch
    lda Iwm::ReadMode
    lda #$08
    sta WorkPointer
    ldy #$00
READADDRESSGCR_1:
    ldx #$02
READADDRESSGCR_2:
    dey
    bne READADDRESSGCR_3
    dec WorkPointer
    beq READADDRESSGCR_10
READADDRESSGCR_3:
    lda Iwm::DataLatch
    bpl READADDRESSGCR_3
    cmp AddressMark,X
    bne READADDRESSGCR_1
    dex
    bpl READADDRESSGCR_2
    ldx #$04
    stz HeaderChecksum
READADDRESSGCR_4:
    ldy Iwm::DataLatch
    bpl READADDRESSGCR_4
    lda GCRDECODE-$96,Y
    sta AddressChecksum,X
    eor HeaderChecksum
    sta HeaderChecksum
    dex
    bpl READADDRESSGCR_4
    tay
    bne READADDRESSGCR_11
READADDRESSGCR_5:
    ldx Iwm::DataLatch
    bpl READADDRESSGCR_5
    cpx Epilogue+2
    bne READADDRESSGCR_11
READADDRESSGCR_6:
    ldx Iwm::DataLatch
    bpl READADDRESSGCR_6
    cpx Epilogue+1
    bne READADDRESSGCR_11
    ldx Drive
    lda AddressFormat
    sta LastFormatByte,X
    and #$20
    asl A
    asl A
    sta DiskSides,X
    lda AddressSide
    eor Side
    lsr A
    bne READADDRESSGCR_9
    lda AddressTrack
    bcc READADDRESSGCR_7
    ora #$40
READADDRESSGCR_7:
    cmp Track
    beq READADDRESSGCR_8
    ldx Drive
    sta CurrentTrack,X
    lda #$04
    bra READADDRESSGCR_12
READADDRESSGCR_8:
    clc
    rts
READADDRESSGCR_9:
    lda #$28
    bra READADDRESSGCR_12
READADDRESSGCR_10:
    lda #$01
    bra READADDRESSGCR_12
READADDRESSGCR_11:
    lda #$20
READADDRESSGCR_12:
    tsb DiskErrors
    sec
    rts

;; Disk bytes $8F-$95, never valid.
GCRINVALID:
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; The 6-and-2 GCR decode table for disk bytes $96-$FF (an invalid byte holds a value of $80 or more), indexed from $E500.
GCRDECODE:
    .byte $00, $01, $98, $99, $02, $03, $9C, $04, $05, $06, $A0, $A1, $A2, $A3, $A4, $A5
    .byte $07, $08, $A8, $A9, $AA, $09, $0A, $0B, $0C, $0D, $B0, $B1, $0E, $0F, $10, $11
    .byte $12, $13, $B8, $14, $15, $16, $17, $18, $19, $1A, $C0, $C1, $C2, $C3, $C4, $C5
    .byte $C6, $C7, $C8, $C9, $CA, $1B, $CC, $1C, $1D, $1E, $D0, $D1, $D2, $1F, $D4, $D5
    .byte $20, $21, $D8, $22, $23, $24, $25, $26, $27, $28, $E0, $E1, $E2, $E3, $E4, $29
    .byte $2A, $2B, $E8, $2C, $2D, $2E, $2F, $30, $31, $32, $F0, $F1, $33, $34, $35, $36
    .byte $37, $38, $F8, $39, $3A, $3B, $3C, $3D, $3E, $3F

;; Selects the drive's read-data register for Side's head and puts the IWM in read mode.
SELECTREADHEAD:
    lda #$01
    jsr DRIVESENSE
    jsr SELECTHEAD
    bit Iwm::DataLatch
    bit Iwm::ReadMode
    rts

;; Reads the data field after an address field, by GCR or MFM, into BufferPointer and SecondBufferPointer.
;; Out:   carry = set if it failed (DiskErrors bit 0 = no field, 3 = bad epilogue, 4 = bad checksum)
READDATA:
    bit SwimState
    bpl READDATA_1
    jmp READDATAMFM
READDATA_1:
    jmp ReadDataVector

;; The ReadDataVector routine: reads a GCR data field: the sector number, 12 tag bytes to TAGBYTES
;; and 512 data bytes, with their three checksums.
ReadGcrDataField:
    stz Checksum2
    stz Checksum1
    stz Checksum0
    stz DiskErrors
    ldy #$19
READDATAGCR_1:
    ldx #$02
READDATAGCR_2:
    dey
    beq READDATAGCR_5
READDATAGCR_3:
    lda Iwm::DataLatch
    bpl READDATAGCR_3
    cmp DataMark,X
    bne READDATAGCR_1
    dex
    bpl READDATAGCR_2
    ldy #$0C
READDATAGCR_4:
    ldx Iwm::DataLatch
    bpl READDATAGCR_4
    lda GCRDECODE-$96,X
    eor AddressSector
    beq READDATAGCR_6
READDATAGCR_5:
    lda #$01
    jmp READDATAGCR_FAIL
READDATAGCR_6:
    clc
READDATAGCR_7:
    ldx Iwm::DataLatch
    bpl READDATAGCR_7
    adc Checksum0
    cmp #$80
    rol A
    sta Checksum0
    lda GCRDECODE-$96,X
    sta Work0
READDATAGCR_8:
    ldx Iwm::DataLatch
    bpl READDATAGCR_8
    lda GCRDECODE-$96,X
    ldx Work0
    ora GCRHIGH1,X
    eor Checksum0
    sta TAGBYTES-1,Y
    dey
    adc Checksum2
    sta Checksum2
READDATAGCR_9:
    ldx Iwm::DataLatch
    bpl READDATAGCR_9
    lda GCRDECODE-$96,X
    ldx Work0
    ora GCRHIGH2,X
    eor Checksum2
    sta TAGBYTES-1,Y
    dey
    adc Checksum1
    sta Checksum1
READDATAGCR_10:
    ldx Iwm::DataLatch
    bpl READDATAGCR_10
    lda GCRDECODE-$96,X
    ldx Work0
    ora GCRHIGH3,X
    eor Checksum1
    sta TAGBYTES-1,Y
    dey
    bne READDATAGCR_7
    bra READDATAGCR_13
READDATAGCR_11:
    ldx Iwm::DataLatch
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor Checksum2
    sta (BufferPointer)
    inc BufferPointer
    adc Checksum1
    sta Checksum1
READDATAGCR_12:
    ldx Iwm::DataLatch
    bpl READDATAGCR_12
    lda GCRDECODE-$96,X
    ora GCRHIGH3,Y
    eor Checksum1
    sta (BufferPointer)
    inc BufferPointer
READDATAGCR_13:
    ldx Iwm::DataLatch
    bpl READDATAGCR_13
    adc Checksum0
    cmp #$80
    rol A
    sta Checksum0
    ldy GCRDECODE-$96,X
READDATAGCR_14:
    ldx Iwm::DataLatch
    bpl READDATAGCR_14
    lda GCRDECODE-$96,X
    ora GCRHIGH1,Y
    eor Checksum0
    sta (BufferPointer)
    adc Checksum2
    sta Checksum2
    inc BufferPointer
    bne READDATAGCR_11
    ldx Iwm::DataLatch
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor Checksum2
    sta (SecondBufferPointer)
    adc Checksum1
    sta Checksum1
    inc SecondBufferPointer
    nop
READDATAGCR_15:
    ldx Iwm::DataLatch
    lda GCRDECODE-$96,X
    ora GCRHIGH3,Y
    eor Checksum1
    sta (SecondBufferPointer)
    inc SecondBufferPointer
READDATAGCR_16:
    ldx Iwm::DataLatch
    bpl READDATAGCR_16
    adc Checksum0
    cmp #$80
    rol A
    sta Checksum0
    ldy GCRDECODE-$96,X
READDATAGCR_17:
    ldx Iwm::DataLatch
    bpl READDATAGCR_17
    lda GCRDECODE-$96,X
    ora GCRHIGH1,Y
    eor Checksum0
    sta (SecondBufferPointer)
    inc SecondBufferPointer
    adc Checksum2
    sta Checksum2
READDATAGCR_18:
    ldx Iwm::DataLatch
    bpl READDATAGCR_18
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor Checksum2
    sta (SecondBufferPointer)
    adc Checksum1
    sta Checksum1
    inc SecondBufferPointer
    bne READDATAGCR_15
    ldx Iwm::DataLatch
    ldy GCRDECODE-$96,X
    lda GCRHIGH3,Y
    sta Work0
    lda GCRHIGH2,Y
    sta Work1
    lda GCRHIGH1,Y
    ldx #$02
READDATAGCR_19:
    ldy Iwm::DataLatch
    bpl READDATAGCR_19
    ora GCRDECODE-$96,Y
    eor Checksum0,X
    sta Checksum0,X
    lda ChecksumHighBits,X
    dex
    bpl READDATAGCR_19
    ldx #$02
READDATAGCR_20:
    lda Iwm::DataLatch
    bpl READDATAGCR_20
    cmp Epilogue,X
    bne READDATAGCR_21
    dex
    bne READDATAGCR_20
    bra READDATAGCR_22
READDATAGCR_21:
    lda #$08
    tsb DiskErrors
READDATAGCR_22:
    lda Checksum2
    ora Checksum1
    ora Checksum0
    bne READDATAGCR_23
    lda DiskErrors
    cmp #$01
    rts
READDATAGCR_23:
    lda #$10
READDATAGCR_FAIL:
    tsb DiskErrors
    sec
    rts

;; Nibblizes a sector for WRITEDATA, keeping the tag bytes in the buffers (READWRITE's writes).
PREPAREDATATAGS:
    ldx #$AF
    bra PREPAREDATA_2

;; Nibblizes a sector for WRITEDATA with zero tags. On a IIgs host (WriteProgress negative) it
;; follows the host's copy: $C0 first half, $C1 second, $D0 done.
PREPAREDATA:
    ldx #$04
PREPAREDATA_1:
    stz NIBBLES1+$AB,X
    stz NIBBLES2+$AB,X
    stz NIBBLES3+$AA,X
    dex
    bne PREPAREDATA_1
    ldx #$AB
PREPAREDATA_2:
    bit SwimState
    bpl PREPAREDATA_3
    lda BufferPointer+1
    inc A
    sta SecondBufferPointer+1
    lda BufferPointer
    sta SecondBufferPointer
    rts
PREPAREDATA_3:
    stx NibbleStart
    lda BufferPointer+1
    sta SecondBufferPointer+1
PREPAREDATA_4:
    lda WriteProgress
    bpl PREPAREDATA_7
    cmp #$D0
    beq PREPAREDATA_6
    cmp #$C1
    beq PREPAREDATA_7
    cmp #$C0
    bne PREPAREDATA_4
    ldy #$C8
PREPAREDATA_5:
    dey
    bne PREPAREDATA_5
    bra PREPAREDATA_7
PREPAREDATA_6:
    stz WriteProgress
PREPAREDATA_7:
    stz Checksum2
    stz Checksum1
    stz Checksum0
    clc
    ldy #$00
    bra PREPAREDATA_9
PREPAREDATA_8:
    lda (BufferPointer),Y
    eor Checksum1
    sta NIBBLES3,X
    eor Checksum1
    adc Checksum0
    cmp #$80
    rol A
    sta Checksum0
    iny
    bne PREPAREDATA_9
    inc BufferPointer+1
    lda WriteProgress
    bpl PREPAREDATA_9
    eor #$D0
    bne PREPAREDATA_11
PREPAREDATA_9:
    lda (BufferPointer),Y
    eor Checksum0
    sta NIBBLES1,X
    eor Checksum0
    adc Checksum2
    sta Checksum2
    iny
    bne PREPAREDATA_10
    inc BufferPointer+1
    lda WriteProgress
    bpl PREPAREDATA_10
    eor #$D0
    bne PREPAREDATA_11
PREPAREDATA_10:
    lda (BufferPointer),Y
    eor Checksum2
    sta NIBBLES2,X
    eor Checksum2
    adc Checksum1
    sta Checksum1
    iny
    bne PREPAREDATA_14
    inc BufferPointer+1
    lda WriteProgress
    bpl PREPAREDATA_14
    eor #$D0
    beq PREPAREDATA_14
PREPAREDATA_11:
    cmp #$11
    beq PREPAREDATA_13
    lda #$D0
PREPAREDATA_12:
    cmp WriteProgress
    bne PREPAREDATA_12
    stz WriteProgress
PREPAREDATA_13:
    lda SecondBufferPointer+1
    sta BufferPointer+1
    ldx NibbleStart
    bra PREPAREDATA_7
PREPAREDATA_14:
    dex
    bne PREPAREDATA_8
    lda Checksum0
    lsr A
    lsr A
    eor Checksum1
    and #$30
    eor Checksum1
    lsr A
    lsr A
    eor Checksum2
    and #$3C
    eor Checksum2
    lsr A
    lsr A
    sta ChecksumHighBits
    lda NIBBLES1+$AF
    sta Nibble0
    asl A
    rol NibbleHighBits
    asl A
    rol NibbleHighBits
    lda NIBBLES2+$AF
    sta Nibble1
    asl A
    rol NibbleHighBits
    asl A
    rol NibbleHighBits
    lda NIBBLES3+$AE
    sta Nibble2
    asl A
    rol NibbleHighBits
    asl A
    rol NibbleHighBits
    rts

;; Writes a data field after an address field, by GCR or MFM.
;; Out:   carry = set if it failed
WRITEDATA:
    bit SwimState
    bpl WRITEDATA_1
    jmp WRITEDATAMFM
WRITEDATA_1:
    jmp WriteDataVector

;; The WriteDataVector routine: writes the sync bytes, D5 AA AD, the nibblized sector and checksums,
;; and DE AA.
;; Out:   carry = set if the IWM underran (DiskErrors bit 6)
WriteGcrDataField:
    bit Iwm::LoadLatch
    lda #$FF
    sta Iwm::WriteMode
    stz DiskErrors
    ldx #$07
WRITEDATAGCR_1:
    lda DataMark,X
WRITEDATAGCR_2:
    bit Iwm::DataLatch
    bpl WRITEDATAGCR_2
    sta Iwm::LoadLatch
    dex
    bpl WRITEDATAGCR_1
    ldy AddressSector
    lda GCRENCODE,Y
WRITEDATAGCR_3:
    bit Iwm::DataLatch
    bpl WRITEDATAGCR_3
    sta Iwm::LoadLatch
    ldx #$AE
    bra WRITEDATAGCR_5
WRITEDATAGCR_4:
    ldy Nibble2
    lda NIBBLES3,X
    sta Nibble2
    asl A
    rol NibbleHighBits
    asl A
    lda GCRENCODE,Y
    sta Iwm::LoadLatch
    rol NibbleHighBits
WRITEDATAGCR_5:
    ldy NibbleHighBits
    lda GCRENCODE,Y
WRITEDATAGCR_6:
    bit Iwm::DataLatch
    bpl WRITEDATAGCR_6
    sta Iwm::LoadLatch
    ldy Nibble0
    lda NIBBLES1,X
    sta Nibble0
    asl A
    rol NibbleHighBits
    asl A
    rol NibbleHighBits
    lda GCRENCODE,Y
    sta Iwm::LoadLatch
    ldy Nibble1
    lda NIBBLES2,X
    sta Nibble1
    asl A
    rol NibbleHighBits
    asl A
    rol NibbleHighBits
    lda GCRENCODE,Y
    sta Iwm::LoadLatch
    dex
    cpx #$FF
    bne WRITEDATAGCR_4
    ldx #$03
WRITEDATAGCR_7:
    ldy Checksum0,X
    lda GCRENCODE,Y
WRITEDATAGCR_8:
    bit Iwm::DataLatch
    bpl WRITEDATAGCR_8
    sta Iwm::LoadLatch
    dex
    bpl WRITEDATAGCR_7
    ldx #$02
WRITEDATAGCR_9:
    lda Epilogue,X
WRITEDATAGCR_10:
    bit Iwm::DataLatch
    bpl WRITEDATAGCR_10
    sta Iwm::LoadLatch
    dex
    bpl WRITEDATAGCR_9
    lda #$40
    and Iwm::DataLatch
    eor #$40
    tsb DiskErrors
WRITEDATAGCR_11:
    bit Iwm::DataLatch
    bvs WRITEDATAGCR_11
    bit Iwm::ReadMode
    lda DiskErrors
    cmp #$01
    rts
