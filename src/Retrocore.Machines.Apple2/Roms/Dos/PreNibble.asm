;; DOS 3.3 RWTS: SPLIT A SECTOR INTO SIX-BIT VALUES (PRENIBL)
;;
;; The first step of writing a sector. The 6-and-2 encoding writes each byte as six bits in one nibble and two
;; bits shared with two other bytes in another, so before writing, RWTS splits the 256 bytes of the caller's
;; buffer into 342 six-bit values: 256 in NBUF1 and 86 in NBUF2. WRITE16 (WriteSector.asm) then turns them into
;; nibbles; POSTNB16 (PostNibbleRead.asm) undoes this after a read. Runs at $B800 where DOS runs. RWTS calls it
;; before it starts looking for the sector, because once the sector's address field passes the head there is
;; no time left to do it. docs/DiskII.md explains the encoding.

;; Splits the 256 bytes at BUF into NBUF1 (each byte's top six bits) and NBUF2 (the low two bits, three to a
;; value).
;;
;; NBUF1 + n gets byte n shifted right twice. NBUF2 + x, for x from 0 to $55, gets the low two bits of bytes
;; $55 - x, $AB - x and $101 - x, in bits 1-0, 3-2 and 5-4, each pair with its two bits swapped; for x = 0 and 1
;; the last of these is past the end of the buffer, and the pair comes from byte 1 or byte 0 a second time.
;;
;; The first loop takes the bytes from byte 1 downwards (1, 0, $FF, ... 2), rotating each one's low bits into
;; NBUF2 + X as X counts up from 0 to $55 three times over: 258 passes, so bytes 1 and 0 go round twice. ROL
;; leaves the bits that were in the NBUF2 entry before above the six it fills, and the second loop clears them.
;; In:    BUF = the address of the 256 bytes to write
;; Out:   NBUF1 = 256 six-bit values, NBUF2 = 86 six-bit values
;; Uses:  A, X, Y
PRENIB16:
    ldx #$0                         ; X: the NBUF2 index, counting up
    ldy #2                          ; Y: the buffer index, counting down from byte 1
PRENIB1:
    dey
    lda (BUF),y
    lsr a                           ; bit 0 into NBUF2's entry...
    rol a:NBUF2,x
    lsr a                           ; ...then bit 1, so the pair arrives swapped
    rol a:NBUF2,x
    sta a:NBUF1,y                   ; the six bits left
    inx
    cpx #$56
    bcc PRENIB1
    ldx #0                          ; 86 done: back to NBUF2's first entry
    tya
    bne PRENIB1                     ; stop when the third pass has reached byte 0
    ldx #$55
PRENIB2:
    lda a:NBUF2,x
    and #$3F                        ; keep the six bits just filled
    sta a:NBUF2,x
    dex
    bpl PRENIB2
    rts
