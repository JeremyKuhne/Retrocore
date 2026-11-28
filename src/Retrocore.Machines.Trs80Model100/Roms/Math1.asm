;; MODEL 100 ROM: FRE AND THE BCD MATH PACKAGE: ARITHMETIC AND THE TRANSCENDENTAL FUNCTIONS
;;
;; Runs at $2B4C-$33F1. Model100.asm describes the ROM as a whole and how it is named.

FN_FRE:
    LHLD STREND
    XCHG
    LXI H,$0000
    DAD SP
    RST 5
    JNZ GIVDBL
    CALL FREFAC
    CALL GARBA2

CLCDIF:
    XCHG
    LHLD STKTOP
    XCHG
    LHLD FRETOP
    JMP GIVDBL

L_2B69:
    LXI H,$FC69
    MOV A,M
    ORA A
    RZ
    XRI $80
    MOV M,A
    JMP L_2B7E

L_2B75:
    CALL L_3461

L_2B78:
    LXI H,$FC69
    MOV A,M
    ORA A
    RZ

L_2B7E:
    ANI $7F
    MOV B,A
    LXI D,$FC18
    LDAX D
    ORA A
    JZ L_347B
    ANI $7F
    SUB B
    JNC L_2BA2
    CMA
    INR A
    PUSH PSW
    PUSH H
    MVI B,$08

L_2B95:
    LDAX D
    MOV C,M
    MOV M,A
    MOV A,C
    STAX D
    INX D
    INX H
    DCR B
    JNZ L_2B95
    POP H
    POP PSW

L_2BA2:
    CPI $10
    RNC
    PUSH PSW
    XRA A
    STA D_FC20
    STA D_FC71
    LXI H,$FC6A
    POP PSW
    CALL L_2CAD
    LXI H,$FC69
    LDA D_FC18
    XRA M
    JM L_2BDB
    LDA D_FC71
    STA D_FC20
    CALL L_2C46
    JNC L_2C27
    XCHG
    MOV A,M
    INR M
    XRA M
    JM OVERR
    CALL L_2CF2
    MOV A,M
    ORI $10
    MOV M,A
    JMP L_2C27

L_2BDB:
    CALL L_2C5A

L_2BDE:
    LXI H,$FC19
    LXI B,$0800

L_2BE4:
    MOV A,M
    ORA A
    JNZ L_2BF3
    INX H
    DCR C
    DCR C
    DCR B
    JNZ L_2BE4
    JMP L_33ED

L_2BF3:
    ANI $F0
    JNZ L_2BFE
    PUSH H
    CALL L_2C94
    POP H
    DCR C

L_2BFE:
    MVI A,$08
    SUB B
    JZ L_2C17
    PUSH PSW
    PUSH B
    MOV C,B
    LXI D,$FC19
    CALL L_2EDD
    POP B
    POP PSW
    MOV B,A
    XRA A

L_2C11:
    STAX D
    INX D
    DCR B
    JNZ L_2C11

L_2C17:
    MOV A,C
    ORA A
    JZ L_2C27
    LXI H,$FC18
    MOV B,M
    ADD M
    MOV M,A
    XRA B
    JM OVERR
    RZ

L_2C27:
    LXI H,$FC20
    MVI B,$07

L_2C2C:
    MOV A,M
    CPI $50
    RC
    DCX H
    XRA A
    STC

L_2C33:
    ADC M
    DAA
    MOV M,A
    RNC
    DCX H
    DCR B
    JNZ L_2C33
    MOV A,M
    INR M
    XRA M
    JM OVERR
    INX H
    MVI M,$10
    RET

L_2C46:
    LXI H,$FC70
    LXI D,$FC1F
    MVI B,$07

L_2C4E:
    XRA A

L_2C4F:
    LDAX D
    ADC M
    DAA
    STAX D
    DCX D
    DCX H
    DCR B
    JNZ L_2C4F
    RET

L_2C5A:
    LXI H,$FC71
    MOV A,M
    CPI $50
    JNZ L_2C64
    INR M

L_2C64:
    LXI D,$FC20
    MVI B,$08
    STC

L_2C6A:
    MVI A,$99
    ACI $00
    SUB M
    MOV C,A
    LDAX D
    ADD C
    DAA
    STAX D
    DCX D
    DCX H
    DCR B
    JNZ L_2C6A
    RC
    XCHG
    MOV A,M
    XRI $80
    MOV M,A
    LXI H,$FC20
    MVI B,$08
    XRA A

L_2C86:
    MVI A,$9A
    SBB M
    ACI $00
    DAA
    CMC
    MOV M,A
    DCX H
    DCR B
    JNZ L_2C86
    RET

L_2C94:
    LXI H,$FC20

L_2C97:
    PUSH B
    MOV D,B
    MVI C,$04

L_2C9B:
    PUSH H
    ORA A

L_2C9D:
    MOV A,M
    RAL
    MOV M,A
    DCX H
    DCR B
    JNZ L_2C9D
    MOV B,D
    POP H
    DCR C
    JNZ L_2C9B
    POP B
    RET

L_2CAD:
    ORA A
    RAR
    PUSH PSW
    ORA A
    JZ L_2CFA
    PUSH PSW
    CMA
    INR A
    MOV C,A
    MVI B,$FF
    LXI D,$0007
    DAD D
    MOV D,H
    MOV E,L
    DAD B
    MVI A,$08
    ADD C
    MOV C,A
    PUSH B
    CALL L_2EE6
    POP B
    POP PSW
    INX H
    INX D
    PUSH D
    MOV B,A
    XRA A

L_2CD0:
    MOV M,A
    INX H
    DCR B
    JNZ L_2CD0
    POP H
    POP PSW
    RNC
    MOV A,C

L_2CDA:
    PUSH B
    PUSH D
    MOV D,A
    MVI C,$04

L_2CDF:
    MOV B,D
    PUSH H
    ORA A

L_2CE2:
    MOV A,M
    RAR
    MOV M,A
    INX H
    DCR B
    JNZ L_2CE2
    POP H
    DCR C
    JNZ L_2CDF
    POP D
    POP B
    RET

L_2CF2:
    LXI H,$FC19

L_2CF5:
    MVI A,$08
    JMP L_2CDA

L_2CFA:
    POP PSW
    RNC
    JMP L_2CF5

L_2CFF:
    RST 6
    RZ
    LDA D_FC69
    ORA A
    JZ L_33ED
    MOV B,A
    LXI H,$FC18
    XRA M
    ANI $80
    MOV C,A
    MOV A,B
    ANI $7F
    MOV B,A
    MOV A,M
    ANI $7F
    ADD B
    MOV B,A
    MVI M,$00
    ANI $C0
    RZ
    CPI $C0
    JNZ L_2D26
    JMP OVERR

L_2D26:
    MOV A,B
    ADI $40
    ANI $7F
    RZ
    ORA C
    DCX H
    MOV M,A
    LXI D,$FC67
    LXI B,$0008
    LXI H,$FC1F
    PUSH D
    CALL L_2EE6
    INX H
    XRA A
    MVI B,$08

L_2D40:
    MOV M,A
    INX H
    DCR B
    JNZ L_2D40
    POP D
    LXI B,L_2DA8
    PUSH B

L_2D4B:
    CALL L_2DAF
    PUSH H
    LXI B,$0008
    XCHG
    CALL L_2EE6
    XCHG
    LXI H,$FC5F
    MVI B,$08
    CALL L_2C4E
    POP D
    CALL L_2DAF
    MVI C,$07
    LXI D,$FC70

L_2D68:
    LDAX D
    ORA A
    JNZ L_2D72
    DCX D
    DCR C
    JMP L_2D68

L_2D72:
    LDAX D
    DCX D
    PUSH D
    LXI H,$FC2F

L_2D78:
    ADD A
    JC L_2D86
    JZ L_2D95

L_2D7F:
    LXI D,$0008
    DAD D
    JMP L_2D78

L_2D86:
    PUSH PSW
    MVI B,$08
    LXI D,$FC1F
    PUSH H
    CALL L_2C4E
    POP H
    POP PSW
    JMP L_2D7F

L_2D95:
    MVI B,$0F
    LXI D,$FC26
    LXI H,$FC27
    CALL L_3472
    MVI M,$00
    POP D
    DCR C
    JNZ L_2D72
    RET

L_2DA8:
    DCX H
    MOV A,M
    INX H
    MOV M,A
    JMP L_2BDE

L_2DAF:
    LXI H,$FFF8
    DAD D
    MVI C,$03

L_2DB5:
    MVI B,$08
    ORA A

L_2DB8:
    LDAX D
    ADC A
    DAA
    MOV M,A
    DCX H
    DCX D
    DCR B
    JNZ L_2DB8
    DCR C
    JNZ L_2DB5
    RET

L_2DC7:
    LDA D_FC69
    ORA A
    JZ DV0ERR
    MOV B,A
    LXI H,$FC18
    MOV A,M
    ORA A
    JZ L_33ED
    XRA B
    ANI $80
    MOV C,A
    MOV A,B
    ANI $7F
    MOV B,A
    MOV A,M
    ANI $7F
    SUB B
    MOV B,A
    RAR
    XRA B
    ANI $40
    MVI M,$00
    JZ L_2DF4
    MOV A,B
    ANI $80
    RNZ

L_2DF1:
    JMP OVERR

L_2DF4:
    MOV A,B
    ADI $41
    ANI $7F
    MOV M,A
    JZ L_2DF1
    ORA C
    MVI M,$00
    DCX H
    MOV M,A
    LXI D,$FC1F
    LXI H,$FC70
    MVI B,$07

L_2E0A:
    MOV A,M
    ORA A
    JNZ L_2E15
    DCX D
    DCX H
    DCR B
    JNZ L_2E0A

L_2E15:
    SHLD D_FC14
    XCHG
    SHLD D_FC12
    MOV A,B
    STA D_FC16
    LXI H,$FC60

L_2E23:
    MVI B,$0F

L_2E25:
    PUSH H
    PUSH B
    LHLD D_FC14
    XCHG
    LHLD D_FC12
    LDA D_FC16
    MVI C,$FF

L_2E33:
    STC
    INR C
    MOV B,A
    PUSH H
    PUSH D

L_2E38:
    MVI A,$99
    ACI $00
    XCHG
    SUB M
    XCHG
    ADD M
    DAA
    MOV M,A
    DCX H
    DCX D
    DCR B
    JNZ L_2E38
    MOV A,M
    CMC
    SBI $00
    MOV M,A
    POP D
    POP H
    LDA D_FC16
    JNC L_2E33
    MOV B,A
    XCHG
    CALL L_2C4E
    JNC L_2E5F
    XCHG
    INR M

L_2E5F:
    MOV A,C
    POP B
    MOV C,A
    PUSH B
    MOV A,B
    ORA A
    RAR
    MOV B,A
    INR B
    MOV E,B
    MVI D,$00
    LXI H,$FC17
    DAD D
    CALL L_2C97
    POP B
    POP H
    MOV A,B
    INR C
    DCR C
    JNZ L_2EBB
    CPI $0F
    JZ L_2EAC
    RRC
    RLC
    JNC L_2EBB
    PUSH B
    PUSH H
    LXI H,$FC18
    MVI B,$08

L_2E8B:
    MOV A,M
    ORA A
    JNZ L_2EA6
    INX H
    DCR B
    JNZ L_2E8B
    POP H
    POP B
    MOV A,B
    ORA A
    RAR
    INR A
    MOV B,A
    XRA A

L_2E9D:
    MOV M,A
    INX H
    DCR B
    JNZ L_2E9D
    JMP L_2ECF

L_2EA6:
    POP H
    POP B
    MOV A,B
    JMP L_2EBB

L_2EAC:
    LDA D_FC17
    MOV E,A
    DCR A
    STA D_FC17
    XRA E
    JP L_2E23
    JMP L_33ED

L_2EBB:
    RAR
    MOV A,C
    JC L_2EC6
    ORA M
    MOV M,A
    INX H
    JMP L_2ECB

L_2EC6:
    ADD A
    ADD A
    ADD A
    ADD A
    MOV M,A

L_2ECB:
    DCR B
    JNZ L_2E25

L_2ECF:
    LXI H,$FC20
    LXI D,$FC67
    MVI B,$08
    CALL L_3472
    JMP L_2DA8

L_2EDD:
    MOV A,M
    STAX D
    INX H
    INX D
    DCR C
    JNZ L_2EDD
    RET

L_2EE6:
    MOV A,M
    STAX D
    DCX H
    DCX D
    DCR C
    JNZ L_2EE6
    RET

FN_COS:
    LXI H,D_32CE
    CALL L_31A3
    LDA D_FC18
    ANI $7F
    STA D_FC18
    LXI H,D_328E
    CALL L_319A
    CALL L_33FD
    JMP L_2F0F

FN_SIN:
    LXI H,D_32CE
    CALL L_31A3

L_2F0F:
    LDA D_FC18
    ORA A
    CM L_31E3
    CALL L_3234
    CALL FN_INT
    CALL L_31B5
    CALL L_324B
    CALL L_2B69
    LDA D_FC18
    CPI $40
    JC L_2F52
    LDA D_FC19
    CPI $25
    JC L_2F52
    CPI $75
    JNC L_2F49
    CALL L_31B5
    LXI H,D_327C
    CALL L_31C4
    CALL L_2B69
    JMP L_2F52

L_2F49:
    LXI H,D_3286
    CALL L_31B8
    CALL L_2B69

L_2F52:
    LXI H,D_335A
    JMP L_31F7

FN_TAN:
    CALL L_3234
    CALL FN_COS
    CALL L_31D2
    CALL FN_SIN
    CALL L_3245
    LDA D_FC69
    ORA A
    JNZ L_2DC7
    JMP OVERR

FN_ATN:
    LDA D_FC18
    ORA A
    RZ
    CM L_31E3
    CPI $41
    JC L_2F99
    CALL L_31B5
    LXI H,D_3286
    CALL L_31C4
    CALL L_2DC7
    CALL L_2F99
    CALL L_31B5
    LXI H,D_32AE
    CALL L_31C4
    JMP L_2B69

L_2F99:
    LXI H,D_32B6
    CALL L_31AF
    JM L_2FC9
    CALL L_3234
    LXI H,D_32BE
    CALL L_3194
    CALL L_31D2
    LXI H,D_32BE
    CALL L_31A3
    LXI H,D_3286
    CALL L_319A
    CALL L_3245
    CALL L_2DC7
    CALL L_2FC9
    LXI H,D_32C6
    JMP L_3194

L_2FC9:
    LXI H,D_339B
    JMP L_31F7

FN_LOG:
    RST 6
    JM FCERR
    JZ FCERR
    LXI H,$FC18
    MOV A,M
    PUSH PSW
    MVI M,$41
    LXI H,D_3296
    CALL L_31AF
    JM L_2FED
    POP PSW
    INR A
    PUSH PSW
    LXI H,$FC18
    DCR M

L_2FED:
    POP PSW
    STA TEMP3
    CALL L_3234
    LXI H,D_3286
    CALL L_3194
    CALL L_31D2
    LXI H,D_3286
    CALL L_319A
    CALL L_3245
    CALL L_2DC7
    CALL L_3234
    CALL L_31A0
    CALL L_3234
    CALL L_3234
    LXI H,D_3331
    CALL L_3209
    CALL L_31D2
    LXI H,D_3310
    CALL L_3209
    CALL L_3245
    CALL L_2DC7
    CALL L_3245
    CALL L_2CFF
    LXI H,D_329E
    CALL L_3194
    CALL L_3245
    CALL L_2CFF
    CALL L_3234
    LDA TEMP3
    SUI $41
    MOV L,A
    ADD A
    SBB A
    MOV H,A
    CALL L_3543
    CALL L_35C2
    CALL L_3245
    CALL L_2B78
    LXI H,D_32A6
    JMP L_31A3

FN_SQR:
    RST 6
    RZ
    JM FCERR
    CALL L_31B5
    LDA D_FC18
    ORA A
    RAR
    ACI $20
    STA D_FC69
    LDA D_FC19
    ORA A
    RRC
    ORA A
    RRC
    ANI $33
    ADI $10
    STA D_FC6A
    MVI A,$07

L_307C:
    STA TEMP3
    CALL L_3234
    CALL L_322E
    CALL L_2DC7
    CALL L_3245
    CALL L_2B78
    LXI H,D_327C
    CALL L_31A3
    CALL L_31B5
    CALL L_324B
    LDA TEMP3
    DCR A
    JNZ L_307C
    JMP L_31C1

FN_EXP:
    LXI H,D_3274
    CALL L_31A3
    CALL L_3234
    CALL FN_CINT
    MOV A,L
    RAL
    SBB A
    CMP H
    JZ L_30CB
    MOV A,H
    ORA A
    JP L_30C8
    CALL L_35CF
    CALL L_324B
    LXI H,D_327E
    JMP L_31C4

L_30C8:
    JMP OVERR

L_30CB:
    SHLD TEMP3
    CALL FN_CDBL
    CALL L_31B5
    CALL L_324B
    CALL L_2B69
    LXI H,D_327C
    CALL L_31AF
    PUSH PSW
    JZ L_30ED
    JC L_30ED
    LXI H,D_327C
    CALL L_319A

L_30ED:
    CALL L_3234
    LXI H,D_32F7
    CALL L_31F7
    CALL L_31D2
    LXI H,D_32D6
    CALL L_31EB
    CALL L_3245
    CALL L_322E
    CALL L_3234
    CALL L_2B69
    LXI H,$FC60
    CALL L_31CA
    CALL L_3245
    CALL L_324B
    CALL L_2B78
    LXI H,$FC60
    CALL L_31B8
    CALL L_2DC7
    POP PSW
    JC L_3130
    JZ L_3130
    LXI H,D_3296
    CALL L_31A3

L_3130:
    LDA TEMP3
    LXI H,$FC18
    MOV C,M
    ADD M
    MOV M,A
    XRA C
    RP
    JMP OVERR

FN_RND:
    RST 6
    LXI H,$FC79
    JZ L_3173
    CM L_31CA
    LXI H,$FC60
    LXI D,$FC79
    CALL L_31CD
    LXI H,D_3264
    CALL L_31B8
    LXI H,D_325C
    CALL L_31C4
    LXI D,$FC67
    CALL L_2D4B
    LXI D,$FC20
    LXI H,$FC7A
    MVI B,$07
    CALL L_3469
    LXI H,$FC79
    MVI M,$00

L_3173:
    CALL L_31C4
    LXI H,$FC18
    MVI M,$40
    XRA A
    STA D_FC20
    JMP L_2BDE

L_3182:
    LXI D,D_326C
    LXI H,$FC79
    JMP L_31CD

L_318B:
    CALL L_3543
    LXI H,$FC79
    JMP L_31CA

L_3194:
    CALL L_31B8
    JMP L_2B78

L_319A:
    CALL L_31B8
    JMP L_2B69

L_31A0:
    LXI H,$FC18

L_31A3:
    CALL L_31B8
    JMP L_2CFF

L_31A9:
    CALL L_31B8
    JMP L_2DC7

L_31AF:
    CALL L_31B8
    JMP L_34D2

L_31B5:
    LXI H,$FC18

L_31B8:
    LXI D,$FC69

L_31BB:
    XCHG
    CALL L_31CD
    XCHG
    RET

L_31C1:
    LXI H,$FC69

L_31C4:
    LXI D,$FC18
    JMP L_31BB

L_31CA:
    LXI D,$FC18

L_31CD:
    MVI B,$08
    JMP L_3469

L_31D2:
    POP H
    SHLD D_FBE7
    CALL L_3245
    CALL L_3234
    CALL L_31C1
    LHLD D_FBE7
    PCHL

L_31E3:
    CALL L_33FD
    LXI H,L_33FD
    XTHL
    PCHL

L_31EB:
    SHLD D_FBE7
    CALL L_31A0
    LHLD D_FBE7
    JMP L_3209

L_31F7:
    SHLD D_FBE7
    CALL L_3234
    LHLD D_FBE7
    CALL L_31EB
    CALL L_3245
    JMP L_2CFF

L_3209:
    MOV A,M
    PUSH PSW
    INX H
    PUSH H
    LXI H,$FBE7
    CALL L_31CA
    POP H
    CALL L_31C4

L_3217:
    POP PSW
    DCR A
    RZ
    PUSH PSW
    PUSH H
    LXI H,$FBE7
    CALL L_31A3
    POP H
    CALL L_31B8
    PUSH H
    CALL L_2B78
    POP H
    JMP L_3217

L_322E:
    LXI H,$FC70
    JMP L_3237

L_3234:
    LXI H,$FC1F

L_3237:
    MVI A,$04
    POP D

L_323A:
    MOV B,M
    DCX H
    MOV C,M
    DCX H
    PUSH B
    DCR A
    JNZ L_323A
    XCHG
    PCHL

L_3245:
    LXI H,$FC69
    JMP L_324E

L_324B:
    LXI H,$FC18

L_324E:
    MVI A,$04
    POP D

L_3251:
    POP B
    MOV M,C
    INX H
    MOV M,B
    INX H
    DCR A
    JNZ L_3251
    XCHG
    PCHL

D_325C:
    .byte $00, $14, $38, $98, $20, $42, $08, $21

D_3264:
    .byte $00, $21, $13, $24, $86, $54, $05, $19

D_326C:
    .byte $00, $40, $64, $96, $51, $37, $23, $58

D_3274:
    .byte $40, $43, $42, $94, $48, $19, $03, $24

D_327C:
    .byte $40, $50

D_327E:
    .byte $00, $00, $00, $00, $00, $00, $00, $00

D_3286:
    .byte $41, $10, $00, $00, $00, $00, $00, $00

D_328E:
    .byte $40, $25, $00, $00, $00, $00, $00, $00

D_3296:
    .byte $41, $31, $62, $27, $76, $60, $16, $84

D_329E:
    .byte $40, $86, $85, $88, $96, $38, $06, $50

D_32A6:
    .byte $41, $23, $02, $58, $50, $92, $99, $40

D_32AE:
    .byte $41, $15, $70, $79, $63, $26, $79, $49

D_32B6:
    .byte $40, $26, $79, $49, $19, $24, $31, $12

D_32BE:
    .byte $41, $17, $32, $05, $08, $07, $56, $89

D_32C6:
    .byte $40, $52, $35, $98, $77, $55, $98, $30

D_32CE:
    .byte $40, $15, $91, $54, $94, $30, $91, $90

D_32D6:
    .byte $04, $41, $10, $00, $00, $00, $00, $00, $00, $43, $15, $93, $74, $15, $23, $60
    .byte $31, $44, $27, $09, $31, $69, $40, $85, $16, $44, $44, $97, $63, $35, $57, $40
    .byte $58

D_32F7:
    .byte $03, $42, $18, $31, $23, $60, $15, $92, $75, $43, $83, $14, $06, $72, $12, $93
    .byte $71, $44, $51, $78, $09, $19, $91, $51, $62

D_3310:
    .byte $04, $C0, $71, $43, $33, $82, $15, $32, $26, $41, $62, $50, $36, $51, $12, $79
    .byte $08, $C2, $13, $68, $23, $70, $24, $15, $03, $41, $85, $16, $73, $19, $87, $23
    .byte $89

D_3331:
    .byte $05, $41, $10, $00, $00, $00, $00, $00, $00, $C2, $13, $21, $04, $78, $35, $01
    .byte $56, $42, $47, $92, $52, $56, $04, $38, $73, $C2, $64, $90, $66, $82, $74, $09
    .byte $43, $42, $29, $41, $57, $50, $17, $23, $23

D_335A:
    .byte $08, $C0, $69, $21, $56, $92, $29, $18, $09, $41, $38, $17, $28, $86, $38, $57
    .byte $71, $C2, $15, $09, $44, $99, $47, $48, $01, $42, $42, $05, $86, $89, $66, $73
    .byte $55, $C2, $76, $70, $58, $59, $68, $32, $91, $42, $81, $60, $52, $49, $27, $55
    .byte $13, $C2, $41, $34, $17, $02, $24, $03, $98, $41, $62, $83, $18, $53, $07, $17
    .byte $96

D_339B:
    .byte $08, $BF, $52, $08, $69, $39, $04, $00, $00, $3F, $75, $30, $71, $49, $13, $48
    .byte $00, $BF, $90, $81, $34, $32, $24, $70, $50, $40, $11, $11, $07, $94, $18, $40
    .byte $29, $C0, $14, $28

.if MODEL = 100
    .byte $56
.else
    .byte $57
.endif

    .byte $08, $55, $48, $84, $40, $19, $99, $99, $99, $94, $89, $67, $C0, $33, $33, $33
    .byte $33, $33, $31, $60, $41, $10, $00, $00, $00, $00, $00, $00

L_33DC:
    LDA D_FC18
    ORA A
    RZ
    LDA D_FC18
    JMP L_33E8

L_33E7:
    CMA

L_33E8:
    RAL

L_33E9:
    SBB A
    RNZ
    INR A
    RET

L_33ED:
    XRA A
    STA D_FC18
    RET
