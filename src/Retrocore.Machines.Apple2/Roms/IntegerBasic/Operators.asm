; retrocore: style=strict
;; Integer BASIC: the rule starts, DSP, comparisons, AND, OR and the last statements
;;
;; <RuleStarts>, the tokenizer's index of where each syntax rule starts; the display of a variable marked with DSP
;; when a program assigns it; the comparisons less than, greater than, at most and at least, AND and OR; STEP, which
;; sets a FOR's step; DSP and NODSP; CON, ASC(, PDL, ^, PR# and IN#; the line input of INPUT; and a few small routines
;; the other modules share. It follows Memory.asm, at $F197.
;;
;; Part of IntegerBasic.asm.

;; How far a variable's display flag is before its value: the flag, then the next variable's address (2 bytes).
DISPLAY_FLAG_BEFORE_VALUE = 3

;; The first token that ends a variable's name: THEN, TO, STEP, AND, OR, MOD and AT at the bottom of the syntax table's
;; first page are $85 and up, and are never written as tokens.
FIRST_RESERVED_TOKEN = $85

;; The bits of PDL's number that pick the paddle, 0 to 3.
PADDLE_MASK = $03

;; One entry of <RuleStarts>: where a syntax rule starts, as <Tokenizer::StartRule> takes it.
;; Parameters:
;;   number = the rule's number, which is its entry's place in the table
;;   start = the rule's address in the syntax table
.macro RuleStart number, start
    .assert * - RuleStarts = number, "The rule starts are in the order of the rules' numbers."
    .byte (start - Syntax::Table - 1) / 2
.endmacro

;; Where each of the 32 syntax rules starts, as the tokenizer's <Tokenizer::StartRule> takes it: the address less $EC01,
;; halved.
;;
;; A rule therefore starts at an odd offset in its page; bit 7 selects the page at $ED00.
;; See: <Syntax::Table>, <Tokenizer::CallRule>
;; Also: SYNTABLNDX (IBSM)
RuleStarts:
    RuleStart Syntax::RULE_NUMBER, Syntax::NumberRule
    RuleStart Syntax::RULE_NUMBER_THEN_ARRAY, Syntax::NumberThenArrayRule
    RuleStart Syntax::RULE_STATEMENT, Syntax::StatementRule
    RuleStart Syntax::RULE_DIM_STRING, Syntax::DimStringRule
    RuleStart Syntax::RULE_THEN, Syntax::ThenRule
    RuleStart Syntax::RULE_INPUT_NEXT, Syntax::InputNextRule
    RuleStart Syntax::RULE_SUBSTRING, Syntax::SubstringRule
    RuleStart Syntax::RULE_EXPRESSION, Syntax::ExpressionRule
    RuleStart Syntax::RULE_STRING, Syntax::StringRule
    RuleStart Syntax::RULE_STRING_VARIABLE, Syntax::StringVariableRule
    RuleStart Syntax::RULE_STRING_DESTINATION, Syntax::StringDestinationRule
    RuleStart Syntax::RULE_STATEMENTS_TEXT_TO_TAB, Syntax::StatementsTextToTabRule
    RuleStart Syntax::RULE_STRING_CHARACTERS, Syntax::StringCharactersRule
    RuleStart Syntax::RULE_DIM_NEXT, Syntax::DimNextRule
    RuleStart Syntax::RULE_PRINT_NEXT, Syntax::PrintNextRule
    RuleStart Syntax::RULE_DIGIT, Syntax::DigitRule
    RuleStart Syntax::RULE_DIM_ARRAY, Syntax::DimArrayRule
    RuleStart Syntax::RULE_RIGHT_PARENTHESIS, Syntax::RightParenthesisRule
    RuleStart Syntax::RULE_INPUT_NUMBERS, Syntax::InputNumbersRule
    RuleStart Syntax::RULE_SIGNED_NUMBER, Syntax::SignedNumberRule
    RuleStart Syntax::RULE_FUNCTION_NAME, Syntax::FunctionNameRule
    RuleStart Syntax::RULE_OPERAND, Syntax::OperandRule
    RuleStart Syntax::RULE_UNSIGNED_OPERAND, Syntax::UnsignedOperandRule
    RuleStart Syntax::RULE_NUMBER_VARIABLE, Syntax::NumberVariableRule
    RuleStart Syntax::RULE_ASSIGNMENT, Syntax::AssignmentRule
    RuleStart Syntax::RULE_NAME, Syntax::NameRule
    RuleStart Syntax::RULE_IMMEDIATE_STATEMENT, Syntax::ImmediateStatementRule
    RuleStart Syntax::RULE_STATEMENTS_LIST_TO_IN, Syntax::StatementsListToInRule
    RuleStart Syntax::RULE_NAME_REST, Syntax::NameRestRule
    RuleStart Syntax::RULE_NAME_CHARACTER, Syntax::NameCharacterRule
    RuleStart Syntax::RULE_OPERATOR, Syntax::OperatorRule
    RuleStart Syntax::RULE_LINE, Syntax::LineRule
.assert * - RuleStarts = 32, "One start for each of the 32 rules."

; Showing a variable that DSP marks.
.scope Display continued

;; Prints the number in <Accumulator> and a blank: the value of a variable DSP shows.
;; In: Accumulator = the number
;; See: <Statements::PrintNumber::FromAccumulator>
;; Also: PRNUMBLANK (UNKN)
.proc PrintNumberAndBlank
    ldy #0
    jsr Statements::PrintNumber::FromAccumulator
    lda #BLANK | $80
    jmp CharacterOut
.endproc

    ; Unused bytes.
    .res 8, $00

;; Prints the name of the variable whose value is at <Auxiliary>, then =.
;;
;; It walks the variables from LOMEM to the last one that starts below Auxiliary. A string's $ token prints as $.
;; In: Auxiliary = the address of the variable's value
;; Out: SearchPointer = the variable's address
;; Uses: A, Y
;; Also: PRVARNAME (UNKN)
.proc PrintVariableName
    ; A (high) and Y (low) = the variable to look at, from the first one.
    ldy LowMemory
    lda LowMemory+1

    ; Stop at the first variable that is not below Auxiliary; the one before it is the one.
NextVariable:
    pha
    cpy Auxiliary
    sbc Auxiliary+1
    bcs PrintName
    pla
    sty SearchPointer
    sta SearchPointer+1

    ; Skip its name, then take the next variable's address.
    ldy #$FF
SkipName:
    iny
    lda (SearchPointer),y
    bmi SkipName
    cmp #TOKEN_DOLLAR
    beq SkipName
    iny
    iny
    lda (SearchPointer),y
    pha
    dey
    lda (SearchPointer),y
    tay
    pla
    bne NextVariable                ; always: no variable is in page zero

;; Prints the name of the variable at <SearchPointer>, up to its display flag.
;; Also: PRSRCHNAME (UNKN)
PrintName:
    pla
    ldy #0

NextCharacter:
    lda (SearchPointer),y
    bmi Print
    lsr a
    beq PrintEquals                 ; the display flag, 0 or 1, ends the name
    lda #'$'

Print:
    jsr CharacterOut
    iny
    bne NextCharacter

PrintEquals:
    lda #'='
    jmp CharacterOut
.endproc

;; Stores the high byte of a numeric assignment and pops the variable; shows it if it is marked with DSP.
;; In: A = the value's high byte, Auxiliary = the variable's value, Y = 1, X = the noun stack, its top entry the
;;   variable, whose display flag the lookup left in its high byte of numbers
;; Out: X = the noun stack, one entry higher
;; See: <Statements::AssignNumber>, <TryShowNumber>
;; Also: LETNUMEND (UNKN)
.proc FinishNumberAssignment
    sta (Auxiliary),y
    inx
    lda NounStackNumberHigh-1,x
    beq ShowString::Return
    jmp TryShowNumber
.endproc

    ; An unused byte (an LDY immediate).
    .byte $A0

;; Shows a numeric variable after an assignment: # and the line number unless TRACE has printed it, then the name,
;; = and the value.
;;
;; It loads <CurrentLine> into A and Y before printing the line number, though
;; <Display::TraceLine::PrintLineNumber> reads the line itself.
;; In: negative = set in TRACE mode, Accumulator = the value, Auxiliary = the variable's value
;; Out: X = the noun stack index kept in <SavedX>
;; See: <TryShowNumber>
;; Also: SHOWNUM (UNKN)
.proc ShowNumber
    bmi PrintName
    lda CurrentLine
    ldy CurrentLine+1
    jsr TraceLine::PrintLineNumber

PrintName:
    jsr PrintVariableName
    ldx SavedX
    jmp PrintNumberAndBlank
.endproc

;; Pops a string assignment's variable, and shows it if it is marked with DSP.
;; In: X = the noun stack, its top entries the variable's range and address
;; Out: X = the noun stack, both popped
;; See: <Statements::LetString>, <TryShowString>
;; Also: LETSTREND (UNKN)
.proc FinishStringAssignment
    inx
    inx
    lda NounStackNumberHigh-1,x
    beq GetNumberPlusOne::Done
    jmp TryShowString
.endproc

;; Shows a string variable after an assignment, as <ShowNumber> shows a number.
;; In: negative = set in TRACE mode, Auxiliary = the variable's value
;; Out: X = the noun stack index kept in <SavedX>
;; See: <TryShowString>
;; Entry:
;;   Return = returns; <FinishNumberAssignment> branches here for a variable DSP does not mark
;; Also: SHOWSTR (UNKN)
.proc ShowString
    bmi PrintName
    lda CurrentLine
    ldy CurrentLine+1
    jsr TraceLine::PrintLineNumber

PrintName:
    jsr PrintVariableName
    ldx SavedX
    jmp PrintStringAt

    ; An unused byte (an INX).
    .byte $E8

Return:
    rts
.endproc

.endscope

;; Takes a number off the noun stack and adds 1.
;; In: X = the noun stack
;; Out: Accumulator = the number + 1, A = 0 for a number entry or the value's low byte for a variable's, X = the noun
;;   stack, one entry higher, Y = 0
;; Keeps: carry
;; See: <GetNumber>
;; Entry:
;;   Done = returns; <Display::FinishStringAssignment> branches here for a variable DSP does not mark
;; Also: GET16INC (UNKN)
.proc GetNumberPlusOne
    jsr GetNumber
    inc Accumulator
    bne Done
    inc Accumulator+1

Done:
    rts
.endproc

; The comparisons, AND and OR.
.scope Operators continued

;; < (token $1C): replaces two numbers with 1 if the lower is less than the top one, 0 if not: NOT >=.
;;
;; <Operators::Not> always ends with zero clear, so the branch is always taken.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 if the difference overflows
;; See: <GreaterOrEqual>
;; Also: LESS (UNKN)
.proc Less
    jsr GreaterOrEqual
    bne GreaterOrEqual::ToNot
.endproc

;; > (token $19): 1 if the lower number is greater than the top one: NOT <=.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 if the difference overflows
;; See: <LessOrEqual>
;; Also: GREATER (UNKN)
.proc Greater
    jsr LessOrEqual
    bne GreaterOrEqual::ToNot
.endproc

;; <= (token $1A): 1 if the lower number is at most the top one: the difference, negated, is not negative.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 if the difference overflows
;; Also: LESSEQ (UNKN)
.proc LessOrEqual
    jsr Operators::Subtract
    jsr Operators::Negate
    bvc GreaterOrEqual::Sign        ; always: an overflow is an error
.endproc

;; >= (token $18): 1 if the lower number is at least the top one: the difference is not negative.
;;
;; The difference's sign (<Functions::Sgn>) halved is 0 for 0 and 1, and $FF7F for -1; <Operators::Not> turns that into
;; 1, 1 and 0. As the difference must fit in 16 bits, comparing numbers more than 32767 apart is the >32767 error.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 if the difference overflows
;; Entry:
;;   Sign = turns the difference on the noun stack into the result; <LessOrEqual> branches here
;;   ToNot = replaces the top number with NOT of it (<Operators::Not>); <Operators::Less> and <Operators::Greater>
;;   branch here, and AND and OR reach it through <Operators::Or::Store>
;; Also: GREATEQ (UNKN)
.proc GreaterOrEqual
    jsr Operators::Subtract

;; Turns the difference on the noun stack into the result; <LessOrEqual> branches here.
Sign:
    jsr Functions::Sgn
    lsr NounStackLow,x

;; Replaces the top number with NOT of it (<Operators::Not>); <Operators::Less> and <Operators::Greater> branch
;; here, and AND and OR reach it through <Operators::Or::Store>.
;; Also: JmpNOT (IBSM)
ToNot:
    jmp Operators::Not
.endproc

;; AND (token $1D): 1 if both numbers are not 0, else 0.
;;
;; It works as NOT (NOT a OR NOT b) on the 0 and 1 that <InvertBoth> leaves.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; See: <Or>
;; Also: VAND (IBSM)
.proc And
    jsr InvertBoth
    ora NounStackLow-1,x
    bpl Or::Store                   ; always: A is 0 or 1
.endproc

;; OR (token $1E): 1 if either number is not 0, else 0: NOT (NOT a AND NOT b).
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the result
;; See: <InvertBoth>, <And>
;; Entry:
;;   Store = stores A as the number, then replaces it with NOT of it; <And> branches here
;; Also: VOR (IBSM)
.proc Or
    jsr InvertBoth
    and NounStackLow-1,x

;; Stores A as the number, then replaces it with NOT of it; <And> branches here.
Store:
    sta NounStackLow,x
    bpl GreaterOrEqual::ToNot       ; always: A is 0 or 1
    jmp InvertBoth                  ; unused: the branch before it is always taken
.endproc

.endscope

; STEP.
.scope Statements continued

;; STEP (token $58): sets the step of the FOR loop being set up, and the place to loop back to again, after STEP.
;; In: X = the noun stack, its top entry the step
;; See: <Statements::To>, <Statements::For>, <Statements::To::SetPlace>
;; Also: STEP (IBSM)
.proc Step
    jsr GetNumber
    ldy ForIndex
    lda Accumulator
    sta ForStepLow-1,y
    lda Accumulator+1
    jmp Statements::To::SetPlace
.endproc

.endscope

;; The rest of FOR: stores the new loop's variable address high byte, then removes any older FOR loop for the same
;; variable, moving the loops above it down.
;;
;; In the ROMs the move copies the <ForTokenLow> column twice and never <ForTokenHigh>, so each loop that moves down
;; keeps the token address high byte of the loop that was in its new place; NEXT then goes back to the wrong token
;; when the two addresses are in different pages. The 1983 System Master's INTBASIC copies <ForTokenHigh> instead,
;; which FORFIX builds.
;; In: A = the variable's address, high byte, Y = the new loop's index, X = the noun stack, its top entry the variable
;; Keeps: X
;; See: <Statements::For>
;; Also: FORDROPOLD (UNKN)
.proc DropOlderForLoop
    sta ForVariableHigh,y

    ; Look down the older loops for the same variable.
FindOlder:
    dey
    bmi Done
    lda ForVariableLow,y
    cmp NounStackLow,x
    bne FindOlder
    lda ForVariableHigh,y
    cmp NounStackHigh,x
    bne FindOlder

    ; One loop fewer: move each loop above it down one place.
    dec ForIndex
MoveDown:
    lda ForVariableLow+1,y
    sta ForVariableLow,y
    lda ForVariableHigh+1,y
    sta ForVariableHigh,y
    lda ForLimitLow+1,y
    sta ForLimitLow,y
    lda ForLimitHigh+1,y
    sta ForLimitHigh,y
    lda ForStepLow+1,y
    sta ForStepLow,y
    lda ForStepHigh+1,y
    sta ForStepHigh,y
    lda ForLineLow+1,y
    sta ForLineLow,y
    lda ForLineHigh+1,y
    sta ForLineHigh,y
    lda ForTokenLow+1,y
    sta ForTokenLow,y
.if FORFIX
    ; The 1983 System Master's INTBASIC copies the token addresses' high bytes.
    lda ForTokenHigh+1,y
    sta ForTokenHigh,y
.else
    ; The ROMs copy the token addresses' low bytes a second time instead.
    lda ForTokenLow+1,y
    sta ForTokenLow,y
.endif
    iny
    cpy ForIndex
    bcc MoveDown

Done:
    rts
.endproc

; NODSP.
.scope Statements continued

;; NODSP of a string (token $78): stops showing the variable when it is assigned.
;; In: X = the noun stack, its top entries the variable's range and address
;; Out: X = the noun stack, both popped
;; See: <DspString>
;; Also: NODSP_STR (IBSM)
.proc NoDspString
    inx
    ; Falls into NoDspNumber.
.endproc

;; NODSP of a number (token $79): clears the variable's display flag.
;; In: X = the noun stack, its top entry the variable's address
;; Out: X = the noun stack, popped
;; Also: NODSP_NUM (IBSM)
.proc NoDspNumber
    lda #0
    ; Falls into Display::SetFlag.
.endproc

.endscope

.scope Display continued

;; Sets the display flag of the variable on the noun stack to A, and pops it.
;;
;; The flag is the byte 3 before the value, after the name and before the next variable's address.
;; In: A = 0 or 1, X = the noun stack, its top entry the variable's address
;; Out: X = the noun stack, popped, Accumulator = the flag's address, Y = 0
;; Also: SETDSPFLAG (UNKN)
.proc SetFlag
    pha
    lda NounStackLow,x
    sec
    sbc #DISPLAY_FLAG_BEFORE_VALUE
    sta Accumulator
    lda NounStackHigh,x
    sbc #0
    sta Accumulator+1
    pla
    ldy #0
    sta (Accumulator),y
    inx
    rts
.endproc

.endscope

;; A keyword matched (<Tokenizer::GotKeyword>): writes its token and goes on (<Tokenizer::PutTokenAndNext>), or fails if
;; it is a reserved word, a token of $85 and up.
;;
;; Failing with Y = 2, at the bottom of the first page, makes the name rule (<Syntax::RULE_NAME_CHARACTER>) try a digit
;; and end the name.
;; In: A = the token, Y = the item
;; Also: KEYMATCHED (UNKN)
.proc WriteKeywordToken
    cmp #FIRST_RESERVED_TOKEN
    bcs Reserved
    jmp Tokenizer::PutTokenAndNext

Reserved:
    ldy #2
    jmp Tokenizer::ItemFailed
.endproc

; DSP and CON.
.scope Statements continued

;; DSP of a string (token $7B): shows the variable each time it is assigned.
;; In: X = the noun stack, its top entries the variable's range and address
;; Out: X = the noun stack, both popped
;; See: <NoDspString>
;; Also: DSP_STR (IBSM)
.proc DspString
    inx
    ; Falls into DspNumber.
.endproc

;; DSP of a number (token $7C): sets the variable's display flag.
;; In: X = the noun stack, its top entry the variable's address
;; Out: X = the noun stack, popped
;; Also: DSP_NUM (IBSM)
.proc DspNumber
    lda #1
    bne Display::SetFlag            ; always
.endproc

    ; An unused byte (an INX).
    .byte $E8

;; CON (token $06): continues a program stopped by Control-C, from the token where it stopped.
;;
;; <Break::Check> saved the place in the noun stack's first entries.
;; See: <Lines::RunFromToken>
;; Also: CON (IBSM)
.proc Con
    lda Break::StoppedLine
    sta CurrentLine
    lda Break::StoppedLineHigh
    sta CurrentLine+1
    lda Break::StoppedToken
    ldy Break::StoppedTokenHigh
    jmp Lines::RunFromToken
.endproc

.endscope

.scope Display continued

;; Sets a variable's display flag to 1, as DSP does; nothing in the ROM reaches it.
;; In: X = the noun stack, its top entry the variable's address
;; Out: X = the noun stack, popped
;; Also: DSPFLAGON (UNKN)
.proc SetFlagOn
    lda #1
    bne SetFlag                     ; always
.endproc

.endscope

; ASC( and PDL.
.scope Functions continued

;; ASC( (token $3C): replaces a string with its first character's code, bit 7 set as the Apple II keeps text: 193
;; for A.
;;
;; The routine then ends as a left parenthesis does (<Operators::LeftParenthesis>), as the token opens ASC's
;; parenthesis.
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, its top entry the code
;; Errors: RANGE for an empty string
;; Also: ASC (IBSM)
.proc Asc
    lda NounStackLow,x
    cmp NounStackHigh,x
    bcc ReadCharacter
    jmp RangeError

    ; Read the first character, and push it as a number.
ReadCharacter:
    tay
    lda NounStackLow+1,x
    sta Accumulator
    lda NounStackHigh+1,x
    sta Accumulator+1
    lda (Accumulator),y
    ldy #0
    inx
    inx
    jsr PushNoun
    jmp StoreHighByteAndClose
.endproc

;; PDL (token $32): replaces a paddle's number, 0 to 3, with its position, 0 to 255.
;;
;; Only the number's low two bits count.
;; In: X = the noun stack, its top entry the paddle
;; Out: X = the noun stack, its top entry the position
;; Errors: >255
;; See: <ReadPaddle>
;; Also: PDL (IBSM)
.proc Pdl
    jsr GetByte
    stx SavedX
    and #PADDLE_MASK
    tax
    jsr ReadPaddle
    ldx SavedX
    tya
    ldy #0
    jsr PushNoun
    sty NounStackNumberHigh,x
    rts
.endproc

.endscope

;; Reads a line into <InputBuffer> from index X, after the prompt, and goes to the warm start if it holds a
;; Control-C (<Break::CheckLine>).
;;
;; INPUT of a string reads with it.
;; In: X = where the line starts in <InputBuffer>
;; Out: X = the index of the return that ends it
;; See: <GetLine::NextCharacter>, <Strings::ReadLineInto>
;; Also: RDKEY (IBSM)
.proc ReadInputLine
    jsr GetLine::NextCharacter
    ; Falls into Break::CheckLine.
.endproc

.scope Break continued

;; Goes to the warm start (<WarmEntry>) if the line in <InputBuffer> holds a Control-C, from index X down to 0.
;;
;; The index counts down only while it is below $80, so when X is $81 or more only the character at X is checked.
;; In: X = the last index to check
;; Out: A = X
;; Keeps: X, Y
;; Also: CHKCTRLC (UNKN)
.proc CheckLine
    txa
    pha

NextCharacter:
    lda InputBuffer,x
    cmp #CONTROL_C | $80
    bne NotControlC
    jmp WarmEntry

NotControlC:
    dex
    bpl NextCharacter
    pla
    tax
    rts
.endproc

.endscope

;; Reads a line for INPUT of numbers, with the ? prompt, and checks it for Control-C (<Break::CheckLine>).
;; Out: Y = the index of the underline that ends it, X = the same
;; See: <Editor::ReadInputLine>, <Statements::InputNumber>
;; Also: INPUTNUMLN (UNKN)
.proc ReadNumberLine
    jsr Editor::ReadInputLine
    tya
    tax
    jsr Break::CheckLine
    txa
    tay
    rts
.endproc

; ^.
.scope Operators continued

;; ^ (token $20): replaces two numbers with the lower one raised to the power of the top one.
;;
;; The power is repeated multiplication (<Operators::Multiply>), starting from 1: <SearchPointer> counts,
;; <SearchPointer2> holds the base. A negative exponent gives 0, but pushes it above the exponent instead of replacing
;; both operands, so they stay on the noun stack below it.
;; In: X = the noun stack: the base, then the exponent on top
;; Out: X = the noun stack, its top entry the power
;; Errors: >32767
;; Also: EXP (IBSM)
.proc Power
    jsr GetNumber
    lda Accumulator+1
    bpl Positive

    ; A negative exponent: push 0.
    tya
    dex
    jsr PushNoun
    sty NounStackNumberHigh,x

Done:
    rts

    ; SearchPointer = the exponent, SearchPointer2 = the base, and the result starts as 1.
Positive:
    sta SearchPointer+1
    lda Accumulator
    sta SearchPointer
    jsr GetNumber
    lda Accumulator
    sta SearchPointer2
    lda Accumulator+1
    sta SearchPointer2+1
    lda #1
    jsr PushNoun
    sty NounStackNumberHigh,x

    ; Count the exponent down, multiplying by the base each time.
Multiply:
    lda SearchPointer
    bne CountDown
    dec SearchPointer+1
    bmi Done
CountDown:
    dec SearchPointer
    lda SearchPointer2
    ldy #0
    jsr PushNoun
    lda SearchPointer2+1
    sta NounStackNumberHigh,x
    jsr Operators::Multiply
    jmp Multiply
.endproc

.endscope

;; Takes a byte from the noun stack, less 1: VTAB's line counted from 0.
;; In: X = the noun stack
;; Out: A = the byte - 1, carry = clear for a byte of 0, X = the noun stack, one entry higher, Y = 0
;; Errors: >255
;; Entry:
;;   Return = returns; <Display::TryShowNumber> and <Display::TryShowString> branch here when no program runs
;; Also: GETBYTEDEC (UNKN)
.proc GetByteMinusOne
    jsr GetByte
    clc
    adc #$FF

Return:
    rts
.endproc

; PRINT's comma at the end.
.scope Statements continued

;; PRINT's comma at the end of the statement (token $4A): moves to the next tab stop, and the line owes no return.
;; Out: ReturnPending = bit 7 clear
;; See: <NextTabStop>
;; Also: COMMA_PREND (UNKN)
.proc PrintCommaEnd
    jsr NextTabStop
    lsr ReturnPending
    rts
.endproc

.endscope

;; Runs a line's tokens with the run flag and the stack pointer set from X, checking for Control-C first; nothing in
;; the ROM reaches it.
;; In: X = the run flag and the stack pointer
;; See: <Break::Check>, <Lines::RunLoop>
;; Also: RUNTOKENS (UNKN)
.proc RunWithStack
    stx Running
    txs
    jsr Break::Check
    jmp Lines::RunLoop
.endproc

; PR#.
.scope Statements continued

;; PR# (token $7E): sends output to slot n's ROM, or to the screen for 0.
;; In: X = the noun stack, its top entry the slot
;; Out: X = the noun stack, popped
;; Errors: >255
;; See: <SetOutput>, <InNumber>
;; Also: PRSLOT (IBSM)
.proc PrNumber
    jsr GetByte
    stx SavedX
    jsr SetOutput
    ldx SavedX
    rts
.endproc

    ; An unused byte.
    .byte $FE

.endscope

.scope Display continued

;; After a numeric assignment to a variable DSP marks: shows it, if a program is running.
;; In: X = the noun stack
;; Out: X = the noun stack, as it was
;; See: <ShowNumber>
;; Also: TRYSHOWNUM (UNKN)
.proc TryShowNumber
    bit Running
    bpl GetByteMinusOne::Return
    stx SavedX
    bit Tracing
    jmp ShowNumber
.endproc

;; After a string assignment to a variable DSP marks: shows it, if a program is running.
;; In: X = the noun stack
;; Out: X = the noun stack, as it was
;; See: <ShowString>
;; Also: TRYSHOWSTR (UNKN)
.proc TryShowString
    bit Running
    bpl GetByteMinusOne::Return
    stx SavedX
    bit Tracing
    jmp ShowString
.endproc

.endscope

;; Reads the next byte of the line (<Interpreter::ReadNextByte>), with Y = 0.
;; Out: A = the byte, Y = 0
;; Keeps: X, carry
;; Also: GETVERB0 (UNKN)
.proc ReadNextLineByte
    ldy #0
    jmp Interpreter::ReadNextByte
.endproc

;; Moves down a line for <TabToColumn>, and takes the column less the window's width as the column on that line.
;; In: A = the column less the window's width
.proc TabNextLine
    tay
    jsr PrintReturn
    ; Falls into TabToColumn.
.endproc

;; Sets the cursor's column to Y, moving down a line for each window's width it passes.
;; In: Y = the column, from 0
;; Out: CursorColumn = the column on its line
;; See: <Statements::Tab>, <NextTabStop>
;; Also: SETCURCOL (UNKN)
.proc TabToColumn
    tya
    sec
    sbc WindowWidth
    bcs TabNextLine
    sty CursorColumn
    rts
.endproc

    ; Unused bytes.
    .byte $00, $00, $00, $FF, $FF, $FF, $FF

;; Stores Y as the high byte of the number just pushed, then ends as a left parenthesis does
;; (<Operators::LeftParenthesis>).
;; In: Y = the high byte, X = the noun stack
;; Also: HIBYTEPAREN (UNKN)
.proc StoreHighByteAndClose
    sty NounStackNumberHigh,x
    jmp Operators::LeftParenthesis
.endproc

.scope Display continued

;; Prints the string at <Auxiliary>, up to the byte with bit 7 clear that ends it, and sets <ReturnPending>.
;; In: Auxiliary = the string
;; Out: ReturnPending = $FF
;; Also: PRSTRAUX (UNKN)
.proc PrintStringAt
    ldy #0
    beq Next                        ; always

Print:
    jsr CharacterOut
    iny

Next:
    lda (Auxiliary),y
    bmi Print
    lda #$FF
    sta ReturnPending
    rts
.endproc

.endscope

; IN#.
.scope Statements continued

;; IN# (token $7F): takes input from slot n's ROM, or from the keyboard for 0.
;; In: X = the noun stack, its top entry the slot
;; Out: X = the noun stack, popped
;; Errors: >255
;; See: <SetInput>, <PrNumber>
;; Also: INSLOT (IBSM)
.proc InNumber
    jsr GetByte
    stx SavedX
    jsr SetInput
    ldx SavedX
    rts
.endproc

.endscope
