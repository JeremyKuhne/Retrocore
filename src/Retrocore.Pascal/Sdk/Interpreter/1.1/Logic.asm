; retrocore: style=strict
;; Logical operations: <LAND at Pcodes::LogicalAnd>, <LOR at Pcodes::LogicalOr> and <LNOT at Pcodes::LogicalNot>, on
;; whole words.

; Pcodes: LogicalAnd, LogicalOr and LogicalNot.
.scope Pcodes continued

;; <LAND at Pcodes::LogicalAnd>: pops two words and pushes their bitwise AND.
;; Also: AND (UCSD20), LAND (A2POSRM)
.proc LogicalAnd

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

;; <LOR at Pcodes::LogicalOr>: pops two words and pushes their bitwise OR.
;; Also: LOR (A2POSRM)
.proc LogicalOr

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

;; <LNOT at Pcodes::LogicalNot>: pops a word and pushes its bitwise complement.
;; Also: LNOT (A2POSRM, WK11), NOT (UCSD20)
.proc LogicalNot
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
.endscope
