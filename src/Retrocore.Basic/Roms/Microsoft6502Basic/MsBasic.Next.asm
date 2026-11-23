; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: NEXT AND RESULT-TYPE CHECKS
;
; NextEntries countedStack, nextStatement
;   countedStack = 1 advances X through the frame; 0 calculates the offsets in A.
;   nextStatement is the platform's continuation after <Statements::Next>.
; The frame holds a five-byte step, its sign and a five-byte packed limit.

.macro NextEntries countedStack, nextStatement
    .assert countedStack = 0 || countedStack = 1, "countedStack must be 0 or 1."

    .scope Statements continued

    ;; Executes NEXT, optionally naming a FOR variable and optionally continuing with a comma-separated list.
    ;;
    ;; <FindForFrame> locates the frame. The step is added to the variable and compared with the limit using the
    ;; step's sign; on continuation, the frame's line and text pointers restore the loop body. Otherwise the
    ;; frame is removed. An unmatched variable raises NEXT WITHOUT FOR.
    ;; Entry:
    ;;   ToError = with zero set, relays to <RequireType::ToError>, as for NEXT WITHOUT FOR (offset 0) and for
    ;;     `READ`'s input path (VariableInput), which branches here with `beq`; with zero clear, falls into
    ;;     <Statements::Next::AddStep>
    ;; Also: NEXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Next
    bne WithVariable
    ldy #$00
    beq SearchFrame

;; NEXT names a variable: <PTRGET>; the comma path jsr's here for the next variable.
;; Also: GETFOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
WithVariable:
    jsr PTRGET

;; <AssignedVariable> = A/Y (Y = 0: any), <FindForFrame>; no frame: NEXT WITHOUT FOR.
;; Also: STXFOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SearchFrame:
    sta AssignedVariable
    sty AssignedVariable+1
    jsr FindForFrame
    beq AddStep
    ldx #<ERROR_NEXT_WITHOUT_FOR

;; With zero set, relays to <RequireType::ToError>, as for NEXT WITHOUT FOR (offset 0) and for `READ`'s input path
;; (VariableInput), which branches here with `beq`; with zero clear, falls into <AddStep>.
;; Also: ERRGO5 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToError:
    beq RequireType::ToError

;; Sets the stack to the frame, adds <ForFrame::STEP> to the variable, stores, compares with <ForFrame::LIMIT> signed by
;; STEP_SIGN.
;; Also: HAVFOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AddStep:
    txs
    .if countedStack
        inx
        inx
        inx
        inx
        txa
        inx
        inx
        inx
        inx
        inx
        inx
        stx Pointer2
    .else
        txa
        clc
        adc #$04
        pha
        adc #$06
        sta Pointer2
        pla
    .endif
    ldy #$01
    jsr Float::LoadFac
    tsx
    lda Stack + 1 + ForFrame::STEP_SIGN,x
    sta FacSign
    lda AssignedVariable
    ldy AssignedVariable+1
    jsr Float::AddPacked
    jsr Float::StoreFacInVariable
    ldy #$01
    jsr Float::CompareAtPointer2
    tsx
    sec
    sbc Stack + 1 + ForFrame::STEP_SIGN,x
    beq EndLoop
    lda Stack + 1 + ForFrame::LINE,x
    sta CurrentLine
    lda Stack + 1 + ForFrame::LINE+1,x
    sta CurrentLine+1
    lda Stack + 1 + ForFrame::TEXT_POINTER,x
    sta TextPointer
    lda Stack + 1 + ForFrame::TEXT_POINTER_HIGH,x
    sta TextPointer+1

;; Jumps to the continuation.
;; Also: NEWSGO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToNextStatement:
    jmp nextStatement

;; Removes the frame (adds <FOR_FRAME_SIZE>); a comma continues with the next variable.
;; Also: LOOPDN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
EndLoop:
    txa
    adc #(FOR_FRAME_SIZE - 1)           ; carry is set
    tax
    txs
    jsr GetCurrentCharacter
    cmp #','
    bne ToNextStatement
    jsr GetNextCharacter
    jsr WithVariable
    .endproc
    .endscope

    ;; Evaluates an expression and requires its result to be numeric.
    ;; In: TextPointer = first character of the expression
    ;; Out: Fac = numeric result, TextPointer = terminating character
    ;; Errors: TYPE MISMATCH for a string
    ;; Also: FRMNUM (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc EvaluateNumber
    jsr FRMEVL
    .endproc

    ;; Requires the current expression result to be numeric.
    ;; In: ValueType = result type
    ;; Errors: TYPE MISMATCH for a string
    ;; Also: CHKNUM (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc RequireNumber
    clc
    .byte $24                   ; BIT zero-page skips the next byte
    .endproc

    ;; Requires the current expression result to be a string.
    ;; In: ValueType = result type
    ;; Errors: TYPE MISMATCH for a number
    ;; Also: CHKSTR (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc RequireString
    sec
    .endproc

    ;; Checks the result type selected by carry without changing <ValueType>.
    ;; In: carry = set for string or clear for numeric, ValueType = result type
    ;; Out: carry = selected type on success
    ;; Errors: TYPE MISMATCH if the types differ
    ;; Entry:
    ;;   ToError = jumps to <ERROR>; <Statements::Next::ToError> relays here
    ;; Also: CHKVAL (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc RequireType
    bit ValueType
    bmi IsString
    bcs Mismatch

;; Returns.
;; Also: CHKOK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts

;; A string result: succeeds only with carry set.
;; Also: DOCSTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
IsString:
    bcs Done

;; Reports TYPE MISMATCH: loads its error offset into X and jumps on to the error handler.
;; Also: CHKERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Mismatch:
    ldx #<ERROR_TYPE_MISMATCH

;; Jumps to <ERROR>; <Statements::Next::ToError> relays here.
;; Also: ERRGO4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToError:
    jmp ERROR
    .endproc
.endmacro
