; retrocore: style=strict
;; Helpers the handlers share: big operands, static links and the heap's directory, and what assembled procedures
;; reach through .INTERP.

;; Where <EnterRestart>, in $E000-$FFFF, arrives once it has switched bank 1 in: goes on to <Restart>.
;; Also: JMOVIC (WK11)
.proc RestartJump
    jmp Restart
.endproc

;; Reads a big operand: one byte for 0-127, or two, high byte first, when the first has bit 7 set.
;; In: Y = the operand's offset from <InstructionPointer>
;; Out:
;;   Offset = the operand times 2, the byte offset of the word it numbers
;;   InstructionPointer = one more when the operand took two bytes, so the caller's <Fetch::Skip2> or <Fetch::Skip3>
;;     steps over both
;; Keeps: X, Y
;; Also: B (A2POSRM), EBIG2M (WK11)
.proc GetBig
    ; One byte or two?
    lda (InstructionPointer),y
    bpl OneByte

    ; Two: keep the first as the high byte, and step InstructionPointer on to the second.
    sta Offset+1
    inc InstructionPointer
    bne LowByte
    inc InstructionPointer+1

    ; Double the operand; doubling drops the first byte's bit 7.
LowByte:
    lda (InstructionPointer),y
    asl a
    sta Offset
    rol Offset+1
    rts

    ; One: double it.
OneByte:
    asl a
    sta Offset
    lda #0
    sta Offset+1
    rts
.endproc

;; Finds the mark stack frame of the procedure X lexical levels out from the current one, by following static links up
;; from <LocalFrame>.
;; In: X = how many levels out
;; Out: Frame = that procedure's frame
.proc FindFrame

;; The static link's low byte, kept while <Frame>'s high byte changes.
LinkLow = Pointer

    ; Start at the current procedure.
    lda LocalFrame
    sta Frame
    lda LocalFrame+1
    sta Frame+1
    cpx #0
    beq Done

    ; Follow one static link a level.
NextLevel:
    ldy #MarkStack::STATIC_LINK
    lda (Frame),y
    sta LinkLow
    iny
    lda (Frame),y
    sta Frame+1
    lda LinkLow
    sta Frame
    dex
    bne NextLevel

Done:
    rts
.endproc

;; Gives the heap back down to the directory SYSTEM.PASCAL read onto it, if there is one, to make room for the
;; stack.
;; Out: HeapTop = <Syscom::Directory> when it was set, and Syscom::Directory = 0
;; Keeps: Y
.proc FreeDirectory
    ; Is there a directory?
    lda Syscom::Directory
    bne Free
    ldx Syscom::Directory+1
    bne Free
    rts

    ; Put HeapTop back where the directory starts, and forget it.
Free:
    sta HeapTop
    lda Syscom::Directory+1
    sta HeapTop+1
    lda #0
    sta Syscom::Directory
    lda #0
    sta Syscom::Directory+1
    rts
.endproc

;; The address an assembled procedure's .INTERP references are relocated by: <InterpTable>'s.
InterpAddress:
    .word InterpTable

;; What an assembled procedure reaches through .INTERP, a word at each offset from it.
InterpTable:
    ; .INTERP+0: ExecutionError::Report, which reports the execution error whose number is in A.
    .word ExecutionError::Report
    ; .INTERP+2: the BIOS's first stub; the other 21 follow it, 3 bytes apart.
    .word BiosConsoleRead
    ; .INTERP+4: SYSCOM.
    .word Syscom::Start
    ; .INTERP+6: Pointer, the first of the zero-page bytes the handlers use for working storage.
    .word Pointer
