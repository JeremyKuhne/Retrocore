;; MODEL 100 ROM: THE SCREEN'S CONTROLS, ESCAPE SEQUENCES AND FUNCTION-KEY LINE
;;
;; Runs at $4222-$4643. Model100.asm describes the ROM as a whole and how it is named.

CRLF:
    MVI A,$0D
    RST 4
    MVI A,$0A
    RST 4
    RET

ST_BEEP:
    MVI A,$07
    RST 4
    RET

HOME:
    MVI A,$0B
    RST 4
    RET

CLS:
    MVI A,$0C
    RST 4
    RET

SETSYS:
    MVI A,$54
    JMP ESCA

RSTSYS:
    MVI A,$55
    JMP ESCA

LOCK:
    MVI A,$56
    JMP ESCA

UNLOCK:
    MVI A,$57
    JMP ESCA

CURSON:
    MVI A,$50
    JMP ESCA

CUROFF:
    MVI A,$51
    JMP ESCA

DELLIN:
    MVI A,$4D
    JMP ESCA

INSLIN:
    MVI A,$4C
    JMP ESCA

ERAEOL:
    MVI A,$4B
    JMP ESCA

L_4262:
    MVI A,$58
    JMP ESCA

L_4267:
    ORA M
    RZ

ENTREV:
    MVI A,$70
    JMP ESCA

EXTREV:
    MVI A,$71

ESCA:
    PUSH PSW
    MVI A,$1B
    RST 4
    POP PSW
    RST 4
    RET

L_4277:
    LHLD D_F63B
    MVI H,$01

POSIT:
    MVI A,$59
    CALL ESCA
    MOV A,L
    ADI $1F
    RST 4
    MOV A,H
    ADI $1F
    RST 4
    RET

ERAFNK:
    LDA D_F63D
    ANA A
    RZ
    CALL RSTSYS
    LHLD CSRY
    PUSH H
    CALL L_4277
    CALL ERAEOL
    POP H
    CALL POSIT
    CALL L_4262
    XRA A
    RET

STDSPF:
    CALL STFNK

DSPFNK:
    LHLD CSRY
    LDA D_F63B
    CMP L
    JNZ L_42C0
    PUSH H
    CALL L_45ED
    MVI L,$01
    CALL POSIT
    CALL DELLIN
    POP H
    DCR L

L_42C0:
    PUSH H
    CALL RSTSYS
    CALL L_4277
    LXI H,$F789
    MVI E,$08
    LDA D_F648
    PUSH PSW
    CALL EXTREV

L_42D3:
    LDA D_F63C
    CPI $28
    LXI B,$040C
    JZ L_42E1
    LXI B,$0907

L_42E1:
    PUSH H
    LXI H,$FAC3
    MOV A,E
    SUI $06
    JZ L_42ED
    DCR A
    DCX H

L_42ED:
    CZ L_4267
    POP H
    CALL L_1BE0
    DAD B
    CALL EXTREV
    DCR E
    CNZ L_001E
    JNZ L_42D3
    CALL ERAEOL
    CALL SETSYS
    POP PSW
    ANA A
    CNZ ENTREV
    POP H
    CALL POSIT
    CALL L_4262
    XRA A
    RET

L_4313:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    RST 7
    .byte $08                           ; the hook's offset in the table at $FADA
    CALL L_431F
    JMP L_14ED

L_431F:
    MOV C,A
    XRA A
    STA D_FAC7
    LDA D_F638
    ANA A
    JNZ L_434A
    CALL L_4335
    LHLD CSRY
    SHLD D_F640
    RET

L_4335:
    CALL L_73C5
    CALL L_434C

L_433B:
    LHLD CSRY
    XCHG
    CALL L_7440
    LDA D_F63F
    ANA A
    RZ
    JMP L_73D9

L_434A:
    RST 7
    .byte $3C                           ; the hook's offset in the table at $FADA

L_434C:
    LXI H,$F646
    MOV A,M
    ANA A
    JNZ L_43FA
    MOV A,C
    LHLD CSRY
    CPI $09
    JZ L_4480
    CPI $7F
    JZ L_451F
    CPI $20
    JC L_4373
    CALL L_4560
    CALL L_4453
    RNZ
    MVI H,$01
    JMP L_4494

L_4373:
    LXI H,$4388
    MVI C,$08

L_4378:
    INX H
    INX H
    DCR C
    RM
    CMP M
    INX H
    JNZ L_4378
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    PUSH H
    LHLD CSRY
    RET

LCDCTL:
    DISPATCH $07, L_7662
    DISPATCH $08, L_4461
    DISPATCH $09, L_4480
    DISPATCH $0A, L_4494
    DISPATCH $0B, L_44A8
    DISPATCH $0C, L_4548
    DISPATCH $0D, L_44AA
    DISPATCH $1B, L_43B2

L_43A2:
    LDA D_FAC7
    ANA A
    RZ
    POP PSW
    RET

L_43A9:
    LDA D_F63D
    ADI $08
    RET

L_43AF:
    MVI A,$02
    .byte $01                           ; LXI B,$AF3E: skips the next two bytes

L_43B2:
    .byte $3E                           ; MVI A,$AF: skips the next byte

L_43B3:
    XRA A
    STA D_F646
    RET

ESCTAB:
    DISPATCH 'j', L_4548
    DISPATCH 'E', L_4548
    DISPATCH 'K', L_4537
    DISPATCH 'J', L_454E
    DISPATCH 'l', L_4535
    DISPATCH 'L', L_44EA
    DISPATCH 'M', L_44C4
    DISPATCH 'Y', L_43AF
    DISPATCH 'A', L_4469
    DISPATCH 'B', L_446E
    DISPATCH 'C', L_4453
    DISPATCH 'D', L_445C
    DISPATCH 'H', L_44A8
    DISPATCH 'p', L_4431
    DISPATCH 'q', L_4432
    DISPATCH 'P', L_44AF
    DISPATCH 'Q', L_44BA
    DISPATCH 'T', L_4439
    DISPATCH 'U', L_4437
    DISPATCH 'V', L_443F
    DISPATCH 'W', L_4440
    DISPATCH 'X', L_444A

L_43FA:
    MOV A,C
    CPI $1B
    MOV A,M
    JZ L_4445
    ANA A
    JP L_4411
    CALL L_43B3
    MOV A,C
    LXI H,$43B6
    MVI C,$16
    JMP L_4378

L_4411:
    DCR A
    STA D_F646
    LDA D_F63C
    LXI D,CSRX
    JZ L_4426
    LDA D_F63B
    LXI H,$F63D
    ADD M
    DCX D

L_4426:
    MOV B,A
    MOV A,C
    SUI $20
    CMP B
    INR A
    STAX D
    RC
    MOV A,B
    STAX D
    RET

L_4431:
    .byte $F6                           ; ORI $AF: skips the next byte

L_4432:
    XRA A
    STA D_F648
    RET

L_4437:
    XRA A
    .byte $C2                           ; JNZ $FF3E: skips the next two bytes, unless it jumps

L_4439:
    MVI A,$FF
    STA D_F63D
    RET

L_443F:
    .byte $F6                           ; ORI $AF: skips the next byte

L_4440:
    XRA A
    STA D_F63E
    RET

L_4445:
    INX H
    MOV M,A
    JMP L_43B2

L_444A:
    LXI H,$F647
    MOV A,M
    MVI M,$00
    DCX H
    MOV M,A
    RET

L_4453:
    LDA D_F63C
    CMP H
    RZ
    INR H
    JMP L_4477

L_445C:
    DCR H
    RZ
    JMP L_4477

L_4461:
    CALL L_445C
    RNZ
    LDA D_F63C
    MOV H,A

L_4469:
    DCR L
    RZ
    JMP L_4477

L_446E:
    CALL L_63CD
    CMP L
    RZ
    JC L_447B
    INR L

L_4477:
    SHLD CSRY
    RET

L_447B:
    DCR L
    XRA A
    JMP L_4477

L_4480:
    LDA CSRX
    PUSH PSW
    MVI A,$20
    RST 4
    POP B
    LDA CSRX
    CMP B
    RZ
    DCR A
    ANI $07
    JNZ L_4480
    RET

L_4494:
    CALL L_446E
    RNZ
    LDA D_F63E
    ANA A
    RNZ
    CALL L_4477
    CALL L_45ED
    MVI L,$01
    JMP L_44C7

L_44A8:
    MVI L,$01

L_44AA:
    MVI H,$01
    JMP L_4477

L_44AF:
    MVI A,$01
    STA D_F63F
    CALL L_43A2
    JMP L_73D9

L_44BA:
    XRA A
    STA D_F63F
    CALL L_43A2
    JMP L_73C5

L_44C4:
    CALL L_44AA

L_44C7:
    CALL L_43A2
    CALL L_43A9
    SUB L
    RC
    JZ L_4535

L_44D2:
    PUSH PSW
    MVI H,$28

L_44D5:
    INR L
    CALL L_4512
    DCR L
    CALL L_4566
    DCR H
    JNZ L_44D5
    INR L
    POP PSW
    DCR A
    JNZ L_44D2
    JMP L_4535

L_44EA:
    CALL L_44AA
    CALL L_43A2
    CALL L_43A9
    MOV H,A
    SUB L
    RC
    JZ L_4535
    MOV L,H

L_44FA:
    PUSH PSW
    MVI H,$28

L_44FD:
    DCR L
    CALL L_4512
    INR L
    CALL L_4566
    DCR H
    JNZ L_44FD
    DCR L
    POP PSW
    DCR A
    JNZ L_44FA
    JMP L_4535

L_4512:
    PUSH H
    PUSH H
    CALL L_4586
    MOV C,M
    POP H
    CALL L_45AA
    ANA M
    POP H
    RET

L_451F:
    LDA D_F648
    PUSH PSW
    CALL EXTREV
    MVI A,$08
    RST 4
    MVI A,$20
    RST 4
    MVI A,$08
    RST 4
    POP PSW
    ANA A
    RZ
    JMP ENTREV

L_4535:
    MVI H,$01

L_4537:
    CALL L_43A2

L_453A:
    MVI C,$20
    XRA A
    CALL L_4566
    INR H
    MOV A,H
    CPI $29
    JC L_453A
    RET

L_4548:
    CALL L_44A8
    CALL L_45D3

L_454E:
    CALL L_43A2

L_4551:
    CALL L_4537
    CALL L_43A9
    CMP L
    RC
    RZ
    MVI H,$01
    INR L
    JMP L_4551

L_4560:
    CALL L_43A2
    LDA D_F648

L_4566:
    PUSH H
    PUSH PSW
    PUSH H
    PUSH H
    CALL L_459A
    POP H
    CALL L_4586
    MOV M,C
    POP D
    CALL L_73EE
    POP PSW
    ANA A
    POP H
    RZ
    DI
    MVI A,$0D
    SIM
    EI
    CALL L_73A9
    MVI A,$09
    SIM
    RET

L_4586:
    MOV A,L
    ADD A
    ADD A
    ADD L
    ADD A
    ADD A
    ADD A
    MOV E,A
    SBB A
    CMA
    MOV D,A
    MOV L,H
    MVI H,$00
    DAD D
    LXI D,$FED7
    DAD D
    RET

L_459A:
    MOV B,A
    CALL L_45AA
    INR B
    DCR B
    JZ L_45A6
    ORA M
    MOV M,A
    RET

L_45A6:
    CMA
    ANA M
    MOV M,A
    RET

L_45AA:
    MOV A,L
    ADD A
    ADD A
    ADD L
    MOV L,A
    MOV A,H
    DCR A
    PUSH PSW
    RRC
    RRC
    RRC
    ANI $1F
    ADD L
    MOV L,A
    MVI H,$00
    LXI D,$FB35
    DAD D
    POP PSW
    ANI $07
    MOV D,A
    XRA A
    STC

L_45C5:
    RAR
    DCR D
    JP L_45C5
    RET

L_45CB:
    PUSH H
    CALL L_45AA
    XRA M
    MOV M,A
    POP H
    RET

L_45D3:
    CALL L_43A2
    LDA D_F650
    ADD A
    RP
    PUSH H
    LXI H,$FCC0
    LXI B,$0140

L_45E2:
    MVI M,$20
    INX H
    DCX B
    MOV A,B
    ORA C
    JNZ L_45E2
    POP H
    RET

L_45ED:
    CALL L_43A2
    LDA D_F650
    ADD A
    RP
    LXI D,$FCC0
    LXI H,$FCE8
    LXI B,$0140
    JMP L_6BDB

L_4601:
    CALL L_73C5
    MVI L,$01

L_4606:
    MVI H,$01

L_4608:
    CALL L_4512
    CALL L_4566
    INR H
    MOV A,H
    CPI $29
    JNZ L_4608
    INR L
    MOV A,L
    CPI $09
    JNZ L_4606
    JMP L_433B

L_461F:
    LXI H,$FCC0
    MVI E,$01

L_4624:
    MVI D,$01

L_4626:
    PUSH H
    PUSH D
    MOV C,M
    CALL L_73EE
    POP D
    POP H
    INX H
    INR D
    MOV A,D
    CPI $29
    JNZ L_4626
    INR E
    MOV A,E
    CPI $09
    JNZ L_4624
    RET

L_463E:
    MVI A,$3F
    RST 4
    MVI A,$20
    RST 4
