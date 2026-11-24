;; APPLESOFT: STATEMENT DISPATCH AND CONTROL FLOW
;;
;; The statement dispatcher, FOR and GOSUB frames, program transfers and cassette commands. The FOR stack
;; search and NEXT are in other modules; LET and PRINT follow in AppleSoft.Assignment.asm and AppleSoft.Print.asm.

.include "../Microsoft6502Basic/MsBasic.For.asm"
.include "../Microsoft6502Basic/MsBasic.ProgramTransfers.asm"
.include "../Microsoft6502Basic/MsBasic.StatementFlow.asm"

NXTCO1:
    tsx
    stx REMSTK

;; Runs the next statement or advances to the next linked line, checking for Control-C first.
;;
;; Saves the current text position for CONT while running a program. Trace mode prints each line number.
;; See: <GONE>, <ISCNTC>, <Statements::Cont>
NEWSTT:
    jsr ISCNTC
    lda TXTPTR
    ldy TXTPTR+1
    ldx CURLIN+1
    inx
    beq DIRCON
    sta OLDTXT
    sty OLDTXT+1
DIRCON:
    ldy #$00
    lda (TXTPTR),y
    bne MORSTS
    ldy #$02
    lda (TXTPTR),y
    clc
    beq GONE1
    iny
    lda (TXTPTR),y
    sta CURLIN
    iny
    lda (TXTPTR),y
    sta CURLIN+1
    tya
    adc TXTPTR
    sta TXTPTR
    bcc TRCLIN
    inc TXTPTR+1
TRCLIN:
    bit TRCFLG
    bpl GONE
    ldx CURLIN+1
    inx
    beq GONE
    lda #'#'
    jsr OUTDO
    ldx CURLIN
    lda CURLIN+1
    jsr LINPRT
    jsr OUTSPC

;; Advances past the separator and dispatches a statement using <STMDSP>, or treats a non-token as LET.
;; See: <NEWSTT>, <LET>
GONE:
    jsr CHRGET
    jsr GONE3
    jmp NXTCO1
GONE1:
    beq ENDCON
GONE3:
    beq ISCRTS
; GetNextCharacter leaves carry set for a non-digit; a digit here is a syntax error.
GONE2:
    sbc #ENDTK
    bcc GLET
    cmp #$40
    bcs SNERR1
    asl a
    tay
    lda STMDSP+1,y
    pha
    lda STMDSP,y
    pha
    jmp CHRGET
GLET:
    jmp LET
MORSTS:
    cmp #':'
    beq TRCLIN
SNERR1:
    jmp SNERR

    RestoreStatement

;; Checks the keyboard for Control-C without consuming any other key.
;; See: <ISCCA1>, <Statements::Stop>
ISCNTC:
    lda KBD
    cmp #$83
    beq ISCCAP
    rts
ISCCAP:
    jsr INCHR

;; Handles Control-C, passing error code $FF to an active ONERR handler.
ISCCA1:
    ldx #$FF
    bit ERRFLG
    bpl ISCCA2
    jmp HANDLE
ISCCA2:
    cmp #$03

    StopAndContinue 1, 0

;; SAVE: writes the program length and program text to cassette through the Monitor.
;; See: <LOAD>, <VARTIO>, <PROGIO>
SAVE:
    sec
    lda PRGEND
    sbc TXTTAB
    sta POKER
    lda PRGEND+1
    sbc TXTTAB+1
    sta POKER+1
    jsr VARTIO
    jsr MWRITE
    jsr PROGIO
    jmp MWRITE

;; LOAD: reads a cassette program, then resets and relinks it unless the lock flag is set.
;; See: <SAVE>, <FINI>
LOAD:
    jsr VARTIO
    jsr MREAD
    clc
    lda TXTTAB
    adc POKER
    sta VARTAB
    lda TXTTAB+1
    adc POKER+1
    sta VARTAB+1
    lda TEMPPT
    sta LOCK
    jsr PROGIO
    jsr MREAD
    bit LOCK
    bpl LOAD1
    jmp RUNC
LOAD1:
    jmp FINI

;; Sets the Monitor cassette range to the two-byte program length at <POKER>, and clears <LOCK>.
VARTIO:
    lda #<POKER
    ldy #$00
    sta A1L
    sty A1H
    lda #<(POKER+2)
    sta A2L
    sty A2H
    sty LOCK
    rts

;; Sets the Monitor cassette range to the program from <TXTTAB> through <VARTAB>.
PROGIO:
    lda TXTTAB
    ldy TXTTAB+1
    sta A1L
    sty A1H
    lda VARTAB
    ldy VARTAB+1
    sta A2L
    sty A2H
    rts

;; Decrements <CURLIN>+1 while preserving the incoming flags before <Statements::Run>.
RUNSTM:
    php
    dec CURLIN+1
    plp
    RunStatement
    GosubAndGoto NXTCO1

;; POP: searches past FOR frames for the innermost GOSUB frame and discards it without transferring control.
POP:
    ReturnStatement 1, 1

    StatementScan 0, 1
    ConditionalStatements

;; ON: selects a one-based entry in a GOTO or GOSUB line-number list.
ON:
    OnStatement

.include "../Microsoft6502Basic/MsBasic.LineNumber.asm"
