; retrocore: style=strict
; APPLESOFT: PRINT AND CHARACTER OUTPUT
;
; PRINT formats expressions, while the shared string and character output routines serve
; error reporting, listing and other statements.

.include "../Microsoft6502Basic/MsBasic.Print.asm"

    PrintItems PrintTabOrSpace, 1, 1, 0

;; Microsoft's last comma-zone column, ((40/14)-1)*14; AppleSoft's code never uses it, and compares with
;; <COMMA_NEWLINE_COLUMN> instead.
;; Also: NCMPOS (M6502)
LAST_COMMA_COLUMN = $0E

;; The column at or past which PRINT's comma starts a new line instead of moving to the next zone.
COMMA_NEWLINE_COLUMN = 24

;; Prints a carriage return, then complements A for the callers that test the result.
;; Entry:
;;   Finish = complements A; the shared <PrintString> enters here after printing a return from a string
;;   Return = returns; the shared PRINT and <PrintString> branch here to end
;; Also: CRDO (M6502, ASTIL)
.proc PrintNewline
    lda #$0D                        ; carriage return
    jsr PrintCharacter

;; Complements A.
;; Also: CRFIN (M6502)
Finish:
    eor #$FF

;; Returns.
;; Also: PRTRTS (M6502)
Return:
    rts
.endproc

;; PRINT's comma: starts a new line at or past <COMMA_NEWLINE_COLUMN>, and otherwise moves to the next 16-column
;; zone. The enhanced IIe reads the column through <CHKCOL>, which in 80 columns skips the new line below column 73, and
;; prints spaces to the zone through <PrintTabOrSpace>; the II Plus and IIe only store the zone's column in
;; <TerminalPosition>.
;; Also: COMPRT (M6502)
.proc PrintComma
.if ENHNCD
    jsr CHKCOL
    bmi NextZone
.else
    lda TerminalPosition
.endif
    cmp #COMMA_NEWLINE_COLUMN
    bcc NextZone
    jsr PrintNewline
    bne PrintSpaces::ContinuePrint

.if ENHNCD
;; Rounds the column up to the next zone and goes on to set it. The overlay's LINCHK is here; Microsoft's is PRINT's
;; number item, <Statements::Print::NumberItem>.
;; Also: LINCHK (UNKN)
NextZone:
.else
;; Rounds the column up to the next zone and sets it. The overlay's LINCHK, the enhanced IIe's label here, falls
;; inside the `and`'s operand in these builds, at <PrintComma::ZoneMaskOperand>, and its TABER inside the next `jsr`'s
;; operand.
;; Also: COMPR1 (UNKN)
NextZone:
.endif
    adc #$10
.if ENHNCD
    and #$F0
    tax
    sec
    bcs PrintTabOrSpace::MoveToColumn
.else

;; The `and`'s operand, where the overlay's LINCHK falls in these builds; nothing enters it here.
;; Also: LINCHK (UNKN)
ZoneMaskOperand = * + 1
    and #$F0
    sta TerminalPosition
    bcc PrintSpaces::ContinuePrint
.endif
.endproc

;; `TAB(` or `SPC(`: reads the byte argument and the `)`, then prints spaces to the column (`TAB`) or the count (`SPC`),
;; and continues PRINT. The enhanced IIe's <PrintComma> enters at `MoveToColumn` to set the column.
;; In: carry = set for `TAB`, clear for `SPC`
.proc PrintTabOrSpace
.if ENHNCD

;; Saves the carry and reads the argument.
;; Also: TABER (M6502)
ReadArgument:
.else

;; Saves the carry and reads the argument. The overlay's TABER, the enhanced IIe's name for this routine, falls inside
;; the `jsr`'s operand in these builds, at <PrintTabOrSpace::EvaluateCallHigh>.
;; Also: LINCH1 (UNKN)
ReadArgument:
.endif
    php
.if .not ENHNCD

;; The `jsr`'s high address byte, where the overlay's TABER falls in these builds; nothing enters it here.
;; Also: TABER (UNKN)
EvaluateCallHigh = * + 2
.endif
    jsr SkipAndEvaluateByte
    cmp #')'
.if ENHNCD
    bne HandleBadInput::ToSyntaxError
.else
    beq ClosedParenthesis
    jmp SyntaxError
.endif

;; After the `)`: `SPC` prints X spaces; `TAB` subtracts the column.
;; Also: TABER1 (UNKN)
ClosedParenthesis:
    plp
    bcc PrintSpaces::CountInX
    dex
.if ENHNCD
;; Computes the spaces to the target column through <TRMSET>; the enhanced IIe's <PrintComma> enters here.
;; Also: TABER2 (UNKN)
MoveToColumn:
    jsr TRMSET
.else
    txa
    sbc TerminalPosition
.endif
    bcc PrintSpaces::ContinuePrint
    ; Falls into PrintSpaces.
.endproc

;; Prints A spaces, then continues PRINT; <PrintTabOrSpace> falls into it with the count for `TAB`.
;; Entry:
;;   CountInX = prints X spaces (zero prints none); <PrintTabOrSpace>'s `SPC` enters here
;;   ContinuePrint = reads the next character and continues PRINT at <Statements::Print::Item> without a newline;
;;     the shared PRINT, <PrintComma> and <PrintTabOrSpace> branch here
;; Also: ASPAC (M6502)
.proc PrintSpaces
    tax

;; Prints X spaces; zero prints none.
;; Also: XSPAC (M6502)
CountInX:
    inx

;; Counts down; zero goes on to `ContinuePrint`.
;; Also: XSPAC2 (M6502)
Next:
    dex
    bne One

;; Reads the next character and continues PRINT without a newline.
;; Also: NOTABR (M6502)
ContinuePrint:
    jsr GetNextCharacter
    jmp Statements::Print::Item

;; Prints one space and loops.
;; Also: XSPAC1 (M6502)
One:
    jsr PrintSpace
    bne Next
.endproc

.include "../Microsoft6502Basic/MsBasic.StringOutput.asm"

;; Prints a space: loads it and skips <PrintQuestionMark>'s load, into <PrintCharacter>.
;; Also: OUTSPC (M6502, ASTIL)
.proc PrintSpace
    lda #' '
    .byte $2C                       ; BIT absolute skips PrintQuestionMark's LDA
    ; Falls into PrintQuestionMark, past its load.
.endproc

;; Prints a question mark.
;; Also: OUTQST (M6502, ASTIL)
.proc PrintQuestionMark
    lda #'?'
    ; Falls into PrintCharacter.
.endproc

;; Sends a character to the Monitor's output routine and applies the configured output delay.
;;
;; Printable characters also receive <FlashMask>; output is passed with bit 7 set.
;; In: A = character
;; Out: A = the character returned by the Monitor, with bit 7 cleared
;; See: <OUTCH>, <MWAIT>, <OutputDelay>
;; Also: OUTDO (M6502, ASTIL)
.proc PrintCharacter
    ora #$80
    cmp #(' ' | $80)
    bcc Send
    ora FlashMask

;; Sends the character through <OUTCH> and applies the output delay.
;; Also: OUTLOC (M6502), TRYOUT (M6502)
Send:
    jsr OUTCH
    and #$7F
    pha
    lda OutputDelay
    jsr MWAIT
    pla

;; Returns; nothing in AppleSoft branches here, and the label is kept for its old name.
;; Also: GETRTS (M6502)
Return:
    rts
.endproc
