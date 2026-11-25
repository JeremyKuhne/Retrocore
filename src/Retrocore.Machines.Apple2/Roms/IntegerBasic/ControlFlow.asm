; retrocore: style=strict
;; Integer BASIC: printing numbers, assignment and running a program ($E7C1-$E97F)
;;
;; `PRINT` of a number, `AUTO`, numeric assignment and the statement separators; then the run loop (<Lines>), which
;; takes the program's lines in turn, and the statements that change its course: `IF`, `GOTO`, `GOSUB`, `RETURN`,
;; `END`, `FOR`, `TO` and `NEXT`.
;;
;; The run loop keeps <CurrentLine> at the line running and <TokenPointer> at its tokens. `GOSUB` keeps both on the
;; GOSUB stack, and `FOR` keeps its variable, step, limit and the place to loop back to on the FOR stack, both in
;; page 1 (<GoSubTokenLow> and <ForVariableLow>); each holds 16 entries. A jump restarts the run loop, which resets
;; the 6502's stack.
;;
;; Part of IntegerBasic.asm; it follows Arithmetic.asm, at $E7C1.

; Statements: printing numbers, AUTO, assignment and the statement separators.
.scope Statements continued

;; `PRINT`'s comma before a number (token $49): moves to the next tab stop, then prints the number (falls into
;; <Statements::PrintNumber>).
;; In: X = the noun stack, its top entry the number
;; Also: COMMA_PRNUM (UNKN)
.proc PrintNumberComma
    jsr NextTabStop
    ; Falls into PrintNumber.
.endproc

;; `PRINT` of a number (token $62), and the semicolon before one (token $46): prints the number in decimal.
;;
;; A negative number gets a minus sign and is printed as its negative. The line now owes a return
;; (<ReturnPending>). Leading zeros print as <LeadingZero> says, which the prompt sets to 0.
;; In: X = the noun stack, its top entry the number
;; Out: X = the noun stack, one entry higher
;; Errors: >32767 for -32768, after the minus sign
;; Uses: A, Y, Accumulator
;; Entry:
;;   FromAccumulator = prints the number in <Accumulator>, with Y = 0, keeping X
;; Also: PRINTNUM (IBSM)
.proc PrintNumber
    jsr GetNumber

;; Prints the number in <Accumulator>.
;; In: Accumulator = the number, Y = 0
;; Errors: >32767 for -32768, after the minus sign
;; Keeps: X
;; Also: PRINTACC (UNKN)
FromAccumulator:
    lda Accumulator+1
    bpl NotNegative
    lda #'-'
    jsr CharacterOut
    jsr Operators::Negate::FromAccumulator
    bvc PrintNumber                 ; always: an overflow was the error

    ; Not negative: the line owes a return (Y is 0, so $FF), and the number is printed, keeping X.
NotNegative:
    dey
    sty ReturnPending
    stx Accumulator+1
    ldx Accumulator
    jsr PrintDecimal
    ldx Accumulator+1
    rts
.endproc

;; `AUTO` (token $0D): starts `AUTO` mode at the line number given, counting by 10.
;; In: X = the noun stack, its top entry the first line number
;; Out: X = the noun stack, one entry higher
;; Uses: A, Y, Accumulator
;; See: <Statements::AutoComma>, <WarmStart>, <AutoNumbering>
;; Entry:
;;   SetStep = sets the step between line numbers to A (low) and Y (high)
;; Also: AUTO (IBSM)
.proc Auto

;; The step between line numbers unless `AUTO` gives one.
DEFAULT_STEP = 10

    jsr GetNumber
    lda Accumulator
    sta AutoLine
    lda Accumulator+1
    sta AutoLine+1

    ; AutoNumbering = $FF, from Y = 0.
    dey
    sty AutoNumbering
    iny
    lda #DEFAULT_STEP

;; Sets the step between line numbers to A (low) and Y (high).
;; Keeps: X
;; Also: SETAUTOINC (UNKN)
SetStep:
    sta AutoIncrement
    sty AutoIncrement+1
    rts
.endproc

;; The comma of `AUTO` (token $0E): `AUTO n,m` counts by m.
;; In: X = the noun stack, its top entry the step
;; Out: X = the noun stack, one entry higher
;; Uses: A, Y, Accumulator
;; Also: COMMA_AUTO (IBSM)
.proc AutoComma
    jsr GetNumber
    lda Accumulator
    ldy Accumulator+1
    bpl Auto::SetStep               ; always: the syntax takes only a number, at most 32767
.endproc

;; Numeric assignment (token $71, and $56, the = of `FOR`): stores the number on top in the variable below it.
;;
;; If the variable was marked with `DSP`, a running program then shows its name and new value
;; (<Display::FinishNumberAssignment>).
;; In: X = the noun stack: the value above the variable's address
;; Out: X = the noun stack, both popped
;; See: <Statements::DspNumber>
;; Also: ASSIGN_NUM (UNKN)
.proc AssignNumber
    jsr GetNumber
    lda NounStackLow,x
    sta Auxiliary
    lda NounStackHigh,x
    sta Auxiliary+1
    lda Accumulator
    sta (Auxiliary),y
    iny
    lda Accumulator+1
    jmp Display::FinishNumberAssignment
.endproc

;; `LET` (token $5E), and `THEN` before a statement (token $25): nothing to do.
;; Keeps: A, X, Y
;; Also: LET (IBSM)
.proc Let
    rts
.endproc

;; Token 0, at the bottom of the waiting tokens: ends the line.
;;
;; It runs when the end-of-line token arrives, after all the others. Dropping the return to the interpreter's loop
;; makes the RTS return from <Interpreter::RunLine>; first it falls into <Statements::Colon>, to print a return that
;; `PRINT` owes.
;; Also: BEGIN_LINE (IBSM)
.proc BeginLine
    pla
    pla
    ; Falls into Colon.
.endproc

;; The colon between statements (token $03): prints the return that a `PRINT` without a final `;` or `,` owes.
;; Keeps: X, Y
;; See: <ReturnPending>
;; Also: COLON (IBSM)
.proc Colon
    bit ReturnPending
    bpl PrintSemicolonEnd::Done
    ; Falls into Print.
.endproc

;; `PRINT` alone (token $63): prints a return.
;; Keeps: X, Y
;; Also: PRINT_CR (IBSM)
.proc Print
    jsr PrintReturn
    ; Falls into PrintSemicolonEnd.
.endproc

;; `PRINT`'s semicolon at the end of the statement (token $47): the line owes no return.
;; Keeps: A, X, Y
;; Entry:
;;   Done = returns
;; Also: SEMI_END (UNKN)
.proc PrintSemicolonEnd
    lsr ReturnPending
Done:
    rts
.endproc

.endscope

; Operators: the parentheses.
.scope Operators continued

;; The left parenthesis tokens ($22, $34, $38 and $3F): set <VerbPriority> to <Interpreter::HOLD_PRIORITY>, so nothing
;; waiting before the parenthesis runs.
;;
;; A left parenthesis runs when the right parenthesis arrives, after the operators inside it. Raising the arriving
;; priority then stops the waiting tokens outside the parentheses from running yet. The routines of other tokens that
;; open a parenthesis end here too, such as SCRN('s (<StoreHighByteAndClose>).
;; Uses: Y
;; Keeps: A, X
;; See: <Operators::RightParenthesis>, <Interpreter::RunLine>
;; Also: LEFT_PAREN (UNKN)
.proc LeftParenthesis
    ldy #Interpreter::HOLD_PRIORITY
    sty VerbPriority
    ; Falls into RightParenthesis.
.endproc

;; The right parenthesis (token $72): nothing to do; its arrival made the parentheses' contents run.
;; Keeps: A, X, Y
;; Also: RIGHT_PAREN (IBSM)
.proc RightParenthesis
    rts
.endproc

.endscope

; Statements: IF.
.scope Statements continued

;; `IF` (token $60): when the condition is 0, sets <SkippingStatement> so the rest of the statement is skipped.
;;
;; `IF` runs when `THEN` arrives. A false condition also changes the arriving token to <TOKEN_THEN_STATEMENT>, the
;; `THEN` that comes before a statement, so that `IF X THEN 100` does not jump; the skipping then passes over the
;; line number.
;; In: X = the noun stack, its top entry the condition
;; Out: X = the noun stack, one entry higher
;; Uses: A, Y, Accumulator
;; See: <Interpreter::RunLine>, <Statements::GoTo>
;; Also: IF (IBSM)
.proc If
    jsr InvertBoth::TopOnly
    beq Pop                         ; true: nothing to skip
    lda #TOKEN_THEN_STATEMENT
    sta CurrentVerb
    dey
    sty SkippingStatement

    ; Pops the condition.
Pop:
    inx
    rts
.endproc

.endscope

;; Running the program line by line: the run loop, and the places the statements that change its course send it.
;;
;; <CurrentLine> holds the line running and <TokenPointer> its tokens. Every line, and every jump, starts again at
;; <Lines::RunFromToken>, which resets the 6502's stack, so a statement can leave by jumping here whatever it has
;; pushed.
.scope Lines

;; Runs the program from its first line, keeping the variables.
;;
;; At $E836, where DOS's `CHAIN` jumps (DOS's equates call it `IBCHN`). `RUN` comes here after `CLR`.
;; See: <Statements::Run>
;; Also: RUNWARM (IBSM)
.proc RunFromStart
.assert * = $E836, "Lines::RunFromStart must stay at $E836, where DOS's CHAIN jumps."
    lda ProgramStart
    ldy ProgramStart+1
    bne RunLoop::TryLine            ; always: the program is not in page 0
.endproc

.endscope

; Statements: GOSUB and GOTO.
.scope Statements continued

;; `GOSUB` (token $5C): saves where the program is on the GOSUB stack, then goes to the line (falls into
;; <Statements::GoTo>).
;;
;; The saved <TokenPointer> is at the token after the line number, where <Statements::Return> picks up.
;; In: X = the noun stack, its top entry the line number
;; Errors: 16 GOSUBS if 16 are already active, BAD BRANCH if there is no such line
;; See: <Statements::Pop>
;; Also: GOSUB (IBSM)
.proc GoSub
    ldy #<Messages::SixteenGoSubs
    lda GoSubIndex
    cmp #GOSUB_STACK_DEPTH
    bcs Lines::RunLoop::ToReportError
    tay
    inc GoSubIndex
    lda TokenPointer
    sta GoSubTokenLow,y
    lda TokenPointer+1
    sta GoSubTokenHigh,y
    lda CurrentLine
    sta GoSubLineLow,y
    lda CurrentLine+1
    sta GoSubLineHigh,y
    ; Falls into GoTo.
.endproc

;; `GOTO` (token $5F), and `THEN` before a line number (token $24): goes to the line (falls into
;; <Lines::RunFrom>).
;; In: X = the noun stack, its top entry the line number
;; Errors: BAD BRANCH if there is no such line
;; See: <FindLine>
;; Also: GOTO (IBSM)
.proc GoTo
    jsr GetNumber
    jsr FindLine
    bcc Found
    ldy #<Messages::BadBranch
    bne Lines::RunLoop::ToReportError   ; always

    ; Runs the program from the line found.
Found:
    lda Pointer2
    ldy Pointer2+1
    ; Falls into Lines::RunFrom.
.endproc

.endscope

; Lines: the run loop.
.scope Lines continued

;; Runs the program from the line at A (low) and Y (high), from its first token (falls into
;; <Lines::RunFromToken>).
;; In: A/Y = the line
;; Also: GOLINE (UNKN)
.proc RunFrom
    sta CurrentLine
    sty CurrentLine+1
    clc
    adc #ProgramLine::TOKENS
    bcc RunFromToken
    iny
    ; Falls into RunFromToken.
.endproc

;; Runs from the token at A (low) and Y (high) in the line at <CurrentLine>, with a fresh 6502 stack (falls into
;; <Lines::RunLoop>).
;;
;; It marks the program as running (<Running>), and checks for Control-C and prints the line number in `TRACE` mode
;; (<Break::Check>). Each line of a running program starts here.
;; In: A/Y = the token, CurrentLine = its line
;; See: <Statements::Return>, <Statements::Next>, <Statements::Con>
;; Also: GETNEXT (IBSM)
.proc RunFromToken
    ; $FF is both the top of the 6502's stack and a run flag with bit 7 set.
    ldx #$FF
    stx Running
    txs
    sta TokenPointer
    sty TokenPointer+1
    jsr Break::Check
    ldy #0
    ; Falls into RunLoop.
.endproc

;; Runs the line from the token at <TokenPointer>, then the lines after it, until a statement stops the program.
;;
;; A typed line without a number runs from here too, with <Running> clear, so it ends after that line. When
;; TokenPointer is at a statement's first token, that statement starts here; after `RETURN` or `NEXT` it is at the
;; colon or the end of the line instead, and the statement after it starts at <Interpreter::RunLine::Wait>. The
;; debugger's BASIC thread takes a line's first statement from here.
;; In: TokenPointer = the token, CurrentLine = its line
;; Errors: NO END if the program runs past its last line
;; Entry:
;;   TryLine = runs the line at A (low) and Y (high), unless it is the end of the program
;;   RanOff = the program has run past its last line
;;   ToReportError = reports the error whose message is at offset Y
;; Also: RUNLOOP (UNKN)
.proc RunLoop
    jsr Interpreter::RunLine

    ; Not running: a typed line, which ends here.
    bit Running
    bpl Statements::End

    ; The next line: CurrentLine + its length.
    clc
    ldy #ProgramLine::LENGTH
    lda CurrentLine
    adc (CurrentLine),y
    ldy CurrentLine+1
    bcc TryLine
    iny

;; Runs the line at A (low) and Y (high), unless it is <HighMemory>, the end of the program.
;; Also: TRYLINE (UNKN)
TryLine:
    cmp HighMemory
    bne RunFrom
    cpy HighMemory+1
    bne RunFrom
    ldy #<Messages::NoEnd

;; The program has run past its last line: no longer running, it reports NO END.
;; Also: TRYLINE_END (UNKN)
RanOff:
    lsr Running

;; Reports the error whose message is at offset Y (<ReportError>).
;; Also: JmpERRMESS1 (IBSM)
ToReportError:
    jmp ReportError
.endproc

.endscope

; Statements: RETURN.
.scope Statements continued

;; `RETURN` (token $5B): goes back to the token after the last `GOSUB`.
;; Errors: BAD RETURN if no GOSUB is active
;; See: <Statements::GoSub>, <Statements::Pop>
;; Entry:
;;   ContinueAt = runs from the token at X (low) and A (high), in the line at <CurrentLine>
;; Also: RETURN (IBSM)
.proc Return
    ldy #<Messages::BadReturn
    lda GoSubIndex
    beq Lines::RunLoop::ToReportError
    dec GoSubIndex
    tay
    lda GoSubLineLow-1,y
    sta CurrentLine
    lda GoSubLineHigh-1,y
    sta CurrentLine+1
    ldx a:GoSubTokenLow-1,y         ; absolute: page zero,Y would wrap within page zero
    lda GoSubTokenHigh-1,y

;; Runs from the token at X (low) and A (high), in the line at <CurrentLine>.
;; Also: GETNEXTXA (UNKN)
ContinueAt:
    tay
    txa
    jmp Lines::RunFromToken
.endproc

.endscope

; Lines: stopping the program.
.scope Lines continued

;; Stops the program: prints STOPPED AT and the number of the line at <CurrentLine>, then ends (falls into
;; <Statements::End>).
;;
;; Control-C and errors in a running program come here.
;; See: <Break::Check>, <Messages::StopOrRetype>
;; Also: STOPPED_AT (IBSM)
.proc Stop
    ldy #<Messages::StoppedAt
    jsr PrintMessage
    ldy #ProgramLine::NUMBER
    lda (CurrentLine),y
    tax
    iny
    lda (CurrentLine),y
    jsr PrintDecimal
    ; Falls into Statements::End.
.endproc

.endscope

; Statements: END, then NEXT, FOR and TO.
.scope Statements continued

;; `END` (token $51): stops the program and returns to the prompt.
;; Also: END (IBSM)
.proc End
    jmp WarmStart
.endproc

;; Drops the innermost `FOR` loop, whose variable is not `NEXT`'s, then looks again (falls into
;; <Statements::Next>).
.proc DropInnerLoop
    dec ForIndex
    ; Falls into Next.
.endproc

;; `NEXT` (token $59, and $5A after a comma): adds the step to the loop's variable and loops back, unless it has passed
;; the limit.
;;
;; The FOR stack is searched from the innermost loop for the variable; the loops inside it are dropped
;; (<Statements::DropInnerLoop>). The loop goes on while the variable equals the limit or the sign of variable -
;; limit is not the step's sign. That difference is a subtraction (<Operators::Subtract>), so by the code a variable
;; and limit more than 32767 apart (`FOR I = -20000 TO 20000`) stop the loop with the >32767 error.
;; In: X = the noun stack, its top entry the variable
;; Out: X = the noun stack, one entry higher, when the loop is done
;; Errors: BAD NEXT if no FOR loop has the variable, >32767 if the variable passes 32767 or is too far from the limit
;; See: <Statements::For>, <ForVariableLow>
;; Entry:
;;   ErrorIfZero = reports the error whose message is at offset Y when zero is set
;; Also: NEXT (IBSM)
.proc Next
    ldy #<Messages::BadNext
    lda ForIndex

;; Reports the error whose message is at offset Y when zero is set: no loops left (BAD NEXT), or
;; <FOR_STACK_DEPTH> loops already (16 FORS).
;; Also: JmpERRMESS2 (IBSM)
ErrorIfZero:
    beq Lines::RunLoop::ToReportError

    ; The innermost loop must be this variable's.
    tay
    lda NounStackLow,x
    cmp ForVariableLow-1,y
    bne DropInnerLoop
    lda NounStackHigh,x
    cmp ForVariableHigh-1,y
    bne DropInnerLoop

    ; Stores the variable's value + the step in the variable.
    lda ForStepLow-1,y
    sta Auxiliary
    lda ForStepHigh-1,y
    sta Auxiliary+1
    jsr GetNumber
    dex                             ; the variable again, below its new value
    jsr Operators::Add::AddAuxiliary
    jsr AssignNumber

    ; The sign of the variable - the limit: pushes the variable again, then the limit.
    dex
    ldy ForIndex
    lda ForLimitHigh-1,y
    sta NounStackNumberHigh-1,x
    lda ForLimitLow-1,y
    ldy #0
    jsr PushNoun
    jsr Operators::Subtract
    jsr Functions::Sgn
    jsr GetNumber

    ; Equal to the limit: once more. A sign that differs from the step's: once more.
    ldy ForIndex
    lda Accumulator
    beq LoopBack
    eor ForStepHigh-1,y
    bpl Done

    ; Loops back: runs from the token after the FOR statement.
LoopBack:
    lda ForLineLow-1,y
    sta CurrentLine
    lda ForLineHigh-1,y
    sta CurrentLine+1
    ldx ForTokenLow-1,y
    lda ForTokenHigh-1,y
    bne Return::ContinueAt          ; always: the address is not in page 0

    ; The loop is done: drops it.
Done:
    dec ForIndex
    rts
.endproc

;; `FOR` (token $55): starts a FOR loop for the variable, which `=` then assigns.
;;
;; The variable stays on the noun stack for the `=` (<Statements::AssignNumber>). `TO` and `STEP` fill in the rest of
;; the entry. A FOR loop already active for the same variable is removed (<DropOlderForLoop>); the ROMs' removal moves
;; the loops above it down with one column wrong, which the FORFIX build corrects.
;; In: X = the noun stack, its top entry the variable
;; Errors: 16 FORS if 16 loops are active
;; See: <Statements::To>, <Statements::Step>, <Statements::Next>
;; Also: FOR (IBSM)
.proc For
    ldy #<Messages::SixteenFors
    lda ForIndex
    cmp #FOR_STACK_DEPTH
    beq Next::ErrorIfZero
    inc ForIndex
    tay
    lda NounStackLow,x
    sta ForVariableLow,y
    lda NounStackHigh,x
    jmp DropOlderForLoop
    .byte $60                       ; an unused byte (an RTS)
.endproc

;; `TO` (token $57): sets the loop's limit and a step of 1, and the place to loop back to.
;;
;; The place is the line at <CurrentLine> and the token at <TokenPointer>, which is the token after the statement,
;; or `STEP`: `STEP` runs later, and sets it again.
;; In: X = the noun stack, its top entry the limit
;; Out: X = the noun stack, one entry higher
;; Uses: A, Y, Accumulator
;; See: <Statements::For>, <Statements::Step>
;; Entry:
;;   SetPlace = stores A as the step's high byte, then the place to loop back to
;; Also: TO (IBSM)
.proc To
    jsr GetNumber
    ldy ForIndex
    lda Accumulator
    sta ForLimitLow-1,y
    lda Accumulator+1
    sta ForLimitHigh-1,y

    ; A step of 1.
    lda #1
    sta ForStepLow-1,y
    lda #0

;; Stores A as the step's high byte, then the place to loop back to.
;; In: A = the step's high byte, Y = <ForIndex>
;; Keeps: X, Y
;; Also: SETFORPLACE (UNKN)
SetPlace:
    sta ForStepHigh-1,y
    lda CurrentLine
    sta ForLineLow-1,y
    lda CurrentLine+1
    sta ForLineHigh-1,y
    lda TokenPointer
    sta ForTokenLow-1,y
    lda TokenPointer+1
    sta ForTokenHigh-1,y
    rts
    .byte $20, $15                  ; unused bytes
.endproc

.endscope
