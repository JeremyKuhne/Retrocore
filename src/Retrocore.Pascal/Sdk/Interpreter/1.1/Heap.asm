; retrocore: style=strict
;; The heap: <NEW at StandardProcedures::New>, MARK and RELEASE, which move <HeapTop>.

; StandardProcedures: New, MarkHeap and ReleaseHeap.
.scope StandardProcedures continued

;; <NEW at StandardProcedures::New>: pops a size in words, then a pointer variable's address; points the variable at
;; <HeapTop> and allocates the size there. Gives back the heap's directory first, and reports a stack overflow when
;; <HeapTop> passes <ProgramStackTop>.
;; Also: NEW (A2POSRM, UCSD20, WK11)
.proc New

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

    ; Point the variable at HeapTop.
    asl Size
    rol Size+1
    ldy #0
    lda HeapTop
    sta (Variable),y
    iny
    lda HeapTop+1
    sta (Variable),y

    ; Move HeapTop up past the allocation.
    lda HeapTop
    clc
    adc Size
    sta HeapTop
    lda HeapTop+1
    adc Size+1
    sta HeapTop+1

    ; Overflow unless ProgramStackTop is still at or above HeapTop.
    sec
    lda ProgramStackTop
    sbc HeapTop
    lda ProgramStackTop+1
    sbc HeapTop+1
    bcs Done
    jmp ExecutionError::ResetForOverflow
Done:
    jmp Fetch::Skip2
.endproc

;; MARK: pops a pointer variable's address, and stores <HeapTop> in it. Gives back the heap's directory first.
;; Also: MARK (UCSD20), MRK (A2POSRM, WK11)
.proc MarkHeap

;; The pointer variable's address.
Variable = Pointer

    ; Give back the directory, and pop the address.
    jsr FreeDirectory
    pla
    sta Variable
    pla
    sta Variable+1

    ; Store HeapTop in it.
    ldy #0
    lda HeapTop
    sta (Variable),y
    iny
    lda HeapTop+1
    sta (Variable),y
    jmp Fetch::Skip2
.endproc

;; RELEASE: pops a pointer variable's address, and moves <HeapTop> back to where the variable points, forgetting the
;; heap's directory.
;; Also: RELEASE (UCSD20), RLS (A2POSRM, WK11)
.proc ReleaseHeap

;; The pointer variable's address.
Variable = Pointer

    ; Pop the address, and move HeapTop to the variable's value.
    pla
    sta Variable
    pla
    sta Variable+1
    ldy #0
    lda (Variable),y
    sta HeapTop
    iny
    lda (Variable),y
    sta HeapTop+1

    ; Forget the directory.
    lda #0
    sta Syscom::Directory
    lda #0
    sta Syscom::Directory+1
    jmp Fetch::Skip2
.endproc
.endscope
