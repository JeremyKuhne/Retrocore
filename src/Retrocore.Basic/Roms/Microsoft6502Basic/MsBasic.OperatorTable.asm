; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; The operator dispatch table shared by Microsoft 6502 BASIC variants.

;; Emits the operator table with independently selected precedence rules and AND handler.
;; Parameters: powerBelowNegation = 1 for power below unary negation, 0 for power above it
;;   highNot = 1 for NOT at the unary precedence, 0 for the original lower precedence
;;   andEntry = the AND operator's handler
.macro OperatorEntries powerBelowNegation, highNot, andEntry

    .assert powerBelowNegation = 0 || powerBelowNegation = 1, "powerBelowNegation is 0 or 1."
    .assert highNot = 0 || highNot = 1, "highNot is 0 or 1."

;; Operator precedence bytes and handler addresses, in the order of tokens + through OR.
;;
;; Each entry is one precedence byte followed by a little-endian handler address minus one. The evaluator
;; stacks that address for RTS dispatch. Higher precedence binds more tightly; the following entries provide
;; unary negation, NOT and the shared relational handler.
;; Also: OPTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
OperatorTable:
    .byte $79
    .word Float::AddArg - 1
    .byte $79
    .word Float::SubtractFromArg - 1
    .byte $7B
    .word Float::MultiplyArg - 1
    .byte $7B
    .word Float::DivideArg - 1
    .if powerBelowNegation
        .byte $7D
    .else
        .byte $7F
    .endif
    .word Float::RaiseArg - 1
    .byte $50
    .word andEntry - 1
    .byte $46
    .word OROP - 1

;; Precedence and handler address minus one for unary negation.
;; Also: NEGTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Negation:
    .if powerBelowNegation
        .byte $7F
    .else
        .byte $7D
    .endif
    .word Float::Negate - 1

;; Precedence and handler address minus one for NOT.
;; Also: NOTTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Not:
    .if highNot
        .byte $7F
    .else
        .byte $5A
    .endif
    .word NOTOP - 1

;; Precedence and handler address minus one for relational comparisons.
;; Also: PTDORL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Relation:
    .byte $64
    .word ApplyRelation - 1

.endmacro
