;; MBASIC 5.21: VARIABLES AND ARRAYS
;;
;; Part of Mbasic.asm.

ST_DIM:
    LD BC,$397D
    PUSH BC
    .byte $F6
L_398B:
    .byte $AF
    LD [D_0A66],A
    LD C,[HL]
L_3990:
    CALL L_4503
    JP C,SNERR
    XOR A
    LD B,A
    LD [D_07C5],A
    INC HL
    LD A,[HL]
    CP $2E
    JP C,L_39E3
    JP Z,L_39B5
    CP $3A
    JP NC,L_39AF
    CP $30
    JP NC,L_39B5
L_39AF:
    CALL L_4504
    JP C,L_39E3
L_39B5:
    LD B,A
    PUSH BC
    LD B,$FF
    LD DE,$07C5
L_39BC:
    OR $80
    INC B
    LD [DE],A
    INC DE
    INC HL
    LD A,[HL]
    CP $3A
    JP NC,L_39CD
    CP $30
    JP NC,L_39BC
L_39CD:
    CALL L_4504
    JP NC,L_39BC
    CP $2E
    JP Z,L_39BC
    LD A,B
    CP $27
    JP NC,SNERR
    POP BC
    LD [D_07C5],A
    LD A,[HL]
L_39E3:
    CP $26
    JP NC,L_39FF
    LD DE,$3A0D
    PUSH DE
    LD D,$02
    CP $25
    RET Z
    INC D
    CP $24
    RET Z
    INC D
    CP $21
    RET Z
    LD D,$08
    CP $23
    RET Z
    POP AF
L_39FF:
    LD A,C
    AND $7F
    LD E,A
    LD D,$00
    PUSH HL
    LD HL,$0A89
    ADD HL,DE
    LD D,[HL]
    POP HL
    DEC HL
    LD A,D
    LD [D_0A67],A
    CALL CHRGTR
    LD A,[SUBFLG]
    DEC A
    JP Z,L_3B92
    JP P,L_3A29
    LD A,[HL]
    SUB $28
    JP Z,L_3B16
    SUB $33
    JP Z,L_3B16
L_3A29:
    XOR A
    LD [SUBFLG],A
    PUSH HL
    LD A,[D_0BB7]
    OR A
    LD [D_0BB4],A
    JP Z,L_3A7D
    LD HL,[D_0AE6]
    LD DE,$0AE8
    ADD HL,DE
    LD [D_0BB5],HL
    EX DE,HL
    JP L_3A63
L_3A46:
    LD A,[DE]
    LD L,A
    INC DE
    LD A,[DE]
    INC DE
    CP C
    JP NZ,L_3A5B
    LD A,[D_0A67]
    CP L
    JP NZ,L_3A5B
    LD A,[DE]
    CP B
    JP Z,L_3AE5
L_3A5B:
    INC DE
L_3A5C:
    LD A,[DE]
L_3A5D:
    LD H,$00
    ADD A,L
    INC A
    LD L,A
    ADD HL,DE
L_3A63:
    EX DE,HL
    LD A,[D_0BB5]
    CP E
    JP NZ,L_3A46
    LD A,[D_0BB6]
    CP D
    JP NZ,L_3A46
    LD A,[D_0BB4]
    OR A
    JP Z,L_3A92
    XOR A
    LD [D_0BB4],A
L_3A7D:
    LD HL,[ARYTAB]
    LD [D_0BB5],HL
    LD HL,[VARTAB]
    JP L_3A63
L_3A89:
    CALL L_398B
    RET
L_3A8D:
    LD D,A
    LD E,A
    POP BC
    EX [SP],HL
    RET
L_3A92:
    POP HL
    EX [SP],HL
    PUSH DE
    LD DE,$3A8C
    CALL L_43CD
    JP Z,L_3A8D
    LD DE,$1C4D
    CALL L_43CD
    POP DE
    JP Z,L_3B00
    EX [SP],HL
    PUSH HL
    PUSH BC
    LD A,[D_0A67]
    LD B,A
    LD A,[D_07C5]
    ADD A,B
    INC A
    LD C,A
    PUSH BC
    LD B,$00
    INC BC
    INC BC
    INC BC
    LD HL,[STREND]
    PUSH HL
    ADD HL,BC
    POP BC
    PUSH HL
    CALL L_42B6
    POP HL
    LD [STREND],HL
    LD H,B
    LD L,C
    LD [ARYTAB],HL
L_3ACE:
    DEC HL
    LD [HL],$00
    CALL L_43CD
    JP NZ,L_3ACE
    POP DE
    LD [HL],D
    INC HL
    POP DE
    LD [HL],E
    INC HL
    LD [HL],D
    CALL L_3CA3
    EX DE,HL
    INC DE
    POP HL
    RET
L_3AE5:
    INC DE
    LD A,[D_07C5]
    LD H,A
    LD A,[DE]
    CP H
    JP NZ,L_3A5C
    OR A
    JP NZ,L_3AF6
    INC DE
    POP HL
    RET
L_3AF6:
    EX DE,HL
    CALL L_3CB8
    EX DE,HL
    JP NZ,L_3A5D
    POP HL
    RET
L_3B00:
    LD [D_0C07],A
    LD H,A
    LD L,A
    LD [D_0C04],HL
    CALL L_1D64
    JP NZ,L_3B14
    LD HL,$0C44
    LD [D_0C04],HL
L_3B14:
    POP HL
    RET
L_3B16:
    PUSH HL
    LD HL,[D_0A66]
    EX [SP],HL
    LD D,A
L_3B1C:
    PUSH DE
    PUSH BC
    LD DE,$07C5
    LD A,[DE]
    OR A
    JP Z,L_3B58
    EX DE,HL
    ADD A,$02
    RRA
    LD C,A
    CALL L_42C7
    LD A,C
L_3B2F:
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,L_3B2F
    PUSH HL
    LD A,[D_07C5]
    PUSH AF
    EX DE,HL
    CALL L_1411
    POP AF
    LD [D_07EC],HL
    POP HL
    ADD A,$02
    RRA
L_3B49:
    POP BC
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC A
    JP NZ,L_3B49
    LD HL,[D_07EC]
    JP L_3B5F
L_3B58:
    CALL L_1411
    XOR A
    LD [D_07C5],A
L_3B5F:
    LD A,[D_0BC6]
    OR A
    JP Z,L_3B6C
    LD A,D
    OR E
    JP Z,L_3BD6
    DEC DE
L_3B6C:
    POP BC
    POP AF
    EX DE,HL
    EX [SP],HL
    PUSH HL
    EX DE,HL
    INC A
    LD D,A
    LD A,[HL]
    CP $2C
    JP Z,L_3B1C
    CP $29
    JP Z,L_3B84
    CP $5D
    JP NZ,SNERR
L_3B84:
    CALL CHRGTR
    LD [TEMP2],HL
    POP HL
    LD [D_0A66],HL
    LD E,$00
    PUSH DE
    .byte $11
L_3B92:
    PUSH HL
    PUSH AF
    LD HL,[ARYTAB]
    .byte $3E
L_3B98:
    .byte $19
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_3BF0
    LD E,[HL]
    INC HL
    LD A,[HL]
    INC HL
    CP C
    JP NZ,L_3BB8
    LD A,[D_0A67]
    CP E
    JP NZ,L_3BB8
    LD A,[HL]
    CP B
    JP Z,L_3BDC
L_3BB8:
    INC HL
L_3BB9:
    LD E,[HL]
    INC E
    LD D,$00
    ADD HL,DE
L_3BBE:
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    JP NZ,L_3B98
    LD A,[D_0A66]
    OR A
    JP NZ,DDERR
    POP AF
    LD B,H
    LD C,L
    JP Z,L_2757
    SUB [HL]
    JP Z,L_3C5D
L_3BD6:
    LD DE,$0009
    JP ERROR
L_3BDC:
    INC HL
    LD A,[D_07C5]
    CP [HL]
    JP NZ,L_3BB9
    INC HL
    OR A
    JP Z,L_3BBE
    DEC HL
    CALL L_3CB8
    JP L_3BBE
L_3BF0:
    LD A,[D_0A67]
    LD [HL],A
    INC HL
    LD E,A
    LD D,$00
    POP AF
    JP Z,L_3C96
    LD [HL],C
    INC HL
    LD [HL],B
    CALL L_3CA3
    INC HL
    LD C,A
    CALL L_42C7
    INC HL
    INC HL
    LD [TEMP3],HL
    LD [HL],C
    INC HL
    LD A,[D_0A66]
    RLA
    LD A,C
L_3C13:
    JP C,L_3C23
    PUSH AF
    LD A,[D_0BC6]
    XOR $0B
    LD C,A
    LD B,$00
    POP AF
    JP NC,L_3C25
L_3C23:
    POP BC
    INC BC
L_3C25:
    LD [HL],C
    PUSH AF
    INC HL
    LD [HL],B
    INC HL
    CALL L_2B05
    POP AF
    DEC A
    JP NZ,L_3C13
    PUSH AF
    LD B,D
    LD C,E
    EX DE,HL
    ADD HL,DE
    JP C,L_42DD
    CALL L_42EB
    LD [STREND],HL
L_3C40:
    DEC HL
    LD [HL],$00
    CALL L_43CD
    JP NZ,L_3C40
    INC BC
    LD D,A
    LD HL,[TEMP3]
    LD E,[HL]
    EX DE,HL
    ADD HL,HL
    ADD HL,BC
    EX DE,HL
    DEC HL
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    POP AF
    JP C,L_3C92
L_3C5D:
    LD B,A
    LD C,A
    LD A,[HL]
    INC HL
    .byte $16
L_3C62:
    .byte $E1
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL
    PUSH AF
    CALL L_43CD
    JP NC,L_3BD6
    CALL L_2B05
    ADD HL,DE
    POP AF
    DEC A
    LD B,H
    LD C,L
    JP NZ,L_3C62
    LD A,[D_0A67]
    LD B,H
    LD C,L
    ADD HL,HL
    SUB $04
    JP C,L_3C8A
    ADD HL,HL
    JP Z,L_3C8F
    ADD HL,HL
L_3C8A:
    OR A
    JP PO,L_3C8F
    ADD HL,BC
L_3C8F:
    POP BC
    ADD HL,BC
    EX DE,HL
L_3C92:
    LD HL,[TEMP2]
    RET
L_3C96:
    SCF
    SBC A,A
    POP HL
    RET
L_3C9A:
    LD A,[HL]
    INC HL
L_3C9C:
    PUSH BC
    LD B,$00
    LD C,A
    ADD HL,BC
    POP BC
    RET
L_3CA3:
    PUSH BC
    PUSH DE
    PUSH AF
    LD DE,$07C5
    LD A,[DE]
    LD B,A
    INC B
L_3CAC:
    LD A,[DE]
    INC DE
    INC HL
    LD [HL],A
    DEC B
    JP NZ,L_3CAC
    POP AF
    POP DE
    POP BC
    RET
L_3CB8:
    PUSH DE
    PUSH BC
    LD DE,$07C6
    LD B,A
    INC HL
    INC B
L_3CC0:
    DEC B
    JP Z,L_3CD2
    LD A,[DE]
    INC DE
    CP [HL]
    INC HL
    JP Z,L_3CC0
    LD A,B
    DEC A
    CALL NZ,L_3C9C
    XOR A
    DEC A
L_3CD2:
    POP BC
    POP DE
    RET
L_3CD5:
    LD [D_078A],A
    LD HL,[ERRLIN]
    OR H
    AND L
    INC A
    EX DE,HL
    RET Z
    JP L_3CE7
