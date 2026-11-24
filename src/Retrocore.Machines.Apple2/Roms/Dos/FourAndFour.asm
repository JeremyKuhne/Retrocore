; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: writing 4-and-4 bytes and address field nibbles
;;
;; <DiskII::WriteFourAndFour> writes a byte of an address field as two 4-and-4 nibbles, and
;; <DiskII::WriteFieldNibble> writes a nibble for the address field writer and the formatter. DOS 3.3 keeps them
;; with its address field writer (WriteAddress.asm includes this file), at $BCC4-$BCDE where DOS runs; DOS 3.2 after
;; its formatter (Formatter.asm includes it), at $BFBB-$BFD4. docs/DiskII.md explains the 4-and-4 encoding.
;;
;; As in the data field writer, every store of a nibble must come exactly 32 cycles after the one before. These
;; routines go back to shift mode with `CMP DataLatch,X`, which leaves A alone. The two versions' routines differ
;; only in how they spend the cycles between stores.

.scope DiskII continued

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; From a store in the caller's last call to the first store here, through `LDA zp`, takes 32 cycles. The first
;; nibble is the byte shifted right with every other bit set, through <FormatMask>, the zero-page byte that holds
;; $AA: an `ORA` zero page takes the 3 cycles the timing needs where `ORA #$AA` takes 2. Falls into
;; <WriteFieldNibble> for the even bits.
;; In:    A = the byte, X = slot * 16, FormatMask = $AA, the card in write mode
;; Uses:  A
;; Keeps: X, Y
;; Also: WBYTE (DOS33)
.proc WriteFourAndFour
    pha
    lsr a
    ora FormatMask                  ; 1 b7 1 b5 1 b3 1 b1
    sta LoadLatch,x
    cmp DataLatch,x
    pla
.if DOS32
    cmp ($00,x)                     ; delay: 6 cycles
.else
    nop                             ; delay
    nop
    nop
.endif
    ora #FOUR_AND_FOUR_BITS         ; 1 b6 1 b4 1 b2 1 b0
    ; Falls into WriteFieldNibble.
.endproc

;; Writes the nibble in A after a delay that keeps the stores 32 cycles apart.
;;
;; From the JSR to the store takes 17 cycles here, 15 at <WriteFieldNibble::Shorter> (and 6 at DOS 3.3's
;; <WriteFieldNibble::Now>); the store, the CMP and the RTS take 15 more. A store in one call and the store in the
;; next, with only an `LDA #nibble` between the calls, are 32 cycles apart through Shorter.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: Shorter = 2 cycles less delay
;; Also: WNIBLA (DOS33)
.proc WriteFieldNibble
    nop

;; Writes the nibble 2 cycles sooner.
;; Also: WNIBLB2 (DOS33)
Shorter:
.if DOS32
    pha                             ; delay
    pla
    nop
.else
    nop
    pha                             ; delay
    pla

;; Writes the nibble at once. Nothing calls it.
;; Also: WRNIBL (DOS33)
Now:
.endif
    sta LoadLatch,x                 ; load the nibble
    cmp DataLatch,x                 ; and shift it out
    rts
.endproc

.endscope
