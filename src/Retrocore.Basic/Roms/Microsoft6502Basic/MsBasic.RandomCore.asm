; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the random-number constants and routine.
;; Parameters: useTimers = 1 to seed RND(0) from hardware timers, 0 to return the previous value
.macro RandomRoutine useTimers

    .assert useTimers = 0 || useTimers = 1, "useTimers is 0 or 1."

    .scope Float continued

;; Multiplier for <Functions::Rnd>, stored as four bytes followed by the first byte of <Float::RandomAddend>.
;;
;; The five-byte operands intentionally overlap; <Float::RandomAddend>'s fifth byte is the opcode at <Functions::Rnd>.
;; Also: RMULZC (M6502)
RandomMultiplier:
    .byte $98, $35, $44, $7A

;; Addend for <Functions::Rnd>: four bytes followed by the first instruction byte at <Functions::Rnd>.
;; Also: RADDZC (M6502)
RandomAddend:
    .byte $68, $28, $B1, $46
    .endscope

    .scope Functions continued

    ;; Implements RND using the sign of <Fac>.
    ;;
    ;; A negative argument starts a sequence from that argument. A positive argument advances the saved value using
    ;; <Float::RandomMultiplier> and <Float::RandomAddend>. Zero returns the last value in <RandomValue> unless the
    ;; timer variant reads hardware timers. For a nonzero argument the high and low mantissa bytes are exchanged (and,
    ;; in the timer variant, the middle two); a zero argument's timer bytes are loaded already permuted and skip the
    ;; exchange. The exponent is shifted into the mantissa during normalization, and the positive result is saved in
    ;; <RandomValue>.
    ;; Out: Fac = pseudorandom value
    ;; Entry:
    ;;   ToStoreFac = Jumps on to <Float::StoreFac>
    ;; Also: RND (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Rnd
    jsr Float::GetSign
    .if .not useTimers
        tax
    .endif
    bmi Scramble
    .if useTimers
        bne NextValue
        lda CQHTIM
        sta FacMantissa1
        lda CQHTIM+4
        sta FacMantissa2
        lda CQHTIM+1
        sta FacMantissa3
        lda CQHTIM+5
        sta FacMantissa4
        jmp NormalizeAndSave
    .endif

;; Loads <RandomValue>. Without timers, a zero argument returns it unchanged through
;; <Float::EvaluateStoredPolynomial::Done>; otherwise it is multiplied by <Float::RandomMultiplier> and
;; <Float::RandomAddend> is added.
;; Also: QSETNR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextValue:
    lda #<RandomValue
    ldy #>RandomValue
    jsr Float::LoadFac
    .if .not useTimers
        txa
        beq Float::EvaluateStoredPolynomial::Done
    .endif
    lda #<Float::RandomMultiplier
    ldy #>Float::RandomMultiplier
    jsr Float::MultiplyPacked
    lda #<Float::RandomAddend
    ldy #>Float::RandomAddend
    jsr Float::AddPacked

;; Swaps the top and bottom mantissa bytes (and the middle two, timer build).
;; Also: RND1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Scramble:
    ldx FacMantissa4
    lda FacMantissa1
    sta FacMantissa4
    stx FacMantissa1
    .if useTimers
        ldx FacMantissa2
        lda FacMantissa3
        sta FacMantissa2
        stx FacMantissa3
    .endif

;; Normalizes and saves the current mantissa.
;; Also: STRNEX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NormalizeAndSave:
    lda #0
    sta FacSign
    lda FacExponent
    sta FacExtension
    lda #$80
    sta FacExponent
    jsr Float::Normalize
    ldx #<RandomValue
    ldy #>RandomValue

;; Stores <Fac> in the floating-point variable addressed by X and Y via <Float::StoreFac>.
;; Also: GMOVMF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToStoreFac:
    jmp Float::StoreFac
    .endproc
    .endscope

.endmacro
