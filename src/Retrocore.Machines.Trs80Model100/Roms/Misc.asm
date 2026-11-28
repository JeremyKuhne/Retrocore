;; MODEL 100 ROM: BLTU AND GETSTK, THE ON COM AND ON TIME$ INTERRUPT STATES, RESTORE, STOP, END, CONT, CLEAR AND NEXT
;;
;; Runs at $3EF0-$4221. Model100.asm describes the ROM as a whole and how it is named.

L_3EF0:
    CALL L_3F08

L_3EF3:
    PUSH B
    XTHL
    POP B

L_3EF6:
    RST 3
    MOV A,M
    STAX B
    RZ
    DCX B
    DCX H
    JMP L_3EF6

L_3EFF:
    PUSH H
    LHLD STREND
    MVI B,$00
    DAD B
    DAD B
    .byte $3E                           ; MVI A,$E5: skips the next byte

L_3F08:
    PUSH H
    MVI A,$88
    SUB L
    MOV L,A
    MVI A,$FF
    SBB H
    MOV H,A
    JC L_3F17
    DAD SP
    POP H
    RC

L_3F17:
    CALL LINKER
    LHLD STKTOP
    DCX H
    DCX H
    SHLD SAVSTK
    LXI D,$0007
    JMP ERROR

L_3F28:
    LHLD TXTTAB
    DCX H

L_3F2C:
    SHLD D_FB99

L_3F2F:
    CALL L_4009
    MVI B,$1A
    LXI H,$FBBA

L_3F37:
    MVI M,$08
    INX H
    DCR B
    JNZ L_3F37
    CALL L_3182
    XRA A
    STA ONEFLG
    MOV L,A
    MOV H,A
    SHLD ONELIN
    SHLD OLDTXT
    LHLD MEMSIZ
    SHLD FRETOP
    CALL ST_RESTORE
    LHLD VARTAB
    SHLD ARYTAB
    SHLD STREND
    CALL L_4E22
    LDA D_FCA7
    ANI $01
    JNZ L_3F6D
    STA D_FCA7

L_3F6D:
    POP B
    LHLD STKTOP
    DCX H
    DCX H
    SHLD SAVSTK
    INX H
    INX H

L_3F78:
    SPHL
    LXI H,$FB6B
    SHLD TEMPPT
    CALL L_4B92
    CALL FINPRT
    XRA A
    MOV H,A
    MOV L,A
    SHLD D_FBD6
    STA D_FBE1
    SHLD D_FBDB
    SHLD D_FBE4
    SHLD D_FBD4
    STA D_FB96
    PUSH H
    PUSH B

L_3F9C:
    LHLD D_FB99
    RET

L_3FA0:
    DI
    MOV A,M
    ANI $04
    ORI $01
    CMP M
    MOV M,A
    JZ L_3FB0
    ANI $04
    JNZ L_3FE8

L_3FB0:
    EI
    RET

L_3FB2:
    DI
    MOV A,M
    MVI M,$00
    JMP L_3FC0

L_3FB9:
    DI
    MOV A,M
    PUSH PSW
    ORI $02
    MOV M,A
    POP PSW

L_3FC0:
    XRI $05
    JZ L_3FFC
    EI
    RET

L_3FC7:
    DI
    MOV A,M
    ANI $05
    CMP M
    MOV M,A
    JNZ L_3FE1
    EI
    RET

L_3FD2:
    DI
    MOV A,M
    ANI $01
    JZ L_3FE6
    MOV A,M
    ORI $04
    CMP M
    JZ L_3FE6
    MOV M,A

L_3FE1:
    XRI $05
    JZ L_3FE8

L_3FE6:
    EI
    RET

L_3FE8:
    LDA D_F654
    INR A
    STA D_F654
    EI
    RET

L_3FF1:
    DI
    MOV A,M
    ANI $03
    CMP M
    MOV M,A
    JNZ L_3FFC

L_3FFA:
    EI
    RET

L_3FFC:
    LDA D_F654
    SUI $01
    JC L_3FFA
    STA D_F654
    EI
    RET

L_4009:
    LXI H,$F944
    MVI B,$0A
    XRA A

L_400F:
    MOV M,A
    INX H
    MOV M,A
    INX H
    MOV M,A
    INX H
    DCR B
    JNZ L_400F
    LXI H,$F630
    MVI B,$08

L_401E:
    MOV M,A
    INX H
    DCR B
    JNZ L_401E
    STA D_F654
    RET

L_4028:
    MVI B,$02
    .byte $11                           ; LXI D,$0106: skips the next two bytes

L_402B:
    MVI B,$01
    LDA ONEFLG
    ORA A
    RNZ
    PUSH H
    LHLD CURLIN
    MOV A,H
    ANA L
    INR A
    JZ L_4052
    DCR B
    JNZ L_4075
    LXI H,$F947
    MVI B,$09

L_4045:
    MOV A,M
    CPI $05
    JZ L_4054

L_404B:
    INX H
    INX H
    INX H
    DCR B
    JNZ L_4045

L_4052:
    POP H
    RET

L_4054:
    PUSH B
    INX H
    MOV E,M
    INX H
    MOV D,M
    DCX H
    DCX H
    MOV A,D
    ORA E
    POP B
    JZ L_404B
    PUSH D
    PUSH H
    CALL L_3FF1
    CALL L_3FB9
    MVI C,$03
    CALL L_3EFF
    POP B
    POP D
    POP H
    POP PSW
    JMP L_0952

L_4075:
    LXI H,$F944
    MOV A,M
    DCR A
    JZ L_4054
    POP H
    RET

ST_RESTORE:
    XCHG
    LHLD TXTTAB
    JZ L_4094
    XCHG
    CALL LINGET
    PUSH H
    CALL FNDLIN
    MOV H,B
    MOV L,C
    POP D
    JNC L_094D

L_4094:
    DCX H

L_4095:
    SHLD DATPTR
    XCHG
    RET

ST_STOP:
    RNZ
    INR A
    JMP CONSTP

ST_END:
    RNZ
    XRA A
    STA ONEFLG
    PUSH PSW
    CZ L_4E22
    POP PSW

CONSTP:
    SHLD SAVTXT
    LXI H,$FB6B
    SHLD TEMPPT
    .byte $21                           ; LXI H,$FFF6: skips the next two bytes

STPEND:
    ORI $FF
    POP B

ENDCON:
    LHLD CURLIN
    PUSH H
    PUSH PSW
    MOV A,L
    ANA H
    INR A
    JZ DIRIS
    SHLD OLDLIN
    LHLD SAVTXT
    SHLD OLDTXT

DIRIS:
    CALL L_4B92
    CALL L_4BB8
    POP PSW
    LXI H,$03FB
    JNZ L_04F6
    JMP L_0501

ST_CONT:
    LHLD OLDTXT
    MOV A,H
    ORA L
    LXI D,$0011
    JZ ERROR
    XCHG
    LHLD OLDLIN
    SHLD CURLIN
    XCHG
    RET

L_40EE:
    JMP FCERR

L_40F1:
    MOV A,M

L_40F2:
    CPI $41
    RC
    CPI $5B
    CMC
    RET

ST_CLEAR:
    PUSH H
    CALL L_2262
    POP H
    DCX H
    RST 2
    JZ L_3F2C
    RST 7
    .byte $00                           ; the hook's offset in the table at $FADA
    CALL INTID2
    DCX H
    RST 2
    PUSH H
    LHLD D_F5F4
    MOV B,H
    MOV C,L
    LHLD MEMSIZ
    JZ L_4140
    POP H
    RST 1
    .byte $2C                           ; SYNCHR: ','
    PUSH D
    CALL FRMQNT
    DCX H
    RST 2
    JNZ SNERR
    XTHL
    XCHG
    MOV A,H
    ANA A
    JP FCERR
    PUSH D
    LXI D,$F5F1
    RST 3
    JNC FCERR
    POP D
    PUSH H
    LXI B,$FEF5
    LDA D_FC82

L_4139:
    DAD B
    DCR A
    JP L_4139
    POP B
    DCX H

L_4140:
    MOV A,L
    SUB E
    MOV E,A
    MOV A,H
    SBB D
    MOV D,A
    JC L_3F17
    PUSH H
    LHLD VARTAB
    PUSH B
    LXI B,$00A0
    DAD B
    POP B
    RST 3
    JNC L_3F17
    XCHG
    SHLD STKTOP
    MOV H,B
    MOV L,C
    SHLD D_F5F4
    POP H
    SHLD MEMSIZ
    POP H
    CALL L_3F2C
    LDA D_FC82
    CALL L_7F2B
    LHLD D_FB99
    JMP NEWSTT

ST_NEXT:
    LXI D,$0000

L_4177:
    CNZ L_4790
    SHLD D_FB99
    CALL FNDFOR
    JNZ NFERR
    SPHL
    PUSH D
    MOV A,M
    PUSH PSW
    INX H
    PUSH D
    MOV A,M
    INX H
    ORA A
    JM L_41BB
    DCR A
    JNZ L_4197
    LXI B,$0008
    DAD B

L_4197:
    ADI $04
    STA VALTYP
    CALL L_347E
    XCHG
    XTHL
    PUSH H
    RST 5
    JNC L_41F6
    CALL L_3447
    CALL L_37F4
    POP H
    CALL L_3459
    POP H
    CALL L_3450
    PUSH H
    CALL L_3498
    JMP L_41E4

L_41BB:
    LXI B,$000C
    DAD B
    MOV C,M
    INX H
    MOV B,M
    INX H
    XTHL
    MOV E,M
    INX H
    MOV D,M
    PUSH H
    MOV L,C
    MOV H,B
    CALL L_3704
    LDA VALTYP
    CPI $02
    JNZ OVERR
    XCHG
    POP H
    MOV M,D
    DCX H
    MOV M,E
    POP H
    PUSH D
    MOV E,M
    INX H
    MOV D,M
    INX H
    XTHL
    CALL L_34C2

L_41E4:
    POP H
    POP B
    SUB B
    CALL L_3450
    JZ L_4208
    XCHG
    SHLD CURLIN
    MOV L,C
    MOV H,B
    JMP L_0800

L_41F6:
    CALL L_2B75
    POP H
    CALL L_3487
    POP H
    CALL L_3461
    PUSH D
    CALL L_34D2
    JMP L_41E4

L_4208:
    SPHL
    SHLD SAVSTK
    XCHG
    LHLD D_FB99
    MOV A,M
    CPI $2C
    JNZ NEWSTT
    RST 2
    CALL L_4177

L_421A:
    PUSH H
    LHLD D_FC8C
    MOV A,H
    ORA L
    POP H
    RET
