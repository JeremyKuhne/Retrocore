; retrocore: style=strict
;; Helpers the handlers share: big operands, static links and the heap's directory, and what assembled procedures
;; reach through .INTERP.

;; Where <EnterRestart>, in $E000-$FFFF, arrives once it has switched bank 1 in: goes on to <Restart>.
;; Also: JMOVIC (WK11)
.proc RestartJump
    jmp Restart
.endproc

;; Reads a big operand: one byte for 0-127, or two, high byte first, when the first has bit 7 set.
;; In: Y = the operand's offset from <IPC>
;; Out:
;;   Offset = the operand times 2, the byte offset of the word it numbers
;;   IPC = one more when the operand took two bytes, so the caller's <Fetch::Skip2> or <Fetch::Skip3> steps over both
;; Keeps: X, Y
;; Also: B (A2POSRM), EBIG2M (WK11)
.proc GetBig
    ; One byte or two?
    lda (IPC),y
    bpl OneByte

    ; Two: keep the first as the high byte, and step IPC on to the second.
    sta Offset+1
    inc IPC
    bne LowByte
    inc IPC+1

    ; Double the operand; doubling drops the first byte's bit 7.
LowByte:
    lda (IPC),y
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

;; Finds the mark stack frame of the procedure X lexical levels out from the current one, by following static
;; links up from <MP>.
;; In: X = how many levels out
;; Out: Frame = that procedure's frame
.proc FindFrame

;; The static link's low byte, kept while <Frame>'s high byte changes.
LinkLow = Pointer

    ; Start at the current procedure.
    lda MP
    sta Frame
    lda MP+1
    sta Frame+1
    cpx #0
    beq Done

    ; Follow one static link a level.
NextLevel:
    ldy #MSCW_STATIC_LINK
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
;; Out: NP = <SysDirectory> when it was set, and SysDirectory = 0
;; Keeps: Y
.proc FreeDirectory
    ; Is there a directory?
    lda SysDirectory
    bne Free
    ldx SysDirectory+1
    bne Free
    rts

    ; Put NP back where the directory starts, and forget it.
Free:
    sta NP
    lda SysDirectory+1
    sta NP+1
    lda #0
    sta SysDirectory
    lda #0
    sta SysDirectory+1
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
    .word Syscom
    ; .INTERP+6: Pointer, the first of the zero-page bytes the handlers use for working storage.
    .word Pointer
