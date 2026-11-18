;; MBASIC 5.21: STRINGS
;;
;; Part of Mbasic.asm.

FN_OCT:
    CALL L_366F
    JP L_4699
FN_HEX:
    CALL L_3672
    JP L_4699
FN_STR:
    CALL L_3129
L_4699:
    CALL L_46C7
    CALL L_48A8
    LD BC,$48FC
    PUSH BC
L_46A3:
    LD A,[HL]
    INC HL
    PUSH HL
    CALL L_473C
    POP HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    CALL L_46BC
    PUSH HL
    LD L,A
    CALL L_489B
    POP DE
    RET
L_46B7:
    LD A,$01
L_46B9:
    CALL L_473C
L_46BC:
    LD HL,$0A98
    PUSH HL
    LD [HL],A
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    RET
L_46C7:
    DEC HL
L_46C8:
    LD B,$22
L_46CA:
    LD D,B
L_46CB:
    PUSH HL
    LD C,$FF
L_46CE:
    INC HL
    LD A,[HL]
    INC C
    OR A
    JP Z,L_46DD
    CP D
    JP Z,L_46DD
    CP B
    JP NZ,L_46CE
L_46DD:
    CP $22
    CALL Z,CHRGTR
    PUSH HL
    LD A,B
    CP $2C
    JP NZ,L_46F5
    INC C
L_46EA:
    DEC C
    JP Z,L_46F5
    DEC HL
    LD A,[HL]
    CP $20
    JP Z,L_46EA
L_46F5:
    POP HL
    EX [SP],HL
    INC HL
    EX DE,HL
    LD A,C
    CALL L_46BC
L_46FD:
    LD DE,$0A98
    .byte $3E
L_4701:
    .byte $D5
    LD HL,[TEMPPT]
    LD [D_0C04],HL
    LD A,$03
    LD [D_0A67],A
    CALL L_28C9
    LD DE,$0A9B
    CALL L_43CD
    LD [TEMPPT],HL
    POP HL
    LD A,[HL]
    RET NZ
    LD DE,$0010
    JP ERROR
    .byte $23
L_4723:
    CALL L_46C7
L_4726:
    CALL L_48A8
    CALL L_28B9
    INC D
L_472D:
    DEC D
    RET Z
    LD A,[BC]
    CALL OUTDO
    CP $0D
    CALL Z,L_422B
    INC BC
    JP L_472D
L_473C:
    OR A
    LD C,$F1
    PUSH AF
    LD HL,[STREND]
    EX DE,HL
    LD HL,[FRETOP]
    CPL
    LD C,A
    LD B,$FF
    ADD HL,BC
    INC HL
    CALL L_43CD
    JP C,L_475A
    LD [FRETOP],HL
    INC HL
    EX DE,HL
L_4758:
    POP AF
    RET
L_475A:
    POP AF
    LD DE,$000E
    JP Z,ERROR
    CP A
    PUSH AF
    LD BC,$473E
    PUSH BC
L_4767:
    LD HL,[MEMSIZ]
L_476A:
    LD [FRETOP],HL
    LD HL,$0000
    PUSH HL
    LD HL,[STREND]
    PUSH HL
    LD HL,$0A7A
    EX DE,HL
    LD HL,[TEMPPT]
    EX DE,HL
    CALL L_43CD
    LD BC,$4778
    JP NZ,L_4812
    LD HL,$0B4C
    LD [D_0BB8],HL
    LD HL,[ARYTAB]
    LD [D_0BB5],HL
    LD HL,[VARTAB]
L_4795:
    EX DE,HL
    LD HL,[D_0BB5]
    EX DE,HL
    CALL L_43CD
    JP Z,L_47B9
    LD A,[HL]
    INC HL
    INC HL
    INC HL
    PUSH AF
    CALL L_3C9A
    POP AF
    CP $03
    JP NZ,L_47B2
    CALL L_4813
    XOR A
L_47B2:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP L_4795
L_47B9:
    LD HL,[D_0BB8]
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    LD HL,[ARYTAB]
    JP Z,L_47DB
    EX DE,HL
    LD [D_0BB8],HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    EX DE,HL
    ADD HL,DE
    LD [D_0BB5],HL
    EX DE,HL
    JP L_4795
L_47DA:
    POP BC
L_47DB:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL L_43CD
    JP Z,L_4837
    LD A,[HL]
    INC HL
    PUSH AF
    INC HL
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
    JP NZ,L_47DA
    LD [TEMP8],HL
    POP HL
    LD C,[HL]
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL
    EX DE,HL
    LD HL,[TEMP8]
    EX DE,HL
    CALL L_43CD
    JP Z,L_47DB
    LD BC,$4804
L_4812:
    PUSH BC
L_4813:
    XOR A
    OR [HL]
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    RET Z
    LD B,H
    LD C,L
    LD HL,[FRETOP]
    CALL L_43CD
    LD H,B
    LD L,C
    RET C
    POP HL
    EX [SP],HL
    CALL L_43CD
    EX [SP],HL
    PUSH HL
    LD H,B
    LD L,C
    RET NC
    POP BC
    POP AF
    POP AF
    PUSH HL
    PUSH DE
    PUSH BC
    RET
L_4837:
    POP DE
    POP HL
    LD A,H
    OR L
    RET Z
    DEC HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    PUSH HL
    DEC HL
    LD L,[HL]
    LD H,$00
    ADD HL,BC
    LD D,B
    LD E,C
    DEC HL
    LD B,H
    LD C,L
    LD HL,[FRETOP]
    CALL L_42B9
    POP HL
    LD [HL],C
    INC HL
    LD [HL],B
    LD H,B
    LD L,C
    DEC HL
    JP L_476A
L_485B:
    PUSH BC
    PUSH HL
    LD HL,[D_0C04]
    EX [SP],HL
    CALL L_1B93
    EX [SP],HL
    CALL L_2A3B
    LD A,[HL]
    PUSH HL
    LD HL,[D_0C04]
    PUSH HL
    ADD A,[HL]
    LD DE,$000F
    JP C,ERROR
    CALL L_46B9
    POP DE
    CALL L_48AC
    EX [SP],HL
    CALL L_48AB
    PUSH HL
    LD HL,[D_0A99]
    EX DE,HL
    CALL L_4893
    CALL L_4893
    LD HL,$1A12
    EX [SP],HL
    PUSH HL
    JP L_46FD
L_4893:
    POP HL
    EX [SP],HL
    LD A,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD L,A
L_489B:
    INC L
L_489C:
    DEC L
    RET Z
    LD A,[BC]
    LD [DE],A
    INC BC
    INC DE
    JP L_489C
L_48A5:
    CALL L_2A3B
L_48A8:
    LD HL,[D_0C04]
L_48AB:
    EX DE,HL
L_48AC:
    CALL L_48C6
    EX DE,HL
    RET NZ
    PUSH DE
    LD D,B
    LD E,C
    DEC DE
    LD C,[HL]
    LD HL,[FRETOP]
    CALL L_43CD
    JP NZ,L_48C4
    LD B,A
    ADD HL,BC
    LD [FRETOP],HL
L_48C4:
    POP HL
    RET
L_48C6:
    LD HL,[TEMPPT]
    DEC HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    DEC HL
    CALL L_43CD
    RET NZ
    LD [TEMPPT],HL
L_48D5:
    RET
FN_LEN:
    LD BC,$1DD5
    PUSH BC
L_48DA:
    CALL L_48A5
    XOR A
    LD D,A
    LD A,[HL]
L_48E0:
    OR A
    RET
FN_ASC:
    LD BC,$1DD5
    PUSH BC
L_48E6:
    CALL L_48DA
    JP Z,L_1418
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,[DE]
    RET
FN_CHR:
    CALL L_46B7
    CALL L_2078
L_48F8:
    LD HL,[D_0A99]
    LD [HL],E
L_48FC:
    POP BC
    JP L_46FD
L_4900:
    CALL CHRGTR
    CALL L_43D3
    JR Z,L_48D5
    LD [HL],L
    JR NZ,L_48E0
    CALL L_43D3
    INC L
    CALL L_1A02
    CALL L_43D3
    ADD HL,HL
    EX [SP],HL
    PUSH HL
    CALL L_1D64
    JP Z,L_4924
    CALL L_2078
    JP L_4927
L_4924:
    CALL L_48E6
L_4927:
    POP DE
    CALL L_4930
FN_SPACE:
    CALL L_2078
    LD A,$20
L_4930:
    PUSH AF
    LD A,E
    CALL L_46B9
    LD B,A
    POP AF
    INC B
    DEC B
    JP Z,L_48FC
    LD HL,[D_0A99]
L_493F:
    LD [HL],A
    INC HL
    DEC B
    JP NZ,L_493F
    JP L_48FC
FN_LEFT:
    CALL L_49C1
    XOR A
L_494C:
    EX [SP],HL
    LD C,A
    .byte $3E
L_494F:
    .byte $E5
    PUSH HL
    LD A,[HL]
    CP B
    JP C,L_4958
    LD A,B
    .byte $11
L_4958:
    .byte $0E, $00
    PUSH BC
    CALL L_473C
    POP BC
    POP HL
    PUSH HL
    INC HL
    LD B,[HL]
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC
    LD B,H
    LD C,L
    CALL L_46BC
    LD L,A
    CALL L_489B
    POP DE
    CALL L_48AC
    JP L_46FD
FN_RIGHT:
    CALL L_49C1
    POP DE
    PUSH DE
    LD A,[DE]
    SUB B
    JP L_494C
FN_MID:
    EX DE,HL
    LD A,[HL]
    CALL L_49C6
    INC B
    DEC B
    JP Z,L_1418
    PUSH BC
    CALL L_4AE3
    POP AF
    EX [SP],HL
    LD BC,$4950
    PUSH BC
    DEC A
    CP [HL]
    LD B,$00
    RET NC
    LD C,A
    LD A,[HL]
    SUB C
    CP E
    LD B,A
    RET C
    LD B,E
    RET
FN_VAL:
    CALL L_48DA
    JP Z,L_1DD5
    LD E,A
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    PUSH HL
    ADD HL,DE
    LD B,[HL]
    LD [HL],D
    EX [SP],HL
    PUSH BC
    DEC HL
    CALL CHRGTR
    CALL L_2ECA
    POP BC
    POP HL
    LD [HL],B
    RET
L_49C1:
    EX DE,HL
    CALL L_43D3
    ADD HL,HL
L_49C6:
    POP BC
    POP DE
    PUSH BC
    LD B,E
    RET
L_49CB:
    CALL CHRGTR
    CALL L_19FE
    CALL L_1D64
    LD A,$01
    PUSH AF
    JP Z,L_49ED
    POP AF
    CALL L_2078
    OR A
    JP Z,L_1418
    PUSH AF
    CALL L_43D3
    INC L
    CALL L_1A02
    CALL L_2A3B
L_49ED:
    CALL L_43D3
    INC L
    PUSH HL
    LD HL,[D_0C04]
    EX [SP],HL
    CALL L_1A02
    CALL L_43D3
    ADD HL,HL
    PUSH HL
    CALL L_48A5
    EX DE,HL
    POP BC
    POP HL
    POP AF
    PUSH BC
    LD BC,$2757
    PUSH BC
    LD BC,$1DD5
    PUSH BC
    PUSH AF
    PUSH DE
    CALL L_48AB
    POP DE
    POP AF
    LD B,A
    DEC A
    LD C,A
    CP [HL]
    LD A,$00
    RET NC
    LD A,[DE]
    OR A
    LD A,B
    RET Z
    LD A,[HL]
    INC HL
    LD B,[HL]
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC
    SUB C
    LD B,A
    PUSH BC
    PUSH DE
    EX [SP],HL
    LD C,[HL]
    INC HL
    LD E,[HL]
    INC HL
L_4A32:
    LD D,[HL]
    POP HL
L_4A34:
    PUSH HL
    PUSH DE
    PUSH BC
L_4A37:
    LD A,[DE]
    CP [HL]
    JP NZ,L_4A55
    INC DE
    DEC C
    JP Z,L_4A4C
    INC HL
    DEC B
    JP NZ,L_4A37
    POP DE
    POP DE
    POP BC
L_4A49:
    POP DE
    XOR A
    RET
L_4A4C:
    POP HL
    POP DE
    POP DE
    POP BC
    LD A,B
    SUB H
    ADD A,C
    INC A
    RET
L_4A55:
    POP BC
    POP DE
    POP HL
    INC HL
    DEC B
    JP NZ,L_4A34
    JP L_4A49
L_4A60:
    CALL L_43D3
    JR Z,L_4A32
    ADC A,E
    ADD HL,SP
    CALL L_2A3B
    PUSH HL
    PUSH DE
    EX DE,HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD HL,[STREND]
    CALL L_43CD
    JP C,L_4A8D
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_4A8D
    POP HL
    PUSH HL
    CALL L_46A3
    POP HL
    PUSH HL
    CALL L_28C9
L_4A8D:
    POP HL
    EX [SP],HL
    CALL L_43D3
    INC L
    CALL L_2075
    OR A
    JP Z,L_1418
    PUSH AF
    LD A,[HL]
    CALL L_4AE3
    PUSH DE
    CALL L_19F7
    PUSH HL
    CALL L_48A5
    EX DE,HL
    POP HL
    POP BC
    POP AF
    LD B,A
    EX [SP],HL
    PUSH HL
    LD HL,$2757
    EX [SP],HL
    LD A,C
    OR A
    RET Z
    LD A,[HL]
    SUB B
    JP C,L_1418
    INC A
    CP C
    JP C,L_4AC0
    LD A,C
L_4AC0:
    LD C,B
    DEC C
    LD B,$00
    PUSH DE
    INC HL
    LD E,[HL]
    INC HL
    LD H,[HL]
    LD L,E
    ADD HL,BC
    LD B,A
    POP DE
    EX DE,HL
    LD C,[HL]
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL
    LD A,C
    OR A
    RET Z
L_4AD8:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    RET Z
    DEC B
    JP NZ,L_4AD8
    RET
L_4AE3:
    LD E,$FF
    CP $29
    JP Z,L_4AF1
    CALL L_43D3
    INC L
    CALL L_2075
L_4AF1:
    CALL L_43D3
    ADD HL,HL
    RET
FN_FRE:
    CALL L_1D64
    JP NZ,L_4B02
    CALL L_48A8
    CALL L_4767
L_4B02:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    LD HL,[FRETOP]
    JP L_1DC2
L_4B0D:
    LD A,$3F
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    JP L_4B28
L_4B1A:
    CALL L_41BF
    CP $01
    JP NZ,L_4B7A
    LD [HL],$00
    JP L_4B38
L_4B27:
    LD [HL],B
L_4B28:
    XOR A
    LD [D_0789],A
    XOR A
    LD [D_0BE6],A
L_4B30:
    CALL L_41BF
    CP $01
    JP NZ,L_4B6F
L_4B38:
    CALL L_4221
    LD HL,$FFFF
    JP L_3D00
L_4B41:
    LD A,[D_0792]
    OR A
    LD A,$5C
    LD [D_0792],A
    JP NZ,L_4B55
    DEC B
    JP Z,L_4B27
    CALL OUTDO
    INC B
L_4B55:
    DEC B
    DEC HL
    JP Z,L_4B69
    LD A,[HL]
    CALL OUTDO
    JP L_4B1A
    .byte $05
L_4B62:
    DEC HL
    CALL OUTDO
    JP NZ,L_4B1A
L_4B69:
    CALL OUTDO
    CALL L_4221
L_4B6F:
    LD HL,$0962
    LD B,$01
    PUSH AF
    XOR A
    LD [D_0792],A
    POP AF
L_4B7A:
    LD C,A
    CP $7F
    JP Z,L_4B41
    LD A,[D_0792]
    OR A
    JP Z,L_4B90
    LD A,$5C
    CALL OUTDO
    XOR A
    LD [D_0792],A
L_4B90:
    LD A,C
    CP $07
    JP Z,L_4BFA
    CP $03
    CALL Z,L_4443
    SCF
    RET Z
    CP $0D
    JP Z,L_4C3B
    CP $09
    JP Z,L_4BFA
    CP $0A
    JP NZ,L_4BB4
    DEC B
    JP Z,L_4B28
    INC B
    JP L_4BFA
L_4BB4:
    CP $15
    CALL Z,L_4443
    JP Z,L_4B28
    CP $08
    JP NZ,L_4BD2
    DEC B
    JP Z,L_4B30
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    LD A,$08
    JP L_4B62
L_4BD2:
    CP $18
    JP NZ,L_4BDC
    LD A,$23
    JP L_4B69
L_4BDC:
    CP $12
    JP NZ,L_4BF5
    PUSH BC
    PUSH DE
    PUSH HL
    LD [HL],$00
    CALL L_4221
    LD HL,$0962
    CALL L_20DC
    POP HL
    POP DE
    POP BC
    JP L_4B1A
L_4BF5:
    CP $20
    JP C,L_4B1A
L_4BFA:
    LD A,B
    OR A
    JP NZ,L_4C18
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    POP HL
    LD A,$07
    JP Z,L_4C1C
    LD HL,$0962
    CALL L_1428
    EX DE,HL
    LD [CURLIN],HL
    JP L_115F
L_4C18:
    LD A,C
    LD [HL],C
    INC HL
    INC B
L_4C1C:
    CALL OUTDO
    SUB $0A
    JP NZ,L_4B1A
    LD [D_0A65],A
    LD A,$0D
    CALL OUTDO
L_4C2C:
    CALL L_41BF
    OR A
    JP Z,L_4C2C
    CP $0D
    JP Z,L_4B1A
    JP L_4B7A
L_4C3B:
    LD A,[D_0BE6]
    OR A
    JP Z,L_421C
    XOR A
    LD [HL],A
    LD HL,$0961
    RET
L_4C48:
    PUSH AF
    LD A,$00
    LD [D_0BE6],A
    POP AF
    CP $3B
    RET NZ
    LD [D_0BE6],A
    JP CHRGTR
