; retrocore: style=strict
;; Hello, world: the program every target builds
;;
;; It writes a greeting through its machine's console, then ends as its environment ends a program. The console is in
;; the machine family's folder of `src/platform/`, such as `src/platform/apple2/`, or the environment's where the
;; environment owns the screen, as `src/platform/sos/` does; the ending is in the environment's, such as
;; `src/platform/dos33/`. The build assembles those folders before this file, so it uses only what they give
;; every target: the console's `Start`, `Write` and `NewLine`, and `Exit`. The SDK's own defines are there too,
;; such as `RC_TARGET`, the target's name.
;;
;; `LOWERCASE` is a build switch: retrocore.json gives it to every target as 0, and a target whose machine shows
;; lowercase letters sets it to 1.
;;
;; | Machine | `LOWERCASE` | The greeting |
;; | --- | --- | --- |
;; | The Apple-1, the Apple II and II Plus, the PETs but the business one | 0 (the project's define) | `HELLO, WORLD!` |
;; | The Apple IIe, the Apple III, the business PET, the BBC Micro | 1 (the target's define) | `Hello, world!` |

.assert LOWERCASE = 0 || LOWERCASE = 1, "LOWERCASE is 1 for a machine that shows lowercase or 0 for capitals only."

.section CODE

;; Writes the greeting on a line of its own, then ends.
.proc Main
    jsr Console::Start
    jsr Console::NewLine
    ldx #0
NextCharacter:
    lda Greeting,x
    beq Written
    jsr Console::Write
    inx
    bne NextCharacter
Written:
    jsr Console::NewLine
    jmp Exit
.endproc

.section RODATA

;; The greeting, in ASCII, ending in 0.
Greeting:
.if LOWERCASE
    .byte "Hello, world!", 0
.else
    .byte "HELLO, WORLD!", 0
.endif
