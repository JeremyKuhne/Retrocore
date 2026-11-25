; retrocore: style=strict
; B3MAINC: the error handler, the prompt and the lines typed at it, tokenizing, finding a line, and NEW and CLEAR
; with the routines that reset the program's state.
;
; A program is a list of lines from TXTTAB, in order of their numbers. Each line is its length in bytes (the whole
; line, this byte included), its number (low byte first), its tokens, and a zero; a length of zero ends the
; program. The byte before TXTTAB is a zero, which the statement fetcher reads as the end of a line before the first.

; ---------------------------------------------------------------------------------------------------------------------
; Errors
; ---------------------------------------------------------------------------------------------------------------------

;; Ends with OUT OF MEMORY.
;; See: <ReportError>
;; Also: OMERR (BB13)
.proc ReportOutOfMemory
    ldx #ERROM
    ; Falls into ReportError.
.endproc

;; Reports error X: through `ON ERR` when the program has it in force, otherwise with a message, then goes back to
;; the prompt.
;;
;; It clears <CMDFLG>, sends output back to the `OUTPUT#` device (<FILNO> from <FILNO>+1, in case the error came
;; during `PRINT#`), keeps the number in <ERRNUM> (the `ERR` function) and frees the string temporaries.
;;
;; When a program is running (<CURLIN> is not direct), it copies <CURLIN> to <ERRLIN> (the `ERRLIN` function) and
;; to <OLDLIN>, and when bit 7 of <ERRFLG> is set (`ON ERR`) goes to <TrapError>. Otherwise, at
;; <ReportError::Untrapped>, it resets output to the console, takes back all memory, turns the screen on, starts a
;; new line and prints `?`, puts the stack pointer back to <REMSTK>, where the failing statement started, and prints
;; the message and <ERR> (` ERROR` with a beep), and ` IN ` and the line when a program was running; then it closes
;; any `EXEC` file and goes to <ReadyForCommand>.
;;
;; The number is the message's place in <ERRTAB>, from 1 (<ERRNF>). A SOS error with no number of BASIC's own comes
;; through <SERROR> as SOS CALL (<SSSSSS>), with SOS's code in <SOSLOC>. `INPUT`'s errors 253 (extra ignored) and
;; 254 (bad input) come here only when `ON ERR` can take them, and CONTROL-C's 255 goes to <TrapError> from
;; <ISCNTC>.
;;
;; In 1.3, before a program has reached the prompt (<RNFLG> clear), it first prints the name of the program the
;; selector started.
;; In: X = the error number
;; See: <ReportMessage>, <TrapError>, <SERROR>
;; Also: ERROR (BB13)
.proc ReportError
.if VERSION >= 130
    ; 1.3: restore SOS's prefix, and print the program's name when no program has reached the prompt yet.
    txa
    pha
    jsr ProgramPrefix::UseSos
    lda RNFLG
    bne NameDone
    lda #<(PROGPATH+1)
    ldy #>(PROGPATH+1)
    ldx #ERRTABB
    jsr STROUTR

;; Gets the error number back, after the program's name.
;; Also: ERRORR (BB13)
NameDone:
    pla
    tax
.endif
    lda #0
    sta CMDFLG
    lda FILNO+1                             ; Output back to the OUTPUT# device
    sta FILNO
    stx ERRNUM

;; Frees each string temporary in use, and its string.
;; Also: FREALL (BB13)
FreeTemporaries:
    lda LASTPT
    ldy LASTPT+1
    ldx #0
    jsr FRETNOW
    lda #<(TEMPST)
    cmp TEMPPT
    bcc FreeTemporaries
    ldx ERRNUM
    ldy CURLIN+1                            ; Direct: no ON ERR, and no line to keep
    iny
    beq Untrapped
    dey
    sty ERRLIN+1
    sty OLDLIN+1
    ldy CURLIN
    sty ERRLIN
    sty OLDLIN
    bit ERRFLG
    bpl Untrapped
    jmp TrapError                           ; ON ERR takes it

;; Prints error X's message and goes back to the prompt.
;; Also: DNTTRAP (BB13)
Untrapped:
    lda #CONSOLE_FILE                       ; Output to the console
    sta FILNO
    sta FILNO+1
    lda #0
    jsr EXPAND                              ; All the memory there is
    lda #Console::SCREEN_ON
    jsr OUTDO
    jsr CRDO
    jsr OUTQST
    ldx REMSTK
    txs
    ldx ERRNUM
    lda #ERRTABB
    sta INDEXB
    lda #>(ERRTAB)
    sta INDEX+1
    lda #<(ERRTAB)
    sta INDEX
    ldy #0

;; Counts X down to the message in <ERRTAB>.
;; Also: FINDHERR (BB13)
FindMessage:
    dex
    beq PrintMessage

;; Skips one message: its last character has bit 7 set.
;; Also: CHECKHER (BB13)
SkipMessage:
    lda (INDEX),Y
    iny
    bne SkipNext
    inc INDEX+1                             ; The table never crosses into another bank

;; Tests the character just read.
SkipNext:
    cmp #$80
    bcc SkipMessage
    bcs FindMessage

;; Prints the message, through its last character.
;; Also: GOTHER (BB13)
PrintMessage:
    lda (INDEX),Y
    iny
    bne PrintMessageCharacter
    inc INDEX+1

;; Prints the character just read.
PrintMessageCharacter:
    pha
    jsr OUTDO
    pla
    cmp #$80
    bcc PrintMessage
    lda #<(ERR)
    ldy #>(ERR)
    ldx #TEMPST
    stx TEMPPT
    ldx #ERRTABB
    ; Falls into ReportMessage.
.endproc

;; Prints a message, then ` IN ` and the line when a program was running, ends the line, closes any `EXEC` file and
;; goes to <ReadyForCommand>.
;;
;; BREAK and `INPUT`'s EXTRA IGNORED come here with their own messages.
;; In: A = the message's low byte, Y = its high byte, X = its bank; the message ends with a zero
;; See: <ReportError>, <STOP2>
;; Also: ERRFIN (BB13)
.proc ReportMessage
    jsr STROUTR
    ldy CURLIN+1
    iny                                     ; Direct?
    beq Direct
    jsr INPRT

;; Ends the line, then closes any `EXEC` file.
Direct:
    jsr CRDO
    ldx INFLNO                              ; An EXEC file?
    beq ReadyForCommand
    lda #SEEOF                              ; Close it, with an error EXCCLS accepts
    jsr EXCCLS
    ; Falls into ReadyForCommand.
.endproc

;; Goes back to the prompt after a program ends or stops, or after an error: writes out all files' buffers with
;; FLUSH (<Console::FlushAllParameters>, whose reference number zero means every file), then falls into
;; <CommandLoop>.
;;
;; The run-time version has no prompt: after an error it asks for the space bar, then, as when a program ends,
;; starts SOS again through <COLD1>.
;; See: <ReportMessage>, <CommandLoop>
;; Also: READY (BB13)
.proc ReadyForCommand
.if VERSION >= 130
    jsr ProgramPrefix::UseSos                      ; 1.3: SOS's own prefix
.endif
.if RUNTIME
    lda ERRNUM                              ; Zero: the program ended
    beq Restart
    lda #<(RTMSG)
    ldy #>(RTMSG)
    ldx #ERRTABB
    jsr STROUTR

;; Waits for the space bar.
;; Also: READY1 (BB13)
WaitForSpace:
    jsr Console::ReadKey
    lda KEYSAVE
    cmp #' '                                ; The space bar?
    bne WaitForSpace

;; Starts SOS again.
;; Also: READYGO (BB13)
Restart:
    jmp COLD1
.else
    brk
    .byte SFLS
    .word Console::FlushAllParameters
    ; Falls into CommandLoop.
.endif
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The prompt
; ---------------------------------------------------------------------------------------------------------------------

;; The prompt: reads a line, then runs it at once or, when it starts with a line number, puts it into the program.
;;
;; Each time round, it sets <CURLIN> direct and <RNFLG>, starts a new screen line unless the cursor is at the left
;; (from <VPOS>, which reads <Console::CursorColumn>), and turns the console's any-key event off for the prompt: it
;; calls D_CONTROL with priority zero in <Console::AnyKeyEvent>, then puts `ON KBD`'s priority back there for `CONT`
;; to turn it on again. It clears <KEYSTROK> and reads the line with the prompt `)` through
;; <InputLine::WithPrompt>.
;;
;; A blank line is ignored. A direct line is tokenized in place by <Tokenize> and run from <BUF> through <GONE>;
;; after its last statement the statement fetcher comes back through <ReadyForCommand>. A numbered line goes to
;; <CommandLoop::EditLine>.
;;
;; It puts a numbered line into the program, replacing any line with its number, or deletes the line when nothing
;; follows the number. It reads the number into <LINNUM>, tokenizes the line, and forbids `CONT` (<OLDTXT>'s X-byte
;; zero). <FindLine> finds the line or where it goes. An old line is removed with <CloseGap>; a new one is made room
;; for with <OpenGap>, and its length and number are put in the three bytes before <BUF> so the whole line copies
;; from <BUF>-3. Both moves take the variables and arrays along, so they keep their values. At the end,
;; <RewindTextPointer> and <ClearVariables::RestoreData> reset the text pointer, the `ON ERR`, `ON KBD` and `ON EOF`
;; handlers, the `DATA` pointer and the stack, and it goes back to the prompt.
;; See: <ReadyForCommand>, <Tokenize>, <FindLine>
;; Also: MAIN (BB13)
.proc CommandLoop

;; The prompt character.
PROMPT = ')'

    lda #DIRECT_LINE                        ; Direct
    sta CURLIN+1
    lda #1
    sta RNFLG                               ; The prompt has been reached
.if VERSION >= 130
    jsr ProgramPrefix::UseSos                      ; 1.3: SOS's prefix, and the program's prefix
.endif
.if VERSION >= 130
    jsr ProgramPrefix::StripFileName
.endif
    jsr VPOS
    lda a:Console::CursorColumn
    sta TRMPOS
    beq AtLeft                              ; At the left already
    jsr CRDO

;; Turns the any-key event off for the prompt, and reads the line.
AtLeft:
    lda a:Console::AnyKeyEvent
    pha
    lda #0
    sta a:Console::AnyKeyEvent
    brk                                     ; D_CONTROL: the any-key event off
    .byte SDCNT
    .word Console::AnyKeyParameters
    pla
    sta a:Console::AnyKeyEvent
    ldx #PROMPT
    stx KEYSTROK                            ; which also clears bits 7 and 6: no key, no CONTROL-C
    jsr InputLine::WithPrompt
    stx TXTPTR
    sty TXTPTR+1
    sta TXTPTRB
    jsr CHRGET
    tax                                     ; The line's end?
    beq CommandLoop
    ldx #DIRECT_LINE
    stx CURLIN+1
    bcc EditLine                            ; A digit: a line number
    stx LOWTR+1                             ; Tells Tokenize the line is direct
    jsr Tokenize
    jmp GONE                                ; Run it

;; Puts a numbered line into the program: deletes any old line with its number first.
;; Also: MAIN1 (BB13)
EditLine:
    jsr LINGET
    lda #0                                  ; Tells Tokenize the line is in a program
    sta LOWTR+1
    sta OLDTXTB                             ; No CONT now
    jsr Tokenize
    sty COUNT                               ; The stored line's length
    sty BUF-3
    jsr FindLine
    bcc InsertLine                          ; No line to delete
    ldy #00                                 ; DELTA = minus the old line's length
    lda #$7F
    sta DELTA+1
    lda #$FF
    sta DELTAB
    eor (LOWTR),Y
    sta DELTA
    inc DELTA
    lda (LOWTR),Y                           ; The next line starts here
    clc
    adc LOWTR
    sta INDEX1
    lda LOWTR+1
    adc #0
    ldy LOWTRB
    jsr FIXADC
    sta INDEX1+1
    tya
    adc #0
    sta INDEX1B
    jsr CloseGap

;; Inserts the new line, unless it is empty.
;; Also: NODEL (BB13)
InsertLine:
    lda BUF                                 ; Nothing after the number?
    beq ResetAndPrompt
    lda #0                                  ; DELTA = the new line's length
    sta DELTA+1
    sta DELTAB
    lda COUNT
    sta DELTA
    jsr OpenGap
    lda LINNUM
    ldy LINNUM+1
    sta BUF-2
    sty BUF-2+1
    ldy COUNT

;; Copies the line, from <BUF>-3, into the gap, last byte first.
;; Also: STOLOP (BB13)
CopyLine:
    lda BUF-4,Y
    dey
    sta (LOWTR),Y
    bne CopyLine

;; Resets the program's state after an edit, then goes back to the prompt.
;; Also: FINI (BB13)
ResetAndPrompt:
    jsr RewindTextPointer
    jsr ClearVariables::RestoreData
    jmp CommandLoop
.endproc

;; Reads a line into <BUF> with no prompt, for `INPUT`.
;;
;; It reads from the console, or from the `EXEC` file while one runs, through <INPUTLIN>. Lines read from a file with
;; `INPUT#` end at <InputLine::Terminate> too.
;; Out: X = the low byte of <BUF>-1, Y = its high byte, A = 0 (its bank), BUF = the line, ending in a zero
;; Entry:
;;   WithPrompt = prints the prompt character in X first, or none for zero
;;   Terminate = ends the line in <BUF> with a zero at X, its length, and returns <BUF>-1
;; See: <INPUTLIN>
;; Also: INLIN (BB13)
.proc InputLine
    ldx #0

;; Reads a line after printing the prompt in X, or none for zero.
;; Also: INLINB (BB13)
WithPrompt:
    jsr INPUTLIN

;; Ends the line in <BUF> with a zero at X and returns <BUF>-1 for <TXTPTR>.
;; Also: GDBUFS (BB13)
Terminate:
    lda #0
    sta BUF,X
    lda #0
    sta YSAVE
    ldx #<(BUF-1)
    ldy #>(BUF-1)
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Tokenizing
; ---------------------------------------------------------------------------------------------------------------------

;; The first byte of a two-byte token: the token, from the second keyword list, follows it.
TWO_BYTE_TOKEN = $FF

;; The tokenizer's helpers: <Tokenize> is at the top level.
.scope Tokenizer

;; Goes to <Tokenize::Finish> at the line's end, for <Tokenize>'s branch.
;; Also: GCRNCHED (BB13)
.proc ToFinish
    jmp Tokenize::Finish
.endproc

.endscope

;; Tokenizes the line in <BUF> in place, from <TXTPTR> on, and points <TXTPTR> at <BUF>-1 to run it.
;;
;; Keywords from <RESLST> become one-byte tokens, $80 to <SCRATK>; those of the second list, from <RESL2>, become
;; two bytes, <TWO_BYTE_TOKEN> and the token. A word is a keyword only with a separator (anything but a letter, digit
;; or period) before and after it, or when it ends in one, as `TAB(` does, so long variable names can hold keywords.
;; Letters may be in either case, and spaces inside a keyword are skipped. Spaces outside quotes are dropped, `?`
;; becomes `PRINT` and `!` becomes `REM`. Quoted text, and everything after `REM`, is copied as it is.
;;
;; <DORES> says when to copy: bit 7 set copies characters unchanged; a colon always turns tokenizing back on, and a
;; comma does when bit 6 is clear. `DATA`, `IMAGE` and `CAT` copy up to the colon. In a direct line (<LOWTR>+1 =
;; $FF), `INVOKE` and `RENAME` copy up to the colon, the other disk commands from `LOAD` to `CATALOG` up to the next
;; comma or colon, and `OPEN` tokenizes up to its first comma and copies after it, which bit 7 of <INTFLG> marks.
;;
;; The tokens go from <BUF> on, behind the characters still to read, with <BUFPTR> counting from 3. They end with
;; two zeros: the line's end, and a zero where a next line's length would be, which ends a direct line when it
;; runs. The three bytes before <BUF> are left for the line's length and number.
;; In: TXTPTR = the first character to tokenize, LOWTR+1 = $FF for a direct line, 0 for a numbered one
;; Out: Y = the line's length as stored in a program (its tokens and zero, and three bytes for its length and
;;   number), TXTPTR = <BUF>-1, TXTPTRB = 0
;; See: <CommandLoop>, <CommandLoop::EditLine>, <Tokenizer::IsSeparator>
;; Also: CRUNCH (BB13)
.proc Tokenize

;; Clears bit 5, which makes a lower-case letter upper case.
UPPER_CASE_MASK = $DF

    lda TXTPTR
    sec
    sbc #<(BUF)
    tax                                     ; X = the input's index in BUF
    lda #3
    sta BUFPTR
    sta DORES                               ; Tokenizing on
    sta INTFLG
    sta BUF-1,X                             ; A separator before the first word

;; Starts on the next input character, at the top of the keyword list.
;; Also: CLOOP (BB13)
NextInput:
    ldy #0
    sty COUNT+1                             ; One-byte tokens first
    lda #FIRST_TOKEN
    sta COUNT                               ; The first token
    lda #<(RESLST)
    sta FAC
    lda #>(RESLST)
    sta FAC+1
    lda #RESLSTB
    sta FACB
    lda BUF,X
    beq Tokenizer::ToFinish
    and #$7F
    cmp #':'                                ; A colon?
    beq TokenizeAgain
    cmp #','                                ; A comma?
    bne Classify
    bit INTFLG
    bpl CheckForComma
    ror DORES                               ; After OPEN: copy from here
    bmi Classify

;; Does a comma turn tokenizing back on?
CheckForComma:
    bit DORES
    bvs Classify

;; Turns tokenizing back on: A, a colon or comma, has bits 7 and 6 clear.
;; Also: ONCRNC (BB13)
TokenizeAgain:
    sta DORES

;; Copies the character, drops a space, or looks for a keyword.
;; Also: CL1 (BB13)
Classify:
    bit DORES
    bmi StoreToken                          ; Copying
    cmp #' '+1
    bcs NotSpace
    jmp Advance                             ; A space: drop it

;; Turns `!` into `REM`, and keeps the punctuation below it.
NotSpace:
    cmp #'!'
    bcc StoreToken
    bne CheckQuestion
    lda #REMTK
    bcs StoreToken

;; Turns `?` into `PRINT` and keeps other punctuation and digits.
;; Also: SHORT1 (BB13)
CheckQuestion:
    cmp #'?'
    bcc StoreToken
    bne SearchKeywords
    lda #PRINTK
    bcs StoreToken

;; Goes to <Tokenize::NextKeyword> for the branches.
;; Also: GNMTCH (BB13)
ToNextKeyword:
    jmp NextKeyword

;; Compares the input from X with the keyword at <FAC>.
;; Also: NPRNT (BB13)
SearchKeywords:
    stx TEMP                                ; Where the word starts

;; Starts the comparison again, with the next keyword.
;; Also: NPR2 (BB13)
TryKeyword:
    ldx TEMP

;; Compares the next input character, skipping spaces.
;; Also: NPR3 (BB13)
CompareNext:
    lda BUF,X
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
    eor (FAC),Y
    iny
    inx
    asl                                     ; The low seven bits must match
    bne ToNextKeyword
    bcc CompareNext                         ; Bit 7 clear: not the keyword's last character
    lda BUF,X                               ; The whole keyword matches: is a separator after it?
    and #$7F
    jsr Tokenizer::IsSeparator
    bcc CheckBefore
    dey                                     ; Or does the keyword end in one, as DEC( does?
    lda (FAC),Y
    and #$7F
    jsr Tokenizer::IsSeparator
    bcc CheckBefore
    lda COUNT                               ; Or is it EXFN. or EXFN%., or FN?
    cmp #EXFNSTK-1
    beq CheckBefore
    cmp #EXFNSTK
    beq CheckBefore
    cmp #FNTK
    bne ToNextKeyword
    bit COUNT+1                             ; FN is in the second list
    bpl ToNextKeyword

;; Takes the keyword when a separator comes before it too.
;; Also: YMTCH (BB13)
CheckBefore:
    txa
    pha
    ldx TEMP
    lda BUF-1,X
    jsr Tokenizer::IsSeparator
    pla
    tax
    bcs ToNextKeyword
    dex                                     ; Back to the keyword's last character
    lda COUNT+1
    bmi StoreToken                          ; Two bytes: TWO_BYTE_TOKEN first
    lda COUNT

;; Stores A in the tokens, with the token after <TWO_BYTE_TOKEN> for a two-byte token.
;; Also: STUFIT (BB13)
StoreToken:
    ldy BUFPTR
    sta BUF-3,Y
    iny
    cmp #TWO_BYTE_TOKEN
    bne KeepIndex
    lda COUNT
    sta BUF-3,Y
    iny
    lda #0                                  ; Matches none of the tests below

;; Keeps the output index.
;; Also: NESC (BB13)
KeepIndex:
    sty BUFPTR

;; Steps to the next input character, after checking whether the token just stored turns tokenizing off.
;; Also: NXCHR (BB13)
Advance:
    inx
    cmp #REMTK
    beq CopyRemark
    cmp #DATATK
    beq CopyToColon
    cmp #'"'                                ; A quote
    beq CopyUntil
    cmp #IMAGETK+2
    bcs ToNextInput
    ldy LOWTR+1                             ; A direct line?
    iny
    beq CheckOpen
    cmp #DSKCOMS+1                          ; In a program, only IMAGE and CAT go on
    bcc ToNextInput

;; Checks `OPEN`, `INVOKE` and the disk commands, and `IMAGE` and `CAT`.
;; Also: ITDIR (BB13)
CheckOpen:
    cmp #OPENTK
    bne CheckDiskCommand
    ror INTFLG                              ; Copy after OPEN's first comma
    bmi ToNextInput                         ; Always

;; Checks `INVOKE` and the disk commands.
;; Also: ITDIR1 (BB13)
CheckDiskCommand:
    cmp #INVOKTK
    beq CopyToColon
    cmp #LDTKN
    bcc ToNextInput
    cmp #RENMTK
    bne CopyToCommaOrColon

;; Copies up to the colon: bits 7 and 6 of <DORES> set.
;; Also: ITDIR15 (BB13)
CopyToColon:
    sec
    .byte $2C                               ; BIT abs, which skips the CMP

;; Copies up to the next comma or colon after a disk command (bit 6 clear), or up to the colon after `IMAGE` and
;; `CAT` (bit 6 set).
;; Also: ITDIR2 (BB13)
CopyToCommaOrColon:
    cmp #DSKCOMS+1
    ror DORES
    sec
    ror DORES

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
    sta ENDCHR
    ldy BUFPTR
    dey

;; Copies a character.
;; Also: DOQ2 (BB13)
CopyCharacter:
    iny
    inx
    lda BUF,X
    sta BUF-3,Y
    sty BUFPTR
    beq Finish
    cmp ENDCHR
    bne CopyCharacter
    iny
    sty BUFPTR
    inx
    jmp ToNextInput

;; Steps to the next keyword in the list, or stores the character as it is when there are no more.
;; Also: NOMTCH (BB13)
NextKeyword:
    dey
    beq SkipKeyword
    dey

;; Skips the rest of this keyword, then adds its length to <FAC>.
;; Also: FNDNXT (BB13)
SkipKeyword:
    iny
    lda (FAC),Y
    bpl SkipKeyword                         ; A keyword ends with bit 7 set
    sec
    tya
    adc FAC
    sta FAC
    bcc NextToken
    inc FAC+1                               ; The list never crosses into another bank

;; Steps the token number, moving to the second list after the statements.
NextToken:
    ldy #0
    ldx COUNT
    inx
    cpx #SCRATK+1                           ; Past the statements?
    bne CheckListEnd
    ldx #TWO_BYTE_TOKEN                     ; The second list: two-byte tokens from FIRST_TOKEN
    stx COUNT+1
    ldx #FIRST_TOKEN

;; Keeps the token number and checks for the list's end.
;; Also: FND2 (BB13)
CheckListEnd:
    stx COUNT
    lda (FAC),Y
    bne ToTryKeyword
    ldx TEMP                                ; No keyword: store the character
    lda BUF,X
    and #$7F
    jmp StoreToken

;; Ends the tokens with two zeros and points <TXTPTR> at <BUF>-1.
;; Also: CRNCHED (BB13)
Finish:
    ldy BUFPTR
    sta BUF-3,Y
    sta BUF-2,Y                             ; A zero length after the line: a direct line ends there
    lda #0
    sta TXTPTRB
    lda #>(BUF-1)
    sta TXTPTR+1
    lda #<(BUF-1)
    sta TXTPTR
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
;; See: <ISLETC>
;; Also: CKSEP (BB13)
.proc IsSeparator
    jsr ISLETC
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

;; Finds the line numbered <LINNUM>, or where it would go.
;;
;; It searches from <TXTTAB>; <FindLine::FromLine> searches from the line at Y, X and A (X-byte, page, low byte), as
;; `GOTO` does when the line is after the current one. Invokable modules can call both through <JMPRTAB>.
;; In: LINNUM = the line's number
;; Out: carry = set when found, LOWTR = the line's length byte, or the first line with a higher number, or the
;;   program's end
;; Entry:
;;   FromLine = searches from the line at Y, X and A
;;   FromPage = from the X-byte in <LOWTRB> and the page in X
;;   FromAddress = from the X-byte and page in LOWTR and the low byte in A
;; Also: FNDLIN (BB13)
.proc FindLine
    lda TXTTAB
    ldx TXTTAB+1
    ldy TXTTABB

;; Searches from the line at Y, X and A.
;; Also: FNDLNC0 (BB13)
FromLine:
    sty LOWTRB

;; Searches from the X-byte in <LOWTRB>, the page in X and the low byte in A.
;; Also: FNDLNC1 (BB13)
FromPage:
    stx LOWTR+1

;; Searches from the line at <LOWTR>, with its low byte in A.
;; Also: FNDLNC (BB13)
FromAddress:
    sta LOWTR
    ldy #0
    lda (LOWTR),Y                           ; The line's length
    beq NotFound                            ; Zero: the program's end
    ldy #2
    tax
    lda LINNUM+1
    cmp (LOWTR),Y
    bcc Done                                ; Past it: not there
    bne NextLine
    lda LINNUM
    dey
    cmp (LOWTR),Y
    bcc Done                                ; Past it: not there
    beq Done                                ; Found, with carry set

;; Steps <LOWTR> to the next line, by this one's length in X.
;; Also: AFFRTS (BB13)
NextLine:
    txa
    clc
    adc LOWTR
    bcc FromAddress
    ldx LOWTR+1
    inx
    cpx #MAXPG
    bcc FromPage
    pha                                     ; Into the next bank pair
    txa
    sbc #MAXPG-MINPG
    tax
    pla
    inc LOWTRB
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
.scope Statements continued

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
    jsr CLSALL
    jsr ResetInterpreter
    ; Falls into ResetProgramState.
.endproc

;; Gets ready to run the program from its start, for `RUN`: points <TXTPTR> before the first line, marks <CURLIN> as
;; not direct so the statement fetcher goes on to the first line, and clears as `CLEAR` does.
;; See: <RewindTextPointer>, <ClearVariables>
;; Also: RUNC (BB13)
.proc ResetProgramState
    jsr RewindTextPointer
    lda #0                                  ; Sets zero for CLEAR's test
    sta CURLIN+1
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
;; The strings start again at <MEMSIZ>, and the simple variables and the end of the variables (<VARTAB> and
;; <STREND>) go back to <ARYTAB>, the program's end. Memory comes back with <EXPAND>, `DATA` with <RESTOR>, and it
;; falls into <ResetStack>.
;; Entry:
;;   KeepFiles = clears without closing the files, for `LOAD`
;;   RestoreData = only takes back the memory and resets `DATA` and the stack
;; See: <ResetStack>
;; Also: CLEARC (BB13)
.proc ClearVariables
    jsr CLSALL

;; Clears without closing the files.
;; Also: CLEARL (BB13)
KeepFiles:
    lda MEMSIZ
    ldx MEMSIZB
    ldy MEMSIZ+1                            ; No strings
    sta FRETOP
    sty FRETOP+1
    stx FRETOPB
    lda ARYTAB
    ldy ARYTAB+1                            ; No variables or arrays
    ldx ARYTABB
    sta VARTAB
    sty VARTAB+1
    stx VARTABB
    sta STREND
    sty STREND+1
    stx STRENDB
    lda #0
    sta KEYSAVE                             ; KBD
    sta ERRNUM                              ; ERR
    sta ERRLIN                              ; ERRLIN
    sta ERRLIN+1
    sta EOFSV                               ; EOF

;; Takes back all memory with <EXPAND>, points `DATA` at the program's start with <RESTOR>, and resets the stack.
;; Also: FLOAD (BB13)
RestoreData:
    lda #0
    jsr EXPAND
    jsr RESTOR
    ; Falls into ResetStack.
.endproc

;; Empties the stack, keeping only the caller's return address, and resets the formula evaluator's stacks.
;;
;; The stack pointer goes to <STKEND> and into <REMSTK>; `GOSUB` and `FOR` entries are gone. The byte above, the
;; zero <ColdStart> pushed, stays at the bottom for <FindForFrame>. Apple's comment said it also frees the string
;; temporaries and forbids `CONT`; the code does neither.
;; Entry: Done = returns, for `CLEAR` with something after it
;; Also: STKINI (BB13)
.proc ResetStack
    pla                                     ; The return address
    tay
    pla
    ldx #STKEND
    stx REMSTK
    txs
    pha
    tya
    pha
    lda #2
    sta VRBPT                               ; Past the end-of-line entry
    lda #0
    sta VRBSTK+1                            ; The end-of-line precedence
    sta NOUNPT
    sta SUBFLG                              ; Subscripts allowed

;; Returns.
;; Also: STKRTS (BB13)
Done:
    rts
.endproc

;; Points <TXTPTR> at the byte before the program, writing the zero there, then turns off the program's handlers
;; as <ClearHandlers> does.
;; See: <ClearHandlers>
;; Also: STXTPT (BB13)
.proc RewindTextPointer
    sec
    lda TXTTAB
    sbc #1
    sta TXTPTR
    lda TXTTAB+1
    sbc #0
    ldy TXTTABB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc #0
    sta TXTPTRB
    ldy #0
    tya
    sta (TXTPTR),Y                          ; The zero before the first line
    ; Falls into ClearHandlers.
.endproc

;; Turns off `ON KBD`, `ON EOF` and `ON ERR`, clears any key waiting in <KEYSTROK>, and leaves nothing for `RESUME`.
;;
;; It turns off the console's any-key event with <Statements::OffKbd>, clears every handler in <EOFPTRS>, and clears
;; <ERRFLG> and <ERRPOSB>. `LOAD` calls it too.
;; Out: A = 0, Y = 0
;; Also: CLEARONS (BB13)
.proc ClearHandlers
    jsr Statements::OffKbd
    ldy #EOFSIZ
    lda #0
    sta KEYSTROK

;; Clears <EOFPTRS>, from the top.
;; Also: CLEOFS (BB13)
ClearNext:
    sta EOFPTRS-1,Y
    dey
    bne ClearNext
    sty ERRFLG                              ; No ON ERR
    sty ERRPOSB                             ; No error to RESUME
    rts
.endproc
