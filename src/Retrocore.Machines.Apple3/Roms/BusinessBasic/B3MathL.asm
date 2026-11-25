; retrocore: style=strict
;; Business BASIC's floating point, part two (Apple's B3MATHL): `LOG`, multiplication and division, the routines that
;; move reals between <FAC>, <ARG> and memory, rounding, `SGN` and `ABS`, comparison, and the start of
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
;; See: <POLYX>
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

;; Gives `LOG`, the natural logarithm of <FAC>.
;;
;; For a <FAC> of f times 2^n, with f from 0.5 to 1, it works out the base-2 logarithm of f from a polynomial in
;; `(f - SQR(0.5)) / (f + SQR(0.5))`, adds n and multiplies by the logarithm of 2. A <FAC> of zero or less is an illegal
;; quantity.
;; Errors: ILLEGAL QUANTITY = the <FAC> is zero or negative
;; See: <Float::LogPolynomial>, <POLYX>, <Float::AddSignedByte>
;; Also: LOG (BB13)
.proc Log
    jsr Float::GetSign
    beq ToIllegalQuantity
    bpl Reduce

;; Ends the statement with ILLEGAL QUANTITY.
;; Also: LOGERR (BB13)
ToIllegalQuantity:
    jmp FCERR

;; Takes the logarithm of a positive <FAC>: keeps its exponent as n and makes it a fraction from 0.5 to 1.
;; Also: LOG1 (BB13)
Reduce:
    lda FACEXP
    sbc #Float::EXPONENT_BIAS - 1           ; the carry is clear: less the bias
    pha                                     ; n
    lda #Float::EXPONENT_BIAS
    sta FACEXP                              ; f, from 0.5 to 1
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
    jsr POLYX
    lda #<(Float::MinusHalf)
    ldy #>(Float::MinusHalf)
    jsr Float::AddPacked
    pla
    jsr Float::AddSignedByte                ; add n
    lda #<(Float::LogOfTwo)
    ldy #>(Float::LogOfTwo)
    ldx #SQR0B                              ; left over: MultiplyPacked sets X itself
    ; Falls into Float::MultiplyPacked.
.endproc

.endscope

; Floating point, part two: multiplication, division, moves, signs and comparison.
.scope Float continued

; ---------------------------------------------------------------------------------------------------------------------
; Multiplication
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies <FAC> by the five-byte real at A, Y.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::MultiplyArg>, <Float::LoadArg>
;; Also: FMULT (BB13)
.proc MultiplyPacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into MultiplyArg.
.endproc

;; Multiplies <FAC> by <ARG>, into the <FAC>: <ARG>'s mantissa times each byte of the <FAC>'s, the rounding byte first,
;; summed in <RES>.
;; In: A = <FACEXP>, zero = set for a zero <FAC>, ARISGN = the product's sign
;; See: <Float::CombineExponents>, <Float::MultiplyByte>, <Float::NormalizeResult>
;; Also: FMULTT (BB13)
.proc MultiplyArg
    bne *+5                                 ; skip the jump for a FAC that is not zero
    jmp MultiplyByte::Done                  ; a zero FAC is the product
    jsr CombineExponents
    lda #0
    sta RESHO
    sta RESMOH
    sta RESMO
    sta RESLO
    lda FACOV
    jsr MultiplyByte
    lda FACLO
    jsr MultiplyByte
    lda FACMO
    jsr MultiplyByte
    lda FACMOH
    jsr MultiplyByte
    lda FACHO
    jsr MultiplyByte::NonZero               ; the high byte is never zero
    jmp NormalizeResult
.endproc

;; Adds <ARG> times the multiplier byte in A into <RES>, shifting <RES> right a bit for each of its bits; a zero byte
;; just shifts <RES> a byte.
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

;; Adds <ARG> to <RES> when the bit shifted out is set.
;; In: carry = the bit, A = the bits left
;; Also: MLTPL2 (BB13)
NextBit:
    tay
    bcc Shift
    clc
    lda RESLO
    adc ARGLO
    sta RESLO
    lda RESMO
    adc ARGMO
    sta RESMO
    lda RESMOH
    adc ARGMOH
    sta RESMOH
    lda RESHO
    adc ARGHO
    sta RESHO

;; Shifts <RES> right a bit, into <FACOV>, and goes on while bits are left.
;; Also: MLTPL3 (BB13)
Shift:
    ror RESHO
    ror RESMOH
    ror RESMO
    ror RESLO
    ror FACOV
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

;; Unpacks a real from memory into <ARG>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A = the real's address, low byte, Y = its high byte, X = its bank, 0 for BASIC's own
;; Out: ARG = the real, ARISGN = <ARG>'s sign exclusive-ored with the <FAC>'s, A = <FACEXP>,
;;   zero = set for a zero <FAC>, Y = 0
;; Uses: INDEX1
;; Keeps: X
;; See: <Float::LoadFac>
;; Also: CONUPK (BB13)
.proc LoadArg
    sta INDEX1
    stx INDEX1B
    sty INDEX1+1
    ldy #CONSTANT_SIZE - 1
    lda (INDEX1),y
    cpx #0
    beq *+4                                 ; BASIC's own bank: keep the fifth byte
    lda #0                                  ; a variable: no fifth byte
    sta ARGLO
    dey
    lda (INDEX1),y
    sta ARGMO
    dey
    lda (INDEX1),y
    sta ARGMOH
    dey
    lda (INDEX1),y
    sta ARGSGN                              ; the sign is the top bit
    eor FACSGN
    sta ARISGN
    lda ARGSGN
    ora #$80                                ; the implied 1
    sta ARGHO
    dey
    lda (INDEX1),y
    sta ARGEXP
    lda FACEXP
    rts
.endproc

;; Adds <ARG>'s exponent to <FAC>'s for a multiplication or division, and sets the result's sign.
;;
;; A zero <ARG>, or a result too small to hold, makes the <FAC> zero and returns from the routine that called this
;; one; a result too large ends the statement with OVERFLOW. A result exponent of exactly 0 makes the <FAC> zero, its
;; sign too, and returns to the caller.
;; Out: FACEXP = the sum, less the bias, FACSGN = <ARISGN>
;; See: <Float::AddExponent>
;; Also: MULDIV (BB13)
.proc CombineExponents
    lda ARGEXP
    ; Falls into AddExponent.
.endproc

;; Adds the exponent in A to <FAC>'s, as <Float::CombineExponents> does.
;; In: A = the exponent
;; Also: MLDEXP (BB13)
.proc AddExponent
    beq Underflow                           ; times zero
    clc
    adc FACEXP
    bcc NoCarry
    bmi ToOverflowError                     ; past $17F: too large
    clc
    .byte $2C                               ; BIT absolute, which skips NoCarry's BPL

;; Takes a sum with no carry: below $80 is too small; otherwise takes off the bias.
;; Also: TRYOFF (BB13)
NoCarry:
    bpl Underflow
    adc #EXPONENT_BIAS
    sta FACEXP
    bne *+5                                 ; skip the jump for an exponent that is not zero
    jmp SetSign                             ; zero: the sign is 0 too
    lda ARISGN
    sta FACSGN
    rts
.endproc

;; For a result whose exponent is out of range: too large when <FAC> is positive, and zero when it is negative.
;; See: <EXP>
;; Also: MLDVEX (BB13)
.proc ExponentOutOfRange
    lda FACSGN
    eor #$FF
    bmi ToOverflowError
    ; Falls into Underflow.
.endproc

;; Makes <FAC> zero and returns from the routine that called the exponent check.
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

;; Multiplies <FAC> by 10: four times itself, plus itself, doubled.
;; Out: ARG = the <FAC> as it was, rounded
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
    stx ARISGN
    jsr AlignAndAdd                         ; plus itself
    inc FACEXP                              ; doubled
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

;; Divides <FAC> by 10.
;;
;; The quotient is positive whatever the <FAC>'s sign: <Float::ReadNumber> and <Float::FormatFac>, which use it, work on
;; a positive number and set the sign themselves.
;; Also: DIV10 (BB13)
.proc DivideByTen
    jsr CopyFacToArg
    lda #<(Ten)
    ldy #>(Ten)
    ldx #0                                  ; the quotient's sign
    ; Falls into DivideArgByPacked.
.endproc

;; Divides <ARG> by the five-byte real at A, Y, giving the quotient the sign in X.
;; In: A = the divisor's address, low byte, Y = its high byte, in BASIC's own bank, X = the quotient's sign
;; Also: FDIVF (BB13)
.proc DivideArgByPacked
    stx ARISGN
    ldx #TEN_CB
    jsr LoadFac
    jmp DivideArg
.endproc

;; Divides the five-byte real at A, Y by <FAC>, into the <FAC>.
;; In: A = the real's address, low byte, Y = its high byte, in BASIC's own bank
;; See: <Float::DivideArg>, <Float::LoadArg>
;; Also: FDIV (BB13)
.proc DividePacked
    ldx #0                                  ; BASIC's own bank
    jsr LoadArg
    ; Falls into DivideArg.
.endproc

;; Divides <ARG> by <FAC>, into the <FAC>, a bit of the quotient at a time; a zero <FAC> ends the statement with
;; DIVISION BY ZERO.
;; In: A = <FACEXP>, zero = set for a zero <FAC>, ARISGN = the quotient's sign
;; Errors: DIVISION BY ZERO = the <FAC> is zero, OVERFLOW = the quotient is too large
;; See: <Float::CombineExponents>, <Float::NormalizeResult>
;; Also: FDIVT (BB13)
.proc DivideArg
    bne NotZero
    jmp DivisionByZero

;; Divides by a <FAC> that is not zero: rounds it, subtracts its exponent from <ARG>'s, and sets the marker bit that
;; counts each quotient byte's eight bits.
;; Also: NO0ERR (BB13)
NotZero:
    jsr Round
    lda #0                                  ; negate the FAC's exponent, so CombineExponents subtracts it
    sec
    sbc FACEXP
    sta FACEXP
    jsr CombineExponents
    inc FACEXP
    beq ToOverflowError
    ldx #$100-3-1                           ; RES's bytes, from RESHO
    lda #1                                  ; a marker bit, to count eight bits

;; Compares <ARG>'s mantissa with <FAC>'s, the divisor.
;; Also: DIVIDE (BB13)
Compare:
    ldy ARGHO
    cpy FACHO
    bne SaveBit
    ldy ARGMOH
    cpy FACMOH
    bne SaveBit
    ldy ARGMO
    cpy FACMO
    bne SaveBit
    ldy ARGLO
    cpy FACLO

;; Shifts the comparison's result, as the next bit of the quotient, into A; each full byte goes to <RES>, and the last
;; two bits to <FACOV>.
;; In: carry = set when the divisor goes into <ARG>
;; Also: SAVQUO (BB13)
SaveBit:
    php
    rol a
    bcc TestSubtract                        ; the byte is not full yet
    inx
    sta RESLO,x
    beq LastBits                            ; RESLO is done: two more bits
    bpl Finish                              ; the two more bits are done
    lda #1

;; Subtracts the divisor when it went into <ARG>, then shifts <ARG> left a bit.
;; Also: QSHFT (BB13)
TestSubtract:
    plp
    bcs Subtract

;; Shifts <ARG> left a bit, then compares again; a bit carried out of <ARG>'s top means the divisor goes in, and a clear
;; top bit that it does not.
;; Also: SHFARG (BB13)
ShiftDividend:
    asl ARGLO
    rol ARGMO
    rol ARGMOH
    rol ARGHO
    bcs SaveBit
    bmi Compare
    bpl SaveBit

;; Subtracts the divisor from <ARG>.
;; In: carry = set
;; Also: DIVSUB (BB13)
Subtract:
    tay
    lda ARGLO
    sbc FACLO
    sta ARGLO
    lda ARGMO
    sbc FACMO
    sta ARGMO
    lda ARGMOH
    sbc FACMOH
    sta ARGMOH
    lda ARGHO
    sbc FACHO
    sta ARGHO
    tya
    jmp ShiftDividend

;; Sets the marker bit for the last two bits of the quotient.
;; Also: LD100 (BB13)
LastBits:
    lda #$40
    bne TestSubtract                        ; always

;; Puts the last two bits of the quotient at the top of <FACOV>, then moves the quotient into <FAC>.
;; Also: DIVNRM (BB13)
Finish:
    ror a
    ror a
    ror a
    and #$C0
    sta FACOV
    plp
    jmp NormalizeResult

;; Ends the statement with DIVISION BY ZERO, through <ERROR>.
;; Also: DV0ERR (BB13)
DivisionByZero:
    ldx #ERRDV0
    jmp ERROR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Moving reals
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the result of a multiplication or division, <RES>, into <FAC>'s mantissa and normalizes it.
;; See: <Float::Normalize>
;; Also: MOVFR (BB13)
.proc NormalizeResult
    lda RESHO
    sta FACHO
    lda RESMOH
    sta FACMOH
    lda RESMO
    sta FACMO
    lda RESLO
    sta FACLO
    jmp Normalize
.endproc

;; Unpacks a real from memory into <FAC>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A = the real's address, low byte, Y = its high byte, X = its bank, 0 for BASIC's own
;; Out: A = <FACEXP>, zero = set for a zero <FAC>, FACOV = 0, Y = 0
;; Uses: INDEX1
;; Keeps: X
;; Also: MOVFM (BB13)
.proc LoadFac
    sta INDEX1
    stx INDEXB
    sty INDEX1+1
    ldy #CONSTANT_SIZE - 1
    lda #0
    cpx #0
    bne *+4                                 ; a variable: no fifth byte
    lda (INDEX),y
    sta FACLO
    dey
    lda (INDEX1),y
    sta FACMO
    dey
    lda (INDEX1),y
    sta FACMOH
    dey
    lda (INDEX1),y
    sta FACSGN                              ; the sign is the top bit
    ora #$80                                ; the implied 1
    sta FACHO
    dey
    lda (INDEX1),y
    sta FACEXP
    sty FACOV
    rts
.endproc

;; Packs <FAC> into <TEMPF2>, five bytes.
;; See: <Float::StoreFac>
;; Also: MOV2F (BB13)
.proc StoreFacInTemporary2
    ldx #TEMPF2
    .byte $2C                               ; BIT absolute, which skips StoreFacInTemporary1's LDX
    ; Falls into StoreFacInTemporary1.
.endproc

;; Packs <FAC> into <TEMPF1>, five bytes.
;; See: <Float::StoreFac>
;; Also: MOV1F (BB13)
.proc StoreFacInTemporary1
    ldx #TEMPF1
    ldy #0
    tya                                     ; BASIC's own bank
    beq StoreFac                            ; always
.endproc

;; Packs <FAC> into the variable <FORPNT> points to.
;; See: <Float::StoreFac>
;; Also: MOVVF (BB13)
.proc StoreFacInVariable
    ldx FORPNT
    lda FORPNTB
    ldy FORPNT+1
    ; Falls into StoreFac.
.endproc

;; Rounds <FAC> and packs it into memory: five bytes in BASIC's own bank, or a variable's four, rounded to three
;; mantissa bytes, in another.
;;
;; In BASIC's own bank the fifth byte is stored and the variable's rounding skipped, except that a fifth byte of zero
;; doesn't skip it: <Float::RoundForVariable> then rounds once more by the next bit of <FACOV>, which can only make
;; <FACLO> 1, and clears <FACLO> again, so the bytes stored are the same.
;; In: X = the address, low byte, Y = its high byte, A = the bank, 0 for BASIC's own
;; Out: X = the bank, Y = 0, FACOV = 0
;; Uses: INDEX1
;; Entry:
;;   AtPointer = stores at the address and bank already in <INDEX1> and its X-byte, with the bank in A as well
;; See: <Float::Round>, <Float::RoundForVariable>
;; Also: MOVMF (BB13)
.proc StoreFac
    stx INDEX1
    sty INDEX1+1
    sta INDEX1B

;; Stores <FAC>'s five or four bytes at <INDEX1>.
;; In: A = the bank
;; Also: FOURBYT (BB13)
AtPointer:
    ldy #CONSTANT_SIZE - 1
    tax
    bne ToVariable                          ; a variable
    jsr Round
    lda FACLO
    sta (INDEX),y                           ; the fifth byte
    bne *+5                                 ; skip ToVariable's rounding (not for a fifth byte of zero)

;; Rounds <FAC> to a variable's three mantissa bytes, then stores the first four bytes.
;; Also: FURBYT (BB13)
ToVariable:
    jsr RoundForVariable
    dey
    lda FACMO
    sta (INDEX),y
    dey
    lda FACMOH
    sta (INDEX),y
    dey
    lda FACSGN                              ; the sign, in place of the implied 1
    ora #$7F
    and FACHO
    sta (INDEX),y
    dey
    lda FACEXP
    sta (INDEX),y
    sty FACOV
    rts
.endproc

;; Rounds <FAC> to the three mantissa bytes a variable keeps, to the nearest, a half to even, and clears <FACLO>.
;; Out: FACLO = 0
;; Keeps: X, Y
;; See: <Float::Round>
;; Also: ROUNDER (BB13)
.proc RoundForVariable
    jsr Round
    lda FACLO
    bpl ClearLow                            ; below a half: down
    asl a
    sta TEMP
    lda FACMO
    and #1
    ora TEMP                                ; above a half, or a half with FACMO odd: up
    beq ClearLow
    lda #$FF
    sta FACLO                               ; so that adding one carries into FACMO
    jsr Round::Increment

;; Clears <FACLO>.
;; Also: RONDRTS (BB13)
ClearLow:
    lda #0
    sta FACLO
    rts
.endproc

;; Moves <ARG> into <FAC>.
;; Out: X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVFA (BB13)
.proc CopyArgToFac
    lda ARGSGN
    ; Falls into CopyArgToFacWithSign.
.endproc

;; Moves <ARG>'s exponent and mantissa into <FAC>, with A as its sign.
;; In: A = the sign
;; Out: X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVFA1 (BB13)
.proc CopyArgToFacWithSign
    sta FACSGN
    ldx #UNPACKED_SIZE - 1                  ; the exponent and the mantissa

;; Moves a byte, from the lowest.
;; Also: MOVFAL (BB13)
Loop:
    lda ARGEXP-1,x
    sta FACEXP-1,x
    dex
    bne Loop
    stx FACOV
    rts
.endproc

;; Rounds <FAC> and copies it, with its sign, into <ARG>.
;; Out: A = <FACEXP>, X = 0, FACOV = 0
;; Keeps: Y
;; See: <Float::Round>
;; Also: MOVAF (BB13)
.proc CopyFacToArg
    jsr Round
    ; Falls into CopyFacToArgUnrounded.
.endproc

;; Copies <FAC>, with its sign, into <ARG> without rounding it.
;; Out: A = <FACEXP>, X = 0, FACOV = 0
;; Keeps: Y
;; Also: MOVEF (BB13)
.proc CopyFacToArgUnrounded
    ldx #UNPACKED_SIZE

;; Copies a byte, from the sign down.
;; Also: MOVAFL (BB13)
Loop:
    lda FACEXP-1,x
    sta ARGEXP-1,x
    dex
    bne Loop
    stx FACOV
    rts
.endproc

;; Rounds <FAC>'s mantissa by the top bit of <FACOV>, taking a carry out of the top into the exponent.
;; Uses: A
;; Keeps: X, Y
;; Entry:
;;   Increment = adds one to the mantissa, taking a carry out of the top into the exponent
;;   Done = returns
;; Also: ROUND (BB13)
.proc Round
    lda FACEXP
    beq Done                                ; zero
    asl FACOV
    bcc Done                                ; below a half

;; Adds one to <FAC>'s mantissa, taking a carry out of the top into the exponent.
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

;; Gives <FAC>'s sign.
;; Out: A = 0 for zero, 1 for positive, $FF for negative
;; Keeps: X, Y
;; Entry:
;;   FromSignByte = gives the sign of <FACSGN>, as a non-zero <FAC>'s, with carry = set for negative
;;   FromBit7 = gives 1 or $FF by the top bit of A, with carry = set for $FF
;;   Done = returns
;; Also: SIGN (BB13)
.proc GetSign
    lda FACEXP
    beq Done

;; Gives the sign of <FACSGN>, as a non-zero <FAC>'s.
;; Also: FCSIGN (BB13)
FromSignByte:
    lda FACSGN

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

;; Gives `SGN`, replacing <FAC> with its sign: -1, 0 or 1.
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

;; Floats the signed byte in A into <FAC>.
;; In: A = the byte
;; Also: FLOAT (BB13)
.proc ConvertSignedByte
    sta FACHO
    lda #0
    sta FACHO+1
    ldx #BYTE_EXPONENT
    ; Falls into ConvertSignedWord.
.endproc

;; Floats the signed 16-bit number in <FACHO> and <FACHO>+1, high byte first, into <FAC>.
;; In: X = the exponent: <Float::WORD_EXPONENT> for an integer
;; Also: FLOATS (BB13)
.proc ConvertSignedWord
    lda FACHO
    eor #$FF
    rol a                                   ; the carry is set for positive
    ; Falls into ConvertWord.
.endproc

;; Floats the number in <FACHO> and <FACHO>+1 into <FAC>, negating it when the carry is clear.
;; In: X = the exponent, carry = set for a positive number
;; See: <Float::NormalizeSigned>
;; Also: FLOATC (BB13)
.proc ConvertWord
    lda #0
    sta FACLO
    sta FACMO
    stx FACEXP
    sta FACOV
    sta FACSGN
    jmp NormalizeSigned
.endproc

.endscope

; The ABS function.
.scope Functions continued

;; Gives `ABS`, making <FAC> positive.
;; Keeps: A, X, Y
;; Also: ABS (BB13)
.proc Abs
    lsr FACSGN
    rts
.endproc

.endscope

; Floating point, part two: comparison and the integer part.
.scope Float continued

; ---------------------------------------------------------------------------------------------------------------------
; Comparison
; ---------------------------------------------------------------------------------------------------------------------

;; How many bits two reals must match in, plus one, to count as equal: <Float::CompareArgWithin> takes it here.
MatchBits = KIMY

;; The bits the relational operators compare in, plus one: a 24-bit mantissa, a variable's.
RELATION_MATCH_BITS = 25

;; The bits <Float::Compare> compares in, plus one: a 32-bit mantissa, a constant's.
PACKED_MATCH_BITS = 33

;; Compares <ARG> with <FAC>, taking them as equal when they match to 24 bits.
;;
;; It subtracts the <FAC> from <ARG> and calls them equal when the difference's exponent is at least 25 below the
;; <FAC>'s. The <FAC> is kept, but <ARG> and <FACOV> are not.
;; Out: A = 1 when <ARG> is less, 0 when equal, $FF when <ARG> is greater
;; Uses: KIMY, TEMP
;; See: <Float::Compare>
;; Also: FCOMPARG (BB13)
.proc CompareArg
    lda #RELATION_MATCH_BITS
    sta MatchBits
    ; Falls into CompareArgWithin.
.endproc

;; Compares <ARG> with <FAC>, as <Float::CompareArg> does, with <Float::MatchBits> bits that must match.
;; In: MatchBits = the bits that must match, plus one
;; Out: A = 1 when <ARG> is less, 0 when equal, $FF when <ARG> is greater
;; Uses: TEMP
;; Also: FCOMPA1 (BB13)
.proc CompareArgWithin

;; The difference's exponent.
DifferenceExponent = TEMP

    lda FACSGN
    eor ARGSGN
    bmi GetSign::FromSignByte               ; the signs differ: the FAC's sign is the answer
    ldx #UNPACKED_SIZE - 1

;; Saves <FAC> on the stack.
;; Also: PHFAC34 (BB13)
SaveFac:
    lda FAC,x
    pha
    dex
    bpl SaveFac
    jsr SubtractFromArg
    ldy FACSGN                              ; the difference's sign
    lda FACEXP
    sta DifferenceExponent
    ldx #$100-UNPACKED_SIZE

;; Restores <FAC> from the stack.
;; Also: PHFAC35 (BB13)
RestoreFac:
    pla
    sta FAC+UNPACKED_SIZE,x                 ; FAC to FAC+5, as zero page wraps
    inx
    bne RestoreFac
    lda DifferenceExponent
    beq Equal                               ; no difference
    lda FACEXP
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

;; Compares a five-byte real in BASIC's own bank, at <INDEX2>'s low byte and the page in Y, with <FAC>, for `NEXT`.
;; In: Y = the page, 1 for a `FOR` entry on the stack
;; See: <Float::Compare>
;; Also: FCOMPN (BB13)
.proc CompareAtPointer2
    lda INDEX2
    ldx #0                                  ; BASIC's own bank
    ; Falls into Compare.
.endproc

;; Compares the real at A, Y with <FAC>, taking them as equal when they match to 32 bits.
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

;; Turns <FAC> into a signed 32-bit integer in <FACHO>, <FACMOH>, <FACMO> and <FACLO>, high byte first: the greatest
;; integer not above it.
;;
;; A negative number is negated into two's complement first, then shifted with ones coming in from the left. The
;; <FAC> must be below 2^31 in size, an exponent below <Float::LONG_INTEGER_EXPONENT>: a larger one isn't checked, and
;; gives a wrong result. The exponent and sign are left as they were. The routine goes on in B3FinpM.asm.
;; Out: Y = 0
;; Uses: BITS
;; See: <Functions::Int>, <Float::ShiftRightFilled>
;; Also: QINT (BB13)
.proc ToLongInteger
    lda #0
    sta BITS                                ; zeros come in for a positive number
    lda FACEXP
    beq ClearMantissa
    sec
    sbc #LONG_INTEGER_EXPONENT              ; minus the bits to shift
    bit FACSGN
    bpl Shift
    tax
    lda #$FF
    sta BITS                                ; ones come in for a negative number
    jsr ComplementMantissa
    txa

;; Shifts the integer into place: eight bits or more with <Float::ShiftRightFilled>, which shifts whole bytes first,
;; fewer with <Float::ToLongInteger::ShortShift>.
;; Also: QISHFT (BB13)
Shift:
    ldx #FAC
    cmp #$100-7
    bpl ShortShift
