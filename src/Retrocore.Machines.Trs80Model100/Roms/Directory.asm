;; MODEL 100 ROM: INSERTING AND DELETING IN RAM FILES, THE ROM'S DIRECTORY AND BASIC'S ENTRY
;;
;; Runs at $6B61-$6CD5. Model100.asm describes the ROM as a whole and how it is named.

INSCHR:
    LXI B,$0001
    PUSH PSW
    CALL MAKHOL
    POP B
    RC
    MOV M,B
    INX H
    RET

MAKHOL:
    XCHG
    LHLD STREND
    DAD B
    RC
    MVI A,$88
    SUB L
    MOV L,A
    MVI A,$FF
    SBB H
    MOV H,A
    RC
    DAD SP
    CMC
    RC

L_6B7F:
    PUSH B
    CALL L_6BC3
    LHLD STREND
    MOV A,L
    SUB E
    MOV E,A
    MOV A,H
    SBB D
    MOV D,A
    PUSH D
    MOV E,L
    MOV D,H
    DAD B
    SHLD STREND
    XCHG
    DCX D
    DCX H
    POP B
    MOV A,B
    ORA C
    CNZ L_6BE6
    INX H
    POP B
    RET

MASDEL:
    MOV A,B
    ORA C
    RZ
    PUSH H
    PUSH B
    PUSH H
    DAD B
    XCHG
    LHLD STREND
    XCHG
    MOV A,E
    SUB L
    MOV C,A
    MOV A,D
    SBB H
    MOV B,A
    POP D
    MOV A,B
    ORA C
    CNZ L_6BDB
    XCHG
    SHLD STREND
    POP B
    XRA A
    SUB C
    MOV C,A
    SBB A
    SUB B
    MOV B,A
    POP H

L_6BC3:
    PUSH H
    LHLD COSTRT
    DAD B
    SHLD COSTRT
    LHLD VARTAB
    DAD B
    SHLD VARTAB
    LHLD ARYTAB
    DAD B
    SHLD ARYTAB
    POP H
    RET

L_6BDB:
    MOV A,M
    STAX D
    INX H
    INX D
    DCX B
    MOV A,B
    ORA C
    JNZ L_6BDB
    RET

L_6BE6:
    MOV A,M
    STAX D
    DCX H
    DCX D
    DCX B
    MOV A,B
    ORA C
    JNZ L_6BE6
    RET

ROMDIR:
    .byte $B0, "IlBASIC  ", $00, $B0, $EE, $5D, $54, $45
    .byte "XT   ", $00, $B0, "FQTELCOM "
    .byte $00, $B0, "h[ADDRSS ", $00, $B0, $6F, $5B, $53
    .byte "CHEDL ", $00, $88, $00, $00, $00

.if MODEL = 100
L_6C2C:
    .byte "Suzuki ", $C8, $00, $00, $00

L_6C37:
    .byte "HayashiH", $00, $00, $00

L_6C42:
    .byte "RickY "
.else
L_6C2C:
    .byte $32, $FB, $FF, $C3, $82, $76, $20, $C8, $00, $00, $00

L_6C37:
    .byte $C5, $CD, $DD, $26, $C1, $C9, $69, $48, $00, $00, $00

L_6C42:
    .byte $32, $09, $F8, $C3, $8D, $21
.endif

    .byte $20

BASIC:
    CALL L_6C7F
    CALL L_7EA6
    LXI H,$F999
    SHLD D_FA8C
    LHLD D_F99A
    SHLD TXTTAB

L_6C5B:
    CALL L_6C9C
    CALL FNKSB
    XRA A
    STA D_F650
    INR A
    STA D_FAAD
    LXI H,D_6C78
    SHLD D_F88A
    CALL LINKER
    CALL L_3F28
    JMP READY

D_6C78:
    .byte "llist", $0D, $00

L_6C7F:
    LHLD VARTAB
    LXI B,$0178
    DAD B
    XCHG
    LHLD MEMSIZ
    RST 3
    JC L_6C8F
    DCR H

L_6C8F:
    SHLD STKTOP
    RET

L_6C93:
    LXI H,$F789
    LXI D,$F80A
    JMP L_6CA2

L_6C9C:
    LXI H,$F80A
    LXI D,$F789

L_6CA2:
    MVI B,$80
    JMP L_2542

L_6CA7:
    DCX H
    RST 2

L_6CA9:
    LDAX D
    INR A
    RZ
    PUSH H
    MVI B,$04

L_6CAF:
    LDAX D
    MOV C,A
    CALL MAKUPL
    CMP C
    INX D
    INX H
    JNZ L_6CCC
    DCR B
    JNZ L_6CAF
    POP PSW
    PUSH H
    XCHG
    MOV E,M
    INX H
    MOV D,M
    XCHG
    POP D
    XTHL
    PUSH H
    XCHG
    INR H
    DCR H
    RET

L_6CCC:
    INX D
    DCR B
    JNZ L_6CCC
    INX D
    POP H
    JMP L_6CA9
