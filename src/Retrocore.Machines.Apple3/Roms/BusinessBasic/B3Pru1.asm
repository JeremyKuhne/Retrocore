; retrocore: style=strict
;; `PRINT USING`'s first half: finding the image, the loop over the expressions, printing literals and strings, and
;; the scanner that checks each spec and builds a number's edit mask.
;;
;; The image comes from a string literal, a string variable or an `IMAGE` statement, and is a list of specs separated
;; by commas:
;;
;; - A literal: text in quotes, X for a space or / for a new line.
;; - A string field: A to left-justify, C to center or R to right-justify, as wide as its count of letters.
;; - A number field: digit positions, # (leading zeros as spaces), Z (leading zeros printed) or & (spaces, with
;;   commas); ** for asterisk fill; $ or a floating $$; a sign, + or -, before or after the digits, or a floating ++
;;   or --; a decimal point; and EEE or EEEE for an exponent.
;;
;; A count before a character repeats it, so 5# is #####. The scanner keeps its state in the bytes of <Fac>, which are
;; free while it runs; the expression's value is kept as decimal digits in <UsingDigits> for the editor,
;; <PrintUsing::FormatNumber>, in B3Pru2.asm.

;; `PRINT USING` and the `IMAGE` format it prints through: reading the image, checking each spec and building a number
;; spec's edit mask, and writing numbers and strings into their fields.
;;
;; Business BASIC's own code, with no counterpart in Microsoft's BASIC. `IMAGE` itself is skipped like `REM` when it
;; runs; only `PRINT USING` reads it.
.scope PrintUsing

; ---------------------------------------------------------------------------------------------------------------------
; The scanner's and the editor's state, in the bytes of Fac and the bytes after it
; ---------------------------------------------------------------------------------------------------------------------

;; The spec character <ReadFormatCharacter> found, as the image gives it (upper or lower case); `9` while it reads a
;; count.
;; Also: DELIM (BB13)
SpecCharacter = Fac+1

;; The spec character's count: the repeat count before it, or the run of the same character.
;; Also: REP (BB13)
RepeatCount = Fac+2

;; The count of digit positions before the decimal point.
;; Also: DIGB4DPT (BB13)
DigitsBeforePoint = Fac+24

;; The count of digit positions after the decimal point.
;; Also: DIGAFDPT (BB13)
DigitsAfterPoint = Fac+25

;; The length of a literal, or of the string to print.
;; Also: SAVLEN (BB13)
TextLength = Fac+6

;; The spec's type: <SPEC_NUMBER>, <FIELD_STRING>, <FIELD_LITERAL>, or <SPEC_END> when none was found.
;; Also: SPECTYP (BB13)
SpecType = Fac+7

;; While a spec is scanned, the digit positions counted but not yet put in the mask; while a number is edited, the
;; count of digits <NextDigit> has taken.
;; Also: DIGCTR (BB13)
DigitCounter = Fac+8

;; The power of ten of the digit the editor wants.
;; Also: DIGEXP (BB13)
DigitPower = Fac+9

;; The string's length, kept while its spec is found.
;; Also: USVSTRL (BB13)
StringLength = Fac+9

;; The decimal point's index in the mask, <NO_INDEX> for none.
;; Also: DPTNDX (BB13)
PointIndex = Fac+10

;; The digit class so far: <FIELD_ZERO_FILLED>, <FIELD_SPACE_FILLED> or <FIELD_COMMAS>, 0 for none.
;; Also: NMASK (BB13)
DigitClass = Fac+11

;; The editor's adjustment to the exponent, for engineering notation.
;; Also: EXPADJ (BB13)
ExponentAdjustment = Fac+11

;; The spec's parts: <PARTS_DIGITS>, and the codes of the editing characters it has (<FIELD_SIGN>, with <PARTS_PLUS>
;; for +, <FIELD_DOLLAR>, <FIELD_EXPONENT> and <FIELD_POINT>).
;; Also: EMASK (BB13)
SpecParts = Fac+12

;; The floating symbols: <FLOAT_ASTERISKS>, <FLOAT_DOLLAR>, <FLOAT_SIGN> and <FLOAT_DOLLAR_AFTER_SIGN>.
;; Also: FLTMSK (BB13)
FloatingSymbols = Fac+13

;; The text X or / prints: a space, or a return and a line feed.
;; Also: LITRLCH (BB13)
LiteralText = Fac+14

;; In engineering notation, the mask index of the first digit.
;; Also: SPCB4DIG (BB13)
FirstDigitPlace = Fac+14

;; The edit mask, <MASK_SIZE> bytes of string space from <Strings::ReserveSpace>, with its X-byte at <NewStringXByte>.
;; Also: MASKPT (BB13)
MaskPointer = NewString

;; $FF once a spec has taken a value, so the image may start over.
;; Also: VSPEC (BB13)
ValueSpecSeen = Fac+29

;; How the statement ends: 0 with a new line, a semicolon without one.
;; Also: ENDFLG (BB13)
EndingSeparator = ValueSpecSeen

;; The index of the mask's last byte, <NO_INDEX> while it is empty; the editor makes it the mask's length.
;; Also: MSKNDX (BB13)
MaskIndex = Fac+16

;; The image's address, with its X-byte at <ImagePointerXByte>.
;; Also: SPCPTR (BB13)
ImagePointer = Fac+17

;; The image's address's high byte.
;; Also: SPCPTRH (BB13)
ImagePointerHigh = Fac+17+1

;; The index of the image's character last read.
;; Also: SPCNDX (BB13)
ImageIndex = Fac+19

;; The image's length, 1 to 255.
;; Also: SPCLEN (BB13)
ImageLength = Fac+20

;; The mask index of the units digit, <NO_INDEX> for none.
;; Also: TENZNDX (BB13)
UnitsIndex = Fac+21

;; The editor's count of digits since a comma.
;; Also: CMACTR (BB13)
CommaCounter = Fac+22

;; Which half of a decimal byte <UnpackDecimal> takes next: bit 7 set for the high digit.
;; Also: HALF (BB13)
NextHalf = Fac+22

;; The character for leading zeros, with <FILL_COMMAS> set to put in commas.
;; Also: CMAFILL (BB13)
FillCharacter = Fac+23

;; The image's X-byte: its bank.
;; Also: SPCPTRB (BB13)
ImagePointerXByte = ImagePointer+X_BYTE_OFFSET

; ---------------------------------------------------------------------------------------------------------------------
; Values
; ---------------------------------------------------------------------------------------------------------------------

;; Z's digit class: leading zeros printed. The lowest class, and the class of every digit after the point.
;; Also: ZTYP (BB13)
FIELD_ZERO_FILLED = $41

;; &'s digit class: leading zeros as spaces, with commas put in. The highest class.
;; Also: CMATYP (BB13)
FIELD_COMMAS = $44

;; #'s digit class: leading zeros as spaces.
;; Also: DTYP (BB13)
FIELD_SPACE_FILLED = $42

;; The edit mask's size, the widest number field.
;; Also: MSKLEN (BB13)
MASK_SIZE = 32

; The format characters' types, from <FormatTypes>. The top two bits give the class: 01 a digit, 00 an editing
; character, 10 a literal, 11 a string. An editing character's code is the bit it sets in SpecParts.

;; A string field's type: A, C or R.
FIELD_STRING = $FF

;; A literal's type: a quote, X or /.
FIELD_LITERAL = $80

;; A sign's type, for -: a space or a minus.
FIELD_SIGN = $20

;; +'s type: a sign, with <PARTS_PLUS>.
FIELD_PLUS = FIELD_SIGN | PARTS_PLUS

;; $'s type.
FIELD_DOLLAR = $10

;; E's type: the exponent.
FIELD_EXPONENT = $08

;; The decimal point's type.
FIELD_POINT = $04

;; *'s type: asterisk fill.
FIELD_ASTERISK = $02

; The bits of SpecParts that are not an editing character's code.

;; The spec has digit positions.
PARTS_DIGITS = $80

;; The sign is +, which prints + or -, rather than -, which prints a space or -.
PARTS_PLUS = $01

; The bits of FloatingSymbols.

;; ** fills the places before the digits with asterisks.
FLOAT_ASTERISKS = $10

;; A floating $, before a floating sign or with none.
FLOAT_DOLLAR = $20

;; A floating sign.
FLOAT_SIGN = $40

;; A floating $ after a floating sign, so nearer the digits.
FLOAT_DOLLAR_AFTER_SIGN = $80

;; The bit of <FillCharacter> that puts commas in, for &.
FILL_COMMAS = $80

; The values of SpecType besides FIELD_STRING and FIELD_LITERAL.

;; A number spec.
SPEC_NUMBER = 0

;; No spec: the image's end.
SPEC_END = 1

;; An index for none: no decimal point, no units digit, an empty mask; and an index one before the first.
NO_INDEX = $FF

;; The count of a doubled symbol, which floats: $$, ++, -- and **.
FLOAT_RUN = 2

;; The fewest & places, room for a comma: #,###.
COMMA_MIN_PLACES = 5

;; The digits between commas.
DIGITS_PER_COMMA = 3

;; The step of engineering notation's exponent.
ENGINEERING_STEP = 3

;; The smallest count no digit may follow: 26 or more, times ten, is past 255.
COUNT_LIMIT = 255 / 10 + 1

;; What <SpecCharacter> holds while a count is read: no format character is a digit.
COUNT_MARK = '9'

;; The bit that makes a letter lower case.
LOWER_CASE_BIT = $20

;; A stored line's link and line number, before its tokens.
LINE_HEADER_SIZE = 3

; The number's digits in UsingDigits, one a byte.

;; The index in <UsingDigits> of the first digit.
DIGITS_START = 2

;; The digits <UnpackDecimal> unpacks.
DIGIT_COUNT = 20

;; The index in <UsingDigits> just past the digits, where <UnpackDecimal> writes a 0.
DIGITS_END = DIGITS_START + DIGIT_COUNT

;; The lowest digit that rounds up.
ROUND_UP_DIGIT = 5

; ---------------------------------------------------------------------------------------------------------------------
; PRINT USING
; ---------------------------------------------------------------------------------------------------------------------

;; `PRINT USING`: prints each expression through the next number or string spec of the image, with the literals
;; between.
;;
;; The image follows `USING` as a line number (of an `IMAGE` statement), a string literal or a string variable, then a
;; semicolon and the expressions, separated by commas; a semicolon may only end the statement. When the image runs out
;; of specs it starts over; when the expressions run out, the literals up to the next number or string spec are printed,
;; and a spec left over is a type mismatch. A semicolon at the end leaves the line open.
;; In: TextPointer = `USING`
;; Errors: SYNTAX ERROR, UNDEF'D STATEMENT for a line that is not an `IMAGE`, TYPE MISMATCH, ILLEGAL QUANTITY
;; See: <ScanSpec>, <FormatNumber>
;; Also: PRUSING (BB13)
.proc Statement
    jsr GetNextCharacter
    bcc TakeImageStatement                  ; a line number
    cmp #'"'
    beq TakeLiteral
    jsr IsLetter                            ; a variable?
    bcc ToSyntaxError
    jsr FindVariable
    cpx #VALUE_TYPE_STRING
    bne ToSyntaxError
    sta Pointer1
    sty Pointer1+1
    lda VariablePointerXByte
    sta Pointer1XByte
    jsr Strings::FindFromDescriptor         ; the string itself
    sta ImageLength
    stx ImagePointer
    sty ImagePointerHigh
    lda Pointer1XByte
    sta ImagePointerXByte
    jmp StartList

;; Takes the image from a string literal, which may not be empty.
;; Also: ULITRL (BB13)
TakeLiteral:
    ldy #0

;; Takes the literal's next character.
;; Also: ULITS (BB13)
LiteralLoop:
    jsr GetNextCharacter
    beq ToSyntaxError                       ; no closing quote
    cpy #0
    bne CheckQuote
    ldx TextPointer                         ; the first character: the image starts here
    stx ImagePointer
    ldx TextPointer+1
    stx ImagePointer+1
    ldx TextPointerXByte
    stx ImagePointerXByte

;; Ends the literal at its closing quote.
;; Also: ULITX (BB13)
CheckQuote:
    cmp #'"'
    beq LiteralEnd
    iny
    bne LiteralLoop

;; Keeps the literal's length; an empty one, or the statement's end after it, is a syntax error.
;; Also: ULITE (BB13)
LiteralEnd:
    sty ImageLength
    tya
    beq ToSyntaxError                       ; empty
    jsr GetNextCharacter
    bne StartList
    ; Falls into ToSyntaxError.
.endproc

;; Ends the statement with a syntax error.
;; Also: USNERR (BB13)
.proc ToSyntaxError
    jmp SyntaxError
.endproc

;; Ends the statement with an undefined-statement error: the line is not an `IMAGE` statement, or the image is empty.
;; Also: UIMERR (BB13)
.proc NoImageError
    ldx #ERROR_UNDEFINED_STATEMENT
    jmp ReportError
.endproc

;; Takes the image from the `IMAGE` statement at the line number in the program text, the rest of its line.
;; Errors: UNDEF'D STATEMENT for no such line, or a line that is not an `IMAGE`, or an empty one
;; Also: UIMAGE (BB13)
.proc TakeImageStatement
    jsr ReadLineNumber
    lda TextPointer
    pha
    lda TextPointer+1
    pha
    lda TextPointerXByte
    pha
    jsr Statements::GoTo::ToLineNumber      ; find the line
    ldy #LINE_HEADER_SIZE
    jsr AdvanceTextPointer                  ; past its link and number
    jsr GetNextCharacter
    tax
    cpx #TOKEN_IMAGE
    bne NoImageError
    jsr GetNextCharacter
    beq NoImageError
    lda TextPointer
    sta ImagePointer
    lda TextPointer+1
    sta ImagePointer+1
    lda TextPointerXByte
    sta ImagePointerXByte
    jsr FindLineEnd                         ; the length to the line's end
    sty ImageLength
    pla
    sta TextPointerXByte
    pla
    sta TextPointer+1
    pla
    sta TextPointer
    ; Falls into StartList.
.endproc

;; Starts on the expressions after the image's semicolon; an image that is empty or starts with a comma is a syntax
;; error.
;; Entry:
;;   SkipSeparator = skips the image's semicolon or a comma between the expressions, then takes the next
;; Also: UGOTSPT (BB13)
.proc StartList
    jsr GetCurrentCharacter
    cmp #';'
    bne ToSyntaxError
    ldx #NO_INDEX
    stx ImageIndex
    jsr ReadNext
    beq ToSyntaxError
    stx ImageIndex                          ; back before the first character
    inx
    stx ValueSpecSeen                       ; no spec has taken a value yet

;; Skips the image's semicolon or a comma between the expressions.
;; Also: USKPNXT (BB13)
SkipSeparator:
    jsr GetNextCharacter
    bne NextExpression::CheckEnd            ; past NextExpression's GetCurrentCharacter
    ; Falls into NextExpression.
.endproc

;; Takes the next expression; at the statement's end, or a semicolon, prints the image's last literals.
;; Entry:
;;   CheckEnd = takes the character in A, flags as <GetCurrentCharacter> sets them
;; Also: UNXTEXP (BB13)
.proc NextExpression
    jsr GetCurrentCharacter

;; Takes the character in A.
CheckEnd:
    bne CheckSeparator
    lda #0
    beq Finish

;; Skips a comma, ends at a semicolon, or evaluates the next expression.
;; Also: UNXTEXC (BB13)
CheckSeparator:
    cmp #','
    beq StartList::SkipSeparator
    cmp #';'
    bne Evaluate
    ; Falls into Finish.
.endproc

;; Ends the statement: prints the literals left before the next number or string spec, then a new line unless a
;; semicolon ended it. A number or string spec found there, with no value for it, is a type mismatch.
;; In: A = 0 at the statement's end, or a semicolon
;; Also: UTAILS (BB13)
.proc Finish
    sta EndingSeparator
    tax
    beq CheckFollowing
    jsr GetNextCharacter                    ; nothing may follow the semicolon
CheckFollowing:
    beq PrintTail
    jmp ToSyntaxError
PrintTail:
    lda #MASK_SIZE
    jsr Strings::ReserveSpace               ; the mask, for the scan
    jsr PrintLiterals
    jsr FreeMask
    .assert SPEC_END = 1, "Finish takes SPEC_END to zero with a DEC."
    dec SpecType                            ; SPEC_END, the image's end, is the only good result
    beq EndLine
    jmp FindValueSpec::ToTypeMismatchError
EndLine:
    lda EndingSeparator
    bne Done
    jmp PrintNewline
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Each expression
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates the next expression, or `SCALE(n, expression)`, and makes it ready to print: a number as decimal digits
;; in <UsingDigits>, a string as its pointer and length.
;;
;; The image's place is kept on the stack meanwhile, as the evaluator uses the bytes of <Fac>. `SCALE`'s n, a signed
;; byte, goes to the editor in <ArrayElementFound>; it is 0 otherwise.
;; Also: UEVAL (BB13)
.proc Evaluate
    lda ImageIndex
    pha
    lda ImageLength
    pha
    lda ImagePointer
    pha
    lda ImagePointerHigh
    pha
    lda ValueSpecSeen
    pha
    lda #0                                  ; no scale
    pha
    jsr GetCurrentCharacter
    cmp #TOKEN_SCALE
    bne NoScale
    jsr GetNextCharacter
    jsr EvaluateSignedByte
    pla                                     ; the scale in place of the 0
    txa
    pha
    jsr CheckComma
    lda #VALUE_TYPE_ANY
    sta ValueType                           ; EvaluateSignedByte set it
    jsr EvaluateExpression
    jsr CheckCloseParenthesis
    beq Prepare                             ; then the end, a comma or a semicolon
    cmp #','
    beq Prepare
    cmp #';'
    beq Prepare
    jmp SyntaxError

;; Evaluates an expression of any type.
;; Also: UNOSCALE (BB13)
NoScale:
    lda #VALUE_TYPE_ANY
    sta ValueType
    jsr EvaluateExpression

;; Makes the value ready by its type: a string's pointer to <Pointer1> and its length to <StringLength>, a long
;; integer's digits by <LongInteger::FacToDigits>, or a real's from <Float::FormatFac>'s text.
;; Also: UGOTNUM (BB13)
Prepare:
    bit ValueType
    bpl UnpackReal
    jsr Strings::FindFacString              ; a string
    sta StringLength
    jmp RestorePlace

;; Unpacks a long integer's digits into <UsingDigits>, its exponent to <FacExponent>.
;; Also: UDTYPE (BB13)
UnpackLong:
    jsr LongInteger::FacToDigits
    lda ArrayElementFound
    sta FacExponent
    jmp RestorePlace

;; Turns a real into decimal digits in <UsingDigits>, from <DIGITS_START>, through <Float::FormatFac>'s text; its
;; exponent less 1, times 2, plus 1 when negative, goes to <FacExponent>.
;; Also: UNTYPE (BB13)
UnpackReal:
    bvs UnpackLong                          ; a long integer
    lda FacSign
    pha
    jsr Float::FormatFac
    pla
    cmp #$80                                ; carry = the sign
    php
    lda ArrayElementFound                   ; Float::FormatFac's exponent
    sec
    sbc #1
    plp
    rol
    sta FacExponent
    ldy #DIGITS_START
    ldx #0

;; Copies <Float::FormatFac>'s digits, skipping the point, a minus and leading zeros, up to the first other character.
;; Also: STRBCD0 (BB13)
CopyDigit:
    lda NumberBuffer,X
    cmp #'.'
    beq SkipCharacter
    cmp #'-'
    beq SkipCharacter
    cmp #'9'+1
    bcs DigitsDone
    sbc #'0'-1
    bcc DigitsDone
    bne StoreDigit
    cpy #DIGITS_START                       ; a zero before any other digit
    beq SkipCharacter
StoreDigit:
    sta UsingDigits,Y
    iny

;; Goes on to <Float::FormatFac>'s next character.
;; Also: STRBCD1 (BB13)
SkipCharacter:
    inx
    bne CopyDigit                           ; always

;; Fills the places after the digits with zeros, up to <DIGITS_END>.
;; Also: STRBCD2 (BB13)
DigitsDone:
    lda #0

;; Writes the next zero.
;; Also: STRBCD3 (BB13)
ZeroLoop:
    sta UsingDigits,Y
    iny
    cpy #DIGITS_END
    bne ZeroLoop

;; Takes the image's place and the scale back off the stack, then finds the value's spec.
;; Also: USTKSAV (BB13)
RestorePlace:
    pla
    sta ArrayElementFound
    pla
    sta ValueSpecSeen
    pla
    sta ImagePointerHigh
    pla
    sta ImagePointer
    pla
    sta ImageLength
    pla
    sta ImageIndex
    lda #MASK_SIZE
    jsr Strings::ReserveSpace
    ; Falls into FindValueSpec.
.endproc

;; Prints the literals up to the next number or string spec; at the image's end starts over from its first spec,
;; unless no spec in it takes a value, which is a type mismatch.
;; Entry:
;;   ToTypeMismatchError = ends the statement with a type mismatch
;; Also: UNXTSPC (BB13)
.proc FindValueSpec
    jsr PrintLiterals
    ldx SpecType
    beq CheckType                           ; a number
    bmi CheckType                           ; a string
    lda ValueSpecSeen
    beq FreeMaskThenTypeMismatch
    sta ImageIndex                          ; $FF: start over
    bne FindValueSpec                       ; always

;; Checks the value's type against the spec's, then prints it.
;; Also: UVSPEC (BB13)
CheckType:
    lda #$FF
    sta ValueSpecSeen
    sec
    lda ValueType
    tax
    sbc SpecType
    lsr                                     ; carry = set when only one is a string
    bcc TypesMatch

;; Frees the mask, then ends the statement with a type mismatch.
;; Also: UTMERR2 (BB13)
FreeMaskThenTypeMismatch:
    jsr FreeMask

;; Ends the statement with a type mismatch.
;; Also: UTMERR (BB13)
ToTypeMismatchError:
    jmp TypeMismatchError

;; Prints a string or a number.
TypesMatch:
    txa
    bpl ToPrintNumber
    jmp FormatString
ToPrintNumber:
    jmp PrintNumber
.endproc

;; Clears the mask, scans the next spec, and prints it when it is a literal, until a number or string spec or the
;; image's end.
;; Out: SpecType = <SPEC_NUMBER> for a number spec, <FIELD_STRING> for a string spec, <SPEC_END> at the image's end
;; See: <ScanSpec>
;; Also: UDOLITS (BB13)
.proc PrintLiterals
    ldy #MASK_SIZE-1
    lda #0

;; Clears the mask's next byte, from the last.
;; Also: UBLKMSK (BB13)
ClearMask:
    sta (MaskPointer),Y
    dey
    bpl ClearMask
    jsr ScanSpec
    bit SpecType
    bmi PrintLiteral

;; Returns.
;; Also: UDOXIT (BB13)
Done:
    rts

;; Prints a literal, unless the spec was a string's.
;; Also: ULITOUT (BB13)
PrintLiteral:
    bvs Done                                ; a string

;; Prints the literal at <SourceStart>, <TextLength> bytes, <RepeatCount> times, then goes on to the next spec.
;;
;; An empty literal, "", has a length of 0, and prints 256 bytes (a bug of the original).
;; Also: UREPEAT (BB13)
Repeat:
    ldy #0
    ldx TextLength

;; Prints the literal's next byte.
;; Also: UOUTLP (BB13)
OutputLoop:
    lda (SourceStart),Y
    jsr PrintCharacter
    iny
    dex
    bne OutputLoop
    dec RepeatCount
    bne Repeat
    beq PrintLiterals
.endproc

;; Prints a string through its spec, cut to the field's width or padded with spaces: A puts the spaces after it, C
;; half before, and R all before; then takes the next expression.
;; In: Pointer1 = the string, StringLength = its length, RepeatCount = the field's width, SpecCharacter = the spec's
;;   letter
;; Also: USTRVAR (BB13)
.proc FormatString
    lda StringLength
    sta TextLength
    lda RepeatCount                         ; the width less the length
    sec
    sbc TextLength
    beq CopyText
    bcs Fits
    ldx RepeatCount                         ; too long: cut it
    stx TextLength
    jmp CopyText

;; Prints the spaces before a string shorter than its field.
;; In: A = the spaces to spare
;; Also: USFITS (BB13)
Fits:
    ldy SpecCharacter
    cpy #'A'
    beq CopyText
    cpy #'a'
    beq CopyText
    cpy #'C'
    beq Center
    cpy #'c'
    bne PadBefore
Center:
    ldx TextLength
    beq PadBefore
    lsr                                     ; centered: half before

;; Prints A spaces, counting them off the width.
;; Also: UEATME (BB13)
PadBefore:
    tax
    inx

;; Prints the next space.
;; Also: ULSPCS (BB13)
PadBeforeLoop:
    dex
    beq CopyText
    jsr PrintSpace
    dec RepeatCount
    bne PadBeforeLoop

;; Prints the string's <TextLength> characters, then spaces to the field's end.
;; Also: UEXACT (BB13)
CopyText:
    ldy #0
    ldx TextLength
    beq PadAfter

;; Prints the string's next character.
;; Also: UEXACT2 (BB13)
TextLoop:
    lda (Pointer1),Y
    jsr PrintCharacter
    iny
    dec RepeatCount
    dex
    bne TextLoop

;; Prints spaces to the field's end.
;; Also: UNULL (BB13)
PadAfter:
    ldx RepeatCount

;; Prints the next space, or frees the string at the field's end.
;; Also: UFILL3 (BB13)
PadAfterLoop:
    beq FreeStringThenNext
    jsr PrintSpace
    dex
    jmp PadAfterLoop
.endproc

;; Prints a number through its mask, then takes the next expression.
;; See: <FormatNumber>
;; Also: UNUMVAR (BB13)
.proc PrintNumber
    jsr FormatNumber
    ; Falls into FreeMaskThenNext.
.endproc

;; Frees the mask and takes the next expression.
;; Also: UFREMSK (BB13)
.proc FreeMaskThenNext
    jsr FreeMask
    jmp NextExpression
.endproc

;; Frees the string, if it was a temporary one, and the mask, then takes the next expression.
;; Also: UFRESTR (BB13)
.proc FreeStringThenNext
    jsr Strings::FreeFacTemporary
    jmp FreeMaskThenNext
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Reading the image
; ---------------------------------------------------------------------------------------------------------------------

;; Frees the mask's <MASK_SIZE> bytes of string space.
;; See: <Strings::FreeSpace>
;; Also: UFRESPC (BB13)
.proc FreeMask
    lda #MASK_SIZE
    ldy NewString+1
    ldx NewString
    stx Pointer1
    sty Pointer1+1
    ldx NewStringXByte
    stx Pointer1XByte
    jmp Strings::FreeSpace
.endproc

;; Drops <ReadNonSpace>'s saved status and reads on past a space.
;; Also: UREGET (BB13)
.proc SkipSpace
    pla
    ; Falls into ReadNonSpace.
.endproc

;; Reads the image's next character other than a space, and classifies it as <ClassifyCharacter> does.
;; Out: A = the character, Y and the flags as <ClassifyCharacter> sets them
;; Keeps: X
;; See: <ReadNext>
;; Also: UGETCHR (BB13)
.proc ReadNonSpace
    jsr ReadNext
    php
    cmp #' '
    beq SkipSpace
    plp
    rts
.endproc

;; Moves <ImageIndex> to the image's next character, and classifies it as <ClassifyCharacter> does.
;; Out: A = the character, Y and the flags as <ClassifyCharacter> sets them
;; Keeps: X
;; Also: UGETCH (BB13)
.proc ReadNext
    inc ImageIndex
    ; Falls into ClassifyCharacter.
.endproc

;; Classifies the image's character at <ImageIndex>.
;;
;; An index of $FF, past a 255-character image, reads as the end, and stays there.
;; In: ImageIndex = the character's index, ImagePointer = the image, ImageLength = its length
;; Out: A = the character (0 at the end), Y = the character for one that is not a comma or a letter, zero = set at the
;;   end or a comma, carry = clear for a digit, overflow = set for an upper-case letter
;; Keeps: X
;; Also: IGOTCH (BB13)
.proc ClassifyCharacter
    ldy ImageIndex
    lda #0
    cpy #NO_INDEX
    bne InImage
    dec ImageIndex
    bne SetZero

;; Reads the character, or the end past the image's length.
;; Also: UGETCKL (BB13)
InImage:
    cpy ImageLength
    bcs SetZero                             ; the end
    lda (ImagePointer),Y
    cmp #','
    beq Done
    cmp #'A'
    bcc CheckDigit
    cmp #'Z'+1
    bcc Letter

;; Sets carry clear for a digit.
;; Also: UGETCKD (BB13)
CheckDigit:
    cmp #'9'+1
    bcs SetZero
    sec                                     ; carry = clear for a digit, and A as it was
    sbc #'0'
    sec
    sbc #$100-'0'

;; Sets zero for 0, the end.
;; Also: UGETNE (BB13)
SetZero:
    tay

;; Returns with overflow clear.
;; Also: UGETEND (BB13)
Done:
    clv
    rts

;; Returns an upper-case letter with overflow set and carry set.
;; Also: UGETVS (BB13)
Letter:
    bit Compare+1                           ; the $40 of the CMP sets overflow
Compare:
    cmp #$40
    rts
.endproc

;; Adds A to the mask.
;;
;; A mask longer than <MASK_SIZE> bytes is a syntax error.
;; In: A = the byte
;; Out: Y = the byte's index, MaskIndex = Y
;; Keeps: A, X
;; Entry:
;;   ToSyntaxError = ends the statement with a syntax error
;; Also: UATOMSK (BB13)
.proc AddToMask
    ldy MaskIndex
    iny
    cpy #MASK_SIZE
    bcs ToSyntaxError
    sta (MaskPointer),Y
    sty MaskIndex
    rts

;; Ends the statement with a syntax error.
;; Also: USYERR (BB13)
ToSyntaxError:
    jmp PrintUsing::ToSyntaxError
.endproc

;; Puts the digit positions counted in <DigitCounter> into the mask as zeros, and sets <DigitsBeforePoint> or
;; <DigitsAfterPoint> to their count.
;;
;; Before the decimal point, the last one's index is the units digit's, in <UnitsIndex>. It is a syntax error for
;; digits before the point that are all Z in a field with a floating symbol, or for fewer than <COMMA_MIN_PLACES> &
;; places.
;; Out: A = as it was, Y = 2, DigitClass = 0
;; Also: UDOMASK (BB13)
.proc PutDigitsInMask
    pha
    ldy DigitCounter
    beq Done
    ldx #1                                  ; after the point
    lda #FIELD_POINT
    bit SpecParts
    php                                     ; zero = set before the point
    bne CountDigits
    lda DigitClass
    cmp #FIELD_ZERO_FILLED
    bne BeforePoint
    lda FloatingSymbols
    bne AddToMask::ToSyntaxError

;; Counts the digits before the point.
;; Also: UNOTZ (BB13)
BeforePoint:
    dex

;; Sets the count, and checks the room for commas.
;; Also: UAFDPT (BB13)
CountDigits:
    tya
    sta DigitsBeforePoint,X
    ldx DigitClass
    beq AddToMask::ToSyntaxError
    cpx #FIELD_COMMAS
    bne AddZeros
    cmp #COMMA_MIN_PLACES                   ; room for #,###
    bcc AddToMask::ToSyntaxError

;; Puts the digits into the mask.
;; Also: UANYSIZ (BB13)
AddZeros:
    lda #0

;; Puts the next digit into the mask.
;; Also: UDOMSKL (BB13)
ZeroLoop:
    jsr AddToMask
    dec DigitCounter
    bne ZeroLoop
    plp
    bne Done
    sty UnitsIndex

;; Returns.
;; Also: UDONT (BB13)
Done:
    ldy #FLOAT_RUN
    lda #0
    sta DigitClass
    pla
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The spec scanner
; ---------------------------------------------------------------------------------------------------------------------

;; Scans the image's next spec, checking its syntax, and builds a number spec's edit mask at <MaskPointer>, or points
;; <SourceStart> and <TextLength> at a literal's text.
;;
;; A number spec's parts may come in this order: **, $ or a sign (a fixed $ or sign goes into the mask, a floating
;; one only reserves its place), $ again, the digits and decimal point, a trailing sign, then the exponent's E's. A
;; spec must end at a comma or the image's end; anything else is a syntax error. A number spec returns from
;; <FinishNumberSpec>, and the image's end from <ReadFormatCharacter>, straight to this routine's caller.
;; Out: SpecType = <SPEC_NUMBER> for a number, <FIELD_STRING> for a string, <FIELD_LITERAL> for a literal, <SPEC_END>
;;   at the image's end, RepeatCount = its count, SpecCharacter = its character
;; See: <ReadFormatCharacter>, <PrintLiterals>
;; Also: IMSYNCK (BB13)
.proc ScanSpec
    ldy #SPEC_END
    sty SpecType                            ; none, until one is found
    dey
    sty FillCharacter
    sty DigitsBeforePoint
    sty DigitsAfterPoint
    sty FloatingSymbols
    sty DigitCounter
    sty SpecParts
    sty DigitClass
    dey
    sty PointIndex                          ; NO_INDEX
    sty UnitsIndex
    sty MaskIndex
    jsr ReadFormatCharacter
    bpl NumberSpec                          ; a number spec's character
    sta SpecType
    bit SpecType
    bvs CheckSpecEnd                        ; a string: done
    lda SpecCharacter
    cmp #'/'
    beq NewLineLiteral
    cmp #'X'
    beq NewLineLiteral::SpaceLiteral
    cmp #'x'
    beq NewLineLiteral::SpaceLiteral
    lda ImageIndex                          ; a quoted literal: it starts after the quote
    sec
    adc ImagePointer
    ldy ImagePointer+1
    ldx ImagePointerXByte
    bcc Store
    iny
    jsr Memory::WrapPage
Store:
    sta SourceStart
    sty SourceStart+1
    stx SourceStartXByte
    ldx #<(0-1)

;; Counts the literal's characters up to its closing quote; with none, it is a syntax error.
;; Also: UQSCAN (BB13)
QuoteLoop:
    inx
    jsr ReadNext
    cmp #0
    beq CheckSpecEnd::ToSyntaxError
    cmp #'"'
    bne QuoteLoop
    stx TextLength
    jsr ReadNonSpace
    ; Falls into CheckSpecEnd.
.endproc

;; Returns when the spec ends at a comma or the image's end, or ends the statement with a syntax error.
;; Entry:
;;   ToSyntaxError = ends the statement with a syntax error
;; Also: UCHEKCM (BB13)
.proc CheckSpecEnd
    jsr ClassifyCharacter
    bne ToSyntaxError
    rts

;; Ends the statement with a syntax error.
;; Also: USNERRL (BB13)
ToSyntaxError:
    jmp PrintUsing::ToSyntaxError
.endproc

;; Makes / a literal of a return and a line feed, then checks the spec's end.
;; Entry:
;;   SpaceLiteral = makes X a literal of a space
;; Also: UCRLIT (BB13)
.proc NewLineLiteral
    lda #CHARACTER_LINE_FEED
    sta LiteralText+1
    ldy #2
    lda #CHARACTER_RETURN
    bne Store

;; Makes X a literal of a space.
;; Also: USPLIT (BB13)
SpaceLiteral:
    lda #' '
    ldy #1
Store:
    sta LiteralText
    ldx #>(LiteralText)
    lda #LiteralText
    sta SourceStart
    stx SourceStart+1
    sty SourceStartXByte                    ; 1 or 2: no bank, as for the zero page
    sty TextLength
    bne CheckSpecEnd
.endproc

;; Starts a number spec: takes **, which must be exactly two, for asterisk fill.
;; In: A = the spec character's type
;; Also: UNUMTYP (BB13)
.proc NumberSpec
    ldy #FLOAT_RUN
    cmp #FIELD_ASTERISK
    bne TakeLeadingSign
    cpy RepeatCount
    bne TakeLeadingSign::ToSyntaxError
    lda #FLOAT_ASTERISKS
    sta FloatingSymbols
    lda SpecCharacter
    sta FillCharacter
    jsr RequireSpecCharacter
    jmp TakeLeadingSign
.endproc

;; Takes a $, or returns when A is not one: $$ floats; one $ floats after ** or a floating sign, and otherwise goes
;; into the mask. A second $ in the spec, or $$ after another floating symbol, is a syntax error.
;; In: A = the spec character's type, Y = 2
;; Out: A = the next spec character's type after a $, as it was otherwise, Y = 2
;; Also: UDOLAR (BB13)
.proc TakeDollar
    cmp #FIELD_DOLLAR
    beq IsDollar
    rts
IsDollar:
    bit SpecParts
    bne TakeLeadingSign::ToSyntaxError
    ora SpecParts
    sta SpecParts
    cpy RepeatCount
    bne Single
    lda FloatingSymbols
    bne TakeLeadingSign::ToSyntaxError
    beq Floating

;; Takes a single $.
;; Also: UCK1DL (BB13)
Single:
    dey
    cpy RepeatCount
    bne TakeLeadingSign::ToSyntaxError
    lda FloatingSymbols
    beq Fixed

;; Marks a floating $, after a floating sign or not, and reserves its place in the mask.
;; Also: UDLFLT (BB13)
Floating:
    cmp #FLOAT_SIGN                         ; after a floating sign?
    lda #FLOAT_DOLLAR
    bcc Mark
    .assert FLOAT_DOLLAR << 2 = FLOAT_DOLLAR_AFTER_SIGN, "Two shifts take a floating $ to after the sign."
    asl
    asl
Mark:
    ora FloatingSymbols
    sta FloatingSymbols
    inc MaskIndex
    jmp Next

;; Puts a fixed $ into the mask.
;; Also: USTDLR (BB13)
Fixed:
    lda SpecCharacter
    jsr AddToMask

;; Reads the spec's next character, which must be there.
;; Also: UXDLR (BB13)
Next:
    jmp RequireSpecCharacter
.endproc

;; Takes a $ and then a leading sign: ++ or -- floats; one sign floats after another floating symbol, and otherwise
;; goes into the mask. Then a $ after the sign.
;; In: A = the spec character's type, Y = 2
;; Entry:
;;   ToSyntaxError = ends the statement with a syntax error
;; Also: UDOLLR (BB13)
.proc TakeLeadingSign
    jsr TakeDollar
    .assert FIELD_SIGN = $20, "BIT TakeLeadingSign tests for a sign with the $20 of its JSR opcode."
    bit TakeLeadingSign                     ; its JSR's $20: a sign?
    beq DollarAfterSign
    ora SpecParts
    sta SpecParts
    cpy RepeatCount
    bne Single
    lda FloatingSymbols
    bne ToSyntaxError
    beq Floating

;; Takes a single sign.
;; Also: UCK1SIN (BB13)
Single:
    dey
    cpy RepeatCount
    bne ToSyntaxError
    lda FloatingSymbols
    beq Fixed

;; Marks a floating sign and reserves its place in the mask.
;; Also: UFLTSIN (BB13)
Floating:
    lda #FLOAT_SIGN
    ora FloatingSymbols
    sta FloatingSymbols
    inc MaskIndex
    jmp Next

;; Ends the statement with a syntax error.
;; Also: UNSERR (BB13)
ToSyntaxError:
    jmp PrintUsing::ToSyntaxError

;; Puts a fixed leading sign into the mask.
;; Also: USETSIN (BB13)
Fixed:
    lda SpecCharacter
    jsr AddToMask

;; Reads the spec's next character, which must be there.
;; Also: UXSIN (BB13)
Next:
    jsr RequireSpecCharacter

;; Takes a $ after the sign.
;; Also: UTRYDL2 (BB13)
DollarAfterSign:
    jsr TakeDollar
    ; Falls into TakeDigits.
.endproc

;; Takes a run of digit positions, counting them in <DigitCounter> and noting the field's digit class and fill.
;;
;; The class is the highest of the digits' so far; after the decimal point it is Z's, as every digit there prints.
;; A string or literal character among them is a syntax error.
;; In: A = the spec character's type
;; Entry:
;;   More = reads the spec's next character, or finishes the spec at its end
;; Also: UTRYDIG (BB13)
.proc TakeDigits
    cmp #FIELD_ZERO_FILLED
    bcc TakePoint                           ; not a digit
    tax
    bmi TakeLeadingSign::ToSyntaxError
    lda #PARTS_DIGITS
    ora SpecParts
    sta SpecParts
    lda RepeatCount
    clc
    adc DigitCounter
    sta DigitCounter
    cpx DigitClass
    bcs Highest
    ldx DigitClass
Highest:
    lda #FIELD_POINT
    bit SpecParts
    beq BeforePoint
    ldx #FIELD_ZERO_FILLED                  ; after the point
    bne SetClass

;; Sets the fill for leading zeros from the class, or keeps **'s asterisk, with the comma bit for &.
;; Also: UB4DPT (BB13)
BeforePoint:
    lda FillCharacter
    and #$FF ^ FILL_COMMAS
    cmp #'*'
    beq SetFill
    lda a:FillCharacters-FIELD_ZERO_FILLED,X

;; Adds the comma bit and sets the fill.
;; Also: USETCMA (BB13)
SetFill:
    ora a:CommaFlags-FIELD_ZERO_FILLED,X
    sta FillCharacter

;; Sets the class.
;; Also: UXNMASK (BB13)
SetClass:
    stx DigitClass

;; Reads the spec's next character, or finishes the spec at its end.
;; Also: UXMORE (BB13)
More:
    jsr NextSpecCharacter
    jmp TakeDigits
.endproc

;; Puts the digits counted into the mask, then takes a decimal point, which must be single and the spec's only one.
;; In: A = the spec character's type
;; Also: UBLDMK (BB13)
.proc TakePoint
    jsr PutDigitsInMask
    cmp #FIELD_POINT
    bne TakeTrailingSign
    bit SpecParts
    bne TakeLeadingSign::ToSyntaxError
    dey
    cpy RepeatCount
    bne TakeLeadingSign::ToSyntaxError
    ora SpecParts
    sta SpecParts
    lda SpecCharacter
    jsr AddToMask
    lda MaskIndex
    sta PointIndex
    jmp TakeDigits::More
.endproc

;; Takes a trailing sign, which must be single and the spec's only one.
;; In: A = the spec character's type, Y = 2
;; Also: USGNCK (BB13)
.proc TakeTrailingSign
    bit TakeLeadingSign                     ; its JSR's $20: a sign?
    beq TakeExponent
    dey
    cpy RepeatCount
    bne FreeMaskThenSyntaxError
    bit SpecParts
    bne FreeMaskThenSyntaxError
    ora SpecParts
    sta SpecParts
    lda SpecCharacter
    jsr AddToMask
    jsr NextSpecCharacter
    ; Falls into TakeExponent.
.endproc

;; Takes the exponent, EEE or EEEE, which must end the spec; anything else is a syntax error.
;;
;; With an exponent, no floating symbol may come with 0 or 1 digit before the point, only a floating sign with 3, and
;; any other count is a syntax error.
;; In: A = the spec character's type, Y = 2
;; Also: UCKEXP (BB13)
.proc TakeExponent
    cmp #FIELD_EXPONENT
    bne FreeMaskThenSyntaxError
    iny
    cpy RepeatCount
    beq Mark
    iny
    cpy RepeatCount
    bne FreeMaskThenSyntaxError

;; Marks the exponent and puts its E's into the mask.
;; Also: UEEE (BB13)
Mark:
    ora SpecParts
    sta SpecParts
    lda SpecCharacter

;; Puts the next E into the mask.
;; Also: UEEELP (BB13)
MaskLoop:
    jsr AddToMask
    dec RepeatCount
    bne MaskLoop
    lda #FLOAT_ASTERISKS | FLOAT_DOLLAR | FLOAT_SIGN | FLOAT_DOLLAR_AFTER_SIGN ; no floating symbol
    ldx DigitsBeforePoint
    beq CheckFloating
    dex
    beq CheckFloating
    cpx #2
    bne FreeMaskThenSyntaxError
    lda #FLOAT_ASTERISKS | FLOAT_DOLLAR | FLOAT_DOLLAR_AFTER_SIGN ; only a floating sign

;; Checks the floating symbols the count allows.
;; Also: UENOFLT (BB13)
CheckFloating:
    and FloatingSymbols
    bne FreeMaskThenSyntaxError
    jsr CheckSpecEnd
    jsr FinishNumberSpec                    ; which does not return
.endproc

;; Reads the spec's next character, which must be there.
;; Out: A = its type, Y = 2
;; Also: UENDERR (BB13)
.proc RequireSpecCharacter
    jsr ClassifyCharacter
    beq FreeMaskThenSyntaxError
    bne NextSpecCharacter::Read
.endproc

;; Reads the spec's next character, or at its end finishes the spec with <FinishNumberSpec>.
;; Out: A = its type, Y = 2
;; Entry:
;;   Read = reads the spec's next character
;; Also: UCKDEND (BB13)
.proc NextSpecCharacter
    jsr ClassifyCharacter
    beq FinishNumberSpec

;; Reads the spec's next character.
;; Also: UNXTGET (BB13)
Read:
    jsr ReadFormatCharacter
    ldy #FLOAT_RUN
    rts
.endproc

;; Finishes a number spec: puts the last digits into the mask, and returns to <ScanSpec>'s caller with <SpecType>
;; <SPEC_NUMBER>, dropping the return address of the routine that called this one.
;;
;; A spec with no digits, or with a floating symbol and no digit before the point, is a syntax error.
;; Also: UDIGEND (BB13)
.proc FinishNumberSpec
    lda SpecParts
    bpl FreeMaskThenSyntaxError
    jsr PutDigitsInMask
    lda FloatingSymbols
    beq Accept
    lda DigitsBeforePoint
    beq FreeMaskThenSyntaxError

;; Marks the spec a number's and returns past the caller.
;; Also: UCKXIT (BB13)
Accept:
    lda #SPEC_NUMBER
    sta SpecType
    pla
    pla
    rts
.endproc

;; Frees the mask, then ends the statement with a syntax error.
;; Also: USTERR (BB13)
.proc FreeMaskThenSyntaxError
    jsr FreeMask
    jmp ToSyntaxError
.endproc

.endscope
