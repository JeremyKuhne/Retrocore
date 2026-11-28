;; MODEL 100 ROM: THE STRING PACKAGE
;;
;; Runs at $270C-$2B4B. Model100.asm describes the ROM as a whole and how it is named.

STRCMP:
    CALL FRESTR
    MOV A,M
    INX H
    MOV C,M
    INX H
    MOV B,M
    POP D
    PUSH B
    PUSH PSW
    CALL FRETMP
    POP PSW
    MOV D,A
    MOV E,M
    INX H
    MOV C,M
    INX H
    MOV B,M
    POP H

CSLOOP:
    MOV A,E
    ORA D
    RZ
    MOV A,D
    SUI $01
    RC
    XRA A
    CMP E
    INR A
    RNC
    DCR D
    DCR E
    LDAX B
    INX B
    CMP M
    INX H
    JZ CSLOOP
    CMC
    JMP L_33E9

FN_STR:
    CALL L_39E8

STR1:
    CALL STRLIT
    CALL FREFAC
    LXI B,FINBCK
    PUSH B

STRCPY:
    MOV A,M
    INX H
    PUSH H
    CALL GETSPA
    POP H
    MOV C,M
    INX H
    MOV B,M
    CALL STRAD2
    PUSH H
    MOV L,A
    CALL MOVSTR
    POP D
    RET

STRIN1:
    MVI A,$01

STRINI:
    CALL GETSPA

STRAD2:
    LXI H,$FB89
    PUSH H
    MOV M,A
    INX H
    MOV M,E
    INX H
    MOV M,D
    POP H
    RET

STRLIT:
    DCX H

STRLTI:
    MVI B,$22

STRLT3:
    MOV D,B

STRLT2:
    PUSH H
    MVI C,$FF

STRGET:
    INX H
    MOV A,M
    INR C
    ORA A
    JZ STRFIN
    CMP D
    JZ STRFIN
    CMP B
    JNZ STRGET

STRFIN:
    CPI $22
    CZ CHRGTR
    XTHL
    INX H
    XCHG
    MOV A,C
    CALL STRAD2

PUTNEW:
    LXI D,$FB89
    .byte $3E                           ; MVI A,$D5: skips the next byte

L_2791:
    PUSH D
    LHLD TEMPPT
    SHLD D_FC1A
    MVI A,$03
    STA VALTYP
    CALL L_3465
    LXI D,FRETOP
    RST 3
    SHLD TEMPPT
    POP H
    MOV A,M
    RNZ
    LXI D,$0010
    JMP ERROR

STROUI:
    INX H

STROUT:
    CALL STRLIT

STRPRT:
    CALL FREFAC
    CALL L_3452
    INR D

STRPR2:
    DCR D
    RZ
    LDAX B
    RST 4
    CPI $0D
    CZ L_4BD1
    INX B
    JMP STRPR2

GETSPA:
    ORA A
    .byte $0E                           ; MVI C,$F1: skips the next byte

L_27CA:
    POP PSW
    PUSH PSW
    LHLD STKTOP
    XCHG
    LHLD FRETOP
    CMA
    MOV C,A
    MVI B,$FF
    DAD B
    INX H
    RST 3
    JC GARBAG
    SHLD FRETOP
    INX H
    XCHG

PPSWRT:
    POP PSW
    RET

GARBAG:
    POP PSW
    LXI D,$000E
    JZ ERROR
    CMP A
    PUSH PSW
    LXI B,L_27CA
    PUSH B

GARBA2:
    LHLD MEMSIZ

FNDVAR:
    SHLD FRETOP
    LXI H,$0000
    PUSH H
    LHLD STREND
    PUSH H
    LXI H,$FB6B

TVAR:
    XCHG
    LHLD TEMPPT
    XCHG
    RST 3
    LXI B,TVAR
    JNZ DVAR2
    LXI H,$FBD9
    SHLD TEMP9
    LHLD ARYTAB
    SHLD ARYTA2
    LHLD VARTAB

SVAR:
    XCHG
    LHLD ARYTA2
    XCHG
    RST 3
    JZ ARYVAR
    MOV A,M
    INX H
    INX H
    INX H
    CPI $03
    JNZ SKPVAR
    CALL DVARS
    XRA A

SKPVAR:
    MOV E,A
    MVI D,$00
    DAD D
    JMP SVAR

ARYVAR:
    LHLD TEMP9
    MOV E,M
    INX H
    MOV D,M
    MOV A,D
    ORA E
    LHLD ARYTAB
    JZ ARYVA4
    XCHG
    SHLD TEMP9
    INX H
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    XCHG
    DAD D
    SHLD ARYTA2
    XCHG
    JMP SVAR

ARYVA2:
    POP B

ARYVA4:
    XCHG
    LHLD STREND
    XCHG
    RST 3
    JZ GRBPAS
    MOV A,M
    INX H
    CALL L_3450
    PUSH H
    DAD B
    CPI $03
    JNZ ARYVA2
    SHLD TEMP8
    POP H
    MOV C,M
    MVI B,$00
    DAD B
    DAD B
    INX H

ARYSTR:
    XCHG
    LHLD TEMP8
    XCHG
    RST 3
    JZ ARYVA4
    LXI B,ARYSTR

DVAR2:
    PUSH B

DVARS:
    XRA A
    ORA M
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    RZ
    MOV B,H
    MOV C,L
    LHLD FRETOP
    RST 3
    MOV H,B
    MOV L,C
    RC
    POP H
    XTHL
    RST 3
    XTHL
    PUSH H
    MOV H,B
    MOV L,C
    RNC
    POP B
    POP PSW
    POP PSW
    PUSH H
    PUSH D
    PUSH B
    RET

GRBPAS:
    POP D
    POP H
    MOV A,H
    ORA L
    RZ
    DCX H
    MOV B,M
    DCX H
    MOV C,M
    PUSH H
    DCX H
    MOV L,M
    MVI H,$00
    DAD B
    MOV D,B
    MOV E,C
    DCX H
    MOV B,H
    MOV C,L
    LHLD FRETOP
    CALL L_3EF3
    POP H
    MOV M,C
    INX H
    MOV M,B
    MOV H,B
    MOV L,C
    DCX H
    JMP FNDVAR

CAT:
    PUSH B
    PUSH H
    LHLD D_FC1A
    XTHL
    CALL EVAL
    XTHL
    CALL L_35D9
    MOV A,M
    PUSH H
    LHLD D_FC1A
    PUSH H
    ADD M
    LXI D,$000F
    JC ERROR
    CALL STRINI
    POP D
    CALL FRETMP
    XTHL
    CALL FRETM2
    PUSH H
    LHLD DSCPTR
    XCHG
    CALL MOVINS
    CALL MOVINS
    LXI H,TSTOP
    XTHL
    PUSH H
    JMP PUTNEW

MOVINS:
    POP H
    XTHL
    MOV A,M
    INX H
    MOV C,M
    INX H
    MOV B,M
    MOV L,A

MOVSTR:
    INR L

MOVLP:
    DCR L
    RZ
    LDAX B
    STAX D
    INX B
    INX D
    JMP MOVLP

FRESTR:
    CALL L_35D9

FREFAC:
    LHLD D_FC1A

FRETM2:
    XCHG

FRETMP:
    CALL FRETMS
    XCHG
    RNZ
    PUSH D
    MOV D,B
    MOV E,C
    DCX D
    MOV C,M
    LHLD FRETOP
    RST 3
    JNZ NOTLST
    MOV B,A
    DAD B
    SHLD FRETOP

NOTLST:
    POP H
    RET

FRETMS:
    LHLD TEMPPT
    DCX H
    MOV B,M
    DCX H
    MOV C,M
    DCX H
    RST 3
    RNZ
    SHLD TEMPPT
    RET

FN_LEN:
    LXI B,SNGFLT
    PUSH B

LEN1:
    CALL FRESTR
    XRA A
    MOV D,A
    MOV A,M
    ORA A
    RET

FN_ASC:
    LXI B,SNGFLT
    PUSH B

ASC2:
    CALL LEN1
    JZ FCERR
    INX H
    MOV E,M
    INX H
    MOV D,M
    LDAX D
    RET

FN_CHR:
    CALL STRIN1
    CALL CONINT

SETSTR:
    LHLD DSCPTR
    MOV M,E

FINBCK:
    POP B
    JMP PUTNEW

L_296D:
    RST 2
    RST 1
    .byte $28                           ; SYNCHR: '('
    CALL GETBYT
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL FRMEVL
    RST 1
    .byte $29                           ; SYNCHR: ')'
    XTHL
    PUSH H
    RST 5
    JZ STRSTR
    CALL CONINT
    JMP CALSPA

STRSTR:
    CALL ASC2

CALSPA:
    POP D
    CALL SPACE2

FN_SPACE:
    CALL CONINT
    MVI A,$20

SPACE2:
    PUSH PSW
    MOV A,E
    CALL STRINI
    MOV B,A
    POP PSW
    INR B
    DCR B
    JZ FINBCK
    LHLD DSCPTR

SPLP:
    MOV M,A
    INX H
    DCR B
    JNZ SPLP
    JMP FINBCK

FN_LEFT:
    CALL PREAM
    XRA A

LEFT3:
    XTHL
    MOV C,A
    .byte $3E                           ; MVI A,$E5: skips the next byte

L_29B2:
    PUSH H

LEFT2:
    PUSH H
    MOV A,M
    CMP B
    JC L_29BB
    MOV A,B
    .byte $11                           ; LXI D,$000E: skips the next two bytes

L_29BB:
    MVI C,$00
    PUSH B
    CALL GETSPA
    POP B
    POP H
    PUSH H
    INX H
    MOV B,M
    INX H
    MOV H,M
    MOV L,B
    MVI B,$00
    DAD B
    MOV B,H
    MOV C,L
    CALL STRAD2
    MOV L,A
    CALL MOVSTR
    POP D
    CALL FRETMP
    JMP PUTNEW

FN_RIGHT:
    CALL PREAM
    POP D
    PUSH D
    LDAX D
    SUB B
    JMP LEFT3

FN_MID:
    XCHG
    MOV A,M
    CALL PREAM2
    INR B
    DCR B
    JZ FCERR
    PUSH B
    CALL MIDRST
    POP PSW
    XTHL
    LXI B,LEFT2
    PUSH B
    DCR A
    CMP M
    MVI B,$00
    RNC
    MOV C,A
    MOV A,M
    SUB C
    CMP E
    MOV B,A
    RC
    MOV B,E
    RET

FN_VAL:
    CALL LEN1
    JZ SNGFLT
    MOV E,A
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    PUSH H
    DAD D
    MOV B,M
    SHLD D_F67E
    MOV A,B
    STA D_FBE6
    MOV M,D
    XTHL
    PUSH B
    DCX H
    RST 2
    CALL L_3840
    LXI H,$0000
    SHLD D_F67E
    POP B
    POP H
    MOV M,B
    RET

PREAM:
    XCHG
    RST 1
    .byte $29                           ; SYNCHR: ')'

PREAM2:
    POP B
    POP D
    PUSH B
    MOV B,E
    RET

L_2A37:
    RST 2
    CALL FRMPRN
    RST 5
    MVI A,$01
    PUSH PSW
    JZ WUZSTR
    POP PSW
    CALL CONINT
    ORA A
    JZ FCERR
    PUSH PSW
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL FRMEVL
    CALL L_35D9

WUZSTR:
    RST 1
    .byte $2C                           ; SYNCHR: ','
    PUSH H
    LHLD D_FC1A
    XTHL
    CALL FRMEVL
    RST 1
    .byte $29                           ; SYNCHR: ')'
    PUSH H
    CALL FRESTR
    XCHG
    POP B
    POP H
    POP PSW
    PUSH B
    LXI B,L_383E
    PUSH B
    LXI B,SNGFLT
    PUSH B
    PUSH PSW
    PUSH D
    CALL FRETM2
    POP D
    POP PSW
    MOV B,A
    DCR A
    MOV C,A
    CMP M
    MVI A,$00
    RNC
    LDAX D
    ORA A
    MOV A,B
    RZ
    MOV A,M
    INX H
    MOV B,M
    INX H
    MOV H,M
    MOV L,B
    MVI B,$00
    DAD B
    SUB C
    MOV B,A
    PUSH B
    PUSH D
    XTHL
    MOV C,M
    INX H
    MOV E,M
    INX H
    MOV D,M
    POP H

CHK1:
    PUSH H
    PUSH D
    PUSH B

CHK:
    LDAX D
    CMP M
    JNZ OHWELL
    INX D
    DCR C
    JZ GOTSTR
    INX H
    DCR B
    JNZ CHK
    POP D
    POP D
    POP B

RETZR1:
    POP D
    XRA A
    RET

GOTSTR:
    POP H
    POP D
    POP D
    POP B
    MOV A,B
    SUB H
    ADD C
    INR A
    RET

OHWELL:
    POP B
    POP D
    POP H
    INX H
    DCR B
    JNZ CHK1
    JMP RETZR1

LHSMID:
    RST 1
    .byte $28                           ; SYNCHR: '('
    CALL L_4790
    CALL L_35D9
    PUSH H
    PUSH D
    XCHG
    INX H
    MOV E,M
    INX H
    MOV D,M
    LHLD STREND
    RST 3
    JC NCPMID
    LHLD TXTTAB
    RST 3
    JNC NCPMID
    POP H
    PUSH H
    CALL STRCPY
    POP H
    PUSH H
    CALL L_3465

NCPMID:
    POP H
    XTHL
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    ORA A
    JZ FCERR
    PUSH PSW
    MOV A,M
    CALL MIDRST
    PUSH D
    CALL L_0DA4
    PUSH H
    CALL FRESTR
    XCHG
    POP H
    POP B
    POP PSW
    MOV B,A
    XTHL
    PUSH H
    LXI H,L_383E
    XTHL
    MOV A,C
    ORA A
    RZ
    MOV A,M
    SUB B
    JC FCERR
    INR A
    CMP C
    JC BIGLEN
    MOV A,C

BIGLEN:
    MOV C,B
    DCR C
    MVI B,$00
    PUSH D
    INX H
    MOV E,M
    INX H
    MOV H,M
    MOV L,E
    DAD B
    MOV B,A
    POP D
    XCHG
    MOV C,M
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    XCHG
    MOV A,C
    ORA A
    RZ

MIDLP:
    LDAX D
    MOV M,A
    INX D
    INX H
    DCR C
    RZ
    DCR B
    JNZ MIDLP
    RET

MIDRST:
    MVI E,$FF
    CPI $29
    JZ MID2
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT

MID2:
    RST 1
    .byte $29                           ; SYNCHR: ')'
    RET
