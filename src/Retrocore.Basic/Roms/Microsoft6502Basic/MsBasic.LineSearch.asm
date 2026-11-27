; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: PROGRAM LINE SEARCH

;; Finds the stored program line equal to or immediately after <LineNumber>.
;; In: LineNumber = line number to find
;; Out: SourceStart = link field of the matching or following line or the end marker, carry = set for an exact match
;; Entry:
;;   FromAddress = searches from the line at A (low) and X (high)
;;   Done = returns; <Statements::New> and List's range parsing branch here for a syntax error return
;; Also: FNDLIN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
.proc FindLine
    lda ProgramStart
    ldx ProgramStart+1

;; Searches from the line at A (low) and X (high).
;; Also: FNDLNC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
FromAddress:
    ldy #$01
    sta SourceStart
    stx SourceStart+1
    lda (SourceStart),y
    beq NotFound
    iny
    iny
    lda LineNumber+1
    cmp (SourceStart),y
    bcc Done
    beq CompareLow
    dey
    bne NextLine

;; High bytes equal: compares the low bytes.
;; Also: FNDLO1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CompareLow:
    lda LineNumber
    dey
    cmp (SourceStart),y
    bcc Done
    beq Done

;; Loads the link into A/X and loops.
;; Also: AFFRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NextLine:
    dey
    lda (SourceStart),y
    tax
    dey
    lda (SourceStart),y
    bcs FromAddress

;; Zero link (end of program): clears carry.
;; Also: FLINRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
NotFound:
    clc

;; Returns; <Statements::New> and List's range parsing branch here for a syntax error return.
;; Also: FLNRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
.endproc
