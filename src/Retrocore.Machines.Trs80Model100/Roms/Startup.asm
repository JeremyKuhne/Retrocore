;; MODEL 100 ROM: THE COLD START, THE POWER-UP MESSAGES AND MAX
;;
;; Runs at $7D33-$7FFF. Model100.asm describes the ROM as a whole and how it is named.


.if MODEL = 100
COLD:
    DI
    LXI SP,$FCC0
    LXI H,$2710

L_7D3A:
    DCX H
    MOV A,H
    ORA L
    JNZ L_7D3A
.else
COLD:
    LXI SP,$FCC0
    DCR A
    JNZ L_1BA8

L_7D3A:
    IN $D8
    ANA A
    JP L_7D3A
.endif

    MVI A,$43
    OUT $B8
    MVI A,$EC
    OUT $BA
    MVI A,$FF
    OUT $B9
    IN $E8
    ANI $82
    MVI A,$ED
    OUT $BA
    JZ L_7DE7
    LHLD D_F5F0
    LXI D,$8A4D
    RST 3
    JNZ L_7DE7
    LDA D_FAC1
    MOV D,A
    CALL L_7EE1
    CMP D
    JNZ L_7DE7
    CALL D_F605
    MVI A,$00
    JNZ L_7D75
    DCR A

L_7D75:
    LXI H,$F62A
    CMP M
    JNZ L_7DE7
    LHLD D_F5F2
    XCHG
    LXI H,$0000
    SHLD D_F5F2
    LXI H,$9C0B
    RST 3
    JNZ L_7DA8
    LHLD D_FABE
    SPHL
    CALL D_F5F6
    CALL L_7DD0
    LHLD D_FFF8
    PUSH H
    CALL L_4601
    POP H
    MOV A,H
    ANA A
    JZ L_14ED
    SPHL
    JMP L_7435

L_7DA8:
    LDA D_F651
    ANA A
    JZ L_7DBB
    CALL L_7DD0
    CALL L_5D53
    CALL L_4601
    JMP L_5FDD

L_7DBB:
    LXI H,$FAAF
    SHLD D_F62C
    LHLD STKTOP
    SPHL
    CALL D_F5F6
    CALL L_3F6D
    LXI H,MENU
    PUSH H
    .byte $F6                           ; ORI: skips the next byte

L_7DD0:
    XRA A
    CALL IOINIT
    XRA A
    STA D_F656
    LDA D_FF43
    ANA A
    RZ
    LXI H,$F65A
    RST 2
    CNC L_3457
    JMP SETSER

L_7DE7:
    LXI SP,$F5E6
    CALL L_7EE1
    MVI B,$90
    LXI D,$F5F0
    LXI H,RAMIMG
    CALL L_2542
    CALL L_7EC6
    MVI A,$0C
    STA D_F930
    MVI A,$64
    STA D_F931
    LXI H,D_5B46
    CALL STFNK
    CALL L_6C93
    MVI B,$58
    LXI D,ROMDIR
    LXI H,DIRTBL
    CALL L_3469
    MVI B,$D1
    XRA A

L_7E1C:
    MOV M,A
    INX H
    DCR B
    JNZ L_7E1C
    MVI M,$FF
    CALL D_F605
    JNZ L_7E43
    DCR A
    STA D_F62A
    LXI H,$F9BA
    MVI M,$F0
    INX H
    INX H
    INX H
    LXI D,$FAA6
    MVI B,$06
    CALL L_3469
    MVI M,$20
    INX H
    MVI M,$00

L_7E43:
    XRA A
    STA D_F787
    STA D_FCA7
    CALL L_1A96
    STA D_F932
    MVI A,$3A
    STA D_F680
    LXI H,$FBD4
    SHLD D_FBD9
    SHLD STKTOP
    SHLD MEMSIZ
    MVI A,$01
    STA D_FBB3
    CALL L_7F2B
    CALL L_3F6D
    LHLD D_FAC0
    XRA A
    MOV M,A
    INX H
    SHLD TXTTAB
    SHLD D_F99A
    MOV M,A
    INX H
    MOV M,A
    INX H
    SHLD DOSTRT
    SHLD D_F9A5
    MVI M,$1A
    INX H
    SHLD COSTRT
    SHLD VARTAB
    LXI H,$F999
    SHLD D_FA8C
    CALL L_20FF
    CALL INITIO
    LXI H,$0000
    SHLD D_F92D
    LXI H,D_7F01
    CALL L_732A
    JMP MENU

L_7EA6:
    LXI H,D_7FA4
    CALL STROUT

L_7EAC:
    LHLD VARTAB
    XCHG
    LHLD STKTOP
    MOV A,L
    SUB E
    MOV L,A
    MOV A,H
    SBB D
    MOV H,A
    LXI B,$FFF2
    DAD B
    CALL L_39D4
    LXI H,D_7F98
    JMP STROUT

L_7EC6:
    LXI H,$FADA
    LXI B,$1D02
    LXI D,$7FF3

L_7ECF:
    MOV M,E
    INX H
    MOV M,D
    INX H
    DCR B
    JNZ L_7ECF
    MVI B,$13
    LXI D,FCERR
    DCR C
    JNZ L_7ECF
    RET

L_7EE1:
    LXI H,$C000

L_7EE4:
    MOV A,M
    CMA
    MOV M,A
    CMP M
    CMA
    MOV M,A
    MOV A,H
    JNZ L_7EF8
    INR L
    JNZ L_7EE4
    SUI $20
    MOV H,A
    JM L_7EE4

L_7EF8:
    MVI L,$00
    ADI $20
    MOV H,A
    SHLD D_FAC0
    RET

D_7F01:
    .byte $00, $00, $00, $00, $00, $00, $01, $00, $00, $01

ST_MAX:
    RST 1
    .byte $9D                           ; SYNCHR: the FILES token
    RST 1
    .byte $DD                           ; SYNCHR: the = token
    CALL GETBYT
    JNZ SNERR
    CPI $10
    JNC FCERR
    SHLD D_FB99
    PUSH PSW
    CALL L_4E22
    POP PSW
    CALL L_7F2B
    CALL L_3F2F
    JMP NEWSTT

L_7F2B:
    PUSH PSW
    LHLD D_F5F4
    LXI D,$FEF5

L_7F32:
    DAD D
    DCR A
    JP L_7F32
    XCHG
    LHLD STKTOP
    MOV B,H
    MOV C,L
    LHLD MEMSIZ
    MOV A,L
    SUB C
    MOV L,A
    MOV A,H
    SBB B
    MOV H,A
    POP PSW
    PUSH H
    PUSH PSW
    LXI B,$008C
    DAD B
    MOV B,H
    MOV C,L
    LHLD VARTAB
    DAD B
    RST 3
    JNC L_3F17
    POP PSW
    STA D_FC82
    MOV L,E
    MOV H,D
    SHLD D_FC83
    DCX H
    DCX H
    SHLD MEMSIZ
    POP B
    MOV A,L
    SUB C
    MOV L,A
    MOV A,H
    SBB B
    MOV H,A
    SHLD STKTOP
    DCX H
    DCX H
    POP B
    SPHL
    PUSH B
    LDA D_FC82
    MOV L,A
    INR L
    MVI H,$00
    DAD H
    DAD D
    XCHG
    PUSH D
    LXI B,$0109

L_7F82:
    MOV M,E
    INX H
    MOV M,D
    INX H
    XCHG
    MVI M,$00
    DAD B
    XCHG
    DCR A
    JP L_7F82
    POP H
    LXI B,$0009
    DAD B
    SHLD D_FC87
    RET

D_7F98:
    .byte " Bytes free", $00

D_7FA4:
    .byte "TRS-80 Model 100"
    .byte " Software", $0D, $0A, "Copr."
    .byte " 1983 Microsoft", $0D
    .byte $0A, $00

HOOK:
    XTHL
    PUSH PSW
    MOV A,M
    STA D_FAC9
    POP PSW
    INX H
    XTHL
    PUSH H
    PUSH B
    PUSH PSW
    LXI H,$FADA
    LDA D_FAC9
    MOV C,A
    MVI B,$00
    DAD B
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    POP PSW
    POP B
    XTHL
    RET

L_7FF4:
    CALL FN_CDBL
    JMP L_31B5

.if MODEL = 100
L_7FFA:
    .byte $00, $00, $00, $00, $00, $00
.else
L_7FFA:
    LXI H,BUFMIN
    MVI M,$2C
    RET
.endif

