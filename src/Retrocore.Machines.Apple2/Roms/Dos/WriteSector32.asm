;; DOS 3.2 RWTS: WRITE A DATA FIELD
;;
;; WRITE13 writes the data field of the sector whose address field has just passed the head: self-sync bytes,
;; the prologue D5 AA AD, the 410 nibbles PRENIB13 prepared, a checksum nibble and the epilogue DE AA EB. Runs
;; at $B86A-$B8FC where DOS runs. docs/DiskII.md explains the data field and writing.

;; Writes NBUF2 and NBUF1 as a data field, in the 32-cycle rhythm the drive needs.
;;
;; Each value goes out exclusive-ored with the one before it, through NIBL, which turns a five-bit value into
;; a nibble; the last value written is the checksum. NBUF2 goes first, from its last value down to its first,
;; then NBUF1 from its first value up. Between the stores to Q6H the loops take exactly 32 cycles, counting
;; SLOTZ's 3-cycle load in one loop and SLOTABS's 4-cycle load in the other. The ten self-sync bytes before the
;; prologue are $FF stored every 36 cycles, which writes a ninth bit, a 0, after each: the sync pattern of
;; 13-sector disks.
;; In:    X = slot * 16, NBUF1 and NBUF2 from PRENIB13, the drive running, the card in read mode
;; Out:   carry = clear, with the card back in read mode
;; Errors: carry set if the disk is write-protected; nothing is written
;; Uses:  A, Y, WTEMP, SLOTZ, SLOTABS
;; Keeps: X
WRITE13:
    sec                             ; the result if the disk is protected
    lda Q6H,x
    lda Q7L,x                       ; sense write protect: bit 7 set if protected
    bmi WEXIT
    stx SLOTZ
    stx SLOTABS
    lda NBUF2
    sta WTEMP                       ; for a 3-cycle load where the loops change over
    lda #$FF
    sta Q7H,x                       ; write mode, $FF in the latch
    ora Q6L,x
    pha
    pla
    nop
    ldy #$0A
WSYNC:
    ora WTEMP                       ; A stays $FF; a 3-cycle delay
    jsr WNIBL7
    dey
    bne WSYNC
    lda #$D5
    jsr WNIBL9
    lda #$AA
    jsr WNIBL9
    lda #$AD
    jsr WNIBL9

; NBUF2, from its 154th value down. A is 0, the value before the first.
    tya
    ldy #$9A
    bne WDATA1                      ; always
WDATA0:
    lda NBUF2,y
WDATA1:
    eor NBUF2-1,y
    tax
    lda NIBL,x
    ldx SLOTZ
    sta Q6H,x
    lda Q6L,x
    dey
    bne WDATA0

; NBUF1, from its first value up. A is NBUF2's first value, WTEMP's copy.
    lda WTEMP
    nop
WDATA2:
    eor NBUF1,y
    tax
    lda NIBL,x
    ldx SLOTABS
    sta Q6H,x
    lda Q6L,x
    lda NBUF1,y
    iny
    bne WDATA2

; The checksum, NBUF1's last value, then the epilogue.
    tax
    lda NIBL,x
    ldx SLOTZ
    jsr WNIBL
    lda #$DE
    jsr WNIBL9
    lda #$AA
    jsr WNIBL9
    lda #$EB
    jsr WNIBL9
    lda Q7L,x                       ; back to read mode
WEXIT:
    lda Q6L,x
    rts

;; Writes the nibble in A, the store 32 cycles after the store before it when the caller's code between the
;; two calls is an `LDA #nibble` and a JSR to WNIBL9.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Out:   carry = clear at WNIBL9
;; Keeps: X, Y
;; Entry: WNIBL7 = 2 cycles less delay, keeping the carry; WNIBL = no delay
WNIBL9:
    clc
WNIBL7:
    pha
    pla
WNIBL:
    sta Q6H,x
    ora Q6L,x
    rts
