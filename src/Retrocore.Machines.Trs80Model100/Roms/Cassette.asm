;; MODEL 100 ROM: THE CASSETTE'S LEADERS, SYNC AND BYTES
;;
;; Runs at $6F46-$7241. Model100.asm describes the ROM as a whole and how it is named.

SYNCW:
    LXI B,$0200

L_6F49:
    MVI A,$55
    PUSH B
    CALL L_6F5E
    POP B
    DCX B
    MOV A,B
    ORA C
    JNZ L_6F49
    MVI A,$7F
    JMP L_6F5E

DATAW:
    CALL L_6F71

L_6F5E:
    MVI B,$08

L_6F60:
    CALL L_6F6A
    DCR B
    JNZ L_6F60
    JMP L_729F

L_6F6A:
    RLC
    LXI D,$1F24
    JC L_6F74

L_6F71:
    LXI D,$4349

L_6F74:
    DCR D
    JNZ L_6F74
    MOV D,A
    MVI A,$D0
    SIM

L_6F7C:
    DCR E
    JNZ L_6F7C
    MVI A,$50
    SIM
    MOV A,D
    RET

SYNCR:
    MVI B,$80

L_6F87:
    CALL L_6FDB
    RC
    MOV A,C
    CPI $08
    JC SYNCR
    CPI $40
    JNC SYNCR
    DCR B
    JNZ L_6F87

L_6F9A:
    CALL L_729F
    RC
    LXI H,$0000
    MVI B,$40

L_6FA3:
    CALL L_7016
    RC
    MOV D,C
    CALL L_7016
    RC
    MOV A,D
    SUB C
    JNC L_6FB3
    CMA
    INR A

L_6FB3:
    CPI $0B
    JC L_6FBA
    INR H
    .byte $3E                           ; MVI A,$2C: skips the next byte

L_6FBA:
    INR L
    DCR B
    JNZ L_6FA3
    MVI A,$40
    CMP L
    JZ L_6FC9
    SUB H
    JNZ L_6F9A

L_6FC9:
    STA D_FF8E
    MVI D,$00

L_6FCE:
    CALL L_6FDB
    RC
    CALL L_7023
    CPI $7F
    JNZ L_6FCE
    RET

L_6FDB:
    MVI C,$00
    LDA D_FF8E
    ANA A
    JZ L_6FFA

L_6FE4:
    CALL L_729F
    RC
    RIM
    RLC
    JNC L_6FE4

L_6FED:
    INR C

L_6FEE:
    INR C
    JZ L_6FE4
    RIM
    RLC
    JC L_6FEE
    JMP L_700D

L_6FFA:
    CALL L_729F
    RC
    RIM
    RLC
    JC L_6FFA

L_7003:
    INR C

L_7004:
    INR C
    JZ L_6FFA
    RIM
    RLC
    JNC L_7004

L_700D:
    LDA D_FF44
    ANA A
    CZ L_7676
    XRA A
    RET

L_7016:
    CALL L_7003
    RC
    MVI C,$00
    CALL L_6FED
    RC
    JMP L_7003

L_7023:
    MOV A,C
    CPI $15
    MOV A,D
    RAL
    MOV D,A
    RET

DATAR:
    CALL L_6FDB
    RC
    MOV A,C
    CPI $15
    JC DATAR
    MVI B,$08

L_7036:
    CALL L_6FDB
    RC
    CALL L_7023
    DCR B
    JNZ L_7036
    XRA A
    RET

L_7043:
    LDA D_FF45
    ANI $F1
    INR E
    DCR E
    JZ L_704F
    ORI $08

L_704F:
    OUT $E8
    STA D_FF45
    RET

L_7055:
    LXI H,L_71F4
    PUSH H
    LXI H,$FF8F
    DCR M
    RNZ
    MVI M,$03
    LXI H,$FF99
    LXI D,$FFA2
    CALL L_72B1
    CMA
    CMP M
    MOV M,A
    CZ L_7101
    XRA A
    OUT $B9
    IN $E8
    INR A
    MVI A,$FF
    OUT $B9
    JZ L_71FD
    MVI A,$7F
    MVI C,$07

L_7080:
    DCX H
    DCX D
    MOV B,A
    OUT $B9
    IN $E8
    CMA
    CMP M
    MOV M,A
    JNZ L_7092
    LDAX D
    CMP M
    CNZ L_70C5

L_7092:
    MVI A,$FF
    OUT $B9
    MOV A,B
    RRC
    DCR C
    JP L_7080
    DCX H
    MVI M,$02
    LXI H,$FFA5
    DCR M
    JZ L_711A
    INR M
    RM
    LDA D_FFA7
    LHLD D_FFA8
    ANA M
    RZ
    LDA D_FFAA
    CPI $02
    RNC
    LXI H,$FFA4
    DCR M
    RNZ
    MVI M,$06
    MVI A,$01
    STA D_FFF3
    JMP L_7122

L_70C5:
    PUSH B
    PUSH H
    PUSH D
    MOV B,A
    MVI A,$80
    MVI E,$07

L_70CD:
    MOV D,A
    ANA M
    JZ L_70D6
    ANA B
    JZ L_70E2

L_70D6:
    MOV A,D
    RRC
    DCR E
    JP L_70CD
    POP D

L_70DD:
    POP H
    MOV A,M
    STAX D
    POP B
    RET

L_70E2:
    LXI H,$FFA5
    INR A
    CMP M
    JNZ L_70EE
    POP D
    POP H
    POP B
    RET

L_70EE:
    MOV M,A
    MOV A,C
    RLC
    RLC
    RLC
    ORA E
    INX H
    MOV M,A
    INX H
    MOV M,D
    POP D
    XCHG
    SHLD D_FFA8
    XCHG
    JMP L_70DD

L_7101:
    LDAX D
    MOV B,A
    MOV A,M
    STAX D
    RLC
    RNC
    MOV A,B
    RLC
    RC
    XTHL
    LXI H,$71C4
    XTHL
    MVI B,$00
    MOV D,B
    MOV A,M
    RRC
    MVI A,$03
    RC
    MVI A,$13
    RET

L_711A:
    DCX H
    MVI M,$54
    DCX H
    LDA D_FFA2
    MOV M,A

L_7122:
    LDA D_FFA6
    MOV C,A
    LXI D,$002C
    MOV B,D
    CPI $33
    JC L_7133
    LXI H,$FFA7
    MOV M,B

L_7133:
    LDA D_FFA3
    RRC
    PUSH PSW
    MOV A,C
    CMP E
    JC L_7184
    CPI $30
    JNC L_7148
    POP PSW
    PUSH PSW
    RRC
    JC L_7184

L_7148:
    LXI H,D_7CEF
    POP PSW
    JNC L_7152
    LXI H,D_7CDB

L_7152:
    DAD B
    MOV A,M
    RLC
    ORA A
    RAR
    MOV C,A
    JNC L_71E4
    CPI $08
    JNC L_7180
    LDA D_F650
    ANI $E0
    JNZ L_7180
    LHLD CURLIN
    MOV A,H
    ANA L
    INR A
    JZ L_7180
    LXI H,$F630
    DAD B
    MOV A,M
    ORA A
    JZ L_7180
    MOV A,C
    ORI $80
    JMP L_71D5

L_7180:
    DCR B
    JMP L_71E4

L_7184:
    POP PSW
    JC L_7189
    MOV E,B

L_7189:
    RRC
    PUSH PSW
    JC L_720A

L_718E:
    LXI H,D_7C49
    RRC
    JC L_71B5
    LXI H,D_7CA1
    RRC
    JC L_71B5
    RRC
    JNC L_71AE
    LXI H,D_7BF1
    DAD B
    PUSH D
    MOV D,A
    CALL L_7233
    MOV A,D
    POP D
    JZ L_71B7

L_71AE:
    RRC
    CC L_722C
    LXI H,D_7BF1

L_71B5:
    DAD D

L_71B6:
    DAD B

L_71B7:
    POP PSW
    MOV A,M
    JNC L_71C2
    CPI $60
    RNC
    ANI $3F
    .byte $DA                           ; JC $C8B7: skips the next two bytes, unless it jumps

L_71C2:
    ORA A
    RZ
    MOV C,A
    ANI $EF
    CPI $03
    JNZ L_71E4
    LDA D_F650
    ANI $C0
    JNZ L_71E4
    MOV A,C

L_71D5:
    STA D_FFEB
    CPI $03
    RNZ
    LXI H,$FFAA
    MVI M,$01
    INX H
    JMP L_71F0

L_71E4:
    LXI H,$FFAA
    MOV A,M
    CPI $20
    RZ
    INR M
    RLC
    INX H
    MOV E,A
    DAD D

L_71F0:
    MOV M,C
    INX H
    MOV M,B
    POP PSW

L_71F4:
    MVI A,$09
    SIM

L_71F7:
    POP PSW

L_71F8:
    POP B
    POP D
    POP H
    EI
    RET

L_71FD:
    LXI H,$FF90
    DCR M
    RNZ
    LXI H,$FF91
    MVI B,$11
    JMP L_4F0A

L_720A:
    MOV A,C
    CPI $1A
    LXI H,D_7C1D
    JC L_71B6
    CPI $2C
    JC L_721D
    CPI $30
    JC L_7222

L_721D:
    POP PSW
    PUSH PSW
    JMP L_718E

L_7222:
    SUI $2C
    LXI H,D_7D2F
    MOV C,A
    DAD B
    JMP L_71B7

L_722C:
    MOV A,C
    CPI $1A
    RNC
    MVI E,$2C
    RET

L_7233:
    MOV A,M
    MVI E,$06
    LXI H,D_7CF9

L_7239:
    CMP M
    INX H
    RZ
    INX H
    DCR E
    JP L_7239
    RET
