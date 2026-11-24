; retrocore: style=strict
; APPLESOFT: ERRORS, COMMAND INPUT AND PROGRAM STORAGE
;
; Error reporting and the command loop, line editing and tokenization, program-line search and insertion,
; and the NEW and CLEAR paths. Statement execution continues in NextStatement.

.include "../Microsoft6502Basic/MsBasic.CommandCore.asm"

;; Reports an OUT OF MEMORY error: loads its offset and falls into <ReportError>.
;; Also: OMERR (M6502)
.proc ReportOutOfMemory
    ldx #ERROR_OUT_OF_MEMORY
    ; Falls into ReportError.
.endproc

;; Passes the error to an active `ONERR` handler, or prints it and returns to the command loop.
;;
;; The high bit marks the last character of each message in <ErrorMessages>. After the message, <ResetStack> clears
;; execution state and the line number is printed unless the error occurred in direct mode.
;; In: X = the message's offset in <ErrorMessages>
;; Also: ERROR (M6502, ASTIL)
.proc ReportError
    bit OnErrorActive
    bpl PrintMessage
    jmp HANDLE

;; No `ONERR` handler is active: starts a new line and prints the question mark.
;; Also: ERROR1 (UNKN), DOERRMSG (AS82)
PrintMessage:
    jsr PrintNewline
    jsr PrintQuestionMark

;; Prints the message's characters until the one with bit 7 set, then falls into `AddErrorSuffix`.
;; Also: GETERR (M6502)
NextCharacter:
    lda ErrorMessages,x
    pha
    jsr PrintCharacter
    inx
    pla
    bpl NextCharacter
    ErrorFinish
.endproc

    ReportMessageRoutine

;; Where errors, `END` and `STOP` return: AppleSoft prints no READY message, so this is <CommandLoop>'s own address.
;; Also: READY (M6502)
ReadyForCommand:

;; Prompts for a command, then runs a direct statement or inserts, replaces or deletes a numbered line.
;;
;; Editing an existing line first closes the gap. A replacement opens space with <MoveRangeUp>, then the program is
;; relinked and variables and execution state are reset. An empty numbered line deletes the old line.
;; See: <InputLine::WithPrompt>, <Tokenize>, <FindLine>, <LinkProgram>
;; Also: MAIN (M6502)
.proc CommandLoop
    jsr PrintNewline
    ldx #(']' | $80)
    jsr InputLine::WithPrompt
    stx TextPointer
    sty TextPointer+1
    lsr OnErrorActive
    jsr GetNextCharacter
    tax
    beq CommandLoop
    ldx #$FF                        ; a direct line: line number $FFxx
    stx CurrentLine+1
    bcc EditProgram
    jsr Tokenize
    jmp NextStatement::TraceLine

;; A numbered line: resets <VariablesStart> from <ProgramEnd>, then deletes any old line of that number.
;; Also: READY1 (UNKN)
EditProgram:
    ldx ProgramEnd
    stx VariablesStart
    ldx ProgramEnd+1
    stx VariablesStart+1
    DeleteOldLine Pointer1

;; After any deletion: an empty line relinks; otherwise opens space at the insertion point with <MoveRangeUp>.
;; Also: NODEL (M6502)
InsertLine:
    lda BUF
    beq ClearAndRelink
    lda MemoryTop
    ldy MemoryTop+1
    sta StringsBottom
    sty StringsBottom+1             ; Microsoft's NCMWID here is the same byte
    lda VariablesStart
    sta SourceEnd
    adc Counter
    sta DestinationEnd
    ldy VariablesStart+1
    sty SourceEnd+1
    bcc OpenGap
    iny

;; Stores the high byte of the move's end and opens the gap with <MoveRangeUp>.
;; Also: NODELC (M6502)
OpenGap:
    sty DestinationEnd+1
    jsr MoveRangeUp
    lda LineNumber
    ldy LineNumber+1
    sta BUF-2
    sty BUF-1
    lda ArraysEnd
    ldy ArraysEnd+1
    sta VariablesStart
    sty VariablesStart+1
    ldy Counter

;; Copies the tokenized line from the input buffer into the program.
;; Also: NODEL1 (UNKN)
CopyLine:
    lda BUF-5,y
    dey
    sta (SourceStart),y
    bne CopyLine
    ; Falls into ClearAndRelink.
.endproc

;; Clears execution state and relinks the program after editing or loading it, falling into <LinkProgram>.
;; See: <ResetProgramState>
;; Also: FINI (M6502)
.proc ClearAndRelink
    jsr ResetProgramState
    ; Falls into LinkProgram.
.endproc

;; Rebuilds the linked program's line addresses, then records <VariablesStart> as <ProgramEnd> and returns to
;; <CommandLoop>.
;;
;; Each line ends in zero; the next line starts immediately after it. A zero link marks the end of the program.
;; Also: LNKPRG (M6502)
.proc LinkProgram
    lda ProgramStart
    ldy ProgramStart+1
    sta Pointer1
    sty Pointer1+1
    clc

;; Tests a line's link high byte; zero ends the program.
;; Also: CHEAD (M6502), NXLINK (AS82)
NextLine:
    ldy #ProgramLine::LINK + 1
    lda (Pointer1),y
    bne StoreLink
    lda VariablesStart
    sta ProgramEnd
    lda VariablesStart+1
    sta ProgramEnd+1
    jmp CommandLoop

;; Scans the line to its zero and stores the next line's address as its link.
;; Also: CHEAD1 (UNKN)
StoreLink:
    LinkLine 0
.endproc

;; The longest line AppleSoft keeps from the Monitor's input: the buffer, less the zero that ends the line.
INPUT_LINE_LIMIT = INPUT_BUFFER_LENGTH - 1

;; Reads a line through the Monitor without printing a prompt character.
;;
;; The terminating byte is replaced with zero, the input is limited to <INPUT_LINE_LIMIT> characters, and bit 7 is
;; cleared from each character.
;; Out: A = 0, X = the low byte of the address before <BUF>, Y = its high byte
;; Entry:
;;   WithPrompt = uses X as the Monitor's prompt character; <CommandLoop> enters here with `]`
;; See: <GETLN>, <InputCharacter>
;; Also: INLIN (M6502, ASTIL)
.proc InputLine
    ldx #$80                        ; a prompt the Monitor prints as nothing

;; Uses X as the Monitor's prompt character.
;; Also: INLIN1 (UNKN)
WithPrompt:
    stx PROMPT
    jsr GETLN
    cpx #INPUT_LINE_LIMIT
    bcc Terminate
    ldx #INPUT_LINE_LIMIT

;; Stores the zero after the last character.
;; Also: GDBUFS (M6502, ASTIL)
Terminate:
    lda #$00
    sta BUF,x
    txa
    beq Finish

;; Clears bit 7 of each input character.
;; Also: LOPBHT (M6502)
ClearHighBits:
    lda BUF-1,x
    and #$7F
    sta BUF-1,x
    dex
    bne ClearHighBits

;; Returns A = 0 and X/Y = the address before <BUF>.
;; Also: NOCHR (M6502)
Finish:
    lda #$00
    ldx #<(BUF-1)
    ldy #>(BUF-1)
    rts
.endproc

;; Reads a key through the Monitor and clears its high bit.
;; Out: A = the character, with bit 7 clear
;; Also: INCHR (M6502, ASTIL)
.proc InputCharacter
    jsr CQINCH
    and #$7F

;; Returns; nothing branches here, and the label is kept for its old name.
;; Also: INCRTS (M6502)
Return:
    rts
.endproc

;; The input buffer's page base for the tokenizer's indexing. Microsoft's source sets it to 0 and then to $0200;
;; AppleSoft's code never uses it.
;; Also: BUFOFS (M6502)
INPUT_BUFFER_BASE = $0200

;; Tokenizes the line in <BUF> in place, replacing reserved words by their single-byte tokens from <ReservedWords>.
;;
;; Spaces outside literals and `DATA` are discarded. Quoted strings, `DATA` fields and `REM` text are copied without
;; tokenization; `?` abbreviates `PRINT`. The enhanced IIe folds case outside quoted strings, `DATA` and `REM`. `AT` is
;; not matched when followed by `N` or `O`, so that `ATN` and `TO` are recognized. Where the program is run-only
;; (<RunOnly>), it discards its caller and runs the program instead.
;; In: TextPointer = the first character's address, whose low byte is its offset in <BUF>'s page
;; Out: TextPointer = the address before the tokenized line, Y = the encoded line's length, header included
;; See: <Statements::List>
;; Also: CRUNCH (M6502)
.proc Tokenize
    ldx TextPointer
    dex
    ldy #$04                        ; the stores, to BUF-5,y after an increment, start at BUF
    sty TokenizeState
    bit RunOnly
    bpl Advance
    pla
    pla
    jsr ResetProgramState
    jmp NextStatementSavingStack

;; Steps to the next input character.
;; Also: CRUNC1 (UNKN)
Advance:
    inx

;; Reads the next input character, folding its case on the enhanced IIe, for tokenizing.
;; Also: KLOOP (M6502)
NextCharacter:
.if ENHNCD
    jsr UPCASE
.else
    lda BUF,x
.endif
    bit TokenizeState
    bvs CheckQuote

;; Skips a space outside `DATA`.
;; Also: CMPSPC (M6502)
CheckSpace:
    cmp #' '
    beq Advance

;; Records the character as the end delimiter, and starts a quoted copy at a quote.
;; Also: CMPSP1 (UNKN)
CheckQuote:
    sta EndDelimiter
    cmp #'"'
    beq StoreLiteral
    bvs StoreByte
    cmp #'?'
    bne CheckDigit
    lda #TOKEN_PRINT
    bne StoreByte

;; Copies digits, `:` and `;` unchanged.
;; Also: KLOOP1 (M6502)
CheckDigit:
    cmp #'0'
    bcc SearchWords
    cmp #';' + 1
    bcc StoreByte

;; Sets up the walk of <ReservedWords> from the current input position.
;; Also: MUSTCR (M6502)
SearchWords:
    sty TokenizePointer
    lda #<(ReservedWords-256)
    sta Fac
    lda #>(ReservedWords-256)
    sta FacMantissa1
    ldy #$00
    sty Counter
    dey
    stx TextPointer
    dex

;; A character matched: advances in the table, with the page carry, and in the input.
;; Also: RESER (M6502)
CharacterMatched:
    iny
    bne AdvanceInput
    inc FacMantissa1

;; Advances the input index, skipping spaces.
;; Also: RESPUL (M6502)
AdvanceInput:
    inx

;; Compares the input character with the table's.
;; Also: RESPU1 (UNKN)
CompareCharacter:
.if ENHNCD
    jsr UPCASE
.else
    lda BUF,x
.endif
    cmp #' '
    beq AdvanceInput
    sec
    sbc (Fac),y
    beq CharacterMatched
    cmp #$80                        ; the word's last character, which has bit 7 set
    bne NextWord
    ora Counter
    cmp #TOKEN_AT
    bne StoreToken
.if ENHNCD
    jsr UPNXT
.else
    lda BUF+1,x
.endif
    cmp #'N'
    beq NextWord
    cmp #'O'
    beq NextWord
    lda #TOKEN_AT
    TokenStore BUF, ENHNCD

;; A mismatch: restores the input index, counts the word and skips to its end.
;; Also: NTHIS (M6502)
NextWord:
    ldx TextPointer
    inc Counter

;; Reads table bytes until the word's last character.
;; Also: NTHIS2 (UNKN)
SkipWord:
    lda (Fac),y

;; Advances the table index; nothing branches here, and the label is kept for its old name.
;; Also: NTHIS1 (M6502)
AdvanceTable:
    iny
    bne TestWordEnd
    inc FacMantissa1

;; Tests bit 7 of the table byte after any page carry.
;; Also: NTHIS3 (UNKN)
TestWordEnd:
    asl a
    bcc SkipWord
    lda (Fac),y
    bne CompareCharacter
.if ENHNCD
    jsr UPBUF
.else
    lda BUF,x
.endif
    bpl StoreToken

;; Stores the line's end and sets <TextPointer> to the byte before <BUF>.
;; Also: CRDONE (M6502)
Finish:
    sta BUF-3,y
    dec TextPointer+1
    lda #<(BUF-1)
    sta TextPointer

;; Returns; nothing branches here, and the label is kept for its old name.
;; Also: LISTRT (M6502)
Return:
    rts
.endproc

.include "../Microsoft6502Basic/MsBasic.LineSearch.asm"
.include "../Microsoft6502Basic/MsBasic.ProgramReset.asm"
    ProgramReset 1, 1, 0, 1
    ClearStatement ResetStack::Done
    ClearStorage 0, 0
    ExecutionReset 0, 0, $F8
