;; MODEL 100 ROM: INLIN, THE LINE EDITOR THAT READS TYPED LINES
;;
;; Runs at $4644-$478A. Model100.asm describes the ROM as a whole and how it is named.

INLIN:
    CALL L_421A
    JNZ L_4703
    LDA CSRX
    STA D_FACA
    LXI D,BUF
    MVI B,$01

L_4655:
    CALL CHGET
    LXI H,L_4655
    PUSH H
    RC
    CPI $7F
    JZ L_46A0
    CPI $20
    JNC L_46CC
    LXI H,$466D
    MVI C,$07
    JMP L_4378

INLCTL:
    DISPATCH $03, L_4684
    DISPATCH $08, L_46A0
    DISPATCH $09, L_46CA
    DISPATCH $0D, L_4696
    DISPATCH $15, L_46C3
    DISPATCH $18, L_46C3
    DISPATCH $1D, L_46A0

L_4684:
    POP H
    MVI A,$5E
    RST 4
    MVI A,$43
    RST 4
    CALL CRLF
    LXI H,BUF
    MVI M,$00
    DCX H
    STC
    RET

L_4696:
    POP H
    CALL CRLF
    XRA A
    STAX D

.if MODEL = 100
    LXI H,BUFMIN
.else
    JMP L_7FFA
.endif

    RET

L_46A0:
    MOV A,B
    DCR A
    STC
    RZ
    DCR B
    DCX D
    CALL L_46D8

L_46A9:
    PUSH PSW
    MVI A,$7F
    RST 4
    LHLD CSRY
    DCR L
    DCR H
    MOV A,H
    ORA L
    JZ L_46C0
    LXI H,CSRX
    POP PSW
    CMP M
    JNZ L_46A9
    RET

L_46C0:
    POP PSW
    STC
    RET

L_46C3:
    CALL L_46A0
    JNC L_46C3
    RET

L_46CA:
    MVI A,$09

L_46CC:
    INR B
    JZ L_46D4
    RST 4
    STAX D
    INX D
    RET

L_46D4:
    DCR B
    JMP ST_BEEP

L_46D8:
    PUSH B
    LDA D_FACA
    DCR B
    JZ L_4701
    MOV C,A
    LXI H,BUF

L_46E4:
    INR C
    MOV A,M
    CPI $09
    JNZ L_46F2
    MOV A,C
    DCR A
    ANI $07
    JNZ L_46E4

L_46F2:
    LDA D_F63C
    CMP C
    JNC L_46FB
    MVI C,$01

L_46FB:
    INX H
    DCR B
    JNZ L_46E4
    MOV A,C

L_4701:
    POP B
    RET

L_4703:
    LHLD D_FC8C
    PUSH H
    INX H
    INX H
    INX H
    INX H
    MOV A,M
    SUI $F8
    JNZ L_4728
    MOV L,A
    MOV H,A
    SHLD D_FC8C
    LXI H,$FAC4
    INR M
    MOV A,M
    RRC
    CNC ENTREV
    LXI H,D_5593
    CALL STROUT
    CALL EXTREV

L_4728:
    POP H
    SHLD D_FC8C
    MVI B,$00
    LXI H,BUF

L_4731:
    XRA A
    STA D_FAA2
    STA D_FAA3
    CALL L_4E7A
    JC L_4759
    MOV M,A
    CPI $0D
    JZ L_4753
    CPI $09
    JZ L_474E
    CPI $20
    JC L_4731

L_474E:
    INX H
    DCR B
    JNZ L_4731

L_4753:
    XRA A
    MOV M,A
    LXI H,BUFMIN
    RET

L_4759:
    MOV A,B
    ANA A
    JNZ L_4753
    LDA D_FCA7
    ANI $80
    STA D_FCA7
    CALL L_4F45
    MVI A,$0D
    RST 4
    CALL ERAEOL
    LDA D_FC92
    ANA A
    JZ L_477C
    CALL L_3F28
    JMP NEWSTT

L_477C:
    LDA D_F651
    ANA A
    JNZ L_5EBA
    JMP L_0501

L_4786:
    DCX H
    RST 2
    RZ
    RST 1
    .byte $2C                           ; SYNCHR: ','
