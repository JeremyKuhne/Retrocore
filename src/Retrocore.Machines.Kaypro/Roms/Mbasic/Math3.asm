;; MBASIC 5.21: MATH PACKAGE, PART 3
;;
;; Part of Mbasic.asm.

LINPRT:
    LD BC,$4722
    PUSH BC
    CALL L_29DC
    XOR A
    CALL L_31B2
    OR [HL]
    JP L_3146
L_3129:
    XOR A
L_312A:
    CALL L_31B2
    AND $08
    JP Z,L_3134
    LD [HL],$2B
L_3134:
    EX DE,HL
    CALL L_2886
    EX DE,HL
    JP P,L_3146
    LD [HL],$2D
    PUSH BC
    PUSH HL
    CALL L_286B
    POP HL
    POP BC
    OR H
L_3146:
    INC HL
    LD [HL],$30
    LD A,[TEMP3]
    LD D,A
    RLA
    LD A,[D_0A67]
    JP C,L_32D7
    JP Z,L_32CF
    CP $04
    JP NC,L_31BB
    LD BC,$0000
    CALL L_35BA
L_3162:
    LD HL,$0C16
    LD B,[HL]
    LD C,$20
    LD A,[TEMP3]
    LD E,A
    AND $20
    JP Z,L_317F
    LD A,B
    CP C
    LD C,$2A
    JP NZ,L_317F
    LD A,E
    AND $04
    JP NZ,L_317F
    LD B,C
L_317F:
    LD [HL],C
    CALL CHRGTR
    JP Z,L_319F
    CP $45
    JP Z,L_319F
    CP $44
    JP Z,L_319F
    CP $30
    JP Z,L_317F
    CP $2C
    JP Z,L_317F
    CP $2E
    JP NZ,L_31A2
L_319F:
    DEC HL
    LD [HL],$30
L_31A2:
    LD A,E
    AND $10
    JP Z,L_31AB
    DEC HL
    LD [HL],$24
L_31AB:
    LD A,E
    AND $04
    RET NZ
    DEC HL
    LD [HL],B
    RET
L_31B2:
    LD [TEMP3],A
    LD HL,$0C16
    LD [HL],$20
    RET
L_31BB:
    CALL L_2899
    EX DE,HL
    LD HL,[D_0C00]
    PUSH HL
    LD HL,[D_0C02]
    PUSH HL
    EX DE,HL
    PUSH AF
    XOR A
    LD [D_0C0B],A
    POP AF
    PUSH AF
    CALL L_3266
    LD B,$45
    LD C,$00
L_31D6:
    PUSH HL
    LD A,[HL]
L_31D8:
    CP B
    JP Z,L_3207
    CP $3A
    JP NC,L_31E7
    CP $30
    JP C,L_31E7
    INC C
L_31E7:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_31D8
    LD A,$44
    CP B
    LD B,A
    POP HL
    LD C,$00
    JP NZ,L_31D6
L_31F7:
    POP AF
    POP BC
    POP DE
    EX DE,HL
    LD [D_0C00],HL
    LD H,B
    LD L,C
    LD [D_0C02],HL
    EX DE,HL
    POP BC
    POP DE
    RET
L_3207:
    PUSH BC
    LD B,$00
    INC HL
    LD A,[HL]
L_320C:
    CP $2B
    JP Z,L_324E
    CP $2D
    JP Z,L_3225
    SUB $30
    LD C,A
    LD A,B
    ADD A,A
    ADD A,A
    ADD A,B
    ADD A,A
    ADD A,C
    LD B,A
    CP $10
    JP NC,L_324E
L_3225:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,L_320C
    LD H,B
    POP BC
    LD A,B
    CP $45
    JP NZ,L_3243
    LD A,C
    ADD A,H
    CP $09
    POP HL
    JP NC,L_31F7
L_323B:
    LD A,$80
    LD [D_0C0B],A
    JP L_3253
L_3243:
    LD A,H
    ADD A,C
    CP $12
    POP HL
    JP NC,L_31F7
    JP L_323B
L_324E:
    POP BC
    POP HL
    JP L_31F7
L_3253:
    POP AF
    POP BC
    POP DE
    EX DE,HL
    LD [D_0C00],HL
    LD H,B
    LD L,C
    LD [D_0C02],HL
    EX DE,HL
    POP BC
    POP DE
    CALL L_28A9
    INC HL
L_3266:
    CP $05
    PUSH HL
    SBC A,$00
    RLA
    LD D,A
    INC D
    CALL L_345C
    LD BC,$0300
    PUSH AF
    LD A,[D_0C0B]
    OR A
    JP P,L_3281
    POP AF
    ADD A,D
    JP L_328B
L_3281:
    POP AF
    ADD A,D
    JP M,L_328F
    INC D
    CP D
    JP NC,L_328F
L_328B:
    INC A
    LD B,A
    LD A,$02
L_328F:
    SUB $02
    POP HL
    PUSH AF
    CALL L_34FB
    LD [HL],$30
    CALL Z,L_28BE
    CALL L_3522
L_329E:
    DEC HL
    LD A,[HL]
    CP $30
    JP Z,L_329E
    CP $2E
    CALL NZ,L_28BE
    POP AF
    JP Z,L_32D0
L_32AE:
    PUSH AF
    CALL L_1D64
    LD A,$22
    ADC A,A
    LD [HL],A
    INC HL
    POP AF
    LD [HL],$2B
    JP P,L_32C1
    LD [HL],$2D
    CPL
    INC A
L_32C1:
    LD B,$2F
L_32C3:
    INC B
    SUB $0A
    JP NC,L_32C3
    ADD A,$3A
    INC HL
    LD [HL],B
    INC HL
    LD [HL],A
L_32CF:
    INC HL
L_32D0:
    LD [HL],$00
    EX DE,HL
    LD HL,$0C16
    RET
L_32D7:
    INC HL
    PUSH BC
    CP $04
    LD A,D
    JP NC,L_3351
    RRA
    JP C,L_33EE
    LD BC,$0603
    CALL L_34F3
    POP DE
    LD A,D
    SUB $05
    CALL P,L_34CF
    CALL L_35BA
L_32F3:
    LD A,E
    OR A
    CALL Z,L_281F
    DEC A
    CALL P,L_34CF
L_32FC:
    PUSH HL
    CALL L_3162
    POP HL
    JP Z,L_3306
    LD [HL],B
    INC HL
L_3306:
    LD [HL],$00
    LD HL,$0C15
L_330B:
    INC HL
L_330C:
    LD A,[TEMP2]
    SUB L
    SUB D
    RET Z
    LD A,[HL]
    CP $20
    JP Z,L_330B
    CP $2A
    JP Z,L_330B
    DEC HL
    PUSH HL
    PUSH AF
    LD BC,$331F
    PUSH BC
    CALL CHRGTR
    CP $2D
    RET Z
    CP $2B
    RET Z
    CP $24
    RET Z
    POP BC
    CP $30
    JP NZ,L_3349
    INC HL
    CALL CHRGTR
    JP NC,L_3349
    DEC HL
    .byte $01
L_333F:
    .byte $2B, $77
    POP AF
    JP Z,L_333F
    POP BC
    JP L_330C
L_3349:
    POP AF
    JP Z,L_3349
    POP HL
    LD [HL],$25
    RET
L_3351:
    PUSH HL
    RRA
    JP C,L_33F5
    JP Z,L_336D
    LD DE,$3611
    CALL L_2943
    LD D,$10
    JP M,L_337B
L_3364:
    POP HL
    POP BC
    CALL L_3129
    DEC HL
    LD [HL],$25
    RET
L_336D:
    LD BC,$B60E
    LD DE,$1BCA
    CALL L_2906
    JP P,L_3364
    LD D,$06
L_337B:
    CALL L_2845
    CALL NZ,L_345C
    POP HL
    POP BC
    JP M,L_33A0
    PUSH BC
    LD E,A
    LD A,B
    SUB D
    SUB E
    CALL P,L_34CF
    CALL L_34E6
    CALL L_3522
    OR E
    CALL NZ,L_34DF
    OR E
    CALL NZ,L_350E
    POP DE
    JP L_32F3
L_33A0:
    LD E,A
    LD A,C
    OR A
    CALL NZ,L_2FCB
    ADD A,E
    JP M,L_33AB
    XOR A
L_33AB:
    PUSH BC
    PUSH AF
L_33AD:
    CALL M,L_2FCD
    JP M,L_33AD
    POP BC
    LD A,E
    SUB B
    POP BC
    LD E,A
    ADD A,D
    LD A,B
    JP M,L_33C9
    SUB D
    SUB E
    CALL P,L_34CF
    PUSH BC
    CALL L_34E6
    JP L_33DA
L_33C9:
    CALL L_34CF
    LD A,C
    CALL L_3512
    LD C,A
    XOR A
    SUB D
    SUB E
    CALL L_34CF
    PUSH BC
    LD B,A
    LD C,A
L_33DA:
    CALL L_3522
    POP BC
    OR C
    JP NZ,L_33E5
    LD HL,[TEMP2]
L_33E5:
    ADD A,E
    DEC A
    CALL P,L_34CF
    LD D,B
    JP L_32FC
L_33EE:
    PUSH HL
    PUSH DE
    CALL L_2A11
    POP DE
    XOR A
L_33F5:
    JP Z,L_33FB
    LD E,$10
    .byte $01
L_33FB:
    .byte $1E, $06
    CALL L_2845
    SCF
    CALL NZ,L_345C
    POP HL
    POP BC
    PUSH AF
    LD A,C
    OR A
    PUSH AF
    CALL NZ,L_2FCB
    ADD A,B
    LD C,A
    LD A,D
    AND $04
    CP $01
    SBC A,A
    LD D,A
    ADD A,C
    LD C,A
    SUB E
    PUSH AF
    PUSH BC
L_341B:
    CALL M,L_2FCD
    JP M,L_341B
    POP BC
    POP AF
    PUSH BC
    PUSH AF
    JP M,L_3429
    XOR A
L_3429:
    CPL
    INC A
    ADD A,B
    INC A
    ADD A,D
    LD B,A
    LD C,$00
    CALL L_3522
    POP AF
    CALL P,L_34D8
    CALL L_350E
    POP BC
    POP AF
    JP NZ,L_344C
    CALL L_281F
    LD A,[HL]
    CP $2E
    CALL NZ,L_28BE
    LD [TEMP2],HL
L_344C:
    POP AF
    JP C,L_3453
    ADD A,E
    SUB B
    SUB D
L_3453:
    PUSH BC
    CALL L_32AE
    EX DE,HL
    POP DE
    JP L_32FC
L_345C:
    PUSH DE
    XOR A
    PUSH AF
    CALL L_1D64
    JP PO,L_3480
L_3465:
    LD A,[D_0C07]
    CP $91
    JP NC,L_3480
    LD DE,$35F1
    LD HL,$0C0D
    CALL L_28C9
    CALL L_2D64
    POP AF
    SUB $0A
    PUSH AF
    JP L_3465
L_3480:
    CALL L_34B2
L_3483:
    CALL L_1D64
    JP PE,L_3495
    LD BC,$9143
    LD DE,$4FF9
    CALL L_2906
    JP L_349B
L_3495:
    LD DE,$35F9
    CALL L_2943
L_349B:
    JP P,L_34AE
    POP AF
    CALL L_2FBE
    PUSH AF
    JP L_3483
L_34A6:
    POP AF
    CALL L_2FCD
    PUSH AF
    CALL L_34B2
L_34AE:
    POP AF
    OR A
    POP DE
    RET
L_34B2:
    CALL L_1D64
    JP PE,L_34C4
    LD BC,$9474
    LD DE,$23F8
    CALL L_2906
    JP L_34CA
L_34C4:
    LD DE,$3601
    CALL L_2943
L_34CA:
    POP HL
    JP P,L_34A6
    JP [HL]
L_34CF:
    OR A
L_34D0:
    RET Z
    DEC A
    LD [HL],$30
    INC HL
    JP L_34D0
L_34D8:
    JP NZ,L_34DF
L_34DB:
    RET Z
    CALL L_350E
L_34DF:
    LD [HL],$30
    INC HL
    DEC A
    JP L_34DB
L_34E6:
    LD A,E
    ADD A,D
    INC A
    LD B,A
    INC A
L_34EB:
    SUB $03
    JP NC,L_34EB
    ADD A,$05
    LD C,A
L_34F3:
    LD A,[TEMP3]
    AND $40
    RET NZ
    LD C,A
    RET
L_34FB:
    DEC B
    JP P,L_350F
    LD [TEMP2],HL
    LD [HL],$2E
L_3504:
    INC HL
    LD [HL],$30
    INC B
    JP NZ,L_3504
    INC HL
    LD C,B
    RET
L_350E:
    DEC B
L_350F:
    JP NZ,L_351A
L_3512:
    LD [HL],$2E
    LD [TEMP2],HL
    INC HL
    LD C,B
    RET
L_351A:
    DEC C
    RET NZ
    LD [HL],$2C
    INC HL
    LD C,$03
    RET
L_3522:
    PUSH DE
    CALL L_1D64
    JP PO,L_3571
    PUSH BC
    PUSH HL
    CALL L_28F4
    LD HL,$3609
    CALL L_28EE
    CALL L_2C26
    XOR A
    CALL L_2ACF
    POP HL
    POP BC
    LD DE,$3619
    LD A,$0A
L_3542:
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    LD B,$2F
L_354B:
    INC B
    POP HL
    PUSH HL
    LD A,$9E
    CALL L_2CFF
    JP NC,L_354B
    POP HL
    LD A,$8E
    CALL L_2CFF
    EX DE,HL
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,L_3542
    PUSH BC
    PUSH HL
    LD HL,$0C00
    CALL L_28A6
    JP L_357E
L_3571:
    PUSH BC
    PUSH HL
    CALL L_2579
    LD A,$01
    CALL L_2A42
    CALL L_28A9
L_357E:
    POP HL
    POP BC
    XOR A
    LD DE,$365F
L_3584:
    CCF
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    CALL L_28B4
    POP HL
    LD B,$2F
L_3592:
    INC B
    LD A,E
    SUB [HL]
    LD E,A
    INC HL
    LD A,D
    SBC A,[HL]
    LD D,A
    INC HL
    LD A,C
    SBC A,[HL]
    LD C,A
    DEC HL
    DEC HL
    JP NC,L_3592
    CALL L_2642
    INC HL
    CALL L_28A9
    EX DE,HL
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    JP C,L_3584
    INC DE
    INC DE
    LD A,$04
    JP L_35C0
L_35BA:
    PUSH DE
    LD DE,$3665
    LD A,$05
L_35C0:
    CALL L_350E
    PUSH BC
    PUSH AF
    PUSH HL
    EX DE,HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    INC HL
    EX [SP],HL
    EX DE,HL
    LD HL,[D_0C04]
    LD B,$2F
L_35D3:
    INC B
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP NC,L_35D3
    ADD HL,DE
    LD [D_0C04],HL
    POP DE
    POP HL
    LD [HL],B
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,L_35C0
    CALL L_350E
    LD [HL],A
    POP DE
    RET
    .byte $00, $00, $00, $00, $F9, $02, $15, $A2, $E1, $FF, $9F, $31, $A9, $5F, $63, $B2
    .byte $FE, $FF, $03, $BF, $C9, $1B, $0E, $B6, $00, $00, $00, $00, $00, $00, $00, $80
    .byte $00, $00, $04, $BF, $C9, $1B, $0E, $B6, $00, $80, $C6, $A4, $7E, $8D, $03, $00
    .byte $40, $7A, $10, $F3, $5A, $00, $00, $A0, $72, $4E, $18, $09, $00, $00, $10, $A5
    .byte $D4, $E8, $00, $00, $00, $E8, $76, $48, $17, $00, $00, $00, $E4, $0B, $54, $02
    .byte $00, $00, $00, $CA, $9A, $3B, $00, $00, $00, $00, $E1, $F5, $05, $00, $00, $00
    .byte $80, $96, $98, $00, $00, $00, $00, $40, $42, $0F, $00, $00, $00, $00, $A0, $86
    .byte $01, $10, $27, $00, $10, $27, $E8, $03, $64, $00, $0A, $00, $01, $00
L_366F:
    XOR A
    LD B,A
    .byte $C2
L_3672:
    LD B,$01
    PUSH BC
    CALL L_22DB
    POP BC
    LD DE,$0C15
    PUSH DE
    XOR A
    LD [DE],A
    DEC B
    INC B
    LD C,$06
    JP Z,L_368E
    LD C,$04
L_3688:
    ADD HL,HL
    ADC A,A
L_368A:
    ADD HL,HL
    ADC A,A
    ADD HL,HL
    ADC A,A
L_368E:
    ADD HL,HL
    ADC A,A
    OR A
    JP NZ,L_369F
    LD A,C
    DEC A
    JP Z,L_369F
    LD A,[DE]
    OR A
    JP Z,L_36AB
    XOR A
L_369F:
    ADD A,$30
    CP $3A
    JP C,L_36A8
    ADD A,$07
L_36A8:
    LD [DE],A
    INC DE
    LD [DE],A
L_36AB:
    XOR A
    DEC C
    JP Z,L_36B8
    DEC B
    INC B
    JP Z,L_368A
    JP L_3688
L_36B8:
    LD [DE],A
    POP HL
    RET
L_36BB:
    LD HL,$2874
    EX [SP],HL
    JP [HL]
FN_SQR:
    CALL L_2899
    LD HL,$360D
    CALL L_28A6
    JP L_36CF
    .byte $CD, $F4, $29
L_36CF:
    POP BC
    POP DE
    LD HL,$2572
    PUSH HL
    LD A,$01
    LD [D_0C09],A
    CALL L_2845
    LD A,B
    JP Z,FN_EXP
    JP P,L_36E8
    OR A
    JP Z,L_3097
L_36E8:
    OR A
    JP Z,L_25F0
    PUSH DE
    PUSH BC
    LD A,C
    OR $7F
    CALL L_28B4
    JP P,L_3713
    PUSH AF
    LD A,[D_0C07]
    CP $99
    JP C,L_3704
    POP AF
    JP L_3713
L_3704:
    POP AF
    PUSH DE
    PUSH BC
    CALL L_2A8D
    POP BC
    POP DE
    PUSH AF
    CALL L_2906
    POP HL
    LD A,H
    RRA
L_3713:
    POP HL
    LD [D_0C06],HL
    POP HL
    LD [D_0C04],HL
    CALL C,L_36BB
    CALL Z,L_2874
    PUSH DE
    PUSH BC
    CALL FN_LOG
    POP BC
    POP DE
    CALL L_2703
FN_EXP:
    LD BC,$8138
    LD DE,$AA3B
    CALL L_2703
    LD A,[D_0C07]
    CP $88
    JP NC,L_3760
    CP $68
    JP C,L_3772
    CALL L_2899
    CALL L_2A8D
    ADD A,$81
    POP BC
    POP DE
    JP Z,L_3763
    PUSH AF
    CALL L_2585
    LD HL,$377B
    CALL L_37A7
    POP BC
    LD DE,$0000
    LD C,D
    JP L_2703
L_3760:
    CALL L_2899
L_3763:
    LD A,[D_0C06]
    OR A
    JP P,L_376F
    POP AF
    POP AF
    JP L_25EF
L_376F:
    JP L_307E
L_3772:
    LD BC,$8100
    LD DE,$0000
    JP L_28A9
    .byte $07, $7C, $88, $59, $74, $E0, $97, $26, $77, $C4, $1D, $1E, $7A, $5E, $50, $63
    .byte $7C, $1A, $FE, $75, $7E, $18, $72, $31, $80, $00, $00, $00, $81
L_3798:
    CALL L_2899
    LD DE,$2B95
    PUSH DE
    PUSH HL
    CALL L_28B4
    CALL L_2703
    POP HL
L_37A7:
    CALL L_2899
    LD A,[HL]
    INC HL
    CALL L_28A6
    .byte $06
L_37B0:
    .byte $F1
    POP BC
    POP DE
    DEC A
    RET Z
    PUSH DE
    PUSH BC
    PUSH AF
    PUSH HL
    CALL L_2703
    POP HL
    CALL L_28B7
    PUSH HL
    CALL L_2588
    POP HL
    JP L_37B0
    .byte $52, $C7, $4F, $80
L_37CC:
    CALL CHRGTR
L_37CF:
    PUSH HL
    LD HL,$2697
    CALL L_28A6
    CALL FN_RND
    POP HL
    JP L_2A36
FN_RND:
    CALL L_2845
    LD HL,$3848
    JP M,L_383E
    LD HL,$3869
    CALL L_28A6
    LD HL,$3848
    RET Z
    ADD A,[HL]
    AND $07
    LD B,$00
    LD [HL],A
    INC HL
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL L_28B7
    CALL L_2703
    LD A,[D_3847]
    INC A
    AND $03
    LD B,$00
    CP $01
    ADC A,B
    LD [D_3847],A
    LD HL,$3869
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL L_257C
L_3819:
    CALL L_28B4
    LD A,E
    LD E,C
    XOR $4F
    LD C,A
    LD [HL],$80
    DEC HL
    LD B,[HL]
    LD [HL],$80
    LD HL,$3846
    INC [HL]
    LD A,[HL]
    SUB $AB
    JP NZ,L_3835
    LD [HL],A
    INC C
    DEC D
    INC E
L_3835:
    CALL L_25DA
    LD HL,$3869
    JP L_28C0
L_383E:
    LD [HL],A
    DEC HL
    LD [HL],A
    DEC HL
    LD [HL],A
    JP L_3819
    .byte $00
D_3847:
    .byte $00, $00, $35, $4A, $CA, $99, $39, $1C, $76, $98, $22, $95, $B3, $98, $0A, $DD
    .byte $47, $98, $53, $D1, $99, $99, $0A, $1A, $9F, $98, $65, $BC, $CD, $98, $D6, $77
    .byte $3E, $98, $52
D_386A:
    .byte $C7, $4F, $80, $68, $B1, $46, $68, $99, $E9, $92, $69, $10, $D1, $75, $68
FN_COS:
    LD HL,$38FF
    CALL L_257C
FN_SIN:
    LD A,[D_0C07]
    CP $77
    RET C
    LD A,[D_0C06]
    OR A
    JP P,L_3895
    AND $7F
    LD [D_0C06],A
    LD DE,$2874
    PUSH DE
L_3895:
    LD BC,$7E22
    LD DE,$F983
    CALL L_2703
    CALL L_2899
    CALL L_2A8D
    POP BC
    POP DE
    CALL L_2585
    LD BC,$7F00
    LD DE,$0000
    CALL L_2906
    JP M,L_38D9
    LD BC,$7F80
    LD DE,$0000
    CALL L_2588
    LD BC,$8080
    LD DE,$0000
    CALL L_2588
    CALL L_2845
    CALL P,L_2874
    LD BC,$7F00
    LD DE,$0000
    CALL L_2588
    CALL L_2874
L_38D9:
    LD A,[D_0C06]
    OR A
    PUSH AF
    JP P,L_38E6
    XOR $80
    LD [D_0C06],A
L_38E6:
    LD HL,$3907
    CALL L_3798
    POP AF
    RET P
    LD A,[D_0C06]
    XOR $80
    LD [D_0C06],A
    RET
    .byte $00, $00, $00, $00, $83, $F9, $22, $7E, $DB, $0F, $49, $81, $00, $00, $00, $7F
    .byte $05, $FB, $D7, $1E, $86, $65, $26, $99, $87, $58, $34, $23, $87, $E1, $5D, $A5
    .byte $86, $DB, $0F, $49, $83
FN_TAN:
    CALL L_2899
    CALL FN_SIN
    POP BC
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_28A9
    CALL FN_COS
    JP L_2767
FN_ATN:
    CALL L_2845
    CALL M,L_36BB
    CALL M,L_2874
    LD A,[D_0C07]
    CP $81
    JP C,L_394E
    LD BC,$8100
    LD D,C
    LD E,C
    CALL L_2769
    LD HL,$2582
    PUSH HL
L_394E:
    LD HL,$3958
    CALL L_3798
    LD HL,$38FF
    RET
    .byte $09, $4A, $D7, $3B, $78, $02, $6E, $84, $7B, $FE, $C1, $2F, $7C, $74, $31, $9A
    .byte $7D, $84, $3D, $5A, $7D, $C8, $7F, $91, $7E, $E4, $BB, $4C, $7E, $6C, $AA, $AA
    .byte $7F, $00, $00, $00, $81, $2B, $CD, $05, $13, $C8, $CD, $D3, $43, $2C
