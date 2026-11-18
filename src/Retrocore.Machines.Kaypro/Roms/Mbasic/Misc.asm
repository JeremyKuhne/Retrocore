;; MBASIC 5.21: NEW, CLEAR, NEXT AND OTHER STATEMENTS
;;
;; Part of Mbasic.asm.

ST_NEW:
    RET NZ
L_4321:
    LD HL,[TXTTAB]
    CALL ST_TROFF
    LD [D_0BEC],A
    LD [AUTFLG],A
    LD [PTRFLG],A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [VARTAB],HL
L_4337:
    LD HL,[TXTTAB]
    DEC HL
L_433B:
    LD [TEMP],HL
    LD A,[D_0BED]
    OR A
    JP NZ,L_4358
    XOR A
    LD [D_0BC7],A
    LD [D_0BC6],A
    LD B,$1A
    LD HL,$0ACA
L_4351:
    LD [HL],$04
    INC HL
    DEC B
    JP NZ,L_4351
L_4358:
    LD DE,$37C8
    LD HL,$3869
    CALL L_28C3
    LD HL,$3846
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    XOR A
    LD [ONEFLG],A
    LD L,A
    LD H,A
    LD [ONELIN],HL
    LD [OLDTXT],HL
    LD HL,[MEMSIZ]
    LD A,[D_0BF3]
    OR A
    JP NZ,L_4383
    LD [FRETOP],HL
L_4383:
    XOR A
    CALL ST_RESTORE
    LD HL,[VARTAB]
    LD [ARYTAB],HL
    LD [STREND],HL
    LD A,[D_0BED]
    OR A
    CALL Z,L_540D
L_4397:
    POP BC
    LD HL,[TOPMEM]
    DEC HL
    DEC HL
    LD [SAVSTK],HL
    INC HL
    INC HL
L_43A2:
    LD SP,HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    CALL L_2572
    CALL L_4144
    CALL L_17E9
    XOR A
    LD H,A
    LD L,A
    LD [D_0AE6],HL
    LD [D_0BB7],A
    LD [D_0B4E],HL
    LD [D_0BBA],HL
    LD [D_0AE4],HL
    LD [SUBFLG],A
    PUSH HL
    PUSH BC
L_43C9:
    LD HL,[TEMP]
    RET
L_43CD:
    LD A,H
    SUB D
    RET NZ
    LD A,L
    SUB E
    RET
L_43D3:
    LD A,[HL]
    EX [SP],HL
    CP [HL]
    JP NZ,L_43E3
    INC HL
    EX [SP],HL
    INC HL
    LD A,[HL]
    CP $3A
    RET NC
    JP L_130A
L_43E3:
    JP SNERR
ST_RESTORE:
    EX DE,HL
    LD HL,[TXTTAB]
    JP Z,L_43FB
    EX DE,HL
    CALL L_1428
    PUSH HL
    CALL L_0EF8
    LD H,B
    LD L,C
    POP DE
    JP NC,L_14CC
L_43FB:
    DEC HL
    LD [DATPTR],HL
    EX DE,HL
    RET
ST_STOP:
    RET NZ
    INC A
    JP STPEND
ST_END:
    RET NZ
    PUSH AF
    CALL Z,L_540D
    POP AF
STPEND:
    LD [SAVTXT],HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    .byte $21
L_4416:
    .byte $F6, $FF
    POP BC
ENDCON:
    LD HL,[CURLIN]
    PUSH HL
    PUSH AF
    LD A,L
    AND H
    INC A
    JP Z,L_442D
    LD [OLDLIN],HL
    LD HL,[SAVTXT]
    LD [OLDTXT],HL
L_442D:
    XOR A
    LD [D_0793],A
    CALL L_4144
    CALL L_4214
    POP AF
    LD HL,$0C4A
    JP NZ,ERRFIN
    JP STPRDY
L_4441:
    LD A,$0F
L_4443:
    PUSH AF
    SUB $03
    JP NZ,L_444F
    LD [D_078D],A
    LD [D_0793],A
L_444F:
    LD A,$5E
    CALL OUTDO
    POP AF
    ADD A,$40
    CALL OUTDO
    JP L_4221
ST_CONT:
    LD HL,[OLDTXT]
    LD A,H
    OR L
    LD DE,$0011
    JP Z,ERROR
    EX DE,HL
    LD HL,[OLDLIN]
    EX DE,HL
    EX DE,HL
    LD [CURLIN],HL
    EX DE,HL
    RET
ST_NULL:
    CALL L_2075
    RET NZ
    INC A
    LD [D_0788],A
    RET
ST_TRON:
    .byte $3E
ST_TROFF:
    .byte $AF
    LD [TRCFLG],A
    RET
ST_SWAP:
    CALL L_398B
    PUSH DE
    PUSH HL
    LD HL,$0BF6
    CALL L_28C9
    LD HL,[ARYTAB]
    EX [SP],HL
    CALL L_1D64
    PUSH AF
    CALL L_43D3
    INC L
    CALL L_398B
    POP AF
    LD B,A
    CALL L_1D64
    CP B
    JP NZ,TMERR
    EX [SP],HL
    EX DE,HL
    PUSH HL
    LD HL,[ARYTAB]
    CALL L_43CD
    JP NZ,L_44C1
    POP DE
    POP HL
    EX [SP],HL
    PUSH DE
    CALL L_28C9
    POP HL
    LD DE,$0BF6
    CALL L_28C9
    POP HL
    RET
L_44C1:
    JP L_1418
ST_ERASE:
    LD A,$01
    LD [SUBFLG],A
    CALL L_398B
    JP NZ,L_44C1
    PUSH HL
    LD [SUBFLG],A
    LD H,B
    LD L,C
    DEC BC
    DEC BC
    DEC BC
L_44D8:
    LD A,[BC]
    DEC BC
    OR A
    JP M,L_44D8
    DEC BC
    DEC BC
    ADD HL,DE
    EX DE,HL
    LD HL,[STREND]
L_44E5:
    CALL L_43CD
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,L_44E5
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    POP HL
    LD A,[HL]
    CP $2C
    RET NZ
    CALL CHRGTR
    JP ST_ERASE
L_4500:
    POP AF
    POP HL
    RET
L_4503:
    LD A,[HL]
L_4504:
    CP $41
    RET C
    CP $5B
    CCF
    RET
L_450B:
    JP L_433B
ST_CLEAR:
    JP Z,L_450B
    CP $2C
    JP Z,L_4520
    CALL L_1414
    DEC HL
    CALL CHRGTR
    JP Z,L_450B
L_4520:
    CALL L_43D3
    INC L
    JP Z,L_450B
    EX DE,HL
    LD HL,[TOPMEM]
    EX DE,HL
    CP $2C
    JP Z,L_4534
    CALL L_4579
L_4534:
    DEC HL
    CALL CHRGTR
    PUSH DE
    JP Z,L_4585
    CALL L_43D3
    INC L
    JP Z,L_4585
    CALL L_4579
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
L_454D:
    EX [SP],HL
    PUSH HL
    LD HL,$004E
    CALL L_43CD
    JP NC,L_4582
    POP HL
    CALL L_4597
    JP C,L_4582
    PUSH HL
    LD HL,[VARTAB]
    LD BC,$0014
    ADD HL,BC
    CALL L_43CD
    JP NC,L_4582
    EX DE,HL
    LD [MEMSIZ],HL
    POP HL
    LD [TOPMEM],HL
    POP HL
    JP L_450B
L_4579:
    CALL L_22D1
    LD A,D
    OR E
    JP Z,L_1418
    RET
L_4582:
    JP L_42DD
L_4585:
    PUSH HL
    LD HL,[TOPMEM]
    EX DE,HL
    LD HL,[MEMSIZ]
    LD A,E
    SUB L
    LD E,A
    LD A,D
    SBC A,H
    LD D,A
    POP HL
    JP L_454D
L_4597:
    LD A,L
    SUB E
    LD E,A
    LD A,H
    SBC A,D
    LD D,A
    RET
ST_NEXT:
    PUSH AF
    .byte $F6
L_45A0:
    .byte $AF
    LD [D_0BBF],A
    POP AF
    LD DE,$0000
L_45A8:
    LD [D_0BBD],HL
    CALL NZ,L_398B
    LD [TEMP],HL
    CALL L_0C50
    JP NZ,NFERR
    LD SP,HL
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    PUSH HL
    LD HL,[D_0BBD]
    CALL L_43CD
    JP NZ,NFERR
    POP HL
    POP DE
    PUSH DE
    LD A,[HL]
    PUSH AF
    INC HL
    PUSH DE
    LD A,[HL]
    INC HL
    OR A
    JP M,L_45F9
    CALL L_28A6
    EX [SP],HL
    PUSH HL
    LD A,[D_0BBF]
    OR A
    JP NZ,L_45E7
    LD HL,$0BC0
    CALL L_28A6
    XOR A
L_45E7:
    CALL NZ,L_257C
    POP HL
    CALL L_28C0
    POP HL
    CALL L_28B7
    PUSH HL
    CALL L_2906
    JP L_462F
L_45F9:
    INC HL
    INC HL
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    EX [SP],HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    PUSH HL
    LD L,C
    LD H,B
    LD A,[D_0BBF]
    OR A
    JP NZ,L_4615
    LD HL,[D_0BC0]
    JP L_4620
L_4615:
    CALL L_2B31
    LD A,[D_0A67]
    CP $04
    JP Z,OVERR
L_4620:
    EX DE,HL
    POP HL
    LD [HL],D
    DEC HL
    LD [HL],E
    POP HL
    PUSH DE
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL
    CALL L_2933
L_462F:
    POP HL
    POP BC
    SUB B
    CALL L_28B7
    JP Z,L_4641
    EX DE,HL
    LD [CURLIN],HL
    LD L,C
    LD H,B
    JP L_129C
L_4641:
    LD SP,HL
    LD [SAVSTK],HL
    LD HL,[TEMP]
    LD A,[HL]
    CP $2C
    JP NZ,NEWSTT
    CALL CHRGTR
    CALL L_45A8
L_4654:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    POP HL
    RET
    .byte $CD, $A5, $48, $7E, $23, $4E, $23, $46, $D1, $C5, $F5, $CD, $AC, $48, $F1, $57
    .byte $5E, $23, $4E, $23, $46, $E1, $7B, $B2, $C8, $7A, $D6, $01, $D8, $AF, $BB, $3C
    .byte $D0, $15, $1D, $0A, $03, $BE, $23, $CA, $72, $46, $3F, $C3, $50, $28
