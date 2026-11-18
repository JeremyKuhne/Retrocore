;; MBASIC 5.21: INTERPRETER: ERRORS, THE MAIN LOOP AND CRUNCHING
;;
;; Part of Mbasic.asm.

FNDFOR:
    NOP
L_0C50:
    LD HL,$0004
    ADD HL,SP
L_0C54:
    LD A,[HL]
    INC HL
    CP $B4
    JP NZ,L_0C62
    LD BC,$0006
    ADD HL,BC
    JP L_0C54
L_0C62:
    CP $82
    RET NZ
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH HL
    LD H,B
    LD L,C
    LD A,D
    OR E
    EX DE,HL
    JP Z,L_0C76
    EX DE,HL
    CALL L_43CD
L_0C76:
    LD BC,$0010
    POP HL
    RET Z
    ADD HL,BC
    JP L_0C54
    .byte $01, $86, $0D, $C3, $FC, $0C
GOPRGD:
    LD HL,[CURLIN]
    LD A,H
    AND L
    INC A
    JP Z,L_0C97
    LD A,[ONEFLG]
    OR A
    LD E,$13
    JP NZ,ERROR
L_0C97:
    JP ENDCON
DERDFL:
    LD E,$3D
    .byte $01
DERDIO:
    LD E,$39
    .byte $01
DERBFM:
    LD E,$36
    .byte $01
DERFNF:
    LD E,$35
    .byte $01
DERBFN:
    LD E,$34
    .byte $01
DERIER:
    LD E,$33
    .byte $01
DERRPE:
    LD E,$3E
    .byte $01
DERFAO:
    LD E,$37
    .byte $01
DERIFN:
    LD E,$40
    .byte $01
DERBRN:
    LD E,$3F
    .byte $01
DERFOV:
    LD E,$32
    .byte $01
DERTMF:
    LD E,$43
    .byte $01
DERFAE:
    LD E,$3A
    JP ERROR
    .byte $2A, $A3, $0A, $22, $98, $07
SNERR:
    LD E,$02
    .byte $01
DV0ERR:
    LD E,$0B
    .byte $01
NFERR:
    LD E,$01
    .byte $01
DDERR:
    LD E,$0A
    .byte $01
UFERR:
    LD E,$12
    .byte $01
REERR:
    LD E,$14
    .byte $01
OVERR:
    LD E,$06
    .byte $01
MOERR:
    LD E,$16
    .byte $01
TMERR:
    LD E,$0D
ERROR:
    LD HL,[CURLIN]
    LD [ERRLIN],HL
    XOR A
    LD [D_0BED],A
    LD [D_0BF3],A
    LD A,H
    AND L
    INC A
    JP Z,L_0CF9
    LD [DOT],HL
L_0CF9:
    LD BC,$0D02
    LD HL,[SAVSTK]
    JP L_43A2
    .byte $C1, $7B, $4B, $32, $8A, $07, $2A, $AF, $0A, $22, $B7, $0A, $EB, $2A, $B3, $0A
    .byte $7C, $A5, $3C, $CA, $1F, $0D, $22, $BE, $0A, $EB, $22, $C0, $0A, $2A, $B9, $0A
    .byte $7C, $B5, $EB, $21, $BB, $0A, $CA, $34, $0D, $A6, $C2, $34, $0D, $35, $EB, $C3
    .byte $C0, $12, $AF, $77, $59, $32, $93, $07, $CD, $14, $42, $21, $B3, $04, $7B, $FE
    .byte $44, $D2, $50, $0D, $FE, $32, $D2, $52, $0D, $FE, $1F, $DA, $55, $0D
L_0D50:
    LD A,$28
    SUB $13
    LD E,A
L_0D55:
    CALL ST_REM
    INC HL
    DEC E
    JP NZ,L_0D55
    PUSH HL
    LD HL,[ERRLIN]
    EX [SP],HL
ERRFIN:
    LD A,[HL]
    CP $3F
    JP NZ,L_0D6F
    POP HL
    LD HL,$04B3
    JP L_0D50
L_0D6F:
    CALL L_4723
    POP HL
    LD DE,$FFFE
    CALL L_43CD
    CALL Z,L_4221
    JP Z,L_59BB
    LD A,H
    AND L
    INC A
    CALL NZ,L_3112
    .byte $3E
STPRDY:
    POP BC
READY:
    CALL L_4144
    XOR A
    LD [D_0793],A
    CALL L_534D
    CALL L_4214
    LD HL,$0C45
    .byte $CD
D_0D98:
    .byte $00, $00
    LD A,[D_078A]
    SUB $02
    CALL Z,L_3CD5
MAIN:
    LD HL,$FFFF
    LD [CURLIN],HL
    LD A,[AUTFLG]
    OR A
    JP Z,L_0DF9
    LD HL,[AUTLIN]
    PUSH HL
    CALL LINPRT
    POP DE
    PUSH DE
    CALL L_0EF8
    LD A,$2A
    JP C,L_0DC2
    LD A,$20
L_0DC2:
    CALL OUTDO
    CALL L_4B28
    POP DE
    JP NC,L_0DDA
    XOR A
    LD [AUTFLG],A
    JP READY
L_0DD3:
    XOR A
    LD [AUTFLG],A
    JP L_0DEF
L_0DDA:
    LD HL,[AUTINC]
    ADD HL,DE
    JP C,L_0DD3
    PUSH DE
    LD DE,$FFF9
    CALL L_43CD
    POP DE
    JP NC,L_0DD3
    LD [AUTLIN],HL
L_0DEF:
    LD A,[D_0962]
    OR A
    JP Z,MAIN
    JP L_3EE2
L_0DF9:
    CALL L_4B28
    JP C,MAIN
    CALL CHRGTR
    INC A
    DEC A
    JP Z,MAIN
    PUSH AF
    CALL L_1428
    CALL L_11AC
    LD A,[HL]
    CP $20
    CALL Z,L_28BE
L_0E14:
    PUSH DE
    CALL L_0F18
    POP DE
    POP AF
    LD [SAVTXT],HL
    JP NC,L_538A
    PUSH DE
    PUSH BC
    CALL L_5D65
    CALL CHRGTR
    OR A
    PUSH AF
    EX DE,HL
    LD [DOT],HL
    EX DE,HL
    CALL L_0EF8
    JP C,L_0E3B
    POP AF
    PUSH AF
    JP Z,L_14CC
    OR A
L_0E3B:
    PUSH BC
    PUSH AF
    PUSH HL
    CALL L_2435
    POP HL
    POP AF
    POP BC
    PUSH BC
    CALL C,L_22A2
    POP DE
    POP AF
    PUSH DE
    JP Z,L_0E87
    POP DE
    LD A,[D_0BF3]
    OR A
    JP NZ,L_0E5C
    LD HL,[MEMSIZ]
    LD [FRETOP],HL
L_0E5C:
    LD HL,[VARTAB]
    EX [SP],HL
    POP BC
    PUSH HL
    ADD HL,BC
    PUSH HL
    CALL L_42B6
    POP HL
    LD [VARTAB],HL
    EX DE,HL
    LD [HL],H
    POP BC
    POP DE
    PUSH HL
    INC HL
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD DE,$0823
    DEC BC
    DEC BC
    DEC BC
    DEC BC
L_0E7D:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
    LD A,C
    OR B
    JP NZ,L_0E7D
L_0E87:
    POP DE
    CALL L_0EAF
    LD HL,$0080
    LD [HL],$00
    LD [D_07A4],HL
    LD HL,[D_0794]
    LD [TEMP2],HL
    CALL L_4337
    LD HL,[D_07A2]
    LD [D_07A4],HL
    LD HL,[TEMP2]
    LD [D_0794],HL
    JP MAIN
L_0EAB:
    LD HL,[TXTTAB]
    EX DE,HL
L_0EAF:
    LD H,D
    LD L,E
    LD A,[HL]
    INC HL
    OR [HL]
    RET Z
    INC HL
    INC HL
L_0EB7:
    INC HL
    LD A,[HL]
L_0EB9:
    OR A
    JP Z,L_0ED0
    CP $20
    JP NC,L_0EB7
    CP $0B
    JP C,L_0EB7
    CALL CHRGT2
    CALL CHRGTR
    JP L_0EB9
L_0ED0:
    INC HL
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    JP L_0EAF
L_0ED8:
    LD DE,$0000
    PUSH DE
    JP Z,L_0EEB
    POP DE
    CALL L_141D
    PUSH DE
    JP Z,L_0EF4
    CALL L_43D3
    DI
L_0EEB:
    LD DE,$FFFA
    CALL NZ,L_141D
    JP NZ,SNERR
L_0EF4:
    EX DE,HL
    POP DE
L_0EF6:
    EX [SP],HL
    PUSH HL
L_0EF8:
    LD HL,[TXTTAB]
L_0EFB:
    LD B,H
    LD C,L
    LD A,[HL]
    INC HL
    OR [HL]
    DEC HL
    RET Z
    INC HL
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CALL L_43CD
    LD H,B
    LD L,C
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CCF
    RET Z
    CCF
    RET NC
    JP L_0EFB
L_0F18:
    XOR A
    LD [D_0A69],A
    LD [D_0A68],A
    LD BC,$013B
    LD DE,$0823
L_0F25:
    LD A,[HL]
    OR A
    JP NZ,L_0F3D
L_0F2A:
    LD HL,$0140
    LD A,L
    SUB C
    LD C,A
    LD A,H
    SBC A,B
    LD B,A
    LD HL,$0822
    XOR A
    LD [DE],A
    INC DE
    LD [DE],A
    INC DE
    LD [DE],A
    RET
L_0F3D:
    CP $22
    JP Z,L_0F79
    CP $20
    JP Z,L_0F4F
    LD A,[D_0A68]
    OR A
    LD A,[HL]
    JP Z,L_0F82
L_0F4F:
    INC HL
    PUSH AF
    CALL L_1159
    POP AF
    SUB $3A
    JP Z,L_0F61
    CP $4A
    JP NZ,L_0F67
    LD A,$01
L_0F61:
    LD [D_0A68],A
    LD [D_0A69],A
L_0F67:
    SUB $55
    JP NZ,L_0F25
    PUSH AF
L_0F6D:
    LD A,[HL]
    OR A
    EX [SP],HL
    LD A,H
    POP HL
    JP Z,L_0F2A
    CP [HL]
    JP Z,L_0F4F
L_0F79:
    PUSH AF
    LD A,[HL]
L_0F7B:
    INC HL
    CALL L_1159
    JP L_0F6D
L_0F82:
    CP $3F
    LD A,$91
    PUSH DE
    PUSH BC
    JP Z,L_1048
    LD DE,$046A
    CALL L_1C5A
    CALL L_4504
    JP C,L_1097
    PUSH HL
    LD DE,$0FCC
    CALL L_0FBE
    JP NZ,L_0FD6
    CALL CHRGTR
    LD DE,$0FD0
    CALL L_0FBE
    LD A,$89
    JP Z,L_0FB8
    LD DE,$0FD3
    CALL L_0FBE
    JP NZ,L_0FD6
L_0FB8:
    LD A,$8D
    POP BC
    JP L_1048
L_0FBE:
    LD A,[DE]
    OR A
    RET Z
    LD C,A
    CALL L_1C5A
    CP C
    RET NZ
    INC HL
    INC DE
    JP L_0FBE
    .byte $47, $4F, $20, $00, $54, $4F, $00, $55, $42, $00
L_0FD6:
    POP HL
    CALL L_1C5A
    PUSH HL
    LD HL,$0207
    SUB $41
    ADD A,A
    LD C,A
    LD B,$00
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    POP HL
    INC HL
L_0FEA:
    PUSH HL
L_0FEB:
    CALL L_1C5A
    LD C,A
    LD A,[DE]
    AND $7F
    JP Z,L_1164
    INC HL
    CP C
    JP NZ,L_103C
    LD A,[DE]
    INC DE
    OR A
    JP P,L_0FEB
    LD A,C
    CP $28
    JP Z,L_1021
    LD A,[DE]
    CP $D3
    JP Z,L_1021
    CP $D2
    JP Z,L_1021
    CALL L_1C5A
    CP $2E
    JP Z,L_101C
    CALL L_21E2
L_101C:
    LD A,$00
    JP NC,L_1164
L_1021:
    POP AF
    LD A,[DE]
    OR A
    JP M,L_1047
    POP BC
    POP DE
    OR $80
    PUSH AF
    LD A,$FF
    CALL L_1159
    XOR A
    LD [D_0A69],A
    POP AF
    CALL L_1159
    JP L_0F25
L_103C:
    POP HL
L_103D:
    LD A,[DE]
    INC DE
    OR A
    JP P,L_103D
    INC DE
    JP L_0FEA
L_1047:
    DEC HL
L_1048:
    PUSH AF
    LD DE,$105A
    LD C,A
L_104D:
    LD A,[DE]
    OR A
    JP Z,L_1069
    INC DE
    CP C
    JP NZ,L_104D
    JP L_106B
    .byte $8C, $AB, $AC, $AA, $A7, $A9, $D6, $A2, $8A, $93, $9F, $89, $CF, $8D, $00
L_1069:
    XOR A
    .byte $C2
L_106B:
    LD A,$01
L_106D:
    LD [D_0A69],A
    POP AF
    POP BC
    POP DE
    CP $A2
    PUSH AF
    CALL Z,L_1157
    POP AF
    CP $B4
    JP NZ,L_1084
    CALL L_1159
    LD A,$F2
L_1084:
    CP $DB
    JP NZ,L_1135
    PUSH AF
    CALL L_1157
    LD A,$8F
    CALL L_1159
    POP AF
    PUSH AF
    JP L_0F7B
L_1097:
    LD A,[HL]
    CP $2E
    JP Z,L_10A7
    CP $3A
    JP NC,L_1122
    CP $30
    JP C,L_1122
L_10A7:
    LD A,[D_0A69]
    OR A
    LD A,[HL]
    POP BC
    POP DE
    JP M,L_0F4F
    JP Z,L_10D3
    CP $2E
    JP Z,L_0F4F
    LD A,$0E
    CALL L_1159
    PUSH DE
    CALL L_1428
    CALL L_11AC
L_10C5:
    EX [SP],HL
    EX DE,HL
L_10C7:
    LD A,L
    CALL L_1159
    LD A,H
L_10CC:
    POP HL
    CALL L_1159
    JP L_0F25
L_10D3:
    PUSH DE
    PUSH BC
    LD A,[HL]
    CALL L_2ED1
    CALL L_11AC
    POP BC
    POP DE
    PUSH HL
    LD A,[D_0A67]
    CP $02
    JP NZ,L_10FF
    LD HL,[D_0C04]
    LD A,H
    OR A
    LD A,$02
    JP NZ,L_10FF
    LD A,L
    LD H,L
    LD L,$0F
    CP $0A
    JP NC,L_10C7
    ADD A,$11
    JP L_10CC
L_10FF:
    PUSH AF
    RRCA
    ADD A,$1B
    CALL L_1159
    LD HL,$0C04
    CALL L_1D64
    JP C,L_1112
    LD HL,$0C00
L_1112:
    POP AF
L_1113:
    PUSH AF
    LD A,[HL]
    CALL L_1159
    POP AF
    INC HL
    DEC A
    JP NZ,L_1113
    POP HL
    JP L_0F25
L_1122:
    LD DE,$0469
L_1125:
    INC DE
    LD A,[DE]
    AND $7F
    JP Z,L_118E
    INC DE
    CP [HL]
    LD A,[DE]
    JP NZ,L_1125
    JP L_11A0
L_1135:
    CP $26
    JP NZ,L_0F4F
    PUSH HL
    CALL CHRGTR
    POP HL
    CALL L_1C5B
    CP $48
    LD A,$0B
    JP NZ,L_114B
    LD A,$0C
L_114B:
    CALL L_1159
    PUSH DE
    PUSH BC
    CALL L_1C69
    POP BC
    JP L_10C5
L_1157:
    LD A,$3A
L_1159:
    LD [DE],A
    INC DE
    DEC BC
    LD A,C
    OR B
    RET NZ
L_115F:
    LD E,$17
    JP ERROR
L_1164:
    POP HL
    DEC HL
    DEC A
    LD [D_0A69],A
    POP BC
    POP DE
    CALL L_1C5A
L_116F:
    CALL L_1159
    INC HL
    CALL L_1C5A
    CALL L_4504
    JP NC,L_116F
    CP $3A
    JP NC,L_118B
    CP $30
    JP NC,L_116F
    CP $2E
    JP Z,L_116F
L_118B:
    JP L_0F25
L_118E:
    LD A,[HL]
    CP $20
    JP NC,L_11A0
    CP $09
    JP Z,L_11A0
    CP $0A
    JP Z,L_11A0
    LD A,$20
L_11A0:
    PUSH AF
    LD A,[D_0A69]
    INC A
    JP Z,L_11A9
    DEC A
L_11A9:
    JP L_106D
L_11AC:
    DEC HL
    LD A,[HL]
    CP $20
    JP Z,L_11AC
    CP $09
    JP Z,L_11AC
    CP $0A
    JP Z,L_11AC
    INC HL
    RET
