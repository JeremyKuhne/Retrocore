; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: DECIMAL LINE NUMBERS

;; Reads a decimal line number from the current text position, rejecting values at or above 64000.
;;
;; The character reader skips spaces between the digits. Before adding a digit to a value of 6400 ($1900) or more,
;; the routine branches to <Statements::On::RequireGoto> with the value's high byte in A, for the syntax error. That
;; code tests A for <TOKEN_GOTO>, so a value whose high byte is the token, followed by another digit, goes on into
;; <Statements::On>'s selection loop with whatever selector it holds instead: 43776 to 44031 in AppleSoft, 35072 to
;; 35327 on the PET.
;; In: A = current character, carry = clear for a digit
;; Out: LineNumber = line number, TextPointer = terminating character, A = terminating character, carry = set,
;;   zero = set when no digit was read or the terminator is a null or colon
;; Errors: SYNTAX for a value of 64000 or more, except the values above that go on into <Statements::On>'s loop
;; Also: LINGET (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc ReadLineNumber
    ldx #$00
    stx LineNumber
    stx LineNumber+1

;; A non-digit exits through <Statements::On::Done>; otherwise multiplies by 10 and adds the digit.
;; Also: MORLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
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
;; Also: NXTLGC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextCharacter:
    jsr GetNextCharacter
    jmp NextDigit
.endproc
