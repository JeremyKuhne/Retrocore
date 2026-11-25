; retrocore: style=strict
; B3MAINC: the error handler, the prompt and the lines typed at it, tokenizing, finding a line, and NEW and CLEAR
; with the routines that reset the program's state.
;
; A program is a list of lines from ProgramStart, in order of their numbers. Each line is its length in bytes (the whole
; line, this byte included), its number (low byte first), its tokens, and a zero; a length of zero ends the
; program. The byte before ProgramStart is a zero, which the statement fetcher reads as the end of a line before the
; first.

; ---------------------------------------------------------------------------------------------------------------------
; Errors
; ---------------------------------------------------------------------------------------------------------------------

;; Ends with `OUT OF MEMORY`.
;; See: <ReportError>
;; Also: OMERR (BB13)
.proc ReportOutOfMemory
    ldx #ERROR_OUT_OF_MEMORY
    ; Falls into ReportError.
.endproc

;; Reports error X: through `ON ERR` when the program has it in force, otherwise with a message, then goes back to
;; the prompt.
;;
;; It clears <ProgramLoading>, sends output back to the `OUTPUT#` device (<OutputFileNumber> from <OutputFileNumber>+1,
;; in case the error came during `PRINT#`), keeps the number in <ErrorCode> (the `ERR` function) and frees the string
;; temporaries.
;;
;; When a program is running (<CurrentLine> is not direct), it copies <CurrentLine> to <ErrorLine> (the `ERRLIN`
;; function) and to <StoppedLine>, and when bit 7 of <OnErrorActive> is set (`ON ERR`) goes to <TrapError>. Otherwise,
;; at <ReportError::Untrapped>, it resets output to the console, takes back all memory, turns the screen on, starts a
;; new line and prints `?`, puts the stack pointer back to <StatementStack>, where the failing statement started, and
;; prints the message and <ErrorSuffix> (` ERROR` with a beep), and ` IN ` and the line when a program was running; then
;; it closes any `EXEC` file and goes to <ReadyForCommand>.
;;
;; The number is the message's place in <ErrorMessages>, from 1 (<ERROR_NEXT_WITHOUT_FOR>). A SOS error with no number
;; of BASIC's own comes through <ReportSosError> as SOS CALL (<ERROR_SOS_CALL>), with SOS's code in <SosError>.
;; `INPUT`'s errors 253 (extra ignored) and 254 (bad input) come here only when `ON ERR` can take them, and
;; `CONTROL-C`'s 255 goes to <TrapError> from <HandleBreak>.
;;
;; In 1.3, before a program has reached the prompt (<StartupDone> clear), it first prints the name of the program the
;; selector started.
;; In: X = the error number
;; See: <ReportMessage>, <TrapError>, <ReportSosError>
;; Also: ERROR (BB13)
.proc ReportError
.if VERSION >= 130
    ; 1.3: restore SOS's prefix, and print the program's name when no program has reached the prompt yet.
    txa
    pha
    jsr ProgramPrefix::UseSos
    lda StartupDone
    bne NameDone
    lda #<(ProgramPath+1)
    ldy #>(ProgramPath+1)
    ldx #ERROR_MESSAGES_X_BYTE
    jsr Output::PrintTextDirect

;; Gets the error number back, after the program's name.
;; Also: ERRORR (BB13)
NameDone:
    pla
    tax
.endif
    lda #0
    sta ProgramLoading
    lda OutputFileNumber+1                  ; Output back to the OUTPUT# device
    sta OutputFileNumber
    stx ErrorCode

;; Frees each string temporary in use, and its string.
;; Also: FREALL (BB13)
FreeTemporaries:
    lda LastTemporary
    ldy LastTemporary+1
    ldx #0
    jsr Strings::FreeTemporary
    lda #<(TemporaryDescriptors)
    cmp NextTemporary
    bcc FreeTemporaries
    ldx ErrorCode
    ldy CurrentLine+1                       ; Direct: no ON ERR, and no line to keep
    iny
    beq Untrapped
    dey
    sty ErrorLine+1
    sty StoppedLine+1
    ldy CurrentLine
    sty ErrorLine
    sty StoppedLine
    bit OnErrorActive
    bpl Untrapped
    jmp TrapError                           ; ON ERR takes it

;; Prints error X's message and goes back to the prompt.
;; Also: DNTTRAP (BB13)
Untrapped:
    lda #CONSOLE_FILE                       ; Output to the console
    sta OutputFileNumber
    sta OutputFileNumber+1
    lda #0
    jsr Segments::Grow                      ; All the memory there is
    lda #Console::SCREEN_ON
    jsr PrintCharacter
    jsr PrintNewline
    jsr PrintQuestionMark
    ldx StatementStack
    txs
    ldx ErrorCode
    lda #ERROR_MESSAGES_X_BYTE
    sta Pointer1XByte
    lda #>(ErrorMessages)
    sta Pointer1+1
    lda #<(ErrorMessages)
    sta Pointer1
    ldy #0

;; Counts X down to the message in <ErrorMessages>.
;; Also: FINDHERR (BB13)
FindMessage:
    dex
    beq PrintMessage

;; Skips one message: its last character has bit 7 set.
;; Also: CHECKHER (BB13)
SkipMessage:
    lda (Pointer1),Y
    iny
    bne SkipNext
    inc Pointer1+1                          ; The table never crosses into another bank

;; Tests the character just read.
SkipNext:
    cmp #$80
    bcc SkipMessage
    bcs FindMessage

;; Prints the message, through its last character.
;; Also: GOTHER (BB13)
PrintMessage:
    lda (Pointer1),Y
    iny
    bne PrintMessageCharacter
    inc Pointer1+1

;; Prints the character just read.
PrintMessageCharacter:
    pha
    jsr PrintCharacter
    pla
    cmp #$80
    bcc PrintMessage
    lda #<(ErrorSuffix)
    ldy #>(ErrorSuffix)
    ldx #TemporaryDescriptors
    stx NextTemporary
    ldx #ERROR_MESSAGES_X_BYTE
    ; Falls into ReportMessage.
.endproc

;; Prints a message, then ` IN ` and the line when a program was running, ends the line, closes any `EXEC` file and
;; goes to <ReadyForCommand>.
;;
;; BREAK and `INPUT`'s EXTRA IGNORED come here with their own messages.
;; In: A = the message's low byte, Y = its high byte, X = its bank; the message ends with a zero
;; See: <ReportError>, <Statements::StopOrEnd>
;; Also: ERRFIN (BB13)
.proc ReportMessage
    jsr Output::PrintTextDirect
    ldy CurrentLine+1
    iny                                     ; Direct?
    beq Direct
    jsr Float::PrintInLineNumber

;; Ends the line, then closes any `EXEC` file.
Direct:
    jsr PrintNewline
    ldx ExecFile                            ; An EXEC file?
    beq ReadyForCommand
    lda #SOS_ERROR_END_OF_FILE              ; Close it, with an error Files::CloseExecFile accepts
    jsr Files::CloseExecFile
    ; Falls into ReadyForCommand.
.endproc

;; Goes back to the prompt after a program ends or stops, or after an error: writes out all files' buffers with
;; `FLUSH` (<Console::FlushAllParameters>, whose reference number zero means every file), then falls into
;; <CommandLoop>.
;;
;; The run-time version has no prompt: after an error it asks for the space bar, then, as when a program ends,
;; leaves BASIC through <Statements::Bye::CloseAndTerminate>.
;; See: <ReportMessage>, <CommandLoop>
;; Also: READY (BB13)
.proc ReadyForCommand
.if VERSION >= 130
    jsr ProgramPrefix::UseSos               ; 1.3: SOS's own prefix
.endif
.if RUNTIME
    lda ErrorCode                           ; Zero: the program ended
    beq Restart
    lda #<(RunTimeEndMessage)
    ldy #>(RunTimeEndMessage)
    ldx #ERROR_MESSAGES_X_BYTE
    jsr Output::PrintTextDirect

;; Waits for the space bar.
;; Also: READY1 (BB13)
WaitForSpace:
    jsr Console::ReadKey
    lda LastKey
    cmp #' '                                ; The space bar?
    bne WaitForSpace

;; Starts SOS again.
;; Also: READYGO (BB13)
Restart:
    jmp Statements::Bye::CloseAndTerminate
.else
    brk
    .byte SOS_FLUSH
    .word Console::FlushAllParameters
    ; Falls into CommandLoop.
.endif
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The prompt
; ---------------------------------------------------------------------------------------------------------------------

;; The prompt: reads a line, then runs it at once or, when it starts with a line number, puts it into the program.
;;
;; Each time round, it sets <CurrentLine> direct and <StartupDone>, starts a new screen line unless the cursor is at the
;; left (from <ReadCursorPosition>, which reads <Console::CursorColumn>), and turns the console's any-key event off for
;; the prompt: it calls D_CONTROL with priority zero in <Console::AnyKeyEvent>, then puts `ON KBD`'s priority back there
;; for `CONT` to turn it on again. It clears <PendingEvents> and reads the line with the prompt `)` through
;; <InputLine::WithPrompt>.
;;
;; A blank line is ignored. A direct line is tokenized in place by <Tokenize> and run from <InputBuffer> through
;; <ExecuteStatement>; after its last statement the statement fetcher comes back through <ReadyForCommand>. A numbered
;; line goes to <CommandLoop::EditLine>.
;;
;; It puts a numbered line into the program, replacing any line with its number, or deletes the line when nothing
;; follows the number. It reads the number into <LineNumber>, tokenizes the line, and forbids `CONT` (<StoppedText>'s
;; X-byte zero). <FindLine> finds the line or where it goes. An old line is removed with <CloseGap>; a new one is made
;; room for with <OpenGap>, and its length and number are put in the three bytes before <InputBuffer> so the whole line
;; copies from <InputBuffer>-3. Both moves take the variables and arrays along, so they keep their values. At the end,
;; <RewindTextPointer> and <ClearVariables::RestoreData> reset the text pointer, the `ON ERR`, `ON KBD` and `ON EOF`
;; handlers, the `DATA` pointer and the stack, and it goes back to the prompt.
;; See: <ReadyForCommand>, <Tokenize>, <FindLine>
;; Also: MAIN (BB13)
.proc CommandLoop

;; The prompt character.
PROMPT = ')'

    lda #DIRECT_LINE                        ; Direct
    sta CurrentLine+1
    lda #1
    sta StartupDone                         ; The prompt has been reached
.if VERSION >= 130
    jsr ProgramPrefix::UseSos               ; 1.3: SOS's prefix, and the program's prefix
.endif
.if VERSION >= 130
    jsr ProgramPrefix::StripFileName
.endif
    jsr ReadCursorPosition
    lda a:Console::CursorColumn
    sta TerminalPosition
    beq AtLeft                              ; At the left already
    jsr PrintNewline

;; Turns the any-key event off for the prompt, and reads the line.
AtLeft:
    lda a:Console::AnyKeyEvent
    pha
    lda #0
    sta a:Console::AnyKeyEvent
    brk                                     ; D_CONTROL: the any-key event off
    .byte SOS_DEVICE_CONTROL
    .word Console::AnyKeyParameters
    pla
    sta a:Console::AnyKeyEvent
    ldx #PROMPT
    stx PendingEvents                       ; which also clears bits 7 and 6: no key, no CONTROL-C
    jsr InputLine::WithPrompt
    stx TextPointer
    sty TextPointer+1
    sta TextPointerXByte
    jsr GetNextCharacter
    tax                                     ; The line's end?
    beq CommandLoop
    ldx #DIRECT_LINE
    stx CurrentLine+1
    bcc EditLine                            ; A digit: a line number
    stx SourceStart+1                       ; Tells Tokenize the line is direct
    jsr Tokenize
    jmp ExecuteStatement                    ; Run it

;; Puts a numbered line into the program: deletes any old line with its number first.
;; Also: MAIN1 (BB13)
EditLine:
    jsr ReadLineNumber
    lda #0                                  ; Tells Tokenize the line is in a program
    sta SourceStart+1
    sta StoppedTextXByte                    ; No CONT now
    jsr Tokenize
    sty Counter                             ; The stored line's length
    sty InputBuffer-3
    jsr FindLine
    bcc InsertLine                          ; No line to delete
    ldy #00                                 ; MoveDistance = minus the old line's length
    lda #$7F
    sta MoveDistance+1
    lda #$FF
    sta MoveDistanceXByte
    eor (SourceStart),Y
    sta MoveDistance
    inc MoveDistance
    lda (SourceStart),Y                     ; The next line starts here
    clc
    adc SourceStart
    sta Pointer1
    lda SourceStart+1
    adc #0
    ldy SourceStartXByte
    jsr Memory::NormalizeAfterAdd
    sta Pointer1+1
    tya
    adc #0
    sta Pointer1XByte
    jsr CloseGap

;; Inserts the new line, unless it is empty.
;; Also: NODEL (BB13)
InsertLine:
    lda InputBuffer                         ; Nothing after the number?
    beq ResetAndPrompt
    lda #0                                  ; MoveDistance = the new line's length
    sta MoveDistance+1
    sta MoveDistanceXByte
    lda Counter
    sta MoveDistance
    jsr OpenGap
    lda LineNumber
    ldy LineNumber+1
    sta InputBuffer-2
    sty InputBuffer-2+1
    ldy Counter

;; Copies the line, from <InputBuffer>-3, into the gap, last byte first.
;; Also: STOLOP (BB13)
CopyLine:
    lda InputBuffer-4,Y
    dey
    sta (SourceStart),Y
    bne CopyLine

;; Resets the program's state after an edit, then goes back to the prompt.
;; Also: FINI (BB13)
ResetAndPrompt:
    jsr RewindTextPointer
    jsr ClearVariables::RestoreData
    jmp CommandLoop
.endproc

;; Reads a line into <InputBuffer> with no prompt, for `INPUT`.
;;
;; It reads from the console, or from the `EXEC` file while one runs, through <ReadLine>. Lines read from a file with
;; `INPUT#` end at <InputLine::Terminate> too.
;; Out: X = the low byte of <InputBuffer>-1, Y = its high byte, A = 0 (its bank), InputBuffer = the line, ending in a
;;   zero
;; Entry:
;;   WithPrompt = prints the prompt character in X first, or none for zero
;;   Terminate = ends the line in <InputBuffer> with a zero at X, its length, and returns <InputBuffer>-1
;; See: <ReadLine>
;; Also: INLIN (BB13)
.proc InputLine
    ldx #0

;; Reads a line after printing the prompt in X, or none for zero.
;; Also: INLINB (BB13)
WithPrompt:
    jsr ReadLine

;; Ends the line in <InputBuffer> with a zero at X and returns <InputBuffer>-1 for <TextPointer>.
;; Also: GDBUFS (BB13)
Terminate:
    lda #0
    sta InputBuffer,X
    lda #0
    sta SavedY
    ldx #<(InputBuffer-1)
    ldy #>(InputBuffer-1)
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Tokenizing
; ---------------------------------------------------------------------------------------------------------------------

;; The tokenizer's helpers: <Tokenize> is at the top level.
.scope Tokenizer

;; Goes to <Tokenize::Finish> at the line's end, for <Tokenize>'s branch.
;; Also: GCRNCHED (BB13)
.proc ToFinish
    jmp Tokenize::Finish
.endproc

.endscope

;; Tokenizes the line in <InputBuffer> in place, from <TextPointer> on, and points <TextPointer> at <InputBuffer>-1 to
;; run it.
;;
;; Keywords from <ReservedWords> become one-byte tokens, $80 to <TOKEN_NEW>; those of the second list, from
;; <ExtendedReservedWords>, become two bytes, <TOKEN_ESCAPE> and the token. A word is a keyword only with a separator
;; (anything but a letter, digit or period) before and after it, or when it ends in one, as `TAB(` does, so long
;; variable names can hold keywords. Letters may be in either case, and spaces inside a keyword are skipped. Spaces
;; outside quotes are dropped, `?` becomes `PRINT` and `!` becomes `REM`. Quoted text, and everything after `REM`, is
;; copied as it is.
;;
;; <TokenizeState> says when to copy: bit 7 set copies characters unchanged; a colon always turns tokenizing back on,
;; and a comma does when bit 6 is clear. `DATA`, `IMAGE` and `CAT` copy up to the colon. In a direct line
;; (<SourceStart>+1 = $FF), `INVOKE` and `RENAME` copy up to the colon, the other disk commands from `LOAD` to `CATALOG`
;; up to the next comma or colon, and `OPEN` tokenizes up to its first comma and copies after it, which bit 7 of
;; <IntegerType> marks.
;;
;; The tokens go from <InputBuffer> on, behind the characters still to read, with <TokenizePointer> counting from 3.
;; They end with two zeros: the line's end, and a zero where a next line's length would be, which ends a direct line
;; when it runs. The three bytes before <InputBuffer> are left for the line's length and number.
;; In: TextPointer = the first character to tokenize, SourceStart+1 = $FF for a direct line, 0 for a numbered one
;; Out: Y = the line's length as stored in a program (its tokens and zero, and three bytes for its length and
;;   number), TextPointer = <InputBuffer>-1, TextPointerXByte = 0
;; See: <CommandLoop>, <CommandLoop::EditLine>, <Tokenizer::IsSeparator>
;; Also: CRUNCH (BB13)
.proc Tokenize

;; Clears bit 5, which makes a lower-case letter upper case.
UPPER_CASE_MASK = $DF

    lda TextPointer
    sec
    sbc #<(InputBuffer)
    tax                                     ; X = the input's index in InputBuffer
    lda #3
    sta TokenizePointer
    sta TokenizeState                       ; Tokenizing on
    sta IntegerType
    sta InputBuffer-1,X                     ; A separator before the first word

;; Starts on the next input character, at the top of the keyword list.
;; Also: CLOOP (BB13)
NextInput:
    ldy #0
    sty Counter+1                           ; One-byte tokens first
    lda #FIRST_TOKEN
    sta Counter                             ; The first token
    lda #<(ReservedWords)
    sta Fac
    lda #>(ReservedWords)
    sta Fac+1
    lda #RESERVED_WORDS_X_BYTE
    sta FacXByte
    lda InputBuffer,X
    beq Tokenizer::ToFinish
    and #$7F
    cmp #':'                                ; A colon?
    beq TokenizeAgain
    cmp #','                                ; A comma?
    bne Classify
    bit IntegerType
    bpl CheckForComma
    ror TokenizeState                       ; After OPEN: copy from here
    bmi Classify

;; Does a comma turn tokenizing back on?
CheckForComma:
    bit TokenizeState
    bvs Classify

;; Turns tokenizing back on: A, a colon or comma, has bits 7 and 6 clear.
;; Also: ONCRNC (BB13)
TokenizeAgain:
    sta TokenizeState

;; Copies the character, drops a space, or looks for a keyword.
;; Also: CL1 (BB13)
Classify:
    bit TokenizeState
    bmi StoreToken                          ; Copying
    cmp #' '+1
    bcs NotSpace
    jmp Advance                             ; A space: drop it

;; Turns `!` into `REM`, and keeps the punctuation below it.
NotSpace:
    cmp #'!'
    bcc StoreToken
    bne CheckQuestion
    lda #TOKEN_REM
    bcs StoreToken

;; Turns `?` into `PRINT` and keeps other punctuation and digits.
;; Also: SHORT1 (BB13)
CheckQuestion:
    cmp #'?'
    bcc StoreToken
    bne SearchKeywords
    lda #TOKEN_PRINT
    bcs StoreToken

;; Goes to <Tokenize::NextKeyword> for the branches.
;; Also: GNMTCH (BB13)
ToNextKeyword:
    jmp NextKeyword

;; Compares the input from X with the keyword at <Fac>.
;; Also: NPRNT (BB13)
SearchKeywords:
    stx Temporary                           ; Where the word starts

;; Starts the comparison again, with the next keyword.
;; Also: NPR2 (BB13)
TryKeyword:
    ldx Temporary

;; Compares the next input character, skipping spaces.
;; Also: NPR3 (BB13)
CompareNext:
    lda InputBuffer,X
    beq UpperCase
    and #$7F
    cmp #' '+1
    bcs UpperCase
    inx
    bne CompareNext

;; Makes a lower-case letter upper case.
;; Also: NSPC (BB13)
UpperCase:
    cmp #'a'
    bcc CompareCharacter
    cmp #'z'+1
    bcs CompareCharacter
    and #UPPER_CASE_MASK

;; Compares the character with the keyword's.
;; Also: NSP2 (BB13)
CompareCharacter:
    eor (Fac),Y
    iny
    inx
    asl                                     ; The low seven bits must match
    bne ToNextKeyword
    bcc CompareNext                         ; Bit 7 clear: not the keyword's last character
    lda InputBuffer,X                       ; The whole keyword matches: is a separator after it?
    and #$7F
    jsr Tokenizer::IsSeparator
    bcc CheckBefore
    dey                                     ; Or does the keyword end in one, as DEC( does?
    lda (Fac),Y
    and #$7F
    jsr Tokenizer::IsSeparator
    bcc CheckBefore
    lda Counter                             ; Or is it EXFN. or EXFN%., or FN?
    cmp #TOKEN_EXFN_INTEGER-1
    beq CheckBefore
    cmp #TOKEN_EXFN_INTEGER
    beq CheckBefore
    cmp #TOKEN_FN
    bne ToNextKeyword
    bit Counter+1                           ; FN is in the second list
    bpl ToNextKeyword

;; Takes the keyword when a separator comes before it too.
;; Also: YMTCH (BB13)
CheckBefore:
    txa
    pha
    ldx Temporary
    lda InputBuffer-1,X
    jsr Tokenizer::IsSeparator
    pla
    tax
    bcs ToNextKeyword
    dex                                     ; Back to the keyword's last character
    lda Counter+1
    bmi StoreToken                          ; Two bytes: TOKEN_ESCAPE first
    lda Counter

;; Stores A in the tokens, with the token after <TOKEN_ESCAPE> for a two-byte token.
;; Also: STUFIT (BB13)
StoreToken:
    ldy TokenizePointer
    sta InputBuffer-3,Y
    iny
    cmp #TOKEN_ESCAPE
    bne KeepIndex
    lda Counter
    sta InputBuffer-3,Y
    iny
    lda #0                                  ; Matches none of the tests below

;; Keeps the output index.
;; Also: NESC (BB13)
KeepIndex:
    sty TokenizePointer

;; Steps to the next input character, after checking whether the token just stored turns tokenizing off.
;; Also: NXCHR (BB13)
Advance:
    inx
    cmp #TOKEN_REM
    beq CopyRemark
    cmp #TOKEN_DATA
    beq CopyToColon
    cmp #'"'                                ; A quote
    beq CopyUntil
    cmp #TOKEN_IMAGE+2
    bcs ToNextInput
    ldy SourceStart+1                       ; A direct line?
    iny
    beq CheckOpen
    cmp #TOKEN_LAST_FILE_COMMAND+1          ; In a program, only IMAGE and CAT go on
    bcc ToNextInput

;; Checks `OPEN`, `INVOKE` and the disk commands, and `IMAGE` and `CAT`.
;; Also: ITDIR (BB13)
CheckOpen:
    cmp #TOKEN_OPEN
    bne CheckDiskCommand
    ror IntegerType                         ; Copy after OPEN's first comma
    bmi ToNextInput                         ; Always

;; Checks `INVOKE` and the disk commands.
;; Also: ITDIR1 (BB13)
CheckDiskCommand:
    cmp #TOKEN_INVOKE
    beq CopyToColon
    cmp #TOKEN_LOAD
    bcc ToNextInput
    cmp #TOKEN_RENAME
    bne CopyToCommaOrColon

;; Copies up to the colon: bits 7 and 6 of <TokenizeState> set.
;; Also: ITDIR15 (BB13)
CopyToColon:
    sec
    .byte $2C                               ; BIT abs, which skips the CMP

;; Copies up to the next comma or colon after a disk command (bit 6 clear), or up to the colon after `IMAGE` and
;; `CAT` (bit 6 set).
;; Also: ITDIR2 (BB13)
CopyToCommaOrColon:
    cmp #TOKEN_LAST_FILE_COMMAND+1
    ror TokenizeState
    sec
    ror TokenizeState

;; Goes back to <Tokenize::NextInput>.
;; Also: GCLOOP (BB13)
ToNextInput:
    jmp NextInput

;; Copies the rest of the line after `REM`.
;; Also: REMIT (BB13)
CopyRemark:
    lda #0                                  ; Only the line's end ends it

;; Copies characters unchanged up to the one in A, or the line's end.
;; Also: DOQUOT (BB13)
CopyUntil:
    dex
    sta EndDelimiter
    ldy TokenizePointer
    dey

;; Copies a character.
;; Also: DOQ2 (BB13)
CopyCharacter:
    iny
    inx
    lda InputBuffer,X
    sta InputBuffer-3,Y
    sty TokenizePointer
    beq Finish
    cmp EndDelimiter
    bne CopyCharacter
    iny
    sty TokenizePointer
    inx
    jmp ToNextInput

;; Steps to the next keyword in the list, or stores the character as it is when there are no more.
;; Also: NOMTCH (BB13)
NextKeyword:
    dey
    beq SkipKeyword
    dey

;; Skips the rest of this keyword, then adds its length to <Fac>.
;; Also: FNDNXT (BB13)
SkipKeyword:
    iny
    lda (Fac),Y
    bpl SkipKeyword                         ; A keyword ends with bit 7 set
    sec
    tya
    adc Fac
    sta Fac
    bcc NextToken
    inc Fac+1                               ; The list never crosses into another bank

;; Steps the token number, moving to the second list after the statements.
NextToken:
    ldy #0
    ldx Counter
    inx
    cpx #TOKEN_NEW+1                        ; Past the statements?
    bne CheckListEnd
    ldx #TOKEN_ESCAPE                       ; The second list: two-byte tokens from FIRST_TOKEN
    stx Counter+1
    ldx #FIRST_TOKEN

;; Keeps the token number and checks for the list's end.
;; Also: FND2 (BB13)
CheckListEnd:
    stx Counter
    lda (Fac),Y
    bne ToTryKeyword
    ldx Temporary                           ; No keyword: store the character
    lda InputBuffer,X
    and #$7F
    jmp StoreToken

;; Ends the tokens with two zeros and points <TextPointer> at <InputBuffer>-1.
;; Also: CRNCHED (BB13)
Finish:
    ldy TokenizePointer
    sta InputBuffer-3,Y
    sta InputBuffer-2,Y                     ; A zero length after the line: a direct line ends there
    lda #0
    sta TextPointerXByte
    lda #>(InputBuffer-1)
    sta TextPointer+1
    lda #<(InputBuffer-1)
    sta TextPointer
    iny
    rts

;; Goes to <Tokenize::TryKeyword> for the branch.
;; Also: GNPR2 (BB13)
ToTryKeyword:
    jmp TryKeyword
.endproc

; The tokenizer's helpers, continued.
.scope Tokenizer continued

;; Tells whether a character separates words: anything but a letter, a digit or a period does.
;; In: A = the character
;; Out: carry = clear for a separator
;; Keeps: A, X, Y
;; See: <IsLetter>
;; Also: CKSEP (BB13)
.proc IsSeparator
    jsr IsLetter
    bcs Done
    cmp #'9'+1
    bcs Separator
    cmp #'0'
    bcs Done
    cmp #'.'
    beq Done

;; Returns with carry clear: a separator.
;; Also: CKRT1 (BB13)
Separator:
    clc

;; Returns.
;; Also: CKRTS (BB13)
Done:
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Finding a line
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the line numbered <LineNumber>, or where it would go.
;;
;; It searches from <ProgramStart>; <FindLine::FromLine> searches from the line at Y, X and A (X-byte, page, low byte),
;; as `GOTO` does when the line is after the current one. Invokable modules can call both through <ModuleRoutines>.
;; In: LineNumber = the line's number
;; Out: carry = set when found, SourceStart = the line's length byte, or the first line with a higher number, or the
;;   program's end
;; Entry:
;;   FromLine = searches from the line at Y, X and A
;;   FromPage = from the X-byte in <SourceStartXByte> and the page in X
;;   FromAddress = from the X-byte and page in <SourceStart> and the low byte in A
;; Also: FNDLIN (BB13)
.proc FindLine
    lda ProgramStart
    ldx ProgramStart+1
    ldy ProgramStartXByte

;; Searches from the line at Y, X and A.
;; Also: FNDLNC0 (BB13)
FromLine:
    sty SourceStartXByte

;; Searches from the X-byte in <SourceStartXByte>, the page in X and the low byte in A.
;; Also: FNDLNC1 (BB13)
FromPage:
    stx SourceStart+1

;; Searches from the line at <SourceStart>, with its low byte in A.
;; Also: FNDLNC (BB13)
FromAddress:
    sta SourceStart
    ldy #0
    lda (SourceStart),Y                     ; The line's length
    beq NotFound                            ; Zero: the program's end
    ldy #2
    tax
    lda LineNumber+1
    cmp (SourceStart),Y
    bcc Done                                ; Past it: not there
    bne NextLine
    lda LineNumber
    dey
    cmp (SourceStart),Y
    bcc Done                                ; Past it: not there
    beq Done                                ; Found, with carry set

;; Steps <SourceStart> to the next line, by this one's length in X.
;; Also: AFFRTS (BB13)
NextLine:
    txa
    clc
    adc SourceStart
    bcc FromAddress
    ldx SourceStart+1
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc FromPage
    pha                                     ; Into the next bank pair
    txa
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
    tax
    pla
    inc SourceStartXByte
    bne FromPage                            ; Always
    bcs FromAddress                         ; Never reached

;; Returns with carry clear: not found.
;; Also: FLINRT (BB13)
NotFound:
    clc

;; Returns.
;; Also: FLNRTS (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; NEW, CLEAR and resetting
; ---------------------------------------------------------------------------------------------------------------------

; NEW and CLEAR.
;; BASIC's statements: a routine for each keyword's statement, named for the keyword split at its words, as
;; AppleSoft's are (`Statements::GoSub`, `Statements::OnErr`), and the parts they share. <StatementTable> holds
;; their addresses by token. The scope is in pieces through the files, in Apple's order.
.scope Statements

;; The `NEW` statement: deletes the program and its variables, closing all files.
;;
;; With anything after `NEW` it returns at once, and the statement fetcher reports SYNTAX.
;; See: <EraseProgram>
;; Also: SCRATH (BB13)
.proc New
    bne FindLine::Done
    ; Falls into EraseProgram.
.endproc

.endscope

;; Deletes the program and its variables: closes all files, resets BASIC's state with <ResetInterpreter>, then
;; clears everything as <ResetProgramState> does. <ColdStart> calls it.
;; See: <ResetInterpreter>, <ResetProgramState>
;; Also: SCRTCH (BB13)
.proc EraseProgram
    jsr Files::CloseAll
    jsr ResetInterpreter
    ; Falls into ResetProgramState.
.endproc

;; Gets ready to run the program from its start, for `RUN`: points <TextPointer> before the first line, marks
;; <CurrentLine> as not direct so the statement fetcher goes on to the first line, and clears as `CLEAR` does.
;; See: <RewindTextPointer>, <ClearVariables>
;; Also: RUNC (BB13)
.proc ResetProgramState
    jsr RewindTextPointer
    lda #0                                  ; Sets zero for CLEAR's test
    sta CurrentLine+1
    ; Falls into Statements::Clear.
.endproc

; CLEAR.
.scope Statements continued

;; The `CLEAR` statement: closes all files and clears the variables, the strings and the stack.
;;
;; With anything after `CLEAR` it returns at once, and the statement fetcher reports SYNTAX.
;; In: zero = set at the end of the statement
;; See: <ClearVariables>
;; Also: CLEAR (BB13)
.proc Clear
    bne ResetStack::Done
    ; Falls into ClearVariables.
.endproc

.endscope

;; Closes all files and clears the variables, arrays and strings, `ERR`, `ERRLIN`, `KBD` and `EOF`, then takes back
;; all memory, points `DATA` at the program's start and resets the stack.
;;
;; The strings start again at <MemoryTop>, and the simple variables and the end of the variables (<VariablesStart> and
;; <VariablesEnd>) go back to <ArraysStart>, the program's end. Memory comes back with <Segments::Grow>, `DATA` with
;; <Statements::Restore>, and it falls into <ResetStack>.
;; Entry:
;;   KeepFiles = clears without closing the files, for `LOAD`
;;   RestoreData = only takes back the memory and resets `DATA` and the stack
;; See: <ResetStack>
;; Also: CLEARC (BB13)
.proc ClearVariables
    jsr Files::CloseAll

;; Clears without closing the files.
;; Also: CLEARL (BB13)
KeepFiles:
    lda MemoryTop
    ldx MemoryTopXByte
    ldy MemoryTop+1                         ; No strings
    sta StringsBottom
    sty StringsBottom+1
    stx StringsBottomXByte
    lda ArraysStart
    ldy ArraysStart+1                       ; No variables or arrays
    ldx ArraysStartXByte
    sta VariablesStart
    sty VariablesStart+1
    stx VariablesStartXByte
    sta VariablesEnd
    sty VariablesEnd+1
    stx VariablesEndXByte
    lda #0
    sta LastKey                             ; KBD
    sta ErrorCode                           ; ERR
    sta ErrorLine                           ; ERRLIN
    sta ErrorLine+1
    sta EndOfFileNumber                     ; EOF

;; Takes back all memory with <Segments::Grow>, points `DATA` at the program's start with <Statements::Restore>, and
;; resets the stack.
;; Also: FLOAD (BB13)
RestoreData:
    lda #0
    jsr Segments::Grow
    jsr Statements::Restore
    ; Falls into ResetStack.
.endproc

;; Empties the stack, keeping only the caller's return address, and resets the formula evaluator's stacks.
;;
;; The stack pointer goes to <STACK_END> and into <StatementStack>; `GOSUB` and `FOR` entries are gone. The byte above,
;; the zero <ColdStart> pushed, stays at the bottom for <FindForFrame>. Apple's comment said it also frees the string
;; temporaries and forbids `CONT`; the code does neither.
;; Entry: Done = returns, for `CLEAR` with something after it
;; Also: STKINI (BB13)
.proc ResetStack
    pla                                     ; The return address
    tay
    pla
    ldx #STACK_END
    stx StatementStack
    txs
    pha
    tya
    pha
    lda #2
    sta OperatorStackTop                    ; Past the end-of-line entry
    lda #0
    sta OperatorStack+1                     ; The end-of-line precedence
    sta OperandStackTop
    sta SubscriptMode                       ; Subscripts allowed

;; Returns.
;; Also: STKRTS (BB13)
Done:
    rts
.endproc

;; Points <TextPointer> at the byte before the program, writing the zero there, then turns off the program's handlers
;; as <ClearHandlers> does.
;; See: <ClearHandlers>
;; Also: STXTPT (BB13)
.proc RewindTextPointer
    sec
    lda ProgramStart
    sbc #1
    sta TextPointer
    lda ProgramStart+1
    sbc #0
    ldy ProgramStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta TextPointer+1
    tya
    sbc #0
    sta TextPointerXByte
    ldy #0
    tya
    sta (TextPointer),Y                     ; The zero before the first line
    ; Falls into ClearHandlers.
.endproc

;; Turns off `ON KBD`, `ON EOF` and `ON ERR`, clears any key waiting in <PendingEvents>, and leaves nothing for
;; `RESUME`.
;;
;; It turns off the console's any-key event with <Statements::OffKbd>, clears every handler in <EndOfFileHandlers>, and
;; clears <OnErrorActive> and <ErrorTextXByte>. `LOAD` calls it too.
;; Out: A = 0, Y = 0
;; Also: CLEARONS (BB13)
.proc ClearHandlers
    jsr Statements::OffKbd
    ldy #END_OF_FILE_HANDLERS_SIZE
    lda #0
    sta PendingEvents

;; Clears <EndOfFileHandlers>, from the top.
;; Also: CLEOFS (BB13)
ClearNext:
    sta EndOfFileHandlers-1,Y
    dey
    bne ClearNext
    sty OnErrorActive                       ; No ON ERR
    sty ErrorTextXByte                      ; No error to RESUME
    rts
.endproc
