;; MODEL 100 ROM: CHARACTER OUTPUT TO THE SCREEN, THE PRINTER AND FILES, INKEY$, FILE NAMES AND FILE NUMBERS
;;
;; Runs at $4B44-$4CCA. Model100.asm describes the ROM as a whole and how it is named.

LCD:
    PUSH PSW
    PUSH H
    CALL L_421A
    JNZ L_4E52
    POP H
    LDA PRTFLG
    ORA A
    JZ L_4BAA
    POP PSW

PRTTAB:
    PUSH PSW
    CPI $09
    JNZ L_4B6A

L_4B5B:
    MVI A,$20
    CALL PRTTAB
    LDA LPTPOS
    ANI $07
    JNZ L_4B5B
    POP PSW
    RET

L_4B6A:
    SUI $0D
    JZ L_4B76
    JC L_4B79
    LDA LPTPOS
    INR A

L_4B76:
    STA LPTPOS

L_4B79:
    POP PSW

L_4B7A:
    CPI $0A
    JNZ L_4B88
    PUSH B
    MOV B,A
    LDA D_FAAC
    CPI $0D
    MOV A,B
    POP B

L_4B88:
    STA D_FAAC
    RZ
    CPI $1A
    RZ
    JMP PNOTAB

L_4B92:
    XRA A
    STA PRTFLG
    LDA LPTPOS
    ORA A
    RZ
    LDA D_FACD
    ORA A
    RZ

L_4BA0:
    MVI A,$0D
    CALL L_4B7A
    XRA A
    STA LPTPOS
    RET

L_4BAA:
    POP PSW
    PUSH PSW
    CALL L_4313
    LDA CSRX
    DCR A
    STA TTYPOS
    POP PSW
    RET

L_4BB8:
    LDA CSRX
    DCR A
    RZ
    JMP L_4BCB

L_4BC0:
    MVI M,$00
    CALL L_421A
    LXI H,BUFMIN
    JNZ L_4BD1

L_4BCB:
    MVI A,$0D
    RST 4
    MVI A,$0A
    RST 4

L_4BD1:
    CALL L_421A
    JZ L_4BD9
    XRA A
    RET

L_4BD9:
    LDA PRTFLG
    ORA A
    JZ L_4BE5
    XRA A
    STA LPTPOS
    RET

L_4BE5:
    XRA A
    STA TTYPOS
    RET

FN_INKEY:
    RST 2
    PUSH H
    CALL CHSNS
    JZ L_4BFE
    CALL CHGET
    PUSH PSW
    CALL STRIN1
    POP PSW
    MOV E,A
    CALL SETSTR

L_4BFE:
    LXI H,$03F5
    SHLD D_FC1A
    MVI A,$03
    STA VALTYP
    POP H
    RET

L_4C0B:
    PUSH H
    JMP L_4C21

L_4C0F:
    CALL FRMEVL
    PUSH H
    CALL FRESTR
    MOV A,M
    ORA A
    JZ L_4C55
    INX H
    MOV E,M
    INX H
    MOV H,M
    MOV L,E
    MOV E,A

L_4C21:
    CALL L_5075
    PUSH PSW
    LXI B,FILNAM
    MVI D,$09
    INR E

L_4C2B:
    DCR E
    JZ L_4C72
    CALL MAKUPL
    CPI $20
    JC L_4C55
    CPI $7F
    JZ L_4C55
    CPI $2E
    JZ L_4C5C
    STAX B
    INX B
    INX H
    DCR D
    JNZ L_4C2B

L_4C48:
    POP PSW
    PUSH PSW
    MOV D,A
    LDA FILNAM
    INR A
    JZ L_4C55
    POP PSW
    POP H
    RET

L_4C55:
    JMP NMERR

L_4C58:
    INX H
    JMP L_4C2B

L_4C5C:
    MOV A,D
    CPI $09
    JZ L_4C55
    CPI $03
    JC L_4C55
    JZ L_4C58
    MVI A,$20
    STAX B
    INX B
    DCR D
    JMP L_4C5C

L_4C72:
    MVI A,$20
    STAX B
    INX B
    DCR D
    JNZ L_4C72
    JMP L_4C48

L_4C7D:
    MOV A,M
    INX H
    DCR E
    RET

L_4C81:
    CALL CONINT

L_4C84:
    MOV L,A
    LDA D_FC82
    CMP L
    JC BNERR
    MVI H,$00
    SHLD D_FAA2
    DAD H
    XCHG
    LHLD D_FC83
    DAD D
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    MOV A,M
    ORA A
    RZ
    PUSH H
    LXI D,$0004
    DAD D
    MOV A,M
    CPI $09
    JNC L_4CAE
    RST 7
    .byte $1E                           ; the hook's offset in the table at $FADA
    JMP IEERR

L_4CAE:
    POP H
    MOV A,M
    ORA A
    STC
    RET

L_4CB3:
    DCX H
    RST 2
    CPI $23
    CZ CHRGTR
    CALL GETBYT
    XTHL
    PUSH H

L_4CBF:
    CALL L_4C84
    JZ CFERR
    SHLD D_FC8C
    RST 7
    .byte $0C                           ; the hook's offset in the table at $FADA
    RET
