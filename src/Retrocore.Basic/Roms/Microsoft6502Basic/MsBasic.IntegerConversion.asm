; MICROSOFT 6502 BASIC: SUBSCRIPT AND SIGNED INTEGER CONVERSION
;
; Emit INTEGER_CONVERSION_BOUNDARY immediately followed by INTEGER_CONVERSION. The latter selects the expression
; evaluator independently of POSINT's optional numeric-type check. AppleSoft and PET BASIC 1 use FRMNUM without
; the extra check; PET BASIC 2 and 4 use FRMEVL and the check.

;; Emits the prefix of the integer-conversion boundary constant.
.macro INTEGER_CONVERSION_BOUNDARY

;; Four-byte prefix of the packed number compared with <FAC> by <AYINT>.
;;
;; <FCOMP> reads five bytes: the fifth is the $20 JSR opcode at <INTIDX>, not a zero byte.
N32768:
    .byte $90, $80, $00, $00
.endmacro

;; Emits the subscript and integer conversion entries immediately after <N32768>.
;; Parameters: evaluateEntry = expression evaluator, checkType = 1 to check the type at <POSINT>, 0 to omit it
.macro INTEGER_CONVERSION evaluateEntry, checkType
    .assert checkType = 0 || checkType = 1, "checkType must be 0 or 1."
    .assert * = N32768+4, "INTEGER_CONVERSION must immediately follow INTEGER_CONVERSION_BOUNDARY."

;; Evaluates the next subscript and converts it to a nonnegative integer.
;;
;; <CHRGET> advances to the expression before the selected evaluator is called.
;; In: TXTPTR = character immediately before the expression
;; Out: INDICE = integer subscript, high byte first in <FACMO>/<FACLO>
;; Errors: TYPE MISMATCH if the selected evaluator or <POSINT> checks the type and the result is a string,
;;   ILLEGAL QUANTITY if <POSINT> rejects the value
;; See: <POSINT>
INTIDX:
    jsr CHRGET
    jsr evaluateEntry

;; Converts a nonnegative <FAC> to an integer.
;;
;; When selected, the type check runs before the sign check. Otherwise the caller must supply a numeric result.
;; A set sign bit is rejected even when the exponent is zero.
;; In: FAC = numeric result, VALTYP = result type when the type check is selected
;; Out: FACMO/FACLO = integer, high byte first
;; Errors: TYPE MISMATCH if the selected type check rejects a string, ILLEGAL QUANTITY if negative or too large
;; See: <AYINT>
POSINT:
.if checkType
    jsr CHKNUM
.endif
    lda FACSGN
    bmi NONONO

;; Converts <FAC> to a signed integer after the exponent and boundary checks.
;;
;; Exponents below $90 go directly to <QINT>; otherwise <FCOMP> must report equality with <N32768>.
;; Because its fifth byte is $20, exact -32768 with a zero guard compares unequal, while the packed value
;; $90 $80 $00 $00 $20 compares equal. <FCOMP> also uses the <FACOV> guard in its last-byte comparison.
;; <QINT> rounds fractions down and the result here is its low 16 bits.
;; In: FAC = numeric result
;; Out: FACMO/FACLO = signed integer, high byte first
;; Errors: ILLEGAL QUANTITY if the exponent is at least $90 and the comparison is unequal
;; See: <FCOMP>, <N32768>, <QINT>
AYINT:
    lda FACEXP
    cmp #$90
    bcc QINTGO
    lda #<N32768
    ldy #>N32768
    jsr FCOMP

NONONO:
    bne FCERR

;; Converts <FAC> without checking its type, sign or range.
;; See: <QINT>
QINTGO:
    jmp QINT
.endmacro
