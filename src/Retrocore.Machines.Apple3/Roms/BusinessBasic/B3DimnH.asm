; retrocore: style=strict
;; Finding variables: `DIM`, <FindVariable>'s search of the simple variable and array tables, which makes a variable
;; it does not find, the tables of each type's size and type byte, the start of making an array
;; (<Variables::CreateArray>; B3UdefI.asm finishes it), and helpers to push the <Fac> for `FOR` and to make the <Fac> a
;; 16-bit integer.
;;
;; Variables live after the program: the array table from <ArraysStart> to <VariablesStart>, then the simple
;; variable table from <VariablesStart> to <VariablesEnd>. Strings grow down from <StringsBottom> to meet them. Every
;; pointer into this space is three bytes: the low byte, a page kept in $02-$81, and the X-byte ($80 + the bank pair) in
;; the X-byte page. A page past $81 goes on at $02 through the next X-byte, so the space reads as one run of memory, 32K
;; per X-byte.
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

;; The type byte of an integer (`%`) variable; <FindVariable> turns it into <IntegerType> set with a real's <ValueType>.
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
;; <Dimensioning>, which <FindVariable::WithDimensionFlag> takes from X, is the array name's first letter, so its bit 6
;; is set; the search tests that bit to size a new array from the subscripts, to refuse an array that exists, and to
;; stop before indexing it.
;; In: A = the character after `DIM`
;; See: <Variables::FindArray>, <Variables::CreateArray>
;; Also: DIM (BB13)
.proc Dim
    tax                                     ; Dimensioning: the first letter, bit 6 set
    lda #0
    sta TokenizeState                       ; arrays not found are made
    jsr FindVariable::WithDimensionFlag
    jsr GetCurrentCharacter
    bne DimNextArray
    rts
.endproc

.endscope

;; Reads the variable name at <TextPointer> and finds its value, making the variable when it does not exist.
;;
;; An array's subscripts are evaluated as formulas, which can call this again, so the array search keeps its state
;; on the stack. A simple variable or an array element not yet used is made, zeroed; an array not yet used is made
;; with 11 elements (0-10) in each dimension given.
;; In: TextPointer = the variable's name
;; Out: VariablePointer = the value's address (<VariablePointerXByte> its bank), A = its low byte, Y = its page,
;;   TextPointer = past the name and any subscripts, ValueType = 0 for a number, $FF for a string or $40 for a long
;;   integer, IntegerType = $80 for an integer,
;;   ArrayElementFound = $80 for an array element, 0 for a simple variable
;; Errors: <ERROR_SYNTAX> = a bad name or one longer than 64 characters, <ERROR_BAD_SUBSCRIPT> = the wrong count of
;;   subscripts or one past the array's size, <ERROR_ILLEGAL_QUANTITY> = a negative or too large subscript,
;;   <ERROR_REDIMENSIONED_ARRAY> = `DIM` of an array that exists, <ERROR_OUT_OF_MEMORY> = no room
;; Entry:
;;   ForExpression = with X nonzero, an array not found is not made: <VariablePointer> points to a zero (<ZeroValue>)
;;   instead, as <EvaluateVariable> wants
;;   WithDimensionFlag = takes <Dimensioning> from X; <Statements::Dim> enters here
;;   KeepDimensionFlag = takes <Dimensioning>, <TokenizeState> and <SubscriptMode> as they are; `FN`'s name and `DEF`'s
;;   argument enter here
;;   ValidFirst = reads a name whose first letter <TextPointer> is at, with <Dimensioning>, <TokenizeState> and
;;   <SubscriptMode> set; the table of routines for modules, in Catalog.asm, gives it
;;   PointAtValue = points <VariablePointer> at the value A plus carry bytes into the entry at <VariableSearchPointer>;
;;   <Variables::Create> goes here
;;   SetIntegerFlag = sorts out an integer's type and returns; <Variables::ElementAddress> goes here
;; See: <IsLetter>, <Variables::ValueSizes>, <Variables::FindArray>
;; Also: PTRGET (BB13)
.proc FindVariable
    ldx #0                                  ; TokenizeState: make arrays not found

;; With X nonzero, an array not found is not made: <VariablePointer> points to a zero (<ZeroValue>) instead, as the
;; expression evaluator wants.
;; In: X = nonzero not to make an array not found, TextPointer = the variable's name
;; Also: PTREVL (BB13)
ForExpression:
    stx TokenizeState
    ldx #0                                  ; not in `DIM`

;; Takes <Dimensioning> from X; <Statements::Dim> enters here.
;; In: X = <Dimensioning>, nonzero in `DIM`, TextPointer = the variable's name
;; Also: PTRGT1 (BB13)
WithDimensionFlag:
    stx Dimensioning

;; Takes <Dimensioning>, <TokenizeState> and <SubscriptMode> as they are; `FN`'s name and `DEF`'s argument enter here
;; with <SubscriptMode> set.
;; In: SubscriptMode = $80 for `DEF`'s argument (no subscripts), bits 7 and 6 for an `FN` name, TextPointer = the
;;   variable's name
;; See: <ReadFunctionName::AfterFn>, <Statements::Def>
;; Also: PTRGT2 (BB13)
KeepDimensionFlag:
    jsr GetCurrentCharacter
    jsr IsLetter
    bcs ValidFirst

;; Ends the statement with SYNTAX <ReportError>, for a variable name that is not one.
;; Also: WRDERR (BB13)
ToSyntaxError:
    jmp SyntaxError

;; Starts with a letter: notes where the name starts, in <DestinationStart> and <VariableNamePointer>, and reads to its
;; end.
;; Also: PTRGT3 (BB13)
ValidFirst:
    ldx #0
    stx IntegerType                         ; a real unless the name says otherwise
    stx ArrayElementFound                   ; and a simple variable
    lda TextPointer
    sta DestinationStart
    sta VariableNamePointer
    lda TextPointer+1
    sta DestinationStart+1
    sta VariableNamePointer+1
    lda TextPointerXByte
    sta DestinationStartXByte
    sta VariableNamePointerXByte

;; Skips the name's letters, digits and periods.
;; Also: EATEM (BB13)
SkipRest:
    jsr GetNextCharacter
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
    bit SubscriptMode
    bmi ToSyntaxError                       ; `FN` names are real
    jsr GetNextCharacter

;; Looks up the type's value size and type byte, and works out the name's length.
;;
;; A real's name has no type character, so its length gets 1 here to match the others: <CollectorStep> is the name's
;; length plus 1 in every case. An `FN` name gets type <Variables::TYPE_FUNCTION> and a value of
;; <Variables::SIZE_FUNCTION> bytes.
;; Also: REAL (BB13)
LookUpType:
    ldy a:Variables::ValueSizes,X
    sty VariableSizes                       ; the value's size
    pha                                     ; the character after the name
    lda TextPointer
    sec
    sbc DestinationStart
    cmp #Variables::MAXIMUM_NAME_LENGTH+1
    bcs ToSyntaxError                       ; too long
    ldy a:Variables::TypeBytes,X
    bne KeepLength
    adc #1                                  ; a real: carry is clear

;; Keeps the name's length plus 1 in <CollectorStep>, and sets an `FN` name's type.
;; Also: NTREAL (BB13)
KeepLength:
    sta CollectorStep
    pla
    bit SubscriptMode
    bpl StoreType
    bvc StoreType
    ldy #Variables::SIZE_FUNCTION
    sty VariableSizes
    ldy #Variables::TYPE_FUNCTION

;; Keeps the type byte in <ValueType>, then goes to the array search for a name followed by `(`, unless <SubscriptMode>
;; is set.
;; Also: YSTORE (BB13)
StoreType:
    sty ValueType
    sec
    ora SubscriptMode                       ; any SubscriptMode bit makes it a simple variable
    sbc #'('
    bne NoParenthesis

;; Goes to the array search.
;; Also: GARRAY (BB13)
ToFindArray:
    jmp Variables::FindArray

;; Not followed by `(`: with <SubscriptMode> bit 6 alone, still an array; otherwise a simple variable.
;;
;; Nothing in this BASIC sets bit 6 without bit 7, so the branch to <FindVariable::ToFindArray> is never taken.
;; Also: SPLVAR (BB13)
NoParenthesis:
    bit SubscriptMode
    bmi SearchScalars
    bvs ToFindArray

;; Searches the simple variable table, from <VariablesStart> to <VariablesEnd>, for the name and type; makes the
;; variable at <VariablesEnd> if it is not there.
;;
;; A `!` variable must be an array.
;; Also: SIMVAR (BB13)
SearchScalars:
    cpy #Variables::TYPE_BYTE
    beq ToSyntaxError
    ldy #0
    sty SubscriptMode                       ; subscripts allowed again
    lda VariablesStart
    ldx VariablesStart+1
    ldy VariablesStartXByte
    sty VariableSearchPointerXByte

;; Keeps the entry's page in <VariableSearchPointer> and checks it against <VariablesEnd>, the table's end.
;; Also: STXLOP (BB13)
SetEntryHigh:
    stx VariableSearchPointer+1

;; Keeps the entry's low byte in <VariableSearchPointer> and checks it against <VariablesEnd>.
;; Also: SRCHLP (BB13)
CheckEnd:
    sta VariableSearchPointer
    cmp VariablesEnd
    bne CompareEntry
    cpx VariablesEnd+1
    bne CompareEntry
    ldy VariableSearchPointerXByte
    cpy VariablesEndXByte
    beq Variables::Create                   ; the end: not found

;; Compares the name in the program with this entry's, upper-casing the program's letters.
;;
;; A character below `.` (the type character, `(` or a space) or above `z` (a token) ends the name.
;; Also: PNTER3 (BB13)
CompareEntry:
    ldy #0
    lda (VariableSearchPointer),Y
    sta VariableSizes+1                     ; the entry's length, for Advance

;; Compares the next character of the name.
;; Also: COMPAR (BB13)
CompareName:
    lda (DestinationStart),Y
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
    cmp (VariableSearchPointer),Y
    beq CompareName

;; At the name's end, or the first difference: the entry matches when its type byte is here and the name's length
;; agrees.
;; Also: TYPCHK (BB13)
CheckType:
    lda ValueType
    cmp (VariableSearchPointer),Y
    bne Advance
    cpy CollectorStep
    bne Advance
    tya                                     ; carry is set, adding one more

;; Points <VariablePointer> at the value: the entry's address plus A plus carry, going on through the next X-byte past
;; page $81.
;; In: A = the value's offset (less the carry), carry, VariableSearchPointer = the entry, X = its page
;; Also: FINUP (BB13)
PointAtValue:
    adc VariableSearchPointer
    bcc StoreValuePointer
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc StoreValuePointer
    ldx #POINTER_PAGE_FIRST
    inc VariableSearchPointerXByte

;; Stores <VariablePointer> and its X-byte.
;; Also: CMPLTE (BB13)
StoreValuePointer:
    stx VariablePointer+1
    ldy VariablePointer+1
    sta VariablePointer
    ldx VariableSearchPointerXByte
    stx VariablePointerXByte

;; Turns an integer's type byte into <IntegerType> = $80 with <ValueType> = 0, as the expression evaluator wants.
;; Also: MYMYMY (BB13)
SetIntegerFlag:
    ldx ValueType
    cpx #Variables::TYPE_INTEGER
    bne Done
    stx IntegerType
    ldx #VALUE_TYPE_REAL
    stx ValueType

;; Returns.
;; Also: PTRRTS (BB13)
Done:
    rts

;; Steps <VariableSearchPointer> past this entry, by its length byte, and searches on.
;; Also: GONEXT (BB13)
Advance:
    clc
    lda VariableSizes+1                     ; the entry's length
    adc VariableSearchPointer
    bcc CheckEnd
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc SetEntryHigh
    ldx #POINTER_PAGE_FIRST
    inc VariableSearchPointerXByte
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

;; Makes a simple variable at <VariablesEnd>, the table's end: the length byte, the name in upper case, the type byte
;; and a zero value, then points <VariablePointer> at the value.
;;
;; The simple variable table is last, so the entry only moves <VariablesEnd> up; <CheckFreeMemory> checks that it stays
;; below the strings.
;; In: VariableSearchPointer = <VariablesEnd>, DestinationStart = the name in the program, CollectorStep = the name's
;;   length plus 1, VariableSizes = the value's size,
;;   ValueType = the type byte
;; Out: VariablePointer = the value's address, and the rest as from <FindVariable>
;; Errors: <ERROR_OUT_OF_MEMORY> = no room
;; See: <FindVariable::SearchScalars>
;; Also: ADDVAR (BB13)
.proc Create
    sec
    lda CollectorStep
    sta VariableSizes+1
    adc VariableSizes                       ; the entry's length: the name's plus 2, and the value's
    ldy VariablesEnd+1
    ldx VariablesEndXByte
    pha
    adc VariablesEnd                        ; carry is clear
    bcc SetNewEnd
    iny
    cpy #POINTER_PAGE_LIMIT                 ; past page $81:
    bcc SetNewEnd
    ldy #POINTER_PAGE_FIRST                 ; on at page 2 through the next X-byte
    inx

;; Moves <VariablesEnd> past the new entry, if there is room, and writes the entry.
;; Also: GOARND (BB13)
SetNewEnd:
    jsr CheckFreeMemory
    sty VariablesEnd+1
    stx VariablesEndXByte
    sta VariablesEnd
    pla                                     ; the entry's length
    ldy #0
    sta (VariableSearchPointer),Y
    tay
    dey                                     ; the value's last byte
    ldx VariableSizes                       ; the value's size
    lda #0

;; Zeroes the value, from its last byte down, then writes the type byte.
;; Also: TILOOP (BB13)
ClearValue:
    sta (VariableSearchPointer),Y
    dey
    dex
    bne ClearValue
    lda ValueType
    sta (VariableSearchPointer),Y

;; Copies the name from the program into the entry, from its last character down, upper-casing it.
;; Also: TGHTLP (BB13)
CopyName:
    dey
    dey
    bmi Finish
    lda (DestinationStart),Y
    cmp #'a'
    bcc Upper
    sbc #'a'-'A'
Upper:
    iny
    sta (VariableSearchPointer),Y
    bpl CopyName                            ; always

;; Points <VariablePointer> at the new value, past the length byte, the name and the type byte.
;; Also: ALDONE (BB13)
Finish:
    ldx VariableSearchPointer+1
    lda VariableSizes+1                     ; the name's length plus 1
    sec                                     ; plus 1 more
    jmp FindVariable::PointAtValue
.endproc

;; Each type's value size in bytes, by the index the type character gives: a real (no character), `!`, `"`, `#`, `$`
;; (a string's descriptor, <DESCRIPTOR_SIZE>), `%` and `&`.
;;
;; `"` and `#` never get here: only `!` and `$` to `&` are taken as type characters, and their entries (none, and 10)
;; are left over.
;; See: <Variables::TypeBytes>, <FindVariable::LookUpType>
;; Also: VALTAB (BB13)
ValueSizes:
    .byte SIZE_REAL, SIZE_BYTE, 0, 10       ; real, !, unused, #
    .byte DESCRIPTOR_SIZE, SIZE_INTEGER, SIZE_LONG_INTEGER ; $, %, &

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

;; Pushes A, then the rounded <Fac>, under the caller's return: `FOR` keeps its `STEP` this way.
;; In: A = the byte to push first (the step's sign)
;; See: <PushFac>
;; Also: PUSHF (BB13)
.proc PushSignedFac
    tay
    pla                                     ; the return address, into Pointer1
    sta Pointer1
    pla
    sta Pointer1+1
    inc Pointer1
    bne PushSign
    inc Pointer1+1
PushSign:
    tya
    pha
    ; Falls into PushFac.
.endproc

;; Pushes the rounded <Fac>, five bytes with the exponent on top, then jumps to <Pointer1>.
;; In: Pointer1 = where to go on
;; Also: FORPSH (BB13)
.proc PushFac
    jsr Float::Round
    lda FacMantissa4
    pha
    lda FacMantissa3
    pha
    lda FacMantissa2
    pha
    lda FacMantissa1
    pha
    lda FacExponent
    pha
    jmp (Pointer1)
.endproc

.scope Variables continued

;; Points <ArrayPointer> at an array's elements: past the entry's head and two bytes for each of <Counter> dimensions.
;; In: SourceStart = the array's entry, VariableSizes+1 = the name's length plus 3, Counter = the count of dimensions
;; Out: ArrayPointer = the elements' address, with its bank in <ArrayPointerXByte>, carry = clear
;; Entry:
;;   SizesPlus = points <ArrayPointer> A bytes past the start of the array's sizes
;;   CountPlus = points <ArrayPointer> A bytes plus carry past the array's count of dimensions
;; Also: FMAPTR (BB13)
.proc ElementsStart
    lda Counter
    asl

;; Points <ArrayPointer> A bytes past an array's sizes, which start one past the count of dimensions.
;; In: A = the offset, SourceStart = the array's entry, VariableSizes+1 = the name's length plus 3
;; Also: FMPTR1 (BB13)
SizesPlus:
    sec

;; Points <ArrayPointer> A bytes plus carry past an array's count of dimensions.
;; In: A = the offset, carry, SourceStart = the array's entry, VariableSizes+1 = the name's length plus 3
;; Also: FMPTR2 (BB13)
CountPlus:
    adc VariableSizes+1
    adc SourceStart
    ldy SourceStart+1
    ldx SourceStartXByte
    bcc Store
    iny
    cpy #POINTER_PAGE_LIMIT
    bcc Store
    ldy #POINTER_PAGE_FIRST
    inx

;; Stores <ArrayPointer> and its X-byte.
;; Also: JSRGM (BB13)
Store:
    sta ArrayPointer
    sty ArrayPointer+1
    stx ArrayPointerXByte
    rts
.endproc

.endscope

;; -32768 as a packed real, for <FacToInteger>'s check.
;; Also: N32768 (BB13)
MinimumInteger:
    .byte Float::WORD_EXPONENT, $80, 0, 0
    .byte 0

;; Evaluates a subscript: the formula after the current character, as an integer 0-32767.
;;
;; The formula can name another array, so the name's address in <VariableNamePointer> and <TokenizeState> are kept on
;; the stack meanwhile.
;; Out: ArrayIndex = the subscript's high byte (<ArrayIndex> is <FacMantissa3>), FacMantissa4 = its low byte
;; Errors: <ERROR_ILLEGAL_QUANTITY> = a negative or too large value
;; See: <FacToNonnegativeInteger>
;; Also: INTIDX (BB13)
.proc EvaluateSubscript
    jsr GetNextCharacter
    lda VariableNamePointer
    pha
    lda VariableNamePointer+1
    pha
    lda VariableNamePointerXByte
    pha
    lda TokenizeState
    pha
    jsr EvaluateNumber
    pla
    sta TokenizeState
    pla
    sta VariableNamePointerXByte
    pla
    sta VariableNamePointer+1
    pla
    sta VariableNamePointer
    ; Falls into FacToNonnegativeInteger.
.endproc

;; Makes the <Fac> a 16-bit integer, refusing a negative number.
;; Out: FacMantissa3 = the high byte, FacMantissa4 = the low byte
;; Errors: <ERROR_ILLEGAL_QUANTITY> = a negative number or one past 32767
;; See: <FacToInteger>
;; Also: POSINT (BB13)
.proc FacToNonnegativeInteger
    lda FacSign
    bmi FacToInteger::FailUnlessEqual       ; negative: zero is clear, so an error
    ; Falls into FacToInteger.
.endproc

;; Makes the <Fac> a signed 16-bit integer, -32768 to 32767, rounding it by adding one half first.
;; Out: FacMantissa3 = the high byte, FacMantissa4 = the low byte
;; Errors: <ERROR_ILLEGAL_QUANTITY> = a number out of range
;; Entry:
;;   FailUnlessEqual = goes on when zero is set, or else ends with ILLEGAL QUANTITY; <FacToNonnegativeInteger>
;;     branches here for a negative number
;; See: <FacToNonnegativeInteger>, <MinimumInteger>
;; Also: AYINT (BB13)
.proc FacToInteger
    lda FacExponent
    cmp #Float::WORD_EXPONENT               ; below 32768 in size?
    bcc RoundToInteger
    lda #<(MinimumInteger)
    ldx #0
    ldy #>(MinimumInteger)
    jsr Float::Compare                      ; or exactly -32768?

;; Goes on when zero is set; otherwise an ILLEGAL QUANTITY error.
;; Also: NONONO (BB13)
FailUnlessEqual:
    beq RoundToInteger
    jmp IllegalQuantityError

;; Adds one half and makes the <Fac> an integer.
;; Also: QINTGO (BB13)
RoundToInteger:
    jsr Float::AddHalf
    jmp Float::ToLongInteger
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Arrays
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued

;; Finds an array, or makes it, and points <VariablePointer> at the element the subscripts name.
;;
;; The subscripts are evaluated first and kept on the stack, two bytes each with the low byte on top and the last
;; subscript nearest the top, under the type byte and <Dimensioning>. In `DIM` the array must not exist, and is only
;; made.
;; In: Y = the type byte, CollectorStep = the name's length plus 1, VariableNamePointer = the name in the program
;; Out: VariablePointer = the value's address, and the rest as from <FindVariable>
;; See: <EvaluateSubscript>, <Variables::ArrayNotFound>, <Variables::ElementAddress>
;; Also: ISARY (BB13)
.proc FindArray
    lda CollectorStep
    clc
    adc #2
    sta VariableSizes+1                     ; the name's length plus 3: the length bytes and the type
    lda SubscriptMode
    bne Search                              ; no subscripts to read
    lda Dimensioning
    ora IntegerType
    pha
    tya
    pha                                     ; the type byte
    ldy #0                                  ; no subscripts yet

;; Evaluates each subscript and slips it on the stack under the type byte and <Dimensioning>.
;; Also: INDLOP (BB13)
NextSubscript:
    tya
    pha
    lda VariableSizes+1
    pha
    lda VariableSizes
    pha
    jsr EvaluateSubscript
    pla
    sta VariableSizes
    pla
    sta VariableSizes+1
    pla
    tay
    tsx
    lda $0102,X
    pha                                     ; Dimensioning and the type, pushed again
    lda $0101,X
    pha
    lda ArrayIndex                          ; and the subscript in their old place
    sta $0102,X
    lda ArrayIndex+1
    sta $0101,X
    iny
    jsr GetCurrentCharacter
    cmp #','                                ; another subscript
    beq NextSubscript
    sty Counter                             ; the count of subscripts
    jsr CheckCloseParenthesis
    pla
    sta ValueType
    pla
    sta IntegerType
    and #$7F
    sta Dimensioning

;; Searches the array table, from <ArraysStart> to <VariablesStart>, for the name and type.
;; Also: STRTSRCH (BB13)
Search:
    lda ArraysStart+1
    ldx ArraysStart
    ldy ArraysStartXByte

;; Points <SourceStart> at the next entry, and ends the search at <VariablesStart>.
;; In: X = the entry's low byte, A = its page, Y = its bank
;; Also: LOPFDA (BB13)
CheckEnd:
    sta SourceStart+1
    stx SourceStart
    sty SourceStartXByte
    cpy VariablesStartXByte
    bne CompareName
    cmp VariablesStart+1
    bne CompareName
    cpx VariablesStart
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
    lda (VariableNamePointer),Y
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
    cmp (SourceStart),Y
    beq NextCharacter

;; The entry matches when its type byte is here and the name's length agrees.
;; Also: CHKTYP (BB13)
CheckType:
    lda ValueType
    cmp (SourceStart),Y
    bne NextArray
    iny
    cpy VariableSizes+1
    beq ArrayFound

;; Steps <SourceStart> past this entry, by its two-byte length, and searches on.
;; Also: NOGOT (BB13)
NextArray:
    ldy #0
    lda (SourceStart),Y
    clc
    adc SourceStart
    tax
    iny
    lda (SourceStart),Y
    adc SourceStart+1
    ldy SourceStartXByte
    jsr Memory::NormalizeAfterAdd
    jmp CheckEnd                            ; always
.endproc

.endscope

;; Ends the statement with BAD SUBSCRIPT.
;; Errors: <ERROR_BAD_SUBSCRIPT>
;; Also: BSERR (BB13)
.proc BadSubscriptError
    ldx #ERROR_BAD_SUBSCRIPT
    .byte $2C                               ; BIT absolute skips IllegalQuantityError's LDX
    ; Falls into IllegalQuantityError, past its load.
.endproc

;; Ends the statement with ILLEGAL QUANTITY.
;; Errors: <ERROR_ILLEGAL_QUANTITY>
;; Entry:
;;   ToError = ends the statement with the error in X; <Variables::ArrayFound> branches here with REDIM'D ARRAY
;; Also: FCERR (BB13)
.proc IllegalQuantityError
    ldx #ERROR_ILLEGAL_QUANTITY

;; Ends the statement with the error in X.
;; Also: ERRGO3 (BB13)
ToError:
    jmp ReportError
.endproc

.scope Variables continued

;; Found the array: in `DIM`, a REDIM'D ARRAY error; otherwise checks the count of subscripts and finds the element.
;;
;; With <SubscriptMode> set it returns with carry set and <SourceStart> at the entry, for a statement that names a whole
;; array; nothing in this BASIC sets it here.
;; Errors: <ERROR_REDIMENSIONED_ARRAY> = `DIM` of an array that exists, <ERROR_BAD_SUBSCRIPT> = the wrong count of
;;   subscripts
;; Also: GOTARY (BB13)
.proc ArrayFound
    ldx #ERROR_REDIMENSIONED_ARRAY
    lda Dimensioning
    bne IllegalQuantityError::ToError
    lda SubscriptMode
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
    jsr ElementsStart::CountPlus            ; ArrayPointer: the count of dimensions
    lda Counter
    ldy #0
    cmp (ArrayPointer),Y
    bne BadSubscriptError
    jmp ElementAddress
.endproc

;; Not found. From an expression (<TokenizeState> set), the array is not made: the subscripts are dropped and
;; <VariablePointer> points to <ZeroValue>, so the element reads as zero or an empty string.
;; See: <Variables::CreateArray>
;; Also: NOTFFD (BB13)
.proc ArrayNotFound
    lda TokenizeState
    beq CreateArray
    lda #<(ZeroValue)
    ldy #>(ZeroValue)
    sta VariablePointer
    sty VariablePointer+1

;; Drops a subscript from the stack.
;; Also: NOTFONE (BB13)
DropSubscript:
    pla
    pla
    dec Counter
    bne DropSubscript
    lda #0                                  ; ZeroValue's bank
    jmp ElementAddress::SetArrayFlags
.endproc

;; Makes the array at <VariablesStart>, the array table's end, moving the simple variable table up to make room.
;;
;; Each dimension's size is its subscript plus 1 in `DIM`, or 11 otherwise; the size of the whole entry is the element
;; size times every dimension's size, plus the head: the length, the name, the type, the count and the sizes. More
;; than 64K is OUT OF MEMORY. The sizes stay on the stack; <Variables::InitializeArray> writes the entry.
;; In: SourceStart = <VariablesStart>, Counter = the count of subscripts, on the stack
;; Errors: <ERROR_OUT_OF_MEMORY> = 64K or more, or no room
;; See: <Variables::MultiplyUnsigned>, <MoveRangeUp>
;; Also: NOTFF2 (BB13)
.proc CreateArray
    lda Counter
    sta Pointer1+1                          ; the dimensions left
    ldy #0
    sty LinearIndex+1
    ldy VariableSizes
    sty LinearIndex                         ; the element's size
    tsx                                     ; reads the subscripts in place

;; Multiplies <LinearIndex> by each dimension's size.
;; Also: SIZLOP (BB13)
NextDimension:
    lda #0
    ldy #DEFAULT_HIGHEST_SUBSCRIPT          ; not `DIM`
    bit Dimensioning
    bvc SizeFromHighest
    inx
    lda $0100,X                             ; `DIM`: the subscript's low byte
    inx
    tay
    lda $0100,X                             ; and high byte

;; Makes the dimension's size, one more than its highest subscript, in Y (low) and X (high).
;; Also: NOTDIM (BB13)
SizeFromHighest:
    stx Pointer1
    tax
    iny
    bne Multiply
    inx

;; Multiplies <LinearIndex> by the size, then takes the next dimension; past the last, adds the head's size.
;; Also: NOVFLW (BB13)
Multiply:
    jsr MultiplyUnsigned
    stx LinearIndex
    sty LinearIndex+1
    ldx Pointer1
    dec Pointer1+1
    bne NextDimension
    lda Counter
    asl
    sec                                     ; the count byte
    adc VariableSizes+1                     ; the name, its length bytes and type
    adc LinearIndex                         ; the elements
    sta LinearIndex
    bcc MoveSimpleVariables
    iny
    bne KeepHigh
    jmp ReportOutOfMemory                   ; 64K or more

;; Keeps the size's high byte.
;; Also: ALGOOD (BB13)
KeepHigh:
    clc
    sty LinearIndex+1

;; Moves the simple variable table, from <VariablesStart> to <VariablesEnd>, up by the entry's size, which moves
;; <VariablesEnd>.
;; Also: GOODIE (BB13)
MoveSimpleVariables:
    lda VariablesEnd
    sta SourceEnd
    adc LinearIndex
    sta DestinationEnd
    lda VariablesEnd+1
    sta SourceEnd+1
    adc LinearIndex+1
    ldy VariablesEndXByte
    sty SourceEndXByte
    jsr Memory::NormalizeAfterAdd
    sta DestinationEnd+1
    tya
    sta DestinationEndXByte
    tax
    lda DestinationEnd
    ldy DestinationEnd+1
    jsr MoveRangeUp
    .assert * = InitializeArray, "CreateArray must fall into InitializeArray, in B3UdefI.asm."
    ; Falls into InitializeArray.
.endproc

.endscope
