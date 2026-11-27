; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: RELATIONAL OPERATORS

;; Emits the numeric and string comparison entries.
;; Parameters: trueByte = $01 for a true result of one, $FF for a true result of minus one
.macro RelationalOperators trueByte
    .assert trueByte = $01 || trueByte = $FF, "trueByte is $01 or $FF."

    ;; Compares numeric or string operands and applies the relation mask.
    ;; In: carry = set for an argument string or clear for a number, ValueType = accumulator type,
    ;;   RelationMask = relation mask
    ;; Out: Fac = zero or the variant's true value
    ;; Errors: TYPE MISMATCH if the operand types differ
    ;; See: <ApplyRelation::CompareStrings>, <Float::Compare>
    ;; Also: DOREL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc ApplyRelation
    jsr CHKVAL
    bcs CompareStrings
    lda ArgSign
    ora #$7F
    and ArgMantissa1
    sta ArgMantissa1
    lda #<ArgExponent
    ldy #$00
    jsr Float::Compare
    tax
    jmp NumberResult

;; Compares bytes up to the shorter string's length, then compares lengths if needed.
;; In: ArgMantissa3 = the low byte of the argument's descriptor address, ArgMantissa4 = its high byte,
;;   FacMantissa3 = the low byte of the accumulator's descriptor address, FacMantissa4 = its high byte,
;;   RelationMask = relation mask
;; Out: Fac = zero or the variant's true value
;; Also: STRCMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CompareStrings:
    lda #$00
    sta ValueType
    dec OperatorMask
    jsr Strings::ReleaseFac
    sta NewDescriptor
    stx NewDescriptor+1
    sty NewDescriptor+2
    lda ArgMantissa3
    ldy ArgMantissa4
    jsr Strings::ReleaseDescriptor
    stx ArgMantissa3
    sty ArgMantissa4
    tax
    sec
    sbc NewDescriptor
    beq SetLengthOrder
    lda #$01
    bcc SetLengthOrder
    ldx NewDescriptor
    lda #$FF
;; Stores the length order (0, 1, $FF) for equal prefixes.
;; Also: STASGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SetLengthOrder:
    sta FacSign
    ldy #$FF
    inx
;; Counts down the shorter length; at its end uses the length order.
;; Also: NXTCMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextByte:
    iny
    dex
    bne CompareByte
    ldx FacSign
;; Turns the order in X into the carry form <ApplyRelation::ApplyMask> expects.
;; Also: QCOMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NumberResult:
    bmi ApplyMask
    clc
    bcc ApplyMask
;; Compares one byte of each string.
;; Also: GETCMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CompareByte:
    lda (ArgMantissa3),y
    cmp (NewDescriptor+1),y
    beq NextByte
    ldx #$FF
    bcs ApplyMask
    ldx #$01
;; Maps the order to a relation bit and masks it with <RelationMask>.
;; Also: DOCMP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ApplyMask:
    inx
    txa
    rol a
    and RelationMask
    beq ToConvertSignedByte
    lda #trueByte
;; Jumps on to <Float::ConvertSignedByte> with the result.
;; Also: GOFLOT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToConvertSignedByte:
    jmp Float::ConvertSignedByte
    .endproc
.endmacro
