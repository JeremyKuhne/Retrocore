;; THE KEYBOARD INTERRUPT AND THE 6502'S VECTORS ($FFBE-$FFFF)
;;
;; The keyboard interrupt's handler, which VKEYBD points to, the ROM's checksum word, and the 6502's NMI, reset and
;; IRQ vectors.

; The keyboard interrupt's values.

KEY_CONTROL_1 = $9F                 ;; CTRL+1's key code, which stops and restarts the screen's output
KEY_DEBOUNCE = 3                    ;; KEYDEL's count, in vertical blanks, during which the same key is ignored
KEY_REPEAT_DELAY = $30              ;; SRTIMR's count, 48 vertical blanks, before a held key repeats

;; The keyboard interrupt's handler: puts the new key's code in CH for <KEYBOARD_GET>, or toggles SSFLAG for CTRL+1.
;;
;; The same key again before the vertical blank has counted KEYDEL down is a bounce, and ignored. A key other than
;; CTRL+1 ends attract mode. Every key, a bounce included, restarts the auto-repeat delay, which the vertical blank
;; counts. It ends with PLA and RTI, the IRQ handler having pushed A before jumping through VKEYBD.
;; Uses: CH, CH1, KEYDEL, ATRACT, SSFLAG, SRTIMR
;; Keeps: X, Y
;; See: <VKEYBD>, <IRQ_ENTRY>
KEYBOARD_IRQ:
    lda KBCODE
    cmp CH1
    bne KEYBOARD_IRQ_NEW
    lda KEYDEL
    bne KEYBOARD_IRQ_REPEAT         ; a bounce
KEYBOARD_IRQ_NEW:
    lda KBCODE
    cmp #KEY_CONTROL_1
    bne KEYBOARD_IRQ_STORE
    lda SSFLAG
    eor #$FF
    sta SSFLAG
    bcs KEYBOARD_IRQ_REPEAT         ; always: carry is set by the compare
KEYBOARD_IRQ_STORE:
    sta CH
    sta CH1
    lda #KEY_DEBOUNCE
    sta KEYDEL
    lda #$00
    sta ATRACT
KEYBOARD_IRQ_REPEAT:
    lda #KEY_REPEAT_DELAY
    sta SRTIMR
    pla
    rti

    .byte $FF, $FF, $FF, $FF, $FF, $FF ; unused

;; The checksum of the chip at $F000-$FFFF.
;;
;; In rev. A and the PAL OS it is the 16-bit sum of the chip's other bytes, as the pad bytes at $E40F and $E41F hold
;; the $E000-$EFFF chip's (<CHECKSUM_E000>). Rev. B's, $E6F3, is no sum of the chip's bytes; it equals the IRQ vector.
CHECKSUM:
    .assert CHECKSUM = $FFF8, "The checksum is at $FFF8."
.if VERSION = VERSION_A
    .word $57DD
.elseif VERSION = VERSION_PAL
    .word $57D6
.else
    .word $E6F3
.endif

;; The 6502's vectors: NMI, reset and IRQ.
;;
;; Rev. A's reset vector points at COLDSV, rev. B's straight at <COLD_START>.
;; See: <NMI_HANDLER>, <COLD_START>, <IRQ_ENTRY>
CPU_VECTORS:
    .assert CPU_VECTORS = $FFFA, "The 6502's vectors are at $FFFA."
    .word NMI_HANDLER               ; NMI: the display list interrupt, the vertical blank and SYSTEM RESET
.if VERSION = VERSION_B
    .word COLD_START                ; reset: the power-up
.else
    .word COLDSV                    ; reset: the power-up, through COLDSV's JMP
.endif
    .word IRQ_ENTRY                 ; IRQ and BRK
