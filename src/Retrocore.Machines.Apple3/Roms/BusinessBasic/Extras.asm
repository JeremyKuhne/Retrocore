; retrocore: style=strict ignore=unlinked-name:DATA -- DATA in the message OUT OF DATA
; EXTRAS: statements Business BASIC adds to Applesoft's: OUTREC, INDENT, HPOS and VPOS as statements, NORMAL,
; INVERSE, TRACE and NOTRACE, ON ERR and RESUME, ON KBD, ON EOF# and OFF, DELETE, TEXT and HOME, with the routines
; that test for two-byte tokens and that send a program to its ON KBD or ON EOF# handler.
;
; ON KBD and ON EOF# keep their handlers in EOFPTRS and EOFLINS, three bytes and two each, by number: 1 to 10 for
; the files #1 to #10, 11 for the keyboard. A handler is where its statement continues, as an offset from TXTTAB so
; it survives the program moving, and the line it is in. A zero first byte means no handler.

; ---------------------------------------------------------------------------------------------------------------------
; Screen and listing settings
; ---------------------------------------------------------------------------------------------------------------------

; Business BASIC's added statements.
.scope Statements continued

;; The `OUTREC = n` statement: sets <OUTREC>, `LIST`'s right margin.
;; See: <Statements::GetEqualsByte>
;; Also: SOUTREC (BB13)
.proc OutRec
    jsr GetEqualsByte
    stx OUTREC
    rts
.endproc

;; The `INDENT = n` statement: sets <INDENT>, the spaces `LIST` indents each `FOR` loop by.
;; See: <Statements::GetEqualsByte>
;; Also: SINDENT (BB13)
.proc Indent
    jsr GetEqualsByte
    stx INDENT
    rts
.endproc

;; Reads `=` and a number from 0 to 255, for the statements that set a value.
;; Out: X = the number
;; Errors: SYNTAX without the `=`, ILLEGAL QUANTITY for a number out of range
;; Also: CHKBYT (BB13)
.proc GetEqualsByte
    jsr CHKEQL
    jmp GETBYT
.endproc

;; The `HPOS = n` statement: moves the cursor to column n, counting from 1, and records it in <TRMPOS>.
;; See: <Statements::MoveToColumn>
;; Also: HTAB (BB13)
.proc HPos
    jsr MoveToColumn
    sta TRMPOS                              ; The column, from 0
    rts
.endproc

;; Ends with ILLEGAL QUANTITY, for `TAB(0)`.
;; Also: TOOBIG (BB13)
.proc ToIllegalQuantity
    jmp FCERR
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
    jsr CHKEQL
    jsr GETBYT
    pla
    ; Falls into Console::SendCodeAndPosition.
.endproc

.endscope

; Sending the console a position.
.scope Console continued

;; Sends a console code and its argument, counting from 1, which the console counts from 0.
;; In: A = the code, X = the argument
;; Out: A = the argument as sent
;; See: <DOITOUT>
;; Also: VWINDER (BB13)
.proc SendCodeAndPosition
    jsr PRNACHAR
    txa
    jmp DOITOUT
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
    jmp PRNACHAR
.endproc

;; The `TRACE` statement: sets bit 7 of <TRFLAG>, so the statement fetcher prints each line's number as it runs.
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

;; The `NOTRACE` statement: clears bit 7 of <TRFLAG>.
;; In: zero = set at the end of the statement
;; See: <Statements::Trace>
;; Entry: Done = returns
;; Also: TRACEOFF (BB13)
.proc NoTrace
    clc
    bne Done                                ; Something follows: leave it for SYNTAX
    ror TRFLAG

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
;; It keeps where they start in <ERRTO> (the address of the `ERR` token, with its X-byte in <ERRTOB>) and the line's
;; number in <ERRTO>+3 and +4, and sets bit 7 of <ERRFLG>. `OFF ERR` clears the bit; `RUN`, `NEW`, `LOAD` and editing
;; the program clear <ERRFLG>.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <TrapError>, <ReportError>, <Statements::Off>
;; Also: ONERR (BB13)
.proc OnErr
    jsr ERRDIR
    lda TXTPTR
    sta ERRTO
    lda TXTPTR+1
    sta ERRTO+1
    lda TXTPTRB
    sta ERRTOB
    lda ERRFLG
    ora #$80
    sta ERRFLG
    lda CURLIN                              ; The line, for the handler to run in
    sta ERRTO+3
    lda CURLIN+1
    sta ERRTO+4
    jsr REMN                                ; Skip the handler for now
    jmp ADDON
.endproc

.endscope

;; Runs the `ON ERR` handler: <ReportError> comes here when bit 7 of <ERRFLG> is set.
;;
;; It puts the stack pointer back to <REMSTK>, where the failing statement started, so `FOR` and `GOSUB` entries
;; stay; keeps <OLDTXT>, the failing statement's start, in <ERRPOS> and <ERRPOSB> for `RESUME`; then sets <TXTPTR>
;; and <CURLIN> from <ERRTO> and goes on at the statement after `ON ERR`, through <DIRCON>. <ReportError> has
;; already set <ERRNUM> and <ERRLIN>. The handler stays in force.
;; See: <Statements::OnErr>, <Statements::Resume>
;; Also: HNDLERR (BB13)
.proc TrapError
    ldx REMSTK
    txs
    lda OLDTXT
    sta ERRPOS
    lda OLDTXT+1
    sta ERRPOS+1
    lda OLDTXTB
    sta ERRPOSB
    lda ERRTO
    sta TXTPTR
    lda ERRTO+1
    sta TXTPTR+1
    lda ERRTOB
    sta TXTPTRB
    lda ERRTO+3
    sta CURLIN
    lda ERRTO+4
    sta CURLIN+1
    jmp DIRCON
.endproc

; RESUME.
.scope Statements continued

;; The `RESUME` statement: runs the statement that failed again, from <ERRPOS> in line <ERRLIN>.
;;
;; When no error has been handled (<ERRPOSB> zero) it does nothing.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <TrapError>
;; Also: RESUME (BB13)
.proc Resume
    jsr ERRDIR
    lda ERRPOSB
    beq Done
    sta TXTPTRB
    lda ERRLIN
    sta CURLIN
    lda ERRLIN+1
    sta CURLIN+1
    lda ERRPOS
    sta TXTPTR
    lda ERRPOS+1
    sta TXTPTR+1

;; Returns, to the statement fetcher.
;; Also: RSM2 (BB13)
Done:
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Two-byte tokens
; ---------------------------------------------------------------------------------------------------------------------

;; Tests whether the program has a two-byte token, <TWO_BYTE_TOKEN> and A, at <TXTPTR>, and steps over the first
;; byte if so.
;; In: A = the token's second byte
;; Out: zero = set when found, with <TXTPTR> at the second byte, A = the character at <TXTPTR>
;; Keeps: X, Y
;; See: <RequireTwoByteToken>
;; Also: TRYESC (BB13)
.proc MatchTwoByteToken
    sty YSAVE
    ldy #1
    cmp (TXTPTR),Y
    bne Reread
    dey
    lda (TXTPTR),Y
    cmp #TWO_BYTE_TOKEN
    bne Reread
    jsr CHRGET                              ; Step over the TWO_BYTE_TOKEN
    lda #$00                                ; Found

;; Reads the character at <TXTPTR> again, keeping the flags.
;; Also: TRY2 (BB13)
Reread:
    php
    jsr CHRGOT
    ldy YSAVE
    plp
    rts
.endproc

;; Requires the two-byte token <TWO_BYTE_TOKEN> and A next, and steps past it.
;; In: A = the token's second byte
;; Errors: SYNTAX when it is not there
;; See: <MatchTwoByteToken>, <SYNCHR>
;; Also: MSTESC (BB13)
.proc RequireTwoByteToken
    pha
    lda #TWO_BYTE_TOKEN
    jsr SYNCHR
    pla
    jmp SYNCHR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; ON KBD, ON EOF# and OFF
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON KBD` and `ON EOF#` handlers, kept in <EOFPTRS> and <EOFLINS>, and going to them.
.scope Handlers

;; The handler number of `ON KBD`; `ON EOF#`'s are the file numbers, 1 to 10.
KEYBOARD = 11

.endscope

; ON KBD and ON EOF#.
.scope Statements continued

;; The `ON KBD statements` statement: makes the statements after `KBD` the handler for a key pressed while the
;; program runs, and turns the console's any-key event on.
;;
;; The handler is number <Handlers::KEYBOARD> in <EOFPTRS>; <Handlers::KeyPressed> calls it as a `GOSUB`.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <Statements::OnEof::SetHandler>, <Handlers::KeyPressed>, <Statements::OffKbd>
;; Also: ONKBD (BB13)
.proc OnKbd
    jsr ERRDIR
    lda #1
    sta a:Console::AnyKeyEvent+SosCalls::EventList::PRIORITY
    brk                                     ; D_CONTROL: the any-key event on
    .byte SDCNT
    .word Console::AnyKeyParameters
    ldx #Handlers::KEYBOARD
    bne OnEof::SetHandler
.endproc

;; The `ON EOF#n statements` statement: makes the statements after the file number the handler for reaching the
;; end of file #n.
;;
;; <Handlers::EndOfFile> goes to it as a `GOTO`.
;; Errors: ILLEGAL DIRECT outside a program
;; Entry: SetHandler = records handler X, 1 to 11, at the statements after <TXTPTR>
;; See: <Handlers::EndOfFile>, <Statements::OffEof>
;; Also: ONEOF (BB13)
.proc OnEof
    jsr CHRGET
    jsr ERRDIR
    jsr GTFLNO
    inx                                     ; The file's number, from 1
    jsr DECTPT                              ; Back to the character before the statements

;; Records handler X: where the statements start, relative to <TXTTAB>, in <EOFPTRS>, and the line in <EOFLINS>;
;; then skips the statements.
;; Also: ONEOF2 (BB13)
SetHandler:
    txa
    sta YSAVE
    asl                                     ; Three bytes each
    adc YSAVE
    tax
    jsr Handlers::ToggleOffset
    lda TXTPTR
    sta EOFPTRS-2,X
    lda TXTPTR+1
    sta EOFPTRS-1,X
    lda TXTPTRB
    sta EOFPTRS-3,X
    jsr Handlers::ToggleOffset              ; Back to an address
    lda CURLIN
    sta EOFLINS-3,X
    lda CURLIN+1
    sta EOFLINS-2,X
    jsr REMN                                ; Skip the handler for now
    jmp ADDON
.endproc

.endscope

; The handlers, continued.
.scope Handlers continued

;; Turns <TXTPTR> into an offset from <TXTTAB>, or such an offset back into an address.
;;
;; It replaces <TXTPTR> with <TXTTAB> less <TXTPTR>, which undoes itself when done twice.
;; Keeps: X
;; Also: RELTXT (BB13)
.proc ToggleOffset
    sec
    lda TXTTAB
    sbc TXTPTR
    sta TXTPTR
    lda TXTTAB+1
    sbc TXTPTR+1
    ldy TXTTABB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc TXTPTRB
    sta TXTPTRB
    rts
.endproc

.endscope

; OFF.
.scope Statements continued

;; The `OFF` statement: `OFF KBD`, `OFF EOF#n` or `OFF ERR` turns that handler off.
;;
;; Any other word after `OFF` is ignored here, and left for the statement fetcher.
;; In: A = the token after `OFF`
;; See: <Statements::OffKbd>, <Statements::OffEof>
;; Also: OFF (BB13)
.proc Off
    pha
    jsr CHRGET
    pla
    cmp #KBDTK
    beq OffKbd
    cmp #EOFTK
    beq OffEof
    cmp #ERRTK
    bne Done
    lda ERRFLG                              ; OFF ERR
    and #$7F
    sta ERRFLG

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
    .byte SDCNT
    .word Console::AnyKeyParameters
    ldx #Handlers::KEYBOARD
    bne OffEof::ClearHandler
.endproc

;; `OFF EOF#n`: turns the file's `ON EOF#` handler off.
;; Entry: ClearHandler = clears handler X, 1 to 11
;; See: <Statements::OnEof>
;; Also: OFFEOF (BB13)
.proc OffEof
    jsr GTFLNO
    inx

;; Clears handler X in <EOFPTRS>.
;; Also: OFFEOF2 (BB13)
ClearHandler:
    txa
    sta YSAVE
    asl
    adc YSAVE
    tax
    lda #0
    sta EOFPTRS-2,X
    sta EOFPTRS-1,X
    sta EOFPTRS-3,X
    rts
.endproc

.endscope

; Going to a handler.
.scope Handlers continued

;; Goes to the `ON EOF#` handler of the file in <SVFLNO>, which reached its end, or ends with OUT OF DATA when it has
;; none.
;;
;; It keeps the file's number, from 1, in <EOFSV> for the `EOF` function, puts the stack pointer back to <REMSTK>,
;; sends output back to the `OUTPUT#` device, and goes on at the handler's statements in its line, through <GONE>.
;; In: SVFLNO = the file's number, from 0
;; Entry: GoToHandler = goes to handler X/3, without setting EOF or the stack
;; See: <Statements::OnEof>, <DSKEOF>
;; Also: CHKEOF (BB13)
.proc EndOfFile
    inc SVFLNO
    lda SVFLNO
    sta EOFSV
    asl
    adc SVFLNO
    ldx REMSTK                              ; The stack as the statement started
    txs
    tax

;; Goes to handler X/3 in <EOFPTRS>, or ends with OUT OF DATA when there is none.
;; Also: CKEOF2 (BB13)
GoToHandler:
    lda FILNO+1
    sta FILNO
    lda EOFPTRS-3,X
    beq NoHandler                           ; No handler
    sta TXTPTRB
    lda EOFPTRS-2,X
    sta TXTPTR
    lda EOFPTRS-1,X
    sta TXTPTR+1
    lda EOFLINS-3,X
    sta CURLIN
    lda EOFLINS-2,X
    sta CURLIN+1
    jsr ToggleOffset                        ; Back to an address
    jmp GONE

;; Ends with OUT OF DATA.
;; Also: GIVOD (BB13)
NoHandler:
    ldx #ERROD
    jmp ReportError
.endproc

;; Calls the `ON KBD` handler as a `GOSUB`: the statement fetcher comes here when bit 7 of <KEYSTROK> says the
;; any-key event saw a key.
;;
;; It clears the bit and pushes a `GOSUB` entry, so `RETURN` goes back to the statement that was next.
;; See: <Statements::OnKbd>, <Console::AnyKeyHandler>, <DIRCON>
;; Also: KEYHIT (BB13)
.proc KeyPressed
    lda KEYSTROK
    and #$7F
    sta KEYSTROK
    jsr PSHTXT4
    ldx #EOFSIZ                             ; Handler 11, times 3
    bne EndOfFile::GoToHandler              ; Always
.endproc

.endscope
.assert EOFSIZ = 3 * Handlers::KEYBOARD, "The keyboard's handler must be the last in EOFPTRS."

; ---------------------------------------------------------------------------------------------------------------------
; DELETE
; ---------------------------------------------------------------------------------------------------------------------

; DELETE.
.scope Statements continued

;; Ends with SYNTAX, for <Statements::Delete>.
;; Also: BLOWDEL (BB13)
.proc ToSyntaxError
    jmp SNERR
.endproc

;; The `DELETE first[,last]` statement: deletes a line, or the lines from first to last, from the program.
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
.proc Delete
    bcs ToSyntaxError                       ; Not a digit
    jsr LINGET
    jsr FindLine                            ; The first line to delete
    ldx CURLIN+1
    inx
    beq RangeChecked                        ; Direct: any line
    lda CURLIN
    cmp LINNUM
    lda CURLIN+1
    sbc LINNUM+1
    bcc RangeChecked

;; Ends with RANGE.
;; Also: RNGERR (BB13)
ReportRange:
    ldx #ERRNG
    jmp ReportError

;; Reads the range's end and deletes the lines.
;; Also: RNGOK (BB13)
RangeChecked:
    lda LOWTR
    pha
    lda LOWTR+1
    pha
    lda LOWTRB
    pha
    jsr CHRGOT
    beq FindEnd                             ; One line
    cmp #','
    beq ReadLast
    cmp #'-'
    beq ReadLast
    lda #TOTK
    jsr MatchTwoByteToken
    bne ToSyntaxError

;; Reads the last line's number.
;; Also: DELOK (BB13)
ReadLast:
    jsr CHRGET
    bcs ToSyntaxError                       ; Not a digit
    jsr LINGET

;; Finds the first line after the range, and moves what follows it down to the range's start.
;; Also: JSONEL (BB13)
FindEnd:
    inc LINNUM
    bne FindNext
    inc LINNUM+1

;; Finds the line after the range.
FindNext:
    jsr FindLine
    lda LOWTR
    sta INDEX1                              ; Move from here
    lda LOWTR+1
    sta INDEX1+1
    lda LOWTRB
    sta INDEX1B
    pla
    sta LOWTRB
    pla
    sta LOWTR+1
    pla
    sec                                     ; DELTA = the range's start less its end
    sta LOWTR
    sbc INDEX1
    sta DELTA
    lda LOWTR+1
    sbc INDEX1+1
    ldy LOWTRB
    jsr FIXSBC
    sta DELTA+1
    tax
    bpl NotEmpty                            ; $80 or more: the range holds nothing
    rts

;; Closes the gap the lines leave.
NotEmpty:
    tya
    sbc INDEX1B
    sta DELTAB
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
    jsr PRNACHAR
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
    jmp PRNACHAR
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
