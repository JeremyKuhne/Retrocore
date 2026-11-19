;; APPLESOFT: STATEMENT DISPATCH AND CONTROL FLOW
;;
;; The statement dispatcher, FOR and GOSUB frames, program transfers and cassette commands. The FOR stack
;; search and NEXT are in other modules; LET and PRINT follow in AppleSoft.Assignment.asm and AppleSoft.Print.asm.

;; FOR: assigns the initial value and builds a loop frame, replacing an earlier FOR for the same variable.
;;
;; From low to high addresses the <FORSIZ>-byte frame holds <FORTK>, the variable address, the five-byte step, its
;; sign, the five-byte packed limit, the line number and the text pointer after the FOR statement.
;; See: <FNDFOR>, <FORPSH>, <NEXT>
FOR:
    lda #$80
    sta SUBFLG
    jsr LET
    jsr FNDFOR
    bne NOTOL
    txa
    adc #(FORSIZ-3)
    tax
    txs
NOTOL:
    pla
    pla
    lda #$09
    jsr GETSTK
    jsr DATAN
    clc
    tya
    adc TXTPTR
    pha
    lda TXTPTR+1
    adc #$00
    pha
    lda CURLIN+1
    pha
    lda CURLIN
    pha
    lda #TOTK
    jsr SYNCHR
    jsr CHKNUM
    jsr FRMNUM
    lda FACSGN
    ora #$7F
    and FACHO
    sta FACHO
    lda #<LDFONE
    ldy #>LDFONE
    sta INDEX
    sty INDEX+1
    jmp FORPSH
LDFONE:
    lda #<FONE
    ldy #>FONE
    jsr MOVFM
    jsr CHRGOT
    cmp #STEPTK
    bne ONEON
    jsr CHRGET
    jsr FRMNUM
ONEON:
    jsr SIGN
    jsr PUSHF
    lda FORPNT+1
    pha
    lda FORPNT
    pha
NXTCON:
    lda #FORTK
    pha
NXTCO1:
    tsx
    stx REMSTK

;; Runs the next statement or advances to the next linked line, checking for Control-C first.
;;
;; Saves the current text position for CONT while running a program. Trace mode prints each line number.
;; See: <GONE>, <ISCNTC>, <CONT>
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
; CHRGET leaves carry set for a non-digit; a digit here is a syntax error.
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

;; RESTORE: positions the DATA reader before the first program line.
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

;; Checks the keyboard for Control-C without consuming any other key.
;; See: <ISCCA1>, <STOP>
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

;; STOP: saves the program position and reports BREAK; END stops without the message.
;; See: <END>, <CONT>
STOP:
    bcs STOPC
END:
    clc
STOPC:
    bne CONTRT
    lda TXTPTR
    ldy TXTPTR+1
    ldx CURLIN+1
    inx
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
    bcc GORDY
    jmp ERRFIN
GORDY:
    jmp READY

;; CONT: resumes at the saved line and text position, or reports CAN'T CONTINUE.
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

;; RUN: clears variables and runs from the beginning or the specified line.
;;
;; The statement entry decrements <CURLIN>+1 while preserving the incoming flags. A line argument enters
;; <RUNC2> after clearing state; without one, <RUNC> resets the text pointer to the start.
RUNSTM:
    php
    dec CURLIN+1
    plp
RUN:
    bne RUN1
    jmp RUNC
RUN1:
    jsr CLEARC
    jmp RUNC2
;; GOSUB: saves the caller and transfers to its target line.
;;
;; From low to high addresses its five-byte stack frame holds <GOSUTK>, the line number and the text pointer
;; still pointing before the target number. RETURN subsequently skips that number.
;; See: <RETURN>, <GOTO>
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
    jmp NXTCO1

;; GOTO: finds the requested line and points <TXTPTR> just before its link field.
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

;; POP: searches past FOR frames for the innermost GOSUB frame and discards it without transferring control.
POP:

;; RETURN: searches past FOR frames and restores the GOSUB caller's line and text position.
;; Errors: RETURN WITHOUT GOSUB if there is no GOSUB frame
;; See: <GOSUB>, <POP>
RETURN:
    bne GORTS
    lda #$FF
    sta FORPNT
    jsr FNDFOR
    txs
    cmp #GOSUTK
    beq RETU1
    ldx #ERRRG
    .byte $2C                       ; BIT absolute skips the following LDX on the RETURN error path
USERR:
    ldx #ERRUS
    jmp ERROR
SNERR2:
    jmp SNERR
RETU1:
    pla
    pla
    cpy #((POPTK-ENDTK)*2)
    beq REMER1
    sta CURLIN
    pla
    sta CURLIN+1
    pla
    sta TXTPTR
    pla
    sta TXTPTR+1

;; DATA: skips its fields up to an unquoted colon or end of line.
;; See: <DATAN>, <READ>
DATA:
    jsr DATAN

;; Advances <TXTPTR> by Y, to the terminator found by <DATAN> or <REMN>.
ADDON:
    tya
    clc
    adc TXTPTR
    sta TXTPTR
    bcc REMRTS
    inc TXTPTR+1
REMRTS:
    rts

;; Scans from <TXTPTR> to an unquoted colon or a zero byte, leaving the offset in Y.
;; See: <DATA>, <DATLOP>, <REMN>
DATAN:
    ldx #':'
    .byte $2C                       ; BIT absolute skips REMN's LDX

;; Scans from <TXTPTR> to the end-of-line zero, leaving its offset in Y.
REMN:
    ldx #$00
    stx CHARAC
    ldy #$00
    sty ENDCHR
EXCHQT:
    lda ENDCHR
    ldx CHARAC
    sta CHARAC
    stx ENDCHR
REMER:
    lda (TXTPTR),y
    beq REMRTS
    cmp ENDCHR
    beq REMRTS
    iny
    cmp #'"'
    bne REMER
    beq EXCHQT
REMER1:
    pla
    pla
    pla
    rts

;; IF: evaluates the condition; false skips the line, true executes the THEN statement or jumps to a line.
;; See: <REM>, <GOTO>, <GONE3>
IF:
    jsr FRMEVL
    jsr CHRGOT
    cmp #GOTOTK
    beq OKGOTO
    lda #THENTK
    jsr SYNCHR
OKGOTO:
    lda FAC
    bne DOCOND

;; REM: skips the rest of the line.
REM:
    jsr REMN
    beq ADDON
DOCOND:
    jsr CHRGOT
    bcs DOCO
    jmp GOTO
DOCO:
    jmp GONE3

;; ON: selects a one-based entry in a GOTO or GOSUB line-number list.
;;
;; If the selector exceeds the number of entries, execution continues after the list.
ON:
ONGOTO:
    jsr GETBYT
    pha
    cmp #GOSUTK
    beq ONGLOP
SNERR3:
    cmp #GOTOTK
    bne SNERR2
ONGLOP:
    dec FACLO
    bne ONGLP1
    pla
    jmp GONE2
ONGLP1:
    jsr CHRGET
    jsr LINGET
    cmp #','
    beq ONGLOP
    pla
ONGRTS:
    rts

;; Reads a decimal line number from the current text position, rejecting values at or above 64000.
;; In: A = current character, carry = clear for a digit
;; Out: LINNUM = line number, TXTPTR = terminating character, A = terminating character, carry = set
LINGET:
    ldx #$00
    stx LINNUM
    stx LINNUM+1
MORLIN:
    bcs ONGRTS
    sbc #'0'-1
    sta CHARAC
    lda LINNUM+1
    sta INDEX
    cmp #$19
    bcs SNERR3
    lda LINNUM
    asl a
    rol INDEX
    asl a
    rol INDEX
    adc LINNUM
    sta LINNUM
    lda INDEX
    adc LINNUM+1
    sta LINNUM+1
    asl LINNUM
    rol LINNUM+1
    lda LINNUM
    adc CHARAC
    sta LINNUM
    bcc NXTLGC
    inc LINNUM+1
NXTLGC:
    jsr CHRGET
    jmp MORLIN
