; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC EXPONENTIATION, RANDOM NUMBERS AND TRANSCENDENTAL FUNCTIONS
;;
;; These routines operate on the floating-point accumulator <FAC> and use the five-byte packed format for
;; constants and polynomial coefficients. <LOG> and the arithmetic primitives are in the floating-point modules.
;; This shared module follows MsBasic.FloatOutput.asm; in the Apple II build its final table ends immediately
;; before the machine-specific <INITAT> cold-start template.

.include "MsBasic.TranscendentalCore.asm"
.include "MsBasic.RandomCore.asm"


;; Group: Exponentiation and square root

    POWER_ROUTINES

;; Group: Exponential approximation

    EXP_CONSTANTS

    EXP_ROUTINE

;; Group: Polynomial evaluation

    POLYNOMIAL_ROUTINES

;; Group: Random numbers

    RANDOM_ROUTINE 0

;; Group: Sine, cosine and tangent

    TRIG_ROUTINES

    SIN_CONSTANTS
    ; Unused signature: "MICROSOFT!" backwards, each byte XORed with $87.
    .byte $A6, $D3, $C1, $C8, $D4, $C8, $D5, $C4, $CE, $CA

;; Group: Arctangent

    ATN_ROUTINE

    ATN_CONSTANTS
