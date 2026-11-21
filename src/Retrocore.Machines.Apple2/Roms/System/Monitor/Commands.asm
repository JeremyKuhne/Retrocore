;; Copies A1 to PCL/PCH when the command gave an address (X is not zero).
A1PC:
    txa                             ; $FE75
    beq A1PCRTS                     ; $FE76

A1PCLP:
    lda A1L,x                       ; $FE78
    sta PCL,x                       ; $FE7A
    dex                             ; $FE7C
    bpl A1PCLP                      ; $FE7D

A1PCRTS:
    rts                             ; $FE7F

;; Sets inverse text: INVFLG = $3F.
SETINV:
    ldy #$3F                        ; $FE80
    bne SETIFLG                     ; $FE82

;; Sets normal text: INVFLG = $FF.
SETNORM:
    ldy #$FF                        ; $FE84

SETIFLG:
    sty INVFLG                      ; $FE86
    rts                             ; $FE88

;; Sets the input hook to the keyboard (KEYIN).
SETKBD:
    lda #$00                        ; $FE89

;; Sets the input hook to a slot.
;; In: A = slot (0 for the keyboard)
INPORT:
    sta A2L                         ; $FE8B

INPRT:
    ldx #KSWL                       ; $FE8D
    ldy #<KEYIN                     ; $FE8F
    bne IOPRT                       ; $FE91

;; Sets the output hook to the screen (COUT1).
SETVID:
    lda #$00                        ; $FE93

;; Sets the output hook to a slot.
;; In: A = slot (0 for the screen)
OUTPORT:
    sta A2L                         ; $FE95

OUTPRT:
    ldx #CSWL                       ; $FE97
    ldy #<COUT1                     ; $FE99

IOPRT:
    lda A2L                         ; $FE9B
    and #$0F                        ; $FE9D
.if ENHANCED
    beq IOPRT_1                     ; $FE9F
.else
    beq IOPRT1                      ; $FE9F
.endif
    ora #$C0                        ; $FEA1
    ldy #$00                        ; $FEA3

IOPRT_1:
.if .not ENHANCED
    beq IOPRT2                      ; $FEA5

IOPRT1:
    lda #>COUT1                     ; $FEA7

IOPRT2:
.endif
    sty LOC0,x                      ; $FEA5 original $FEA9
    sta LOC1,x                      ; $FEA7 original $FEAB
.if ENHANCED
    ldy #$0E                        ; $FEA9
    jmp GOTOCX                      ; $FEAB
.else
    rts                             ; $FEAD
.endif
    .byte $EA                       ; $FEAE

CKSUMFIX:
.if ENHANCED
    .byte $00                       ; $FEAF
.elseif MONITOR = MONITOR_IIE
    .byte $D1                       ; $FEAF
.else
    .byte $EA                       ; $FEAF
.endif

;; Monitor Control-B: starts AppleSoft (cold).
;;
;; On an Apple II, $E000 starts whichever BASIC its ROMs hold, Integer BASIC or AppleSoft.
XBASIC:
    jmp BASIC                       ; $FEB0

;; Monitor Control-C: continues AppleSoft (warm).
BASCONT:
    jmp BASIC2                      ; $FEB3

;; Monitor G command: restores the registers and runs the program at A1 (or the current PC).
GO:
    jsr A1PC                        ; $FEB6
    jsr RESTORE                     ; $FEB9
    jmp (PCL)                       ; $FEBC

;; Monitor Control-E: shows the registers.
REGZ:
    jmp REGDSP                      ; $FEBF

;; Monitor T command: tracing was removed on the IIe; does nothing.
;;
;; The Autostart Monitor does nothing here either. In the Apple II Monitor, T steps the program
;; without end: it moves YSAV back onto the T, so that after each step (STEPZ, which it falls into)
;; the command line performs the T again. A BRK in the program, or reset, stops it.
TRACE:
.if MONITOR = MONITOR_II
    dec YSAV                        ; $FEC2
.else
    rts                             ; $FEC2
    .byte $EA                       ; $FEC3
.endif

;; Monitor S command: single-stepping was removed on the IIe; does nothing.
;;
;; The Autostart Monitor does nothing here either. In the Apple II Monitor, S runs one instruction of
;; the program, at A1 when the command gives an address (A1PC), and shows it and the registers (STEP).
STEPZ:
.if MONITOR = MONITOR_II
    jsr A1PC                        ; $FEC4
    jmp STEP                        ; $FEC7
.else
    rts                             ; $FEC4
.if MONITOR = MONITOR_AUTOSTART
    .res 5, $EA                     ; $FEC5 unused; the S command's Control-Y entry runs on into USR
.else

;; Enhanced IIe: switches slot ROM back in and returns (internal firmware calls end here).
;; The original IIe has unused bytes here.
SLOTRTS:
.if ENHANCED
    sta SETSLOTCXROM                ; $FEC5
.else
    .byte "Bry"                     ; $FEC5 with the next two bytes, "Bryan"
.endif

SLOTRTS_1:
.if ENHANCED
    rts                             ; $FEC8
    .byte $EA                       ; $FEC9
.else
    .byte "an"                      ; $FEC8
.endif
.endif
.endif

;; Monitor Control-Y: jumps to the user routine at USRADR ($03F8).
USR:
    jmp USRADR                      ; $FECA

;; Monitor W command: writes A1-A2 to cassette.
;; The Enhanced IIe calls the cassette routine in internal ROM.
WRITE:
    lda #$40                        ; $FECD
.if ENHANCED
    sta SETINTCXROM                 ; $FECF
    jsr WRITETAPE                   ; $FED2
    beq READ_1                      ; $FED5

;; Enhanced IIe: prints the address of each place from A1 to A2 that holds the byte in A4L,
;; followed by A4H when A4H is not zero.
MEMFIND:
    ldy #$01                        ; $FED7
    lda A4H                         ; $FED9
    beq MEMFIND_1                   ; $FEDB
    cmp (A1L),y                     ; $FEDD
    bne MEMFIND_2                   ; $FEDF
.else
    jsr HEADR                       ; $FECF
    ldy #$27                        ; $FED2

WR1:
    ldx #$00                        ; $FED4
    eor (A1L,x)                     ; $FED6
    pha                             ; $FED8
    lda (A1L,x)                     ; $FED9
    jsr WRBYTE                      ; $FEDB
    jsr NXTA1                       ; $FEDE
.endif

MEMFIND_1:
.if ENHANCED
    dey                             ; $FEE1
    lda A4L                         ; $FEE2
    cmp (A1L),y                     ; $FEE4
    bne MEMFIND_2                   ; $FEE6
    jsr PRA1                        ; $FEE8
.else
    ldy #$1D                        ; $FEE1
    pla                             ; $FEE3
    bcc WR1                         ; $FEE4
    ldy #$22                        ; $FEE6
    jsr WRBYTE                      ; $FEE8
.endif

MEMFIND_2:
.if ENHANCED
    jsr NXTA1                       ; $FEEB
    bcc MEMFIND                     ; $FEEE
.else
    beq BELL                        ; $FEEB

WRBYTE:
    ldx #$10                        ; $FEED

WRBYT2:
    asl a                           ; $FEEF
    jsr WRBIT                       ; $FEF0
    bne WRBYT2                      ; $FEF3
.endif
    rts                             ; $FEF0 original $FEF5
.if ENHANCED

;; Enhanced IIe: enters the mini-assembler in the internal firmware (function $0D).
MINIASM:
    ldy #$0D                        ; $FEF1
    jsr GOTOCX                      ; $FEF3
.endif

;; Monitor command line: a carriage return ends the line; examines the next lines and returns to the
;; prompt.
CRMON:
    jsr BL1                         ; $FEF6
    pla                             ; $FEF9
    pla                             ; $FEFA
    bne MONZ                        ; $FEFB

;; Monitor R command: reads cassette data into A1-A2, then beeps, or prints ERR on a checksum error.
;; The Enhanced IIe calls the cassette routine in internal ROM.
READ:
.if ENHANCED
    sta SETINTCXROM                 ; $FEFD
    jsr READTAPE                    ; $FF00

READ_1:
    sta SETSLOTCXROM                ; $FF03
    beq BELL                        ; $FF06
    bne PRERR                       ; $FF08

;; Enhanced IIe: the title, "Apple //e", copied by APPLEII.
TITLE2E:
    .byte "Apple //e"               ; $FF0A

;; Enhanced IIe: Monitor input: skips blanks, returning the next character.
SKIPBLNK:
    jsr UPMON                       ; $FF13
    cmp #' '                        ; $FF16
    beq SKIPBLNK                    ; $FF18
    rts                             ; $FF1A
.else
    jsr RD2BIT                      ; $FEFD
    lda #$16                        ; $FF00
    jsr HEADR                       ; $FF02
    sta MASK                        ; $FF05
    jsr RD2BIT                      ; $FF07

RD2:
    ldy #$24                        ; $FF0A
    jsr RDBIT                       ; $FF0C
    bcs RD2                         ; $FF0F
    jsr RDBIT                       ; $FF11
    ldy #$3B                        ; $FF14

RD3:
    jsr RDBYTE                      ; $FF16
    sta (A1L,x)                     ; $FF19
.endif

RD3_1:
.if ENHANCED
    bcs DIG                         ; $FF1B
    cmp #' '                        ; $FF1D
    bne RESTR1_1                    ; $FF1F
    lda IN,y                        ; $FF21
    ldx #$07                        ; $FF24
    cmp #KEY_CR                     ; $FF26
    beq GETNUM                      ; $FF28
    iny                             ; $FF2A
    bne NXTBIT                      ; $FF2B
.else
    eor MASK                        ; $FF1B
    sta MASK                        ; $FF1D
    jsr NXTA1                       ; $FF1F
    ldy #$35                        ; $FF22
    bcc RD3                         ; $FF24
    jsr RDBYTE                      ; $FF26
    cmp MASK                        ; $FF29
    beq BELL                        ; $FF2B
.endif

;; Prints "ERR" and beeps.
PRERR:
    lda #'E'                        ; $FF2D
    jsr COUT                        ; $FF2F
    lda #'R'                        ; $FF32
    jsr COUT                        ; $FF34
    jsr COUT                        ; $FF37

;; Beeps by printing Control-G.
BELL:
    lda #KEY_BELL                   ; $FF3A
    jmp COUT                        ; $FF3C

;; Restores A, X, Y and P from A5H, XREG, YREG and STATUS.
RESTORE:
    lda STATUS                      ; $FF3F
    pha                             ; $FF41
    lda A5H                         ; $FF42

RESTR1:
    ldx XREG                        ; $FF44
    ldy YREG                        ; $FF46
    plp                             ; $FF48

RESTR1_1:
    rts                             ; $FF49

;; Saves A, X, Y, P and S in A5H, XREG, YREG, STATUS and SPNT, and clears decimal mode.
SAVE:
    sta A5H                         ; $FF4A

SAV1:
    stx XREG                        ; $FF4C
    sty YREG                        ; $FF4E
    php                             ; $FF50
    pla                             ; $FF51
    sta STATUS                      ; $FF52
    tsx                             ; $FF54
    stx SPNT                        ; $FF55
    cld                             ; $FF57
    rts                             ; $FF58
