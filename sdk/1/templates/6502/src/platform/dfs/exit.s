; retrocore: style=strict
;; How a program ends under the BBC Micro's DFS: back in BASIC
;;
;; `*RUN` calls the program as a subroutine, so returning from it goes back to the language that ran the command,
;; BASIC, which shows its `>` prompt. The program's entry, <Main>, leaves the stack as it found it.

.section CODE

;; Returns to the `*RUN` that started the program.
.proc Exit
    rts
.endproc
