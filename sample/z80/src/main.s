; retrocore: style=strict
;; Hello, world: the program every target builds
;;
;; It writes a greeting through its machine's console, then ends as its environment ends a program. The console is in
;; the machine family's folder of `src/platform/`, such as `src/platform/trs80/`, or the environment's where the
;; environment owns the console, as `src/platform/cpm/` does, and the ending in the environment's, such as
;; `src/platform/level2/`. The build assembles those folders before this file, so it uses only what they give
;; every target: the console's `Start`, `Write` and `NewLine`, and `Exit`.

.section CODE

;; Writes the greeting on a line of its own, then ends.
.proc Main
    CALL Console::Start
    CALL Console::NewLine
    LD HL,Greeting
NextCharacter:
    LD A,[HL]
    OR A
    JR Z,Written
    CALL Console::Write
    INC HL
    JR NextCharacter
Written:
    CALL Console::NewLine
    JP Exit
.endproc

.section RODATA

;; The greeting, in ASCII, ending in 0.
Greeting:
    .byte "HELLO, WORLD!", 0
