; retrocore: style=strict
;; Where ProDOS starts the program
;;
;; ProDOS starts a system file at its first byte, $2000. The made linker configuration puts the STARTUP section there,
;; ahead of the Apple II's console in CODE, so the program's first byte goes on to the engine's start.

.section STARTUP

;; The system file's first byte, where ProDOS starts it: on to <Engine::Start>.
Start:
    jmp Engine::Start
