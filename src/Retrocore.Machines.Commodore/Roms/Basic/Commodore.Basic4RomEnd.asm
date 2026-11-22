; COMMODORE BASIC 4: CHECKSUM, STATUS-LINK PATCH AND SIGN-ON

;; Emits the $D000 ROM's checksum, GETDS helper, sign-on and reserved patch space.
.macro COMMODORE_BASIC4_ROM_END
;; Checksum-adjustment byte from the BASIC 4 ROM.
CKSUMD:
    .byte $F4

;; Stores A in the I/O status and the disk-status string's backlink high byte, then decrements Y.
;;
;; <GETDS> enters with A=0, clearing the I/O status.
;; In: A = backlink high byte, Y = backlink high-byte offset
DSLINK:
    sta SATUS
    sta (DSDESC+1),y
    dey
    rts

;; BASIC 4 startup banner.
SIGNON:
    .byte "*** COMMODORE BASIC 4.0 ***", CR, CR, 0

; Unused space at the end of the ROM is reserved for patches.
    .res $E000 - *, $AA
    .assert * = $E000, "The BASIC 4 ROM must end at $E000."
.endmacro
