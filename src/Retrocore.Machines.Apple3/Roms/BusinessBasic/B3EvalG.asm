; retrocore: style=strict
;; The second half of the formula evaluator: the end of <FRMEVL>'s operator step (<Operators::Apply>), one operand
;; (<EvaluateOperand>: a constant, a variable, a string literal, a function, a reserved-word value, `NOT`, unary minus
;; or a formula in parentheses), the syntax checks such as <CheckComma>, the function dispatch (<CallFunction>), `AND`
;; and `OR`, and the relational operators for numbers and strings (<ApplyRelation>).
;;
;; As the evaluator holds them, <VALTYP> is <VALUE_TYPE_REAL> for a real, <VALUE_TYPE_LONG_INTEGER> for a long integer
;; and <VALUE_TYPE_STRING> for a string; <VALUE_TYPE_ANY> before a formula asks for any type. A real or an integer
;; variable's value is a real in the <FAC>, unpacked; a long integer is eight bytes from <FAC>, two's complement, high
;; byte first; a string is a pointer to its descriptor in <FACMO>, <FACMO>+1 and <FACMOB>.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

;; The exponent of a real whose binary point is 16 bits past the top of its mantissa: <FLOATC> and <FLOATS> make a
;; 16-bit integer a real with it.
WORD_EXPONENT = $90

; ---------------------------------------------------------------------------------------------------------------------
; FRMEVL's operator step, continued
; ---------------------------------------------------------------------------------------------------------------------

.scope Operators continued

;; Does a binary operator, for <FRMEVL>: with the operator's left operand in <ARG> and its right in the <FAC>, calls
;; the operator's routine from <OPDSPT>, then goes on with the formula.
;;
;; <FRMEVL>'s <DOLAST>, in B3InpuF.asm, pulls the operands and the operator and falls in here with the operator in A and
;; in <DOMASK>. Each relational operator (1 to 7, its bits) takes the first dispatch entry, <ApplyRelation>; each
;; other operator an entry of its own. A long integer's entries follow the reals' in <OPDSPT>, <NUMDSP> bytes on. For
;; strings only `+` (whose offset is <NUMDSP>, as the last of the reals' entries) and the relational operators are
;; allowed.
;; In: A = the operator's number, DOMASK = the same, ARG = the left operand, FAC = the right one, VALTYP = their type,
;;   the stack = the operator that ended the operand, which <DOLAST> pushed
;; Errors: ERRSN = a string operator other than `+` or a relational one
;; Entry:
;;   Continue = pulls the operator <DOLAST> pushed and goes on with the formula at <FRMEVLZ>
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
    bit VALTYP                              ; a string or a long integer needs more care
    bmi StringOperands
    clc
    bvc NotLongInteger                      ; a real
    adc #NUMDSP                             ; a long integer: use the long-integer entries
    tax
    bcc Dispatch

;; Works out the sign of a real product or quotient, for the operator's routine.
;; Also: NOTDBLP (BB13)
NotLongInteger:
    lda ARGSGN
    eor FACSGN
    sta ARISGN

;; Calls the operator's routine, with A = the <FAC>'s exponent and zero set for a zero <FAC>, as the routines expect.
;; Also: RDY2GO (BB13)
Dispatch:
    lda OPDSPT-2,X
    sta JMPER+1
    lda OPDSPT-1,X
    sta JMPER+2
    lda FACEXP
    jsr JMPER

;; Pulls the operator that ended the operand back off the stack and goes on with the formula at <FRMEVLZ>.
;; Also: FRMEV3 (BB13)
Continue:
    pla
    jmp FRMEVLZ

;; Takes a binary operator on two strings: `+` concatenates them and a relational operator compares them; any other is
;; a syntax error.
;; Also: ASTRNG (BB13)
StringOperands:
    cmp #NUMDSP                             ; +?
    beq JoinStrings
    cmp #2*RELNUM                           ; a relational operator?
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

;; Evaluates one operand from the program text into the <FAC>: a number, a string, a variable, a function's result, or
;; a formula in parentheses.
;;
;; A digit or a period starts a constant, which is read as a long integer when <VALTYP> asks for one (or for a string,
;; which gives a type mismatch later), and as a real otherwise.
;; In: TXTPTR = the character before the operand, VALTYP = the type the formula wants
;; Out: FAC = the value, VALTYP = its type, TXTPTR = the operand's last character
;; Errors: ERRSN = a constant with no digits, or what can't start an operand
;; See: <FRMEVL>, <EvaluateVariable>, <CallFunction>
;; Also: EVAL (BB13)
.proc EvaluateOperand
;; The first byte of a two-byte token: a function, `FN` or `NOT`, with the token's own byte after it.
ESCAPE = $FF

    jsr CHRGET
    bcs NotDigit

;; Reads a numeric constant: a long integer with <LINP> when <VALTYP> is above <VALUE_TYPE_ANY>, or a real with <FIN>.
;; Also: ACONSTNT (BB13)
ReadConstant:
    lda VALTYP
    cmp #VALUE_TYPE_ANY+1
    bcc ReadReal
    jmp LINP

;; Reads a real constant with <FIN>, ending the statement with a syntax error when it has no digits.
;; Also: RLBNY (BB13)
ReadReal:
    lda #VALUE_TYPE_REAL
    sta VALTYP
    jsr FIN
    bit ANYNUM                              ; $FF when FIN found no digits
    bmi Operators::Apply::ToSyntaxError
    rts

;; Takes an operand that does not start with a digit: an escape token, a reserved word, a variable, a period, a plus,
;; a string literal, a minus or an opening parenthesis.
;; Also: EVAL1 (BB13)
NotDigit:
    cmp #ESCAPE                             ; a function, `FN` or `NOT`
    beq EvaluateEscapeToken
    cmp #ENDTK                              ; a reserved word
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

;; Makes a temporary string of the literal after the quote at <TXTPTR>, then moves TXTPTR past its closing quote.
;; In: TXTPTR = the opening quote, carry = set, as the comparison that found the quote leaves it
;; Out: FAC = the string, TXTPTR = past the closing quote
;; See: <STRLIT>, <ST2TXT>
;; Also: STRTXT (BB13)
.proc ReadQuotedString
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    adc #0                                  ; the carry is set: one past the quote
    bcc HaveAddress
    iny
    cpy #MAXPG
    bcc HaveAddress
    inx                                     ; past the bank's last page: page MINPG of the next
    ldy #MINPG

;; Makes the literal at A, Y and bank X a temporary string, then moves <TXTPTR> past it.
;; Also: STRTX2 (BB13)
HaveAddress:
    jsr STRLIT
    jmp ST2TXT
.endproc

.scope Operators continued

;; Takes `NOT`, evaluating the one operand that follows: gives 1 when it is zero, or 0 when it is not, as a long
;; integer for a long integer and as a real otherwise.
;;
;; `NOT` applies to the next operand alone, not to a formula, so `NOT A = B` is `(NOT A) = B`. A string is not caught
;; here: its <VALTYP> takes the long integer's path.
;; In: TXTPTR = the character after the token
;; Out: FAC = 1 or 0
;; See: <Operators::NotLongInteger>
;; Also: NOTDO (BB13)
.proc Not
    jsr BackUpTextPointer                   ; so EvaluateOperand's CHRGET reads the operand's first character
    jsr EvaluateOperand
    bit VALTYP
    bvc Real
    jmp NotLongInteger
Real:
    lda FACEXP
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

;; Takes an escape token: reads the byte after it and moves <TXTPTR> past both, then goes to <CallFunction> with the
;; byte.
;; Also: PARC22 (BB13)
.proc EvaluateEscapeToken
    jsr CHRGET
    tax
    jsr CHRGET
    txa
    jmp CallFunction
.endproc

;; Takes a reserved word that gives a value with no arguments, such as `ERR` or `TIME$`, through <RESTBL>; any other
;; reserved word is a syntax error.
;; In: A = the token
;; Errors: ERRSN = a reserved word that gives no value
;; See: <RESTBL>
;; Also: PARC23 (BB13)
.proc EvaluateReservedWord
    cmp #FRETK
    bcc ApplyMinus::ToSyntaxError
    cmp #POPTKN
    bcs ApplyMinus::ToSyntaxError
    asl
    tax
    jsr CHRGET
    lda RESTBL-FRETK-FRETK+256,X            ; the token less FRETK, times two
    sta JMPER+1
    lda RESTBL-FRETK-FRETK+257,X
    sta JMPER+2
    jmp JMPER
.endproc

;; Reads the cursor's position from the console into <CURX> and <CURY>, with a SOS D_STATUS call.
;; Out: Y = the cursor's line, from <CURY>
;; See: <REDCUR>, <Functions::VPos>, <Functions::Pos>
;; Also: VPOS (BB13)
.proc ReadCursorPosition
    brk
    .byte SDSTAT
    .word REDCUR
    ldy CURY
    rts
.endproc

.scope Functions continued

;; The value of `ERRLIN`: the line number of the last error, from <ERRLIN>.
;; Out: FAC = the line number, as a real
;; Also: DOERRLN (BB13)
.proc ErrLin
    lda ERRLIN+1
    ldy ERRLIN
    sta FACHO
    sty FACHO+1
    ldx #WORD_EXPONENT
    sec                                     ; positive
    jmp FLOATC
.endproc

;; The value of `OUTREC`: the column at which `LIST` wraps its lines (0 for none), from <OUTREC>.
;; Out: FAC = the column, as a real
;; Also: GIVOUTREC (BB13)
.proc OutRec
    ldy OUTREC
    jmp ReturnByte
.endproc

;; The value of `INDENT`: the indent `LIST` uses, from <INDENT>.
;; Out: FAC = the indent, as a real
;; Also: GIVINDENT (BB13)
.proc Indent
    ldy INDENT
    jmp ReturnByte
.endproc

;; The value of `KBD`: the last key read on an interrupt, from <KEYSAVE>.
;; Out: FAC = the key, as a real
;; Also: GIVKBD (BB13)
.proc Kbd
    ldy KEYSAVE
    jmp ReturnByte
.endproc

;; The value of `EOF`: the file number of the last end of file, from <EOFSV>.
;; Out: FAC = the file number, as a real
;; Also: GIVEOF (BB13)
.proc Eof
    ldy EOFSV
    .byte $2C                               ; BIT absolute skips Err's LDY
    ; Falls into Err, past its load.
.endproc

;; The value of `ERR`: the number of the last error, from <ERRNUM>.
;; Out: FAC = the error number, as a real
;; Also: GIVERR (BB13)
.proc Err
    ldy ERRNUM
    jmp ReturnByte
.endproc

.endscope

.scope Operators continued

;; Finishes `NOT` for a long integer: 1 when all eight bytes of the <FAC> are zero, 0 otherwise.
;;
;; X is not set: <LORALL> takes it as the bank of the FAC's address, and it holds whatever <EvaluateOperand> left. An
;; X-byte with bit 7 clear reads page zero, as meant; <Statements::If> clears X before the same call.
;; Out: FAC = 1 or 0, as a long integer
;; See: <Operators::Not>, <LORALL>
;; Also: BCDTSTR (BB13)
.proc NotLongInteger
    lda #<(FAC)
    ldy #>(FAC)
    jsr LORALL
    beq ReturnOne
    jmp LONGST0

;; Gives 1 as a long integer, for a zero operand.
;; Also: ISFALS (BB13)
ReturnOne:
    jmp LONGST1
.endproc

.endscope

;; Takes a unary minus, evaluating the one operand that follows and negating it, as a long integer or a real.
;;
;; A string is not caught here: its <VALTYP> takes the long integer's path.
;; Out: FAC = the negated operand
;; Entry:
;;   ToSyntaxError = jumps to <SyntaxError>; <EvaluateReservedWord> branches here for a reserved word with no value
;; See: <LTWSCOMP>, <NEGOP>
;; Also: DOMIN (BB13)
.proc ApplyMinus
    jsr EvaluateOperand
    bit VALTYP
    bvc NegateReal                          ; a real
    jmp LTWSCOMP

;; Negates the real in the <FAC>.
;; Also: CHGSGN (BB13)
NegateReal:
    jmp NEGOP

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
;; A zero precedence on the verb stack, <VRBSTK>, stops <FRMEVL> from taking an operator from outside the formula.
;; In: TXTPTR = the formula's first character, VALTYP = the type wanted
;; Out: FAC = the value, VALTYP = its type
;; Errors: ERRST = the verb stack is full
;; See: <FRMEVL1A>, <FormulaTooComplexError>
;; Also: DOPAR (BB13)
.proc EvaluateSubexpression
;; The bytes of <VRBSTK>, two for each operator held.
VERB_STACK_SIZE = 32

    .assert EOFPTRS - VRBSTK = VERB_STACK_SIZE, "VERB_STACK_SIZE must be VRBSTK's size."

    lda #0
    ldy VRBPT
    iny
    sta VRBSTK,Y                            ; precedence 0
    iny
    sty VRBPT
    cpy #VERB_STACK_SIZE                    ; too deep
    bcs FormulaTooComplexError
    jsr FRMEVL1A
    dec VRBPT
    dec VRBPT
    rts
.endproc

;; Evaluates a formula in parentheses.
;; In: TXTPTR = the opening parenthesis
;; Out: FAC = the value, VALTYP = its type, A = the character after the closing parenthesis
;; Errors: ERRSN = a missing parenthesis
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
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not a closing parenthesis
;; See: <CheckCharacter>
;; Also: CHKCLS (BB13)
.proc CheckCloseParenthesis
    lda #')'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckSemicolon, past its load.
.endproc

;; Checks for a semicolon and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not a semicolon
;; Also: CHKSMC (BB13)
.proc CheckSemicolon
    lda #';'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckEquals, past its load.
.endproc

;; Checks for an equals sign and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not an equals sign
;; Also: CHKEQL (BB13)
.proc CheckEquals
    lda #'='
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckNumberSign, past its load.
.endproc

;; Checks for a number sign and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not a number sign
;; Also: CHKPND (BB13)
.proc CheckNumberSign
    lda #'#'
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckOpenParenthesis, past its load.
.endproc

;; Checks for an opening parenthesis and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not an opening parenthesis
;; Also: CHKOPN (BB13)
.proc CheckOpenParenthesis
    lda #'('
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into CheckComma, past its load.
.endproc

;; Checks for a comma and moves past it, or ends the statement with a syntax error.
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = not a comma
;; Also: CHKCOM (BB13)
.proc CheckComma
    lda #','
    ; Falls into CheckCharacter.
.endproc

;; Checks that the character at <TXTPTR> is A and moves past it, or ends the statement with a syntax error.
;; In: A = the character
;; Out: A = the next character, as from <CHRGET>
;; Errors: ERRSN = a different character
;; Also: SYNCHR (BB13)
.proc CheckCharacter
    ldy #0
    cmp (TXTPTR),Y
    bne SyntaxError
    jmp CHRGET
.endproc

;; Ends the statement with FORMULA TOO COMPLEX.
;; Errors: ERRST
;; Also: CMPLXERR (BB13)
.proc FormulaTooComplexError
    ldx #ERRST
    jmp ERROR
.endproc

;; Ends the statement with SYNTAX <ERROR>.
;; Errors: ERRSN
;; Also: SNERR (BB13)
.proc SyntaxError
    ldx #ERRSN
    jmp ERROR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a variable's value into the <FAC>; an array that does not exist yet is not made.
;; In: TXTPTR = the variable's name
;; Out: FAC = the value, <VALTYP> and INTFLG = its type, TXTPTR = past the name and any subscripts
;; Entry:
;;   AtAddress = takes the value of the variable at A, Y and bank X; `READ#` calls it from <DRD3>
;; See: <FindVariable::ForExpression>
;; Also: ISVAR (BB13)
.proc EvaluateVariable
    ldx #$FF                                ; not to make an array
    jsr FindVariable::ForExpression
    ldx VARPNTB

;; Takes the value of the variable at A, Y and bank X into the <FAC>, by its type: a long integer's eight bytes, a
;; real, an integer floated to a real, or, for a string, the pointer to its descriptor.
;; In: A, Y = the variable's address, X = its bank, <VALTYP> and INTFLG = its type
;; Out: FACMO, FACMO+1, FACMOB = the variable's address
;; See: <DMOVFM>, <MOVFM>, <ReturnSignedWord>
;; Also: ISVRET2 (BB13)
AtAddress:
    sta FACMO
    sty FACMO+1
    stx FACMOB
    bit VALTYP
    bvc LoadNumericVariable                 ; a real or an integer
    bpl LongInteger                         ; a long integer
    ldx #0                                  ; a string: FACMO points to its descriptor
    stx FACOV
    rts

;; Copies a long integer variable's eight bytes into the <FAC>.
;; Also: DBLVAR (BB13)
LongInteger:
    jmp DMOVFM
.endproc

;; Moves <TXTPTR> back one character.
;;
;; At the start of a page it steps the page back, then calls <Memory::WrapPage>, which only brings a page past the
;; window down. So backing up from the first byte of an X-byte's window (page <MINPG>) leaves page 1, which banked
;; pointers cannot reach, where <Memory::PreviousPage> would have gone on at the last page of the X-byte before: a bug
;; of the original, which matters only for program text that crosses from one X-byte to the next.
;; Uses: A, Y
;; Keeps: X
;; Also: DECTPT (BB13)
.proc BackUpTextPointer
    txa
    pha
    lda TXTPTR
    bne SamePage                            ; the page stays
    dec TXTPTR+1
    ldx TXTPTRB
    ldy TXTPTR+1
    jsr Memory::WrapPage
    stx TXTPTRB
    sty TXTPTR+1

;; Steps the low byte back.
;; Also: DECTP1 (BB13)
SamePage:
    dec TXTPTR
    pla
    tax
    rts
.endproc

;; Takes a real or an integer variable's value into the FAC.
;; In: FACMO = the variable's address, INTFLG = $80 for an integer
;; Out: FAC = the value
;; Entry:
;;   FloatInteger = floats the integer variable at FACMO; `NEXT` calls it from <HAVFOR> for an integer
;;     loop variable
;; See: <MOVFM>
;; Also: GOOO (BB13)
.proc LoadNumericVariable
    bit INTFLG
    bpl NotInteger

;; Floats an integer variable, its high byte first, into the <FAC>.
;; See: <ReturnSignedWord>
;; Also: GOOO2 (BB13)
FloatInteger:
    ldy #0
    lda (FACMO),Y
    tax
    iny
    lda (FACMO),Y
    tay
    txa
    jmp ReturnSignedWord

;; Unpacks a real variable into the <FAC>.
;; Also: GOOOOO (BB13)
NotInteger:
    jmp MOVFM
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Functions
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a function's escape token: `FN`, `NOT`, or a function from <FUNDSP>.
;;
;; A function before <LENTK> takes a number, one up to <CONVTK> a string, and `CONV` and its kin any type; each reads
;; its argument in parentheses. Those past <LASNUM> (`LEFT$`, `RIGHT$`, `MID$` and `INSTR`) take a string, then `INSTR`
;; another, then a byte; <CallFunction::Builtin> pushes their strings' descriptor pointers and the byte for the function
;; to pull, and the function checks for its closing parenthesis.
;; In: A = the byte after the escape token, TXTPTR = the character after it
;; Errors: ERRSN = a token that is no function
;; See: <FUNDSP>, <Functions::Fn>, <Operators::Not>
;; Also: ISFUN (BB13)
.proc CallFunction
    cmp #ONEFUN
    bcs Builtin
    cmp #FNTK
    bne NotFn
    jmp Functions::Fn
NotFn:
    cmp #NOTTK
    bne SyntaxError
    jmp Operators::Not

;; Reads the arguments of a function from <FUNDSP> and calls it.
;;
;; For `LEFT$`, `RIGHT$`, `MID$` and `INSTR`, the stack holds, from the top: the byte argument, then the descriptor
;; pointer of each string, low byte, high byte and bank, the last string first. `INSTR`'s byte is 1 when it is left
;; out.
;; Also: GOODFUN (BB13)
Builtin:
    asl
    pha
    tax
    cpx #2*LASNUM-256+1
    bcc OneArgument                         ; one argument
    lda #VALUE_TYPE_STRING
    sta VALTYP
    jsr EvaluateSubexpression               ; the string
    jsr CheckComma
    pla                                     ; the function
    tax
    lda FACMOB
    pha
    lda FACMO+1
    pha
    lda FACMO
    pha
    txa
    pha                                     ; on the stack, as the arguments may hold functions too
    cmp #2*INSTRTK-256
    bne ReadByteArgument
    lda #VALUE_TYPE_STRING                  ; `INSTR`: the string to look for
    sta VALTYP
    jsr EvaluateSubexpression
    pla
    tax
    lda FACMOB
    pha
    lda FACMO+1
    pha
    lda FACMO
    pha
    txa
    pha
    jsr CHRGOT
    cmp #','
    beq SkipComma
    ldx #1                                  ; no start: 1
    bne HaveByte                            ; always

;; Moves past the comma before the byte argument.
;; Also: NORMFUN (BB13)
SkipComma:
    jsr CHRGET

;; Reads the byte argument, then calls the function with it on the stack.
;; Also: NORMFN2 (BB13)
ReadByteArgument:
    jsr GETBYT
HaveByte:
    pla
    tay
    txa
    pha
    jmp Dispatch

;; Reads a one-argument function's argument in parentheses, of the type the function takes, then calls it.
;; Also: OKNORM (BB13)
OneArgument:
    cpx #2*LENTK-256
    bcc NumericArgument                     ; a number
    cpx #2*CONVTK-256
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
    sta VALTYP
    jsr EvaluateParenthesized::AfterOpen
    pla
    tay

;; Calls the function from <FUNDSP>.
;; In: Y = the function's token times two
;; Also: FINGO (BB13)
Dispatch:
    lda FUNDSP-ONEFUN-ONEFUN+256,Y
    sta JMPER+1
    lda FUNDSP-ONEFUN-ONEFUN+257,Y
    sta JMPER+2
    jmp JMPER
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Logical and relational operators
; ---------------------------------------------------------------------------------------------------------------------

.scope Operators continued

;; Takes `OR`, giving 1 when either real is nonzero, 0 otherwise.
;; In: ARG, FAC = the operands
;; Out: FAC = 1 or 0, as a real
;; Also: OROP (BB13)
.proc Or
    lda ARGEXP
    ora FACEXP
    bne And::LoadTrue
    ; Falls into And.
.endproc

;; Takes `AND`, giving 1 when both reals are nonzero, 0 otherwise.
;; In: ARG, FAC = the operands
;; Out: FAC = 1 or 0, as a real
;; Entry:
;;   LoadFalse = gives 0 as a real; <LMAKFLT> jumps here for a zero long integer
;;   LoadTrue = gives 1 as a real; <Operators::Or> branches here when either operand is nonzero
;; Also: ANDOP (BB13)
.proc And
    lda ARGEXP
    beq LoadFalse
    lda FACEXP
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

;; Compares <ARG> with the <FAC>, reals or strings, and gives 1 when the relation in <DOMASK> holds, 0 when not.
;;
;; <DOMASK> has a bit for each part of the operator: 1 for greater, 2 for equal and 4 for less. Strings compare
;; character by character, and a shorter string that matches the start of a longer one is less. Both strings'
;; temporaries are freed.
;; In: ARG = the left operand, FAC = the right one
;; Out: FAC = 1 or 0, as a real, VALTYP = 0
;; See: <FCOMPARG>, <Strings::ReleaseFac>
;; Also: DOREL (BB13)
.proc ApplyRelation
    bit VALTYP
    bmi CompareStrings
    jsr FCOMPARG
    tax
    jmp NumberResult

;; Compares two strings.
;; Also: STRCMP (BB13)
CompareStrings:
    jsr Strings::ReleaseFac                 ; the right string
    php                                     ; whether its temporary was freed
    sta DSCTMP                              ; its length
    stx DSCTMP+1
    sty DSCTMP+2
    lda INDEXB
    sta DSCTMPB
    lda ARGMO
    ldy ARGMO+1                             ; the left string
    ldx ARGMOB
    jsr Strings::ReleaseDescriptor
    php
    stx ARGMO
    sty ARGMO+1
    ldx INDEXB
    stx ARGMOB
    tax
    pha                                     ; its length
    sec
    sbc DSCTMP                              ; which is longer?
    beq SetLengthOrder
    lda #1                                  ; the left is shorter: less
    bcc SetLengthOrder
    ldx DSCTMP                              ; the left is longer: compare the right's length
    lda #$100-1

;; Keeps the result the lengths give, for when the shorter string matches the start of the longer.
;; Also: STASGN (BB13)
SetLengthOrder:
    sta FACSGN
    ldy #$FF
    inx

;; Compares the next character, or takes the lengths' result when there are no more.
;; Also: NXTCMP (BB13)
NextByte:
    iny
    dex
    bne CompareByte
    ldx FACSGN

;; Turns a comparison result in X, -1, 0 or 1, into the relation's bit, with the carry set for -1.
;; Also: QCOMP (BB13)
NumberResult:
    bmi ApplyMask                           ; the carry is set for -1
    clc
    bcc ApplyMask                           ; always

;; Compares one character of the two strings.
;; Also: GETCMP (BB13)
CompareByte:
    lda (ARGMO),Y
    cmp (DSCTMP+1),Y
    beq NextByte
    ldx #$100-1                             ; the left is greater
    bcs ApplyMask
    ldx #1                                  ; the left is less

;; Turns the comparison's result into 1 or 0 by the relation in <DOMASK>.
;; In: X = $FF when the left is greater, 0 when equal, 1 when less, carry = set for $FF
;; Also: DOCMP (BB13)
ApplyMask:
    inx                                     ; -1, 0 and 1 become bits 1, 2 and 4
    txa
    rol
    and DOMASK
    beq FreeStrings
    lda #1

;; Frees the two strings' space after a string comparison, then floats the result.
;; Also: GOFLOT (BB13)
FreeStrings:
    bit VALTYP
    bpl ToFloat                             ; numbers
    sta FOUR6                               ; the result
    lda #VALUE_TYPE_REAL
    sta VALTYP
    pla                                     ; the left string's length
    ldx ARGMO
    ldy ARGMO+1
    stx INDEX
    sty INDEX+1
    ldx ARGMOB
    stx INDEXB
    plp                                     ; whether the left's temporary was freed
    jsr Strings::FreeSpaceIfReleased
    plp                                     ; whether the right's was
    jsr Strings::FreeFacIfReleased
    lda FOUR6

;; Floats the comparison's result, 1 or 0.
;; Also: GFLOT1 (BB13)
ToFloat:
    jmp FLOAT
.endproc
