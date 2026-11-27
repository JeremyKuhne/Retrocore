; retrocore: style=strict
;; How a program ends under SOS: it stays
;;
;; SOS's TERMINATE call would stop the system and blank the screen, so the greeting would be gone at once; a program
;; that has finished waits instead, and the machine's Reset key, or the debugger, leaves it.

.section CODE

;; Waits for good. It never returns.
.proc Exit
    jmp Exit
.endproc
