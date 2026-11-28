;; MODEL 100 ROM: TEXT
;;
;; Runs at $5DEE-$6B60. Model100.asm describes the ROM as a whole and how it is named.

TEXT:
    LXI H,$5DFB
    SHLD D_F652
    LXI H,D_5E22
    CALL STFNK
    XRA A
    CNZ ST_BEEP
    CALL L_5D53
    LXI H,D_5E15
    CALL STROUT
    CALL L_463E
    RST 2
    ANA A
    JZ MENU
    CALL L_2206
    JMP L_5F65

D_5E15:
    .byte "File to edit", $00

D_5E22:
    .byte $80, $80, $80, $80, $80, $80, $80, $83

D_5E2A:
    .byte "Find", $8E, "Load", $96, "Save", $87, $80
    .byte "Copy", $8F, "Cut ", $95, "Sel ", $8C, $4D
    .byte $65, $6E, $75, $1B, $9B

D_5E4F:
    .byte $19, $00

ST_EDIT:
    PUSH H
    PUSH PSW
    MVI A,$01
    JZ L_5E5A
    MVI A,$FF

L_5E5A:
    STA D_F651
    XRA A
    STA D_FC95
    LXI H,$2020
    SHLD D_FC99
    LXI H,$5EDA
    SHLD D_F652
    LXI D,$F802
    LXI H,D_5F48
    CALL L_4D12
    LXI H,L_5ED5
    SHLD D_F652
    POP PSW
    POP H
    PUSH H
    JMP ST_LIST

L_5E82:
    CALL L_4F45
    CALL L_212D
    LDA D_F63D
    STA D_FACC
    LXI H,$0000
    SHLD D_F6E7
    CALL L_2146
    CALL L_4009
    LHLD D_F9B0
    MOV A,M
    CPI $1A
    JZ L_5EBD
    PUSH H
    XRA A
    LXI H,L_5EAB
    JMP L_5F71

L_5EAB:
    XRA A
    LXI H,D_5EEB
    SHLD D_F652
    LXI H,D_5F48
    MVI D,$F8
    JMP L_4D9E

L_5EBA:
    CALL CLS

L_5EBD:
    XRA A
    STA D_F651
    MOV L,A
    MOV H,A
    SHLD D_F652
    CALL L_1FF8
    CALL L_3F6D
    LDA D_FACC
    STA D_F63D
    JMP L_6C5B

L_5ED5:
    PUSH D
    CALL L_1FF8
    POP D
    PUSH D
    XRA A
    STA D_F651
    MOV L,A
    MOV H,A
    SHLD D_F652
    CALL L_4F45
    POP D
    JMP ERROR

D_5EEB:
    .byte $7B, $F5, $2A, $87, $FC, $2B, $46, $05, "+N+n", $AF, $67, $09, $01
    .byte $FF, $FF, $09, $DA, $03, $5F, $6F, $67, $22, $E7, $F6, $CD, $45, $4F, $F1, $FE
    .byte $07, $21, $B1, $60, $CA, $15, "_!8_", $CD, $31, $42, $CD, $B1, $27
    .byte $21, $60, $5F, $CD, $24, $5F, $C3, $94, $5E

L_5F24:
    PUSH H
    LXI H,D_5F49
    CALL STROUT
    POP H
    CALL STROUT

L_5F2F:
    CALL CHGET
    CPI $20
    JNZ L_5F2F
    RET

    .byte "Text ill-formed", $07

D_5F48:
    .byte $00

D_5F49:
    .byte $0D, $0A, "Press space ba"
    .byte "r for ", $00, "TEXT", $00

L_5F65:
    PUSH H
    LXI H,$0000
    SHLD D_F6E7
    MVI A,$01
    LXI H,MENU

L_5F71:
    STA D_F921
    SHLD D_F765
    CALL EXTREV
    CALL ERAFNK
    CALL LOCK
    CALL CUROFF
    CALL L_65B9
    LXI H,D_5E2A
    CALL STFNK
    LDA D_F651
    ANA A
    JZ L_5F9F
    LXI H,D_7845
    SHLD D_F7F9
    LXI H,$7469
    SHLD D_F7FB

L_5F9F:
    LXI H,D_5E4F
    SHLD D_F88A
    LDA D_F63C
    STA D_F922
    MVI A,$80
    STA D_F650
    XRA A
    MOV L,A
    MOV H,A
    STA D_F6DF
    STA D_F920
    STA D_F6E1
    STA D_F71F
    SHLD D_F6E2
    POP H
    SHLD D_F767
    PUSH H
    CALL L_6B2A
    CALL L_634A
    POP D
    LHLD D_F6E7
    DAD D
    CALL L_63CD
    PUSH H
    CALL L_6986
    POP H
    CALL L_630B

L_5FDD:
    CALL L_5D53
    LXI H,L_5FDD
    SHLD D_F652
    PUSH H
    LDA D_F6DF
    STA D_F6E0
    CALL L_63E5
    STA D_F6DF
    PUSH PSW
    CALL L_65EC
    POP PSW
    JC L_6501
    CPI $7F
    JZ L_6118
    CPI $20
    JNC L_608A
    MOV C,A
    MVI B,$00
    LXI H,TXTCTL
    DAD B
    DAD B
    MOV C,M
    INX H
    MOV H,M
    MOV L,C
    PUSH H
    LHLD CSRY

L_6015:
    RET

TXTCTL:
    .word L_6015                        ; ^@
    .word L_618C                        ; ^A
    .word L_61D7                        ; ^B
    .word L_628F                        ; ^C
    .word L_60DE                        ; ^D
    .word L_6155                        ; ^E
    .word L_617A                        ; ^F
    .word L_6713                        ; ^G
    .word L_610B                        ; ^H
    .word L_608A                        ; ^I
    .word L_6015                        ; ^J
    .word L_6015                        ; ^K
    .word L_6242                        ; ^L
    .word L_60BE                        ; ^M
    .word L_6551                        ; ^N
    .word L_6431                        ; ^O
    .word L_607C                        ; ^P
    .word L_620B                        ; ^Q
    .word L_61FD                        ; ^R
    .word L_6151                        ; ^S
    .word L_61C2                        ; ^T
    .word L_6445                        ; ^U
    .word L_6774                        ; ^V
    .word L_6210                        ; ^W
    .word L_60E2                        ; ^X
    .word L_6691                        ; ^Y
    .word L_621C                        ; ^Z
    .word L_6056                        ; ^[
    .word L_60DE                        ; ^\
    .word L_6151                        ; ^]
    .word L_6155                        ; ^^
    .word L_60E2                        ; ^_

L_6056:
    LDA D_F6E0
    SUI $1B
    RNZ
    MOV L,A
    MOV H,A
    SHLD D_F652
    RST 7
    .byte $38                           ; the hook's number
    CALL L_65B9
    CALL UNLOCK
    CALL ERAFNK
    CALL L_63DB
    CALL POSIT
    CALL CRLF
    CALL L_6383
    LHLD D_F765
    PCHL

L_607C:
    CALL L_63E5
    JC L_6501
    ANA A
    RZ
    CPI $1A
    RZ
    CPI $7F
    RZ

L_608A:
    PUSH PSW
    CALL L_628F
    CALL L_6A9B
    CALL L_6AF9
    POP PSW

L_6095:
    CALL L_6396
    JC L_60A3
    PUSH H
    CALL L_6253
    POP H
    JMP L_6146

L_60A3:
    CALL L_659B
    PUSH H
    LXI H,D_60B1
    CALL L_65AE

L_60AD:
    POP H
    JMP POSIT

D_60B1:
    .byte "Memory full", $07, $00

L_60BE:
    CALL L_628F
    CALL L_6A9B
    LHLD D_FB62
    INX H
    MOV A,M
    INX H
    ORA M
    JNZ L_60A3
    CALL L_6253
    CALL L_6AF9
    MVI A,$0D
    CALL L_6396
    MVI A,$0A
    JMP L_6095

L_60DE:
    CALL L_60E8
    STC

L_60E2:
    CNC L_60F5
    JMP L_62A0

L_60E8:
    LHLD CSRY
    LDA D_F63C
    INR H
    CMP H
    JNC L_6175
    MVI H,$01

L_60F5:
    INR L
    MOV A,L
    PUSH H
    CALL L_6A48
    MOV A,E
    ANA D
    INR A
    POP H
    STC
    RZ
    CALL L_63CD
    CMP L
    CC L_6311
    JMP L_6175

L_610B:
    CALL L_628F
    CALL L_6AF9
    CALL L_630B
    CALL L_615B
    RC

L_6118:
    CALL L_628F
    CALL L_6AF9
    PUSH H
    CALL L_630B
    POP H
    MOV A,M
    CPI $1A
    RZ
    PUSH PSW
    PUSH H
    PUSH H
    CALL L_6A9B
    POP H

L_612E:
    CALL L_63B6
    CALL L_6256
    POP H
    POP PSW
    CPI $0D
    JNZ L_6146
    MOV A,M
    CPI $0A
    JNZ L_6146
    PUSH PSW
    PUSH H
    JMP L_612E

L_6146:
    PUSH H
    LDA CSRY
    CALL L_699E
    POP H
    JMP L_62F6

L_6151:
    CALL L_615B
    STC

L_6155:
    CNC L_6166
    JMP L_62A0

L_615B:
    LHLD CSRY
    DCR H
    JNZ L_6175
    LDA D_F63C
    MOV H,A

L_6166:
    PUSH H
    CALL L_6A45
    LHLD D_F767
    RST 3
    POP H
    CMC
    RC
    DCR L
    CZ L_631D

L_6175:
    CALL POSIT
    ANA A
    RET

L_617A:
    CALL L_6AF9

L_617D:
    CALL L_61A4
    JNZ L_617D

L_6183:
    CALL L_61A4
    JZ L_6183
    JMP L_619E

L_618C:
    CALL L_6AF9

L_618F:
    CALL L_61AF
    JZ L_618F

L_6195:
    CALL L_61AF
    JNZ L_6195
    CALL L_61A4

L_619E:
    CALL L_62F6
    JMP L_62A0

L_61A4:
    MOV A,M
    CPI $1A
    POP B
    JZ L_619E
    INX H
    JMP L_61BA

L_61AF:
    XCHG
    LHLD D_F767
    XCHG
    RST 3
    POP B
    JZ L_619E
    DCX H

L_61BA:
    PUSH B
    PUSH H
    MOV A,M
    CALL L_6965
    POP H
    RET

L_61C2:
    DCR L
    MVI L,$01
    JNZ L_61D1
    PUSH H
    CALL L_6A45
    XCHG
    CALL L_6230
    POP H

L_61D1:
    CALL POSIT
    JMP L_62A0

L_61D7:
    PUSH H
    INR L
    CALL L_63CD
    INR A
    CMP L
    JNZ L_61EC
    PUSH PSW
    CALL L_6A45
    XCHG
    MVI A,$01
    CALL L_6233
    POP PSW

L_61EC:
    DCR A
    CALL L_6A48
    MOV B,A
    INX D
    MOV A,D
    ORA E
    MOV A,B
    JZ L_61EC
    POP H
    MOV L,A
    JMP L_61D1

L_61FD:
    LDA D_F63C
    MOV H,A
    CALL POSIT
    CALL L_6AF9
    CALL L_6AA3
    .byte $01                           ; LXI B,$0126: skips the next two bytes

L_620B:
    MVI H,$01
    JMP L_61D1

L_6210:
    LHLD D_F767
    CALL L_6236
    CALL HOME
    JMP L_62A0

L_621C:
    LHLD D_FB62
    PUSH H
    CALL L_6A3E
    POP H
    RST 3
    PUSH H
    CNC L_6230

L_6229:
    POP H
    CALL L_630B
    JMP L_62A0

L_6230:
    CALL L_63CD

L_6233:
    CALL L_6B39

L_6236:
    CALL L_0013
    RZ
    SHLD D_F6EB
    MVI A,$01
    JMP L_69CB

L_6242:
    CALL L_628F
    CALL L_6AF9
    SHLD D_F6E2
    SHLD D_F6E4
    MOV E,L
    MOV D,H
    JMP L_62B3

L_6253:
    MVI C,$00
    .byte $21                           ; LXI H,$800E: skips the next two bytes

L_6256:
    MVI C,$80
    CALL L_63CD
    LXI H,CSRY
    SUB M
    MOV B,A
    CALL L_6A45
    INX H

L_6264:
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX D
    MOV A,D
    ORA E
    RZ
    DCR C
    JM L_6272
    DCX D
    DCX D

L_6272:
    DCX H
    MOV M,E
    INX H
    MOV M,D
    DCR B
    JP L_6264
    RET

L_627B:
    CALL HOME
    CALL DELLIN
    CALL L_63CD

L_6284:
    ADD A
    MOV B,A
    LXI D,$F6EB
    LXI H,$F6ED
    JMP L_2542

L_628F:
    CALL L_62EE
    PUSH H
    LXI H,$0000
    SHLD D_F6E2
    CALL L_6AF9
    POP D
    JMP L_62B0

L_62A0:
    CALL L_62EE
    CALL L_6AF9
    XCHG
    LHLD D_F6E4
    RST 3
    RZ
    XCHG
    SHLD D_F6E4

L_62B0:
    CALL L_64B2

L_62B3:
    PUSH H
    PUSH D
    CALL L_6A3E
    POP H
    RST 3
    JC L_62C0
    CALL L_63DB

L_62C0:
    CC L_6AA3
    MOV H,L
    XTHL
    CALL L_0013
    JNC L_62CD
    MVI L,$01

L_62CD:
    CNC L_6AA3
    POP PSW
    SUB L
    MOV C,A
    XCHG
    LHLD CSRY
    XCHG
    PUSH D
    MVI H,$01
    CALL POSIT
    CALL L_6A45
    MOV A,C

L_62E2:
    PUSH PSW
    CALL L_6A0D
    POP PSW
    DCR A
    JP L_62E2
    JMP L_60AD

L_62EE:
    LHLD D_F6E2
    MOV A,H
    ORA L
    RNZ
    POP H
    RET

L_62F6:
    CALL L_0013
    CC L_631E
    JC L_62F6

L_62FF:
    PUSH H
    CALL L_6A3E
    POP H
    RST 3
    CNC L_6312
    JNC L_62FF

L_630B:
    CALL L_6AA3
    JMP POSIT

L_6311:
    DCR L

L_6312:
    PUSH PSW
    PUSH H
    CALL L_627B
    CALL L_63CD
    JMP L_6344

L_631D:
    INR L

L_631E:
    PUSH PSW
    PUSH H
    CALL L_65DF
    CALL HOME
    CALL INSLIN
    CALL L_6A55
    PUSH D
    CALL L_6A3E
    INX H
    MOV E,L
    MOV D,H
    DCX H
    DCX H
    DCR A
    ADD A
    MOV C,A
    MVI B,$00
    CALL L_6BE6
    XCHG
    POP D
    MOV M,D
    DCX H
    MOV M,E
    MVI A,$01

L_6344:
    CALL L_69CB
    POP H
    POP PSW
    RET

L_634A:
    LHLD STREND
    LXI B,$00C8
    DAD B
    XRA A
    SUB L
    MOV L,A
    SBB A
    SUB H
    MOV H,A
    DAD SP
    RNC
    MOV A,H
    ORA L
    RZ
    MOV B,H
    MOV C,L
    LHLD D_FB62
    XCHG
    INX D
    CALL L_6B7F

L_6366:
    MVI M,$00
    INX H
    DCX B
    MOV A,B
    ORA C
    JNZ L_6366
    RET

L_6370:
    LHLD DOSTRT

L_6373:
    CALL L_6B2D
    INX H
    XCHG
    LHLD COSTRT
    XCHG
    RST 3
    RNC
    MOV A,M
    ANA A
    JNZ L_6373

L_6383:
    LHLD D_FB62
    PUSH H
    LXI B,$FFFF
    XRA A

L_638B:
    INX H
    INX B
    CMP M
    JZ L_638B
    POP H
    INX H
    JMP MASDEL

L_6396:
    XCHG
    LHLD D_FB62
    INX H
    INR M
    DCR M
    STC
    RNZ
    PUSH PSW
    SHLD D_FB62
    XCHG
    MOV A,E
    SUB L
    MOV C,A
    MOV A,D
    SBB H
    MOV B,A
    MOV L,E
    MOV H,D
    DCX H
    CALL L_6BE6
    INX H
    POP PSW
    MOV M,A
    INX H
    ANA A
    RET

L_63B6:
    XCHG
    LHLD D_FB62
    MOV A,L
    SUB E
    MOV C,A
    MOV A,H
    SBB D
    MOV B,A
    DCX H
    SHLD D_FB62
    MOV L,E
    MOV H,D
    INX H
    CALL L_6BDB
    XRA A
    STAX D
    RET

L_63CD:
    PUSH H
    PUSH PSW
    LXI H,$F63D
    LDA D_F63B
    ADD M
    MOV L,A
    POP PSW
    MOV A,L
    POP H
    RET

L_63DB:
    PUSH PSW
    LHLD D_F63B
    CALL L_63CD
    MOV L,A
    POP PSW
    RET

L_63E5:
    LHLD CSRY
    PUSH H
    MOV A,L
    STA D_FAAD
    LDA D_F63D
    PUSH PSW
    CALL CHGET
    POP B
    POP H
    PUSH PSW
    XRA A
    STA D_FAAD
    LDA D_F63D
    CMP B
    JNZ L_6404
    POP PSW
    RET

L_6404:
    ANA A
    JZ L_6414
    LDA CSRY
    CMP L
    LDA D_F63B
    CNZ L_6284
    POP PSW
    RET

L_6414:
    PUSH H
    LDA D_F63B
    DCR A
    CALL L_6A48
    INX H
    MVI M,$FE
    INX H
    INX H
    MVI M,$FE
    DCR A
    CALL L_69CB
    XRA A
    STA D_F6E1
    POP H
    CALL POSIT
    POP PSW
    RET

L_6431:
    CALL L_62EE
    CALL L_6383
    CALL L_64B6
    PUSH PSW
    CALL L_634A
    POP PSW
    JNC L_628F
    JMP L_60A3

L_6445:
    CALL L_62EE
    CALL L_6383
    CALL L_64B6
    PUSH PSW
    CNC MASDEL
    POP PSW
    JNC L_646F
    MOV A,B
    ANA A
    JZ L_646A

L_645B:
    CALL L_1BB1
    PUSH B
    LXI B,$0100
    CALL L_6488
    POP B
    DCR B
    JNZ L_645B

L_646A:
    MOV A,C
    ANA A
    CNZ L_6488

L_646F:
    LXI D,$0000
    XCHG
    SHLD D_F6E2
    XCHG
    PUSH H
    LDA CSRY
    CALL L_6986
    POP H
    CALL L_630B
    CALL L_6B2A
    JMP L_634A

L_6488:
    PUSH H
    PUSH B
    XCHG
    LHLD D_FC87
    XCHG
    CALL L_6BDB
    POP B
    POP H
    PUSH H
    PUSH B
    CALL MASDEL
    LHLD D_F9A5
    DAD B
    XCHG
    POP B
    CALL L_6B7F
    XCHG
    LHLD D_FC87
    CALL L_6BDB
    POP H
    RET

L_64AB:
    LHLD D_F6E2
    XCHG
    LHLD D_F6E4

L_64B2:
    RST 3
    RC
    XCHG
    RET

L_64B6:
    CALL L_2262
    LHLD D_F9A5
    SHLD D_F88C
    XRA A
    STA D_F6E6
    CALL L_64AB
    DCX D

L_64C7:
    MOV A,E
    SUB L
    MOV C,A
    MOV A,D
    SBB H
    MOV B,A
    JC L_64E3
    LDAX D
    CPI $1A
    JZ L_64E4
    CPI $0D
    JNZ L_64E3
    INX D
    LDAX D
    CPI $0A
    JNZ L_64E3
    INX B

L_64E3:
    INX B

L_64E4:
    MOV A,B
    ORA C
    RZ
    PUSH H
    LHLD D_F88C
    CALL MAKHOL
    XCHG
    POP H
    RC
    LDA D_F6E6
    ANA A
    JZ L_64F9
    DAD B

L_64F9:
    PUSH H
    PUSH B
    CALL L_6BDB
    POP B
    POP H
    RET

L_6501:
    CALL L_628F
    CALL L_6383
    CALL L_2146
    CALL L_6AF9
    SHLD D_F88C
    MOV A,H
    STA D_F6E6
    LHLD D_F9A5
    MOV A,M
    CPI $1A
    JZ L_634A
    MOV E,L
    MOV D,H
    DCX D

L_6520:
    INX D
    LDAX D
    CPI $1A
    JNZ L_6520
    CALL L_64C7
    PUSH PSW
    PUSH D
    CALL L_6B2A
    CALL L_634A
    POP D
    POP PSW
    JC L_60A3
    PUSH D
    LHLD D_F88C
    LDA CSRY
    CALL L_6986
    CALL L_6A3E
    POP H
    RST 3
    CALL L_63CD
    PUSH H
    CNC L_6986
    POP H
    JMP L_630B

.if MODEL = 100
L_6551:
    CALL L_659B
.else
L_6551:
    CALL L_1B98
.endif

    CALL L_6AF9
    PUSH H
    LXI H,D_65D7
    LXI D,$F71F
    PUSH D
    CALL L_6603
    POP D
    INX H
    MOV A,M
    ANA A
    STC
    JZ L_658B
    CALL L_65C3
    POP D
    PUSH D
    LDAX D
    CPI $1A
    JZ L_658F
    INX D
    CALL L_5C3F
    JNC L_658F
    POP D
    PUSH B
    PUSH B
    CALL L_6A3E
    POP H
    RST 3
    JC L_658B
    CALL L_6981
    ANA A

L_658B:
    CC L_65F3
    STC

L_658F:
    LXI H,D_65CE
    CNC L_65AE
    JMP L_6229

L_6598:
    CALL L_628F

L_659B:
    LHLD CSRY
    CALL L_63CD
    CMP L
    RNZ
    DCR L
    PUSH H
    CALL L_627B
    JMP L_60AD

L_65AB:
    LXI H,D_5771

L_65AE:
    MVI A,$01
    STA D_F6E1

L_65B3:
    CALL L_65DF
    CALL STROUT

L_65B9:
    CALL CHSNS
    RZ
    CALL CHGET
    JMP L_65B9

L_65C3:
    PUSH H

L_65C4:
    MOV A,M
    STAX D
    INX H
    INX D
    ANA A
    JNZ L_65C4
    POP H
    RET

D_65CE:
    .byte "No match", $00

D_65D7:
    .byte "String:", $00

L_65DF:
    PUSH H
    CALL L_63DB
    MVI H,$01
    CALL POSIT
    POP H
    JMP ERAEOL

L_65EC:
    LXI H,$F6E1
    XRA A
    CMP M
    RZ
    MOV M,A

L_65F3:
    LHLD CSRY
    PUSH H
    CALL L_63CD
    CALL L_69CB
    JMP L_60AD

L_6600:
    LXI D,D_5F48

L_6603:
    PUSH D
    CALL L_65B3
    LDA CSRX
    STA D_FACA
    POP H
    PUSH H
    CALL STROUT

L_6612:
    CALL CHGET
    JC L_6612
    ANA A
    JZ L_6612
    POP H
    CPI $0D
    JZ L_6654
    PUSH PSW
    CALL L_63DB
    LDA D_FACA
    MOV H,A
    CALL POSIT
    CALL ERAEOL
    POP PSW
    LXI D,BUF
    MVI B,$01
    ANA A
    JMP L_663D

L_663A:
    CALL CHGET

L_663D:
    LXI H,L_663A
    PUSH H
    RC
    CPI $7F
    JZ L_46A0
    CPI $20
    JNC L_667E
    LXI H,$665B
    MVI C,$07
    JMP L_4378

L_6654:
    LXI D,BUF
    CALL L_65C3
    JMP L_6678

TXTINL:
    DISPATCH $03, L_6672
    DISPATCH $08, L_46A0
    DISPATCH $09, L_667C
    DISPATCH $0D, L_6675
    DISPATCH $15, L_46C3
    DISPATCH $18, L_46C3
    DISPATCH $1D, L_46A0

L_6672:
    LXI D,BUF

L_6675:
    POP H
    XRA A
    STAX D

L_6678:
    LXI H,BUFMIN
    RET

L_667C:
    MVI A,$09

L_667E:
    MOV C,A
    LDA D_F63C
    SUI $09
    LXI H,CSRX
    CMP M
    JC ST_BEEP
    MOV A,C
    INR B
    RST 4
    STAX D
    INX D
    RET

L_6691:
    CALL L_6598
    LXI H,L_66F2
    SHLD D_F652
    PUSH H
    LHLD CSRY
    SHLD D_F6E7
    LXI H,D_670C
    LXI D,$F64A
    CALL L_6603
    RST 2
    XRA A
    CMP M
    JZ L_66E6
    STA D_F688
    CALL GETBYT
    CPI $0A
    RC
    CPI $85
    RNC
    POP D
    STA D_F649
    STA D_F922
    STA PRTFLG
    LXI D,$F64A
    LXI H,BUF
    CALL L_65C3
    INR A
    STA D_F920
    CALL CRLF
    LHLD D_F767
    XCHG

L_66DA:
    CALL L_6A0D
    MOV A,D
    ANA E
    INR A
    JNZ L_66DA
    CALL L_66FE

L_66E6:
    CALL L_65F3

L_66E9:
    LHLD D_F6E7
    CALL POSIT
    JMP L_5FDD

L_66F2:
    CALL L_66FE
    CALL L_4F45
    CALL L_65AB
    JMP L_66E9

L_66FE:
    LDA D_F63C
    STA D_F922
    XRA A
    STA PRTFLG
    STA D_F920
    RET

D_670C:
    .byte "Width:", $00

L_6713:
    LXI D,D_6735
    CALL L_673E
    JC L_66F2
    JZ L_66E6
    MVI E,$02
    CALL L_4D12
    LHLD D_F767

L_6727:
    MOV A,M
    RST 4
    INX H
    CPI $1A
    JNZ L_6727
    CALL L_4F45
    JMP L_66E6

D_6735:
    .byte "Save to:", $00

L_673E:
    PUSH D
    CALL L_6598
    LXI H,L_66F2
    SHLD D_F652
    LHLD CSRY
    SHLD D_F6E7
    POP H
    CALL L_6600
    RST 2
    ANA A
    RZ
    CALL L_21FA
    CALL L_4C0B
    JNZ L_6760
    MVI D,$FD

L_6760:
    MOV A,D
    CPI $F8
    STC
    RZ
    CPI $FE
    STC
    RZ
    CPI $FF
    STC
    RZ
    LXI H,D_5F48
    CMC
    MVI A,$00
    RET

L_6774:
    LXI D,D_67D4
    CALL L_673E
    JC L_66F2
    JZ L_66E6
    PUSH H
    LXI H,L_67CB
    SHLD D_F652
    LHLD D_FB62
    SHLD D_F6E7
    STA D_FAC6
    XTHL
    MVI E,$01
    CALL L_4D12
    POP H

L_6797:
    CALL L_4E7A
    JC L_67B7
    CALL L_56FE
    JZ L_6797
    JNC L_67AB
    CALL L_6396
    MVI A,$0A

L_67AB:
    CNC L_6396
    JNC L_6797
    CALL L_4F45
    CALL L_60A3

L_67B7:
    CALL L_4F45

L_67BA:
    CALL L_6B2A
    LHLD D_F6E7
    PUSH H
    CALL L_6981
    POP H
    CALL L_630B
    JMP L_5FDD

L_67CB:
    CALL L_4F45
    CALL L_65AB
    JMP L_67BA

D_67D4:
    .byte "Load from:", $00

L_67DF:
    XRA A
    STA D_F890
    STA D_F6E6
    LXI H,$F894
    SHLD D_F892

L_67EC:
    PUSH D
    CALL L_6912
    POP D
    LDAX D
    INX D
    CPI $1A
    JZ L_6887
    CPI $0D
    JZ L_6897
    CPI $09
    JZ L_6807
    CPI $20
    JC L_685D

L_6807:
    CALL L_68B2
    JNC L_67EC
    LDAX D
    CALL L_695E
    JNZ L_6827
    CALL L_6855
    LDAX D
    CPI $20
    RNZ
    LDA D_F920
    ANA A
    RZ
    INX D
    LDAX D
    CPI $20
    RNZ
    DCX D
    RET

L_6827:
    XCHG
    SHLD D_F88C
    XCHG
    LHLD D_F892
    SHLD D_F88E
    DCX D
    LDAX D
    INX D
    CALL L_695E
    JZ L_6855

L_683B:
    DCX D
    LDAX D
    INX D
    CALL L_695E
    JZ L_68EF
    DCX D
    CALL L_68D9
    JNZ L_683B
    LHLD D_F88E
    SHLD D_F892
    LHLD D_F88C
    XCHG

L_6855:
    LDA D_F920
    DCR A
    JZ L_6908
    RET

L_685D:
    PUSH PSW
    MVI A,$5E
    CALL L_68B2
    JC L_6877
    POP PSW
    ORI $40
    CALL L_68B2
    JNC L_67EC
    LDA D_F920
    ANA A
    JNZ L_6908
    RET

L_6877:
    POP PSW
    DCX D
    LHLD D_F892
    DCX H
    SHLD D_F892
    LXI H,$F890
    DCR M
    JMP L_68EF

L_6887:
    LDA D_F920
    ANA A
    MVI A,$9B
    CZ L_68B2
    CALL L_68EF
    LXI D,$FFFF
    RET

L_6897:
    LDAX D
    CPI $0A
    MVI A,$0D
    JNZ L_685D
    PUSH D
    CALL L_6912
    POP D
    LDA D_F920
    ANA A
    MVI A,$8F
    CZ L_68B2
    CALL L_68EF
    INX D
    RET

L_68B2:
    PUSH H
    CALL L_68D0
    LXI H,$F890
    CPI $09
    JZ L_68C2
    INR M
    JMP L_68C9

L_68C2:
    INR M
    MOV A,M
    ANI $07
    JNZ L_68C2

L_68C9:
    LDA D_F922
    DCR A
    CMP M
    POP H
    RET

L_68D0:
    LHLD D_F892
    MOV M,A
    INX H
    SHLD D_F892
    RET

L_68D9:
    LHLD D_F892
    DCX H
    DCX H
    DCX H
    MOV A,M
    CPI $1B
    JZ L_68E7
    INX H
    INX H

L_68E7:
    SHLD D_F892
    LXI H,$F890
    DCR M
    RET

L_68EF:
    LDA D_F890
    LXI H,$F922
    CMP M
    RNC
    LDA D_F920
    ANA A
    JNZ L_6908
    MVI A,$1B
    CALL L_68D0
    MVI A,$4B
    CALL L_68D0

L_6908:
    MVI A,$0D
    CALL L_68D0
    MVI A,$0A
    JMP L_68D0

L_6912:
    CALL L_62EE
    LDA D_F920
    ANA A
    RNZ
    LXI B,$F6E6
    PUSH D
    XCHG
    LHLD D_F6E4
    XCHG
    RST 3
    POP D
    JNC L_693F
    XCHG
    RST 3
    JC L_694D
    XCHG
    LHLD D_F6E4
    XCHG
    RST 3
    JNC L_694D

L_6936:
    LDAX B
    ANA A
    RNZ
    INR A
    MVI H,$70
    JMP L_6953

L_693F:
    XCHG
    RST 3
    JNC L_694D
    XCHG
    LHLD D_F6E4
    XCHG
    RST 3
    JNC L_6936

L_694D:
    LDAX B
    ANA A
    RZ
    XRA A
    MVI H,$71

L_6953:
    PUSH H
    STAX B
    MVI A,$1B
    CALL L_68D0
    POP PSW
    JMP L_68D0

L_695E:
    MOV B,A
    LDA D_F921
    ANA A
    MOV A,B
    RZ

L_6965:
    LXI H,D_6977
    MVI B,$0A

L_696A:
    CMP M
    RZ
    INX H
    DCR B
    JNZ L_696A
    CPI $21
    INR B
    RNC
    DCR B
    RET

D_6977:
    .byte "()<>[]+-*/"

L_6981:
    CALL L_63CD
    ANA A
    RAR

L_6986:
    CALL L_6B39
    SHLD D_F6EB
    CALL L_63CD
    ADD A
    LXI H,$F6ED

L_6993:
    MVI M,$FE
    INX H
    DCR A
    JNZ L_6993
    INR A
    JMP L_69CB

L_699E:
    PUSH PSW
    LHLD D_F6E9
    MOV A,H
    ORA L
    JZ L_69CA
    XCHG
    CALL L_67DF
    POP PSW
    MOV B,A
    CALL L_6A27
    MOV A,B
    PUSH PSW
    JZ L_69CA
    DCR A
    JZ L_69CA
    MOV L,A
    MVI H,$01
    CALL POSIT
    CALL L_6A10
    MOV A,D
    ANA E
    INR A
    POP B
    JZ ERAEOL
    PUSH B

L_69CA:
    POP PSW

L_69CB:
    MOV L,A
    MVI H,$01
    CALL POSIT
    CALL L_6A45
    MOV A,E
    ANA D
    INR A
    JZ L_6A04
    CALL L_6A45

L_69DD:
    CALL L_63DB
    CMP L
    JZ L_69F4
    CALL L_6A0D
    MOV A,D
    ANA E
    INR A
    JZ L_69FE
    CALL L_6A2E
    JNZ L_69DD
    RET

L_69F4:
    CALL L_6A0D

L_69F7:
    CALL L_63CD
    INR A
    JMP L_6A27

L_69FE:
    CALL L_6A2E
    JZ L_69F7

L_6A04:
    CALL ERAEOL
    CALL CRLF
    JMP L_69FE

L_6A0D:
    CALL L_67DF

L_6A10:
    PUSH D
    LHLD D_F892
    LXI D,$F894

L_6A17:
    LDAX D
    RST 4
    INX D
    RST 3
    JNZ L_6A17
    LDA D_F920
    ANA A
    CZ EXTREV
    POP D
    RET

L_6A27:
    PUSH D
    CALL L_6A48
    JMP L_6A32

L_6A2E:
    PUSH D
    CALL L_6A45

L_6A32:
    MOV C,A
    XTHL
    RST 3
    MOV A,C
    XCHG
    POP H
    RZ
    MOV M,E
    INX H
    MOV M,D
    MOV A,C
    RET

L_6A3E:
    CALL L_63CD
    INR A
    JMP L_6A48

L_6A45:
    LDA CSRY

L_6A48:
    MOV E,A
    MVI D,$00
    LXI H,$F6E9
    DAD D
    DAD D
    MOV E,M
    INX H
    MOV D,M
    DCX H
    RET

L_6A55:
    CALL L_6A45
    DCR A
    JZ L_6A61
    DCX H
    MOV D,M
    DCX H
    MOV E,M
    RET

L_6A61:
    LHLD D_F767
    RST 3
    JC L_6A6C
    LXI D,$0000
    RET

L_6A6C:
    PUSH D
    DCX D
    RST 3
    JNC L_6A8A

L_6A72:
    DCX D
    RST 3
    JNC L_6A8A
    LDAX D
    CPI $0A
    JNZ L_6A72
    DCX D
    RST 3
    JNC L_6A8A
    LDAX D
    INX D
    CPI $0D
    JNZ L_6A72
    INX D

L_6A8A:
    PUSH D
    CALL L_67DF
    POP B
    XCHG
    POP D
    PUSH D
    RST 3
    XCHG
    JC L_6A8A
    POP D
    MOV E,C
    MOV D,B
    RET

L_6A9B:
    CALL L_6A55
    XCHG
    SHLD D_F6E9
    RET

L_6AA3:
    SHLD D_F6E7
    PUSH H
    LXI H,$F6EB
    CALL L_63CD
    MOV B,A

L_6AAE:
    MOV E,M
    INX H
    MOV D,M
    INX H
    PUSH H
    LHLD D_F6E7
    RST 3
    JC L_6AC4
    POP H
    XCHG
    XTHL
    XCHG
    DCR B
    JP L_6AAE
    DI
    HLT

L_6AC4:
    XCHG
    POP H
    POP H

L_6AC7:
    PUSH H
    LXI H,$F894
    SHLD D_F892
    XRA A
    STA D_F890
    POP H
    DCX H

L_6AD4:
    INX H
    RST 3
    JNC L_6AEE
    MOV A,M
    CALL L_68B2
    MOV A,M
    CPI $20
    JNC L_6AD4
    CPI $09
    JZ L_6AD4
    CALL L_68B2
    JMP L_6AD4

L_6AEE:
    LDA D_F890
    INR A
    MOV H,A
    CALL L_63CD
    SUB B
    MOV L,A
    RET

L_6AF9:
    CALL L_6A45
    PUSH D
    INR A
    CALL L_6A48
    MOV A,D
    ANA E
    INR A
    JNZ L_6B0C
    LHLD D_FB62
    XCHG
    INX D

L_6B0C:
    DCX D
    LDAX D
    CPI $0A
    JNZ L_6B1B
    DCX D
    LDAX D
    CPI $0D
    JZ L_6B1B
    INX D

L_6B1B:
    POP H
    PUSH H
    CALL L_6AC7
    LDA CSRX
    CMP H
    JC L_6B0C
    POP H
    XCHG
    RET

L_6B2A:
    LHLD D_F767

L_6B2D:
    MVI A,$1A

L_6B2F:
    CMP M
    INX H
    JNZ L_6B2F
    DCX H
    SHLD D_FB62
    RET

L_6B39:
    PUSH PSW
    XCHG
    LHLD D_F767
    XCHG

L_6B3F:
    PUSH H
    PUSH D
    CALL L_67DF
    POP B
    POP H
    RST 3
    JNC L_6B3F
    MOV H,B
    MOV L,C
    POP B
    DCR B
    RZ
    XCHG

L_6B50:
    PUSH B
    CALL L_6A61
    POP B
    MOV A,D
    ORA E
    LHLD D_F767
    RZ
    DCR B
    JNZ L_6B50
    XCHG
    RET
