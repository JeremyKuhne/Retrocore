; retrocore: style=strict
;; The fetch: every handler ends by jumping to one of these entries, which step <InstructionPointer> past the p-code it
;; ran and run the next.
.scope Fetch

;; Steps <InstructionPointer> past a 3-byte p-code and runs the next.
;; Also: UPDBY3 (WK11)
Skip3:
    lda InstructionPointer
    clc
    adc #3
    sta InstructionPointer
    bcc Next
    inc InstructionPointer+1

    ; INC leaves carry set, so this always branches.
    bcs Next

;; Steps <InstructionPointer> past a 2-byte p-code and runs the next.
;; Also: UPDBY2 (WK11)
Skip2:
    lda InstructionPointer
    clc
    adc #2
    sta InstructionPointer
    bcc Next
    inc InstructionPointer+1

    ; INC leaves carry set, so this always branches.
    bcs Next

;; <SLDC> 0-127, which <Next> comes to itself: pushes the opcode, as a word.
;; In: A = the opcode, Y = 0
;; Also: PSHLIT (WK11), SLDC (A2POSRM)
SmallConstant:
    tax
    tya
    pha
    txa
    pha

;; Steps <InstructionPointer> past a 1-byte p-code and runs the next. NOP runs only this.
;; Also: NOP (A2POSRM, UCSD20), UPDBY1 (WK11)
Skip1:
    inc InstructionPointer
    bne Next
    inc InstructionPointer+1

;; Runs the p-code at <InstructionPointer>: <SLDC> 0-127 here, and the rest through <Dispatch> and <OpcodeTable>.
;; Also: EXECPC (WK11)
Next:
    ; Fetch the opcode.
    ldy #0
    lda (InstructionPointer),y
    bpl SmallConstant

    ; Point Dispatch at the opcode's entry: its offset in OpcodeTable is the opcode times 2, less 256.
    asl a
    sta DispatchLow
    jmp Dispatch

.endscope
