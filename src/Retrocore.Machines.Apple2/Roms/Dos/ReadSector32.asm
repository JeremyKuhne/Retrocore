;; DOS 3.2 RWTS: READ A DATA FIELD
;;
;; READ13 reads the data field of the sector whose address field has just passed the head, into NBUF2 and
;; NBUF1, for POSTNB13 to turn back into bytes. Runs at $B8FD-$B964 where DOS runs. docs/DiskII.md explains the
;; data field and reading.

;; Reads a data field's 410 nibbles into NBUF2 and NBUF1 and checks its checksum and epilogue.
;;
;; It looks for the prologue D5 AA AD within 32 nibbles. Each nibble goes through DNIBL, which gives its
;; five-bit value shifted left three places, and exclusive-oring that with the value before undoes WRITE13's
;; chaining. NBUF2 fills from its 154th value down, then NBUF1 from its first up, as WRITE13 wrote them. The
;; checksum nibble must bring the chain to its own value, and the epilogue must start DE AA. Each wait loop on
;; Q6L takes 7 cycles and the work after it the rest of the 32 a nibble lasts.
;; In:    X = slot * 16, the card in read mode, just after an address field
;; Out:   NBUF2/NBUF1 = the values, shifted left three places, carry = clear
;; Errors: carry set if the field isn't found or doesn't check
;; Uses:  A, Y, IDX
;; Keeps: X
READ13:
    ldy #$20                        ; nibbles to find the prologue in
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
    ldy #$9A                        ; NBUF2's length
READ3:
    lda Q6L,x
    bpl READ3
    cmp #$AD
    bne RSYNC1
    lda #$00                        ; the value before the first

; NBUF2, from its last value down. Y holds the nibble, as an index into DNIBL, so IDX holds the place.
RDATA1:
    dey
    sty IDX
READ4:
    ldy Q6L,x
    bpl READ4
    eor DNIBL,y
    ldy IDX
    sta NBUF2,y
    bne RDATA1

; NBUF1, from its first value up.
RDATA2:
    sty IDX
READ5:
    ldy Q6L,x
    bpl READ5
    eor DNIBL,y
    ldy IDX
    sta NBUF1,y
    iny
    bne RDATA2

; The checksum nibble's value must equal the last value read.
READ6:
    ldy Q6L,x
    bpl READ6
    cmp DNIBL,y
    bne RDERR
READ7:
    lda Q6L,x
    bpl READ7
    cmp #$DE
    bne RDERR
    nop
READ8:
    lda Q6L,x
    bpl READ8
    cmp #$AA
    beq RDEXIT

;; The failure exit of READ13 and RDADR13: returns with the carry set.
;; Out:   carry = set
RDERR:
    sec
    rts
