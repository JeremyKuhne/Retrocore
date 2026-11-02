;; PROGRAMMER'S AID #1: HIGH-RESOLUTION GRAPHICS ($D000-$D3FF)
;;
;; Steve Wozniak's hi-res graphics routines (1977), which Integer BASIC programs CALL: INIT clears a page and shows
;; it with four lines of text below, and then PLOT, LINE, DRAW (a shape from a shape table, scaled and rotated) and
;; FIND (where the last point plotted is) draw on it. The screen is 280 dots across (X0, 0 to 279) by 192 down (Y0,
;; 0 to 191).
;;
;; The routines BASIC calls, from $D2F9 on (POSN, PLOT, LINE, DRAW and the others), take their parameters from
;; BASIC's first variables, in the order a program must define them: X0, Y0, COLR, SHAPE, ROT and SCALE. They read
;; each variable's value at a fixed offset from LOMEM, so a program starts with a line such as
;; `0 X0 = Y0 = COLR = SHAPE = ROT = SCALE`. The routines under them take theirs in the 6502's registers, for
;; machine-language programs: <HiResGraphics::HPOSN>, <HiResGraphics::HPLOT>, <HiResGraphics::HLIN>,
;; <HiResGraphics::DRAW> and <HiResGraphics::XDRAW>.
;;
;; Colors are a byte of dots: 0 black, 42 green, 85 violet, 127 white, 128 black with the high bit, 170 orange, 213
;; blue and 255 white. <HiResGraphics::HPAG> picks the page drawn on: $20 for $2000-$3FFF, the default, or $40 for
;; $4000-$5FFF.
;;
;; Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm, which includes it first.

.scope HiResGraphics

;; The shape table address the drawing routines walk (2 bytes): the shape being drawn.
SHAPEL = $1A

;; The high byte of <SHAPEL>.
SHAPEH = $1B

;; The color byte being plotted: <HCOLOR>, shifted each byte so the color's dots fall on the right columns.
HCOLOR1 = $1C

;; The count of dots <HLIN> has left to draw, with <DXL> as its low byte.
COUNTH = $1D

;; The address of the screen line being drawn on (2 bytes), which <HPOSN> sets.
HBASL = $26

;; The high byte of <HBASL>.
HBASH = $27

;; The bit of the screen byte the next dot is in.
HMASK = $30

;; Inherit: <Monitor:A1L>
A1L = $3C

;; Inherit: <Monitor:A1H>
A1H = $3D

;; Inherit: <Monitor:A2L>
A2L = $3E

;; Inherit: <Monitor:A2H>
A2H = $3F

;; Inherit: <IntegerBasic:LOMEM>
LOMEML = $4A

;; The high byte of <LOMEML>.
LOMEMH = $4B

;; The line's horizontal distance (2 bytes) for <HLIN>, and the X step for <DRAW>.
DXL = $50

;; The high byte of <DXL>.
DXH = $51

;; The bits of the shape byte <DRAW> has left to draw, three at a time (the same byte as <DXH>).
SHAPEX = $51

;; The line's vertical distance for <HLIN>, and the Y step for <DRAW>.
DY = $52

;; The direction: the quadrant of a shape's rotation, or which way a line goes.
QDRNT = $53

;; The error term (2 bytes) <HLIN> steps the line by.
EL = $54

;; The high byte of <EL>.
EH = $55

;; Inherit: <IntegerBasic:PP>
PPL = $CA

;; The high byte of <PPL>.
PPH = $CB

;; Inherit: <IntegerBasic:PV>
PVL = $CC

;; The high byte of <PVL>.
PVH = $CD

;; Inherit: <IntegerBasic:ACC>
ACL = $CE

;; The high byte of <ACL>.
ACH = $CF

;; The X coordinate (2 bytes) of the last point plotted or the end of the last line, where the next line starts.
X0L = $0320

;; The high byte of <X0L>.
X0H = $0321

;; The Y coordinate of the last point plotted or the end of the last line.
Y0 = $0322

;; Where the routines BASIC calls keep X, which BASIC needs back.
BXSAV = $0323

;; The color, as a byte of dots, that <HPLOT> and <HLIN> draw with.
HCOLOR = $0324

;; The byte of the screen line the next dot is in, 0 to 39.
HNDX = $0325

;; The page drawn on: $20 for $2000-$3FFF (the default) or $40 for $4000-$5FFF.
HPAG = $0326

;; How many times <DRAW> repeats each step of a shape: its scale.
SCALE = $0327

;; The shape table's address (2 bytes), which <SHLOAD> sets.
SHAPXL = $0328

;; The high byte of <SHAPXL>.
SHAPXH = $0329

;; How many dots <DRAW> and <XDRAW> found already lit: their collision count.
COLLSN = $032A

;; Inherit: <Monitor:HIRES>
HIRES = $C057

;; Inherit: <Monitor:MIXSET>
MIXSET = $C053

;; Inherit: <Monitor:TXTCLR>
TXTCLR = $C050

;; Inherit: <IntegerBasic:MEMFULL>
MEMFUL = $E36B

;; Integer BASIC's RANGE ERR, which a BASIC parameter out of range jumps to.
RNGERR = $EE68

;; Integer BASIC's tape setup, which reads a 2-byte length and points <Monitor:A1L> and <Monitor:A2L> at it.
ACADR = $F11E

;; The Monitor's tape routine that waits for two edges of the signal.
RD2BIT = $FCFA

;; Inherit: <Monitor:READ>
READ = $FEFD

;; The Monitor's tape read after its header: <Monitor:READ> less the wait for the header tone.
READX1 = $FF02

;; INIT (CALL -12288): shows hi-res page 1 with four lines of text below, and clears the page drawn on to black.
;; Uses: A, Y
SETHRL:
    lda #$20                        ; $D000
    sta HPAG                        ; $D002
    lda HIRES                       ; $D005
    lda MIXSET                      ; $D008
    lda TXTCLR                      ; $D00B

;; CLEAR (CALL -12274): clears the page drawn on to black.
HCLR:
    lda #$00                        ; $D00E

;; Fills the page drawn on with the color in A.
BKGND0:
    sta HCOLOR1                     ; $D010

BKGND:
    lda HPAG                        ; $D012
    sta SHAPEH                      ; $D015
    ldy #$00                        ; $D017
    sty SHAPEL                      ; $D019

BKGND1:
    lda HCOLOR1                     ; $D01B
    sta (SHAPEL),y                  ; $D01D
    jsr CSHFT2                      ; $D01F
    iny                             ; $D022
    bne BKGND1                      ; $D023
    inc SHAPEH                      ; $D025
    lda SHAPEH                      ; $D027
    and #$1F                        ; $D029
    bne BKGND1                      ; $D02B
    rts                             ; $D02D

;; Moves to a point without plotting: sets <HBASL>/<HBASH>, <HNDX> and <HMASK> for it, and keeps it in <X0L>,
;; <X0H> and <Y0>.
;; In: A = Y, X = X's low byte, Y = X's high byte
;; Out: HCOLOR1 = the color shifted for the point's byte
HPOSN:
    sta Y0                          ; $D02E
    stx X0L                         ; $D031
    sty X0H                         ; $D034
    pha                             ; $D037
    and #$C0                        ; $D038
    sta HBASL                       ; $D03A
    lsr                             ; $D03C
    lsr                             ; $D03D
    ora HBASL                       ; $D03E
    sta HBASL                       ; $D040
    pla                             ; $D042
    sta HBASH                       ; $D043
    asl                             ; $D045
    asl                             ; $D046
    asl                             ; $D047
    rol HBASH                       ; $D048
    asl                             ; $D04A
    rol HBASH                       ; $D04B
    asl                             ; $D04D
    ror HBASL                       ; $D04E
    lda HBASH                       ; $D050
    and #$1F                        ; $D052
    ora HPAG                        ; $D054
    sta HBASH                       ; $D057
    txa                             ; $D059
    cpy #$00                        ; $D05A
    beq HPOSN2                      ; $D05C
    ldy #$23                        ; $D05E
    adc #$04                        ; $D060

HPOSN1:
    iny                             ; $D062

HPOSN2:
    sbc #$07                        ; $D063
    bcs HPOSN1                      ; $D065
    sty HNDX                        ; $D067
    tax                             ; $D06A
    lda MSKTBL-249,x                ; $D06B
    sta HMASK                       ; $D06E
    tya                             ; $D070
    lsr                             ; $D071
    lda HCOLOR                      ; $D072

HPOSN3:
    sta HCOLOR1                     ; $D075
    bcs CSHFT2                      ; $D077
    rts                             ; $D079

;; Plots a point in <HCOLOR>.
;; In: A = Y, X = X's low byte, Y = X's high byte
HPLOT:
    jsr HPOSN                       ; $D07A

HPLOT1:
    lda HCOLOR1                     ; $D07D
    eor (HBASL),y                   ; $D07F
    and HMASK                       ; $D081
    eor (HBASL),y                   ; $D083
    sta (HBASL),y                   ; $D085
    rts                             ; $D087

LFTRT:
    bpl RIGHT                       ; $D088

LEFT:
    lda HMASK                       ; $D08A
    lsr                             ; $D08C
    bcs LEFT1                       ; $D08D
    eor #$C0                        ; $D08F

LR1:
    sta HMASK                       ; $D091
    rts                             ; $D093

LEFT1:
    dey                             ; $D094
    bpl LEFT2                       ; $D095
    ldy #$27                        ; $D097

LEFT2:
    lda #$C0                        ; $D099

NEWNDX:
    sta HMASK                       ; $D09B
    sty HNDX                        ; $D09D

CSHIFT:
    lda HCOLOR1                     ; $D0A0

CSHFT2:
    asl                             ; $D0A2
    cmp #$C0                        ; $D0A3
    bpl RTS1                        ; $D0A5
    lda HCOLOR1                     ; $D0A7
    eor #$7F                        ; $D0A9
    sta HCOLOR1                     ; $D0AB

RTS1:
    rts                             ; $D0AD

RIGHT:
    lda HMASK                       ; $D0AE
    asl                             ; $D0B0
    eor #$80                        ; $D0B1
    bmi LR1                         ; $D0B3
    lda #$81                        ; $D0B5
    iny                             ; $D0B7
    cpy #$28                        ; $D0B8
    bcc NEWNDX                      ; $D0BA
    ldy #$00                        ; $D0BC
    bcs NEWNDX                      ; $D0BE

LRUDX1:
    clc                             ; $D0C0

LRUDX2:
    lda SHAPEX                      ; $D0C1
    and #$04                        ; $D0C3
    beq LRUD4                       ; $D0C5
    lda #$7F                        ; $D0C7
    and HMASK                       ; $D0C9
    and (HBASL),y                   ; $D0CB
    bne LRUD3                       ; $D0CD
    inc COLLSN                      ; $D0CF
    lda #$7F                        ; $D0D2
    and HMASK                       ; $D0D4
    bpl LRUD3                       ; $D0D6

LRUD1:
    clc                             ; $D0D8

LRUD2:
    lda SHAPEX                      ; $D0D9
    and #$04                        ; $D0DB
    beq LRUD4                       ; $D0DD
    lda (HBASL),y                   ; $D0DF
    eor HCOLOR1                     ; $D0E1
    and HMASK                       ; $D0E3
    bne LRUD3                       ; $D0E5
    inc COLLSN                      ; $D0E7

LRUD3:
    eor (HBASL),y                   ; $D0EA
    sta (HBASL),y                   ; $D0EC

LRUD4:
    lda SHAPEX                      ; $D0EE
    adc QDRNT                       ; $D0F0
    and #$03                        ; $D0F2
EQ3 = * - 1                         ;; the AND #$03 operand byte, which BIT tests
    cmp #$02                        ; $D0F4
    ror                             ; $D0F6

LRUD:
    bcs LFTRT                       ; $D0F7

UPDWN:
    bmi DOWN4                       ; $D0F9

UP:
    clc                             ; $D0FB
    lda HBASH                       ; $D0FC
    bit EQ1C                        ; $D0FE
    bne UP4                         ; $D101
    asl HBASL                       ; $D103
    bcs UP2                         ; $D105
    bit EQ3                         ; $D107
    beq UP1                         ; $D10A
    adc #$1F                        ; $D10C
    sec                             ; $D10E
    bcs UP3                         ; $D10F

UP1:
    adc #$23                        ; $D111
    pha                             ; $D113
    lda HBASL                       ; $D114
    adc #$B0                        ; $D116
    bcs UP5                         ; $D118
    adc #$F0                        ; $D11A

UP5:
    sta HBASL                       ; $D11C
    pla                             ; $D11E
    bcs UP3                         ; $D11F

UP2:
    adc #$1F                        ; $D121

UP3:
    ror HBASL                       ; $D123

UP4:
    adc #$FC                        ; $D125

UPDWN1:
    sta HBASH                       ; $D127
    rts                             ; $D129

DOWN:
    clc                             ; $D12A

DOWN4:
    lda HBASH                       ; $D12B
    adc #$04                        ; $D12D
EQ4 = * - 1                         ;; the ADC #$04 operand byte, which BIT tests
    bit EQ1C                        ; $D12F
    bne UPDWN1                      ; $D132
    asl HBASL                       ; $D134
    bcc DOWN1                       ; $D136
    adc #$E0                        ; $D138
    clc                             ; $D13A
    bit EQ4                         ; $D13B
    beq DOWN2                       ; $D13E
    lda HBASL                       ; $D140
    adc #$50                        ; $D142
    eor #$F0                        ; $D144
    beq DOWN3                       ; $D146
    eor #$F0                        ; $D148

DOWN3:
    sta HBASL                       ; $D14A
    lda HPAG                        ; $D14C
    bcc DOWN2                       ; $D14F

DOWN1:
    adc #$E0                        ; $D151

DOWN2:
    ror HBASL                       ; $D153
    bcc UPDWN1                      ; $D155

;; Draws a line from (0,0) to a point: <HLIN> after clearing the last point.
HLINRL:
    pha                             ; $D157
    lda #$00                        ; $D158
    sta X0L                         ; $D15A
    sta X0H                         ; $D15D
    sta Y0                          ; $D160
    pla                             ; $D163

;; Draws a line in <HCOLOR> from the last point plotted (<X0L>, <X0H>, <Y0>) to a point, which becomes the last.
;; In: A = the X's low byte, X = its high byte, Y = the Y
HLIN:
    pha                             ; $D164
    sec                             ; $D165
    sbc X0L                         ; $D166
    pha                             ; $D169
    txa                             ; $D16A
    sbc X0H                         ; $D16B
    sta QDRNT                       ; $D16E
    bcs HLIN2                       ; $D170
    pla                             ; $D172
    eor #$FF                        ; $D173
    adc #$01                        ; $D175
    pha                             ; $D177
    lda #$00                        ; $D178
    sbc QDRNT                       ; $D17A

HLIN2:
    sta DXH                         ; $D17C
    sta EH                          ; $D17E
    pla                             ; $D180
    sta DXL                         ; $D181
    sta EL                          ; $D183
    pla                             ; $D185
    sta X0L                         ; $D186
    stx X0H                         ; $D189
    tya                             ; $D18C
    clc                             ; $D18D
    sbc Y0                          ; $D18E
    bcc HLIN3                       ; $D191
    eor #$FF                        ; $D193
    adc #$FE                        ; $D195

HLIN3:
    sta DY                          ; $D197
    sty Y0                          ; $D199
    ror QDRNT                       ; $D19C
    sec                             ; $D19E
    sbc DXL                         ; $D19F
    tax                             ; $D1A1
    lda #$FF                        ; $D1A2
    sbc DXH                         ; $D1A4
    sta COUNTH                      ; $D1A6
    ldy HNDX                        ; $D1A8
    bcs MOVEX2                      ; $D1AB

MOVEX:
    asl                             ; $D1AD
    jsr LFTRT                       ; $D1AE
    sec                             ; $D1B1

MOVEX2:
    lda EL                          ; $D1B2
    adc DY                          ; $D1B4
    sta EL                          ; $D1B6
    lda EH                          ; $D1B8
    sbc #$00                        ; $D1BA

HCOUNT:
    sta EH                          ; $D1BC
    lda (HBASL),y                   ; $D1BE
    eor HCOLOR1                     ; $D1C0
    and HMASK                       ; $D1C2
    eor (HBASL),y                   ; $D1C4
    sta (HBASL),y                   ; $D1C6
    inx                             ; $D1C8
    bne HLIN4                       ; $D1C9
    inc COUNTH                      ; $D1CB
    beq RTS2                        ; $D1CD

HLIN4:
    lda QDRNT                       ; $D1CF
    bcs MOVEX                       ; $D1D1
    jsr UPDWN                       ; $D1D3
    clc                             ; $D1D6
    lda EL                          ; $D1D7
    adc DXL                         ; $D1D9
    sta EL                          ; $D1DB
    lda EH                          ; $D1DD
    adc DXH                         ; $D1DF
    bvc HCOUNT                      ; $D1E1

MSKTBL:
    .byte $81                       ; $D1E3
    .byte $82, $84, $88             ; $D1E4
    .byte $90, $A0                  ; $D1E7
    .byte $C0                       ; $D1E9

EQ1C:
    .byte $1C                       ; $D1EA

COS:
    .byte $FF, $FE, $FA, $F4, $EC, $E1, $D4, $C5, $B4; $D1EB
    .byte $A1, $8D, $78, $61, $49, $31, $18, $FF; $D1F4

;; FIND (CALL -11780): works out the last point drawn from the screen position, and puts it in <X0L>, <X0H>
;; and <Y0>, where BASIC's X0 and Y0 can read it.
;; Out: X0L/X0H = X, Y0 = Y
HFIND:
    lda HBASL                       ; $D1FC
    asl                             ; $D1FE
    lda HBASH                       ; $D1FF
    and #$03                        ; $D201
    rol                             ; $D203
    ora HBASL                       ; $D204
    asl                             ; $D206
    asl                             ; $D207
    asl                             ; $D208
    sta Y0                          ; $D209
    lda HBASH                       ; $D20C
    lsr                             ; $D20E
    lsr                             ; $D20F
    and #$07                        ; $D210
    ora Y0                          ; $D212
    sta Y0                          ; $D215
    lda HNDX                        ; $D218
    asl                             ; $D21B
    adc HNDX                        ; $D21C
    asl                             ; $D21F
    tax                             ; $D220
    dex                             ; $D221
    lda HMASK                       ; $D222
    and #$7F                        ; $D224

HFIND1:
    inx                             ; $D226
    lsr                             ; $D227
    bne HFIND1                      ; $D228
    sta X0H                         ; $D22A
    txa                             ; $D22D
    clc                             ; $D22E
    adc HNDX                        ; $D22F
    bcc HFIND2                      ; $D232
    inc X0H                         ; $D234

HFIND2:
    sta X0L                         ; $D237

RTS2:
    rts                             ; $D23A

;; Draws a shape from <SHAPEL>/<SHAPEH> in <HCOLOR>, rotated and scaled, at the last point.
;; In: X = the shape's address, low byte; Y = its high byte; A = the rotation, 0 to 63 (16 is a quarter turn)
DRAW:
    stx SHAPEL                      ; $D23B
    sty SHAPEH                      ; $D23D

DRAW1:
    tax                             ; $D23F
    lsr                             ; $D240
    lsr                             ; $D241
    lsr                             ; $D242
    lsr                             ; $D243
    sta QDRNT                       ; $D244
    txa                             ; $D246
    and #$0F                        ; $D247
    tax                             ; $D249
    ldy COS,x                       ; $D24A
    sty DXL                         ; $D24D
    eor #$0F                        ; $D24F
    tax                             ; $D251
    ldy COS+1,x                     ; $D252
    iny                             ; $D255
    sty DY                          ; $D256

DRAW2:
    ldy HNDX                        ; $D258
    ldx #$00                        ; $D25B
    stx COLLSN                      ; $D25D
    lda (SHAPEL,x)                  ; $D260

DRAW3:
    sta SHAPEX                      ; $D262
    ldx #$80                        ; $D264
    stx EL                          ; $D266
    stx EH                          ; $D268
    ldx SCALE                       ; $D26A

DRAW4:
    lda EL                          ; $D26D
    sec                             ; $D26F
    adc DXL                         ; $D270
    sta EL                          ; $D272
    bcc DRAW5                       ; $D274
    jsr LRUD1                       ; $D276
    clc                             ; $D279

DRAW5:
    lda EH                          ; $D27A
    adc DY                          ; $D27C
    sta EH                          ; $D27E
    bcc DRAW6                       ; $D280
    jsr LRUD2                       ; $D282

DRAW6:
    dex                             ; $D285
    bne DRAW4                       ; $D286
    lda SHAPEX                      ; $D288
    lsr                             ; $D28A
    lsr                             ; $D28B
    lsr                             ; $D28C
    bne DRAW3                       ; $D28D
    inc SHAPEL                      ; $D28F
    bne DRAW7                       ; $D291
    inc SHAPEH                      ; $D293

DRAW7:
    lda (SHAPEL,x)                  ; $D295
    bne DRAW3                       ; $D297
    rts                             ; $D299

;; Draws a shape as <DRAW> does, but inverts each dot instead of setting it, so drawing it again erases it.
;; In: X = the shape's address, low byte; Y = its high byte; A = the rotation, 0 to 3 quarter turns
XDRAW:
    stx SHAPEL                      ; $D29A
    sty SHAPEH                      ; $D29C

XDRAW1:
    tax                             ; $D29E
    lsr                             ; $D29F
    lsr                             ; $D2A0
    lsr                             ; $D2A1
    lsr                             ; $D2A2
    sta QDRNT                       ; $D2A3
    txa                             ; $D2A5
    and #$0F                        ; $D2A6
    tax                             ; $D2A8
    ldy COS,x                       ; $D2A9
    sty DXL                         ; $D2AC
    eor #$0F                        ; $D2AE
    tax                             ; $D2B0
    ldy COS+1,x                     ; $D2B1
    iny                             ; $D2B4
    sty DY                          ; $D2B5

XDRAW2:
    ldy HNDX                        ; $D2B7
    ldx #$00                        ; $D2BA
    stx COLLSN                      ; $D2BC
    lda (SHAPEL,x)                  ; $D2BF

XDRAW3:
    sta SHAPEX                      ; $D2C1
    ldx #$80                        ; $D2C3
    stx EL                          ; $D2C5
    stx EH                          ; $D2C7
    ldx SCALE                       ; $D2C9

XDRAW4:
    lda EL                          ; $D2CC
    sec                             ; $D2CE
    adc DXL                         ; $D2CF
    sta EL                          ; $D2D1
    bcc XDRAW5                      ; $D2D3
    jsr LRUDX1                      ; $D2D5
    clc                             ; $D2D8

XDRAW5:
    lda EH                          ; $D2D9
    adc DY                          ; $D2DB
    sta EH                          ; $D2DD
    bcc XDRAW6                      ; $D2DF
    jsr LRUD2                       ; $D2E1

XDRAW6:
    dex                             ; $D2E4
    bne XDRAW4                      ; $D2E5
    lda SHAPEX                      ; $D2E7
    lsr                             ; $D2E9
    lsr                             ; $D2EA
    lsr                             ; $D2EB
    bne XDRAW3                      ; $D2EC
    inc SHAPEL                      ; $D2EE
    bne XDRAW7                      ; $D2F0
    inc SHAPEH                      ; $D2F2

XDRAW7:
    lda (SHAPEL,x)                  ; $D2F4
    bne XDRAW3                      ; $D2F6
    rts                             ; $D2F8

;; POSN (CALL -11527): moves to (X0, Y0) in the color COLR without plotting.
BPOSN:
    jsr PCOLR                       ; $D2F9
    sta HCOLOR                      ; $D2FC
    jsr GETY0                       ; $D2FF
    pha                             ; $D302
    jsr GETX0                       ; $D303
    pla                             ; $D306
    jsr HPOSN                       ; $D307
    ldx BXSAV                       ; $D30A
    rts                             ; $D30D

;; PLOT (CALL -11506): plots (X0, Y0) in the color COLR.
BPLOT:
    jsr BPOSN                       ; $D30E
    jmp HPLOT1                      ; $D311

;; LINE (CALL -11500): draws a line in the color COLR from the last point to (X0, Y0).
BLIN1:
    lda HNDX                        ; $D314
    lsr                             ; $D317
    jsr PCOLR                       ; $D318
    jsr HPOSN3                      ; $D31B

BLINE:
    jsr GETX0                       ; $D31E
    txa                             ; $D321
    pha                             ; $D322
    tya                             ; $D323
    tax                             ; $D324
    jsr GETY0                       ; $D325
    tay                             ; $D328
    pla                             ; $D329
    jsr HLIN                        ; $D32A
    ldx BXSAV                       ; $D32D
    rts                             ; $D330

;; BKGND (CALL -11471): fills the page drawn on with the color COLR.
BGND:
    jsr PCOLR                       ; $D331
    jmp BKGND0                      ; $D334

;; DRAW (CALL -11465): moves to (X0, Y0), then draws shape number SHAPE as <BDRAW> does.
BDRAW1:
    jsr BPOSN                       ; $D337

;; DRAW1 (CALL -11462): draws shape number SHAPE at the last point, rotated by ROT and scaled by SCALE.
BDRAW:
    jsr BDRAWX                      ; $D33A
    jsr DRAW                        ; $D33D
    ldx BXSAV                       ; $D340
    rts                             ; $D343

;; Moves to (X0, Y0), then draws shape number SHAPE as <BXDRAW> does.
BXDRW1:
    jsr BPOSN                       ; $D344

;; Draws shape number SHAPE at the last point as <XDRAW> does, inverting each dot.
BXDRAW:
    jsr BDRAWX                      ; $D347
    jsr XDRAW                       ; $D34A
    ldx BXSAV                       ; $D34D
    rts                             ; $D350

BDRAWX:
    stx BXSAV                       ; $D351
    ldy #$32                        ; $D354
    jsr PBYTE                       ; $D356
    sta SCALE                       ; $D359
    ldy #$28                        ; $D35C
    jsr PBYTE                       ; $D35E
    pha                             ; $D361
    lda SHAPXL                      ; $D362
    sta SHAPEL                      ; $D365
    lda SHAPXH                      ; $D367
    sta SHAPEH                      ; $D36A
    ldy #$20                        ; $D36C
    jsr PBYTE                       ; $D36E
    beq RERR1                       ; $D371
    ldx #$00                        ; $D373
    cmp (SHAPEL,x)                  ; $D375
    beq BDRWX1                      ; $D377
    bcs RERR1                       ; $D379

BDRWX1:
    asl                             ; $D37B
    bcc BDRWX2                      ; $D37C
    inc SHAPEH                      ; $D37E
    clc                             ; $D380

BDRWX2:
    tay                             ; $D381
    lda (SHAPEL),y                  ; $D382
    adc SHAPEL                      ; $D384
    tax                             ; $D386
    iny                             ; $D387
    lda (SHAPEL),y                  ; $D388
    adc SHAPXH                      ; $D38A
    tay                             ; $D38D
    pla                             ; $D38E
    rts                             ; $D38F

;; Reads COLR, BASIC's third variable, as a byte; RANGE ERR if it is over 255.
PCOLR:
    ldy #$16                        ; $D390

PBYTE:
    lda (LOMEML),y                  ; $D392
    bne RERR1                       ; $D394
    dey                             ; $D396
    lda (LOMEML),y                  ; $D397

RTSB:
    rts                             ; $D399

;; Reads X0, BASIC's first variable; RANGE ERR if it is over 279.
;; Out: X = its low byte, Y = its high byte
GETX0:
    stx BXSAV                       ; $D39A
    ldy #$05                        ; $D39D
    lda (LOMEML),y                  ; $D39F
    tax                             ; $D3A1
    iny                             ; $D3A2
    lda (LOMEML),y                  ; $D3A3
    tay                             ; $D3A5
    cpx #$18                        ; $D3A6
    sbc #$01                        ; $D3A8
    bcc RTSB                        ; $D3AA

RERR1:
    jmp RNGERR                      ; $D3AC

;; Reads Y0, BASIC's second variable; RANGE ERR if it is over 191.
;; Out: A = Y0
GETY0:
    ldy #$0D                        ; $D3AF
    jsr PBYTE                       ; $D3B1
    cmp #$C0                        ; $D3B4
    bcs RERR1                       ; $D3B6
    rts                             ; $D3B8

;; SHLOAD (CALL -11335): loads a shape table from tape to $0800, after a 2-byte length, and moves LOMEM above it;
;; MEM FULL if it reaches the program.
;; Out: SHAPXL/SHAPXH = $0800
SHLOAD:
    stx BXSAV                       ; $D3B9
    jsr ACADR                       ; $D3BC
    jsr READ                        ; $D3BF
    lda #$00                        ; $D3C2
    sta A1L                         ; $D3C4
    sta SHAPXL                      ; $D3C6
    clc                             ; $D3C9
    adc ACL                         ; $D3CA
    tay                             ; $D3CC
    lda #$08                        ; $D3CD
    sta A1H                         ; $D3CF
    sta SHAPXH                      ; $D3D1
    adc ACH                         ; $D3D4
    bcs MFULL1                      ; $D3D6
    cpy PPL                         ; $D3D8
    pha                             ; $D3DA
    sbc PPH                         ; $D3DB
    pla                             ; $D3DD
    bcs MFULL1                      ; $D3DE
    sty A2L                         ; $D3E0
    sta A2H                         ; $D3E2
    iny                             ; $D3E4
    bne SHLOD1                      ; $D3E5
    adc #$01                        ; $D3E7

SHLOD1:
    sty LOMEML                      ; $D3E9
    sta LOMEMH                      ; $D3EB
    sty PVL                         ; $D3ED
    sta PVH                         ; $D3EF
    jsr RD2BIT                      ; $D3F1
    lda #$03                        ; $D3F4
    jsr READX1                      ; $D3F6
    ldx BXSAV                       ; $D3F9
    rts                             ; $D3FC

MFULL1:
    jmp MEMFUL                      ; $D3FD

.endscope
