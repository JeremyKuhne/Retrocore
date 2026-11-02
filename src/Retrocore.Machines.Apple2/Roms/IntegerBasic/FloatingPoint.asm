;; APPLE II FLOATING-POINT ROUTINES ($F425-$F4FF)
;;
;; Steve Wozniak and Roy Rankin's floating-point arithmetic, which shares the Integer BASIC chips; Integer BASIC
;; itself never calls it. It adds, subtracts, multiplies and divides 32-bit numbers, and converts 16-bit integers to
;; and from them. The last two routines, FIX1 and FIX, come after the Mini-Assembler, at $F63D (MiniAssembler.asm).
;;
;; A number is 4 bytes in page zero: an exponent, biased by $80 (so $80 means 2^0), then a 24-bit two's complement
;; mantissa, high byte first, with the binary point after its top two bits. A normalized mantissa has its top two
;; bits different, so its size is from 1 up to 2. There are two such accumulators: FP1 (X1 and M1, $F8-$FB), which
;; holds the result, and FP2 (X2 and M2, $F4-$F7). E ($FC-$FF) extends M1 while multiplying and dividing, and SIGN
;; counts the operands made positive for them.
;;
;; On overflow the routines jump to OVLOC ($03F5), where the program using them puts a JMP to its handler.
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978). Part of IntegerBasic.asm; it follows
;; Operators.asm, at $F425.

;; The sign count for multiplying and dividing: its low bit is set when one operand was negative.
;;
;; <MD1> shifts it left and <ABSWAP> adds 1 for each negative operand it makes positive; <MDEND> shifts the bit out
;; to decide whether to negate the result.
;; See: <MD1>, <MDEND>
SIGN = $F3

;; FP2's exponent, biased by $80.
;; See: <M2>, <X1>
X2 = $F4

;; FP2's mantissa (3 bytes, high byte first): the second operand.
;; See: <X2>, <M1>
M2 = $F5

;; FP1's exponent, biased by $80.
;; See: <M1>, <X2>
X1 = $F8

;; FP1's mantissa (3 bytes, high byte first): the first operand and the result.
;;
;; <FLOAT> takes a 16-bit integer here, high byte first, and <FIX> leaves one here.
;; See: <X1>, <M2>, <E>
M1 = $F9

;; The extension of <M1> (4 bytes): <SWAP> leaves a copy of a mantissa here, <FMUL> shifts the multiplier through it
;; and <FDIV> holds the divisor in it.
;; See: <SWAP>, <FMUL>, <FDIV>
E = $FC

;; Adds the mantissas: <M1> = <M1> + <M2>.
;; Out:   carry = the carry out of the high bytes, overflow = their signed overflow
;; Uses: A, X
ADD:
    clc                             ; $F425
    ldx #$02                        ; $F426

ADD1:
    lda M1,x                        ; $F428
    adc M2,x                        ; $F42A
    sta M1,x                        ; $F42C
    dex                             ; $F42E
    bpl ADD1                        ; $F42F
    rts                             ; $F431

;; Prepares for multiplying or dividing: makes both mantissas positive and counts the negative ones in <SIGN>.
;;
;; It calls <ABSWAP> for FP1, which swaps the accumulators, then falls into it for the other, which swaps them back.
;; Out: A = X2, carry set
;; Uses: X, Y, E
MD1:
    asl SIGN                        ; $F432
    jsr ABSWAP                      ; $F434

;; Makes <M1> positive, adding 1 to <SIGN> if it was negative, then swaps FP1 and FP2 with the carry set.
;; Entry: ABSWAP1 = the swap with the carry set
ABSWAP:
    bit M1                          ; $F437
    bpl ABSWAP1                     ; $F439
    jsr FCOMPL                      ; $F43B
    inc SIGN                        ; $F43E

ABSWAP1:
    sec                             ; $F440

;; Exchanges FP1 and FP2, leaving in <E> a copy of the mantissa that moves to <M1>.
;;
;; X counts 4 to 1: SIGN,X and M2+2,X reach X2 to M2+2 and X1 to M1+2. Each byte moving to FP1 is also stored, on
;; the next pass, at M1+2,X: E to E+2.
;; Out: A = the new X2, X = 0
;; Uses: Y
;; Keeps: carry
;; Entry: SWAP1 = the loop
SWAP:
    ldx #$04                        ; $F441

SWAP1:
    sty M1+2,x                      ; $F443
    lda M2+2,x                      ; $F445
    ldy SIGN,x                      ; $F447
    sty M2+2,x                      ; $F449
    sta SIGN,x                      ; $F44B
    dex                             ; $F44D
    bne SWAP1                       ; $F44E
    rts                             ; $F450

;; Converts the 16-bit integer in <M1> (high byte) and M1+1 to floating point in FP1.
;;
;; The exponent starts at 14 ($8E), the scale of an integer in the mantissa's top 16 bits; normalizing adjusts it.
;; M1+2 is taken as the fraction, 0 for a whole number.
;; In: M1, M1+1 = the integer
;; Out: X1/M1 = the number
FLOAT:
    lda #$8E                        ; $F451
    sta X1                          ; $F453

;; Normalizes FP1: shifts the mantissa left, one less in the exponent each time, until its top two bits differ or
;; the exponent reaches 0.
;; Entry: NORM = checks the exponent first
NORM1:
    lda M1                          ; $F455
    cmp #$C0                        ; $F457
    bmi RTS1                        ; $F459 normalized: the top two bits differ
    dec X1                          ; $F45B
    asl M1+2                        ; $F45D
    rol M1+1                        ; $F45F
    rol M1                          ; $F461

NORM:
    lda X1                          ; $F463
    bne NORM1                       ; $F465

;; The end of normalizing.
RTS1:
    rts                             ; $F467

;; Subtracts: FP1 = FP2 - FP1.
;;
;; It negates FP1 and adds.
;; See: <FADD>, <FCOMPL>
;; Entry: SWPALGN = aligns the operands, then adds
FSUB:
    jsr FCOMPL                      ; $F468

SWPALGN:
    jsr ALGNSWP                     ; $F46B

;; Adds: FP1 = FP1 + FP2.
;;
;; The operand with the smaller exponent is shifted right until the exponents agree (<ALGNSWP>), then the mantissas
;; are added and the sum normalized. An overflow of the sum is shifted back in from the right.
;; Errors: jumps to OVLOC on overflow
;; See: <FSUB>, <ADD>, <NORM>
FADD:
    lda X2                          ; $F46E
    cmp X1                          ; $F470
    bne SWPALGN                     ; $F472
    jsr ADD                         ; $F474

;; After adding: normalizes, or on overflow shifts the mantissa right with the carry as its sign.
ADDEND:
    bvc NORM                        ; $F477
    bvs RTLOG                       ; $F479

;; Aligns the operands for adding: swaps them if the carry is clear (FP2's exponent the smaller), otherwise shifts
;; FP1 right one place.
ALGNSWP:
    bcc SWAP                        ; $F47B

;; Shifts FP1 right one place, arithmetically: the sign stays.
;; Entry: RTLOG = shifts in the carry instead, RTLOG1 = shifts M1 and E without changing the exponent
RTAR:
    lda M1                          ; $F47D
    asl a                           ; $F47F

RTLOG:
    inc X1                          ; $F480
    beq OVFL                        ; $F482 the exponent has overflowed

RTLOG1:
    ldx #$FA                        ; $F484 6 bytes, $F9-$FE: M1 and the first three of E

ROR1:
    ror E+3,x                       ; $F486
    inx                             ; $F488
    bne ROR1                        ; $F489
    rts                             ; $F48B

;; Multiplies: FP1 = FP1 x FP2.
;;
;; The exponents are added (<MD2>). The multiplier, in E, is shifted right a bit at a time, and the multiplicand is
;; added into the product, in M1, when the bit is 1; the product shifts right with it. 24 steps give the top 24
;; bits of the product, which is negated if one operand was negative.
;; Errors: jumps to OVLOC on overflow
;; See: <MD1>, <MD2>, <MDEND>
FMUL:
    jsr MD1                         ; $F48C
    adc X1                          ; $F48F
    jsr MD2                         ; $F491
    clc                             ; $F494

;; One step of the multiplication.
MUL1:
    jsr RTLOG1                      ; $F495
    bcc MUL2                        ; $F498
    jsr ADD                         ; $F49A

MUL2:
    dey                             ; $F49D
    bpl MUL1                        ; $F49E

;; Ends multiplying or dividing: normalizes the result, after negating it if the low bit of <SIGN> is set.
;; Entry: NORMX = normalizes, or negates first if the carry is set
MDEND:
    lsr SIGN                        ; $F4A0

NORMX:
    bcc NORM                        ; $F4A2

;; Negates FP1's mantissa (two's complement), then normalizes it.
;;
;; The branch at the end is always taken (X is 0), into <ADDEND>, which also handles negating $800000.
FCOMPL:
    sec                             ; $F4A4
    ldx #$03                        ; $F4A5

COMPL1:
    lda #$00                        ; $F4A7
    sbc X1,x                        ; $F4A9
    sta X1,x                        ; $F4AB
    dex                             ; $F4AD
    bne COMPL1                      ; $F4AE
    beq ADDEND                      ; $F4B0

;; Divides: FP1 = FP2 / FP1.
;;
;; The exponents are subtracted (<MD2>). Each of the 23 steps subtracts the divisor, E, from the dividend, M2,
;; keeping the difference if it is not negative, and shifts the result bit into the quotient in M1.
;; Errors: jumps to OVLOC on overflow, which a divisor that is not normalized causes
;; See: <MD1>, <MD2>, <MDEND>
FDIV:
    jsr MD1                         ; $F4B2
    sbc X1                          ; $F4B5
    jsr MD2                         ; $F4B7

;; One step of the division.
DIV1:
    sec                             ; $F4BA
    ldx #$02                        ; $F4BB

DIV2:
    lda M2,x                        ; $F4BD
    sbc E,x                         ; $F4BF
    pha                             ; $F4C1
    dex                             ; $F4C2
    bpl DIV2                        ; $F4C3
    ldx #$FD                        ; $F4C5 X = -3: M2 to M2+2

DIV3:
    pla                             ; $F4C7
    bcc DIV4                        ; $F4C8 the divisor did not fit: keep the dividend
    sta X1,x                        ; $F4CA

DIV4:
    inx                             ; $F4CC
    bne DIV3                        ; $F4CD
    rol M1+2                        ; $F4CF
    rol M1+1                        ; $F4D1
    rol M1                          ; $F4D3
    asl M2+2                        ; $F4D5
    rol M2+1                        ; $F4D7
    rol M2                          ; $F4D9
    bcs OVFL                        ; $F4DB the dividend overflowed
    dey                             ; $F4DD
    bne DIV1                        ; $F4DE
    beq MDEND                       ; $F4E0

;; Sets the result's exponent for multiplying or dividing, and clears M1 for the result.
;;
;; A carry from the exponents' sum or difference means an overflow if the exponent is positive. A result too small
;; for the exponent is an underflow: MD2 drops its caller's return address and returns 0 instead.
;; In: A = the exponents' sum or difference, X = 0
;; Out: X1 = the exponent, Y = 23 (the steps)
MD2:
    stx M1+2                        ; $F4E2
    stx M1+1                        ; $F4E4
    stx M1                          ; $F4E6
    bcs OVCHK                       ; $F4E8
    bmi MD3                         ; $F4EA
    pla                             ; $F4EC underflow: return 0 from FMUL or FDIV
    pla                             ; $F4ED
    bcc NORMX                       ; $F4EE

;; Stores the result's exponent, with its top bit, the bias, put back.
MD3:
    eor #$80                        ; $F4F0
    sta X1                          ; $F4F2
    ldy #$17                        ; $F4F4
    rts                             ; $F4F6

;; After a carry: an overflow unless the exponent is positive.
OVCHK:
    bpl MD3                         ; $F4F7

;; An overflow: jumps to the program's handler at <OVLOC>.
OVFL:
    jmp OVLOC                       ; $F4F9
    .byte $FF, $FF, $FF, $FF        ; $F4FC .fill 4,$FF unused bytes
