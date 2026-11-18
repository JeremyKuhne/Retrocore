;; MBASIC 5.21: DISK FILES, PART 2
;;
;; Part of Mbasic.asm.

FN_LOC:
    CALL L_5136
    JP Z,DERBFN
    CP $03
    LD HL,$0026
    JP NZ,L_5651
    LD HL,$00AE
L_5651:
    ADD HL,BC
    LD A,[HL]
    DEC HL
    LD L,[HL]
    JP L_1DD7
FN_LOF:
    CALL L_5136
    JP Z,DERBFN
    LD HL,$0010
    ADD HL,BC
    LD A,[HL]
    JP L_1DD5
L_5666:
    POP HL
    POP AF
L_5668:
    PUSH HL
    PUSH AF
    LD HL,[D_0794]
    LD A,[HL]
    CP $01
    JP Z,L_4500
    CP $03
    JP Z,L_5C65
    POP AF
L_5679:
    PUSH DE
    PUSH BC
    LD B,H
    LD C,L
    PUSH AF
    LD DE,$0027
    ADD HL,DE
    LD A,[HL]
    CP $80
    PUSH HL
    CALL Z,L_55C9
    POP HL
    INC [HL]
    LD C,[HL]
    LD B,$00
    INC HL
    POP AF
    PUSH AF
    LD D,[HL]
    CP $0D
    LD [HL],B
    JP Z,L_569D
    ADD A,$E0
    LD A,D
    ADC A,B
    LD [HL],A
L_569D:
    ADD HL,BC
    POP AF
    POP BC
    POP DE
    LD [HL],A
    POP HL
    RET
L_56A4:
    DEC DE
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],$80
    INC HL
    LD [HL],$80
    POP HL
    EX [SP],HL
    LD B,H
    LD C,L
    PUSH HL
    LD A,[D_081F]
    OR A
    JP Z,L_56C8
    LD HL,$0022
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],$00
    JP L_570D
L_56C8:
    LD HL,$000D
    ADD HL,BC
    LD A,E
    RLA
    LD A,D
    RLA
    LD D,[HL]
    CP D
    JP Z,L_5705
    PUSH DE
    PUSH AF
    PUSH HL
    PUSH BC
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    POP DE
    PUSH DE
    INC DE
    LD C,$10
    CALL L_0005
    POP DE
    POP HL
    POP AF
    LD [HL],A
    PUSH DE
    INC DE
    LD C,$0F
    PUSH DE
    CALL L_0005
    POP DE
    INC A
    JP NZ,L_5703
    LD C,$16
    CALL L_0005
    INC A
    JP Z,DERTMF
L_5703:
    POP BC
    POP DE
L_5705:
    LD HL,$0021
    ADD HL,BC
    LD A,E
    AND $7F
    LD [HL],A
L_570D:
    POP HL
    LD A,[D_07A0]
    OR A
    JP NZ,L_571A
    CALL L_577D
    POP HL
    RET
L_571A:
    LD HL,$0021
    ADD HL,BC
    LD A,[HL]
    CP $7F
    PUSH AF
    LD DE,$0080
    LD HL,$0029
    ADD HL,BC
    PUSH DE
    PUSH HL
    CALL Z,L_573B
    CALL L_55C9
    POP DE
    POP HL
    POP AF
    CALL Z,L_573B
    POP HL
    JP L_17E9
L_573B:
    PUSH BC
    LD B,$80
L_573E:
    LD A,[HL]
    INC HL
    LD [DE],A
    INC DE
    DEC B
    JP NZ,L_573E
    POP BC
    RET
L_5748:
    PUSH BC
    PUSH HL
L_574A:
    LD HL,[D_0794]
    LD A,[HL]
    CP $03
    JP Z,L_5C96
    LD BC,$0028
    ADD HL,BC
    LD A,[HL]
    OR A
    JP Z,L_5768
    DEC HL
    LD A,[HL]
    INC HL
    DEC [HL]
    SUB [HL]
    LD C,A
    ADD HL,BC
    LD A,[HL]
    OR A
    POP HL
    POP BC
    RET
L_5768:
    DEC HL
    LD A,[HL]
    OR A
    JP Z,L_5774
    CALL L_577A
    JP NZ,L_574A
L_5774:
    SCF
    POP HL
    POP BC
    LD A,$1A
    RET
L_577A:
    LD HL,[D_0794]
L_577D:
    PUSH DE
    LD D,H
    LD E,L
    INC DE
    LD BC,$0025
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC BC
    DEC HL
    LD [HL],C
    INC HL
    LD [HL],B
    INC HL
    INC HL
    PUSH HL
    LD C,$80
L_5792:
    INC HL
    LD [HL],$00
    DEC C
    JP NZ,L_5792
    CALL L_57B1
    LD A,[D_0820]
    CALL L_5A9E
    OR A
    LD A,$00
    JP NZ,L_57AA
    LD A,$80
L_57AA:
    POP HL
    LD [HL],A
    DEC HL
    LD [HL],A
    OR A
    POP DE
    RET
L_57B1:
    PUSH BC
    PUSH DE
    PUSH HL
    LD HL,$0028
    ADD HL,DE
    EX DE,HL
    LD C,$1A
    CALL L_0005
    POP HL
    POP DE
    POP BC
    RET
L_57C2:
    CALL L_5748
    RET C
    CP $1A
    SCF
    CCF
    RET NZ
    PUSH BC
    PUSH HL
    LD HL,[D_0794]
    LD BC,$0027
    ADD HL,BC
    LD [HL],$00
    INC HL
    LD [HL],$00
    SCF
    POP HL
    POP BC
    RET
L_57DD:
    CALL L_1A02
    PUSH HL
    CALL L_48A5
    LD A,[HL]
    OR A
    JP Z,DERIFN
    PUSH AF
    INC HL
    LD E,[HL]
    INC HL
    LD H,[HL]
    LD L,E
    LD E,A
    CP $02
    JP C,L_5800
    LD C,[HL]
    INC HL
    LD A,[HL]
    DEC E
    CP $3A
    JP Z,L_5804
    DEC HL
    INC E
L_5800:
    DEC HL
    INC E
    LD C,$40
L_5804:
    DEC E
    JP Z,L_5862
    LD A,C
    AND $DF
    SUB $40
    JP C,L_5862
    CP $1B
    JP NC,L_5862
    LD BC,$07FE
    LD [BC],A
    INC BC
    LD D,$0B
L_581C:
    INC HL
L_581D:
    DEC E
    JP M,L_5852
    LD A,[HL]
    CP $2E
    JP NZ,L_5830
    CALL L_583E
    POP AF
    SCF
    PUSH AF
    JP L_581C
L_5830:
    LD [BC],A
    INC BC
    INC HL
    DEC D
    JP NZ,L_581D
L_5837:
    XOR A
    LD [D_080A],A
    POP AF
    POP HL
    RET
L_583E:
    LD A,D
    CP $0B
    JP Z,L_5862
    CP $03
    JP C,L_5862
    RET Z
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP L_583E
L_5852:
    INC D
    DEC D
    JP Z,L_5837
L_5857:
    LD A,$20
    LD [BC],A
    INC BC
    DEC D
    JP NZ,L_5857
    JP L_5837
L_5862:
    JP DERIFN
ST_NAME:
    CALL L_57DD
    PUSH HL
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    LD C,$0F
    CALL L_0005
    INC A
    JP Z,DERFNF
    LD HL,$07EE
    LD DE,$07FE
    LD B,$0C
L_5885:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC B
    JP NZ,L_5885
    POP HL
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_57DD
    PUSH HL
    LD A,[D_07FE]
    LD HL,$07EE
    CP [HL]
    JP NZ,L_1418
    LD DE,$07FE
    LD C,$0F
    CALL L_0005
    INC A
    JP NZ,DERFAE
    LD C,$17
    LD DE,$07EE
    CALL L_0005
    POP HL
    RET
ST_OPEN:
    LD BC,$17E9
    PUSH BC
    CALL L_1A02
    PUSH HL
    CALL L_48A5
    LD A,[HL]
    OR A
    JP Z,DERBFM
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]
    AND $DF
    LD D,$02
    CP $4F
    JP Z,L_58E6
    LD D,$01
    CP $49
    JP Z,L_58E6
    LD D,$03
    CP $52
    JP NZ,DERBFM
L_58E6:
    POP HL
    CALL L_43D3
    INC L
    PUSH DE
    CP $23
    CALL Z,CHRGTR
    CALL L_2075
    CALL L_43D3
    INC L
    LD A,E
    OR A
    JP Z,DERBFN
    POP DE
L_58FE:
    LD E,A
    PUSH DE
    CALL L_5139
    JP NZ,DERFAO
    POP DE
    PUSH BC
    PUSH DE
    CALL L_57DD
    POP DE
    POP BC
    PUSH BC
    PUSH AF
    LD A,D
    CALL L_5ACD
    POP AF
    LD [TEMP],HL
    JP C,L_5931
    LD A,E
    OR A
    JP NZ,L_5931
    LD HL,$0807
    LD A,[HL]
    CP $20
    JP NZ,L_5931
    LD [HL],$42
    INC HL
    LD [HL],$41
    INC HL
    LD [HL],$53
L_5931:
    POP HL
    LD A,D
    PUSH AF
    LD [D_0794],HL
    PUSH HL
    INC HL
    LD DE,$07FE
    LD C,$0C
L_593E:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    JP NZ,L_593E
    XOR A
    LD [HL],A
    LD DE,$0014
    ADD HL,DE
    LD [HL],A
    POP DE
    PUSH DE
    INC DE
    CALL L_57B1
    POP HL
    POP AF
    PUSH AF
    PUSH HL
    CP $02
    JP NZ,L_596F
    PUSH DE
    LD C,$13
    CALL L_0005
    POP DE
L_5963:
    LD C,$16
    CALL L_0005
    INC A
    JP Z,DERTMF
    JP L_5985
L_596F:
    LD C,$0F
    CALL L_0005
    INC A
    JP NZ,L_5985
    POP DE
    POP AF
    PUSH AF
    PUSH DE
    CP $03
    JP NZ,DERFNF
    INC DE
    JP L_5963
L_5985:
    POP DE
    POP AF
    LD [DE],A
    PUSH DE
    LD HL,$0025
    ADD HL,DE
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    POP HL
    LD A,[HL]
    CP $03
    JP Z,L_59A8
    CP $01
    JP NZ,L_43C9
    CALL L_577A
    LD HL,[TEMP]
    RET
L_59A8:
    LD BC,$0029
    ADD HL,BC
    LD C,$80
L_59AE:
    LD [HL],B
    INC HL
    DEC C
    JP NZ,L_59AE
    JP L_43C9
ST_SYSTEM:
    RET NZ
    CALL L_540D
L_59BB:
    JP L_0000
ST_RESET:
    RET NZ
    PUSH HL
    CALL L_540D
    LD C,$19
    CALL L_0005
    PUSH AF
    LD C,$0D
    CALL L_0005
    POP AF
    LD E,A
    LD C,$0E
    CALL L_0005
    POP HL
    RET
ST_KILL:
    CALL L_57DD
    PUSH HL
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    PUSH DE
    LD C,$0F
    CALL L_0005
    INC A
    POP DE
    PUSH DE
    PUSH AF
    LD C,$10
    JP Z,L_59F8
    CALL L_0005
L_59F8:
    POP AF
    POP DE
    JP Z,DERFNF
    LD C,$13
    CALL L_0005
    POP HL
    RET
ST_FILES:
    JP NZ,L_5A14
    PUSH HL
    LD HL,$07FE
    LD [HL],$00
    INC HL
    LD C,$0B
    CALL L_5A96
    POP HL
L_5A14:
    CALL NZ,L_57DD
    XOR A
    LD [D_080A],A
    PUSH HL
    LD HL,$07FF
    LD C,$08
    CALL L_5A92
    LD HL,$0807
    LD C,$03
    CALL L_5A92
    LD DE,$0080
    LD C,$1A
    CALL L_0005
    LD DE,$07FE
    LD C,$11
    CALL L_0005
    CP $FF
    JP Z,DERFNF
L_5A41:
    AND $03
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    LD C,A
    LD B,$00
    LD HL,$0081
    ADD HL,BC
    LD C,$0B
L_5A51:
    LD A,[HL]
    INC HL
    CALL OUTDO
    LD A,C
    CP $04
    JP NZ,L_5A67
    LD A,[HL]
    CP $20
    JP Z,L_5A64
    LD A,$2E
L_5A64:
    CALL OUTDO
L_5A67:
    DEC C
    JP NZ,L_5A51
    LD A,[D_0A65]
    ADD A,$0D
    LD D,A
    LD A,[D_0790]
    CP D
    JP C,L_5A80
    LD A,$20
    CALL OUTDO
    CALL OUTDO
L_5A80:
    CALL C,L_4221
    LD DE,$07FE
    LD C,$12
    CALL L_0005
    CP $FF
    JP NZ,L_5A41
    POP HL
    RET
L_5A92:
    LD A,[HL]
    CP $2A
    RET NZ
L_5A96:
    LD [HL],$3F
    INC HL
    DEC C
    JP NZ,L_5A96
    RET
L_5A9E:
    PUSH DE
    LD C,A
    PUSH BC
    CALL L_0005
    POP BC
    POP DE
    PUSH AF
    LD HL,$0021
    ADD HL,DE
    INC [HL]
    JP NZ,L_5AB6
    INC HL
    INC [HL]
    JP NZ,L_5AB6
    INC HL
    INC [HL]
L_5AB6:
    LD A,C
    CP $22
    JP NZ,L_5ACB
    POP AF
    OR A
    RET Z
    CP $05
    JP Z,DERTMF
    CP $03
    LD A,$01
    RET Z
    INC A
    RET
L_5ACB:
    POP AF
    RET
L_5ACD:
    CP $03
    RET NZ
    DEC HL
    CALL CHRGTR
    PUSH DE
    LD DE,$0080
    JP Z,L_5AE0
    PUSH BC
    CALL L_1411
    POP BC
L_5AE0:
    PUSH HL
    LD HL,[D_0BEA]
    CALL L_43CD
    JP C,L_1418
    LD HL,$00A9
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    XOR A
    LD E,$07
L_5AF4:
    INC HL
    LD [HL],A
    DEC E
    JP NZ,L_5AF4
    POP HL
    POP DE
    RET
ST_PUT:
    .byte $F6
ST_GET:
    .byte $AF
    LD [D_5D75],A
    CALL L_512A
    CP $03
    JP NZ,DERBFM
    PUSH BC
    PUSH HL
    LD HL,$00AD
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE
    EX [SP],HL
    LD A,[HL]
    CP $2C
    CALL Z,L_1411
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR
    EX [SP],HL
    LD A,D
    OR E
    JP Z,DERBRN
    DEC HL
    LD [HL],E
    INC HL
    LD [HL],D
    DEC DE
    POP HL
    POP BC
    PUSH HL
    PUSH BC
    LD HL,$00B0
    ADD HL,BC
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    LD HL,$00A9
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL
    PUSH DE
    PUSH HL
    LD HL,$0080
    CALL L_43CD
    POP HL
    JP NZ,L_5B54
    LD DE,$0000
    JP L_5B92
L_5B54:
    LD B,D
    LD C,E
    LD A,$10
    EX DE,HL
    LD HL,$0000
    PUSH HL
L_5B5D:
    ADD HL,HL
    EX [SP],HL
    JP NC,L_5B67
    ADD HL,HL
    INC HL
    JP L_5B68
L_5B67:
    ADD HL,HL
L_5B68:
    EX [SP],HL
    EX DE,HL
    ADD HL,HL
    EX DE,HL
    JP NC,L_5B76
    ADD HL,BC
    EX [SP],HL
    JP NC,L_5B75
    INC HL
L_5B75:
    EX [SP],HL
L_5B76:
    DEC A
    JP NZ,L_5B5D
    LD A,L
    AND $7F
    LD E,A
    LD D,$00
    POP BC
    LD A,L
    LD L,H
    LD H,C
    ADD HL,HL
    JP C,L_1418
    RLA
    JP NC,L_5B8D
    INC HL
L_5B8D:
    LD A,B
    OR A
    JP NZ,L_1418
L_5B92:
    LD [D_5D6F],HL
    POP HL
    POP BC
    PUSH HL
    LD HL,$00B2
    ADD HL,BC
    LD [D_5D71],HL
L_5B9F:
    LD HL,$0029
    ADD HL,BC
    ADD HL,DE
    LD [D_5D73],HL
    POP HL
    PUSH HL
    LD HL,$0080
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    POP DE
    PUSH DE
    CALL L_43CD
    JP C,L_5BBC
    LD H,D
    LD L,E
L_5BBC:
    LD A,[D_5D75]
    OR A
    JP Z,L_5C02
    LD DE,$0080
    CALL L_43CD
    JP NC,L_5BD1
    PUSH HL
    CALL L_5C20
    POP HL
L_5BD1:
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[D_5D73]
    EX DE,HL
    LD HL,[D_5D71]
    CALL L_5C58
    LD [D_5D71],HL
    LD D,B
    LD E,C
    POP BC
    CALL L_5C1F
L_5BE8:
    LD HL,[D_5D6F]
    INC HL
    LD [D_5D6F],HL
    POP HL
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD A,H
    OR L
    LD DE,$0000
    PUSH HL
    JP NZ,L_5B9F
    POP HL
    POP HL
    RET
L_5C02:
    PUSH HL
    CALL L_5C20
    POP HL
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[D_5D71]
    EX DE,HL
    LD HL,[D_5D73]
    CALL L_5C58
    EX DE,HL
    LD [D_5D71],HL
    LD D,B
    LD E,C
    POP BC
    JP L_5BE8
L_5C1F:
    .byte $F6
L_5C20:
    .byte $AF
    LD [D_07A0],A
    PUSH BC
    PUSH DE
    PUSH HL
    EX DE,HL
    LD HL,[D_5D6F]
    EX DE,HL
    LD HL,$00AB
    ADD HL,BC
    PUSH HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    INC DE
    CALL L_43CD
    POP HL
    LD [HL],E
    INC HL
    LD [HL],D
    JP NZ,L_5C47
    LD A,[D_07A0]
    OR A
    JP Z,L_5C54
L_5C47:
    LD HL,$5C54
    PUSH HL
    PUSH BC
    PUSH HL
    LD HL,$0026
    ADD HL,BC
    JP L_56A4
L_5C54:
    POP HL
    POP DE
    POP BC
    RET
L_5C58:
    PUSH BC
L_5C59:
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    DEC BC
    LD A,B
    OR C
    JP NZ,L_5C59
    POP BC
    RET
L_5C65:
    POP AF
    PUSH DE
    PUSH BC
    PUSH AF
    LD B,H
    LD C,L
    CALL L_5CC4
    JP Z,L_5C93
    CALL L_5CB9
    LD HL,$00B1
    ADD HL,BC
    ADD HL,DE
    POP AF
    LD [HL],A
    PUSH AF
    LD HL,$0028
    ADD HL,BC
    LD D,[HL]
    LD [HL],$00
    CP $0D
    JP Z,L_5C8E
    ADD A,$E0
    LD A,D
    ADC A,$00
    LD [HL],A
L_5C8E:
    POP AF
    POP BC
    POP DE
    POP HL
    RET
L_5C93:
    JP DERFOV
L_5C96:
    PUSH DE
    CALL L_5CC2
    JP Z,L_5C93
    CALL L_5CB9
    LD HL,$00B1
    ADD HL,BC
    ADD HL,DE
    LD A,[HL]
    OR A
    POP DE
    POP HL
    POP BC
    RET
L_5CAB:
    LD HL,$00A9
    JP L_5CB4
L_5CB1:
    LD HL,$00B0
L_5CB4:
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    RET
L_5CB9:
    INC DE
    LD HL,$00B0
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    RET
L_5CC2:
    LD B,H
    LD C,L
L_5CC4:
    CALL L_5CB1
    PUSH DE
    CALL L_5CAB
    EX DE,HL
    POP DE
    CALL L_43CD
    RET
L_5CD1:
    CALL CHRGTR
    LD [TEMP],HL
    CALL L_2392
    CALL L_5CE8
    LD A,$FE
    CALL L_53BE
    CALL L_5D22
    JP L_43C9
L_5CE8:
    LD BC,$0D0B
    LD HL,[TXTTAB]
    EX DE,HL
L_5CEF:
    LD HL,[VARTAB]
    CALL L_43CD
    RET Z
    LD HL,$3958
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    LD A,[DE]
    SUB B
    XOR [HL]
    PUSH AF
    LD HL,$3907
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    POP AF
    XOR [HL]
    ADD A,C
    LD [DE],A
    INC DE
    DEC C
    JP NZ,L_5D19
    LD C,$0B
L_5D19:
    DEC B
    JP NZ,L_5CEF
    LD B,$0D
    JP L_5CEF
L_5D22:
    LD BC,$0D0B
    LD HL,[TXTTAB]
    EX DE,HL
L_5D29:
    LD HL,[VARTAB]
    CALL L_43CD
    RET Z
    LD HL,$3907
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    LD A,[DE]
    SUB C
    XOR [HL]
    PUSH AF
    LD HL,$3958
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A
    POP AF
    XOR [HL]
    ADD A,B
    LD [DE],A
    INC DE
    DEC C
    JP NZ,L_5D53
    LD C,$0B
L_5D53:
    DEC B
    JP NZ,L_5D29
    LD B,$0D
    JP L_5D29
L_5D5C:
    PUSH HL
    LD HL,[CURLIN]
    LD A,H
    AND L
    POP HL
    INC A
    RET NZ
L_5D65:
    PUSH AF
    LD A,[D_0BEC]
    OR A
    JP NZ,L_1418
    POP AF
    RET
