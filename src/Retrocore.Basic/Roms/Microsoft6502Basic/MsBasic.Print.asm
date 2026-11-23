; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: PRINT DISPATCH

;; Emits the expression and separator dispatch for PRINT.
;; Parameters: tabEntry = `TAB` and SPC handler, clearSpaceCarry = 1 to clear carry before SPC dispatch;
;;   clearCommaCarry = 1 to clear carry before comma dispatch;
;;   trailingSpace = 1 to print a separate space after a converted number
.macro PrintItems tabEntry, clearSpaceCarry, clearCommaCarry, trailingSpace
    .assert clearSpaceCarry = 0 || clearSpaceCarry = 1, "clearSpaceCarry is 0 or 1."
    .assert clearCommaCarry = 0 || clearCommaCarry = 1, "clearCommaCarry is 0 or 1."
    .assert trailingSpace = 0 || trailingSpace = 1, "trailingSpace is 0 or 1."

    .scope Statements continued

    ;; Prints a string expression and continues the PRINT statement.
    ;; In: FacMantissa3 = string descriptor address low byte, FacMantissa4 = its high byte
    ;; Also: STRDON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintStringItem
    jsr STRPRT
    .endproc

    ;; Continues PRINT at the current character.
    ;; Also: NEWCHR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintNextItem
    jsr GetCurrentCharacter
    .endproc

    ;; Prints expressions, handling comma zones, semicolons, `TAB` and SPC.
    ;;
    ;; At the end of the statement it prints a carriage return; the PET's `PRINT#` and `CMD` enter here too.
    ;; In: A = current character, zero = set at the end of the statement
    ;; Entry:
    ;;   Item = prints the next item: at the end of the statement, returns without a carriage return; otherwise
    ;;     `TAB(`, `SPC(`, a comma, a semicolon, or an expression, a number formatted by <Float::FormatFac> through
    ;;     <STRLIT>; the `TAB(`, `SPC(`, comma and semicolon code, the vendors' included, returns here
    ;; See: <STRPRT>, <Float::FormatFac>, <COMPRT>
    ;; Also: PRINT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Print
    beq CRDO

;; Continues PRINT without adding a newline if the statement ends.
;; In: A = current character, zero = set at the end of the statement
;; Also: PRINTC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Item:
    beq PRTRTS
    cmp #TOKEN_TAB
    beq tabEntry
    cmp #TOKEN_SPC
    .if clearSpaceCarry
        clc
    .endif
    beq tabEntry
    cmp #','
    .if clearCommaCarry
        clc
    .endif
    beq COMPRT
    cmp #';'
    beq NOTABR
    jsr FRMEVL
    bit ValueType
    bmi PrintStringItem
    jsr Float::FormatFac
    jsr STRLIT
    .if trailingSpace

;; Prints a converted number and a trailing space, then continues PRINT.
;; Also: LINCHK (M6502)
NumberItem:
        jsr STRPRT
        jsr OUTSPC
        bne PrintNextItem
    .else
        jmp PrintStringItem
    .endif
    .endproc
    .endscope

.endmacro
