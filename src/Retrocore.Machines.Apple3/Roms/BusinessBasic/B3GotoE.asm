; retrocore: style=strict
;; B3GOTOE: `GOSUB`, `GOTO`, `RETURN` and `POP`, `ON ... GOTO` and `ON ... GOSUB`, the skips for `DATA` and `REM`,
;; <ReadLineNumber>, `LET` with its string assignment, and `PRINT` with the output routines under it:
;; <PrintCharacter>, <PrintText>, <PrintNewline>, and <Lister::WrapCharacter>, `LIST`'s output with its wrap.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; GOSUB, GOTO and RETURN
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; GOSUB, GOTO, DATA and RETURN.

;; The `GOSUB` statement: puts a <GoSubEntry> on the stack, then goes to the line as `GOTO` does.
;;
;; The entry, from <PushGoSubEntry>, holds <TXTPTR> after the line number, where `RETURN` goes on, and the current
;; <CURLIN>. It goes under <ExecuteStatement::StatementReturn>, the return address to <NextStatement>.
;; In: A = the character after `GOSUB`, flags as <CHRGOT> sets them
;; Entry:
;;   Transfer = goes to the line whose number is at <TXTPTR>, returning to <NextStatement> to run it; `RUN n` comes here
;; See: <Statements::Return>, <Statements::GoTo>
;; Also: GOSUB (BB13)
.proc GoSub
    jsr SaveTextPointer                     ; TXTPTR at the line number
    jsr CHRGOT
    jsr ReadLineNumber                      ; pass the number
    jsr PushGoSubEntry
    jsr RestoreTextPointer                  ; back to the number, for GOTO

;; Goes to the line whose number is at <TXTPTR>, returning to <NextStatement> to run it.
;; Also: RUNC2 (BB13)
Transfer:
    jsr CHRGOT
    jsr Statements::GoTo
    rts
.endproc

;; The `GOTO` statement: points <TXTPTR> at the zero before the line with the number given, so <NextStatement> runs it.
;;
;; When more follows the number, `GOTO` does nothing and <NextStatement> gives the syntax error.
;; In: A = the character after `GOTO`, flags as <CHRGOT> sets them
;; Errors: UNDEF'D STATEMENT when there is no such line
;; Entry:
;;   ToLineNumber = finds the line numbered <LINNUM> and points <TXTPTR> at the zero before its link; `ON`,
;;     `PRINT USING`'s image line and the table of routines for invokable modules come here
;;   SearchFromStart = searches from the program's first line; <FRUN> comes here to start a program at a line
;; See: <FNDLNC0>
;; Also: GOTO (BB13)
.proc GoTo
    jsr ReadLineNumber
    jsr CHRGOT
    bne PushGoSubEntry::Done

;; Finds the line numbered <LINNUM> and points <TXTPTR> at the zero before its link.
;;
;; A line after the current one is looked for from the next line on; any other, from the program's start (always, in
;; a direct line, whose <CURLIN> is $FFxx).
;; In: LINNUM = the line number, TXTPTR = in the current line
;; Uses: A, X, Y, LOWTR
;; Also: GOTOB (BB13)
ToLineNumber:
    jsr FindLineEnd                         ; Y = the end of the line
    lda CURLIN
    cmp LINNUM
    lda CURLIN+1
    sbc LINNUM+1
    bcs SearchFromStart                     ; not later than this line: from the start
    tya                                     ; the next line's link: TXTPTR + Y + 1
    ldy TXTPTRB
    sec
    adc TXTPTR
    ldx TXTPTR+1
    bcc Search
    inx
    cpx #MAXPG
    bcc Search
    iny                                     ; page $82 is the next bank's page $02
    ldx #MINPG
    bne Search
    bcs Search                              ; never reached

;; Searches from the program's first line.
;; Also: LUK4IT (BB13)
SearchFromStart:
    lda TXTTAB
    ldx TXTTAB+1
    ldy TXTTABB

;; Searches from the line at A, X, Y (low, high, bank), then points <TXTPTR> one byte before the line found.
;; Also: LUKALL (BB13)
Search:
    jsr FNDLNC0
    bcc Statements::Return::UndefinedStatement ; no such line
    lda LOWTR
    sbc #1
    sta TXTPTR
    lda LOWTR+1
    sbc #0
    ldy LOWTRB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc #0
    sta TXTPTRB

;; Returns, for the statements here.
;; Also: GORTS (BB13)
Done:
    rts
.endproc

;; The `DATA` statement: in a program, passes over the statement as `REM` does; in a direct line, an error.
;; Errors: ILLEGAL DIRECT in a direct line
;; Also: DATAIS (BB13)
.proc Data
    jsr ERRDIR
    bne Statements::Rem                     ; always
.endproc

;; The `RETURN` statement, and `POP`: takes the newest <GoSubEntry> off the stack, with any `FOR` entries above it.
;;
;; `RETURN` goes on from the entry's text pointer, after the `GOSUB`, on its line; `POP` goes on after itself. Both
;; share this handler, and Y, <DispatchStatement>'s index into <STMDSP>, tells them apart.
;; In: Y = the statement's index in <STMDSP>, times two, zero = set for a terminator
;; Errors: RETURN WITHOUT GOSUB when no `GOSUB` entry is under the `FOR` entries
;; Entry:
;;   UndefinedStatement = ends the statement with UNDEF'D STATEMENT; <Statements::GoTo> branches here
;; See: <Statements::GoSub>, <PushGoSubEntry>, <FNDFOR>
;; Also: RETURN (BB13)
.proc Return
    bne Statements::GoTo::Done              ; more follows: NextStatement gives the syntax error
    lda #$FF
    sta TEMPFOR                             ; matches no FOR entry
    jsr FNDFOR
    cmp #GOSUTK
    beq RestoreCaller
    ldx #ERRRG
    .byte $2C                               ; BIT absolute skips the next LDX

;; Ends the statement with UNDEF'D STATEMENT.
;; Also: USERR (BB13)
UndefinedStatement:
    ldx #ERRUS
    jmp ERROR

;; Takes the entry off: the stack is cut to it, which drops <NextStatement>'s return address and the `FOR` entries, and
;; `RETURN`'s <CURLIN> and <TXTPTR> come from it.
;; In: X = the entry's place on the stack
;; Also: RETU1 (BB13)
RestoreCaller:
    txs
    pla                                     ; GOSUTK
    pla                                     ; the line number's low byte
    cpy #<(POPTKN*2)
    beq Statements::PopFinish
    sta CURLIN
    pla
    sta CURLIN+1
    pla
    sta TXTPTRB                             ; the offset's bank
    clc
    pla
    tay                                     ; its high byte
    pla                                     ; its low byte
    adc TXTTAB
    sta TXTPTR
    tya
    adc TXTTAB+1
    ldy TXTTABB
    jsr FIXADC
    sta TXTPTR+1
    tya
    adc TXTPTRB
    sta TXTPTRB
    jmp NextStatement::SavePlace
.endproc

.endscope

;; Moves <TXTPTR> to the end of the statement: a colon or the line's zero, outside quotes.
;; Out: A = the terminator
;; See: <FindStatementEnd>, <AdvanceTextPointer>
;; Also: DATA (BB13)
.proc SkipStatement
    jsr FindStatementEnd
    ; Falls into AdvanceTextPointer.
.endproc

;; Adds Y to <TXTPTR>, into the next bank past <MAXPG>.
;; In: Y = the count to add
;; Entry:
;;   Done = returns; a statement returns from here to <NextStatement>
;;   ToSyntaxError = ends the statement with a syntax error; `ON` branches here
;; Also: ADDON (BB13)
.proc AdvanceTextPointer
    tya
    clc
    adc TXTPTR
    sta TXTPTR
    bcc Done
    lda TXTPTR+1
    adc #0
    ldy TXTPTRB
    jsr FIXADC
    sty TXTPTRB
    sta TXTPTR+1

;; Returns, for the skips; a statement returns from here to <NextStatement>.
;; Also: REMRTS (BB13)
Done:
    rts

;; Ends the statement with a syntax error.
;; Also: SNERR2 (BB13)
ToSyntaxError:
    jmp SNERR
.endproc

.scope Statements continued
; REM.

;; The `REM` statement: moves <TXTPTR> to the end of the line.
;; Also: REM (BB13)
.proc Rem
    jsr FindLineEnd
    beq AdvanceTextPointer                  ; always
.endproc

.endscope

;; Finds the end of the statement: a colon or a zero, outside quotes.
;; In: TXTPTR = where to start
;; Out: Y = the terminator's index from TXTPTR, A = the terminator, zero = set
;; Uses: X, CHARAC, ENDCHR
;; See: <FindLineEnd>
;; Also: DATAN (BB13)
.proc FindStatementEnd
    ldx #':'
    .byte $2C                               ; BIT absolute skips FindLineEnd's LDX
    ; Falls into FindLineEnd.
.endproc

;; Finds the end of the line: its zero.
;;
;; <CHARAC> and <ENDCHR> hold the two characters that end the scan besides the zero; a quote swaps them, so inside
;; quotes only the zero ends it.
;; In: TXTPTR = where to start
;; Out: Y = the zero's index from TXTPTR, A = 0, zero = set
;; Uses: X, CHARAC, ENDCHR
;; See: <FindStatementEnd>
;; Also: REMN (BB13)
.proc FindLineEnd
    ldx #0
    stx CHARAC
    ldy #0
    sty ENDCHR

;; Swaps the end characters, at the start and at each quote.
;; Also: EXCHQT (BB13)
SwapDelimiters:
    lda ENDCHR
    ldx CHARAC
    sta CHARAC
    stx ENDCHR

;; Scans for a zero or <ENDCHR>, swapping at each quote.
;; Also: REMER (BB13)
NextCharacter:
    lda (TXTPTR),y
    beq AdvanceTextPointer::Done
    cmp ENDCHR
    beq AdvanceTextPointer::Done
    iny
    cmp #'"'
    bne NextCharacter
    beq SwapDelimiters
.endproc

.scope Statements continued
; POP and ON.

;; Ends `POP`: drops the rest of the <GoSubEntry> and goes on after `POP`.
;; Also: DOPOP (BB13)
.proc PopFinish
    pla
    pla
    pla
    pla
    jmp NextStatement
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; ON ... GOTO and ON ... GOSUB
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON` statement: `ON ERR`, `ON KBD` and `ON EOF#` go to their own handlers; otherwise `ON n GOTO` or
;; `ON n GOSUB` goes to the nth line of the list.
;;
;; An n of 0, or past the list's end, goes on with the next statement.
;; In: A = the character after `ON`, flags as <CHRGOT> sets them
;; Entry:
;;   RequireGoto = ends the statement with a syntax error unless A is `GOTO`'s token; <ReadLineNumber> branches here
;;   Done = returns; <ReadLineNumber> branches here
;; See: <ONERR>, <ONKBD>, <ONEOF>
;; Also: ONGOTO (BB13)
.proc On
    cmp #ERRTK
    beq ToOnError
    cmp #KBDTK
    beq ToOnKeyboard
    cmp #EOFTK
    bne ReadIndex
    jmp ONEOF

;; Reads n and the `GOTO` or `GOSUB` after it.
;; Also: ONGOTO2 (BB13)
ReadIndex:
    jsr GETBYT                              ; n into FACLO
    pha                                     ; the token after it
    cmp #GOSUTK
    beq NextEntry

;; Ends the statement with a syntax error unless A is `GOTO`'s token.
;; Also: SNERR3 (BB13)
RequireGoto:
    cmp #GOTOTK
    bne AdvanceTextPointer::ToSyntaxError

;; Counts n down, passing a line number for each step; at zero, goes to the line that follows.
;; Also: ONGLOP (BB13)
NextEntry:
    dec FACLO
    bne SkipEntry
    pla
    cmp #GOSUTK
    bne GoToEntry
    jsr SaveTextPointer
    jsr SkipStatement                       ; GOSUB's entry goes on after the statement
    jsr PushGoSubEntry
    jsr RestoreTextPointer
    jsr GoToEntry
    rts

;; Reads the line number after <TXTPTR> and goes to it through <Statements::GoTo::ToLineNumber>.
;; Also: DOONGT (BB13)
GoToEntry:
    jsr CHRGET                              ; the token or the comma
    jsr ReadLineNumber
    jmp Statements::GoTo::ToLineNumber

;; Passes a line number of the list, and goes on at a comma; at the list's end, `ON` does nothing.
;; Also: ONGLP1 (BB13)
SkipEntry:
    jsr CHRGET
    jsr ReadLineNumber
    cmp #','
    beq NextEntry
    pla

;; Returns, for `ON` and <ReadLineNumber>.
;; Also: ONGRTS (BB13)
Done:
    rts

;; `ON ERR`.
;; Also: GOERR (BB13)
ToOnError:
    jmp ONERR

;; `ON KBD`.
;; Also: GOKBD (BB13)
ToOnKeyboard:
    jmp ONKBD
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Line numbers
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a line number, 0 to 63999, from the text into <LINNUM>; with no digit there, LINNUM is 0.
;;
;; A number of 64000 or more is a syntax error through <Statements::On::RequireGoto>, which compares A, the high byte
;; so far, with `GOTO`'s token: when that byte is $BA, as for a number whose first five digits are 47616 to 47871, the
;; error is missed, and the code goes on in `ON`'s loop, counting down <FACLO> and pulling a byte `ON` never pushed.
;; In: A = the character at TXTPTR, carry = clear for a digit, as <CHRGOT> leaves them
;; Out: LINNUM = the number, TXTPTR = the character after it, A = that character, flags as <CHRGET> sets them
;; Errors: SYNTAX ERROR for 64000 or more
;; Uses: X, CHARAC, INDEX
;; Also: LINGET (BB13)
.proc ReadLineNumber
    ldx #0
    stx LINNUM
    stx LINNUM+1

;; Adds a digit to <LINNUM>, unless the character is not a digit.
;; Also: MORLIN (BB13)
NextDigit:
    bcs Statements::On::Done
    sbc #'0'-1                              ; carry is clear
    sta CHARAC
    lda LINNUM+1
    sta INDEX
    cmp #TENTH_LIMIT_HIGH                   ; 6400 or more would pass 63999
    bcs Statements::On::RequireGoto
    lda LINNUM                              ; LINNUM times 10: times 4, plus itself, times 2
    asl a
    rol INDEX
    asl a
    rol INDEX
    adc LINNUM
    sta LINNUM
    lda INDEX
    adc LINNUM+1
    sta LINNUM+1
    asl LINNUM
    rol LINNUM+1
    lda LINNUM
    adc CHARAC
    sta LINNUM
    bcc NextCharacter
    inc LINNUM+1

;; Reads the next character.
;; Also: NXTLGC (BB13)
NextCharacter:
    jsr CHRGET
    jmp NextDigit

;; The high byte of 6400: a line number of 6400 or more, times ten, passes 63999.
TENTH_LIMIT_HIGH = 25
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; LET
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; LET.

;; The `LET` statement, and any statement without a keyword: evaluates the formula after `=` and assigns it.
;; In: TXTPTR = before the variable's name
;; Errors: TYPE MISMATCH, from <EvaluateExpression>, when the formula's type is not the variable's
;; See: <AssignFac>, <AssignString>
;; Also: LET (BB13)
.proc Let
    jsr MYPTRGET                            ; the variable's address in FORPNT
    jsr CHKEQL
    lda INTFLG
    pha
    lda ISARA
    pha
    jsr EvaluateExpression
    jmp AssignFac::ByType
.endproc

.endscope

;; Assigns the value in the <FAC> to the variable at <FORPNT>, as `LET` does; the disk statements and `INPUT` use it.
;; In: FORPNT, FORPNTB = the variable, <VALTYP>, <INTFLG>, ISARA = its type, the FAC = the value
;; Entry:
;;   ByType = takes <ISARA> and <INTFLG> back off the stack; `LET` comes here with them pushed
;; Also: LETP2 (BB13)
.proc AssignFac
    lda INTFLG
    pha
    lda ISARA
    pha

;; Assigns by the value's type: a string through <AssignString>, a long integer through <StoreLongInteger>, a real or
;; an integer through <StoreNumber>, taking <ISARA> and <INTFLG> back off the stack.
;; Also: LETP3 (BB13)
ByType:
    pla
    sta ISARA
    bit VALTYP
    bmi Statements::LetString               ; a string
    bvs Statements::LetLongInteger          ; a long integer
    pla
    sta INTFLG
    ; Falls into StoreNumber.
.endproc

;; Stores the <FAC> in the variable at <FORPNT>: a real as it is, an integer rounded to two bytes, high byte first.
;; In: negative = set for an integer, as <INTFLG> sets it
;; Also: QINTGR (BB13)
.proc StoreNumber
    bpl ToPackFac
    jsr ROUND
    jsr AYINT
    ldy #0
    lda FACMO
    sta (FORPNT),y
    iny
    lda FACLO
    sta (FORPNT),y
    rts

;; Stores the <FAC> as a real, through <MOVVF>.
;; Also: COPFLT (BB13)
ToPackFac:
    jmp MOVVF
.endproc

.scope Statements continued
; LET's long integers and strings.

;; Stores a long integer, dropping <INTFLG> from the stack.
;; Also: BMOVVF (BB13)
.proc LetLongInteger
    pla
    ; Falls into StoreLongInteger.
.endproc

.endscope

;; Stores the long integer in the <FAC> in the variable at <FORPNT>, through <STFACT>.
;; Also: BMOVF1 (BB13)
.proc StoreLongInteger
    ldx FORPNTB
    lda FORPNT
    ldy FORPNT+1
    jmp STFACT
.endproc

.scope Statements continued
; LET's strings.

;; Assigns a string, dropping <INTFLG> from the stack.
;; Also: COPSTR (BB13)
.proc LetString
    pla
    ; Falls into AssignString.
.endproc

.endscope

;; Assigns the string whose descriptor <FACMO> points to, to the string variable at <FORPNT>.
;;
;; A variable's string is copied to new room; a temporary's (one in BASIC's own bank, <FACMOB> zero) is taken over. The
;; variable's old string is freed, the descriptor copied in, and the string's information bytes, at <HIGHDS>, are set
;; to point back at the variable: its type (<SIMTYP> for a simple variable, <ARYTYP> for an array element) and its
;; offset from <Variables::VariableOffset>. An empty string gets no back pointer.
;; In: FACMO, FACMOB = the descriptor, <FORPNT>, FORPNTB = the variable, ISARA = negative for an array element
;; Errors: VARIABLE error when the offset does not fit in 16 bits
;; Entry:
;;   MoveCharacters = moves the string into the room <DSCPNT> gives and makes its temporary descriptor; the
;;     substring assignment, <SUBLNK1>, comes here
;;   SetBackPointer = points the string's information bytes back at its variable; `SWAP` comes here
;; Also: INPCOM (BB13)
.proc AssignString
    ldy FACMOB                              ; zero for a temporary
    bne CopyCharacters
    lda FACMO
    ldy FACMO+1
    ldx FACMOB
    jmp StoreDescriptor

;; Copies a variable's string to new room, making the copy a temporary.
;; Also: COPY (BB13)
CopyCharacters:
    ldy #0
    lda (FACMO),y                           ; the length
    jsr STRINI

;; Moves the string into the room and makes its temporary descriptor.
;; Also: COPY_M (BB13)
MoveCharacters:
    lda DSCPNT
    ldy DSCPNT+1
    ldx DSCPNTB
    sta STRNG1
    sty STRNG1+1
    stx STRNG1B
    jsr MOVINS
    jsr PUTNEW
    lda FACMO
    ldy FACMO+1
    ldx FACMOB

;; Frees the temporary descriptor (not its string) and the variable's old string, then copies the descriptor in.
;; In: A, Y, X = the descriptor (low, high, bank)
;; Also: COPY_C (BB13)
StoreDescriptor:
    sta DSCPNT
    stx DSCPNTB
    sty DSCPNT+1
    jsr FRETMS
    lda FORPNT
    ldy FORPNT+1
    ldx FORPNTB
    jsr NOTNW2                              ; the old string into INDEX
    jsr FRESPA
    ldy #STRSIZ-1

;; Copies the descriptor's three bytes into the variable.
;; Also: COPY_S (BB13)
CopyDescriptor:
    lda (DSCPNT),y
    sta (FORPNT),y
    dey
    bpl CopyDescriptor
    tax                                     ; the length
    beq Done                                ; empty: no back pointer

;; Points the string's information bytes back at its variable.
;; Also: FIXBAK (BB13)
SetBackPointer:
    jsr Variables::VariableOffset
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY                               ; the offset, packed to 16 bits
    cpy #$FF
    bcc Variables::VariableOffset::VariableError
    ldy #2
    sta (HIGHDS),y
    dey
    lda FORPNT
    sta (HIGHDS),y
    txa                                     ; ISARA, as VariableOffset leaves X
    bmi ArrayElement
    lda #SIMTYP
    .byte $2C                               ; BIT absolute skips the LDA

;; Takes an array element's type.
ArrayElement:
    lda #ARYTYP
    dey
    sta (HIGHDS),y

;; Returns, for `LET`.
;; Also: LETRTS (BB13)
Done:
    rts
.endproc

.scope Variables continued
; A variable's offset.

;; Turns the variable pointer in <FORPNT> into an offset: from <ARYTAB> for an array element, otherwise from the simple
;; variables' start through <Variables::SimpleVariableOffset>.
;;
;; An offset is the table's start less the address, so the same subtraction turns it back into the address.
;; In: ISARA = negative for an array element
;; Out: FORPNT, FORPNT+1, FORPNTB = the offset, X = ISARA
;; Errors: OUT OF MEMORY when an array element's offset passes 64K
;; Entry:
;;   ArrayElement = takes <FORPNT> as an array element's; the table of routines for invokable modules lists it
;;   VariableError = ends the statement with the VARIABLE error; <AssignString> branches here
;; See: <AssignString::SetBackPointer>
;; Also: RELPTR (BB13)
.proc VariableOffset
    ldx ISARA
    bpl Simple

;; Takes <FORPNT> as an array element's.
;; Also: RELPTR2 (BB13)
ArrayElement:
    lda ARYTAB
    sec
    sbc FORPNT
    sta FORPNT
    lda ARYTAB+1
    sbc FORPNT+1
    ldy ARYTABB
    jsr FIXSBC
    sta FORPNT+1
    tya
    sbc FORPNTB
    sta FORPNTB
    bcc Done                                ; a borrow, as there should be
    jmp OMERR

;; Makes a simple variable's offset.
;; Also: ISSIMP (BB13)
Simple:
    jsr Variables::SimpleVariableOffset

;; Returns.
;; Also: GOTRELA (BB13)
Done:
    rts

;; Ends the statement with the VARIABLE error.
;; Also: VAERR (BB13)
VariableError:
    ldx #ERRVA
    jmp ERROR
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; PRINT
; ---------------------------------------------------------------------------------------------------------------------

;; A RETURN, which ends a line of output.
RETURN_CHARACTER = $0D

;; A line feed, which follows a RETURN on the console and on devices.
LINE_FEED_CHARACTER = $0A

.scope Statements continued
; PRINT's list.

;; Prints a string, then goes on with `PRINT`'s list.
;; Also: STRDON (BB13)
.proc PrintStringItem
    jsr PrintString
    ; Falls into PrintNextItem.
.endproc

;; Goes on with `PRINT`'s list at the current character.
;; Also: NEWCHR (BB13)
.proc PrintNextItem
    jsr CHRGOT
    ; Falls into PrintList.
.endproc

;; Prints `PRINT`'s list: values, `TAB(` and `SPC(`, with commas and semicolons between; a list that does not end in a
;; comma or semicolon ends with a RETURN.
;;
;; A comma moves to the next column of 16; a semicolon prints nothing.
;; In: A = the character at <TXTPTR>, flags as <CHRGOT> sets them
;; Entry:
;;   Item = prints the rest of the list after a separator, where a terminator ends the line without a RETURN
;; See: <Statements::Print>
;; Also: PRINT (BB13)
.proc PrintList
    beq PrintNewline

;; Prints the rest of the list after a comma, a semicolon, `TAB(` or `SPC(`, where a terminator ends the line without
;; a RETURN.
;; Also: PRINTC (BB13)
Item:
    beq PrintNewline::Return
    lda #TABTK
    jsr TRYESC
    beq PrintTabOrSpace
    lda #SPCTK
    jsr TRYESC
    clc                                     ; carry clear for SPC(
    beq PrintTabOrSpace
    cmp #','
    beq PrintComma
    cmp #';'
    bne Value
    jmp PrintSpaces::ContinuePrint

;; Evaluates and prints a value of any type.
Value:
    lda #VALUE_TYPE_ANY
    sta VALTYP
    jsr EvaluateExpression
    bit VALTYP
    bmi Statements::PrintStringItem         ; a string
    bvc Real                                ; a real
    jsr LOUT                                ; a long integer, as text in NUMSTR
    lda #<(NUMSTR)
    sta INDEX
    lda #>(NUMSTR)
    sta INDEX+1
    lda #NUMSTRB
    sta INDEXB
    ldx LENUM
    jsr Output::WriteString
    beq Statements::PrintNextItem           ; always

;; Prints a real, through <FOUT>'s text.
;; Also: ISBIN (BB13)
Real:
    jsr FOUT
    jsr STRLIT
    jmp Statements::PrintStringItem
.endproc

.endscope

;; Ends the output line: a RETURN, then a line feed when the output goes to the console or another device rather than
;; a disk file; <TRMPOS> goes back to 0.
;; Uses: A, TEMP, KIMY
;; Entry:
;;   Return = returns; `PRINT`'s list branches here
;; Also: CRDO (BB13)
.proc PrintNewline
    lda #RETURN_CHARACTER
    jsr PrintCharacter
    stx TEMP
    sty KIMY
    ldx FILNO
    bmi LineFeed                            ; the console
    jsr GTFLNO1
    lda FCB+XRFNM,y                         ; the reference number: bit 7 set for a device
    bpl ResetColumn                         ; a disk file: no line feed

;; Prints the line feed.
;; Also: DOLF (BB13)
LineFeed:
    lda #LINE_FEED_CHARACTER
    jsr PrintCharacter

;; Sets the column back to 0 and takes X and Y back.
;; Also: DOLFRT (BB13)
ResetColumn:
    ldx #0
    stx TRMPOS
    ldx TEMP
    ldy KIMY

;; Returns, for `PRINT`.
;; Also: PRTRTS (BB13)
Return:
    rts
.endproc

.scope Output
; The output routines Business BASIC adds to Microsoft's.

;; Frees the string just printed, if it was one.
;; In: VALTYP = the printed value's type
;; Also: PRTRTS1 (BB13)
.proc FreePrintedString
    bit VALTYP
    bpl PrintNewline::Return
    jmp FRECNOW
.endproc

.endscope

;; Moves to the next column of 16, past the current one.
;; In: carry = set, as the comma's compare leaves it
;; Also: COMPRT (BB13)
.proc PrintComma
    lda TRMPOS
    adc #COMMA_ZONE-1
    and #<(-COMMA_ZONE)
    ; A check against the window's width is left out here.
    sec
    sbc TRMPOS
    tax
    jmp PrintSpaces::One

;; The width of the zones a comma moves between.
COMMA_ZONE = 16
.endproc

;; Does `TAB(n)`, which moves to column n (1 first) when the output is short of it, or `SPC(n)`, which prints n spaces.
;; In: carry = set for `TAB(`, clear for `SPC(`
;; Errors: ILLEGAL QUANTITY for `TAB(0)`
;; Also: TABER (BB13)
.proc PrintTabOrSpace
    php
    jsr GTBYTC                              ; n into X
    stx TEMP
    jsr CHKCLS
    jsr DECTPT                              ; back one, for ContinuePrint's CHRGET
    plp
    ldx TEMP
    bcc PrintSpaces                         ; SPC(
    bne NotZero
    jmp TOOBIG

;; Works out the spaces to the column.
NotZero:
    dex
    txa
    sbc TRMPOS
    bcc PrintSpaces::ContinuePrint          ; already past it
    tax
    ; Falls into PrintSpaces.
.endproc

;; Prints X spaces, then goes on with `PRINT`'s list.
;; In: X = the count of spaces
;; Entry:
;;   ContinuePrint = goes on with the list after its separator
;;   One = prints a space and counts it; <PrintComma> comes here
;; Also: XSPAC (BB13)
.proc PrintSpaces
    inx

;; Counts the spaces down.
;; Also: XSPAC2 (BB13)
Next:
    dex
    bne One

;; Goes on with the list after its separator.
;; Also: NOTABR (BB13)
ContinuePrint:
    jsr CHRGET
    jmp Statements::PrintList::Item

;; Prints a space and counts it.
;; Also: XSPAC1 (BB13)
One:
    jsr PrintSpace
    bne Next
.endproc

;; Prints a string that ends in a zero, making a temporary for it.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <Output::PrintTextDirect>
;; Also: STROUT (BB13)
.proc PrintText
    jsr STRLIT
    ; Falls into PrintString.
.endproc

;; Prints the string whose descriptor <FACMO> points to, then frees it if it is a temporary.
;; Also: STRPRT (BB13)
.proc PrintString
    jsr NOTFAC
    tax
    ; Falls into Output::WriteString.
.endproc

.scope Output continued
; Writing a string.

;; Prints X characters from <INDEX>, to the console or the output file, with one SOS WRITE through <SINIT>.
;;
;; <SINIT>'s reference number is the console's; for a file, the file's goes in for the call and the console's comes
;; back. The WRITE's buffer address is <INDEX> itself, a zero-page pointer, which SOS reads with its X-byte.
;; In: X = the length, INDEX = the string, with its X-byte, VALTYP = negative for a string to free afterwards
;; Also: STRPR3 (BB13)
.proc WriteString
    stx OUTSTRL
    txa
    beq Finish
    ldy SINIT+1                             ; the console's reference number
    bit FILNO
    bmi Write                               ; the console
    pha
    ldx FILNO
    jsr GTFLNO1
    jsr PRETXT
    jsr TSTOUT
    lda FCB+XRFNM,y                         ; the file's reference number
    ldy SINIT+1
    sta SINIT+1
    pla

;; Counts the characters into <TRMPOS> and makes the WRITE.
;; Also: GOOUT (BB13)
Write:
    clc
    adc TRMPOS
    sta TRMPOS
    lda #<(INDEX)
    sta SPRNTPL
    lda #>(INDEX)
    sta SPRNTPL+1
    brk
    .byte SWRT
    .word SINIT
    sty SINIT+1                             ; the console's reference number back
    bne PrintCharacter::WriteError

;; Frees the string, if it was one.
;; Also: STRPR4 (BB13)
Finish:
    jmp Output::FreePrintedString
.endproc

.endscope

;; Prints a space.
;; See: <PrintCharacter>
;; Also: OUTSPC (BB13)
.proc PrintSpace
    lda #' '
    .byte $2C                               ; BIT absolute skips the next LDA
    ; Falls into PrintQuestionMark.
.endproc

;; Prints a question mark.
;; See: <PrintCharacter>
;; Also: OUTQST (BB13)
.proc PrintQuestionMark
    lda #'?'
    ; Falls into PrintCharacter.
.endproc

;; Prints the character in A, to the console or the output file, and counts it in <TRMPOS>.
;;
;; A file's character goes out with a one-byte SOS WRITE through <SCHRTB>, with the file's reference number put in for
;; the call.
;; In: A = the character, FILNO = the output file, negative for the console
;; Out: A = the character
;; Entry:
;;   WriteError = ends the statement with the WRITE's error; <Output::WriteString> branches here
;; See: <PRNACHAR>
;; Also: OUTDO (BB13)
.proc PrintCharacter
    inc TRMPOS
    bit FILNO
    bmi Send                                ; the console
    sta OUTCHAR
    txa
    pha
    tya
    pha
    lda #WRITE_PARAMETER_COUNT
    sta SCHRTB
    ldx FILNO
    jsr GTFLNO1
    jsr PRETXT
    jsr TSTOUT
    lda FCB+XRFNM,y
    ldy SCHRTB+1
    sta SCHRTB+1
    brk
    .byte SWRT
    .word SCHRTB
    sty SCHRTB+1
    bne WriteError
    pla
    tay
    pla
    tax
    lda OUTCHAR
    rts

;; Ends the statement with the WRITE's error.
;; Also: OTDOER (BB13)
WriteError:
    jmp SERROR

;; Prints the character on the console.
;; Also: OUTLOC (BB13)
Send:
    jmp PRNACHAR

;; The count of SOS WRITE's parameters, the first byte of its parameter list.
WRITE_PARAMETER_COUNT = 3
.endproc

.scope Statements continued
; PRINT.

;; The `PRINT` statement: `PRINT# n;` to a file, `PRINT USING`, or `PRINT` to the console.
;;
;; For the console, the cursor's column is read first, so commas and `TAB(` count from where the cursor is.
;; In: A = the character after `PRINT`, flags as <CHRGOT> sets them
;; See: <Statements::PrintList>, <PRUSING>
;; Also: DOPRINT (BB13)
.proc Print
    cmp #'#'
    bne ReadColumn
    lsr IOFLG
    jsr FILNUM
    lda SVFLNO
    sta FILNO
    jsr CHRGOT
    beq List                                ; nothing more
    cmp #';'
    bne CheckUsing
    jsr SYNCHR

;; Takes `PRINT USING`, or the plain list.
;; Also: GPRNT (BB13)
CheckUsing:
    lda #USINGTK
    jsr TRYESC
    bne List
    jsr PRUSING
    rts

;; Prints the list.
;; Also: GPR3 (BB13)
List:
    jsr CHRGOT
    jmp Statements::PrintList

;; Reads the cursor's column into <TRMPOS> when the output goes to the console.
;; Also: GPRNT2 (BB13)
ReadColumn:
    bit FILNO
    bpl ToCheckUsing                        ; to a file: leave TRMPOS
    jsr VPOS
    lda CURX
    sta TRMPOS

;; Goes on with `PRINT USING` or the list.
;; Also: GPR4 (BB13)
ToCheckUsing:
    jmp CheckUsing
.endproc

.endscope

.scope Output continued
; Printing text directly.

;; Prints a string that ends in a zero, as it is, without the string routines; the length must be under 256.
;; In: A, Y = the string's address (low, high), X = its bank
;; See: <PrintText>
;; Also: STROUTR (BB13)
.proc PrintTextDirect
    sta INDEX
    sty INDEX+1
    stx INDEXB
    ldy #$FF

;; Counts to the zero.
;; Also: STRLUP (BB13)
Count:
    iny
    lda (INDEX),y
    bne Count
    tya
    tax
    lda #VALUE_TYPE_REAL                    ; nothing to free
    sta VALTYP
    jmp Output::WriteString
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; LIST's output
; ---------------------------------------------------------------------------------------------------------------------

;; `LIST`'s output, which wraps a long line to the column its text started in.
.scope Lister

;; Prints a space as <Lister::WrapCharacter> does.
;; Also: ROUTSPC (BB13)
.proc WrapSpace
    lda #' '
    ; Falls into WrapCharacter.
.endproc

;; Prints a character for `LIST`, first wrapping the line when the output has reached <OUTREC>'s width.
;;
;; A wrapped line goes on after spaces to the column in <DELTA>+1, where the listed line's text started. <OUTREC> 0
;; turns the wrap off.
;; In: A = the character, DELTA+1 = the margin
;; Errors: RANGE ERROR when the margin leaves no room in the width
;; See: <Statements::List>, <PrintCharacter>
;; Also: ROUTDO (BB13)
.proc WrapCharacter
    pha
    lda OUTREC
    beq Print                               ; no wrap
    clc
    sbc TRMPOS                              ; OUTREC less TRMPOS, less one
    beq Wrap
    bcs Print                               ; room left

;; Ends the output line, to go on at the margin.
Wrap:
    jsr PrintNewline

;; Prints spaces up to the margin.
;; Also: TSTTAB (BB13)
Indent:
    jsr PrintSpace
    lda DELTA+1
    cmp TRMPOS
    bcs Indent
    cmp OUTREC
    bcc Print
    jmp RNGERR

;; Prints the character.
;; Also: ROUTDONE (BB13)
Print:
    pla
    jmp PrintCharacter
.endproc

.endscope
