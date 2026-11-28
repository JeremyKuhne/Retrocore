;; MODEL 100 ROM: THE MODEL 100'S OWN STATEMENTS: TIME$, DATE$, DAY$, IPL, COM, MDM, KEY, PSET, PRESET, SOUND, MOTOR, CALL, SCREEN, LCOPY, FILES, KILL, NAME AND NEW
;;
;; Runs at $19AB-$220E. Model100.asm describes the ROM as a whole and how it is named.

ST_TIME:
    CPI $DD
    JNZ L_1AA5
    CALL L_1A42

L_19B3:
    LXI H,$F923
    DI
    CALL L_732A
    EI
    POP H
    RET

ST_DATE:
    CALL L_1A2C
    JNZ SNERR
    CALL GETBYT
    DCR A
    CPI $0C
    JNC SNERR
    INR A
    LXI D,$F92C
    STAX D
    RST 1
    .byte $2F                           ; SYNCHR: '/'
    DCX D
    CALL L_1A6A
    CPI $04
    JNC SNERR
    CALL L_1A6A
    RST 1
    .byte $2F                           ; SYNCHR: '/'
    LXI D,$F92F
    CALL L_1A6A
    CALL L_1A6A
    XRA A
    STA D_F655
    JMP L_19B3

ST_DAY:
    CALL L_1A2C
    CPI $03
    JNZ SNERR
    LXI D,D_1978
    MVI C,$07

L_19FE:
    PUSH H
    MVI B,$03

L_1A01:
    LDAX D
    PUSH D
    CALL MAKUPS
    MOV E,A
    CALL MAKUPL
    CMP E
    POP D
    JNZ L_1A1F
    INX D
    INX H
    DCR B
    JNZ L_1A01
    POP H
    MVI A,$07
    SUB C
    STA D_F92B
    JMP L_19B3

L_1A1F:
    INX D
    DCR B
    JNZ L_1A1F
    POP H
    DCR C
    JNZ L_19FE
    JMP SNERR

L_1A2C:
    RST 1
    .byte $DD                           ; SYNCHR: the = token

L_1A2E:
    CALL FRMEVL
    XTHL
    PUSH H
    CALL L_19A0
    CALL FRESTR
    MOV A,M
    INX H
    MOV E,M
    INX H
    MOV H,M
    MOV L,E
    CPI $08
    RET

L_1A42:
    CALL L_1A2C
    JNZ SNERR
    XCHG
    POP H
    XTHL
    PUSH H
    XCHG
    LXI D,$F929
    CALL L_1A6A
    CPI $03
    JNC SNERR
    CALL L_1A6A
    RST 1
    .byte $3A                           ; SYNCHR: ':'
    CALL L_1A62
    RST 1
    .byte $3A                           ; SYNCHR: ':'

L_1A62:
    CALL L_1A6A
    CPI $06
    JNC SNERR

L_1A6A:
    DCX D
    MOV A,M
    INX H
    SUI $30
    CPI $0A
    JNC SNERR
    ANI $0F
    STAX D
    RET

ST_IPL:
    JZ L_1A96
    CALL L_1A2E
    ANA A
    JZ L_1A95
    CPI $0A
    JNC FCERR
    MOV B,A
    XCHG
    LXI H,$FAAF
    CALL L_3469
    MVI M,$0D
    INX H
    MOV M,B
    POP H
    RET

L_1A95:
    POP H

L_1A96:
    XRA A
    STA D_FAAF
    STA D_FAB0
    RET

ST_COM:
    PUSH H
    LXI H,$F944
    JMP L_1AA9

L_1AA5:
    PUSH H
    LXI H,$F947

L_1AA9:
    CALL L_1AEA

L_1AAC:
    POP H
    POP PSW
    RST 2
    JMP L_0811

L_1AB2:
    CALL GETBYT
    DCR A
    CPI $08
    JNC FCERR
    MOV A,M
    PUSH H
    CALL L_1AD4
    JMP L_1AAC

L_1AC3:
    PUSH H
    MVI E,$08

L_1AC6:
    PUSH D
    PUSH PSW
    CALL L_1AD4
    POP PSW
    POP D
    DCR E
    JNZ L_1AC6
    JMP L_1AAC

L_1AD4:
    MVI D,$00
    LXI H,$F62F
    DAD D
    PUSH H
    LXI H,$F947
    DAD D
    DAD D
    DAD D
    CALL L_1AEA
    MOV A,M
    ANI $01
    POP H
    MOV M,A
    RET

L_1AEA:
    CPI $97
    JZ L_3FA0
    CPI $CB
    JZ L_3FB2
    CPI $8F
    JZ L_3FB9
    JMP SNERR

L_1AFC:
    CPI $AD
    LXI B,$0001
    RZ
    CPI $AE
    RZ
    CPI $AF
    LXI B,$0208
    RZ
    CPI $AA
    STC
    RNZ
    INX H
    CALL L_1A42
    .byte $21, $3D

L_1B15:
    SPHL
    MVI B,$06
    CALL L_3469
    POP H
    DCX H
    LXI B,$0101
    ANA A
    RET

L_1B22:
    PUSH H
    MOV B,A
    ADD A
    ADD B
    MOV L,A
    MVI H,$00
    LXI B,$F945
    DAD B
    MOV M,E
    INX H
    MOV M,D
    POP H
    RET

L_1B32:
    CALL D_F5FF
    PUSH H
    PUSH D
    PUSH B
    PUSH PSW
    MVI A,$0D
    SIM
    EI
    LXI H,$F92F
    DCR M
    JNZ L_1BAE
    MVI M,$7D
    INX H
    DCR M
    JNZ L_1B65
    MVI M,$0C
    INX H
    PUSH H
    LHLD CURLIN
    INX H
    MOV A,H
    ORA L
    POP H
    CNZ L_1BB1
    MOV A,M
    ANA A
    JZ L_1B65
    DCR M
    JNZ L_1B65
    INX H
    MVI M,$FF

L_1B65:
    LXI H,$F933
    PUSH H
    CALL L_7329
    POP D
    LXI H,$F93D
    MVI B,$06

L_1B72:
    LDAX D
    SUB M
    JNZ L_1B88
    INX D
    INX H
    DCR B
    JNZ L_1B72
    ORA M
    JNZ L_1B8C
    LXI H,$F947
    CALL L_3FD2
    .byte $3E

L_1B88:
    .byte $AF
    STA D_F943

.if MODEL = 100
L_1B8C:
    LDA D_F93C

L_1B8F:
    LXI H,$F655
    CMP M
    MOV M,A
    JNC L_1BAB
    .byte $21                           ; LXI: skips the next instruction

L_1B98:
    .byte $2D, $F9
    INR M
    MOV A,M
    SUI $0A
    JNZ L_1BAB
    MOV M,A
    INX H
    INR M
    MOV A,M
    SUI $0A

L_1BA7:
    .byte $C2                           ; JNZ: skips the next instruction

L_1BA8:
    .byte $AB, $1B
    MOV M,A
.else
L_1B8C:
    JMP L_1BAB

L_1B8F:
    CALL L_20D5
    RZ
    CPI $F0
    RNZ
    INR A
    RET

L_1B98:
    LHLD CSRY
    SHLD D_F6E7
    LXI H,L_66E6
    SHLD D_F652
    JMP L_659B

L_1BA7:
    XRA A

L_1BA8:
    JMP COLD
.endif

L_1BAB:
    CALL L_7682

L_1BAE:
    JMP L_7391

L_1BB1:
    LDA D_F657
    STA D_F931
    RET

ST_KEY:
    CPI $A5
    JNZ L_1BF6
    RST 2
    PUSH H
    LXI H,$F789
    MVI C,$04

L_1BC4:
    CALL L_1BD3
    CALL L_1BD3
    CALL CRLF
    DCR C
    JNZ L_1BC4
    POP H
    RET

L_1BD3:
    MVI B,$10
    CALL L_1BE0
    MVI B,$03

L_1BDA:
    RST 4
    DCR B
    JNZ L_1BDA
    RET

L_1BE0:
    MOV A,M
    CPI $7F
    JZ L_1BEB
    CPI $20
    JNC L_1BED

L_1BEB:
    MVI A,$20

L_1BED:
    RST 4
    INX H
    DCR B
    JNZ L_1BE0
    MVI A,$20
    RET

L_1BF6:
    CPI $28
    JZ L_1AB2
    CPI $97
    JZ L_1AC3
    CPI $CB
    JZ L_1AC3
    CPI $8F
    JZ L_1AC3
    CALL GETBYT
    DCR A
    CPI $08
    JNC FCERR
    XCHG
    MOV L,A
    MVI H,$00
    DAD H
    DAD H
    DAD H
    DAD H
    LXI B,$F789
    DAD B
    PUSH H
    XCHG
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL FRMEVL
    PUSH H
    CALL FRESTR
    MOV B,M
    INX H
    MOV E,M
    INX H
    MOV D,M
    POP H
    XTHL
    MVI C,$0F
    MOV A,B
    ANA A
    JZ L_1C48

L_1C38:
    LDAX D
    ANA A
    JZ FCERR
    MOV M,A
    INX D
    INX H
    DCR C
    JZ L_1C4E
    DCR B
    JNZ L_1C38

L_1C48:
    MOV M,B
    INX H
    DCR C
    JNZ L_1C48

L_1C4E:
    MOV M,C
    CALL FNKSB
    CALL L_6C93
    POP H
    RET

ST_PSET:
    CALL L_1D2E

L_1C5A:
    RRC
    PUSH H
    PUSH PSW
    CC PLOT
    POP PSW
    CNC UNPLOT
    POP H
    RET

ST_PRESET:
    CALL L_1D2E
    CMA
    JMP L_1C5A

L_1C6D:
    CPI $D1
    XCHG
    LHLD D_F64E
    XCHG
    CNZ L_1D2E
    PUSH D
    RST 1
    .byte $D1                           ; SYNCHR: the - token
    CALL L_1D2E
    PUSH D
    LXI D,PLOT
    JZ L_1C94
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    POP D
    RRC
    JC L_1C92
    LXI D,UNPLOT

L_1C92:
    DCX H
    RST 2

L_1C94:
    XCHG
    SHLD D_F661
    XCHG
    JZ L_1CD2
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $42                           ; SYNCHR: 'B'
    JZ L_1CBC
    RST 1
    .byte $46                           ; SYNCHR: 'F'
    POP D
    XTHL
    MOV A,E
    SUB L
    JNC L_1CAF
    CMA
    INR A
    MOV L,E

L_1CAF:
    MOV B,A
    INR B

L_1CB1:
    MOV E,L
    CALL L_1CD9
    INR L
    DCR B
    JNZ L_1CB1
    POP H
    RET

L_1CBC:
    POP D
    XTHL
    PUSH D
    MOV E,L
    CALL L_1CD9
    POP D
    PUSH D
    MOV D,H
    CALL L_1CD9
    POP D
    PUSH H
    MOV H,D
    CALL L_1CD9
    POP H
    MOV L,E
    .byte $01

L_1CD2:
    .byte $D1, $E3
    CALL L_1CD9
    POP H
    RET

L_1CD9:
    PUSH H
    PUSH D
    PUSH B
    MOV A,L
    SUB E
    JNC L_1CE4
    XCHG
    CMA
    INR A

L_1CE4:
    MOV B,A
    MVI C,$14
    MOV A,H
    SUB D
    JNC L_1CEF
    CMA
    INR A
    INR C

L_1CEF:
    CMP B
    JC L_1CFA
    MOV H,A
    MOV L,B
    MVI A,$1C
    JMP L_1CFF

L_1CFA:
    MOV L,A
    MOV H,B
    MOV A,C
    MVI C,$1C

L_1CFF:
    STA D_F663
    MOV A,C
    STA D_F665
    MOV B,H
    INR B
    MOV A,H
    ANA A
    RAR
    MOV C,A

L_1D0C:
    PUSH H
    PUSH D
    PUSH B
    CALL D_F660
    POP B
    POP D
    POP H
    CALL D_F665
    MOV A,C
    ADD L
    MOV C,A
    JC L_1D22
    CMP H
    JC L_1D27

L_1D22:
    SUB H
    MOV C,A
    CALL D_F663

L_1D27:
    DCR B
    JNZ L_1D0C
    JMP L_14EE

L_1D2E:
    RST 1
    .byte $28                           ; SYNCHR: '('
    CALL GETBYT
    CPI $F0
    JNC FCERR
    PUSH PSW
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    CPI $40
    JNC FCERR
    POP PSW
    MOV D,A
    XCHG
    SHLD D_F64E
    XCHG
    MOV A,M
    CPI $29
    JNZ L_1D54
    RST 2
    MVI A,$01
    RET

L_1D54:
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    RST 1
    .byte $29                           ; SYNCHR: ')'
    MOV A,E
    POP D
    RET

L_1D5F:
    CALL GETINT
    RST 1
    .byte $2C                           ; SYNCHR: ','
    PUSH H
    XCHG
    LDA D_F63C
    CMA
    INR A
    MOV C,A
    MVI B,$FF
    MOV E,B

L_1D6F:
    INR E
    MOV D,L
    DAD B
    JC L_1D6F
    LDA D_F63C
    INR D
    CMP D
    JC FCERR
    LDA D_F63B
    INR E
    CMP E
    JC FCERR
    XCHG
    CALL POSIT
    MOV A,H
    DCR A
    STA TTYPOS
    POP H
    RET

L_1D90:
    PUSH H
    LDA CSRY
    DCR A

L_1D95:
    CALL L_340A
    POP H
    RST 2
    RET

L_1D9B:
    RST 2
    CPI $9D
    JZ L_1DB2
    RST 1
    .byte $52                           ; SYNCHR: 'R'
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    RST 1
    .byte $4D                           ; SYNCHR: 'M'
    PUSH H
    RST 7
    .byte $02                           ; the hook's number
    LXI H,$F5F0
    CALL L_37DB
    POP H
    RET

L_1DB2:
    PUSH H
    LDA D_FC82
    JMP L_1D95

L_1DB9:
    PUSH H
    LHLD D_F5F4
    CALL L_37DB
    POP H
    RST 2
    RET

ST_WIDTH:
    RST 7
    .byte $3A                           ; the hook's number

ST_SOUND:
    CPI $97
    JZ L_1DE6
    CPI $CB
    JZ L_1DE5
    CALL FRMQNT
    MOV A,D
    ANI $C0
    JNZ FCERR
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    ANA A
    MOV B,A
    POP D
    JNZ MUSIC
    RET

L_1DE5:
    .byte $3E

L_1DE6:
    .byte $AF
    STA D_FF44
    RST 2
    RET

ST_MOTOR:
    SUI $CB
    JZ L_1DF5
    RST 1
    .byte $97                           ; SYNCHR: the ON token
    DCX H
    MOV A,H

L_1DF5:
    MOV E,A
    RST 2
    JMP L_7043

ST_CALL:
    CALL FRMQNT
    XCHG
    SHLD D_F661
    XCHG
    DCX H
    RST 2
    JZ L_1E1B
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CPI $2C
    JZ L_1E14
    CALL GETBYT
    JZ L_1E1B

L_1E14:
    PUSH PSW
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL FRMQNT
    POP PSW

L_1E1B:
    PUSH H
    XCHG
    CALL D_F660
    POP H
    RET

ST_SCREEN:
    CPI $2C
    LDA D_F638
    CNZ GETBYT
    CALL L_1E3C
    DCX H
    RST 2
    RZ
    RST 1
    .byte $2C                           ; SYNCHR: ','
    CALL GETBYT
    PUSH H
    ANA A
    CALL L_13AF
    POP H
    RET

L_1E3C:
    PUSH H
    STA D_F638
    ANA A
    LXI D,$2808
    LHLD D_F640
    MVI A,$0E
    JZ L_1E52
    XRA A
    STA D_F638
    RST 7
    .byte $3E                           ; the hook's number

L_1E52:
    SHLD CSRY
    XCHG
    SHLD D_F63B
    STA D_F676
    POP H
    RET

PRTLCD:
    PUSH H
    CALL L_4BA0
    LXI H,$FE00
    MVI E,$08

L_1E67:
    MVI D,$28

L_1E69:
    MOV A,M
    CALL PNOTAB
    INX H
    DCR D
    JNZ L_1E69
    CALL L_4BA0
    DCR E
    JNZ L_1E67
    POP H
    RET

L_1E7B:
    PUSH H
    CALL L_2146
    LHLD D_FC99
    LXI D,$2020
    RST 3
    PUSH PSW
    JZ L_1E91
    LXI D,$4142
    RST 3
    JNZ L_1EC7

L_1E91:
    CALL L_20A6
    JZ L_1EC7
    POP PSW
    POP B
    POP PSW
    JZ FCERR
    MVI A,$00
    PUSH PSW
    PUSH B
    SHLD D_FA8C
    XCHG
    SHLD TXTTAB
    CALL LINKER
    POP H
    MOV A,M
    CPI $2C
    JNZ L_1EBA
    RST 2
    RST 1
    .byte $52                           ; SYNCHR: 'R'
    POP PSW
    MVI A,$80
    STC
    PUSH PSW

L_1EBA:
    POP PSW
    STA D_FCA7
    JC L_3F28
    CALL L_3F28
    JMP READY

L_1EC7:
    POP PSW
    POP H
    MVI D,$F8
    JNZ L_4D8D
    PUSH H
    LXI H,$2020
    SHLD D_FC99
    POP H
    JMP L_4D8D

L_1ED9:
    PUSH H
    LHLD D_FC99
    LXI D,$4F44
    RST 3
    MVI B,$00
    JZ L_1EF8
    LXI D,$4142
    RST 3
    MVI B,$01
    JZ L_1EF8
    LXI D,$2020
    RST 3
    MVI B,$02
    JNZ L_504E

L_1EF8:
    POP H
    PUSH B
    DCX H
    RST 2
    JZ L_1F10
    RST 1
    .byte $2C                           ; SYNCHR: ','
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    POP B
    DCR B
    JZ L_504E

L_1F08:
    XRA A
    LXI D,$F802
    PUSH PSW
    JMP L_4E0B

L_1F10:
    POP B
    DCR B
    JM L_1F08
    CALL L_2081
    JNZ FCERR
    CALL L_20A6
    CNZ L_2017
    CALL L_2146
    CALL L_20E4
    SHLD D_FA8C
    MVI A,$80
    XCHG
    LHLD TXTTAB
    XCHG
    CALL L_2239
    CALL L_21D4
    JMP READY

ST_FILES:
    PUSH H
    CALL L_1F42
    POP H
    JMP L_4BB8

L_1F42:
    LXI H,$F957

L_1F45:
    MVI C,$03
    LDA D_F63C
    CPI $28
    JZ L_1F51
    MVI C,$06

L_1F51:
    CALL L_20D5
    RZ
    ANI $18
    JNZ L_1F51
    PUSH H
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    PUSH D
    MVI B,$06

L_1F63:
    MOV A,M
    RST 4
    INX H
    DCR B
    JNZ L_1F63
    MVI A,$2E
    RST 4
    MOV A,M
    RST 4
    INX H
    MOV A,M
    RST 4
    POP D
    LHLD TXTTAB
    RST 3
    MVI A,$2A
    MVI B,$20
    JZ L_1F7F
    MOV A,B

L_1F7F:
    RST 4
    MOV A,B
    RST 4
    RST 4
    POP H
    DCR C
    JNZ L_1F51
    CALL CRLF
    CALL L_13F3
    JMP L_1F45

ST_KILL:
    CALL L_207A
    DCX H
    RST 2
    JNZ SNERR
    MOV A,D
    CPI $F8
    JZ L_1FA1
    RST 7
    .byte $58                           ; the hook's number

L_1FA1:
    PUSH H
    XRA A
    STA D_FCA7
    CALL L_4E22
    CALL L_2146
    CALL L_20AF
    JZ FFERR
    MOV B,A
    ANI $20
    JNZ L_1FDA
    MOV A,B
    ANI $40
    JZ L_2005

KILASC:
    .byte $3E

L_1FBF:
    .byte $E5
    LXI B,$0000
    MOV M,C
    MOV L,E
    MOV H,D

L_1FC6:
    LDAX D
    INX D
    INX B
    CPI $1A
    JNZ L_1FC6
    CALL MASDEL

L_1FD1:
    CALL L_18DD
    CALL L_2146
    POP H
    RET

L_1FD9:
    PUSH H

L_1FDA:
    MVI M,$00
    LHLD COSTRT
    PUSH H
    XCHG
    PUSH H
    INX H
    INX H
    MOV C,M
    INX H
    MOV B,M
    LXI H,$0006
    DAD B
    MOV B,H
    MOV C,L
    POP H
    CALL MASDEL
    POP H
    SHLD COSTRT
    JMP L_1FD1

L_1FF8:
    CALL L_2146
    LHLD D_F9B0
    XCHG
    LXI H,$F9AF
    JMP L_1FBF

L_2005:
    PUSH H
    LHLD TXTTAB
    RST 3
    POP H
    JZ FCERR
    CALL L_2017
    CALL L_3F2C
    JMP READY

L_2017:
    MVI M,$00
    LHLD TXTTAB
    RST 3
    PUSH PSW
    PUSH D
    CALL CHEAD
    POP D
    INX H
    CALL L_2134
    PUSH B
    CALL L_2146
    POP B
    POP PSW
    RZ
    RC
    LHLD TXTTAB
    DAD B
    SHLD TXTTAB
    RET

ST_NAME:
    CALL L_207A
    PUSH D
    CALL L_224C
    RST 1
    .byte $41                           ; SYNCHR: 'A'
    RST 1
    .byte $53                           ; SYNCHR: 'S'
    CALL L_207A
    MOV A,D
    POP D
    CMP D
    JNZ FCERR
    CPI $F8
    JZ L_2052
    RST 7
    .byte $5A                           ; the hook's number

L_2052:
    PUSH H
    CALL L_20AF
    JNZ FCERR
    CALL L_224C
    CALL L_20AF
    JZ FFERR
    PUSH H
    LHLD D_FC99
    XCHG
    LHLD D_FCA2
    RST 3
    JNZ FCERR
    POP H
    CALL L_224C
    INX H
    INX H
    INX H
    CALL L_2241
    POP H
    RET

L_207A:
    CALL L_4C0F
    RNZ
    MVI D,$F8
    RET

L_2081:
    LHLD D_FA8C
    LXI D,$F999
    RST 3
    RET

L_2089:
    LXI B,$434F
    JMP L_20A9

L_208F:
    LHLD D_FC99
    LXI D,$2020
    RST 3
    JZ L_20A0
    LXI D,$4F44
    RST 3
    JNZ L_504E

L_20A0:
    LXI B,$444F
    JMP L_20A9

L_20A6:
    LXI B,$4241

L_20A9:
    LXI H,$FC99
    MOV M,B
    INX H
    MOV M,C

L_20AF:
    LXI H,$F957
    .byte $3E

L_20B3:
    .byte $E1
    CALL L_20D5
    RZ
    PUSH H
    INX H
    INX H
    LXI D,$FC92
    MVI B,$08

L_20C0:
    INX D
    INX H
    LDAX D
    CMP M
    JNZ L_20B3
    DCR B
    JNZ L_20C0
    POP H
    MOV A,M
    INX H
    MOV E,M
    INX H
    MOV D,M
    DCX H
    DCX H
    ANA A
    RET

L_20D5:
    PUSH B
    LXI B,$000B
    DAD B
    POP B
    MOV A,M
    CPI $FF
    RZ
    ANA A
    JP L_20D5
    RET

L_20E4:
    LDA D_F651
    ANA A
    LXI H,$F9AF
    RNZ
    LXI H,$F9AF
    LXI B,$000B

L_20F2:
    DAD B
    MOV A,M
    CPI $FF
    JZ FLERR
    ADD A
    JC L_20F2
    RET

ST_NEW:
    RNZ

L_20FF:
    CALL L_2081
    CNZ L_2146
    LXI H,$F999
    SHLD D_FA8C
    LHLD D_F99A
    SHLD TXTTAB
    XRA A
    MOV M,A
    INX H
    MOV M,A
    INX H
    XCHG
    LHLD DOSTRT
    CALL L_2134
    LHLD D_FAD8
    DAD B
    SHLD D_FAD8
    LXI H,$FFFF
    SHLD D_F62E
    JMP L_3F28

L_212D:
    LHLD D_FABA
    XCHG
    LHLD D_FABC

L_2134:
    MOV A,L
    SUB E
    MOV C,A
    MOV A,H
    SBB D
    MOV B,A
    XCHG
    CALL MASDEL
    LHLD DOSTRT
    DAD B
    SHLD DOSTRT
    RET

L_2146:
    XRA A

.if MODEL = 100
    STA D_F809
    LHLD D_FAC0
    INX H

L_214E:
    PUSH H
    LXI H,$F98E
    LXI D,$FFFF

L_2155:
    CALL L_20D5
.else
    CALL L_6C42
    LHLD D_FAC0
    INX H

L_214E:
    PUSH H
    LXI H,$F98E
    LXI D,$FFFF

L_2155:
    CALL L_1B8F
.endif

    JZ L_2175
    RRC
    JC L_2155
    PUSH H
    INX H
    MOV A,M
    INX H
    MOV H,M
    MOV L,A
    RST 3
    POP H
    JNC L_2155
    MOV B,H
    MOV C,L
    INX H
    MOV E,M
    INX H
    MOV D,M
    DCX H
    DCX H
    JMP L_2155

L_2175:
    MOV A,E
    ANA D
    INR A
    POP D
    JZ L_218D
    MOV H,B
    MOV L,C
    MOV A,M
    ORI $01
    MOV M,A
    INX H
    MOV M,E
    INX H
    MOV M,D
    XCHG
    CALL L_219A
    JMP L_214E

L_218D:
    LXI H,$F957

L_2190:
    CALL L_20D5
    RZ
    ANI $FE
    MOV M,A
    JMP L_2190

L_219A:
    LDA D_F809
    DCR A
    JM L_21C2
    JZ L_21AE
    INX H
    INX H
    MOV E,M
    INX H
    MOV D,M
    INX H
    INX H
    INX H
    DAD D
    RET

L_21AE:
    MVI A,$1A

L_21B0:
    CMP M
    INX H
    JNZ L_21B0
    XCHG
    LHLD COSTRT
    XCHG
    RST 3
    RNZ
    MVI A,$02
    STA D_F809
    RET

L_21C2:
    XCHG
    CALL CHEAD
    INX H
    XCHG
    LHLD DOSTRT
    XCHG
    RST 3
    RNZ
    MVI A,$01
    STA D_F809
    RET

L_21D4:
    LHLD VARTAB
    SHLD ARYTAB
    SHLD STREND
    LHLD DOSTRT
    DCX H
    SHLD D_F99A
    INX H
    LXI B,$0002
    XCHG
    CALL L_6B7F
    XRA A
    MOV M,A
    INX H
    MOV M,A
    LHLD DOSTRT
    DAD B
    SHLD DOSTRT
    JMP L_2146

L_21FA:
    PUSH H
    MVI E,$FF

L_21FD:
    INR E
    MOV A,M
    INX H
    ANA A
    JNZ L_21FD
    POP H
    RET

L_2206:
    CALL L_21FA
    CALL L_4C0B
    JNZ SNERR
