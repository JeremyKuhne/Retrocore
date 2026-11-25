; retrocore: style=strict
; COMMODORE BASIC: ERRORS, COMMAND EDITING, TERMINAL INPUT AND TOKENIZATION
;
; Include after the selected workspace and emit these four macros in order at ReportOutOfMemory:
;              CommodoreErrorReady  CommodoreCommandLoop  CommodoreTerminalInput  CommodoreTokenize
; BASIC 1      1                    0, 0, 0, 0            1, 0                    0, 1
; BASIC 2      1                    1, 1, 1, 0            0, 0                    0, 0
; BASIC 4      0                    1, 1, 1, 1            0, 1                    1, 0
; Both revisions of BASIC 1 and BASIC 4 use their version's same settings. The next entry is FindLine.

.include "../../Microsoft6502Basic/MsBasic.CommandCore.asm"

;; Emits error reporting and the READY prompt: <ReportOutOfMemory>, <ReportError> and <ReadyForCommand>, which falls
;; into the <CommandLoop> that <CommodoreCommandLoop> emits next.
;; Parameters: clearSuppression = 1 to clear the output-suppression flag when reporting an error and at READY
.macro CommodoreErrorReady clearSuppression
    .assert clearSuppression = 0 || clearSuppression = 1, "clearSuppression is 0 or 1."

    ;; Reports an OUT OF MEMORY error: loads its offset and falls into <ReportError>.
    ;; Also: OMERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReportOutOfMemory
    ldx #<ERROR_OUT_OF_MEMORY
    ; Falls into ReportError.
    .endproc

    ;; Restores the default channels when one is selected and prints the error, then returns to the command prompt.
    ;;
    ;; Where `clearSuppression` is 1 (BASIC 1 and 2), it first clears the output-suppression flag.
    ;; In: X = the message's offset in <ErrorMessages>
    ;; See: <KernalResetChannels>, <PrintCharacter>, <ReportMessage>
    ;; Also: ERROR (M6502, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, CBM4S79)
    .proc ReportError
    .if clearSuppression
        lsr OutputSuppressed
    .endif
    lda CurrentChannel
    beq PrintMessage
    jsr KernalResetChannels
    lda #$00
    sta CurrentChannel

;; Starts a new line and prints the question mark.
;; Also: ERRCRD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PrintMessage:
    jsr PrintNewline
    jsr PrintQuestionMark

;; Prints the message's characters until the one with bit 7 set, then falls into <ReportError::AddErrorSuffix>.
;; Also: GETERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    lda ErrorMessages,x
    pha
    and #$7F
    jsr PrintCharacter
    inx
    pla
    bpl NextCharacter
    ErrorFinish
    .endproc

    ReportMessageRoutine

    ;; Prints the READY message and falls into <CommandLoop>.
    ;;
    ;; Where `clearSuppression` is 1 (BASIC 1 and 2), it first clears the output-suppression flag.
    ;; See: <CommandLoop>
    ;; Also: READY (M6502, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, CBM4S79)
    .proc ReadyForCommand
    .if clearSuppression
        lsr OutputSuppressed
    .endif
    lda #<ReadyMessage
    ldy #>ReadyMessage
    jsr PrintText
    ; Falls into CommandLoop.
    .endproc
.endmacro

;; Emits the command loop, program-line editing and link reconstruction: <CommandLoop>, <ClearAndRelink> and
;; <LinkProgram>.
;; Parameters: testCharacter = 1 to set zero from A after fetching the first character;
;;   resetBeforeInsert = 1 to clear variables and relink before inserting;
;;   linkReturns = 1 for <LinkProgram> to return rather than jump to <CommandLoop>;
;;   addHighToY = 1 for the BASIC 4 link high-byte addition
.macro CommodoreCommandLoop testCharacter, resetBeforeInsert, linkReturns, addHighToY
    .assert testCharacter = 0 || testCharacter = 1, "testCharacter is 0 or 1."
    .assert resetBeforeInsert = 0 || resetBeforeInsert = 1, "resetBeforeInsert is 0 or 1."
    .assert linkReturns = 0 || linkReturns = 1, "linkReturns is 0 or 1."
    .assert addHighToY = 0 || addHighToY = 1, "addHighToY is 0 or 1."
    .assert resetBeforeInsert = 0 || linkReturns = 1, "Relinking before insertion requires a returning LinkProgram."

    ;; Reads and executes a direct command, or inserts, replaces or deletes a numbered program line.
    ;;
    ;; Where `resetBeforeInsert` is 1 (BASIC 2 and 4), a new line first clears the variables and relinks the program.
    ;; See: <InputLine>, <Tokenize>, <FindLine>, <LinkProgram>
    ;; Also: MAIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CommandLoop
    jsr InputLine
    stx TextPointer
    sty TextPointer+1
    jsr GetNextCharacter
    .if testCharacter
        tax
    .endif
    beq CommandLoop
    ldx #$FF                        ; a direct line: line number $FFxx
    stx CurrentLine+1
    bcc EditLine
    jsr Tokenize
    jmp ExecuteStatement

    DeleteOldLine Pointer1

;; After any deletion: an empty line relinks; otherwise opens space with <MoveRangeUp>.
;; Also: NODEL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
InsertLine:
    .if resetBeforeInsert
        jsr ResetProgramState
        jsr LinkProgram
        lda InputBuffer
        beq CommandLoop
        clc
    .else
        lda InputBuffer
        beq ClearAndRelink
        lda MemoryTop
        ldy MemoryTop+1
        sta StringsBottom
        sty StringsBottom+1
    .endif
    lda VariablesStart
    sta SourceEnd
    adc Counter
    sta DestinationEnd
    ldy VariablesStart+1
    sty SourceEnd+1
    bcc OpenGap
    iny

;; Stores the high byte of the move's end and opens the gap with <MoveRangeUp>.
;; Also: NODELC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
OpenGap:
    sty DestinationEnd+1
    jsr MoveRangeUp
    .if INPUT_BUFFER_PAGE
        lda LineNumber
        ldy LineNumber+1
        sta InputBuffer-2
        sty InputBuffer-1
    .endif
    lda ArraysEnd
    ldy ArraysEnd+1
    sta VariablesStart
    sty VariablesStart+1
    ldy Counter
    dey

;; Copies the tokenized line from the input buffer into the program.
;; Also: STOLOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CopyLine:
    lda InputBuffer-4,y
    sta (SourceStart),y
    dey
    bpl CopyLine
    ; Falls into ClearAndRelink.
    .endproc

    ;; Clears execution state and relinks the program after an edit, then enters <CommandLoop>; where `linkReturns`
    ;; is 0 (BASIC 1) it falls into <LinkProgram>, which enters <CommandLoop> itself.
    ;; See: <ResetProgramState>, <LinkProgram>
    ;; Also: FINI (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ClearAndRelink
    jsr ResetProgramState
    .if linkReturns
        jsr LinkProgram
        jmp CommandLoop
    .endif
    .endproc

    ;; Rebuilds the linked program addresses by scanning each zero-terminated line.
    ;;
    ;; Where `linkReturns` is 0 (BASIC 1) it enters <CommandLoop> at the end; in BASIC 2 and 4 it returns.
    ;; In: ProgramStart = the first line, with a zero high link byte marking the end of the program
    ;; Also: LNKPRG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc LinkProgram
    lda ProgramStart
    ldy ProgramStart+1
    sta Pointer1
    sty Pointer1+1
    clc

;; Tests a line's link high byte; zero ends the program.
;; Also: CHEAD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextLine:
    ldy #ProgramLine::LINK + 1
    lda (Pointer1),y
    .if linkReturns
        beq Return
    .else
        bne StoreLink
        jmp CommandLoop

;; A line follows: scans it and stores the next line's address as its link.
StoreLink:
    .endif
    LinkLine addHighToY
    .if linkReturns

;; Returns at the end of the program.
;; Also: LNKRTS (M6502, CBM4S79, HV2, HV4, HV4R)
Return:
        rts
    .endif
    .endproc
.endmacro

;; Emits the terminal-line reader, <InputLine>, and, where `checkedInput` is 0, its character-input wrapper.
;; Parameters: earlyDelete = 1 to retain the early line-editing entries;
;;   checkedInput = 1 to reject a full buffer and call the kernal directly
.macro CommodoreTerminalInput earlyDelete, checkedInput
    .assert earlyDelete = 0 || earlyDelete = 1, "earlyDelete is 0 or 1."
    .assert checkedInput = 0 || checkedInput = 1, "checkedInput is 0 or 1."
    .assert earlyDelete = 0 || checkedInput = 0, "The early editor uses the character-input wrapper."

    .if earlyDelete
        ;; Backs the input index up one, and before the buffer falls into <RestartInputLine>; nothing enters here,
        ;; and the routine is kept for its old name.
        ;; Also: LINLIN (M6502, HV1, HV1R)
        .proc EraseInputCharacter
        dex
        bpl InputLine::NextCharacter
        ; Falls into RestartInputLine.
        .endproc

        ;; Prints a newline and falls into <InputLine>; nothing enters here, and the routine is kept for its old name.
        ;; Also: INLINN (M6502, HV1, HV1R)
        .proc RestartInputLine
        jsr PrintNewline
        ; Falls into InputLine.
        .endproc
    .endif

    ;; Reads a carriage-return-terminated line into <InputBuffer>.
    ;;
    ;; Where `checkedInput` is 1 (BASIC 4), it reports STRING TOO LONG when it fills the buffer. The earlier readers
    ;; rely on the editor's limit and continue until carriage return or an eight-bit index wrap.
    ;; Out: X/Y = address before <InputBuffer> after <FinishInputLine>
    ;; Errors: STRING TOO LONG for a full buffer where `checkedInput` is 1
    ;; Entry:
    ;;   NextCharacter = reads and stores the next character; BASIC 1's erase step branches here
    ;; Also: INLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc InputLine
    ldx #$00

;; Reads and stores the next character.
;; Also: INLINC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    .if checkedInput
        jsr KernalCharacterIn
    .else
        jsr InputCharacter
    .endif
    cmp #$0D                        ; carriage return
    beq ToFinishInputLine
    .if .not checkedInput

;; Stores the character in the buffer; nothing branches here, and the label is kept for its old name.
;; Also: GOODCH (M6502)
StoreCharacter:
    .endif
    sta InputBuffer,x
    inx
    .if checkedInput
        cpx #INPUT_BUFFER_LENGTH
        bne NextCharacter
        ldx #<ERROR_STRING_TOO_LONG
        jmp ReportError
    .else
        bne NextCharacter
    .endif

;; Jumps on to <FinishInputLine>.
;; Also: FININ1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToFinishInputLine:
    jmp FinishInputLine
    .endproc

    .if .not checkedInput
        ;; Reads a character, and toggles <OutputSuppressed> on Control-O from the keyboard.
        ;;
        ;; Control-O on a selected nonterminal channel is returned without changing the flag.
        ;; Out: A = input character
        ;; See: <KernalCharacterIn>
        ;; Also: INCHR (M6502, HV1, HV1R, HV2)
        .proc InputCharacter
        jsr KernalCharacterIn
        ldy CurrentChannel
        bne Return
        cmp #SUPPRESS_OUTPUT_KEY
        bne Return
        pha
        lda OutputSuppressed
        eor #$FF
        sta OutputSuppressed
        pla

;; Returns.
;; Also: INCRTS (M6502, HV1, HV1R, HV2)
Return:
        rts
        .endproc
    .endif
.endmacro

;; Emits the PET reserved-word tokenizer, <Tokenize>.
;; Parameters: indirectTable = 1 to walk a table longer than 256 bytes through <Pointer1>;
;;   skipKeywordSpaces = 1 to ignore spaces while matching reserved words
.macro CommodoreTokenize indirectTable, skipKeywordSpaces
    .assert indirectTable = 0 || indirectTable = 1, "indirectTable is 0 or 1."
    .assert skipKeywordSpaces = 0 || skipKeywordSpaces = 1, "skipKeywordSpaces is 0 or 1."
    .assert indirectTable = 0 || skipKeywordSpaces = 0, "The indirect table walker does not skip keyword spaces."
    .if indirectTable
        .assert <ReservedWords != 0, "The indirect table setup branches on the nonzero low byte of ReservedWords."
    .endif

    ;; Replaces reserved words in the input buffer with tokens from <ReservedWords>.
    ;;
    ;; Spaces are retained. Quoted strings, `DATA` fields and `REM` text are copied without tokenization; a colon
    ;; ends a `DATA` field and `?` abbreviates `PRINT`. High-bit characters other than pi are discarded outside
    ;; quoted strings and `REM` text, including in an unquoted `DATA` field. Where `skipKeywordSpaces` is 1
    ;; (BASIC 1), the walker ignores spaces within a word; where `indirectTable` is 1 (BASIC 4), it walks the table
    ;; through <Pointer1>.
    ;; In: TextPointer = the first character's address, whose low byte is its offset in <InputBuffer>'s page
    ;; Out: TextPointer = address before <InputBuffer>, Y = encoded line length including the link and line-number
    ;;   header
    ;; See: <Statements::List>
    ;; Also: CRUNCH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Tokenize
    ldx TextPointer
    ldy #$04                        ; the stores, to InputBuffer-5,y after an increment, start at InputBuffer
    sty TokenizeState

;; Reads the next input character; a high-bit character other than pi is skipped.
;; Also: KLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    lda INPUT_BUFFER_BASE,x
    bpl CheckSpace
    cmp #TOKEN_PI
    beq StoreByte
    inx
    bne NextCharacter

;; Copies a space; records the end delimiter and starts a quoted copy at a quote.
;; Also: CMPSPC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckSpace:
    cmp #' '
    beq StoreByte
    sta EndDelimiter
    cmp #'"'
    beq StoreLiteral
    bit TokenizeState
    bvs StoreByte
    cmp #'?'
    bne CheckDigit
    lda #<TOKEN_PRINT
    bne StoreByte

;; Copies digits, `:` and `;` unchanged.
;; Also: KLOOP1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckDigit:
    cmp #'0'
    bcc SearchWords
    cmp #';' + 1
    bcc StoreByte

;; Sets up the walk of <ReservedWords> from the current input position.
;; Also: MUSTCR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SearchWords:
    sty TokenizePointer
    ldy #$00
    sty Counter
    .if indirectTable
        stx TextPointer
        lda #>ReservedWords
        sta Pointer1+1
        lda #<ReservedWords
        sta Pointer1
        bne CompareCharacter

;; A character matched: advances in the table and the input.
;; Also: RESER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CharacterMatched:
        inx
        inc Pointer1
        bne CompareCharacter
        inc Pointer1+1
    .else
        dey
        stx TextPointer
        dex

;; A character matched: advances in the table and the input.
;; Also: RESER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CharacterMatched:
        iny

;; Advances the input index; BASIC 1 skips spaces here.
;; Also: RESPUL (M6502, HV1, HV1R)
AdvanceInput:
        inx
    .endif

;; Compares the input character with the table's.
;; Also: RESCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CompareCharacter:
    lda INPUT_BUFFER_BASE,x
    .if skipKeywordSpaces
        cmp #' '
        beq AdvanceInput
    .endif
    sec
    .if indirectTable
        sbc (Pointer1),y
    .else
        sbc ReservedWords,y
    .endif
    beq CharacterMatched
    cmp #$80                        ; the word's last character, which has bit 7 set
    bne NextWord
    ora Counter

    TokenStore INPUT_BUFFER_BASE, 0

;; A mismatch: restores the input index, counts the word and skips to its end.
;; Also: NTHIS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextWord:
    ldx TextPointer
    inc Counter

;; Reads table bytes until the word's last character.
;; Also: NTHIS1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipWord:
    .if indirectTable
        lda (Pointer1),y
        php
        inc Pointer1
        bne TestWordEnd
        inc Pointer1+1

;; Tests bit 7 after the pointer's page carry.
;; Also: NTHIS2 (CBM4S79, HV4, HV4R)
TestWordEnd:
        plp
    .else
        iny
        lda ReservedWords-1,y
    .endif
    bpl SkipWord
    .if indirectTable
        lda (Pointer1),y
    .else
        lda ReservedWords,y
    .endif
    bne CompareCharacter
    lda INPUT_BUFFER_BASE,x
    bpl StoreToken

;; Stores the line's end and sets <TextPointer> to the byte before <InputBuffer>.
;; Also: CRDONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Finish:
    sta InputBuffer-3,y
    .if INPUT_BUFFER_PAGE
        dec TextPointer+1
    .endif
    lda #<(InputBuffer-1)
    sta TextPointer

;; Returns; nothing branches here, and the label is kept for its old name.
;; Also: LISTRT (M6502)
Return:
    rts
    .endproc
.endmacro
