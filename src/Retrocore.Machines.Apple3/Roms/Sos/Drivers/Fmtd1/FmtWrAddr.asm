; Writing a gap and an address field. Included by Fmtd1.asm.

;; Writes a gap of self-sync nibbles, then an address field for volume NVOL, track TRK and sector NSECT.
;;
;; Each self-sync nibble takes 40 cycles, so that it is ten bits on the disk; the address field's marks, its
;; four-and-four encoded volume, track, sector and checksum, and its end marks follow at 32 cycles a nibble. The
;; timing assumes 1 MHz, and the loop's branch must not cross a page.
;; In: X = the slot times 16, Y = the self-sync nibbles less one (0 for 256), the drive in read mode, at speed
;; Out: carry = set if the disk is write-protected, and nothing is written
;; Uses: A, Y
;; Keeps: X
WADR16:
    sec                                 ; write-protected, unless it isn't
    lda Q6H,x
    lda Q7L,x
    bmi WADRTS
    lda #$FF                            ; a self-sync nibble
    sta Q7H,x
    cmp Q6L,x
    pha
    pla
WSYNC1:
    jsr WADRTS1
    jsr WADRTS1
    sta Q6H,x
    cmp Q6L,x
    nop
    dey
    bne WSYNC1
    lda #$D5                            ; the address field's marks
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$96
    jsr WNIBLB2
    lda NVOL
    jsr WBYTE
    lda TRK
    jsr WBYTE
    lda NSECT
    jsr WBYTE
    lda NVOL
    eor TRK
    eor NSECT                           ; the checksum
    pha
    lsr a
    ora AA
    sta Q6H,x
    lda Q6L,x
    pla
    ora #$AA
    jsr WNIBLA
    lda #$DE                            ; the end marks
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$EB
    jsr WNIBLB2
    clc
WADRTS:
    lda Q7L,x                           ; back to read mode
    lda Q6L,x
WADRTS1:
    rts

;; Writes a byte four-and-four: its odd bits, then its even bits, each with the clock bits set.
;; In: A = the byte, X = the slot times 16, the drive in write mode
;; Uses: A
;; Keeps: X, Y
WBYTE:
    pha
    lsr a
    ora AA
    sta Q6H,x
    cmp Q6L,x
    pla
    nop
    nop
    nop
    ora #$AA

;; Writes a nibble, entered here 17 cycles after the last one; <WNIBLB2> is 15 cycles after.
;; In: A = the nibble, X = the slot times 16, the drive in write mode
;; Keeps: A, X, Y
WNIBLA:
    nop
WNIBLB2:
    nop
    pha
    pla
WRNIBL:
    sta Q6H,x
    cmp Q6L,x
    rts
