;; MODEL 100 ROM: THE KEYBOARD'S SCAN AND ITS BUFFER, BREAK, SOUND, THE CLOCK AND CHARACTER DRAWING
;;
;; Runs at $7055-$744B. Model100.asm describes the ROM as a whole and how it is named.

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
    CC PUTTMP
    POP H
    RET

L_7315:
    CALL RV232C
    RC
    CPI $7F
    STC
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
    .byte $F6                           ; ORI $AF: skips the next byte

L_732A:
    XRA A
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
