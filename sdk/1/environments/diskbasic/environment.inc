; retrocore: style=strict
;; The diskbasic environment: a Color Computer program on an RS-DOS disk, which Disk BASIC's LOADM loads
;;
;; A project includes it as <environment.inc>. The build writes the program as a machine-language file, .BIN, under
;; the project's name in capitals cut to eight, on a disk with the target's files: one block of its bytes from its load
;; address, $2700, and its entry as the address <EXEC> starts. LOADM loads it above Disk BASIC's workspace, Extended
;; BASIC's graphics pages, which Disk BASIC moves up to $0E00-$25FF, and BASIC's empty program at $2601; <EXEC> jumps to
;; its entry with BASIC's stack below its string space at the top of RAM, its return to BASIC on top. The program has
;; Color BASIC's calls, which the Color Computer's <machine.inc> names, and goes back to BASIC's OK prompt with RTS.
;; BASIC's variables start just below the program, at $2603, and grow up over it once it has gone back.

.assert .defined(RC_ENV_DISKBASIC), "environment.inc for diskbasic is for targets whose environment is diskbasic."
