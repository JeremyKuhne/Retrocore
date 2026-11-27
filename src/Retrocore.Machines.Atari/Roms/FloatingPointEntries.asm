;; FLOATING POINT PACKAGE ENTRY POINTS, FOR THE SOURCES THAT CALL IT
;;
;; The floating point package's routines, at the addresses the OS User's Manual documents, and the constant tables
;; that Atari BASIC reads by address, as equates. FloatingPoint.asm defines and documents each of them as a label,
;; so it does not include this file; the sources that call the package do, and each definition here inherits the
;; package's documentation. The package's registers and buffers (FR0, FR1, FLPTR, INBUFF, CIX, LBUFF and the rest)
;; are in OsEquates.asm, which those sources include too.

; The routines.

;; Inherit: <FloatingPoint:AFP>
AFP = $D800

;; Inherit: <FloatingPoint:FASC>
FASC = $D8E6

;; Inherit: <FloatingPoint:IFP>
IFP = $D9AA

;; Inherit: <FloatingPoint:FPI>
FPI = $D9D2

;; Inherit: <FloatingPoint:ZFR0>
ZFR0 = $DA44

;; Inherit: <FloatingPoint:ZF1>
ZF1 = $DA46

;; Inherit: <FloatingPoint:FSUB>
FSUB = $DA60

;; Inherit: <FloatingPoint:FADD>
FADD = $DA66

;; Inherit: <FloatingPoint:FMUL>
FMUL = $DADB

;; Inherit: <FloatingPoint:FDIV>
FDIV = $DB28

;; Inherit: <FloatingPoint:PLYEVL>
PLYEVL = $DD40

;; Inherit: <FloatingPoint:FLD0R>
FLD0R = $DD89

;; Inherit: <FloatingPoint:FLD0P>
FLD0P = $DD8D

;; Inherit: <FloatingPoint:FLD1R>
FLD1R = $DD98

;; Inherit: <FloatingPoint:FLD1P>
FLD1P = $DD9C

;; Inherit: <FloatingPoint:FST0R>
FST0R = $DDA7

;; Inherit: <FloatingPoint:FST0P>
FST0P = $DDAB

;; Inherit: <FloatingPoint:FMOVE>
FMOVE = $DDB6

;; Inherit: <FloatingPoint:EXP>
EXP = $DDC0

;; Inherit: <FloatingPoint:EXP10>
EXP10 = $DDCC

;; Inherit: <FloatingPoint:LOG>
LOG = $DECD

;; Inherit: <FloatingPoint:LOG10>
LOG10 = $DED1

; Routines inside the package that Atari BASIC calls, though the manual does not document them.

;; Inherit: <FloatingPoint:FP_CLEAR_BYTES>
FP_CLEAR_BYTES = $DA48

;; Inherit: <FloatingPoint:FP_SET_INBUFF_LBUFF>
FP_SET_INBUFF_LBUFF = $DA51

;; Inherit: <FloatingPoint:FP_SKIP_SPACES>
FP_SKIP_SPACES = $DBA1

;; Inherit: <FloatingPoint:FP_TEST_DIGIT>
FP_TEST_DIGIT = $DBAF

;; Inherit: <FloatingPoint:FP_NORMALIZE>
FP_NORMALIZE = $DC00

; The constant tables, each value six bytes in the package's format.

;; Inherit: <FloatingPoint:EXP_COEFFICIENTS>
EXP_COEFFICIENTS = $DE4D

;; Inherit: <FloatingPoint:FP_LOG10_E>
FP_LOG10_E = $DE89

;; Inherit: <FloatingPoint:FP_ONE>
FP_ONE = $DE8F

;; Inherit: <FloatingPoint:FP_DIFFERENCE_OVER_SUM>
FP_DIFFERENCE_OVER_SUM = $DE95

;; Inherit: <FloatingPoint:FP_HALF>
FP_HALF = $DF6C

;; Inherit: <FloatingPoint:FP_SQRT10>
FP_SQRT10 = $DF66

;; Inherit: <FloatingPoint:LOG_COEFFICIENTS>
LOG_COEFFICIENTS = $DF72

;; Inherit: <FloatingPoint:ATN_COEFFICIENTS>
ATN_COEFFICIENTS = $DFAE

;; Inherit: <FloatingPoint:FP_PI_OVER_4>
FP_PI_OVER_4 = $DFF0

ATN_COEFFICIENT_COUNT = 11          ;; the coefficients of <ATN_COEFFICIENTS>, for the arctangent
