; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: FLOATING-POINT ADDITION AND SUBTRACTION
;;
;; AppleSoft and PET BASIC store a number in five bytes: an exponent E biased by $80, then four mantissa bytes,
;; most significant first. Bit 7 of the first mantissa byte is the sign; the remaining 31 bits follow an implicit 1.
;; Put the binary point before that leading bit, giving a fraction M in [1/2, 1). When E is nonzero, the value is
;; (-1)^sign * M * 2^(E - $80). E = 0 denotes zero regardless of the other bytes. For example,
;; $81,$00,$00,$00,$00 is 1 and $80,$00,$00,$00,$00 is 1/2.
;;
;; In the unpacked <Fac> and argument accumulators, the leading bit is restored in <FacMantissa1> or <ArgMantissa1>,
;; and bit 7 of <FacSign> or <ArgSign> is the sign. The other sign-byte bits are not guaranteed to be zero.
;; <FacExtension> extends <Fac> with eight low guard bits; it is used for alignment and rounding. An exponent of zero
;; is the only reliable test for zero in either representation.
;;
;; Binary operations normally take a packed operand at Y:A, unpack it into the argument accumulator, and combine it
;; with <Fac>. Their Arg entries instead take both operands already unpacked; except for <Float::SubtractFromArg>,
;; they also expect the zero flag to reflect <FacExponent> and <ResultSign> to hold the exclusive OR of the signs. The
;; result is in <Fac>. Subtraction and division take the argument accumulator minus <Fac> and divided by <Fac>.
;;
;; The routines are in <Float>, each giving Microsoft's name in its `Also:` section. AppleSoft's build includes this
;; module and the five that follow it; the PET builds include the same macros through Commodore.FloatingPoint.asm.
;; The arithmetic continues in MsBasic.FloatArithmetic.asm.

.include "MsBasic.AdditionCore.asm"

    AdditionEntries
    AddAndNormalize
