; retrocore: style=strict
;; B3INPUF: `INPUT`, `GET` and `READ`, which share one loop over their variables, <AssignVariableList>; `NEXT`; the type
;; checks <EvaluateNumber>, <RequireNumber> and <RequireString>; and the first half of <EvaluateExpression>, the formula
;; evaluator, up to taking an operator off its stack (B3EvalG.asm goes on from there).
;;
;; `INPUT`, `GET` and `READ` tell themselves apart by <InputMode>: <INPUT_MODE_INPUT>, <INPUT_MODE_GET> or
;; <INPUT_MODE_READ>. Each keeps the place in its data in <InputPointer> (with its X-byte in <InputPointerXByte>),
;; pointing at the separator before the next item, and the place in the statement's variable list in
;; <VariableListPointer> while <TextPointer> reads the data.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; INPUT, GET and READ
; ---------------------------------------------------------------------------------------------------------------------

;; <InputMode> for `INPUT`.
INPUT_MODE_INPUT = $00

;; <InputMode> for `GET`: bit 6 set.
INPUT_MODE_GET = $40

;; <InputMode> for `READ`: bit 7 set.
INPUT_MODE_READ = $98

;; `CONTROL-C`, as the console reads it: a `CONTROL-C` at the start of `INPUT`'s line stops the program.
CONTROL_C = $03

;; The error number a bad answer to `INPUT` gives `ON ERR`, in <ErrorCode>.
ERROR_REENTER = 254

;; The error number data left over by `INPUT` or `GET` gives `ON ERR`, in <ErrorCode>.
ERROR_EXTRA_IGNORED = 253

;; Handles a data item that does not end in a comma or the end: `INPUT` asks again, `READ` and `GET` end with SYNTAX
;; ERROR.
;;
;; `READ`'s error names the `DATA` statement's line, from <DataLine>.
;; Entry:
;;   ToSyntaxError = ends the statement with a syntax error
;; Also: TRMNOK (BB13)
.proc HandleBadInput
    lda InputMode
    beq RetryInput                          ; INPUT
    bpl ToSyntaxError                       ; GET
    lda DataLine
    ldy DataLine+1
    sta CurrentLine
    sty CurrentLine+1

;; Ends the statement with a syntax error.
;; Also: SNERR4 (BB13)
ToSyntaxError:
    jmp SyntaxError
.endproc

;; Drops the byte <AssignVariableList::ConvertNumber> pushed, then asks again.
;; Also: TRMNO2 (BB13)
.proc DiscardAndRetryInput
    pla
    ; Falls into RetryInput.
.endproc

;; Asks again for `INPUT`'s line: `INPUT#` from a file ends with `TYPE MISMATCH`, and with `ON ERR` the program goes to
;; its line with error <ERROR_REENTER>.
;; Entry:
;;   PrintReenter = prints ?REENTER and runs the `INPUT` statement again from its start
;; Also: TRMNO1 (BB13)
.proc RetryInput
    bit OutputFileNumber                    ; from the console?
    bmi FromConsole
    jmp TypeMismatchError

;; Asks again, unless `ON ERR` takes the error.
FromConsole:
    bit OnErrorActive                       ; ON ERR on?
    bpl PrintReenter
    ldy CurrentLine+1
    iny
    beq PrintReenter
    ldx #ERROR_REENTER
    jmp ReportError

;; Prints ?REENTER and runs the `INPUT` statement again from its start.
;; Also: DOAGIN (BB13)
PrintReenter:
    lda #<(RetryMessage)
    ldx #0
    ldy #>(RetryMessage)
    jsr PrintText
    jsr RewindInputStatement
    pla                                     ; NextStatement's return address: SavePlace, which
    pla                                     ; needs no terminator, runs INPUT again
    jmp NextStatement::SavePlace
.endproc

;; Points <TextPointer> back at the statement's start, from <StoppedText>.
;; Entry:
;;   Done = returns; `INPUT` branches here
;; Also: DOAG2 (BB13)
.proc RewindInputStatement
    lda StoppedText
    ldy StoppedText+1
    ldx StoppedTextXByte
    stx TextPointerXByte
    sta TextPointer
    sty TextPointer+1

;; Returns, for `INPUT`.
;; Also: GTRTS (BB13)
Done:
    rts
.endproc

.scope Statements continued
; GET and INPUT.

;; The `GET` statement: reads one key, without echo, into each variable of its list, from the console, the `EXEC` file
;; while `EXEC` runs, or a file after `#n;`.
;;
;; A numeric variable takes the key's value as `VAL` would give it.
;; In: A = the character after `GET`, flags as <GetCurrentCharacter> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <Console::ReadKey>, <AssignVariableList::SwitchToData>
;; Also: GET (BB13)
.proc Get
    jsr RejectDirectMode
    ldx ExecFile                            ; EXEC's file, if it runs
    bne KeepReference
    ldx Console::LineParameters+1           ; else the console's

;; Reads from the reference number in X, or from the file after `#`.
KeepReference:
    stx Console::KeyReference
    cmp #'#'
    bne StartLoop
    jsr Files::TakeFileNumber
    sta Console::KeyReference
    jsr CheckSemicolon

;; Starts the variable loop with no data, the zero at <InputBuffer>+1, so each variable reads a key.
;; Also: GOTREF (BB13)
StartLoop:
    ldx #<(InputBuffer+1)
    ldy #>(InputBuffer+1)
    lda #$80                                ; no terminators
    sta InQuotes
    lda #0
    sta SavedY                              ; the data's X-byte
    sta InputBuffer+1
    sta InputBuffer
    lda #INPUT_MODE_GET
    jmp AssignVariableList
.endproc

;; The `INPUT` statement: prints a prompt, reads a line from the console, or from a file after `#n;`, and assigns its
;; items to the variables of the list.
;;
;; The prompt is the string given, or `?`. Items are separated by commas; the last variable, when a string, takes the
;; rest of the line, commas and all. When the line runs out, `??` asks for more. `CONTROL-C` at the start of the line
;; stops the program, where `CONT` runs the `INPUT` again.
;; In: A = the character after `INPUT`, flags as <GetCurrentCharacter> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <AssignVariableList>, <HandleBadInput>, <AssignVariableList::ListDone>
;; Also: INPUT (BB13)
.proc Input
    jsr RejectDirectMode
    jsr GetCurrentCharacter
    cmp #'"'                                ; a prompt?
    bne CheckFile
    jsr ReadQuotedString
    jsr GetCurrentCharacter
    cmp #','
    beq PrintPrompt
    lda #';'                                ; not a comma: it must be a semicolon

;; Checks the comma or semicolon after the prompt, prints the prompt, and reads the line.
;; Also: INPAOK (BB13)
PrintPrompt:
    jsr CheckCharacter
    jsr PrintString
    jmp ReadInputLine

;; Takes `INPUT# n;` from a file, or prints the `?` prompt.
;; Also: NOTQT0 (BB13)
CheckFile:
    cmp #'#'
    bne QuestionPrompt
    ror FileAccessMode
    jsr Files::TakeFileAndRecord
    jsr GetCurrentCharacter
    cmp #';'
    bne RewindInputStatement::Done          ; no semicolon: NextStatement gives the syntax error
    lda CurrentFileNumber
    sta OutputFileNumber
    jsr GetNextCharacter
    jsr Files::ReadTextLine
    lda #','                                ; a comma before the line, as the separator
    sta InputBuffer-1
    jmp AssignInputList

;; Prints the `?` prompt.
;; Also: NOTQTI (BB13)
QuestionPrompt:
    jsr PrintQuestionMark

;; Reads `INPUT`'s line from the console into <InputBuffer>, with a comma before it.
;; Also: NOTQTII (BB13)
ReadInputLine:
    ldx #0
    stx InQuotes                            ; commas end items
    dex
    stx OutputFileNumber                    ; from the console
    lda #','
    sta InputBuffer-1
    jsr InputLine
    lda InputBuffer
    cmp #CONTROL_C                          ; CONTROL-C at the start?
    bne AssignInputList
    jsr RewindInputStatement                ; so CONT runs the INPUT again
    lda #CONTROL_C
    jmp HandleBreak::WithFlags
.endproc

.endscope

;; Prints `?` and reads a line from the console, so a second `?` follows `INPUT`'s.
;; Also: QINLIN (BB13)
.proc PromptAndInputLine
    jsr PrintQuestionMark
    jmp InputLine
.endproc

.scope Statements continued
; READ.

;; The `READ` statement: assigns the items of the program's `DATA` statements to the variables of the list, from
;; <DataPointer> on; `READ#` reads from a file instead.
;; In: A = the character after `READ`, flags as <GetCurrentCharacter> sets them
;; Errors: OUT OF DATA when the `DATA` statements run out, SYNTAX ERROR for a bad item (on the `DATA`'s line)
;; See: <AssignVariableList::SearchData>, <ReadFile>, <Statements::Restore>
;; Also: READ (BB13)
.proc Read
    ldx DataPointerXByte
    stx SavedY
    ldx DataPointer
    ldy DataPointer+1
    cmp #'#'
    bne StartLoop
    jmp ReadFile

;; Starts `READ`'s variable loop.
;; Also: READON (BB13)
StartLoop:
    lda #0
    sta InQuotes
    lda #INPUT_MODE_READ
    .byte $2C                               ; BIT absolute skips AssignInputList's LDA
    ; Falls into AssignInputList.
.endproc

.endscope

;; Starts `INPUT`'s variable loop.
;; In: X, Y = the data's place (low, high), SavedY = its X-byte
;; Also: INPCON (BB13)
.proc AssignInputList
    lda #INPUT_MODE_INPUT
    ; Falls into AssignVariableList.
.endproc

;; Assigns an item of the data to each variable of `INPUT`'s, `GET`'s or `READ`'s list.
;;
;; <InputPointer> keeps the place in the data while <VariableListPointer> keeps the place in the list. `GET` reads a key
;; when its data, which starts empty, runs out; `READ` looks for the next `DATA` statement; `INPUT` reads another line.
;; In: A = <InputMode>'s value, X, Y = the data's place (low, high), SavedY = its X-byte
;; Errors: OUT OF DATA when `READ` finds no more `DATA`, and <HandleBadInput>'s for a bad item
;; Entry:
;;   SearchData = looks for the next `DATA` statement
;;   ListDone = ends the loop
;; See: <FindVariableToAssign>, <AssignString>, <StoreNumber>
;; Also: INPCO1 (BB13)
.proc AssignVariableList
    sta InputMode
    stx InputPointer
    ldx SavedY
    stx InputPointerXByte
    sty InputPointer+1

;; Takes the next variable of the list; for `INPUT` and `GET`, the last one takes the data with no terminators.
;; Also: INLOOP (BB13)
NextVariable:
    jsr FindVariableToAssign                ; the variable's address in AssignedVariable
    bit InputMode
    bmi SwitchToData                        ; READ
    jsr GetCurrentCharacter
    bne SwitchToData
    lda #$80                                ; the last variable: no terminators
    sta InQuotes

;; Moves <TextPointer> to the data, keeping the list's place in <VariableListPointer>, and takes the next item; at the
;; end of the data, `GET` reads a key, `READ` finds the next `DATA` statement, and `INPUT` reads another line.
;; Also: INLP2 (BB13)
SwitchToData:
    jsr SaveTextPointer
    ldx InputPointer
    ldy InputPointer+1
    lda InputPointerXByte
    sta TextPointerXByte
    stx TextPointer
    sty TextPointer+1
    ldy #0
    lda (TextPointer),y                     ; the separator, or the data's end
    bne NextValue
    bit InputMode
    bvc SourceEmpty
    jsr Console::ReadKey                    ; GET: a key into LastKey
    ldx #<(LastKey)
    ldy #>(LastKey)
    stx StringPointer
    sty StringPointer+1
    lda #0
    sta StringPointerXByte
    lda ValueType
    pha
    ldy Console::KeyTransferred             ; the count read: one
    jsr Strings::CopyText
    pla
    sta ValueType
    jsr ConvertKey
    jsr AssignFac
    jmp CheckTerminator

;; Gets more data: `READ` looks for the next `DATA`, `INPUT` reads another line from its file or the console.
;; Also: QDATA (BB13)
SourceEmpty:
    bmi ToSearchData                        ; READ
    bit OutputFileNumber
    bmi AskForMore                          ; the console
    jsr Files::ReadTextLine
    jmp SetCursor

;; Asks for more with `??`.
;; Also: QD11 (BB13)
AskForMore:
    jsr PrintQuestionMark
    jsr PromptAndInputLine

;; Points <TextPointer> at the new line.
;; In: X, Y = the line's place (low, high)
;; Also: DATBK (BB13)
SetCursor:
    stx TextPointer
    lda InputPointerXByte
    sta TextPointerXByte
    sty TextPointer+1

;; Takes the item after the separator: a number, or a string.
;; Also: DATBK1 (BB13)
NextValue:
    ldy #1
    jsr AdvanceTextPointer                  ; past the separator
    bit ValueType
    bpl ConvertNumber                       ; a number
    bit InputMode
    bvc SetDelimiters
    inx                                     ; GET (never here: its data stays the zero)
    stx TextPointer

;; Takes the string up to the data's end, with no terminators.
;; Also: NOTERMS (BB13)
NoDelimiters:
    lda #0
    sta Delimiter
    beq StringAtCursor

;; Goes on looking for `READ`'s next `DATA` statement.
;; Also: DTLP1 (BB13)
ToSearchData:
    jmp SearchData

;; Chooses the string's terminators: a quote for a quoted string, a comma otherwise, none for the last variable of
;; `INPUT`.
;; Also: SETQUT (BB13)
SetDelimiters:
    ldy #0
    lda (TextPointer),y
    sta Delimiter
    bit InQuotes
    bmi NoDelimiters
    cmp #'"'                                ; a quote: the string is inside it
    beq MakeString
    lda #','
    sta Delimiter

;; Starts the string at <TextPointer> itself.
;; Also: RESETC (BB13)
StringAtCursor:
    clc

;; Makes a string of the item and assigns it.
;; In: A = <EndDelimiter>'s terminator, carry = set to start after <TextPointer> (past a quote)
;; Also: NOWGET (BB13)
MakeString:
    sta EndDelimiter
    lda TextPointer
    ldx TextPointerXByte
    ldy TextPointer+1
    adc #0
    bcc HaveAddress
    iny
    cpy #POINTER_PAGE_LIMIT
    bcc HaveAddress
    inx
    ldy #POINTER_PAGE_FIRST

;; Makes the string, moves <TextPointer> past it and assigns it.
;; Also: NOWGE1 (BB13)
HaveAddress:
    jsr Strings::FromTextUntil
    jsr SetTextPointer
    jsr AssignString
    jmp CheckTerminator

;; Takes a number: an empty `INPUT` line, or an `INPUT` item with no digits, asks again.
;; In: overflow = set for a long integer, as <ValueType>'s BIT sets it
;; Also: NUMINS (BB13)
ConvertNumber:
    pha
    lda InputBuffer
    beq EmptyNumber                         ; an empty line

;; Reads the number, a long integer through <LongInteger::ReadNumber> or a real through <Float::ReadNumber>.
;; Also: NUMINS2 (BB13)
ReadNumber:
    pla
    bvs ReadLongInteger                     ; a long integer
    jsr Float::ReadNumber
    bit InputMode
    bvs StoreValue                          ; GET
    bmi StoreValue                          ; READ
    pha
    lda DigitsSeen
    bmi EmptyNumber                         ; no digits
    pla

;; Stores the number as a real or an integer, as the variable is.
;; Also: NUMINS3 (BB13)
StoreValue:
    lda IntegerType
    jsr StoreNumber

;; Checks what ends the item, a terminator or a comma, then keeps the data's place and takes the next variable.
;; Also: STRDN2 (BB13)
CheckTerminator:
    jsr GetCurrentCharacter
    beq TerminatorOk
    cmp #','
    beq TerminatorOk
    jmp HandleBadInput

;; Keeps the data's place in <InputPointer>, goes back to the list, and takes the next variable or ends.
;; Also: TRMOK (BB13)
TerminatorOk:
    lda TextPointer
    ldx TextPointerXByte
    ldy TextPointer+1
    sta InputPointer
    stx InputPointerXByte
    sty InputPointer+1
    jsr RestoreTextPointer
    jsr GetCurrentCharacter
    beq ListDone
    jsr CheckComma
    jmp NextVariable

;; Reads a long integer and stores it.
;; Also: NUMBCD (BB13)
ReadLongInteger:
    jsr LongInteger::ReadNumber
    jsr StoreLongInteger
    jmp CheckTerminator

;; Handles a missing number: `INPUT` asks again; `READ` and `GET` go on to read it.
;;
;; The empty-line test reads <InputBuffer> even for `READ`, whose data is elsewhere, so `READ` comes here for nothing at
;; times.
;; Also: MAYBAD (BB13)
EmptyNumber:
    lsr DigitsSeen
    lda InputMode
    bne ReadNumber
    jmp DiscardAndRetryInput

;; Looks for the next `DATA` statement, from <TextPointer>, keeping its line number in <DataLine>.
;; Errors: OUT OF DATA at the program's end
;; Also: DATLOP (BB13)
SearchData:
    jsr FindStatementEnd                    ; the statement's end
    iny
    tax
    bne CheckStatement                      ; a colon: the next statement is on this line
    ldx #ERROR_OUT_OF_DATA
    lda (TextPointer),y                     ; the next line's link
    bne NextDataLine
    jmp ReportError

;; Takes the next line's number.
NextDataLine:
    iny
    lda (TextPointer),y                     ; the line number's low byte
    sta DataLine
    iny
    lda (TextPointer),y                     ; and its high byte
    iny
    sta DataLine+1

;; Checks the statement's first byte for `DATA`, and takes its first item when it is.
;; Also: NOWLIN (BB13)
CheckStatement:
    lda (TextPointer),y
    tax
    jsr AdvanceTextPointer
    cpx #TOKEN_DATA
    bne SearchData
    jsr GetNextCharacter
    jsr BackUpTextPointer
    jmp NextValue

;; Ends the variable loop: `READ` keeps its place in <DataPointer>; `INPUT` and `GET` check that the data is used up.
;;
;; Data left over prints ?EXTRA IGNORED through <ReportMessage>, which ends at <ReadyForCommand>; with `ON ERR` the
;; program goes to its line with error <ERROR_EXTRA_IGNORED> instead.
;; Also: VAREND (BB13)
ListDone:
    lda #0
    sta InQuotes
    lda InputPointer
    ldy InputPointer+1
    ldx InputPointerXByte
    bit InputMode
    bpl CheckExtra
    jmp Statements::Restore::SetDataPointer ; READ

;; Checks for data left over.
;; Also: VARY0 (BB13)
CheckExtra:
    ldy #0
    lda (InputPointer),y                    ; the end should be a zero
    beq RestoreOutput
    jsr RestoreOutput
    bit OnErrorActive                       ; ON ERR on?
    bpl PrintExtraIgnored
    ldx #ERROR_EXTRA_IGNORED
    ldy CurrentLine+1
    iny
    beq PrintExtraIgnored
    jmp ReportError

;; Prints ?EXTRA IGNORED and the line.
;; Also: INPVAR0 (BB13)
PrintExtraIgnored:
    lda #<(ExtraIgnoredMessage)
    ldx #0
    ldy #>(ExtraIgnoredMessage)
    jmp ReportMessage

;; Sends output back to its usual place, after `INPUT#`.
;; Also: INPRTS (BB13)
RestoreOutput:
    lda OutputFileNumber+1
    sta OutputFileNumber
    rts
.endproc

;; Keeps <TextPointer> in <VariableListPointer>.
;; Uses: A, X, Y
;; See: <RestoreTextPointer>
;; Also: SVTXT (BB13)
.proc SaveTextPointer
    lda TextPointer
    ldy TextPointer+1
    ldx TextPointerXByte
    stx VariableListPointerXByte
    sta VariableListPointer
    sty VariableListPointer+1
    rts
.endproc

;; Sets <TextPointer> back from <VariableListPointer>.
;; Uses: A
;; Keeps: X, Y
;; See: <SaveTextPointer>
;; Also: RSTTXT (BB13)
.proc RestoreTextPointer
    lda VariableListPointer
    sta TextPointer
    lda VariableListPointer+1
    sta TextPointer+1
    lda VariableListPointerXByte
    sta TextPointerXByte
    rts
.endproc

;; The message for data left over, ending in a zero.
;; Also: EXIGNT (BB13)
ExtraIgnoredMessage:
    .byte "?EXTRA IGNORED"
    .byte 0

;; The message asking for `INPUT`'s line again, ending in a zero.
;; Also: TRYAGN (BB13)
RetryMessage:
    .byte "?REENTER"
    .byte RETURN_CHARACTER, LINE_FEED_CHARACTER, 0

;; Turns `GET`'s string into the variable's type: a real through <Functions::Val>, a long integer through
;; <LongInteger::StringToLong>.
;; In: ValueType = the variable's type
;; Also: CHANGTP (BB13)
.proc ConvertKey
    bit ValueType
    bmi IsString
    bvs ToLongInteger
    jmp Functions::Val

;; Returns: a string variable takes the string as it is.
;; Also: ISSTRIN (BB13)
IsString:
    rts

;; Turns the string into a long integer.
;; Also: ISLONG (BB13)
ToLongInteger:
    jmp LongInteger::StringToLong
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; NEXT
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; NEXT.

;; The `NEXT` statement: adds the step to the loop's variable, and goes back after the `FOR` unless the variable has
;; passed the limit.
;;
;; `NEXT` alone takes the newest <ForEntry>; `NEXT` with variables takes each one's entry in turn, dropping the newer
;; `FOR` entries above it. The loop ends when the comparison of the new value with the limit (1 for greater, 0 for
;; equal, $FF for less) equals the step's sign; then the entry comes off the stack.
;; In: A = the character after `NEXT`, zero = set for a terminator
;; Errors: NEXT WITHOUT FOR when there is no entry for the variable
;; See: <Statements::For>, <FindForFrame>
;; Also: NEXT (BB13)
.proc Next
    bne WithVariable
    ldy #0
    sty AssignedVariable+1
    sty AssignedVariable
    beq SearchFrame                         ; AssignedVariable zero: the newest entry

;; Finds the loop variable's offset and type, the key of its `FOR` entry.
;; Also: GETFOR (BB13)
WithVariable:
    jsr FindVariableToAssign
    jsr Variables::VariableOffset
    lda ArrayElementFound
    rol a
    lda IntegerType
    adc #0                                  ; an array element into bit 0
    sta ForVariableType
    lda AssignedVariable+1
    ldy AssignedVariableXByte
    jsr Memory::PackPages
    sta AssignedVariable+1

;; Finds the `FOR` entry.
;; Also: STXFOR (BB13)
SearchFrame:
    jsr FindForFrame
    beq AddStep
    ldx #ERROR_NEXT_WITHOUT_FOR
    jmp ReportError

;; Cuts the stack to the entry, then adds the step to the variable's value.
;; In: X = the entry's place on the stack
;; Also: HAVFOR (BB13)
AddStep:
    lda #$FE                                ; the packed offset's X-byte
    sta AssignedVariableXByte
    txs
    txa
    clc
    adc #<(StackTop + ForEntry::STEP)
    tay
    adc #ForEntry::LIMIT - ForEntry::STEP
    sta Pointer2                            ; the limit, for Float::CompareAtPointer2
    tya
    ldy #>(StackTop + ForEntry::STEP)       ; in page 1
    ldx #0
    jsr Float::LoadFac                      ; the step into the Fac
    tsx
    lda StackTop + ForEntry::STEP_SIGN,x
    sta FacSign
    jsr Variables::VariableOffset           ; the offset back into the variable's address
    bit IntegerType
    bpl RealVariable
    jsr Float::CopyFacToArg                 ; an integer: the step into Arg
    lda AssignedVariable
    sta FacMantissa3
    lda AssignedVariable+1
    sta FacMantissa3+1
    lda AssignedVariableXByte
    sta FacMantissa3XByte
    jsr LoadNumericVariable::FloatInteger   ; and the variable into the Fac
    jmp AddAndCompare

;; Takes a real variable's value into <Arg>.
;; Also: HAVFLT (BB13)
RealVariable:
    ldy AssignedVariable+1
    ldx AssignedVariableXByte
    lda AssignedVariable
    jsr Float::LoadArg

;; Adds, compares with the limit, stores the new value, and loops or ends.
;; Also: HAVSUM (BB13)
AddAndCompare:
    lda ArgSign
    eor FacSign
    sta ResultSign
    lda FacExponent                         ; zero set for a zero Fac
    jsr Float::AddArg
    ldy #>(StackTop + ForEntry::LIMIT)
    jsr Float::CompareAtPointer2            ; with the limit
    pha
    bit IntegerType
    jsr StoreNumber                         ; store it as LET does
    pla
    tsx
    sec
    sbc StackTop + ForEntry::STEP_SIGN,x    ; less the step's sign
    beq EndLoop                             ; equal: the loop is done
    lda StackTop + ForEntry::LINE,x
    sta CurrentLine
    lda StackTop + ForEntry::LINE + 1,x
    sta CurrentLine+1
    lda StackTop + ForEntry::TEXT_LOW,x     ; the FOR statement's end, an offset from ProgramStart
    clc
    adc ProgramStart
    sta TextPointer
    lda StackTop + ForEntry::TEXT_HIGH,x
    adc ProgramStart+1
    ldy ProgramStartXByte
    jsr Memory::NormalizeAfterAdd
    sta TextPointer+1
    tya
    adc StackTop + ForEntry::TEXT_BANK,x
    sta TextPointerXByte

;; Goes on with the statement after the `FOR`.
;; Also: NEWSGO (BB13)
ToNextStatement:
    jmp NextStatement

;; Takes the entry off the stack; after a comma, goes on with the next variable.
;;
;; The JSR to <Statements::Next::WithVariable> stands in for <NextStatement>'s return address, which <FindForFrame>
;; passes over; <WithVariable> does not return.
;; In: carry = set
;; Also: LOOPDN (BB13)
EndLoop:
    txa
    adc #FOR_FRAME_SIZE-1                   ; FOR_FRAME_SIZE, with the carry
    tax
    txs
    jsr GetCurrentCharacter
    cmp #','
    bne ToNextStatement
    jsr GetNextCharacter
    jsr WithVariable
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Type checks
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a numeric formula.
;; In: TextPointer = the formula's first character
;; Out: Fac = the value
;; Errors: TYPE MISMATCH for a string or a long integer
;; See: <EvaluateSubexpression>, <RequireNumber>
;; Also: FRMNUM (BB13)
.proc EvaluateNumber
    lda #VALUE_TYPE_REAL
    sta ValueType                           ; a real wanted
    jsr EvaluateSubexpression
    ; Falls into RequireNumber.
.endproc

;; Checks that the value is a number: a string or a long integer is a `TYPE MISMATCH`.
;; Errors: `TYPE MISMATCH` for a string or a long integer
;; Keeps: A, X, Y
;; See: <RequireString>
;; Also: CHKNUM (BB13)
.proc RequireNumber
    clc
    .byte $24                               ; BIT zero page skips RequireString's SEC
    ; Falls into RequireString, past its SEC.
.endproc

;; Checks that the value is a string: anything else is a `TYPE MISMATCH`.
;; Errors: `TYPE MISMATCH` for anything but a string
;; Keeps: A, X, Y
;; Entry:
;;   Mismatch = ends the statement with `TYPE MISMATCH`
;; See: <RequireNumber>
;; Also: CHKSTR (BB13)
.proc RequireString
    sec
    bit ValueType
    bmi IsString
    bvs Mismatch                            ; a long integer passes neither
    bcs Mismatch

;; Returns, for the checks.
;; Also: CHKOK (BB13)
Done:
    rts
    bvc Mismatch                            ; never reached

;; Passes a string when a string is wanted.
;; Also: DOCSTR (BB13)
IsString:
    bcs Done

;; Ends the statement with `TYPE MISMATCH`.
;; Also: CHKERR (BB13)
Mismatch:
    ldx #ERROR_TYPE_MISMATCH
    jmp ReportError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The formula evaluator
;
; EvaluateExpression keeps two stacks. The verb stack, OperatorStack, holds two bytes for each pending operator: its
; number, then its left operand's type (bits 7-6) with its precedence (bits 5-0); OperatorStackTop is the index past the
; top. A zero precedence at the bottom, or where EvaluateSubexpression starts a formula in parentheses, stops operators
; from below. The noun stack, OperandStack, holds each pending left operand, nine bytes: FacMantissa3XByte, then the
; eight bytes from FacExponent; OperandStackTop is the index of the top's last byte.
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a formula: values joined by operators, taken in order of precedence.
;;
;; The precedences, high to low: ^ (8); * / `DIV` `MOD` (6); + - (5); the relational operators (4); `AND` (3); `OR`
;; (2). A relational operator is any of the characters less-than, equals and greater-than, each at most once, combined
;; as bits: greater-than 1, equals 2, less-than 4. The routine goes on into B3EvalG.asm, which does the operator taken
;; off the verb stack and comes back to <EvaluateExpression::WithOperator>.
;; In: TextPointer = the formula's first character, ValueType = the type wanted (<VALUE_TYPE_ANY> for any)
;; Out: the Fac = the value, ValueType = its type, TextPointer = the character after the formula
;; Errors: TYPE MISMATCH when the result is not the type wanted, FORMULA TOO COMPLEX at the 15th pending operator,
;;   SYNTAX ERROR for a relational operator given twice
;; Entry:
;;   KeepingStacks = keeps both stacks as they are, so a formula in parentheses (from <EvaluateSubexpression>) stacks on
;;   the one outside it
;;   WithOperator = goes on with the operator in A; B3EvalG.asm comes back here after doing one
;; See: <EvaluateOperand>, <EvaluateExpression::PopOperand>
;; Also: FRMEVL (BB13)
.proc EvaluateExpression
    lda #0
    sta ExfnNameOffset
    sta OperandStackTop
    sta OperatorStack+1                     ; the bottom's zero precedence
    sta StringFlag
    sta IntegerType
    lda #2
    sta OperatorStackTop

;; Keeps both stacks as they are, so a formula in parentheses (from <EvaluateSubexpression>) stacks on the one outside
;; it.
;; Also: FRMEVL1A (BB13)
KeepingStacks:
    lda ValueType                           ; the type wanted, checked at the end
    pha
    jsr BackUpTextPointer                   ; back one, for EvaluateOperand's GetNextCharacter

;; Takes a value, then the operator after it: a character of <OperatorSymbols>, or an escape token's second byte;
;; anything else ends the formula.
;; Also: FRMEVL1 (BB13)
NextOperand:
    jsr EvaluateOperand

;; The return address <EvaluateExpression::NextOperand>'s JSR pushes, which <Modules::FinishFunction> checks for after a
;; function.
;; Also: EVALRET (BB13)
OperandReturn = * - 1
    jsr GetCurrentCharacter
    ldy #0
    ldx #OPERATOR_COUNT
    cmp #FIRST_TOKEN
    bcc FindOperator                        ; a character
    cmp #TOKEN_ESCAPE
    bne NoOperator                          ; another token: not an operator
    iny
    lda (TextPointer),y                     ; the escape token's second byte

;; Looks the operator up in <OperatorSymbols>, from its end.
;; Also: FNDOPR (BB13)
FindOperator:
    cmp OperatorSymbols-1,x
    beq FoundOperator
    dex
    bne FindOperator

;; Takes the end of the formula as the operator.
;; Also: NOOPR (BB13)
NoOperator:
    ldx #OPERATOR_COUNT
    dey

;; Moves past the escape token's first byte, and gathers the relational operators into <RelationMask>.
;; In: X = the operator's place in <OperatorSymbols>, Y = 1 for an escape token
;; Also: FOUNDOP (BB13)
FoundOperator:
    pha
    clc
    txa
    adc #OPERATOR_NUMBER_OFFSET             ; past the combined relational operators' numbers
    tax
    pla
    dey
    bmi CheckRelation
    jsr GetNextCharacter                    ; the escape token's first byte

;; Takes a relational operator's characters, or goes on with another operator.
;; Also: FOP2 (BB13)
CheckRelation:
    cpx #OPERATOR_LAST_RELATIONAL+1
    bcs ComparePrecedence
    ldx #0
    stx RelationMask

;; Adds a relational character's bit to <RelationMask>; the same one twice is a syntax error.
;; Also: GTRLOP (BB13)
NextRelation:
    cmp #'>'+1
    bcs EndRelations
    cmp #'<'
    bcc EndRelations
    eor #$3F                                ; > 1, = 2, < 3
    cmp #3
    adc #0                                  ; and < 4
    eor RelationMask
    cmp RelationMask                        ; the bit must be new
    bcc ToSyntaxError
    sta RelationMask
    jsr GetNextCharacter
    jmp NextRelation

;; Ends the relational operator: its bits are its number.
;; Also: NOGTRL (BB13)
EndRelations:
    jsr BackUpTextPointer
    lda RelationMask

;; Goes on with the operator in A; B3EvalG.asm comes back here after doing one.
;; Also: FRMEVLZ (BB13)
WithOperator:
    tax

;; Does the pending operator first when its precedence is at least the new one's; otherwise pushes the new one and its
;; left operand, and takes the next value.
;; In: X = the operator's number
;; Also: NOTREL (BB13)
ComparePrecedence:
    ldy OperatorStackTop
    lda OperatorStack-1,y
    and #PRECEDENCE_BITS                    ; the pending operator's precedence
    cmp PrecedenceTable-1,x
    bcs PopOperand
    lda ValueType
    and #TYPE_BITS
    ora PrecedenceTable-1,x
    sta OperatorStack+1,y                   ; type and precedence
    txa
    sta OperatorStack,y                     ; the operator
    iny
    iny
    cmp #OPERATOR_END
    bne KeepVerbTop
    lda OperatorStack-3,y                   ; the formula's end over the bottom's zero: done
    beq CheckResultType

;; Keeps the verb stack's new top, unless it has grown too deep.
;; Also: NT1 (BB13)
KeepVerbTop:
    sty OperatorStackTop
    cpy #VERB_STACK_SIZE
    bcc PushOperand
    jmp FormulaTooComplexError

;; Pushes the <Fac> on the noun stack, nine bytes.
;; Also: STKOK (BB13)
PushOperand:
    lda OperandStackTop
    adc #NOUN_SIZE                          ; carry is clear
    sta OperandStackTop
    tay
    ldx #NOUN_SIZE-2

;; Copies the <Fac>'s eight bytes, then <FacMantissa3XByte> under them.
;; Also: PSHFAC (BB13)
PushFacByte:
    lda FacExponent,x
    sta OperandStack-1,y
    dey
    dex
    bpl PushFacByte
    lda FacMantissa3XByte
    sta OperandStack-1,y
    jmp NextOperand

;; Ends the statement with a syntax error.
;; Also: SNERR5 (BB13)
ToSyntaxError:
    jmp SyntaxError

;; Ends the formula, checking its type against the one wanted.
;; Also: EXPRDN2 (BB13)
CheckResultType:
    pla                                     ; the type wanted
    cmp #VALUE_TYPE_ANY
    beq Return                              ; any
    eor ValueType
    bne ToTypeMismatch

;; Returns, for <EvaluateExpression>.
;; Also: EXPRDN3 (BB13)
Return:
    rts

;; Does the pending operator: pulls its left operand off the noun stack into <Arg> and the operator off the verb stack,
;; checking that the two operands' types agree; B3EvalG.asm goes on to do it.
;; In: X = the new operator, carry = set
;; Errors: TYPE MISMATCH when the operands' types differ
;; Also: DOLAST (BB13)
PopOperand:
    txa
    pha                                     ; the new operator, for later
    lda OperandStackTop
    tay
    sbc #NOUN_SIZE
    sta OperandStackTop
    ldx #NOUN_SIZE-1

;; Copies the eight bytes into <Arg>, then <FacMantissa3XByte>'s byte into <ArgMantissa3XByte>.
;; Also: PLLARG (BB13)
PullArgByte:
    lda OperandStack-1,y
    sta Arg-1,x
    dey
    dex
    bne PullArgByte
    lda OperandStack-1,y
    sta ArgMantissa3XByte
    ldy OperatorStackTop
    dey
    dey
    sty OperatorStackTop
    lda OperatorStack+1,y
    and #TYPE_BITS                          ; the left operand's type
    sta Temporary
    lda ValueType
    and #TYPE_BITS
    eor Temporary
    beq TakeOperator

;; Ends the statement with `TYPE MISMATCH`.
;; Also: CANTFIX (BB13)
ToTypeMismatch:
    jmp RequireString::Mismatch

;; Takes the operator's number into A and <RelationMask>, for <Operators::Apply>.
;; Also: GETOP (BB13)
TakeOperator:
    lda OperatorStack,y
    sta RelationMask
    .assert * = Operators::Apply, "TakeOperator must fall into Operators::Apply, at the start of B3EvalG.asm."
    ; Falls into Operators::Apply.

;; The bits of a verb stack entry's second byte that hold the operator's precedence.
PRECEDENCE_BITS = $3F

;; The bits of a verb stack entry's second byte that hold the left operand's type, as <ValueType>'s bits 7 and 6.
TYPE_BITS = $C0

;; The verb stack's size, two bytes for each of 15 pending operators and the bottom's entry.
VERB_STACK_SIZE = $20

;; The bytes of a noun stack entry: <FacMantissa3XByte>, then the eight bytes from <FacExponent>.
NOUN_SIZE = 9
.endproc
