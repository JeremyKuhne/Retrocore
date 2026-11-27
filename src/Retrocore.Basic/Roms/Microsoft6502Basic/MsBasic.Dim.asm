; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: DIM STATEMENT

.scope Statements continued

;; Consumes the comma between arrays in a `DIM` statement, then dimensions the next array.
;; Errors: SYNTAX if no comma follows
;; Also: DIM3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc DimNextArray
    jsr CheckComma
; Falls into Dim.
.endproc

;; Dimensions each array in a comma-separated `DIM` statement.
;;
;; The nonzero character in X becomes <Dimensioning>, which tells the variable search to create arrays with the
;; supplied bounds and to reject an array that already exists.
;; In: A = the first character of the array's name
;; Also: DIM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc Dim
    tax
;; Calls <FindVariable::WithDimensionFlag>, which creates the array.
;; Also: DIM1 (M6502)
DefineArray:
    jsr FindVariable::WithDimensionFlag
;; Rereads the current character; a non-terminator goes back to <Statements::DimNextArray>.
;; Also: DIMCON (M6502)
CheckMore:
    jsr GetCurrentCharacter
    bne DimNextArray
    rts
.endproc
.endscope

