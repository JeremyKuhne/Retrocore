;; MICROSOFT 6502 BASIC FLOATING-POINT ADDITION AND SUBTRACTION
;;
;; AppleSoft and PET BASIC store a number in five bytes: an exponent E biased by $80, then four mantissa bytes,
;; most significant first. Bit 7 of the first mantissa byte is the sign; the remaining 31 bits follow an implicit 1.
;; Put the binary point before that leading bit, giving a fraction M in [1/2, 1). When E is nonzero, the value is
;; (-1)^sign * M * 2^(E - $80). E = 0 denotes zero regardless of the other bytes. For example,
;; $81,$00,$00,$00,$00 is 1 and $80,$00,$00,$00,$00 is 1/2.
;;
;; In the unpacked <FAC> and argument accumulators, the leading bit is restored in <FACHO> or <ARGHO> and bit 7
;; of <FACSGN> or <ARGSGN> is the sign. The other sign-byte bits are not guaranteed to be zero. <FACOV> extends
;; <FAC> with eight low guard bits; it is used for alignment and rounding. An exponent of zero is the only reliable
;; test for zero in either representation.
;;
;; Binary operations normally take a packed operand at Y:A, unpack it into the argument accumulator, and combine it
;; with <FAC>. Their T entries instead take both operands already unpacked; except for <FSUBT>, they also expect
;; the zero flag to reflect <FACEXP> and <ARISGN> to hold the exclusive OR of the signs. The result is in <FAC>.
;; Subtraction and division use the argument accumulator minus <FAC> and divided by <FAC> respectively.
;;
;; Microsoft's routine names are retained. The AppleSoft native build uses these modules; the PET builds still use
;; the MACRO-10 overlays. The arithmetic continues in MsBasic.FloatArithmetic.asm.

.include "MsBasic.AdditionCore.asm"

    ADD_ENTRIES

; The WAIT statement's exit alias refers back to <STORDO> in MsBasic.MemoryAccess.asm.
ZSTORD = STORDO

    ADD_AND_NORMALIZE
