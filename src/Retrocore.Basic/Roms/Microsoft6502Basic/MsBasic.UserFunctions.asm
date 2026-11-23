; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: USER-DEFINED FUNCTIONS
;
; A DEF FN entry is a scalar-variable entry whose name has the function bit set.
; Its value contains pointers to the formula and to its numeric argument variable.

;; Emits DEF and FN with either undefined-function check.
;; Parameters: earlyCheck = 1 to test the low byte of the argument address, 0 to test its high byte
.macro UserFunctions earlyCheck
    .assert earlyCheck = 0 || earlyCheck = 1, "earlyCheck must be 0 or 1."

    ;; Rejects a statement in direct mode.
    ;;
    ;; Where the undefined-function check tests the argument's high byte, `UndefinedFunction` follows inside the
    ;; routine: `FN` enters there to report UNDEF'D FUNCTION, and the direct-mode path's `BIT` skips its load.
    ;; Errors: ILLEGAL DIRECT when no program line is executing
    ;; Entry:
    ;;   ToError = jumps to <ERROR> with the error in X; BASIC 1's `FN` enters here
    ;; Also: ERRDIR (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc RejectDirectMode
    ldx CurrentLine+1
    inx
    bne DIMRTS
    ldx #<ERROR_ILLEGAL_DIRECT
    .if earlyCheck = 0
        .byte $2C                   ; BIT absolute skips the next two bytes

;; Reports a call to a function with no definition.
;; Also: ERRGUF (M6502, CBM4S79, HV2, HV4, HV4R)
UndefinedFunction:
        ldx #<ERROR_UNDEFINED_FUNCTION
    .endif

;; Jumps to <ERROR> with the error in X; BASIC 1's `FN` enters here.
;; Also: ERRGO1 (M6502, HV1, HV1R)
ToError:
    jmp ERROR
    .endproc

    .scope Statements continued

    ;; Defines a single-argument numeric function from the rest of the current program statement.
    ;;
    ;; The function entry records the expression's text pointer and the argument variable's value pointer.
    ;; The formula is evaluated when called, not when defined.
    ;; Errors: ILLEGAL DIRECT in direct mode, TYPE MISMATCH for a string name or argument
    ;; Also: DEF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Def
    jsr ReadFunctionName
    jsr RejectDirectMode
    jsr CHKOPN
    lda #$80
    sta SubscriptMode
    jsr PTRGET
    jsr RequireNumber
    jsr CHKCLS
    lda #<TOKEN_EQUAL
    jsr SYNCHR
    pha
    lda VariablePointer+1
    pha
    lda VariablePointer
    pha
    lda TextPointer+1
    pha
    lda TextPointer
    pha
    jsr Data
    jmp PopToFunctionPointer
    .endproc
    .endscope

    ;; Parses FN and its name, finding or creating the function's scalar entry.
    ;; Out: FunctionPointer = function entry value address
    ;; Also: GETFNM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReadFunctionName
    lda #<TOKEN_FN
    jsr SYNCHR
    ora #$80
    sta SubscriptMode
    jsr PTRGT2
    sta FunctionPointer
    sty FunctionPointer+1
    jmp RequireNumber
    .endproc

    .scope Functions continued

    ;; Calls a user-defined function with a numeric argument.
    ;;
    ;; The argument variable's old value and the caller's text pointer are saved on the stack. The function
    ;; expression is evaluated with the new argument, then both are restored. An undefined function is an error.
    ;; The early check also rejects a defined argument whose address has a zero low byte.
    ;; Out: Fac = function result
    ;; Also: FNDOER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Fn
    jsr ReadFunctionName
    lda FunctionPointer+1
    pha
    lda FunctionPointer
    pha
    jsr PARCHK
    jsr RequireNumber
    pla
    sta FunctionPointer
    pla
    sta FunctionPointer+1
    ldy #$02
    .if earlyCheck
        ldx #<ERROR_UNDEFINED_FUNCTION
        lda (FunctionPointer),y
        beq RejectDirectMode::ToError
        sta VariablePointer
        tax
        iny
        lda (FunctionPointer),y
    .else
        lda (FunctionPointer),y
        sta VariablePointer
        tax
        iny
        lda (FunctionPointer),y
        beq RejectDirectMode::UndefinedFunction
    .endif
    sta VariablePointer+1
    iny

;; Pushes the argument variable's five bytes.
;; Also: DEFSTF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SaveArgument:
    lda (VariablePointer),y
    pha
    dey
    bpl SaveArgument
    ldy VariablePointer+1
    jsr Float::StoreFac
    lda TextPointer+1
    pha
    lda TextPointer
    pha
    lda (FunctionPointer),y
    sta TextPointer
    iny
    lda (FunctionPointer),y
    sta TextPointer+1
    lda VariablePointer+1
    pha
    lda VariablePointer
    pha
    jsr EvaluateNumber
    pla
    sta FunctionPointer
    pla
    sta FunctionPointer+1
    jsr GetCurrentCharacter
    beq *+5
    jmp SNERR
    pla
    sta TextPointer
    pla
    sta TextPointer+1
    .endproc
    .endscope

    ;; Copies five stacked bytes into the destination at <FunctionPointer>.
    ;;
    ;; DEF uses this to install its text and argument pointers; <Functions::Fn> uses it to restore the argument value.
    ;; Also: DEFFIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PopToFunctionPointer
    ldy #$00
    pla
    sta (FunctionPointer),y
    pla
    iny
    sta (FunctionPointer),y
    pla
    iny
    sta (FunctionPointer),y
    pla
    iny
    sta (FunctionPointer),y
    pla
    iny
    sta (FunctionPointer),y

;; The rts.
;; Also: DEFRTS (M6502)
Done:
    rts
    .endproc
.endmacro
