; retrocore: style=strict
;; How a program ends under the PET's BASIC: back at READY.
;;
;; BASIC's `SYS` calls the program as a subroutine, so returning from it goes back to BASIC, which shows `READY.`.
;; The program's entry, <Main>, leaves the stack as it found it.

.section CODE

;; Returns to the `SYS` that started the program.
.proc Exit
    rts
.endproc
