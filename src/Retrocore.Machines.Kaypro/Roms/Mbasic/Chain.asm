;; MBASIC 5.21: WHILE, WEND, CALL, CHAIN AND WRITE
;;
;; Part of Mbasic.asm.

ST_WHILE:
    LD [ENDFOR],HL
    CALL L_24DD
    CALL CHRGTR
    EX DE,HL
    CALL L_4CC1
    INC SP
    INC SP
    JP NZ,L_4C6F
    ADD HL,BC
    LD SP,HL
    LD [SAVSTK],HL
L_4C6F:
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[ENDFOR]
    PUSH HL
    PUSH DE
    JP L_4CA1
ST_WEND:
    JP NZ,SNERR
    EX DE,HL
    CALL L_4CC1
    JP NZ,L_4CEB
    LD SP,HL
    LD [SAVSTK],HL
    EX DE,HL
    LD HL,[CURLIN]
    EX DE,HL
    EX DE,HL
    LD [D_0BC4],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD [CURLIN],HL
    EX DE,HL
L_4CA1:
    CALL L_1A02
    PUSH HL
    CALL L_2886
    POP HL
    JP Z,L_4CB5
    LD BC,$00B4
    LD B,C
    PUSH BC
    INC SP
    JP NEWSTT
L_4CB5:
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    POP HL
    POP BC
    POP BC
    JP NEWSTT
L_4CC1:
    LD HL,$0004
    ADD HL,SP
L_4CC5:
    LD A,[HL]
    INC HL
    LD BC,$0082
    CP C
    JP NZ,L_4CD5
    LD BC,$0010
    ADD HL,BC
    JP L_4CC5
L_4CD5:
    LD BC,$00B4
    CP C
    RET NZ
    PUSH HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CALL L_43CD
    POP HL
    LD BC,$0006
    RET Z
    ADD HL,BC
    .byte $C3
L_4CE9:
    PUSH BC
    LD C,H
L_4CEB:
    LD DE,$001E
    JP ERROR
ST_CALL:
    LD A,$80
    LD [SUBFLG],A
    CALL L_398B
    PUSH HL
    EX DE,HL
    CALL L_1D64
    CALL L_28EE
    CALL L_22DB
    LD [D_0BE6],HL
    LD C,$20
    CALL L_42C7
    POP DE
    LD HL,$FFC0
    ADD HL,SP
    LD SP,HL
    EX DE,HL
    LD C,$20
    DEC HL
    CALL CHRGTR
    LD [TEMP],HL
    JP Z,L_4D5F
    CALL L_43D3
    .byte $28
L_4D23:
    .byte $C5
    PUSH DE
    CALL L_398B
    EX [SP],HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    EX [SP],HL
    POP DE
    POP BC
    LD A,[HL]
    CP $2C
    JP NZ,L_4D3D
    DEC C
    CALL CHRGTR
    JP L_4D23
L_4D3D:
    CALL L_43D3
    ADD HL,HL
    LD [TEMP],HL
    LD A,$21
    SUB C
    POP HL
    DEC A
    JP Z,L_4D5F
    POP DE
    DEC A
    JP Z,L_4D5F
    POP BC
    DEC A
    JP Z,L_4D5F
    PUSH BC
    PUSH HL
    LD HL,$0002
    ADD HL,SP
    LD B,H
    LD C,L
    POP HL
L_4D5F:
    PUSH HL
    LD HL,$4D6A
    EX [SP],HL
    PUSH HL
    LD HL,[D_0BE6]
    EX [SP],HL
    RET
    .byte $2A, $B1, $0A, $F9, $2A, $A7, $0A, $C3, $A0, $12
ST_CHAIN:
    XOR A
    LD [D_0BED],A
    LD [D_0BEE],A
    LD A,[HL]
    LD DE,$00C5
    CP E
    JP NZ,L_4D87
    LD [D_0BED],A
    INC HL
L_4D87:
    DEC HL
    CALL CHRGTR
    CALL L_5294
    PUSH HL
    LD HL,$0000
    LD [D_0BF4],HL
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E07
    CALL L_43D3
    INC L
    CP $2C
    JP Z,L_4DB8
    CALL L_1A02
    PUSH HL
    CALL L_22DB
    LD [D_0BF4],HL
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E07
L_4DB8:
    CALL L_43D3
    INC L
    LD DE,$00AA
    CP E
    JP Z,L_4DDB
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD C,H
    CALL L_43D3
    LD C,H
    JP Z,L_4F4E
    CALL L_43D3
    INC L
    CP E
    JP NZ,SNERR
    OR A
L_4DDB:
    PUSH AF
    LD [D_0BEE],A
    CALL CHRGTR
    CALL L_0ED8
    PUSH BC
    CALL L_2435
    POP BC
    POP DE
    PUSH BC
    LD H,B
    LD L,C
    LD [D_0BF1],HL
    CALL L_0EF8
    JP NC,L_4E00
    LD D,H
    LD E,L
    LD [D_0BEF],HL
    POP HL
    CALL L_43CD
L_4E00:
    JP NC,L_1418
    POP AF
    JP NZ,L_4F4E
L_4E07:
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[TXTTAB]
    DEC HL
L_4E0F:
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,L_4ECF
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL
    EX DE,HL
L_4E1F:
    CALL CHRGTR
L_4E22:
    OR A
    JP Z,L_4E0F
    CP $3A
    JP Z,L_4E1F
    LD DE,$00B8
    CP E
    JP Z,L_4E3C
    CALL CHRGTR
    CALL ST_DATA
    DEC HL
    JP L_4E1F
L_4E3C:
    CALL CHRGTR
    JP Z,L_4E22
L_4E42:
    PUSH HL
    LD A,$01
    LD [SUBFLG],A
    CALL L_3A89
    JP Z,L_4EA2
    LD A,B
    OR $80
    LD B,A
    XOR A
    CALL L_3B92
    LD A,$00
    LD [SUBFLG],A
    JP NZ,L_4E68
    LD A,[HL]
    CP $28
    JP NZ,L_4E6E
    POP AF
    JP L_4EBE
L_4E68:
    LD A,[HL]
    CP $28
    JP Z,L_1418
L_4E6E:
    POP HL
    CALL L_3A89
    LD A,D
    OR E
    JP NZ,L_4E8F
    LD A,B
    OR $80
    LD B,A
    LD DE,$4E8A
    PUSH DE
    LD DE,$3A8C
    PUSH DE
    LD A,[D_0A67]
    LD D,A
    JP L_3A29
    .byte $7A, $B3, $CA, $18, $14
L_4E8F:
    PUSH HL
    LD B,D
    LD C,E
    LD HL,$4EB1
    PUSH HL
L_4E96:
    DEC BC
L_4E97:
    LD A,[BC]
    DEC BC
    OR A
    JP M,L_4E97
    LD A,[BC]
    OR $80
    LD [BC],A
    RET
L_4EA2:
    LD [SUBFLG],A
    LD A,[HL]
    CP $28
    JP NZ,L_4E6E
    EX [SP],HL
    DEC BC
    DEC BC
    CALL L_4E96
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_4E22
    CP $28
    JP NZ,L_4EC8
L_4EBE:
    CALL CHRGTR
    CALL L_43D3
    ADD HL,HL
    JP Z,L_4E22
L_4EC8:
    CALL L_43D3
    INC L
    JP L_4E42
L_4ECF:
    POP HL
    LD [CURLIN],HL
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    LD HL,[VARTAB]
L_4EDB:
    CALL L_43CD
    JP Z,L_4F23
    PUSH HL
    LD C,[HL]
    INC HL
    INC HL
    LD A,[HL]
    OR A
    PUSH AF
    AND $7F
    LD [HL],A
    INC HL
    CALL L_3C9A
    LD B,$00
    ADD HL,BC
    POP AF
    POP BC
    JP M,L_4EDB
    PUSH BC
    CALL L_4F07
    LD HL,[ARYTAB]
    ADD HL,DE
    LD [ARYTAB],HL
    EX DE,HL
    POP HL
    JP L_4EDB
L_4F07:
    EX DE,HL
    LD HL,[STREND]
L_4F0B:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_4F0B
    LD A,C
    SUB L
    LD E,A
    LD A,B
    SBC A,H
    LD D,A
    DEC DE
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    RET
L_4F23:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
L_4F28:
    CALL L_43CD
    JP Z,L_4F4E
    PUSH HL
    INC HL
    INC HL
    LD A,[HL]
    OR A
    PUSH AF
    AND $7F
    LD [HL],A
    INC HL
    CALL L_3C9A
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    ADD HL,BC
    POP AF
    POP BC
    JP M,L_4F28
    PUSH BC
    CALL L_4F07
    EX DE,HL
    POP HL
    JP L_4F28
L_4F4E:
    LD HL,[VARTAB]
L_4F51:
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4F76
    LD A,[HL]
    INC HL
    INC HL
    INC HL
    PUSH AF
    CALL L_3C9A
    POP AF
    CP $03
    JP NZ,L_4F6E
    CALL L_4FAE
    XOR A
L_4F6E:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP L_4F51
L_4F75:
    POP BC
L_4F76:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4FD8
    LD A,[HL]
    INC HL
    INC HL
    PUSH AF
    INC HL
    CALL L_3C9A
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    POP AF
    PUSH HL
    ADD HL,BC
    CP $03
    JP NZ,L_4F75
    LD [TEMP3],HL
    POP HL
    LD C,[HL]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL
    EX DE,HL
    LD HL,[TEMP3]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4F76
    LD BC,$4F9F
    PUSH BC
L_4FAE:
    LD A,[HL]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    OR A
    RET Z
    PUSH HL
    LD HL,[VARTAB]
    CALL L_43CD
    POP HL
    RET C
    PUSH HL
    LD HL,[TXTTAB]
    CALL L_43CD
    POP HL
    RET NC
    PUSH HL
    DEC HL
    DEC HL
    DEC HL
    PUSH HL
    CALL L_46A3
    POP HL
    LD B,$03
    CALL L_28CD
    POP HL
    RET
L_4FD8:
    CALL L_4767
    LD HL,[STREND]
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL
    LD HL,[ARYTAB]
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD [D_0BB8],HL
    LD HL,[FRETOP]
    LD [D_0BE8],HL
    CALL L_42B9
    LD H,B
    LD L,C
    DEC HL
    LD [FRETOP],HL
    LD A,[D_0BEE]
    OR A
    JP Z,L_501B
    LD HL,[D_0BF1]
    LD B,H
    LD C,L
    LD HL,[D_0BEF]
    CALL L_22A2
    LD [ARYTAB],HL
    LD [STREND],HL
    CALL L_0EAB
L_501B:
    LD A,$01
    LD [D_0BF3],A
    LD A,[D_0BED]
    OR A
    JP NZ,L_536D
    LD A,[D_07C4]
    LD [D_079F],A
    JP L_52B9
L_5030:
    XOR A
    LD [D_0BF3],A
    LD [D_0BED],A
    LD HL,[VARTAB]
    LD B,H
    LD C,L
    LD HL,[D_0BB8]
    ADD HL,BC
    LD [ARYTAB],HL
    LD HL,[FRETOP]
    INC HL
    EX DE,HL
    LD HL,[D_0BE8]
    LD [FRETOP],HL
L_504E:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_504E
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    EX DE,HL
    LD HL,[D_0BF4]
    EX DE,HL
    LD HL,[TXTTAB]
    DEC HL
    LD A,D
    OR E
    JP Z,NEWSTT
    CALL L_0EF8
    JP NC,L_14CC
    DEC BC
    LD H,B
    LD L,C
    JP NEWSTT
    .byte $C3, $EC, $14
ST_WRITE:
    LD C,$02
    CALL L_510D
    DEC HL
    CALL CHRGTR
    JP Z,L_50DA
L_5087:
    CALL L_1A02
    PUSH HL
    CALL L_1D64
    JP Z,L_50CA
    CALL L_3129
    CALL L_46C7
    LD HL,[D_0C04]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,[DE]
    CP $20
    JP NZ,L_50AA
    INC DE
    LD [HL],D
    DEC HL
    LD [HL],E
    DEC HL
    DEC [HL]
L_50AA:
    CALL L_4726
L_50AD:
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,L_50DA
    CP $3B
    JP Z,L_50BF
    CALL L_43D3
    INC L
    DEC HL
L_50BF:
    CALL CHRGTR
    LD A,$2C
    CALL OUTDO
    JP L_5087
L_50CA:
    LD A,$22
    CALL OUTDO
    CALL L_4726
    LD A,$22
    CALL OUTDO
    JP L_50AD
L_50DA:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    JP Z,L_5104
    LD A,[HL]
    CP $03
    JP NZ,L_5104
    CALL L_5CC2
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD DE,$FFFE
    ADD HL,DE
    JP NC,L_5104
L_50F9:
    LD A,$20
    CALL OUTDO
    DEC HL
    LD A,H
    OR L
    JP NZ,L_50F9
L_5104:
    POP HL
    CALL L_4221
    JP L_17E9
L_510B:
    LD C,$01
L_510D:
    CP $23
    RET NZ
    PUSH BC
    CALL L_512A
    POP DE
    CP E
    JP Z,L_511E
    CP $03
    JP NZ,DERBFM
L_511E:
    CALL L_43D3
    INC L
L_5122:
    LD D,B
    LD E,C
    EX DE,HL
    LD [D_0794],HL
    EX DE,HL
    RET
L_512A:
    DEC HL
    CALL CHRGTR
    CP $23
    CALL Z,CHRGTR
    CALL L_1A02
L_5136:
    CALL L_2078
L_5139:
    LD E,A
L_513A:
    LD A,[D_07C4]
    CP E
    JP C,DERBFN
    LD D,$00
    PUSH HL
    LD HL,$07A4
    ADD HL,DE
    ADD HL,DE
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]
    OR A
    POP HL
    RET
L_5150:
    CALL L_513A
    LD HL,$0029
    CP $03
    JP NZ,L_515E
    LD HL,$00B2
L_515E:
    ADD HL,BC
    EX DE,HL
    RET
