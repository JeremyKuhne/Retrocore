;; Emits the random-number constants and routine.
;; Parameters: useTimers = 1 to seed RND(0) from hardware timers, 0 to return the previous value
.macro RANDOM_ROUTINE useTimers

    .assert useTimers = 0 || useTimers = 1, "useTimers is 0 or 1."

;; Multiplier for <RND>, stored as four bytes followed by the first byte of <RADDZC>.
;;
;; The five-byte operands intentionally overlap; <RADDZC>'s fifth byte is the opcode at <RND>.
RMULZC:
    .byte $98, $35, $44, $7A

;; Addend for <RND>: four bytes followed by the first instruction byte at <RND>.
RADDZC:
    .byte $68, $28, $B1, $46

;; Implements RND using the sign of <FAC>.
;;
;; A negative argument starts a sequence from that argument. A positive argument advances the saved value using
;; <RMULZC> and <RADDZC>. Zero returns the last value in <RNDX> unless the timer variant reads hardware timers.
;; The high and low mantissa bytes are exchanged, the exponent is shifted into the mantissa during normalization,
;; and the positive result is saved in <RNDX>. The timer variant also exchanges the middle mantissa bytes.
;; Out: FAC = pseudorandom value
;; Entry: STRNEX = normalizes and saves the current mantissa
RND:
    jsr SIGN
.if .not useTimers
    tax
.endif
    bmi RND1
.if useTimers
    bne QSETNR
    lda CQHTIM
    sta FACHO
    lda CQHTIM+4
    sta FACMOH
    lda CQHTIM+1
    sta FACMO
    lda CQHTIM+5
    sta FACLO
    jmp STRNEX
.endif

QSETNR:
    lda #<RNDX
    ldy #>RNDX
    jsr MOVFM
.if .not useTimers
    txa
    beq RANDRT
.endif
    lda #<RMULZC
    ldy #>RMULZC
    jsr FMULT
    lda #<RADDZC
    ldy #>RADDZC
    jsr FADD

RND1:
    ldx FACLO
    lda FACHO
    sta FACLO
    stx FACHO
.if useTimers
    ldx FACMOH
    lda FACMO
    sta FACMOH
    stx FACMO
.endif

STRNEX:
    lda #0
    sta FACSGN
    lda FACEXP
    sta FACOV
    lda #$80
    sta FACEXP
    jsr NORMAL
    ldx #<RNDX
    ldy #>RNDX

;; Stores <FAC> in the floating-point variable addressed by X and Y via <MOVMF>.
GMOVMF:
    jmp MOVMF

.endmacro
