;; APPLESOFT: ERRORS, COMMAND INPUT AND PROGRAM STORAGE
;;
;; Error reporting and the command loop, line editing and tokenization, program-line search and insertion,
;; and the NEW and CLEAR paths. Statement execution continues in <NEWSTT>.

;; Reports an OUT OF MEMORY error.
OMERR:
    ldx #ERROM

;; Dispatches to an active ONERR handler or prints the selected error and returns to the command loop.
;;
;; The high bit marks the last character of each message in <ERRTAB>. After the message, <STKINI> clears
;; execution state and the line number is printed unless the error occurred in direct mode.
;; In: X = error-table offset
ERROR:
    bit ERRFLG
    bpl ERROR1
    jmp HANDLE
ERROR1:
    jsr CRDO
    jsr OUTQST
GETERR:
    lda ERRTAB,x
    pha
    jsr OUTDO
    inx
    pla
    bpl GETERR
TYPERR:
    jsr STKINI
    lda #<ERR
    ldy #>ERR

;; Prints the zero-terminated message at A/Y and, in program mode, the current line number.
;; See: <ERROR>, <STOP>
ERRFIN:
    jsr STROUT
    ldy CURLIN+1
    iny
    beq READY
    jsr INPRT
READY:
;; Prompts for a command, executing a direct statement or inserting or deleting a numbered line.
;;
;; Editing an existing line first closes the gap. A replacement opens space with <BLTU>, then the program is
;; relinked and variables and execution state are reset. An empty numbered line deletes the old line.
;; See: <INLIN1>, <CRUNCH>, <FNDLIN>, <LNKPRG>
MAIN:
    jsr CRDO
    ldx #$DD
    jsr INLIN1
    stx TXTPTR
    sty TXTPTR+1
    lsr ERRFLG
    jsr CHRGET
    tax
    beq MAIN
    ldx #$FF
    stx CURLIN+1
    bcc READY1
    jsr CRUNCH
    jmp TRCLIN
READY1:
    ldx PRGEND
    stx VARTAB
    ldx PRGEND+1
    stx VARTAB+1
MAIN1:
    jsr LINGET
    jsr CRUNCH
    sty COUNT
    jsr FNDLIN
    bcc NODEL
    ldy #$01
    lda (LOWTR),y
    sta INDEX+1
    lda VARTAB
    sta INDEX
    lda LOWTR+1
    sta INDEX2+1
    lda LOWTR
    dey
    sbc (LOWTR),y
    clc
    adc VARTAB
    sta VARTAB
    sta INDEX2
    lda VARTAB+1
    adc #$FF
    sta VARTAB+1
    sbc LOWTR+1
    tax
    sec
    lda LOWTR
    sbc VARTAB
    tay
    bcs QDECT1
    inx
    dec INDEX2+1
QDECT1:
    clc
    adc INDEX
    bcc MLOOP
    dec INDEX+1
    clc
MLOOP:
    lda (INDEX),y
    sta (INDEX2),y
    iny
    bne MLOOP
    inc INDEX+1
    inc INDEX2+1
    dex
    bne MLOOP
NODEL:
    lda BUF
    beq FINI
    lda MEMSIZ
    ldy MEMSIZ+1
    sta FRETOP
    sty NCMWID
    lda VARTAB
    sta HIGHTR
    adc COUNT
    sta HIGHDS
    ldy VARTAB+1
    sty HIGHTR+1
    bcc NODELC
    iny
NODELC:
    sty HIGHDS+1
    jsr BLTU
    lda LINNUM
    ldy LINNUM+1
    sta BUF-2
    sty BUF-1
    lda STREND
    ldy STREND+1
    sta VARTAB
    sty VARTAB+1
    ldy COUNT
NODEL1:
    lda BUF-5,y
    dey
    sta (LOWTR),y
    bne NODEL1

;; Clears execution state and relinks the program after editing or loading it.
FINI:
    jsr RUNC

;; Rebuilds the linked program line addresses, then records <VARTAB> as <PRGEND> and returns to the prompt.
;;
;; Each line ends in zero; the next line starts immediately after it. A zero link marks the end of the program.
LNKPRG:
    lda TXTTAB
    ldy TXTTAB+1
    sta INDEX
    sty INDEX+1
    clc
CHEAD:
    ldy #$01
    lda (INDEX),y
    bne CHEAD1
    lda VARTAB
    sta PRGEND
    lda VARTAB+1
    sta PRGEND+1
    jmp MAIN
CHEAD1:
    ldy #$04
CZLOOP:
    iny
    lda (INDEX),y
    bne CZLOOP
    iny
    tya
    adc INDEX
    tax
    ldy #$00
    sta (INDEX),y
    lda INDEX+1
    adc #$00
    iny
    sta (INDEX),y
    stx INDEX
    sta INDEX+1
    bcc CHEAD

;; Reads a line through the Monitor without printing a prompt character.
;;
;; The terminating byte is replaced with zero, the input is limited to 239 characters, and bit 7 is cleared
;; from each character. X/Y return the address immediately before <BUF>.
;; Entry: INLIN1 = uses X as the Monitor prompt character
;; Out: A = 0, X = $FF, Y = $01
;; See: <GETLN>, <INCHR>
INLIN:
    ldx #$80
INLIN1:
    stx PROMPT
    jsr GETLN
    cpx #$EF
    bcc GDBUFS
    ldx #$EF
GDBUFS:
    lda #$00
    sta BUF,x
    txa
    beq NOCHR
LOPBHT:
    lda BUF-1,x
    and #$7F
    sta BUF-1,x
    dex
    bne LOPBHT
NOCHR:
    lda #$00
    ldx #$FF
    ldy #$01
    rts

;; Reads one character through the Monitor and clears its high bit.
;; Out: A = character with bit 7 clear
INCHR:
    jsr CQINCH
    and #$7F
INCRTS:
    rts
BUFOFS .set $0000
BUFOFS .set $0200

;; Tokenizes the line in <BUF>, replacing reserved words by their single-byte tokens from <RESLST>.
;;
;; Spaces outside literals and DATA are discarded. Quoted strings, DATA fields and REM text are copied without
;; tokenization; ? abbreviates PRINT. Enhanced IIe folds case outside quoted strings and DATA. AT is not matched
;; when followed by N or O, allowing ATN and TO to be recognized.
;; Out: TXTPTR = address before the tokenized line, Y = encoded line length including its header
;; See: <LIST>
CRUNCH:
    ldx TXTPTR
    dex
    ldy #$04
    sty DORES
    bit LOCK
    bpl CRUNC1
    pla
    pla
    jsr RUNC
    jmp NXTCO1
CRUNC1:
    inx
KLOOP:
.if ENHNCD
    jsr UPCASE
.else
    lda BUF,x
.endif
    bit DORES
    bvs CMPSP1
CMPSPC:
    cmp #' '
    beq CRUNC1
CMPSP1:
    sta ENDCHR
    cmp #'"'
    beq STRNG
    bvs STUFFH
    cmp #'?'
    bne KLOOP1
    lda #PRINTK
    bne STUFFH
KLOOP1:
    cmp #'0'
    bcc MUSTCR
    cmp #$3C
    bcc STUFFH
MUSTCR:
    sty BUFPTR
    lda #<(RESLST-256)
    sta FAC
    lda #>(RESLST-256)
    sta FACHO
    ldy #$00
    sty COUNT
    dey
    stx TXTPTR
    dex
RESER:
    iny
    bne RESPUL
    inc FACHO
RESPUL:
    inx
RESPU1:
.if ENHNCD
    jsr UPCASE
.else
    lda BUF,x
.endif
    cmp #' '
    beq RESPUL
    sec
    sbc (FAC),y
    beq RESER
    cmp #$80
    bne NTHIS
    ora COUNT
    cmp #ATTK
    bne GETBPT
.if ENHNCD
    jsr UPNXT
.else
    lda BUF+1,x
.endif
    cmp #'N'
    beq NTHIS
    cmp #'O'
    beq NTHIS
    lda #ATTK
GETBPT:
    ldy BUFPTR
STUFFH:
    inx
    iny
    sta BUF-5,y
    lda BUF-5,y
    beq CRDONE
    sec
    sbc #':'
    beq COLIS
    cmp #(DATATK-':')
    bne NODATT
COLIS:
    sta DORES
NODATT:
    sec
    sbc #(REMTK-':')
    bne KLOOP
    sta ENDCHR
STR1:
.if ENHNCD
    jsr UPCASE
.else
    lda BUF,x
.endif
    beq STUFFH
    cmp ENDCHR
    beq STUFFH
STRNG:
    iny
    sta BUF-5,y
    inx
    bne STR1
NTHIS:
    ldx TXTPTR
    inc COUNT
NTHIS2:
    lda (FAC),y
NTHIS1:
    iny
    bne NTHIS3
    inc FACHO
NTHIS3:
    asl a
    bcc NTHIS2
    lda (FAC),y
    bne RESPU1
.if ENHNCD
    jsr UPBUF
.else
    lda BUF,x
.endif
    bpl GETBPT
CRDONE:
    sta BUF-3,y
    dec TXTPTR+1
    lda #$FF
    sta TXTPTR
LISTRT:
    rts

;; Finds the stored program line equal to or immediately after <LINNUM>.
;; In: LINNUM = line number to find
;; Out: LOWTR = link field of the matching or following line or the end marker, carry = set for an exact match
;; Entry: FNDLNC = searches from the line at A (low) and X (high)
FNDLIN:
    lda TXTTAB
    ldx TXTTAB+1
FNDLNC:
    ldy #$01
    sta LOWTR
    stx LOWTR+1
    lda (LOWTR),y
    beq FLINRT
    iny
    iny
    lda LINNUM+1
    cmp (LOWTR),y
    bcc FLNRTS
    beq FNDLO1
    dey
    bne AFFRTS
FNDLO1:
    lda LINNUM
    dey
    cmp (LOWTR),y
    bcc FLNRTS
    beq FLNRTS
AFFRTS:
    dey
    lda (LOWTR),y
    tax
    dey
    lda (LOWTR),y
    bcs FNDLNC
FLINRT:
    clc
FLNRTS:
    rts

;; NEW: discards the program and falls into the variable and stack reset.
;; See: <CLEAR>, <SCRTCH>
NEW:
SCRATH:
    bne FLNRTS
SCRTCH:
    lda #$00
    sta LOCK
    tay
    sta (TXTTAB),y
    iny
    sta (TXTTAB),y
    lda TXTTAB
    adc #$02
    sta VARTAB
    sta PRGEND
    lda TXTTAB+1
    adc #$00
    sta VARTAB+1
    sta PRGEND+1

;; Resets the text pointer to before the program and clears variables and execution state.
;; See: <STXTPT>, <CLEARC>
RUNC:
    jsr STXTPT
    lda #$00
;; CLEAR: discards variables, restores DATA and clears the execution stack, retaining program text.
;; See: <CLEARC>, <STKINI>
CLEAR:
    bne STKRTS

;; Resets string, variable and array storage, then falls into the DATA and stack reset.
CLEARC:
    lda MEMSIZ
    ldy MEMSIZ+1
    sta FRETOP
    sty FRETOP+1
    lda VARTAB
    ldy VARTAB+1
    sta ARYTAB
    sty ARYTAB+1
    sta STREND
    sty STREND+1
FLOAD:
    jsr RESTOR

;; Resets the stack while preserving the return address, frees string temporaries and disables CONT.
;;
;; FOR and GOSUB contexts are discarded and <SUBFLG> is cleared.
;; See: <FNDFOR>, <CONT>
STKINI:
    ldx #TEMPST
    stx TEMPPT
    pla
    tay
    pla
    ldx #$F8
    txs
    pha
    tya
    pha
    lda #$00
    sta OLDTXT+1
    sta SUBFLG
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
