; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: SIGNS, COMPARISON AND NUMBER PARSING
;;
;; Sign and comparison return signed byte results; integer conversion and decimal input leave results in <Fac>.
;; <Float::ReadNumber> accumulates digits, tracks the decimal point and scales by a decimal exponent.
;;
;; This shared module follows MsBasic.FloatMovement.asm.

.include "MsBasic.ConversionCore.asm"
.include "MsBasic.DecimalInputCore.asm"

    SignAndIntegerRoutines
    DecimalInput 0
