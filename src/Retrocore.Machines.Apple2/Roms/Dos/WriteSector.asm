;; DOS 3.3 RWTS: WRITE A DATA FIELD (WRITRTN)
;;
;; Writes a sector's data field from the 342 six-bit values PRENIB16 left in NBUF1 and NBUF2: a few self-sync
;; nibbles, the prologue D5 AA AD, 343 data nibbles (the values exclusive-ored in a chain, then a checksum) and
;; the epilogue DE AA EB. RWTS calls it just after RDADR16 has read the sector's address field, so the data
;; field lands where the old one was; the formatter calls it after each address field it writes. Runs at
;; $B82A-$B8C1 where DOS runs, all within one page, as its timing requires.
;;
;; In write mode the controller shifts the latch out one bit every 4 cycles, so the code must store a new
;; nibble exactly every 32 cycles: a store early or late adds or loses bits on the disk. Every path from one
;; store to the next is counted to 32 cycles (40 for the 10-bit self-sync nibbles), which is why the code holds
;; NOPs, PHA/PLA pairs, a zero-page and an absolute copy of the slot, and why NBUF2 must start a page. The
;; counts below run from one STA Q6H,X to the next. docs/DiskII.md explains the switches and the field.

;; Writes the data field from NBUF1 and NBUF2, starting at once: the head must be just past the sector's
;; address field.
;;
;; Writing a nibble is two switch accesses: storing it to Q6H,X sets load mode and puts it on the data bus,
;; and reading Q6L,X goes back to shift mode, in which the card writes it out bit by bit.
;; In:    X = slot * 16, NBUF1 and NBUF2 = the sector's six-bit values from PRENIB16, the drive running
;; Out:   carry clear, Y = 0, the controller back in read mode
;; Errors: carry set if the disk is write-protected; nothing is written
;; Uses:  A, Y, SLOTZ, SLOTABS, WTEMP
;; Keeps: X
WRITE16:
    sec                             ; the error, in case of write protection
    stx SLOTZ
    stx SLOTABS
    lda Q6H,x                       ; Q6 on, Q7 off: sense write protect...
    lda Q7L,x                       ; ...and read it in the latch's top bit
    bmi WEXIT
    lda a:NBUF2
    sta WTEMP                       ; NBUF2's first value, for a 3-cycle load later
    lda #$FF
; The first self-sync nibble: with Q6 still on, turning Q7 on enters load mode and the STA's $FF is loaded.
; From here on every cycle counts.
    sta Q7H,x
    ora Q6L,x                       ; shift mode: writing
    pha                             ; delay
    pla
    nop
    ldy #4                          ; four more self-sync nibbles
; Each self-sync nibble is $FF followed by two 0 bits: 40 cycles. The fifth is followed by only one, as the
; path from the last to the D5 takes 36 cycles.
WSYNC:
    pha                             ; delay
    pla
    jsr WNIBL7
    dey
    bne WSYNC
; The prologue, D5 AA AD, 32 cycles apart.
    lda #$D5
    jsr WNIBL9
    lda #$AA
    jsr WNIBL9
    lda #$AD
    jsr WNIBL9
; The 86 values of NBUF2, from the last down to the first. Each nibble on the disk is a value exclusive-ored
; with the one written before it (0 before the first), looked up in NIBL. The first comes 36 cycles after
; the AD, which only puts one more 0 bit between them; the loop then takes 32.
    tya                             ; A = 0, the value before the first
    ldy #$56
    bne WDATA1                      ; always
WDATA0:
    lda a:NBUF2,y                   ; the value just written...
WDATA1:
    eor a:NBUF2-1,y                 ; ...against the next: NBUF2 - 1 + Y always crosses a page, taking 5 cycles
    tax
    lda a:NIBL,x
    ldx SLOTZ
    sta Q6H,x
    lda Q6L,x
    dey
    bne WDATA0
; The 256 values of NBUF1, from the first up. The loop is the same length as the one above, 32 cycles: its EOR
; takes one cycle less, and loading the slot from SLOTABS takes one more.
    lda WTEMP                       ; NBUF2's first value, the one just written
    nop                             ; delay
WDATA2:
    eor a:NBUF1,y
    tax
    lda a:NIBL,x
    ldx SLOTABS
    sta Q6H,x
    lda Q6L,x
    lda a:NBUF1,y                   ; the value just written, for the next
    iny
    bne WDATA2
; The checksum nibble: the last value itself, which makes the exclusive-or of all the nibbles' values zero.
    tax
    lda a:NIBL,x
    ldx SLOTZ
    jsr WNIBL
; The epilogue, DE AA EB, then an $FF. Storing the $FF 32 cycles after the EB keeps the card in write mode until
; the EB is fully out; the code leaves write mode 14 cycles after storing the $FF, so only a few of its bits
; reach the disk.
    lda #$DE
    jsr WNIBL9
    lda #$AA
    jsr WNIBL9
    lda #$EB
    jsr WNIBL9
    lda #$FF
    jsr WNIBL9                      ; WNIBL9 also cleared the carry: success
    lda Q7L,x                       ; Q7 off: out of write mode
WEXIT:
    lda Q6L,x                       ; Q6 off: read mode
    rts
;; Writes the nibble in A to the disk, after a delay that keeps the stores 32 cycles apart.
;;
;; From the JSR to the STA takes 15 cycles at WNIBL9, 13 at WNIBL7 and 6 at WNIBL; the STA and ORA take 9 more
;; and the RTS 6. So a store in one call and the store in the next, with only an `LDA #nibble` between the
;; calls, are 32 cycles apart through WNIBL9. Going back to shift mode with ORA rather than LDA leaves A at $FF
;; when it was $FF, so the self-sync loop can store it again without reloading it.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Out:   carry = clear when entered at WNIBL9
;; Uses:  A
;; Keeps: X, Y
;; Entry: WNIBL7 = keeps the carry and takes 2 cycles less, WNIBL = no delay
WNIBL9:
    clc
WNIBL7:
    pha                             ; delay
    pla
WNIBL:
    sta Q6H,x                       ; load the nibble
    ora Q6L,x                       ; and shift it out
    rts
