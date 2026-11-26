; retrocore: style=strict
;; Jumps: <FJP at Jump::IfFalse> and <UJP at Jump::Always>.

;; The bit of a boolean that holds its value: TRUE is 1 and FALSE 0, and <FJP at Jump::IfFalse> tests only this bit.
TRUE_BIT = 1

;; <FJP at Jump::IfFalse> and <UJP at Jump::Always>, which share <UJP at Jump::Always>'s jump: an offset byte, a short
;; jump from the next p-code when positive, and a jump through the procedure's jump table when negative.
.scope Jump

;; The jump table's word that a negative offset picks.
Entry = Pointer

;; Pops a boolean, and jumps by the offset when it is false.
;; Also: FJP (A2POSRM, UCSD20, WK11)
IfFalse:
    ; Pop the boolean. True: on to the next p-code.
    pla
    tax
    pla
    txa
    and #TRUE_BIT
    bne Fetch::Skip2

    ; False: jump, as UJP does.

;; Jumps by the offset.
;; Also: UJP (A2POSRM, UCSD20, WK11)
Always:
    ; A positive offset counts from the next p-code: add it to InstructionPointer, and step over the UJP.
    clc
    ldy #1
    lda (InstructionPointer),y
    bmi Long
    adc InstructionPointer
    sta InstructionPointer
    bcc Fetch::Skip2
    inc InstructionPointer+1
    jmp Fetch::Skip2

    ; A negative offset picks a word of the jump table, below JumpTable: add it, with $FF as its high byte.
Long:
    adc JumpTable
    sta Entry
    lda #$FF
    adc JumpTable+1
    sta Entry+1

    ; The word holds its own distance above the target.
    lda Entry
    sec
    ldy #0
    sbc (Entry),y
    sta InstructionPointer
    lda Entry+1
    iny
    sbc (Entry),y
    sta InstructionPointer+1
    jmp Fetch::Next

.endscope
