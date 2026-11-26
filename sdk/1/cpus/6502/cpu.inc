; retrocore: style=strict
;; The 6502 family's names, for every target whose CPU is a 6502 or a 65C02
;;
;; A project includes it as <cpu.inc>. It names what every 6502 has wherever it is: the stack's page and the vectors
;; the CPU reads at the top of memory. The ROM owns the vectors on most machines, so a program reads them rather than
;; writes them. A 65C02 target defines RC_CPU_65C02 as well as RC_CPU_6502, so `.if .defined(RC_CPU_65C02)` chooses
;; code that needs the CMOS instructions.

.assert .defined(RC_CPU_6502), "cpu.inc for the 6502 is for targets whose CPU runs 6502 code."

;; The stack's page, from $0100 to $01FF; S indexes it, from $FF down.
Stack = $0100

;; The vector the CPU jumps through on a non-maskable interrupt.
NmiVector = $FFFA

;; The vector the CPU jumps through when it is reset.
ResetVector = $FFFC

;; The vector the CPU jumps through on an interrupt request or a BRK.
IrqVector = $FFFE
