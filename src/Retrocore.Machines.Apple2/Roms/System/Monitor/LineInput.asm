; retrocore: style=strict
;; Line input, $FD3D-$FDA2: reading a line into the input buffer with its editing keys, and printing a Return or an
;; address.

; Line input.

;; The position in <IN> from which each character typed rings the bell: 248, eight before the buffer's end.
INPUT_WARNING = $F8

;; The mask the original IIe's <GetLine> applies where the Apple II's apply <UPPERCASE_MASK>: every bit, so
;; lowercase stays.
KEEP_CASE_MASK = $FF
.if ENHANCED

;; The internal firmware's function that gets the character under the 80-column cursor, with its high bit set.
FIRMWARE_CHARACTER_UNDER_CURSOR = $0F
.endif

;; The parts of <GetLine> that handle a character once it is in the buffer: echoing it, its editing keys,
;; and cancelling the line.
.scope LineInput
.if ENHANCED

;; Control-U in 80 columns: has the internal firmware get the character under the cursor, stores it in the
;; line, then echoes it.
;;
;; At $FD3D.
;; In: X = the position in <IN>
;; Also: PICKFIX (IIETRM85)
.proc PickUnderCursor
.assert * = $FD3D, "LineInput::PickUnderCursor must stay at $FD3D."
    ldy #FIRMWARE_CHARACTER_UNDER_CURSOR
    jsr CallFirmware
    ldy CH
    sta IN,x
    ; Falls into Echo.
.endproc

;; Echoes a character typed into the line, other than Return, then performs the backspace key and Control-X, and
;; rings the bell near the buffer's end.
;;
;; At $FD47. The 256th character cancels the line.
;; In: X = the character's position in <IN>
;; Also: NOTCR (IIETRM85)
.proc Echo
.assert * = $FD47, "LineInput::Echo must stay at $FD47."
    jsr CharacterOut

    ; In place of the other builds' INVFLG save and restore.
    nop
    nop
    nop

    ; The editing keys.
    lda IN,x
    cmp #KEY_BS
    beq GetLine::TakeBack
    cmp #KEY_CTRL_X
    beq Cancel

    ; The bell from INPUT_WARNING on.
    cpx #INPUT_WARNING
    bcc Next
    jsr Beep

;; Goes on with the next position; past the buffer's end, falls into <Cancel>.
;; Also: NOTCR1 (IIETRM85)
Next:
    inx
    bne GetLine::NextCharacter
    ; Falls into Cancel.
.endproc
.else

;; Echoes a character typed into the line, other than Return, then performs the backspace key and Control-X, and
;; rings the bell near the buffer's end.
;;
;; At $FD3D. The Apple II's Monitors echo in normal video, whatever <INVFLG> holds, and restore it; the
;; original IIe keeps the save and restore but echoes with <INVFLG> as it is. The 256th character cancels the
;; line.
;; In: X = the character's position in <IN>
;; Also: NOTCR (A2RM78, A2RM79, IIEROM82)
.proc Echo
.assert * = $FD3D, "LineInput::Echo must stay at $FD3D."
    lda INVFLG
    pha
    lda #TEXT_NORMAL
.if MONITOR = MONITOR_IIE
    nop
    nop
.else
    sta INVFLG
.endif
    lda IN,x
    jsr CharacterOut
    pla
    sta INVFLG

    ; The editing keys.
    lda IN,x
    cmp #KEY_BS
    beq GetLine::TakeBack
    cmp #KEY_CTRL_X
    beq Cancel

    ; The bell from INPUT_WARNING on.
    cpx #INPUT_WARNING
    bcc Next
    jsr Beep

;; Goes on with the next position; past the buffer's end, falls into <Cancel>.
;; Also: NOTCR1 (A2RM79)
Next:
    inx
    bne GetLine::NextCharacter
    ; Falls into Cancel.
.endproc
.endif

;; Cancels the input line: prints a backslash and starts again on a new line.
;;
;; At $FD62.
;; Also: CANCEL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Cancel
.assert * = $FD62, "LineInput::Cancel must stay at $FD62."
    lda #'\'
    jsr CharacterOut
    ; Falls into GetLineAfterReturn.
.endproc

.endscope

;; Prints a Return, then reads a line as <GetLine> does.
;;
;; At $FD67.
;; Out: X = the line's length, IN,X = the Return that ends it
;; Also: GETLNZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc GetLineAfterReturn
.assert * = $FD67, "GetLineAfterReturn must stay at $FD67."
    jsr PrintReturn
    ; Falls into GetLine.
.endproc
.if ENHANCED

;; Reads a line into <IN> after printing the prompt character in <PROMPT>.
;;
;; At $FD6A. Backspace deletes a character, Control-X cancels the line, and the right arrow (Control-U) takes
;; the character under the cursor. Lowercase stays lowercase.
;; Out: X = the line's length, IN,X = the Return that ends it
;; Entry:
;;   NoPrompt = reads a line without printing the prompt
;;   TakeBack = takes back a character; at the line's start, starts the line again
;;   NextCharacter = reads the next character; Control-U takes the one under the cursor
;; Also: GETLN (IIETRM85)
.proc GetLine
.assert * = $FD6A, "GetLine must stay at $FD6A."
    lda PROMPT
    jsr CharacterOut

;; Reads a line without printing the prompt.
;; Out: X = the line's length, IN,X = the Return that ends it
;; Also: GETLN1 (IIETRM85)
NoPrompt:
.assert * = $FD6F, "GetLine::NoPrompt must stay at $FD6F."
    ldx #1

;; Takes back a character; at the line's start, starts the line again. <LineInput::Echo> enters here.
;; Also: BCKSPC (IIETRM85)
TakeBack:
    txa
    beq GetLineAfterReturn
    dex

;; Reads the next character; Control-U takes the one under the cursor.
;; Also: NXTCHAR (IIETRM85)
NextCharacter:
    jsr ReadCharacter
    cmp #KEY_RIGHT
    bne Store
    lda (BASL),y
    bit RD80VID
    bmi LineInput::PickUnderCursor
    nop

;; Stores the character in the line, and echoes it unless it is a Return.
;; Also: ADDINP (IIETRM85)
Store:
    sta IN,x
    cmp #KEY_CR
    bne LineInput::Echo
    ; Falls into ClearAndPrintReturn.
.endproc
.else

;; Reads a line into <IN> after printing the prompt character in <PROMPT>.
;;
;; At $FD6A. Backspace deletes a character, Control-X cancels the line, and the right arrow (Control-U) takes
;; the character under the cursor. The Apple II's Monitors store lowercase letters as capitals; the original
;; IIe keeps them.
;; Out: X = the line's length, IN,X = the Return that ends it
;; Entry:
;;   NoPrompt = reads a line without printing the prompt
;;   TakeBack = takes back a character; at the line's start, starts the line again
;;   NextCharacter = reads the next character; Control-U takes the one under the cursor
;; Also: GETLN (A2RM78, A2RM79, IIEROM82)
.proc GetLine
.assert * = $FD6A, "GetLine must stay at $FD6A."
    lda PROMPT
    jsr CharacterOut

;; Reads a line without printing the prompt.
;; Out: X = the line's length, IN,X = the Return that ends it
;; Also: GETLN1 (A2RM79)
NoPrompt:
.assert * = $FD6F, "GetLine::NoPrompt must stay at $FD6F."
    ldx #1

;; Takes back a character; at the line's start, starts the line again. <LineInput::Echo> enters here.
;; Also: BCKSPC (A2RM78, A2RM79, IIEROM82)
TakeBack:
    txa
    beq GetLineAfterReturn
    dex

;; Reads the next character; Control-U takes the one under the cursor.
;; Also: NXTCHAR (A2RM78, A2RM79, IIEROM82)
NextCharacter:
    jsr ReadCharacter
    cmp #KEY_RIGHT
    bne Uppercase
    lda (BASL),y

;; On the Apple II's Monitors, makes a lowercase letter a capital: everything from the character before "a" up
;; has bit 5 cleared. The original IIe's mask keeps it.
;; Also: CAPTST (A2RM78, A2RM79, IIEROM82)
Uppercase:
    cmp #'a' - 1
    bcc Store
.if MONITOR = MONITOR_IIE
    and #KEEP_CASE_MASK
.else
    and #UPPERCASE_MASK
.endif

;; Stores the character in the line, and echoes it unless it is a Return.
;; Also: ADDINP (A2RM78, A2RM79, IIEROM82)
Store:
    sta IN,x
    cmp #KEY_CR
    bne LineInput::Echo
    ; Falls into ClearAndPrintReturn.
.endproc
.endif

;; Clears the rest of the line, then prints a Return.
;;
;; At $FD8B.
;; Also: CROUT1 (A2RM79, IIETRM85)
.proc ClearAndPrintReturn
.assert * = $FD8B, "ClearAndPrintReturn must stay at $FD8B."
    jsr ClearToEndOfLine
    ; Falls into PrintReturn.
.endproc

;; Prints a Return.
;;
;; At $FD8E.
;; Also: CROUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintReturn
.assert * = $FD8E, "PrintReturn must stay at $FD8E."
    lda #KEY_CR
    bne CharacterOut
.endproc

;; Prints a Return, then <A1L>/<A1H> as "AAAA-".
;;
;; At $FD92.
;; Out: Y = 0, when the output hook keeps Y as the screen's does
;; Entry:
;;   YX = prints a Return, then Y and X as "YYXX-"
;; Also: PRA1 (A2RM78, A2RM79, IIEROM82)
.proc PrintAddress
.assert * = $FD92, "PrintAddress must stay at $FD92."
    ldy A1H
    ldx A1L

;; Prints a Return, then Y and X as "YYXX-".
;; In: Y = the high byte, X = the low byte
;; Out: Y = 0, when the output hook keeps Y as the screen's does
;; Also: PRYX2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
YX:
.assert * = $FD96, "PrintAddress::YX must stay at $FD96."
    jsr PrintReturn
    jsr PrintYX

    ; Y = 0 for the caller, then the dash.
    ldy #0
    lda #'-'
    jmp CharacterOut
.endproc
