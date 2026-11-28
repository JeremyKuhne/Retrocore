; retrocore: style=strict
;; The 6809's names, for every target whose CPU is a 6809
;;
;; A project includes it as <cpu.inc>. It names what every 6809 has wherever it is: the vectors it reads at the top
;; of memory. The ROM owns them on the Color Computer, which points the interrupts through jumps in RAM at $0100, so a
;; program reads the vectors rather than writes them.

.assert .defined(RC_CPU_6809), "cpu.inc for the 6809 is for targets whose CPU is a 6809."

;; The vector the 6809 jumps through for SWI3.
Swi3Vector = $FFF2

;; The vector the 6809 jumps through for SWI2.
Swi2Vector = $FFF4

;; The vector the 6809 jumps through on a fast interrupt request.
FirqVector = $FFF6

;; The vector the 6809 jumps through on an interrupt request.
IrqVector = $FFF8

;; The vector the 6809 jumps through for SWI.
SwiVector = $FFFA

;; The vector the 6809 jumps through on a non-maskable interrupt.
NmiVector = $FFFC

;; The vector the 6809 jumps through when it is reset.
ResetVector = $FFFE
