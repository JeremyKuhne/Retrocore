; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: rebuilding a sector from the values read
;;
;; The second half of reading a sector's data. Once <DiskII::ReadDataField> (ReadData.asm) has read a data field
;; into <DiskII::HighBits> and <DiskII::LowBits>, <DiskII::PostNibble> puts each byte's high and low bits back
;; together in the caller's buffer, undoing <DiskII::PreNibble> (PreNibble.asm). DOS 3.3's rebuilds a byte from six
;; high bits and two low bits; DOS 3.2's from five and three. docs/DiskII.md explains both encodings.
;;
;; The two versions' routines differ throughout, and sit in different places: DOS 3.3's at $B8C2, before the reader
;; (Dos33.asm includes this file before ReadData.asm), and DOS 3.2's at $B9C1, after the address field reader
;; (Dos32.asm and Software/Boot13.1980.asm include it after ReadAddress.asm). `BOOT 1` in DOS 3.2 has its own copy
;; of DOS 3.2's, `Boot::Stage1::PostNibble` (BootLoader.asm), for the values the 13-sector ROM's reader leaves.

; DiskII: the postnibble routine.
.scope DiskII continued

.if DOS32

;; Rebuilds the 256 bytes at <SectorBuffer> from <HighBits> and <LowBits>.
;;
;; At $B9C1 where DOS runs. <ReadDataField> leaves every value shifted left three places, so a <HighBits> value is
;; a byte's top five bits in place, and a <LowBits> value shifted right three places is the five bits <PreNibble>
;; made: a byte's low three bits, then a bit of the group's fourth byte and a bit of its fifth.
;; <PostNibble::FourthBits> and <PostNibble::FifthBits> gather those, a bit from each of the group's three <LowBits>
;; values. The groups come in the order <PreNibble> made them, X from 50 down to 0.
;; In: SectorBuffer = the address of the buffer, <HighBits> and <LowBits> = the values from <ReadDataField>
;; Out: (SectorBuffer) = the 256 bytes
;; Also: POSTNB16 (DOS33), POSTNIB (DOS31)
.proc PostNibble

;; The low bits of a group's fourth byte, gathered from the group's three <LowBits> values.
FourthBits = LowResBase

;; The low bits of a group's fifth byte, gathered likewise.
FifthBits = LowResBaseHigh

    ldx #GROUP_COUNT - 1
    ldy #0
;; One group of five bytes, from place X of each run, into the buffer from its start up.
;; Also: POST1 (DOS33), POSTNB1 (DOS31)
Loop:

    ; The first byte: its low bits from the first run's value, which also holds a bit of the fifth byte and one of
    ; the fourth.
    lda LowBits,x
    lsr a
    lsr a
    lsr a
    sta FifthBits                   ; bit 0: the fifth byte's bit 2
    lsr a
    sta FourthBits                  ; bit 0: the fourth byte's bit 2
    lsr a
    ora HighBits,x
    sta (SectorBuffer),y
    iny

    ; The second and third bytes likewise, from the second and third runs.
    lda LowBits + GROUP_COUNT,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol FifthBits
    lsr a
    rol FourthBits
    ora HighBits + GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    lda LowBits + 2 * GROUP_COUNT,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol FifthBits
    lsr a
    rol FourthBits
    ora HighBits + 2 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny

    ; The fourth and fifth bytes, from the bits gathered.
    lda FourthBits
    and #LOW_BITS_MASK
    ora HighBits + 3 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    lda FifthBits
    and #LOW_BITS_MASK
    ora HighBits + 4 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    dex
    bpl Loop

    ; The last byte.
    lda LowBits + 3 * GROUP_COUNT
    lsr a
    lsr a
    lsr a
    ora HighBits + 5 * GROUP_COUNT
    sta (SectorBuffer),y
    rts
.endproc

.else

;; Rebuilds RebuildCount bytes at SectorBuffer (256 when RebuildCount is 0) from the six-bit values
;; <ReadDataField> left in <HighBits> and <LowBits>.
;;
;; Byte n is HighBits + n shifted left twice, with the low two bits from LowBits + $55 - (n mod $56). Each byte
;; shifts two bits out of the bottom of its LowBits entry, low bit first, so the pair <PreNibble> stored swapped
;; comes back in order; three bytes take their bits from each entry in turn, and LowBits is left shifted away.
;; In:    SectorBuffer = the buffer, RebuildCount = the number of bytes (0 = 256), HighBits = the values from
;;   <ReadDataField>, LowBits = the same
;; Out:   the bytes at SectorBuffer, Y = RebuildCount
;; Uses:  A, X, LowBits
;; Also: POSTNB16 (DOS33), POSTNIB (DOS31)
.proc PostNibble
    ldy #0                          ; Y: the byte, counting up

;; Starts again at the last <LowBits> entry, for the next third of the bytes.
;; Also: POST1 (DOS33), POSTNB1 (DOS31)
Loop:
    ldx #LOW_BITS_SIZE              ; X: the LowBits entry, counting down from $55 and starting again

;; Rebuilds the next byte.
;; Also: POST2 (DOS33)
NextByte:
    dex
    bmi Loop
    lda a:HighBits,y                ; the top six bits, 00abcdef
    lsr a:LowBits,x                 ; and the two low bits, shifted in after them
    rol a
    lsr a:LowBits,x
    rol a
    sta (SectorBuffer),y
    iny
    cpy RebuildCount
    bne NextByte
    rts
.endproc

.endif

.endscope
