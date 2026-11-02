;; DOS 3.2 RWTS: SPLIT A SECTOR INTO 5-AND-3 VALUES
;;
;; PRENIB13 prepares a sector for WRITE13: it splits the caller's 256 bytes into the 410 five-bit values that
;; the data field carries, one per nibble. Runs at $B800-$B869 where DOS runs. docs/DiskII.md explains the
;; 5-and-3 encoding; POSTNB13 (PostNibble32.asm) puts the bytes back together after a read.

;; Splits the 256 bytes at BUF into NBUF1 and NBUF2.
;;
;; The bytes go in 51 groups of five and one last byte. Each byte's top five bits go to NBUF1, in five runs of
;; 51 values, one for each place in a group: the group's byte q goes to NBUF1 + 51 * q + X, where X counts the
;; groups from 50 down to 0. The low three bits go to NBUF2's three runs of 51: GROUP0, GROUP1 and GROUP2 take
;; the low bits of the group's first three bytes, then, two places up, a bit of the fourth byte and a bit of the
;; fifth, so that each holds five bits. The last byte's top five bits are NBUF1's last value and its low three
;; bits NBUF2's.
;; In:    BUF = the address of the sector's 256 bytes
;; Out:   NBUF1 = 256 values, NBUF2 = 154 values, each 0 to 31
;; Uses:  A, X, Y, GROUP0, GROUP1, GROUP2
PRENIB13:
    ldx #$32
    ldy #0
PRENIB1:
    lda (BUF),y
    sta GROUP0
    lsr a
    lsr a
    lsr a
    sta NBUF1,x
    iny
    lda (BUF),y
    sta GROUP1
    lsr a
    lsr a
    lsr a
    sta NBUF1+$33,x
    iny
    lda (BUF),y
    sta GROUP2
    lsr a
    lsr a
    lsr a
    sta NBUF1+$66,x
    iny

; The fourth byte: bits 0, 1 and 2 to the ends of GROUP2, GROUP1 and GROUP0, which then hold four bits.
    lda (BUF),y
    lsr a
    rol GROUP2
    lsr a
    rol GROUP1
    lsr a
    rol GROUP0
    sta NBUF1+$99,x
    iny

; The fifth byte: bits 0 and 1 to GROUP2 and GROUP1 here, and bit 2, left in the carry, to GROUP0 below.
    lda (BUF),y
    lsr a
    rol GROUP2
    lsr a
    rol GROUP1
    lsr a
    sta NBUF1+$CC,x
    lda GROUP0
    rol a
    and #$1F                        ; the five bits: the byte's low three, then the two added
    sta NBUF2,x
    lda GROUP1
    and #$1F
    sta NBUF2+$33,x
    lda GROUP2
    and #$1F
    sta NBUF2+$66,x
    iny
    dex
    bpl PRENIB1

; The last byte, Y = 255.
    lda (BUF),y
    tax
    and #7
    sta NBUF2+$99
    txa
    lsr a
    lsr a
    lsr a
    sta NBUF1+$FF
    rts
