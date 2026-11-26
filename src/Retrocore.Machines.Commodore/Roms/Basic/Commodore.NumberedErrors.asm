; retrocore: style=strict
;; COMMODORE BASIC: NUMBERED ERROR MESSAGES
;;
;; The VIC-20's BASIC numbers its errors from 1 and finds each message through a table of addresses, so that the
;; kernal's errors, which it returns as numbers 1 to 9 with carry set, are reported by the same routine as BASIC's
;; own. <CommodoreDispatchTables> emits these messages in place of the PET's offset-addressed ones when
;; <NUMBERED_ERRORS> is 1. Including this file emits no bytes.

;; Emits the numbered error messages, their table of addresses and the prompts that follow them: `OK` for `VERIFY`,
;; the error suffix, the line-number prefix, `READY.` and `BREAK`.
.macro CommodoreNumberedErrors

;; "TOO MANY FILES": the kernal's error 1, a tenth file opened.
;; Also: ERR01 (BV20)
TooManyFilesMessage:
    .byte "TOO MANY FILE", 'S' | $80

;; "FILE OPEN": the kernal's error 2, a logical file number already open.
;; Also: ERR02 (BV20)
FileOpenMessage:
    .byte "FILE OPE", 'N' | $80

;; "FILE NOT OPEN": the kernal's error 3.
;; Also: ERR03 (BV20)
FileNotOpenMessage:
    .byte "FILE NOT OPE", 'N' | $80

;; "FILE NOT FOUND": the kernal's error 4.
;; Also: ERR04 (BV20)
FileNotFoundMessage:
    .byte "FILE NOT FOUN", 'D' | $80

;; "DEVICE NOT PRESENT": the kernal's error 5.
;; Also: ERR05 (BV20)
DeviceNotPresentMessage:
    .byte "DEVICE NOT PRESEN", 'T' | $80

;; "NOT INPUT FILE": the kernal's error 6.
;; Also: ERR06 (BV20)
NotInputFileMessage:
    .byte "NOT INPUT FIL", 'E' | $80

;; "NOT OUTPUT FILE": the kernal's error 7.
;; Also: ERR07 (BV20)
NotOutputFileMessage:
    .byte "NOT OUTPUT FIL", 'E' | $80

;; "MISSING FILE NAME": the kernal's error 8.
;; Also: ERR08 (BV20)
MissingFileNameMessage:
    .byte "MISSING FILE NAM", 'E' | $80

;; "ILLEGAL DEVICE NUMBER": the kernal's error 9.
;; Also: ERR09 (BV20)
IllegalDeviceNumberMessage:
    .byte "ILLEGAL DEVICE NUMBE", 'R' | $80

;; "NEXT WITHOUT FOR".
;; Also: ERR10 (BV20)
NextWithoutForMessage:
    .byte "NEXT WITHOUT FO", 'R' | $80

;; "SYNTAX".
;; Also: ERR11 (BV20)
SyntaxMessage:
    .byte "SYNTA", 'X' | $80

;; "RETURN WITHOUT GOSUB".
;; Also: ERR12 (BV20)
ReturnWithoutGosubMessage:
    .byte "RETURN WITHOUT GOSU", 'B' | $80

;; "OUT OF DATA".
;; Also: ERR13 (BV20)
OutOfDataMessage:
    .byte "OUT OF DAT", 'A' | $80

;; "ILLEGAL QUANTITY".
;; Also: ERR14 (BV20)
IllegalQuantityMessage:
    .byte "ILLEGAL QUANTIT", 'Y' | $80

;; "OVERFLOW".
;; Also: ERR15 (BV20)
OverflowMessage:
    .byte "OVERFLO", 'W' | $80

;; "OUT OF MEMORY".
;; Also: ERR16 (BV20)
OutOfMemoryMessage:
    .byte "OUT OF MEMOR", 'Y' | $80

;; "UNDEF'D STATEMENT".
;; Also: ERR17 (BV20)
UndefinedStatementMessage:
    .byte "UNDEF'D STATEMEN", 'T' | $80

;; "BAD SUBSCRIPT".
;; Also: ERR18 (BV20)
BadSubscriptMessage:
    .byte "BAD SUBSCRIP", 'T' | $80

;; "REDIM'D ARRAY".
;; Also: ERR19 (BV20)
RedimensionedArrayMessage:
    .byte "REDIM'D ARRA", 'Y' | $80

;; "DIVISION BY ZERO".
;; Also: ERR20 (BV20)
DivisionByZeroMessage:
    .byte "DIVISION BY ZER", 'O' | $80

;; "ILLEGAL DIRECT".
;; Also: ERR21 (BV20)
IllegalDirectMessage:
    .byte "ILLEGAL DIREC", 'T' | $80

;; "TYPE MISMATCH".
;; Also: ERR22 (BV20)
TypeMismatchMessage:
    .byte "TYPE MISMATC", 'H' | $80

;; "STRING TOO LONG".
;; Also: ERR23 (BV20)
StringTooLongMessage:
    .byte "STRING TOO LON", 'G' | $80

;; "FILE DATA".
;; Also: ERR24 (BV20)
FileDataMessage:
    .byte "FILE DAT", 'A' | $80

;; "FORMULA TOO COMPLEX".
;; Also: ERR25 (BV20)
FormulaTooComplexMessage:
    .byte "FORMULA TOO COMPLE", 'X' | $80

;; "CAN'T CONTINUE".
;; Also: ERR26 (BV20)
CantContinueMessage:
    .byte "CAN'T CONTINU", 'E' | $80

;; "UNDEF'D FUNCTION".
;; Also: ERR27 (BV20)
UndefinedFunctionMessage:
    .byte "UNDEF'D FUNCTIO", 'N' | $80

;; "VERIFY": a `VERIFY` that found the file different.
;; Also: ERR28 (BV20)
VerifyMessage:
    .byte "VERIF", 'Y' | $80

;; "LOAD": a `LOAD` that failed with a status other than end of file.
;; Also: ERR29 (BV20)
LoadMessage:
    .byte "LOA", 'D' | $80

;; The addresses of the messages, by error number from 1: <ReportError> reads entry X at this table's address plus 2X
;; minus 2.
;; Also: ERRTAB (BV20)
ErrorMessageAddresses:
    .word TooManyFilesMessage, FileOpenMessage, FileNotOpenMessage, FileNotFoundMessage, DeviceNotPresentMessage
    .word NotInputFileMessage, NotOutputFileMessage, MissingFileNameMessage, IllegalDeviceNumberMessage
    .word NextWithoutForMessage, SyntaxMessage, ReturnWithoutGosubMessage, OutOfDataMessage, IllegalQuantityMessage
    .word OverflowMessage, OutOfMemoryMessage, UndefinedStatementMessage, BadSubscriptMessage
    .word RedimensionedArrayMessage, DivisionByZeroMessage, IllegalDirectMessage, TypeMismatchMessage
    .word StringTooLongMessage, FileDataMessage, FormulaTooComplexMessage, CantContinueMessage
    .word UndefinedFunctionMessage, VerifyMessage, LoadMessage, BreakErrorMessage

    ;; The number of "NEXT WITHOUT FOR", the order of <ErrorMessageAddresses>.
    ;; Also: ERRNF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_NEXT_WITHOUT_FOR = 10

    ;; The number of "SYNTAX".
    ;; Also: ERRSN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_SYNTAX = 11

    ;; The number of "RETURN WITHOUT GOSUB".
    ;; Also: ERRRG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_RETURN_WITHOUT_GOSUB = 12

    ;; The number of "OUT OF DATA".
    ;; Also: ERROD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_OUT_OF_DATA = 13

    ;; The number of "ILLEGAL QUANTITY".
    ;; Also: ERRFC (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
    ERROR_ILLEGAL_QUANTITY = 14

    ;; The number of "OVERFLOW".
    ;; Also: ERROV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_OVERFLOW = 15

    ;; The number of "OUT OF MEMORY".
    ;; Also: ERROM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_OUT_OF_MEMORY = 16

    ;; The number of "UNDEF'D STATEMENT".
    ;; Also: ERRUS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_UNDEFINED_STATEMENT = 17

    ;; The number of "BAD SUBSCRIPT".
    ;; Also: ERRBS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_BAD_SUBSCRIPT = 18

    ;; The number of "REDIM'D ARRAY".
    ;; Also: ERRDD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_REDIMENSIONED_ARRAY = 19

    ;; The number of "DIVISION BY ZERO".
    ;; Also: ERRDV0 (M6502), ERRDVO (BV20)
    ERROR_DIVISION_BY_ZERO = 20

    ;; The number of "ILLEGAL DIRECT".
    ;; Also: ERRID (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_ILLEGAL_DIRECT = 21

    ;; The number of "TYPE MISMATCH".
    ;; Also: ERRTM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_TYPE_MISMATCH = 22

    ;; The number of "STRING TOO LONG".
    ;; Also: ERRLS (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
    ERROR_STRING_TOO_LONG = 23

    ;; The number of "FILE DATA".
    ;; Also: ERRBD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_FILE_DATA = 24

    ;; The number of "FORMULA TOO COMPLEX".
    ;; Also: ERRST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_FORMULA_TOO_COMPLEX = 25

    ;; The number of "CAN'T CONTINUE".
    ;; Also: ERRCN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_CANT_CONTINUE = 26

    ;; The number of "UNDEF'D FUNCTION".
    ;; Also: ERRUF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    ERROR_UNDEFINED_FUNCTION = 27

    ;; The number of "VERIFY".
    ;; Also: ERVFY (BV20)
    ERROR_VERIFY = 28

    ;; The number of "LOAD".
    ;; Also: ERLOAD (BV20)
    ERROR_LOAD = 29

    ;; The number of "BREAK", which BASIC reports for a kernal call stopped by the STOP key, error 0.
    ;; Also: ERBRK (BV20)
    ERROR_BREAK = 30

;; The message after a `VERIFY` typed directly that found the file the same.
;; Also: OKMSG (BV20)
OkMessage:
    .byte CARRIAGE_RETURN, "OK", CARRIAGE_RETURN, $00

;; Suffix appended to an error message; it starts with a carriage return, for the VIC-20's narrow screen.
;; Also: ERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ErrorSuffix:
    .byte CARRIAGE_RETURN
    .asciiz " ERROR"

;; Introduction before the line number in an error or break message.
;; Also: INTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LineNumberPrefix:
    .asciiz " IN "

;; Message shown when the interpreter is ready for another command.
;; Also: REDDY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ReadyMessage:
    .byte CARRIAGE_RETURN, LINE_FEED, "READY.", CARRIAGE_RETURN, LINE_FEED, $00

;; Message shown when execution is stopped.
;; Also: BRKTXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
BreakMessage:
    .byte CARRIAGE_RETURN, LINE_FEED

;; "BREAK", error 30's message: the end of <BreakMessage>. Unlike the other messages it ends with a zero, so
;; <ReportError> prints the zero and the shifted space after it before it stops at the shifted space's bit 7.
;; Also: ERR30 (BV20)
BreakErrorMessage:
    .byte "BREAK", $00, ' ' | $80
.endmacro
