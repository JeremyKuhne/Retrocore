; retrocore: style=strict
;; The second half of the formula evaluator: the end of <EvaluateExpression>'s operator step (<Operators::Apply>), one
;; operand (<EvaluateOperand>: a constant, a variable, a string literal, a function, a reserved-word value, `NOT`, unary
;; minus or a formula in parentheses), the syntax checks such as <CheckComma>, the function dispatch (<CallFunction>),
;; `AND` and `OR`, and the relational operators for numbers and strings (<ApplyRelation>).
;;
;; As the evaluator holds them, <ValueType> is <VALUE_TYPE_REAL> for a real, <VALUE_TYPE_LONG_INTEGER> for a long
;; integer and <VALUE_TYPE_STRING> for a string; <VALUE_TYPE_ANY> before a formula asks for any type. A real or an
;; integer variable's value is a real in the <Fac>, unpacked; a long integer is eight bytes from <Fac>, two's
;; complement, high byte first; a string is a pointer to its descriptor in <FacMantissa3>, <FacMantissa3>+1 and
;; <FacMantissa3XByte>.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; EvaluateExpression's operator step, continued
; ---------------------------------------------------------------------------------------------------------------------

;; BASIC's operators, and the step of <EvaluateExpression> that applies them; the scope is in pieces through the
;; files.
.scope Operators

;; Does a binary operator, for <EvaluateExpression>: with the operator's left operand in <Arg> and its right in the
;; <Fac>, calls the operator's routine from <OperatorRoutineTable>, then goes on with the formula.
;;
;; <EvaluateExpression>'s <EvaluateExpression::PopOperand>, in B3InpuF.asm, pulls the operands and the operator and
;; falls in here with the operator in A and in <RelationMask>. Each relational operator (1 to 7, its bits) takes the
;; first dispatch entry, <ApplyRelation>; each other operator an entry of its own. A long integer's entries follow the
;; reals' in <OperatorRoutineTable>, <OPERATOR_LONG_ROUTINES> bytes on. For strings only `+` (whose offset is
;; <OPERATOR_LONG_ROUTINES>, as the last of the reals' entries) and the relational operators are allowed.
;; In: A = the operator's number, RelationMask = the same, Arg = the left operand, Fac = the right one, ValueType =
;;   their type, the stack = the operator that ended the operand, which <EvaluateExpression::PopOperand> pushed
;; Errors: <ERROR_SYNTAX> = a string operator other than `+` or a relational one
;; Entry:
;;   Continue = pulls the operator <EvaluateExpression::PopOperand> pushed and goes on with the formula at
;;   <EvaluateExpression::WithOperator>
;;   ToSyntaxError = jumps to <SyntaxError>; <EvaluateOperand> branches here for a constant with no digits
.proc Apply
    sec
    sbc #6
    cmp #1
    bpl HaveIndex
    lda #1                                  ; a relational operator: the first entry
HaveIndex:
    asl
    tax
    bit ValueType                           ; a string or a long integer needs more care
    bmi StringOperands
    clc
    bvc NotLongInteger                      ; a real
    adc #OPERATOR_LONG_ROUTINES             ; a long integer: use the long-integer entries
    tax
    bcc Dispatch

;; Works out the sign of a real product or quotient, for the operator's routine.
;; Also: NOTDBLP (BB13)
NotLongInteger:
    lda ArgSign
    eor FacSign
    sta ResultSign

;; Calls the operator's routine, with A = the <Fac>'s exponent and zero set for a zero <Fac>, as the routines expect.
;; Also: RDY2GO (BB13)
Dispatch:
    lda OperatorRoutineTable-2,X
    sta FunctionJump+1
    lda OperatorRoutineTable-1,X
    sta FunctionJump+2
    lda FacExponent
    jsr FunctionJump

;; Pulls the operator that ended the operand back off the stack and goes on with the formula at
;; <EvaluateExpression::WithOperator>.
;; Also: FRMEV3 (BB13)
Continue:
    pla
    jmp EvaluateExpression::WithOperator

;; Takes a binary operator on two strings: `+` concatenates them and a relational operator compares them; any other is
;; a syntax error.
;; Also: ASTRNG (BB13)
StringOperands:
    cmp #OPERATOR_LONG_ROUTINES             ; +?
    beq JoinStrings
    cmp #2*OPERATOR_RELATIONAL_ENTRY        ; a relational operator?
    beq NotLongInteger

;; Ends the statement with a syntax error.
;; Also: EVALER (BB13)
ToSyntaxError:
    jmp SyntaxError

;; Concatenates the two strings, then goes on with the formula.
;; Also: PLUSOK (BB13)
JoinStrings:
    jsr Strings::Concatenate
    jmp Continue
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; One operand
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates one operand from the program text into the <Fac>: a number, a string, a variable, a function's result, or
;; a formula in parentheses.
;;
;; A digit or a period starts a constant, which is read as a long integer when <ValueType> asks for one (or for a
;; string, which gives a type mismatch later), and as a real otherwise.
;; In: TextPointer = the character before the operand, ValueType = the type the formula wants
;; Out: Fac = the value, ValueType = its type, TextPointer = the first character after the operand
;; Errors: <ERROR_SYNTAX> = a constant with no digits, or what can't start an operand
;; See: <EvaluateExpression>, <EvaluateVariable>, <CallFunction>
;; Also: EVAL (BB13)
.proc EvaluateOperand
    jsr GetNextCharacter
    bcs NotDigit

;; Reads a numeric constant: a long integer with <LongInteger::ReadNumber> when <ValueType> is above <VALUE_TYPE_ANY>,
;; or a real with <Float::ReadNumber>.
;; Also: ACONSTNT (BB13)
ReadConstant:
    lda ValueType
    cmp #VALUE_TYPE_ANY+1
    bcc ReadReal
    jmp LongInteger::ReadNumber

;; Reads a real constant with <Float::ReadNumber>, ending the statement with a syntax error when it has no digits.
;; Also: RLBNY (BB13)
ReadReal:
    lda #VALUE_TYPE_REAL
    sta ValueType
    jsr Float::ReadNumber
    bit DigitsSeen                          ; $FF when Float::ReadNumber found no digits
    bmi Operators::Apply::ToSyntaxError
    rts

;; Takes an operand that does not start with a digit: an escape token, a reserved word, a variable, a period, a plus,
;; a string literal, a minus or an opening parenthesis.
;; Also: EVAL1 (BB13)
NotDigit:
    cmp #TOKEN_ESCAPE                             ; a function, `FN` or `NOT`
    beq EvaluateEscapeToken
    cmp #TOKEN_END                          ; a reserved word
    bcs EvaluateReservedWord
    jsr IsLetter
    bcc NotVariable
    jmp EvaluateVariable

;; Takes an operand that is not a variable: a constant that starts with a period, a unary plus, which is skipped, a
;; string literal, or <EvaluateMinusOrParentheses>'s minus and parenthesis.
;; Also: NOVAR (BB13)
NotVariable:
    cmp #'.'
    beq ReadConstant
    cmp #'+'
    beq EvaluateOperand
    cmp #'"'
    bne EvaluateMinusOrParentheses
    ; Falls into ReadQuotedString.
.endproc

;; Makes a temporary string of the literal after the quote at <TextPointer>, then moves <TextPointer> past its closing
;; quote.
;; In: TextPointer = the opening quote, carry = set, as the comparison that found the quote leaves it
;; Out: Fac = the string, TextPointer = past the closing quote
;; See: <Strings::FromText>, <SetTextPointer>
;; Also: STRTXT (BB13)
.proc ReadQuotedString
    lda TextPointer
    ldx TextPointerXByte
    ldy TextPointer+1
    adc #0                                  ; the carry is set: one past the quote
    bcc HaveAddress
    iny
    cpy #POINTER_PAGE_LIMIT
    bcc HaveAddress
    inx                                     ; past the bank's last page: page POINTER_PAGE_FIRST of the next
    ldy #POINTER_PAGE_FIRST

;; Makes the literal at A, Y and bank X a temporary string, then moves <TextPointer> past it.
;; Also: STRTX2 (BB13)
HaveAddress:
    jsr Strings::FromText
    jmp SetTextPointer
.endproc

.scope Operators continued

;; Takes `NOT`, evaluating the one operand that follows: gives 1 when it is zero, or 0 when it is not, as a long
;; integer for a long integer and as a real otherwise.
;;
;; `NOT` applies to the next operand alone, not to a formula, so `NOT A = B` is `(NOT A) = B`. A string is not caught
;; here: its <ValueType> takes the long integer's path.
;; In: TextPointer = the character after the token
;; Out: Fac = 1 or 0
;; See: <Operators::NotLongInteger>
;; Also: NOTDO (BB13)
.proc Not
    jsr BackUpTextPointer                   ; so EvaluateOperand's GetNextCharacter reads the operand's first character
    jsr EvaluateOperand
    bit ValueType
    bvc Real
    jmp NotLongInteger
Real:
    lda FacExponent
    beq ReturnOne
    ldy #0
    .byte $2C                               ; BIT absolute skips ReturnOne's LDY

;; Gives 1, for a zero operand, as a real.
;; Also: RLONE (BB13)
ReturnOne:
    ldy #1
    jmp ReturnByte
.endproc

.endscope

;; Takes a unary minus, or else expects a formula in parentheses.
;; In: A = the operand's first character
;; See: <ApplyMinus>, <EvaluateParenthesized>
;; Also: EVAL3 (BB13)
.proc EvaluateMinusOrParentheses
    cmp #'-'
    beq ApplyMinus
    jmp EvaluateParenthesized
.endproc

;; Takes an escape token: reads the byte after it and moves <TextPointer> past both, then goes to <CallFunction> with
;; the byte.
;; Also: PARC22 (BB13)
.proc EvaluateEscapeToken
    jsr GetNextCharacter
    tax
    jsr GetNextCharacter
    txa
    jmp CallFunction
.endproc

;; Takes a reserved word that gives a value with no arguments, such as `ERR` or `TIME$`, through <ValueWordTable>; any
;; other reserved word is a syntax error.
;; In: A = the token
;; Errors: <ERROR_SYNTAX> = a reserved word that gives no value
;; See: <ValueWordTable>
;; Also: PARC23 (BB13)
.proc EvaluateReservedWord
    cmp #TOKEN_FRE
    bcc ApplyMinus::ToSyntaxError
    cmp #TOKEN_POP
    bcs ApplyMinus::ToSyntaxError
    asl
    tax
    jsr GetNextCharacter
    lda ValueWordTable-TOKEN_FRE-TOKEN_FRE+256,X ; the token less TOKEN_FRE, times two
    sta FunctionJump+1
    lda ValueWordTable-TOKEN_FRE-TOKEN_FRE+257,X
    sta FunctionJump+2
    jmp FunctionJump
.endproc

;; Reads the cursor's position from the console into <Console::CursorColumn> and <Console::CursorLine>, with a SOS
;; D_STATUS call.
;; Out: Y = the cursor's line, from <Console::CursorLine>
;; See: <Console::CursorParameters>, <Functions::VPos>, <Functions::Pos>
;; Also: VPOS (BB13)
.proc ReadCursorPosition
    brk
    .byte SOS_DEVICE_STATUS
    .word Console::CursorParameters
    ldy Console::CursorLine
    rts
.endproc

;; BASIC's functions, named for their keywords (`Functions::Left`, `Functions::Conv`), and the parts they share; the
;; scope is in pieces through the files.
.scope Functions

;; The value of `ERRLIN`: the line number of the last error, from <ErrorLine>.
;; Out: Fac = the line number, as a real
;; Also: DOERRLN (BB13)
.proc ErrLin
    lda ErrorLine+1
    ldy ErrorLine
    sta FacMantissa1
    sty FacMantissa1+1
    ldx #Float::WORD_EXPONENT
    sec                                     ; positive
    jmp Float::ConvertWord
.endproc

;; The value of `OUTREC`: the column at which `LIST` wraps its lines (0 for none), from <OutputRecordLength>.
;; Out: Fac = the column, as a real
;; Also: GIVOUTREC (BB13)
.proc OutRec
    ldy OutputRecordLength
    jmp ReturnByte
.endproc

;; The value of `INDENT`: the indent `LIST` uses, from <ListIndent>.
;; Out: Fac = the indent, as a real
;; Also: GIVINDENT (BB13)
.proc Indent
    ldy ListIndent
    jmp ReturnByte
.endproc

;; The value of `KBD`: the last key read on an interrupt, from <LastKey>.
;; Out: Fac = the key, as a real
;; Also: GIVKBD (BB13)
.proc Kbd
    ldy LastKey
    jmp ReturnByte
.endproc

;; The value of `EOF`: the file number of the last end of file, from <EndOfFileNumber>.
;; Out: Fac = the file number, as a real
;; Also: GIVEOF (BB13)
.proc Eof
    ldy EndOfFileNumber
    .byte $2C                               ; BIT absolute skips Err's LDY
    ; Falls into Err, past its load.
.endproc

;; The value of `ERR`: the number of the last error, from <ErrorCode>.
;; Out: Fac = the error number, as a real
;; Also: GIVERR (BB13)
.proc Err
    ldy ErrorCode
    jmp ReturnByte
.endproc

.endscope

.scope Operators continued

;; Finishes `NOT` for a long integer: 1 when all eight bytes of the <Fac> are zero, 0 otherwise.
;;
;; X is not set: <LongInteger::IsZero> takes it as the bank of the <Fac>'s address, and it holds whatever
;; <EvaluateOperand> left. An X-byte with bit 7 clear reads page zero, as meant; <Statements::If> clears X before the
;; same call.
;; Out: Fac = 1 or 0, as a long integer
;; See: <Operators::Not>, <LongInteger::IsZero>
;; Also: BCDTSTR (BB13)
.proc NotLongInteger
    lda #<(Fac)
    ldy #>(Fac)
    jsr LongInteger::IsZero
    beq ReturnOne
    jmp LongInteger::SetFacToZero

;; Gives 1 as a long integer, for a zero operand.
;; Also: ISFALS (BB13)
ReturnOne:
    jmp LongInteger::SetFacToOne
.endproc

.endscope

;; Takes a unary minus, evaluating the one operand that follows and negating it, as a long integer or a real.
;;
;; A string is not caught here: its <ValueType> takes the long integer's path.
;; Out: Fac = the negated operand
;; Entry:
;;   ToSyntaxError = jumps to <SyntaxError>; <EvaluateReservedWord> branches here for a reserved word with no value
;; See: <LongInteger::NegateFac>, <Float::Negate>
;; Also: DOMIN (BB13)
.proc ApplyMinus
    jsr EvaluateOperand
    bit ValueType
    bvc NegateReal                          ; a real
    jmp LongInteger::NegateFac

;; Negates the real in the <Fac>.
;; Also: CHGSGN (BB13)
NegateReal:
    jmp Float::Negate

;; Ends the statement with a syntax error.
;; Also: SNERR6 (BB13)
ToSyntaxError:
    jmp SyntaxError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Parentheses and syntax checks
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a formula that ends at a closing parenthesis or another delimiter, keeping the operators before it.
;;
;; A zero precedence on the verb stack, <OperatorStack>, stops <EvaluateExpression> from taking an operator from outside
;; the formula.
;; In: TextPointer = the formula's first character, ValueType = the type wanted
;; Out: Fac = the value, ValueType = its type
;; Errors: <ERROR_FORMULA_TOO_COMPLEX> = the verb stack is full
;; See: <EvaluateExpression::KeepingStacks>, <FormulaTooComplexError>
;; Also: DOPAR (BB13)
.proc EvaluateSubexpression
;; The bytes of <OperatorStack>, two for each operator held.
VERB_STACK_SIZE = 32

    .assert EndOfFileHandlers - OperatorStack = VERB_STACK_SIZE, "VERB_STACK_SIZE must be VRBSTK's size."

    lda #0
    ldy OperatorStackTop
    iny
    sta OperatorStack,Y                     ; precedence 0
    iny
    sty OperatorStackTop
    cpy #VERB_STACK_SIZE                    ; too deep
    bcs FormulaTooComplexError
    jsr EvaluateExpression::KeepingStacks
    dec OperatorStackTop
    dec OperatorStackTop
    rts
.endproc

;; Evaluates a formula in parentheses.
;; In: TextPointer = the opening parenthesis
;; Out: Fac = the value, ValueType = its type, A = the character after the closing parenthesis
;; Errors: <ERROR_SYNTAX> = a missing parenthesis
;; Entry:
;;   AfterOpen = evaluates the formula after an opening parenthesis already read, and its closing parenthesis;
;;     <CallFunction> enters here for a function's argument
;; See: <EvaluateSubexpression>, <CheckCloseParenthesis>
;; Also: PARCHK (BB13)
.proc EvaluateParenthesized
    jsr CheckOpenParenthesis

;; Evaluates a formula and its closing parenthesis.
;; Also: PARCHK2 (BB13)
AfterOpen:
    jsr EvaluateSubexpression
    ; Falls into CheckCloseParenthesis.
.endproc

;; Checks for a closing parenthesis and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not a closing parenthesis
;; See: <CheckCharacter>
;; Also: CHKCLS (BB13)
.proc CheckCloseParenthesis
    lda #')'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckSemicolon, past its load.
.endproc

;; Checks for a semicolon and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not a semicolon
;; Also: CHKSMC (BB13)
.proc CheckSemicolon
    lda #';'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckEquals, past its load.
.endproc

;; Checks for an equals sign and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not an equals sign
;; Also: CHKEQL (BB13)
.proc CheckEquals
    lda #'='
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckNumberSign, past its load.
.endproc

;; Checks for a number sign and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not a number sign
;; Also: CHKPND (BB13)
.proc CheckNumberSign
    lda #'#'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckOpenParenthesis, past its load.
.endproc

;; Checks for an opening parenthesis and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not an opening parenthesis
;; Also: CHKOPN (BB13)
.proc CheckOpenParenthesis
    lda #'('
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckComma, past its load.
.endproc

;; Checks for a comma and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = not a comma
;; Also: CHKCOM (BB13)
.proc CheckComma
    lda #','
    ; Falls into CheckCharacter.
.endproc

;; Checks that the character at <TextPointer> is A and moves past it, or ends the statement with a syntax error.
;; In: A = the character
;; Out: A = the next character, as from <GetNextCharacter>
;; Errors: <ERROR_SYNTAX> = a different character
;; Also: SYNCHR (BB13)
.proc CheckCharacter
    ldy #0
    cmp (TextPointer),Y
    bne SyntaxError
    jmp GetNextCharacter
.endproc

;; Ends the statement with FORMULA TOO COMPLEX.
;; Errors: <ERROR_FORMULA_TOO_COMPLEX>
;; Also: CMPLXERR (BB13)
.proc FormulaTooComplexError
    ldx #ERROR_FORMULA_TOO_COMPLEX
    jmp ReportError
.endproc

;; Ends the statement with SYNTAX ERROR.
;; Errors: <ERROR_SYNTAX>
;; Also: SNERR (BB13)
.proc SyntaxError
    ldx #ERROR_SYNTAX
    jmp ReportError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a variable's value into the <Fac>; an array that does not exist yet is not made.
;; In: TextPointer = the variable's name
;; Out: Fac = the value, <ValueType> and IntegerType = its type, TextPointer = past the name and any subscripts
;; Entry:
;;   AtAddress = takes the value of the variable at A, Y and bank X; `READ#` calls it from
;;   <Statements::ReadFile::TakeItem>
;; See: <FindVariable::ForExpression>
;; Also: ISVAR (BB13)
.proc EvaluateVariable
    ldx #$FF                                ; not to make an array
    jsr FindVariable::ForExpression
    ldx VariablePointerXByte

;; Takes the value of the variable at A, Y and bank X into the <Fac>, by its type: a long integer's eight bytes, a
;; real, an integer floated to a real, or, for a string, the pointer to its descriptor.
;; In: A, Y = the variable's address, X = its bank, <ValueType> and IntegerType = its type
;; Out: FacMantissa3, FacMantissa3+1, FacMantissa3XByte = the variable's address
;; See: <LongInteger::LoadFac>, <Float::LoadFac>, <ReturnSignedWord>
;; Also: ISVRET2 (BB13)
AtAddress:
    sta FacMantissa3
    sty FacMantissa3+1
    stx FacMantissa3XByte
    bit ValueType
    bvc LoadNumericVariable                 ; a real or an integer
    bpl LongIntegerVariable                 ; a long integer
    ldx #0                                  ; a string: FacMantissa3 points to its descriptor
    stx FacExtension
    rts

;; Copies a long integer variable's eight bytes into the <Fac>.
;; Also: DBLVAR (BB13)
LongIntegerVariable:
    jmp LongInteger::LoadFac
.endproc

;; Moves <TextPointer> back one character.
;;
;; At the start of a page it steps the page back, then calls <Memory::WrapPage>, which only brings a page past the
;; window down. So backing up from the first byte of an X-byte's window (page <POINTER_PAGE_FIRST>) leaves page 1, which
;; banked pointers cannot reach, where <Memory::PreviousPage> would have gone on at the last page of the X-byte before:
;; a bug of the original, which matters only for program text that crosses from one X-byte to the next.
;; Uses: A, Y
;; Keeps: X
;; Also: DECTPT (BB13)
.proc BackUpTextPointer
    txa
    pha
    lda TextPointer
    bne SamePage                            ; the page stays
    dec TextPointer+1
    ldx TextPointerXByte
    ldy TextPointer+1
    jsr Memory::WrapPage
    stx TextPointerXByte
    sty TextPointer+1

;; Steps the low byte back.
;; Also: DECTP1 (BB13)
SamePage:
    dec TextPointer
    pla
    tax
    rts
.endproc

;; Takes a real or an integer variable's value into the <Fac>.
;; In: FacMantissa3 = the variable's address, IntegerType = $80 for an integer
;; Out: Fac = the value
;; Entry:
;;   FloatInteger = floats the integer variable at <FacMantissa3>; `NEXT` calls it from <Statements::Next::AddStep> for
;;   an integer loop variable
;; See: <Float::LoadFac>
;; Also: GOOO (BB13)
.proc LoadNumericVariable
    bit IntegerType
    bpl NotInteger

;; Floats an integer variable, its high byte first, into the <Fac>.
;; See: <ReturnSignedWord>
;; Also: GOOO2 (BB13)
FloatInteger:
    ldy #0
    lda (FacMantissa3),Y
    tax
    iny
    lda (FacMantissa3),Y
    tay
    txa
    jmp ReturnSignedWord

;; Unpacks a real variable into the <Fac>.
;; Also: GOOOOO (BB13)
NotInteger:
    jmp Float::LoadFac
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Functions
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a function's escape token: `FN`, `NOT`, or a function from <FunctionTable>.
;;
;; A function before <TOKEN_LEN> takes a number, one up to <TOKEN_CONV> a string, and `CONV` and its kin any type; each
;; reads its argument in parentheses. Those past <TOKEN_LAST_SIMPLE_FUNCTION> (`LEFT$`, `RIGHT$`, `MID$` and `INSTR`)
;; take a string, then `INSTR` another, then a byte; <CallFunction::Builtin> pushes their strings' descriptor pointers
;; and the byte for the function to pull, and the function checks for its closing parenthesis.
;; In: A = the byte after the escape token, TextPointer = the character after it
;; Errors: <ERROR_SYNTAX> = a token that is no function
;; See: <FunctionTable>, <Functions::Fn>, <Operators::Not>
;; Also: ISFUN (BB13)
.proc CallFunction
    cmp #TOKEN_FIRST_FUNCTION
    bcs Builtin
    cmp #TOKEN_FN
    bne NotFn
    jmp Functions::Fn
NotFn:
    cmp #TOKEN_NOT
    bne SyntaxError
    jmp Operators::Not

;; Reads the arguments of a function from <FunctionTable> and calls it.
;;
;; For `LEFT$`, `RIGHT$`, `MID$` and `INSTR`, the stack holds, from the top: the byte argument, then the descriptor
;; pointer of each string, low byte, high byte and bank, the last string first. `INSTR`'s byte is 1 when it is left
;; out.
;; Also: GOODFUN (BB13)
Builtin:
    asl
    pha
    tax
    cpx #2*TOKEN_LAST_SIMPLE_FUNCTION-256+1
    bcc OneArgument                         ; one argument
    lda #VALUE_TYPE_STRING
    sta ValueType
    jsr EvaluateSubexpression               ; the string
    jsr CheckComma
    pla                                     ; the function
    tax
    lda FacMantissa3XByte
    pha
    lda FacMantissa3+1
    pha
    lda FacMantissa3
    pha
    txa
    pha                                     ; on the stack, as the arguments may hold functions too
    cmp #2*TOKEN_INSTR-256
    bne ReadByteArgument
    lda #VALUE_TYPE_STRING                  ; `INSTR`: the string to look for
    sta ValueType
    jsr EvaluateSubexpression
    pla
    tax
    lda FacMantissa3XByte
    pha
    lda FacMantissa3+1
    pha
    lda FacMantissa3
    pha
    txa
    pha
    jsr GetCurrentCharacter
    cmp #','
    beq SkipComma
    ldx #1                                  ; no start: 1
    bne HaveByte                            ; always

;; Moves past the comma before the byte argument.
;; Also: NORMFUN (BB13)
SkipComma:
    jsr GetNextCharacter

;; Reads the byte argument, then calls the function with it on the stack.
;; Also: NORMFN2 (BB13)
ReadByteArgument:
    jsr EvaluateByte
HaveByte:
    pla
    tay
    txa
    pha
    jmp Dispatch

;; Reads a one-argument function's argument in parentheses, of the type the function takes, then calls it.
;; Also: OKNORM (BB13)
OneArgument:
    cpx #2*TOKEN_LEN-256
    bcc NumericArgument                     ; a number
    cpx #2*TOKEN_CONV-256
    bcc StringArgument                      ; a string
    lda #VALUE_TYPE_ANY                     ; `CONV` and its kin: any type
    .byte $2C                               ; BIT absolute skips the next LDA

;; Wants a string argument.
;; Also: ISASTRNG (BB13)
StringArgument:
    lda #VALUE_TYPE_STRING
    .byte $2C                               ; BIT absolute skips the next LDA

;; Wants a numeric argument, then reads the argument.
;; Also: ISABIN (BB13)
NumericArgument:
    lda #VALUE_TYPE_REAL
    sta ValueType
    jsr EvaluateParenthesized::AfterOpen
    pla
    tay

;; Calls the function from <FunctionTable>.
;; In: Y = the function's token times two
;; Also: FINGO (BB13)
Dispatch:
    lda FunctionTable-TOKEN_FIRST_FUNCTION-TOKEN_FIRST_FUNCTION+256,Y
    sta FunctionJump+1
    lda FunctionTable-TOKEN_FIRST_FUNCTION-TOKEN_FIRST_FUNCTION+257,Y
    sta FunctionJump+2
    jmp FunctionJump
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Logical and relational operators
; ---------------------------------------------------------------------------------------------------------------------

.scope Operators continued

;; Takes `OR`, giving 1 when either real is nonzero, 0 otherwise.
;; In: Arg, Fac = the operands
;; Out: Fac = 1 or 0, as a real
;; Also: OROP (BB13)
.proc Or
    lda ArgExponent
    ora FacExponent
    bne And::LoadTrue
    ; Falls into And.
.endproc

;; Takes `AND`, giving 1 when both reals are nonzero, 0 otherwise.
;; In: Arg, Fac = the operands
;; Out: Fac = 1 or 0, as a real
;; Entry:
;;   LoadFalse = gives 0 as a real; <LongInteger::ToReal> jumps here for a zero long integer
;;   LoadTrue = gives 1 as a real; <Operators::Or> branches here when either operand is nonzero
;; Also: ANDOP (BB13)
.proc And
    lda ArgExponent
    beq LoadFalse
    lda FacExponent
    bne LoadTrue

;; Gives 0 as a real.
;; Also: GIVE0 (BB13)
LoadFalse:
    ldy #0
    .byte $2C                               ; BIT absolute skips LoadTrue's LDY

;; Gives 1 as a real.
;; Also: GIVE1 (BB13)
LoadTrue:
    ldy #1
    jmp ReturnByte
.endproc

.endscope

;; Compares <Arg> with the <Fac>, reals or strings, and gives 1 when the relation in <RelationMask> holds, 0 when not.
;;
;; <RelationMask> has a bit for each part of the operator: 1 for greater, 2 for equal and 4 for less. Strings compare
;; character by character, and a shorter string that matches the start of a longer one is less. Both strings'
;; temporaries are freed.
;; In: Arg = the left operand, Fac = the right one
;; Out: Fac = 1 or 0, as a real, ValueType = 0
;; See: <Float::CompareArg>, <Strings::ReleaseFac>
;; Also: DOREL (BB13)
.proc ApplyRelation
    bit ValueType
    bmi CompareStrings
    jsr Float::CompareArg
    tax
    jmp NumberResult

;; Compares two strings.
;; Also: STRCMP (BB13)
CompareStrings:
    jsr Strings::ReleaseFac                 ; the right string
    php                                     ; whether its temporary was freed
    sta NewDescriptor                       ; its length
    stx NewDescriptor+1
    sty NewDescriptor+2
    lda Pointer1XByte
    sta NewDescriptorXByte
    lda ArgMantissa3
    ldy ArgMantissa3+1                      ; the left string
    ldx ArgMantissa3XByte
    jsr Strings::ReleaseDescriptor
    php
    stx ArgMantissa3
    sty ArgMantissa3+1
    ldx Pointer1XByte
    stx ArgMantissa3XByte
    tax
    pha                                     ; its length
    sec
    sbc NewDescriptor                       ; which is longer?
    beq SetLengthOrder
    lda #1                                  ; the left is shorter: less
    bcc SetLengthOrder
    ldx NewDescriptor                       ; the left is longer: compare the right's length
    lda #$100-1

;; Keeps the result the lengths give, for when the shorter string matches the start of the longer.
;; Also: STASGN (BB13)
SetLengthOrder:
    sta FacSign
    ldy #$FF
    inx

;; Compares the next character, or takes the lengths' result when there are no more.
;; Also: NXTCMP (BB13)
NextByte:
    iny
    dex
    bne CompareByte
    ldx FacSign

;; Turns a comparison result in X, -1, 0 or 1, into the relation's bit, with the carry set for -1.
;; Also: QCOMP (BB13)
NumberResult:
    bmi ApplyMask                           ; the carry is set for -1
    clc
    bcc ApplyMask                           ; always

;; Compares one character of the two strings.
;; Also: GETCMP (BB13)
CompareByte:
    lda (ArgMantissa3),Y
    cmp (NewDescriptor+1),Y
    beq NextByte
    ldx #$100-1                             ; the left is greater
    bcs ApplyMask
    ldx #1                                  ; the left is less

;; Turns the comparison's result into 1 or 0 by the relation in <RelationMask>.
;; In: X = $FF when the left is greater, 0 when equal, 1 when less, carry = set for $FF
;; Also: DOCMP (BB13)
ApplyMask:
    inx                                     ; -1, 0 and 1 become bits 1, 2 and 4
    txa
    rol
    and RelationMask
    beq FreeStrings
    lda #1

;; Frees the two strings' space after a string comparison, then floats the result.
;; Also: GOFLOT (BB13)
FreeStrings:
    bit ValueType
    bpl ToFloat                             ; numbers
    sta CollectorStep                       ; the result
    lda #VALUE_TYPE_REAL
    sta ValueType
    pla                                     ; the left string's length
    ldx ArgMantissa3
    ldy ArgMantissa3+1
    stx Pointer1
    sty Pointer1+1
    ldx ArgMantissa3XByte
    stx Pointer1XByte
    plp                                     ; whether the left's temporary was freed
    jsr Strings::FreeSpaceIfReleased
    plp                                     ; whether the right's was
    jsr Strings::FreeFacIfReleased
    lda CollectorStep

;; Floats the comparison's result, 1 or 0.
;; Also: GFLOT1 (BB13)
ToFloat:
    jmp Float::ConvertSignedByte
.endproc
