; retrocore: style=strict
;; Hello, world: the program every target builds
;;
;; It writes a greeting through its machine's console, then ends as its environment ends a program. The console is in
;; the machine family's folder of `src/platform/`, such as `src/platform/coco/`, and the ending in the environment's,
;; such as `src/platform/colorbasic/`. The build assembles those folders before this file, so it uses only what they
;; give every target: the console's `Start`, `Write` and `NewLine`, and `Exit`.

.section CODE

;; Writes the greeting on a line of its own, then ends.
.proc Main
    jsr Console::Start
    jsr Console::NewLine
    leax Greeting,pcr
NextCharacter:
    lda ,x+
    beq Written
    jsr Console::Write
    bra NextCharacter
Written:
    jsr Console::NewLine
    jmp Exit
.endproc

.section RODATA

;; The greeting, in ASCII, ending in 0.
Greeting:
    .byte "HELLO, WORLD!", 0
