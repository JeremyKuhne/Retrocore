;; APPLESOFT: PROGRAM LISTING
;;
;; LIST walks the program's linked lines and expands their tokens using <RESLST>. The execution code that
;; follows this module begins with FOR, not with a continuation of the lister.

;; LIST: prints the requested range of stored lines, or all lines when no range is given.
;;
;; A hyphen or comma separates the bounds; a single number selects just that line. A zero upper bound, including
;; an omitted upper bound after a separator, becomes $FFFF. The enhanced IIe uses screen-width-aware helpers.
;; See: <LINGET>, <FNDLIN>, <ISCNTC>, <RESLST>
LIST:
    bcc GOLST
    beq GOLST
    cmp #MINUTK
    beq GOLST
    cmp #','
    bne STKRTS
GOLST:
    jsr LINGET
    jsr FNDLIN
    jsr CHRGOT
    beq LSTEND
    cmp #MINUTK
    beq GOLST1
    cmp #','
    bne FLNRTS
GOLST1:
    jsr CHRGET
    jsr LINGET
    bne STKRTS
LSTEND:
    pla
    pla
    lda LINNUM
    ora LINNUM+1
    bne LIST4
    lda #$FF
    sta LINNUM
    sta LINNUM+1

; LOWTR points to the link and line number of the next line.
LIST4:
    ldy #$01
    lda (LOWTR),y
    beq GRODY
    jsr ISCNTC
    jsr CRDO
    iny
    lda (LOWTR),y
    tax
    iny
    lda (LOWTR),y
    cmp LINNUM+1
    bne TSTDUN
    cpx LINNUM
    beq TYPLIN
TSTDUN:
    bcs GRODY
TYPLIN:
    sty LSTPNT
.if ENHNCD
    jsr SPCLIN
.else
    jsr LINPRT
.endif
    lda #' '
PRIT4:
    ldy LSTPNT
    and #$7F
PLOOP:
    jsr OUTDO
.if ENHNCD
    jsr CHKCOL
    nop
.else
    lda TRMPOS
    cmp #$21
.endif
    bcc PLOOP1
    jsr CRDO
    lda #$05
    sta TRMPOS
PLOOP1:
    iny
    lda (LOWTR),y
    bne QPLOP
    tay
    lda (LOWTR),y
    tax
    iny
    lda (LOWTR),y
    stx LOWTR
    sta LOWTR+1
    bne LIST4

; End the listing and return to the statement loop.
GRODY:
    lda #$0D
    jsr OUTDO
    jmp NXTCO1

;; Advances Y through <RESLST>, carrying into the table pointer, and reads the next byte.
;; In: FAC = table pointer, Y = offset before the next character
;; Out: A = table byte, Y = advanced offset
GRODY1:
    iny
    bne GRODY2
    inc FACHO
GRODY2:
    lda (FAC),y
    rts

; Ordinary characters print directly; high-bit token bytes index the reserved-word table.
QPLOP:
    bpl PLOOP
    sec
    sbc #$7F
    tax
    sty LSTPNT
    ldy #<(RESLST-256)
    sty FAC
    ldy #>(RESLST-256)
    sty FACHO
    ldy #$FF
RESRCH:
    dex
    beq PRIT3
RESCR1:
    jsr GRODY1
    bpl RESCR1
    bmi RESRCH
PRIT3:
    lda #' '
    jsr OUTDO
PRIT31:
    jsr GRODY1
    bmi PRIT32
    jsr OUTDO
    bne PRIT31
PRIT32:
    jsr OUTDO
    lda #' '
    bne PRIT4
