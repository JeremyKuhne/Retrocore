; retrocore: style=strict
;; Programmer's Aid #1: Renumber's BASIC entries ($D6DD-$D716)
;;
;; The CALLs that renumber an Integer BASIC program from BASIC's variables: they read the new numbering and the range,
;; put them in Renumber's SWEET16 registers, and enter <Renumber::RenumberRange>. The variables must be the program's
;; first, in this order, which `CLR` then `START=` and `STEP=` (and `FROM=` and `TO=`) give:
;;
;; - `START`, the first new line number, and `STEP`, the step between them;
;; - `FROM` and `TO`, the lowest and highest line renumbered, for <Renumber::BasicRenumberRange> only.
;;
;; Apple's listings do not include this part, so its names have no historical names. Part of ProgrammersAid.asm.

; Renumber: its entries from BASIC, after the RAM test.
.scope Renumber continued

; Where each variable's value is, from LOMEM: its name, the byte after it and the 2-byte link come first.

;; `START`'s value, the first variable's.
START_VALUE = $08

;; `STEP`'s value, the second variable's.
STEP_VALUE = $11

;; `FROM`'s value, the third variable's.
FROM_VALUE = $1A

;; `TO`'s value, the fourth variable's.
TO_VALUE = $21

; Renumber's SWEET16 registers, as the page-zero bytes they live in.

;; <FIRST_NUMBER>'s bytes: the first new number.
FirstNumber = Sweet16Registers + FIRST_NUMBER * SWEET16_REGISTER_SIZE

;; <STEP>'s bytes: the step.
Step = Sweet16Registers + STEP * SWEET16_REGISTER_SIZE

;; <LOWEST_LINE>'s bytes: the lowest line renumbered.
LowestLine = Sweet16Registers + LOWEST_LINE * SWEET16_REGISTER_SIZE

;; <HIGHEST_LINE>'s bytes: the highest line renumbered.
HighestLine = Sweet16Registers + HIGHEST_LINE * SWEET16_REGISTER_SIZE

;; CALL -10531: renumbers every line, from `START` by `STEP`.
.proc BasicRenumberAll
.assert * = $D6DD, "Renumber::BasicRenumberAll must stay at $D6DD, CALL -10531."

    ; From line 0 to line 65535.
    ldy #0
    sty LowestLine
    sty LowestLine + 1
    dey
    tya
    ; Always taken.
    bne BasicRenumberRange::SetNumbering
.endproc

;; CALL -10521: renumbers the lines from `FROM` to `TO`, from `START` by `STEP`.
;; Entry:
;;   SetNumbering = takes the highest line from A (low) and Y (high), then `START` and `STEP`, and renumbers
.proc BasicRenumberRange
.assert * = $D6E7, "Renumber::BasicRenumberRange must stay at $D6E7, CALL -10521."
    ldy #FROM_VALUE
    jsr ReadVariable
    sta LowestLine
    sty LowestLine + 1
    ldy #TO_VALUE
    jsr ReadVariable

;; Takes the highest line from A and Y, then `START` and `STEP`, and renumbers.
SetNumbering:
    sta HighestLine
    sty HighestLine + 1
    ldy #START_VALUE
    jsr ReadVariable
    sta FirstNumber
    sty FirstNumber + 1
    ldy #STEP_VALUE
    jsr ReadVariable
    sta Step
    sty Step + 1
    jmp RenumberRange
.endproc

;; Reads the value of the variable at an offset from <LOMEM>.
;; In: Y = the offset of its value
;; Out: A = the value's low byte, Y = its high byte
;; Keeps: X
.proc ReadVariable
    lda (LOMEM),y
    pha
    iny
    lda (LOMEM),y
    tay
    pla
    rts
.endproc

.endscope
