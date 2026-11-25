;; THE CARD'S FIRMWARE: READING AND WRITING BLOCKS

;; Counts a retry: ResultA/ResultX tally the errors, Retries counts down.
;; Out:   carry = set with ErrorCode = $27 when the retries are used up; else A = DiskErrors, which is cleared
COUNTRETRY:
    inc ResultA
    bne COUNTRETRY_1
    inc ResultX
COUNTRETRY_1:
    dec Retries
    bpl COUNTRETRY_2
    lda #$27
    sta ErrorCode
    sec
    rts
COUNTRETRY_2:
    lda DiskErrors
    stz DiskErrors
    clc
    rts

;; SmartPort READ ($08) and WRITE ($09): a 524-byte block with its 12 tag bytes, on a GCR 400K or 800K
;; disk. The byte count must be $020C, and the address parameter is the block number.
;; Out:   READ: the tags and data at $0C00-$0E0B, CardData = 6
READWRITE:
    lda #$11
    ldx Drive
    bpl READWRITE_2
READWRITE_1:
    jmp SETERROR
READWRITE_2:
    jsr CHECKDISK
    bpl READWRITE_3
    jsr IDENTIFYMEDIA
READWRITE_3:
    bcs READWRITE_1
    lda MediaKind,Y
    cmp #$04
    beq READWRITE_4
    cmp #$02
    beq READWRITE_4
    lda #$27
    jmp SETERROR
READWRITE_4:
    lda CountHigh
    cmp #$02
    beq READWRITE_6
READWRITE_5:
    jmp ERRBADPARAMETER
READWRITE_6:
    lda Count
    cmp #$0C
    bne READWRITE_5
    lda ParameterHigh
    sta ParameterLow
    lda Parameter3
    sta ParameterMiddle
    stz ParameterHigh
    stz Parameter3
    dec TagCall
    lda #$06
    sta BufferCode
    lda CardState
    cmp #$01
    beq READWRITE_7
    jmp DOWRITEBLOCK
READWRITE_7:
    jsr READTAGGED
    bcs READWRITE_10
    ldy #$0B
READWRITE_8:
    lda TAGBYTES,Y
    sta XFERBUFFER,Y
    dey
    bpl READWRITE_8
    ldy #$00
READWRITE_9:
    lda XFERBUFFER+$200,Y
    sta XFERBUFFER+$0C,Y
    lda XFERBUFFER+$300,Y
    sta XFERBUFFER+$10C,Y
    iny
    bne READWRITE_9
    lda BufferCode
    stz ErrorCode
    sta CardData
READWRITE_10:
    clc
    rts

;; Reads the block in ParameterLow/ParameterMiddle and its tags into buffer code 6's two halves.
;; Out:   carry = set with ErrorCode set if it failed
READTAGGED:
    jsr CHECKBLOCK
    bcs READTAGGED_7
    lda #$06
    sta Retries
    stz SwimState
    jsr MOTORON
    jsr BLOCKTOSECTOR
    bcs READTAGGED_7
    asl A
    asl A
    asl A
    sta SectorCount
READTAGGED_1:
    jsr SEEK
    bcs READTAGGED_6
READTAGGED_2:
    lda BufferCode
    jsr SETBUFFER
    jsr WAITREADYEVER
READTAGGED_3:
    jsr READADDRESS
    bcc READTAGGED_8
    jsr COUNTRETRY
    bcs READTAGGED_6
    bit #$04
    bne READTAGGED_1
    bit #$01
    beq READTAGGED_4
    jsr RECALIBRATE
    bcc READTAGGED_1
READTAGGED_4:
    bit #$20
    beq READTAGGED_6
READTAGGED_5:
    dec SectorCount
    bne READTAGGED_3
READTAGGED_6:
    lda #$27
READTAGGED_7:
    jsr SETERROR
    sec
    rts
READTAGGED_8:
    lda AddressSector
    cmp Sector
    bne READTAGGED_5
    jsr READDATA
    bcc READTAGGED_9
    jsr COUNTRETRY
    bcc READTAGGED_2
    bra READTAGGED_6
READTAGGED_9:
    clc
    rts

;; SmartPort READBLOCK ($01), and ProDOS READ: reads the block from the cache, or reads its whole
;; track into the cache and hands the host the block's buffer as soon as it is read.
;; Out:   CardData = the buffer code the host copies from, or 0 with ErrorCode set
DOREADBLOCK:
    lda #$11
    ldx Drive
    bpl DOREADBLOCK_2
DOREADBLOCK_1:
    jmp SETERROR
DOREADBLOCK_2:
    jsr CHECKDISK
    bpl DOREADBLOCK_3
    jsr IDENTIFYMEDIA
DOREADBLOCK_3:
    bcs DOREADBLOCK_1
    jsr CHECKBLOCK
    bcs DOREADBLOCK_1
    lda #$80
    sta Reading
    ldx Drive
    lda #$60
    bit MediaMode,X
    beq DOREADBLOCK_5
    bit TagCall
    bpl DOREADBLOCK_4
    lda #$21
    sta TagError
    rts
DOREADBLOCK_4:
    jsr MFMON
DOREADBLOCK_5:
    jsr BLOCKTOSECTOR
    bcs DOREADBLOCK_1
    sta SectorsPerTrack
    and #$10
    asl A
    adc #$60
    sta SectorTries
    jsr FINDCACHED
    bcc DOREADBLOCK_6
    sta CardData
    clc
    rts
DOREADBLOCK_6:
    lda #$06
    sta Retries
    lda #$04
    sta ResultStatus
    lda #$14
    sta ResultY
    jsr MOTORON
    lda #$00
    sta SpanStart
    lda SectorsPerTrack
    sta SpanEnd
    dec A
    sta SectorCount
    lda #$C0
    ldx SectorsPerTrack
DOREADBLOCK_7:
    sta SECTORFLAGS,X
    cpx SpanStart
    bcc DOREADBLOCK_8
    cpx SpanEnd
    bcs DOREADBLOCK_8
    stz SECTORFLAGS,X
DOREADBLOCK_8:
    dex
    bpl DOREADBLOCK_7
    lda CacheOption
    sta ReadState
    bra DOREADBLOCK_10
DOREADBLOCK_9:
    jsr RECALIBRATE
    bcs DOREADBLOCK_FAIL
DOREADBLOCK_10:
    dec ResultStatus
    bmi DOREADBLOCK_FAIL
    jsr SEEK
    bcs DOREADBLOCK_FAIL
    jsr WAITREADY
    bcc DOREADBLOCK_READ
DOREADBLOCK_11:
    lda #$2F
    bra DOREADBLOCK_15
DOREADBLOCK_READ:
    stz DiskErrors
    jsr READADDRESS
    bcc DOREADBLOCK_16
    lda DiskErrors
    bit #$04
    bne DOREADBLOCK_10
    bit #$20
    beq DOREADBLOCK_14
    dec SectorTries
    beq DOREADBLOCK_FAIL
    lda SectorTries
    and #$3F
    lsr A
    cmp SectorsPerTrack
    beq DOREADBLOCK_12
    bit #$08
    beq DOREADBLOCK_READ
    bra DOREADBLOCK_10
DOREADBLOCK_12:
    bit ReadState
    bvc DOREADBLOCK_9
DOREADBLOCK_13:
    jsr LEAVEISMIF
    sec
    rts
DOREADBLOCK_14:
    bit #$01
    beq DOREADBLOCK_FAIL
    bit ReadState
    bvs DOREADBLOCK_13
    lda #$02
    jsr DRIVESENSE
    bcs DOREADBLOCK_11
    dec ResultStatus
    bmi DOREADBLOCK_FAIL
    jsr RECALIBRATE
    stz DiskErrors
    jsr READADDRESS
    bcc DOREADBLOCK_10
    ldx Drive
    jsr FORGETDISK
DOREADBLOCK_FAIL:
    lda #$27
DOREADBLOCK_15:
    bit ReadState
    bvs DOREADBLOCK_13
    jmp SETERROR
DOREADBLOCK_16:
    ldx AddressSector
    cpx Sector
    bne DOREADBLOCK_18
    bit ReadState
    bvs DOREADBLOCK_13
    jsr FILLSLOT
    stz Reading
    jsr READDATA
    bcc DOREADBLOCK_17
    jsr COUNTRETRY
    bcs DOREADBLOCK_FAIL
    bra DOREADBLOCK_26
DOREADBLOCK_17:
    lda BufferCode
    sta CardData
    lda SectorCount
    ora #$80
    sta CardState
    lda #$40
    tsb ReadState
    bra DOREADBLOCK_23
DOREADBLOCK_18:
    bit ReadState
    bmi DOREADBLOCK_26
    bit SECTORFLAGS,X
    bvs DOREADBLOCK_19
    ldy SECTORSLOTS,X
    lda CACHEOWNER-1,Y
    bmi DOREADBLOCK_22
    cmp Drive
    bne DOREADBLOCK_22
    lda CACHECYLINDER-1,Y
    cmp Cylinder
    bne DOREADBLOCK_22
    lda CACHESECTORS-1,Y
    cmp AddressSector
    bne DOREADBLOCK_22
    lda #$40
    sta SECTORFLAGS,X
    bra DOREADBLOCK_25
DOREADBLOCK_19:
    bit ReadState
    bvc DOREADBLOCK_26
    ldx #$08
DOREADBLOCK_20:
    lda #$CC
DOREADBLOCK_21:
    bit CardState
    bpl DOREADBLOCK_27
    dec A
    bne DOREADBLOCK_21
    dex
    bne DOREADBLOCK_20
    bra DOREADBLOCK_26
DOREADBLOCK_22:
    jsr FILLSLOT
    jsr READDATA
    bcc DOREADBLOCK_23
    dec ResultY
    bpl DOREADBLOCK_25
    lda #$80
    tsb ReadState
    bra DOREADBLOCK_25
DOREADBLOCK_23:
    ldx AddressSector
    lda #$40
    sta SECTORFLAGS,X
    lda AddressSector
    jsr CACHESECTOR
    bcc DOREADBLOCK_25
DOREADBLOCK_24:
    jmp DOREADBLOCK_FAIL
DOREADBLOCK_25:
    bit ReadState
    bvc DOREADBLOCK_26
    bmi DOREADBLOCK_27
    dec SectorCount
    beq DOREADBLOCK_27
    lda CardState
    bpl DOREADBLOCK_27
DOREADBLOCK_26:
    jsr LEAVEISMIF
    dec SectorTries
    beq DOREADBLOCK_24
    jmp DOREADBLOCK_READ
DOREADBLOCK_27:
    jsr LEAVEISMIF
    bit ReadState
    bvs DOREADBLOCK_28
    clc
    rts
DOREADBLOCK_28:
    sec
    rts

;; SmartPort WRITEBLOCK ($02), and ProDOS WRITE: asks the host for the block in buffer code 6 and
;; writes it; on a IIgs it starts writing while the host is still copying.
;; Out:   ErrorCode = the error
DOWRITEBLOCK:
    lda #$11
    ldx Drive
    bmi DOWRITEBLOCK_2
    jsr CHECKDISK
    bpl DOWRITEBLOCK_1
    jsr IDENTIFYMEDIA
DOWRITEBLOCK_1:
    bcc DOWRITEBLOCK_3
DOWRITEBLOCK_2:
    jmp SETERROR
DOWRITEBLOCK_3:
    bne DOWRITEBLOCK_2
    jsr CHECKBLOCK
    bcs DOWRITEBLOCK_2
    ldx Drive
    lda #$60
    bit MediaMode,X
    beq DOWRITEBLOCK_5
    bit TagCall
    bpl DOWRITEBLOCK_4
    lda #$21
    sta TagError
    rts
DOWRITEBLOCK_4:
    jsr MFMON
DOWRITEBLOCK_5:
    lda #$06
    sta Retries
    lda #$03
    sta ResultStatus
    jsr BLOCKTOSECTOR
    bcs DOWRITEBLOCK_2
    sta SectorsPerTrack
    and #$18
    asl A
    adc #$60
    sta SectorTries
    ldx Sector
    jsr FILLSLOT
    stz WriteProgress
    bit TestCall
    bmi DOWRITEBLOCK_6
    bit SharedExpansion+HOSTTYPEOFFSET
    bvc DOWRITEBLOCK_6
    bit TagCall
    bmi DOWRITEBLOCK_6
    bit SwimState
    bmi DOWRITEBLOCK_6
    dec WriteProgress
DOWRITEBLOCK_6:
    lda BufferCode
    sta CardData
    jsr MOTORON
    jsr SEEK
    bcs DOWRITEBLOCK_19
    bit TestCall
    bmi DOWRITEBLOCK_9
    bit WriteProgress
    bmi DOWRITEBLOCK_8
DOWRITEBLOCK_7:
    lda CardData
    bpl DOWRITEBLOCK_7
DOWRITEBLOCK_8:
    bit TagCall
    bpl DOWRITEBLOCK_9
    jsr PREPAREDATATAGS
    bra DOWRITEBLOCK_10
DOWRITEBLOCK_9:
    jsr PREPAREDATA
DOWRITEBLOCK_10:
    jsr WAITREADY
    bcc DOWRITEBLOCK_12
DOWRITEBLOCK_11:
    lda #$2F
    bra DOWRITEBLOCK_20
DOWRITEBLOCK_12:
    jsr READADDRESS
    bcc DOWRITEBLOCK_16
    lda DiskErrors
    bit #$04
    bne DOWRITEBLOCK_14
    bit #$20
    beq DOWRITEBLOCK_15
    dec SectorTries
    beq DOWRITEBLOCK_19
    lda SectorTries
    and #$3F
    lsr A
    cmp SectorsPerTrack
    beq DOWRITEBLOCK_13
    bit #$08
    beq DOWRITEBLOCK_12
    bra DOWRITEBLOCK_14
DOWRITEBLOCK_13:
    jsr RECALIBRATE
    bcs DOWRITEBLOCK_19
DOWRITEBLOCK_14:
    dec ResultStatus
    bmi DOWRITEBLOCK_19
    jsr SEEK
    bcc DOWRITEBLOCK_10
    bra DOWRITEBLOCK_19
DOWRITEBLOCK_15:
    bit #$01
    beq DOWRITEBLOCK_19
    lda #$02
    jsr DRIVESENSE
    bcs DOWRITEBLOCK_11
    bra DOWRITEBLOCK_13
DOWRITEBLOCK_16:
    lda AddressSector
    cmp Sector
    beq DOWRITEBLOCK_17
    dec SectorTries
    beq DOWRITEBLOCK_19
    jsr LEAVEISMIF
    bra DOWRITEBLOCK_12
DOWRITEBLOCK_17:
    jsr WRITEDATA
    bcs DOWRITEBLOCK_19
    bit TestCall
    bmi DOWRITEBLOCK_18
    lda Sector
    jsr CACHESECTOR
DOWRITEBLOCK_18:
    clc
    rts
DOWRITEBLOCK_19:
    lda #$27
DOWRITEBLOCK_20:
    sta ErrorCode
    clc
    rts

;; The boot command ($0C): READBLOCK of block 0 of unit 1 as a ProDOS call, or $28 if there is no
;; drive 1. A SmartPort bus device as unit 1 is read through the bus.
BOOTREAD:
    stz ErrorCode
    stz Side
    stz Track
    stz Cylinder
    jsr FLUSHCACHE
    lda #$01
    sta CardState
    ora #$80
    sta CardCommand
    stz ParameterLow
    stz ParameterMiddle
    stz ParameterHigh
    stz Drive
    lda #$01
    sta CardUnit
    stz SavedDrive
    ldx SavedDrive
    lda DeviceKinds,X
    beq BOOTREAD_2
    bmi BOOTREAD_1
    jsr FORGETDISK
    jmp CALLHANDLER
BOOTREAD_1:
    lda #$FF
    jsr DELAY2
    jmp PASSTOBUS
BOOTREAD_2:
    lda #$28
    sta ErrorCode
    stz CardData
    clc
    rts

;; Unused, to put the tables below on a page.
GCRHIGH_PAD:
    .res $E200-*

;; The high two bits of a 6-and-2 auxiliary nibble's three fields, for ReadGcrDataField.
GCRHIGH1:
.repeat 64, I
    .byte ((I >> 4) & 3) << 6
.endrepeat
GCRHIGH2:
.repeat 64, I
    .byte ((I >> 2) & 3) << 6
.endrepeat
GCRHIGH3:
.repeat 64, I
    .byte ((I >> 0) & 3) << 6
.endrepeat

;; Command $0D: checks a run of blocks (Parameter4/Parameter5 more after the first) and works out how many
;; lie in the first block's track, for the host, then waits briefly for the next command.
;; Out:   carry = set (the host's next command is run at once)
READAHEAD:
    lda #$11
    ldx Drive
    bpl READAHEAD_2
READAHEAD_1:
    jmp SETERROR
READAHEAD_2:
    jsr CHECKDISK
    bpl READAHEAD_3
    jsr IDENTIFYMEDIA
READAHEAD_3:
    bcs READAHEAD_1
    jsr CHECKBLOCK
    bcs READAHEAD_1
    lda #$80
    sta Reading
    ldx Drive
    lda #$60
    bit MediaMode,X
    beq READAHEAD_4
    jsr MFMON
READAHEAD_4:
    lda ParameterMiddle
    pha
    lda ParameterLow
    pha
    clc
    adc Parameter4
    sta ParameterLow
    lda ParameterMiddle
    adc Parameter5
    sta ParameterLow
    jsr CHECKBLOCK
    bcs READAHEAD_1
    pla
    sta ParameterLow
    pla
    sta ParameterMiddle
    jsr BLOCKTOSECTOR
    bcs READAHEAD_1
    sta SectorsPerTrack
    stz CountHigh
    lda SectorsPerTrack
    sec
    sbc Sector
    sta SectorCount
    ldy Parameter5
    bne READAHEAD_5
    cmp Parameter4
    beq READAHEAD_5
    bcc READAHEAD_5
    lda Parameter4
READAHEAD_5:
    sta Count
    stz CardData
    lda #$FF
    sta CardState
    lda #$05
    sta WorkPointer+1
    stz WorkPointer
READAHEAD_6:
    dec WorkPointer
    bne READAHEAD_7
    dec WorkPointer+1
    bmi READAHEAD_8
READAHEAD_7:
    lda CardState
    bmi READAHEAD_6
READAHEAD_8:
    sec
    rts

;; Command $0E: reads the sectors of a run of blocks that share a track into the cache, and lists in
;; $0600 how many were read and, from $0602, each one's buffer code ($A7 for one that failed).
;; Out:   carry = set when all were read (the host's next command is run at once)
READSPAN:
    lda #$11
    ldx Drive
    bpl READSPAN_2
READSPAN_1:
    jmp SETERROR
READSPAN_2:
    jsr CHECKDISK
    bpl READSPAN_3
    jsr IDENTIFYMEDIA
READSPAN_3:
    bcs READSPAN_1
    jsr CHECKBLOCK
    bcs READSPAN_1
    lda #$80
    sta Reading
    ldx Drive
    lda #$60
    bit MediaMode,X
    beq READSPAN_4
    jsr MFMON
READSPAN_4:
    jsr BLOCKTOSECTOR
    bcs READSPAN_1
    sta SectorsPerTrack
    lda Sector
    sta SpanFirst
    lda Cylinder
    sta SpanCylinder
    lda Parameter4
    clc
    adc ParameterLow
    sta ParameterLow
    lda Parameter5
    adc ParameterMiddle
    sta ParameterMiddle
    lda ParameterLow
    bne READSPAN_5
    dec ParameterMiddle
READSPAN_5:
    dec ParameterLow
    jsr CHECKBLOCK
    bcs READSPAN_1
    jsr BLOCKTOSECTOR
    bcs READSPAN_1
    lda Cylinder
    cmp SpanCylinder
    beq READSPAN_6
    lda #$2D
    jmp SETERROR
READSPAN_6:
    stz INTERLEAVEMAP
    stz INTERLEAVEMAP+1
    ldx SectorsPerTrack
READSPAN_7:
    dex
    stz INTERLEAVEMAP+2,X
    bne READSPAN_7
    lda SpanFirst
    sta SpanStart
    lda Sector
    inc A
    sta SpanEnd
    sec
    sbc SpanFirst
    sta SectorCount
    asl A
    asl A
    sta Retries
    lda #$40
    ldx SectorsPerTrack
    stx AddressSector
READSPAN_8:
    sta SECTORFLAGS,X
    cpx SpanStart
    bcc READSPAN_9
    cpx SpanEnd
    bcs READSPAN_9
    stz SECTORFLAGS,X
READSPAN_9:
    dex
    bpl READSPAN_8
    lda #$03
    sta CardData
    lda SectorsPerTrack
    asl A
    asl A
    inc A
    sta SectorTries
    lda #$02
    sta ResultStatus
    jsr MOTORON
    bra READSPAN_11
READSPAN_10:
    jsr RECALIBRATE
    bcs READSPAN_15
READSPAN_11:
    dec ResultStatus
    bmi READSPAN_15
    jsr SEEK
    bcs READSPAN_15
    jsr WAITREADY
    bcc READSPAN_14
READSPAN_12:
    lda #$2F
    bra READSPAN_26
READSPAN_13:
    jsr LEAVEISMIF
READSPAN_14:
    stz DiskErrors
    jsr READADDRESS
    bcc READSPAN_18
    lda DiskErrors
    bit #$04
    bne READSPAN_11
    bit #$20
    bne READSPAN_16
    bit #$01
    bne READSPAN_12
READSPAN_15:
    bra READSPAN_25
READSPAN_16:
    dec SectorTries
    beq READSPAN_25
    lda SectorTries
    cmp SectorsPerTrack
    bne READSPAN_17
    bra READSPAN_10
READSPAN_17:
    bit #$08
    beq READSPAN_14
    bra READSPAN_11
READSPAN_18:
    ldx AddressSector
    bit SECTORFLAGS,X
    bvs READSPAN_19
    jsr FILLSLOT
    jsr READDATA
    bcs READSPAN_24
    ldx AddressSector
    lda #$40
    sta SECTORFLAGS,X
    txa
    sec
    sbc SpanFirst
    tax
    lda BufferCode
    sta INTERLEAVEMAP+2,X
    inc INTERLEAVEMAP
    dec SectorCount
    beq READSPAN_27
    bra READSPAN_23
READSPAN_19:
    stz Scratch
    ldx #$08
READSPAN_20:
    lda #$CC
READSPAN_21:
    bit Scratch
    bpl READSPAN_22
READSPAN_22:
    dec A
    bne READSPAN_21
    dex
    bne READSPAN_20
READSPAN_23:
    dec SectorTries
    bne READSPAN_13
    bra READSPAN_25
READSPAN_24:
    dec Retries
    bpl READSPAN_13
    lda AddressSector
    sec
    sbc SpanFirst
    tax
    lda #$A7
    sta INTERLEAVEMAP+2,X
READSPAN_25:
    lda #$27
READSPAN_26:
    sta ErrorCode
    lda #$01
    sta INTERLEAVEMAP+1
    clc
    rts
READSPAN_27:
    lda #$FF
    sta CardState
    lda #$05
    sta WorkPointer+1
    stz WorkPointer
READSPAN_28:
    dec WorkPointer
    bne READSPAN_29
    dec WorkPointer+1
    bmi READSPAN_30
READSPAN_29:
    lda CardState
    bmi READSPAN_28
READSPAN_30:
    sec
    rts

;; Unused, to put READADDRESS on a page: GCRDECODE is indexed from it.
READADDRESS_PAD:
    .res $E500-*
