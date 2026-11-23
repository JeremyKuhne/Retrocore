; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: ARRAY MULTIPLICATION
;
; These unsigned 16-bit helpers multiply dimension sizes and element offsets. Overflow branches
; to <OMERR1> in the array code.

;; Multiplies <CURTOL> by a big-endian two-byte dimension in an array descriptor.
;;
;; The 16 shifts consume <CURTOL>; it is zero on successful return. <INDEX> saves the original Y.
;; In: LOWTR = descriptor address, Y = offset of the dimension's low byte, CURTOL = multiplicand
;; Out: X = low product byte, A = high product byte, Y = high product byte
;; Errors: OUT OF MEMORY on 16-bit overflow
;; Uses: CURTOL, CURTOL+1, ADDEND, ADDEND+1, DECCNT, INDEX
UMULT:
    sty INDEX
    lda (LOWTR),y
    sta ADDEND
    dey
    lda (LOWTR),y

;; Multiplies <CURTOL> by A:<ADDEND>, with A holding the high byte.
;;
;; This entry likewise consumes <CURTOL>, leaving it zero on successful return.
;; In: A = high multiplier byte, ADDEND = low multiplier byte, CURTOL = multiplicand
;; Out: X = low product byte, A = high product byte, Y = high product byte
;; Errors: OUT OF MEMORY on 16-bit overflow
;; Uses: CURTOL, CURTOL+1, ADDEND+1, DECCNT
UMULTD:
    sta ADDEND+1
    lda #$10
    sta DECCNT
    ldx #$00
    ldy #$00

UMULTC:
    ; Shift the partial product and add the multiplier for each set bit of CURTOL.
    txa
    asl a
    tax
    tya
    rol a
    tay
    bcs OMERR1
    asl CURTOL
    rol CURTOL+1
    bcc UMLCNT
    clc
    txa
    adc ADDEND
    tax
    tya
    adc ADDEND+1
    tay
    bcs OMERR1

UMLCNT:
    dec DECCNT
    bne UMULTC

UMLRTS:
    rts
