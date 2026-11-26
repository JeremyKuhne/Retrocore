; retrocore: style=strict
;; The bare environment: a program loaded straight into RAM, which calls only the ROM's routines
;;
;; A project includes it as <environment.inc>. A bare program has no system of its own to call: it uses the routines
;; and locations its machine's <machine.inc> names, and starts at its entry with the machine as its ROM left it. It
;; ends by looping or by returning to the ROM's monitor, as its machine allows.

.assert .defined(RC_ENV_BARE), "environment.inc for bare is for targets whose environment is bare."
