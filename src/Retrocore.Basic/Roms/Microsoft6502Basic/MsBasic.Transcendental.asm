; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: EXPONENTIATION, RANDOM NUMBERS AND TRANSCENDENTAL FUNCTIONS
;;
;; These routines operate on <Fac> and use the five-byte packed format for constants and polynomial coefficients.
;; <Functions::Log> and the arithmetic primitives are in the floating-point modules. This shared module follows
;; MsBasic.FloatOutput.asm; in the Apple II build its final table ends immediately before the machine-specific
;; <CharacterReaderTemplate> cold-start template.

.include "MsBasic.TranscendentalCore.asm"
.include "MsBasic.RandomCore.asm"

;; Group: Exponentiation and square root

    PowerRoutines

;; Group: Exponential approximation

    ExponentialConstants

    ExponentialRoutine

;; Group: Polynomial evaluation

    PolynomialRoutines

;; Group: Random numbers

    RandomRoutine 0

;; Group: Sine, cosine and tangent

    TrigonometricRoutines

    SineConstants
    ; Unused signature: "MICROSOFT!" backwards, each byte XORed with $87.
    .byte $A6, $D3, $C1, $C8, $D4, $C8, $D5, $C4, $CE, $CA

;; Group: Arctangent

    ArctangentRoutine

    ArctangentConstants
