; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: DECIMAL LINE NUMBERS

;; Reads a decimal line number from the current text position, rejecting values at or above 64000.
;; In: A = current character, carry = clear for a digit
;; Out: LineNumber = line number, TextPointer = terminating character, A = terminating character, carry = set
;; Also: LINGET (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
.proc ReadLineNumber
    ldx #$00
    stx LineNumber
    stx LineNumber+1

;; A non-digit exits through <Statements::On::Done>; otherwise multiplies by 10 and adds the digit.
;; Also: MORLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextDigit:
    bcs Statements::On::Done
    sbc #('0'-1)
    sta Delimiter
    lda LineNumber+1
    sta Pointer1
    cmp #$19
    bcs Statements::On::RequireGoto
    lda LineNumber
    asl a
    rol Pointer1
    asl a
    rol Pointer1
    adc LineNumber
    sta LineNumber
    lda Pointer1
    adc LineNumber+1
    sta LineNumber+1
    asl LineNumber
    rol LineNumber+1
    lda LineNumber
    adc Delimiter
    sta LineNumber
    bcc NextCharacter
    inc LineNumber+1

;; <GetNextCharacter> and loop.
;; Also: NXTLGC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextCharacter:
    jsr GetNextCharacter
    jmp NextDigit
.endproc
