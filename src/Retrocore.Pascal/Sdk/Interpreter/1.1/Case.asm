; retrocore: style=strict
;; <XJP at OpXJP>, the case jump.

; XJP's operands, from IPC once XJP has made it odd, so that they are word aligned.

;; The case's lowest value, a word.
XJP_MINIMUM = 1

;; The case's highest value, a word.
XJP_MAXIMUM = 3

;; The <UJP at Jump::Always> to the code for a value out of range.
XJP_DEFAULT = 5

;; The jump table: a word for each value from <XJP_MINIMUM>, holding its own distance above the value's code.
XJP_TABLE = 7

;; <XJP at OpXJP>: pops a value and jumps to its case through the jump table, or runs the <UJP at Jump::Always> after
;; the bounds when the value is out of range. The bounds are signed.
;; Also: XJP (A2POSRM, UCSD20)
.proc OpXJP

;; The value.
Value = Work4

;; The value's jump table word.
Entry = Work4

    ; Make IPC odd, stepping over the pad byte when there is one, and pop the value.
    lda #1
    ora IPC
    sta IPC
    pla
    sta Value
    pla
    sta Value+1

    ; Is it at least the minimum? Different signs: only when the value is positive.
    ldy #XJP_MINIMUM + 1
    eor (IPC),y
    bmi MinimumSign
    lda (IPC),y
    cmp Value+1
    bcc CheckMaximum
    bne OutOfRange
    dey
    lda Value
    cmp (IPC),y
    bcs CheckMaximum
    bcc OutOfRange
MinimumSign:
    lda Value+1
    bmi OutOfRange

    ; Is it at most the maximum? Different signs: only when the value is negative.
CheckMaximum:
    ldy #XJP_MAXIMUM + 1
    lda (IPC),y
    eor Value+1
    bmi MaximumSign
    lda Value+1
    cmp (IPC),y
    bcc InRange
    bne OutOfRange
    dey
    lda (IPC),y
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
    sbc (IPC),y
    sta Value
    lda Value+1
    iny
    sbc (IPC),y
    sta Value+1
    asl Value
    rol Value+1
    lda IPC
    clc
    adc Value
    sta Entry
    lda IPC+1
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
    sta IPC
    lda Entry+1
    iny
    sbc (Entry),y
    sta IPC+1
    jmp Fetch::Next

;; Runs the UJP after the table: the index is out of its range.
;; Also: OUTBND (WK11)
OutOfRange:
    lda IPC
    clc
    adc #XJP_DEFAULT
    sta IPC
    bcc Default
    inc IPC+1
Default:
    jmp Fetch::Next
.endproc
