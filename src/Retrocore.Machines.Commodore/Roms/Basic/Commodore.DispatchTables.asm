; retrocore: style=strict
; COMMODORE BASIC: DISPATCH TABLES AND TEXT
;
; The caller places this module at the start of BASIC ROM and supplies the workspace from
; Commodore.Equates.asm. Entries in the statement table are addresses minus one for RTS dispatch;
; the function table contains actual entry addresses.

.include "../../Microsoft6502Basic/MsBasic.OperatorTable.asm"

;; Emits the Commodore statement, function and operator tables, reserved words and messages.
;; Parameters: goToken = 1 to include the `GO` spelling; diskCommands = 1 to add the disk statements;
;;   badData = 1 for the early `BAD DATA` error, 0 for `FILE DATA`;
;;   singleReturn = 1 for a carriage return alone in `READY` and `BREAK`, 0 for `CR/LF`
.macro COMMODORE_DISPATCH_TABLES goToken, diskCommands, badData, singleReturn
    .assert goToken = 0 || goToken = 1, "goToken is 0 or 1."
    .assert diskCommands = 0 || diskCommands = 1, "diskCommands is 0 or 1."
    .assert badData = 0 || badData = 1, "badData is 0 or 1."
    .assert singleReturn = 0 || singleReturn = 1, "singleReturn is 0 or 1."
    .assert diskCommands = 0 || goToken = 1, "Disk commands follow GO."

;; Statement handler addresses minus one, indexed by token starting with `END`.
;; Disk commands, when present, follow `GO` in this table even though their tokens follow the functions.
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
    .word KernalLoad - 1
    .word KernalSave - 1
    .word KernalVerify - 1
    .word DEF - 1
    .word POKE - 1
    .word PRINTN - 1
    .word PRINT - 1
    .word CONT - 1
    .word LIST - 1
    .word CLEAR - 1
    .word CMD - 1
    .word KernalSys - 1
    .word KernalOpen - 1
    .word KernalClose - 1
    .word GET - 1
    .word SCRATH - 1
    .if diskCommands
        .word GO - 1
        .word KernalConcat - 1
        .word KernalDiskOpen - 1
        .word KernalDiskClose - 1
        .word KernalRecord - 1
        .word KernalHeader - 1
        .word KernalCollect - 1
        .word KernalBackup - 1
        .word KernalCopy - 1
        .word KernalAppend - 1
        .word KernalDiskSave - 1
        .word KernalDiskLoad - 1
        .word KernalDirectory - 1
        .word KernalRename - 1
        .word KernalScratch - 1
        .word KernalDirectory - 1
    .endif

;; Function entry addresses, in token order from `SGN` through `MID$`.
FUNDSP:
    .word SGN
    .word INT
    .word ABS

;; Initial `USR` function target: the writable jump at <UserVector>.
USRLOC:
    .word UserVector
    .word FRE
    .word POS
    .word SQR
    .word RND
    .word LOG
    .word EXP

;; `COS` function-table entry.
COSFIX:
    .word COS
;; `SIN` function-table entry.
SINFIX:
    .word SIN
;; `TAN` function-table entry.
TANFIX:
    .word TAN
;; `ATN` function-table entry.
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

    OperatorEntries 0, 0, Operators::And

;; Reserved words in token order; bit 7 marks the last character of each spelling.
;; <CRUNCH> searches this list and <Statements::List> expands tokens from it. A zero byte ends the list.
RESLST:
    .byte "EN", 'D' | $80
    ;; The token of `END`, the first statement token.
    ;; Also: ENDTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_END = $80
    .byte "FO", 'R' | $80
    ;; The token of `FOR`.
    ;; Also: FORTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_FOR = $81
    .byte "NEX", 'T' | $80
    .byte "DAT", 'A' | $80
    ;; The token of `DATA`.
    ;; Also: DATATK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_DATA = $83
    .byte "INPUT", '#' | $80
    .byte "INPU", 'T' | $80
    .byte "DI", 'M' | $80
    .byte "REA", 'D' | $80
    .byte "LE", 'T' | $80
    .byte "GOT", 'O' | $80
    ;; The token of `GOTO`.
    ;; Also: GOTOTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_GOTO = $89
    .byte "RU", 'N' | $80
    .byte 'I', 'F' | $80
    .byte "RESTOR", 'E' | $80
    .byte "GOSU", 'B' | $80
    ;; The token of `GOSUB`.
    ;; Also: GOSUTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_GOSUB = $8D
    .byte "RETUR", 'N' | $80
    .byte "RE", 'M' | $80
    ;; The token of `REM`.
    ;; Also: REMTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_REM = $8F
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
    ;; The token of `PRINT` (the tokenizer stores it for ?).
    ;; Also: PRINTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_PRINT = $99
    .byte "CON", 'T' | $80
    .byte "LIS", 'T' | $80
    .byte "CL", 'R' | $80
    .byte "CM", 'D' | $80
    .byte "SY", 'S' | $80
    .byte "OPE", 'N' | $80
    .byte "CLOS", 'E' | $80
    .byte "GE", 'T' | $80
    .byte "NE", 'W' | $80
    ;; The token of `NEW`, the last ordinary statement.
    ;; Also: SCRATK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_NEW = $A2
    .byte "TAB", '(' | $80
    ;; The token of `TAB(`.
    ;; Also: TABTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_TAB = $A3
    .byte 'T', 'O' | $80
    ;; The token of `TO`.
    ;; Also: TOTK (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    TOKEN_TO = $A4
    .byte 'F', 'N' | $80
    ;; The token of `FN`.
    ;; Also: FNTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_FN = $A5
    .byte "SPC", '(' | $80
    ;; The token of `SPC(`.
    ;; Also: SPCTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_SPC = $A6
    .byte "THE", 'N' | $80
    ;; The token of `THEN`.
    ;; Also: THENTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_THEN = $A7
    .byte "NO", 'T' | $80
    ;; The token of `NOT`.
    ;; Also: NOTTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_NOT = $A8
    .byte "STE", 'P' | $80
    ;; The token of `STEP`.
    ;; Also: STEPTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_STEP = $A9
    ;; The token of `+`.
    ;; Also: PLUSTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_PLUS = $AA
    ;; The token of `-`.
    ;; Also: MINUTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_MINUS = TOKEN_PLUS + 1
    .byte '+' | $80, '-' | $80, '*' | $80, '/' | $80, '^' | $80
    .byte "AN", 'D' | $80
    .byte 'O', 'R' | $80
    .byte '>' | $80
    ;; The token of `>`, the first relational token.
    ;; Also: GREATK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_GREATER = $B1
    .byte '=' | $80
    ;; The token of `=`.
    ;; Also: EQULTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_EQUAL = $B2
    .byte '<' | $80
    ;; The token of `<`.
    ;; Also: LESSTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_LESS = $B3
    .byte "SG", 'N' | $80
    ;; The token of `SGN`, the first function.
    ;; Also: ONEFUN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_FIRST_FUNCTION = $B4
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
    ;; The token of `CHR$`, the last one-argument function.
    ;; Also: LASNUM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    TOKEN_LAST_SIMPLE_FUNCTION = $C7
    .byte "LEFT", '$' | $80
    .byte "RIGHT", '$' | $80
    .byte "MID", '$' | $80
    .if goToken
        .byte 'G', 'O' | $80
        ;; The token of `GO`.
        ;; Also: GOTK (M6502, CBM4S79, HV2, HV4, HV4R)
        TOKEN_GO = $CB
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

;; Error messages addressed by the ERROR_* constants' byte offsets.
;; Bit 7 on the last character ends each message; <ERROR> appends <ErrorSuffix>.
ERRTAB:
    ;; Offset of `NEXT` WITHOUT `FOR` in <ERRTAB>.
    ;; Also: ERRNF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_NEXT_WITHOUT_FOR = * - ERRTAB
    .byte "NEXT WITHOUT FO", 'R' | $80
    ;; Offset of SYNTAX in <ERRTAB>.
    ;; Also: ERRSN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_SYNTAX = * - ERRTAB
    .byte "SYNTA", 'X' | $80
    ;; Offset of `RETURN` WITHOUT `GOSUB` in <ERRTAB>.
    ;; Also: ERRRG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_RETURN_WITHOUT_GOSUB = * - ERRTAB
    .byte "RETURN WITHOUT GOSU", 'B' | $80
    ;; Offset of OUT OF `DATA` in <ERRTAB>.
    ;; Also: ERROD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OUT_OF_DATA = * - ERRTAB
    .byte "OUT OF DAT", 'A' | $80
    ;; Offset of ILLEGAL QUANTITY in <ERRTAB>.
    ;; Also: ERRFC (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    ERROR_ILLEGAL_QUANTITY = * - ERRTAB
    .byte "ILLEGAL QUANTIT", 'Y' | $80
    .if ERROR_PADDING5
        .res 5, $00
    .endif
    ;; Offset of OVERFLOW in <ERRTAB>.
    ;; Also: ERROV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OVERFLOW = * - ERRTAB
    .byte "OVERFLO", 'W' | $80
    ;; Offset of OUT OF MEMORY in <ERRTAB>.
    ;; Also: ERROM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OUT_OF_MEMORY = * - ERRTAB
    .byte "OUT OF MEMOR", 'Y' | $80
    ;; Offset of UNDEF'D STATEMENT in <ERRTAB>.
    ;; Also: ERRUS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_UNDEFINED_STATEMENT = * - ERRTAB
    .byte "UNDEF'D STATEMEN", 'T' | $80
    ;; Offset of `BAD` SUBSCRIPT in <ERRTAB>.
    ;; Also: ERRBS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_BAD_SUBSCRIPT = * - ERRTAB
    .byte "BAD SUBSCRIP", 'T' | $80
    ;; Offset of REDIM'D ARRAY in <ERRTAB>.
    ;; Also: ERRDD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_REDIMENSIONED_ARRAY = * - ERRTAB
    .byte "REDIM'D ARRA", 'Y' | $80
    ;; Offset of DIVISION BY `ZERO` in <ERRTAB>.
    ;; Also: ERRDV0 (M6502)
    ERROR_DIVISION_BY_ZERO = * - ERRTAB
    .byte "DIVISION BY ZER", 'O' | $80
    ;; Offset of ILLEGAL DIRECT in <ERRTAB>.
    ;; Also: ERRID (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_ILLEGAL_DIRECT = * - ERRTAB
    .byte "ILLEGAL DIREC", 'T' | $80
    ;; Offset of TYPE MISMATCH in <ERRTAB>.
    ;; Also: ERRTM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_TYPE_MISMATCH = * - ERRTAB
    .byte "TYPE MISMATC", 'H' | $80
    ;; Offset of STRING TOO LONG in <ERRTAB>.
    ;; Also: ERRLS (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    ERROR_STRING_TOO_LONG = * - ERRTAB
    .byte "STRING TOO LON", 'G' | $80
    ;; Offset of the file-data message: `BAD` `DATA` in BASIC 1, FILE `DATA` later.
    ;; Also: ERRBD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_FILE_DATA = * - ERRTAB
    .if badData
        .byte "BAD DAT", 'A' | $80
    .else
        .byte "FILE DAT", 'A' | $80
    .endif
    ;; Offset of FORMULA TOO COMPLEX in <ERRTAB>.
    ;; Also: ERRST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_FORMULA_TOO_COMPLEX = * - ERRTAB
    .byte "FORMULA TOO COMPLE", 'X' | $80
    ;; Offset of CAN'T CONTINUE in <ERRTAB>.
    ;; Also: ERRCN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_CANT_CONTINUE = * - ERRTAB
    .byte "CAN'T CONTINU", 'E' | $80
    ;; Offset of UNDEF'D FUNCTION in <ERRTAB>.
    ;; Also: ERRUF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_UNDEFINED_FUNCTION = * - ERRTAB
    .byte "UNDEF'D FUNCTIO", 'N' | $80
    .assert * - ERRTAB <= 256, "The error message offsets must fit in one byte."

;; Suffix appended to an error message.
;; Also: ERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ErrorSuffix:
    .asciiz " ERROR"
;; Introduction before the line number in an error or break message.
;; Also: INTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LineNumberPrefix:
    .asciiz " IN "
;; Message shown when the interpreter is ready for another command.
;; Also: REDDY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReadyMessage:
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
;; Also: BRKTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
BreakMessage:
    .byte $0D
    .if .not singleReturn
        .byte $0A
    .endif
    .asciiz "BREAK"
.endmacro
