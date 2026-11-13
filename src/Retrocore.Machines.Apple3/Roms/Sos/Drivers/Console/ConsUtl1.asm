; ---------------------------------------------------------------------------------------------------------------------
; Screen routines
; ---------------------------------------------------------------------------------------------------------------------

;; Makes the screen state consistent and puts it into effect.
;;
;; It keeps the hardware mode, the viewport and the cursor within the screen (80 columns have no color), sets
;; <SMFLAGS>, <VPHMAX>, <VPVMAX> and <TCOLOR> from them, and turns the video on or off as <SCRNMODE> says. Unless
;; graphics are showing, it sets the video switches for the first text page in the mode's columns and color. Last it
;; points BASE1 and BASE2 at the cursor's line.
;; Uses: A, X, Y
VERIFY:
    lda a:HMODE
    and #$03
    asl a
    cmp #$04
    bcc @L010
    lda #$04
@L010:
    ror a                           ; bit 7 set for 80 columns, which clears color
    sta a:HMODE
    ldy a:SMODE
    lda #$00
    ldx #$05
@L020:
    sta a:SMFLAGS,x
    lsr a:SMODE
    ror a:SMFLAGS,x
    dex
    bpl @L020
    sty a:SMODE
    lda #79
    bit a:HMODE
    bmi @L100
    lda #39
@L100:
    cmp a:VPR
    bcs @L110
    sta a:VPR
@L110:
    lda a:VPR
    cmp a:VPL
    bcs @L120
    sta a:VPL
@L120:
    sec
    lda a:VPR
    sbc a:VPL
    sta a:VPHMAX
    cmp a:TPX
    bcs @L200
    sta a:TPX
@L200:
    lda #23
    cmp a:VPB
    bcs @L210
    sta a:VPB
@L210:
    lda a:VPB
    cmp a:VPT
    bcs @L220
    sta a:VPT
@L220:
    sec
    lda a:VPB
    sbc a:VPT
    sta a:VPVMAX
    cmp a:TPY
    bcs @L300
    sta a:TPY
@L300:
    lda a:TCB
    and #$0F
    sta a:TCB
    lda a:TCF
    and #$0F
    sta a:TCF
    asl a
    asl a
    asl a
    asl a
    ora a:TCB
    sta a:TCOLOR
    php
    sei
    lda SCRNMODE
    asl a
    bmi @L500                       ; graphics: leave the switches alone
    lda E_REG
    ora #<BITON5
    bcs @L400
    and #<BITOFF5                   ; the video off
@L400:
    sta E_REG
    lda a:HMODE
    and #$03
    bcc @L410
    ora #<BITON7
@L410:
    sta SCRNMODE
.if RELEASE_130
    ; 1.30 touches the first switch of each pair, then the second if the mode bit is set, so turning on color or
    ; 80 columns passes through black and white or 40 columns for a moment, which makes noise on the screen.
    lsr a
    bit VMODE0
    bcc @L420
    bit VMODE0+$01
@L420:
    lsr a
    bit VMODE1
    bcc @L430
    bit VMODE1+$01
@L430:
.else
    ; 1.31 touches only the switch it wants in each pair, indexed by the mode bit.
    lsr a
    and #$01
    tay
    lda #$00
    rol a
    tax
    lda VMODE0,x
    lda VMODE1,y
.endif
    bit VMODE2
    bit VMODE3
@L500:
    plp
    jsr TBASCAL
    rts

;; Shows the cursor, or takes it off, by inverting the character under it, when the cursor is on.
;; Uses: A, Y
;; Keeps: X
CURSOR:
    bit a:SMCURSOR
    bpl @L020
    lda a:TPX
    bit a:HMODE
    bpl @L010
    lsr a
    bcc @L010
    tay
    lda (BASE2),y
    eor #$80
    sta (BASE2),y
    rts
@L010:
    tay
    lda (BASE1),y
    eor #$80
    sta (BASE1),y
@L020:
    rts

;; Reads the character under the cursor from the screen.
;; Out: A = the screen's byte
;; Uses: Y
;; Keeps: X
SCRNPICK:
    lda a:TPX
    tay
    bit a:HMODE
    bpl @L010
    lsr a
    tay
    bcc @L010
    lda (BASE2),y
    bcs @L020
@L010:
    lda (BASE1),y
@L020:
    rts

;; Points BASE1 and BASE2 at the cursor's line, from the viewport's left edge.
;;
;; In 40 columns BASE1 addresses the characters and BASE2 their colors. In 80 columns BASE1 addresses the viewport's
;; columns 0, 2, 4 and on and BASE2 its columns 1, 3, 5 and on, so that half the column indexes both.
;; Entry: TBASCAL1 = for the screen line in X
;; Out: X = the screen line
;; Uses: A
;; Keeps: Y
TBASCAL:
    clc
    lda a:TPY
    adc a:VPT
    tax
TBASCAL1:
    clc
    lda a:VPL
    bit a:HMODE
    bpl @L010
    lsr a
@L010:
    php
    adc a:BASL,x
    sta BASE1
    sta BASE2
    lda a:BASH,x
    plp
    bcc @L020
    dec BASE1
    eor #$0C
@L020:
    sta BASE1+$01
    eor #$0C
    sta BASE2+$01
    rts

;; Clears from the cursor to the end of its line in the viewport, with spaces in the current video and, in 40 columns,
;; the current colors. BASE1 and BASE2 must address the line.
;; Entry: CLREOL1 = from the column in Y
;; Uses: A, Y, BLANK, TEMPX
;; Keeps: X
CLREOL:
    ldy a:TPX
CLREOL1:
    lda #<($80+ASC_SP)
    eor a:SMINV
    sta BLANK
    bit a:HMODE
    bpl @L200
    tya
    bne @L150
    lda a:VPHMAX
    lsr a
    tay
    lda BLANK
    bcc @L110
@L100:
    sta (BASE2),y
@L110:
    sta (BASE1),y
    dey
    bpl @L100
    rts
@L150:
    stx TEMPX
    clc
    sbc a:VPHMAX
    tax
    tya
    lsr a
    tay
    lda BLANK
    bcs @L170
@L160:
    sta (BASE1),y
    inx
    bpl @L180
@L170:
    sta (BASE2),y
    iny
    inx
    bmi @L160
@L180:
    ldx TEMPX
    rts
@L200:
    lda BLANK
    sta (BASE1),y
    lda a:TCOLOR
    sta (BASE2),y
    cpy a:VPHMAX
    iny
    bcc @L200
    rts
