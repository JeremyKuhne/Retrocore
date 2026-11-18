;; MBASIC 5.21: LIST, DELETE AND RENUM
;;
;; Part of Mbasic.asm.

ST_LLIST:
    LD A,$01
    LD [D_078D],A
ST_LIST:
    POP BC
    CALL L_0ED8
    PUSH BC
    CALL L_5D65
L_2091:
    LD HL,$FFFF
    LD [CURLIN],HL
    POP HL
    POP DE
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    LD A,B
    OR C
    JP Z,READY
    CALL L_4654
    CALL Z,L_4251
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    EX [SP],HL
    EX DE,HL
    CALL L_43CD
    POP BC
    JP C,STPRDY
    EX [SP],HL
    PUSH HL
    PUSH BC
    EX DE,HL
    LD [DOT],HL
    CALL LINPRT
    POP HL
    LD A,[HL]
    CP $09
    JP Z,L_20CD
    LD A,$20
    CALL OUTDO
L_20CD:
    CALL L_20E6
    LD HL,$0962
    CALL L_20DC
    CALL L_4221
    JP L_2091
L_20DC:
    LD A,[HL]
    OR A
    RET Z
    CALL L_42A5
    INC HL
    JP L_20DC
L_20E6:
    LD BC,$0962
    LD D,$FF
    XOR A
    LD [D_0BE6],A
    CALL L_5D65
    JP L_20F9
L_20F5:
    INC BC
    INC HL
    DEC D
    RET Z
L_20F9:
    LD A,[HL]
    OR A
    LD [BC],A
    RET Z
    CP $0B
    JP C,L_2108
    CP $20
    LD E,A
    JP C,L_211C
L_2108:
    OR A
    JP M,L_2141
    LD E,A
    CP $2E
    JP Z,L_211C
    CALL L_21E2
    JP NC,L_211C
    XOR A
    JP L_212F
L_211C:
    LD A,[D_0BE6]
    OR A
    JP Z,L_212D
    INC A
    JP NZ,L_212D
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    RET Z
L_212D:
    LD A,$01
L_212F:
    LD [D_0BE6],A
    LD A,E
    CP $0B
    JP C,L_213D
    CP $20
    JP C,L_21ED
L_213D:
    LD [BC],A
    JP L_20F5
L_2141:
    INC A
    LD A,[HL]
    JP NZ,L_214A
    INC HL
    LD A,[HL]
    AND $7F
L_214A:
    INC HL
    CP $DB
    JP NZ,L_2158
    DEC BC
    DEC BC
    DEC BC
    DEC BC
    INC D
    INC D
    INC D
    INC D
L_2158:
    CP $A2
    CALL Z,L_2A6B
    CP $B4
    JP NZ,L_216C
    LD A,[HL]
    INC HL
    CP $F2
    LD A,$B4
    JP Z,L_216C
    DEC HL
L_216C:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,$023A
    LD B,A
    LD C,$40
L_2175:
    INC C
L_2176:
    INC HL
    LD D,H
    LD E,L
L_2179:
    LD A,[HL]
    OR A
    JP Z,L_2175
    INC HL
    JP P,L_2179
    LD A,[HL]
    CP B
    JP NZ,L_2176
    EX DE,HL
    CP $D2
    JP Z,L_218F
    CP $D3
L_218F:
    LD A,C
    POP DE
    POP BC
    LD E,A
    JP NZ,L_21A2
    LD A,[D_0BE6]
    OR A
    LD A,$00
    LD [D_0BE6],A
    JP L_21B7
L_21A2:
    CP $5B
    JP NZ,L_21AE
    XOR A
    LD [D_0BE6],A
    JP L_21C6
L_21AE:
    LD A,[D_0BE6]
    OR A
    LD A,$FF
    LD [D_0BE6],A
L_21B7:
    JP Z,L_21C2
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP Z,L_4758
L_21C2:
    LD A,E
    JP L_21C9
L_21C6:
    LD A,[HL]
    INC HL
    LD E,A
L_21C9:
    AND $7F
    LD [BC],A
    INC BC
    DEC D
    JP Z,L_4758
    OR E
    JP P,L_21C6
    CP $A8
    JP NZ,L_21DE
    XOR A
    LD [D_0BE6],A
L_21DE:
    POP HL
    JP L_20F9
L_21E2:
    CALL L_4504
    RET NC
    CP $30
    RET C
    CP $3A
    CCF
    RET
L_21ED:
    DEC HL
    CALL CHRGTR
    PUSH DE
    PUSH BC
    PUSH AF
    CALL L_138E
    POP AF
    LD BC,$220C
    PUSH BC
    CP $0B
    JP Z,L_366F
    CP $0C
    JP Z,L_3672
    LD HL,[D_0A6E]
    JP L_3129
    .byte $C1, $D1, $3A, $6C, $0A, $1E, $4F, $FE, $0B, $CA, $1F, $22, $FE, $0C, $1E, $48
    .byte $C2, $2A, $22, $3E, $26, $02, $03, $15, $C8, $7B, $02, $03, $15, $C8, $3A, $6D
    .byte $0A, $FE, $04, $1E, $00, $DA, $3B, $22, $1E, $21, $CA, $3B, $22, $1E, $23, $7E
    .byte $FE, $20, $CC, $BE, $28, $7E, $23, $B7, $CA, $6D, $22, $02, $03, $15, $C8, $3A
    .byte $6D, $0A, $FE, $04, $DA, $41, $22, $0B, $0A, $03, $C2, $5E, $22, $FE, $2E, $CA
    .byte $68, $22, $FE, $44, $CA, $68, $22, $FE, $45, $C2, $41, $22, $1E, $00, $C3, $41
    .byte $22, $7B, $B7, $CA, $76, $22, $02, $03, $15, $C8, $2A, $6A, $0A, $C3, $F9, $20
ST_DELETE:
    CALL L_0ED8
    PUSH BC
    CALL L_2435
    POP BC
    POP DE
    PUSH BC
    PUSH BC
    CALL L_0EF8
    JP NC,L_2294
    LD D,H
    LD E,L
    EX [SP],HL
    PUSH HL
    CALL L_43CD
L_2294:
    JP NC,L_1418
    LD HL,$0C45
    CALL L_4723
    POP BC
    LD HL,$0E87
    EX [SP],HL
L_22A2:
    EX DE,HL
    LD HL,[VARTAB]
L_22A6:
    LD A,[DE]
    LD [BC],A
    INC BC
    INC DE
    CALL L_43CD
    JP NZ,L_22A6
    LD H,B
    LD L,C
    LD [VARTAB],HL
    RET
FN_PEEK:
    CALL L_22DB
    CALL L_5D5C
    LD A,[HL]
    JP L_1DD5
ST_POKE:
    CALL L_22D1
    PUSH DE
    CALL L_5D5C
    CALL L_43D3
    INC L
    CALL L_2075
    POP DE
    LD [DE],A
    RET
L_22D1:
    CALL L_1A02
    PUSH HL
    CALL L_22DB
    EX DE,HL
    POP HL
    RET
L_22DB:
    LD BC,$297A
    PUSH BC
    CALL L_1D64
    RET M
    LD A,[D_0C07]
    CP $90
    RET NZ
    CALL L_2845
    RET M
    CALL FN_CSNG
    LD BC,$9180
    LD DE,$0000
    JP L_2588
ST_RENUM:
    LD BC,$000A
    PUSH BC
    LD D,B
    LD E,B
    JP Z,L_232F
    CP $2C
    JP Z,L_2311
    PUSH DE
    CALL L_141D
    LD B,D
    LD C,E
    POP DE
    JP Z,L_232F
L_2311:
    CALL L_43D3
    INC L
    CALL L_141D
    JP Z,L_232F
    POP AF
    CALL L_43D3
    INC L
    PUSH DE
    CALL L_1428
    JP NZ,SNERR
    LD A,D
    OR E
    JP Z,L_1418
    EX DE,HL
    EX [SP],HL
    EX DE,HL
L_232F:
    PUSH BC
    CALL L_0EF8
    POP DE
    PUSH DE
    PUSH BC
    CALL L_0EF8
    LD H,B
    LD L,C
    POP DE
    CALL L_43CD
    EX DE,HL
    JP C,L_1418
    POP DE
    POP BC
    POP AF
    PUSH HL
    PUSH DE
    JP L_235B
L_234B:
    ADD HL,BC
    JP C,L_1418
    EX DE,HL
    PUSH HL
    LD HL,$FFF9
    CALL L_43CD
    POP HL
    JP C,L_1418
L_235B:
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    EX DE,HL
    POP DE
    JP Z,L_236E
    LD A,[HL]
    INC HL
    OR [HL]
    DEC HL
    EX DE,HL
    JP NZ,L_234B
L_236E:
    PUSH BC
    CALL L_2391
    POP BC
    POP DE
    POP HL
L_2375:
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    JP Z,L_238C
    EX DE,HL
    EX [SP],HL
    EX DE,HL
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    EX DE,HL
    ADD HL,BC
    EX DE,HL
    POP HL
    JP L_2375
L_238C:
    LD BC,$0D86
    PUSH BC
    .byte $FE
L_2391:
    .byte $F6
L_2392:
    XOR A
    LD [PTRFLG],A
    LD HL,[TXTTAB]
    DEC HL
L_239A:
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    RET Z
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
L_23A3:
    CALL CHRGTR
L_23A6:
    OR A
    JP Z,L_239A
    LD C,A
    LD A,[PTRFLG]
    OR A
    LD A,C
    JP Z,L_2412
    CP $A8
    JP NZ,L_23D4
    CALL CHRGTR
    CP $89
    JP NZ,L_23A6
    CALL CHRGTR
    CP $0E
    JP NZ,L_23A6
    PUSH DE
    CALL L_1433
    LD A,D
    OR E
    JP NZ,L_23DD
    JP L_23FD
L_23D4:
    CP $0E
    JP NZ,L_23A3
    PUSH DE
    CALL L_1433
L_23DD:
    PUSH HL
    CALL L_0EF8
    DEC BC
    LD A,$0D
    JP C,L_2425
    CALL L_4214
    LD HL,$2402
    PUSH DE
    CALL L_4723
    POP HL
    CALL LINPRT
    POP BC
    POP HL
    PUSH HL
    PUSH BC
    CALL L_3112
    POP HL
L_23FD:
    POP DE
    DEC HL
L_23FF:
    JP L_23A3
    .byte $55, $6E, $64, $65, $66, $69, $6E, $65, $64, $20, $6C, $69, $6E, $65, $20, $00
L_2412:
    CP $0D
    JP NZ,L_23FF
    PUSH DE
    CALL L_1433
    PUSH HL
    EX DE,HL
    INC HL
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,$0E
L_2425:
    LD HL,$23FC
    PUSH HL
    LD HL,[D_0A6A]
L_242C:
    PUSH HL
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    LD [HL],A
    POP HL
    RET
L_2435:
    LD A,[PTRFLG]
    OR A
    RET Z
    JP L_2392
ST_OPTION:
    CALL L_43D3
    LD B,D
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_43D3
    LD B,L
    LD A,[D_0BC7]
    OR A
    JP NZ,DDERR
    PUSH HL
    LD HL,[ARYTAB]
    EX DE,HL
    LD HL,[STREND]
    CALL L_43CD
    JP NZ,DDERR
    POP HL
    LD A,[HL]
    SUB $30
    JP C,SNERR
    CP $02
    JP NC,SNERR
    LD [D_0BC6],A
    INC A
    LD [D_0BC7],A
    CALL CHRGTR
    RET
L_2479:
    LD A,[HL]
    OR A
    RET Z
    CALL L_2483
    INC HL
    JP L_2479
L_2483:
    PUSH AF
    JP L_415C
