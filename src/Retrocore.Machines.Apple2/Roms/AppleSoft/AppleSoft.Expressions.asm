; retrocore: style=strict
; APPLESOFT: NEXT AND EXPRESSION EVALUATION
;
; This part follows INPUT and READ in AppleSoft.InputOutput.asm. NEXT belongs with FOR, whose stack
; frames are created in AppleSoft.ControlFlow.asm; it is here because the ROM places it immediately before
; the expression evaluator. The evaluator saves pending operators and operands on the machine stack.
; OperatorTable gives each operator its precedence and dispatch address. Relational operators accumulate a mask,
; and string concatenation returns to the evaluator through EvaluateExpression::NextOperator.

.include "../Microsoft6502Basic/MsBasic.Next.asm"
.include "../Microsoft6502Basic/MsBasic.ExpressionCore.asm"
.include "../Microsoft6502Basic/MsBasic.OperandEvaluation.asm"

    NextEntries 1, NextStatementSavingStack
    ExpressionCore 0
    OperandEvaluation 0, 0, CheckScrnFunction

;; Looks up the variable operand with <FindVariable> and falls into <LoadVariableValue>.
;; Also: ISVAR (M6502)
.proc EvaluateVariable
    jsr FindVariable
    ; Falls into LoadVariableValue.
.endproc

;; Leaves a string variable's descriptor address in <FacMantissa3> and <FacMantissa4>, and loads a numeric
;; variable's value into <Fac>.
;; In: A = the value's address (low byte), Y = its high byte, ValueType = the variable's type, IntegerType = negative
;;   for an integer variable
;; Out: FacMantissa3 = the value's address (low byte), FacMantissa4 = its high byte; for a number, Fac = its value
;; Also: ISVRET (M6502)
.proc LoadVariableValue
    sta FacMantissa3
    sty FacMantissa4
    ldx ValueType
    beq LoadNumericVariable
    ldx #$00
    stx FacExtension

;; Returns with a string's descriptor address in <FacMantissa3> and <FacMantissa4>; nothing in AppleSoft branches
;; here, and the label is kept for its old name.
;; Also: STRRTS (M6502)
Return:
    rts

    IntegerVariableValue

;; A real variable: moves it into <Fac>. AppleSoft has no ST variable to test here, where Microsoft's source does.
;; Also: QSTATV (M6502)
LoadFloat:
    jmp Float::LoadFac
.endproc

.scope Functions continued

;; `SCRN(`: evaluates the coordinates and returns the Monitor's low-resolution color there as a number.
;; Also: QSTAT1 (UNKN)
.proc Scrn
    jsr GetNextCharacter
    jsr ReadLowResCoordinates
    txa
    ldy LowResFirst
    jsr MSCRN
    tay
    jsr ReturnByte
    jmp CheckCloseParenthesis
.endproc

.endscope

;; The evaluator's function entry: `SCRN(` goes to <Functions::Scrn>, and the other functions fall into the shared
;; function dispatch.
;; In: A = the function's token
;; Also: QSTAT2 (UNKN)
.proc CheckScrnFunction
    cmp #<TOKEN_SCRN
    beq Functions::Scrn
    ; Falls into the shared function dispatch.
.endproc

    FunctionDispatch
    LogicalOperators 0

.include "../Microsoft6502Basic/MsBasic.Relational.asm"
    RelationalOperators $01

.scope Functions continued

;; `PDL`: reads the numbered paddle through the Monitor and returns its value.
;; Also: PDL (UNKN)
.proc Pdl
    jsr ConvertToByte
    jsr PREAD
    jmp ReturnByte
.endproc

.endscope
