;; MODEL 100 ROM: DIM, THE VARIABLE SEARCH AND PRINT USING
;;
;; Runs at $478B-$4B43. Model100.asm describes the ROM as a whole and how it is named.

ST_DIM:
    LXI B,L_4786
    PUSH B
    .byte $F6                           ; ORI $AF: skips the next byte

L_4790:
    XRA A
    STA D_FB64
    MOV C,M
    CALL L_40F1
    JC SNERR
    XRA A
    MOV B,A
    RST 2
    JC L_47A7
    CALL L_40F2
    JC L_47B2

L_47A7:
    MOV B,A

L_47A8:
    RST 2
    JC L_47A8
    CALL L_40F2
    JNC L_47A8

L_47B2:
    CPI $26
    JNC L_47CE
    LXI D,L_47DC
    PUSH D
    MVI D,$02
    CPI $25
    RZ
    INR D
    CPI $24
    RZ
    INR D
    CPI $21
    RZ
    MVI D,$08
    CPI $23
    RZ
    POP PSW

L_47CE:
    MOV A,C
    ANI $7F
    MOV E,A
    MVI D,$00
    PUSH H
    LXI H,$FB79
    DAD D
    MOV D,M
    POP H
    DCX H

L_47DC:
    MOV A,D
    STA VALTYP
    RST 2
    LDA D_FB96
    DCR A
    JZ L_48BC
    JP L_47F6
    MOV A,M
    SUI $28
    JZ L_488D
    SUI $33
    JZ L_488D

L_47F6:
    XRA A
    STA D_FB96
    PUSH H
    LHLD VARTAB
    JMP L_481A

L_4801:
    LDAX D
    MOV L,A
    INX D
    LDAX D
    INX D
    CMP C
    JNZ L_4816
    LDA VALTYP
    CMP L
    JNZ L_4816
    LDAX D
    CMP B
    JZ L_4876

L_4816:
    INX D
    MVI H,$00
    DAD D

L_481A:
    XCHG
    LDA ARYTAB
    CMP E
    JNZ L_4801
    LDA D_FBB5
    CMP D
    JNZ L_4801
    JMP L_4835

L_482C:
    CALL L_4790
    RET

L_4830:
    MOV D,A
    MOV E,A
    POP B
    XTHL
    RET

L_4835:
    POP H
    XTHL
    PUSH D
    LXI D,$482F
    RST 3
    JZ L_4830
    LXI D,RETVAR
    RST 3
    POP D
    JZ L_4879
    XTHL
    PUSH H
    PUSH B
    LDA VALTYP
    MOV C,A
    PUSH B
    MVI B,$00
    INX B
    INX B
    INX B
    LHLD STREND
    PUSH H
    DAD B
    POP B
    PUSH H
    CALL L_3EF0
    POP H
    SHLD STREND
    MOV H,B
    MOV L,C
    SHLD ARYTAB

L_4867:
    DCX H
    MVI M,$00
    RST 3
    JNZ L_4867
    POP D
    MOV M,E
    INX H
    POP D
    MOV M,E
    INX H
    MOV M,D
    XCHG

L_4876:
    INX D
    POP H
    RET

L_4879:
    STA D_FC18
    MOV H,A
    MOV L,A
    SHLD D_FC1A
    RST 5
    JNZ L_488B
    LXI H,$03F5
    SHLD D_FC1A

L_488B:
    POP H
    RET

L_488D:
    PUSH H
    LHLD D_FB64
    XTHL
    MOV D,A

L_4893:
    PUSH D
    PUSH B
    CALL INTIDX
    POP B
    POP PSW
    XCHG
    XTHL
    PUSH H
    XCHG
    INR A
    MOV D,A
    MOV A,M
    CPI $2C
    JZ L_4893
    CPI $29
    JZ L_48B0
    CPI $5D
    JNZ SNERR

L_48B0:
    RST 2
    SHLD TEMP2
    POP H
    SHLD D_FB64
    MVI E,$00
    PUSH D
    .byte $11                           ; LXI D,$F5E5: skips the next two bytes

L_48BC:
    PUSH H
    PUSH PSW
    LHLD ARYTAB
    .byte $3E                           ; MVI A,$19: skips the next byte

L_48C2:
    DAD D
    XCHG
    LHLD STREND
    XCHG
    RST 3
    JZ L_48FC
    MOV E,M
    INX H
    MOV A,M
    INX H
    CMP C
    JNZ L_48DD
    LDA VALTYP
    CMP E
    JNZ L_48DD
    MOV A,M
    CMP B

L_48DD:
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    JNZ L_48C2
    LDA D_FB64
    ORA A
    JNZ DDERR
    POP PSW
    MOV B,H
    MOV C,L
    JZ L_383E
    SUB M
    JZ L_495A

L_48F6:
    LXI D,$0009
    JMP ERROR

L_48FC:
    LDA VALTYP
    MOV M,A
    INX H
    MOV E,A
    MVI D,$00
    POP PSW
    JZ FCERR
    MOV M,C
    INX H
    MOV M,B
    INX H
    MOV C,A
    CALL L_3EFF
    INX H
    INX H
    SHLD TEMP3
    MOV M,C
    INX H
    LDA D_FB64
    RAL
    MOV A,C

L_491C:
    LXI B,$000B
    JNC L_4924
    POP B
    INX B

L_4924:
    MOV M,C
    PUSH PSW
    INX H
    MOV M,B
    INX H
    CALL L_36D8
    POP PSW
    DCR A
    JNZ L_491C
    PUSH PSW
    MOV B,D
    MOV C,E
    XCHG
    DAD D
    JC L_3F17
    CALL L_3F08
    SHLD STREND

L_493F:
    DCX H
    MVI M,$00
    RST 3
    JNZ L_493F
    INX B
    MOV D,A
    LHLD TEMP3
    MOV E,M
    XCHG
    DAD H
    DAD B
    XCHG
    DCX H
    DCX H
    MOV M,E
    INX H
    MOV M,D
    INX H
    POP PSW
    JC L_498D

L_495A:
    MOV B,A
    MOV C,A
    MOV A,M
    INX H
    .byte $16                           ; MVI D,$E1: skips the next byte

L_495F:
    POP H
    MOV E,M
    INX H
    MOV D,M
    INX H
    XTHL
    PUSH PSW
    RST 3
    JNC L_48F6
    CALL L_36D8
    DAD D
    POP PSW
    DCR A
    MOV B,H
    MOV C,L
    JNZ L_495F
    LDA VALTYP
    MOV B,H
    MOV C,L
    DAD H
    SUI $04
    JC L_4985
    DAD H
    JZ L_498A
    DAD H

L_4985:
    ORA A
    JPO L_498A
    DAD B

L_498A:
    POP B
    DAD B
    XCHG

L_498D:
    LHLD TEMP2
    RET

L_4991:
    CALL FRMCHK

.if MODEL = 100
    CALL L_35D9
.else
    CALL L_7304
.endif

    RST 1
    .byte $3B                           ; SYNCHR: ';'
    XCHG
    LHLD D_FC1A
    JMP L_49A9

L_49A0:
    LDA FLGINP
    ORA A
    JZ L_49B4
    POP D
    XCHG

L_49A9:
    PUSH H
    XRA A
    STA FLGINP
    INR A
    PUSH PSW
    PUSH D
    MOV B,M
    INR B
    DCR B

L_49B4:
    JZ FCERR
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    JMP L_49DC

L_49BF:
    MOV E,B
    PUSH H
    MVI C,$02

L_49C3:
    MOV A,M
    INX H
    CPI $5C
    JZ L_4B07
    CPI $20
    JNZ L_49D4
    INR C
    DCR B
    JNZ L_49C3

L_49D4:
    POP H
    MOV B,E
    MVI A,$5C

L_49D8:
    CALL L_4B3A
    RST 4

L_49DC:
    XRA A
    MOV E,A
    MOV D,A

L_49DF:
    CALL L_4B3A
    MOV D,A
    MOV A,M
    INX H
    CPI $21
    JZ L_4B04
    CPI $23
    JZ L_4A2E
    DCR B
    JZ L_4AF0
    CPI $2B
    MVI A,$08
    JZ L_49DF
    DCX H
    MOV A,M
    INX H
    CPI $2E
    JZ L_4A4D
    CPI $5C
    JZ L_49BF
    CMP M
    JNZ L_49D8
    CPI $24
    JZ L_4A27
    CPI $2A
    JNZ L_49D8
    INX H
    MOV A,B
    CPI $02
    JC L_4A1F
    MOV A,M
    CPI $24

L_4A1F:
    MVI A,$20
    JNZ L_4A2B
    DCR B
    INR E
    .byte $FE                           ; CPI $AF: skips the next byte

L_4A27:
    XRA A
    ADI $10
    INX H

L_4A2B:
    INR E
    ADD D
    MOV D,A

L_4A2E:
    INR E
    MVI C,$00
    DCR B
    JZ L_4A83
    MOV A,M
    INX H
    CPI $2E
    JZ L_4A58
    CPI $23
    JZ L_4A2E
    CPI $2C
    JNZ L_4A64
    MOV A,D
    ORI $40
    MOV D,A
    JMP L_4A2E

L_4A4D:
    MOV A,M
    CPI $23
    MVI A,$2E
    JNZ L_49D8
    MVI C,$01
    INX H

L_4A58:
    INR C
    DCR B
    JZ L_4A83
    MOV A,M
    INX H
    CPI $23
    JZ L_4A58

L_4A64:
    PUSH D
    LXI D,L_4A81
    PUSH D
    MOV D,H
    MOV E,L
    CPI $5E
    RNZ
    CMP M
    RNZ
    INX H
    CMP M
    RNZ
    INX H
    CMP M
    RNZ
    INX H
    MOV A,B
    SUI $04
    RC
    POP D
    POP D
    MOV B,A
    INR D
    INX H
    .byte $CA                           ; JZ $D1EB: skips the next two bytes, unless it jumps

L_4A81:
    XCHG
    POP D

L_4A83:
    MOV A,D
    DCX H
    INR E
    ANI $08
    JNZ L_4AA3
    DCR E
    MOV A,B
    ORA A
    JZ L_4AA3
    MOV A,M
    SUI $2D
    JZ L_4A9E
    CPI $FE
    JNZ L_4AA3
    MVI A,$08

L_4A9E:
    ADI $04
    ADD D
    MOV D,A
    DCR B

L_4AA3:
    POP H
    POP PSW
    JZ L_4AF9
    PUSH B
    PUSH D
    CALL FRMEVL
    POP D
    POP B
    PUSH B
    PUSH H
    MOV B,E
    MOV A,B
    ADD C
    CPI $19
    JNC FCERR
    MOV A,D
    ORI $80
    CALL L_39E9
    CALL STROUT

L_4AC2:
    POP H
    DCX H
    RST 2
    STC
    JZ L_4AD7
    STA FLGINP
    CPI $3B
    JZ L_4AD6
    CPI $2C
    JNZ SNERR

L_4AD6:
    RST 2

L_4AD7:
    POP B
    XCHG
    POP H
    PUSH H
    PUSH PSW
    PUSH D
    MOV A,M
    SUB B
    INX H
    MVI D,$00
    MOV E,A
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    DAD D
    MOV A,B
    ORA A
    JNZ L_49DC
    JMP L_4AF4

L_4AF0:
    CALL L_4B3A
    RST 4

L_4AF4:
    POP H
    POP PSW
    JNZ L_49A0

L_4AF9:
    CC L_4BCB
    XTHL
    CALL FRETM2
    POP H
    JMP FINPRT

L_4B04:
    MVI C,$01
    .byte $3E                           ; MVI A,$F1: skips the next byte

L_4B07:
    POP PSW
    DCR B
    CALL L_4B3A
    POP H
    POP PSW
    JZ L_4AF9
    PUSH B
    CALL FRMEVL
    CALL L_35D9
    POP B
    PUSH B
    PUSH H
    LHLD D_FC1A
    MOV B,C
    MVI C,$00
    MOV A,B
    PUSH PSW
    CALL LEFTUS
    CALL STRPRT
    LHLD D_FC1A
    POP PSW
    SUB M
    MOV B,A
    MVI A,$20
    INR B

L_4B32:
    DCR B
    JZ L_4AC2
    RST 4
    JMP L_4B32

L_4B3A:
    PUSH PSW
    MOV A,D
    ORA A
    MVI A,$2B
    CNZ LCD
    POP PSW
    RET
