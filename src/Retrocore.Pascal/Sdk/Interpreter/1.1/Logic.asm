; retrocore: style=strict
;; Logical operations: <LAND at OpLAND>, <LOR at OpLOR> and <LNOT at OpLNOT>, on whole words.

;; <LAND at OpLAND>: pops two words and pushes their bitwise AND.
;; Also: AND (UCSD20), LAND (A2POSRM)
.proc OpLAND

;; The top word.
Operand = Pointer

    ; Pop the top word.
    pla
    sta Operand
    pla
    sta Operand+1

    ; AND the next word with it, high byte first, and push the result in its place.
    pla
    tax
    pla
    and Operand+1
    pha
    txa
    and Operand
    pha
    jmp Fetch::Skip1
.endproc

;; <LOR at OpLOR>: pops two words and pushes their bitwise OR.
;; Also: LOR (A2POSRM)
.proc OpLOR

;; The top word.
Operand = Pointer

    ; Pop the top word.
    pla
    sta Operand
    pla
    sta Operand+1

    ; OR the next word with it, high byte first, and push the result in its place.
    pla
    tax
    pla
    ora Operand+1
    pha
    txa
    ora Operand
    pha
    jmp Fetch::Skip1
.endproc

;; <LNOT at OpLNOT>: pops a word and pushes its bitwise complement.
;; Also: LNOT (A2POSRM, WK11), NOT (UCSD20)
.proc OpLNOT
    ; Complement both bytes.
    pla
    tax
    pla
    eor #$FF
    pha
    txa
    eor #$FF
    pha
    jmp Fetch::Skip1
.endproc
