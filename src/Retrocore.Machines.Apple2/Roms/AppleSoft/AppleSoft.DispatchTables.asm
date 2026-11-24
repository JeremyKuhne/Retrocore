; retrocore: style=strict
;; APPLESOFT: HANDLER TABLES, RESERVED WORDS AND MESSAGES
;;
;; These tables begin at $D000. <Tokenize> searches <ReservedWords> in order; <Statements::List> expands its token bytes
;; back through the same list. <DispatchStatement> dispatches statement tokens with <StatementTable>, while expression
;; evaluation uses <FunctionTable> and <OperatorTable>. <ReportError> indexes <ErrorMessages> by byte offset, not by an
;; ordinal error number.

;; Handler addresses minus one for the 64 statements, indexed by token $80-$BF.
;;
;; <DispatchStatement> pushes the high and low bytes and returns through <GetNextCharacter>; the RTS increments the
;; stacked address before entering the handler. `HOME` enters the Monitor and & enters the RAM vector <AmpersandJump>.
;; Also: STMDSP (M6502)
StatementTable:
    .word Statements::End - 1               ; $80 END
    .word Statements::For - 1               ; $81 FOR
    .word Statements::Next - 1              ; $82 NEXT
    .word Statements::Data - 1              ; $83 DATA
    .word Statements::Input - 1             ; $84 INPUT
    .word DEL - 1                           ; $85 DEL
    .word Statements::Dim - 1               ; $86 DIM
    .word Statements::Read - 1              ; $87 READ
    .word GR - 1                            ; $88 GR
    .word TEXT - 1                          ; $89 TEXT
    .word PRNUM - 1                         ; $8A PR#
    .word INNUM - 1                         ; $8B IN#
    .word CALL - 1                          ; $8C CALL
    .word PLOT - 1                          ; $8D PLOT
    .word HLIN - 1                          ; $8E HLIN
    .word VLIN - 1                          ; $8F VLIN
    .word HGR2 - 1                          ; $90 HGR2
    .word HGR - 1                           ; $91 HGR
    .word HCOLOR - 1                        ; $92 HCOLOR=
    .word HPLOT - 1                         ; $93 HPLOT
    .word DRAW - 1                          ; $94 DRAW
    .word XDRAW - 1                         ; $95 XDRAW
    .word HTAB - 1                          ; $96 HTAB
    .word HOME - 1                          ; $97 HOME
    .word ROT - 1                           ; $98 ROT=
    .word SCALE - 1                         ; $99 SCALE=
    .word SHLOAD - 1                        ; $9A SHLOAD
    .word TRACE - 1                         ; $9B TRACE
    .word NOTRAC - 1                        ; $9C NOTRACE
    .word NRMSTM - 1                        ; $9D NORMAL
    .word INVERS - 1                        ; $9E INVERSE
    .word FLASH - 1                         ; $9F FLASH
    .word COLSTM - 1                        ; $A0 COLOR=
    .word Statements::Pop - 1               ; $A1 POP
    .word VTAB - 1                          ; $A2 VTAB
    .word HIMEM - 1                         ; $A3 HIMEM:
    .word LOMEM - 1                         ; $A4 LOMEM:
    .word ONERR - 1                         ; $A5 ONERR
    .word RESUME - 1                        ; $A6 RESUME
    .word RECALL - 1                        ; $A7 RECALL
    .word STORE - 1                         ; $A8 STORE
    .word SPEED - 1                         ; $A9 SPEED=
    .word Statements::Let - 1               ; $AA LET
    .word Statements::GoTo - 1              ; $AB GOTO
    .word Statements::PrepareRun - 1        ; $AC RUN
    .word Statements::If - 1                ; $AD IF
    .word Statements::Restore - 1           ; $AE RESTORE
    .word AmpersandJump - 1                 ; $AF &
    .word Statements::GoSub - 1             ; $B0 GOSUB
    .word Statements::Pop - 1               ; $B1 RETURN
    .word Statements::Rem - 1               ; $B2 REM
    .word Statements::Stop - 1              ; $B3 STOP
    .word Statements::On - 1                ; $B4 ON
    .word WAIT - 1                          ; $B5 WAIT
    .word Statements::Load - 1              ; $B6 LOAD
    .word Statements::Save - 1              ; $B7 SAVE
    .word Statements::Def - 1               ; $B8 DEF
    .word Statements::Poke - 1              ; $B9 POKE
    .word Statements::Print - 1             ; $BA PRINT
    .word Statements::Cont - 1              ; $BB CONT
    .word Statements::List - 1              ; $BC LIST
    .word Statements::Clear - 1             ; $BD CLEAR
    .word Statements::Get - 1               ; $BE GET
    .word Statements::New - 1               ; $BF NEW

;; Addresses of the functions in token order, from `SGN` through `MID$`.
;;
;; Unlike <StatementTable>, these words are the actual entry addresses. The SCRN( entry goes to <ReportError>; its
;; special handling is elsewhere in expression evaluation. `USR` enters the writable <UserVector> vector.
;; Also: FUNDSP (M6502)
FunctionTable:
    .word Functions::Sgn                    ; SGN
    .word Functions::Int                    ; INT
    .word Functions::Abs                    ; ABS
    .word UserVector                        ; USR
    .word Functions::Fre                    ; FRE
    .word ReportError                       ; SCRN(
    .word Functions::Pdl                    ; PDL
    .word Functions::Pos                    ; POS
    .word Functions::Sqr                    ; SQR
    .word Functions::Rnd                    ; RND
    .word Functions::Log                    ; LOG
    .word Functions::Exp                    ; EXP
    .word Functions::Cos                    ; COS
    .word Functions::Sin                    ; SIN
    .word Functions::Tan                    ; TAN
    .word Functions::Atn                    ; ATN
    .word Functions::Peek                   ; PEEK
    .word Functions::Len                    ; LEN
    .word Functions::Str                    ; STR$
    .word Functions::Val                    ; VAL
    .word Functions::Asc                    ; ASC
    .word Functions::Chr                    ; CHR$
    .word Functions::Left                   ; LEFT$
    .word Functions::Right                  ; RIGHT$
    .word Functions::Mid                    ; MID$

.include "../Microsoft6502Basic/MsBasic.OperatorTable.asm"
    ; AppleSoft puts power below negation, gives NOT unary precedence, and dispatches AND to <Operators::And>.
    OperatorEntries 1, 1, Operators::And

;; Reserved-word spellings in token order, starting at $80 and ending with a zero byte.
;;
;; Each spelling has bit 7 set on its last character; the preceding characters have bit 7 clear. The token
;; is $80 plus the spelling's index, not its offset in this variable-length table. Ordering matters when one
;; spelling is a prefix of another. `REM`, `DATA` and quoted text have special treatment during tokenization.
;;
;; Microsoft's source counts the token values here, and the error offsets below, with an assembly-time variable,
;; Q; this table writes each token's value and computes each offset.
;; Also: RESLST (M6502)
ReservedWords:
    .byte "EN", 'D' | $80           ; $80 END

;; The token of `END`, the first statement token.
;; Also: ENDTK (M6502)
TOKEN_END = $80

    .byte "FO", 'R' | $80           ; $81 FOR

;; The token of `FOR`.
;; Also: FORTK (M6502)
TOKEN_FOR = $81

    .byte "NEX", 'T' | $80          ; $82 NEXT
    .byte "DAT", 'A' | $80          ; $83 DATA

;; The token of `DATA`.
;; Also: DATATK (M6502)
TOKEN_DATA = $83

    .byte "INPU", 'T' | $80         ; $84 INPUT
    .byte "DE", 'L' | $80           ; $85 DEL
    .byte "DI", 'M' | $80           ; $86 DIM
    .byte "REA", 'D' | $80          ; $87 READ
    .byte "G", 'R' | $80            ; $88 GR
    .byte "TEX", 'T' | $80          ; $89 TEXT
    .byte "PR", '#' | $80           ; $8A PR#
    .byte "IN", '#' | $80           ; $8B IN#
    .byte "CAL", 'L' | $80          ; $8C CALL
    .byte "PLO", 'T' | $80          ; $8D PLOT
    .byte "HLI", 'N' | $80          ; $8E HLIN
    .byte "VLI", 'N' | $80          ; $8F VLIN
    .byte "HGR", '2' | $80          ; $90 HGR2
    .byte "HG", 'R' | $80           ; $91 HGR
    .byte "HCOLOR", '=' | $80       ; $92 HCOLOR=
    .byte "HPLO", 'T' | $80         ; $93 HPLOT
    .byte "DRA", 'W' | $80          ; $94 DRAW
    .byte "XDRA", 'W' | $80         ; $95 XDRAW
    .byte "HTA", 'B' | $80          ; $96 HTAB
    .byte "HOM", 'E' | $80          ; $97 HOME
    .byte "ROT", '=' | $80          ; $98 ROT=
    .byte "SCALE", '=' | $80        ; $99 SCALE=
    .byte "SHLOA", 'D' | $80        ; $9A SHLOAD
    .byte "TRAC", 'E' | $80         ; $9B TRACE
    .byte "NOTRAC", 'E' | $80       ; $9C NOTRACE
    .byte "NORMA", 'L' | $80        ; $9D NORMAL
    .byte "INVERS", 'E' | $80       ; $9E INVERSE
    .byte "FLAS", 'H' | $80         ; $9F FLASH
    .byte "COLOR", '=' | $80        ; $A0 COLOR=
    .byte "PO", 'P' | $80           ; $A1 POP

;; The token of `POP`.
;; Also: POPTK (UNKN)
TOKEN_POP = $A1

    .byte "VTA", 'B' | $80          ; $A2 VTAB
    .byte "HIMEM", ':' | $80        ; $A3 HIMEM:
    .byte "LOMEM", ':' | $80        ; $A4 LOMEM:
    .byte "ONER", 'R' | $80         ; $A5 ONERR
    .byte "RESUM", 'E' | $80        ; $A6 RESUME
    .byte "RECAL", 'L' | $80        ; $A7 RECALL
    .byte "STOR", 'E' | $80         ; $A8 STORE
    .byte "SPEED", '=' | $80        ; $A9 SPEED=
    .byte "LE", 'T' | $80           ; $AA LET
    .byte "GOT", 'O' | $80          ; $AB GOTO

;; The token of `GOTO`.
;; Also: GOTOTK (M6502)
TOKEN_GOTO = $AB

    .byte "RU", 'N' | $80           ; $AC RUN
    .byte "I", 'F' | $80            ; $AD IF
    .byte "RESTOR", 'E' | $80       ; $AE RESTORE
    .byte '&' | $80                 ; $AF &
    .byte "GOSU", 'B' | $80         ; $B0 GOSUB

;; The token of `GOSUB`.
;; Also: GOSUTK (M6502)
TOKEN_GOSUB = $B0

    .byte "RETUR", 'N' | $80        ; $B1 RETURN
    .byte "RE", 'M' | $80           ; $B2 REM

;; The token of `REM`.
;; Also: REMTK (M6502)
TOKEN_REM = $B2

    .byte "STO", 'P' | $80          ; $B3 STOP
    .byte "O", 'N' | $80            ; $B4 ON
    .byte "WAI", 'T' | $80          ; $B5 WAIT
    .byte "LOA", 'D' | $80          ; $B6 LOAD
    .byte "SAV", 'E' | $80          ; $B7 SAVE
    .byte "DE", 'F' | $80           ; $B8 DEF
    .byte "POK", 'E' | $80          ; $B9 POKE
    .byte "PRIN", 'T' | $80         ; $BA PRINT

;; The token of `PRINT` (the tokenizer stores it for ?).
;; Also: PRINTK (M6502)
TOKEN_PRINT = $BA

    .byte "CON", 'T' | $80          ; $BB CONT
    .byte "LIS", 'T' | $80          ; $BC LIST
    .byte "CLEA", 'R' | $80         ; $BD CLEAR
    .byte "GE", 'T' | $80           ; $BE GET
    .byte "NE", 'W' | $80           ; $BF NEW

;; The token of `NEW`, the last statement token.
;; Also: SCRATK (M6502)
TOKEN_NEW = $BF

    .byte "TAB", '(' | $80          ; $C0 TAB(

;; The token of `TAB(`.
;; Also: TABTK (M6502)
TOKEN_TAB = $C0

    .byte "T", 'O' | $80            ; $C1 TO

;; The token of `TO`.
;; Also: TOTK (M6502)
TOKEN_TO = $C1

    .byte "F", 'N' | $80            ; $C2 FN

;; The token of `FN`.
;; Also: FNTK (M6502)
TOKEN_FN = $C2

    .byte "SPC", '(' | $80          ; $C3 SPC(

;; The token of `SPC(`.
;; Also: SPCTK (M6502)
TOKEN_SPC = $C3

    .byte "THE", 'N' | $80          ; $C4 THEN

;; The token of `THEN`.
;; Also: THENTK (M6502)
TOKEN_THEN = $C4

    .byte "A", 'T' | $80            ; $C5 AT

;; The token of `AT`; the tokenizer refuses it before N or O.
;; Also: ATTK (UNKN)
TOKEN_AT = $C5

    .byte "NO", 'T' | $80           ; $C6 NOT

;; The token of `NOT`.
;; Also: NOTTK (M6502)
TOKEN_NOT = $C6

    .byte "STE", 'P' | $80          ; $C7 STEP

;; The token of `STEP`.
;; Also: STEPTK (M6502)
TOKEN_STEP = $C7

    .byte '+' | $80                 ; $C8 +

;; The token of `+`.
;; Also: PLUSTK (M6502)
TOKEN_PLUS = $C8

    .byte '-' | $80                 ; $C9 -

;; The token of `-`.
;; Also: MINUTK (M6502)
TOKEN_MINUS = $C9

    .byte '*' | $80                 ; $CA *
    .byte '/' | $80                 ; $CB /
    .byte '^' | $80                 ; $CC ^
    .byte "AN", 'D' | $80           ; $CD AND
    .byte "O", 'R' | $80            ; $CE OR
    .byte '>' | $80                 ; $CF >

;; The token of `>`, the first relational token.
;; Also: GREATK (M6502)
TOKEN_GREATER = $CF

    .byte '=' | $80                 ; $D0 =

;; The token of `=`.
;; Also: EQULTK (M6502)
TOKEN_EQUAL = $D0

    .byte '<' | $80                 ; $D1 <

;; The token of `<`.
;; Also: LESSTK (M6502)
TOKEN_LESS = $D1

    .byte "SG", 'N' | $80           ; $D2 SGN

;; The token of `SGN`, the first function; the evaluator and <FunctionTable>'s index start here.
;; Also: ONEFUN (M6502)
TOKEN_FIRST_FUNCTION = $D2

    .byte "IN", 'T' | $80           ; $D3 INT
    .byte "AB", 'S' | $80           ; $D4 ABS
    .byte "US", 'R' | $80           ; $D5 USR
    .byte "FR", 'E' | $80           ; $D6 FRE
    .byte "SCRN", '(' | $80         ; $D7 SCRN(

;; The token of `SCRN(`.
;; Also: SCRNTK (UNKN)
TOKEN_SCRN = $D7

    .byte "PD", 'L' | $80           ; $D8 PDL
    .byte "PO", 'S' | $80           ; $D9 POS
    .byte "SQ", 'R' | $80           ; $DA SQR
    .byte "RN", 'D' | $80           ; $DB RND
    .byte "LO", 'G' | $80           ; $DC LOG
    .byte "EX", 'P' | $80           ; $DD EXP
    .byte "CO", 'S' | $80           ; $DE COS
    .byte "SI", 'N' | $80           ; $DF SIN
    .byte "TA", 'N' | $80           ; $E0 TAN
    .byte "AT", 'N' | $80           ; $E1 ATN
    .byte "PEE", 'K' | $80          ; $E2 PEEK
    .byte "LE", 'N' | $80           ; $E3 LEN
    .byte "STR", '$' | $80          ; $E4 STR$
    .byte "VA", 'L' | $80           ; $E5 VAL
    .byte "AS", 'C' | $80           ; $E6 ASC
    .byte "CHR", '$' | $80          ; $E7 CHR$

;; The token of `CHR$`, the last function taking one parenthesized argument; later ones are the string slicers.
;; Also: LASNUM (M6502)
TOKEN_LAST_SIMPLE_FUNCTION = $E7

    .byte "LEFT", '$' | $80         ; $E8 LEFT$
    .byte "RIGHT", '$' | $80        ; $E9 RIGHT$
    .byte "MID", '$' | $80          ; $EA MID$
    .byte $00

;; Error messages addressed by the ERROR_* constants' byte offsets.
;;
;; Each message ends in a character with bit 7 set. <ReportError> prints until that byte, then appends <ErrorSuffix>;
;; all offsets fit in one byte.
;; Also: ERRTAB (M6502)
ErrorMessages:
;; Offset of `NEXT` WITHOUT `FOR` in <ErrorMessages>.
;; Also: ERRNF (M6502)
ERROR_NEXT_WITHOUT_FOR = * - ErrorMessages
    .byte "NEXT WITHOUT FO", 'R' | $80
    .assert ERROR_NEXT_WITHOUT_FOR = $00, "ERROR_NEXT_WITHOUT_FOR must stay at its offset."

;; Offset of `SYNTAX` in <ErrorMessages>.
;; Also: ERRSN (M6502)
ERROR_SYNTAX = * - ErrorMessages
    .byte "SYNTA", 'X' | $80
    .assert ERROR_SYNTAX = $10, "ERROR_SYNTAX must stay at its offset."

;; Offset of `RETURN` WITHOUT `GOSUB` in <ErrorMessages>.
;; Also: ERRRG (M6502)
ERROR_RETURN_WITHOUT_GOSUB = * - ErrorMessages
    .byte "RETURN WITHOUT GOSU", 'B' | $80
    .assert ERROR_RETURN_WITHOUT_GOSUB = $16, "ERROR_RETURN_WITHOUT_GOSUB must stay at its offset."

;; Offset of OUT OF `DATA` in <ErrorMessages>.
;; Also: ERROD (M6502)
ERROR_OUT_OF_DATA = * - ErrorMessages
    .byte "OUT OF DAT", 'A' | $80
    .assert ERROR_OUT_OF_DATA = $2A, "ERROR_OUT_OF_DATA must stay at its offset."

;; Offset of ILLEGAL QUANTITY in <ErrorMessages>.
;; Also: ERRFC (M6502)
ERROR_ILLEGAL_QUANTITY = * - ErrorMessages
    .byte "ILLEGAL QUANTIT", 'Y' | $80
    .assert ERROR_ILLEGAL_QUANTITY = $35, "ERROR_ILLEGAL_QUANTITY must stay at its offset."

;; Offset of OVERFLOW in <ErrorMessages>.
;; Also: ERROV (M6502, ASTIL)
ERROR_OVERFLOW = * - ErrorMessages
    .byte "OVERFLO", 'W' | $80
    .assert ERROR_OVERFLOW = $45, "ERROR_OVERFLOW must stay at its offset."

;; Offset of OUT OF MEMORY in <ErrorMessages>.
;; Also: ERROM (M6502)
ERROR_OUT_OF_MEMORY = * - ErrorMessages
    .byte "OUT OF MEMOR", 'Y' | $80
    .assert ERROR_OUT_OF_MEMORY = $4D, "ERROR_OUT_OF_MEMORY must stay at its offset."

;; Offset of UNDEF'D STATEMENT in <ErrorMessages>.
;; Also: ERRUS (M6502)
ERROR_UNDEFINED_STATEMENT = * - ErrorMessages
    .byte "UNDEF'D STATEMEN", 'T' | $80
    .assert ERROR_UNDEFINED_STATEMENT = $5A, "ERROR_UNDEFINED_STATEMENT must stay at its offset."

;; Offset of BAD SUBSCRIPT in <ErrorMessages>.
;; Also: ERRBS (M6502)
ERROR_BAD_SUBSCRIPT = * - ErrorMessages
    .byte "BAD SUBSCRIP", 'T' | $80
    .assert ERROR_BAD_SUBSCRIPT = $6B, "ERROR_BAD_SUBSCRIPT must stay at its offset."

;; Offset of REDIM'D ARRAY in <ErrorMessages>.
;; Also: ERRDD (M6502)
ERROR_REDIMENSIONED_ARRAY = * - ErrorMessages
    .byte "REDIM'D ARRA", 'Y' | $80
    .assert ERROR_REDIMENSIONED_ARRAY = $78, "ERROR_REDIMENSIONED_ARRAY must stay at its offset."

;; Offset of DIVISION BY `ZERO` in <ErrorMessages>.
;; Also: ERRDV0 (M6502)
ERROR_DIVISION_BY_ZERO = * - ErrorMessages
    .byte "DIVISION BY ZER", 'O' | $80
    .assert ERROR_DIVISION_BY_ZERO = $85, "ERROR_DIVISION_BY_ZERO must stay at its offset."

;; Offset of ILLEGAL DIRECT in <ErrorMessages>.
;; Also: ERRID (M6502)
ERROR_ILLEGAL_DIRECT = * - ErrorMessages
    .byte "ILLEGAL DIREC", 'T' | $80
    .assert ERROR_ILLEGAL_DIRECT = $95, "ERROR_ILLEGAL_DIRECT must stay at its offset."

;; Offset of TYPE MISMATCH in <ErrorMessages>.
;; Also: ERRTM (M6502)
ERROR_TYPE_MISMATCH = * - ErrorMessages
    .byte "TYPE MISMATC", 'H' | $80
    .assert ERROR_TYPE_MISMATCH = $A3, "ERROR_TYPE_MISMATCH must stay at its offset."

;; Offset of STRING TOO LONG in <ErrorMessages>.
;; Also: ERRLS (M6502)
ERROR_STRING_TOO_LONG = * - ErrorMessages
    .byte "STRING TOO LON", 'G' | $80
    .assert ERROR_STRING_TOO_LONG = $B0, "ERROR_STRING_TOO_LONG must stay at its offset."

;; Offset of FORMULA TOO COMPLEX in <ErrorMessages>.
;; Also: ERRST (M6502)
ERROR_FORMULA_TOO_COMPLEX = * - ErrorMessages
    .byte "FORMULA TOO COMPLE", 'X' | $80
    .assert ERROR_FORMULA_TOO_COMPLEX = $BF, "ERROR_FORMULA_TOO_COMPLEX must stay at its offset."

;; Offset of CAN'T CONTINUE in <ErrorMessages>.
;; Also: ERRCN (M6502)
ERROR_CANT_CONTINUE = * - ErrorMessages
    .byte "CAN'T CONTINU", 'E' | $80
    .assert ERROR_CANT_CONTINUE = $D2, "ERROR_CANT_CONTINUE must stay at its offset."

;; Offset of UNDEF'D FUNCTION in <ErrorMessages>.
;; Also: ERRUF (M6502)
ERROR_UNDEFINED_FUNCTION = * - ErrorMessages
    .byte "UNDEF'D FUNCTIO", 'N' | $80
    .assert ERROR_UNDEFINED_FUNCTION = $E0, "ERROR_UNDEFINED_FUNCTION must stay at its offset."

;; Error suffix: a space, `ERROR`, a bell and a zero terminator.
;; Also: ERR (M6502)
ErrorSuffix:
    .byte " ERROR", $07, $00

;; Line-number introduction: a space, IN, a space and a zero terminator.
;; Also: INTXT (M6502)
LineNumberPrefix:
    .byte " IN ", $00

;; Break message: carriage return, `BREAK`, a bell and a zero terminator.
;; Also: BRKTXT (M6502)
BreakMessage:
    .byte $0D, "BREAK", $07, $00

; Microsoft's REDDY, the READY message's offset, and GOTK, the GO token, are not defined: AppleSoft has neither
; the message nor the keyword, and nothing uses them.
