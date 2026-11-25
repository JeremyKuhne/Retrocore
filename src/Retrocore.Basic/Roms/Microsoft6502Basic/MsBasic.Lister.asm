; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: PROGRAM LISTING
;;
;; These macros emit LIST's argument parser, linked-line walker and token expansion in that order. The
;; platform supplies the output and continuation entries and chooses the independent listing behaviors.

.include "MsBasic.Families.asm"

;; Emits the <Statements::List> argument parser.
;; Parameters: commaRange = 1 to accept a comma as well as a minus token between bounds;
;;   secondBoundReturn = return entry used when characters follow the upper bound
.macro ListRange commaRange, secondBoundReturn
    .assert commaRange = 0 || commaRange = 1, "commaRange must be 0 or 1."

    .scope Statements continued

    ;; Lists the selected stored lines, or all lines when no bound is supplied.
    ;;
    ;; A nonzero single number selects that line; a minus token introduces an upper bound. When selected, a
    ;; comma is also accepted. A zero upper bound, including an omitted one, becomes $FFFF. A valid command
    ;; discards the statement dispatcher's return address before listing; trailing text after a bound returns to
    ;; the dispatcher. A second bound with no digits counts as omitted, since <ReadLineNumber> then returns with zero
    ;; set, so `LIST 10-X` lists from line 10 to the end and the text after the minus is ignored.
    ;; In: A = current character, carry = clear for a digit, zero = set for a null or colon
    ;; See: <ReadLineNumber>, <FindLine>, <Statements::List::NextLine>
    ;; Also: LIST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc List
    bcc ReadFirstBound
    beq ReadFirstBound
    cmp #TOKEN_MINUS
    .if commaRange
        beq ReadFirstBound
        cmp #','
    .endif
    bne ResetStack::Done
;; <ReadLineNumber>, <FindLine>, then checks for the end, minus (or comma).
;; Also: GOLST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReadFirstBound:
    jsr ReadLineNumber
    jsr FindLine
    jsr GetCurrentCharacter
    beq StartListing
    cmp #TOKEN_MINUS
    .if commaRange
        beq ReadSecondBound
        cmp #','
    .endif
    bne FindLine::Done
    .if commaRange
;; AppleSoft: after minus or comma, reads the upper bound.
ReadSecondBound:
    .endif
    jsr GetNextCharacter
    jsr ReadLineNumber
    bne secondBoundReturn
;; Drops the statement loop's return; a zero upper bound becomes $FFFF; falls into <Statements::List::NextLine>.
;; Also: LSTEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StartListing:
    pla
    pla
    lda LineNumber
    ora LineNumber+1
    bne NextLine
    lda #$FF
    sta LineNumber
    sta LineNumber+1
.endmacro

;; Emits the line walker and its normal listing exit.
;; Parameters: trackQuotes = 1 to reset and complement <TokenizeState> around quoted text;
;;   guardOffset = 1 to stop if a malformed line's byte offset wraps;
;;   columnMode = 0 for no lister wrap, 1 for the fixed column check, 2 for the width-aware helper;
;;   linePrinter = entry printing a line number in A (high) and X (low);
;;   finalCr = 1 to output a carriage return before resuming;
;;   resume = entry reached at the end of the listing
.macro ListLines trackQuotes, guardOffset, columnMode, linePrinter, finalCr, resume
    .assert trackQuotes = 0 || trackQuotes = 1, "trackQuotes must be 0 or 1."
    .assert guardOffset = 0 || guardOffset = 1, "guardOffset must be 0 or 1."
    .assert columnMode >= 0 && columnMode <= 2, "columnMode must be 0, 1 or 2."
    .assert finalCr = 0 || finalCr = 1, "finalCr must be 0 or 1."

;; Displays linked lines through the inclusive upper bound.
;;
;; The stop check and newline precede the upper-bound comparison. A zero high byte in the next link
;; ends the listing. With `trackQuotes`, each line starts with <TokenizeState> = 1, complemented for each quote.
;; In: SourceStart = link field of the first line, LineNumber = inclusive upper bound
;; See: <CheckStop>, <Statements::List::CheckToken>
;; Also: LIST4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextLine:
    ldy #$01
    .if trackQuotes
        sty TokenizeState
    .endif
    lda (SourceStart),y
    beq Finish
    jsr CheckStop
    jsr PrintNewline
    iny
    lda (SourceStart),y
    tax
    iny
    lda (SourceStart),y
    cmp LineNumber+1
    bne CheckPastEnd
    cpx LineNumber
    beq ListLine
;; Carry set (line above the bound) finishes.
;; Also: TSTDUN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckPastEnd:
    bcs Finish
;; Saves the offset in <ListOffset>, prints the line number, then a space.
;; Also: TYPLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ListLine:
    sty ListOffset
    jsr linePrinter
    lda #' '
;; Reloads the line offset, clears bit 7 of A, falls into <Statements::List::ListCharacter>.
;; Also: PRIT4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ResumeLine:
    ldy ListOffset
    and #$7F
;; Outputs A; with columnMode wraps at the column and indents to 5.
;; Also: PLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ListCharacter:
    jsr PrintCharacter
    .if columnMode
        .if trackQuotes
            pha
        .endif
        .if columnMode = 2
            jsr CHKCOL
            nop
        .else
            lda TerminalPosition
            cmp #$21
        .endif
        .if trackQuotes
            bcc CheckQuote
        .else
            bcc NextByte
        .endif
        jsr PrintNewline
        lda #$05
        sta TerminalPosition
        .if trackQuotes
;; Restores the character saved around the wrap check, then the quote test.
CheckQuote:
            pla
        .endif
    .endif
    .if trackQuotes
        cmp #'"'
        bne NextByte
        lda TokenizeState
        eor #$FF
        sta TokenizeState
    .endif
;; Next byte: nonzero to <Statements::List::CheckToken>; zero follows the link to the next line.
;; Also: PLOOP1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextByte:
    iny
    .if guardOffset
        beq Finish
    .endif
    lda (SourceStart),y
    bne CheckToken
    tay
    lda (SourceStart),y
    tax
    iny
    lda (SourceStart),y
    stx SourceStart
    sta SourceStart+1
    bne NextLine
;; Optional carriage return, then jmp to the resume entry.
;; Also: GRODY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Finish:
    .if finalCr
        lda #$0D
        jsr PrintCharacter
    .endif
    jmp resume
.endmacro

;; Emits the page-carrying table reader used by the <Fac>-based token walker.
.macro ListNextTableByte
    .assert FacMantissa1 = Fac+1, "The listing table pointer must occupy FAC and FACHO."

;; Advances the table offset, carrying into its pointer on wrap, and reads the byte.
;; In: Fac = two-byte table pointer, Y = offset before the next byte
;; Out: A = table byte, Y = advanced offset, FacMantissa1 = incremented when Y wraps,
;;   zero = set for a zero byte, negative = bit 7 of the byte
;; Keeps: X, carry
NextTableByte:
    iny
    bne ReadTableByte
    inc FacMantissa1
;; Reads (<Fac>),y and returns.
ReadTableByte:
    lda (Fac),y
    rts
.endmacro

;; Emits character handling and reserved-word expansion after <ListLines>.
;;
;; Mode 0 indexes <ReservedWords> with an eight-bit Y; mode 1 walks it through <Pointer1>, with a special first-token
;; path and a signed X countdown; mode 2 uses <ListNextTableByte> and the pointer in <Fac>. The line walker
;; and token expansion must use the same quote-tracking choice.
;; Parameters: tableMode = 0 for direct indexed, 1 for <Pointer1> indirect, 2 for <Fac> indirect with page carry;
;;   trackQuotes = 1 to print high-bit characters inside quotes literally;
;;   literalPi = 1 to print the PI character literally;
;;   spaceWords = 1 to output spaces before and after each expanded word
.macro ListTokens tableMode, trackQuotes, literalPi, spaceWords
    .assert tableMode >= 0 && tableMode <= 2, "tableMode must be 0, 1 or 2."
    .assert trackQuotes = 0 || trackQuotes = 1, "trackQuotes must be 0 or 1."
    .assert literalPi = 0 || literalPi = 1, "literalPi must be 0 or 1."
    .assert spaceWords = 0 || spaceWords = 1, "spaceWords must be 0 or 1."

;; Prints a stored character or expands a token using <ReservedWords>.
;;
;; The high bit marks the last byte of each reserved word. In table mode 0 Y wraps after 256 table bytes;
;; the two indirect modes can walk farther. Tokens are not checked against the end of the table.
;; In: A = nonzero stored byte, Y = offset in the current line, negative = bit 7 of A
;; See: <Statements::List::NextLine>, <PrintCharacter>
;; Also: QPLOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckToken:
    bpl ListCharacter
    .if literalPi
        cmp #PI
        beq ListCharacter
    .endif
    .if trackQuotes
        bit TokenizeState
        bmi ListCharacter
    .endif
    .if tableMode = 1
        tax
        sty ListOffset
        ldy #>ReservedWords
        sty Pointer1+1
        ldy #<ReservedWords
        sty Pointer1
        ldy #$00
        asl a
        beq ListFirstWord
    .else
        sec
        sbc #$7F
        tax
        sty ListOffset
        .if tableMode = 2
            ldy #<(ReservedWords-256)
            sty Fac
            ldy #>(ReservedWords-256)
            sty FacMantissa1
        .endif
        ldy #$FF
    .endif
;; Dex per keyword; reaching the token's count prints that word.
;; Also: RESRCH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FindWord:
    dex
    .if tableMode = 1
        bpl ListWord
    .else
        beq ListWord
    .endif
;; Reads table bytes until one with bit 7 set (a word's last byte).
;; Also: RESCR1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipWord:
    .if tableMode = 1
        inc Pointer1
        bne ReadWordByte
        inc Pointer1+1
;; BASIC 4: reads (<Pointer1>),y after advancing the pointer.
ReadWordByte:
        lda (Pointer1),y
    .elseif tableMode = 2
        jsr NextTableByte
    .else
        iny
        lda ReservedWords,y
    .endif
    bpl SkipWord
    bmi FindWord
;; Prints the keyword's bytes up to the one with bit 7 set.
;; Also: PRIT3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ListWord:
    .if tableMode = 1
        iny
;; BASIC 4: the first token ($80) skips the search.
ListFirstWord:
    .endif
    .if spaceWords
        lda #' '
        jsr PrintCharacter
    .endif
    .if spaceWords || tableMode = 2
;; AppleSoft: reads and prints the next keyword byte.
ListWordCharacter:
    .endif
    .if tableMode = 1
        lda (Pointer1),y
    .elseif tableMode = 2
        jsr NextTableByte
    .else
        iny
        lda ReservedWords,y
    .endif
    .if spaceWords
        bmi ListLastCharacter
        jsr PrintCharacter
        .if tableMode = 1
            beq ListLastCharacter
            iny
            jmp ListWordCharacter
        .else
            bne ListWordCharacter
        .endif
;; AppleSoft: prints the last keyword byte and a space, back to <Statements::List::ResumeLine>.
ListLastCharacter:
        jsr PrintCharacter
        lda #' '
        bne ResumeLine
    .else
        bmi ResumeLine
        jsr PrintCharacter
        .if tableMode = 2
            bne ListWordCharacter
        .else
            bne ListWord
        .endif
    .endif
    .endproc
    .endscope

.endmacro
