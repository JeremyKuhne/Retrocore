;; MICROSOFT 6502 BASIC FLOATING-POINT MOVEMENT
;;
;; These routines pack and unpack five-byte numbers and move the unpacked <FAC>, argument accumulator and result.
;; Packing rounds <FAC> using <FACOV>; zero is identified by its exponent, not by the other bytes.
;;
;; This shared module follows MsBasic.FloatArithmetic.asm.

.include "MsBasic.MovementCore.asm"

    FLOAT_MOVEMENT
