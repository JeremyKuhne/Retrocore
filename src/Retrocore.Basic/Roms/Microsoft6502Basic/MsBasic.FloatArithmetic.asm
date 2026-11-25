; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: LOGARITHM, MULTIPLICATION AND DIVISION
;;
;; The logarithm constants precede the arithmetic routines in ROM. <Functions::Log> reduces its argument and
;; evaluates a polynomial; multiplication and division form a mantissa in <Result1> through <Result4> and normalize it
;; into <Fac>. Packed operands are five bytes in the format described in MsBasic.FloatingPoint.asm.
;;
;; This shared module follows MsBasic.FloatingPoint.asm.

.include "MsBasic.FloatConstants.asm"
.include "MsBasic.Logarithm.asm"
.include "MsBasic.ArithmeticCore.asm"

    LogarithmConstants
    LogarithmRoutine
    FloatArithmetic 0
