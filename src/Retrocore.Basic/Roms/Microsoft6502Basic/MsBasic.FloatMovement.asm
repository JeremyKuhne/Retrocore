; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: FLOATING-POINT MOVEMENT
;;
;; These routines pack and unpack five-byte numbers and move the unpacked <Fac>, argument accumulator and result.
;; Packing rounds <Fac> using <FacExtension>; zero is identified by its exponent, not by the other bytes.
;;
;; This shared module follows MsBasic.FloatArithmetic.asm.

.include "MsBasic.MovementCore.asm"

    FloatMovement
