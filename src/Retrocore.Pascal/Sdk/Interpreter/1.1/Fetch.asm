; retrocore: style=strict
;; The fetch: every handler ends by jumping to one of these entries, which step <IPC> past the p-code it ran and run
;; the next.
.scope Fetch

;; Steps <IPC> past a 3-byte p-code and runs the next.
Skip3:
    lda IPC
    clc
    adc #3
    sta IPC
    bcc Next
    inc IPC+1

    ; INC leaves carry set, so this always branches.
    bcs Next

;; Steps <IPC> past a 2-byte p-code and runs the next.
Skip2:
    lda IPC
    clc
    adc #2
    sta IPC
    bcc Next
    inc IPC+1

    ; INC leaves carry set, so this always branches.
    bcs Next

;; SLDC 0-127, which <Next> comes to itself: pushes the opcode, as a word.
;; In: A = the opcode, Y = 0
SmallConstant:
    tax
    tya
    pha
    txa
    pha

;; Steps <IPC> past a 1-byte p-code and runs the next. NOP runs only this.
Skip1:
    inc IPC
    bne Next
    inc IPC+1

;; Runs the p-code at <IPC>: SLDC 0-127 here, and the rest through <Dispatch> and <OpcodeTable>.
Next:
    ; Fetch the opcode.
    ldy #0
    lda (IPC),y
    bpl SmallConstant

    ; Point Dispatch at the opcode's entry: its offset in OpcodeTable is the opcode times 2, less 256.
    asl a
    sta DispatchLow
    jmp Dispatch

.endscope
