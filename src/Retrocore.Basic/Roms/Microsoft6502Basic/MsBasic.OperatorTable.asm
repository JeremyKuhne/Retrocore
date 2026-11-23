; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; The operator dispatch table shared by Microsoft 6502 BASIC variants.

;; Emits the operator table with independently selected precedence rules and AND handler.
;; Parameters: powerBelowNegation = 1 for power below unary negation, 0 for power above it
;;   highNot = 1 for NOT at the unary precedence, 0 for the original lower precedence
;;   andEntry = the AND operator's handler
.macro OPERATOR_TABLE powerBelowNegation, highNot, andEntry

    .assert powerBelowNegation = 0 || powerBelowNegation = 1, "powerBelowNegation is 0 or 1."
    .assert highNot = 0 || highNot = 1, "highNot is 0 or 1."

;; Operator precedence bytes and handler addresses, in the order of tokens + through OR.
;;
;; Each entry is one precedence byte followed by a little-endian handler address minus one. The evaluator
;; stacks that address for RTS dispatch. Higher precedence binds more tightly; the following entries provide
;; unary negation, NOT and the shared relational handler.
OPTAB:
    .byte $79
    .word FADDT - 1
    .byte $79
    .word FSUBT - 1
    .byte $7B
    .word FMULTT - 1
    .byte $7B
    .word FDIVT - 1
.if powerBelowNegation
    .byte $7D
.else
    .byte $7F
.endif
    .word FPWRT - 1
    .byte $50
    .word andEntry - 1
    .byte $46
    .word OROP - 1

;; Precedence and handler address minus one for unary negation.
NEGTAB:
.if powerBelowNegation
    .byte $7F
.else
    .byte $7D
.endif
    .word NEGOP - 1

;; Precedence and handler address minus one for NOT.
NOTTAB:
.if highNot
    .byte $7F
.else
    .byte $5A
.endif
    .word NOTOP - 1

;; Precedence and handler address minus one for relational comparisons.
PTDORL:
    .byte $64
    .word DOREL - 1

.endmacro
