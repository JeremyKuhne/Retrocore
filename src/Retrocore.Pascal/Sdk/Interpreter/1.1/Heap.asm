; retrocore: style=strict
;; The heap: <NEW at CspNEW>, MARK and RELEASE, which move <NP>.

;; <NEW at CspNEW>: pops a size in words, then a pointer variable's address; points the variable at <NP> and allocates
;; the size there. Gives back the heap's directory first, and reports a stack overflow when <NP> passes <KP>.
.proc CspNEW

;; The size, in words and then in bytes.
Size = Pointer

;; The pointer variable's address.
Variable = Pointer2

    ; Give back the directory, and pop the arguments.
    jsr FreeDirectory
    pla
    sta Size
    pla
    sta Size+1
    pla
    sta Variable
    pla
    sta Variable+1

    ; Point the variable at NP.
    asl Size
    rol Size+1
    ldy #0
    lda NP
    sta (Variable),y
    iny
    lda NP+1
    sta (Variable),y

    ; Move NP up past the allocation.
    lda NP
    clc
    adc Size
    sta NP
    lda NP+1
    adc Size+1
    sta NP+1

    ; Overflow unless KP is still at or above NP.
    sec
    lda KP
    sbc NP
    lda KP+1
    sbc NP+1
    bcs Done
    jmp ExecutionError::ResetForOverflow
Done:
    jmp Fetch::Skip2
.endproc

;; MARK: pops a pointer variable's address, and stores <NP> in it. Gives back the heap's directory first.
.proc CspMRK

;; The pointer variable's address.
Variable = Pointer

    ; Give back the directory, and pop the address.
    jsr FreeDirectory
    pla
    sta Variable
    pla
    sta Variable+1

    ; Store NP in it.
    ldy #0
    lda NP
    sta (Variable),y
    iny
    lda NP+1
    sta (Variable),y
    jmp Fetch::Skip2
.endproc

;; RELEASE: pops a pointer variable's address, and moves <NP> back to where the variable points, forgetting the heap's
;; directory.
.proc CspRLS

;; The pointer variable's address.
Variable = Pointer

    ; Pop the address, and move NP to the variable's value.
    pla
    sta Variable
    pla
    sta Variable+1
    ldy #0
    lda (Variable),y
    sta NP
    iny
    lda (Variable),y
    sta NP+1

    ; Forget the directory.
    lda #0
    sta SysDirectory
    lda #0
    sta SysDirectory+1
    jmp Fetch::Skip2
.endproc
