;; MODEL 100 ROM: RAM FILES: MAKING A TEXT FILE, CSAVE AND CLOAD
;;
;; Runs at $220F-$270B. Model100.asm describes the ROM as a whole and how it is named.

MAKTXT:
    CALL L_2146
    CALL L_208F
    XCHG
    STC
    RNZ
    CALL L_20E4
    PUSH H
    LHLD DOSTRT
    PUSH H
    MVI A,$1A
    CALL INSCHR
    JC L_3F17
    POP D
    POP H
    PUSH H
    PUSH D
    MVI A,$C0
    DCX D
    CALL L_2239
    CALL L_2146
    POP H
    POP D
    ANA A
    RET

L_2239:
    PUSH D
    MOV M,A
    INX H
    MOV M,E
    INX H
    MOV M,D
    INX H
    .byte $3E                           ; MVI: skips the next byte

L_2241:
    PUSH D
    LXI D,FILNAM
    MVI B,$08
    CALL L_3469
    POP D
    RET

L_224C:
    PUSH H
    MVI B,$09
    LXI D,FILNAM
    LXI H,$FC9C

L_2255:
    MOV C,M
    LDAX D
    MOV M,A
    MOV A,C
    STAX D
    INX D
    INX H
    DCR B
    JNZ L_2255
    POP H
    RET

L_2262:
    CALL L_2146
    LXI H,$FFFF
    SHLD D_F62E
    MOV B,H
    MOV C,L
    LHLD D_F9A5
    PUSH H
    MVI A,$1A

L_2273:
    CMP M
    INX B
    INX H
    JNZ L_2273
    POP H
    CALL MASDEL
    JMP L_2146

ST_CSAVE:
    CPI $4D
    JZ L_22DD
    CALL L_25FC

L_2288:
    DCX H
    RST 2
    JZ L_2298

CSKPCM:
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    MVI E,$02
    ANA A
    PUSH PSW
    JMP L_4E0B

L_2298:
    CALL LINKER
    XCHG
    LHLD TXTTAB
    MOV A,E
    SUB L
    MOV L,A
    MOV A,D
    SBB H
    MOV H,A
    DCX H
    MOV A,H
    ORA L
    JZ L_0501
    SHLD D_FAD0
    PUSH H
    CALL L_260B
    CALL L_2648
    POP D
    LHLD TXTTAB

L_22B9:
    MVI C,$00

L_22BB:
    MOV A,M
    CALL CSOUT
    INX H
    DCX D
    MOV A,D
    ORA E
    JNZ L_22BB
    CALL L_2635
    JMP L_0501

L_22CC:
    RST 2
    CALL L_207A
    MOV A,D
    CPI $FD
    JZ L_22E1
    CPI $F8
    JZ L_22F4
    RST 7
    .byte $5C                           ; the hook's number

L_22DD:
    RST 2
    CALL L_25FC

L_22E1:
    CALL L_2346
    CALL L_2611
    CALL L_2648
    LHLD D_FAD0
    XCHG
    LHLD D_FACE
    JMP L_22B9

L_22F4:
    CALL L_2346
    CALL L_2146
    CALL L_2089
    CNZ L_1FD9
    CALL L_20E4
    PUSH H
    LHLD COSTRT
    PUSH H
    LHLD D_FAD0
    MOV A,H
    ORA L
    JZ L_3F17
    PUSH H
    LXI B,$0006
    DAD B
    MOV B,H
    MOV C,L
    LHLD VARTAB
    SHLD D_FB99
    CNC MAKHOL
    JC L_3F17
    XCHG
    LXI H,$FACE
    CALL L_2540
    LHLD D_FACE
    POP B
    CALL L_6BDB
    POP H
    SHLD COSTRT
    POP H
    MVI A,$A0
    XCHG
    LHLD D_FB99
    XCHG
    CALL L_2239
    CALL L_2146
    JMP READY

L_2346:
    CALL L_2372
    PUSH D
    CALL L_2372
    PUSH D
    DCX H
    RST 2
    LXI D,$0000
    CNZ L_2372
    DCX H
    RST 2
    JNZ SNERR
    XCHG
    SHLD D_FAD2
    POP D
    POP H
    SHLD D_FACE
    MOV A,E
    SUB L
    MOV L,A
    MOV A,D
    SBB H
    MOV H,A
    JC FCERR
    INX H
    SHLD D_FAD0
    RET

L_2372:
    RST 1
    .byte $2C                           ; SYNCHR: ','
    JMP FRMQNT

ST_CLOAD:
    CPI $4D
    JZ L_24A7
    CPI $A3
    JZ L_2456
    CALL L_25E7
    ORI $FF
    PUSH PSW

L_2387:
    POP PSW
    PUSH PSW
    JNZ L_2391
    DCX H
    RST 2
    JNZ FCERR

L_2391:
    DCX H
    RST 2
    MVI A,$00
    STC
    CMC
    JZ L_23A6
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $52                           ; SYNCHR: 'R'
    JNZ SNERR
    POP PSW
    STC
    PUSH PSW
    MVI A,$80

L_23A6:
    PUSH PSW
    STA D_FCA7

L_23AA:
    CALL L_2667
    CPI $D3
    JZ L_23BD
    CPI $9C
    JZ L_2432

L_23B7:
    CALL L_26DD
    JMP L_23AA

L_23BD:
    POP B
    POP PSW
    PUSH PSW
    PUSH B
    JZ L_23B7
    POP PSW
    POP PSW
    SBB A
    STA D_FC92
    CALL L_26E3
    CALL L_20FF
    LHLD D_FAD0
    PUSH H
    MOV B,H
    MOV C,L
    LHLD TXTTAB
    PUSH H
    CALL MAKHOL
    JC L_3F17
    LXI H,L_2426
    SHLD D_F652
    LHLD DOSTRT
    DAD B
    SHLD DOSTRT
    CALL L_26D1
    POP H
    POP D
    CALL L_2413
    JNZ L_2426
    MOV L,A
    MOV H,A
    SHLD D_F652
    CALL CTOFF
    CALL L_4BB8
    CALL LINKER
    CALL L_3F28
    LDA D_FC92
    ANA A
    JNZ NEWSTT
    JMP READY

L_2413:
    MVI C,$00

L_2415:
    CALL CASIN
    MOV M,A
    INX H
    DCX D
    MOV A,D
    ORA E
    JNZ L_2415
    CALL CASIN
    MOV A,C
    ANA A
    RET

L_2426:
    CALL L_20FF
    LXI H,$0000
    SHLD D_F652
    JMP L_1491

L_2432:
    CALL L_26E3
    CALL L_4BB8
    LHLD D_FC83
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    SHLD D_FC8C
    MVI M,$01
    INX H
    INX H
    INX H
    INX H
    MVI M,$FD
    INX H
    INX H
    XRA A
    MOV M,A
    INX H
    MOV M,A
    STA D_FA8E
    JMP L_4DA6

L_2456:
    CALL L_25E8
    PUSH H
    CALL L_2650
    CALL L_26D1
    LHLD D_FAD0
    XCHG
    LHLD TXTTAB
    CALL L_2590
    JNZ L_2478
    MOV A,M
    INX H
    ORA M
    JNZ L_2478

L_2473:
    CALL CTOFF
    POP H
    RET

L_2478:
    LXI H,D_2481
    CALL L_5791
    JMP L_2473

D_2481:
    .byte "Verify failed", $0D, $0A, $00

L_2491:
    RST 2
    POP PSW
    PUSH PSW
    JZ FCERR
    CALL L_207A
    MOV A,D
    CPI $FD
    JZ L_24B3
    CPI $F8
    JZ L_24E7
    RST 7
    .byte $5E                           ; the hook's number

L_24A7:
    RST 2
    CPI $A3
    JZ L_2573
    CALL L_25E7
    ORI $FF
    PUSH PSW

L_24B3:
    DCX H
    RST 2
    JNZ SNERR
    PUSH H
    CALL L_2656
    LHLD D_FAD2
    MOV A,H
    ORA L
    JNZ L_24CB
    POP H
    POP PSW
    PUSH PSW
    PUSH H
    JC FCERR

L_24CB:
    CALL L_2531
    JC L_3F17
    CALL L_26D1
    LHLD D_FAD0
    XCHG
    LHLD D_FACE
    CALL L_2413
    JNZ L_1491
    CALL CTOFF
    JMP L_251A

L_24E7:
    PUSH H
    CALL L_2146
    CALL L_2089
    JZ FFERR
    XCHG
    CALL L_253D
    PUSH H
    LHLD D_FAD2
    MOV A,H
    ORA L
    JNZ L_2507
    POP D
    POP H
    POP PSW
    PUSH PSW
    PUSH H
    PUSH D
    JC FCERR

L_2507:
    CALL L_2531
    JC L_3F17
    LHLD D_FAD0
    MOV B,H
    MOV C,L
    LHLD D_FACE
    XCHG
    POP H
    CALL L_6BDB

L_251A:
    POP H
    POP PSW
    JNC L_3F2C
    CALL L_3F2C
    LHLD D_FAD2
    SHLD D_F661
    CALL D_F660
    LHLD D_FB99
    JMP NEWSTT

L_2531:
    CALL L_25A4

L_2534:
    LHLD D_F5F4
    XCHG
    LHLD D_FACE
    RST 3
    RET

L_253D:
    LXI D,$FACE

L_2540:
    MVI B,$06

L_2542:
    MOV A,M
    STAX D
    INX H
    INX D
    DCR B
    JNZ L_2542
    RET

L_254B:
    CALL L_253D
    PUSH H
    CALL L_2534
    JC L_256D
    XCHG
    LHLD D_FAD0
    MOV B,H
    MOV C,L
    POP H
    CALL L_6BDB
    LHLD D_FAD2
    MOV A,H
    ORA L
    SHLD D_F661
    CNZ D_F660
    JMP MENU

L_256D:
    CALL ST_BEEP
    JMP MENU

L_2573:
    RST 2
    CALL L_25E7
    PUSH H
    CALL L_2656
    CALL L_26D1
    LHLD D_FAD0
    XCHG
    LHLD D_FACE
    CALL L_2590
    JNZ L_2478
    CALL CTOFF
    POP H
    RET

L_2590:
    MVI C,$00

L_2592:
    CALL CASIN
    CMP M
    RNZ
    INX H
    DCX D
    MOV A,D
    ORA E
    JNZ L_2592
    CALL CASIN
    MOV A,C
    ANA A
    RET

L_25A4:
    LHLD CURLIN
    INX H
    MOV A,H
    ORA L
    RNZ
    LHLD D_FACE
    PUSH H
    XCHG
    LXI H,D_25D5
    CALL L_25CD
    LHLD D_FAD0
    DCX H
    POP D
    DAD D
    XCHG
    LXI H,D_25DB
    CALL L_25CD
    LHLD D_FAD2
    MOV A,H
    ORA L
    RZ
    XCHG
    LXI H,D_25E1

L_25CD:
    PUSH D
    CALL L_5791
    POP H
    JMP L_39D4

D_25D5:
    .byte "Top: ", $00

D_25DB:
    .byte "End: ", $00

D_25E1:
    .byte "Exe: ", $00

L_25E7:
    DCX H

L_25E8:
    RST 2
    JNZ L_25FC
    MVI B,$06
    LXI D,FILNAM
    MVI A,$20

L_25F3:
    STAX D
    INX D
    DCR B
    JNZ L_25F3
    JMP L_2602

L_25FC:
    CALL L_4C0F
    JNZ L_2604

L_2602:
    MVI D,$FD

L_2604:
    MOV A,D
    CPI $FD
    JNZ FCERR
    RET

L_260B:
    MVI A,$D3
    .byte $01                           ; LXI: skips the next instruction

L_260E:
    MVI A,$9C
    .byte $01                           ; LXI: skips the next instruction

L_2611:
    MVI A,$D0
    PUSH PSW
    CALL L_1499
    POP PSW
    CALL CSOUT
    MVI C,$00
    LXI H,FILNAM
    LXI D,$0602

L_2623:
    MOV A,M
    CALL CSOUT
    INX H
    DCR D
    JNZ L_2623
    LXI H,$FACE
    MVI D,$0A
    DCR E
    JNZ L_2623

L_2635:
    MOV A,C
    CMA
    INR A
    CALL CSOUT
    MVI B,$14

L_263D:
    XRA A
    CALL CSOUT
    DCR B
    JNZ L_263D
    JMP CTOFF

L_2648:
    CALL L_1499
    MVI A,$8D
    JMP CSOUT

L_2650:
    MVI B,$D3
    .byte $11                           ; LXI: skips the next instruction

L_2653:
    MVI B,$9C
    .byte $11                           ; LXI: skips the next instruction

L_2656:
    MVI B,$D0

L_2658:
    PUSH B
    CALL L_2667
    POP B
    CMP B
    JZ L_26E3

.if MODEL = 100
    CALL L_26DD
.else
    CALL L_6C37
.endif

    JMP L_2658

L_2667:
    CALL L_148A
    CALL CASIN
    CPI $D3
    JZ L_267C
    CPI $9C
    JZ L_267C
    CPI $D0
    JNZ L_2667

L_267C:
    PUSH PSW
    LXI H,$FC9C
    LXI D,$0602
    MVI C,$00

L_2685:
    CALL CASIN
    MOV M,A
    INX H
    DCR D
    JNZ L_2685
    LXI H,$FACE
    MVI D,$0A
    DCR E
    JNZ L_2685
    CALL CASIN
    MOV A,C
    ANA A
    JNZ L_26CD
    CALL CTOFF
    LXI H,FILNAM
    MVI B,$06
    MVI A,$20

L_26A9:
    CMP M
    JNZ L_26B5
    INX H
    DCR B
    JNZ L_26A9
    JMP L_26C8

L_26B5:
    LXI D,FILNAM
    LXI H,$FC9C
    MVI B,$06

L_26BD:
    LDAX D
    CMP M
    JNZ L_26CA
    INX D
    INX H
    DCR B
    JNZ L_26BD

L_26C8:
    POP PSW
    RET

L_26CA:
    CALL L_26DD

L_26CD:
    POP PSW
    JMP L_2667

L_26D1:
    CALL L_148A
    CALL CASIN
    CPI $8D
    JNZ L_1491
    RET

L_26DD:
    LXI D,D_2705
    JMP L_26E6

L_26E3:
    LXI D,D_26FE

L_26E6:
    LHLD CURLIN
    INX H
    MOV A,H
    ORA L
    RNZ
    XCHG
    CALL L_5791
    XRA A
    STA D_FCA2
    LXI H,$FC9C
    CALL STROUT
    JMP ERAEOL

D_26FE:
    .byte "Found:", $00

D_2705:
    .byte "Skip :", $00
