; retrocore: style=strict
;; Integer BASIC: printing strings, graphics, memory and more statements
;;
;; The routines of many tokens: PRINT of a string, LEN(, COLOR=, PLOT, HLIN, VLIN, VTAB, MAN, CALL, PEEK, POKE,
;; division, DIM of numeric arrays and array elements, RND, INPUT of strings and the start of INPUT with a prompt,
;; and RUN; with <GetByte>, which most of them use, the >255 and RANGE errors, the error messages' printer, the
;; division loop, and the helpers of AND, OR, substrings and the lister. It follows SyntaxTable.asm, at $EE00.
;;
;; A statement with two values, such as PLOT or POKE, has two routines: one for its keyword and one for its comma.
;; Whichever runs first (their priorities decide, VerbTables.asm) takes one value off the noun stack and keeps it in
;; <Statements::FirstValueByte>, the tokenizer's <TextIndex>, which it no longer needs (<Statements::FirstValue>); the
;; other takes the second value and does the work.
;;
;; Part of IntegerBasic.asm.

; This file's constants.

;; The first page of the variables after a cold start, which <Memory::SetFor4K> also uses: $0800, the first page above
;; the text screen.
VARIABLES_PAGE = $08

;; The page just above the first 4K of RAM, where <Memory::SetFor4K> puts HIMEM.
END_OF_4K_PAGE = $10

;; A blank as the syntax table stores a keyword's character: its code less $A0, with bit 7 set.
KEYWORD_BLANK = (' ' - $A0) | $80

;; How many times <Functions::Rnd> shifts the random state for each number.
RANDOM_SHIFTS = 17

;; The low bits of <RandomSeedHigh> that the random state keeps: bit 15 is cleared, so the state is positive.
RANDOM_HIGH_MASK = $7F

;; Added to the shifted high byte in <Functions::Rnd>, so that bit 7 becomes bits 14 and 13 exclusive-ORed.
RANDOM_TAP = $40

; PRINT of a string.
.scope Statements continued

;; PRINT's comma before a string (token $48): moves to the next tab stop, then prints the string.
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, both popped, ReturnPending = $FF
;; See: <NextTabStop>
;; Also: COMMA_PRSTR (UNKN)
.proc PrintStringComma
    jsr NextTabStop
    ; Falls into PrintString.
.endproc

;; PRINT of a string (token $61), and the semicolon before one (token $45): prints the characters of the string's
;; range.
;;
;; The line then owes a return (<ReturnPending>), which the end of the statement prints unless a semicolon or comma
;; ends it.
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, both popped, ReturnPending = $FF
;; Uses: A, Y, Auxiliary
;; Also: PRINTSTR (IBSM)
.proc PrintString
    ; Pop both entries: Auxiliary = the address, Y = the first index.
    inx
    inx
    lda NounStackLow-1,x
    sta Auxiliary
    lda NounStackHigh-1,x
    sta Auxiliary+1
    ldy NounStackLow-2,x

    ; Print up to the end index.
NextCharacter:
    tya
    cmp NounStackHigh-2,x
    bcs SetReturnPending
    lda (Auxiliary),y
    jsr CharacterOut
    iny
    jmp NextCharacter

;; Sets <ReturnPending>: the line owes a return.
;; Also: SETCRFLAG (UNKN)
SetReturnPending:
    lda #$FF
    sta ReturnPending
    rts
.endproc

.endscope

; LEN(.
.scope Functions continued

;; LEN( (token $3B): replaces a string with its length, the size of its range.
;;
;; The length replaces the address entry, and the routine then ends as a left parenthesis does
;; (<Operators::LeftParenthesis>), as the token opens LEN's parenthesis.
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, its top entry the length
;; Also: LEN (IBSM)
.proc Len
    inx
    lda #0
    sta NounStackHigh,x
    sta NounStackNumberHigh,x
    lda NounStackHigh-1,x
    sec
    sbc NounStackLow-1,x
    sta NounStackLow,x
    jmp Operators::LeftParenthesis
.endproc

.endscope

    ; An unused byte.
    .res 1, $FF

;; Takes a number from the noun stack that must fit in a byte.
;; In: X = the noun stack
;; Out: A = the number, Accumulator = the number, X = the noun stack, one entry higher, Y = 0, zero = set for 0
;; Errors: >255 if the number is above 255 or negative
;; Keeps: carry
;; See: <GetNumber>
;; Also: GETBYTE (IBSM)
.proc GetByte
    jsr GetNumber
    lda Accumulator+1
    bne ValueOver255Error
    lda Accumulator
    rts
.endproc

; PLOT's comma, COLOR=, MAN and VTAB.
.scope Statements continued

;; The first of a statement's two values, which <FirstValue> keeps in <TextIndex> for the routine that runs next: the
;; value POKE stores, PLOT's column, HLIN's left end or VLIN's top row.
FirstValueByte = TextIndex

;; PLOT's comma (token $68): plots the lo-res block at the column <FirstValue> kept and the row on the noun stack.
;; In: X = the noun stack, its top entry the row, FirstValueByte = the column
;; Errors: RANGE if the row is 48 or more, or the column 40 or more
;; See: <LowRes::Plot>
;; Also: COMMA_PLOT (IBSM)
.proc PlotComma
    jsr GetByte
    ldy FirstValueByte
    cmp #LOW_RES_ROWS
    bcs RangeError
    cpy #LOW_RES_COLUMNS
    bcs RangeError
    jmp LowRes::Plot
.endproc

;; COLOR= (token $66): sets the lo-res color, 0 to 15 (<LowRes::SetColor> uses the low four bits).
;; In: X = the noun stack, its top entry the color
;; Errors: >255
;; Also: COLOR_EQ (UNKN)
.proc Color
    jsr GetByte
    jmp LowRes::SetColor
.endproc

;; MAN (token $0F): leaves AUTO mode.
;; Out: AutoNumbering = bit 7 clear
;; See: <Statements::Auto>
;; Also: MAN (UNKN)
.proc Man
    lsr AutoNumbering
    rts
.endproc

;; VTAB (token $6F): moves the cursor to line n of the screen, 1 to 24.
;; In: X = the noun stack, its top entry the line
;; Errors: RANGE outside 1 to 24, >255
;; See: <VerticalTab>, <CV>
;; Also: IVTAB (IBSM)
.proc VTab
    jsr GetByteMinusOne
    cmp #TEXT_ROWS
    bcs RangeError
    sta CV
    jmp VerticalTab
.endproc

.endscope

;; Reports the >255 error: a value that must fit in a byte does not.
;; Entry:
;;   ToReportError = reports the error whose message offset is in Y (<ReportError>); <RangeError> branches here
;; Also: HI255ERR (IBSM)
.proc ValueOver255Error
    ldy #<Messages::GreaterThan255

;; Reports the error whose message offset is in Y (<ReportError>); <RangeError> branches here.
;; Also: JmpERRMESS3 (IBSM)
ToReportError:
    jmp ReportError
.endproc

;; Reports the RANGE error: a value outside what a statement allows, such as a screen position.
;; Also: RANGERR (IBSM)
.proc RangeError
    ldy #<Messages::Range
    bne ValueOver255Error::ToReportError
.endproc

;; Divides two numbers from the noun stack, the lower by the top one, as magnitudes, keeping the quotient's sign.
;;
;; <Operators::TakeMagnitudes> takes both as positive values and keeps the sign. Each of the 16 steps shifts the next
;; bit of the dividend into the remainder and subtracts the divisor where it fits, setting the quotient's bit.
;; <Operators::Divide> and MOD (<Operators::Mod>) end with <Operators::Multiply::PushResult>, which applies the sign.
;; In: X = the noun stack: the dividend, then the divisor on top
;; Out: Accumulator = the quotient's magnitude, Pointer3 = the remainder's magnitude, Pointer2+1 = bit 7 set for a
;;   negative result, Auxiliary = the divisor's magnitude, X = both popped, Y = 0, zero = set
;; Errors: >32767 for a division by 0
;; Also: DIVMOD (UNKN)
.proc DivideWithRemainder
    jsr Operators::TakeMagnitudes
    lda Auxiliary
    bne NextBit
    lda Auxiliary+1
    bne NextBit
    jmp Operators::Negate::OverflowError

    ; One step: the dividend and the remainder shift left together.
NextBit:
    asl Accumulator
    rol Accumulator+1
    rol Pointer3
    rol Pointer3+1

    ; Does the divisor fit in the remainder? Then subtract it, and the quotient's bit is a 1.
    lda Pointer3
    cmp Auxiliary
    lda Pointer3+1
    sbc Auxiliary+1
    bcc CountBit
    sta Pointer3+1
    lda Pointer3
    sbc Auxiliary
    sta Pointer3
    inc Accumulator

CountBit:
    dey
    bne NextBit
    rts
.endproc

    ; Unused bytes.
    .res 6, $FF

; CALL, HLIN and VLIN.
.scope Statements continued

;; CALL (token $4D): calls the machine-language routine at the address.
;;
;; The routine starts with X = the noun stack and Y = 0, and returns to the interpreter with RTS. Negative numbers
;; reach the top half of memory: CALL -151 enters the Monitor at $FF69.
;; In: X = the noun stack, its top entry the address
;; Also: CALL (IBSM)
.proc Call
    jsr GetNumber
    jmp (Accumulator)
.endproc

;; HLIN's comma (token $6A): keeps the line's right end in <HorizontalLineEnd>; it must not be left of the left end.
;;
;; Neither end is checked against the screen's width, so a column of 40 or more draws past the end of the row.
;; In: X = the noun stack, its top entry the right end, FirstValueByte = the left end
;; Errors: RANGE if the right end is left of the left end, >255
;; Also: COMMA_HLIN (IBSM)
.proc HLinComma
    jsr GetByte
    cmp FirstValueByte
    bcc RangeError
    sta HorizontalLineEnd
    rts
.endproc

;; HLIN's AT (token $6B): draws the line across at the row given.
;; In: X = the noun stack, its top entry the row, FirstValueByte = the left end, HorizontalLineEnd = the right end
;; Errors: RANGE if the row is 48 or more, >255
;; See: <LowRes::HorizontalLine>
;; Also: AT_HLIN (IBSM)
.proc HLinAt
    jsr GetByte
    cmp #LOW_RES_ROWS
    bcs RangeError
    ldy FirstValueByte
    jmp LowRes::HorizontalLine
.endproc

;; VLIN's comma (token $6D): keeps the line's bottom row in <VerticalLineEnd>; it must not be above the top.
;;
;; Neither row is checked against the screen's height, so a row of 48 or more draws past the bottom of the screen.
;; In: X = the noun stack, its top entry the bottom row, FirstValueByte = the top row
;; Errors: RANGE if the bottom is above the top, >255
;; Also: COMMA_VLIN (IBSM)
.proc VLinComma
    jsr GetByte
    cmp FirstValueByte
    bcc RangeError
    sta VerticalLineEnd
    rts
.endproc

;; VLIN's AT (token $6E): draws the line down in the column given.
;;
;; TAB, the array routines and <Memory::SetLowMemory> enter at RangeErrorIfCarry with the carry set, for a RANGE error.
;; With the carry clear it goes on to draw a line, as the unused <Memory::SetHighMemory> would.
;; In: X = the noun stack, its top entry the column, FirstValueByte = the top row, VerticalLineEnd = the bottom row
;; Errors: RANGE if the column is 40 or more, >255
;; See: <LowRes::VerticalLine>
;; Entry:
;;   RangeErrorIfCarry = a RANGE error if the carry is set
;; Also: AT_VLIN (IBSM)
.proc VLinAt
    jsr GetByte
    cmp #LOW_RES_COLUMNS

;; A RANGE error if the carry is set.
;; Also: BcsRANGERR (IBSM)
RangeErrorIfCarry:
    bcs RangeError
    tay
    lda FirstValueByte
    jmp LowRes::VerticalLine
.endproc

.endscope

;; Prints an error: ***, the message at offset Y and ERR, then sounds the bell.
;; In: Y = the message's offset from <Messages::GreaterThan32767>
;; Uses: A, X, Y
;; See: <ReportError>
;; Also: PRINTERR (IBSM)
.proc PrintErrorMessage
    tya
    tax
    ldy #<Messages::ErrorStart
    jsr PrintMessage
    txa
    tay
    jsr PrintMessage
    ldy #<Messages::ErrorEnd
    jmp PrintMessageThenBeep
.endproc

;; Takes an array index from the noun stack and turns it into a size in bytes: (index + 1) x 2.
;;
;; The doubling runs again while bit 15 is set, so the carry catches a size of $8000 or more. A size of 0, from an
;; index of -1, is caught by comparing it with the A that <GetNumberPlusOne> leaves: 0 for a constant, or the index's
;; low byte for a variable, which is below the size's low byte whenever the size fits in a byte.
;; In: X = the noun stack, its top entry the index
;; Out: Accumulator = the size, X = the noun stack, one entry higher, Y = 0, carry = clear
;; Errors: RANGE for a size of $8000 or more, or of 0
;; Also: NDXSIZE (UNKN)
.proc ArraySize
    jsr GetNumberPlusOne

;; Doubles <Accumulator>, and again while bit 15 is set.
;; Also: DBLACC (UNKN)
Double:
    asl Accumulator
    rol Accumulator+1
    bmi Double
    bcs Statements::VLinAt::RangeErrorIfCarry
    bne Done
    cmp Accumulator
    bcs Statements::VLinAt::RangeErrorIfCarry

Done:
    rts
.endproc

; PEEK.
.scope Functions continued

;; PEEK (token $2E): replaces an address with the byte there.
;; In: X = the noun stack, its top entry the address
;; Out: X = the noun stack, its top entry the byte
;; Also: PEEK (IBSM)
.proc Peek
    jsr GetNumber
    lda (Accumulator),y
    sty NounStackNumberHigh-1,x
    jmp PushNoun
.endproc

.endscope

; POKE and the first of two values.
.scope Statements continued

;; The first of a statement's two values: POKE's comma (token $65), PLOT, HLIN and VLIN (tokens $67, $69 and $6C).
;;
;; It keeps the byte in <FirstValueByte>, for the routine that runs next: the value POKE stores, PLOT's column, HLIN's
;; left end or VLIN's top row.
;; In: X = the noun stack, its top entry the value
;; Out: FirstValueByte = the value, A = the value, X = the noun stack, one entry higher, Y = 0
;; Errors: >255
;; See: <Poke>, <PlotComma>, <HLinComma>, <VLinComma>
;; Also: GETVAL255 (IBSM)
.proc FirstValue
    jsr GetByte
    lda Accumulator
    sta FirstValueByte
    rts
.endproc

;; POKE (token $64): stores the value its comma kept at the address.
;; In: X = the noun stack, its top entry the address, FirstValueByte = the value
;; See: <FirstValue>
;; Also: POKE (IBSM)
.proc Poke
    jsr GetNumber
    lda FirstValueByte
    sta (Accumulator),y
    rts
.endproc

.endscope

; Division.
.scope Operators continued

;; Division (token $15): replaces two numbers with the quotient, rounded toward 0.
;; In: X = the noun stack: the dividend, then the divisor on top
;; Out: X = the noun stack, its top entry the quotient
;; Errors: >32767 for a division by 0
;; See: <DivideWithRemainder>, <Operators::Mod>
;; Also: DIVIDE (IBSM)
.proc Divide
    jsr DivideWithRemainder
    lda Accumulator
    sta Pointer3
    lda Accumulator+1
    sta Pointer3+1
    jmp Operators::Multiply::PushResult
.endproc

.endscope

; DIM of a numeric array.
.scope Statements continued

;; DIM of a numeric array (token $4F, and $44 after a comma): makes the newest variable's value 2 x (n + 1) bytes,
;; elements 0 to n.
;; In: X = the noun stack: the size n above the variable's address
;; Errors: RANGE for a size of $8000 bytes or more, or an n of -1, MEM FULL, DIM for a variable that is not the newest
;; See: <SetVariableSize>, <Statements::DimString>
;; Also: DIMNUM (IBSM)
.proc DimNumber
    jsr ArraySize
    jmp SetVariableSize
.endproc

.endscope

; An array element.
.scope Operators continued

;; An array element (token $2D): replaces an array's address and an index with the element's address.
;;
;; The element must lie below the address of the next variable, the end of the array: indexes run from 0 to the
;; size DIM gave. An array that was never DIMed has room for element 0 only. The routine then ends as a left
;; parenthesis does (<Operators::LeftParenthesis>), as the token opens the index's parenthesis.
;; In: X = the noun stack: the index above the array's address
;; Out: X = the noun stack, its top entry the element's address
;; Errors: RANGE for an index past the end, or below 0
;; See: <ArraySize>
;; Also: PAREN_ARRAY (UNKN)
.proc ArrayElement
    ; Auxiliary = the array's address - 2, where the next variable's address is. The carry is clear from ArraySize.
    jsr ArraySize
    ldy NounStackHigh,x
    lda NounStackLow,x
    adc #<(-2)
    bcs AddSize
    dey

AddSize:
    sta Auxiliary
    sty Auxiliary+1

    ; Auxiliary + (index + 1) x 2 is the element's address.
    clc
    adc Accumulator
    sta NounStackLow,x
    tya
    adc Accumulator+1
    sta NounStackHigh,x

    ; It must be below the next variable.
    ldy #0
    lda NounStackLow,x
    cmp (Auxiliary),y
    iny
    lda NounStackHigh,x
    sbc (Auxiliary),y
    bcs Statements::VLinAt::RangeErrorIfCarry
    jmp Operators::LeftParenthesis
.endproc

.endscope

; RND.
.scope Functions continued

;; RND (token $2F): replaces n with a random number from 0 to n - 1 (from 0 to -(n - 1) for a negative n).
;;
;; The random state is <RandomSeed>/<RandomSeedHigh>, which the Monitor's keyboard routine counts up while it waits
;; for a key. RND takes the state, cleared of bit 15 and never 0, modulo n (<Operators::Mod>), and advances it 17 times
;; as a shift register whose new low bit is bits 14 and 13 exclusive-ORed.
;; In: X = the noun stack, its top entry n
;; Out: X = the noun stack, its top entry the random number
;; Errors: >32767 for an n of 0
;; Also: RND (IBSM)
.proc Rnd
    ; Push the state: its low byte now, its high byte once cleared of bit 15.
    jsr GetNumber
    lda RandomSeed
    jsr PushNoun
    lda RandomSeedHigh
    bne ClearTopBit
    cmp RandomSeed
    adc #0                          ; a high byte of 0 becomes 1 if the low byte is 0 too, so the state is never 0

ClearTopBit:
    and #RANDOM_HIGH_MASK
    sta RandomSeedHigh
    sta NounStackNumberHigh,x

    ; Advance the state. Bit 7 of (high byte x 2 + $40) is bits 14 and 13 exclusive-ORed.
    ldy #RANDOM_SHIFTS
Advance:
    lda RandomSeedHigh
    asl a
    clc
    adc #RANDOM_TAP
    asl a
    rol RandomSeed
    rol RandomSeedHigh
    dey
    bne Advance

    ; Push n, and take the state modulo n.
    lda Accumulator
    jsr PushNoun
    lda Accumulator+1
    sta NounStackNumberHigh,x
    jmp Operators::Mod
.endproc

.endscope

;; Two routines that move the ends of BASIC's memory and erase the program, which nothing in the ROM reaches, and
;; the setup for a 4K machine.
;;
;; The statements HIMEM: and LOMEM: (<Statements::HiMem>, <Statements::LoMem>) are the routines BASIC uses.
.scope Memory

;; Sets HIMEM to the number on the noun stack, if it is not below LOMEM, and erases the program; nothing in the ROM
;; reaches it.
;;
;; A new HIMEM below LOMEM was meant to be a RANGE error, but the branch reaches
;; <Statements::VLinAt::RangeErrorIfCarry> with the carry clear, which goes on to draw a vertical line instead.
;; In: X = the noun stack, its top entry the new HIMEM
;; Entry:
;;   ToNew = erases the program (<Statements::New>)
;; Also: SETHIMEM (UNKN)
.proc SetHighMemory
    jsr GetNumber
    ldy Accumulator
    cpy LowMemory
    lda Accumulator+1
    sbc LowMemory+1
    bcc SetLowMemory::ToRangeErrorIfCarry
    sty HighMemory
    lda Accumulator+1
    sta HighMemory+1

;; Erases the program (<Statements::New>).
;; Also: JMPNEW (UNKN)
ToNew:
    jmp Statements::New
.endproc

;; Sets LOMEM to the number on the noun stack, if it is below HIMEM, and erases the program; nothing in the ROM
;; reaches it.
;; In: X = the noun stack, its top entry the new LOMEM
;; Errors: RANGE if it is not below HIMEM
;; Entry:
;;   ToRangeErrorIfCarry = a RANGE error if the carry is set
;; Also: SETLOMEM (UNKN)
.proc SetLowMemory
    jsr GetNumber
    ldy Accumulator
    cpy HighMemory
    lda Accumulator+1
    sbc HighMemory+1
    bcs ToRangeErrorIfCarry
    sty LowMemory
    lda Accumulator+1
    sta LowMemory+1
    bcc SetHighMemory::ToNew        ; always

;; A RANGE error if the carry is set.
;; Also: JmpBcsRANGEERR (IBSM)
ToRangeErrorIfCarry:
    jmp Statements::VLinAt::RangeErrorIfCarry
.endproc

    ; Unused bytes.
    .res 8, $FF

.endscope

; INPUT of a string, and INPUT's prompt.
.scope Statements continued

;; INPUT of a string (token $52, and $26 after a comma): reads a line into the string variable.
;; In: X = the noun stack, its top entries the variable's range and address
;; See: <Strings::ReadLineInto>
;; Also: INPUT_STRVAR (UNKN)
.proc InputString
    jsr Strings::ReadLineInto
    jmp MarkInputLineUsed
.endproc

;; INPUT with a prompt (token $53): prints the prompt string; the variables follow.
;;
;; It marks the input line as used up, so the first numeric variable asks for a line (<Statements::InputNumberComma>).
;; In: X = the noun stack, its top entries the prompt's range and address
;; Out: X = the noun stack, both popped
;; Also: INPUT_PROMPT (IBSM)
.proc InputPrompt
    jsr PrintString
    ; Falls into MarkInputLineUsed.
.endproc

.endscope

;; Marks the input line as used up: <TextIndex> before the buffer, and <TOKEN_INPUT_END> at its start.
;; Out: TextIndex = $FF, A = <TOKEN_INPUT_END>
;; Keeps: X, Y
;; Also: INLINEDONE (UNKN)
.proc MarkInputLineUsed
    lda #$FF
    sta TextIndex
    lda #TOKEN_INPUT_END
    sta InputBuffer
    rts
.endproc

;; Replaces the top two numbers with NOT of each, for AND and OR, leaving the lower one's in A.
;;
;; By De Morgan's laws, AND is NOT of (NOT a OR NOT b), and OR is NOT of (NOT a AND NOT b) (<Operators::And>,
;; <Operators::Or>).
;; In: X = the noun stack: two numbers
;; Out: A = NOT of the lower number, 0 or 1, X = the noun stack at the lower one, with NOT of the top one below it,
;;   Y = 0
;; Uses: Accumulator
;; Entry:
;;   TopOnly = NOT of the top number only, with A = the result and zero = set for 0, without moving X; IF uses it
;; Also: NOTBOTH (UNKN)
.proc InvertBoth
    jsr Operators::Not
    inx

;; NOT of the top number only, with A = the result and zero = set for 0, without moving X; IF uses it.
;; Also: NOTTOP (UNKN)
TopOnly:
    jsr Operators::Not
    lda NounStackLow,x
    rts
.endproc

.scope Memory continued

;; Sets up memory for a 4K machine: LOMEM at $0800 and HIMEM at $1000, then erases the program (<Statements::New>).
;; See: <ColdStart4K>, <ColdStart>
;; Also: SETMEM4K (UNKN)
.proc SetFor4K
    lda #0
    sta LowMemory
    sta HighMemory
    lda #VARIABLES_PAGE
    sta LowMemory+1
    lda #END_OF_4K_PAGE
    sta HighMemory+1
    jmp Statements::New
.endproc

.endscope

;; The end of a substring's checks: carry clear if A is at most the string's end, for
;; <Operators::Substring::CheckRange>.
;; In: A = the substring's end, X = the noun stack, NounStackHigh,X = the string's end
;; Out: Y = $FF, VerbPriority = $FF (<Operators::Substring::CheckRange> returns through <Operators::LeftParenthesis>)
;; Errors: STRING if A is past the string's end
;; See: <Operators::SubstringComma>
;; Also: CHKSTREND (UNKN)
.proc CheckSubstringEnd
    cmp NounStackHigh,x
    bne ToCheckRange
    clc

ToCheckRange:
    jmp Operators::Substring::CheckRange
.endproc

; RUN.
.scope Statements continued

;; RUN alone (token $08): clears the variables and runs the program from its first line.
;; See: <Statements::Clr>, <Lines::RunFromStart>
;; Also: RUN (IBSM)
.proc Run
    jsr Statements::Clr
    jmp Lines::RunFromStart
.endproc

;; RUN with a line number (token $07): clears the variables and runs the program from that line.
;; In: X = the noun stack, its top entry the line number
;; Errors: BAD BRANCH if there is no such line
;; See: <Statements::Clr>, <Statements::GoTo>
;; Also: RUNNUM (IBSM)
.proc RunLine
    jsr Statements::Clr
    jmp Statements::GoTo
.endproc

.endscope

;; For the lister: before a keyword, skips the blank its text starts with, if any, then prints a blank if the keyword
;; starts with a letter (<Lister::BlankAfterLetter>).
;; In: X = the keyword's first table byte, Y = its index in the syntax table's page
;; Out: Y = the index of the first character to print
;; Uses: A, Pointer2
;; Keeps: X
;; See: <Lister::PrintLine::PrintToken>
;; Also: KEYBLANK (UNKN)
.proc BlankBeforeKeyword
    cpx #KEYWORD_BLANK
    bne ToBlankIfLetter
    dey

ToBlankIfLetter:
    jmp Lister::BlankAfterLetter
.endproc
