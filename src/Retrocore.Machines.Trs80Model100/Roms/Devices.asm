;; MODEL 100 ROM: THE KEYBOARD QUEUE, POWER, THE CASSETTE'S MOTOR AND BYTES, AND THE DEVICES' DRIVERS
;;
;; Runs at $12CB-$19AA. Model100.asm describes the ROM as a whole and how it is named.

CHGET:
    PUSH H
    PUSH D
    PUSH B
    CALL L_12D4
    JMP L_14EE

L_12D4:
    RST 7
    .byte $04                           ; the hook's offset in the table at $FADA
    LHLD D_F62C
    INR H
    DCR H
    JZ L_1300
    MOV B,M
    MOV A,B
    ORA A
    JZ L_12EA
    INX H
    MOV A,M
    ORA A
    JNZ L_12EB

L_12EA:
    MOV H,A

L_12EB:
    SHLD D_F62C
    MOV A,B
    RET

L_12F0:
    LDA D_F650
    ADD A
    RC
    LXI H,$0000
    SHLD D_F62E
    MVI A,$0D
    STA D_FAA1

L_1300:
    LHLD D_F62E
    MOV A,L
    ANA H
    INR A
    JZ L_133D
    PUSH H
    LDA D_FAA1
    CPI $0D
    CZ L_2146
    LHLD D_F9A5
    POP D
    DAD D
    MOV A,M
    STA D_FAA1
    MOV B,A
    CPI $1A
    MVI A,$00
    JZ L_1336
    CALL KEYX
    JC L_1336
    INX H
    MOV A,M
    XCHG
    INX H
    SHLD D_F62E
    CPI $1A
    MOV A,B
    STC
    CMC
    RNZ

L_1336:
    LXI H,$FFFF
    SHLD D_F62E
    RET

L_133D:
    CALL CHSNS
    JNZ L_1358
    CALL L_13C2
    MVI A,$FF
    STA D_F656

L_134B:
    CALL CHSNS
    JZ L_134B
    XRA A
    STA D_F656
    CALL L_13D0

L_1358:
    LXI H,$F932
    MOV A,M
    ANA A
    JNZ L_13B5
    CALL L_1BB1
    CALL KYREAD
    RNC
    SUI $0B
    JZ L_12F0
    JNC L_13C0
    INR A
    JZ L_139F
    INR A
    JZ PRTLCD
    INR A
    JZ L_13A5
    MOV E,A
    LDA D_F650
    ADD A
    ADD A
    MOV A,E
    RC
    MVI D,$FF
    XCHG
    DAD H
    DAD H
    DAD H
    DAD H
    LXI D,$F809
    DAD D
    LDA D_F650
    ANA A
    JP L_1399
    INX H
    INX H
    INX H
    INX H

L_1399:
    SHLD D_F62C
    JMP L_12D4

L_139F:
    LHLD D_F88A
    JMP L_1399

L_13A5:
    LDA D_FAAD
    ANA A
    RZ
    LDA D_F63D
    XRI $FF

L_13AF:
    JZ ERAFNK
    JMP DSPFNK

L_13B5:
    DI
    MVI M,$00
    LDA D_F657
    DCX H
    MOV M,A
    CALL L_143F

L_13C0:
    XRA A
    RET

L_13C2:
    LDA D_F63F
    STA D_FACB
    ANA A
    RNZ
    CALL CURSON
    JMP L_4262

L_13D0:
    LDA D_FACB
    ANA A
    RNZ
    CALL CUROFF
    JMP L_4262

CHSNS:
    LDA D_F62D
    ANA A
    RNZ
    LDA D_F932
    ANA A
    RNZ
    PUSH H
    LHLD D_F62E
    MOV A,L
    ANA H
    INR A
    POP H
    RNZ
    RST 7
    .byte $06                           ; the hook's offset in the table at $FADA
    JMP KEYX

L_13F3:
    CALL BRKCHK
    RZ
    CPI $03
    JZ L_1412
    CPI $13
    RNZ
    CALL L_13C2

L_1402:
    CALL BRKCHK
    CPI $13
    JZ L_13D0
    CPI $03
    JNZ L_1402
    CALL L_13D0

L_1412:
    XRA A
    STA D_FFAA
    JMP ST_STOP

ST_POWER:
    SUI $A4
    JZ L_1459
    CPI $27
    JNZ L_1461
    RST 2
    JZ L_1451
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $95                           ; SYNCHR: the RESUME token
    JNZ SNERR
    JMP L_143F

L_1431:
    PUSH PSW
    LDA D_F656
    ANA A
    MVI A,$01
    STA D_F656
    JNZ L_1451
    POP PSW

L_143F:
    DI
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    LXI H,$0000
    DAD SP
    SHLD D_FABE
    LXI H,$9C0B
    SHLD D_F5F2

L_1451:
    DI
    IN $BA
    ORI $10
    OUT $BA
    HLT

L_1459:
    CALL L_1469
    STA D_F932
    RST 2
    RET

L_1461:
    CALL GETBYT
    CPI $0A
    JC FCERR

L_1469:
    STA D_F657
    STA D_F931
    RET

PNOTAB:
    RST 7
    .byte $0A                           ; the hook's offset in the table at $FADA
    CALL PRINTR
    JNC L_147F
    XRA A
    STA D_FACD
    JMP L_1494

L_147F:
    PUSH PSW
    MVI A,$FF
    STA D_FACD
    CALL L_1BB1
    POP PSW
    RET

L_148A:
    CALL CTON
    CALL SYNCR
    RNC

L_1491:
    CALL CTOFF

L_1494:
    MVI E,$12
    JMP ERROR

L_1499:
    CALL CTON
    LXI B,$0000

L_149F:
    DCX B
    MOV A,B
    ORA C
    JNZ L_149F
    JMP SYNCW

CTON:
    DI
    .byte $11                           ; LXI D,$1EFB: skips the next two bytes

CTOFF:
    EI
    MVI E,$00
    JMP L_7043

CASIN:
    PUSH D
    PUSH H
    PUSH B
    CALL DATAR
    JC L_1491
    MOV A,D
    POP B
    ADD C
    MOV C,A
    MOV A,D
    POP H
    POP D
    RET

CSOUT:
    PUSH D
    PUSH H
    MOV D,A
    ADD C
    MOV C,A
    PUSH B
    MOV A,D
    CALL DATAW
    JC L_1491
    POP B
    POP H
    POP D
    RET

LCDDEV:
    .word L_14D8                        ; the driver's routine 0
    .word L_4D59                        ; the driver's routine 1
    .word L_14E5                        ; the driver's routine 2

L_14D8:
    MVI A,$02
    CMP E
    JNZ NMERR

L_14DE:
    SHLD D_FC8C
    MOV M,E
    POP PSW
    POP H
    RET

L_14E5:
    POP PSW
    PUSH PSW
    CALL L_431F

L_14EA:
    CALL L_1BB1

L_14ED:
    POP PSW

L_14EE:
    POP B
    POP D
    POP H
    RET

CRTDEV:
    .word L_14F8                        ; the driver's routine 0
    .word L_4D59                        ; the driver's routine 1
    .word L_14FA                        ; the driver's routine 2

L_14F8:
    RST 7
    .byte $40                           ; the hook's offset in the table at $FADA

L_14FA:
    RST 7
    .byte $44                           ; the hook's offset in the table at $FADA

RAMDEV:
    .word L_1506                        ; the driver's routine 0
    .word L_158D                        ; the driver's routine 1
    .word L_15AC                        ; the driver's routine 2
    .word L_15C4                        ; the driver's routine 3
    .word L_161B                        ; the driver's routine 4

L_1506:
    PUSH H
    PUSH D
    INX H
    INX H
    PUSH H
    MOV A,E
    CPI $01
    JZ L_1541
    CPI $08
    JZ L_155C

L_1516:
    CALL MAKTXT
    JC L_1580
    PUSH D
    CALL L_18DA
    POP D

L_1521:
    LXI B,$0000

L_1524:
    POP H
    LDAX D
    ANI $02
    JNZ AOERR
    LDAX D
    ORI $02
    STAX D
    INX D
    MOV M,E
    INX H
    MOV M,D
    INX H
    INX H
    INX H
    MVI M,$00
    INX H
    MOV M,C
    INX H
    MOV M,B
    POP D
    POP H
    JMP L_14DE

L_1541:
    LDA D_F651
    ANA A
    LXI H,$F9AF
    CZ L_208F
    JZ FFERR
    XCHG
    CALL L_1675
    XRA A
    MOV M,A
    MOV L,A
    MOV H,A
    SHLD D_FAD8
    JMP L_1521

L_155C:
    POP H
    POP D
    MVI E,$02
    PUSH D
    PUSH H
    CALL L_2146
    CALL L_208F
    JZ L_1516
    MOV E,L
    MOV D,H
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    LXI B,$FFFF

L_1575:
    MOV A,M
    INX H
    INX B
    CPI $1A
    JNZ L_1575
    JMP L_1524

L_1580:
    LDAX D
    ANI $02
    JNZ AOERR
    XCHG
    CALL L_1FBF
    JMP L_1516

L_158D:
    PUSH H
    CALL L_15A0
    POP H
    CALL L_172A
    CNZ L_1621
    CALL L_1675
    MVI M,$00
    JMP L_4D59

L_15A0:
    INX H
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    DCX H
    MOV A,M
    ANI $FD
    MOV M,A
    RET

L_15AC:
    POP PSW
    PUSH PSW
    LXI B,L_14EA
    PUSH B
    ANA A
    RZ
    CPI $1A
    RZ
    CPI $7F
    RZ
    CALL L_1739
    RNZ
    LXI B,$0100
    JMP L_1621

L_15C4:
    XCHG
    CALL L_1675
    CALL L_18C7
    XCHG
    CALL L_1749
    JNZ L_1609
    XCHG
    LHLD D_FC87
    RST 3
    PUSH PSW
    PUSH D
    CNZ L_2146
    POP H
    POP PSW
    LXI B,$FFF9
    DAD B
    MOV E,M
    INX H
    MOV D,M
    XCHG
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    JNZ L_15F5
    PUSH D
    XCHG
    LHLD D_FAD8
    XCHG
    DAD D
    POP D

L_15F5:
    XCHG
    INX H
    INX H
    INX H
    INX H
    MOV C,M
    INX H
    MOV B,M
    INR M
    INX H
    XCHG
    DAD B
    MVI B,$00
    CALL L_2542
    XCHG
    DCR H
    XRA A

L_1609:
    MOV C,A
    DAD B
    MOV A,M
    CPI $1A
    STC
    CMC
    JNZ L_4E8A
    CALL L_1675
    MOV M,A
    STC
    JMP L_4E8A

L_161B:
    CALL L_1675
    JMP L_17CD

L_1621:
    PUSH H
    PUSH B
    PUSH H
    XCHG
    LHLD D_FC87
    RST 3
    CNZ L_2146
    POP H
    DCX H
    MOV D,M
    DCX H
    MOV E,M
    XCHG
    POP B
    PUSH B
    PUSH H
    DAD B
    XCHG
    MOV M,E
    INX H
    MOV M,D
    LXI B,$FFFA
    DAD B
    MOV E,M
    INX H
    MOV D,M
    LDAX D
    MOV L,A
    INX D
    LDAX D
    MOV H,A
    POP B
    DAD B
    POP B
    PUSH H
    PUSH B
    CALL MAKHOL
    CNC L_18DD
    POP B
    POP D
    POP H
    JC L_1669
    PUSH H

L_1658:
    MOV A,M
    STAX D
    INX D
    INX H
    DCR C
    JNZ L_1658
    POP D
    LHLD D_FC87
    RST 3
    RZ
    JMP L_2146

L_1669:
    LXI B,$FFF7
    DAD B
    MVI M,$00
    CALL L_15A0
    JMP L_3F17

L_1675:
    PUSH D
    LHLD D_FAA2
    LXI D,$FA91
    DAD D
    POP D
    RET

CASDEV:
    .word L_1689                        ; the driver's routine 0
    .word L_16AD                        ; the driver's routine 1
    .word L_16C7                        ; the driver's routine 2
    .word L_16D2                        ; the driver's routine 3
    .word L_1710                        ; the driver's routine 4

L_1689:
    PUSH H
    PUSH D
    LXI B,$0006
    DAD B
    XRA A
    MOV M,A
    STA D_FA8E
    MOV A,E
    CPI $08
    JZ NMERR
    CPI $01
    JZ L_16A7
    CALL L_260E

L_16A2:
    POP D
    POP H
    JMP L_14DE

L_16A7:
    CALL L_2653
    JMP L_16A2

L_16AD:
    CALL L_172A
    JZ L_16C0
    PUSH H
    DAD B

L_16B5:
    MVI M,$1A
    INX H
    INR C
    JNZ L_16B5
    POP H
    CALL L_1716

L_16C0:
    XRA A
    STA D_FA8E
    JMP L_4D59

L_16C7:
    POP PSW
    PUSH PSW
    CALL L_1739
    CZ L_1716
    JMP L_14EA

L_16D2:
    XCHG
    LXI H,$FA8E
    CALL L_18C7
    XCHG
    CALL L_1749
    JNZ L_16FF
    PUSH H
    CALL L_26D1
    POP H
    LXI B,$0000

L_16E8:
    CALL CASIN
    MOV M,A
    INX H
    DCR B
    JNZ L_16E8
    CALL CASIN
    MOV A,C
    ANA A
    JNZ L_1491
    CALL CTOFF
    DCR H
    XRA A
    MOV B,A

L_16FF:
    MOV C,A
    DAD B
    MOV A,M
    CPI $1A
    STC
    CMC
    JNZ L_4E8A
    STA D_FA8E
    STC
    JMP L_4E8A

L_1710:
    LXI H,$FA8E
    JMP L_17CD

L_1716:
    PUSH H
    CALL L_2648
    POP H
    LXI B,$0000

L_171E:
    MOV A,M
    CALL CSOUT
    INX H
    DCR B
    JNZ L_171E
    JMP L_2635

L_172A:
    MOV A,M
    CPI $01
    RZ
    LXI B,$0006
    DAD B
    MOV A,M
    MOV C,A
    MVI M,$00
    JMP L_174F

L_1739:
    MOV E,A
    LXI B,$0006
    DAD B
    MOV A,M
    INR M
    INX H
    INX H
    INX H
    PUSH H
    MOV C,A
    DAD B
    MOV M,E
    POP H
    RET

L_1749:
    LXI B,$0006
    DAD B
    MOV A,M
    INR M

L_174F:
    INX H
    INX H
    INX H
    ANA A
    RET

LPTDEV:
    .word L_14D8                        ; the driver's routine 0
    .word L_4D59                        ; the driver's routine 1
    .word L_175A                        ; the driver's routine 2

L_175A:
    POP PSW
    PUSH PSW
    CALL PRTTAB
    JMP L_14EA

COMDEV:
    .word L_176D                        ; the driver's routine 0
    .word L_179E                        ; the driver's routine 1
    .word L_17A8                        ; the driver's routine 2
    .word L_17B0                        ; the driver's routine 3
    .word L_17CA                        ; the driver's routine 4

L_176C:
    .byte $F6                           ; ORI $37: skips the next byte

L_176D:
    STC
    PUSH PSW
    CC DISC
    POP PSW
    PUSH PSW
    PUSH H
    PUSH D
    LXI H,FILNAM
    CALL SETSER
    POP D
    MOV A,E
    CPI $08
    JZ NMERR
    SUI $01
    JNZ L_178B
    STA D_FA8F

L_178B:
    POP H
    POP PSW
    JC L_14DE
    CALL L_52E4
    JC L_1494
    MVI A,$02
    CALL L_5316
    JMP L_14DE

L_179E:
    CALL CLSCOM
    XRA A
    STA D_FA8F
    JMP L_4D59

L_17A8:
    POP PSW
    PUSH PSW
    CALL SD232C
    JMP L_14EA

L_17B0:
    LXI H,$FA8F
    CALL L_18C7
    CALL RV232C
    JC L_1494
    CPI $1A
    STC
    CMC
    JNZ L_4E8A
    STA D_FA8F
    STC
    JMP L_4E8A

L_17CA:
    LXI H,$FA8F

L_17CD:
    MOV M,C
    JMP NOSKCR

MDMDEV:
    .word L_176C                        ; the driver's routine 0
    .word L_17DB                        ; the driver's routine 1
    .word L_17A8                        ; the driver's routine 2
    .word L_17B0                        ; the driver's routine 3
    .word L_17CA                        ; the driver's routine 4

L_17DB:
    MVI A,$02
    CALL L_5316
    CALL DISC
    JMP L_179E

SETSER:
    PUSH PSW
    LXI B,NMERR
    PUSH B
    JNC L_17F7
    MOV A,M
    SUI $31
    CPI $09
    RNC
    INR A
    MOV D,A
    INX H

L_17F7:
    MOV A,M
    SUI $36
    CPI $03
    RNC
    INR A
    ADD A
    ADD A
    ADD A
    MOV E,A
    INX H
    CALL MAKUPL
    CPI $49
    JNZ L_181C
    MOV A,E
    CPI $18
    RZ
    ADI $0C
    MOV E,A
    ANI $08
    ADD A
    ADD A
    ADD A
    ORI $3F
    JMP L_1832

L_181C:
    CPI $45
    MVI B,$02
    JZ L_182D
    SUI $4E
    MVI B,$04
    JZ L_182D
    DCR A
    RNZ
    MOV B,A

L_182D:
    MOV A,B
    ORA E
    MOV E,A
    MVI A,$FF

L_1832:
    STA D_FF8D
    INX H
    MOV A,M
    SUI $31
    CPI $02
    RNC
    ORA E
    MOV E,A
    INX H
    CALL MAKUPL
    CPI $44
    JZ L_184E
    CPI $45
    RNZ
    CALL L_6F31
    STC

L_184E:
    CNC L_6F32
    POP B
    POP PSW
    PUSH PSW
    PUSH D
    DCX H
    DCX H
    DCX H
    DCX H
    LXI D,$F65B
    MVI B,$05
    MOV A,M
    JC L_1864
    MVI A,$4D

L_1864:
    STAX D
    INX H
    INX D
    CALL MAKUPL
    DCR B
    JNZ L_1864
    XCHG
    POP H
    POP PSW
    PUSH D
    CALL INZCOM
    POP H
    RET

WNDDEV:
    .word L_1881                        ; the driver's routine 0
    .word L_1883                        ; the driver's routine 1
    .word FCERR                         ; the driver's routine 2
    .word L_1885                        ; the driver's routine 3
    .word L_1887                        ; the driver's routine 4

L_1881:
    RST 7
    .byte $46                           ; the hook's offset in the table at $FADA

L_1883:
    RST 7
    .byte $48                           ; the hook's offset in the table at $FADA

L_1885:
    RST 7
    .byte $4A                           ; the hook's offset in the table at $FADA

L_1887:
    RST 7
    .byte $4C                           ; the hook's offset in the table at $FADA

FN_EOF:
    RST 7
    .byte $26                           ; the hook's offset in the table at $FADA
    CALL L_4C81
    JZ CFERR
    CPI $01
    JNZ NMERR
    PUSH H
    CALL L_18BF
    MOV C,A
    SBB A
    CALL L_340A
    POP H
    INX H
    INX H
    INX H
    INX H
    MOV A,M
    LXI H,$FA8F
    CPI $FC
    JZ L_18BD
    CPI $F9
    JZ L_18BD
    CALL L_1675
    CPI $F8
    JZ L_18BD
    LXI H,$FA8E

L_18BD:
    MOV M,C
    RET

L_18BF:
    PUSH B
    PUSH H
    PUSH D
    MVI A,$06
    JMP L_5123

L_18C7:
    MOV A,M
    MVI M,$00
    ANA A
    RZ
    INX SP
    INX SP
    CPI $1A
    STC
    CMC
    JNZ L_4E8A
    MOV M,A
    STC
    JMP L_4E8A

L_18DA:
    LXI B,$0001

L_18DD:
    LHLD SAVSTK

L_18E0:
    MOV A,M
    ANA A
    RZ
    XCHG
    LHLD STKTOP
    XCHG
    RST 3
    RNC
    MOV A,M
    CPI $81
    LXI D,$0007
    JNZ L_1900
    INX H
    MOV E,M
    INX H
    MOV D,M
    XCHG
    DAD B
    XCHG
    MOV M,D
    DCX H
    MOV M,E
    LXI D,$0018

L_1900:
    DAD D
    JMP L_18E0

L_1904:
    RST 2
    PUSH H
    CALL L_198D
    CALL TIME
    JMP PUTNEW

TIME:
    CALL L_19A0
    LXI D,$F928
    CALL L_1996
    MVI M,$3A
    INX H
    CALL L_1996
    MVI M,$3A

L_1920:
    INX H
    JMP L_1996

L_1924:
    RST 2
    PUSH H
    CALL L_198D
    CALL DATE
    JMP PUTNEW

DATE:
    CALL L_19A0
    LXI D,$F92C
    LDAX D
    CPI $0A
    MVI B,$30
    JC L_1941
    MVI B,$31
    SUI $0A

L_1941:
    MOV M,B
    INX H
    CALL L_199A
    DCX D
    MVI M,$2F
    INX H
    CALL L_1996
    MVI M,$2F
    LXI D,$F92E
    JMP L_1920

L_1955:
    RST 2
    PUSH H
    MVI A,$03
    CALL L_198F
    CALL DAY
    JMP PUTNEW

DAY:
    CALL L_19A0
    LDA D_F92B
    MOV C,A
    ADD A
    ADD C
    MOV C,A
    MVI B,$00
    XCHG
    LXI H,D_1978
    DAD B
    MVI B,$03
    JMP L_2542

D_1978:
    .byte "SunMonTueWedThuF"
    .byte "riSat"

L_198D:
    MVI A,$08

L_198F:
    CALL STRINI
    LHLD DSCPTR
    RET

L_1996:
    CALL L_1999

L_1999:
    LDAX D

L_199A:
    ORI $30
    MOV M,A
    DCX D
    INX H
    RET

L_19A0:
    PUSH H
    LXI H,$F923
    DI
    CALL L_7329
    EI
    POP H
    RET
