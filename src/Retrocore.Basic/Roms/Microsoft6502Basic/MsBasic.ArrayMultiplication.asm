; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: ARRAY MULTIPLICATION
;
; These unsigned 16-bit helpers multiply dimension sizes and element offsets. Overflow branches to the array code's
; OUT OF MEMORY jump.

.scope Variables continued

;; Multiplies <LinearIndex> by a big-endian two-byte dimension in an array descriptor.
;;
;; The 16 shifts consume <LinearIndex>; it is zero on successful return. <Pointer1> saves the original Y.
;; In: SourceStart = descriptor address, Y = offset of the dimension's low byte, LinearIndex = multiplicand
;; Out: X = low product byte, A = high product byte, Y = high product byte
;; Errors: OUT OF MEMORY on 16-bit overflow
;; Uses: Addend, DigitCount, LinearIndex, Pointer1
;; Also: UMULT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc MultiplyByBound
    sty Pointer1
    lda (SourceStart),y
    sta Addend
    dey
    lda (SourceStart),y
; Falls into MultiplyUnsigned.
.endproc

;; Multiplies <LinearIndex> by A:<Addend>, with A holding the high byte.
;;
;; This entry likewise consumes <LinearIndex>, leaving it zero on successful return.
;; In: A = high multiplier byte, Addend = low multiplier byte, LinearIndex = multiplicand
;; Out: X = low product byte, A = high product byte, Y = high product byte
;; Errors: OUT OF MEMORY on 16-bit overflow
;; Uses: Addend, DigitCount, LinearIndex
;; Also: UMULTD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc MultiplyUnsigned
    sta Addend+1
    lda #$10
    sta DigitCount
    ldx #$00
    ldy #$00

;; Doubles the partial product in X/Y and adds the multiplier when the bit shifted out of <LinearIndex> is set.
;; Also: UMULTC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextBit:
    ; Shift the partial product and add the multiplier for each set bit of LinearIndex.
    txa
    asl a
    tax
    tya
    rol a
    tay
    bcs ElementAddress::ToOutOfMemoryError
    asl LinearIndex
    rol LinearIndex+1
    bcc CountBit
    clc
    txa
    adc Addend
    tax
    tya
    adc Addend+1
    tay
    bcs ElementAddress::ToOutOfMemoryError

;; Counts down <DigitCount>, once for each of the 16 bits, and loops to <NextBit>.
;; Also: UMLCNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CountBit:
    dec DigitCount
    bne NextBit

;; The routine's RTS; nothing branches here, and the label is kept for its old name.
;; Also: UMLRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
.endproc
.endscope

