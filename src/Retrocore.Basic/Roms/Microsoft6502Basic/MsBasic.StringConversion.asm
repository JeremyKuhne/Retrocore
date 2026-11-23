; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: DECIMAL AND BUFFER STRING CONVERSION
;
; Emit STRING_FROM_NUMBER immediately before STRING_STORAGE.

;; Emits the STR$ entry and its buffer-to-string continuation.
.macro STRING_FROM_NUMBER
    .assert LOFBUF >= 0 && LOFBUF < $100, "TIMSTR requires LOFBUF in page zero."

;; Converts numeric <FAC> to a decimal string in a temporary descriptor.
;;
;; It enters <Float::FormatFacAtOffset> with Y = 0 so the result starts at <LOFBUF>. AppleSoft omits the leading
;; blank on a nonnegative value; PET BASIC retains it. A negative sign is emitted when bit 7 of
;; <FACSGN> is set, even when the exponent is zero. One caller return address is discarded before
;; continuing at <TIMSTR>.
;;
;; In: FAC = numeric value, VALTYP = numeric, decimal = clear
;; Out: FACMO/FACLO = temporary descriptor pointer, VALTYP = string
;; Errors: TYPE MISMATCH for a string, OUT OF MEMORY or FORMULA TOO COMPLEX while making the result
STR:
    jsr CHKNUM
    ldy #$00
    jsr FOUTC
    pla
    pla

;; Copies the text at <LOFBUF> to a temporary string through <STRLIT>.
;;
;; The text ends at a quote or zero. Unlike <STR>, this entry does not discard a return address.
;; Out: FACMO/FACLO = temporary descriptor pointer, VALTYP = string
;; Errors: OUT OF MEMORY or FORMULA TOO COMPLEX while making the result
TIMSTR:
    lda #<LOFBUF
    ldy #>LOFBUF
    beq STRLIT
.endmacro
