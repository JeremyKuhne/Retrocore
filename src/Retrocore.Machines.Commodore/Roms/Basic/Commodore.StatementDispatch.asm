; retrocore: style=strict
; COMMODORE BASIC: NEXT STATEMENT AND TOKEN DISPATCH

.include "../../Microsoft6502Basic/MsBasic.Families.asm"

;; Emits the next-statement fetcher: <NextStatement> and <ExecuteStatement>.
;; Parameters: bufferPage = zero for a page-zero direct buffer, or the nonzero buffer page,
;;   spareByte = 1 to retain the later ROM's NOP before the direct-mode branch,
;;   earlySeparators = 1 to check separators before the line link,
;;   shortEnd = 1 to branch directly to <Statements::StopOrEnd::Finish>,
;;   fetchToken = character-reader entry, or the revised BASIC 4 PI-checking patch
.macro CommodoreStatementFetch bufferPage, spareByte, earlySeparators, shortEnd, fetchToken
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert spareByte = 0 || spareByte = 1, "spareByte is 0 or 1."
    .assert earlySeparators = 0 || earlySeparators = 1, "earlySeparators is 0 or 1."
    .assert shortEnd = 0 || shortEnd = 1, "shortEnd is 0 or 1."

    ;; Runs the next statement or advances to the next linked line, checking for STOP first.
    ;;
    ;; The text position is saved in <StoppedText>, for INPUT's retry and CONT, when execution is not in the direct
    ;; buffer's page. A zero line link ends the program. Where `earlySeparators` is 1 (BASIC 1), it checks for a colon
    ;; before reading the link, and a byte that is neither a colon nor a zero is a syntax error here.
    ;; In: TextPointer = the statement separator or line terminator
    ;; See: <ExecuteStatement>, <Statements::StopOrEnd::Finish>
    ;; Also: NEWSTT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc NextStatement
    jsr CheckStop
    lda TextPointer
    ldy TextPointer+1
    .if bufferPage
        cpy #bufferPage
    .endif
    .if spareByte
        nop
    .endif
    beq TestSeparator
    sta StoppedText
    sty StoppedText+1
    .if bufferPage

;; Reads the byte at <TextPointer>: a zero reads the next line, and anything else is checked as a separator.
;; Also: DIRCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestSeparator:
    .endif
    ldy #$00
    .if .not bufferPage

;; Reads the byte at <TextPointer>: a zero reads the next line, and anything else is checked as a separator.
;; Also: DIRCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestSeparator:
    .endif
    lda (TextPointer),y
    .if earlySeparators
        beq NextLine
        cmp #':'
        beq ExecuteStatement

;; Jumps on to <SyntaxError>; <DispatchStatement> branches here too.
;; Also: SNERR1 (M6502, HV1, HV1R)
ToSyntaxError:
        jmp SyntaxError

;; Reads the next line's link and number.
;; Also: NXTLIN (UNKN), CKEOL (HV1, HV1R)
NextLine:
    .else
        bne CheckStatementSeparator
    .endif
    ldy #$02                        ; the next line's link high byte, past the zero
    lda (TextPointer),y
    clc
    .if shortEnd
        beq Statements::StopOrEnd::Finish
    .else
        bne ReadLine
        jmp Statements::StopOrEnd::Finish

;; A line follows: reads its number and moves <TextPointer> to its text.
ReadLine:
    .endif
    iny
    lda (TextPointer),y
    sta CurrentLine
    iny
    lda (TextPointer),y
    sta CurrentLine+1
    tya
    adc TextPointer
    sta TextPointer
    bcc ExecuteStatement
    inc TextPointer+1
    ; Falls into ExecuteStatement.
    .endproc

    ;; Fetches a statement's first character, dispatches it with <DispatchStatement>, then continues at
    ;; <NextStatement>.
    ;; Also: GONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ExecuteStatement
    jsr fetchToken
    jsr DispatchStatement
    jmp NextStatement
    .endproc
.endmacro

;; Emits statement-token dispatch, <DispatchStatement>, and the GO or disk-command handling.
;; Parameters: earlyDispatch = 1 for the earlier carry and error paths,
;;   diskCommands = 1 to dispatch disk tokens after the GO gap
.macro CommodoreStatementDispatch earlyDispatch, diskCommands
    .assert earlyDispatch = 0 || earlyDispatch = 1, "earlyDispatch is 0 or 1."
    .assert diskCommands = 0 || diskCommands = 1, "diskCommands is 0 or 1."
    .assert earlyDispatch = 0 || diskCommands = 0, "Early dispatch has no disk-command gap."

    ;; Returns at the end of a statement; otherwise dispatches a statement token through <StatementTable>, and treats
    ;; anything else as <Statements::Let>.
    ;;
    ;; Where `diskCommands` is 1 (BASIC 4), the disk tokens after `GO` dispatch from the table's next entries.
    ;; In: A = statement token or first character, zero = set at the end of the statement, carry = set for a non-digit
    ;;   (where `earlyDispatch` is 1, BASIC 1, the routine sets carry itself)
    ;; Errors: SYNTAX for a non-statement reserved word
    ;; Entry:
    ;;   WithToken = subtracts <TOKEN_END> from A and dispatches; the shared `ON` code enters here
    ;; Also: GONE3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc DispatchStatement
    .if earlyDispatch
        beq Statements::Cont::Done
        sec
    .else
        beq Statements::Restore::Done
    .endif

;; Subtracts <TOKEN_END> from A and dispatches.
;; Also: GONE2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
WithToken:
    sbc #<TOKEN_END
    .if earlyDispatch
        bcs LookUp
        jmp Statements::Let

;; Checks the statement range and indexes <StatementTable>.
;; Also: GONE4 (UNKN)
LookUp:
        cmp #<(TOKEN_NEW-TOKEN_END+1)
        bcs NextStatement::ToSyntaxError
    .else
        bcc ToLet
        cmp #<(TOKEN_NEW-TOKEN_END+1)
        .if diskCommands
            bcc LookUp
            cmp #<(TOKEN_GO-TOKEN_END)
            bcc CheckStatementSeparator::ToSyntaxError
            sbc #<(TOKEN_GO-TOKEN_NEW-1)

;; Dispatches after mapping a disk token past the `GO` gap.
;; Also: GONE4 (HV4, HV4R, CBM4S79)
LookUp:
        .else
            bcs CheckGoStatement
        .endif
    .endif
    asl a
    tay
    lda StatementTable+1,y
    pha
    lda StatementTable,y
    pha
    jmp GetNextCharacter
    .if .not earlyDispatch

;; Jumps on to <Statements::Let>.
;; Also: GLET (M6502, CBM4S79, HV2, HV4, HV4R)
ToLet:
        jmp Statements::Let
    .endif
    .endproc

    .if .not earlyDispatch
        ;; Runs the next statement after a colon; anything else is a syntax error.
        ;; In: A = the nonzero byte at <TextPointer>
        ;; Entry:
        ;;   ToSyntaxError = jumps to <SyntaxError>; <DispatchStatement> branches here for a token beyond the statements
        ;; Also: MORSTS (M6502, CBM4S79, HV2, HV4, HV4R)
        .proc CheckStatementSeparator
        cmp #':'
        beq ExecuteStatement

;; Jumps on to <SyntaxError>.
;; Also: SNERR1 (M6502, CBM4S79, HV2, HV4, HV4R)
ToSyntaxError:
        jmp SyntaxError
        .endproc

        .if diskCommands
            .scope Statements continued

            ;; `GO`: requires `TO` and continues as <Statements::GoTo>, BASIC 4's table entry for `GO TO`.
            ;; Also: GO (CBM4S79, HV4, HV4R)
            .proc Go
            jsr GetCurrentCharacter
            lda #<TOKEN_TO
            jsr CheckCharacter
            jmp Statements::GoTo
            .endproc

            .endscope
        .else
            ;; BASIC 2's token past the statements: `GO` requires `TO` and continues as <Statements::GoTo>, and any
            ;; other token is a syntax error.
            ;; In: A = the token less <TOKEN_END>
            ;; Also: SNERRX (M6502, HV2)
            .proc CheckGoStatement
            cmp #<(TOKEN_GO-TOKEN_END)
            bne CheckStatementSeparator::ToSyntaxError
            jsr GetNextCharacter
            lda #<TOKEN_TO
            jsr CheckCharacter
            jmp Statements::GoTo
            .endproc
        .endif
    .endif
.endmacro
