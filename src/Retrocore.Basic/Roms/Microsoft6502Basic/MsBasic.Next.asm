; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: NEXT AND RESULT-TYPE CHECKS
;
; NEXT_ENTRIES countedStack, nextStatement
;   countedStack = 1 advances X through the frame; 0 calculates the offsets in A.
;   nextStatement is the platform's continuation after <NEXT>.
; The frame holds a five-byte step, its sign and a five-byte packed limit.

.macro NEXT_ENTRIES countedStack, nextStatement
    .assert countedStack = 0 || countedStack = 1, "countedStack must be 0 or 1."

;; Executes NEXT, optionally naming a FOR variable and optionally continuing with a comma-separated list.
;;
;; <FNDFOR> locates the frame. The step is added to the variable and compared with the limit using the
;; step's sign; on continuation, the frame's line and text pointers restore the loop body. Otherwise the
;; frame is removed. An unmatched variable raises NEXT WITHOUT FOR.
NEXT:
    bne GETFOR
    ldy #$00
    beq STXFOR

GETFOR:
    jsr PTRGET

STXFOR:
    sta FORPNT
    sty FORPNT+1
    jsr FNDFOR
    beq HAVFOR
    ldx #<ERRNF

ERRGO5:
    beq ERRGO4

HAVFOR:
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
    stx INDEX2
.else
    txa
    clc
    adc #$04
    pha
    adc #$06
    sta INDEX2
    pla
.endif
    ldy #$01
    jsr MOVFM
    tsx
    lda Stack + 1 + ForFrame::STEP_SIGN,x
    sta FACSGN
    lda FORPNT
    ldy FORPNT+1
    jsr FADD
    jsr MOVVF
    ldy #$01
    jsr FCOMPN
    tsx
    sec
    sbc Stack + 1 + ForFrame::STEP_SIGN,x
    beq LOOPDN
    lda Stack + 1 + ForFrame::LINE,x
    sta CURLIN
    lda Stack + 1 + ForFrame::LINE+1,x
    sta CURLIN+1
    lda Stack + 1 + ForFrame::TEXT_POINTER,x
    sta TXTPTR
    lda Stack + 1 + ForFrame::TEXT_POINTER_HIGH,x
    sta TXTPTR+1

NEWSGO:
    jmp nextStatement

LOOPDN:
    txa
    adc #$11
    tax
    txs
    jsr CHRGOT
    cmp #$2C
    bne NEWSGO
    jsr CHRGET
    jsr GETFOR

;; Evaluates an expression and requires its result to be numeric.
;; In: TXTPTR = first character of the expression
;; Out: FAC = numeric result, TXTPTR = terminating character
;; Errors: TYPE MISMATCH for a string
FRMNUM:
    jsr FRMEVL

;; Requires the current expression result to be numeric.
;; In: VALTYP = result type
;; Errors: TYPE MISMATCH for a string
CHKNUM:
    clc
    .byte $24                   ; BIT zero-page skips the next byte

;; Requires the current expression result to be a string.
;; In: VALTYP = result type
;; Errors: TYPE MISMATCH for a number
CHKSTR:
    sec

;; Checks the result type selected by carry without changing <VALTYP>.
;; In: carry = set for string or clear for numeric, VALTYP = result type
;; Out: carry = selected type on success
;; Errors: TYPE MISMATCH if the types differ
CHKVAL:
    bit VALTYP
    bmi DOCSTR
    bcs CHKERR

CHKOK:
    rts

DOCSTR:
    bcs CHKOK

CHKERR:
    ldx #<ERRTM

ERRGO4:
    jmp ERROR
.endmacro
