;; MODEL 100 ROM: LIST AND LLIST, PEEK AND POKE
;;
;; Runs at $113B-$12CA. Model100.asm describes the ROM as a whole and how it is named.

ST_LLIST:
    MVI A,$01
    STA PRTFLG

ST_LIST:
    POP B
    CALL SCNLIN
    PUSH B
    MOV H,B
    MOV L,C
    SHLD D_FABA

L_114A:
    LXI H,$FFFF
    SHLD CURLIN
    POP H
    SHLD D_FABC
    POP D
    MOV C,M
    INX H
    MOV B,M
    INX H
    MOV A,B
    ORA C
    JZ L_1195
    CALL L_421A
    CZ L_13F3
    PUSH B
    MOV C,M
    INX H
    MOV B,M
    INX H
    PUSH B
    XTHL
    XCHG
    RST 3
    POP B
    JC L_1194
    XTHL
    PUSH H
    PUSH B
    XCHG
    SHLD DOT
    CALL L_39D4
    POP H
    MOV A,M
    CPI $09
    JZ NOSPAL
    MVI A,$20
    RST 4

NOSPAL:
    CALL BUFLIN
    LXI H,BUF
    CALL LISPRT
    CALL L_4BCB
    JMP L_114A

L_1194:
    POP B

L_1195:
    LDA D_F651
    ANA A
    JNZ L_5E82
    MVI A,$1A
    RST 4
    JMP READY

LISPRT:
    MOV A,M
    ORA A
    RZ
    RST 4
    INX H
    JMP LISPRT

BUFLIN:
    LXI B,BUF
    MVI D,$FF
    XRA A
    STA DORES
    JMP L_11B9

L_11B6:
    INX B
    DCR D
    RZ

L_11B9:
    MOV A,M
    INX H
    ORA A
    STAX B
    RZ
    CPI $22
    JNZ L_11CD
    LDA DORES
    XRI $01
    STA DORES
    MVI A,$22

L_11CD:
    CPI $3A
    JNZ L_11E1
    LDA DORES
    RAR
    JC L_11DF
    RAL
    ANI $FD
    STA DORES

L_11DF:
    MVI A,$3A

L_11E1:
    ORA A
    JP L_11B6
    LDA DORES
    RAR
    JC L_11B6
    DCX H
    RAR
    RAR
    JNC L_1233
    MOV A,M
    CPI $FF
    PUSH H
    PUSH B
    LXI H,L_121A
    PUSH H
    RNZ
    DCX B
    LDAX B
    CPI $4D
    RNZ
    DCX B
    LDAX B
    CPI $45
    RNZ
    DCX B
    LDAX B
    CPI $52
    RNZ
    DCX B
    LDAX B
    CPI $3A
    RNZ
    POP PSW
    POP PSW
    POP H
    INR D
    INR D
    INR D
    INR D
    JMP L_1242

L_121A:
    POP B
    POP H
    MOV A,M

L_121D:
    INX H
    JMP L_11B6

L_1221:
    LDA DORES
    ORI $02

L_1226:
    STA DORES
    XRA A
    RET

L_122B:
    LDA DORES
    ORI $04
    JMP L_1226

L_1233:
    RAL
    JC L_121D
    MOV A,M
    CPI $83
    CZ L_1221
    CPI $8E
    CZ L_122B

L_1242:
    MOV A,M
    INX H
    CPI $91
    CZ L_3643
    SUI $7F
    PUSH H
    MOV E,A
    LXI H,RESLST

L_1250:
    MOV A,M
    INX H
    ORA A
    JP L_1250
    DCR E
    JNZ L_1250

MORLN1:
    ANI $7F

L_125C:
    STAX B
    INX B
    DCR D
    JZ PPSWRT
    MOV A,M
    INX H
    ORA A
    JP L_125C
    POP H
    JMP L_11B9

DEL:
    XCHG
    LHLD VARTAB

MLOOP:
    LDAX D
    STAX B
    INX B
    INX D
    RST 3
    JNZ MLOOP
    MOV H,B
    MOV L,C
    SHLD VARTAB
    SHLD ARYTAB
    SHLD STREND
    RET

FN_PEEK:
    CALL FRQINT
    MOV A,M
    JMP SNGFLT

ST_POKE:
    CALL FRMQNT
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    POP D
    STAX D
    RET

FRMQNT:
    CALL FRMEVL
    PUSH H
    CALL FRQINT
    XCHG
    POP H
    RET

FRQINT:
    LXI B,FN_CINT
    PUSH B
    RST 5
    RM
    RST 6
    RM
    CALL FN_CSNG
    LXI B,$3245
    LXI D,$8076
    CALL L_3498
    RC
    LXI B,$6545
    LXI D,$6053
    CALL L_3498
    JNC OVERR
    LXI B,$65C5
    LXI D,$6053
    JMP L_37F4
