;; APPLESOFT: NEXT AND EXPRESSION EVALUATION
;;
;; This part follows INPUT and READ in AppleSoft.InputOutput.asm. NEXT belongs with FOR, whose stack
;; frames are created in AppleSoft.ControlFlow.asm; it is here because the ROM places it immediately before
;; the expression evaluator. The evaluator saves pending operators and operands on the machine stack.
;; <OPTAB> gives each operator its precedence and dispatch address. Relational operators accumulate a mask,
;; and string concatenation returns to the evaluator through <TSTOP>.

.include "../Microsoft6502Basic/MsBasic.Next.asm"
.include "../Microsoft6502Basic/MsBasic.ExpressionCore.asm"
.include "../Microsoft6502Basic/MsBasic.OperandEvaluation.asm"

    NEXT_ENTRIES 1, NXTCO1
    EXPRESSION_CORE 0
    OPERAND_EVALUATION 0, 0, QSTAT2

;; Resolves a variable operand and loads its value, or leaves its string descriptor in <FAC>.
ISVAR:
    jsr PTRGET

ISVRET:
    sta FACMO
    sty FACLO
    ldx VALTYP
    beq GOOO
    ldx #$00
    stx FACOV

STRRTS:
    rts

    INTEGER_VARIABLE_VALUE

QSTATV:
    jmp MOVFM

;; Evaluates SCRN's coordinates and returns the color read by the Monitor.
QSTAT1:
    jsr CHRGET
    jsr PLOTFN
    txa
    ldy FIRST
    jsr MSCRN
    tay
    jsr SNGFLT
    jmp CHKCLS

QSTAT2:
    cmp #<SCRNTK
    beq QSTAT1

    FUNCTION_DISPATCH
    LOGICAL_OPERATORS 0

.include "../Microsoft6502Basic/MsBasic.Relational.asm"
    RELATIONAL_OPERATORS $01

;; Reads the paddle specified by the numeric argument and returns its value in <FAC>.
PDL:
    jsr CONINT
    jsr PREAD
    jmp SNGFLT
