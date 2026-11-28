; retrocore: style=strict
;; The TRS-80's console: Level II's screen output
;;
;; It uses the ROM's documented call alone, so it serves the Model I with Level II and the Model III. The greeting is
;; in capitals, as the Model I shows no lowercase without its modification.

.include <machine.inc>

;; The console the program writes to.
.scope Console

.section CODE

;; Readies the console. The ROM's screen is ready once the machine has started.
.proc Start
    RET
.endproc

;; Writes a character at the cursor, through the ROM's video device control block.
;; In: A = the character, in ASCII
;; Keeps: BC, DE, HL
.proc Write
    PUSH BC
    PUSH DE
    PUSH HL
    CALL DisplayCharacter
    POP HL
    POP DE
    POP BC
    RET
.endproc

;; Ends the line: the cursor goes to the start of the next, scrolling at the bottom.
;; Keeps: BC, DE, HL
.proc NewLine
    LD A,RETURN
    JR Write
.endproc

.endscope
