; retrocore: style=strict
;; The card's firmware: the sector cache, and how a block maps to a track and sector
;;
;; The cache keeps the sectors of the track last read: 18 slots, one for each sector a track can have, each a
;; 512-byte buffer at card $1000-$33FF (buffer codes $08-$19) with the slot's owner, cylinder and sector in
;; <CacheOwners>, <CacheCylinders> and <CacheSectors>, which are indexed from 1. <BlockMap> turns a block number into
;; the cylinder, side and sector that hold it, for each kind of disk.

; What a cache slot's owner byte in CacheOwners says, when it is not a drive (0 or 1).

;; The slot holds a sector that is not a 3.5 drive's.
CACHE_NOT_A_DRIVE = $8E

;; The slot is being filled.
CACHE_FILLING = $8F

;; Owners below this are drives; the others are the values above.
CACHE_DRIVE_END = $20

; The disk kinds in MediaKind, which <BlockMap::Locate> takes as an index into <BlockMap::Maps>.

;; The error <BlockMap::Locate> gives for a disk of unknown format: not one of SmartPort's documented codes.
ERROR_UNKNOWN_FORMAT = $3D

;; The <Side> byte for the second side.
SIDE_SECOND = $20

;; The sectors in each track of a 1440K MFM disk.
MFM_1440_SECTORS = 18

;; The sectors in each track of a 720K MFM disk.
MFM_720_SECTORS = 9

;; The routines that keep a track's sectors in the card's RAM, so that a block read again, or the next block of the
;; track, needs no disk access.
.scope Cache

;; Marks every cache slot not kept for a write (<CACHE_KEPT>) as empty.
;; Out: A = <CACHE_EMPTY>, X = 0
;; Keeps: Y
.proc Flush
    lda #CACHE_EMPTY
    ldx #CACHE_SLOTS
Loop:
    bit CacheOwners-1,X
    bvs Next
    sta CacheOwners-1,X
Next:
    dex
    bne Loop
    rts
.endproc

;; Never called: claims a cache slot without pointing the buffer pointers at it, marking it empty unless it is kept
;; for a write.
;; In: Y = the slot
;; Out: A = the slot's buffer code, also in <BufferCode>; CacheSlot = Y
;; Keeps: X, Y
.proc ClaimUnused
    lda CacheOwners-1,Y
    bit #CACHE_KEPT
    bne Claim
    lda #CACHE_EMPTY
    sta CacheOwners-1,Y
Claim:
    lda SlotBuffers,Y
    sty CacheSlot
    sta BufferCode
    rts
.endproc

;; Claims the cache slot for a sector, marking it <CACHE_FILLING>, and points the buffer pointers at its buffer.
;; In: X = the sector
;; Out: BufferCode = the slot's buffer code, CacheSlot = the slot; as <PointAtBuffer>
;; Keeps: Y
.proc ClaimSlot
    lda SectorSlots,X
    tax
    lda #CACHE_FILLING
    sta CacheOwners-1,X
    lda SlotBuffers,X
    sta BufferCode
    stx CacheSlot
    ; Falls into PointAtBuffer.
.endproc

;; Points <BufferPointer> and <SecondBufferPointer> at the two 256-byte halves of a 512-byte buffer.
;; In: A = the buffer code (the card address / $200)
;; Out: X = the buffer code, A = the first half's page
;; Keeps: Y
.proc PointAtBuffer
    tax
    lda SecondPages,X
    sta SecondBufferPointer+1
    dec a
    sta BufferPointer+1
    stz BufferPointer
    stz SecondBufferPointer
    rts
.endproc

;; Each buffer code's second half's page: the code times 2, plus 1.
SecondPages:
.repeat 27, I
    .byte I * 2 + 1
.endrepeat

;; Each cache slot's buffer code, by the slot from 1: $08 (card $1000) for slot 1, to $19 for slot 18; $1A and $1B,
;; and the $37 for slot 0, are never used.
SlotBuffers:
    .byte $37
.repeat 20, I
    .byte $08 + I
.endrepeat

;; Each sector's cache slot: the sector plus 1.
SectorSlots:
.repeat CACHE_SLOTS, I
    .byte I + 1
.endrepeat

;; Records the sector just read in its cache slot: the sector, the cylinder and the owner (<Drive>), or
;; <CACHE_NOT_A_DRIVE> when <Drive> is not a 3.5 drive's unit.
;;
;; With no slot (CacheSlot 0) it marks the byte before <CacheOwners> instead, the last of <CacheSectors>' page.
;; In: A = the sector, CacheSlot = the slot
;; Out: carry = clear when the slot is <Drive>'s; set when it was marked <CACHE_NOT_A_DRIVE> for a unit past the
;;   drives, and unchanged with no slot
;; Keeps: X
.proc Record
    ldy CacheSlot
    beq NotADrive
    sta CacheSectors-1,Y

    ; The cylinder: the track times 2, plus 1 for the second side.
    lda Side
    cmp #1
    lda Track
    rol a
    sta CacheCylinders-1,Y
    lda Drive
    cmp UnitCount
    bcs NotADrive
    sta CacheOwners-1,Y
    rts
NotADrive:
    lda #CACHE_NOT_A_DRIVE
    sta CacheOwners-1,Y
    rts
.endproc

.endscope

;; Answers whether the block in <ParameterLow> and <ParameterMiddle> is on <Drive>'s disk.
;; Out: carry = set if it is past the disk's end, with A = <ERROR_BAD_BLOCK>; X = <Drive>
;; Keeps: Y
.proc CheckBlock
    ldx Drive
    lda ParameterLow
    cmp BlockCount,X
    lda ParameterMiddle
    sbc BlockCountHigh,X
    bcc Done
    lda #ERROR_BAD_BLOCK
Done:
    rts
.endproc

; The cache, continued: forgetting and finding sectors.
.scope Cache continued

;; Drops a drive's sectors from the cache; slots kept for a write stay.
;; In: X = the drive
;; Out: SavedDrive = the drive, Y = 0
;; Keeps: X
.proc Forget
    stx SavedDrive
    ldy #CACHE_SLOTS
Loop:
    lda CacheOwners-1,Y
    cmp #CACHE_DRIVE_END
    bcs Next
    cmp SavedDrive
    bne Next
    lda #CACHE_EMPTY
    sta CacheOwners-1,Y
Next:
    dey
    bne Loop
    rts
.endproc

;; Looks for <Sector> of the current cylinder of <Drive>'s disk in the cache.
;; Out: carry = set if it is there, with A = its buffer code; Y = its slot
;; Keeps: X
.proc Find
    ldy Sector
    lda SectorSlots,Y
    tay
    jsr MatchSlot
    bne NotThere
    lda SlotBuffers,Y
    sec
    rts
NotThere:
    clc
    rts
.endproc

;; Compares a cache slot's owner, cylinder and sector with <Drive>, <Track> and <Side>, and <Sector>.
;; In: Y = the slot
;; Out: zero = set if they match
;; Keeps: X, Y
.proc MatchSlot
    lda CacheOwners-1,Y
    cmp Drive
    bne Done
    lda Side
    cmp #1
    lda Track
    rol a
    cmp CacheCylinders-1,Y
    bne Done
    lda Sector
    cmp CacheSectors-1,Y
Done:
    rts
.endproc

.endscope

;; The routines that find where a block lies on a disk.
;;
;; A GCR disk has five zones of 16 tracks, with 12, 11, 10, 9 and 8 sectors a track, and its blocks are counted
;; in groups (16 blocks on a 400K disk, 32 on an 800K one) whose first cylinder and sector are in a table; the group
;; offsets in <BlockMap::GroupOffsets> place each block of a group. An MFM disk has the same number of sectors on every
;; track, and its blocks go through each cylinder's sides in turn.
.scope BlockMap

;; Finds where the block in <ParameterLow> and <ParameterMiddle> is on <Drive>'s disk, by its <MediaKind>.
;; Out: carry = set for an unknown format, with A = <ERROR_UNKNOWN_FORMAT>; otherwise A = the sectors in the track,
;;   and <Track>, <Side>, <Sector> and <Cylinder> set
.proc Locate
    ldx Drive
    lda MediaKind,X
    tax
    jmp (Maps,X)
.endproc

;; <Locate>'s routine for each <MediaKind>.
Maps:
    .word Unknown, Gcr400, Gcr800, Gcr800, Mfm720, Mfm1440, Mfm1440
.assert MEDIA_400K = 2 && MEDIA_800K = 4 && MEDIA_800K_2_TO_1 = 6, "The GCR kinds index Maps."
.assert MEDIA_720K = 8 && MEDIA_1440K = $0A, "The MFM kinds index Maps."

;; <Locate> for a disk of unknown format: track, side and sector 0.
;; Out: carry = set, A = <ERROR_UNKNOWN_FORMAT>
.proc Unknown
    stz Side
    stz Track
    stz Sector
    lda #ERROR_UNKNOWN_FORMAT
    sec
    rts
.endproc

;; <Locate> for a 400K GCR disk: one side, in 16-block groups.
;; Out: as <Locate>, carry = clear
.proc Gcr400

    ; The sector within the group: the block's low four bits. Side holds the low byte while its high four bits
    ; shift into the group number.
    lda ParameterLow
    sta Side
    and #$0F
    sta Sector
    lda ParameterMiddle
    rol Side
    rol a
    rol Side
    rol a
    rol Side
    rol a
    rol Side
    rol a

    ; The group's first cylinder, and its zone (bits 5-7) and first sector.
    tax
    lda Group400Cylinders,X
    sta Cylinder
    lda Group400Starts,X
    and #$E0
    ora Sector
    tay
    lda Group400Starts,X
    jsr FinishGcr400
    rts
.endproc

;; <Gcr400>'s first cylinder (track times 2) of each 16-block group.
Group400Cylinders:
    .byte $00, $02, $04, $08, $0A, $0C, $10, $12, $14, $18, $1A, $1C, $20, $22, $24, $28
    .byte $2A, $2E, $30, $34, $36, $3A, $3C, $40, $42, $46, $48, $4C, $50, $52, $56, $58
    .byte $5C, $60, $62, $66, $6A, $6E, $70, $74, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; <Gcr400>'s group starts: the zone (bits 5-7) and the first sector (bits 0-4).
Group400Starts:
    .byte $00, $04, $08, $00, $04, $08, $00, $04, $08, $00, $04, $08, $20, $25, $2A, $24
    .byte $29, $23, $28, $22, $27, $21, $26, $40, $46, $42, $48, $44, $40, $46, $42, $48
    .byte $44, $60, $67, $65, $63, $61, $68, $66, $64, $62, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; <Locate> for an 800K GCR disk: two sides, a cylinder's two sides in turn, in 32-block groups.
;; Out: as <Locate>, carry = clear
.proc Gcr800

    ; The sector within the group: the block's low five bits. Side holds the low byte while its high three bits
    ; shift into the group number.
    lda ParameterLow
    sta Side
    and #$1F
    sta Sector
    lda ParameterMiddle
    rol Side
    rol a
    rol Side
    rol a
    rol Side
    rol a

    ; The group's first cylinder, and its zone (bits 5-7) and first sector.
    tax
    lda Group800Cylinders,X
    sta Cylinder
    lda Group800Starts,X
    and #$E0
    ora Sector
    tay
    lda Group800Starts,X
    jsr FinishGcr800
    rts
.endproc

;; <Gcr800>'s first cylinder of each 32-block group.
Group800Cylinders:
    .byte $00, $02, $05, $08, $0A, $0D, $10, $12, $15, $18, $1A, $1D, $20, $22, $25, $28
    .byte $2B, $2E, $31, $34, $37, $3A, $3D, $40, $43, $46, $49, $4C, $50, $53, $56, $59
    .byte $5C, $60, $63, $67, $6A, $6E, $71, $75, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; <Gcr800>'s group starts: the zone (bits 5-7) and the first sector (bits 0-4).
Group800Starts:
    .byte $00, $08, $04, $00, $08, $04, $00, $08, $04, $00, $08, $04, $20, $2A, $29, $28
    .byte $27, $26, $25, $24, $23, $22, $21, $40, $42, $44, $46, $48, $40, $42, $44, $46
    .byte $48, $60, $65, $61, $66, $62, $67, $63, $68, $64, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; <Locate> for a 1440K MFM disk: 18 sectors a side, a cylinder's sides in turn.
;; Out: as <Locate>, carry = clear; <Work0> and Work1 = the block's offset in its run of 10 cylinders
.proc Mfm1440

    ; The run of 10 cylinders (180 blocks) the block is in: the last whose start is not past it.
    ldx #$FE
FindRun:
    inx
    inx
    lda Runs1440+2,X
    cmp ParameterLow
    lda Runs1440+3,X
    sbc ParameterMiddle
    bcc FindRun
    lda ParameterLow
    sbc Runs1440,X
    sta Work0
    lda ParameterMiddle
    sbc Runs1440+1,X
    sta Work1
    lda Cylinders1440,X
    tax

    ; An offset of 128 or more is past the run's first seven cylinders (126 blocks), so the count need not go
    ; negative.
    lda Work0
    bpl CountCylinders
    sec
    sbc #7 * MFM_1440_SECTORS
    tay
    txa
    clc
    adc #7
    tax
    tya
CountCylinders:
    cmp #MFM_1440_SECTORS
    bcc Found
NextCylinder:
    sec
    sbc #MFM_1440_SECTORS
    bmi Back
    inx
    bra NextCylinder
Back:
    clc
    adc #MFM_1440_SECTORS
Found:
    sta Sector
    stx Cylinder

    ; The track is the cylinder over 2; an odd cylinder is the second side.
    txa
    lsr a
    sta Track
    lda #0
    bcc SetSide
    lda #SIDE_SECOND
SetSide:
    sta Side
    lda #MFM_1440_SECTORS
    clc
    rts
.endproc

;; <Mfm1440>'s first block of each run of 10 cylinders, then the disk's end, and $FFFF to stop the search.
Runs1440:
.repeat 17, I
    .word I * 10 * MFM_1440_SECTORS
.endrepeat
    .word $FFFF

;; <Mfm1440>'s first cylinder of each run, by the same index as <Runs1440>.
Cylinders1440:
.repeat 16, I
    .word I * 10
.endrepeat
    .word $FFFF

;; <Locate> for a 720K MFM disk: 9 sectors a side, a cylinder's sides in turn.
;; Out: as <Locate>, carry = clear; <Work0> and Work1 = the block's offset in its run of 10 cylinders
.proc Mfm720

    ; The run of 10 cylinders (90 blocks) the block is in: the last whose start is not past it.
    ldx #$FE
FindRun:
    inx
    inx
    lda Runs720+2,X
    cmp ParameterLow
    lda Runs720+3,X
    sbc ParameterMiddle
    bcc FindRun
    lda ParameterLow
    sbc Runs720,X
    sta Work0
    lda ParameterMiddle
    sbc Runs720+1,X
    sta Work1
    lda Cylinders720,X
    tax
    lda Work0
    cmp #MFM_720_SECTORS
    bcc Found
NextCylinder:
    sec
    sbc #MFM_720_SECTORS
    bmi Back
    inx
    bra NextCylinder
Back:
    clc
    adc #MFM_720_SECTORS
Found:
    sta Sector
    stx Cylinder

    ; The track is the cylinder over 2; an odd cylinder is the second side.
    txa
    lsr a
    sta Track
    lda #0
    bcc SetSide
    lda #SIDE_SECOND
SetSide:
    sta Side
    lda #MFM_720_SECTORS
    clc
    rts
.endproc

;; <Mfm720>'s first block of each run of 10 cylinders, then the disk's end, and $FFFF to stop the search.
Runs720:
.repeat 17, I
    .word I * 10 * MFM_720_SECTORS
.endrepeat
    .word $FFFF

;; <Mfm720>'s first cylinder of each run, by the same index as <Runs720>.
Cylinders720:
.repeat 16, I
    .word I * 10
.endrepeat
    .word $FFFF

;; Finishes <Gcr800>: the cylinder, side and sector from the group's start and the block's place in the group,
;; going on to the next cylinder where the sector is past the zone's last.
;; In: A = the group's start (its first sector in bits 0-4), Y = the zone (bits 5-7) and the block's place in the
;;   group, Cylinder = the group's first cylinder
;; Out: as <Locate>, carry = clear
.proc FinishGcr800

    ; The sector: the group's first plus the block's offset.
    and #$1F
    clc
    sta Sector
    lda GroupOffsets,Y
    and #$1F
    adc Sector
    tax

    ; The cylinder: the group's first plus the block's offset (bits 5-7).
    lda GroupOffsets,Y
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc Cylinder
    sta Cylinder

    ; The zone is the cylinder over 32; a sector past the zone's last is on the next cylinder.
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    txa
    cmp ZoneSectors,Y
    bcc Found
    sbc ZoneSectors,Y
    inc Cylinder
Found:
    sta Sector

    ; The track is the cylinder over 2; an odd cylinder is the second side.
    lda Cylinder
    lsr a
    sta Track
    lda #0
    bcc SetSide
    lda #SIDE_SECOND
SetSide:
    sta Side
    lda ZoneSectors,Y
    clc
    rts
.endproc

;; Finishes <Gcr400>, as <FinishGcr800> does <Gcr800>, for a disk with one side: its cylinders are the even ones, and
;; it is always side 0.
;; In: A = the group's start (its first sector in bits 0-4), Y = the zone (bits 5-7) and the block's place in the
;;   group, Cylinder = the group's first cylinder
;; Out: as <Locate>, carry = clear
.proc FinishGcr400

    ; The sector: the group's first plus the block's offset.
    and #$1F
    clc
    sta Sector
    lda GroupOffsets,Y
    and #$1F
    adc Sector
    tax

    ; The cylinder: the group's first plus twice the block's track offset (bits 5-7).
    lda GroupOffsets,Y
    lsr a
    lsr a
    lsr a
    lsr a
    and #$0E
    clc
    adc Cylinder
    sta Cylinder

    ; The zone is the cylinder over 32; a sector past the zone's last is on the next track.
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    txa
    cmp ZoneSectors,Y
    bcc Found
    sbc ZoneSectors,Y
    inc Cylinder
    inc Cylinder
Found:
    sta Sector
    lda Cylinder
    lsr a
    sta Track
    stz Side
    lda ZoneSectors,Y
    clc
    rts
.endproc

;; The offset of each block in a group: the track (bits 5-7) and sector (bits 0-4) past the group's first, by zone,
;; 32 entries a zone. The bytes after the fifth zone's are not read here.
GroupOffsets:
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

;; The GCR sectors in each track of each 16-track zone: 12, 11, 10, 9 and 8.
ZoneSectors:
    .byte 12, 11, 10, 9, 8

.endscope
