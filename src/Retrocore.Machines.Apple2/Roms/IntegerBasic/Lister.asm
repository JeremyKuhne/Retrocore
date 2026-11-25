; retrocore: style=strict
;; Integer BASIC: the entry points and the lister
;;
;; The two entry points at the start of the ROM, which the Monitor's Control-B and Control-C commands jump to, and
;; LIST, which turns a program's tokens back into text.
;;
;; The lister prints a line's number, then walks its bytes. A byte with bit 7 set and bit 6 clear starts a constant,
;; whose value follows; one with bits 7 and 6 set starts a name, whose characters all have bit 7 set. Any other byte
;; is a token, whose text the lister finds in the syntax table (SyntaxTable.asm) by counting keywords down from the
;; top of a page, the same count that gave the word its token. After REM and an opening quote it copies the
;; characters that follow as they are. It adds blanks around keywords that begin or end with a letter, and starts a
;; new line, indented, when a line would run past the screen's width.
;;
;; Part of IntegerBasic.asm.

;; Starts Integer BASIC from scratch, the cold start, which the Monitor's Control-B command runs.
;;
;; At $E000. <ColdStart> sets <LowMemory> and <HighMemory> and erases any program, then returns here to fall into the
;; warm start.
;; Also: BASIC (IBSM)
.proc ColdEntry
.assert * = $E000, "ColdEntry must stay at $E000."
    jsr ColdStart
    ; Falls into WarmEntry.
.endproc

;; Enters Integer BASIC keeping its program and variables, the warm start, which the Monitor's Control-C command
;; runs.
;;
;; At $E003. Typing Control-C in a line that INPUT reads also comes here (<Break::CheckLine>).
;; Also: BASIC2 (IBSM)
.proc WarmEntry
.assert * = $E003, "WarmEntry must stay at $E003."
    jmp WarmStart
.endproc

;; Sets the prompt character and prints it.
;; In: A = the prompt character, with its high bit set
;; Keeps: X, Y
.proc SetPrompt
    sta PromptCharacter
    jmp CharacterOut

    ; An unused byte (an RTS).
    .byte $60
.endproc

;; The lister: the routines that print a stored line as text, and that walk its bytes.
.scope Lister

; The screen's width, as the lister uses it.

;; The column past which the lister starts a new line before the next token or constant.
WRAP_COLUMN = 32

;; The column past which the lister starts a new line inside a name, a string or a remark.
TEXT_WRAP_COLUMN = 37

;; The blanks that indent a line the lister continues, so it goes on under the start of its text.
INDENT = 6

; The syntax table's two pages.

;; The first byte of the syntax table's first page ($EC00), which that page's tokens count up from: a token above it
;; has its keyword in that page, and the others in the second page ($ED00), whose tokens count up from 0.
FIRST_PAGE_BASE = $50

;; Prints a blank if a keyword's character is a letter, to separate the keyword from what follows.
;;
;; The syntax table stores a character as its code less $A0, so bit 5 of the byte is set for the letters and clear for
;; punctuation and digits.
;; In: X = the syntax table byte of the character
;; Out: Pointer2 = $A0 if a blank was printed
;; Keeps: X, Y
;; Entry:
;;   Blank = prints the blank whatever X holds
;; Also: BLANKIFLET (UNKN)
.proc BlankAfterLetter
    txa
    and #SYNTAX_LETTER_BIT
    beq FetchByte::Done

;; Prints a blank whatever X holds, and remembers it in <Pointer2>, so a keyword that follows gets no other.
;; Also: LISTBLANK (UNKN)
Blank:
    lda #BLANK | $80
    sta Pointer2
    jmp CharacterOut
.endproc

;; Fetches the next byte to list, first starting a new, indented line if the cursor is past column 32.
;;
;; The new line is a Return and six blanks.
;; In: Pointer1 = the byte
;; Out: A = the byte, Y = 0, Pointer1 = the byte after it
;; Entry:
;;   PastColumn = takes the column past which to start a new line in A, instead of 32
;; Also: LISTBYTE (UNKN)
.proc NextByteWrapping
    lda #WRAP_COLUMN

;; Fetches the next byte to list, first starting a new line if the cursor is past the column in A.
;; In: A = the column, Pointer1 = the byte
;; Out: A = the byte, Y = 0, Pointer1 = the byte after it
;; Also: LISTBYTECOL (UNKN)
PastColumn:
    cmp CursorColumn
    bcs FetchByte                   ; still room on this line

    ; A Return, then the blanks.
    lda #CARRIAGE_RETURN | $80
    ldy #INDENT + 1
Indent:
    jsr CharacterOut
    lda #BLANK | $80
    dey
    bne Indent
    ; Falls into FetchByte.
.endproc

;; Fetches the next byte to list from <Pointer1> and steps <Pointer1> past it.
;; In: Pointer1 = the byte
;; Out: A = the byte, Y = 0, Pointer1 = the byte after it
;; Keeps: X
;; Entry:
;;   Done = returns; the routines around it branch here to return
;; Also: NextByte (IBSM)
.proc FetchByte
    ldy #0
    lda (Pointer1),y
    inc Pointer1
    bne Done
    inc Pointer1+1
Done:
    rts
.endproc

.endscope

;; The routines of the statement tokens: each token the verb tables (<Verbs::RoutinesLow>) give a routine runs it
;; when the interpreter (<Interpreter::RunLine>) reaches it, taking its operands off the noun stack.
;;
;; Integer BASIC gives each use of a keyword its own token, so a statement has a routine for each of its parts: its
;; keyword, its commas and `AT`s, and its string and number forms, named for the keyword and the part
;; (<Statements::HLinComma>, <Statements::PrintString>). The scope is in pieces through the ROM, in address order;
;; this first piece is `LIST`'s comma.
.scope Statements

;; The comma of LIST with two numbers (token $75): lists from where <Statements::ListLine> stopped up to the second
;; line number.
;;
;; <FindLine::FromPointer3> searches on from <Pointer3>, where the search of <Statements::ListLine> stopped, for the
;; first line numbered at or above the number, and leaves <Pointer3> after that line when the number exists, so that
;; line is listed too.
;; In: X = the noun stack, its top entry the last line number to list, Pointer1 = the next line to list
;; Out: X = the noun stack, one entry higher
;; Also: COMMA_LIST (IBSM)
.proc ListComma
    jsr GetNumber
    jsr FindLine::FromPointer3
    ; Falls into Lister::ListLines.
.endproc

.endscope

; The lister, continued: listing a range of lines.
.scope Lister continued

;; Lists the lines from <Pointer1> up to, but not including, <Pointer3>.
;; In: Pointer1 = the first line, Pointer3 = the line to stop at
;; Out: Pointer1 = Pointer3 or past it
;; Also: LISTRANGE (UNKN)
.proc ListLines
    lda Pointer1
    cmp Pointer3
    lda Pointer1+1
    sbc Pointer3+1
    bcs FetchByte::Done
    jsr PrintLine
    jmp ListLines
.endproc

.endscope

; Statements: LIST, and LIST with a number.
.scope Statements continued

;; LIST alone (token $76): lists the whole program, from <ProgramStart> up to <HighMemory>.
;; Also: LIST (IBSM)
.proc List
    lda ProgramStart
    sta Pointer1
    lda ProgramStart+1
    sta Pointer1+1
    lda HighMemory
    sta Pointer3
    lda HighMemory+1
    sta Pointer3+1
    bne Lister::ListLines           ; always: HIMEM is above page 0
.endproc

;; LIST with a number (token $74): lists that line, if it exists, and leaves <Pointer1> ready for
;; <Statements::ListComma>.
;;
;; When the line is missing, <Pointer1> is left at the next line above the number, so LIST 5,30 lists from there.
;; In: X = the noun stack, its top entry the line number
;; Out: X = the noun stack, two entries higher: <FindLine> takes one more, Pointer1 = the line after the one listed,
;;   or the line above the number
;; Also: LISTNUM (IBSM)
.proc ListLine
    jsr GetNumber
    jsr FindLine
    lda Pointer2
    sta Pointer1
    lda Pointer2+1
    sta Pointer1+1
    bcs Lister::FetchByte::Done     ; the number is not a line: list nothing yet
    ; Falls into Lister::PrintLine.
.endproc

.endscope

; The lister, continued: printing a line.
.scope Lister continued

;; Lists one line: prints its number, then its tokens as text, and a Return.
;;
;; <Pointer2> remembers what was printed last: 0 after the line number, a constant's marker shifted left, the token
;; that ended a name or text, a keyword's last character less $A0, or $A0 after a blank. Only a name right after the
;; line number, where <Pointer2> is 0, gets a blank before it; a keyword that starts with a letter gets one unless a
;; blank came last, the only value with bit 7 set (<Lister::BlankBeforeKeyword>). X is saved in <SavedX> and restored
;; before the Return.
;; In: Pointer1 = the line's length byte
;; Out: Pointer1 = the next line
;; Uses: A, Y, Pointer2, LeadingZero, Accumulator, DecimalNumber, DigitPlace, DigitCharacter
;; Also: UNPACK (IBSM)
.proc PrintLine
    stx SavedX
    lda #BLANK | $80
    sta LeadingZero                 ; pad the line number to five places with blanks
    jsr FetchByte                   ; the length byte
    tya                             ; A = 0: nothing printed yet
    ; Falls into PrintConstant, which prints the line number first.

;; Prints a constant: its value follows the digit that marks it.
;;
;; A holds the marker shifted left, which is not 0, so <Pointer2> no longer asks for a blank before a name; for the
;; line number, which <PrintLine> falls in with, A is 0.
PrintConstant:
    sta Pointer2
    jsr FetchByte
    tax
    jsr FetchByte
    jsr PrintDecimal                       ; the value, or the line number the first time through

;; The loop over the line's bytes: fetches the next one and decides what it starts.
NextItem:
    jsr NextByteWrapping
    sty LeadingZero                 ; no padding for constants after the line number
    tax
    bpl PrintToken                  ; bit 7 clear: a token
    asl a
    bpl PrintConstant               ; bit 6 clear: a digit, the start of a constant

    ; A name: a blank before it only after the line number.
    lda Pointer2
    bne PrintName
    jsr BlankAfterLetter::Blank
PrintName:
    txa

;; Prints a name or text: the character in A, then every following byte with bit 7 set.
;;
;; Text breaks onto a new line past column 37, later than tokens do.
;; Also: LISTTEXT (UNKN)
PrintText:
    jsr CharacterOut

;; Prints the text after REM or an opening quote: every byte with bit 7 set, up to the token that ends it.
;; Also: LISTTEXTNXT (UNKN)
CopyText:
    lda #TEXT_WRAP_COLUMN
    jsr NextByteWrapping::PastColumn
    tax
    bmi PrintText
    sta Pointer2                    ; the token that ended the text

;; Lists a token: ends the line at the end-of-line token; otherwise finds the token's text in the syntax table and
;; prints it.
;;
;; Tokens below $51 are counted in the page at <Syntax::SecondPage> ($ED00), the rest in the page at <Syntax::Table>
;; ($EC00), whose count starts at $50. Each keyword is stored with its last character lowest, and the count goes down
;; from the top of the page: a keyword's first character is a character byte whose neighbor above is either not a
;; character or the last character of another keyword (bit 6 set). The X-th such character from the top starts token X's
;; text.
;; Also: LISTTOKEN (UNKN)
PrintToken:
    cmp #TOKEN_END_OF_LINE
    bne FindKeyword
    ldx SavedX
    jmp PrintReturn

    ; Y = 0, so the first byte read is the page's first, which is not a character: as if it were above the top.
FindKeyword:
    pha
    sty Accumulator
    ldx #>Syntax::SecondPage
    stx Accumulator+1
    cmp #FIRST_PAGE_BASE + 1
    bcc CountKeywords               ; tokens up to $50 are in the second page
    dec Accumulator+1
    sbc #FIRST_PAGE_BASE            ; carry is set: the count in the first page starts at $50

;; Counts keywords down the page until the count in A reaches 0.
CountKeywords:
    pha
    lda (Accumulator),y
SkipToCharacter:
    tax                             ; X = the byte above the one read next
    dey
    lda (Accumulator),y
    bpl SkipToCharacter             ; skip bytes that are not characters
    cpx #SYNTAX_LAST_CHARACTER
    bcs KeywordStart                ; a character below a keyword's last character starts a keyword
    cpx #0
    bmi SkipToCharacter             ; a character below another character: not a start

;; Found the start of a keyword: Y indexes its first character, A holds it.
KeywordStart:
    tax
    pla
    sbc #1                          ; carry is set
    bne CountKeywords               ; not this keyword yet
    bit Pointer2
    bmi PrintKeyword                ; a blank came last: no other before the keyword
    jsr Lister::BlankBeforeKeyword                    ; a blank before a keyword starting with a letter

    ; Print the keyword's characters, down the page, through the one with bit 6 set.
PrintKeyword:
    lda (Accumulator),y
    bpl AfterKeyword                ; a byte that is not a character ends the keyword
    tax
    and #SYNTAX_CHARACTER_BITS      ; Pointer2 = the character, bit 7 clear: not a blank
    sta Pointer2
    clc
    adc #SYNTAX_CHARACTER_BASE
    jsr CharacterOut
    dey
    cpx #SYNTAX_LAST_CHARACTER      ; bit 6 clear: more characters
    bcc PrintKeyword

;; After the keyword: a blank if it ends with a letter, then the text that follows REM or an opening quote.
AfterKeyword:
    jsr BlankAfterLetter
    pla
    cmp #TOKEN_REM
    beq CopyText                    ; REM: copy the remark
    cmp #TOKEN_OPEN_QUOTE
    bne NextItem                    ; anything but the opening quote: the next token
    beq CopyText                    ; always: copy the string
.endproc

.endscope
