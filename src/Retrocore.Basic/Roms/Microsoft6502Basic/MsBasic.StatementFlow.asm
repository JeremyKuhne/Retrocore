; MICROSOFT 6502 BASIC: DATA, REM, IF AND ON
;
; The three macros are emitted consecutively before the line-number parser. The scanner can retain an earlier
; quote-branch ordering and an optional stack-unwind entry used by a platform's POP statement.

;; Emits the <DATA> entry and its scanners.
;; Parameters: quoteFirst = 1 to branch on a quote first, 0 to branch on a non-quote first;
;;   popExit = 1 to include the entry that removes three stack bytes for POP
.macro STATEMENT_SCAN quoteFirst, popExit
    .assert quoteFirst = 0 || quoteFirst = 1, "quoteFirst must be 0 or 1."
    .assert popExit = 0 || popExit = 1, "popExit must be 0 or 1."

;; Skips DATA fields up to an unquoted colon or end of line.
;; See: <DATAN>, <READ>
DATA:
    jsr DATAN

;; Advances <TXTPTR> by Y, to the terminator found by <DATAN> or <REMN>.
;; In: Y = offset of the terminator
ADDON:
    tya
    clc
    adc TXTPTR
    sta TXTPTR
    bcc REMRTS
    inc TXTPTR+1
REMRTS:
    rts

;; Scans from <TXTPTR> to an unquoted colon or a zero byte.
;; Out: Y = terminator offset
;; See: <DATA>, <DATLOP>, <REMN>
DATAN:
    ldx #':'
    .byte $2C                   ; BIT absolute skips <REMN>'s LDX

;; Scans from <TXTPTR> to the end-of-line zero.
;; Out: Y = terminator offset
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
.if quoteFirst
    beq EXCHQT
    bne REMER
.else
    bne REMER
    beq EXCHQT
.endif
.if popExit
REMER1:
    pla
    pla
    pla
    rts
.endif
.endmacro

;; Emits the <IF> and <REM> statement entries.
.macro CONDITIONAL_STATEMENTS

;; Evaluates the condition; false skips the line, true executes the THEN statement or jumps to a line.
;; See: <REM>, <GOTO>, <GONE3>
IF:
    jsr FRMEVL
    jsr CHRGOT
    cmp #GOTOTK
    beq OKGOTO
    lda #THENTK
    jsr SYNCHR
OKGOTO:
    lda FACEXP
    bne DOCOND

;; Skips the rest of the line.
REM:
    jsr REMN
    beq ADDON
DOCOND:
    jsr CHRGOT
    bcs DOCO
    jmp GOTO
DOCO:
    jmp GONE3
.endmacro

;; Emits the <ONGOTO> statement entry.
.macro ON_STATEMENT

;; Selects a one-based entry in a <GOTO> or <GOSUB> line-number list.
;;
;; Proceeds past the list when the selector exceeds the number of entries.
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
.endmacro
