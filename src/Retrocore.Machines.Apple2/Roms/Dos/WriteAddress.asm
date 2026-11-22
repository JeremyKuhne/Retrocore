; retrocore: style=strict
;; DOS 3.3 RWTS: writing an address field
;;
;; Used only by the formatter (Formatter.asm), which writes each sector of a track as a gap of self-sync nibbles
;; and an address field from <DiskII::WriteAddressField>, then a data field from <DiskII::WriteDataField>
;; (WriteSector.asm). The address field is the prologue D5 AA 96, the volume, track and sector and their checksum
;; in 4-and-4 nibbles, and the epilogue DE AA EB. At $BC56-$BCDE where DOS runs, after <DiskII::LowBits>, within
;; one page as its timing requires; zeros then fill the page, so that RWTS proper starts at $BD00. docs/DiskII.md
;; explains the address field.
;;
;; As in the data field writer, every store of a nibble must come exactly 32 cycles after the one before, or 40 for
;; a 10-bit self-sync nibble; the NOPs and PHA/PLA pairs pad each path to that length. These routines go back to
;; shift mode with `CMP DataLatch,X`, which leaves A alone.

;; The start of the relocator's range for the address field writer, to <WriteAddressCodeEnd>. See Relocator.asm.
;; Also: SWADR1 (DOS33)
WriteAddressCodeStart:

; DiskII: the address field writer.
.scope DiskII continued

;; The bits a 4-and-4 nibble has set between the byte's bits: `1 x 1 x 1 x 1 x`.
FOUR_AND_FOUR_BITS = $AA

;; Writes Y + 1 self-sync nibbles (257 when Y is 0) and an address field for sector <FormatSector> of track
;; <FormatTrack>, volume <FormatVolume>.
;;
;; The self-sync nibbles are $FF with two 0 bits after each, 40 cycles apart, except the last, which the D5
;; follows after 32. A 4-and-4 byte is written as `(byte >> 1) | $AA`, its odd bits, then `byte | $AA`, its even
;; bits; the ORA with the odd bits uses <FormatMask>, the zero-page byte that holds $AA, because it takes the 3
;; cycles the timing needs where `ORA #$AA` takes 2. The code leaves write mode 16 cycles after storing the EB, so
;; only about half of it reaches the disk; <ReadAddressField> checks only the DE AA.
;; In:    X = slot * 16, Y = one less than the self-sync nibbles to write (0 counts as 256), FormatVolume = the
;;   volume, FormatTrack = the track, FormatSector = the sector, FormatMask = $AA, the drive running, the card in
;;   read mode
;; Out:   carry = clear, Y = 0, the card back in read mode
;; Errors: carry = set if the disk is write-protected; nothing is written
;; Uses:  A
;; Keeps: X
;; Also: WADR16 (DOS33)
.proc WriteAddressField
    sec                             ; the error, in case of write protection
    lda LoadLatch,x                 ; sense write protect...
    lda ReadMode,x                  ; ...in the latch's top bit
    bmi ToReadMode
    lda #SELF_SYNC
    sta WriteMode,x                 ; Q6 still on: load mode, and the first self-sync nibble
    cmp DataLatch,x                 ; shift mode: writing
    pha                             ; delay
    pla

;; Writes the next self-sync nibble, 40 cycles after the one before: the two calls to an RTS are 12 cycles of
;; delay each.
;; Also: WSYNC1 (DOS33)
SyncLoop:
    jsr Return
    jsr Return
    sta LoadLatch,x
    cmp DataLatch,x
    nop
    dey
    bne SyncLoop

    ; The prologue, D5 AA 96.
    lda #PROLOGUE_FIRST
    jsr WriteFieldNibble::Shorter
    lda #PROLOGUE_SECOND
    jsr WriteFieldNibble::Shorter
    lda #ADDRESS_MARK
    jsr WriteFieldNibble::Shorter

    ; The volume, track and sector, then the checksum, written here as WriteFourAndFour would, the two EORs taking
    ; the 6 cycles of the JSR.
    lda FormatVolume
    jsr WriteFourAndFour
    lda FormatTrack
    jsr WriteFourAndFour
    lda FormatSector
    jsr WriteFourAndFour
    lda FormatVolume
    eor FormatTrack
    eor FormatSector
    pha
    lsr a
    ora FormatMask                  ; the odd bits
    sta LoadLatch,x
    lda DataLatch,x
    pla
    ora #FOUR_AND_FOUR_BITS         ; the even bits
    jsr WriteFieldNibble

    ; The epilogue, DE AA EB.
    lda #EPILOGUE_FIRST
    jsr WriteFieldNibble::Shorter
    lda #EPILOGUE_SECOND
    jsr WriteFieldNibble::Shorter
    lda #EPILOGUE_THIRD
    jsr WriteFieldNibble::Shorter
    clc                             ; success

;; Leaves write mode and goes back to read mode; also the exit for a write-protected disk.
;; Also: WADRTS (DOS33)
ToReadMode:
    lda ReadMode,x                  ; out of write mode
    lda DataLatch,x                 ; read mode

;; Returns; a JSR to it is a 12-cycle delay.
;; Also: WADRTS1 (DOS33)
Return:
    rts
.endproc

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; From a store in the caller's last call to the first store here, through `LDA zp`, takes 32 cycles. Falls into
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
    nop                             ; delay
    nop
    nop
    ora #FOUR_AND_FOUR_BITS         ; 1 b6 1 b4 1 b2 1 b0
    ; Falls into WriteFieldNibble.
.endproc

;; Writes the nibble in A after a delay that keeps the stores 32 cycles apart.
;;
;; From the JSR to the store takes 17 cycles here, 15 at <WriteFieldNibble::Shorter> and 6 at
;; <WriteFieldNibble::Now>; the store, the CMP and the RTS
;; take 15 more. A store in one call and the store in the next, with only an `LDA #nibble` between the calls, are
;; 32 cycles apart through Shorter.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: Shorter = 2 cycles less delay, Now = no delay
;; Also: WNIBLA (DOS33)
.proc WriteFieldNibble
    nop

;; Writes the nibble 2 cycles sooner.
;; Also: WNIBLB2 (DOS33)
Shorter:
    nop
    pha                             ; delay
    pla

;; Writes the nibble at once. Nothing calls it.
;; Also: WRNIBL (DOS33)
Now:
    sta LoadLatch,x                 ; load the nibble
    cmp DataLatch,x                 ; and shift it out
    rts
.endproc

.endscope

;; The end of the relocator's range for the address field writer, the byte after it.
;; Also: EWADR1 (DOS33)
WriteAddressCodeEnd:

.if YEAR = 1983
    ; Zeros fill the rest of the page, up to RWTS (Apple's XP2 and XP2H name the next page).
    .res ((* + $FF) & $FF00) - *, 0
.else
    ; Leftover: what the 1980 master holds here.
    .byte $88, $A5, $E8, $91, $A0, $94, $88, $96, $E8, $91, $A0, $94, $88, $96, $91, $91
    .byte $C8, $94, $D0, $96, $91, $91, $C8, $94, $D0, $96, $91, $A3, $C8, $A0, $A5, $85
    .byte $A4
.endif
