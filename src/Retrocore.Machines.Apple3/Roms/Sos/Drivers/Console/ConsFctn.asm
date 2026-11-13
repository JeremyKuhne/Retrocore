; ---------------------------------------------------------------------------------------------------------------------
; Control codes, which PRINT carries out with their parameters in CTLBUFF
; ---------------------------------------------------------------------------------------------------------------------

;; Control codes $00 and $1B: nothing.
CF_NUL:
CF_ESC:
    rts

;; Control code $01: saves the screen state in <SCRSTSAV> and makes the whole screen the viewport, leaving the cursor
;; where it is on the screen.
;; Uses: A, X, Y
;; See: <CF_EOT>
CF_SOH:
    ldy #<SCRSTLEN
@L010:
    lda a:SCRSTTBL-$01,y
    sta a:SCRSTSAV-$01,y
    dey
    bne @L010
    clc
    lda a:TPX
    adc a:VPL
    sta a:TPX
    lda a:TPY
    adc a:VPT
    sta a:TPY
    lda #$00
    sta a:VPL
    sta a:VPT
    lda #$FF
    sta a:VPR                       ; VERIFY brings the right and bottom edges in
    sta a:VPB
    jmp VERIFY

;; Control code $02: moves the viewport's top left corner to the cursor, which stays there.
;; Uses: A, X, Y
CF_STX:
    clc
    lda a:VPL
    adc a:TPX
    sta a:VPL
    lda a:VPT
    adc a:TPY
    sta a:VPT
    lda #$00
    sta a:TPX
    sta a:TPY
    jmp VERIFY

;; Control code $03: moves the viewport's bottom right corner to the cursor.
;; Uses: A, X, Y
CF_ETX:
    clc
    lda a:TPX
    adc a:VPL
    sta a:VPR
    lda a:TPY
    adc a:VPT
    sta a:VPB
    jmp VERIFY

;; Control code $04: brings back the screen state that control code $01 saved.
;; Uses: A, X, Y
;; See: <CF_SOH>
CF_EOT:
    ldy #<SCRSTLEN
@L010:
    lda a:SCRSTSAV-$01,y
    sta a:SCRSTTBL-$01,y
    dey
    bne @L010
    jmp VERIFY

;; Control code $05: shows the cursor.
;; Uses: A
CF_ENQ:
    lda a:SMODE
    ora #<BITON4
    sta a:SMODE
    lda #<TRUE
    sta a:SMCURSOR
    rts

;; Control code $06: hides the cursor.
;; Uses: A
CF_ACK:
    lda a:SMODE
    and #<BITOFF4
    sta a:SMODE
    lda #<FALSE
    sta a:SMCURSOR
    rts

;; Control code $07: sounds the bell.
CF_BEL:
    bit BELL
    rts

;; Control code $08: moves the cursor left. At the viewport's left edge it wraps to the right edge of the line above
;; when wrapping is on, and otherwise stays.
;; Uses: A, X, Y
CF_BS:
    dec a:TPX
    bpl @L020
    bit a:SMAUTOCR
    bpl @L010
    lda a:VPHMAX
    sta a:TPX
    jmp CF_VT
@L010:
    inc a:TPX
@L020:
    rts

;; Control code $09: moves the cursor right. At the viewport's right edge it wraps to the start of the next line when
;; wrapping is on, and otherwise stays.
;; Uses: A, X, Y
CF_HT:
    lda a:TPX
    cmp a:VPHMAX
    bcs @L010
    inc a:TPX
    rts
@L010:
    bit a:SMAUTOCR
    bpl CF_EXIT
    lda #$00
    sta a:TPX
    jmp CF_LF

;; Control code $0A: moves the cursor down a line. On the bottom line it scrolls the viewport up when scrolling is on,
;; and otherwise stays.
;; Uses: A, X, Y
CF_LF:
    lda a:TPY
    cmp a:VPVMAX
    bcs @L010
    inc a:TPY
    jmp TBASCAL
@L010:
    bit a:SMSCROLL
    bpl CF_EXIT
    lda #$00
    jmp SCROLL

;; Control code $0B: moves the cursor up a line. On the top line it scrolls the viewport down when scrolling is on, and
;; otherwise stays.
;; Uses: A, X, Y
CF_VT:
    lda a:TPY
    beq @L010
    dec a:TPY
    jmp TBASCAL
@L010:
    bit a:SMSCROLL
    bpl CF_EXIT
    lda #$80
    jmp SCROLL

;; Control code $0C: moves the cursor to the viewport's top left corner.
;; Uses: A, X
CF_FF:
    lda #$00
    sta a:TPX
    sta a:TPY
    jmp TBASCAL

;; Control code $0D: moves the cursor to the start of its line, and down a line when automatic line feed is on.
;; Uses: A, X, Y
CF_CR:
    lda #$00
    sta a:TPX
    bit a:SMAUTOLF
    bpl CF_EXIT
    jmp CF_LF

;; Control code $0E: turns the video off.
;; Uses: A, X, Y
CF_SO:
    lda #<FALSE
    sta SCRNMODE
    jmp VERIFY

;; Control code $0F: turns the video on, showing the text screen.
;; Uses: A, X, Y
CF_SI:
    lda #<TRUE
    sta SCRNMODE
    jmp VERIFY

;; Control code $10: sets the hardware mode from its parameter: bit 1 for 80 columns, bit 0 for color in 40 columns.
;; In: CTLBUFF+1 = the mode
;; Uses: A, X, Y
CF_DLE:
    lda a:CTLBUFF+$01
    sta a:HMODE
    jmp VERIFY

;; Control code $11: normal video for the characters that follow.
;; Uses: A
CF_DC1:
    lda a:SMODE
    and #<BITOFF5
    sta a:SMODE
    lda #<FALSE
    sta a:SMINV
CF_EXIT:
    rts

;; Control code $12: inverse video for the characters that follow.
;; Uses: A
CF_DC2:
    lda a:SMODE
    ora #<BITON5
    sta a:SMODE
    lda #<TRUE
    sta a:SMINV
    rts

;; Control code $13: sets the text color for 40 columns from its parameter, 0-15.
;; In: CTLBUFF+1 = the color
;; Uses: A, X, Y
CF_DC3:
    lda a:CTLBUFF+$01
    sta a:TCF
    jmp VERIFY

;; Control code $14: sets the background color for 40 columns from its parameter, 0-15.
;; In: CTLBUFF+1 = the color
;; Uses: A, X, Y
CF_DC4:
    lda a:CTLBUFF+$01
    sta a:TCB
    jmp VERIFY

;; Control code $15: sets the software mode's scrolling, wrapping, automatic line feed and automatic advance from bits
;; 3-0 of its parameter, keeping the cursor and inverse video as they are.
;; In: CTLBUFF+1 = the mode
;; Uses: A, X, Y
CF_NAK:
    lda a:CTLBUFF+$01
    and #$0F
    sta a:CTLBUFF+$01
    lda a:SMODE
    and #$F0
    ora a:CTLBUFF+$01
    sta a:SMODE
    jmp VERIFY

;; Control code $16: waits for the start of the next vertical blanking, showing the cursor while it waits. It does not
;; wait when the vertical-blanking resource is in use.
;; Uses: A, X, Y
CF_SYN:
    lda #<SYNCSSIZ
    ldx a:SYNCSADR
    ldy a:SYNCSADR+$01
    jsr ALLOCSIR
    bcs CF_EXIT
    jsr CURSOR
    php
    sei
    lda E_PCR
    and #$1F
    ora #$60                        ; CB2: the rising edge of vertical blanking
    sta E_PCR
    lda #$08
    sta E_IER                       ; masked, so it is only polled
    sta E_IFR
    plp
@L010:
    bit E_IFR
    beq @L010
    jsr CURSOR
    lda #<SYNCSSIZ
    ldx a:SYNCSADR
    ldy a:SYNCSADR+$01
    jmp DEALCSIR

;; Control code $17: shifts the viewport's text sideways by its parameter, signed: negative to the left, positive to the
;; right.
;; In: CTLBUFF+1 = the shift
;; Uses: A, X, Y
CF_ETB:
    lda a:CTLBUFF+$01
    jmp SHIFT

;; Control code $18: moves the cursor to the column in its parameter, or to the viewport's last column if it is beyond.
;; In: CTLBUFF+1 = the column
;; Uses: A
CF_CAN:
    lda a:CTLBUFF+$01
    cmp a:VPHMAX
    bcc @L010
    lda a:VPHMAX
@L010:
    sta a:TPX
    rts

;; Control code $19: moves the cursor to the line in its parameter, or to the viewport's last line if it is beyond.
;; In: CTLBUFF+1 = the line
;; Uses: A, X
CF_EM:
    lda a:CTLBUFF+$01
    cmp a:VPVMAX
    bcc @L010
    lda a:VPVMAX
@L010:
    sta a:TPY
    jmp TBASCAL

;; Control code $1A: moves the cursor to the column and line in its two parameters.
;; In: CTLBUFF+1 = the column, CTLBUFF+2 = the line
;; Uses: A, X
CF_SUB:
    jsr CF_CAN
    lda a:CTLBUFF+$02
    sta a:CTLBUFF+$01
    jmp CF_EM

;; Control code $1C: clears the viewport and moves the cursor to its top left corner.
;; Uses: A, X, Y
CF_FS:
    jsr CF_FF
    jmp CLREOS

;; Control code $1D: clears from the cursor to the end of the viewport.
;; Uses: A, X, Y
CF_GS:
    jmp CLREOS

;; Control code $1E: clears the cursor's line and moves the cursor to its start.
;; Uses: A, Y
CF_RS:
    lda #$00
    sta a:TPX
    jmp CLREOL

;; Control code $1F: clears from the cursor to the end of its line.
;; Uses: A, Y
CF_US:
    jmp CLREOL
