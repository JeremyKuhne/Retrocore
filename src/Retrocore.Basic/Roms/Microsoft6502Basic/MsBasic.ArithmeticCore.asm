; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

;; Emits the five-byte multiplication, division and decimal scaling routines.
;; Parameters: shortZeroBranch = 1 to branch directly from <Float::MultiplyArg> to <Float::MultiplyByte::Done>, 0 for
;;   the long jump
.macro FloatArithmetic shortZeroBranch

    .assert shortZeroBranch = 0 || shortZeroBranch = 1, "shortZeroBranch is 0 or 1."

    ; Multiplication, unpacking and exponent handling.

    .scope Float continued

    ;; Multiplies <Fac> by a packed number and leaves the product in <Fac>.
    ;;
    ;; Each multiplier byte is shifted through the result, adding the argument accumulator when a multiplier bit is set.
    ;; In: A = low byte of packed operand address, Y = high byte of packed operand address
    ;; See: <Float::CombineExponents>, <Float::NormalizeResult>
    ;; Also: FMULT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc MultiplyPacked
    jsr LoadArg
    ; Falls into MultiplyArg.
    .endproc

    ;; Multiplies the unpacked argument accumulator by <Fac>, with zero set from <FacExponent> and <ResultSign> already
    ;; set.
    ;; Also: FMULTT (M6502, ASTIL, HV1, HV1R, HV2, HV4, HV4R, CBM4S79)
    .proc MultiplyArg
    .if shortZeroBranch
        beq MultiplyByte::Done
    .else
        bne *+5                         ; skip the return jump when <Fac> is nonzero
        jmp MultiplyByte::Done
    .endif
    jsr CombineExponents
    lda #$00
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
    jsr MultiplyByte::NonZero
    jmp NormalizeResult
    .endproc

    ;; Accumulates one byte of the multiplier, shifting the partial product right.
    ;; In: A = multiplier byte
    ;; Entry:
    ;;   NonZero = skips the zero test, for a byte that is never zero
    ;;   Done = The shared rts
    ;; Also: MLTPLY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc MultiplyByte
    bne *+5                         ; a zero byte takes the whole-byte shift
    jmp ShiftProductByte

;; Shifts the first multiplier bit into carry and sets bit 7 as a marker, which ends the loop when it shifts out.
;; Also: MLTPL1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NonZero:
    lsr a
    ora #$80

;; Carry set: adds Arg's mantissa to <Result1> through <Result4>.
;; Also: MLTPL2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextBit:
    tay
    bcc Shift                      ; add ARG only for a set multiplier bit
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

;; Rotates <Result1> through <Result4> and <FacExtension> right; loops until only the marker bit has gone.
;; Also: MLTPL3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Shift:
    ror Result1
    ror Result2
    ror Result3
    ror Result4
    ror FacExtension
    tya
    lsr a
    bne NextBit

;; The shared rts.
;; Also: MULTRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Unpacks a five-byte memory operand into the argument accumulator and sets the relative sign in <ResultSign>.
    ;; In: A = low byte of packed operand address, Y = high byte of packed operand address
    ;; Out: A = exponent of <Fac>, zero = set when <Fac> is zero
    ;; See: <Float::LoadFac>
    ;; Also: CONUPK (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc LoadArg
    sta Pointer1
    sty Pointer1+1
    ldy #$04
    lda (Pointer1),y
    sta ArgMantissa4
    dey
    lda (Pointer1),y
    sta ArgMantissa3
    dey
    lda (Pointer1),y
    sta ArgMantissa2
    dey
    lda (Pointer1),y
    sta ArgSign
    eor FacSign
    sta ResultSign
    lda ArgSign
    ora #$80
    sta ArgMantissa1
    dey
    lda (Pointer1),y
    sta ArgExponent
    lda FacExponent
    rts
    .endproc

    ;; Combines the exponents and signs for multiplication or division.
    ;;
    ;; A zero operand or exponent underflow discards the caller's return address and returns zero from the arithmetic
    ;; operation. Overflow goes to <Float::OverflowError>.
    ;; Also: MULDIV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CombineExponents
    lda ArgExponent
    ; Falls into AddExponent.
    .endproc

    ;; Uses the exponent already in A.
    ;; Also: MLDEXP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddExponent
    beq Underflow
    clc
    adc FacExponent
    bcc NoCarry
    bmi ToOverflowError
    clc
    .byte $2C                       ; BIT absolute skips the BPL and its displacement

;; No carry from the add: a sum under $80 underflows; otherwise rebiases and stores the exponent.
;; Also: TRYOFF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NoCarry:
    bpl Underflow
    adc #$80
    sta FacExponent
    bne *+5
    jmp SetSign
    lda ResultSign
    sta FacSign
    rts
    .endproc

    ;; Handles an exceptional exponent in <Functions::Exp>, choosing overflow or zero from the sign of <Fac>.
    ;; Also: MLDVEX (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ExponentOutOfRange
    lda FacSign
    eor #$FF
    bmi ToOverflowError
    .endproc

    ;; Drops the caller's return address and sets <Fac> to zero, so the caller's caller gets zero.
    ;; Also: ZEREMV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Underflow
    pla
    pla
    jmp SetZero
    .endproc

    ;; Jumps on to <Float::OverflowError>.
    ;; Also: GOOVER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ToOverflowError
    jmp OverflowError
    .endproc

    ;; Multiplies <Fac> by ten, using an addition and exponent adjustments.
    ;; Errors: overflow = jumps to <Float::OverflowError> if the exponent wraps
    ;; Also: MUL10 (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc MultiplyByTen
    jsr CopyFacToArg
    tax
    beq AddScaledArgAndDouble::Done
    clc
    adc #$02
    bcs ToOverflowError
    ; Falls into AddScaledArgAndDouble.
    .endproc

    ;; Adds the argument accumulator, scaled by A as its exponent, to <Fac> through <Float::AlignAndAdd> with
    ;; <ResultSign> cleared, then doubles the sum (exponent + 1); overflow is an error. From <Float::MultiplyByTen>,
    ;; A is the copy's exponent plus 2, so the sum is five times <Fac> and the result ten times.
    ;; In: A = the exponent to give the argument accumulator's mantissa
    ;; Entry:
    ;;   Done = The shared rts
    ;; Also: FINML6 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddScaledArgAndDouble
    ldx #$00
    stx ResultSign
    jsr AlignAndAdd
    inc FacExponent
    beq ToOverflowError

;; The shared rts.
;; Also: MUL10R (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

;; Packed floating-point constant ten.
;; Also: TENZC (M6502)
Ten:
    .byte $84, $20, $00, $00, $00

    ; Division and decimal scaling.

    ;; Divides <Fac> by ten.
    ;; See: <Float::DivideArgByPacked>, <Float::Ten>
    ;; Also: DIV10 (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc DivideByTen
    jsr CopyFacToArg
    lda #<Ten
    ldy #>Ten
    ldx #$00
    ; Falls into DivideArgByPacked.
    .endproc

    ;; Divides the unpacked argument accumulator by the packed number at Y:A.
    ;; In: A = low byte of divisor address, Y = high byte of divisor address, X = relative sign
    ;; Also: FDIVF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc DivideArgByPacked
    stx ResultSign
    jsr LoadFac
    jmp DivideArg
    .endproc

    ;; Divides a packed number by <Fac> and leaves the quotient in <Fac>.
    ;;
    ;; The divisor is rounded, then repeated comparisons and subtractions build the quotient a bit at a time.
    ;; In: A = low byte of packed dividend address, Y = high byte of packed dividend address
    ;; Errors: divide by zero = jumps to <ERROR>, overflow = jumps to <Float::OverflowError>
    ;; Also: FDIV (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc DividePacked
    jsr LoadArg
    ; Falls into DivideArg.
    .endproc

    ;; Divides the unpacked argument accumulator by <Fac>, with zero set from <FacExponent> and <ResultSign> already
    ;; set.
    ;; Also: FDIVT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc DivideArg
    beq DivisionByZero
    jsr Round
    lda #$00
    sec
    sbc FacExponent
    sta FacExponent
    jsr CombineExponents
    inc FacExponent
    beq ToOverflowError
    ldx #$FC
    lda #$01

;; Builds quotient bits by comparing and subtracting the divisor from the argument accumulator.
;; Also: DIVIDE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Compare:
    ; Compare the remaining dividend with the divisor, most significant byte first.
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

;; Rotates the comparison's carry into the quotient byte; each full byte is stored in <Result1> through <Result4>.
;; After the fourth it goes on to <Float::DivideArg::LastBits>, and the partial fifth to <Float::DivideArg::Finish>.
;; Also: SAVQUO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SaveBit:
    php
    rol a
    bcc TestSubtract
    inx
    sta Result4,x
    beq LastBits
    bpl Finish
    lda #$01

;; Restores the comparison's flags: Arg >= <Fac> subtracts.
;; Also: QSHFT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestSubtract:
    plp
    bcs Subtract

;; Shifts Arg left one bit and compares again (a carry out means it is larger).
;; Also: SHFARG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ShiftDividend:
    asl ArgMantissa4
    rol ArgMantissa3
    rol ArgMantissa2
    rol ArgMantissa1
    bcs SaveBit
    bmi Compare
    bpl SaveBit

;; Subtracts <Fac>'s mantissa from Arg's, then shifts.
;; Also: DIVSUB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Subtract:
    ; A quotient bit was set: subtract the divisor, then shift the remainder.
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

;; After four quotient bytes, sets A to $40 to collect two more bits.
;; Also: LD100 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LastBits:
    lda #$40
    bne TestSubtract

;; Moves the two extra bits to the top of <FacExtension> and normalizes the quotient (<Float::NormalizeResult>).
;; Also: DIVNRM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Finish:
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta FacExtension
    plp
    jmp NormalizeResult

;; Reports division by zero through <ERROR>.
;; Also: DV0ERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DivisionByZero:
    ldx #ERROR_DIVISION_BY_ZERO
    jmp ERROR
    .endproc
    .endscope

.endmacro
