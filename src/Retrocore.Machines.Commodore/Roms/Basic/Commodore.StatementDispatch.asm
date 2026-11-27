; retrocore: style=strict
; COMMODORE BASIC: NEXT STATEMENT AND TOKEN DISPATCH

.include "../../Microsoft6502Basic/MsBasic.Families.asm"
.include "Commodore.Switches.asm"

;; Emits the next-statement fetcher: <NextStatement> and <ExecuteStatement>.
;; The workspace's <INPUT_BUFFER_PAGE> is the direct buffer's page: zero for page zero.
;; Parameters: spareByte = 1 to retain the later ROM's NOP before the direct-mode branch,
;;   earlySeparators = 1 to check separators before the line link,
;;   shortEnd = 1 to branch directly to <Statements::StopOrEnd::Finish>,
;;   fetchToken = character-reader entry, or the revised BASIC 4 PI-checking patch
.macro CommodoreStatementFetch spareByte, earlySeparators, shortEnd, fetchToken
    .assert spareByte = 0 || spareByte = 1, "spareByte is 0 or 1."
    .assert earlySeparators = 0 || earlySeparators = 1, "earlySeparators is 0 or 1."
    .assert shortEnd = 0 || shortEnd = 1, "shortEnd is 0 or 1."

    ;; Runs the next statement or advances to the next linked line, checking for STOP first.
    ;;
    ;; The text position is saved in <StoppedText>, for INPUT's retry and CONT, when execution is not in the direct
    ;; buffer's page. A zero line link ends the program. Where `earlySeparators` is 1 (BASIC 1), it checks for a colon
    ;; before reading the link, and a byte that is neither a colon nor a zero is a syntax error here.
    ;; In: TextPointer = the statement separator or line terminator
    ;; Errors: SYNTAX for a byte that is neither a colon nor a zero, here where `earlySeparators` is 1 and otherwise
    ;;   through the separator check that follows the dispatcher
    ;; See: <ExecuteStatement>, <Statements::StopOrEnd::Finish>
    ;; Also: NEWSTT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc NextStatement
    jsr CheckStop
    lda TextPointer
    ldy TextPointer+1
    .if INPUT_BUFFER_PAGE
        cpy #INPUT_BUFFER_PAGE
    .endif
    .if spareByte
        nop
    .endif
    beq TestSeparator
    sta StoppedText
    sty StoppedText+1
    .if INPUT_BUFFER_PAGE

;; Reads the byte at <TextPointer>: a zero reads the next line, and anything else is checked as a separator.
;; Also: DIRCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TestSeparator:
    .endif
    ldy #$00
    .if .not INPUT_BUFFER_PAGE

;; Reads the byte at <TextPointer>: a zero reads the next line, and anything else is checked as a separator.
;; Also: DIRCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TestSeparator:
    .endif
    lda (TextPointer),y
    .if earlySeparators
        beq NextLine
        ; HV1 and HV1R call this compare MORSTS, the name CheckStatementSeparator has in the other builds.
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
;; Also: DIRCN1 (CBM4S79, HV2, HV4, HV4R, BV20)
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
    ;;
    ;; With <BASIC_RAM_VECTORS> (the VIC-20), it jumps through `StatementVector`, to its `Default` entry unless a
    ;; program has changed the vector.
    ;; Also: GONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc ExecuteStatement
    .if BASIC_RAM_VECTORS
        jmp (StatementVector)

;; The ROM's statement execution, where <StatementVector> points unless a program changes it.
;; Also: NGONE (BV20)
Default:
    .endif
    jsr fetchToken
    .if BASIC_RAM_VECTORS

;; Dispatches the statement; nothing branches here, and the label is kept for its old name.
;; Also: NGONE1 (BV20)
Dispatch:
    .endif
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

    ;; Returns at the end of a statement; otherwise dispatches a statement token through <StatementTable>. A
    ;; character below <TOKEN_END> is <Statements::Let>, and any other token is a syntax error, except BASIC 2's `GO`,
    ;; which goes on to <Statements::GoTo>.
    ;;
    ;; Where `diskCommands` is 1 (BASIC 4), the disk tokens after `GO` dispatch from the table's next entries.
    ;; In: A = statement token or first character, zero = set at the end of the statement, carry = set for a non-digit
    ;;   (where `earlyDispatch` is 1, BASIC 1, the routine sets carry itself)
    ;; Errors: SYNTAX for a non-statement reserved word, and where `diskCommands` and `earlyDispatch` are 0
    ;;   (BASIC 2) for `GO` without `TO`
    ;; Entry:
    ;;   WithToken = subtracts <TOKEN_END> from A and dispatches; <Statements::On> enters here
    ;; Also: GONE3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc DispatchStatement
    .if earlyDispatch
        beq Statements::Cont::Done
        sec
    .else
        beq Statements::Restore::Done
    .endif

;; Subtracts <TOKEN_END> from A and dispatches.
;; Also: GONE2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
WithToken:
    sbc #<TOKEN_END
    .if earlyDispatch
        bcs LookUp

;; Jumps on to <Statements::Let>.
;; Also: GLET (HV1, HV1R)
ToLet:
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
;; Also: GLET (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
ToLet:
        jmp Statements::Let
    .endif
    .endproc

    .if .not earlyDispatch
        ;; Runs the next statement after a colon; anything else is a syntax error.
        ;; In: A = the nonzero byte at <TextPointer>
        ;; Entry:
        ;;   ToSyntaxError = jumps to <SyntaxError>; for a token beyond the statements, <DispatchStatement> branches
        ;;     here where `diskCommands` is 1 (BASIC 4), and BASIC 2's `GO` check where it is 0
        ;; Errors: SYNTAX for any byte other than a colon
        ;; Also: MORSTS (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
        .proc CheckStatementSeparator
        cmp #':'
        beq ExecuteStatement

;; Jumps on to <SyntaxError>.
;; Also: SNERR1 (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
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
            ;; Also: SNERRX (M6502, HV2, BV20)
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
