; retrocore: style=strict
;; `PRINT USING`'s second part: the reader that takes each format character from the image, the tables of format
;; characters, and the editor that writes a number into its field.

; PrintUsing, continued: the format characters and the number editor.
.scope PrintUsing continued

; ---------------------------------------------------------------------------------------------------------------------
; Format characters
; ---------------------------------------------------------------------------------------------------------------------

;; Takes the next format character from the image, with its repeat count, and returns its type from <FormatTypes>.
;;
;; A count may come before the character (`3#`), and a run of the same character adds to it (`3##` is 4). A quote
;; starts a literal and stops the reading at once. A comma before the character is skipped; at the end of the image
;; this routine drops its caller's return address and returns to the caller's caller, with <SpecType> left as it was.
;; In: ImageIndex = the index of the last character of the image used, ImagePointer = the image, ImageLength = its
;;   length
;; Out: A = the type, negative = set for a literal or string field, Y = the character's index in <FormatCharacters>,
;;   SpecCharacter = the character, RepeatCount = the count
;; Errors: ILLEGAL QUANTITY for a count of 0 or over 255; SYNTAX ERROR for a character that isn't a format
;;   character, or a run that takes the count past 255
;; See: <ScanSpec>, <ReadNonSpace>
;; Also: UGETDL (BB13)
.proc ReadFormatCharacter
    ldy #0
    sty SpecCharacter
    sty RepeatCount

;; Skips commas, or at the image's end returns to the caller's caller.
;; Also: UCOMA (BB13)
SkipCommas:
    jsr ReadNonSpace
    bne Take
    cmp #','
    beq SkipCommas
    pla                                     ; the end of the image: return from the caller
    pla
    rts

;; Takes a digit of the count, or goes on to a format character.
;; In: A = the character, carry = clear for a digit
;; Also: UGOT1 (BB13)
Take:
    bcs FormatCharacter
    ldx SpecCharacter
    beq AddDigit                            ; nothing yet
    cpx #COUNT_MARK                         ; only digits so far?
    bne Back                                ; no: a digit after a format character ends it

;; Adds a digit to the count: <RepeatCount> times 10, plus the digit.
;; Also: UG1STD (BB13)
AddDigit:
    ldy RepeatCount
    cpy #COUNT_LIMIT                        ; would RepeatCount times 10 pass 255?
    bcc TimesTen

;; Frees the mask and ends the statement with an illegal quantity error.
;; See: <FreeMask>, <IllegalQuantityError>
;; Also: UIQERR (BB13)
FreeMaskThenIllegalQuantity:
    jsr FreeMask
    jmp IllegalQuantityError

;; Multiplies the count by 10 and adds the digit.
TimesTen:
    ldx #COUNT_MARK
    stx SpecCharacter                       ; marks digits read
    tya
    asl
    asl
    asl
    adc RepeatCount
    adc RepeatCount                         ; RepeatCount times 10
    sta RepeatCount
    ldy ImageIndex
    lda (ImagePointer),Y
    and #$0F                                ; the digit's value
    adc RepeatCount
    bcs FreeMaskThenIllegalQuantity         ; past 255
    sta RepeatCount

;; Takes the next character of the image.
;; Also: UGNXTC (BB13)
NextCharacter:
    jsr ReadNonSpace
    beq LookUp                              ; the end of the field
    bne Take

;; Backs up so the character that ended the field is read again by the next call.
;; Also: UGVAL (BB13)
Back:
    dec ImageIndex

;; Looks the format character up in <FormatCharacters>, in upper case, and returns its type.
;; Also: UGEND (BB13)
LookUp:
    lda SpecCharacter
    cmp #'Z'+1
    bcc Search
    sbc #LOWER_CASE_BIT                     ; lower case to upper
Search:
    ldy #FORMAT_CHARACTER_COUNT-1

;; Compares the next entry, from the last.
;; Also: UVALOOP (BB13)
SearchLoop:
    cmp a:FormatCharacters,Y
    beq Found
    dey
    bpl SearchLoop

;; Frees the mask and ends the statement with a syntax error.
;; See: <FreeMask>, <ToSyntaxError>
;; Also: UGERRX (BB13)
FreeMaskThenSyntaxError:
    jsr FreeMask
    jmp ToSyntaxError

;; Returns the type of the format character found at Y.
;; Also: UGETND (BB13)
Found:
    lda a:FormatTypes,Y
    rts

;; Takes a format character: the first, the one after a count, or another of a run.
;; In: A = the character
;; Also: UDLCHR (BB13)
FormatCharacter:
    ldy SpecCharacter
    beq First
    cpy #COUNT_MARK                         ; after a count?
    bne Run
    ldy RepeatCount
    beq FreeMaskThenIllegalQuantity         ; a count of 0
    bne Record

;; Takes the first format character, with a count of 1.
;; Also: U1STDL (BB13)
First:
    ldy #1
    sty RepeatCount

;; Records the format character; a quote ends the reading, as a literal follows it.
;; Also: USETDL (BB13)
Record:
    sta SpecCharacter
    cmp #'"'
    beq LookUp
    bne NextCharacter

;; Counts another of the same format character, or ends the field at a different one.
;; Also: UDLCK (BB13)
Run:
    cmp SpecCharacter
    bne Back
    cmp #'"'
    beq FreeMaskThenSyntaxError
    inc RepeatCount
    bne NextCharacter
    beq FreeMaskThenSyntaxError             ; a run past 255
.endproc

;; The format characters, in upper case; <FormatTypes> gives each one's type.
;; Also: DLMTBL (BB13)
FormatCharacters:
    .byte 'A', 'X', '"', '+', '-', '&', '$', '.', 'E', 'C', 'R', '/', '#', 'Z', '*'

;; Each format character's type, in <FormatCharacters>' order: the FIELD_ codes, or for a digit its class.
;;
;; The top two bits give the class: 01 a digit, 00 an editing character, 10 a literal, 11 a string. An editing
;; character's other bits say which it is: <FIELD_SIGN> (with <PARTS_PLUS> for `+`), <FIELD_DOLLAR>,
;; <FIELD_EXPONENT>, <FIELD_POINT> and <FIELD_ASTERISK>. A digit's low bits rank its kind: <FIELD_ZERO_FILLED>,
;; <FIELD_SPACE_FILLED>, then <FIELD_COMMAS>.
;; Also: STYPTBL (BB13)
FormatTypes:
    .byte FIELD_STRING                      ; A: a string, from the left
    .byte FIELD_LITERAL                     ; X: a space
    .byte FIELD_LITERAL                     ; ": a literal, to the next quote
    .byte FIELD_PLUS                        ; +: a sign, + or -
    .byte FIELD_SIGN                        ; -: a sign, a space or -
    .byte FIELD_COMMAS                      ; &: a digit, with commas
    .byte FIELD_DOLLAR                      ; $
    .byte FIELD_POINT                       ; .: the point
    .byte FIELD_EXPONENT                    ; E: the exponent
    .byte FIELD_STRING                      ; C: a string, centered
    .byte FIELD_STRING                      ; R: a string, to the right
    .byte FIELD_LITERAL                     ; /: a RETURN and a line feed
    .byte FIELD_SPACE_FILLED                ; #: a digit, space filled
    .byte FIELD_ZERO_FILLED                 ; Z: a digit, zero filled
    .byte FIELD_ASTERISK                    ; *: asterisk fill
.assert * - FormatTypes = FORMAT_CHARACTER_COUNT, "A type for each format character."

;; The number of format characters.
;; Also: DLMCNT (BB13)
FORMAT_CHARACTER_COUNT = FormatTypes - FormatCharacters

;; The fill character for the places before the point, by digit class less <FIELD_ZERO_FILLED>: `0` for Z, a space
;; for #, a space for the class between, which no character has, and a space for &.
;; Also: FILLTABL (BB13)
FillCharacters:
    .byte "0   "

;; The comma flag, by digit class less <FIELD_ZERO_FILLED>: <FILL_COMMAS> for &, which puts commas in.
;; Also: CMATBL (BB13)
CommaFlags:
    .byte 0, 0, 0, FILL_COMMAS
.assert CommaFlags - FillCharacters = FIELD_COMMAS - FIELD_ZERO_FILLED + 1, "A fill for each digit class."

; ---------------------------------------------------------------------------------------------------------------------
; Numeric fields
; ---------------------------------------------------------------------------------------------------------------------

;; Unpacks the decimal mantissa in <FacDecimalDigits> into <UsingDigits>, one digit a byte from <DIGITS_START>:
;; <DIGIT_COUNT> digits, then a 0.
;;
;; Leading zeros are dropped, each lowering the exponent in <ArrayElementFound> by one; <ArrayElementFound> holds the
;; exponent doubled, with the sign in bit 0. For a positive zero, the 20th zero brings <ArrayElementFound> to 0, and the
;; loop goes on storing the digits it reads past the mantissa; <LongInteger::FacToDigits>'s copy in <Arg> holds the same
;; zeros.
;; In: FacDecimalDigits = <DIGIT_COUNT> digits, two a byte, the first in the high half, ArrayElementFound = the exponent
;;   doubled, with the sign
;; Out: A = 0, zero = set, Y = <DIGITS_END>
;; Uses: X, NextHalf
;; See: <LongInteger::FacToDigits>
;; Also: UUNPACK (BB13)
.proc UnpackDecimal
    ldy #DIGITS_START
    ldx #$FF
    stx NextHalf                            ; the high digit first
    inx

;; Takes the next digit.
;; Also: UHLOOP (BB13)
Loop:
    lda FacDecimalDigits,X
    bit NextHalf
    bpl LowDigit
    inc NextHalf                            ; the low digit next
    lsr
    lsr
    lsr
    lsr
    bpl Digit

;; Takes the low digit; the next byte's high digit comes next.
;; Also: UPUSELOW (BB13)
LowDigit:
    dec NextHalf                            ; the high digit of the next byte next
    inx
    and #$0F

;; Stores the digit, or drops a leading zero.
;; Also: UPUSEA (BB13)
Digit:
    cpy #DIGITS_START+1
    bcs Store                               ; past the first digit, zeros count
    cmp #0
    bne Store
    dec ArrayElementFound                   ; a leading zero: the exponent goes down one
    dec ArrayElementFound
    bne Loop                                ; always, but for a positive zero's 20th

;; Stores the digit.
;; Also: UGTABYT (BB13)
Store:
    sta UsingDigits,Y
    iny
    cpy #DIGITS_END
    bne Loop
    lda #0
    sta UsingDigits,Y
    rts
.endproc

;; Writes a number into its field of the mask, as the image asks, and prints it.
;;
;; The number is in <UsingDigits>, one digit a byte, with its exponent doubled in <FacExponent> and its sign in bit 0.
;; This routine makes <FacExponent> the power of ten of the first digit and adds the `SCALE` factor in
;; <ArrayElementFound>; the result must lie between -99 and 99. The number is rounded at the last place shown, and one
;; too big for its field prints as a field of `!`. A field with an exponent goes on to <FormatScientific>.
;; In: MaskPointer = the mask, MaskIndex = the index of its last byte, and the field as <ScanSpec> left it:
;;   <DigitsBeforePoint>, <DigitsAfterPoint>, <SpecParts>, <FloatingSymbols>, <FillCharacter>, <UnitsIndex>,
;;   <PointIndex>
;; Errors: ILLEGAL QUANTITY for an exponent out of range
;; Entry:
;;   WriteFraction = writes the digits after the point, then the exponent, and prints the field
;; See: <PrintNumber>
;; Also: UNUMEDIT (BB13)
.proc FormatNumber
    inc MaskIndex                           ; now the field's length
    lda FacExponent
    cmp #$80                                ; carry = the exponent's sign
    ror
    ror                                     ; the mantissa's sign to bit 7
    sta FacSign
    rol                                     ; the exponent, signed
    sec
    sbc #1                                  ; the power of the first digit
    clc
    adc ArrayElementFound                   ; plus the SCALE factor
    sta FacExponent
    cmp #EXPONENT_MIN
    bcs InRange
    cmp #EXPONENT_MAX+1
    bcc InRange
    jsr FreeMask
    jmp IllegalQuantityError

;; Fills in a fixed sign, then edits the field: with an exponent at <FormatScientific>, otherwise here.
;;
;; With commas, the places before the point are cut to the digits they hold once the commas take their places.
;; Also: UROKNOW (BB13)
InRange:
    jsr FillFixedSign
    ldy #0
    sty CommaCounter
    sty DigitCounter
    lda #FIELD_EXPONENT
    bit SpecParts
    beq CheckCommas
    jmp FormatScientific
CheckCommas:
    bit FillCharacter
    bpl RoundFixed                          ; no commas
    lda DigitsBeforePoint
    and #3
    cmp #1                                  ; carry = clear for a multiple of 4
    lda DigitsBeforePoint
    tax
    bcc Quarter
    sbc #1                                  ; one off a count that is not a multiple of 4

;; Takes a quarter of the count: the places the commas take.
;; Also: UNOSBC1 (BB13)
Quarter:
    lsr
    lsr                                     ; the places the commas take
    sta DigitsBeforePoint
    txa
    sec
    sbc DigitsBeforePoint
    sta DigitsBeforePoint

;; Rounds the number at the last decimal place shown and checks the digits before the point fit.
;; Also: UNOCMAS (BB13)
RoundFixed:
    lda #<(0-1)
    sec
    sbc DigitsAfterPoint                    ; the power of ten of the first place dropped
    tax
    jsr RoundAtPower
    jsr RaiseExponent
    lda DecimalExponent
    bit FacExponent
    bmi WriteWhole                          ; below 1: it fits
    cmp DigitsBeforePoint
    bcc WriteWhole

;; Fills the field with `!`, for a number that doesn't fit, and prints it.
;; Also: UTOOBIG (BB13)
TooBig:
    lda #'!'
    ldy MaskIndex

;; Fills the next place, from the last.
;; Also: UEXLOOP (BB13)
TooBigLoop:
    dey
    bmi TooBigDone
    sta (MaskPointer),Y
    bne TooBigLoop                          ; always

;; Prints the field.
;; Also: UEXDONE (BB13)
TooBigDone:
    jmp PrintField

;; Writes the digits before the point, right to left from the units place, with a comma every three digits when
;; asked; the units place shows 0 for a number below 1.
;; Also: UDOLEFT (BB13)
WriteWhole:
    lda DigitsBeforePoint
    bne HasWholePlaces
    jmp WriteFraction                       ; no places before the point
HasWholePlaces:
    ldx #$FF
    ldy UnitsIndex

;; Writes the next place, from the units.
;; Also: ULEFTLP (BB13)
WholeLoop:
    inx
    cpx DigitsBeforePoint
    bcs FloatingSigns                       ; every place is done
    jsr DigitAtPower
    bpl PlaceDigit
    txa
    bne MinusSign                           ; past the first digit
    lda #'0'                                ; the units place

;; Puts in a comma first, every three digits.
;; Also: UDOADIG (BB13)
PlaceDigit:
    bit FillCharacter
    bpl StoreWhole                          ; no commas
    pha
    lda CommaCounter
    cmp #DIGITS_PER_COMMA
    bcc CountComma
    lda #','
    sta (MaskPointer),Y
    dey
    lda #0
    sta CommaCounter

;; Counts the digit toward the next comma.
;; Also: UINCMA (BB13)
CountComma:
    inc CommaCounter
    pla

;; Stores the digit.
;; Also: USTALFT (BB13)
StoreWhole:
    sta (MaskPointer),Y
    dey
    bpl WholeLoop

;; Puts a minus sign before a negative number whose image has no sign, in a spare digit place; with no place for it
;; the number doesn't fit.
;; Also: UDOISGN (BB13)
MinusSign:
    lda #FIELD_SIGN
    bit SpecParts
    bne FloatingSigns                       ; the image has a sign
    bit FacSign
    bpl FloatingSigns
    tya
    bmi TooBig
    lda (MaskPointer),Y
    bne TooBig                              ; not a digit place
    lda #'-'
    sta (MaskPointer),Y
    dey

;; Writes the floating `$` and sign before the digits, right to left in the order the image gave them, from the bits
;; of <FloatingSymbols>: <FLOAT_DOLLAR_AFTER_SIGN>, <FLOAT_SIGN>, then <FLOAT_DOLLAR>.
;; Also: UDOFLTS (BB13)
FloatingSigns:
    lda FloatingSymbols
    and #FLOAT_DOLLAR_AFTER_SIGN | FLOAT_SIGN | FLOAT_DOLLAR
    beq FillLeft
    .assert FLOAT_DOLLAR_AFTER_SIGN = $80, "The first ASL takes the $ after the sign into carry."
    asl
    bcc CheckSign
    tax
    lda #'$'
    sta (MaskPointer),Y
    dey
    txa

;; Writes a floating sign: `-` for a negative number, `+` for a positive one when the image asks for one.
;; Also: UNODL1 (BB13)
CheckSign:
    asl
    bcc CheckDollar
    tax
    lda SpecParts
    lsr                                     ; carry = set for +
    lda #'-'
    bit FacSign
    bmi StoreSign
    bcc SignDone                            ; positive, and no + asked for
    lda #'+'

;; Stores the sign.
;; Also: USTORMI (BB13)
StoreSign:
    sta (MaskPointer),Y
    dey

;; Goes on to a floating $ before the sign.
;; Also: USKPSI (BB13)
SignDone:
    txa

;; Writes a floating $ before the sign, or with none.
;; Also: UNOSIGN (BB13)
CheckDollar:
    asl
    bcc FillLeft
    lda #'$'
    sta (MaskPointer),Y
    dey

;; Fills the digit places left before the number with the fill character: a space, `0` or `*`.
;; Also: UDOFILL (BB13)
FillLeft:
    tya
    bmi WriteFraction
    lda FillCharacter
    and #$FF ^ FILL_COMMAS                  ; without the comma flag
    tax

;; Fills the next place, until one that is not a digit place.
;; Also: UFILLP (BB13)
FillLoop:
    lda (MaskPointer),Y
    bne WriteFraction                       ; not a digit place
    txa
    sta (MaskPointer),Y
    dey
    bpl FillLoop

;; Writes the digits after the point: the number's own places, or with an exponent its next digits.
;; Also: URIGHTS (BB13)
WriteFraction:
    lda DigitsAfterPoint
    beq WriteExponent
    ldy PointIndex
    iny
    ldx #0
    txa
    sec
    sbc DigitsAfterPoint
    sta DigitsAfterPoint                    ; the power of ten of the last place

;; Writes the next place.
;; Also: URITLOP (BB13)
FractionLoop:
    dex
    cpx DigitsAfterPoint
    bcc WriteExponent
    lda #FIELD_EXPONENT
    bit SpecParts
    bne NextOfDigits
    jsr DigitAtPower
    bpl StoreFraction
    lda #'0'
    bpl StoreFraction

;; Takes the next of the number's digits, for a field with an exponent.
;; Also: UEXPTYP (BB13)
NextOfDigits:
    jsr NextDigit

;; Stores the digit.
;; Also: UDIGRIT (BB13)
StoreFraction:
    sta (MaskPointer),Y
    iny
    jmp FractionLoop

;; Writes the exponent at the image's first E: an upper-case E, the exponent's sign, and two digits, or one when the
;; image has only three Es; an exponent that needs two digits there doesn't fit.
;; Also: UDOEXP (BB13)
WriteExponent:
    lda #FIELD_EXPONENT
    bit SpecParts
    beq PrintField
    ldy #0

;; Looks for the first E.
;; Also: UDOEXP1 (BB13)
FindE:
    lda (MaskPointer),Y
    and #$FF ^ LOWER_CASE_BIT               ; upper case
    iny
    cmp #'E'
    bne FindE
    dey
    sta (MaskPointer),Y
    iny
    lda #'+'
    bit FacExponent
    bpl StoreExponentSign
    lda #'-'
StoreExponentSign:
    sta (MaskPointer),Y
    iny
    lda DecimalExponent
    ldx #0
    sec

;; Counts the tens.
;; Also: USBCLP (BB13)
TensLoop:
    sbc #10
    bcc Units
    inx                                     ; the tens
    bne TensLoop

;; Takes the units, and checks the room for two digits.
;; Also: UGOTHI (BB13)
Units:
    adc #10                                 ; the units
    iny
    cpy MaskIndex                           ; room for two digits?
    dey
    bcc TwoDigits
    cpx #0
    beq UnitsDigit
    jmp TooBig

;; Writes the tens digit.
;; Also: UDO1STD (BB13)
TwoDigits:
    pha
    txa
    ora #'0'
    sta (MaskPointer),Y
    iny
    pla

;; Writes the units digit.
;; Also: UDO2NDD (BB13)
UnitsDigit:
    ora #'0'
    sta (MaskPointer),Y

;; Prints the field: the mask, <MaskIndex> characters, as a string.
;; See: <Output::WriteString>
;; Also: USENDIT (BB13)
PrintField:
    lda #0
    sta ValueType
    lda MaskPointer
    sta Pointer1
    lda MaskPointer+1
    sta Pointer1+1
    lda NewStringXByte                      ; the mask's bank
    sta Pointer1XByte
    ldx MaskIndex
    jmp Output::WriteString
.endproc

;; The smallest exponent a field takes, -99.
;; Also: MINSGN (BB13)
EXPONENT_MIN = -99 & $FF

;; The largest exponent a field takes, 99.
;; Also: MAXSGN (BB13)
EXPONENT_MAX = 99

;; Writes a number into a field with an exponent: `.DDDE+EE` with no places before the point, `D.DDDE+EE` with one,
;; or engineering notation with three.
;;
;; The number is rounded to the places shown. With one place before the point, its digit goes after whatever the
;; field's first place holds, a fixed sign or `$`; only that one place is checked, so with both (`+$#.##EEEE`) the
;; digit takes the `$`'s place and leaves its own place a zero byte.
;; See: <FormatNumber>
;; Also: UEEEDIT (BB13)
.proc FormatScientific
    lda DigitsBeforePoint
    clc
    adc DigitsAfterPoint
    tax                                     ; the index of the first place dropped
    jsr RoundAtPower::AtIndex
    jsr RaiseExponent
    ldx DigitsBeforePoint
    beq NoWholePlaces
    dex
    bne Engineering
    ldy #0
    lda (MaskPointer),Y
    beq WholeDigits
    iny                                     ; after the sign

;; Writes <DigitsBeforePoint> digits, then those after the point.
;; In: Y = the first digit's place
;; Also: UDOSCI1 (BB13)
WholeDigits:
    lda DigitsBeforePoint
    beq ToWriteFraction
    jsr NextDigit
    sta (MaskPointer),Y
    dec DigitsBeforePoint
    iny
    bne WholeDigits

;; With no places before the point, the exponent is one higher.
;; Also: UDOSCI0 (BB13)
NoWholePlaces:
    sec
    jsr RaiseExponent

;; Writes the digits after the point.
;; Also: UDOSCI2 (BB13)
ToWriteFraction:
    jmp FormatNumber::WriteFraction

;; Engineering notation: lowers the exponent to a multiple of three, which leaves one to three digits before the
;; point, and puts the floating sign and the fill character in the places left before them.
;;
;; Only one place gets the fill character (a bug of the original): the fill loop doesn't step Y, so after filling a
;; place it finds it filled and stops, and any place further left keeps its zero byte. A floating sign's place keeps
;; its zero byte too for a positive number without `+`, as the fill starts left of it.
;; Also: UENGNOT (BB13)
Engineering:
    lda FacExponent

;; Adds 3 to a negative exponent until it is not.
;; Also: UMOD3LP (BB13)
ModLoop:
    bpl CheckMod
    clc
    adc #ENGINEERING_STEP
    bmi ModLoop

;; Takes 3 off until the remainder is below 3.
;; Also: UCHKMD3 (BB13)
CheckMod:
    cmp #ENGINEERING_STEP
    bcc GotMod
    sbc #ENGINEERING_STEP
    bne ModLoop

;; Lowers the exponent by the remainder, which is the count of digits before the point less one.
;; Also: UGOTMOD (BB13)
GotMod:
    bit FacExponent                         ; the flags aren't used
    sta DigitsBeforePoint
    sta ExponentAdjustment
    lda FacExponent
    sec
    sbc ExponentAdjustment
    sta FacExponent
    jsr RaiseExponent::Magnitude
    lda #ENGINEERING_STEP-1
    sec
    sbc DigitsBeforePoint                   ; the places before the digits: 2, 1 or 0
    sta FirstDigitPlace
    inc DigitsBeforePoint                   ; the digits: 1, 2 or 3
    ldy FirstDigitPlace
    lda FloatingSymbols
    beq Fill
    inc FirstDigitPlace                     ; a floating sign takes the place before the digits
    lda SpecParts
    lsr                                     ; carry = set for +
    lda #'-'
    bit FacSign
    bmi StoreSign
    bcc Fill
    lda #'+'

;; Stores the floating sign.
;; Also: USTORM (BB13)
StoreSign:
    sta (MaskPointer),Y

;; Fills the place before the digits, or the sign.
;; Also: UDOEFIL (BB13)
Fill:
    dey
    bmi Digits
    lda FillCharacter
    and #$FF ^ FILL_COMMAS
    tax

;; Fills the place, then finds it filled.
;; Also: UDOEFLL (BB13)
FillLoop:
    lda (MaskPointer),Y
    bne Digits
    txa
    sta (MaskPointer),Y
    bne FillLoop                            ; and the place now reads filled

;; Writes the digits from the place in <FirstDigitPlace>.
;; Also: UDODIGS (BB13)
Digits:
    ldy FirstDigitPlace
    jmp WholeDigits
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Digits, signs and rounding
; ---------------------------------------------------------------------------------------------------------------------

;; Returns the number's digit for a power of ten, in `ASCII`.
;;
;; Indexes up to 21 are read, two past the 20 digits from <DIGITS_START>, as the index from the first digit is
;; compared with <DIGITS_END>, an index from the start of <UsingDigits>. So the furthest places come from
;; <UsingDigits>+22, where <UnpackDecimal> writes its end mark (a real leaves it as it was), and <UsingDigits>+23, which
;; nothing writes.
;; In: X = the power of ten
;; Out: A = the digit, `0` past the digits, negative = set (and A no digit) when the power is above the first digit
;; Uses: DigitPower
;; Keeps: X, Y
;; Entry:
;;   AtIndex = takes the digit's index from the first in A
;; See: <PowerToIndex>, <NextDigit>
;; Also: UGET10X (BB13)
.proc DigitAtPower
    jsr PowerToIndex
    bmi Done

;; Takes the digit's index from the first in A.
;; Also: UGETITA (BB13)
AtIndex:
    cmp #DIGITS_END
    bcc Read
    lda #'0'

;; Returns.
;; Also: UNODIGT (BB13)
Done:
    rts

;; Reads the digit.
;; Also: UUSEIT (BB13)
Read:
    tax
    lda UsingDigits+DIGITS_START,X
    ora #'0'
    ldx DigitPower
    and #$7F                                ; negative = clear
    rts
.endproc

;; Returns the number's next digit, counting from the first with <DigitCounter>, in `ASCII`.
;; Out: A = the digit, or `0` past the digits
;; Uses: DigitCounter, DigitPower
;; Keeps: X, Y
;; See: <DigitAtPower>
;; Also: UGETNSD (BB13)
.proc NextDigit
    stx DigitPower
    lda DigitCounter
    inc DigitCounter
    jmp DigitAtPower::AtIndex
.endproc

;; Fills in the image's fixed sign by the number's: a `+` becomes `+` or `-`, a `-` becomes a space or `-`.
;;
;; Only the mask's first `+` or `-` is filled in; a floating sign has none in the mask, so it is left alone.
;; In: FacSign = bit 7 set for a negative number, SpecParts = <FIELD_SIGN> set for a sign, MaskIndex = the field's
;;   length, MaskPointer = the mask
;; Uses: A, Y
;; Keeps: X
;; Also: USGNSCN (BB13)
.proc FillFixedSign
    lda #FIELD_SIGN
    bit SpecParts
    beq Done                                ; no sign
    ldy #NO_INDEX

;; Looks at the mask's next place.
;; Also: USIGNLP (BB13)
Loop:
    iny
    cpy MaskIndex
    beq Done
    lda (MaskPointer),Y
    cmp #'-'
    beq Minus
    cmp #'+'
    bne Loop
    lda #'+'
    bne Store

;; Makes a `-` a space for a positive number.
;; Also: UDOMSIN (BB13)
Minus:
    lda #' '

;; Stores the sign, `-` for a negative number.
;; Also: USTASIN (BB13)
Store:
    bit FacSign
    bpl StoreIt
    lda #'-'
StoreIt:
    sta (MaskPointer),Y

;; Returns.
;; Also: USGNRTS (BB13)
Done:
    rts
.endproc

;; Adds one to the exponent in <FacExponent> when carry is set, then puts its size in <DecimalExponent>.
;; In: carry = set to add one
;; Out: DecimalExponent = the exponent without its sign
;; Uses: A, RepeatCount
;; Keeps: X, Y
;; Entry:
;;   Magnitude = only sets <DecimalExponent>
;; Also: UEXPLS1 (BB13)
.proc RaiseExponent
    lda #1
    bcc Magnitude
    sta RepeatCount
    lda FacExponent
    clc
    adc RepeatCount
    sta FacExponent

;; Puts the exponent's size in <DecimalExponent>.
;; Also: UABSEXP (BB13)
Magnitude:
    lda FacExponent
    bpl Store
    eor #$FF
    clc
    adc #1

;; Stores the size.
;; Also: USTATEN (BB13)
Store:
    sta DecimalExponent
    rts
.endproc

;; Turns a power of ten into its digit's index in <UsingDigits>, counting from <DIGITS_START>.
;; In: X = the power of ten
;; Out: A = the index, negative = set when the power is above the first digit, DigitPower = X
;; Keeps: X, Y
;; Also: UCVTX (BB13)
.proc PowerToIndex
    stx DigitPower
    lda FacExponent
    sec
    sbc DigitPower
    rts
.endproc

;; Rounds the number at a power of ten: if that place's digit is 5 or more, it becomes 0 and one is carried into the
;; places before it.
;;
;; When every place before it is 9, the number becomes 1 followed by zeros and the exponent must go up one.
;; In: X = the power of ten of the first place dropped
;; Out: carry = set when the exponent must go up one
;; Uses: A, X, DigitPower
;; Entry:
;;   AtIndex = takes the place's index in X
;; See: <RaiseExponent>
;; Also: UROUNDI (BB13)
.proc RoundAtPower
    jsr PowerToIndex
    bmi NoCarryOut                          ; above the first digit
    cmp #DIGITS_END
    bcs NoCarryOut                          ; past the digits
    tax

;; Rounds at the place with index X.
;; Also: UROUNDA (BB13)
AtIndex:
    lda UsingDigits+DIGITS_START,X
    cmp #ROUND_UP_DIGIT
    bcc NoCarryOut+1                        ; below 5: carry clear, to the RTS
    lda #9                                  ; 9 plus the carry makes this place 0
    bcs AddCarry

;; Carries into the place before.
;; Also: UROUNDL (BB13)
CarryLoop:
    dex
    bmi CarryOut                            ; carried out of the first digit
    lda UsingDigits+DIGITS_START,X

;; Adds the carry to the place, in decimal.
;; Also: UROUNDB (BB13)
AddCarry:
    sed
    adc #0                                  ; plus the carry, in decimal
    cld
    cmp #$10                                ; carry = set for a carry on
    and #$0F
    sta UsingDigits+DIGITS_START,X
    bcs CarryLoop

;; Returns with carry clear: the exponent stands.
;; Also: UROUNDX (BB13)
NoCarryOut:
    clc
    rts

;; Makes the number 1 after a carry out of its first digit, the other places now 0, and returns with carry set.
;; Also: UROUNDO (BB13)
CarryOut:
    lda #1
    sta UsingDigits+DIGITS_START
    rts
.endproc

.endscope
