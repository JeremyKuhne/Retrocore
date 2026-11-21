;; Delays.
;; In: A = count
;; Takes about (26 + 27A + 5A^2) / 2 microseconds.
;; Out: A = 0.
WAIT:
    sec                             ; $FCA8

WAIT2:
    pha                             ; $FCA9

WAIT3:
    sbc #$01                        ; $FCAA
    bne WAIT3                       ; $FCAC
    pla                             ; $FCAE
    sbc #$01                        ; $FCAF
    bne WAIT2                       ; $FCB1
    rts                             ; $FCB3

;; Increments A4, then does NXTA1 (used by MOVE to step source and destination together).
NXTA4:
    inc A4L                         ; $FCB4
    bne NXTA1                       ; $FCB6
    inc A4H                         ; $FCB8

;; Compares A1 with A2, then increments A1.
;; Out:   carry = set when A1 was at or past A2 (the range is finished)
NXTA1:
    lda A1L                         ; $FCBA
    cmp A2L                         ; $FCBC
    lda A1H                         ; $FCBE
    sbc A2H                         ; $FCC0
    inc A1L                         ; $FCC2
    bne RTS4B                       ; $FCC4
    inc A1H                         ; $FCC6

RTS4B:
    rts                             ; $FCC8

;; Writes a cassette header tone.
;; Original IIe: a tone of A times 256 half cycles, then the sync bit.
;; Enhanced IIe: the cassette routines live in internal ROM; this calls them there.
HEADR:
.if ENHANCED
    sta SETINTCXROM                 ; $FCC9
    jsr TAPEHEADR                   ; $FCCC
    jmp SLOTRTS                     ; $FCCF
.else
    ldy #$4B                        ; $FCC9
    jsr ZERDLY                      ; $FCCB
    bne HEADR                       ; $FCCE
    adc #$FE                        ; $FCD0
.endif

HEADR_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FCD2
    jsr PRBL2                       ; $FCD5
    lda #'^'                        ; $FCD8
    jsr COUT                        ; $FCDA
    jsr BELL                        ; $FCDD
    jmp RDBYT2_1                    ; $FCE0
.else
    bcs HEADR                       ; $FCD2
    ldy #$21                        ; $FCD4

WRBIT:
    jsr ZERDLY                      ; $FCD6
    iny                             ; $FCD9
    iny                             ; $FCDA

ZERDLY:
    dey                             ; $FCDB
    bne ZERDLY                      ; $FCDC
    bcc WRTAPE                      ; $FCDE
    ldy #$32                        ; $FCE0

ONEDLY:
    dey                             ; $FCE2
.endif

ONEDLY_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FCE3
    jsr INSTDSP                     ; $FCE6
    jsr PCADJ                       ; $FCE9
.else
    bne ONEDLY                      ; $FCE3

WRTAPE:
    ldy TAPEOUT                     ; $FCE5
    ldy #$2C                        ; $FCE8
    dex                             ; $FCEA
    rts                             ; $FCEB
.endif

; Original IIe: reads one byte from the cassette.
; Out: A = the byte.
; The Enhanced IIe uses these bytes for its command line (input of the mini-assembler and the
; uppercase conversion of Monitor input).
.if ENHANCED
    sty PCH                         ; $FCEC
    sta PCL                         ; $FCEE

RDBYT2_1:
    lda #'!'                        ; $FCF0
    sta PROMPT                      ; $FCF2
    jsr GETLNZ                      ; $FCF4
    sta SETINTCXROM                 ; $FCF7
.else

RDBYTE:
    ldx #$08                        ; $FCEC

RDBYT2:
    pha                             ; $FCEE
    jsr RD2BIT                      ; $FCEF
    pla                             ; $FCF2
    rol a                           ; $FCF3
    ldy #$3A                        ; $FCF4
    dex                             ; $FCF6
    bne RDBYT2                      ; $FCF7
    rts                             ; $FCF9
.endif

; Original IIe: reads a cassette bit as the time between two transitions.
; Out: carry = the bit.
; The Apple II's Monitors read cassette bits the same way; their listings call LENGTH LASTIN here.
.if ENHANCED
    jmp MINILINE                    ; $FCFA

UPMON:
    lda IN,y                        ; $FCFD
    iny                             ; $FD00
    cmp #'a'                        ; $FD01
    bcc RDBIT_1                     ; $FD03
    cmp #'z' + 1                    ; $FD05
    bcs RDBIT_1                     ; $FD07
    and #$DF                        ; $FD09 to uppercase
.else

RD2BIT:
    jsr RDBIT                       ; $FCFA

RDBIT:
    dey                             ; $FCFD
    lda TAPEIN                      ; $FCFE
    eor LENGTH                      ; $FD01
    bpl RDBIT                       ; $FD03
    eor LENGTH                      ; $FD05
    sta LENGTH                      ; $FD07
    cpy #$80                        ; $FD09
.endif

RDBIT_1:
    rts                             ; $FD0B
