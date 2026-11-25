; retrocore: style=strict
;; Integer BASIC: the error messages and INPUT of numbers
;;
;; The error messages, which <PrintMessage> prints by their offset in the page at $EB00, and the routines of INPUT for
;; numbers, which also handle an error in the line typed.
;;
;; INPUT reads a line and runs the tokenizer on it with a rule of its own, <Syntax::InputLineStart>: a list of
;; numbers, each with an optional sign, separated by commas. The numbers' tokens go after the line's text in
;; <InputBuffer>, as a program line's do, and each variable of the INPUT statement takes the next one. A line that is
;; not a list of numbers is an error, which here asks for the line again: RETYPE LINE.
;;
;; Part of IntegerBasic.asm; it follows VerbTables.asm, at $EB00.

;; Places a message: its characters with bit 7 set, except the last one's, which ends the message for <PrintMessage>.
;;
;; Earlier versions of this source called it MSG.
;; Parameters:
;;   text = the message
.macro Message text
    .repeat .strlen(text) - 1, I
        .byte .strat(text, I)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) & $7F
.endmacro

;; The error messages, and what a running program does on an error.
;;
;; Each message is its characters with bit 7 set on all but the last. The routines that report an error load Y with
;; the low byte of a message's address, its offset in this page (`ldy #<Messages::TooLong`). An error prints
;; <Messages::ErrorStart>, the message and <Messages::ErrorEnd> (<Messages::PrintError>): `*** >32767 ERR` for the
;; first.
.scope Messages

;; `>32767`: a number that does not fit in 15 bits, or a result past 32767.
;; See: <ReportError>, <PrintMessage>, <Messages::PrintError>
;; Also: ErrMsg00 (IBSM)
GreaterThan32767:
    Message ">32767"
    .assert <GreaterThan32767 = 0, "The messages are found by their offset in the page."

;; `TOO LONG`: a line with too many tokens, or a syntax nested too deeply.
;; Also: ErrMsg01 (IBSM)
TooLong:
    Message "TOO LONG"

;; `SYNTAX`: a line that matches no rule of the syntax table (<Syntax::Table>).
;;
;; Named SyntaxError rather than Syntax, which is the syntax table's scope.
;; Also: ErrMsg02 (IBSM)
SyntaxError:
    Message "SYNTAX"

;; `MEM FULL`: the program and the variables would overlap.
;; Also: ErrMsg03 (IBSM)
MemoryFull:
    Message "MEM FULL"

;; `TOO MANY PARENS`, which no routine reports.
;; Also: ErrMsg04 (IBSM)
TooManyParentheses:
    Message "TOO MANY PARENS"

;; `STRING`: a substring position out of range.
;; Also: ErrMsg05 (IBSM)
String:
    Message "STRING"

;; `NO END`: the program ran past its last line.
;; Also: ErrMsg06 (IBSM)
NoEnd:
    Message "NO END"

;; `BAD BRANCH`: `GOTO` or `GOSUB` to a line that does not exist.
;; Also: ErrMsg07 (IBSM)
BadBranch:
    Message "BAD BRANCH"

;; `16 GOSUBS`: a `GOSUB` with the `GOSUB` stack full.
;; Also: ErrMsg08 (IBSM)
SixteenGoSubs:
    Message "16 GOSUBS"

;; `BAD RETURN`: `RETURN` with no `GOSUB` active.
;; Also: ErrMsg09 (IBSM)
BadReturn:
    Message "BAD RETURN"

;; `16 FORS`: a `FOR` with the `FOR` stack full.
;; Also: ErrMsg10 (IBSM)
SixteenFors:
    Message "16 FORS"

;; `BAD NEXT`: `NEXT` for a variable no `FOR` loop has.
;; Also: ErrMsg11 (IBSM)
BadNext:
    Message "BAD NEXT"

;; `STOPPED AT`, which <Lines::Stop> prints before the line number.
;;
;; A full noun stack's error (<PushNoun>) prints it from its fourth character: `PPED AT`.
;; Also: ErrMsg12 (IBSM)
StoppedAt:
    Message "STOPPED AT "

;; The `***` that starts every error.
;; Also: ErrMsg13 (IBSM)
ErrorStart:
    Message "*** "

;; `ERR` and a return, which end every error; the return, bit 7 clear, ends the message.
;; Also: ErrMsg14 (IBSM)
ErrorEnd:
    .byte " ERR", CARRIAGE_RETURN

;; `>255`: a value that must fit in a byte.
;; Also: ErrMsg15 (IBSM)
GreaterThan255:
    Message ">255"

;; `RANGE`: a value outside what a statement allows, such as a screen position.
;; Also: ErrMsg16 (IBSM)
Range:
    Message "RANGE"

;; `DIM`: `DIM` of a variable that is not the newest.
;; Also: ErrMsg17 (IBSM)
Dim:
    Message "DIM"

;; `STR OVFL`: a string longer than its `DIM`.
;; Also: ErrMsg18 (IBSM)
StringOverflow:
    Message "STR OVFL"

    ; A message no routine reports: a backslash and a return. Apple-1 BASIC, whose messages these are, reports it.
    .byte '\', CARRIAGE_RETURN

;; `RETYPE LINE` and a return, then `?`, for a line INPUT could not read.
;;
;; The return has bit 7 set, so the message runs on into <QuestionMark>.
;; Also: ErrMsg20 (IBSM)
RetypeLine:
    .byte "RETYPE LINE", CARRIAGE_RETURN | $80

;; `?`: INPUT's prompt for numbers.
;; Also: ErrMsg21 (IBSM)
QuestionMark:
    .byte '?' & $7F

;; An error in a running program: stops it at the line, or, while INPUT tokenizes a typed line, asks for the line
;; again.
;;
;; <ReportError> comes here once it has printed the error, when bit 7 of <Running> is set. <Running> is $FF while a
;; program runs and $FE while INPUT tokenizes (<Statements::InputNumber>), so bit 0 tells the two apart. Either way it
;; leaves <Running> with bit 7 clear, and <Statements::InputNumber::ReadLine> sets it again.
;; In: Running = $FF or $FE, Accumulator = INPUT's noun stack index, then its 6502 stack pointer, while it tokenizes
;; See: <ReportError>, <Statements::InputNumber>
;; Also: RUNERROR (UNKN)
.proc StopOrRetype
    lsr Running
    bcc Retype
    jmp Lines::Stop

Retype:
    ; Put back the noun stack and the 6502's stack INPUT had, print RETYPE LINE and ?, and read the line again.
    ldx Accumulator+1
    txs
    ldx Accumulator
    ldy #<RetypeLine
    bne Statements::InputNumber::ReadLine ; always
.endproc

.endscope

; Statements, continued: INPUT of numbers.
.scope Statements continued

;; INPUT of numbers without a prompt (token $54): prints ? and reads a line, then tokenizes it as a list of numbers
;; and assigns the first one.
;;
;; <InputNumberComma> comes back here, for a new line, when the variables outnumber the numbers typed. A line that
;; is not a list of numbers prints its error and RETYPE LINE (<Messages::StopOrRetype>), and is read again from
;; <InputNumber::ReadLine>; Control-C in the line goes back to BASIC's prompt (<ReadNumberLine>).
;;
;; The tokenizing leaves <Running> at $FF, as a running program has it, whatever it was before. A bug: in a line typed
;; without a line number, which reaches `INPUT` through `IF ... THEN`, the run loop (<Lines::RunLoop>) then goes on as
;; if a program were running, from the line after <CurrentLine>, the last line a program ran: the typed line never
;; becomes <CurrentLine>. After a program that stopped at line 10, line 20 runs; where nothing has run since power-on
;; and it is still 0, as in the emulator's cleared RAM, it runs page zero as a line (IntegerBasicQuirkTests pins the
;; first).
;; In: X = the noun stack, its top entry the first variable's address
;; Out: X = the noun stack, the variable popped
;; Uses: A, Y, Accumulator, Auxiliary, TextIndex, TokenIndex
;; See: <InputNumberComma>, <ReadNumberLine>
;; Entry:
;;   ReadLine = prints the message at offset Y in <Messages> instead of ?
;; Also: INPUTNUM (UNKN)
.proc InputNumber
    ldy #<Messages::QuestionMark

;; Also: READNUMLINE (UNKN)
ReadLine:
    jsr PrintMessage

    ; Keep the noun stack and the 6502's stack, for RETYPE LINE.
    stx Accumulator
    tsx
    stx Accumulator+1

    ; Read the line; Y = the index of the underline that ends it, where the tokens start.
    jsr ReadNumberLine
    sty TokenIndex
    lda #$FF                        ; before the line's first character
    sta TextIndex
    asl a
    sta Running                     ; $FE: tokenizing for INPUT

    ; Tokenize it from the INPUT rule; <TextIndex> is left at the underline, before the tokens.
    ldx #SYNTAX_STACK_EMPTY
    lda #(Syntax::InputLineStart - Syntax::Table - 1) / 2
    jsr Tokenizer::StartRule
    inc Running                     ; $FF
    ldx Accumulator
    ; Falls into InputNumberComma.
.endproc

;; Assigns the next number of the typed line to the variable (token $27, the comma between INPUT's variables, and
;; after <InputNumber>).
;;
;; <TextIndex> keeps the place in the line's tokens. The INPUT rule writes <TOKEN_INPUT_END> at the end of the line,
;; <TOKEN_INPUT_COMMA> for a comma, <TOKEN_INPUT_PLUS> and <TOKEN_INPUT_MINUS> for the signs, and each number as its
;; marker digit and value; a minus sign just before the number negates it. When the line has no numbers left, it
;; reads another (<InputNumber>).
;;
;; The token before the number is kept exclusive-ORed with the marker of 0. The value A comes in with is doubled
;; first, so it is even and never matches the minus sign's odd value when the number is the line's first token.
;; In: X = the noun stack, its top entry the variable's address, TextIndex = the last token used
;; Out: X = the noun stack, the variable popped
;; Uses: A, Y, Accumulator, Auxiliary, TextIndex
;; See: <Statements::AssignNumber>
;; Also: COMMA_INPUT (UNKN)
.proc InputNumberComma
    ldy TextIndex
    asl a

SkipToNumber:
    ; Step over the tokens before the next number, keeping the last one in Accumulator.
    sta Accumulator
    iny
    lda InputBuffer,y
    cmp #TOKEN_INPUT_END
    beq InputNumber                 ; the end of the line: read another
    eor #'0'                        ; a digit marker gives 0 to 9
    cmp #'9' - '0' + 1
    bcs SkipToNumber

    ; Push the number: its low byte, then its high byte, after the marker.
    iny
    iny
    sty TextIndex
    lda InputBuffer,y
    pha
    lda InputBuffer-1,y
    ldy #0                          ; a number, not an address
    jsr PushNoun
    pla
    sta NounStackNumberHigh,x

    ; Negate it after a minus sign.
    lda Accumulator
    cmp #TOKEN_INPUT_MINUS ^ '0'
    bne Assign
    jsr Operators::Negate

Assign:
    jmp Statements::AssignNumber
.endproc

.endscope

    ; The rest of the page is unused.
    .res 3, $FF
    .assert * = $EC00, "The syntax table starts a page."
