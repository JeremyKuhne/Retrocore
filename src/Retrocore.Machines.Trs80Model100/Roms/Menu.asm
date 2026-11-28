;; MODEL 100 ROM: THE MAIN MENU, THE FUNCTION KEYS AND THE DIRECTORY SEARCH, ADDRSS AND SCHEDL
;;
;; Runs at $5797-$5DED. Model100.asm describes the ROM as a whole and how it is named.

MENU:
    LHLD MEMSIZ
    SHLD STKTOP
    CALL L_3F2C
    CALL CLSCOM
    CALL L_6370
    CALL L_2146
    CALL EXTREV
    CALL CUROFF
    CALL ERAFNK
    CALL LOCK
    LDA D_F638
    STA D_FDFA
    MVI A,$FF
    STA D_FAC8
    INR A
    STA D_F650
    STA D_FAAD
    CALL L_1E3C
    CALL L_5D4D
    LXI H,MENU
    SHLD D_F652
    CALL CLRFLK
    CALL L_5A12
    LXI H,$1C01
    CALL POSIT
    LXI H,D_5B0D
    CALL L_5A58
    LXI H,$FDA1
    SHLD D_FDD7
    MVI B,$36

L_57ED:
    MVI M,$FF
    INX H
    DCR B
    JNZ L_57ED
    MOV L,B
    LXI D,D_5B1E

L_57F8:
    LDAX D
    ORA A
    JZ L_5807
    MOV C,A
    PUSH D
    CALL L_5970
    POP D
    INX D
    JMP L_57F8

L_5807:
    MOV A,L
    DCR A
    STA D_FDEF
    CPI $17
    JZ L_5823

L_5811:
    CALL L_59C9
    PUSH H
    LXI H,D_5B1A
    CALL L_5A58
    POP H
    INR L
    MOV A,L
    CPI $18
    JNZ L_5811

L_5823:
    SUB A
    STA PRGNAM
    STA D_FDEE
    MOV L,A
    CALL L_59E5
    LXI H,$1808
    CALL POSIT
    CALL L_7EAC

L_5837:
    CALL L_5D4D
    LXI H,L_5906
    SHLD D_F652
    LXI H,$0108
    CALL POSIT
    LXI H,D_5B24
    CALL L_5A58
    LXI H,$0908
    CALL POSIT
    SUB A
    STA D_FDED
    LXI H,PRGNAM
    INR A

L_585A:
    CZ ST_BEEP

L_585D:
    CALL L_5D70
    CALL L_5D64
    CPI $0D
    JZ L_58F7
    CPI $08
    JZ L_588E
    CPI $7F
    JZ L_588E
    CPI $15
    JZ L_5837
    CPI $20
    JC L_589C
    MOV C,A
    LDA D_FDED
    CZ L_5897
    CPI $09
    JZ L_585A
    CALL L_5D88
    JMP L_585D

L_588E:
    CALL L_5D9E
    JZ L_585A
    JMP L_585D

L_5897:
    ORA A
    RNZ
    POP PSW
    MVI A,$1C

L_589C:
    PUSH PSW
    LDA D_FDEE
    MOV E,A
    POP PSW
    SUI $1C
    LXI B,L_585D
    PUSH B
    RM
    LXI B,L_58C3
    PUSH B
    JZ L_58EB
    DCR A
    JZ L_58E2
    DCR A
    POP B
    JZ L_58DB
    MOV A,E
    ADI $04
    MOV D,A
    LDA D_FDEF
    CMP D
    RM
    MOV A,D

L_58C3:
    STA D_FDEE
    PUSH H
    LHLD CSRY
    PUSH H
    MOV L,E
    PUSH D
    CALL L_59E5
    POP D
    MOV L,D
    CALL L_59E5
    POP H
    CALL POSIT
    POP H
    RET

L_58DB:
    MOV A,E
    SUI $04
    MOV D,A
    RM
    PUSH B
    RET

L_58E2:
    MOV A,E
    DCR A
    MOV D,A
    RP
    LDA D_FDEF
    MOV D,A
    RET

L_58EB:
    MOV A,E
    INR A
    MOV D,A
    LDA D_FDEF
    CMP D
    MOV A,D
    RP
    SUB A
    MOV D,A
    RET

L_58F7:
    LDA D_FDED
    ORA A
    JZ L_590C
    MVI M,$00
    CALL L_5AB1
    JNZ L_5921

L_5906:
    CALL ST_BEEP
    JMP L_5837

L_590C:
    LDA D_FDEE
    LXI H,$FDA1
    LXI D,$0002

L_5915:
    ORA A
    JZ L_591E
    DAD D
    DCR A
    JMP L_5915

L_591E:
    CALL L_5AE4

L_5921:
    PUSH H
    CALL CLS
    CALL UNLOCK
    LDA D_FDFA
    CALL L_1E3C
    MVI A,$0C
    RST 4
    SUB A
    STA D_FAC8
    MOV L,A
    MOV H,L
    SHLD D_F652
    DCR A
    STA D_FAAD
    POP H
    MOV A,M
    CALL GTXTTB
    CPI $A0
    JZ L_254B
    CPI $B0
    JZ L_596F
    CPI $F0
    JZ D_F624
    CPI $C0
    JZ L_5F65
    SHLD TXTTAB
    DCX D
    DCX D
    XCHG
    SHLD D_FA8C
    CALL LINKER
    CALL L_6C9C
    CALL L_6C7F
    CALL L_3F28
    JMP NEWSTT

L_596F:
    PCHL

L_5970:
    MVI B,$1B
    LXI D,DIRTBL

L_5975:
    LDAX D
    INR A
    RZ
    DCR A
    CMP C
    JNZ L_59A1
    PUSH B
    PUSH D
    PUSH H
    LHLD D_FDD7
    MOV M,E
    INX H
    MOV M,D
    INX H
    INX D
    INX D
    INX D
    SHLD D_FDD7
    POP H
    CALL L_59C9
    PUSH H
    LXI H,PRGNAM
    PUSH H
    CALL L_59AD
    POP H
    CALL L_5A58
    POP H
    INR L
    POP D
    POP B

L_59A1:
    PUSH H
    LXI H,$000B
    DAD D
    XCHG
    POP H
    DCR B
    JNZ L_5975
    RET

L_59AD:
    MVI A,$06
    CALL L_5A62
    MVI A,$20

L_59B4:
    DCX H
    CMP M
    JZ L_59B4
    INX H
    MVI M,$00
    LDAX D
    CPI $20
    RZ
    MVI M,$2E
    INX H
    CALL L_5A60
    MVI M,$00
    RET

L_59C9:
    PUSH D
    PUSH H
    MOV A,L
    RAR
    RAR
    ANI $3F
    MOV E,A
    INR E
    INR E
    MOV A,L
    ANI $03
    ADD A
    MOV D,A
    ADD A
    ADD A
    ADD D
    MOV D,A
    INR D
    INR D
    XCHG
    CALL POSIT
    POP H
    POP D
    RET

L_59E5:
    CALL L_73C5
    CALL L_59C9
    MVI B,$0A
    PUSH H
    LXI H,CSRX
    DCR M

L_59F2:
    PUSH B
    PUSH D
    LHLD CSRY
    CALL L_45CB
    XCHG
    CALL L_7440
    DI
    CALL L_73A9
    EI
    POP D
    LXI H,CSRX
    INR M
    POP B
    DCR B
    JNZ L_59F2
    CALL L_73C5
    POP H
    RET

L_5A12:
    CALL CLS

L_5A15:
    CALL L_5D6A
    LXI H,$FD8B
    CALL DATE
    MVI M,$20
    INX H
    CALL DAY
    XCHG
    MVI M,$20
    INX H
    CALL TIME
    MVI M,$00
    LDA D_F92C
    LXI H,$5AE6
    LXI B,$0003

L_5A36:
    DAD B
    DCR A
    JNZ L_5A36
    LXI D,$FD88
    XCHG
    PUSH H
    MOV A,C
    CALL L_5A62
    MOV D,H
    MOV E,L
    MVI M,$20
    INX D
    INX D
    INX D
    INX H
    CALL L_5A60
    MVI M,$2C
    INX H
    MVI M,$31
    INX H
    MVI M,$39
    POP H

L_5A58:
    MOV A,M
    ORA A
    RZ
    RST 4
    INX H
    JMP L_5A58

L_5A60:
    MVI A,$02

L_5A62:
    PUSH PSW
    LDAX D
    MOV M,A
    INX D
    INX H
    POP PSW
    DCR A
    JNZ L_5A62
    RET

L_5A6D:
    LDAX D
    CMP M
    RNZ
    ORA A
    RZ
    INX H
    INX D
    DCR C
    JNZ L_5A6D
    RET

CLRFLK:
    LXI H,D_5B3E

STFNK:
    LXI D,$F789
    MVI B,$08

L_5A81:
    MVI C,$10

L_5A83:
    MOV A,M
    INX H
    ORA A
    PUSH PSW
    ANI $7F
    STAX D
    POP PSW
    JM L_5A93
    INX D
    DCR C
    JNZ L_5A83

L_5A93:
    SUB A

L_5A94:
    INX D
    DCR C
    STAX D
    JNZ L_5A94
    DCR B
    JNZ L_5A81

FNKSB:
    LDA D_F63D
    ORA A
    CNZ DSPFNK
    RET

L_5AA6:
    LXI D,D_5CCE

CHKDC:
    MVI A,$08
    LXI H,PRGNAM
    CALL L_5A62

L_5AB1:
    MVI B,$1B
    LXI D,DIRTBL

L_5AB6:
    LXI H,$FDF0
    LDAX D
    INR A
    RZ
    ANI $80
    JZ L_5AD9
    PUSH D
    INX D
    INX D
    INX D
    PUSH H
    CALL L_59AD
    POP H
    MVI C,$09
    LXI D,PRGNAM
    CALL L_5A6D
    JNZ L_5AD8
    POP H
    INR C
    RET

L_5AD8:
    POP D

L_5AD9:
    LXI H,$000B
    DAD D
    XCHG
    DCR B
    JNZ L_5AB6
    RET

GTXTTB:
    INX H

L_5AE4:
    MOV E,M
    INX H
    MOV D,M
    XCHG
    RET

    .byte "JanFebMarAprMayJ"
    .byte $75, $6E, $4A

.if MODEL = 100
    .byte $6C, $79
.else
    .byte $75, $6C
.endif

    .byte "AugSepOctNovDec"

D_5B0D:
    .byte "(C)Microsoft", $00

D_5B1A:
    .byte $2D, $2E, $2D, $00

D_5B1E:
    .byte $B0, $F0, $C0, $80, $A0, $00

D_5B24:
    .byte "Select: _       "
    .byte $20, $20, $00

D_5B37:
    .byte $20, $08, $08

D_5B3A:
    .byte $5F, $08

D_5B3C:
    .byte $00, $00

D_5B3E:
    .byte $80, $80, $80, $80, $80, $80, $80, $80

D_5B46:
    .byte "Files", $8D, "Load ", $A2, "Save"
    .byte $20, $A2, $52, $75, $6E, $8D, "List", $8D, $80, $80, $4D, $65, $6E
    .byte $75, $8D

ADDRSS:
    LXI D,D_5CCE
    SUB A
    JMP L_5B74

SCHEDL:
    LXI D,D_5D02
    MVI A,$FF

L_5B74:
    STA D_FDED
    CALL L_5D4D
    PUSH D
    CALL CHKDC
    CALL GTXTTB
    JNZ L_5BA9
    POP H
    SHLD D_FDEE

L_5B88:
    LXI H,L_5B88
    SHLD D_F652
    CALL CLS
    CALL ST_BEEP
    LHLD D_FDEE
    CALL L_5A58
    LXI H,D_5CD6
    CALL L_5A58
    LXI H,$0003
    CALL L_5F24
    JMP MENU

L_5BA9:
    SHLD D_FDD7
    CALL CLS
    LXI H,D_5D0A
    CALL STDSPF
    LXI H,L_5BE2
    SHLD D_F652

L_5BBB:
    CALL L_5D5D
    SUB A
    STA PRTFLG
    LXI H,D_5CE1
    LDA D_FDED
    ORA A
    JZ L_5BCF
    LXI H,D_5CE8

L_5BCF:
    CALL L_5A58
    CALL INLIN
    INX H
    MOV A,M
    ORA A
    JZ L_5BBB
    LXI D,ADRCMD
    CALL L_6CA7
    RNZ

L_5BE2:
    SUB A
    STA PRTFLG
    CALL L_4BB8
    CALL ST_BEEP
    LXI H,D_5D0A
    CALL STFNK
    JMP L_5BBB

L_5BF5:
    SUB A
    .byte $01                           ; LXI B,$FF3E: skips the next two bytes

L_5BF7:
    MVI A,$FF
    CALL L_5DB1

L_5BFC:
    CALL L_5C3F
    JNC L_5BBB
    PUSH H
    PUSH D
    CALL L_5DC5

L_5C07:
    CALL L_67DF
    LDA D_FDEE
    STA PRTFLG
    CALL L_6A10
    SUB A
    STA PRTFLG
    LDA D_FDEE
    ORA A
    JNZ L_5C24
    CALL L_5DE4
    JZ L_5BBB

L_5C24:
    DCX D
    LDAX D
    INX D
    CPI $0A
    JZ L_5C37
    PUSH D
    INX D
    MOV A,E
    ORA D
    POP D
    JNZ L_5C07
    JMP L_5BBB

L_5C37:
    POP D
    CALL L_5C6D
    POP H
    JMP L_5BFC

L_5C3F:
    PUSH D

L_5C40:
    PUSH H
    PUSH D

L_5C42:
    LDAX D
    CALL MAKUPS
    MOV C,A
    CALL MAKUPL
    CMP C
    JNZ L_5C53
    INX D
    INX H
    JMP L_5C42

L_5C53:
    CPI $00
    MOV A,C
    POP B
    POP H
    JZ L_5C6A
    CPI $1A
    JZ L_5C96
    CALL L_5C74
    JNZ L_5C40
    POP PSW
    JMP L_5C3F

L_5C6A:
    POP D
    STC
    RET

L_5C6D:
    CALL L_5C74
    JNZ L_5C6D
    RET

L_5C74:
    LDAX D
    CPI $0D
    INX D
    RNZ
    LDAX D
    CPI $0A
    RNZ
    INX D
    RET

L_5C7F:
    PUSH D
    LXI H,D_5D2B
    CALL STFNK
    CALL L_5CAE
    PUSH PSW
    LXI H,D_51A4

L_5C8D:
    CALL STFNK
    CALL L_5DBC
    POP PSW
    CPI $51

L_5C96:
    POP D
    RET

L_5C98:
    PUSH D
    LXI H,D_5D1E
    CALL STFNK

L_5C9F:
    CALL L_5CAE
    CPI $43
    JZ L_5C9F
    PUSH PSW
    LXI H,D_5D0A
    JMP L_5C8D

L_5CAE:
    CALL CHGET
    PUSH PSW
    SUB A
    STA D_F62D
    POP PSW
    CALL MAKUPS
    CPI $51
    RZ
    CPI $20
    RZ
    CPI $4D
    RZ
    CPI $43
    RZ
    CPI $0D
    JNZ L_5CAE
    ADI $36
    RET

D_5CCE:
    .byte "ADRS.DO", $00

D_5CD6:
    .byte " not found", $00

D_5CE1:
    .byte "Adrs: ", $00

D_5CE8:
    .byte "Schd: ", $00

ADRCMD:
    .byte "FIND"
    .word L_5BF5
    .byte "LFND"
    .word L_5BF7
    .byte "MENU"
    .word MENU
    .byte $FF                           ; the end

D_5D02:
    .byte "NOTE.DO", $00

D_5D0A:
    .byte "Find", $A0, $80, $80, $80, "Lfnd", $A0, $80, $80, $4D
    .byte $65, $6E, $75, $8D

D_5D1E:
    .byte $80, $80, $4D, $6F, $72, $E5, $51, $75, $69, $F4, $80, $80, $80

D_5D2B:
    .byte $80, "Call", $A0, $4D, $6F, $72, $E5, $51, $75, $69, $F4, $80, $80
    .byte $80, $80, $C3, $97, $57, $11, $10, $00, $19, $0D, $C9

L_5D46:
    MOV A,M
    INX H
    CPI $20
    RZ
    DCX H
    RET

L_5D4D:
    LXI H,D_5B3C
    SHLD D_F88A

L_5D53:
    LXI H,$FFFF
    SHLD CURLIN
    INX H
    SHLD D_FAC2

L_5D5D:
    POP B
    LHLD SAVSTK
    SPHL
    PUSH B
    RET

L_5D64:
    CALL CHGET
    JMP MAKUPS

L_5D6A:
    LXI H,$0101
    JMP POSIT

L_5D70:
    PUSH H
    LHLD CSRY
    PUSH H
    CALL CHSNS
    PUSH PSW
    CZ L_5A15
    POP PSW
    POP H
    PUSH PSW
    CALL POSIT
    POP PSW
    POP H
    JZ L_5D70
    RET

L_5D88:
    MOV M,C
    INX H
    PUSH H
    LXI H,$FDED
    INR M
    MOV A,C
    RST 4
    LXI H,D_5B3A
    CALL L_5A58
    POP H
    RET

L_5D99:
    LDA D_FDED
    ORA A
    RET

L_5D9E:
    CALL L_5D99
    RZ
    DCR A
    STA D_FDED
    DCX H
    PUSH H
    LXI H,D_5B37
    CALL L_5A58
    POP H
    INR A
    RET

L_5DB1:
    STA D_FDEE
    CALL L_5D46
    XCHG
    LHLD D_FDD7
    XCHG

L_5DBC:
    LDA D_F63B
    DCR A
    DCR A
    STA D_FDEF
    RET

L_5DC5:
    LXI H,$F63C
    MVI A,$FF
    STA D_F921
    STA D_F920
    LDA D_FDEE
    ORA A
    JZ L_5DDF
    MVI A,$01
    STA D_F920
    LXI H,$F649

L_5DDF:
    MOV A,M
    STA D_F922
    RET

L_5DE4:
    LXI H,$FDEF
    DCR M
    CZ L_5C98
    CPI $51
    RET
