; ---------------------------------------------------------------------------------------------------------------------
; The write request
; ---------------------------------------------------------------------------------------------------------------------

;; The write request: writes the caller's bytes through <PRINT>, with the cursor off while it does.
;;
;; It waits while output is suspended. When output is being thrown away it stops, dropping the rest and any control code
;; half collected.
;; In: BUFFPTR = the bytes, REQCNT = how many
;; Errors: XNOTOPEN (through <SYSERR>)
;; Uses: A, X, Y, COUNT
CNSLWRIT:
    bit a:OPENFLG
    bmi @L010
    jmp CNOTOPEN
@L010:
    jsr CURSOR
    lda #$00
    sta COUNT
    sta COUNT+$01
@L020:
    lda COUNT
    cmp REQCNT
    lda COUNT+$01
    sbc REQCNT+$01
    bcs @L060
@L030:
    bit SUSPFLSH
    bmi @L030                       ; suspended: wait
    bvs @L050                       ; thrown away: stop
    ldy #$00
    lda (BUFFPTR),y
    jsr PRINT
    inc BUFFPTR
    bne @L040
    inc BUFFPTR+$01
    bne @L040
    lda #$80
    sta BUFFPTR+$01
    inc $1400+BUFFPTR+$01           ; the next bank
@L040:
    inc COUNT
    bne @L020
    inc COUNT+$01
    jmp @L020
@L050:
    lda #$00
    sta a:CTLINDX
@L060:
    jsr CURSOR
    jmp ZPOUT

;; Writes one byte to the screen: shows a character (<DISPLAY>), or carries out a control code.
;;
;; A control code is collected in <CTLBUFF> with the parameter bytes <QUOTATBL> says it takes, then carried out through
;; <CTLSWTBL>. While control characters are being shown (<DSPLYCTL>), every byte is shown as a character.
;; In: A = the byte
;; Uses: A, X, Y
PRINT:
    ldy a:CTLINDX
    bne @L010                       ; a parameter for the control code being collected
    ora a:DSPLYCTL
    cmp #<ASC_SP
    bcs DISPLAY
    tax
    lda QUOTATBL,x
    beq @L020                       ; a control code that does nothing
    sta a:CTLQUOTA
    txa
@L010:
    sta a:CTLBUFF,y
    iny
    sty a:CTLINDX
    cpy a:CTLQUOTA
    bcc @L020
    ldy #$00
    sty a:CTLINDX
    SWITCH a:CTLBUFF, , CTLSWTBL, *
@L020:
    rts

;; Shows a character at the cursor, in normal or inverse video and, in 40 columns, in the text colors, then advances the
;; cursor if automatic advance is on.
;; In: A = the character
;; Uses: A, X, Y
DISPLAY:
    ora #$80
    eor a:SMINV
    pha
    bit a:HMODE
    bpl @L010                       ; 40 columns
    lda a:TPX
    lsr a
    tay
    bcc @L020                       ; an even column
    pla
    sta (BASE2),y
    bcs @L030
@L010:
    ldy a:TPX
    lda a:TCOLOR
    sta (BASE2),y
@L020:
    pla
    sta (BASE1),y
@L030:
    bit a:SMAUTOADV
    bpl @L040
    jmp CF_HT
@L040:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Control code tables
; ---------------------------------------------------------------------------------------------------------------------

;; How many bytes each control code $00-$1F takes, the code included; 0 for the codes that do nothing, $00 and $1B.
QUOTATBL:
    .res $01, $00
    .res 15, $01
    .res $01, $02
    .res $02, $01
    .res $02, $02
    .res $01, $02
    .res $01, $01
    .res $03, $02
    .res $01, $03
    .res $01, $00
    .res $04, $01

;; The control codes' routines, less one, for <SWITCH>.
CTLSWTBL:
    .word CF_NUL-$01
    .word CF_SOH-$01
    .word CF_STX-$01
    .word CF_ETX-$01
    .word CF_EOT-$01
    .word CF_ENQ-$01
    .word CF_ACK-$01
    .word CF_BEL-$01
    .word CF_BS-$01
    .word CF_HT-$01
    .word CF_LF-$01
    .word CF_VT-$01
    .word CF_FF-$01
    .word CF_CR-$01
    .word CF_SO-$01
    .word CF_SI-$01
    .word CF_DLE-$01
    .word CF_DC1-$01
    .word CF_DC2-$01
    .word CF_DC3-$01
    .word CF_DC4-$01
    .word CF_NAK-$01
    .word CF_SYN-$01
    .word CF_ETB-$01
    .word CF_CAN-$01
    .word CF_EM-$01
    .word CF_SUB-$01
    .word CF_ESC-$01
    .word CF_FS-$01
    .word CF_GS-$01
    .word CF_RS-$01
    .word CF_US-$01
