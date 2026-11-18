;; MBASIC 5.21: THE FORMULA EVALUATOR
;;
;; Part of Mbasic.asm.

L_19F7:
    CALL L_43D3
    RET P
    JP L_1A02
L_19FE:
    CALL L_43D3
    .byte $28
L_1A02:
    .byte $2B
L_1A03:
    LD D,$00
L_1A05:
    PUSH DE
    LD C,$01
    CALL L_42C7
    CALL L_1B93
    XOR A
    LD [D_0C09],A
    LD [TEMP2],HL
L_1A15:
    LD HL,[TEMP2]
    POP BC
    LD A,[HL]
    LD [TEMP3],HL
    CP $EF
    RET C
    CP $F2
    JP C,L_1A8E
    SUB $F2
    LD E,A
    JP NZ,L_1A34
    LD A,[D_0A67]
L_1A2E:
    CP $03
    LD A,E
    JP Z,L_485B
L_1A34:
    CP $0C
    RET NC
    LD HL,$047F
    LD D,$00
    ADD HL,DE
    LD A,B
    LD D,[HL]
    CP D
    RET NC
    PUSH BC
    LD BC,$1A15
    PUSH BC
    LD A,D
    CP $7F
    JP Z,L_1AAC
    CP $51
    JP C,L_1ABA
    AND $FE
    CP $7A
    JP Z,L_1ABA
L_1A58:
    LD HL,$0C04
    LD A,[D_0A67]
    SUB $03
    JP Z,TMERR
    OR A
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    JP M,L_1A7F
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    JP PO,L_1A7F
    LD HL,$0C00
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
L_1A7F:
    ADD A,$03
    LD C,E
    LD B,A
    PUSH BC
    LD BC,$1AE3
L_1A87:
    PUSH BC
    LD HL,[TEMP3]
    JP L_1A05
L_1A8E:
    LD D,$00
L_1A90:
    SUB $EF
    JP C,L_1AC6
    CP $03
    JP NC,L_1AC6
    CP $01
    RLA
    XOR D
    CP D
    LD D,A
    JP C,SNERR
    LD [TEMP3],HL
    CALL CHRGTR
    JP L_1A90
L_1AAC:
    CALL FN_CSNG
    CALL L_2899
    LD BC,$36CC
    LD D,$7F
    JP L_1A87
L_1ABA:
    PUSH DE
    CALL FN_CINT
    POP DE
    PUSH HL
    LD BC,$1D75
    JP L_1A87
L_1AC6:
    LD A,B
    CP $64
    RET NC
    PUSH BC
    PUSH DE
    LD DE,$6404
    LD HL,$1D42
    PUSH HL
    CALL L_1D64
    JP NZ,L_1A58
    LD HL,[D_0C04]
    PUSH HL
    LD BC,$465C
    JP L_1A87
    .byte $C1, $79, $32, $68, $0A, $3A, $67, $0A, $B8, $C2, $FC, $1A, $FE, $02, $CA, $18
    .byte $1B, $FE, $04, $CA, $67, $1B, $D2, $2B, $1B, $57, $78, $FE, $08, $CA, $28, $1B
    .byte $7A, $FE, $08, $CA, $4F, $1B, $78, $FE, $04, $CA, $64, $1B, $7A, $FE, $03, $CA
    .byte $E1, $0C, $D2, $6F, $1B, $21, $A9, $04, $06, $00, $09, $09, $4E, $23, $46, $D1
    .byte $2A, $04, $0C, $C5, $C9, $CD, $20, $2A, $CD, $F4, $28, $E1, $22, $02, $0C, $E1
    .byte $22, $00, $0C, $C1, $D1, $CD, $A9, $28, $CD, $20, $2A, $21, $95, $04, $3A, $68
    .byte $0A, $07, $85, $6F, $8C, $95, $67, $7E, $23, $66, $6F, $E9, $78, $F5, $CD, $F4
    .byte $28, $F1, $32, $67, $0A, $FE, $04, $CA, $36, $1B, $E1, $22, $04, $0C, $C3, $3B
    .byte $1B, $CD, $F4, $29, $C1, $D1, $21, $9F, $04, $C3, $41, $1B, $E1, $CD, $99, $28
    .byte $CD, $14, $2A, $CD, $B4, $28, $E1, $22, $06, $0C, $E1, $22, $04, $0C, $C3, $69
    .byte $1B, $E5, $EB, $CD, $14, $2A, $E1, $CD, $99, $28, $CD, $14, $2A, $C3, $67, $27
L_1B93:
    CALL CHRGTR
    JP Z,MOERR
    JP C,L_2ED1
    CALL L_4504
    JP NC,L_1C4A
    CP $20
    JP C,L_135D
    INC A
    JP Z,ISFUN
    DEC A
    CP $F2
    JP Z,L_1B93
    CP $F3
    JP Z,L_1C3C
    CP $22
    JP Z,L_46C8
    CP $D5
    JP Z,L_1D4F
    CP $26
    JP Z,L_1C69
    CP $D7
    JP NZ,L_1BD6
    CALL CHRGTR
    LD A,[D_078A]
    PUSH HL
    CALL L_1DD5
    POP HL
    RET
L_1BD6:
    CP $D6
    JP NZ,L_1BE7
    CALL CHRGTR
    PUSH HL
    LD HL,[ERRLIN]
    CALL L_2C03
    POP HL
    RET
L_1BE7:
    CP $DC
    JP NZ,L_1C16
    CALL CHRGTR
    CALL L_43D3
L_1BF2:
    JR Z,L_1BF2
    INC HL
    JP NZ,L_1C03
    CALL L_2072
    PUSH HL
    CALL L_5150
    POP HL
    JP L_1C06
L_1C03:
    CALL L_3A89
L_1C06:
    CALL L_43D3
    ADD HL,HL
    PUSH HL
    EX DE,HL
    LD A,H
    OR L
    JP Z,L_1418
    CALL L_29DC
    POP HL
    RET
L_1C16:
    CP $D2
    JP Z,L_1DDB
    CP $DA
    JP Z,L_49CB
    CP $DD
    JP Z,L_426F
    CP $D8
    JP Z,L_4900
    CP $85
    JP Z,L_5527
    CP $D3
    JP Z,L_1E54
L_1C34:
    CALL L_19FE
    CALL L_43D3
    ADD HL,HL
    RET
L_1C3C:
    LD D,$7D
    CALL L_1A05
    LD HL,[TEMP2]
    PUSH HL
    CALL L_286B
    POP HL
    RET
L_1C4A:
    CALL L_398B
    PUSH HL
    EX DE,HL
    LD [D_0C04],HL
    CALL L_1D64
    CALL NZ,L_28EE
    POP HL
    RET
L_1C5A:
    LD A,[HL]
L_1C5B:
    CP $61
    RET C
    CP $7B
    RET NC
    AND $5F
    RET
    .byte $FE, $26, $C2, $28, $14
L_1C69:
    LD DE,$0000
    CALL CHRGTR
    CALL L_1C5B
    CP $4F
    JP Z,L_1CAD
    CP $48
    JP NZ,L_1CAC
    LD B,$05
L_1C7E:
    INC HL
    LD A,[HL]
    CALL L_1C5B
    CALL L_4504
    EX DE,HL
    JP NC,L_1C97
    CP $3A
    JP NC,L_1CCE
    SUB $30
    JP C,L_1CCE
    JP L_1C9E
L_1C97:
    CP $47
    JP NC,L_1CCE
    SUB $37
L_1C9E:
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    OR L
    LD L,A
    EX DE,HL
    DEC B
    JP NZ,L_1C7E
    JP OVERR
L_1CAC:
    DEC HL
L_1CAD:
    CALL CHRGTR
    EX DE,HL
    JP NC,L_1CCE
    CP $38
    JP NC,SNERR
    LD BC,$0CDB
    PUSH BC
    ADD HL,HL
    RET C
    ADD HL,HL
    RET C
    ADD HL,HL
    RET C
    POP BC
    LD B,$00
    SUB $30
    LD C,A
    ADD HL,BC
    EX DE,HL
    JP L_1CAD
L_1CCE:
    CALL L_29DC
    EX DE,HL
    RET
ISFUN:
    INC HL
    LD A,[HL]
    SUB $81
    CP $07
    JP NZ,L_1CE8
    PUSH HL
    CALL CHRGTR
    CP $28
    POP HL
    JP NZ,L_37CC
    LD A,$07
L_1CE8:
    LD B,$00
    RLCA
    LD C,A
    PUSH BC
    CALL CHRGTR
    LD A,C
    CP $05
    JP NC,L_1D0F
    CALL L_19FE
    CALL L_43D3
    INC L
    CALL L_2A3B
    EX DE,HL
    LD HL,[D_0C04]
    EX [SP],HL
    PUSH HL
    EX DE,HL
    CALL L_2075
    EX DE,HL
    EX [SP],HL
    JP L_1D29
L_1D0F:
    CALL L_1C34
    EX [SP],HL
    LD A,L
    CP $0C
    JP C,L_1D20
    CP $1B
    PUSH HL
    CALL C,FN_CSNG
    POP HL
L_1D20:
    LD DE,$1C48
    PUSH DE
    LD A,$01
    LD [D_0C09],A
L_1D29:
    LD BC,$019F
L_1D2C:
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD H,[HL]
    LD L,C
    JP [HL]
L_1D32:
    DEC D
    CP $F3
    RET Z
    CP $2D
    RET Z
    INC D
    CP $2B
    RET Z
    CP $F2
    RET Z
    DEC HL
    RET
    .byte $3C, $8F, $C1, $A0, $C6, $FF, $9F, $CD, $7F, $28, $C3, $61, $1D
L_1D4F:
    LD D,$5A
    CALL L_1A05
    CALL FN_CINT
    LD A,L
    CPL
    LD L,A
    LD A,H
    CPL
    LD H,A
    LD [D_0C04],HL
    POP BC
    JP L_1A15
L_1D64:
    LD A,[D_0A67]
    CP $08
    JP NC,L_1D71
    SUB $03
    OR A
    SCF
    RET
L_1D71:
    SUB $03
    OR A
    RET
    .byte $78, $F5, $CD, $7A, $29, $F1, $D1, $FE, $7A, $CA, $0D, $2C, $FE, $7B, $CA, $A8
    .byte $2B, $01, $D7, $1D, $C5, $FE, $46, $C2, $95, $1D, $7B, $B5, $6F, $7C, $B2, $C9
    .byte $FE, $50, $C2, $A0, $1D, $7B, $A5, $6F, $7C, $A2, $C9, $FE, $3C, $C2, $AB, $1D
    .byte $7B, $AD, $6F, $7C, $AA, $C9, $FE, $32, $C2, $B8, $1D, $7B, $AD, $2F, $6F, $7C
    .byte $AA, $2F, $C9, $7D, $2F, $A3, $2F, $6F, $7C, $2F, $A2, $2F, $C9
L_1DC2:
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP L_2C03
FN_LPOS:
    LD A,[D_078C]
    JP L_1DD4
FN_POS:
    LD A,[D_0A65]
L_1DD4:
    INC A
L_1DD5:
    LD L,A
    XOR A
L_1DD7:
    LD H,A
    JP L_29DC
L_1DDB:
    CALL L_1DFA
    PUSH DE
    CALL L_1C34
    EX [SP],HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,$2757
    PUSH HL
    PUSH DE
    LD A,[D_0A67]
    PUSH AF
    CP $03
    CALL Z,L_48A8
    POP AF
    EX DE,HL
    LD HL,$0C04
    RET
L_1DFA:
    CALL CHRGTR
    LD BC,$0000
    CP $1B
    JP NC,L_1E13
    CP $11
    JP C,L_1E13
    CALL CHRGTR
    LD A,[D_0A6E]
    OR A
    RLA
    LD C,A
L_1E13:
    EX DE,HL
    LD HL,$0774
    ADD HL,BC
    EX DE,HL
    RET
L_1E1A:
    CALL L_1DFA
    PUSH DE
    CALL L_43D3
    RET P
    CALL L_22D1
    EX [SP],HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    RET
ST_DEF:
    CP $D2
L_1E2D:
    JP Z,L_1E1A
    CALL L_1FD4
    CALL L_1FC6
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    EX DE,HL
    LD A,[HL]
    CP $28
    JP NZ,ST_DATA
    CALL CHRGTR
L_1E44:
    CALL L_398B
    LD A,[HL]
    CP $29
    JP Z,ST_DATA
    CALL L_43D3
    INC L
    JP L_1E44
L_1E54:
    CALL L_1FD4
    LD A,[D_0A67]
    OR A
    PUSH AF
    LD [TEMP2],HL
    EX DE,HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD A,H
    OR L
    JP Z,UFERR
    LD A,[HL]
    CP $28
    JP NZ,L_1F1E
    CALL CHRGTR
    LD [TEMP3],HL
    EX DE,HL
    LD HL,[TEMP2]
    CALL L_43D3
    JR Z,L_1E2D
    PUSH AF
    PUSH HL
    EX DE,HL
L_1E81:
    LD A,$80
    LD [SUBFLG],A
    CALL L_398B
    EX DE,HL
    EX [SP],HL
    LD A,[D_0A67]
    PUSH AF
    PUSH DE
    CALL L_1A02
    LD [TEMP2],HL
    POP HL
    LD [TEMP3],HL
    POP AF
    CALL L_1FAC
    LD C,$04
    CALL L_42C7
    LD HL,$FFF8
    ADD HL,SP
    LD SP,HL
    CALL L_28F7
    LD A,[D_0A67]
    PUSH AF
    LD HL,[TEMP2]
    LD A,[HL]
    CP $29
    JP Z,L_1ECB
    CALL L_43D3
    INC L
    PUSH HL
    LD HL,[TEMP3]
    CALL L_43D3
    INC L
    JP L_1E81
    .byte $F1, $32, $4E, $0B
L_1ECB:
    POP AF
    OR A
    JP Z,L_1F0F
    LD [D_0A67],A
    LD HL,$0000
    ADD HL,SP
    CALL L_28EE
    LD HL,$0008
    ADD HL,SP
    LD SP,HL
    POP DE
    LD L,$03
L_1EE2:
    INC L
    DEC DE
    LD A,[DE]
    OR A
    JP M,L_1EE2
    DEC DE
    DEC DE
    DEC DE
    LD A,[D_0A67]
    ADD A,L
    LD B,A
    LD A,[D_0B4E]
    LD C,A
    ADD A,B
    CP $64
    JP NC,L_1418
    PUSH AF
    LD A,L
    LD B,$00
    LD HL,$0B50
    ADD HL,BC
    LD C,A
    CALL L_1FC0
    LD BC,$1EC7
    PUSH BC
    PUSH BC
    JP L_153A
L_1F0F:
    LD HL,[TEMP2]
    CALL CHRGTR
    PUSH HL
    LD HL,[TEMP3]
    CALL L_43D3
    ADD HL,HL
    .byte $3E
L_1F1E:
    .byte $D5
    LD [TEMP3],HL
    LD A,[D_0AE6]
    ADD A,$04
    PUSH AF
    RRCA
    LD C,A
    CALL L_42C7
    POP AF
    LD C,A
    CPL
    INC A
    LD L,A
    LD H,$FF
    ADD HL,SP
    LD SP,HL
    PUSH HL
    LD DE,$0AE4
    CALL L_1FC0
    POP HL
    LD [D_0AE4],HL
    LD HL,[D_0B4E]
    LD [D_0AE6],HL
    LD B,H
    LD C,L
    LD HL,$0AE8
    LD DE,$0B50
    CALL L_1FC0
    LD H,A
    LD L,A
    LD [D_0B4E],HL
    LD HL,[D_0BBA]
    INC HL
    LD [D_0BBA],HL
    LD A,H
    OR L
    LD [D_0BB7],A
    LD HL,[TEMP3]
    CALL L_19F7
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    CALL L_1D64
    JP NZ,L_1F88
    LD DE,$0A98
    LD HL,[D_0C04]
    CALL L_43CD
    JP C,L_1F88
    CALL L_46A3
    CALL L_4701
L_1F88:
    LD HL,[D_0AE4]
    LD D,H
    LD E,L
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC BC
    INC BC
    INC BC
    INC BC
    LD HL,$0AE4
    CALL L_1FC0
    EX DE,HL
    LD SP,HL
    LD HL,[D_0BBA]
    DEC HL
    LD [D_0BBA],HL
    LD A,H
    OR L
    LD [D_0BB7],A
    POP HL
    POP AF
L_1FAC:
    PUSH HL
    AND $07
    LD HL,$048B
    LD C,A
    LD B,$00
    ADD HL,BC
    CALL L_1D2C
    POP HL
    RET
L_1FBB:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
L_1FC0:
    LD A,B
    OR C
    JP NZ,L_1FBB
    RET
L_1FC6:
    PUSH HL
    LD HL,[CURLIN]
    INC HL
    LD A,H
    OR L
    POP HL
    RET NZ
    LD E,$0C
    JP ERROR
L_1FD4:
    CALL L_43D3
    OUT [$3E],A
    ADD A,B
    LD [SUBFLG],A
    OR [HL]
    LD C,A
    JP L_3990
L_1FE2:
    CP $7E
    JP NZ,SNERR
    INC HL
    LD A,[HL]
    INC HL
    CP $83
    JP Z,L_4A60
    JP SNERR
FN_INP:
    CALL L_2078
    LD [D_1FF9],A
    .byte $DB
D_1FF9:
    .byte $00
    JP L_1DD5
ST_OUT:
    CALL L_2062
    .byte $D3
D_2001:
    .byte $00
    RET
ST_WAIT:
    CALL L_2062
    PUSH AF
    LD E,$00
    DEC HL
    CALL CHRGTR
    JP Z,L_2017
    CALL L_43D3
    INC L
    CALL L_2075
L_2017:
    POP AF
    LD D,A
L_2019:
    .byte $DB
D_201A:
    .byte $00
    XOR E
    AND D
    JP Z,L_2019
    RET
    .byte $C3, $C9, $0C
ST_WIDTH:
    CP $9E
    JP NZ,L_203A
    CALL CHRGTR
    CALL L_2075
    LD [D_078F],A
    LD E,A
    CALL L_2048
    LD [D_078E],A
    RET
L_203A:
    CALL L_2075
    LD [D_0790],A
    LD E,A
    CALL L_2048
    LD [D_0791],A
    RET
L_2048:
    SUB $0E
    JP NC,L_2048
    ADD A,$1C
    CPL
    INC A
    ADD A,E
    RET
L_2053:
    CALL CHRGTR
L_2056:
    CALL L_1A02
L_2059:
    PUSH HL
    CALL FN_CINT
    EX DE,HL
    POP HL
    LD A,D
    OR A
    RET
L_2062:
    CALL L_2075
    LD [D_201A],A
    LD [D_2001],A
    CALL L_43D3
    INC L
    JP L_2075
L_2072:
    CALL CHRGTR
L_2075:
    CALL L_1A02
L_2078:
    CALL L_2059
    JP NZ,L_1418
    DEC HL
    CALL CHRGTR
    LD A,E
    RET
