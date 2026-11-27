; retrocore: style=strict
;; How a program ends on a bare machine: it stays
;;
;; A bare target's program is loaded and started by the debugger, with no system to go back to, so a program that
;; has finished waits, and the machine's Reset key, or the debugger, leaves it. A target in another environment uses
;; that environment's folder of `src/platform/` instead of this one.

.section CODE

;; Waits for good. It never returns.
.proc Exit
    jmp Exit
.endproc
