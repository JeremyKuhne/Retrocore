;; MBASIC 5.21 FOR CP/M ($0100-$5FFF)
;;
;; Microsoft's BASIC-80 interpreter, Rev. 5.21 (28 July 1981), as MBASIC.COM: a CP/M program that loads at $0100
;; and calls CP/M's BDOS at $0005 for its console, printer and files.
;;
;; It follows Microsoft's design, which GW-BASIC's MIT-licensed source (https://github.com/microsoft/GW-BASIC) keeps
;; nearly line for line. A line is crunched into tokens, with its numbers in binary; NEWSTT runs a statement at a time,
;; GONE dispatching each through STMDSP and functions through FUNDSP; errors load their code into E and jump to ERROR.
;; Numbers are integers, or single or double precision in Microsoft's binary format. The program starts at TXTTAB, its
;; simple variables at VARTAB and its arrays at ARYTAB, and strings grow down from MEMSIZ to FRETOP.
;;
;; Labels are Microsoft's names, as GW-BASIC's source gives them, for the routines and variables identified so far;
;; statement and function handlers are named for their keyword (ST_FOR, FN_LEFT), as in Level2.asm. Labels still
;; named L_ or D_ and their address are routines and variables not yet identified.
;;
;; Maintained by hand. KayproTests check that it assembles to a program compatible byte for byte with MBASIC.COM.

.cpu Z80

; Addresses outside the program that it refers to, not yet identified.
L_0000 = $0000
D_0001 = $0001
L_0005 = $0005
D_0006 = $0006
L_0008 = $0008
D_64CD = $64CD
L_7F1E = $7F1E
L_D1EB = $D1EB
L_E1C1 = $E1C1

;; A reserved word in ALPTAB: its letters after the first, the last with bit 7 set, then its token. A token below
;; $80 is a function's, which CRUNCH stores after $FF.
.macro RESWORD rest, token
    .repeat .strlen(rest) - 1, index
    .byte .strat(rest, index)
    .endrepeat
    .byte .strat(rest, .strlen(rest) - 1) | $80, token
.endmacro

.org $0100
    JP L_5D8C
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

; BASIC's variables, with the values the file starts them at.
    .byte $18, $14, $18, $14, $18, $14, $18, $14, $18, $14, $18, $14, $18, $14, $18, $14
    .byte $18, $14, $18, $14
D_0788:
    .byte $01
D_0789:
    .byte $00
D_078A:
    .byte $00, $00
D_078C:
    .byte $00
D_078D:
    .byte $00
D_078E:
    .byte $70
D_078F:
    .byte $84
D_0790:
    .byte $50
D_0791:
    .byte $38
D_0792:
    .byte $00
D_0793:
    .byte $00
D_0794:
    .byte $00, $00
TOPMEM:
    .byte $A3, $60
CURLIN:
    .byte $FE, $FF
TXTTAB:
    .byte $40, $60
D_079C:
    .byte $09, $05
D_079E:
    .byte $00
D_079F:
    .byte $00
D_07A0:
    .byte $00, $00
D_07A2:
    .byte $00, $00
D_07A4:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
D_07C4:
    .byte $00
D_07C5:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00
D_07EC:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00
D_07FE:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
D_080A:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00
D_081F:
    .byte $00
D_0820:
    .byte $00
D_0821:
    .byte $00, $3A, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $2C
D_0962:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00
D_0A64:
    .byte $00
D_0A65:
    .byte $00
D_0A66:
    .byte $00
D_0A67:
    .byte $00
D_0A68:
    .byte $00
D_0A69:
    .byte $00
D_0A6A:
    .byte $00, $00
D_0A6C:
    .byte $00
D_0A6D:
    .byte $00
D_0A6E:
    .byte $00, $00
D_0A70:
    .byte $00, $00, $00, $00, $00, $00
MEMSIZ:
    .byte $00, $00
TEMPPT:
    .byte $00, $00
TEMPST:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
DSCTMP:
    .byte $00
D_0A99:
    .byte $00, $00
FRETOP:
    .byte $00, $00
TEMP3:
    .byte $00, $00
TEMP8:
    .byte $00, $00
ENDFOR:
    .byte $00, $00
DATLIN:
    .byte $00, $00
SUBFLG:
    .byte $00
FLGINP:
    .byte $00
TEMP:
    .byte $00, $00
PTRFLG:
    .byte $00
AUTFLG:
    .byte $00
AUTLIN:
    .byte $00, $00
AUTINC:
    .byte $00, $00
SAVTXT:
    .byte $00, $00
SAVSTK:
    .byte $00, $00
ERRLIN:
    .byte $00, $00
DOT:
    .byte $00, $00
ERRTXT:
    .byte $00, $00
ONELIN:
    .byte $00, $00
ONEFLG:
    .byte $00
TEMP2:
    .byte $00, $00
OLDLIN:
    .byte $00, $00
OLDTXT:
    .byte $00, $00
VARTAB:
    .byte $00, $00
ARYTAB:
    .byte $00, $00
STREND:
    .byte $00, $00
DATPTR:
    .byte $00, $00
DEFTBL:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
D_0AE4:
    .byte $00, $00
D_0AE6:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00
D_0B4C:
    .byte $00, $00
D_0B4E:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00
D_0BB4:
    .byte $00
D_0BB5:
    .byte $00
D_0BB6:
    .byte $00
D_0BB7:
    .byte $00
D_0BB8:
    .byte $00, $00
D_0BBA:
    .byte $00, $00
D_0BBC:
    .byte $00
D_0BBD:
    .byte $00, $00
D_0BBF:
    .byte $00
D_0BC0:
    .byte $00, $00, $00, $00
D_0BC4:
    .byte $00, $00
D_0BC6:
    .byte $00
D_0BC7:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
D_0BE6:
    .byte $00
D_0BE7:
    .byte $00
D_0BE8:
    .byte $00, $00
D_0BEA:
    .byte $00, $00
D_0BEC:
    .byte $00
D_0BED:
    .byte $00
D_0BEE:
    .byte $00
D_0BEF:
    .byte $00, $00
D_0BF1:
    .byte $00, $00
D_0BF3:
    .byte $00
D_0BF4:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
TRCFLG:
    .byte $00
D_0BFF:
    .byte $00
D_0C00:
    .byte $00, $00
D_0C02:
    .byte $00, $00
D_0C04:
    .byte $00, $00
D_0C06:
    .byte $00
D_0C07:
    .byte $00
D_0C08:
    .byte $00
D_0C09:
    .byte $00, $00
D_0C0B:
    .byte $00
D_0C0C:
    .byte $00, $00, $00, $00, $00, $00, $00
D_0C13:
    .byte $00
D_0C14:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $69, $6E, $20
    .byte $00, $4F, $6B, $0D, $0A, $00, $42, $72, $65, $61, $6B
FNDFOR:
    NOP
L_0C50:
    LD HL,$0004
    ADD HL,SP
L_0C54:
    LD A,[HL]
    INC HL
    CP $B4
    JP NZ,L_0C62
    LD BC,$0006
    ADD HL,BC
    JP L_0C54
L_0C62:
    CP $82
    RET NZ
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH HL
    LD H,B
    LD L,C
    LD A,D
    OR E
    EX DE,HL
    JP Z,L_0C76
    EX DE,HL
    CALL L_43CD
L_0C76:
    LD BC,$0010
    POP HL
    RET Z
    ADD HL,BC
    JP L_0C54
    .byte $01, $86, $0D, $C3, $FC, $0C
GOPRGD:
    LD HL,[CURLIN]
    LD A,H
    AND L
    INC A
    JP Z,L_0C97
    LD A,[ONEFLG]
    OR A
    LD E,$13
    JP NZ,ERROR
L_0C97:
    JP ENDCON
DERDFL:
    LD E,$3D
    .byte $01
DERDIO:
    LD E,$39
    .byte $01
DERBFM:
    LD E,$36
    .byte $01
DERFNF:
    LD E,$35
    .byte $01
DERBFN:
    LD E,$34
    .byte $01
DERIER:
    LD E,$33
    .byte $01
DERRPE:
    LD E,$3E
    .byte $01
DERFAO:
    LD E,$37
    .byte $01
DERIFN:
    LD E,$40
    .byte $01
DERBRN:
    LD E,$3F
    .byte $01
DERFOV:
    LD E,$32
    .byte $01
DERTMF:
    LD E,$43
    .byte $01
DERFAE:
    LD E,$3A
    JP ERROR
    .byte $2A, $A3, $0A, $22, $98, $07
SNERR:
    LD E,$02
    .byte $01
DV0ERR:
    LD E,$0B
    .byte $01
NFERR:
    LD E,$01
    .byte $01
DDERR:
    LD E,$0A
    .byte $01
UFERR:
    LD E,$12
    .byte $01
REERR:
    LD E,$14
    .byte $01
OVERR:
    LD E,$06
    .byte $01
MOERR:
    LD E,$16
    .byte $01
TMERR:
    LD E,$0D
ERROR:
    LD HL,[CURLIN]
    LD [ERRLIN],HL
    XOR A
    LD [D_0BED],A
    LD [D_0BF3],A
    LD A,H
    AND L
    INC A
    JP Z,L_0CF9
    LD [DOT],HL
L_0CF9:
    LD BC,$0D02
    LD HL,[SAVSTK]
    JP L_43A2
    .byte $C1, $7B, $4B, $32, $8A, $07, $2A, $AF, $0A, $22, $B7, $0A, $EB, $2A, $B3, $0A
    .byte $7C, $A5, $3C, $CA, $1F, $0D, $22, $BE, $0A, $EB, $22, $C0, $0A, $2A, $B9, $0A
    .byte $7C, $B5, $EB, $21, $BB, $0A, $CA, $34, $0D, $A6, $C2, $34, $0D, $35, $EB, $C3
    .byte $C0, $12, $AF, $77, $59, $32, $93, $07, $CD, $14, $42, $21, $B3, $04, $7B, $FE
    .byte $44, $D2, $50, $0D, $FE, $32, $D2, $52, $0D, $FE, $1F, $DA, $55, $0D
L_0D50:
    LD A,$28
    SUB $13
    LD E,A
L_0D55:
    CALL ST_REM
    INC HL
    DEC E
    JP NZ,L_0D55
    PUSH HL
    LD HL,[ERRLIN]
    EX [SP],HL
ERRFIN:
    LD A,[HL]
    CP $3F
    JP NZ,L_0D6F
    POP HL
    LD HL,$04B3
    JP L_0D50
L_0D6F:
    CALL L_4723
    POP HL
    LD DE,$FFFE
    CALL L_43CD
    CALL Z,L_4221
    JP Z,L_59BB
    LD A,H
    AND L
    INC A
    CALL NZ,L_3112
    .byte $3E
STPRDY:
    POP BC
READY:
    CALL L_4144
    XOR A
    LD [D_0793],A
    CALL L_534D
    CALL L_4214
    LD HL,$0C45
    .byte $CD
D_0D98:
    .byte $00, $00
    LD A,[D_078A]
    SUB $02
    CALL Z,L_3CD5
MAIN:
    LD HL,$FFFF
    LD [CURLIN],HL
    LD A,[AUTFLG]
    OR A
    JP Z,L_0DF9
    LD HL,[AUTLIN]
    PUSH HL
    CALL LINPRT
    POP DE
    PUSH DE
    CALL L_0EF8
    LD A,$2A
    JP C,L_0DC2
    LD A,$20
L_0DC2:
    CALL OUTDO
    CALL L_4B28
    POP DE
    JP NC,L_0DDA
    XOR A
    LD [AUTFLG],A
    JP READY
L_0DD3:
    XOR A
    LD [AUTFLG],A
    JP L_0DEF
L_0DDA:
    LD HL,[AUTINC]
    ADD HL,DE
    JP C,L_0DD3
    PUSH DE
    LD DE,$FFF9
    CALL L_43CD
    POP DE
    JP NC,L_0DD3
    LD [AUTLIN],HL
L_0DEF:
    LD A,[D_0962]
    OR A
    JP Z,MAIN
    JP L_3EE2
L_0DF9:
    CALL L_4B28
    JP C,MAIN
    CALL CHRGTR
    INC A
    DEC A
    JP Z,MAIN
    PUSH AF
    CALL L_1428
    CALL L_11AC
    LD A,[HL]
    CP $20
    CALL Z,L_28BE
L_0E14:
    PUSH DE
    CALL L_0F18
    POP DE
    POP AF
    LD [SAVTXT],HL
    JP NC,L_538A
    PUSH DE
    PUSH BC
    CALL L_5D65
    CALL CHRGTR
    OR A
    PUSH AF
    EX DE,HL
    LD [DOT],HL
    EX DE,HL
    CALL L_0EF8
    JP C,L_0E3B
    POP AF
    PUSH AF
    JP Z,L_14CC
    OR A
L_0E3B:
    PUSH BC
    PUSH AF
    PUSH HL
    CALL L_2435
    POP HL
    POP AF
    POP BC
    PUSH BC
    CALL C,L_22A2
    POP DE
    POP AF
    PUSH DE
    JP Z,L_0E87
    POP DE
    LD A,[D_0BF3]
    OR A
    JP NZ,L_0E5C
    LD HL,[MEMSIZ]
    LD [FRETOP],HL
L_0E5C:
    LD HL,[VARTAB]
    EX [SP],HL
    POP BC
    PUSH HL
    ADD HL,BC
    PUSH HL
    CALL L_42B6
    POP HL
    LD [VARTAB],HL
    EX DE,HL
    LD [HL],H
    POP BC
    POP DE
    PUSH HL
    INC HL
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD DE,$0823
    DEC BC
    DEC BC
    DEC BC
    DEC BC
L_0E7D:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
    LD A,C
    OR B
    JP NZ,L_0E7D
L_0E87:
    POP DE
    CALL L_0EAF
    LD HL,$0080
    LD [HL],$00
    LD [D_07A4],HL
    LD HL,[D_0794]
    LD [TEMP2],HL
    CALL L_4337
    LD HL,[D_07A2]
    LD [D_07A4],HL
    LD HL,[TEMP2]
    LD [D_0794],HL
    JP MAIN
L_0EAB:
    LD HL,[TXTTAB]
    EX DE,HL
L_0EAF:
    LD H,D
    LD L,E
    LD A,[HL]
    INC HL
    OR [HL]
    RET Z
    INC HL
    INC HL
L_0EB7:
    INC HL
    LD A,[HL]
L_0EB9:
    OR A
    JP Z,L_0ED0
    CP $20
    JP NC,L_0EB7
    CP $0B
    JP C,L_0EB7
    CALL CHRGT2
    CALL CHRGTR
    JP L_0EB9
L_0ED0:
    INC HL
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    JP L_0EAF
L_0ED8:
    LD DE,$0000
    PUSH DE
    JP Z,L_0EEB
    POP DE
    CALL L_141D
    PUSH DE
    JP Z,L_0EF4
    CALL L_43D3
    DI
L_0EEB:
    LD DE,$FFFA
    CALL NZ,L_141D
    JP NZ,SNERR
L_0EF4:
    EX DE,HL
    POP DE
L_0EF6:
    EX [SP],HL
    PUSH HL
L_0EF8:
    LD HL,[TXTTAB]
L_0EFB:
    LD B,H
    LD C,L
    LD A,[HL]
    INC HL
    OR [HL]
    DEC HL
    RET Z
    INC HL
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CALL L_43CD
    LD H,B
    LD L,C
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CCF
    RET Z
    CCF
    RET NC
    JP L_0EFB
L_0F18:
    XOR A
    LD [D_0A69],A
    LD [D_0A68],A
    LD BC,$013B
    LD DE,$0823
L_0F25:
    LD A,[HL]
    OR A
    JP NZ,L_0F3D
L_0F2A:
    LD HL,$0140
    LD A,L
    SUB C
    LD C,A
    LD A,H
    SBC A,B
    LD B,A
    LD HL,$0822
    XOR A
    LD [DE],A
    INC DE
    LD [DE],A
    INC DE
    LD [DE],A
    RET
L_0F3D:
    CP $22
    JP Z,L_0F79
    CP $20
    JP Z,L_0F4F
    LD A,[D_0A68]
    OR A
    LD A,[HL]
    JP Z,L_0F82
L_0F4F:
    INC HL
    PUSH AF
    CALL L_1159
    POP AF
    SUB $3A
    JP Z,L_0F61
    CP $4A
    JP NZ,L_0F67
    LD A,$01
L_0F61:
    LD [D_0A68],A
    LD [D_0A69],A
L_0F67:
    SUB $55
    JP NZ,L_0F25
    PUSH AF
L_0F6D:
    LD A,[HL]
    OR A
    EX [SP],HL
    LD A,H
    POP HL
    JP Z,L_0F2A
    CP [HL]
    JP Z,L_0F4F
L_0F79:
    PUSH AF
    LD A,[HL]
L_0F7B:
    INC HL
    CALL L_1159
    JP L_0F6D
L_0F82:
    CP $3F
    LD A,$91
    PUSH DE
    PUSH BC
    JP Z,L_1048
    LD DE,$046A
    CALL L_1C5A
    CALL L_4504
    JP C,L_1097
    PUSH HL
    LD DE,$0FCC
    CALL L_0FBE
    JP NZ,L_0FD6
    CALL CHRGTR
    LD DE,$0FD0
    CALL L_0FBE
    LD A,$89
    JP Z,L_0FB8
    LD DE,$0FD3
    CALL L_0FBE
    JP NZ,L_0FD6
L_0FB8:
    LD A,$8D
    POP BC
    JP L_1048
L_0FBE:
    LD A,[DE]
    OR A
    RET Z
    LD C,A
    CALL L_1C5A
    CP C
    RET NZ
    INC HL
    INC DE
    JP L_0FBE
    .byte $47, $4F, $20, $00, $54, $4F, $00, $55, $42, $00
L_0FD6:
    POP HL
    CALL L_1C5A
    PUSH HL
    LD HL,$0207
    SUB $41
    ADD A,A
    LD C,A
    LD B,$00
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    POP HL
    INC HL
L_0FEA:
    PUSH HL
L_0FEB:
    CALL L_1C5A
    LD C,A
    LD A,[DE]
    AND $7F
    JP Z,L_1164
    INC HL
    CP C
    JP NZ,L_103C
    LD A,[DE]
    INC DE
    OR A
    JP P,L_0FEB
    LD A,C
    CP $28
    JP Z,L_1021
    LD A,[DE]
    CP $D3
    JP Z,L_1021
    CP $D2
    JP Z,L_1021
    CALL L_1C5A
    CP $2E
    JP Z,L_101C
    CALL L_21E2
L_101C:
    LD A,$00
    JP NC,L_1164
L_1021:
    POP AF
    LD A,[DE]
    OR A
    JP M,L_1047
    POP BC
    POP DE
    OR $80
    PUSH AF
    LD A,$FF
    CALL L_1159
    XOR A
    LD [D_0A69],A
    POP AF
    CALL L_1159
    JP L_0F25
L_103C:
    POP HL
L_103D:
    LD A,[DE]
    INC DE
    OR A
    JP P,L_103D
    INC DE
    JP L_0FEA
L_1047:
    DEC HL
L_1048:
    PUSH AF
    LD DE,$105A
    LD C,A
L_104D:
    LD A,[DE]
    OR A
    JP Z,L_1069
    INC DE
    CP C
    JP NZ,L_104D
    JP L_106B
    .byte $8C, $AB, $AC, $AA, $A7, $A9, $D6, $A2, $8A, $93, $9F, $89, $CF, $8D, $00
L_1069:
    XOR A
    .byte $C2
L_106B:
    LD A,$01
L_106D:
    LD [D_0A69],A
    POP AF
    POP BC
    POP DE
    CP $A2
    PUSH AF
    CALL Z,L_1157
    POP AF
    CP $B4
    JP NZ,L_1084
    CALL L_1159
    LD A,$F2
L_1084:
    CP $DB
    JP NZ,L_1135
    PUSH AF
    CALL L_1157
    LD A,$8F
    CALL L_1159
    POP AF
    PUSH AF
    JP L_0F7B
L_1097:
    LD A,[HL]
    CP $2E
    JP Z,L_10A7
    CP $3A
    JP NC,L_1122
    CP $30
    JP C,L_1122
L_10A7:
    LD A,[D_0A69]
    OR A
    LD A,[HL]
    POP BC
    POP DE
    JP M,L_0F4F
    JP Z,L_10D3
    CP $2E
    JP Z,L_0F4F
    LD A,$0E
    CALL L_1159
    PUSH DE
    CALL L_1428
    CALL L_11AC
L_10C5:
    EX [SP],HL
    EX DE,HL
L_10C7:
    LD A,L
    CALL L_1159
    LD A,H
L_10CC:
    POP HL
    CALL L_1159
    JP L_0F25
L_10D3:
    PUSH DE
    PUSH BC
    LD A,[HL]
    CALL L_2ED1
    CALL L_11AC
    POP BC
    POP DE
    PUSH HL
    LD A,[D_0A67]
    CP $02
    JP NZ,L_10FF
    LD HL,[D_0C04]
    LD A,H
    OR A
    LD A,$02
    JP NZ,L_10FF
    LD A,L
    LD H,L
    LD L,$0F
    CP $0A
    JP NC,L_10C7
    ADD A,$11
    JP L_10CC
L_10FF:
    PUSH AF
    RRCA
    ADD A,$1B
    CALL L_1159
    LD HL,$0C04
    CALL L_1D64
    JP C,L_1112
    LD HL,$0C00
L_1112:
    POP AF
L_1113:
    PUSH AF
    LD A,[HL]
    CALL L_1159
    POP AF
    INC HL
    DEC A
    JP NZ,L_1113
    POP HL
    JP L_0F25
L_1122:
    LD DE,$0469
L_1125:
    INC DE
    LD A,[DE]
    AND $7F
    JP Z,L_118E
    INC DE
    CP [HL]
    LD A,[DE]
    JP NZ,L_1125
    JP L_11A0
L_1135:
    CP $26
    JP NZ,L_0F4F
    PUSH HL
    CALL CHRGTR
    POP HL
    CALL L_1C5B
    CP $48
    LD A,$0B
    JP NZ,L_114B
    LD A,$0C
L_114B:
    CALL L_1159
    PUSH DE
    PUSH BC
    CALL L_1C69
    POP BC
    JP L_10C5
L_1157:
    LD A,$3A
L_1159:
    LD [DE],A
    INC DE
    DEC BC
    LD A,C
    OR B
    RET NZ
L_115F:
    LD E,$17
    JP ERROR
L_1164:
    POP HL
    DEC HL
    DEC A
    LD [D_0A69],A
    POP BC
    POP DE
    CALL L_1C5A
L_116F:
    CALL L_1159
    INC HL
    CALL L_1C5A
    CALL L_4504
    JP NC,L_116F
    CP $3A
    JP NC,L_118B
    CP $30
    JP NC,L_116F
    CP $2E
    JP Z,L_116F
L_118B:
    JP L_0F25
L_118E:
    LD A,[HL]
    CP $20
    JP NC,L_11A0
    CP $09
    JP Z,L_11A0
    CP $0A
    JP Z,L_11A0
    LD A,$20
L_11A0:
    PUSH AF
    LD A,[D_0A69]
    INC A
    JP Z,L_11A9
    DEC A
L_11A9:
    JP L_106D
L_11AC:
    DEC HL
    LD A,[HL]
    CP $20
    JP Z,L_11AC
    CP $09
    JP Z,L_11AC
    CP $0A
    JP Z,L_11AC
    INC HL
    RET
ST_FOR:
    LD A,$64
    LD [SUBFLG],A
    CALL L_398B
    CALL L_43D3
    RET P
    PUSH DE
    EX DE,HL
    LD [TEMP],HL
    EX DE,HL
    LD A,[D_0A67]
    PUSH AF
    CALL L_1A02
    POP AF
    PUSH HL
    CALL L_1FAC
    LD HL,$0BC0
    CALL L_28C0
    POP HL
    POP DE
    POP BC
    PUSH HL
    CALL ST_DATA
    LD [ENDFOR],HL
    LD HL,$0002
    ADD HL,SP
L_11F1:
    CALL L_0C54
    JP NZ,L_1211
    ADD HL,BC
    PUSH DE
    DEC HL
    LD D,[HL]
    DEC HL
    LD E,[HL]
    INC HL
    INC HL
    PUSH HL
    LD HL,[ENDFOR]
    CALL L_43CD
    POP HL
    POP DE
    JP NZ,L_11F1
    POP DE
    LD SP,HL
    LD [SAVSTK],HL
    .byte $0E
L_1211:
    .byte $D1
    EX DE,HL
    LD C,$08
    CALL L_42C7
    PUSH HL
    LD HL,[ENDFOR]
    EX [SP],HL
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL
    CALL L_43D3
    ADC A,$CD
    LD H,H
    DEC E
    JP Z,TMERR
    JP NC,TMERR
    PUSH AF
    CALL L_1A02
    POP AF
    PUSH HL
    JP P,L_124E
    CALL FN_CINT
    EX [SP],HL
    LD DE,$0001
    LD A,[HL]
    CP $D1
    CALL Z,L_2053
    PUSH DE
    PUSH HL
    EX DE,HL
    CALL L_2892
    JP L_1271
L_124E:
    CALL FN_CSNG
    CALL L_28B4
    POP HL
    PUSH BC
    PUSH DE
    LD BC,$8100
    LD D,C
    LD E,D
    LD A,[HL]
    CP $D1
    LD A,$01
    JP NZ,L_1272
    CALL L_1A03
    PUSH HL
    CALL FN_CSNG
    CALL L_28B4
    CALL L_2845
L_1271:
    POP HL
L_1272:
    PUSH BC
    PUSH DE
    LD C,A
    CALL L_1D64
    LD B,A
    PUSH BC
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    CALL L_24E2
    CALL CHRGTR
    PUSH HL
    PUSH HL
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    LD HL,[TEMP]
    EX [SP],HL
    LD B,$82
    PUSH BC
    INC SP
    PUSH AF
    PUSH AF
    JP L_45A0
L_129C:
    LD B,$82
    PUSH BC
    INC SP
NEWSTT:
    PUSH HL
    .byte $CD
D_12A2:
    .byte $00, $00
    POP HL
    OR A
    CALL NZ,L_425C
    LD [SAVTXT],HL
    EX DE,HL
    LD HL,$0000
    ADD HL,SP
    LD [SAVSTK],HL
    EX DE,HL
    LD A,[HL]
    CP $3A
    JP Z,GONE
    OR A
    JP NZ,SNERR
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,GOPRGD
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL
    LD A,[TRCFLG]
    OR A
    JP Z,L_12E4
    PUSH DE
    LD A,$5B
    CALL OUTDO
    CALL LINPRT
    LD A,$5D
    CALL OUTDO
    POP DE
L_12E4:
    EX DE,HL
GONE:
    CALL CHRGTR
    LD DE,$12A0
    PUSH DE
    RET Z
L_12ED:
    SUB $81
    JP C,LET
    CP $4C
    JP NC,L_1FE2
    RLCA
    LD C,A
    LD B,$00
    EX DE,HL
    LD HL,$0107
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    EX DE,HL
CHRGTR:
    INC HL
CHRGT2:
    LD A,[HL]
    CP $3A
    RET NC
L_130A:
    CP $20
    JP Z,CHRGTR
    JP NC,L_1386
    OR A
    RET Z
    CP $0B
    JP C,L_1381
    CP $1E
    JP NZ,L_1323
    LD A,[D_0A6C]
    OR A
    RET
L_1323:
    CP $10
    JP Z,L_1360
    PUSH AF
    INC HL
    LD [D_0A6C],A
    SUB $1C
    JP NC,L_1366
    SUB $F5
    JP NC,L_133E
    CP $FE
    JP NZ,L_1352
    LD A,[HL]
    INC HL
L_133E:
    LD [D_0A6A],HL
    LD H,$00
L_1343:
    LD L,A
    LD [D_0A6E],HL
    LD A,$02
    LD [D_0A6D],A
    LD HL,$138C
    POP AF
    OR A
    RET
L_1352:
    LD A,[HL]
    INC HL
    INC HL
    LD [D_0A6A],HL
    DEC HL
    LD H,[HL]
    JP L_1343
L_135D:
    CALL L_138E
L_1360:
    LD HL,[D_0A6A]
    JP CHRGT2
L_1366:
    INC A
    RLCA
    LD [D_0A6D],A
    PUSH DE
    PUSH BC
    LD DE,$0A6E
    EX DE,HL
    LD B,A
    CALL L_28CD
    EX DE,HL
    POP BC
    POP DE
    LD [D_0A6A],HL
    POP AF
    LD HL,$138C
    OR A
    RET
L_1381:
    CP $09
    JP NC,CHRGTR
L_1386:
    CP $30
    CCF
    INC A
    DEC A
    RET
    .byte $1E, $10
L_138E:
    LD A,[D_0A6C]
    CP $0F
    JP NC,L_13AB
    CP $0D
    JP C,L_13AB
    LD HL,[D_0A6E]
    JP NZ,L_13A8
    INC HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
L_13A8:
    JP L_2C03
L_13AB:
    LD A,[D_0A6D]
    LD [D_0A67],A
    CP $08
    JP Z,L_13C3
    LD HL,[D_0A6E]
    LD [D_0C04],HL
    LD HL,[D_0A70]
    LD [D_0C06],HL
    RET
L_13C3:
    LD HL,$0A6E
    JP L_28EE
ST_DEFSTR:
    LD E,$03
    .byte $01
ST_DEFINT:
    LD E,$02
    .byte $01
ST_DEFSNG:
    LD E,$04
    .byte $01
ST_DEFDBL:
    LD E,$08
L_13D4:
    CALL L_4503
    LD BC,$0CC9
    PUSH BC
    RET C
    SUB $41
    LD C,A
    LD B,A
    CALL CHRGTR
    CP $F3
    JP NZ,L_13F5
    CALL CHRGTR
    CALL L_4503
    RET C
    SUB $41
    LD B,A
    CALL CHRGTR
L_13F5:
    LD A,B
    SUB C
    RET C
    INC A
    EX [SP],HL
    LD HL,$0ACA
    LD B,$00
    ADD HL,BC
L_1400:
    LD [HL],E
    INC HL
    DEC A
    JP NZ,L_1400
    POP HL
    LD A,[HL]
    CP $2C
    RET NZ
    CALL CHRGTR
    JP L_13D4
L_1411:
    CALL CHRGTR
L_1414:
    CALL L_2056
    RET P
L_1418:
    LD E,$05
    JP ERROR
L_141D:
    LD A,[HL]
    CP $2E
    EX DE,HL
    LD HL,[DOT]
    EX DE,HL
    JP Z,CHRGTR
L_1428:
    DEC HL
L_1429:
    CALL CHRGTR
    CP $0E
    JP Z,L_1433
    CP $0D
L_1433:
    EX DE,HL
    LD HL,[D_0A6E]
    EX DE,HL
    JP Z,CHRGTR
    XOR A
    LD [D_0A6C],A
    DEC HL
    LD DE,$0000
L_1443:
    CALL CHRGTR
    RET NC
    PUSH HL
    PUSH AF
    LD HL,$1998
    CALL L_43CD
    JP C,L_1464
    LD H,D
    LD L,E
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    POP AF
    SUB $30
    LD E,A
    LD D,$00
    ADD HL,DE
    EX DE,HL
    POP HL
    JP L_1443
L_1464:
    POP AF
    POP HL
    RET
ST_RUN:
    JP Z,L_4337
    CP $0E
    JP Z,L_1474
    CP $0D
    JP NZ,L_529A
L_1474:
    CALL L_433B
    LD BC,$12A0
    JP L_1494
ST_GOSUB:
    LD C,$03
    CALL L_42C7
    CALL L_1428
    POP BC
    PUSH HL
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL
    LD A,$8D
    PUSH AF
    INC SP
    PUSH BC
    JP L_1498
L_1494:
    PUSH BC
ST_GOTO:
    CALL L_1428
L_1498:
    LD A,[D_0A6C]
    CP $0D
    EX DE,HL
    RET Z
    CP $0E
    JP NZ,SNERR
    EX DE,HL
    PUSH HL
    LD HL,[D_0A6A]
    EX [SP],HL
    CALL ST_REM
    INC HL
    PUSH HL
    LD HL,[CURLIN]
    CALL L_43CD
    POP HL
    CALL C,L_0EFB
    CALL NC,L_0EF8
    JP NC,L_14CC
    DEC BC
    LD A,$0D
    LD [PTRFLG],A
    POP HL
    CALL L_242C
    LD H,B
    LD L,C
    RET
L_14CC:
    LD E,$08
    JP ERROR
ST_RETURN:
    RET NZ
    LD D,$FF
    CALL L_0C50
    LD SP,HL
    LD [SAVSTK],HL
    CP $8D
    LD E,$03
    JP NZ,ERROR
    POP HL
    LD [CURLIN],HL
    LD HL,$12A0
    EX [SP],HL
    LD A,$E1
ST_DATA:
    .byte $01, $3A
ST_REM:
    .byte $0E
    NOP
    LD B,$00
L_14F2:
    LD A,C
    LD C,B
    LD B,A
L_14F5:
    DEC HL
L_14F6:
    CALL CHRGTR
    OR A
    RET Z
    CP B
    RET Z
    INC HL
    CP $22
    JP Z,L_14F2
    INC A
    JP Z,L_14F6
    SUB $8C
    JP NZ,L_14F5
    CP B
    ADC A,D
    LD D,A
    JP L_14F5
    .byte $F1, $C6, $03, $C3, $2D, $15
LET:
    CALL L_398B
    CALL L_43D3
    RET P
    EX DE,HL
    LD [TEMP],HL
    EX DE,HL
    PUSH DE
    LD A,[D_0A67]
    PUSH AF
    CALL L_1A02
    POP AF
L_152D:
    EX [SP],HL
L_152E:
    LD B,A
    LD A,[D_0A67]
    CP B
    LD A,B
    JP Z,L_153D
    CALL L_1FAC
L_153A:
    LD A,[D_0A67]
L_153D:
    LD DE,$0C04
    CP $05
    JP C,L_1548
    LD DE,$0C00
L_1548:
    PUSH HL
    CP $03
    JP NZ,L_157F
    LD HL,[D_0C04]
    PUSH HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_1573
    LD HL,[STREND]
    CALL L_43CD
    POP DE
    JP NC,L_157B
    LD HL,$0A98
    CALL L_43CD
    JP NC,L_157B
    .byte $3E
L_1573:
    .byte $D1
    CALL L_48C6
    EX DE,HL
    CALL L_46A3
L_157B:
    CALL L_48C6
    EX [SP],HL
L_157F:
    CALL L_28C9
    POP DE
    POP HL
    RET
ST_ON:
    CP $A8
    JP NZ,L_15B5
    CALL CHRGTR
    CALL L_43D3
    ADC A,C
    CALL L_1428
    LD A,D
    OR E
    JP Z,L_15A2
    CALL L_0EF6
    LD D,B
    LD E,C
    POP HL
    JP NC,L_14CC
L_15A2:
    EX DE,HL
    LD [ONELIN],HL
    EX DE,HL
    RET C
    LD A,[ONEFLG]
    OR A
    LD A,E
    RET Z
    LD A,[D_078A]
    LD E,A
    JP L_0CF9
L_15B5:
    CALL L_2075
    LD A,[HL]
    LD B,A
    CP $8D
    JP Z,L_15C4
    CALL L_43D3
    ADC A,C
    DEC HL
L_15C4:
    LD C,E
L_15C5:
    DEC C
    LD A,B
    JP Z,L_12ED
    CALL L_1429
    CP $2C
    RET NZ
    JP L_15C5
ST_RESUME:
    LD DE,$0ABB
    LD A,[DE]
    OR A
    JP Z,REERR
    INC A
    LD [D_078A],A
    LD [DE],A
    LD A,[HL]
    CP $83
    JP Z,L_15F3
    CALL L_1428
    RET NZ
    LD A,D
    OR E
    JP NZ,L_1498
    INC A
    JP L_15F7
L_15F3:
    CALL CHRGTR
    RET NZ
L_15F7:
    LD HL,[ERRTXT]
    EX DE,HL
    LD HL,[ERRLIN]
    LD [CURLIN],HL
    EX DE,HL
    RET NZ
    LD A,[HL]
    OR A
    JP NZ,L_160C
    INC HL
    INC HL
    INC HL
    INC HL
L_160C:
    INC HL
    JP ST_DATA
ST_ERROR:
    CALL L_2075
    RET NZ
    OR A
    JP Z,L_1418
    JP ERROR
ST_AUTO:
    LD DE,$000A
    PUSH DE
    JP Z,L_163D
    CALL L_141D
    EX DE,HL
    EX [SP],HL
    JP Z,L_163E
    EX DE,HL
    CALL L_43D3
    INC L
    EX DE,HL
    LD HL,[AUTINC]
    EX DE,HL
    JP Z,L_163D
    CALL L_1428
    JP NZ,SNERR
L_163D:
    EX DE,HL
L_163E:
    LD A,H
    OR L
    JP Z,L_1418
    LD [AUTINC],HL
    LD [AUTFLG],A
    POP HL
    LD [AUTLIN],HL
    POP BC
    JP MAIN
ST_IF:
    CALL L_1A02
    LD A,[HL]
    CP $2C
    CALL Z,CHRGTR
    CP $89
    JP Z,L_1664
    CALL L_43D3
    RST $08
    DEC HL
L_1664:
    PUSH HL
    CALL L_2886
    POP HL
    JP Z,L_167E
L_166C:
    CALL CHRGTR
    RET Z
    CP $0E
    JP Z,ST_GOTO
    CP $0D
    JP NZ,L_12ED
    LD HL,[D_0A6E]
    RET
L_167E:
    LD D,$01
L_1680:
    CALL ST_DATA
    OR A
    RET Z
    CALL CHRGTR
    CP $A2
    JP NZ,L_1680
    DEC D
    JP NZ,L_1680
    JP L_166C
ST_LPRINT:
    LD A,$01
    LD [D_078D],A
    JP L_16A1
ST_PRINT:
    LD C,$02
    CALL L_510D
L_16A1:
    DEC HL
    CALL CHRGTR
    CALL Z,L_4221
L_16A8:
    JP Z,L_17E9
    CP $D9
    JP Z,L_3EF7
    CP $D0
    JP Z,L_1765
    CP $D4
    JP Z,L_1765
    PUSH HL
    CP $2C
    JP Z,L_1725
    CP $3B
    JP Z,L_17E2
    POP BC
    CALL L_1A02
    PUSH HL
    CALL L_1D64
    JP Z,L_16DC
    CALL L_3129
    CALL L_46C7
    LD [HL],$20
    LD HL,[D_0C04]
    INC [HL]
L_16DC:
    CALL L_4654
    JP NZ,L_171E
    LD HL,[D_0C04]
    LD A,[D_078D]
    OR A
    JP Z,L_1705
    LD A,[D_078F]
    LD B,A
    INC A
    JP Z,L_171E
    LD A,[D_078C]
    OR A
    JP Z,L_171E
    ADD A,[HL]
    CCF
    JP NC,L_171B
    DEC A
    CP B
    JP L_171B
L_1705:
    LD A,[D_0790]
    LD B,A
    INC A
    JP Z,L_171E
    LD A,[D_0A65]
    OR A
    JP Z,L_171E
    ADD A,[HL]
    CCF
    JP NC,L_171B
    DEC A
    CP B
L_171B:
    CALL NC,L_4221
L_171E:
    CALL L_4726
    POP HL
    JP L_16A1
L_1725:
    LD BC,$0028
    LD HL,[D_0794]
    ADD HL,BC
    CALL L_4654
    LD A,[HL]
    JP NZ,L_175C
    LD A,[D_078D]
    OR A
    JP Z,L_1749
    LD A,[D_078E]
    LD B,A
    INC A
    LD A,[D_078C]
    JP Z,L_175C
    CP B
    JP L_1756
L_1749:
    LD A,[D_0791]
    LD B,A
    LD A,[D_0A65]
    CP $FF
    JP Z,L_175C
    CP B
L_1756:
    CALL NC,L_4221
    JP NC,L_17E2
L_175C:
    SUB $0E
    JP NC,L_175C
    CPL
    JP L_17D7
L_1765:
    PUSH AF
    CALL CHRGTR
    CALL L_2056
    POP AF
    PUSH AF
    CP $D4
    JP Z,L_1774
    DEC DE
L_1774:
    LD A,D
    OR A
    JP P,L_177C
    LD DE,$0000
L_177C:
    PUSH HL
    CALL L_4654
    JP NZ,L_179B
    LD A,[D_078D]
    OR A
    LD A,[D_078F]
    JP NZ,L_1790
    LD A,[D_0790]
L_1790:
    LD L,A
    INC A
    JP Z,L_179B
    LD H,$00
    CALL L_2C0D
    EX DE,HL
L_179B:
    POP HL
    CALL L_43D3
    ADD HL,HL
    DEC HL
    POP AF
    SUB $D4
    PUSH HL
    JP Z,L_17C6
    LD BC,$0028
    LD HL,[D_0794]
    ADD HL,BC
    CALL L_4654
    LD A,[HL]
    JP NZ,L_17C6
    LD A,[D_078D]
    OR A
    JP Z,L_17C3
    LD A,[D_078C]
    JP L_17C6
L_17C3:
    LD A,[D_0A65]
L_17C6:
    CPL
    ADD A,E
    JP C,L_17D7
    INC A
    JP Z,L_17E2
    CALL L_4221
    LD A,E
    DEC A
    JP M,L_17E2
L_17D7:
    INC A
    LD B,A
    LD A,$20
L_17DB:
    CALL OUTDO
    DEC B
    JP NZ,L_17DB
L_17E2:
    POP HL
    CALL CHRGTR
    JP L_16A8
L_17E9:
    XOR A
    LD [D_078D],A
    PUSH HL
    LD H,A
    LD L,A
    LD [D_0794],HL
    POP HL
    RET
ST_LINE:
    CALL L_43D3
    ADD A,L
    CP $23
    JP Z,L_51A7
    CALL L_4C48
    CALL L_186F
    CALL L_398B
    CALL L_2A3B
    PUSH DE
    PUSH HL
    CALL L_4B30
    POP DE
    POP BC
    JP C,L_4416
    PUSH BC
    PUSH DE
    LD B,$00
    CALL L_46CA
    POP HL
    LD A,$03
    JP L_152D
    .byte $3F, $52, $65, $64, $6F, $20, $66, $72, $6F, $6D, $20, $73, $74, $61, $72, $74
    .byte $0D, $0A, $00, $23, $7E, $B7, $CA, $C9, $0C, $FE, $22, $C2, $34, $18, $C3, $DA
    .byte $18, $E1, $E1, $C3, $4E, $18, $3A, $A6, $0A, $B7, $C2, $C3, $0C, $C1, $21, $21
    .byte $18, $CD, $23, $47, $2A, $AF, $0A, $C9
L_1859:
    CALL L_510B
    PUSH HL
    LD HL,$0961
    JP L_193B
ST_INPUT:
    CP $23
    JP Z,L_1859
    CALL L_4C48
    LD BC,$1899
    PUSH BC
L_186F:
    CP $22
    LD A,$00
    LD [D_0793],A
    LD A,$FF
    LD [D_0BE7],A
    RET NZ
    CALL L_46C8
    LD A,[HL]
    CP $2C
    JP NZ,L_188F
    XOR A
    LD [D_0BE7],A
    CALL CHRGTR
    JP L_1893
L_188F:
    CALL L_43D3
    DEC SP
L_1893:
    PUSH HL
    CALL L_4726
    POP HL
    RET
    .byte $E5, $3A, $E7, $0B, $B7, $CA, $AB, $18, $3E, $3F, $CD, $D6, $40, $3E, $20, $CD
    .byte $D6, $40, $CD, $30, $4B, $C1, $DA, $16, $44, $C5, $AF, $32, $A6, $0A, $36, $2C
    .byte $EB, $E1, $E5, $D5, $D5, $2B, $3E, $80, $32, $A5, $0A, $CD, $05, $13, $CD, $89
    .byte $3A, $7E, $2B, $FE, $5B, $CA, $D6, $18, $FE, $28, $C2, $FD, $18, $23, $06, $00
    .byte $04, $CD, $05, $13, $CA, $C9, $0C, $FE, $22, $CA, $34, $18, $FE, $28, $CA, $D9
    .byte $18, $FE, $5B, $CA, $DA, $18, $FE, $5D, $CA, $F9, $18, $FE, $29, $C2, $DA, $18
    .byte $05, $C2, $DA, $18, $CD, $05, $13, $CA, $08, $19, $FE, $2C, $C2, $C9, $0C, $E3
    .byte $7E, $FE, $2C, $C2, $42, $18, $3E, $01, $32, $0A, $0C, $CD, $64, $19, $3A, $0A
    .byte $0C, $3D, $C2, $42, $18, $E5, $CD, $64, $1D, $CC, $A8, $48, $E1, $2B, $CD, $05
    .byte $13, $E3, $7E, $FE, $2C, $CA, $BF, $18, $E1, $2B, $CD, $05, $13, $B7, $E1, $C2
    .byte $4E, $18
L_193B:
    LD [HL],$2C
    JP L_1945
ST_READ:
    PUSH HL
    LD HL,[DATPTR]
    .byte $F6
L_1945:
    .byte $AF
    LD [FLGINP],A
    EX [SP],HL
    JP L_1951
    .byte $CD, $D3, $43, $2C
L_1951:
    CALL L_398B
    EX [SP],HL
    PUSH DE
    LD A,[HL]
    CP $2C
    JP Z,L_1963
    LD A,[FLGINP]
    OR A
    JP NZ,L_19D3
L_1963:
    OR $AF
    LD [D_0BBC],A
    CALL L_4654
    JP NZ,L_5197
    CALL L_1D64
    PUSH AF
    JP NZ,L_19A2
    CALL CHRGTR
    LD D,A
    LD B,A
    CP $22
    JP Z,L_198C
    LD A,[FLGINP]
    OR A
    LD D,A
    JP Z,L_1989
    LD D,$3A
L_1989:
    LD B,$2C
    DEC HL
L_198C:
    CALL L_46CB
    POP AF
    ADD A,$03
    LD C,A
    LD A,[D_0BBC]
    OR A
    RET Z
    LD A,C
    EX DE,HL
    LD HL,$19B1
    EX [SP],HL
    PUSH DE
    JP L_152E
L_19A2:
    CALL CHRGTR
    POP AF
    PUSH AF
    LD BC,$198F
    PUSH BC
    JP C,L_2ED1
    JP L_2ECA
    .byte $2B, $CD, $05, $13, $CA, $BD, $19, $FE, $2C, $C2, $47, $18, $E3, $2B, $CD, $05
    .byte $13, $C2, $4D, $19, $D1, $3A, $A6, $0A, $B7, $EB, $C2, $FC, $43, $D5, $E1, $C3
    .byte $E9, $17
L_19D3:
    CALL ST_DATA
    OR A
    JP NZ,L_19EC
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    LD E,$04
    JP Z,ERROR
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [DATLIN],HL
    EX DE,HL
L_19EC:
    CALL CHRGTR
    CP $84
    JP NZ,L_19D3
    JP L_1963
L_19F7:
    CALL L_43D3
    RET P
    JP L_1A02
L_19FE:
    CALL L_43D3
    .byte $28
L_1A02:
    .byte $2B
L_1A03:
    LD D,$00
L_1A05:
    PUSH DE
    LD C,$01
    CALL L_42C7
    CALL L_1B93
    XOR A
    LD [D_0C09],A
    LD [TEMP2],HL
L_1A15:
    LD HL,[TEMP2]
    POP BC
    LD A,[HL]
    LD [TEMP3],HL
    CP $EF
    RET C
    CP $F2
    JP C,L_1A8E
    SUB $F2
    LD E,A
    JP NZ,L_1A34
    LD A,[D_0A67]
L_1A2E:
    CP $03
    LD A,E
    JP Z,L_485B
L_1A34:
    CP $0C
    RET NC
    LD HL,$047F
    LD D,$00
    ADD HL,DE
    LD A,B
    LD D,[HL]
    CP D
    RET NC
    PUSH BC
    LD BC,$1A15
    PUSH BC
    LD A,D
    CP $7F
    JP Z,L_1AAC
    CP $51
    JP C,L_1ABA
    AND $FE
    CP $7A
    JP Z,L_1ABA
L_1A58:
    LD HL,$0C04
    LD A,[D_0A67]
    SUB $03
    JP Z,TMERR
    OR A
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    JP M,L_1A7F
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    JP PO,L_1A7F
    LD HL,$0C00
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
L_1A7F:
    ADD A,$03
    LD C,E
    LD B,A
    PUSH BC
    LD BC,$1AE3
L_1A87:
    PUSH BC
    LD HL,[TEMP3]
    JP L_1A05
L_1A8E:
    LD D,$00
L_1A90:
    SUB $EF
    JP C,L_1AC6
    CP $03
    JP NC,L_1AC6
    CP $01
    RLA
    XOR D
    CP D
    LD D,A
    JP C,SNERR
    LD [TEMP3],HL
    CALL CHRGTR
    JP L_1A90
L_1AAC:
    CALL FN_CSNG
    CALL L_2899
    LD BC,$36CC
    LD D,$7F
    JP L_1A87
L_1ABA:
    PUSH DE
    CALL FN_CINT
    POP DE
    PUSH HL
    LD BC,$1D75
    JP L_1A87
L_1AC6:
    LD A,B
    CP $64
    RET NC
    PUSH BC
    PUSH DE
    LD DE,$6404
    LD HL,$1D42
    PUSH HL
    CALL L_1D64
    JP NZ,L_1A58
    LD HL,[D_0C04]
    PUSH HL
    LD BC,$465C
    JP L_1A87
    .byte $C1, $79, $32, $68, $0A, $3A, $67, $0A, $B8, $C2, $FC, $1A, $FE, $02, $CA, $18
    .byte $1B, $FE, $04, $CA, $67, $1B, $D2, $2B, $1B, $57, $78, $FE, $08, $CA, $28, $1B
    .byte $7A, $FE, $08, $CA, $4F, $1B, $78, $FE, $04, $CA, $64, $1B, $7A, $FE, $03, $CA
    .byte $E1, $0C, $D2, $6F, $1B, $21, $A9, $04, $06, $00, $09, $09, $4E, $23, $46, $D1
    .byte $2A, $04, $0C, $C5, $C9, $CD, $20, $2A, $CD, $F4, $28, $E1, $22, $02, $0C, $E1
    .byte $22, $00, $0C, $C1, $D1, $CD, $A9, $28, $CD, $20, $2A, $21, $95, $04, $3A, $68
    .byte $0A, $07, $85, $6F, $8C, $95, $67, $7E, $23, $66, $6F, $E9, $78, $F5, $CD, $F4
    .byte $28, $F1, $32, $67, $0A, $FE, $04, $CA, $36, $1B, $E1, $22, $04, $0C, $C3, $3B
    .byte $1B, $CD, $F4, $29, $C1, $D1, $21, $9F, $04, $C3, $41, $1B, $E1, $CD, $99, $28
    .byte $CD, $14, $2A, $CD, $B4, $28, $E1, $22, $06, $0C, $E1, $22, $04, $0C, $C3, $69
    .byte $1B, $E5, $EB, $CD, $14, $2A, $E1, $CD, $99, $28, $CD, $14, $2A, $C3, $67, $27
L_1B93:
    CALL CHRGTR
    JP Z,MOERR
    JP C,L_2ED1
    CALL L_4504
    JP NC,L_1C4A
    CP $20
    JP C,L_135D
    INC A
    JP Z,ISFUN
    DEC A
    CP $F2
    JP Z,L_1B93
    CP $F3
    JP Z,L_1C3C
    CP $22
    JP Z,L_46C8
    CP $D5
    JP Z,L_1D4F
    CP $26
    JP Z,L_1C69
    CP $D7
    JP NZ,L_1BD6
    CALL CHRGTR
    LD A,[D_078A]
    PUSH HL
    CALL L_1DD5
    POP HL
    RET
L_1BD6:
    CP $D6
    JP NZ,L_1BE7
    CALL CHRGTR
    PUSH HL
    LD HL,[ERRLIN]
    CALL L_2C03
    POP HL
    RET
L_1BE7:
    CP $DC
    JP NZ,L_1C16
    CALL CHRGTR
    CALL L_43D3
L_1BF2:
    JR Z,L_1BF2
    INC HL
    JP NZ,L_1C03
    CALL L_2072
    PUSH HL
    CALL L_5150
    POP HL
    JP L_1C06
L_1C03:
    CALL L_3A89
L_1C06:
    CALL L_43D3
    ADD HL,HL
    PUSH HL
    EX DE,HL
    LD A,H
    OR L
    JP Z,L_1418
    CALL L_29DC
    POP HL
    RET
L_1C16:
    CP $D2
    JP Z,L_1DDB
    CP $DA
    JP Z,L_49CB
    CP $DD
    JP Z,L_426F
    CP $D8
    JP Z,L_4900
    CP $85
    JP Z,L_5527
    CP $D3
    JP Z,L_1E54
L_1C34:
    CALL L_19FE
    CALL L_43D3
    ADD HL,HL
    RET
L_1C3C:
    LD D,$7D
    CALL L_1A05
    LD HL,[TEMP2]
    PUSH HL
    CALL L_286B
    POP HL
    RET
L_1C4A:
    CALL L_398B
    PUSH HL
    EX DE,HL
    LD [D_0C04],HL
    CALL L_1D64
    CALL NZ,L_28EE
    POP HL
    RET
L_1C5A:
    LD A,[HL]
L_1C5B:
    CP $61
    RET C
    CP $7B
    RET NC
    AND $5F
    RET
    .byte $FE, $26, $C2, $28, $14
L_1C69:
    LD DE,$0000
    CALL CHRGTR
    CALL L_1C5B
    CP $4F
    JP Z,L_1CAD
    CP $48
    JP NZ,L_1CAC
    LD B,$05
L_1C7E:
    INC HL
    LD A,[HL]
    CALL L_1C5B
    CALL L_4504
    EX DE,HL
    JP NC,L_1C97
    CP $3A
    JP NC,L_1CCE
    SUB $30
    JP C,L_1CCE
    JP L_1C9E
L_1C97:
    CP $47
    JP NC,L_1CCE
    SUB $37
L_1C9E:
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    OR L
    LD L,A
    EX DE,HL
    DEC B
    JP NZ,L_1C7E
    JP OVERR
L_1CAC:
    DEC HL
L_1CAD:
    CALL CHRGTR
    EX DE,HL
    JP NC,L_1CCE
    CP $38
    JP NC,SNERR
    LD BC,$0CDB
    PUSH BC
    ADD HL,HL
    RET C
    ADD HL,HL
    RET C
    ADD HL,HL
    RET C
    POP BC
    LD B,$00
    SUB $30
    LD C,A
    ADD HL,BC
    EX DE,HL
    JP L_1CAD
L_1CCE:
    CALL L_29DC
    EX DE,HL
    RET
ISFUN:
    INC HL
    LD A,[HL]
    SUB $81
    CP $07
    JP NZ,L_1CE8
    PUSH HL
    CALL CHRGTR
    CP $28
    POP HL
    JP NZ,L_37CC
    LD A,$07
L_1CE8:
    LD B,$00
    RLCA
    LD C,A
    PUSH BC
    CALL CHRGTR
    LD A,C
    CP $05
    JP NC,L_1D0F
    CALL L_19FE
    CALL L_43D3
    INC L
    CALL L_2A3B
    EX DE,HL
    LD HL,[D_0C04]
    EX [SP],HL
    PUSH HL
    EX DE,HL
    CALL L_2075
    EX DE,HL
    EX [SP],HL
    JP L_1D29
L_1D0F:
    CALL L_1C34
    EX [SP],HL
    LD A,L
    CP $0C
    JP C,L_1D20
    CP $1B
    PUSH HL
    CALL C,FN_CSNG
    POP HL
L_1D20:
    LD DE,$1C48
    PUSH DE
    LD A,$01
    LD [D_0C09],A
L_1D29:
    LD BC,$019F
L_1D2C:
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD H,[HL]
    LD L,C
    JP [HL]
L_1D32:
    DEC D
    CP $F3
    RET Z
    CP $2D
    RET Z
    INC D
    CP $2B
    RET Z
    CP $F2
    RET Z
    DEC HL
    RET
    .byte $3C, $8F, $C1, $A0, $C6, $FF, $9F, $CD, $7F, $28, $C3, $61, $1D
L_1D4F:
    LD D,$5A
    CALL L_1A05
    CALL FN_CINT
    LD A,L
    CPL
    LD L,A
    LD A,H
    CPL
    LD H,A
    LD [D_0C04],HL
    POP BC
    JP L_1A15
L_1D64:
    LD A,[D_0A67]
    CP $08
    JP NC,L_1D71
    SUB $03
    OR A
    SCF
    RET
L_1D71:
    SUB $03
    OR A
    RET
    .byte $78, $F5, $CD, $7A, $29, $F1, $D1, $FE, $7A, $CA, $0D, $2C, $FE, $7B, $CA, $A8
    .byte $2B, $01, $D7, $1D, $C5, $FE, $46, $C2, $95, $1D, $7B, $B5, $6F, $7C, $B2, $C9
    .byte $FE, $50, $C2, $A0, $1D, $7B, $A5, $6F, $7C, $A2, $C9, $FE, $3C, $C2, $AB, $1D
    .byte $7B, $AD, $6F, $7C, $AA, $C9, $FE, $32, $C2, $B8, $1D, $7B, $AD, $2F, $6F, $7C
    .byte $AA, $2F, $C9, $7D, $2F, $A3, $2F, $6F, $7C, $2F, $A2, $2F, $C9
L_1DC2:
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP L_2C03
FN_LPOS:
    LD A,[D_078C]
    JP L_1DD4
FN_POS:
    LD A,[D_0A65]
L_1DD4:
    INC A
L_1DD5:
    LD L,A
    XOR A
L_1DD7:
    LD H,A
    JP L_29DC
L_1DDB:
    CALL L_1DFA
    PUSH DE
    CALL L_1C34
    EX [SP],HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,$2757
    PUSH HL
    PUSH DE
    LD A,[D_0A67]
    PUSH AF
    CP $03
    CALL Z,L_48A8
    POP AF
    EX DE,HL
    LD HL,$0C04
    RET
L_1DFA:
    CALL CHRGTR
    LD BC,$0000
    CP $1B
    JP NC,L_1E13
    CP $11
    JP C,L_1E13
    CALL CHRGTR
    LD A,[D_0A6E]
    OR A
    RLA
    LD C,A
L_1E13:
    EX DE,HL
    LD HL,$0774
    ADD HL,BC
    EX DE,HL
    RET
L_1E1A:
    CALL L_1DFA
    PUSH DE
    CALL L_43D3
    RET P
    CALL L_22D1
    EX [SP],HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    RET
ST_DEF:
    CP $D2
L_1E2D:
    JP Z,L_1E1A
    CALL L_1FD4
    CALL L_1FC6
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    EX DE,HL
    LD A,[HL]
    CP $28
    JP NZ,ST_DATA
    CALL CHRGTR
L_1E44:
    CALL L_398B
    LD A,[HL]
    CP $29
    JP Z,ST_DATA
    CALL L_43D3
    INC L
    JP L_1E44
L_1E54:
    CALL L_1FD4
    LD A,[D_0A67]
    OR A
    PUSH AF
    LD [TEMP2],HL
    EX DE,HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD A,H
    OR L
    JP Z,UFERR
    LD A,[HL]
    CP $28
    JP NZ,L_1F1E
    CALL CHRGTR
    LD [TEMP3],HL
    EX DE,HL
    LD HL,[TEMP2]
    CALL L_43D3
    JR Z,L_1E2D
    PUSH AF
    PUSH HL
    EX DE,HL
L_1E81:
    LD A,$80
    LD [SUBFLG],A
    CALL L_398B
    EX DE,HL
    EX [SP],HL
    LD A,[D_0A67]
    PUSH AF
    PUSH DE
    CALL L_1A02
    LD [TEMP2],HL
    POP HL
    LD [TEMP3],HL
    POP AF
    CALL L_1FAC
    LD C,$04
    CALL L_42C7
    LD HL,$FFF8
    ADD HL,SP
    LD SP,HL
    CALL L_28F7
    LD A,[D_0A67]
    PUSH AF
    LD HL,[TEMP2]
    LD A,[HL]
    CP $29
    JP Z,L_1ECB
    CALL L_43D3
    INC L
    PUSH HL
    LD HL,[TEMP3]
    CALL L_43D3
    INC L
    JP L_1E81
    .byte $F1, $32, $4E, $0B
L_1ECB:
    POP AF
    OR A
    JP Z,L_1F0F
    LD [D_0A67],A
    LD HL,$0000
    ADD HL,SP
    CALL L_28EE
    LD HL,$0008
    ADD HL,SP
    LD SP,HL
    POP DE
    LD L,$03
L_1EE2:
    INC L
    DEC DE
    LD A,[DE]
    OR A
    JP M,L_1EE2
    DEC DE
    DEC DE
    DEC DE
    LD A,[D_0A67]
    ADD A,L
    LD B,A
    LD A,[D_0B4E]
    LD C,A
    ADD A,B
    CP $64
    JP NC,L_1418
    PUSH AF
    LD A,L
    LD B,$00
    LD HL,$0B50
    ADD HL,BC
    LD C,A
    CALL L_1FC0
    LD BC,$1EC7
    PUSH BC
    PUSH BC
    JP L_153A
L_1F0F:
    LD HL,[TEMP2]
    CALL CHRGTR
    PUSH HL
    LD HL,[TEMP3]
    CALL L_43D3
    ADD HL,HL
    .byte $3E
L_1F1E:
    .byte $D5
    LD [TEMP3],HL
    LD A,[D_0AE6]
    ADD A,$04
    PUSH AF
    RRCA
    LD C,A
    CALL L_42C7
    POP AF
    LD C,A
    CPL
    INC A
    LD L,A
    LD H,$FF
    ADD HL,SP
    LD SP,HL
    PUSH HL
    LD DE,$0AE4
    CALL L_1FC0
    POP HL
    LD [D_0AE4],HL
    LD HL,[D_0B4E]
    LD [D_0AE6],HL
    LD B,H
    LD C,L
    LD HL,$0AE8
    LD DE,$0B50
    CALL L_1FC0
    LD H,A
    LD L,A
    LD [D_0B4E],HL
    LD HL,[D_0BBA]
    INC HL
    LD [D_0BBA],HL
    LD A,H
    OR L
    LD [D_0BB7],A
    LD HL,[TEMP3]
    CALL L_19F7
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    CALL L_1D64
    JP NZ,L_1F88
    LD DE,$0A98
    LD HL,[D_0C04]
    CALL L_43CD
    JP C,L_1F88
    CALL L_46A3
    CALL L_4701
L_1F88:
    LD HL,[D_0AE4]
    LD D,H
    LD E,L
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC BC
    INC BC
    INC BC
    INC BC
    LD HL,$0AE4
    CALL L_1FC0
    EX DE,HL
    LD SP,HL
    LD HL,[D_0BBA]
    DEC HL
    LD [D_0BBA],HL
    LD A,H
    OR L
    LD [D_0BB7],A
    POP HL
    POP AF
L_1FAC:
    PUSH HL
    AND $07
    LD HL,$048B
    LD C,A
    LD B,$00
    ADD HL,BC
    CALL L_1D2C
    POP HL
    RET
L_1FBB:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
L_1FC0:
    LD A,B
    OR C
    JP NZ,L_1FBB
    RET
L_1FC6:
    PUSH HL
    LD HL,[CURLIN]
    INC HL
    LD A,H
    OR L
    POP HL
    RET NZ
    LD E,$0C
    JP ERROR
L_1FD4:
    CALL L_43D3
    OUT [$3E],A
    ADD A,B
    LD [SUBFLG],A
    OR [HL]
    LD C,A
    JP L_3990
L_1FE2:
    CP $7E
    JP NZ,SNERR
    INC HL
    LD A,[HL]
    INC HL
    CP $83
    JP Z,L_4A60
    JP SNERR
FN_INP:
    CALL L_2078
    LD [D_1FF9],A
    .byte $DB
D_1FF9:
    .byte $00
    JP L_1DD5
ST_OUT:
    CALL L_2062
    .byte $D3
D_2001:
    .byte $00
    RET
ST_WAIT:
    CALL L_2062
    PUSH AF
    LD E,$00
    DEC HL
    CALL CHRGTR
    JP Z,L_2017
    CALL L_43D3
    INC L
    CALL L_2075
L_2017:
    POP AF
    LD D,A
L_2019:
    .byte $DB
D_201A:
    .byte $00
    XOR E
    AND D
    JP Z,L_2019
    RET
    .byte $C3, $C9, $0C
ST_WIDTH:
    CP $9E
    JP NZ,L_203A
    CALL CHRGTR
    CALL L_2075
    LD [D_078F],A
    LD E,A
    CALL L_2048
    LD [D_078E],A
    RET
L_203A:
    CALL L_2075
    LD [D_0790],A
    LD E,A
    CALL L_2048
    LD [D_0791],A
    RET
L_2048:
    SUB $0E
    JP NC,L_2048
    ADD A,$1C
    CPL
    INC A
    ADD A,E
    RET
L_2053:
    CALL CHRGTR
L_2056:
    CALL L_1A02
L_2059:
    PUSH HL
    CALL FN_CINT
    EX DE,HL
    POP HL
    LD A,D
    OR A
    RET
L_2062:
    CALL L_2075
    LD [D_201A],A
    LD [D_2001],A
    CALL L_43D3
    INC L
    JP L_2075
L_2072:
    CALL CHRGTR
L_2075:
    CALL L_1A02
L_2078:
    CALL L_2059
    JP NZ,L_1418
    DEC HL
    CALL CHRGTR
    LD A,E
    RET
ST_LLIST:
    LD A,$01
    LD [D_078D],A
ST_LIST:
    POP BC
    CALL L_0ED8
    PUSH BC
    CALL L_5D65
L_2091:
    LD HL,$FFFF
    LD [CURLIN],HL
    POP HL
    POP DE
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    LD A,B
    OR C
    JP Z,READY
    CALL L_4654
    CALL Z,L_4251
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    EX [SP],HL
    EX DE,HL
    CALL L_43CD
    POP BC
    JP C,STPRDY
    EX [SP],HL
    PUSH HL
    PUSH BC
    EX DE,HL
    LD [DOT],HL
    CALL LINPRT
    POP HL
    LD A,[HL]
    CP $09
    JP Z,L_20CD
    LD A,$20
    CALL OUTDO
L_20CD:
    CALL L_20E6
    LD HL,$0962
    CALL L_20DC
    CALL L_4221
    JP L_2091
L_20DC:
    LD A,[HL]
    OR A
    RET Z
    CALL L_42A5
    INC HL
    JP L_20DC
L_20E6:
    LD BC,$0962
    LD D,$FF
    XOR A
    LD [D_0BE6],A
    CALL L_5D65
    JP L_20F9
L_20F5:
    INC BC
    INC HL
    DEC D
    RET Z
L_20F9:
    LD A,[HL]
    OR A
    LD [BC],A
    RET Z
    CP $0B
    JP C,L_2108
    CP $20
    LD E,A
    JP C,L_211C
L_2108:
    OR A
    JP M,L_2141
    LD E,A
    CP $2E
    JP Z,L_211C
    CALL L_21E2
    JP NC,L_211C
    XOR A
    JP L_212F
L_211C:
    LD A,[D_0BE6]
    OR A
    JP Z,L_212D
    INC A
    JP NZ,L_212D
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    RET Z
L_212D:
    LD A,$01
L_212F:
    LD [D_0BE6],A
    LD A,E
    CP $0B
    JP C,L_213D
    CP $20
    JP C,L_21ED
L_213D:
    LD [BC],A
    JP L_20F5
L_2141:
    INC A
    LD A,[HL]
    JP NZ,L_214A
    INC HL
    LD A,[HL]
    AND $7F
L_214A:
    INC HL
    CP $DB
    JP NZ,L_2158
    DEC BC
    DEC BC
    DEC BC
    DEC BC
    INC D
    INC D
    INC D
    INC D
L_2158:
    CP $A2
    CALL Z,L_2A6B
    CP $B4
    JP NZ,L_216C
    LD A,[HL]
    INC HL
    CP $F2
    LD A,$B4
    JP Z,L_216C
    DEC HL
L_216C:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,$023A
    LD B,A
    LD C,$40
L_2175:
    INC C
L_2176:
    INC HL
    LD D,H
    LD E,L
L_2179:
    LD A,[HL]
    OR A
    JP Z,L_2175
    INC HL
    JP P,L_2179
    LD A,[HL]
    CP B
    JP NZ,L_2176
    EX DE,HL
    CP $D2
    JP Z,L_218F
    CP $D3
L_218F:
    LD A,C
    POP DE
    POP BC
    LD E,A
    JP NZ,L_21A2
    LD A,[D_0BE6]
    OR A
    LD A,$00
    LD [D_0BE6],A
    JP L_21B7
L_21A2:
    CP $5B
    JP NZ,L_21AE
    XOR A
    LD [D_0BE6],A
    JP L_21C6
L_21AE:
    LD A,[D_0BE6]
    OR A
    LD A,$FF
    LD [D_0BE6],A
L_21B7:
    JP Z,L_21C2
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP Z,L_4758
L_21C2:
    LD A,E
    JP L_21C9
L_21C6:
    LD A,[HL]
    INC HL
    LD E,A
L_21C9:
    AND $7F
    LD [BC],A
    INC BC
    DEC D
    JP Z,L_4758
    OR E
    JP P,L_21C6
    CP $A8
    JP NZ,L_21DE
    XOR A
    LD [D_0BE6],A
L_21DE:
    POP HL
    JP L_20F9
L_21E2:
    CALL L_4504
    RET NC
    CP $30
    RET C
    CP $3A
    CCF
    RET
L_21ED:
    DEC HL
    CALL CHRGTR
    PUSH DE
    PUSH BC
    PUSH AF
    CALL L_138E
    POP AF
    LD BC,$220C
    PUSH BC
    CP $0B
    JP Z,L_366F
    CP $0C
    JP Z,L_3672
    LD HL,[D_0A6E]
    JP L_3129
    .byte $C1, $D1, $3A, $6C, $0A, $1E, $4F, $FE, $0B, $CA, $1F, $22, $FE, $0C, $1E, $48
    .byte $C2, $2A, $22, $3E, $26, $02, $03, $15, $C8, $7B, $02, $03, $15, $C8, $3A, $6D
    .byte $0A, $FE, $04, $1E, $00, $DA, $3B, $22, $1E, $21, $CA, $3B, $22, $1E, $23, $7E
    .byte $FE, $20, $CC, $BE, $28, $7E, $23, $B7, $CA, $6D, $22, $02, $03, $15, $C8, $3A
    .byte $6D, $0A, $FE, $04, $DA, $41, $22, $0B, $0A, $03, $C2, $5E, $22, $FE, $2E, $CA
    .byte $68, $22, $FE, $44, $CA, $68, $22, $FE, $45, $C2, $41, $22, $1E, $00, $C3, $41
    .byte $22, $7B, $B7, $CA, $76, $22, $02, $03, $15, $C8, $2A, $6A, $0A, $C3, $F9, $20
ST_DELETE:
    CALL L_0ED8
    PUSH BC
    CALL L_2435
    POP BC
    POP DE
    PUSH BC
    PUSH BC
    CALL L_0EF8
    JP NC,L_2294
    LD D,H
    LD E,L
    EX [SP],HL
    PUSH HL
    CALL L_43CD
L_2294:
    JP NC,L_1418
    LD HL,$0C45
    CALL L_4723
    POP BC
    LD HL,$0E87
    EX [SP],HL
L_22A2:
    EX DE,HL
    LD HL,[VARTAB]
L_22A6:
    LD A,[DE]
    LD [BC],A
    INC BC
    INC DE
    CALL L_43CD
    JP NZ,L_22A6
    LD H,B
    LD L,C
    LD [VARTAB],HL
    RET
FN_PEEK:
    CALL L_22DB
    CALL L_5D5C
    LD A,[HL]
    JP L_1DD5
ST_POKE:
    CALL L_22D1
    PUSH DE
    CALL L_5D5C
    CALL L_43D3
    INC L
    CALL L_2075
    POP DE
    LD [DE],A
    RET
L_22D1:
    CALL L_1A02
    PUSH HL
    CALL L_22DB
    EX DE,HL
    POP HL
    RET
L_22DB:
    LD BC,$297A
    PUSH BC
    CALL L_1D64
    RET M
    LD A,[D_0C07]
    CP $90
    RET NZ
    CALL L_2845
    RET M
    CALL FN_CSNG
    LD BC,$9180
    LD DE,$0000
    JP L_2588
ST_RENUM:
    LD BC,$000A
    PUSH BC
    LD D,B
    LD E,B
    JP Z,L_232F
    CP $2C
    JP Z,L_2311
    PUSH DE
    CALL L_141D
    LD B,D
    LD C,E
    POP DE
    JP Z,L_232F
L_2311:
    CALL L_43D3
    INC L
    CALL L_141D
    JP Z,L_232F
    POP AF
    CALL L_43D3
    INC L
    PUSH DE
    CALL L_1428
    JP NZ,SNERR
    LD A,D
    OR E
    JP Z,L_1418
    EX DE,HL
    EX [SP],HL
    EX DE,HL
L_232F:
    PUSH BC
    CALL L_0EF8
    POP DE
    PUSH DE
    PUSH BC
    CALL L_0EF8
    LD H,B
    LD L,C
    POP DE
    CALL L_43CD
    EX DE,HL
    JP C,L_1418
    POP DE
    POP BC
    POP AF
    PUSH HL
    PUSH DE
    JP L_235B
L_234B:
    ADD HL,BC
    JP C,L_1418
    EX DE,HL
    PUSH HL
    LD HL,$FFF9
    CALL L_43CD
    POP HL
    JP C,L_1418
L_235B:
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    EX DE,HL
    POP DE
    JP Z,L_236E
    LD A,[HL]
    INC HL
    OR [HL]
    DEC HL
    EX DE,HL
    JP NZ,L_234B
L_236E:
    PUSH BC
    CALL L_2391
    POP BC
    POP DE
    POP HL
L_2375:
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    JP Z,L_238C
    EX DE,HL
    EX [SP],HL
    EX DE,HL
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    EX DE,HL
    ADD HL,BC
    EX DE,HL
    POP HL
    JP L_2375
L_238C:
    LD BC,$0D86
    PUSH BC
    .byte $FE
L_2391:
    .byte $F6
L_2392:
    XOR A
    LD [PTRFLG],A
    LD HL,[TXTTAB]
    DEC HL
L_239A:
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    RET Z
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
L_23A3:
    CALL CHRGTR
L_23A6:
    OR A
    JP Z,L_239A
    LD C,A
    LD A,[PTRFLG]
    OR A
    LD A,C
    JP Z,L_2412
    CP $A8
    JP NZ,L_23D4
    CALL CHRGTR
    CP $89
    JP NZ,L_23A6
    CALL CHRGTR
    CP $0E
    JP NZ,L_23A6
    PUSH DE
    CALL L_1433
    LD A,D
    OR E
    JP NZ,L_23DD
    JP L_23FD
L_23D4:
    CP $0E
    JP NZ,L_23A3
    PUSH DE
    CALL L_1433
L_23DD:
    PUSH HL
    CALL L_0EF8
    DEC BC
    LD A,$0D
    JP C,L_2425
    CALL L_4214
    LD HL,$2402
    PUSH DE
    CALL L_4723
    POP HL
    CALL LINPRT
    POP BC
    POP HL
    PUSH HL
    PUSH BC
    CALL L_3112
    POP HL
L_23FD:
    POP DE
    DEC HL
L_23FF:
    JP L_23A3
    .byte $55, $6E, $64, $65, $66, $69, $6E, $65, $64, $20, $6C, $69, $6E, $65, $20, $00
L_2412:
    CP $0D
    JP NZ,L_23FF
    PUSH DE
    CALL L_1433
    PUSH HL
    EX DE,HL
    INC HL
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,$0E
L_2425:
    LD HL,$23FC
    PUSH HL
    LD HL,[D_0A6A]
L_242C:
    PUSH HL
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    LD [HL],A
    POP HL
    RET
L_2435:
    LD A,[PTRFLG]
    OR A
    RET Z
    JP L_2392
ST_OPTION:
    CALL L_43D3
    LD B,D
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_43D3
    LD B,L
    LD A,[D_0BC7]
    OR A
    JP NZ,DDERR
    PUSH HL
    LD HL,[ARYTAB]
    EX DE,HL
    LD HL,[STREND]
    CALL L_43CD
    JP NZ,DDERR
    POP HL
    LD A,[HL]
    SUB $30
    JP C,SNERR
    CP $02
    JP NC,SNERR
    LD [D_0BC6],A
    INC A
    LD [D_0BC7],A
    CALL CHRGTR
    RET
L_2479:
    LD A,[HL]
    OR A
    RET Z
    CALL L_2483
    INC HL
    JP L_2479
L_2483:
    PUSH AF
    JP L_415C
ST_RANDOMIZE:
    JP Z,L_2494
    CALL L_1A02
    PUSH HL
    CALL FN_CINT
    JP L_24B0
L_2494:
    PUSH HL
L_2495:
    LD HL,$24B8
    CALL L_4723
    CALL L_4B0D
    POP DE
    JP C,L_4416
    PUSH DE
    INC HL
    LD A,[HL]
    CALL L_2ED1
    LD A,[HL]
    OR A
    JP NZ,L_2495
    CALL FN_CINT
L_24B0:
    LD [D_386A],HL
    CALL L_37CF
    POP HL
    RET
    .byte $52, $61, $6E, $64, $6F, $6D, $20, $6E, $75, $6D, $62, $65, $72, $20, $73, $65
    .byte $65, $64, $20, $28, $2D, $33, $32, $37, $36, $38, $20, $74, $6F, $20, $33, $32
    .byte $37, $36, $37, $29, $00
L_24DD:
    LD C,$1D
    JP L_24E4
L_24E2:
    LD C,$1A
L_24E4:
    LD B,$00
    EX DE,HL
    LD HL,[CURLIN]
    LD [D_0BC4],HL
    EX DE,HL
L_24EE:
    INC B
L_24EF:
    DEC HL
L_24F0:
    CALL CHRGTR
    JP Z,L_2500
    CP $A2
    JP Z,L_2515
    CP $CF
    JP NZ,L_24F0
L_2500:
    OR A
    JP NZ,L_2515
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    LD E,C
    JP Z,ERROR
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_0BC4],HL
    EX DE,HL
L_2515:
    CALL CHRGTR
    LD A,C
    CP $1A
    LD A,[HL]
    JP Z,L_252E
    CP $B4
    JP Z,L_24EE
    CP $B5
    JP NZ,L_24EF
    DEC B
    JP NZ,L_24EF
    RET
L_252E:
    CP $82
    JP Z,L_24EE
    CP $83
    JP NZ,L_24EF
    DEC B
    RET Z
    CALL CHRGTR
    JP Z,L_2500
    EX DE,HL
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    EX DE,HL
    PUSH BC
    CALL L_398B
    POP BC
    DEC HL
    CALL CHRGTR
    LD DE,$2500
    JP Z,L_2563
    CALL L_43D3
    INC L
    DEC HL
    LD DE,$2538
L_2563:
    EX [SP],HL
    LD [CURLIN],HL
    POP HL
    PUSH DE
    RET
    .byte $F5, $3A, $09, $0C, $32, $0A, $0C, $F1
L_2572:
    PUSH AF
    XOR A
    LD [D_0C09],A
    POP AF
    RET
L_2579:
    LD HL,$360D
L_257C:
    CALL L_28B7
    JP L_2588
    .byte $CD, $B7, $28
L_2585:
    CALL L_2874
L_2588:
    LD A,B
    OR A
    RET Z
    LD A,[D_0C07]
    OR A
    JP Z,L_28A9
    SUB B
    JP NC,L_25A2
    CPL
    INC A
    EX DE,HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    POP BC
    POP DE
L_25A2:
    CP $19
    RET NC
    PUSH AF
    CALL L_28D6
    LD H,A
    POP AF
    CALL L_2662
    LD A,H
    OR A
    LD HL,$0C04
    JP P,L_25C9
    CALL L_2642
    JP NC,L_2623
    INC HL
    INC [HL]
    JP Z,L_3088
    LD L,$01
    CALL L_2689
    JP L_2623
L_25C9:
    XOR A
    SUB B
    LD B,A
    LD A,[HL]
    SBC A,E
    LD E,A
    INC HL
    LD A,[HL]
    SBC A,D
    LD D,A
    INC HL
    LD A,[HL]
    SBC A,C
    LD C,A
L_25D7:
    CALL C,L_264E
L_25DA:
    LD L,B
    LD H,E
    XOR A
L_25DD:
    LD B,A
    LD A,C
    OR A
    JP NZ,L_260E
    LD C,D
    LD D,H
    LD H,L
    LD L,A
    LD A,B
    SUB $08
    CP $E0
    JP NZ,L_25DD
L_25EF:
    XOR A
L_25F0:
    LD [D_0C07],A
    RET
L_25F4:
    LD A,H
    OR L
    OR D
    JP NZ,L_2606
    LD A,C
L_25FB:
    DEC B
    RLA
    JP NC,L_25FB
    INC B
    RRA
    LD C,A
    JP L_2611
L_2606:
    DEC B
    ADD HL,HL
    LD A,D
    RLA
    LD D,A
    LD A,C
    ADC A,A
    LD C,A
L_260E:
    JP P,L_25F4
L_2611:
    LD A,B
    LD E,H
    LD B,L
    OR A
    JP Z,L_2623
    LD HL,$0C07
    ADD A,[HL]
    LD [HL],A
    JP NC,L_25EF
    JP Z,L_25EF
L_2623:
    LD A,B
L_2624:
    LD HL,$0C07
    OR A
    CALL M,L_2635
    LD B,[HL]
    INC HL
    LD A,[HL]
    AND $80
    XOR C
    LD C,A
    JP L_28A9
L_2635:
    INC E
    RET NZ
    INC D
    RET NZ
    INC C
    RET NZ
    LD C,$80
    INC [HL]
    RET NZ
    JP L_3087
L_2642:
    LD A,[HL]
    ADD A,E
    LD E,A
    INC HL
    LD A,[HL]
    ADC A,D
    LD D,A
    INC HL
    LD A,[HL]
    ADC A,C
    LD C,A
    RET
L_264E:
    LD HL,$0C08
    LD A,[HL]
    CPL
    LD [HL],A
    XOR A
    LD L,A
    SUB B
    LD B,A
    LD A,L
    SBC A,E
    LD E,A
    LD A,L
    SBC A,D
    LD D,A
    LD A,L
    SBC A,C
    LD C,A
    RET
L_2662:
    LD B,$00
L_2664:
    SUB $08
    JP C,L_2671
    LD B,E
    LD E,D
    LD D,C
    LD C,$00
    JP L_2664
L_2671:
    ADD A,$09
    LD L,A
    LD A,D
    OR E
    OR B
    JP NZ,L_2685
    LD A,C
L_267B:
    DEC L
    RET Z
    RRA
    LD C,A
    JP NC,L_267B
    JP L_268B
L_2685:
    XOR A
    DEC L
    RET Z
    LD A,C
L_2689:
    RRA
    LD C,A
L_268B:
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    LD A,B
    RRA
    LD B,A
    JP L_2685
    .byte $00, $00, $00, $81, $04, $9A, $F7, $19, $83, $24, $63, $43, $83, $75, $CD, $8D
    .byte $84, $A9, $7F, $83, $82, $04, $00, $00, $00, $81, $E2, $B0, $4D, $83, $0A, $72
    .byte $11, $83, $F4, $04, $35, $7F
FN_LOG:
    CALL L_2845
    OR A
    JP PE,L_1418
    CALL L_26D0
    LD BC,$8031
    LD DE,$7218
    JP L_2703
L_26D0:
    CALL L_28B4
    LD A,$80
    LD [D_0C07],A
    XOR B
    PUSH AF
    CALL L_2899
    LD HL,$269B
    CALL L_37A7
    POP BC
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    LD HL,$26AC
    CALL L_37A7
    POP BC
    POP DE
    CALL L_2769
    POP AF
    CALL L_2899
    CALL L_2854
    POP BC
    POP DE
    JP L_2588
L_2703:
    CALL L_2845
    RET Z
    LD L,$00
    CALL L_2803
    LD A,C
    LD [D_273C],A
    EX DE,HL
    LD [D_2737],HL
    LD BC,$0000
    LD D,B
    LD E,B
    LD HL,$25DA
    PUSH HL
    LD HL,$2725
    PUSH HL
    PUSH HL
    LD HL,$0C04
    LD A,[HL]
    INC HL
    OR A
    JP Z,L_2759
    PUSH HL
    EX DE,HL
    LD E,$08
L_272F:
    RRA
    LD D,A
    LD A,C
    JP NC,L_273D
    PUSH DE
    .byte $11
D_2737:
    .byte $00, $00
    ADD HL,DE
    POP DE
    .byte $CE
D_273C:
    .byte $00
L_273D:
    RRA
    LD C,A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    LD A,B
    RRA
    LD B,A
    AND $10
    JP Z,L_2751
    LD A,B
    OR $20
    LD B,A
L_2751:
    DEC E
    LD A,D
    JP NZ,L_272F
    EX DE,HL
L_2757:
    POP HL
    RET
L_2759:
    LD B,E
    LD E,D
    LD D,C
    LD C,A
    RET
L_275E:
    CALL L_2899
    LD HL,$2DAE
    CALL L_28A6
L_2767:
    POP BC
    POP DE
L_2769:
    CALL L_2845
    JP Z,L_3090
    LD L,$FF
    CALL L_2803
    INC [HL]
    JP Z,L_3067
    INC [HL]
    JP Z,L_3067
    DEC HL
    LD A,[HL]
    LD [D_27A0],A
    DEC HL
    LD A,[HL]
    LD [D_279C],A
    DEC HL
    LD A,[HL]
    LD [D_2798],A
    LD B,C
    EX DE,HL
    XOR A
    LD C,A
    LD D,A
    LD E,A
    LD [D_27A3],A
L_2794:
    PUSH HL
    PUSH BC
    LD A,L
    .byte $D6
D_2798:
    .byte $00
    LD L,A
    LD A,H
    .byte $DE
D_279C:
    .byte $00
    LD H,A
    LD A,B
    .byte $DE
D_27A0:
    .byte $00
    LD B,A
    .byte $3E
D_27A3:
    .byte $00
    SBC A,$00
    CCF
    JP NC,L_27B1
    LD [D_27A3],A
    POP AF
    POP AF
    SCF
    .byte $D2
L_27B1:
    .byte $C1, $E1
    LD A,C
    INC A
    DEC A
    RRA
    JP P,L_27CF
    RLA
    LD A,[D_27A3]
    RRA
    AND $C0
    PUSH AF
    LD A,B
    OR H
    OR L
    JP Z,L_27CA
    LD A,$20
L_27CA:
    POP HL
    OR H
    JP L_2624
L_27CF:
    RLA
    LD A,E
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,C
    RLA
    LD C,A
    ADD HL,HL
    LD A,B
    RLA
    LD B,A
    LD A,[D_27A3]
    RLA
    LD [D_27A3],A
    LD A,C
    OR D
    OR E
    JP NZ,L_2794
    PUSH HL
    LD HL,$0C07
    DEC [HL]
    POP HL
    JP NZ,L_2794
    JP L_25EF
    .byte $3E, $FF, $2E
L_27F9:
    XOR A
    LD HL,$0C13
    LD C,[HL]
    INC HL
    XOR [HL]
    LD B,A
    LD L,$00
L_2803:
    LD A,B
    OR A
    JP Z,L_2827
    LD A,L
    LD HL,$0C07
    XOR [HL]
    ADD A,B
    LD B,A
    RRA
    XOR B
    LD A,B
    JP P,L_2826
    ADD A,$80
    LD [HL],A
    JP Z,L_2757
    CALL L_28D6
    LD [HL],A
L_281F:
    DEC HL
    RET
    .byte $CD, $45, $28, $2F, $E1
L_2826:
    OR A
L_2827:
    POP HL
    JP P,L_25EF
    JP L_3067
L_282E:
    CALL L_28B4
    LD A,B
    OR A
    RET Z
    ADD A,$02
    JP C,L_3080
    LD B,A
    CALL L_2588
    LD HL,$0C07
    INC [HL]
    RET NZ
    JP L_3080
L_2845:
    LD A,[D_0C07]
    OR A
    RET Z
    LD A,[D_0C06]
    CP $2F
L_284F:
    RLA
L_2850:
    SBC A,A
    RET NZ
    INC A
    RET
L_2854:
    LD B,$88
    LD DE,$0000
L_2859:
    LD HL,$0C07
    LD C,A
    LD [HL],B
    LD B,$00
    INC HL
    LD [HL],$80
    RLA
    JP L_25D7
FN_ABS:
    CALL L_2886
    RET P
L_286B:
    CALL L_1D64
    JP M,L_2BF8
    JP Z,TMERR
L_2874:
    LD HL,$0C06
    LD A,[HL]
    XOR $80
    LD [HL],A
    RET
FN_SGN:
    CALL L_2886
L_287F:
    LD L,A
    RLA
    SBC A,A
    LD H,A
    JP L_29DC
L_2886:
    CALL L_1D64
    JP Z,TMERR
    JP P,L_2845
    LD HL,[D_0C04]
L_2892:
    LD A,H
    OR L
    RET Z
    LD A,H
    JP L_284F
L_2899:
    EX DE,HL
    LD HL,[D_0C04]
    EX [SP],HL
    PUSH HL
    LD HL,[D_0C06]
    EX [SP],HL
    PUSH HL
    EX DE,HL
    RET
L_28A6:
    CALL L_28B7
L_28A9:
    EX DE,HL
    LD [D_0C04],HL
    LD H,B
    LD L,C
    LD [D_0C06],HL
    EX DE,HL
    RET
L_28B4:
    LD HL,$0C04
L_28B7:
    LD E,[HL]
    INC HL
L_28B9:
    LD D,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
L_28BE:
    INC HL
    RET
L_28C0:
    LD DE,$0C04
L_28C3:
    LD B,$04
    JP L_28CD
    .byte $EB
L_28C9:
    LD A,[D_0A67]
    LD B,A
L_28CD:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC B
    JP NZ,L_28CD
    RET
L_28D6:
    LD HL,$0C06
    LD A,[HL]
    RLCA
    SCF
    RRA
    LD [HL],A
    CCF
    RRA
    INC HL
    INC HL
    LD [HL],A
    LD A,C
    RLCA
    SCF
    RRA
    LD C,A
    RRA
    XOR [HL]
    RET
L_28EB:
    LD HL,$0C0D
L_28EE:
    LD DE,$28C8
    JP L_28FA
L_28F4:
    LD HL,$0C0D
L_28F7:
    LD DE,$28C9
L_28FA:
    PUSH DE
    LD DE,$0C04
    CALL L_1D64
    RET C
    LD DE,$0C00
    RET
L_2906:
    LD A,B
    OR A
    JP Z,L_2845
    LD HL,$284E
    PUSH HL
    CALL L_2845
    LD A,C
    RET Z
    LD HL,$0C06
    XOR [HL]
    LD A,C
    RET M
    CALL L_2920
L_291D:
    RRA
    XOR C
    RET
L_2920:
    INC HL
    LD A,B
    CP [HL]
    RET NZ
    DEC HL
    LD A,C
    CP [HL]
    RET NZ
    DEC HL
    LD A,D
    CP [HL]
    RET NZ
    DEC HL
    LD A,E
    SUB [HL]
    RET NZ
    POP HL
    POP HL
    RET
L_2933:
    LD A,D
    XOR H
    LD A,H
    JP M,L_284F
    CP D
    JP NZ,L_2940
    LD A,L
    SUB E
    RET Z
L_2940:
    JP L_2850
L_2943:
    LD HL,$0C0D
    CALL L_28C9
    LD DE,$0C14
    LD A,[DE]
    OR A
    JP Z,L_2845
    LD HL,$284E
    PUSH HL
    CALL L_2845
    DEC DE
    LD A,[DE]
    LD C,A
    RET Z
    LD HL,$0C06
    XOR [HL]
    LD A,C
    RET M
    INC DE
    INC HL
    LD B,$08
L_2966:
    LD A,[DE]
    SUB [HL]
    JP NZ,L_291D
    DEC DE
    DEC HL
    DEC B
    JP NZ,L_2966
    POP BC
    RET
    .byte $CD, $49, $29, $C2, $4E, $28, $C9
FN_CINT:
    CALL L_1D64
    LD HL,[D_0C04]
    RET M
    JP Z,TMERR
    JP PO,L_2999
    CALL L_28F4
    LD HL,$3609
    CALL L_28EE
    CALL L_2C26
    CALL L_29FE
    JP L_299C
L_2999:
    CALL L_2579
L_299C:
    LD A,[D_0C06]
    OR A
    PUSH AF
    AND $7F
    LD [D_0C06],A
    LD A,[D_0C07]
    CP $90
    JP NC,OVERR
    CALL L_2A42
    LD A,[D_0C07]
    OR A
    JP NZ,L_29BD
    POP AF
    EX DE,HL
    JP L_29C2
L_29BD:
    POP AF
    EX DE,HL
    JP P,L_29C8
L_29C2:
    LD A,H
    CPL
    LD H,A
    LD A,L
    CPL
    LD L,A
L_29C8:
    JP L_29DC
    .byte $21, $DB, $0C, $E5
L_29CF:
    LD A,[D_0C07]
    CP $90
    JP NC,L_29E5
    CALL L_2A42
    EX DE,HL
L_29DB:
    POP DE
L_29DC:
    LD [D_0C04],HL
L_29DF:
    LD A,$02
L_29E1:
    LD [D_0A67],A
    RET
L_29E5:
    LD BC,$9080
    LD DE,$0000
    CALL L_2906
    RET NZ
    LD H,C
    LD L,D
    JP L_29DB
FN_CSNG:
    CALL L_1D64
    RET PO
    JP M,L_2A11
    JP Z,TMERR
L_29FE:
    CALL L_28B4
    CALL L_2A36
    LD A,B
    OR A
    RET Z
    CALL L_28D6
    LD HL,$0C03
    LD B,[HL]
    JP L_2623
L_2A11:
    LD HL,[D_0C04]
L_2A14:
    CALL L_2A36
    LD A,H
    LD D,L
    LD E,$00
    LD B,$90
    JP L_2859
FN_CDBL:
    CALL L_1D64
    RET NC
    JP Z,TMERR
    CALL M,L_2A11
L_2A2A:
    LD HL,$0000
    LD [D_0C00],HL
    LD [D_0C02],HL
L_2A33:
    LD A,$08
    .byte $01
L_2A36:
    LD A,$04
    JP L_29E1
L_2A3B:
    CALL L_1D64
    RET Z
    JP TMERR
L_2A42:
    LD B,A
    LD C,A
    LD D,A
    LD E,A
    OR A
    RET Z
    PUSH HL
    CALL L_28B4
    CALL L_28D6
    XOR [HL]
    LD H,A
    CALL M,L_2A66
    LD A,$98
    SUB B
    CALL L_2662
    LD A,H
    RLA
    CALL C,L_2635
    LD B,$00
    CALL C,L_264E
    POP HL
    RET
L_2A66:
    DEC DE
    LD A,D
    AND E
    INC A
    RET NZ
L_2A6B:
    DEC BC
    RET
FN_FIX:
    CALL L_1D64
    RET M
    CALL L_2845
    JP P,FN_INT
    CALL L_2874
    CALL FN_INT
    JP L_286B
FN_INT:
    CALL L_1D64
    RET M
    JP NC,L_2AA6
    JP Z,TMERR
    CALL L_29CF
L_2A8D:
    LD HL,$0C07
    LD A,[HL]
    CP $98
    LD A,[D_0C04]
    RET NC
    LD A,[HL]
    CALL L_2A42
    LD [HL],$98
    LD A,E
    PUSH AF
    LD A,C
    RLA
    CALL L_25D7
    POP AF
    RET
L_2AA6:
    LD HL,$0C07
    LD A,[HL]
    CP $90
    JP NZ,L_2ACA
    LD C,A
    DEC HL
    LD A,[HL]
    XOR $80
    LD B,$06
L_2AB6:
    DEC HL
    OR [HL]
    DEC B
    JP NZ,L_2AB6
    OR A
    LD HL,$8000
    JP NZ,L_2AC9
    CALL L_29DC
    JP FN_CDBL
L_2AC9:
    LD A,C
L_2ACA:
    OR A
    RET Z
    CP $B8
    RET NC
L_2ACF:
    PUSH AF
    CALL L_28B4
    CALL L_28D6
    XOR [HL]
    DEC HL
    LD [HL],$B8
    PUSH AF
    DEC HL
    LD [HL],C
    CALL M,L_2AFA
    LD A,[D_0C06]
    LD C,A
    LD HL,$0C06
    LD A,$B8
    SUB B
    CALL L_2D25
    POP AF
    CALL M,L_2CDD
    XOR A
    LD [D_0BFF],A
    POP AF
    RET NC
    JP L_2C91
L_2AFA:
    LD HL,$0C00
L_2AFD:
    LD A,[HL]
    DEC [HL]
    OR A
    INC HL
    JP Z,L_2AFD
    RET
L_2B05:
    PUSH HL
    LD HL,$0000
    LD A,B
    OR C
    JP Z,L_2B22
    LD A,$10
L_2B10:
    ADD HL,HL
    JP C,L_3BD6
    EX DE,HL
    ADD HL,HL
    EX DE,HL
    JP NC,L_2B1E
    ADD HL,BC
    JP C,L_3BD6
L_2B1E:
    DEC A
    JP NZ,L_2B10
L_2B22:
    EX DE,HL
    POP HL
    RET
    .byte $7C, $17, $9F, $47, $CD, $EE, $2B, $79, $98, $C3, $34, $2B
L_2B31:
    LD A,H
    RLA
    SBC A,A
    LD B,A
    PUSH HL
    LD A,D
    RLA
    SBC A,A
    ADD HL,DE
    ADC A,B
    RRCA
    XOR H
    JP P,L_29DB
    PUSH BC
    EX DE,HL
    CALL L_2A14
    POP AF
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_2C08
    JP L_304E
    .byte $7C, $B5, $CA, $DC, $29, $E5, $D5, $CD, $E2, $2B, $C5, $44, $4D, $21, $00, $00
    .byte $3E, $10, $29, $DA, $89, $2B, $EB, $29, $EB, $D2, $71, $2B, $09, $DA, $89, $2B
    .byte $3D, $C2, $63, $2B, $C1, $D1
L_2B77:
    LD A,H
    OR A
    JP M,L_2B81
    POP DE
    LD A,B
    JP L_2BEA
L_2B81:
    XOR $80
    OR L
    JP Z,L_2B9A
    EX DE,HL
    LD BC,$E1C1
    CALL L_2A14
    POP HL
    CALL L_2899
    CALL L_2A14
    POP BC
    POP DE
    JP L_2703
L_2B9A:
    LD A,B
    OR A
    POP BC
    JP M,L_29DC
    PUSH DE
    CALL L_2A14
    POP DE
    JP L_2874
L_2BA8:
    LD A,H
    OR L
    JP Z,DV0ERR
    CALL L_2BE2
    PUSH BC
    EX DE,HL
    CALL L_2BEE
    LD B,H
    LD C,L
    LD HL,$0000
    LD A,$11
    PUSH AF
    OR A
    JP L_2BCB
L_2BC1:
    PUSH AF
    PUSH HL
    ADD HL,BC
    JP NC,L_2BCA
    POP AF
    SCF
    .byte $3E
L_2BCA:
    .byte $E1
L_2BCB:
    LD A,E
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,L
    RLA
    LD L,A
    LD A,H
    RLA
    LD H,A
    POP AF
    DEC A
    JP NZ,L_2BC1
    EX DE,HL
    POP BC
    PUSH DE
    JP L_2B77
L_2BE2:
    LD A,H
    XOR D
    LD B,A
    CALL L_2BE9
    EX DE,HL
L_2BE9:
    LD A,H
L_2BEA:
    OR A
    JP P,L_29DC
L_2BEE:
    XOR A
    LD C,A
    SUB L
    LD L,A
    LD A,C
    SBC A,H
    LD H,A
    JP L_29DC
L_2BF8:
    LD HL,[D_0C04]
    CALL L_2BEE
    LD A,H
    XOR $80
    OR L
    RET NZ
L_2C03:
    EX DE,HL
    CALL L_2A36
    XOR A
L_2C08:
    LD B,$98
    JP L_2859
L_2C0D:
    PUSH DE
    CALL L_2BA8
    XOR A
    ADD A,D
    RRA
    LD H,A
    LD A,E
    RRA
    LD L,A
    CALL L_29DF
    POP AF
    JP L_2BEA
    .byte $21, $13, $0C, $7E, $EE, $80, $77
L_2C26:
    LD HL,$0C14
    LD A,[HL]
    OR A
    RET Z
    LD B,A
    DEC HL
    LD C,[HL]
    LD DE,$0C07
    LD A,[DE]
    OR A
    JP Z,L_28EB
    SUB B
    JP NC,L_2C52
    CPL
    INC A
    PUSH AF
    LD C,$08
    INC HL
    PUSH HL
L_2C42:
    LD A,[DE]
    LD B,[HL]
    LD [HL],A
    LD A,B
    LD [DE],A
    DEC DE
    DEC HL
    DEC C
    JP NZ,L_2C42
    POP HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    POP AF
L_2C52:
    CP $39
    RET NC
    PUSH AF
    CALL L_28D6
    LD HL,$0C0C
    LD B,A
    LD A,$00
    LD [HL],A
    LD [D_0BFF],A
    POP AF
    LD HL,$0C13
    CALL L_2D25
    LD A,B
    OR A
    JP P,L_2C86
    LD A,[D_0C0C]
    LD [D_0BFF],A
    CALL L_2CFA
    JP NC,L_2CCB
    EX DE,HL
    INC [HL]
    JP Z,L_3088
    CALL L_2D51
    JP L_2CCB
L_2C86:
    LD A,$9E
    CALL L_2CFC
    LD HL,$0C08
    CALL C,L_2D12
L_2C91:
    XOR A
L_2C92:
    LD B,A
    LD A,[D_0C06]
    OR A
    JP NZ,L_2CBA
    LD HL,$0BFF
    LD C,$08
L_2C9F:
    LD D,[HL]
    LD [HL],A
    LD A,D
    INC HL
    DEC C
    JP NZ,L_2C9F
    LD A,B
    SUB $08
    CP $C0
    JP NZ,L_2C92
    JP L_25EF
L_2CB2:
    DEC B
    LD HL,$0BFF
    CALL L_2D59
    OR A
L_2CBA:
    JP P,L_2CB2
    LD A,B
    OR A
    JP Z,L_2CCB
    LD HL,$0C07
    ADD A,[HL]
    LD [HL],A
    JP NC,L_25EF
    RET Z
L_2CCB:
    LD A,[D_0BFF]
    OR A
    CALL M,L_2CDD
    LD HL,$0C08
    LD A,[HL]
    AND $80
    DEC HL
    DEC HL
    XOR [HL]
    LD [HL],A
    RET
L_2CDD:
    LD HL,$0C00
    LD B,$07
L_2CE2:
    INC [HL]
    RET NZ
    INC HL
    DEC B
    JP NZ,L_2CE2
    INC [HL]
    JP Z,L_3088
    DEC HL
    LD [HL],$80
    RET
    .byte $11, $30, $0C, $21, $0D, $0C, $C3, $02, $2D
L_2CFA:
    LD A,$8E
L_2CFC:
    LD HL,$0C0D
L_2CFF:
    LD DE,$0C00
    LD C,$07
    LD [D_2D09],A
    XOR A
L_2D08:
    LD A,[DE]
D_2D09:
    ADC A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JP NZ,L_2D08
    RET
L_2D12:
    LD A,[HL]
    CPL
    LD [HL],A
    LD HL,$0BFF
    LD B,$08
    XOR A
    LD C,A
L_2D1C:
    LD A,C
    SBC A,[HL]
    LD [HL],A
    INC HL
    DEC B
    JP NZ,L_2D1C
    RET
L_2D25:
    LD [HL],C
    PUSH HL
L_2D27:
    SUB $08
    JP C,L_2D3C
    POP HL
L_2D2D:
    PUSH HL
    LD DE,$0800
L_2D31:
    LD C,[HL]
    LD [HL],E
    LD E,C
    DEC HL
    DEC D
    JP NZ,L_2D31
    JP L_2D27
L_2D3C:
    ADD A,$09
    LD D,A
L_2D3F:
    XOR A
    POP HL
    DEC D
    RET Z
L_2D43:
    PUSH HL
    LD E,$08
L_2D46:
    LD A,[HL]
    RRA
    LD [HL],A
    DEC HL
    DEC E
    JP NZ,L_2D46
    JP L_2D3F
L_2D51:
    LD HL,$0C06
    LD D,$01
    JP L_2D43
L_2D59:
    LD C,$08
L_2D5B:
    LD A,[HL]
    RLA
    LD [HL],A
    INC HL
    DEC C
    JP NZ,L_2D5B
    RET
L_2D64:
    CALL L_2845
    RET Z
    LD A,[D_0C14]
    OR A
    JP Z,L_25EF
    CALL L_27F9
    CALL L_2E9D
    LD [HL],C
    INC DE
    LD B,$07
L_2D79:
    LD A,[DE]
    INC DE
    OR A
    PUSH DE
    JP Z,L_2D99
    LD C,$08
L_2D82:
    PUSH BC
    RRA
    LD B,A
    CALL C,L_2CFA
    CALL L_2D51
    LD A,B
    POP BC
    DEC C
    JP NZ,L_2D82
L_2D91:
    POP DE
    DEC B
    JP NZ,L_2D79
    JP L_2C91
L_2D99:
    LD HL,$0C06
    CALL L_2D2D
    JP L_2D91
    .byte $CD, $CC, $CC, $CC, $CC, $CC, $4C, $7D, $00, $00, $00, $00, $00, $00, $20, $84
L_2DB2:
    LD A,[D_0C07]
    CP $41
    JP NC,L_2DC6
    LD DE,$2DA2
    LD HL,$0C0D
    CALL L_28C9
    JP L_2D64
L_2DC6:
    LD A,[D_0C06]
    OR A
    JP P,L_2DD6
    AND $7F
    LD [D_0C06],A
    LD HL,$2874
    PUSH HL
L_2DD6:
    CALL L_2E0E
    LD DE,$0C00
    LD HL,$0C0D
    CALL L_28C9
    CALL L_2E0E
    CALL L_2C26
    LD DE,$0C00
    LD HL,$0C0D
    CALL L_28C9
    LD A,$0F
L_2DF3:
    PUSH AF
    CALL L_2E16
    CALL L_2E22
    CALL L_2C26
    LD HL,$0C13
    CALL L_2E33
    POP AF
    DEC A
    JP NZ,L_2DF3
    CALL L_2E0E
    CALL L_2E0E
L_2E0E:
    LD HL,$0C07
    DEC [HL]
    RET NZ
    JP L_25EF
L_2E16:
    LD HL,$0C14
    LD A,$04
L_2E1B:
    DEC [HL]
    RET Z
    DEC A
    JP NZ,L_2E1B
    RET
L_2E22:
    POP DE
    LD A,$04
    LD HL,$0C0D
L_2E28:
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,L_2E28
    PUSH DE
    RET
L_2E33:
    POP DE
    LD A,$04
    LD HL,$0C14
L_2E39:
    POP BC
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    DEC A
    JP NZ,L_2E39
    PUSH DE
    RET
    .byte $3A, $14, $0C, $B7, $CA, $94, $30, $3A, $07, $0C, $B7, $CA, $EF, $25, $CD, $F6
    .byte $27, $34, $34, $CA, $88, $30, $CD, $9D, $2E, $21, $37, $0C, $71, $41, $3E, $9E
    .byte $CD, $F1, $2C, $1A, $99, $3F, $DA, $74, $2E, $3E, $8E, $CD, $F1, $2C, $AF, $DA
    .byte $12, $04, $3A, $06, $0C, $3C, $3D, $1F, $FA, $CE, $2C, $17, $21, $00, $0C, $0E
    .byte $07, $CD, $5B, $2D, $21, $30, $0C, $CD, $59, $2D, $78, $B7, $C2, $62, $2E, $21
    .byte $07, $0C, $35, $C2, $62, $2E, $C3, $EF, $25
L_2E9D:
    LD A,C
    LD [D_0C13],A
    DEC HL
    LD DE,$0C36
    LD BC,$0700
L_2EA8:
    LD A,[HL]
    LD [DE],A
    LD [HL],C
    DEC DE
    DEC HL
    DEC B
    JP NZ,L_2EA8
    RET
L_2EB2:
    CALL L_28F4
    EX DE,HL
    DEC HL
    LD A,[HL]
    OR A
    RET Z
    ADD A,$02
    JP C,L_3088
    LD [HL],A
    PUSH HL
    CALL L_2C26
    POP HL
    INC [HL]
    RET NZ
    JP L_3088
L_2ECA:
    CALL L_25EF
    CALL L_2A33
    .byte $F6
L_2ED1:
    .byte $AF
    LD BC,$256A
    PUSH BC
    PUSH AF
    LD A,$01
    LD [D_0C09],A
    POP AF
    EX DE,HL
    LD BC,$00FF
    LD H,B
    LD L,B
    CALL Z,L_29DC
    EX DE,HL
    LD A,[HL]
    CP $26
    JP Z,L_1C69
    CP $2D
    PUSH AF
    JP Z,L_2EF9
    CP $2B
    JP Z,L_2EF9
    DEC HL
L_2EF9:
    CALL CHRGTR
    JP C,L_2FE0
    CP $2E
    JP Z,L_2F86
    CP $65
    JP Z,L_2F0B
    CP $45
L_2F0B:
    JP NZ,L_2F35
    PUSH HL
    CALL CHRGTR
    CP $6C
    JP Z,L_2F23
    CP $4C
    JP Z,L_2F23
    CP $71
    JP Z,L_2F23
    CP $51
L_2F23:
    POP HL
    JP Z,L_2F34
    LD A,[D_0A67]
    CP $08
    JP Z,L_2F4E
    LD A,$00
    JP L_2F4E
L_2F34:
    LD A,[HL]
L_2F35:
    CP $25
    JP Z,L_2F93
    CP $23
    JP Z,L_2FA4
    CP $21
    JP Z,L_2FA5
    CP $64
    JP Z,L_2F4E
    CP $44
    JP NZ,L_2F65
L_2F4E:
    OR A
    CALL L_2FAE
    CALL CHRGTR
    CALL L_1D32
L_2F58:
    CALL CHRGTR
    JP C,L_3053
    INC D
    JP NZ,L_2F65
    XOR A
    SUB E
    LD E,A
L_2F65:
    PUSH HL
    LD A,E
    SUB B
    LD E,A
L_2F69:
    CALL P,L_2FBD
    CALL M,L_2FCD
    JP NZ,L_2F69
    POP HL
    POP AF
    PUSH HL
    CALL Z,L_286B
    POP HL
    CALL L_1D64
    RET PE
    PUSH HL
    LD HL,$2757
    PUSH HL
    CALL L_29E5
    RET
L_2F86:
    CALL L_1D64
    INC C
    JP NZ,L_2F65
    CALL C,L_2FAE
    JP L_2EF9
L_2F93:
    CALL CHRGTR
    POP AF
    PUSH HL
    LD HL,$2757
    PUSH HL
    LD HL,$297A
    PUSH HL
    PUSH AF
    JP L_2F65
L_2FA4:
    OR A
L_2FA5:
    CALL L_2FAE
    CALL CHRGTR
    JP L_2F65
L_2FAE:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    CALL Z,FN_CSNG
    POP AF
    CALL NZ,FN_CDBL
    POP BC
    POP DE
    POP HL
    RET
L_2FBD:
    RET Z
L_2FBE:
    PUSH AF
    CALL L_1D64
    PUSH AF
    CALL PO,L_282E
    POP AF
    CALL PE,L_2EB2
    POP AF
L_2FCB:
    DEC A
    RET
L_2FCD:
    PUSH DE
    PUSH HL
    PUSH AF
    CALL L_1D64
    PUSH AF
    CALL PO,L_275E
    POP AF
    CALL PE,L_2DB2
    POP AF
    POP HL
    POP DE
    INC A
    RET
L_2FE0:
    PUSH DE
    LD A,B
    ADC A,C
    LD B,A
    PUSH BC
    PUSH HL
    LD A,[HL]
    SUB $30
    PUSH AF
    CALL L_1D64
    JP P,L_3019
    LD HL,[D_0C04]
    LD DE,$0CCD
    CALL L_43CD
    JP NC,L_3015
    LD D,H
    LD E,L
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    POP AF
    LD C,A
    ADD HL,BC
    LD A,H
    OR A
    JP M,L_3013
    LD [D_0C04],HL
L_300D:
    POP HL
    POP BC
    POP DE
    JP L_2EF9
L_3013:
    LD A,C
    PUSH AF
L_3015:
    CALL L_2A11
    SCF
L_3019:
    JP NC,L_3035
    LD BC,$9474
    LD DE,$2400
    CALL L_2906
    JP P,L_3032
    CALL L_282E
    POP AF
    CALL L_3048
    JP L_300D
L_3032:
    CALL L_2A2A
L_3035:
    CALL L_2EB2
    CALL L_28F4
    POP AF
    CALL L_2854
    CALL L_2A2A
    CALL L_2C26
    JP L_300D
L_3048:
    CALL L_2899
    CALL L_2854
L_304E:
    POP BC
    POP DE
    JP L_2588
L_3053:
    LD A,E
    CP $0A
    JP NC,L_3062
    RLCA
    RLCA
    ADD A,E
    RLCA
    ADD A,[HL]
    SUB $30
    LD E,A
    .byte $FA
L_3062:
    .byte $1E, $7F
    JP L_2F58
L_3067:
    PUSH HL
    LD HL,$0C06
    CALL L_1D64
    JP PO,L_3077
    LD A,[D_0C13]
    JP L_3078
L_3077:
    LD A,C
L_3078:
    XOR [HL]
    RLA
    POP HL
    JP L_309E
L_307E:
    POP AF
    POP AF
L_3080:
    LD A,[D_0C06]
    RLA
    JP L_309E
L_3087:
    POP AF
L_3088:
    LD A,[D_0C08]
    CPL
    RLA
    JP L_309E
L_3090:
    LD A,C
    JP L_3097
    .byte $3A, $13, $0C
L_3097:
    RLA
    LD HL,$0562
    LD [D_079C],HL
L_309E:
    PUSH HL
    PUSH BC
    PUSH DE
    PUSH AF
    PUSH AF
    LD HL,[ONELIN]
    LD A,H
    OR L
    JP NZ,L_30CB
    LD HL,$0C09
    LD A,[HL]
    OR A
    JP Z,L_30B8
    DEC A
    JP NZ,L_30CB
    INC [HL]
L_30B8:
    LD HL,[D_079C]
    CALL L_2479
    LD [D_0A65],A
    LD A,$0D
    CALL L_2483
    LD A,$0A
    CALL L_2483
L_30CB:
    POP AF
    LD HL,$0C04
    LD DE,$310A
    JP NC,L_30D8
    LD DE,$310E
L_30D8:
    CALL L_28C3
    CALL L_1D64
    JP C,L_30EA
    LD HL,$0C00
    LD DE,$310E
    CALL L_28C3
L_30EA:
    LD HL,[ONELIN]
    LD A,H
    OR L
    LD HL,[D_079C]
    LD DE,$0509
    EX DE,HL
    LD [D_079C],HL
    JP Z,L_3105
    CALL L_43CD
    JP Z,OVERR
    JP DV0ERR
L_3105:
    POP AF
    POP DE
    POP BC
    POP HL
    RET
    .byte $FF, $FF, $7F, $FF, $FF, $FF, $FF, $FF
L_3112:
    PUSH HL
    LD HL,$0C40
    CALL L_4723
    POP HL
LINPRT:
    LD BC,$4722
    PUSH BC
    CALL L_29DC
    XOR A
    CALL L_31B2
    OR [HL]
    JP L_3146
L_3129:
    XOR A
L_312A:
    CALL L_31B2
    AND $08
    JP Z,L_3134
    LD [HL],$2B
L_3134:
    EX DE,HL
    CALL L_2886
    EX DE,HL
    JP P,L_3146
    LD [HL],$2D
    PUSH BC
    PUSH HL
    CALL L_286B
    POP HL
    POP BC
    OR H
L_3146:
    INC HL
    LD [HL],$30
    LD A,[TEMP3]
    LD D,A
    RLA
    LD A,[D_0A67]
    JP C,L_32D7
    JP Z,L_32CF
    CP $04
    JP NC,L_31BB
    LD BC,$0000
    CALL L_35BA
L_3162:
    LD HL,$0C16
    LD B,[HL]
    LD C,$20
    LD A,[TEMP3]
    LD E,A
    AND $20
    JP Z,L_317F
    LD A,B
    CP C
    LD C,$2A
    JP NZ,L_317F
    LD A,E
    AND $04
    JP NZ,L_317F
    LD B,C
L_317F:
    LD [HL],C
    CALL CHRGTR
    JP Z,L_319F
    CP $45
    JP Z,L_319F
    CP $44
    JP Z,L_319F
    CP $30
    JP Z,L_317F
    CP $2C
    JP Z,L_317F
    CP $2E
    JP NZ,L_31A2
L_319F:
    DEC HL
    LD [HL],$30
L_31A2:
    LD A,E
    AND $10
    JP Z,L_31AB
    DEC HL
    LD [HL],$24
L_31AB:
    LD A,E
    AND $04
    RET NZ
    DEC HL
    LD [HL],B
    RET
L_31B2:
    LD [TEMP3],A
    LD HL,$0C16
    LD [HL],$20
    RET
L_31BB:
    CALL L_2899
    EX DE,HL
    LD HL,[D_0C00]
    PUSH HL
    LD HL,[D_0C02]
    PUSH HL
    EX DE,HL
    PUSH AF
    XOR A
    LD [D_0C0B],A
    POP AF
    PUSH AF
    CALL L_3266
    LD B,$45
    LD C,$00
L_31D6:
    PUSH HL
    LD A,[HL]
L_31D8:
    CP B
    JP Z,L_3207
    CP $3A
    JP NC,L_31E7
    CP $30
    JP C,L_31E7
    INC C
L_31E7:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_31D8
    LD A,$44
    CP B
    LD B,A
    POP HL
    LD C,$00
    JP NZ,L_31D6
L_31F7:
    POP AF
    POP BC
    POP DE
    EX DE,HL
    LD [D_0C00],HL
    LD H,B
    LD L,C
    LD [D_0C02],HL
    EX DE,HL
    POP BC
    POP DE
    RET
L_3207:
    PUSH BC
    LD B,$00
    INC HL
    LD A,[HL]
L_320C:
    CP $2B
    JP Z,L_324E
    CP $2D
    JP Z,L_3225
    SUB $30
    LD C,A
    LD A,B
    ADD A,A
    ADD A,A
    ADD A,B
    ADD A,A
    ADD A,C
    LD B,A
    CP $10
    JP NC,L_324E
L_3225:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_320C
    LD H,B
    POP BC
    LD A,B
    CP $45
    JP NZ,L_3243
    LD A,C
    ADD A,H
    CP $09
    POP HL
    JP NC,L_31F7
L_323B:
    LD A,$80
    LD [D_0C0B],A
    JP L_3253
L_3243:
    LD A,H
    ADD A,C
    CP $12
    POP HL
    JP NC,L_31F7
    JP L_323B
L_324E:
    POP BC
    POP HL
    JP L_31F7
L_3253:
    POP AF
    POP BC
    POP DE
    EX DE,HL
    LD [D_0C00],HL
    LD H,B
    LD L,C
    LD [D_0C02],HL
    EX DE,HL
    POP BC
    POP DE
    CALL L_28A9
    INC HL
L_3266:
    CP $05
    PUSH HL
    SBC A,$00
    RLA
    LD D,A
    INC D
    CALL L_345C
    LD BC,$0300
    PUSH AF
    LD A,[D_0C0B]
    OR A
    JP P,L_3281
    POP AF
    ADD A,D
    JP L_328B
L_3281:
    POP AF
    ADD A,D
    JP M,L_328F
    INC D
    CP D
    JP NC,L_328F
L_328B:
    INC A
    LD B,A
    LD A,$02
L_328F:
    SUB $02
    POP HL
    PUSH AF
    CALL L_34FB
    LD [HL],$30
    CALL Z,L_28BE
    CALL L_3522
L_329E:
    DEC HL
    LD A,[HL]
    CP $30
    JP Z,L_329E
    CP $2E
    CALL NZ,L_28BE
    POP AF
    JP Z,L_32D0
L_32AE:
    PUSH AF
    CALL L_1D64
    LD A,$22
    ADC A,A
    LD [HL],A
    INC HL
    POP AF
    LD [HL],$2B
    JP P,L_32C1
    LD [HL],$2D
    CPL
    INC A
L_32C1:
    LD B,$2F
L_32C3:
    INC B
    SUB $0A
    JP NC,L_32C3
    ADD A,$3A
    INC HL
    LD [HL],B
    INC HL
    LD [HL],A
L_32CF:
    INC HL
L_32D0:
    LD [HL],$00
    EX DE,HL
    LD HL,$0C16
    RET
L_32D7:
    INC HL
    PUSH BC
    CP $04
    LD A,D
    JP NC,L_3351
    RRA
    JP C,L_33EE
    LD BC,$0603
    CALL L_34F3
    POP DE
    LD A,D
    SUB $05
    CALL P,L_34CF
    CALL L_35BA
L_32F3:
    LD A,E
    OR A
    CALL Z,L_281F
    DEC A
    CALL P,L_34CF
L_32FC:
    PUSH HL
    CALL L_3162
    POP HL
    JP Z,L_3306
    LD [HL],B
    INC HL
L_3306:
    LD [HL],$00
    LD HL,$0C15
L_330B:
    INC HL
L_330C:
    LD A,[TEMP2]
    SUB L
    SUB D
    RET Z
    LD A,[HL]
    CP $20
    JP Z,L_330B
    CP $2A
    JP Z,L_330B
    DEC HL
    PUSH HL
    PUSH AF
    LD BC,$331F
    PUSH BC
    CALL CHRGTR
    CP $2D
    RET Z
    CP $2B
    RET Z
    CP $24
    RET Z
    POP BC
    CP $30
    JP NZ,L_3349
    INC HL
    CALL CHRGTR
    JP NC,L_3349
    DEC HL
    .byte $01
L_333F:
    .byte $2B, $77
    POP AF
    JP Z,L_333F
    POP BC
    JP L_330C
L_3349:
    POP AF
    JP Z,L_3349
    POP HL
    LD [HL],$25
    RET
L_3351:
    PUSH HL
    RRA
    JP C,L_33F5
    JP Z,L_336D
    LD DE,$3611
    CALL L_2943
    LD D,$10
    JP M,L_337B
L_3364:
    POP HL
    POP BC
    CALL L_3129
    DEC HL
    LD [HL],$25
    RET
L_336D:
    LD BC,$B60E
    LD DE,$1BCA
    CALL L_2906
    JP P,L_3364
    LD D,$06
L_337B:
    CALL L_2845
    CALL NZ,L_345C
    POP HL
    POP BC
    JP M,L_33A0
    PUSH BC
    LD E,A
    LD A,B
    SUB D
    SUB E
    CALL P,L_34CF
    CALL L_34E6
    CALL L_3522
    OR E
    CALL NZ,L_34DF
    OR E
    CALL NZ,L_350E
    POP DE
    JP L_32F3
L_33A0:
    LD E,A
    LD A,C
    OR A
    CALL NZ,L_2FCB
    ADD A,E
    JP M,L_33AB
    XOR A
L_33AB:
    PUSH BC
    PUSH AF
L_33AD:
    CALL M,L_2FCD
    JP M,L_33AD
    POP BC
    LD A,E
    SUB B
    POP BC
    LD E,A
    ADD A,D
    LD A,B
    JP M,L_33C9
    SUB D
    SUB E
    CALL P,L_34CF
    PUSH BC
    CALL L_34E6
    JP L_33DA
L_33C9:
    CALL L_34CF
    LD A,C
    CALL L_3512
    LD C,A
    XOR A
    SUB D
    SUB E
    CALL L_34CF
    PUSH BC
    LD B,A
    LD C,A
L_33DA:
    CALL L_3522
    POP BC
    OR C
    JP NZ,L_33E5
    LD HL,[TEMP2]
L_33E5:
    ADD A,E
    DEC A
    CALL P,L_34CF
    LD D,B
    JP L_32FC
L_33EE:
    PUSH HL
    PUSH DE
    CALL L_2A11
    POP DE
    XOR A
L_33F5:
    JP Z,L_33FB
    LD E,$10
    .byte $01
L_33FB:
    .byte $1E, $06
    CALL L_2845
    SCF
    CALL NZ,L_345C
    POP HL
    POP BC
    PUSH AF
    LD A,C
    OR A
    PUSH AF
    CALL NZ,L_2FCB
    ADD A,B
    LD C,A
    LD A,D
    AND $04
    CP $01
    SBC A,A
    LD D,A
    ADD A,C
    LD C,A
    SUB E
    PUSH AF
    PUSH BC
L_341B:
    CALL M,L_2FCD
    JP M,L_341B
    POP BC
    POP AF
    PUSH BC
    PUSH AF
    JP M,L_3429
    XOR A
L_3429:
    CPL
    INC A
    ADD A,B
    INC A
    ADD A,D
    LD B,A
    LD C,$00
    CALL L_3522
    POP AF
    CALL P,L_34D8
    CALL L_350E
    POP BC
    POP AF
    JP NZ,L_344C
    CALL L_281F
    LD A,[HL]
    CP $2E
    CALL NZ,L_28BE
    LD [TEMP2],HL
L_344C:
    POP AF
    JP C,L_3453
    ADD A,E
    SUB B
    SUB D
L_3453:
    PUSH BC
    CALL L_32AE
    EX DE,HL
    POP DE
    JP L_32FC
L_345C:
    PUSH DE
    XOR A
    PUSH AF
    CALL L_1D64
    JP PO,L_3480
L_3465:
    LD A,[D_0C07]
    CP $91
    JP NC,L_3480
    LD DE,$35F1
    LD HL,$0C0D
    CALL L_28C9
    CALL L_2D64
    POP AF
    SUB $0A
    PUSH AF
    JP L_3465
L_3480:
    CALL L_34B2
L_3483:
    CALL L_1D64
    JP PE,L_3495
    LD BC,$9143
    LD DE,$4FF9
    CALL L_2906
    JP L_349B
L_3495:
    LD DE,$35F9
    CALL L_2943
L_349B:
    JP P,L_34AE
    POP AF
    CALL L_2FBE
    PUSH AF
    JP L_3483
L_34A6:
    POP AF
    CALL L_2FCD
    PUSH AF
    CALL L_34B2
L_34AE:
    POP AF
    OR A
    POP DE
    RET
L_34B2:
    CALL L_1D64
    JP PE,L_34C4
    LD BC,$9474
    LD DE,$23F8
    CALL L_2906
    JP L_34CA
L_34C4:
    LD DE,$3601
    CALL L_2943
L_34CA:
    POP HL
    JP P,L_34A6
    JP [HL]
L_34CF:
    OR A
L_34D0:
    RET Z
    DEC A
    LD [HL],$30
    INC HL
    JP L_34D0
L_34D8:
    JP NZ,L_34DF
L_34DB:
    RET Z
    CALL L_350E
L_34DF:
    LD [HL],$30
    INC HL
    DEC A
    JP L_34DB
L_34E6:
    LD A,E
    ADD A,D
    INC A
    LD B,A
    INC A
L_34EB:
    SUB $03
    JP NC,L_34EB
    ADD A,$05
    LD C,A
L_34F3:
    LD A,[TEMP3]
    AND $40
    RET NZ
    LD C,A
    RET
L_34FB:
    DEC B
    JP P,L_350F
    LD [TEMP2],HL
    LD [HL],$2E
L_3504:
    INC HL
    LD [HL],$30
    INC B
    JP NZ,L_3504
    INC HL
    LD C,B
    RET
L_350E:
    DEC B
L_350F:
    JP NZ,L_351A
L_3512:
    LD [HL],$2E
    LD [TEMP2],HL
    INC HL
    LD C,B
    RET
L_351A:
    DEC C
    RET NZ
    LD [HL],$2C
    INC HL
    LD C,$03
    RET
L_3522:
    PUSH DE
    CALL L_1D64
    JP PO,L_3571
    PUSH BC
    PUSH HL
    CALL L_28F4
    LD HL,$3609
    CALL L_28EE
    CALL L_2C26
    XOR A
    CALL L_2ACF
    POP HL
    POP BC
    LD DE,$3619
    LD A,$0A
L_3542:
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    LD B,$2F
L_354B:
    INC B
    POP HL
    PUSH HL
    LD A,$9E
    CALL L_2CFF
    JP NC,L_354B
    POP HL
    LD A,$8E
    CALL L_2CFF
    EX DE,HL
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,L_3542
    PUSH BC
    PUSH HL
    LD HL,$0C00
    CALL L_28A6
    JP L_357E
L_3571:
    PUSH BC
    PUSH HL
    CALL L_2579
    LD A,$01
    CALL L_2A42
    CALL L_28A9
L_357E:
    POP HL
    POP BC
    XOR A
    LD DE,$365F
L_3584:
    CCF
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    CALL L_28B4
    POP HL
    LD B,$2F
L_3592:
    INC B
    LD A,E
    SUB [HL]
    LD E,A
    INC HL
    LD A,D
    SBC A,[HL]
    LD D,A
    INC HL
    LD A,C
    SBC A,[HL]
    LD C,A
    DEC HL
    DEC HL
    JP NC,L_3592
    CALL L_2642
    INC HL
    CALL L_28A9
    EX DE,HL
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    JP C,L_3584
    INC DE
    INC DE
    LD A,$04
    JP L_35C0
L_35BA:
    PUSH DE
    LD DE,$3665
    LD A,$05
L_35C0:
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    EX DE,HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    INC HL
    EX [SP],HL
    EX DE,HL
    LD HL,[D_0C04]
    LD B,$2F
L_35D3:
    INC B
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP NC,L_35D3
    ADD HL,DE
    LD [D_0C04],HL
    POP DE
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,L_35C0
    CALL L_350E
    LD [HL],A
    POP DE
    RET
    .byte $00, $00, $00, $00, $F9, $02, $15, $A2, $E1, $FF, $9F, $31, $A9, $5F, $63, $B2
    .byte $FE, $FF, $03, $BF, $C9, $1B, $0E, $B6, $00, $00, $00, $00, $00, $00, $00, $80
    .byte $00, $00, $04, $BF, $C9, $1B, $0E, $B6, $00, $80, $C6, $A4, $7E, $8D, $03, $00
    .byte $40, $7A, $10, $F3, $5A, $00, $00, $A0, $72, $4E, $18, $09, $00, $00, $10, $A5
    .byte $D4, $E8, $00, $00, $00, $E8, $76, $48, $17, $00, $00, $00, $E4, $0B, $54, $02
    .byte $00, $00, $00, $CA, $9A, $3B, $00, $00, $00, $00, $E1, $F5, $05, $00, $00, $00
    .byte $80, $96, $98, $00, $00, $00, $00, $40, $42, $0F, $00, $00, $00, $00, $A0, $86
    .byte $01, $10, $27, $00, $10, $27, $E8, $03, $64, $00, $0A, $00, $01, $00
L_366F:
    XOR A
    LD B,A
    .byte $C2
L_3672:
    LD B,$01
    PUSH BC
    CALL L_22DB
    POP BC
    LD DE,$0C15
    PUSH DE
    XOR A
    LD [DE],A
    DEC B
    INC B
    LD C,$06
    JP Z,L_368E
    LD C,$04
L_3688:
    ADD HL,HL
    ADC A,A
L_368A:
    ADD HL,HL
    ADC A,A
    ADD HL,HL
    ADC A,A
L_368E:
    ADD HL,HL
    ADC A,A
    OR A
    JP NZ,L_369F
    LD A,C
    DEC A
    JP Z,L_369F
    LD A,[DE]
    OR A
    JP Z,L_36AB
    XOR A
L_369F:
    ADD A,$30
    CP $3A
    JP C,L_36A8
    ADD A,$07
L_36A8:
    LD [DE],A
    INC DE
    LD [DE],A
L_36AB:
    XOR A
    DEC C
    JP Z,L_36B8
    DEC B
    INC B
    JP Z,L_368A
    JP L_3688
L_36B8:
    LD [DE],A
    POP HL
    RET
L_36BB:
    LD HL,$2874
    EX [SP],HL
    JP [HL]
FN_SQR:
    CALL L_2899
    LD HL,$360D
    CALL L_28A6
    JP L_36CF
    .byte $CD, $F4, $29
L_36CF:
    POP BC
    POP DE
    LD HL,$2572
    PUSH HL
    LD A,$01
    LD [D_0C09],A
    CALL L_2845
    LD A,B
    JP Z,FN_EXP
    JP P,L_36E8
    OR A
    JP Z,L_3097
L_36E8:
    OR A
    JP Z,L_25F0
    PUSH DE
    PUSH BC
    LD A,C
    OR $7F
    CALL L_28B4
    JP P,L_3713
    PUSH AF
    LD A,[D_0C07]
    CP $99
    JP C,L_3704
    POP AF
    JP L_3713
L_3704:
    POP AF
    PUSH DE
    PUSH BC
    CALL L_2A8D
    POP BC
    POP DE
    PUSH AF
    CALL L_2906
    POP HL
    LD A,H
    RRA
L_3713:
    POP HL
    LD [D_0C06],HL
    POP HL
    LD [D_0C04],HL
    CALL C,L_36BB
    CALL Z,L_2874
    PUSH DE
    PUSH BC
    CALL FN_LOG
    POP BC
    POP DE
    CALL L_2703
FN_EXP:
    LD BC,$8138
    LD DE,$AA3B
    CALL L_2703
    LD A,[D_0C07]
    CP $88
    JP NC,L_3760
    CP $68
    JP C,L_3772
    CALL L_2899
    CALL L_2A8D
    ADD A,$81
    POP BC
    POP DE
    JP Z,L_3763
    PUSH AF
    CALL L_2585
    LD HL,$377B
    CALL L_37A7
    POP BC
    LD DE,$0000
    LD C,D
    JP L_2703
L_3760:
    CALL L_2899
L_3763:
    LD A,[D_0C06]
    OR A
    JP P,L_376F
    POP AF
    POP AF
    JP L_25EF
L_376F:
    JP L_307E
L_3772:
    LD BC,$8100
    LD DE,$0000
    JP L_28A9
    .byte $07, $7C, $88, $59, $74, $E0, $97, $26, $77, $C4, $1D, $1E, $7A, $5E, $50, $63
    .byte $7C, $1A, $FE, $75, $7E, $18, $72, $31, $80, $00, $00, $00, $81
L_3798:
    CALL L_2899
    LD DE,$2B95
    PUSH DE
    PUSH HL
    CALL L_28B4
    CALL L_2703
    POP HL
L_37A7:
    CALL L_2899
    LD A,[HL]
    INC HL
    CALL L_28A6
    .byte $06
L_37B0:
    .byte $F1
    POP BC
    POP DE
    DEC A
    RET Z
    PUSH DE
    PUSH BC
    PUSH AF
    PUSH HL
    CALL L_2703
    POP HL
    CALL L_28B7
    PUSH HL
    CALL L_2588
    POP HL
    JP L_37B0
    .byte $52, $C7, $4F, $80
L_37CC:
    CALL CHRGTR
L_37CF:
    PUSH HL
    LD HL,$2697
    CALL L_28A6
    CALL FN_RND
    POP HL
    JP L_2A36
FN_RND:
    CALL L_2845
    LD HL,$3848
    JP M,L_383E
    LD HL,$3869
    CALL L_28A6
    LD HL,$3848
    RET Z
    ADD A,[HL]
    AND $07
    LD B,$00
    LD [HL],A
    INC HL
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL L_28B7
    CALL L_2703
    LD A,[D_3847]
    INC A
    AND $03
    LD B,$00
    CP $01
    ADC A,B
    LD [D_3847],A
    LD HL,$3869
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL L_257C
L_3819:
    CALL L_28B4
    LD A,E
    LD E,C
    XOR $4F
    LD C,A
    LD [HL],$80
    DEC HL
    LD B,[HL]
    LD [HL],$80
    LD HL,$3846
    INC [HL]
    LD A,[HL]
    SUB $AB
    JP NZ,L_3835
    LD [HL],A
    INC C
    DEC D
    INC E
L_3835:
    CALL L_25DA
    LD HL,$3869
    JP L_28C0
L_383E:
    LD [HL],A
    DEC HL
    LD [HL],A
    DEC HL
    LD [HL],A
    JP L_3819
    .byte $00
D_3847:
    .byte $00, $00, $35, $4A, $CA, $99, $39, $1C, $76, $98, $22, $95, $B3, $98, $0A, $DD
    .byte $47, $98, $53, $D1, $99, $99, $0A, $1A, $9F, $98, $65, $BC, $CD, $98, $D6, $77
    .byte $3E, $98, $52
D_386A:
    .byte $C7, $4F, $80, $68, $B1, $46, $68, $99, $E9, $92, $69, $10, $D1, $75, $68
FN_COS:
    LD HL,$38FF
    CALL L_257C
FN_SIN:
    LD A,[D_0C07]
    CP $77
    RET C
    LD A,[D_0C06]
    OR A
    JP P,L_3895
    AND $7F
    LD [D_0C06],A
    LD DE,$2874
    PUSH DE
L_3895:
    LD BC,$7E22
    LD DE,$F983
    CALL L_2703
    CALL L_2899
    CALL L_2A8D
    POP BC
    POP DE
    CALL L_2585
    LD BC,$7F00
    LD DE,$0000
    CALL L_2906
    JP M,L_38D9
    LD BC,$7F80
    LD DE,$0000
    CALL L_2588
    LD BC,$8080
    LD DE,$0000
    CALL L_2588
    CALL L_2845
    CALL P,L_2874
    LD BC,$7F00
    LD DE,$0000
    CALL L_2588
    CALL L_2874
L_38D9:
    LD A,[D_0C06]
    OR A
    PUSH AF
    JP P,L_38E6
    XOR $80
    LD [D_0C06],A
L_38E6:
    LD HL,$3907
    CALL L_3798
    POP AF
    RET P
    LD A,[D_0C06]
    XOR $80
    LD [D_0C06],A
    RET
    .byte $00, $00, $00, $00, $83, $F9, $22, $7E, $DB, $0F, $49, $81, $00, $00, $00, $7F
    .byte $05, $FB, $D7, $1E, $86, $65, $26, $99, $87, $58, $34, $23, $87, $E1, $5D, $A5
    .byte $86, $DB, $0F, $49, $83
FN_TAN:
    CALL L_2899
    CALL FN_SIN
    POP BC
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    CALL FN_COS
    JP L_2767
FN_ATN:
    CALL L_2845
    CALL M,L_36BB
    CALL M,L_2874
    LD A,[D_0C07]
    CP $81
    JP C,L_394E
    LD BC,$8100
    LD D,C
    LD E,C
    CALL L_2769
    LD HL,$2582
    PUSH HL
L_394E:
    LD HL,$3958
    CALL L_3798
    LD HL,$38FF
    RET
    .byte $09, $4A, $D7, $3B, $78, $02, $6E, $84, $7B, $FE, $C1, $2F, $7C, $74, $31, $9A
    .byte $7D, $84, $3D, $5A, $7D, $C8, $7F, $91, $7E, $E4, $BB, $4C, $7E, $6C, $AA, $AA
    .byte $7F, $00, $00, $00, $81, $2B, $CD, $05, $13, $C8, $CD, $D3, $43, $2C
ST_DIM:
    LD BC,$397D
    PUSH BC
    .byte $F6
L_398B:
    .byte $AF
    LD [D_0A66],A
    LD C,[HL]
L_3990:
    CALL L_4503
    JP C,SNERR
    XOR A
    LD B,A
    LD [D_07C5],A
    INC HL
    LD A,[HL]
    CP $2E
    JP C,L_39E3
    JP Z,L_39B5
    CP $3A
    JP NC,L_39AF
    CP $30
    JP NC,L_39B5
L_39AF:
    CALL L_4504
    JP C,L_39E3
L_39B5:
    LD B,A
    PUSH BC
    LD B,$FF
    LD DE,$07C5
L_39BC:
    OR $80
    INC B
    LD [DE],A
    INC DE
    INC HL
    LD A,[HL]
    CP $3A
    JP NC,L_39CD
    CP $30
    JP NC,L_39BC
L_39CD:
    CALL L_4504
    JP NC,L_39BC
    CP $2E
    JP Z,L_39BC
    LD A,B
    CP $27
    JP NC,SNERR
    POP BC
    LD [D_07C5],A
    LD A,[HL]
L_39E3:
    CP $26
    JP NC,L_39FF
    LD DE,$3A0D
    PUSH DE
    LD D,$02
    CP $25
    RET Z
    INC D
    CP $24
    RET Z
    INC D
    CP $21
    RET Z
    LD D,$08
    CP $23
    RET Z
    POP AF
L_39FF:
    LD A,C
    AND $7F
    LD E,A
    LD D,$00
    PUSH HL
    LD HL,$0A89
    ADD HL,DE
    LD D,[HL]
    POP HL
    DEC HL
    LD A,D
    LD [D_0A67],A
    CALL CHRGTR
    LD A,[SUBFLG]
    DEC A
    JP Z,L_3B92
    JP P,L_3A29
    LD A,[HL]
    SUB $28
    JP Z,L_3B16
    SUB $33
    JP Z,L_3B16
L_3A29:
    XOR A
    LD [SUBFLG],A
    PUSH HL
    LD A,[D_0BB7]
    OR A
    LD [D_0BB4],A
    JP Z,L_3A7D
    LD HL,[D_0AE6]
    LD DE,$0AE8
    ADD HL,DE
    LD [D_0BB5],HL
    EX DE,HL
    JP L_3A63
L_3A46:
    LD A,[DE]
    LD L,A
    INC DE
    LD A,[DE]
    INC DE
    CP C
    JP NZ,L_3A5B
    LD A,[D_0A67]
    CP L
    JP NZ,L_3A5B
    LD A,[DE]
    CP B
    JP Z,L_3AE5
L_3A5B:
    INC DE
L_3A5C:
    LD A,[DE]
L_3A5D:
    LD H,$00
    ADD A,L
    INC A
    LD L,A
    ADD HL,DE
L_3A63:
    EX DE,HL
    LD A,[D_0BB5]
    CP E
    JP NZ,L_3A46
    LD A,[D_0BB6]
    CP D
    JP NZ,L_3A46
    LD A,[D_0BB4]
    OR A
    JP Z,L_3A92
    XOR A
    LD [D_0BB4],A
L_3A7D:
    LD HL,[ARYTAB]
    LD [D_0BB5],HL
    LD HL,[VARTAB]
    JP L_3A63
L_3A89:
    CALL L_398B
    RET
L_3A8D:
    LD D,A
    LD E,A
    POP BC
    EX [SP],HL
    RET
L_3A92:
    POP HL
    EX [SP],HL
    PUSH DE
    LD DE,$3A8C
    CALL L_43CD
    JP Z,L_3A8D
    LD DE,$1C4D
    CALL L_43CD
    POP DE
    JP Z,L_3B00
    EX [SP],HL
    PUSH HL
    PUSH BC
    LD A,[D_0A67]
    LD B,A
    LD A,[D_07C5]
    ADD A,B
    INC A
    LD C,A
    PUSH BC
    LD B,$00
    INC BC
    INC BC
    INC BC
    LD HL,[STREND]
    PUSH HL
    ADD HL,BC
    POP BC
    PUSH HL
    CALL L_42B6
    POP HL
    LD [STREND],HL
    LD H,B
    LD L,C
    LD [ARYTAB],HL
L_3ACE:
    DEC HL
    LD [HL],$00
    CALL L_43CD
    JP NZ,L_3ACE
    POP DE
    LD [HL],D
    INC HL
    POP DE
    LD [HL],E
    INC HL
    LD [HL],D
    CALL L_3CA3
    EX DE,HL
    INC DE
    POP HL
    RET
L_3AE5:
    INC DE
    LD A,[D_07C5]
    LD H,A
    LD A,[DE]
    CP H
    JP NZ,L_3A5C
    OR A
    JP NZ,L_3AF6
    INC DE
    POP HL
    RET
L_3AF6:
    EX DE,HL
    CALL L_3CB8
    EX DE,HL
    JP NZ,L_3A5D
    POP HL
    RET
L_3B00:
    LD [D_0C07],A
    LD H,A
    LD L,A
    LD [D_0C04],HL
    CALL L_1D64
    JP NZ,L_3B14
    LD HL,$0C44
    LD [D_0C04],HL
L_3B14:
    POP HL
    RET
L_3B16:
    PUSH HL
    LD HL,[D_0A66]
    EX [SP],HL
    LD D,A
L_3B1C:
    PUSH DE
    PUSH BC
    LD DE,$07C5
    LD A,[DE]
    OR A
    JP Z,L_3B58
    EX DE,HL
    ADD A,$02
    RRA
    LD C,A
    CALL L_42C7
    LD A,C
L_3B2F:
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,L_3B2F
    PUSH HL
    LD A,[D_07C5]
    PUSH AF
    EX DE,HL
    CALL L_1411
    POP AF
    LD [D_07EC],HL
    POP HL
    ADD A,$02
    RRA
L_3B49:
    POP BC
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC A
    JP NZ,L_3B49
    LD HL,[D_07EC]
    JP L_3B5F
L_3B58:
    CALL L_1411
    XOR A
    LD [D_07C5],A
L_3B5F:
    LD A,[D_0BC6]
    OR A
    JP Z,L_3B6C
    LD A,D
    OR E
    JP Z,L_3BD6
    DEC DE
L_3B6C:
    POP BC
    POP AF
    EX DE,HL
    EX [SP],HL
    PUSH HL
    EX DE,HL
    INC A
    LD D,A
    LD A,[HL]
    CP $2C
    JP Z,L_3B1C
    CP $29
    JP Z,L_3B84
    CP $5D
    JP NZ,SNERR
L_3B84:
    CALL CHRGTR
    LD [TEMP2],HL
    POP HL
    LD [D_0A66],HL
    LD E,$00
    PUSH DE
    .byte $11
L_3B92:
    PUSH HL
    PUSH AF
    LD HL,[ARYTAB]
    .byte $3E
L_3B98:
    .byte $19
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_3BF0
    LD E,[HL]
    INC HL
    LD A,[HL]
    INC HL
    CP C
    JP NZ,L_3BB8
    LD A,[D_0A67]
    CP E
    JP NZ,L_3BB8
    LD A,[HL]
    CP B
    JP Z,L_3BDC
L_3BB8:
    INC HL
L_3BB9:
    LD E,[HL]
    INC E
    LD D,$00
    ADD HL,DE
L_3BBE:
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    JP NZ,L_3B98
    LD A,[D_0A66]
    OR A
    JP NZ,DDERR
    POP AF
    LD B,H
    LD C,L
    JP Z,L_2757
    SUB [HL]
    JP Z,L_3C5D
L_3BD6:
    LD DE,$0009
    JP ERROR
L_3BDC:
    INC HL
    LD A,[D_07C5]
    CP [HL]
    JP NZ,L_3BB9
    INC HL
    OR A
    JP Z,L_3BBE
    DEC HL
    CALL L_3CB8
    JP L_3BBE
L_3BF0:
    LD A,[D_0A67]
    LD [HL],A
    INC HL
    LD E,A
    LD D,$00
    POP AF
    JP Z,L_3C96
    LD [HL],C
    INC HL
    LD [HL],B
    CALL L_3CA3
    INC HL
    LD C,A
    CALL L_42C7
    INC HL
    INC HL
    LD [TEMP3],HL
    LD [HL],C
    INC HL
    LD A,[D_0A66]
    RLA
    LD A,C
L_3C13:
    JP C,L_3C23
    PUSH AF
    LD A,[D_0BC6]
    XOR $0B
    LD C,A
    LD B,$00
    POP AF
    JP NC,L_3C25
L_3C23:
    POP BC
    INC BC
L_3C25:
    LD [HL],C
    PUSH AF
    INC HL
    LD [HL],B
    INC HL
    CALL L_2B05
    POP AF
    DEC A
    JP NZ,L_3C13
    PUSH AF
    LD B,D
    LD C,E
    EX DE,HL
    ADD HL,DE
    JP C,L_42DD
    CALL L_42EB
    LD [STREND],HL
L_3C40:
    DEC HL
    LD [HL],$00
    CALL L_43CD
    JP NZ,L_3C40
    INC BC
    LD D,A
    LD HL,[TEMP3]
    LD E,[HL]
    EX DE,HL
    ADD HL,HL
    ADD HL,BC
    EX DE,HL
    DEC HL
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    POP AF
    JP C,L_3C92
L_3C5D:
    LD B,A
    LD C,A
    LD A,[HL]
    INC HL
    .byte $16
L_3C62:
    .byte $E1
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL
    PUSH AF
    CALL L_43CD
    JP NC,L_3BD6
    CALL L_2B05
    ADD HL,DE
    POP AF
    DEC A
    LD B,H
    LD C,L
    JP NZ,L_3C62
    LD A,[D_0A67]
    LD B,H
    LD C,L
    ADD HL,HL
    SUB $04
    JP C,L_3C8A
    ADD HL,HL
    JP Z,L_3C8F
    ADD HL,HL
L_3C8A:
    OR A
    JP PO,L_3C8F
    ADD HL,BC
L_3C8F:
    POP BC
    ADD HL,BC
    EX DE,HL
L_3C92:
    LD HL,[TEMP2]
    RET
L_3C96:
    SCF
    SBC A,A
    POP HL
    RET
L_3C9A:
    LD A,[HL]
    INC HL
L_3C9C:
    PUSH BC
    LD B,$00
    LD C,A
    ADD HL,BC
    POP BC
    RET
L_3CA3:
    PUSH BC
    PUSH DE
    PUSH AF
    LD DE,$07C5
    LD A,[DE]
    LD B,A
    INC B
L_3CAC:
    LD A,[DE]
    INC DE
    INC HL
    LD [HL],A
    DEC B
    JP NZ,L_3CAC
    POP AF
    POP DE
    POP BC
    RET
L_3CB8:
    PUSH DE
    PUSH BC
    LD DE,$07C6
    LD B,A
    INC HL
    INC B
L_3CC0:
    DEC B
    JP Z,L_3CD2
    LD A,[DE]
    INC DE
    CP [HL]
    INC HL
    JP Z,L_3CC0
    LD A,B
    DEC A
    CALL NZ,L_3C9C
    XOR A
    DEC A
L_3CD2:
    POP BC
    POP DE
    RET
L_3CD5:
    LD [D_078A],A
    LD HL,[ERRLIN]
    OR H
    AND L
    INC A
    EX DE,HL
    RET Z
    JP L_3CE7
ST_EDIT:
    CALL L_141D
    RET NZ
L_3CE7:
    POP HL
L_3CE8:
    EX DE,HL
    LD [DOT],HL
    EX DE,HL
    CALL L_0EF8
    JP NC,L_14CC
    LD H,B
    LD L,C
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    CALL L_20E6
L_3CFF:
    POP HL
L_3D00:
    PUSH HL
    LD A,H
    AND L
    INC A
    LD A,$21
    CALL Z,OUTDO
    CALL NZ,LINPRT
    LD A,$20
    CALL OUTDO
    LD HL,$0962
    PUSH HL
    LD C,$FF
L_3D17:
    INC C
    LD A,[HL]
    INC HL
    OR A
    JP NZ,L_3D17
    POP HL
    LD B,A
    LD D,$00
L_3D22:
    CALL L_41F5
    OR A
    JP Z,L_3D22
    CALL L_1C5B
    SUB $30
    JP C,L_3D41
    CP $0A
    JP NC,L_3D41
    LD E,A
    LD A,D
    RLCA
    RLCA
    ADD A,D
    RLCA
    ADD A,E
    LD D,A
    JP L_3D22
L_3D41:
    PUSH HL
    LD HL,$3D20
    EX [SP],HL
    DEC D
    INC D
    JP NZ,L_3D4C
    INC D
L_3D4C:
    CP $D8
    JP Z,L_3EBA
    CP $4F
    JP Z,L_3EC9
    CP $DD
    JP Z,L_3ED7
    CP $F0
    JP Z,L_3DA8
    CP $31
    JP C,L_3D67
    SUB $20
L_3D67:
    CP $21
    JP Z,L_3EEC
    CP $1C
    JP Z,L_3DE2
    CP $23
    JP Z,L_3DBB
    CP $19
    JP Z,L_3E3E
    CP $14
    JP Z,L_3DEC
    CP $13
    JP Z,L_3E09
    CP $15
    JP Z,L_3EDA
    CP $28
    JP Z,L_3E39
    CP $1B
    JP Z,L_3DB5
    CP $18
    JP Z,L_3E36
    CP $11
    LD A,$07
    JP NZ,OUTDO
    POP BC
    POP DE
    CALL L_4221
    JP L_3CE8
L_3DA8:
    LD A,[HL]
    OR A
    RET Z
    INC B
    CALL L_42A5
    INC HL
    DEC D
    JP NZ,L_3DA8
    RET
L_3DB5:
    PUSH HL
    LD HL,$3E03
    EX [SP],HL
    SCF
L_3DBB:
    PUSH AF
    CALL L_41F5
    LD E,A
    POP AF
    PUSH AF
    CALL C,L_3E03
L_3DC5:
    LD A,[HL]
    OR A
    JP Z,L_3DE0
    CALL L_42A5
    POP AF
    PUSH AF
    CALL C,L_3E81
    JP C,L_3DD7
    INC HL
    INC B
L_3DD7:
    LD A,[HL]
    CP E
    JP NZ,L_3DC5
    DEC D
    JP NZ,L_3DC5
L_3DE0:
    POP AF
    RET
L_3DE2:
    CALL L_20DC
    CALL L_4221
    POP BC
    JP L_3CFF
L_3DEC:
    LD A,[HL]
    OR A
    RET Z
    LD A,$5C
    CALL L_42A5
L_3DF4:
    LD A,[HL]
    OR A
    JP Z,L_3E03
    CALL L_42A5
    CALL L_3E81
    DEC D
    JP NZ,L_3DF4
L_3E03:
    LD A,$5C
    CALL OUTDO
    RET
L_3E09:
    LD A,[HL]
    OR A
    RET Z
L_3E0C:
    CALL L_41F5
    CP $20
    JP NC,L_3E2B
    CP $0A
    JP Z,L_3E2B
    CP $07
    JP Z,L_3E2B
    CP $09
    JP Z,L_3E2B
    LD A,$07
    CALL OUTDO
    JP L_3E0C
L_3E2B:
    LD [HL],A
    CALL L_42A5
    INC HL
    INC B
    DEC D
    JP NZ,L_3E09
    RET
L_3E36:
    LD [HL],$00
    LD C,B
L_3E39:
    LD D,$FF
    CALL L_3DA8
L_3E3E:
    CALL L_41F5
    CP $7F
    JP Z,L_3E71
    CP $08
    JP Z,L_3E73
    CP $0D
    JP Z,L_3ED7
    CP $1B
    RET Z
    CP $08
    JP Z,L_3E73
    CP $0A
    JP Z,L_3E91
    CP $07
    JP Z,L_3E91
    CP $09
    JP Z,L_3E91
    CP $20
    JP C,L_3E3E
    CP $5F
    JP NZ,L_3E91
L_3E71:
    LD A,$5F
L_3E73:
    DEC B
    INC B
    JP Z,L_3E99
    CALL L_42A5
    DEC HL
    DEC B
    LD DE,$3E3E
    PUSH DE
L_3E81:
    PUSH HL
    DEC C
L_3E83:
    LD A,[HL]
    OR A
    SCF
    JP Z,L_2757
    INC HL
    LD A,[HL]
    DEC HL
    LD [HL],A
    INC HL
    JP L_3E83
L_3E91:
    PUSH AF
    LD A,C
    CP $FF
    JP C,L_3EA1
    POP AF
L_3E99:
    LD A,$07
    CALL OUTDO
L_3E9E:
    JP L_3E3E
L_3EA1:
    SUB B
    INC C
    INC B
    PUSH BC
    EX DE,HL
    LD L,A
    LD H,$00
    ADD HL,DE
    LD B,H
    LD C,L
    INC HL
    CALL L_42B9
    POP BC
    POP AF
    LD [HL],A
    CALL L_42A5
    INC HL
    JP L_3E9E
L_3EBA:
    LD A,B
    OR A
    RET Z
    DEC HL
    LD A,$08
    CALL L_42A5
    DEC B
    DEC D
    JP NZ,L_3EC9
    RET
L_3EC9:
    LD A,B
    OR A
    RET Z
    DEC B
    DEC HL
    LD A,[HL]
    CALL L_42A5
    DEC D
    JP NZ,L_3EC9
    RET
L_3ED7:
    CALL L_20DC
L_3EDA:
    CALL L_4221
    POP BC
    POP DE
    LD A,D
    AND E
    INC A
L_3EE2:
    LD HL,$0961
    RET Z
    SCF
    PUSH AF
    INC HL
    JP L_0E14
L_3EEC:
    POP BC
    POP DE
    LD A,D
    AND E
    INC A
    JP Z,L_421C
    JP READY
L_3EF7:
    CALL L_1A03
    CALL L_2A3B
    CALL L_43D3
    DEC SP
    EX DE,HL
    LD HL,[D_0C04]
    JP L_3F11
L_3F08:
    LD A,[FLGINP]
    OR A
    JP Z,L_3F1B
    POP DE
    EX DE,HL
L_3F11:
    PUSH HL
    XOR A
    LD [FLGINP],A
    INC A
    PUSH AF
    PUSH DE
    LD B,[HL]
    OR B
L_3F1B:
    JP Z,L_1418
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    JP L_3F45
L_3F26:
    LD E,B
    PUSH HL
    LD C,$02
L_3F2A:
    LD A,[HL]
    INC HL
    CP $5C
    JP Z,L_4091
    CP $20
    JP NZ,L_3F3B
    INC C
    DEC B
    JP NZ,L_3F2A
L_3F3B:
    POP HL
    LD B,E
    LD A,$5C
L_3F3F:
    CALL L_40CC
    CALL OUTDO
L_3F45:
    XOR A
    LD E,A
    LD D,A
L_3F48:
    CALL L_40CC
    LD D,A
    LD A,[HL]
    INC HL
    CP $21
    JP Z,L_408E
    CP $23
    JP Z,L_3FA1
    CP $26
    JP Z,L_4089
    DEC B
    JP Z,L_4067
    CP $2B
    LD A,$08
    JP Z,L_3F48
    DEC HL
    LD A,[HL]
    INC HL
    CP $2E
    JP Z,L_3FC0
    CP $5F
    JP Z,L_407D
    CP $5C
    JP Z,L_3F26
    CP [HL]
    JP NZ,L_3F3F
    CP $24
    JP Z,L_3F9A
    CP $2A
    JP NZ,L_3F3F
    LD A,B
    INC HL
    CP $02
    JP C,L_3F92
    LD A,[HL]
    CP $24
L_3F92:
    LD A,$20
    JP NZ,L_3F9E
    DEC B
    INC E
    .byte $FE
L_3F9A:
    .byte $AF
    ADD A,$10
    INC HL
L_3F9E:
    INC E
    ADD A,D
    LD D,A
L_3FA1:
    INC E
    LD C,$00
    DEC B
    JP Z,L_3FF6
    LD A,[HL]
    INC HL
    CP $2E
    JP Z,L_3FCB
    CP $23
    JP Z,L_3FA1
    CP $2C
    JP NZ,L_3FD7
    LD A,D
    OR $40
    LD D,A
    JP L_3FA1
L_3FC0:
    LD A,[HL]
    CP $23
    LD A,$2E
    JP NZ,L_3F3F
    LD C,$01
    INC HL
L_3FCB:
    INC C
    DEC B
    JP Z,L_3FF6
    LD A,[HL]
    INC HL
    CP $23
    JP Z,L_3FCB
L_3FD7:
    PUSH DE
    LD DE,$3FF4
    PUSH DE
    LD D,H
    LD E,L
    CP $5E
    RET NZ
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    LD A,B
    SUB $04
    RET C
    POP DE
    POP DE
    LD B,A
    INC D
    INC HL
    JP Z,L_D1EB
L_3FF6:
    LD A,D
    DEC HL
    INC E
    AND $08
    JP NZ,L_4016
    DEC E
    LD A,B
    OR A
    JP Z,L_4016
    LD A,[HL]
    SUB $2D
    JP Z,L_4011
    CP $FE
    JP NZ,L_4016
    LD A,$08
L_4011:
    ADD A,$04
    ADD A,D
    LD D,A
    DEC B
L_4016:
    POP HL
    POP AF
    JP Z,L_4072
    PUSH BC
    PUSH DE
    CALL L_1A02
    POP DE
    POP BC
    PUSH BC
    PUSH HL
    LD B,E
    LD A,B
    ADD A,C
    CP $19
    JP NC,L_1418
    LD A,D
    OR $80
    CALL L_312A
    CALL L_4723
L_4035:
    POP HL
    DEC HL
    CALL CHRGTR
    SCF
    JP Z,L_404E
    LD [FLGINP],A
    CP $3B
    JP Z,L_404B
    CP $2C
    JP NZ,SNERR
L_404B:
    CALL CHRGTR
L_404E:
    POP BC
    EX DE,HL
    POP HL
    PUSH HL
    PUSH AF
    PUSH DE
    LD A,[HL]
    SUB B
    INC HL
    LD D,$00
    LD E,A
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    ADD HL,DE
L_405F:
    LD A,B
    OR A
    JP NZ,L_3F45
    JP L_406D
L_4067:
    CALL L_40CC
    CALL OUTDO
L_406D:
    POP HL
    POP AF
    JP NZ,L_3F08
L_4072:
    CALL C,L_4221
    EX [SP],HL
    CALL L_48AB
    POP HL
    JP L_17E9
L_407D:
    CALL L_40CC
    DEC B
    LD A,[HL]
    INC HL
    CALL OUTDO
    JP L_405F
L_4089:
    LD C,$00
    JP L_4092
L_408E:
    LD C,$01
    .byte $3E
L_4091:
    POP AF
L_4092:
    DEC B
    CALL L_40CC
    POP HL
    POP AF
    JP Z,L_4072
    PUSH BC
    CALL L_1A02
    CALL L_2A3B
    POP BC
    PUSH BC
    PUSH HL
    LD HL,[D_0C04]
    LD B,C
    LD C,$00
    LD A,B
    PUSH AF
    LD A,B
    OR A
    CALL NZ,L_494F
    CALL L_4726
    LD HL,[D_0C04]
    POP AF
    OR A
    JP Z,L_4035
    SUB [HL]
    LD B,A
    LD A,$20
    INC B
L_40C2:
    DEC B
    JP Z,L_4035
    CALL OUTDO
    JP L_40C2
L_40CC:
    PUSH AF
    LD A,D
    OR A
    LD A,$2B
    CALL NZ,OUTDO
    POP AF
    RET
OUTDO:
    PUSH AF
    PUSH HL
    CALL L_4654
    JP NZ,L_5666
    POP HL
    LD A,[D_078D]
    OR A
    JP Z,L_415C
    POP AF
    PUSH AF
    CP $08
    JP NZ,L_40FC
    LD A,[D_078C]
    SUB $01
    JP C,L_40F8
    LD [D_078C],A
L_40F8:
    POP AF
    JP L_4137
L_40FC:
    CP $09
    JP NZ,L_4110
L_4101:
    LD A,$20
    CALL OUTDO
    LD A,[D_078C]
    AND $07
    JP NZ,L_4101
    POP AF
    RET
L_4110:
    POP AF
    PUSH AF
    SUB $0D
    JP Z,L_4133
    JP C,L_4136
    LD A,[D_078F]
    INC A
    LD A,[D_078C]
    JP Z,L_412D
    PUSH HL
    LD HL,$078F
    CP [HL]
    POP HL
    CALL Z,L_414D
L_412D:
    CP $FF
    JP Z,L_4136
    INC A
L_4133:
    LD [D_078C],A
L_4136:
    POP AF
L_4137:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
    .byte $CD
D_413D:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    POP AF
    RET
L_4144:
    XOR A
    LD [D_078D],A
    LD A,[D_078C]
    OR A
    RET Z
L_414D:
    LD A,$0D
    CALL L_4137
    LD A,$0A
    CALL L_4137
    XOR A
    LD [D_078C],A
    RET
L_415C:
    LD A,[D_0793]
    OR A
    JP NZ,L_4758
    POP AF
    PUSH BC
    PUSH AF
    CP $08
    JP NZ,L_417B
    LD A,[D_0A65]
    OR A
    JP Z,L_418D
    DEC A
    LD [D_0A65],A
    LD A,$08
    JP L_41AE
L_417B:
    CP $09
    JP NZ,L_4190
L_4180:
    LD A,$20
    CALL OUTDO
    LD A,[D_0A65]
    AND $07
    JP NZ,L_4180
L_418D:
    POP AF
    POP BC
    RET
L_4190:
    CP $20
    JP C,L_41AE
    LD A,[D_0790]
    LD B,A
    LD A,[D_0A65]
    INC B
    JP Z,L_41A5
    DEC B
    CP B
    CALL Z,L_4221
L_41A5:
    CP $FF
    JP Z,L_41AE
    INC A
    LD [D_0A65],A
L_41AE:
    POP AF
    POP BC
    PUSH AF
    POP AF
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
    .byte $CD
D_41B8:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    POP AF
    RET
L_41BF:
    CALL L_4654
    JP Z,L_41F5
    CALL L_57C2
    RET NC
    PUSH BC
    PUSH DE
    PUSH HL
    CALL L_534D
    POP HL
    POP DE
    POP BC
    LD A,[D_0BF3]
    OR A
    JP NZ,L_5030
    LD A,[D_079E]
    OR A
    JP Z,L_41E7
    LD HL,$12A0
    PUSH HL
    JP L_4337
L_41E7:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,$0C45
    CALL L_4723
    POP DE
    POP BC
    XOR A
    POP HL
    RET
L_41F5:
    PUSH BC
    PUSH DE
    PUSH HL
    .byte $CD
D_41F9:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    AND $7F
    CP $0F
    RET NZ
    LD A,[D_0793]
    OR A
    CALL Z,L_4441
    CPL
    LD [D_0793],A
    OR A
    JP Z,L_4441
    XOR A
    RET
L_4214:
    LD A,[D_0A65]
    OR A
    RET Z
    JP L_4221
L_421C:
    LD [HL],$00
    LD HL,$0961
L_4221:
    LD A,$0D
    CALL OUTDO
    LD A,$0A
    CALL OUTDO
L_422B:
    CALL L_4654
    JP Z,L_4233
    XOR A
    RET
L_4233:
    LD A,[D_078D]
    OR A
    JP Z,L_423F
    XOR A
    LD [D_078C],A
    RET
L_423F:
    XOR A
    LD [D_0A65],A
    LD A,[D_0788]
L_4246:
    DEC A
    RET Z
    PUSH AF
    XOR A
    CALL OUTDO
    POP AF
    JP L_4246
L_4251:
    PUSH BC
    PUSH DE
    PUSH HL
    .byte $CD
D_4255:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    OR A
    RET Z
L_425C:
    CALL L_41F5
    CP $13
    CALL Z,L_41F5
    LD [D_0789],A
    CP $03
    CALL Z,L_4443
    JP ST_STOP
L_426F:
    CALL CHRGTR
    PUSH HL
    CALL L_4299
    JP NZ,L_4283
    .byte $CD
D_427A:
    .byte $00, $00
    OR A
    JP Z,L_428C
    CALL L_41F5
L_4283:
    PUSH AF
    CALL L_46B7
    POP AF
    LD E,A
    CALL L_48F8
L_428C:
    LD HL,$0C44
    LD [D_0C04],HL
    LD A,$03
    LD [D_0A67],A
    POP HL
    RET
L_4299:
    LD A,[D_0789]
    OR A
    RET Z
    PUSH AF
    XOR A
    LD [D_0789],A
    POP AF
    RET
L_42A5:
    CALL OUTDO
    CP $0A
    RET NZ
    LD A,$0D
    CALL OUTDO
    CALL L_422B
    LD A,$0A
    RET
L_42B6:
    CALL L_42EB
L_42B9:
    PUSH BC
    EX [SP],HL
    POP BC
L_42BC:
    CALL L_43CD
    LD A,[HL]
    LD [BC],A
    RET Z
    DEC BC
    DEC HL
    JP L_42BC
L_42C7:
    PUSH HL
    LD HL,[MEMSIZ]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    LD A,$C6
    SUB L
    LD L,A
    LD A,$FF
    SBC A,H
    LD H,A
    JP C,L_42DD
    ADD HL,SP
    POP HL
    RET C
L_42DD:
    LD HL,[TOPMEM]
    DEC HL
    DEC HL
    LD [SAVSTK],HL
L_42E5:
    LD DE,$0007
    JP ERROR
L_42EB:
    CALL L_42FF
    RET NC
    PUSH BC
    PUSH DE
    PUSH HL
    CALL L_4767
    POP HL
    POP DE
    POP BC
    CALL L_42FF
    RET NC
    JP L_42E5
L_42FF:
    PUSH DE
    EX DE,HL
    LD HL,[FRETOP]
    CALL L_43CD
    EX DE,HL
    POP DE
    RET
L_430A:
    LD A,[D_07C4]
    LD B,A
    LD HL,$07A4
    XOR A
    INC B
L_4313:
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    LD [DE],A
    DEC B
    JP NZ,L_4313
    CALL L_540D
    XOR A
ST_NEW:
    RET NZ
L_4321:
    LD HL,[TXTTAB]
    CALL ST_TROFF
    LD [D_0BEC],A
    LD [AUTFLG],A
    LD [PTRFLG],A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [VARTAB],HL
L_4337:
    LD HL,[TXTTAB]
    DEC HL
L_433B:
    LD [TEMP],HL
    LD A,[D_0BED]
    OR A
    JP NZ,L_4358
    XOR A
    LD [D_0BC7],A
    LD [D_0BC6],A
    LD B,$1A
    LD HL,$0ACA
L_4351:
    LD [HL],$04
    INC HL
    DEC B
    JP NZ,L_4351
L_4358:
    LD DE,$37C8
    LD HL,$3869
    CALL L_28C3
    LD HL,$3846
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    XOR A
    LD [ONEFLG],A
    LD L,A
    LD H,A
    LD [ONELIN],HL
    LD [OLDTXT],HL
    LD HL,[MEMSIZ]
    LD A,[D_0BF3]
    OR A
    JP NZ,L_4383
    LD [FRETOP],HL
L_4383:
    XOR A
    CALL ST_RESTORE
    LD HL,[VARTAB]
    LD [ARYTAB],HL
    LD [STREND],HL
    LD A,[D_0BED]
    OR A
    CALL Z,L_540D
L_4397:
    POP BC
    LD HL,[TOPMEM]
    DEC HL
    DEC HL
    LD [SAVSTK],HL
    INC HL
    INC HL
L_43A2:
    LD SP,HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    CALL L_2572
    CALL L_4144
    CALL L_17E9
    XOR A
    LD H,A
    LD L,A
    LD [D_0AE6],HL
    LD [D_0BB7],A
    LD [D_0B4E],HL
    LD [D_0BBA],HL
    LD [D_0AE4],HL
    LD [SUBFLG],A
    PUSH HL
    PUSH BC
L_43C9:
    LD HL,[TEMP]
    RET
L_43CD:
    LD A,H
    SUB D
    RET NZ
    LD A,L
    SUB E
    RET
L_43D3:
    LD A,[HL]
    EX [SP],HL
    CP [HL]
    JP NZ,L_43E3
    INC HL
    EX [SP],HL
    INC HL
    LD A,[HL]
    CP $3A
    RET NC
    JP L_130A
L_43E3:
    JP SNERR
ST_RESTORE:
    EX DE,HL
    LD HL,[TXTTAB]
    JP Z,L_43FB
    EX DE,HL
    CALL L_1428
    PUSH HL
    CALL L_0EF8
    LD H,B
    LD L,C
    POP DE
    JP NC,L_14CC
L_43FB:
    DEC HL
    LD [DATPTR],HL
    EX DE,HL
    RET
ST_STOP:
    RET NZ
    INC A
    JP STPEND
ST_END:
    RET NZ
    PUSH AF
    CALL Z,L_540D
    POP AF
STPEND:
    LD [SAVTXT],HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    .byte $21
L_4416:
    .byte $F6, $FF
    POP BC
ENDCON:
    LD HL,[CURLIN]
    PUSH HL
    PUSH AF
    LD A,L
    AND H
    INC A
    JP Z,L_442D
    LD [OLDLIN],HL
    LD HL,[SAVTXT]
    LD [OLDTXT],HL
L_442D:
    XOR A
    LD [D_0793],A
    CALL L_4144
    CALL L_4214
    POP AF
    LD HL,$0C4A
    JP NZ,ERRFIN
    JP STPRDY
L_4441:
    LD A,$0F
L_4443:
    PUSH AF
    SUB $03
    JP NZ,L_444F
    LD [D_078D],A
    LD [D_0793],A
L_444F:
    LD A,$5E
    CALL OUTDO
    POP AF
    ADD A,$40
    CALL OUTDO
    JP L_4221
ST_CONT:
    LD HL,[OLDTXT]
    LD A,H
    OR L
    LD DE,$0011
    JP Z,ERROR
    EX DE,HL
    LD HL,[OLDLIN]
    EX DE,HL
    EX DE,HL
    LD [CURLIN],HL
    EX DE,HL
    RET
ST_NULL:
    CALL L_2075
    RET NZ
    INC A
    LD [D_0788],A
    RET
ST_TRON:
    .byte $3E
ST_TROFF:
    .byte $AF
    LD [TRCFLG],A
    RET
ST_SWAP:
    CALL L_398B
    PUSH DE
    PUSH HL
    LD HL,$0BF6
    CALL L_28C9
    LD HL,[ARYTAB]
    EX [SP],HL
    CALL L_1D64
    PUSH AF
    CALL L_43D3
    INC L
    CALL L_398B
    POP AF
    LD B,A
    CALL L_1D64
    CP B
    JP NZ,TMERR
    EX [SP],HL
    EX DE,HL
    PUSH HL
    LD HL,[ARYTAB]
    CALL L_43CD
    JP NZ,L_44C1
    POP DE
    POP HL
    EX [SP],HL
    PUSH DE
    CALL L_28C9
    POP HL
    LD DE,$0BF6
    CALL L_28C9
    POP HL
    RET
L_44C1:
    JP L_1418
ST_ERASE:
    LD A,$01
    LD [SUBFLG],A
    CALL L_398B
    JP NZ,L_44C1
    PUSH HL
    LD [SUBFLG],A
    LD H,B
    LD L,C
    DEC BC
    DEC BC
    DEC BC
L_44D8:
    LD A,[BC]
    DEC BC
    OR A
    JP M,L_44D8
    DEC BC
    DEC BC
    ADD HL,DE
    EX DE,HL
    LD HL,[STREND]
L_44E5:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_44E5
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    POP HL
    LD A,[HL]
    CP $2C
    RET NZ
    CALL CHRGTR
    JP ST_ERASE
L_4500:
    POP AF
    POP HL
    RET
L_4503:
    LD A,[HL]
L_4504:
    CP $41
    RET C
    CP $5B
    CCF
    RET
L_450B:
    JP L_433B
ST_CLEAR:
    JP Z,L_450B
    CP $2C
    JP Z,L_4520
    CALL L_1414
    DEC HL
    CALL CHRGTR
    JP Z,L_450B
L_4520:
    CALL L_43D3
    INC L
    JP Z,L_450B
    EX DE,HL
    LD HL,[TOPMEM]
    EX DE,HL
    CP $2C
    JP Z,L_4534
    CALL L_4579
L_4534:
    DEC HL
    CALL CHRGTR
    PUSH DE
    JP Z,L_4585
    CALL L_43D3
    INC L
    JP Z,L_4585
    CALL L_4579
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
L_454D:
    EX [SP],HL
    PUSH HL
    LD HL,$004E
    CALL L_43CD
    JP NC,L_4582
    POP HL
    CALL L_4597
    JP C,L_4582
    PUSH HL
    LD HL,[VARTAB]
    LD BC,$0014
    ADD HL,BC
    CALL L_43CD
    JP NC,L_4582
    EX DE,HL
    LD [MEMSIZ],HL
    POP HL
    LD [TOPMEM],HL
    POP HL
    JP L_450B
L_4579:
    CALL L_22D1
    LD A,D
    OR E
    JP Z,L_1418
    RET
L_4582:
    JP L_42DD
L_4585:
    PUSH HL
    LD HL,[TOPMEM]
    EX DE,HL
    LD HL,[MEMSIZ]
    LD A,E
    SUB L
    LD E,A
    LD A,D
    SBC A,H
    LD D,A
    POP HL
    JP L_454D
L_4597:
    LD A,L
    SUB E
    LD E,A
    LD A,H
    SBC A,D
    LD D,A
    RET
ST_NEXT:
    PUSH AF
    .byte $F6
L_45A0:
    .byte $AF
    LD [D_0BBF],A
    POP AF
    LD DE,$0000
L_45A8:
    LD [D_0BBD],HL
    CALL NZ,L_398B
    LD [TEMP],HL
    CALL L_0C50
    JP NZ,NFERR
    LD SP,HL
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    PUSH HL
    LD HL,[D_0BBD]
    CALL L_43CD
    JP NZ,NFERR
    POP HL
    POP DE
    PUSH DE
    LD A,[HL]
    PUSH AF
    INC HL
    PUSH DE
    LD A,[HL]
    INC HL
    OR A
    JP M,L_45F9
    CALL L_28A6
    EX [SP],HL
    PUSH HL
    LD A,[D_0BBF]
    OR A
    JP NZ,L_45E7
    LD HL,$0BC0
    CALL L_28A6
    XOR A
L_45E7:
    CALL NZ,L_257C
    POP HL
    CALL L_28C0
    POP HL
    CALL L_28B7
    PUSH HL
    CALL L_2906
    JP L_462F
L_45F9:
    INC HL
    INC HL
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    EX [SP],HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    PUSH HL
    LD L,C
    LD H,B
    LD A,[D_0BBF]
    OR A
    JP NZ,L_4615
    LD HL,[D_0BC0]
    JP L_4620
L_4615:
    CALL L_2B31
    LD A,[D_0A67]
    CP $04
    JP Z,OVERR
L_4620:
    EX DE,HL
    POP HL
    LD [HL],D
    DEC HL
    LD [HL],E
    POP HL
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL
    CALL L_2933
L_462F:
    POP HL
    POP BC
    SUB B
    CALL L_28B7
    JP Z,L_4641
    EX DE,HL
    LD [CURLIN],HL
    LD L,C
    LD H,B
    JP L_129C
L_4641:
    LD SP,HL
    LD [SAVSTK],HL
    LD HL,[TEMP]
    LD A,[HL]
    CP $2C
    JP NZ,NEWSTT
    CALL CHRGTR
    CALL L_45A8
L_4654:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    POP HL
    RET
    .byte $CD, $A5, $48, $7E, $23, $4E, $23, $46, $D1, $C5, $F5, $CD, $AC, $48, $F1, $57
    .byte $5E, $23, $4E, $23, $46, $E1, $7B, $B2, $C8, $7A, $D6, $01, $D8, $AF, $BB, $3C
    .byte $D0, $15, $1D, $0A, $03, $BE, $23, $CA, $72, $46, $3F, $C3, $50, $28
FN_OCT:
    CALL L_366F
    JP L_4699
FN_HEX:
    CALL L_3672
    JP L_4699
FN_STR:
    CALL L_3129
L_4699:
    CALL L_46C7
    CALL L_48A8
    LD BC,$48FC
    PUSH BC
L_46A3:
    LD A,[HL]
    INC HL
    PUSH HL
    CALL L_473C
    POP HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    CALL L_46BC
    PUSH HL
    LD L,A
    CALL L_489B
    POP DE
    RET
L_46B7:
    LD A,$01
L_46B9:
    CALL L_473C
L_46BC:
    LD HL,$0A98
    PUSH HL
    LD [HL],A
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    RET
L_46C7:
    DEC HL
L_46C8:
    LD B,$22
L_46CA:
    LD D,B
L_46CB:
    PUSH HL
    LD C,$FF
L_46CE:
    INC HL
    LD A,[HL]
    INC C
    OR A
    JP Z,L_46DD
    CP D
    JP Z,L_46DD
    CP B
    JP NZ,L_46CE
L_46DD:
    CP $22
    CALL Z,CHRGTR
    PUSH HL
    LD A,B
    CP $2C
    JP NZ,L_46F5
    INC C
L_46EA:
    DEC C
    JP Z,L_46F5
    DEC HL
    LD A,[HL]
    CP $20
    JP Z,L_46EA
L_46F5:
    POP HL
    EX [SP],HL
    INC HL
    EX DE,HL
    LD A,C
    CALL L_46BC
L_46FD:
    LD DE,$0A98
    .byte $3E
L_4701:
    .byte $D5
    LD HL,[TEMPPT]
    LD [D_0C04],HL
    LD A,$03
    LD [D_0A67],A
    CALL L_28C9
    LD DE,$0A9B
    CALL L_43CD
    LD [TEMPPT],HL
    POP HL
    LD A,[HL]
    RET NZ
    LD DE,$0010
    JP ERROR
    .byte $23
L_4723:
    CALL L_46C7
L_4726:
    CALL L_48A8
    CALL L_28B9
    INC D
L_472D:
    DEC D
    RET Z
    LD A,[BC]
    CALL OUTDO
    CP $0D
    CALL Z,L_422B
    INC BC
    JP L_472D
L_473C:
    OR A
    LD C,$F1
    PUSH AF
    LD HL,[STREND]
    EX DE,HL
    LD HL,[FRETOP]
    CPL
    LD C,A
    LD B,$FF
    ADD HL,BC
    INC HL
    CALL L_43CD
    JP C,L_475A
    LD [FRETOP],HL
    INC HL
    EX DE,HL
L_4758:
    POP AF
    RET
L_475A:
    POP AF
    LD DE,$000E
    JP Z,ERROR
    CP A
    PUSH AF
    LD BC,$473E
    PUSH BC
L_4767:
    LD HL,[MEMSIZ]
L_476A:
    LD [FRETOP],HL
    LD HL,$0000
    PUSH HL
    LD HL,[STREND]
    PUSH HL
    LD HL,$0A7A
    EX DE,HL
    LD HL,[TEMPPT]
    EX DE,HL
    CALL L_43CD
    LD BC,$4778
    JP NZ,L_4812
    LD HL,$0B4C
    LD [D_0BB8],HL
    LD HL,[ARYTAB]
    LD [D_0BB5],HL
    LD HL,[VARTAB]
L_4795:
    EX DE,HL
    LD HL,[D_0BB5]
    EX DE,HL
    CALL L_43CD
    JP Z,L_47B9
    LD A,[HL]
    INC HL
    INC HL
    INC HL
    PUSH AF
    CALL L_3C9A
    POP AF
    CP $03
    JP NZ,L_47B2
    CALL L_4813
    XOR A
L_47B2:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP L_4795
L_47B9:
    LD HL,[D_0BB8]
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    LD HL,[ARYTAB]
    JP Z,L_47DB
    EX DE,HL
    LD [D_0BB8],HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX DE,HL
    ADD HL,DE
    LD [D_0BB5],HL
    EX DE,HL
    JP L_4795
L_47DA:
    POP BC
L_47DB:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4837
    LD A,[HL]
    INC HL
    PUSH AF
    INC HL
    INC HL
    CALL L_3C9A
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    POP AF
    PUSH HL
    ADD HL,BC
    CP $03
    JP NZ,L_47DA
    LD [TEMP8],HL
    POP HL
    LD C,[HL]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL
    EX DE,HL
    LD HL,[TEMP8]
    EX DE,HL
    CALL L_43CD
    JP Z,L_47DB
    LD BC,$4804
L_4812:
    PUSH BC
L_4813:
    XOR A
    OR [HL]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    RET Z
    LD B,H
    LD C,L
    LD HL,[FRETOP]
    CALL L_43CD
    LD H,B
    LD L,C
    RET C
    POP HL
    EX [SP],HL
    CALL L_43CD
    EX [SP],HL
    PUSH HL
    LD H,B
    LD L,C
    RET NC
    POP BC
    POP AF
    POP AF
    PUSH HL
    PUSH DE
    PUSH BC
    RET
L_4837:
    POP DE
    POP HL
    LD A,H
    OR L
    RET Z
    DEC HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    PUSH HL
    DEC HL
    LD L,[HL]
    LD H,$00
    ADD HL,BC
    LD D,B
    LD E,C
    DEC HL
    LD B,H
    LD C,L
    LD HL,[FRETOP]
    CALL L_42B9
    POP HL
    LD [HL],C
    INC HL
    LD [HL],B
    LD H,B
    LD L,C
    DEC HL
    JP L_476A
L_485B:
    PUSH BC
    PUSH HL
    LD HL,[D_0C04]
    EX [SP],HL
    CALL L_1B93
    EX [SP],HL
    CALL L_2A3B
    LD A,[HL]
    PUSH HL
    LD HL,[D_0C04]
    PUSH HL
    ADD A,[HL]
    LD DE,$000F
    JP C,ERROR
    CALL L_46B9
    POP DE
    CALL L_48AC
    EX [SP],HL
    CALL L_48AB
    PUSH HL
    LD HL,[D_0A99]
    EX DE,HL
    CALL L_4893
    CALL L_4893
    LD HL,$1A12
    EX [SP],HL
    PUSH HL
    JP L_46FD
L_4893:
    POP HL
    EX [SP],HL
    LD A,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD L,A
L_489B:
    INC L
L_489C:
    DEC L
    RET Z
    LD A,[BC]
    LD [DE],A
    INC BC
    INC DE
    JP L_489C
L_48A5:
    CALL L_2A3B
L_48A8:
    LD HL,[D_0C04]
L_48AB:
    EX DE,HL
L_48AC:
    CALL L_48C6
    EX DE,HL
    RET NZ
    PUSH DE
    LD D,B
    LD E,C
    DEC DE
    LD C,[HL]
    LD HL,[FRETOP]
    CALL L_43CD
    JP NZ,L_48C4
    LD B,A
    ADD HL,BC
    LD [FRETOP],HL
L_48C4:
    POP HL
    RET
L_48C6:
    LD HL,[TEMPPT]
    DEC HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    DEC HL
    CALL L_43CD
    RET NZ
    LD [TEMPPT],HL
L_48D5:
    RET
FN_LEN:
    LD BC,$1DD5
    PUSH BC
L_48DA:
    CALL L_48A5
    XOR A
    LD D,A
    LD A,[HL]
L_48E0:
    OR A
    RET
FN_ASC:
    LD BC,$1DD5
    PUSH BC
L_48E6:
    CALL L_48DA
    JP Z,L_1418
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,[DE]
    RET
FN_CHR:
    CALL L_46B7
    CALL L_2078
L_48F8:
    LD HL,[D_0A99]
    LD [HL],E
L_48FC:
    POP BC
    JP L_46FD
L_4900:
    CALL CHRGTR
    CALL L_43D3
    JR Z,L_48D5
    LD [HL],L
    JR NZ,L_48E0
    CALL L_43D3
    INC L
    CALL L_1A02
    CALL L_43D3
    ADD HL,HL
    EX [SP],HL
    PUSH HL
    CALL L_1D64
    JP Z,L_4924
    CALL L_2078
    JP L_4927
L_4924:
    CALL L_48E6
L_4927:
    POP DE
    CALL L_4930
FN_SPACE:
    CALL L_2078
    LD A,$20
L_4930:
    PUSH AF
    LD A,E
    CALL L_46B9
    LD B,A
    POP AF
    INC B
    DEC B
    JP Z,L_48FC
    LD HL,[D_0A99]
L_493F:
    LD [HL],A
    INC HL
    DEC B
    JP NZ,L_493F
    JP L_48FC
FN_LEFT:
    CALL L_49C1
    XOR A
L_494C:
    EX [SP],HL
    LD C,A
    .byte $3E
L_494F:
    .byte $E5
    PUSH HL
    LD A,[HL]
    CP B
    JP C,L_4958
    LD A,B
    .byte $11
L_4958:
    .byte $0E, $00
    PUSH BC
    CALL L_473C
    POP BC
    POP HL
    PUSH HL
    INC HL
    LD B,[HL]
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC
    LD B,H
    LD C,L
    CALL L_46BC
    LD L,A
    CALL L_489B
    POP DE
    CALL L_48AC
    JP L_46FD
FN_RIGHT:
    CALL L_49C1
    POP DE
    PUSH DE
    LD A,[DE]
    SUB B
    JP L_494C
FN_MID:
    EX DE,HL
    LD A,[HL]
    CALL L_49C6
    INC B
    DEC B
    JP Z,L_1418
    PUSH BC
    CALL L_4AE3
    POP AF
    EX [SP],HL
    LD BC,$4950
    PUSH BC
    DEC A
    CP [HL]
    LD B,$00
    RET NC
    LD C,A
    LD A,[HL]
    SUB C
    CP E
    LD B,A
    RET C
    LD B,E
    RET
FN_VAL:
    CALL L_48DA
    JP Z,L_1DD5
    LD E,A
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    PUSH HL
    ADD HL,DE
    LD B,[HL]
    LD [HL],D
    EX [SP],HL
    PUSH BC
    DEC HL
    CALL CHRGTR
    CALL L_2ECA
    POP BC
    POP HL
    LD [HL],B
    RET
L_49C1:
    EX DE,HL
    CALL L_43D3
    ADD HL,HL
L_49C6:
    POP BC
    POP DE
    PUSH BC
    LD B,E
    RET
L_49CB:
    CALL CHRGTR
    CALL L_19FE
    CALL L_1D64
    LD A,$01
    PUSH AF
    JP Z,L_49ED
    POP AF
    CALL L_2078
    OR A
    JP Z,L_1418
    PUSH AF
    CALL L_43D3
    INC L
    CALL L_1A02
    CALL L_2A3B
L_49ED:
    CALL L_43D3
    INC L
    PUSH HL
    LD HL,[D_0C04]
    EX [SP],HL
    CALL L_1A02
    CALL L_43D3
    ADD HL,HL
    PUSH HL
    CALL L_48A5
    EX DE,HL
    POP BC
    POP HL
    POP AF
    PUSH BC
    LD BC,$2757
    PUSH BC
    LD BC,$1DD5
    PUSH BC
    PUSH AF
    PUSH DE
    CALL L_48AB
    POP DE
    POP AF
    LD B,A
    DEC A
    LD C,A
    CP [HL]
    LD A,$00
    RET NC
    LD A,[DE]
    OR A
    LD A,B
    RET Z
    LD A,[HL]
    INC HL
    LD B,[HL]
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC
    SUB C
    LD B,A
    PUSH BC
    PUSH DE
    EX [SP],HL
    LD C,[HL]
    INC HL
    LD E,[HL]
    INC HL
L_4A32:
    LD D,[HL]
    POP HL
L_4A34:
    PUSH HL
    PUSH DE
    PUSH BC
L_4A37:
    LD A,[DE]
    CP [HL]
    JP NZ,L_4A55
    INC DE
    DEC C
    JP Z,L_4A4C
    INC HL
    DEC B
    JP NZ,L_4A37
    POP DE
    POP DE
    POP BC
L_4A49:
    POP DE
    XOR A
    RET
L_4A4C:
    POP HL
    POP DE
    POP DE
    POP BC
    LD A,B
    SUB H
    ADD A,C
    INC A
    RET
L_4A55:
    POP BC
    POP DE
    POP HL
    INC HL
    DEC B
    JP NZ,L_4A34
    JP L_4A49
L_4A60:
    CALL L_43D3
    JR Z,L_4A32
    ADC A,E
    ADD HL,SP
    CALL L_2A3B
    PUSH HL
    PUSH DE
    EX DE,HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,[STREND]
    CALL L_43CD
    JP C,L_4A8D
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_4A8D
    POP HL
    PUSH HL
    CALL L_46A3
    POP HL
    PUSH HL
    CALL L_28C9
L_4A8D:
    POP HL
    EX [SP],HL
    CALL L_43D3
    INC L
    CALL L_2075
    OR A
    JP Z,L_1418
    PUSH AF
    LD A,[HL]
    CALL L_4AE3
    PUSH DE
    CALL L_19F7
    PUSH HL
    CALL L_48A5
    EX DE,HL
    POP HL
    POP BC
    POP AF
    LD B,A
    EX [SP],HL
    PUSH HL
    LD HL,$2757
    EX [SP],HL
    LD A,C
    OR A
    RET Z
    LD A,[HL]
    SUB B
    JP C,L_1418
    INC A
    CP C
    JP C,L_4AC0
    LD A,C
L_4AC0:
    LD C,B
    DEC C
    LD B,$00
    PUSH DE
    INC HL
    LD E,[HL]
    INC HL
    LD H,[HL]
    LD L,E
    ADD HL,BC
    LD B,A
    POP DE
    EX DE,HL
    LD C,[HL]
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL
    LD A,C
    OR A
    RET Z
L_4AD8:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    RET Z
    DEC B
    JP NZ,L_4AD8
    RET
L_4AE3:
    LD E,$FF
    CP $29
    JP Z,L_4AF1
    CALL L_43D3
    INC L
    CALL L_2075
L_4AF1:
    CALL L_43D3
    ADD HL,HL
    RET
FN_FRE:
    CALL L_1D64
    JP NZ,L_4B02
    CALL L_48A8
    CALL L_4767
L_4B02:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    LD HL,[FRETOP]
    JP L_1DC2
L_4B0D:
    LD A,$3F
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    JP L_4B28
L_4B1A:
    CALL L_41BF
    CP $01
    JP NZ,L_4B7A
    LD [HL],$00
    JP L_4B38
L_4B27:
    LD [HL],B
L_4B28:
    XOR A
    LD [D_0789],A
    XOR A
    LD [D_0BE6],A
L_4B30:
    CALL L_41BF
    CP $01
    JP NZ,L_4B6F
L_4B38:
    CALL L_4221
    LD HL,$FFFF
    JP L_3D00
L_4B41:
    LD A,[D_0792]
    OR A
    LD A,$5C
    LD [D_0792],A
    JP NZ,L_4B55
    DEC B
    JP Z,L_4B27
    CALL OUTDO
    INC B
L_4B55:
    DEC B
    DEC HL
    JP Z,L_4B69
    LD A,[HL]
    CALL OUTDO
    JP L_4B1A
    .byte $05
L_4B62:
    DEC HL
    CALL OUTDO
    JP NZ,L_4B1A
L_4B69:
    CALL OUTDO
    CALL L_4221
L_4B6F:
    LD HL,$0962
    LD B,$01
    PUSH AF
    XOR A
    LD [D_0792],A
    POP AF
L_4B7A:
    LD C,A
    CP $7F
    JP Z,L_4B41
    LD A,[D_0792]
    OR A
    JP Z,L_4B90
    LD A,$5C
    CALL OUTDO
    XOR A
    LD [D_0792],A
L_4B90:
    LD A,C
    CP $07
    JP Z,L_4BFA
    CP $03
    CALL Z,L_4443
    SCF
    RET Z
    CP $0D
    JP Z,L_4C3B
    CP $09
    JP Z,L_4BFA
    CP $0A
    JP NZ,L_4BB4
    DEC B
    JP Z,L_4B28
    INC B
    JP L_4BFA
L_4BB4:
    CP $15
    CALL Z,L_4443
    JP Z,L_4B28
    CP $08
    JP NZ,L_4BD2
    DEC B
    JP Z,L_4B30
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    LD A,$08
    JP L_4B62
L_4BD2:
    CP $18
    JP NZ,L_4BDC
    LD A,$23
    JP L_4B69
L_4BDC:
    CP $12
    JP NZ,L_4BF5
    PUSH BC
    PUSH DE
    PUSH HL
    LD [HL],$00
    CALL L_4221
    LD HL,$0962
    CALL L_20DC
    POP HL
    POP DE
    POP BC
    JP L_4B1A
L_4BF5:
    CP $20
    JP C,L_4B1A
L_4BFA:
    LD A,B
    OR A
    JP NZ,L_4C18
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    POP HL
    LD A,$07
    JP Z,L_4C1C
    LD HL,$0962
    CALL L_1428
    EX DE,HL
    LD [CURLIN],HL
    JP L_115F
L_4C18:
    LD A,C
    LD [HL],C
    INC HL
    INC B
L_4C1C:
    CALL OUTDO
    SUB $0A
    JP NZ,L_4B1A
    LD [D_0A65],A
    LD A,$0D
    CALL OUTDO
L_4C2C:
    CALL L_41BF
    OR A
    JP Z,L_4C2C
    CP $0D
    JP Z,L_4B1A
    JP L_4B7A
L_4C3B:
    LD A,[D_0BE6]
    OR A
    JP Z,L_421C
    XOR A
    LD [HL],A
    LD HL,$0961
    RET
L_4C48:
    PUSH AF
    LD A,$00
    LD [D_0BE6],A
    POP AF
    CP $3B
    RET NZ
    LD [D_0BE6],A
    JP CHRGTR
ST_WHILE:
    LD [ENDFOR],HL
    CALL L_24DD
    CALL CHRGTR
    EX DE,HL
    CALL L_4CC1
    INC SP
    INC SP
    JP NZ,L_4C6F
    ADD HL,BC
    LD SP,HL
    LD [SAVSTK],HL
L_4C6F:
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[ENDFOR]
    PUSH HL
    PUSH DE
    JP L_4CA1
ST_WEND:
    JP NZ,SNERR
    EX DE,HL
    CALL L_4CC1
    JP NZ,L_4CEB
    LD SP,HL
    LD [SAVSTK],HL
    EX DE,HL
    LD HL,[CURLIN]
    EX DE,HL
    EX DE,HL
    LD [D_0BC4],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD [CURLIN],HL
    EX DE,HL
L_4CA1:
    CALL L_1A02
    PUSH HL
    CALL L_2886
    POP HL
    JP Z,L_4CB5
    LD BC,$00B4
    LD B,C
    PUSH BC
    INC SP
    JP NEWSTT
L_4CB5:
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    POP HL
    POP BC
    POP BC
    JP NEWSTT
L_4CC1:
    LD HL,$0004
    ADD HL,SP
L_4CC5:
    LD A,[HL]
    INC HL
    LD BC,$0082
    CP C
    JP NZ,L_4CD5
    LD BC,$0010
    ADD HL,BC
    JP L_4CC5
L_4CD5:
    LD BC,$00B4
    CP C
    RET NZ
    PUSH HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CALL L_43CD
    POP HL
    LD BC,$0006
    RET Z
    ADD HL,BC
    .byte $C3
L_4CE9:
    PUSH BC
    LD C,H
L_4CEB:
    LD DE,$001E
    JP ERROR
ST_CALL:
    LD A,$80
    LD [SUBFLG],A
    CALL L_398B
    PUSH HL
    EX DE,HL
    CALL L_1D64
    CALL L_28EE
    CALL L_22DB
    LD [D_0BE6],HL
    LD C,$20
    CALL L_42C7
    POP DE
    LD HL,$FFC0
    ADD HL,SP
    LD SP,HL
    EX DE,HL
    LD C,$20
    DEC HL
    CALL CHRGTR
    LD [TEMP],HL
    JP Z,L_4D5F
    CALL L_43D3
    .byte $28
L_4D23:
    .byte $C5
    PUSH DE
    CALL L_398B
    EX [SP],HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    EX [SP],HL
    POP DE
    POP BC
    LD A,[HL]
    CP $2C
    JP NZ,L_4D3D
    DEC C
    CALL CHRGTR
    JP L_4D23
L_4D3D:
    CALL L_43D3
    ADD HL,HL
    LD [TEMP],HL
    LD A,$21
    SUB C
    POP HL
    DEC A
    JP Z,L_4D5F
    POP DE
    DEC A
    JP Z,L_4D5F
    POP BC
    DEC A
    JP Z,L_4D5F
    PUSH BC
    PUSH HL
    LD HL,$0002
    ADD HL,SP
    LD B,H
    LD C,L
    POP HL
L_4D5F:
    PUSH HL
    LD HL,$4D6A
    EX [SP],HL
    PUSH HL
    LD HL,[D_0BE6]
    EX [SP],HL
    RET
    .byte $2A, $B1, $0A, $F9, $2A, $A7, $0A, $C3, $A0, $12
ST_CHAIN:
    XOR A
    LD [D_0BED],A
    LD [D_0BEE],A
    LD A,[HL]
    LD DE,$00C5
    CP E
    JP NZ,L_4D87
    LD [D_0BED],A
    INC HL
L_4D87:
    DEC HL
    CALL CHRGTR
    CALL L_5294
    PUSH HL
    LD HL,$0000
    LD [D_0BF4],HL
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E07
    CALL L_43D3
    INC L
    CP $2C
    JP Z,L_4DB8
    CALL L_1A02
    PUSH HL
    CALL L_22DB
    LD [D_0BF4],HL
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E07
L_4DB8:
    CALL L_43D3
    INC L
    LD DE,$00AA
    CP E
    JP Z,L_4DDB
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD C,H
    CALL L_43D3
    LD C,H
    JP Z,L_4F4E
    CALL L_43D3
    INC L
    CP E
    JP NZ,SNERR
    OR A
L_4DDB:
    PUSH AF
    LD [D_0BEE],A
    CALL CHRGTR
    CALL L_0ED8
    PUSH BC
    CALL L_2435
    POP BC
    POP DE
    PUSH BC
    LD H,B
    LD L,C
    LD [D_0BF1],HL
    CALL L_0EF8
    JP NC,L_4E00
    LD D,H
    LD E,L
    LD [D_0BEF],HL
    POP HL
    CALL L_43CD
L_4E00:
    JP NC,L_1418
    POP AF
    JP NZ,L_4F4E
L_4E07:
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[TXTTAB]
    DEC HL
L_4E0F:
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,L_4ECF
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL
    EX DE,HL
L_4E1F:
    CALL CHRGTR
L_4E22:
    OR A
    JP Z,L_4E0F
    CP $3A
    JP Z,L_4E1F
    LD DE,$00B8
    CP E
    JP Z,L_4E3C
    CALL CHRGTR
    CALL ST_DATA
    DEC HL
    JP L_4E1F
L_4E3C:
    CALL CHRGTR
    JP Z,L_4E22
L_4E42:
    PUSH HL
    LD A,$01
    LD [SUBFLG],A
    CALL L_3A89
    JP Z,L_4EA2
    LD A,B
    OR $80
    LD B,A
    XOR A
    CALL L_3B92
    LD A,$00
    LD [SUBFLG],A
    JP NZ,L_4E68
    LD A,[HL]
    CP $28
    JP NZ,L_4E6E
    POP AF
    JP L_4EBE
L_4E68:
    LD A,[HL]
    CP $28
    JP Z,L_1418
L_4E6E:
    POP HL
    CALL L_3A89
    LD A,D
    OR E
    JP NZ,L_4E8F
    LD A,B
    OR $80
    LD B,A
    LD DE,$4E8A
    PUSH DE
    LD DE,$3A8C
    PUSH DE
    LD A,[D_0A67]
    LD D,A
    JP L_3A29
    .byte $7A, $B3, $CA, $18, $14
L_4E8F:
    PUSH HL
    LD B,D
    LD C,E
    LD HL,$4EB1
    PUSH HL
L_4E96:
    DEC BC
L_4E97:
    LD A,[BC]
    DEC BC
    OR A
    JP M,L_4E97
    LD A,[BC]
    OR $80
    LD [BC],A
    RET
L_4EA2:
    LD [SUBFLG],A
    LD A,[HL]
    CP $28
    JP NZ,L_4E6E
    EX [SP],HL
    DEC BC
    DEC BC
    CALL L_4E96
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E22
    CP $28
    JP NZ,L_4EC8
L_4EBE:
    CALL CHRGTR
    CALL L_43D3
    ADD HL,HL
    JP Z,L_4E22
L_4EC8:
    CALL L_43D3
    INC L
    JP L_4E42
L_4ECF:
    POP HL
    LD [CURLIN],HL
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    LD HL,[VARTAB]
L_4EDB:
    CALL L_43CD
    JP Z,L_4F23
    PUSH HL
    LD C,[HL]
    INC HL
    INC HL
    LD A,[HL]
    OR A
    PUSH AF
    AND $7F
    LD [HL],A
    INC HL
    CALL L_3C9A
    LD B,$00
    ADD HL,BC
    POP AF
    POP BC
    JP M,L_4EDB
    PUSH BC
    CALL L_4F07
    LD HL,[ARYTAB]
    ADD HL,DE
    LD [ARYTAB],HL
    EX DE,HL
    POP HL
    JP L_4EDB
L_4F07:
    EX DE,HL
    LD HL,[STREND]
L_4F0B:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_4F0B
    LD A,C
    SUB L
    LD E,A
    LD A,B
    SBC A,H
    LD D,A
    DEC DE
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    RET
L_4F23:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
L_4F28:
    CALL L_43CD
    JP Z,L_4F4E
    PUSH HL
    INC HL
    INC HL
    LD A,[HL]
    OR A
    PUSH AF
    AND $7F
    LD [HL],A
    INC HL
    CALL L_3C9A
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    ADD HL,BC
    POP AF
    POP BC
    JP M,L_4F28
    PUSH BC
    CALL L_4F07
    EX DE,HL
    POP HL
    JP L_4F28
L_4F4E:
    LD HL,[VARTAB]
L_4F51:
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4F76
    LD A,[HL]
    INC HL
    INC HL
    INC HL
    PUSH AF
    CALL L_3C9A
    POP AF
    CP $03
    JP NZ,L_4F6E
    CALL L_4FAE
    XOR A
L_4F6E:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP L_4F51
L_4F75:
    POP BC
L_4F76:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4FD8
    LD A,[HL]
    INC HL
    INC HL
    PUSH AF
    INC HL
    CALL L_3C9A
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    POP AF
    PUSH HL
    ADD HL,BC
    CP $03
    JP NZ,L_4F75
    LD [TEMP3],HL
    POP HL
    LD C,[HL]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL
    EX DE,HL
    LD HL,[TEMP3]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4F76
    LD BC,$4F9F
    PUSH BC
L_4FAE:
    LD A,[HL]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    OR A
    RET Z
    PUSH HL
    LD HL,[VARTAB]
    CALL L_43CD
    POP HL
    RET C
    PUSH HL
    LD HL,[TXTTAB]
    CALL L_43CD
    POP HL
    RET NC
    PUSH HL
    DEC HL
    DEC HL
    DEC HL
    PUSH HL
    CALL L_46A3
    POP HL
    LD B,$03
    CALL L_28CD
    POP HL
    RET
L_4FD8:
    CALL L_4767
    LD HL,[STREND]
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL
    LD HL,[ARYTAB]
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD [D_0BB8],HL
    LD HL,[FRETOP]
    LD [D_0BE8],HL
    CALL L_42B9
    LD H,B
    LD L,C
    DEC HL
    LD [FRETOP],HL
    LD A,[D_0BEE]
    OR A
    JP Z,L_501B
    LD HL,[D_0BF1]
    LD B,H
    LD C,L
    LD HL,[D_0BEF]
    CALL L_22A2
    LD [ARYTAB],HL
    LD [STREND],HL
    CALL L_0EAB
L_501B:
    LD A,$01
    LD [D_0BF3],A
    LD A,[D_0BED]
    OR A
    JP NZ,L_536D
    LD A,[D_07C4]
    LD [D_079F],A
    JP L_52B9
L_5030:
    XOR A
    LD [D_0BF3],A
    LD [D_0BED],A
    LD HL,[VARTAB]
    LD B,H
    LD C,L
    LD HL,[D_0BB8]
    ADD HL,BC
    LD [ARYTAB],HL
    LD HL,[FRETOP]
    INC HL
    EX DE,HL
    LD HL,[D_0BE8]
    LD [FRETOP],HL
L_504E:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_504E
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    EX DE,HL
    LD HL,[D_0BF4]
    EX DE,HL
    LD HL,[TXTTAB]
    DEC HL
    LD A,D
    OR E
    JP Z,NEWSTT
    CALL L_0EF8
    JP NC,L_14CC
    DEC BC
    LD H,B
    LD L,C
    JP NEWSTT
    .byte $C3, $EC, $14
ST_WRITE:
    LD C,$02
    CALL L_510D
    DEC HL
    CALL CHRGTR
    JP Z,L_50DA
L_5087:
    CALL L_1A02
    PUSH HL
    CALL L_1D64
    JP Z,L_50CA
    CALL L_3129
    CALL L_46C7
    LD HL,[D_0C04]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,[DE]
    CP $20
    JP NZ,L_50AA
    INC DE
    LD [HL],D
    DEC HL
    LD [HL],E
    DEC HL
    DEC [HL]
L_50AA:
    CALL L_4726
L_50AD:
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_50DA
    CP $3B
    JP Z,L_50BF
    CALL L_43D3
    INC L
    DEC HL
L_50BF:
    CALL CHRGTR
    LD A,$2C
    CALL OUTDO
    JP L_5087
L_50CA:
    LD A,$22
    CALL OUTDO
    CALL L_4726
    LD A,$22
    CALL OUTDO
    JP L_50AD
L_50DA:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    JP Z,L_5104
    LD A,[HL]
    CP $03
    JP NZ,L_5104
    CALL L_5CC2
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD DE,$FFFE
    ADD HL,DE
    JP NC,L_5104
L_50F9:
    LD A,$20
    CALL OUTDO
    DEC HL
    LD A,H
    OR L
    JP NZ,L_50F9
L_5104:
    POP HL
    CALL L_4221
    JP L_17E9
L_510B:
    LD C,$01
L_510D:
    CP $23
    RET NZ
    PUSH BC
    CALL L_512A
    POP DE
    CP E
    JP Z,L_511E
    CP $03
    JP NZ,DERBFM
L_511E:
    CALL L_43D3
    INC L
L_5122:
    LD D,B
    LD E,C
    EX DE,HL
    LD [D_0794],HL
    EX DE,HL
    RET
L_512A:
    DEC HL
    CALL CHRGTR
    CP $23
    CALL Z,CHRGTR
    CALL L_1A02
L_5136:
    CALL L_2078
L_5139:
    LD E,A
L_513A:
    LD A,[D_07C4]
    CP E
    JP C,DERBFN
    LD D,$00
    PUSH HL
    LD HL,$07A4
    ADD HL,DE
    ADD HL,DE
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]
    OR A
    POP HL
    RET
L_5150:
    CALL L_513A
    LD HL,$0029
    CP $03
    JP NZ,L_515E
    LD HL,$00B2
L_515E:
    ADD HL,BC
    EX DE,HL
    RET
FN_MKI:
    LD A,$02
    .byte $01
FN_MKS:
    LD A,$04
    .byte $01
FN_MKD:
    LD A,$08
    PUSH AF
    CALL L_1FAC
    POP AF
    CALL L_46B9
    LD HL,[D_0A99]
    CALL L_28F7
    JP L_48FC
FN_CVI:
    LD A,$01
    .byte $01
FN_CVS:
    LD A,$03
    .byte $01
FN_CVD:
    LD A,$07
    PUSH AF
    CALL L_48A5
    POP AF
    CP [HL]
    JP NC,L_1418
    INC A
    LD [D_0A67],A
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    JP L_28EE
L_5197:
    CALL L_1D64
    LD BC,$198F
    LD DE,$2C20
    JP NZ,L_51BB
    LD E,D
    JP L_51BB
L_51A7:
    CALL L_510B
    CALL L_398B
    CALL L_2A3B
    LD BC,$17E9
    PUSH BC
    PUSH DE
    LD BC,$1512
    XOR A
    LD D,A
    LD E,A
L_51BB:
    PUSH AF
    PUSH BC
    PUSH HL
L_51BE:
    CALL L_57C2
    JP C,DERRPE
    CP $20
    JP NZ,L_51CE
    INC D
    DEC D
    JP NZ,L_51BE
L_51CE:
    CP $22
    JP NZ,L_51E3
    LD B,A
    LD A,E
    CP $2C
    LD A,B
    JP NZ,L_51E3
    LD D,B
    LD E,B
    CALL L_57C2
    JP C,L_5231
L_51E3:
    LD HL,$0962
    LD B,$FF
L_51E8:
    LD C,A
    LD A,D
    CP $22
    LD A,C
    JP Z,L_521C
    CP $0D
    PUSH HL
    JP Z,L_5251
    POP HL
    CP $0A
    JP NZ,L_521C
    LD C,A
    LD A,E
    CP $2C
    LD A,C
    CALL NZ,L_528A
    CALL L_57C2
    JP C,L_5231
    CP $0D
    JP NZ,L_521C
    LD A,E
    CP $20
    JP Z,L_522B
    CP $2C
    LD A,$0D
    JP Z,L_522B
L_521C:
    OR A
    JP Z,L_522B
    CP D
    JP Z,L_5231
    CP E
    JP Z,L_5231
    CALL L_528A
L_522B:
    CALL L_57C2
    JP NC,L_51E8
L_5231:
    PUSH HL
    CP $22
    JP Z,L_523C
    CP $20
    JP NZ,L_5264
L_523C:
    CALL L_57C2
    JP C,L_5264
    CP $20
    JP Z,L_523C
    CP $2C
    JP Z,L_5264
    CP $0D
    JP NZ,L_525C
L_5251:
    CALL L_57C2
    JP C,L_5264
    CP $0A
    JP Z,L_5264
L_525C:
    LD HL,[D_0794]
    LD BC,$0028
    ADD HL,BC
    INC [HL]
L_5264:
    POP HL
L_5265:
    LD [HL],$00
    LD HL,$0961
    LD A,E
    SUB $20
    JP Z,L_5278
    LD B,D
    LD D,$00
    CALL L_46CB
    POP HL
    RET
L_5278:
    CALL L_1D64
    PUSH AF
    CALL CHRGTR
    POP AF
    PUSH AF
    CALL C,L_2ED1
    POP AF
    CALL NC,L_2ECA
    POP HL
    RET
L_528A:
    OR A
    RET Z
    LD [HL],A
    INC HL
    DEC B
    RET NZ
    POP BC
    JP L_5265
L_5294:
    LD D,$01
L_5296:
    XOR A
    JP L_58FE
L_529A:
    .byte $F6
ST_LOAD:
    XOR A
    PUSH AF
    CALL L_5294
    LD A,[D_07C4]
    LD [D_079F],A
    DEC HL
    CALL CHRGTR
    JP Z,L_52BE
    CALL L_43D3
    INC L
    CALL L_43D3
    LD D,D
    JP NZ,SNERR
    POP AF
L_52B9:
    XOR A
    LD [D_07C4],A
    .byte $F6
L_52BE:
    .byte $F1
    LD [D_079E],A
    LD HL,$0080
    LD [HL],$00
    LD [D_07A4],HL
    CALL L_4321
    LD A,[D_079F]
    LD [D_07C4],A
    LD HL,[D_07A2]
    LD [D_07A4],HL
    LD [D_0794],HL
    LD HL,[CURLIN]
    INC HL
    LD A,H
    AND L
    INC A
    JP NZ,L_52E9
    LD [CURLIN],HL
L_52E9:
    CALL L_57C2
    JP C,MAIN
    CP $FE
    JP NZ,L_52FA
    LD [D_0BEC],A
    JP L_52FE
L_52FA:
    INC A
    JP NZ,L_537F
L_52FE:
    LD HL,[TXTTAB]
L_5301:
    EX DE,HL
    LD HL,[FRETOP]
    LD BC,$FFAA
    ADD HL,BC
    CALL L_43CD
    EX DE,HL
    JP C,L_5356
    CALL L_5748
    LD [HL],A
    INC HL
    JP NC,L_5301
    LD [VARTAB],HL
    LD A,[D_0BEC]
    OR A
    CALL NZ,L_5D22
    CALL L_0EAB
    INC HL
    INC HL
    LD [VARTAB],HL
    LD HL,$07C4
    LD A,[HL]
    LD [D_079F],A
    LD [HL],$00
    CALL L_4337
    LD A,[D_079F]
    LD [D_07C4],A
    LD A,[D_0BF3]
    OR A
    JP NZ,L_5030
    LD A,[D_079E]
    OR A
    JP Z,READY
    JP NEWSTT
L_534D:
    CALL L_17E9
    CALL L_5606
    JP L_43C9
L_5356:
    CALL L_4321
    JP L_42DD
ST_MERGE:
    POP BC
    CALL L_5294
    DEC HL
    CALL CHRGTR
    JP Z,L_536D
    CALL L_534D
    JP SNERR
L_536D:
    XOR A
    LD [D_079E],A
    CALL L_57C2
    JP C,MAIN
    INC A
    JP Z,DERBFM
    INC A
    JP Z,DERBFM
L_537F:
    LD HL,[D_0794]
    LD BC,$0028
    ADD HL,BC
    INC [HL]
    JP MAIN
L_538A:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    LD DE,$0042
    JP NZ,ERROR
    POP HL
    JP GONE
ST_SAVE:
    LD D,$02
    CALL L_5296
    DEC HL
    CALL CHRGTR
    JP Z,L_53B6
    CALL L_43D3
    INC L
    CP $50
    JP Z,L_5CD1
    CALL L_43D3
    LD B,C
    JP ST_LIST
L_53B6:
    CALL L_2392
    CALL L_5D65
    LD A,$FF
L_53BE:
    CALL L_5668
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL
    LD HL,[TXTTAB]
L_53C9:
    CALL L_43CD
    JP Z,L_534D
    LD A,[HL]
    INC HL
    PUSH DE
    CALL L_5668
    POP DE
    JP L_53C9
ST_CLOSE:
    LD BC,$5606
    LD A,[D_07C4]
    JP NZ,L_53FC
    PUSH HL
    PUSH BC
    PUSH AF
    LD DE,$53EB
    PUSH DE
    PUSH BC
    RET
    .byte $F1, $C1, $3D, $F2, $E3, $53, $E1, $C9, $C1, $E1, $7E, $FE, $2C, $C0, $CD, $05
    .byte $13
L_53FC:
    PUSH BC
    LD A,[HL]
    CP $23
    CALL Z,CHRGTR
    CALL L_2075
    EX [SP],HL
    PUSH HL
    LD DE,$53F3
    PUSH DE
    JP [HL]
L_540D:
    PUSH DE
    PUSH BC
    XOR A
    CALL ST_CLOSE
    POP BC
    POP DE
    XOR A
    RET
ST_FIELD:
    CALL L_512A
    JP Z,DERBFN
    SUB $03
    JP NZ,DERBFM
    EX DE,HL
    LD HL,$00A9
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD [D_0BE6],HL
    LD HL,$0000
    LD [D_5D6F],HL
    LD A,H
    EX DE,HL
    LD DE,$00B2
L_5439:
    EX DE,HL
    ADD HL,BC
    LD B,A
    EX DE,HL
    LD A,[HL]
    CP $2C
    RET NZ
    PUSH DE
    PUSH BC
    CALL L_2072
    PUSH AF
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_398B
    CALL L_2A3B
    POP AF
    POP BC
    EX [SP],HL
    LD C,A
    PUSH DE
    PUSH HL
    LD HL,[D_5D6F]
    LD B,$00
    ADD HL,BC
    LD [D_5D6F],HL
    EX DE,HL
    LD HL,[D_0BE6]
    CALL L_43CD
    JP C,DERFOV
    POP HL
    POP DE
    EX DE,HL
    LD [HL],C
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    JP L_5439
ST_RSET:
    .byte $F6
ST_LSET:
    .byte $37
    PUSH AF
    CALL L_398B
    CALL L_2A3B
    PUSH DE
    CALL L_19F7
    POP BC
    EX [SP],HL
    PUSH HL
    PUSH BC
    CALL L_48A5
    LD B,[HL]
    EX [SP],HL
    LD A,[HL]
    LD C,A
    PUSH BC
    PUSH HL
    PUSH AF
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    OR A
    JP Z,L_54FC
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_54D7
    LD HL,[VARTAB]
    CALL L_43CD
    JP C,L_54D7
    LD E,C
    LD D,$00
    LD HL,[STREND]
    ADD HL,DE
    EX DE,HL
    LD HL,[FRETOP]
    CALL L_43CD
    JP C,L_5510
    POP AF
L_54C1:
    LD A,C
    CALL L_473C
    POP HL
    POP BC
    EX [SP],HL
    PUSH DE
    PUSH BC
    CALL L_48A5
    POP BC
    POP DE
    EX [SP],HL
    PUSH BC
    PUSH HL
    INC HL
    PUSH AF
    LD [HL],E
    INC HL
    LD [HL],D
L_54D7:
    POP AF
    POP HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    POP BC
    POP HL
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD A,C
    CP B
    JP NC,L_54EA
    LD B,A
L_54EA:
    SUB B
    LD C,A
    POP AF
    CALL NC,L_5506
    INC B
L_54F1:
    DEC B
    JP Z,L_5501
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    JP L_54F1
L_54FC:
    POP BC
    POP BC
    POP BC
    POP BC
L_5500:
    POP BC
L_5501:
    CALL C,L_5506
    POP HL
    RET
L_5506:
    LD A,$20
    INC C
L_5509:
    DEC C
    RET Z
L_550B:
    LD [DE],A
    INC DE
    JP L_5509
L_5510:
    POP AF
    POP HL
    POP BC
    EX [SP],HL
    EX DE,HL
    JP NZ,L_5521
    PUSH BC
    LD A,B
    CALL L_46B9
    CALL L_46FD
    POP BC
L_5521:
    EX [SP],HL
    PUSH BC
    PUSH HL
    JP L_54C1
L_5527:
    CALL CHRGTR
    CALL L_43D3
    INC H
    CALL L_43D3
    JR Z,L_5500
    LD [HL],L
    JR NZ,L_550B
    LD A,[HL]
    CP $2C
    JP NZ,L_554B
    CALL CHRGTR
    CALL L_512A
    CP $02
    JP Z,DERBFM
    CALL L_5122
    XOR A
L_554B:
    PUSH AF
    CALL L_43D3
    ADD HL,HL
    POP AF
    EX [SP],HL
    PUSH AF
    LD A,L
    OR A
    JP Z,L_1418
    PUSH HL
    CALL L_46B9
    EX DE,HL
    POP BC
L_555E:
    POP AF
    PUSH AF
    JP Z,L_5585
    CALL L_4299
    JP NZ,L_556C
    CALL L_41F5
L_556C:
    CP $03
    JP Z,L_557E
L_5571:
    LD [HL],A
    INC HL
    DEC C
    JP NZ,L_555E
    POP AF
    CALL L_17E9
    JP L_46FD
L_557E:
    LD HL,[SAVSTK]
    LD SP,HL
    JP ENDCON
L_5585:
    CALL L_57C2
    JP C,DERRPE
    JP L_5571
FN_EOF:
    CALL L_5136
    JP Z,DERBFN
    CP $02
    JP Z,DERBFM
L_5599:
    LD HL,$0027
    ADD HL,BC
    LD A,[HL]
    OR A
    JP Z,L_55C3
    LD A,[BC]
    CP $03
    JP Z,L_55C3
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_55B8
    PUSH BC
    LD H,B
    LD L,C
    CALL L_577D
    POP BC
    JP L_5599
L_55B8:
    LD A,$80
    SUB [HL]
    LD C,A
    LD B,$00
    ADD HL,BC
    INC HL
    LD A,[HL]
    SUB $1A
L_55C3:
    SUB $01
    SBC A,A
    JP L_287F
L_55C9:
    LD D,B
    LD E,C
    INC DE
    LD HL,$0027
    ADD HL,BC
    PUSH BC
    XOR A
    LD [HL],A
    CALL L_57B1
    LD A,[D_0821]
    CALL L_5A9E
    CP $FF
    JP Z,DERTMF
    DEC A
    JP Z,DERDIO
    DEC A
    JP NZ,L_55F5
    POP DE
    XOR A
    LD [DE],A
    LD C,$10
    INC DE
    CALL L_0005
    JP DERDFL
L_55F5:
    INC A
    JP Z,DERTMF
    POP BC
    LD HL,$0025
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE
    LD [HL],D
    DEC HL
    LD [HL],E
    RET
L_5606:
    CALL L_5139
    JP Z,L_5636
    PUSH BC
    LD A,[BC]
    LD D,B
    LD E,C
    INC DE
    PUSH DE
    CP $02
    JP NZ,L_562C
    LD HL,$5623
    PUSH HL
    PUSH HL
    LD H,B
    LD L,C
    LD A,$1A
    JP L_5679
    .byte $21, $27, $00, $09, $7E, $B7, $C4, $CC, $55
L_562C:
    POP DE
    CALL L_57B1
    LD C,$10
    CALL L_0005
    POP BC
L_5636:
    LD D,$29
    XOR A
L_5639:
    LD [BC],A
    INC BC
    DEC D
    JP NZ,L_5639
    RET
FN_LOC:
    CALL L_5136
    JP Z,DERBFN
    CP $03
    LD HL,$0026
    JP NZ,L_5651
    LD HL,$00AE
L_5651:
    ADD HL,BC
    LD A,[HL]
    DEC HL
    LD L,[HL]
    JP L_1DD7
FN_LOF:
    CALL L_5136
    JP Z,DERBFN
    LD HL,$0010
    ADD HL,BC
    LD A,[HL]
    JP L_1DD5
L_5666:
    POP HL
    POP AF
L_5668:
    PUSH HL
    PUSH AF
    LD HL,[D_0794]
    LD A,[HL]
    CP $01
    JP Z,L_4500
    CP $03
    JP Z,L_5C65
    POP AF
L_5679:
    PUSH DE
    PUSH BC
    LD B,H
    LD C,L
    PUSH AF
    LD DE,$0027
    ADD HL,DE
    LD A,[HL]
    CP $80
    PUSH HL
    CALL Z,L_55C9
    POP HL
    INC [HL]
    LD C,[HL]
    LD B,$00
    INC HL
    POP AF
    PUSH AF
    LD D,[HL]
    CP $0D
    LD [HL],B
    JP Z,L_569D
    ADD A,$E0
    LD A,D
    ADC A,B
    LD [HL],A
L_569D:
    ADD HL,BC
    POP AF
    POP BC
    POP DE
    LD [HL],A
    POP HL
    RET
L_56A4:
    DEC DE
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],$80
    INC HL
    LD [HL],$80
    POP HL
    EX [SP],HL
    LD B,H
    LD C,L
    PUSH HL
    LD A,[D_081F]
    OR A
    JP Z,L_56C8
    LD HL,$0022
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],$00
    JP L_570D
L_56C8:
    LD HL,$000D
    ADD HL,BC
    LD A,E
    RLA
    LD A,D
    RLA
    LD D,[HL]
    CP D
    JP Z,L_5705
    PUSH DE
    PUSH AF
    PUSH HL
    PUSH BC
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    POP DE
    PUSH DE
    INC DE
    LD C,$10
    CALL L_0005
    POP DE
    POP HL
    POP AF
    LD [HL],A
    PUSH DE
    INC DE
    LD C,$0F
    PUSH DE
    CALL L_0005
    POP DE
    INC A
    JP NZ,L_5703
    LD C,$16
    CALL L_0005
    INC A
    JP Z,DERTMF
L_5703:
    POP BC
    POP DE
L_5705:
    LD HL,$0021
    ADD HL,BC
    LD A,E
    AND $7F
    LD [HL],A
L_570D:
    POP HL
    LD A,[D_07A0]
    OR A
    JP NZ,L_571A
    CALL L_577D
    POP HL
    RET
L_571A:
    LD HL,$0021
    ADD HL,BC
    LD A,[HL]
    CP $7F
    PUSH AF
    LD DE,$0080
    LD HL,$0029
    ADD HL,BC
    PUSH DE
    PUSH HL
    CALL Z,L_573B
    CALL L_55C9
    POP DE
    POP HL
    POP AF
    CALL Z,L_573B
    POP HL
    JP L_17E9
L_573B:
    PUSH BC
    LD B,$80
L_573E:
    LD A,[HL]
    INC HL
    LD [DE],A
    INC DE
    DEC B
    JP NZ,L_573E
    POP BC
    RET
L_5748:
    PUSH BC
    PUSH HL
L_574A:
    LD HL,[D_0794]
    LD A,[HL]
    CP $03
    JP Z,L_5C96
    LD BC,$0028
    ADD HL,BC
    LD A,[HL]
    OR A
    JP Z,L_5768
    DEC HL
    LD A,[HL]
    INC HL
    DEC [HL]
    SUB [HL]
    LD C,A
    ADD HL,BC
    LD A,[HL]
    OR A
    POP HL
    POP BC
    RET
L_5768:
    DEC HL
    LD A,[HL]
    OR A
    JP Z,L_5774
    CALL L_577A
    JP NZ,L_574A
L_5774:
    SCF
    POP HL
    POP BC
    LD A,$1A
    RET
L_577A:
    LD HL,[D_0794]
L_577D:
    PUSH DE
    LD D,H
    LD E,L
    INC DE
    LD BC,$0025
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC BC
    DEC HL
    LD [HL],C
    INC HL
    LD [HL],B
    INC HL
    INC HL
    PUSH HL
    LD C,$80
L_5792:
    INC HL
    LD [HL],$00
    DEC C
    JP NZ,L_5792
    CALL L_57B1
    LD A,[D_0820]
    CALL L_5A9E
    OR A
    LD A,$00
    JP NZ,L_57AA
    LD A,$80
L_57AA:
    POP HL
    LD [HL],A
    DEC HL
    LD [HL],A
    OR A
    POP DE
    RET
L_57B1:
    PUSH BC
    PUSH DE
    PUSH HL
    LD HL,$0028
    ADD HL,DE
    EX DE,HL
    LD C,$1A
    CALL L_0005
    POP HL
    POP DE
    POP BC
    RET
L_57C2:
    CALL L_5748
    RET C
    CP $1A
    SCF
    CCF
    RET NZ
    PUSH BC
    PUSH HL
    LD HL,[D_0794]
    LD BC,$0027
    ADD HL,BC
    LD [HL],$00
    INC HL
    LD [HL],$00
    SCF
    POP HL
    POP BC
    RET
L_57DD:
    CALL L_1A02
    PUSH HL
    CALL L_48A5
    LD A,[HL]
    OR A
    JP Z,DERIFN
    PUSH AF
    INC HL
    LD E,[HL]
    INC HL
    LD H,[HL]
    LD L,E
    LD E,A
    CP $02
    JP C,L_5800
    LD C,[HL]
    INC HL
    LD A,[HL]
    DEC E
    CP $3A
    JP Z,L_5804
    DEC HL
    INC E
L_5800:
    DEC HL
    INC E
    LD C,$40
L_5804:
    DEC E
    JP Z,L_5862
    LD A,C
    AND $DF
    SUB $40
    JP C,L_5862
    CP $1B
    JP NC,L_5862
    LD BC,$07FE
    LD [BC],A
    INC BC
    LD D,$0B
L_581C:
    INC HL
L_581D:
    DEC E
    JP M,L_5852
    LD A,[HL]
    CP $2E
    JP NZ,L_5830
    CALL L_583E
    POP AF
    SCF
    PUSH AF
    JP L_581C
L_5830:
    LD [BC],A
    INC BC
    INC HL
    DEC D
    JP NZ,L_581D
L_5837:
    XOR A
    LD [D_080A],A
    POP AF
    POP HL
    RET
L_583E:
    LD A,D
    CP $0B
    JP Z,L_5862
    CP $03
    JP C,L_5862
    RET Z
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP L_583E
L_5852:
    INC D
    DEC D
    JP Z,L_5837
L_5857:
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP NZ,L_5857
    JP L_5837
L_5862:
    JP DERIFN
ST_NAME:
    CALL L_57DD
    PUSH HL
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    LD C,$0F
    CALL L_0005
    INC A
    JP Z,DERFNF
    LD HL,$07EE
    LD DE,$07FE
    LD B,$0C
L_5885:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC B
    JP NZ,L_5885
    POP HL
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_57DD
    PUSH HL
    LD A,[D_07FE]
    LD HL,$07EE
    CP [HL]
    JP NZ,L_1418
    LD DE,$07FE
    LD C,$0F
    CALL L_0005
    INC A
    JP NZ,DERFAE
    LD C,$17
    LD DE,$07EE
    CALL L_0005
    POP HL
    RET
ST_OPEN:
    LD BC,$17E9
    PUSH BC
    CALL L_1A02
    PUSH HL
    CALL L_48A5
    LD A,[HL]
    OR A
    JP Z,DERBFM
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]
    AND $DF
    LD D,$02
    CP $4F
    JP Z,L_58E6
    LD D,$01
    CP $49
    JP Z,L_58E6
    LD D,$03
    CP $52
    JP NZ,DERBFM
L_58E6:
    POP HL
    CALL L_43D3
    INC L
    PUSH DE
    CP $23
    CALL Z,CHRGTR
    CALL L_2075
    CALL L_43D3
    INC L
    LD A,E
    OR A
    JP Z,DERBFN
    POP DE
L_58FE:
    LD E,A
    PUSH DE
    CALL L_5139
    JP NZ,DERFAO
    POP DE
    PUSH BC
    PUSH DE
    CALL L_57DD
    POP DE
    POP BC
    PUSH BC
    PUSH AF
    LD A,D
    CALL L_5ACD
    POP AF
    LD [TEMP],HL
    JP C,L_5931
    LD A,E
    OR A
    JP NZ,L_5931
    LD HL,$0807
    LD A,[HL]
    CP $20
    JP NZ,L_5931
    LD [HL],$42
    INC HL
    LD [HL],$41
    INC HL
    LD [HL],$53
L_5931:
    POP HL
    LD A,D
    PUSH AF
    LD [D_0794],HL
    PUSH HL
    INC HL
    LD DE,$07FE
    LD C,$0C
L_593E:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    JP NZ,L_593E
    XOR A
    LD [HL],A
    LD DE,$0014
    ADD HL,DE
    LD [HL],A
    POP DE
    PUSH DE
    INC DE
    CALL L_57B1
    POP HL
    POP AF
    PUSH AF
    PUSH HL
    CP $02
    JP NZ,L_596F
    PUSH DE
    LD C,$13
    CALL L_0005
    POP DE
L_5963:
    LD C,$16
    CALL L_0005
    INC A
    JP Z,DERTMF
    JP L_5985
L_596F:
    LD C,$0F
    CALL L_0005
    INC A
    JP NZ,L_5985
    POP DE
    POP AF
    PUSH AF
    PUSH DE
    CP $03
    JP NZ,DERFNF
    INC DE
    JP L_5963
L_5985:
    POP DE
    POP AF
    LD [DE],A
    PUSH DE
    LD HL,$0025
    ADD HL,DE
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    POP HL
    LD A,[HL]
    CP $03
    JP Z,L_59A8
    CP $01
    JP NZ,L_43C9
    CALL L_577A
    LD HL,[TEMP]
    RET
L_59A8:
    LD BC,$0029
    ADD HL,BC
    LD C,$80
L_59AE:
    LD [HL],B
    INC HL
    DEC C
    JP NZ,L_59AE
    JP L_43C9
ST_SYSTEM:
    RET NZ
    CALL L_540D
L_59BB:
    JP L_0000
ST_RESET:
    RET NZ
    PUSH HL
    CALL L_540D
    LD C,$19
    CALL L_0005
    PUSH AF
    LD C,$0D
    CALL L_0005
    POP AF
    LD E,A
    LD C,$0E
    CALL L_0005
    POP HL
    RET
ST_KILL:
    CALL L_57DD
    PUSH HL
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    PUSH DE
    LD C,$0F
    CALL L_0005
    INC A
    POP DE
    PUSH DE
    PUSH AF
    LD C,$10
    JP Z,L_59F8
    CALL L_0005
L_59F8:
    POP AF
    POP DE
    JP Z,DERFNF
    LD C,$13
    CALL L_0005
    POP HL
    RET
ST_FILES:
    JP NZ,L_5A14
    PUSH HL
    LD HL,$07FE
    LD [HL],$00
    INC HL
    LD C,$0B
    CALL L_5A96
    POP HL
L_5A14:
    CALL NZ,L_57DD
    XOR A
    LD [D_080A],A
    PUSH HL
    LD HL,$07FF
    LD C,$08
    CALL L_5A92
    LD HL,$0807
    LD C,$03
    CALL L_5A92
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    LD C,$11
    CALL L_0005
    CP $FF
    JP Z,DERFNF
L_5A41:
    AND $03
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    LD C,A
    LD B,$00
    LD HL,$0081
    ADD HL,BC
    LD C,$0B
L_5A51:
    LD A,[HL]
    INC HL
    CALL OUTDO
    LD A,C
    CP $04
    JP NZ,L_5A67
    LD A,[HL]
    CP $20
    JP Z,L_5A64
    LD A,$2E
L_5A64:
    CALL OUTDO
L_5A67:
    DEC C
    JP NZ,L_5A51
    LD A,[D_0A65]
    ADD A,$0D
    LD D,A
    LD A,[D_0790]
    CP D
    JP C,L_5A80
    LD A,$20
    CALL OUTDO
    CALL OUTDO
L_5A80:
    CALL C,L_4221
    LD DE,$07FE
    LD C,$12
    CALL L_0005
    CP $FF
    JP NZ,L_5A41
    POP HL
    RET
L_5A92:
    LD A,[HL]
    CP $2A
    RET NZ
L_5A96:
    LD [HL],$3F
    INC HL
    DEC C
    JP NZ,L_5A96
    RET
L_5A9E:
    PUSH DE
    LD C,A
    PUSH BC
    CALL L_0005
    POP BC
    POP DE
    PUSH AF
    LD HL,$0021
    ADD HL,DE
    INC [HL]
    JP NZ,L_5AB6
    INC HL
    INC [HL]
    JP NZ,L_5AB6
    INC HL
    INC [HL]
L_5AB6:
    LD A,C
    CP $22
    JP NZ,L_5ACB
    POP AF
    OR A
    RET Z
    CP $05
    JP Z,DERTMF
    CP $03
    LD A,$01
    RET Z
    INC A
    RET
L_5ACB:
    POP AF
    RET
L_5ACD:
    CP $03
    RET NZ
    DEC HL
    CALL CHRGTR
    PUSH DE
    LD DE,$0080
    JP Z,L_5AE0
    PUSH BC
    CALL L_1411
    POP BC
L_5AE0:
    PUSH HL
    LD HL,[D_0BEA]
    CALL L_43CD
    JP C,L_1418
    LD HL,$00A9
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    XOR A
    LD E,$07
L_5AF4:
    INC HL
    LD [HL],A
    DEC E
    JP NZ,L_5AF4
    POP HL
    POP DE
    RET
ST_PUT:
    .byte $F6
ST_GET:
    .byte $AF
    LD [D_5D75],A
    CALL L_512A
    CP $03
    JP NZ,DERBFM
    PUSH BC
    PUSH HL
    LD HL,$00AD
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE
    EX [SP],HL
    LD A,[HL]
    CP $2C
    CALL Z,L_1411
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    EX [SP],HL
    LD A,D
    OR E
    JP Z,DERBRN
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    DEC DE
    POP HL
    POP BC
    PUSH HL
    PUSH BC
    LD HL,$00B0
    ADD HL,BC
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    LD HL,$00A9
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL
    PUSH DE
    PUSH HL
    LD HL,$0080
    CALL L_43CD
    POP HL
    JP NZ,L_5B54
    LD DE,$0000
    JP L_5B92
L_5B54:
    LD B,D
    LD C,E
    LD A,$10
    EX DE,HL
    LD HL,$0000
    PUSH HL
L_5B5D:
    ADD HL,HL
    EX [SP],HL
    JP NC,L_5B67
    ADD HL,HL
    INC HL
    JP L_5B68
L_5B67:
    ADD HL,HL
L_5B68:
    EX [SP],HL
    EX DE,HL
    ADD HL,HL
    EX DE,HL
    JP NC,L_5B76
    ADD HL,BC
    EX [SP],HL
    JP NC,L_5B75
    INC HL
L_5B75:
    EX [SP],HL
L_5B76:
    DEC A
    JP NZ,L_5B5D
    LD A,L
    AND $7F
    LD E,A
    LD D,$00
    POP BC
    LD A,L
    LD L,H
    LD H,C
    ADD HL,HL
    JP C,L_1418
    RLA
    JP NC,L_5B8D
    INC HL
L_5B8D:
    LD A,B
    OR A
    JP NZ,L_1418
L_5B92:
    LD [D_5D6F],HL
    POP HL
    POP BC
    PUSH HL
    LD HL,$00B2
    ADD HL,BC
    LD [D_5D71],HL
L_5B9F:
    LD HL,$0029
    ADD HL,BC
    ADD HL,DE
    LD [D_5D73],HL
    POP HL
    PUSH HL
    LD HL,$0080
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    POP DE
    PUSH DE
    CALL L_43CD
    JP C,L_5BBC
    LD H,D
    LD L,E
L_5BBC:
    LD A,[D_5D75]
    OR A
    JP Z,L_5C02
    LD DE,$0080
    CALL L_43CD
    JP NC,L_5BD1
    PUSH HL
    CALL L_5C20
    POP HL
L_5BD1:
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[D_5D73]
    EX DE,HL
    LD HL,[D_5D71]
    CALL L_5C58
    LD [D_5D71],HL
    LD D,B
    LD E,C
    POP BC
    CALL L_5C1F
L_5BE8:
    LD HL,[D_5D6F]
    INC HL
    LD [D_5D6F],HL
    POP HL
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD A,H
    OR L
    LD DE,$0000
    PUSH HL
    JP NZ,L_5B9F
    POP HL
    POP HL
    RET
L_5C02:
    PUSH HL
    CALL L_5C20
    POP HL
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[D_5D71]
    EX DE,HL
    LD HL,[D_5D73]
    CALL L_5C58
    EX DE,HL
    LD [D_5D71],HL
    LD D,B
    LD E,C
    POP BC
    JP L_5BE8
L_5C1F:
    .byte $F6
L_5C20:
    .byte $AF
    LD [D_07A0],A
    PUSH BC
    PUSH DE
    PUSH HL
    EX DE,HL
    LD HL,[D_5D6F]
    EX DE,HL
    LD HL,$00AB
    ADD HL,BC
    PUSH HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    INC DE
    CALL L_43CD
    POP HL
    LD [HL],E
    INC HL
    LD [HL],D
    JP NZ,L_5C47
    LD A,[D_07A0]
    OR A
    JP Z,L_5C54
L_5C47:
    LD HL,$5C54
    PUSH HL
    PUSH BC
    PUSH HL
    LD HL,$0026
    ADD HL,BC
    JP L_56A4
L_5C54:
    POP HL
    POP DE
    POP BC
    RET
L_5C58:
    PUSH BC
L_5C59:
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    DEC BC
    LD A,B
    OR C
    JP NZ,L_5C59
    POP BC
    RET
L_5C65:
    POP AF
    PUSH DE
    PUSH BC
    PUSH AF
    LD B,H
    LD C,L
    CALL L_5CC4
    JP Z,L_5C93
    CALL L_5CB9
    LD HL,$00B1
    ADD HL,BC
    ADD HL,DE
    POP AF
    LD [HL],A
    PUSH AF
    LD HL,$0028
    ADD HL,BC
    LD D,[HL]
    LD [HL],$00
    CP $0D
    JP Z,L_5C8E
    ADD A,$E0
    LD A,D
    ADC A,$00
    LD [HL],A
L_5C8E:
    POP AF
    POP BC
    POP DE
    POP HL
    RET
L_5C93:
    JP DERFOV
L_5C96:
    PUSH DE
    CALL L_5CC2
    JP Z,L_5C93
    CALL L_5CB9
    LD HL,$00B1
    ADD HL,BC
    ADD HL,DE
    LD A,[HL]
    OR A
    POP DE
    POP HL
    POP BC
    RET
L_5CAB:
    LD HL,$00A9
    JP L_5CB4
L_5CB1:
    LD HL,$00B0
L_5CB4:
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    RET
L_5CB9:
    INC DE
    LD HL,$00B0
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    RET
L_5CC2:
    LD B,H
    LD C,L
L_5CC4:
    CALL L_5CB1
    PUSH DE
    CALL L_5CAB
    EX DE,HL
    POP DE
    CALL L_43CD
    RET
L_5CD1:
    CALL CHRGTR
    LD [TEMP],HL
    CALL L_2392
    CALL L_5CE8
    LD A,$FE
    CALL L_53BE
    CALL L_5D22
    JP L_43C9
L_5CE8:
    LD BC,$0D0B
    LD HL,[TXTTAB]
    EX DE,HL
L_5CEF:
    LD HL,[VARTAB]
    CALL L_43CD
    RET Z
    LD HL,$3958
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    LD A,[DE]
    SUB B
    XOR [HL]
    PUSH AF
    LD HL,$3907
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    POP AF
    XOR [HL]
    ADD A,C
    LD [DE],A
    INC DE
    DEC C
    JP NZ,L_5D19
    LD C,$0B
L_5D19:
    DEC B
    JP NZ,L_5CEF
    LD B,$0D
    JP L_5CEF
L_5D22:
    LD BC,$0D0B
    LD HL,[TXTTAB]
    EX DE,HL
L_5D29:
    LD HL,[VARTAB]
    CALL L_43CD
    RET Z
    LD HL,$3907
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    LD A,[DE]
    SUB C
    XOR [HL]
    PUSH AF
    LD HL,$3958
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    POP AF
    XOR [HL]
    ADD A,B
    LD [DE],A
    INC DE
    DEC C
    JP NZ,L_5D53
    LD C,$0B
L_5D53:
    DEC B
    JP NZ,L_5D29
    LD B,$0D
    JP L_5D29
L_5D5C:
    PUSH HL
    LD HL,[CURLIN]
    LD A,H
    AND L
    POP HL
    INC A
    RET NZ
L_5D65:
    PUSH AF
    LD A,[D_0BEC]
    OR A
    JP NZ,L_1418
    POP AF
    RET
D_5D6F:
    .byte $00, $00
D_5D71:
    .byte $00, $00
D_5D73:
    .byte $00, $00
D_5D75:
    .byte $00
L_5D76:
    CALL L_430A
    LD HL,[TXTTAB]
    DEC HL
    LD [HL],$00
    LD HL,[TEMP8]
    LD A,[HL]
    OR A
    JP NZ,L_529A
    JP READY
    .byte $00, $00
L_5D8C:
    LD HL,$603F
    LD SP,HL
    XOR A
    LD [D_0BEC],A
    LD [TOPMEM],HL
    LD SP,HL
    LD HL,$0822
    LD [HL],$3A
    CALL L_4397
    LD [D_0A65],A
    LD [SAVSTK],HL
    LD HL,[D_0001]
    LD BC,$0004
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_427A],HL
    LD [D_4255],HL
    LD [D_12A2],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_41F9],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_41B8],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_413D],HL
    LD C,$0C
    CALL L_0005
    LD [D_081F],A
    OR A
    LD HL,$1514
    JP Z,L_5DEA
    LD HL,$2221
L_5DEA:
    LD [D_0820],HL
    LD HL,$FFFE
    LD [CURLIN],HL
    XOR A
    LD [D_0793],A
    LD [D_0A64],A
    LD [D_0BF3],A
    LD [D_0BED],A
    LD [D_078A],A
    LD HL,$0000
    LD [D_078C],HL
    LD HL,$0080
    LD [D_0BEA],HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    LD HL,$0AE4
    LD [D_0B4C],HL
    LD HL,[D_0006]
    LD [MEMSIZ],HL
    LD A,$03
    LD [D_07C4],A
    LD HL,$5ED4
    LD [TEMP8],HL
    LD A,[D_5ED5]
    OR A
    JP NZ,L_5ED6
    INC A
    LD [D_5ED5],A
    LD HL,$0080
    LD A,[HL]
    OR A
    LD [TEMP8],HL
    JP Z,L_5ED6
    LD B,[HL]
    INC HL
L_5E44:
    LD A,[HL]
    DEC HL
    LD [HL],A
    INC HL
    INC HL
    DEC B
    JP NZ,L_5E44
    DEC HL
    LD [HL],$00
    LD [TEMP8],HL
    LD HL,$007F
    CALL CHRGTR
    OR A
    JP Z,L_5ED6
    CP $2F
    JP Z,L_5E78
    DEC HL
    LD [HL],$22
    LD [TEMP8],HL
    INC HL
L_5E69:
    CP $2F
    JP Z,L_5E78
    CALL CHRGTR
    OR A
    JP NZ,L_5E69
    JP L_5ED6
L_5E78:
    LD [HL],$00
    CALL CHRGTR
L_5E7D:
    CALL L_1C5A
    CP $53
    JP Z,L_5EC2
    CP $4D
    PUSH AF
    JP Z,L_5E90
    CP $46
    JP NZ,SNERR
L_5E90:
    CALL CHRGTR
    CALL L_43D3
    LD A,[D_64CD]
    INC E
    POP AF
    JP Z,L_5EAF
    LD A,D
    OR A
    JP NZ,L_1418
    LD A,E
    CP $10
    JP NC,L_1418
    LD [D_07C4],A
    JP L_5EB4
L_5EAF:
    EX DE,HL
    LD [MEMSIZ],HL
    EX DE,HL
L_5EB4:
    DEC HL
    CALL CHRGTR
    JP Z,L_5ED6
    CALL L_43D3
    CPL
    JP L_5E7D
L_5EC2:
    CALL CHRGTR
    CALL L_43D3
    LD A,[D_64CD]
    INC E
    EX DE,HL
    LD [D_0BEA],HL
    EX DE,HL
    JP L_5EB4
    .byte $00
D_5ED5:
    .byte $00
L_5ED6:
    DEC HL
    LD HL,[MEMSIZ]
    DEC HL
    LD [MEMSIZ],HL
    DEC HL
    PUSH HL
    LD A,[D_07C4]
    LD HL,$5D8A
    LD [D_07A2],HL
    LD DE,$07A4
    LD [D_07C4],A
    INC A
    LD BC,$00A9
L_5EF3:
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    EX DE,HL
    ADD HL,BC
    PUSH HL
    LD HL,[D_0BEA]
    LD BC,$00B2
    ADD HL,BC
    LD B,H
    LD C,L
    POP HL
    DEC A
    JP NZ,L_5EF3
    INC HL
    LD [TXTTAB],HL
    LD [SAVSTK],HL
    POP DE
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A
    JP C,L_42DD
    LD B,$03
L_5F1C:
    OR A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    DEC B
    JP NZ,L_5F1C
    LD A,H
    CP $02
    JP C,L_5F30
    LD HL,$0200
L_5F30:
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A
    JP C,L_42DD
    LD [MEMSIZ],HL
    EX DE,HL
    LD [TOPMEM],HL
    LD [FRETOP],HL
    LD SP,HL
    LD [SAVSTK],HL
    LD HL,[TXTTAB]
    EX DE,HL
    CALL L_42EB
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    DEC HL
    DEC HL
    PUSH HL
    LD HL,$5F9A
    CALL L_4723
    POP HL
    CALL LINPRT
    LD HL,$5F8E
    CALL L_4723
    LD HL,$4723
    LD [D_0D98],HL
    CALL L_4221
    LD HL,$0C7F
    JP L_5D76
    .byte $0D, $0A, $0A, $4F, $77, $6E, $65, $64, $20, $62, $79, $20, $4D, $69, $63, $72
    .byte $6F, $73, $6F, $66, $74, $0D, $0A, $00, $20, $42, $79, $74, $65, $73, $20, $66
    .byte $72, $65, $65, $00, $42, $41, $53, $49, $43, $2D, $38, $30, $20, $52, $65, $76
    .byte $2E, $20, $35, $2E, $32, $31, $0D, $0A, $5B, $43, $50, $2F, $4D, $20, $56, $65
    .byte $72, $73, $69, $6F, $6E, $5D, $0D, $0A, $43, $6F, $70, $79, $72, $69, $67, $68
    .byte $74, $20, $31, $39, $37, $37, $2D, $31, $39, $38, $31, $20, $28, $43, $29, $20
    .byte $62, $79, $20, $4D, $69, $63, $72, $6F, $73, $6F, $66, $74, $0D, $0A, $43, $72
    .byte $65, $61, $74, $65, $64, $3A, $20, $32, $38, $2D, $4A, $75, $6C, $2D, $38, $31
    .byte $0D, $0A, $00, $00, $00, $00, $00, $00, $00, $00

.assert * = $6000, "MBASIC.COM is $5F00 bytes, from $0100."
