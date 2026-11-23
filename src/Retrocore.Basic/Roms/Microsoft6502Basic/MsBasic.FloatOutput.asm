; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: FORMATTING NUMBERS
;;
;; <Float::FormatFac> converts <Fac> to a zero-terminated decimal string in <NumberBuffer>, with a minus sign when its
;; sign bit is set. The sign is tested even for a zero exponent. It scales and rounds to nine significant digits,
;; removes trailing zeroes, and uses an E exponent when needed. The alternating signed powers of ten in
;; <Float::PowersOfTen> generate the decimal digits.
;;
;; This shared module follows MsBasic.FloatConversion.asm.

.include "MsBasic.OutputCore.asm"

    OutputConstants 0
    DecimalOutput 1, TIME
    OutputTables 1, TIME
