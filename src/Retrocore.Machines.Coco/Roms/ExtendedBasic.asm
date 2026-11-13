;; TRS-80 COLOR COMPUTER EXTENDED COLOR BASIC ($8000-$9FFF), VERSIONS 1.0 AND 1.1
;;
;; Extended Color BASIC is the second 8K ROM, which Color BASIC finds at <EXBAS> and starts. It adds graphics
;; (PMODE, PCLS, PSET, LINE, CIRCLE, PAINT, DRAW, GET and PUT), sound (PLAY), the editor (EDIT, DEL, RENUM, TRON),
;; DEF FN and USR, PRINT USING, hex and octal numbers, more functions (ATN, COS, TAN, EXP, LOG, SQR, FIX, HEX$,
;; INSTR, STRING$, VARPTR, TIMER, PPOINT), CSAVEM and DLOAD.
;;
;; It adds itself the ways Color BASIC provides for. <XBINIT> copies its command tables into <COMVEC>, after Color
;; BASIC's, so its words crunch and run through <XCOMMAND> and <XFUNCTION>, and points the RAM hooks it needs
;; (<RVEC0> to <RVEC24>) at its own routines: <XVEC20> runs the statement loop, with TRON, and <XVEC15> evaluates
;; FN, USR and hex numbers. Its RAM, at the top of the direct page, is in ExtendedBasicEquates.asm, and the Color
;; BASIC routines it calls are in ColorBasicEntries.asm, at addresses every Color BASIC version shares.
;;
;; Assembles byte-identically to Extended Color BASIC 1.0 or 1.1: VERSION selects the version (11, the default, or
;; 10). 1.0 loads DLOADM's flag the other way round, shows PRINT USING's exponents wrongly from 10, starts PMODE's
;; page from the wrong byte, and does not keep a program's place when PCLEAR moves it.
;;
;; Labels follow the names Microsoft's BASIC and Spectral Associates' Extended Basic Unravelled use where they have
;; them, such as <XVEC20>, <PUFOUT> and <PLYTMR>. The comments are our own.
;;
;; Maintained by hand. CocoRomSourceTests check that each version assembles byte-identically to its ROM.

.ifndef VERSION
VERSION = 11
.endif
.assert (VERSION = 10) | (VERSION = 11), "VERSION is 10 or 11."
.ifndef COCO3
COCO3 = 0
.endif
.assert (COCO3 = 0) | (VERSION = 11), "The CoCo 3's Extended BASIC is 1.1, patched."

.cpu M6809

.include "ColorBasicEquates.asm"
.include "ColorBasicEntries.asm"
.include "ExtendedBasicEquates.asm"
.if COCO3
.include "Coco3Equates.asm"
.include "Coco3Entries.asm"
.endif

.org $8000

    .byte "EX"                      ; EXBAS: Color BASIC looks for these to find this ROM

;; Starts Extended Color BASIC: Color BASIC's cold start jumps here, at <EXBAS>+2, when it finds this ROM.
;;
;; Adds Extended BASIC's command tables to <COMVEC>, points the IRQ at <XIRQSV> for TIMER and PLAY, starts the USR
;; calls at ?FC ERROR, and replaces the RAM hooks Extended BASIC needs with JMPs to its own routines. Then, unless
;; Disk BASIC's ROM is at <ROMPAK>, which takes over from here, it signs on and enters BASIC.
XBINIT:
    LDX #XCOMVEC
    LDU #COMVEC+10                  ; the second table
    LDB #10
    JSR MOVEXU
    LDX #SNERR
    STX 3,U                         ; Disk BASIC's command and function routines, until it adds them
    STX 8,U
    LDX #XIRQSV
    STX IRQVEC+1
    LDX ZERO
    STX TIMVAL                      ; TIMER starts at 0
    JSR XVEC18                      ; PLAY's and DRAW's defaults
    LDD #$2C05
    STD DLBAUD                      ; DLOAD at 1200 baud, and its timeout
    LDX #USR0
    STX USRADR
    LDU #FCERR
    LDB #10
XBINIT_USR:
    STU ,X++                        ; USR0 to USR9 all ?FC ERROR
    DECB
    BNE XBINIT_USR
    LDA #$7E                        ; JMP
    STA RVEC20
    LDX #XVEC20
    STX RVEC20+1
    STA RVEC15
    LDX #XVEC15
    STX RVEC15+1
    STA RVEC19
    LDX #XVEC19
    STX RVEC19+1
    STA RVEC9
    LDX #XVEC9
    STX RVEC9+1
    STA RVEC17
    LDX #XVEC17
    STX RVEC17+1
    STA RVEC4
    LDX #XVEC4
    STX RVEC4+1
    STA RVEC3
    LDX #XVEC3
    STX RVEC3+1
    STA RVEC8
    LDX #XVEC8
    STX RVEC8+1
    STA RVEC23
    LDX #XVEC23
    STX RVEC23+1
    STA RVEC18
    LDX #XVEC18
    STX RVEC18+1
    STA EXPJMP
    LDX #XPOWER
    STX EXPJMP+1                    ; ^ now raises to a power
    JSR GRINIT
    LDA PIA0+3
    ORA #$01                        ; let the field sync interrupt through, for TIMER
    STA PIA0+3
    LDX #$444B                      ; "DK": the start of Disk BASIC's ROM?
    CMPX ROMPAK
    LBEQ ROMPAK+2                   ; then it starts instead
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
    LDX #XSIGNON-1
    JSR STROUT1
    LDX #XBWMST
    STX RSTVEC                      ; RESET now warm starts here
    JMP COLDST_RSTFLG

;; Extended BASIC's warm start, where <RSTVEC> points: stops PLAY's timer and lets the field sync interrupt through
;; again, then warm starts Color BASIC.
XBWMST:
.if COCO3
    .byte $FF                       ; not NOP: the ROM never warm starts here, and start-up's patch makes it NOP
.else
    NOP                             ; the warm start's mark: <WARMCK> looks for it
.endif
    CLR PLYTMR
    CLR PLYTMR+1
    LDA PIA0+3
    ORA #$01
    STA PIA0+3
    JMP BAWMST

.if VERSION = 10
;; Unused: 1.0 has this routine, but nothing calls it. It sets the SAM's M1 bit unless bit 1 of PIA 1's port B is
;; set, then jumps to X.
PCLEAR_CHARAD:
    LDA PIA1+2
    BITA #$02
    BNE PCLEAR_CHARAD_DONE
    STA SAMREG+29                   ; M1 set
PCLEAR_CHARAD_DONE:
    JMP ,X
    .byte 0, 0
.else
;; Moves the program's reading place along with the program after PCLEAR moves it, so PCLEAR in a program goes on
;; with the statement after it. In direct mode there is no program place to move.
;;
;; In:   Y = the program's new start
PCLEAR_CHARAD:
    LDA CURLIN
    INCA
    BEQ PCLEAR_CHARAD_DONE          ; direct mode
    TFR Y,D
    SUBD TXTTAB
    ADDD CHARAD
    STD CHARAD
PCLEAR_CHARAD_DONE:
    RTS
.endif

;; Extended BASIC's command tables, which <XBINIT> copies into <COMVEC>'s second ten bytes.
XCOMVEC:
    .byte 25                        ; 25 commands, from TK_DEL
    .dbyt XCOMWRD                   ;   their reserved words
    .dbyt XCOMMAND                  ;   and the routine that runs them
    .byte 14                        ; 14 functions, from TK_ATN
    .dbyt XFUNWRD                   ;   their reserved words
    .dbyt XFUNCTION                 ;   and the routine that runs them

;; The sign-on message, ended by a zero.
XSIGNON:
.if COCO3
    .byte "EXTENDED COLOR BASIC 2.0", $0D, "COPR. 1982, 1986 BY TANDY  ", $0D
.elseif VERSION = 10
    .byte "EXTENDED COLOR BASIC 1."
    .byte "0", $0D, "COPYRIGHT (C) 1981 BY TANDY", $0D
.else
    .byte "EXTENDED COLOR BASIC 1."
    .byte "1", $0D, "COPYRIGHT (C) 1982 BY TANDY", $0D
.endif
    .byte "UNDER LICENSE FROM MICROSOFT", $0D, $0D, 0

;; Runs an Extended BASIC command, or passes a token that is not one on to Disk BASIC's table.
;;
;; Two of Color BASIC's functions are also commands here: MID$ on the left of an assignment, and TIMER= sets the
;; timer. FN and USING are tokens only inside other statements, so they cannot start one.
;;
;; In:   A = the token, B = twice it
XCOMMAND:
    CMPA #TK_RENUM
    BHI XCOMMAND_OTHER
    LDX #XCOMDSP
    SUBA #TK_DEL
    JMP GONE_DISPATCH
XCOMMAND_OTHER:
    CMPA #$FF                       ; a function token's first byte
    BEQ XCOMMAND_FF
    CMPA #TK_USING
    BLS XCOMMAND_SN                 ; FN or USING
    JMP [COMVEC+23]                 ; Disk BASIC's commands
XCOMMAND_FF:
    JSR GETNCH
    CMPA #TK_MID
    LBEQ MIDSTR                     ; MID$(...)=
    CMPA #TK_TIMER
    LBEQ TIMEQ                      ; TIMER=
    JSR RVEC22
XCOMMAND_SN:
    JMP SNERR

;; Runs an Extended BASIC function, or passes a token that is not one on to Disk BASIC's table. The functions up to
;; HEX$ take one argument in parentheses, which is evaluated first.
;;
;; In:   B = twice the token's second byte, less $80
XFUNCTION:
    CMPB #(TK_STRING - $80) * 2
    BLS XFUNCTION_OURS
    JMP [COMVEC+28]                 ; Disk BASIC's functions
XFUNCTION_OURS:
    SUBB #(TK_ATN - $80) * 2
    CMPB #(TK_HEX - TK_ATN) * 2
    BHI XFUNCTION_CALL              ; the rest read their own arguments
    PSHS B
    JSR PARENS
    PULS B
XFUNCTION_CALL:
    LDX #XFUNDSP
    JMP EVAL_FN_DISPATCH

;; The commands' reserved words, in token order from <TK_DEL>.
XCOMWRD:
    KEYWORD "DEL"
    KEYWORD "EDIT"
    KEYWORD "TRON"
    KEYWORD "TROFF"
    KEYWORD "DEF"
    KEYWORD "LET"
    KEYWORD "LINE"
    KEYWORD "PCLS"
    KEYWORD "PSET"
    KEYWORD "PRESET"
    KEYWORD "SCREEN"
    KEYWORD "PCLEAR"
    KEYWORD "COLOR"
    KEYWORD "CIRCLE"
    KEYWORD "PAINT"
    KEYWORD "GET"
    KEYWORD "PUT"
    KEYWORD "DRAW"
    KEYWORD "PCOPY"
    KEYWORD "PMODE"
    KEYWORD "PLAY"
    KEYWORD "DLOAD"
    KEYWORD "RENUM"
    KEYWORD "FN"
    KEYWORD "USING"

;; The commands' routines, in token order from <TK_DEL> to <TK_RENUM>.
XCOMDSP:
    .dbyt DEL
    .dbyt EDIT
    .dbyt TRON
    .dbyt TROFF
    .dbyt DEF
    .dbyt LET
    .dbyt LINE
    .dbyt PCLS
    .dbyt PSET
    .dbyt PRESET
    .dbyt SCREEN
    .dbyt PCLEAR
    .dbyt COLOR
    .dbyt CIRCLE
    .dbyt PAINT
    .dbyt GET
    .dbyt PUT
    .dbyt DRAW
    .dbyt PCOPY
    .dbyt PMOD
    .dbyt PLAY
    .dbyt DLOAD
    .dbyt RENUM

;; The functions' reserved words, in token order from <TK_ATN>.
XFUNWRD:
    KEYWORD "ATN"
    KEYWORD "COS"
    KEYWORD "TAN"
    KEYWORD "EXP"
    KEYWORD "FIX"
    KEYWORD "LOG"
    KEYWORD "POS"
    KEYWORD "SQR"
    KEYWORD "HEX$"
    KEYWORD "VARPTR"
    KEYWORD "INSTR"
    KEYWORD "TIMER"
    KEYWORD "PPOINT"
    KEYWORD "STRING$"

;; The functions' routines, in token order from <TK_ATN>.
XFUNDSP:
    .dbyt ATN
    .dbyt COS
    .dbyt TAN
    .dbyt EXP
    .dbyt FIX
    .dbyt LOG
    .dbyt POS
    .dbyt SQR
    .dbyt HEXDOL
    .dbyt VARPT
    .dbyt INSTR
    .dbyt TIMER
    .dbyt PPOINT
    .dbyt STRING

;; The console out hook: on the screen, first shows the text screen again (<TEXTSCREEN>), in case graphics are
;; shown; to DLOAD's device, -3, sends nothing.
;;
;; In:   A = the character
XVEC3:
    TST DEVNUM
    LBEQ TEXTSCREEN
    PSHS B
    LDB DEVNUM
    CMPB #$FD                       ; DLOAD's device, -3?
    PULS B
    BNE XVEC3_DONE
    LEAS 2,S                        ; then return from <PUTCHR> without sending it
XVEC3_DONE:
    RTS

;; The close hook: closes a cassette file open for output whose buffer is empty by writing just the end of file
;; block, where Color BASIC 1.0 would write an empty data block first.
XVEC8:
    LDA DEVNUM
    INCA
    BNE XVEC3_DONE                  ; not the cassette
    LDA FILSTA
    CMPA #2
    BNE XVEC3_DONE                  ; not open for output
    LDA CINCTR
    BNE XVEC3_DONE                  ; something left to write
    CLR DEVNUM
    LEAS 2,S                        ; return from <CLSONE>, past the rest
    JMP CLSONE_EOF
;; The RUN hook, and part of Extended BASIC's start-up: sets PLAY's volume, tempo, octave and note length, and
;; DRAW's angle, scale and starting point in the middle of the screen, to their defaults.
XVEC18:
    LDD #$BA42
    STD VOLHI                       ; the volume's middle, high and low DAC levels
    LDA #2
    STA TEMPO
    STA OCTAVE
    ASLA
    STA NOTELN                      ; quarter notes
    CLR DOTVAL
    LDD ZERO
    STD ANGLE                       ; and SCALE
    LDB #128
    STD HORDEF
    LDB #96
    STD VERDEF
    RTS

;; The statement loop's hook: Extended BASIC runs every statement from here on, as <NEWSTT> does, but with TRON's
;; line numbers, and with CSAVEM and its own CLOAD handled before Color BASIC sees them.
XVEC20:
    LEAS 2,S                        ; never return to <NEWSTT>
XVEC20_NEXT:
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
    JSR ISCNTC
    LDX CHARAD
    STX TINPTR
    LDA ,X+
    BEQ XVEC20_LINE                 ; the line has ended
    CMPA #':'
    BEQ XVEC20_RUN                  ; the next statement on the line
    JMP SNERR
XVEC20_LINE:
    LDA ,X++                        ; the next line's link
    STA ENDFLG
    BNE XVEC20_NUMBER
    JMP ENDPRG                      ; past the last line: END
XVEC20_NUMBER:
    LDD ,X+
    STD CURLIN
    STX CHARAD                      ; GETNCH starts after the number
    LDA TRCFLG
    BEQ XVEC20_RUN
    LDA #'['
    JSR PUTCHR
    LDA CURLIN                      ; B still has its low byte
    JSR LINPRT
    LDA #']'
    JSR PUTCHR
XVEC20_RUN:
    JSR GETNCH
    TFR CC,B
    CMPA #TK_CSAVE
    BEQ XVEC20_CSAVE
    CMPA #TK_CLOAD
    BEQ XVEC20_CLOAD
    TFR B,CC                        ; the flags GETNCH left
    JSR GONE2
    BRA XVEC20_NEXT

;; The crunch hook: a line typed in direct mode runs through Extended BASIC's statement loop rather than Color
;; BASIC's, by changing where <CRUNCH> returns to.
XVEC23:
    LDX 2,S
    CMPX #MAINLP_RUN                ; crunching a direct line, to run it?
    BNE XVEC23_DONE
    LDX #XVEC20_RUN
    STX 2,S
XVEC23_DONE:
    RTS

XVEC20_CLOAD:
    JSR XCLOAD
    BRA XVEC20_NEXT
XVEC20_CSAVE:
    BSR XCSAVE
    BRA XVEC20_NEXT

;; Runs CSAVE, and CSAVEM: CSAVEM "name",start,end,exec saves memory from start to end as a machine language file
;; that runs from exec.
;;
;; Errors: ?FC ERROR when end is below start
XCSAVE:
    JSR GETNCH
    CMPA #'M'
    LBNE CSAVE
    JSR GETNCH
    JSR GETNAM
    BSR COMADR
    STX CASBUF+13                   ; the header's load address
    BSR COMADR
    CMPX 2,S
    LBLO FCERR                      ; the end before the start
    BSR COMADR
    STX CASBUF+11                   ; the header's start address
    JSR GETCCH
    BNE XVEC23_DONE                 ; more on the line: nothing done
    LDA #2                          ; machine language
    LDX ZERO                        ; binary, without gaps
    JSR WRHDR
    CLR FILSTA
    INC BLKTYP                      ; data blocks
    JSR WRLDR
    LDX 4,S                         ; the start
XCSAVE_BLOCK:
    STX CBUFAD
    LDA #255
    STA BLKLEN
    LDD 2,S
    SUBD CBUFAD                     ; the bytes left, less one
    BHS XCSAVE_SIZE
    LEAS 6,S                        ; all written: drop the addresses
    JMP CSAVE_END
XCSAVE_SIZE:
    CMPD #255
    BHS XCSAVE_WRITE                ; a full block
    INCB
    STB BLKLEN                      ; the last block, shorter
XCSAVE_WRITE:
    JSR SNDBLK
    BRA XCSAVE_BLOCK

;; Reads a comma and an address, and leaves the address on the stack, under the return address.
COMADR:
    JSR SYNCOM
    JSR GETADR
    LDU ,S
    STX ,S
    TFR U,PC

;; Runs the COS function: the cosine of an angle in radians, as the sine of the angle plus pi/2.
COS:
    LDX #FPIHLF
    JSR FADDX
COS_SIN:
    JMP SIN

;; Runs the TAN function: the tangent of an angle in radians, its sine over its cosine. The cosine reuses the end of
;; <SIN>, with the quadrant the sine found.
;;
;; Errors: ?OV ERROR when the cosine is zero
TAN:
    JSR MOVV40                      ; keep the angle
    CLR RELFLG
    BSR COS_SIN
    LDX #V4A
    JSR MOVMF                       ; keep the sine
    LDX #V40
    JSR MOVFM
    CLR FP0SGN
    LDA RELFLG
    BSR TAN_COS
    TST FP0EXP
    LBEQ OVERR
    LDX #V4A
TAN_DIVIDE:
    JMP FDIVX
TAN_COS:
    PSHS A
    JMP SIN_NEGATE

;; pi/2 in packed floating point.
FPIHLF:
    .byte $81, $49, $0F, $DA, $A2

;; Runs the ATN function: the arctangent, in radians. Beyond 1 it is pi/2 less the arctangent of the reciprocal, so
;; the series always works below 1.
ATN:
    LDA FP0SGN
    PSHS A
    BPL ATN_RANGE
    BSR ATN_NEGATE                  ; work on the magnitude
ATN_RANGE:
    LDA FP0EXP
    PSHS A
    CMPA #$81
    BLO ATN_SERIES                  ; below 1
    LDX #FPONE
    BSR TAN_DIVIDE                  ; the reciprocal
ATN_SERIES:
    LDX #ATNCOF
    JSR ODDPOL
    PULS A
    CMPA #$81
    BLO ATN_SIGN
    LDX #FPIHLF
    JSR FSUBX                       ; pi/2 less it
ATN_SIGN:
    PULS A
    TSTA
    BPL ATN_DONE
ATN_NEGATE:
    JMP NEGATE
ATN_DONE:
    RTS

;; The arctangent's series, for <ODDPOL>: its degree, then twelve coefficients, highest first.
ATNCOF:
    .byte 11
    .byte $76, $B3, $83, $BD, $D3
    .byte $79, $1E, $F4, $A6, $F5
    .byte $7B, $83, $FC, $B0, $10
    .byte $7C, $0C, $1F, $67, $CA
    .byte $7C, $DE, $53, $CB, $C1
    .byte $7D, $14, $64, $70, $4C
    .byte $7D, $B7, $EA, $51, $7A
    .byte $7D, $63, $30, $88, $7E
    .byte $7E, $92, $44, $99, $3A
    .byte $7E, $4C, $CC, $91, $C7
    .byte $7F, $AA, $AA, $AA, $13
    .byte $81, $00, $00, $00, $00

;; The logarithm's series, for <ODDPOL>: its degree, then four coefficients, highest first.
LOGCOF:
    .byte 3
    .byte $7F, $5E, $56, $CB, $79
    .byte $80, $13, $9B, $0B, $64
    .byte $80, $76, $38, $93, $16
    .byte $82, $38, $AA, $3B, $20

;; The square root of 1/2, sqrt(2) and -1/2 in packed floating point.
FSQHLF:
    .byte $80, $35, $04, $F3, $34
FSQTWO:
    .byte $81, $35, $04, $F3, $34
FMHALF:
    .byte $80, $80, $00, $00, $00

;; The natural logarithm of 2 in packed floating point.
FLN2:
    .byte $80, $31, $72, $17, $F8
;; Runs the LOG function: the natural logarithm. With the number as m times 2^e, m between 1/2 and 1, the logarithm
;; is (e - 1/2 + log2(m * sqrt(2))) * ln 2, and log2 of m * sqrt(2) comes from a series in
;; (m * sqrt(2) - 1) / (m * sqrt(2) + 1).
;;
;; Errors: ?FC ERROR for zero or a negative number
LOG:
    JSR SIGN
    LBLE FCERR
    LDX #FSQHLF
    LDA FP0EXP
    SUBA #$80
    PSHS A                          ; e
    LDA #$80
    STA FP0EXP                      ; m
    JSR FADDX
    LDX #FSQTWO
    JSR FDIVX                       ; sqrt(2) / (m + 1/sqrt(2))
    LDX #FPONE
    JSR FSUBX                       ; 1 less it
    LDX #LOGCOF
    JSR ODDPOL
    LDX #FMHALF
    JSR FADDX
    PULS B
    JSR FADDB                       ; plus e
    LDX #FLN2
    JMP FMULX

;; Runs the SQR function: the square root, as the number raised to the power 1/2.
;;
;; Errors: ?FC ERROR for a negative number
SQR:
    JSR MOVAF
    LDX #FHALF
    JSR MOVFM
;; The ^ operator, through <EXPJMP>: FPA1 raised to the power in FPA0, as e^(FPA0 * ln FPA1). A negative base works
;; only for a whole power, and the result is negative when the power is odd.
;;
;; In:   A = FPA1's exponent, zero = set when FPA0 is zero
;; Errors: ?FC ERROR for a negative base and a power that is not whole
XPOWER:
    BEQ EXP                         ; x^0: e^0, 1
    TSTA
    BNE XPOWER_BASE
    JMP ZEROF0_EXP                  ; 0^x: 0
XPOWER_BASE:
    LDX #V4A
    JSR MOVMF                       ; keep the power
    CLRB                            ; a positive result
    LDA FP1SGN
    BPL XPOWER_LOG
    JSR INT
    LDX #V4A
    LDA FP1SGN
    JSR FCOMP_SAME
    BNE XPOWER_LOG                  ; not whole: LOG raises ?FC ERROR
    COMA                            ; the base positive
    LDB CHARAC                      ; the power's low byte: bit 0 odd
XPOWER_LOG:
    JSR MOVFA_SIGN
    PSHS B
    JSR LOG
    LDX #V4A
    JSR FMULX
    BSR EXP
    PULS A
    RORA
    LBCS NEGATE                     ; an odd power of a negative base
    RTS

;; 1/ln 2, which turns a power of e into a power of 2, in packed floating point.
FLOG2E:
    .byte $81, $38, $AA, $3B, $29

;; The series for 2^x between 0 and 1, for <POLY>: its degree, then eight coefficients, highest first.
EXPCOF:
    .byte 7
    .byte $71, $34, $58, $3E, $56
    .byte $74, $16, $7E, $B3, $1B
    .byte $77, $2F, $EE, $E3, $85
    .byte $7A, $1D, $84, $1C, $2A
    .byte $7C, $63, $59, $58, $0A
    .byte $7E, $75, $FD, $E7, $C6
    .byte $80, $31, $72, $18, $10
    .byte $81, $00, $00, $00, $00

;; Runs the EXP function: e raised to a power, as 2 raised to the power over ln 2. The whole part of that becomes
;; the exponent, and a series gives 2 raised to the fraction.
;;
;; Errors: ?OV ERROR when the result is too big; too small is zero
EXP:
    LDX #FLOG2E
    JSR FMULX
    JSR MOVV40
    LDA FP0EXP
    CMPA #$88
    BLO EXP_INT                     ; below 128
EXP_RANGE:
    JMP MULDIV_SIGN
EXP_INT:
    JSR INT
    LDA CHARAC                      ; the whole part
    ADDA #$81                       ; as an exponent, plus one
    BEQ EXP_RANGE                   ; 127: too big
    DECA
    PSHS A
    LDX #V40
    JSR FSUBX                       ; the fraction
    LDX #EXPCOF
    JSR POLYX
    CLR RESSGN
    PULS A
    JSR MULDIV                      ; add the whole part to the exponent
    RTS

;; Runs the FIX function: the number without its fraction, toward zero, where INT goes down.
FIX:
    JSR SIGN
    BMI FIX_NEGATIVE
FIX_INT:
    JMP INT
FIX_NEGATIVE:
    COM FP0SGN
    BSR FIX_INT
    JMP NEGATE

;; Runs EDIT: edits a program line one subcommand at a time, as Microsoft's BASICs do. A count may come before a
;; subcommand: n space moves right n characters, and n backspace left; nD deletes; nC changes; I inserts, X
;; inserts at the end, and H deletes the rest and inserts, until ENTER or ESC (or SHIFT-up arrow); nSc moves to the
;; nth c, and nKc deletes up to it; L shows the line and starts again at its start; A starts again from the line in
;; the program; ENTER and E keep the edited line, and Q leaves it as it was.
;;
;; Errors: ?UL ERROR when the line does not exist
EDIT:
    JSR LINNUM
    LEAS 2,S                        ; never return to the statement loop
EDIT_LINE:
    LDA #1
    STA VD8                         ; show the line first
    JSR FINDLN
    LBLO ULERR
    JSR DETOK                       ; the line's text, from LINBUF+1
    TFR Y,D
    SUBD #LINBUF+2
    STB VD7                         ; its length
EDIT_START:
    LDD BINVAL
    JSR LINPRT
    JSR OUTSPC
    LDX #LINBUF+1                   ; the cursor at the line's start
    LDB VD8
    BNE EDIT_LIST
EDIT_COMMAND:
    CLRB                            ; no count yet
EDIT_COUNT:
    JSR EDTKEY
    JSR DIGCHK
    BLO EDIT_KEY                    ; not a digit
    SUBA #'0'
    PSHS A
    LDA #10
    MUL
    ADDB ,S+                        ; the count times 10, plus the digit
    BRA EDIT_COUNT
EDIT_KEY:
    SUBB #1
    ADCB #1                         ; a count of 0 is 1
    CMPA #'A'
    BNE EDIT_L
    JSR PRNTCR
    BRA EDIT_LINE
EDIT_L:
    CMPA #'L'
    BNE EDIT_ENTER
EDIT_LIST:
    BSR EDIT_REST
    CLR VD8
    JSR PRNTCR
    BRA EDIT_START
EDIT_ENTER_INSERT:
    LEAS 2,S                        ; ENTER while inserting: leave the insert
EDIT_ENTER:
    CMPA #$0D
    BNE EDIT_E
    BSR EDIT_REST
EDIT_SAVE:
    JSR PRNTCR
    LDX #LINBUF+1
    STX CHARAD
    JMP EDITLN_NUMBER               ; crunch it and put it in the program
EDIT_E:
    CMPA #'E'
    BEQ EDIT_SAVE
    CMPA #'Q'
    BNE EDIT_OTHER
    JSR PRNTCR
    JMP OKPRMT
EDIT_OTHER:
    BSR EDIT_SPACE
    BRA EDIT_COMMAND

;; Runs EDIT's space, D, I, X, H, C, backspace, K and S subcommands; any other key does nothing.
;;
;; In:   A = the subcommand, B = its count, X = the cursor
EDIT_SPACE:
    CMPA #' '
    BNE EDIT_D
    .byte $8C                       ; CMPX #: skips the LDB below, to move the count
;; Shows the rest of the line from the cursor, moving the cursor to its end.
EDIT_REST:
    LDB #249                        ; more than a line has
EDIT_SHOW:
    LDA ,X
    BEQ EDIT_SHOW_DONE
    JSR PUTCHR
    LEAX 1,X
    DECB
    BNE EDIT_SHOW
EDIT_SHOW_DONE:
    RTS
EDIT_D:
    CMPA #'D'
    BNE EDIT_C
EDIT_DELETE:
    TST ,X
    BEQ EDIT_SHOW_DONE              ; nothing left to delete
    BSR EDIT_REMOVE
    DECB
    BNE EDIT_DELETE
    RTS

;; Removes the character at the cursor, moving the rest of the line left.
;;
;; In:   X = the cursor
EDIT_REMOVE:
    DEC VD7
    LEAY -1,X
EDIT_REMOVE_NEXT:
    LEAY 1,Y
    LDA 1,Y
    STA ,Y
    BNE EDIT_REMOVE_NEXT
    RTS

EDIT_I:
    CMPA #'I'
    BEQ EDIT_INSERT
    CMPA #'X'
    BEQ EDIT_EXTEND
    CMPA #'H'
    BNE EDIT_BS
    CLR ,X                          ; delete the rest
    TFR X,D
    SUBD #LINBUF+2
    STB VD7
EDIT_EXTEND:
    BSR EDIT_REST
EDIT_INSERT:
    JSR EDTKEY
    CMPA #$0D
    BEQ EDIT_ENTER_INSERT
    CMPA #$1B
    BEQ EDIT_DONE                   ; ESC: back to subcommands
    CMPA #$08
    BNE EDIT_INSERT_CHAR
    CMPX #LINBUF+1
    BEQ EDIT_INSERT                 ; at the start: nothing to rub out
    BSR EDIT_LEFT
    BSR EDIT_REMOVE
    BRA EDIT_INSERT
EDIT_C:
    CMPA #'C'
    BNE EDIT_I
EDIT_CHANGE:
    TST ,X
    BEQ EDIT_DONE                   ; at the line's end
    JSR EDTKEY
    BLO EDIT_CHANGE_STORE           ; a character
    BRA EDIT_CHANGE
EDIT_CHANGE_STORE:
    STA ,X+
    BSR EDIT_OUT
    DECB
    BNE EDIT_CHANGE
EDIT_DONE:
    RTS
EDIT_INSERT_CHAR:
    LDB VD7
    CMPB #249
    BNE EDIT_INSERT_ROOM
    BRA EDIT_INSERT                 ; the line is full
EDIT_INSERT_ROOM:
    PSHS X
EDIT_INSERT_END:
    TST ,X+
    BNE EDIT_INSERT_END
EDIT_INSERT_MOVE:
    LDB ,-X                         ; move the rest of the line right one
    STB 1,X
    CMPX ,S
    BNE EDIT_INSERT_MOVE
    LEAS 2,S
    STA ,X+
    BSR EDIT_OUT
    INC VD7
    BRA EDIT_INSERT
EDIT_BS:
    CMPA #$08
    BNE EDIT_K
EDIT_BACK:
    BSR EDIT_LEFT
    DECB
    BNE EDIT_BACK
    RTS

;; Moves the cursor left one character, unless it is at the line's start.
EDIT_LEFT:
    CMPX #LINBUF+1
    BEQ EDIT_DONE
    LEAX -1,X
    LDA #$08
EDIT_OUT:
    JMP PUTCHR
EDIT_K:
    CMPA #'K'
    BEQ EDIT_FIND                   ; A nonzero: kill
    SUBA #'S'
    BEQ EDIT_FIND                   ; A zero: search
    RTS
EDIT_FIND:
    PSHS A
    BSR EDTKEY                      ; the character to find
    PSHS A
EDIT_FIND_NEXT:
    LDA ,X
    BEQ EDIT_FIND_DONE              ; not found
    TST 1,S
    BNE EDIT_FIND_KILL
    BSR EDIT_OUT                    ; search: move past it
    LEAX 1,X
    BRA EDIT_FIND_CHECK
EDIT_FIND_KILL:
    JSR EDIT_REMOVE
EDIT_FIND_CHECK:
    LDA ,X
    CMPA ,S
    BNE EDIT_FIND_NEXT
    DECB                            ; one more found
    BNE EDIT_FIND_NEXT
EDIT_FIND_DONE:
    PULS Y,PC                       ; drop the two bytes and return

;; Waits for a key for EDIT, ignoring keys above $7E and control keys other than ENTER, ESC and backspace.
;; SHIFT-up arrow is ESC.
;;
;; Out:  A = the key, carry = set for a character to store
EDTKEY:
    JSR INCHR
    CMPA #$7F
    BHS EDTKEY
    CMPA #$5F                       ; SHIFT-up arrow
    BNE EDTKEY_CHECK
    LDA #$1B
EDTKEY_CHECK:
    CMPA #$0D
    BEQ EDTKEY_DONE
    CMPA #$1B
    BEQ EDTKEY_DONE
    CMPA #$08
    BEQ EDTKEY_DONE
    CMPA #' '
    BLO EDTKEY
    ORCC #$01                       ; carry: a character
EDTKEY_DONE:
    RTS

;; Runs TRON: shows each line's number in brackets as it runs.
TRON:
    .byte $86                       ; LDA #: skips the CLRA below, so A is not zero
;; Runs TROFF: stops TRON.
TROFF:
    CLRA
    STA TRCFLG
    RTS

;; Runs the POS function: the column a device's output is at, 0 for the screen's left edge.
;;
;; In:   FPA0 = the device number
POS:
    LDA DEVNUM
    PSHS A
    JSR SETDEV
    JSR CHKOUT
    JSR SETPRM
    LDB DEVPOS
    JMP EOF_RESULT                  ; the device back, and B as the result

;; Runs the VARPTR function: the address of a variable's value, or of an array's start. The variable must already
;; exist, since making it would move the arrays.
;;
;; Errors: ?FC ERROR when the variable does not exist yet
VARPT:
    JSR SYNLPR
    LDD ARYEND
    PSHS A,B
    JSR PTRGET
    JSR SYNRPR
    PULS A,B
    EXG X,D
    CMPX ARYEND
    BNE MIDSTR_FC                   ; it was just made
    JMP GIVABF
;; Runs MID$(s$,start,length)=t$: replaces part of a string variable with another string's characters, in place.
;; The variable keeps its length: no more of t$ goes in than length, or than the variable has from start.
;;
;; A string whose text is still in the program, as a literal assigned to it, is copied into string space first,
;; so the program is not changed.
;;
;; Errors: ?FC ERROR when start is 0 or past the string's end
MIDSTR:
    JSR GETNCH                      ; past MID$
    JSR SYNLPR
    JSR PTRGET
    PSHS X                          ; the variable's descriptor
    LDD 2,X
    CMPD FRETOP
    BLS MIDSTR_COPY                 ; below string space: in the program
    SUBD MEMSIZ
    BLS MIDSTR_START                ; in string space
MIDSTR_COPY:
    LDB ,X
    JSR GETSPA
    PSHS X
    LDX 2,S
    JSR MOVSTR
    PULS X,U
    STX 2,U                         ; the copy's address
    PSHS U
MIDSTR_START:
    JSR COMBYT
    PSHS B                          ; start
    TSTB
    BEQ MIDSTR_FC
    LDB #255                        ; no length: all of t$ that fits
    CMPA #')'
    BEQ MIDSTR_LENGTH
    JSR COMBYT
MIDSTR_LENGTH:
    PSHS B                          ; length
    JSR SYNRPR
    LDB #TK_EQUAL
    JSR SYNCHR
    BSR FRMSTR                      ; t$
    TFR X,U
    LDX 2,S
    LDA ,X
    SUBA 1,S
    BHS MIDSTR_ROOM
MIDSTR_FC:
    JMP FCERR                       ; start past the end
MIDSTR_ROOM:
    INCA                            ; the characters from start to the end
    CMPA ,S
    BHS MIDSTR_PLACE
    STA ,S                          ; fewer than length
MIDSTR_PLACE:
    LDA 1,S
    EXG A,B                         ; A = t$'s length, B = start
    LDX 2,X
    DECB
    ABX                             ; where t$ goes
    TSTA
    BEQ MIDSTR_DONE                 ; t$ is empty
    CMPA ,S
    BLS MIDSTR_MOVE
    LDA ,S
MIDSTR_MOVE:
    TFR A,B
    EXG U,X
    JSR MOVEXU
MIDSTR_DONE:
    PULS A,B,X,PC

;; Evaluates a string expression and frees its temporary string, ready to use.
;;
;; Out:  B = its length, X = its text
FRMSTR:
    JSR FRMEVL
    JMP FRESTR

;; Runs the STRING$(n,c) function: n copies of a character, given as its code or as a string's first character.
STRING:
    JSR SYNLPR
    JSR GETBYT
    PSHS B                          ; n
    JSR SYNCOM
    JSR FRMEVL
    JSR SYNRPR
    LDA VALTYP
    BNE STRING_FIRST
    JSR BYTCHK                      ; a character code
    BRA STRING_MAKE
STRING_FIRST:
    JSR FIRSTC                      ; a string's first character
STRING_MAKE:
    PSHS B
    LDB 1,S
    JSR STRSPA
    PULS A,B
    BEQ STRING_DONE                 ; n is 0
STRING_FILL:
    STA ,X+
    DECB
    BNE STRING_FILL
STRING_DONE:
    JMP CHRSTR_DONE

;; Runs the INSTR([start,]s$,t$) function: where t$ first appears in s$ at or after start (1 by default), or 0
;; when it does not. An empty t$ is found at start, unless start is past s$'s end.
;;
;; Errors: ?FC ERROR when start is 0
INSTR:
    JSR SYNLPR
    JSR FRMEVL
    LDB #1
    PSHS B                          ; start
    LDA VALTYP
    BNE INSTR_SEARCH                ; no start given
    JSR BYTCHK
    STB ,S
    BEQ MIDSTR_FC
    JSR SYNCOM
    JSR FRMEVL
    JSR CKSTR
INSTR_SEARCH:
    LDX FPA0+2
    PSHS X                          ; s$'s descriptor
    JSR SYNCOM
    JSR FRMSTR
    PSHS B,X                        ; t$'s length and text
    JSR SYNRPR
    LDX 3,S
    JSR FRETMP                      ; s$'s length and text
    PSHS B
    CMPB 6,S
    BLO INSTR_NONE                  ; start is past its end
    LDA 1,S
    BEQ INSTR_FOUND                 ; t$ is empty
    LDB 6,S
    DECB
    ABX
INSTR_TRY:
    LEAY ,X
    LDU 2,S
    LDB 1,S
    LDA ,S
    SUBA 6,S
    INCA                            ; the characters left
    CMPA 1,S
    BLO INSTR_NONE                  ; fewer than t$ has
INSTR_COMPARE:
    LDA ,X+
    CMPA ,U+
    BNE INSTR_NEXT
    DECB
    BNE INSTR_COMPARE
INSTR_FOUND:
    LDB 6,S
    .byte $21                       ; BRN: skips the CLRB below
INSTR_NONE:
    CLRB
    LEAS 7,S
    JMP GIVB
INSTR_NEXT:
    INC 6,S
    LEAX 1,Y
    BRA INSTR_TRY

;; The number hook: reads &H followed by hex digits, or &O or & followed by octal digits, as a number from 0 to
;; 65535, for <FIN>.
;;
;; In:   A = the number's first character
;; Errors: ?OV ERROR past 16 bits; ?SN ERROR for an octal 9
XVEC19:
    CMPA #'&'
    BNE XVEC19_DONE
    LEAS 2,S                        ; return from FIN with the number
HEXOCT:
    CLR FPA0+2
    CLR FPA0+3
    LDX #FPA0+2                     ; the value
    JSR GETNCH
    CMPA #'O'
    BEQ HEXOCT_OCTAL
    CMPA #'H'
    BEQ HEXOCT_HEX
    JSR GETCCH                      ; octal, with its first digit read
    BRA HEXOCT_OCTAL_CHECK
HEXOCT_OCTAL_DIGIT:
    CMPA #'8'                       ; 8 slips through: only 9 is refused
    LBHI SNERR
    LDB #3
    BSR HEXOCT_SHIFT
HEXOCT_OCTAL:
    JSR GETNCH
HEXOCT_OCTAL_CHECK:
    BLO HEXOCT_OCTAL_DIGIT          ; a digit
;; Returns the 16-bit number at <FPA0>+2 as the result, from 0 to 65535.
GIVINT:
    CLR FPA0
    CLR FPA0+1
    CLR VALTYP
    CLR FPSBYT
    CLR FP0SGN
    LDB #$A0                        ; the binary point after 32 bits
    STB FP0EXP
    JMP NORMAL
HEXOCT_HEX:
    JSR GETNCH
    BLO HEXOCT_HEX_DIGIT            ; 0-9
    JSR ISLETC
    BLO GIVINT                      ; not a letter: the end
    CMPA #'G'
    BHS GIVINT                      ; past F
    SUBA #'A' - '0' - 10            ; A-F after 9
HEXOCT_HEX_DIGIT:
    LDB #4
    BSR HEXOCT_SHIFT
    BRA HEXOCT_HEX

;; Shifts the value left a digit's bits and adds the digit.
;;
;; In:   A = the digit's character, B = its bits, X = the value
;; Errors: ?OV ERROR past 16 bits
HEXOCT_SHIFT:
    ASL 1,X
    ROL ,X
    LBCS OVERR
    DECB
    BNE HEXOCT_SHIFT
    SUBA #'0'
    ADDA 1,X
    STA 1,X
XVEC19_DONE:
    RTS

;; The expression hook: a term that is a hex or octal number, FN, or USR goes to Extended BASIC's routine; any
;; other goes back to <EVAL>, with the program's place as it was.
XVEC15:
    PULS U                          ; where EVAL goes on
    CLR VALTYP
    LDX CHARAD
    JSR GETNCH
    CMPA #'&'
    BEQ HEXOCT
    CMPA #TK_FN
    BEQ FNCALL
    CMPA #$FF                       ; a function token's first byte
    BNE XVEC15_BACK
    JSR GETNCH
    CMPA #TK_USR
    LBEQ USRCALL
XVEC15_BACK:
    STX CHARAD
    JMP ,U

;; Raises ?ID ERROR in direct mode.
NODIRECT:
    LDX CURLIN
    LEAX 1,X
    BNE XVEC19_DONE                 ; a program is running
    LDB #ERR_ID
NODIRECT_ERROR:
    JMP ERROR

;; Runs DEF FN: DEF FNname(variable)=expression keeps where the expression is, and the variable, in the function's
;; variable, then skips the rest of the statement. DEF USR goes to <DEFUSR>.
;;
;; Errors: ?ID ERROR in direct mode
DEF:
    LDX [CHARAD]
    CMPX #$FF00 | TK_USR
    LBEQ DEFUSR
    BSR FNNAME
    BSR NODIRECT
    JSR SYNLPR
    LDB #$80
    STB ARYDIS                      ; a simple variable
    JSR PTRGET
    BSR FNNAME_NUMBER
    JSR SYNRPR
    LDB #TK_EQUAL
    JSR SYNCHR
    LDX V4B
    LDD CHARAD
    STD ,X                          ; the expression
    LDD VARPTR
    STD 2,X                         ; the variable
    JMP DATA

;; Reads FN and a function's name, and finds or makes its variable: the name with bit 7 set in its first character,
;; so it is apart from the variables.
;;
;; Out:  X, V4B = the function's variable
FNNAME:
    LDB #TK_FN
    JSR SYNCHR
    LDB #$80
    STB ARYDIS
    ORA #$80
    JSR PTRGT2_NAME
    STX V4B
FNNAME_NUMBER:
    JMP CKNUM

;; Calls a function DEF FN made: evaluates its argument, gives the value to the function's variable, evaluates its
;; expression, then gives the variable back the value it had.
;;
;; Errors: ?UF ERROR when the function is not defined
FNCALL:
    BSR FNNAME
    PSHS X
    JSR PARENS
    BSR FNNAME_NUMBER
    PULS U
    LDB #ERR_UF
    LDX 2,U                         ; the variable
    BEQ NODIRECT_ERROR              ; never defined
    LDY CHARAD
    LDU ,U
    STU CHARAD                      ; read the expression
    LDA 4,X
    PSHS A
    LDD ,X
    LDU 2,X
    PSHS A,B,X,Y,U                  ; the variable's value, and the program's place
    JSR MOVMF
    JSR FRMNUM
    PULS A,B,X,Y,U
    STD ,X
    STU 2,X
    PULS A
    STA 4,X
    JSR GETCCH
    LBNE SNERR                      ; the expression must be all of its statement
    STY CHARAD
FNCALL_DONE:
    RTS

;; The error hook: shows Extended BASIC's errors, which Color BASIC's table does not have.
;;
;; In:   B = the error's code
XVEC17:
    CMPB #ERR_UF
    BLO FNCALL_DONE                 ; Color BASIC's
    JSR MOTOROFF
    JSR SNDOFF
    JSR RSTSTK
    CLR DEVNUM
    JSR NEWLIN
    JSR OUTQST
    LDX #XERRTAB - ERR_UF
    JMP ERROR_SHOW

;; Extended BASIC's errors' two-letter names, from <ERR_UF>.
XERRTAB:
    .byte "UF", "NE"

;; Runs DEF USRn=address: sets where USRn calls, for n from 0 to 9.
DEFUSR:
    JSR GETNCH
    BSR USRSLOT
    PSHS X
    BSR EQADR
    PULS U
    STX ,U
    RTS

;; Reads the digit after USR, 0 if there is none, and finds its address in the USR table at <USRADR>.
;;
;; Out:  X = the address's place
USRSLOT:
    CLRB
    JSR GETNCH
    BHS USRSLOT_NUMBER              ; no digit
    SUBA #'0'
    TFR A,B
    JSR GETNCH
USRSLOT_NUMBER:
    LDX USRADR
    ASLB
    ABX
    RTS

;; Calls USRn(argument): evaluates the argument and calls the machine language routine DEF USRn set, by returning
;; into it.
;;
;; Out:  A = the argument's type, as <VALTYP>; X = FPA0's exponent for a number, or a string's descriptor
USRCALL:
    BSR USRSLOT
    LDX ,X
    PSHS X                          ; the routine, as the return address
    JSR PARENS
    LDX #FP0EXP
    LDA VALTYP
    BEQ USRCALL_DONE
    JSR FREFAC
    LDX FPA0+2
    LDA VALTYP
USRCALL_DONE:
    RTS

;; Reads = and a 16-bit address.
;;
;; Out:  X = the address
EQADR:
    LDB #TK_EQUAL
    JSR SYNCHR
    JMP GETADR

;; Extended BASIC's IRQ handler: on the field sync interrupt, counts TIMER up, and PLAY's and SOUND's timers down.
XIRQSV:
    LDA PIA0+3
    BMI XIRQSV_FIELD
    RTI
XIRQSV_FIELD:
    LDA PIA0+2                      ; acknowledge it
XIRQSV_TIMER:
    LDX TIMVAL
    LEAX 1,X
    STX TIMVAL
    JMP PLAYIRQ

;; Runs TIMER=n: sets the timer, which counts sixtieths of a second.
TIMEQ:
    JSR GETNCH
    BSR EQADR
    STX TIMVAL
    RTS

;; Runs the TIMER function: the sixtieths of a second counted since it was set, from 0 to 65535.
TIMER:
    LDX TIMVAL
    STX FPA0+2
    JMP GIVINT

;; Runs DEL n, DEL n-m and DEL n-: deletes a line, or the lines from n to m, or from n to the end. With no line n,
;; the deleting starts at the next line after it.
;;
;; Errors: ?FC ERROR with no line number
DEL:
    LBEQ FCERR
    JSR LINGET
    JSR FINDLN
    STX VD3                         ; the first line to delete
    JSR GETCCH
    BEQ DEL_FIRST                   ; just n
    CMPA #TK_MINUS
    BNE MOVPRG_DONE
    JSR GETNCH
    BEQ DEL_END
    BSR LINNUM
    BRA DEL_FIRST
DEL_END:
    LDA #$FF
    STA BINVAL                      ; past the last line
DEL_FIRST:
    LDU VD3
    .byte $8C                       ; CMPX #: skips the LDU below
DEL_NEXT:
    LDU ,U
    LDD ,U
    BEQ DEL_MOVE                    ; the end of the program
    LDD 2,U
    SUBD BINVAL
    BLS DEL_NEXT                    ; not past the last line to delete
DEL_MOVE:
    LDX VD3
    BSR MOVPRG
    JSR CLRVAR
    LDX VD3
    JSR LINKLN_LINE
    JMP OKPRMT

;; Reads a line number, which must end the statement.
;;
;; Out:  BINVAL = the number
LINNUM:
    JSR LINGET
    JMP NAMEND_CHECK

MOVPRG_BYTE:
    LDA ,U+
    STA ,X+
;; Moves the program down: the bytes from U up to the variables' start go to X, and the variables start after them.
;;
;; In:   U = the first byte to keep, X = where it goes
MOVPRG:
    CMPU VARTAB
    BNE MOVPRG_BYTE
    STX VARTAB
MOVPRG_DONE:
    RTS
;; Runs LINE INPUT [#device,]["prompt";]v$: reads a whole line, commas and quotes and all, into a string variable.
;;
;; Errors: ?ID ERROR in direct mode
LINEINPUT:
    JSR NODIRECT
    JSR GETNCH                      ; past INPUT
    CMPA #'#'
    BNE LINEINPUT_PROMPT
    JSR GETDEV
    JSR CHKIN
    JSR SYNCOM
LINEINPUT_PROMPT:
    CMPA #'"'
    BNE LINEINPUT_READ
    JSR STRLIT
    LDB #';'
    JSR SYNCHR
    JSR STRPRT
LINEINPUT_READ:
    LEAS -2,S                       ; room for what INPLIN drops on BREAK
    JSR INPLIN_READ
    LEAS 2,S
    CLR DEVNUM
    JSR PTRGET
    STX VARDES
    JSR CKSTR
    LDX #LINBUF
    CLRA                            ; only the line's end ends it
    JSR STRLT2_ENDS
    JMP LETSTR

;; Reads a line number for RENUM.
;;
;; Out:  X, BINVAL = the number
RENUM_NUMBER:
    JSR LINGET
    LDX BINVAL
    RTS

;; Finds the first line to renumber, or the line with the number in X.
;;
;; Out:  X = the line, or the next line after the number
RENUM_OLD:
    LDX VD1
RENUM_FIND:
    STX BINVAL
    JMP FINDLN

;; Runs RENUM [new][,[old][,step]]: renumbers the lines from old (the first line, by default) to the end, as new
;; (10), new + step (10), and so on, and every GOTO, GOSUB, THEN and ELSE that names them. A line a reference names
;; that does not exist is reported as UL, and the reference keeps its number.
;;
;; The references are first packed in place as five bytes, 1 and then the number with its zero bytes flagged, so
;; they can be found and changed whatever their length; at the end they are turned back into text.
;;
;; Errors: ?FC ERROR when step is 0, when new would come before a line that is not renumbered, or when a number
;; would pass 63999
RENUM:
    JSR CLRSTR
    LDD #10
    STD VD5                         ; new
    STD VCF                         ; step
    CLRB
    STD VD1                         ; old
    JSR GETCCH
    BHS RENUM_OLDARG                ; no new
    BSR RENUM_NUMBER
    STX VD5
    JSR GETCCH
RENUM_OLDARG:
    BEQ RENUM_START
    JSR SYNCOM
    BHS RENUM_STEPARG               ; no old
    BSR RENUM_NUMBER
    STX VD1
    JSR GETCCH
RENUM_STEPARG:
    BEQ RENUM_START
    JSR SYNCOM
    BHS RENUM_END                   ; no step
    BSR RENUM_NUMBER
    STX VCF
    BEQ RENUM_FC
RENUM_END:
    JSR NAMEND_CHECK
RENUM_START:
    BSR RENUM_OLD
    STX VD3                         ; the first line to renumber
    LDX VD5
    BSR RENUM_FIND
    CMPX VD3
    BLO RENUM_FC                    ; new is below a line before old
    BSR RENUM_CHECK                 ; every new number in range?
    JSR RENUM_PACK
    JSR LINKLN
    BSR RENUM_OLD
    STX VD3
    BSR RENUM_REFS                  ; each reference to the line it names
    BSR RENUM_LINES                 ; the lines' new numbers
    BSR RENUM_REFS                  ; each reference to its line's new number
    JSR RENUM_TEXT
    JSR CLRSTR
    JSR LINKLN
    JMP OKPRMT

;; Gives the lines from the first to renumber their new numbers, or with RENUM_CHECK only checks that every new
;; number is below 64000.
;;
;; Errors: ?FC ERROR past 63999
RENUM_CHECK:
    .byte $86                       ; LDA #: skips the CLRA below, so A is not zero
RENUM_LINES:
    CLRA
    STA VD8                         ; zero: store the numbers
    LDX VD3
    LDD VD5
    BSR PRGEND
RENUM_LINES_NEXT:
    TST VD8
    BNE RENUM_LINES_LINK
    STD 2,X
RENUM_LINES_LINK:
    LDX ,X
    BSR PRGEND
    ADDD VCF
    BLO RENUM_FC
    CMPA #$FA                       ; 64000
    BLO RENUM_LINES_NEXT
RENUM_FC:
    JMP FCERR

;; Returns from the caller when X is at the program's end, the zero link after its last line.
;;
;; In:   X = a line
PRGEND:
    PSHS A,B
    LDD ,X
    PULS A,B
    BNE PRGEND_DONE
    LEAS 2,S
PRGEND_DONE:
    RTS

;; Goes through every packed reference once: 1, a line number not looked up yet, becomes 2 and the address of the
;; line it names, or 3 when there is no such line; 2 becomes 1 and the named line's number, which is its new number
;; by now.
RENUM_REFS:
    LDX TXTTAB
    LEAX -1,X
RENUM_REFS_LINE:
    LEAX 1,X
    BSR PRGEND
RENUM_REFS_SKIP:
    LEAX 3,X                        ; past the link and number, or a reference's bytes
RENUM_REFS_NEXT:
    LEAX 1,X
    LDA ,X
    BEQ RENUM_REFS_LINE
    STX TEMPTR
    DECA
    BEQ RENUM_REFS_FIND             ; 1
    DECA
    BEQ RENUM_REFS_NEW              ; 2
    DECA
    BNE RENUM_REFS_NEXT
RENUM_REFS_MISSING:
    LDA #3
    STA ,X+
    BRA RENUM_REFS_SKIP
RENUM_REFS_FIND:
    LDD 1,X
    DEC 2,X
    BEQ RENUM_REFS_LOW
    CLRA                            ; the high byte is zero
RENUM_REFS_LOW:
    LDB 3,X
    DEC 4,X
    BEQ RENUM_REFS_SEARCH
    CLRB                            ; the low byte is zero
RENUM_REFS_SEARCH:
    STD 1,X
    STD BINVAL
    JSR FINDLN
RENUM_REFS_STORE:
    LDX TEMPTR
    BLO RENUM_REFS_MISSING
    LDD V47
    INC ,X+                         ; 1 becomes 2, or 0 becomes 1
    STD ,X
    BRA RENUM_REFS_SKIP
RENUM_REFS_NEW:
    CLR ,X                          ; and the carry
    LDX 1,X
    LDX 2,X                         ; the line's number
    STX V47
    BRA RENUM_REFS_STORE

;; Packs each line number after GOTO, GOSUB, THEN and ELSE, and those in ON ... GOTO and GOSUB lists, as 1, the
;; number's high byte, 1 or 2 when it is zero, the low byte, and 1 or 2, moving the program to fit.
RENUM_PACK:
    LDX TXTTAB
    BRA RENUM_PACK_START
RENUM_PACK_LINE:
    LDX CHARAD
    LEAX 1,X
RENUM_PACK_START:
    BSR PRGEND
    LEAX 2,X
RENUM_PACK_SKIP:
    LEAX 1,X
RENUM_PACK_AT:
    STX CHARAD
RENUM_PACK_NEXT:
    JSR GETNCH
RENUM_PACK_CHECK:
    TSTA
    BEQ RENUM_PACK_LINE
    BPL RENUM_PACK_NEXT             ; not a token
    LDX CHARAD
    CMPA #$FF
    BEQ RENUM_PACK_SKIP             ; a function: skip its second byte
    JSR RVEC22
    CMPA #TK_THEN
    BEQ RENUM_PACK_NUMBER
    CMPA #TK_ELSE
    BEQ RENUM_PACK_NUMBER
    CMPA #TK_GO
    BNE RENUM_PACK_NEXT
    JSR GETNCH
    CMPA #TK_TO
    BEQ RENUM_PACK_NUMBER
    CMPA #TK_SUB
    BNE RENUM_PACK_AT
RENUM_PACK_NUMBER:
    JSR GETNCH
    BLO RENUM_PACK_DIGITS
RENUM_PACK_ON:
    JSR GETCCH
    BRA RENUM_PACK_CHECK
RENUM_PACK_DIGITS:
    LDX CHARAD
    PSHS X
    JSR LINGET
    LDX CHARAD
RENUM_PACK_BACK:
    LDA ,-X
    JSR DIGCHK
    BLO RENUM_PACK_BACK             ; back to the last digit
    LEAX 1,X
    TFR X,D
    SUBB 1,S                        ; the digits' length
    SUBB #5
    BEQ RENUM_PACK_STORE
    BLO RENUM_PACK_ROOM             ; fewer than five
    LEAU ,X
    NEGB
    LEAX B,X
    JSR MOVPRG                      ; close up the extra digits
    BRA RENUM_PACK_STORE
RENUM_PACK_ROOM:
    STX V47
    LDX VARTAB
    STX V43
    NEGB
    LEAX B,X
    STX V41
    STX VARTAB
    JSR MOVEUP                      ; open up room for five
    LDX V45
    STX CHARAD
RENUM_PACK_STORE:
    PULS X
    LDA #1
    STA ,X
    STA 2,X
    STA 4,X
    LDB BINVAL
    BNE RENUM_PACK_LOW
    LDB #1
    INC 2,X
RENUM_PACK_LOW:
    STB 1,X
    LDB BINVAL+1
    BNE RENUM_PACK_DONE
    LDB #1
    INC 4,X
RENUM_PACK_DONE:
    STB 3,X
    JSR GETCCH
    CMPA #','
    BEQ RENUM_PACK_NUMBER           ; the next number in an ON list
    BRA RENUM_PACK_ON

;; Turns each packed reference back into its number's digits, moving the program to fit, and reports each
;; reference to a line that does not exist as UL number IN line.
RENUM_TEXT:
    LDX TXTTAB
    LEAX -1,X
RENUM_TEXT_LINE:
    LEAX 1,X
    LDD 2,X
    STD CURLIN                      ; for IN line
    JSR PRGEND
    LEAX 3,X
RENUM_TEXT_NEXT:
    LEAX 1,X
RENUM_TEXT_CHECK:
    LDA ,X
    BEQ RENUM_TEXT_LINE
    DECA
    BEQ RENUM_TEXT_NUMBER           ; 1
    SUBA #2
    BNE RENUM_TEXT_NEXT             ; not 3
    PSHS X
    LDX #RENUM_UL-1
    JSR STROUT1
    LDX ,S
    LDD 1,X
    JSR LINPRT
    JSR INPRT
    JSR PRNTCR
    PULS X
RENUM_TEXT_NUMBER:
    PSHS X
    LDD 1,X
    STD FPA0+2
    JSR GIVINT
    JSR FOUT
    PULS U
    LDB #5
RENUM_TEXT_COPY:
    LEAX 1,X                        ; past FOUT's sign
    LDA ,X
    BEQ RENUM_TEXT_CLOSE
    DECB
    STA ,U+
    BRA RENUM_TEXT_COPY
RENUM_TEXT_CLOSE:
    LEAX ,U
    TSTB
    BEQ RENUM_TEXT_CHECK
    LEAY ,U
    LEAU B,U
    JSR MOVPRG                      ; close up what the digits did not fill
    LEAX ,Y
    BRA RENUM_TEXT_CHECK

;; RENUM's message for a line that does not exist, ended by a zero.
RENUM_UL:
    .byte "UL ", 0

;; Runs the HEX$ function: a number from 0 to 65535 as hex digits, without leading zeros.
HEXDOL:
    JSR ADRCHK
    LDX #STRBUF+2
    LDB #4                          ; four digits
HEXDOL_DIGIT:
    PSHS B
    CLRB
    LDA #4
HEXDOL_SHIFT:
    ASL FPA0+3
    ROL FPA0+2
    ROLB                            ; the next four bits into B
    DECA
    BNE HEXDOL_SHIFT
    TSTB
    BNE HEXDOL_SHOW
    LDA ,S
    DECA
    BEQ HEXDOL_SHOW                 ; the last digit, even 0
    CMPX #STRBUF+2
    BEQ HEXDOL_NEXT                 ; a leading zero
HEXDOL_SHOW:
    ADDB #'0'
    CMPB #'9'
    BLS HEXDOL_STORE
    ADDB #'A' - '9' - 1
HEXDOL_STORE:
    STB ,X+
    CLR ,X
HEXDOL_NEXT:
    PULS B
    DECB
    BNE HEXDOL_DIGIT
    LEAS 2,S                        ; a string: return past the function call's number check
    LDX #STRBUF+1
    JMP STRLT2

;; Runs DLOAD and DLOADM: DLOAD["name"][,baud] loads a BASIC program in text from a host computer through the
;; serial port, as if its lines were typed; DLOADM["name"][,baud][,offset] loads a machine language file, as
;; CLOADM does. The baud is 0 for 300 or 1 for 1200, the default, and stays set.
;;
;; The program arrives through console in, as device -3, a block at a time from <DLOPEN>.
;;
;; Errors: ?FM ERROR when the file is not of the kind asked for; ?NE ERROR when the host has no such file
DLOAD:
    JSR CLSALL_CASSETTE
.if COCO3
    ; DLOAD is gone from the CoCo 3: it falls into RESET's routine, which takes its place

;; The CoCo 3's RESET: maps the whole internal ROM in, with the MMU off, and starts the machine at <COCO3RESET>.
;;
;; The 6809's RESET vector points here, so RESET works whatever the MMU had mapped: this part of the ROM is at
;; $8C1B in every mapping.
INTRESET:
    ORCC #$50                       ; no interrupts
    LDA #MC3+MC1
    STA INIT0                       ; 32K of internal ROM, the MMU off, not CoCo compatible
    CLR SAMREG+$1E                  ; the ROM in: the SAM's map type cleared
    JMP COCO3RESET

;; Starts a ROM pack from its FIRQ: marks the GIME's interrupt vectors invalid and turns off the cartridge's
;; interrupt, then maps the cartridge's ROM in as <CARTROM> does. <CARTST> calls it.
CARTFIRQ:
    CLR INT_FLAG                    ; the vectors at $FEEE must be set up again
    CLR PIA1+3                      ; CB1's interrupt off
;; Maps a ROM pack in: the internal ROM at $8000-$BFFF and the cartridge's at $C000-$FDFF, with the MMU on and
;; the constant page at $FE00, and the ROM in place of RAM.
CARTROM:
    LDA #COCO+MMUEN+MC3+MC2
    STA INIT0
    CLR SAMREG+$1E                  ; the ROM in: the SAM's map type cleared
    RTS

;; The screen's character output, which start-up patches into <SCRCHR>: on a hi-res text screen it prints there,
;; through <PUTCHR20>, and otherwise goes on as <SCRCHR> does.
;;
;; In:   A = the character
PUTCHR3:
    PSHS A,B,X
    LDX CURPOS
    LDB HRWIDTH
    LBNE PUTCHR20                   ; a hi-res text screen
    LDB 1,S                         ; B as it came
    JMP SCRCHR_SAVED

;; CLS, which start-up patches in after <CLS>'s hook: on a hi-res text screen it clears that screen through
;; <CLS20>, and otherwise goes on as <CLS> does.
;;
;; In:   zero = set when CLS has no color
CLS3:
    PSHS CC
    TST HRWIDTH
    BEQ CLS3_LORES
    JMP CLS20                       ; a hi-res text screen
CLS3_LORES:
    PULS CC
    JMP CLS_HOOKED
    NOP
    .byte <NAMEND_CHECK             ; the last byte of 1.1's JSR NAMEND_CHECK, left in place
.else
DLOAD_KIND:
.if VERSION = 10
    CLR ,-S                         ; not DLOADM
    CMPA #'M'
    BNE DLOAD_NAME
    STA ,S
.else
    JSR GETCCH
    SUBA #'M'
    PSHS A                          ; zero for DLOADM
    BNE DLOAD_NAME
.endif
    JSR GETNCH
DLOAD_NAME:
    JSR GETNAM
    JSR GETCCH
    BEQ DLOAD_OPEN
    JSR SYNCOM
    CMPA #','
    BEQ DLOAD_OPEN                  ; no baud
    JSR GETBYT
    LDA #$B0                        ; 300 baud
    TSTB
    BEQ DLOAD_BAUD
    LDA #$2C                        ; 1200 baud
    DECB
    LBNE FCERR
DLOAD_BAUD:
    STA DLBAUD
DLOAD_OPEN:
    JSR DLOPEN
    PSHS A
    LDA #$FD
    STA DEVNUM                      ; DLOAD's device, -3
    PULS A
    TST ,S+
.if VERSION = 10
    BNE XCLOAD_TYPE                 ; DLOADM
.else
    BEQ XCLOAD_TYPE                 ; DLOADM
.endif
    JSR NAMEND_CHECK
.endif
    TSTB
    BEQ DLOAD_FM                    ; not text
    JSR ERASEP
    JMP MAINLP                      ; the lines come in as typed lines
DLOAD_FM:
    JMP FMERR

;; Runs CLOAD, and CLOADM: a machine language file saved without gaps goes to Color BASIC's CLOADM, and one saved
;; in blocks with gaps is read here, as <XCLOAD_TYPE> reads DLOADM's.
XCLOAD:
    JSR GETNCH
    CMPA #'M'
    LBNE CLOAD
    CLR FILSTA
    JSR GETNCH
    JSR GETNAM
    JSR FINDFL
    TST CASBUF+10                   ; the gap flag
    LBEQ CLOADM_OFFSET
    LDU CASBUF+8                    ; the type and text flag
    DEC DEVNUM                      ; the cassette, -1
    JSR RDDATA
    TFR U,D
;; Loads a machine language file through console in: records of a zero, a length and an address, then the bytes,
;; until one of $FF, an unused length and the address to run, which goes in <EXECJP>. Each address is offset by
;; the number after a comma, if there is one.
;;
;; In:   A = the file's type, B = its text flag
;; Errors: ?FM ERROR unless it is binary machine language; ?IO ERROR when a byte does not stay in RAM
XCLOAD_TYPE:
    SUBD #$0200                     ; machine language, binary
    BNE DLOAD_FM
    LDX ZERO
    JSR GETCCH
    BEQ XCLOAD_OFFSET
    JSR SYNCOM
    JSR GETADR
XCLOAD_OFFSET:
    STX VD3
    JSR NAMEND_CHECK
XCLOAD_RECORD:
    BSR BINBYTE
    PSHS A                          ; 0 data, $FF the end
    BSR BINWORD
    TFR D,Y                         ; the length
    BSR BINWORD
    ADDD VD3
    STD EXECJP
    TFR D,X
    LDA ,S+
    LBNE CLSONE                     ; the end: the address is where to run
XCLOAD_BYTE:
    BSR BINBYTE
    STA ,X
    CMPA ,X+
    BNE BINBYTE_IO
    LEAY -1,Y
    BNE XCLOAD_BYTE
    BRA XCLOAD_RECORD

;; Reads a 16-bit word through console in, high byte first.
;;
;; Out:  D = the word
BINWORD:
    BSR BINBYTE_SWAP
BINBYTE_SWAP:
    BSR BINBYTE
    EXG A,B
BINBYTE_DONE:
    RTS

;; Reads a byte through console in.
;;
;; Out:  A = the byte
;; Errors: ?IO ERROR at the file's end
BINBYTE:
    JSR CONIN
    TST CINBFL
    BEQ BINBYTE_DONE
BINBYTE_IO:
    JMP IOERR

;; Asks the host for the file named in <CFNBUF> and reads its first block.
;;
;; Out:  A = the file's type, B = its text flag
;; Errors: ?NE ERROR when the host has no such file
DLOPEN:
    BSR DLFILE
    PSHS A,B
    INCA
    BEQ DLOPEN_NE                   ; type $FF: not found
    LDU ZERO                        ; block 0
    BSR DLBLOCK
    PULS A,B,PC
DLOPEN_NE:
    LDB #ERR_NE
    JMP ERROR

;; Reads the next block of the file into the cassette buffer, for console in.
DLNEXT:
    LDU CBUFAD                      ; its number
;; Reads a block of the file into the cassette buffer, and sets the buffer's count and pointer for console in.
;;
;; In:   U = the block's number
DLBLOCK:
    LEAX 1,U
    STX CBUFAD                      ; the next one's number
    LDX #CASBUF
    JSR DLREAD
    JMP RDDATA_COUNT

;; The console in hook: on DLOAD's device, -3, takes the next character from the buffer, reading the next block
;; when it empties; <CINBFL> is set when the file has ended.
;;
;; Out:  A = the character
XVEC4:
    LDA DEVNUM
    CMPA #$FD
    BNE XVEC4_DONE
    LEAS 2,S                        ; return from <CONIN> with the character
    CLR CINBFL
    TST CINCTR
    BNE XVEC4_CHAR
    COM CINBFL                      ; nothing left: the end
XVEC4_DONE:
    RTS
XVEC4_CHAR:
    PSHS B,X,Y,U
    LDX CINPTR
    LDA ,X+
    PSHS A
    STX CINPTR
    DEC CINCTR
    BNE XVEC4_RETURN
    BSR DLNEXT
XVEC4_RETURN:
    PULS A,B,X,Y,U,PC

;; Asks the host for a file: sends $8A, which the host echoes, then the name and a checksum, which the host
;; acknowledges with $C8, then reads the file's type and text flag and their checksum. Each step is tried again
;; when it fails, up to five times.
;;
;; Out:  A = the file's type, $FF when there is no such file; B = its text flag
;; Errors: ?IO ERROR after five failures
DLFILE:
    CLRA
    PSHS A,B,X                      ; the tries, the checksum, then the type and text flag
    LEAY ,S
    BRA DLFILE_ASK
DLFILE_RETRY:
    BSR DLRETRY
DLFILE_ASK:
    LDA #$8A
    BSR DLSEND
    BNE DLFILE_RETRY
    LDX #CFNBUF+1
DLFILE_NAME:
    LDA ,X+
    JSR RSOUTSUM
    CMPX #CFNBUF+9
    BNE DLFILE_NAME
    BSR DLSUM
    BNE DLFILE_RETRY
    BSR DLRECV
    BNE DLFILE_RETRY
    STA 2,Y                         ; the type
    BSR DLRECV
    BNE DLFILE_RETRY
    STA 3,Y                         ; the text flag
    BSR DLCHECK
    BNE DLFILE_RETRY
    LEAS 2,S
    PULS A,B,PC

;; Counts a failed try; after five, tells the host to stop with $BC.
;;
;; In:   Y = the transfer's frame
;; Errors: ?IO ERROR after five failures
DLRETRY:
    INC ,Y
    LDA ,Y
    CMPA #5
    BLO DLSUM_DONE
    LDA #$BC
    JSR RSOUT
    JMP IOERR

;; Sends a byte and waits for the host to echo it.
;;
;; In:   A = the byte
;; Out:  zero = set when the echo matches
DLSEND:
    PSHS A
    BSR DLXFER
    BNE DLSEND_DONE                 ; no answer
    CMPA ,S
DLSEND_DONE:
    PULS A,PC

;; Sends the checksum and waits for the host's $C8.
;;
;; Out:  zero = set when it came
DLSUM:
    LDA 1,Y
    BSR DLXFER
    BNE DLSUM_DONE
    CMPA #$C8
DLSUM_DONE:
    RTS

;; Reads the host's checksum and checks it against the bytes read.
;;
;; Out:  A = zero, and zero = set, when they agree
DLCHECK:
    BSR DLRECV
    BNE DLSUM_DONE
    LDA 1,Y
    RTS

;; Reads a byte, adding it to the checksum.
;;
;; Out:  A = the byte, zero = clear when it timed out
DLRECV:
    BSR RSIN
    PSHS CC,A
    EORA 1,Y
    STA 1,Y
    PULS CC,A,PC

;; Reads a 128-byte block of the file: sends $97, which the host echoes, then the block's number as two 7-bit bytes
;; and a checksum, then reads the count of the block's bytes the file uses, the 128 bytes and their checksum. Each
;; step is tried again when it fails, up to five times.
;;
;; In:   U = the block's number, X = where it goes
;; Out:  A = the bytes of it the file uses
;; Errors: ?IO ERROR after five failures
DLREAD:
    CLRA
    PSHS A,B,X,Y,U
    ASL 7,S
    ROL 6,S
    LSR 7,S                         ; seven bits in each byte
    LEAY ,S
    BRA DLREAD_ASK
DLREAD_RETRY:
    BSR DLRETRY
DLREAD_ASK:
    LDA #$97
    BSR DLSEND
    BNE DLREAD_RETRY
    LDA 6,Y
    BSR RSOUTSUM
    LDA 7,Y
    BSR RSOUTSUM
    BSR DLSUM
    BNE DLREAD_RETRY
    BSR DLRECV
    BNE DLREAD_RETRY
    STA 4,Y                         ; the count
    LDX 2,Y
    LDB #128
DLREAD_BYTE:
    BSR DLRECV
    BNE DLREAD_RETRY
    STA ,X+
    DECB
    BNE DLREAD_BYTE
    BSR DLCHECK
    BNE DLREAD_RETRY
    LEAS 4,S
    PULS A,B,X,PC                   ; A = the count

;; Sends a byte, starting a new checksum, then reads the answer.
;;
;; In:   A = the byte
DLXFER:
    CLR 1,Y
    BSR RSOUT
;; Reads a byte from the serial port, at <DLBAUD>: waits for the line to go idle, then for a start bit, then takes
;; eight bits, low bit first, in the middle of each. Interrupts are masked meanwhile.
;;
;; Out:  A = the byte, zero = clear when nothing came within <TIMOUT>'s wait
RSIN:
    CLRA                            ; zero set, for the flags restored
    PSHS CC,B,X
    ORCC #$50
    LDA TIMOUT
    LDX ZERO
RSIN_IDLE:
    BSR RSIN_SAMPLE
    BHS RSIN_IDLE                   ; wait for a mark
RSIN_START:
    BSR RSIN_SAMPLE
    BLO RSIN_START                  ; then for the start bit
    BSR RSHALF                      ; to the middle of it
    LDB #$01
    PSHS B                          ; the bit
    CLRA
RSIN_BIT:
    BSR RSBIT
    LDB PIA1+2
    RORB                            ; the serial input
    BHS RSIN_NEXT
    ORA ,S
RSIN_NEXT:
    ASL ,S
    BHS RSIN_BIT
    LEAS 1,S
    PULS CC,B,X,PC

;; Samples the serial input, counting down the timeout.
;;
;; Out:  carry = the input
RSIN_SAMPLE:
    LDB PIA1+2
    RORB
    LEAX 1,X
    BNE RSIN_SAMPLE_DONE
    DECA
    BNE RSIN_SAMPLE_DONE
    LEAS 2,S                        ; timed out: return from RSIN
    PULS CC,B,X
    INCA                            ; zero clear
RSIN_SAMPLE_DONE:
    RTS

;; Waits one bit's time at <DLBAUD>.
RSBIT:
    BSR RSHALF
;; Waits half a bit's time at <DLBAUD>.
RSHALF:
    PSHS A
    LDA DLBAUD
RSHALF_WAIT:
    BRN RSHALF_WAIT                 ; for the time it takes
    DECA
    BNE RSHALF_WAIT
    PULS A,PC

;; Sends a byte, adding it to the checksum.
;;
;; In:   A = the byte
RSOUTSUM:
    PSHS A
    EORA 1,Y
    STA 1,Y
    PULS A
;; Sends a byte through the serial port, at <DLBAUD>: two bits' time of mark, a start bit, then eight bits, low
;; bit first, and a stop bit. Interrupts are masked meanwhile.
;;
;; In:   A = the byte
RSOUT:
    PSHS CC,A,B
    ORCC #$50
    BSR RSBIT
    BSR RSBIT
    CLR PIA1                        ; the start bit
    BSR RSBIT
    LDB #$01
    PSHS B                          ; the bit
RSOUT_BIT:
    LDA 2,S
    ANDA ,S
    BEQ RSOUT_LEVEL
    LDA #$02                        ; bit 1, serial output
RSOUT_LEVEL:
    STA PIA1
    BSR RSBIT
    ASL ,S
    BHS RSOUT_BIT
    LDA #$02
    STA PIA1                        ; the stop bit
    LEAS 1,S
    PULS CC,A,B,PC
;; PRINT USING's ! field: the string's first character.
USING_ONE:
    LDA #1
    STA VD9                         ; the field's width
;; Prints a string item in a field of VD9 characters: its first characters, padded with spaces.
;;
;; In:   B = the format's characters left, before this field's last
USING_STRING:
    DECB
    JSR USING_PLUS
    JSR GETCCH
    LBEQ USING_LINE                 ; no more items
    STB VD3
    JSR FRMEVL
    JSR CKSTR
    LDX FPA0+2
    STX V4D
    LDB VD9
    JSR LEFT_START                  ; no more than the field holds
    JSR STRPRT
    LDX FPA0+2
    LDB VD9
    SUBB ,X                         ; the spaces to pad with
USING_PAD:
    DECB
    LBMI USING_NEXT
    JSR OUTSPC
    BRA USING_PAD

;; PRINT USING's %spaces% field: as many characters as the field is wide, the two % signs included. A % without
;; its closing % is printed as itself.
USING_SPACES:
    STB VD3
    STX TEMPTR
    LDA #2
    STA VD9
USING_SPACES_NEXT:
    LDA ,X
    CMPA #'%'
    BEQ USING_STRING
    CMPA #' '
    BNE USING_SPACES_NONE
    INC VD9
    LEAX 1,X
    DECB
    BNE USING_SPACES_NEXT
USING_SPACES_NONE:
    LDX TEMPTR
    LDB VD3
    LDA #'%'
;; Prints a format character that is not part of a field.
USING_LITERAL:
    JSR USING_PLUS
    JSR PUTCHR
    BRA USING_FIELD

;; The PRINT hook: PRINT USING goes to <USING>.
;;
;; In:   A = the character after PRINT
XVEC9:
    CMPA #TK_USING
    BEQ USING
    RTS

;; Runs PRINT USING format$;items: prints each item in the next field of the format, and the format's other
;; characters as they are, starting the format again when it runs out and items are left. The fields are:
;;
;; - ! the first character of a string, and %spaces% as many characters as it is wide;
;; - # for each digit, with . for the point and , anywhere left of it for commas every three digits;
;; - ** before the digits to fill with asterisks, $$ for a dollar sign just left of the digits, and **$ for both;
;; - + before or after the digits for the number's sign, - after them for a sign only when negative;
;; - ^^^^ after the digits for an exponent.
;;
;; A number too wide for its field is printed with % before it. <VDA> holds the field's flags: bit 6 commas, bit 5
;; asterisks, bit 4 a dollar sign, bit 3 a sign before, bit 2 a sign after, bit 0 an exponent; <VD9> and <VD8>
;; count the places left and right of the point.
;;
;; Errors: ?FC ERROR for an empty format, one with no field and items left, or a field of more than 16 digits
USING:
    LEAS 2,S                        ; never return to PRINT
    JSR FRMEVL_START
    JSR CKSTR
    LDB #';'
    JSR SYNCHR
    LDX FPA0+2
    STX VD5                         ; the format
    BRA USING_FORMAT
USING_AGAIN:
    LDA VD7
    BEQ USING_FC                    ; the last item had no comma or semicolon
    LDX VD5
USING_FORMAT:
    CLR VD7
    LDB ,X
    BNE USING_TEXT
USING_FC:
    JMP FCERR
USING_TEXT:
    LDX 2,X
USING_FIELD:
    CLR VDA
USING_CHAR:
    CLR VD9
    LDA ,X+
    CMPA #'!'
    LBEQ USING_ONE
    CMPA #'#'
    BEQ USING_NUMBER
    DECB
    BNE USING_PLUSSIGN
    JSR USING_PLUS                  ; the format's last character
    JSR PUTCHR
USING_END:
    JSR GETCCH
    BNE USING_AGAIN                 ; items left: the format again
    LDA VD7
USING_LINE:
    BNE USING_FREE                  ; it ended with a comma or semicolon
    JSR PRNTCR
USING_FREE:
    LDX VD5
    JMP FRETMP
USING_PLUSSIGN:
    CMPA #'+'
    BNE USING_OTHER
    JSR USING_PLUS                  ; an earlier + was not a sign
    LDA #$08
    STA VDA                         ; a sign before the number
    BRA USING_CHAR
USING_OTHER:
    CMPA #'.'
    BEQ USING_POINT
    CMPA #'%'
    LBEQ USING_SPACES
    CMPA ,X                         ; two the same?
USING_PAIR:
    BNE USING_LITERAL
    CMPA #'$'
    BEQ USING_DOLLAR
    CMPA #'*'
    BNE USING_PAIR                  ; not **: a character
    LDA VDA
    ORA #$20                        ; asterisks
    STA VDA
    CMPB #2
    BLO USING_SECOND
    LDA 1,X
    CMPA #'$'
    BNE USING_SECOND
    DECB                            ; **$
    LEAX 1,X
    INC VD9
USING_DOLLAR:
    LDA VDA
    ORA #$10                        ; a dollar sign
    STA VDA
USING_SECOND:
    LEAX 1,X
    INC VD9
USING_NUMBER:
    CLR VD8
USING_LEFT:
    INC VD9
    DECB
    BEQ USING_SIGN
    LDA ,X+
    CMPA #'.'
    BEQ USING_RIGHT
    CMPA #'#'
    BEQ USING_LEFT
    CMPA #','
    BNE USING_EXP
    LDA VDA
    ORA #$40                        ; commas
    STA VDA
    BRA USING_LEFT
USING_POINT:
    LDA ,X
    CMPA #'#'
    LBNE USING_LITERAL              ; a point without a digit after it
    LDA #1
    STA VD8
    LEAX 1,X
USING_RIGHT:
    INC VD8
    DECB
    BEQ USING_SIGN
    LDA ,X+
    CMPA #'#'
    BEQ USING_RIGHT
USING_EXP:
    CMPA #'^'
    BNE USING_SIGN
    CMPA ,X
    BNE USING_SIGN
    CMPA 1,X
    BNE USING_SIGN
    CMPA 2,X
    BNE USING_SIGN
    CMPB #4
    BLO USING_SIGN
    SUBB #4
    LEAX 4,X
    INC VDA                         ; an exponent
USING_SIGN:
    LEAX -1,X
    INC VD9
    LDA VDA
    BITA #$08
    BNE USING_ITEM                  ; the sign goes before
    DEC VD9
    TSTB
    BEQ USING_ITEM
    LDA ,X
    SUBA #'-'
    BEQ USING_TRAIL                 ; - after: a sign after when negative
    CMPA #$FE                       ; '+', less '-'
    BNE USING_ITEM
    LDA #$08                        ; + after: a sign after, always
USING_TRAIL:
    ORA #$04
    ORA VDA
    STA VDA
    DECB
USING_ITEM:
    JSR GETCCH
    LBEQ USING_LINE                 ; no more items
    STB VD3
    JSR FRMNUM
    LDA VD9
    ADDA VD8
    CMPA #17
    LBHI FCERR                      ; more than 16 places
    JSR PUFOUT
    LEAX -1,X
    JSR STROUT1
USING_NEXT:
    CLR VD7
    JSR GETCCH
    BEQ USING_RESUME
    STA VD7
    CMPA #';'
    BEQ USING_SEMI
    JSR SYNCOM
    BRA USING_RESUME
USING_SEMI:
    JSR GETNCH
USING_RESUME:
    LDX VD5
    LDB ,X
    SUBB VD3
    LDX 2,X
    ABX                             ; the format where this field ended
    LDB VD3
    LBNE USING_FIELD
    JMP USING_END

;; Prints a + that turned out not to start a number's field.
USING_PLUS:
    PSHS A
    LDA #'+'
    TST VDA
    BEQ USING_PLUS_DONE
    JSR PUTCHR
USING_PLUS_DONE:
    PULS A,PC
;; Formats FPA0 for a PRINT USING number field, as <VDA>, <VD9> and <VD8> describe it, in the string buffer from
;; <STRBUF>+4: the sign or a space, then the digits with the point, commas, dollar sign, fill and exponent the
;; field asks for. A number too wide for the field, or of a billion or more without an exponent, gets % before it.
;;
;; Out:  X = the text, from <STRBUF>+3 or after
PUFOUT:
    LDU #STRBUF+4
    LDB #' '
    LDA VDA
    BITA #$08
    BEQ PUFOUT_SIGN
    LDB #'+'                        ; the sign goes before
PUFOUT_SIGN:
    TST FP0SGN
    BPL PUFOUT_STORE
    CLR FP0SGN
    LDB #'-'
PUFOUT_STORE:
    STB ,U+
    LDB #'0'                        ; room for a leading digit
    STB ,U+
    ANDA #$01
    LBNE PUFOUT_EXP
    LDX #FBILN
    JSR FCOMP_SAME
    BMI PUFOUT_FIXED                ; below a billion
    JSR FOUT                        ; too big: as PRINT shows it
PUFOUT_END:
    LDA ,X+
    BNE PUFOUT_END
PUFOUT_OVER:
    LDA ,-X                         ; move it right one
    STA 1,X
    CMPX #STRBUF+3
    BNE PUFOUT_OVER
    LDA #'%'
    STA ,X
    RTS
PUFOUT_FIXED:
    LDA FP0EXP
    STA V47
    BEQ PUFOUT_SCALED               ; zero
    JSR PUSCALE
PUFOUT_SCALED:
    LDA V47
    LBMI PUFOUT_SMALL               ; a fraction
    NEGA
    ADDA VD9
    SUBA #9
    JSR ZEROS                       ; leading zeros, for a field wider than the digits
    JSR PUCOUNT
    JSR PUDIGS
    LDA V47
    JSR PUZEROS                     ; zeros before the point
    LDA V47
    JSR PUPOINT
    LDA VD8
    BNE PUFOUT_RIGHT
    LEAU -1,U                       ; no digits after the point: no point
PUFOUT_RIGHT:
    DECA
    JSR ZEROS                       ; zeros after the point
PUFOUT_FINISH:
    JSR PUFILL
    TSTA
    BEQ PUFOUT_TRIM
    CMPB #'*'
    BEQ PUFOUT_TRIM
    STB ,U+                         ; the sign after
PUFOUT_TRIM:
    CLR ,U
    LDX #STRBUF+3
PUFOUT_LEAD:
    LEAX 1,X
    STX TEMPTR
    LDA VARPTR+1                    ; where the point is,
    SUBA TEMPTR+1
    SUBA VD9                        ;   less the places before it: zero at the field's start
    BEQ PUFOUT_DONE
    LDA ,X
    CMPA #' '
    BEQ PUFOUT_LEAD
    CMPA #'*'
    BEQ PUFOUT_LEAD
    CLRA                            ; the end of what is kept
PUFOUT_SIGNS:
    PSHS A
    LDA ,X+
    CMPA #'-'
    BEQ PUFOUT_SIGNS
    CMPA #'+'
    BEQ PUFOUT_SIGNS
    CMPA #'$'
    BEQ PUFOUT_SIGNS
    CMPA #'0'
    BNE PUFOUT_TOOWIDE
    LDA 1,X
    BSR DIGCHK
    BLO PUFOUT_TOOWIDE
PUFOUT_PUTBACK:
    PULS A                          ; drop a leading zero: the signs move over it
    STA ,-X
    BNE PUFOUT_PUTBACK
    BRA PUFOUT_LEAD
PUFOUT_TOOWIDE:
    PULS A
    TSTA
    BNE PUFOUT_TOOWIDE
    LDX TEMPTR
    LDA #'%'
    STA ,-X
PUFOUT_DONE:
    RTS

;; Checks for a decimal digit.
;;
;; In:   A = the character
;; Out:  carry = clear for a digit
DIGCHK:
    CMPA #'0'
    BLO DIGCHK_DONE
    SUBA #'9' + 1
    SUBA #-('9' + 1) & $FF          ; back to the character, the carry set above '9'
DIGCHK_DONE:
    RTS

PUFOUT_SMALL:
    LDA VD8
    BEQ PUFOUT_SMALL_ADD
    DECA
PUFOUT_SMALL_ADD:
    ADDA V47
    BMI PUFOUT_SMALL_SHIFT
    CLRA
PUFOUT_SMALL_SHIFT:
    PSHS A
PUFOUT_SMALL_DIV:
    BPL PUFOUT_SMALL_DIGITS
    PSHS A
    JSR DIV10                       ; drop the digits the field has no room for
    PULS A
    INCA
    BRA PUFOUT_SMALL_DIV
PUFOUT_SMALL_DIGITS:
    LDA V47
    SUBA ,S+
    STA V47
    ADDA #9
    BMI PUFOUT_TINY
    LDA VD9
    SUBA #9
    SUBA V47
    BSR ZEROS
    JSR PUCOUNT
    BRA PUFOUT_DIGITS

ZEROS_ONE:
    PSHS A
    LDA #'0'
    STA ,U+
    PULS A
;; Puts zeros in the buffer.
;;
;; In:   A = how many, U = where
ZEROS:
    DECA
    BPL ZEROS_ONE
    RTS

PUFOUT_TINY:
    LDA VD9
    BSR ZEROS
    JSR PUPOINT_HERE
    LDA #$F7
    SUBA V47
    BSR ZEROS                       ; the zeros after the point
    CLR V45
    CLR VD7
PUFOUT_DIGITS:
    JSR PUDIGS
    LDA VD8
    BNE PUFOUT_DIGITS_RIGHT
    LDU VARPTR                      ; no digits after the point: drop it
PUFOUT_DIGITS_RIGHT:
    ADDA V47
    LBRA PUFOUT_RIGHT

;; Formats an exponent field: the digits scaled to fill the places, then E, the exponent's sign and two digits.
PUFOUT_EXP:
    LDA FP0EXP
    PSHS A
    BEQ PUFOUT_EXP_PLACES           ; zero
    JSR PUSCALE
PUFOUT_EXP_PLACES:
    LDA VD8
    BEQ PUFOUT_EXP_ADD
    DECA
PUFOUT_EXP_ADD:
    ADDA VD9
    CLR STRBUF+3
    LDB VDA
    ANDB #$04
    BNE PUFOUT_EXP_SIGN
    COM STRBUF+3                    ; no sign after: one place less
PUFOUT_EXP_SIGN:
    ADDA STRBUF+3
    SUBA #9
    PSHS A
PUFOUT_EXP_DIV:
    BPL PUFOUT_EXP_POINT
    PSHS A
    JSR DIV10
    PULS A
    INCA
    BRA PUFOUT_EXP_DIV
PUFOUT_EXP_POINT:
    LDA ,S
    BMI PUFOUT_EXP_LEFT
    CLRA
PUFOUT_EXP_LEFT:
    NEGA
    ADDA VD9
    INCA
    ADDA STRBUF+3
    STA V45                         ; the digits before the point
    CLR VD7                         ; no commas
    JSR PUDIGS
    PULS A
    JSR PUZEROS
    LDA VD8
    BNE PUFOUT_EXP_VALUE
    LEAU -1,U
PUFOUT_EXP_VALUE:
    LDB ,S+
    BEQ PUFOUT_EXP_SHOW             ; zero: E+00
    LDB V47
    ADDB #9
    SUBB VD9
    SUBB STRBUF+3
PUFOUT_EXP_SHOW:
    LDA #'+'
    TSTB
    BPL PUFOUT_EXP_DIGITS
    LDA #'-'
    NEGB
PUFOUT_EXP_DIGITS:
    STA 1,U
    LDA #'E'
    STA ,U++
    LDA #'0' - 1
PUFOUT_EXP_TENS:
    INCA
.if VERSION = 10
    SUBB #12                        ; 1.0 divides by 12 here, so exponents from 10 show wrongly
    BHS PUFOUT_EXP_TENS
    ADDB #'0' + 12
.else
    SUBB #10
    BHS PUFOUT_EXP_TENS
    ADDB #'0' + 10
.endif
    STD ,U++
    CLR ,U
    JMP PUFOUT_FINISH

;; Fills the field's leading zeros with spaces, or with asterisks for **, and puts the dollar sign and a sign before
;; the digits.
;;
;; Out:  A = nonzero when the sign goes after the digits, B = the sign or the fill
PUFILL:
    LDX #STRBUF+4
    LDB ,X                          ; the sign
    PSHS B
    LDA #' '
    LDB VDA
    BITB #$20
    PULS B
    BEQ PUFILL_START
    LDA #'*'
    CMPB #' '
    BNE PUFILL_START
    TFR A,B                         ; a positive number's space is filled too
PUFILL_START:
    PSHS B
PUFILL_NEXT:
    STA ,X+
    LDB ,X
    BEQ PUFILL_ZERO
    CMPB #'E'
    BEQ PUFILL_ZERO
    CMPB #'0'
    BEQ PUFILL_NEXT
    CMPB #','
    BEQ PUFILL_NEXT
    CMPB #'.'
    BNE PUFILL_DOLLAR
PUFILL_ZERO:
    LDA #'0'                        ; all zeros: keep one
    STA ,-X
PUFILL_DOLLAR:
    LDA VDA
    BITA #$10
    BEQ PUFILL_SIGN
    LDB #'$'
    STB ,-X
PUFILL_SIGN:
    ANDA #$04
    PULS B
    BNE PUFILL_DONE
    STB ,-X
PUFILL_DONE:
    RTS

;; Scales FPA0 to nine digits before its point, between 99999999.9 and 999999999, counting the powers of ten in
;; <V47>.
PUSCALE:
    PSHS U
    CLRA
PUSCALE_BIG:
    STA V47
    LDB FP0EXP
    CMPB #$80
    BHI PUSCALE_HIGH                ; 1 or more
    LDX #FBILN
    JSR FMULX                       ; times a billion
    LDA V47
    SUBA #9
    BRA PUSCALE_BIG
PUSCALE_DIV:
    JSR DIV10
    INC V47
PUSCALE_HIGH:
    LDX #FMAX10
    JSR FCOMP_SAME
    BGT PUSCALE_DIV
PUSCALE_LOW:
    LDX #FMAX9
    JSR FCOMP_SAME
    BGT PUSCALE_DONE
    JSR MUL10
    DEC V47
    BRA PUSCALE_LOW
PUSCALE_DONE:
    PULS U,PC

;; Rounds FPA0 to a whole number and puts its nine digits in the buffer, with the point and commas as <PUPOINT>
;; counts them, as <FOUT> does.
;;
;; In:   U = where
PUDIGS:
    PSHS U
    JSR ADDHLF
    JSR QINT
    PULS U
    LDX #FPWRTB
    LDB #$80                        ; subtracting
PUDIGS_NEXT:
    BSR PUPOINT
PUDIGS_ADD:
    LDA FPA0+3
    ADDA 3,X
    STA FPA0+3
    LDA FPA0+2
    ADCA 2,X
    STA FPA0+2
    LDA FPA0+1
    ADCA 1,X
    STA FPA0+1
    LDA FPA0
    ADCA ,X
    STA FPA0
    INCB
    RORB
    ROLB                            ; overflow: the sign changed
    BVC PUDIGS_ADD
    BHS PUDIGS_DIGIT
    SUBB #11
    NEGB
PUDIGS_DIGIT:
    ADDB #'0' - 1
    LEAX 4,X
    TFR B,A
    ANDA #$7F
    STA ,U+
    COMB
    ANDB #$80
    CMPX #FPWRTB + 9 * 4
    BNE PUDIGS_NEXT
    CLR ,U
;; Counts a digit toward the point, putting the point there, and a comma every three digits when there are commas.
PUPOINT:
    DEC V45
    BNE PUPOINT_COMMA
;; Puts the point in the buffer, keeping where it is in <VARPTR>.
PUPOINT_HERE:
    STU VARPTR
    LDA #'.'
    STA ,U+
    CLR VD7                         ; no commas after the point
    RTS
PUPOINT_COMMA:
    DEC VD7
    BNE PUPOINT_DONE
    LDA #3
    STA VD7
    LDA #','
    STA ,U+
PUPOINT_DONE:
    RTS

;; Starts the counts for <PUPOINT>: the digits before the point, and when there are commas, where the first comma
;; goes.
PUCOUNT:
    LDA V47
    ADDA #10
    STA V45
    INCA
PUCOUNT_MOD:
    SUBA #3
    BHS PUCOUNT_MOD
    ADDA #5
    STA VD7
    LDA VDA
    ANDA #$40
    BNE PUCOUNT_DONE
    STA VD7                         ; no commas
PUCOUNT_DONE:
    RTS

PUZEROS_ONE:
    PSHS A
    BSR PUPOINT
    PULS A
;; Puts zeros in the buffer, counting them toward the point as <PUPOINT> does.
;;
;; In:   A = how many
PUZEROS:
    DECA
    BMI PUZEROS_DONE
    PSHS A
    LDA #'0'
    STA ,U+
    LDA ,S+
    BNE PUZEROS_ONE
PUZEROS_DONE:
    RTS
;; Finds the routine that turns a point into its byte and pixel mask for the current PMODE.
;;
;; Out:  U = the routine
PIXRTN:
    LDU #PIXTAB
    LDA PMODE
    ASLA
    LDU A,U
    RTS

;; Finds the byte and pixel mask of the point <HORBEG>, <VERBEG> on the graphics page.
;;
;; Out:  X = the byte, A = the pixel's bits
PIXADR:
    BSR PIXRTN
    JMP ,U

;; The routines <PIXADR> uses, for each PMODE: the two-color modes 0, 2 and 4 have eight pixels a byte, the
;; four-color modes 1 and 3 four.
PIXTAB:
    .dbyt PIXADR2
    .dbyt PIXADR4
    .dbyt PIXADR2
    .dbyt PIXADR4
    .dbyt PIXADR2

;; Finds a point's byte and mask in a two-color mode.
;;
;; Out:  X = the byte, A = the pixel's bit
PIXADR2:
    PSHS B,U
    LDB HORBYT
    LDA VERBEG+1
    MUL
    ADDD BEGGRP
    TFR D,X                         ; the row
    LDB HORBEG+1
    LSRB
    LSRB
    LSRB
    ABX                             ; eight pixels a byte
    LDA HORBEG+1
    ANDA #$07
    LDU #PIXMASK2
    LDA A,U
    PULS B,U,PC

;; Finds a point's byte and mask in a four-color mode.
;;
;; Out:  X = the byte, A = the pixel's two bits
PIXADR4:
    PSHS B,U
    LDB HORBYT
    LDA VERBEG+1
    MUL
    ADDD BEGGRP
    TFR D,X
    LDB HORBEG+1
    LSRB
    LSRB
    ABX                             ; four pixels a byte
    LDA HORBEG+1
    ANDA #$03
    LDU #PIXMASK4
    LDA A,U
    PULS B,U,PC

;; The pixels' bits in a byte, left to right, in the two-color modes and in the four-color modes.
PIXMASK2:
    .byte $80, $40, $20, $10, $08, $04, $02, $01
PIXMASK4:
    .byte $C0, $30, $0C, $03

;; Moves a pixel's byte down a row.
;;
;; In:   X = the byte
PIXDOWN:
    LDB HORBYT
    ABX
    RTS

;; Moves a pixel right one, in a two-color mode.
;;
;; In:   X = the byte, A = the pixel's bit
PIXRIGHT2:
    LSRA
    BHS PIXRIGHT2_DONE
    RORA                            ; $80, in the next byte
PIXRIGHT2_BYTE:
    LEAX 1,X
PIXRIGHT2_DONE:
    RTS

;; Moves a pixel right one, in a four-color mode.
;;
;; In:   X = the byte, A = the pixel's bits
PIXRIGHT4:
    LSRA
    BHS PIXRIGHT2                   ; the second shift
    LDA #$C0
    LEAX 1,X
    RTS

;; Reads a point, x and then a comma and y, as screen coordinates, limited to 255 and 191.
;;
;; In:   Y = where it goes: <HORBEG>, or <HOREND> through <GETXY_LIMIT>
GETXY:
    JSR ADRBYT
    LDY #HORBEG
GETXY_LIMIT:
    CMPB #192
    BLO GETXY_HORIZONTAL
    LDB #191
GETXY_HORIZONTAL:
    CLRA
    STD 2,Y
    LDD BINVAL
    CMPD #256
    BLO GETXY_STORE
    LDD #255
GETXY_STORE:
    STD ,Y
    RTS

;; Reads a point, as <GETXY> does, then scales it for the PMODE.
GETXYS:
    JSR GETXY
;; Scales the point <HORBEG>, <VERBEG> from screen coordinates, 256 by 192, to the PMODE's pixels: half as many
;; rows in PMODEs 0 and 1, half as many columns in PMODEs 0 to 3.
GRSCALE:
    LDU #HORBEG
;; Scales the point at U, as <GRSCALE> does.
GRSCALE_AT:
    LDA PMODE
    CMPA #2
    BHS GRSCALE_HORIZONTAL
    LDD 2,U
    LSRA
    RORB
    STD 2,U
GRSCALE_HORIZONTAL:
    LDA PMODE
    CMPA #4
    BHS GRSCALE_DONE
    LDD ,U
    LSRA
    RORB
    STD ,U
GRSCALE_DONE:
    RTS

;; Runs the PPOINT(x,y) function: the color of a point on the graphics page, 0 to 8.
PPOINT:
    JSR PARXY
    JSR GRSCALE
    JSR PIXADR
    ANDA ,X
    LDB PMODE
    RORB
    BHS PPOINT_TWO                  ; a two-color mode
PPOINT_FOUR:
    CMPA #4
    BLO PPOINT_COLOR
    RORA                            ; the pixel's two bits down to bits 0 and 1
    RORA
    BRA PPOINT_FOUR
PPOINT_COLOR:
    INCA
    ASLA
    ADDA CSSVAL
    LSRA                            ; plus 4 in the second color set
PPOINT_DONE:
    TFR A,B
    JMP GIVB
PPOINT_TWO:
    TSTA
    BEQ PPOINT_DONE                 ; off: 0
    CLRA
    BRA PPOINT_COLOR

;; Runs PSET(x,y[,c]): sets a point to the foreground color, or to c.
PSET:
    LDA #1
    BRA PSET_FLAG
;; Runs PRESET(x,y): sets a point to the background color.
PRESET:
    CLRA
PSET_FLAG:
    STA SETFLG
    JSR SYNLPR
    JSR GETXYS
    JSR PSETCOLOR
    JSR SYNRPR
    JSR PIXADR
;; Sets a pixel to the working color <ALLCOL>, noting in <CHGFLG> when that changed it.
;;
;; In:   X = the byte, A = the pixel's bits
PIXSET:
    LDB ,X
    PSHS B
    TFR A,B
    COMA
    ANDA ,X                         ; the other pixels
    ANDB ALLCOL                     ; this one in the color
    PSHS B
    ORA ,S+
    STA ,X
    SUBA ,S+
    ORA CHGFLG
    STA CHGFLG
    RTS

;; Reads LINE's points, (x1,y1)-(x2,y2), into <HORBEG> and <HOREND>; with -(x2,y2) the line starts at the last
;; one's end, <HORDEF>.
;;
;; In:   A = the character after LINE
LINEXY:
    LDX HORDEF
    STX HORBEG
    LDX VERDEF
    STX VERBEG
    CMPA #TK_MINUS
    BEQ LINEXY_END
    JSR PARXY
LINEXY_END:
    LDB #TK_MINUS
    JSR SYNCHR
    JSR SYNLPR
    JSR ADRBYT
    LDY #HOREND
    JSR GETXY_LIMIT
    BRA PARXY_DONE

;; Reads a point in parentheses into <HORBEG>.
PARXY:
    JSR SYNLPR
    JSR GETXY
PARXY_DONE:
    JMP SYNRPR

;; Runs LINE (x1,y1)-(x2,y2),PSET|PRESET[,B|,BF]: draws a line, or with B a box, or with BF a filled box, in the
;; foreground color for PSET or the background for PRESET. LINE INPUT goes to <LINEINPUT>.
LINE:
    CMPA #TK_INPUT
    LBEQ LINEINPUT
    CMPA #'('
    BEQ LINE_POINTS
    CMPA #TK_MINUS
    BEQ LINE_POINTS
    LDB #'@'                        ; LINE@ is LINE too
    JSR SYNCHR
LINE_POINTS:
    JSR LINEXY
    LDX HOREND
    STX HORDEF                      ; the next line starts at this one's end
    LDX VEREND
    STX VERDEF
    JSR SYNCOM
    CMPA #TK_PRESET
    BEQ LINE_PRESET
    CMPA #TK_PSET
    LBNE SNERR
    LDB #1
    .byte $86                       ; LDA #: skips the CLRB below
LINE_PRESET:
    CLRB
    PSHS B
    JSR GETNCH
    JSR LINESCALE
    PULS B
    STB SETFLG
    JSR SETWORK
    JSR GETCCH
    LBEQ DLINE                      ; a line
    JSR SYNCOM
    LDB #'B'
    JSR SYNCHR
    BNE LINE_FILL
    BSR HLINE                       ; a box: the top,
    BSR VLINE                       ;   the left side,
    LDX HORBEG
    PSHS X
    LDX HOREND
    STX HORBEG
    BSR VLINE                       ;   the right side
    PULS X
    STX HORBEG
    LDX VEREND
    STX VERBEG
    BRA HLINE                       ;   and the bottom

;; Scales LINE's two points for the PMODE.
LINESCALE:
    JSR GRSCALE
    LDU #HOREND
    JMP GRSCALE_AT

LINE_FILL:
    LDB #'F'
    JSR SYNCHR
    BRA LINE_FILL_NEXT              ; a row at a time from the top's y to the bottom's
LINE_FILL_UP:
    LEAX -1,X
LINE_FILL_ROW:
    STX VERBEG
LINE_FILL_NEXT:
    JSR HLINE
    LDX VERBEG
    CMPX VEREND
    BEQ LINE_FILL_DONE
    BHS LINE_FILL_UP
    LEAX 1,X
    BRA LINE_FILL_ROW
LINE_FILL_DONE:
    RTS

;; Draws a horizontal line from <HORBEG> to <HOREND> at <VERBEG>.
HLINE:
    LDX HORBEG
    PSHS X
    JSR DIFFX
    BHS HLINE_START
    LDX HOREND
    STX HORBEG                      ; from the left end
HLINE_START:
    TFR D,Y
    LEAY 1,Y
    JSR PIXADR
    PULS U
    STU HORBEG
    BSR RIGHTRTN
;; Sets pixels in a line, moving with the routine in U after each.
;;
;; In:   X, A = the first pixel, Y = how many, U = the routine that moves along
PLOTLINE:
    STA VD7
    JSR PIXSET
    LDA VD7
    JSR ,U
    LEAY -1,Y
    BNE PLOTLINE
    RTS

VLINE_DROP:
    PULS A,B
;; Draws a vertical line from <VERBEG> to <VEREND> at <HORBEG>.
VLINE:
    LDD VERBEG
    PSHS A,B
    JSR DIFFY
    BHS VLINE_START
    LDX VEREND
    STX VERBEG                      ; from the top
VLINE_START:
    TFR D,Y
    LEAY 1,Y
    JSR PIXADR
    PULS U
    STU VERBEG
    BSR DOWNRTN
    BRA PLOTLINE

;; The routines that move a pixel right one, for each PMODE.
RIGHTTAB:
    .dbyt PIXRIGHT2
    .dbyt PIXRIGHT4
    .dbyt PIXRIGHT2
    .dbyt PIXRIGHT4
    .dbyt PIXRIGHT2

;; Finds the routine that moves a pixel right one in the current PMODE.
;;
;; Out:  U = the routine
RIGHTRTN:
    LDU #RIGHTTAB
    LDB PMODE
    ASLB
    LDU B,U
    RTS

;; Finds the routine that moves a pixel down a row.
;;
;; Out:  U = the routine
DOWNRTN:
    LDU #PIXDOWN
    RTS

;; Draws a line from <HORBEG>, <VERBEG> to <HOREND>, <VEREND> by stepping along the longer axis, and along the
;; shorter one whenever the error built up passes the longer one's length.
DLINE:
    LDY #INCY
    JSR DIFFY
    LBEQ HLINE                      ; flat
    BHS DLINE_X
    LDY #DECY                       ; going up
DLINE_X:
    PSHS A,B
    LDU #INCX
    JSR DIFFX
    BEQ VLINE_DROP                  ; upright
    BHS DLINE_MAJOR
    LDU #DECX                       ; going left
DLINE_MAJOR:
    CMPD ,S
    PULS X
    BHS DLINE_START                 ; wider than it is tall
    EXG U,Y
    EXG D,X
DLINE_START:
    PSHS A,B,U                      ; the steps left, and the longer axis's step
    PSHS A,B                        ; the longer axis's length
    LSRA
    RORB                            ; the error starts at half of it
    BLO DLINE_ERROR
    CMPU #INCY + 1
    BLO DLINE_ERROR                 ; stepping right or down
    SUBD #1
DLINE_ERROR:
    PSHS A,B,X                      ; the error, and the shorter axis's length
    JSR PIXRTN
DLINE_POINT:
    JSR ,U
    JSR PIXSET
    LDX 6,S
    BEQ DLINE_DONE
    LEAX -1,X
    STX 6,S
    JSR [8,S]                       ; a step along the longer axis
    LDD ,S
    ADDD 2,S
    STD ,S
    SUBD 4,S
    BLO DLINE_POINT
    STD ,S
    JSR ,Y                          ; and one along the shorter
    BRA DLINE_POINT
DLINE_DONE:
    PULS X
    PULS A,B,X,Y,U,PC

;; Steps <HORBEG> right one.
INCX:
    LDX HORBEG
    LEAX 1,X
    STX HORBEG
    RTS

;; Steps <VERBEG> down one.
INCY:
    LDX VERBEG
    LEAX 1,X
    STX VERBEG
    RTS

;; Steps <HORBEG> left one.
DECX:
    LDX HORBEG
    LEAX -1,X
    STX HORBEG
    RTS

;; Steps <VERBEG> up one.
DECY:
    LDX VERBEG
    LEAX -1,X
    STX VERBEG
    RTS
;; Sets <VD3>, <VD5> to the graphics page's last point, 255,191, scaled for the PMODE.
GRLIMIT:
    LDU #VD3
    LDX #255
    STX ,U
    LDX #191
    STX 2,U
    JMP GRSCALE_AT

;; Runs PCLS[c]: clears the graphics page to a color, or to the background color.
PCLS:
    BEQ PCLS_BACK
    BSR GETCOLOR
PCLS_FILL:
    LDA #$55
    MUL                             ; the color in every pixel of a byte
    LDX BEGGRP
PCLS_BYTE:
    STB ,X+
    CMPX ENDGRP
    BNE PCLS_BYTE
    RTS
PCLS_BACK:
    LDB BAKCOL
    BRA PCLS_FILL

;; Runs COLOR [foreground][,background]: sets the colors graphics draw in.
COLOR:
    CMPA #','
    BEQ COLOR_BACK
    BSR GETCOLOR
    STB FORCOL
    JSR GETCCH
    BEQ COLOR_DONE
COLOR_BACK:
    JSR SYNCOM
    BSR GETCOLOR
    STB BAKCOL
COLOR_DONE:
    RTS

;; Reads a color, 0 to 8, as the bits a pixel holds for it in the current PMODE.
;;
;; Out:  B = the pixel's bits in its lowest two, A = 8 for colors 5 to 8, the second color set
;; Errors: ?FC ERROR above 8
GETCOLOR:
    JSR GETBYT
;; Turns a color, 0 to 8, into the bits a pixel holds for it, as <GETCOLOR> does.
CHKCOLOR:
    CMPB #9
    LBHS FCERR
    CLRA
    CMPB #5
    BLO CHKCOLOR_MODE
    LDA #8
    SUBB #4                         ; 5-8 are 1-4 in the second set
CHKCOLOR_MODE:
    PSHS A
    LDA PMODE
    RORA
    BHS CHKCOLOR_TWO
    TSTB                            ; four colors: 1-4 are 0-3, and 0 is 3
    BNE CHKCOLOR_FOUR
CHKCOLOR_ALL:
    LDB #4
CHKCOLOR_FOUR:
    DECB
CHKCOLOR_DONE:
    PULS A,PC
CHKCOLOR_TWO:
    RORB                            ; two colors: odd is on, even off
    BLO CHKCOLOR_ALL
    CLRB
    BRA CHKCOLOR_DONE

;; Sets the working color for PSET and PRESET, and reads a color after the point when there is one.
PSETCOLOR:
    JSR SETWORK
    JSR GETCCH
    BEQ PSETCOLOR_DONE
    CMPA #')'
    BEQ PSETCOLOR_DONE
    JSR SYNCOM
    CMPA #','
    BEQ PSETCOLOR_DONE
    JSR GETCOLOR
    BSR SETWORK_COLOR
PSETCOLOR_DONE:
    JMP GETCCH

;; Sets the working color: the foreground for PSET, the background for PRESET, as <SETFLG> says.
SETWORK:
    LDB FORCOL
    TST SETFLG
    BNE SETWORK_COLOR
    LDB BAKCOL
;; Sets the working color.
;;
;; In:   B = the pixel's bits
SETWORK_COLOR:
    STB WCOLOR
    LDA #$55
    MUL
    STB ALLCOL                      ; in every pixel of a byte
    RTS

;; Shows the graphics page, or with zero set the text screen.
SETSCREEN:
    BNE GRAPHSCREEN
;; Shows the text screen: the SAM's text mode and the page at <VIDRAM>, and the VDG's text mode.
TEXTSCREEN:
    PSHS A,B,X
    LDX #SAMREG+8
    STA 10,X                        ; F6 clear
    STA 8,X                         ; F5 clear
    STA 6,X                         ; F4 clear
    STA 4,X                         ; F3 clear
    STA 2,X                         ; F2 clear
    STA 1,X                         ; F1 set: $0400
    STA -2,X                        ; F0 clear
    STA -4,X                        ; V2 clear
    STA -6,X                        ; V1 clear
    STA -8,X                        ; V0 clear
    LDA PIA1+2
    ANDA #$07                       ; the VDG's text mode
    STA PIA1+2
    PULS A,B,X,PC

;; Shows the graphics page: the VDG's mode for the PMODE and the color set, and the SAM's mode and page.
GRAPHSCREEN:
    PSHS A,B,X
    LDA PMODE
    ADDA #3
    LDB #$10
    MUL
    ORB #$80                        ; graphics
    ORB CSSVAL
    LDA PIA1+2
    ANDA #$07
    PSHS A
    ORB ,S+
    STB PIA1+2
    LDA BEGGRP
    LSRA                            ; in 512-byte steps
    JSR SAMOFFSET
    LDA PMODE
    ADDA #3
    CMPA #7
    BNE GRAPHSCREEN_MODE
    DECA                            ; PMODE 4 is the SAM's mode 6 too
GRAPHSCREEN_MODE:
    BSR SAMMODE
    PULS A,B,X,PC

;; Sets the SAM's video mode bits, V0 to V2.
;;
;; In:   A = the mode
SAMMODE:
    LDB #3
    LDX #SAMREG
;; Sets a run of the SAM's bits from the low bits of A.
;;
;; In:   B = how many, X = the first's clear address
SAMBITS:
    RORA
    BHS SAMBITS_CLEAR
    STA 1,X
    BRA SAMBITS_NEXT
SAMBITS_CLEAR:
    STA ,X
SAMBITS_NEXT:
    LEAX 2,X
    DECB
    BNE SAMBITS
    RTS

;; Sets the SAM's display offset bits, F0 to F6.
;;
;; In:   A = the page's address over 512
SAMOFFSET:
    LDB #7
    LDX #SAMREG+6
    BRA SAMBITS

;; Sets the VDG's color set from <CSSVAL>.
SETCSS:
    LDA PIA1+2
    ANDA #$F7
    ORA CSSVAL
    STA PIA1+2
    RTS

;; Runs PMODE [mode][,page]: sets the graphics mode, 0 to 4, and the page it starts at. A mode sets the colors to
;; their defaults and starts at the first page.
;;
;; Errors: ?FC ERROR for a mode above 4, page 0, or a page that runs into the program
PMOD:
    CMPA #','
    BEQ PMODE_PAGE
    JSR GETBYT
    CMPB #5
    BHS PMODE_FC
.if VERSION = 10
    LDA VALTYP                      ; 1.0 loads $06 rather than GRPRAM here
.else
    LDA GRPRAM
.endif
PMOD_SET:
    STA BEGGRP
    ASLB
    LDU #PMODETAB+1
    ADDA B,U                        ; the page's size
    CMPA TXTTAB
    BHI PMODE_FC
    STA ENDGRP
    LEAU -1,U
    LDA B,U
    STA HORBYT
    LSRB
    STB PMODE
    CLRA
    STA BAKCOL
    LDA #3
    STA FORCOL
    JSR GETCCH
    BEQ PMODE_DONE
PMODE_PAGE:
    JSR COMBYT
    TSTB
    BEQ PMODE_FC
    DECB
    LDA #6
    MUL                             ; 1.5K a page
    ADDB GRPRAM
    PSHS B
    ADDB ENDGRP
    SUBB BEGGRP
    CMPB TXTTAB
    BHI PMODE_FC
    STB ENDGRP
    PULS B
    STB BEGGRP
PMODE_DONE:
    RTS
PMODE_FC:
    JMP FCERR

;; Runs SCREEN [screen][,set]: shows the text screen for 0 or the graphics page otherwise, in the first color set
;; for 0 or the second otherwise.
SCREEN:
    CMPA #','
    BEQ SCREEN_CSS
    JSR GETBYT
    TSTB
    JSR SETSCREEN
    JSR GETCCH
    BEQ PMODE_DONE
SCREEN_CSS:
    JSR COMBYT
    TSTB
    BEQ SCREEN_SET
    LDB #8
SCREEN_SET:
    STB CSSVAL
    BRA SETCSS

;; Runs PCLEAR n: keeps n 1.5K graphics pages, 1 to 8, below the program, moving the program up or down to fit and
;; clearing the variables. In a program, 1.1 goes on after PCLEAR from where the program has moved to; 1.0 does
;; not.
;;
;; Errors: ?FC ERROR for 0 or more than 8, fewer pages than PMODE uses, or not enough memory
PCLEAR:
    JSR GETBYT
    TSTB
    BEQ PMODE_FC
    CMPB #9
    BHS PMODE_FC
    LDA #6
    MUL
    ADDB GRPRAM
    TFR B,A
    LDB #1
    TFR D,Y                         ; the program's new start
    CMPD ENDGRP
.if VERSION = 10
    LBLO FCERR
    SUBD TXTTAB
    ADDD VARTAB
    TFR D,X                         ; the variables' new start
    ADDD #200
    SUBD FRETOP
    BHS PMODE_FC                    ; not enough room
.else
    BLO PMODE_FC
    SUBD TXTTAB
    ADDD VARTAB
    TFR D,X                         ; the variables' new start
    INCA                            ; and 256 bytes more
    SUBD FRETOP
    BHS PMODE_FC                    ; not enough room
    JSR PCLEAR_CHARAD
    NOP
.endif
    LDU VARTAB
    STX VARTAB
    CMPU VARTAB
    BHS PCLEAR_DOWN
PCLEAR_UP:
    LDA ,-U                         ; from the end
    STA ,-X
    CMPU TXTTAB
    BNE PCLEAR_UP
    STY TXTTAB
    CLR -1,Y
PCLEAR_DONE:
    JSR LINKLN
    JSR CLRSTR
    JMP NEWSTT
PCLEAR_DOWN:
    LDU TXTTAB
    STY TXTTAB
    CLR -1,Y
PCLEAR_DOWN_BYTE:
    LDA ,U+                         ; from the start
    STA ,Y+
    CMPY VARTAB
    BNE PCLEAR_DOWN_BYTE
    BRA PCLEAR_DONE

;; Sets up graphics at power on: four pages from $0600, the program after them at $1E01, PMODE 0 on the first page.
GRINIT:
    LDB #$1E
    STB TXTTAB
    LDA #$06
GRINIT_PAGES:
    STA GRPRAM
    STA BEGGRP
    CLRA
    STA PMODE
    LDA #16
    STA HORBYT
    LDA #3
    STA FORCOL
    LDA #$0C
    STA ENDGRP
    LDX TXTTAB
    CLR -1,X
    JMP ERASEP

;; Each PMODE's bytes a row, and its page's size in 256-byte pages.
PMODETAB:
    .byte 16, $06
    .byte 32, $0C
    .byte 16, $0C
    .byte 32, $18
    .byte 32, $18

;; Finds how far <VEREND> is from <VERBEG>.
;;
;; Out:  D = the distance, carry = set when VEREND is above
DIFFY:
    LDD VEREND
    SUBD VERBEG
DIFF_SIGN:
    BHS PAGEADR_DONE
    PSHS CC
    JSR NEGD
    PULS CC,PC

;; Finds how far <HOREND> is from <HORBEG>.
;;
;; Out:  D = the distance, carry = set when HOREND is to the left
DIFFX:
    LDD HOREND
    SUBD HORBEG
    BRA DIFF_SIGN

;; Runs PCOPY page TO page: copies one 1.5K graphics page onto another.
;;
;; Errors: ?FC ERROR for page 0
PCOPY:
    BSR PAGEADR
    PSHS A,B
    LDB #TK_TO
    JSR SYNCHR
    BSR PAGEADR
    PULS X
    TFR D,U
    LDY #$0300                      ; 768 words
PCOPY_WORD:
    LDD ,X++
    STD ,U++
    LEAY -1,Y
    BNE PCOPY_WORD
    RTS

;; Reads a graphics page's number and finds its address.
;;
;; Out:  D = the page's address
;; Errors: ?FC ERROR for page 0
PAGEADR:
    JSR GETBYT
    TSTB
    BEQ PAGEADR_FC
    CMPB TXTTAB
    BHI PAGEADR_FC
    DECB
    LDA #6
    MUL
    ADDB GRPRAM
    EXG A,B
PAGEADR_DONE:
    RTS
PAGEADR_FC:
    JMP FCERR

;; Runs GET (x1,y1)-(x2,y2),array[,G]: copies a rectangle of the graphics page into a numeric array, whose bytes
;; hold it. Without G, the rectangle is taken in whole bytes; with G, a pixel at a time.
GET:
    CLRB
    BRA GETPUT
;; Runs PUT (x1,y1)-(x2,y2),array[,action]: copies a rectangle GET saved onto the graphics page. Without an action
;; it goes in whole bytes; with PSET, PRESET, AND, OR or NOT, a pixel at a time, as the action says.
;;
;; Errors: ?FC ERROR for an array too small or not numeric
PUT:
    LDB #1
GETPUT:
    STB VD8                         ; zero for GET
    JSR RVEC22
GETPUT_HOOKED:
    CMPA #'@'
    BNE GETPUT_POINTS
    JSR GETNCH
GETPUT_POINTS:
    JSR LINEXY
    JSR SYNCOM
    JSR ARYFIND
    TFR X,D
    LDU ,X
    LEAU -2,U
    LEAU D,U
    STU VD1                         ; the array's end
    LEAX 2,X
    LDB ,X
    ASLB
    ABX
    STX VCF                         ; before its first element
    LDA VALTYP
    BNE PAGEADR_FC                  ; a string array
    CLR VD4                         ; whole bytes
    JSR GETCCH
    BEQ GETPUT_BYTES
    COM VD4                         ; pixels
    JSR SYNCOM
    TST VD8
    BNE GETPUT_ACTION
    LDB #'G'
    JSR SYNCHR
    BRA GETPUT_SIZE
GETPUT_ACTION:
    LDB #5
    LDX #PUTTAB
GETPUT_ACTION_NEXT:
    LDU ,X++
    LDY ,X++
    CMPA ,X+
    BEQ GETPUT_ACTION_FOUND
    DECB
    BNE GETPUT_ACTION_NEXT
    JMP SNERR
GETPUT_ACTION_FOUND:
    STY VD5                         ; for a pixel that is on in the array
    STU VD9                         ; for one that is off
    JSR GETNCH
    BRA GETPUT_SIZE
GETPUT_BYTES:
    LDB #$F8                        ; eight pixels a byte
    LDA PMODE
    RORA
    BHS GETPUT_ALIGN
    LDB #$FC                        ; four
GETPUT_ALIGN:
    TFR B,A
    ANDB HORBEG+1
    STB HORBEG+1
    ANDA HOREND+1
    STA HOREND+1
GETPUT_SIZE:
    JSR DIFFX
    BHS GETPUT_WIDTH
    LDX HOREND
    STX HORBEG
GETPUT_WIDTH:
    STD HOREND                      ; the width, less one
    JSR DIFFY
    BHS GETPUT_HEIGHT
    LDX VEREND
    STX VERBEG
GETPUT_HEIGHT:
    STD VEREND                      ; the height, less one
    LDA PMODE
    RORA
    LDD HOREND
    BHS GETPUT_SCALE
    ADDD HOREND                     ; four colors: two bits a pixel
    STD HOREND
GETPUT_SCALE:
    JSR LINESCALE
    LDD HOREND
    LDX VEREND
    LEAX 1,X
    STX VEREND                      ; the rows
    TST VD4
    BNE GETPUT_PIXELS
    LSRA
    RORB
    LSRA
    RORB
    LSRA
    RORB
    ADDD #1
    STD HOREND                      ; the bytes a row
    JSR PIXADR
GETPUT_ROW:
    LDB HOREND+1
    PSHS X
GETPUT_BYTE:
    TST VD8
    BEQ GETPUT_GETBYTE
    BSR ARYNEXT
    LDA ,U
    STA ,X+
GETPUT_BYTE_NEXT:
    DECB
    BNE GETPUT_BYTE
    PULS X
    JSR PIXDOWN
    DEC VEREND+1
    BNE GETPUT_ROW
GETPUT_DONE:
    RTS

;; Moves to the array's next byte.
;;
;; Out:  U = the byte
;; Errors: ?FC ERROR past the array's end
ARYNEXT:
    LDU VCF
    LEAU 1,U
    STU VCF
    CMPU VD1
    BNE GETPUT_DONE
ARYNEXT_FC:
    JMP FCERR

GETPUT_GETBYTE:
    LDA ,X+
    BSR ARYNEXT
    STA ,U
    BRA GETPUT_BYTE_NEXT

;; PUT's actions: the routines for a pixel off and on in the array, then the action's token.
PUTTAB:
    .dbyt PUTOFF, PUTON
    .byte TK_PSET
    .dbyt PUTON, PUTOFF
    .byte TK_PRESET
    .dbyt GETPUT_PIXEL_NEXT, PUTON
    .byte TK_OR
    .dbyt PUTOFF, GETPUT_PIXEL_NEXT
    .byte TK_AND
    .dbyt PUTNOT, PUTNOT
    .byte TK_NOT

GETPUT_PIXELS:
    ADDD #1
    STD HOREND                      ; the pixels a row
    LDA VD8
    BNE GETPUT_FIRST
    LDU VD1                         ; GET: clear the array first
GETPUT_CLEAR:
    STA ,-U
    CMPU VCF
    BHI GETPUT_CLEAR
GETPUT_FIRST:
    JSR PIXADR
    LDB PMODE
    RORB
    BHS GETPUT_START
    ANDA #$AA
GETPUT_START:
    LDB #$01                        ; the array's bit
    LDY VCF
GETPUT_PIXROW:
    PSHS A,X
    LDU HOREND
GETPUT_PIXEL:
    PSHS A,U
    LSRB
    BHS GETPUT_PIXEL_BIT
    RORB                            ; $80, in the array's next byte
    LEAY 1,Y
    CMPY VD1
    BEQ ARYNEXT_FC
GETPUT_PIXEL_BIT:
    TST VD8
    BEQ GETPUT_GETPIXEL
    BITB ,Y
    BEQ GETPUT_PIXEL_OFF
    JMP [VD5]
GETPUT_PIXEL_OFF:
    JMP [VD9]

;; Clears the pixel, for PUT.
PUTOFF:
    COMA
    ANDA ,X
    STA ,X
    BRA GETPUT_PIXEL_NEXT
;; Sets the pixel, for PUT.
PUTON:
    ORA ,X
    STA ,X
    BRA GETPUT_PIXEL_NEXT
;; Inverts the pixel, for PUT's NOT.
PUTNOT:
    EORA ,X
    STA ,X
    BRA GETPUT_PIXEL_NEXT

GETPUT_GETPIXEL:
    BITA ,X
    BEQ GETPUT_PIXEL_NEXT
    TFR B,A
    ORA ,Y
    STA ,Y
GETPUT_PIXEL_NEXT:
    PULS A,U
    JSR PIXRIGHT2
    LEAU -1,U
    CMPU ZERO
    BNE GETPUT_PIXEL
    LDX 1,S
    LDA HORBYT
    LEAX A,X                        ; the next row
    PULS A
    LEAS 2,S
    DEC VEREND+1
    BNE GETPUT_PIXROW
    RTS

;; Finds the array a name after GET or PUT names.
;;
;; Out:  X = the array's header, after its name
;; Errors: ?FC ERROR when there is no such array
ARYFIND:
    JSR PTRGET
    LDB ,-X
    LDA ,-X                         ; the name
    TFR D,U
    LDX ARYTAB
ARYFIND_NEXT:
    CMPX ARYEND
    LBEQ FCERR
    CMPU ,X
    BEQ ARYFIND_FOUND
    LDD 2,X
    LEAX D,X
    BRA ARYFIND_NEXT
ARYFIND_FOUND:
    LEAX 2,X
    RTS

PAINT_DONE:
    RTS

;; Runs PAINT (x,y)[,color[,border]]: fills the area around a point, up to pixels of the border color (the paint
;; color by default), a row at a time. The rows still to fill above and below go on the stack, each as its
;; direction, row, start and length.
PAINT:
    CMPA #'@'
    BNE PAINT_POINT
    JSR GETNCH
PAINT_POINT:
    JSR PARXY
    JSR GRSCALE
    LDA #1
    STA SETFLG
    JSR PSETCOLOR
    LDD WCOLOR
    PSHS A,B                        ; the paint color
    JSR GETCCH
    BEQ PAINT_BORDER
    JSR PSETCOLOR                   ; the border's
PAINT_BORDER:
    LDA ALLCOL
    STA VD8
    PULS A,B
    STD WCOLOR
    CLRA
    PSHS A,B,X,U                    ; direction 0: the end
    JSR GRLIMIT
    JSR PIXRTN
    STU VD9
    JSR PNTLEFT
    BEQ PAINT_STACK                 ; the point is on the border
    JSR PNTWIDE
    LDA #1
    STA VD7
    JSR PNTPUSH                     ; the rows below
    NEG VD7
    JSR PNTPUSH                     ;   and above
PAINT_STACK:
    STS TMPSTK
PAINT_NEXT:
    TST CHGFLG
    BNE PAINT_POP
    LDS TMPSTK                      ; nothing painted: drop what that row pushed
PAINT_POP:
    PULS A,B,X,U
    CLR CHGFLG
    STS TMPSTK
    LEAX 1,X
    STX HORBEG
    STU VD1                         ; the length
    STA VD7                         ; the direction
    BEQ PAINT_DONE
    BMI PAINT_UP
    INCB
    CMPB VD6
    BLS PAINT_ROW
    CLRB                            ; past the bottom
PAINT_UP:
    TSTB
    BEQ PAINT_NEXT                  ; past the top
    DECB
PAINT_ROW:
    STB VERBEG+1
    JSR PNTLEFT
    BEQ PAINT_REST
    CMPD #3
    BLO PAINT_RIGHT
    LEAX -2,X
    BSR PNTBACK                     ; it went past the row it came from: back that way too
PAINT_RIGHT:
    JSR PNTWIDE
PAINT_PUSH:
    BSR PNTPUSH
PAINT_REST:
    COMA
    COMB
PAINT_REST_NEXT:
    ADDD VD1
    STD VD1
    BLE PAINT_REST_END
    JSR INCX
    JSR PNTBORDER
    BNE PAINT_REST_GAP
    LDD #$FFFF
    BRA PAINT_REST_NEXT
PAINT_REST_GAP:
    JSR DECX
    BSR PNTMARK
    BSR PNTRIGHT
    BRA PAINT_PUSH
PAINT_REST_END:
    JSR INCX
    LEAX D,X
    STX HORBEG
    COMA
    COMB
    SUBD #1
    BLE PAINT_REST_DONE
    TFR D,X
    BSR PNTBACK                     ; past the row it came from: back that way too
PAINT_REST_DONE:
    JMP PAINT_NEXT

;; Pushes a row to fill in the other direction: from <HORBEG>, X long.
PNTBACK:
    STD VCB
    PULS Y
    LDD HORBEG
    PSHS A,B,X
    LDA VD7
    NEGA
PNTSAVE:
    LDB VERBEG+1
    PSHS A,B
    PSHS Y
    LDB #2
    JSR GETSTK
    LDD VCB
    RTS

;; Pushes a row to fill in the same direction: from <HOREND>, X long.
PNTPUSH:
    STD VCB
    PULS Y
    LDD HOREND
    PSHS A,B,X
    LDA VD7
    BRA PNTSAVE

;; Marks where a row's fill starts.
PNTMARK:
    LDX HORBEG
    STX HOREND
    RTS

;; Fills right after filling left, and counts the whole row.
;;
;; In:   D = the pixels filled left
;; Out:  X = the row's length, D = it plus one
PNTWIDE:
    STD VCD
    LDY HOREND
    BSR PNTMARK
    STY HORBEG
    BSR PNTRIGHT
    LDX VCD
    LEAX D,X
    ADDD #1
    RTS

;; Fills left from <HORBEG> up to the border or the page's edge.
;;
;; Out:  D, X = the pixels filled, zero = set when none
PNTLEFT:
    JSR PNTMARK
    LDY #DECX
    BRA PNTSCAN
;; Fills right from the pixel after <HORBEG>, as <PNTLEFT> does.
PNTRIGHT:
    LDY #INCX
    JSR ,Y
PNTSCAN:
    LDU ZERO
    LDX HORBEG
PNTSCAN_NEXT:
    BMI PNTSCAN_DONE                ; off the left edge
    CMPX VD3
    BHI PNTSCAN_DONE                ; off the right
    PSHS Y,U
    BSR PNTBORDER
    BEQ PNTSCAN_BORDER
    JSR PIXSET
    PULS Y,U
    LEAU 1,U
    JSR ,Y
    BRA PNTSCAN_NEXT
PNTSCAN_BORDER:
    PULS Y,U
PNTSCAN_DONE:
    TFR U,D
    TFR D,X
    SUBD ZERO
    RTS

;; Checks whether the pixel at <HORBEG>, <VERBEG> is the border's color.
;;
;; Out:  X, A = the pixel, zero = set when it is the border
PNTBORDER:
    JSR [VD9]
    TFR A,B
    ANDB VD8
    PSHS A,B
    ANDA ,X
    CMPA 1,S
    PULS A,B,PC

;; Runs PLAY string: plays the notes and rests a string of commands spells out, through the DAC. The commands are
;; O octave (1-5), V volume (1-31), L note length (1-255, a quarter note 4, with dots for half as long again),
;; T tempo (1-255), P pause, N note number (1-12) or the letters A to G with # or + for sharp and - for flat,
;; and Xstring$; to play another string. A value may be +, -, > (doubled), < (halved) or =variable; instead of a
;; number. Each note plays until the IRQ handler's PLAY timer runs out (<PLAYIRQ>).
;;
;; Errors: ?FC ERROR for a value out of range or a command it does not know
PLAY:
    LDX ZERO
    LDB #1
    PSHS B,X                        ; the end, for X strings to return to
    JSR FRMEVL
    CLRB
    JSR SELMUX                      ; the DAC to the speaker
    JSR SNDON
PLAY_STRING:
    JSR FRESTR
    BRA PLAY_START
PLAY_POP:
    PULS B,X                        ; back to the string before an X string
PLAY_START:
    STB VD8                         ; the characters left
    BEQ PLAY_POP
    STX VD9                         ; the next character
    LBEQ SNDOFF                     ; the end
PLAY_NEXT:
    TST VD8
    BEQ PLAY_POP
    JSR PLAYCHR
    CMPA #';'
    BEQ PLAY_NEXT
    CMPA #$27                       ; '
    BEQ PLAY_NEXT
    CMPA #'X'
    LBEQ PLAYSUB
    BSR PLAYCMD
    BRA PLAY_NEXT

;; Runs one PLAY command.
;;
;; In:   A = the command's letter
PLAYCMD:
    CMPA #'O'
    BNE PLAYCMD_V
    LDB OCTAVE
    INCB
    BSR PLAYCMD_VALUE
    DECB
    CMPB #4
    BHI PLAYCMD_FC
    STB OCTAVE
    RTS
PLAYCMD_V:
    CMPA #'V'
    BNE PLAYCMD_L
    LDB VOLHI
    LSRB
    LSRB
    SUBB #31                        ; the volume now
    BSR PLAYCMD_VALUE
    CMPB #31
    BHI PLAYCMD_FC
    ASLB
    ASLB
    PSHS B
    LDD #$7E7E                      ; the DAC's middle
    ADDA ,S
    SUBB ,S+
    STD VOLHI                       ; the wave's high and low levels
    RTS
PLAYCMD_L:
    CMPA #'L'
    BNE PLAYCMD_T
    LDB NOTELN
    BSR PLAYCMD_VALUE
    TSTB
    BEQ PLAYCMD_FC
    STB NOTELN
    CLR DOTVAL
PLAYCMD_DOTS:
    BSR PLAYDOT
    BHS PLAYCMD_DOTS
    RTS

;; Counts a dot after a note or a length.
;;
;; Out:  carry = set when there was none
PLAYDOT:
    TST VD8
    BEQ PLAYDOT_NONE
    JSR PLAYCHR
    CMPA #'.'
    BEQ PLAYDOT_ONE
    JSR PLAYBACK
PLAYDOT_NONE:
    COMA
    RTS
PLAYDOT_ONE:
    INC DOTVAL
    RTS

PLAYCMD_T:
    CMPA #'T'
    BNE PLAYCMD_P
    LDB TEMPO
    BSR PLAYCMD_VALUE
    TSTB
    BEQ PLAYCMD_FC
    STB TEMPO
    RTS
PLAYCMD_VALUE:
    JMP PLAYVAL
PLAYCMD_P:
    CMPA #'P'
    BNE PLAYCMD_N
    JSR PLAYARG
    TSTB
    BNE PLAYCMD_PAUSE
PLAYCMD_FC:
    JMP FCERR
PLAYCMD_PAUSE:
    LDA DOTVAL
    LDX VOLHI
    PSHS A,X
    LDA #$7E
    STA VOLHI                       ; a note with no volume
    STA VOLLOW
    CLR DOTVAL
    BSR PLAYREST
    PULS A,X
    STA DOTVAL
    STX VOLHI
    RTS

;; Plays a silent note.
;;
;; In:   B = its length
PLAYREST:
    CLR ,-S
    BRA PLAYTONE

PLAYCMD_N:
    CMPA #'N'
    BNE PLAYCMD_NOTE
    JSR PLAYCHR
PLAYCMD_NOTE:
    CMPA #'A'
    BLO PLAYCMD_NUMBER
    CMPA #'G'
    BLS PLAYCMD_LETTER
PLAYCMD_NUMBER:
    JSR PLAYNUM
    BRA PLAYNOTE
PLAYCMD_LETTER:
    SUBA #'A'
    LDX #NOTETAB
    LDB A,X
    TST VD8
    BEQ PLAYNOTE
    JSR PLAYCHR
    CMPA #'#'
    BEQ PLAYCMD_SHARP
    CMPA #'+'
    BNE PLAYCMD_FLAT
PLAYCMD_SHARP:
    INCB
    BRA PLAYNOTE
PLAYCMD_FLAT:
    CMPA #'-'
    BNE PLAYCMD_NATURAL
    DECB
    BRA PLAYNOTE
PLAYCMD_NATURAL:
    JSR PLAYBACK
;; Plays a note in the octave <OCTAVE>, for <NOTELN> at <TEMPO>.
;;
;; In:   B = the note, 1 to 12 from C
;; Errors: ?FC ERROR for any other note
PLAYNOTE:
    DECB
    CMPB #11
    BHI PLAYCMD_FC
    PSHS B
    LDB NOTELN
;; Plays a tone until the PLAY timer runs out: the IRQ handler then returns from here to the caller.
;;
;; In:   B = the length, 0,S = the note, from 0
PLAYTONE:
    LDA TEMPO
    MUL
    STD VD5                         ; how much the timer counts down each sixtieth
    LEAU 1,S                        ; where the IRQ handler returns to
    LDA OCTAVE
    CMPA #1
    BHI PLAYTONE_HIGH
    LDX #PLAYLOW                    ; octaves 1 and 2: 16-bit delays
    LDB #24
    MUL
    ABX
    PULS B
    ASLB
    ABX
    LEAY ,X
    BSR PLAYTIME
    STD PLYTMR
PLAYTONE_LOW:
    BSR PLAYLOW_MID
    LDA VOLHI
    BSR PLAYLOW_LEVEL
    BSR PLAYLOW_MID
    LDA VOLLOW
    BSR PLAYLOW_LEVEL
    BRA PLAYTONE_LOW
PLAYLOW_MID:
    LDA #$7E
    NOP
PLAYLOW_LEVEL:
    STA PIA1                        ; the DAC
    LDX ,Y
PLAYLOW_WAIT:
    LEAX -1,X
    BNE PLAYLOW_WAIT
    RTS
PLAYTONE_HIGH:
    LDX #PLAYHIGH - 24              ; octaves 3 to 5: 8-bit delays
    LDB #12
    MUL
    ABX
    PULS B
    ABX
    BSR PLAYTIME
    STD PLYTMR
PLAYTONE_HIGH_CYCLE:
    BSR PLAYHIGH_MID
    LDA VOLHI
    BSR PLAYHIGH_LEVEL
    BSR PLAYHIGH_MID
    LDA VOLLOW
    BSR PLAYHIGH_LEVEL
    BRA PLAYTONE_HIGH_CYCLE
PLAYHIGH_MID:
    LDA #$7E
    NOP
PLAYHIGH_LEVEL:
    STA PIA1
    LDA ,X
PLAYHIGH_WAIT:
    DECA
    BNE PLAYHIGH_WAIT
    RTS

;; Finds the PLAY timer's start: 255, or half again for each dot.
;;
;; Out:  D = the time
PLAYTIME:
    LDB #$FF
    LDA DOTVAL
    BEQ PLAYTIME_DONE
    ADDA #2
    MUL
    LSRA
    RORB
PLAYTIME_DONE:
    RTS

;; Gets the next character of a PLAY or DRAW string, skipping spaces.
;;
;; Out:  A = the character
;; Errors: ?FC ERROR at the string's end
PLAYCHR:
    PSHS X
PLAYCHR_NEXT:
    TST VD8
    BEQ PLAYVAL_FC
    LDX VD9
    LDA ,X+
    STX VD9
    DEC VD8
    CMPA #' '
    BEQ PLAYCHR_NEXT
    PULS X,PC

;; Reads a command's value: + or - for one more or less, > for twice, < for half, =variable; or a number.
;;
;; In:   B = the value now
;; Out:  B = the new value
;; Errors: ?FC ERROR for a value that would leave 1 to 255
PLAYVAL:
    BSR PLAYCHR
    CMPA #'+'
    BEQ PLAYVAL_PLUS
    CMPA #'-'
    BEQ PLAYVAL_MINUS
    CMPA #'>'
    BEQ PLAYVAL_DOUBLE
    CMPA #'<'
    BEQ PLAYVAL_HALF
;; Reads a number, 0 to 255, or =variable;.
;;
;; In:   A = its first character
;; Out:  B = the number
PLAYNUM:
    CMPA #'='
    BEQ PLAYVAL_VAR
    JSR DIGCHK
    BLO PLAYVAL_FC
    CLRB
PLAYNUM_DIGIT:
    SUBA #'0'
    STA VD7
    LDA #10
    MUL
    TSTA
    BNE PLAYVAL_FC                  ; past 255
    ADDB VD7
    BLO PLAYVAL_FC
    TST VD8
    BEQ PLAYVAL_DONE
    JSR PLAYCHR
    JSR DIGCHK
    BHS PLAYNUM_DIGIT
;; Puts the last character back, to be read again.
PLAYBACK:
    INC VD8
    LDX VD9
    LEAX -1,X
    STX VD9
    RTS
PLAYVAL_FC:
    JMP FCERR
PLAYVAL_PLUS:
    INCB
    BEQ PLAYVAL_FC
PLAYVAL_DONE:
    RTS
PLAYVAL_MINUS:
    TSTB
    BEQ PLAYVAL_FC
    DECB
    RTS
PLAYVAL_HALF:
    TSTB
    BEQ PLAYVAL_FC
    LSRB
    RTS
PLAYVAL_DOUBLE:
    TSTB
    BMI PLAYVAL_FC
    ASLB
    RTS
PLAYVAL_VAR:
    PSHS Y,U
    BSR PLAYVAR
    JSR BYTCHK
    PULS Y,U,PC

;; Runs PLAY's and DRAW's Xstring$;: plays or draws another string, then comes back.
PLAYSUB:
    JSR PLAYVAR
    LDB #2
    JSR GETSTK
    LDB VD8
    LDX VD9
    PSHS B,X                        ; where to come back to
    JMP PLAY_STRING

;; Evaluates the variable named in a PLAY or DRAW string, up to its semicolon.
;;
;; Errors: ?FC ERROR unless a letter starts it
PLAYVAR:
    LDX VD9
    PSHS X
    JSR PLAYCHR
    JSR ISLETC
    BLO PLAYVAL_FC
PLAYVAR_NAME:
    JSR PLAYCHR
    CMPA #';'
    BNE PLAYVAR_NAME
    PULS X
    LDU CHARAD
    PSHS U
    STX CHARAD                      ; read it as BASIC would
    JSR EVAL_VAR
    PULS X
    STX CHARAD
    RTS

;; PLAY's part of the IRQ handler: counts the note's timer down, and when it runs out stops the note by returning
;; from <PLAYTONE> to its caller. With no note playing, SOUND's timer is counted instead.
PLAYIRQ:
    CLRA
    TFR A,DP
    LDD PLYTMR
    LBEQ BIRQSV_SOUND
    SUBD VD5
    STD PLYTMR
    BHI PLAYIRQ_DONE
    CLR PLYTMR
    CLR PLYTMR+1
    PULS A                          ; the saved CC
    LDS 7,S                         ; the saved U: PLAYTONE's frame
    ANDA #$7F                       ; only CC and PC to restore
    PSHS A
PLAYIRQ_DONE:
    RTI

;; The notes A to G, as numbers from C.
NOTETAB:
    .byte 10, 12, 1, 3, 5, 6, 8

;; The delays of a half cycle's quarters for octaves 1 and 2, twelve notes each from C.
PLAYLOW:
    .dbyt $01A8, $0190, $017A, $0164, $0150, $013D, $012B, $011A, $010A, $00FB, $00ED, $00DF
    .dbyt $00D3, $00C7, $00BB, $00B1, $00A6, $009D, $0094, $008B, $0083, $007C, $0075, $006E

;; The delays for octaves 3 to 5.
PLAYHIGH:
    .byte $A6, $9C, $93, $8B, $83, $7B, $74, $6D, $67, $61, $5B, $56
    .byte $51, $4C, $47, $43, $3F, $3B, $37, $34, $31, $2E, $2B, $28
    .byte $26, $23, $21, $1F, $1D, $1B, $19, $18, $16, $14, $13, $12

;; Runs DRAW string: draws lines a string of commands spells out, from the last point drawn.
DRAW:
    LDX ZERO
    LDB #1
    PSHS B,X
    STB SETFLG
    STX VD5
    JSR SETWORK
    JSR FRMEVL
DRAW_STRING:
    JSR FRESTR
    BRA DRAW_START

;; Reads the character after a command and a number from it, as <PLAYNUM> does.
PLAYARG:
    JSR PLAYCHR
    JMP PLAYNUM

DRAW_POP:
    PULS B,X                        ; back to the string before an X string
DRAW_START:
    STB VD8
    BEQ DRAW_POP
    STX VD9
    LBEQ NEGD_DONE                  ; the end
DRAW_NEXT:
    TST VD8
    BEQ DRAW_POP
    JSR PLAYCHR
    CMPA #';'
    BEQ DRAW_NEXT
    CMPA #$27                       ; '
    BEQ DRAW_NEXT
    CMPA #'N'
    BNE DRAW_B
    COM VD5                         ; the next move leaves the last point where it was
    BRA DRAW_NEXT
DRAW_B:
    CMPA #'B'
    BNE DRAW_OTHER
    COM VD6                         ; the next move draws nothing
    BRA DRAW_NEXT
DRAW_OTHER:
    CMPA #'X'
    LBEQ DRAW_X
    CMPA #'M'
    LBEQ DRAW_M
    PSHS A
    LDB #1                          ; no number: 1
    TST VD8
    BEQ DRAW_COMMAND
    JSR PLAYCHR
    JSR ISLETC
    PSHS CC
    JSR PLAYBACK
    PULS CC
    BHS DRAW_COMMAND                ; a letter: the next command
    BSR PLAYARG
DRAW_COMMAND:
    PULS A
    CMPA #'C'
    BEQ DRAW_C
    CMPA #'A'
    BEQ DRAW_A
    CMPA #'S'
    BEQ DRAW_S
    CMPA #'U'
    BEQ DRAW_U
    CMPA #'D'
    BEQ DRAW_D
    CMPA #'L'
    BEQ DRAW_L
    CMPA #'R'
    BEQ DRAW_R
    SUBA #'E'
    BEQ DRAW_E
    DECA
    BEQ DRAW_F
    DECA
    BEQ DRAW_G
    DECA
    BEQ DRAW_H
DRAW_FC:
    JMP FCERR
DRAW_C:
    JSR CHKCOLOR
    STB FORCOL
    JSR SETWORK
DRAW_DONE:
    BRA DRAW_NEXT
DRAW_A:
    CMPB #4
    BHS DRAW_FC
    STB ANGLE
    BRA DRAW_DONE
DRAW_S:
    CMPB #63
    BHS DRAW_FC
    STB SCALE
    BRA DRAW_DONE
DRAW_H:
    CLRA                            ; up and left
    BSR NEGB16
    .byte $21                       ; BRN: skips the CLRA below
DRAW_F:
    CLRA                            ; down and right
    TFR D,X
    BRA DRAWBY
DRAW_E:
    CLRA                            ; up and right
    TFR D,X
    BSR NEGB16
    EXG D,X
    BRA DRAWBY
DRAW_G:
    CLRA                            ; down and left
    TFR D,X
    BSR NEGB16
    BRA DRAWBY
DRAW_R:
    CLRA
DRAW_ACROSS:
    LDX ZERO
    BRA DRAWBY
DRAW_L:
    CLRA
    BSR NEGB16
    BRA DRAW_ACROSS
DRAW_D:
    CLRA
    BRA DRAW_UPRIGHT
DRAW_U:
    CLRA
    BSR NEGB16
DRAW_UPRIGHT:
    LDX ZERO
    EXG X,D
    BRA DRAWBY
DRAW_X:
    JSR PLAYVAR
    LDB #2
    JSR GETSTK
    LDB VD8
    LDX VD9
    PSHS B,X                        ; where to come back to
    JMP DRAW_STRING

;; Scales a distance by <SCALE> in quarters, 0 being unscaled.
;;
;; In:   X = the distance
;; Out:  D = it scaled
DRAWSCALE:
    LDB SCALE
    BEQ DRAWSCALE_NONE
    CLRA
    EXG D,X
    STA ,-S                         ; its sign
    BPL DRAWSCALE_MULTIPLY
    BSR NEGD
DRAWSCALE_MULTIPLY:
    JSR MUL16
    TFR U,D
    LSRA
    RORB
    LSRA
    RORB
    TST ,S+
    BPL NEGD_DONE
;; Negates D.
NEGD:
    NEGA
;; Negates B into D, with A clear, or finishes negating D.
NEGB16:
    NEGB
    SBCA #0
NEGD_DONE:
    RTS
DRAWSCALE_NONE:
    TFR X,D
    RTS

;; Draws by a distance from the last point, scaled by <SCALE> and turned by <ANGLE>.
;;
;; In:   D = the distance across, X = down
DRAWBY:
    PSHS A,B
    BSR DRAWSCALE
    PULS X
    PSHS A,B
    BSR DRAWSCALE
    PULS X
    LDY ANGLE
    PSHS Y
DRAWBY_TURN:
    TST ,S
    BEQ DRAWBY_ADD
    EXG X,D                         ; a quarter turn clockwise
    BSR NEGD
    DEC ,S
    BRA DRAWBY_TURN
DRAWBY_ADD:
    PULS Y
    LDU ZERO
    ADDD HORDEF
    BMI DRAWBY_Y                    ; off the left: 0
    TFR D,U
DRAWBY_Y:
    TFR X,D
    LDX ZERO
    ADDD VERDEF
    BMI DRAWTO                      ; off the top: 0
    TFR D,X
;; Draws a line from the last point to U, X, kept on the screen, unless B came before; it becomes the last point,
;; unless N came before.
DRAWTO:
    CMPU #256
    BLO DRAWTO_Y
    LDU #255
DRAWTO_Y:
    CMPX #192
    BLO DRAWTO_LINE
    LDX #191
DRAWTO_LINE:
    LDD HORDEF
    STD HORBEG
    LDD VERDEF
    STD VERBEG
    STX VEREND
    STU HOREND
    TST VD5
    BNE DRAWTO_DRAW
    STX VERDEF
    STU HORDEF
DRAWTO_DRAW:
    JSR LINESCALE
    TST VD6
    BNE DRAWTO_DONE
    JSR DLINE
DRAWTO_DONE:
    CLR VD5
    CLR VD6
    JMP DRAW_NEXT

;; DRAW's M x,y: a line to the point, or by the distances when x has a sign.
DRAW_M:
    JSR PLAYCHR
    PSHS A
    JSR DRAWNUM_SIGN
    PSHS A,B
    JSR PLAYCHR
    CMPA #','
    LBNE DRAW_FC
    JSR DRAWNUM
    TFR D,X
    PULS U
    PULS A
    CMPA #'+'
    BEQ DRAW_M_RELATIVE
    CMPA #'-'
    BNE DRAWTO
DRAW_M_RELATIVE:
    TFR U,D
    JMP DRAWBY

;; Reads a number with an optional sign, for DRAW's M.
;;
;; Out:  D = the number
DRAWNUM:
    JSR PLAYCHR
DRAWNUM_SIGN:
    CMPA #'+'
    BEQ DRAWNUM_PLUS
    CMPA #'-'
    BEQ DRAWNUM_READ                ; A nonzero: negative
    JSR PLAYBACK
DRAWNUM_PLUS:
    CLRA
DRAWNUM_READ:
    PSHS A
    JSR PLAYARG
    PULS A
    TSTA
    BEQ DRAWNUM_DONE
    CLRA
    NEGB
    SBCA #0
DRAWNUM_DONE:
    RTS

;; The cosines and sines of each 64th of a turn through an eighth, as 16-bit fractions plus 1, so that 0 is 1.
CIRCTAB:
    .dbyt $0000, $0001
    .dbyt $FEC5, $1919
    .dbyt $FB16, $31F2
    .dbyt $F4FB, $4A51
    .dbyt $EC84, $61F9
    .dbyt $E1C7, $78AE
    .dbyt $D4DC, $8E3B
    .dbyt $C5E5, $A269
    .dbyt $B506, $B506

;; Runs CIRCLE (x,y),r[,color[,ratio[,start[,end]]]]: draws a circle, an ellipse whose height is ratio times its
;; width, or an arc of either from start to end, as fractions of a turn clockwise from the right. It draws lines
;; between points a 64th of a turn apart.
;;
;; Errors: ?FC ERROR when the ratio makes it too tall
CIRCLE:
    CMPA #'@'
    BNE CIRCLE_CENTER
    JSR GETNCH
CIRCLE_CENTER:
    JSR GRLIMIT
    JSR PARXY
    JSR GRSCALE
    LDX ,U
    STX VCB                         ; the center
    LDX 2,U
    STX VCD
    JSR SYNCOM
    JSR GETADR
    LDU #VCF
    STX ,U                          ; the radius
    JSR GRSCALE_AT
    LDA #1
    STA SETFLG
    JSR PSETCOLOR
    LDX #$0100                      ; a ratio of 1, in 256ths
    JSR GETCCH
    BEQ CIRCLE_RATIO
    JSR SYNCOM
    JSR FRMNUM
    LDA FP0EXP
    ADDA #8
    STA FP0EXP                      ; times 256
    JSR ADRCHK
CIRCLE_RATIO:
    LDA PMODE
    BITA #$02
    BEQ CIRCLE_ARC
    TFR X,D
    LEAX D,X                        ; twice as tall in PMODEs 2 and 3
CIRCLE_ARC:
    STX VD1
    LDB #1
    STB SETFLG
    STB VD8                         ; the first point: no line to it
    JSR CIRCARG
    PSHS A,B                        ; the start
    JSR CIRCARG
    STD VD9                         ; the end
    PULS A,B
CIRCLE_POINT:
    PSHS A,B                        ; the eighth and the 64th in it
    LDX HOREND
    STX HORBEG
    LDX VEREND
    STX VERBEG                      ; from the last point
    LDU #CIRCTAB + 2
    ANDA #$01
    BEQ CIRCLE_STEP
    NEGB                            ; odd eighths go backward
    ADDB #8
CIRCLE_STEP:
    ASLB
    ASLB
    LEAU B,U
    PSHS U
    JSR CIRCMUL                     ; the sine times the radius
    PULS U
    LEAU -2,U
    PSHS X
    JSR CIRCMUL                     ; the cosine times the radius
    PULS Y
    LDA ,S
    ANDA #$03
    BEQ CIRCLE_OFFSETS
    CMPA #$03
    BEQ CIRCLE_OFFSETS
    EXG X,Y
CIRCLE_OFFSETS:
    STX HOREND
    TFR Y,X
    LDD VD1
    JSR MUL16                       ; down, times the ratio
    TFR Y,D
    TSTA
    LBNE FCERR
    STB VEREND
    TFR U,D
    STA VEREND+1
    LDA ,S
    CMPA #2
    BLO CIRCLE_RIGHT
    CMPA #6
    BHS CIRCLE_RIGHT
    LDD VCB                         ; eighths 2 to 5: left of the center
    SUBD HOREND
    BHS CIRCLE_X
    CLRA
    CLRB
    BRA CIRCLE_X
CIRCLE_RIGHT:
    LDD VCB
    ADDD HOREND
    BLO CIRCLE_RIGHT_EDGE
    CMPD VD3
    BLO CIRCLE_X
CIRCLE_RIGHT_EDGE:
    LDD VD3
CIRCLE_X:
    STD HOREND
    LDA ,S
    CMPA #4
    BLO CIRCLE_DOWN
    LDD VCD                         ; eighths 4 to 7: above it
    SUBD VEREND
    BHS CIRCLE_Y
    CLRA
    CLRB
    BRA CIRCLE_Y
CIRCLE_DOWN:
    LDD VCD
    ADDD VEREND
    BLO CIRCLE_DOWN_EDGE
    CMPD VD5
    BLO CIRCLE_Y
CIRCLE_DOWN_EDGE:
    LDD VD5
CIRCLE_Y:
    STD VEREND
    TST VD8
    BNE CIRCLE_NEXT
    BSR CIRCLINE
CIRCLE_NEXT:
    PULS A,B
    LSR VD8
    BLO CIRCLE_ADVANCE              ; the first point: past the end too
    CMPD VD9
    BEQ CIRCLE_DONE
CIRCLE_ADVANCE:
    INCB
    CMPB #8
    BNE CIRCLE_AGAIN
    INCA
    CLRB
    ANDA #$07
CIRCLE_AGAIN:
    JMP CIRCLE_POINT
CIRCLE_DONE:
    RTS

;; Multiplies the radius by a cosine or sine from <CIRCTAB>.
;;
;; In:   U = the entry
;; Out:  X = the product
CIRCMUL:
    LDX VCF
    LDD ,U
    BEQ CIRCMUL_DONE                ; 1: the radius
    SUBD #1
    BSR MUL16
    TFR Y,X
CIRCMUL_DONE:
    RTS

;; Multiplies two 16-bit numbers.
;;
;; In:   D, X = the numbers
;; Out:  Y = the product's high 16 bits, U = its low
MUL16:
    PSHS A,B,X,Y,U
    CLR 4,S
    LDA 3,S
    MUL
    STD 6,S
    LDD 1,S
    MUL
    ADDB 6,S
    ADCA #0
    STD 5,S
    LDB ,S
    LDA 3,S
    MUL
    ADDD 5,S
    STD 5,S
    BHS MUL16_HIGH
    INC 4,S
MUL16_HIGH:
    LDA ,S
    LDB 2,S
    MUL
    ADDD 4,S
    STD 4,S
    PULS A,B,X,Y,U,PC

CIRCLINE:
    JMP DLINE

;; Reads CIRCLE's start or end, a fraction of a turn, as 64ths: 0 when there is none.
;;
;; Out:  A = the eighth, B = the 64th in it
CIRCARG:
    CLRB
    JSR GETCCH
    BEQ CIRCARG_SPLIT
    JSR SYNCOM
    JSR FRMNUM
    LDA FP0EXP
    ADDA #6
    STA FP0EXP                      ; times 64
    JSR BYTCHK
    ANDB #$3F
CIRCARG_SPLIT:
    TFR B,A
    ANDB #$07
    LSRA
    LSRA
    LSRA
    RTS