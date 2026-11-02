;; DOS 3.3 RWTS: WRITE AN ADDRESS FIELD (WRITADR)
;;
;; Used only by the formatter (Formatter.asm), which writes each sector of a track as a gap of self-sync
;; nibbles and an address field from WADR16, then a data field from WRITE16 (WriteSector.asm). The address field
;; is the prologue D5 AA 96, the volume, track and sector and their checksum in 4-and-4 nibbles, and the
;; epilogue DE AA EB. Runs at $BC56-$BCDE where DOS runs, after NBUF2, within one page as its timing requires;
;; zeros then fill the page, so RWTS proper starts at $BD00. docs/DiskII.md explains the address field.
;;
;; As in WRITE16, every store of a nibble must come exactly 32 cycles after the one before, or 40 for a
;; 10-bit self-sync nibble; the NOPs and PHA/PLA pairs pad each path to that length. WADR16 goes back to shift
;; mode with CMP Q6L,X, which leaves A alone.

;; Writes Y + 1 self-sync nibbles (257 when Y is 0) and an address field for sector NSECT of track TRK, volume
;; NVOL.
;;
;; The self-sync nibbles are $FF with two 0 bits after each, 40 cycles apart, except the last, which the D5
;; follows after 32. A 4-and-4 byte is written as `(byte >> 1) | $AA`, its odd bits, then `byte | $AA`, its even
;; bits; the ORA with the odd bits uses AA, the zero-page byte that holds $AA, because it takes the 3 cycles
;; the timing needs where `ORA #$AA` takes 2. The code leaves write mode 16 cycles after storing the EB, so only
;; about half of it reaches the disk; RDADR16 checks only the DE AA.
;; In:    X = slot * 16, Y = one less than the self-sync nibbles to write (0 counts as 256), NVOL, TRK, NSECT,
;;   AA = $AA, the drive running, the card in read mode
;; Out:   carry clear, Y = 0, the card back in read mode
;; Errors: carry set if the disk is write-protected; nothing is written
;; Uses:  A, Y
;; Keeps: X
SWADR1:
WADR16:
    sec                             ; the error, in case of write protection
    lda Q6H,x                       ; sense write protect...
    lda Q7L,x                       ; ...in the latch's top bit
    bmi WADRTS
    lda #$FF
    sta Q7H,x                       ; Q6 still on: load mode, and the first self-sync nibble
    cmp Q6L,x                       ; shift mode: writing
    pha                             ; delay
    pla
; One self-sync nibble each pass, 40 cycles; the two calls to an RTS are 12 cycles of delay each.
WSYNC1:
    jsr WADRTS1
    jsr WADRTS1
    sta Q6H,x
    cmp Q6L,x
    nop
    dey
    bne WSYNC1
; The prologue, D5 AA 96.
    lda #$D5
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$96
    jsr WNIBLB2
; The volume, track and sector, then the checksum, written here as WBYTE would, the two EORs taking the 6
; cycles of the JSR.
    lda NVOL
    jsr WBYTE
    lda TRK
    jsr WBYTE
    lda NSECT
    jsr WBYTE
    lda NVOL
    eor TRK
    eor NSECT
    pha
    lsr a
    ora AA                          ; the odd bits
    sta Q6H,x
    lda Q6L,x
    pla
    ora #$AA                        ; the even bits
    jsr WNIBLA
; The epilogue, DE AA EB.
    lda #$DE
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$EB
    jsr WNIBLB2
    clc                             ; success
WADRTS:
    lda Q7L,x                       ; out of write mode
    lda Q6L,x                       ; read mode
WADRTS1:
    rts
;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; From a store in the caller's last call to the first store here, through `LDA zp`, takes 32 cycles.
;; In:    A = the byte, X = slot * 16, AA = $AA, the card in write mode
;; Uses:  A
;; Keeps: X, Y
WBYTE:
    pha
    lsr a
    ora AA                          ; 1 b7 1 b5 1 b3 1 b1
    sta Q6H,x
    cmp Q6L,x
    pla
    nop                             ; delay
    nop
    nop
    ora #$AA                        ; 1 b6 1 b4 1 b2 1 b0
;; Writes the nibble in A after a delay that keeps the stores 32 cycles apart.
;;
;; From the JSR to the STA takes 17 cycles at WNIBLA, 15 at WNIBLB2 and 6 at WRNIBL; the STA, CMP and RTS
;; take 15 more. A store in one call and the store in the next, with only an `LDA #nibble` between the calls,
;; are 32 cycles apart through WNIBLB2.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: WNIBLB2 = 2 cycles less delay, WRNIBL = no delay
WNIBLA:
    nop
WNIBLB2:
    nop
    pha                             ; delay
    pla
WRNIBL:
    sta Q6H,x                       ; load the nibble
    cmp Q6L,x                       ; and shift it out
    rts
EWADR1:
; The end of the relocator's range SWADR1 to EWADR1. Zeros fill the rest of the page.
XP2 = >(*+255)                      ;; the next page's high byte
XP2H = 256*XP2                      ;; the next page's address, $BD00 where DOS runs
.if YEAR = 1983
    .res XP2H-*,0
.else
    ; leftover: what the 1980 master holds here
    .byte $88, $A5, $E8, $91, $A0, $94, $88, $96, $E8, $91, $A0, $94, $88, $96, $91, $91
    .byte $C8, $94, $D0, $96, $91, $91, $C8, $94, $D0, $96, $91, $A3, $C8, $A0, $A5, $85
    .byte $A4
.endif
