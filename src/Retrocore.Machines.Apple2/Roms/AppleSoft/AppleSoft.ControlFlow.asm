; retrocore: style=strict
; APPLESOFT: STATEMENT DISPATCH AND CONTROL FLOW
;
; The statement dispatcher, FOR and GOSUB frames, program transfers and cassette commands. The FOR stack
; search and NEXT are in other modules; LET and PRINT follow in AppleSoft.Assignment.asm and AppleSoft.Print.asm.

.include "../Microsoft6502Basic/MsBasic.For.asm"
.include "../Microsoft6502Basic/MsBasic.ProgramTransfers.asm"
.include "../Microsoft6502Basic/MsBasic.StatementFlow.asm"

;; The ASCII code of Control-C, which <HandleBreak> compares A with for the shared STOP code.
CONTROL_C = $03

;; Control-C as the keyboard reads it, with bit 7 set.
KEYBOARD_CONTROL_C = CONTROL_C | $80

;; Saves the stack pointer in <StatementStack>, the level `ONERR` resumes at, and falls into <NextStatement>.
;;
;; It is the next-statement target AppleSoft's GOTO, NEXT, LIST and the run-only path of <Tokenize> pass, where the
;; PET's pass <NextStatement>.
;; Also: NXTCO1 (UNKN)
.proc NextStatementSavingStack
    tsx
    stx StatementStack
    ; Falls into NextStatement.
.endproc

;; Runs the next statement or advances to the next linked line, checking for Control-C first.
;;
;; Saves the current text position in <StoppedText>, for CONT, while running a program. Trace mode prints each line
;; number.
;; Entry:
;;   TraceLine = prints `#` and the line number when `TRACE` is on and a program is running, then falls into
;;     <ExecuteStatement>; <CommandLoop> jumps here for a direct statement and <CheckStatementSeparator> after a colon
;; See: <ExecuteStatement>, <CheckStop>, <Statements::Cont>
;; Also: NEWSTT (M6502)
.proc NextStatement
    jsr CheckStop
    lda TextPointer
    ldy TextPointer+1
    ldx CurrentLine+1
    inx
    beq TestSeparator
    sta StoppedText
    sty StoppedText+1

;; Reads the byte at <TextPointer>: a nonzero byte goes to <CheckStatementSeparator>, and a zero one reads the next
;; line's link and number.
;; Also: DIRCON (M6502)
TestSeparator:
    ldy #$00
    lda (TextPointer),y
    bne CheckStatementSeparator
    ldy #$02                        ; the next line's link high byte, past the zero
    lda (TextPointer),y
    clc
    beq ExecuteStatement::ToEndOfProgram
    iny
    lda (TextPointer),y
    sta CurrentLine
    iny
    lda (TextPointer),y
    sta CurrentLine+1
    tya
    adc TextPointer
    sta TextPointer
    bcc TraceLine
    inc TextPointer+1

;; Prints `#` and the line number when `TRACE` is on and a program is running, then falls into <ExecuteStatement>.
;; Also: TRCLIN (UNKN)
TraceLine:
    bit TraceMode
    bpl ExecuteStatement
    ldx CurrentLine+1
    inx
    beq ExecuteStatement
    lda #'#'
    jsr PrintCharacter
    ldx CurrentLine
    lda CurrentLine+1
    jsr Float::PrintDecimalAX
    jsr PrintSpace
    ; Falls into ExecuteStatement.
.endproc

;; Advances past the separator and dispatches a statement with <DispatchStatement>, then goes on to the next one.
;; Entry:
;;   ToEndOfProgram = goes on to <Statements::StopOrEnd::Finish>, the end of the program; <NextStatement> branches
;;     here, for range, at a zero link
;; See: <NextStatement>, <Statements::Let>
;; Also: GONE (M6502)
.proc ExecuteStatement
    jsr GetNextCharacter
    jsr DispatchStatement
    jmp NextStatementSavingStack

;; Goes on to <Statements::StopOrEnd::Finish>, the end of the program.
;; Also: GONE1 (UNKN)
ToEndOfProgram:
    beq Statements::StopOrEnd::Finish
.endproc

;; Returns at the end of a statement; otherwise dispatches a statement token through <StatementTable>, and anything
;; else is <Statements::Let>.
;; In: A = the statement's first character, zero = set at the end of the statement, carry = set unless it is a digit
;;   (as <GetNextCharacter> leaves it)
;; Entry:
;;   WithToken = subtracts <TOKEN_END> from A (carry set) and dispatches; the shared `ON` and IF code enters here with
;;     a token
;; Also: GONE3 (M6502)
.proc DispatchStatement
    beq Statements::Restore::Done

;; Subtracts <TOKEN_END> and dispatches; <GetNextCharacter> leaves carry set for a non-digit, and a digit here is a
;; syntax error.
;; Also: GONE2 (M6502)
WithToken:
    sbc #TOKEN_END
    bcc ToLet
    cmp #TOKEN_TAB - TOKEN_END      ; TAB( is the first token that is not a statement
    bcs CheckStatementSeparator::ToSyntaxError
    asl a
    tay
    lda StatementTable+1,y
    pha
    lda StatementTable,y
    pha
    jmp GetNextCharacter

;; Jumps on to <Statements::Let> for a character below <TOKEN_END>.
;; Also: GLET (M6502)
ToLet:
    jmp Statements::Let
.endproc

;; Takes a colon back to <NextStatement::TraceLine> for the next statement; anything else is a syntax error.
;; In: A = the nonzero byte at <TextPointer>
;; Entry:
;;   ToSyntaxError = jumps to <SyntaxError>; <DispatchStatement> branches here for a token beyond the statements
;; Also: MORSTS (M6502)
.proc CheckStatementSeparator
    cmp #':'
    beq NextStatement::TraceLine

;; Jumps on to <SyntaxError>.
;; Also: SNERR1 (M6502)
ToSyntaxError:
    jmp SyntaxError
.endproc

    RestoreStatement

;; Checks the keyboard for Control-C without consuming any other key: returns at once unless the keyboard holds it,
;; and otherwise reads the key and falls into <HandleBreak>.
;; See: <HandleBreak>, <Statements::Stop>
;; Also: ISCNTC (M6502, ASTIL)
.proc CheckStop
    lda KBD
    cmp #KEYBOARD_CONTROL_C
    beq ConsumeKey
    rts

;; Consumes the Control-C key through <InputCharacter>.
;; Also: ISCCAP (M6502)
ConsumeKey:
    jsr InputCharacter
    ; Falls into HandleBreak.
.endproc

;; Handles a break: gives error code $FF to an active `ONERR` handler, and otherwise compares A with <CONTROL_C> and
;; falls into the shared STOP code, which reports BREAK when they match.
;; In: A = the key read
;; Also: ISCCA1 (UNKN)
.proc HandleBreak
    ldx #$FF
    bit OnErrorActive
    bpl NoHandler
    jmp HANDLE

;; No `ONERR` handler is active: sets the flags for the shared STOP code from A.
;; Also: ISCCA2 (UNKN)
NoHandler:
    cmp #CONTROL_C
    ; Falls into Statements::Stop.
.endproc

    StopAndContinue 1, 0

.scope Statements continued

;; SAVE: writes the program's two-byte length and then the program to cassette through the Monitor.
;; See: <Statements::Load>, <SetCassetteLengthRange>, <SetCassetteProgramRange>
;; Also: SAVE (M6502)
.proc Save
    sec
    lda ProgramEnd
    sbc ProgramStart
    sta PokeAddress
    lda ProgramEnd+1
    sbc ProgramStart+1
    sta PokeAddress+1
    jsr SetCassetteLengthRange
    jsr MWRITE
    jsr SetCassetteProgramRange
    jmp MWRITE
.endproc

;; LOAD: reads a cassette program's length and text and sets <VariablesStart>, then clears the program's state, and
;; also relinks it unless it was saved run-only.
;; See: <Statements::Save>, <ClearAndRelink>
;; Also: LOAD (M6502)
.proc Load
    jsr SetCassetteLengthRange
    jsr MREAD
    clc
    lda ProgramStart
    adc PokeAddress
    sta VariablesStart
    lda ProgramStart+1
    adc PokeAddress+1
    sta VariablesStart+1
    lda NextTemporary
    sta RunOnly
    jsr SetCassetteProgramRange
    jsr MREAD
    bit RunOnly
    bpl ToClearAndRelink
    jmp ResetProgramState

;; Jumps on to <ClearAndRelink> when <RunOnly> is clear.
;; Also: LOAD1 (UNKN)
ToClearAndRelink:
    jmp ClearAndRelink
.endproc

.endscope

;; Points the Monitor's cassette range, A1 to A2, at the two bytes of <PokeAddress>, and clears <RunOnly>.
;; Also: VARTIO (M6502)
.proc SetCassetteLengthRange
    lda #<PokeAddress
    ldy #$00
    sta A1L
    sty A1H
    lda #<(PokeAddress+2)
    sta A2L
    sty A2H
    sty RunOnly
    rts
.endproc

;; Points the Monitor's cassette range, A1 to A2, at the program from <ProgramStart> to <VariablesStart>.
;; Also: PROGIO (M6502)
.proc SetCassetteProgramRange
    lda ProgramStart
    ldy ProgramStart+1
    sta A1L
    sty A1H
    lda VariablesStart
    ldy VariablesStart+1
    sta A2L
    sty A2H
    rts
.endproc

.scope Statements continued

;; RUN's dispatch entry: decrements <CurrentLine>'s high byte, keeping the incoming flags, and falls into the shared
;; <Statements::Run>.
;; Also: RUNSTM (UNKN)
.proc PrepareRun
    php
    dec CurrentLine+1
    plp
    ; Falls into Run.
.endproc

.endscope

    RunStatement
    GosubAndGoto NextStatementSavingStack

.scope Statements continued

;; POP: discards the innermost GOSUB frame, and the FOR frames above it, without transferring control. It is also
;; RETURN's dispatch entry: the shared <Statements::Return> that follows tells the two apart by Y.
;; Also: POP (UNKN)
Pop:

.endscope

    ReturnStatement 1, 1

    StatementScan 0, 1
    ConditionalStatements
    OnStatement

.include "../Microsoft6502Basic/MsBasic.LineNumber.asm"
