; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the decimal input routines.
;; Parameters: earlyExponentLimit = 1 for the earlier exponent limit, 0 for the later limit
.macro DecimalInput earlyExponentLimit

    .assert earlyExponentLimit = 0 || earlyExponentLimit = 1, "earlyExponentLimit is 0 or 1."

    ; Decimal text input.

    .scope Float continued

    ;; Reads a decimal number from BASIC text into <Fac>.
    ;;
    ;; Digits are accumulated by multiplying by ten and adding; <DigitCount> counts fractional digits and
    ;; <DecimalExponent> holds the decimal exponent. An optional exponent accepts either the plus and minus characters
    ;; or BASIC's sign tokens. The final scale is applied by <Float::MultiplyByTen> or <Float::DivideByTen>, then the
    ;; original sign is applied.
    ;; In: A = first character, TextPointer = address of first character, carry = clear if it is a digit
    ;; Entry:
    ;;   NextExponentCharacter = Reads the next exponent character
    ;; See: <GetNextCharacter>, <Float::AddSignedByte>
    ;; Also: FIN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReadNumber
    ldy #$00
    ldx #$0A

;; Zeroes the eleven work bytes from <DigitCount> up without touching carry.
;; Also: FINZLP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ClearLoop:
    ; Clear the decimal counters, sign flags and <Fac> workspace without changing carry.
    sty DigitCount,x
    dex
    bpl ClearLoop
    bcc TestDigit
    cmp #'-'
    bne CheckPlus
    stx InputSign
    beq NextCharacter

;; Skips a leading plus sign.
;; Also: QPLUS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckPlus:
    cmp #'+'
    bne CheckPoint

;; Reads the next character (<GetNextCharacter>).
;; Also: FINC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    jsr GetNextCharacter

;; A digit (carry clear) goes to <Float::ReadNumber::Digit>.
;; Also: FINDGQ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestDigit:
    bcc Digit

;; Tests for '.' and 'E'; after E reads the exponent's sign, as a character or a sign token.
;; Also: FIN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckPoint:
    cmp #'.'
    beq DecimalPoint
    cmp #'E'
    bne EndOfNumber
    jsr GetNextCharacter
    bcc TestExponentDigit
    cmp #TOKEN_MINUS
    beq NegativeExponent
    cmp #'-'
    beq NegativeExponent
    cmp #TOKEN_PLUS
    beq NextExponentCharacter
    cmp #'+'
    beq NextExponentCharacter
    bne ExponentDone

;; Sets <ExponentSign>'s bit 7 for a minus sign after E.
;; Also: FINEC1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NegativeExponent:
    ror ExponentSign

;; Reads the next exponent character.
;; Also: FINEC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextExponentCharacter:
    jsr GetNextCharacter

;; A digit goes to <Float::AccumulateExponentDigit>.
;; Also: FNEDG1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestExponentDigit:
    bcc AccumulateExponentDigit

;; Negates <DecimalExponent> if <ExponentSign> is set, then scales.
;; Also: FINEC2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ExponentDone:
    bit ExponentSign
    bpl EndOfNumber
    lda #$00
    sec
    sbc DecimalExponent
    jmp AdjustExponent

;; Rotates carry into <DecimalPointSeen>; a second point (bit 6 then set) ends the number.
;; Also: FINDP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DecimalPoint:
    ror DecimalPointSeen
    bit DecimalPointSeen
    bvc NextCharacter

;; Loads <DecimalExponent> to scale.
;; Also: FINE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
EndOfNumber:
    lda DecimalExponent

;; Subtracts the digits counted after the point from <DecimalExponent> and picks the scaling loop.
;; Also: FINE1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AdjustExponent:
    sec
    sbc DigitCount                      ; account for digits accumulated after the decimal point
    sta DecimalExponent
    beq ApplySign
    bpl MultiplyLoop

;; <Float::DivideByTen> until <DecimalExponent> is zero.
;; Also: FINDIV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DivideLoop:
    jsr DivideByTen
    inc DecimalExponent
    bne DivideLoop
    beq ApplySign

;; <Float::MultiplyByTen> until <DecimalExponent> is zero.
;; Also: FINMUL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MultiplyLoop:
    jsr MultiplyByTen
    dec DecimalExponent
    bne MultiplyLoop

;; Negates the result if <InputSign> is negative.
;; Also: FINQNG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ApplySign:
    lda InputSign
    bmi ToNegate
    rts

;; Jumps on to <Float::Negate>.
;; Also: NEGXQS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToNegate:
    jmp Negate

;; Counts a digit after the point, then multiplies <Fac> by ten.
;; Also: FINDIG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Digit:
    pha
    bit DecimalPointSeen
    bpl AddDigit
    inc DigitCount

;; <Float::MultiplyByTen>, then adds the digit's value (<Float::AddSignedByte>).
;; Also: FINDG1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AddDigit:
    jsr MultiplyByTen
    pla
    sec
    sbc #'0'
    jsr AddSignedByte
    jmp NextCharacter
    .endproc

    ;; Adds the signed byte in A to <Fac>, converting it to floating point first.
    ;; In: A = signed byte
    ;; Also: FINLOG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
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

    ;; Accumulates a decimal exponent digit into <DecimalExponent>.
    ;;
    ;; With the later limit, an accumulated exponent of ten or more signals overflow when positive and becomes 100
    ;; when negative. With the earlier limit, an accumulated exponent of twelve or more signals overflow when positive;
    ;; when negative, the arithmetic uses eleven for the first term but still adds the old <DecimalExponent>. The
    ;; resulting exponent is (88 + twice the old exponent + the next digit), modulo 256.
    ;; Also: FINEDG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AccumulateExponentDigit
    lda DecimalExponent
    .if earlyExponentLimit
        cmp #$0C
        bcc TimesTen
        bit ExponentSign
        bmi ClampNegative
        jmp OverflowError

;; Negative exponent over the limit: earlier build continues with 11, later build stores 100.
;; Also: MLEXMI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ClampNegative:
        lda #$0B
    .else
        cmp #$0A
        bcc TimesTen
        lda #$64
        bit ExponentSign
        bmi ClampNegative
        jmp OverflowError
    .endif

;; Computes (4 * A + <DecimalExponent>) * 2 + the digit at <TextPointer>: ten times <DecimalExponent> plus the digit,
;; except on the earlier build's clamp path, where A is 11.
;; Also: MLEX10 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TimesTen:
    asl a
    asl a
    clc
    adc DecimalExponent
    asl a
    clc
    ldy #$00
    adc (TextPointer),y
    sec
    sbc #'0'

    .if .not earlyExponentLimit
;; Negative exponent over the limit: earlier build continues with 11, later build stores 100.
;; Also: MLEXMI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ClampNegative:
    .endif
    sta DecimalExponent
    jmp ReadNumber::NextExponentCharacter
    .endproc
    .endscope

.endmacro
