;; MODEL 100 ROM: FNDFOR, THE ERRORS, READY AND MAIN, LINE LINKS AND SEARCH, CRUNCH, FOR, NEWSTT, GONE AND CHRGTR
;;
;; Runs at $0401-$0871. Model100.asm describes the ROM as a whole and how it is named.

FNDFOR:
    LXI H,$0004
    DAD SP

LOOPER:
    MOV A,M
    INX H
    CPI $81
    RNZ
    MOV C,M
    INX H
    MOV B,M
    INX H
    PUSH H
    MOV H,B
    MOV L,C
    MOV A,D
    ORA E
    XCHG
    JZ POPGOF
    XCHG
    RST 3

POPGOF:
    LXI B,$0016
    POP H
    RZ
    DAD B
    JMP LOOPER

READYR:
    LXI B,L_0501
    JMP ERESET

PRGEND:
    LHLD CURLIN
    MOV A,H
    ANA L
    INR A
    JZ ENDCNJ
    LDA ONEFLG
    ORA A
    MVI E,$13
    JNZ ERROR

ENDCNJ:
    JMP ENDCON

L_043D:
    JMP ERROR

DATSNE:
    LHLD DATLIN
    SHLD CURLIN

SNERR:
    MVI E,$02
    .byte $01                           ; LXI B,$0B1E: skips the next two bytes

DV0ERR:
    MVI E,$0B
    .byte $01                           ; LXI B,$011E: skips the next two bytes

NFERR:
    MVI E,$01
    .byte $01                           ; LXI B,$0A1E: skips the next two bytes

DDERR:
    MVI E,$0A
    .byte $01                           ; LXI B,$141E: skips the next two bytes

RWERR:
    MVI E,$14
    .byte $01                           ; LXI B,$061E: skips the next two bytes

OVERR:
    MVI E,$06
    .byte $01                           ; LXI B,$161E: skips the next two bytes

MOERR:
    MVI E,$16
    .byte $01                           ; LXI B,$0D1E: skips the next two bytes

TMERR:
    MVI E,$0D

ERROR:
    XRA A
    STA D_FCA7
    LHLD D_F67E
    MOV A,H
    ORA L
    JZ L_0473
    LDA D_FBE6
    MOV M,A
    LXI H,$0000
    SHLD D_F67E

L_0473:
    EI
    LHLD D_F652
    PUSH H
    MOV A,H
    ORA L
    RNZ
    LHLD CURLIN
    SHLD ERRLIN
    MOV A,H
    ANA L
    INR A
    JZ ERRESM
    SHLD DOT

ERRESM:
    LXI B,ERRMOR

ERESET:
    LHLD SAVSTK
    JMP L_3F78

ERRMOR:
    POP B
    MOV A,E
    MOV C,E
    STA ERRFLG
    LHLD SAVTXT
    SHLD ERRTXT
    XCHG
    LHLD ERRLIN
    MOV A,H
    ANA L
    INR A
    JZ L_04B6
    SHLD OLDLIN
    XCHG
    SHLD OLDTXT

NTMDCN:
    LHLD ONELIN
    MOV A,H
    ORA L
    XCHG

L_04B6:
    LXI H,ONEFLG
    JZ NOTRAP
    ANA M
    JNZ NOTRAP
    DCR M
    XCHG
    JMP GONE4

NOTRAP:
    XRA A
    MOV M,A
    MOV E,C
    CALL L_4BB8
    MOV A,E
    CPI $3B
    JNC L_04DB
    CPI $32
    JNC L_04DD
    CPI $17
    JC L_04E0

L_04DB:
    MVI A,$30

L_04DD:
    SUI $1B
    MOV E,A

L_04E0:
    MVI D,$00
    LXI H,ERRTAB-2
    DAD D
    DAD D
    MVI A,$3F
    RST 4
    MOV A,M
    RST 4
    RST 2
    RST 4
    LXI H,ERRMSG
    PUSH H
    LHLD ERRLIN
    XTHL

L_04F6:
    CALL STROUT
    POP H
    MOV A,H
    ANA L
    INR A
    CNZ L_39CC
    .byte $3E                           ; MVI A,$C1: skips the next byte

L_0501:
    POP B

READY:
    CALL L_4B92
    CALL L_4F45
    CALL L_4BB8
    LXI H,$03F6
    CALL STROUT

MAIN:
    LXI H,$FFFF
    SHLD CURLIN
    LXI H,$F66D
    SHLD SAVTXT

NTAUTO:
    CALL INLIN
    JC MAIN
    RST 2
    INR A
    DCR A
    JZ MAIN
    PUSH PSW
    CALL LINGET
    JNC L_0536
    CALL L_421A
    JZ SNERR

L_0536:
    DCX H
    MOV A,M
    CPI $20
    JZ L_0536
    CPI $09
    JZ L_0536
    INX H
    MOV A,M
    CPI $20
    CZ L_3457

EDENT:
    PUSH D
    CALL CRUNCH
    POP D
    POP PSW
    SHLD SAVTXT
    JNC L_4F1C
    PUSH D
    PUSH B
    XRA A
    STA D_FB97
    RST 2
    ORA A
    PUSH PSW
    XCHG
    SHLD DOT
    XCHG
    CALL FNDLIN
    JC INONLY
    POP PSW
    PUSH PSW
    JZ L_094D
    ORA A

INONLY:
    PUSH B
    JNC L_0591
    CALL DEL
    MOV A,C
    SUB E
    MOV C,A
    MOV A,B
    SBB D
    MOV B,A
    LHLD DOSTRT
    DAD B
    SHLD DOSTRT
    LHLD COSTRT
    DAD B
    SHLD COSTRT
    LHLD D_FAD8
    DAD B
    SHLD D_FAD8

L_0591:
    POP D
    POP PSW
    PUSH D
    JZ L_05DA
    POP D
    LXI H,$0000
    SHLD ONELIN

LEVFRE:
    LHLD VARTAB
    XTHL
    POP B
    PUSH H
    DAD B
    PUSH H
    CALL L_3EF0
    POP H
    SHLD VARTAB
    XCHG
    MOV M,H
    POP B
    POP D
    PUSH H
    INX H
    INX H
    MOV M,E
    INX H
    MOV M,D
    INX H
    LXI D,$F681
    PUSH H
    LHLD DOSTRT
    DAD B
    SHLD DOSTRT
    LHLD COSTRT
    DAD B
    SHLD COSTRT
    LHLD D_FAD8
    DAD B
    SHLD D_FAD8
    POP H

MLOOPR:
    LDAX D
    MOV M,A
    INX H
    INX D
    ORA A
    JNZ MLOOPR

L_05DA:
    POP D
    CALL CHEAD
    LHLD D_FC8C
    SHLD TEMP2
    CALL L_3F28
    LHLD TEMP2
    SHLD D_FC8C
    JMP MAIN

LINKER:
    LHLD TXTTAB
    XCHG

CHEAD:
    MOV H,D
    MOV L,E
    MOV A,M
    INX H
    ORA M
    RZ
    INX H
    INX H

CZLOOP:
    INX H
    XRA A

L_05FE:
    CMP M
    INX H
    JNZ L_05FE
    XCHG
    MOV M,E
    INX H
    MOV M,D
    JMP CHEAD

SCNLIN:
    LXI D,$0000
    PUSH D
    JZ ALLLST
    POP D
    CALL LINSPC
    PUSH D
    JZ SNGLIN
    RST 1
    .byte $D1                           ; SYNCHR: the - token

ALLLST:
    LXI D,$FFFA
    CNZ LINSPC
    JNZ SNERR

SNGLIN:
    XCHG
    POP D

FNDLN1:
    XTHL
    PUSH H

FNDLIN:
    LHLD TXTTAB

LOOP:
    MOV B,H
    MOV C,L
    MOV A,M
    INX H
    ORA M
    DCX H
    RZ
    INX H
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    RST 3
    MOV H,B
    MOV L,C
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    CMC
    RZ
    CMC
    RNC
    JMP LOOP

CRUNCH:
    XRA A
    STA DORES
    MOV C,A
    LXI D,$F681

L_064E:
    MOV A,M
    CPI $20
    JZ L_06EA
    MOV B,A
    CPI $22
    JZ L_070F
    ORA A
    JZ L_0716
    INX H
    ORA A
    JM L_064E
    DCX H
    LDA DORES
    ORA A
    MOV A,M
    JNZ L_06EA
    CPI $3F
    MVI A,$A3
    JZ L_06EA
    MOV A,M
    CPI $30
    JC L_067E
    CPI $3C
    JC L_06EA

L_067E:
    PUSH D
    LXI D,$007F
    PUSH B
    LXI B,L_06CD
    PUSH B
    MVI B,$7F
    MOV A,M
    CPI $61
    JC L_0697
    CPI $7B
    JNC L_0697
    ANI $5F
    MOV M,A

L_0697:
    MOV C,M
    XCHG

L_0699:
    INX H
    ORA M
    JP L_0699
    INR B
    MOV A,M
    ANI $7F
    RZ
    CMP C
    JNZ L_0699
    XCHG
    PUSH H

L_06A9:
    INX D
    LDAX D
    ORA A
    JM L_06C9
    MOV C,A
    MOV A,B
    CPI $88
    JNZ L_06B8
    RST 2
    DCX H

L_06B8:
    INX H
    MOV A,M
    CPI $61
    JC L_06C1
    ANI $5F

L_06C1:
    CMP C
    JZ L_06A9
    POP H
    JMP L_0697

L_06C9:
    MOV C,B
    POP PSW
    XCHG
    RET

L_06CD:
    XCHG
    MOV A,C
    POP B
    POP D
    XCHG
    CPI $91
    MVI M,$3A
    JNZ L_06DB
    INR C
    INX H

L_06DB:
    CPI $FF
    JNZ L_06E9
    MVI M,$3A
    INX H
    MVI B,$8E
    MOV M,B
    INX H
    INR C
    INR C

L_06E9:
    XCHG

L_06EA:
    INX H
    STAX D
    INX D
    INR C
    SUI $3A
    JZ L_06F8
    CPI $49
    JNZ L_06FB

L_06F8:
    STA DORES

L_06FB:
    SUI $54
    JZ L_0705
    SUI $71
    JNZ L_064E

L_0705:
    MOV B,A

L_0706:
    MOV A,M
    ORA A
    JZ L_0716
    CMP B
    JZ L_06EA

L_070F:
    INX H
    STAX D
    INR C
    INX D
    JMP L_0706

L_0716:
    LXI H,$0005
    MOV B,H
    DAD B
    MOV B,H
    MOV C,L
    LXI H,$F680
    STAX D
    INX D
    STAX D
    INX D
    STAX D
    RET

ST_FOR:
    MVI A,$64
    STA D_FB96
    CALL ST_LET
    POP B
    PUSH H
    CALL ST_DATA
    SHLD ENDFOR
    LXI H,$0002
    DAD SP

LPFORM:
    CALL LOOPER
    JNZ L_0758
    DAD B
    PUSH D
    DCX H
    MOV D,M
    DCX H
    MOV E,M
    INX H
    INX H
    PUSH H
    LHLD ENDFOR
    RST 3
    POP H
    POP D
    JNZ LPFORM
    POP D
    SPHL
    SHLD SAVSTK
    .byte $0E                           ; MVI C,$D1: skips the next byte

L_0758:
    POP D
    XCHG
    MVI C,$0C
    CALL L_3EFF
    PUSH H
    LHLD ENDFOR
    XTHL
    PUSH H
    LHLD CURLIN
    XTHL
    RST 1
    .byte $C1                           ; SYNCHR: the TO token
    RST 5
    JZ TMERR
    PUSH PSW
    CALL FRMEVL
    POP PSW
    PUSH H
    JNC L_0791
    JP SNGFOR
    CALL FN_CINT
    XTHL
    LXI D,$0001
    MOV A,M
    CPI $CF
    CZ GETINT
    PUSH D
    PUSH H
    XCHG
    CALL L_341B
    JMP STPSGN

L_0791:
    CALL FN_CDBL
    POP D
    LXI H,$FFF8
    DAD SP
    SPHL
    PUSH D
    CALL L_3487
    POP H
    MOV A,M
    CPI $CF
    LXI D,D_3286
    MVI A,$01
    JNZ L_07B7
    RST 2
    CALL FRMEVL
    PUSH H
    CALL FN_CDBL
    RST 6
    LXI D,$FC18
    POP H

L_07B7:
    MOV B,H
    MOV C,L
    LXI H,$FFF8
    DAD SP
    SPHL
    PUSH PSW
    PUSH B
    CALL L_3465
    POP H
    POP PSW
    JMP L_07F1

SNGFOR:
    CALL FN_CSNG
    CALL L_343D
    POP H
    PUSH B
    PUSH D
    LXI B,$1041
    LXI D,$0000
    MOV A,M
    CPI $CF
    MVI A,$01
    JNZ L_07EB
    CALL FRMCHK
    PUSH H
    CALL FN_CSNG
    CALL L_343D
    RST 6

STPSGN:
    POP H

L_07EB:
    PUSH D
    PUSH B
    PUSH B
    PUSH B
    PUSH B
    PUSH B

L_07F1:
    ORA A
    JNZ L_07F7
    MVI A,$02

L_07F7:
    MOV C,A
    RST 5
    MOV B,A
    PUSH B
    PUSH H
    LHLD D_FB99
    XTHL

L_0800:
    MVI B,$81
    PUSH B
    INX SP

NEWSTT:
    CALL RCVX
    CNZ L_4028
    LDA D_F654
    ORA A
    CNZ L_402B

L_0811:
    CALL L_13F3
    SHLD SAVTXT
    XCHG
    LXI H,$0000
    DAD SP
    SHLD SAVSTK
    XCHG
    MOV A,M
    CPI $3A
    JZ GONE
    ORA A
    JNZ SNERR
    INX H

GONE4:
    MOV A,M
    INX H
    ORA M
    JZ PRGEND
    INX H
    MOV E,M
    INX H
    MOV D,M
    XCHG
    SHLD CURLIN

NOTTRC:
    XCHG

GONE:
    RST 2
    LXI D,NEWSTT
    PUSH D

GONE3:
    RZ

GONE2:
    SUI $80
    JC ST_LET
    CPI $40
    JNC L_10F4
    RLC
    MOV C,A
    MVI B,$00
    XCHG
    LXI H,STMDSP
    DAD B
    MOV C,M
    INX H
    MOV B,M
    PUSH B
    XCHG

CHRGTR:
    INX H

CHRGT2:
    MOV A,M
    CPI $3A
    RNC

CHRCON:
    CPI $20
    JZ CHRGTR
    CPI $0B
    JNC NOTLFT

NOTCON:
    CPI $09
    JNC CHRGTR

NOTLFT:
    CPI $30
    CMC
    INR A
    DCR A
    RET
