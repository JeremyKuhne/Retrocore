; retrocore: style=strict
;; Integer BASIC: strings, multiplication and SCRN(
;;
;; The routines for string tokens: substrings, DIM of a string, string INPUT, string assignment and the string
;; comparisons; then multiplication and MOD, the line input INPUT uses for numbers, and SCRN(.
;;
;; On the noun stack a string takes two entries. The lower one is the string's address (the variable's first
;; character, or $0200 for a line just typed). The one above it is a range: the index of the first character in
;; <NounStackLow> and the index just past the last in <NounStackHigh>. Indexes count from 0, so A$(2,3) is the range 1
;; to 3. A string variable holds its characters and, after them, a byte with bit 7 clear; how many characters it can
;; hold is fixed by DIM and found from the address of the next variable.
;;
;; Part of IntegerBasic.asm.

;; The routines of the operator tokens: arithmetic, comparisons and `AND`, `OR` and `NOT`, for numbers and strings,
;; and the parentheses, which mark where a substring, an array element or a string being stored to starts.
;;
;; Each takes its operands off the noun stack and pushes its result. The scope is in pieces through the ROM, in
;; address order; this first piece is a substring's parenthesis and comma.
.scope Operators

;; The opening parenthesis of a substring in an expression (token $2A): A$(n) starts the string at character n.
;;
;; The range's end stays where it was, and the start must stay before it: A$(0), or a start past the end, is a STRING
;; error.
;; In: X = the noun stack: the position, above the string's range and address
;; Out: X = the noun stack, its top entry the string's range, VerbPriority = $FF
;; Errors: STRING, >255 for a position above 255
;; Entry:
;;   CheckRange = checks a range
;;   StringError = the STRING error
;;   ToReportError = reports the error whose message's offset is in Y
;; Also: PAREN_SUBSTR (IBSM)
.proc Substring
    jsr Strings::GetPosition
    sta NounStackLow,x
    cmp NounStackHigh,x

;; Checks a substring's range: carry clear passes, and ends the token as <Operators::SubstringComma> does; carry set
;; is the STRING error.
;; In: carry = clear if the range is good
;; Also: CHKSTRRNG (UNKN)
CheckRange:
    bcc SubstringComma::Finish

;; The STRING error.
;; Also: PrintErr05 (IBSM)
StringError:
    ldy #<Messages::String

;; Reports the error whose message's offset is in Y, for the branches nearby.
;; In: Y = the message's offset from <Messages::GreaterThan32767>
;; Also: STRERRMESS (UNKN)
ToReportError:
    jmp ReportError
.endproc

;; The comma of a substring (token $23): A$(m,n) ends the string after character n.
;;
;; n may not be less than m - 1, which leaves the string empty, nor past the string's present end.
;; In: X = the noun stack: the second position, above the string's range
;; Out: X = the noun stack, its top entry the string's range, VerbPriority = $FF
;; Errors: STRING, >255 for a position above 255
;; Entry:
;;   Finish = ends the token as a left parenthesis does
;; Also: COMMA_SUBSTR (IBSM)
.proc SubstringComma
    jsr GetByte
    cmp NounStackLow,x
    bcc Substring::StringError
    jsr CheckSubstringEnd
    sta NounStackHigh,x

;; Ends a substring token the way a left parenthesis ends, so the operators before it wait
;; (<Operators::LeftParenthesis>).
;; Also: SUBSTRDONE (UNKN)
Finish:
    jmp Operators::LeftParenthesis
.endproc

.endscope

;; The helpers of the string tokens.
.scope Strings

;; Takes a character position, counted from 1, off the noun stack and returns it counted from 0.
;; In: X = the noun stack, its top entry the position
;; Out: A = the position less 1, X = the noun stack, one entry higher, Accumulator = the position, Y = 0, carry = set
;; Errors: STRING for 0, >255 for a position above 255
;; Also: GETSTRNDX (UNKN)
.proc GetPosition
    jsr GetByte
    beq Operators::Substring::StringError
    sec
    sbc #1
    rts
.endproc

.endscope

; Operators: the position of a string being assigned to.
.scope Operators continued

;; The opening parenthesis of a string being assigned to (token $42): A$(n)="..." stores from character n on.
;;
;; The position can be anywhere in the string or just after its end, so the string cannot get a gap.
;; In: X = the noun stack: the position, above the variable's range and address
;; Out: X = the noun stack, its top entry the variable's range, VerbPriority = $FF
;; Errors: STRING, >255 for a position above 255
;; See: <Statements::LetString>
;; Also: PAREN_STRDEST (UNKN)
.proc StringDestination
    jsr Strings::GetPosition
    sta NounStackLow,x
    clc
    sbc NounStackHigh,x             ; carry is clear: position - end - 1
    jmp Substring::CheckRange
.endproc

.endscope

; The string helpers, continued.
.scope Strings continued

;; Reports the MEM FULL error, for <SetVariableSize>.
;; Also: PrintErr03 (IBSM)
.proc MemoryFull
    ldy #<Messages::MemoryFull
    bne Operators::Substring::ToReportError ; always
.endproc

.endscope

; Statements: DIM of a string.
.scope Statements continued

;; DIM of a string (token $4E, and $43 after a comma): reserves room for a string of n characters.
;;
;; A new variable gets 2 bytes for its value (<Variables::CompareName>), so DIM can only size the variable created last,
;; the one whose next-variable address is still <VariablesEnd>; DIM of any other is a DIM error. It moves
;; <VariablesEnd>, and that address, past n + 1 bytes: the characters and the byte that ends them.
;; In: X = the noun stack: the length, above the variable's range and address
;; Out: X = the noun stack, all three entries taken off
;; Errors: STRING for a length of 0, >255 for one above 255, MEM FULL, DIM
;; Also: DIMSTR (IBSM)
.proc DimString
    jsr Strings::GetPosition
    inx                             ; drop the range entry: the variable's address is on top; carry is set
    ; Falls into SetVariableSize.
.endproc

.endscope

;; Makes the newest variable's value Accumulator bytes long, plus 1 with carry set.
;;
;; The address after the value goes in both the variable's next-variable field, the two bytes before its value, and
;; <VariablesEnd>, if it stays below <ProgramStart>.
;; In: X = the noun stack, its top entry the variable's value's address, Accumulator = the size, carry = set to add a
;;   byte
;; Out: X = the noun stack, one entry higher, VariablesEnd = the end of the value, Auxiliary = the variable's
;;   next-variable field, Y = $FF
;; Errors: MEM FULL, DIM for a variable that is not the newest
;; Entry:
;;   DimError = the DIM error
;;   ToReportError = reports the error whose message's offset is in Y
;; Also: SETVARSIZE (UNKN)
.proc SetVariableSize
    lda NounStackLow,x
    sta Auxiliary
    adc Accumulator
    pha
    tay
    lda NounStackHigh,x
    sta Auxiliary+1
    adc Accumulator+1
    pha
    cpy ProgramStart
    sbc ProgramStart+1              ; the new end must stay below the program
    bcs Strings::MemoryFull

    ; Auxiliary = the value's address less 2: the next-variable field. Carry is clear.
    lda Auxiliary
    adc #<-2
    sta Auxiliary
    lda #$FF
    tay
    adc Auxiliary+1
    sta Auxiliary+1

    ; The field must hold VariablesEnd, both bytes.
CompareEnd:
    iny
    lda (Auxiliary),y
    cmp VariablesEnd,y
    bne DimError
    tya
    beq CompareEnd                  ; Y = 0: compare the high byte too

    ; Store the new end in both, high byte first.
StoreEnd:
    pla
    sta (Auxiliary),y
    sta VariablesEnd,y
    dey
    bpl StoreEnd
    inx
    rts

    ; An unused byte (a NOP).
    .byte $EA

;; The DIM error.
;; Also: DimErr (IBSM)
DimError:
    ldy #<Messages::Dim

;; Reports the error whose message's offset is in Y, for the branches nearby.
ToReportError:
    bne Operators::Substring::ToReportError ; always
.endproc

; The string helpers, continued: INPUT of a string.
.scope Strings continued

;; Reads a line with the ? prompt, then assigns it to the string variable as <Statements::LetString> does.
;;
;; It pushes the typed line as a string: address $0200 (<InputBuffer>) and the range 0 to the line's length. A
;; Control-C in the line goes to the warm start (<ReadInputLine>).
;; In: X = the noun stack: the variable's range and address
;; Out: X = the noun stack, the variable's two entries taken off
;; Errors: `STR OVFL`
;; Also: INPUTSTR (IBSM)
.proc ReadLineInto
    ; The line's address: $0200.
    lda #0
    jsr PushNoun::LowOnly
    ldy #>InputBuffer
    sty NounStackHigh,x

    ; The range, from 0; its end comes from the line.
    jsr PushNoun::LowOnly
    stx SavedX
    tax                             ; the line starts at index 0
    inc PromptCharacter             ; > becomes ?
    jsr ReadInputLine
    dec PromptCharacter
    txa
    ldx SavedX
    sta NounStackHigh,x
    ; Falls into Statements::LetString.
.endproc

.endscope

; Statements: string assignment.
.scope Statements continued

;; String assignment (token $70): copies the source string's range into the variable, from the variable's start
;; position, and ends it there.
;;
;; A character past the room DIM gave is a `STR OVFL` error.
;; In: X = the noun stack: the source's range and address above the variable's range and address
;; Out: X = the noun stack, all four entries taken off
;; Errors: `STR OVFL`
;; See: <Strings::FindRoom>, <Operators::StringDestination>
;; Also: LET_STR (UNKN)
.proc LetString
    lda NounStackLow+1,x
    sta Accumulator
    lda NounStackHigh+1,x
    sta Accumulator+1
    inx                             ; pop the source; Accumulator = its address
    inx
    jsr Strings::FindRoom

;; The copy loop, until the source's range is empty.
CopyCharacter:
    lda NounStackLow-2,x
    cmp NounStackHigh-2,x
    bcs EndString
    inc NounStackLow-2,x
    tay
    lda (Accumulator),y
    ldy NounStackLow,x
    cpy Pointer2                    ; past the room the variable has?
    bcc StoreCharacter
    ldy #<Messages::StringOverflow
    bne SetVariableSize::ToReportError ; always

StoreCharacter:
    sta (Auxiliary),y
    inc NounStackLow,x
    bcc CopyCharacter               ; always: the CPY above cleared carry

;; Ends the string with X, which is below $80, then pops the variable and shows it if DSP is on
;; (<Display::FinishStringAssignment>).
EndString:
    ldy NounStackLow,x
    txa
    sta (Auxiliary),y
    jmp Display::FinishStringAssignment
.endproc

.endscope

; The string helpers, continued: the room a string variable has.
.scope Strings continued

;; Points <Auxiliary> at the destination string and works out how many characters it can hold.
;;
;; The two bytes before a value are the next variable's address, so the low byte of that address, less the value's
;; address, less 1 for the ending byte, is the room DIM gave.
;; In: X = the noun stack, with the variable's address at X+1
;; Out: Auxiliary = the variable's address, Pointer2 = the number of characters it can hold, Y = 0
;; Keeps: X
;; Also: GETSTRROOM (UNKN)
.proc FindRoom
    lda NounStackLow+1,x
    sta Auxiliary
    sec
    sbc #2
    sta Pointer2
    lda NounStackHigh+1,x
    sta Auxiliary+1
    sbc #0
    sta Pointer2+1
    ldy #0
    lda (Pointer2),y
    clc
    sbc Auxiliary
    sta Pointer2
    rts
.endproc

.endscope

; Operators: the string comparisons, multiplication and MOD.
.scope Operators continued

;; String comparison with = (token $39): replaces two strings with 1 if they are the same, 0 if not.
;;
;; The strings are compared a character at a time over their ranges; they are equal only if both ranges run out
;; together.
;; In: X = the noun stack: two strings, each a range above an address
;; Out: X = the noun stack, three entries higher, its top entry the result
;; Uses: A, Y, Accumulator, Auxiliary, Pointer2
;; See: <Operators::StringNotEqual>
;; Also: EQ_STR (UNKN)
.proc StringEqual
    lda NounStackLow+3,x
    sta Accumulator
    lda NounStackHigh+3,x
    sta Accumulator+1               ; the left string's address
    lda NounStackLow+1,x
    sta Auxiliary
    lda NounStackHigh+1,x
    sta Auxiliary+1                 ; the right string's address
    inx
    inx
    inx                             ; pop to the result's entry, the left string's address
    ldy #0
    sty NounStackHigh,x
    sty NounStackNumberHigh,x       ; the result is a number
    iny
    sty NounStackLow,x              ; 1: equal so far

;; Compares the next pair of characters.
Compare:
    lda NounStackLow-3,x
    cmp NounStackHigh-3,x           ; the right string's range
    php
    pha
    lda NounStackLow-1,x
    cmp NounStackHigh-1,x           ; the left string's range
    bcc CompareCharacters           ; the left one has a character left
    pla
    plp
    bcs Done                        ; both ran out together: equal

;; The strings differ: the result becomes 0.
Differ:
    lsr NounStackLow,x
Done:
    rts

CompareCharacters:
    tay
    lda (Accumulator),y
    sta Pointer2
    pla
    tay
    plp
    bcs Differ                      ; the right one ran out first
    lda (Auxiliary),y
    cmp Pointer2
    bne Differ
    inc NounStackLow-1,x
    inc NounStackLow-3,x
    bcs Compare                     ; always: the CMP found them equal
.endproc

;; String comparison with # (token $3A, not equal): the opposite of <Operators::StringEqual>.
;; In: X = the noun stack: two strings, each a range above an address
;; Out: X = the noun stack, three entries higher, its top entry the result
;; Also: NE_STR (UNKN)
.proc StringNotEqual
    jsr StringEqual
    jmp Operators::Not
.endproc

;; Multiplication (token $14): replaces the top two numbers with their product.
;;
;; <Operators::TakeMagnitudes> makes both numbers positive and keeps the product's sign. The product is built a bit of
;; the multiplier at a time, from the top: the partial product doubles each step and gains the multiplicand when the
;; bit is 1. A bug: only the doublings are checked, each for a partial product that has reached $4000, so an addition
;; that carries into bit 15 goes through whenever the next doubling does not see bit 14 set, and the last addition
;; is never checked: 3 * 16000 gives -17536 and 6 * 12288 gives 8192 instead of the >32767 error.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the product
;; Errors: >32767 when a doubling would pass $7FFF (not every product that does not fit: above), or for an operand of
;;   -32768
;; Uses: A, Y, Accumulator, Auxiliary, Pointer2, Pointer3
;; Entry:
;;   PushResult = pushes the result in <Pointer3>
;; Also: MULT (IBSM)
.proc Multiply
    jsr TakeMagnitudes

    ; The multiplier's next bit, from the top.
NextBit:
    asl Accumulator
    rol Accumulator+1
    bcc NextStep
    clc                             ; a 1: add the multiplicand
    lda Pointer3
    adc Auxiliary
    sta Pointer3
    lda Pointer3+1
    adc Auxiliary+1
    sta Pointer3+1

NextStep:
    dey
    beq PushResult
    asl Pointer3
    rol Pointer3+1
    bpl NextBit                     ; the product must stay below $8000
    jmp Operators::Negate::OverflowError

;; Pushes <Pointer3> as the result, negated when the sign kept in the high byte of <Pointer2> says so.
;;
;; MOD and division end here too.
;; In: Pointer3 = the magnitude, Pointer2+1 = bit 7 set for a negative result, Y = 0, X = the noun stack
;; Out: X = the noun stack, its top entry the result
;; Errors: >32767 for a negative result whose magnitude is $8000
;; Also: MultEnd (IBSM)
PushResult:
    lda Pointer3
    jsr PushNoun
    lda Pointer3+1                  ; Y = 0: a number
    sta NounStackNumberHigh,x
    asl Pointer2+1
    bcc TakeMagnitudes::Done
    jmp Operators::Negate
.endproc

;; Takes two numbers off the noun stack as positive values for multiplication or division.
;;
;; The high byte of <Pointer2> starts as $55 (%01010101) and is shifted left for each negative operand, so its top
;; bit, set after one shift and clear after none or two, ends up as the sign of the result.
;; In: X = the noun stack: two numbers
;; Out: Auxiliary = the top number's magnitude, Accumulator = the one below's magnitude, Pointer3 = 0, Y = 16 (the bits
;;   to work), Pointer2+1 = bit 7 set for a negative result, X = the noun stack, two entries higher
;; Errors: >32767 for an operand of -32768
;; Entry:
;;   Done = returns; <Operators::Multiply::PushResult> branches here
;; Also: MDARGS (UNKN)
.proc TakeMagnitudes
;; The sign's seed: alternate bits, so each shift left flips bit 7.
SIGN_SEED = %01010101

;; The bits a multiplication or division works.
BITS = 16

    lda #SIGN_SEED
    sta Pointer2+1
    jsr TakeOne

;; Moves <Accumulator> to <Auxiliary> and takes the next number off the noun stack into <Accumulator>, made positive.
;; Also: POPABS (UNKN)
TakeOne:
    lda Accumulator
    sta Auxiliary
    lda Accumulator+1
    sta Auxiliary+1
    jsr GetNumber
    sty Pointer3
    sty Pointer3+1
    lda Accumulator+1
    bpl Positive

    ; Negative: push it back, negate it on the stack and take it again.
    dex
    asl Pointer2+1                  ; one more negative operand
    jsr Operators::Negate
    jsr GetNumber

Positive:
    ldy #BITS
Done:
    rts
.endproc

;; MOD (token $1F): replaces two numbers with the remainder of dividing the lower by the top.
;;
;; <DivideWithRemainder> divides, leaving the remainder in <Pointer3> and Y = 0, so the branch always goes to
;; <Operators::Multiply::PushResult>. The remainder takes the sign a quotient would have: 7 MOD -2 is -1.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, one entry higher, its top entry the remainder
;; Errors: >32767 for a division by 0, or for an operand of -32768
;; See: <DivideWithRemainder>, <Operators::Divide>
;; Also: MOD (IBSM)
.proc Mod
    jsr DivideWithRemainder
    beq Multiply::PushResult        ; always

    ; An unused byte.
    .byte $FF
.endproc

.endscope

;; The line input of the command loop and of INPUT, and the routines that store and delete program lines.
.scope Editor

;; Reads a line for INPUT of numbers into <InputBuffer>, with the ? prompt.
;;
;; INPUT has printed the ? already; the prompt character becomes ? so a line cancelled with Control-X is prompted
;; again with it.
;; Out: Y = the index of the underline that ends the line, X = $FF
;; See: <ReadNumberLine>
;; Also: GETQLINE (UNKN)
.proc ReadInputLine
    inc PromptCharacter             ; > becomes ?
    ldy #0
    jsr Editor::ReadLine
    dec PromptCharacter
    rts
.endproc

.endscope

;; The routines of the function tokens: `ABS`, `SGN`, `PEEK`, `RND`, `PDL`, `LEN(`, `ASC(` and `SCRN(`.
;;
;; Each takes its argument off the noun stack and pushes its value. The scope is in pieces through the ROM, in
;; address order.
.scope Functions

;; SCRN( (token $3D): replaces a column and a row with the color of that lo-res block, 0 to 15.
;;
;; A text byte holds two lo-res blocks: the even row in the low nibble, the odd row in the high nibble. The row is not
;; checked against the screen.
;; In: X = the noun stack: the column, then the row on top
;; Out: X = the noun stack, one entry higher, its top entry the color, VerbPriority = $FF
;; Errors: >255 for a column or row above 255
;; Also: SCRN (IBSM)
.proc Scrn
;; The low nibble of a screen byte: one block's color.
COLOR_BITS = $0F

    jsr GetByte
    lsr a
    php                             ; carry = the row's lowest bit
    jsr LowRes::RowAddress
    jsr GetByte
    tay
    lda (LowResBase),y
    plp
    bcc EvenRow

    ; An odd row: the upper nibble.
    lsr a
    lsr a
    lsr a
    lsr a

EvenRow:
    and #COLOR_BITS
    ldy #0
    jsr PushNoun
    sty NounStackNumberHigh,x
    dey                             ; VerbPriority = $FF, as a left parenthesis sets it
    sty VerbPriority
    ; Falls into ScrnComma.
.endproc

;; The comma of SCRN( (token $3E): nothing to do, as <Functions::Scrn> takes both numbers.
;; Also: COMMA_SCRN (IBSM)
.proc ScrnComma
    rts

    ; Unused bytes.
    .byte $FF, $FF, $FF, $FF
.endproc

.endscope
