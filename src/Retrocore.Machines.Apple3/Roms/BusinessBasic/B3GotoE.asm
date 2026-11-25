; retrocore: style=strict
;; B3GOTOE: `GOSUB`, `GOTO`, `RETURN` and `POP`, `ON ... GOTO` and `ON ... GOSUB`, the skips for `DATA` and `REM`,
;; <ReadLineNumber>, `LET` with its string assignment, and `PRINT` with the output routines under it:
;; <PrintCharacter>, <PrintText>, <PrintNewline>, and <Lister::WrapCharacter>, `LIST`'s output with its wrap.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; GOSUB, GOTO and RETURN
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; GOSUB, GOTO, DATA and RETURN.

;; The `GOSUB` statement: puts a <GoSubEntry> on the stack, then goes to the line as `GOTO` does.
;;
;; The entry, from <PushGoSubEntry>, holds <TextPointer> after the line number, where `RETURN` goes on, and the current
;; <CurrentLine>. It goes under <ExecuteStatement::StatementReturn>, the return address to <NextStatement>.
;; In: A = the character after `GOSUB`, flags as <GetCurrentCharacter> sets them
;; Entry:
;;   Transfer = goes to the line whose number is at <TextPointer>, returning to <NextStatement> to run it; `RUN n` comes
;;   here
;; See: <Statements::Return>, <Statements::GoTo>
;; Also: GOSUB (BB13)
.proc GoSub
    jsr SaveTextPointer                     ; TextPointer at the line number
    jsr GetCurrentCharacter
    jsr ReadLineNumber                      ; pass the number
    jsr PushGoSubEntry
    jsr RestoreTextPointer                  ; back to the number, for GOTO

;; Goes to the line whose number is at <TextPointer>, returning to <NextStatement> to run it.
;; Also: RUNC2 (BB13)
Transfer:
    jsr GetCurrentCharacter
    jsr Statements::GoTo
    rts
.endproc

;; The `GOTO` statement: points <TextPointer> at the zero before the line with the number given, so <NextStatement> runs
;; it.
;;
;; When more follows the number, `GOTO` does nothing and <NextStatement> gives the syntax error.
;; In: A = the character after `GOTO`, flags as <GetCurrentCharacter> sets them
;; Errors: UNDEF'D STATEMENT when there is no such line
;; Entry:
;;   ToLineNumber = finds the line numbered <LineNumber> and points <TextPointer> at the zero before its link; `ON`,
;;     `PRINT USING`'s image line and the table of routines for invokable modules come here
;;   SearchFromStart = searches from the program's first line; <Files::StartProgram> comes here to start a program at a
;;   line
;; See: <FindLine::FromLine>
;; Also: GOTO (BB13)
.proc GoTo
    jsr ReadLineNumber
    jsr GetCurrentCharacter
    bne PushGoSubEntry::Done

;; Finds the line numbered <LineNumber> and points <TextPointer> at the zero before its link.
;;
;; A line after the current one is looked for from the next line on; any other, from the program's start (always, in
;; a direct line, whose <CurrentLine> is $FFxx).
;; In: LineNumber = the line number, TextPointer = in the current line
;; Uses: A, X, Y, SourceStart
;; Also: GOTOB (BB13)
ToLineNumber:
    jsr FindLineEnd                         ; Y = the end of the line
    lda CurrentLine
    cmp LineNumber
    lda CurrentLine+1
    sbc LineNumber+1
    bcs SearchFromStart                     ; not later than this line: from the start
    tya                                     ; the next line's link: TextPointer + Y + 1
    ldy TextPointerXByte
    sec
    adc TextPointer
    ldx TextPointer+1
    bcc Search
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc Search
    iny                                     ; page $82 is the next bank's page $02
    ldx #POINTER_PAGE_FIRST
    bne Search
    bcs Search                              ; never reached

;; Searches from the program's first line.
;; Also: LUK4IT (BB13)
SearchFromStart:
    lda ProgramStart
    ldx ProgramStart+1
    ldy ProgramStartXByte

;; Searches from the line at A, X, Y (low, high, bank), then points <TextPointer> one byte before the line found.
;; Also: LUKALL (BB13)
Search:
    jsr FindLine::FromLine
    bcc Statements::Return::UndefinedStatement ; no such line
    lda SourceStart
    sbc #1
    sta TextPointer
    lda SourceStart+1
    sbc #0
    ldy SourceStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta TextPointer+1
    tya
    sbc #0
    sta TextPointerXByte

;; Returns, for the statements here.
;; Also: GORTS (BB13)
Done:
    rts
.endproc

;; The `DATA` statement: in a program, passes over the statement as `REM` does; in a direct line, an error.
;; Errors: ILLEGAL DIRECT in a direct line
;; Also: DATAIS (BB13)
.proc Data
    jsr RejectDirectMode
    bne Statements::Rem                     ; always
.endproc

;; The `RETURN` statement, and `POP`: takes the newest <GoSubEntry> off the stack, with any `FOR` entries above it.
;;
;; `RETURN` goes on from the entry's text pointer, after the `GOSUB`, on its line; `POP` goes on after itself. Both
;; share this handler, and Y, <DispatchStatement>'s index into <StatementTable>, tells them apart.
;; In: Y = the statement's index in <StatementTable>, times two, zero = set for a terminator
;; Errors: RETURN WITHOUT GOSUB when no `GOSUB` entry is under the `FOR` entries
;; Entry:
;;   UndefinedStatement = ends the statement with UNDEF'D STATEMENT; <Statements::GoTo> branches here
;; See: <Statements::GoSub>, <PushGoSubEntry>, <FindForFrame>
;; Also: RETURN (BB13)
.proc Return
    bne Statements::GoTo::Done              ; more follows: NextStatement gives the syntax error
    lda #$FF
    sta ForVariableType                     ; matches no FOR entry
    jsr FindForFrame
    cmp #TOKEN_GOSUB
    beq RestoreCaller
    ldx #ERROR_RETURN_WITHOUT_GOSUB
    .byte $2C                               ; BIT absolute skips the next LDX

;; Ends the statement with UNDEF'D STATEMENT.
;; Also: USERR (BB13)
UndefinedStatement:
    ldx #ERROR_UNDEFINED_STATEMENT
    jmp ReportError

;; Takes the entry off: the stack is cut to it, which drops <NextStatement>'s return address and the `FOR` entries, and
;; `RETURN`'s <CurrentLine> and <TextPointer> come from it.
;; In: X = the entry's place on the stack
;; Also: RETU1 (BB13)
RestoreCaller:
    txs
    pla                                     ; TOKEN_GOSUB
    pla                                     ; the line number's low byte
    cpy #<(TOKEN_POP*2)
    beq Statements::PopFinish
    sta CurrentLine
    pla
    sta CurrentLine+1
    pla
    sta TextPointerXByte                    ; the offset's bank
    clc
    pla
    tay                                     ; its high byte
    pla                                     ; its low byte
    adc ProgramStart
    sta TextPointer
    tya
    adc ProgramStart+1
    ldy ProgramStartXByte
    jsr Memory::NormalizeAfterAdd
    sta TextPointer+1
    tya
    adc TextPointerXByte
    sta TextPointerXByte
    jmp NextStatement::SavePlace
.endproc

.endscope

;; Moves <TextPointer> to the end of the statement: a colon or the line's zero, outside quotes.
;; Out: TextPointer = the terminator
;; See: <FindStatementEnd>, <AdvanceTextPointer>
;; Also: DATA (BB13)
.proc SkipStatement
    jsr FindStatementEnd
    ; Falls into AdvanceTextPointer.
.endproc

;; Adds Y to <TextPointer>, into the next bank past <POINTER_PAGE_LIMIT>.
;; In: Y = the count to add
;; Entry:
;;   Done = returns; a statement returns from here to <NextStatement>
;;   ToSyntaxError = ends the statement with a syntax error; `ON` branches here
;; Also: ADDON (BB13)
.proc AdvanceTextPointer
    tya
    clc
    adc TextPointer
    sta TextPointer
    bcc Done
    lda TextPointer+1
    adc #0
    ldy TextPointerXByte
    jsr Memory::NormalizeAfterAdd
    sty TextPointerXByte
    sta TextPointer+1

;; Returns, for the skips; a statement returns from here to <NextStatement>.
;; Also: REMRTS (BB13)
Done:
    rts

;; Ends the statement with a syntax error.
;; Also: SNERR2 (BB13)
ToSyntaxError:
    jmp SyntaxError
.endproc

.scope Statements continued
; REM.

;; The `REM` statement: moves <TextPointer> to the end of the line.
;; Also: REM (BB13)
.proc Rem
    jsr FindLineEnd
    beq AdvanceTextPointer                  ; always
.endproc

.endscope

;; Finds the end of the statement: a colon or a zero, outside quotes.
;; In: TextPointer = where to start
;; Out: Y = the terminator's index from TextPointer, A = the terminator, zero = set
;; Uses: X, Delimiter, EndDelimiter
;; See: <FindLineEnd>
;; Also: DATAN (BB13)
.proc FindStatementEnd
    ldx #':'
    .byte $2C                               ; BIT absolute skips FindLineEnd's LDX
    ; Falls into FindLineEnd.
.endproc

;; Finds the end of the line: its zero.
;;
;; <Delimiter> and <EndDelimiter> hold the two characters that end the scan besides the zero; a quote swaps them, so
;; inside quotes only the zero ends it.
;; In: TextPointer = where to start
;; Out: Y = the zero's index from TextPointer, A = 0, zero = set
;; Uses: X, Delimiter, EndDelimiter
;; See: <FindStatementEnd>
;; Also: REMN (BB13)
.proc FindLineEnd
    ldx #0
    stx Delimiter
    ldy #0
    sty EndDelimiter

;; Swaps the end characters, at the start and at each quote.
;; Also: EXCHQT (BB13)
SwapDelimiters:
    lda EndDelimiter
    ldx Delimiter
    sta Delimiter
    stx EndDelimiter

;; Scans for a zero or <EndDelimiter>, swapping at each quote.
;; Also: REMER (BB13)
NextCharacter:
    lda (TextPointer),y
    beq AdvanceTextPointer::Done
    cmp EndDelimiter
    beq AdvanceTextPointer::Done
    iny
    cmp #'"'
    bne NextCharacter
    beq SwapDelimiters
.endproc

.scope Statements continued
; POP and ON.

;; Ends `POP`: drops the rest of the <GoSubEntry> and goes on after `POP`.
;; Also: DOPOP (BB13)
.proc PopFinish
    pla
    pla
    pla
    pla
    jmp NextStatement
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; ON ... GOTO and ON ... GOSUB
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON` statement: `ON ERR`, `ON KBD` and `ON EOF#` go to their own handlers; otherwise `ON n GOTO` or
;; `ON n GOSUB` goes to the nth line of the list.
;;
;; An n of 0, or past the list's end, goes on with the next statement.
;; In: A = the character after `ON`, flags as <GetCurrentCharacter> sets them
;; Entry:
;;   RequireGoto = ends the statement with a syntax error unless A is `GOTO`'s token; <ReadLineNumber> branches here
;;   Done = returns; <ReadLineNumber> branches here
;; See: <OnErr>, <OnKbd>, <OnEof>
;; Also: ONGOTO (BB13)
.proc On
    cmp #TOKEN_ERR
    beq ToOnError
    cmp #TOKEN_KBD
    beq ToOnKeyboard
    cmp #TOKEN_EOF
    bne ReadIndex
    jmp OnEof

;; Reads n and the `GOTO` or `GOSUB` after it.
;; Also: ONGOTO2 (BB13)
ReadIndex:
    jsr EvaluateByte                        ; n into FacMantissa4
    pha                                     ; the token after it
    cmp #TOKEN_GOSUB
    beq NextEntry

;; Ends the statement with a syntax error unless A is `GOTO`'s token.
;; Also: SNERR3 (BB13)
RequireGoto:
    cmp #TOKEN_GOTO
    bne AdvanceTextPointer::ToSyntaxError

;; Counts n down, passing a line number for each step; at zero, goes to the line that follows.
;; Also: ONGLOP (BB13)
NextEntry:
    dec FacMantissa4
    bne SkipEntry
    pla
    cmp #TOKEN_GOSUB
    bne GoToEntry
    jsr SaveTextPointer
    jsr SkipStatement                       ; GOSUB's entry goes on after the statement
    jsr PushGoSubEntry
    jsr RestoreTextPointer
    jsr GoToEntry
    rts

;; Reads the line number after <TextPointer> and goes to it through <Statements::GoTo::ToLineNumber>.
;; Also: DOONGT (BB13)
GoToEntry:
    jsr GetNextCharacter                    ; the token or the comma
    jsr ReadLineNumber
    jmp Statements::GoTo::ToLineNumber

;; Passes a line number of the list, and goes on at a comma; at the list's end, `ON` does nothing.
;; Also: ONGLP1 (BB13)
SkipEntry:
    jsr GetNextCharacter
    jsr ReadLineNumber
    cmp #','
    beq NextEntry
    pla

;; Returns, for `ON` and <ReadLineNumber>.
;; Also: ONGRTS (BB13)
Done:
    rts

;; `ON ERR`.
;; Also: GOERR (BB13)
ToOnError:
    jmp OnErr

;; `ON KBD`.
;; Also: GOKBD (BB13)
ToOnKeyboard:
    jmp OnKbd
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Line numbers
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a line number, 0 to 63999, from the text into <LineNumber>; with no digit there, <LineNumber> is 0.
;;
;; A number of 64000 or more is a syntax error through <Statements::On::RequireGoto>, which compares A, the high byte
;; so far, with `GOTO`'s token: when that byte is $BA, as for a number from 47616 to 47871, the
;; error is missed, and the code goes on in `ON`'s loop, counting down <FacMantissa4> and pulling a byte `ON` never
;; pushed.
;; In: A = the character at TextPointer, carry = clear for a digit, as <GetCurrentCharacter> leaves them
;; Out: LineNumber = the number, TextPointer = the character after it, A = that character, flags as <GetNextCharacter>
;;   sets them
;; Errors: SYNTAX ERROR for 64000 or more
;; Uses: X, Delimiter, Pointer1
;; Also: LINGET (BB13)
.proc ReadLineNumber
    ldx #0
    stx LineNumber
    stx LineNumber+1

;; Adds a digit to <LineNumber>, unless the character is not a digit.
;; Also: MORLIN (BB13)
NextDigit:
    bcs Statements::On::Done
    sbc #'0'-1                              ; carry is clear
    sta Delimiter
    lda LineNumber+1
    sta Pointer1
    cmp #TENTH_LIMIT_HIGH                   ; 6400 or more would pass 63999
    bcs Statements::On::RequireGoto
    lda LineNumber                          ; LineNumber times 10: times 4, plus itself, times 2
    asl a
    rol Pointer1
    asl a
    rol Pointer1
    adc LineNumber
    sta LineNumber
    lda Pointer1
    adc LineNumber+1
    sta LineNumber+1
    asl LineNumber
    rol LineNumber+1
    lda LineNumber
    adc Delimiter
    sta LineNumber
    bcc NextCharacter
    inc LineNumber+1

;; Reads the next character.
;; Also: NXTLGC (BB13)
NextCharacter:
    jsr GetNextCharacter
    jmp NextDigit

;; The high byte of 6400: a line number of 6400 or more, times ten, passes 63999.
TENTH_LIMIT_HIGH = 25
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; LET
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; LET.

;; The `LET` statement, and any statement without a keyword: evaluates the formula after `=` and assigns it.
;; In: TextPointer = before the variable's name
;; Errors: TYPE MISMATCH, from <EvaluateExpression>, when the formula's type is not the variable's
;; See: <AssignFac>, <AssignString>
;; Also: LET (BB13)
.proc Let
    jsr FindVariableToAssign                ; the variable's address in AssignedVariable
    jsr CheckEquals
    lda IntegerType
    pha
    lda ArrayElementFound
    pha
    jsr EvaluateExpression
    jmp AssignFac::ByType
.endproc

.endscope

;; Assigns the value in the <Fac> to the variable at <AssignedVariable>, as `LET` does; the disk statements and `INPUT`
;; use it.
;; In: AssignedVariable, AssignedVariableXByte = the variable, <ValueType>, <IntegerType>, ArrayElementFound = its type,
;;   the Fac = the value
;; Entry:
;;   ByType = takes <ArrayElementFound> and <IntegerType> back off the stack; `LET` comes here with them pushed
;; Also: LETP2 (BB13)
.proc AssignFac
    lda IntegerType
    pha
    lda ArrayElementFound
    pha

;; Assigns by the value's type: a string through <AssignString>, a long integer through <StoreLongInteger>, a real or
;; an integer through <StoreNumber>, taking <ArrayElementFound> and <IntegerType> back off the stack.
;; Also: LETP3 (BB13)
ByType:
    pla
    sta ArrayElementFound
    bit ValueType
    bmi Statements::LetString               ; a string
    bvs Statements::LetLongInteger          ; a long integer
    pla
    sta IntegerType
    ; Falls into StoreNumber.
.endproc

;; Stores the <Fac> in the variable at <AssignedVariable>: a real as it is, an integer rounded to two bytes, high byte
;; first.
;; In: negative = set for an integer, as <IntegerType> sets it
;; Also: QINTGR (BB13)
.proc StoreNumber
    bpl ToPackFac
    jsr Float::Round
    jsr FacToInteger
    ldy #0
    lda FacMantissa3
    sta (AssignedVariable),y
    iny
    lda FacMantissa4
    sta (AssignedVariable),y
    rts

;; Stores the <Fac> as a real, through <Float::StoreFacInVariable>.
;; Also: COPFLT (BB13)
ToPackFac:
    jmp Float::StoreFacInVariable
.endproc

.scope Statements continued
; LET's long integers and strings.

;; Stores a long integer, dropping <IntegerType> from the stack.
;; Also: BMOVVF (BB13)
.proc LetLongInteger
    pla
    ; Falls into StoreLongInteger.
.endproc

.endscope

;; Stores the long integer in the <Fac> in the variable at <AssignedVariable>, through <LongInteger::StoreFac>.
;; Also: BMOVF1 (BB13)
.proc StoreLongInteger
    ldx AssignedVariableXByte
    lda AssignedVariable
    ldy AssignedVariable+1
    jmp LongInteger::StoreFac
.endproc

.scope Statements continued
; LET's strings.

;; Assigns a string, dropping <IntegerType> from the stack.
;; Also: COPSTR (BB13)
.proc LetString
    pla
    ; Falls into AssignString.
.endproc

.endscope

;; Assigns the string whose descriptor <FacMantissa3> points to, to the string variable at <AssignedVariable>.
;;
;; A variable's string is copied to new room; a temporary's (one in BASIC's own bank, <FacMantissa3XByte> zero) is taken
;; over. The variable's old string is freed, the descriptor copied in, and the string's information bytes, at
;; <DestinationEnd>, are set to point back at the variable: its type (<STRING_TYPE_SIMPLE_VARIABLE> for a simple
;; variable, <STRING_TYPE_ARRAY_ELEMENT> for an array element) and its offset from <Variables::VariableOffset>. An empty
;; string gets no back pointer.
;; In: FacMantissa3, FacMantissa3XByte = the descriptor, <AssignedVariable>, AssignedVariableXByte = the variable,
;;   ArrayElementFound = negative for an array element
;; Errors: VARIABLE error when the offset does not fit in 16 bits
;; Entry:
;;   MoveCharacters = moves the string into the room <DescriptorPointer> gives and makes its temporary descriptor; the
;;     substring assignment, <Statements::Sub::FillSpaces>, comes here
;;   SetBackPointer = points the string's information bytes back at its variable; `SWAP` comes here
;; Also: INPCOM (BB13)
.proc AssignString
    ldy FacMantissa3XByte                   ; zero for a temporary
    bne CopyCharacters
    lda FacMantissa3
    ldy FacMantissa3+1
    ldx FacMantissa3XByte
    jmp StoreDescriptor

;; Copies a variable's string to new room, making the copy a temporary.
;; Also: COPY (BB13)
CopyCharacters:
    ldy #0
    lda (FacMantissa3),y                    ; the length
    jsr Strings::AllocateForFac

;; Moves the string into the room and makes its temporary descriptor.
;; Also: COPY_M (BB13)
MoveCharacters:
    lda DescriptorPointer
    ldy DescriptorPointer+1
    ldx DescriptorPointerXByte
    sta StringPointer
    sty StringPointer+1
    stx StringPointerXByte
    jsr Strings::CopyString
    jsr Strings::PushTemporary
    lda FacMantissa3
    ldy FacMantissa3+1
    ldx FacMantissa3XByte

;; Frees the temporary descriptor (not its string) and the variable's old string, then copies the descriptor in.
;; In: A, Y, X = the descriptor (low, high, bank)
;; Also: COPY_C (BB13)
StoreDescriptor:
    sta DescriptorPointer
    stx DescriptorPointerXByte
    sty DescriptorPointer+1
    jsr Strings::ReleaseTemporary
    lda AssignedVariable
    ldy AssignedVariable+1
    ldx AssignedVariableXByte
    jsr Strings::FindFromDescriptorAt       ; the old string into Pointer1
    jsr Strings::FreeSpace
    ldy #DESCRIPTOR_SIZE-1

;; Copies the descriptor's three bytes into the variable.
;; Also: COPY_S (BB13)
CopyDescriptor:
    lda (DescriptorPointer),y
    sta (AssignedVariable),y
    dey
    bpl CopyDescriptor
    tax                                     ; the length
    beq Done                                ; empty: no back pointer

;; Points the string's information bytes back at its variable.
;; Also: FIXBAK (BB13)
SetBackPointer:
    jsr Variables::VariableOffset
    lda AssignedVariable+1
    ldy AssignedVariableXByte
    jsr Memory::PackPages                   ; the offset, packed to 16 bits
    cpy #$FF
    bcc Variables::VariableOffset::VariableError
    ldy #2
    sta (DestinationEnd),y
    dey
    lda AssignedVariable
    sta (DestinationEnd),y
    txa                                     ; ArrayElementFound, as VariableOffset leaves X
    bmi ArrayElement
    lda #STRING_TYPE_SIMPLE_VARIABLE
    .byte $2C                               ; BIT absolute skips the LDA

;; Takes an array element's type.
ArrayElement:
    lda #STRING_TYPE_ARRAY_ELEMENT
    dey
    sta (DestinationEnd),y

;; Returns, for `LET`.
;; Also: LETRTS (BB13)
Done:
    rts
.endproc

.scope Variables continued
; A variable's offset.

;; Turns the variable pointer in <AssignedVariable> into an offset: from <ArraysStart> for an array element, otherwise
;; from the simple variables' start through <Variables::SimpleVariableOffset>.
;;
;; An offset is the table's start less the address, so the same subtraction turns it back into the address.
;; In: ArrayElementFound = negative for an array element
;; Out: AssignedVariable, AssignedVariable+1, AssignedVariableXByte = the offset, X = <ArrayElementFound>
;; Errors: OUT OF MEMORY when the array element is not above <ArraysStart>
;; Entry:
;;   ArrayElement = takes <AssignedVariable> as an array element's; the table of routines for invokable modules lists it
;;   VariableError = ends the statement with the VARIABLE error; <AssignString> branches here
;; See: <AssignString::SetBackPointer>
;; Also: RELPTR (BB13)
.proc VariableOffset
    ldx ArrayElementFound
    bpl Simple

;; Takes <AssignedVariable> as an array element's.
;; Also: RELPTR2 (BB13)
ArrayElement:
    lda ArraysStart
    sec
    sbc AssignedVariable
    sta AssignedVariable
    lda ArraysStart+1
    sbc AssignedVariable+1
    ldy ArraysStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta AssignedVariable+1
    tya
    sbc AssignedVariableXByte
    sta AssignedVariableXByte
    bcc Done                                ; a borrow, as there should be
    jmp ReportOutOfMemory

;; Makes a simple variable's offset.
;; Also: ISSIMP (BB13)
Simple:
    jsr Variables::SimpleVariableOffset

;; Returns.
;; Also: GOTRELA (BB13)
Done:
    rts

;; Ends the statement with the VARIABLE error.
;; Also: VAERR (BB13)
VariableError:
    ldx #ERROR_VARIABLE
    jmp ReportError
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; PRINT
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; PRINT's list.

;; Prints a string, then goes on with `PRINT`'s list.
;; Also: STRDON (BB13)
.proc PrintStringItem
    jsr PrintString
    ; Falls into PrintNextItem.
.endproc

;; Goes on with `PRINT`'s list at the current character.
;; Also: NEWCHR (BB13)
.proc PrintNextItem
    jsr GetCurrentCharacter
    ; Falls into PrintList.
.endproc

;; Prints `PRINT`'s list: values, `TAB(` and `SPC(`, with commas and semicolons between; a list that does not end in a
;; comma, a semicolon, `TAB(` or `SPC(` ends with a RETURN.
;;
;; A comma moves to the next column of 16; a semicolon prints nothing.
;; In: A = the character at <TextPointer>, flags as <GetCurrentCharacter> sets them
;; Entry:
;;   Item = prints the rest of the list after a separator, where a terminator ends the line without a RETURN
;; See: <Statements::Print>
;; Also: PRINT (BB13)
.proc PrintList
    beq PrintNewline

;; Prints the rest of the list after a comma, a semicolon, `TAB(` or `SPC(`, where a terminator ends the line without
;; a RETURN.
;; Also: PRINTC (BB13)
Item:
    beq PrintNewline::Return
    lda #TOKEN_TAB
    jsr MatchTwoByteToken
    beq PrintTabOrSpace
    lda #TOKEN_SPC
    jsr MatchTwoByteToken
    clc                                     ; carry clear for SPC(
    beq PrintTabOrSpace
    cmp #','
    beq PrintComma
    cmp #';'
    bne Value
    jmp PrintSpaces::ContinuePrint

;; Evaluates and prints a value of any type.
Value:
    lda #VALUE_TYPE_ANY
    sta ValueType
    jsr EvaluateExpression
    bit ValueType
    bmi Statements::PrintStringItem         ; a string
    bvc Real                                ; a real
    jsr LongInteger::FormatFac              ; a long integer, as text in LongText
    lda #<(LongText)
    sta Pointer1
    lda #>(LongText)
    sta Pointer1+1
    lda #LONG_TEXT_X_BYTE
    sta Pointer1XByte
    ldx LongTextLength
    jsr Output::WriteString
    beq Statements::PrintNextItem           ; always

;; Prints a real, through <Float::FormatFac>'s text.
;; Also: ISBIN (BB13)
Real:
    jsr Float::FormatFac
    jsr Strings::FromText
    jmp Statements::PrintStringItem
.endproc

.endscope

;; Ends the output line: a RETURN, then a line feed when the output goes to the console or another device rather than
;; a disk file; <TerminalPosition> goes back to 0.
;; Uses: A, Temporary, KeptY
;; Entry:
;;   Return = returns; `PRINT`'s list branches here
;; Also: CRDO (BB13)
.proc PrintNewline
    lda #CHARACTER_RETURN
    jsr PrintCharacter
    stx Temporary
    sty KeptY
    ldx OutputFileNumber
    bmi LineFeed                            ; the console
    jsr Files::TakeFileNumber::FromIndex
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,y ; the reference number: bit 7 set for a device
    bpl ResetColumn                         ; a disk file: no line feed

;; Prints the line feed.
;; Also: DOLF (BB13)
LineFeed:
    lda #CHARACTER_LINE_FEED
    jsr PrintCharacter

;; Sets the column back to 0 and takes X and Y back.
;; Also: DOLFRT (BB13)
ResetColumn:
    ldx #0
    stx TerminalPosition
    ldx Temporary
    ldy KeptY

;; Returns, for `PRINT`.
;; Also: PRTRTS (BB13)
Return:
    rts
.endproc

.scope Output
; The output routines Business BASIC adds to Microsoft's.

;; Frees the string just printed, if it was one.
;; In: ValueType = the printed value's type
;; Also: PRTRTS1 (BB13)
.proc FreePrintedString
    bit ValueType
    bpl PrintNewline::Return
    jmp Strings::FreeFacTemporary
.endproc

.endscope

;; Moves to the next column of 16, past the current one.
;; In: carry = set, as the comma's compare leaves it
;; Also: COMPRT (BB13)
.proc PrintComma
    lda TerminalPosition
    adc #COMMA_ZONE-1
    and #<(-COMMA_ZONE)
    ; A check against the window's width is left out here.
    sec
    sbc TerminalPosition
    tax
    jmp PrintSpaces::One

;; The width of the zones a comma moves between.
COMMA_ZONE = 16
.endproc

;; Does `TAB(n)`, which moves to column n (1 first) when the output is short of it, or `SPC(n)`, which prints n spaces.
;; In: carry = set for `TAB(`, clear for `SPC(`
;; Errors: ILLEGAL QUANTITY for `TAB(0)`
;; Also: TABER (BB13)
.proc PrintTabOrSpace
    php
    jsr SkipAndEvaluateByte                 ; n into X
    stx Temporary
    jsr CheckCloseParenthesis
    jsr BackUpTextPointer                   ; back one, for ContinuePrint's GetNextCharacter
    plp
    ldx Temporary
    bcc PrintSpaces                         ; SPC(
    bne NotZero
    jmp Statements::ToIllegalQuantity

;; Works out the spaces to the column.
NotZero:
    dex
    txa
    sbc TerminalPosition
    bcc PrintSpaces::ContinuePrint          ; already past it
    tax
    ; Falls into PrintSpaces.
.endproc

;; Prints X spaces, then goes on with `PRINT`'s list.
;; In: X = the count of spaces
;; Entry:
;;   ContinuePrint = goes on with the list after its separator
;;   One = prints a space and counts it; <PrintComma> comes here
;; Also: XSPAC (BB13)
.proc PrintSpaces
    inx

;; Counts the spaces down.
;; Also: XSPAC2 (BB13)
Next:
    dex
    bne One

;; Goes on with the list after its separator.
;; Also: NOTABR (BB13)
ContinuePrint:
    jsr GetNextCharacter
    jmp Statements::PrintList::Item

;; Prints a space and counts it.
;; Also: XSPAC1 (BB13)
One:
    jsr PrintSpace
    bne Next
.endproc

;; Prints a string that ends in a zero, making a temporary for it.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <Output::PrintTextDirect>
;; Also: STROUT (BB13)
.proc PrintText
    jsr Strings::FromText
    ; Falls into PrintString.
.endproc

;; Prints the string whose descriptor <FacMantissa3> points to, then frees it if it is a temporary.
;; Also: STRPRT (BB13)
.proc PrintString
    jsr Strings::FindFacString
    tax
    ; Falls into Output::WriteString.
.endproc

.scope Output continued
; Writing a string.

;; Prints X characters from <Pointer1>, to the console or the output file, with one SOS `WRITE` through
;; <Console::WriteParameters>.
;;
;; <Console::WriteParameters>'s reference number is the console's; for a file, the file's goes in for the call and the
;; console's comes back. The `WRITE`'s buffer address is <Pointer1> itself, a zero-page pointer, which SOS reads with
;; its X-byte.
;; In: X = the length, Pointer1 = the string, with its X-byte, ValueType = negative for a string to free afterwards
;; Also: STRPR3 (BB13)
.proc WriteString
    stx Console::WriteLength
    txa
    beq Finish
    ldy Console::WriteParameters+1          ; the console's reference number
    bit OutputFileNumber
    bmi Write                               ; the console
    pha
    ldx OutputFileNumber
    jsr Files::TakeFileNumber::FromIndex
    jsr Files::PrepareTextFile
    jsr Files::CheckWriteAccess
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,y ; the file's reference number
    ldy Console::WriteParameters+1
    sta Console::WriteParameters+1
    pla

;; Counts the characters into <TerminalPosition> and makes the `WRITE`.
;; Also: GOOUT (BB13)
Write:
    clc
    adc TerminalPosition
    sta TerminalPosition
    lda #<(Pointer1)
    sta Console::WriteAddress
    lda #>(Pointer1)
    sta Console::WriteAddress+1
    brk
    .byte SOS_WRITE
    .word Console::WriteParameters
    sty Console::WriteParameters+1          ; the console's reference number back
    bne PrintCharacter::WriteError

;; Frees the string, if it was one.
;; Also: STRPR4 (BB13)
Finish:
    jmp Output::FreePrintedString
.endproc

.endscope

;; Prints a space.
;; See: <PrintCharacter>
;; Also: OUTSPC (BB13)
.proc PrintSpace
    lda #' '
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into PrintQuestionMark.
.endproc

;; Prints a question mark.
;; See: <PrintCharacter>
;; Also: OUTQST (BB13)
.proc PrintQuestionMark
    lda #'?'
    ; Falls into PrintCharacter.
.endproc

;; Prints the character in A, to the console or the output file, and counts it in <TerminalPosition>.
;;
;; A file's character goes out with a one-byte SOS `WRITE` through <Console::CharacterParameters>, with the file's
;; reference number put in for the call.
;; In: A = the character, OutputFileNumber = the output file, negative for the console
;; Out: A = the character
;; Entry:
;;   WriteError = ends the statement with the `WRITE`'s error; <Output::WriteString> branches here
;; See: <WriteConsoleCharacter>
;; Also: OUTDO (BB13)
.proc PrintCharacter
    inc TerminalPosition
    bit OutputFileNumber
    bmi Send                                ; the console
    sta Console::Character
    txa
    pha
    tya
    pha
    lda #WRITE_PARAMETER_COUNT
    sta Console::CharacterParameters
    ldx OutputFileNumber
    jsr Files::TakeFileNumber::FromIndex
    jsr Files::PrepareTextFile
    jsr Files::CheckWriteAccess
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,y
    ldy Console::CharacterParameters+1
    sta Console::CharacterParameters+1
    brk
    .byte SOS_WRITE
    .word Console::CharacterParameters
    sty Console::CharacterParameters+1
    bne WriteError
    pla
    tay
    pla
    tax
    lda Console::Character
    rts

;; Ends the statement with the `WRITE`'s error.
;; Also: OTDOER (BB13)
WriteError:
    jmp ReportSosError

;; Prints the character on the console.
;; Also: OUTLOC (BB13)
Send:
    jmp WriteConsoleCharacter

;; The count of SOS `WRITE`'s parameters, the first byte of its parameter list.
WRITE_PARAMETER_COUNT = 3
.endproc

.scope Statements continued
; PRINT.

;; The `PRINT` statement: `PRINT# n;` to a file, `PRINT USING`, or `PRINT` to the console.
;;
;; For the console, the cursor's column is read first, so commas and `TAB(` count from where the cursor is.
;; In: A = the character after `PRINT`, flags as <GetCurrentCharacter> sets them
;; See: <Statements::PrintList>, <PrintUsing::Statement>
;; Also: DOPRINT (BB13)
.proc Print
    cmp #'#'
    bne ReadColumn
    lsr FileAccessMode
    jsr Files::TakeFileAndRecord
    lda CurrentFileNumber
    sta OutputFileNumber
    jsr GetCurrentCharacter
    beq List                                ; nothing more
    cmp #';'
    bne CheckUsing
    jsr CheckCharacter

;; Takes `PRINT USING`, or the plain list.
;; Also: GPRNT (BB13)
CheckUsing:
    lda #TOKEN_USING
    jsr MatchTwoByteToken
    bne List
    jsr PrintUsing::Statement
    rts

;; Prints the list.
;; Also: GPR3 (BB13)
List:
    jsr GetCurrentCharacter
    jmp Statements::PrintList

;; Reads the cursor's column into <TerminalPosition> when the output goes to the console.
;; Also: GPRNT2 (BB13)
ReadColumn:
    bit OutputFileNumber
    bpl ToCheckUsing                        ; to a file: leave TerminalPosition
    jsr ReadCursorPosition
    lda Console::CursorColumn
    sta TerminalPosition

;; Goes on with `PRINT USING` or the list.
;; Also: GPR4 (BB13)
ToCheckUsing:
    jmp CheckUsing
.endproc

.endscope

.scope Output continued
; Printing text directly.

;; Prints a string that ends in a zero, as it is, without the string routines; the length must be under 256.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <PrintText>
;; Also: STROUTR (BB13)
.proc PrintTextDirect
    sta Pointer1
    sty Pointer1+1
    stx Pointer1XByte
    ldy #$FF

;; Counts to the zero.
;; Also: STRLUP (BB13)
Count:
    iny
    lda (Pointer1),y
    bne Count
    tya
    tax
    lda #VALUE_TYPE_REAL                    ; nothing to free
    sta ValueType
    jmp Output::WriteString
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; LIST's output
; ---------------------------------------------------------------------------------------------------------------------

;; `LIST`'s output, which wraps a long line to the column its text started in.
.scope Lister

;; Prints a space as <Lister::WrapCharacter> does.
;; Also: ROUTSPC (BB13)
.proc WrapSpace
    lda #' '
    ; Falls into WrapCharacter.
.endproc

;; Prints a character for `LIST`, first wrapping the line when the output has reached <OutputRecordLength>'s width.
;;
;; A wrapped line goes on after spaces to the column in <MoveDistance>+1, where the listed line's text started.
;; <OutputRecordLength> 0 turns the wrap off.
;; In: A = the character, MoveDistance+1 = the margin
;; Errors: RANGE ERROR when the margin leaves no room in the width
;; See: <Statements::List>, <PrintCharacter>
;; Also: ROUTDO (BB13)
.proc WrapCharacter
    pha
    lda OutputRecordLength
    beq Print                               ; no wrap
    clc
    sbc TerminalPosition                    ; OUTREC less TerminalPosition, less one
    beq Wrap
    bcs Print                               ; room left

;; Ends the output line, to go on at the margin.
Wrap:
    jsr PrintNewline

;; Prints spaces up to the margin.
;; Also: TSTTAB (BB13)
Indent:
    jsr PrintSpace
    lda MoveDistance+1
    cmp TerminalPosition
    bcs Indent
    cmp OutputRecordLength
    bcc Print
    jmp Statements::Del::ReportRange

;; Prints the character.
;; Also: ROUTDONE (BB13)
Print:
    pla
    jmp PrintCharacter
.endproc

.endscope
