;; MICROSOFT 6502 BASIC LOGARITHM, MULTIPLICATION AND DIVISION
;;
;; The logarithm constants precede the arithmetic routines in ROM. <LOG> reduces its argument and evaluates a
;; polynomial; multiplication and division form a mantissa in <RESHO> through <RESLO> and normalize it into <FAC>.
;; Packed operands are five bytes in the format described in MsBasic.FloatingPoint.asm.
;;
;; This shared module follows MsBasic.FloatingPoint.asm.

.include "MsBasic.FloatConstants.asm"
.include "MsBasic.Logarithm.asm"
.include "MsBasic.ArithmeticCore.asm"

    LOG_CONSTANTS
    LOG_ROUTINE
    FLOAT_ARITHMETIC 0
