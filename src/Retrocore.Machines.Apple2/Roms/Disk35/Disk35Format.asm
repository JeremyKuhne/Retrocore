;; THE CARD'S FIRMWARE: FORMATTING

;; SmartPort FORMAT ($03), through the FormatVector vector.
DOFORMAT:
    jmp FormatVector

;; The FormatVector routine: formats Drive's disk, in the kind SETFORMAT chose or the drive's default
;; (800K GCR; 1440K MFM for a high-density disk in an FDHD drive), verifying each track, then reads it
;; back for its format.
;; Out:   ErrorCode = 0, $27, $2B, $2F or $21
FormatDisk:
    lda #$01
    ldx Drive
    bmi FORMATDISK_1
    jsr FORGETCACHE
    lda #$03
    jsr DRIVECOMMAND
    jsr MFMOFF
    ldx Drive
    jsr CHECKDISK
    bcc FORMATDISK_2
FORMATDISK_1:
    jmp SETERROR
FORMATDISK_2:
    bne FORMATDISK_1
    lda #$80
    sta DiskSides,X
    lda #$02
    bit DeviceKinds,X
    bne CALLFORMATHOOK_1
    lda FormatKind,X
    beq FORMATDISK_3
    cmp #$08
    bcs CALLFORMATHOOK_3
FORMATDISK_3:
    jsr CALLFORMATHOOK
    bcs CALLFORMATHOOK_3
    bra CALLFORMATHOOK_6

;; Calls FormatHook ($BA), which points at an RTS until something changes it.
CALLFORMATHOOK:
    jmp (FormatHook)
CALLFORMATHOOK_1:
    lda #$0F
    jsr DRIVESENSE
    bcc CALLFORMATHOOK_4
    ldy FormatKind,X
    cpy #$08
    bne CALLFORMATHOOK_2
    lda #$50
    sta MfmGap
    lda #$20
    sta MediaMode,X
    bra CALLFORMATHOOK_5
CALLFORMATHOOK_2:
    cpy #$08
    bcc CALLFORMATHOOK_6
CALLFORMATHOOK_3:
    lda #$21
    bra FORMATDISK_1
CALLFORMATHOOK_4:
    lda #$40
    sta MediaMode,X
    lda #$02
    sta Interleave
    lda #$65
    sta MfmGap
    ldx Drive
    lda FormatKind,X
    beq CALLFORMATHOOK_5
    cmp #$0A
    beq CALLFORMATHOOK_5
    cmp #$0C
    bne CALLFORMATHOOK_3
CALLFORMATHOOK_5:
    jsr MFMON
    stz NibbleHighBits
    stz Nibble0
CALLFORMATHOOK_6:
    jsr FORGETCACHE
    jsr MOTORON
    jsr RECALIBRATE
    bcs CALLFORMATHOOK_12
    jsr WAITREADY
    bcs CALLFORMATHOOK_12
    ldy Drive
    ldx FormatKind,Y
    beq CALLFORMATHOOK_7
    lda FormatInterleave,Y
    sta Interleave
    cpx #$02
    bne CALLFORMATHOOK_7
    stz TwoSided
CALLFORMATHOOK_7:
    stz Side
    stz Track
CALLFORMATHOOK_8:
    lda #$03
    sta Retries
CALLFORMATHOOK_9:
    jsr WRITETRACK
    bcs CALLFORMATHOOK_12
    jsr VERIFYTRACK
    bcc CALLFORMATHOOK_10
    jsr COUNTRETRY
    bcc CALLFORMATHOOK_9
    bra CALLFORMATHOOK_12
CALLFORMATHOOK_10:
    bit TwoSided
    bmi CALLFORMATHOOK_11
    lda #$20
    sta Side
    jsr WIPESIDE
CALLFORMATHOOK_11:
    lda #$20
    eor Side
    sta Side
    bne CALLFORMATHOOK_8
    inc Track
    lda Track
    cmp #$50
    bcc CALLFORMATHOOK_8
    stz Side
    stz Track
    ldx Drive
    jsr CLEARFORMAT
    jsr RECALIBRATE
    clc
    jsr IDENTIFYMEDIA
    bcs CALLFORMATHOOK_13
    rts
CALLFORMATHOOK_12:
    lda #$27
CALLFORMATHOOK_13:
    pha
    ldx Drive
    jsr CLEARFORMAT
    jsr EJECT
    pla
    jmp SETERROR

;; Forgets SETFORMAT's choice: the defaults (two sides, interleave 4) for the next FORMAT.
;; In:    X = the drive
CLEARFORMAT:
    lda FormatKind,X
    beq CLEARFORMAT_1
    lda #$80
    sta TwoSided
    lda #$04
    sta Interleave
    stz FormatInterleave,X
    stz FormatKind,X
CLEARFORMAT_1:
    rts

;; Writes a track's length of $BB bytes over the second side of a single-sided GCR format.
WIPESIDE:
    bit SwimState
    bmi WIPESIDE_2
    lda Track
    lsr A
    lsr A
    lsr A
    and #$0E
    sta Scratch
    jsr SELECTREADHEAD
    ldx Scratch
    lda WIPELENGTHS+1,X
    tay
    lda WIPELENGTHS,X
    tax
    lda #$BB
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
WIPESIDE_1:
    bit Iwm::DataLatch
    bpl WIPESIDE_1
    sta Iwm::LoadLatch
    dex
    bne WIPESIDE_1
    dey
    bne WIPESIDE_1
    bit Iwm::ReadMode
    bit Iwm::DataLatch
WIPESIDE_2:
    rts

;; WIPESIDE's byte counts (low, high) by zone.
WIPELENGTHS:
    .byte $94
    .byte $25, $74, $22, $54, $1F, $34, $1C, $14, $19

;; Writes a whole track, by GCR or MFM.
;; Out:   carry = set if it failed
WRITETRACK:
    bit SwimState
    bpl WRITETRACK_1
    jmp WRITETRACKMFM
WRITETRACK_1:
    jmp WriteTrackVector

;; The WriteTrackVector routine: writes a GCR track: each sector's address and an empty data field,
;; in INTERLEAVEMAP's order.
WriteGcrTrack:
    jsr SEEK
    jsr MAKEHEADER
    jsr WAITREADYEVER
    stz DiskErrors
    lda Side
    bne WRITETRACKGCR_1
    lda Track
    and #$0F
    bne WRITETRACKGCR_1
    lda Track
    lsr A
    lsr A
    lsr A
    lsr A
    tax
    lda ZONEDELAYS,X
    jsr DELAY2
WRITETRACKGCR_1:
    jsr SELECTREADHEAD
    lda SectorsPerTrack
    sta SectorCount
    ldy #$C8
    lda #$FF
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
WRITETRACKGCR_SECTOR:
    ldx #$04
WRITETRACKGCR_2:
    lda SyncBytes,X
WRITETRACKGCR_3:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_3
    sta Iwm::LoadLatch
    dex
    bpl WRITETRACKGCR_2
    dey
    bne WRITETRACKGCR_SECTOR
    ldx #$03
WRITETRACKGCR_4:
    lda AddressMark,X
WRITETRACKGCR_5:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_5
    sta Iwm::LoadLatch
    dex
    bpl WRITETRACKGCR_4
    ldx #$04
WRITETRACKGCR_6:
    ldy AddressChecksum,X
    lda GCRENCODE,Y
WRITETRACKGCR_7:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_7
    sta Iwm::LoadLatch
    dex
    bpl WRITETRACKGCR_6
    ldx #$0B
WRITETRACKGCR_8:
    lda DataMark,X
WRITETRACKGCR_9:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_9
    sta Iwm::LoadLatch
    dex
    bpl WRITETRACKGCR_8
    ldx AddressSector
    lda GCRENCODE,X
WRITETRACKGCR_10:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_10
    sta Iwm::LoadLatch
    ldx #$03
    ldy #$EB
    bra WRITETRACKGCR_12
WRITETRACKGCR_11:
    ldy #$EA
WRITETRACKGCR_12:
    lda #$96
WRITETRACKGCR_13:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_13
    sta Iwm::LoadLatch
    dey
    bne WRITETRACKGCR_12
    dex
    bne WRITETRACKGCR_11
    ldx #$01
WRITETRACKGCR_14:
    lda Epilogue+1,X
WRITETRACKGCR_15:
    bit Iwm::DataLatch
    bpl WRITETRACKGCR_15
    sta Iwm::LoadLatch
    dex
    bpl WRITETRACKGCR_14
    dec SectorCount
    beq WRITETRACKGCR_16
    lda AddressSector
    eor AddressChecksum
    ldy SectorCount
    ldx INTERLEAVEMAP-1,Y
    stx AddressSector
    eor AddressSector
    ldy #$FF
    sty Iwm::LoadLatch
    sta AddressChecksum
    ldy #$0A
    jmp WRITETRACKGCR_SECTOR
WRITETRACKGCR_16:
    lda #$40
    and Iwm::DataLatch
    eor #$40
    tsb DiskErrors
WRITETRACKGCR_17:
    lda Iwm::DataLatch
    bpl WRITETRACKGCR_17
    lda #$FF
    sta Iwm::LoadLatch
WRITETRACKGCR_18:
    bit Iwm::DataLatch
    bvs WRITETRACKGCR_18
    bit Iwm::ReadMode
    lda DiskErrors
    cmp #$01
    rts

;; Milliseconds / 2 to wait before writing the first track of each GCR zone.
ZONEDELAYS:
    .byte $96, $19, $19, $19, $19

;; Reads back each sector of the track just written, through the VerifyVector vector.
VERIFYTRACK:
    jmp VerifyVector

;; The VerifyVector routine: reads every sector of the track once.
;; Out:   carry = set if one failed
VerifyGcrTrack:
    jsr DELAY1MS
    lda #$00
    sta BufferPointer
    sta SecondBufferPointer
    lda #$0C
    sta BufferPointer+1
    sta SecondBufferPointer+1
    jsr SELECTREADHEAD
    ldx SectorsPerTrack
    stx SectorCount
VERIFYTRACKGCR_1:
    stz SECTORFLAGS,X
    dex
    bpl VERIFYTRACKGCR_1
VERIFYTRACKGCR_2:
    jsr READADDRESS
    bcs VERIFYTRACKGCR_4
    ldx AddressSector
    cpx SectorsPerTrack
    bcs VERIFYTRACKGCR_3
    lda SECTORFLAGS,X
    bmi VERIFYTRACKGCR_3
    lda #$FF
    sta SECTORFLAGS,X
    jsr READDATA
    bcs VERIFYTRACKGCR_4
    dec SectorCount
    bne VERIFYTRACKGCR_2
    clc
    rts
VERIFYTRACKGCR_3:
    jsr LEAVEISMIF
VERIFYTRACKGCR_4:
    sec
    rts

;; Works out a GCR track's sector count, interleave map and address-field bytes.
MAKEHEADER:
    lda Track
    lsr A
    lsr A
    lsr A
    lsr A
    tax
    lda ZONESECTORS,X
    sta SectorsPerTrack
    jsr MAKEINTERLEAVE
    lda Track
    and #$3F
    sta AddressTrack
    stz AddressSector
    lda Track
    and #$40
    beq MAKEHEADER_1
    inc A
MAKEHEADER_1:
    ldx Side
    beq MAKEHEADER_2
    ora #$20
MAKEHEADER_2:
    sta AddressSide
    lda Interleave
    bit TwoSided
    bpl MAKEHEADER_3
    ora #$20
MAKEHEADER_3:
    sta AddressFormat
    eor AddressSide
    eor AddressTrack
    sta AddressChecksum
    rts

;; Builds INTERLEAVEMAP: the order of the track's sectors for Interleave.
MAKEINTERLEAVE:
    lda Interleave
    bne MAKEINTERLEAVE_1
    lda #$01
    sta Interleave
MAKEINTERLEAVE_1:
    lda SectorsPerTrack
    dec A
    dec A
    cmp Interleave
    bcs MAKEINTERLEAVE_2
    sta Interleave
MAKEINTERLEAVE_2:
    ldx SectorsPerTrack
    inx
    lda #$FF
MAKEINTERLEAVE_3:
    sta INTERLEAVEMAP,X
    dex
    bpl MAKEINTERLEAVE_3
    ldx SectorsPerTrack
    dex
    ldy #$00
MAKEINTERLEAVE_4:
    tya
    sta INTERLEAVEMAP,X
    iny
    cpy SectorsPerTrack
    beq MAKEINTERLEAVE_7
    txa
    sec
    sbc Interleave
    tax
MAKEINTERLEAVE_5:
    bpl MAKEINTERLEAVE_6
    txa
    clc
    adc SectorsPerTrack
    tax
MAKEINTERLEAVE_6:
    bit INTERLEAVEMAP,X
    bmi MAKEINTERLEAVE_4
    dex
    bra MAKEINTERLEAVE_5
MAKEINTERLEAVE_7:
    clc
MAKEINTERLEAVE_8:
    rts

;; Writes an MFM track through the ISM: the gaps, each sector's ID and an empty data field.
WRITETRACKMFM:
    jsr SEEK
    stz UnitWithHighBit
    lda #$12
    ldx Drive
    ldy FormatKind,X
    cpy #$08
    bne WRITETRACKMFM_1
    lda #$09
    dec UnitWithHighBit
WRITETRACKMFM_1:
    sta SectorsPerTrack
    sta SectorCount
    jsr MAKEINTERLEAVE
    jsr WAITREADY
    bcs MAKEINTERLEAVE_8
    lda Track
    bne WRITETRACKMFM_2
    lda Side
    bne WRITETRACKMFM_2
    lda #$96
    jsr DELAY2
    lda #$96
    jsr DELAY2
WRITETRACKMFM_2:
    jsr SELECTREADHEAD
    jsr ENTERISM
    bit Ism::ReadError
    lda #$18
    sta Ism::ClearMode
    lda #$10
    sta Ism::SetMode
    lda #$01
    sta Ism::SetMode
    sta Ism::ClearMode
    sta AddressSector
    bit Ism::ReadError
    ldy #$34
    ldx #$35
    bit UnitWithHighBit
    bpl WRITETRACKMFM_3
    ldy #$9A
    ldx #$1A
WRITETRACKMFM_3:
    lda #$4E
    sta Ism::WriteData
    sta Ism::WriteData
    lda #$08
    sta Ism::SetMode
WRITETRACKMFM_4:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_4
    beq WRITETRACKMFM_5
    lda #$4E
    sta Ism::WriteData
    lda #$08
    dey
    bne WRITETRACKMFM_4
    dex
    bne WRITETRACKMFM_4
    jmp WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_5:
    lda #$4E
    sta Ism::WriteData
    lda #$08
WRITETRACKMFM_6:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_6
    bne WRITETRACKMFM_7
    lda #$4E
    sta Ism::WriteData
    lda #$08
    dey
    bne WRITETRACKMFM_6
    dex
    bne WRITETRACKMFM_6
    jmp WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_7:
    lda #$4E
    sta Ism::WriteData
    lda #$F0
    sta Ism::WritePhase
    ldx #$4F
    lda #$4E
WRITETRACKMFM_8:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_8
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_8
    ldx #$0C
WRITETRACKMFM_9:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_9
    stz Ism::WriteData
    dex
    bne WRITETRACKMFM_9
    ldx #$03
WRITETRACKMFM_10:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_10
    lda #$C2
    sta Ism::WriteMark
    dex
    bne WRITETRACKMFM_10
WRITETRACKMFM_11:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_11
    lda #$FC
    sta Ism::WriteData
    ldx #$32
    lda #$4E
WRITETRACKMFM_12:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_12
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_12
    bra WRITETRACKMFM_14
WRITETRACKMFM_SECTOR:
    ldx MfmGap
    lda #$4E
WRITETRACKMFM_13:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_13
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_13
WRITETRACKMFM_14:
    ldx #$0C
WRITETRACKMFM_15:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_15
    stz Ism::WriteData
    dex
    bne WRITETRACKMFM_15
    ldx #$03
WRITETRACKMFM_16:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_16
    lda #$A1
    sta Ism::WriteMark
    dex
    bne WRITETRACKMFM_16
WRITETRACKMFM_17:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_17
    lda #$FE
    sta Ism::WriteData
    lda Track
WRITETRACKMFM_18:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_18
    sta Ism::WriteData
    lda #$00
    ldx Side
    beq WRITETRACKMFM_19
    inc A
WRITETRACKMFM_19:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_19
    sta Ism::WriteData
    lda AddressSector
WRITETRACKMFM_20:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_20
    sta Ism::WriteData
WRITETRACKMFM_21:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_21
    lda #$02
    sta Ism::WriteData
WRITETRACKMFM_22:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_22
    stz Ism::WriteCrc
    ldx #$16
    lda #$4E
WRITETRACKMFM_23:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_23
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_23
    ldx #$0C
WRITETRACKMFM_24:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_24
    stz Ism::WriteData
    dex
    bne WRITETRACKMFM_24
    ldx #$03
WRITETRACKMFM_25:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_25
    lda #$A1
    sta Ism::WriteMark
    dex
    bne WRITETRACKMFM_25
WRITETRACKMFM_26:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_26
    lda #$FB
    sta Ism::WriteData
    ldx #$00
    lda #$00
WRITETRACKMFM_27:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_27
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_27
WRITETRACKMFM_28:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_28
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_28
WRITETRACKMFM_29:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_29
    stz Ism::WriteCrc
    dec SectorCount
    beq WRITETRACKMFM_30
    ldy SectorCount
    lda INTERLEAVEMAP-1,Y
    inc A
    sta AddressSector
    jmp WRITETRACKMFM_SECTOR
WRITETRACKMFM_30:
    lda #$04
    sta Scratch
    ldx #$05
WRITETRACKMFM_31:
    bit Ism::ReadHandshake
    bpl WRITETRACKMFM_31
    lda #$4E
    sta Ism::WriteData
    dex
    bne WRITETRACKMFM_31
    ldy #$00
    lda #$F4
    sta Ism::WritePhase
    ldx #$4E
WRITETRACKMFM_32:
    lda Ism::ReadHandshake
    bpl WRITETRACKMFM_32
    stx Ism::WriteData
    bit #$08
    bne WRITETRACKMFM_33
    dey
    bne WRITETRACKMFM_32
    dec Scratch
    bne WRITETRACKMFM_32
    bra WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_33:
    and #$20
    beq WRITETRACKMFM_34
    lda #$34
    sec
    bra WRITETRACKMFM_35
WRITETRACKMFM_34:
    lda #$00
    clc
WRITETRACKMFM_35:
    sta DiskErrors
    php
    lda #$18
    sta Ism::ClearMode
    jsr LEAVEISM
    plp
    rts
WRITETRACKMFM_TIMEOUT:
    lda #$35
    sec
    bra WRITETRACKMFM_35

;; Unused.
DIVIDE7_PAD:
    .res $F500-*

;; Divides a bus packet's byte count by 7.
;; In:    WorkPointer = the count
;; Out:   Groups = the 7-byte groups, OddBytes = the rest
DIVIDE7:
    stz Groups
    ldx #$08
    lda WorkPointer+1
DIVIDE7_1:
    asl WorkPointer
    rol A
    cmp #$07
    bcc DIVIDE7_2
    sbc #$07
DIVIDE7_2:
    rol Groups
    dex
    bne DIVIDE7_1
    sta OddBytes
    rts
