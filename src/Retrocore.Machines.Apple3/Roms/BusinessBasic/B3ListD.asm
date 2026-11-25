; retrocore: style=strict
;; B3LISTD: `LIST`, which turns the program's tokens back into text; `FOR`, which puts a loop's entry on the stack; the
;; statement loop, <NextStatement>, which runs the program one statement at a time; and `RESTORE`, `STOP`, `END`,
;; `CONT`, `BYE`, `RUN` and the push of a `GOSUB` entry.
;;
;; A program line in memory is a <ProgramLine>: a one-byte link (the line's length, from this byte to the next line's
;; link), the line number (low byte, high byte), the tokenized text, and a zero. A zero link ends the program, and a
;; zero stands just before the first line, at <TXTTAB>-1. Pointers into the program carry a bank byte, their X-byte, at
;; their address plus <SYSPAG>, as <TXTPTR> does in <TXTPTRB>, and keep their page in <MINPG> to <MAXPG>-1 ($02-$81).
;; Pages $82 and up of one bank are the same memory as pages $02 and up of the next, so a pointer may run past the top
;; and still read the right byte; the code brings it back into range where a line starts.
;;
;; Apple's Business BASIC 1.3 listing (BB13) gives the names in `Also:`.

;; A program line, as it is stored in memory.
.struct ProgramLine
    ;; The line's length, from this byte to the next line's link; zero ends the program.
    LINK .byte
    NUMBER .word ;; The line number, low byte first.
    TEXT .byte ;; The first byte of the tokenized text, which ends in a zero.
.endstruct

;; A `FOR` loop's entry on the stack, from its top (the lowest address) down.
;;
;; Code reaches a field at <StackTop> plus the field, indexed by the entry's place from `TSX`.
.struct ForEntry
    ;; <FORTK>, which marks the entry as a `FOR` loop's.
    TOKEN .byte
    ;; The variable's type: bit 7 set for an integer, bit 0 for an array element (as in <TEMPFOR>).
    TYPE .byte
    ;; The variable's offset (low, high), from <Variables::VariableOffset>, packed to 16 bits by <FIXAY>.
    VARIABLE .word
    STEP .res 5 ;; The step, unpacked, as <PUSHF> pushes it.
    ;; The step's sign: 1 for positive, 0 for zero, $FF for negative.
    STEP_SIGN .byte
    ;; The limit, packed, its sign in bit 7 of the first mantissa byte.
    LIMIT .res 5
    LINE .word ;; The `FOR` statement's line number, low byte first.
    ;; The text pointer to the `FOR` statement's end, as an offset from <TXTTAB>: its bank, then its high and low bytes.
    TEXT_BANK .byte
    TEXT_HIGH .byte ;; The text offset's high byte.
    TEXT_LOW .byte ;; The text offset's low byte.
.endstruct
.assert .sizeof(ForEntry) = FORSIZ, "A FOR entry is FORSIZ bytes."

;; A `GOSUB` entry on the stack, from its top (the lowest address) down, as <PushGoSubEntry> builds it.
.struct GoSubEntry
    TOKEN .byte ;; <GOSUTK>, which marks the entry as a `GOSUB` entry.
    LINE .word ;; The line number of the `GOSUB`, low byte first.
    ;; The text pointer to where `RETURN` goes on, as an offset from <TXTTAB>: its bank, then its high and low bytes.
    TEXT_BANK .byte
    TEXT_HIGH .byte ;; The text offset's high byte.
    TEXT_LOW .byte ;; The text offset's low byte.
.endstruct

;; The first byte of an escape token, which a second byte, from <TABTK> on, follows.
ESCAPE_TOKEN = $FF

;; The lowest token, which the first word of <RESLST> or <RESL2> stands for.
FIRST_TOKEN = $80

;; The byte above the stack pointer: the stack's top byte, as code reaches it at StackTop,X after `TSX`.
StackTop = $0101

; ---------------------------------------------------------------------------------------------------------------------
; LIST
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; LIST.

;; The `LIST` statement: lists the program, or the lines in a range, turning tokens back into words.
;;
;; The range is `LIST`, `LIST n`, `LIST n-`, `LIST -m` or `LIST n-m`, where a comma or `TO` may stand for the dash.
;; Each line is printed as a space, its number, <INDENT> spaces times one more than the `FOR`s open, and its text; text
;; wraps at <OUTREC> to the column the text started in. A `FOR` adds a level for the lines after it and each variable
;; of a `NEXT` takes one away. CONTROL-C stops the listing with BREAK.
;; In: A = the character after `LIST`, flags as <CHRGOT> sets them
;; Uses: A, X, Y, LINNUM, LOWTR, VARNAM, DELTA, FAC, FORPNT, INPFLG
;; See: <Lister::WrapCharacter>, <Statements::List::CheckToken>, <FNDLIN>
;; Also: LIST (BB13)
.proc List
    php                                     ; zero set: nothing follows LIST
    ldx #0
    stx DELTA                               ; no FOR open yet
    jsr ReadLineNumber                      ; the first line's number, or 0
    jsr FNDLIN                              ; LOWTR = the first line at or after it
    plp
    bne CheckRange

;; Lists to the end of the program: sets the last line's number to $FFxx.
;; Also: LXZYQ (BB13)
ToProgramEnd:
    lda #LAST_LINE_HIGH
    sta LINNUM+1

;; Reads the rest of the range: a terminator lists the one line, a dash, comma or `TO` reads the last line's number.
;; Also: GOLS1 (BB13)
CheckRange:
    jsr CHRGOT
    beq StartListing                        ; only one number: the last is the first
    cmp #'-'
    beq ReadLastLine
    cmp #','
    beq ReadLastLine
    lda #TOTK
    jsr TRYESC
    beq ReadLastLine
    jmp SNERR

;; Reads the last line's number after the dash, comma or `TO`; nothing there lists to the end.
;; Also: LSTOK (BB13)
ReadLastLine:
    jsr CHRGET
    beq ToProgramEnd
    jsr ReadLineNumber
    jsr CHRGOT
    bne Done                                ; more after it: NextStatement gives the syntax error

;; Starts the listing at the line <FNDLIN> found, through <VARNAM>.
;; Also: LSTEND (BB13)
StartListing:
    lda LOWTR
    sta VARNAM
    lda LOWTR+1
    sta VARNAM+1
    lda LOWTRB
    sta VARNAMB

;; Lists the line at <VARNAM>, unless it is past the last line asked for or the program has ended.
;; In: VARNAM = the line's link byte, LINNUM = the last line to list
;; Also: LIST4 (BB13)
NextLine:
    ldy #ProgramLine::LINK
    lda (VARNAM),y                          ; a zero link ends the program
    beq Finish
    bit KEYSTROK                            ; CONTROL-C?
    bvc NoBreak
    jmp HandleBreak

;; Starts the line on a new output line and reads its number.
NoBreak:
    jsr PrintNewline
    iny
    lda (VARNAM),y                          ; the line number's low byte
    tax
    iny
    lda (VARNAM),y                          ; and its high byte
    cmp LINNUM+1
    bne CheckPastEnd
    cpx LINNUM
    beq ListLine

;; Ends the listing when the line's number is past the last one's.
;; In: carry = set when the line is past the last
;; Also: TSTDUN (BB13)
CheckPastEnd:
    bcs Done

;; Prints the line number and the indentation, then the text.
;; In: X, A = the line number (low, high), Y = 2
;; Also: TYPLIN (BB13)
ListLine:
    sty LSTPNT
    pha
    jsr Lister::WrapSpace                   ; a space before the number
    pla
    jsr LINPRT
    ldx INDENT
    beq SetMargin

;; Prints <DELTA>+1 spaces, once for each of <INDENT>'s spaces per level.
;; Also: PLOOP1 (BB13)
IndentLevel:
    ldy DELTA

;; Prints one space of the level's indentation.
;; Also: PLOOP0 (BB13)
IndentSpace:
    jsr PrintSpace
    dey
    bpl IndentSpace
    dex
    bne IndentLevel

;; Notes the column the text starts in, as the margin for wrapped text.
;;
;; A still holds what the output left, which <Statements::List::CheckQuote> prints: a space after the indentation, or,
;; with no indentation, the 0 that SOS's WRITE left after the line number.
;; Also: PLOOP3 (BB13)
SetMargin:
    ldy TRMPOS                              ; the margin for Lister::WrapCharacter's wrap
    sty DELTA+1
    ldy LSTPNT

;; Prints a character of the line, or starts a quoted string at a quote.
;; In: A = the character, Y = its index in the line
;; Also: PLOOP5 (BB13)
CheckQuote:
    cmp #'"'
    beq QuotedString

;; Prints a character of the line.
;; Also: PLOOP (BB13)
ListCharacter:
    jsr Lister::WrapCharacter

;; Takes the line's next byte: a zero ends the line.
;; Also: PLOOP2 (BB13)
NextByte:
    iny
    lda (VARNAM),y
    bne CheckToken                          ; not the end: a character or a token

;; Moves <VARNAM> past the line's zero to the next line's link, into the next bank past <MAXPG>, and lists it.
;; Also: PLOOP8 (BB13)
NextLineLink:
    sec                                     ; the zero's index, plus one
    tya
    adc VARNAM
    sta VARNAM
    bcc NextLine
    ldx VARNAM+1
    inx
    cpx #MAXPG
    bcc StorePage
    ldx #MINPG                              ; page $82 is the next bank's page $02
    inc VARNAMB

;; Stores the link's page and lists the line.
StorePage:
    stx VARNAM+1
    jmp NextLine

;; Reads the next byte of a reserved-word list, through the pointer in <FAC>.
;;
;; The lists lie in BASIC's own bank, so the page can go up without the bank.
;; In: Y = the index of the byte before
;; Out: A = the byte, negative = set for a word's last character
;; Also: GETNXTW (BB13)
NextTableByte:
    iny
    bne ReadTableByte
    inc FAC+1

;; Reads the byte at Y.
ReadTableByte:
    lda (FAC),y

;; Returns, for the listing's branches.
;; Also: LSTRTS (BB13)
Done:
    rts

;; Ends the listing with a RETURN.
;; Also: GREEDY (BB13)
Finish:
    jmp PrintNewline

;; Prints a quoted string as it is, up to its closing quote or the end of the line.
;; Also: PLOOP7 (BB13)
QuotedString:
    jsr Lister::WrapCharacter
    iny
    lda (VARNAM),y
    beq NextLineLink
    cmp #'"'
    bne QuotedString
    beq ListCharacter

;; Prints a character, or a token as its reserved word.
;;
;; A token is one byte, $80-$FE, for a word of <RESLST>, or <ESCAPE_TOKEN> and a second byte for a word of <RESL2>. A
;; space goes before the word unless it starts the line or follows a token or a colon (or, for an escape token, unless
;; it is a function); a space goes after a word that ends in a letter when a token, a letter, a digit or a period
;; follows. `FOR` and `NEXT` change the indentation of the lines after them in <DELTA>.
;; In: A = the byte, negative = set for a token, Y = its index in the line
;; See: <Statements::List::NextTableByte>, <CKSEP>
;; Also: QPLOP (BB13)
CheckToken:
    bpl CheckQuote                          ; a character
    cmp #FORTK
    bne CheckNext
    inc DELTA                               ; FOR: one level more

;; Checks for `NEXT`'s token.
CheckNext:
    cmp #FORTK+1                            ; NEXT?
    bne PointAtWords
    sty YSAVE

;; Takes a level away for each of `NEXT`'s variables, never below zero.
;; Also: NOTSPEC0 (BB13)
Outdent:
    dec DELTA
    bpl FindComma
    inc DELTA

;; Looks for another of `NEXT`'s variables, after a comma, up to the end of the statement.
;; Also: NOTSPEC2 (BB13)
FindComma:
    iny
    lda (VARNAM),y
    beq ReloadToken
    cmp #':'
    beq ReloadToken
    cmp #','
    beq Outdent
    bne FindComma

;; Takes `NEXT`'s token back.
;; Also: NOTSPEC3 (BB13)
ReloadToken:
    ldy YSAVE
    lda (VARNAM),y

;; Points <FAC> at the reserved words: <RESLST> for a one-byte token, <RESL2> for an escape token's second byte.
;;
;; <FAC> is set a page below the list, as <Statements::List::NextTableByte>'s first INY takes Y from $FF to 0 and
;; carries into the page.
;; Also: NOTSPEC4 (BB13)
PointAtWords:
    ldx #<(RESLST)
    stx FAC
    ldx #>(RESLST-256)
    stx FAC+1
    ldx #RESLSTB
    stx FACB
    tax
    inx                                     ; INPFLG = 0 for an escape token, negative for another
    stx INPFLG
    cmp #ESCAPE_TOKEN
    bne CountWords
    iny
    lda (VARNAM),y                          ; the escape token's second byte
    ldx #<(RESL2)
    stx FAC
    ldx #>(RESL2-256)
    stx FAC+1
    ldx #RESLSTB
    stx FACB

;; Finds the token's word in the list: the token's number, less <FIRST_TOKEN>, counts the words to pass.
;; In: A = the token, Y = the index of its last byte in the line
;; Also: NRMTKN (BB13)
CountWords:
    sec
    sbc #FIRST_TOKEN
    tax
    stx TKNSAV
    sty LSTPNT
    ldy #255                                ; NextTableByte's first INY makes it 0

;; Counts down the words to pass; at zero, the word is found.
;; Also: RESRCH (BB13)
FindWord:
    dex
    bmi SpaceBefore

;; Passes one word, up to its last character's set bit 7.
;; Also: RESCR1 (BB13)
SkipWord:
    jsr NextTableByte
    bpl SkipWord
    bmi FindWord

;; Decides whether a space goes before the word, from what comes before the token.
;;
;; A token at the line's start (<ProgramLine::TEXT>) takes none; nor does one after a colon or a token, nor an escape
;; token for a function (`SGN(` on, in <RESL2>).
;; Also: PRIT25 (BB13)
SpaceBefore:
    lda LSTPNT
    cmp #ProgramLine::TEXT                  ; the first byte of the line's text
    beq ListWord
    tya                                     ; the word's index in the list
    pha
    ldy LSTPNT
    dey
    bit INPFLG                              ; an escape token?
    bmi CheckPrevious
    dey                                     ; yes: look before its escape byte
    lda TKNSAV
    cmp #ONEFUN-FIRST_TOKEN                 ; a function: no space
    bcs SpaceUnlessCarry

;; Looks at the byte before the token: carry is set for a colon or a token.
;; Also: PRIT26 (BB13)
CheckPrevious:
    lda (VARNAM),y
    cmp #':'
    beq SpaceUnlessCarry
    asl a                                   ; bit 7 into carry: a token

;; Prints the space before the word unless carry says not to.
;; In: carry = set for no space
;; Also: PRIT27 (BB13)
SpaceUnlessCarry:
    pla
    tay
    bcs ListWord
    jsr Lister::WrapSpace

;; Prints the word, then its last character without bit 7.
;; Also: PRIT3 (BB13)
ListWord:
    jsr NextTableByte
    bmi LastCharacter
    jsr Lister::WrapCharacter
    jmp ListWord

;; Prints the word's last character, then a space when the word ends in a letter and a token, a letter, a digit or a
;; period follows.
;; Also: PRFINIS (BB13)
LastCharacter:
    and #CHARACTER_BITS
    jsr Lister::WrapCharacter
    ldy LSTPNT
    iny
    cmp #'A'                                ; ends in a symbol, as in PR# or CHR$(: no space
    bcc AfterToken
    lda (VARNAM),y
    bmi SpaceAfter                          ; a token follows
    jsr CKSEP
    bcc AfterToken                          ; a separator follows

;; Prints the space after the word.
;; Also: PRF2 (BB13)
SpaceAfter:
    jsr Lister::WrapSpace

;; Goes on with the byte after the token.
;; Also: JPL2 (BB13)
AfterToken:
    dey
    jmp NextByte

;; The high byte of the last line's number when `LIST` lists to the end of the program.
LAST_LINE_HIGH = $FF

;; The bits of a reserved word's character, without the bit 7 its last character has.
CHARACTER_BITS = $7F
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; FOR
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued
; Variables' offsets, which survive the variable table moving.

;; Turns the variable pointer in <FORPNT> into an offset from the simple variables' start, <SMVARS>, or back again.
;;
;; The offset is <SMVARS> less the address, so the same subtraction undoes it. Loops and strings' back pointers keep
;; offsets, which stay right when the variable table moves.
;; Out: FORPNT, FORPNT+1, FORPNTB = the offset (or the address)
;; Uses: A, Y, KIMY
;; Entry:
;;   OfPointerAtX = takes the pointer at the zero-page address in X, and returns with X = <KIMY>
;; See: <Variables::VariableOffset>
;; Also: PNTREL (BB13)
.proc SimpleVariableOffset
    stx KIMY
    ldx #FORPNT

;; Takes the pointer at the zero-page address in X, and returns with X = <KIMY>.
;; In: X = the zero-page address of the pointer
;; Also: PNTRL1 (BB13)
OfPointerAtX:
    lda SMVARS
    sec
    sbc 0,x
    sta 0,x
    lda SMVARS+1
    sbc 1,x
    ldy SMVARSB
    jsr FIXSBC
    sta 1,x
    tya
    sbc SYSPAG,x                            ; the pointer's X-byte
    sta SYSPAG,x
    ldx KIMY
    rts
.endproc

.endscope

.scope Statements continued
; FOR.

;; The `FOR` statement: assigns the loop variable its first value and puts the loop's entry, a <ForEntry>, on the stack.
;;
;; An entry for the same variable already on the stack is taken out; the newer `FOR` entries above it move up to close
;; the gap and stay. `FOR` then falls into <NextStatement>; the loop's body runs at least once, as <Statements::Next>
;; makes the test.
;; In: A = the character after `FOR`, flags as <CHRGOT> sets them
;; Errors: TYPE MISMATCH for a string or long-integer variable, OVERFLOW when its offset does not fit in 16 bits
;; See: <Statements::Next>, <FNDFOR>, <Statements::For::ReadStep>
;; Also: FOR (BB13)
.proc For
    jsr Statements::Let
    lda VALTYP
    beq IsNumber
    jmp TMERR                               ; only a real or an integer

;; Notes the variable's type and turns its address into an offset.
IsNumber:
    lda ISARA
    rol a
    lda INTFLG
    adc #0                                  ; an array element into bit 0
    sta TEMPFOR
    jsr Variables::VariableOffset
    lda FORPNT+1
    ldy FORPNTB
    jsr FIXAY
    sta FORPNT+1
    cpy #$FE                                ; the offset must fit in 16 bits
    bcs Fits
    jmp OVERR

;; Takes out an entry for the same variable: moves the stack above it up <FORSIZ> bytes.
Fits:
    jsr FNDFOR
    bne BuildFrame                          ; no loop on this variable yet
    lda #>StackTop                          ; page 1, in each pointer's high byte and X-byte
    sta HIGHDSB
    sta HIGHTRB
    sta LOWTRB
    sta HIGHDS+1
    sta HIGHTR+1
    sta LOWTR+1
    inx
    stx HIGHTR
    txa
    clc
    adc #FORSIZ
    sta HIGHDS
    tsx
    stx LOWTR
    jsr BLTUC
    tsx
    txa
    clc
    adc #FORSIZ
    tax
    txs

;; Builds the new entry, starting with the text pointer and line number <PushGoSubEntryHere> pushes, then reads `TO`
;; and the limit.
;; Also: NOTOL (BB13)
BuildFrame:
    pla                                     ; NextStatement's return address: FOR falls into NextStatement instead
    pla
    lda #FORSIZ / 2
    jsr GETSTK                              ; room for the entry
    jsr SaveTextPointer
    jsr SkipStatement                       ; TXTPTR to the FOR statement's end
    jsr PushGoSubEntryHere
    pla                                     ; the GOSUB entry's token: not a FOR entry's
    jsr RestoreTextPointer
    lda #TOTK
    jsr MSTESC
    jsr RequireNumber
    jsr EvaluateNumber                      ; the limit
    lda FACSGN                              ; pack the sign into the mantissa
    ora #$7F
    and FACHO
    sta FACHO
    lda #<(ReadStep)
    ldy #>(ReadStep)
    sta INDEX1
    sty INDEX1+1
    jmp FORPSH                              ; push the limit and go on at ReadStep

;; Pushes the rest of the entry: the step (1 when there is no `STEP`) and its sign, the variable's offset, its type and
;; <FORTK>, then falls into <NextStatement>.
;; Also: LDFONE (BB13)
ReadStep:
    lda #<(FONE)
    ldy #>(FONE)
    ldx #0
    jsr MOVFM
    lda #STEPTK
    jsr TRYESC
    bne PushStep
    jsr CHRGET
    jsr EvaluateNumber                      ; the step

;; Pushes the step and its sign, then the variable's offset, type and <FORTK>.
;; Also: ONEON (BB13)
PushStep:
    jsr SIGN
    jsr PUSHF
    lda FORPNT+1
    pha
    lda FORPNT
    pha
    lda TEMPFOR
    pha
    lda #FORTK
    pha
    ; Falls into NextStatement.
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The statement loop
; ---------------------------------------------------------------------------------------------------------------------

;; The statement loop: runs the next statement, from where <TXTPTR> stands.
;;
;; On entry <TXTPTR> points at the terminator of the statement just run: a colon, or the zero that ends a line (for a
;; `GOTO`, the zero before the line's link). Anything else is a syntax error. In a program, <OLDTXT> and <OLDTXTB> take
;; its value, the place to go on from for `CONT`. At a zero, the next line's link is read at <TXTPTR>+1: a zero link
;; ends the program (or the direct line) at <READY>; otherwise the line number at <TXTPTR>+2 goes into <CURLIN> and the
;; pointer moves to <TXTPTR>+3, the number's high byte, so <CHRGET> reads the text's first byte. When the page reaches
;; <MAXPG>, <TXTPTRB> goes up by one and the page down by a bank's $80 pages. The line number's high byte is $FF while
;; a direct line runs.
;;
;; CONTROL-C (bit 6 of <KEYSTROK>) stops the program, and a key with `ON KBD` (bit 7) goes to its line, before the next
;; statement.
;; Entry:
;;   SavePlace = keeps <TXTPTR> for `CONT` without checking for a terminator; `RETURN`, `CONT`, `INPUT`'s retry and
;;     `IF` come here
;;   CheckEvents = takes a pending CONTROL-C or key, then moves to the next statement; the `ON ERR` handler,
;;     <HNDLERR>, comes here
;; See: <ExecuteStatement>, <DispatchStatement>
;; Also: NEWSTT (BB13)
.proc NextStatement
    lda #0
    sta CMDFLG                              ; no RUN or CHAIN pending
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: BASIC's own prefix again
.endif
    tsx
    stx REMSTK                              ; the stack to go back to on an error
    lda FILNO+1                             ; output back to its usual place
    sta FILNO
    jsr CHRGOT
    bne ExecuteStatement::ToSyntaxError     ; no terminator
    ldx CURLIN+1
    inx
    beq CheckEvents                         ; a direct line: no CONT

;; Keeps <TXTPTR> in <OLDTXT> for `CONT`, without checking for a terminator.
;; Also: NWSTT (BB13)
SavePlace:
    lda TXTPTR
    ldy TXTPTR+1
    sta OLDTXT
    sty OLDTXT+1
    lda TXTPTRB
    sta OLDTXTB

;; Takes a pending CONTROL-C or key, then moves to the next statement, or the next line's at the end of a line.
;; Also: DIRCON (BB13)
CheckEvents:
    bit KEYSTROK
    bvs ExecuteStatement::ToBreak           ; bit 6: CONTROL-C
    bmi ExecuteStatement::ToKeyHandler      ; bit 7: a key for ON KBD
    ldy #0
    lda (TXTPTR),y
    bne ExecuteStatement                    ; a colon: the next statement is on this line
    iny
    lda (TXTPTR),y                          ; the next line's link
    clc
    beq DispatchStatement::ToEndOfProgram   ; zero: the program has ended
    iny
    lda (TXTPTR),y
    sta CURLIN
    iny
    lda (TXTPTR),y
    sta CURLIN+1
    tya
    adc TXTPTR                              ; TXTPTR to the number's high byte
    sta TXTPTR
    bcc KeepPageInRange
    inc TXTPTR+1

;; Brings <TXTPTR>'s page back below <MAXPG>, moving it into the next bank.
;; Also: CHKPGE (BB13)
KeepPageInRange:
    lda TXTPTR+1
    cmp #MAXPG
    bcc ExecuteStatement
    inc TXTPTRB
    sbc #MAXPG-MINPG
    sta TXTPTR+1
    ; Falls into ExecuteStatement.
.endproc

;; Runs the statement after <TXTPTR>, tracing it first when `TRACE` is on, then goes on to the next.
;;
;; With `TRACE`, every statement of a program (not of a direct line) prints `#` and its line number and a space. The
;; statement's handler is called with <ExecuteStatement::StatementReturn> on the stack, which returns to
;; <NextStatement>. The debugger stops here for each statement.
;; In: TXTPTR = the byte before the statement, CURLIN = its line number
;; See: <DispatchStatement>
;; Also: GONE (BB13)
.proc ExecuteStatement
    tsx
    stx REMSTK
    bit TRFLAG
    bpl Dispatch
    ldx CURLIN+1
    inx
    beq Dispatch                            ; a direct line is not traced
    lda #'#'
    jsr PrintCharacter
    ldx CURLIN
    lda CURLIN+1
    jsr LINPRT
    jsr PrintSpace

;; Reads the statement's first byte and runs it.
;; Also: GOFORIT (BB13)
Dispatch:
    jsr CHRGET
    jsr DispatchStatement

;; The return address <ExecuteStatement::Dispatch>'s JSR pushes, the byte before the JMP back to <NextStatement>.
;; Also: NEWRET (BB13)
StatementReturn = * - 1
    jmp NextStatement

;; Ends the statement with a syntax error.
;; Also: SNERR1 (BB13)
ToSyntaxError:
    jmp SNERR

;; Runs the `ON KBD` line for a key.
;; Also: ISAKEY (BB13)
ToKeyHandler:
    jmp KEYHIT

;; Stops the program for CONTROL-C, through <HandleBreak>, which does not come back.
;; Also: ISCTRLC (BB13)
ToBreak:
    jsr HandleBreak
.endproc

;; Runs a statement: a token from `END` to `NEW` goes to its handler from <STMDSP>, anything else is a `LET`.
;;
;; The handler is reached through an RTS, after <CHRGET>, with the statement's next character in A and the flags set as
;; <CHRGET> sets them.
;; In: A = the statement's first byte, flags as <CHRGET> sets them
;; Entry:
;;   ToEndOfProgram = ends the program at a zero link, as `END` does; <NextStatement> branches here with carry clear
;; Also: GONE3 (BB13)
.proc DispatchStatement
    beq Statements::Restore::Done           ; an empty statement
    ; Carry is already set: CHRGET sets it for anything but a digit, and a digit is a syntax error, as it should be.
    sbc #ENDTK
    ldx #TEMPST                             ; no string temporaries in use
    stx TEMPPT
    bcc ToLet                               ; not a token: a LET
    cmp #SCRATK-ENDTK+1
    bcs ExecuteStatement::ToSyntaxError     ; a token that is not a statement
    asl a
    tay
    lda STMDSP+1,y
    pha
    lda STMDSP,y
    pha                                     ; the handler's address, less one
    jmp CHRGET

;; Ends the program at a zero link, as `END` does.
;; In: carry = clear
;; Also: INTERM (BB13)
ToEndOfProgram:
    beq Statements::StopOrEnd::Finish

;; Runs a statement without a keyword as `LET`.
;; Also: GLET (BB13)
ToLet:
    jmp Statements::Let
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; RESTORE, STOP, END, CONT and BYE
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued
; RESTORE.

;; The `RESTORE` statement: points <DATPTR> at the zero before the program, so `READ` starts at the first `DATA` again.
;;
;; The borrow out of the page goes through <FIXYX>, which only checks the top of the range: a program starting at the
;; start of page <MINPG> would leave <DATPTR> in page 1, below the usual range (the same byte, by the banks' overlap).
;; Entry:
;;   SetDataPointer = sets <DATPTR> from A, Y and X; `READ` comes here with where its data ended
;;   Done = returns; <DispatchStatement> branches here for an empty statement
;; Also: RESTOR (BB13)
.proc Restore
    sec
    ldx TXTTABB
    lda TXTTAB
    sbc #1
    ldy TXTTAB+1
    bcs SetDataPointer
    dey
    jsr FIXYX

;; Sets <DATPTR>; `READ` comes here with where its data ended.
;; In: A, Y, X = the pointer (low, high, bank)
;; Also: RESFIN (BB13)
SetDataPointer:
    sta DATPTR
    stx DATPTRB
    sty DATPTR+1

;; Returns, for branches.
;; Also: ISCRTS (BB13)
Done:
    rts
.endproc

.endscope

;; Stops the program for CONTROL-C, with BREAK, or goes to `ON ERR`'s line with error <ERROR_BREAK>.
;;
;; When the any-key flag is set too, or in a direct line, `ON ERR` is passed over.
;; Entry:
;;   WithFlags = takes <KEYSTROK>'s flags in A; `INPUT` comes here with <CONTROL_C> for a CONTROL-C typed at its
;;     prompt, which is stored in <KEYSTROK> as it is
;; See: <Statements::StopOrEnd>, <HNDLERR>
;; Also: ISCNTC (BB13)
.proc HandleBreak
    lda KEYSTROK

;; Takes the flags in A; `INPUT` comes here with <CONTROL_C> for a CONTROL-C typed at its prompt.
;; In: A = <KEYSTROK>'s flags
;; Also: ISCNTC2 (BB13)
WithFlags:
    and #<(~KEY_CONTROL_C)
    sta KEYSTROK                            ; CONTROL-C taken
    ldx #ERROR_BREAK
    cmp #KEY_ANY
    bcs Stop
    ldy CURLIN+1
    iny
    beq Stop                                ; a direct line: no ON ERR
    dey
    sty ERRLIN+1
    stx ERRNUM
    ldy CURLIN
    sty ERRLIN
    bit ERRFLG                              ; ON ERR on?
    bpl Stop
    jmp HNDLERR

;; Stops with BREAK, printing to the console.
;; Also: ISRESET (BB13)
Stop:
    stx FILNO
    sec
    bcs Statements::StopOrEnd               ; always
.endproc

;; <KEYSTROK>'s bit for a CONTROL-C waiting.
KEY_CONTROL_C = $40

;; <KEYSTROK>'s bit for a key waiting for `ON KBD`.
KEY_ANY = $80

;; The error number a break gives `ON ERR`, in <ERRNUM>.
ERROR_BREAK = $FF

.scope Statements continued
; STOP, END, CONT, BYE and RUN.

;; The `END` statement: stops the program without a message.
;; Also: END (BB13)
.proc End
    clc
    ; Falls into Stop.
.endproc

;; The `STOP` statement: stops the program with BREAK.
;; In: A = the character after the keyword, zero = set for a terminator, carry = set for BREAK (<CHRGET> sets it after
;;   `STOP`; `END` clears it)
;; Also: STOP (BB13)
.proc Stop
    bne Statements::Cont::Done              ; not a terminator: NextStatement gives the syntax error
    ; Falls into StopOrEnd.
.endproc

;; Stops the program: keeps <TXTPTR> and <CURLIN> in <OLDTXT> and <OLDLIN> for `CONT` (not for a direct line), then goes
;; to <READY>, with BREAK and its line first when carry is set.
;;
;; The debugger stops here for `STOP`, `END` and CONTROL-C.
;; In: carry = set to print BREAK
;; Entry:
;;   Finish = goes to <READY>, through BREAK's message when carry is set; the end of the program comes here, and the
;;     debugger watches it
;; Also: STOP2 (BB13)
.proc StopOrEnd
    lda #$FF
    sta FILNO                               ; output to the console
    sta FILNO+1
    lda TXTPTR
    ldy TXTPTR+1
    ldx CURLIN+1
    inx
    beq DiscardReturn
    sta OLDTXT
    sty OLDTXT+1
    lda TXTPTRB
    sta OLDTXTB
    lda CURLIN
    ldy CURLIN+1
    sta OLDLIN
    sty OLDLIN+1

;; Drops the return address to <NextStatement>.
;; Also: DIRIS (BB13)
DiscardReturn:
    pla
    pla

;; Goes to <READY>, through BREAK's message when carry is set.
;; In: carry = set to print BREAK
;; Also: ENDCON (BB13)
Finish:
    bcc ToReady
    brk                                     ; empty the type-ahead buffer
    .byte SDCNT
    .word DFLUSH
    jsr PrintNewline
    lda #<(BRKTXT)
    ldx #0
    ldy #>(BRKTXT)
    jmp ERRFIN

;; Goes to <READY>.
;; Also: GORDY (BB13)
ToReady:
    jmp READY
.endproc

;; The `CONT` statement: goes on from where `STOP`, `END`, CONTROL-C or an error stopped the program.
;;
;; It runs only in a direct line (in a program it does nothing). It clears <KEYSTROK>, sets the any-key event again,
;; and goes on at <OLDTXT> on line <OLDLIN>. A zero <OLDTXTB> means there is nothing to go on with: CAN'T CONTINUE.
;; Entering or changing a line clears it.
;; In: zero = set for a terminator after `CONT`
;; Entry:
;;   Done = returns; the statements' checks branch here
;; See: <Statements::StopOrEnd>, <NextStatement::SavePlace>
;; Also: CONT (BB13)
.proc Cont
    bne Done
    ldx CURLIN+1
    inx
    bne Done                                ; in a program: nothing
    stx KEYSTROK
    brk
    .byte SDCNT
    .word DKBD
    ldx #ERRCN
    ldy OLDTXTB
    bne Resume
    jmp ERROR                               ; nothing to continue

;; Goes on from the place kept.
Resume:
    lda OLDTXT
    sta TXTPTR
    sty TXTPTRB
    lda OLDTXT+1
    sta TXTPTR+1
    lda OLDLIN
    ldy OLDLIN+1
    sta CURLIN
    sty CURLIN+1
    pla                                     ; NextStatement's return address
    pla
    jmp NextStatement::SavePlace

;; Returns, for the statements' checks.
;; Also: CONTRT (BB13)
Done:
    rts
.endproc

;; The `BYE` statement: closes the files and restarts the Apple III through SOS's COLD_START.
;;
;; Each call's parameter list is the call itself, starting at its BRK, a zero: no parameters. COLD_START takes none;
;; CLOSE wants one, so SOS refuses that call, which matters little, as <CLSALL> has closed BASIC's files.
;; Entry:
;;   CloseAndRestart = closes the files and restarts, with nothing to check
;; Also: COLD (BB13)
.proc Bye
    jsr CHRGOT
    beq CloseAndRestart
    jmp SNERR

;; Closes the files and restarts.
;; Also: COLD1 (BB13)
CloseAndRestart:
    jsr CLSALL
    brk
    .byte SCLS
    .word * - 2
    brk
    .byte CLDSTRT
    .word * - 2                             ; never returns
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; RUN and the GOSUB entry
; ---------------------------------------------------------------------------------------------------------------------

;; The `RUN` statement: runs the program from its start, from a line (`RUN n` or `RUN ,n`), or loads a program first.
;;
;; Each clears the variables and the stack. `RUN pathname` loads the program, turns `TRACE` off and runs it through
;; <FRUN>.
;; In: A = the character after `RUN`, flags as <CHRGOT> sets them
;; See: <RUNC>, <Statements::GoSub::Transfer>
;; Also: RUN (BB13)
.proc Run
    bne WithArgument
    jmp RUNC                                ; RUN alone: from the start

;; Takes a line number, a comma and a line number, or a pathname.
WithArgument:
    bcc FromLine                            ; a digit: from that line
    cmp #','
    beq AfterComma
    jsr LDRUN                               ; a pathname
    lda #1
    sta RNFLG
    jsr DOLD2
    jsr CLEARC
.if VERSION >= 130
    jsr CNVTPFX1                            ; 1.3: name the program's prefix by its volume
.endif
    lsr TRFLAG                              ; TRACE off
    jmp FRUN

;; Runs from the line after the comma.
;; Also: RUNL2 (BB13)
AfterComma:
    jsr CHKCOM

;; Clears the variables and the stack (<CLEARC> resets it, taking <NextStatement>'s return address), then goes to the
;; line.
;; Also: RUNL (BB13)
FromLine:
    jsr CLEARC
    jsr Statements::GoSub::Transfer
    jmp NextStatement
.endproc

.endscope

;; Puts a <GoSubEntry> on the stack, below the caller's return address and the one above it, after checking for room.
;;
;; The entry holds the text pointer as an offset from <TXTTAB>. For `GOSUB`, the second return address is
;; <ExecuteStatement::StatementReturn>, so the entry goes under it; `FOR` and `ON KBD` call through
;; <PushGoSubEntryHere> and <PushGoSubEntryHereChecked>, so the entry goes at their own level.
;; In: TXTPTR = where `RETURN` goes on from, CURLIN = the line
;; Uses: A, X, Y, INDEX, PNTSAV
;; Entry:
;;   WithoutRoomCheck = does not check for room
;;   Done = returns; <Statements::GoTo> branches here
;; See: <Statements::Return>, <Statements::For>
;; Also: PSHTXT (BB13)
.proc PushGoSubEntry
    lda #4
    jsr GETSTK                              ; room for 8 bytes

;; Does not check for room.
;; Also: PSHTXT2 (BB13)
WithoutRoomCheck:
    pla                                     ; the return address
    sta PNTSAV
    pla
    tax
    pla                                     ; and the one above it
    sta INDEX
    pla
    sta INDEX+1
    sec                                     ; TXTPTR, less TXTTAB
    lda TXTPTR
    sbc TXTTAB
    pha
    lda TXTPTR+1
    sbc TXTTAB+1
    ldy TXTPTRB
    jsr FIXSBC
    pha
    tya
    sbc TXTTABB
    pha
    lda CURLIN+1
    pha
    lda CURLIN
    pha
    lda #GOSUTK
    pha
    lda INDEX+1                             ; the return addresses back on top
    pha
    lda INDEX
    pha
    txa
    pha
    lda PNTSAV
    pha

;; Returns, for branches.
;; Also: PSHTRT (BB13)
Done:
    rts
.endproc

;; Pushes a <GoSubEntry> at the caller's own level, without checking for room; `FOR` uses it.
;; See: <PushGoSubEntry>
;; Also: PSHTXT3 (BB13)
.proc PushGoSubEntryHere
    jsr PushGoSubEntry::WithoutRoomCheck
    rts
.endproc

;; Pushes a <GoSubEntry> at the caller's own level, after checking for room; `ON KBD` uses it.
;; See: <PushGoSubEntry>, <KEYHIT>
;; Also: PSHTXT4 (BB13)
.proc PushGoSubEntryHereChecked
    jsr PushGoSubEntry
    rts
.endproc
