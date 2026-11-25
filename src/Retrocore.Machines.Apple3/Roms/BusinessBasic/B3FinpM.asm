; retrocore: style=strict
;; Business BASIC's floating point, part three (Apple's B3FINPM): reals to and from text. <Float::ReadNumber> reads a
;; number into <Fac> and <Float::FormatFac> writes the <Fac> as text; with them come the end of
;; <Float::ToLongInteger>, the `INT` function, line number printing, and the `^` operator and `SQR`.
;;
;; A real is a binary floating-point number. In the <Fac> it is an exponent byte (<FacExponent>), four mantissa bytes
;; (<FacMantissa1>, <FacMantissa2>, <FacMantissa3>, <FacMantissa4>), the sign (bit 7 of <FacSign>) and a rounding byte
;; (<FacExtension>). The exponent is biased by $80, and an exponent of 0 means the number is zero whatever the other
;; bytes hold. The mantissa is a fraction from 1/2 to 1, its top bit always 1, so the value is mantissa * 2^(exponent -
;; $80). In memory the top bit's place holds the sign instead: a real variable is four bytes, the exponent and then the
;; mantissa's top three bytes, rounded; a constant in BASIC's own bank keeps the fourth mantissa byte as a fifth byte.

; Float::ToLongInteger, part two, inside the scope Float that B3MathL.asm opened.

    ; Eight places or more to shift go through ShiftRightFilled, which shifts whole bytes first.
    jmp ShiftRightFilled

;; Shifts <Fac>'s mantissa right a few places, keeping a negative number's sign bits.
;; In: A = minus the count of places, X = <Fac>'s address
;; Also: QINT1 (BB13)
ShortShift:
    tay                                     ; the count
    lda FacSign
    and #$80
    lsr FacMantissa1
    ora FacMantissa1                        ; the sign into the top bit
    sta FacMantissa1
    jmp ShiftRightByCount::ShiftLow
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; INT
; ---------------------------------------------------------------------------------------------------------------------

; The INT function.
.scope Functions continued

;; Gives `INT`: the greatest integer not above <Fac>.
;;
;; A real of 2^31 or more in size has no fraction bits and is returned as it is, leaving <SmallInteger> alone.
;; In: Fac = the real
;; Out: Fac = its integer part, rounded down, SmallInteger = the integer's low byte
;; See: <Float::ToLongInteger>
;; Also: INT (BB13)
.proc Int
    lda FacExponent
    cmp #Float::LONG_INTEGER_EXPONENT
    bcs Float::ClearMantissa::Done          ; already an integer
    jsr Float::ToLongInteger
    sty FacExtension                        ; Y = 0
    lda FacSign
    sty FacSign
    eor #$80                                ; the sign, inverted, into the carry for NormalizeSigned
    rol a
    lda #Float::LONG_INTEGER_EXPONENT
    sta FacExponent
    lda FacMantissa4
    sta SmallInteger
    jmp Float::NormalizeSigned
.endproc

.endscope

; Floating point, part three: reading and writing numbers.
.scope Float continued

;; Zeros <Fac>'s mantissa, for <Float::ToLongInteger>'s zero.
;; In: A = 0
;; Out: Y = 0
;; Entry:
;;   Done = returns
;; Also: CLRFAC (BB13)
.proc ClearMantissa
    sta FacMantissa1
    sta FacMantissa2
    sta FacMantissa3
    sta FacMantissa4
    tay

;; Returns.
;; Also: INTRTS (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Reading a number: text to a real
; ---------------------------------------------------------------------------------------------------------------------

;; How many digits after the period <Float::ReadNumber> takes; the rest are skipped.
FRACTION_DIGITS = 9

;; Reads a real from the text at <TextPointer> into <Fac>.
;;
;; The number is an optional sign, digits with at most one period, and an optional exponent: `E` or `e`, an optional
;; sign and digits. The digits are gathered into the <Fac> as an integer, counting those after the period in
;; <DigitCount>; then the <Fac> is multiplied or divided by 10 as many times as the exponent less that count says. Only
;; nine digits after the period are taken; the rest are skipped. An exponent of 100 or more is an overflow error, even
;; when the digits would bring the number back in range; a negative one of that size is taken as -100.
;; In: TextPointer = the number's first character
;; Out: Fac = the number, TextPointer = the first character after it, DigitsSeen = $FF when there were no digits
;; Errors: OVERFLOW = the number or its exponent is too large
;; Uses: DigitCount, DecimalExponent, DecimalPointSeen, ExponentSign, InputSign, DigitsLeft, Arg
;; Entry:
;;   NextExponentCharacter = takes the exponent's next character
;; See: <Float::FormatFac>, <LongInteger::ReadNumber>
;; Also: FIN (BB13)
.proc ReadNumber

;; The bytes the routine clears from <DigitCount>: <DigitCount> and <DecimalExponent>, <DecimalPointSeen> and
;; <ExponentSign>, <Fac>'s six and <InputSign>.
CLEARED_BYTES = 11

    jsr GetCurrentCharacter
    ldy #0
    sty DigitsLeft                          ; no limit before the period
    sty DigitsSeen                          ; no digits yet
    ldx #CLEARED_BYTES - 1

;; Zeros <DigitCount> and the bytes after it, leaving the carry from <GetCurrentCharacter>.
;; Also: FINZLP (BB13)
ClearLoop:
    sty DigitCount,x
    dex
    bpl ClearLoop
    bcc TestDigit                           ; GetCurrentCharacter's carry: a digit
    cmp #'-'
    bne CheckPlus
    stx InputSign                           ; X = $FF: negative
    beq NextCharacter                       ; always

;; Skips a plus sign.
;; Also: QPLUS (BB13)
CheckPlus:
    cmp #'+'
    bne CheckPoint

;; Takes the next character; after the ninth digit past the period, skips the remaining digits.
;; Also: FINC (BB13)
NextCharacter:
    jsr GetNextCharacter
    dec DigitsLeft
    beq SkipDigits

;; Takes a digit.
;; Also: FINDGQ (BB13)
TestDigit:
    bcc Digit

;; Takes a character other than a digit: a period, an exponent, or the number's end.
;; Also: FIN1 (BB13)
CheckPoint:
    cmp #'.'
    beq DecimalPoint
    eor #'E'
    and #$DF                                ; either case
    bne EndOfNumber
    sta DigitsLeft                          ; 0, though the exponent's digits don't count
    lda DigitsSeen
    beq NoDigits                            ; an E with no digits before it
    jsr GetNextCharacter
    bcc TestExponentDigit                   ; a digit
    cmp #'-'
    beq NegativeExponent
    cmp #'+'
    beq NextExponentCharacter
    bne ExponentDone

;; Notes a negative exponent.
;; Also: FINEC1 (BB13)
NegativeExponent:
    ror ExponentSign                        ; the carry from the Directory::FileLine: set

;; Takes the exponent's next character.
;; Also: FINEC (BB13)
NextExponentCharacter:
    jsr GetNextCharacter

;; Takes an exponent digit.
;; Also: FNEDG1 (BB13)
TestExponentDigit:
    bcc AccumulateExponentDigit

;; Ends the exponent, negating it when its sign was minus.
;; Also: FINEC2 (BB13)
ExponentDone:
    bit ExponentSign
    bpl EndOfNumber
    lda #0
    sec
    sbc DecimalExponent
    jmp AdjustExponent

;; Takes the period, with nine digits after it; a second period ends the number.
;; Also: FINDP (BB13)
DecimalPoint:
    ror DecimalPointSeen                    ; bit 7 for the first, bit 6 too for a second
    lda #FRACTION_DIGITS + 1
    sta DigitsLeft
    bit DecimalPointSeen
    bvc NextCharacter

;; Ends the number: scales <Fac> by the power of ten, then gives it its sign.
;; Also: FINE (BB13)
EndOfNumber:
    lda DecimalExponent

;; Scales <Fac> by 10 to the power of A less <DigitCount>.
;; Also: FINE1 (BB13)
AdjustExponent:
    sec
    sbc DigitCount
    sta DecimalExponent
    beq ApplySign
    bpl MultiplyLoop

;; Divides <Fac> by 10 for each negative power.
;; Also: FINDIV (BB13)
DivideLoop:
    jsr DivideByTen
    inc DecimalExponent
    bne DivideLoop
    beq ApplySign

;; Multiplies <Fac> by 10 for each positive power.
;; Also: FINMUL (BB13)
MultiplyLoop:
    jsr MultiplyByTen
    dec DecimalExponent
    bne MultiplyLoop

;; Checks for digits and gives <Fac> its sign.
;; Also: FINQNG (BB13)
ApplySign:
    lda DigitsSeen
    beq NoDigits
    lda InputSign
    bmi ToNegate
    rts

;; Negates <Fac> for a minus sign.
;; Also: NEGXQS (BB13)
ToNegate:
    jmp Negate

;; Marks the number as having no digits, setting <DigitsSeen> to $FF.
;; Also: BADNMB (BB13)
NoDigits:
    lda #$FF
    sta DigitsSeen
    rts

;; Skips a digit past the ninth after the period.
;; Also: FINED1 (BB13)
SkipDigit:
    jsr GetNextCharacter

;; Skips the remaining digits, then takes the next character.
;; Also: FINEND (BB13)
SkipDigits:
    bcc SkipDigit
    bcs CheckPoint

;; Takes a digit: <Fac> = <Fac> * 10 + the digit, counting it when after the period.
;; In: A = the digit's character
;; Also: FINDIG (BB13)
Digit:
    pha
    bit DecimalPointSeen
    bpl AddDigit
    inc DigitCount                          ; a digit after the period

;; Multiplies <Fac> by 10 and adds the digit.
;; Also: FINDG1 (BB13)
AddDigit:
    jsr MultiplyByTen
    pla
    inc DigitsSeen
    sec
    sbc #'0'
    jsr AddSignedByte
    jmp NextCharacter
.endproc

;; Adds a small integer to <Fac>.
;; In: A = the integer, from -128 to 127
;; Out: Fac = <Fac> + A
;; Uses: Arg
;; Also: FINLOG (BB13)
.proc AddSignedByte
    pha
    jsr CopyFacToArg
    pla
    jsr ConvertSignedByte
    lda ArgSign
    eor FacSign
    sta ResultSign
    ldx FacExponent
    jmp AddArg
.endproc

;; Takes an exponent digit for <Float::ReadNumber>: <DecimalExponent> = <DecimalExponent> * 10 + the digit, with no more
;; than two digits.
;; In: TextPointer = the digit
;; Errors: OVERFLOW = a positive exponent of 100 or more
;; Also: FINEDG (BB13)
.proc AccumulateExponentDigit

;; What a negative exponent of three digits or more is taken as.
NEGATIVE_EXPONENT_LIMIT = 100

    lda DecimalExponent
    cmp #10
    bcc TimesTen                            ; one digit so far
    lda #NEGATIVE_EXPONENT_LIMIT
    bit ExponentSign
    bmi ClampNegative
    jmp OverflowError

;; Multiplies the exponent by 10 and adds the digit.
;; Also: MLEX10 (BB13)
TimesTen:
    asl a
    asl a
    clc
    adc DecimalExponent                     ; times 5
    asl a                                   ; times 10
    clc
    ldy #0
    adc (TextPointer),y
    sec
    sbc #'0'

;; Keeps the new exponent and takes the next character.
;; Also: MLEXMI (BB13)
ClampNegative:
    sta DecimalExponent
    jmp ReadNumber::NextExponentCharacter
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Writing a number: a real to text
; ---------------------------------------------------------------------------------------------------------------------

;; How many significant digits <Float::FormatFac> writes.
OUTPUT_DIGITS = 6

;; The real 99999.94998: <Float::FormatFac> multiplies by 10 until the number is above it.
;; Also: N_0999 (BB13)
LowerOutputLimit:
    .byte $91, $43, $4F, $F9, $99

;; The real 999999.5: <Float::FormatFac> divides by 10 until the number is no more than it. (Apple's comment says
;; 999999.499.)
;; Also: N_9999 (BB13)
UpperOutputLimit:
    .byte $94, $74, $23, $F8, $00

;; The real 1000000, which brings a number below 1 up for <Float::FormatFac>.
;; Also: N_MIL (BB13)
Million:
    .byte $94, $74, $24, $00, $00

;; Prints " IN " and the current line number, after an error message.
;; See: <Float::PrintDecimalAX>, <LineNumberPrefix>
;; Also: INPRT (BB13)
.proc PrintInLineNumber
    lda #<(LineNumberPrefix)
    ldy #>(LineNumberPrefix)
    ldx #LINE_NUMBER_PREFIX_X_BYTE
    jsr Output::PrintTextDirect
    lda CurrentLine+1
    ldx CurrentLine
    ; Falls into PrintDecimalAX.
.endproc

;; Prints a 16-bit number from 0 to 65535, such as a line number, with no space before it.
;; In: A = the high byte, X = the low byte
;; See: <Float::FormatFac>
;; Also: LINPRT (BB13)
.proc PrintDecimalAX
    sta FacMantissa1
    stx FacMantissa1+1
    ldx #WORD_EXPONENT
    sec                                     ; positive
    jsr ConvertWord
    jsr FormatFac
    jmp Output::PrintTextDirect
.endproc

;; Writes <Fac> as text in <NumberBuffer>, rounded first to a variable's precision and then to six significant digits.
;;
;; A negative number starts with a minus sign; a positive one has nothing before its digits. Trailing zeros are dropped,
;; and the period with them when nothing follows it. A number from 0.01 to below 999999.5 is written out, one below 0.1
;; as `.0` and its digits; any other is written with one digit before the period and a two-digit exponent with its
;; sign, as in `1.5E+07`. Zero is `0`.
;; In: Fac = the number
;; Out: NumberBuffer = the text, ending in a zero, A = its address's low byte, Y = its high byte, X = 0, its bank,
;;   ArrayElementFound = 7 more than the power of ten of the last digit, for `PRINT USING`
;; Uses: DigitCount, DecimalExponent, NumberBufferPointer, PowerTablePointer, Arg
;; See: <Float::ReadNumber>, <LongInteger::FormatFac>
;; Also: FOUT (BB13)
.proc FormatFac
    jsr RoundForVariable
    ldy #1
    ; Falls into FormatFacAtOffset.
.endproc

;; Writes <Fac> as text from <NumberBuffer> + Y - 1, as <Float::FormatFac> does but without rounding the <Fac> to a
;; variable's precision first: `STR$` calls it with Y = 0, for text one byte earlier, at <NumberBufferPrefix>.
;; In: Y = one more than the place to start at
;; Also: FOUTC (BB13)
.proc FormatFacAtOffset
    lda #'-'
    dey
    bit FacSign
    bpl SignDone
    iny
    sta NumberBuffer-1,y

;; Makes <Fac> positive and checks for zero.
;; Also: FOUT1_1 (BB13)
SignDone:
    sta FacSign                             ; '-', $2D: positive
    sty NumberBufferPointer
    iny
    lda #'0'
    ldx FacExponent
    bne *+5                                 ; skip the jump for a Fac that is not zero
    jmp StoreZero
    lda #0
    cpx #EXPONENT_BIAS
    beq ScaleUpSmall                        ; from 1/2 to 1
    bcs SetScale                            ; 1 or more

;; Multiplies a number below 1 by a million first.
;; Also: FOUT37 (BB13)
ScaleUpSmall:
    lda #<(Million)
    ldy #>(Million)
    jsr MultiplyPacked
    lda #$100-OUTPUT_DIGITS                 ; the power of ten so far

;; Sets the power of ten so far.
;; Also: FOUT7 (BB13)
SetScale:
    sta DigitCount

;; Brings the number to 999999.5 or below, dividing by 10.
;; Also: FOUT4 (BB13)
CheckUpper:
    lda #<(UpperOutputLimit)
    ldx #NUMBER_LIMITS_X_BYTE
    ldy #>(UpperOutputLimit)
    jsr Compare
    beq ConvertInteger                      ; exactly 999999.5: no rounding
    bpl DivideDown                          ; above it: smaller

;; Brings the number above 99999.95, multiplying by 10.
;; Also: FOUT3 (BB13)
CheckLower:
    lda #<(LowerOutputLimit)
    ldx #NUMBER_LIMITS_X_BYTE
    ldy #>(LowerOutputLimit)
    jsr Compare
    beq MultiplyUp
    bpl RoundHalf                           ; in range

;; Multiplies by 10, counting the power down.
;; Also: FOUT38 (BB13)
MultiplyUp:
    jsr MultiplyByTen
    dec DigitCount
    bne CheckLower                          ; always

;; Divides by 10, counting the power up.
;; Also: FOUT9 (BB13)
DivideDown:
    jsr DivideByTen
    inc DigitCount
    bne CheckUpper                          ; always

;; Rounds to the nearest integer.
;; Also: FOUT5 (BB13)
RoundHalf:
    jsr AddHalf

;; Takes the six-digit integer and decides where the period goes and whether there is an exponent.
;; Also: BIGGES (BB13)
ConvertInteger:
    jsr ToLongInteger
    ldx #1                                  ; one digit before the period, with an exponent
    lda DigitCount
    clc
    adc #OUTPUT_DIGITS + 1
    sta ArrayElementFound
    bmi UseExponent                         ; below 0.01: an exponent
    cmp #OUTPUT_DIGITS + 2
    bcs SetExponent                         ; 999999.5 or more: an exponent
    adc #$100-1
    tax                                     ; the digits before the period
    lda #2                                  ; no exponent

;; Sets the carry for the subtract.
;; Also: FOUTPI (BB13)
UseExponent:
    sec

;; Sets the exponent to write, then writes a leading period, or `.0`, when no digit comes before it.
;; Also: FOUT6 (BB13)
SetExponent:
    sbc #2
    sta DecimalExponent
    stx DigitCount                          ; the digits before the period
    txa
    beq LeadingPoint
    bpl FirstPower

;; Writes the period before the digits, and a 0 after it for a number below 0.1.
;; Also: FOUT39 (BB13)
LeadingPoint:
    ldy NumberBufferPointer
    lda #'.'
    iny
    sta NumberBuffer-1,y
    txa
    beq SavePosition
    lda #'0'
    iny
    sta NumberBuffer-1,y

;; Keeps the place in the text.
;; Also: FOUT16 (BB13)
SavePosition:
    sty NumberBufferPointer

;; Writes the six digits, one for each power of ten in <Float::PowersOfTen>.
;; Also: FOUT8 (BB13)
FirstPower:
    ldy #0
    ldx #$80

;; Takes one digit: adds the power of ten (subtracting for the negative ones) until the number's sign changes,
;; counting in X.
;; Also: FOUT2 (BB13)
AddPower:
    lda FacMantissa4
    clc
    adc a:PowersOfTen+3,y
    sta FacMantissa4
    lda FacMantissa3
    adc a:PowersOfTen+2,y
    sta FacMantissa3
    lda FacMantissa2
    adc a:PowersOfTen+1,y
    sta FacMantissa2
    lda FacMantissa1
    adc a:PowersOfTen,y
    sta FacMantissa1
    inx
    bcs Carried
    bpl AddPower
    bmi DigitFound

;; Goes on adding until the sign changes.
;; Also: FOUT41 (BB13)
Carried:
    bmi AddPower

;; Turns the count into the digit: for a power that was subtracted, the count less one; for one added, 10 less it.
;; Also: FOUT40 (BB13)
DigitFound:
    txa
    bcc StoreDigit
    eor #$FF
    adc #10

;; Writes the digit, and the period after it when its place comes.
;; Also: FOUTYP (BB13)
StoreDigit:
    adc #'0'-1
    iny
    iny
    iny
    iny                                     ; the next power
    sty PowerTablePointer
    ldy NumberBufferPointer
    iny
    tax
    and #$7F
    sta NumberBuffer-1,y
    dec DigitCount
    bne SavePointer
    lda #'.'
    iny
    sta NumberBuffer-1,y

;; Keeps the place in the text and flips the direction for the next power.
;; Also: STXBUF (BB13)
SavePointer:
    sty NumberBufferPointer
    ldy PowerTablePointer
    txa
    eor #$FF
    and #$80
    tax
    cpy #PowersOfTenEnd-PowersOfTen
    bne AddPower
    ldy NumberBufferPointer

;; Drops trailing zeros, and the period if it ends the number.
;; Also: FOUT11 (BB13)
TrimZeros:
    lda NumberBuffer-1,y
    dey
    cmp #'0'
    beq TrimZeros
    cmp #'.'
    beq Exponent
    iny                                     ; keep this character

;; Writes the exponent, if any: `E`, its sign and two digits.
;; Also: FOUT12 (BB13)
Exponent:
    lda #'+'
    ldx DecimalExponent
    beq Terminate
    bpl StoreExponentSign
    lda #0
    sec
    sbc DecimalExponent
    tax
    lda #'-'

;; Writes `E`, the sign and the exponent's two digits.
;; Also: FOUT14 (BB13)
StoreExponentSign:
    sta NumberBuffer-1+2,y
    lda #'E'
    sta NumberBuffer-1+1,y
    txa
    ldx #'0'-1
    sec

;; Counts the exponent's tens in X.
;; Also: FOUT15 (BB13)
ExponentTens:
    inx
    sbc #10
    bcs ExponentTens
    adc #'0'+10
    sta NumberBuffer-1+4,y                  ; the ones digit
    txa
    sta NumberBuffer-1+3,y                  ; the tens digit
    lda #0
    sta NumberBuffer-1+5,y
    beq ReturnBuffer                        ; always

;; Writes the one character in A, for zero.
;; Also: FOUT19 (BB13)
StoreZero:
    sta NumberBuffer-1,y

;; Ends the text with a zero.
;; Also: FOUT17 (BB13)
Terminate:
    lda #0
    sta NumberBuffer-1+1,y

;; Returns the text's address.
;; Also: FOUT20 (BB13)
ReturnBuffer:
    lda #<(NumberBuffer)
    ldx #0
    ldy #>(NumberBuffer)
    rts
.endproc

;; The real 0.5, five bytes, the last four shared with <ZeroValue>.
;; Also: FHALF (BB13)
Half:
    .byte $80

.endscope

;; Eight zero bytes: a real or long integer 0. <FindVariable> returns this for a variable that is read but was never
;; set, rather than making one.
;; Also: ZERO (BB13)
ZeroValue:
    .byte $00, $00, $00, $00
    .byte $00, $00, $00, $00
.assert ZeroValue = Float::Half + 1, "Half's last four bytes are ZeroValue's first four."

; Floating point, part three: the powers of ten, and SQR and ^.
.scope Float continued

;; The powers of ten for <Float::FormatFac>'s digits, as 32-bit integers, most significant byte first: -100000, 10000,
;; -1000, 100, -10 and 1. Alternating the signs lets each digit be counted from where the last left the number,
;; without restoring.
;; Also: FOUTBL (BB13)
PowersOfTen:
    .byte $FF, $FE, $79, $60                ; -100000
    .byte $00, $00, $27, $10                ; 10000
    .byte $FF, $FF, $FC, $18                ; -1000
    .byte $00, $00, $00, $64                ; 100
    .byte $FF, $FF, $FF, $F6                ; -10
    .byte $00, $00, $00, $01                ; 1

;; The end of <Float::PowersOfTen>.
;; Also: FDCEND (BB13)
PowersOfTenEnd:
.assert PowersOfTenEnd - PowersOfTen = 4 * OUTPUT_DIGITS, "PowersOfTen has a four-byte power for each digit."

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; SQR and ^
; ---------------------------------------------------------------------------------------------------------------------

; The SQR function.
.scope Functions continued

;; Gives `SQR`: the square root of <Fac>, as <Fac> ^ 0.5.
;; Errors: ILLEGAL QUANTITY = the <Fac> is negative
;; See: <Float::RaiseArg>
;; Also: SQR (BB13)
.proc Sqr
    jsr Float::CopyFacToArg
    lda #<(Float::Half)
    ldx #HALF_X_BYTE
    ldy #>(Float::Half)
    jsr Float::LoadFac                      ; with the zero flag from 0.5's exponent
    ; Falls into Float::RaiseArg.
.endproc

.endscope

; Floating point, part three: ^ and negation.
.scope Float continued

;; The `^` operator: <Arg> to the power of <Fac>, as `EXP(FAC * LOG(ARG))`.
;;
;; Anything to the power 0 is 1, even 0; 0 to any other power is 0. A negative <Arg> needs an integer power, else
;; <Functions::Log> gives an ILLEGAL QUANTITY error; the power of its size is negated when the power is odd. For a
;; power of 2^31 or more, <Functions::Int> leaves <SmallInteger> alone, so whether it counts as odd comes from whatever
;; <SmallInteger> held.
;; In: Arg = the base, Fac = the power, zero = set for a zero power
;; Out: Fac = the result
;; Errors: ILLEGAL QUANTITY = a negative base with a power that is not an integer, OVERFLOW = the result is too large
;; Uses: FloatTemporary3, KeptY
;; See: <Functions::Exp>, <Functions::Log>, <Functions::Sqr>
;; Also: FPWRT (BB13)
.proc RaiseArg

;; The sign the base is given before its logarithm is taken.
BaseSign = KeptY

    beq ToExp                               ; a zero power: EXP(0)
    lda ArgExponent
    bne NonzeroBase
    jmp SetExponentAndSign                  ; a zero base

;; Saves the power, and checks a negative base's power is an integer.
;; Also: FPWRT1 (BB13)
NonzeroBase:
    ldx #FloatTemporary3
    lda #FLOAT_TEMPORARY3_X_BYTE
    ldy #>(FloatTemporary3)
    jsr StoreFac                            ; the power into FloatTemporary3; Y = 0, an even power
    lda ArgSign
    bpl TakeLog
    jsr Functions::Int
    ldx #UNPACKED_SIZE - 1

;; Saves <Arg>, which <Float::Compare> overwrites.
;; Also: FPLP1 (BB13)
SaveArg:
    lda Arg,x
    pha
    dex
    bpl SaveArg
    lda #FloatTemporary3
    ldx #FLOAT_TEMPORARY3_X_BYTE
    ldy #>(FloatTemporary3)
    jsr Compare
    bne SetBaseSign                         ; not an integer: A is $FF, so Log refuses the negative base
    tya                                     ; an integer: make the base positive
    ldy SmallInteger                        ; and keep whether the power is odd

;; Takes the base's sign from A and restores <Arg>.
;; Also: FPLP3 (BB13)
SetBaseSign:
    ldx #$100-UNPACKED_SIZE
    sta BaseSign

;; Restores a byte of <Arg>.
;; Also: FPLP2 (BB13)
RestoreArg:
    pla
    sta Arg+UNPACKED_SIZE,x
    inx
    bne RestoreArg
    lda BaseSign

;; Works out `EXP(power * LOG(base))`, then negates it for an odd power.
;; Also: FPWR1 (BB13)
TakeLog:
    jsr CopyArgToFacWithSign                ; the base into Fac, with the sign in A
    tya
    pha                                     ; bit 0 set for an odd power
    jsr Functions::Log
    lda #FloatTemporary3
    ldy #>(FloatTemporary3)
    jsr MultiplyPacked
    jsr Functions::Exp
    pla
    lsr a
    bcc Negate::Done                        ; even
    ; Falls into Negate.
.endproc

;; Negates <Fac>, unless it is zero.
;; Keeps: X, Y
;; Entry:
;;   Done = returns
;; Also: NEGOP (BB13)
.proc Negate
    lda FacExponent
    beq Done
    lda FacSign
    eor #$FF
    sta FacSign

;; Returns.
;; Also: NEGRTS (BB13)
Done:
    rts
.endproc

;; Gives EXP(0), 1, for a zero power.
;; Also: GOTOEXP (BB13)
.proc ToExp
    jmp Functions::Exp
.endproc

.endscope
