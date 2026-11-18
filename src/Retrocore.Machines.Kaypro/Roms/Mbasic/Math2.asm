;; MBASIC 5.21: MATH PACKAGE, PART 2: INT, INTEGER AND DOUBLE-PRECISION ARITHMETIC, NUMBER INPUT
;;
;; The middle of Microsoft's math package: the truncating functions, the integer and double-precision
;; arithmetic that the operator dispatch tables (FRCTBL, Tables.asm) call, the soft overflow handler, and FIN,
;; which turns the text of a number into the floating accumulator. It is the code GW-BASIC keeps in MATH1.ASM
;; and MATH2.ASM, here in its 8080 form, nearly instruction for instruction the same as the TRS-80's Level II
;; BASIC (Level2.asm), from which most of the names come. In order:
;;
;; - FN_FIX, FN_INT, INT and DINT truncate the FAC; DINTFO also serves FOUT (Math3.asm).
;; - UMULT multiplies array subscripts. IADD, ISUB, IMULT, IDIV (the \ operator) and IMOD work on 16-bit
;;   integers, redoing the operation in single precision when an integer result overflows; INEG negates.
;; - DADD, DSUB, DMULT and DDIV are the double-precision operators, on the FAC and ARG, with DNORML and
;;   DROUND to normalize and round, the 7-byte mantissa helpers DADDS, DNEGR, DSHFTR and DSHFTL, and DMUL10
;;   and DDIV10 for FIN and FOUT. The mantissa add is self-modifying: DADDOP is an ADC or an SBC.
;; - FIN and FINDBL parse a number: digits, a decimal point, an E or D exponent and a %, ! or # suffix, with
;;   & constants passed to the octal and hex scanner. The value starts as an integer and moves up to single
;;   and double precision as the digits need.
;; - OVFLS is MBASIC's overflow and division-by-zero handler. Unlike Level II, an overflow is not an error
;;   unless error trapping is on: it prints "Overflow" or "Division by zero" (only once within FIN or a
;;   function), puts the largest number of the right sign in the FAC, and carries on.
;;
;; The FAC is the 8 bytes from DFACLO to its exponent (FAC); a single-precision value is its top
;; four, from FACLO. The byte below DFACLO (FAC_ROUND_BYTE) holds the bits rounded off; the byte above the
;; exponent (FAC_SIGN_TEMP) holds the sign while the FAC is unpacked. ARG, the second operand, is laid out the same
;; from ARGLO to its exponent (ARG), and FBUFFR holds the multiplier or dividend of DMULT and DDIV.
;;
;; Runs at $2A6D-$3111.

;; Truncates the FAC toward zero (the FIX function).
;;
;; In:    FAC = the number, VALTYP = its type
;; Out:   FAC = the number with its fraction dropped, of the same type
FN_FIX:
    CALL GETYPR                     ; what type is the argument?
    RET M                           ; an integer has no fraction to remove
    CALL SIGN                       ; the sign
    JP P,FN_INT                     ; positive values truncate the same as INT
    CALL NEG                        ; negative: FIX(x) = -INT(-x)
    CALL FN_INT
    JP VNEG

;; Replaces the FAC with the largest whole number not above it (the INT function), for any numeric type.
;;
;; A single-precision value that fits an integer becomes one: the conversion routine returns straight to the
;; caller then. A double-precision value stays double.
;;
;; In:    FAC = the number, VALTYP = its type
;; Out:   FAC = INT of the number
;; Errors: TM error for a string
FN_INT:
    CALL GETYPR                     ; what type is the FAC?
    RET M                           ; integers are already whole
    JP NC,DINT                      ; double precision has its own path
    JP Z,TMERR
    CALL CONIS                      ; if it fits an integer, this returns straight to our caller

;; Takes the integer part of the single-precision accumulator, rounding toward minus infinity.
;;
;; In:    FAC = a single-precision number
;; Out:   FAC = its integer part, still single precision, A = the integer's low byte
;; Uses:  BC, DE, HL
INT:
    LD HL,FAC
    LD A,[HL]
    CP $98                          ; exponent $98 or more leaves no fraction bits
    LD A,[FACLO]                    ; A = low byte, wanted by one caller
    RET NC
    LD A,[HL]
    CALL QINT                       ; truncate to a signed integer in CDE
    LD [HL],$98                     ; exponent for a 24-bit integer before renormalizing
    LD A,E                          ; keep the low byte for the caller
    PUSH AF
    LD A,C                          ; sign of the integer into carry
    RLA
    CALL FADFLT                     ; float it back into the FAC
    POP AF
    RET

;; Applies INT to the double-precision FAC, leaving it double precision.
;;
;; -32768 exactly is made an integer and converted back to double; otherwise the fraction bits are shifted
;; out by DINTFO.
;;
;; In:    FAC = a double-precision number
;; Out:   FAC = its integer part, double precision
;; Uses:  A, BC, DE, HL
DINT:
    LD HL,FAC
    LD A,[HL]
    CP $90                          ; exponent $90 could be -32768
    JP NZ,DINT2
    LD C,A
    DEC HL
    LD A,[HL]
    XOR $80                         ; a high byte of $80 means -.5 times 2^16
    LD B,$06                        ; the six lower mantissa bytes must all be zero
DINT1:
    DEC HL
    OR [HL]
    DEC B
    JP NZ,DINT1
    OR A
    LD HL,$8000                     ; HL = -32768
    JP NZ,DINT_1                    ; not -32768
    CALL MAKINT                     ; -32768 as an integer
    JP FN_CDBL                      ; and back to double precision
DINT_1:
    LD A,C                          ; A = the exponent again
DINT2:
    OR A                            ; zero is already whole
    RET Z
    CP $B8                          ; $B8 or more leaves no fraction bits in 56
    RET NC

;; Truncates the double-precision accumulator to its integer part, normalizing it if carry is set.
;;
;; FOUT calls it with carry clear, to get the integer unnormalized at exponent $B8 for its digits.
;;
;; In:    FAC = a double-precision number below 2^56, carry = set to normalize the result
;; Out:   FAC = its integer part
;; Uses:  A, BC, DE, HL
DINTFO:
    PUSH AF                         ; keep the carry, whether to normalize
    CALL MOVRF                      ; high bytes into BCDE
    CALL UNPACK                     ; unpack: hidden bit set, C = the high byte, A = the sign
    XOR [HL]                        ; A's top bit = the number's sign
    DEC HL                          ; exponent that normalizes to the integer value
    LD [HL],$B8
    PUSH AF                         ; keep the sign
    DEC HL
    LD [HL],C                       ; the unpacked high byte back in the FAC
    CALL M,DINTA                    ; negative: less 1, so the result rounds down
    LD A,[FACHI]
    LD C,A                          ; C = the high byte, for DSHFTR to store
    LD HL,FACHI
    LD A,$B8                        ; A = bits to shift out to drop the fraction
    SUB B
    CALL DSHFTR
    POP AF
    CALL M,DROUNA                   ; negative: add the 1 back
    XOR A                           ; clear the round byte so zeros shift in
    LD [FAC_ROUND_BYTE],A
    POP AF                          ; recover the normalize flag
    RET NC                          ; FOUT wants the unnormalized integer
    JP DNORML

;; Decrements the double-precision accumulator's 7-byte mantissa, propagating the borrow.
;;
;; In:    DFACLO..FACHI = the mantissa
;; Out:   DFACLO..FACHI = the mantissa less 1 in its lowest bit
;; Uses:  A, HL
DINTA:
    LD HL,DFACLO                    ; FAC's low mantissa byte
DINTA1:
    LD A,[HL]
    DEC [HL]
    OR A                            ; a byte that was zero borrows from the next
    INC HL
    JP Z,DINTA1
    RET

;; Multiplies BC by DE unsigned into DE, for an array's size or element offset.
;;
;; In:    BC = the multiplicand, DE = the multiplier
;; Out:   DE = the product
;; Errors: BS error (subscript out of range) if the product is 64K or more
;; Uses:  A
;; Keeps: BC, HL
UMULT:
    PUSH HL
    LD HL,$0000                     ; HL = product, starting at zero
    LD A,B                          ; a zero multiplicand gives a zero product
    OR C
    JP Z,MULRET
    LD A,$10                        ; 16 bits of multiplier in DE
UMULT1:
    ADD HL,HL                       ; shift the product left
    JP C,BSERR                      ; product over 64K: the array is too big
    EX DE,HL                        ; next multiplier bit into carry
    ADD HL,HL
    EX DE,HL
    JP NC,UMULT2
    ADD HL,BC                       ; bit set, add the multiplicand
    JP C,BSERR
UMULT2:
    DEC A
    JP NZ,UMULT1
MULRET:
    EX DE,HL                        ; product into DE
    POP HL
    RET

;; Subtracts the integer HL from DE into the FAC, going to single precision on overflow.
;;
;; In:    DE = the first operand, HL = the second
;; Out:   FAC = DE - HL, an integer, or single precision if it does not fit
ISUB:
    LD A,H                          ; B = sign extension of HL
    RLA
    SBC A,A
    LD B,A
    CALL INEGHL                     ; negate the subtrahend and add instead
    LD A,C                          ; A = 0, the C INEGHL leaves
    SBC A,B                         ; sign extension of the negated value
    JP IADDS

;; Adds the integers HL and DE into the FAC, going to single precision on overflow.
;;
;; In:    DE = the first operand, HL = the second
;; Out:   FAC = DE + HL, an integer, or single precision if it does not fit
;; Entry: IADDS = A = the sign extension of HL, from ISUB
IADD:
    LD A,H
    RLA
    SBC A,A
IADDS:
    LD B,A                          ; B = sign extension of the second operand
    PUSH HL                         ; kept in case the sum must be redone in floating
    LD A,D                          ; A = sign extension of DE
    RLA
    SBC A,A
    ADD HL,DE
    ADC A,B                         ; A = bit 16 and up of the true sum
    RRCA                            ; bit 16 into bit 7
    XOR H                           ; differs from bit 15 only on overflow
    JP P,CONIS1                     ; fits, store it as an integer
    PUSH BC                         ; overflow: redo both operands in single precision
    EX DE,HL                        ; HL = the first operand, floated into the FAC
    CALL CONSIH
    POP AF                          ; A = the second operand's sign extension
    POP HL                          ; HL = the second operand
    CALL PUSHF                      ; first operand to the stack
    EX DE,HL                        ; second operand as A D E
    CALL INEGAD                     ; float it as a 24-bit integer
    JP FADDT                        ; add them in single precision

;; Multiplies the integers DE and HL into the FAC, going to single precision on overflow.
;;
;; In:    DE = the first operand, HL = the second
;; Out:   FAC = DE * HL, an integer, or single precision if it does not fit
IMULT:
    LD A,H
    OR L
    JP Z,MAKINT                     ; times zero gives zero
    PUSH HL                         ; both operands kept in case of overflow
    PUSH DE
    CALL IMULDV                     ; make both positive, B = sign of the product
    PUSH BC                         ; keep the product's sign
    LD B,H                          ; BC = multiplicand
    LD C,L
    LD HL,$0000                     ; HL = product
    LD A,$10                        ; 16 multiplier bits in DE
IMULT1:
    ADD HL,HL
    JP C,IMULT5                     ; overflow, redo it in single precision
    EX DE,HL                        ; next multiplier bit into carry
    ADD HL,HL
    EX DE,HL
    JP NC,IMULT2
    ADD HL,BC                       ; add the multiplicand for a 1 bit
    JP C,IMULT5
IMULT2:
    DEC A
    JP NZ,IMULT1
    POP BC                          ; B = sign of the product
    POP DE                          ; DE = the first operand

;; Finishes an integer multiply or divide, applying the result's sign in B or handling a value of 32768 up.
;;
;; In:    HL = the unsigned result, B = its sign in bit 7, DE = the first operand (the remainder from IDIV),
;;          SP = at the saved second operand
;; Out:   FAC = the signed result
IMLDIV:
    LD A,H                          ; a result of 32768 or more?
    OR A
    JP M,IMULT3                     ; may be overflow, or exactly 32768
    POP DE                          ; drop the saved second operand
    LD A,B                          ; negate if the result should be negative
    JP INEGA

;; Handles a result with bit 15 set: exactly 32768 goes to IMULT4, anything larger is redone in single
;; precision.
;;
;; In:    HL = the unsigned result, B = its sign in bit 7, DE = the first operand, SP = at the saved second
;;          operand
;; Out:   FAC = the result
;; Entry: IMULT5 = the multiply overflowed, with the sign, the first operand and the second saved on the stack
IMULT3:
    XOR $80                         ; exactly $8000 means 32768
    OR L
    JP Z,IMULT4                     ; from IDIV it cannot be more than 32768
    EX DE,HL                        ; overflow: HL = first operand, skip two POPs
    .byte $01                       ; LD BC,nn: skips POP BC and POP HL
IMULT5:
    POP BC                          ; discard the result sign
    POP HL                          ; HL = the first operand
    CALL CONSIH                     ; float it into the FAC
    POP HL                          ; HL = the second operand
    CALL PUSHF                      ; first operand, floated, onto the stack
    CALL CONSIH                     ; float the second operand into the FAC

;; Pops a single-precision number off the stack into BCDE and multiplies the FAC by it.
;;
;; In:    SP = at the number, under the return address
;; Out:   FAC = the FAC times the number
FMULTT:
    POP BC                          ; the number into BCDE
    POP DE
    JP FMULT

;; Returns a result of 32768 as the integer -32768 if negative, else as +32768 in single precision.
;;
;; In:    HL = $8000, B = the result's sign in bit 7, DE = the remainder (for IMOD), SP = at the saved
;;          second operand
;; Out:   FAC = the result, DE = the remainder
IMULT4:
    LD A,B                          ; sign of the result
    OR A
    POP BC                          ; drop the saved second operand
    JP M,MAKINT                     ; -32768 fits an integer as it is
    PUSH DE                         ; keep DE, the remainder for MOD
    CALL CONSIH                     ; float $8000, which gives -32768
    POP DE
    JP NEG                          ; flip it to +32768

;; Divides the integer DE by HL into the FAC, truncating toward zero (the \ operator).
;;
;; A shift-and-subtract loop of 17 steps: HL holds the remainder and BC the divisor negated, and each step
;; shifts the next quotient bit, from carry, into DE.
;;
;; In:    DE = the dividend, HL = the divisor
;; Out:   FAC = DE \ HL, an integer, or single precision for -32768 \ -1, DE = the remainder times 2
;; Errors: /0 error (division by zero) if HL is zero
IDIV:
    LD A,H
    OR L
    JP Z,DV0ERR
    CALL IMULDV                     ; make both positive, B = sign of the quotient
    PUSH BC
    EX DE,HL                        ; negate the divisor
    CALL INEGHL
    LD B,H                          ; BC = -divisor
    LD C,L
    LD HL,$0000                     ; HL = remainder
    LD A,$11                        ; 16 bits, plus one step to shift the last in
    PUSH AF
    OR A                            ; the first bit shifted in is 0
    JP IDIV_3
IDIV_1:
    PUSH AF
    PUSH HL                         ; keep the remainder, in case the divisor does not fit
    ADD HL,BC                       ; try subtracting the divisor
    JP NC,IDIV_2                    ; it did not fit
    POP AF                          ; it fitted: drop the old remainder
    SCF                             ; quotient bit 1
    .byte $3E                       ; LD A,n: skips the POP HL
IDIV_2:
    POP HL                          ; restore the remainder, carry clear: quotient bit 0
IDIV_3:
    LD A,E                          ; shift the quotient bit into DE
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,L                          ; and the dividend's next bit into the remainder
    RLA
    LD L,A
    LD A,H
    RLA
    LD H,A
    POP AF
    DEC A
    JP NZ,IDIV_1
    EX DE,HL                        ; HL = the quotient, DE = the remainder
    POP BC                          ; B = the quotient's sign
    PUSH DE
    JP IMLDIV

;; Makes DE and HL positive for an integer multiply or divide, leaving the result's sign in B bit 7.
;;
;; In:    DE = the first operand, HL = the second
;; Out:   DE = the first operand's absolute value, HL = the second's, B = the result's sign in bit 7,
;;          FAC = the first operand's absolute value, as an integer
;; Uses:  A, C
IMULDV:
    LD A,H                          ; result is negative if the signs differ
    XOR D
    LD B,A                          ; B bit 7 = sign of the result
    CALL INEGH                      ; absolute value of the second operand
    EX DE,HL                        ; now do the first operand

;; Stores the absolute value of the integer in HL as the integer FAC.
;;
;; In:    HL = the integer
;; Out:   HL = FAC = its absolute value
;; Entry: INEGA = A = the sign in bit 7 that decides whether to negate HL
;; Uses:  A, C
INEGH:
    LD A,H
INEGA:
    OR A
    JP P,MAKINT                     ; already positive

;; Negates the integer in HL and stores it as the integer FAC.
;;
;; In:    HL = the integer
;; Out:   HL = FAC = its negative, C = 0, carry = set unless HL was zero
INEGHL:
    XOR A                           ; A = 0
    LD C,A                          ; C = 0, used by ISUB
    SUB L
    LD L,A
    LD A,C
    SBC A,H
    LD H,A
    JP MAKINT

;; Negates the integer FAC, turning the one overflow case (-32768) into single-precision 32768.
;;
;; In:    FAC = an integer
;; Out:   FAC = its negative
INEG:
    LD HL,[FACLO]
    CALL INEGHL                     ; -32768 negated is still $8000
    LD A,H
    XOR $80                         ; is the result $8000?
    OR L
    RET NZ                          ; no, a valid integer

;; Converts the unsigned 16-bit value in HL to single precision in the FAC.
;;
;; In:    HL = the value
;; Out:   FAC = the value, single precision
INEG2:
    EX DE,HL                        ; 32768 must go to single precision
    CALL VALSNG                     ; VALTYP = single
    XOR A                           ; A D E = 0, H, L as an unsigned value

;; Converts the signed 24-bit value in A:D:E to single precision in the FAC.
;;
;; In:    A = the value's high byte, DE = its low 16 bits
;; Out:   FAC = the value, single precision
INEGAD:
    LD B,$98                        ; exponent for a 24-bit integer
    JP FLOATR

;; Takes the remainder of the integer DE divided by HL into the FAC (the MOD operator).
;;
;; The remainder has the sign of the dividend.
;;
;; In:    DE = the dividend, HL = the divisor
;; Out:   FAC = DE MOD HL, an integer
;; Errors: /0 error (division by zero) if HL is zero
IMOD:
    PUSH DE                         ; keep the dividend, for its sign
    CALL IDIV                       ; DE = the remainder times 2
    XOR A
    ADD A,D                         ; halve it into HL
    RRA
    LD H,A
    LD A,E
    RRA
    LD L,A
    CALL VALINT                     ; VALTYP = integer
    POP AF                          ; A = the dividend's high byte
    JP INEGA                        ; give the remainder the dividend's sign

;; Subtracts the double-precision ARG from the double-precision FAC.
;;
;; In:    FAC, ARG = double-precision numbers
;; Out:   FAC = FAC - ARG
DSUB:
    LD HL,ARGHI                     ; ARG's sign byte
    LD A,[HL]
    XOR $80                         ; flip its sign, so adding it subtracts
    LD [HL],A

;; Adds the double-precision ARG to the double-precision FAC.
;;
;; The number with the smaller exponent goes to ARG, swapping them if need be, and is shifted right to line
;; up with the FAC; the mantissas are then added or, if the signs differ, subtracted.
;;
;; In:    FAC, ARG = double-precision numbers
;; Out:   FAC = FAC + ARG
;; Uses:  A, BC, DE, HL, ARGLO..ARG
DADD:
    LD HL,ARG                       ; ARG's exponent
    LD A,[HL]
    OR A
    RET Z                           ; adding zero changes nothing
    LD B,A                          ; B = ARG exponent, C = its high byte and sign
    DEC HL
    LD C,[HL]
    LD DE,FAC                       ; FAC's exponent
    LD A,[DE]
    OR A
    JP Z,VMOVFA                     ; FAC zero: the sum is just ARG
    SUB B                           ; A = how many bits ARG must be shifted down
    JP NC,DADD2                     ; ARG is the smaller, as needed
    CPL                             ; FAC is smaller: make the count positive
    INC A
    PUSH AF
    LD C,$08                        ; swap FAC and ARG, 8 bytes each
    INC HL                          ; HL = ARG exponent
    PUSH HL
DADD1:
    LD A,[DE]
    LD B,[HL]
    LD [HL],A
    LD A,B
    LD [DE],A
    DEC DE
    DEC HL
    DEC C
    JP NZ,DADD1
    POP HL
    LD B,[HL]                       ; B = new ARG exponent
    DEC HL
    LD C,[HL]                       ; C = new ARG high byte and sign
    POP AF
DADD2:
    CP $39                          ; 57 bits or more apart: ARG is too small to matter
    RET NC
    PUSH AF
    CALL UNPACK                     ; hidden bits back, A bit 7 set if signs agree
    LD HL,ARG_ROUND_BYTE            ; ARG's round byte
    LD B,A                          ; B = add or subtract flag
    LD A,$00
    LD [HL],A                       ; clear both round bytes
    LD [FAC_ROUND_BYTE],A
    POP AF
    LD HL,ARGHI                     ; align ARG with the FAC
    CALL DSHFTR
    LD A,B                          ; signs differ?
    OR A
    JP P,DADD3                      ; yes, subtract
    LD A,[ARG_ROUND_BYTE]           ; bits shifted out of ARG become the round byte
    LD [FAC_ROUND_BYTE],A
    CALL DADDAA                     ; signs agree, add the mantissas
    JP NC,DROUND                    ; no carry out, just round
    EX DE,HL                        ; HL = FAC exponent
    INC [HL]                        ; carry out: bump the exponent
    JP Z,UNPOVF
    CALL DSHFRB                     ; shift the carry back in at the top
    JP DROUND

;; Subtracts the mantissas when the double add's signs differ, negating a negative result, then normalizes.
;;
;; In:    FAC, ARG = unpacked and aligned, FAC_SIGN_TEMP = the FAC's sign, complemented
;; Out:   FAC = the difference, normalized and rounded
DADD3:
    LD A,$9E                        ; SBC A,[HL]
    CALL DADDA                      ; FAC mantissa less ARG's
    LD HL,FAC_SIGN_TEMP             ; sign byte, for DNEGR
    CALL C,DNEGR                    ; borrow means the result came out negative

;; Normalizes the double-precision FAC, shifting out leading zero bytes and bits, then rounds it.
;;
;; In:    FAC = unpacked, its mantissa from FAC_ROUND_BYTE (the round byte) up
;; Out:   FAC = normalized and rounded, or zero
;; Errors: overflow (UNPOVF) if rounding carries out of the exponent
DNORML:
    XOR A                           ; B counts the shift, as a negative number
DNORM1:
    LD B,A
    LD A,[FACHI]                    ; high byte zero, a whole byte can be shifted
    OR A
    JP NZ,DNORM5                    ; nonzero, shift bit by bit
    LD HL,FAC_ROUND_BYTE            ; start from the round byte, the lowest
    LD C,$08                        ; 8 bytes move up one place
DNORM2:
    LD D,[HL]
    LD [HL],A                       ; A holds the lower byte, zero the first time
    LD A,D
    INC HL
    DEC C
    JP NZ,DNORM2
    LD A,B                          ; shift count less 8
    SUB $08
    CP $C0                          ; all 64 bits shifted away?
    JP NZ,DNORM1
    JP ZERO                         ; the value is zero
DNORM3:
    DEC B                           ; one more bit of shift
    LD HL,FAC_ROUND_BYTE            ; the round byte, lowest of the 8
    CALL DSHFLC
    OR A                            ; top bit set yet?
DNORM5:
    JP P,DNORM3                     ; not normalized, keep shifting
    LD A,B                          ; A = bits shifted, as a negative number
    OR A
    JP Z,DROUND                     ; no shift, go round
    LD HL,FAC
    ADD A,[HL]                      ; lower the exponent by the shift
    LD [HL],A
    JP NC,ZERO                      ; exponent went below zero
    RET Z                           ; exponent exactly zero is also a zero

;; Rounds the double-precision FAC using its round byte and puts the sign back over the hidden bit.
;;
;; In:    FAC = unpacked and normalized, FAC_ROUND_BYTE = the round byte, FAC_SIGN_TEMP = the sign, complemented
;; Out:   FAC = rounded and packed
;; Entry: DROUNB = A = the round byte
;; Errors: overflow (UNPOVF) if rounding carries out of the exponent
DROUND:
    LD A,[FAC_ROUND_BYTE]
DROUNB:
    OR A                            ; top bit of the round byte set: round up
    CALL M,DROUNA
    LD HL,FAC_SIGN_TEMP             ; unpacked sign byte, complemented
    LD A,[HL]
    AND $80                         ; keep only its sign bit
    DEC HL
    DEC HL
    XOR [HL]                        ; put the sign over the hidden bit
    LD [HL],A
    RET

;; Increments the double-precision mantissa, carrying into the exponent.
;;
;; In:    FAC = unpacked
;; Out:   FAC = the mantissa plus 1 in its lowest bit
;; Errors: overflow (UNPOVF) if the exponent carries out
;; Uses:  B, HL
DROUNA:
    LD HL,DFACLO                    ; FAC's low mantissa byte
    LD B,$07                        ; 7 mantissa bytes
DRONA1:
    INC [HL]
    RET NZ                          ; no carry, finished
    INC HL
    DEC B
    JP NZ,DRONA1
    INC [HL]                        ; all bytes wrapped to zero, bump the exponent
    JP Z,UNPOVF                     ; exponent overflowed
    DEC HL
    LD [HL],$80                     ; mantissa becomes .5 at the new exponent
    RET

;; Adds (A = $8E) or subtracts (A = $9E) ARG's mantissa to or from the one in FBUFFR, for DDIV.
;;
;; In:    A = $8E (ADC A,[HL]) to add or $9E (SBC A,[HL]) to subtract
;; Out:   FBUFFR+27..FBUFFR+33 = the result, carry = the carry or borrow out, DE = FBUFFR+34
;; Uses:  A, C, HL
DADDFB:
    LD DE,FBUFFR+27                 ; the dividend's low byte
    LD HL,ARGLO
    JP DADDS

;; Adds ARG's 7-byte mantissa to the double-precision FAC's.
;;
;; In:    FAC, ARG = unpacked
;; Out:   DFACLO..FACHI = the sum, carry = the carry out, DE = FAC's exponent
;; Uses:  A, C, HL
DADDAA:
    LD A,$8E                        ; ADC A,[HL]

;; Adds (A = $8E) or subtracts (A = $9E) ARG's 7-byte mantissa to or from the double-precision FAC's.
;;
;; In:    A = $8E (ADC A,[HL]) to add or $9E (SBC A,[HL]) to subtract
;; Out:   DFACLO..FACHI = the result, carry = the carry or borrow out, DE = FAC's exponent
;; Uses:  A, C, HL
DADDA:
    LD HL,ARGLO

;; Adds or subtracts the 7-byte mantissa at HL to or from the double-precision FAC's.
;;
;; The operation is stored into DADDOP, so the same loop adds or subtracts.
;;
;; In:    HL = the low byte of the other mantissa, A = $8E (ADC A,[HL]) or $9E (SBC A,[HL])
;; Out:   DFACLO..FACHI = the result, carry = the carry or borrow out, DE = FAC's exponent
;; Entry: DADDS = DE = the low byte of the 7-byte number to change
;; Uses:  A, C, HL
DADDFO:
    LD DE,DFACLO
DADDS:
    LD C,$07                        ; 7 bytes
    LD [DADDOP],A                   ; the add or subtract
    XOR A                           ; clear carry for the first byte
DADDL:
    LD A,[DE]
DADDOP:
    ADC A,[HL]                      ; self-modified: ADC A,[HL] or SBC A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JP NZ,DADDL
    RET

;; Complements the sign byte at HL and negates the 8-byte double-precision mantissa, round byte included.
;;
;; In:    HL = the sign byte (FAC_SIGN_TEMP)
;; Out:   FAC_ROUND_BYTE..FACHI = negated
;; Uses:  A, BC, HL
DNEGR:
    LD A,[HL]                       ; unpacked sign byte
    CPL
    LD [HL],A
    LD HL,FAC_ROUND_BYTE            ; start at the round byte
    LD B,$08                        ; 8 bytes, round byte included
    XOR A                           ; clear borrow, C = 0
    LD C,A
DNEGR1:
    LD A,C
    SBC A,[HL]                      ; 0 minus the byte, with borrow
    LD [HL],A
    INC HL
    DEC B
    JP NZ,DNEGR1
    RET

;; Stores C at HL, then shifts the 8-byte number ending at HL right by A bits.
;;
;; In:    HL = the number's top byte, C = the value for it, A = the bit count
;; Out:   A = 0, with the number shifted
;; Entry: DSHFRM = shifts one byte, then A - 8 more bits, DSHFRA = shifts D - 1 bits, the top at HL
;; Uses:  BC, DE, HL
DSHFTR:
    LD [HL],C                       ; put the unpacked high byte back first
    PUSH HL
DSHFR1:
    SUB $08                         ; at least 8 bits still to shift?
    JP C,DSHFR3                     ; no, finish bit by bit
    POP HL
DSHFRM:
    PUSH HL
    LD DE,$0800                     ; E = 0 enters the top, D counts 8 bytes
DSHFR2:
    LD C,[HL]                       ; move each byte down one place
    LD [HL],E
    LD E,C
    DEC HL
    DEC D
    JP NZ,DSHFR2
    JP DSHFR1
DSHFR3:
    ADD A,$09                       ; A = bits left to shift plus one
    LD D,A
DSHFR4:
    XOR A                           ; zero carry enters the top bit
    POP HL                          ; HL = top byte of the number
    DEC D
    RET Z
DSHFRA:
    PUSH HL
    LD E,$08                        ; 8 bytes per bit shift
DSHFR5:
    LD A,[HL]
    RRA                             ; shift right through carry
    LD [HL],A
    DEC HL
    DEC E
    JP NZ,DSHFR5
    JP DSHFR4

;; Shifts the double-precision FAC's mantissa right one bit, carry entering the top.
;;
;; In:    carry = the bit for the top
;; Out:   FAC_ROUND_BYTE..FACHI = shifted, A = 0
;; Uses:  DE, HL
DSHFRB:
    LD HL,FACHI                     ; the FAC's high byte
    LD D,$01                        ; one bit
    JP DSHFRA

;; Rotates the 8-byte number at HL left one bit through carry, low byte first.
;;
;; In:    HL = the low byte, carry = the bit for the bottom
;; Out:   carry = the bit out of the top, HL = past the top byte
;; Entry: DSHFTL = C = the byte count
;; Uses:  A, C
DSHFLC:
    LD C,$08                        ; 8 bytes
DSHFTL:
    LD A,[HL]
    RLA                             ; shift left through carry
    LD [HL],A
    INC HL
    DEC C
    JP NZ,DSHFTL
    RET

;; Multiplies the double-precision FAC by the double-precision ARG.
;;
;; The multiplier, copied to FBUFFR, is taken a bit at a time from the bottom: ARG is added for each 1, and
;; the product shifted right each time.
;;
;; In:    FAC, ARG = double-precision numbers
;; Out:   FAC = FAC * ARG
;; Errors: overflow (MLDVOV) if the product is too big
DMULT:
    CALL SIGN                       ; is the FAC zero?
    RET Z                           ; zero times anything is zero
    LD A,[ARG]                      ; is ARG zero?
    OR A
    JP Z,ZERO                       ; then so is the product
    CALL MULDVA                     ; add exponents and work out the result sign
    CALL DMULDV                     ; multiplier to FBUFFR, FAC zeroed for the product
    LD [HL],C                       ; clear the FAC's round byte
    INC DE                          ; DE = low byte of the multiplier copy
    LD B,$07                        ; 7 multiplier bytes
DMULT2:
    LD A,[DE]                       ; next multiplier byte
    INC DE
    OR A                            ; a zero byte only shifts the product
    PUSH DE                         ; keep the multiplier pointer
    JP Z,DMULT5
    LD C,$08                        ; 8 bits in this byte
DMULT3:
    PUSH BC                         ; keep the byte and bit counters
    RRA                             ; next multiplier bit into carry
    LD B,A                          ; B keeps the bits still to test
    CALL C,DADDAA                   ; bit set, add the multiplicand ARG
    CALL DSHFRB                     ; shift the product right a bit
    LD A,B
    POP BC
    DEC C
    JP NZ,DMULT3
DMULT4:
    POP DE                          ; multiplier pointer back
    DEC B                           ; another multiplier byte?
    JP NZ,DMULT2
    JP DNORML                       ; normalize and round the product
DMULT5:
    LD HL,FACHI
    CALL DSHFRM                     ; shift the product down a byte
    JP DMULT4

;; Holds the double-precision constant 0.1, which DDIV10 multiplies a small number by.
DTENTH:
    .byte $CD, $CC, $CC, $CC, $CC, $CC, $4C, $7D ; 0.1
    ; The double-precision 10.0: its low four bytes, then FTEN, its high half.
    .byte $00, $00, $00, $00

;; Holds the single-precision constant 10.0, which is also the high half of the double-precision 10.0.
FTEN:
    .byte $00, $00, $20, $84        ; 10.0

;; Divides the double-precision FAC by 10.
;;
;; A number with an exponent below $41 is multiplied by DTENTH. Any other is divided exactly by a series:
;; x/10 = (x/2 + x/4) * (1 + 1/16 + 1/256 + ...) / 8, adding 15 terms with ARG shifted 4 bits further
;; each time, which only needs DADD and the exponent.
;;
;; In:    FAC = a double-precision number
;; Out:   FAC = the number / 10
;; Uses:  A, BC, DE, HL, ARGLO..ARG
DDIV10:
    LD A,[FAC]
    CP $41                          ; too small for the series?
    JP NC,DDIV10_1
    LD DE,DTENTH                    ; then multiply by 0.1
    LD HL,ARGLO
    CALL VMOVE
    JP DMULT
DDIV10_1:
    LD A,[FACHI]
    OR A
    JP P,DDIV10_2                   ; positive
    AND $7F                         ; negative: work on its absolute value
    LD [FACHI],A
    LD HL,NEG                       ; and negate it on the way out
    PUSH HL
DDIV10_2:
    CALL DHALVE                     ; FAC = x/2
    LD DE,DFACLO
    LD HL,ARGLO
    CALL VMOVE                      ; ARG = x/2
    CALL DHALVE                     ; FAC = x/4
    CALL DADD                       ; FAC = 3x/4
    LD DE,DFACLO
    LD HL,ARGLO
    CALL VMOVE                      ; ARG = 3x/4
    LD A,$0F                        ; 15 more terms
DDIV10_3:
    PUSH AF
    CALL ARGD16                     ; ARG / 16
    CALL PSHARG                     ; DADD changes ARG, so keep it
    CALL DADD
    LD HL,ARGHI
    CALL POPARG
    POP AF
    DEC A
    JP NZ,DDIV10_3
    CALL DHALVE                     ; 4x/5 divided by 8
    CALL DHALVE

;; Halves the FAC by decrementing its exponent, making it zero on underflow.
;;
;; In:    FAC = a nonzero number
;; Out:   FAC = the number / 2
;; Uses:  HL
DHALVE:
    LD HL,FAC
    DEC [HL]
    RET NZ
    JP ZERO

;; Divides ARG by 16 by lowering its exponent by 4, stopping if it reaches zero.
;;
;; In:    ARG = a double-precision number
;; Out:   ARG = the number / 16, or a zero exponent, zero = set if it became zero
;; Uses:  A, HL
ARGD16:
    LD HL,ARG
    LD A,$04
ARGD16_1:
    DEC [HL]
    RET Z
    DEC A
    JP NZ,ARGD16_1
    RET

;; Pushes ARG's 8 bytes onto the stack, under the return address.
;;
;; In:    ARG = a double-precision number
;; Out:   SP = at the copy of ARG, four words
;; Uses:  A, BC, DE, HL
PSHARG:
    POP DE                          ; the return address
    LD A,$04
    LD HL,ARGLO
PSHARG_1:
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,PSHARG_1
    PUSH DE
    RET

;; Pops the 8 bytes PSHARG pushed back into ARG.
;;
;; In:    SP = at the copy of ARG, under the return address
;; Out:   ARG = restored
;; Uses:  A, BC, DE, HL
POPARG:
    POP DE                          ; the return address
    LD A,$04
    LD HL,ARG
POPARG_1:
    POP BC
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    DEC A
    JP NZ,POPARG_1
    PUSH DE
    RET

;; Divides the double-precision FAC by the double-precision ARG.
;;
;; The dividend, copied to FBUFFR with an extra byte on top, has ARG subtracted from it, and added back if it
;; did not fit; each step shifts a quotient bit into the FAC and the dividend left.
;;
;; In:    FAC, ARG = double-precision numbers
;; Out:   FAC = FAC / ARG
;; Errors: division by zero (DDIV0S) if ARG is zero, overflow (UNPOVF) if the quotient is too big
DDIV:
    LD A,[ARG]                      ; exponent of ARG, the divisor
    OR A
    JP Z,DDIV0S                     ; dividing by zero
    LD A,[FAC]
    OR A
    JP Z,ZERO                       ; zero divided by anything is zero
    CALL MULDVS                     ; subtract exponents, work out the sign
    INC [HL]                        ; exponent + 2 to suit the divide loop
    INC [HL]
    JP Z,UNPOVF
    CALL DMULDV                     ; dividend to FBUFFR, FAC zeroed for the quotient
    LD HL,FBUFFR+34                 ; an extra high byte above the dividend
    LD [HL],C                       ; C = 0 here
    LD B,C                          ; B = 0 until a quotient 1 bit appears
DDIV1:
    LD A,$9E                        ; SBC A,[HL]
    CALL DADDFB                     ; try subtracting the divisor
    LD A,[DE]                       ; borrow through the extra high byte
    SBC A,C
    CCF                             ; carry now set if the divisor fitted
    JP C,DDIV2                      ; fitted, quotient bit is 1
    LD A,$8E                        ; ADC A,[HL]
    CALL DADDFB                     ; did not fit: add the divisor back
    XOR A                           ; quotient bit is 0
    .byte $DA                       ; JP C,nn, never taken: skips the next two instructions
DDIV2:
    LD [DE],A                       ; keep the new extra byte
    INC B                           ; a quotient 1 bit has been seen
    LD A,[FACHI]                    ; is the quotient's top bit set yet?
    INC A                           ; sign flag from A, carry kept
    DEC A
    RRA                             ; carry (the next bit) into bit 7 for rounding
    JP M,DROUNB                     ; quotient complete, round with it
    RLA                             ; carry back = the new quotient bit
    LD HL,DFACLO                    ; shift the bit into the quotient
    LD C,$07
    CALL DSHFTL
    LD HL,FBUFFR+27                 ; and the dividend left a bit
    CALL DSHFLC
    LD A,B                          ; any quotient 1 bit yet?
    OR A
    JP NZ,DDIV1                     ; yes, keep dividing
    LD HL,FAC                       ; leading zero: lower the exponent instead
    DEC [HL]
    JP NZ,DDIV1
    JP ZERO                         ; exponent ran out: the quotient is zero

;; Saves C as ARG's high byte, moves the FAC's 7-byte mantissa below HL to FBUFFR and zeroes it.
;;
;; In:    HL = the FAC's exponent, C = ARG's unpacked high byte
;; Out:   FBUFFR+27..FBUFFR+33 = the mantissa, DFACLO..FACHI = 0, C = 0, DE = FBUFFR+26, HL = FAC_ROUND_BYTE
;; Uses:  A, B
DMULDV:
    LD A,C                          ; unpacked high byte of ARG
    LD [ARGHI],A
    DEC HL                          ; HL = FAC high mantissa byte
    LD DE,FBUFFR+33                 ; the copy's top byte
    LD BC,$0700                     ; 7 bytes, C = 0 to clear the FAC
DMLDV1:
    LD A,[HL]
    LD [DE],A
    LD [HL],C
    DEC DE
    DEC HL
    DEC B
    JP NZ,DMLDV1
    RET

;; Multiplies the double-precision FAC by 10: times 4 by the exponent, plus the original, times 2.
;;
;; In:    FAC = a double-precision number
;; Out:   FAC = the number * 10
;; Errors: overflow (UNPOVF) if it is too big
;; Uses:  A, BC, DE, HL, ARGLO..ARG
DMUL10:
    CALL VMOVAF                     ; copy the FAC to ARG
    EX DE,HL
    DEC HL
    LD A,[HL]                       ; FAC exponent
    OR A
    RET Z                           ; zero times 10 is zero
    ADD A,$02                       ; exponent + 2 multiplies by 4
    JP C,UNPOVF
    LD [HL],A
    PUSH HL
    CALL DADD                       ; plus the original gives 5 times
    POP HL
    INC [HL]                        ; double it, giving 10 times
    RET NZ                          ; done unless the exponent wrapped to zero
    JP UNPOVF

;; Converts the number text at HL into the FAC as double precision.
;;
;; In:    HL = the text, at the number
;; Out:   HL = the text after the number, FAC = the number, double precision
;; See:   <FIN>
FINDBL:
    CALL ZERO                       ; FAC = 0
    CALL VALDBL                     ; VALTYP = double
    .byte $F6                       ; OR n: skips the XOR A, so zero is clear and the type stays double

;; Converts the number text at HL into the FAC, choosing the type from the number (Microsoft's FIN).
;;
;; The value is built as an integer while it fits, then single precision up to seven digits, then double.
;; An E or D exponent (lowercase too), a decimal point or a %, ! or # suffix forces a type. An "E" that
;; starts ELSE or EQV ends the number. Text starting with & is an octal or hex constant. While it runs,
;; FLGOVC = 1, so an overflow is reported only once; FINOVC, its return, keeps FLGOVC in OVCSTR for INPUT.
;;
;; In:    HL = the text, at the number
;; Out:   HL = the text after the number, FAC = the number, VALTYP = its type
;; Uses:  A, BC, DE
FIN:
    XOR A                           ; zero: the number starts as integer zero
    LD BC,FINOVC                    ; return through FINOVC
    PUSH BC
    PUSH AF
    LD A,$01                        ; report an overflow only once
    LD [FLGOVC],A
    POP AF
    EX DE,HL                        ; text pointer to DE meanwhile
    LD BC,$00FF                     ; B = digits after the point, C = $FF no point yet
    LD H,B
    LD L,B
    CALL Z,MAKINT                   ; FAC = integer 0, unless entered from FINDBL
    EX DE,HL
    LD A,[HL]                       ; first character of the number
    CP '&'                          ; an octal or hex constant
    JP Z,OCTCNS
    CP '-'                          ; leading minus sign?
    PUSH AF                         ; zero flag kept, to negate at the end
    JP Z,FIN_1                      ; skip past the sign
    CP '+'                          ; a leading plus is skipped too
    JP Z,FIN_1
    DEC HL                          ; no sign, so reread the first character
FIN_1:
    CALL CHRGTR                     ; next character, carry set for a digit
    JP C,FINDIG
    CP '.'                          ; decimal point
    JP Z,FINDP
    CP 'e'                          ; an exponent, lowercase or capital
    JP Z,FIN_2
    CP 'E'
FIN_2:
    JP NZ,FIN_5
    PUSH HL                         ; an E: does ELSE or EQV start here?
    CALL CHRGTR
    CP 'l'
    JP Z,FIN_3
    CP 'L'
    JP Z,FIN_3
    CP 'q'
    JP Z,FIN_3
    CP 'Q'
FIN_3:
    POP HL
    JP Z,FIN_4                      ; yes: the number ends before the E
    LD A,[VALTYP]                   ; an exponent: a double stays double
    CP $08
    JP Z,FINEX
    LD A,$00                        ; anything else becomes single
    JP FINEX
FIN_4:
    LD A,[HL]                       ; A = the E again, which ends the number
FIN_5:
    CP '%'                          ; % suffix makes it an integer
    JP Z,FININT
    CP '#'                          ; # suffix makes it double
    JP Z,FINDBF
    CP '!'                          ; ! suffix makes it single
    JP Z,FINSNF
    CP 'd'                          ; D: exponent, double precision
    JP Z,FINEX
    CP 'D'
    JP NZ,FINE                      ; none of these ends the number

;; Reads an exponent after its E or D, and goes on to scale the number by it.
;;
;; In:    A = nonzero for double precision, zero for single, HL = the text, at the E or D, SP = at the
;;          sign flags, under FINOVC
;; Entry: FINEC = reads the next exponent digit, with D $FF for a negative exponent and E the exponent so far
FINEX:
    OR A                            ; zero flag picks single precision, nonzero double
    CALL FINFRC                     ; make the FAC single or double
    CALL CHRGTR                     ; first character after the E or D
    CALL MINPLS                     ; a sign: D = $FF for minus, or reread a digit
FINEC:
    CALL CHRGTR                     ; next exponent character
    JP C,FINEDG                     ; add the digit into the exponent in E
    INC D                           ; D becomes zero if the exponent is negative
    JP NZ,FINE                      ; positive exponent
    XOR A                           ; negate the exponent
    SUB E
    LD E,A

;; Ends the number: scales it by its power of ten, applies its sign, and makes -32768 an integer.
;;
;; In:    E = the exponent, B = the digits after the point, HL = the text after the number, SP = at
;;          the sign flags, under FINOVC
;; Out:   HL = the text after the number, FAC = the number
FINE:
    PUSH HL
    LD A,E                          ; A = exponent less the digits after the point
    SUB B
    LD E,A
FINE2:
    CALL P,FINMUL                   ; positive: multiply by 10 once
    CALL M,FINDIV                   ; negative: divide by 10 once
    JP NZ,FINE2                     ; until the power of ten is used up
    POP HL
    POP AF                          ; zero flag from the leading minus test
    PUSH HL
    CALL Z,VNEG                     ; leading minus: negate
    POP HL
    CALL GETYPR                     ; 32768 parsed as a negative may need to be an int
    RET PE                          ; not single precision, so not -32768
    PUSH HL
    LD HL,POPHRT                    ; restores the text pointer either way
    PUSH HL
    CALL CONIS2                     ; becomes integer -32768 if that is the value
    RET

;; Handles a decimal point while parsing a number, ending the number at a second one.
;;
;; In:    C = $FF before the first point, HL = the text, at the point
FINDP:
    CALL GETYPR
    INC C                           ; C goes $FF to 0 on the first decimal point
    JP NZ,FINE                      ; a second decimal point ends the number
    CALL C,FINFRC                   ; an integer becomes single (the flags from the type test)
    JP FIN_1

;; Ends a number with a % suffix, making it an integer.
;;
;; In:    HL = the text, at the %, SP = at the sign flags, under FINOVC
FININT:
    CALL CHRGTR                     ; skip the %
    POP AF                          ; the sign flags
    PUSH HL
    LD HL,POPHRT                    ; last, restore the text pointer
    PUSH HL
    LD HL,FN_CINT                   ; before that, make it an integer
    PUSH HL
    PUSH AF                         ; the sign flags back for FINE
    JP FINE

;; Ends a number with a # (FINDBF) or ! (FINSNF) suffix, making it double or single precision.
;;
;; In:    HL = the text, at the suffix, zero = set for ! (from the compare)
;; Entry: FINSNF = zero = set for single precision, clear for double
FINDBF:
    OR A                            ; nonzero picks double precision for the # suffix
FINSNF:
    CALL FINFRC
    CALL CHRGTR                     ; skip the suffix
    JP FINE

;; Forces the FAC to single (zero set) or double (zero clear) precision.
;;
;; In:    zero = set for single precision, clear for double
;; Keeps: BC, DE, HL
FINFRC:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    CALL Z,FN_CSNG                  ; zero from the caller selects single precision
    POP AF
    CALL NZ,FN_CDBL                 ; nonzero selects double precision instead
    POP BC
    POP DE
    POP HL
    RET

;; Returns if zero is set; otherwise multiplies the FAC by 10 and decrements A.
;;
;; In:    A = the power of ten still to apply, zero = set if none
;; Out:   A = one less, zero = set if it is used up
;; Entry: FINMLT = multiplies without testing zero
FINMUL:
    RET Z                           ; nothing left to scale
FINMLT:
    PUSH AF
    CALL GETYPR
    PUSH AF                         ; keep the type flags for the second test
    CALL PO,MUL10                   ; single: times 10
    POP AF
    CALL PE,DMUL10                  ; double: times 10
    POP AF

;; Decrements A and returns.
;;
;; In:    A = a count
;; Out:   A = the count less 1, zero = set if it is used up
DCRART:
    DEC A
    RET

;; Divides the FAC by 10 and increments A.
;;
;; In:    A = the negative power of ten still to apply
;; Out:   A = one more, zero = set if it is used up
;; Keeps: DE, HL
FINDIV:
    PUSH DE
    PUSH HL
    PUSH AF
    CALL GETYPR
    PUSH AF                         ; keep the type flags for the second test
    CALL PO,DIV10                   ; single: divided by 10
    POP AF
    CALL PE,DDIV10                  ; double: divided by 10
    POP AF
    POP HL
    POP DE
    INC A                           ; one fewer digit past the decimal point to undo
    RET

;; Adds the digit at HL into the number being parsed, as an integer while it fits, else as a single or
;; double.
;;
;; In:    HL = the text, at the digit, carry = set, B = the digits after the point, C = $FF before the
;;          point and 0 after
;; Out:   B = the digits after the point, this one included if it follows the point (going on at FIN_1)
FINDIG:
    PUSH DE
    LD A,B                          ; C is $FF before the point and 0 after, carry is set for a digit
    ADC A,C
    LD B,A                          ; B counts this digit only if it follows the decimal point
    PUSH BC
    PUSH HL
    LD A,[HL]
    SUB '0'                         ; A = the digit's value 0 to 9
    PUSH AF
    CALL GETYPR
    JP P,FINDGV
    LD HL,[FACLO]
    LD DE,$0CCD                     ; 3277: above this, ten times the value overflows an integer
    CALL DCOMPR
    JP NC,FINDG2                    ; too big to stay an integer, switch to single precision
    LD D,H
    LD E,L
    ADD HL,HL                       ; HL = value times 4
    ADD HL,HL
    ADD HL,DE                       ; HL = value times 5
    ADD HL,HL                       ; HL = value times 10
    POP AF
    LD C,A                          ; BC = digit, B is 0 since an integer has no decimal point
    ADD HL,BC
    LD A,H
    OR A
    JP M,FINDG1                     ; sign bit set means 32767 was exceeded
    LD [FACLO],HL
FINDGE:
    POP HL
    POP BC
    POP DE
    JP FIN_1
FINDG1:
    LD A,C                          ; put the digit back on the stack for the single-precision path
    PUSH AF
FINDG2:
    CALL CONSI                      ; the integer to single precision
    SCF                             ; carry tells FINDGV the value is single, not double
FINDGV:
    JP NC,FINDGD                    ; no carry means the value is already double precision
    LD BC,$9474                     ; BCDE = 1E6 in single precision
    LD DE,$2400
    CALL FCOMP
    JP P,FINDG3                     ; a seventh digit would lose precision in single, go double
    CALL MUL10                      ; times 10
    POP AF                          ; A = the digit value
    CALL FINLOG                     ; plus the digit
    JP FINDGE
FINDG3:
    CALL CONDS                      ; to double precision
FINDGD:
    CALL DMUL10
    CALL VMOVAF                     ; move the scaled value to ARG for the addition
    POP AF                          ; A = the digit value
    CALL FLOAT                      ; float it
    CALL CONDS                      ; as a double
    CALL DADD                       ; value = value * 10 + digit
    JP FINDGE

;; Adds the signed byte in A to the single-precision FAC.
;;
;; In:    A = the byte, FAC = a single-precision number
;; Out:   FAC = the sum
FINLOG:
    CALL PUSHF                      ; the FAC to the stack
    CALL FLOAT                      ; FAC = A, floated

;; Pops a single-precision number off the stack into BCDE and adds it to the FAC.
;;
;; In:    SP = at the number, under the return address
;; Out:   FAC = the FAC plus the number
FADDT:
    POP BC                          ; BCDE = the saved number off the stack
    POP DE
    JP FADD

;; Adds a digit into the exponent being parsed in E, capping the exponent at 127 past two digits.
;;
;; In:    E = the exponent so far, HL = the text, at the digit
;; Out:   E = the exponent with the digit added, or 127 (going on at FINEC)
FINEDG:
    LD A,E
    CP $0A                          ; exponent already two digits long
    JP NC,FINEDO
    RLCA                            ; A = exponent times 4
    RLCA
    ADD A,E                         ; A = exponent times 5
    RLCA                            ; A = exponent times 10
    ADD A,[HL]
    SUB '0'                         ; remove the ASCII bias from the digit just added
    LD E,A
    .byte $FA                       ; JP M,nn: skips the LD E,$7F (not taken: the exponent is under 100)
FINEDO:
    LD E,$7F                        ; cap at 127, already far past the range of any number
    JP FINEC

;; Reports an overflow in a multiply or divide, the result's sign being the operands' signs combined.
;;
;; In:    FAC = the first operand, C = the second's high byte (single precision) or ARG's (double)
;; Out:   FAC = the largest number of that sign
;; Errors: OV error if error trapping is on
;; See:   <OVFLS>
MLDVOV:
    PUSH HL
    LD HL,FACHI                     ; the FAC's sign
    CALL GETYPR
    JP PO,MLDVOV_1
    LD A,[ARGHI]                    ; double: ARG's sign
    JP MLDVOV_2
MLDVOV_1:
    LD A,C                          ; single: the sign in C
MLDVOV_2:
    XOR [HL]                        ; the result's sign into carry
    RLA
    POP HL
    JP OVFLS

;; Drops two words from the stack and reports an overflow with the FAC's sign.
;;
;; Entry: FACOVF = drops nothing
;; See:   <OVFLS>
FACOVP:
    POP AF
    POP AF
FACOVF:
    LD A,[FACHI]                    ; the FAC's sign into carry
    RLA
    JP OVFLS

;; Drops a word from the stack and reports an overflow with the sign of the unpacked FAC.
;;
;; Entry: UNPOVF = drops nothing: the overflow of an add, round or multiply on the unpacked FAC
;; See:   <OVFLS>
UNPOVP:
    POP AF
UNPOVF:
    LD A,[FAC_SIGN_TEMP]            ; the complemented sign
    CPL
    RLA                             ; the sign into carry
    JP OVFLS

;; Reports a division by zero, the sign of the infinity being C's top bit (a single-precision divide).
;;
;; Entry: DDIV0S = the sign is ARG's (a double-precision divide), DIV0S = the sign is in A's top bit
;; See:   <OVFLS>
FDIV0S:
    LD A,C
    JP DIV0S
DDIV0S:
    LD A,[ARGHI]
DIV0S:
    RLA                             ; the sign into carry
    LD HL,DIVMSG                    ; "Division by zero" instead of "Overflow"
    LD [OVERRI],HL

;; Handles an overflow or a division by zero, as an error if error trapping is on, otherwise as a warning.
;;
;; Without trapping, the message (OVERRI) is printed, unless FLGOVC says one was printed already during FIN
;; or a function; then the FAC is set to the largest number of the result's sign, and the arithmetic goes
;; on. OVERRI is set back to "Overflow" either way.
;;
;; In:    carry = set if the result is negative, OVERRI = the message
;; Out:   FAC = the largest number of that sign, for its type
;; Errors: OV or /0 error if error trapping is on (ONELIN is nonzero)
;; Keeps: AF, BC, DE, HL
OVFLS:
    PUSH HL
    PUSH BC
    PUSH DE
    PUSH AF
    PUSH AF                         ; the sign, for choosing the infinity
    LD HL,[ONELIN]                  ; trapping errors?
    LD A,H
    OR L
    JP NZ,OVFLS_2                   ; yes: no message
    LD HL,FLGOVC                    ; 0 always prints, 1 prints once, 2 not again
    LD A,[HL]
    OR A
    JP Z,OVFLS_1
    DEC A
    JP NZ,OVFLS_2
    INC [HL]                        ; 1 becomes 2
OVFLS_1:
    LD HL,[OVERRI]                  ; print the message
    CALL STRPRN
    LD [TTYPOS],A
    LD A,$0D                        ; carriage return
    CALL CALTTY
    LD A,$0A                        ; line feed
    CALL CALTTY
OVFLS_2:
    POP AF                          ; carry = the sign
    LD HL,FACLO
    LD DE,INFP
    JP NC,OVFLS_3
    LD DE,INFM
OVFLS_3:
    CALL MOVE                       ; the largest single of that sign
    CALL GETYPR
    JP C,OVFLS_4                    ; not double precision
    LD HL,DFACLO                    ; double: its low four bytes all ones
    LD DE,INFM
    CALL MOVE
OVFLS_4:
    LD HL,[ONELIN]
    LD A,H
    OR L
    LD HL,[OVERRI]                  ; HL = the message used
    LD DE,OVRMSG
    EX DE,HL
    LD [OVERRI],HL                  ; back to "Overflow" for next time
    JP Z,OVFLS_5                    ; not trapping: carry on
    CALL DCOMPR                     ; trapping: which error?
    JP Z,OVERR
    JP DV0ERR
OVFLS_5:
    POP AF
    POP DE
    POP BC
    POP HL
    RET

;; Holds the largest positive single-precision number, which OVFLS gives for an overflow.
INFP:
    .byte $FF, $FF, $7F, $FF        ; 1.70141E+38

;; Holds the largest negative single-precision number, whose bytes also fill a double's low half.
INFM:
    .byte $FF, $FF, $FF, $FF        ; -1.70141E+38
