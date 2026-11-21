X_CRPAS:
    lda #$00                        ; $CBFD
    sta OURCH                       ; $CBFF
    lda MODE80                      ; $CC02
    and #$20                        ; $CC05
    bne X_CRRET                     ; $CC07
    jsr X_LF                        ; $CC09

X_CRRET:
    rts                             ; $CC0C

;; Puts the 80-column cursor at WNDTOP, column 0, and computes the base address.
X_EM:
    lda WNDTOP                      ; $CC0D
    sta OURCV                       ; $CC0F
    lda #$00                        ; $CC12
    sta OURCH                       ; $CC14
    jmp C8_BASCALC                  ; $CC17

;; Clears the whole window line at BASL/BASH, honoring inverse.
;; Uses: A, Y
X_SUB:
    ldy WNDWDTH                     ; $CC1A
    dey                             ; $CC1C

X_SUB80:
    lda #' '                        ; $CC1D

X_SUBLP:
    jsr STORCHAR                    ; $CC1F
    dey                             ; $CC22
    bpl X_SUBLP                     ; $CC23
    rts                             ; $CC25

;; Moves the cursor right; at the window's right edge does X_CR.
X_FS:
    inc OURCH                       ; $CC26
    lda OURCH                       ; $CC29
    cmp WNDWDTH                     ; $CC2C
    bcc X_FSRET                     ; $CC2E
    jsr X_CR                        ; $CC30

X_FSRET:
    rts                             ; $CC33

;; Moves the cursor up a line, but not above WNDTOP.
X_US:
    dec OURCV                       ; $CC34
    bmi X_US1                       ; $CC37
    lda OURCV                       ; $CC39
    cmp WNDTOP                      ; $CC3C
    bcs X_US2                       ; $CC3E

X_US1:
    inc OURCV                       ; $CC40
    beq X_USRET                     ; $CC43

X_US2:
    jsr C8_BASCALC                  ; $CC45

X_USRET:
    rts                             ; $CC48

;; Control-N: normal video (clears mode bit 2, INVFLG = $FF).
X_SO:
    lda MODE80                      ; $CC49
    and #$FB                        ; $CC4C
    ldy #$FF                        ; $CC4E
    bne STUFFINV                    ; $CC50

;; Control-O: inverse video (sets mode bit 2, INVFLG = $7F).
X_SI:
    lda MODE80                      ; $CC52
    ora #$04                        ; $CC55
    ldy #$7F                        ; $CC57

;; Stores the mode byte and INVFLG.
STUFFINV:
    sta MODE80                      ; $CC59
    sty INVFLG                      ; $CC5C
    rts                             ; $CC5E

;; The control characters' handlers, Control-G ($07) to Control-_ ($1F) in order; 0 means not handled.
;; CTLADL ($CC5F) holds the low bytes and CTLADH ($CC78) the high bytes of each address minus one, read
;; as CTLADL-7+Y and CTLADH-7+Y: CTLCHAR checks the high byte and CTLXFER returns to the handler.
.set CTLCHARS, 0

.macro CONTROL handler
    .ident(.sprintf("CTLAD_%d", CTLCHARS)) = handler - 1
    .set CTLCHARS, CTLCHARS + 1
.endmacro

.macro NOCONTROL
    .ident(.sprintf("CTLAD_%d", CTLCHARS)) = 0
    .set CTLCHARS, CTLCHARS + 1
.endmacro

    CONTROL X_BELL                  ; Control-G: bell
    CONTROL X_BS                    ; Control-H: left
    NOCONTROL                       ; Control-I
    CONTROL X_LF                    ; Control-J: line feed
    CONTROL X_VT                    ; Control-K: clear to the end of the window
    CONTROL X_FF                    ; Control-L: home and clear
    CONTROL X_CR                    ; Control-M: carriage return
    CONTROL X_SO                    ; Control-N: normal video
    CONTROL X_SI                    ; Control-O: inverse video
    NOCONTROL                       ; Control-P
    CONTROL X_DC1                   ; Control-Q: 40 columns
    CONTROL X_DC2                   ; Control-R: 80 columns
    NOCONTROL                       ; Control-S
    NOCONTROL                       ; Control-T
    CONTROL X_NAK                   ; Control-U: quit the 80-column firmware
    CONTROL SCROLLDN                ; Control-V: scroll down
    CONTROL SCROLLUP                ; Control-W: scroll up
    NOCONTROL                       ; Control-X
    CONTROL X_EM                    ; Control-Y: home
    CONTROL X_SUB                   ; Control-Z: clear the line
    NOCONTROL                       ; Control-[
    CONTROL X_FS                    ; Control-\: right
    CONTROL X_GS                    ; Control-]: clear to the end of the line
    NOCONTROL                       ; Control-^
    CONTROL X_US                    ; Control-_: up
.assert CTLCHARS = $1F - $07 + 1, "CTLADL and CTLADH cover Control-G to Control-_."

CTLADL:
.repeat CTLCHARS, index
    .byte <.ident(.sprintf("CTLAD_%d", index))
.endrepeat

CTLADH:
.repeat CTLCHARS, index
    .byte >.ident(.sprintf("CTLAD_%d", index))
.endrepeat

;; Line feed: moves the cursor down a line; at the bottom of the window scrolls up instead.
X_LF:
    inc OURCV                       ; $CC91
    lda OURCV                       ; $CC94
    cmp WNDBTM                      ; $CC97
    bcs X_LF2                       ; $CC99
    jmp X_LFRET                     ; $CC9B

;; Line feed at the bottom: leaves the cursor on WNDBTM-1 and scrolls up.
X_LF2:
    ldy WNDBTM                      ; $CC9E
    dey                             ; $CCA0
    sty OURCV                       ; $CCA1

;; Control-W: scrolls the window up one line and clears the bottom line. In 80 columns does main and
;; auxiliary memory separately with WNDWDTH halved.
;; Keeps: X
;; Uses: A, Y, BASL/BASH, BAS2L/BAS2H
SCROLLUP:
    txa                             ; $CCA4
    pha                             ; $CCA5
    ldx #$01                        ; $CCA6
    bne SCROLL1                     ; $CCA8

;; Control-V: scrolls the window down one line and clears the top line.
;; Keeps: X
SCROLLDN:
    txa                             ; $CCAA
    pha                             ; $CCAB
    ldx #$00                        ; $CCAC

SCROLL1:
    bit RD80VID                     ; $CCAE
    bpl SCROLL2                     ; $CCB1
    lda WNDWDTH                     ; $CCB3
    pha                             ; $CCB5
    lsr WNDWDTH                     ; $CCB6

SCROLL2:
    jsr SCRLSUB                     ; $CCB8
    bit RD80VID                     ; $CCBB
    bpl X_SCRLRET                   ; $CCBE
    php                             ; $CCC0
    sei                             ; $CCC1
    lda HISCR                       ; $CCC2
    jsr SCRLSUB                     ; $CCC5
    lda LOWSCR                      ; $CCC8
    plp                             ; $CCCB
    pla                             ; $CCCC
    sta WNDWDTH                     ; $CCCD
    bne X_SCRLRET                   ; $CCCF

;; Moves the window's lines in the currently selected text memory: up (X = 1) or down (X = 0), using
;; WNDTAB for the starting edge and PLUSMINUS1 for the direction.
SCRLSUB:
    ldy WNDTAB,x                    ; $CCD1
    lda a:LOC0,y                    ; $CCD4
    cpx #$01                        ; $CCD7
    bcs MSCRL0                      ; $CCD9
    sbc #$00                        ; $CCDB

MSCRL0:
    pha                             ; $CCDD
    jsr C8_BASCALC_1                ; $CCDE

MSCRL1:
    lda BASL                        ; $CCE1
    sta BAS2L                       ; $CCE3
    lda BASH                        ; $CCE5
    sta BAS2H                       ; $CCE7
    ldy WNDWDTH                     ; $CCE9
    dey                             ; $CCEB
    pla                             ; $CCEC
    clc                             ; $CCED
    adc PLUSMINUS1,x                ; $CCEE
    cmp WNDTOP,x                    ; $CCF1
    beq MSCRLRET                    ; $CCF3
    pha                             ; $CCF5
    jsr C8_BASCALC_1                ; $CCF6

MSCRL2:
    lda (BASL),y                    ; $CCF9
    sta (BAS2L),y                   ; $CCFB
    dey                             ; $CCFD
    bpl MSCRL2                      ; $CCFE
    bmi MSCRL1                      ; $CD00

MSCRLRET:
    cpx #$00                        ; $CD02
    bne MSCRLRTS                    ; $CD04
    jsr C8_BASCALC_1                ; $CD06

ONEMORE:
    lda (BASL),y                    ; $CD09
    sta (BAS2L),y                   ; $CD0B
    dey                             ; $CD0D
    bpl ONEMORE                     ; $CD0E

MSCRLRTS:
    rts                             ; $CD10

;; After a scroll: clears the line left empty (bottom for up, top for down), restores X and recomputes the
;; base address for the cursor row.
X_SCRLRET:
    ldy WNDTOP,x                    ; $CD11
    txa                             ; $CD13
    beq X_SCRLRET2                  ; $CD14
    dey                             ; $CD16

X_SCRLRET2:
    tya                             ; $CD17
    jsr C8_BASCALC_1                ; $CD18
    pla                             ; $CD1B
    tax                             ; $CD1C
    jsr X_SUB                       ; $CD1D

X_LFRET:
    jmp C8_BASCALC                  ; $CD20

;; Control-K: clears from the cursor to the end of the line and every line below it in the window.
X_VT:
    jsr X_GS                        ; $CD23
    lda OURCV                       ; $CD26
    pha                             ; $CD29
    bpl X_VTNEXT                    ; $CD2A

X_VTLOOP:
    jsr C8_BASCALC                  ; $CD2C
    jsr X_SUB                       ; $CD2F

X_VTNEXT:
    inc OURCV                       ; $CD32
    lda OURCV                       ; $CD35
    cmp WNDBTM                      ; $CD38
    bcc X_VTLOOP                    ; $CD3A
    pla                             ; $CD3C
    sta OURCV                       ; $CD3D
    bpl X_LFRET                     ; $CD40

;; Control-L: homes the cursor and clears the window.
X_FF:
    jsr X_EM                        ; $CD42
    jmp X_VT                        ; $CD45

;; Control-]: clears from the 80-column cursor to the end of the line.
X_GS:
    ldy OURCH                       ; $CD48
    jmp X_GS2                       ; $CD4B

;; Stores spaces (honoring inverse) from column Y to the window's right edge.
;; In: Y = column.
;; Out: Y = WNDWDTH
X_GSEOLZ:
    lda #' '                        ; $CD4E
    jsr STORCHAR                    ; $CD50
    iny                             ; $CD53

X_GS2:
    cpy WNDWDTH                     ; $CD54
    bcc X_GSEOLZ                    ; $CD56
    rts                             ; $CD58

;; Control-Q: sets a 40-column window (top 20 if graphics are on) and, if 80 columns was on, converts the
;; screen with SCRN84.
X_DC1:
    lda #$00                        ; $CD59
    sta WNDLFT                      ; $CD5B
    bit RDTEXT                      ; $CD5D
    bmi X_DC1B                      ; $CD60
    lda #$14                        ; $CD62

X_DC1B:
    sta WNDTOP                      ; $CD64
    lda #$18                        ; $CD66
    sta WNDBTM                      ; $CD68
    lda #$28                        ; $CD6A
    sta WNDWDTH                     ; $CD6C
    bit RD80VID                     ; $CD6E
    bpl X_DC1RTS                    ; $CD71
    jsr SCRN84                      ; $CD73

X_DC1RTS:
    rts                             ; $CD76

;; Control-R: if a card answers, sets the 80x24 window (top 20 if graphics are on) and, unless 80STORE is
;; already on, converts the screen with SCRN48.
X_DC2:
    jsr TESTCARD                    ; $CD77
    bne X_NAKRET                    ; $CD7A
    jsr FULL80                      ; $CD7C
    bit RDTEXT                      ; $CD7F
    bmi X_DC2B                      ; $CD82
    lda #$14                        ; $CD84
    sta WNDTOP                      ; $CD86

X_DC2B:
    bit RD80STORE                   ; $CD88
    bmi X_NAKRET                    ; $CD8B
    jmp SCRN48                      ; $CD8D

;; Control-U output: quits the 80-column firmware (QUIT) unless in Pascal mode.
X_NAK:
    lda MODE80                      ; $CD90
    and #$20                        ; $CD93
    bne X_NAKRET                    ; $CD95
    jsr QUIT                        ; $CD97

X_NAKRET:
    rts                             ; $CD9A

;; Sets the window to 80 columns by 24 lines from the top left.
FULL80:
    lda #$00                        ; $CD9B
    sta WNDTOP                      ; $CD9D
    sta WNDLFT                      ; $CD9F
    lda #$50                        ; $CDA1
    sta WNDWDTH                     ; $CDA3
    lda #$18                        ; $CDA5
    sta WNDBTM                      ; $CDA7
    rts                             ; $CDA9

;; Leaves the 80-column firmware: sets a full 40-column window, converts the screen to 40 columns if needed,
;; puts the cursor at line 23, column 0, selects the primary character set, marks the firmware inactive
;; ($04FB = $FF) and restores the Monitor's input and output hooks (SETVID, SETKBD).
QUIT:
    lda #$00                        ; $CDAA
    sta WNDTOP                      ; $CDAC
    sta WNDLFT                      ; $CDAE
    lda #$18                        ; $CDB0
    sta WNDBTM                      ; $CDB2
    lda #$28                        ; $CDB4
    sta WNDWDTH                     ; $CDB6
    bit RD80VID                     ; $CDB8
    bpl QUIT2                       ; $CDBB
    jsr SCRN84                      ; $CDBD

QUIT2:
    lda #$17                        ; $CDC0
    sta OURCV                       ; $CDC2
    jsr C8_BASCALC                  ; $CDC5
    lda #$00                        ; $CDC8
    sta OURCH                       ; $CDCA
    sta CLRALTCHAR                  ; $CDCD
    lda #$FF                        ; $CDD0
    sta MODE80                      ; $CDD2
    jsr SETVID                      ; $CDD5
    jmp SETKBD                      ; $CDD8

;; Converts the screen from 80 to 40 columns, keeping the left 40 columns, from line 23 up to line 0 (line
;; 20 when graphics are on), then turns 80STORE and 80VID off. Keeps the 80-column cursor.
;; Uses: BAS2L (the row counter)
SCRN84:
    lda OURCV                       ; $CDDB
    pha                             ; $CDDE
    lda OURCH                       ; $CDDF
    pha                             ; $CDE2
    lda #$17                        ; $CDE3
    sta BAS2L                       ; $CDE5
    sta SET80STORE                  ; $CDE7

SCR40:
    lda BAS2L                       ; $CDEA
    jsr C8_BASCALC_1                ; $CDEC
    jsr ATEFOR                      ; $CDEF
    dec BAS2L                       ; $CDF2
    bmi SCR40RET                    ; $CDF4
    bit RDTEXT                      ; $CDF6
    bmi SCR40                       ; $CDF9
    lda BAS2L                       ; $CDFB
    cmp #$14                        ; $CDFD
    bcs SCR40                       ; $CDFF
