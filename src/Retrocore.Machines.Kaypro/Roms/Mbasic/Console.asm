;; MBASIC 5.21: EDIT, LINE INPUT AND CONSOLE OUTPUT
;;
;; Part of Mbasic.asm.

ST_EDIT:
    CALL L_141D
    RET NZ
L_3CE7:
    POP HL
L_3CE8:
    EX DE,HL
    LD [DOT],HL
    EX DE,HL
    CALL L_0EF8
    JP NC,L_14CC
    LD H,B
    LD L,C
    INC HL
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    CALL L_20E6
L_3CFF:
    POP HL
L_3D00:
    PUSH HL
    LD A,H
    AND L
    INC A
    LD A,$21
    CALL Z,OUTDO
    CALL NZ,LINPRT
    LD A,$20
    CALL OUTDO
    LD HL,$0962
    PUSH HL
    LD C,$FF
L_3D17:
    INC C
    LD A,[HL]
    INC HL
    OR A
    JP NZ,L_3D17
    POP HL
    LD B,A
    LD D,$00
L_3D22:
    CALL L_41F5
    OR A
    JP Z,L_3D22
    CALL L_1C5B
    SUB $30
    JP C,L_3D41
    CP $0A
    JP NC,L_3D41
    LD E,A
    LD A,D
    RLCA
    RLCA
    ADD A,D
    RLCA
    ADD A,E
    LD D,A
    JP L_3D22
L_3D41:
    PUSH HL
    LD HL,$3D20
    EX [SP],HL
    DEC D
    INC D
    JP NZ,L_3D4C
    INC D
L_3D4C:
    CP $D8
    JP Z,L_3EBA
    CP $4F
    JP Z,L_3EC9
    CP $DD
    JP Z,L_3ED7
    CP $F0
    JP Z,L_3DA8
    CP $31
    JP C,L_3D67
    SUB $20
L_3D67:
    CP $21
    JP Z,L_3EEC
    CP $1C
    JP Z,L_3DE2
    CP $23
    JP Z,L_3DBB
    CP $19
    JP Z,L_3E3E
    CP $14
    JP Z,L_3DEC
    CP $13
    JP Z,L_3E09
    CP $15
    JP Z,L_3EDA
    CP $28
    JP Z,L_3E39
    CP $1B
    JP Z,L_3DB5
    CP $18
    JP Z,L_3E36
    CP $11
    LD A,$07
    JP NZ,OUTDO
    POP BC
    POP DE
    CALL L_4221
    JP L_3CE8
L_3DA8:
    LD A,[HL]
    OR A
    RET Z
    INC B
    CALL L_42A5
    INC HL
    DEC D
    JP NZ,L_3DA8
    RET
L_3DB5:
    PUSH HL
    LD HL,$3E03
    EX [SP],HL
    SCF
L_3DBB:
    PUSH AF
    CALL L_41F5
    LD E,A
    POP AF
    PUSH AF
    CALL C,L_3E03
L_3DC5:
    LD A,[HL]
    OR A
    JP Z,L_3DE0
    CALL L_42A5
    POP AF
    PUSH AF
    CALL C,L_3E81
    JP C,L_3DD7
    INC HL
    INC B
L_3DD7:
    LD A,[HL]
    CP E
    JP NZ,L_3DC5
    DEC D
    JP NZ,L_3DC5
L_3DE0:
    POP AF
    RET
L_3DE2:
    CALL L_20DC
    CALL L_4221
    POP BC
    JP L_3CFF
L_3DEC:
    LD A,[HL]
    OR A
    RET Z
    LD A,$5C
    CALL L_42A5
L_3DF4:
    LD A,[HL]
    OR A
    JP Z,L_3E03
    CALL L_42A5
    CALL L_3E81
    DEC D
    JP NZ,L_3DF4
L_3E03:
    LD A,$5C
    CALL OUTDO
    RET
L_3E09:
    LD A,[HL]
    OR A
    RET Z
L_3E0C:
    CALL L_41F5
    CP $20
    JP NC,L_3E2B
    CP $0A
    JP Z,L_3E2B
    CP $07
    JP Z,L_3E2B
    CP $09
    JP Z,L_3E2B
    LD A,$07
    CALL OUTDO
    JP L_3E0C
L_3E2B:
    LD [HL],A
    CALL L_42A5
    INC HL
    INC B
    DEC D
    JP NZ,L_3E09
    RET
L_3E36:
    LD [HL],$00
    LD C,B
L_3E39:
    LD D,$FF
    CALL L_3DA8
L_3E3E:
    CALL L_41F5
    CP $7F
    JP Z,L_3E71
    CP $08
    JP Z,L_3E73
    CP $0D
    JP Z,L_3ED7
    CP $1B
    RET Z
    CP $08
    JP Z,L_3E73
    CP $0A
    JP Z,L_3E91
    CP $07
    JP Z,L_3E91
    CP $09
    JP Z,L_3E91
    CP $20
    JP C,L_3E3E
    CP $5F
    JP NZ,L_3E91
L_3E71:
    LD A,$5F
L_3E73:
    DEC B
    INC B
    JP Z,L_3E99
    CALL L_42A5
    DEC HL
    DEC B
    LD DE,$3E3E
    PUSH DE
L_3E81:
    PUSH HL
    DEC C
L_3E83:
    LD A,[HL]
    OR A
    SCF
    JP Z,L_2757
    INC HL
    LD A,[HL]
    DEC HL
    LD [HL],A
    INC HL
    JP L_3E83
L_3E91:
    PUSH AF
    LD A,C
    CP $FF
    JP C,L_3EA1
    POP AF
L_3E99:
    LD A,$07
    CALL OUTDO
L_3E9E:
    JP L_3E3E
L_3EA1:
    SUB B
    INC C
    INC B
    PUSH BC
    EX DE,HL
    LD L,A
    LD H,$00
    ADD HL,DE
    LD B,H
    LD C,L
    INC HL
    CALL L_42B9
    POP BC
    POP AF
    LD [HL],A
    CALL L_42A5
    INC HL
    JP L_3E9E
L_3EBA:
    LD A,B
    OR A
    RET Z
    DEC HL
    LD A,$08
    CALL L_42A5
    DEC B
    DEC D
    JP NZ,L_3EC9
    RET
L_3EC9:
    LD A,B
    OR A
    RET Z
    DEC B
    DEC HL
    LD A,[HL]
    CALL L_42A5
    DEC D
    JP NZ,L_3EC9
    RET
L_3ED7:
    CALL L_20DC
L_3EDA:
    CALL L_4221
    POP BC
    POP DE
    LD A,D
    AND E
    INC A
L_3EE2:
    LD HL,$0961
    RET Z
    SCF
    PUSH AF
    INC HL
    JP L_0E14
L_3EEC:
    POP BC
    POP DE
    LD A,D
    AND E
    INC A
    JP Z,L_421C
    JP READY
L_3EF7:
    CALL L_1A03
    CALL L_2A3B
    CALL L_43D3
    DEC SP
    EX DE,HL
    LD HL,[D_0C04]
    JP L_3F11
L_3F08:
    LD A,[FLGINP]
    OR A
    JP Z,L_3F1B
    POP DE
    EX DE,HL
L_3F11:
    PUSH HL
    XOR A
    LD [FLGINP],A
    INC A
    PUSH AF
    PUSH DE
    LD B,[HL]
    OR B
L_3F1B:
    JP Z,L_1418
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    JP L_3F45
L_3F26:
    LD E,B
    PUSH HL
    LD C,$02
L_3F2A:
    LD A,[HL]
    INC HL
    CP $5C
    JP Z,L_4091
    CP $20
    JP NZ,L_3F3B
    INC C
    DEC B
    JP NZ,L_3F2A
L_3F3B:
    POP HL
    LD B,E
    LD A,$5C
L_3F3F:
    CALL L_40CC
    CALL OUTDO
L_3F45:
    XOR A
    LD E,A
    LD D,A
L_3F48:
    CALL L_40CC
    LD D,A
    LD A,[HL]
    INC HL
    CP $21
    JP Z,L_408E
    CP $23
    JP Z,L_3FA1
    CP $26
    JP Z,L_4089
    DEC B
    JP Z,L_4067
    CP $2B
    LD A,$08
    JP Z,L_3F48
    DEC HL
    LD A,[HL]
    INC HL
    CP $2E
    JP Z,L_3FC0
    CP $5F
    JP Z,L_407D
    CP $5C
    JP Z,L_3F26
    CP [HL]
    JP NZ,L_3F3F
    CP $24
    JP Z,L_3F9A
    CP $2A
    JP NZ,L_3F3F
    LD A,B
    INC HL
    CP $02
    JP C,L_3F92
    LD A,[HL]
    CP $24
L_3F92:
    LD A,$20
    JP NZ,L_3F9E
    DEC B
    INC E
    .byte $FE
L_3F9A:
    .byte $AF
    ADD A,$10
    INC HL
L_3F9E:
    INC E
    ADD A,D
    LD D,A
L_3FA1:
    INC E
    LD C,$00
    DEC B
    JP Z,L_3FF6
    LD A,[HL]
    INC HL
    CP $2E
    JP Z,L_3FCB
    CP $23
    JP Z,L_3FA1
    CP $2C
    JP NZ,L_3FD7
    LD A,D
    OR $40
    LD D,A
    JP L_3FA1
L_3FC0:
    LD A,[HL]
    CP $23
    LD A,$2E
    JP NZ,L_3F3F
    LD C,$01
    INC HL
L_3FCB:
    INC C
    DEC B
    JP Z,L_3FF6
    LD A,[HL]
    INC HL
    CP $23
    JP Z,L_3FCB
L_3FD7:
    PUSH DE
    LD DE,$3FF4
    PUSH DE
    LD D,H
    LD E,L
    CP $5E
    RET NZ
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    LD A,B
    SUB $04
    RET C
    POP DE
    POP DE
    LD B,A
    INC D
    INC HL
    JP Z,L_D1EB
L_3FF6:
    LD A,D
    DEC HL
    INC E
    AND $08
    JP NZ,L_4016
    DEC E
    LD A,B
    OR A
    JP Z,L_4016
    LD A,[HL]
    SUB $2D
    JP Z,L_4011
    CP $FE
    JP NZ,L_4016
    LD A,$08
L_4011:
    ADD A,$04
    ADD A,D
    LD D,A
    DEC B
L_4016:
    POP HL
    POP AF
    JP Z,L_4072
    PUSH BC
    PUSH DE
    CALL L_1A02
    POP DE
    POP BC
    PUSH BC
    PUSH HL
    LD B,E
    LD A,B
    ADD A,C
    CP $19
    JP NC,L_1418
    LD A,D
    OR $80
    CALL L_312A
    CALL L_4723
L_4035:
    POP HL
    DEC HL
    CALL CHRGTR
    SCF
    JP Z,L_404E
    LD [FLGINP],A
    CP $3B
    JP Z,L_404B
    CP $2C
    JP NZ,SNERR
L_404B:
    CALL CHRGTR
L_404E:
    POP BC
    EX DE,HL
    POP HL
    PUSH HL
    PUSH AF
    PUSH DE
    LD A,[HL]
    SUB B
    INC HL
    LD D,$00
    LD E,A
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    ADD HL,DE
L_405F:
    LD A,B
    OR A
    JP NZ,L_3F45
    JP L_406D
L_4067:
    CALL L_40CC
    CALL OUTDO
L_406D:
    POP HL
    POP AF
    JP NZ,L_3F08
L_4072:
    CALL C,L_4221
    EX [SP],HL
    CALL L_48AB
    POP HL
    JP L_17E9
L_407D:
    CALL L_40CC
    DEC B
    LD A,[HL]
    INC HL
    CALL OUTDO
    JP L_405F
L_4089:
    LD C,$00
    JP L_4092
L_408E:
    LD C,$01
    .byte $3E
L_4091:
    POP AF
L_4092:
    DEC B
    CALL L_40CC
    POP HL
    POP AF
    JP Z,L_4072
    PUSH BC
    CALL L_1A02
    CALL L_2A3B
    POP BC
    PUSH BC
    PUSH HL
    LD HL,[D_0C04]
    LD B,C
    LD C,$00
    LD A,B
    PUSH AF
    LD A,B
    OR A
    CALL NZ,L_494F
    CALL L_4726
    LD HL,[D_0C04]
    POP AF
    OR A
    JP Z,L_4035
    SUB [HL]
    LD B,A
    LD A,$20
    INC B
L_40C2:
    DEC B
    JP Z,L_4035
    CALL OUTDO
    JP L_40C2
L_40CC:
    PUSH AF
    LD A,D
    OR A
    LD A,$2B
    CALL NZ,OUTDO
    POP AF
    RET
OUTDO:
    PUSH AF
    PUSH HL
    CALL L_4654
    JP NZ,L_5666
    POP HL
    LD A,[D_078D]
    OR A
    JP Z,L_415C
    POP AF
    PUSH AF
    CP $08
    JP NZ,L_40FC
    LD A,[D_078C]
    SUB $01
    JP C,L_40F8
    LD [D_078C],A
L_40F8:
    POP AF
    JP L_4137
L_40FC:
    CP $09
    JP NZ,L_4110
L_4101:
    LD A,$20
    CALL OUTDO
    LD A,[D_078C]
    AND $07
    JP NZ,L_4101
    POP AF
    RET
L_4110:
    POP AF
    PUSH AF
    SUB $0D
    JP Z,L_4133
    JP C,L_4136
    LD A,[D_078F]
    INC A
    LD A,[D_078C]
    JP Z,L_412D
    PUSH HL
    LD HL,$078F
    CP [HL]
    POP HL
    CALL Z,L_414D
L_412D:
    CP $FF
    JP Z,L_4136
    INC A
L_4133:
    LD [D_078C],A
L_4136:
    POP AF
L_4137:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
    .byte $CD
D_413D:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    POP AF
    RET
L_4144:
    XOR A
    LD [D_078D],A
    LD A,[D_078C]
    OR A
    RET Z
L_414D:
    LD A,$0D
    CALL L_4137
    LD A,$0A
    CALL L_4137
    XOR A
    LD [D_078C],A
    RET
L_415C:
    LD A,[D_0793]
    OR A
    JP NZ,L_4758
    POP AF
    PUSH BC
    PUSH AF
    CP $08
    JP NZ,L_417B
    LD A,[D_0A65]
    OR A
    JP Z,L_418D
    DEC A
    LD [D_0A65],A
    LD A,$08
    JP L_41AE
L_417B:
    CP $09
    JP NZ,L_4190
L_4180:
    LD A,$20
    CALL OUTDO
    LD A,[D_0A65]
    AND $07
    JP NZ,L_4180
L_418D:
    POP AF
    POP BC
    RET
L_4190:
    CP $20
    JP C,L_41AE
    LD A,[D_0790]
    LD B,A
    LD A,[D_0A65]
    INC B
    JP Z,L_41A5
    DEC B
    CP B
    CALL Z,L_4221
L_41A5:
    CP $FF
    JP Z,L_41AE
    INC A
    LD [D_0A65],A
L_41AE:
    POP AF
    POP BC
    PUSH AF
    POP AF
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
    .byte $CD
D_41B8:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    POP AF
    RET
L_41BF:
    CALL L_4654
    JP Z,L_41F5
    CALL L_57C2
    RET NC
    PUSH BC
    PUSH DE
    PUSH HL
    CALL L_534D
    POP HL
    POP DE
    POP BC
    LD A,[D_0BF3]
    OR A
    JP NZ,L_5030
    LD A,[D_079E]
    OR A
    JP Z,L_41E7
    LD HL,$12A0
    PUSH HL
    JP L_4337
L_41E7:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,$0C45
    CALL L_4723
    POP DE
    POP BC
    XOR A
    POP HL
    RET
L_41F5:
    PUSH BC
    PUSH DE
    PUSH HL
    .byte $CD
D_41F9:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    AND $7F
    CP $0F
    RET NZ
    LD A,[D_0793]
    OR A
    CALL Z,L_4441
    CPL
    LD [D_0793],A
    OR A
    JP Z,L_4441
    XOR A
    RET
L_4214:
    LD A,[D_0A65]
    OR A
    RET Z
    JP L_4221
L_421C:
    LD [HL],$00
    LD HL,$0961
L_4221:
    LD A,$0D
    CALL OUTDO
    LD A,$0A
    CALL OUTDO
L_422B:
    CALL L_4654
    JP Z,L_4233
    XOR A
    RET
L_4233:
    LD A,[D_078D]
    OR A
    JP Z,L_423F
    XOR A
    LD [D_078C],A
    RET
L_423F:
    XOR A
    LD [D_0A65],A
    LD A,[D_0788]
L_4246:
    DEC A
    RET Z
    PUSH AF
    XOR A
    CALL OUTDO
    POP AF
    JP L_4246
L_4251:
    PUSH BC
    PUSH DE
    PUSH HL
    .byte $CD
D_4255:
    .byte $00, $00
    POP HL
    POP DE
    POP BC
    OR A
    RET Z
L_425C:
    CALL L_41F5
    CP $13
    CALL Z,L_41F5
    LD [D_0789],A
    CP $03
    CALL Z,L_4443
    JP ST_STOP
L_426F:
    CALL CHRGTR
    PUSH HL
    CALL L_4299
    JP NZ,L_4283
    .byte $CD
D_427A:
    .byte $00, $00
    OR A
    JP Z,L_428C
    CALL L_41F5
L_4283:
    PUSH AF
    CALL L_46B7
    POP AF
    LD E,A
    CALL L_48F8
L_428C:
    LD HL,$0C44
    LD [D_0C04],HL
    LD A,$03
    LD [D_0A67],A
    POP HL
    RET
L_4299:
    LD A,[D_0789]
    OR A
    RET Z
    PUSH AF
    XOR A
    LD [D_0789],A
    POP AF
    RET
L_42A5:
    CALL OUTDO
    CP $0A
    RET NZ
    LD A,$0D
    CALL OUTDO
    CALL L_422B
    LD A,$0A
    RET
L_42B6:
    CALL L_42EB
L_42B9:
    PUSH BC
    EX [SP],HL
    POP BC
L_42BC:
    CALL L_43CD
    LD A,[HL]
    LD [BC],A
    RET Z
    DEC BC
    DEC HL
    JP L_42BC
L_42C7:
    PUSH HL
    LD HL,[MEMSIZ]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    LD A,$C6
    SUB L
    LD L,A
    LD A,$FF
    SBC A,H
    LD H,A
    JP C,L_42DD
    ADD HL,SP
    POP HL
    RET C
L_42DD:
    LD HL,[TOPMEM]
    DEC HL
    DEC HL
    LD [SAVSTK],HL
L_42E5:
    LD DE,$0007
    JP ERROR
L_42EB:
    CALL L_42FF
    RET NC
    PUSH BC
    PUSH DE
    PUSH HL
    CALL L_4767
    POP HL
    POP DE
    POP BC
    CALL L_42FF
    RET NC
    JP L_42E5
L_42FF:
    PUSH DE
    EX DE,HL
    LD HL,[FRETOP]
    CALL L_43CD
    EX DE,HL
    POP DE
    RET
L_430A:
    LD A,[D_07C4]
    LD B,A
    LD HL,$07A4
    XOR A
    INC B
L_4313:
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    LD [DE],A
    DEC B
    JP NZ,L_4313
    CALL L_540D
    XOR A
