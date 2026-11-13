; Reading a data field, to verify it. Included by Fmtd1.asm.

;; Reads the next data field and checks its checksum, keeping none of the data.
;;
;; It is the boot ROM's 16-sector read without the stores, so the sector image stays encoded for the next track. The
;; loops are timed for 1 MHz, and their branches must not cross a page.
;; In: X = the slot times 16, the drive in read mode
;; Out: carry = set if no data field was found or it was bad, A = $AA and Y = 0 when it was good
;; Uses: A, Y, IDX
;; Keeps: X
READ16:
    ldy #$20                            ; the nibbles to look through for the marks
RSYNC:
    dey
    beq RDERR
RD1:
    lda Q6L,x
    bpl RD1
RSYNC1:
    eor #$D5
    bne RSYNC
    nop
RD2:
    lda Q6L,x
    bpl RD2
    cmp #$AA
    bne RSYNC1
    ldy #$56
RD3:
    lda Q6L,x
    bpl RD3
    cmp #$AD
    bne RSYNC1
    lda #$00                            ; the checksum
RDATA1:
    dey
    sty IDX
RD4:
    ldy Q6L,x
    bpl RD4
RDNIBL1:
    eor DNIBL,y
    ldy IDX
    bne RDATA1
RDATA2:
    sty IDX
RD5:
    ldy Q6L,x
    bpl RD5
RDNIBL2:
    eor DNIBL,y
    ldy IDX
    iny
    bne RDATA2
RD6:
    ldy Q6L,x
    bpl RD6
RDNIBL3:
    cmp DNIBL,y
    bne RDERR
RD7:
    lda Q6L,x
    bpl RD7
    cmp #$DE
    bne RDERR
    nop
RD8:
    lda Q6L,x
    bpl RD8
    cmp #$AA
    beq RDEXIT
RDERR:
    sec
    rts
RDEXIT:
    clc
    rts
