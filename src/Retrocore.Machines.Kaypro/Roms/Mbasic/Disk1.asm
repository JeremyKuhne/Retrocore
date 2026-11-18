;; MBASIC 5.21: DISK FILES, PART 1
;;
;; Part of Mbasic.asm.

FN_MKI:
    LD A,$02
    .byte $01
FN_MKS:
    LD A,$04
    .byte $01
FN_MKD:
    LD A,$08
    PUSH AF
    CALL L_1FAC
    POP AF
    CALL L_46B9
    LD HL,[D_0A99]
    CALL L_28F7
    JP L_48FC
FN_CVI:
    LD A,$01
    .byte $01
FN_CVS:
    LD A,$03
    .byte $01
FN_CVD:
    LD A,$07
    PUSH AF
    CALL L_48A5
    POP AF
    CP [HL]
    JP NC,L_1418
    INC A
    LD [D_0A67],A
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    JP L_28EE
L_5197:
    CALL L_1D64
    LD BC,$198F
    LD DE,$2C20
    JP NZ,L_51BB
    LD E,D
    JP L_51BB
L_51A7:
    CALL L_510B
    CALL L_398B
    CALL L_2A3B
    LD BC,$17E9
    PUSH BC
    PUSH DE
    LD BC,$1512
    XOR A
    LD D,A
    LD E,A
L_51BB:
    PUSH AF
    PUSH BC
    PUSH HL
L_51BE:
    CALL L_57C2
    JP C,DERRPE
    CP $20
    JP NZ,L_51CE
    INC D
    DEC D
    JP NZ,L_51BE
L_51CE:
    CP $22
    JP NZ,L_51E3
    LD B,A
    LD A,E
    CP $2C
    LD A,B
    JP NZ,L_51E3
    LD D,B
    LD E,B
    CALL L_57C2
    JP C,L_5231
L_51E3:
    LD HL,$0962
    LD B,$FF
L_51E8:
    LD C,A
    LD A,D
    CP $22
    LD A,C
    JP Z,L_521C
    CP $0D
    PUSH HL
    JP Z,L_5251
    POP HL
    CP $0A
    JP NZ,L_521C
    LD C,A
    LD A,E
    CP $2C
    LD A,C
    CALL NZ,L_528A
    CALL L_57C2
    JP C,L_5231
    CP $0D
    JP NZ,L_521C
    LD A,E
    CP $20
    JP Z,L_522B
    CP $2C
    LD A,$0D
    JP Z,L_522B
L_521C:
    OR A
    JP Z,L_522B
    CP D
    JP Z,L_5231
    CP E
    JP Z,L_5231
    CALL L_528A
L_522B:
    CALL L_57C2
    JP NC,L_51E8
L_5231:
    PUSH HL
    CP $22
    JP Z,L_523C
    CP $20
    JP NZ,L_5264
L_523C:
    CALL L_57C2
    JP C,L_5264
    CP $20
    JP Z,L_523C
    CP $2C
    JP Z,L_5264
    CP $0D
    JP NZ,L_525C
L_5251:
    CALL L_57C2
    JP C,L_5264
    CP $0A
    JP Z,L_5264
L_525C:
    LD HL,[D_0794]
    LD BC,$0028
    ADD HL,BC
    INC [HL]
L_5264:
    POP HL
L_5265:
    LD [HL],$00
    LD HL,$0961
    LD A,E
    SUB $20
    JP Z,L_5278
    LD B,D
    LD D,$00
    CALL L_46CB
    POP HL
    RET
L_5278:
    CALL L_1D64
    PUSH AF
    CALL CHRGTR
    POP AF
    PUSH AF
    CALL C,L_2ED1
    POP AF
    CALL NC,L_2ECA
    POP HL
    RET
L_528A:
    OR A
    RET Z
    LD [HL],A
    INC HL
    DEC B
    RET NZ
    POP BC
    JP L_5265
L_5294:
    LD D,$01
L_5296:
    XOR A
    JP L_58FE
L_529A:
    .byte $F6
ST_LOAD:
    XOR A
    PUSH AF
    CALL L_5294
    LD A,[D_07C4]
    LD [D_079F],A
    DEC HL
    CALL CHRGTR
    JP Z,L_52BE
    CALL L_43D3
    INC L
    CALL L_43D3
    LD D,D
    JP NZ,SNERR
    POP AF
L_52B9:
    XOR A
    LD [D_07C4],A
    .byte $F6
L_52BE:
    .byte $F1
    LD [D_079E],A
    LD HL,$0080
    LD [HL],$00
    LD [D_07A4],HL
    CALL L_4321
    LD A,[D_079F]
    LD [D_07C4],A
    LD HL,[D_07A2]
    LD [D_07A4],HL
    LD [D_0794],HL
    LD HL,[CURLIN]
    INC HL
    LD A,H
    AND L
    INC A
    JP NZ,L_52E9
    LD [CURLIN],HL
L_52E9:
    CALL L_57C2
    JP C,MAIN
    CP $FE
    JP NZ,L_52FA
    LD [D_0BEC],A
    JP L_52FE
L_52FA:
    INC A
    JP NZ,L_537F
L_52FE:
    LD HL,[TXTTAB]
L_5301:
    EX DE,HL
    LD HL,[FRETOP]
    LD BC,$FFAA
    ADD HL,BC
    CALL L_43CD
    EX DE,HL
    JP C,L_5356
    CALL L_5748
    LD [HL],A
    INC HL
    JP NC,L_5301
    LD [VARTAB],HL
    LD A,[D_0BEC]
    OR A
    CALL NZ,L_5D22
    CALL L_0EAB
    INC HL
    INC HL
    LD [VARTAB],HL
    LD HL,$07C4
    LD A,[HL]
    LD [D_079F],A
    LD [HL],$00
    CALL L_4337
    LD A,[D_079F]
    LD [D_07C4],A
    LD A,[D_0BF3]
    OR A
    JP NZ,L_5030
    LD A,[D_079E]
    OR A
    JP Z,READY
    JP NEWSTT
L_534D:
    CALL L_17E9
    CALL L_5606
    JP L_43C9
L_5356:
    CALL L_4321
    JP L_42DD
ST_MERGE:
    POP BC
    CALL L_5294
    DEC HL
    CALL CHRGTR
    JP Z,L_536D
    CALL L_534D
    JP SNERR
L_536D:
    XOR A
    LD [D_079E],A
    CALL L_57C2
    JP C,MAIN
    INC A
    JP Z,DERBFM
    INC A
    JP Z,DERBFM
L_537F:
    LD HL,[D_0794]
    LD BC,$0028
    ADD HL,BC
    INC [HL]
    JP MAIN
L_538A:
    PUSH HL
    LD HL,[D_0794]
    LD A,H
    OR L
    LD DE,$0042
    JP NZ,ERROR
    POP HL
    JP GONE
ST_SAVE:
    LD D,$02
    CALL L_5296
    DEC HL
    CALL CHRGTR
    JP Z,L_53B6
    CALL L_43D3
    INC L
    CP $50
    JP Z,L_5CD1
    CALL L_43D3
    LD B,C
    JP ST_LIST
L_53B6:
    CALL L_2392
    CALL L_5D65
    LD A,$FF
L_53BE:
    CALL L_5668
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL
    LD HL,[TXTTAB]
L_53C9:
    CALL L_43CD
    JP Z,L_534D
    LD A,[HL]
    INC HL
    PUSH DE
    CALL L_5668
    POP DE
    JP L_53C9
ST_CLOSE:
    LD BC,$5606
    LD A,[D_07C4]
    JP NZ,L_53FC
    PUSH HL
    PUSH BC
    PUSH AF
    LD DE,$53EB
    PUSH DE
    PUSH BC
    RET
    .byte $F1, $C1, $3D, $F2, $E3, $53, $E1, $C9, $C1, $E1, $7E, $FE, $2C, $C0, $CD, $05
    .byte $13
L_53FC:
    PUSH BC
    LD A,[HL]
    CP $23
    CALL Z,CHRGTR
    CALL L_2075
    EX [SP],HL
    PUSH HL
    LD DE,$53F3
    PUSH DE
    JP [HL]
L_540D:
    PUSH DE
    PUSH BC
    XOR A
    CALL ST_CLOSE
    POP BC
    POP DE
    XOR A
    RET
ST_FIELD:
    CALL L_512A
    JP Z,DERBFN
    SUB $03
    JP NZ,DERBFM
    EX DE,HL
    LD HL,$00A9
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD [D_0BE6],HL
    LD HL,$0000
    LD [D_5D6F],HL
    LD A,H
    EX DE,HL
    LD DE,$00B2
L_5439:
    EX DE,HL
    ADD HL,BC
    LD B,A
    EX DE,HL
    LD A,[HL]
    CP $2C
    RET NZ
    PUSH DE
    PUSH BC
    CALL L_2072
    PUSH AF
    CALL L_43D3
    LD B,C
    CALL L_43D3
    LD D,E
    CALL L_398B
    CALL L_2A3B
    POP AF
    POP BC
    EX [SP],HL
    LD C,A
    PUSH DE
    PUSH HL
    LD HL,[D_5D6F]
    LD B,$00
    ADD HL,BC
    LD [D_5D6F],HL
    EX DE,HL
    LD HL,[D_0BE6]
    CALL L_43CD
    JP C,DERFOV
    POP HL
    POP DE
    EX DE,HL
    LD [HL],C
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    JP L_5439
ST_RSET:
    .byte $F6
ST_LSET:
    .byte $37
    PUSH AF
    CALL L_398B
    CALL L_2A3B
    PUSH DE
    CALL L_19F7
    POP BC
    EX [SP],HL
    PUSH HL
    PUSH BC
    CALL L_48A5
    LD B,[HL]
    EX [SP],HL
    LD A,[HL]
    LD C,A
    PUSH BC
    PUSH HL
    PUSH AF
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    OR A
    JP Z,L_54FC
    LD HL,[TXTTAB]
    CALL L_43CD
    JP NC,L_54D7
    LD HL,[VARTAB]
    CALL L_43CD
    JP C,L_54D7
    LD E,C
    LD D,$00
    LD HL,[STREND]
    ADD HL,DE
    EX DE,HL
    LD HL,[FRETOP]
    CALL L_43CD
    JP C,L_5510
    POP AF
L_54C1:
    LD A,C
    CALL L_473C
    POP HL
    POP BC
    EX [SP],HL
    PUSH DE
    PUSH BC
    CALL L_48A5
    POP BC
    POP DE
    EX [SP],HL
    PUSH BC
    PUSH HL
    INC HL
    PUSH AF
    LD [HL],E
    INC HL
    LD [HL],D
L_54D7:
    POP AF
    POP HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    POP BC
    POP HL
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD A,C
    CP B
    JP NC,L_54EA
    LD B,A
L_54EA:
    SUB B
    LD C,A
    POP AF
    CALL NC,L_5506
    INC B
L_54F1:
    DEC B
    JP Z,L_5501
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    JP L_54F1
L_54FC:
    POP BC
    POP BC
    POP BC
    POP BC
L_5500:
    POP BC
L_5501:
    CALL C,L_5506
    POP HL
    RET
L_5506:
    LD A,$20
    INC C
L_5509:
    DEC C
    RET Z
L_550B:
    LD [DE],A
    INC DE
    JP L_5509
L_5510:
    POP AF
    POP HL
    POP BC
    EX [SP],HL
    EX DE,HL
    JP NZ,L_5521
    PUSH BC
    LD A,B
    CALL L_46B9
    CALL L_46FD
    POP BC
L_5521:
    EX [SP],HL
    PUSH BC
    PUSH HL
    JP L_54C1
L_5527:
    CALL CHRGTR
    CALL L_43D3
    INC H
    CALL L_43D3
    JR Z,L_5500
    LD [HL],L
    JR NZ,L_550B
    LD A,[HL]
    CP $2C
    JP NZ,L_554B
    CALL CHRGTR
    CALL L_512A
    CP $02
    JP Z,DERBFM
    CALL L_5122
    XOR A
L_554B:
    PUSH AF
    CALL L_43D3
    ADD HL,HL
    POP AF
    EX [SP],HL
    PUSH AF
    LD A,L
    OR A
    JP Z,L_1418
    PUSH HL
    CALL L_46B9
    EX DE,HL
    POP BC
L_555E:
    POP AF
    PUSH AF
    JP Z,L_5585
    CALL L_4299
    JP NZ,L_556C
    CALL L_41F5
L_556C:
    CP $03
    JP Z,L_557E
L_5571:
    LD [HL],A
    INC HL
    DEC C
    JP NZ,L_555E
    POP AF
    CALL L_17E9
    JP L_46FD
L_557E:
    LD HL,[SAVSTK]
    LD SP,HL
    JP ENDCON
L_5585:
    CALL L_57C2
    JP C,DERRPE
    JP L_5571
FN_EOF:
    CALL L_5136
    JP Z,DERBFN
    CP $02
    JP Z,DERBFM
L_5599:
    LD HL,$0027
    ADD HL,BC
    LD A,[HL]
    OR A
    JP Z,L_55C3
    LD A,[BC]
    CP $03
    JP Z,L_55C3
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_55B8
    PUSH BC
    LD H,B
    LD L,C
    CALL L_577D
    POP BC
    JP L_5599
L_55B8:
    LD A,$80
    SUB [HL]
    LD C,A
    LD B,$00
    ADD HL,BC
    INC HL
    LD A,[HL]
    SUB $1A
L_55C3:
    SUB $01
    SBC A,A
    JP L_287F
L_55C9:
    LD D,B
    LD E,C
    INC DE
    LD HL,$0027
    ADD HL,BC
    PUSH BC
    XOR A
    LD [HL],A
    CALL L_57B1
    LD A,[D_0821]
    CALL L_5A9E
    CP $FF
    JP Z,DERTMF
    DEC A
    JP Z,DERDIO
    DEC A
    JP NZ,L_55F5
    POP DE
    XOR A
    LD [DE],A
    LD C,$10
    INC DE
    CALL L_0005
    JP DERDFL
L_55F5:
    INC A
    JP Z,DERTMF
    POP BC
    LD HL,$0025
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE
    LD [HL],D
    DEC HL
    LD [HL],E
    RET
L_5606:
    CALL L_5139
    JP Z,L_5636
    PUSH BC
    LD A,[BC]
    LD D,B
    LD E,C
    INC DE
    PUSH DE
    CP $02
    JP NZ,L_562C
    LD HL,$5623
    PUSH HL
    PUSH HL
    LD H,B
    LD L,C
    LD A,$1A
    JP L_5679
    .byte $21, $27, $00, $09, $7E, $B7, $C4, $CC, $55
L_562C:
    POP DE
    CALL L_57B1
    LD C,$10
    CALL L_0005
    POP BC
L_5636:
    LD D,$29
    XOR A
L_5639:
    LD [BC],A
    INC BC
    DEC D
    JP NZ,L_5639
    RET
