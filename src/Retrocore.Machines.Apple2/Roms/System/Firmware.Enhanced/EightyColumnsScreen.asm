SCROLLUP80:
    ldy #$01                        ; $CBEB scroll up entry (ctrl-W)

SCROLL80_2:
    txa                             ; $CBED
    pha                             ; $CBEE
    sty OLDBASL                     ; $CBEF
    lda WNDWDTH                     ; $CBF2
    pha                             ; $CBF4
    bit RD80VID                     ; $CBF5
    bpl SCROLL80_5                  ; $CBF8
    sta SET80STORE                  ; $CBFA
    lsr a                           ; $CBFD
    tax                             ; $CBFE
    lda WNDLFT                      ; $CBFF
    lsr a                           ; $CC01
    clv                             ; $CC02
    bcc SCROLL80_3                  ; $CC03
    bit DOCTRL_6                    ; $CC05

SCROLL80_3:
    rol a                           ; $CC08
    eor WNDWDTH                     ; $CC09
    lsr a                           ; $CC0B
    bvs SCROLL80_4                  ; $CC0C
    bcs SCROLL80_4                  ; $CC0E
    dex                             ; $CC10

SCROLL80_4:
    stx WNDWDTH                     ; $CC11
    lda RD80VID                     ; $CC13

SCROLL80_5:
    php                             ; $CC16
    ldx WNDTOP                      ; $CC17
    tya                             ; $CC19
    bne SCROLL80_6                  ; $CC1A
    ldx WNDBTM                      ; $CC1C
    dex                             ; $CC1E

SCROLL80_6:
    txa                             ; $CC1F
    jsr VTAB80_1                    ; $CC20

SCROLL80_7:
    lda BASL                        ; $CC23
    sta BAS2L                       ; $CC25
    lda BASH                        ; $CC27
    sta BAS2H                       ; $CC29
    lda OLDBASL                     ; $CC2B
    beq SCROLL80_14                 ; $CC2E
    inx                             ; $CC30
    cpx WNDBTM                      ; $CC31
    bcs SCROLL80_15                 ; $CC33

SCROLL80_8:
    txa                             ; $CC35
    jsr VTAB80_1                    ; $CC36
    ldy WNDWDTH                     ; $CC39
    plp                             ; $CC3B
    php                             ; $CC3C
    bpl SCROLL80_13                 ; $CC3D
    lda HISCR                       ; $CC3F
    tya                             ; $CC42
    beq SCROLL80_10                 ; $CC43

SCROLL80_9:
    lda (BASL),y                    ; $CC45
    sta (BAS2L),y                   ; $CC47
    dey                             ; $CC49
    bne SCROLL80_9                  ; $CC4A

SCROLL80_10:
    bvs SCROLL80_11                 ; $CC4C
    lda (BASL),y                    ; $CC4E
    sta (BAS2L),y                   ; $CC50

SCROLL80_11:
    lda LOWSCR                      ; $CC52
    ldy WNDWDTH                     ; $CC55
    bcs SCROLL80_13                 ; $CC57

SCROLL80_12:
    lda (BASL),y                    ; $CC59
    sta (BAS2L),y                   ; $CC5B

SCROLL80_13:
    dey                             ; $CC5D
    bpl SCROLL80_12                 ; $CC5E
    bmi SCROLL80_7                  ; $CC60

SCROLL80_14:
    dex                             ; $CC62
    cpx WNDTOP                      ; $CC63
    bpl SCROLL80_8                  ; $CC65

SCROLL80_15:
    plp                             ; $CC67
    pla                             ; $CC68
    sta WNDWDTH                     ; $CC69
    jsr CLRLINE80                   ; $CC6B
    jsr VTAB80                      ; $CC6E
    pla                             ; $CC71
    tax                             ; $CC72
    rts                             ; $CC73

;; Ctrl-K: clears from $057B to the end of the line, then every line below to WNDBTM; restores CV.
CLREOP80:
    jsr CLREOL80                    ; $CC74
    lda CV                          ; $CC77
    pha                             ; $CC79
    bpl CLREOP80_2                  ; $CC7A

CLREOP80_1:
    jsr VTAB80_1                    ; $CC7C
    jsr CLRLINE80                   ; $CC7F

CLREOP80_2:
    inc CV                          ; $CC82
    lda CV                          ; $CC84
    cmp WNDBTM                      ; $CC86
    bcc CLREOP80_1                  ; $CC88
    pla                             ; $CC8A
    sta CV                          ; $CC8B
    jmp VTAB80                      ; $CC8D

;; Ctrl-L: HOMECURSOR, then CLREOP80.
CLRSCRN80:
    jsr HOMECURSOR                  ; $CC90
    jmp CLREOP80                    ; $CC93

;; Ctrl-Z: clears the cursor line from column 0. CLREOL80 (ctrl-]) clears from $057B,
;; CLRLINE80_2 from Y.
;; The blank is $A0, or $20 when INVFLG bit 7 is clear; with 80VID it goes through FILL80.
;; In: Y = first column (CLRLINE80_2)
CLRLINE80:
    ldy #$00                        ; $CC96
    beq CLRLINE80_2                 ; $CC98

CLREOL80:
    ldy OURCH                       ; $CC9A

CLRLINE80_2:
    lda INVFLG                      ; $CC9D
    and #$80                        ; $CC9F
    ora #$20                        ; $CCA1
    bit RD80VID                     ; $CCA3
    bmi FILL80                      ; $CCA6

CLRLINE80_3:
    sta (BASL),y                    ; $CCA8
    iny                             ; $CCAA
    cpy WNDWDTH                     ; $CCAB
    bcc CLRLINE80_3                 ; $CCAD
    rts                             ; $CCAF

;; Fills 80-column columns 40-79 of the line at BASL with a blank (from INVFLG) through FILL80; used by
;; SCR40TO80.
;; Out:   carry = set
;; Keeps: X (kept in BAS2L)
CLRRIGHT:
    stx BAS2L                       ; $CCB0
    ldx #$D8                        ; $CCB2
    ldy #$14                        ; $CCB4
    lda INVFLG                      ; $CCB6
    and #$A0                        ; $CCB8
    jmp FILL80_2                    ; $CCBA

;; Stores A in 80-column columns Y to WNDWDTH-1 of (BASL), alternating aux (HISCR) and main bytes.
;; In: A = character, Y = first column
;; Out:   carry = set
;; Keeps: X
;; Uses: BAS2L
FILL80:
    stx BAS2L                       ; $CCBD
    pha                             ; $CCBF
    tya                             ; $CCC0
    pha                             ; $CCC1
    sec                             ; $CCC2
    sbc WNDWDTH                     ; $CCC3
    tax                             ; $CCC5
    tya                             ; $CCC6
    lsr a                           ; $CCC7
    tay                             ; $CCC8
    pla                             ; $CCC9
    eor WNDLFT                      ; $CCCA
    ror a                           ; $CCCC
    bcs FILL80_1                    ; $CCCD
    bpl FILL80_1                    ; $CCCF
    iny                             ; $CCD1

FILL80_1:
    pla                             ; $CCD2
    bcs FILL80_3                    ; $CCD3

FILL80_2:
    bit HISCR                       ; $CCD5
    sta (BASL),y                    ; $CCD8
    bit LOWSCR                      ; $CCDA
    inx                             ; $CCDD
    beq FILL80_4                    ; $CCDE

FILL80_3:
    sta (BASL),y                    ; $CCE0
    iny                             ; $CCE2
    inx                             ; $CCE3
    bne FILL80_2                    ; $CCE4

FILL80_4:
    ldx BAS2L                       ; $CCE6
    sec                             ; $CCE8
    rts                             ; $CCE9

;; Ctrl-Q (not in Pascal mode): converts the screen to 40 columns if 80VID is on. SET80COL is ctrl-R:
;; with auxiliary text memory and 80VID off, converts to 80 columns. Both then add WNDLFT into $057B
;; (clamped to 39 for 40 columns), set CH, a full window and WNDTOP (0, or 20 with graphics shown).
;; $CCEF (no Pascal check, used by OFF80) and $CD2E (full 40-column window, then WNDTOP) are entered by others.
SET40COL:
    lda MODE80                      ; $CCEA
    bmi SET40COL_7                  ; $CCED

SET40COL_1:
    jsr SET40COL_5                  ; $CCEF
    bit RD80VID                     ; $CCF2
    bpl SET40COL_2                  ; $CCF5
    jsr SCR80TO40                   ; $CCF7
    bcc SET40COL_2                  ; $CCFA

SET80COL:
    jsr AUXPRESENT                  ; $CCFC
    bne SET40COL_7                  ; $CCFF
    bit RD80VID                     ; $CD01
    bmi SET40COL_2                  ; $CD04
    jsr SCR40TO80                   ; $CD06

SET40COL_2:
    lda OURCH                       ; $CD09
    clc                             ; $CD0C
    adc WNDLFT                      ; $CD0D
    bit RD80VID                     ; $CD0F
    bmi SET40COL_3                  ; $CD12
    cmp #$28                        ; $CD14
    bcc SET40COL_3                  ; $CD16
    lda #$27                        ; $CD18

SET40COL_3:
    sta OURCH                       ; $CD1A
    sta CH                          ; $CD1D
    lda CV                          ; $CD1F
    jsr ROWBASE                     ; $CD21
    bit RD80VID                     ; $CD24
    bpl SET40COL_4                  ; $CD27
    jsr FULLWND_1                   ; $CD29
    beq SET40COL_5                  ; $CD2C

SET40COL_4:
    jsr FULLWND                     ; $CD2E full 40-column window entry

SET40COL_5:
    lda #$00                        ; $CD31
    bit RDTEXT                      ; $CD33
    bmi SET40COL_6                  ; $CD36
    lda #$14                        ; $CD38

SET40COL_6:
    sta WNDTOP                      ; $CD3A

SET40COL_7:
    rts                             ; $CD3C

;; Ctrl-X: sets $04FB bit 0 (inverse $40-$5F shown as inverse capitals instead of MouseText).
;; MTEXTON is ESC (ctrl-[): clears bit 0.
MTEXTOFF:
    lda MODE80                      ; $CD3D
    ora #$01                        ; $CD40
    bne MTEXTOFF_1                  ; $CD42

MTEXTON:
    lda MODE80                      ; $CD44

    and #$FE                        ; $CD47

MTEXTOFF_1:
    sta MODE80                      ; $CD49
    rts                             ; $CD4C

;; Ctrl-U (not in Pascal mode): full 40-column window, OFF80, then CSW = COUT1 and KSW = KEYIN.
;; $CD5B sets only KSW.
QUIT80:
    lda MODE80                      ; $CD4D
    bmi CSWTOCOUT1_1                ; $CD50
    jsr SET40COL_4                  ; $CD52
    jsr OFF80                       ; $CD55
    jsr CSWTOCOUT1                  ; $CD58

QUIT80_1:
    lda #>KEYIN                     ; $CD5B
    sta KSWH                        ; $CD5D
    lda #<KEYIN                     ; $CD5F
    sta KSWL                        ; $CD61
    rts                             ; $CD63

;; CSW = COUT1.
CSWTOCOUT1:
    lda #>COUT1                     ; $CD64
    sta CSWH                        ; $CD66
    lda #<COUT1                     ; $CD68
    sta CSWL                        ; $CD6A

CSWTOCOUT1_1:
    rts                             ; $CD6C

;; Full window: WNDWDTH 40 ($CD71: 80), WNDBTM 24, WNDTOP and WNDLFT 0.
FULLWND:
    lda #$28                        ; $CD6D
    bne FULLWND_2                   ; $CD6F

FULLWND_1:
    lda #$50                        ; $CD71 80-column width

FULLWND_2:
    sta WNDWDTH                     ; $CD73
    lda #$18                        ; $CD75
    sta WNDBTM                      ; $CD77
    lda #$00                        ; $CD79
    sta WNDTOP                      ; $CD7B
    sta WNDLFT                      ; $CD7D
    rts                             ; $CD7F

;; If 80VID is on converts the screen to 40 columns; then CLRALTCHAR and $04FB = $FF (inactive).
OFF80:
    bit RD80VID                     ; $CD80
    bpl OFF80_1                     ; $CD83
    jsr SET40COL_1                  ; $CD85

OFF80_1:
    sta CLRALTCHAR                  ; $CD88
    lda #$FF                        ; $CD8B
    sta MODE80                      ; $CD8D
    rts                             ; $CD90

;; Copies columns 0-39 of each 80-column row from 23 up to WNDTOP into the 40-column screen, then turns
;; 80STORE and 80VID off and recomputes BASL.
;; Keeps: X
;; Uses: BASL/BASH, BAS2L
SCR80TO40:
    txa                             ; $CD91
    pha                             ; $CD92
    ldx #$17                        ; $CD93
    sta SET80STORE                  ; $CD95

SCR80TO40_1:
    txa                             ; $CD98
    jsr ROWBASE                     ; $CD99
    ldy #$27                        ; $CD9C

SCR80TO40_2:
    sty BAS2L                       ; $CD9E
    tya                             ; $CDA0
    lsr a                           ; $CDA1
    bcs SCR80TO40_3                 ; $CDA2
    bit HISCR                       ; $CDA4

SCR80TO40_3:
    tay                             ; $CDA7
    lda (BASL),y                    ; $CDA8
    bit LOWSCR                      ; $CDAA
    ldy BAS2L                       ; $CDAD
    sta (BASL),y                    ; $CDAF
    dey                             ; $CDB1
    bpl SCR80TO40_2                 ; $CDB2
    dex                             ; $CDB4
    bmi SCR80TO40_4                 ; $CDB5
    cpx WNDTOP                      ; $CDB7
    bcs SCR80TO40_1                 ; $CDB9

SCR80TO40_4:
    sta KBD                         ; $CDBB write to $C000 clears 80STORE
    sta CLR80VID                    ; $CDBE
    jmp SCR40TO80_5                 ; $CDC1

;; Spreads each 40-column row (23 up to WNDTOP) into 80-column columns 0-39, clears columns 40-79
;; (CLRRIGHT), then sets 80VID and recomputes BASL.
;; Keeps: X
SCR40TO80:
    txa                             ; $CDC4
    pha                             ; $CDC5
    ldx #$17                        ; $CDC6

SCR40TO80_1:
    txa                             ; $CDC8
    jsr ROWBASE                     ; $CDC9
    ldy #$00                        ; $CDCC
    sta SET80STORE                  ; $CDCE

SCR40TO80_2:
    lda (BASL),y                    ; $CDD1
    sty BAS2L                       ; $CDD3
    pha                             ; $CDD5
    tya                             ; $CDD6
    lsr a                           ; $CDD7
    bcs SCR40TO80_3                 ; $CDD8
    sta HISCR                       ; $CDDA

SCR40TO80_3:
    tay                             ; $CDDD
    pla                             ; $CDDE
    sta (BASL),y                    ; $CDDF
    sta LOWSCR                      ; $CDE1
    ldy BAS2L                       ; $CDE4
    iny                             ; $CDE6
    cpy #$28                        ; $CDE7
    bcc SCR40TO80_2                 ; $CDE9
    jsr CLRRIGHT                    ; $CDEB
    dex                             ; $CDEE
    bmi SCR40TO80_4                 ; $CDEF
    cpx WNDTOP                      ; $CDF1
    bcs SCR40TO80_1                 ; $CDF3

SCR40TO80_4:
    sta SET80VID                    ; $CDF5

SCR40TO80_5:
    jsr VTAB80                      ; $CDF8
    pla                             ; $CDFB
    tax                             ; $CDFC
    rts                             ; $CDFD
