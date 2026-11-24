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
.macro CommodoreDispatchTables goToken, diskCommands, badData, singleReturn
    .assert goToken = 0 || goToken = 1, "goToken is 0 or 1."
    .assert diskCommands = 0 || diskCommands = 1, "diskCommands is 0 or 1."
    .assert badData = 0 || badData = 1, "badData is 0 or 1."
    .assert singleReturn = 0 || singleReturn = 1, "singleReturn is 0 or 1."
    .assert diskCommands = 0 || goToken = 1, "Disk commands follow GO."

;; Statement handler addresses minus one, indexed by token starting with `END`.
;; Disk commands, when present, follow `GO` in this table even though their tokens follow the functions.
;; Also: STMDSP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StatementTable:
    .word Statements::End - 1
    .word Statements::For - 1
    .word Statements::Next - 1
    .word Statements::Data - 1
    .word Statements::InputNumber - 1
    .word Statements::Input - 1
    .word Statements::Dim - 1
    .word Statements::Read - 1
    .word Statements::Let - 1
    .word Statements::GoTo - 1
    .word Statements::Run - 1
    .word Statements::If - 1
    .word Statements::Restore - 1
    .word Statements::GoSub - 1
    .word Statements::Return - 1
    .word Statements::Rem - 1
    .word Statements::Stop - 1
    .word Statements::On - 1
    .word Statements::Wait - 1
    .word KernalLoad - 1
    .word KernalSave - 1
    .word KernalVerify - 1
    .word Statements::Def - 1
    .word Statements::Poke - 1
    .word Statements::PrintNumber - 1
    .word Statements::Print - 1
    .word Statements::Cont - 1
    .word Statements::List - 1
    .word Statements::Clear - 1
    .word Statements::Cmd - 1
    .word KernalSys - 1
    .word KernalOpen - 1
    .word KernalClose - 1
    .word Statements::Get - 1
    .word Statements::New - 1
    .if diskCommands
        .word Statements::Go - 1
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
    ;; Also: FUNDSP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FunctionTable
    .word Functions::Sgn
    .word Functions::Int
    .word Functions::Abs

;; `USR`'s entry: the writable jump at <UserVector>.
;; Also: USRLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Usr:
    .word UserVector
    .word Functions::Fre
    .word Functions::Pos
    .word Functions::Sqr
    .word Functions::Rnd
    .word Functions::Log
    .word Functions::Exp

;; `COS`'s entry, Microsoft's patch point; nothing refers to it, and the label is kept for its old name.
;; Also: COSFIX (M6502)
Cos:
    .word Functions::Cos

;; `SIN`'s entry, Microsoft's patch point; kept for its old name.
;; Also: SINFIX (M6502)
Sin:
    .word Functions::Sin

;; `TAN`'s entry, Microsoft's patch point; kept for its old name.
;; Also: TANFIX (M6502)
Tan:
    .word Functions::Tan

;; `ATN`'s entry, Microsoft's patch point; kept for its old name.
;; Also: ATNFIX (M6502)
Atn:
    .word Functions::Atn
    .word Functions::Peek
    .word Functions::Len
    .word Functions::Str
    .word Functions::Val
    .word Functions::Asc
    .word Functions::Chr
    .word Functions::Left
    .word Functions::Right
    .word Functions::Mid
    .endproc

    OperatorEntries 0, 0, Operators::And

;; Reserved words in token order; bit 7 marks the last character of each spelling.
;; <Tokenize> searches this list and <Statements::List> expands tokens from it. A zero byte ends the list.
;; Also: RESLST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReservedWords:
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
;; Bit 7 on the last character ends each message; <ReportError> appends <ErrorSuffix>.
;; Also: ERRTAB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ErrorMessages:
    ;; Offset of "NEXT WITHOUT FOR" in <ErrorMessages>.
    ;; Also: ERRNF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_NEXT_WITHOUT_FOR = * - ErrorMessages
    .byte "NEXT WITHOUT FO", 'R' | $80
    ;; Offset of "SYNTAX" in <ErrorMessages>.
    ;; Also: ERRSN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_SYNTAX = * - ErrorMessages
    .byte "SYNTA", 'X' | $80
    ;; Offset of "RETURN WITHOUT GOSUB" in <ErrorMessages>.
    ;; Also: ERRRG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_RETURN_WITHOUT_GOSUB = * - ErrorMessages
    .byte "RETURN WITHOUT GOSU", 'B' | $80
    ;; Offset of "OUT OF DATA" in <ErrorMessages>.
    ;; Also: ERROD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OUT_OF_DATA = * - ErrorMessages
    .byte "OUT OF DAT", 'A' | $80
    ;; Offset of "ILLEGAL QUANTITY" in <ErrorMessages>.
    ;; Also: ERRFC (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    ERROR_ILLEGAL_QUANTITY = * - ErrorMessages
    .byte "ILLEGAL QUANTIT", 'Y' | $80
    .if ERROR_PADDING5
        .res 5, $00
    .endif
    ;; Offset of "OVERFLOW" in <ErrorMessages>.
    ;; Also: ERROV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OVERFLOW = * - ErrorMessages
    .byte "OVERFLO", 'W' | $80
    ;; Offset of "OUT OF MEMORY" in <ErrorMessages>.
    ;; Also: ERROM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_OUT_OF_MEMORY = * - ErrorMessages
    .byte "OUT OF MEMOR", 'Y' | $80
    ;; Offset of "UNDEF'D STATEMENT" in <ErrorMessages>.
    ;; Also: ERRUS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_UNDEFINED_STATEMENT = * - ErrorMessages
    .byte "UNDEF'D STATEMEN", 'T' | $80
    ;; Offset of "BAD SUBSCRIPT" in <ErrorMessages>.
    ;; Also: ERRBS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_BAD_SUBSCRIPT = * - ErrorMessages
    .byte "BAD SUBSCRIP", 'T' | $80
    ;; Offset of "REDIM'D ARRAY" in <ErrorMessages>.
    ;; Also: ERRDD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_REDIMENSIONED_ARRAY = * - ErrorMessages
    .byte "REDIM'D ARRA", 'Y' | $80
    ;; Offset of "DIVISION BY ZERO" in <ErrorMessages>.
    ;; Also: ERRDV0 (M6502)
    ERROR_DIVISION_BY_ZERO = * - ErrorMessages
    .byte "DIVISION BY ZER", 'O' | $80
    ;; Offset of "ILLEGAL DIRECT" in <ErrorMessages>.
    ;; Also: ERRID (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_ILLEGAL_DIRECT = * - ErrorMessages
    .byte "ILLEGAL DIREC", 'T' | $80
    ;; Offset of "TYPE MISMATCH" in <ErrorMessages>.
    ;; Also: ERRTM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_TYPE_MISMATCH = * - ErrorMessages
    .byte "TYPE MISMATC", 'H' | $80
    ;; Offset of "STRING TOO LONG" in <ErrorMessages>.
    ;; Also: ERRLS (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    ERROR_STRING_TOO_LONG = * - ErrorMessages
    .byte "STRING TOO LON", 'G' | $80
    ;; Offset of the file-data message: "BAD DATA" in BASIC 1, "FILE DATA" later.
    ;; Also: ERRBD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_FILE_DATA = * - ErrorMessages
    .if badData
        .byte "BAD DAT", 'A' | $80
    .else
        .byte "FILE DAT", 'A' | $80
    .endif
    ;; Offset of "FORMULA TOO COMPLEX" in <ErrorMessages>.
    ;; Also: ERRST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_FORMULA_TOO_COMPLEX = * - ErrorMessages
    .byte "FORMULA TOO COMPLE", 'X' | $80
    ;; Offset of "CAN'T CONTINUE" in <ErrorMessages>.
    ;; Also: ERRCN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_CANT_CONTINUE = * - ErrorMessages
    .byte "CAN'T CONTINU", 'E' | $80
    ;; Offset of "UNDEF'D FUNCTION" in <ErrorMessages>.
    ;; Also: ERRUF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    ERROR_UNDEFINED_FUNCTION = * - ErrorMessages
    .byte "UNDEF'D FUNCTIO", 'N' | $80
    .assert * - ErrorMessages <= 256, "The error message offsets must fit in one byte."

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
    .byte CARRIAGE_RETURN
    .if .not singleReturn
        .byte LINE_FEED
    .endif
    .byte "READY.", CARRIAGE_RETURN
    .if .not singleReturn
        .byte LINE_FEED
    .endif
    .byte $00
;; Message shown when execution is stopped.
;; Also: BRKTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
BreakMessage:
    .byte CARRIAGE_RETURN
    .if .not singleReturn
        .byte LINE_FEED
    .endif
    .asciiz "BREAK"
.endmacro
