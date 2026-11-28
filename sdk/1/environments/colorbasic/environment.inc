; retrocore: style=strict
;; The colorbasic environment: a Color Computer program on a cassette, which Color BASIC's <CLOADM> loads
;;
;; A project includes it as <environment.inc>. The build writes the program as a machine-language file on a 1500 baud
;; cassette, under the project's name in capitals cut to eight, with its entry as the address <EXEC> starts. <CLOADM>
;; loads it at its load address, $1F00, above Extended BASIC's graphics pages and BASIC's empty program, and <EXEC>
;; jumps to its entry, with BASIC's stack below its string space at the top of RAM, its return to BASIC on top; the
;; program has Color BASIC's calls, which the Color Computer's <machine.inc> names, and goes back to BASIC's OK prompt
;; with RTS. BASIC's variables start just below the program, at $1E03, and grow up over it once it has gone back.

.assert .defined(RC_ENV_COLORBASIC), "environment.inc for colorbasic is for targets whose environment is colorbasic."
