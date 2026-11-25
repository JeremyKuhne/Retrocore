; retrocore: style=strict
;; Finding variables: `DIM`, <FindVariable>'s search of the simple variable and array tables, which makes a variable
;; it does not find, the tables of each type's size and type byte, the start of making an array
;; (<Variables::CreateArray>; B3UdefI.asm finishes it), and helpers to push the <FAC> for `FOR` and to make the <FAC> a
;; 16-bit integer.
;;
;; Variables live after the program: the array table from <ARYTAB> to <VARTAB> (also called <SMVARS>), then the simple
;; variable table from <VARTAB> to <STREND>. Strings grow down from <FRETOP> to meet them. Every pointer into this space
;; is three bytes: the low byte, a page kept in $02-$81, and the X-byte ($80 + the bank pair) in the X-byte page. A
;; page past $81 goes on at $02 through the next X-byte, so the space reads as one run of memory, 32K per X-byte.
;;
;; A simple variable's entry is one length byte (the whole entry's), the name, a type byte and the value:
;;
;; > length | name (n bytes) | type | value
;;
;; An array's entry has a two-byte length (low byte first), then the name, the type, the count of dimensions, each
;; dimension's size (high byte first, the last subscript's first), then the elements, the first subscript varying
;; fastest:
;;
;; > length (2) | name (n bytes) | type | count | sizes (2 per dimension) | elements
;;
;; Names are kept in upper case without their type character; in the program a name, with its type character, may be
;; up to <Variables::MAXIMUM_NAME_LENGTH> characters.

; ---------------------------------------------------------------------------------------------------------------------
; Types and sizes
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued

;; The longest name, its type character included.
MAXIMUM_NAME_LENGTH = 64

;; The highest subscript of each dimension of an array made without `DIM`.
DEFAULT_HIGHEST_SUBSCRIPT = 10

;; The type byte of an integer (`%`) variable; <FindVariable> turns it into <INTFLG> set with a real's <VALTYP>.
TYPE_INTEGER = $80

;; The type byte of a byte (`!`) variable, which can only be an array.
TYPE_BYTE = $C0

;; The type byte of a function `DEF FN` makes, whose name has no type character.
TYPE_FUNCTION = $10

;; The bytes of a real's value: the exponent, then the mantissa's top three bytes, the sign in bit 7 of the first.
SIZE_REAL = 4

;; The bytes of a byte (`!`) variable's value.
SIZE_BYTE = 1

;; The bytes of an integer's value, high byte first.
SIZE_INTEGER = 2

;; The bytes of a long integer's value, two's complement, high byte first.
SIZE_LONG_INTEGER = 8

;; The bytes of a function's value: the formula's address and the argument variable's, three bytes each.
SIZE_FUNCTION = 6

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `DIM` and the variable search
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued

;; `DIM`'s loop: after each array, a comma brings the next one.
;; See: <Statements::Dim>
;; Also: DIM3 (BB13)
.proc DimNextArray
    jsr CheckComma
    ; Falls into Dim.
.endproc

;; The `DIM` statement: makes each array named, sized by its subscripts.
;;
;; <DIMFLG>, which <FindVariable::WithDimensionFlag> takes from X, is the array name's first letter, so its bit 6 is
;; set; the search tests that bit to size a new array from the subscripts, to refuse an array that exists, and to
;; stop before indexing it.
;; In: A = the character after `DIM`
;; See: <Variables::FindArray>, <Variables::CreateArray>
;; Also: DIM (BB13)
.proc Dim
    tax                                     ; DIMFLG: the first letter, bit 6 set
    lda #0
    sta DORES                               ; arrays not found are made
    jsr FindVariable::WithDimensionFlag
    jsr CHRGOT
    bne DimNextArray
    rts
.endproc

.endscope

;; Reads the variable name at <TXTPTR> and finds its value, making the variable when it does not exist.
;;
;; An array's subscripts are evaluated as formulas, which can call this again, so the array search keeps its state
;; on the stack. A simple variable or an array element not yet used is made, zeroed; an array not yet used is made
;; with 11 elements (0-10) in each dimension given.
;; In: TXTPTR = the variable's name
;; Out: VARPNT = the value's address (<VARPNTB> its bank), A = its low byte, Y = its page, TXTPTR = past the name and
;;   any subscripts, VALTYP = 0 for a number, $FF for a string or $40 for a long integer, INTFLG = $80 for an integer,
;;   ISARA = $80 for an array element, 0 for a simple variable
;; Errors: ERRSN = a bad name or one longer than 64 characters, ERRBS = the wrong count of subscripts or one past the
;;   array's size, ERRFC = a negative or too large subscript, ERRDD = `DIM` of an array that exists, ERROM = no room
;; Entry:
;;   ForExpression = with X nonzero, an array not found is not made: VARPNT points to a zero (<ZERO>) instead, as
;;     <EvaluateVariable> wants
;;   WithDimensionFlag = takes <DIMFLG> from X; <Statements::Dim> enters here
;;   KeepDimensionFlag = takes <DIMFLG>, <DORES> and <SUBFLG> as they are; `FN`'s name and `DEF`'s argument enter here
;;   ValidFirst = reads a name whose first letter TXTPTR is at, with <DIMFLG>, <DORES> and <SUBFLG> set; the table of
;;     routines for modules, in Catalog.asm, gives it
;;   PointAtValue = points VARPNT at the value A plus carry bytes into the entry at <SRCHPT>; <Variables::Create>
;;     goes here
;;   SetIntegerFlag = sorts out an integer's type and returns; <Variables::ElementAddress> goes here
;; See: <IsLetter>, <Variables::ValueSizes>, <Variables::FindArray>
;; Also: PTRGET (BB13)
.proc FindVariable
    ldx #0                                  ; DORES: make arrays not found

;; With X nonzero, an array not found is not made: <VARPNT> points to a zero (<ZERO>) instead, as the expression
;; evaluator wants.
;; In: X = nonzero not to make an array not found, TXTPTR = the variable's name
;; Also: PTREVL (BB13)
ForExpression:
    stx DORES
    ldx #0                                  ; not in `DIM`

;; Takes <DIMFLG> from X; <Statements::Dim> enters here.
;; In: X = <DIMFLG>, nonzero in `DIM`, TXTPTR = the variable's name
;; Also: PTRGT1 (BB13)
WithDimensionFlag:
    stx DIMFLG

;; Takes <DIMFLG>, <DORES> and SUBFLG as they are; `FN`'s name and `DEF`'s argument enter here with SUBFLG set.
;; In: SUBFLG = $80 for `DEF`'s argument (no subscripts), bits 7 and 6 for an `FN` name, TXTPTR = the variable's name
;; See: <ReadFunctionName::AfterFn>, <Statements::Def>
;; Also: PTRGT2 (BB13)
KeepDimensionFlag:
    jsr CHRGOT
    jsr IsLetter
    bcs ValidFirst

;; Ends the statement with SYNTAX <ERROR>, for a variable name that is not one.
;; Also: WRDERR (BB13)
ToSyntaxError:
    jmp SyntaxError

;; Starts with a letter: notes where the name starts, in <LOWDS> and <TMPPTR>, and reads to its end.
;; Also: PTRGT3 (BB13)
ValidFirst:
    ldx #0
    stx INTFLG                              ; a real unless the name says otherwise
    stx ISARA                               ; and a simple variable
    lda TXTPTR
    sta LOWDS
    sta TMPPTR
    lda TXTPTR+1
    sta LOWDS+1
    sta TMPPTR+1
    lda TXTPTRB
    sta LOWDSB
    sta TMPPTRB

;; Skips the name's letters, digits and periods.
;; Also: EATEM (BB13)
SkipRest:
    jsr CHRGET
    bcc SkipRest                            ; a digit
    jsr IsLetter
    bcs SkipRest
    cmp #'.'
    beq SkipRest
    cmp #'!'                                ; the type character, if any: ! $ % or &
    beq TypeCharacter
    cmp #'&'+1
    bcs LookUpType
    cmp #'$'
    bcc LookUpType

;; Turns the type character into an index in <Variables::ValueSizes>, refusing one on an `FN` name, and steps past it.
;; Also: GOTTYP (BB13)
TypeCharacter:
    adc #$100-'!'                           ; carry set: ! is 1, $ is 4, % is 5, & is 6
    tax
    bit SUBFLG
    bmi ToSyntaxError                       ; `FN` names are real
    jsr CHRGET

;; Looks up the type's value size and type byte, and works out the name's length.
;;
;; A real's name has no type character, so its length gets 1 here to match the others: <FOUR6> is the name's length
;; plus 1 in every case. An `FN` name gets type <Variables::TYPE_FUNCTION> and a value of
;; <Variables::SIZE_FUNCTION> bytes.
;; Also: REAL (BB13)
LookUpType:
    ldy a:Variables::ValueSizes,X
    sty VARNAM                              ; the value's size
    pha                                     ; the character after the name
    lda TXTPTR
    sec
    sbc LOWDS
    cmp #Variables::MAXIMUM_NAME_LENGTH+1
    bcs ToSyntaxError                       ; too long
    ldy a:Variables::TypeBytes,X
    bne KeepLength
    adc #1                                  ; a real: carry is clear

;; Keeps the name's length plus 1 in <FOUR6>, and sets an `FN` name's type.
;; Also: NTREAL (BB13)
KeepLength:
    sta FOUR6
    pla
    bit SUBFLG
    bpl StoreType
    bvc StoreType
    ldy #Variables::SIZE_FUNCTION
    sty VARNAM
    ldy #Variables::TYPE_FUNCTION

;; Keeps the type byte in <VALTYP>, then goes to the array search for a name followed by `(`, unless <SUBFLG> is set.
;; Also: YSTORE (BB13)
StoreType:
    sty VALTYP
    sec
    ora SUBFLG                              ; any SUBFLG bit makes it a simple variable
    sbc #'('
    bne NoParenthesis

;; Goes to the array search.
;; Also: GARRAY (BB13)
ToFindArray:
    jmp Variables::FindArray

;; Not followed by `(`: with <SUBFLG> bit 6 alone, still an array; otherwise a simple variable.
;;
;; Nothing in this BASIC sets bit 6 without bit 7, so the branch to <FindVariable::ToFindArray> is never taken.
;; Also: SPLVAR (BB13)
NoParenthesis:
    bit SUBFLG
    bmi SearchScalars
    bvs ToFindArray

;; Searches the simple variable table, from <SMVARS> to <STREND>, for the name and type; makes the variable at <STREND>
;; if it is not there.
;;
;; A `!` variable must be an array.
;; Also: SIMVAR (BB13)
SearchScalars:
    cpy #Variables::TYPE_BYTE
    beq ToSyntaxError
    ldy #0
    sty SUBFLG                              ; subscripts allowed again
    lda SMVARS
    ldx SMVARS+1
    ldy SMVARSB
    sty SRCHPTB

;; Keeps the entry's page in <SRCHPT> and checks it against <STREND>, the table's end.
;; Also: STXLOP (BB13)
SetEntryHigh:
    stx SRCHPT+1

;; Keeps the entry's low byte in <SRCHPT> and checks it against <STREND>.
;; Also: SRCHLP (BB13)
CheckEnd:
    sta SRCHPT
    cmp STREND
    bne CompareEntry
    cpx STREND+1
    bne CompareEntry
    ldy SRCHPTB
    cpy STRENDB
    beq Variables::Create                   ; the end: not found

;; Compares the name in the program with this entry's, upper-casing the program's letters.
;;
;; A character below `.` (the type character, `(` or a space) or above `z` (a token) ends the name.
;; Also: PNTER3 (BB13)
CompareEntry:
    ldy #0
    lda (SRCHPT),Y
    sta VARNAM+1                            ; the entry's length, for Advance

;; Compares the next character of the name.
;; Also: COMPAR (BB13)
CompareName:
    lda (LOWDS),Y
    iny
    cmp #'.'
    bcc CheckType
    cmp #'a'
    bcc CompareCharacter
    cmp #'z'+1
    bcs CheckType
    sbc #'a'-'A'-1                          ; carry clear: subtracts $20

;; Compares the character, in upper case, with the entry's.
;; Also: NOT2BIG (BB13)
CompareCharacter:
    cmp (SRCHPT),Y
    beq CompareName

;; At the name's end, or the first difference: the entry matches when its type byte is here and the name's length
;; agrees.
;; Also: TYPCHK (BB13)
CheckType:
    lda VALTYP
    cmp (SRCHPT),Y
    bne Advance
    cpy FOUR6
    bne Advance
    tya                                     ; carry is set, adding one more

;; Points <VARPNT> at the value: the entry's address plus A plus carry, going on through the next X-byte past page $81.
;; In: A = the value's offset (less the carry), carry, SRCHPT = the entry, X = its page
;; Also: FINUP (BB13)
PointAtValue:
    adc SRCHPT
    bcc StoreValuePointer
    inx
    cpx #MAXPG
    bcc StoreValuePointer
    ldx #MINPG
    inc SRCHPTB

;; Stores <VARPNT> and its X-byte.
;; Also: CMPLTE (BB13)
StoreValuePointer:
    stx VARPNT+1
    ldy VARPNT+1
    sta VARPNT
    ldx SRCHPTB
    stx VARPNTB

;; Turns an integer's type byte into INTFLG = $80 with VALTYP = 0, as the expression evaluator wants.
;; Also: MYMYMY (BB13)
SetIntegerFlag:
    ldx VALTYP
    cpx #Variables::TYPE_INTEGER
    bne Done
    stx INTFLG
    ldx #VALUE_TYPE_REAL
    stx VALTYP

;; Returns.
;; Also: PTRRTS (BB13)
Done:
    rts

;; Steps <SRCHPT> past this entry, by its length byte, and searches on.
;; Also: GONEXT (BB13)
Advance:
    clc
    lda VARNAM+1                            ; the entry's length
    adc SRCHPT
    bcc CheckEnd
    inx
    cpx #MAXPG
    bcc SetEntryHigh
    ldx #MINPG
    inc SRCHPTB
    bcs SetEntryHigh                        ; always
.endproc

;; Tells whether a character is a letter, upper or lower case.
;; In: A = the character
;; Out: carry = set for a letter
;; Keeps: A, X, Y
;; Also: ISLETC (BB13)
.proc IsLetter
    cmp #'A'
    bcc Done
    sbc #'Z'+1                              ; the two subtractions take 256 in all, leaving A as it was
    sec
    sbc #$100-'Z'-1                         ; and carry set only for A-Z
    bcs Done
    cmp #'a'
    bcc Done
    sbc #'z'+1                              ; the same for a-z
    sec
    sbc #$100-'z'-1

;; Returns.
;; Also: ISLRTS (BB13)
Done:
    rts
.endproc

.scope Variables continued

;; Makes a simple variable at <STREND>, the table's end: the length byte, the name in upper case, the type byte and a
;; zero value, then points <VARPNT> at the value.
;;
;; The simple variable table is last, so the entry only moves <STREND> up; <REASON> checks that it stays below the
;; strings.
;; In: SRCHPT = <STREND>, LOWDS = the name in the program, FOUR6 = the name's length plus 1, VARNAM = the value's size,
;;   VALTYP = the type byte
;; Out: VARPNT = the value's address, and the rest as from <FindVariable>
;; Errors: ERROM = no room
;; See: <FindVariable::SearchScalars>
;; Also: ADDVAR (BB13)
.proc Create
    sec
    lda FOUR6
    sta VARNAM+1
    adc VARNAM                              ; the entry's length: the name's plus 2, and the value's
    ldy STREND+1
    ldx STRENDB
    pha
    adc STREND                              ; carry is clear
    bcc SetNewEnd
    iny
    cpy #MAXPG                              ; past page $81:
    bcc SetNewEnd
    ldy #MINPG                              ; on at page 2 through the next X-byte
    inx

;; Moves <STREND> past the new entry, if there is room, and writes the entry.
;; Also: GOARND (BB13)
SetNewEnd:
    jsr REASON
    sty STREND+1
    stx STRENDB
    sta STREND
    pla                                     ; the entry's length
    ldy #0
    sta (SRCHPT),Y
    tay
    dey                                     ; the value's last byte
    ldx VARNAM                              ; the value's size
    lda #0

;; Zeroes the value, from its last byte down, then writes the type byte.
;; Also: TILOOP (BB13)
ClearValue:
    sta (SRCHPT),Y
    dey
    dex
    bne ClearValue
    lda VALTYP
    sta (SRCHPT),Y

;; Copies the name from the program into the entry, from its last character down, upper-casing it.
;; Also: TGHTLP (BB13)
CopyName:
    dey
    dey
    bmi Finish
    lda (LOWDS),Y
    cmp #'a'
    bcc Upper
    sbc #'a'-'A'
Upper:
    iny
    sta (SRCHPT),Y
    bpl CopyName                            ; always

;; Points <VARPNT> at the new value, past the length byte, the name and the type byte.
;; Also: ALDONE (BB13)
Finish:
    ldx SRCHPT+1
    lda VARNAM+1                            ; the name's length plus 1
    sec                                     ; plus 1 more
    jmp FindVariable::PointAtValue
.endproc

;; Each type's value size in bytes, by the index the type character gives: a real (no character), `!`, `"`, `#`, `$`
;; (a string's descriptor, <STRSIZ>), `%` and `&`.
;;
;; `"` and `#` never get here: only `!` and `$` to `&` are taken as type characters, and their entries (none, and 10)
;; are left over.
;; See: <Variables::TypeBytes>, <FindVariable::LookUpType>
;; Also: VALTAB (BB13)
ValueSizes:
    .byte SIZE_REAL, SIZE_BYTE, 0, 10       ; real, !, unused, #
    .byte STRSIZ, SIZE_INTEGER, SIZE_LONG_INTEGER ; $, %, &

;; Each type's type byte, in <Variables::ValueSizes>'s order: a real's <VALUE_TYPE_REAL>, `!`'s <TYPE_BYTE>, `#`'s
;; <VALUE_TYPE_LONG_INTEGER>, `$`'s <VALUE_TYPE_STRING>, `%`'s <TYPE_INTEGER>, `&`'s <VALUE_TYPE_LONG_INTEGER>.
;;
;; An `FN` gets <TYPE_FUNCTION> instead, in <FindVariable::KeepLength>.
;; Also: VALTB2 (BB13)
TypeBytes:
    .byte VALUE_TYPE_REAL, TYPE_BYTE, 0, VALUE_TYPE_LONG_INTEGER
    .byte VALUE_TYPE_STRING, TYPE_INTEGER, VALUE_TYPE_LONG_INTEGER

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Helpers for `FOR` and for subscripts
; ---------------------------------------------------------------------------------------------------------------------

;; Pushes A, then the rounded <FAC>, under the caller's return: `FOR` keeps its `STEP` this way.
;; In: A = the byte to push first (the step's sign)
;; See: <PushFac>
;; Also: PUSHF (BB13)
.proc PushSignedFac
    tay
    pla                                     ; the return address, into INDEX1
    sta INDEX1
    pla
    sta INDEX1+1
    inc INDEX1
    bne PushSign
    inc INDEX1+1
PushSign:
    tya
    pha
    ; Falls into PushFac.
.endproc

;; Pushes the rounded <FAC>, five bytes with the exponent on top, then jumps to INDEX1.
;; In: INDEX1 = where to go on
;; Also: FORPSH (BB13)
.proc PushFac
    jsr ROUND
    lda FACLO
    pha
    lda FACMO
    pha
    lda FACMOH
    pha
    lda FACHO
    pha
    lda FACEXP
    pha
    jmp (INDEX1)
.endproc

.scope Variables continued

;; Points ARYPNT at an array's elements: past the entry's head and two bytes for each of COUNT dimensions.
;; In: LOWTR = the array's entry, VARNAM+1 = the name's length plus 3, COUNT = the count of dimensions
;; Out: ARYPNT = the elements' address, with its bank in <ARYPNTB>, carry = clear
;; Entry:
;;   SizesPlus = points ARYPNT A bytes past the start of the array's sizes
;;   CountPlus = points ARYPNT A bytes plus carry past the array's count of dimensions
;; Also: FMAPTR (BB13)
.proc ElementsStart
    lda COUNT
    asl

;; Points <ARYPNT> A bytes past an array's sizes, which start one past the count of dimensions.
;; In: A = the offset, LOWTR = the array's entry, VARNAM+1 = the name's length plus 3
;; Also: FMPTR1 (BB13)
SizesPlus:
    sec

;; Points <ARYPNT> A bytes plus carry past an array's count of dimensions.
;; In: A = the offset, carry, LOWTR = the array's entry, VARNAM+1 = the name's length plus 3
;; Also: FMPTR2 (BB13)
CountPlus:
    adc VARNAM+1
    adc LOWTR
    ldy LOWTR+1
    ldx LOWTRB
    bcc Store
    iny
    cpy #MAXPG
    bcc Store
    ldy #MINPG
    inx

;; Stores <ARYPNT> and its X-byte.
;; Also: JSRGM (BB13)
Store:
    sta ARYPNT
    sty ARYPNT+1
    stx ARYPNTB
    rts
.endproc

.endscope

;; -32768 as a packed real, for <FacToInteger>'s check.
;; Also: N32768 (BB13)
MinimumInteger:
    .byte WORD_EXPONENT, $80, 0, 0
    .byte 0

;; Evaluates a subscript: the formula after the current character, as an integer 0-32767.
;;
;; The formula can name another array, so the name's address in <TMPPTR> and <DORES> are kept on the stack meanwhile.
;; Out: INDICE = the subscript's high byte (INDICE is <FACMO>), FACLO = its low byte
;; Errors: ERRFC = a negative or too large value
;; See: <FacToNonnegativeInteger>
;; Also: INTIDX (BB13)
.proc EvaluateSubscript
    jsr CHRGET
    lda TMPPTR
    pha
    lda TMPPTR+1
    pha
    lda TMPPTRB
    pha
    lda DORES
    pha
    jsr FRMNUM
    pla
    sta DORES
    pla
    sta TMPPTRB
    pla
    sta TMPPTR+1
    pla
    sta TMPPTR
    ; Falls into FacToNonnegativeInteger.
.endproc

;; Makes the <FAC> a 16-bit integer, refusing a negative number.
;; Out: FACMO = the high byte, FACLO = the low byte
;; Errors: ERRFC = a negative number or one past 32767
;; See: <FacToInteger>
;; Also: POSINT (BB13)
.proc FacToNonnegativeInteger
    lda FACSGN
    bmi FacToInteger::FailUnlessEqual       ; negative: zero is clear, so an error
    ; Falls into FacToInteger.
.endproc

;; Makes the <FAC> a signed 16-bit integer, -32768 to 32767, rounding it by adding one half first.
;; Out: FACMO = the high byte, FACLO = the low byte
;; Errors: ERRFC = a number out of range
;; Entry:
;;   FailUnlessEqual = goes on when zero is set, or else ends with ILLEGAL QUANTITY; <FacToNonnegativeInteger>
;;     branches here for a negative number
;; See: <FacToNonnegativeInteger>, <MinimumInteger>
;; Also: AYINT (BB13)
.proc FacToInteger
    lda FACEXP
    cmp #WORD_EXPONENT                      ; below 32768 in size?
    bcc RoundToInteger
    lda #<(MinimumInteger)
    ldx #0
    ldy #>(MinimumInteger)
    jsr FCOMP                               ; or exactly -32768?

;; Goes on when zero is set; otherwise an ILLEGAL QUANTITY error.
;; Also: NONONO (BB13)
FailUnlessEqual:
    beq RoundToInteger
    jmp IllegalQuantityError

;; Adds one half and makes the <FAC> an integer.
;; Also: QINTGO (BB13)
RoundToInteger:
    jsr FADDH
    jmp QINT
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Arrays
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued

;; Finds an array, or makes it, and points <VARPNT> at the element the subscripts name.
;;
;; The subscripts are evaluated first and kept on the stack, two bytes each with the low byte on top and the last
;; subscript nearest the top, under the type byte and <DIMFLG>. In `DIM` the array must not exist, and is only made.
;; In: Y = the type byte, FOUR6 = the name's length plus 1, TMPPTR = the name in the program
;; Out: VARPNT = the value's address, and the rest as from <FindVariable>
;; See: <EvaluateSubscript>, <Variables::ArrayNotFound>, <Variables::ElementAddress>
;; Also: ISARY (BB13)
.proc FindArray
    lda FOUR6
    clc
    adc #2
    sta VARNAM+1                            ; the name's length plus 3: the length bytes and the type
    lda SUBFLG
    bne Search                              ; no subscripts to read
    lda DIMFLG
    ora INTFLG
    pha
    tya
    pha                                     ; the type byte
    ldy #0                                  ; no subscripts yet

;; Evaluates each subscript and slips it on the stack under the type byte and <DIMFLG>.
;; Also: INDLOP (BB13)
NextSubscript:
    tya
    pha
    lda VARNAM+1
    pha
    lda VARNAM
    pha
    jsr EvaluateSubscript
    pla
    sta VARNAM
    pla
    sta VARNAM+1
    pla
    tay
    tsx
    lda $0102,X
    pha                                     ; DIMFLG and the type, pushed again
    lda $0101,X
    pha
    lda INDICE                              ; and the subscript in their old place
    sta $0102,X
    lda INDICE+1
    sta $0101,X
    iny
    jsr CHRGOT
    cmp #','                                ; another subscript
    beq NextSubscript
    sty COUNT                               ; the count of subscripts
    jsr CheckCloseParenthesis
    pla
    sta VALTYP
    pla
    sta INTFLG
    and #$7F
    sta DIMFLG

;; Searches the array table, from <ARYTAB> to <VARTAB>, for the name and type.
;; Also: STRTSRCH (BB13)
Search:
    lda ARYTAB+1
    ldx ARYTAB
    ldy ARYTABB

;; Points <LOWTR> at the next entry, and ends the search at <VARTAB>.
;; In: X = the entry's low byte, A = its page, Y = its bank
;; Also: LOPFDA (BB13)
CheckEnd:
    sta LOWTR+1
    stx LOWTR
    sty LOWTRB
    cpy VARTABB
    bne CompareName
    cmp VARTAB+1
    bne CompareName
    cpx VARTAB
    beq ArrayNotFound                       ; the end: not found

;; Compares the name in the program with this entry's, upper-casing the program's letters.
;;
;; Unlike the simple variable search, any character below `a` is compared, so a type character or `(` is what ends a
;; match.
;; Also: LOPFDV (BB13)
CompareName:
    ldy #1

;; Compares the next character of the name.
;; Also: NMLOOP (BB13)
NextCharacter:
    dey
    lda (TMPPTR),Y
    iny
    iny                                     ; the entry's name starts at offset 2
    cmp #'a'
    bcc CompareCharacter
    cmp #'z'+1
    bcs CheckType
    sbc #'a'-'A'-1                          ; carry clear: subtracts $20

;; Compares the character, in upper case, with the entry's.
;; Also: NOT2SML (BB13)
CompareCharacter:
    cmp (LOWTR),Y
    beq NextCharacter

;; The entry matches when its type byte is here and the name's length agrees.
;; Also: CHKTYP (BB13)
CheckType:
    lda VALTYP
    cmp (LOWTR),Y
    bne NextArray
    iny
    cpy VARNAM+1
    beq ArrayFound

;; Steps <LOWTR> past this entry, by its two-byte length, and searches on.
;; Also: NOGOT (BB13)
NextArray:
    ldy #0
    lda (LOWTR),Y
    clc
    adc LOWTR
    tax
    iny
    lda (LOWTR),Y
    adc LOWTR+1
    ldy LOWTRB
    jsr Memory::NormalizeAfterAdd
    jmp CheckEnd                            ; always
.endproc

.endscope

;; Ends the statement with BAD SUBSCRIPT.
;; Errors: ERRBS
;; Also: BSERR (BB13)
.proc BadSubscriptError
    ldx #ERRBS
    .byte $2C                               ; BIT absolute skips IllegalQuantityError's LDX
    ; Falls into IllegalQuantityError, past its load.
.endproc

;; Ends the statement with ILLEGAL QUANTITY.
;; Errors: ERRFC
;; Entry:
;;   ToError = ends the statement with the error in X; <Variables::ArrayFound> branches here with REDIM'D ARRAY
;; Also: FCERR (BB13)
.proc IllegalQuantityError
    ldx #ERRFC

;; Ends the statement with the error in X.
;; Also: ERRGO3 (BB13)
ToError:
    jmp ERROR
.endproc

.scope Variables continued

;; Found the array: in `DIM`, a REDIM'D ARRAY error; otherwise checks the count of subscripts and finds the element.
;;
;; With <SUBFLG> set it returns with carry set and <LOWTR> at the entry, for a statement that names a whole array;
;; nothing in this BASIC sets it here.
;; Errors: ERRDD = `DIM` of an array that exists, ERRBS = the wrong count of subscripts
;; Also: GOTARY (BB13)
.proc ArrayFound
    ldx #ERRDD
    lda DIMFLG
    bne IllegalQuantityError::ToError
    lda SUBFLG
    beq CheckDimensions
    sec
    rts

;; Checks that the array has as many dimensions as there are subscripts (BAD SUBSCRIPT otherwise), then finds the
;; element.
;; See: <Variables::ElementAddress>
;; Also: GOGETM (BB13)
CheckDimensions:
    clc
    lda #0
    jsr ElementsStart::CountPlus            ; ARYPNT: the count of dimensions
    lda COUNT
    ldy #0
    cmp (ARYPNT),Y
    bne BadSubscriptError
    jmp ElementAddress
.endproc

;; Not found. From an expression (<DORES> set), the array is not made: the subscripts are dropped and <VARPNT> points to
;; <ZERO>, so the element reads as zero or an empty string.
;; See: <Variables::CreateArray>
;; Also: NOTFFD (BB13)
.proc ArrayNotFound
    lda DORES
    beq CreateArray
    lda #<(ZERO)
    ldy #>(ZERO)
    sta VARPNT
    sty VARPNT+1

;; Drops a subscript from the stack.
;; Also: NOTFONE (BB13)
DropSubscript:
    pla
    pla
    dec COUNT
    bne DropSubscript
    lda #0                                  ; ZERO's bank
    jmp ElementAddress::SetArrayFlags
.endproc

;; Makes the array at <VARTAB>, the array table's end, moving the simple variable table up to make room.
;;
;; Each dimension's size is its subscript plus 1 in `DIM`, or 11 otherwise; the size of the whole entry is the element
;; size times every dimension's size, plus the head: the length, the name, the type, the count and the sizes. More
;; than 64K is OUT OF MEMORY. The sizes stay on the stack; <Variables::InitializeArray> writes the entry.
;; In: LOWTR = <VARTAB>, COUNT = the count of subscripts, on the stack
;; Errors: ERROM = 64K or more, or no room
;; See: <Variables::MultiplyUnsigned>, <BLTU>
;; Also: NOTFF2 (BB13)
.proc CreateArray
    lda COUNT
    sta INDEX+1                             ; the dimensions left
    ldy #0
    sty CURTOL+1
    ldy VARNAM
    sty CURTOL                              ; the element's size
    tsx                                     ; reads the subscripts in place

;; Multiplies <CURTOL> by each dimension's size.
;; Also: SIZLOP (BB13)
NextDimension:
    lda #0
    ldy #DEFAULT_HIGHEST_SUBSCRIPT          ; not `DIM`
    bit DIMFLG
    bvc SizeFromHighest
    inx
    lda $0100,X                             ; `DIM`: the subscript's low byte
    inx
    tay
    lda $0100,X                             ; and high byte

;; Makes the dimension's size, one more than its highest subscript, in Y (low) and X (high).
;; Also: NOTDIM (BB13)
SizeFromHighest:
    stx INDEX
    tax
    iny
    bne Multiply
    inx

;; Multiplies <CURTOL> by the size, then takes the next dimension; past the last, adds the head's size.
;; Also: NOVFLW (BB13)
Multiply:
    jsr MultiplyUnsigned
    stx CURTOL
    sty CURTOL+1
    ldx INDEX
    dec INDEX+1
    bne NextDimension
    lda COUNT
    asl
    sec                                     ; the count byte
    adc VARNAM+1                            ; the name, its length bytes and type
    adc CURTOL                              ; the elements
    sta CURTOL
    bcc MoveSimpleVariables
    iny
    bne KeepHigh
    jmp OMERR                               ; 64K or more

;; Keeps the size's high byte.
;; Also: ALGOOD (BB13)
KeepHigh:
    clc
    sty CURTOL+1

;; Moves the simple variable table, from <VARTAB> to <STREND>, up by the entry's size, which moves <STREND>.
;; Also: GOODIE (BB13)
MoveSimpleVariables:
    lda STREND
    sta HIGHTR
    adc CURTOL
    sta HIGHDS
    lda STREND+1
    sta HIGHTR+1
    adc CURTOL+1
    ldy STRENDB
    sty HIGHTRB
    jsr Memory::NormalizeAfterAdd
    sta HIGHDS+1
    tya
    sta HIGHDSB
    tax
    lda HIGHDS
    ldy HIGHDS+1
    jsr BLTU
    .assert * = InitializeArray, "CreateArray must fall into InitializeArray, in B3UdefI.asm."
    ; Falls into InitializeArray.
.endproc

.endscope
