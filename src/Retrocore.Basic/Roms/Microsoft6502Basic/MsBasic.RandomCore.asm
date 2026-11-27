; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the random-number constants and routine.
;; Parameters: useTimers = 1 to seed RND(0) from the PET's timer registers, 2 from the I/O chip the kernal's
;;   `KernalIoBase` names, with five-byte constants, 0 to return the previous value
.macro RandomRoutine useTimers

    .assert useTimers >= 0 && useTimers <= 2, "useTimers is 0, 1 or 2."

    .scope Float continued

    .if useTimers = 2
;; Multiplier for <Functions::Rnd>, five bytes.
;; Also: RMULZC (M6502)
RandomMultiplier:
        .byte $98, $35, $44, $7A, $00

;; Addend for <Functions::Rnd>, five bytes.
;; Also: RADDZC (M6502)
RandomAddend:
        .byte $68, $28, $B1, $46, $00
    .else
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
    .endif
    .endscope

    .scope Functions continued

    ;; Implements RND using the sign of <Fac>.
    ;;
    ;; A negative argument starts a sequence from that argument. A positive argument advances the saved value using
    ;; <Float::RandomMultiplier> and <Float::RandomAddend>. Zero returns the last value in <RandomValue> unless the
    ;; timer variant reads hardware timers: the PET's at fixed addresses or, in mode 2 (the VIC-20), timer 1 and timer
    ;; 2 of the VIA whose address the kernal's `KernalIoBase` returns. For a nonzero argument the high and low mantissa
    ;; bytes are exchanged (and, in the timer variants, the middle two); a zero argument's timer bytes are loaded
    ;; already permuted and skip the exchange. The exponent is shifted into the mantissa during normalization, and the
    ;; positive result is saved in <RandomValue>.
    ;; Out: Fac = pseudorandom value
    ;; Entry:
    ;;   ToStoreFac = Jumps on to <Float::StoreFac>
    ;; Also: RND (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Rnd
    jsr Float::GetSign
    .if .not useTimers
        tax
    .endif
    bmi Scramble
    .if useTimers = 2
        bne NextValue
        jsr KernalIoBase
        stx Pointer1
        sty Pointer1+1
        ldy #VIA_TIMER1_LOW
        lda (Pointer1),y
        sta FacMantissa1
        iny
        lda (Pointer1),y
        sta FacMantissa3
        ldy #VIA_TIMER2_LOW
        lda (Pointer1),y
        sta FacMantissa2
        iny
        lda (Pointer1),y
        sta FacMantissa4
        jmp NormalizeAndSave
    .elseif useTimers
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
;; Also: QSETNR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
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
;; Also: RND1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
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
;; Also: STRNEX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
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
;; Also: GMOVMF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToStoreFac:
    jmp Float::StoreFac
    .endproc
    .endscope

.endmacro
