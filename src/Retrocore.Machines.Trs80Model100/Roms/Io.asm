;; MODEL 100 ROM: THE COLD AND WARM RESETS, THE PRINTER, THE RS-232 PORT AND THE MODEM
;;
;; Runs at $6CD6-$6F45. Model100.asm describes the ROM as a whole and how it is named.

INITIO:
    DI
    LXI H,$FF40
    MVI B,$BD
    CALL L_4F0A
    INR A

IOINIT:
    PUSH PSW
    DI
    MVI A,$19
    SIM
    IN $C8
    MVI A,$43
    OUT $B8
    MVI A,$05
    CALL L_7383
    MVI A,$ED
    OUT $BA
    XRA A
    STA D_FF45
    OUT $E8
    OUT $A8

.if MODEL = 100
    CALL L_7682
.else
    CALL L_6C2C
.endif

    CALL L_7533
    XRA A
    OUT $FE
    CALL L_7533
    MVI A,$3B
    OUT $FE
    CALL L_752B
    CALL L_7533
    MVI A,$39
    OUT $FE
    EI
    CALL L_76A0
    JNC L_6D1E

L_6D1D:
    XRA A

L_6D1E:
    STA D_FC81
    ORA A
    JZ L_6D3D
    LDA D_FFFC
    ORA A
    JNZ L_6D3D
    POP PSW
    RZ
    LHLD VARTAB
    LXI D,$E000
    RST 3
    RNC
    CALL L_76B6
    PUSH PSW
    JC L_6D1D

L_6D3D:
    POP PSW
    RET

PRINTR:
    PUSH B
    MOV C,A

L_6D41:
    CALL L_729F
    JC L_6D6A
    IN $BB
    ANI $06
    XRI $02
    JNZ L_6D41
    CALL L_765C
    MOV A,C
    OUT $B9
    LDA D_FF45
    MOV B,A
    ORI $02
    OUT $E8
    MOV A,B
    OUT $E8
    MVI B,$24

L_6D63:
    DCR B
    JNZ L_6D63
    MVI A,$09
    SIM

L_6D6A:
    MOV A,C
    POP B
    RET

RCVX:
    LDA D_FF42
    ORA A
    JZ L_6D79
    LDA D_FF41
    INR A
    RZ

L_6D79:
    LDA D_FF86
    ORA A
    RET

RV232C:
    PUSH H
    PUSH D
    PUSH B
    LXI H,L_71F8
    PUSH H
    LXI H,$FF86

L_6D88:
    CALL L_729F
    RC
    CALL RCVX
    JZ L_6D88
    CPI $03
    CC SENDCQ
    DI
    DCR M
    CALL L_6DFC
    MOV A,M
    XCHG
    INX H
    INX H
    INR M
    DCR M
    RZ
    DCR M
    JZ L_6DA9
    CMP A
    RET

L_6DA9:
    ORI $FF
    RET

L_6DAC:
    CALL D_F5FC
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    LXI H,L_71F7
    PUSH H
    IN $C8
    LXI H,$FF8D
    ANA M
    MOV C,A
    IN $D8
    ANI $0E
    MOV B,A
    JNZ L_6DDB
    MOV A,C
    CPI $11
    JZ L_6DD2
    CPI $13
    JNZ L_6DDB
    .byte $3E

L_6DD2:
    .byte $AF
    STA D_FF40
    LDA D_FF42
    ORA A
    RNZ

L_6DDB:
    LXI H,$FF86
    MOV A,M
    CPI $40
    RZ
    CPI $28
    CNC SENDCS
    PUSH B
    INR M
    INX H
    CALL L_6DFC
    POP B
    MOV M,C
    MOV A,B
    ORA A
    RZ
    XCHG
    INX H
    DCR M
    INR M
    RNZ
    LDA D_FF86
    MOV M,A
    RET

L_6DFC:
    INX H
    MOV C,M
    MOV A,C
    INR A
    ANI $3F
    MOV M,A
    XCHG
    LXI H,$FF46
    MVI B,$00
    DAD B
    RET

SENDCQ:
    LDA D_FF42
    ANA A
    RZ
    LDA D_FF8A
    DCR A
    RNZ
    STA D_FF8A
    PUSH B
    MVI C,$11
    JMP L_6E3A

SENDCS:
    LDA D_FF42
    ANA A
    RZ
    LDA D_FF8A
    ORA A
    RNZ
    INR A
    STA D_FF8A
    PUSH B
    MVI C,$13
    JMP L_6E3A

SD232C:
    PUSH B
    MOV C,A
    CALL L_6E4D
    JC L_6E4A

L_6E3A:
    CALL L_729F
    JC L_6E4A
    IN $D8
    ANI $10
    JZ L_6E3A
    MOV A,C
    OUT $C8

L_6E4A:
    MOV A,C
    POP B
    RET

L_6E4D:
    LDA D_FF42
    ORA A
    RZ
    MOV A,C
    CPI $11
    JNZ L_6E5F
    XRA A
    STA D_FF8A
    JMP L_6E65

L_6E5F:
    SUI $13
    JNZ L_6E69
    DCR A

L_6E65:
    STA D_FF41
    RET

L_6E69:
    CALL L_729F
    RC
    LDA D_FF40
    ORA A
    JNZ L_6E69
    RET

BAUDST:
    PUSH H
    MOV A,H
    RLC
    LXI H,$6E92
    MVI D,$00
    MOV E,A
    DAD D
    SHLD D_FF8B
    POP H

L_6E83:
    PUSH H
    LHLD D_FF8B
    MOV A,M
    OUT $BC
    INX H
    MOV A,M
    OUT $BD
    MVI A,$C3
    OUT $B8
    POP H
    RET

    .byte $00, $48, $6B, $45, $00, $42, $00, $41, $80, $40, $40, $40, $20, $40, $10, $40
    .byte $08, $40

INZCOM:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    MVI B,$25
    JC L_6EB3
    MVI H,$03
    MVI B,$2D

L_6EB3:
    DI
    CALL BAUDST
    MOV A,B
    OUT $BA
    IN $D8
    MOV A,L
    ANI $1F
    OUT $D8
    CALL L_6F39
    DCR A
    STA D_FF43
    JMP L_71F7

CLSCOM:
    IN $BA
    ORI $C0
    OUT $BA
    XRA A
    STA D_FF43
    RET

L_6ED6:
    MVI E,$00

L_6ED8:
    IN $D8
    ANI $01
    XRA D
    JNZ L_6EE5
    INR E
    JP L_6ED8
    RET

L_6EE5:
    PUSH PSW
    LDA D_FF44
    ORA A
    CZ L_7676
    POP PSW
    RET

CARDET:
    PUSH H
    PUSH D
    PUSH B
    LXI H,L_6F2C
    PUSH H
    IN $BB
    ANI $10
    LXI H,$0249
    LXI B,$1A0E
    JNZ L_6F09
    LXI H,$0427
    LXI B,$0C07

L_6F09:
    DI
    IN $D8
    ANI $01
    MOV D,A
    CALL L_6ED6
    JM L_6F1A
    XRA D
    MOV D,A
    CALL L_6ED6

L_6F1A:
    EI
    RM
    MOV A,E
    CMP B
    RNC
    CMP C
    RC
    DCX H
    MOV A,H
    ORA L
    JNZ L_6F09
    CALL L_6F39
    POP H
    .byte $C2

L_6F2C:
    ORI $FF
    JMP L_14EE

L_6F31:
    .byte $3E

L_6F32:
    XRA A
    DI
    STA D_FF42
    EI
    RET

L_6F39:
    XRA A
    MOV L,A
    MOV H,A
    SHLD D_FF40
    SHLD D_FF86
    SHLD D_FF88
    RET
