; retrocore: style=strict
;; <XJP at Pcodes::CaseJump>, the case jump.

; XJP's operands, from InstructionPointer once XJP has made it odd, so that they are word aligned.

;; The case's lowest value, a word.
XJP_MINIMUM = 1

;; The case's highest value, a word.
XJP_MAXIMUM = 3

;; The <UJP at Jump::Always> to the code for a value out of range.
XJP_DEFAULT = 5

;; The jump table: a word for each value from <XJP_MINIMUM>, holding its own distance above the value's code.
XJP_TABLE = 7

; Pcodes: CaseJump.
.scope Pcodes continued

;; <XJP at Pcodes::CaseJump>: pops a value and jumps to its case through the jump table, or runs the
;; <UJP at Jump::Always> after the bounds when the value is out of range. The bounds are signed.
;; Also: XJP (A2POSRM, UCSD20, WK11)
.proc CaseJump

;; The value.
Value = Work4

;; The value's jump table word.
Entry = Work4

    ; Make InstructionPointer odd, stepping over the pad byte when there is one, and pop the value.
    lda #1
    ora InstructionPointer
    sta InstructionPointer
    pla
    sta Value
    pla
    sta Value+1

    ; Is it at least the minimum? Different signs: only when the value is positive.
    ldy #XJP_MINIMUM + 1
    eor (InstructionPointer),y
    bmi MinimumSign
    lda (InstructionPointer),y
    cmp Value+1
    bcc CheckMaximum
    bne OutOfRange
    dey
    lda Value
    cmp (InstructionPointer),y
    bcs CheckMaximum
    bcc OutOfRange
MinimumSign:
    lda Value+1
    bmi OutOfRange

    ; Is it at most the maximum? Different signs: only when the value is negative.
CheckMaximum:
    ldy #XJP_MAXIMUM + 1
    lda (InstructionPointer),y
    eor Value+1
    bmi MaximumSign
    lda Value+1
    cmp (InstructionPointer),y
    bcc InRange
    bne OutOfRange
    dey
    lda (InstructionPointer),y
    cmp Value
    bcs InRange
    bcc OutOfRange
MaximumSign:
    lda Value+1
    bpl OutOfRange

    ; In range: find the value's word in the jump table, at XJP_TABLE plus twice the value less the minimum.
InRange:
    sec
    ldy #XJP_MINIMUM
    lda Value
    sbc (InstructionPointer),y
    sta Value
    lda Value+1
    iny
    sbc (InstructionPointer),y
    sta Value+1
    asl Value
    rol Value+1
    lda InstructionPointer
    clc
    adc Value
    sta Entry
    lda InstructionPointer+1
    adc Value+1
    sta Entry+1
    lda Entry
    clc
    adc #XJP_TABLE
    sta Entry
    bcc Jump
    inc Entry+1

    ; Jump to the code the word gives.
Jump:
    ldy #0
    sec
    lda Entry
    sbc (Entry),y
    sta InstructionPointer
    lda Entry+1
    iny
    sbc (Entry),y
    sta InstructionPointer+1
    jmp Fetch::Next

;; Runs the <UJP> after the bounds: the index is out of their range.
;; Also: OUTBND (WK11)
OutOfRange:
    lda InstructionPointer
    clc
    adc #XJP_DEFAULT
    sta InstructionPointer
    bcc Default
    inc InstructionPointer+1
Default:
    jmp Fetch::Next
.endproc
.endscope
