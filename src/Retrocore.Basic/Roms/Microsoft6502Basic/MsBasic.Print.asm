; MICROSOFT 6502 BASIC: PRINT DISPATCH

;; Emits the expression and separator dispatch for PRINT.
;; Parameters: tabEntry = TAB and SPC handler, clearSpaceCarry = 1 to clear carry before SPC dispatch;
;;   clearCommaCarry = 1 to clear carry before comma dispatch;
;;   trailingSpace = 1 to print a separate space after a converted number
.macro PRINT_CORE tabEntry, clearSpaceCarry, clearCommaCarry, trailingSpace
    .assert clearSpaceCarry = 0 || clearSpaceCarry = 1, "clearSpaceCarry is 0 or 1."
    .assert clearCommaCarry = 0 || clearCommaCarry = 1, "clearCommaCarry is 0 or 1."
    .assert trailingSpace = 0 || trailingSpace = 1, "trailingSpace is 0 or 1."

;; Prints a string expression and continues the PRINT statement.
;; In: FACMO/FACLO = string descriptor address
STRDON:
    jsr STRPRT

;; Continues PRINT at the current character.
NEWCHR:
    jsr CHRGOT

;; Prints expressions, handling comma zones, semicolons, TAB and SPC.
;; In: A = current character, zero = set at the end of the statement
;; See: <STRPRT>, <FOUT>, <COMPRT>
PRINT:
    beq CRDO

;; Continues PRINT without adding a newline if the statement ends.
;; In: A = current character, zero = set at the end of the statement
PRINTC:
    beq PRTRTS
    cmp #TABTK
    beq tabEntry
    cmp #SPCTK
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
    bit VALTYP
    bmi STRDON
    jsr FOUT
    jsr STRLIT
.if trailingSpace

;; Prints a converted number and a trailing space, then continues PRINT.
LINCHK:
    jsr STRPRT
    jsr OUTSPC
    bne NEWCHR
.else
    jmp STRDON
.endif
.endmacro
