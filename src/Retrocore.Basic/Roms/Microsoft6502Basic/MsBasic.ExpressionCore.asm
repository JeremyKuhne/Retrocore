; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: EXPRESSION EVALUATION
;
; The pending operations' stack holds five-byte packed values.

;; Emits the precedence evaluator and its operand stack routines.
;; Parameters: carryReturn = 1 to carry <EvaluateExpression::PushSignedFac>'s return address into its high byte, 0 to
;;   increment only its low byte (AppleSoft, BASIC 1 and 2)
.macro ExpressionCore carryReturn
    .assert carryReturn = 0 || carryReturn = 1, "carryReturn must be 0 or 1."

    ;; Evaluates an expression with operator precedence.
    ;;
    ;; Each pending operation has its dispatch address, unpacked operand and precedence on the stack. A
    ;; relational mask also records the operand type so <ApplyRelation> can compare either numbers or strings.
    ;; In: TextPointer = first character of the expression
    ;; Out: Fac = numeric result or string descriptor pointer, ValueType = result type,
    ;;   TextPointer = terminating character
    ;; Errors: SYNTAX for a repeated relation, TYPE MISMATCH for a string where a number is needed, FORMULA TOO COMPLEX
    ;;   or OUT OF MEMORY when the stack runs out
    ;; Entry:
    ;;   NextOperator = rereads the character after an operand; <Strings::Concatenate> jumps back here
    ;;   Prefix = pushes the operation at Y and evaluates its operand; <ApplyPrefixOperator> jumps here for unary minus
    ;;     and `NOT`
    ;;   PushSignedFac = pops its return address into <Pointer1>, pushes A (the sign) and the rounded <Fac>, and jumps
    ;;     back; `FOR` calls it
    ;;   PushFac = rounds <Fac>, pushes its five bytes and jumps through <Pointer1>; `FOR` enters here
    ;; Also: FRMEVL (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc EvaluateExpression
    ldx TextPointer
    bne BackUpLow
    dec TextPointer+1

;; Decrements <TextPointer>'s low byte so the first operand's character is reread; starts with precedence 0.
;; Also: FRMEV1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
BackUpLow:
    dec TextPointer
    ldx #$00
    .byte $24                   ; BIT zero-page skips the next byte

;; Pushes the precedence and mask, checks stack room and evaluates the next operand.
;; Also: LPOPER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextOperand:
    pha
    txa
    pha
    lda #$01
    jsr CheckStack
    jsr EvaluateOperand
    lda #$00
    sta OperatorMask

;; Rereads the character after an operand; <Strings::Concatenate> jumps back here.
;; Also: TSTOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextOperator:
    jsr GetCurrentCharacter

;; Accumulates the less-than, equal and greater-than signs into <OperatorMask>; a repeated one is a syntax error.
;; Also: LOPREL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextRelation:
    sec
    sbc #<TOKEN_GREATER
    bcc EndRelations
    cmp #$03
    bcs EndRelations
    cmp #$01
    rol a
    eor #$01
    eor OperatorMask
    cmp OperatorMask
    bcc ToSyntaxError
    sta OperatorMask
    jsr GetNextCharacter
    jmp NextRelation

;; No more relations: finishes a relation, ends without an operator, or picks the arithmetic operator (`+` on strings
;; jumps to <Strings::Concatenate>).
;; Also: ENDREL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
EndRelations:
    ldx OperatorMask
    bne FinishRelation
    bcs NoOperator
    adc #<(TOKEN_GREATER-TOKEN_PLUS)
    bcc NoOperator
    adc ValueType
    bne Arithmetic
    jmp Strings::Concatenate

;; An arithmetic operator: forms its offset in <OperatorTable> from its token.
Arithmetic:
    adc #$FF
    sta Pointer1
    asl a
    adc Pointer1
    tay

;; Compares the pending precedence with the new operator's in <OperatorTable>.
;; Also: QPREC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ComparePrecedence:
    pla
    cmp OperatorTable + OperatorEntry::PRECEDENCE,y
    bcs CheckOperands
    jsr RequireNumber

;; The new operator binds tighter: keeps the pending precedence on the stack.
;; Also: DOPREC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DeferOperator:
    pha

;; Pushes the operation at Y and evaluates its operand; <ApplyPrefixOperator> jumps here for unary minus and NOT.
;; Also: NEGPRC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Prefix:
    jsr PushOperation
    pla
    ldy OperatorPointer
    bpl CompareAfterPrefix
    tax
    beq CheckDone
    bne PopOperand

;; Combines the relation mask with the operand type and backs up <TextPointer>.
;; Also: FINREL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FinishRelation:
    lsr ValueType
    txa
    rol a
    ldx TextPointer
    bne RelationBackUpLow
    dec TextPointer+1

;; Decrements <TextPointer>'s low byte and selects the relational operator's table entry.
;; Also: FINRE2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RelationBackUpLow:
    dec TextPointer
    ldy #<(OperatorTable::Relation - OperatorTable)
    sta OperatorMask
    bne ComparePrecedence

;; After a prefix operation: compares precedence with the operator at <OperatorPointer>.
;; Also: QPREC1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CompareAfterPrefix:
    cmp OperatorTable + OperatorEntry::PRECEDENCE,y
    bcs PopOperand
    bcc DeferOperator

;; Pushes the operator's dispatch address and <Fac> with its precedence, then evaluates the next operand.
;; Also: DOPRE1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushOperation:
    lda OperatorTable + OperatorEntry::HANDLER + 1,y
    pha
    lda OperatorTable + OperatorEntry::HANDLER,y
    pha
    jsr PushOperand
    lda OperatorMask
    jmp NextOperand

;; Jumps to <SyntaxError>.
;; Also: SNERR5 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToSyntaxError:
    jmp SyntaxError

;; Saves the current <Fac> and operator precedence for a pending operation.
;; Also: PUSHF1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushOperand:
    lda FacSign
    ldx OperatorTable + OperatorEntry::PRECEDENCE,y

;; Saves the sign in A and rounded <Fac> on the stack, then returns through <Pointer1>.
;;
;; Where `carryReturn` is 0 (AppleSoft, BASIC 1 and 2), only the return address's low byte is incremented, so a call
;; whose return address ends in $FF returns a page early; where it is 1 (BASIC 4), the increment carries.
;; Also: PUSHF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushSignedFac:
    tay
    pla
    sta Pointer1
    .if .not carryReturn
        inc Pointer1
    .endif
    pla
    sta Pointer1+1
    tya
    pha
    .if carryReturn
        inc Pointer1
        bne PushFac
        inc Pointer1+1
    .endif

;; Saves the rounded <Fac> on the stack without pushing its sign, then jumps through <Pointer1>.
;;
;; `FOR` sets <Pointer1> to its continuation before entering here; <PushSignedFac> takes it from the return address.
;; Also: FORPSH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushFac:
    jsr Float::Round
    lda FacMantissa4
    pha
    lda FacMantissa3
    pha
    lda FacMantissa2
    pha
    lda FacMantissa1
    pha
    lda FacExponent
    pha
    jmp (Pointer1)

;; End of the expression: sets Y to $FF and pulls the pending precedence.
;; Also: QOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NoOperator:
    ldy #$FF
    pla

;; Precedence 0 means no pending operation: returns the result.
;; Also: QOPGO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckDone:
    beq Finish

;; A relation's precedence skips the numeric check, so strings compare; others require a number.
;; Also: QCHNUM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckOperands:
    cmp #PRECEDENCE_RELATION
    beq SaveOperator
    jsr RequireNumber

;; Saves Y in <OperatorPointer>.
;; Also: UNPSTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SaveOperator:
    sty OperatorPointer

;; Pulls the mask into <RelationMask> and the stacked operand into the argument register, setting <ResultSign>.
;; Also: PULSTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PopOperand:
    pla
    lsr a
    sta RelationMask
    pla
    sta ArgExponent
    pla
    sta ArgMantissa1
    pla
    sta ArgMantissa2
    pla
    sta ArgMantissa3
    pla
    sta ArgMantissa4
    pla
    sta ArgSign
    eor FacSign
    sta ResultSign

;; Loads <FacExponent> (sets the flags) before the RTS that dispatches to the operator or returns.
;; Also: QOPRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Finish:
    lda FacExponent

;; Returns into the operator routine whose address was pushed, or to the caller.
;; Also: UNPRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Return:
    rts
    .endproc
.endmacro
