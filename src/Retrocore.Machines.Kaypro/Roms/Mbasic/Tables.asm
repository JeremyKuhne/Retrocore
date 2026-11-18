;; MBASIC 5.21: TABLES: STATEMENT AND FUNCTION DISPATCH, RESERVED WORDS, OPERATORS AND ERROR MESSAGES
;;
;; The interpreter's constant tables, at $0103-$0773, after the jump to INIT at $0100. GW-BASIC keeps them in
;; IBMRES.ASM (the dispatch tables and the reserved words) and GWDATA.ASM (the operator tables and the error
;; messages).
;;
;; - USRCNV, at the fixed addresses $0103 and $0105, gives a USR routine the addresses of FRCINT and MAKINT.
;; - STMDSP holds each statement's routine by its token, $81 on; GONE dispatches through it. FUNDSP holds each
;;   function's routine by its number, which follows the $FF prefix in the crunched text.
;; - ALPTAB points to each letter's list of reserved words, ATAB to ZTAB, each word written by the RESWORD
;;   macro (Mbasic.asm). CRUNCH looks a word up by its first letter, and LIST finds a token's word by scanning
;;   the whole list from RESLST. SPCTAB holds the operators that are single characters.
;; - OPTAB holds each operator's precedence for FRMEVL. FRCTBL holds the routines that convert a value to a
;;   type, for LET, and DBLDSP, SNGDSP and INTDSP the arithmetic routines that APPLOP calls once both operands
;;   have the same type.
;; - ERRTAB holds the error messages, which ERROR finds by counting zeros up to the error's code.

;; The addresses of FRCINT and MAKINT, at the fixed addresses $0103 and $0105 that the MBASIC manual gives USR
;; routines: FRCINT (CINT) converts the argument in FAC to an integer in HL, and MAKINT returns the integer in HL
;; as the function's value.
USRCNV:
    .word FN_CINT, MAKINT

;; Each statement's routine, by its token from END's, $81; a zero is a token that is not a statement.
STMDSP:
    .word ST_END                    ; $81 END
    .word ST_FOR                    ; $82 FOR
    .word ST_NEXT                   ; $83 NEXT
    .word ST_DATA                   ; $84 DATA
    .word ST_INPUT                  ; $85 INPUT
    .word ST_DIM                    ; $86 DIM
    .word ST_READ                   ; $87 READ
    .word LET                       ; $88 LET
    .word ST_GOTO                   ; $89 GOTO
    .word ST_RUN                    ; $8A RUN
    .word ST_IF                     ; $8B IF
    .word ST_RESTORE                ; $8C RESTORE
    .word ST_GOSUB                  ; $8D GOSUB
    .word ST_RETURN                 ; $8E RETURN
    .word ST_REM                    ; $8F REM
    .word ST_STOP                   ; $90 STOP
    .word ST_PRINT                  ; $91 PRINT
    .word ST_CLEAR                  ; $92 CLEAR
    .word ST_LIST                   ; $93 LIST
    .word ST_NEW                    ; $94 NEW
    .word ST_ON                     ; $95 ON
    .word ST_NULL                   ; $96 NULL
    .word ST_WAIT                   ; $97 WAIT
    .word ST_DEF                    ; $98 DEF
    .word ST_POKE                   ; $99 POKE
    .word ST_CONT                   ; $9A CONT
    .word SNERR                     ; $9B, no word: a syntax error
    .word SNERR                     ; $9C, no word: a syntax error
    .word ST_OUT                    ; $9D OUT
    .word ST_LPRINT                 ; $9E LPRINT
    .word ST_LLIST                  ; $9F LLIST
    .word 0                         ; $A0, no word
    .word ST_WIDTH                  ; $A1 WIDTH
    .word ST_REM                    ; $A2 ELSE: reached after THEN's part has run, so skipped like REM
    .word ST_TRON                   ; $A3 TRON
    .word ST_TROFF                  ; $A4 TROFF
    .word ST_SWAP                   ; $A5 SWAP
    .word ST_ERASE                  ; $A6 ERASE
    .word ST_EDIT                   ; $A7 EDIT
    .word ST_ERROR                  ; $A8 ERROR
    .word ST_RESUME                 ; $A9 RESUME
    .word ST_DELETE                 ; $AA DELETE
    .word ST_AUTO                   ; $AB AUTO
    .word ST_RENUM                  ; $AC RENUM
    .word ST_DEFSTR                 ; $AD DEFSTR
    .word ST_DEFINT                 ; $AE DEFINT
    .word ST_DEFSNG                 ; $AF DEFSNG
    .word ST_DEFDBL                 ; $B0 DEFDBL
    .word ST_LINE                   ; $B1 LINE
    .word 0                         ; $B2, no word
    .word 0                         ; $B3, no word
    .word ST_WHILE                  ; $B4 WHILE
    .word ST_WEND                   ; $B5 WEND
    .word ST_CALL                   ; $B6 CALL
    .word ST_WRITE                  ; $B7 WRITE
    .word ST_DATA                   ; $B8 COMMON: skipped like DATA; CHAIN reads it
    .word ST_CHAIN                  ; $B9 CHAIN
    .word ST_OPTION                 ; $BA OPTION
    .word ST_RANDOMIZE              ; $BB RANDOMIZE
    .word 0                         ; $BC, no word
    .word ST_SYSTEM                 ; $BD SYSTEM
    .word 0                         ; $BE, no word
    .word ST_OPEN                   ; $BF OPEN
    .word ST_FIELD                  ; $C0 FIELD
    .word ST_GET                    ; $C1 GET
    .word ST_PUT                    ; $C2 PUT
    .word ST_CLOSE                  ; $C3 CLOSE
    .word ST_LOAD                   ; $C4 LOAD
    .word ST_MERGE                  ; $C5 MERGE
    .word ST_FILES                  ; $C6 FILES
    .word ST_NAME                   ; $C7 NAME
    .word ST_KILL                   ; $C8 KILL
    .word ST_LSET                   ; $C9 LSET
    .word ST_RSET                   ; $CA RSET
    .word ST_SAVE                   ; $CB SAVE
    .word ST_RESET                  ; $CC RESET

;; Each function's routine, by its number from LEFT$'s, 1, which follows the $FF prefix in the program; a zero is
;; a number that is not a function.
FUNDSP:
    .word FN_LEFT                   ; $01 LEFT$
    .word FN_RIGHT                  ; $02 RIGHT$
    .word FN_MID                    ; $03 MID$
    .word FN_SGN                    ; $04 SGN
    .word FN_INT                    ; $05 INT
    .word FN_ABS                    ; $06 ABS
    .word FN_SQR                    ; $07 SQR
    .word FN_RND                    ; $08 RND
    .word FN_SIN                    ; $09 SIN
    .word FN_LOG                    ; $0A LOG
    .word FN_EXP                    ; $0B EXP
    .word FN_COS                    ; $0C COS
    .word FN_TAN                    ; $0D TAN
    .word FN_ATN                    ; $0E ATN
    .word FN_FRE                    ; $0F FRE
    .word FN_INP                    ; $10 INP
    .word FN_POS                    ; $11 POS
    .word FN_LEN                    ; $12 LEN
    .word FN_STR                    ; $13 STR$
    .word FN_VAL                    ; $14 VAL
    .word FN_ASC                    ; $15 ASC
    .word FN_CHR                    ; $16 CHR$
    .word FN_PEEK                   ; $17 PEEK
    .word FN_SPACE                  ; $18 SPACE$
    .word FN_OCT                    ; $19 OCT$
    .word FN_HEX                    ; $1A HEX$
    .word FN_LPOS                   ; $1B LPOS
    .word FN_CINT                   ; $1C CINT
    .word FN_CSNG                   ; $1D CSNG
    .word FN_CDBL                   ; $1E CDBL
    .word FN_FIX                    ; $1F FIX
    .word 0, 0, 0, 0, 0, 0          ; $20-$25, no word
    .word 0, 0, 0, 0, 0             ; $26-$2A, no word
    .word FN_CVI                    ; $2B CVI
    .word FN_CVS                    ; $2C CVS
    .word FN_CVD                    ; $2D CVD
    .word 0                         ; $2E, no word
    .word FN_EOF                    ; $2F EOF
    .word FN_LOC                    ; $30 LOC
    .word FN_LOF                    ; $31 LOF
    .word FN_MKI                    ; $32 MKI$
    .word FN_MKS                    ; $33 MKS$
    .word FN_MKD                    ; $34 MKD$

;; Each letter's list of reserved words in RESLST, A to Z, which CRUNCH picks by a word's first letter.
ALPTAB:
    .word ATAB, BTAB, CTAB, DTAB, ETAB, FTAB, GTAB
    .word HTAB, ITAB, JTAB, KTAB, LTAB, MTAB, NTAB
    .word OTAB, PTAB, QTAB, RTAB, STAB, TTAB, UTAB
    .word VTAB, WTAB, XTAB, YTAB, ZTAB

;; The reserved words, by their first letter, as ALPTAB points to them; RESLST starts the whole list.
;; Each letter's list ends with a zero. ATAB is the first: the words that start with A.
RESLST:
ATAB:
    RESWORD "UTO", $AB
    RESWORD "ND", $F7
    RESWORD "BS", $06               ; a function
    RESWORD "TN", $0E               ; a function
    RESWORD "SC", $15               ; a function
    .byte 0

;; No reserved word starts with B: an empty list.
BTAB:
    .byte 0

;; The reserved words that start with C.
CTAB:
    RESWORD "LOSE", $C3
    RESWORD "ONT", $9A
    RESWORD "LEAR", $92
    RESWORD "INT", $1C              ; a function
    RESWORD "SNG", $1D              ; a function
    RESWORD "DBL", $1E              ; a function
    RESWORD "VI", $2B               ; a function
    RESWORD "VS", $2C               ; a function
    RESWORD "VD", $2D               ; a function
    RESWORD "OS", $0C               ; a function
    RESWORD "HR$", $16              ; a function
    RESWORD "ALL", $B6
    RESWORD "OMMON", $B8
    RESWORD "HAIN", $B9
    .byte 0

;; The reserved words that start with D.
DTAB:
    RESWORD "ELETE", $AA
    RESWORD "ATA", $84
    RESWORD "IM", $86
    RESWORD "EFSTR", $AD
    RESWORD "EFINT", $AE
    RESWORD "EFSNG", $AF
    RESWORD "EFDBL", $B0
    RESWORD "EF", $98
    .byte 0

;; The reserved words that start with E.
ETAB:
    RESWORD "LSE", $A2
    RESWORD "ND", $81
    RESWORD "RASE", $A6
    RESWORD "DIT", $A7
    RESWORD "RROR", $A8
    RESWORD "RL", $D6
    RESWORD "RR", $D7
    RESWORD "XP", $0B               ; a function
    RESWORD "OF", $2F               ; a function
    RESWORD "QV", $FA
    .byte 0

;; The reserved words that start with F.
FTAB:
    RESWORD "OR", $82
    RESWORD "IELD", $C0
    RESWORD "ILES", $C6
    RESWORD "N", $D3
    RESWORD "RE", $0F               ; a function
    RESWORD "IX", $1F               ; a function
    .byte 0

;; The reserved words that start with G.
GTAB:
    RESWORD "OTO", $89
    RESWORD "O TO", $89
    RESWORD "OSUB", $8D
    RESWORD "ET", $C1
    .byte 0

;; The reserved words that start with H.
HTAB:
    RESWORD "EX$", $1A              ; a function
    .byte 0

;; The reserved words that start with I.
ITAB:
    RESWORD "NPUT", $85
    RESWORD "F", $8B
    RESWORD "NSTR", $DA
    RESWORD "NT", $05               ; a function
    RESWORD "NP", $10               ; a function
    RESWORD "MP", $FB
    RESWORD "NKEY$", $DD
    .byte 0

;; No reserved word starts with J: an empty list.
JTAB:
    .byte 0

;; The reserved words that start with K.
KTAB:
    RESWORD "ILL", $C8
    .byte 0

;; The reserved words that start with L.
LTAB:
    RESWORD "PRINT", $9E
    RESWORD "LIST", $9F
    RESWORD "POS", $1B              ; a function
    RESWORD "ET", $88
    RESWORD "INE", $B1
    RESWORD "OAD", $C4
    RESWORD "SET", $C9
    RESWORD "IST", $93
    RESWORD "OG", $0A               ; a function
    RESWORD "OC", $30               ; a function
    RESWORD "EN", $12               ; a function
    RESWORD "EFT$", $01             ; a function
    RESWORD "OF", $31               ; a function
    .byte 0

;; The reserved words that start with M.
MTAB:
    RESWORD "ERGE", $C5
    RESWORD "OD", $FC
    RESWORD "KI$", $32              ; a function
    RESWORD "KS$", $33              ; a function
    RESWORD "KD$", $34              ; a function
    RESWORD "ID$", $03              ; a function
    .byte 0

;; The reserved words that start with N.
NTAB:
    RESWORD "EXT", $83
    RESWORD "ULL", $96
    RESWORD "AME", $C7
    RESWORD "EW", $94
    RESWORD "OT", $D5
    .byte 0

;; The reserved words that start with O.
OTAB:
    RESWORD "PEN", $BF
    RESWORD "UT", $9D
    RESWORD "N", $95
    RESWORD "R", $F8
    RESWORD "CT$", $19              ; a function
    RESWORD "PTION", $BA
    .byte 0

;; The reserved words that start with P.
PTAB:
    RESWORD "RINT", $91
    RESWORD "UT", $C2
    RESWORD "OKE", $99
    RESWORD "OS", $11               ; a function
    RESWORD "EEK", $17              ; a function
    .byte 0

;; No reserved word starts with Q: an empty list.
QTAB:
    .byte 0

;; The reserved words that start with R.
RTAB:
    RESWORD "ETURN", $8E
    RESWORD "EAD", $87
    RESWORD "UN", $8A
    RESWORD "ESTORE", $8C
    RESWORD "EM", $8F
    RESWORD "ESUME", $A9
    RESWORD "SET", $CA
    RESWORD "IGHT$", $02            ; a function
    RESWORD "ND", $08               ; a function
    RESWORD "ENUM", $AC
    RESWORD "ESET", $CC
    RESWORD "ANDOMIZE", $BB
    .byte 0

;; The reserved words that start with S.
STAB:
    RESWORD "TOP", $90
    RESWORD "WAP", $A5
    RESWORD "AVE", $CB
    RESWORD "PC(", $D4
    RESWORD "TEP", $D1
    RESWORD "GN", $04               ; a function
    RESWORD "QR", $07               ; a function
    RESWORD "IN", $09               ; a function
    RESWORD "TR$", $13              ; a function
    RESWORD "TRING$", $D8
    RESWORD "PACE$", $18            ; a function
    RESWORD "YSTEM", $BD
    .byte 0

;; The reserved words that start with T.
TTAB:
    RESWORD "HEN", $CF
    RESWORD "RON", $A3
    RESWORD "ROFF", $A4
    RESWORD "AB(", $D0
    RESWORD "O", $CE
    RESWORD "AN", $0D               ; a function
    .byte 0

;; The reserved words that start with U.
UTAB:
    RESWORD "SING", $D9
    RESWORD "SR", $D2
    .byte 0

;; The reserved words that start with V.
VTAB:
    RESWORD "AL", $14               ; a function
    RESWORD "ARPTR", $DC
    .byte 0

;; The reserved words that start with W.
WTAB:
    RESWORD "IDTH", $A1
    RESWORD "AIT", $97
    RESWORD "HILE", $B4
    RESWORD "END", $B5
    RESWORD "RITE", $B7
    .byte 0

;; The reserved words that start with X.
XTAB:
    RESWORD "OR", $F9
    .byte 0

;; No reserved word starts with Y: an empty list.
YTAB:
    .byte 0

;; No reserved word starts with Z: an empty list.
ZTAB:
    .byte 0

;; The operators that are single characters, each with bit 7 set and then its token, ending with a zero. CRUNCH
;; looks a character up here when no reserved word starts with it.
SPCTAB:
    .byte '+' | $80, $F2
    .byte '-' | $80, $F3
    .byte '*' | $80, $F4
    .byte '/' | $80, $F5
    .byte '^' | $80, $F6
    .byte $DC, $FD                  ; the backslash | $80: integer division
    .byte $A7, $DB                  ; the apostrophe | $80: a remark
    .byte '>' | $80, $EF
    .byte '=' | $80, $F0
    .byte '<' | $80, $F1
    .byte 0

;; Each operator's precedence, by its token less $F2: + - * / ^ AND OR XOR EQV IMP MOD and the backslash. FRMEVL
;; applies the operator on its left first when that one's precedence is at least as high.
OPTAB:
    .byte 121                       ; +
    .byte 121                       ; -
    .byte 124                       ; *
    .byte 124                       ; /
    .byte 127                       ; ^
    .byte 80                        ; AND
    .byte 70                        ; OR
    .byte 60                        ; XOR
    .byte 50                        ; EQV
    .byte 40                        ; IMP
    .byte 122                       ; MOD
    .byte 123                       ; the backslash, integer division

;; The routines that convert FAC to a type, for LET to make a value its variable's type, by twice the type's low
;; three bits: double (8) first, then integer (2), string (3) and single (4).
FRCTBL:
    .word FN_CDBL                   ; 8: FRCDBL
    .word 0                         ; no type 1
    .word FN_CINT                   ; 2: FRCINT
    .word CHKSTR                    ; 3: CHKSTR, a type mismatch unless it is a string
    .word FN_CSNG                   ; 4: FRCSNG

;; The double precision operators, which APPLOP calls when both operands are double: add, subtract, multiply,
;; divide and compare.
DBLDSP:
    .word DADD
    .word DSUB
    .word DMULT
    .word DDIV
    .word DCOMP

;; The single precision operators, which APPLOP calls when both operands are single: add, subtract, multiply,
;; divide and compare.
SNGDSP:
    .word FADD
    .word FSUB
    .word FMULT
    .word FDIV
    .word FCOMP

;; The integer operators, which APPLOP calls when both operands are integers: add, subtract, multiply, divide (in
;; single precision) and compare.
INTDSP:
    .word IADD
    .word ISUB
    .word IMULT
    .word INTDIV
    .word ICOMP

;; The error messages, each ending with a zero, by their code: 1-30, then the disk errors from 50. ERROR counts
;; the zeros from the first up to the code; "?" stands for a code with no message.
ERRTAB:
    .byte 0
    .byte "NEXT without FOR", 0     ; 1 NF
    .byte "Syntax error", 0         ; 2 SN
    .byte "RETURN without GOSUB", 0 ; 3 RG
    .byte "Out of DATA", 0          ; 4 OD
    .byte "Illegal function call", 0 ; 5 FC

;; The overflow message, which OVERRI points to.
OVRMSG:
    .byte "Overflow", 0             ; 6 OV
    .byte "Out of memory", 0        ; 7 OM
    .byte "Undefined line number", 0 ; 8 UL
    .byte "Subscript out of range", 0 ; 9 BS
    .byte "Duplicate Definition", 0 ; 10 DD

;; The division by zero message, which the math package puts in OVERRI to print it.
DIVMSG:
    .byte "Division by zero", 0     ; 11 /0
    .byte "Illegal direct", 0       ; 12 ID
    .byte "Type mismatch", 0        ; 13 TM
    .byte "Out of string space", 0  ; 14 OS
    .byte "String too long", 0      ; 15 LS
    .byte "String formula too complex", 0 ; 16 ST
    .byte "Can't continue", 0       ; 17 CN
    .byte "Undefined user function", 0 ; 18 UF
    .byte "No RESUME", 0            ; 19 NR
    .byte "RESUME without error", 0 ; 20 RW
    .byte "Unprintable error", 0    ; 21 UE
    .byte "Missing operand", 0      ; 22 MO
    .byte "Line buffer overflow", 0 ; 23 BO
    .byte "?", 0                    ; 24
    .byte "?", 0                    ; 25
    .byte "FOR Without NEXT", 0     ; 26 FN
    .byte "?", 0                    ; 27
    .byte "?", 0                    ; 28
    .byte "WHILE without WEND", 0   ; 29 WH
    .byte "WEND without WHILE", 0   ; 30 WE
    .byte "FIELD overflow", 0       ; 50 FO
    .byte "Internal error", 0       ; 51 IE
    .byte "Bad file number", 0      ; 52 BN
    .byte "File not found", 0       ; 53 FF
    .byte "Bad file mode", 0        ; 54 BM
    .byte "File already open", 0    ; 55 AO
    .byte "?", 0                    ; 56
    .byte "Disk I/O error", 0       ; 57 IO
    .byte "File already exists", 0  ; 58 FE
    .byte "?", 0                    ; 59
    .byte "?", 0                    ; 60
    .byte "Disk full", 0            ; 61 DF
    .byte "Input past end", 0       ; 62 EF
    .byte "Bad record number", 0    ; 63 RN
    .byte "Bad file name", 0        ; 64 NM
    .byte "?", 0                    ; 65
    .byte "Direct statement in file", 0 ; 66 DS
    .byte "Too many files", 0       ; 67 FL
