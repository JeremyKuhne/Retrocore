; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: DATA, REM, IF AND ON
;
; The three macros are emitted consecutively before the line-number parser. The scanner can retain an earlier
; quote-branch ordering and an optional stack-unwind entry used by a platform's POP statement.

;; Emits the <Statements::Data> entry and its scanners.
;; Parameters: quoteFirst = 1 to branch on a quote first, 0 to branch on a non-quote first;
;;   popExit = 1 to include the entry that removes three stack bytes for POP
.macro StatementScan quoteFirst, popExit
    .assert quoteFirst = 0 || quoteFirst = 1, "quoteFirst must be 0 or 1."
    .assert popExit = 0 || popExit = 1, "popExit must be 0 or 1."

    .scope Statements continued

    ;; Skips DATA fields up to an unquoted colon or end of line.
    ;; See: <FindStatementEnd>, <READ>
    ;; Also: DATA (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Data
    jsr FindStatementEnd
    .endproc
    .endscope

    ;; Advances <TextPointer> by Y, to the terminator found by <FindStatementEnd> or <FindLineEnd>.
    ;; In: Y = offset of the terminator
    ;; Entry:
    ;;   Done = The rts; <FindLineEnd>'s terminator branches return through it
    ;; Also: ADDON (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AdvanceTextPointer
    tya
    clc
    adc TextPointer
    sta TextPointer
    bcc Done
    inc TextPointer+1
;; The rts; <FindLineEnd>'s terminator branches return through it.
;; Also: REMRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Scans from <TextPointer> to an unquoted colon or a zero byte.
    ;; Out: Y = terminator offset
    ;; See: <Statements::Data>, <DATLOP>, <FindLineEnd>
    ;; Also: DATAN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FindStatementEnd
    ldx #':'
    .byte $2C                   ; BIT absolute skips <FindLineEnd>'s LDX
    .endproc

    ;; Scans from <TextPointer> to the end-of-line zero.
    ;; Out: Y = terminator offset
    ;; Also: REMN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FindLineEnd
    ldx #$00
    stx Delimiter
    ldy #$00
    sty EndDelimiter
;; Exchanges Delimiter and <EndDelimiter> (on entry and at each quote).
;; Also: EXCHQT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SwapDelimiters:
    lda EndDelimiter
    ldx Delimiter
    sta Delimiter
    stx EndDelimiter
;; Zero or <EndDelimiter> ends; a quote swaps.
;; Also: REMER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    lda (TextPointer),y
    beq AdvanceTextPointer::Done
    cmp EndDelimiter
    beq AdvanceTextPointer::Done
    iny
    cmp #'"'
    .if quoteFirst
        beq SwapDelimiters
        bne NextCharacter
    .else
        bne NextCharacter
        beq SwapDelimiters
    .endif
    .endproc

    .if popExit
        .scope Statements continued

        ;; AppleSoft: pulls the three GOSUB frame bytes left and returns, for POP.
        ;; Also: REMER1 (UNKN)
        .proc PopFinish
        pla
        pla
        pla
        rts
        .endproc
        .endscope
    .endif

.endmacro

;; Emits the <Statements::If> and <Statements::Rem> statement entries.
.macro ConditionalStatements

    .scope Statements continued

    ;; Evaluates the condition; false skips the line, true executes the THEN statement or jumps to a line.
    ;; See: <Statements::Rem>, <Statements::GoTo>, <GONE3>
    ;; Also: IF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc If
    jsr FRMEVL
    jsr GetCurrentCharacter
    cmp #TOKEN_GOTO
    beq Test
    lda #TOKEN_THEN
    jsr SYNCHR
;; <FacExponent> nonzero: true.
;; Also: OKGOTO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Test:
    lda FacExponent
    bne IfTrue
    .endproc

    ;; Skips the rest of the line.
    ;; Also: REM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Rem
    jsr FindLineEnd
    beq AdvanceTextPointer
    .endproc
    ;; A digit after THEN/GOTO: <Statements::GoTo>; else the statement through GONE3.
    ;; Also: DOCOND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc IfTrue
    jsr GetCurrentCharacter
    bcs ToExecuteStatement
    jmp GoTo
;; Jmp GONE3.
;; Also: DOCO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToExecuteStatement:
    jmp GONE3
    .endproc
    .endscope

.endmacro

;; Emits the <Statements::On> statement entry.
.macro OnStatement

    .scope Statements continued

    ;; Selects a one-based entry in a <Statements::GoTo> or <Statements::GoSub> line-number list.
    ;;
    ;; Proceeds past the list when the selector exceeds the number of entries.
    ;; Entry:
    ;;   RequireGoto = Not GOTO: syntax error; <ReadLineNumber>'s overflow branch also lands here
    ;;   Done = The rts; <ReadLineNumber> exits through it at a non-digit
    ;; Also: ONGOTO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc On
    jsr GETBYT
    pha
    cmp #TOKEN_GOSUB
    beq NextEntry
;; Not GOTO: syntax error; <ReadLineNumber>'s overflow branch also lands here.
;; Also: SNERR3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RequireGoto:
    cmp #TOKEN_GOTO
    bne Return::ToSyntaxError
;; Decrements the selector; zero: dispatches the GOTO/GOSUB.
;; Also: ONGLOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextEntry:
    dec FacMantissa4
    bne SkipEntry
    pla
    jmp GONE2
;; Reads a line number; a comma continues.
;; Also: ONGLP1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipEntry:
    jsr GetNextCharacter
    jsr ReadLineNumber
    cmp #','
    beq NextEntry
    pla
;; The rts; <ReadLineNumber> exits through it at a non-digit.
;; Also: ONGRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

.endmacro
