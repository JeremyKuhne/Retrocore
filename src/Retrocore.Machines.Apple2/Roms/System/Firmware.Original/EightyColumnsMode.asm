SCR40RET:
    sta KBD                         ; $CE01
    sta CLR80VID                    ; $CE04
    jmp SCR80RET_1                  ; $CE07

;; Converts one line at BASL from 80 to 40 columns, working from column 39 down, interrupts off.
ATEFOR:
    php                             ; $CE0A
    sei                             ; $CE0B
    ldy #$28                        ; $CE0C
    sty BAS2H                       ; $CE0E
    bit LOWSCR                      ; $CE10

ATEFOR1:
    jsr GET84                       ; $CE13
    bit HISCR                       ; $CE16
    jsr GET84                       ; $CE19
    ldy BAS2H                       ; $CE1C
    bne ATEFOR1                     ; $CE1E
    plp                             ; $CE20
    rts                             ; $CE21

;; Copies one 80-column character (column BAS2H-1, from the text page selected by the caller) to main
;; memory column BAS2H-1, and decrements BAS2H.
GET84:
    dec BAS2H                       ; $CE22
    lda BAS2H                       ; $CE24
    lsr a                           ; $CE26
    tay                             ; $CE27
    lda (BASL),y                    ; $CE28
    ldy BAS2H                       ; $CE2A
    bit LOWSCR                      ; $CE2C
    sta (BASL),y                    ; $CE2F
    rts                             ; $CE31

;; Converts the screen from 40 to 80 columns, from line 23 up to line 0 (line 20 when graphics are on), then
;; turns 80VID on. The label SCR80RET_1 ($CE58) restores the saved cursor and recomputes the base address.
SCRN48:
    lda OURCV                       ; $CE32
    pha                             ; $CE35
    lda OURCH                       ; $CE36
    pha                             ; $CE39
    lda #$17                        ; $CE3A
    sta BAS2L                       ; $CE3C

SCR80:
    lda BAS2L                       ; $CE3E
    jsr C8_BASCALC_1                ; $CE40
    jsr FORATE                      ; $CE43
    dec BAS2L                       ; $CE46
    bmi SCR80RET                    ; $CE48
    bit RDTEXT                      ; $CE4A
    bmi SCR80                       ; $CE4D
    lda BAS2L                       ; $CE4F
    cmp #$14                        ; $CE51
    bcs SCR80                       ; $CE53

SCR80RET:
    sta SET80VID                    ; $CE55

SCR80RET_1:
    pla                             ; $CE58
    sta OURCH                       ; $CE59
    pla                             ; $CE5C
    sta OURCV                       ; $CE5D
    jmp C8_BASCALC                  ; $CE60

;; Converts one line at BASL from 40 to 80 columns (even columns to auxiliary, odd to main memory), then
;; blanks the right half of the line, interrupts off.
FORATE:
    php                             ; $CE63
    sei                             ; $CE64
    ldy #$00                        ; $CE65
    sty BAS2H                       ; $CE67
    sty SET80STORE                  ; $CE69
    bit LOWSCR                      ; $CE6C

FORATE1:
    lda (BASL),y                    ; $CE6F
    bit HISCR                       ; $CE71
    jsr PUTCOL80                    ; $CE74
    bit LOWSCR                      ; $CE77
    lda (BASL),y                    ; $CE7A
    jsr PUTCOL80                    ; $CE7C
    cpy #$28                        ; $CE7F
    bcc FORATE1                     ; $CE81
    jsr CLRHALF                     ; $CE83
    bit HISCR                       ; $CE86
    jsr CLRHALF                     ; $CE89
    bit LOWSCR                      ; $CE8C
    plp                             ; $CE8F
    rts                             ; $CE90

;; Fills bytes $14-$27 of the line at BASL with spaces (inverse spaces when INVFLG bit 7 is clear).
CLRHALF:
    ldy #$14                        ; $CE91
    lda #' '                        ; $CE93
    bit INVFLG                      ; $CE95
    bmi CLRHALF2                    ; $CE97
    and #$7F                        ; $CE99

CLRHALF2:
    sta (BASL),y                    ; $CE9B
    iny                             ; $CE9D
    cpy #$28                        ; $CE9E
    bne CLRHALF2                    ; $CEA0
    rts                             ; $CEA2

;; Stores A at (BASL),Y/2 and steps the column count in BAS2H.
;; Out: Y = new BAS2H
PUTCOL80:
    pha                             ; $CEA3
    tya                             ; $CEA4
    lsr a                           ; $CEA5
    tay                             ; $CEA6
    pla                             ; $CEA7
    sta (BASL),y                    ; $CEA8
    inc BAS2H                       ; $CEAA
    ldy BAS2H                       ; $CEAC
    rts                             ; $CEAE

;; Sets the 80-column cursor column from A and copies it to CH and $047B. In 80 columns CH is set to 0
;; instead, or to 40 minus the remaining columns when fewer than 8 remain.
;; In: A = column.
;; Out: A = column
SETCH:
    sta OURCH                       ; $CEAF
    sta CH                          ; $CEB2
    sta OLDCH                       ; $CEB4
    bit RD80VID                     ; $CEB7
    bpl SETCHRTS                    ; $CEBA
    lda #$00                        ; $CEBC
    sta CH                          ; $CEBE
    sta OLDCH                       ; $CEC0
    lda WNDWDTH                     ; $CEC3
    sec                             ; $CEC5
    sbc OURCH                       ; $CEC6
    cmp #$08                        ; $CEC9
    bcs SETCHRTS                    ; $CECB
    sta CH                          ; $CECD
    lda #$28                        ; $CECF
    sec                             ; $CED1
    sbc CH                          ; $CED2
    sta CH                          ; $CED4
    sta OLDCH                       ; $CED6

SETCHRTS:
    lda OURCH                       ; $CED9
    rts                             ; $CEDC

;; Inverts bit 7 of the character at the 80-column cursor (shows or hides the cursor).
;; Keeps: A, Y
INVERT:
    pha                             ; $CEDD
    tya                             ; $CEDE
    pha                             ; $CEDF
    ldy OURCH                       ; $CEE0
    jsr PICK                        ; $CEE3
    eor #$80                        ; $CEE6
    bit SEV                         ; $CEE8 BIT SEV sets V: write
    jsr SCREENIT                    ; $CEEB
    pla                             ; $CEEE
    tay                             ; $CEEF
    pla                             ; $CEF0
    rts                             ; $CEF1

;; Stores a character at column Y of the current line, clearing bit 7 when INVFLG selects inverse.
;; Keeps: A
;; In: A = character, Y = column
STORCHAR:
    pha                             ; $CEF2
    bit INVFLG                      ; $CEF3
    bmi STORCHAR_1                  ; $CEF5
    eor #$80                        ; $CEF7

STORCHAR_1:
    bit SEV                         ; $CEF9 BIT SEV sets V: write
    jsr SCREENIT                    ; $CEFC
    pla                             ; $CEFF

;; An RTS ($60), also used as a byte: BIT SEV sets V.
SEV:
    rts                             ; $CF00

;; Reads the character at column Y of the current line.
;; In: Y = column.
;; Out: A = character
;; Keeps: Y
PICK:
    clv                             ; $CF01
    jsr SCREENIT                    ; $CF02
    rts                             ; $CF05

;; Reads (V clear) or writes (V set) the screen byte at column Y. In 80 columns even columns are in
;; auxiliary memory and odd in main, reached by PAGE2 with 80STORE on, with interrupts off.
;; In: Y = column, A = character to write.
;; Out: A = character (read) or kept (write).
;; Keeps: Y
;; Uses: $1F
SCREENIT:
    sty $1F                         ; $CF06
    pha                             ; $CF08
    lda RD80VID                     ; $CF09
    bpl SCRN40                      ; $CF0C
    lda $1F                         ; $CF0E
    lsr a                           ; $CF10
    tay                             ; $CF11
    bvs STOR80                      ; $CF12
    php                             ; $CF14
    sei                             ; $CF15
    lda HISCR                       ; $CF16 with 80STORE on, PAGE2 selects auxiliary text memory
    bcc C8_SCRN2                    ; $CF19
    lda LOWSCR                      ; $CF1B

C8_SCRN2:
    lda (BASL),y                    ; $CF1E
    tay                             ; $CF20
    lda LOWSCR                      ; $CF21
    plp                             ; $CF24
    pla                             ; $CF25
    tya                             ; $CF26
    pha                             ; $CF27
    bvc STPKEXIT                    ; $CF28

STOR80:
    pla                             ; $CF2A
    pha                             ; $CF2B
    php                             ; $CF2C
    sei                             ; $CF2D
    pha                             ; $CF2E
    lda HISCR                       ; $CF2F
    bcc SCRN3                       ; $CF32
    lda LOWSCR                      ; $CF34

SCRN3:
    pla                             ; $CF37
    sta (BASL),y                    ; $CF38
    lda LOWSCR                      ; $CF3A
    plp                             ; $CF3D
    bvs STPKEXIT                    ; $CF3E

SCRN40:
    ldy $1F                         ; $CF40
    bvs STOR40                      ; $CF42
    pla                             ; $CF44
    lda (BASL),y                    ; $CF45
    pha                             ; $CF47
    bvc STPKEXIT                    ; $CF48

STOR40:
    pla                             ; $CF4A
    pha                             ; $CF4B
    sta (BASL),y                    ; $CF4C

STPKEXIT:
    pla                             ; $CF4E
    ldy $1F                         ; $CF4F
    rts                             ; $CF51

;; Saves the character at the cursor in $067B and shows a "+" cursor there in the opposite video.
;; Keeps: A, Y
ESCON:
    pha                             ; $CF52
    tya                             ; $CF53
    pha                             ; $CF54
    ldy OURCH                       ; $CF55
    jsr PICK                        ; $CF58
    sta CHAR                        ; $CF5B
    and #$80                        ; $CF5E
    eor #'+'                        ; $CF60 a "+" in the opposite video
    jmp ESCRET                      ; $CF62

;; Puts the character saved in $067B back at the cursor.
;; Keeps: A, Y
ESCOFF:
    pha                             ; $CF65
    tya                             ; $CF66
    pha                             ; $CF67
    ldy OURCH                       ; $CF68
    lda CHAR                        ; $CF6B

ESCRET:
    bit SEV                         ; $CF6E BIT SEV sets V: write
    jsr SCREENIT                    ; $CF71
    pla                             ; $CF74
    tay                             ; $CF75
    pla                             ; $CF76
    rts                             ; $CF77

;; Copies the ROM's $F800-$FFFF into language card RAM bank 2 (reading ROM, writing RAM), then restores the
;; bank and ROM/RAM read selection. Interrupts off.
;; Uses: CSWL/CSWH (the pointer; CSWH is left at $C3, CSWL restored), X, Y
;; Keeps: A
COPYROM:
    pha                             ; $CF78
    php                             ; $CF79
    sei                             ; $CF7A
    lda RDLCBNK2                    ; $CF7B
    pha                             ; $CF7E
    ldx RDLCRAM                     ; $CF7F
    lda ROMIN                       ; $CF82
    lda ROMIN                       ; $CF85
    ldy #$00                        ; $CF88
    lda #$F8                        ; $CF8A
    sta CSWH                        ; $CF8C
    lda CSWL                        ; $CF8E
    pha                             ; $CF90
    lda #$00                        ; $CF91
    sta CSWL                        ; $CF93

COPYROM2:
    lda (CSWL),y                    ; $CF95
    sta (CSWL),y                    ; $CF97
    iny                             ; $CF99
    bne COPYROM2                    ; $CF9A
    inc CSWH                        ; $CF9C
    bne COPYROM2                    ; $CF9E
    pla                             ; $CFA0
    sta CSWL                        ; $CFA1
    lda #$C3                        ; $CFA3
    sta CSWH                        ; $CFA5
    pla                             ; $CFA7
    bpl LCB1                        ; $CFA8
    txa                             ; $CFAA
    bpl LCB2ROM                     ; $CFAB
    lda LCRAM2                      ; $CFAD
    jmp COPYRET                     ; $CFB0

;; Language card restore: bank 2, ROM read.
LCB2ROM:
    lda ROMIN                       ; $CFB3
    jmp COPYRET                     ; $CFB6

;; Language card restore: bank 1, chosen by whether RAM was being read.
LCB1:
    txa                             ; $CFB9
    bpl LCB1ROM                     ; $CFBA
    lda LCRAM1                      ; $CFBC
    jmp COPYRET                     ; $CFBF

;; Language card restore: bank 1, ROM read.
LCB1ROM:
    lda ROMIN1                      ; $CFC2

COPYRET:
    plp                             ; $CFC5
    pla                             ; $CFC6
    rts                             ; $CFC7

;; Prepares a Pascal call: with mode bit 0 clear sets the full 80x24 window; sets INVFLG from mode bit 2
;; and reloads BASL/BASH from $077B/$07FB.
PSETUP:
    lda MODE80                      ; $CFC8
    and #$01                        ; $CFCB
    bne PSETUP2                     ; $CFCD
    jsr FULL80                      ; $CFCF

PSETUP2:
    lda #$FF                        ; $CFD2
    sta INVFLG                      ; $CFD4
    lda MODE80                      ; $CFD6
    and #$04                        ; $CFD9
    beq PSETUPRET                   ; $CFDB

;; Sets INVFLG to inverse ($7F), then reloads BASL/BASH.
PSETUP2_1:
    lsr INVFLG                      ; $CFDD

PSETUPRET:
    lda OLDBASL                     ; $CFDF
    sta BASL                        ; $CFE2
    lda OLDBASH                     ; $CFE4
    sta BASH                        ; $CFE7
    rts                             ; $CFE9

;; Low bytes minus one of the 40-column functions 0-5; B_OLDFUNC pushes page $C1 and returns to them.
F_TABLE:
    .lobytes F_CLREOP-1, F_HOME-1, F_SCROLL-1, F_CLREOL-1, F_CLEOLZ-1, B_RESET-1 ; $CFEA
.assert (>(F_CLREOP-1) = $C1) && (>(B_RESET-1) = $C1), "The 40-column functions must follow the first byte of page $C1."

;; Line steps for SCRLSUB: -1 (down), +1 (up). Nothing reads the third byte.
PLUSMINUS1:
    .byte $FF, $01, $89             ; $CFF0

;; Low bytes minus one of the 80-column functions 0-5; B_FUNC1 pushes page $C1 and returns to them.
B_TABLE:
    .lobytes B_CLREOP-1, B_HOME-1, B_SCROLL-1, B_CLREOL-1, B_CLEOLZ-1, B_RESET-1 ; $CFF3
.assert (>(B_SCROLL-1) = $C1) && (>(B_HOME-1) = $C1), "The 80-column functions must follow the first byte of page $C1."

;; Page-zero addresses of the starting edge for SCRLSUB: WNDBTM (down), WNDTOP (up). Nothing reads the
;; rest.
WNDTAB:
    .byte WNDBTM, WNDTOP            ; $CFF9
    .byte $E6, $00, $00, $00        ; $CFFB

; The last byte, at CLRROM: reading it ($C336) releases the $C800 ROMs.
    .byte $00                       ; $CFFF
