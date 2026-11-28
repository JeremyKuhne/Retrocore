; retrocore: style=strict
;; How a program ends under CP/M: back at the CCP's prompt, through a warm boot
;;
;; A warm boot reloads the CCP from the disk, so the program may have used its memory, and CP/M shows its prompt for
;; the next command. The CP/M names come from <environment.inc>, which console.s includes: the build assembles a
;; platform folder's files in the order of their names, so console.s comes before this file.

.section CODE

;; Ends the program with a warm boot. It never returns.
.proc Exit
    JP WarmBoot
.endproc
