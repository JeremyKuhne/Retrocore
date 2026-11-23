; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: SUBSCRIPT AND SIGNED INTEGER CONVERSION
;
; Emit IntegerConversionBoundary immediately followed by IntegerConversion. The latter selects the expression
; evaluator independently of POSINT's optional numeric-type check. AppleSoft and PET BASIC 1 use FRMNUM without
; the extra check; PET BASIC 2 and 4 use FRMEVL and the check.

;; Emits the prefix of the integer-conversion boundary constant.
.macro IntegerConversionBoundary

;; Four-byte prefix of the packed number compared with <Fac> by <FacToInteger>.
;;
;; <Float::Compare> reads five bytes: the fifth is the $20 JSR opcode at <EvaluateSubscript>, not a zero byte.
;; Also: N32768 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MinimumInteger:
    .byte $90, $80, $00, $00
.endmacro

;; Emits the subscript and integer conversion entries immediately after <MinimumInteger>.
;; Parameters: evaluateEntry = expression evaluator, checkType = 1 to check the type at <FacToNonnegativeInteger>, 0 to
;;   omit it
.macro IntegerConversion evaluateEntry, checkType
    .assert checkType = 0 || checkType = 1, "checkType must be 0 or 1."
    .assert * = MinimumInteger+4, "IntegerConversion must immediately follow IntegerConversionBoundary."

    ;; Evaluates the next subscript and converts it to a nonnegative integer.
    ;;
    ;; <GetNextCharacter> advances to the expression before the selected evaluator is called.
    ;; In: TextPointer = character immediately before the expression
    ;; Out: ArrayIndex = integer subscript, high byte first in <FacMantissa3>/<FacMantissa4>
    ;; Errors: TYPE MISMATCH if the selected evaluator or <FacToNonnegativeInteger> checks the type and the result is a
    ;;   string, ILLEGAL QUANTITY if <FacToNonnegativeInteger> rejects the value
    ;; See: <FacToNonnegativeInteger>
    ;; Also: INTIDX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EvaluateSubscript
    jsr GetNextCharacter
    jsr evaluateEntry
    ; Falls into FacToNonnegativeInteger.
    .endproc

    ;; Converts a nonnegative <Fac> to an integer.
    ;;
    ;; When selected, the type check runs before the sign check. Otherwise the caller must supply a numeric result.
    ;; A set sign bit is rejected even when the exponent is zero.
    ;; In: Fac = numeric result, ValueType = result type when the type check is selected
    ;; Out: FacMantissa3 = the integer's high byte, FacMantissa4 = its low byte
    ;; Errors: TYPE MISMATCH if the selected type check rejects a string, ILLEGAL QUANTITY if negative or too large
    ;; See: <FacToInteger>
    ;; Also: POSINT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FacToNonnegativeInteger
    .if checkType
        jsr CHKNUM
    .endif
    lda FacSign
    bmi FacToInteger::FailUnlessEqual
    .endproc

    ;; Converts <Fac> to a signed integer after the exponent and boundary checks.
    ;;
    ;; Exponents below $90 go directly to <Float::ToLongInteger>; otherwise <Float::Compare> must report equality with
    ;; <MinimumInteger>. Because its fifth byte is $20, exact -32768 with a zero guard compares unequal, while the
    ;; packed value $90 $80 $00 $00 $20 compares equal. <Float::Compare> also uses the <FacExtension> guard in its
    ;; last-byte comparison. <Float::ToLongInteger> rounds fractions down and the result here is its low 16 bits.
    ;; In: Fac = numeric result
    ;; Out: FacMantissa3 = the signed integer's high byte, FacMantissa4 = its low byte
    ;; Errors: ILLEGAL QUANTITY if the exponent is at least $90 and the comparison is unequal
    ;; Entry:
    ;;   FailUnlessEqual = A nonzero result (Compare unequal, or <FacSign> negative) goes to ILLEGAL QUANTITY
    ;; See: <Float::Compare>, <MinimumInteger>, <Float::ToLongInteger>
    ;; Also: AYINT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FacToInteger
    lda FacExponent
    cmp #$90
    bcc ToLongInteger
    lda #<MinimumInteger
    ldy #>MinimumInteger
    jsr Float::Compare

;; A nonzero result (Compare unequal, or <FacSign> negative) goes to ILLEGAL QUANTITY.
;; Also: NONONO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FailUnlessEqual:
    bne IllegalQuantityError

;; Converts <Fac> without checking its type, sign or range.
;; See: <Float::ToLongInteger>
;; Also: QINTGO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToLongInteger:
    jmp Float::ToLongInteger
    .endproc
.endmacro
