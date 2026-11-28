;; MODEL 100 ROM: THE RESTARTS AND THE INTERPRETER'S TABLES: FUNCTIONS, RESERVED WORDS, STATEMENTS, OPERATORS, ERRORS, THE RAM IMAGE AND THE MESSAGES
;;
;; Runs at $0000-$0400. Model100.asm describes the ROM as a whole and how it is named.

.org $0000


.if MODEL = 100
RESET:
    JMP COLD
.else
RESET:
    JMP L_1BA7
.endif

    .byte "MENU", $00

SYNCHR:
    MOV A,M
    XTHL
    CMP M
    JNZ SNERR
    INX H
    XTHL

CHRGET:
    JMP CHRGTR

L_0013:
    XCHG
    LHLD D_F6EB
    XCHG

DCOMPR:
    MOV A,H
    SUB D
    RNZ
    MOV A,L
    SUB E
    RET

L_001E:
    MVI A,$20

OUTDO:
    JMP LCD

    .byte $00

TRAP:
    JMP D_F602

    .byte $00

GETYPE:
    JMP GETYPR

    .byte $00

RST55:
    DI
    JMP D_F5F9

VSIGN:
    JMP L_33DC

    .byte $00

RST65:
    DI
    JMP L_6DAC

RST38:
    JMP HOOK

    .byte $00

RST75:
    DI
    JMP L_1B32

FUNDSP:
    .word FN_SGN                        ; $DF SGN
    .word FN_INT                        ; $E0 INT
    .word FN_ABS                        ; $E1 ABS
    .word FN_FRE                        ; $E2 FRE
    .word FN_INP                        ; $E3 INP
    .word FN_LPOS                       ; $E4 LPOS
    .word FN_POS                        ; $E5 POS
    .word FN_SQR                        ; $E6 SQR
    .word FN_RND                        ; $E7 RND
    .word FN_LOG                        ; $E8 LOG
    .word FN_EXP                        ; $E9 EXP
    .word FN_COS                        ; $EA COS
    .word FN_SIN                        ; $EB SIN
    .word FN_TAN                        ; $EC TAN
    .word FN_ATN                        ; $ED ATN
    .word FN_PEEK                       ; $EE PEEK
    .word FN_EOF                        ; $EF EOF
    .word FN_LOC                        ; $F0 LOC
    .word FN_LOF                        ; $F1 LOF
    .word FN_CINT                       ; $F2 CINT
    .word FN_CSNG                       ; $F3 CSNG
    .word FN_CDBL                       ; $F4 CDBL
    .word FN_FIX                        ; $F5 FIX
    .word FN_LEN                        ; $F6 LEN
    .word FN_STR                        ; $F7 STR$
    .word FN_VAL                        ; $F8 VAL
    .word FN_ASC                        ; $F9 ASC
    .word FN_CHR                        ; $FA CHR$
    .word FN_SPACE                      ; $FB SPACE$
    .word FN_LEFT                       ; $FC LEFT$
    .word FN_RIGHT                      ; $FD RIGHT$
    .word FN_MID                        ; $FE MID$

RESLST:
    KEYWORD "END"                       ; $80
    KEYWORD "FOR"                       ; $81
    KEYWORD "NEXT"                      ; $82
    KEYWORD "DATA"                      ; $83
    KEYWORD "INPUT"                     ; $84
    KEYWORD "DIM"                       ; $85
    KEYWORD "READ"                      ; $86
    KEYWORD "LET"                       ; $87
    KEYWORD "GOTO"                      ; $88
    KEYWORD "RUN"                       ; $89
    KEYWORD "IF"                        ; $8A
    KEYWORD "RESTORE"                   ; $8B
    KEYWORD "GOSUB"                     ; $8C
    KEYWORD "RETURN"                    ; $8D
    KEYWORD "REM"                       ; $8E
    KEYWORD "STOP"                      ; $8F
    KEYWORD "WIDTH"                     ; $90
    KEYWORD "ELSE"                      ; $91
    KEYWORD "LINE"                      ; $92
    KEYWORD "EDIT"                      ; $93
    KEYWORD "ERROR"                     ; $94
    KEYWORD "RESUME"                    ; $95
    KEYWORD "OUT"                       ; $96
    KEYWORD "ON"                        ; $97
    KEYWORD "DSKO$"                     ; $98
    KEYWORD "OPEN"                      ; $99
    KEYWORD "CLOSE"                     ; $9A
    KEYWORD "LOAD"                      ; $9B
    KEYWORD "MERGE"                     ; $9C
    KEYWORD "FILES"                     ; $9D
    KEYWORD "SAVE"                      ; $9E
    KEYWORD "LFILES"                    ; $9F
    KEYWORD "LPRINT"                    ; $A0
    KEYWORD "DEF"                       ; $A1
    KEYWORD "POKE"                      ; $A2
    KEYWORD "PRINT"                     ; $A3
    KEYWORD "CONT"                      ; $A4
    KEYWORD "LIST"                      ; $A5
    KEYWORD "LLIST"                     ; $A6
    KEYWORD "CLEAR"                     ; $A7
    KEYWORD "CLOAD"                     ; $A8
    KEYWORD "CSAVE"                     ; $A9
    KEYWORD "TIME$"                     ; $AA
    KEYWORD "DATE$"                     ; $AB
    KEYWORD "DAY$"                      ; $AC
    KEYWORD "COM"                       ; $AD
    KEYWORD "MDM"                       ; $AE
    KEYWORD "KEY"                       ; $AF
    KEYWORD "CLS"                       ; $B0
    KEYWORD "BEEP"                      ; $B1
    KEYWORD "SOUND"                     ; $B2
    KEYWORD "LCOPY"                     ; $B3
    KEYWORD "PSET"                      ; $B4
    KEYWORD "PRESET"                    ; $B5
    KEYWORD "MOTOR"                     ; $B6
    KEYWORD "MAX"                       ; $B7
    KEYWORD "POWER"                     ; $B8
    KEYWORD "CALL"                      ; $B9
    KEYWORD "MENU"                      ; $BA
    KEYWORD "IPL"                       ; $BB
    KEYWORD "NAME"                      ; $BC
    KEYWORD "KILL"                      ; $BD
    KEYWORD "SCREEN"                    ; $BE
    KEYWORD "NEW"                       ; $BF
    KEYWORD "TAB("                      ; $C0
    KEYWORD "TO"                        ; $C1
    KEYWORD "USING"                     ; $C2
    KEYWORD "VARPTR"                    ; $C3
    KEYWORD "ERL"                       ; $C4
    KEYWORD "ERR"                       ; $C5
    KEYWORD "STRING$"                   ; $C6
    KEYWORD "INSTR"                     ; $C7
    KEYWORD "DSKI$"                     ; $C8
    KEYWORD "INKEY$"                    ; $C9
    KEYWORD "CSRLIN"                    ; $CA
    KEYWORD "OFF"                       ; $CB
    KEYWORD "HIMEM"                     ; $CC
    KEYWORD "THEN"                      ; $CD
    KEYWORD "NOT"                       ; $CE
    KEYWORD "STEP"                      ; $CF
    .byte $AB                           ; $D0 +
    .byte $AD                           ; $D1 -
    .byte $AA                           ; $D2 *
    .byte $AF                           ; $D3 /
    .byte $DE                           ; $D4 ^
    KEYWORD "AND"                       ; $D5
    KEYWORD "OR"                        ; $D6
    KEYWORD "XOR"                       ; $D7
    KEYWORD "EQV"                       ; $D8
    KEYWORD "IMP"                       ; $D9
    KEYWORD "MOD"                       ; $DA
    .byte $DC                           ; $DB \
    .byte $BE                           ; $DC >
    .byte $BD                           ; $DD =
    .byte $BC                           ; $DE <
    KEYWORD "SGN"                       ; $DF
    KEYWORD "INT"                       ; $E0
    KEYWORD "ABS"                       ; $E1
    KEYWORD "FRE"                       ; $E2
    KEYWORD "INP"                       ; $E3
    KEYWORD "LPOS"                      ; $E4
    KEYWORD "POS"                       ; $E5
    KEYWORD "SQR"                       ; $E6
    KEYWORD "RND"                       ; $E7
    KEYWORD "LOG"                       ; $E8
    KEYWORD "EXP"                       ; $E9
    KEYWORD "COS"                       ; $EA
    KEYWORD "SIN"                       ; $EB
    KEYWORD "TAN"                       ; $EC
    KEYWORD "ATN"                       ; $ED
    KEYWORD "PEEK"                      ; $EE
    KEYWORD "EOF"                       ; $EF
    KEYWORD "LOC"                       ; $F0
    KEYWORD "LOF"                       ; $F1
    KEYWORD "CINT"                      ; $F2
    KEYWORD "CSNG"                      ; $F3
    KEYWORD "CDBL"                      ; $F4
    KEYWORD "FIX"                       ; $F5
    KEYWORD "LEN"                       ; $F6
    KEYWORD "STR$"                      ; $F7
    KEYWORD "VAL"                       ; $F8
    KEYWORD "ASC"                       ; $F9
    KEYWORD "CHR$"                      ; $FA
    KEYWORD "SPACE$"                    ; $FB
    KEYWORD "LEFT$"                     ; $FC
    KEYWORD "RIGHT$"                    ; $FD
    KEYWORD "MID$"                      ; $FE
    .byte $A7                           ; $FF '
    .byte $80                           ; the end

STMDSP:
    .word ST_END                        ; $80 END
    .word ST_FOR                        ; $81 FOR
    .word ST_NEXT                       ; $82 NEXT
    .word ST_DATA                       ; $83 DATA
    .word ST_INPUT                      ; $84 INPUT
    .word ST_DIM                        ; $85 DIM
    .word ST_READ                       ; $86 READ
    .word ST_LET                        ; $87 LET
    .word ST_GOTO                       ; $88 GOTO
    .word ST_RUN                        ; $89 RUN
    .word ST_IF                         ; $8A IF
    .word ST_RESTORE                    ; $8B RESTORE
    .word ST_GOSUB                      ; $8C GOSUB
    .word ST_RETURN                     ; $8D RETURN
    .word ST_REM                        ; $8E REM
    .word ST_STOP                       ; $8F STOP
    .word ST_WIDTH                      ; $90 WIDTH
    .word ST_REM                        ; $91 ELSE
    .word ST_LINE                       ; $92 LINE
    .word ST_EDIT                       ; $93 EDIT
    .word ST_ERROR                      ; $94 ERROR
    .word ST_RESUME                     ; $95 RESUME
    .word ST_OUT                        ; $96 OUT
    .word ST_ON                         ; $97 ON
    .word ST_DSKO                       ; $98 DSKO$
    .word ST_OPEN                       ; $99 OPEN
    .word ST_CLOSE                      ; $9A CLOSE
    .word ST_LOAD                       ; $9B LOAD
    .word ST_MERGE                      ; $9C MERGE
    .word ST_FILES                      ; $9D FILES
    .word ST_SAVE                       ; $9E SAVE
    .word ST_LFILES                     ; $9F LFILES
    .word ST_LPRINT                     ; $A0 LPRINT
    .word ST_DEF                        ; $A1 DEF
    .word ST_POKE                       ; $A2 POKE
    .word ST_PRINT                      ; $A3 PRINT
    .word ST_CONT                       ; $A4 CONT
    .word ST_LIST                       ; $A5 LIST
    .word ST_LLIST                      ; $A6 LLIST
    .word ST_CLEAR                      ; $A7 CLEAR
    .word ST_CLOAD                      ; $A8 CLOAD
    .word ST_CSAVE                      ; $A9 CSAVE
    .word ST_TIME                       ; $AA TIME$
    .word ST_DATE                       ; $AB DATE$
    .word ST_DAY                        ; $AC DAY$
    .word ST_COM                        ; $AD COM
    .word ST_COM                        ; $AE MDM
    .word ST_KEY                        ; $AF KEY
    .word CLS                           ; $B0 CLS
    .word ST_BEEP                       ; $B1 BEEP
    .word ST_SOUND                      ; $B2 SOUND
    .word PRTLCD                        ; $B3 LCOPY
    .word ST_PSET                       ; $B4 PSET
    .word ST_PRESET                     ; $B5 PRESET
    .word ST_MOTOR                      ; $B6 MOTOR
    .word ST_MAX                        ; $B7 MAX
    .word ST_POWER                      ; $B8 POWER
    .word ST_CALL                       ; $B9 CALL
    .word MENU                          ; $BA MENU
    .word ST_IPL                        ; $BB IPL
    .word ST_NAME                       ; $BC NAME
    .word ST_KILL                       ; $BD KILL
    .word ST_SCREEN                     ; $BE SCREEN
    .word ST_NEW                        ; $BF NEW

OPTAB:
    .byte $79                           ; +
    .byte $79                           ; -
    .byte $7C                           ; *
    .byte $7C                           ; /
    .byte $7F                           ; ^
    .byte $50                           ; AND
    .byte $46                           ; OR
    .byte $3C                           ; XOR
    .byte $32                           ; EQV
    .byte $28                           ; IMP
    .byte $7A                           ; MOD
    .byte $7B                           ; \

DECDSP:
    .word FN_CDBL                       ; to double
    .word 0                             ; (unused)
    .word FN_CINT                       ; to integer
    .word L_35D9                        ; string check
    .word FN_CSNG                       ; to single

DBLDSP:
    .word L_2B78                        ; double +
    .word L_2B69                        ; double -
    .word L_2CFF                        ; double *
    .word L_2DC7                        ; double /
    .word L_3D8E                        ; double ^
    .word L_34FA                        ; double compare

SNGDSP:
    .word L_37F4                        ; single +
    .word L_37FD                        ; single -
    .word L_3803                        ; single *
    .word L_380E                        ; single /
    .word L_3D7F                        ; single ^
    .word L_3498                        ; single compare

INTDSP:
    .word L_3704                        ; integer +
    .word L_36F8                        ; integer -
    .word L_3725                        ; integer *
    .word INTDIV                        ; integer /
    .word L_3DF7                        ; integer ^
    .word L_34C2                        ; integer compare

ERRTAB:
    .byte "NF"                          ; 1
    .byte "SN"                          ; 2
    .byte "RG"                          ; 3
    .byte "OD"                          ; 4
    .byte "FC"                          ; 5
    .byte "OV"                          ; 6
    .byte "OM"                          ; 7
    .byte "UL"                          ; 8
    .byte "BS"                          ; 9
    .byte "DD"                          ; 10
    .byte "/0"                          ; 11
    .byte "ID"                          ; 12
    .byte "TM"                          ; 13
    .byte "OS"                          ; 14
    .byte "LS"                          ; 15
    .byte "ST"                          ; 16
    .byte "CN"                          ; 17
    .byte "IO"                          ; 18
    .byte "NR"                          ; 19
    .byte "RW"                          ; 20
    .byte "UE"                          ; 21
    .byte "MO"                          ; 22
    .byte "IE"                          ; 50
    .byte "BN"                          ; 51
    .byte "FF"                          ; 52
    .byte "AO"                          ; 53
    .byte "EF"                          ; 54
    .byte "NM"                          ; 55
    .byte "DS"                          ; 56
    .byte "FL"                          ; 57
    .byte "CF"                          ; 58

RAMIMG:
    .byte $4D, $8A, $00, $00, $F0, $F5, $C9, $00, $00, $FB, $C9, $00, $C9, $00, $00, $C9
    .byte $00, $00, $C3, $31, $14, $3E, $01, $D3, $E8, $21, $40, $00, $11, $A4, $FA, $7E
    .byte $12, $23, $13, $7D, $D6, $48, $C2, $0F, $F6, $D3, $E8, $2A, $A4, $FA, $11

.if MODEL = 100
    .byte $54, $43
.else
    .byte $41, $42
.endif

    .byte $C3, $18, $00, $F3, $3E, $01, $D3, $E8, $C7, $00, $01, $00, $00, $FF, $FF, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $08, $28, $00, $00, $00, $01
    .byte $01, $01, $01, $19, $28, $00, $00, $00, $50, $38, $30, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $64, $FF, $00, $00, $4D, $37, $49, $31

.if MODEL = 100
    .byte $45
.else
    .byte $44
.endif

    .byte $C3, $00, $00, $00, $C9, $00, $C9, $D3, $00, $C9, $DB, $00, $C9, $3A, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $0E, $00, $15, $FD, $FE, $FF, $B2, $FC, $00, $00

ERRMSG:
    .byte " Error", $00, " in ", $00, $4F, $6B, $0D, $0A
    .byte $00, "Break", $00
