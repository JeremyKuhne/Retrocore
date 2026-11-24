; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: DECIMAL AND BUFFER STRING CONVERSION
;
; Emit StringFromNumber immediately before StringStorage.

;; Emits the `STR$` entry and its buffer-to-string continuation.
.macro StringFromNumber
    .assert NumberBufferPrefix >= 0 && NumberBufferPrefix < $100, "NumberBufferPrefix must be in page zero."

    .scope Functions continued

    ;; Converts numeric <Fac> to a decimal string in a temporary descriptor.
    ;;
    ;; It enters <Float::FormatFacAtOffset> with Y = 0 so the result starts at <NumberBufferPrefix>. AppleSoft omits
    ;; the leading blank on a nonnegative value; PET BASIC retains it. A negative sign is emitted when bit 7 of
    ;; <FacSign> is set, even when the exponent is zero. It discards the function dispatcher's return, so that
    ;; <CallFunction> does not check for a number, before continuing at <Strings::FromNumberBuffer>.
    ;;
    ;; In: Fac = numeric value, ValueType = numeric, decimal = clear
    ;; Out: FacMantissa3 = temporary descriptor pointer (low byte), FacMantissa4 = 0, ValueType = string
    ;; Errors: TYPE MISMATCH for a string, OUT OF MEMORY or FORMULA TOO COMPLEX while making the result
    ;; Also: STR (M6502)
    .proc Str
    jsr RequireNumber
    ldy #$00
    jsr Float::FormatFacAtOffset
    pla
    pla
    ; Falls into Strings::FromNumberBuffer.
    .endproc
    .endscope

    .scope Strings continued

    ;; Copies the text at <NumberBufferPrefix> to a temporary string through <Strings::FromText>.
    ;;
    ;; The text ends at a quote or zero. Unlike <Functions::Str>, this entry does not discard a return address.
    ;; Out: FacMantissa3 = temporary descriptor pointer (low byte), FacMantissa4 = 0, ValueType = string
    ;; Errors: OUT OF MEMORY or FORMULA TOO COMPLEX while making the result
    ;; Also: TIMSTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FromNumberBuffer
    lda #<NumberBufferPrefix
    ldy #>NumberBufferPrefix
    ; The prefix is in page zero, so Y is 0 and this always branches.
    beq FromText
    .endproc
    .endscope

.endmacro
