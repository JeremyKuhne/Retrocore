; retrocore: style=strict
;; The Apple-1's console: the Woz Monitor's terminal output
;;
;; The Apple-1 shows capitals only, so its targets leave `LOWERCASE` 0.

.include <machine.inc>

;; A Return, with bit 7 set as the terminal takes characters.
RETURN = $8D

;; The high bit the terminal takes characters with.
HIGH_BIT = $80

;; The console the program writes to.
.scope Console

.section CODE

;; Readies the console. The terminal needs nothing.
.proc Start
    rts
.endproc

;; Writes a character.
;; In: A = the character, in ASCII
;; Keeps: X, Y
.proc Write
    ora #HIGH_BIT
    jmp CharacterOut
.endproc

;; Ends the line.
;; Keeps: X, Y
.proc NewLine
    lda #RETURN
    jmp CharacterOut
.endproc

.endscope
