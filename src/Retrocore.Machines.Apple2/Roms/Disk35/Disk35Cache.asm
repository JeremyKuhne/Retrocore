;; THE CARD'S FIRMWARE: THE SECTOR CACHE, AND HOW A BLOCK MAPS TO A TRACK AND SECTOR

;; Marks every cache slot not in use for a write ($40) as empty ($80).
FLUSHCACHE:
    lda #$80
    ldx #$12
FLUSHCACHE_1:
    bit CACHEOWNER-1,X
    bvs FLUSHCACHE_2
    sta CACHEOWNER-1,X
FLUSHCACHE_2:
    dex
    bne FLUSHCACHE_1
    rts

;; Never called: claims a cache slot, as FILLSLOT does, without setting the buffer pointers.
UNUSEDCLAIM:
    lda CACHEOWNER-1,Y
    bit #$40
    bne UNUSEDCLAIM_1
    lda #$80
    sta CACHEOWNER-1,Y
UNUSEDCLAIM_1:
    lda SLOTBUFFERS,Y
    sty CacheSlot
    sta BufferCode
    rts

;; Claims the cache slot for a sector ($8F, filling) and points the buffers at it.
;; In:    X = the sector
;; Out:   BufferCode = its buffer code, CacheSlot = the slot
FILLSLOT:
    lda SECTORSLOTS,X
    tax
    lda #$8F
    sta CACHEOWNER-1,X
    lda SLOTBUFFERS,X
    sta BufferCode
    stx CacheSlot

;; Points BufferPointer and SecondBufferPointer at the two halves of a 512-byte buffer.
;; In:    A = the buffer code (the card address / $200)
SETBUFFER:
    tax
    lda BUFFERHIGH,X
    sta SecondBufferPointer+1
    dec A
    sta BufferPointer+1
    stz BufferPointer
    stz SecondBufferPointer
    rts

;; A buffer code's second half's page: code * 2 + 1.
BUFFERHIGH:
    .byte $01, $03, $05, $07, $09, $0B, $0D, $0F, $11, $13, $15, $17, $19, $1B, $1D, $1F
    .byte $21, $23, $25, $27, $29, $2B, $2D, $2F, $31, $33, $35

;; Each cache slot's buffer code, from slot 1 ($08, card $1000) to slot $12.
SLOTBUFFERS:
    .byte $37, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10, $11, $12, $13, $14, $15, $16
    .byte $17, $18, $19, $1A, $1B

;; Each sector's cache slot: the sector plus 1.
SECTORSLOTS:
    .byte $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10
    .byte $11, $12

;; Records the sector just read in its cache slot: the sector, the cylinder (track and side) and the
;; owner (Drive), or $8E if the data is not for a 3.5 drive.
;; In:    A = the sector, CacheSlot = the slot
CACHESECTOR:
    ldy CacheSlot
    beq CACHESECTOR_1
    sta CACHESECTORS-1,Y
    lda Side
    cmp #$01
    lda Track
    rol A
    sta CACHECYLINDER-1,Y
    lda Drive
    cmp UnitCount
    bcs CACHESECTOR_1
    sta CACHEOWNER-1,Y
    rts
CACHESECTOR_1:
    lda #$8E
    sta CACHEOWNER-1,Y
    rts

;; Answers whether the block in ParameterLow/ParameterMiddle is on Drive's disk.
;; Out:   carry = set with A = $2D if it is not
CHECKBLOCK:
    ldx Drive
    lda ParameterLow
    cmp BlockCount,X
    lda ParameterMiddle
    sbc BlockCountHigh,X
    bcc CHECKBLOCK_1
    lda #$2D
CHECKBLOCK_1:
    rts

;; Drops a drive's sectors from the cache.
;; In:    X = the drive
FORGETCACHE:
    stx SavedDrive
    ldy #$12
FORGETCACHE_1:
    lda CACHEOWNER-1,Y
    cmp #$20
    bcs FORGETCACHE_2
    cmp SavedDrive
    bne FORGETCACHE_2
    lda #$80
    sta CACHEOWNER-1,Y
FORGETCACHE_2:
    dey
    bne FORGETCACHE_1
    rts

;; Looks for Sector of the current track in the cache.
;; Out:   carry = set with A = its buffer code if it is there
FINDCACHED:
    ldy Sector
    lda SECTORSLOTS,Y
    tay
    jsr MATCHSLOT
    bne FINDCACHED_1
    lda SLOTBUFFERS,Y
    sec
    rts
FINDCACHED_1:
    clc
    rts

;; Compares a cache slot with Drive, the cylinder and Sector.
;; In:    Y = the slot
;; Out:   zero = they match
MATCHSLOT:
    lda CACHEOWNER-1,Y
    cmp Drive
    bne MATCHSLOT_1
    lda Side
    cmp #$01
    lda Track
    rol A
    cmp CACHECYLINDER-1,Y
    bne MATCHSLOT_1
    lda Sector
    cmp CACHESECTORS-1,Y
MATCHSLOT_1:
    rts

;; Finds where a block is on Drive's disk, by its MediaKind.
;; Out:   carry = set with A = $3D for an unknown format; else A = the sectors in the track,
;;        Track, Side, Sector and Cylinder set
BLOCKTOSECTOR:
    ldx Drive
    lda MediaKind,X
    tax
    jmp (BLOCKMAPS,X)

;; BLOCKTOSECTOR's routine for each MediaKind.
BLOCKMAPS:
    .word MAPNONE, MAP400K, MAP800K, MAP800K, MAP720K, MAP1440K, MAP1440K ; MediaKind 0, 2, 4, 6, 8, $0A, $0C

;; BLOCKTOSECTOR for a disk of unknown format: no place.
;; Out:   carry = set, A = $3D
MAPNONE:
    stz Side
    stz Track
    stz Sector
    lda #$3D
    sec
    rts

;; BLOCKTOSECTOR for a 400K GCR disk: one side, the 4:1 interleave of Apple II disks.
MAP400K:
    lda ParameterLow
    sta Side
    and #$0F
    sta Sector
    lda ParameterMiddle
    rol Side
    rol A
    rol Side
    rol A
    rol Side
    rol A
    rol Side
    rol A
    tax
    lda GROUP400TRACK,X
    sta Cylinder
    lda GROUP400SECTOR,X
    and #$E0
    ora Sector
    tay
    lda GROUP400SECTOR,X
    jsr ZONESECTOR400
    rts

;; MAP400K's first track (times 2) of each 32-block group.
GROUP400TRACK:
    .byte $00, $02, $04, $08, $0A, $0C, $10, $12, $14, $18, $1A, $1C, $20, $22, $24, $28
    .byte $2A, $2E, $30, $34, $36, $3A, $3C, $40, $42, $46, $48, $4C, $50, $52, $56, $58
    .byte $5C, $60, $62, $66, $6A, $6E, $70, $74, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; MAP400K's group start: the zone (bits 5-7) and the first sector.
GROUP400SECTOR:
    .byte $00, $04, $08, $00, $04, $08, $00, $04, $08, $00, $04, $08, $20, $25, $2A, $24
    .byte $29, $23, $28, $22, $27, $21, $26, $40, $46, $42, $48, $44, $40, $46, $42, $48
    .byte $44, $60, $67, $65, $63, $61, $68, $66, $64, $62, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; BLOCKTOSECTOR for an 800K GCR disk: two sides, a track's two sides in turn.
MAP800K:
    lda ParameterLow
    sta Side
    and #$1F
    sta Sector
    lda ParameterMiddle
    rol Side
    rol A
    rol Side
    rol A
    rol Side
    rol A
    tax
    lda GROUP800TRACK,X
    sta Cylinder
    lda GROUP800SECTOR,X
    and #$E0
    ora Sector
    tay
    lda GROUP800SECTOR,X
    jsr ZONESECTOR800
    rts

;; MAP800K's first cylinder of each 32-block group.
GROUP800TRACK:
    .byte $00, $02, $05, $08, $0A, $0D, $10, $12, $15, $18, $1A, $1D, $20, $22, $25, $28
    .byte $2B, $2E, $31, $34, $37, $3A, $3D, $40, $43, $46, $49, $4C, $50, $53, $56, $59
    .byte $5C, $60, $63, $67, $6A, $6E, $71, $75, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; MAP800K's group start: the zone (bits 5-7) and the first sector.
GROUP800SECTOR:
    .byte $00, $08, $04, $00, $08, $04, $00, $08, $04, $00, $08, $04, $20, $2A, $29, $28
    .byte $27, $26, $25, $24, $23, $22, $21, $40, $42, $44, $46, $48, $40, $42, $44, $46
    .byte $48, $60, $65, $61, $66, $62, $67, $63, $68, $64, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; BLOCKTOSECTOR for a 1440K MFM disk: 18 sectors a side, sides in turn.
MAP1440K:
    ldx #$FE
MAP1440K_1:
    inx
    inx
    lda ZONES1440+2,X
    cmp ParameterLow
    lda ZONES1440+3,X
    sbc ParameterMiddle
    bcc MAP1440K_1
    lda ParameterLow
    sbc ZONES1440,X
    sta Work0
    lda ParameterMiddle
    sbc ZONES1440+1,X
    sta Work1
    lda CYLINDERS1440,X
    tax
    lda Work0
    bpl MAP1440K_2
    sec
    sbc #$7E
    tay
    txa
    clc
    adc #$07
    tax
    tya
MAP1440K_2:
    cmp #$12
    bcc MAP1440K_5
MAP1440K_3:
    sec
    sbc #$12
    bmi MAP1440K_4
    inx
    bra MAP1440K_3
MAP1440K_4:
    clc
    adc #$12
MAP1440K_5:
    sta Sector
    stx Cylinder
    txa
    lsr A
    sta Track
    lda #$00
    bcc MAP1440K_6
    lda #$20
MAP1440K_6:
    sta Side
    lda #$12
    clc
    rts

;; MAP1440K's blocks where each run of 10 cylinders starts, and the end ($FFFF).
ZONES1440:
    .byte $00
    .byte $00
    .byte $B4
    .byte $00, $68, $01, $1C, $02, $D0, $02, $84, $03, $38, $04, $EC, $04, $A0, $05, $54
    .byte $06, $08, $07, $BC, $07, $70, $08, $24, $09, $D8, $09, $8C, $0A, $40, $0B, $FF
    .byte $FF

;; And the first cylinder of each run.
CYLINDERS1440:
    .byte $00, $00, $0A, $00, $14, $00, $1E, $00, $28, $00, $32, $00, $3C, $00, $46, $00
    .byte $50, $00, $5A, $00, $64, $00, $6E, $00, $78, $00, $82, $00, $8C, $00, $96, $00
    .byte $FF, $FF

;; BLOCKTOSECTOR for a 720K MFM disk: 9 sectors a side, sides in turn.
MAP720K:
    ldx #$FE
MAP720K_1:
    inx
    inx
    lda ZONES720+2,X
    cmp ParameterLow
    lda ZONES720+3,X
    sbc ParameterMiddle
    bcc MAP720K_1
    lda ParameterLow
    sbc ZONES720,X
    sta Work0
    lda ParameterMiddle
    sbc ZONES720+1,X
    sta Work1
    lda CYLINDERS720,X
    tax
    lda Work0
    cmp #$09
    bcc MAP720K_4
MAP720K_2:
    sec
    sbc #$09
    bmi MAP720K_3
    inx
    bra MAP720K_2
MAP720K_3:
    clc
    adc #$09
MAP720K_4:
    sta Sector
    stx Cylinder
    txa
    lsr A
    sta Track
    lda #$00
    bcc MAP720K_5
    lda #$20
MAP720K_5:
    sta Side
    lda #$09
    clc
    rts

;; MAP720K's blocks where each run of 10 cylinders starts, and the end ($FFFF).
ZONES720:
    .byte $00
    .byte $00
    .byte $5A
    .byte $00, $B4, $00, $0E, $01, $68, $01, $C2, $01, $1C, $02, $76, $02, $D0, $02, $2A
    .byte $03, $84, $03, $DE, $03, $38, $04, $92, $04, $EC, $04, $46, $05, $A0, $05, $FF
    .byte $FF

;; And the first cylinder of each run.
CYLINDERS720:
    .byte $00, $00, $0A, $00, $14, $00, $1E, $00, $28, $00, $32, $00, $3C, $00, $46, $00
    .byte $50, $00, $5A, $00, $64, $00, $6E, $00, $78, $00, $82, $00, $8C, $00, $96, $00
    .byte $FF, $FF

;; Finishes MAP800K: the track and sector from a group of 32 blocks and the zone's sector count.
ZONESECTOR800:
    and #$1F
    clc
    sta Sector
    lda GROUPOFFSETS,Y
    and #$1F
    adc Sector
    tax
    lda GROUPOFFSETS,Y
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    clc
    adc Cylinder
    sta Cylinder
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    tay
    txa
    cmp ZONESECTORS,Y
    bcc ZONESECTOR800_1
    sbc ZONESECTORS,Y
    inc Cylinder
ZONESECTOR800_1:
    sta Sector
    lda Cylinder
    lsr A
    sta Track
    lda #$00
    bcc ZONESECTOR800_2
    lda #$20
ZONESECTOR800_2:
    sta Side
    lda ZONESECTORS,Y
    clc
    rts

;; Finishes MAP400K: the track and sector from a group of 32 blocks and the zone's sector count.
ZONESECTOR400:
    and #$1F
    clc
    sta Sector
    lda GROUPOFFSETS,Y
    and #$1F
    adc Sector
    tax
    lda GROUPOFFSETS,Y
    lsr A
    lsr A
    lsr A
    lsr A
    and #$0E
    clc
    adc Cylinder
    sta Cylinder
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    tay
    txa
    cmp ZONESECTORS,Y
    bcc ZONESECTOR400_1
    sbc ZONESECTORS,Y
    inc Cylinder
    inc Cylinder
ZONESECTOR400_1:
    sta Sector
    lda Cylinder
    lsr A
    sta Track
    stz Side
    lda ZONESECTORS,Y
    clc
    rts

;; The cylinder (bits 5-7) and sector (bits 0-4) of each block in a group, by zone.
GROUPOFFSETS:
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $20, $21, $22, $23
    .byte $24, $25, $26, $27, $28, $29, $2A, $2B, $40, $41, $42, $43, $44, $45, $46, $47
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $20, $21, $22, $23, $24
    .byte $25, $26, $27, $28, $29, $2A, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $20, $21, $22, $23, $24, $25
    .byte $26, $27, $28, $29, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49, $60, $61
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $20, $21, $22, $23, $24, $25, $26
    .byte $27, $28, $40, $41, $42, $43, $44, $45, $46, $47, $48, $60, $61, $62, $63, $64
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $20, $21, $22, $23, $24, $25, $26, $27
    .byte $40, $41, $42, $43, $44, $45, $46, $47, $60, $61, $62, $63, $64, $65, $66, $67
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F
    .byte $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D
    .byte $0E, $0F, $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B
    .byte $0C, $0D, $0E, $0F, $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09
    .byte $12, $11, $10, $0F, $0E, $0D

;; The GCR sectors per track in each 16-track zone: 12, 11, 10, 9, 8.
ZONESECTORS:
    .byte $0C, $0B, $0A, $09, $08
