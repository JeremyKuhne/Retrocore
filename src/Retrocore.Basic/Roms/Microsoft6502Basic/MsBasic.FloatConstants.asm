; Microsoft's ADDPRC=1 constants, shared by AppleSoft and PET BASIC 1, 2 and 4.

;; Emits the five-byte floating-point constant 1.
.macro FLOAT_ONE
    .byte $81, $00, $00, $00, $00
.endmacro

;; Emits the five-byte constants and polynomial table used by <LOG>.
.macro LOG_CONSTANTS

;; Packed floating-point constant 1.
FONE:
    FLOAT_ONE

;; Logarithm polynomial: degree 3, followed by four packed coefficients.
LOGCN2:
    .byte $03
    .byte $7F, $5E, $56, $CB, $79
    .byte $80, $13, $9B, $0B, $64
    .byte $80, $76, $38, $93, $16
    .byte $82, $38, $AA, $3B, $20

;; Packed approximation to the square root of one half.
SQRHLF:
    .byte $80, $35, $04, $F3, $34

;; Packed approximation to the square root of two.
SQRTWO:
    .byte $81, $35, $04, $F3, $34

;; Packed floating-point constant minus one half.
NEGHLF:
    .byte $80, $80, $00, $00, $00

;; Packed approximation to the natural logarithm of two.
LOG2:
    .byte $80, $31, $72, $17, $F8

.endmacro

;; Emits the five-byte decimal-output scaling constants.
;; Parameters: preciseUpper = 1 for the 999,999,999.5 upper threshold, 0 for 999,999,999.25
.macro OUTPUT_CONSTANTS preciseUpper

    .assert preciseUpper = 0 || preciseUpper = 1, "preciseUpper is 0 or 1."

;; Packed lower scaling threshold, 99,999,999.90625.
NZ0999:
    .byte $9B, $3E, $BC, $1F, $FD

;; Packed upper scaling threshold, selected by the macro's preciseUpper parameter.
NZ9999:
.if preciseUpper
    .byte $9E, $6E, $6B, $27, $FE
.else
    .byte $9E, $6E, $6B, $27, $FD
.endif

;; Packed floating-point constant one billion, used to scale small output values.
NZMIL:
    .byte $9E, $6E, $6B, $28, $00

.endmacro

;; Emits the decimal digit table and, optionally, the time-conversion table.
;; Parameters: defineZero = 1 to define <ZERO> within <FHALF>, 0 when <ZERO> is defined elsewhere
;;   includeTime = 1 to include the time-conversion table, 0 to omit it
.macro OUTPUT_TABLES defineZero, includeTime

    .assert defineZero = 0 || defineZero = 1, "defineZero is 0 or 1."
    .assert includeTime = 0 || includeTime = 1, "includeTime is 0 or 1."

;; Packed floating-point constant one half.
FHALF:
    .byte $80, $00

.if defineZero
;; Three zero bytes shared by <FHALF> and other constants.
ZERO:
.endif
    .byte $00, $00, $00

;; Nine signed, big-endian powers of ten, alternating from -100,000,000 to -1.
;;
;; Repeated addition of these values extracts the nine output digits.
FOUTBL:
    .byte $FA, $0A, $1F, $00       ; -100,000,000
    .byte $00, $98, $96, $80       ;   10,000,000
    .byte $FF, $F0, $BD, $C0       ;   -1,000,000
    .byte $00, $01, $86, $A0       ;      100,000
    .byte $FF, $FF, $D8, $F0       ;      -10,000
    .byte $00, $00, $03, $E8       ;        1,000
    .byte $FF, $FF, $FF, $9C       ;         -100
    .byte $00, $00, $00, $0A       ;           10
    .byte $FF, $FF, $FF, $FF       ;           -1

;; End of the decimal powers in <FOUTBL>.
FDCEND:
    .assert FDCEND - FOUTBL = 36, "FOUTBL has nine four-byte entries."

.if includeTime
; Alternating signed divisors for the time conversion.
    .byte $FF, $DF, $0A, $80       ; -2,160,000
    .byte $00, $03, $4B, $C0       ;    216,000
    .byte $FF, $FF, $73, $60       ;    -36,000
    .byte $00, $00, $0E, $10       ;      3,600
    .byte $FF, $FF, $FD, $A8       ;       -600
    .byte $00, $00, $00, $3C       ;         60

;; End of the time-conversion divisors following <FDCEND>.
TIMEND:
.endif

.endmacro

;; Emits the five-byte constant and polynomial table used by <EXP>.
.macro EXP_CONSTANTS

;; The five-byte floating-point constant log base 2 of e.
LOGEB2:
    .byte $81, $38, $AA, $3B, $29

;; <EXP>'s polynomial: degree 7, followed by eight five-byte coefficients in evaluation order.
EXPCON:
    .byte $07                       ; polynomial degree
    .byte $71, $34, $58, $3E, $56   ; approximately 0.00002149876370
    .byte $74, $16, $7E, $B3, $1B   ; approximately 0.0001435231404
    .byte $77, $2F, $EE, $E3, $85   ; approximately 0.001342263482
    .byte $7A, $1D, $84, $1C, $2A   ; approximately 0.009614017014
    .byte $7C, $63, $59, $58, $0A   ; approximately 0.05550512686
    .byte $7E, $75, $FD, $E7, $C6   ; approximately 0.2402263846
    .byte $80, $31, $72, $18, $10   ; approximately 0.6931471862
    FLOAT_ONE                       ; 1

.endmacro

;; Emits the five-byte constants and polynomial table used by <SIN>.
.macro SIN_CONSTANTS

;; Five-byte floating-point pi/2.
PI2:
    .byte $81, $49, $0F, $DA, $A2

;; Five-byte floating-point 2*pi.
TWOPI:
    .byte $83, $49, $0F, $DA, $A2

;; Five-byte floating-point one quarter.
FR4:
    .byte $7F, $00, $00, $00, $00

;; <SIN>'s odd-polynomial table: degree 5 for P and six five-byte coefficients for X * P(X squared).
SINCON:
    .byte $05                       ; polynomial degree
    .byte $84, $E6, $1A, $2D, $1B   ; approximately -14.38139067
    .byte $86, $28, $07, $FB, $F8   ; approximately 42.00779712
    .byte $87, $99, $68, $89, $01   ; approximately -76.70417026
    .byte $87, $23, $35, $DF, $E1   ; approximately 81.60522369
    .byte $86, $A5, $5D, $E7, $28   ; approximately -41.34170210
    .byte $83, $49, $0F, $DA, $A2   ; approximately 6.283185307

.endmacro

;; Emits the five-byte polynomial table used by <ATN>.
.macro ATN_CONSTANTS

;; <ATN>'s odd-polynomial table: degree 11 for P and twelve five-byte coefficients for X * P(X squared).
ATNCON:
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
    FLOAT_ONE                       ; 1

.endmacro
