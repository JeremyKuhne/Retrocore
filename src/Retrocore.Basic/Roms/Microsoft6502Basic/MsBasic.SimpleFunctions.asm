; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: FREE SPACE AND POSITION
;
; These entries follow array multiplication and precede the user-defined-function code.

;; Emits the free-space, position and integer-to-float entries.
;; Parameters: setCarry = 1 to set carry before the <ReturnByte> branch, 0 to leave it unchanged;
;;   cursorRead = optional, the operating system's routine that returns the cursor's column in Y when called with carry
;;   set, for `POS` to call instead of reading <TerminalPosition> (the VIC-20's PLOT)
.macro SimpleFunctions setCarry, cursorRead
    .assert setCarry = 0 || setCarry = 1, "setCarry must be 0 or 1."

    .scope Functions continued

    ;; Collects unused strings and returns free space between <ArraysEnd> and <StringsBottom> in <Fac>.
    ;;
    ;; If the argument is a string, its temporary descriptor is released before collection. The 16-bit
    ;; difference is converted as a signed integer, so free space of 32768 bytes or more appears negative.
    ;; Also: FRE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Fre
    lda ValueType
    beq Collect
    jsr Strings::ReleaseFac

;; Collects garbage and subtracts.
;; Also: NOFREF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Collect:
    jsr Strings::CollectGarbage
    sec
    lda StringsBottom
    sbc ArraysEnd
    tay
    lda StringsBottom+1
    sbc ArraysEnd+1
    .endproc
    .endscope

    ;; Converts the signed 16-bit value in A:Y to floating point in <Fac>.
    ;; In: A = high byte, Y = low byte
    ;; Out: Fac = numeric result, ValueType = numeric
    ;; Also: GIVAYF (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReturnSignedWord
    ldx #$00
    stx ValueType
    sta FacMantissa1
    sty FacMantissa2
    ldx #$90
    jmp Float::ConvertSignedWord
    .endproc

    .scope Functions continued

    ;; Returns the current text output column in <Fac>.
    ;; Also: POS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Pos
    .ifnblank cursorRead
        sec
        jsr cursorRead
    .else
        ldy TerminalPosition
    .endif
    .endproc
    .endscope

    ;; Converts the unsigned byte in Y to floating point in <Fac>.
    ;; In: Y = value
    ;; Out: Fac = numeric result, ValueType = numeric
    ;; Also: SNGFLT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReturnByte
    lda #$00
    .if setCarry
        sec
    .endif
    beq ReturnSignedWord             ; always taken: A is zero
    .endproc
.endmacro
