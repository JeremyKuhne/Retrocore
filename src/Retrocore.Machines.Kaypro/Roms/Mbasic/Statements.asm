;; MBASIC 5.21: STATEMENTS: FOR, NEWSTT AND THE CONTROL STATEMENTS
;;
;; Part of Mbasic.asm.

ST_FOR:
    LD A,$64
    LD [SUBFLG],A
    CALL L_398B
    CALL L_43D3
    RET P
    PUSH DE
    EX DE,HL
    LD [TEMP],HL
    EX DE,HL
    LD A,[D_0A67]
    PUSH AF
    CALL L_1A02
    POP AF
    PUSH HL
    CALL L_1FAC
    LD HL,$0BC0
    CALL L_28C0
    POP HL
    POP DE
    POP BC
    PUSH HL
    CALL ST_DATA
    LD [ENDFOR],HL
    LD HL,$0002
    ADD HL,SP
L_11F1:
    CALL L_0C54
    JP NZ,L_1211
    ADD HL,BC
    PUSH DE
    DEC HL
    LD D,[HL]
    DEC HL
    LD E,[HL]
    INC HL
    INC HL
    PUSH HL
    LD HL,[ENDFOR]
    CALL L_43CD
    POP HL
    POP DE
    JP NZ,L_11F1
    POP DE
    LD SP,HL
    LD [SAVSTK],HL
    .byte $0E
L_1211:
    .byte $D1
    EX DE,HL
    LD C,$08
    CALL L_42C7
    PUSH HL
    LD HL,[ENDFOR]
    EX [SP],HL
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL
    CALL L_43D3
    ADC A,$CD
    LD H,H
    DEC E
    JP Z,TMERR
    JP NC,TMERR
    PUSH AF
    CALL L_1A02
    POP AF
    PUSH HL
    JP P,L_124E
    CALL FN_CINT
    EX [SP],HL
    LD DE,$0001
    LD A,[HL]
    CP $D1
    CALL Z,L_2053
    PUSH DE
    PUSH HL
    EX DE,HL
    CALL L_2892
    JP L_1271
L_124E:
    CALL FN_CSNG
    CALL L_28B4
    POP HL
    PUSH BC
    PUSH DE
    LD BC,$8100
    LD D,C
    LD E,D
    LD A,[HL]
    CP $D1
    LD A,$01
    JP NZ,L_1272
    CALL L_1A03
    PUSH HL
    CALL FN_CSNG
    CALL L_28B4
    CALL L_2845
L_1271:
    POP HL
L_1272:
    PUSH BC
    PUSH DE
    LD C,A
    CALL L_1D64
    LD B,A
    PUSH BC
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    CALL L_24E2
    CALL CHRGTR
    PUSH HL
    PUSH HL
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    LD HL,[TEMP]
    EX [SP],HL
    LD B,$82
    PUSH BC
    INC SP
    PUSH AF
    PUSH AF
    JP L_45A0
L_129C:
    LD B,$82
    PUSH BC
    INC SP
NEWSTT:
    PUSH HL
    .byte $CD
D_12A2:
    .byte $00, $00
    POP HL
    OR A
    CALL NZ,L_425C
    LD [SAVTXT],HL
    EX DE,HL
    LD HL,$0000
    ADD HL,SP
    LD [SAVSTK],HL
    EX DE,HL
    LD A,[HL]
    CP $3A
    JP Z,GONE
    OR A
    JP NZ,SNERR
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,GOPRGD
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL
    LD A,[TRCFLG]
    OR A
    JP Z,L_12E4
    PUSH DE
    LD A,$5B
    CALL OUTDO
    CALL LINPRT
    LD A,$5D
    CALL OUTDO
    POP DE
L_12E4:
    EX DE,HL
GONE:
    CALL CHRGTR
    LD DE,$12A0
    PUSH DE
    RET Z
L_12ED:
    SUB $81
    JP C,LET
    CP $4C
    JP NC,L_1FE2
    RLCA
    LD C,A
    LD B,$00
    EX DE,HL
    LD HL,$0107
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    EX DE,HL
CHRGTR:
    INC HL
CHRGT2:
    LD A,[HL]
    CP $3A
    RET NC
L_130A:
    CP $20
    JP Z,CHRGTR
    JP NC,L_1386
    OR A
    RET Z
    CP $0B
    JP C,L_1381
    CP $1E
    JP NZ,L_1323
    LD A,[D_0A6C]
    OR A
    RET
L_1323:
    CP $10
    JP Z,L_1360
    PUSH AF
    INC HL
    LD [D_0A6C],A
    SUB $1C
    JP NC,L_1366
    SUB $F5
    JP NC,L_133E
    CP $FE
    JP NZ,L_1352
    LD A,[HL]
    INC HL
L_133E:
    LD [D_0A6A],HL
    LD H,$00
L_1343:
    LD L,A
    LD [D_0A6E],HL
    LD A,$02
    LD [D_0A6D],A
    LD HL,$138C
    POP AF
    OR A
    RET
L_1352:
    LD A,[HL]
    INC HL
    INC HL
    LD [D_0A6A],HL
    DEC HL
    LD H,[HL]
    JP L_1343
L_135D:
    CALL L_138E
L_1360:
    LD HL,[D_0A6A]
    JP CHRGT2
L_1366:
    INC A
    RLCA
    LD [D_0A6D],A
    PUSH DE
    PUSH BC
    LD DE,$0A6E
    EX DE,HL
    LD B,A
    CALL L_28CD
    EX DE,HL
    POP BC
    POP DE
    LD [D_0A6A],HL
    POP AF
    LD HL,$138C
    OR A
    RET
L_1381:
    CP $09
    JP NC,CHRGTR
L_1386:
    CP $30
    CCF
    INC A
    DEC A
    RET
    .byte $1E, $10
L_138E:
    LD A,[D_0A6C]
    CP $0F
    JP NC,L_13AB
    CP $0D
    JP C,L_13AB
    LD HL,[D_0A6E]
    JP NZ,L_13A8
    INC HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
L_13A8:
    JP L_2C03
L_13AB:
    LD A,[D_0A6D]
    LD [D_0A67],A
    CP $08
    JP Z,L_13C3
    LD HL,[D_0A6E]
    LD [D_0C04],HL
    LD HL,[D_0A70]
    LD [D_0C06],HL
    RET
L_13C3:
    LD HL,$0A6E
    JP L_28EE
ST_DEFSTR:
    LD E,$03
    .byte $01
ST_DEFINT:
    LD E,$02
    .byte $01
ST_DEFSNG:
    LD E,$04
    .byte $01
ST_DEFDBL:
    LD E,$08
L_13D4:
    CALL L_4503
    LD BC,$0CC9
    PUSH BC
    RET C
    SUB $41
    LD C,A
    LD B,A
    CALL CHRGTR
    CP $F3
    JP NZ,L_13F5
    CALL CHRGTR
    CALL L_4503
    RET C
    SUB $41
    LD B,A
    CALL CHRGTR
L_13F5:
    LD A,B
    SUB C
    RET C
    INC A
    EX [SP],HL
    LD HL,$0ACA
    LD B,$00
    ADD HL,BC
L_1400:
    LD [HL],E
    INC HL
    DEC A
    JP NZ,L_1400
    POP HL
    LD A,[HL]
    CP $2C
    RET NZ
    CALL CHRGTR
    JP L_13D4
L_1411:
    CALL CHRGTR
L_1414:
    CALL L_2056
    RET P
L_1418:
    LD E,$05
    JP ERROR
L_141D:
    LD A,[HL]
    CP $2E
    EX DE,HL
    LD HL,[DOT]
    EX DE,HL
    JP Z,CHRGTR
L_1428:
    DEC HL
L_1429:
    CALL CHRGTR
    CP $0E
    JP Z,L_1433
    CP $0D
L_1433:
    EX DE,HL
    LD HL,[D_0A6E]
    EX DE,HL
    JP Z,CHRGTR
    XOR A
    LD [D_0A6C],A
    DEC HL
    LD DE,$0000
L_1443:
    CALL CHRGTR
    RET NC
    PUSH HL
    PUSH AF
    LD HL,$1998
    CALL L_43CD
    JP C,L_1464
    LD H,D
    LD L,E
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    POP AF
    SUB $30
    LD E,A
    LD D,$00
    ADD HL,DE
    EX DE,HL
    POP HL
    JP L_1443
L_1464:
    POP AF
    POP HL
    RET
ST_RUN:
    JP Z,L_4337
    CP $0E
    JP Z,L_1474
    CP $0D
    JP NZ,L_529A
L_1474:
    CALL L_433B
    LD BC,$12A0
    JP L_1494
ST_GOSUB:
    LD C,$03
    CALL L_42C7
    CALL L_1428
    POP BC
    PUSH HL
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL
    LD A,$8D
    PUSH AF
    INC SP
    PUSH BC
    JP L_1498
L_1494:
    PUSH BC
ST_GOTO:
    CALL L_1428
L_1498:
    LD A,[D_0A6C]
    CP $0D
    EX DE,HL
    RET Z
    CP $0E
    JP NZ,SNERR
    EX DE,HL
    PUSH HL
    LD HL,[D_0A6A]
    EX [SP],HL
    CALL ST_REM
    INC HL
    PUSH HL
    LD HL,[CURLIN]
    CALL L_43CD
    POP HL
    CALL C,L_0EFB
    CALL NC,L_0EF8
    JP NC,L_14CC
    DEC BC
    LD A,$0D
    LD [PTRFLG],A
    POP HL
    CALL L_242C
    LD H,B
    LD L,C
    RET
L_14CC:
    LD E,$08
    JP ERROR
ST_RETURN:
    RET NZ
    LD D,$FF
    CALL L_0C50
    LD SP,HL
    LD [SAVSTK],HL
    CP $8D
    LD E,$03
    JP NZ,ERROR
    POP HL
    LD [CURLIN],HL
    LD HL,$12A0
    EX [SP],HL
    LD A,$E1
ST_DATA:
    .byte $01, $3A
ST_REM:
    .byte $0E
    NOP
    LD B,$00
L_14F2:
    LD A,C
    LD C,B
    LD B,A
L_14F5:
    DEC HL
L_14F6:
    CALL CHRGTR
    OR A
    RET Z
    CP B
    RET Z
    INC HL
    CP $22
    JP Z,L_14F2
    INC A
    JP Z,L_14F6
    SUB $8C
    JP NZ,L_14F5
    CP B
    ADC A,D
    LD D,A
    JP L_14F5
    .byte $F1, $C6, $03, $C3, $2D, $15
LET:
    CALL L_398B
    CALL L_43D3
    RET P
    EX DE,HL
    LD [TEMP],HL
    EX DE,HL
    PUSH DE
    LD A,[D_0A67]
    PUSH AF
    CALL L_1A02
    POP AF
L_152D:
    EX [SP],HL
L_152E:
    LD B,A
    LD A,[D_0A67]
    CP B
    LD A,B
    JP Z,L_153D
    CALL L_1FAC
L_153A:
    LD A,[D_0A67]
L_153D:
    LD DE,$0C04
    CP $05
    JP C,L_1548
    LD DE,$0C00
L_1548:
    PUSH HL
    CP $03
    JP NZ,L_157F
    LD HL,[D_0C04]
    PUSH HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_1573
    LD HL,[STREND]
    CALL L_43CD
    POP DE
    JP NC,L_157B
    LD HL,$0A98
    CALL L_43CD
    JP NC,L_157B
    .byte $3E
L_1573:
    .byte $D1
    CALL L_48C6
    EX DE,HL
    CALL L_46A3
L_157B:
    CALL L_48C6
    EX [SP],HL
L_157F:
    CALL L_28C9
    POP DE
    POP HL
    RET
ST_ON:
    CP $A8
    JP NZ,L_15B5
    CALL CHRGTR
    CALL L_43D3
    ADC A,C
    CALL L_1428
    LD A,D
    OR E
    JP Z,L_15A2
    CALL L_0EF6
    LD D,B
    LD E,C
    POP HL
    JP NC,L_14CC
L_15A2:
    EX DE,HL
    LD [ONELIN],HL
    EX DE,HL
    RET C
    LD A,[ONEFLG]
    OR A
    LD A,E
    RET Z
    LD A,[D_078A]
    LD E,A
    JP L_0CF9
L_15B5:
    CALL L_2075
    LD A,[HL]
    LD B,A
    CP $8D
    JP Z,L_15C4
    CALL L_43D3
    ADC A,C
    DEC HL
L_15C4:
    LD C,E
L_15C5:
    DEC C
    LD A,B
    JP Z,L_12ED
    CALL L_1429
    CP $2C
    RET NZ
    JP L_15C5
ST_RESUME:
    LD DE,$0ABB
    LD A,[DE]
    OR A
    JP Z,REERR
    INC A
    LD [D_078A],A
    LD [DE],A
    LD A,[HL]
    CP $83
    JP Z,L_15F3
    CALL L_1428
    RET NZ
    LD A,D
    OR E
    JP NZ,L_1498
    INC A
    JP L_15F7
L_15F3:
    CALL CHRGTR
    RET NZ
L_15F7:
    LD HL,[ERRTXT]
    EX DE,HL
    LD HL,[ERRLIN]
    LD [CURLIN],HL
    EX DE,HL
    RET NZ
    LD A,[HL]
    OR A
    JP NZ,L_160C
    INC HL
    INC HL
    INC HL
    INC HL
L_160C:
    INC HL
    JP ST_DATA
ST_ERROR:
    CALL L_2075
    RET NZ
    OR A
    JP Z,L_1418
    JP ERROR
ST_AUTO:
    LD DE,$000A
    PUSH DE
    JP Z,L_163D
    CALL L_141D
    EX DE,HL
    EX [SP],HL
    JP Z,L_163E
    EX DE,HL
    CALL L_43D3
    INC L
    EX DE,HL
    LD HL,[AUTINC]
    EX DE,HL
    JP Z,L_163D
    CALL L_1428
    JP NZ,SNERR
L_163D:
    EX DE,HL
L_163E:
    LD A,H
    OR L
    JP Z,L_1418
    LD [AUTINC],HL
    LD [AUTFLG],A
    POP HL
    LD [AUTLIN],HL
    POP BC
    JP MAIN
ST_IF:
    CALL L_1A02
    LD A,[HL]
    CP $2C
    CALL Z,CHRGTR
    CP $89
    JP Z,L_1664
    CALL L_43D3
    RST $08
    DEC HL
L_1664:
    PUSH HL
    CALL L_2886
    POP HL
    JP Z,L_167E
L_166C:
    CALL CHRGTR
    RET Z
    CP $0E
    JP Z,ST_GOTO
    CP $0D
    JP NZ,L_12ED
    LD HL,[D_0A6E]
    RET
L_167E:
    LD D,$01
L_1680:
    CALL ST_DATA
    OR A
    RET Z
    CALL CHRGTR
    CP $A2
    JP NZ,L_1680
    DEC D
    JP NZ,L_1680
    JP L_166C
