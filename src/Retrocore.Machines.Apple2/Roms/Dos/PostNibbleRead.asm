;; DOS 3.3 RWTS: READ A DATA FIELD AND REBUILD THE SECTOR (POSTNRD)
;;
;; The two halves of reading a sector's data. READ16 reads a data field into NBUF1 and NBUF2 as 342 six-bit
;; values and checks its checksum and epilogue; POSTNB16 then puts each byte's six high bits and two low bits
;; back together in the caller's buffer, undoing PRENIB16 (PreNibble.asm). RWTS calls READ16 right after
;; RDADR16 (ReadAddressSeek.asm) has found the sector's address field. Runs at $B8C2-$B943 where DOS runs.
;; READ16's error exit, RDERR, also serves RDADR16, and its success exit, RDEXIT, is RDADR16's.
;; docs/DiskII.md explains the 6-and-2 encoding and the data field.

;; Rebuilds T0 bytes at BUF (256 when T0 is 0) from the six-bit values READ16 left in NBUF1 and NBUF2.
;;
;; Byte n is NBUF1 + n shifted left twice, with the low two bits from NBUF2 + $55 - (n mod $56). Each byte
;; shifts two bits out of the bottom of its NBUF2 entry, low bit first, so the pair PRENIB16 stored swapped
;; comes back in order; three bytes take their bits from each entry in turn, and NBUF2 is left shifted away.
;; In:    BUF = the buffer, T0 = the number of bytes (0 = 256), NBUF1 and NBUF2 = the values from READ16
;; Out:   the bytes at BUF, Y = T0
;; Uses:  A, X, NBUF2
POSTNB16:
    ldy #0                          ; Y: the byte, counting up
POST1:
    ldx #$56                        ; X: the NBUF2 entry, counting down from $55 and starting again
POST2:
    dex
    bmi POST1
    lda a:NBUF1,y                   ; the top six bits, 00abcdef
    lsr a:NBUF2,x                   ; and the two low bits, shifted in after them
    rol a
    lsr a:NBUF2,x
    rol a
    sta (BUF),y
    iny
    cpy T0
    bne POST2
    rts
;; Reads the data field that follows the address field just read into NBUF1 and NBUF2, as six-bit values.
;;
;; It looks for the prologue D5 AA AD in the next 31 nibbles or so, then reads 86 nibbles into NBUF2, from the
;; last entry down, 256 into NBUF1, from the first up, and the checksum nibble. Each nibble becomes six bits
;; through DNIBL; since each was written exclusive-ored with the value before it, A, exclusive-ored with each
;; in turn, runs through the values themselves, and the checksum nibble must match the last. Then the
;; epilogue's first two nibbles, DE AA, must follow.
;;
;; The card holds a finished nibble in its latch only long enough for a 7-cycle loop to see it, so each
;; `LDA Q6L,X / BPL` wait loop must take 7 cycles: none of their branches may cross a page, which would add a
;; cycle. Between nibbles the code has 32 cycles; each data loop takes 20 of them besides the wait. It reads the
;; latch into Y rather than A, to index DNIBL with the nibble directly, and keeps its own index in IDX. After
;; seeing a nibble, the code lets a few cycles pass before reading the latch again, or it could see the same
;; nibble twice: hence the NOPs.
;;
;; Once D5 AA has been seen, Y holds $56, so a third nibble that is not AD restarts the search count from $56.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry clear, NBUF1 and NBUF2 = the sector's six-bit values, A = $AA, Y = 0
;; Errors: carry set if the prologue is not found, the checksum is wrong or the epilogue is missing
;; Uses:  A, Y, IDX
;; Keeps: X
READ16:
    ldy #$20                        ; how many nibbles to look through for the prologue
RSYNC:
    dey
    beq RDERR
READ1:
    lda Q6L,x
    bpl READ1
RSYNC1:
    eor #$D5
    bne RSYNC
    nop                             ; timing: too soon, the next read would see the D5 again
READ2:
    lda Q6L,x
    bpl READ2
    cmp #$AA
    bne RSYNC1                      ; not D5 AA, but this nibble may be a D5
    ldy #$56                        ; NBUF2's size, and the same delay as the NOP
READ3:
    lda Q6L,x
    bpl READ3
    cmp #$AD
    bne RSYNC1
; The 86 values of NBUF2, into NBUF2 + $55 down to NBUF2 + 0.
    lda #$00                        ; the value before the first
RDATA1:
    dey
    sty IDX
READ4:
    ldy Q6L,x
    bpl READ4
    eor a:DNIBL,y                   ; DNIBL starts a page, so this never crosses one
    ldy IDX
    sta a:NBUF2,y
    bne RDATA1                      ; LDY IDX set Z: until entry 0 is stored
; The 256 values of NBUF1, from NBUF1 + 0 up, Y being 0.
RDATA2:
    sty IDX
READ5:
    ldy Q6L,x
    bpl READ5
    eor a:DNIBL,y
    ldy IDX
    sta a:NBUF1,y
    iny
    bne RDATA2
; The checksum nibble decodes to the last value read.
READ6:
    ldy Q6L,x
    bpl READ6
    cmp a:DNIBL,y
    bne RDERR
; The epilogue: DE AA. The EB that ends it is not checked.
READ7:
    lda Q6L,x
    bpl READ7
    cmp #$DE
    bne RDERR
    nop                             ; timing, as after the D5
READ8:
    lda Q6L,x
    bpl READ8
    cmp #$AA
    beq RDEXIT
;; The error exit of READ16 and RDADR16: returns with the carry set.
;; Out:   carry = set
RDERR:
    sec
    rts
