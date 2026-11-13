;; Clears from the cursor to the end of the viewport.
;; Entry: CLREOS1 = from the screen line in X and the column in Y
;; Uses: A, X, Y, BLANK, TEMPX
CLREOS:
    clc
    lda a:TPY
    adc a:VPT
    tax
    ldy a:TPX
CLREOS1:
@L010:
    jsr TBASCAL1
    jsr CLREOL1
    ldy #$00
    cpx a:VPB
    inx
    bcc @L010
    jmp TBASCAL

;; Scrolls the viewport's text up or down a line and clears the line that comes in.
;; In: A = $00 to scroll up, $80 to scroll down
;; Uses: A, X, Y, FLAGS, TEMP1, WORK1, WORK2
SCROLL:
    sta FLAGS
    sec
    lda a:VPHMAX
    bit a:HMODE
    bpl @L010
    lsr a
@L010:
    sta TEMP1
    ror FLAGS
    ldx a:VPT
    bit FLAGS
    bvc @L020
    ldx a:VPB
@L020:
    jsr TBASCAL1
@L030:
    bit FLAGS
    bvc @L040
    cpx a:VPT
    beq @L080
    dex
    bpl @L050
@L040:
    cpx a:VPB
    beq @L080
    inx
@L050:
    lda BASE1
    ldy BASE1+$01
    sta WORK1
    sty WORK1+$01
    lda BASE2
    ldy BASE2+$01
    sta WORK2
    sty WORK2+$01
    jsr TBASCAL1
    ldy TEMP1
    bit FLAGS
    bpl @L070
@L060:
    lda (BASE2),y
    sta (WORK2),y
@L070:
    lda (BASE1),y
    sta (WORK1),y
    dey
    bpl @L060
    bmi @L030
@L080:
    ldy #$00
    jsr CLREOL1
    jmp TBASCAL

;; Shifts the viewport's text left or right, clearing the columns that come in; a shift of the viewport's width or more
;; clears it.
;; In: A = the shift, signed: negative to the left, positive to the right, 0 for none
;; Uses: A, X, Y, BLANK, TEMPX, FLAGS, TEMP1, TEMP2, TEMP3, TEMP4, WORK1, WORK2
SHIFT:
    tay
    beq @L020
    and #<BITON7
    sta FLAGS
    tya
    cmp #$80
    bcc @L010
    eor #$FF
@L010:
    adc #$00
    sta TEMP1
    adc a:VPL
    sta TEMP2
    ldx a:VPT
    sec
    lda a:VPHMAX
    sbc TEMP1
    bcs @L030
    ldy #$00
    jsr CLREOS1
@L020:
    rts
@L030:
    bit FLAGS
    bmi @L060
    sec
    bit a:HMODE
    bpl @L040
    lsr a
@L040:
    sta TEMP3
    lda #<BITON6
    bcs @L050
    lda #$00
@L050:
    ora FLAGS
    sta FLAGS
    ldy TEMP1
    dey
    sty TEMP4
    lda #<($80+ASC_SP)
    eor a:SMINV
    sta BLANK
    jmp SHIFT1                      ; shift right
@L060:
    tay
    bit a:HMODE
    bmi @L070
    sec
    rol a
@L070:
    sta TEMP3
    iny
    sty TEMP4
SHIFT1:
    jsr TBASCAL1
    clc
    lda TEMP2
    bit a:HMODE
    bpl @L010
    lsr a
@L010:
    php
    adc a:BASL,x
    sta WORK1
    sta WORK2
    lda a:BASH,x
    plp
    bcc @L020
    dec WORK1
    eor #$0C
@L020:
    sta WORK1+$01
    eor #$0C
    sta WORK2+$01
    bit FLAGS
    bmi SHFTLF
SHFTRT:
    ldy TEMP3
    bvc @L020
@L010:
    lda (BASE2),y
    sta (WORK2),y
@L020:
    lda (BASE1),y
    sta (WORK1),y
    dey
    bpl @L010
    lda TEMP4
    bit a:HMODE
    bpl @L050
    lsr a
    tay
    lda BLANK
    bcc @L040
@L030:
    sta (BASE2),y
@L040:
    sta (BASE1),y
    dey
    bpl @L030
    bmi SHIFT2
@L050:
    tay
@L060:
    lda BLANK
    sta (BASE1),y
    lda a:TCOLOR
    sta (BASE2),y
    dey
    bpl @L060
SHIFT2:
    cpx a:VPB
    inx
    bcc SHIFT1
    jmp TBASCAL
SHFTLF:
    ldy #$00
    stx TEMPX
    ldx TEMP3
@L010:
    lda (WORK1),y
    sta (BASE1),y
    dex
    bmi @L020
    lda (WORK2),y
    sta (BASE2),y
    iny
    dex
    bpl @L010
@L020:
    ldx TEMPX
    ldy TEMP4
    jsr CLREOL1
    jmp SHIFT2

;; Copies the viewport's contents to the caller's list for status 18, or from it back to the screen for control 18.
;;
;; The contents follow the list's first three bytes, a line at a time. In 80 columns each line is its even columns, then
;; its odd ones; in 40 columns its characters, then their colors. The cursor is off while it copies.
;; In: A = $00 to save the contents, $80 to restore them, SCLIST = the list
;; Uses: A, X, Y, FLAGS, TEMP1, TEMP2, WORK1, WORK2
SCRNDUMP:
    sta FLAGS
    jsr CURSOR
    lda a:VPHMAX
    sta TEMP2
    inc TEMP2
    bit a:HMODE
    bmi @L010
    asl TEMP2
    asl a
@L010:
    lsr a
    sta TEMP1
    ror FLAGS
    clc
    lda SCLIST
    adc #$03
    sta WORK1
    lda SCLIST+$01
    adc #$00
    cmp #$F0
    ldx $1401+SCLIST
    bcc @L020
    sbc #$80                        ; keep the pointer within its bank
    inx
@L020:
    sta WORK1+$01
    stx $1401+WORK1
    lda TEMP2
    lsr a
    adc WORK1
    sta WORK2
    lda WORK1+$01
    adc #$00
    sta WORK2+$01
    stx $1401+WORK2
    ldx a:VPT
@L100:
    jsr TBASCAL1
    ldy TEMP1
    bit FLAGS
    bvs @L120
    bpl @L115
@L110:
    lda (BASE2),y
    sta (WORK2),y
@L115:
    lda (BASE1),y
    sta (WORK1),y
    dey
    bpl @L110
    bmi @L140
@L120:
    bpl @L135
@L130:
    lda (WORK2),y
    sta (BASE2),y
@L135:
    lda (WORK1),y
    sta (BASE1),y
    dey
    bpl @L130
@L140:
    clc
    lda WORK1
    adc TEMP2
    sta WORK1
    bcc @L150
    inc WORK1+$01
@L150:
    clc
    lda WORK2
    adc TEMP2
    sta WORK2
    bcc @L160
    inc WORK2+$01
@L160:
    cpx a:VPB
    inx
    bcc @L100
    jsr TBASCAL
    jsr CURSOR
    rts

;; Saves BASE1 and BASE2 in <ZPSAVE> for the next request.
;; Uses: A, X
ZPOUT:
    ldx #<(ZPLENGTH-$01)
@L010:
    lda ZPDATA,x
    sta a:ZPSAVE,x
    dex
    bpl @L010
    rts
