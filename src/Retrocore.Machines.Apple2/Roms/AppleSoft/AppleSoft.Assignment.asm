;; APPLESOFT: VARIABLE ASSIGNMENT
;;
;; LET evaluates an expression and assigns it to a variable. INPUT and READ also use the
;; numeric and string assignment entries here.

;; LET: evaluates and assigns an expression to a numeric or string variable.
;; See: <PTRGET>, <QINTGR>, <INPCOM>
LET:
    jsr PTRGET
    sta FORPNT
    sty FORPNT+1
    lda #EQULTK
    jsr SYNCHR
    lda INTFLG
    pha
    lda VALTYP
    pha
    jsr FRMEVL
    pla
    rol a
    jsr CHKVAL
    bne COPSTR
COPNUM:
    pla

;; Stores the numeric <FAC> in the variable at <FORPNT>, choosing integer or floating-point storage.
;; In: A = integer flag
QINTGR:
    bpl COPFLT
    jsr ROUND
    jsr AYINT
    ldy #$00
    lda FACMO
    sta (FORPNT),y
    iny
    lda FACLO
    sta (FORPNT),y
    rts
COPFLT:
    jmp MOVVF
COPSTR:
    pla

;; Assigns the string descriptor at <FACMO> to the variable at <FORPNT>, copying its contents if necessary.
;; See: <STRINI>, <FRETMS>
INPCOM:
GETSPT:
    ldy #$02
    lda (FACMO),y
    cmp FRETOP+1
    bcc DNTCPY
    bne QVARIA
    dey
    lda (FACMO),y
    cmp FRETOP
    bcc DNTCPY
QVARIA:
    ldy FACLO
    cpy VARTAB+1
    bcc DNTCPY
    bne COPY
    lda FACMO
    cmp VARTAB
    bcs COPY
DNTCPY:
    lda FACMO
    ldy FACLO
    jmp COPYZC
COPY:
    ldy #$00
    lda (FACMO),y
    jsr STRINI
    lda DSCPNT
    ldy DSCPNT+1
    sta STRNG1
    sty STRNG1+1
    jsr MOVINS
    lda #$9D
    ldy #$00
COPYZC:
    sta DSCPNT
    sty DSCPNT+1
    jsr FRETMS
    ldy #$00
    lda (DSCPNT),y
    sta (FORPNT),y
    iny
    lda (DSCPNT),y
    sta (FORPNT),y
    iny
    lda (DSCPNT),y
    sta (FORPNT),y
    rts
