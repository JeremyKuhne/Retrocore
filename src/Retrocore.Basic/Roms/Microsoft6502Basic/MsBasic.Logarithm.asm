; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; Emits the natural-logarithm routine before the multiplication routine it enters.
.macro LOG_ROUTINE

;; Computes the natural logarithm of <FAC>.
;;
;; It reduces <FAC> to a fractional range, evaluates a polynomial, adds the binary exponent, and multiplies by ln(2).
;; Errors: illegal argument = jumps to <FCERR> for zero or a negative argument
;; See: <LOGCN2>, <POLYX>
LOG:
    jsr SIGN
    beq LOGERR
    bpl LOG1

LOGERR:
    jmp FCERR

LOG1:
    lda FACEXP
    sbc #$7F                        ; save the binary exponent without its bias
    pha
    lda #$80
    sta FACEXP
    lda #<SQRHLF
    ldy #>SQRHLF
    jsr FADD
    lda #<SQRTWO
    ldy #>SQRTWO
    jsr FDIV
    lda #<FONE
    ldy #>FONE
    jsr FSUB
    lda #<LOGCN2
    ldy #>LOGCN2
    jsr POLYX
    lda #<NEGHLF
    ldy #>NEGHLF
    jsr FADD
    pla
    jsr FINLOG

;; Selects ln(2) and falls through to <FMULT>.
MULLN2:
    lda #<LOG2
    ldy #>LOG2

    .assert * = FMULT, "LOG must fall through to FMULT."
.endmacro
