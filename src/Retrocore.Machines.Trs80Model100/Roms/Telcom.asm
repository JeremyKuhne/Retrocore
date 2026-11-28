;; MODEL 100 ROM: TELCOM
;;
;; Runs at $5146-$5796. Model100.asm describes the ROM as a whole and how it is named.

TELCOM:
    CALL UNLOCK
    LXI H,D_51A4
    CALL STDSPF
    JMP L_51C7

L_5152:
    CALL ST_BEEP
    LXI H,D_51A4
    CALL STFNK

L_515B:
    CALL L_5D53
    LXI H,L_5152
    SHLD D_F652
    LXI H,D_517C
    CALL L_5791
    CALL INLIN
    RST 2
    ANA A
    JZ L_515B
    LXI D,TELCMD
    CALL L_6CA7
    JZ L_5152
    RET

D_517C:
    .byte "Telcom: ", $00

TELCMD:
    .byte "STAT"
    .word L_51C0
    .byte "TERM"
    .word L_5455
    .byte "CALL"
    .word L_522F
    .byte "FIND"
    .word L_524D
    .byte "MENU"
    .word MENU
    .byte $FF                               ; the end

D_51A4:
    .byte "Find", $A0, "Call", $A0, "Stat", $A0, $54
    .byte $65, $72, $6D, $8D, $80, $80, $80, "Menu", $8D

L_51C0:
    DCX H
    RST 2
    INR A
    DCR A
    JNZ L_51ED

L_51C7:
    LXI H,$F65B
    MVI B,$05

L_51CC:
    MOV A,M
    RST 4
    INX H
    DCR B
    JNZ L_51CC
    MVI A,$2C
    RST 4
    LDA D_F62B
    RRC
    MVI A,$32
    SBB B
    RST 4
    LXI H,D_51E7
    CALL STROUT
    JMP L_515B

D_51E7:
    .byte "0 pps", $00

L_51ED:
    JC L_51FE
    CPI $2C
    JZ L_520A
    CALL MAKUPS
    CPI $4D
    JNZ L_5152
    INX H

L_51FE:
    CALL SETSER
    CALL CLSCOM
    DCX H
    RST 2
    ANA A
    JZ L_515B

L_520A:
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    CPI $14
    JZ L_521A
    SUI $0A
    JNZ L_5152
    INR A

L_521A:
    STA D_F62B
    JMP L_515B

L_5220:
    LXI H,D_5244
    CALL L_5A58
    POP D
    CALL L_5284
    JZ L_5152
    XCHG
    .byte $F6

L_522F:
    STC
    PUSH H
    LXI H,D_5244
    CC L_5A58
    POP H
    CALL DIAL
    JC L_5152
    JNZ L_515B
    JMP L_5468

D_5244:
    .byte "Calling ", $00

L_524D:
    SUB A
    CALL L_5DB1
    PUSH H
    CALL L_5AA6
    JZ L_5152
    CALL GTXTTB
    XCHG
    POP H

L_525D:
    CALL L_5C3F
    JNC L_515B
    PUSH H
    PUSH D
    CALL L_5DC5
    CALL L_5284
    CNZ L_5292
    CALL CRLF
    CALL L_5C7F
    JZ L_515B
    CPI $43
    JZ L_5220
    POP D
    CALL L_5C6D
    POP H
    JMP L_525D

L_5284:
    CALL L_52A8
    RZ
    RST 4
    CPI $3A
    INX D
    JNZ L_5284
    JMP L_52AE

L_5292:
    CALL L_52A8
    RZ
    CPI $3C
    JZ L_52A3
    CPI $3A
    RZ
    RST 4
    INX D
    JMP L_5292

L_52A3:
    RST 4
    MVI A,$3E
    RST 4
    RET

L_52A8:
    CALL L_5C74
    DCX D
    LDAX D
    RZ

L_52AE:
    CPI $1A
    JZ L_5152
    RET

L_52B4:
    IN $BA
    ANI $7F
    OUT $BA
    RET

DISC:
    CALL L_52D8
    CALL L_5351

L_52C1:
    IN $BA
    ORI $80
    OUT $BA
    RET

L_52C8:
    LDA D_FAAE
    ORI $01
    JMP L_52DD

CONN:
    CALL L_52B4
    MVI A,$03
    JMP L_52DD

L_52D8:
    LDA D_FAAE
    ANI $01

L_52DD:
    STA D_FAAE
    OUT $A8
    STC
    RET

L_52E4:
    IN $BB
    ANI $10
    JZ L_52F9
    CALL CONN

L_52EE:
    CALL L_729F
    RC
    CALL CARDET
    JNZ L_52EE
    RET

L_52F9:
    CALL L_52C8
    CALL L_52B4
    NOP
    NOP
    NOP
    CALL L_52EE
    RC
    MVI A,$05
    CALL L_5316
    CALL CONN
    ANA A
    RET

L_5310:
    XRA A
    MVI A,$05

L_5313:
    CNZ L_531A

L_5316:
    DCR A
    JNZ L_5313

L_531A:
    MVI C,$C8

L_531C:
    CALL L_5326
    CALL L_5326
    DCR C
    JNZ L_531C

L_5326:
    MVI B,$AC

L_5328:
    DCR B
    JNZ L_5328
    RET

DIAL:
    IN $BA
    PUSH PSW
    ORI $08
    OUT $BA
    CALL L_5359
    POP B
    PUSH PSW
    MOV A,B
    ANI $08
    MOV B,A
    IN $BA
    ANI $F7
    ORA B
    OUT $BA
    POP PSW
    RNC
    CALL DISC
    CALL L_52C8
    MVI A,$03
    CALL L_5316

L_5351:
    LDA D_FAAE
    ANI $02
    JMP L_52DD

L_5359:
    XRA A
    STA D_FAAE
    CALL L_52C1
    CALL L_52C8
    CALL L_531A
    CALL CONN
    CALL L_52D8
    CALL L_5310
    DCX H

L_5370:
    CALL L_729F
    RC
    PUSH H
    XCHG
    CALL L_5C74
    DCX D
    LDAX D
    POP H
    JZ L_539E
    CPI $1A
    JZ L_539E
    RST 2
    JZ L_539E
    PUSH PSW
    CC L_540A
    POP PSW
    JC L_5370
    CPI $3C
    STC
    JZ L_539E
    CPI $3D
    CZ L_5310
    JMP L_5370

L_539E:
    PUSH PSW
    LDA D_F62B
    RRC
    CNC L_531A
    POP PSW
    JNC DISC
    LDA D_F65B
    CPI $4D
    STC
    RNZ
    PUSH H
    LXI H,$F65C
    ANA A
    CALL SETSER
    MVI A,$04
    CALL L_5316
    POP H
    CALL L_52E4
    RC

L_53C3:
    CALL L_5673
    CALL L_5406
    RZ
    CPI $3E
    RZ
    CPI $3D
    JZ L_53E7
    CPI $5E
    JZ L_53FD
    CPI $3F
    JZ L_53ED
    CPI $21
    CZ L_5406
    RZ

L_53E2:
    CALL SD232C
    XRA A
    INR A

L_53E7:
    CZ L_5310
    JMP L_53C3

L_53ED:
    CALL L_5406
    RZ

L_53F1:
    CALL RV232C
    RC
    RST 4
    CMP M
    JNZ L_53F1
    JMP L_53C3

L_53FD:
    CALL L_5406
    RZ
    ANI $1F
    JMP L_53E2

L_5406:
    INX H
    MOV A,M
    ANA A
    RET

L_540A:
    RST 4
    DI
    ANI $0F
    MOV C,A
    JNZ L_5414
    MVI C,$0A

L_5414:
    LDA D_F62B
    RRC
    LXI D,D_161C
    JNC L_5421
    LXI D,$2440

L_5421:
    CALL L_52C1

L_5424:
    CALL L_5326
    DCR E
    JNZ L_5424
    CALL L_52B4

L_542E:
    CALL L_5326
    DCR D
    JNZ L_542E
    DCR C
    JNZ L_5414
    EI
    LDA D_F62B
    ANI $01
    INR A
    JMP L_5316

D_5443:
    .byte $50, $72, $65, $F6, $44, $6F, $77, $EE, $20, $55, $F0, $80, $80, $80, $80, $42
    .byte $79, $E5

L_5455:
    LXI H,$F65A
    RST 2
    CNC L_3457
    PUSH PSW
    CALL SETSER
    POP PSW
    CMC
    CC L_52E4
    JC L_5739

L_5468:
    MVI A,$40
    STA D_F650
    STA D_F67B
    XRA A
    STA D_FAC2
    STA D_FAC3
    CALL L_45D3
    LXI H,D_5443
    CALL STFNK
    CALL L_5544
    CALL L_5556
    CALL L_5562
    CALL DSPFNK
    CALL CURSON

L_548F:
    CALL L_5D5D
    LXI H,L_54EF
    SHLD D_F652
    LDA D_FF42
    ANA A
    JZ L_54AA
    LDA D_FF40
    LXI H,$F7D9
    XRA M
    RRC
    CC L_5562

L_54AA:
    CALL CHSNS
    JZ L_54C6
    CALL CHGET
    JC L_54FC
    MOV B,A
    LDA D_F658
    ANA A
    MOV A,B
    CZ LCD
    ANA A
    CNZ SD232C
    JC L_54E2

L_54C6:
    CALL RCVX
    JZ L_548F

.if MODEL = 100
    CALL RV232C
.else
    CALL L_7315
.endif

    JC L_548F
    RST 4
    MOV B,A
    LDA D_F659
    ANA A
    MOV A,B
    CNZ PRTTAB
    CALL L_56C5
    JMP L_548F

L_54E2:
    XRA A
    STA D_FF40

L_54E6:
    CALL L_729F
    JC L_54E6
    JMP L_548F

L_54EF:
    CALL ST_BEEP
    XRA A
    STA D_F659
    CALL L_5556
    JMP L_548F

L_54FC:
    MOV E,A
    MVI D,$FF
    LXI H,L_551D
    DAD D
    DAD D
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    LXI D,L_548F
    PUSH D
    PCHL

TRMFNK:
    .word L_5523                        ; F1
    .word L_567E                        ; F2
    .word L_559D                        ; F3
    .word L_553E                        ; F4
    .word L_5550                        ; F5
    .word L_551D                        ; F6
    .word L_5520                        ; F7
    .word L_571E                        ; F8

L_551D:
    RST 7
    .byte $32                           ; the hook's number
    RET

L_5520:
    RST 7
    .byte $34                           ; the hook's number
    RET

L_5523:
    CALL L_43A2
    CALL CUROFF
    CALL L_461F

L_552C:
    CALL CHSNS
    JZ L_552C
    CALL CHGET
    CALL L_4601
    CALL CURSON
    JMP L_4262

L_553E:
    LXI H,$F658
    MOV A,M
    CMA
    MOV M,A

L_5544:
    LDA D_F658
    LXI D,$F7B9
    LXI H,D_5583
    JMP L_556B

L_5550:
    LXI H,$F659
    MOV A,M
    CMA
    MOV M,A

L_5556:
    LDA D_F659
    LXI D,$F7C9
    LXI H,D_558B
    JMP L_556B

L_5562:
    LDA D_FF40
    LXI D,$F7D9
    LXI H,D_5595

L_556B:
    ANA A
    LXI B,$0004
    JNZ L_5573
    DAD B

L_5573:
    MOV B,C
    CALL L_2542
    MVI B,$0C
    XRA A

L_557A:
    STAX D
    INX D
    DCR B
    JNZ L_557A
    JMP FNKSB

D_5583:
    .byte "FullHalf"

D_558B:
    .byte "Echo    "

D_5593:
    .byte $0D, $20

D_5595:
    .byte "Wait ", $00, $20, $20

L_559D:
    LXI H,D_56EF
    SHLD D_F652
    PUSH H
    LDA D_FAC2
    ANA A
    RNZ
    CALL L_2146
    LXI H,D_5751
    CALL L_5791
    CALL L_463E
    RST 2
    ANA A
    RZ
    STA D_FAC6
    CALL L_21FA
    CALL L_4C0B
    RNZ
    CALL L_208F
    LXI H,D_577C
    JZ L_5791
    XCHG
    XTHL
    PUSH H
    LXI H,D_670C
    CALL L_5791
    CALL INLIN
    RC
    RST 2
    ANA A
    MVI A,$01
    STA D_FAC3
    STA D_F920
    JZ L_55FD
    CALL GETBYT
    CPI $0A
    RC
    CPI $85
    RNC
    LXI H,$F894
    SHLD D_F892
    STA D_F922
    STA D_FAC3
    POP PSW
    POP D
    .byte $01

L_55FD:
    .byte $F1, $E1
    PUSH D
    PUSH H
    CALL FNKSB
    POP H
    POP D

L_5606:
    LDA D_FAC3
    DCR A
    JZ L_562D
    PUSH D
    XCHG
    LHLD D_F892
    XCHG
    RST 3
    POP D
    JNZ L_562D
    CALL L_67DF
    MOV A,D
    ANA E
    INR A
    JNZ L_562A
    LHLD D_F892
    MVI M,$1A
    INX H
    SHLD D_F892

L_562A:
    LXI H,$F894

L_562D:
    MOV A,M
    CPI $1A
    RST 7
    .byte $36                           ; the hook's number
    JZ L_566C
    CPI $0A
    JNZ L_5646
    LDA D_F65A
    ANA A
    JNZ L_5646
    LDA D_FAC6
    CPI $0D

L_5646:
    MOV A,M
    STA D_FAC6
    JZ L_5653
    CALL SD232C
    CALL L_5673

L_5653:
    INX H
    CALL CHSNS
    JZ L_5606
    CALL CHGET
    CPI $03
    JZ L_566C
    CPI $13
    CZ CHGET
    CPI $03
    JNZ L_5606

L_566C:
    XRA A
    STA D_FAC3
    JMP FNKSB

L_5673:
    CALL RCVX
    RZ
    CALL RV232C
    RST 4
    JMP L_5673

L_567E:
    CALL L_2146
    LDA D_FAC2
    XRI $FF
    STA D_FAC2
    JZ L_56BF
    LXI H,$56E2
    SHLD D_F652
    PUSH H
    LXI H,D_5760
    CALL L_5791
    CALL L_463E
    RST 2
    ANA A
    RZ
    STA D_FAC6
    POP PSW

L_56A3:
    PUSH H
    CALL L_2206
    JC L_56B7
    SHLD D_FAC4
    CALL L_6B2D
    POP PSW
    CALL L_634A
    JMP FNKSB

L_56B7:
    XCHG
    CALL L_1FBF
    POP H
    JMP L_56A3

L_56BF:
    CALL FNKSB
    JMP L_6383

L_56C5:
    MOV C,A
    LDA D_FAC2
    ANA A
    MOV A,C
    RZ
    CALL L_56FE
    RZ
    JNC L_56D8
    CALL L_56D8
    MVI A,$0A

L_56D8:
    LHLD D_FAC4
    CALL L_6396
    SHLD D_FAC4
    RNC
    XRA A
    STA D_FAC2
    CALL FNKSB
    LXI H,D_5768
    JMP L_56F2

D_56EF:
    .byte $21, $59, $57

L_56F2:
    CALL L_5791
    LXI H,D_5771
    CALL STROUT
    JMP L_548F

L_56FE:
    MOV C,A
    ANA A
    RZ
    CPI $1A
    RZ
    CPI $7F
    RZ
    CPI $0A
    JNZ L_5711
    LDA D_FAC6
    CPI $0D

L_5711:
    MOV A,C
    STA D_FAC6
    RZ
    CPI $0D
    STC
    CMC
    RNZ
    ANA A
    STC
    RET

L_571E:
    LXI H,D_5786
    CALL L_5791
    CALL L_463E
    RST 2
    CALL MAKUPS
    CPI $59
    JZ L_5739
    LXI H,D_5771
    CALL L_5791
    JMP L_548F

L_5739:
    XRA A
    STA D_F650
    MOV L,A
    MOV H,A
    SHLD D_FAC2
    CALL CLSCOM
    CALL CUROFF
    CALL DISC
    CALL L_6370
    JMP TELCOM

D_5751:
    .byte "File to Upload", $00

D_5760:
    .byte "File to "

D_5768:
    .byte "Download", $00

D_5771:
    .byte " aborted", $0D, $0A, $00

D_577C:
    .byte "No file", $0D, $0A, $00

D_5786:
    .byte "Disconnect", $00

L_5791:
    CALL L_4BB8
    JMP STROUT
