; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; Microsoft's constants for ADDITIONAL_PRECISION = 1 (ADDPRC=1), shared by AppleSoft and PET BASIC 1, 2 and 4.

;; Emits the five-byte floating-point constant 1.
.macro FloatOne
    .byte $81, $00, $00, $00, $00
.endmacro

;; Emits the five-byte constants and polynomial table used by <Functions::Log>.
.macro LogarithmConstants

    .scope Float continued

;; Packed floating-point constant 1.
;; Also: FONE (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79, BV20)
One:
    FloatOne

;; Logarithm polynomial: degree 3, followed by four packed coefficients.
;; Also: LOGCN2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LogPolynomial:
    .byte $03
    .byte $7F, $5E, $56, $CB, $79
    .byte $80, $13, $9B, $0B, $64
    .byte $80, $76, $38, $93, $16
    .byte $82, $38, $AA, $3B, $20

;; Packed approximation to the square root of one half.
;; Also: SQRHLF (M6502)
SquareRootOfHalf:
    .byte $80, $35, $04, $F3, $34

;; Packed approximation to the square root of two.
;; Also: SQRTWO (M6502)
SquareRootOfTwo:
    .byte $81, $35, $04, $F3, $34

;; Packed floating-point constant minus one half.
;; Also: NEGHLF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
MinusHalf:
    .byte $80, $80, $00, $00, $00

;; Packed approximation to the natural logarithm of two.
;; Also: LOG2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LogOfTwo:
    .byte $80, $31, $72, $17, $F8
    .endscope

.endmacro

;; Emits the five-byte decimal-output scaling constants.
;; Parameters: preciseUpper = 1 for the 999,999,999.5 upper threshold, 0 for 999,999,999.25
.macro OutputConstants preciseUpper

    .assert preciseUpper = 0 || preciseUpper = 1, "preciseUpper is 0 or 1."

    .scope Float continued

;; Packed lower scaling threshold, 99,999,999.90625.
;; Also: NZ0999 (M6502)
LowerOutputLimit:
    .byte $9B, $3E, $BC, $1F, $FD

;; Packed upper scaling threshold, selected by the macro's preciseUpper parameter.
;; Also: NZ9999 (M6502)
UpperOutputLimit:
    .if preciseUpper
        .byte $9E, $6E, $6B, $27, $FE
    .else
        .byte $9E, $6E, $6B, $27, $FD
    .endif

;; Packed floating-point constant one billion, used to scale small output values.
;; Also: NZMIL (M6502)
Billion:
    .byte $9E, $6E, $6B, $28, $00
    .endscope

.endmacro

;; Emits the decimal digit table and, optionally, the time-conversion table.
;; Parameters: defineZero = 1 to put the top-level label `ZeroValue` on the last three bytes of <Float::Half>, 0 when
;;   it is defined elsewhere
;;   includeTime = 1 to include the time-conversion table, 0 to omit it
.macro OutputTables defineZero, includeTime

    .assert defineZero = 0 || defineZero = 1, "defineZero is 0 or 1."
    .assert includeTime = 0 || includeTime = 1, "includeTime is 0 or 1."

    .scope Float continued

;; Packed floating-point constant one half.
;; Also: FHALF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Half:
    .byte $80, $00
    .endscope

    .if defineZero
;; Three zero bytes shared by <Float::Half> and other constants.
;; Also: ZERO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ZeroValue:
    .endif
    .byte $00, $00, $00

    .scope Float continued

;; Nine signed, big-endian powers of ten, alternating from -100,000,000 to -1.
;;
;; Repeated addition of these values extracts the nine output digits.
;; Also: FOUTBL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
PowersOfTen:
    .byte $FA, $0A, $1F, $00       ; -100,000,000
    .byte $00, $98, $96, $80       ;   10,000,000
    .byte $FF, $F0, $BD, $C0       ;   -1,000,000
    .byte $00, $01, $86, $A0       ;      100,000
    .byte $FF, $FF, $D8, $F0       ;      -10,000
    .byte $00, $00, $03, $E8       ;        1,000
    .byte $FF, $FF, $FF, $9C       ;         -100
    .byte $00, $00, $00, $0A       ;           10
    .byte $FF, $FF, $FF, $FF       ;           -1

;; End of the decimal powers in <Float::PowersOfTen>.
;; Also: FDCEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
PowersOfTenEnd:
    .assert PowersOfTenEnd - PowersOfTen = 36, "FOUTBL has nine four-byte entries."

    .if includeTime
        ; Alternating signed divisors for the time conversion.
        .byte $FF, $DF, $0A, $80       ; -2,160,000
        .byte $00, $03, $4B, $C0       ;    216,000
        .byte $FF, $FF, $73, $60       ;    -36,000
        .byte $00, $00, $0E, $10       ;      3,600
        .byte $FF, $FF, $FD, $A8       ;       -600
        .byte $00, $00, $00, $3C       ;         60

;; End of the time-conversion divisors following <Float::PowersOfTenEnd>.
;; Also: TIMEND (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79, BV20)
TimeDivisorsEnd:
    .endif
    .endscope

.endmacro

;; Emits the five-byte constant and polynomial table used by <Functions::Exp>.
.macro ExponentialConstants

    .scope Float continued

;; The five-byte floating-point constant log base 2 of e.
;; Also: LOGEB2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LogBase2OfE:
    .byte $81, $38, $AA, $3B, $29

;; <Functions::Exp>'s polynomial: degree 7, followed by eight five-byte coefficients in evaluation order.
;; Also: EXPCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ExponentialPolynomial:
    .byte $07                       ; polynomial degree
    .byte $71, $34, $58, $3E, $56   ; approximately 0.00002149876370
    .byte $74, $16, $7E, $B3, $1B   ; approximately 0.0001435231404
    .byte $77, $2F, $EE, $E3, $85   ; approximately 0.001342263482
    .byte $7A, $1D, $84, $1C, $2A   ; approximately 0.009614017014
    .byte $7C, $63, $59, $58, $0A   ; approximately 0.05550512686
    .byte $7E, $75, $FD, $E7, $C6   ; approximately 0.2402263846
    .byte $80, $31, $72, $18, $10   ; approximately 0.6931471862
    FloatOne                       ; 1
    .endscope

.endmacro

;; Emits the five-byte constants and polynomial table used by <Functions::Sin>.
.macro SineConstants

    .scope Float continued

;; Five-byte floating-point pi/2.
;; Also: PI2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
HalfPi:
    .byte $81, $49, $0F, $DA, $A2

;; Five-byte floating-point 2*pi.
;; Also: TWOPI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
TwoPi:
    .byte $83, $49, $0F, $DA, $A2

;; Five-byte floating-point one quarter.
;; Also: FR4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Quarter:
    .byte $7F, $00, $00, $00, $00

;; <Functions::Sin>'s odd-polynomial table: degree 5 for P and six five-byte coefficients for X * P(X squared).
;; Also: SINCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SinePolynomial:
    .byte $05                       ; polynomial degree
    .byte $84, $E6, $1A, $2D, $1B   ; approximately -14.38139067
    .byte $86, $28, $07, $FB, $F8   ; approximately 42.00779712
    .byte $87, $99, $68, $89, $01   ; approximately -76.70417026
    .byte $87, $23, $35, $DF, $E1   ; approximately 81.60522369
    .byte $86, $A5, $5D, $E7, $28   ; approximately -41.34170210
    .byte $83, $49, $0F, $DA, $A2   ; approximately 6.283185307
    .endscope

.endmacro

;; Emits the five-byte polynomial table used by <Functions::Atn>.
.macro ArctangentConstants

    .scope Float continued

;; <Functions::Atn>'s odd-polynomial table: degree 11 for P and twelve five-byte coefficients for X * P(X squared).
;; Also: ATNCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ArctangentPolynomial:
    .byte $0B                       ; polynomial degree
    .byte $76, $B3, $83, $BD, $D3   ; approximately -0.0006847939119
    .byte $79, $1E, $F4, $A6, $F5   ; approximately 0.004850942156
    .byte $7B, $83, $FC, $B0, $10   ; approximately -0.01611170184
    .byte $7C, $0C, $1F, $67, $CA   ; approximately 0.03420963805
    .byte $7C, $DE, $53, $CB, $C1   ; approximately -0.05427913276
    .byte $7D, $14, $64, $70, $4C   ; approximately 0.07245719654
    .byte $7D, $B7, $EA, $51, $7A   ; approximately -0.08980239538
    .byte $7D, $63, $30, $88, $7E   ; approximately 0.1109324134
    .byte $7E, $92, $44, $99, $3A   ; approximately -0.1428398077
    .byte $7E, $4C, $CC, $91, $C7   ; approximately 0.1999991205
    .byte $7F, $AA, $AA, $AA, $13   ; approximately -0.3333333157
    FloatOne                       ; 1
    .endscope

.endmacro
