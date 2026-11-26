; retrocore: style=strict
;; The wozmon environment: an Apple-1 program typed in at the Woz Monitor as hex, or read from the cassette
;; interface's tape, and started at its entry with R
;;
;; A project includes it as <environment.inc>. The build writes the program as the Woz Monitor's hex, lines that
;; store its bytes from its load address and then the line that runs it, and, unless the target's image is false, as
;; an ACI tape of the same bytes, which C100R and then the program's start.endR read. The program has the Woz Monitor's routines, which the Apple-1's
;; <machine.inc> names, and it ends by looping or by jumping to the Monitor's command line, MonitorCommandLine.

.assert .defined(RC_ENV_WOZMON), "environment.inc for wozmon is for targets whose environment is wozmon."
