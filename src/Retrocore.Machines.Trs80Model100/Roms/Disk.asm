;; MODEL 100 ROM: OPEN, LOAD, MERGE, SAVE, CLOSE, THE FILE INPUT ROUTINES, LOF, LOC, LFILES AND DSKO$
;;
;; Runs at $4CCB-$5145. Model100.asm describes the ROM as a whole and how it is named.

ST_OPEN:
    LXI B,FINPRT
    PUSH B
    CALL L_4C0F
    JNZ L_4CD7
    MVI D,$F8

L_4CD7:
    RST 1
    .byte $81                           ; SYNCHR: the FOR token
    CPI $84
    MVI E,$01
    JZ L_4CFC
    CPI $96
    JZ L_4CF2
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    RST 1
    .byte $50                           ; SYNCHR: 'P'
    RST 1
    .byte $50                           ; SYNCHR: 'P'
    RST 1
    .byte $80                           ; SYNCHR: the END token
    MVI E,$08
    JMP L_4CFD

L_4CF2:
    RST 2
    RST 1
    .byte $50                           ; SYNCHR: 'P'
    RST 1
    .byte $55                           ; SYNCHR: 'U'
    RST 1
    .byte $54                           ; SYNCHR: 'T'
    MVI E,$02
    .byte $3E

L_4CFC:
    .byte $D7

L_4CFD:
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    RST 1
    .byte $53                           ; SYNCHR: 'S'
    PUSH D
    MOV A,M
    CPI $23
    CZ CHRGTR
    CALL GETBYT
    ORA A
    JZ BNERR
    RST 7
    .byte $18                           ; the hook's number
    .byte $1E

L_4D12:
    PUSH D
    DCX H
    MOV E,A
    RST 2
    JNZ SNERR
    XTHL
    MOV A,E
    PUSH PSW
    PUSH H
    CALL L_4C84
    JNZ AOERR
    POP D
    MOV A,D
    CPI $09
    RST 7
    .byte $1C                           ; the hook's number
    JC IEERR
    PUSH H
    LXI B,$0004
    DAD B
    MOV M,D
    MVI A,$00
    POP H
    JMP L_5123

L_4D38:
    PUSH H
    ORA A
    JNZ L_4D45
    LDA D_FCA7
    ANI $01
    JNZ L_4F08

L_4D45:
    CALL L_4C84
    JZ L_4D5D
    SHLD D_FC8C
    PUSH H
    MVI A,$02
    JC L_5123
    RST 7
    .byte $14                           ; the hook's number
    JMP IEERR

L_4D59:
    CALL L_4EFF
    POP H

L_4D5D:
    PUSH H
    LXI D,$0007
    DAD D
    MOV M,A
    MOV H,A
    MOV L,A
    SHLD D_FC8C
    POP H
    ADD M
    MVI M,$00
    POP H
    RET

L_4D6E:
    STC
    .byte $11

ST_LOAD:
    .byte $F6

ST_MERGE:
    .byte $AF
    PUSH PSW
    DCX H
    RST 2
    CPI $4D
    JZ L_2491
    CALL L_4C0F
    JZ L_1E7B
    MOV A,D
    CPI $F8
    JZ L_1E7B
    CPI $FD
    JZ L_2387
    RST 7
    .byte $1A                           ; the hook's number

L_4D8D:
    POP PSW
    PUSH PSW
    JZ L_4D9F
    MOV A,M
    SUI $2C
    ORA A
    JNZ L_4D9F
    RST 2
    RST 1
    .byte $52                           ; SYNCHR: 'R'
    POP PSW
    STC

L_4D9E:
    PUSH PSW

L_4D9F:
    PUSH PSW
    XRA A
    MVI E,$01
    CALL L_4D12

L_4DA6:
    LHLD D_FC8C
    LXI B,$0007
    DAD B
    POP PSW
    SBB A
    ANI $80
    ORI $01
    STA D_FCA7
    POP PSW
    PUSH PSW
    SBB A
    STA D_FC92
    MOV A,M
    ORA A
    JM L_4E1D
    POP PSW
    CNZ L_20FF
    CALL L_4E22
    XRA A
    CALL L_4CBF
    JMP MAIN

ST_SAVE:
    CPI $4D
    JZ L_22CC
    CALL L_3F2C
    CALL L_4C0F
    JZ L_1ED9
    MOV A,D
    CPI $F8
    JZ L_1ED9
    CPI $FD
    JZ L_2288
    RST 7
    .byte $16                           ; the hook's number
    DCX H
    RST 2
    MVI E,$80
    STC
    JZ L_4DF9
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    ORA A
    MVI E,$02

L_4DF9:
    PUSH PSW
    MOV A,D
    CPI $09
    JC L_4E0B
    MOV A,E
    ANI $80
    JZ L_4E0B
    MVI E,$02
    POP PSW
    XRA A
    PUSH PSW

L_4E0B:
    XRA A
    CALL L_4D12
    POP PSW
    JC L_4E18
    DCX H
    RST 2
    JMP ST_LIST

L_4E18:
    RST 7
    .byte $22                           ; the hook's number
    JMP L_504E

L_4E1D:
    RST 7
    .byte $24                           ; the hook's number
    JMP L_504E

L_4E22:
    LDA D_FCA7
    ORA A
    RM
    XRA A

ST_CLOSE:
    LDA D_FC82
    JNZ L_4E3B
    PUSH H

L_4E2F:
    PUSH PSW
    ORA A
    CALL L_4D38
    POP PSW
    DCR A
    JP L_4E2F
    POP H
    RET

L_4E3B:
    MOV A,M
    CPI $23
    CZ CHRGTR
    CALL GETBYT
    PUSH H
    STC
    CALL L_4D38
    POP H
    MOV A,M
    CPI $2C
    RNZ
    RST 2
    JMP L_4E3B

L_4E52:
    POP H
    POP PSW
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    LHLD D_FC8C
    MVI A,$04
    CALL L_4E65
    RST 7
    .byte $20                           ; the hook's number
    JMP L_504E

L_4E65:
    PUSH PSW
    PUSH D
    XCHG
    LXI H,$0004
    DAD D
    MOV A,M
    XCHG
    POP D
    CPI $09
    JC L_4F1A
    POP PSW
    XTHL
    POP H
    JMP L_5123

L_4E7A:
    PUSH B
    PUSH H
    PUSH D
    LHLD D_FC8C
    MVI A,$06
    CALL L_4E65
    RST 7
    .byte $0E                           ; the hook's number
    JMP L_504E

L_4E8A:
    POP D
    POP H
    POP B
    RET

L_4E8E:
    RST 2
    RST 1
    .byte $24                           ; SYNCHR: '$'
    RST 1
    .byte $28                           ; SYNCHR: '('
    PUSH H
    LHLD D_FC8C
    PUSH H
    LXI H,$0000
    SHLD D_FC8C
    POP H
    XTHL
    CALL GETBYT
    PUSH D
    MOV A,M
    CPI $2C
    JNZ L_4EBB
    RST 2
    CALL L_4CB3
    CPI $01
    JZ L_4EB8
    CPI $04
    JNZ EFERR

L_4EB8:
    POP H
    XRA A
    MOV A,M

L_4EBB:
    PUSH PSW
    RST 1
    .byte $29                           ; SYNCHR: ')'
    POP PSW
    XTHL
    PUSH PSW
    MOV A,L
    ORA A
    JZ FCERR
    PUSH H
    CALL STRINI
    XCHG
    POP B

L_4ECC:
    POP PSW
    PUSH PSW
    JZ L_4EF6
    CALL CHGET
    CPI $03
    JZ L_4EEB

L_4ED9:
    MOV M,A
    INX H
    DCR C
    JNZ L_4ECC
    POP PSW
    POP B
    POP H
    RST 7
    .byte $10                           ; the hook's number
    SHLD D_FC8C
    PUSH B
    JMP PUTNEW

L_4EEB:
    POP PSW
    LHLD CURLIN
    SHLD ERRLIN
    POP H
    JMP READYR

L_4EF6:
    CALL L_4E7A
    JC EFERR
    JMP L_4ED9

L_4EFF:
    CALL L_4F12
    PUSH H
    MVI B,$00
    CALL L_4F0A

L_4F08:
    POP H
    RET

L_4F0A:
    XRA A

L_4F0B:
    MOV M,A
    INX H
    DCR B
    JNZ L_4F0B
    RET

L_4F12:
    LHLD D_FC8C
    LXI D,$0009
    DAD D
    RET

L_4F1A:
    POP PSW
    RET

L_4F1C:
    CALL L_421A
    JZ GONE
    XRA A
    CALL L_4D38
    JMP DSERR

FILINP:
    MVI C,$01

FILGET:
    CPI $23
    RNZ
    PUSH B
    CALL GTBYTC
    RST 1
    .byte $2C                           ; SYNCHR: ','
    MOV A,E
    PUSH H
    CALL L_4CBF
    MOV A,M
    POP H
    POP B
    CMP C
    JZ L_4F43
    JMP BNERR

L_4F43:
    MOV A,M
    RET

L_4F45:
    LXI B,L_3F9C
    PUSH B
    XRA A
    JMP L_4D38

FILIND:
    RST 5
    LXI B,DOASIG
    LXI D,$2C20
    JNZ INPDOR
    MOV E,D
    JMP INPDOR

L_4F5B:
    LXI B,FINPRT
    PUSH B
    CALL FILINP
    CALL L_4790
    CALL L_35D9
    PUSH D
    LXI B,$09BD
    XRA A
    MOV D,A
    MOV E,A

INPDOR:
    PUSH PSW
    PUSH B
    PUSH H

NOTNWT:
    CALL L_4E7A
    JC EFERR
    CPI $20
    JNZ NTSPCI
    INR D
    DCR D
    JNZ NOTNWT

NTSPCI:
    CPI $22
    JNZ NOTQTE
    MOV A,E
    CPI $2C
    MVI A,$22
    JNZ NOTQTE
    MOV D,A
    MOV E,A
    CALL L_4E7A
    JC QUITSI

NOTQTE:
    LXI H,BUF
    MVI B,$FF

LOPCRS:
    MOV C,A
    MOV A,D
    CPI $22
    MOV A,C
    JZ NOTQTL
    CPI $0D
    PUSH H
    JZ ICASLF
    POP H
    CPI $0A
    JNZ NOTQTL

L_4FB0:
    MOV C,A
    MOV A,E
    CPI $2C
    MOV A,C
    CNZ STRCHR
    CALL L_4E7A
    JC QUITSI
    CPI $0A
    JZ L_4FB0
    CPI $0D
    JNZ NOTQTL
    MOV A,E
    CPI $20
    JZ LPCRGT
    CPI $2C
    MVI A,$0D
    JZ LPCRGT

NOTQTL:
    ORA A
    JZ LPCRGT
    CMP D
    JZ QUITSI
    CMP E
    JZ QUITSI
    CALL STRCHR

LPCRGT:
    CALL L_4E7A
    JNC LOPCRS

QUITSI:
    PUSH H
    CPI $22
    JZ MORSPC
    CPI $20
    JNZ NOSKCR

MORSPC:
    CALL L_4E7A
    JC NOSKCR
    CPI $20
    JZ MORSPC
    CPI $2C
    JZ NOSKCR
    CPI $0D
    JNZ BAKUPT

ICASLF:
    CALL L_4E7A
    JC NOSKCR
    CPI $0A
    JZ NOSKCR

BAKUPT:
    LHLD D_FC8C
    MOV C,A
    MVI A,$08
    CALL L_4E65
    RST 7
    .byte $12                           ; the hook's number
    JMP L_504E

NOSKCR:
    POP H

QUIT2B:
    MVI M,$00
    LXI H,BUFMIN
    MOV A,E
    SUI $20
    JZ NUMIMK
    MVI B,$00
    CALL STRLT3
    POP H
    RET

NUMIMK:
    RST 5
    PUSH PSW
    RST 2
    POP PSW
    PUSH PSW
    CC L_3840
    POP PSW
    CNC L_3840
    POP H
    RET

STRCHR:
    ORA A
    RZ
    MOV M,A
    INX H
    DCR B
    RNZ
    POP PSW
    JMP QUIT2B

L_504E:
    MVI E,$37
    .byte $01

AOERR:
    MVI E,$35
    .byte $01

DSERR:
    MVI E,$38
    .byte $01

FFERR:
    .byte $1E, $34, $01

CFERR:
    .byte $1E, $3A, $01

BNERR:
    .byte $1E, $33, $01

IEERR:
    .byte $1E, $32, $01

EFERR:
    .byte $1E, $36, $01

FLERR:
    .byte $1E, $39
    JMP ERROR

FN_LOF:
    RST 7
    .byte $4E                           ; the hook's number

FN_LOC:
    RST 7
    .byte $50                           ; the hook's number

ST_LFILES:
    RST 7
    .byte $52                           ; the hook's number

ST_DSKO:
    RST 7
    .byte $56                           ; the hook's number

L_5073:
    RST 7
    .byte $54                           ; the hook's number

L_5075:
    RST 7
    .byte $28                           ; the hook's number
    MOV A,M
    CPI $3A
    JC L_5096
    PUSH H
    MOV D,E
    CALL L_4C7D
    JZ L_5090

L_5085:
    CPI $3A
    JZ L_509B
    CALL L_4C7D
    JP L_5085

L_5090:
    MOV E,D
    POP H
    XRA A
    RST 7
    .byte $2A                           ; the hook's number
    RET

L_5096:
    RST 7
    .byte $2E                           ; the hook's number
    JMP L_504E

L_509B:
    MOV A,D
    SUB E
    DCR A
    CPI $02
    JNC L_50A8
    RST 7
    .byte $2C                           ; the hook's number
    JMP L_504E

L_50A8:
    CPI $05
    JNC L_504E
    POP B
    PUSH D
    PUSH B
    MOV C,A
    MOV B,A
    LXI D,DEVTAB
    XTHL
    PUSH H

L_50B7:
    CALL MAKUPL
    PUSH B
    MOV B,A
    LDAX D
    INX H
    INX D
    CMP B
    POP B
    JNZ L_50DC
    DCR C
    JNZ L_50B7

L_50C8:
    LDAX D
    ORA A
    JM L_50D7
    CPI $31
    JNZ L_50DC
    INX D
    LDAX D
    JMP L_50DC

L_50D7:
    POP H
    POP H
    POP D
    ORA A
    RET

L_50DC:
    ORA A
    JM L_50C8

L_50E0:
    LDAX D
    ORA A
    INX D
    JP L_50E0
    MOV C,B
    POP H
    PUSH H
    LDAX D
    ORA A
    JNZ L_50B7
    JMP L_504E

DEVTAB:
    .byte $4C, $43, $44, $FF, $43, $52, $54, $FE, $43, $41, $53, $FD, $43, $4F, $4D, $FC
    .byte "WAND", $FB, $4C, $50, $54, $FA, $4D, $44, $4D, $F9, $52, $41, $4D
    .byte $F8, $00

DEVDSP:
    .word L_14D2                        ; LCD:
    .word L_14F2                        ; CRT:
    .word L_167F                        ; CAS:
    .word L_1762                        ; COM:
    .word L_1877                        ; WAND:
    .word L_1754                        ; LPT:
    .word L_17D1                        ; MDM:
    .word L_14FC                        ; RAM:

L_5123:
    RST 7
    .byte $30                           ; the hook's number
    PUSH H
    PUSH D
    PUSH PSW
    LXI D,$0004
    DAD D
    MVI A,$FF
    SUB M
    ADD A
    MOV E,A
    MVI D,$00
    LXI H,DEVDSP
    DAD D
    MOV E,M
    INX H
    MOV D,M
    POP PSW
    MOV L,A
    MVI H,$00
    DAD D
    MOV E,M
    INX H
    MOV D,M
    XCHG
    POP D
    XTHL
    RET
