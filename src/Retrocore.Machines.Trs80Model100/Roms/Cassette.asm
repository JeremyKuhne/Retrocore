;; MODEL 100 ROM: THE CASSETTE'S LEADERS, SYNC, BYTES AND MOTOR
;;
;; Runs at $6F46-$7054. Model100.asm describes the ROM as a whole and how it is named.

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
