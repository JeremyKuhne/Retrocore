; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the line-number and decimal-output routines.
;; Parameters: omitPositiveSpace = 1 to omit the leading space for positive values, otherwise 0
;;   includeTime = 1 to use the time-conversion table, otherwise 0
.macro DecimalOutput omitPositiveSpace, includeTime

    .assert omitPositiveSpace = 0 || omitPositiveSpace = 1, "omitPositiveSpace is 0 or 1."
    .assert includeTime = 0 || includeTime = 1, "includeTime is 0 or 1."

    ; Line-number printing and floating-point formatting.

    .scope Float continued

    ;; Prints the line-number prefix and the current line number.
    ;; See: <Float::PrintDecimalAX>, <INTXT>
    ;; Also: INPRT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintInLineNumber
    lda #<INTXT
    ldy #>INTXT
    jsr PrintFac::ToPrintString
    lda CurrentLine+1
    ldx CurrentLine
    ; Falls into PrintDecimalAX.
    .endproc

    ;; Prints the unsigned line number in A:X.
    ;; In: A = high byte of line number, X = low byte of line number
    ;; See: <Float::FormatFac>, <PrintText>
    ;; Also: LINPRT (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc PrintDecimalAX
    sta FacMantissa1
    stx FacMantissa2
    ldx #$90
    sec
    jsr ConvertWord
    ; Falls into PrintFac.
    .endproc

    ;; Prints <Fac> as a decimal number through <Float::FormatFac> and <PrintText>.
    ;; Entry:
    ;;   ToPrintString = Jumps on to <PrintText>, printing the string at Y:A
    .proc PrintFac
    jsr FormatFac

;; Prints the string addressed by Y:A through <PrintText>.
;; Also: STROU2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToPrintString:
    jmp PrintText
    .endproc

    ;; Formats <Fac> as a zero-terminated decimal string in <NumberBuffer>.
    ;;
    ;; It scales the magnitude between the thresholds, rounds by adding one half, and converts the integer with
    ;; <Float::PowersOfTen>. It suppresses trailing fractional zeroes and emits a signed, two-digit E exponent when
    ;; needed. <Fac> is changed. The positive sign is either a space or omitted, according to the variant.
    ;; <Float::FormatFacAtOffset> also serves `STR$`: with Y = 0 its string begins one byte earlier at
    ;; <NumberBufferPrefix>.
    ;; Out: A = low byte of <NumberBuffer>, Y = high byte of <NumberBuffer>
    ;; Also: FOUT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FormatFac
    ldy #$01
    .endproc

    ;; Uses the caller's Y to select the initial output position.
    ;; Entry:
    ;;   ExtractDigits = With Y at a power of ten: sets X's bit 7 for the first pass and extracts digits; the PET's TI$
    ;;     conversion enters here with Y at a time divisor
    ;; Also: FOUTC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FormatFacAtOffset
    .if omitPositiveSpace
        lda #'-'
        dey
        bit FacSign
        bpl SignDone
        iny

;; Stores the minus sign; a positive number skips this store, since this build omits the leading space.
;; Also: FOUT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreSign:
        sta NumberBuffer-1,y

;; A positive number in the omitted-space build stores no sign character.
SignDone:
    .else
        lda #' '
        bit FacSign
        bpl StoreSign
        lda #'-'

;; Stores the sign character, a space or a minus.
;; Also: FOUT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreSign:
        sta NumberBuffer-1,y
    .endif
    sta FacSign
    sty NumberBufferPointer
    iny
    lda #'0'
    ldx FacExponent
    bne *+5                         ; skip the zero-output jump for a nonzero exponent
    jmp StoreZero
    lda #$00
    cpx #$80
    beq ScaleUpSmall
    bcs SetScale

;; <Fac> below 1: multiplies by <Float::Billion> and starts the decimal scale at -9.
;; Also: FOUT37 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ScaleUpSmall:
    lda #<Billion
    ldy #>Billion
    jsr MultiplyPacked
    lda #$F7

;; Stores the starting decimal scale in <DigitCount>.
;; Also: FOUT7 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetScale:
    sta DigitCount

;; Compares with <Float::UpperOutputLimit>: equal goes straight to <Float::FormatFacAtOffset::ConvertInteger>, larger
;; divides.
;; Also: FOUT4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckUpper:
    ; Scale the magnitude into the nine-digit range, keeping the decimal scale in <DigitCount>.
    lda #<UpperOutputLimit
    ldy #>UpperOutputLimit
    jsr Compare
    beq ConvertInteger
    bpl DivideDown

;; Compares with <Float::LowerOutputLimit>: larger rounds.
;; Also: FOUT3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckLower:
    lda #<LowerOutputLimit
    ldy #>LowerOutputLimit
    jsr Compare
    beq MultiplyUp
    bpl RoundHalf

;; <Float::MultiplyByTen> and lowers the scale.
;; Also: FOUT38 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MultiplyUp:
    jsr MultiplyByTen
    dec DigitCount
    bne CheckLower

;; <Float::DivideByTen> and raises the scale.
;; Also: FOUT9 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DivideDown:
    jsr DivideByTen
    inc DigitCount
    bne CheckUpper

;; Adds 1/2 (<Float::AddHalf>) to round.
;; Also: FOUT5 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RoundHalf:
    jsr AddHalf

;; <Float::ToLongInteger>, then decides between fixed point and an E exponent from the scale.
;; Also: BIGGES (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ConvertInteger:
    jsr ToLongInteger
    ldx #$01
    lda DigitCount
    clc
    adc #$0A
    bmi UseExponent
    cmp #$0B
    bcs SetExponent
    adc #$FF
    tax
    lda #$02

;; Sets carry for the subtraction that follows: branched to when the decimal scale is below -10 (the value, rounded
;; to nine digits, is below .01), or fallen into with A = 2, which makes the printed exponent zero (fixed point). A
;; large value goes on to <Float::FormatFacAtOffset::SetExponent> with carry already set.
;; Also: FOUTPI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
UseExponent:
    sec

;; Stores the printed exponent in <DecimalExponent> (0 means fixed point) and the digits before the point.
;; Also: FOUT6 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetExponent:
    sbc #$02
    sta DecimalExponent                      ; zero selects fixed-point output
    stx DigitCount
    txa
    beq LeadingPoint
    bpl FirstPower

;; No digits before the point: writes '.' and, if needed, '0'.
;; Also: FOUT39 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
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

;; Saves the buffer position.
;; Also: FOUT16 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SavePosition:
    sty NumberBufferPointer

;; Starts at the first power of ten.
;; Also: FOUT8 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FirstPower:
    ldy #$00

;; With Y at a power of ten: sets X's bit 7 for the first pass and extracts digits. The PET's TI$ conversion enters
;; here with Y at a time divisor.
;; Also: FOUTIM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ExtractDigits:
    ldx #$80

;; Extracts one decimal digit by repeated addition of an alternating signed power of ten.
;; Also: FOUT2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AddPower:
    lda FacMantissa4
    clc
    adc PowersOfTen+3,y
    sta FacMantissa4
    lda FacMantissa3
    adc PowersOfTen+2,y
    sta FacMantissa3
    lda FacMantissa2
    adc PowersOfTen+1,y
    sta FacMantissa2
    lda FacMantissa1
    adc PowersOfTen,y
    sta FacMantissa1
    inx
    bcs Carried
    bpl AddPower
    bmi DigitFound

;; A carry with a negative power: keep adding.
;; Also: FOUT41 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Carried:
    bmi AddPower

;; Turns the count into the digit (complemented for a positive power).
;; Also: FOUT40 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DigitFound:
    txa
    bcc StoreDigit
    eor #$FF
    adc #$0A

;; Makes the count a digit character, stores it and writes '.' when the digits before the point are done.
;; Also: FOUTYP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreDigit:
    adc #('0'-1)
    iny
    iny
    iny
    iny
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

;; Saves the buffer position and reloads the table offset.
;; Also: STXBUF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SavePointer:
    sty NumberBufferPointer
    ldy PowerTablePointer

;; Flips X's bit 7 for the next power's sign; loops until the table (or the TI$ divisors) ends.
;; Also: FOUTCM (M6502)
NextPower:
    txa
    eor #$FF
    and #$80
    tax
    cpy #(PowersOfTenEnd-PowersOfTen)
    .if includeTime
        beq DigitsDone
        cpy #(TimeDivisorsEnd-PowersOfTen)
    .endif
    bne AddPower

;; Reloads the buffer position.
;; Also: FOULDY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DigitsDone:
    ldy NumberBufferPointer

;; Removes trailing fractional zeroes and an unnecessary decimal point before emitting any exponent.
;; Also: FOUT11 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TrimZeros:
    lda NumberBuffer-1,y
    dey
    cmp #'0'
    beq TrimZeros
    cmp #'.'
    beq Exponent
    iny

;; Writes no exponent for fixed point; otherwise picks its sign.
;; Also: FOUT12 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Exponent:
    lda #'+'
    ldx DecimalExponent
    beq Terminate
    bpl StoreExponentSign
    lda #$00
    sec
    sbc DecimalExponent
    tax
    lda #'-'

;; Writes 'E' and the exponent's sign.
;; Also: FOUT14 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreExponentSign:
    sta NumberBuffer+1,y
    lda #'E'
    sta NumberBuffer,y
    txa
    ldx #('0'-1)
    sec

;; Counts the exponent's tens, then writes its two digits and the terminator.
;; Also: FOUT15 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ExponentTens:
    inx
    sbc #$0A
    bcs ExponentTens
    adc #('0'+10)
    sta NumberBuffer+3,y
    txa
    sta NumberBuffer+2,y
    lda #$00
    sta NumberBuffer+4,y
    beq ReturnBuffer

;; <Fac> is zero: writes '0'.
;; Also: FOUT19 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreZero:
    sta NumberBuffer-1,y

;; Writes the zero terminator.
;; Also: FOUT17 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Terminate:
    lda #$00
    sta NumberBuffer,y

;; Returns Y:A = <NumberBuffer>.
;; Also: FOUT20 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReturnBuffer:
    lda #<NumberBuffer
    ldy #>NumberBuffer

;; The rts.
;; Also: FPWRRT (M6502)
Return:
    rts
    .endproc
    .endscope

.endmacro
