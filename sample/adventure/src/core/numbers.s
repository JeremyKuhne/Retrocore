; retrocore: style=strict
;; Arithmetic the 6502 lacks: multiplying, dividing and random numbers

;; The random numbers' first state, the same in every game, so a transcript plays the same each time.
RANDOM_SEED = $ACE1

;; What the random numbers' state takes when a bit shifts out of it: the taps of a 16-bit maximal-length
;; linear-feedback shift register.
RANDOM_TAPS = $B400

;; Multiplying, dividing and random numbers.
.scope Numbers

.section BSS

;; The number <Multiply> multiplies.
Multiplicand:
    .res 1

;; The product's low byte, after <Multiply>.
Product:
    .res 1

;; The number <Divide> divides, and then the quotient.
Dividend:
    .res 2

;; The number <Divide> divides by.
Divisor:
    .res 1

;; The random numbers' state.
Random:
    .res 2

.section CODE

;; Multiplies two bytes.
;; In: A = one, X = the other
;; Out: A = the product's high byte, Product = its low byte
.proc Multiply
    sta Multiplicand
    stx Product

    ; Each of the multiplier's bits, from the lowest, adds the multiplicand to the high byte; the shifts move the
    ; product's low bits into the multiplier's place.
    lda #0
    ldx #8
    lsr Product
NextBit:
    bcc Shift
    clc
    adc Multiplicand
Shift:
    ror a
    ror Product
    dex
    bne NextBit
    rts
.endproc

;; Divides a 16-bit number by a byte.
;; In: Dividend = the number, Divisor = what it is divided by, not 0
;; Out: Dividend = the quotient, A = the remainder
.proc Divide
    lda #0
    ldx #16
NextBit:
    asl Dividend
    rol Dividend + 1
    rol a
    bcs Subtract
    cmp Divisor
    bcc Next
Subtract:
    sbc Divisor
    inc Dividend
Next:
    dex
    bne NextBit
    rts
.endproc

;; Starts the random numbers at <RANDOM_SEED>.
.proc Seed
    lda #<RANDOM_SEED
    sta Random
    lda #>RANDOM_SEED
    sta Random + 1
    rts
.endproc

;; Takes the next random byte: shifts the state eight times, applying <RANDOM_TAPS> each time a 1 shifts out.
;; Out: A = the byte
.proc NextRandom
    ldx #8
NextBit:
    lsr Random + 1
    ror Random
    bcc Shifted
    lda Random + 1
    eor #>RANDOM_TAPS
    sta Random + 1
    lda Random
    eor #<RANDOM_TAPS
    sta Random
Shifted:
    dex
    bne NextBit
    lda Random
    rts
.endproc

.endscope
