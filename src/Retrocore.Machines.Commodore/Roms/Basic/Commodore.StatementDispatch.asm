; COMMODORE BASIC: NEXT STATEMENT AND TOKEN DISPATCH

;; Emits the next-statement fetcher.
;; Parameters: bufferPage = zero for a page-zero direct buffer, or the nonzero buffer page,
;;             spareByte = 1 to retain the later ROM's NOP before the direct-mode branch,
;;             earlySeparators = 1 to check separators before the line link,
;;             shortEnd = 1 to branch directly to <Statements::StopOrEnd::Finish>,
;;             fetchToken = character-reader entry, or the revised BASIC 4 PI-checking patch
.macro COMMODORE_STATEMENT_FETCH bufferPage, spareByte, earlySeparators, shortEnd, fetchToken
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert spareByte = 0 || spareByte = 1, "spareByte is 0 or 1."
    .assert earlySeparators = 0 || earlySeparators = 1, "earlySeparators is 0 or 1."
    .assert shortEnd = 0 || shortEnd = 1, "shortEnd is 0 or 1."

;; Runs the next statement or advances to the next linked line, checking for STOP first.
;;
;; The text position is saved for INPUT retry when execution is not in the direct buffer's page.
;; A zero line link ends the program. The earlier separator check accepts a colon before reading the link.
;; In: TextPointer = statement separator or line terminator
;; See: <GONE>, <Statements::StopOrEnd::Finish>
NEWSTT:
    jsr ISCNTC
    lda TXTPTR
    ldy TXTPTR+1
.if bufferPage
    cpy #bufferPage
.endif
.if spareByte
    nop
.endif
    beq DIRCON
    sta OLDTXT
    sty OLDTXT+1
.if bufferPage
DIRCON:
.endif
    ldy #$00
.if .not bufferPage
DIRCON:
.endif
    lda (TXTPTR),y
.if earlySeparators
    beq NXTLIN
    cmp #':'
    beq GONE
SNERR1:
    jmp SNERR
NXTLIN:
.else
    bne MORSTS
.endif
    ldy #$02
    lda (TXTPTR),y
    clc
.if shortEnd
    beq ENDCON
.else
    bne *+5
    jmp ENDCON
.endif
    iny
    lda (TXTPTR),y
    sta CURLIN
    iny
    lda (TXTPTR),y
    sta CURLIN+1
    tya
    adc TXTPTR
    sta TXTPTR
    bcc GONE
    inc TXTPTR+1

;; Fetches and executes a statement, then continues at <NEWSTT>.
GONE:
    jsr fetchToken
    jsr GONE3
    jmp NEWSTT
.endmacro

;; Emits statement-token dispatch and optional GO or disk-command handling.
;; Parameters: earlyDispatch = 1 for the earlier carry and error paths,
;;             diskCommands = 1 to dispatch disk tokens after the GO gap
.macro COMMODORE_STATEMENT_DISPATCH earlyDispatch, diskCommands
    .assert earlyDispatch = 0 || earlyDispatch = 1, "earlyDispatch is 0 or 1."
    .assert diskCommands = 0 || diskCommands = 1, "diskCommands is 0 or 1."
    .assert earlyDispatch = 0 || diskCommands = 0, "Early dispatch has no disk-command gap."

;; Dispatches a statement token through <STMDSP>, or treats a non-token as <Statements::Let>.
;; Entry: GONE2 = dispatches the token in A after ON's selection
;; In: A = statement token or first character, carry = set for a non-digit
;; Errors: SYNTAX for a non-statement reserved word
GONE3:
.if earlyDispatch
    beq CONTRT
    sec
.else
    beq ISCRTS
.endif
GONE2:
    sbc #<ENDTK
.if earlyDispatch
    bcs GONE4
    jmp LET
GONE4:
    cmp #<(SCRATK-ENDTK+1)
    bcs SNERR1
.else
    bcc GLET
    cmp #<(SCRATK-ENDTK+1)
.if diskCommands
    bcc GONE4
    cmp #<(GOTK-ENDTK)
    bcc SNERR1
    sbc #<(GOTK-SCRATK-1)
GONE4:
.else
    bcs SNERRX
.endif
.endif
    asl a
    tay
    lda STMDSP+1,y
    pha
    lda STMDSP,y
    pha
    jmp CHRGET
.if .not earlyDispatch
GLET:
    jmp LET
MORSTS:
    cmp #':'
    beq GONE
SNERR1:
    jmp SNERR
.if diskCommands

;; Parses GO TO as a two-token spelling of GOTO.
GO:
    jsr CHRGOT
    lda #<TOTK
    jsr SYNCHR
    jmp GOTO
.else
SNERRX:
    cmp #<(GOTK-ENDTK)
    bne SNERR1
    jsr CHRGET
    lda #<TOTK
    jsr SYNCHR
    jmp GOTO
.endif
.endif
.endmacro
