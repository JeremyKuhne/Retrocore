; retrocore: style=strict
; EXTRAS: OUTREC, INDENT, HPOS and VPOS as statements, ON KBD, ON EOF# and OFF, which Business BASIC adds to
; Applesoft's, and NORMAL, INVERSE, TRACE and NOTRACE, ON ERR and RESUME, DEL, TEXT and HOME, with the routines
; that test for two-byte tokens and that send a program to its ON KBD or ON EOF# handler.
;
; ON KBD and ON EOF# keep their handlers in EndOfFileHandlers and EndOfFileHandlerLines, three bytes and two each, by
; number: 1 to 10 for the files #1 to #10, 11 for the keyboard. A handler is where its statement continues, as an offset
; from ProgramStart so it survives the program moving, and the line it is in. A zero first byte means no handler.

; ---------------------------------------------------------------------------------------------------------------------
; Screen and listing settings
; ---------------------------------------------------------------------------------------------------------------------

; Business BASIC's added statements.
.scope Statements continued

;; The `OUTREC = n` statement: sets <OutputRecordLength>, `LIST`'s right margin.
;; See: <Statements::GetEqualsByte>
;; Also: SOUTREC (BB13)
.proc OutRec
    jsr GetEqualsByte
    stx OutputRecordLength
    rts
.endproc

;; The `INDENT = n` statement: sets <ListIndent>, the spaces `LIST` indents each `FOR` loop by.
;; See: <Statements::GetEqualsByte>
;; Also: SINDENT (BB13)
.proc Indent
    jsr GetEqualsByte
    stx ListIndent
    rts
.endproc

;; Reads `=` and a number from 0 to 255, for the statements that set a value.
;; Out: X = the number
;; Errors: SYNTAX without the `=`, ILLEGAL QUANTITY for a number out of range
;; Also: CHKBYT (BB13)
.proc GetEqualsByte
    jsr CheckEquals
    jmp EvaluateByte
.endproc

;; The `HPOS = n` statement: moves the cursor to column n, counting from 1, and records it in <TerminalPosition>.
;; See: <Statements::MoveToColumn>
;; Also: HTAB (BB13)
.proc HPos
    jsr MoveToColumn
    sta TerminalPosition                    ; The column, from 0
    rts
.endproc

;; Ends with ILLEGAL QUANTITY, for `TAB(0)`.
;; Also: TOOBIG (BB13)
.proc ToIllegalQuantity
    jmp IllegalQuantityError
.endproc

;; Moves the cursor to the column after `=`, for <Statements::HPos>.
;; Out: A = the column, counting from 0
;; See: <Statements::VPos>
;; Also: HTABB (BB13)
.proc MoveToColumn
    lda #Console::SET_COLUMN
    .byte $2C                               ; BIT abs, which skips VPos's LDA
    ; Falls into Statements::VPos.
.endproc

;; The `VPOS = n` statement: moves the cursor to line n, counting from 1.
;; See: <Statements::HPos>
;; Also: VTAB (BB13)
.proc VPos
    lda #Console::SET_LINE
    pha
    jsr CheckEquals
    jsr EvaluateByte
    pla
    ; Falls into Console::SendCodeAndPosition.
.endproc

.endscope

; Sending the console a position.
.scope Console continued

;; Sends a console code and its argument, counting from 1, which the console counts from 0.
;; In: A = the code, X = the argument
;; Out: A = the argument as sent
;; See: <SendCoordinate>
;; Also: VWINDER (BB13)
.proc SendCodeAndPosition
    jsr WriteConsoleCharacter
    txa
    jmp SendCoordinate
.endproc

.endscope

; More of Business BASIC's added statements.
.scope Statements continued

;; The `NORMAL` statement: sets normal video.
;; Also: SETNORM (BB13)
.proc Normal
    lda #Console::NORMAL_VIDEO
    .byte $2C                               ; BIT abs, which skips Inverse's LDA
    ; Falls into Statements::Inverse.
.endproc

;; The `INVERSE` statement: sets inverse video.
;; Also: INVERSE (BB13)
.proc Inverse
    lda #Console::INVERSE_VIDEO
    jmp WriteConsoleCharacter
.endproc

;; The `TRACE` statement: sets bit 7 of <TraceMode>, so the statement fetcher prints each line's number as it runs.
;;
;; With anything after `TRACE` it changes nothing, and the statement fetcher reports SYNTAX. Apple's comment had this
;; the wrong way round.
;; See: <Statements::NoTrace>
;; Also: SETTRACE (BB13)
.proc Trace
    sec
    .byte $90                               ; BCC, never taken after SEC, which skips NoTrace's CLC
    ; Falls into Statements::NoTrace.
.endproc

;; The `NOTRACE` statement: clears bit 7 of <TraceMode>.
;; In: zero = set at the end of the statement
;; See: <Statements::Trace>
;; Entry: Done = returns
;; Also: TRACEOFF (BB13)
.proc NoTrace
    clc
    bne Done                                ; Something follows: leave it for SYNTAX
    ror TraceMode

;; Returns.
;; Also: RTSBCK (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; ON ERR and RESUME
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON ERR statements` statement: makes the statements after `ERR`, to the end of the line, the program's error
;; handler, then skips them.
;;
;; It keeps where they start in <OnErrorText> (the address of the `ERR` token, with its X-byte in <OnErrorTextXByte>)
;; and the line's number in <OnErrorText>+3 and +4, and sets bit 7 of <OnErrorActive>. `OFF ERR` clears the bit; `RUN`,
;; `NEW`, `LOAD` and editing the program clear <OnErrorActive>.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <TrapError>, <ReportError>, <Statements::Off>
;; Also: ONERR (BB13)
.proc OnErr
    jsr RejectDirectMode
    lda TextPointer
    sta OnErrorText
    lda TextPointer+1
    sta OnErrorText+1
    lda TextPointerXByte
    sta OnErrorTextXByte
    lda OnErrorActive
    ora #$80
    sta OnErrorActive
    lda CurrentLine                         ; The line, for the handler to run in
    sta OnErrorText+3
    lda CurrentLine+1
    sta OnErrorText+4
    jsr FindLineEnd                         ; Skip the handler for now
    jmp AdvanceTextPointer
.endproc

.endscope

;; Runs the `ON ERR` handler: <ReportError> comes here when bit 7 of <OnErrorActive> is set.
;;
;; It puts the stack pointer back to <StatementStack>, where the failing statement started, so `FOR` and `GOSUB` entries
;; stay; keeps <StoppedText>, the failing statement's start, in <ErrorText> and <ErrorTextXByte> for `RESUME`; then sets
;; <TextPointer> and <CurrentLine> from <OnErrorText> and goes on at the statement after `ON ERR`, through
;; <NextStatement::CheckEvents>. <ReportError> has already set <ErrorCode> and <ErrorLine>. The handler stays in force.
;; See: <Statements::OnErr>, <Statements::Resume>
;; Also: HNDLERR (BB13)
.proc TrapError
    ldx StatementStack
    txs
    lda StoppedText
    sta ErrorText
    lda StoppedText+1
    sta ErrorText+1
    lda StoppedTextXByte
    sta ErrorTextXByte
    lda OnErrorText
    sta TextPointer
    lda OnErrorText+1
    sta TextPointer+1
    lda OnErrorTextXByte
    sta TextPointerXByte
    lda OnErrorText+3
    sta CurrentLine
    lda OnErrorText+4
    sta CurrentLine+1
    jmp NextStatement::CheckEvents
.endproc

; RESUME.
.scope Statements continued

;; The `RESUME` statement: runs the statement that failed again, from <ErrorText> in line <ErrorLine>.
;;
;; When no error has been handled (<ErrorTextXByte> zero) it does nothing.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <TrapError>
;; Also: RESUME (BB13)
.proc Resume
    jsr RejectDirectMode
    lda ErrorTextXByte
    beq Done
    sta TextPointerXByte
    lda ErrorLine
    sta CurrentLine
    lda ErrorLine+1
    sta CurrentLine+1
    lda ErrorText
    sta TextPointer
    lda ErrorText+1
    sta TextPointer+1

;; Returns, to the statement fetcher.
;; Also: RSM2 (BB13)
Done:
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Two-byte tokens
; ---------------------------------------------------------------------------------------------------------------------

;; Tests whether the program has a two-byte token, <TOKEN_ESCAPE> and A, at <TextPointer>, and steps over the first
;; byte if so.
;; In: A = the token's second byte
;; Out: zero = set when found, with <TextPointer> at the second byte, A = the character at <TextPointer>
;; Keeps: X, Y
;; See: <RequireTwoByteToken>
;; Also: TRYESC (BB13)
.proc MatchTwoByteToken
    sty SavedY
    ldy #1
    cmp (TextPointer),Y
    bne Reread
    dey
    lda (TextPointer),Y
    cmp #TOKEN_ESCAPE
    bne Reread
    jsr GetNextCharacter                    ; Step over the TOKEN_ESCAPE
    lda #$00                                ; Found

;; Reads the character at <TextPointer> again, keeping the flags.
;; Also: TRY2 (BB13)
Reread:
    php
    jsr GetCurrentCharacter
    ldy SavedY
    plp
    rts
.endproc

;; Requires the two-byte token <TOKEN_ESCAPE> and A next, and steps past it.
;; In: A = the token's second byte
;; Errors: SYNTAX when it is not there
;; See: <MatchTwoByteToken>, <CheckCharacter>
;; Also: MSTESC (BB13)
.proc RequireTwoByteToken
    pha
    lda #TOKEN_ESCAPE
    jsr CheckCharacter
    pla
    jmp CheckCharacter
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; ON KBD, ON EOF# and OFF
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON KBD` and `ON EOF#` handlers, kept in <EndOfFileHandlers> and <EndOfFileHandlerLines>, and going to them.
.scope Handlers

;; The handler number of `ON KBD`; `ON EOF#`'s are the file numbers, 1 to 10.
KEYBOARD = 11

.endscope

; ON KBD and ON EOF#.
.scope Statements continued

;; The `ON KBD statements` statement: makes the statements after `KBD` the handler for a key pressed while the
;; program runs, and turns the console's any-key event on.
;;
;; The handler is number <Handlers::KEYBOARD> in <EndOfFileHandlers>; <Handlers::KeyPressed> calls it as a `GOSUB`.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <Statements::OnEof::SetHandler>, <Handlers::KeyPressed>, <Statements::OffKbd>
;; Also: ONKBD (BB13)
.proc OnKbd
    jsr RejectDirectMode
    lda #1
    sta a:Console::AnyKeyEvent+SosCalls::EventList::PRIORITY
    brk                                     ; D_CONTROL: the any-key event on
    .byte SOS_DEVICE_CONTROL
    .word Console::AnyKeyParameters
    ldx #Handlers::KEYBOARD
    bne OnEof::SetHandler
.endproc

;; The `ON EOF#n statements` statement: makes the statements after the file number the handler for reaching the
;; end of file #n.
;;
;; <Handlers::EndOfFile> goes to it as a `GOTO`.
;; Errors: ILLEGAL DIRECT outside a program
;; Entry: SetHandler = records handler X, 1 to 11, at the statements after <TextPointer>
;; See: <Handlers::EndOfFile>, <Statements::OffEof>
;; Also: ONEOF (BB13)
.proc OnEof
    jsr GetNextCharacter
    jsr RejectDirectMode
    jsr Files::TakeFileNumber
    inx                                     ; The file's number, from 1
    jsr BackUpTextPointer                   ; Back to the character before the statements

;; Records handler X: where the statements start, relative to <ProgramStart>, in <EndOfFileHandlers>, and the line in
;; <EndOfFileHandlerLines>; then skips the statements.
;; Also: ONEOF2 (BB13)
SetHandler:
    txa
    sta SavedY
    asl                                     ; Three bytes each
    adc SavedY
    tax
    jsr Handlers::ToggleOffset
    lda TextPointer
    sta EndOfFileHandlers-2,X
    lda TextPointer+1
    sta EndOfFileHandlers-1,X
    lda TextPointerXByte
    sta EndOfFileHandlers-3,X
    jsr Handlers::ToggleOffset              ; Back to an address
    lda CurrentLine
    sta EndOfFileHandlerLines-3,X
    lda CurrentLine+1
    sta EndOfFileHandlerLines-2,X
    jsr FindLineEnd                         ; Skip the handler for now
    jmp AdvanceTextPointer
.endproc

.endscope

; The handlers, continued.
.scope Handlers continued

;; Turns <TextPointer> into an offset from <ProgramStart>, or such an offset back into an address.
;;
;; It replaces <TextPointer> with <ProgramStart> less <TextPointer>, which undoes itself when done twice.
;; Keeps: X
;; Also: RELTXT (BB13)
.proc ToggleOffset
    sec
    lda ProgramStart
    sbc TextPointer
    sta TextPointer
    lda ProgramStart+1
    sbc TextPointer+1
    ldy ProgramStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta TextPointer+1
    tya
    sbc TextPointerXByte
    sta TextPointerXByte
    rts
.endproc

.endscope

; OFF.
.scope Statements continued

;; The `OFF` statement: `OFF KBD`, `OFF EOF#n` or `OFF ERR` turns that handler off.
;;
;; Any other one-byte word after `OFF` is stepped past and ignored, with no error: `OFF X` does nothing.
;; In: A = the token after `OFF`
;; See: <Statements::OffKbd>, <Statements::OffEof>
;; Also: OFF (BB13)
.proc Off
    pha
    jsr GetNextCharacter
    pla
    cmp #TOKEN_KBD
    beq OffKbd
    cmp #TOKEN_EOF
    beq OffEof
    cmp #TOKEN_ERR
    bne Done
    lda OnErrorActive                       ; OFF ERR
    and #$7F
    sta OnErrorActive

;; Returns.
;; Also: RTS999 (BB13)
Done:
    rts
.endproc

;; `OFF KBD`: turns the console's any-key event off and clears handler <Handlers::KEYBOARD>.
;; See: <Statements::OnKbd>
;; Also: OFFKBD (BB13)
.proc OffKbd
    lda #0
    sta a:Console::AnyKeyEvent+SosCalls::EventList::PRIORITY
    brk                                     ; D_CONTROL: the any-key event off
    .byte SOS_DEVICE_CONTROL
    .word Console::AnyKeyParameters
    ldx #Handlers::KEYBOARD
    bne OffEof::ClearHandler
.endproc

;; `OFF EOF#n`: turns the file's `ON EOF#` handler off.
;; Entry: ClearHandler = clears handler X, 1 to 11
;; See: <Statements::OnEof>
;; Also: OFFEOF (BB13)
.proc OffEof
    jsr Files::TakeFileNumber
    inx

;; Clears handler X in <EndOfFileHandlers>.
;; Also: OFFEOF2 (BB13)
ClearHandler:
    txa
    sta SavedY
    asl
    adc SavedY
    tax
    lda #0
    sta EndOfFileHandlers-2,X
    sta EndOfFileHandlers-1,X
    sta EndOfFileHandlers-3,X
    rts
.endproc

.endscope

; Going to a handler.
.scope Handlers continued

;; Goes to the `ON EOF#` handler of the file in <CurrentFileNumber>, which reached its end, or ends with OUT OF DATA
;; when it has none.
;;
;; It keeps the file's number, from 1, in <EndOfFileNumber> for the `EOF` function, puts the stack pointer back to
;; <StatementStack>, sends output back to the `OUTPUT#` device, and goes on at the handler's statements in its line,
;; through <ExecuteStatement>.
;; In: CurrentFileNumber = the file's number, from 0
;; Entry: GoToHandler = goes to handler X/3, without setting EOF or the stack
;; See: <Statements::OnEof>, <Files::ReadTextLine::ReadFailed>
;; Also: CHKEOF (BB13)
.proc EndOfFile
    inc CurrentFileNumber
    lda CurrentFileNumber
    sta EndOfFileNumber
    asl
    adc CurrentFileNumber
    ldx StatementStack                      ; The stack as the statement started
    txs
    tax

;; Goes to handler X/3 in <EndOfFileHandlers>, or ends with OUT OF DATA when there is none.
;; Also: CKEOF2 (BB13)
GoToHandler:
    lda OutputFileNumber+1
    sta OutputFileNumber
    lda EndOfFileHandlers-3,X
    beq NoHandler                           ; No handler
    sta TextPointerXByte
    lda EndOfFileHandlers-2,X
    sta TextPointer
    lda EndOfFileHandlers-1,X
    sta TextPointer+1
    lda EndOfFileHandlerLines-3,X
    sta CurrentLine
    lda EndOfFileHandlerLines-2,X
    sta CurrentLine+1
    jsr ToggleOffset                        ; Back to an address
    jmp ExecuteStatement

;; Ends with OUT OF DATA.
;; Also: GIVOD (BB13)
NoHandler:
    ldx #ERROR_OUT_OF_DATA
    jmp ReportError
.endproc

;; Calls the `ON KBD` handler as a `GOSUB`: the statement fetcher comes here when bit 7 of <PendingEvents> says the
;; any-key event saw a key.
;;
;; It clears the bit and pushes a `GOSUB` entry, so `RETURN` goes back to the statement that was next.
;; See: <Statements::OnKbd>, <Console::AnyKeyHandler>, <NextStatement::CheckEvents>
;; Also: KEYHIT (BB13)
.proc KeyPressed
    lda PendingEvents
    and #$7F
    sta PendingEvents
    jsr PushGoSubEntryHereChecked
    ldx #END_OF_FILE_HANDLERS_SIZE          ; Handler 11, times 3
    bne EndOfFile::GoToHandler              ; Always
.endproc

.endscope
.assert END_OF_FILE_HANDLERS_SIZE = 3 * Handlers::KEYBOARD, "The keyboard's handler is the last in EndOfFileHandlers."

; ---------------------------------------------------------------------------------------------------------------------
; DEL
; ---------------------------------------------------------------------------------------------------------------------

; DEL.
.scope Statements continued

;; Ends with SYNTAX, for <Statements::Del>.
;; Also: BLOWDEL (BB13)
.proc ToSyntaxError
    jmp SyntaxError
.endproc

;; The `DEL first[,last]` statement: deletes a line, or the lines from first to last, from the program.
;;
;; A comma, `-` or `TO` may separate the numbers. Run from a program, it may delete only lines after the one it is
;; in. The program's end, the variables and the arrays move down with <CloseGap>, so the variables keep their
;; values; <ClearVariables::RestoreData> then resets the `DATA` pointer and the stack. When the range holds no lines
;; it does nothing.
;; In: carry = clear for a digit next
;; Errors: SYNTAX without a line number, RANGE for a line at or before the current one
;; Entry: ReportRange = ends with RANGE
;; See: <FindLine>, <CloseGap>
;; Also: DELETE (BB13)
.proc Del
    bcs ToSyntaxError                       ; Not a digit
    jsr ReadLineNumber
    jsr FindLine                            ; The first line to delete
    ldx CurrentLine+1
    inx
    beq RangeChecked                        ; Direct: any line
    lda CurrentLine
    cmp LineNumber
    lda CurrentLine+1
    sbc LineNumber+1
    bcc RangeChecked

;; Ends with RANGE.
;; Also: RNGERR (BB13)
ReportRange:
    ldx #ERROR_RANGE
    jmp ReportError

;; Reads the range's end and deletes the lines.
;; Also: RNGOK (BB13)
RangeChecked:
    lda SourceStart
    pha
    lda SourceStart+1
    pha
    lda SourceStartXByte
    pha
    jsr GetCurrentCharacter
    beq FindEnd                             ; One line
    cmp #','
    beq ReadLast
    cmp #'-'
    beq ReadLast
    lda #TOKEN_TO
    jsr MatchTwoByteToken
    bne ToSyntaxError

;; Reads the last line's number.
;; Also: DELOK (BB13)
ReadLast:
    jsr GetNextCharacter
    bcs ToSyntaxError                       ; Not a digit
    jsr ReadLineNumber

;; Finds the first line after the range, and moves what follows it down to the range's start.
;; Also: JSONEL (BB13)
FindEnd:
    inc LineNumber
    bne FindNext
    inc LineNumber+1

;; Finds the line after the range.
FindNext:
    jsr FindLine
    lda SourceStart
    sta Pointer1                            ; Move from here
    lda SourceStart+1
    sta Pointer1+1
    lda SourceStartXByte
    sta Pointer1XByte
    pla
    sta SourceStartXByte
    pla
    sta SourceStart+1
    pla
    sec                                     ; MoveDistance = the range's start less its end
    sta SourceStart
    sbc Pointer1
    sta MoveDistance
    lda SourceStart+1
    sbc Pointer1+1
    ldy SourceStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta MoveDistance+1
    tax
    bpl NotEmpty                            ; $80 or more: the range holds nothing
    rts

;; Closes the gap the lines leave.
NotEmpty:
    tya
    sbc Pointer1XByte
    sta MoveDistanceXByte
    jsr CloseGap
    jmp ClearVariables::RestoreData
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; TEXT and HOME
; ---------------------------------------------------------------------------------------------------------------------

;; The `TEXT` statement: puts the console back in its text mode, with the whole screen, normal video and the screen
;; on, by writing <Statements::TextCodes>.
;;
;; With anything after `TEXT` it returns at once, and the statement fetcher reports SYNTAX.
;; In: zero = set at the end of the statement
;; Entry: Done = returns
;; Also: MSETTXT (BB13)
.proc Text
    bne Done
    ldx #0

;; Writes <Statements::TextCodes> to the console, up to its zero.
;; Also: TXTOUT (BB13)
NextCode:
    lda a:TextCodes,X
    beq Done
    jsr WriteConsoleCharacter
    inx
    bne NextCode

;; Returns.
;; Also: TXTRTS (BB13)
Done:
    rts
.endproc

;; The `HOME` statement: clears the viewport and puts the cursor at its top left.
;;
;; With anything after `HOME` it returns at once, and the statement fetcher reports SYNTAX.
;; In: zero = set at the end of the statement
;; Also: HOME (BB13)
.proc Home
    bne Text::Done
    lda #Console::CLEAR_VIEWPORT
    jmp WriteConsoleCharacter
.endproc

;; The console codes `TEXT` writes, ending in a zero: 80-column text mode with the cursor off, the text options,
;; normal video and the whole screen as the viewport, the screen on, and a carriage return.
;; See: <Statements::Text>
;; Also: TXTCHRS (BB13)
TextCodes:
    .byte Console::SET_TEXT_MODE, Console::TEXT_MODE_80_COLUMNS, Console::CURSOR_OFF
    .byte Console::SET_TEXT_OPTIONS, Console::TEXT_OPTIONS
    .byte Console::NORMAL_VIDEO, Console::RESET_VIEWPORT
    .byte Console::SCREEN_ON, Console::RETURN, 0

.endscope
