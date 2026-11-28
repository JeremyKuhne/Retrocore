; retrocore: style=strict
;; How a program ends under Level II: back at BASIC's prompt
;;
;; SYSTEM loaded the program from its tape and / started it, so it goes back to BASIC's command loop. BASIC takes the
;; stack as the program leaves it, here the one SYSTEM started it on, as its calls are balanced; on the Model III, READY
;; turns the interrupts back on as it stops the cassette.

.include <environment.inc>

.section CODE

;; Goes back to BASIC's prompt. It never returns.
.proc Exit
    JP BasicReady
.endproc
