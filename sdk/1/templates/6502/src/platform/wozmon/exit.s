; retrocore: style=strict
;; How a program ends under the Woz Monitor: back at its command line
;;
;; The Woz Monitor's `R` command jumps to the program, so it has nothing to return to; it jumps back to the Monitor's
;; command line, which starts a new line and waits for the next command. `MonitorCommandLine` is the Apple-1's
;; `machine.inc`'s, which the Apple-1's console, assembled before this file, includes.

.section CODE

;; Goes back to the Woz Monitor's command line. It never returns.
.proc Exit
    jmp MonitorCommandLine
.endproc
