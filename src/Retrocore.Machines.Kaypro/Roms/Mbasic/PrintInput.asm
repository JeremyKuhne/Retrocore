;; MBASIC 5.21: PRINT, INPUT AND READ
;;
;; Part of Mbasic.asm.

ST_LPRINT:
    LD A,$01
    LD [D_078D],A
    JP L_16A1
ST_PRINT:
    LD C,$02
    CALL L_510D
L_16A1:
    DEC HL
    CALL CHRGTR
    CALL Z,L_4221
L_16A8:
    JP Z,L_17E9
    CP $D9
    JP Z,L_3EF7
    CP $D0
    JP Z,L_1765
    CP $D4
    JP Z,L_1765
    PUSH HL
    CP $2C
    JP Z,L_1725
    CP $3B
    JP Z,L_17E2
    POP BC
    CALL L_1A02
    PUSH HL
    CALL L_1D64
    JP Z,L_16DC
    CALL L_3129
    CALL L_46C7
    LD [HL],$20
    LD HL,[D_0C04]
    INC [HL]
L_16DC:
    CALL L_4654
    JP NZ,L_171E
    LD HL,[D_0C04]
    LD A,[D_078D]
    OR A
    JP Z,L_1705
    LD A,[D_078F]
    LD B,A
    INC A
    JP Z,L_171E
    LD A,[D_078C]
    OR A
    JP Z,L_171E
    ADD A,[HL]
    CCF
    JP NC,L_171B
    DEC A
    CP B
    JP L_171B
L_1705:
    LD A,[D_0790]
    LD B,A
    INC A
    JP Z,L_171E
    LD A,[D_0A65]
    OR A
    JP Z,L_171E
    ADD A,[HL]
    CCF
    JP NC,L_171B
    DEC A
    CP B
L_171B:
    CALL NC,L_4221
L_171E:
    CALL L_4726
    POP HL
    JP L_16A1
L_1725:
    LD BC,$0028
    LD HL,[D_0794]
    ADD HL,BC
    CALL L_4654
    LD A,[HL]
    JP NZ,L_175C
    LD A,[D_078D]
    OR A
    JP Z,L_1749
    LD A,[D_078E]
    LD B,A
    INC A
    LD A,[D_078C]
    JP Z,L_175C
    CP B
    JP L_1756
L_1749:
    LD A,[D_0791]
    LD B,A
    LD A,[D_0A65]
    CP $FF
    JP Z,L_175C
    CP B
L_1756:
    CALL NC,L_4221
    JP NC,L_17E2
L_175C:
    SUB $0E
    JP NC,L_175C
    CPL
    JP L_17D7
L_1765:
    PUSH AF
    CALL CHRGTR
    CALL L_2056
    POP AF
    PUSH AF
    CP $D4
    JP Z,L_1774
    DEC DE
L_1774:
    LD A,D
    OR A
    JP P,L_177C
    LD DE,$0000
L_177C:
    PUSH HL
    CALL L_4654
    JP NZ,L_179B
    LD A,[D_078D]
    OR A
    LD A,[D_078F]
    JP NZ,L_1790
    LD A,[D_0790]
L_1790:
    LD L,A
    INC A
    JP Z,L_179B
    LD H,$00
    CALL L_2C0D
    EX DE,HL
L_179B:
    POP HL
    CALL L_43D3
    ADD HL,HL
    DEC HL
    POP AF
    SUB $D4
    PUSH HL
    JP Z,L_17C6
    LD BC,$0028
    LD HL,[D_0794]
    ADD HL,BC
    CALL L_4654
    LD A,[HL]
    JP NZ,L_17C6
    LD A,[D_078D]
    OR A
    JP Z,L_17C3
    LD A,[D_078C]
    JP L_17C6
L_17C3:
    LD A,[D_0A65]
L_17C6:
    CPL
    ADD A,E
    JP C,L_17D7
    INC A
    JP Z,L_17E2
    CALL L_4221
    LD A,E
    DEC A
    JP M,L_17E2
L_17D7:
    INC A
    LD B,A
    LD A,$20
L_17DB:
    CALL OUTDO
    DEC B
    JP NZ,L_17DB
L_17E2:
    POP HL
    CALL CHRGTR
    JP L_16A8
L_17E9:
    XOR A
    LD [D_078D],A
    PUSH HL
    LD H,A
    LD L,A
    LD [D_0794],HL
    POP HL
    RET
ST_LINE:
    CALL L_43D3
    ADD A,L
    CP $23
    JP Z,L_51A7
    CALL L_4C48
    CALL L_186F
    CALL L_398B
    CALL L_2A3B
    PUSH DE
    PUSH HL
    CALL L_4B30
    POP DE
    POP BC
    JP C,L_4416
    PUSH BC
    PUSH DE
    LD B,$00
    CALL L_46CA
    POP HL
    LD A,$03
    JP L_152D
    .byte $3F, $52, $65, $64, $6F, $20, $66, $72, $6F, $6D, $20, $73, $74, $61, $72, $74
    .byte $0D, $0A, $00, $23, $7E, $B7, $CA, $C9, $0C, $FE, $22, $C2, $34, $18, $C3, $DA
    .byte $18, $E1, $E1, $C3, $4E, $18, $3A, $A6, $0A, $B7, $C2, $C3, $0C, $C1, $21, $21
    .byte $18, $CD, $23, $47, $2A, $AF, $0A, $C9
L_1859:
    CALL L_510B
    PUSH HL
    LD HL,$0961
    JP L_193B
ST_INPUT:
    CP $23
    JP Z,L_1859
    CALL L_4C48
    LD BC,$1899
    PUSH BC
L_186F:
    CP $22
    LD A,$00
    LD [D_0793],A
    LD A,$FF
    LD [D_0BE7],A
    RET NZ
    CALL L_46C8
    LD A,[HL]
    CP $2C
    JP NZ,L_188F
    XOR A
    LD [D_0BE7],A
    CALL CHRGTR
    JP L_1893
L_188F:
    CALL L_43D3
    DEC SP
L_1893:
    PUSH HL
    CALL L_4726
    POP HL
    RET
    .byte $E5, $3A, $E7, $0B, $B7, $CA, $AB, $18, $3E, $3F, $CD, $D6, $40, $3E, $20, $CD
    .byte $D6, $40, $CD, $30, $4B, $C1, $DA, $16, $44, $C5, $AF, $32, $A6, $0A, $36, $2C
    .byte $EB, $E1, $E5, $D5, $D5, $2B, $3E, $80, $32, $A5, $0A, $CD, $05, $13, $CD, $89
    .byte $3A, $7E, $2B, $FE, $5B, $CA, $D6, $18, $FE, $28, $C2, $FD, $18, $23, $06, $00
    .byte $04, $CD, $05, $13, $CA, $C9, $0C, $FE, $22, $CA, $34, $18, $FE, $28, $CA, $D9
    .byte $18, $FE, $5B, $CA, $DA, $18, $FE, $5D, $CA, $F9, $18, $FE, $29, $C2, $DA, $18
    .byte $05, $C2, $DA, $18, $CD, $05, $13, $CA, $08, $19, $FE, $2C, $C2, $C9, $0C, $E3
    .byte $7E, $FE, $2C, $C2, $42, $18, $3E, $01, $32, $0A, $0C, $CD, $64, $19, $3A, $0A
    .byte $0C, $3D, $C2, $42, $18, $E5, $CD, $64, $1D, $CC, $A8, $48, $E1, $2B, $CD, $05
    .byte $13, $E3, $7E, $FE, $2C, $CA, $BF, $18, $E1, $2B, $CD, $05, $13, $B7, $E1, $C2
    .byte $4E, $18
L_193B:
    LD [HL],$2C
    JP L_1945
ST_READ:
    PUSH HL
    LD HL,[DATPTR]
    .byte $F6
L_1945:
    .byte $AF
    LD [FLGINP],A
    EX [SP],HL
    JP L_1951
    .byte $CD, $D3, $43, $2C
L_1951:
    CALL L_398B
    EX [SP],HL
    PUSH DE
    LD A,[HL]
    CP $2C
    JP Z,L_1963
    LD A,[FLGINP]
    OR A
    JP NZ,L_19D3
L_1963:
    OR $AF
    LD [D_0BBC],A
    CALL L_4654
    JP NZ,L_5197
    CALL L_1D64
    PUSH AF
    JP NZ,L_19A2
    CALL CHRGTR
    LD D,A
    LD B,A
    CP $22
    JP Z,L_198C
    LD A,[FLGINP]
    OR A
    LD D,A
    JP Z,L_1989
    LD D,$3A
L_1989:
    LD B,$2C
    DEC HL
L_198C:
    CALL L_46CB
    POP AF
    ADD A,$03
    LD C,A
    LD A,[D_0BBC]
    OR A
    RET Z
    LD A,C
    EX DE,HL
    LD HL,$19B1
    EX [SP],HL
    PUSH DE
    JP L_152E
L_19A2:
    CALL CHRGTR
    POP AF
    PUSH AF
    LD BC,$198F
    PUSH BC
    JP C,L_2ED1
    JP L_2ECA
    .byte $2B, $CD, $05, $13, $CA, $BD, $19, $FE, $2C, $C2, $47, $18, $E3, $2B, $CD, $05
    .byte $13, $C2, $4D, $19, $D1, $3A, $A6, $0A, $B7, $EB, $C2, $FC, $43, $D5, $E1, $C3
    .byte $E9, $17
L_19D3:
    CALL ST_DATA
    OR A
    JP NZ,L_19EC
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    LD E,$04
    JP Z,ERROR
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [DATLIN],HL
    EX DE,HL
L_19EC:
    CALL CHRGTR
    CP $84
    JP NZ,L_19D3
    JP L_1963
