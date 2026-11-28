;; MODEL 100 ROM: DEF, THE LINE-NUMBER SCANNER, RUN, GOSUB, GOTO, RETURN, DATA, LET, ON, RESUME, ERROR, IF, PRINT, LINE INPUT, INPUT AND READ
;;
;; Runs at $0872-$0DA8. Model100.asm describes the ROM as a whole and how it is named.

ST_DEF:
    CPI $E0
    JZ L_0886
    CPI $44
    JNZ L_088C
    RST 2
    RST 1
    .byte $42                           ; SYNCHR: 'B'
    RST 1
    .byte $4C                           ; SYNCHR: 'L'
    MVI E,$08
    JMP DEFCON

L_0886:
    RST 2
    MVI E,$02
    JMP DEFCON

L_088C:
    RST 1
    .byte $53                           ; SYNCHR: 'S'
    CPI $4E
    JNZ L_089B
    RST 2
    RST 1
    .byte $47                           ; SYNCHR: 'G'
    MVI E,$04
    JMP DEFCON

L_089B:
    RST 1
    .byte $54                           ; SYNCHR: 'T'
    RST 1
    .byte $52                           ; SYNCHR: 'R'
    MVI E,$03

DEFCON:
    CALL L_40F1
    LXI B,SNERR
    PUSH B
    RC
    SUI $41
    MOV C,A
    MOV B,A
    RST 2
    CPI $D1
    JNZ NOTRNG
    RST 2
    CALL L_40F1
    RC
    SUI $41
    MOV B,A
    RST 2

NOTRNG:
    MOV A,B
    SUB C
    RC
    INR A
    XTHL
    LXI H,$FBBA
    MVI B,$00
    DAD B

LPDCHG:
    MOV M,E
    INX H
    DCR A
    JNZ LPDCHG
    POP H
    MOV A,M
    CPI $2C
    RNZ
    RST 2
    JMP DEFCON

INTIDX:
    RST 2

INTID2:
    CALL GETIN2
    RP

FCERR:
    MVI E,$05
    JMP ERROR

LINSPC:
    MOV A,M
    CPI $2E
    XCHG
    LHLD DOT
    XCHG
    JZ CHRGTR

LINGET:
    DCX H

L_08EC:
    LXI D,$0000

MORLIN:
    RST 2
    RNC
    PUSH H
    PUSH PSW
    LXI H,$1998
    RST 3
    JC POPHSR
    MOV H,D
    MOV L,E
    DAD D
    DAD H
    DAD D
    DAD H
    POP PSW
    SUI $30
    MOV E,A
    MVI D,$00
    DAD D
    XCHG
    POP H
    JMP MORLIN

POPHSR:
    POP PSW
    POP H
    RET

ST_RUN:
    JZ L_3F28
    JNC L_4D6E

CONRUN:
    CALL L_3F2C
    LXI B,NEWSTT
    JMP L_0935

ST_GOSUB:
    MVI C,$03
    CALL L_3EFF
    POP B
    PUSH H
    PUSH H
    LHLD CURLIN
    XTHL
    LXI B,$0000
    PUSH B
    LXI B,NEWSTT
    MVI A,$8C
    PUSH PSW
    INX SP

L_0935:
    PUSH B

ST_GOTO:
    CALL LINGET

L_0939:
    CALL ST_REM
    INX H
    PUSH H
    LHLD CURLIN
    RST 3
    POP H
    CC LOOP
    CNC FNDLIN
    MOV H,B
    MOV L,C
    DCX H
    RC

L_094D:
    MVI E,$08
    JMP ERROR

L_0952:
    PUSH H
    PUSH H
    LHLD CURLIN
    XTHL
    PUSH B
    MVI A,$8C
    PUSH PSW
    INX SP
    XCHG
    DCX H
    SHLD SAVTXT
    INX H
    JMP GONE4

ST_RETURN:
    RNZ
    MVI D,$FF
    CALL FNDFOR
    CPI $8C
    JZ L_0972
    DCX H

L_0972:
    SPHL
    SHLD SAVSTK
    MVI E,$03
    JNZ ERROR
    POP H
    MOV A,H
    ORA L
    JZ L_0987
    MOV A,M
    ANI $01
    CNZ L_3FC7

L_0987:
    POP H
    SHLD CURLIN
    INX H
    MOV A,H
    ORA L
    JNZ L_0998
    LDA D_FB97
    ORA A
    JNZ L_0501

L_0998:
    LXI H,NEWSTT
    XTHL
    .byte $3E                           ; MVI A,$E1: skips the next byte

L_099D:
    POP H

ST_DATA:
    .byte $01                           ; LXI B,$0E3A: skips the next two bytes
    .byte $3A

ST_REM:
    MVI C,$00
    MVI B,$00

EXCHQT:
    MOV A,C
    MOV C,B
    MOV B,A

L_09A7:
    MOV A,M
    ORA A
    RZ
    CMP B
    RZ
    INX H
    CPI $22
    JZ EXCHQT
    SUI $8A
    JNZ L_09A7
    CMP B
    ADC D
    MOV D,A
    JMP L_09A7

    .byte $F1, $C6, $03, $C3, $D6, $09

ST_LET:
    CALL L_4790
    RST 1
    .byte $DD                           ; SYNCHR: the = token
    XCHG
    SHLD D_FB99
    XCHG
    PUSH D
    LDA VALTYP
    PUSH PSW
    CALL FRMEVL
    POP PSW

LETCN2:
    XTHL

INPCOM:
    MOV B,A
    LDA VALTYP
    CMP B
    MOV A,B
    JZ LETCN5
    CALL DOCNVF

LETCN4:
    LDA VALTYP

LETCN5:
    LXI D,$FC18
    CPI $02
    JNZ LETCN6
    LXI D,$FC1A

LETCN6:
    PUSH H
    CPI $03
    JNZ COPNUM
    LHLD D_FC1A
    PUSH H
    INX H
    MOV E,M
    INX H
    MOV D,M

.if MODEL = 100
    LXI H,BUFMIN
.else
    LXI H,$F683
.endif

    RST 3
    JC L_0A1D
    LHLD STREND
    RST 3
    POP D
    JNC DNTCPY
    LXI H,$FB88
    RST 3
    JC L_0A1C
    LXI H,$FB6A
    RST 3
    JC DNTCPY

L_0A1C:
    .byte $3E                           ; MVI A,$D1: skips the next byte

L_0A1D:
    POP D
    CALL FRETMS
    XCHG
    CALL STRCPY

DNTCPY:
    CALL FRETMS
    XTHL

COPNUM:
    CALL L_3465
    POP D
    POP H
    RET

ST_ON:
    CPI $94
    JNZ NTOERR
    RST 2
    RST 1
    .byte $88                           ; SYNCHR: the GOTO token
    CALL LINGET
    MOV A,D
    ORA E
    JZ RESTRP
    CALL FNDLN1
    MOV D,B
    MOV E,C
    POP H
    JNC L_094D

RESTRP:
    XCHG
    SHLD ONELIN
    XCHG
    RC
    LDA ONEFLG
    ORA A
    MOV A,E
    RZ
    LDA ERRFLG
    MOV E,A
    JMP ERRESM

NTOERR:
    CALL L_1AFC
    JC L_0A94
    PUSH B
    RST 2
    RST 1
    .byte $8C                           ; SYNCHR: the GOSUB token
    XRA A

L_0A66:
    POP B
    PUSH B
    CMP C
    JNC SNERR
    PUSH PSW
    CALL LINGET
    MOV A,D
    ORA E
    JZ L_0A7E
    CALL FNDLN1
    MOV D,B
    MOV E,C
    POP H
    JNC L_094D

L_0A7E:
    POP PSW
    POP B
    PUSH PSW
    ADD B
    PUSH B
    CALL L_1B22
    DCX H
    RST 2
    POP B
    POP D
    RZ
    PUSH B
    PUSH D
    RST 1
    .byte $2C                           ; SYNCHR: ','
    POP PSW
    INR A
    JMP L_0A66

L_0A94:
    CALL GETBYT
    MOV A,M
    MOV B,A
    CPI $8C
    JZ ISGOSU
    RST 1
    .byte $88                           ; SYNCHR: the GOTO token
    DCX H

ISGOSU:
    MOV C,E

LOOPON:
    DCR C
    MOV A,B
    JZ GONE2
    CALL L_08EC
    CPI $2C
    RNZ
    JMP LOOPON

ST_RESUME:
    LDA ONEFLG
    ORA A
    JNZ L_0AC0
    STA ONELIN
    STA D_FBA6
    JMP RWERR

L_0AC0:
    INR A
    STA ERRFLG
    MOV A,M
    CPI $82
    JZ L_0ADB
    CALL LINGET
    RNZ
    MOV A,D
    ORA E
    JZ L_0AE0
    CALL L_0939
    XRA A
    STA ONEFLG
    RET

L_0ADB:
    RST 2
    RNZ
    JMP RESTXT

L_0AE0:
    XRA A
    STA ONEFLG
    INR A

RESTXT:
    LHLD ERRTXT
    XCHG
    LHLD ERRLIN
    SHLD CURLIN
    XCHG
    RNZ
    MOV A,M
    ORA A
    JNZ NOTBGL
    INX H
    INX H
    INX H
    INX H

NOTBGL:
    INX H
    MOV A,D
    ANA E
    INR A
    JNZ L_0B08
    LDA D_FB97
    DCR A
    JZ STPEND

L_0B08:
    XRA A
    STA ONEFLG
    JMP ST_DATA

ST_ERROR:
    CALL GETBYT
    RNZ
    ORA A
    JZ FCERR
    JMP ERROR

ST_IF:
    CALL FRMEVL
    MOV A,M
    CPI $2C
    CZ CHRGTR
    CPI $88
    JZ OKGOTO
    RST 1
    .byte $CD                           ; SYNCHR: the THEN token
    DCX H

OKGOTO:
    PUSH H
    CALL L_3411
    POP H
    JZ FALSIF

DOCOND:
    RST 2
    JC ST_GOTO
    JMP GONE3

FALSIF:
    MVI D,$01

SKPMRF:
    CALL ST_DATA
    ORA A
    RZ
    RST 2
    CPI $91
    JNZ SKPMRF
    DCR D
    JNZ SKPMRF
    JMP DOCOND

ST_LPRINT:
    MVI A,$01
    STA PRTFLG
    JMP NEWCHR

ST_PRINT:
    MVI C,$02
    CALL FILGET
    CPI $40
    CZ L_1D5F

NEWCHR:
    DCX H
    RST 2
    CZ L_4BCB

PRINTC:
    JZ FINPRT
    CPI $C2
    JZ L_4991
    CPI $C0
    JZ L_0C01
    PUSH H
    CPI $2C
    JZ COMPRT
    CPI $3B
    JZ NOTABR
    POP B
    CALL FRMEVL
    PUSH H
    RST 5
    JZ L_0BC6
    CALL L_39E8
    CALL STRLIT
    MVI M,$20
    LHLD D_FC1A
    INR M

STRDON:
    CALL L_421A
    JNZ L_0BC2
    LHLD D_FC1A
    LDA PRTFLG
    ORA A
    JZ ISTTY
    LDA LPTPOS
    ADD M
    CPI $FF
    JMP L_0BB9

ISTTY:
    LDA D_F63C
    MOV B,A
    INR A
    JZ L_0BC2
    LDA TTYPOS
    ADD M
    DCR A
    CMP B

L_0BB9:
    JC L_0BC2
    CZ L_4BD1
    CNZ L_4BCB

L_0BC2:
    CALL STRPRT
    ORA A

L_0BC6:
    CZ STRPRT
    POP H
    JMP NEWCHR

COMPRT:
    LXI B,$0008
    LHLD D_FC8C
    DAD B
    CALL L_421A
    MOV A,M
    JNZ MORCOM
    LDA PRTFLG
    ORA A
    JZ ISCTTY
    LDA LPTPOS
    CPI $EE
    JMP CHKCOM

ISCTTY:
    LDA D_F676
    MOV B,A
    LDA TTYPOS
    CMP B

CHKCOM:
    CNC L_4BCB
    JNC NOTABR

MORCOM:
    SUI $0E
    JNC MORCOM
    CMA
    JMP ASPA2

L_0C01:
    CALL GTBYTC
    RST 1
    .byte $29                           ; SYNCHR: ')'
    DCX H
    PUSH H
    LXI B,$0008
    LHLD D_FC8C
    DAD B
    CALL L_421A
    MOV A,M
    JNZ DOSIZT
    LDA PRTFLG
    ORA A
    JZ TTYIST
    LDA LPTPOS
    JMP DOSIZT

TTYIST:
    LDA TTYPOS

DOSIZT:
    CMA
    ADD E
    JNC NOTABR

ASPA2:
    INR A
    MOV B,A
    MVI A,$20

REPOUT:
    RST 4
    DCR B
    JNZ REPOUT

NOTABR:
    POP H
    RST 2
    JMP PRINTC

FINPRT:
    XRA A
    STA PRTFLG
    PUSH H
    MOV H,A
    MOV L,A
    SHLD D_FC8C
    POP H
    RET

ST_LINE:
    CPI $84
    JNZ L_1C6D
    RST 2
    CPI $23
    JZ L_4F5B
    CALL ERRDIR
    MOV A,M
    CALL QTINP
    CALL L_4790
    CALL L_35D9
    PUSH D
    PUSH H
    CALL INLIN
    POP D
    POP B
    JC STPEND
    PUSH B
    PUSH D
    MVI B,$00
    CALL STRLT3
    POP H
    MVI A,$03
    JMP LETCN2

D_0C74:
    .byte "?Redo from start"
    .byte $0D, $0A, $00

TRMNOK:
    LDA FLGINP
    ORA A
    JNZ DATSNE

RDOIN2:
    POP B
    LXI H,D_0C74
    CALL STROUT
    LHLD SAVTXT
    RET

FILSTI:
    CALL FILINP
    PUSH H
    LXI H,BUFMIN
    JMP INPCN3

ST_INPUT:
    CALL ERRDIR
    MOV A,M
    CPI $23
    JZ FILSTI
    CALL ERRDIR
    MOV A,M
    LXI B,NOTQTI
    PUSH B

QTINP:
    CPI $22
    MVI A,$00
    RNZ
    CALL STRLTI

NTICMA:
    RST 1
    .byte $3B                           ; SYNCHR: ';'

INPCMA:
    PUSH H
    CALL STRPRT
    POP H
    RET

NOTQTI:
    PUSH H
    CALL L_463E
    POP B
    JC STPEND
    INX H
    MOV A,M
    ORA A
    DCX H
    PUSH B
    JZ L_099D

INPCN3:
    MVI M,$2C
    JMP L_0CDE

ST_READ:
    PUSH H
    LHLD DATPTR
    .byte $F6                           ; ORI $AF: skips the next byte

L_0CDE:
    XRA A
    STA FLGINP
    XTHL
    JMP LOPDAT

LOPDT2:
    RST 1
    .byte $2C                           ; SYNCHR: ','

LOPDAT:
    CALL L_4790
    XTHL
    PUSH D
    MOV A,M
    CPI $2C
    JZ L_0D0E
    LDA FLGINP
    ORA A
    JNZ DATLOP
    MVI A,$3F
    RST 4
    CALL L_463E
    POP D
    POP B
    JC STPEND
    INX H
    MOV A,M
    DCX H
    ORA A
    PUSH B
    JZ L_099D
    PUSH D

L_0D0E:
    CALL L_421A
    JNZ FILIND
    RST 5
    PUSH PSW
    JNZ NUMINS
    RST 2
    MOV D,A
    MOV B,A
    CPI $22
    JZ NOWGET
    LDA FLGINP
    ORA A
    MOV D,A
    JZ NCOLST
    MVI D,$3A

NCOLST:
    MVI B,$2C
    DCX H

NOWGET:
    CALL STRLT2

DOASIG:
    POP PSW
    ADI $03
    XCHG
    LXI H,STRDN2
    XTHL
    PUSH D
    JMP INPCOM

NUMINS:
    RST 2
    LXI B,DOASIG
    PUSH B
    JMP L_3840

STRDN2:
    DCX H
    RST 2
    JZ TRMOK
    CPI $2C
    JNZ TRMNOK

TRMOK:
    XTHL
    DCX H
    RST 2
    JNZ LOPDT2
    POP D
    LDA FLGINP
    ORA A
    XCHG
    JNZ L_4095
    PUSH D
    CALL L_421A
    JNZ L_0D6D
    MOV A,M
    ORA A
    LXI H,D_0D71
    CNZ STROUT

L_0D6D:
    POP H
    JMP FINPRT

D_0D71:
    .byte "?Extra ignored", $0D, $0A
    .byte $00

DATLOP:
    CALL ST_DATA
    ORA A
    JNZ NOWLIN
    INX H
    MOV A,M
    INX H
    ORA M
    MVI E,$04
    JZ ERROR
    INX H
    MOV E,M
    INX H
    MOV D,M
    XCHG
    SHLD DATLIN
    XCHG

NOWLIN:
    RST 2
    CPI $83
    JNZ DATLOP
    JMP L_0D0E

L_0DA4:
    RST 1
    .byte $DD                           ; SYNCHR: the = token
    JMP FRMEVL
