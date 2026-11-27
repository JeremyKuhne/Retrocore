; retrocore: style=strict
;; The PET's console: the Kernal's screen output
;;
;; Most PETs start in their character set of capitals and graphics, where ASCII's capitals are PETSCII's, so their
;; targets leave `LOWERCASE` 0. The business PETs start in the other set, of lowercase and capitals, where PETSCII
;; gives a lowercase letter the code of ASCII's capital and a capital that code with bit 7 set; their targets set
;; `LOWERCASE` to 1, and the console swaps each letter's case to write ASCII in that set.

.include <machine.inc>

;; A Return, which ends a line on the screen.
RETURN = $0D

;; The bit that tells a letter's case: clear for ASCII's capitals, set for its lowercase.
ASCII_CASE_BIT = $20

;; The bit PETSCII's lowercase and capitals set gives its capitals.
PETSCII_CAPITAL_BIT = $80

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

;; Readies the console. The screen editor is ready once BASIC has started.
.proc Start
    rts
.endproc

;; Writes a character on the screen.
;; In: A = the character, in ASCII: capitals alone while `LOWERCASE` is 0
;; Keeps: X, Y
.proc Write
    stx SavedX
    sty SavedY
.if LOWERCASE
    ; A capital gets PETSCII's capital bit, and a lowercase letter loses ASCII's lowercase bit.
    cmp #'A'
    bcc Show
    cmp #'Z' + 1
    bcc Capital
    cmp #'a'
    bcc Show
    cmp #'z' + 1
    bcs Show
    and #$FF - ASCII_CASE_BIT
    bne Show
Capital:
    ora #PETSCII_CAPITAL_BIT
Show:
.endif
    jsr KernalCharacterOut
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
