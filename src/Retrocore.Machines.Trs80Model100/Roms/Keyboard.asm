;; MODEL 100 ROM: THE KEYBOARD SCAN, BREAK, SOUND AND THE CLOCK
;;
;; Runs at $7242-$744B. Model100.asm describes the ROM as a whole and how it is named.

KYREAD:
    CALL L_765C
    LDA D_FFAA
    ORA A
    JZ L_726A
    LXI H,$FFAC
    MOV A,M
    ADI $02
    DCX H
    MOV A,M
    PUSH PSW
    DCX H
    DCR M
    MOV A,M
    RLC
    MOV C,A
    INX H
    LXI D,$FFAD

L_725E:
    DCR C
    JM L_7269
    LDAX D
    MOV M,A
    INX H
    INX D
    JMP L_725E

L_7269:
    POP PSW

L_726A:
    PUSH PSW
    MVI A,$09
    SIM
    POP PSW
    RET

KEYX:
    CALL BRKCHK
    JZ L_727E
    CPI $03
    JNZ L_727E
    ORA A
    STC
    RET

L_727E:
    LDA D_FFAA
    ORA A
    RET

BRKCHK:
    PUSH H
    LXI H,$FFEB
    MOV A,M
    MVI M,$00
    POP H
    ORA A
    RP
    PUSH H
    PUSH B
    LXI H,$F7CA
    MOV C,A
    MVI B,$00
    DAD B
    DAD B
    DAD B
    CALL L_3FD2
    POP B
    POP H
    XRA A
    RET

L_729F:
    PUSH B
    IN $B9
    MOV C,A
    CALL L_72B1
    PUSH PSW
    MOV A,C
    OUT $B9
    POP PSW
    POP B
    ANI $81
    RNZ
    STC
    RET

L_72B1:
    MVI A,$FF
    OUT $B9
    IN $BA
    ANI $FE
    MOV B,A
    OUT $BA
    IN $E8
    PUSH PSW
    MOV A,B
    INR A
    OUT $BA
    POP PSW
    RET

MUSIC:
    DI
    MOV A,E
    OUT $BC
    MOV A,D
    ORI $40
    OUT $BD
    MVI A,$C3
    OUT $B8
    IN $BA
    ANI $F8
    ORI $20
    OUT $BA

L_72DA:
    CALL L_729F
    JNC L_72E8
    MVI A,$03
    STA D_FFEB
    JMP L_72F9

L_72E8:
    MVI C,$64

L_72EA:
    PUSH B
    MVI C,$1E
    CALL L_7657
    POP B
    DCR C
    JNZ L_72EA
    DCR B
    JNZ L_72DA

L_72F9:
    IN $BA
    ORI $04
    OUT $BA
    CALL L_6E83
    EI
    RET

.if MODEL = 100
L_7304:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    MOV E,M
    INX H
    MOV D,M
    INX H
    MOV C,M
    INX H
    MOV B,M
    INX H
    MOV A,M
    OUT $70
    DI
    INX H

L_7315:
    MOV A,M
    OUT $71
    INX H
    MOV A,M
    OUT $72

L_731C:
    MOV A,B
    ORA C
    JZ L_71F7
    IN $73
    STAX D
    INX D
    DCX B
    JMP L_731C
.else
L_7304:
    CALL L_35D9
    PUSH H
    LHLD D_FC1A
    LXI D,$F5F0
    RST 3
    XCHG
    CC L_2791
    POP H
    RET

L_7315:
    CALL RV232C
    RC
    CPI $7F
    STC

L_731C:
    CMC
    RNZ
    MOV B,A
    LDA D_F65B
    CPI $3A
    MOV A,B
    CMC
    RET

    .byte $3C, $C9
.endif

L_7329:
    .byte $F6

L_732A:
    .byte $AF
    PUSH PSW
    CALL L_765C
    MVI A,$03
    CNZ L_7383
    MVI A,$01
    CALL L_7383
    MVI C,$07
    CALL L_7657
    MVI B,$0A

L_7340:
    MVI C,$04
    MOV D,M

L_7343:
    POP PSW
    PUSH PSW
    JZ L_7352
    IN $BB
    RAR
    MOV A,D
    RAR
    MOV D,A
    XRA A
    JMP L_735D

L_7352:
    MOV A,D
    RRC
    MOV D,A
    MVI A,$10
    RAR
    RAR
    RAR
    RAR
    OUT $B9

L_735D:
    ORI $09
    OUT $B9
    ANI $F7
    OUT $B9
    DCR C
    JNZ L_7343
    MOV A,D
    RRC
    RRC
    RRC
    RRC
    ANI $0F
    MOV M,A
    INX H
    DCR B
    JNZ L_7340
    POP PSW
    MVI A,$02
    CZ L_7383
    XRA A
    CALL L_7383
    JMP L_743C

L_7383:
    OUT $B9
    LDA D_FF45
    ORI $04
    OUT $E8
    ANI $FB
    OUT $E8
    RET

L_7391:
    CALL L_765C
    LXI H,L_7055
    PUSH H
    LXI H,$FFF3
    DCR M
    RNZ
    MVI M,$7D
    DCX H
    MOV A,M
    ORA A
    JP L_73A6
    RPO

L_73A6:
    XRI $01
    MOV M,A

L_73A9:
    PUSH H
    LXI H,$FFEC
    MVI D,$00
    CALL L_74A2
    MVI B,$06
    DCX H

L_73B5:
    MOV A,M
    CMA
    MOV M,A
    DCX H
    DCR B
    JNZ L_73B5
    INX H
    MVI D,$01
    CALL L_74A2
    POP H
    RET

L_73C5:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    CALL L_765C
    LXI H,$FFF2
    MOV A,M
    RRC
    CC L_73A9
    MVI M,$80
    JMP L_71F4

L_73D9:
    PUSH PSW
    PUSH H
    CALL L_765C
    LXI H,$FFF2
    MOV A,M
    ANI $7F
    MOV M,A
    INX H
    MVI M,$01
    MVI A,$09
    SIM
    POP H
    POP PSW
    RET

L_73EE:
    CALL L_765C
    LXI H,$0000
    DAD SP
    SHLD D_FFF8
    DCR D
    DCR E
    XCHG
    SHLD D_FFF4
    MOV A,C
    LXI D,D_7710
    SUI $20
    JZ L_7410
    INX D
    CPI $60
    JC L_7410
    LXI D,$76B1

L_7410:
    PUSH PSW
    MOV L,A
    MVI H,$00
    MOV B,H
    MOV C,L
    DAD H
    DAD H
    DAD B
    POP PSW
    PUSH PSW
    JC L_741F
    DAD B

L_741F:
    DAD D
    POP PSW
    JNC L_7430
    LXI D,$FFEC
    PUSH D
    MVI B,$05
    CALL L_2542
    XRA A
    STAX D
    POP H

L_7430:
    MVI D,$01
    CALL L_74A2

L_7435:
    XRA A
    STA D_FFF9
    CALL L_752B

L_743C:
    MVI A,$09
    SIM
    RET

L_7440:
    CALL L_765C
    DCR D
    DCR E
    XCHG
    SHLD D_FFF4
    JMP L_743C
