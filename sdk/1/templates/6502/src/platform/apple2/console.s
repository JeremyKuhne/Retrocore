; retrocore: style=strict
;; The Apple II's console: the Monitor's screen output
;;
;; It uses the Monitor's routines alone, so it serves a bare Apple II and one running DOS 3.3 alike: with DOS, the
;; Monitor's output goes through DOS, which passes it on to the screen. The Apple II and II Plus show capitals only,
;; so their targets leave `LOWERCASE` 0; the IIe's set it to 1.

.include <machine.inc>

;; A Return, with its high bit set, as the screen takes it.
RETURN = $8D

;; The high bit the screen takes characters with.
HIGH_BIT = $80

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

;; Readies the console. The Monitor's screen is ready once the machine has started.
.proc Start
    rts
.endproc

;; Writes a character on the screen. The Monitor's output goes through its output hook, which DOS or a card may have
;; taken, so the registers are kept here rather than left to whichever routine that is.
;; In: A = the character, in ASCII
;; Keeps: X, Y
.proc Write
    ora #HIGH_BIT
    stx SavedX
    sty SavedY
    jsr CharacterOut
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Ends the line.
;; Keeps: X, Y
.proc NewLine
    lda #RETURN
    jmp Write
.endproc

.endscope
