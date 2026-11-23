; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: PROGRAM LISTING
;;
;; These macros emit LIST's argument parser, linked-line walker and token expansion in that order. The
;; platform supplies the output and continuation entries and chooses the independent listing behaviors.

;; Emits the <LIST> argument parser.
;; Parameters: commaRange = 1 to accept a comma as well as a minus token between bounds;
;;   secondBoundReturn = return entry used when characters follow the upper bound
.macro LIST_RANGE commaRange, secondBoundReturn
    .assert commaRange = 0 || commaRange = 1, "commaRange must be 0 or 1."

;; Lists the selected stored lines, or all lines when no bound is supplied.
;;
;; A nonzero single number selects that line; a minus token introduces an upper bound. When selected, a
;; comma is also accepted. A zero upper bound, including an omitted one, becomes $FFFF. A valid command
;; discards the statement dispatcher's return address before listing; invalid trailing text returns to the dispatcher.
;; In: A = current character, carry = clear for a digit, zero = set for a null or colon
;; See: <LINGET>, <FNDLIN>, <LIST4>
LIST:
    bcc GOLST
    beq GOLST
    cmp #MINUTK
.if commaRange
    beq GOLST
    cmp #','
.endif
    bne STKRTS
GOLST:
    jsr LINGET
    jsr FNDLIN
    jsr CHRGOT
    beq LSTEND
    cmp #MINUTK
.if commaRange
    beq GOLST1
    cmp #','
.endif
    bne FLNRTS
.if commaRange
GOLST1:
.endif
    jsr CHRGET
    jsr LINGET
    bne secondBoundReturn
LSTEND:
    pla
    pla
    lda LINNUM
    ora LINNUM+1
    bne LIST4
    lda #$FF
    sta LINNUM
    sta LINNUM+1
.endmacro

;; Emits the line walker and its normal listing exit.
;; Parameters: trackQuotes = 1 to reset and complement <DORES> around quoted text;
;;   guardOffset = 1 to stop if a malformed line's byte offset wraps;
;;   columnMode = 0 for no lister wrap, 1 for the fixed column check, 2 for the width-aware helper;
;;   linePrinter = entry printing a line number in A (high) and X (low);
;;   finalCr = 1 to output a carriage return before resuming;
;;   resume = entry reached at the end of the listing
.macro LIST_LINES trackQuotes, guardOffset, columnMode, linePrinter, finalCr, resume
    .assert trackQuotes = 0 || trackQuotes = 1, "trackQuotes must be 0 or 1."
    .assert guardOffset = 0 || guardOffset = 1, "guardOffset must be 0 or 1."
    .assert columnMode >= 0 && columnMode <= 2, "columnMode must be 0, 1 or 2."
    .assert finalCr = 0 || finalCr = 1, "finalCr must be 0 or 1."

;; Displays linked lines through the inclusive upper bound.
;;
;; The stop check and newline precede the upper-bound comparison. A zero high byte in the next link
;; ends the listing. Quote tracking starts each line with <DORES> = 1 and complements it for each quote.
;; In: LOWTR = link field of the first line, LINNUM = inclusive upper bound
;; See: <ISCNTC>, <QPLOP>
LIST4:
    ldy #$01
.if trackQuotes
    sty DORES
.endif
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
    jsr linePrinter
    lda #' '
PRIT4:
    ldy LSTPNT
    and #$7F
PLOOP:
    jsr OUTDO
.if columnMode
.if trackQuotes
    pha
.endif
.if columnMode = 2
    jsr CHKCOL
    nop
.else
    lda TRMPOS
    cmp #$21
.endif
.if trackQuotes
    bcc LIST_QUOTE_CHECK
.else
    bcc PLOOP1
.endif
    jsr CRDO
    lda #$05
    sta TRMPOS
.if trackQuotes
LIST_QUOTE_CHECK:
    pla
.endif
.endif
.if trackQuotes
    cmp #'"'
    bne PLOOP1
    lda DORES
    eor #$FF
    sta DORES
.endif
PLOOP1:
    iny
.if guardOffset
    beq GRODY
.endif
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
GRODY:
.if finalCr
    lda #$0D
    jsr OUTDO
.endif
    jmp resume
.endmacro

;; Emits the page-carrying table reader used by the <FAC>-based token walker.
.macro LIST_TABLE_NEXT
    .assert FACHO = FAC+1, "The listing table pointer must occupy FAC and FACHO."

;; Advances the table offset, carrying into its pointer on wrap, and reads the byte.
;; In: FAC = two-byte table pointer, Y = offset before the next byte
;; Out: A = table byte, Y = advanced offset, FACHO = incremented when Y wraps,
;;   zero = set for a zero byte, negative = bit 7 of the byte
;; Keeps: X, carry
GRODY1:
    iny
    bne GRODY2
    inc FACHO
GRODY2:
    lda (FAC),y
    rts
.endmacro

;; Emits character handling and reserved-word expansion after <LIST_LINES>.
;;
;; Mode 0 indexes <RESLST> with an eight-bit Y; mode 1 walks it through <INDEX1>, with a special first-token
;; path and a signed X countdown; mode 2 uses <LIST_TABLE_NEXT> and the pointer in <FAC>. The line walker
;; and token expansion must use the same quote-tracking choice.
;; Parameters: tableMode = 0 for direct indexed, 1 for <INDEX1> indirect, 2 for <FAC> indirect with page carry;
;;   trackQuotes = 1 to print high-bit characters inside quotes literally;
;;   literalPi = 1 to print the PI character literally;
;;   spaceWords = 1 to output spaces before and after each expanded word
.macro LIST_TOKENS tableMode, trackQuotes, literalPi, spaceWords
    .assert tableMode >= 0 && tableMode <= 2, "tableMode must be 0, 1 or 2."
    .assert trackQuotes = 0 || trackQuotes = 1, "trackQuotes must be 0 or 1."
    .assert literalPi = 0 || literalPi = 1, "literalPi must be 0 or 1."
    .assert spaceWords = 0 || spaceWords = 1, "spaceWords must be 0 or 1."

;; Prints a stored character or expands a token using <RESLST>.
;;
;; The high bit marks the last byte of each reserved word. In direct mode Y wraps after 256 table bytes;
;; the two indirect modes can walk farther. Tokens are not checked against the end of the table.
;; In: A = nonzero stored byte, Y = offset in the current line, negative = bit 7 of A
;; See: <LIST4>, <OUTDO>
QPLOP:
    bpl PLOOP
.if literalPi
    cmp #PI
    beq PLOOP
.endif
.if trackQuotes
    bit DORES
    bmi PLOOP
.endif
.if tableMode = 1
    tax
    sty LSTPNT
    ldy #>RESLST
    sty INDEX1+1
    ldy #<RESLST
    sty INDEX1
    ldy #$00
    asl a
    beq PRIT3B
.else
    sec
    sbc #$7F
    tax
    sty LSTPNT
.if tableMode = 2
    ldy #<(RESLST-256)
    sty FAC
    ldy #>(RESLST-256)
    sty FACHO
.endif
    ldy #$FF
.endif
RESRCH:
    dex
.if tableMode = 1
    bpl PRIT3
.else
    beq PRIT3
.endif
RESCR1:
.if tableMode = 1
    inc INDEX1
    bne RESCR2
    inc INDEX1+1
RESCR2:
    lda (INDEX1),y
.elseif tableMode = 2
    jsr GRODY1
.else
    iny
    lda RESLST,y
.endif
    bpl RESCR1
    bmi RESRCH
PRIT3:
.if tableMode = 1
    iny
PRIT3B:
.endif
.if spaceWords
    lda #' '
    jsr OUTDO
.endif
.if spaceWords || tableMode = 2
PRIT31:
.endif
.if tableMode = 1
    lda (INDEX1),y
.elseif tableMode = 2
    jsr GRODY1
.else
    iny
    lda RESLST,y
.endif
.if spaceWords
    bmi PRIT32
    jsr OUTDO
.if tableMode = 1
    beq PRIT32
    iny
    jmp PRIT31
.else
    bne PRIT31
.endif
PRIT32:
    jsr OUTDO
    lda #' '
    bne PRIT4
.else
    bmi PRIT4
    jsr OUTDO
.if tableMode = 2
    bne PRIT31
.else
    bne PRIT3
.endif
.endif
.endmacro
