; retrocore: style=strict ignore=unlinked-name:BASIC -- the language's name in prose
;; Integer BASIC: the noun stack and arithmetic ($E6FF-$E7C0)
;;
;; The routines that step through a line's tokens and move values on and off the noun stack, and the routines of
;; the comparison, sign and addition tokens; then `TAB` and the tab stops of `PRINT`'s comma.
;;
;; Numbers are 16-bit two's complement. A result that does not fit is the >32767 error: addition checks the 6502's
;; overflow flag, so it allows -32768, which only negating or printing it turns into the error. Comparisons give 1
;; for true and 0 for false.
;;
;; Part of IntegerBasic.asm; it follows Interpreter.asm, at $E6FF.

; Interpreter: reading the next byte of a line.
.scope Interpreter continued

;; Steps <TokenPointer> to the next byte of the line and reads it.
;; In: Y = the index to read at, normally 0
;; Out: A = the byte at <TokenPointer> + Y, negative and zero = set by it
;; Keeps: X, Y, carry, overflow
;; Also: GETVERB (IBSM)
.proc ReadNextByte
    inc TokenPointer
    bne Read
    inc TokenPointer+1
Read:
    lda (TokenPointer),y
    rts
.endproc

.endscope

;; Pushes a noun: A as its low byte and Y as its address high byte (0 for a number).
;;
;; The caller stores the high byte of a number in <NounStackNumberHigh>,X afterwards.
;; In: A = the low byte, Y = the high byte of an address, or 0, X = the noun stack
;; Out: X = the noun stack, one entry lower
;; Errors: PPED AT (the STOPPED AT message from its fourth character) when the stack is full
;; Keeps: A, Y, carry, overflow
;; Entry:
;;   LowOnly = pushes A, leaving the entry's address high byte as it was
;;   ToReportError = reports the error whose message is at offset Y
;; Also: PUSHNOUN (UNKN)
.proc PushNoun
    sty NounStackHigh-1,x

;; Pushes A as an entry's low byte, leaving its address high byte as it was.
;; Also: PUSHNOUNLO (UNKN)
LowOnly:
    dex
    bmi Full
    sta NounStackLow,x
    rts

    ; The stack is full: its error's message starts three characters into STOPPED AT.
Full:
    ldy #<(ErrMsg12+3)

;; Reports the error whose message is at offset Y (<ERRMESS>).
;; Also: GOERRMESS (UNKN)
ToReportError:
    jmp ERRMESS
.endproc

;; Pops a noun and returns its 16-bit value in <Accumulator>.
;;
;; An entry whose address high byte is not 0 is a variable, and the value is read from its address; otherwise the
;; entry holds the value.
;; In: X = the noun stack
;; Out: Accumulator = the value, X = the noun stack, one entry higher, Y = 0
;; Uses: A
;; Keeps: carry, overflow
;; See: <PushNoun>, <GETBYTE>
;; Also: GET16BIT (IBSM)
.proc GetNumber
    ldy #0
    lda NounStackLow,x
    sta Accumulator
    lda NounStackNumberHigh,x
    sta Accumulator+1
    lda NounStackHigh,x
    beq Pop

    ; A variable: reads its value through its address.
    sta Accumulator+1
    lda (Accumulator),y
    pha
    iny
    lda (Accumulator),y
    sta Accumulator+1
    pla
    sta Accumulator
    dey
Pop:
    inx
    rts
.endproc

; Operators: = and NOT, then # and <>, which fall into ABS.
.scope Operators continued

;; Numeric `=` (token $16): replaces two numbers with 1 if they are equal, 0 if not.
;;
;; <Operators::NotEqual> gives 1 if they differ, and `NOT` (<Operators::Not>, into which this falls) turns that
;; around.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the result
;; Errors: >32767 for numbers too far apart, as <Operators::NotEqual>
;; Uses: A, Y, Accumulator, Auxiliary
;; Also: EQUAL_NUM (UNKN)
.proc Equal
    jsr NotEqual
    ; Falls into Not.
.endproc

;; `NOT` (token $37): replaces a number with 1 if it is 0, 0 otherwise.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result, A = 0, Y = 0, zero = clear
;; Uses: Accumulator
;; Keeps: X
;; Also: NOT (IBSM)
.proc Not
    jsr GetNumber
    tya                             ; A = 0
    jsr PushNoun
    sta NounStackNumberHigh,x
    cmp Accumulator
    bne Done
    cmp Accumulator+1
    bne Done
    inc NounStackLow,x              ; the low byte becomes 1
Done:
    rts
.endproc

;; Numeric `#` and `<>` (tokens $17 and $1B): replaces two numbers with 1 if they differ, 0 if they are equal.
;;
;; The difference's sign (<Functions::Sgn>) is -1, 0 or 1, and its absolute value (<Functions::Abs>, into which this
;; falls) is the answer. The difference is taken as <Operators::Subtract> takes it, so two numbers whose difference
;; does not fit in 16 bits, such as 20000 and -20000, are the >32767 error instead of a comparison.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the result, Y = 0
;; Errors: >32767 if the difference does not fit, or the top number is -32768
;; Uses: A, Accumulator, Auxiliary
;; Also: NOTEQUAL_NUM (UNKN)
.proc NotEqual
    jsr Subtract
    jsr Functions::Sgn
    ; Falls into Functions::Abs.
.endproc

.endscope

; Functions: ABS and SGN.
.scope Functions continued

;; `ABS` (token $31): replaces a number with its absolute value.
;;
;; A number that is not negative stays as it is: the entry is pushed back (<Functions::Abs::Repush>) unchanged.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result, Y = 0
;; Errors: >32767 for -32768
;; Uses: A, Accumulator
;; Keeps: X
;; Entry:
;;   Repush = pushes back the entry <GetNumber> has just popped
;;   Done = returns
;; Also: ABS (IBSM)
.proc Abs
    jsr GetNumber
    bit Accumulator+1
    bmi Operators::Negate::FromAccumulator

;; Pushes back the entry <GetNumber> has just popped, as it was.
;; Also: REPUSHNOUN (UNKN)
Repush:
    dex
Done:
    rts
.endproc

;; `SGN` (token $30): replaces a number with its sign: -1, 0 or 1.
;;
;; 0 stays as it is. Otherwise it pushes -1, and returns for a negative number; for a positive one it falls into
;; <Operators::Negate>, which turns the -1 into 1.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result, Y = 0
;; Uses: A, Accumulator
;; Keeps: X
;; Also: SGN (IBSM)
.proc Sgn
    jsr GetNumber
    lda Accumulator+1
    bne NotZero
    lda Accumulator
    beq Abs::Repush

    ; -1, which stays for a negative number.
NotZero:
    lda #$FF
    jsr PushNoun
    sta NounStackNumberHigh,x
    bit Accumulator+1
    bmi Abs::Done
    ; Falls into Operators::Negate.
.endproc

.endscope

; Operators: unary -, then subtraction and addition, which end in unary +.
.scope Operators continued

;; Unary `-` (token $36): replaces a number with its negative.
;; In: X = the noun stack
;; Out: X = the noun stack, its top entry the result, Y = 0
;; Errors: >32767 for -32768, which has no positive counterpart
;; Uses: A, Accumulator
;; Keeps: X
;; Entry:
;;   FromAccumulator = negates the value in <Accumulator> and pushes the result
;;   OverflowError = the >32767 error
;; Also: NEGATE (IBSM)
.proc Negate
    jsr GetNumber

;; Negates the value in <Accumulator> and pushes the result.
;; In: Accumulator = the value, Y = 0, X = the noun stack
;; Out: X = the noun stack, one entry lower, its top entry the result
;; Errors: >32767 for -32768
;; Also: NEGATEACC (UNKN)
FromAccumulator:
    tya                             ; A = 0
    sec
    sbc Accumulator
    jsr PushNoun
    tya
    sbc Accumulator+1
    bvc Add::StoreHigh

;; The >32767 error: a result that does not fit in 16 bits, or the negative of -32768.
;; Also: Err32767 (IBSM)
OverflowError:
    ldy #<ErrMsg00
    bpl PushNoun::ToReportError     ; always: the message's offset is 0
.endproc

;; Subtraction (token $13): negates the top number, then adds (falls into <Operators::Add>).
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the difference, Y = 0
;; Errors: >32767 if the difference does not fit, or the top number is -32768
;; Uses: A, Accumulator, Auxiliary
;; Also: SUBTRACT (IBSM)
.proc Subtract
    jsr Negate
    ; Falls into Add.
.endproc

;; Addition (token $12): replaces two numbers with their sum.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the sum, Y = 0
;; Errors: >32767 if the sum overflows
;; Uses: A, Accumulator, Auxiliary
;; Entry:
;;   AddAuxiliary = adds <Auxiliary> to <Accumulator> and pushes the sum
;;   StoreHigh = stores A as the high byte of the number just pushed
;; Also: PLUS (UNKN)
.proc Add
    jsr GetNumber
    lda Accumulator
    sta Auxiliary
    lda Accumulator+1
    sta Auxiliary+1
    jsr GetNumber

;; Adds <Auxiliary> to <Accumulator> and pushes the sum.
;; In: Accumulator, Auxiliary = the numbers, Y = 0, X = the noun stack
;; Out: X = the noun stack, one entry lower, its top entry the sum
;; Errors: >32767 if the sum overflows
;; Also: ADDAUX (UNKN)
AddAuxiliary:
    clc
    lda Accumulator
    adc Auxiliary
    jsr PushNoun
    lda Accumulator+1
    adc Auxiliary+1
    bvs Negate::OverflowError

;; Stores A as the high byte of the number just pushed: the end of addition and negation.
;; Also: SETNOUNHI (UNKN)
StoreHigh:
    sta NounStackNumberHigh,x
    ; Falls into Plus.
.endproc

;; Unary `+` (token $35): nothing to do.
;; Keeps: A, X, Y
;; Also: POSITIVE (IBSM)
.proc Plus
    rts
.endproc

.endscope

; Statements: TAB.
.scope Statements continued

;; `TAB` (token $50): moves the cursor to column n (1 is the first) of the window, wrapping past its width onto the
;; lines below.
;;
;; `TAB 0` is the RANGE error. It goes through <BcsRANGERR>, whose branch is always taken here: carry is still set
;; from the interpreter's priority comparison, and <GETBYTE> keeps it.
;; In: X = the noun stack, its top entry the column
;; Out: X = the noun stack, one entry higher
;; Errors: >255 for a column above 255, RANGE for 0
;; Uses: A, Y, Accumulator
;; See: <SETCURCOL>
;; Entry:
;;   ToSetColumn = sets the cursor's column to Y
;; Also: TAB (IBSM)
.proc Tab
    jsr GETBYTE
    tay
    bne CountFromZero
    jmp BcsRANGERR

    ; Counts the column from 0, then sets it.
CountFromZero:
    dey

;; Sets the cursor's column to Y, from 0 (<SETCURCOL>).
;; Also: TOCOLUMN (UNKN)
ToSetColumn:
    jmp SETCURCOL
.endproc

.endscope

;; Moves the cursor to the next tab stop, a multiple of 8 columns, for `PRINT`'s comma.
;;
;; <SETCURCOL> wraps the column onto the next line when it is past the window's width. A cursor column of $F8 or
;; more, which a window of 40 columns never gives, would loop here forever: the next stop wraps to 0, and the second
;; try reads the same column again.
;; Uses: A, Y
;; Keeps: X
;; Also: NEXTTAB (UNKN)
.proc NextTabStop

;; The columns between tab stops.
TAB_WIDTH = 8

    lda CursorColumn
    ora #TAB_WIDTH - 1
    tay
    iny
SetUnlessZero:
    bne Statements::Tab::ToSetColumn
    iny
    bne NextTabStop

;; Unused code, a branch back and a return; nothing in the ROM reaches it.
;; Also: UNUSED_BCSTAB (UNKN)
Unused:
    bcs SetUnlessZero
    rts
    .byte $00, $00                  ; unused bytes
.endproc
