; retrocore: style=strict
; APPLESOFT: CASSETTE, INTERPRETER AND DISPLAY HELPERS ($F775-$F7FF)
;
; Shape loading and array transfer use each model's cassette support: the enhanced IIe calls the AppleSoft cassette
; code in its internal slot 5 ROM, and the II Plus and IIe have their own copies here. The enhanced IIe's space
; instead holds its uppercase tokenizing and 80-column PRINT helpers. The shared array lookup and HTAB finish the
; ROM. InterpreterEnd follows the image, at the Monitor's $F800. This module follows AppleSoft.HighResolution.asm.
;
; The two builds' code shares only a few instructions at the same addresses, so each build's is written whole.

.if ENHNCD
; The enhanced IIe: cassette through the internal slot 5 ROM, and the tokenizer's, lister's and PRINT's helpers

;; The 40-column limit <CompareCommaColumn> compares the column with: 40 less 7.
COMMA_LIMIT_40 = 33

;; The 80-column limit <CompareCommaColumn> compares the column with: 80 less 7.
COMMA_LIMIT_80 = 73

.scope Statements continued

;; `SHLOAD`: sets carry, which selects the shape-table load, and skips <Statements::CallAppleSoftCassette>'s `clc`.
;; Also: SHLOAD (ASTIL)
.proc ShLoad
    sec
    .byte $90                       ; BCC: skips CallAppleSoftCassette's CLC, since carry is set
    ; Falls into CallAppleSoftCassette, past its clc.
.endproc

;; Calls the internal slot 5 ROM's AppleSoft cassette code, with the slot ROMs switched out around it; carry selects
;; the shape-table load (set) or setting the cassette range to an array's data (clear).
;;
;; The OUT OF MEMORY branch is reached only if the ROM returns with carry set. Where a shape table does not fit, the
;; ROM returns with a byte of the start still on the stack, so its return goes astray before the carry test: AppleSoft
;; reports no error, and the slot ROMs stay switched out.
;; Also: CALLC5 (UNKN)
.proc CallAppleSoftCassette
    clc
    sta InternalCxRomOn
    jsr AppleSoftCassette
    sta InternalCxRomOff
    bcs ToOutOfMemory
    rts

;; Jumps on to <ReportOutOfMemory>.
;; Also: CALLC1 (UNKN)
ToOutOfMemory:
    jmp ReportOutOfMemory
.endproc

.endscope

;; Reads the input character after the current one, uppercased, for the tokenizer's `AT` check; with bit 7 set it
;; falls into <UppercaseInput> instead, which returns the current one. That case is likely unreachable.
;; In: X = the current character's offset in <InputBuffer>
;; Also: UPNXT (UNKN)
.proc UppercaseNextCharacter
    lda InputBuffer+1,x
    bpl UppercaseCharacter
    ; Falls into UppercaseInput.
.endproc

;; Returns the input character, uppercased unless the tokenizer is copying `REM` text (<EndDelimiter> zero), a quoted
;; string or a `DATA` field.
;; In: X = the character's offset in <InputBuffer>
;; Also: UPCASE (UNKN)
.proc UppercaseInput
    lda EndDelimiter
    beq ReadBufferCharacter
    cmp #'"'
    beq ReadBufferCharacter
    lda TokenizeState
    cmp #<(TOKEN_DATA-':')
    beq ReadBufferCharacter
    ; Falls into UppercaseBufferCharacter.
.endproc

;; Loads the input character and falls into <UppercaseCharacter>.
;; In: X = the character's offset in <InputBuffer>
;; Also: UPBUF (UNKN)
.proc UppercaseBufferCharacter
    lda InputBuffer,x
    ; Falls into UppercaseCharacter.
.endproc

;; Clears bits 5 and 7 of A when it is `a` or above, keeping the flags of the load before it: it uppercases a
;; lowercase letter, also folds $7B-$7F to $5B-$5F, and clears bit 7 of any character from $80 up.
;; In: A = the character
;; Out: A = the character, uppercased
;; Also: UPBUF1 (UNKN)
.proc UppercaseCharacter
    php
    cmp #'a'
    bcc RestoreFlags
    and #$5F                        ; clears bits 5 and 7

;; Restores the flags and returns.
;; Also: UPBUF4 (UNKN)
RestoreFlags:
    plp
    rts
.endproc

;; Loads the input character unchanged and returns.
;; In: X = the character's offset in <InputBuffer>
;; Also: UPBUF5 (UNKN)
.proc ReadBufferCharacter
    lda InputBuffer,x
    rts
.endproc

;; Prints a space, then the line number in A and X through <Float::PrintDecimalAX>; the lister calls it.
;; Also: SPCLIN (UNKN)
.proc PrintSpaceAndLineNumber
    pha
    lda #' '
    jsr PrintCharacter
    pla
    jmp Float::PrintDecimalAX
.endproc

;; Compares the output column with the last comma column: <TerminalPosition> with <COMMA_LIMIT_40>, or, with 80 columns
;; (<Columns80State>), <EightyColumns::CursorColumn> with <COMMA_LIMIT_80>. <PrintComma> uses only its negative flag,
;; and compares A with <COMMA_NEWLINE_COLUMN> itself, so the carry has no effect on PRINT.
;; Out: A = the column; carry = set at or past the limit; negative = with 80 columns, set below the limit, and with
;;   40 columns clear (from <Columns80State>)
;; Also: CHKCOL (UNKN)
.proc CompareCommaColumn
    lda TerminalPosition
    cmp #COMMA_LIMIT_40
    bit Columns80State
    bpl Done
    lda EightyColumns::CursorColumn
    cmp #COMMA_LIMIT_80

;; Returns.
;; Also: CHKCO1 (UNKN)
Done:
    rts
.endproc

;; Returns X less the output column: <TerminalPosition>, subtracted with carry set, or, with 80 columns
;; (<Columns80State>), <EightyColumns::CursorColumn>, subtracted with the caller's carry.
;; In: X = the target column
;; Out: A = X less the column; carry = set where there is no borrow
;; Entry:
;;   SetPosition = stores A in <TerminalPosition>, then returns X less it; <Statements::HTab> calls it
;;   Done = returns; <Statements::HTab> branches here
;; Also: TRMSET (UNKN)
.proc DistanceToColumn
    txa
    bit Columns80State
    bmi UseFirmwareColumn
    .byte $2C                       ; BIT absolute skips SetPosition's STA

;; Stores A in <TerminalPosition>, then returns X less it.
;; Also: TRMSE1 (UNKN)
SetPosition:
    sta TerminalPosition
    sec
    txa
    sbc TerminalPosition

;; Returns.
;; Also: TRMSE2 (UNKN)
Done:
    rts

;; Subtracts <EightyColumns::CursorColumn> with the caller's carry.
;; Also: TRMSE3 (UNKN)
UseFirmwareColumn:
    sbc EightyColumns::CursorColumn
    rts
.endproc

    .byte $00, $00, $00, $00        ; unused

.else
; The II Plus and IIe: their own cassette shape loading and array range

.scope Statements continued

;; `SHLOAD`: reads a shape table's length from cassette into <LineNumber>, puts the table just below <MemoryTop>,
;; lowering it and <StringsBottom>, and reads the table there, pointing <ShapeTable> at it. Its fit is checked on the
;; high bytes only.
;; Errors: OUT OF MEMORY where the table's first page is not above <ArraysEnd>'s
;; Also: SHLOAD (ASTIL)
.proc ShLoad
    lda #0
    sta Address1High
    sta Address2High
    ldy #LineNumber
    sty Address1
    iny
    sty Address2
    jsr ReadCassette
    clc
    lda MemoryTop
    tax
    dex
    stx Address2
    sbc LineNumber
    pha
    lda MemoryTop+1
    tay
    inx
    bne StoreEnd
    dey

;; Stores the table's last address high byte in <Address2High> and checks that its first page is above <ArraysEnd>'s.
;; Also: SHLOD1 (UNKN)
StoreEnd:
    sty Address2High
    sbc LineNumber+1
    cmp ArraysEnd+1
    bcc ToOutOfMemory
    bne SetShapeTable

;; Jumps on to <ReportOutOfMemory>.
;; Also: SHLOD2 (UNKN)
ToOutOfMemory:
    jmp ReportOutOfMemory

;; Lowers <MemoryTop> and <StringsBottom> to the table's start, points <ShapeTable> and A1 there, and reads the
;; table, entering the Monitor's <ReadCassette> past its edge search and delay count with a shorter delay.
;; Also: SHLOD3 (UNKN)
SetShapeTable:
    sta MemoryTop+1
    sta StringsBottom+1
    sta Address1High
    sta ShapeTable+1
    pla
    sta ShapeTable
    sta MemoryTop
    sta StringsBottom
    sta Address1
    jsr Cassette::ReadBit
    lda #3                          ; WriteHeader's delay count
    jmp ReadCassette+5              ; ReadCassette at its jsr WriteHeader
.endproc

;; Points the Monitor's cassette range at an array's data: A1 at its first element, from the header at <SourceStart>,
;; and A2 at its last byte, <SourceStart> plus the length less one in <LineNumber>.
;; Also: SETA2 (UNKN)
.proc SetArrayBlock
    clc
    lda SourceStart
    adc LineNumber
    sta Address2
    lda SourceStart+1
    adc LineNumber+1
    sta Address2High
    ldy #ArrayHeader::DIMENSIONS
    lda (SourceStart),y
    jsr Variables::ElementsStart::FromCount
    lda DestinationEnd
    sta Address1
    lda DestinationEnd+1
    sta Address1High
    rts
.endproc

.endscope

.endif

; Array lookup and horizontal tab

.scope Statements continued

;; Finds the array named in the text, with <SubscriptMode> nonzero for the existing-array lookup, and points the
;; cassette range at its length through <SetCassetteLengthRange>.
;; Out: SourceStart = the array's header
;; Also: GETARY (UNKN), GETARYPT (ASTIL)
.proc FindCassetteArray
    lda #$40                        ; nonzero: an existing array, with no subscripts
    sta SubscriptMode
    jsr FindVariable
    lda #0
    sta SubscriptMode
    jmp SetCassetteLengthRange
.endproc

.if ENHNCD
;; `HTAB`: reads a one-based column and sets <TerminalPosition>, printing a return for each line width it passes;
;; the width is the wider of 40 and <WindowWidth>.
;; Also: HTAB (UNKN)
.proc HTab
    jsr EvaluateByte
    dex

;; Starts a line: picks the width, the wider of 40 and <WindowWidth>.
;; Also: HTAB1 (UNKN)
NextLine:
    lda #LINE_LENGTH
    cmp WindowWidth
    bcs CompareWidth
    lda WindowWidth

;; Sets <TerminalPosition> to the column if it fits; otherwise subtracts the width and prints a return.
;; Also: HTAB12 (UNKN)
CompareWidth:
    jsr DistanceToColumn::SetPosition
    stx TerminalPosition
    bcc DistanceToColumn::Done
    tax
    jsr PrintNewline
    bne NextLine
.endproc
.else
;; `HTAB`: reads a one-based column and sets <TerminalPosition>, printing a return for each 40 columns it passes.
;; Also: HTAB (UNKN)
.proc HTab
    jsr EvaluateByte
    dex
    txa

;; Starts a line: subtracts 40 and prints a return while the column is 40 or more.
;; Also: HTAB11 (UNKN)
NextLine:
    cmp #LINE_LENGTH
    bcc SetColumn
    sbc #LINE_LENGTH
    pha
    jsr PrintNewline
    pla
    jmp NextLine

;; Stores the column in <TerminalPosition>.
;; Also: HTAB13 (UNKN)
SetColumn:
    sta TerminalPosition
    rts
.endproc

    ; The ROM's last three bytes, unused; the last differs on the II Plus.
    .byte $CB, $D2
.if APLPLS
    .byte $D7
.else
    .byte $78
.endif
.endif

.endscope

;; The address after the AppleSoft image, $F800, where the Monitor's ROM begins. Its 100 reserved bytes are
;; Microsoft's temporary-stack block; here they cover the Monitor's code from $F800 to $F863, not BASIC's workspace.
;; Also: LASTWR (M6502)
InterpreterEnd:
    .res 100
