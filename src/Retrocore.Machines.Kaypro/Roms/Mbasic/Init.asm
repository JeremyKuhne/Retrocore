;; MBASIC 5.21: INITIALIZATION
;;
;; Part of Mbasic.asm.

D_5D6F:
    .byte $00, $00
D_5D71:
    .byte $00, $00
D_5D73:
    .byte $00, $00
D_5D75:
    .byte $00
L_5D76:
    CALL L_430A
    LD HL,[TXTTAB]
    DEC HL
    LD [HL],$00
    LD HL,[TEMP8]
    LD A,[HL]
    OR A
    JP NZ,L_529A
    JP READY
    .byte $00, $00
L_5D8C:
    LD HL,$603F
    LD SP,HL
    XOR A
    LD [D_0BEC],A
    LD [TOPMEM],HL
    LD SP,HL
    LD HL,$0822
    LD [HL],$3A
    CALL L_4397
    LD [D_0A65],A
    LD [SAVSTK],HL
    LD HL,[D_0001]
    LD BC,$0004
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_427A],HL
    LD [D_4255],HL
    LD [D_12A2],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_41F9],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_41B8],HL
    EX DE,HL
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [D_413D],HL
    LD C,$0C
    CALL L_0005
    LD [D_081F],A
    OR A
    LD HL,$1514
    JP Z,L_5DEA
    LD HL,$2221
L_5DEA:
    LD [D_0820],HL
    LD HL,$FFFE
    LD [CURLIN],HL
    XOR A
    LD [D_0793],A
    LD [D_0A64],A
    LD [D_0BF3],A
    LD [D_0BED],A
    LD [D_078A],A
    LD HL,$0000
    LD [D_078C],HL
    LD HL,$0080
    LD [D_0BEA],HL
    LD HL,$0A7A
    LD [TEMPPT],HL
    LD HL,$0AE4
    LD [D_0B4C],HL
    LD HL,[D_0006]
    LD [MEMSIZ],HL
    LD A,$03
    LD [D_07C4],A
    LD HL,$5ED4
    LD [TEMP8],HL
    LD A,[D_5ED5]
    OR A
    JP NZ,L_5ED6
    INC A
    LD [D_5ED5],A
    LD HL,$0080
    LD A,[HL]
    OR A
    LD [TEMP8],HL
    JP Z,L_5ED6
    LD B,[HL]
    INC HL
L_5E44:
    LD A,[HL]
    DEC HL
    LD [HL],A
    INC HL
    INC HL
    DEC B
    JP NZ,L_5E44
    DEC HL
    LD [HL],$00
    LD [TEMP8],HL
    LD HL,$007F
    CALL CHRGTR
    OR A
    JP Z,L_5ED6
    CP $2F
    JP Z,L_5E78
    DEC HL
    LD [HL],$22
    LD [TEMP8],HL
    INC HL
L_5E69:
    CP $2F
    JP Z,L_5E78
    CALL CHRGTR
    OR A
    JP NZ,L_5E69
    JP L_5ED6
L_5E78:
    LD [HL],$00
    CALL CHRGTR
L_5E7D:
    CALL L_1C5A
    CP $53
    JP Z,L_5EC2
    CP $4D
    PUSH AF
    JP Z,L_5E90
    CP $46
    JP NZ,SNERR
L_5E90:
    CALL CHRGTR
    CALL L_43D3
    LD A,[D_64CD]
    INC E
    POP AF
    JP Z,L_5EAF
    LD A,D
    OR A
    JP NZ,L_1418
    LD A,E
    CP $10
    JP NC,L_1418
    LD [D_07C4],A
    JP L_5EB4
L_5EAF:
    EX DE,HL
    LD [MEMSIZ],HL
    EX DE,HL
L_5EB4:
    DEC HL
    CALL CHRGTR
    JP Z,L_5ED6
    CALL L_43D3
    CPL
    JP L_5E7D
L_5EC2:
    CALL CHRGTR
    CALL L_43D3
    LD A,[D_64CD]
    INC E
    EX DE,HL
    LD [D_0BEA],HL
    EX DE,HL
    JP L_5EB4
    .byte $00
D_5ED5:
    .byte $00
L_5ED6:
    DEC HL
    LD HL,[MEMSIZ]
    DEC HL
    LD [MEMSIZ],HL
    DEC HL
    PUSH HL
    LD A,[D_07C4]
    LD HL,$5D8A
    LD [D_07A2],HL
    LD DE,$07A4
    LD [D_07C4],A
    INC A
    LD BC,$00A9
L_5EF3:
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    EX DE,HL
    ADD HL,BC
    PUSH HL
    LD HL,[D_0BEA]
    LD BC,$00B2
    ADD HL,BC
    LD B,H
    LD C,L
    POP HL
    DEC A
    JP NZ,L_5EF3
    INC HL
    LD [TXTTAB],HL
    LD [SAVSTK],HL
    POP DE
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A
    JP C,L_42DD
    LD B,$03
L_5F1C:
    OR A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    DEC B
    JP NZ,L_5F1C
    LD A,H
    CP $02
    JP C,L_5F30
    LD HL,$0200
L_5F30:
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A
    JP C,L_42DD
    LD [MEMSIZ],HL
    EX DE,HL
    LD [TOPMEM],HL
    LD [FRETOP],HL
    LD SP,HL
    LD [SAVSTK],HL
    LD HL,[TXTTAB]
    EX DE,HL
    CALL L_42EB
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    DEC HL
    DEC HL
    PUSH HL
    LD HL,$5F9A
    CALL L_4723
    POP HL
    CALL LINPRT
    LD HL,$5F8E
    CALL L_4723
    LD HL,$4723
    LD [D_0D98],HL
    CALL L_4221
    LD HL,$0C7F
    JP L_5D76
    .byte $0D, $0A, $0A, $4F, $77, $6E, $65, $64, $20, $62, $79, $20, $4D, $69, $63, $72
    .byte $6F, $73, $6F, $66, $74, $0D, $0A, $00, $20, $42, $79, $74, $65, $73, $20, $66
    .byte $72, $65, $65, $00, $42, $41, $53, $49, $43, $2D, $38, $30, $20, $52, $65, $76
    .byte $2E, $20, $35, $2E, $32, $31, $0D, $0A, $5B, $43, $50, $2F, $4D, $20, $56, $65
    .byte $72, $73, $69, $6F, $6E, $5D, $0D, $0A, $43, $6F, $70, $79, $72, $69, $67, $68
    .byte $74, $20, $31, $39, $37, $37, $2D, $31, $39, $38, $31, $20, $28, $43, $29, $20
    .byte $62, $79, $20, $4D, $69, $63, $72, $6F, $73, $6F, $66, $74, $0D, $0A, $43, $72
    .byte $65, $61, $74, $65, $64, $3A, $20, $32, $38, $2D, $4A, $75, $6C, $2D, $38, $31
    .byte $0D, $0A, $00, $00, $00, $00, $00, $00, $00, $00
