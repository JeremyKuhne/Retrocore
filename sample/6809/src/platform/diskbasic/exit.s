; retrocore: style=strict
;; How a program ends under Disk BASIC: back at BASIC's OK prompt
;;
;; <EXEC> jumped to the program with BASIC's return on the stack, so its RTS goes back to BASIC, which prints OK and
;; reads the next command.

.include <environment.inc>

.section CODE

;; Goes back to BASIC, which <EXEC> jumped from. The program's calls are balanced, so the stack is as <EXEC> left it.
.proc Exit
    rts
.endproc
