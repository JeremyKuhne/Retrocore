; COMMODORE BASIC: DISPATCH TABLES AND TEXT
;
; The caller places this module at the start of BASIC ROM and supplies the workspace from
; Commodore.Equates.asm. Entries in the statement table are addresses minus one for RTS dispatch;
; the function table contains actual entry addresses.

.include "../../Microsoft6502Basic/MsBasic.OperatorTable.asm"

;; Emits the Commodore statement, function and operator tables, reserved words and messages.
;; Parameters: goToken = 1 to include the GO spelling; diskCommands = 1 to add the disk statements;
;;   badData = 1 for the early BAD DATA error, 0 for FILE DATA;
;;   singleReturn = 1 for a carriage return alone in READY and BREAK, 0 for CR/LF
.macro COMMODORE_DISPATCH_TABLES goToken, diskCommands, badData, singleReturn
    .assert goToken = 0 || goToken = 1, "goToken is 0 or 1."
    .assert diskCommands = 0 || diskCommands = 1, "diskCommands is 0 or 1."
    .assert badData = 0 || badData = 1, "badData is 0 or 1."
    .assert singleReturn = 0 || singleReturn = 1, "singleReturn is 0 or 1."
    .assert diskCommands = 0 || goToken = 1, "Disk commands follow GO."

;; Statement handler addresses minus one, indexed by token starting with END.
;; Disk commands, when present, follow GO in this table even though their tokens follow the functions.
STMDSP:
    .word END - 1
    .word FOR - 1
    .word NEXT - 1
    .word DATA - 1
    .word INPUTN - 1
    .word INPUT - 1
    .word DIM - 1
    .word READ - 1
    .word LET - 1
    .word GOTO - 1
    .word RUN - 1
    .word IF - 1
    .word RESTOR - 1
    .word GOSUB - 1
    .word RETURN - 1
    .word REM - 1
    .word STOP - 1
    .word ONGOTO - 1
    .word FNWAIT - 1
    .word CQLOAD - 1
    .word CQSAVE - 1
    .word CQVERF - 1
    .word DEF - 1
    .word POKE - 1
    .word PRINTN - 1
    .word PRINT - 1
    .word CONT - 1
    .word LIST - 1
    .word CLEAR - 1
    .word CMD - 1
    .word CQSYS - 1
    .word CQOPEN - 1
    .word CQCLOS - 1
    .word GET - 1
    .word SCRATH - 1
.if diskCommands
    .word GO - 1
    .word CQCONC - 1
    .word CQDOPN - 1
    .word CQDCLS - 1
    .word CQRECD - 1
    .word CQFORM - 1
    .word CQCOLL - 1
    .word CQBACK - 1
    .word CQCOPY - 1
    .word CQAPND - 1
    .word CQDSAV - 1
    .word CQDLOD - 1
    .word CQDCAT - 1
    .word CQRENM - 1
    .word CQSCRA - 1
    .word CQDCAT - 1
.endif

;; Function entry addresses, in token order from SGN through MID$.
FUNDSP:
    .word SGN
    .word INT
    .word ABS

;; Initial USR function target: the writable jump at <USRPOK>.
USRLOC:
    .word USRPOK
    .word FRE
    .word POS
    .word SQR
    .word RND
    .word LOG
    .word EXP

;; COS function-table entry.
COSFIX:
    .word COS
;; SIN function-table entry.
SINFIX:
    .word SIN
;; TAN function-table entry.
TANFIX:
    .word TAN
;; ATN function-table entry.
ATNFIX:
    .word ATN
    .word PEEK
    .word LEN
    .word STR
    .word VAL
    .word ASC
    .word CHR
    .word LEFT
    .word RIGHT
    .word MID

    OPERATOR_TABLE 0, 0, ANDOP

;; Reserved words in token order; bit 7 marks the last character of each spelling.
;; <CRUNCH> searches this list and <LIST> expands tokens from it. A zero byte ends the list.
RESLST:
    .byte "EN", 'D' | $80
ENDTK = $80                         ;; token for END
    .byte "FO", 'R' | $80
FORTK = $81                         ;; token for FOR
    .byte "NEX", 'T' | $80
    .byte "DAT", 'A' | $80
DATATK = $83                        ;; token for DATA
    .byte "INPUT", '#' | $80
    .byte "INPU", 'T' | $80
    .byte "DI", 'M' | $80
    .byte "REA", 'D' | $80
    .byte "LE", 'T' | $80
    .byte "GOT", 'O' | $80
GOTOTK = $89                        ;; token for GOTO
    .byte "RU", 'N' | $80
    .byte 'I', 'F' | $80
    .byte "RESTOR", 'E' | $80
    .byte "GOSU", 'B' | $80
GOSUTK = $8D                        ;; token for GOSUB
    .byte "RETUR", 'N' | $80
    .byte "RE", 'M' | $80
REMTK = $8F                         ;; token for REM
    .byte "STO", 'P' | $80
    .byte 'O', 'N' | $80
    .byte "WAI", 'T' | $80
    .byte "LOA", 'D' | $80
    .byte "SAV", 'E' | $80
    .byte "VERIF", 'Y' | $80
    .byte "DE", 'F' | $80
    .byte "POK", 'E' | $80
    .byte "PRINT", '#' | $80
    .byte "PRIN", 'T' | $80
PRINTK = $99                        ;; token for PRINT
    .byte "CON", 'T' | $80
    .byte "LIS", 'T' | $80
    .byte "CL", 'R' | $80
    .byte "CM", 'D' | $80
    .byte "SY", 'S' | $80
    .byte "OPE", 'N' | $80
    .byte "CLOS", 'E' | $80
    .byte "GE", 'T' | $80
    .byte "NE", 'W' | $80
SCRATK = $A2                        ;; token for NEW, the last ordinary statement
    .byte "TAB", '(' | $80
TABTK = $A3                         ;; token for TAB(
    .byte 'T', 'O' | $80
TOTK = $A4                          ;; token for TO
    .byte 'F', 'N' | $80
FNTK = $A5                          ;; token for FN
    .byte "SPC", '(' | $80
SPCTK = $A6                         ;; token for SPC(
    .byte "THE", 'N' | $80
THENTK = $A7                        ;; token for THEN
    .byte "NO", 'T' | $80
NOTTK = $A8                         ;; token for NOT
    .byte "STE", 'P' | $80
STEPTK = $A9                        ;; token for STEP
    .byte '+' | $80, '-' | $80, '*' | $80, '/' | $80, '^' | $80
    .byte "AN", 'D' | $80
    .byte 'O', 'R' | $80
    .byte '>' | $80
GREATK = $B1                        ;; token for >
    .byte '=' | $80
EQULTK = $B2                        ;; token for =
    .byte '<' | $80
LESSTK = $B3                         ;; token for <
    .byte "SG", 'N' | $80
ONEFUN = $B4                        ;; token for SGN, the first function
    .byte "IN", 'T' | $80
    .byte "AB", 'S' | $80
    .byte "US", 'R' | $80
    .byte "FR", 'E' | $80
    .byte "PO", 'S' | $80
    .byte "SQ", 'R' | $80
    .byte "RN", 'D' | $80
    .byte "LO", 'G' | $80
    .byte "EX", 'P' | $80
    .byte "CO", 'S' | $80
    .byte "SI", 'N' | $80
    .byte "TA", 'N' | $80
    .byte "AT", 'N' | $80
    .byte "PEE", 'K' | $80
    .byte "LE", 'N' | $80
    .byte "STR", '$' | $80
    .byte "VA", 'L' | $80
    .byte "AS", 'C' | $80
    .byte "CHR", '$' | $80
LASNUM = $C7                        ;; token for CHR$, the last single-argument function
    .byte "LEFT", '$' | $80
    .byte "RIGHT", '$' | $80
    .byte "MID", '$' | $80
.if goToken
    .byte 'G', 'O' | $80
GOTK = $CB                          ;; token for GO
.endif
.if diskCommands
    .byte "CONCA", 'T' | $80
    .byte "DOPE", 'N' | $80
    .byte "DCLOS", 'E' | $80
    .byte "RECOR", 'D' | $80
    .byte "HEADE", 'R' | $80
    .byte "COLLEC", 'T' | $80
    .byte "BACKU", 'P' | $80
    .byte "COP", 'Y' | $80
    .byte "APPEN", 'D' | $80
    .byte "DSAV", 'E' | $80
    .byte "DLOA", 'D' | $80
    .byte "CATALO", 'G' | $80
    .byte "RENAM", 'E' | $80
    .byte "SCRATC", 'H' | $80
    .byte "DIRECTOR", 'Y' | $80
.endif
    .byte $00

;; Error messages addressed by the ERR constants' byte offsets.
;; Bit 7 on the last character ends each message; <ERROR> appends <ERR>.
ERRTAB:
ERRNF = * - ERRTAB                  ;; offset of NEXT WITHOUT FOR in <ERRTAB>
    .byte "NEXT WITHOUT FO", 'R' | $80
ERRSN = * - ERRTAB                  ;; offset of SYNTAX in <ERRTAB>
    .byte "SYNTA", 'X' | $80
ERRRG = * - ERRTAB                  ;; offset of RETURN WITHOUT GOSUB in <ERRTAB>
    .byte "RETURN WITHOUT GOSU", 'B' | $80
ERROD = * - ERRTAB                  ;; offset of OUT OF DATA in <ERRTAB>
    .byte "OUT OF DAT", 'A' | $80
ERRFC = * - ERRTAB                  ;; offset of ILLEGAL QUANTITY in <ERRTAB>
    .byte "ILLEGAL QUANTIT", 'Y' | $80
.if ERROR_PADDING5
    .res 5, $00
.endif
    .assert ERROV = * - ERRTAB, "The OVERFLOW error offset must match the workspace."
    .byte "OVERFLO", 'W' | $80
ERROM = * - ERRTAB                  ;; offset of OUT OF MEMORY in <ERRTAB>
    .byte "OUT OF MEMOR", 'Y' | $80
ERRUS = * - ERRTAB                  ;; offset of UNDEF'D STATEMENT in <ERRTAB>
    .byte "UNDEF'D STATEMEN", 'T' | $80
ERRBS = * - ERRTAB                  ;; offset of BAD SUBSCRIPT in <ERRTAB>
    .byte "BAD SUBSCRIP", 'T' | $80
ERRDD = * - ERRTAB                  ;; offset of REDIM'D ARRAY in <ERRTAB>
    .byte "REDIM'D ARRA", 'Y' | $80
    .assert ERRDV0 = * - ERRTAB, "The DIVISION BY ZERO error offset must match the workspace."
    .byte "DIVISION BY ZER", 'O' | $80
ERRID = * - ERRTAB                  ;; offset of ILLEGAL DIRECT in <ERRTAB>
    .byte "ILLEGAL DIREC", 'T' | $80
ERRTM = * - ERRTAB                  ;; offset of TYPE MISMATCH in <ERRTAB>
    .byte "TYPE MISMATC", 'H' | $80
ERRLS = * - ERRTAB                  ;; offset of STRING TOO LONG in <ERRTAB>
    .byte "STRING TOO LON", 'G' | $80
ERRBD = * - ERRTAB                  ;; offset of the file-data error in <ERRTAB>
.if badData
    .byte "BAD DAT", 'A' | $80
.else
    .byte "FILE DAT", 'A' | $80
.endif
ERRST = * - ERRTAB                  ;; offset of FORMULA TOO COMPLEX in <ERRTAB>
    .byte "FORMULA TOO COMPLE", 'X' | $80
ERRCN = * - ERRTAB                  ;; offset of CAN'T CONTINUE in <ERRTAB>
    .byte "CAN'T CONTINU", 'E' | $80
ERRUF = * - ERRTAB                  ;; offset of UNDEF'D FUNCTION in <ERRTAB>
    .byte "UNDEF'D FUNCTIO", 'N' | $80
    .assert * - ERRTAB <= 256, "The error message offsets must fit in one byte."

;; Suffix appended to an error message.
ERR:
    .asciiz " ERROR"
;; Introduction before the line number in an error or break message.
INTXT:
    .asciiz " IN "
;; Message shown when the interpreter is ready for another command.
REDDY:
    .byte $0D
.if .not singleReturn
    .byte $0A
.endif
    .byte "READY.", $0D
.if .not singleReturn
    .byte $0A
.endif
    .byte $00
;; Message shown when execution is stopped.
BRKTXT:
    .byte $0D
.if .not singleReturn
    .byte $0A
.endif
    .asciiz "BREAK"

FORSIZ = 2 * ADDPRC + 16            ;; size of a FOR stack frame
.endmacro
