; retrocore: style=strict
;; DOS 3.2 RWTS: the prenibble routine, which splits a sector into 5-and-3 values ($B800-$B869 where DOS runs)
;;
;; The first step of writing a sector. The 5-and-3 encoding writes each byte as five bits in one nibble and three
;; bits shared with other bytes in another, so before writing, RWTS splits the 256 bytes of the caller's buffer
;; into 410 five-bit values: 256 in <DiskII::HighBits> and 154 in <DiskII::LowBits>. <DiskII::WriteDataField>
;; (WriteSector32.asm) then writes them as nibbles, and <DiskII::PostNibble> (PostNibble32.asm) puts the bytes
;; back together after a read. docs/DiskII.md explains the 5-and-3 encoding.
;;
;; This is the first piece of DOS 3.2's DiskII scope; Software/Boot13.1980.asm includes it too.

;; The lowest layer of RWTS: the routines that talk to the Disk II controller nibble by nibble, with their tables
;; and buffers. They split a sector into the values written on the disk and rebuild it after a read, write and read
;; data fields, read address fields, move the head and wait. <DiskII::Fail> and <DiskII::Succeed> are the exits the
;; readers share. docs/DiskII.md explains nibbles, the fields of a sector and the stepper motor.
.scope DiskII

;; The number of groups of five bytes a sector is split into, 51, and so the length of each run of values in
;; <HighBits> and <LowBits>.
;;
;; 51 groups take 255 bytes; the 256th byte is split on its own, its values last in each buffer.
GROUP_COUNT = 51

;; The number of values in <LowBits>, 154: three runs of <GROUP_COUNT>, one for each of a group's first three
;; bytes, and the last byte's.
LOW_BITS_SIZE = 3 * GROUP_COUNT + 1

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
;; Also: PRENIBL (DOS31)
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

;; The five bits of a value written on the disk.
VALUE_MASK = $1F

;; A byte's low three bits, the ones <LowBits> holds.
LOW_BITS_MASK = 7

.endscope
