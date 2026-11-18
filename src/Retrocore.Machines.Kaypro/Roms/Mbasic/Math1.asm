;; MBASIC 5.21: MATH PACKAGE, PART 1
;;
;; Part of Mbasic.asm.

ST_RANDOMIZE:
    JP Z,L_2494
    CALL L_1A02
    PUSH HL
    CALL FN_CINT
    JP L_24B0
L_2494:
    PUSH HL
L_2495:
    LD HL,$24B8
    CALL L_4723
    CALL L_4B0D
    POP DE
    JP C,L_4416
    PUSH DE
    INC HL
    LD A,[HL]
    CALL L_2ED1
    LD A,[HL]
    OR A
    JP NZ,L_2495
    CALL FN_CINT
L_24B0:
    LD [D_386A],HL
    CALL L_37CF
    POP HL
    RET
    .byte $52, $61, $6E, $64, $6F, $6D, $20, $6E, $75, $6D, $62, $65, $72, $20, $73, $65
    .byte $65, $64, $20, $28, $2D, $33, $32, $37, $36, $38, $20, $74, $6F, $20, $33, $32
    .byte $37, $36, $37, $29, $00
L_24DD:
    LD C,$1D
    JP L_24E4
L_24E2:
    LD C,$1A
L_24E4:
    LD B,$00
    EX DE,HL
    LD HL,[CURLIN]
    LD [D_0BC4],HL
    EX DE,HL
L_24EE:
    INC B
L_24EF:
    DEC HL
L_24F0:
    CALL CHRGTR
    JP Z,L_2500
    CP $A2
    JP Z,L_2515
    CP $CF
    JP NZ,L_24F0
L_2500:
    OR A
    JP NZ,L_2515
    INC HL
    LD A,[HL]
    INC HL
    OR [HL]
    LD E,C
    JP Z,ERROR
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_0BC4],HL
    EX DE,HL
L_2515:
    CALL CHRGTR
    LD A,C
    CP $1A
    LD A,[HL]
    JP Z,L_252E
    CP $B4
    JP Z,L_24EE
    CP $B5
    JP NZ,L_24EF
    DEC B
    JP NZ,L_24EF
    RET
L_252E:
    CP $82
    JP Z,L_24EE
    CP $83
    JP NZ,L_24EF
    DEC B
    RET Z
    CALL CHRGTR
    JP Z,L_2500
    EX DE,HL
    LD HL,[CURLIN]
    PUSH HL
    LD HL,[D_0BC4]
    LD [CURLIN],HL
    EX DE,HL
    PUSH BC
    CALL L_398B
    POP BC
    DEC HL
    CALL CHRGTR
    LD DE,$2500
    JP Z,L_2563
    CALL L_43D3
    INC L
    DEC HL
    LD DE,$2538
L_2563:
    EX [SP],HL
    LD [CURLIN],HL
    POP HL
    PUSH DE
    RET
    .byte $F5, $3A, $09, $0C, $32, $0A, $0C, $F1
L_2572:
    PUSH AF
    XOR A
    LD [D_0C09],A
    POP AF
    RET
L_2579:
    LD HL,$360D
L_257C:
    CALL L_28B7
    JP L_2588
    .byte $CD, $B7, $28
L_2585:
    CALL L_2874
L_2588:
    LD A,B
    OR A
    RET Z
    LD A,[D_0C07]
    OR A
    JP Z,L_28A9
    SUB B
    JP NC,L_25A2
    CPL
    INC A
    EX DE,HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    POP BC
    POP DE
L_25A2:
    CP $19
    RET NC
    PUSH AF
    CALL L_28D6
    LD H,A
    POP AF
    CALL L_2662
    LD A,H
    OR A
    LD HL,$0C04
    JP P,L_25C9
    CALL L_2642
    JP NC,L_2623
    INC HL
    INC [HL]
    JP Z,L_3088
    LD L,$01
    CALL L_2689
    JP L_2623
L_25C9:
    XOR A
    SUB B
    LD B,A
    LD A,[HL]
    SBC A,E
    LD E,A
    INC HL
    LD A,[HL]
    SBC A,D
    LD D,A
    INC HL
    LD A,[HL]
    SBC A,C
    LD C,A
L_25D7:
    CALL C,L_264E
L_25DA:
    LD L,B
    LD H,E
    XOR A
L_25DD:
    LD B,A
    LD A,C
    OR A
    JP NZ,L_260E
    LD C,D
    LD D,H
    LD H,L
    LD L,A
    LD A,B
    SUB $08
    CP $E0
    JP NZ,L_25DD
L_25EF:
    XOR A
L_25F0:
    LD [D_0C07],A
    RET
L_25F4:
    LD A,H
    OR L
    OR D
    JP NZ,L_2606
    LD A,C
L_25FB:
    DEC B
    RLA
    JP NC,L_25FB
    INC B
    RRA
    LD C,A
    JP L_2611
L_2606:
    DEC B
    ADD HL,HL
    LD A,D
    RLA
    LD D,A
    LD A,C
    ADC A,A
    LD C,A
L_260E:
    JP P,L_25F4
L_2611:
    LD A,B
    LD E,H
    LD B,L
    OR A
    JP Z,L_2623
    LD HL,$0C07
    ADD A,[HL]
    LD [HL],A
    JP NC,L_25EF
    JP Z,L_25EF
L_2623:
    LD A,B
L_2624:
    LD HL,$0C07
    OR A
    CALL M,L_2635
    LD B,[HL]
    INC HL
    LD A,[HL]
    AND $80
    XOR C
    LD C,A
    JP L_28A9
L_2635:
    INC E
    RET NZ
    INC D
    RET NZ
    INC C
    RET NZ
    LD C,$80
    INC [HL]
    RET NZ
    JP L_3087
L_2642:
    LD A,[HL]
    ADD A,E
    LD E,A
    INC HL
    LD A,[HL]
    ADC A,D
    LD D,A
    INC HL
    LD A,[HL]
    ADC A,C
    LD C,A
    RET
L_264E:
    LD HL,$0C08
    LD A,[HL]
    CPL
    LD [HL],A
    XOR A
    LD L,A
    SUB B
    LD B,A
    LD A,L
    SBC A,E
    LD E,A
    LD A,L
    SBC A,D
    LD D,A
    LD A,L
    SBC A,C
    LD C,A
    RET
L_2662:
    LD B,$00
L_2664:
    SUB $08
    JP C,L_2671
    LD B,E
    LD E,D
    LD D,C
    LD C,$00
    JP L_2664
L_2671:
    ADD A,$09
    LD L,A
    LD A,D
    OR E
    OR B
    JP NZ,L_2685
    LD A,C
L_267B:
    DEC L
    RET Z
    RRA
    LD C,A
    JP NC,L_267B
    JP L_268B
L_2685:
    XOR A
    DEC L
    RET Z
    LD A,C
L_2689:
    RRA
    LD C,A
L_268B:
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    LD A,B
    RRA
    LD B,A
    JP L_2685
    .byte $00, $00, $00, $81, $04, $9A, $F7, $19, $83, $24, $63, $43, $83, $75, $CD, $8D
    .byte $84, $A9, $7F, $83, $82, $04, $00, $00, $00, $81, $E2, $B0, $4D, $83, $0A, $72
    .byte $11, $83, $F4, $04, $35, $7F
FN_LOG:
    CALL L_2845
    OR A
    JP PE,L_1418
    CALL L_26D0
    LD BC,$8031
    LD DE,$7218
    JP L_2703
L_26D0:
    CALL L_28B4
    LD A,$80
    LD [D_0C07],A
    XOR B
    PUSH AF
    CALL L_2899
    LD HL,$269B
    CALL L_37A7
    POP BC
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    LD HL,$26AC
    CALL L_37A7
    POP BC
    POP DE
    CALL L_2769
    POP AF
    CALL L_2899
    CALL L_2854
    POP BC
    POP DE
    JP L_2588
L_2703:
    CALL L_2845
    RET Z
    LD L,$00
    CALL L_2803
    LD A,C
    LD [D_273C],A
    EX DE,HL
    LD [D_2737],HL
    LD BC,$0000
    LD D,B
    LD E,B
    LD HL,$25DA
    PUSH HL
    LD HL,$2725
    PUSH HL
    PUSH HL
    LD HL,$0C04
    LD A,[HL]
    INC HL
    OR A
    JP Z,L_2759
    PUSH HL
    EX DE,HL
    LD E,$08
L_272F:
    RRA
    LD D,A
    LD A,C
    JP NC,L_273D
    PUSH DE
    .byte $11
D_2737:
    .byte $00, $00
    ADD HL,DE
    POP DE
    .byte $CE
D_273C:
    .byte $00
L_273D:
    RRA
    LD C,A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    LD A,B
    RRA
    LD B,A
    AND $10
    JP Z,L_2751
    LD A,B
    OR $20
    LD B,A
L_2751:
    DEC E
    LD A,D
    JP NZ,L_272F
    EX DE,HL
L_2757:
    POP HL
    RET
L_2759:
    LD B,E
    LD E,D
    LD D,C
    LD C,A
    RET
L_275E:
    CALL L_2899
    LD HL,$2DAE
    CALL L_28A6
L_2767:
    POP BC
    POP DE
L_2769:
    CALL L_2845
    JP Z,L_3090
    LD L,$FF
    CALL L_2803
    INC [HL]
    JP Z,L_3067
    INC [HL]
    JP Z,L_3067
    DEC HL
    LD A,[HL]
    LD [D_27A0],A
    DEC HL
    LD A,[HL]
    LD [D_279C],A
    DEC HL
    LD A,[HL]
    LD [D_2798],A
    LD B,C
    EX DE,HL
    XOR A
    LD C,A
    LD D,A
    LD E,A
    LD [D_27A3],A
L_2794:
    PUSH HL
    PUSH BC
    LD A,L
    .byte $D6
D_2798:
    .byte $00
    LD L,A
    LD A,H
    .byte $DE
D_279C:
    .byte $00
    LD H,A
    LD A,B
    .byte $DE
D_27A0:
    .byte $00
    LD B,A
    .byte $3E
D_27A3:
    .byte $00
    SBC A,$00
    CCF
    JP NC,L_27B1
    LD [D_27A3],A
    POP AF
    POP AF
    SCF
    .byte $D2
L_27B1:
    .byte $C1, $E1
    LD A,C
    INC A
    DEC A
    RRA
    JP P,L_27CF
    RLA
    LD A,[D_27A3]
    RRA
    AND $C0
    PUSH AF
    LD A,B
    OR H
    OR L
    JP Z,L_27CA
    LD A,$20
L_27CA:
    POP HL
    OR H
    JP L_2624
L_27CF:
    RLA
    LD A,E
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,C
    RLA
    LD C,A
    ADD HL,HL
    LD A,B
    RLA
    LD B,A
    LD A,[D_27A3]
    RLA
    LD [D_27A3],A
    LD A,C
    OR D
    OR E
    JP NZ,L_2794
    PUSH HL
    LD HL,$0C07
    DEC [HL]
    POP HL
    JP NZ,L_2794
    JP L_25EF
    .byte $3E, $FF, $2E
L_27F9:
    XOR A
    LD HL,$0C13
    LD C,[HL]
    INC HL
    XOR [HL]
    LD B,A
    LD L,$00
L_2803:
    LD A,B
    OR A
    JP Z,L_2827
    LD A,L
    LD HL,$0C07
    XOR [HL]
    ADD A,B
    LD B,A
    RRA
    XOR B
    LD A,B
    JP P,L_2826
    ADD A,$80
    LD [HL],A
    JP Z,L_2757
    CALL L_28D6
    LD [HL],A
L_281F:
    DEC HL
    RET
    .byte $CD, $45, $28, $2F, $E1
L_2826:
    OR A
L_2827:
    POP HL
    JP P,L_25EF
    JP L_3067
L_282E:
    CALL L_28B4
    LD A,B
    OR A
    RET Z
    ADD A,$02
    JP C,L_3080
    LD B,A
    CALL L_2588
    LD HL,$0C07
    INC [HL]
    RET NZ
    JP L_3080
L_2845:
    LD A,[D_0C07]
    OR A
    RET Z
    LD A,[D_0C06]
    CP $2F
L_284F:
    RLA
L_2850:
    SBC A,A
    RET NZ
    INC A
    RET
L_2854:
    LD B,$88
    LD DE,$0000
L_2859:
    LD HL,$0C07
    LD C,A
    LD [HL],B
    LD B,$00
    INC HL
    LD [HL],$80
    RLA
    JP L_25D7
FN_ABS:
    CALL L_2886
    RET P
L_286B:
    CALL L_1D64
    JP M,L_2BF8
    JP Z,TMERR
L_2874:
    LD HL,$0C06
    LD A,[HL]
    XOR $80
    LD [HL],A
    RET
FN_SGN:
    CALL L_2886
L_287F:
    LD L,A
    RLA
    SBC A,A
    LD H,A
    JP L_29DC
L_2886:
    CALL L_1D64
    JP Z,TMERR
    JP P,L_2845
    LD HL,[D_0C04]
L_2892:
    LD A,H
    OR L
    RET Z
    LD A,H
    JP L_284F
L_2899:
    EX DE,HL
    LD HL,[D_0C04]
    EX [SP],HL
    PUSH HL
    LD HL,[D_0C06]
    EX [SP],HL
    PUSH HL
    EX DE,HL
    RET
L_28A6:
    CALL L_28B7
L_28A9:
    EX DE,HL
    LD [D_0C04],HL
    LD H,B
    LD L,C
    LD [D_0C06],HL
    EX DE,HL
    RET
L_28B4:
    LD HL,$0C04
L_28B7:
    LD E,[HL]
    INC HL
L_28B9:
    LD D,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
L_28BE:
    INC HL
    RET
L_28C0:
    LD DE,$0C04
L_28C3:
    LD B,$04
    JP L_28CD
    .byte $EB
L_28C9:
    LD A,[D_0A67]
    LD B,A
L_28CD:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC B
    JP NZ,L_28CD
    RET
L_28D6:
    LD HL,$0C06
    LD A,[HL]
    RLCA
    SCF
    RRA
    LD [HL],A
    CCF
    RRA
    INC HL
    INC HL
    LD [HL],A
    LD A,C
    RLCA
    SCF
    RRA
    LD C,A
    RRA
    XOR [HL]
    RET
L_28EB:
    LD HL,$0C0D
L_28EE:
    LD DE,$28C8
    JP L_28FA
L_28F4:
    LD HL,$0C0D
L_28F7:
    LD DE,$28C9
L_28FA:
    PUSH DE
    LD DE,$0C04
    CALL L_1D64
    RET C
    LD DE,$0C00
    RET
L_2906:
    LD A,B
    OR A
    JP Z,L_2845
    LD HL,$284E
    PUSH HL
    CALL L_2845
    LD A,C
    RET Z
    LD HL,$0C06
    XOR [HL]
    LD A,C
    RET M
    CALL L_2920
L_291D:
    RRA
    XOR C
    RET
L_2920:
    INC HL
    LD A,B
    CP [HL]
    RET NZ
    DEC HL
    LD A,C
    CP [HL]
    RET NZ
    DEC HL
    LD A,D
    CP [HL]
    RET NZ
    DEC HL
    LD A,E
    SUB [HL]
    RET NZ
    POP HL
    POP HL
    RET
L_2933:
    LD A,D
    XOR H
    LD A,H
    JP M,L_284F
    CP D
    JP NZ,L_2940
    LD A,L
    SUB E
    RET Z
L_2940:
    JP L_2850
L_2943:
    LD HL,$0C0D
    CALL L_28C9
    LD DE,$0C14
    LD A,[DE]
    OR A
    JP Z,L_2845
    LD HL,$284E
    PUSH HL
    CALL L_2845
    DEC DE
    LD A,[DE]
    LD C,A
    RET Z
    LD HL,$0C06
    XOR [HL]
    LD A,C
    RET M
    INC DE
    INC HL
    LD B,$08
L_2966:
    LD A,[DE]
    SUB [HL]
    JP NZ,L_291D
    DEC DE
    DEC HL
    DEC B
    JP NZ,L_2966
    POP BC
    RET
    .byte $CD, $49, $29, $C2, $4E, $28, $C9
FN_CINT:
    CALL L_1D64
    LD HL,[D_0C04]
    RET M
    JP Z,TMERR
    JP PO,L_2999
    CALL L_28F4
    LD HL,$3609
    CALL L_28EE
    CALL L_2C26
    CALL L_29FE
    JP L_299C
L_2999:
    CALL L_2579
L_299C:
    LD A,[D_0C06]
    OR A
    PUSH AF
    AND $7F
    LD [D_0C06],A
    LD A,[D_0C07]
    CP $90
    JP NC,OVERR
    CALL L_2A42
    LD A,[D_0C07]
    OR A
    JP NZ,L_29BD
    POP AF
    EX DE,HL
    JP L_29C2
L_29BD:
    POP AF
    EX DE,HL
    JP P,L_29C8
L_29C2:
    LD A,H
    CPL
    LD H,A
    LD A,L
    CPL
    LD L,A
L_29C8:
    JP L_29DC
    .byte $21, $DB, $0C, $E5
L_29CF:
    LD A,[D_0C07]
    CP $90
    JP NC,L_29E5
    CALL L_2A42
    EX DE,HL
L_29DB:
    POP DE
L_29DC:
    LD [D_0C04],HL
L_29DF:
    LD A,$02
L_29E1:
    LD [D_0A67],A
    RET
L_29E5:
    LD BC,$9080
    LD DE,$0000
    CALL L_2906
    RET NZ
    LD H,C
    LD L,D
    JP L_29DB
FN_CSNG:
    CALL L_1D64
    RET PO
    JP M,L_2A11
    JP Z,TMERR
L_29FE:
    CALL L_28B4
    CALL L_2A36
    LD A,B
    OR A
    RET Z
    CALL L_28D6
    LD HL,$0C03
    LD B,[HL]
    JP L_2623
L_2A11:
    LD HL,[D_0C04]
L_2A14:
    CALL L_2A36
    LD A,H
    LD D,L
    LD E,$00
    LD B,$90
    JP L_2859
FN_CDBL:
    CALL L_1D64
    RET NC
    JP Z,TMERR
    CALL M,L_2A11
L_2A2A:
    LD HL,$0000
    LD [D_0C00],HL
    LD [D_0C02],HL
L_2A33:
    LD A,$08
    .byte $01
L_2A36:
    LD A,$04
    JP L_29E1
L_2A3B:
    CALL L_1D64
    RET Z
    JP TMERR
L_2A42:
    LD B,A
    LD C,A
    LD D,A
    LD E,A
    OR A
    RET Z
    PUSH HL
    CALL L_28B4
    CALL L_28D6
    XOR [HL]
    LD H,A
    CALL M,L_2A66
    LD A,$98
    SUB B
    CALL L_2662
    LD A,H
    RLA
    CALL C,L_2635
    LD B,$00
    CALL C,L_264E
    POP HL
    RET
L_2A66:
    DEC DE
    LD A,D
    AND E
    INC A
    RET NZ
L_2A6B:
    DEC BC
    RET
