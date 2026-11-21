;; Monitor examine: shows the eight bytes from A1 (to the next multiple of 8).
XAM8:
    lda A1L                         ; $FDA3
    ora #$07                        ; $FDA5
    sta A2L                         ; $FDA7
    lda A1H                         ; $FDA9
    sta A2H                         ; $FDAB

MOD8CHK:
    lda A1L                         ; $FDAD
    and #$07                        ; $FDAF
    bne DATAOUT                     ; $FDB1

;; Monitor examine: shows memory from A1 to A2, eight bytes per line.
XAM:
    jsr PRA1                        ; $FDB3

DATAOUT:
    lda #' '                        ; $FDB6
    jsr COUT                        ; $FDB8
    lda (A1L),y                     ; $FDBB
    jsr PRBYTE                      ; $FDBD
    jsr NXTA1                       ; $FDC0
    bcc MOD8CHK                     ; $FDC3

RTS4C:
    rts                             ; $FDC5

;; Monitor + and - commands: prints A1 plus or minus A2 as "=xx".
XAMPM:
    lsr a                           ; $FDC6
    bcc XAM                         ; $FDC7
    lsr a                           ; $FDC9
    lsr a                           ; $FDCA
    lda A2L                         ; $FDCB
    bcc ADD                         ; $FDCD
    eor #$FF                        ; $FDCF

ADD:
    adc A1L                         ; $FDD1
    pha                             ; $FDD3
    lda #'='                        ; $FDD4
    jsr COUT                        ; $FDD6
    pla                             ; $FDD9

;; Prints A as two hex digits.
PRBYTE:
    pha                             ; $FDDA
    lsr a                           ; $FDDB
    lsr a                           ; $FDDC
    lsr a                           ; $FDDD
    lsr a                           ; $FDDE
    jsr PRHEXZ                      ; $FDDF
    pla                             ; $FDE2

;; Prints the low four bits of A as a hex digit.
PRHEX:
    and #$0F                        ; $FDE3

PRHEXZ:
    ora #'0'                        ; $FDE5
    cmp #'9' + 1                    ; $FDE7
    bcc COUT                        ; $FDE9
    adc #$06                        ; $FDEB

;; Prints a character through the output hook, CSWL.
;; In: A = character with the high bit set
COUT:
    jmp (CSWL)                      ; $FDED

;; The screen's output routine (CSWL's default): applies INVFLG to printable characters, then prints
;; with the Control-S pause (VIDWAIT).
;; Keeps: A, Y
COUT1:
.if ENHANCED
    pha                             ; $FDF0
.endif
    cmp #' '                        ; $FDF1 original $FDF0
.if ENHANCED
    jmp DOCOUT1                     ; $FDF3
.else
    bcc COUTZ                       ; $FDF2
    and INVFLG                      ; $FDF4
.endif

;; Prints a character on the screen without applying INVFLG.
;;
;; The Apple II Monitor prints with VIDOUT, without the Control-S pause.
;; Keeps: A, Y
COUTZ:
.if ENHANCED
    pha                             ; $FDF6

COUTZ_1:
.endif
    sty YSAV1                       ; $FDF7 original $FDF6
.if ENHANCED
    tay                             ; $FDF9
.else
    pha                             ; $FDF8
.if MONITOR = MONITOR_II
    jsr VIDOUT                      ; $FDF9
.else
    jsr VIDWAIT                     ; $FDF9
.endif
.endif
    pla                             ; $FDFA original $FDFC
.if ENHANCED
    jmp CLREOP_1                    ; $FDFB
    .byte $EA, $EA                  ; $FDFE
.else
    ldy YSAV1                       ; $FDFD
    rts                             ; $FDFF
.endif

;; Monitor command line: counts down the examine-on-return line (part of the blank handler).
BL1:
    dec YSAV                        ; $FE00
    beq XAM8                        ; $FE02

;; Monitor command line: a blank or colon after a number. After a colon, stores the number at A3 and
;; advances A3.
BLANK:
    dex                             ; $FE04
    bne SETMDZ                      ; $FE05
    cmp #':'                        ; $FE07
    bne XAMPM                       ; $FE09

STOR:
    sta MODE                        ; $FE0B
    lda A2L                         ; $FE0D
    sta (A3L),y                     ; $FE0F
    inc A3L                         ; $FE11
    bne RTS5                        ; $FE13
    inc A3H                         ; $FE15

RTS5:
    rts                             ; $FE17

;; Monitor command line: sets MODE from the command character (".", ":", "+", "-").
SETMODE:
    ldy YSAV                        ; $FE18
    lda $01FF,y                     ; $FE1A

;; Sets MODE from A.
SETMDZ:
    sta MODE                        ; $FE1D
    rts                             ; $FE1F

;; Monitor < command: copies A2 to A4 and A5, the destination of MOVE and VFY.
LT:
    ldx #$01                        ; $FE20

;; Copies A2 to A4 and A5 (from LT).
LT2:
    lda A2L,x                       ; $FE22
    sta A4L,x                       ; $FE24
    sta A5L,x                       ; $FE26
    dex                             ; $FE28
    bpl LT2                         ; $FE29
    rts                             ; $FE2B

;; Monitor M command: copies A1-A2 to A4.
MOVE:
    lda (A1L),y                     ; $FE2C
    sta (A4L),y                     ; $FE2E
    jsr NXTA4                       ; $FE30
    bcc MOVE                        ; $FE33
    rts                             ; $FE35

;; Monitor V command: compares A1-A2 with the memory at A4, printing each difference as
;; "AAAA-xx (yy)".
VFY:
    lda (A1L),y                     ; $FE36
    cmp (A4L),y                     ; $FE38
    beq VFY_1                       ; $FE3A
    jsr PRA1                        ; $FE3C
    lda (A1L),y                     ; $FE3F
    jsr PRBYTE                      ; $FE41
    lda #' '                        ; $FE44
    jsr COUT                        ; $FE46
    lda #'('                        ; $FE49
    jsr COUT                        ; $FE4B
    lda (A4L),y                     ; $FE4E
    jsr PRBYTE                      ; $FE50
    lda #')'                        ; $FE53
    jsr COUT                        ; $FE55

VFY_1:
    jsr NXTA4                       ; $FE58

VFYOK:
    bcc VFY                         ; $FE5B
    rts                             ; $FE5D

;; Monitor L command: disassembles 20 instructions from A1 (or the current PC).
LIST:
    jsr A1PC                        ; $FE5E
    lda #$14                        ; $FE61

LIST2:
    pha                             ; $FE63
    jsr INSTDSP                     ; $FE64
    jsr PCADJ                       ; $FE67
    sta PCL                         ; $FE6A
    sty PCH                         ; $FE6C
    pla                             ; $FE6E
    sec                             ; $FE6F
    sbc #$01                        ; $FE70
    bne LIST2                       ; $FE72
    rts                             ; $FE74
