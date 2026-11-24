; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: splitting a sector into the values written on the disk
;;
;; The first step of writing a sector. DOS 3.3's 6-and-2 encoding writes each byte as six bits in one nibble and two
;; bits shared with two other bytes in another, so before writing, RWTS splits the 256 bytes of the caller's buffer
;; into 342 six-bit values: 256 in <DiskII::HighBits> and 86 in <DiskII::LowBits>. DOS 3.2's 5-and-3 encoding
;; splits them into 410 five-bit values instead: 256 in HighBits and 154 in LowBits. <DiskII::WriteDataField>
;; (WriteSector.asm) then turns them into nibbles, and <DiskII::PostNibble> (PostNibble.asm) undoes this after a
;; read. At $B800 where DOS runs. RWTS calls it before it starts looking for the sector, because once the sector's
;; address field passes the head there is no time left to do it. docs/DiskII.md explains both encodings and the
;; fields.
;;
;; The two versions' routines differ throughout, so each has its own, chosen by <DOS32>. This is the first piece of
;; the DiskII scope; Software/Boot13.1980.asm includes it too, for DOS 3.2.

;; The routines that talk to the Disk II controller nibble by nibble, and their tables and buffers: Wozniak and
;; Wigginton's read and write routines, as DOS 3.3 and 3.2 each have them.
;;
;; <DiskII::PreNibble> splits a sector into six-bit values (five-bit in DOS 3.2) and <DiskII::PostNibble> rebuilds
;; it; <DiskII::WriteDataField> and <DiskII::ReadDataField> write and read a data field, and
;; <DiskII::ReadAddressField> reads an address field, sharing the exits <DiskII::Fail> and <DiskII::Succeed>;
;; <DiskII::MoveHead> steps the head and <DiskII::Wait> times it. Their timing is counted to the cycle: RwtsEquates.asm
;; says why, and docs/DiskII.md explains nibbles, the fields and the controller's switches.
.scope DiskII

; The nibbles that mark the fields of a sector on the disk. Both kinds of field start D5 AA, a pair that never occurs
; inside one; the third nibble says which kind it is. docs/DiskII.md explains the fields.

;; The first nibble of every field's prologue, D5, which no data nibble is.
PROLOGUE_FIRST = $D5

;; The second nibble of every field's prologue, AA.
PROLOGUE_SECOND = $AA

.if DOS32
;; The third nibble of an address field's prologue, B5 in DOS 3.2: the mark that says an address field follows.
ADDRESS_MARK = $B5
.else
;; The third nibble of an address field's prologue, 96: the mark that says an address field follows.
ADDRESS_MARK = $96
.endif

;; The third nibble of a data field's prologue, AD: the mark that says a data field follows.
DATA_MARK = $AD

;; The first nibble of every field's epilogue, DE.
EPILOGUE_FIRST = $DE

;; The second nibble of every field's epilogue, AA.
EPILOGUE_SECOND = $AA

;; The third nibble of every field's epilogue, EB, which the readers do not check.
EPILOGUE_THIRD = $EB

;; A self-sync nibble, FF, which the write routines follow with 0 bits (two in DOS 3.3, one in DOS 3.2) so that a
;; reader that starts anywhere falls into step.
SELF_SYNC = $FF

;; The bits a 4-and-4 nibble has set between the byte's bits, `1 x 1 x 1 x 1 x`: the address field's first nibble of
;; a pair is the byte shifted right with these set, and its second the byte with these set.
FOUR_AND_FOUR_BITS = $AA

.if DOS32

; The five-bit values.

;; The number of groups of five bytes a sector is split into, 51, and so the length of each run of values in
;; <HighBits> and <LowBits>.
;;
;; 51 groups take 255 bytes; the 256th byte is split on its own, its values last in each buffer.
GROUP_COUNT = 51

;; The number of values in <LowBits>, 154: three runs of <GROUP_COUNT>, one for each of a group's first three
;; bytes, and the last byte's.
LOW_BITS_SIZE = 3 * GROUP_COUNT + 1

;; The five bits of a value written on the disk.
VALUE_MASK = $1F

;; A byte's low three bits, the ones <LowBits> holds.
LOW_BITS_MASK = 7

.else

; The six-bit values.

;; The number of six-bit values in <LowBits>, 86 ($56): each holds the low two bits of three bytes.
LOW_BITS_SIZE = 86

;; The six bits a value has.
VALUE_MASK = $3F

.endif

.if DOS32

;; Splits the 256 bytes at <SectorBuffer> into the five-bit values of <HighBits> and <LowBits>.
;;
;; At $B800 where DOS runs. The bytes go in <GROUP_COUNT> groups of five and one last byte. Each byte's top five
;; bits go to <HighBits>, in five runs of 51 values, one for each place in a group: the group's byte q goes to
;; HighBits + 51 * q + X, where X counts the groups from 50 down to 0. The low three bits go to <LowBits>' three
;; runs of 51: the group's first three bytes' low bits, each with two more bits below them, a bit of the fourth
;; byte and a bit of the fifth, so that each value holds five bits. The last byte's top five bits are HighBits'
;; last value and its low three bits LowBits' last.
;; In: SectorBuffer = the address of the sector's 256 bytes
;; Out: HighBits = 256 values, LowBits = 154 values, each 0 to 31
;; Also: PRENIB16 (DOS33), PRENIBL (DOS31)
.proc PreNibble

;; The low three bits of a group's first byte, with two more bits shifted in below them, while the group is split.
FirstBits = LowResBase

;; The same for the group's second byte.
SecondBits = LowResBaseHigh

;; The same for the group's third byte.
ThirdBits = ScrollBase

    ldx #GROUP_COUNT - 1
    ldy #0
;; One group of five bytes, from the buffer's start up, into place X of each run.
;; Also: PRENIB1 (DOS33), PNIB1 (DOS31)
Split:

    ; The first three bytes: the top five bits to their runs of HighBits, the whole byte kept for its low bits.
    lda (SectorBuffer),y
    sta FirstBits
    lsr a
    lsr a
    lsr a
    sta HighBits,x
    iny
    lda (SectorBuffer),y
    sta SecondBits
    lsr a
    lsr a
    lsr a
    sta HighBits + GROUP_COUNT,x
    iny
    lda (SectorBuffer),y
    sta ThirdBits
    lsr a
    lsr a
    lsr a
    sta HighBits + 2 * GROUP_COUNT,x
    iny

    ; The fourth byte: bits 0, 1 and 2 to the ends of ThirdBits, SecondBits and FirstBits, which then hold four
    ; bits each.
    lda (SectorBuffer),y
    lsr a
    rol ThirdBits
    lsr a
    rol SecondBits
    lsr a
    rol FirstBits
    sta HighBits + 3 * GROUP_COUNT,x
    iny

    ; The fifth byte: bits 0 and 1 to ThirdBits and SecondBits here, and bit 2, left in the carry, to FirstBits
    ; below. Each value keeps its five low bits: the byte's low three, then the two shifted in.
    lda (SectorBuffer),y
    lsr a
    rol ThirdBits
    lsr a
    rol SecondBits
    lsr a
    sta HighBits + 4 * GROUP_COUNT,x
    lda FirstBits
    rol a
    and #VALUE_MASK
    sta LowBits,x
    lda SecondBits
    and #VALUE_MASK
    sta LowBits + GROUP_COUNT,x
    lda ThirdBits
    and #VALUE_MASK
    sta LowBits + 2 * GROUP_COUNT,x
    iny
    dex
    bpl Split

    ; The last byte, Y = 255: its low three bits to LowBits' last value, its top five to HighBits'.
    lda (SectorBuffer),y
    tax
    and #LOW_BITS_MASK
    sta LowBits + 3 * GROUP_COUNT
    txa
    lsr a
    lsr a
    lsr a
    sta HighBits + 5 * GROUP_COUNT
    rts
.endproc

.else

;; Splits the 256 bytes at <SectorBuffer> into <HighBits> (each byte's top six bits) and <LowBits> (the low two
;; bits, three to a value).
;;
;; HighBits + n gets byte n shifted right twice. LowBits + x, for x from 0 to $55, gets the low two bits of bytes
;; $55 - x, $AB - x and $101 - x, in bits 1-0, 3-2 and 5-4, each pair with its two bits swapped; for x = 0 and 1 the
;; last of these is past the end of the buffer, and the pair comes from byte 1 or byte 0 a second time.
;;
;; The first loop takes the bytes from byte 1 downwards (1, 0, $FF, ... 2), rotating each one's low bits into
;; LowBits + X as X counts up from 0 to $55 three times over: 258 passes, so bytes 1 and 0 go round twice. ROL
;; leaves the bits that were in the LowBits entry before above the six it fills, and the second loop clears them.
;; At $B800 where DOS runs.
;; In:    SectorBuffer = the address of the 256 bytes to write
;; Out:   HighBits = 256 six-bit values, LowBits = 86 six-bit values, X = $FF, Y = 0
;; Uses:  A
;; Also: PRENIB16 (DOS33), PRENIBL (DOS31)
.proc PreNibble
.assert MASTER || * = $B800, "PreNibble is at $B800 where DOS runs."
    ldx #0                          ; X: the LowBits index, counting up
    ldy #2                          ; Y: the buffer index, counting down from byte 1

;; Moves the next byte's low two bits into <LowBits> and its top six into <HighBits>.
;; Also: PRENIB1 (DOS33), PNIB1 (DOS31)
Split:
    dey
    lda (SectorBuffer),y
    lsr a                           ; bit 0 into LowBits' entry...
    rol a:LowBits,x
    lsr a                           ; ...then bit 1, so the pair arrives swapped
    rol a:LowBits,x
    sta a:HighBits,y                ; the six bits left
    inx
    cpx #LOW_BITS_SIZE
    bcc Split
    ldx #0                          ; 86 done: back to LowBits' first entry
    tya
    bne Split                       ; stop when the third pass has reached byte 0

    ; Clear the bits above the six in each LowBits value.
    ldx #LOW_BITS_SIZE - 1

;; Clears the top two bits of the next <LowBits> value.
;; Also: PRENIB2 (DOS33)
Mask:
    lda a:LowBits,x
    and #VALUE_MASK
    sta a:LowBits,x
    dex
    bpl Mask
    rts
.endproc

.endif

.endscope
