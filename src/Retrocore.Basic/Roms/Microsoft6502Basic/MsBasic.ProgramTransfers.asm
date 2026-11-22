; MICROSOFT 6502 BASIC: RUN, GOSUB, GOTO AND RETURN
;
; RUN through RETURN are emitted consecutively before DATA. RESTORE and STOP/CONT can be separated by a
; platform's interrupt handling. The macros select their platform-specific entry points and early quirks.

;; Emits the RESTORE entry.
.macro RESTORE_DATA
;; Positions the DATA reader before the first program line.
;; See: <READ>, <DATPTR>
RESTOR:
    sec
    lda TXTTAB
    sbc #$01
    ldy TXTTAB+1
    bcs RESFIN
    dey
RESFIN:
    sta DATPTR
    sty DATPTR+1
ISCRTS:
    rts
.endmacro

;; Emits STOP, END and CONT.
;; Parameters: lineNumberDirect = 1 to detect direct execution through <CURLIN>, 0 through the text-pointer page;
;;   clearOutput = 1 to clear the output-suppression flag before reporting a break
.macro STOP_AND_CONTINUE lineNumberDirect, clearOutput
    .assert lineNumberDirect = 0 || lineNumberDirect = 1, "lineNumberDirect is 0 or 1."
    .assert clearOutput = 0 || clearOutput = 1, "clearOutput is 0 or 1."

;; Saves the program position and reports BREAK; END stops without the message.
;; See: <END>, <CONT>
STOP:
    bcs STOPC
END:
    clc
STOPC:
    bne CONTRT
    lda TXTPTR
    ldy TXTPTR+1
.if lineNumberDirect
    ldx CURLIN+1
    inx
.endif
    beq DIRIS
    sta OLDTXT
    sty OLDTXT+1
STPEND:
    lda CURLIN
    ldy CURLIN+1
    sta OLDLIN
    sty OLDLIN+1
DIRIS:
    pla
    pla
ENDCON:
    lda #<BRKTXT
    ldy #>BRKTXT
.if clearOutput
    ldx #$00
    stx CNTWFL
.endif
    bcc GORDY
    jmp ERRFIN
GORDY:
    jmp READY

;; Resumes at the saved line and text position, or reports CAN'T CONTINUE.
;; See: <STOP>, <STKINI>
CONT:
    bne CONTRT
    ldx #ERRCN
    ldy OLDTXT+1
    bne CONT1
    jmp ERROR
CONT1:
    lda OLDTXT
    sta TXTPTR
    sty TXTPTR+1
    lda OLDLIN
    ldy OLDLIN+1
    sta CURLIN
    sty CURLIN+1
CONTRT:
    rts
.endmacro

;; Emits the <RUN> statement entry.
;; Parameters: runLabel = 1 to define the additional RUN1 entry
.macro RUN_STATEMENT runLabel
    .assert runLabel = 0 || runLabel = 1, "runLabel must be 0 or 1."

;; Clears variables and runs from the beginning or the specified line.
;; In: zero = set when no line number follows
;; See: <RUNC>, <CLEARC>, <RUNC2>
RUN:
    bne *+5
    jmp RUNC
.if runLabel
RUN1:
.endif
    jsr CLEARC
    jmp RUNC2
.endmacro

;; Emits the <GOSUB> and <GOTO> entries.
;; Parameters: nextStatement = entry that resumes the statement loop after the transfer
.macro GOSUB_AND_GOTO nextStatement

;; Saves the caller and transfers to its target line.
;;
;; From low to high addresses the five-byte stack frame holds <GOSUTK>, the current line number and the text
;; pointer still pointing before the target number. <RETURN> later skips the saved number.
;; See: <GOTO>, <GETSTK>
GOSUB:
    lda #$03
    jsr GETSTK
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    lda CURLIN+1
    pha
    lda CURLIN
    pha
    lda #GOSUTK
    pha
RUNC2:
    jsr CHRGOT
    jsr GOTO
    jmp nextStatement

;; Finds the requested line and points <TXTPTR> just before its link field.
;;
;; A forward jump can start its search after the current line; otherwise it starts at <TXTTAB>.
;; Errors: UNDEF'D STATEMENT if the line is absent
;; See: <LINGET>, <FNDLNC>
GOTO:
    jsr LINGET
    jsr REMN
    lda CURLIN+1
    cmp LINNUM+1
    bcs LUK4IT
    tya
    sec
    adc TXTPTR
    ldx TXTPTR+1
    bcc LUKALL
    inx
    bcs LUKALL
LUK4IT:
    lda TXTTAB
    ldx TXTTAB+1
LUKALL:
    jsr FNDLNC
QFOUND:
    bcc USERR
    lda LOWTR
    sbc #$01
    sta TXTPTR
    lda LOWTR+1
    sbc #$00
    sta TXTPTR+1
GORTS:
    rts
.endmacro

;; Emits the <RETURN> entry.
;; Parameters: searchLow = 1 to set <FORPNT>'s low byte before searching, 0 to set its high byte;
;;   popEntry = 1 to include the POP test and unwind branch
.macro RETURN_STATEMENT searchLow, popEntry
    .assert searchLow = 0 || searchLow = 1, "searchLow must be 0 or 1."
    .assert popEntry = 0 || popEntry = 1, "popEntry must be 0 or 1."

;; Searches past FOR frames and restores the <GOSUB> caller's line and text position.
;;
;; The earlier search sets the low byte of <FORPNT> to $FF; later versions set the high byte instead.
;; The earlier code can still match a FOR variable ending in $FF, or select the first frame if the
;; previous high byte is zero.
;; Errors: RETURN WITHOUT GOSUB if there is no GOSUB frame
;; See: <GOSUB>, <FNDFOR>
RETURN:
    bne GORTS
    lda #$FF
    sta FORPNT+1-searchLow
    jsr FNDFOR
    txs
    cmp #GOSUTK
    beq RETU1
    ldx #ERRRG
    .byte $2C                   ; BIT absolute skips the following LDX on the RETURN error path
USERR:
    ldx #ERRUS
    jmp ERROR
SNERR2:
    jmp SNERR
RETU1:
    pla
    pla
.if popEntry
    cpy #((POPTK-ENDTK)*2)
    beq REMER1
.endif
    sta CURLIN
    pla
    sta CURLIN+1
    pla
    sta TXTPTR
    pla
    sta TXTPTR+1
.endmacro
