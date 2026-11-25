; retrocore: style=strict
;; Integer BASIC: the command loop and program editing
;;
;; The warm start and the loop that reads each line typed at the > prompt, has it tokenized, and either runs it at
;; once or stores it in the program; DEL, which removes lines; and the routines that print an error message and
;; return to the prompt.
;;
;; A typed line goes into <InputBuffer> ($0200) and its tokens after it in the same buffer. A line that starts with
;; a number is stored: its tokens already have the stored form, except that the constant marker of the line number
;; becomes the line's length. Storing a line first deletes any line with the same number, then moves the lines below
;; the place it goes down by its length and copies it into the gap. A number alone deletes the line.
;;
;; Part of IntegerBasic.asm.

;; Sets up memory for a 4K machine, then falls into the warm start; nothing in the ROM calls it.
;; See: <SETMEM4K>
;; Also: COLD4K (UNKN)
.proc ColdStart4K
    jsr SETMEM4K
    ; Falls into WarmStart.
.endproc

;; The warm start: prints a Return, then reads and handles lines typed at the > prompt, forever.
;;
;; In `AUTO` mode the prompt is followed by the next line number, which the line typed starts with as if it had been
;; typed: <PRDEC> also puts the digits in <InputBuffer>.
;; Entry:
;;   Prompt = without the Return; the end of each line, and errors, come back here
;; Also: WARM (IBSM)
.proc WarmStart
;; The high nibble of a byte: a constant's marker, $B0-$B9, gives $B0, the character 0.
HIGH_NIBBLE = $F0

    jsr PrintReturn

;; Prompts for the next line: >, and the next line number in `AUTO` mode.
;; Also: CMDPROMPT (UNKN)
Prompt:
    lsr Running                     ; not running a program
    lda #'>'
    jsr SetPrompt
    ldy #0
    sty LeadingZero                 ; no blanks before the line number
    bit AutoNumbering
    bpl ReadCommand                 ; not AUTO
    ldx AutoLine
    lda AutoLine+1
    jsr PRDEC
    lda #BLANK | $80
    jsr CharacterOut

;; Reads a line and tokenizes it, then runs it or stores it.
;;
;; The tokenizer starts at the top of the syntax table, $EDFF, with <TextIndex> before the line's first character and
;; <TokenIndex> at the end of its text, where the tokens will go. When it returns, <TokenPointer> is set to the first
;; token.
;; Also: CMDLINE (UNKN)
ReadCommand:
    ldx #$FF                        ; a fresh 6502 stack
    txs
    jsr Editor::ReadLine            ; Y = the length of the line
    sty TokenIndex
    txa
    sta TextIndex                   ; X = $FF: before the first character
    ldx #EMPTY_STACK
    jsr STARTRULE                   ; A = $FF: the rule at $EDFF, a whole line

    ; TokenPointer = the first token, after the text. Carry is set.
    lda TextIndex
    adc #0
    sta TokenPointer
    lda #0
    tax
    adc #>InputBuffer
    sta TokenPointer+1

    ; A line that starts with a constant, its number, is stored; any other runs now.
    lda (TokenPointer,x)
    and #HIGH_NIBBLE
    cmp #'0'
    beq Editor::StoreLine
    jmp RUNLOOP
.endproc

; The editor, continued: storing a line.
.scope Editor continued

;; Stores a numbered line in the program, replacing any line with the same number, or deletes the line if nothing
;; follows its number.
;;
;; It returns to the prompt. In `AUTO` mode it adds the step to the next line number first.
;; In: TokenPointer = the line's first token, the constant marker of its number, TextIndex = the index in
;;   <InputBuffer> before it, TokenIndex = the index of its last token, X = 0
;; Errors: MEM FULL if the line would reach the variables
;; Also: STORELINE (UNKN)
.proc StoreLine
;; The tokens of a line that is only a number: its marker, its two bytes and the end-of-line token.
NUMBER_ONLY = 4

    ; Accumulator = the line number, from the constant after its marker.
    ldy #2
CopyNumber:
    lda (TokenPointer),y
    sta Accumulator-1,y
    dey
    bne CopyNumber

    ; Delete the old line. X becomes 1, as <FINDLINE> takes an entry off the noun stack; carry is set.
    jsr DeleteLine

    ; The line's length: its tokens, from the marker to the end.
    lda TokenIndex
    sbc TextIndex
    cmp #NUMBER_ONLY
    beq WarmStart::Prompt           ; only the number: the line is deleted
    sta (TokenPointer),y            ; the length replaces the marker: the stored form

    ; The new start of the program, Pointer2 = ProgramStart - length, must stay above the variables.
    lda ProgramStart
    sbc (TokenPointer),y
    sta Pointer2
    lda ProgramStart+1
    sbc #0
    sta Pointer2+1
    lda Pointer2
    cmp VariablesEnd
    lda Pointer2+1
    sbc VariablesEnd+1
    bcc MemoryFullError

;; Moves each byte from <ProgramStart> up to <Pointer1>, the lines below the insertion point, down by the new line's
;; length.
MoveDown:
    lda ProgramStart
    sbc (TokenPointer),y
    sta Pointer3
    lda ProgramStart+1
    sbc #0
    sta Pointer3+1
    lda (ProgramStart),y
    sta (Pointer3),y
    inc ProgramStart
    bne CheckMoved
    inc ProgramStart+1
CheckMoved:
    lda Pointer1
    cmp ProgramStart
    lda Pointer1+1
    sbc ProgramStart+1
    bcs MoveDown

;; Sets <ProgramStart> to the new start of the program, both bytes as X counts down from 1, then copies the new line
;; into the gap at <Pointer3>.
SetStart:
    lda Pointer2,x
    sta ProgramStart,x
    dex
    bpl SetStart
    lda (TokenPointer),y
    tay
CopyLine:
    dey
    lda (TokenPointer),y
    sta (Pointer3),y
    tya
    bne CopyLine

    ; In AUTO mode, the next line number: X = $FF, then 0, adds both bytes. Carry is clear.
    bit AutoNumbering
    bpl Done
NextAutoLine:
    lda AutoLine+1,x
    adc AutoIncrement+1,x
    sta AutoLine+1,x
    inx
    beq NextAutoLine

;; Goes back to the prompt for the next line; the branch reaches it through <ReportError::LeaveLine>.
Done:
    bpl ReportError::LeaveLine      ; always

    ; Unused bytes.
    .byte $00, $00, $00, $00
.endproc

.endscope

;; Reports the MEM FULL error.
;;
;; At $E36B, which Programmer's Aid jumps to.
;; Also: MEMFULL (IBSM)
.proc MemoryFullError
.assert * = $E36B, "MemoryFullError must stay at $E36B, where Programmer's Aid jumps."
    ldy #<ErrMsg03
    bne ReportError                 ; always
.endproc

; Statements: DEL and its comma.
.scope Statements continued

;; The comma of DEL (token $0A): DEL m,n deletes the lines from where <Statements::Del> left off through line n.
;;
;; <Statements::Del> has removed line m, if it existed, and left the address of the line after it in <Pointer1>.
;; In: X = the noun stack, its top entry the last line number, Pointer1 = the first line to delete
;; Out: X = the noun stack, two entries higher: <FINDP3POP> takes one more
;; See: <FINDP3POP>
;; Also: COMMA_DEL (IBSM)
.proc DelComma
    jsr GET16BIT
    lda Pointer1
    sta Pointer3
    lda Pointer1+1
    sta Pointer3+1
    jsr FINDP3POP                   ; find line n, from Pointer3; Pointer3 = the line after it

    ; Remove what lies from Pointer1 to Pointer3.
    lda Pointer1
    sta Pointer2
    lda Pointer1+1
    sta Pointer2+1
    bne Editor::CloseGap            ; always: the program is not in page 0
.endproc

;; DEL (token $09): deletes the line with the number on the noun stack, if there is one.
;; In: X = the noun stack, its top entry the line number
;; Out: X = the noun stack, two entries higher: <FINDLINE> takes one more, Pointer1 = the line after it
;; See: <Statements::DelComma>
;; Also: DEL (IBSM)
.proc Del
    jsr GET16BIT
    ; Falls into Editor::DeleteLine.
.endproc

.endscope

; The editor, continued: deleting a line.
.scope Editor continued

;; Deletes the line numbered <Accumulator> if it exists, leaving <Pointer1> at the line after it: where a line
;; numbered <Accumulator> goes.
;;
;; <FINDLINE> leaves <Pointer3> after the line when it exists, and equal to <Pointer2> when it does not; then
;; <Editor::CloseGap> only copies each byte onto itself.
;; In: Accumulator = the line number, X = the noun stack
;; Out: Pointer1 = the line after it, ProgramStart = the new start of the program, X = one higher (<FINDLINE> takes
;;   an entry off the noun stack), Y = 0, carry = set
;; Also: DELLINE (UNKN)
.proc DeleteLine
    jsr FINDLINE
    lda Pointer3
    sta Pointer1
    lda Pointer3+1
    sta Pointer1+1
    ; Falls into CloseGap.
.endproc

;; Moves the bytes from <ProgramStart> up to <Pointer2> to end at <Pointer3>, from the top down, removing what lay
;; between <Pointer2> and <Pointer3>.
;; In: Pointer2 = the end of what is kept, Pointer3 = where it ends up
;; Out: ProgramStart = Pointer3 = the new start of the program, Y = 0, carry = set
;; Keeps: X
;; Also: CLOSEGAP (UNKN)
.proc CloseGap
    ldy #0
MoveByte:
    lda ProgramStart
    cmp Pointer2
    lda ProgramStart+1
    sbc Pointer2+1
    bcs Moved                       ; everything is moved

    ; Step both pointers down a byte, and move it.
    lda Pointer2
    bne DecrementSource
    dec Pointer2+1
DecrementSource:
    dec Pointer2
    lda Pointer3
    bne DecrementDestination
    dec Pointer3+1
DecrementDestination:
    dec Pointer3
    lda (Pointer2),y
    sta (Pointer3),y
    bcc MoveByte                    ; always: the comparison above cleared carry

;; Sets <ProgramStart> to <Pointer3>, the new start of the program.
Moved:
    lda Pointer3
    sta ProgramStart
    lda Pointer3+1
    sta ProgramStart+1
    rts
.endproc

.endscope

;; The loop of <PrintMessage>, four bytes before its entry: prints a character of a message, then goes on with the
;; next.
;; In: A = the character, Y = its offset from <ErrMsg00>
PrintMessageCharacter:
    jsr CharacterOut
    iny
    ; Falls into PrintMessage.

;; Prints the message at offset Y in the message table.
;;
;; The messages (<ErrMsg00>) have bit 7 set on every character but the last.
;; In: Y = the message's offset from <ErrMsg00>
;; Out: Y = the offset of its last character
;; Keeps: X
;; See: <PRINTERR>
;; Also: ERRORMESS (IBSM)
.proc PrintMessage
    lda ErrMsg00,y
    bmi PrintMessageCharacter
    ora #$80
    jmp CharacterOut
.endproc

; The editor, continued: line input.
.scope Editor continued

;; Reads a line into <InputBuffer> from index Y, after the prompt has been printed, and marks its end with an
;; underline.
;;
;; The underline replaces the Return; the syntax table's last rule matches it as the end of the line.
;; In: Y = where in <InputBuffer> the line starts
;; Out: Y = the index of the underline, X = $FF, A = the underline
;; See: <GetLine::NextCharacter>, <WarmStart>, <Editor::ReadInputLine>
;; Also: GETCMD (IBSM)
.proc ReadLine
    tya
    tax
    jsr GetLine::NextCharacter
    txa
    tay
    lda #LINE_END_MARK
    sta InputBuffer,y
    ldx #$FF
    rts

    ; An unused byte (an RTS).
    .byte $60
.endproc

.endscope

;; Reports the TOO LONG error.
;; Also: ErrTooLong (IBSM)
.proc TooLongError
    ldy #<ErrMsg01
    ; Falls into ReportError.
.endproc

;; Reports an error: prints *** and the message at offset Y, then `ERR` and a bell, and leaves the statement.
;;
;; Typed lines go back to the prompt. In a running program <RUNERROR> decides: the error stops the program with the
;; line's number, unless INPUT is reading numbers, which asks for the line again.
;; In: Y = the message's offset from <ErrMsg00>
;; Entry:
;;   LeaveLine = leaves for the prompt, or for <RUNERROR> while a program runs
;; See: <PRINTERR>
;; Also: ERRMESS (IBSM)
.proc ReportError
    jsr PRINTERR
    bit Running

;; Leaves for the prompt, or for <RUNERROR> while a program runs.
;; In: negative = set while a program runs
;; Also: LEAVELINE (UNKN)
LeaveLine:
    bmi ToRunError
    jmp WarmStart::Prompt

ToRunError:
    jmp RUNERROR
.endproc
