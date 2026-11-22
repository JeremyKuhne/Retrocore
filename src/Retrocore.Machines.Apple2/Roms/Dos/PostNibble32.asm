; retrocore: style=strict
;; DOS 3.2 RWTS: the postnibble routine, which rebuilds a sector from 5-and-3 values ($B9C1-$BA1D where DOS runs)
;;
;; <DiskII::PostNibble> turns the values <DiskII::ReadDataField> read into <DiskII::HighBits> and
;; <DiskII::LowBits> back into the sector's 256 bytes, in the caller's buffer: the reverse of
;; <DiskII::PreNibble> (PreNibble32.asm). `BOOT 1` has its own copy of this code, <Boot::Stage1::PostNibble>
;; (BootLoader32.asm), for the values the 13-sector ROM's reader leaves.

; DiskII: the postnibble routine.
.scope DiskII continued

;; Rebuilds the 256 bytes at <SectorBuffer> from <HighBits> and <LowBits>.
;;
;; At $B9C1 where DOS runs. <ReadDataField> leaves every value shifted left three places, so a <HighBits> value is
;; a byte's top five bits in place, and a <LowBits> value shifted right three places is the five bits <PreNibble>
;; made: a byte's low three bits, then a bit of the group's fourth byte and a bit of its fifth.
;; <PostNibble::FourthBits> and <PostNibble::FifthBits> gather those, a bit from each of the group's three <LowBits>
;; values. The groups come in the order <PreNibble> made them, X from 50 down to 0.
;; In: SectorBuffer = the address of the buffer, <HighBits> and LowBits = the values from <ReadDataField>
;; Out: (SectorBuffer) = the 256 bytes
;; Also: POSTNIB (DOS31)
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

.endscope
