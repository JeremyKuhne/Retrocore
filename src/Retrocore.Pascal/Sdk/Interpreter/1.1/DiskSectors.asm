; retrocore: style=strict
;; The Disk II driver's sectors: writing and reading data fields, reading address fields, and the nibble tables.
;;
;; A data field holds a sector's 256 bytes as 342 disk bytes, each a 6-bit value written as one of 64 valid disk
;; bytes ($96-$FF): first the bytes' low bit pairs, 86 values of three pairs each (<TwoBitParts>), then the bytes'
;; top six bits (<ScratchBuffer> on a write), then a checksum. Each value goes to the disk exclusive-ored with the
;; one before it.

; The disk bytes that mark the fields.

;; The first byte of an address or data field's prologue.
PROLOGUE_1 = $D5

;; The second byte of a prologue.
PROLOGUE_2 = $AA

;; The third byte of an address field's prologue.
ADDRESS_PROLOGUE_3 = $96

;; The third byte of a data field's prologue.
DATA_PROLOGUE_3 = $AD

;; The first byte of a field's epilogue.
EPILOGUE_1 = $DE

;; The second byte of an epilogue.
EPILOGUE_2 = $AA

;; The third byte of a data field's epilogue.
EPILOGUE_3 = $EB

;; A sync byte, which <WriteSector> writes in 40 cycles rather than 32 so that the controller falls into step on it.
SYNC_BYTE = $FF

; The data field's layout.

;; The bytes of <TwoBitParts>: 86, each holding the low bit pairs of up to three of a sector's bytes.
TWO_BIT_BYTES = $56

;; The top six bits of a byte, which <ScratchBuffer> and the nibble tables keep as a 6-bit value times 4.
HIGH_SIX_BITS = $FC

;; The lowest disk byte that can be a nibble, <ReadNibbles>' first index.
FIRST_NIBBLE = $96

;; Where <ReadSector>'s Y starts, counting up to 0, for 86 values: <TwoBitParts>, and the first two passes over the
;; sector's bytes.
TWO_BIT_PASS_START = $100 - TWO_BIT_BYTES

;; Where <ReadSector>'s Y starts for its third pass, over the last 84 bytes, $AC-$FF.
THIRD_PASS_START = $100 - (SECTOR_SIZE - 2 * TWO_BIT_BYTES)

; Timing and searches.

;; The sync bytes <WriteSector> writes in its loop, after the first.
SYNC_COUNT = 4

;; The bytes of an address field after its prologue: volume, track, sector and checksum.
ADDRESS_FIELD_SIZE = 4

;; Where <ReadAddressField>'s two search counts start, so that it gives up after about 770 disk bytes.
ADDRESS_SEARCH_START = $FC

;; One more than the disk bytes <ReadSector> checks for a data field's prologue's first byte before giving up.
DATA_SEARCH_BYTES = $20

;; One row of <FirstPairs>, <SecondPairs>, <ThirdPairs> and <WriteNibbles>: a 6-bit value's three bit pairs, each put
;; back in order from how <PrenibbleSector> stores it, and the disk byte it is written as.
;; Parameters:
;;   value = the 6-bit value; the rows go in order, and the tables index them by the value times 4
;;   disk = its disk byte
.macro NibbleRow value, disk
    .assert * = FirstPairs + 4 * (value), "FirstPairs' rows are in value order."
    .byte (((value) & 1) << 1) | (((value) >> 1) & 1)
    .byte (((value) & 4) >> 1) | (((value) >> 3) & 1)
    .byte (((value) & 16) >> 3) | (((value) >> 5) & 1)
    .byte disk
.endmacro

;; One entry of <ReadNibbles>: a disk byte that is a nibble, and the value it stands for.
;; Parameters:
;;   disk = the disk byte; the entries go in order, from <FIRST_NIBBLE>
;;   value = its 6-bit value, which the entry holds times 4
.macro ReadNibble disk, value
    .assert * = ReadNibbles + (disk) - FIRST_NIBBLE, "ReadNibbles' entries are in disk byte order."
    .byte (value) * 4
.endmacro

;; One entry of <ReadNibbles> for a disk byte that is not a nibble, which holds the disk byte itself as filler.
;; Parameters:
;;   disk = the disk byte; the entries go in order, from <FIRST_NIBBLE>
.macro NoNibble disk
    .assert * = ReadNibbles + (disk) - FIRST_NIBBLE, "ReadNibbles' entries are in disk byte order."
    .byte disk
.endmacro

;; Writes a sector's data field after its address field: sync bytes, the prologue, the nibbles of <TwoBitParts> and
;; <ScratchBuffer> as <PrenibbleSector> leaves them, the checksum, the epilogue and a last sync byte.
;; In: X = the slot times 16
;; Out: carry = set when the disk is write-protected
;; Keeps: X
;; Also: WRDF (WK11)
.proc WriteSector

;; The slot times 16, for reloading X in 3 cycles. The loop over <ScratchBuffer> reloads it from <WriteSlot> instead,
;; in 4.
Slot = DiskTemp

;; <TwoBitParts>' first byte, the last of its values written: <ScratchBuffer>'s first nibble is exclusive-ored with it.
LastTwoBits = DiskTemp2

    ; Leave with carry set when the disk is write-protected.
    sec
    stx Slot
    stx WriteSlot
    lda DiskLoad,x
    lda DiskReadMode,x
    bmi Done

    ; Switch to writing, starting with a sync byte.
    lda TwoBitParts
    sta LastTwoBits
    lda #SYNC_BYTE
    sta DiskWriteMode,x
    ora DiskLatch,x

    ; More sync bytes, each 40 cycles.
    pha
    pla
    nop
    ldy #SYNC_COUNT

;; Writes the sync bytes, Y of them.
;; Also: AUTOLP (WK11)
WriteSync:
    pha
    pla
    jsr WriteNibble::Sync
    dey
    bne WriteSync

    ; The prologue.
    lda #PROLOGUE_1
    jsr WriteNibble
    lda #PROLOGUE_2
    jsr WriteNibble
    lda #DATA_PROLOGUE_3
    jsr WriteNibble

    ; TwoBitParts, from its last byte down, each exclusive-ored with the one before it.
    tya
    ldy #TWO_BIT_BYTES
    bne FirstTwoBits

;; Writes the next of <TwoBitParts>' nibbles, from its last byte down.
;; Also: WRDAA (WK11)
NextTwoBits:
    lda TwoBitParts,y

;; Writes a <TwoBitParts> nibble exclusive-ored with the one before it.
;; Also: WRDAB (WK11)
FirstTwoBits:
    eor TwoBitParts-1,y
    tax
    lda WriteNibbles,x
    ldx Slot
    sta DiskLoad,x
    lda DiskLatch,x
    dey
    bne NextTwoBits

    ; ScratchBuffer, from its first byte up, each exclusive-ored with the one before it.
    lda LastTwoBits
    nop

;; Writes the next of <ScratchBuffer>'s nibbles, exclusive-ored with the one before it.
;; Also: WRDAC (WK11)
NextSixBits:
    eor ScratchBuffer,y
    tax
    lda WriteNibbles,x
    ldx WriteSlot
    sta DiskLoad,x
    lda DiskLatch,x
    lda ScratchBuffer,y
    iny
    bne NextSixBits

    ; The checksum: the last value, which exclusive-ors every value before it away.
    tax
    lda WriteNibbles,x
    ldx Slot
    jsr WriteNibble::Now

    ; The epilogue, and a last sync byte; WriteNibble's CLC leaves carry clear.
    lda #EPILOGUE_1
    jsr WriteNibble
    lda #EPILOGUE_2
    jsr WriteNibble
    lda #EPILOGUE_3
    jsr WriteNibble
    lda #SYNC_BYTE
    jsr WriteNibble

    ; Back to reading.
    lda DiskReadMode,x

;; Switches the drive back to reading and returns.
;; Also: WRDAD (WK11)
Done:
    lda DiskLatch,x
    rts
.endproc

;; Writes a disk byte, timed for the data field: 32 cycles from its caller's LDA immediate to the next.
;; In: A = the disk byte, X = the slot times 16
;; Out: carry = clear
;; Keeps: X, Y
;; Also: WRCHE1 (WK11)
.proc WriteNibble
    clc

;; <WriteNibble> without its CLC, 2 cycles shorter: with its caller's PHA and PLA, writes the 40-cycle sync bytes.
;; In: A = the disk byte, X = the slot times 16
;; Keeps: X, Y
;; Also: WRCHE2 (WK11)
Sync:
    pha
    pla

;; Stores the disk byte in the write latch at once, when the caller has spent the time already.
;; In: A = the disk byte, X = the slot times 16
;; Keeps: X, Y
;; Also: WRCHE3 (WK11)
Now:
    sta DiskLoad,x
    ora DiskLatch,x
    rts
.endproc

;; Waits for an address field, reads its volume, track, sector and checksum into <AddressVolume>, <AddressTrack>,
;; <AddressSector> and <AddressChecksum>, and checks the checksum and the epilogue.
;; In: X = the slot times 16
;; Out: carry = set when no address field read correctly within about 770 disk bytes
;; Keeps: X
;; Also: READAF (WK11)
.proc ReadAddressField

;; The search's count of disk bytes, its high byte, with Y as its low byte.
;; Also: RETRYC (WK11)
SearchCount = DiskTemp2

;; Each 4-and-4 byte's odd bits, from its first disk byte.
;; Also: HODDB (WK11)
OddBits = DiskTemp2

;; The exclusive-or of the field's bytes so far.
;; Also: HCKSUM (WK11)
Checksum = DiskTemp

    ; Count the search's disk bytes.
    ldy #ADDRESS_SEARCH_START
    sty SearchCount

;; Counts a disk byte of the search, and fails once there have been too many.
;; Also: CHKTRY (WK11)
NextByte:
    iny
    bne ReadByte
    inc SearchCount
    beq Fail

;; Looks for the prologue.
;; Also: WAITA1 (WK11)
ReadByte:
    lda DiskLatch,x
    bpl ReadByte

;; Checks for the prologue's first byte.
;; Also: CHKPB1 (WK11)
CheckFirst:
    cmp #PROLOGUE_1
    bne NextByte
    nop

;; Reads and checks the prologue's second byte.
;; Also: WAITA2 (WK11)
ReadSecond:
    lda DiskLatch,x
    bpl ReadSecond
    cmp #PROLOGUE_2
    bne CheckFirst
    .assert AddressVolume = AddressChecksum + ADDRESS_FIELD_SIZE - 1, "The address field's bytes are stored down."
    ldy #ADDRESS_FIELD_SIZE - 1

;; Reads and checks the address prologue's third byte.
;; Also: WAITA3 (WK11)
ReadThird:
    lda DiskLatch,x
    bpl ReadThird
    cmp #ADDRESS_PROLOGUE_3
    bne CheckFirst

    ; Read the volume, track, sector and checksum, each two disk bytes: the odd bits shifted left, then the even.
    lda #0
NextField:
    sta Checksum

;; Reads a field's first disk byte, its odd bits.
;; Also: WAITA4 (WK11)
ReadOdd:
    lda DiskLatch,x
    bpl ReadOdd
    rol a
    sta OddBits

;; Reads a field's second disk byte, its even bits, and combines them.
;; Also: WAITA5 (WK11)
ReadEven:
    lda DiskLatch,x
    bpl ReadEven
    and OddBits
    sta AddressChecksum,y
    eor Checksum
    dey
    bpl NextField

    ; The exclusive-or of all four must be 0.
    tay
    bne Fail

;; Reads and checks the epilogue's first byte.
;; Also: WAITA6 (WK11)
ReadEpilogue1:
    lda DiskLatch,x
    bpl ReadEpilogue1
    cmp #EPILOGUE_1
    bne Fail
    nop

;; Reads and checks the epilogue's second byte.
;; Also: WAITA7 (WK11)
ReadEpilogue2:
    lda DiskLatch,x
    bpl ReadEpilogue2
    cmp #EPILOGUE_2
    bne Fail
    clc
    rts

;; Returns with carry set: no good address field was found.
;; Also: ERREX (WK11)
Fail:
    sec
    rts
.endproc

;; Watches the drive's data latch for up to 256 reads, to see whether a disk is turning.
;; In: X = the slot times 16
;; Out: zero = clear when the latch changed: a disk is turning
;; Keeps: X
.proc CheckSpinning
    ; Read the latch, wait, and read it again.
    ldy #0
Check:
    lda DiskLatch,x
    jsr Return
    pha
    pla
    cmp DiskLatch,x
    bne Return
    dey
    bne Check

    ; Also called, from the loop, to waste 12 cycles.
Return:
    rts
.endproc

;; Unused: <ReadNibbles>' entries start at disk byte <FIRST_NIBBLE>.
UnusedByte:
    .res 1

;; Each nibble's 6-bit value times 4, indexed by the disk byte from <FIRST_NIBBLE>: <ReadSector> reads it as
;; ReadNibbles-<FIRST_NIBBLE>,X with X = the disk byte. A disk byte that is not a nibble holds itself as filler.
ReadNibbles:
    ReadNibble $96, $00
    ReadNibble $97, $01
    NoNibble $98
    NoNibble $99
    ReadNibble $9A, $02
    ReadNibble $9B, $03
    NoNibble $9C
    ReadNibble $9D, $04
    ReadNibble $9E, $05
    ReadNibble $9F, $06
    NoNibble $A0
    NoNibble $A1
    NoNibble $A2
    NoNibble $A3
    NoNibble $A4
    NoNibble $A5
    ReadNibble $A6, $07
    ReadNibble $A7, $08
    NoNibble $A8
    NoNibble $A9
    NoNibble $AA
    ReadNibble $AB, $09
    ReadNibble $AC, $0A
    ReadNibble $AD, $0B
    ReadNibble $AE, $0C
    ReadNibble $AF, $0D
    NoNibble $B0
    NoNibble $B1
    ReadNibble $B2, $0E
    ReadNibble $B3, $0F
    ReadNibble $B4, $10
    ReadNibble $B5, $11
    ReadNibble $B6, $12
    ReadNibble $B7, $13
    NoNibble $B8
    ReadNibble $B9, $14
    ReadNibble $BA, $15
    ReadNibble $BB, $16
    ReadNibble $BC, $17
    ReadNibble $BD, $18
    ReadNibble $BE, $19
    ReadNibble $BF, $1A
    NoNibble $C0
    NoNibble $C1
    NoNibble $C2
    NoNibble $C3
    NoNibble $C4
    NoNibble $C5
    NoNibble $C6
    NoNibble $C7
    NoNibble $C8
    NoNibble $C9
    NoNibble $CA
    ReadNibble $CB, $1B
    NoNibble $CC
    ReadNibble $CD, $1C
    ReadNibble $CE, $1D
    ReadNibble $CF, $1E
    NoNibble $D0
    NoNibble $D1
    NoNibble $D2
    ReadNibble $D3, $1F
    NoNibble $D4
    NoNibble $D5
    ReadNibble $D6, $20
    ReadNibble $D7, $21
    NoNibble $D8
    ReadNibble $D9, $22
    ReadNibble $DA, $23
    ReadNibble $DB, $24
    ReadNibble $DC, $25
    ReadNibble $DD, $26
    ReadNibble $DE, $27
    ReadNibble $DF, $28
    NoNibble $E0
    NoNibble $E1
    NoNibble $E2
    NoNibble $E3
    NoNibble $E4
    ReadNibble $E5, $29
    ReadNibble $E6, $2A
    ReadNibble $E7, $2B
    NoNibble $E8
    ReadNibble $E9, $2C
    ReadNibble $EA, $2D
    ReadNibble $EB, $2E
    ReadNibble $EC, $2F
    ReadNibble $ED, $30
    ReadNibble $EE, $31
    ReadNibble $EF, $32
    NoNibble $F0
    NoNibble $F1
    ReadNibble $F2, $33
    ReadNibble $F3, $34
    ReadNibble $F4, $35
    ReadNibble $F5, $36
    ReadNibble $F6, $37
    ReadNibble $F7, $38
    NoNibble $F8
    ReadNibble $F9, $39
    ReadNibble $FA, $3A
    ReadNibble $FB, $3B
    ReadNibble $FC, $3C
    ReadNibble $FD, $3D
    ReadNibble $FE, $3E
    ReadNibble $FF, $3F
    .assert * = FirstPairs, "FirstPairs follows ReadNibbles."

;; With X = a 6-bit value times 4: the bit pair it carries for one of a sector's bytes $00-$55, in bits 0-1, put
;; back in order. FirstPairs, <SecondPairs>, <ThirdPairs> and <WriteNibbles> interleave, 4 bytes a value.
FirstPairs:
    NibbleRow $00, $96
    NibbleRow $01, $97
    NibbleRow $02, $9A
    NibbleRow $03, $9B
    NibbleRow $04, $9D
    NibbleRow $05, $9E
    NibbleRow $06, $9F
    NibbleRow $07, $A6
    NibbleRow $08, $A7
    NibbleRow $09, $AB
    NibbleRow $0A, $AC
    NibbleRow $0B, $AD
    NibbleRow $0C, $AE
    NibbleRow $0D, $AF
    NibbleRow $0E, $B2
    NibbleRow $0F, $B3
    NibbleRow $10, $B4
    NibbleRow $11, $B5
    NibbleRow $12, $B6
    NibbleRow $13, $B7
    NibbleRow $14, $B9
    NibbleRow $15, $BA
    NibbleRow $16, $BB
    NibbleRow $17, $BC
    NibbleRow $18, $BD
    NibbleRow $19, $BE
    NibbleRow $1A, $BF
    NibbleRow $1B, $CB
    NibbleRow $1C, $CD
    NibbleRow $1D, $CE
    NibbleRow $1E, $CF
    NibbleRow $1F, $D3
    NibbleRow $20, $D6
    NibbleRow $21, $D7
    NibbleRow $22, $D9
    NibbleRow $23, $DA
    NibbleRow $24, $DB
    NibbleRow $25, $DC
    NibbleRow $26, $DD
    NibbleRow $27, $DE
    NibbleRow $28, $DF
    NibbleRow $29, $E5
    NibbleRow $2A, $E6
    NibbleRow $2B, $E7
    NibbleRow $2C, $E9
    NibbleRow $2D, $EA
    NibbleRow $2E, $EB
    NibbleRow $2F, $EC
    NibbleRow $30, $ED
    NibbleRow $31, $EE
    NibbleRow $32, $EF
    NibbleRow $33, $F2
    NibbleRow $34, $F3
    NibbleRow $35, $F4
    NibbleRow $36, $F5
    NibbleRow $37, $F6
    NibbleRow $38, $F7
    NibbleRow $39, $F9
    NibbleRow $3A, $FA
    NibbleRow $3B, $FB
    NibbleRow $3C, $FC
    NibbleRow $3D, $FD
    NibbleRow $3E, $FE
    NibbleRow $3F, $FF

;; With X = a 6-bit value times 4: the bit pair it carries for one of a sector's bytes $56-$AB.
SecondPairs = FirstPairs + 1

;; With X = a 6-bit value times 4: the bit pair it carries for one of a sector's bytes $AC-$FF.
ThirdPairs = FirstPairs + 2

;; With X = a 6-bit value times 4: the disk byte it is written as.
;; Also: WRXLTT (WK11)
WriteNibbles = FirstPairs + 3

;; <ReadSector>'s exit when it finds no data field's prologue.
;; Out: carry = set
;; Also: RDFNG1 (WK11)
.proc NoDataField
    sec
    rts
.endproc

;; Reads the data field after an address field into the 256 bytes at <SectorPointer>, patching the slot's data latch
;; and the buffer into its own loops, which have no time to index them.
;;
;; A keeps an exclusive-or running through the nibbles: its top six bits decode each byte's top six bits, and its
;; low two bits sum the bit pairs of the <TwoBitParts> values read so far, which decodes them the same way. Each
;; pass over the bytes starts its sum again.
;;
;; In: X = the slot times 16, SectorPointer = the buffer
;; Out: carry = set when no data field's prologue comes within about 30 disk bytes, or the checksum or the
;;     epilogue is bad
;; Keeps: X
;; Also: READDF (WK11)
.proc ReadSector

;; The slot times 16.
Slot = DiskTemp

;; The exclusive-or of the <TwoBitParts> nibbles so far.
Checksum = DiskTemp2

    ; Patch the slot's data latch into the loops.
    stx Slot
    txa
    ora #<DiskLatch
    sta ReadLatch1
    sta ReadLatch2
    sta ReadLatch3
    sta ReadLatch4
    sta ReadLatch5

    ; Patch in the buffer, less Y's start in each pass.
    lda SectorPointer
    ldy SectorPointer+1
    sta ReadBuffer3
    sty ReadBuffer3+1
    sec
    sbc #TWO_BIT_PASS_START - TWO_BIT_BYTES
    bcs SetBuffer2
    dey
    sec
SetBuffer2:
    sta ReadBuffer2
    sty ReadBuffer2+1
    sbc #TWO_BIT_BYTES + 1
    bcs SetBuffer1
    dey
SetBuffer1:
    sta ReadBuffer1
    sty ReadBuffer1+1

    ; Look for the prologue.
    ldy #DATA_SEARCH_BYTES
NextByte:
    dey
    beq NoDataField

;; Reads a disk byte of the search for the data prologue.
;; Also: WAITD1 (WK11)
ReadByte:
    lda DiskLatch,x
    bpl ReadByte
CheckFirst:
    eor #PROLOGUE_1
    bne NextByte
    nop

;; Reads and checks the prologue's second byte.
;; Also: WAITD2 (WK11)
ReadSecond:
    lda DiskLatch,x
    bpl ReadSecond
    cmp #PROLOGUE_2
    bne CheckFirst
    nop

;; Reads and checks the data prologue's third byte.
;; Also: WAITD3 (WK11)
ReadThird:
    lda DiskLatch,x
    bpl ReadThird
    cmp #DATA_PROLOGUE_3
    bne CheckFirst

    ; Read the TwoBitParts nibbles as they are, before they are decoded.
    ldy #TWO_BIT_PASS_START
    lda #0
NextTwoBits:
    sta Checksum

;; Reads a <TwoBitParts> nibble from the slot's data latch, patched into its LDX.
;; Also: WAITD4 (WK11)
ReadTwoBits:
    ldx DiskLatch + MAIN_DISK_SLOT * 16

;; The low byte of the data latch's address in <ReadSector>'s first LDX, which it patches to the slot's data latch.
ReadLatch1 = *-2

    bpl ReadTwoBits
    lda ReadNibbles-FIRST_NIBBLE,x
    sta TwoBitParts-TWO_BIT_PASS_START,y
    eor Checksum
    iny
    bne NextTwoBits

    ; The first pass: bytes $00-$55, with FirstPairs. The loop stores each byte at the top of its next round, so
    ; the last, byte $55, is kept on the stack and stored at the end.
    ldy #TWO_BIT_PASS_START
    bne ReadFirst

;; Stores a byte of the first pass, at an address patched into its STA.
;; Also: IMM1 (WK11)
StoreFirst:
    sta $1000,y

;; The address <ReadSector>'s first pass stores bytes $00-$54 at, patched to <SectorPointer> - (<TWO_BIT_PASS_START> +
;; 1), for Y = $AB-$FF.
ReadBuffer1 = *-2

;; Reads a nibble of the first pass, bytes $00-$55.
;; Also: WAITD5 (WK11)
ReadFirst:
    ldx DiskLatch + MAIN_DISK_SLOT * 16

;; The patched low byte of the data latch's address in <ReadSector>'s first pass.
ReadLatch2 = *-2

    bpl ReadFirst
    eor ReadNibbles-FIRST_NIBBLE,x
    ldx TwoBitParts-TWO_BIT_PASS_START,y
    eor FirstPairs,x
    iny
    bne StoreFirst
    pha

    ; The second pass: bytes $56-$AB, with SecondPairs.
    and #HIGH_SIX_BITS
    ldy #TWO_BIT_PASS_START

;; Reads a nibble of the second pass, bytes $56-$AB.
;; Also: WAITD6 (WK11)
ReadSecondPass:
    ldx DiskLatch + MAIN_DISK_SLOT * 16

;; The patched low byte of the data latch's address in <ReadSector>'s second pass.
ReadLatch3 = *-2

    bpl ReadSecondPass
    eor ReadNibbles-FIRST_NIBBLE,x
    ldx TwoBitParts-TWO_BIT_PASS_START,y
    eor SecondPairs,x
    sta $1000,y

;; The address <ReadSector>'s second pass stores bytes $56-$AB at, patched to <SectorPointer> - (<TWO_BIT_PASS_START> -
;; <TWO_BIT_BYTES>), for Y = $AA-$FF.
ReadBuffer2 = *-2

    iny
    bne ReadSecondPass

;; Reads the third pass's first nibble: bytes $AC-$FF, with <ThirdPairs>.
;; Also: WAITD7 (WK11)
ReadThirdFirst:
    ldx DiskLatch + MAIN_DISK_SLOT * 16

;; The patched low byte of the data latch's address in <ReadSector>'s first read of its third pass.
ReadLatch4 = *-2

    bpl ReadThirdFirst
    and #HIGH_SIX_BITS
    ldy #THIRD_PASS_START
NextThird:
    eor ReadNibbles-FIRST_NIBBLE,x
    ldx TwoBitParts-THIRD_PASS_START,y
    eor ThirdPairs,x
    sta $1000,y

;; The address <ReadSector>'s third pass stores bytes $AC-$FF at, patched to <SectorPointer>.
ReadBuffer3 = *-2

;; Reads a nibble of the third pass, bytes $AC-$FF, and the checksum last.
;; Also: WAITD8 (WK11)
ReadThirdPass:
    ldx DiskLatch + MAIN_DISK_SLOT * 16

;; The patched low byte of the data latch's address in <ReadSector>'s third pass, which reads the checksum last.
ReadLatch5 = *-2

    bpl ReadThirdPass
    iny
    bne NextThird

    ; The checksum must leave the top six bits 0.
    and #HIGH_SIX_BITS
    eor ReadNibbles-FIRST_NIBBLE,x
    ldx Slot
    tay
    bne Bad

;; Reads and checks the epilogue's first byte.
;; Also: WAITD9 (WK11)
ReadEpilogue:
    lda DiskLatch,x
    bpl ReadEpilogue
    cmp #EPILOGUE_1
    beq Good

;; Leaves with carry set when bad (or, entered at <Good>, clear), storing byte $55 either way.
;; Also: RDFNG2 (WK11)
Bad:
    sec
    .byte $24                 ; BIT zero page: skips the next instruction for the code falling in

;; Leaves with carry clear: the sector is good.
;; Also: RDFOK (WK11)
Good:
    clc
    pla
    ldy #TWO_BIT_BYTES - 1
    sta (SectorPointer),y
    rts
.endproc
