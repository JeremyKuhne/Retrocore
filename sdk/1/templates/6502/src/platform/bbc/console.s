; retrocore: style=strict
;; The BBC Micro's console: the MOS's character output
;;
;; MODE 7, the screen the BBC Micro starts in, shows lowercase letters, so its targets set `LOWERCASE` to 1.

.include <machine.inc>

;; The console the program writes to.
.scope Console

.section BSS

;; X while <Write> runs.
SavedX:
    .res 1

;; Y while <Write> runs.
SavedY:
    .res 1

.section CODE

;; Readies the console. The MOS's screen is ready once the machine has started.
.proc Start
    rts
.endproc

;; Writes a character on the screen.
;; In: A = the character, in ASCII
;; Keeps: X, Y
.proc Write
    stx SavedX
    sty SavedY
    jsr OSWRCH
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Ends the line, with a line feed and a Return.
;; Keeps: X, Y
.proc NewLine
    stx SavedX
    sty SavedY
    jsr OSNEWL
    ldx SavedX
    ldy SavedY
    rts
.endproc

.endscope
