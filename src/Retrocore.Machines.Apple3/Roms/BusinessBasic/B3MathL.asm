; retrocore: style=strict
;; Business BASIC's floating point, part two (Apple's B3MATHL): `LOG`, multiplication and division, the routines that
;; move reals between <Fac>, <ArgExponent> and memory, rounding, `SGN` and `ABS`, comparison, and the start of
;; <Float::ToLongInteger>, which goes on in B3FinpM.asm.
;;
;; The formats are described in B3MathK.asm. The constants here are five-byte reals in BASIC's own bank.

; Floating point, part two: LOG's constants.
.scope Float continued

; ---------------------------------------------------------------------------------------------------------------------
; LOG
; ---------------------------------------------------------------------------------------------------------------------

;; 1.0.
;; Also: FONE (BB13)
One:
    .byte $81, $00, $00, $00, $00

;; The polynomial <Functions::Log> uses for the base-2 logarithm of its fraction, in odd powers: the count of terms less
;; one, then the coefficients, highest power first.
;; See: <EvaluateOddPolynomial>
;; Also: LOGCN2 (BB13)
LogPolynomial:
    .byte 3
    .byte $7F, $5E, $56, $CB, $79           ; 0.43425594188
    .byte $80, $13, $9B, $0B, $64           ; 0.57658454134
    .byte $80, $76, $38, $93, $16           ; 0.96180075921
    .byte $82, $38, $AA, $3B, $20           ; 2.8853900728

;; The square root of 0.5.
;; Also: SQR0_5 (BB13)
SquareRootOfHalf:
    .byte $80, $35, $04, $F3, $34

;; The square root of 2.
;; Also: SQR2_0 (BB13)
SquareRootOfTwo:
    .byte $81, $35, $04, $F3, $34

;; -0.5.
;; Also: NEGHLF (BB13)
MinusHalf:
    .byte $80, $80, $00, $00, $00

;; The natural logarithm of 2.
;; Also: LOG2 (BB13)
LogOfTwo:
    .byte $80, $31, $72, $17, $F8

.endscope

; The LOG function.
.scope Functions continued

;; Gives `LOG`, the natural logarithm of <Fac>.
;;
;; For a <Fac> of f times 2^n, with f from 0.5 to 1, it works out the base-2 logarithm of f from a polynomial in
;; `(f - SQR(0.5)) / (f + SQR(0.5))`, adds n and multiplies by the logarithm of 2. A <Fac> of zero or less is an illegal
;; quantity.
;; Errors: ILLEGAL QUANTITY = the <Fac> is zero or negative
;; See: <Float::LogPolynomial>, <Float::EvaluateOddPolynomial>, <Float::AddSignedByte>
;; Also: LOG (BB13)
.proc Log
    jsr Float::GetSign
    beq ToIllegalQuantity
    bpl Reduce

;; Ends the statement with ILLEGAL QUANTITY.
;; Also: LOGERR (BB13)
ToIllegalQuantity:
    jmp IllegalQuantityError

;; Takes the logarithm of a positive <Fac>: keeps its exponent as n and makes it a fraction from 0.5 to 1.
;; Also: LOG1 (BB13)
Reduce:
    lda FacExponent
    sbc #Float::EXPONENT_BIAS - 1           ; the carry is clear: less the bias
    pha                                     ; n
    lda #Float::EXPONENT_BIAS
    sta FacExponent                              ; f, from 0.5 to 1
    lda #<(Float::SquareRootOfHalf)
    ldy #>(Float::SquareRootOfHalf)
    jsr Float::AddPacked
    lda #<(Float::SquareRootOfTwo)
    ldy #>(Float::SquareRootOfTwo)
    jsr Float::DividePacked
    lda #<(Float::One)
    ldy #>(Float::One)
    jsr Float::SubtractFromPacked           ; 1 - SQR(2) / (f + SQR(0.5))
    lda #<(Float::LogPolynomial)
    ldy #>(Float::LogPolynomial)
    jsr Float::EvaluateOddPolynomial
    lda #<(Float::MinusHalf)
    ldy #>(Float::MinusHalf)
    jsr Float::AddPacked
    pla
    jsr Float::AddSignedByte                ; add n
    lda #<(Float::LogOfTwo)
    ldy #>(Float::LogOfTwo)
    ldx #LOG_CONSTANTS_X_BYTE                              ; left over: MultiplyPacked sets X itself
    ; Falls into Float::MultiplyPacked.
.endproc

.endscope

; Floating point, part two: multiplication, division, moves, signs and comparison.
.scope Float continued

; ---------------------------------------------------------------------------------------------------------------------
; Multiplication
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies <Fac> by the five-byte real at A, Y.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::MultiplyArg>, <Float::LoadArg>
;; Also: FMULT (BB13)
.proc MultiplyPacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into MultiplyArg.
.endproc

;; Multiplies <Fac> by <ArgExponent>, into the <Fac>: <ArgExponent>'s mantissa times each byte of the <Fac>'s, the rounding byte first,
;; summed in <Result1>.
;; In: A = <FacExponent>, zero = set for a zero <Fac>, ARISGN = the product's sign
;; See: <Float::CombineExponents>, <Float::MultiplyByte>, <Float::NormalizeResult>
;; Also: FMULTT (BB13)
.proc MultiplyArg
    bne *+5                                 ; skip the jump for a FAC that is not zero
    jmp MultiplyByte::Done                  ; a zero FAC is the product
    jsr CombineExponents
    lda #0
    sta Result1
    sta Result2
    sta Result3
    sta Result4
    lda FacExtension
    jsr MultiplyByte
    lda FacMantissa4
    jsr MultiplyByte
    lda FacMantissa3
    jsr MultiplyByte
    lda FacMantissa2
    jsr MultiplyByte
    lda FacMantissa1
    jsr MultiplyByte::NonZero               ; the high byte is never zero
    jmp NormalizeResult
.endproc

;; Adds <ArgExponent> times the multiplier byte in A into <Result1>, shifting <Result1> right a bit for each of its bits; a zero byte
;; just shifts <Result1> a byte.
;; In: A = the multiplier byte
;; Entry:
;;   NonZero = skips the test for zero, for a byte that is never zero
;;   Done = returns
;; See: <Float::ShiftProductByte>
;; Also: MLTPLY (BB13)
.proc MultiplyByte
    bne *+5                                 ; skip the jump for a byte that is not zero
    jmp ShiftProductByte

;; Multiplies by a non-zero byte, with a marker bit above it to count the eight bits.
;; Also: MLTPL1 (BB13)
NonZero:
    lsr a
    ora #$80

;; Adds <ArgExponent> to <Result1> when the bit shifted out is set.
;; In: carry = the bit, A = the bits left
;; Also: MLTPL2 (BB13)
NextBit:
    tay
    bcc Shift
    clc
    lda Result4
    adc ArgMantissa4
    sta Result4
    lda Result3
    adc ArgMantissa3
    sta Result3
    lda Result2
    adc ArgMantissa2
    sta Result2
    lda Result1
    adc ArgMantissa1
    sta Result1

;; Shifts <Result1> right a bit, into <FacExtension>, and goes on while bits are left.
;; Also: MLTPL3 (BB13)
Shift:
    ror Result1
    ror Result2
    ror Result3
    ror Result4
    ror FacExtension
    tya
    lsr a
    bne NextBit

;; Returns.
;; Also: MULTRT (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Unpacking and exponents
; ---------------------------------------------------------------------------------------------------------------------

;; Unpacks a real from memory into <ArgExponent>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A = the real's address, low byte, Y = its high byte, X = its bank, 0 for BASIC's own
;; Out: ARG = the real, ARISGN = <ArgExponent>'s sign exclusive-ored with the <Fac>'s, A = <FacExponent>,
;;   zero = set for a zero <Fac>, Y = 0
;; Uses: INDEX1
;; Keeps: X
;; See: <Float::LoadFac>
;; Also: CONUPK (BB13)
.proc LoadArg
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    ldy #CONSTANT_SIZE - 1
    lda (Pointer1),y
    cpx #0
    beq *+4                                 ; BASIC's own bank: keep the fifth byte
    lda #0                                  ; a variable: no fifth byte
    sta ArgMantissa4
    dey
    lda (Pointer1),y
    sta ArgMantissa3
    dey
    lda (Pointer1),y
    sta ArgMantissa2
    dey
    lda (Pointer1),y
    sta ArgSign                              ; the sign is the top bit
    eor FacSign
    sta ResultSign
    lda ArgSign
    ora #$80                                ; the implied 1
    sta ArgMantissa1
    dey
    lda (Pointer1),y
    sta ArgExponent
    lda FacExponent
    rts
.endproc

;; Adds <ArgExponent>'s exponent to <Fac>'s for a multiplication or division, and sets the result's sign.
;;
;; A zero <ArgExponent>, or a result too small to hold, makes the <Fac> zero and returns from the routine that called this
;; one; a result too large ends the statement with OVERFLOW. A result exponent of exactly 0 makes the <Fac> zero, its
;; sign too, and returns to the caller.
;; Out: FACEXP = the sum, less the bias, FACSGN = <ResultSign>
;; See: <Float::AddExponent>
;; Also: MULDIV (BB13)
.proc CombineExponents
    lda ArgExponent
    ; Falls into AddExponent.
.endproc

;; Adds the exponent in A to <Fac>'s, as <Float::CombineExponents> does.
;; In: A = the exponent
;; Also: MLDEXP (BB13)
.proc AddExponent
    beq Underflow                           ; times zero
    clc
    adc FacExponent
    bcc NoCarry
    bmi ToOverflowError                     ; past $17F: too large
    clc
    .byte $2C                               ; BIT absolute, which skips NoCarry's BPL

;; Takes a sum with no carry: below $80 is too small; otherwise takes off the bias.
;; Also: TRYOFF (BB13)
NoCarry:
    bpl Underflow
    adc #EXPONENT_BIAS
    sta FacExponent
    bne *+5                                 ; skip the jump for an exponent that is not zero
    jmp SetSign                             ; zero: the sign is 0 too
    lda ResultSign
    sta FacSign
    rts
.endproc

;; For a result whose exponent is out of range: too large when <Fac> is positive, and zero when it is negative.
;; See: <Functions::Exp>
;; Also: MLDVEX (BB13)
.proc ExponentOutOfRange
    lda FacSign
    eor #$FF
    bmi ToOverflowError
    ; Falls into Underflow.
.endproc

;; Makes <Fac> zero and returns from the routine that called the exponent check.
;; Also: ZEREMV (BB13)
.proc Underflow
    pla
    pla
    jmp SetZero
.endproc

;; Ends the statement with OVERFLOW.
;; Also: GOOVER (BB13)
.proc ToOverflowError
    jmp OverflowError
.endproc

;; Multiplies <Fac> by 10: four times itself, plus itself, doubled.
;; Out: ARG = the <Fac> as it was, rounded
;; Errors: OVERFLOW = the product is too large
;; Entry:
;;   Done = returns
;; Also: MUL10 (BB13)
.proc MultiplyByTen
    jsr CopyFacToArg
    tax
    beq Done                                ; zero stays zero
    clc
    adc #2                                  ; four times
    bcs ToOverflowError
    ldx #0
    stx ResultSign
    jsr AlignAndAdd                         ; plus itself
    inc FacExponent                              ; doubled
    beq ToOverflowError

;; Returns.
;; Also: MUL10R (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Division
; ---------------------------------------------------------------------------------------------------------------------

;; 10.0.
;; Also: TEN_C (BB13)
Ten:
    .byte $84, $20, $00, $00, $00

;; Divides <Fac> by 10.
;;
;; The quotient is positive whatever the <Fac>'s sign: <Float::ReadNumber> and <Float::FormatFac>, which use it, work on
;; a positive number and set the sign themselves.
;; Also: DIV10 (BB13)
.proc DivideByTen
    jsr CopyFacToArg
    lda #<(Ten)
    ldy #>(Ten)
    ldx #0                                  ; the quotient's sign
    ; Falls into DivideArgByPacked.
.endproc

;; Divides <ArgExponent> by the five-byte real at A, Y, giving the quotient the sign in X.
;; In: A = the divisor's address, low byte, Y = its high byte, in BASIC's own bank, X = the quotient's sign
;; Also: FDIVF (BB13)
.proc DivideArgByPacked
    stx ResultSign
    ldx #TEN_X_BYTE
    jsr LoadFac
    jmp DivideArg
.endproc

;; Divides the five-byte real at A, Y by <Fac>, into the <Fac>.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::DivideArg>, <Float::LoadArg>
;; Also: FDIV (BB13)
.proc DividePacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into DivideArg.
.endproc

;; Divides <ArgExponent> by <Fac>, into the <Fac>, a bit of the quotient at a time; a zero <Fac> ends the statement with
;; DIVISION BY ZERO.
;; In: A = <FacExponent>, zero = set for a zero <Fac>, ARISGN = the quotient's sign
;; Errors: DIVISION BY ZERO = the <Fac> is zero, OVERFLOW = the quotient is too large
;; See: <Float::CombineExponents>, <Float::NormalizeResult>
;; Also: FDIVT (BB13)
.proc DivideArg
    bne NotZero
    jmp DivisionByZero

;; Divides by a <Fac> that is not zero: rounds it, subtracts its exponent from <ArgExponent>'s, and sets the marker bit that
;; counts each quotient byte's eight bits.
;; Also: NO0ERR (BB13)
NotZero:
    jsr Round
    lda #0                                  ; negate the FAC's exponent, so CombineExponents subtracts it
    sec
    sbc FacExponent
    sta FacExponent
    jsr CombineExponents
    inc FacExponent
    beq ToOverflowError
    ldx #$100-3-1                           ; RES's bytes, from RESHO
    lda #1                                  ; a marker bit, to count eight bits

;; Compares <ArgExponent>'s mantissa with <Fac>'s, the divisor.
;; Also: DIVIDE (BB13)
Compare:
    ldy ArgMantissa1
    cpy FacMantissa1
    bne SaveBit
    ldy ArgMantissa2
    cpy FacMantissa2
    bne SaveBit
    ldy ArgMantissa3
    cpy FacMantissa3
    bne SaveBit
    ldy ArgMantissa4
    cpy FacMantissa4

;; Shifts the comparison's result, as the next bit of the quotient, into A; each full byte goes to <Result1>, and the last
;; two bits to <FacExtension>.
;; In: carry = set when the divisor goes into <ArgExponent>
;; Also: SAVQUO (BB13)
SaveBit:
    php
    rol a
    bcc TestSubtract                        ; the byte is not full yet
    inx
    sta Result4,x
    beq LastBits                            ; RESLO is done: two more bits
    bpl Finish                              ; the two more bits are done
    lda #1

;; Subtracts the divisor when it went into <ArgExponent>, then shifts <ArgExponent> left a bit.
;; Also: QSHFT (BB13)
TestSubtract:
    plp
    bcs Subtract

;; Shifts <ArgExponent> left a bit, then compares again; a bit carried out of <ArgExponent>'s top means the divisor goes in, and a clear
;; top bit that it does not.
;; Also: SHFARG (BB13)
ShiftDividend:
    asl ArgMantissa4
    rol ArgMantissa3
    rol ArgMantissa2
    rol ArgMantissa1
    bcs SaveBit
    bmi Compare
    bpl SaveBit

;; Subtracts the divisor from <ArgExponent>.
;; In: carry = set
;; Also: DIVSUB (BB13)
Subtract:
    tay
    lda ArgMantissa4
    sbc FacMantissa4
    sta ArgMantissa4
    lda ArgMantissa3
    sbc FacMantissa3
    sta ArgMantissa3
    lda ArgMantissa2
    sbc FacMantissa2
    sta ArgMantissa2
    lda ArgMantissa1
    sbc FacMantissa1
    sta ArgMantissa1
    tya
    jmp ShiftDividend

;; Sets the marker bit for the last two bits of the quotient.
;; Also: LD100 (BB13)
LastBits:
    lda #$40
    bne TestSubtract                        ; always

;; Puts the last two bits of the quotient at the top of <FacExtension>, then moves the quotient into <Fac>.
;; Also: DIVNRM (BB13)
Finish:
    ror a
    ror a
    ror a
    and #$C0
    sta FacExtension
    plp
    jmp NormalizeResult

;; Ends the statement with DIVISION BY ZERO, through <ReportError>.
;; Also: DV0ERR (BB13)
DivisionByZero:
    ldx #ERROR_DIVISION_BY_ZERO
    jmp ReportError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Moving reals
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the result of a multiplication or division, <Result1>, into <Fac>'s mantissa and normalizes it.
;; See: <Float::Normalize>
;; Also: MOVFR (BB13)
.proc NormalizeResult
    lda Result1
    sta FacMantissa1
    lda Result2
    sta FacMantissa2
    lda Result3
    sta FacMantissa3
    lda Result4
    sta FacMantissa4
    jmp Normalize
.endproc

;; Unpacks a real from memory into <Fac>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A = the real's address, low byte, Y = its high byte, X = its bank, 0 for BASIC's own
;; Out: A = <FacExponent>, zero = set for a zero <Fac>, FACOV = 0, Y = 0
;; Uses: INDEX1
;; Keeps: X
;; Also: MOVFM (BB13)
.proc LoadFac
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    ldy #CONSTANT_SIZE - 1
    lda #0
    cpx #0
    bne *+4                                 ; a variable: no fifth byte
    lda (Pointer1),y
    sta FacMantissa4
    dey
    lda (Pointer1),y
    sta FacMantissa3
    dey
    lda (Pointer1),y
    sta FacMantissa2
    dey
    lda (Pointer1),y
    sta FacSign                              ; the sign is the top bit
    ora #$80                                ; the implied 1
    sta FacMantissa1
    dey
    lda (Pointer1),y
    sta FacExponent
    sty FacExtension
    rts
.endproc

;; Packs <Fac> into <FloatTemporary2>, five bytes.
;; See: <Float::StoreFac>
;; Also: MOV2F (BB13)
.proc StoreFacInTemporary2
    ldx #FloatTemporary2
    .byte $2C                               ; BIT absolute, which skips StoreFacInTemporary1's LDX
    ; Falls into StoreFacInTemporary1.
.endproc

;; Packs <Fac> into <FloatTemporary1>, five bytes.
;; See: <Float::StoreFac>
;; Also: MOV1F (BB13)
.proc StoreFacInTemporary1
    ldx #FloatTemporary1
    ldy #0
    tya                                     ; BASIC's own bank
    beq StoreFac                            ; always
.endproc

;; Packs <Fac> into the variable <AssignedVariable> points to.
;; See: <Float::StoreFac>
;; Also: MOVVF (BB13)
.proc StoreFacInVariable
    ldx AssignedVariable
    lda AssignedVariableXByte
    ldy AssignedVariable+1
    ; Falls into StoreFac.
.endproc

;; Rounds <Fac> and packs it into memory: five bytes in BASIC's own bank, or a variable's four, rounded to three
;; mantissa bytes, in another.
;;
;; In BASIC's own bank the fifth byte is stored and the variable's rounding skipped, except that a fifth byte of zero
;; doesn't skip it: <Float::RoundForVariable> then rounds once more by the next bit of <FacExtension>, which can only make
;; <FacMantissa4> 1, and clears <FacMantissa4> again, so the bytes stored are the same.
;; In: X = the address, low byte, Y = its high byte, A = the bank, 0 for BASIC's own
;; Out: X = the bank, Y = 0, FACOV = 0
;; Uses: INDEX1
;; Entry:
;;   AtPointer = stores at the address and bank already in <Pointer1> and its X-byte, with the bank in A as well
;; See: <Float::Round>, <Float::RoundForVariable>
;; Also: MOVMF (BB13)
.proc StoreFac
    stx Pointer1
    sty Pointer1+1
    sta Pointer1XByte

;; Stores <Fac>'s five or four bytes at <Pointer1>.
;; In: A = the bank
;; Also: FOURBYT (BB13)
AtPointer:
    ldy #CONSTANT_SIZE - 1
    tax
    bne ToVariable                          ; a variable
    jsr Round
    lda FacMantissa4
    sta (Pointer1),y                           ; the fifth byte
    bne *+5                                 ; skip ToVariable's rounding (not for a fifth byte of zero)

;; Rounds <Fac> to a variable's three mantissa bytes, then stores the first four bytes.
;; Also: FURBYT (BB13)
ToVariable:
    jsr RoundForVariable
    dey
    lda FacMantissa3
    sta (Pointer1),y
    dey
    lda FacMantissa2
    sta (Pointer1),y
    dey
    lda FacSign                              ; the sign, in place of the implied 1
    ora #$7F
    and FacMantissa1
    sta (Pointer1),y
    dey
    lda FacExponent
    sta (Pointer1),y
    sty FacExtension
    rts
.endproc

;; Rounds <Fac> to the three mantissa bytes a variable keeps, to the nearest, a half to even, and clears <FacMantissa4>.
;; Out: FACLO = 0
;; Keeps: X, Y
;; See: <Float::Round>
;; Also: ROUNDER (BB13)
.proc RoundForVariable
    jsr Round
    lda FacMantissa4
    bpl ClearLow                            ; below a half: down
    asl a
    sta Temporary
    lda FacMantissa3
    and #1
    ora Temporary                                ; above a half, or a half with FACMO odd: up
    beq ClearLow
    lda #$FF
    sta FacMantissa4                               ; so that adding one carries into FACMO
    jsr Round::Increment

;; Clears <FacMantissa4>.
;; Also: RONDRTS (BB13)
ClearLow:
    lda #0
    sta FacMantissa4
    rts
.endproc

;; Moves <ArgExponent> into <Fac>.
;; Out: X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVFA (BB13)
.proc CopyArgToFac
    lda ArgSign
    ; Falls into CopyArgToFacWithSign.
.endproc

;; Moves <ArgExponent>'s exponent and mantissa into <Fac>, with A as its sign.
;; In: A = the sign
;; Out: X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVFA1 (BB13)
.proc CopyArgToFacWithSign
    sta FacSign
    ldx #UNPACKED_SIZE - 1                  ; the exponent and the mantissa

;; Moves a byte, from the lowest.
;; Also: MOVFAL (BB13)
Loop:
    lda ArgExponent-1,x
    sta FacExponent-1,x
    dex
    bne Loop
    stx FacExtension
    rts
.endproc

;; Rounds <Fac> and copies it, with its sign, into <ArgExponent>.
;; Out: A = <FacExponent>, X = 0, FACOV = 0
;; Keeps: Y
;; See: <Float::Round>
;; Also: MOVAF (BB13)
.proc CopyFacToArg
    jsr Round
    ; Falls into CopyFacToArgUnrounded.
.endproc

;; Copies <Fac>, with its sign, into <ArgExponent> without rounding it.
;; Out: A = <FacExponent>, X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVEF (BB13)
.proc CopyFacToArgUnrounded
    ldx #UNPACKED_SIZE

;; Copies a byte, from the sign down.
;; Also: MOVAFL (BB13)
Loop:
    lda FacExponent-1,x
    sta ArgExponent-1,x
    dex
    bne Loop
    stx FacExtension
    rts
.endproc

;; Rounds <Fac>'s mantissa by the top bit of <FacExtension>, taking a carry out of the top into the exponent.
;; Uses: A
;; Keeps: X, Y
;; Entry:
;;   Increment = adds one to the mantissa, taking a carry out of the top into the exponent
;;   Done = returns
;; Also: ROUND (BB13)
.proc Round
    lda FacExponent
    beq Done                                ; zero
    asl FacExtension
    bcc Done                                ; below a half

;; Adds one to <Fac>'s mantissa, taking a carry out of the top into the exponent.
;; See: <Float::IncrementMantissa>, <Float::ShiftInCarry>
;; Also: INCRND (BB13)
Increment:
    jsr IncrementMantissa
    bne Done
    jsr ShiftInCarry

;; Returns.
;; Also: RONRTS (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Signs
; ---------------------------------------------------------------------------------------------------------------------

;; Gives <Fac>'s sign.
;; Out: A = 0 for zero, 1 for positive, $FF for negative
;; Keeps: X, Y
;; Entry:
;;   FromSignByte = gives the sign of <FacSign>, as a non-zero <Fac>'s, with carry = set for negative
;;   FromBit7 = gives 1 or $FF by the top bit of A, with carry = set for $FF
;;   Done = returns
;; Also: SIGN (BB13)
.proc GetSign
    lda FacExponent
    beq Done

;; Gives the sign of <FacSign>, as a non-zero <Fac>'s.
;; Also: FCSIGN (BB13)
FromSignByte:
    lda FacSign

;; Gives 1 or $FF by the top bit of A.
;; Also: FCOMPS (BB13)
FromBit7:
    rol a
    lda #$100-1
    bcs Done
    lda #1

;; Returns.
;; Also: SIGNRT (BB13)
Done:
    rts
.endproc

.endscope

; The SGN function.
.scope Functions continued

;; Gives `SGN`, replacing <Fac> with its sign: -1, 0 or 1.
;; See: <Float::GetSign>, <Float::ConvertSignedByte>
;; Also: SGN (BB13)
.proc Sgn
    jsr Float::GetSign
    ; Falls into Float::ConvertSignedByte.
.endproc

.endscope

; Floating point, part two: integers to reals.
.scope Float continued

;; The exponent of a real whose mantissa, taken as a 32-bit integer, is its value: from 2^31 to below 2^32.
LONG_INTEGER_EXPONENT = EXPONENT_BIAS + 32

;; The exponent of a real whose mantissa's top two bytes, taken as a 16-bit integer, are its value.
WORD_EXPONENT = EXPONENT_BIAS + 16

;; The exponent of a real whose mantissa's top byte, taken as an 8-bit integer, is its value.
BYTE_EXPONENT = EXPONENT_BIAS + 8

;; Floats the signed byte in A into <Fac>.
;; In: A = the byte
;; Also: FLOAT (BB13)
.proc ConvertSignedByte
    sta FacMantissa1
    lda #0
    sta FacMantissa1+1
    ldx #BYTE_EXPONENT
    ; Falls into ConvertSignedWord.
.endproc

;; Floats the signed 16-bit number in <FacMantissa1> and <FacMantissa1>+1, high byte first, into <Fac>.
;; In: X = the exponent: <Float::WORD_EXPONENT> for an integer
;; Also: FLOATS (BB13)
.proc ConvertSignedWord
    lda FacMantissa1
    eor #$FF
    rol a                                   ; the carry is set for positive
    ; Falls into ConvertWord.
.endproc

;; Floats the number in <FacMantissa1> and <FacMantissa1>+1 into <Fac>, negating it when the carry is clear.
;; In: X = the exponent, carry = set for a positive number
;; See: <Float::NormalizeSigned>
;; Also: FLOATC (BB13)
.proc ConvertWord
    lda #0
    sta FacMantissa4
    sta FacMantissa3
    stx FacExponent
    sta FacExtension
    sta FacSign
    jmp NormalizeSigned
.endproc

.endscope

; The ABS function.
.scope Functions continued

;; Gives `ABS`, making <Fac> positive.
;; Keeps: A, X, Y
;; Also: ABS (BB13)
.proc Abs
    lsr FacSign
    rts
.endproc

.endscope

; Floating point, part two: comparison and the integer part.
.scope Float continued

; ---------------------------------------------------------------------------------------------------------------------
; Comparison
; ---------------------------------------------------------------------------------------------------------------------

;; How many bits two reals must match in, plus one, to count as equal: <Float::CompareArgWithin> takes it here.
MatchBits = KeptY

;; The bits the relational operators compare in, plus one: a 24-bit mantissa, a variable's.
RELATION_MATCH_BITS = 25

;; The bits <Float::Compare> compares in, plus one: a 32-bit mantissa, a constant's.
PACKED_MATCH_BITS = 33

;; Compares <ArgExponent> with <Fac>, taking them as equal when they match to 24 bits.
;;
;; It subtracts the <Fac> from <ArgExponent> and calls them equal when the difference's exponent is at least 25 below the
;; <Fac>'s. The <Fac> is kept, but <ArgExponent> and <FacExtension> are not.
;; Out: A = 1 when <ArgExponent> is less, 0 when equal, $FF when <ArgExponent> is greater
;; Uses: KIMY, TEMP
;; See: <Float::Compare>
;; Also: FCOMPARG (BB13)
.proc CompareArg
    lda #RELATION_MATCH_BITS
    sta MatchBits
    ; Falls into CompareArgWithin.
.endproc

;; Compares <ArgExponent> with <Fac>, as <Float::CompareArg> does, with <Float::MatchBits> bits that must match.
;; In: MatchBits = the bits that must match, plus one
;; Out: A = 1 when <ArgExponent> is less, 0 when equal, $FF when <ArgExponent> is greater
;; Uses: TEMP
;; Also: FCOMPA1 (BB13)
.proc CompareArgWithin

;; The difference's exponent.
DifferenceExponent = Temporary

    lda FacSign
    eor ArgSign
    bmi GetSign::FromSignByte               ; the signs differ: the FAC's sign is the answer
    ldx #UNPACKED_SIZE - 1

;; Saves <Fac> on the stack.
;; Also: PHFAC34 (BB13)
SaveFac:
    lda Fac,x
    pha
    dex
    bpl SaveFac
    jsr SubtractFromArg
    ldy FacSign                              ; the difference's sign
    lda FacExponent
    sta DifferenceExponent
    ldx #$100-UNPACKED_SIZE

;; Restores <Fac> from the stack.
;; Also: PHFAC35 (BB13)
RestoreFac:
    pla
    sta Fac+UNPACKED_SIZE,x                 ; FAC to FAC+5, as zero page wraps
    inx
    bne RestoreFac
    lda DifferenceExponent
    beq Equal                               ; no difference
    lda FacExponent
    sec
    sbc DifferenceExponent
    bcc Unequal                             ; the difference is larger than the FAC
    cmp MatchBits
    bcs Equal                               ; so small it counts as none

;; Gives the result by the difference's sign.
;; In: Y = the difference's sign
;; Also: NTEQU36 (BB13)
Unequal:
    tya
    eor #$FF
    jmp GetSign::FromBit7

;; Gives 0, equal.
;; Also: ISEQU37 (BB13)
Equal:
    lda #0
    rts
.endproc

;; Compares a five-byte real in BASIC's own bank, at <Pointer2>'s low byte and the page in Y, with <Fac>, for `NEXT`.
;; In: Y = the page, 1 for a `FOR` entry on the stack
;; See: <Float::Compare>
;; Also: FCOMPN (BB13)
.proc CompareAtPointer2
    lda Pointer2
    ldx #0                                  ; BASIC's own bank
    ; Falls into Compare.
.endproc

;; Compares the real at A, Y with <Fac>, taking them as equal when they match to 32 bits.
;; In: A = the real's address, low byte, Y = its high byte, X = its bank, 0 for BASIC's own
;; Out: A = 1 when the real is less, 0 when equal, $FF when it is greater
;; Uses: KIMY, TEMP
;; See: <Float::CompareArg>, <Float::LoadArg>
;; Also: FCOMP (BB13)
.proc Compare
    jsr LoadArg
    lda #PACKED_MATCH_BITS
    sta MatchBits
    jmp CompareArgWithin
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Integer part
; ---------------------------------------------------------------------------------------------------------------------

;; Turns <Fac> into a signed 32-bit integer in <FacMantissa1>, <FacMantissa2>, <FacMantissa3> and <FacMantissa4>, high byte first: the greatest
;; integer not above it.
;;
;; A negative number is negated into two's complement first, then shifted with ones coming in from the left. The
;; <Fac> must be below 2^31 in size, an exponent below <Float::LONG_INTEGER_EXPONENT>: a larger one isn't checked, and
;; gives a wrong result. The exponent and sign are left as they were. The routine goes on in B3FinpM.asm.
;; Out: Y = 0
;; Uses: BITS
;; See: <Functions::Int>, <Float::ShiftRightFilled>
;; Also: QINT (BB13)
.proc ToLongInteger
    lda #0
    sta ShiftFill                                ; zeros come in for a positive number
    lda FacExponent
    beq ClearMantissa
    sec
    sbc #LONG_INTEGER_EXPONENT              ; minus the bits to shift
    bit FacSign
    bpl Shift
    tax
    lda #$FF
    sta ShiftFill                                ; ones come in for a negative number
    jsr ComplementMantissa
    txa

;; Shifts the integer into place: eight bits or more with <Float::ShiftRightFilled>, which shifts whole bytes first,
;; fewer with <Float::ToLongInteger::ShortShift>.
;; Also: QISHFT (BB13)
Shift:
    ldx #Fac
    cmp #$100-7
    bpl ShortShift
