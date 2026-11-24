; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: OPERANDS, FUNCTIONS AND LOGICAL OPERATORS

;; Emits the operand parser and syntax checks preceding variable-value handling.
;; Parameters: piToken = 1 to accept the single-byte PI constant (the PET), bitwiseNot = 1 for signed 16-bit NOT (the
;;   PET), 0 for Boolean NOT (AppleSoft), functionEntry = the entry a function token goes to: <CallFunction>, or
;;   AppleSoft's SCRN check
.macro OperandEvaluation piToken, bitwiseNot, functionEntry
    .assert piToken = 0 || piToken = 1, "piToken is 0 or 1."
    .assert bitwiseNot = 0 || bitwiseNot = 1, "bitwiseNot is 0 or 1."

    ;; Evaluates a numeric constant, variable, string literal, parenthesized expression or function.
    ;;
    ;; A quoted literal falls into <ReadQuotedString>, a unary minus goes to <ApplyPrefixOperator>, and the other tokens
    ;; to <EvaluateTokenOperand>, which sends `NOT` to <ApplyPrefixOperator> and the rest to <EvaluateFunctionOperand>.
    ;; In: TextPointer = character preceding the operand
    ;; Out: Fac = value or string descriptor, ValueType = result type, TextPointer = terminating character
    ;; Also: EVAL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EvaluateOperand
    lda #$00
    sta ValueType
;; Reads the next character; a unary plus comes back here.
;; Also: EVAL0 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    jsr GetNextCharacter
    bcs NotDigit
;; Jumps to <Float::ReadNumber> for a digit or decimal point.
;; Also: EVAL1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToParseNumber:
    jmp Float::ReadNumber
;; Not a digit: a letter goes to the vendor's variable operand, <ISVAR>, and where `piToken` is 1 the `PI` token
;; loads pi.
;; Also: EVAL2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NotDigit:
    jsr IsLetter
    bcs ISVAR
    .if piToken
        cmp #<TOKEN_PI
        bne CheckPoint
        lda #<Pi
        ldy #>Pi
        jsr Float::LoadFac
        jmp GetNextCharacter

;; Five-byte floating-point approximation of pi used by the PI token.
;; Also: PIVAL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Pi:
        .byte $82, $49, $0F, $DA, $A1
    .endif
;; Checks for a decimal point, the minus and plus tokens and a quote.
;; Also: QDOT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckPoint:
    cmp #'.'
    beq ToParseNumber
    cmp #<TOKEN_MINUS
    beq ApplyMinus
    cmp #<TOKEN_PLUS
    beq NextCharacter
    cmp #'"'
    bne EvaluateTokenOperand
    ; Falls into ReadQuotedString.
    .endproc

    ;; Builds a descriptor for the quoted literal at <TextPointer> and advances past it.
    ;; In: TextPointer = the opening quote, carry = set (as the comparison that found the quote leaves it), so that
    ;;   adding it skips the quote
    ;; Also: STRTXT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReadQuotedString
    lda TextPointer
    ldy TextPointer+1
    adc #$00
    bcc HaveAddress
    iny
;; Text address in A/Y (carry from the quote added): makes the string and sets <TextPointer>.
;; Also: STRTX2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
HaveAddress:
    jsr Strings::FromText
    jmp SetTextPointer
    .endproc

    ;; An operand starting with a token: `NOT` goes to <ApplyPrefixOperator> with its table entry, others to
    ;; <EvaluateFunctionOperand>.
    ;; In: A = the token
    ;; Also: EVAL3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EvaluateTokenOperand
    cmp #<TOKEN_NOT
    bne EvaluateFunctionOperand
    ldy #<(OperatorTable::Not - OperatorTable)
    bne ApplyPrefixOperator
    .endproc

    .scope Operators continued

    ;; Applies `NOT` to <Fac>.
    ;;
    ;; Where `bitwiseNot` is 1 (the PET), the result is the signed 16-bit complement of the integer; where it is 0
    ;; (AppleSoft), it is 1 for zero and 0 otherwise.
    ;; In: Fac = the operand
    ;; Out: Fac = numeric result
    ;; Errors: ILLEGAL QUANTITY where `bitwiseNot` is 1 and the operand is outside -32768 to 32767
    ;; Also: NOTOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Not
    .if bitwiseNot
        jsr FacToInteger
        lda FacMantissa4
        eor #$FF
        tay
        lda FacMantissa3
        eor #$FF
        jmp ReturnSignedWord
    .else
        lda FacExponent
        bne LoadFalse
        ldy #$01
        .byte $2C                   ; BIT absolute skips the next two bytes
;; A nonzero operand: returns 0.
LoadFalse:
        ldy #$00
        jmp ReturnByte
    .endif
    .endproc
    .endscope

    ;; An operand starting with a token other than `NOT`: `FN` goes to <Functions::Fn>, a function token to
    ;; `functionEntry`, and any other token to <EvaluateParenthesized>, which requires a parenthesis.
    ;; In: A = the token
    ;; Also: EVAL4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EvaluateFunctionOperand
    cmp #<TOKEN_FN
    bne NotFn
    jmp Functions::Fn

;; Not `FN`: a token below the first function goes to <EvaluateParenthesized>.
NotFn:
    cmp #<TOKEN_FIRST_FUNCTION
    bcc EvaluateParenthesized
    jmp functionEntry
    .endproc

    ;; Requires an opening parenthesis, evaluates an expression, and requires the closing parenthesis.
    ;; Out: Fac = the value, ValueType = its type, A = the character after the parenthesis
    ;; Errors: SYNTAX for a missing parenthesis, and those of <EvaluateExpression>
    ;; Also: PARCHK (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc EvaluateParenthesized
    jsr CheckOpenParenthesis
    jsr EvaluateExpression
    ; Falls into CheckCloseParenthesis.
    .endproc

    ;; Requires and consumes a closing parenthesis.
    ;; Out: A = the next character, as <GetNextCharacter> returns it
    ;; Errors: SYNTAX if the character is not `)`
    ;; Also: CHKCLS (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc CheckCloseParenthesis
    lda #')'
    .byte $2C                   ; BIT absolute skips the next two bytes
    ; Falls into CheckOpenParenthesis, past its load.
    .endproc

    ;; Requires and consumes an opening parenthesis.
    ;; Out: A = the next character, as <GetNextCharacter> returns it
    ;; Errors: SYNTAX if the character is not `(`
    ;; Also: CHKOPN (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc CheckOpenParenthesis
    lda #'('
    .byte $2C                   ; BIT absolute skips the next two bytes
    ; Falls into CheckComma, past its load.
    .endproc

    ;; Requires and consumes a comma.
    ;; Out: A = the next character, as <GetNextCharacter> returns it
    ;; Errors: SYNTAX if the character is not a comma
    ;; Also: CHKCOM (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc CheckComma
    lda #','
    ; Falls into CheckCharacter.
    .endproc

    ;; Requires the character in A at <TextPointer>, then advances to the next character.
    ;; In: A = the character required
    ;; Out: A = the next character, as <GetNextCharacter> returns it, with its carry and zero
    ;; Errors: SYNTAX if the character does not match
    ;; Also: SYNCHR (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc CheckCharacter
    ldy #$00
    cmp (TextPointer),y
    bne SyntaxError
;; Jumps to <GetNextCharacter> after a match.
;; Also: CHRGO5 (M6502)
ToGetNextCharacter:
    jmp GetNextCharacter
    .endproc

    ;; Reports a syntax error.
    ;; Errors: SYNTAX
    ;; Also: SNERR (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc SyntaxError
    ldx #<ERROR_SYNTAX
    jmp ERROR
    .endproc

    ;; Selects the unary-minus entry of <OperatorTable> and falls into <ApplyPrefixOperator>.
    ;; Also: DOMIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ApplyMinus
    ldy #<(OperatorTable::Negation - OperatorTable)
    ; Falls into ApplyPrefixOperator.
    .endproc

    ;; Drops <EvaluateOperand>'s return address and jumps to <EvaluateExpression::Prefix> with Y = the operator's table
    ;; offset.
    ;; Also: GONPRC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ApplyPrefixOperator
    pla
    pla
    jmp EvaluateExpression::Prefix
    .endproc
.endmacro

;; Emits the integer-variable conversion path, falling through for floating-point variables.
.macro IntegerVariableValue
    ;; Loads an integer variable through <FacMantissa3> and converts it to floating point.
    ;; For a real variable it returns nothing: the code after it, in the vendor's file, loads the value.
    ;; In: IntegerType = negative for an integer variable, FacMantissa3 = the value's address (low byte),
    ;;   FacMantissa4 = its high byte
    ;; Out: Fac = numeric value for an integer variable
    ;; Also: GOOO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc LoadNumericVariable
    ldx IntegerType
    bpl NotInteger
    ldy #$00
    lda (FacMantissa3),y
    tax
    iny
    lda (FacMantissa3),y
    tay
    txa
    jmp ReturnSignedWord
;; A real variable: goes on into the vendor's code that loads it.
;; Also: GOOOOO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NotInteger:
    .endproc
.endmacro

;; Emits the built-in function argument parser and dispatcher.
.macro FunctionDispatch
    ;; Parses a built-in function's arguments and dispatches through <FUNDSP>.
    ;;
    ;; The string slicing functions take a string and a byte argument; their descriptors and arguments are
    ;; stacked for the callee. Ordinary functions take one parenthesized expression.
    ;; Also: ISFUN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CallFunction
    asl a
    pha
    tax
    jsr GetNextCharacter
    cpx #<(2*TOKEN_LAST_SIMPLE_FUNCTION-255)
    bcc OneArgument
    jsr CheckOpenParenthesis
    jsr EvaluateExpression
    jsr CheckComma
    jsr RequireString
    pla
    tax
    lda FacMantissa4
    pha
    lda FacMantissa3
    pha
    txa
    pha
    jsr EvaluateByte
    pla
    tay
    txa
    pha
    jmp Dispatch
;; Ordinary function: evaluates the parenthesized argument.
;; Also: OKNORM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
OneArgument:
    jsr EvaluateParenthesized
    pla
    tay
;; Stores the routine's address from <FUNDSP> in <FunctionJump>, calls it, then requires a numeric result.
;; Also: FINGO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Dispatch:
    lda FUNDSP-2*TOKEN_FIRST_FUNCTION+256,y
    sta FunctionJump+1
    lda FUNDSP-2*TOKEN_FIRST_FUNCTION+257,y
    sta FunctionJump+2
    jsr FunctionJump
    jmp RequireNumber
    .endproc
.endmacro

;; Emits the variant's OR and AND entries.
;; Parameters: bitwise = 1 for signed 16-bit operations, 0 for Boolean zero-or-one results
.macro LogicalOperators bitwise
    .assert bitwise = 0 || bitwise = 1, "bitwise is 0 or 1."

    .scope Operators continued

    .if bitwise
        ;; Computes OR on the numeric argument and <Fac>.
        ;; Out: Fac = numeric result
        ;; Errors: ILLEGAL QUANTITY if an operand is outside -32768 to 32767
        ;; Also: OROP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
        .proc Or
        ldy #$FF
        .byte $2C                   ; BIT absolute skips the next two bytes
        ; Falls into And.
        .endproc

        ;; Computes signed 16-bit AND on the numeric argument and <Fac>.
        ;;
        ;; Its old name names a different routine in each vendor's builds, so each vendor's historical names file gives
        ;; it (Basic.md E4).
        ;; Out: Fac = numeric result
        ;; Errors: ILLEGAL QUANTITY if an operand is outside -32768 to 32767
        .proc And
        ldy #$00
        sty Counter
        jsr FacToInteger
        lda FacMantissa3
        eor Counter
        sta SmallInteger
        lda FacMantissa4
        eor Counter
        sta SmallInteger+1
        jsr Float::CopyArgToFac
        jsr FacToInteger
        lda FacMantissa4
        eor Counter
        and SmallInteger+1
        eor Counter
        tay
        lda FacMantissa3
        eor Counter
        and SmallInteger
        eor Counter
        jmp ReturnSignedWord
        .endproc
    .else
        ;; Computes Boolean OR on the numeric argument and <Fac>.
        ;; Out: Fac = zero or one
        ;; Also: OROP (M6502)
        .proc Or
        lda ArgExponent
        ora FacExponent
        bne And::LoadTrue
        ; Falls into And.
        .endproc

        ;; Computes Boolean AND on the numeric argument and <Fac>.
        ;; Out: Fac = zero or one
        ;; Entry:
        ;;   LoadTrue = returns 1; <Operators::Or> branches here when either operand is nonzero
        .proc And
        lda ArgExponent
        beq LoadFalse
        lda FacExponent
        bne LoadTrue
;; A zero operand: returns 0.
LoadFalse:
        ldy #$00
        .byte $2C                   ; BIT absolute skips the next two bytes
;; Returns 1; <Operators::Or> branches here when either operand is nonzero.
LoadTrue:
        ldy #$01
        jmp ReturnByte
        .endproc
    .endif
    .endscope

.endmacro
