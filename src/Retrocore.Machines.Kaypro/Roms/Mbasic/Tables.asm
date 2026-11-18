;; MBASIC 5.21: TABLES: STATEMENT AND FUNCTION DISPATCH, RESERVED WORDS, OPERATORS AND ERROR MESSAGES
;;
;; Part of Mbasic.asm.

; Two routines' addresses before STMDSP: CINT's, and one not yet identified.
    .word FN_CINT, L_29DC

;; STMDSP: each statement's routine, by its token from $81.
STMDSP:
    .word ST_END, ST_FOR, ST_NEXT, ST_DATA, ST_INPUT, ST_DIM
    .word ST_READ, LET, ST_GOTO, ST_RUN, ST_IF, ST_RESTORE
    .word ST_GOSUB, ST_RETURN, ST_REM, ST_STOP, ST_PRINT, ST_CLEAR
    .word ST_LIST, ST_NEW, ST_ON, ST_NULL, ST_WAIT, ST_DEF
    .word ST_POKE, ST_CONT, SNERR, SNERR, ST_OUT, ST_LPRINT
    .word ST_LLIST, 0, ST_WIDTH, ST_REM, ST_TRON, ST_TROFF
    .word ST_SWAP, ST_ERASE, ST_EDIT, ST_ERROR, ST_RESUME, ST_DELETE
    .word ST_AUTO, ST_RENUM, ST_DEFSTR, ST_DEFINT, ST_DEFSNG, ST_DEFDBL
    .word ST_LINE, 0, 0, ST_WHILE, ST_WEND, ST_CALL
    .word ST_WRITE, ST_DATA, ST_CHAIN, ST_OPTION, ST_RANDOMIZE, 0
    .word ST_SYSTEM, 0, ST_OPEN, ST_FIELD, ST_GET, ST_PUT
    .word ST_CLOSE, ST_LOAD, ST_MERGE, ST_FILES, ST_NAME, ST_KILL
    .word ST_LSET, ST_RSET, ST_SAVE, ST_RESET

;; FUNDSP: each function's routine, by its number from LEFT$'s, 1.
FUNDSP:
    .word FN_LEFT, FN_RIGHT, FN_MID, FN_SGN, FN_INT, FN_ABS
    .word FN_SQR, FN_RND, FN_SIN, FN_LOG, FN_EXP, FN_COS
    .word FN_TAN, FN_ATN, FN_FRE, FN_INP, FN_POS, FN_LEN
    .word FN_STR, FN_VAL, FN_ASC, FN_CHR, FN_PEEK, FN_SPACE
    .word FN_OCT, FN_HEX, FN_LPOS, FN_CINT, FN_CSNG, FN_CDBL
    .word FN_FIX, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0
    .word FN_CVI, FN_CVS, FN_CVD, 0, FN_EOF, FN_LOC
    .word FN_LOF, FN_MKI, FN_MKS, FN_MKD

;; ALPTAB: each letter's reserved words.
ALPTAB:
    .word ATAB, BTAB, CTAB, DTAB, ETAB, FTAB, GTAB
    .word HTAB, ITAB, JTAB, KTAB, LTAB, MTAB, NTAB
    .word OTAB, PTAB, QTAB, RTAB, STAB, TTAB, UTAB
    .word VTAB, WTAB, XTAB, YTAB, ZTAB

ATAB:
    RESWORD "UTO", $AB
    RESWORD "ND", $F7
    RESWORD "BS", $06             ; a function
    RESWORD "TN", $0E             ; a function
    RESWORD "SC", $15             ; a function
    .byte 0
BTAB:
    .byte 0
CTAB:
    RESWORD "LOSE", $C3
    RESWORD "ONT", $9A
    RESWORD "LEAR", $92
    RESWORD "INT", $1C             ; a function
    RESWORD "SNG", $1D             ; a function
    RESWORD "DBL", $1E             ; a function
    RESWORD "VI", $2B             ; a function
    RESWORD "VS", $2C             ; a function
    RESWORD "VD", $2D             ; a function
    RESWORD "OS", $0C             ; a function
    RESWORD "HR$", $16             ; a function
    RESWORD "ALL", $B6
    RESWORD "OMMON", $B8
    RESWORD "HAIN", $B9
    .byte 0
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
ETAB:
    RESWORD "LSE", $A2
    RESWORD "ND", $81
    RESWORD "RASE", $A6
    RESWORD "DIT", $A7
    RESWORD "RROR", $A8
    RESWORD "RL", $D6
    RESWORD "RR", $D7
    RESWORD "XP", $0B             ; a function
    RESWORD "OF", $2F             ; a function
    RESWORD "QV", $FA
    .byte 0
FTAB:
    RESWORD "OR", $82
    RESWORD "IELD", $C0
    RESWORD "ILES", $C6
    RESWORD "N", $D3
    RESWORD "RE", $0F             ; a function
    RESWORD "IX", $1F             ; a function
    .byte 0
GTAB:
    RESWORD "OTO", $89
    RESWORD "O TO", $89
    RESWORD "OSUB", $8D
    RESWORD "ET", $C1
    .byte 0
HTAB:
    RESWORD "EX$", $1A             ; a function
    .byte 0
ITAB:
    RESWORD "NPUT", $85
    RESWORD "F", $8B
    RESWORD "NSTR", $DA
    RESWORD "NT", $05             ; a function
    RESWORD "NP", $10             ; a function
    RESWORD "MP", $FB
    RESWORD "NKEY$", $DD
    .byte 0
JTAB:
    .byte 0
KTAB:
    RESWORD "ILL", $C8
    .byte 0
LTAB:
    RESWORD "PRINT", $9E
    RESWORD "LIST", $9F
    RESWORD "POS", $1B             ; a function
    RESWORD "ET", $88
    RESWORD "INE", $B1
    RESWORD "OAD", $C4
    RESWORD "SET", $C9
    RESWORD "IST", $93
    RESWORD "OG", $0A             ; a function
    RESWORD "OC", $30             ; a function
    RESWORD "EN", $12             ; a function
    RESWORD "EFT$", $01             ; a function
    RESWORD "OF", $31             ; a function
    .byte 0
MTAB:
    RESWORD "ERGE", $C5
    RESWORD "OD", $FC
    RESWORD "KI$", $32             ; a function
    RESWORD "KS$", $33             ; a function
    RESWORD "KD$", $34             ; a function
    RESWORD "ID$", $03             ; a function
    .byte 0
NTAB:
    RESWORD "EXT", $83
    RESWORD "ULL", $96
    RESWORD "AME", $C7
    RESWORD "EW", $94
    RESWORD "OT", $D5
    .byte 0
OTAB:
    RESWORD "PEN", $BF
    RESWORD "UT", $9D
    RESWORD "N", $95
    RESWORD "R", $F8
    RESWORD "CT$", $19             ; a function
    RESWORD "PTION", $BA
    .byte 0
PTAB:
    RESWORD "RINT", $91
    RESWORD "UT", $C2
    RESWORD "OKE", $99
    RESWORD "OS", $11             ; a function
    RESWORD "EEK", $17             ; a function
    .byte 0
QTAB:
    .byte 0
RTAB:
    RESWORD "ETURN", $8E
    RESWORD "EAD", $87
    RESWORD "UN", $8A
    RESWORD "ESTORE", $8C
    RESWORD "EM", $8F
    RESWORD "ESUME", $A9
    RESWORD "SET", $CA
    RESWORD "IGHT$", $02             ; a function
    RESWORD "ND", $08             ; a function
    RESWORD "ENUM", $AC
    RESWORD "ESET", $CC
    RESWORD "ANDOMIZE", $BB
    .byte 0
STAB:
    RESWORD "TOP", $90
    RESWORD "WAP", $A5
    RESWORD "AVE", $CB
    RESWORD "PC(", $D4
    RESWORD "TEP", $D1
    RESWORD "GN", $04             ; a function
    RESWORD "QR", $07             ; a function
    RESWORD "IN", $09             ; a function
    RESWORD "TR$", $13             ; a function
    RESWORD "TRING$", $D8
    RESWORD "PACE$", $18             ; a function
    RESWORD "YSTEM", $BD
    .byte 0
TTAB:
    RESWORD "HEN", $CF
    RESWORD "RON", $A3
    RESWORD "ROFF", $A4
    RESWORD "AB(", $D0
    RESWORD "O", $CE
    RESWORD "AN", $0D             ; a function
    .byte 0
UTAB:
    RESWORD "SING", $D9
    RESWORD "SR", $D2
    .byte 0
VTAB:
    RESWORD "AL", $14             ; a function
    RESWORD "ARPTR", $DC
    .byte 0
WTAB:
    RESWORD "IDTH", $A1
    RESWORD "AIT", $97
    RESWORD "HILE", $B4
    RESWORD "END", $B5
    RESWORD "RITE", $B7
    .byte 0
XTAB:
    RESWORD "OR", $F9
    .byte 0
YTAB:
    .byte 0
ZTAB:
    .byte 0

;; SPCTAB: the characters that are operators, each with bit 7 set and its token.
SPCTAB:
    .byte '+' | $80, $F2
    .byte '-' | $80, $F3
    .byte '*' | $80, $F4
    .byte '/' | $80, $F5
    .byte '^' | $80, $F6
    .byte $DC, $FD                  ; \
    .byte $A7, $DB                  ; '
    .byte '>' | $80, $EF
    .byte '=' | $80, $F0
    .byte '<' | $80, $F1
    .byte 0

;; OPTAB: the precedence of + - * / ^ AND OR XOR EQV IMP MOD and \, which FRMEVL compares.
OPTAB:
    .byte 121, 121, 124, 124, 127, 80, 70, 60, 50, 40, 122, 123

;; The operators' type conversions and dispatch.
OPDISP:
    .byte $20, $2A, $00, $00, $7A, $29, $3B, $2A, $F4, $29, $26, $2C, $1F, $2C, $64, $2D
    .byte $44, $2E, $73, $29, $88, $25, $85, $25, $03, $27, $69, $27, $06, $29, $31, $2B
    .byte $25, $2B, $51, $2B, $84, $1B, $33, $29

;; ERRTAB: the error messages, by code: 1-30, then 50 on.
ERRTAB:
    .byte 0
    .byte "NEXT without FOR", 0
    .byte "Syntax error", 0
    .byte "RETURN without GOSUB", 0
    .byte "Out of DATA", 0
    .byte "Illegal function call", 0
    .byte "Overflow", 0
    .byte "Out of memory", 0
    .byte "Undefined line number", 0
    .byte "Subscript out of range", 0
    .byte "Duplicate Definition", 0
    .byte "Division by zero", 0
    .byte "Illegal direct", 0
    .byte "Type mismatch", 0
    .byte "Out of string space", 0
    .byte "String too long", 0
    .byte "String formula too complex", 0
    .byte "Can't continue", 0
    .byte "Undefined user function", 0
    .byte "No RESUME", 0
    .byte "RESUME without error", 0
    .byte "Unprintable error", 0
    .byte "Missing operand", 0
    .byte "Line buffer overflow", 0
    .byte "?", 0
    .byte "?", 0
    .byte "FOR Without NEXT", 0
    .byte "?", 0
    .byte "?", 0
    .byte "WHILE without WEND", 0
    .byte "WEND without WHILE", 0
    .byte "FIELD overflow", 0
    .byte "Internal error", 0
    .byte "Bad file number", 0
    .byte "File not found", 0
    .byte "Bad file mode", 0
    .byte "File already open", 0
    .byte "?", 0
    .byte "Disk I/O error", 0
    .byte "File already exists", 0
    .byte "?", 0
    .byte "?", 0
    .byte "Disk full", 0
    .byte "Input past end", 0
    .byte "Bad record number", 0
    .byte "Bad file name", 0
    .byte "?", 0
    .byte "Direct statement in file", 0
    .byte "Too many files", 0
