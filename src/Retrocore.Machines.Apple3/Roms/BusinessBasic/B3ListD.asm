; retrocore: style=strict
;; B3LISTD: `LIST`, which turns the program's tokens back into text; `FOR`, which puts a loop's entry on the stack; the
;; statement loop, <NextStatement>, which runs the program one statement at a time; and `RESTORE`, `STOP`, `END`,
;; `CONT`, `BYE`, `RUN` and the push of a `GOSUB` entry.
;;
;; A program line in memory is a <ProgramLine>: a one-byte link (the line's length, from this byte to the next line's
;; link), the line number (low byte, high byte), the tokenized text, and a zero. A zero link ends the program, and a
;; zero stands just before the first line, at <ProgramStart>-1. Pointers into the program carry a bank byte, their
;; X-byte, at their address plus <X_BYTE_OFFSET>, as <TextPointer> does in <TextPointerXByte>, and keep their page in
;; <POINTER_PAGE_FIRST> to <POINTER_PAGE_LIMIT>-1 ($02-$81). Pages $82 and up of one bank are the same memory as pages
;; $02 and up of the next, so a pointer may run past the top and still read the right byte; the code brings it back into
;; range where a line starts.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

;; A program line, as it is stored in memory.
.struct ProgramLine
    ;; The line's length, from this byte to the next line's link; zero ends the program.
    LINK .byte
    NUMBER .word ;; The line number, low byte first.
    TEXT .byte ;; The first byte of the tokenized text, which ends in a zero.
.endstruct

;; A `FOR` loop's entry on the stack, from its top (the lowest address) down.
;;
;; Code reaches a field at <StackTop> plus the field, indexed by the entry's place from `TSX`.
.struct ForEntry
    ;; <TOKEN_FOR>, which marks the entry as a `FOR` loop's.
    TOKEN .byte
    ;; The variable's type: bit 7 set for an integer, bit 0 for an array element (as in <ForVariableType>).
    TYPE .byte
    ;; The variable's offset (low, high), from <Variables::VariableOffset>, packed to 16 bits by <Memory::PackPages>.
    VARIABLE .word
    STEP .res 5 ;; The step, unpacked, as <PushSignedFac> pushes it.
    ;; The step's sign: 1 for positive, 0 for zero, $FF for negative.
    STEP_SIGN .byte
    ;; The limit, packed, its sign in bit 7 of the first mantissa byte.
    LIMIT .res 5
    LINE .word ;; The `FOR` statement's line number, low byte first.
    ;; The text pointer to the `FOR` statement's end, as an offset from <ProgramStart>: its bank, then its high and low
    ;; bytes.
    TEXT_BANK .byte
    TEXT_HIGH .byte ;; The text offset's high byte.
    TEXT_LOW .byte ;; The text offset's low byte.
.endstruct
.assert .sizeof(ForEntry) = FOR_FRAME_SIZE, "A FOR entry is FOR_FRAME_SIZE bytes."

;; A `GOSUB` entry on the stack, from its top (the lowest address) down, as <PushGoSubEntry> builds it.
.struct GoSubEntry
    TOKEN .byte ;; <TOKEN_GOSUB>, which marks the entry as a `GOSUB` entry.
    LINE .word ;; The line number of the `GOSUB`, low byte first.
    ;; The text pointer to where `RETURN` goes on, as an offset from <ProgramStart>: its bank, then its high and low
    ;; bytes.
    TEXT_BANK .byte
    TEXT_HIGH .byte ;; The text offset's high byte.
    TEXT_LOW .byte ;; The text offset's low byte.
.endstruct

;; The lowest token, which the first word of <ReservedWords> or <ExtendedReservedWords> stands for.
FIRST_TOKEN = $80

;; The byte above the stack pointer: the stack's top byte, as code reaches it at StackTop,X after `TSX`.
StackTop = $0101

; ---------------------------------------------------------------------------------------------------------------------
; LIST
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; LIST.

;; The `LIST` statement: lists the program, or the lines in a range, turning tokens back into words.
;;
;; The range is `LIST`, `LIST n`, `LIST n-`, `LIST -m` or `LIST n-m`, where a comma or `TO` may stand for the dash.
;; Each line is printed as a space, its number, <ListIndent> spaces times one more than the `FOR`s open, and its text;
;; text wraps at <OutputRecordLength> to the column the text started in. A `FOR` adds a level for the lines after it and
;; each variable of a `NEXT` takes one away. `CONTROL-C` stops the listing with BREAK.
;; In: A = the character after `LIST`, flags as <GetCurrentCharacter> sets them
;; Uses: A, X, Y, LineNumber, SourceStart, VariableSizes, MoveDistance, Fac, AssignedVariable, InputMode
;; See: <Lister::WrapCharacter>, <Statements::List::CheckToken>, <FindLine>
;; Also: LIST (BB13)
.proc List
    php                                     ; zero set: nothing follows LIST
    ldx #0
    stx MoveDistance                        ; no FOR open yet
    jsr ReadLineNumber                      ; the first line's number, or 0
    jsr FindLine                            ; SourceStart = the first line at or after it
    plp
    bne CheckRange

;; Lists to the end of the program: sets the last line's number to $FFxx.
;; Also: LXZYQ (BB13)
ToProgramEnd:
    lda #LAST_LINE_HIGH
    sta LineNumber+1

;; Reads the rest of the range: a terminator lists the one line, a dash, comma or `TO` reads the last line's number.
;; Also: GOLS1 (BB13)
CheckRange:
    jsr GetCurrentCharacter
    beq StartListing                        ; only one number: the last is the first
    cmp #'-'
    beq ReadLastLine
    cmp #','
    beq ReadLastLine
    lda #TOKEN_TO
    jsr MatchTwoByteToken
    beq ReadLastLine
    jmp SyntaxError

;; Reads the last line's number after the dash, comma or `TO`; nothing there lists to the end.
;; Also: LSTOK (BB13)
ReadLastLine:
    jsr GetNextCharacter
    beq ToProgramEnd
    jsr ReadLineNumber
    jsr GetCurrentCharacter
    bne Done                                ; more after it: NextStatement gives the syntax error

;; Starts the listing at the line <FindLine> found, through <VariableSizes>.
;; Also: LSTEND (BB13)
StartListing:
    lda SourceStart
    sta VariableSizes
    lda SourceStart+1
    sta VariableSizes+1
    lda SourceStartXByte
    sta VariableSizesXByte

;; Lists the line at <VariableSizes>, unless it is past the last line asked for or the program has ended.
;; In: VariableSizes = the line's link byte, LineNumber = the last line to list
;; Also: LIST4 (BB13)
NextLine:
    ldy #ProgramLine::LINK
    lda (VariableSizes),y                   ; a zero link ends the program
    beq Finish
    bit PendingEvents                       ; CONTROL-C?
    bvc NoBreak
    jmp HandleBreak

;; Starts the line on a new output line and reads its number.
NoBreak:
    jsr PrintNewline
    iny
    lda (VariableSizes),y                   ; the line number's low byte
    tax
    iny
    lda (VariableSizes),y                   ; and its high byte
    cmp LineNumber+1
    bne CheckPastEnd
    cpx LineNumber
    beq ListLine

;; Ends the listing when the line's number is past the last one's.
;; In: carry = set when the line is past the last
;; Also: TSTDUN (BB13)
CheckPastEnd:
    bcs Done

;; Prints the line number and the indentation, then the text.
;; In: X, A = the line number (low, high), Y = 2
;; Also: TYPLIN (BB13)
ListLine:
    sty ListOffset
    pha
    jsr Lister::WrapSpace                   ; a space before the number
    pla
    jsr Float::PrintDecimalAX
    ldx ListIndent
    beq SetMargin

;; Prints <MoveDistance>+1 spaces, once for each of <ListIndent>'s spaces per level.
;; Also: PLOOP1 (BB13)
IndentLevel:
    ldy MoveDistance

;; Prints one space of the level's indentation.
;; Also: PLOOP0 (BB13)
IndentSpace:
    jsr PrintSpace
    dey
    bpl IndentSpace
    dex
    bne IndentLevel

;; Notes the column the text starts in, as the margin for wrapped text.
;;
;; A still holds what the output left, which <Statements::List::CheckQuote> prints: a space after the indentation, or,
;; with no indentation, the 0 that SOS's `WRITE` left after the line number.
;; Also: PLOOP3 (BB13)
SetMargin:
    ldy TerminalPosition                    ; the margin for Lister::WrapCharacter's wrap
    sty MoveDistance+1
    ldy ListOffset

;; Prints a character of the line, or starts a quoted string at a quote.
;; In: A = the character, Y = its index in the line
;; Also: PLOOP5 (BB13)
CheckQuote:
    cmp #'"'
    beq QuotedString

;; Prints a character of the line.
;; Also: PLOOP (BB13)
ListCharacter:
    jsr Lister::WrapCharacter

;; Takes the line's next byte: a zero ends the line.
;; Also: PLOOP2 (BB13)
NextByte:
    iny
    lda (VariableSizes),y
    bne CheckToken                          ; not the end: a character or a token

;; Moves <VariableSizes> past the line's zero to the next line's link, into the next bank past <POINTER_PAGE_LIMIT>, and
;; lists it.
;; Also: PLOOP8 (BB13)
NextLineLink:
    sec                                     ; the zero's index, plus one
    tya
    adc VariableSizes
    sta VariableSizes
    bcc NextLine
    ldx VariableSizes+1
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc StorePage
    ldx #POINTER_PAGE_FIRST                 ; page $82 is the next bank's page $02
    inc VariableSizesXByte

;; Stores the link's page and lists the line.
StorePage:
    stx VariableSizes+1
    jmp NextLine

;; Reads the next byte of a reserved-word list, through the pointer in <Fac>.
;;
;; The lists lie in BASIC's own bank, so the page can go up without the bank.
;; In: Y = the index of the byte before
;; Out: A = the byte, negative = set for a word's last character
;; Also: GETNXTW (BB13)
NextTableByte:
    iny
    bne ReadTableByte
    inc Fac+1

;; Reads the byte at Y.
ReadTableByte:
    lda (Fac),y

;; Returns, for the listing's branches.
;; Also: LSTRTS (BB13)
Done:
    rts

;; Ends the listing with a RETURN.
;; Also: GREEDY (BB13)
Finish:
    jmp PrintNewline

;; Prints a quoted string as it is, up to its closing quote or the end of the line.
;; Also: PLOOP7 (BB13)
QuotedString:
    jsr Lister::WrapCharacter
    iny
    lda (VariableSizes),y
    beq NextLineLink
    cmp #'"'
    bne QuotedString
    beq ListCharacter

;; Prints a character, or a token as its reserved word.
;;
;; A token is one byte, $80-$FE, for a word of <ReservedWords>, or <TOKEN_ESCAPE> and a second byte for a word of
;; <ExtendedReservedWords>. A space goes before the word unless it starts the line or follows a token or a colon (or,
;; for an escape token, unless it is a function); a space goes after a word that ends in a letter when a token, a
;; letter, a digit or a period follows. `FOR` and `NEXT` change the indentation of the lines after them in
;; <MoveDistance>.
;; In: A = the byte, negative = set for a token, Y = its index in the line
;; See: <Statements::List::NextTableByte>, <Tokenizer::IsSeparator>
;; Also: QPLOP (BB13)
CheckToken:
    bpl CheckQuote                          ; a character
    cmp #TOKEN_FOR
    bne CheckNext
    inc MoveDistance                        ; FOR: one level more

;; Checks for `NEXT`'s token.
CheckNext:
    cmp #TOKEN_FOR+1                        ; NEXT?
    bne PointAtWords
    sty SavedY

;; Takes a level away for each of `NEXT`'s variables, never below zero.
;; Also: NOTSPEC0 (BB13)
Outdent:
    dec MoveDistance
    bpl FindComma
    inc MoveDistance

;; Looks for another of `NEXT`'s variables, after a comma, up to the end of the statement.
;; Also: NOTSPEC2 (BB13)
FindComma:
    iny
    lda (VariableSizes),y
    beq ReloadToken
    cmp #':'
    beq ReloadToken
    cmp #','
    beq Outdent
    bne FindComma

;; Takes `NEXT`'s token back.
;; Also: NOTSPEC3 (BB13)
ReloadToken:
    ldy SavedY
    lda (VariableSizes),y

;; Points <Fac> at the reserved words: <ReservedWords> for a one-byte token, <ExtendedReservedWords> for an escape
;; token's second byte.
;;
;; <Fac> is set a page below the list, as <Statements::List::NextTableByte>'s first INY takes Y from $FF to 0 and
;; carries into the page.
;; Also: NOTSPEC4 (BB13)
PointAtWords:
    ldx #<(ReservedWords)
    stx Fac
    ldx #>(ReservedWords-256)
    stx Fac+1
    ldx #RESERVED_WORDS_X_BYTE
    stx FacXByte
    tax
    inx                                     ; InputMode = 0 for an escape token, negative for another
    stx InputMode
    cmp #TOKEN_ESCAPE
    bne CountWords
    iny
    lda (VariableSizes),y                   ; the escape token's second byte
    ldx #<(ExtendedReservedWords)
    stx Fac
    ldx #>(ExtendedReservedWords-256)
    stx Fac+1
    ldx #RESERVED_WORDS_X_BYTE
    stx FacXByte

;; Finds the token's word in the list: the token's number, less <FIRST_TOKEN>, counts the words to pass.
;; In: A = the token, Y = the index of its last byte in the line
;; Also: NRMTKN (BB13)
CountWords:
    sec
    sbc #FIRST_TOKEN
    tax
    stx ListToken
    sty ListOffset
    ldy #255                                ; NextTableByte's first INY makes it 0

;; Counts down the words to pass; at zero, the word is found.
;; Also: RESRCH (BB13)
FindWord:
    dex
    bmi SpaceBefore

;; Passes one word, up to its last character's set bit 7.
;; Also: RESCR1 (BB13)
SkipWord:
    jsr NextTableByte
    bpl SkipWord
    bmi FindWord

;; Decides whether a space goes before the word, from what comes before the token.
;;
;; A token at the line's start (<ProgramLine::TEXT>) takes none; nor does one after a colon or a token, nor an escape
;; token for a function (`SGN(` on, in <ExtendedReservedWords>).
;; Also: PRIT25 (BB13)
SpaceBefore:
    lda ListOffset
    cmp #ProgramLine::TEXT                  ; the first byte of the line's text
    beq ListWord
    tya                                     ; the word's index in the list
    pha
    ldy ListOffset
    dey
    bit InputMode                           ; an escape token?
    bmi CheckPrevious
    dey                                     ; yes: look before its escape byte
    lda ListToken
    cmp #TOKEN_FIRST_FUNCTION-FIRST_TOKEN   ; a function: no space
    bcs SpaceUnlessCarry

;; Looks at the byte before the token: carry is set for a colon or a token.
;; Also: PRIT26 (BB13)
CheckPrevious:
    lda (VariableSizes),y
    cmp #':'
    beq SpaceUnlessCarry
    asl a                                   ; bit 7 into carry: a token

;; Prints the space before the word unless carry says not to.
;; In: carry = set for no space
;; Also: PRIT27 (BB13)
SpaceUnlessCarry:
    pla
    tay
    bcs ListWord
    jsr Lister::WrapSpace

;; Prints the word, then its last character without bit 7.
;; Also: PRIT3 (BB13)
ListWord:
    jsr NextTableByte
    bmi LastCharacter
    jsr Lister::WrapCharacter
    jmp ListWord

;; Prints the word's last character, then a space when the word ends in a letter and a token, a letter, a digit or a
;; period follows.
;; Also: PRFINIS (BB13)
LastCharacter:
    and #CHARACTER_BITS
    jsr Lister::WrapCharacter
    ldy ListOffset
    iny
    cmp #'A'                                ; ends in a symbol, as in PR# or CHR$(: no space
    bcc AfterToken
    lda (VariableSizes),y
    bmi SpaceAfter                          ; a token follows
    jsr Tokenizer::IsSeparator
    bcc AfterToken                          ; a separator follows

;; Prints the space after the word.
;; Also: PRF2 (BB13)
SpaceAfter:
    jsr Lister::WrapSpace

;; Goes on with the byte after the token.
;; Also: JPL2 (BB13)
AfterToken:
    dey
    jmp NextByte

;; The high byte of the last line's number when `LIST` lists to the end of the program.
LAST_LINE_HIGH = $FF

;; The bits of a reserved word's character, without the bit 7 its last character has.
CHARACTER_BITS = $7F
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; FOR
; ---------------------------------------------------------------------------------------------------------------------

;; Variables and arrays: finding and making them, their entries, and `FOR`'s variable; the scope is in pieces through
;; the files.
.scope Variables
; Variables' offsets, which survive the variable table moving.

;; Turns the variable pointer in <AssignedVariable> into an offset from the simple variables' start, <VariablesStart>,
;; or back again.
;;
;; The offset is <VariablesStart> less the address, so the same subtraction undoes it. Loops and strings' back pointers
;; keep offsets, which stay right when the variable table moves.
;; Out: AssignedVariable, AssignedVariable+1, AssignedVariableXByte = the offset (or the address)
;; Uses: A, Y, KeptY
;; Entry:
;;   OfPointerAtX = takes the pointer at the zero-page address in X, and returns with X = <KeptY>
;; See: <Variables::VariableOffset>
;; Also: PNTREL (BB13)
.proc SimpleVariableOffset
    stx KeptY
    ldx #AssignedVariable

;; Takes the pointer at the zero-page address in X, and returns with X = <KeptY>.
;; In: X = the zero-page address of the pointer
;; Also: PNTRL1 (BB13)
OfPointerAtX:
    lda VariablesStart
    sec
    sbc 0,x
    sta 0,x
    lda VariablesStart+1
    sbc 1,x
    ldy VariablesStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta 1,x
    tya
    sbc X_BYTE_OFFSET,x                     ; the pointer's X-byte
    sta X_BYTE_OFFSET,x
    ldx KeptY
    rts
.endproc

.endscope

.scope Statements continued
; FOR.

;; The `FOR` statement: assigns the loop variable its first value and puts the loop's entry, a <ForEntry>, on the stack.
;;
;; An entry for the same variable already on the stack is taken out; the newer `FOR` entries above it move up to close
;; the gap and stay. `FOR` then falls into <NextStatement>; the loop's body runs at least once, as <Statements::Next>
;; makes the test.
;; In: A = the character after `FOR`, flags as <GetCurrentCharacter> sets them
;; Errors: TYPE MISMATCH for a string or long-integer variable, OVERFLOW when its offset does not fit in 16 bits
;; See: <Statements::Next>, <FindForFrame>, <Statements::For::ReadStep>
;; Also: FOR (BB13)
.proc For
    jsr Statements::Let
    lda ValueType
    beq IsNumber
    jmp TypeMismatchError                   ; only a real or an integer

;; Notes the variable's type and turns its address into an offset.
IsNumber:
    lda ArrayElementFound
    rol a
    lda IntegerType
    adc #0                                  ; an array element into bit 0
    sta ForVariableType
    jsr Variables::VariableOffset
    lda AssignedVariable+1
    ldy AssignedVariableXByte
    jsr Memory::PackPages
    sta AssignedVariable+1
    cpy #$FE                                ; the offset must fit in 16 bits
    bcs Fits
    jmp Float::OverflowError

;; Takes out an entry for the same variable: moves the stack above it up <FOR_FRAME_SIZE> bytes.
Fits:
    jsr FindForFrame
    bne BuildFrame                          ; no loop on this variable yet
    lda #>StackTop                          ; page 1, in each pointer's high byte and X-byte
    sta DestinationEndXByte
    sta SourceEndXByte
    sta SourceStartXByte
    sta DestinationEnd+1
    sta SourceEnd+1
    sta SourceStart+1
    inx
    stx SourceEnd
    txa
    clc
    adc #FOR_FRAME_SIZE
    sta DestinationEnd
    tsx
    stx SourceStart
    jsr MoveRangeUp::Unchecked
    tsx
    txa
    clc
    adc #FOR_FRAME_SIZE
    tax
    txs

;; Builds the new entry, starting with the text pointer and line number <PushGoSubEntryHere> pushes, then reads `TO`
;; and the limit.
;; Also: NOTOL (BB13)
BuildFrame:
    pla                                     ; NextStatement's return address: FOR falls into NextStatement instead
    pla
    lda #FOR_FRAME_SIZE / 2
    jsr CheckStack                          ; room for the entry
    jsr SaveTextPointer
    jsr SkipStatement                       ; TextPointer to the FOR statement's end
    jsr PushGoSubEntryHere
    pla                                     ; the GOSUB entry's token: not a FOR entry's
    jsr RestoreTextPointer
    lda #TOKEN_TO
    jsr RequireTwoByteToken
    jsr RequireNumber
    jsr EvaluateNumber                      ; the limit
    lda FacSign                             ; pack the sign into the mantissa
    ora #$7F
    and FacMantissa1
    sta FacMantissa1
    lda #<(ReadStep)
    ldy #>(ReadStep)
    sta Pointer1
    sty Pointer1+1
    jmp PushFac                             ; push the limit and go on at ReadStep

;; Pushes the rest of the entry: the step (1 when there is no `STEP`) and its sign, the variable's offset, its type and
;; <TOKEN_FOR>, then falls into <NextStatement>.
;; Also: LDFONE (BB13)
ReadStep:
    lda #<(Float::One)
    ldy #>(Float::One)
    ldx #0
    jsr Float::LoadFac
    lda #TOKEN_STEP
    jsr MatchTwoByteToken
    bne PushStep
    jsr GetNextCharacter
    jsr EvaluateNumber                      ; the step

;; Pushes the step and its sign, then the variable's offset, type and <TOKEN_FOR>.
;; Also: ONEON (BB13)
PushStep:
    jsr Float::GetSign
    jsr PushSignedFac
    lda AssignedVariable+1
    pha
    lda AssignedVariable
    pha
    lda ForVariableType
    pha
    lda #TOKEN_FOR
    pha
    ; Falls into NextStatement.
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The statement loop
; ---------------------------------------------------------------------------------------------------------------------

;; The statement loop: runs the next statement, from where <TextPointer> stands.
;;
;; On entry <TextPointer> points at the terminator of the statement just run: a colon, or the zero that ends a line (for
;; a `GOTO`, the zero before the line's link). Anything else is a syntax error. In a program, <StoppedText> and
;; <StoppedTextXByte> take its value, the place to go on from for `CONT`. At a zero, the next line's link is read at
;; <TextPointer>+1: a zero link ends the program (or the direct line) at <ReadyForCommand>; otherwise the line number at
;; <TextPointer>+2 goes into <CurrentLine> and the pointer moves to <TextPointer>+3, the number's high byte, so
;; <GetNextCharacter> reads the text's first byte. When the page reaches <POINTER_PAGE_LIMIT>, <TextPointerXByte> goes
;; up by one and the page down by a bank's $80 pages. The line number's high byte is $FF while a direct line runs.
;;
;; `CONTROL-C` (bit 6 of <PendingEvents>) stops the program, and a key with `ON KBD` (bit 7) goes to its line, before
;; the next statement.
;; Entry:
;;   SavePlace = keeps <TextPointer> for `CONT` without checking for a terminator; `RETURN`, `CONT`, `INPUT`'s retry and
;;     `IF` come here
;;   CheckEvents = takes a pending `CONTROL-C` or key, then moves to the next statement; the `ON ERR` handler,
;;     <TrapError>, comes here
;; See: <ExecuteStatement>, <DispatchStatement>
;; Also: NEWSTT (BB13)
.proc NextStatement
    lda #0
    sta ProgramLoading                      ; no RUN or CHAIN pending
.if VERSION >= 130
    jsr ProgramPrefix::UseSos               ; 1.3: BASIC's own prefix again
.endif
    tsx
    stx StatementStack                      ; the stack to go back to on an error
    lda OutputFileNumber+1                  ; output back to its usual place
    sta OutputFileNumber
    jsr GetCurrentCharacter
    bne ExecuteStatement::ToSyntaxError     ; no terminator
    ldx CurrentLine+1
    inx
    beq CheckEvents                         ; a direct line: no CONT

;; Keeps <TextPointer> in <StoppedText> for `CONT`, without checking for a terminator.
;; Also: NWSTT (BB13)
SavePlace:
    lda TextPointer
    ldy TextPointer+1
    sta StoppedText
    sty StoppedText+1
    lda TextPointerXByte
    sta StoppedTextXByte

;; Takes a pending `CONTROL-C` or key, then moves to the next statement, or the next line's at the end of a line.
;; Also: DIRCON (BB13)
CheckEvents:
    bit PendingEvents
    bvs ExecuteStatement::ToBreak           ; bit 6: CONTROL-C
    bmi ExecuteStatement::ToKeyHandler      ; bit 7: a key for ON KBD
    ldy #0
    lda (TextPointer),y
    bne ExecuteStatement                    ; a colon: the next statement is on this line
    iny
    lda (TextPointer),y                     ; the next line's link
    clc
    beq DispatchStatement::ToEndOfProgram   ; zero: the program has ended
    iny
    lda (TextPointer),y
    sta CurrentLine
    iny
    lda (TextPointer),y
    sta CurrentLine+1
    tya
    adc TextPointer                         ; TextPointer to the number's high byte
    sta TextPointer
    bcc KeepPageInRange
    inc TextPointer+1

;; Brings <TextPointer>'s page back below <POINTER_PAGE_LIMIT>, moving it into the next bank.
;; Also: CHKPGE (BB13)
KeepPageInRange:
    lda TextPointer+1
    cmp #POINTER_PAGE_LIMIT
    bcc ExecuteStatement
    inc TextPointerXByte
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
    sta TextPointer+1
    ; Falls into ExecuteStatement.
.endproc

;; Runs the statement after <TextPointer>, tracing it first when `TRACE` is on, then goes on to the next.
;;
;; With `TRACE`, every statement of a program (not of a direct line) prints `#` and its line number and a space. The
;; statement's handler is called with <ExecuteStatement::StatementReturn> on the stack, which returns to
;; <NextStatement>. The debugger stops here for each statement.
;; In: TextPointer = the byte before the statement, CurrentLine = its line number
;; See: <DispatchStatement>
;; Also: GONE (BB13)
.proc ExecuteStatement
    tsx
    stx StatementStack
    bit TraceMode
    bpl Dispatch
    ldx CurrentLine+1
    inx
    beq Dispatch                            ; a direct line is not traced
    lda #'#'
    jsr PrintCharacter
    ldx CurrentLine
    lda CurrentLine+1
    jsr Float::PrintDecimalAX
    jsr PrintSpace

;; Reads the statement's first byte and runs it.
;; Also: GOFORIT (BB13)
Dispatch:
    jsr GetNextCharacter
    jsr DispatchStatement

;; The return address <ExecuteStatement::Dispatch>'s JSR pushes, the byte before the JMP back to <NextStatement>.
;; Also: NEWRET (BB13)
StatementReturn = * - 1
    jmp NextStatement

;; Ends the statement with a syntax error.
;; Also: SNERR1 (BB13)
ToSyntaxError:
    jmp SyntaxError

;; Runs the `ON KBD` line for a key.
;; Also: ISAKEY (BB13)
ToKeyHandler:
    jmp Handlers::KeyPressed

;; Stops the program for `CONTROL-C`, through <HandleBreak>, which does not come back.
;; Also: ISCTRLC (BB13)
ToBreak:
    jsr HandleBreak
.endproc

;; Runs a statement: a token from `END` to `NEW` goes to its handler from <StatementTable>, anything else is a `LET`.
;;
;; The handler is reached through an RTS, after <GetNextCharacter>, with the statement's next character in A and the
;; flags set as <GetNextCharacter> sets them.
;; In: A = the statement's first byte, flags as <GetNextCharacter> sets them
;; Entry:
;;   ToEndOfProgram = ends the program at a zero link, as `END` does; <NextStatement> branches here with carry clear
;; Also: GONE3 (BB13)
.proc DispatchStatement
    beq Statements::Restore::Done           ; an empty statement
    ; Carry is already set: GetNextCharacter sets it for anything but a digit, and a digit is a syntax error, as it
    ; should be.
    sbc #TOKEN_END
    ldx #TemporaryDescriptors               ; no string temporaries in use
    stx NextTemporary
    bcc ToLet                               ; not a token: a LET
    cmp #TOKEN_NEW-TOKEN_END+1
    bcs ExecuteStatement::ToSyntaxError     ; a token that is not a statement
    asl a
    tay
    lda StatementTable+1,y
    pha
    lda StatementTable,y
    pha                                     ; the handler's address, less one
    jmp GetNextCharacter

;; Ends the program at a zero link, as `END` does.
;; In: carry = clear
;; Also: INTERM (BB13)
ToEndOfProgram:
    beq Statements::StopOrEnd::Finish

;; Runs a statement without a keyword as `LET`.
;; Also: GLET (BB13)
ToLet:
    jmp Statements::Let
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; RESTORE, STOP, END, CONT and BYE
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; RESTORE.

;; The `RESTORE` statement: points <DataPointer> at the zero before the program, so `READ` starts at the first `DATA`
;; again.
;;
;; The borrow out of the page goes through <Memory::WrapPage>, which only checks the top of the range: a program
;; starting at the start of page <POINTER_PAGE_FIRST> would leave <DataPointer> in page 1, below the usual range (the
;; same byte, by the banks' overlap).
;; Entry:
;;   SetDataPointer = sets <DataPointer> from A, Y and X; `READ` comes here with where its data ended
;;   Done = returns; <DispatchStatement> branches here for an empty statement
;; Also: RESTOR (BB13)
.proc Restore
    sec
    ldx ProgramStartXByte
    lda ProgramStart
    sbc #1
    ldy ProgramStart+1
    bcs SetDataPointer
    dey
    jsr Memory::WrapPage

;; Sets <DataPointer>; `READ` comes here with where its data ended.
;; In: A, Y, X = the pointer (low, high, bank)
;; Also: RESFIN (BB13)
SetDataPointer:
    sta DataPointer
    stx DataPointerXByte
    sty DataPointer+1

;; Returns, for branches.
;; Also: ISCRTS (BB13)
Done:
    rts
.endproc

.endscope

;; Stops the program for `CONTROL-C`, with BREAK, or goes to `ON ERR`'s line with error <ERROR_BREAK>.
;;
;; When the any-key flag is set too, or in a direct line, `ON ERR` is passed over.
;; Entry:
;;   WithFlags = takes <PendingEvents>'s flags in A; `INPUT` comes here with <CONTROL_C> for a `CONTROL-C` typed at its
;;     prompt, which is stored in <PendingEvents> as it is
;; See: <Statements::StopOrEnd>, <TrapError>
;; Also: ISCNTC (BB13)
.proc HandleBreak
    lda PendingEvents

;; Takes the flags in A; `INPUT` comes here with <CONTROL_C> for a `CONTROL-C` typed at its prompt.
;; In: A = <PendingEvents>'s flags
;; Also: ISCNTC2 (BB13)
WithFlags:
    and #<(~KEY_CONTROL_C)
    sta PendingEvents                       ; CONTROL-C taken
    ldx #ERROR_BREAK
    cmp #KEY_ANY
    bcs Stop
    ldy CurrentLine+1
    iny
    beq Stop                                ; a direct line: no ON ERR
    dey
    sty ErrorLine+1
    stx ErrorCode
    ldy CurrentLine
    sty ErrorLine
    bit OnErrorActive                       ; ON ERR on?
    bpl Stop
    jmp TrapError

;; Stops with BREAK, printing to the console.
;; Also: ISRESET (BB13)
Stop:
    stx OutputFileNumber
    sec
    bcs Statements::StopOrEnd               ; always
.endproc

;; <PendingEvents>'s bit for a `CONTROL-C` waiting.
KEY_CONTROL_C = $40

;; <PendingEvents>'s bit for a key waiting for `ON KBD`.
KEY_ANY = $80

;; The error number a break gives `ON ERR`, in <ErrorCode>.
ERROR_BREAK = $FF

.scope Statements continued
; STOP, END, CONT, BYE and RUN.

;; The `END` statement: stops the program without a message.
;; Also: END (BB13)
.proc End
    clc
    ; Falls into Stop.
.endproc

;; The `STOP` statement: stops the program with BREAK.
;; In: A = the character after the keyword, zero = set for a terminator, carry = set for BREAK (<GetNextCharacter> sets
;;   it after `STOP`; `END` clears it)
;; Also: STOP (BB13)
.proc Stop
    bne Statements::Cont::Done              ; not a terminator: NextStatement gives the syntax error
    ; Falls into StopOrEnd.
.endproc

;; Stops the program: keeps <TextPointer> and <CurrentLine> in <StoppedText> and <StoppedLine> for `CONT` (not for a
;; direct line), then goes to <ReadyForCommand>, with BREAK and its line first when carry is set.
;;
;; The debugger stops here for `STOP`, `END` and `CONTROL-C`.
;; In: carry = set to print BREAK
;; Entry:
;;   Finish = goes to <ReadyForCommand>, through BREAK's message when carry is set; the end of the program comes here,
;;   and the debugger watches it
;; Also: STOP2 (BB13)
.proc StopOrEnd
    lda #$FF
    sta OutputFileNumber                    ; output to the console
    sta OutputFileNumber+1
    lda TextPointer
    ldy TextPointer+1
    ldx CurrentLine+1
    inx
    beq DiscardReturn
    sta StoppedText
    sty StoppedText+1
    lda TextPointerXByte
    sta StoppedTextXByte
    lda CurrentLine
    ldy CurrentLine+1
    sta StoppedLine
    sty StoppedLine+1

;; Drops the return address to <NextStatement>.
;; Also: DIRIS (BB13)
DiscardReturn:
    pla
    pla

;; Goes to <ReadyForCommand>, through BREAK's message when carry is set.
;; In: carry = set to print BREAK
;; Also: ENDCON (BB13)
Finish:
    bcc ToReady
    brk                                     ; empty the type-ahead buffer
    .byte SOS_DEVICE_CONTROL
    .word Console::FlushTypeAheadParameters
    jsr PrintNewline
    lda #<(BreakMessage)
    ldx #0
    ldy #>(BreakMessage)
    jmp ReportMessage

;; Goes to <ReadyForCommand>.
;; Also: GORDY (BB13)
ToReady:
    jmp ReadyForCommand
.endproc

;; The `CONT` statement: goes on from where `STOP`, `END`, `CONTROL-C` or an error stopped the program.
;;
;; It runs only in a direct line (in a program it does nothing). It clears <PendingEvents>, sets the any-key event
;; again, and goes on at <StoppedText> on line <StoppedLine>. A zero <StoppedTextXByte> means there is nothing to go on
;; with: CAN'T CONTINUE. Entering or changing a line clears it.
;; In: zero = set for a terminator after `CONT`
;; Entry:
;;   Done = returns; the statements' checks branch here
;; See: <Statements::StopOrEnd>, <NextStatement::SavePlace>
;; Also: CONT (BB13)
.proc Cont
    bne Done
    ldx CurrentLine+1
    inx
    bne Done                                ; in a program: nothing
    stx PendingEvents
    brk
    .byte SOS_DEVICE_CONTROL
    .word Console::AnyKeyParameters
    ldx #ERROR_CANT_CONTINUE
    ldy StoppedTextXByte
    bne Resume
    jmp ReportError                         ; nothing to continue

;; Goes on from the place kept.
Resume:
    lda StoppedText
    sta TextPointer
    sty TextPointerXByte
    lda StoppedText+1
    sta TextPointer+1
    lda StoppedLine
    ldy StoppedLine+1
    sta CurrentLine
    sty CurrentLine+1
    pla                                     ; NextStatement's return address
    pla
    jmp NextStatement::SavePlace

;; Returns, for the statements' checks.
;; Also: CONTRT (BB13)
Done:
    rts
.endproc

;; The `BYE` statement: closes the files and leaves BASIC through SOS's <SOS_TERMINATE> call ($65, which Apple's
;; listing calls `COLD.START`), which doesn't return.
;;
;; Each call's parameter list is the call itself, starting at its BRK, a zero: no parameters. `TERMINATE` takes none;
;; `CLOSE` wants one, so SOS refuses that call, which matters little, as <Files::CloseAll> has closed BASIC's files.
;; Entry:
;;   CloseAndTerminate = closes the files and terminates, with nothing to check
;; Also: COLD (BB13)
.proc Bye
    jsr GetCurrentCharacter
    beq CloseAndTerminate
    jmp SyntaxError

;; Closes the files and terminates.
;; Also: COLD1 (BB13)
CloseAndTerminate:
    jsr Files::CloseAll
    brk
    .byte SOS_CLOSE
    .word * - 2
    brk
    .byte SOS_TERMINATE
    .word * - 2                             ; never returns
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; RUN and the GOSUB entry
; ---------------------------------------------------------------------------------------------------------------------

;; The `RUN` statement: runs the program from its start, from a line (`RUN n` or `RUN ,n`), or loads a program first.
;;
;; Each clears the variables and the stack. `RUN pathname` loads the program, turns `TRACE` off and runs it through
;; <Files::StartProgram>.
;; In: A = the character after `RUN`, flags as <GetCurrentCharacter> sets them
;; See: <ResetProgramState>, <Statements::GoSub::Transfer>
;; Also: RUN (BB13)
.proc Run
    bne WithArgument
    jmp ResetProgramState                   ; RUN alone: from the start

;; Takes a line number, a comma and a line number, or a pathname.
WithArgument:
    bcc FromLine                            ; a digit: from that line
    cmp #','
    beq AfterComma
    jsr Files::OpenProgramToRun             ; a pathname
    lda #1
    sta StartupDone
    jsr Files::LoadProgram
    jsr ClearVariables
.if VERSION >= 130
    jsr ProgramPrefix::ToVolumeName         ; 1.3: name the program's prefix by its volume
.endif
    lsr TraceMode                           ; TRACE off
    jmp Files::StartProgram

;; Runs from the line after the comma.
;; Also: RUNL2 (BB13)
AfterComma:
    jsr CheckComma

;; Clears the variables and the stack (<ClearVariables> resets it, taking <NextStatement>'s return address), then goes
;; to the line.
;; Also: RUNL (BB13)
FromLine:
    jsr ClearVariables
    jsr Statements::GoSub::Transfer
    jmp NextStatement
.endproc

.endscope

;; Puts a <GoSubEntry> on the stack, below the caller's return address and the one above it, after checking for room.
;;
;; The entry holds the text pointer as an offset from <ProgramStart>. For `GOSUB`, the second return address is
;; <ExecuteStatement::StatementReturn>, so the entry goes under it; `FOR` and `ON KBD` call through
;; <PushGoSubEntryHere> and <PushGoSubEntryHereChecked>, so the entry goes at their own level.
;; In: TextPointer = where `RETURN` goes on from, CurrentLine = the line
;; Uses: A, X, Y, Pointer1, ListSavedPointer
;; Entry:
;;   WithoutRoomCheck = does not check for room
;;   Done = returns; <Statements::GoTo> branches here
;; See: <Statements::Return>, <Statements::For>
;; Also: PSHTXT (BB13)
.proc PushGoSubEntry
    lda #4
    jsr CheckStack                          ; room for 8 bytes

;; Does not check for room.
;; Also: PSHTXT2 (BB13)
WithoutRoomCheck:
    pla                                     ; the return address
    sta ListSavedPointer
    pla
    tax
    pla                                     ; and the one above it
    sta Pointer1
    pla
    sta Pointer1+1
    sec                                     ; TextPointer, less ProgramStart
    lda TextPointer
    sbc ProgramStart
    pha
    lda TextPointer+1
    sbc ProgramStart+1
    ldy TextPointerXByte
    jsr Memory::NormalizeAfterSubtract
    pha
    tya
    sbc ProgramStartXByte
    pha
    lda CurrentLine+1
    pha
    lda CurrentLine
    pha
    lda #TOKEN_GOSUB
    pha
    lda Pointer1+1                          ; the return addresses back on top
    pha
    lda Pointer1
    pha
    txa
    pha
    lda ListSavedPointer
    pha

;; Returns, for branches.
;; Also: PSHTRT (BB13)
Done:
    rts
.endproc

;; Pushes a <GoSubEntry> at the caller's own level, without checking for room; `FOR` uses it.
;; See: <PushGoSubEntry>
;; Also: PSHTXT3 (BB13)
.proc PushGoSubEntryHere
    jsr PushGoSubEntry::WithoutRoomCheck
    rts
.endproc

;; Pushes a <GoSubEntry> at the caller's own level, after checking for room; `ON KBD` uses it.
;; See: <PushGoSubEntry>, <Handlers::KeyPressed>
;; Also: PSHTXT4 (BB13)
.proc PushGoSubEntryHereChecked
    jsr PushGoSubEntry
    rts
.endproc
