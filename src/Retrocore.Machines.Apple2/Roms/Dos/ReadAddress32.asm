;; DOS 3.2 RWTS: READ AN ADDRESS FIELD
;;
;; RDADR13 reads the next address field that passes the head: the volume, track and sector that say where the
;; head is and which sector comes next. RWTS reads address fields until it finds the sector it wants, then
;; calls READ13 or WRITE13 for the data field behind it. Runs at $B965-$B9C0 where DOS runs. docs/DiskII.md
;; explains the address field and its 4-and-4 encoding.

;; Reads the next address field into CSSTV: checksum, sector, track and volume.
;;
;; It looks for the prologue D5 AA B5, reads the four 4-and-4 bytes, checks that they exclusive-or to zero, and
;; checks the epilogue's DE AA. It gives up after about 1,800 nibbles without finding a D5, nearly four
;; sectors' worth of track: COUNT and Y count up from $F8F8. Once D5 AA has been seen, Y holds 3, so a wrong
;; third nibble restarts the low byte of the count.
;;
;; Each byte is two nibbles, `1 b7 1 b5 1 b3 1 b1` then `1 b6 1 b4 1 b2 1 b0`. ROL of the first, with the carry
;; set, gives `b7 1 b5 1 b3 1 b1 1`, and ANDing the second leaves the byte. The carry is set the first time by
;; the CMP that matched the B5, and after that by each ROL, which shifts out the nibble's top bit, always 1.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry clear, CSSTV = the checksum, CSSTV+1 = the sector, CSSTV+2 = the track, CSSTV+3 = the volume,
;;   A = $AA, Y = 0
;; Errors: carry set if no address field is found, or its checksum or epilogue is wrong
;; Uses:  A, Y, COUNT, LAST, CSUM
;; Keeps: X
RDADR13:
    ldy #$F8
    sty COUNT
RDASYN:
    iny
    bne RDA1
    inc COUNT
    beq RDERR                       ; the count ran out
RDA1:
    lda Q6L,x
    bpl RDA1
RDASN1:
    cmp #$D5
    bne RDASYN
    nop                             ; timing: too soon, the next read would see the D5 again
RDA2:
    lda Q6L,x
    bpl RDA2
    cmp #$AA
    bne RDASN1                      ; not D5 AA, but this nibble may be a D5
    ldy #$3                         ; four bytes, stored from CSSTV+3 down
RDA3:
    lda Q6L,x
    bpl RDA3
    cmp #$B5
    bne RDASN1
    lda #$0                         ; the checksum so far
RDAFLD:
    sta CSUM
RDA4:
    lda Q6L,x
    bpl RDA4
    rol a                           ; the odd bits, in place, with 1s between them
    sta LAST
RDA5:
    lda Q6L,x
    bpl RDA5
    and LAST                        ; and the even bits: the byte
    sta CSSTV,y
    eor CSUM
    dey
    bpl RDAFLD
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne RDERR

; The epilogue: DE AA. The EB that ends it is not checked.
RDA6:
    lda Q6L,x
    bpl RDA6
    cmp #$DE
    bne RDERR
    nop                             ; timing, as after the D5
RDA7:
    lda Q6L,x
    bpl RDA7
    cmp #$AA
    bne RDERR

;; The success exit of RDADR13 and READ13: returns with the carry clear.
;; Out:   carry = clear
RDEXIT:
    clc
    rts
