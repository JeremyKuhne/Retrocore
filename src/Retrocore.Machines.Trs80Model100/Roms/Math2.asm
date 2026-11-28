;; MODEL 100 ROM: THE BCD MATH PACKAGE: ABS, SGN, CONVERSIONS, NUMBER INPUT AND OUTPUT
;;
;; Runs at $33F2-$3EEF. Model100.asm describes the ROM as a whole and how it is named.

FN_ABS:
    CALL L_3411
    RP

L_33F6:
    RST 5
    JM L_37D0
    JZ TMERR

L_33FD:
    LXI H,$FC18
    MOV A,M
    ORA A
    RZ
    XRI $80
    MOV M,A
    RET

FN_SGN:
    CALL L_3411

L_340A:
    MOV L,A
    RAL
    SBB A
    MOV H,A
    JMP L_3510

L_3411:
    RST 5
    JZ TMERR
    JP L_33DC
    LHLD D_FC1A

L_341B:
    MOV A,H
    ORA L
    RZ
    MOV A,H
    JMP L_33E8

L_3422:
    XCHG
    LHLD D_FC1A
    XTHL
    PUSH H
    LHLD D_FC18
    XTHL
    PUSH H
    XCHG
    RET

L_342F:
    CALL L_3450

L_3432:
    XCHG
    SHLD D_FC1A
    MOV H,B
    MOV L,C
    SHLD D_FC18
    XCHG
    RET

L_343D:
    LHLD D_FC1A
    XCHG
    LHLD D_FC18
    MOV C,L
    MOV B,H
    RET

L_3447:
    MOV C,M
    INX H
    MOV B,M
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    RET

L_3450:
    MOV E,M
    INX H

L_3452:
    MOV D,M
    INX H
    MOV C,M
    INX H
    MOV B,M

L_3457:
    INX H
    RET

L_3459:
    LXI D,$FC18
    MVI B,$04
    JMP L_3469

L_3461:
    LXI D,$FC69

L_3464:
    XCHG

L_3465:
    LDA VALTYP
    MOV B,A

L_3469:
    LDAX D
    MOV M,A
    INX D
    INX H
    DCR B
    JNZ L_3469
    RET

L_3472:
    LDAX D
    MOV M,A
    DCX D
    DCX H
    DCR B
    JNZ L_3472
    RET

L_347B:
    LXI H,$FC69

L_347E:
    LXI D,L_3464
    JMP L_348A

L_3484:
    LXI H,$FC69

L_3487:
    LXI D,L_3465

L_348A:
    PUSH D
    LXI D,$FC18
    LDA VALTYP
    CPI $02
    RNZ
    LXI D,$FC1A
    RET

L_3498:
    MOV A,C
    ORA A
    JZ L_33DC
    LXI H,L_33E7
    PUSH H
    RST 6
    MOV A,C
    RZ
    LXI H,$FC18
    XRA M
    MOV A,C
    RM
    CALL L_34B0
    RAR
    XRA C
    RET

L_34B0:
    MOV A,C
    CMP M
    RNZ
    INX H
    MOV A,B
    CMP M
    RNZ
    INX H
    MOV A,E
    CMP M
    RNZ
    INX H
    MOV A,D
    SUB M
    RNZ
    POP H
    POP H
    RET

L_34C2:
    MOV A,D
    XRA H
    MOV A,H
    JM L_33E8
    CMP D
    JNZ L_34CF
    MOV A,L
    SUB E
    RZ

L_34CF:
    JMP L_33E9

L_34D2:
    LXI D,$FC69
    LDAX D
    ORA A
    JZ L_33DC
    LXI H,L_33E7
    PUSH H
    RST 6
    LDAX D
    MOV C,A
    RZ
    LXI H,$FC18
    XRA M
    MOV A,C
    RM
    MVI B,$08

L_34EA:
    LDAX D
    SUB M
    JNZ L_34F7
    INX D
    INX H
    DCR B
    JNZ L_34EA
    POP B
    RET

L_34F7:
    RAR
    XRA C
    RET

L_34FA:
    CALL L_34D2
    JNZ L_33E7
    RET

FN_CINT:
    RST 5
    LHLD D_FC1A
    RM
    JZ TMERR
    CALL L_35DE
    JC OVERR
    XCHG

L_3510:
    SHLD D_FC1A

L_3513:
    MVI A,$02

L_3515:
    STA VALTYP
    RET

L_3519:
    LXI B,$32C5
    LXI D,$8076
    CALL L_3498
    RNZ
    LXI H,$8000

L_3526:
    POP D
    JMP L_3510

FN_CSNG:
    RST 5
    RPO
    JM L_3540
    JZ TMERR
    CALL L_35D4
    CALL L_3D04
    INX H
    MOV A,B
    ORA A
    RAR
    MOV B,A
    JMP L_2C2C

L_3540:
    LHLD D_FC1A

L_3543:
    MOV A,H

L_3544:
    ORA A
    PUSH PSW
    CM L_37C6
    CALL L_35D4
    XCHG
    LXI H,$0000
    SHLD D_FC18
    SHLD D_FC1A
    MOV A,D
    ORA E
    JZ PPSWRT
    LXI B,$0500
    LXI H,$FC19
    PUSH H
    LXI H,D_35B0

L_3565:
    MVI A,$FF
    PUSH D
    MOV E,M
    INX H
    MOV D,M
    INX H
    XTHL
    PUSH B

L_356E:
    MOV B,H
    MOV C,L
    DAD D
    INR A
    JC L_356E
    MOV H,B
    MOV L,C
    POP B
    POP D
    XCHG
    INR C
    DCR C
    JNZ L_358B
    ORA A
    JZ L_35A1
    PUSH PSW
    MVI A,$40
    ADD B
    STA D_FC18
    POP PSW

L_358B:
    INR C
    XTHL
    PUSH PSW
    MOV A,C
    RAR
    JNC L_359C
    POP PSW
    ADD A
    ADD A
    ADD A
    ADD A
    MOV M,A
    JMP L_35A0

L_359C:
    POP PSW
    ORA M
    MOV M,A
    INX H

L_35A0:
    XTHL

L_35A1:
    MOV A,D
    ORA E
    JZ L_35AA
    DCR B
    JNZ L_3565

L_35AA:
    POP H
    POP PSW
    RP
    JMP L_33FD

D_35B0:
    .byte $F0, $D8, $18, $FC, $9C, $FF, $F6, $FF, $FF, $FF

FN_CDBL:
    RST 5
    RNC
    JZ TMERR
    CM L_3540

L_35C2:
    LXI H,$0000
    SHLD D_FC1C
    SHLD D_FC1E
    MOV A,H
    STA D_FC20

L_35CF:
    MVI A,$08
    JMP L_35D6

L_35D4:
    MVI A,$04

L_35D6:
    JMP L_3515

L_35D9:
    RST 5
    RZ
    JMP TMERR

L_35DE:
    LXI H,L_3641
    PUSH H
    LXI H,$FC18
    MOV A,M
    ANI $7F
    CPI $46
    RNC
    SUI $41
    JNC L_35F6
    ORA A
    POP D
    LXI D,$0000
    RET

L_35F6:
    INR A
    MOV B,A
    LXI D,$0000
    MOV C,D
    INX H

L_35FD:
    MOV A,C
    INR C
    RAR
    MOV A,M
    JC L_360B
    RAR
    RAR
    RAR
    RAR
    JMP L_360C

L_360B:
    INX H

L_360C:
    ANI $0F
    SHLD D_FC12
    MOV H,D
    MOV L,E
    DAD H
    RC
    DAD H
    RC
    DAD D
    RC
    DAD H
    RC
    MOV E,A
    MVI D,$00
    DAD D
    RC
    XCHG
    LHLD D_FC12
    DCR B
    JNZ L_35FD
    LXI H,$8000
    RST 3
    LDA D_FC18
    RC
    JZ L_363D
    POP H
    ORA A
    RP
    XCHG
    CALL L_37C6
    XCHG
    ORA A
    RET

L_363D:
    ORA A
    RP
    POP H
    RET

L_3641:
    STC
    RET

L_3643:
    DCX B
    RET

FN_FIX:
    RST 5
    RM
    RST 6
    JP FN_INT
    CALL L_33FD
    CALL FN_INT
    JMP L_33F6

FN_INT:
    RST 5
    RM
    LXI H,$FC20
    MVI C,$0E
    JNC L_3666
    JZ TMERR
    LXI H,$FC1C
    MVI C,$06

L_3666:
    LDA D_FC18
    ORA A
    JM L_3688
    ANI $7F
    SUI $41
    JC L_33ED
    INR A
    SUB C
    RNC
    CMA
    INR A
    MOV B,A

L_367A:
    DCX H
    MOV A,M
    ANI $F0
    MOV M,A
    DCR B
    RZ
    XRA A
    MOV M,A
    DCR B
    JNZ L_367A
    RET

L_3688:
    ANI $7F
    SUI $41
    JNC L_3695
    LXI H,$FFFF
    JMP L_3510

L_3695:
    INR A
    SUB C
    RNC
    CMA
    INR A
    MOV B,A
    MVI E,$00

L_369D:
    DCX H
    MOV A,M
    MOV D,A
    ANI $F0
    MOV M,A
    CMP D
    JZ L_36A8
    INR E

L_36A8:
    DCR B
    JZ L_36B7
    XRA A
    MOV M,A
    CMP D
    JZ L_36B3
    INR E

L_36B3:
    DCR B
    JNZ L_369D

L_36B7:
    INR E
    DCR E
    RZ
    MOV A,C
    CPI $06
    LXI B,$10C1
    LXI D,$0000
    JZ L_37F4
    XCHG
    SHLD D_FC6F
    SHLD D_FC6D
    SHLD D_FC6B
    MOV H,B
    MOV L,C
    SHLD D_FC69
    JMP L_2B78

L_36D8:
    PUSH H
    LXI H,$0000
    MOV A,B
    ORA C
    JZ L_36F5
    MVI A,$10

L_36E3:
    DAD H
    JC L_48F6
    XCHG
    DAD H
    XCHG
    JNC L_36F1
    DAD B
    JC L_48F6

L_36F1:
    DCR A
    JNZ L_36E3

L_36F5:
    XCHG
    POP H
    RET

L_36F8:
    MOV A,H
    RAL
    SBB A
    MOV B,A
    CALL L_37C6
    MOV A,C
    SBB B
    JMP L_3707

L_3704:
    MOV A,H
    RAL
    SBB A

L_3707:
    MOV B,A
    PUSH H
    MOV A,D
    RAL
    SBB A
    DAD D
    ADC B
    RRC
    XRA H
    JP L_3526
    PUSH B
    XCHG
    CALL L_3543
    POP PSW
    POP H
    CALL L_3422
    CALL L_3543
    POP B
    POP D
    JMP L_37F4

L_3725:
    MOV A,H
    ORA L
    JZ L_3510
    PUSH H
    PUSH D
    CALL L_37BA
    PUSH B
    MOV B,H
    MOV C,L
    LXI H,$0000
    MVI A,$10

L_3737:
    DAD H
    JC L_375F
    XCHG
    DAD H
    XCHG
    JNC L_3745
    DAD B
    JC L_375F

L_3745:
    DCR A
    JNZ L_3737
    POP B
    POP D

L_374B:
    MOV A,H
    ORA A
    JM L_3755
    POP D
    MOV A,B
    JMP L_37C2

L_3755:
    XRI $80
    ORA L
    JZ L_3770
    XCHG
    JMP L_3761

L_375F:
    POP B
    POP H

L_3761:
    CALL L_3543
    POP H
    CALL L_3422
    CALL L_3543
    POP B
    POP D
    JMP L_3803

L_3770:
    MOV A,B
    ORA A
    POP B
    JM L_3510
    PUSH D
    CALL L_3543
    POP D
    JMP L_33FD

L_377E:
    MOV A,H
    ORA L
    JZ DV0ERR
    CALL L_37BA
    PUSH B
    XCHG
    CALL L_37C6
    MOV B,H
    MOV C,L
    LXI H,$0000
    MVI A,$11
    PUSH PSW
    ORA A
    JMP L_37A3

L_3797:
    PUSH PSW
    PUSH H
    DAD B
    JNC L_37A2
    POP PSW
    STC
    JMP L_37A3

L_37A2:
    POP H

L_37A3:
    MOV A,E
    RAL
    MOV E,A
    MOV A,D
    RAL
    MOV D,A
    MOV A,L
    RAL
    MOV L,A
    MOV A,H
    RAL
    MOV H,A
    POP PSW
    DCR A
    JNZ L_3797
    XCHG
    POP B
    PUSH D
    JMP L_374B

L_37BA:
    MOV A,H
    XRA D
    MOV B,A
    CALL L_37C1
    XCHG

L_37C1:
    MOV A,H

L_37C2:
    ORA A
    JP L_3510

L_37C6:
    XRA A
    MOV C,A
    SUB L
    MOV L,A
    MOV A,C
    SBB H
    MOV H,A
    JMP L_3510

L_37D0:
    LHLD D_FC1A
    CALL L_37C6
    MOV A,H
    XRI $80
    ORA L
    RNZ

L_37DB:
    XRA A
    JMP L_3544

L_37DF:
    PUSH D
    CALL L_377E
    XRA A
    ADD D
    RAR
    MOV H,A
    MOV A,E
    RAR
    MOV L,A
    CALL L_3513
    POP PSW
    JMP L_37C2

L_37F1:
    CALL L_3450

L_37F4:
    CALL L_3827
    CALL L_35C2
    JMP L_2B78

L_37FD:
    CALL L_33FD
    JMP L_37F4

L_3803:
    CALL L_3827
    CALL L_35C2
    JMP L_2CFF

L_380C:
    POP B
    POP D

L_380E:
    LHLD D_FC1A
    XCHG
    SHLD D_FC1A
    PUSH B
    LHLD D_FC18
    XTHL
    SHLD D_FC18
    POP B
    CALL L_3827
    CALL L_35C2
    JMP L_2DC7

L_3827:
    XCHG
    SHLD D_FC6B
    MOV H,B
    MOV L,C
    SHLD D_FC69
    LXI H,$0000
    SHLD D_FC6D
    SHLD D_FC6F
    RET

L_383A:
    DCR A
    RET

L_383C:
    DCX H
    RET

L_383E:
    POP H
    RET

L_3840:
    XCHG
    LXI B,$00FF
    MOV H,B
    MOV L,B
    CALL L_3510
    XCHG
    MOV A,M
    CPI $2D
    PUSH PSW
    JZ L_3857
    CPI $2B
    JZ L_3857
    DCX H

L_3857:
    RST 2
    JC L_3940
    CPI $2E
    JZ L_3904
    CPI $65
    JZ L_3867
    CPI $45

L_3867:
    JNZ L_388A
    PUSH H
    RST 2
    CPI $6C
    JZ L_387D
    CPI $4C
    JZ L_387D
    CPI $71
    JZ L_387D
    CPI $51

L_387D:
    POP H
    JZ L_3889
    RST 5
    JNC L_38A3
    XRA A
    JMP L_38A4

L_3889:
    MOV A,M

L_388A:
    CPI $25
    JZ L_391A
    CPI $23
    JZ L_3929
    CPI $21
    JZ L_392A
    CPI $64
    JZ L_38A3
    CPI $44
    JNZ L_38D1

L_38A3:
    ORA A

L_38A4:
    CALL L_3931
    RST 2
    PUSH D
    MVI D,$00
    CALL MINPLS
    MOV C,D
    POP D

L_38B0:
    RST 2
    JNC L_38CA
    MOV A,E
    CPI $0C
    JNC L_38C5
    RLC
    RLC
    ADD E
    RLC
    ADD M
    SUI $30
    MOV E,A
    JMP L_38B0

L_38C5:
    MVI E,$80
    JMP L_38B0

L_38CA:
    INR C
    JNZ L_38D1
    XRA A
    SUB E
    MOV E,A

L_38D1:
    RST 5
    JM L_38E8
    LDA D_FC18
    ORA A
    JZ L_38E8
    MOV A,D
    SUB B
    ADD E
    ADI $40
    STA D_FC18
    ORA A
    CM L_3901

L_38E8:
    POP PSW
    PUSH H
    CZ L_33F6
    RST 5
    JNC L_38FC
    POP H
    RPE
    PUSH H
    LXI H,L_383E
    PUSH H
    CALL L_3519
    RET

L_38FC:
    CALL L_2C27
    POP H
    RET

L_3901:
    JMP OVERR

L_3904:
    RST 5
    INR C
    JNZ L_38D1
    JNC L_3917
    CALL L_3931
    LDA D_FC18
    ORA A
    JNZ L_3917
    MOV D,A

L_3917:
    JMP L_3857

L_391A:
    RST 2
    POP PSW
    PUSH H
    LXI H,L_383E
    PUSH H
    LXI H,FN_CINT
    PUSH H
    PUSH PSW
    JMP L_38D1

L_3929:
    ORA A

L_392A:
    CALL L_3931
    RST 2
    JMP L_38D1

L_3931:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    CZ FN_CSNG
    POP PSW
    CNZ FN_CDBL
    POP B
    POP D
    POP H
    RET

L_3940:
    SUI $30
    JNZ L_394D
    ORA C
    JZ L_394D
    ANA D
    JZ L_3857

L_394D:
    INR D
    MOV A,D
    CPI $07
    JNZ L_3958
    ORA A
    CALL L_3931

L_3958:
    PUSH D
    MOV A,B
    ADD C
    INR A
    MOV B,A
    PUSH B
    PUSH H
    MOV A,M
    SUI $30
    PUSH PSW
    RST 5
    JP L_398D
    LHLD D_FC1A
    LXI D,$0CCD
    RST 3
    JNC L_398A
    MOV D,H
    MOV E,L
    DAD H
    DAD H
    DAD D
    DAD H
    POP PSW
    MOV C,A
    DAD B
    MOV A,H
    ORA A
    JM L_3988
    SHLD D_FC1A

L_3982:
    POP H
    POP B
    POP D
    JMP L_3857

L_3988:
    MOV A,C
    PUSH PSW

L_398A:
    CALL L_3540

L_398D:
    POP PSW
    POP H
    POP B
    POP D
    JNZ L_39A1
    LDA D_FC18
    ORA A
    MVI A,$00
    JNZ L_39A1
    MOV D,A
    JMP L_3857

L_39A1:
    PUSH D
    PUSH B
    PUSH H
    PUSH PSW
    LXI H,$FC18
    MVI M,$01
    MOV A,D
    CPI $10
    JC L_39B4
    POP PSW
    JMP L_3982

L_39B4:
    INR A
    ORA A
    RAR
    MVI B,$00
    MOV C,A
    DAD B
    POP PSW
    MOV C,A
    MOV A,D
    RAR
    MOV A,C
    JNC L_39C7
    ADD A
    ADD A
    ADD A
    ADD A

L_39C7:
    ORA M
    MOV M,A
    JMP L_3982

L_39CC:
    PUSH H
    LXI H,$03F1
    CALL STROUT
    POP H

L_39D4:
    LXI B,STROUI
    PUSH B
    CALL L_3510
    XRA A
    STA TEMP3
    LXI H,$FBE8
    MVI M,$20
    ORA M
    JMP L_3A05

L_39E8:
    XRA A

L_39E9:
    CALL L_3D11
    ANI $08
    JZ L_39F3
    MVI M,$2B

L_39F3:
    XCHG
    CALL L_3411
    XCHG
    JP L_3A05
    MVI M,$2D
    PUSH B
    PUSH H
    CALL L_33F6
    POP H
    POP B
    ORA H

L_3A05:
    INX H
    MVI M,$30
    LDA TEMP3
    MOV D,A
    RAL
    LDA VALTYP
    JC L_3ACA
    JZ L_3AC2
    CPI $04
    JNC L_3A6F
    LXI B,$0000
    CALL L_3CC3

L_3A21:
    LXI H,$FBE8
    MOV B,M
    MVI C,$20
    LDA TEMP3
    MOV E,A
    ANI $20
    JZ L_3A3E
    MOV A,B
    CMP C
    MVI C,$2A
    JNZ L_3A3E
    MOV A,E
    ANI $04
    JNZ L_3A3E
    MOV B,C

L_3A3E:
    MOV M,C
    RST 2
    JZ L_3A5C
    CPI $45
    JZ L_3A5C
    CPI $44
    JZ L_3A5C
    CPI $30
    JZ L_3A3E
    CPI $2C
    JZ L_3A3E
    CPI $2E
    JNZ L_3A5F

L_3A5C:
    DCX H
    MVI M,$30

L_3A5F:
    MOV A,E
    ANI $10
    JZ L_3A68
    DCX H
    MVI M,$24

L_3A68:
    MOV A,E
    ANI $04
    RNZ
    DCX H
    MOV M,B
    RET

L_3A6F:
    PUSH H
    CALL L_3D04
    MOV D,B
    INR D
    LXI B,$0300
    LDA D_FC18
    SUI $3F
    JC L_3A89
    INR D
    CMP D
    JNC L_3A89
    INR A
    MOV B,A
    MVI A,$02

L_3A89:
    SUI $02
    POP H
    PUSH PSW
    CALL L_3C70
    MVI M,$30
    CZ L_3457
    CALL L_3C97

L_3A98:
    DCX H
    MOV A,M
    CPI $30
    JZ L_3A98
    CPI $2E
    CNZ L_3457
    POP PSW
    JZ L_3AC3

L_3AA8:
    MVI M,$45
    INX H
    MVI M,$2B
    JP L_3AB4
    MVI M,$2D
    CMA
    INR A

L_3AB4:
    MVI B,$2F

L_3AB6:
    INR B
    SUI $0A
    JNC L_3AB6
    ADI $3A
    INX H
    MOV M,B
    INX H
    MOV M,A

L_3AC2:
    INX H

L_3AC3:
    MVI M,$00
    XCHG
    LXI H,$FBE8
    RET

L_3ACA:
    INX H
    PUSH B
    CPI $04
    MOV A,D
    JNC L_3B42
    RAR
    JC L_3BCC
    LXI B,$0603
    CALL L_3C68
    POP D
    MOV A,D
    SUI $05
    CP L_3C44
    CALL L_3CC3

L_3AE6:
    MOV A,E
    ORA A
    CZ L_383C
    DCR A
    CP L_3C44

L_3AEF:
    PUSH H
    CALL L_3A21
    POP H
    JZ L_3AF9
    MOV M,B
    INX H

L_3AF9:
    MVI M,$00
    LXI H,$FBE7

L_3AFE:
    INX H

L_3AFF:
    LDA TEMP2
    SUB L
    SUB D
    RZ
    MOV A,M
    CPI $20
    JZ L_3AFE
    CPI $2A
    JZ L_3AFE
    DCX H
    PUSH H

L_3B12:
    PUSH PSW
    LXI B,L_3B12
    PUSH B
    RST 2
    CPI $2D
    RZ
    CPI $2B
    RZ
    CPI $24
    RZ
    POP B
    CPI $30
    JNZ L_3B3A
    INX H
    RST 2
    JNC L_3B3A
    DCX H
    JMP L_3B32

L_3B30:
    DCX H
    MOV M,A

L_3B32:
    POP PSW
    JZ L_3B30
    POP B
    JMP L_3AFF

L_3B3A:
    POP PSW
    JZ L_3B3A
    POP H
    MVI M,$25
    RET

L_3B42:
    PUSH H
    RAR
    JC L_3BD2
    CALL L_3D04
    MOV D,B
    LDA D_FC18
    SUI $4F
    JC L_3B5E
    POP H
    POP B
    CALL L_39E8
    LXI H,$FBE7
    MVI M,$25
    RET

L_3B5E:
    RST 6
    CNZ L_3D55
    POP H
    POP B
    JM L_3B81
    PUSH B
    MOV E,A
    MOV A,B
    SUB D
    SUB E
    CP L_3C44
    CALL L_3C5B
    CALL L_3C97
    ORA E
    CNZ L_3C54
    ORA E
    CNZ L_3C83
    POP D
    JMP L_3AE6

L_3B81:
    MOV E,A
    MOV A,C
    ORA A
    CNZ L_383A
    ADD E
    JM L_3B8C
    XRA A

L_3B8C:
    PUSH B
    PUSH PSW
    CM L_3D2D
    POP B
    MOV A,E
    SUB B
    POP B
    MOV E,A
    ADD D
    MOV A,B
    JM L_3BA7
    SUB D
    SUB E
    CP L_3C44
    PUSH B
    CALL L_3C5B
    JMP L_3BB8

L_3BA7:
    CALL L_3C44
    MOV A,C
    CALL L_3C87
    MOV C,A
    XRA A
    SUB D
    SUB E
    CALL L_3C44
    PUSH B
    MOV B,A
    MOV C,A

L_3BB8:
    CALL L_3C97
    POP B
    ORA C
    JNZ L_3BC3
    LHLD TEMP2

L_3BC3:
    ADD E
    DCR A
    CP L_3C44
    MOV D,B
    JMP L_3AEF

L_3BCC:
    PUSH H
    PUSH D
    CALL L_3540
    POP D

L_3BD2:
    CALL L_3D04
    MOV E,B
    RST 6
    PUSH PSW
    CNZ L_3D55
    POP PSW
    POP H
    POP B
    PUSH PSW
    MOV A,C
    ORA A
    PUSH PSW
    CNZ L_383A
    ADD B
    MOV C,A
    MOV A,D
    ANI $04
    CPI $01
    SBB A
    MOV D,A
    ADD C
    MOV C,A
    SUB E
    PUSH PSW
    JP L_3C04
    CALL L_3D2D
    JNZ L_3C04
    PUSH H
    CALL L_2CF2
    LXI H,$FC18
    INR M
    POP H

L_3C04:
    POP PSW
    PUSH B
    PUSH PSW
    JM L_3C0B
    XRA A

L_3C0B:
    CMA
    INR A
    ADD B
    INR A
    ADD D
    MOV B,A
    MVI C,$00
    CZ L_3C70
    CALL L_3C97
    POP PSW
    CP L_3C4D
    CALL L_3C83
    POP B
    POP PSW
    JNZ L_3C31
    CALL L_383C
    MOV A,M
    CPI $2E
    CNZ L_3457
    SHLD TEMP2

L_3C31:
    POP PSW
    LDA D_FC18
    JZ L_3C3B
    ADD E
    SUB B
    SUB D

L_3C3B:
    PUSH B
    CALL L_3AA8
    XCHG
    POP D
    JMP L_3AEF

L_3C44:
    ORA A

L_3C45:
    RZ
    DCR A
    MVI M,$30
    INX H
    JMP L_3C45

L_3C4D:
    JNZ L_3C54

L_3C50:
    RZ
    CALL L_3C83

L_3C54:
    MVI M,$30
    INX H
    DCR A
    JMP L_3C50

L_3C5B:
    MOV A,E
    ADD D
    INR A
    MOV B,A
    INR A

L_3C60:
    SUI $03
    JNC L_3C60
    ADI $05
    MOV C,A

L_3C68:
    LDA TEMP3
    ANI $40
    RNZ
    MOV C,A
    RET

L_3C70:
    DCR B
    JP L_3C84
    SHLD TEMP2
    MVI M,$2E

L_3C79:
    INX H
    MVI M,$30
    INR B
    MOV C,B
    JNZ L_3C79
    INX H
    RET

L_3C83:
    DCR B

L_3C84:
    JNZ L_3C8F

L_3C87:
    MVI M,$2E
    SHLD TEMP2
    INX H
    MOV C,B
    RET

L_3C8F:
    DCR C
    RNZ
    MVI M,$2C
    INX H
    MVI C,$03
    RET

L_3C97:
    PUSH D
    PUSH H
    PUSH B
    CALL L_3D04
    MOV A,B
    POP B
    POP H
    LXI D,$FC19
    STC

L_3CA4:
    PUSH PSW
    CALL L_3C83
    LDAX D
    JNC L_3CB3
    RAR
    RAR
    RAR
    RAR
    JMP L_3CB4

L_3CB3:
    INX D

L_3CB4:
    ANI $0F
    ADI $30
    MOV M,A
    INX H
    POP PSW
    DCR A
    CMC
    JNZ L_3CA4
    JMP L_3CF4

L_3CC3:
    PUSH D
    LXI D,D_3CFA
    MVI A,$05

L_3CC9:
    CALL L_3C83
    PUSH B
    PUSH PSW
    PUSH H
    XCHG
    MOV C,M
    INX H
    MOV B,M
    PUSH B
    INX H
    XTHL
    XCHG
    LHLD D_FC1A
    MVI B,$2F

L_3CDC:
    INR B
    MOV A,L
    SUB E
    MOV L,A
    MOV A,H
    SBB D
    MOV H,A
    JNC L_3CDC
    DAD D
    SHLD D_FC1A
    POP D
    POP H
    MOV M,B
    INX H
    POP PSW
    POP B
    DCR A
    JNZ L_3CC9

L_3CF4:
    CALL L_3C83
    MOV M,A
    POP D
    RET

D_3CFA:
    .byte $10, $27, $E8, $03, $64, $00, $0A, $00, $01, $00

L_3D04:
    RST 5
    LXI H,$FC1F
    MVI B,$0E
    RNC
    LXI H,$FC1B
    MVI B,$06
    RET

L_3D11:
    STA TEMP3
    PUSH PSW
    PUSH B
    PUSH D
    CALL FN_CDBL
    LXI H,D_327E
    LDA D_FC18
    ANA A
    CZ L_31C4
    POP D
    POP B
    POP PSW
    LXI H,$FBE8
    MVI M,$20
    RET

L_3D2D:
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    CMA
    INR A
    MOV E,A
    MVI A,$01
    JZ L_3D4F
    CALL L_3D04
    PUSH H

L_3D3D:
    CALL L_2CF2
    DCR E
    JNZ L_3D3D
    POP H
    INX H
    MOV A,B
    RRC
    MOV B,A
    CALL L_2C2C
    CALL L_3D67

L_3D4F:
    POP B
    ADD B
    POP B
    POP D
    POP H
    RET

L_3D55:
    PUSH B
    PUSH H
    CALL L_3D04
    LDA D_FC18
    SUI $40
    SUB B
    STA D_FC18
    POP H
    POP B
    ORA A
    RET

L_3D67:
    PUSH B
    CALL L_3D04

L_3D6B:
    MOV A,M
    ANI $0F
    JNZ L_3D7C
    DCR B
    MOV A,M
    ORA A
    JNZ L_3D7C
    DCX H
    DCR B
    JNZ L_3D6B

L_3D7C:
    MOV A,B
    POP B
    RET

L_3D7F:
    CALL L_3827
    CALL L_35C2
    CALL L_322E
    CALL L_31D2
    CALL L_3245

L_3D8E:
    LDA D_FC69
    ORA A
    JZ L_3DFC
    MOV H,A
    LDA D_FC18
    ORA A
    JZ L_3E07
    CALL L_3234
    CALL L_3EDC
    JC L_3DE2
    XCHG
    SHLD TEMP8
    CALL L_35CF
    CALL L_3245
    CALL L_3EDC
    CALL L_35CF
    LHLD TEMP8
    JNC L_3E15
    LDA D_FC69
    PUSH PSW
    PUSH H
    CALL L_31C1
    LXI H,$FBE7
    CALL L_31CA
    LXI H,D_3286
    CALL L_31C4
    POP H
    MOV A,H
    ORA A
    PUSH PSW
    JP L_3DDE
    XRA A
    MOV C,A
    SUB L
    MOV L,A
    MOV A,C
    SBB H
    MOV H,A

L_3DDE:
    PUSH H
    JMP L_3E53

L_3DE2:
    CALL L_35CF
    CALL L_31C1
    CALL L_31D2
    CALL FN_LOG
    CALL L_3245
    CALL L_2CFF
    JMP FN_EXP

L_3DF7:
    MOV A,H
    ORA L
    JNZ L_3E02

L_3DFC:
    LXI H,$0001
    JMP L_3E12

L_3E02:
    MOV A,D
    ORA E
    JNZ L_3E15

L_3E07:
    MOV A,H
    RAL
    JNC L_3E0F
    JMP DV0ERR

L_3E0F:
    LXI H,$0000

L_3E12:
    JMP L_3510

L_3E15:
    SHLD TEMP8
    PUSH D
    MOV A,H
    ORA A
    PUSH PSW
    CM L_37C6
    MOV B,H
    MOV C,L
    LXI H,$0001

L_3E24:
    ORA A
    MOV A,B
    RAR
    MOV B,A
    MOV A,C
    RAR
    MOV C,A
    JNC L_3E34
    CALL L_3ECF
    JNZ L_3E85

L_3E34:
    MOV A,B
    ORA C
    JZ L_3E9E
    PUSH H
    MOV H,D
    MOV L,E
    CALL L_3ECF
    XCHG
    POP H
    JZ L_3E24
    PUSH B
    PUSH H
    LXI H,$FBE7
    CALL L_31CA
    POP H
    CALL L_3543
    CALL L_35C2

L_3E53:
    POP B
    MOV A,B
    ORA A
    RAR
    MOV B,A
    MOV A,C
    RAR
    MOV C,A
    JNC L_3E66
    PUSH B
    LXI H,$FBE7
    CALL L_31A3
    POP B

L_3E66:
    MOV A,B
    ORA C
    JZ L_3E9E
    PUSH B
    CALL L_3234
    LXI H,$FBE7
    PUSH H
    CALL L_31C4
    POP H
    PUSH H
    CALL L_31A3
    POP H
    CALL L_31CA
    CALL L_324B
    JMP L_3E53

L_3E85:
    PUSH B
    PUSH D
    CALL L_7FF4
    POP H
    CALL L_3543
    CALL L_35C2
    LXI H,$FBE7
    CALL L_31CA
    CALL L_31C1
    POP B
    JMP L_3E66

L_3E9E:
    POP PSW
    POP B
    RP
    LDA VALTYP
    CPI $02
    JNZ L_3EB1
    PUSH B
    CALL L_3543
    CALL L_35C2
    POP B

L_3EB1:
    LDA D_FC18
    ORA A
    JNZ L_3EC3
    LHLD TEMP8
    ORA H
    RP
    MOV A,L
    RRC
    ANA B
    JMP OVERR

L_3EC3:
    CALL L_31B5
    LXI H,D_3286
    CALL L_31C4
    JMP L_2DC7

L_3ECF:
    PUSH B
    PUSH D
    CALL L_3725
    LDA VALTYP
    CPI $02
    POP D
    POP B
    RET

L_3EDC:
    CALL L_31C1
    CALL L_322E
    CALL FN_INT
    CALL L_3245
    CALL L_34D2
    STC
    RNZ
    JMP L_35DE
