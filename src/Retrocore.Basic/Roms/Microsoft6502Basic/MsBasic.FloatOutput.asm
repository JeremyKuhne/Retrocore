; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC DECIMAL OUTPUT
;;
;; <FOUT> converts <FAC> to a zero-terminated decimal string in <FBUFFR>, with a minus sign when its sign bit is set.
;; The sign is tested even for a zero exponent.
;; It scales and rounds to nine significant digits, removes trailing zeroes, and uses an E exponent when needed.
;; The alternating signed powers of ten in <FOUTBL> generate the decimal digits.
;;
;; This shared module follows MsBasic.FloatConversion.asm.

.include "MsBasic.OutputCore.asm"

    OUTPUT_CONSTANTS 0
    DECIMAL_OUTPUT 1, TIME
    OUTPUT_TABLES 1, TIME
