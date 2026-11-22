; MICROSOFT 6502 BASIC: NEW, CLEAR AND EXECUTION RESET
;
; These entries discard program or variable storage, reset the stack and position the text pointer. Callers
; choose the platform's side effects and the original or revised stack-reset sequence independently.

;; Emits the NEW and RUN reset entries.
;; Parameters: newAlias = 1 to define NEW at <SCRATH>; resetLock = 1 to clear LOCK;
;;   mirrorEnd = 1 to copy the new variable start to PRGEND; clearCarry = 1 to clear carry before adding two;
;;   runSetsZero = 1 to set zero before falling into the CLEAR entry
.macro PROGRAM_RESET newAlias, resetLock, mirrorEnd, clearCarry, runSetsZero
    .assert newAlias = 0 || newAlias = 1, "newAlias is 0 or 1."
    .assert resetLock = 0 || resetLock = 1, "resetLock is 0 or 1."
    .assert mirrorEnd = 0 || mirrorEnd = 1, "mirrorEnd is 0 or 1."
    .assert clearCarry = 0 || clearCarry = 1, "clearCarry is 0 or 1."
    .assert runSetsZero = 0 || runSetsZero = 1, "runSetsZero is 0 or 1."

.if newAlias
;; Discards the program and falls into the variable and stack reset.
;; See: <SCRATH>
NEW:
.endif
;; Discards the program and falls into the variable and stack reset.
;; See: <CLEARC>, <SCRTCH>
SCRATH:
    bne FLNRTS
SCRTCH:
    lda #$00
.if resetLock
    sta LOCK
.endif
    tay
    sta (TXTTAB),y
    iny
    sta (TXTTAB),y
    lda TXTTAB
.if clearCarry
    clc
.endif
    adc #$02
    sta VARTAB
.if mirrorEnd
    sta PRGEND
.endif
    lda TXTTAB+1
    adc #$00
    sta VARTAB+1
.if mirrorEnd
    sta PRGEND+1
.endif

;; Positions the text pointer before the program and clears variables and execution state.
;; See: <STXTPT>, <CLEARC>
RUNC:
    jsr STXTPT
.if runSetsZero
    lda #$00
.endif
.endmacro

;; Emits the CLEAR statement entry.
;; Parameters: returnEntry = return instruction used when the statement has trailing text
.macro CLEAR_STATEMENT returnEntry
;; Discards variables and execution state, retaining the program text.
;; See: <CLEARC>
CLEAR:
    bne returnEntry
.endmacro

;; Emits the NULL statement entry and its error jump.
;; Parameters: incrementedLimit = first rejected incremented value
.macro NULL_STATEMENT incrementedLimit
    .assert incrementedLimit >= 2 && incrementedLimit <= 255, "incrementedLimit is 2 through 255."

;; Sets the number of null characters printed after a line ending.
;;
;; The comparison is made after incrementing X: values from zero through incrementedLimit - 2 pass, as does
;; 255 because the increment wraps. Some builds retain this entry without exposing a NULL token.
;; Errors: ILLEGAL QUANTITY for other byte values
;; See: <GETBYT>
NULL:
    jsr GETBYT
    bne CONTRT
    inx
    cpx #incrementedLimit
    bcs FCERR1
    dex
    stx NULCNT
    rts
FCERR1:
    jmp FCERR
.endmacro

;; Emits the common variable, DATA and string reset.
;; Parameters: closeFiles = 1 to close the operating system's open files;
;;   clearDiskStatus = 1 to clear the disk-status descriptor
.macro CLEAR_STORAGE closeFiles, clearDiskStatus
    .assert closeFiles = 0 || closeFiles = 1, "closeFiles is 0 or 1."
    .assert clearDiskStatus = 0 || clearDiskStatus = 1, "clearDiskStatus is 0 or 1."

;; Resets string, variable and array storage, then falls into the DATA and stack reset.
;; See: <STKINI>, <RESTOR>
CLEARC:
    lda MEMSIZ
    ldy MEMSIZ+1
    sta FRETOP
    sty FRETOP+1
.if clearDiskStatus
    lda #$00
    sta DSDESC
.endif
.if closeFiles
    jsr CQCALL
.endif
    lda VARTAB
    ldy VARTAB+1
    sta ARYTAB
    sty ARYTAB+1
    sta STREND
    sty STREND+1
FLOAD:
    jsr RESTOR
.endmacro

;; Emits the stack reset and text-pointer positioning entries.
;; Parameters: earlyStack = 1 to store the return address before moving the stack pointer;
;;   paddedReturn = 1 to retain the extra RTS and unused byte before <STKRTS>;
;;   stackTop = the new stack-pointer byte
.macro EXECUTION_RESET earlyStack, paddedReturn, stackTop
    .assert earlyStack = 0 || earlyStack = 1, "earlyStack is 0 or 1."
    .assert paddedReturn = 0 || paddedReturn = 1, "paddedReturn is 0 or 1."
    .assert stackTop >= 0 && stackTop <= 255, "stackTop must fit in a byte."

;; Discards FOR and GOSUB frames while preserving the return address and freeing string temporaries.
;;
;; <SUBFLG> is cleared and CONT is disabled. The early stack sequence stores the return address before
;; moving the stack pointer; an interrupt in between can overwrite it.
;; See: <FNDFOR>, <CONT>
STKINI:
    ldx #TEMPST
    stx TEMPPT
    pla
.if earlyStack
    sta STKEND-2
    pla
    sta STKEND-1
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
    sta OLDTXT+1
    sta SUBFLG
.if paddedReturn
    rts
    .byte $51
.endif
STKRTS:
    rts

;; Sets <TXTPTR> to one byte before <TXTTAB>.
STXTPT:
    clc
    lda TXTTAB
    adc #$FF
    sta TXTPTR
    lda TXTTAB+1
    adc #$FF
    sta TXTPTR+1
    rts
.endmacro
