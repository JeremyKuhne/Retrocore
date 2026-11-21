;; Plots one lo-res block in the current color.
;; In: A = row (0-47), Y = column (0-39), COLOR = color in both nibbles
;; Uses: A, GBASL/GBASH, MASK
;; Keeps: X, Y
PLOT:
    lsr a                           ; $F800
    php                             ; $F801
    jsr GBASCALC                    ; $F802
    plp                             ; $F805
    lda #$0F                        ; $F806 an even row is the low nibble of the text byte, an odd row the high nibble
    bcc RTMASK                      ; $F808
    adc #$E0                        ; $F80A

RTMASK:
    sta MASK                        ; $F80C

PLOT1:
    lda (GBASL),y                   ; $F80E
    eor COLOR                       ; $F810
    and MASK                        ; $F812
    eor (GBASL),y                   ; $F814
    sta (GBASL),y                   ; $F816
    rts                             ; $F818

;; Draws a horizontal lo-res line in the current color.
;; In: A = row, Y = leftmost column, H2 = rightmost column
;; Out: Y = H2.
;; Uses: A
HLINE:
    jsr PLOT                        ; $F819

HLINE1:
    cpy H2                          ; $F81C
    bcs RTS1                        ; $F81E
    iny                             ; $F820
    jsr PLOT1                       ; $F821
    bcc HLINE1                      ; $F824

VLINEZ:
    adc #$01                        ; $F826

;; Draws a vertical lo-res line in the current color.
;; In: A = top row, Y = column, V2 = bottom row
;; Uses: A
VLINE:
    pha                             ; $F828
    jsr PLOT                        ; $F829
    pla                             ; $F82C
    cmp V2                          ; $F82D
    bcc VLINEZ                      ; $F82F

RTS1:
    rts                             ; $F831

;; Clears the whole lo-res screen (48 rows) to black.
CLRSCR:
    ldy #$2F                        ; $F832
    bne CLRSC2                      ; $F834

;; Clears the top 40 lo-res rows to black, leaving the mixed-mode text lines.
CLRTOP:
    ldy #$27                        ; $F836

CLRSC2:
    sty V2                          ; $F838
    ldy #$27                        ; $F83A

CLRSC3:
    lda #$00                        ; $F83C
    sta COLOR                       ; $F83E
    jsr VLINE                       ; $F840
    dey                             ; $F843
    bpl CLRSC3                      ; $F844
    rts                             ; $F846

;; Computes the base address of the text line that holds a lo-res row.
;; In: A = row (0-47)
;; Out: GBASL/GBASH = base address of line A/2
;; Keeps: X, Y
GBASCALC:
    pha                             ; $F847
    lsr a                           ; $F848
    and #$03                        ; $F849
    ora #$04                        ; $F84B
    sta GBASH                       ; $F84D
    pla                             ; $F84F
    and #$18                        ; $F850
    bcc GBCALC                      ; $F852
    adc #$7F                        ; $F854

GBCALC:
    sta GBASL                       ; $F856
    asl a                           ; $F858
    asl a                           ; $F859
    ora GBASL                       ; $F85A
    sta GBASL                       ; $F85C
    rts                             ; $F85E

;; Advances COLOR to the next color (adds 3 to each nibble).
NXTCOL:
    lda COLOR                       ; $F85F
    clc                             ; $F861
    adc #$03                        ; $F862

;; Sets the lo-res color.
;; In: A = color (0-15)
;; Out: COLOR = the color in both nibbles
SETCOL:
    and #$0F                        ; $F864
    sta COLOR                       ; $F866
    asl a                           ; $F868
    asl a                           ; $F869
    asl a                           ; $F86A
    asl a                           ; $F86B
    ora COLOR                       ; $F86C
    sta COLOR                       ; $F86E
    rts                             ; $F870

;; Reads the color of one lo-res block.
;; In: A = row (0-47), Y = column (0-39)
;; Out: A = color (0-15)
SCRN:
    lsr a                           ; $F871
    php                             ; $F872
    jsr GBASCALC                    ; $F873
    lda (GBASL),y                   ; $F876
    plp                             ; $F878

SCRN2:
    bcc RTMSKZ                      ; $F879
    lsr a                           ; $F87B
    lsr a                           ; $F87C
    lsr a                           ; $F87D
    lsr a                           ; $F87E

RTMSKZ:
    and #$0F                        ; $F87F
    rts                             ; $F881
