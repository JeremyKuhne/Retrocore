; retrocore: style=strict
;; Where the CCP starts the program
;;
;; The CCP starts a .COM file at its first byte, $0100. The made linker configuration puts the STARTUP section there,
;; ahead of the console in CODE, so the program's first byte goes on to its start.

.section STARTUP

;; The command's first byte, where the CCP starts it: on to <Main>.
Start:
    JP Main
