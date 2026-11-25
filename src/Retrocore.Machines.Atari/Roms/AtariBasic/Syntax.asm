;; SYNTAX ($A2E1-$A879)
;;
;; What the syntax checker matches a statement against, and the routines its rules call:
;;
;; - <MATCH_OPERATOR> matches an operator's, a function's or a keyword's name in the line against the token a rule
;;   wants, and writes the token.
;; - The syntax routines for the operands: <SYNTAX_NUMERIC_VARIABLE> and <SYNTAX_STRING_VARIABLE> read a variable's
;;   name, adding a new variable to the variable name and value tables; <SYNTAX_NUMERIC_CONSTANT> and
;;   <SYNTAX_STRING_CONSTANT> copy a constant into the tokens.
;; - <SEARCH_NAMES> finds a name in the statement name table, the operator name table or the variable name table,
;;   and <TEST_LETTER> tells a letter.
;; - <STATEMENT_NAMES>, each statement's name and its rule; <STOPPED_MESSAGE>; the syntax tables, a grammar of
;;   Atari BASIC written in the syntax checker's codes, from <RULE_EXPRESSION>; and <OPERATOR_NAMES>, the names of
;;   the operators and functions, which are also their tokens.
;;
;; The engine that runs the rules is the line editor's, <CHECK_SYNTAX>. Maintained by hand; assembles byte-identically
;; to the cartridge.

; ---------------------------------------------------------------------------------------------------------------------
; The tables' macros
; ---------------------------------------------------------------------------------------------------------------------

;; A name in a name table: its characters, the last with bit 7 set (NAME_END).
;; Parameters: text = the name
.macro NAME_TEXT text
    .repeat .strlen(text) - 1, index
    .byte .strat(text, index)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | NAME_END
.endmacro

; The statement name table's entries are counted, to check each against its token.
SYNTAX_STATEMENT_ENTRY .set 0

;; A statement name table entry: the address less 1 of the statement's syntax rule, then its name.
;; Parameters: token = the statement's token, which must be the entry's number, text = the name, rule = the rule
.macro STATEMENT token, text, rule
    .assert (token) = SYNTAX_STATEMENT_ENTRY, "A statement's entry must be its token's."
    .word (rule) - 1
    NAME_TEXT text
SYNTAX_STATEMENT_ENTRY .set SYNTAX_STATEMENT_ENTRY + 1
.endmacro

; The operator name table's entries are counted, to check each against its token.
SYNTAX_OPERATOR_ENTRY .set OPERATOR_NAMES_FIRST

;; An operator name table entry: an operator's or a function's name.
;; Parameters: token = the token, which must be the entry's number from OPERATOR_NAMES_FIRST, text = the name
.macro OPERATOR token, text
    .assert (token) = SYNTAX_OPERATOR_ENTRY, "An operator's entry must be its token's."
    NAME_TEXT text
SYNTAX_OPERATOR_ENTRY .set SYNTAX_OPERATOR_ENTRY + 1
.endmacro

;; An operator name table entry whose name is one character that a string can't hold.
;; Parameters: token = the token, which must be the entry's number from OPERATOR_NAMES_FIRST, character = the
;;   character, without bit 7
.macro OPERATOR_CHARACTER token, character
    .assert (token) = SYNTAX_OPERATOR_ENTRY, "An operator's entry must be its token's."
    .byte (character) | NAME_END
SYNTAX_OPERATOR_ENTRY .set SYNTAX_OPERATOR_ENTRY + 1
.endmacro

;; Syntax code: matches the rule at an address, a word away (SYNTAX_CALL).
;; Parameters: rule = the rule
.macro FAR rule
    .byte SYNTAX_CALL
    .word (rule) - 1
.endmacro

;; Syntax code: matches the rule at an address within 64 bytes back or 63 on (SYNTAX_RELATIVE).
;; Parameters: rule = the rule
.macro NEAR rule
    .assert ((rule) - * >= -64) & ((rule) - * <= 63), "A near rule must be 64 bytes back to 63 on."
    .byte (rule) - * + SYNTAX_BIAS
.endmacro

;; Syntax code: calls a syntax routine, which returns carry set when it doesn't match (SYNTAX_ROUTINE).
;; Parameters: routine = the routine
.macro ROUTINE routine
    .byte SYNTAX_ROUTINE
    .word (routine) - 1
.endmacro

;; Syntax code: ends an alternative that matched, so the rule did, or starts the next alternative (SYNTAX_OR).
.macro OR
    .byte SYNTAX_OR
.endmacro

;; Syntax code: ends the rule's last alternative (SYNTAX_RETURN).
.macro RETURN
    .byte SYNTAX_RETURN
.endmacro

;; Syntax code: matches an operator's or a function's name, after any spaces, and writes its token.
;; Parameters: token = the token, OPERATOR_NAMES_FIRST or more
.macro MATCH token
    .assert (token) >= SYNTAX_FIRST_TOKEN, "A token to match is SYNTAX_FIRST_TOKEN or more."
    .byte token
.endmacro

;; Syntax code: matches an operator's name exactly where the line is, without skipping spaces (SYNTAX_TOKEN).
;; Parameters: token = the token
.macro MATCH_HERE token
    .byte SYNTAX_TOKEN, token
.endmacro

;; Syntax code: replaces the token just written, for an operator that means something else here (SYNTAX_REPLACE).
;; Parameters: token = the token to write instead
.macro REPLACE token
    .byte SYNTAX_REPLACE, token
.endmacro

;; Syntax code: matches an expression, by <RULE_EXPRESSION> (SYNTAX_EXPRESSION).
.macro EXPRESSION
    .byte SYNTAX_EXPRESSION
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; Matching an operator
; ---------------------------------------------------------------------------------------------------------------------

;; Matches the operator, function or keyword a syntax rule wants against the line, and writes its token.
;;
;; The syntax checker comes here for a code from SYNTAX_FIRST_TOKEN up, which is the token to match, and at
;; MATCH_OPERATOR_HERE for SYNTAX_TOKEN's, whose token is in the next byte. The operator name table is searched for
;; the first name that the line starts with at CIX, so "<=" is found before "<". The search's result is kept for
;; that place in the line (OPERATOR_SEARCHED), as a rule's alternatives often try several tokens in the same place.
;; FN_ATN matches any function from FN_ATN on: those that take one number.
;; In: SYNTAX_POINTER = the code, the token wanted, INBUFF/CIX = the line
;; Out: carry = clear when it matched, CIX = past the name
;; Errors: carry = set when it doesn't match, 14 (ERR_LINE_TOO_LONG) when the token output buffer is full
;; Uses: A, X, Y, OPERATOR_SEARCHED, OPERATOR_FOUND, OPERATOR_END, NAME_POINTER, NAME_OFFSET, ENTRY_NUMBER,
;;   TOKEN_INDEX
;; Entry: MATCH_OPERATOR_HERE = without skipping spaces
;; See: <OPERATOR_NAMES>, <SEARCH_NAMES>
MATCH_OPERATOR:
    jsr FP_SKIP_SPACES
MATCH_OPERATOR_HERE:
    lda CIX
    cmp OPERATOR_SEARCHED
    beq MATCH_OPERATOR_COMPARE      ; searched here already
    sta OPERATOR_SEARCHED
    lda #>OPERATOR_NAMES
    ldy #<OPERATOR_NAMES
    ldx #$00                        ; no bytes before each name
    jsr SEARCH_NAMES
    bcs MATCH_OPERATOR_NONE
    stx OPERATOR_END
.if VERSION = VERSION_A
    clc                             ; rev. A clears the carry that SEARCH_NAMES already cleared
.endif
    lda ENTRY_NUMBER                ; carry is clear
    adc #OPERATOR_NAMES_FIRST
    sta OPERATOR_FOUND
MATCH_OPERATOR_COMPARE:
    ldy #$00
    lda (SYNTAX_POINTER),y          ; the token wanted
    cmp OPERATOR_FOUND
    beq MATCH_OPERATOR_WRITE
    cmp #FN_ATN                     ; any function that takes one number?
    bne MATCH_OPERATOR_FAIL
    lda OPERATOR_FOUND
    cmp #FN_ATN
.if VERSION = VERSION_A
    bcs MATCH_OPERATOR_FUNCTION     ; rev. A fails here, and loads the function's token again
MATCH_OPERATOR_FAIL:
    sec
    rts
MATCH_OPERATOR_FUNCTION:
    lda OPERATOR_FOUND
.else
    bcc MATCH_OPERATOR_FAIL
.endif
MATCH_OPERATOR_WRITE:
    jsr WRITE_TOKEN                 ; A = the token found
    ldx OPERATOR_END
    stx CIX
    clc
    rts
MATCH_OPERATOR_NONE:
    lda #$00                        ; no name here: no token matches
    sta OPERATOR_FOUND
.if VERSION >= VERSION_B            ; the later revisions share this RTS; rev. A has its own
MATCH_OPERATOR_FAIL:
.endif
    sec
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; Syntax routine: reads a numeric variable or array's name, adding the variable when it is new, and writes its token.
;;
;; A name is a letter, then letters and digits; a string variable's ends with $, and an array's is followed by "(".
;; The variable name table keeps the $ or the ( as the name's last character, so A, A$ and A( are three variables.
;; For an array, CIX is left on the (, for the rule to match it. A name that starts with an operator's or a
;; function's name (NOT, AND, TO, SIN...) is not a variable when the character after that name is below "0": NOTE1
;; is a variable, and so, by that test, is TO in TO=1, but not NOT in NOT A.
;;
;; A new variable's name goes at the end of the variable name table, and its eight bytes, its type and number and
;; zeros, at the end of the variable value table; NEW_VARIABLES counts it, so that the line editor can take it out
;; again when the line has a syntax error. Its token is TOKEN_VARIABLE with its number.
;; In: INBUFF/CIX = the line
;; Out: carry = clear when a numeric variable or array is here, CIX = past its name, VALUE_TYPE = 0 or VALUE_ARRAY
;; Errors: carry = set when there isn't one, 4 (ERR_TOO_MANY_VARIABLES) for a 129th variable, 2 (ERR_MEMORY) when
;;   the tables can't grow, 14 (ERR_LINE_TOO_LONG) when the token output buffer is full
;; Uses: A, X, Y, VALUE_NUMBER, FR0, NAME_START, NAME_POINTER, NAME_OFFSET, ENTRY_NUMBER, OPERATOR_SEARCHED,
;;   OPERATOR_FOUND, OPERATOR_END, NEW_SPACE, NEW_VARIABLES, TOKEN_INDEX, SPACE_SIZE, MOVE_LENGTH, MOVE_FROM, MOVE_TO,
;;   APPMHI, VNTD..BASIC_MEMTOP+1
;; See: <SYNTAX_STRING_VARIABLE>, <SEARCH_NAMES>, <OPEN_SPACE>
SYNTAX_NUMERIC_VARIABLE:
    lda #$00
    beq SYNTAX_VARIABLE             ; always
;; Syntax routine: reads a string variable's name, adding the variable when it is new, and writes its token.
;; Inherit: <SYNTAX_NUMERIC_VARIABLE>
;; Out: carry = clear when a string variable is here, CIX = past its name and its $, VALUE_TYPE = VALUE_STRING
;; Errors: carry = set when there isn't one, 4 (ERR_TOO_MANY_VARIABLES) for a 129th variable, 2 (ERR_MEMORY) when
;;   the tables can't grow, 14 (ERR_LINE_TOO_LONG) when the token output buffer is full
SYNTAX_STRING_VARIABLE:
    lda #VALUE_STRING
SYNTAX_VARIABLE:
    sta VALUE_TYPE
    jsr FP_SKIP_SPACES
    lda CIX
    sta NAME_START
    jsr TEST_LETTER
    bcs SYNTAX_VARIABLE_FAIL
    jsr MATCH_OPERATOR              ; never matches, but finds any operator's name here
    lda OPERATOR_FOUND
    beq SYNTAX_VARIABLE_NAME
    ldy OPERATOR_END                ; a name follows it?
    lda (INBUFF),y
    cmp #'0'
    bcc SYNTAX_VARIABLE_FAIL
SYNTAX_VARIABLE_NAME:
    inc CIX
    jsr TEST_LETTER
    bcc SYNTAX_VARIABLE_NAME
    jsr FP_TEST_DIGIT
    bcc SYNTAX_VARIABLE_NAME
    lda (INBUFF),y                  ; the character after the letters and digits
    cmp #'$'
    beq SYNTAX_VARIABLE_DOLLAR
    bit VALUE_TYPE
    bpl SYNTAX_VARIABLE_ARRAY
SYNTAX_VARIABLE_FAIL:
    sec
    rts
SYNTAX_VARIABLE_DOLLAR:
    bit VALUE_TYPE
    bpl SYNTAX_VARIABLE_FAIL        ; a string where a number is wanted
    iny                             ; the $ is part of the name
    bne SYNTAX_VARIABLE_SEARCH      ; always
SYNTAX_VARIABLE_ARRAY:
    lda (INBUFF),y
    cmp #'('
    bne SYNTAX_VARIABLE_SEARCH
    iny                             ; an array: the ( is part of the name
    lda #VALUE_ARRAY
    ora VALUE_TYPE
    sta VALUE_TYPE
SYNTAX_VARIABLE_SEARCH:
    lda NAME_START
    sta CIX
    sty NAME_START                  ; NAME_START = the name's end
    lda VNTP+1
    ldy VNTP
    ldx #$00                        ; no bytes before each name
    jsr SEARCH_NAMES
SYNTAX_VARIABLE_CHECK:
    bcs SYNTAX_VARIABLE_ADD
    cpx NAME_START                  ; the whole name, not the start of a longer one?
    beq SYNTAX_VARIABLE_FOUND
    jsr SEARCH_NAMES_NEXT
    jmp SYNTAX_VARIABLE_CHECK
SYNTAX_VARIABLE_ADD:
    sec
    lda NAME_START
    sbc CIX
    sta CIX                         ; CIX = the name's length, for now
    tay
    ldx #VNTD                       ; open space before the name table's dummy zero byte
    jsr OPEN_SPACE
    lda ENTRY_NUMBER                ; the search counted the names: the new variable's number
    sta VALUE_NUMBER
    ldy CIX
    dey
    ldx NAME_START
    dex
SYNTAX_VARIABLE_COPY_NAME:
    lda LBUFF,x
    sta (NEW_SPACE),y
    dex
    dey
    bpl SYNTAX_VARIABLE_COPY_NAME
    ldy CIX
    dey
    lda (NEW_SPACE),y
    ora #NAME_END                   ; mark its last character
    sta (NEW_SPACE),y
    ldy #VALUE_SIZE
    ldx #STMTAB                     ; open space at the end of the value table
    jsr OPEN_SPACE
    inc NEW_VARIABLES
    ldy #$02
    lda #$00
SYNTAX_VARIABLE_CLEAR:
    sta VALUE_TYPE,y                ; FR0 = 0
    iny
    cpy #VALUE_SIZE
    bcc SYNTAX_VARIABLE_CLEAR
    dey
SYNTAX_VARIABLE_COPY_VALUE:
    lda VALUE_TYPE,y
    sta (NEW_SPACE),y
    dey
    bpl SYNTAX_VARIABLE_COPY_VALUE
SYNTAX_VARIABLE_FOUND:
    bit VALUE_TYPE
    bvc SYNTAX_VARIABLE_TOKEN
    dec NAME_START                  ; an array: leave the ( for the rule
SYNTAX_VARIABLE_TOKEN:
    lda NAME_START
    sta CIX
    lda ENTRY_NUMBER
    bmi SYNTAX_VARIABLE_TOO_MANY
    ora #TOKEN_VARIABLE
.if VERSION = VERSION_A
    jsr WRITE_TOKEN                 ; rev. A clears the carry after the call
    clc
    rts
.else
    clc
    jmp WRITE_TOKEN
.endif
SYNTAX_VARIABLE_TOO_MANY:
    jmp TOO_MANY_VARIABLES_ERROR

;; Tells whether the line's character at CIX is a letter.
;; In: INBUFF/CIX = the line
;; Out: carry = clear for a letter, A = the character, Y = CIX
;; Keeps: X
;; Entry: TEST_LETTER_IN_A = tests the character in A
TEST_LETTER:
    ldy CIX
    lda (INBUFF),y
TEST_LETTER_IN_A:
    cmp #'A'
    bcc TEST_LETTER_NO
    cmp #'Z'+1
    rts
TEST_LETTER_NO:
    sec
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

;; Syntax routine: reads a numeric constant from the line and writes it as TOKEN_NUMBER and its six bytes.
;;
;; The number is read by AFP, so it may have a sign and an exponent; a line number after THEN or in a statement is
;; read the same way. The six bytes are written without the token output buffer's check for its end.
;; In: INBUFF/CIX = the line
;; Out: carry = clear when a number is here, CIX = past it, FR0 = it
;; Errors: carry = set when there isn't one, CIX unchanged; 14 (ERR_LINE_TOO_LONG) when the token output buffer is
;;   full
;; Uses: A, X, Y, NAME_START, TOKEN_INDEX, FRE, FRX, EEXP, NSIGN, ESIGN, FCHRFLG, DIGRT
;; See: <AFP>
SYNTAX_NUMERIC_CONSTANT:
    jsr FP_SKIP_SPACES
    lda CIX
    sta NAME_START
    jsr AFP
    bcc SYNTAX_NUMERIC_CONSTANT_FOUND
    lda NAME_START                  ; AFP leaves CIX past what it tried
    sta CIX
    rts
SYNTAX_NUMERIC_CONSTANT_FOUND:
    lda #TOKEN_NUMBER
    jsr WRITE_TOKEN                 ; Y = where it went
.if VERSION = VERSION_A
    ldy TOKEN_INDEX                 ; rev. A reads the next place again
.else
    iny
.endif
    ldx #$00
SYNTAX_NUMERIC_CONSTANT_COPY:
    lda FR0,x
    sta (LOMEM),y
    iny
    inx
    cpx #FP_SIZE
    bcc SYNTAX_NUMERIC_CONSTANT_COPY
    sty TOKEN_INDEX
    clc
    rts

;; Syntax routine: reads a string constant from the line and writes it as TOKEN_STRING, its length and its characters.
;;
;; The string starts with a quote and ends with the next, which is left out, or at the end of the line: the closing
;; quote may be missing. A string can't hold a quote.
;; In: INBUFF/CIX = the line
;; Out: carry = clear when a string is here, CIX = past it
;; Errors: carry = set when there isn't one, 14 (ERR_LINE_TOO_LONG) when the token output buffer is full
;; Uses: A, Y, STRING_LENGTH_INDEX, TOKEN_INDEX
SYNTAX_STRING_CONSTANT:
    jsr FP_SKIP_SPACES
    ldy CIX
    lda (INBUFF),y
    cmp #'"'
.if VERSION = VERSION_A             ; rev. A returns by an RTS of its own, where the later revisions share one
    beq SYNTAX_STRING_CONSTANT_FOUND
    sec                             ; no string here
    rts
SYNTAX_STRING_CONSTANT_FOUND:
.else
    bne TEST_LETTER_NO              ; carry set: no string here
.endif
    lda #TOKEN_STRING
    jsr WRITE_TOKEN
    lda TOKEN_INDEX
    sta STRING_LENGTH_INDEX
    jsr WRITE_TOKEN                 ; room for the length
SYNTAX_STRING_CONSTANT_LOOP:
    inc CIX
    ldy CIX
    lda (INBUFF),y
    cmp #EOL
    beq SYNTAX_STRING_CONSTANT_LENGTH
    cmp #'"'
    beq SYNTAX_STRING_CONSTANT_QUOTE
    jsr WRITE_TOKEN
    jmp SYNTAX_STRING_CONSTANT_LOOP
SYNTAX_STRING_CONSTANT_QUOTE:
    inc CIX                         ; past the closing quote
SYNTAX_STRING_CONSTANT_LENGTH:
    clc                             ; the characters written after the length byte
    lda TOKEN_INDEX
    sbc STRING_LENGTH_INDEX
    ldy STRING_LENGTH_INDEX
    sta (LOMEM),y
.if VERSION >= VERSION_B            ; the later revisions share this RTS; rev. A has its own
SEARCH_NAMES_FOUND:
.endif
    clc                             ; from rev. B, also the end of SEARCH_NAMES, when it finds the name
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Searching a name table
; ---------------------------------------------------------------------------------------------------------------------

;; Searches a name table for a name in LBUFF at CIX.
;;
;; Each entry is NAME_OFFSET bytes (the statement name table's rule address, or none) and a name, its last character
;; with bit 7 set; the table ends where an entry's name starts with a zero byte. An entry matches when the line, from
;; CIX, starts with its whole name, with the line's bit 7 ignored: the first entry that matches is found.
;;
;; In the statement name table, a "." matches the rest of the name, so that the first statement whose name starts
;; with the letters before it is found: L. is LIST, and a "." alone is REM. In the other tables, the "." is compared
;; as $02, which only the operator name table's unused first name is.
;; In: A = the table's address, high byte, Y = its low byte, X = NAME_OFFSET, LBUFF/CIX = the name
;; Out:
;;   carry = clear when found, set when not
;;   ENTRY_NUMBER = the entry's number, from 0, or the number of entries when not found
;;   NAME_POINTER = the entry, or the end of the table
;;   X = the index in LBUFF past the name, or CIX when not found
;;   Y = the offset in the entry past its name, when found
;; Uses: A, NAME_OFFSET
;; Entry: SEARCH_NAMES_NEXT = goes on from the entry after the one found, with NAME_POINTER and Y as returned
SEARCH_NAMES:
    stx NAME_OFFSET
    ldx #$FF
    stx ENTRY_NUMBER
SEARCH_NAMES_ENTRY:
    sta NAME_POINTER+1
    sty NAME_POINTER
    inc ENTRY_NUMBER
    ldx CIX
    ldy NAME_OFFSET
    lda (NAME_POINTER),y
    beq SEARCH_NAMES_END
    lda #$00                        ; zero: matching so far
    php
SEARCH_NAMES_CHARACTER:
    lda LBUFF,x
    and #$7F
    cmp #'.'
    beq SEARCH_NAMES_PERIOD
SEARCH_NAMES_COMPARE:
    eor (NAME_POINTER),y
    asl A                           ; carry = the name's last character; zero = the same character
    beq SEARCH_NAMES_STEP
    pla                             ; replace the saved zero with not zero: a difference
    php
SEARCH_NAMES_STEP:
    iny
    inx
    bcc SEARCH_NAMES_CHARACTER
    plp
    beq SEARCH_NAMES_FOUND
SEARCH_NAMES_NEXT:
    clc                             ; the next entry is Y bytes on
    tya
    adc NAME_POINTER
    tay
    lda NAME_POINTER+1
    adc #$00
    bne SEARCH_NAMES_ENTRY          ; always
.if VERSION = VERSION_A
SEARCH_NAMES_FOUND:
    clc                             ; rev. A's own end for a name found
    rts
.endif
SEARCH_NAMES_END:
    sec
    rts
SEARCH_NAMES_PERIOD:
    lda #STATEMENT_NAME_OFFSET   ; the statement name table?
    cmp NAME_OFFSET
    bne SEARCH_NAMES_COMPARE
SEARCH_NAMES_SKIP:
    lda (NAME_POINTER),y            ; on to the name's last character
    bmi SEARCH_NAMES_ABBREVIATED
    iny
    bne SEARCH_NAMES_SKIP           ; always
SEARCH_NAMES_ABBREVIATED:
    sec                             ; the name's end, as matched so far
    bcs SEARCH_NAMES_STEP           ; always

; ---------------------------------------------------------------------------------------------------------------------
; The statement name table
; ---------------------------------------------------------------------------------------------------------------------

;; The statements' names and syntax rules, in the order of their tokens.
;;
;; Each entry is the address less 1 of the statement's rule in the syntax tables, then its name, the last character
;; with bit 7 set. The line editor finds a statement's name here with <SEARCH_NAMES>, where a "." abbreviates a name,
;; so the order chooses the abbreviations: L. is LIST, not LET. The lister and the error report print names from it.
;;
;; The implied LET's name is a zero byte, which ends the search: a statement without a name is the implied LET, by
;; the entry the search ends on. TOKEN_ERROR's name, "ERROR-  ", is what a line with a syntax error lists as and what
;; the error report prints; its rule address is never used.
;; See: <STATEMENT_ROUTINES>, <LIST_FIND_NAME>
STATEMENT_NAMES:
    STATEMENT TOKEN_REM, "REM", RULE_REM
    STATEMENT TOKEN_DATA, "DATA", RULE_DATA
    STATEMENT TOKEN_INPUT, "INPUT", RULE_INPUT
    STATEMENT TOKEN_COLOR, "COLOR", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_LIST, "LIST", RULE_LIST
    STATEMENT TOKEN_ENTER, "ENTER", RULE_FILE
    STATEMENT TOKEN_LET, "LET", RULE_LET
    STATEMENT TOKEN_IF, "IF", RULE_IF
    STATEMENT TOKEN_FOR, "FOR", RULE_FOR
    STATEMENT TOKEN_NEXT, "NEXT", RULE_NEXT
    STATEMENT TOKEN_GOTO, "GOTO", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_GO_TO, "GO TO", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_GOSUB, "GOSUB", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_TRAP, "TRAP", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_BYE, "BYE", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_CONT, "CONT", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_COM, "COM", RULE_DIM
    STATEMENT TOKEN_CLOSE, "CLOSE", RULE_CLOSE
    STATEMENT TOKEN_CLR, "CLR", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_DEG, "DEG", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_DIM, "DIM", RULE_DIM
    STATEMENT TOKEN_END, "END", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_NEW, "NEW", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_OPEN, "OPEN", RULE_OPEN
    STATEMENT TOKEN_LOAD, "LOAD", RULE_FILE
    STATEMENT TOKEN_SAVE, "SAVE", RULE_FILE
    STATEMENT TOKEN_STATUS, "STATUS", RULE_STATUS
    STATEMENT TOKEN_NOTE, "NOTE", RULE_NOTE
    STATEMENT TOKEN_POINT, "POINT", RULE_NOTE
    STATEMENT TOKEN_XIO, "XIO", RULE_XIO
    STATEMENT TOKEN_ON, "ON", RULE_ON
    STATEMENT TOKEN_POKE, "POKE", RULE_TWO_EXPRESSIONS
    STATEMENT TOKEN_PRINT, "PRINT", RULE_PRINT
    STATEMENT TOKEN_RAD, "RAD", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_READ, "READ", RULE_READ
    STATEMENT TOKEN_RESTORE, "RESTORE", RULE_RESTORE
    STATEMENT TOKEN_RETURN, "RETURN", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_RUN, "RUN", RULE_RUN
    STATEMENT TOKEN_STOP, "STOP", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_POP, "POP", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_QUESTION, "?", RULE_PRINT
    STATEMENT TOKEN_GET, "GET", RULE_GET
    STATEMENT TOKEN_PUT, "PUT", RULE_PUT
    STATEMENT TOKEN_GRAPHICS, "GRAPHICS", RULE_ONE_EXPRESSION
    STATEMENT TOKEN_PLOT, "PLOT", RULE_TWO_EXPRESSIONS
    STATEMENT TOKEN_POSITION, "POSITION", RULE_TWO_EXPRESSIONS
    STATEMENT TOKEN_DOS, "DOS", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_DRAWTO, "DRAWTO", RULE_TWO_EXPRESSIONS
    STATEMENT TOKEN_SETCOLOR, "SETCOLOR", RULE_SETCOLOR
    STATEMENT TOKEN_LOCATE, "LOCATE", RULE_LOCATE
    STATEMENT TOKEN_SOUND, "SOUND", RULE_SOUND
    STATEMENT TOKEN_LPRINT, "LPRINT", RULE_LPRINT
    STATEMENT TOKEN_CSAVE, "CSAVE", RULE_NO_ARGUMENTS
    STATEMENT TOKEN_CLOAD, "CLOAD", RULE_NO_ARGUMENTS
    .assert SYNTAX_STATEMENT_ENTRY = TOKEN_IMPLIED_LET, "The implied LET's entry follows CLOAD's."
    .word RULE_LET - 1              ; TOKEN_IMPLIED_LET: the rule for a statement without a name
    .byte 0, NAME_END               ; its name: a zero byte, which ends the search, and an empty name for the lister
    .word $2A00                     ; TOKEN_ERROR: a rule address no code reads
    NAME_TEXT "ERROR-  "

.if VERSION >= VERSION_B
;; "STOPPED ", which BASIC prints when STOP or BREAK stops the program, its last character with bit 7 set.
;;
;; Its last byte is also where the syntax checker's SYNTAX_EXPRESSION code points, as the address less 1 of
;; <RULE_EXPRESSION>. Rev. A keeps it among STOP's routines, and its SYNTAX_EXPRESSION points at the last byte of
;; "ERROR-  " instead.
STOPPED_MESSAGE:
    NAME_TEXT "STOPPED "
.endif

; ---------------------------------------------------------------------------------------------------------------------
; The syntax tables
; ---------------------------------------------------------------------------------------------------------------------

; Each rule's comment gives its grammar. A rule is named by its label in lower case without RULE_, with - for _;
; "..." is a name in the operator name table, matched after any spaces; (as X) is the token X written in place of
; the one matched; adjacent means without spaces before it; a routine's name is its call; and nothing is an
; alternative that matches nothing. A rule without a RETURN of its own continues into the rule after it.

; Rev. A's expression rule takes a unary operator before any expression, so NOT NOT A and - -A pass; the later
; revisions take one only before an operand or a parenthesis, with an unsigned-expression rule. (- -1 passes in
; every revision, the later ones reading -1 as a signed constant.)
.if VERSION = VERSION_A

;; The syntax tables' first rule, an expression's, which the other rules call by the code SYNTAX_EXPRESSION, as rev.
;; A has it.
;;
;; A unary operator may come before any expression, so NOT NOT A is an expression.
;; > expression = "(" expression ")" expression-rest | unary-operator expression | operand expression-rest
;; See: <CHECK_SYNTAX_CODE>
RULE_EXPRESSION:
    MATCH OP_OPEN_PAREN
    NEAR RULE_EXPRESSION
    MATCH OP_CLOSE_PAREN
    NEAR RULE_EXPRESSION_REST
    OR
    NEAR RULE_UNARY_OPERATOR
    NEAR RULE_EXPRESSION
    OR
    NEAR RULE_OPERAND
    NEAR RULE_EXPRESSION_REST
    RETURN
.else
;; The syntax tables' first rule, an expression's, which the other rules call by the code SYNTAX_EXPRESSION.
;;
;; The syntax tables are a grammar of Atari BASIC: from each statement's rule (<STATEMENT_NAMES>), the line editor's
;; syntax checker (<CHECK_SYNTAX>) matches the line, writing its tokens, and an alternative that fails goes back to
;; where it began, so the first alternative that matches is taken. The checker reaches these rules from
;; <CHECK_SYNTAX_NEXT> by these codes:
;;
;; - SYNTAX_CALL and a word (<FAR>), or SYNTAX_RELATIVE's codes (<NEAR>), match another rule;
;; - SYNTAX_ROUTINE and a word (<ROUTINE>) call a syntax routine;
;; - SYNTAX_OR (<OR>) separates the alternatives, and SYNTAX_RETURN (<RETURN>) ends the last;
;; - a token (<MATCH>, <MATCH_HERE>, which rev. A lacks) is matched by <MATCH_OPERATOR>; SYNTAX_REPLACE (<REPLACE>)
;;   changes the token just written, as the = of LET to OP_ASSIGN_NUMBER, and SYNTAX_EXPRESSION (<EXPRESSION>)
;;   matches this rule.
;;
;; A failed alternative's codes are skipped by their sizes, without knowing their meaning, to the next SYNTAX_OR or
;; SYNTAX_RETURN. Rules lie near the rules that call them, so that most calls are NEAR's one byte, and some rules
;; have a copy further on (<RULE_STATEMENT_END_2>) or a stepping stone (<RULE_FILESPEC>) to be near their callers
;; too.
;;
;; An expression's grammar: a string is a number in an expression only by a comparison of strings, and an operand
;; can't be a unary operator's, so NOT NOT A is a syntax error.
;; > expression = unary-operator unsigned-expression | unsigned-expression
;; See: <CHECK_SYNTAX_CODE>
RULE_EXPRESSION:
    NEAR RULE_UNARY_OPERATOR
    NEAR RULE_UNSIGNED_EXPRESSION
    OR
    NEAR RULE_UNSIGNED_EXPRESSION
    RETURN

; unsigned-expression = "(" expression ")" expression-rest | operand expression-rest
RULE_UNSIGNED_EXPRESSION:
    MATCH OP_OPEN_PAREN
    NEAR RULE_EXPRESSION
    MATCH OP_CLOSE_PAREN
    NEAR RULE_EXPRESSION_REST
    OR
    NEAR RULE_OPERAND
    NEAR RULE_EXPRESSION_REST
    RETURN
.endif

; unary-operator = "+" (as OP_PLUS) | "-" (as OP_MINUS) | "NOT"
RULE_UNARY_OPERATOR:
    MATCH OP_ADD
    REPLACE OP_PLUS
    OR
    MATCH OP_SUBTRACT
    REPLACE OP_MINUS
    OR
    MATCH OP_NOT
    RETURN

; operand = function | numeric-variable | SYNTAX_NUMERIC_CONSTANT | string-comparison
RULE_OPERAND:
    NEAR RULE_FUNCTION
    OR
    NEAR RULE_NUMERIC_VARIABLE
    OR
    ROUTINE SYNTAX_NUMERIC_CONSTANT
    OR
    FAR RULE_STRING_COMPARISON
    RETURN

; expression-rest = binary-operator expression | nothing
RULE_EXPRESSION_REST:
    NEAR RULE_BINARY_OPERATOR
    NEAR RULE_EXPRESSION
    OR
    RETURN

; binary-operator = "^" | "+" | "-" | "*" | "/" | "<=" | ">=" | "<>" | "<" | ">" | "=" | "AND" | "OR"
RULE_BINARY_OPERATOR:
    MATCH OP_POWER
    OR
    MATCH OP_ADD
    OR
    MATCH OP_SUBTRACT
    OR
    MATCH OP_MULTIPLY
    OR
    MATCH OP_DIVIDE
    OR
    MATCH OP_LE
    OR
    MATCH OP_GE
    OR
    MATCH OP_NE
    OR
    MATCH OP_LT
    OR
    MATCH OP_GT
    OR
    MATCH OP_EQ
    OR
    MATCH OP_AND
    OR
    MATCH OP_OR
    RETURN

; numeric-variable = SYNTAX_NUMERIC_VARIABLE subscripts
RULE_NUMERIC_VARIABLE:
    ROUTINE SYNTAX_NUMERIC_VARIABLE
    NEAR RULE_SUBSCRIPTS
    RETURN

; subscripts = "(" (adjacent, as OP_ARRAY_PAREN) expression second-subscript ")" | nothing
RULE_SUBSCRIPTS:
.if VERSION = VERSION_A
    MATCH OP_OPEN_PAREN             ; rev. A skips spaces before the (, so X (1) passes as an element of the variable X
.else
    MATCH_HERE OP_OPEN_PAREN
.endif
    REPLACE OP_ARRAY_PAREN
    EXPRESSION
    NEAR RULE_SECOND_SUBSCRIPT
    MATCH OP_CLOSE_PAREN
    OR
    RETURN

; second-subscript = "," (as OP_ARRAY_COMMA) expression | nothing
RULE_SECOND_SUBSCRIPT:
    MATCH OP_COMMA
    REPLACE OP_ARRAY_COMMA
    EXPRESSION
    OR
    RETURN

; function = "ATN"... numeric-argument | string-number-function string-argument | usr
; "ATN"... is any function from ATN on: ATN, COS, PEEK, SIN, RND, FRE, EXP, LOG, CLOG, SQR, SGN, ABS, INT, PADDLE,
; STICK, PTRIG and STRIG.
RULE_FUNCTION:
    MATCH FN_ATN
    NEAR RULE_NUMERIC_ARGUMENT
    OR
    FAR RULE_STRING_NUMBER_FUNCTION
    NEAR RULE_STRING_ARGUMENT
    OR
    NEAR RULE_USR
    RETURN

; usr = "USR" "(" (as OP_FUNCTION_PAREN) usr-arguments ")"
RULE_USR:
    MATCH FN_USR
    MATCH OP_OPEN_PAREN
    REPLACE OP_FUNCTION_PAREN
    FAR RULE_USR_ARGUMENTS
    MATCH OP_CLOSE_PAREN
    RETURN

; numeric-argument = "(" (as OP_FUNCTION_PAREN) expression ")"
RULE_NUMERIC_ARGUMENT:
    MATCH OP_OPEN_PAREN
    REPLACE OP_FUNCTION_PAREN
    EXPRESSION
    MATCH OP_CLOSE_PAREN
    RETURN

; string-argument = "(" (as OP_FUNCTION_PAREN) string ")"
RULE_STRING_ARGUMENT:
    MATCH OP_OPEN_PAREN
    REPLACE OP_FUNCTION_PAREN
    NEAR RULE_STRING
    MATCH OP_CLOSE_PAREN
    RETURN

; string-comparison = string string-operator string
RULE_STRING_COMPARISON:
    NEAR RULE_STRING
    NEAR RULE_STRING_OPERATOR
    NEAR RULE_STRING
    RETURN

; string = string-function | string-variable | SYNTAX_STRING_CONSTANT
RULE_STRING:
    NEAR RULE_STRING_FUNCTION
    OR
    NEAR RULE_STRING_VARIABLE
    OR
    ROUTINE SYNTAX_STRING_CONSTANT
    RETURN

; string-function = string-function-name numeric-argument
RULE_STRING_FUNCTION:
    FAR RULE_STRING_FUNCTION_NAME
    NEAR RULE_NUMERIC_ARGUMENT
    RETURN

; string-variable = SYNTAX_STRING_VARIABLE substring
RULE_STRING_VARIABLE:
    ROUTINE SYNTAX_STRING_VARIABLE
    NEAR RULE_SUBSTRING
    RETURN

; substring = "(" (as OP_STRING_PAREN) expression substring-end ")" | nothing
RULE_SUBSTRING:
    MATCH OP_OPEN_PAREN
    REPLACE OP_STRING_PAREN
    EXPRESSION
    NEAR RULE_SUBSTRING_END
    MATCH OP_CLOSE_PAREN
    OR
    RETURN

; substring-end = "," (as OP_ARRAY_COMMA) expression | nothing
RULE_SUBSTRING_END:
    MATCH OP_COMMA
    REPLACE OP_ARRAY_COMMA
    EXPRESSION
    OR
    RETURN

; string-operator = "<=" (as OP_STRING_LE) | "<>" (as OP_STRING_NE) | ">=" (as OP_STRING_GE) | "<" (as OP_STRING_LT)
;   | ">" (as OP_STRING_GT) | "=" (as OP_STRING_EQ)
RULE_STRING_OPERATOR:
    MATCH OP_LE
    REPLACE OP_STRING_LE
    OR
    MATCH OP_NE
    REPLACE OP_STRING_NE
    OR
    MATCH OP_GE
    REPLACE OP_STRING_GE
    OR
    MATCH OP_LT
    REPLACE OP_STRING_LT
    OR
    MATCH OP_GT
    REPLACE OP_STRING_GT
    OR
    MATCH OP_EQ
    REPLACE OP_STRING_EQ
    RETURN

; The statements' rules, and the rules they share.

; put = "#" expression "," one-expression
RULE_PUT:
    MATCH OP_HASH
    EXPRESSION
    MATCH OP_COMMA
; one-expression = expression no-arguments: COLOR, GOTO, GO TO, GOSUB, TRAP and GRAPHICS
RULE_ONE_EXPRESSION:
    EXPRESSION
; no-arguments = statement-end: BYE, CONT, CLR, DEG, END, NEW, RAD, RETURN, STOP, POP, DOS, CSAVE and CLOAD
RULE_NO_ARGUMENTS:
    NEAR RULE_STATEMENT_END
    RETURN

; let = numeric-variable "=" (as OP_ASSIGN_NUMBER) expression statement-end
;   | string-variable "=" (as OP_ASSIGN_STRING) string statement-end
; LET's, and the implied LET's.
RULE_LET:
    FAR RULE_NUMERIC_VARIABLE
    MATCH OP_EQ
    REPLACE OP_ASSIGN_NUMBER
    EXPRESSION
    NEAR RULE_STATEMENT_END
    OR
    NEAR RULE_STRING_VARIABLE
    MATCH OP_EQ
    REPLACE OP_ASSIGN_STRING
    FAR RULE_STRING
    NEAR RULE_STATEMENT_END
    RETURN

; for = SYNTAX_NUMERIC_VARIABLE "=" (as OP_ASSIGN_NUMBER) expression "TO" expression step statement-end
RULE_FOR:
    ROUTINE SYNTAX_NUMERIC_VARIABLE
    MATCH OP_EQ
    REPLACE OP_ASSIGN_NUMBER
    EXPRESSION
    MATCH OP_TO
    EXPRESSION
    NEAR RULE_STEP
    NEAR RULE_STATEMENT_END
    RETURN

; step = "STEP" expression | nothing
RULE_STEP:
    MATCH OP_STEP
    EXPRESSION
    OR
    RETURN

; locate = expression "," expression "," next
RULE_LOCATE:
    EXPRESSION
    MATCH OP_COMMA
    EXPRESSION
    MATCH OP_COMMA
    NEAR RULE_NEXT
    RETURN

; get = iocb "," next
RULE_GET:
    NEAR RULE_IOCB
    MATCH OP_COMMA
; next = SYNTAX_NUMERIC_VARIABLE statement-end
RULE_NEXT:
    ROUTINE SYNTAX_NUMERIC_VARIABLE
    NEAR RULE_STATEMENT_END
    RETURN

; restore = expression statement-end | statement-end
RULE_RESTORE:
    EXPRESSION
    NEAR RULE_STATEMENT_END
    OR
    NEAR RULE_STATEMENT_END
    RETURN

; input = iocb-prefix read
RULE_INPUT:
    NEAR RULE_IOCB_PREFIX
; read = variable-list statement-end
RULE_READ:
    NEAR RULE_VARIABLE_LIST
    NEAR RULE_STATEMENT_END
    RETURN

; statement-end = ":" | end-of-line
; The end of the line is matched as TOKEN_LINE_END's name, the line's EOL.
RULE_STATEMENT_END:
    MATCH TOKEN_STATEMENT_END
    OR
    MATCH TOKEN_LINE_END
    RETURN

; print = iocb statement-end | iocb-prefix lprint
RULE_PRINT:
    NEAR RULE_IOCB
    NEAR RULE_STATEMENT_END
    OR
    NEAR RULE_IOCB_PREFIX
; lprint = print-list statement-end
RULE_LPRINT:
    FAR RULE_PRINT_LIST
    NEAR RULE_STATEMENT_END
    RETURN

; iocb = "#" expression
RULE_IOCB:
    MATCH OP_HASH
    EXPRESSION
    RETURN

; input-variable = SYNTAX_NUMERIC_VARIABLE | SYNTAX_STRING_VARIABLE
; Without subscripts: INPUT and READ can't read into an array's element or a substring.
RULE_INPUT_VARIABLE:
    ROUTINE SYNTAX_NUMERIC_VARIABLE
    OR
    ROUTINE SYNTAX_STRING_VARIABLE
    RETURN

; variable-list = input-variable more-variables
; Rev. A's: input-variable more-variables | nothing, so INPUT and READ pass with no variable.
RULE_VARIABLE_LIST:
    NEAR RULE_INPUT_VARIABLE
    NEAR RULE_MORE_VARIABLES
.if VERSION = VERSION_A             ; rev. A lets the list be empty
    OR
.endif
    RETURN

; more-variables = "," variable-list | nothing
RULE_MORE_VARIABLES:
    MATCH OP_COMMA
    NEAR RULE_VARIABLE_LIST
    OR
    RETURN

; xio = expression "," open
RULE_XIO:
    EXPRESSION
    MATCH OP_COMMA
; open = iocb "," expression-pair "," filespec statement-end
RULE_OPEN:
    NEAR RULE_IOCB
    MATCH OP_COMMA
    NEAR RULE_EXPRESSION_PAIR
    MATCH OP_COMMA
    NEAR RULE_FILESPEC
    NEAR RULE_STATEMENT_END
    RETURN

; close = iocb statement-end
RULE_CLOSE:
    NEAR RULE_IOCB
    NEAR RULE_STATEMENT_END
    RETURN

; file = filespec statement-end: ENTER, LOAD and SAVE
RULE_FILE:
    NEAR RULE_FILESPEC
    NEAR RULE_STATEMENT_END
    RETURN

; run = filespec statement-end | statement-end
RULE_RUN:
    NEAR RULE_FILESPEC
    NEAR RULE_STATEMENT_END
    OR
    NEAR RULE_STATEMENT_END
    RETURN

; iocb-prefix = iocb "," | iocb ";" | nothing
RULE_IOCB_PREFIX:
    NEAR RULE_IOCB
    MATCH OP_COMMA
    OR
    NEAR RULE_IOCB
    MATCH OP_SEMICOLON
    OR
    RETURN

; list = filespec statement-end | filespec "," line-range | line-range
RULE_LIST:
    NEAR RULE_FILESPEC
    NEAR RULE_STATEMENT_END
    OR
    NEAR RULE_FILESPEC
    MATCH OP_COMMA
    NEAR RULE_LINE_RANGE
    OR
    NEAR RULE_LINE_RANGE
    RETURN

; line-range = line-numbers statement-end-2
RULE_LINE_RANGE:
    FAR RULE_LINE_NUMBERS
    NEAR RULE_STATEMENT_END_2
    RETURN

; status = iocb-variable statement-end-2
RULE_STATUS:
    NEAR RULE_IOCB_VARIABLE
    NEAR RULE_STATEMENT_END_2
    RETURN

; iocb-variable = iocb "," numeric-variable
RULE_IOCB_VARIABLE:
    NEAR RULE_IOCB
    MATCH OP_COMMA
    FAR RULE_NUMERIC_VARIABLE
    RETURN

; note = iocb-variable "," numeric-variable statement-end-2: NOTE and POINT
RULE_NOTE:
    NEAR RULE_IOCB_VARIABLE
    MATCH OP_COMMA
    FAR RULE_NUMERIC_VARIABLE
    NEAR RULE_STATEMENT_END_2
    RETURN

; filespec = string
; A stepping stone to string, within the reach of NEAR.
RULE_FILESPEC:
    FAR RULE_STRING
    RETURN

; expression-pair = expression "," expression
RULE_EXPRESSION_PAIR:
    EXPRESSION
    MATCH OP_COMMA
    EXPRESSION
    RETURN

; sound = expression "," setcolor
RULE_SOUND:
    EXPRESSION
    MATCH OP_COMMA
; setcolor = expression "," two-expressions
RULE_SETCOLOR:
    EXPRESSION
    MATCH OP_COMMA
; two-expressions = expression-pair statement-end-2: POKE, PLOT, POSITION and DRAWTO
RULE_TWO_EXPRESSIONS:
    NEAR RULE_EXPRESSION_PAIR
    NEAR RULE_STATEMENT_END_2
    RETURN

; dim = dim-list statement-end-2: DIM and COM
RULE_DIM:
    NEAR RULE_DIM_LIST
    NEAR RULE_STATEMENT_END_2
    RETURN

; on = expression goto-or-gosub expression-list statement-end-2
RULE_ON:
    EXPRESSION
    NEAR RULE_GOTO_OR_GOSUB
    NEAR RULE_EXPRESSION_LIST
    NEAR RULE_STATEMENT_END_2
    RETURN

; goto-or-gosub = "GOTO" | "GOSUB"
RULE_GOTO_OR_GOSUB:
    MATCH OP_GOTO
    OR
    MATCH OP_GOSUB
    RETURN

; expression-list = expression more-expressions
RULE_EXPRESSION_LIST:
    EXPRESSION
    NEAR RULE_MORE_EXPRESSIONS
    RETURN

; more-expressions = "," expression-list | nothing
RULE_MORE_EXPRESSIONS:
    MATCH OP_COMMA
    NEAR RULE_EXPRESSION_LIST
    OR
    RETURN

; statement-end-2 = ":" | end-of-line
; A copy of statement-end within the reach of NEAR.
RULE_STATEMENT_END_2:
    MATCH TOKEN_STATEMENT_END
    OR
    MATCH TOKEN_LINE_END
    RETURN

; dim-item = SYNTAX_NUMERIC_VARIABLE "(" (adjacent, as OP_DIM_ARRAY_PAREN) expression second-subscript ")"
;   | SYNTAX_STRING_VARIABLE "(" (as OP_DIM_STRING_PAREN) expression ")"
RULE_DIM_ITEM:
    ROUTINE SYNTAX_NUMERIC_VARIABLE
.if VERSION = VERSION_A
    MATCH OP_OPEN_PAREN             ; rev. A skips spaces before the (
.else
    MATCH_HERE OP_OPEN_PAREN
.endif
    REPLACE OP_DIM_ARRAY_PAREN
    EXPRESSION
    FAR RULE_SECOND_SUBSCRIPT
    MATCH OP_CLOSE_PAREN
    OR
    ROUTINE SYNTAX_STRING_VARIABLE
    MATCH OP_OPEN_PAREN
    REPLACE OP_DIM_STRING_PAREN
    EXPRESSION
    MATCH OP_CLOSE_PAREN
    RETURN

; dim-list = dim-item more-dim-items | nothing
; So DIM with nothing, or with a comma at the end, passes the syntax check.
RULE_DIM_LIST:
    NEAR RULE_DIM_ITEM
    NEAR RULE_MORE_DIM_ITEMS
    OR
    RETURN

; more-dim-items = "," dim-list | nothing
RULE_MORE_DIM_ITEMS:
    MATCH OP_COMMA
    NEAR RULE_DIM_LIST
    OR
    RETURN

; if = expression "THEN" then statement-end-2
RULE_IF:
    EXPRESSION
    MATCH OP_THEN
    NEAR RULE_THEN
    NEAR RULE_STATEMENT_END_2
    RETURN

; then = SYNTAX_NUMERIC_CONSTANT | SYNTAX_END_STATEMENT
; A line number, or a statement: SYNTAX_END_STATEMENT ends IF's statement there, and the line editor goes on to
; the next, so it never comes back and the rule needs no RETURN.
RULE_THEN:
    ROUTINE SYNTAX_NUMERIC_CONSTANT
    OR
    ROUTINE SYNTAX_END_STATEMENT

; print-list = print-items | print-separators optional-print-items | nothing
RULE_PRINT_LIST:
    NEAR RULE_PRINT_ITEMS
    OR
    NEAR RULE_PRINT_SEPARATORS
    NEAR RULE_OPTIONAL_PRINT_ITEMS
    OR
    RETURN

; optional-print-items = print-items | nothing
RULE_OPTIONAL_PRINT_ITEMS:
    NEAR RULE_PRINT_ITEMS
    OR
    RETURN

; print-items = print-item more-print-items
RULE_PRINT_ITEMS:
    NEAR RULE_PRINT_ITEM
    NEAR RULE_MORE_PRINT_ITEMS
    RETURN

; print-item = expression | string
RULE_PRINT_ITEM:
    EXPRESSION
    OR
    FAR RULE_STRING
    RETURN

; more-print-items = print-separators optional-print-items | nothing
RULE_MORE_PRINT_ITEMS:
    NEAR RULE_PRINT_SEPARATORS
    NEAR RULE_OPTIONAL_PRINT_ITEMS
    OR
    RETURN

; print-separators = print-separator more-print-separators
RULE_PRINT_SEPARATORS:
    NEAR RULE_PRINT_SEPARATOR
    NEAR RULE_MORE_PRINT_SEPARATORS
    RETURN

; more-print-separators = print-separators | nothing
RULE_MORE_PRINT_SEPARATORS:
    NEAR RULE_PRINT_SEPARATORS
    OR
    RETURN

; print-separator = "," | ";"
RULE_PRINT_SEPARATOR:
    MATCH OP_COMMA
    OR
    MATCH OP_SEMICOLON
    RETURN

; line-numbers = expression second-line-number | nothing
RULE_LINE_NUMBERS:
    EXPRESSION
    NEAR RULE_SECOND_LINE_NUMBER
    OR
    RETURN

; second-line-number = "," expression | nothing
RULE_SECOND_LINE_NUMBER:
    MATCH OP_COMMA
    EXPRESSION
    OR
    RETURN

; rem = SYNTAX_REST_OF_LINE
; The rest of the line is kept as typed; the routine goes back to the line editor, never to the rule.
RULE_REM:
    ROUTINE SYNTAX_REST_OF_LINE

; data = SYNTAX_REST_OF_LINE
RULE_DATA:
    ROUTINE SYNTAX_REST_OF_LINE

; string-number-function = "ASC" | "VAL" | "ADR" | "LEN"
RULE_STRING_NUMBER_FUNCTION:
    MATCH FN_ASC
    OR
    MATCH FN_VAL
    OR
    MATCH FN_ADR
    OR
    MATCH FN_LEN
    RETURN

; string-function-name = "STR$" | "CHR$"
RULE_STRING_FUNCTION_NAME:
    MATCH FN_STR
    OR
    MATCH FN_CHR
    RETURN

; usr-arguments = expression more-usr-arguments
RULE_USR_ARGUMENTS:
    EXPRESSION
    NEAR RULE_MORE_USR_ARGUMENTS
    RETURN

; more-usr-arguments = "," (as OP_ARRAY_COMMA) usr-arguments | nothing
RULE_MORE_USR_ARGUMENTS:
    MATCH OP_COMMA
    REPLACE OP_ARRAY_COMMA
    NEAR RULE_USR_ARGUMENTS
    OR
    RETURN

; ---------------------------------------------------------------------------------------------------------------------
; The operator name table
; ---------------------------------------------------------------------------------------------------------------------

;; The names of the operators, from OPERATOR_NAMES_FIRST, then of the functions, in the order of their tokens.
;;
;; Each name's last character has bit 7 set, and a zero byte ends the table. <MATCH_OPERATOR> searches it for the
;; token a rule wants, and the lister prints a token's name from it. The search finds the first of two equal names,
;; so the tokens from OP_ASSIGN_NUMBER on, which <REPLACE> writes, are found only by their tokens, for the lister.
;; No rule wants the tokens $10, OP_SENTINEL, OP_ARRAY_PAREN or OP_DIM_ARRAY_PAREN. No line holds $10; the others
;; have empty names and list as nothing.
;; See: <OPERATOR_ROUTINES>, <SEARCH_NAMES>
OPERATOR_NAMES:
    OPERATOR_CHARACTER $10, $02     ; a token no line holds: its name appears to be a placeholder
    OPERATOR_CHARACTER OP_SENTINEL, 0
    OPERATOR OP_COMMA, ","
    OPERATOR OP_DOLLAR, "$"
    OPERATOR TOKEN_STATEMENT_END, ":"
    OPERATOR OP_SEMICOLON, ";"
    OPERATOR_CHARACTER TOKEN_LINE_END, EOL  ; the line's EOL, which matches it and ends its listing
    OPERATOR OP_GOTO, "GOTO"
    OPERATOR OP_GOSUB, "GOSUB"
    OPERATOR OP_TO, "TO"
    OPERATOR OP_STEP, "STEP"
    OPERATOR OP_THEN, "THEN"
    OPERATOR OP_HASH, "#"
    OPERATOR OP_LE, "<="
    OPERATOR OP_NE, "<>"
    OPERATOR OP_GE, ">="
    OPERATOR OP_LT, "<"
    OPERATOR OP_GT, ">"
    OPERATOR OP_EQ, "="
    OPERATOR OP_POWER, "^"
    OPERATOR OP_MULTIPLY, "*"
    OPERATOR OP_ADD, "+"
    OPERATOR OP_SUBTRACT, "-"
    OPERATOR OP_DIVIDE, "/"
    OPERATOR OP_NOT, "NOT"
    OPERATOR OP_OR, "OR"
    OPERATOR OP_AND, "AND"
    OPERATOR OP_OPEN_PAREN, "("
    OPERATOR OP_CLOSE_PAREN, ")"
    OPERATOR OP_ASSIGN_NUMBER, "="
    OPERATOR OP_ASSIGN_STRING, "="
    OPERATOR OP_STRING_LE, "<="
    OPERATOR OP_STRING_NE, "<>"
    OPERATOR OP_STRING_GE, ">="
    OPERATOR OP_STRING_LT, "<"
    OPERATOR OP_STRING_GT, ">"
    OPERATOR OP_STRING_EQ, "="
    OPERATOR OP_PLUS, "+"
    OPERATOR OP_MINUS, "-"
    OPERATOR OP_STRING_PAREN, "("
    OPERATOR_CHARACTER OP_ARRAY_PAREN, 0        ; the array's name ends with its own (
    OPERATOR_CHARACTER OP_DIM_ARRAY_PAREN, 0
    OPERATOR OP_FUNCTION_PAREN, "("
    OPERATOR OP_DIM_STRING_PAREN, "("
    OPERATOR OP_ARRAY_COMMA, ","
    OPERATOR FN_STR, "STR$"
    OPERATOR FN_CHR, "CHR$"
    OPERATOR FN_USR, "USR"
    OPERATOR FN_ASC, "ASC"
    OPERATOR FN_VAL, "VAL"
    OPERATOR FN_LEN, "LEN"
    OPERATOR FN_ADR, "ADR"
    OPERATOR FN_ATN, "ATN"
    OPERATOR FN_COS, "COS"
    OPERATOR FN_PEEK, "PEEK"
    OPERATOR FN_SIN, "SIN"
    OPERATOR FN_RND, "RND"
    OPERATOR FN_FRE, "FRE"
    OPERATOR FN_EXP, "EXP"
    OPERATOR FN_LOG, "LOG"
    OPERATOR FN_CLOG, "CLOG"
    OPERATOR FN_SQR, "SQR"
    OPERATOR FN_SGN, "SGN"
    OPERATOR FN_ABS, "ABS"
    OPERATOR FN_INT, "INT"
    OPERATOR FN_PADDLE, "PADDLE"
    OPERATOR FN_STICK, "STICK"
    OPERATOR FN_PTRIG, "PTRIG"
    OPERATOR FN_STRIG, "STRIG"
    .byte 0                         ; the end of the table
