;; MBASIC 5.21: MATH PACKAGE, PART 2
;;
;; Part of Mbasic.asm.

FN_FIX:
    CALL L_1D64
    RET M
    CALL L_2845
    JP P,FN_INT
    CALL L_2874
    CALL FN_INT
    JP L_286B
FN_INT:
    CALL L_1D64
    RET M
    JP NC,L_2AA6
    JP Z,TMERR
    CALL L_29CF
L_2A8D:
    LD HL,$0C07
    LD A,[HL]
    CP $98
    LD A,[D_0C04]
    RET NC
    LD A,[HL]
    CALL L_2A42
    LD [HL],$98
    LD A,E
    PUSH AF
    LD A,C
    RLA
    CALL L_25D7
    POP AF
    RET
L_2AA6:
    LD HL,$0C07
    LD A,[HL]
    CP $90
    JP NZ,L_2ACA
    LD C,A
    DEC HL
    LD A,[HL]
    XOR $80
    LD B,$06
L_2AB6:
    DEC HL
    OR [HL]
    DEC B
    JP NZ,L_2AB6
    OR A
    LD HL,$8000
    JP NZ,L_2AC9
    CALL L_29DC
    JP FN_CDBL
L_2AC9:
    LD A,C
L_2ACA:
    OR A
    RET Z
    CP $B8
    RET NC
L_2ACF:
    PUSH AF
    CALL L_28B4
    CALL L_28D6
    XOR [HL]
    DEC HL
    LD [HL],$B8
    PUSH AF
    DEC HL
    LD [HL],C
    CALL M,L_2AFA
    LD A,[D_0C06]
    LD C,A
    LD HL,$0C06
    LD A,$B8
    SUB B
    CALL L_2D25
    POP AF
    CALL M,L_2CDD
    XOR A
    LD [D_0BFF],A
    POP AF
    RET NC
    JP L_2C91
L_2AFA:
    LD HL,$0C00
L_2AFD:
    LD A,[HL]
    DEC [HL]
    OR A
    INC HL
    JP Z,L_2AFD
    RET
L_2B05:
    PUSH HL
    LD HL,$0000
    LD A,B
    OR C
    JP Z,L_2B22
    LD A,$10
L_2B10:
    ADD HL,HL
    JP C,L_3BD6
    EX DE,HL
    ADD HL,HL
    EX DE,HL
    JP NC,L_2B1E
    ADD HL,BC
    JP C,L_3BD6
L_2B1E:
    DEC A
    JP NZ,L_2B10
L_2B22:
    EX DE,HL
    POP HL
    RET
    .byte $7C, $17, $9F, $47, $CD, $EE, $2B, $79, $98, $C3, $34, $2B
L_2B31:
    LD A,H
    RLA
    SBC A,A
    LD B,A
    PUSH HL
    LD A,D
    RLA
    SBC A,A
    ADD HL,DE
    ADC A,B
    RRCA
    XOR H
    JP P,L_29DB
    PUSH BC
    EX DE,HL
    CALL L_2A14
    POP AF
    POP HL
    CALL L_2899
    EX DE,HL
    CALL L_2C08
    JP L_304E
    .byte $7C, $B5, $CA, $DC, $29, $E5, $D5, $CD, $E2, $2B, $C5, $44, $4D, $21, $00, $00
    .byte $3E, $10, $29, $DA, $89, $2B, $EB, $29, $EB, $D2, $71, $2B, $09, $DA, $89, $2B
    .byte $3D, $C2, $63, $2B, $C1, $D1
L_2B77:
    LD A,H
    OR A
    JP M,L_2B81
    POP DE
    LD A,B
    JP L_2BEA
L_2B81:
    XOR $80
    OR L
    JP Z,L_2B9A
    EX DE,HL
    LD BC,$E1C1
    CALL L_2A14
    POP HL
    CALL L_2899
    CALL L_2A14
    POP BC
    POP DE
    JP L_2703
L_2B9A:
    LD A,B
    OR A
    POP BC
    JP M,L_29DC
    PUSH DE
    CALL L_2A14
    POP DE
    JP L_2874
L_2BA8:
    LD A,H
    OR L
    JP Z,DV0ERR
    CALL L_2BE2
    PUSH BC
    EX DE,HL
    CALL L_2BEE
    LD B,H
    LD C,L
    LD HL,$0000
    LD A,$11
    PUSH AF
    OR A
    JP L_2BCB
L_2BC1:
    PUSH AF
    PUSH HL
    ADD HL,BC
    JP NC,L_2BCA
    POP AF
    SCF
    .byte $3E
L_2BCA:
    .byte $E1
L_2BCB:
    LD A,E
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,L
    RLA
    LD L,A
    LD A,H
    RLA
    LD H,A
    POP AF
    DEC A
    JP NZ,L_2BC1
    EX DE,HL
    POP BC
    PUSH DE
    JP L_2B77
L_2BE2:
    LD A,H
    XOR D
    LD B,A
    CALL L_2BE9
    EX DE,HL
L_2BE9:
    LD A,H
L_2BEA:
    OR A
    JP P,L_29DC
L_2BEE:
    XOR A
    LD C,A
    SUB L
    LD L,A
    LD A,C
    SBC A,H
    LD H,A
    JP L_29DC
L_2BF8:
    LD HL,[D_0C04]
    CALL L_2BEE
    LD A,H
    XOR $80
    OR L
    RET NZ
L_2C03:
    EX DE,HL
    CALL L_2A36
    XOR A
L_2C08:
    LD B,$98
    JP L_2859
L_2C0D:
    PUSH DE
    CALL L_2BA8
    XOR A
    ADD A,D
    RRA
    LD H,A
    LD A,E
    RRA
    LD L,A
    CALL L_29DF
    POP AF
    JP L_2BEA
    .byte $21, $13, $0C, $7E, $EE, $80, $77
L_2C26:
    LD HL,$0C14
    LD A,[HL]
    OR A
    RET Z
    LD B,A
    DEC HL
    LD C,[HL]
    LD DE,$0C07
    LD A,[DE]
    OR A
    JP Z,L_28EB
    SUB B
    JP NC,L_2C52
    CPL
    INC A
    PUSH AF
    LD C,$08
    INC HL
    PUSH HL
L_2C42:
    LD A,[DE]
    LD B,[HL]
    LD [HL],A
    LD A,B
    LD [DE],A
    DEC DE
    DEC HL
    DEC C
    JP NZ,L_2C42
    POP HL
    LD B,[HL]
    DEC HL
    LD C,[HL]
    POP AF
L_2C52:
    CP $39
    RET NC
    PUSH AF
    CALL L_28D6
    LD HL,$0C0C
    LD B,A
    LD A,$00
    LD [HL],A
    LD [D_0BFF],A
    POP AF
    LD HL,$0C13
    CALL L_2D25
    LD A,B
    OR A
    JP P,L_2C86
    LD A,[D_0C0C]
    LD [D_0BFF],A
    CALL L_2CFA
    JP NC,L_2CCB
    EX DE,HL
    INC [HL]
    JP Z,L_3088
    CALL L_2D51
    JP L_2CCB
L_2C86:
    LD A,$9E
    CALL L_2CFC
    LD HL,$0C08
    CALL C,L_2D12
L_2C91:
    XOR A
L_2C92:
    LD B,A
    LD A,[D_0C06]
    OR A
    JP NZ,L_2CBA
    LD HL,$0BFF
    LD C,$08
L_2C9F:
    LD D,[HL]
    LD [HL],A
    LD A,D
    INC HL
    DEC C
    JP NZ,L_2C9F
    LD A,B
    SUB $08
    CP $C0
    JP NZ,L_2C92
    JP L_25EF
L_2CB2:
    DEC B
    LD HL,$0BFF
    CALL L_2D59
    OR A
L_2CBA:
    JP P,L_2CB2
    LD A,B
    OR A
    JP Z,L_2CCB
    LD HL,$0C07
    ADD A,[HL]
    LD [HL],A
    JP NC,L_25EF
    RET Z
L_2CCB:
    LD A,[D_0BFF]
    OR A
    CALL M,L_2CDD
    LD HL,$0C08
    LD A,[HL]
    AND $80
    DEC HL
    DEC HL
    XOR [HL]
    LD [HL],A
    RET
L_2CDD:
    LD HL,$0C00
    LD B,$07
L_2CE2:
    INC [HL]
    RET NZ
    INC HL
    DEC B
    JP NZ,L_2CE2
    INC [HL]
    JP Z,L_3088
    DEC HL
    LD [HL],$80
    RET
    .byte $11, $30, $0C, $21, $0D, $0C, $C3, $02, $2D
L_2CFA:
    LD A,$8E
L_2CFC:
    LD HL,$0C0D
L_2CFF:
    LD DE,$0C00
    LD C,$07
    LD [D_2D09],A
    XOR A
L_2D08:
    LD A,[DE]
D_2D09:
    ADC A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JP NZ,L_2D08
    RET
L_2D12:
    LD A,[HL]
    CPL
    LD [HL],A
    LD HL,$0BFF
    LD B,$08
    XOR A
    LD C,A
L_2D1C:
    LD A,C
    SBC A,[HL]
    LD [HL],A
    INC HL
    DEC B
    JP NZ,L_2D1C
    RET
L_2D25:
    LD [HL],C
    PUSH HL
L_2D27:
    SUB $08
    JP C,L_2D3C
    POP HL
L_2D2D:
    PUSH HL
    LD DE,$0800
L_2D31:
    LD C,[HL]
    LD [HL],E
    LD E,C
    DEC HL
    DEC D
    JP NZ,L_2D31
    JP L_2D27
L_2D3C:
    ADD A,$09
    LD D,A
L_2D3F:
    XOR A
    POP HL
    DEC D
    RET Z
L_2D43:
    PUSH HL
    LD E,$08
L_2D46:
    LD A,[HL]
    RRA
    LD [HL],A
    DEC HL
    DEC E
    JP NZ,L_2D46
    JP L_2D3F
L_2D51:
    LD HL,$0C06
    LD D,$01
    JP L_2D43
L_2D59:
    LD C,$08
L_2D5B:
    LD A,[HL]
    RLA
    LD [HL],A
    INC HL
    DEC C
    JP NZ,L_2D5B
    RET
L_2D64:
    CALL L_2845
    RET Z
    LD A,[D_0C14]
    OR A
    JP Z,L_25EF
    CALL L_27F9
    CALL L_2E9D
    LD [HL],C
    INC DE
    LD B,$07
L_2D79:
    LD A,[DE]
    INC DE
    OR A
    PUSH DE
    JP Z,L_2D99
    LD C,$08
L_2D82:
    PUSH BC
    RRA
    LD B,A
    CALL C,L_2CFA
    CALL L_2D51
    LD A,B
    POP BC
    DEC C
    JP NZ,L_2D82
L_2D91:
    POP DE
    DEC B
    JP NZ,L_2D79
    JP L_2C91
L_2D99:
    LD HL,$0C06
    CALL L_2D2D
    JP L_2D91
    .byte $CD, $CC, $CC, $CC, $CC, $CC, $4C, $7D, $00, $00, $00, $00, $00, $00, $20, $84
L_2DB2:
    LD A,[D_0C07]
    CP $41
    JP NC,L_2DC6
    LD DE,$2DA2
    LD HL,$0C0D
    CALL L_28C9
    JP L_2D64
L_2DC6:
    LD A,[D_0C06]
    OR A
    JP P,L_2DD6
    AND $7F
    LD [D_0C06],A
    LD HL,$2874
    PUSH HL
L_2DD6:
    CALL L_2E0E
    LD DE,$0C00
    LD HL,$0C0D
    CALL L_28C9
    CALL L_2E0E
    CALL L_2C26
    LD DE,$0C00
    LD HL,$0C0D
    CALL L_28C9
    LD A,$0F
L_2DF3:
    PUSH AF
    CALL L_2E16
    CALL L_2E22
    CALL L_2C26
    LD HL,$0C13
    CALL L_2E33
    POP AF
    DEC A
    JP NZ,L_2DF3
    CALL L_2E0E
    CALL L_2E0E
L_2E0E:
    LD HL,$0C07
    DEC [HL]
    RET NZ
    JP L_25EF
L_2E16:
    LD HL,$0C14
    LD A,$04
L_2E1B:
    DEC [HL]
    RET Z
    DEC A
    JP NZ,L_2E1B
    RET
L_2E22:
    POP DE
    LD A,$04
    LD HL,$0C0D
L_2E28:
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,L_2E28
    PUSH DE
    RET
L_2E33:
    POP DE
    LD A,$04
    LD HL,$0C14
L_2E39:
    POP BC
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    DEC A
    JP NZ,L_2E39
    PUSH DE
    RET
    .byte $3A, $14, $0C, $B7, $CA, $94, $30, $3A, $07, $0C, $B7, $CA, $EF, $25, $CD, $F6
    .byte $27, $34, $34, $CA, $88, $30, $CD, $9D, $2E, $21, $37, $0C, $71, $41, $3E, $9E
    .byte $CD, $F1, $2C, $1A, $99, $3F, $DA, $74, $2E, $3E, $8E, $CD, $F1, $2C, $AF, $DA
    .byte $12, $04, $3A, $06, $0C, $3C, $3D, $1F, $FA, $CE, $2C, $17, $21, $00, $0C, $0E
    .byte $07, $CD, $5B, $2D, $21, $30, $0C, $CD, $59, $2D, $78, $B7, $C2, $62, $2E, $21
    .byte $07, $0C, $35, $C2, $62, $2E, $C3, $EF, $25
L_2E9D:
    LD A,C
    LD [D_0C13],A
    DEC HL
    LD DE,$0C36
    LD BC,$0700
L_2EA8:
    LD A,[HL]
    LD [DE],A
    LD [HL],C
    DEC DE
    DEC HL
    DEC B
    JP NZ,L_2EA8
    RET
L_2EB2:
    CALL L_28F4
    EX DE,HL
    DEC HL
    LD A,[HL]
    OR A
    RET Z
    ADD A,$02
    JP C,L_3088
    LD [HL],A
    PUSH HL
    CALL L_2C26
    POP HL
    INC [HL]
    RET NZ
    JP L_3088
L_2ECA:
    CALL L_25EF
    CALL L_2A33
    .byte $F6
L_2ED1:
    .byte $AF
    LD BC,$256A
    PUSH BC
    PUSH AF
    LD A,$01
    LD [D_0C09],A
    POP AF
    EX DE,HL
    LD BC,$00FF
    LD H,B
    LD L,B
    CALL Z,L_29DC
    EX DE,HL
    LD A,[HL]
    CP $26
    JP Z,L_1C69
    CP $2D
    PUSH AF
    JP Z,L_2EF9
    CP $2B
    JP Z,L_2EF9
    DEC HL
L_2EF9:
    CALL CHRGTR
    JP C,L_2FE0
    CP $2E
    JP Z,L_2F86
    CP $65
    JP Z,L_2F0B
    CP $45
L_2F0B:
    JP NZ,L_2F35
    PUSH HL
    CALL CHRGTR
    CP $6C
    JP Z,L_2F23
    CP $4C
    JP Z,L_2F23
    CP $71
    JP Z,L_2F23
    CP $51
L_2F23:
    POP HL
    JP Z,L_2F34
    LD A,[D_0A67]
    CP $08
    JP Z,L_2F4E
    LD A,$00
    JP L_2F4E
L_2F34:
    LD A,[HL]
L_2F35:
    CP $25
    JP Z,L_2F93
    CP $23
    JP Z,L_2FA4
    CP $21
    JP Z,L_2FA5
    CP $64
    JP Z,L_2F4E
    CP $44
    JP NZ,L_2F65
L_2F4E:
    OR A
    CALL L_2FAE
    CALL CHRGTR
    CALL L_1D32
L_2F58:
    CALL CHRGTR
    JP C,L_3053
    INC D
    JP NZ,L_2F65
    XOR A
    SUB E
    LD E,A
L_2F65:
    PUSH HL
    LD A,E
    SUB B
    LD E,A
L_2F69:
    CALL P,L_2FBD
    CALL M,L_2FCD
    JP NZ,L_2F69
    POP HL
    POP AF
    PUSH HL
    CALL Z,L_286B
    POP HL
    CALL L_1D64
    RET PE
    PUSH HL
    LD HL,$2757
    PUSH HL
    CALL L_29E5
    RET
L_2F86:
    CALL L_1D64
    INC C
    JP NZ,L_2F65
    CALL C,L_2FAE
    JP L_2EF9
L_2F93:
    CALL CHRGTR
    POP AF
    PUSH HL
    LD HL,$2757
    PUSH HL
    LD HL,$297A
    PUSH HL
    PUSH AF
    JP L_2F65
L_2FA4:
    OR A
L_2FA5:
    CALL L_2FAE
    CALL CHRGTR
    JP L_2F65
L_2FAE:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    CALL Z,FN_CSNG
    POP AF
    CALL NZ,FN_CDBL
    POP BC
    POP DE
    POP HL
    RET
L_2FBD:
    RET Z
L_2FBE:
    PUSH AF
    CALL L_1D64
    PUSH AF
    CALL PO,L_282E
    POP AF
    CALL PE,L_2EB2
    POP AF
L_2FCB:
    DEC A
    RET
L_2FCD:
    PUSH DE
    PUSH HL
    PUSH AF
    CALL L_1D64
    PUSH AF
    CALL PO,L_275E
    POP AF
    CALL PE,L_2DB2
    POP AF
    POP HL
    POP DE
    INC A
    RET
L_2FE0:
    PUSH DE
    LD A,B
    ADC A,C
    LD B,A
    PUSH BC
    PUSH HL
    LD A,[HL]
    SUB $30
    PUSH AF
    CALL L_1D64
    JP P,L_3019
    LD HL,[D_0C04]
    LD DE,$0CCD
    CALL L_43CD
    JP NC,L_3015
    LD D,H
    LD E,L
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    POP AF
    LD C,A
    ADD HL,BC
    LD A,H
    OR A
    JP M,L_3013
    LD [D_0C04],HL
L_300D:
    POP HL
    POP BC
    POP DE
    JP L_2EF9
L_3013:
    LD A,C
    PUSH AF
L_3015:
    CALL L_2A11
    SCF
L_3019:
    JP NC,L_3035
    LD BC,$9474
    LD DE,$2400
    CALL L_2906
    JP P,L_3032
    CALL L_282E
    POP AF
    CALL L_3048
    JP L_300D
L_3032:
    CALL L_2A2A
L_3035:
    CALL L_2EB2
    CALL L_28F4
    POP AF
    CALL L_2854
    CALL L_2A2A
    CALL L_2C26
    JP L_300D
L_3048:
    CALL L_2899
    CALL L_2854
L_304E:
    POP BC
    POP DE
    JP L_2588
L_3053:
    LD A,E
    CP $0A
    JP NC,L_3062
    RLCA
    RLCA
    ADD A,E
    RLCA
    ADD A,[HL]
    SUB $30
    LD E,A
    .byte $FA
L_3062:
    .byte $1E, $7F
    JP L_2F58
L_3067:
    PUSH HL
    LD HL,$0C06
    CALL L_1D64
    JP PO,L_3077
    LD A,[D_0C13]
    JP L_3078
L_3077:
    LD A,C
L_3078:
    XOR [HL]
    RLA
    POP HL
    JP L_309E
L_307E:
    POP AF
    POP AF
L_3080:
    LD A,[D_0C06]
    RLA
    JP L_309E
L_3087:
    POP AF
L_3088:
    LD A,[D_0C08]
    CPL
    RLA
    JP L_309E
L_3090:
    LD A,C
    JP L_3097
    .byte $3A, $13, $0C
L_3097:
    RLA
    LD HL,$0562
    LD [D_079C],HL
L_309E:
    PUSH HL
    PUSH BC
    PUSH DE
    PUSH AF
    PUSH AF
    LD HL,[ONELIN]
    LD A,H
    OR L
    JP NZ,L_30CB
    LD HL,$0C09
    LD A,[HL]
    OR A
    JP Z,L_30B8
    DEC A
    JP NZ,L_30CB
    INC [HL]
L_30B8:
    LD HL,[D_079C]
    CALL L_2479
    LD [D_0A65],A
    LD A,$0D
    CALL L_2483
    LD A,$0A
    CALL L_2483
L_30CB:
    POP AF
    LD HL,$0C04
    LD DE,$310A
    JP NC,L_30D8
    LD DE,$310E
L_30D8:
    CALL L_28C3
    CALL L_1D64
    JP C,L_30EA
    LD HL,$0C00
    LD DE,$310E
    CALL L_28C3
L_30EA:
    LD HL,[ONELIN]
    LD A,H
    OR L
    LD HL,[D_079C]
    LD DE,$0509
    EX DE,HL
    LD [D_079C],HL
    JP Z,L_3105
    CALL L_43CD
    JP Z,OVERR
    JP DV0ERR
L_3105:
    POP AF
    POP DE
    POP BC
    POP HL
    RET
    .byte $FF, $FF, $7F, $FF, $FF, $FF, $FF, $FF
L_3112:
    PUSH HL
    LD HL,$0C40
    CALL L_4723
    POP HL
