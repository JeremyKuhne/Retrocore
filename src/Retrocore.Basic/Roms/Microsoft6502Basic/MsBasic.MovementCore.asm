; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the five-byte floating-point movement and rounding routines.
.macro FloatMovement

    .scope Float continued

    ;; Moves the four-byte arithmetic result to <Fac> and normalizes it.
    ;; See: <Float::Normalize>
    ;; Also: MOVFR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc NormalizeResult
    lda Result1
    sta FacMantissa1
    lda Result2
    sta FacMantissa2
    lda Result3
    sta FacMantissa3
    lda Result4
    sta FacMantissa4
    jmp Normalize
    .endproc

    ;; Unpacks a five-byte memory value into <Fac> and clears <FacExtension>.
    ;; In: A = low byte of packed value address, Y = high byte of packed value address
    ;; Out: A = exponent of <Fac>, zero = set when the exponent is zero
    ;; Also: MOVFM (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc LoadFac
    sta Pointer1
    sty Pointer1+1
    ldy #$04
    lda (Pointer1),y
    sta FacMantissa4
    dey
    lda (Pointer1),y
    sta FacMantissa3
    dey
    lda (Pointer1),y
    sta FacMantissa2
    dey
    lda (Pointer1),y
    sta FacSign
    ora #$80
    sta FacMantissa1
    dey
    lda (Pointer1),y
    sta FacExponent
    sty FacExtension
    rts
    .endproc

    ;; Rounds and packs <Fac> into the temporary at <FloatTemporary2>.
    ;; See: <Float::StoreFac>
    ;; Also: MOV2F (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc StoreFacInTemporary2
    ldx #FloatTemporary2
    .byte $2C                       ; BIT absolute skips the following LDX immediate
    ; Falls into StoreFacInTemporary1.
    .endproc

    ;; Rounds and packs <Fac> into the temporary at <FloatTemporary1>.
    ;; See: <Float::StoreFac>
    ;; Also: MOV1F (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc StoreFacInTemporary1
    ldx #FloatTemporary1

;; Sets Y = 0 and branches to <Float::StoreFac>: stores <Fac> at the page-zero address in X.
;; Also: MOVML (M6502, ASTIL)
InPageZero:
    ldy #$00
    beq StoreFac
    .endproc

    ;; Rounds and packs <Fac> into the variable addressed by <AssignedVariable>.
    ;; See: <Float::StoreFac>
    ;; Also: MOVVF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc StoreFacInVariable
    ldx AssignedVariable
    ldy AssignedVariable+1
    .endproc

    ;; Rounds and packs <Fac> into five bytes at Y:X.
    ;; In: X = low byte of destination address, Y = high byte of destination address
    ;; Out: Y = 0, FacExtension = 0
    ;; See: <Float::Round>
    ;; Also: MOVMF (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc StoreFac
    jsr Round
    stx Pointer1
    sty Pointer1+1
    ldy #$04
    lda FacMantissa4
    sta (Pointer1),y
    dey
    lda FacMantissa3
    sta (Pointer1),y
    dey
    lda FacMantissa2
    sta (Pointer1),y
    dey
    lda FacSign
    ora #$7F
    and FacMantissa1                       ; replace the implicit high bit with the sign bit
    sta (Pointer1),y
    dey
    lda FacExponent
    sta (Pointer1),y
    sty FacExtension
    rts
    .endproc

    ;; Copies the unpacked argument accumulator to <Fac>, clearing <FacExtension>.
    ;; Also: MOVFA (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyArgToFac
    lda ArgSign
    .endproc

    ;; Uses A as the <Fac> sign instead of <ArgSign>.
    ;; Also: MOVFA1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyArgToFacWithSign
    sta FacSign
    ldx #$05

;; Copies one byte, from the top down.
;; Also: MOVFAL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Loop:
    lda ArgExponent-1,x
    sta FacExponent-1,x
    dex
    bne Loop
    stx FacExtension
    rts
    .endproc

    ;; Rounds <Fac> and copies it into the argument accumulator.
    ;; See: <Float::Round>
    ;; Also: MOVAF (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyFacToArg
    jsr Round
    .endproc

    ;; Copies <Fac> without first rounding it.
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: MOVEF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyFacToArgUnrounded
    ldx #$06

;; Copies one byte, from the top down.
;; Also: MOVAFL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Loop:
    lda FacExponent-1,x
    sta ArgExponent-1,x
    dex
    bne Loop
    stx FacExtension

;; The shared rts.
;; Also: MOVRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Rounds the <Fac> mantissa upward when bit 7 of <FacExtension> is set.
    ;;
    ;; A carry out of the mantissa shifts it right and increments the exponent. A zero exponent needs no rounding.
    ;; Entry:
    ;;   Increment = <Float::IncrementMantissa>; a mantissa that wrapped to zero goes to <Float::ShiftInCarry>
    ;; See: <Float::IncrementMantissa>, <Float::ShiftInCarry>
    ;; Also: ROUND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Round
    lda FacExponent
    beq CopyFacToArgUnrounded::Done
    asl FacExtension
    bcc CopyFacToArgUnrounded::Done

;; <Float::IncrementMantissa>; a mantissa that wrapped to zero goes to <Float::ShiftInCarry>.
;; Also: INCRND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Increment:
    jsr IncrementMantissa
    bne CopyFacToArgUnrounded::Done
    jmp ShiftInCarry
    .endproc
    .endscope

.endmacro
