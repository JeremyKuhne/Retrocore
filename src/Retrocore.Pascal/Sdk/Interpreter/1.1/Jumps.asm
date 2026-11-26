; retrocore: style=strict
;; Jumps: <FJP at Jump::IfFalse> and <UJP at Jump::Always>.

;; The bit of a boolean that holds its value: TRUE is 1 and FALSE 0, and <FJP at Jump::IfFalse> tests only this bit.
TRUE_BIT = 1

;; <FJP at Jump::IfFalse> and <UJP at Jump::Always>, which share <UJP at Jump::Always>'s jump: an offset byte, a short
;; jump from the next p-code when positive, and a jump through the procedure's jump table when negative.
.scope Jump

;; The jump table's word that a negative offset picks.
Entry = Pointer

;; FJP: pops a boolean, and jumps by the offset when it is false.
IfFalse:
    ; Pop the boolean. True: on to the next p-code.
    pla
    tax
    pla
    txa
    and #TRUE_BIT
    bne Fetch::Skip2

    ; False: jump, as UJP does.

;; UJP: jumps by the offset.
Always:
    ; A positive offset counts from the next p-code: add it to IPC, and step over the UJP.
    clc
    ldy #1
    lda (IPC),y
    bmi Long
    adc IPC
    sta IPC
    bcc Fetch::Skip2
    inc IPC+1
    jmp Fetch::Skip2

    ; A negative offset picks a word of the jump table, below JTAB: add it, with $FF as its high byte.
Long:
    adc JTAB
    sta Entry
    lda #$FF
    adc JTAB+1
    sta Entry+1

    ; The word holds its own distance above the target.
    lda Entry
    sec
    ldy #0
    sbc (Entry),y
    sta IPC
    lda Entry+1
    iny
    sbc (Entry),y
    sta IPC+1
    jmp Fetch::Next

.endscope
