;; MODEL 100 ROM: PLOT, UNPLOT AND THE LCD'S DRIVERS
;;
;; Runs at $744C-$770A. Model100.asm describes the ROM as a whole and how it is named.

PLOT:
    .byte $F6                           ; ORI $AF: skips the next byte

UNPLOT:
    XRA A
    PUSH PSW
    CALL L_765C
    PUSH D
    MVI C,$FE
    MOV A,D

L_7456:
    INR C
    INR C
    MOV D,A
    SUI $32
    JNC L_7456
    MVI B,$00
    LXI H,D_7643
    MOV A,E
    RAL
    RAL
    RAL
    JNC L_746D
    LXI H,D_764D

L_746D:
    DAD B
    MOV B,A
    CALL L_753B
    MOV A,B
    ANI $C0
    ORA D
    MOV B,A
    MVI E,$01
    LXI H,$FFEC
    CALL L_74F5
    POP D
    MOV D,B
    MOV A,E
    ANI $07
    ADD A
    MOV C,A
    MVI B,$00
    LXI H,D_7643
    DAD B
    POP PSW
    MOV A,M
    LXI H,$FFEC
    JNZ L_7497
    CMA
    ANA M
    .byte $06                           ; MVI B,$B6: skips the next byte

L_7497:
    ORA M
    MOV M,A
    MOV B,D
    MVI E,$01
    CALL L_74F6
    JMP L_743C

L_74A2:
    PUSH H
    MVI E,$06
    LDA D_FFF5
    CPI $08
    JZ L_74B7
    CPI $10
    JZ L_74B9
    CPI $21
    JNZ L_74BB

L_74B7:
    DCR E
    DCR E

L_74B9:
    DCR E
    DCR E

L_74BB:
    MOV C,A
    ADD C
    ADD C
    MOV C,A
    MVI B,$00
    LDA D_FFF4
    RAR
    RAR
    RAR
    LXI H,D_75C9
    JC L_74D0
    LXI H,D_7551

L_74D0:
    DAD B
    MOV B,A
    CALL L_753B
    SHLD D_FFF6
    MOV A,B
    ORA M
    MOV B,A
    POP H
    DCR D
    CALL L_74F7
    INR D
    MVI A,$06
    SUB E
    RZ
    MOV E,A
    PUSH H
    LHLD D_FFF6
    INX H
    CALL L_753B
    POP H
    MOV A,B
    ANI $C0
    MOV B,A
    DCR D
    .byte $DA                           ; JC $AFF6: skips the next two bytes, unless it jumps

L_74F5:
    .byte $F6                           ; ORI $AF: skips the next byte

L_74F6:
    XRA A

L_74F7:
    PUSH D
    PUSH PSW
    MOV A,B
    CALL L_7548
    OUT $FE
    JZ L_7507
    CALL L_7548
    IN $FF

L_7507:
    POP PSW
    JNZ L_751B

L_750B:
    IN $FE
    RAL
    JC L_750B
    MOV A,M
    OUT $FF
    INX H
    DCR E
    JNZ L_750B
    POP D
    RET

L_751B:
    IN $FE
    RAL
    JC L_751B
    IN $FF
    MOV M,A
    INX H
    DCR E
    JNZ L_751B
    POP D
    RET

L_752B:
    CALL L_7533
    MVI A,$3E
    OUT $FE
    RET

L_7533:
    MVI C,$03
    CALL L_7657
    LXI H,D_7641

L_753B:
    MOV A,M
    OUT $B9
    INX H
    IN $BA
    ANI $FC
    ORA M
    OUT $BA
    INX H
    RET

L_7548:
    PUSH PSW

L_7549:
    IN $FE
    RAL
    JC L_7549
    POP PSW
    RET

D_7551:
    .byte $01, $00, $00, $01, $00, $06, $01, $00, $0C, $01, $00, $12, $01, $00, $18, $01
    .byte $00, $1E, $01, $00, $24, $01, $00, $2A, $01, $00, $30, $02, $00, $04, $02, $00
    .byte $0A, $02, $00, $10, $02, $00, $16, $02, $00, $1C, $02, $00, $22, $02, $00, $28
    .byte $02, $00, $2E, $04, $00, $02, $04, $00, $08, $04, $00, $0E, $04, $00, $14, $04
    .byte $00, $1A, $04, $00, $20, $04, $00, $26, $04, $00, $2C, $08, $00, $00, $08, $00
    .byte $06, $08, $00, $0C, $08, $00, $12, $08, $00, $18, $08, $00, $1E, $08, $00, $24
    .byte $08, $00, $2A, $08, $00, $30, $10, $00, $04, $10, $00, $0A, $10, $00, $10, $10
    .byte $00, $16, $10, $00, $1C, $10, $00, $22

D_75C9:
    .byte $20, $00, $00, $20, $00, $06, $20, $00, $0C, $20, $00, $12, $20, $00, $18, $20
    .byte $00, $1E, $20, $00, $24, $20, $00, $2A, $20, $00, $30, $40, $00, $04, $40, $00
    .byte $0A, $40, $00, $10, $40, $00, $16, $40, $00, $1C, $40, $00, $22, $40, $00, $28
    .byte $40, $00, $2E, $80, $00, $02, $80, $00, $08, $80, $00, $0E, $80, $00, $14, $80
    .byte $00, $1A, $80, $00, $20, $80, $00, $26, $80, $00, $2C, $00, $01, $00, $00, $01
    .byte $06, $00, $01, $0C, $00, $01, $12, $00, $01, $18, $00, $01, $1E, $00, $01, $24
    .byte $00, $01, $2A, $00, $01, $30, $00, $02, $04, $00, $02, $0A, $00, $02, $10, $00
    .byte $02, $16, $00, $02, $1C, $00, $02, $22

D_7641:
    .byte $FF, $03

D_7643:
    .byte $01, $00, $02, $00, $04, $00, $08, $00, $10, $00

D_764D:
    .byte $20, $00, $40, $00, $80, $00, $00, $01, $00, $02

L_7657:
    DCR C
    JNZ L_7657
    RET

L_765C:
    DI
    MVI A,$1D
    SIM
    EI
    RET

L_7662:
    CALL L_765C
    MVI B,$00

L_7667:
    CALL L_7676
    MVI C,$50
    CALL L_7657
    DCR B
    JNZ L_7667
    JMP L_743C

L_7676:
    IN $BA
    XRI $20
    OUT $BA
    RET

L_767D:
    LDA D_FFFB
    INR A
    RET

L_7682:
    LXI H,$FFFB
    IN $82
    ANI $07
    JZ L_768F
    MVI M,$00
    RET

L_768F:
    ORA M
    RNZ
    MVI M,$FF

L_7693:
    MVI A,$C1
    OUT $83
    IN $80
    MVI A,$04
    OUT $81
    OUT $80
    RET

L_76A0:
    CALL L_767D
    STC
    RNZ
    MVI A,$03
    STA D_FFFA
    XRA A
    CALL L_76DE
    CALL L_76FB
    RLC
    RLC
    ANI $03
    RET

L_76B6:
    MVI A,$03
    STA D_FFFA
    LXI H,KEYTAB
    MVI B,$05

L_76C0:
    MOV A,M
    CALL L_76DE
    INX H
    DCR B
    JNZ L_76C0
    CALL L_76FB
    ORA A
    STC
    RNZ
    LXI H,$E000

L_76D2:
    CALL L_76FB
    MOV M,A
    INX H
    DCR B
    JNZ L_76D2
    JMP D_E000

L_76DE:
    PUSH PSW

L_76DF:
    CALL L_729F
    JC L_76F4
    IN $82
    RLC
    JNC L_76DF
    LDA D_FFFA
    OUT $81
    POP PSW
    OUT $80
    RET

L_76F4:
    POP PSW

L_76F5:
    POP PSW
    CALL L_7693
    STC
    RET

L_76FB:
    CALL L_729F
    JC L_76F5
    IN $82
    ANI $20
    JZ L_76FB
    IN $80
    RET
