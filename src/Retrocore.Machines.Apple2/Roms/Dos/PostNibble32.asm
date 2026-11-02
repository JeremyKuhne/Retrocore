;; DOS 3.2 RWTS: REBUILD A SECTOR FROM 5-AND-3 VALUES
;;
;; POSTNB13 turns the values READ13 read into NBUF1 and NBUF2 back into the sector's 256 bytes, in the caller's
;; buffer: the reverse of PRENIB13 (PreNibble32.asm). Runs at $B9C1-$BA1D where DOS runs. BOOT 1 has its own copy
;; of this code (BootLoader32.asm), for the values the ROM's reader leaves.

;; Rebuilds the 256 bytes at BUF from NBUF1 and NBUF2.
;;
;; READ13 leaves every value shifted left three places, so an NBUF1 value is a byte's top five bits in place,
;; and an NBUF2 value shifted right three places is the five bits PRENIB13 made: a byte's low three bits, then
;; a bit of the group's fourth byte and a bit of its fifth. GROUP3 and GROUP4 gather those, a bit from each of
;; the group's three NBUF2 values. The groups come in the order PRENIB13 made them, X from 50 down to 0.
;; In:    BUF = the address of the buffer, NBUF1 and NBUF2 from READ13
;; Out:   (BUF) = the 256 bytes
;; Uses:  A, X, Y, GROUP3, GROUP4
POSTNB13:
    ldx #$32
    ldy #0
POST1:
    lda NBUF2,x
    lsr a
    lsr a
    lsr a
    sta GROUP4                      ; bit 0: the fifth byte's bit 2
    lsr a
    sta GROUP3                      ; bit 0: the fourth byte's bit 2
    lsr a
    ora NBUF1,x
    sta (BUF),y
    iny
    lda NBUF2+$33,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol GROUP4
    lsr a
    rol GROUP3
    ora NBUF1+$33,x
    sta (BUF),y
    iny
    lda NBUF2+$66,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol GROUP4
    lsr a
    rol GROUP3
    ora NBUF1+$66,x
    sta (BUF),y
    iny
    lda GROUP3
    and #7
    ora NBUF1+$99,x
    sta (BUF),y
    iny
    lda GROUP4
    and #7
    ora NBUF1+$CC,x
    sta (BUF),y
    iny
    dex
    bpl POST1

; The last byte.
    lda NBUF2+$99
    lsr a
    lsr a
    lsr a
    ora NBUF1+$FF
    sta (BUF),y
    rts
