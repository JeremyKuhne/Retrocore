; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the natural-logarithm routine before the multiplication routine it enters.
.macro LogarithmRoutine

    .scope Functions continued

    ;; Computes the natural logarithm of <Fac>.
    ;;
    ;; It reduces <Fac> to a fractional range, evaluates a polynomial, adds the binary exponent, and multiplies by
    ;; ln(2).
    ;; Errors: illegal argument = jumps to <IllegalQuantityError> for zero or a negative argument
    ;; See: <Float::LogPolynomial>, <Float::EvaluateOddPolynomial>
    ;; Also: LOG (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Log
    jsr Float::GetSign
    beq ToIllegalQuantity
    bpl Reduce

;; Jumps on to the ILLEGAL QUANTITY error for zero or a negative argument.
;; Also: LOGERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToIllegalQuantity:
    jmp IllegalQuantityError

;; Saves the unbiased exponent and sets <Fac>'s exponent to $80.
;; Also: LOG1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Reduce:
    lda FacExponent
    sbc #$7F                        ; save the binary exponent without its bias
    pha
    lda #$80
    sta FacExponent
    lda #<Float::SquareRootOfHalf
    ldy #>Float::SquareRootOfHalf
    jsr Float::AddPacked
    lda #<Float::SquareRootOfTwo
    ldy #>Float::SquareRootOfTwo
    jsr Float::DividePacked
    lda #<Float::One
    ldy #>Float::One
    jsr Float::SubtractFromPacked
    lda #<Float::LogPolynomial
    ldy #>Float::LogPolynomial
    jsr Float::EvaluateOddPolynomial
    lda #<Float::MinusHalf
    ldy #>Float::MinusHalf
    jsr Float::AddPacked
    pla
    jsr Float::AddSignedByte

;; Selects ln(2) and falls through to <Float::MultiplyPacked>.
MultiplyByLogOfTwo:
    lda #<Float::LogOfTwo
    ldy #>Float::LogOfTwo

    .assert * = Float::MultiplyPacked, "LOG must fall through to FMULT."
    ; Falls into Float::MultiplyPacked.
    .endproc
    .endscope

.endmacro
