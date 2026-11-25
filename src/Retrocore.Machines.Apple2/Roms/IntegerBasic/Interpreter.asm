; retrocore: style=strict ignore=unlinked-name:BASIC -- the language's name in prose
;; Integer BASIC: variables and the statement interpreter ($E5CC-$E6FE)
;;
;; The interpreter that runs a line's tokens (<Interpreter::RunLine>), and the variable lookup it calls for each name
;; (<Variables::Find>).
;;
;; The interpreter evaluates by operator priority. Operands are pushed on the noun stack as they come: a constant's
;; value, a variable's address, a string's address and range. Every token is an operator, a statement keyword as
;; much as a plus sign, with two priorities in <TABLE1> (VerbTables.asm): one for when it arrives, one for while it
;; waits. Tokens wait on the 6502's stack. When a token arrives, each waiting token whose waiting priority is at
;; least the new one's arriving priority runs first, taking its operands off the noun stack and pushing its result;
;; then the new token waits in turn. So in `A=2+3*4` the `*` runs before the `+`, and the `=` (an assignment) runs
;; last. The stack starts with token 0, whose routine (<Statements::BeginLine>) ends the line, so
;; <TOKEN_END_OF_LINE> at the end of the line, which every waiting token yields to, finishes the line.
;;
;; A variable's name is looked up each time it is met, from <LowMemory> up; one that is not found is created at the
;; end of the variables, with a value of 0. Its address goes on the noun stack, and the statement routines read or
;; store through it, so the same push serves both `A=1` and `PRINT A`.
;;
;; Part of IntegerBasic.asm; it follows Program.asm, at $E5CC.

;; Finding a variable by its name, and creating it when it is new.
;;
;; The variables lie from <LowMemory> to <VariablesEnd>, each its name, then its <VariableFields>: a display flag,
;; the address of the next variable and the value. The lookup walks them through <SearchPointer>, comparing each
;; name with the one at <TokenPointer>. It is part of the interpreter's loop: <Interpreter::RunLine> branches to
;; <Variables::Find> for a name, and the lookup branches back.
.scope Variables

;; An unused instruction that falls into <Variables::ToMemoryFull>; nothing in the ROM reaches it.
;; Also: UNUSED_MEMFULL (UNKN)
.proc UnusedLoad
    lda SearchPointer
    ; Falls into ToMemoryFull.
.endproc

;; The MEM FULL error, for a new variable that would reach the program.
;; Also: ErrMemFull (IBSM)
.proc ToMemoryFull
    jmp MEMFULL
.endproc

;; Compares the name at <TokenPointer> with the variable at <SearchPointer>, and goes on to the next variable if it
;; differs (falls into <Variables::Next>).
;;
;; A name in the program is its characters, then <TOKEN_DOLLAR> for a string, then a token. Bit 7 of <SavedX> stays
;; set for a numeric name; <TOKEN_DOLLAR> clears it, for <Variables::Find>.
;; In: SearchPointer = the variable to compare, TokenPointer = the name
;; Entry:
;;   Begin = with Y already $FF
;;   SkipNameByte = skips the variable's name from the byte in A, at Y - 1
;; Also: CMPVARNAME (UNKN)
.proc CompareName
    ldy #$FF

;; Compares, with Y already $FF.
;; Also: CMPVARNAMEY (UNKN)
Begin:
    sty SavedX
NextNameCharacter:
    iny
    lda (TokenPointer),y
    bmi CompareCharacter

    ; A token: the name ends here. The $ of a string name goes on to be compared.
    cmp #TOKEN_DOLLAR
    bne Find::NameEnded
    sta SavedX
CompareCharacter:
    cmp (SearchPointer),y
    beq NextNameCharacter

    ; The names differ: skips the rest of the variable's name, up to its display flag (0 or 1), and moves to the
    ; next variable through the address after the flag.
SkipName:
    lda (SearchPointer),y

;; Skips the variable's name from the byte in A, which is at Y - 1 once Y is stepped.
SkipNameByte:
    iny
    lsr a
    bne SkipName
    lda (SearchPointer),y
    pha
    iny
    lda (SearchPointer),y
    tay
    pla
    ; Falls into Next.
.endproc

;; Goes on with the variable at A (low) and Y (high), unless that is the end of the variables, <VariablesEnd>.
;;
;; At the end the name is new: it is added at <VariablesEnd>, with a display flag of 0 and a value of 0, and the
;; search goes on from it, which finds it.
;; In: A/Y = the variable, TokenPointer = the name
;; Errors: MEM FULL if the new variable would reach <ProgramStart>
;; Also: TRYVAR (UNKN)
.proc Next
    sta SearchPointer
    sty SearchPointer+1
    cmp VariablesEnd
    bne CompareName
    cpy VariablesEnd+1
    bne CompareName

    ; Counts the new name's characters, its $ included.
    ldy #0
CountName:
    iny
    lda (TokenPointer),y
    bmi CountName
    eor #TOKEN_DOLLAR
    beq CountName

    ; The new end of the variables: carry is set from the compare, so this adds the fields' size.
    tya
    adc #.sizeof(VariableFields) - 1
    pha
    adc SearchPointer
    tay
    lda SearchPointer+1
    adc #0
    pha

    ; It must stay below the program.
    cpy ProgramStart
    sbc ProgramStart+1
    bcs ToMemoryFull
    sty VariablesEnd
    pla
    sta VariablesEnd+1

    ; The fields, from the end: the value 0, the next variable's address (the new end) and the display flag 0.
    pla
    tay
    lda #0
    dey
    sta (SearchPointer),y
    dey
    sta (SearchPointer),y
    dey
    lda VariablesEnd+1
    sta (SearchPointer),y
    dey
    lda VariablesEnd
    sta (SearchPointer),y
    dey
    lda #0

    ; Copies the name in from the program, from its end (a name's characters are never 0), then compares again,
    ; from this variable.
CopyName:
    sta (SearchPointer),y
    dey
    bmi CompareName::Begin
    lda (TokenPointer),y
    bne CopyName
.endproc

;; Looks up the variable whose name starts at <TokenPointer>, from <LowMemory>, pushes its address and goes on with
;; the line.
;;
;; A numeric variable pushes the address of its 2-byte value. A string pushes its address and above it a range from
;; 0 to its length, found by counting the characters before the byte that ends it. The display flag goes in the
;; <NounStackNumberHigh> byte of the address entry, where the assignment routines look for it. TokenPointer ends on
;; the token after the name. The interpreter branches here, and this branches back into <Interpreter::RunLine>.
;; In: TokenPointer = the name's first character, X = the noun stack
;; Out: X = the noun stack with the variable pushed, Y = 0, then the interpreter goes on at the token after the name
;; Errors: MEM FULL if a new variable would reach the program
;; Entry:
;;   NameEnded = the name at <TokenPointer> has ended at Y: the variable at <SearchPointer> matches if its name
;;     ends too
;; Also: LOOKUPVAR (UNKN)
.proc Find
    lda LowMemory
    ldy LowMemory+1
    bne Next                        ; always: LowMemory is above page 0

;; The name at <TokenPointer> has ended at Y: the variable at <SearchPointer> matches if its name ends here too.
NameEnded:
    lda (SearchPointer),y
    cmp #TOKEN_DOLLAR
    bcs CompareName::SkipNameByte   ; the variable's name goes on: not this one

    ; The display flag goes in the entry about to be pushed.
    sta NounStackNumberHigh-1,x

    ; Pushes the value's address, low byte, past the flag and the next address (carry is clear).
    tya
    adc #VariableFields::VALUE
    pha
    adc SearchPointer
    jsr PushNoun::LowOnly

    ; Steps TokenPointer over the name, then adds the carry kept from the low byte to the high byte.
StepOverName:
    jsr Interpreter::ReadNextByte
    dey
    bne StepOverName
    tya
    adc SearchPointer+1
    sta NounStackHigh,x

    ; A numeric variable is done.
    pla
    bit SavedX
    bmi Interpreter::RunLine::ReadItem

    ; A string: a range from 0, whose end counts the characters up to the byte with bit 7 clear that ends them.
    tay
    lda #0
    jsr PushNoun::LowOnly
    sta NounStackHigh,x
CountString:
    lda (SearchPointer),y
    bpl Interpreter::RunLine::NextItem
    inc NounStackHigh,x
    iny
    bne CountString
    .byte $09                       ; an unused byte
.endproc

.endscope

;; Running a line's tokens: the interpreter's loop and the routines that step through a line.
.scope Interpreter

;; The bits of a <TABLE1> byte that hold a token's priority when it arrives.
ARRIVING_PRIORITY = %01010101

;; The bits of a <TABLE1> byte that hold a token's priority while it waits.
WAITING_PRIORITY = %10101010

;; An arriving priority above every waiting one's, which a left parenthesis sets so nothing waiting before it runs.
HOLD_PRIORITY = $FF

;; Runs the tokens of a line, starting at <TokenPointer>, by operator priority, until the end-of-line token finishes
;; it.
;;
;; The 6502's stack holds the tokens waiting to run, starting with token 0, and X the noun stack. When the line's
;; end arrives, every waiting token runs, and token 0's routine, <Statements::BeginLine>, returns from here.
;;
;; While a false `IF`'s statement is skipped (<SkippingStatement>), each constant or string steps X down a second
;; time, so it takes two entries, and nothing takes entries off until the next line starts again with an empty
;; stack. By the code, a skipped statement whose operands fill more than the stack's 32 entries stops with the noun
;; stack's error (<PushNoun>), where running it would not.
;; In: TokenPointer = the first token
;; Uses: all
;; See: <TABLE1>, <VERBADRL>
;; Entry:
;;   NextItem = after an operand, with Y not 0
;;   ReadItem = after an operand, with Y = 0
;;   Arrive = runs the token in A, as it arrives
;;   Wait = steps past the arriving token and makes it wait
;; Also: EXECLINE (UNKN)
.proc RunLine
    ; No IF skipping and no return owed. A = 0 also starts the waiting tokens with token 0.
    lda #0
    sta SkippingStatement
    sta ReturnPending
    ldx #NOUN_STACK_EMPTY

    ; The token in A waits.
PushToken:
    pha

;; Takes the next item at <TokenPointer>: a constant, a name or a token.
NextItem:
    ldy #0

;; Takes the next item, with Y already 0.
ReadItem:
    lda (TokenPointer),y
TakeItem:
    bpl Token

    ; Bits 7 and 6 set: a name.
    asl a
    bmi Variables::Find

    ; A constant: its value follows its first digit. Pushes the low byte, as a number (Y = 0), then the high one.
    jsr ReadNextByte
    jsr PushNoun
    jsr ReadNextByte
    sta NounStackNumberHigh,x

    ; After a constant or a string: while a statement is skipped, X steps down a second time.
AfterOperand:
    bit SkippingStatement
    bpl StepItem
    dex

    ; Steps to the next item; the branch is always taken, as carry is set.
StepItem:
    jsr ReadNextByte
    bcs TakeItem

    ; A token: a string constant is pushed. Its address is TokenPointer, the quote itself, and its range runs from
    ; 1 to the index of the closing quote; while a statement is skipped, it gets no range.
Token:
    cmp #TOKEN_OPEN_QUOTE
    bne CheckSkipping
    lda TokenPointer
    jsr PushNoun::LowOnly
    lda TokenPointer+1
    sta NounStackHigh,x
    bit SkippingStatement
    bmi NextStringByte
    lda #1
    jsr PushNoun::LowOnly
    lda #0
    sta NounStackHigh,x
CountCharacter:
    inc NounStackHigh,x
NextStringByte:
    jsr ReadNextByte
    bmi CountCharacter
    bcs AfterOperand                ; always: the compare with the quote set carry

    ; While a false IF's statement is skipped, passes over every token but the end of the line and a colon, which
    ; end the skipping.
CheckSkipping:
    bit SkippingStatement
    bpl Arrive
    cmp #TOKEN_COLON + 1
    bcs StepItem
    lsr SkippingStatement

;; A token arrives: lets the waiting tokens that come first run, then makes it wait.
;;
;; Each <TABLE1> byte holds two priorities with their bits interleaved: the even bits (<ARRIVING_PRIORITY>) are the
;; priority on arrival, the odd bits (<WAITING_PRIORITY>) the priority while waiting. Shifting the arriving
;; priority left puts it in the odd bits, so the two compare as plain bytes.
;; In: A = the token
;; Also: DOTOKEN (UNKN)
Arrive:
    tay
    sta CurrentVerb
    lda TABLE1,y
    and #ARRIVING_PRIORITY
    asl a
    sta VerbPriority

    ; Takes the next waiting token and runs it if its waiting priority is at least the arriving one; otherwise puts
    ; it back.
NextWaiting:
    pla
    tay
    lda TABLE1,y
    and #WAITING_PRIORITY
    cmp VerbPriority
    bcs RunWaiting
    tya
    pha

;; The arriving token is to wait: steps <TokenPointer> past it to the next item, then makes it wait.
;;
;; When the token is a colon, every token of the statement before it has run, so the next statement starts at the
;; item after it; the debugger's BASIC thread takes each statement after the first in a line from here.
;; See: <Lines::RunLoop>, <Statements::Colon>
;; Also: WAITTOKEN (UNKN)
Wait:
    jsr GETVERB0
    lda CurrentVerb
    bcc PushToken                   ; always: the compare cleared carry

    ; Runs a waiting token through the verb tables, then looks at the next one.
RunWaiting:
    lda VERBADRL,y
    sta Accumulator
    lda VERBADRH,y
    sta Accumulator+1
    jsr CallVerb
    jmp NextWaiting
.endproc

;; Jumps to the address in <Accumulator>: a JSR here calls the token's routine.
;; Also: JMPVERB (UNKN)
.proc CallVerb
    jmp (Accumulator)
.endproc

.endscope
