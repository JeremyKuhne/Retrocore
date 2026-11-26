; retrocore: style=strict
;; The basic environment: a PET program as a PRG whose BASIC line SYSes it, loaded from tape or a 4040 disk and RUN
;;
;; A project includes it as <environment.inc>. The build writes the program as a PRG that loads at <BASIC_START>: a
;; BASIC line, 10 SYS and the program's entry, then the program from its load address. It goes on a TAP tape and on a
;; 4040 disk, which LOAD and RUN start. The program has the Kernal's and the screen editor's routines, which the PET's
;; <machine.inc> names. It runs with BASIC's zero page and workspace as BASIC left them after the line's SYS, and uses
;; them as its memory map says only while it does not return to BASIC.

.assert .defined(RC_ENV_BASIC), "environment.inc for basic is for targets whose environment is basic."

;; Where BASIC's program starts on every PET, where the PRG loads: its BASIC line, then the program.
BASIC_START = $0401

;; BASIC's token for SYS, in BASIC 1, 2 and 4, which the program's BASIC line calls its entry with.
SYS_TOKEN = $9E
