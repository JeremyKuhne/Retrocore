; retrocore: style=strict
;; How a program ends under DOS 3.3: back at BASIC's prompt, with DOS still connected
;;
;; The disk's HELLO program runs this one, and DOS's warm start goes back to the BASIC that ran HELLO, with DOS still
;; hooked to it, however the program left the stack.

.include <environment.inc>

.section CODE

;; Goes back to BASIC through DOS's warm start. It never returns.
.proc Exit
    jmp DosWarmStartJump
.endproc
