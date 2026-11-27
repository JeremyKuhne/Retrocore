; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; The operator dispatch table shared by Microsoft 6502 BASIC variants.

; The precedences of the operator table's entries: higher binds tighter.
;; The precedence of addition and subtraction.
PRECEDENCE_ADD = $79
;; The precedence of multiplication and division.
PRECEDENCE_MULTIPLY = $7B
;; The lower of the levels power and unary negation take, in the order the build gives them.
PRECEDENCE_UPPER = $7D
;; The higher of the levels power and unary negation take; NOT takes it too where `highNot` is 1.
PRECEDENCE_TOP = $7F
;; The precedence of AND.
PRECEDENCE_AND = $50
;; The precedence of OR.
PRECEDENCE_OR = $46
;; The precedence of NOT where `highNot` is 0.
PRECEDENCE_NOT = $5A
;; The precedence of the relational operators, which the evaluator also tests to let a string operand through.
PRECEDENCE_RELATION = $64

;; Emits the operator table with independently selected precedence rules, pointing AND at the handler the vendor
;; names (both vendors pass <Operators::And>).
;; Parameters: powerBelowNegation = 1 for power below unary negation, 0 for power above it
;;   highNot = 1 for NOT at the unary precedence (with powerBelowNegation = 1), 0 for the original lower precedence
;;   andEntry = the AND operator's handler
.macro OperatorEntries powerBelowNegation, highNot, andEntry

    .assert powerBelowNegation = 0 || powerBelowNegation = 1, "powerBelowNegation is 0 or 1."
    .assert highNot = 0 || highNot = 1, "highNot is 0 or 1."

    ;; Operator precedence bytes and handler addresses, in the order of tokens + through OR.
    ;;
    ;; Each entry is one precedence byte followed by a little-endian handler address minus one. The evaluator
    ;; stacks that address for RTS dispatch. Higher precedence binds more tightly; the following entries provide
    ;; unary negation, NOT and the shared relational handler.
    ;; Also: OPTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc OperatorTable
    .byte PRECEDENCE_ADD
    .word Float::AddArg - 1
    .byte PRECEDENCE_ADD
    .word Float::SubtractFromArg - 1
    .byte PRECEDENCE_MULTIPLY
    .word Float::MultiplyArg - 1
    .byte PRECEDENCE_MULTIPLY
    .word Float::DivideArg - 1
    .if powerBelowNegation
        .byte PRECEDENCE_UPPER
    .else
        .byte PRECEDENCE_TOP
    .endif
    .word Float::RaiseArg - 1
    .byte PRECEDENCE_AND
    .word andEntry - 1
    .byte PRECEDENCE_OR
    .word Operators::Or - 1

;; Precedence and handler address minus one for unary negation.
;; Also: NEGTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Negation:
    .if powerBelowNegation
        .byte PRECEDENCE_TOP
    .else
        .byte PRECEDENCE_UPPER
    .endif
    .word Float::Negate - 1

;; Precedence and handler address minus one for NOT.
;; Also: NOTTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Not:
    .if highNot
        .byte PRECEDENCE_TOP
    .else
        .byte PRECEDENCE_NOT
    .endif
    .word Operators::Not - 1

;; Precedence and handler address minus one for relational comparisons.
;; Also: PTDORL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Relation:
    .byte PRECEDENCE_RELATION
    .word ApplyRelation - 1
    .endproc

.endmacro
