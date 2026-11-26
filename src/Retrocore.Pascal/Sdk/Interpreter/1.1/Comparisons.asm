; retrocore: style=strict
;; Comparisons: the handlers for <EQU at Pcodes::Equal>, <NEQ at Pcodes::NotEqual>, <LES at Pcodes::Less>,
;; <LEQ at Pcodes::LessOrEqual>, <GRT at Pcodes::Greater> and <GEQ at Pcodes::GreaterOrEqual>, which compare reals,
;; strings, booleans, sets and arrays, and for their integer forms, <EQUI at Pcodes::EqualIntegers> to
;; <GEQI at Pcodes::GreaterOrEqualIntegers>.
;;
;; Each handler loads its kind of comparison, and they share the rest. The comparison finds whether the lower
;; operand is less than, equal to or greater than the top one, and pushes true when that outcome is in the kind.

; The kinds of comparison the handlers leave in Comparison, for CompareSets too. A kind is the outcomes that make it
; true, a bit for each.

; The types EQU to GEQ compare, their first operand.

;; Two reals.
COMPARE_REAL = 2

;; Two strings, either of which may be a character.
COMPARE_STRING = 4

;; Two booleans.
COMPARE_BOOLEAN = 6

;; Two sets, which <CompareSets> compares.
COMPARE_SET = 8

;; Two arrays of bytes, whose size in bytes follows as a big operand.
COMPARE_BYTES = 10

;; Two arrays of words, whose size in words follows as a big operand. The handlers take any type not above as this.
COMPARE_WORDS = 12

; Reals, as the comparisons pop them.

; How the reals' bytes compare, in Y.

;; Either real is positive, so their bytes, sign bits flipped, compare in order. Any positive value would do.
REALS_IN_ORDER = 1

;; Both reals are negative, so the outcome of comparing their bytes is reversed. Any negative value would do.
REALS_REVERSED = $F4

; Pcodes: the comparisons, of every type and of integers.
.scope Pcodes continued

;; <NEQ at Pcodes::NotEqual>: compares the two operands on the stack for inequality.
;; Also: NEQ (A2POSRM, UCSD20, WK11), NEQBOOL (A2POSRM), NEQBYT (A2POSRM), NEQPOWR (A2POSRM), NEQREAL (A2POSRM),
;;   NEQSTR (A2POSRM), NEQWORD (A2POSRM)
.proc NotEqual
    lda #COMPARISON_NOT_EQUAL
    bpl Pcodes::Equal::Compare
.endproc

;; <GRT at Pcodes::Greater>: compares whether the lower operand on the stack is greater than the top one.
;; Also: GRT (A2POSRM, UCSD20, WK11), GRTBOOL (A2POSRM), GRTBYT (A2POSRM), GRTSTR (A2POSRM), GTRREAL (A2POSRM)
.proc Greater
    lda #COMPARISON_GREATER
    bpl Pcodes::Equal::Compare
.endproc

;; <LES at Pcodes::Less>: compares whether the lower operand on the stack is less than the top one.
;; Also: LES (A2POSRM, UCSD20, WK11), LESBOOL (A2POSRM), LESBYT (A2POSRM), LESREAL (A2POSRM), LESSTR (A2POSRM)
.proc Less
    lda #COMPARISON_LESS
    bpl Pcodes::Equal::Compare
.endproc

;; <GEQ at Pcodes::GreaterOrEqual>: compares whether the lower operand on the stack is greater than or equal to the top
;; one.
;; Also: GEQ (A2POSRM, WK11), GEQBOOL (A2POSRM), GEQBYT (A2POSRM), GEQPOWR (A2POSRM), GEQREAL (A2POSRM),
;;   GEQSTR (A2POSRM)
.proc GreaterOrEqual
    lda #COMPARISON_GREATER_OR_EQUAL
    bpl Pcodes::Equal::Compare
.endproc

;; <LEQ at Pcodes::LessOrEqual>: compares whether the lower operand on the stack is less than or equal to the top one.
;; Also: LEQ (A2POSRM, UCSD20, WK11), LEQBOOL (A2POSRM), LEQBYT (A2POSRM), LEQPOWR (A2POSRM), LEQREAL (A2POSRM),
;;   LEQSTR (A2POSRM)
.proc LessOrEqual
    lda #COMPARISON_LESS_OR_EQUAL
    bpl Pcodes::Equal::Compare
.endproc

;; <EQU at Pcodes::Equal>: compares the two operands on the stack for equality, and pushes the boolean.
;;
;; Its operand is the type it compares, <COMPARE_REAL> to <COMPARE_WORDS>, followed for arrays by their size.
;; Entry: Compare = makes the comparison in A instead, a kind such as <COMPARISON_LESS_OR_EQUAL>
;; Also: EQU (A2POSRM, UCSD20), EQUBOOL (A2POSRM), EQUBYT (A2POSRM), EQUPOWR (A2POSRM), EQUREAL (A2POSRM),
;;   EQUSTR (A2POSRM), EQUWORD (A2POSRM)
.proc Equal

;; The top operand's address, or the character a string is.
Top = Pointer2

;; The lower operand's address, or the character a string is.
Lower = Pointer

;; The bytes of an array still to compare: X counts the low byte, and the high byte counts runs of 256.
Count = Offset

;; A string of one character, made from a top operand that is a character.
TopCharString = Mark

;; A string of one character, made from a lower operand that is a character.
LowerCharString = Result

;; The two reals, 8 bytes, most significant first: the lower one, then the top one at <TopReal>.
Reals = Pointer

;; The top real, in <Reals>.
TopReal = Reals + REAL_SIZE

;; The top boolean's bit 0.
TopBoolean = Pointer

    lda #COMPARISON_EQUAL

;; Makes the comparison in A.
;; In: A = the kind
Compare:
    sta Comparison

    ; Go to the comparison for the type.
    ldy #1
    lda (InstructionPointer),y
    cmp #COMPARE_REAL
    bne NotReal
    jmp CompareReals
NotReal:
    cmp #COMPARE_STRING
    bne NotString
    jmp CompareStrings
NotString:
    cmp #COMPARE_BOOLEAN
    bne NotBoolean
    jmp CompareBooleans
NotBoolean:
    cmp #COMPARE_SET
    bne NotSet
    jmp CompareSets

    ; Arrays: read their size, in bytes.
NotSet:
    cmp #COMPARE_BYTES
    beq Bytes
    bne Words

;; Compares two byte arrays, whose size in bytes follows the opcode and its type byte, as a big operand.
;; Also: CMPBAR (WK11)
Bytes:
    ldy #2
    jsr GetBig
    lsr Count+1
    ror Count
    jmp CompareArrays
Words:
    ldy #2
    jsr GetBig

    ; Pop the addresses, and step InstructionPointer past the type. Fetch::Skip2 steps past the opcode and the size.
CompareArrays:
    pla
    sta Top
    pla
    sta Top+1
    pla
    sta Lower
    pla
    sta Lower+1
    inc InstructionPointer
    bne CountBytes
    inc InstructionPointer+1
CountBytes:
    ldy #0
    ldx Count
    jmp CountByte

    ; Compare a byte at a time, until two differ.
CompareByte:
    lda (Lower),y
    cmp (Top),y
    bne Differ
    inc Lower
    bne StepTop
    inc Lower+1
StepTop:
    inc Top
    bne NextByte
    inc Top+1
NextByte:
    dex
CountByte:
    bne CompareByte
    dec Count+1
    bpl CompareByte
    jmp Equal

    ; The first that differ decide it.
Differ:
    bcs DifferGreater
    jmp Less
DifferGreater:
    jmp Greater

;; The addresses of <TopCharString> and <LowerCharString>, for the strings' pointers.
;; Also: ADRA7E (WK11)
CharStrings:
    .word TopCharString
    .word LowerCharString

;; Compares two strings; a character, whose high byte is 0, is a string of 1.
;; Also: CMPSTR (WK11)
CompareStrings:
    pla
    sta Top
    pla
    sta Top+1
    bne PopLower
    lda Top
    sta TopCharString+1
    lda #1
    sta TopCharString
    lda CharStrings
    sta Top
    lda CharStrings+1
    sta Top+1
PopLower:
    pla
    sta Lower
    pla
    sta Lower+1
    bne CompareLengths
    lda Lower
    sta LowerCharString+1
    lda #1
    sta LowerCharString
    lda CharStrings+2
    sta Lower
    lda CharStrings+3
    sta Lower+1

    ; Compare as many characters as the shorter string has, until two differ.
CompareLengths:
    ldy #0
    lda (Lower),y
    cmp (Top),y
    bcc CountCharacters
    lda (Top),y
CountCharacters:
    tax
    inx
NextCharacter:
    dex
    beq SameStart
    iny
    lda (Lower),y
    cmp (Top),y
    beq NextCharacter
    bcs Greater
    bcc Less

    ; They match as far as the shorter goes: the shorter is the less.
SameStart:
    ldy #0
    lda (Lower),y
    cmp (Top),y
    bcc Less
    beq Equal
    bne Greater

;; Tests for a greater outcome: pushes true when the outcome is one the comparison asks for.
;; Also: ISHIGH (WK11)
Greater:
    lda #COMPARISON_GREATER
    bpl Test

;; Tests for an equal outcome.
;; Also: ISEQ (WK11)
Equal:
    lda #COMPARISON_EQUAL
    bpl Test

;; Tests for a less outcome.
;; Also: ISLOW (WK11)
Less:
    lda #COMPARISON_LESS
Test:
    and Comparison
    beq PushFalse
    lda #0
    pha
    lda #BOOLEAN_TRUE
    pha
    jmp Fetch::Skip2

;; Pushes false and goes on after the opcode's two bytes.
;; Also: FALSE1 (WK11)
PushFalse:
    lda #BOOLEAN_FALSE
    pha
    pha
    jmp Fetch::Skip2

;; Compares two reals, popping both, most significant byte first.
;; Also: CMPR (WK11)
CompareReals:
    ldx #2 * REAL_SIZE - 1
PopReal:
    pla
    sta Reals,x
    dex
    bpl PopReal

    ; Flip both sign bits, so a positive real's bytes compare above a negative one's. When both are negative, the
    ; outcome is reversed.
    ldy #REALS_IN_ORDER
    lda #REAL_NEGATIVE
    eor TopReal
    sta TopReal
    bmi FlipLower
    lda Reals
    bpl FlipLower
    ldy #REALS_REVERSED
FlipLower:
    lda #REAL_NEGATIVE
    eor Reals
    sta Reals

    ; Compare the bytes until two differ.
    ldx #0
CompareRealByte:
    lda Reals,x
    cmp TopReal,x
    bne RealsDiffer
    inx
    cpx #REAL_SIZE
    bne CompareRealByte
    beq Equal
RealsDiffer:
    tya
    bmi Reversed
    bcs Greater
    jmp Less
Reversed:
    bcc Greater
    jmp Less

;; Compares two booleans by their bit 0, false being the less.
;; Also: CMPB (WK11)
CompareBooleans:
    pla
    and #1
    sta TopBoolean
    pla
    pla
    and #1
    tay
    pla
    tya
    cmp TopBoolean
    bcc Less
    beq Equal
    jmp Greater
.endproc

;; <LESI at Pcodes::LessIntegers>: compares whether the lower integer on the stack is less than the top one.
;; Also: LESI (A2POSRM, WK11)
.proc LessIntegers
    lda #COMPARISON_LESS
    bpl Pcodes::NotEqualIntegers::Compare
.endproc

;; <GRTI at Pcodes::GreaterIntegers>: compares whether the lower integer on the stack is greater than the top one.
;; Also: GRTI (A2POSRM, WK11)
.proc GreaterIntegers
    lda #COMPARISON_GREATER
    bpl Pcodes::NotEqualIntegers::Compare
.endproc

;; <LEQI at Pcodes::LessOrEqualIntegers>: compares whether the lower integer on the stack is less than or equal to the
;; top one.
;; Also: LEQI (A2POSRM, WK11)
.proc LessOrEqualIntegers
    lda #COMPARISON_LESS_OR_EQUAL
    bpl Pcodes::NotEqualIntegers::Compare
.endproc

;; <GEQI at Pcodes::GreaterOrEqualIntegers>: compares whether the lower integer on the stack is greater than or equal to
;; the top one.
;; Also: GEQI (A2POSRM, WK11)
.proc GreaterOrEqualIntegers
    lda #COMPARISON_GREATER_OR_EQUAL
    bpl Pcodes::NotEqualIntegers::Compare
.endproc

;; <NEQI at Pcodes::NotEqualIntegers>: compares the two integers on the stack for inequality, and pushes the boolean.
;; Entry: Compare = makes the comparison in A instead, a kind such as <COMPARISON_LESS>
;; Also: NEQI (A2POSRM, WK11)
.proc NotEqualIntegers

;; The top integer.
Top = Pointer2

;; The lower integer.
Lower = Pointer

    lda #COMPARISON_NOT_EQUAL

;; Makes the comparison in A, and pushes the boolean through <Pcodes::EqualIntegers>'s outcomes.
;; In: A = the kind
Compare:
    sta Comparison

    ; Pop the integers. Do their signs differ?
    pla
    sta Top
    pla
    sta Top+1
    pla
    sta Lower
    pla
    sta Lower+1
    eor Top+1
    bmi SignsDiffer

    ; No: compare the high bytes, then the low.
    lda Lower+1
    cmp Top+1
    bne Differ
    lda Lower
    cmp Top
    beq Pcodes::EqualIntegers::Equal
Differ:
    bcc Pcodes::EqualIntegers::Less
    bcs Pcodes::EqualIntegers::Greater

    ; Yes: the negative one is the less.
SignsDiffer:
    lda Lower+1
    bmi Pcodes::EqualIntegers::Less
    bpl Pcodes::EqualIntegers::Greater
.endproc

;; <EQUI at Pcodes::EqualIntegers>: compares the two integers on the stack for equality, and pushes the boolean.
;; Entry:
;;   Greater = pushes true when <Comparison> includes <COMPARISON_GREATER>
;;   Equal = pushes true when <Comparison> includes <COMPARISON_EQUAL>
;;   Less = pushes true when <Comparison> includes <COMPARISON_LESS>
;; Also: EQUI (A2POSRM, WK11)
.proc EqualIntegers

;; The top integer.
Top = Pointer

    ; Pop the top integer, and compare the lower one's low byte.
    pla
    sta Top
    pla
    sta Top+1
    pla
    cmp Top
    bne LowDiffers

    ; Then its high byte.
    pla
    cmp Top+1
    bne PushFalse

;; Pushes true.
;; Also: TRUE (WK11)
PushTrue:
    lda #0
    pha
    lda #BOOLEAN_TRUE
    pha
    jmp Fetch::Skip1

    ; Pop the lower one's high byte, and push false.
LowDiffers:
    pla
    lda #BOOLEAN_FALSE
    pha
    pha
    jmp Fetch::Skip1

;; Pushes true when <Comparison> includes <COMPARISON_GREATER>.
Greater:
    lda #COMPARISON_GREATER
    bpl Test

;; Pushes true when <Comparison> includes <COMPARISON_EQUAL>.
Equal:
    lda #COMPARISON_EQUAL
    bpl Test

;; Pushes true when <Comparison> includes <COMPARISON_LESS>.
Less:
    lda #COMPARISON_LESS

    ; Push true when the outcome is in the kind.
Test:
    and Comparison
    bne PushTrue

;; Pushes false.
;; Also: FALSE2 (WK11)
PushFalse:
    lda #BOOLEAN_FALSE
    pha
    pha
    jmp Fetch::Skip1
.endproc
.endscope
