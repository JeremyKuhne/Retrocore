;; MODEL 100 ROM: THE FORMULA EVALUATOR, THE OPERATORS, LPOS, POS, INP, OUT AND THE ARGUMENT HELPERS
;;
;; Runs at $0DA9-$113A. Model100.asm describes the ROM as a whole and how it is named.

FRMPRN:
    RST 1
    .byte $28                           ; SYNCHR: '('

FRMEVL:
    DCX H

FRMCHK:
    MVI D,$00

LPOPER:
    PUSH D
    MVI C,$01
    CALL L_3EFF
    CALL EVAL

TSTOP:
    SHLD TEMP2

RETAOP:
    LHLD TEMP2
    POP B
    MOV A,M
    SHLD TEMP3
    CPI $D0
    RC
    CPI $DF
    RNC
    CPI $DC
    JNC DORELS
    SUI $D0
    MOV E,A
    JNZ L_0DDC
    LDA VALTYP
    CPI $03
    MOV A,E
    JZ CAT

L_0DDC:
    LXI H,OPTAB
    MVI D,$00
    DAD D
    MOV A,B
    MOV D,M
    CMP D
    RNC
    PUSH B
    LXI B,RETAOP
    PUSH B
    MOV A,D
    CPI $51
    JC ANDORD
    ANI $FE
    CPI $7A
    JZ ANDORD

NUMREL:
    LXI H,$FC1A
    LDA VALTYP
    SUI $03
    JZ TMERR
    ORA A
    LHLD D_FC1A
    PUSH H
    JM VPUSHD
    LHLD D_FC18
    PUSH H
    JPO VPUSHD
    LHLD D_FC1E
    PUSH H
    LHLD D_FC1C
    PUSH H

VPUSHD:
    ADI $03
    MOV C,E
    MOV B,A
    PUSH B
    LXI B,APPLOP

FINTMP:
    PUSH B
    LHLD TEMP3
    JMP LPOPER

DORELS:
    MVI D,$00

L_0E2B:
    SUI $DC
    JC FINREL
    CPI $03
    JNC FINREL
    CPI $01
    RAL
    XRA D
    CMP D
    MOV D,A
    JC SNERR
    SHLD TEMP3
    RST 2
    JMP L_0E2B

ANDORD:
    PUSH D
    CALL FN_CINT
    POP D
    PUSH H
    LXI B,DANDOR
    JMP FINTMP

FINREL:
    MOV A,B
    CPI $64
    RNC
    PUSH B
    PUSH D
    LXI D,$6405
    LXI H,DOCMP
    PUSH H
    RST 5
    JNZ NUMREL
    LHLD D_FC1A
    PUSH H
    LXI B,STRCMP
    JMP FINTMP

APPLOP:
    POP B
    MOV A,C
    STA DORES
    LDA VALTYP
    CMP B
    JNZ VALNSM
    CPI $02
    JZ INTDPC
    CPI $04
    JZ SNGDPC
    JNC DBLDPC

VALNSM:
    MOV D,A
    MOV A,B
    CPI $08
    JZ STKDBL
    MOV A,D
    CPI $08
    JZ FACDBL
    MOV A,B
    CPI $04
    JZ STKSNG
    MOV A,D
    CPI $03
    JZ TMERR
    JNC FACSNG

INTDPC:
    LXI H,$0310
    MVI B,$00
    DAD B
    DAD B
    MOV C,M
    INX H
    MOV B,M
    POP D
    LHLD D_FC1A
    PUSH B
    RET

STKDBL:
    CALL FN_CDBL

DBLDPC:
    CALL L_3484
    POP H
    SHLD D_FC1C
    POP H
    SHLD D_FC1E

SNGDBL:
    POP B
    POP D
    CALL L_3432

SETDBL:
    CALL FN_CDBL
    LXI H,$02F8

DODSP:
    LDA DORES
    RLC
    ADD L
    MOV L,A
    ADC H
    SUB L
    MOV H,A
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    PCHL

FACDBL:
    MOV A,B
    PUSH PSW
    CALL L_3484
    POP PSW
    STA VALTYP
    CPI $04
    JZ SNGDBL
    POP H
    SHLD D_FC1A
    JMP SETDBL

STKSNG:
    CALL FN_CSNG

SNGDPC:
    POP B
    POP D

SNGDO:
    LXI H,$0304
    JMP DODSP

FACSNG:
    POP H
    CALL L_3422
    CALL L_3543
    CALL L_343D
    POP H
    SHLD D_FC18
    POP H
    SHLD D_FC1A
    JMP SNGDO

INTDIV:
    PUSH H
    XCHG
    CALL L_3543
    POP H
    CALL L_3422
    CALL L_3543
    JMP L_380C

EVAL:
    RST 2
    JZ MOERR
    JC L_3840
    CALL L_40F2
    JNC ISVAR
    CPI $D0
    JZ EVAL
    CPI $2E
    JZ L_3840
    CPI $D1
    JZ DOMIN
    CPI $22
    JZ STRLTI
    CPI $CE
    JZ NOTER
    CPI $C5
    JNZ L_0F51
    RST 2
    LDA ERRFLG
    PUSH H
    CALL SNGFLT
    POP H
    RET

L_0F51:
    CPI $C4
    JNZ L_0F60
    RST 2
    PUSH H
    LHLD ERRLIN
    CALL L_37DB
    POP H
    RET

L_0F60:
    CPI $AA
    JZ L_1904
    CPI $AB
    JZ L_1924
    CPI $AC
    JZ L_1955
    CPI $B7
    JZ L_1D9B
    CPI $CC
    JZ L_1DB9
    CPI $C3
    JNZ L_0FA3
    RST 2
    RST 1
    .byte $28                           ; SYNCHR: '('
    CPI $23
    JNZ NVRFIL
    CALL GTBYTC
    PUSH H
    CALL L_4C84
    XCHG
    POP H
    JMP VARRET

NVRFIL:
    CALL L_482C

VARRET:
    RST 1
    .byte $29                           ; SYNCHR: ')'
    PUSH H
    XCHG
    MOV A,H
    ORA L
    JZ FCERR
    CALL L_3510
    POP H
    RET

L_0FA3:
    CPI $C7
    JZ L_2A37
    CPI $C9
    JZ L_4BEA
    CPI $C6
    JZ L_296D
    CPI $84
    JZ L_4E8E
    CPI $CA
    JZ L_1D90
    CPI $C8
    JZ L_5073
    SUI $DF
    JNC NTMRND

PARCHK:
    CALL FRMPRN
    RST 1
    .byte $29                           ; SYNCHR: ')'
    RET

DOMIN:
    MVI D,$7D
    CALL LPOPER
    LHLD TEMP2
    PUSH H
    CALL L_33F6

LABBCK:
    POP H
    RET

ISVAR:
    CALL L_4790

RETVAR:
    PUSH H
    XCHG
    SHLD D_FC1A
    RST 5
    CNZ L_347E
    POP H
    RET

MAKUPL:
    MOV A,M

MAKUPS:
    CPI $61
    RC
    CPI $7B
    RNC
    ANI $5F
    RET

NTMRND:
    MVI B,$00
    RLC
    MOV C,A
    PUSH B
    RST 2
    MOV A,C
    CPI $39
    JC OKNORM
    CALL FRMPRN
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL L_35D9
    XCHG
    LHLD D_FC1A
    XTHL
    PUSH H
    XCHG
    CALL GETBYT
    XCHG
    XTHL
    JMP FINGO

OKNORM:
    CALL PARCHK
    XTHL
    MOV A,L
    CPI $0E
    JC NOTFRF
    CPI $1D
    JNC NOTFRF
    RST 5
    PUSH H
    CC FN_CDBL
    POP H

NOTFRF:
    LXI D,LABBCK
    PUSH D

FINGO:
    LXI B,FUNDSP

DISPAT:
    DAD B
    MOV C,M
    INX H
    MOV H,M
    MOV L,C
    PCHL

MINPLS:
    DCR D
    CPI $D1
    RZ
    CPI $2D
    RZ
    INR D
    CPI $2B
    RZ
    CPI $D0
    RZ
    DCX H
    RET

DOCMP:
    INR A
    ADC A
    POP B
    ANA B
    ADI $FF
    SBB A
    CALL L_340A
    JMP RETAPG

NOTER:
    MVI D,$5A
    CALL LPOPER
    CALL FN_CINT
    MOV A,L
    CMA
    MOV L,A
    MOV A,H
    CMA
    MOV H,A
    SHLD D_FC1A
    POP B

RETAPG:
    JMP RETAOP

GETYPR:
    LDA VALTYP
    CPI $08
    DCR A
    DCR A
    DCR A
    RET

DANDOR:
    MOV A,B
    PUSH PSW
    CALL FN_CINT
    POP PSW
    POP D
    CPI $7A
    JZ L_37DF
    CPI $7B
    JZ L_377E
    LXI B,GIVINT
    PUSH B
    CPI $46
    JNZ NOTOR
    MOV A,E
    ORA L
    MOV L,A
    MOV A,H
    ORA D
    RET

NOTOR:
    CPI $50
    JNZ NOTAND
    MOV A,E
    ANA L
    MOV L,A
    MOV A,H
    ANA D
    RET

NOTAND:
    CPI $3C
    JNZ NOTXOR
    MOV A,E
    XRA L
    MOV L,A
    MOV A,H
    XRA D
    RET

NOTXOR:
    CPI $32
    JNZ NOTEQV
    MOV A,E
    XRA L
    CMA
    MOV L,A
    MOV A,H
    XRA D
    CMA
    RET

NOTEQV:
    MOV A,L
    CMA
    ANA E
    CMA
    MOV L,A
    MOV A,H
    CMA
    ANA D
    CMA
    RET

GIVDBL:
    MOV A,L
    SUB E
    MOV L,A
    MOV A,H
    SBB D
    MOV H,A
    JMP L_37DB

FN_LPOS:
    LDA LPTPOS
    JMP SNGFLT

FN_POS:
    LDA TTYPOS

SNGFLT:
    MOV L,A
    XRA A

GIVINT:
    MOV H,A
    JMP L_3510

DOCNVF:
    PUSH H
    ANI $07
    LXI H,DECDSP
    MOV C,A
    MVI B,$00
    DAD B
    CALL DISPAT
    POP H
    RET

ERRDIR:
    PUSH H
    LHLD CURLIN
    INX H
    MOV A,H
    ORA L
    POP H
    RNZ
    MVI E,$0C
    JMP ERROR

L_10F4:
    CPI $7E
    JNZ SNERR
    INX H
    JMP LHSMID

    .byte $C3, $46, $04

FN_INP:
    CALL CONINT
    STA D_F66B
    CALL D_F66A
    JMP SNGFLT

ST_OUT:
    CALL SETIO
    JMP D_F667

GETINT:
    RST 2

GETIN2:
    CALL FRMEVL

INTFR2:
    PUSH H
    CALL FN_CINT
    XCHG
    POP H
    MOV A,D
    ORA A
    RET

SETIO:
    CALL GETBYT
    STA D_F66B
    STA D_F668
    RST 1
    .byte $2C                           ; SYNCHR: ','
    JMP GETBYT

GTBYTC:
    RST 2

GETBYT:
    CALL FRMEVL

CONINT:
    CALL INTFR2
    JNZ FCERR
    DCX H
    RST 2
    MOV A,E
    RET
