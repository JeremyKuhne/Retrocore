; retrocore: style=strict
;; The Color Computer's console: Color BASIC's character output
;;
;; It uses the ROM's documented call alone, so it serves the Color Computer 1, 2 and 3. Color BASIC's text screen shows
;; capitals; a lowercase letter shows as an inverse capital, so the greeting is in capitals.

.include <machine.inc>

;; The console the program writes to.
.scope Console

.section CODE

;; Readies the console. Color BASIC's screen is ready once the machine has started.
.proc Start
    rts
.endproc

;; Writes a character at the cursor, through Color BASIC's character output vector, whose routine keeps X, Y and U.
;; In: A = the character, in ASCII
;; Keeps: X, Y, U
.proc Write
    jsr [CharacterOutVector]
    rts
.endproc

;; Ends the line: the cursor goes to the start of the next, scrolling at the bottom.
;; Keeps: X, Y, U
.proc NewLine
    lda #RETURN
    bra Write
.endproc

.endscope
