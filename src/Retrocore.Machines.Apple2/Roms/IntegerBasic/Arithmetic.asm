;; INTEGER BASIC: THE NOUN STACK AND ARITHMETIC ($E6FF-$E7C0)
;;
;; The routines that step through a line's tokens and move values on and off the noun stack, and the routines of
;; the comparison, sign and addition tokens; then TAB and the tab stops of PRINT's comma.
;;
;; Numbers are 16-bit two's complement. A result outside -32767 to 32767 is the >32767 error: addition checks the
;; 6502's overflow flag. Comparisons give 1 for true and 0 for false.
;;
;; Part of IntegerBasic.asm; it follows Interpreter.asm, at $E6FF.

;; Steps <PX> to the next byte of the line and reads it.
;; In: Y = 0
;; Out: A = the byte, N and Z set by it
;; Keeps: X, Y, carry
GETVERB:
    inc PX                          ; $E6FF
    bne @NoInc                      ; $E701
    inc PX+1                        ; $E703
@NoInc:
    lda (PX),y                      ; $E705
    rts                             ; $E707

;; Pushes a noun: A as its low byte and Y as its address high byte (0 for a number).
;;
;; The caller stores the high byte of a number in <NOUNSTKC>,X afterwards.
;; In: A = the low byte, Y = the high byte of an address, or 0, X = the noun stack
;; Out: X = the noun stack, one entry lower
;; Errors: PPED AT (the STOPPED AT message from its fourth character) when the stack is full
;; Keeps: A, Y
;; Entry: PUSHNOUNLO = leaves the address high byte as it was
PUSHNOUN:
    sty NOUNSTKH-1,x                ; $E708

PUSHNOUNLO:
    dex                             ; $E70A
    bmi PUSHNOUN_1                  ; $E70B
    sta NOUNSTKL,x                  ; $E70D
    rts                             ; $E70F

;; The error for a full noun stack: its message starts three characters into STOPPED AT.
PUSHNOUN_1:
    ldy #<(ErrMsg12+3)              ; $E710

GOERRMESS:
    jmp ERRMESS                     ; $E712

;; Pops a noun and returns its 16-bit value in ACC.
;;
;; An entry whose address high byte is not 0 is a variable, and the value is read from its address; otherwise the
;; entry holds the value.
;; In: X = the noun stack
;; Out: ACC = the value, X = the noun stack, one entry higher, Y = 0
;; Uses: A
;; See: <PUSHNOUN>, <GETBYTE>
GET16BIT:
    ldy #$00                        ; $E715
    lda NOUNSTKL,x                  ; $E717
    sta ACC                         ; $E719
    lda NOUNSTKC,x                  ; $E71B
    sta ACC+1                       ; $E71D
    lda NOUNSTKH,x                  ; $E71F
    beq GET16BIT_1                  ; $E721 a number: the entry holds it
    sta ACC+1                       ; $E723
    lda (ACC),y                     ; $E725 a variable: read its value
    pha                             ; $E727
    iny                             ; $E728
    lda (ACC),y                     ; $E729
    sta ACC+1                       ; $E72B
    pla                             ; $E72D
    sta ACC                         ; $E72E
    dey                             ; $E730

GET16BIT_1:
    inx                             ; $E731
    rts                             ; $E732

;; Numeric = (token $16): replaces two numbers with 1 if they are equal, 0 if not.
;;
;; <NOTEQUAL_NUM> gives 1 if they differ, and <NOT> turns that around.
;; See: <NOTEQUAL_NUM>, <NOT>
EQUAL_NUM:
    jsr NOTEQUAL_NUM                ; $E733

;; NOT (token $37): replaces a number with 1 if it is 0, 0 otherwise.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result
;; Uses: A, Y, ACC
NOT:
    jsr GET16BIT                    ; $E736
    tya                             ; $E739 A = 0
    jsr PUSHNOUN                    ; $E73A
    sta NOUNSTKC,x                  ; $E73D the high byte, 0
    cmp ACC                         ; $E73F
    bne @Return                     ; $E741
    cmp ACC+1                       ; $E743
    bne @Return                     ; $E745
    inc NOUNSTKL,x                  ; $E747 the low byte becomes 1
@Return:
    rts                             ; $E749

;; Numeric # and <> (tokens $17 and $1B): replaces two numbers with 1 if they differ, 0 if they are equal.
;;
;; The difference's sign (<SGN>) is -1, 0 or 1, and its absolute value (<ABS>, into which this falls) is the answer.
;; See: <SUBTRACT>, <SGN>, <ABS>
NOTEQUAL_NUM:
    jsr SUBTRACT                    ; $E74A
    jsr SGN                         ; $E74D

;; ABS (token $31): replaces a number with its absolute value.
;;
;; A number that is not negative stays as it is: the entry is pushed back (<REPUSHNOUN>) unchanged.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 for -32768
;; Uses: A, Y, ACC
ABS:
    jsr GET16BIT                    ; $E750
    bit ACC+1                       ; $E753
    bmi NEGATEACC                   ; $E755

;; Pushes the entry <GET16BIT> just popped back on the noun stack, as it was.
REPUSHNOUN:
    dex                             ; $E757

REPUSHNOUN_1:
    rts                             ; $E758

;; SGN (token $30): replaces a number with its sign: -1, 0 or 1.
;;
;; It pushes -1 and returns for a negative number, and negates it to 1 (falling into <NEGATE>) for a positive one.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result
;; Uses: A, Y, ACC
SGN:
    jsr GET16BIT                    ; $E759
    lda ACC+1                       ; $E75C
    bne SGN_1                       ; $E75E
    lda ACC                         ; $E760
    beq REPUSHNOUN                  ; $E762 0 stays 0

;; Pushes -1, then negates it unless the number was negative.
SGN_1:
    lda #$FF                        ; $E764
    jsr PUSHNOUN                    ; $E766
    sta NOUNSTKC,x                  ; $E769
    bit ACC+1                       ; $E76B
    bmi REPUSHNOUN_1                ; $E76D

;; Unary - (token $36): replaces a number with its negative.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 for -32768, which has no positive counterpart
;; Uses: A, Y, ACC
;; Entry: NEGATEACC = negates the value already in ACC, pushing the result
NEGATE:
    jsr GET16BIT                    ; $E76F

NEGATEACC:
    tya                             ; $E772 A = 0
    sec                             ; $E773
    sbc ACC                         ; $E774
    jsr PUSHNOUN                    ; $E776
    tya                             ; $E779
    sbc ACC+1                       ; $E77A
    bvc SETNOUNHI                   ; $E77C no overflow: store the high byte

;; The >32767 error.
Err32767:
    ldy #<ErrMsg00                  ; $E77E
    bpl GOERRMESS                   ; $E780

;; Subtraction (token $13): negates the top number, then adds (<PLUS>).
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the difference
;; Errors: >32767
SUBTRACT:
    jsr NEGATE                      ; $E782

;; Addition (token $12): replaces two numbers with their sum.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the sum
;; Errors: >32767 if the sum overflows
;; Uses: A, Y, ACC, AUX
;; Entry: ADDAUX = adds AUX to ACC and pushes the sum
PLUS:
    jsr GET16BIT                    ; $E785
    lda ACC                         ; $E788
    sta AUX                         ; $E78A
    lda ACC+1                       ; $E78C
    sta AUX+1                       ; $E78E
    jsr GET16BIT                    ; $E790

ADDAUX:
    clc                             ; $E793
    lda ACC                         ; $E794
    adc AUX                         ; $E796
    jsr PUSHNOUN                    ; $E798
    lda ACC+1                       ; $E79B
    adc AUX+1                       ; $E79D
    bvs Err32767                    ; $E79F

;; Stores the result's high byte; the end of addition and negation.
SETNOUNHI:
    sta NOUNSTKC,x                  ; $E7A1

;; Unary + (token $35): nothing to do.
POSITIVE:
    rts                             ; $E7A3

;; TAB (token $50): moves the cursor to column n (1 is the first) of the window, wrapping past its width onto the
;; lines below.
;;
;; TAB 0 is a RANGE error. It goes through <BcsRANGERR>, whose branch is always taken here: the carry is still set
;; from the interpreter's priority comparison.
;; In: X = the noun stack, its top entry the column
;; See: <SETCURCOL>
TAB:
    jsr GETBYTE                     ; $E7A4
    tay                             ; $E7A7
    bne TAB_1                       ; $E7A8
    jmp BcsRANGERR                  ; $E7AA

;; Counts the column from 0, then sets it (<SETCURCOL>).
TAB_1:
    dey                             ; $E7AD

TOCOLUMN:
    jmp SETCURCOL                   ; $E7AE

;; PRINT's comma: moves the cursor to the next tab stop, a multiple of 8 columns.
;;
;; <SETCURCOL> wraps the column onto the next line when it is past the window's width.
;; Uses: A, Y
;; Keeps: X
NEXTTAB:
    lda CH                          ; $E7B1
    ora #$07                        ; $E7B3
    tay                             ; $E7B5
    iny                             ; $E7B6 CH = $F8-$FF would wrap to 0

NEXTTAB_1:
    bne TOCOLUMN                    ; $E7B7
    iny                             ; $E7B9 Y = 1
    bne NEXTTAB                     ; $E7BA

;; Unused code; nothing in the ROM reaches it.
UNUSED_BCSTAB:
    bcs NEXTTAB_1                   ; $E7BC
    rts                             ; $E7BE
    .byte $00, $00                  ; $E7BF unused bytes
