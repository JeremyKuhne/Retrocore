; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: ERROR FINISHING, PROGRAM EDITING AND TOKEN STORAGE
;
; Each macro but ReportMessageRoutine expands inside a vendor's routine, whose labels its own join: ErrorFinish ends the
; vendor's ReportError, DeleteOldLine expands in CommandLoop, LinkLine in LinkProgram and TokenStore in Tokenize. Their
; branches name the vendor routine's labels unqualified. The vendor closes ReportError after ErrorFinish and emits
; ReportMessageRoutine next.

;; Emits the end of <ReportError>: the error suffix's load, which falls into <ReportMessage>.
.macro ErrorFinish

;; Resets execution state and loads the address of <ErrorSuffix>, then falls into <ReportMessage>; the message loop
;; falls here at the message's last character.
;; Also: TYPERR (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
AddErrorSuffix:
    jsr ResetStack
    lda #<ErrorSuffix
    ldy #>ErrorSuffix
    ; Falls into ReportMessage.
.endmacro

;; Emits <ReportMessage>, which falls into the vendor's <ReadyForCommand>.
.macro ReportMessageRoutine

    ;; Prints the message at A/Y and the current line number unless execution is direct, then falls into the vendor's
    ;; <ReadyForCommand>.
    ;; In: A = message address low byte, Y = message address high byte
    ;; See: <ReportError>, <Statements::Stop>, <PrintText>, <Float::PrintInLineNumber>, <ReadyForCommand>
    ;; Also: ERRFIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReportMessage
    jsr PrintText
    ldy CurrentLine+1
    iny
    beq ReadyForCommand
    jsr Float::PrintInLineNumber
    ; Falls into ReadyForCommand.
    .endproc
.endmacro

;; Emits <CommandLoop>'s numbered-line path: reading the number, tokenizing, and removing an existing line of that
;; number.
;; Parameters: source = the two-byte scratch pointer used for the move
.macro DeleteOldLine source

;; Finds the numbered input line and removes its old version when present, by moving the rest of the program down.
;;
;; No matching line leaves <SourceStart> at the insertion position.
;; See: <ReadLineNumber>, <Tokenize>, <FindLine>
;; Also: MAIN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
EditLine:
    jsr ReadLineNumber
    jsr Tokenize
    sty Counter
    jsr FindLine
    bcc InsertLine
    ldy #ProgramLine::LINK + 1
    lda (SourceStart),y
    sta source+1
    lda VariablesStart
    sta source
    lda SourceStart+1
    sta Pointer2+1
    lda SourceStart
    dey
    sbc (SourceStart),y
    clc
    adc VariablesStart
    sta VariablesStart
    sta Pointer2
    lda VariablesStart+1
    adc #$FF
    sta VariablesStart+1
    sbc SourceStart+1
    tax
    sec
    lda SourceStart
    sbc VariablesStart
    tay
    bcs SetMoveSource
    inx
    dec Pointer2+1

;; Both borrow paths join here to add the low offset into the move's source pointer.
;; Also: QDECT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetMoveSource:
    clc
    adc source
    bcc MoveDown
    dec source+1
    clc

;; Copies a page at a time, X pages, from the source to <Pointer2>, closing the old line's gap.
;; Also: MLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MoveDown:
    lda (source),y
    sta (Pointer2),y
    iny
    bne MoveDown
    inc source+1
    inc Pointer2+1
    dex
    bne MoveDown
.endmacro

;; Emits <LinkProgram>'s scan of one line and the store of its link, which goes back to <LinkProgram>'s `NextLine`.
;; Parameters: addHighToY = 1 to add the old high byte to zero in Y instead of adding zero to A
.macro LinkLine addHighToY
    .assert addHighToY = 0 || addHighToY = 1, "addHighToY is 0 or 1."

    ldy #.sizeof(ProgramLine)        ; Y at the text: the scan reads from the byte after it

;; Steps Y to the line's zero, then stores the next line's address, just past it, as the line's link.
;; Also: CZLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ScanLine:
    iny
    lda (Pointer1),y
    bne ScanLine
    iny
    tya
    adc Pointer1
    tax
    ldy #$00
    sta (Pointer1),y
    .if addHighToY
        tya
        adc Pointer1+1
    .else
        lda Pointer1+1
        adc #$00
    .endif
    iny
    sta (Pointer1),y
    stx Pointer1
    sta Pointer1+1
    bcc NextLine
.endmacro

;; Emits <Tokenize>'s token store and its copies of literal text, which go back to <Tokenize>'s `NextCharacter` and end
;; at its `Finish`.
;; Parameters: inputBase = indexed input buffer base; foldCase = 1 to call the platform's case folder
.macro TokenStore inputBase, foldCase
    .assert foldCase = 0 || foldCase = 1, "foldCase is 0 or 1."

;; Reloads Y from <TokenizePointer> and stores the token in A; the keyword matcher's exit.
;; Also: GETBPT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreToken:
    ldy TokenizePointer

;; Stores A at the output position and ends at a zero; after a colon or `DATA` sets <TokenizeState>, and after `REM`
;; copies the rest of the line.
;; Also: STUFFH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreByte:
    inx
    iny
    sta BUF-5,y
    lda BUF-5,y
    beq Finish
    sec
    sbc #':'
    beq SetTokenizeState
    cmp #(TOKEN_DATA-':')
    bne CheckRem

;; Stores the colon's (0) or `DATA`'s (nonzero) difference in <TokenizeState>.
;; Also: COLIS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetTokenizeState:
    sta TokenizeState

;; Not `REM`: goes back to the keyword loop; `REM`: clears <EndDelimiter> and copies the rest of the line.
;; Also: NODATT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckRem:
    sec
    sbc #(TOKEN_REM-':')
    bne NextCharacter
    sta EndDelimiter

;; Reads the next input character, or folds its case, and stops at a zero or <EndDelimiter>.
;; Also: STR1 (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79)
CopyLiteral:
    .if foldCase
        jsr UPCASE
    .else
        lda inputBase,x
    .endif
    beq StoreByte
    cmp EndDelimiter
    beq StoreByte

;; Stores the literal character and continues copying; the vendor's tokenizer enters here at a quote.
;; Also: STRNG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreLiteral:
    iny
    sta BUF-5,y
    inx
    bne CopyLiteral
.endmacro
