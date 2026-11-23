; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: OPERANDS, FUNCTIONS AND LOGICAL OPERATORS

;; Emits the operand parser and syntax checks preceding variable-value handling.
;; Parameters: piToken = 1 to accept the single-byte PI constant,
;;             bitwiseNot = 1 for signed 16-bit NOT, 0 for Boolean NOT,
;;             functionEntry = entry used to dispatch built-in functions
.macro OPERAND_EVALUATION piToken, bitwiseNot, functionEntry
    .assert piToken = 0 || piToken = 1, "piToken is 0 or 1."
    .assert bitwiseNot = 0 || bitwiseNot = 1, "bitwiseNot is 0 or 1."

;; Evaluates a numeric constant, variable, string literal, parenthesized expression or function.
;; In: TXTPTR = character preceding the operand
;; Out: FAC = value or string descriptor, VALTYP = result type, TXTPTR = terminating character
EVAL:
    lda #$00
    sta VALTYP
EVAL0:
    jsr CHRGET
    bcs EVAL2
EVAL1:
    jmp FIN
EVAL2:
    jsr ISLETC
    bcs ISVAR
.if piToken
    cmp #<PI
    bne QDOT
    lda #<PIVAL
    ldy #>PIVAL
    jsr MOVFM
    jmp CHRGET

;; Five-byte floating-point approximation of pi used by the PI token.
PIVAL:
    .byte $82, $49, $0F, $DA, $A1
.endif
QDOT:
    cmp #'.'
    beq EVAL1
    cmp #<MINUTK
    beq DOMIN
    cmp #<PLUSTK
    beq EVAL0
    cmp #'"'
    bne EVAL3

;; Builds a descriptor for the quoted literal at <TXTPTR> and advances past it.
STRTXT:
    lda TXTPTR
    ldy TXTPTR+1
    adc #$00
    bcc STRTX2
    iny
STRTX2:
    jsr STRLIT
    jmp ST2TXT

EVAL3:
    cmp #<NOTTK
    bne EVAL4
    ldy #<(NOTTAB-OPTAB)
    bne GONPRC

;; Applies NOT to <FAC>: Boolean zero or one, or a signed 16-bit bitwise complement.
;; Out: FAC = numeric result
NOTOP:
.if bitwiseNot
    jsr AYINT
    lda FACLO
    eor #$FF
    tay
    lda FACMO
    eor #$FF
    jmp GIVAYF
.else
    lda FACEXP
    bne NOTOP1
    ldy #$01
    .byte $2C                   ; BIT absolute skips the next two bytes
NOTOP1:
    ldy #$00
    jmp SNGFLT
.endif
EVAL4:
    cmp #<FNTK
    bne *+5
    jmp FNDOER
    cmp #<ONEFUN
    bcc PARCHK
    jmp functionEntry

;; Requires an opening parenthesis, evaluates an expression, and requires the closing parenthesis.
PARCHK:
    jsr CHKOPN
    jsr FRMEVL

;; Requires and consumes a closing parenthesis.
CHKCLS:
    lda #')'
    .byte $2C                   ; BIT absolute skips the next two bytes

;; Requires and consumes an opening parenthesis.
CHKOPN:
    lda #'('
    .byte $2C                   ; BIT absolute skips the next two bytes

;; Requires and consumes a comma.
CHKCOM:
    lda #','

;; Requires the character in A at <TXTPTR>, then advances to the next character.
;; Errors: SYNTAX if the character does not match
SYNCHR:
    ldy #$00
    cmp (TXTPTR),y
    bne SNERR
CHRGO5:
    jmp CHRGET
SNERR:
    ldx #<ERRSN
    jmp ERROR
DOMIN:
    ldy #<(NEGTAB-OPTAB)
GONPRC:
    pla
    pla
    jmp NEGPRC
.endmacro

;; Emits the integer-variable conversion path, falling through for floating-point variables.
.macro INTEGER_VARIABLE_VALUE
;; Loads an integer variable through <FACMO> and converts it to floating point.
;; In: INTFLG = variable type, FACMO/FACLO = address of the stored value
;; Out: FAC = numeric value for an integer variable
GOOO:
    ldx INTFLG
    bpl GOOOOO
    ldy #$00
    lda (FACMO),y
    tax
    iny
    lda (FACMO),y
    tay
    txa
    jmp GIVAYF
GOOOOO:
.endmacro

;; Emits the built-in function argument parser and dispatcher.
.macro FUNCTION_DISPATCH
;; Parses a built-in function's arguments and dispatches through <FUNDSP>.
;;
;; The string slicing functions take a string and a byte argument; their descriptors and arguments are
;; stacked for the callee. Ordinary functions take one parenthesized expression.
ISFUN:
    asl a
    pha
    tax
    jsr CHRGET
    cpx #<(2*LASNUM-255)
    bcc OKNORM
    jsr CHKOPN
    jsr FRMEVL
    jsr CHKCOM
    jsr CHKSTR
    pla
    tax
    lda FACLO
    pha
    lda FACMO
    pha
    txa
    pha
    jsr GETBYT
    pla
    tay
    txa
    pha
    jmp FINGO
OKNORM:
    jsr PARCHK
    pla
    tay
FINGO:
    lda FUNDSP-2*ONEFUN+256,y
    sta JMPER+1
    lda FUNDSP-2*ONEFUN+257,y
    sta JMPER+2
    jsr JMPER
    jmp CHKNUM
.endmacro

;; Emits the variant's OR and AND entries.
;; Parameters: bitwise = 1 for signed 16-bit operations, 0 for Boolean zero-or-one results
.macro LOGICAL_OPERATORS bitwise
    .assert bitwise = 0 || bitwise = 1, "bitwise is 0 or 1."

;; Computes OR on the numeric argument and <FAC>.
;; Out: FAC = numeric result
OROP:
.if bitwise
    ldy #$FF
    .byte $2C                   ; BIT absolute skips the next two bytes

;; Computes signed 16-bit AND on the numeric argument and <FAC>.
;; Out: FAC = numeric result
ANDOP:
    ldy #$00
    sty COUNT
    jsr AYINT
    lda FACMO
    eor COUNT
    sta INTEGR
    lda FACLO
    eor COUNT
    sta INTEGR+1
    jsr MOVFA
    jsr AYINT
    lda FACLO
    eor COUNT
    and INTEGR+1
    eor COUNT
    tay
    lda FACMO
    eor COUNT
    and INTEGR
    eor COUNT
    jmp GIVAYF
.else
;; Historical alias at the OR entry; AND dispatches to its own Boolean entry instead.
ANDOP:
    lda ARGEXP
    ora FACEXP
    bne OROP12

;; Computes Boolean AND on the numeric argument and <FAC>.
;; Out: FAC = zero or one
OROP1:
    lda ARGEXP
    beq OROP11
    lda FACEXP
    bne OROP12
OROP11:
    ldy #$00
    .byte $2C                   ; BIT absolute skips the next two bytes
OROP12:
    ldy #$01
    jmp SNGFLT
.endif
.endmacro
