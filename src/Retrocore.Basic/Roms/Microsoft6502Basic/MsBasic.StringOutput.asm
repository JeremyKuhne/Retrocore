; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: STRING OUTPUT

;; Prints text up to a quotation mark or zero.
;; In: A = low string address, Y = high string address
;; See: <Strings::FromText>, <PrintString>
;; Also: STROUT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
.proc PrintText
    jsr Strings::FromText
; Falls into PrintString.
.endproc

;; Prints the string whose descriptor is addressed by <FacMantissa3>, releasing the temporary if applicable.
;;
;; Each carriage return it prints is followed by the vendor's <PrintNewline::Finish>. It ends at
;; <PrintNewline::Return>, Print's return.
;; In: FacMantissa3 = string descriptor address (low byte), FacMantissa4 = its high byte
;; See: <Strings::ReleaseFac>, <PrintCharacter>
;; Also: STRPRT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
.proc PrintString
    jsr Strings::ReleaseFac
    tax
    ldy #$00
    inx
;; Prints the next character until the count runs out.
;; Also: STRPR2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    dex
    beq PrintNewline::Return
    lda (Pointer1),y
    jsr PrintCharacter
    iny
    cmp #$0D                    ; carriage return
    bne NextCharacter
    jsr PrintNewline::Finish
    jmp NextCharacter
.endproc
