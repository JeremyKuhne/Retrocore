; retrocore: style=strict
;; The Z80's names, for every target whose CPU is a Z80
;;
;; A project includes it as <cpu.inc>. It names what every Z80 has wherever it is: where it starts when it is reset,
;; where its non-maskable interrupt goes, and where interrupt mode 1 and RST $38 go. A ROM owns that page on the
;; Model I and the Model III, and CP/M keeps its own vectors there, so a program calls the system's routines rather
;; than the restarts' addresses.

.assert .defined(RC_CPU_Z80), "cpu.inc for the Z80 is for targets whose CPU is a Z80."

;; Where the Z80 starts when it is reset, with interrupts disabled and in interrupt mode 0.
ResetAddress = $0000

;; Where RST $38, and a maskable interrupt in interrupt mode 1, call.
InterruptAddress = $0038

;; Where a non-maskable interrupt calls.
NmiAddress = $0066
