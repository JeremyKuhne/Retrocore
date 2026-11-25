; retrocore: style=strict
;; B3Resvb: the keywords and their tokens, the operators, the error messages
;;
;; BASIC's keywords and their tokens, the operators, the error messages, and the SOS errors BASIC turns into its own.
;;
;; A program is kept as tokens: each keyword in <ReservedWords> is one byte, its token, from $80 for `END`. The
;; keywords in <ExtendedReservedWords> (operators, functions and words that only follow others) are two bytes:
;; <TOKEN_ESCAPE>, then the keyword's token, from $80 for `TAB(`. Each keyword's token is its place in its table plus
;; $80, which <Keyword> checks. The entries of the form "A " hold tokens with no keyword.
;;
;; The names say what each value is; Apple's names from its Business BASIC 1.3 listing are in each one's `Also:`.

;; Ends the statement with a `TYPE MISMATCH` error.
;; Also: TMERR (BB13)
.proc TypeMismatchError
    ldx #ERROR_TYPE_MISMATCH
    jmp ReportError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The tables' macros
; ---------------------------------------------------------------------------------------------------------------------

;; How many keywords <Keyword> has placed in the table it is building, which gives the next keyword's token.
.set KeywordCount, 0

;; One entry of <ReservedWords> or <ExtendedReservedWords>: a keyword, with bit 7 set on its last character.
;; Parameters:
;;   text = the keyword, or "A " for a token with no keyword
;;   token = the keyword's TOKEN_ constant, where it has one, which must be its place in the table plus $80
.macro Keyword text, token
    .ifnblank token
        .assert token = $80 + KeywordCount, "A keyword's token is its place in its table plus $80."
    .endif
    .set KeywordCount, KeywordCount + 1
    DCI text
.endmacro

;; How many messages <ErrorMessage> has placed, which gives the next message's error number.
.set ErrorMessageCount, 0

;; One message of <ErrorMessages>, with bit 7 set on its last character.
;; Parameters:
;;   error = the message's ERROR_ number, which must be its place in the table from 1
;;   text = the message
.macro ErrorMessage error, text
    .set ErrorMessageCount, ErrorMessageCount + 1
    .assert error = ErrorMessageCount, "ErrorMessages is in the order of the ERROR_ numbers, from 1."
    DCI text
.endmacro

;; One entry of <SosErrors>: a SOS error's code and the BASIC error it gives.
;; Parameters:
;;   sos = the SOS_ERROR_ code
;;   error = BASIC's ERROR_ number
.macro SosErrorEntry sos, error
    .byte sos, error
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The tokens of the statements and the words that give a value
; ---------------------------------------------------------------------------------------------------------------------

;; The token of `END`, the first one-byte token.
;; Also: ENDTK (BB13)
TOKEN_END = $80

;; The token of `FOR`.
;; Also: FORTK (BB13)
TOKEN_FOR = $81

;; The token of `INPUT`.
;; Also: INPTKN (BB13)
TOKEN_INPUT = $83

;; The token of `OUTPUT`.
;; Also: OUTTKN (BB13)
TOKEN_OUTPUT = $84

;; The token of `OPEN`.
;; Also: OPENTK (BB13)
TOKEN_OPEN = $88

;; The token of `TEXT`.
;; Also: TEXTTK (BB13)
TOKEN_TEXT = $8B

;; The token of `INVOKE`.
;; Also: INVOKTK (BB13)
TOKEN_INVOKE = $94

;; The token of `FRE`, the first of the words that give a value with no parentheses, through <ValueWordTable>.
;; Also: FRETK (BB13)
TOKEN_FRE = $98

;; The token of `HPOS`.
;; Also: HPOSTK (BB13)
TOKEN_HPOS = $99

;; The token of `VPOS`.
;; Also: VPOSTK (BB13)
TOKEN_VPOS = $9A

;; The token of `ERRLIN`.
;; Also: ERRLINTK (BB13)
TOKEN_ERRLIN = $9B

;; The token of `ERR`.
;; Also: ERRTK (BB13)
TOKEN_ERR = $9C

;; The token of `KBD`.
;; Also: KBDTK (BB13)
TOKEN_KBD = $9D

;; The token of `EOF`.
;; Also: EOFTK (BB13)
TOKEN_EOF = $9E

;; The token of `EXFN%.`, the integer form of `EXFN.`.
;; Also: EXFNSTK (BB13)
TOKEN_EXFN_INTEGER = $A3

;; The token of `POP`, the first past the words of <ValueWordTable>.
;; Also: POPTKN (BB13)
TOKEN_POP = $AD

;; The token of `SCALE(`.
;; Also: SCALETK (BB13)
TOKEN_SCALE = $B6

;; The token of `GOTO`.
;; Also: GOTOTK (BB13)
TOKEN_GOTO = $BA

;; The token of `IF`.
;; Also: IFTOKN (BB13)
TOKEN_IF = $BB

;; The token of `GOSUB`.
;; Also: GOSUTK (BB13)
TOKEN_GOSUB = $BE

;; The token of `REM`.
;; Also: REMTK (BB13)
TOKEN_REM = $C0

;; The token of `LOAD`, the first of the file commands, whose file names <Tokenize> leaves as typed.
;; Also: LDTKN (BB13)
TOKEN_LOAD = $C4

;; The token of `RENAME`.
;; Also: RENMTK (BB13)
TOKEN_RENAME = $C8

;; The token of `CATALOG`.
;; Also: CATATK (BB13)
TOKEN_CATALOG = $D1

;; The last of the file commands' tokens, $D3, which has no keyword.
;; Also: DSKCOMS (BB13)
TOKEN_LAST_FILE_COMMAND = $D3

;; The token of `DATA`.
;; Also: DATATK (BB13)
TOKEN_DATA = $D4

;; The token of `IMAGE`.
;; Also: IMAGETK (BB13)
TOKEN_IMAGE = $D5

;; The token of `CAT`.
;; Also: CATTK (BB13)
TOKEN_CAT = $D6

;; The token of `PRINT`.
;; Also: PRINTK (BB13)
TOKEN_PRINT = $D9

;; The token of `ELSE`.
;; Also: ELSETK (BB13)
TOKEN_ELSE = $DB

;; The token of `NEW`, the last one-byte token.
;; Also: SCRATK (BB13)
TOKEN_NEW = $E0

; ---------------------------------------------------------------------------------------------------------------------
; Statements and the words that give a value
; ---------------------------------------------------------------------------------------------------------------------

;; The keywords with one-byte tokens, from $80 to $E0, each with the last character's bit 7 set.
;;
;; The statements' routines are in <StatementTable>, in the same order. `FRE` to `EOF` and the words to `EXFN%.` give
;; a value with no parentheses, through <ValueWordTable>; some of them are statements as well. From `LOAD` on are the
;; file commands, whose file names <Tokenize> leaves as typed.
;; See: <ExtendedReservedWords>, <StatementTable>, <Tokenize>
;; Also: RESLST (BB13)
ReservedWords:
    Keyword "END", TOKEN_END                ; $80
    Keyword "FOR", TOKEN_FOR                ; $81
    Keyword "NEXT"                          ; $82
    Keyword "INPUT", TOKEN_INPUT            ; $83
    Keyword "OUTPUT", TOKEN_OUTPUT          ; $84
    Keyword "DIM"                           ; $85
    Keyword "READ"                          ; $86
    Keyword "WRITE"                         ; $87
    Keyword "OPEN", TOKEN_OPEN              ; $88
    Keyword "CLOSE"                         ; $89
    Keyword "A "                            ; $8A, unused
    Keyword "TEXT", TOKEN_TEXT              ; $8B
    Keyword "A "                            ; $8C, unused
    Keyword "BYE"                           ; $8D
    Keyword "A "                            ; $8E, unused
    Keyword "A "                            ; $8F, unused
    Keyword "A "                            ; $90, unused
    Keyword "A "                            ; $91, unused
    Keyword "A "                            ; $92, unused
    Keyword "WINDOW"                        ; $93
    Keyword "INVOKE", TOKEN_INVOKE          ; $94
    Keyword "PERFORM"                       ; $95
    Keyword "A "                            ; $96, unused
    Keyword "A "                            ; $97, unused
    Keyword "FRE", TOKEN_FRE                ; $98
    Keyword "HPOS", TOKEN_HPOS              ; $99
    Keyword "VPOS", TOKEN_VPOS              ; $9A
    Keyword "ERRLIN", TOKEN_ERRLIN          ; $9B
    Keyword "ERR", TOKEN_ERR                ; $9C
    Keyword "KBD", TOKEN_KBD                ; $9D
    Keyword "EOF", TOKEN_EOF                ; $9E
    Keyword "TIME$"                         ; $9F
    Keyword "DATE$"                         ; $A0
    Keyword "PREFIX$"                       ; $A1
    Keyword "EXFN."                         ; $A2
    Keyword "EXFN%.", TOKEN_EXFN_INTEGER    ; $A3
    Keyword "OUTREC"                        ; $A4
    Keyword "INDENT"                        ; $A5
.if VERSION >= 130
    Keyword "PROGPREFIX$"                   ; $A6
.else
    Keyword "A "                            ; $A6, unused
.endif
    Keyword "A "                            ; $A7, unused
    Keyword "A "                            ; $A8, unused
    Keyword "A "                            ; $A9, unused
    Keyword "A "                            ; $AA, unused
    Keyword "A "                            ; $AB, unused
    Keyword "A "                            ; $AC, unused
    Keyword "POP", TOKEN_POP                ; $AD
    Keyword "HOME"                          ; $AE
.if DEBUG
    Keyword "SHIT"                          ; $AF, the debugger's command, in the debugger build
.else
    Keyword "A   "                          ; $AF, unused
.endif
    Keyword "SUB$("                         ; $B0
    Keyword "OFF"                           ; $B1
    Keyword "TRACE"                         ; $B2
    Keyword "NOTRACE"                       ; $B3
    Keyword "NORMAL"                        ; $B4
    Keyword "INVERSE"                       ; $B5
    Keyword "SCALE(", TOKEN_SCALE           ; $B6
    Keyword "RESUME"                        ; $B7
    Keyword "A "                            ; $B8, unused
    Keyword "LET"                           ; $B9
    Keyword "GOTO", TOKEN_GOTO              ; $BA
    Keyword "IF", TOKEN_IF                  ; $BB
    Keyword "RESTORE"                       ; $BC
    Keyword "SWAP"                          ; $BD
    Keyword "GOSUB", TOKEN_GOSUB            ; $BE
    Keyword "RETURN"                        ; $BF
    Keyword "REM", TOKEN_REM                ; $C0
    Keyword "STOP"                          ; $C1
    Keyword "ON"                            ; $C2
    Keyword "A "                            ; $C3, unused
    Keyword "LOAD", TOKEN_LOAD              ; $C4
    Keyword "SAVE"                          ; $C5
    Keyword "DELETE"                        ; $C6
    Keyword "RUN"                           ; $C7
    Keyword "RENAME", TOKEN_RENAME          ; $C8
    Keyword "LOCK"                          ; $C9
    Keyword "UNLOCK"                        ; $CA
    Keyword "CREATE"                        ; $CB
    Keyword "EXEC"                          ; $CC
    Keyword "CHAIN"                         ; $CD
    Keyword "A "                            ; $CE, unused
    Keyword "A "                            ; $CF, unused
    Keyword "A "                            ; $D0, unused
    Keyword "CATALOG", TOKEN_CATALOG        ; $D1
    Keyword "A "                            ; $D2, unused
    Keyword "A ", TOKEN_LAST_FILE_COMMAND   ; $D3, unused
    Keyword "DATA", TOKEN_DATA              ; $D4
    Keyword "IMAGE", TOKEN_IMAGE            ; $D5
    Keyword "CAT", TOKEN_CAT                ; $D6
    Keyword "DEF"                           ; $D7
    Keyword "A "                            ; $D8, unused
    Keyword "PRINT", TOKEN_PRINT            ; $D9
    Keyword "DEL"                           ; $DA
    Keyword "ELSE", TOKEN_ELSE              ; $DB
    Keyword "CONT"                          ; $DC
    Keyword "LIST"                          ; $DD
    Keyword "CLEAR"                         ; $DE
    Keyword "GET"                           ; $DF
    Keyword "NEW", TOKEN_NEW                ; $E0

; ---------------------------------------------------------------------------------------------------------------------
; The tokens of the operators, functions and other words
;
; Each follows TOKEN_ESCAPE in a program.
; ---------------------------------------------------------------------------------------------------------------------

;; The byte before each two-byte token: the token that follows is a keyword of <ExtendedReservedWords>.
TOKEN_ESCAPE = $FF

;; The token of `TAB(`, the first two-byte token after <TOKEN_ESCAPE>.
;; Also: TABTK (BB13)
TOKEN_TAB = $80

;; The token of `TO`.
;; Also: TOTK (BB13)
TOKEN_TO = $81

;; The token of `SPC(`.
;; Also: SPCTK (BB13)
TOKEN_SPC = $82

;; The token of `USING`.
;; Also: USINGTK (BB13)
TOKEN_USING = $83

;; The token of `THEN`.
;; Also: THENTK (BB13)
TOKEN_THEN = $84

;; $85, a token named for `AT`, which has no keyword.
;; Also: ATTKN (BB13)
TOKEN_AT = $85

;; The token of `MOD`.
;; Also: MODTK (BB13)
TOKEN_MOD = $86

;; The token of `STEP`.
;; Also: STEPTK (BB13)
TOKEN_STEP = $87

;; The token of `AND`.
;; Also: ANDTK (BB13)
TOKEN_AND = $88

;; The token of `OR`.
;; Also: ORTK (BB13)
TOKEN_OR = $89

;; The token of `EXTENSION`.
;; Also: EXTKN (BB13)
TOKEN_EXTENSION = $8A

;; The token of `DIV`.
;; Also: DIVTK (BB13)
TOKEN_DIV = $8B

;; The token of `FN`.
;; Also: FNTK (BB13)
TOKEN_FN = $8D

;; The token of `NOT`.
;; Also: NOTTK (BB13)
TOKEN_NOT = $8E

;; The token of `AS`.
;; Also: ASTKN (BB13)
TOKEN_AS = $9C

;; The token of `SGN(`, the first function's; <FunctionTable>'s index starts here.
;; Also: ONEFUN (BB13)
TOKEN_FIRST_FUNCTION = $9D

;; The token of `STR$(`.
;; Also: STRTK (BB13)
TOKEN_STR = $C3

;; The token of `HEX$(`.
;; Also: HEXTK (BB13)
TOKEN_HEX = $C4

;; The token of `CHR$(`.
;; Also: CHRTK (BB13)
TOKEN_CHR = $C5

;; The token of `LEN(`.
;; Also: LENTK (BB13)
TOKEN_LEN = $C6

;; $CA, a token Apple named DEXP, which has no keyword and which nothing uses.
;; Also: DEXPTK (BB13)
TOKEN_DEXP = $CA

;; $CB, a token Apple named DLOG, which has no keyword and which nothing uses.
;; Also: DLOGTK (BB13)
TOKEN_DLOG = $CB

;; The token of `CONV(`.
;; Also: CONVTK (BB13)
TOKEN_CONV = $CC

;; The token of `CONV%(`, the last function with one argument; the functions after it take more.
;; Also: LASNUM (BB13)
TOKEN_LAST_SIMPLE_FUNCTION = $CF

;; The token of `INSTR(`, the last.
;; Also: INSTRTK (BB13)
TOKEN_INSTR = $D3

; ---------------------------------------------------------------------------------------------------------------------
; Operators, functions and other words
; ---------------------------------------------------------------------------------------------------------------------

; The table counts its own tokens from $80 again.
.set KeywordCount, 0

;; The keywords with two-byte tokens, <TOKEN_ESCAPE> and then $80-$D3, each with the last character's bit 7 set.
;;
;; From `SGN(` (<TOKEN_FIRST_FUNCTION>) on are the functions, whose routines are in <FunctionTable> in the same order;
;; those past <TOKEN_LAST_SIMPLE_FUNCTION> take more than one argument. The list ends with a zero.
;; See: <ReservedWords>, <FunctionTable>
;; Also: RESL2 (BB13)
ExtendedReservedWords:
    Keyword "TAB(", TOKEN_TAB               ; $80
    Keyword "TO", TOKEN_TO                  ; $81
    Keyword "SPC(", TOKEN_SPC               ; $82
    Keyword "USING", TOKEN_USING            ; $83
    Keyword "THEN", TOKEN_THEN              ; $84
    Keyword "A ", TOKEN_AT                  ; $85, unused
    Keyword "MOD", TOKEN_MOD                ; $86
    Keyword "STEP", TOKEN_STEP              ; $87
    Keyword "AND", TOKEN_AND                ; $88
    Keyword "OR", TOKEN_OR                  ; $89
    Keyword "EXTENSION", TOKEN_EXTENSION    ; $8A
    Keyword "DIV", TOKEN_DIV                ; $8B
    Keyword "A "                            ; $8C, unused
    Keyword "FN", TOKEN_FN                  ; $8D
    Keyword "NOT", TOKEN_NOT                ; $8E
    Keyword "A "                            ; $8F, unused
    Keyword "A "                            ; $90, unused
    Keyword "A "                            ; $91, unused
    Keyword "A "                            ; $92, unused
    Keyword "A "                            ; $93, unused
    Keyword "A "                            ; $94, unused
    Keyword "A "                            ; $95, unused
    Keyword "A "                            ; $96, unused
    Keyword "A "                            ; $97, unused
    Keyword "A "                            ; $98, unused
    Keyword "A "                            ; $99, unused
    Keyword "A "                            ; $9A, unused
    Keyword "A "                            ; $9B, unused
    Keyword "AS", TOKEN_AS                  ; $9C
    Keyword "SGN(", TOKEN_FIRST_FUNCTION    ; $9D
    Keyword "INT("                          ; $9E
    Keyword "ABS("                          ; $9F
    Keyword "A "                            ; $A0, unused
    Keyword "TYP("                          ; $A1
    Keyword "REC("                          ; $A2
    Keyword "A "                            ; $A3, unused
    Keyword "A "                            ; $A4, unused
    Keyword "A "                            ; $A5, unused
    Keyword "A "                            ; $A6, unused
    Keyword "A "                            ; $A7, unused
    Keyword "A "                            ; $A8, unused
    Keyword "A "                            ; $A9, unused
    Keyword "A "                            ; $AA, unused
    Keyword "A "                            ; $AB, unused
    Keyword "A "                            ; $AC, unused
    Keyword "PDL("                          ; $AD
    Keyword "BUTTON("                       ; $AE
    Keyword "SQR("                          ; $AF
    Keyword "RND("                          ; $B0
    Keyword "LOG("                          ; $B1
    Keyword "EXP("                          ; $B2
    Keyword "COS("                          ; $B3
    Keyword "SIN("                          ; $B4
    Keyword "TAN("                          ; $B5
    Keyword "ATN("                          ; $B6
    Keyword "A "                            ; $B7, unused
    Keyword "A "                            ; $B8, unused
    Keyword "A "                            ; $B9, unused
    Keyword "A "                            ; $BA, unused
    Keyword "A "                            ; $BB, unused
    Keyword "A "                            ; $BC, unused
    Keyword "A "                            ; $BD, unused
    Keyword "A "                            ; $BE, unused
    Keyword "A "                            ; $BF, unused
    Keyword "A "                            ; $C0, unused
    Keyword "A "                            ; $C1, unused
    Keyword "A "                            ; $C2, unused
    Keyword "STR$(", TOKEN_STR              ; $C3
    Keyword "HEX$(", TOKEN_HEX              ; $C4
    Keyword "CHR$(", TOKEN_CHR              ; $C5
    Keyword "LEN(", TOKEN_LEN               ; $C6
    Keyword "VAL("                          ; $C7
    Keyword "ASC("                          ; $C8
    Keyword "TEN("                          ; $C9
    Keyword "A ", TOKEN_DEXP                ; $CA, unused
    Keyword "A ", TOKEN_DLOG                ; $CB, unused
    Keyword "CONV(", TOKEN_CONV             ; $CC
    Keyword "CONV&("                        ; $CD
    Keyword "CONV$("                        ; $CE
    Keyword "CONV%(", TOKEN_LAST_SIMPLE_FUNCTION ; $CF
    Keyword "LEFT$("                        ; $D0
    Keyword "RIGHT$("                       ; $D1
    Keyword "MID$("                         ; $D2
    Keyword "INSTR(", TOKEN_INSTR           ; $D3
    .byte 0                                 ; The end of the list

;; Added to an operator's place in <OperatorSymbols> to give its number.
;; Also: RELNOT (BB13)
OPERATOR_NUMBER_OFFSET = 4

;; The operators, as the expression evaluator looks for them: the relational characters, then ^, `AND`, `OR`, `MOD`,
;; `DIV`, /, *, - and +, and a zero for the end of the expression.
;;
;; `AND`, `OR`, `MOD` and `DIV` are their tokens in <ExtendedReservedWords>; the others are characters. An operator's
;; number is its place here plus <OPERATOR_NUMBER_OFFSET>, except that the relational ones combine into 1-7 (1 for >,
;; 2 for =, 4 for <).
;; See: <PrecedenceTable>, <OperatorRoutineTable>, <EvaluateExpression>
;; Also: OPTAB (BB13)
OperatorSymbols:
    .byte '>', '=', '<'

;; 7, the highest relational operator's number.
;; Also: RELOPS (BB13)
OPERATOR_LAST_RELATIONAL = * - OperatorSymbols + OPERATOR_NUMBER_OFFSET
    .byte '^', TOKEN_AND, TOKEN_OR, TOKEN_MOD
    .byte TOKEN_DIV, '/', '*', '-'
    .byte '+', 0

;; 17, the number of the end of the expression.
;; Also: ENDOP (BB13)
OPERATOR_END = * - OperatorSymbols + OPERATOR_NUMBER_OFFSET

;; 13, the count of entries in <OperatorSymbols>.
;; Also: NUMOPS (BB13)
OPERATOR_COUNT = * - OperatorSymbols
.assert OPERATOR_LAST_RELATIONAL = 7 && OPERATOR_END = 17 && OPERATOR_COUNT = 13, "The operators' numbers."

; ---------------------------------------------------------------------------------------------------------------------
; Error messages
;
; BASIC's errors are numbered from 1, in the order of their messages; <ErrorCode> keeps the number of the last one.
; ---------------------------------------------------------------------------------------------------------------------

;; `NEXT WITHOUT FOR`.
;; Also: ERRNF (BB13)
ERROR_NEXT_WITHOUT_FOR = 1

;; `SYNTAX`.
;; Also: ERRSN (BB13)
ERROR_SYNTAX = 2

;; `RETURN WITHOUT GOSUB`.
;; Also: ERRRG (BB13)
ERROR_RETURN_WITHOUT_GOSUB = 3

;; `OUT OF DATA`.
;; Also: ERROD (BB13)
ERROR_OUT_OF_DATA = 4

;; `ILLEGAL QUANTITY`.
;; Also: ERRFC (BB13)
ERROR_ILLEGAL_QUANTITY = 5

;; `OVERFLOW`.
;; Also: ERROV (BB13)
ERROR_OVERFLOW = 6

;; `OUT OF MEMORY`.
;; Also: ERROM (BB13)
ERROR_OUT_OF_MEMORY = 7

;; `UNDEF'D STATEMENT`.
;; Also: ERRUS (BB13)
ERROR_UNDEFINED_STATEMENT = 8

;; `BAD SUBSCRIPT`.
;; Also: ERRBS (BB13)
ERROR_BAD_SUBSCRIPT = 9

;; `RANGE`.
;; Also: ERRNG (BB13)
ERROR_RANGE = 10

;; `INVOKE`.
;; Also: ERRIN (BB13)
ERROR_INVOKE = 11

;; `STACK OVERFLOW`.
;; Also: ERRSK (BB13)
ERROR_STACK_OVERFLOW = 12

;; `REDIM'D ARRAY`.
;; Also: ERRDD (BB13)
ERROR_REDIMENSIONED_ARRAY = 13

;; `DIVISION BY ZERO`.
;; Also: ERRDV0 (BB13)
ERROR_DIVISION_BY_ZERO = 14

;; `ILLEGAL DIRECT`.
;; Also: ERRID (BB13)
ERROR_ILLEGAL_DIRECT = 15

;; `TYPE MISMATCH`.
;; Also: ERRTM (BB13)
ERROR_TYPE_MISMATCH = 16

;; `STRING TOO LONG`.
;; Also: ERRLS (BB13)
ERROR_STRING_TOO_LONG = 17

;; `FORMULA TOO COMPLEX`.
;; Also: ERRST (BB13)
ERROR_FORMULA_TOO_COMPLEX = 18

;; `CAN'T CONTINUE`.
;; Also: ERRCN (BB13)
ERROR_CANT_CONTINUE = 19

;; `UNDEF'D FUNCTION`.
;; Also: ERRUF (BB13)
ERROR_UNDEFINED_FUNCTION = 20

;; `VARIABLE`.
;; Also: ERRVA (BB13)
ERROR_VARIABLE = 21

;; `SOS CALL`: a SOS error with no message of its own, its code in <SosError>.
;; Also: SSSSSS (BB13)
ERROR_SOS_CALL = 22

;; `FILES BUSY`.
;; Also: ERRFB (BB13)
ERROR_FILES_BUSY = 23

;; `NOT SOS`.
;; Also: ERRNS (BB13)
ERROR_NOT_SOS = 24

;; `I/O`.
;; Also: ERRIO (BB13)
ERROR_IO = 25

;; `FILE TOO LARGE`.
;; Also: ERRCR (BB13)
ERROR_FILE_TOO_LARGE = 26

;; `WRITE PROTECT`.
;; Also: ERRWP (BB13)
ERROR_WRITE_PROTECT = 27

;; `DISK SWITCHED`.
;; Also: ERRDS (BB13)
ERROR_DISK_SWITCHED = 28

;; `BAD PATH`.
;; Also: ERRBP (BB13)
ERROR_BAD_PATH = 29

;; `FILE NOT FOUND`.
;; Also: ERRFN (BB13)
ERROR_FILE_NOT_FOUND = 30

;; `PATH NOT FOUND`.
;; Also: ERRPN (BB13)
ERROR_PATH_NOT_FOUND = 31

;; `VOLUME NOT FOUND`.
;; Also: ERRVN (BB13)
ERROR_VOLUME_NOT_FOUND = 32

;; `DUPLICATE FILE`.
;; Also: ERRDF (BB13)
ERROR_DUPLICATE_FILE = 33

;; `DISK FULL`.
;; Also: ERRFU (BB13)
ERROR_DISK_FULL = 34

;; `FILE LOCKED`.
;; Also: ERRFL (BB13)
ERROR_FILE_LOCKED = 35

;; `FILE NOT OPEN`.
;; Also: ERRNO (BB13)
ERROR_FILE_NOT_OPEN = 36

;; `DEVICE DISCONNECTED`.
;; Also: ERRDO (BB13)
ERROR_DEVICE_DISCONNECTED = 37

;; `RESOURCE UNAVAILABLE`.
;; Also: ERRDU (BB13)
ERROR_RESOURCE_UNAVAILABLE = 38

;; `DIRECTORY FULL`.
;; Also: ERRFD (BB13)
ERROR_DIRECTORY_FULL = 39

;; `DUPLICATE VOLUME`.
;; Also: ERRDV (BB13)
ERROR_DUPLICATE_VOLUME = 40

;; The error messages, each with the last character's bit 7 set, in the order of their numbers from 1.
;;
;; The message is followed by <ErrorSuffix>, then <LineNumberPrefix> and the line number when a program was running.
;; See: <ReportError>, <ErrorCode>
;; Also: ERRTAB (BB13)
ErrorMessages:
    ErrorMessage ERROR_NEXT_WITHOUT_FOR, "NEXT WITHOUT FOR"
    ErrorMessage ERROR_SYNTAX, "SYNTAX"
    ErrorMessage ERROR_RETURN_WITHOUT_GOSUB, "RETURN WITHOUT GOSUB"
    ErrorMessage ERROR_OUT_OF_DATA, "OUT OF DATA"
    ErrorMessage ERROR_ILLEGAL_QUANTITY, "ILLEGAL QUANTITY"
    ErrorMessage ERROR_OVERFLOW, "OVERFLOW"
    ErrorMessage ERROR_OUT_OF_MEMORY, "OUT OF MEMORY"
    ErrorMessage ERROR_UNDEFINED_STATEMENT, "UNDEF'D STATEMENT"
    ErrorMessage ERROR_BAD_SUBSCRIPT, "BAD SUBSCRIPT"
    ErrorMessage ERROR_RANGE, "RANGE"
    ErrorMessage ERROR_INVOKE, "INVOKE"
    ErrorMessage ERROR_STACK_OVERFLOW, "STACK OVERFLOW"
    ErrorMessage ERROR_REDIMENSIONED_ARRAY, "REDIM'D ARRAY"
    ErrorMessage ERROR_DIVISION_BY_ZERO, "DIVISION BY ZERO"
    ErrorMessage ERROR_ILLEGAL_DIRECT, "ILLEGAL DIRECT"
    ErrorMessage ERROR_TYPE_MISMATCH, "TYPE MISMATCH"
    ErrorMessage ERROR_STRING_TOO_LONG, "STRING TOO LONG"
    ErrorMessage ERROR_FORMULA_TOO_COMPLEX, "FORMULA TOO COMPLEX"
    ErrorMessage ERROR_CANT_CONTINUE, "CAN'T CONTINUE"
    ErrorMessage ERROR_UNDEFINED_FUNCTION, "UNDEF'D FUNCTION"
    ErrorMessage ERROR_VARIABLE, "VARIABLE"
    ErrorMessage ERROR_SOS_CALL, "SOS CALL"
    ErrorMessage ERROR_FILES_BUSY, "FILES BUSY"
    ErrorMessage ERROR_NOT_SOS, "NOT SOS"
    ErrorMessage ERROR_IO, "I/O"
    ErrorMessage ERROR_FILE_TOO_LARGE, "FILE TOO LARGE"
    ErrorMessage ERROR_WRITE_PROTECT, "WRITE PROTECT"
    ErrorMessage ERROR_DISK_SWITCHED, "DISK SWITCHED"
    ErrorMessage ERROR_BAD_PATH, "BAD PATH"
    ErrorMessage ERROR_FILE_NOT_FOUND, "FILE NOT FOUND"
    ErrorMessage ERROR_PATH_NOT_FOUND, "PATH NOT FOUND"
    ErrorMessage ERROR_VOLUME_NOT_FOUND, "VOLUME NOT FOUND"
    ErrorMessage ERROR_DUPLICATE_FILE, "DUPLICATE FILE"
    ErrorMessage ERROR_DISK_FULL, "DISK FULL"
    ErrorMessage ERROR_FILE_LOCKED, "FILE LOCKED"
    ErrorMessage ERROR_FILE_NOT_OPEN, "FILE NOT OPEN"
    ErrorMessage ERROR_DEVICE_DISCONNECTED, "DEVICE DISCONNECTED"
    ErrorMessage ERROR_RESOURCE_UNAVAILABLE, "RESOURCE UNAVAILABLE"
    ErrorMessage ERROR_DIRECTORY_FULL, "DIRECTORY FULL"
    ErrorMessage ERROR_DUPLICATE_VOLUME, "DUPLICATE VOLUME"

;; " ERROR" and a bell, which follow every error message, ending in a zero.
;; Also: ERR (BB13)
ErrorSuffix:
    .byte " ERROR"
    .byte CHARACTER_BELL, 0

;; The run-time build's message after a program ends, asking for the space bar before BASIC starts again.
;; Also: RTMSG (BB13)
RunTimeEndMessage:
    .byte CHARACTER_RETURN, CHARACTER_LINE_FEED, CHARACTER_LINE_FEED
    .byte "Please Press SPACE BAR"
    .byte 0

;; " IN ", between an error message and its line number.
;; Also: INTXT (BB13)
LineNumberPrefix:
    .byte " IN "
    .byte 0

;; The message for Control-C, with the screen turned back on and a bell.
;; Also: BRKTXT (BB13)
BreakMessage:
    .byte CHARACTER_RETURN, CHARACTER_LINE_FEED, CHARACTER_LINE_FEED, CHARACTER_SCREEN_ON
    .byte "PROGRAM INTERRUPTED"
    .byte CHARACTER_BELL, 0

; ---------------------------------------------------------------------------------------------------------------------
; SOS errors
; ---------------------------------------------------------------------------------------------------------------------

;; Pairs of a SOS error code and the BASIC error <ReportSosError> gives for it, in rising order of the code, ending with $FF.
;;
;; The search stops at the first code higher than the one it has. A code not here gives `SOS CALL`
;; (<ERROR_SOS_CALL>), with the code in <SosError>. SOS's not a block device gives a `TYPE MISMATCH`.
;; See: <ReportSosError>
;; Also: ERRTBL (BB13)
SosErrors:
    SosErrorEntry SOS_ERROR_NO_DEVICE, ERROR_FILE_NOT_FOUND
    SosErrorEntry SOS_ERROR_NO_RESOURCE, ERROR_RESOURCE_UNAVAILABLE
    SosErrorEntry SOS_ERROR_IO, ERROR_IO
    SosErrorEntry SOS_ERROR_NO_DRIVE, ERROR_DEVICE_DISCONNECTED
    SosErrorEntry SOS_ERROR_WRITE_PROTECTED, ERROR_WRITE_PROTECT
    SosErrorEntry SOS_ERROR_DISK_SWITCHED, ERROR_DISK_SWITCHED
    SosErrorEntry SOS_ERROR_BAD_PATH, ERROR_BAD_PATH
    SosErrorEntry SOS_ERROR_BAD_REFERENCE_NUMBER, ERROR_FILE_NOT_OPEN
    SosErrorEntry SOS_ERROR_PATH_NOT_FOUND, ERROR_PATH_NOT_FOUND
    SosErrorEntry SOS_ERROR_VOLUME_NOT_FOUND, ERROR_VOLUME_NOT_FOUND
    SosErrorEntry SOS_ERROR_FILE_NOT_FOUND, ERROR_FILE_NOT_FOUND
    SosErrorEntry SOS_ERROR_DUPLICATE_FILE, ERROR_DUPLICATE_FILE
    SosErrorEntry SOS_ERROR_DISK_FULL, ERROR_DISK_FULL
    SosErrorEntry SOS_ERROR_DIRECTORY_FULL, ERROR_DIRECTORY_FULL
    SosErrorEntry SOS_ERROR_POSITION_OUT_OF_RANGE, ERROR_FILE_TOO_LARGE
    SosErrorEntry SOS_ERROR_ACCESS_NOT_ALLOWED, ERROR_FILE_LOCKED
    SosErrorEntry SOS_ERROR_FILE_BUSY, ERROR_FILES_BUSY
    SosErrorEntry SOS_ERROR_DIRECTORY_ERROR, ERROR_NOT_SOS
    SosErrorEntry SOS_ERROR_NOT_SOS_VOLUME, ERROR_NOT_SOS
    SosErrorEntry SOS_ERROR_OUT_OF_MEMORY, ERROR_OUT_OF_MEMORY
    SosErrorEntry SOS_ERROR_DUPLICATE_VOLUME, ERROR_DUPLICATE_VOLUME
    SosErrorEntry SOS_ERROR_NOT_BLOCK_DEVICE, ERROR_TYPE_MISMATCH
    .byte $FF                               ; The end

; ---------------------------------------------------------------------------------------------------------------------
; X-bytes of BASIC's own tables
;
; Routines that read through a pointer with its X-byte take these for tables in BASIC itself: zero, so the access
; reads the bank that is switched in.
; ---------------------------------------------------------------------------------------------------------------------

;; The X-byte for <ErrorMessages> and the other messages.
;; Also: ERRTABB (BB13)
ERROR_MESSAGES_X_BYTE = 0

;; The X-byte for <ReservedWords> and <ExtendedReservedWords>.
;; Also: RESLSTB (BB13)
RESERVED_WORDS_X_BYTE = ERROR_MESSAGES_X_BYTE

;; The X-byte for <LongText>.
;; Also: NUMSTRB (BB13)
LONG_TEXT_X_BYTE = 0

;; The X-byte for <Functions::MinusOne>, -1.
;; Also: CON1MB (BB13)
MINUS_ONE_X_BYTE = 0

;; The X-byte for <Float::Half>, one half.
;; Also: FHALFB (BB13)
HALF_X_BYTE = 0

;; The X-byte for <Float::SquareRootOfHalf> and `LOG`'s other constants.
;; Also: SQR0B (BB13)
LOG_CONSTANTS_X_BYTE = 0

;; The X-byte for <Float::Ten>, ten, and for <Float::DivideArgByPacked>'s divisor.
;; Also: TEN_CB (BB13)
TEN_X_BYTE = 0

;; The X-byte for <LineNumberPrefix>.
;; Also: INTXTB (BB13)
LINE_NUMBER_PREFIX_X_BYTE = 0

;; The X-byte for <Float::LowerOutputLimit> and <Float::UpperOutputLimit>, the limits <Float::FormatFac> scales a number between.
;; Also: N_MILB (BB13)
NUMBER_LIMITS_X_BYTE = 0

;; The X-byte for <FloatTemporary3>, in zero page.
;; Also: TEMPF3B (BB13)
FLOAT_TEMPORARY3_X_BYTE = 0

;; The X-byte for <RandomValue>, in zero page.
;; Also: RNDXB (BB13)
RANDOM_VALUE_X_BYTE = 0
