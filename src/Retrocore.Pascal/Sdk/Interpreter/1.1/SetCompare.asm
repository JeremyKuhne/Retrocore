; retrocore: style=strict
;; Set comparisons: the end of <SetsEqual>, continued from bank 1, and <CompareSets>, which <EQU at Pcodes::Equal>,
;; <NEQ at Pcodes::NotEqual>, <LEQ at Pcodes::LessOrEqual> and <GEQ at Pcodes::GreaterOrEqual> run for sets.

; The comparisons, as the comparison handlers keep them in Comparison.

;; The offset byte of <SetsEqual::Branch>, the BEQ whose opcode is bank 1's last byte: when the shorter set has no
;; bytes, it goes to SetsEqualTail::CheckRest. Otherwise <SetsEqual> runs on into <SetsEqualTail>, after this byte.
SetsEqualOffset:
    .byte SetsEqualTail::CheckRest - SetsEqualOffset - 1

;; The rest of <SetsEqual>: compares the two sets' bytes as far as the shorter goes, checks that the rest of the longer
;; is empty, and returns to <SetsEqual>'s caller.
;; In:
;;   X = the <Stack> index of the set below's first byte, from <PopSets>
;;   Y = the shorter set's length in bytes
;; Out:
;;   carry = set when the sets are equal
;;   Stack = the sets, as far as the bytes compared were pulled; <CompareSets> drops them
.proc SetsEqualTail

;; How many bytes longer the set below is than the set on top, which <PopSets> leaves here: negative when it is
;; shorter.
LengthDifference = Work1

;; <SetsEqual>'s return address, less 1, which <SetsEqual> pulls from the stack and keeps here.
;; Also: FPRETA (WK11)
CallerReturn = Work4

    ; Compare a byte of the set on top, pulling it, with the set below's.
CompareByte:
    pla
    cmp Stack,x
    bne Different
    inx
    dey
    bne CompareByte

    ; Check that the rest of the longer set is empty: the set below's from X, or the set on top's, still on the
    ; stack.
CheckRest:
    lda LengthDifference
    bmi TopLonger
    jsr RestOfSecondEmpty
    jmp Return
TopLonger:
    tsx
    inx
    jsr RestOfFirstEmpty
    jmp Return

Different:
    clc

    ; Return to the byte after SetsEqual's JSR.
Return:
    inc CallerReturn
    bne JumpBack
    inc CallerReturn+1
JumpBack:
    jmp (CallerReturn)
.endproc

;; Compares two sets for <EQU at Pcodes::Equal>, <NEQ at Pcodes::NotEqual>, <LEQ at Pcodes::LessOrEqual> or
;; <GEQ at Pcodes::GreaterOrEqual>, and pushes the boolean in their place.
;;
;; <LEQ at Pcodes::LessOrEqual> tests that the set below, the first operand, is a subset of the set on top; any other
;; comparison but <COMPARISON_EQUAL>, <COMPARISON_NOT_EQUAL> and <COMPARISON_LESS_OR_EQUAL> is
;; <GEQ at Pcodes::GreaterOrEqual>, which tests that it is a superset.
;; In: Comparison = the comparison, Stack = the two sets, each with its length in words on top of its bytes
;; Also: CMPSET (WK11)
.proc CompareSets

;; The stack pointer once both sets are dropped, which <PopSets> leaves here.
StackAfter = Result

;; The boolean, as a word, before it is pushed.
Boolean = Result + 4

;; The <Stack> index of the set below's first byte, which <PopSets> leaves here.
BelowStart = Pointer

;; The shorter set's length in bytes, which <PopSets> leaves here.
ShorterLength = Mark

    ; Which comparison?
    lda Comparison
    cmp #COMPARISON_EQUAL
    bne NotEqu
    jmp Equal
NotEqu:
    cmp #COMPARISON_NOT_EQUAL
    bne NotNeq
    jmp NotEqual
NotNeq:
    cmp #COMPARISON_LESS_OR_EQUAL
    bne Superset
    beq Subset

    ; EQU: the sets are equal.
Equal:
    jsr SetsEqual
    jmp Push

    ; NEQ: the sets are not equal.
NotEqual:
    jsr SetsEqual
    bcs Same
    sec
    bcs NeqDone
Same:
    clc
NeqDone:
    jmp Push

    ; LEQ: no byte of the set below has a bit the set on top's lacks, pulling the set on top's bytes as it goes.
Subset:
    jsr PopSets
    ldx BelowStart
    ldy ShorterLength
    beq SubsetRest
SubsetByte:
    pla
    eor #$FF
    and Stack,x
    bne False
    inx
    dey
    bne SubsetByte

    ; The set below's bytes past the set on top's must be empty.
SubsetRest:
    jsr RestOfSecondEmpty
    jmp Push

    ; GEQ: no byte of the set on top has a bit the set below's lacks.
Superset:
    jsr PopSets
    ldy BelowStart
    tsx
    inx
    lda ShorterLength
    beq SupersetRest
SupersetByte:
    lda Stack,y
    eor #$FF
    and Stack,x
    bne False
    inx
    iny
    dec ShorterLength
    bne SupersetByte

    ; The set on top's bytes past the set below's must be empty.
SupersetRest:
    jsr RestOfFirstEmpty
    jmp Push

False:
    clc

;; Drops both sets, and pushes carry as a boolean.
;; Also: STOANS (WK11)
Push:
    ldx StackAfter
    txs
    ldy #0
    sty Boolean+1
    bcc PushBoolean
    iny
PushBoolean:
    sty Boolean
    lda Boolean+1
    pha
    lda Boolean
    pha
    jmp Fetch::Skip2
.endproc
