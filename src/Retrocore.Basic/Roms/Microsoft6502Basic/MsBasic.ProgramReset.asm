; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: NEW, CLEAR AND EXECUTION RESET
;
; These entries discard program or variable storage, reset the stack and position the text pointer. Callers
; choose the platform's side effects and the original or revised stack-reset sequence independently.

;; Emits the NEW and RUN reset entries.
;; Parameters: resetLock = 1 to clear LOCK;
;;   mirrorEnd = 1 to copy the new variable start to PRGEND; clearCarry = 1 to clear carry before adding two;
;;   runSetsZero = 1 to set zero before falling into the CLEAR entry
.macro ProgramReset resetLock, mirrorEnd, clearCarry, runSetsZero
    .assert resetLock = 0 || resetLock = 1, "resetLock is 0 or 1."
    .assert mirrorEnd = 0 || mirrorEnd = 1, "mirrorEnd is 0 or 1."
    .assert clearCarry = 0 || clearCarry = 1, "clearCarry is 0 or 1."
    .assert runSetsZero = 0 || runSetsZero = 1, "runSetsZero is 0 or 1."

    .scope Statements continued

    ;; Discards the program and falls into the variable and stack reset.
    ;; See: <ClearVariables>, <EraseProgram>
    ;; Also: SCRATH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc New
    bne FindLine::Done
    .endproc
    .endscope

    ;; Stores a zero link at <ProgramStart>, sets <VariablesStart> to <ProgramStart> + 2; falls into <ResetProgramState>.
    ;; Also: SCRTCH (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EraseProgram
    lda #$00
    .if resetLock
        sta LOCK
    .endif
    tay
    sta (ProgramStart),y
    iny
    sta (ProgramStart),y
    lda ProgramStart
    .if clearCarry
        clc
    .endif
    adc #$02
    sta VariablesStart
    .if mirrorEnd
        sta PRGEND
    .endif
    lda ProgramStart+1
    adc #$00
    sta VariablesStart+1
    .if mirrorEnd
        sta PRGEND+1
    .endif
    .endproc

    ;; Positions the text pointer before the program and clears variables and execution state.
    ;; See: <RewindTextPointer>, <ClearVariables>
    ;; Also: RUNC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ResetProgramState
    jsr RewindTextPointer
    .if runSetsZero
        lda #$00
    .endif
    .endproc
.endmacro

;; Emits the CLEAR statement entry.
;; Parameters: returnEntry = return instruction used when the statement has trailing text
.macro ClearStatement returnEntry
    .scope Statements continued

    ;; Discards variables and execution state, retaining the program text.
    ;; See: <ClearVariables>
    ;; Also: CLEAR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Clear
    bne returnEntry
    .endproc
    .endscope

.endmacro

;; Emits the NULL statement entry and its error jump.
;; Parameters: incrementedLimit = first rejected incremented value
.macro NullStatement incrementedLimit
    .assert incrementedLimit >= 2 && incrementedLimit <= 255, "incrementedLimit is 2 through 255."

    .scope Statements continued

    ;; Sets the number of null characters printed after a line ending.
    ;;
    ;; The comparison is made after incrementing X: values from zero through incrementedLimit - 2 pass, as does
    ;; 255 because the increment wraps. Some builds retain this entry without exposing a NULL token.
    ;; Errors: ILLEGAL QUANTITY for other byte values
    ;; See: <GETBYT>
    ;; Also: NULL (M6502, HV1, HV1R)
    .proc Null
    jsr GETBYT
    bne Cont::Done
    inx
    cpx #incrementedLimit
    bcs ToIllegalQuantity
    dex
    stx NULCNT
    rts
;; Jmp FCERR.
;; Also: FCERR1 (M6502, HV1, HV1R)
ToIllegalQuantity:
    jmp FCERR
    .endproc
    .endscope

.endmacro

;; Emits the common variable, DATA and string reset.
;; Parameters: closeFiles = 1 to close the operating system's open files;
;;   clearDiskStatus = 1 to clear the disk-status descriptor
.macro ClearStorage closeFiles, clearDiskStatus
    .assert closeFiles = 0 || closeFiles = 1, "closeFiles is 0 or 1."
    .assert clearDiskStatus = 0 || clearDiskStatus = 1, "clearDiskStatus is 0 or 1."

    ;; Resets string, variable and array storage, then falls into the DATA and stack reset.
    ;; See: <ResetStack>, <Statements::Restore>
    ;; Also: CLEARC (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ClearVariables
    lda MemoryTop
    ldy MemoryTop+1
    sta StringsBottom
    sty StringsBottom+1
    .if clearDiskStatus
        lda #$00
        sta DSDESC
    .endif
    .if closeFiles
        jsr CQCALL
    .endif
    lda VariablesStart
    ldy VariablesStart+1
    sta ArraysStart
    sty ArraysStart+1
    sta ArraysEnd
    sty ArraysEnd+1
;; Jsr Statements::Restore; falls into <ResetStack>.
;; Also: FLOAD (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
RestoreData:
    jsr Statements::Restore
    .endproc
.endmacro

;; Emits the stack reset and text-pointer positioning entries.
;; Parameters: earlyStack = 1 to store the return address before moving the stack pointer;
;;   paddedReturn = 1 to retain the extra RTS and unused byte before <ResetStack::Done>;
;;   stackTop = the new stack-pointer byte
.macro ExecutionReset earlyStack, paddedReturn, stackTop
    .assert earlyStack = 0 || earlyStack = 1, "earlyStack is 0 or 1."
    .assert paddedReturn = 0 || paddedReturn = 1, "paddedReturn is 0 or 1."
    .assert stackTop >= 0 && stackTop <= 255, "stackTop must fit in a byte."

    ;; Discards FOR and GOSUB frames while preserving the return address and freeing string temporaries.
    ;;
    ;; <SubscriptMode> is cleared and CONT is disabled. The early stack sequence stores the return address before
    ;; moving the stack pointer; an interrupt in between can overwrite it.
    ;; Entry:
    ;;   Done = The rts; LIST and CLEAR return through it for a syntax error
    ;; See: <FindForFrame>, <Statements::Cont>
    ;; Also: STKINI (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ResetStack
    ldx #TemporaryDescriptors
    stx NextTemporary
    pla
    .if earlyStack
        sta STACK_END-2
        pla
        sta STACK_END-1
        ldx #stackTop
        txs
    .else
        tay
        pla
        ldx #stackTop
        txs
        pha
        tya
        pha
    .endif
    lda #$00
    sta StoppedText+1
    sta SubscriptMode
    .if paddedReturn
        rts
        .byte $51
    .endif
;; The rts; LIST and CLEAR return through it for a syntax error.
;; Also: STKRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Sets <TextPointer> to one byte before <ProgramStart>.
    ;; Also: STXTPT (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc RewindTextPointer
    clc
    lda ProgramStart
    adc #$FF
    sta TextPointer
    lda ProgramStart+1
    adc #$FF
    sta TextPointer+1
    rts
    .endproc
.endmacro
