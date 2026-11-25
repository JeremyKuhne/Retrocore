; retrocore: style=strict
;; B3INPUF: `INPUT`, `GET` and `READ`, which share one loop over their variables, <AssignVariableList>; `NEXT`; the type
;; checks <EvaluateNumber>, <RequireNumber> and <RequireString>; and the first half of <EvaluateExpression>, the formula
;; evaluator, up to taking an operator off its stack (B3EvalG.asm goes on from there).
;;
;; `INPUT`, `GET` and `READ` tell themselves apart by <INPFLG>: <INPUT_MODE_INPUT>, <INPUT_MODE_GET> or
;; <INPUT_MODE_READ>. Each keeps the place in its data in <INPPTR> (with its X-byte in <INPPTRB>), pointing at the
;; separator before the next item, and the place in the statement's variable list in <VARTXT> while <TXTPTR> reads the
;; data.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; INPUT, GET and READ
; ---------------------------------------------------------------------------------------------------------------------

;; <INPFLG> for `INPUT`.
INPUT_MODE_INPUT = $00

;; <INPFLG> for `GET`: bit 6 set.
INPUT_MODE_GET = $40

;; <INPFLG> for `READ`: bit 7 set.
INPUT_MODE_READ = $98

;; CONTROL-C, as the console reads it: a CONTROL-C at the start of `INPUT`'s line stops the program.
CONTROL_C = $03

;; The error number a bad answer to `INPUT` gives `ON ERR`, in <ERRNUM>.
ERROR_REENTER = 254

;; The error number data left over by `INPUT` or `GET` gives `ON ERR`, in <ERRNUM>.
ERROR_EXTRA_IGNORED = 253

;; Handles a data item that does not end in a comma or the end: `INPUT` asks again, `READ` and `GET` end with SYNTAX
;; <ERROR>.
;;
;; `READ`'s error names the `DATA` statement's line, from <DATLIN>.
;; Entry:
;;   ToSyntaxError = ends the statement with a syntax error
;; Also: TRMNOK (BB13)
.proc HandleBadInput
    lda INPFLG
    beq RetryInput                          ; INPUT
    bpl ToSyntaxError                       ; GET
    lda DATLIN
    ldy DATLIN+1
    sta CURLIN
    sty CURLIN+1

;; Ends the statement with a syntax error.
;; Also: SNERR4 (BB13)
ToSyntaxError:
    jmp SNERR
.endproc

;; Drops the byte <AssignVariableList::ConvertNumber> pushed, then asks again.
;; Also: TRMNO2 (BB13)
.proc DiscardAndRetryInput
    pla
    ; Falls into RetryInput.
.endproc

;; Asks again for `INPUT`'s line: `INPUT#` from a file ends with TYPE MISMATCH, and with `ON ERR` the program goes to
;; its line with error <ERROR_REENTER>.
;; Entry:
;;   PrintReenter = prints ?REENTER and runs the `INPUT` statement again from its start
;; Also: TRMNO1 (BB13)
.proc RetryInput
    bit FILNO                               ; from the console?
    bmi FromConsole
    jmp TMERR

;; Asks again, unless `ON ERR` takes the error.
FromConsole:
    bit ERRFLG                              ; ON ERR on?
    bpl PrintReenter
    ldy CURLIN+1
    iny
    beq PrintReenter
    ldx #ERROR_REENTER
    jmp ERROR

;; Prints ?REENTER and runs the `INPUT` statement again from its start.
;; Also: DOAGIN (BB13)
PrintReenter:
    lda #<(RetryMessage)
    ldx #0
    ldy #>(RetryMessage)
    jsr PrintText
    jsr RewindInputStatement
    pla                                     ; NextStatement's return address: SavePlace, which
    pla                                     ; needs no terminator, runs INPUT again
    jmp NextStatement::SavePlace
.endproc

;; Points <TXTPTR> back at the statement's start, from <OLDTXT>.
;; Entry:
;;   Done = returns; `INPUT` branches here
;; Also: DOAG2 (BB13)
.proc RewindInputStatement
    lda OLDTXT
    ldy OLDTXT+1
    ldx OLDTXTB
    stx TXTPTRB
    sta TXTPTR
    sty TXTPTR+1

;; Returns, for `INPUT`.
;; Also: GTRTS (BB13)
Done:
    rts
.endproc

.scope Statements continued
; GET and INPUT.

;; The `GET` statement: reads one key, without echo, into each variable of its list, from the console, the <EXEC> file
;; while `EXEC` runs, or a file after `#n;`.
;;
;; A numeric variable takes the key's value as `VAL` would give it.
;; In: A = the character after `GET`, flags as <CHRGOT> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <DOAGET>, <AssignVariableList::SwitchToData>
;; Also: GET (BB13)
.proc Get
    jsr ERRDIR
    ldx INFLNO                              ; EXEC's file, if it runs
    bne KeepReference
    ldx SLINTB+1                            ; else the console's

;; Reads from the reference number in X, or from the file after `#`.
KeepReference:
    stx GETREF
    cmp #'#'
    bne StartLoop
    jsr GTFLNO
    sta GETREF
    jsr CHKSMC

;; Starts the variable loop with no data, the zero at <BUF>+1, so each variable reads a key.
;; Also: GOTREF (BB13)
StartLoop:
    ldx #<(BUF+1)
    ldy #>(BUF+1)
    lda #$80                                ; no terminators
    sta QUOTE
    lda #0
    sta YSAVE                               ; the data's X-byte
    sta BUF+1
    sta BUF
    lda #INPUT_MODE_GET
    jmp AssignVariableList
.endproc

;; The `INPUT` statement: prints a prompt, reads a line from the console, or from a file after `#n;`, and assigns its
;; items to the variables of the list.
;;
;; The prompt is the string given, or `?`. Items are separated by commas; the last variable, when a string, takes the
;; rest of the line, commas and all. When the line runs out, `??` asks for more. CONTROL-C at the start of the line
;; stops the program, where `CONT` runs the `INPUT` again.
;; In: A = the character after `INPUT`, flags as <CHRGOT> sets them
;; Errors: ILLEGAL DIRECT in a direct line
;; See: <AssignVariableList>, <HandleBadInput>, <AssignVariableList::ListDone>
;; Also: INPUT (BB13)
.proc Input
    jsr ERRDIR
    jsr CHRGOT
    cmp #'"'                                ; a prompt?
    bne CheckFile
    jsr STRTXT
    jsr CHRGOT
    cmp #','
    beq PrintPrompt
    lda #';'                                ; not a comma: it must be a semicolon

;; Checks the comma or semicolon after the prompt, prints the prompt, and reads the line.
;; Also: INPAOK (BB13)
PrintPrompt:
    jsr SYNCHR
    jsr PrintString
    jmp ReadLine

;; Takes `INPUT# n;` from a file, or prints the `?` prompt.
;; Also: NOTQT0 (BB13)
CheckFile:
    cmp #'#'
    bne QuestionPrompt
    ror IOFLG
    jsr FILNUM
    jsr CHRGOT
    cmp #';'
    bne RewindInputStatement::Done          ; no semicolon: NextStatement gives the syntax error
    lda SVFLNO
    sta FILNO
    jsr CHRGET
    jsr DSKLIN
    lda #','                                ; a comma before the line, as the separator
    sta BUF-1
    jmp AssignInputList

;; Prints the `?` prompt.
;; Also: NOTQTI (BB13)
QuestionPrompt:
    jsr PrintQuestionMark

;; Reads `INPUT`'s line from the console into <BUF>, with a comma before it.
;; Also: NOTQTII (BB13)
ReadLine:
    ldx #0
    stx QUOTE                               ; commas end items
    dex
    stx FILNO                               ; from the console
    lda #','
    sta BUF-1
    jsr INLIN
    lda BUF
    cmp #CONTROL_C                          ; CONTROL-C at the start?
    bne AssignInputList
    jsr RewindInputStatement                ; so CONT runs the INPUT again
    lda #CONTROL_C
    jmp HandleBreak::WithFlags
.endproc

.endscope

;; Prints `?` and reads a line from the console, so a second `?` follows `INPUT`'s.
;; Also: QINLIN (BB13)
.proc PromptAndInputLine
    jsr PrintQuestionMark
    jmp INLIN
.endproc

.scope Statements continued
; READ.

;; The `READ` statement: assigns the items of the program's `DATA` statements to the variables of the list, from
;; <DATPTR> on; `READ#` reads from a file instead.
;; In: A = the character after `READ`, flags as <CHRGOT> sets them
;; Errors: OUT OF DATA when the `DATA` statements run out, SYNTAX ERROR for a bad item (on the `DATA`'s line)
;; See: <AssignVariableList::SearchData>, <DREAD>, <Statements::Restore>
;; Also: READ (BB13)
.proc Read
    ldx DATPTRB
    stx YSAVE
    ldx DATPTR
    ldy DATPTR+1
    cmp #'#'
    bne StartLoop
    jmp DREAD

;; Starts `READ`'s variable loop.
;; Also: READON (BB13)
StartLoop:
    lda #0
    sta QUOTE
    lda #INPUT_MODE_READ
    .byte $2C                               ; BIT absolute skips AssignInputList's LDA
    ; Falls into AssignInputList.
.endproc

.endscope

;; Starts `INPUT`'s variable loop.
;; In: X, Y = the data's place (low, high), YSAVE = its X-byte
;; Also: INPCON (BB13)
.proc AssignInputList
    lda #INPUT_MODE_INPUT
    ; Falls into AssignVariableList.
.endproc

;; Assigns an item of the data to each variable of `INPUT`'s, `GET`'s or `READ`'s list.
;;
;; <INPPTR> keeps the place in the data while <VARTXT> keeps the place in the list. `GET` reads a key when its data,
;; which starts empty, runs out; `READ` looks for the next `DATA` statement; `INPUT` reads another line.
;; In: A = <INPFLG>'s value, X, Y = the data's place (low, high), YSAVE = its X-byte
;; Errors: OUT OF DATA when `READ` finds no more `DATA`, and <HandleBadInput>'s for a bad item
;; Entry:
;;   SearchData = looks for the next `DATA` statement
;;   ListDone = ends the loop
;; See: <MYPTRGET>, <AssignString>, <StoreNumber>
;; Also: INPCO1 (BB13)
.proc AssignVariableList
    sta INPFLG
    stx INPPTR
    ldx YSAVE
    stx INPPTRB
    sty INPPTR+1

;; Takes the next variable of the list; for `INPUT` and `GET`, the last one takes the data with no terminators.
;; Also: INLOOP (BB13)
NextVariable:
    jsr MYPTRGET                            ; the variable's address in FORPNT
    bit INPFLG
    bmi SwitchToData                        ; READ
    jsr CHRGOT
    bne SwitchToData
    lda #$80                                ; the last variable: no terminators
    sta QUOTE

;; Moves <TXTPTR> to the data, keeping the list's place in <VARTXT>, and takes the next item; at the end of the data,
;; `GET` reads a key, `READ` finds the next `DATA` statement, and `INPUT` reads another line.
;; Also: INLP2 (BB13)
SwitchToData:
    jsr SaveTextPointer
    ldx INPPTR
    ldy INPPTR+1
    lda INPPTRB
    sta TXTPTRB
    stx TXTPTR
    sty TXTPTR+1
    ldy #0
    lda (TXTPTR),y                          ; the separator, or the data's end
    bne NextValue
    bit INPFLG
    bvc SourceEmpty
    jsr DOAGET                              ; GET: a key into KEYSAVE
    ldx #<(KEYSAVE)
    ldy #>(KEYSAVE)
    stx STRNG1
    sty STRNG1+1
    lda #0
    sta STRNG1B
    lda VALTYP
    pha
    ldy RNDGOT                              ; the count read: one
    jsr STRCP
    pla
    sta VALTYP
    jsr ConvertKey
    jsr AssignFac
    jmp CheckTerminator

;; Gets more data: `READ` looks for the next `DATA`, `INPUT` reads another line from its file or the console.
;; Also: QDATA (BB13)
SourceEmpty:
    bmi ToSearchData                        ; READ
    bit FILNO
    bmi AskForMore                          ; the console
    jsr DSKLIN
    jmp SetCursor

;; Asks for more with `??`.
;; Also: QD11 (BB13)
AskForMore:
    jsr PrintQuestionMark
    jsr PromptAndInputLine

;; Points <TXTPTR> at the new line.
;; In: X, Y = the line's place (low, high)
;; Also: DATBK (BB13)
SetCursor:
    stx TXTPTR
    lda INPPTRB
    sta TXTPTRB
    sty TXTPTR+1

;; Takes the item after the separator: a number, or a string.
;; Also: DATBK1 (BB13)
NextValue:
    ldy #1
    jsr AdvanceTextPointer                  ; past the separator
    bit VALTYP
    bpl ConvertNumber                       ; a number
    bit INPFLG
    bvc SetDelimiters
    inx                                     ; GET (never here: its data stays the zero)
    stx TXTPTR

;; Takes the string up to the data's end, with no terminators.
;; Also: NOTERMS (BB13)
NoDelimiters:
    lda #0
    sta CHARAC
    beq StringAtCursor

;; Goes on looking for `READ`'s next `DATA` statement.
;; Also: DTLP1 (BB13)
ToSearchData:
    jmp SearchData

;; Chooses the string's terminators: a quote for a quoted string, a comma otherwise, none for the last variable of
;; `INPUT`.
;; Also: SETQUT (BB13)
SetDelimiters:
    ldy #0
    lda (TXTPTR),y
    sta CHARAC
    bit QUOTE
    bmi NoDelimiters
    cmp #'"'                                ; a quote: the string is inside it
    beq MakeString
    lda #','
    sta CHARAC

;; Starts the string at <TXTPTR> itself.
;; Also: RESETC (BB13)
StringAtCursor:
    clc

;; Makes a string of the item and assigns it.
;; In: A = <ENDCHR>'s terminator, carry = set to start after <TXTPTR> (past a quote)
;; Also: NOWGET (BB13)
MakeString:
    sta ENDCHR
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    adc #0
    bcc HaveAddress
    iny
    cpy #MAXPG
    bcc HaveAddress
    inx
    ldy #MINPG

;; Makes the string, moves <TXTPTR> past it and assigns it.
;; Also: NOWGE1 (BB13)
HaveAddress:
    jsr STRLT2
    jsr ST2TXT
    jsr AssignString
    jmp CheckTerminator

;; Takes a number: an empty `INPUT` line, or an `INPUT` item with no digits, asks again.
;; In: overflow = set for a long integer, as <VALTYP>'s BIT sets it
;; Also: NUMINS (BB13)
ConvertNumber:
    pha
    lda BUF
    beq EmptyNumber                         ; an empty line

;; Reads the number, a long integer through <LINP> or a real through <FIN>.
;; Also: NUMINS2 (BB13)
ReadNumber:
    pla
    bvs ReadLongInteger                     ; a long integer
    jsr FIN
    bit INPFLG
    bvs StoreValue                          ; GET
    bmi StoreValue                          ; READ
    pha
    lda ANYNUM
    bmi EmptyNumber                         ; no digits
    pla

;; Stores the number as a real or an integer, as the variable is.
;; Also: NUMINS3 (BB13)
StoreValue:
    lda INTFLG
    jsr StoreNumber

;; Checks what ends the item, a terminator or a comma, then keeps the data's place and takes the next variable.
;; Also: STRDN2 (BB13)
CheckTerminator:
    jsr CHRGOT
    beq TerminatorOk
    cmp #','
    beq TerminatorOk
    jmp HandleBadInput

;; Keeps the data's place in <INPPTR>, goes back to the list, and takes the next variable or ends.
;; Also: TRMOK (BB13)
TerminatorOk:
    lda TXTPTR
    ldx TXTPTRB
    ldy TXTPTR+1
    sta INPPTR
    stx INPPTRB
    sty INPPTR+1
    jsr RestoreTextPointer
    jsr CHRGOT
    beq ListDone
    jsr CHKCOM
    jmp NextVariable

;; Reads a long integer and stores it.
;; Also: NUMBCD (BB13)
ReadLongInteger:
    jsr LINP
    jsr StoreLongInteger
    jmp CheckTerminator

;; Handles a missing number: `INPUT` asks again; `READ` and `GET` go on to read it.
;;
;; The empty-line test reads <BUF> even for `READ`, whose data is elsewhere, so `READ` comes here for nothing at times.
;; Also: MAYBAD (BB13)
EmptyNumber:
    lsr ANYNUM
    lda INPFLG
    bne ReadNumber
    jmp DiscardAndRetryInput

;; Looks for the next `DATA` statement, from <TXTPTR>, keeping its line number in <DATLIN>.
;; Errors: OUT OF DATA at the program's end
;; Also: DATLOP (BB13)
SearchData:
    jsr FindStatementEnd                    ; the statement's end
    iny
    tax
    bne CheckStatement                      ; a colon: the next statement is on this line
    ldx #ERROD
    lda (TXTPTR),y                          ; the next line's link
    bne NextDataLine
    jmp ERROR

;; Takes the next line's number.
NextDataLine:
    iny
    lda (TXTPTR),y                          ; the line number's low byte
    sta DATLIN
    iny
    lda (TXTPTR),y                          ; and its high byte
    iny
    sta DATLIN+1

;; Checks the statement's first byte for `DATA`, and takes its first item when it is.
;; Also: NOWLIN (BB13)
CheckStatement:
    lda (TXTPTR),y
    tax
    jsr AdvanceTextPointer
    cpx #DATATK
    bne SearchData
    jsr CHRGET
    jsr DECTPT
    jmp NextValue

;; Ends the variable loop: `READ` keeps its place in <DATPTR>; `INPUT` and `GET` check that the data is used up.
;;
;; Data left over prints ?EXTRA IGNORED through <ERRFIN>, which ends at <READY>; with `ON ERR` the program goes to its
;; line with error <ERROR_EXTRA_IGNORED> instead.
;; Also: VAREND (BB13)
ListDone:
    lda #0
    sta QUOTE
    lda INPPTR
    ldy INPPTR+1
    ldx INPPTRB
    bit INPFLG
    bpl CheckExtra
    jmp Statements::Restore::SetDataPointer ; READ

;; Checks for data left over.
;; Also: VARY0 (BB13)
CheckExtra:
    ldy #0
    lda (INPPTR),y                          ; the end should be a zero
    beq RestoreOutput
    jsr RestoreOutput
    bit ERRFLG                              ; ON ERR on?
    bpl PrintExtraIgnored
    ldx #ERROR_EXTRA_IGNORED
    ldy CURLIN+1
    iny
    beq PrintExtraIgnored
    jmp ERROR

;; Prints ?EXTRA IGNORED and the line.
;; Also: INPVAR0 (BB13)
PrintExtraIgnored:
    lda #<(ExtraIgnoredMessage)
    ldx #0
    ldy #>(ExtraIgnoredMessage)
    jmp ERRFIN

;; Sends output back to its usual place, after `INPUT#`.
;; Also: INPRTS (BB13)
RestoreOutput:
    lda FILNO+1
    sta FILNO
    rts
.endproc

;; Keeps <TXTPTR> in <VARTXT>.
;; Uses: A, X, Y
;; See: <RestoreTextPointer>
;; Also: SVTXT (BB13)
.proc SaveTextPointer
    lda TXTPTR
    ldy TXTPTR+1
    ldx TXTPTRB
    stx VARTXTB
    sta VARTXT
    sty VARTXT+1
    rts
.endproc

;; Sets <TXTPTR> back from <VARTXT>.
;; Uses: A
;; Keeps: X, Y
;; See: <SaveTextPointer>
;; Also: RSTTXT (BB13)
.proc RestoreTextPointer
    lda VARTXT
    sta TXTPTR
    lda VARTXT+1
    sta TXTPTR+1
    lda VARTXTB
    sta TXTPTRB
    rts
.endproc

;; The message for data left over, ending in a zero.
;; Also: EXIGNT (BB13)
ExtraIgnoredMessage:
    .byte "?EXTRA IGNORED"
    .byte 0

;; The message asking for `INPUT`'s line again, ending in a zero.
;; Also: TRYAGN (BB13)
RetryMessage:
    .byte "?REENTER"
    .byte RETURN_CHARACTER, LINE_FEED_CHARACTER, 0

;; Turns `GET`'s string into the variable's type: a real through <VAL>, a long integer through <STR2LNG>.
;; In: VALTYP = the variable's type
;; Also: CHANGTP (BB13)
.proc ConvertKey
    bit VALTYP
    bmi IsString
    bvs ToLongInteger
    jmp VAL

;; Returns: a string variable takes the string as it is.
;; Also: ISSTRIN (BB13)
IsString:
    rts

;; Turns the string into a long integer.
;; Also: ISLONG (BB13)
ToLongInteger:
    jmp STR2LNG
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; NEXT
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; NEXT.

;; The `NEXT` statement: adds the step to the loop's variable, and goes back after the `FOR` unless the variable has
;; passed the limit.
;;
;; `NEXT` alone takes the newest <ForEntry>; `NEXT` with variables takes each one's entry in turn, dropping the newer
;; `FOR` entries above it. The loop ends when the comparison of the new value with the limit (1 for greater, 0 for
;; equal, $FF for less) equals the step's sign; then the entry comes off the stack.
;; In: A = the character after `NEXT`, zero = set for a terminator
;; Errors: NEXT WITHOUT FOR when there is no entry for the variable
;; See: <Statements::For>, <FNDFOR>
;; Also: NEXT (BB13)
.proc Next
    bne WithVariable
    ldy #0
    sty FORPNT+1
    sty FORPNT
    beq SearchFrame                         ; FORPNT zero: the newest entry

;; Finds the loop variable's offset and type, the key of its `FOR` entry.
;; Also: GETFOR (BB13)
WithVariable:
    jsr MYPTRGET
    jsr Variables::VariableOffset
    lda ISARA
    rol a
    lda INTFLG
    adc #0                                  ; an array element into bit 0
    sta TEMPFOR
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY
    sta FORPNT+1

;; Finds the `FOR` entry.
;; Also: STXFOR (BB13)
SearchFrame:
    jsr FNDFOR
    beq AddStep
    ldx #ERRNF
    jmp ERROR

;; Cuts the stack to the entry, then adds the step to the variable's value.
;; In: X = the entry's place on the stack
;; Also: HAVFOR (BB13)
AddStep:
    lda #$FE                                ; the packed offset's X-byte
    sta FORPNTB
    txs
    txa
    clc
    adc #<(StackTop + ForEntry::STEP)
    tay
    adc #ForEntry::LIMIT - ForEntry::STEP
    sta INDEX2                              ; the limit, for FCOMPN
    tya
    ldy #>(StackTop + ForEntry::STEP)       ; in page 1
    ldx #0
    jsr MOVFM                               ; the step into the FAC
    tsx
    lda StackTop + ForEntry::STEP_SIGN,x
    sta FACSGN
    jsr Variables::VariableOffset           ; the offset back into the variable's address
    bit INTFLG
    bpl RealVariable
    jsr MOVAF                               ; an integer: the step into ARG
    lda FORPNT
    sta FACMO
    lda FORPNT+1
    sta FACMO+1
    lda FORPNTB
    sta FACMOB
    jsr GOOO2                               ; and the variable into the FAC
    jmp AddAndCompare

;; Takes a real variable's value into <ARG>.
;; Also: HAVFLT (BB13)
RealVariable:
    ldy FORPNT+1
    ldx FORPNTB
    lda FORPNT
    jsr CONUPK

;; Adds, compares with the limit, stores the new value, and loops or ends.
;; Also: HAVSUM (BB13)
AddAndCompare:
    lda ARGSGN
    eor FACSGN
    sta ARISGN
    lda FACEXP                              ; zero set for a zero FAC
    jsr FADDT
    ldy #>(StackTop + ForEntry::LIMIT)
    jsr FCOMPN                              ; with the limit
    pha
    bit INTFLG
    jsr StoreNumber                         ; store it as LET does
    pla
    tsx
    sec
    sbc StackTop + ForEntry::STEP_SIGN,x    ; less the step's sign
    beq EndLoop                             ; equal: the loop is done
    lda StackTop + ForEntry::LINE,x
    sta CURLIN
    lda StackTop + ForEntry::LINE + 1,x
    sta CURLIN+1
    lda StackTop + ForEntry::TEXT_LOW,x     ; the FOR statement's end, an offset from TXTTAB
    clc
    adc TXTTAB
    sta TXTPTR
    lda StackTop + ForEntry::TEXT_HIGH,x
    adc TXTTAB+1
    ldy TXTTABB
    jsr FIXADC
    sta TXTPTR+1
    tya
    adc StackTop + ForEntry::TEXT_BANK,x
    sta TXTPTRB

;; Goes on with the statement after the `FOR`.
;; Also: NEWSGO (BB13)
ToNextStatement:
    jmp NextStatement

;; Takes the entry off the stack; after a comma, goes on with the next variable.
;;
;; The JSR to <Statements::Next::WithVariable> stands in for <NextStatement>'s return address, which <FNDFOR> passes
;; over; <WithVariable> does not return.
;; In: carry = set
;; Also: LOOPDN (BB13)
EndLoop:
    txa
    adc #FORSIZ-1                           ; FORSIZ, with the carry
    tax
    txs
    jsr CHRGOT
    cmp #','
    bne ToNextStatement
    jsr CHRGET
    jsr WithVariable
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Type checks
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a numeric formula.
;; In: TXTPTR = the formula's first character
;; Out: FAC = the value
;; Errors: TYPE MISMATCH for a string or a long integer
;; See: <DOPAR>, <RequireNumber>
;; Also: FRMNUM (BB13)
.proc EvaluateNumber
    lda #VALUE_TYPE_REAL
    sta VALTYP                              ; a real wanted
    jsr DOPAR
    ; Falls into RequireNumber.
.endproc

;; Checks that the value is a number: a string or a long integer is a TYPE MISMATCH.
;; Errors: TYPE MISMATCH for a string or a long integer
;; Keeps: A, X, Y
;; See: <RequireString>
;; Also: CHKNUM (BB13)
.proc RequireNumber
    clc
    .byte $24                               ; BIT zero page skips RequireString's SEC
    ; Falls into RequireString, past its SEC.
.endproc

;; Checks that the value is a string: anything else is a TYPE MISMATCH.
;; Errors: TYPE MISMATCH for anything but a string
;; Keeps: A, X, Y
;; Entry:
;;   Mismatch = ends the statement with TYPE MISMATCH
;; See: <RequireNumber>
;; Also: CHKSTR (BB13)
.proc RequireString
    sec
    bit VALTYP
    bmi IsString
    bvs Mismatch                            ; a long integer passes neither
    bcs Mismatch

;; Returns, for the checks.
;; Also: CHKOK (BB13)
Done:
    rts
    bvc Mismatch                            ; never reached

;; Passes a string when a string is wanted.
;; Also: DOCSTR (BB13)
IsString:
    bcs Done

;; Ends the statement with TYPE MISMATCH.
;; Also: CHKERR (BB13)
Mismatch:
    ldx #ERRTM
    jmp ERROR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The formula evaluator
;
; EvaluateExpression keeps two stacks. The verb stack, VRBSTK, holds two bytes for each pending operator: its number,
; then its left operand's type (bits 7-6) with its precedence (bits 5-0); VRBPT is the index past the top. A zero
; precedence at the bottom, or where DOPAR starts a formula in parentheses, stops operators from below. The noun stack,
; NOUNSTK, holds each pending left operand, nine bytes: FACMOB, then the eight bytes from FACEXP; NOUNPT is the index of
; the top's last byte.
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates a formula: values joined by operators, taken in order of precedence.
;;
;; The precedences, high to low: ^ (8); * / `DIV` `MOD` (6); + - (5); the relational operators (4); `AND` (3); `OR`
;; (2). A relational operator is any of the characters less-than, equals and greater-than, each at most once, combined
;; as bits: greater-than 1, equals 2, less-than 4. The routine goes on into B3EvalG.asm, which does the operator taken
;; off the verb stack and comes back to <EvaluateExpression::WithOperator>.
;; In: TXTPTR = the formula's first character, VALTYP = the type wanted (<VALUE_TYPE_ANY> for any)
;; Out: the FAC = the value, VALTYP = its type, TXTPTR = the character after the formula
;; Errors: TYPE MISMATCH when the result is not the type wanted, FORMULA TOO COMPLEX past 15 pending operators,
;;   SYNTAX ERROR for a relational operator given twice
;; Entry:
;;   KeepingStacks = keeps both stacks as they are, so a formula in parentheses (from <DOPAR>) stacks on the one outside
;;     it
;;   WithOperator = goes on with the operator in A; B3EvalG.asm comes back here after doing one
;; See: <EVAL>, <EvaluateExpression::PopOperand>
;; Also: FRMEVL (BB13)
.proc EvaluateExpression
    lda #0
    sta NAMPNT
    sta NOUNPT
    sta VRBSTK+1                            ; the bottom's zero precedence
    sta STRFLG
    sta INTFLG
    lda #2
    sta VRBPT

;; Keeps both stacks as they are, so a formula in parentheses (from <DOPAR>) stacks on the one outside it.
;; Also: FRMEVL1A (BB13)
KeepingStacks:
    lda VALTYP                              ; the type wanted, checked at the end
    pha
    jsr DECTPT                              ; back one, for EVAL's CHRGET

;; Takes a value, then the operator after it: a character of <OPTAB>, or an escape token's second byte; anything else
;; ends the formula.
;; Also: FRMEVL1 (BB13)
NextOperand:
    jsr EVAL

;; The return address <EvaluateExpression::NextOperand>'s JSR pushes, which <RESTNAM> checks for after a function.
;; Also: EVALRET (BB13)
OperandReturn = * - 1
    jsr CHRGOT
    ldy #0
    ldx #NUMOPS
    cmp #FIRST_TOKEN
    bcc FindOperator                        ; a character
    cmp #ESCAPE_TOKEN
    bne NoOperator                          ; another token: not an operator
    iny
    lda (TXTPTR),y                          ; the escape token's second byte

;; Looks the operator up in <OPTAB>, from its end.
;; Also: FNDOPR (BB13)
FindOperator:
    cmp OPTAB-1,x
    beq FoundOperator
    dex
    bne FindOperator

;; Takes the end of the formula as the operator.
;; Also: NOOPR (BB13)
NoOperator:
    ldx #NUMOPS
    dey

;; Moves past the escape token's first byte, and gathers the relational operators into <DOMASK>.
;; In: X = the operator's place in <OPTAB>, Y = 1 for an escape token
;; Also: FOUNDOP (BB13)
FoundOperator:
    pha
    clc
    txa
    adc #RELNOT                             ; past the combined relational operators' numbers
    tax
    pla
    dey
    bmi CheckRelation
    jsr CHRGET                              ; the escape token's first byte

;; Takes a relational operator's characters, or goes on with another operator.
;; Also: FOP2 (BB13)
CheckRelation:
    cpx #RELOPS+1
    bcs ComparePrecedence
    ldx #0
    stx DOMASK

;; Adds a relational character's bit to <DOMASK>; the same one twice is a syntax error.
;; Also: GTRLOP (BB13)
NextRelation:
    cmp #'>'+1
    bcs EndRelations
    cmp #'<'
    bcc EndRelations
    eor #$3F                                ; > 1, = 2, < 3
    cmp #3
    adc #0                                  ; and < 4
    eor DOMASK
    cmp DOMASK                              ; the bit must be new
    bcc ToSyntaxError
    sta DOMASK
    jsr CHRGET
    jmp NextRelation

;; Ends the relational operator: its bits are its number.
;; Also: NOGTRL (BB13)
EndRelations:
    jsr DECTPT
    lda DOMASK

;; Goes on with the operator in A; B3EvalG.asm comes back here after doing one.
;; Also: FRMEVLZ (BB13)
WithOperator:
    tax

;; Does the pending operator first when its precedence is at least the new one's; otherwise pushes the new one and its
;; left operand, and takes the next value.
;; In: X = the operator's number
;; Also: NOTREL (BB13)
ComparePrecedence:
    ldy VRBPT
    lda VRBSTK-1,y
    and #PRECEDENCE_BITS                    ; the pending operator's precedence
    cmp PRECTB-1,x
    bcs PopOperand
    lda VALTYP
    and #TYPE_BITS
    ora PRECTB-1,x
    sta VRBSTK+1,y                          ; type and precedence
    txa
    sta VRBSTK,y                            ; the operator
    iny
    iny
    cmp #ENDOP
    bne KeepVerbTop
    lda VRBSTK-3,y                          ; the formula's end over the bottom's zero: done
    beq CheckResultType

;; Keeps the verb stack's new top, unless it has grown too deep.
;; Also: NT1 (BB13)
KeepVerbTop:
    sty VRBPT
    cpy #VERB_STACK_SIZE
    bcc PushOperand
    jmp CMPLXERR

;; Pushes the <FAC> on the noun stack, nine bytes.
;; Also: STKOK (BB13)
PushOperand:
    lda NOUNPT
    adc #NOUN_SIZE                          ; carry is clear
    sta NOUNPT
    tay
    ldx #NOUN_SIZE-2

;; Copies the <FAC>'s eight bytes, then <FACMOB> under them.
;; Also: PSHFAC (BB13)
PushFacByte:
    lda FACEXP,x
    sta NOUNSTK-1,y
    dey
    dex
    bpl PushFacByte
    lda FACMOB
    sta NOUNSTK-1,y
    jmp NextOperand

;; Ends the statement with a syntax error.
;; Also: SNERR5 (BB13)
ToSyntaxError:
    jmp SNERR

;; Ends the formula, checking its type against the one wanted.
;; Also: EXPRDN2 (BB13)
CheckResultType:
    pla                                     ; the type wanted
    cmp #VALUE_TYPE_ANY
    beq Return                              ; any
    eor VALTYP
    bne ToTypeMismatch

;; Returns, for <EvaluateExpression>.
;; Also: EXPRDN3 (BB13)
Return:
    rts

;; Does the pending operator: pulls its left operand off the noun stack into <ARG> and the operator off the verb stack,
;; checking that the two operands' types agree; B3EvalG.asm goes on to do it.
;; In: X = the new operator, carry = set
;; Errors: TYPE MISMATCH when the operands' types differ
;; Also: DOLAST (BB13)
PopOperand:
    txa
    pha                                     ; the new operator, for later
    lda NOUNPT
    tay
    sbc #NOUN_SIZE
    sta NOUNPT
    ldx #NOUN_SIZE-1

;; Copies the eight bytes into <ARG>, then <FACMOB>'s byte into <ARGMOB>.
;; Also: PLLARG (BB13)
PullArgByte:
    lda NOUNSTK-1,y
    sta ARG-1,x
    dey
    dex
    bne PullArgByte
    lda NOUNSTK-1,y
    sta ARGMOB
    ldy VRBPT
    dey
    dey
    sty VRBPT
    lda VRBSTK+1,y
    and #TYPE_BITS                          ; the left operand's type
    sta TEMP
    lda VALTYP
    and #TYPE_BITS
    eor TEMP
    beq TakeOperator

;; Ends the statement with TYPE MISMATCH.
;; Also: CANTFIX (BB13)
ToTypeMismatch:
    jmp RequireString::Mismatch

;; Takes the operator's number into A and <DOMASK>, for B3EvalG.asm's dispatch.
;; Also: GETOP (BB13)
TakeOperator:
    lda VRBSTK,y
    sta DOMASK
    ; Falls into the operator's dispatch, at the start of B3EvalG.asm.

;; The bits of a verb stack entry's second byte that hold the operator's precedence.
PRECEDENCE_BITS = $3F

;; The bits of a verb stack entry's second byte that hold the left operand's type, as <VALTYP>'s bits 7 and 6.
TYPE_BITS = $C0

;; The verb stack's size, two bytes for each of 15 pending operators and the bottom's entry.
VERB_STACK_SIZE = $20

;; The bytes of a noun stack entry: <FACMOB>, then the eight bytes from <FACEXP>.
NOUN_SIZE = 9
.endproc
