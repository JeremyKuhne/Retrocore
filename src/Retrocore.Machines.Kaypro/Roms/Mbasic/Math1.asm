;; MBASIC 5.21: RANDOMIZE, THE LOOP SCANS AND THE MATH PACKAGE, PART 1
;;
;; The end of the interpreter's statements, then the start of Microsoft's math package: single-precision
;; arithmetic, the floating accumulator's moves and tests, and the conversions between the numeric types. In order:
;;
;; - ST_RANDOMIZE sets the seed RND starts from, asking for it with RANMES when the statement gives none.
;; - NXTSCN and WNDSCN scan ahead from a FOR or WHILE for the NEXT or WEND that matches it, counting nested
;;   loops, so that a loop that runs no times can be skipped.
;; - FINOVC and CLROVC keep and clear FLGOVC, which says whether an overflow's message has been printed.
;; - FADD, FSUB and their entries FADDH, FADDS and FSUBS add and subtract single-precision numbers. They share
;;   NORMAL, which normalizes a result and rounds it (ROUND) into the accumulator, and SHIFTR, which aligns a
;;   mantissa.
;; - FN_LOG takes the natural logarithm through LOG2, a rational approximation of the base-2 logarithm.
;; - FMULT, FDIV, MUL10 and DIV10 multiply and divide, with MULDIV combining the exponents.
;; - SIGN, VSIGN and ISIGN give the sign of the accumulator; FN_ABS, FN_SGN, VNEG and NEG are built on them.
;; - PUSHF, the MOV routines (MOVFM, MOVFR, MOVRF, MOVRM, MOVMF) and the VMOV routines, sized by VALTYP, move
;;   numbers between the accumulator, BCDE, the stack, ARG and memory. UNPACK restores a mantissa's hidden bit.
;; - FCOMP, ICOMP and DCOMPD compare single-precision, integer and double-precision numbers.
;; - FN_CINT, FN_CSNG and FN_CDBL convert between the numeric types, with CONIS, CONSD, CONSI, CONDS and QINT
;;   doing the work, and MAKINT, VALINT, VALSNG and VALDBL setting VALTYP.
;;
;; Numbers are in Microsoft's binary format. A single-precision number is four bytes: the low, middle and high
;; bytes of the mantissa, then the exponent. The mantissa is a fraction from 0.5 to 1 whose top bit, always
;; set, holds the sign instead (set for negative); the exponent is the power of two plus $80, and an exponent of
;; zero is the number zero. A double-precision number has four more mantissa bytes below. The accumulator is
;; DFACLO (a double's low four bytes), FACLO, FACHI (the high byte and sign) and FAC (the
;; exponent); FAC_SIGN_TEMP holds the result's sign while arithmetic runs. An integer is in FACLO. ARG, the second
;; double-precision operand, is ARGLO to ARG.
;;
;; Unlike Level II BASIC's, MBASIC's overflow and division by zero are not errors: they go to the handlers in
;; Math2.asm (MLDVOV, FACOVF, UNPOVP, UNPOVF and FDIV0S), which print a message and go on with the largest
;; number. The multiply and divide keep their operands in their own instructions, which they patch, and keep a
;; sticky bit for rounding. LOG uses Hart's approximation 2524, as GW-BASIC's does, rather than Level II's series.
;;
;; GW-BASIC's GWMAIN.ASM ends with RANDOM, the scans and the overflow flag routines. Its 8086 math package
;; (MATH1.ASM and MATH2.ASM) was rewritten, so the math's names come from Level II BASIC's (Level2.asm), the same
;; Z80 code. Runs at $2487-$2A6C. The main entry points are FADD, FSUB, FMULT, FDIV, FCOMP, ICOMP, the MOV and
;; VMOV routines, FN_CINT (FRCINT), FN_CSNG (FRCSNG), FN_CDBL (FRCDBL) and CONIS; the double-precision
;; arithmetic, INT and the conversions to and from text are in Math2.asm.

;; Sets the random number seed (the RANDOMIZE statement).
;;
;; With no argument, it prints RANMES and reads a number from the keyboard, asking again until the line holds
;; only a number. The seed is the number as an integer, stored in the middle bytes of the seed at RNDXM.
;;
;; In:    HL = the text after RANDOMIZE, zero = set at the end of the statement
;; Out:   HL = the text after the statement
;; Errors: ?OV ERROR for a seed outside -32768 to 32767; Control-C at the prompt stops the program
ST_RANDOMIZE:
    JP Z,INPRG                      ; no argument: ask for one
    CALL FRMEVL
    PUSH HL
    CALL FN_CINT
    JP STRNDS
INPRG:
    PUSH HL                         ; keep the text pointer
INPRAG:
    LD HL,RANMES                    ; ask for a seed
    CALL STROUT
    CALL QINLIN                     ; read a line
    POP DE                          ; DE = the text pointer
    JP C,STPEND                     ; Control-C: stop
    PUSH DE
    INC HL                          ; past BUFMIN to the line typed
    LD A,[HL]                       ; FIN wants the first character in A
    CALL FIN                        ; read a number
    LD A,[HL]
    OR A                            ; anything after it: ask again
    JP NZ,INPRAG
    CALL FN_CINT
STRNDS:
    LD [RNDXM],HL                   ; the seed's middle bytes
    CALL RNDMN2                     ; start the sequence again
    POP HL
    RET

;; The prompt RANDOMIZE prints when it has no argument.
RANMES:
    .byte "Random number seed (-32768 to 32767)", 0

;; Scans ahead from a WHILE for the WEND that matches it.
;;
;; In:    HL = the text after WHILE
;; Out:   HL = the text at the WEND, NXTLIN = the WEND's line number
;; Errors: WHILE without WEND (29) when the program ends first
;; See:   <NXTSCN>
WNDSCN:
    LD C,$1D                        ; WHILE without WEND
    JP SCNCNT

;; Scans ahead from a FOR for the NEXT that matches it, so a loop that runs no times can be skipped.
;;
;; Statements are skipped one at a time, the scan stepping into the statement after a THEN or ELSE, and the
;; nesting is counted in B: each FOR (or WHILE) adds one and each NEXT (or WEND) takes one off. The variables
;; of a NEXT are skipped one by one, since NEXT J,I closes two loops. While it looks at a NEXT, CURLIN is set
;; to the NEXT's line, so an error in its variables is reported there.
;;
;; In:    HL = the text after the FOR statement
;; Out:   HL = the text at the matching NEXT, about to read its variable, NXTLIN = the NEXT's line number
;; Errors: FOR without NEXT (26) when the program ends first
;; Entry: SCNCNT = scans for the error number in C, FOR without NEXT or WHILE without WEND
NXTSCN:
    LD C,$1A                        ; FOR without NEXT
SCNCNT:
    LD B,$00                        ; B counts the loops open
    EX DE,HL
    LD HL,[CURLIN]                  ; the NEXT may be on this line
    LD [NXTLIN],HL
    EX DE,HL
FORINC:
    INC B                           ; one more loop open
FNLOP:
    DEC HL
SCANWF:
    CALL CHRGTR                     ; skip to the end of the statement
    JP Z,FORTRM
    CP $A2                          ; ELSE
    JP Z,FNNWST
    CP $CF                          ; THEN
    JP NZ,SCANWF
FORTRM:
    OR A                            ; a colon: look at the next statement
    JP NZ,FNNWST
    INC HL                          ; the end of a line: is it the program's end?
    LD A,[HL]
    INC HL
    OR [HL]                         ; a link of zero
    LD E,C                          ; E = the error, if it is
    JP Z,ERROR
    INC HL                          ; DE = the next line's number
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [NXTLIN],HL
    EX DE,HL
FNNWST:
    CALL CHRGTR                     ; the statement's keyword
    LD A,C
    CP $1A                          ; scanning for NEXT or for WEND?
    LD A,[HL]
    JP Z,NXTLOK
    CP $B4                          ; WHILE: one more open
    JP Z,FORINC
    CP $B5                          ; WEND
    JP NZ,FNLOP
    DEC B                           ; it closes a loop: the last one?
    JP NZ,FNLOP
    RET
NXTLOK:
    CP $82                          ; FOR: one more open
    JP Z,FORINC
    CP $83                          ; NEXT
    JP NZ,FNLOP
DECNXT:
    DEC B                           ; it closes a loop: the last one?
    RET Z
    CALL CHRGTR                     ; does the NEXT name a variable?
    JP Z,FORTRM                     ; no: it closes only this loop
    EX DE,HL
    LD HL,[CURLIN]                  ; keep CURLIN
    PUSH HL
    LD HL,[NXTLIN]                  ; errors in the variable come from the NEXT's line
    LD [CURLIN],HL
    EX DE,HL
    PUSH BC
    CALL PTRGET                     ; skip the variable's name
    POP BC
    DEC HL
    CALL CHRGTR
    LD DE,FORTRM                    ; the end of the NEXT: go on scanning
    JP Z,TRMNXT
    CALL SYNCHR
    .byte ','
    DEC HL                          ; another variable: it closes another loop
    LD DE,DECNXT
TRMNXT:
    EX [SP],HL                      ; restore CURLIN, keeping the text pointer
    LD [CURLIN],HL
    POP HL
    PUSH DE                         ; go on at DE
    RET

;; Copies FLGOVC to OVCSTR, then clears FLGOVC, so a caller can tell whether FIN overflowed.
;;
;; FLGOVC is zero normally, when every overflow prints its message. Function calls, FIN and exponentiation set
;; it to 1, and after one overflow it becomes 2, so a calculation prints the message only once.
;;
;; Keeps: AF, BC, DE, HL
FINOVC:
    PUSH AF
    LD A,[FLGOVC]
    LD [OVCSTR],A
    POP AF

;; Clears FLGOVC, so every overflow prints its message again.
;;
;; Keeps: AF, BC, DE, HL
CLROVC:
    PUSH AF
    XOR A
    LD [FLGOVC],A
    POP AF
    RET

;; Adds one half to the single-precision accumulator.
FADDH:
    LD HL,FHALF

;; Adds the single-precision number at HL to the accumulator.
;;
;; In:    HL = the number
FADDS:
    CALL MOVRM
    JP FADD

;; Subtracts the accumulator from the single-precision number at HL, leaving the difference in the accumulator.
;;
;; In:    HL = the number
FSUBS:
    CALL MOVRM

;; Subtracts the single-precision accumulator from BCDE, leaving the difference in the accumulator.
;;
;; In:    BC/DE = the number
FSUB:
    CALL NEG

;; Adds BCDE to the single-precision accumulator, leaving the sum in the accumulator.
;;
;; The smaller number is shifted right to line up with the larger, and the mantissas are added or, if the signs
;; differ, subtracted; NORMAL then normalizes and rounds the result.
;;
;; In:    BC/DE = the number
FADD:
    LD A,B
    OR A                            ; BCDE is zero: the accumulator is the sum
    RET Z
    LD A,[FAC]
    OR A
    JP Z,MOVFR                      ; the accumulator is zero: the sum is BCDE
    SUB B                           ; the difference of the exponents
    JP NC,FADD1                     ; the accumulator is the larger already
    CPL                             ; make the difference positive
    INC A
    EX DE,HL                        ; swap the two, so BCDE is the smaller
    CALL PUSHF
    EX DE,HL
    CALL MOVFR
    POP BC
    POP DE

;; Adds the smaller number BCDE to the accumulator, A bits apart, for FADD.
;;
;; In:    BC/DE = the smaller number, A = the difference of the exponents
FADD1:
    CP $19                          ; 25 or more bits apart: BCDE adds nothing
    RET NC
    PUSH AF                         ; keep the shift
    CALL UNPACK                     ; restore the hidden bits, A = the signs compared
    LD H,A                          ; keep the comparison
    POP AF
    CALL SHIFTR                     ; line BCDE up with the accumulator
    LD A,H
    OR A
    LD HL,FACLO
    JP P,FADD3                      ; the signs differ: subtract
    CALL FADDA                      ; the same sign: add the mantissas
    JP NC,ROUND                     ; no carry out: round it
    INC HL
    INC [HL]                        ; a carry out raises the exponent
    JP Z,UNPOVF                     ; too large: overflow
    LD L,$01                        ; take the carry in with a one-bit shift
    CALL SHRADD
    JP ROUND

;; Subtracts the mantissa CDEB from the accumulator's for FADD, then normalizes and rounds the difference.
;;
;; In:    HL = FACLO, C/DE/B = the mantissa to subtract
FADD3:
    XOR A                           ; B = 0 minus the extra low byte
    SUB B
    LD B,A
    LD A,[HL]                       ; subtract with borrow, a byte at a time
    SBC A,E
    LD E,A
    INC HL
    LD A,[HL]
    SBC A,D
    LD D,A
    INC HL
    LD A,[HL]
    SBC A,C
    LD C,A

;; Negates the mantissa CDEB when carry is set, then normalizes and rounds it into the accumulator.
;;
;; In:    C/DE/B = the mantissa, carry = set to negate it
FADFLT:
    CALL C,NEGR                     ; a borrow: the result changed sign

;; Normalizes the mantissa CDEB and rounds it into the single-precision accumulator.
;;
;; The mantissa is shifted left a byte at a time while its top byte is zero, then a bit at a time until its top
;; bit is set, and the exponent lowered to match. A mantissa of zero, or an exponent that falls below the
;; smallest, makes the accumulator zero.
;;
;; In:    C/DE/B = the mantissa, FAC = its exponent, FAC_SIGN_TEMP = its sign in bit 7
NORMAL:
    LD L,B                          ; HL holds the low bytes while shifting
    LD H,E
    XOR A                           ; A = the shift so far, in bits
NORM1:
    LD B,A
    LD A,C
    OR A                            ; the top byte is not zero: shift by bits
    JP NZ,NORM3
    LD C,D                          ; shift the mantissa up a whole byte
    LD D,H
    LD H,L
    LD L,A
    LD A,B
    SUB $08                         ; eight more bits of shift
    CP $E0                          ; shifted 32 bits: the mantissa was zero
    JP NZ,NORM1

;; Makes the single-precision accumulator zero by clearing its exponent.
;;
;; Out:   A = 0
;; Entry: ZERO0 = stores A as the exponent
ZERO:
    XOR A
ZERO0:
    LD [FAC],A
    RET

;; Shifts NORMAL's mantissa left a bit at a time until its top bit is set, then lowers the exponent and rounds.
;;
;; When the lower bytes are zero, the top byte is shifted alone.
;;
;; In:    C, D, H, L = the mantissa, top byte first, B = the shift so far, negative
;; Entry: NORM2 = shifts by a bit first, NORM3 = tests the top bit first, NORMAL_3 = finishes with the shift in B
NORMAL_1:
    LD A,H
    OR L
    OR D                            ; are the lower bytes zero?
    JP NZ,NORM2
    LD A,C
NORMAL_2:
    DEC B                           ; one more bit of shift
    RLA
    JP NC,NORMAL_2                  ; until a one leaves the top
    INC B                           ; that shift was one too many
    RRA                             ; put the one back
    LD C,A
    JP NORMAL_3
NORM2:
    DEC B                           ; one more bit of shift
    ADD HL,HL                       ; shift the mantissa left a bit
    LD A,D
    RLA
    LD D,A
    LD A,C
    ADC A,A
    LD C,A
NORM3:
    JP P,NORMAL_1                   ; until the top bit is set
NORMAL_3:
    LD A,B                          ; A = the total shift, negative
    LD E,H                          ; back into CDEB
    LD B,L
    OR A
    JP Z,ROUND                      ; no shift: just round
    LD HL,FAC
    ADD A,[HL]                      ; lower the exponent by the shift
    LD [HL],A
    JP NC,ZERO                      ; below the smallest exponent: zero
    JP Z,ZERO

;; Rounds the mantissa CDE by the top bit of B and stores the number in the accumulator with its sign.
;;
;; In:    C/DE = the mantissa, B = the bits below it, FAC = the exponent, FAC_SIGN_TEMP = the sign in bit 7
;; Entry: ROUNDB = rounds by the top bit of A instead
ROUND:
    LD A,B                          ; the top bit of B decides the rounding
ROUNDB:
    LD HL,FAC
    OR A
    CALL M,ROUNDA                   ; round up when it is $80 or more
    LD B,[HL]                       ; B = the exponent
    INC HL
    LD A,[HL]
    AND $80                         ; the result's sign
    XOR C                           ; in place of the mantissa's top bit
    LD C,A
    JP MOVFR

;; Increments the mantissa CDE for rounding, raising the exponent at HL when it wraps.
;;
;; In:    C/DE = the mantissa, HL = FAC
;; Out:   C/DE = the mantissa plus one
ROUNDA:
    INC E
    RET NZ
    INC D
    RET NZ
    INC C
    RET NZ
    LD C,$80                        ; the mantissa wrapped: make it $800000
    INC [HL]                        ; and raise the exponent
    RET NZ
    JP UNPOVP                       ; the exponent overflowed

;; Adds the mantissa at HL to CDE.
;;
;; In:    HL = the mantissa's low byte, C/DE = the mantissa to add to
;; Out:   C/DE = the sum, carry = set on a carry out, HL = the mantissa's high byte
;; Keeps: B
FADDA:
    LD A,[HL]
    ADD A,E
    LD E,A
    INC HL
    LD A,[HL]
    ADC A,D
    LD D,A
    INC HL
    LD A,[HL]
    ADC A,C
    LD C,A
    RET

;; Negates the mantissa CDEB and complements the result's sign in FAC_SIGN_TEMP.
;;
;; In:    C/DE/B = the mantissa
;; Out:   C/DE/B = its negation
;; Uses:  A, HL
NEGR:
    LD HL,FAC_SIGN_TEMP             ; the result's sign
    LD A,[HL]
    CPL                             ; flip it
    LD [HL],A
    XOR A                           ; A and L = 0, to subtract from
    LD L,A
    SUB B                           ; negate CDEB as one 32-bit number
    LD B,A
    LD A,L
    SBC A,E
    LD E,A
    LD A,L
    SBC A,D
    LD D,A
    LD A,L
    SBC A,C
    LD C,A
    RET

;; Shifts the mantissa CDEB right by A bits, collecting the bits shifted out in B for rounding.
;;
;; Whole bytes go first. When only C has bits left, it is shifted alone until a one leaves it.
;;
;; In:    C/DE = the mantissa, A = the number of bits
;; Out:   C/DE/B = the mantissa shifted
;; Uses:  A, L
;; Keeps: H
;; Entry: SHRADD = rotates carry into C and shifts the rest, for L - 1 more bits
SHIFTR:
    LD B,$00                        ; B collects the bits shifted out
SHFTR1:
    SUB $08                         ; 8 or more bits still to shift?
    JP C,SHFTR2                     ; fewer: shift by bits
    LD B,E                          ; move the mantissa down a whole byte
    LD E,D
    LD D,C
    LD C,$00
    JP SHFTR1
SHFTR2:
    ADD A,$09                       ; L = the bits still to shift, plus one
    LD L,A
    LD A,D
    OR E
    OR B                            ; only C has bits: shift it alone
    JP NZ,SHFTR3
    LD A,C
SHIFTR_1:
    DEC L
    RET Z
    RRA
    LD C,A
    JP NC,SHIFTR_1                  ; until a one leaves C
    JP SHIFTR_2                     ; then carry it into the rest
SHFTR3:
    XOR A                           ; clear carry, so a zero enters the top
    DEC L
    RET Z
    LD A,C
SHRADD:
    RRA                             ; carry enters the top byte
    LD C,A
SHIFTR_2:
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    LD A,B
    RRA
    LD B,A
    JP SHFTR3                       ; the next bit

;; The single-precision constant 1.0.
FONE:
    .byte $00, $00, $00, $81

;; The numerator P of LOG2's approximation, Hart's 2524: a count of 4, then the coefficients, highest power
;; first.
LOGP:
    .byte 4
    .byte $9A, $F7, $19, $83        ; 4.8114746
    .byte $24, $63, $43, $83        ; 6.105852
    .byte $75, $CD, $8D, $84        ; -8.86266
    .byte $A9, $7F, $83, $82        ; -2.054667

;; The denominator Q of LOG2's approximation: a count of 4, then the coefficients, highest power first.
LOGQ:
    .byte 4
    .byte $00, $00, $00, $81        ; 1.0
    .byte $E2, $B0, $4D, $83        ; 6.427842
    .byte $0A, $72, $11, $83        ; 4.545171
    .byte $F4, $04, $35, $7F        ; 0.3535534

;; Replaces the single-precision accumulator with its natural logarithm (the LOG function).
;;
;; Errors: ?FC ERROR when the argument is zero or negative
FN_LOG:
    CALL SIGN
    OR A                            ; parity even: zero or -1
    JP PE,FCERR                     ; no logarithm of zero or less
    CALL LOG2
    LD BC,$8031                     ; BCDE = ln 2, 0.6931472
    LD DE,$7218
    JP FMULT

;; Replaces the single-precision accumulator with its base-2 logarithm.
;;
;; The exponent is the logarithm's whole part. The mantissa, as a number x from 0.5 to 1, gives the rest as
;; P(x) / Q(x), from LOGP and LOGQ.
;;
;; In:    FAC = the argument's exponent, not zero, FACHI = its high byte, positive
LOG2:
    CALL MOVRF                      ; BCDE = the argument
    LD A,$80
    LD [FAC],A                      ; the accumulator = the mantissa, x
    XOR B                           ; A = the exponent, less the bias
    PUSH AF
    CALL PUSHF                      ; keep x
    LD HL,LOGP
    CALL POLY                       ; P(x)
    POP BC                          ; BCDE = x
    POP HL
    CALL PUSHF                      ; keep P(x)
    EX DE,HL
    CALL MOVFR                      ; the accumulator = x
    LD HL,LOGQ
    CALL POLY                       ; Q(x)
    POP BC                          ; BCDE = P(x)
    POP DE
    CALL FDIV                       ; P(x) / Q(x)
    POP AF
    CALL PUSHF
    CALL FLOAT                      ; the exponent as a number
    POP BC
    POP DE
    JP FADD                         ; plus the fraction

;; Multiplies BCDE by the single-precision accumulator, leaving the product in the accumulator.
;;
;; The multiplicand's mantissa is patched into FMLTT1 and FMLTT2. FMULT2 runs once for each of the accumulator's
;; three mantissa bytes, low byte first, through the return addresses pushed, then NORMAL rounds the product.
;;
;; In:    BC/DE = the multiplicand
FMULT:
    CALL SIGN
    RET Z                           ; the accumulator is zero: so is the product
    LD L,$00                        ; L = 0: a multiply
    CALL MULDIV
    LD A,C                          ; patch in the multiplicand's mantissa
    LD [FMLTT1],A
    EX DE,HL
    LD [FMLTT2],HL
    LD BC,$0000                     ; the product, CDEB, starts at zero
    LD D,B
    LD E,B
    LD HL,NORMAL                    ; after the last byte, normalize
    PUSH HL
    LD HL,FMULT2                    ; FMULT2 three times in all
    PUSH HL
    PUSH HL
    LD HL,FACLO                     ; from the accumulator's low byte
FMULT2:
    LD A,[HL]                       ; A = the next multiplier byte
    INC HL
    OR A
    JP Z,FMULT3                     ; zero: just shift the product a byte
    PUSH HL
    EX DE,HL                        ; the product in CHLB meanwhile
    LD E,$08                        ; E counts the bits
FMULT4:
    RRA                             ; the next multiplier bit into carry
    LD D,A                          ; D = the bits still to test
    LD A,C
    JP NC,FMULT5                    ; clear: only shift the product
    PUSH DE
FMLTT2 = * + 1                      ;; the multiplicand's low and middle bytes, patched in by FMULT
    LD DE,$0000                     ; add the multiplicand to the product
    ADD HL,DE
    POP DE
FMLTT1 = * + 1                      ;; the multiplicand's high byte, patched in by FMULT
    ADC A,$00
FMULT5:
    RRA                             ; shift the product right, carry entering the top
    LD C,A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    LD A,B
    RRA
    LD B,A
    AND $10                         ; once a one reaches bit 4, keep bit 5 set: a sticky bit for rounding
    JP Z,FMULT_1
    LD A,B
    OR $20
    LD B,A
FMULT_1:
    DEC E
    LD A,D                          ; A = the bits left
    JP NZ,FMULT4
    EX DE,HL                        ; the product back in CDEB

;; Pops HL and returns.
POPHRT:
    POP HL
    RET

;; Shifts the product CDEB right a whole byte for FMULT, for a multiplier byte of zero.
;;
;; In:    A = 0
FMULT3:
    LD B,E
    LD E,D
    LD D,C
    LD C,A
    RET

;; Divides the single-precision accumulator by 10.
;;
;; Entry: FDIVT = divides the number pushed with PUSHF, under the return address, by the accumulator
DIV10:
    CALL PUSHF                      ; push the dividend
    LD HL,FTEN
    CALL MOVFM                      ; the accumulator = 10
FDIVT:
    POP BC                          ; BCDE = the dividend
    POP DE

;; Divides BCDE by the single-precision accumulator, leaving the quotient in the accumulator.
;;
;; The divisor's mantissa is patched into FDIVC, FDIVB and FDIVA. Each pass subtracts it from the remainder if it
;; fits, giving one bit of the quotient, until the quotient's top bit is set. The next bit then rounds it, with a
;; sticky bit for any remainder.
;;
;; In:    BC/DE = the dividend
FDIV:
    CALL SIGN
    JP Z,FDIV0S                     ; division by zero
    LD L,$FF                        ; L = $FF: a divide
    CALL MULDIV
    INC [HL]                        ; the exponent plus 2, for the loop
    JP Z,MLDVOV                     ; overflow
    INC [HL]
    JP Z,MLDVOV
    DEC HL                          ; patch in the divisor's mantissa
    LD A,[HL]
    LD [FDIVA],A
    DEC HL
    LD A,[HL]
    LD [FDIVB],A
    DEC HL
    LD A,[HL]
    LD [FDIVC],A
    LD B,C                          ; BHL = the dividend, the remainder so far
    EX DE,HL
    XOR A                           ; CDE collects the quotient
    LD C,A
    LD D,A
    LD E,A
    LD [FDIVG],A                    ; the remainder's extra byte
FDIV1:
    PUSH HL                         ; keep the remainder, in case the divisor does not fit
    PUSH BC
    LD A,L
FDIVC = * + 1                       ;; the divisor's low byte, patched in by FDIV
    SUB $00                         ; subtract the divisor from the remainder
    LD L,A
    LD A,H
FDIVB = * + 1                       ;; the divisor's middle byte, patched in by FDIV
    SBC A,$00
    LD H,A
    LD A,B
FDIVA = * + 1                       ;; the divisor's high byte, patched in by FDIV
    SBC A,$00
    LD B,A
FDIVG = * + 1                       ;; the remainder's extra top byte, kept by FDIV
    LD A,$00
    SBC A,$00
    CCF
    JP NC,FDIV2                     ; a borrow: it did not fit
    LD [FDIVG],A                    ; it fitted: keep the new remainder
    POP AF                          ; drop the old one
    POP AF
    SCF                             ; this quotient bit is a one
    .byte $D2                       ; JP NC,nn: skips the POPs, as carry is set
FDIV2:
    POP BC                          ; restore the remainder
    POP HL
    LD A,C                          ; is the quotient's top bit set yet?
    INC A
    DEC A
    RRA                             ; the new bit aside, keeping the sign of C
    JP P,FDIV_2
    RLA                             ; the quotient is complete: the new bit rounds it
    LD A,[FDIVG]
    RRA
    AND $C0                         ; the rounding bit, and the remainder's top bit
    PUSH AF
    LD A,B
    OR H
    OR L                            ; anything left over?
    JP Z,FDIV_1
    LD A,$20                        ; yes: the sticky bit
FDIV_1:
    POP HL                          ; H = the rounding bits
    OR H
    JP ROUNDB
FDIV_2:
    RLA                             ; carry = the new quotient bit
    LD A,E                          ; shift it into the quotient CDE
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,C
    RLA
    LD C,A
    ADD HL,HL                       ; shift the remainder left
    LD A,B
    RLA
    LD B,A
    LD A,[FDIVG]
    RLA
    LD [FDIVG],A
    LD A,C                          ; any quotient bit set yet?
    OR D
    OR E
    JP NZ,FDIV1                     ; yes: go on dividing
    PUSH HL
    LD HL,FAC                       ; no, a leading zero: lower the exponent instead
    DEC [HL]
    POP HL
    JP NZ,FDIV1
    JP ZERO                         ; it ran out: the quotient is zero

;; Combines the exponents of ARG and the double-precision accumulator for a divide, as MULDIV does.
;;
;; In:    ARG = ARG's exponent, ARGHI = its high byte and sign
;; Out:   HL = FAC, FAC = the quotient's exponent, FAC_SIGN_TEMP = its sign
;; Entry: MULDVA = for a multiply
MULDVS:
    LD A,$FF                        ; $FF: a divide
    .byte $2E                       ; LD L,n: skips the XOR A
MULDVA:
    XOR A                           ; 0: a multiply
    LD HL,ARGHI                     ; ARG's high byte and sign
    LD C,[HL]
    INC HL
    XOR [HL]                        ; B = ARG's exponent, complemented for a divide
    LD B,A
    LD L,$00                        ; the accumulator's exponent as it is

;; Combines the exponents of BCDE and the accumulator for a multiply or divide.
;;
;; The sum of the exponents (the difference, for a divide) becomes the result's exponent, and UNPACK restores the
;; hidden bits and the result's sign. A result too small returns zero from the caller; one too large overflows.
;;
;; In:    BC/DE = the other operand, L = 0 to multiply or $FF to divide
;; Out:   HL = FAC, FAC = the result's exponent, FAC_SIGN_TEMP = its sign, C = BCDE's high byte, hidden bit
;;        set
MULDIV:
    LD A,B                          ; BCDE is zero: so is the result
    OR A
    JP Z,MULDV2
    LD A,L                          ; complement the accumulator's exponent for a divide
    LD HL,FAC
    XOR [HL]
    ADD A,B                         ; add the exponents
    LD B,A
    RRA                             ; the carry and the sign agree: out of range
    XOR B
    LD A,B
    JP P,MULDV1
    ADD A,$80                       ; take away one bias
    LD [HL],A
    JP Z,POPHRT                     ; an exponent of zero: return zero from the caller
    CALL UNPACK                     ; A = the result's sign
    LD [HL],A

;; Decrements HL and returns.
DCXHRT:
    DEC HL                          ; HL = FAC, the exponent
    RET

    ; Nothing calls this, Level II's MLDVEX: zero or overflow by the accumulator's sign.
    CALL SIGN
    CPL
    POP HL

;; Ends MULDIV, or its caller, when the exponent is out of range: zero if A is positive, an overflow if negative.
;;
;; In:    A = the exponent's sum, its sign bit saying which
;; Entry: MULDV2 = decides by the flags as they are
MULDV1:
    OR A
MULDV2:
    POP HL                          ; return from the caller
    JP P,ZERO
    JP MLDVOV                       ; overflow

;; Multiplies the single-precision accumulator by 10.
MUL10:
    CALL MOVRF                      ; BCDE = the accumulator
    LD A,B
    OR A
    RET Z                           ; zero times 10 is zero
    ADD A,$02                       ; the copy times 4
    JP C,FACOVF                     ; overflow
    LD B,A
    CALL FADD                       ; 5 times the accumulator
    LD HL,FAC
    INC [HL]                        ; doubled, 10 times
    RET NZ
    JP FACOVF                       ; overflow

;; Returns the sign of the single-precision accumulator.
;;
;; Out:   A = 1, 0 or $FF (-1) as it is positive, zero or negative, with the flags to match
;; Keeps: BC, DE, HL
;; Entry: FCOMPS = gives the sign opposite to bit 7 of A, ICOMPS = gives the sign in bit 7 of A, SIGNS = gives
;;        $FF if carry is set, otherwise 1
SIGN:
    LD A,[FAC]
    OR A                            ; an exponent of zero is zero
    RET Z
    LD A,[FACHI]                    ; the sign is the high byte's top bit
    .byte $FE                       ; CP n: skips the CPL
FCOMPS:
    CPL
ICOMPS:
    RLA                             ; the sign into carry
SIGNS:
    SBC A,A                         ; $FF if negative, else 0
    RET NZ
    INC A                           ; positive: 1
    RET

;; Converts the signed byte in A to single precision in the accumulator.
;;
;; In:    A = the number
;; Entry: FLOATR = normalizes the signed mantissa A, D, E with exponent B
FLOAT:
    LD B,$88                        ; the exponent of a byte
    LD DE,$0000
FLOATR:
    LD HL,FAC
    LD C,A                          ; C = the high byte, still signed
    LD [HL],B
    LD B,$00                        ; no bits below
    INC HL
    LD [HL],$80                     ; a positive sign, for NEGR to flip
    RLA                             ; the sign into carry: FADFLT negates it
    JP FADFLT

;; Replaces the accumulator with its absolute value, for any numeric type (the ABS function).
;;
;; Errors: ?TM ERROR for a string
FN_ABS:
    CALL VSIGN
    RET P                           ; already positive

;; Negates the accumulator, whatever its numeric type.
;;
;; Errors: ?TM ERROR for a string
VNEG:
    CALL GETYPR
    JP M,INEG                       ; an integer
    JP Z,TMERR

;; Flips the sign of the single- or double-precision accumulator.
;;
;; Uses:  A, HL
;; Keeps: BC, DE
NEG:
    LD HL,FACHI
    LD A,[HL]
    XOR $80                         ; the sign bit
    LD [HL],A
    RET

;; Replaces the accumulator with the integer -1, 0 or 1 by its sign (the SGN function).
;;
;; Errors: ?TM ERROR for a string
FN_SGN:
    CALL VSIGN

;; Stores the signed byte in A as an integer in the accumulator.
;;
;; In:    A = the number
;; Out:   HL = the number
CONIA:
    LD L,A
    RLA                             ; the sign through all of H
    SBC A,A
    LD H,A
    JP MAKINT

;; Returns the sign of the accumulator, for any numeric type.
;;
;; Out:   A = 1, 0 or $FF (-1) as it is positive, zero or negative, with the flags to match
;; Errors: ?TM ERROR for a string
;; Keeps: BC, DE
VSIGN:
    CALL GETYPR
    JP Z,TMERR                      ; a string has no sign
    JP P,SIGN                       ; single and double precision alike
    LD HL,[FACLO]

;; Returns the sign of the integer in HL.
;;
;; In:    HL = the integer
;; Out:   A = 1, 0 or $FF (-1) as it is positive, zero or negative, with the flags to match
;; Keeps: BC, DE, HL
ISIGN:
    LD A,H
    OR L
    RET Z                           ; zero
    LD A,H                          ; H's top bit is the sign
    JP ICOMPS

;; Pushes the single-precision accumulator under the return address.
;;
;; The exponent and high byte end on top, so POP BC and POP DE take the number back into BCDE.
PUSHF:
    EX DE,HL                        ; keep HL in DE
    LD HL,[FACLO]                   ; the low bytes
    EX [SP],HL                      ; under the return address
    PUSH HL
    LD HL,[FACHI]                   ; the high byte and exponent
    EX [SP],HL
    PUSH HL
    EX DE,HL
    RET

;; Loads the single-precision accumulator from the four bytes at HL.
;;
;; In:    HL = the number
;; Out:   BC/DE = the number, HL = the address after it
MOVFM:
    CALL MOVRM

;; Copies BCDE into the single-precision accumulator.
;;
;; In:    BC/DE = the number
;; Out:   DE = BC
;; Keeps: A, BC, HL
MOVFR:
    EX DE,HL
    LD [FACLO],HL                   ; the low bytes
    LD H,B
    LD L,C
    LD [FACHI],HL                   ; the high byte and exponent
    EX DE,HL
    RET

;; Loads BCDE from the single-precision accumulator.
;;
;; Out:   BC/DE = the number, HL = FAC_SIGN_TEMP
;; Keeps: A
MOVRF:
    LD HL,FACLO

;; Loads BCDE from the four bytes at HL.
;;
;; In:    HL = the number
;; Out:   BC/DE = the number, HL = the address after it
;; Keeps: A
;; Entry: GETBCD = loads D, C and B from HL, INXHRT = increments HL
MOVRM:
    LD E,[HL]
    INC HL
GETBCD:
    LD D,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
INXHRT:
    INC HL
    RET

;; Copies the single-precision accumulator to the four bytes at HL.
;;
;; In:    HL = where to copy it
;; Out:   HL = the address after it
MOVMF:
    LD DE,FACLO

;; Copies the four bytes at DE to HL.
;;
;; In:    DE = the source, HL = the destination
;; Out:   DE and HL = the addresses after them, B = 0
;; Keeps: C
MOVE:
    LD B,$04
    JP MOVE1

;; Copies a number sized by VALTYP from HL to DE.
;;
;; In:    HL = the source, DE = the destination
;; Keeps: C
MOVVFM:
    EX DE,HL

;; Copies a number sized by VALTYP from DE to HL.
;;
;; In:    DE = the source, HL = the destination, VALTYP = the type, which is the size: 2, 3, 4 or 8
;; Out:   DE and HL = the addresses after them, B = 0
;; Keeps: C
;; Entry: MOVE1 = copies B bytes
VMOVE:
    LD A,[VALTYP]                   ; VALTYP is the size
    LD B,A
MOVE1:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC B
    JP NZ,MOVE1
    RET

;; Restores the hidden bits of the accumulator and of C, keeping the accumulator's complemented sign in FAC_SIGN_TEMP.
;;
;; In:    C = BCDE's high byte, with its sign
;; Out:   A = bit 7 set when the two signs agree, HL = FAC_SIGN_TEMP, C = with the hidden bit set
;; Keeps: B, DE
UNPACK:
    LD HL,FACHI                     ; the high byte, which holds the sign
    LD A,[HL]
    RLCA                            ; the sign into carry
    SCF                             ; the hidden bit back
    RRA
    LD [HL],A
    CCF                             ; the sign complemented
    RRA                             ; into bit 7 of A
    INC HL
    INC HL
    LD [HL],A
    LD A,C                          ; the same for C
    RLCA
    SCF
    RRA
    LD C,A
    RRA                             ; A = BCDE's sign in bit 7
    XOR [HL]                        ; set when the signs agree, after the CPL
    RET

;; Copies ARG into the accumulator, sized by VALTYP.
;;
;; Keeps: C
VMOVFA:
    LD HL,ARGLO

;; Copies the number at HL into the accumulator, sized by VALTYP.
;;
;; In:    HL = the number
;; Keeps: C
VMOVFM:
    LD DE,MOVVFM
    JP VMVVFM

;; Copies the accumulator into ARG, sized by VALTYP.
;;
;; Keeps: C
VMOVAF:
    LD HL,ARGLO

;; Copies the accumulator to HL, sized by VALTYP.
;;
;; In:    HL = where to copy it
;; Keeps: C
VMOVMF:
    LD DE,VMOVE

;; Goes to the copy routine in DE with DE at the accumulator's first byte for its type.
;;
;; In:    DE = MOVVFM or VMOVE, HL = the other address
;; Keeps: C
VMVVFM:
    PUSH DE                         ; the copy runs when this returns
    LD DE,FACLO                     ; FACLO, below double precision
    CALL GETYPR
    RET C
    LD DE,DFACLO                    ; DFACLO, for double precision
    RET

;; Compares BCDE with the single-precision accumulator.
;;
;; In:    BC/DE = the number
;; Out:   A = 1, 0 or $FF (-1) as the accumulator is larger, equal or smaller, with the flags to match
;; Uses:  HL
;; Keeps: BC, DE
FCOMP:
    LD A,B
    OR A
    JP Z,SIGN                       ; BCDE is zero: the accumulator's sign is the answer
    LD HL,FCOMPS                    ; FCOMPS turns the answer round on return
    PUSH HL
    CALL SIGN                       ; is the accumulator zero?
    LD A,C                          ; A = BCDE's sign
    RET Z                           ; yes: BCDE's sign decides
    LD HL,FACHI
    XOR [HL]                        ; compare the signs
    LD A,C
    RET M                           ; they differ: BCDE's sign decides
    CALL FCOMP2                     ; compare the magnitudes; back here only if they differ
FCOMPD:
    RRA                             ; carry says which is larger
    XOR C                           ; turned round when both are negative
    RET

;; Compares the magnitudes of BCDE and the accumulator for FCOMP, returning from FCOMP when they are equal.
;;
;; In:    BC/DE = the number, HL = FACHI
FCOMP2:
    INC HL                          ; the exponents first
    LD A,B
    CP [HL]
    RET NZ
    DEC HL
    LD A,C
    CP [HL]
    RET NZ
    DEC HL
    LD A,D
    CP [HL]
    RET NZ
    DEC HL
    LD A,E
    SUB [HL]                        ; A = 0 if they are equal
    RET NZ
    POP HL                          ; equal: drop the returns to FCOMPD and FCOMPS
    POP HL
    RET

;; Compares the integers HL and DE.
;;
;; In:    HL = the first integer, DE = the second
;; Out:   A = 1, 0 or $FF (-1) as HL is larger, equal or smaller, with the flags to match
;; Keeps: BC, DE, HL
ICOMP:
    LD A,D                          ; do the signs differ?
    XOR H
    LD A,H                          ; yes: HL's sign decides
    JP M,ICOMPS
    CP D                            ; the high bytes
    JP NZ,ICOMP_1
    LD A,L                          ; then the low bytes
    SUB E
    RET Z                           ; equal
ICOMP_1:
    JP SIGNS                        ; the carry gives 1 or -1

;; Copies the double-precision number at DE into ARG and compares it with the accumulator.
;;
;; In:    DE = the number
;; Out:   A = 1, 0 or $FF (-1) as the accumulator is larger, equal or smaller, with the flags to match
;; Entry: XDCOMP = compares ARG with the accumulator
DCOMPD:
    LD HL,ARGLO
    CALL VMOVE
XDCOMP:
    LD DE,ARG                       ; ARG's exponent
    LD A,[DE]
    OR A
    JP Z,SIGN                       ; ARG is zero: the accumulator's sign is the answer
    LD HL,FCOMPS                    ; FCOMPS turns the answer round on return
    PUSH HL
    CALL SIGN                       ; is the accumulator zero?
    DEC DE
    LD A,[DE]                       ; C = ARG's sign
    LD C,A
    RET Z                           ; yes: ARG's sign decides
    LD HL,FACHI
    XOR [HL]                        ; compare the signs
    LD A,C
    RET M                           ; they differ: ARG's sign decides
    INC DE                          ; from the exponents down, 8 bytes
    INC HL
    LD B,$08
DCOMP1:
    LD A,[DE]
    SUB [HL]
    JP NZ,FCOMPD                    ; the first that differs decides
    DEC DE
    DEC HL
    DEC B
    JP NZ,DCOMP1
    POP BC                          ; equal: drop the return to FCOMPS, A = 0
    RET

;; Compares the double-precision accumulator with ARG, for the relational operators (DBLDSP, Tables.asm).
;;
;; XDCOMP with the answer turned round, as Level II's DCOMP is.
;;
;; Out:   A = 1, 0 or $FF (-1) as the accumulator is larger, equal or smaller, with the flags to match
DCOMP:
    CALL XDCOMP
    JP NZ,FCOMPS
    RET

;; Converts the accumulator to an integer in HL, rounding to the nearest (the CINT function, FRCINT).
;;
;; One half is added, and the sum's magnitude truncated; a negative sum gives the complement of that, so halves
;; round away from zero.
;;
;; Out:   HL = the integer, FACLO = the integer, VALTYP = 2
;; Errors: ?TM ERROR for a string, ?OV ERROR outside -32768 to 32767
FN_CINT:
    CALL GETYPR
    LD HL,[FACLO]                   ; the integer, if it is one
    RET M                           ; an integer already
    JP Z,TMERR                      ; a string
    JP PO,FN_CINT_1                 ; single precision
    CALL VMOVAF                     ; double: ARG = the number
    LD HL,DHALF
    CALL VMOVFM                     ; the accumulator = 0.5
    CALL DADD                       ; the number plus 0.5
    CALL CONSD                      ; to single precision
    JP FN_CINT_2
FN_CINT_1:
    CALL FADDH                      ; the number plus 0.5
FN_CINT_2:
    LD A,[FACHI]
    OR A
    PUSH AF                         ; keep the sign
    AND $7F                         ; take the magnitude
    LD [FACHI],A
    LD A,[FAC]
    CP $90                          ; 32768 or more: overflow
    JP NC,OVERR
    CALL QINT                       ; DE = the whole part
    LD A,[FAC]
    OR A
    JP NZ,FN_CINT_3
    POP AF                          ; the sum was zero, from -0.5: -1
    EX DE,HL
    JP FN_CINT_4
FN_CINT_3:
    POP AF
    EX DE,HL
    JP P,FN_CINT_5                  ; positive: the whole part
FN_CINT_4:
    LD A,H                          ; negative: its complement, one less
    CPL
    LD H,A
    LD A,L
    CPL
    LD L,A
FN_CINT_5:
    JP MAKINT

    ; Nothing jumps here: Level II's FRCINT pushed OVERR here as CONIS's return.
    LD HL,OVERR
    PUSH HL

;; Truncates the single-precision accumulator to an integer, returning from the caller if it fits.
;;
;; The caller's return address must be under this routine's on the stack: if the number fits, CONIS returns to the
;; caller's caller, with the integer in HL and FACLO; if not, it returns to the caller.
;;
;; Out:   HL = the integer, if it fits
;; Entry: CONIS1 = with the integer already in HL, MAKINT = stores HL as an integer, VALINT = sets VALTYP to
;;   integer, CONISD = sets VALTYP to A
CONIS:
    LD A,[FAC]                      ; A = the exponent
    CP $90                          ; 32768 or more
    JP NC,CONIS2                    ; too large, unless it is -32768
    CALL QINT                       ; DE = the integer
    EX DE,HL
CONIS1:
    POP DE                          ; drop the caller's return: it fitted
MAKINT:
    LD [FACLO],HL
VALINT:
    LD A,$02                        ; 2: integer
CONISD:
    LD [VALTYP],A
    RET

;; Accepts -32768 for CONIS, the one number of 32768 or more in magnitude that fits an integer.
;;
;; If it is, CONIS goes on with HL = $8000; if not, it returns to CONIS's caller.
CONIS2:
    LD BC,$9080                     ; BCDE = -32768
    LD DE,$0000
    CALL FCOMP
    RET NZ                          ; not -32768: return to the caller
    LD H,C                          ; HL = $8000
    LD L,D
    JP CONIS1

;; Converts the accumulator to single precision (the CSNG function, FRCSNG).
;;
;; Errors: ?TM ERROR for a string
FN_CSNG:
    CALL GETYPR
    RET PO                          ; single precision already
    JP M,CONSI                      ; an integer
    JP Z,TMERR                      ; a string

;; Converts the double-precision accumulator to single precision, rounding.
CONSD:
    CALL MOVRF                      ; BCDE = the high four bytes
    CALL VALSNG
    LD A,B
    OR A
    RET Z                           ; zero needs no rounding
    CALL UNPACK
    LD HL,FACLO-1                   ; the byte below rounds it
    LD B,[HL]
    JP ROUND

;; Converts the integer accumulator to single precision.
;;
;; Entry: CONSIH = converts the integer in HL
CONSI:
    LD HL,[FACLO]
CONSIH:
    CALL VALSNG
    LD A,H                          ; ADE = the integer as a mantissa
    LD D,L
    LD E,$00
    LD B,$90                        ; the exponent of a 16-bit integer
    JP FLOATR

;; Converts the accumulator to double precision (the CDBL function, FRCDBL).
;;
;; Errors: ?TM ERROR for a string
FN_CDBL:
    CALL GETYPR
    RET NC                          ; double precision already
    JP Z,TMERR                      ; a string
    CALL M,CONSI                    ; an integer: to single precision first

;; Converts the single-precision accumulator to double precision, clearing the low bytes.
;;
;; Entry: VALDBL = sets VALTYP to double precision, using BC
CONDS:
    LD HL,$0000
    LD [DFACLO],HL                  ; DFACLO, the low four bytes
    LD [DFAC_MID],HL
VALDBL:
    LD A,$08                        ; 8: double precision
    .byte $01                       ; LD BC,nn: skips the next instruction

;; Sets VALTYP to single precision.
;;
;; Keeps: BC, DE, HL
VALSNG:
    LD A,$04                        ; 4: single precision
    JP CONISD

;; Returns if the accumulator holds a string.
;;
;; Errors: ?TM ERROR if it is a number
;; Keeps: BC, DE, HL
CHKSTR:
    CALL GETYPR
    RET Z
    JP TMERR

;; Truncates the single-precision accumulator to a signed integer in CDE, toward minus infinity.
;;
;; In:    A = the accumulator's exponent
;; Out:   C/DE = the integer
;; Keeps: HL
QINT:
    LD B,A                          ; zero gives zero
    LD C,A
    LD D,A
    LD E,A
    OR A
    RET Z
    PUSH HL
    CALL MOVRF
    CALL UNPACK
    XOR [HL]                        ; A's top bit = the sign
    LD H,A
    CALL M,QINTA                    ; negative: one less, to round toward minus infinity
    LD A,$98                        ; the exponent of a 24-bit integer
    SUB B                           ; A = the bits of fraction to shift out
    CALL SHIFTR
    LD A,H
    RLA                             ; the sign into carry
    CALL C,ROUNDA                   ; negative: add the one back
    LD B,$00                        ; drop the fraction
    CALL C,NEGR                     ; negative: two's complement
    POP HL
    RET

;; Decrements the mantissa CDE, for QINT.
;;
;; Entry: DCXBRT = decrements BC
QINTA:
    DEC DE
    LD A,D                          ; a borrow out of DE leaves both $FF
    AND E
    INC A
    RET NZ
DCXBRT:
    DEC BC
    RET
