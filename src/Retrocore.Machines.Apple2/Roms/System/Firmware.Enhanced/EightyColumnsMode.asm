;; Copies CV to $05FB and computes BASL/BASH for it; $CE03 does row A. Adds WNDLFT (halved when 80VID
;; is on, since each memory byte holds two columns).
;; In: CV = the row (A when entered at $CE03)
VTAB80:
    lda CV                          ; $CDFE
    sta OURCV                       ; $CE00

VTAB80_1:
    jsr ROWBASE                     ; $CE03 row in A
    lda WNDLFT                      ; $CE06
    bit RD80VID                     ; $CE08
    bpl VTAB80_2                    ; $CE0B
    lsr a                           ; $CE0D

VTAB80_2:
    clc                             ; $CE0E
    adc BASL                        ; $CE0F
    sta BASL                        ; $CE11
    rts                             ; $CE13

;; Converts lowercase letters to uppercase.
;; In:  A = the character
;; Out: A = the result
UPSHIFT:
    cmp #'a'                        ; $CE14
    bcc UPSHIFT_1                   ; $CE16
    cmp #'z' + 1                    ; $CE18
    bcs UPSHIFT_1                   ; $CE1A
    and #$DF                        ; $CE1C

UPSHIFT_1:
    rts                             ; $CE1E

;; Inverts the character at column $057B unless $04FB bit 4 (cursor off) is set; <FLIPCURSOR_1> always does.
;; Out:   A = $00 when the character is inverted, $10 when it is skipped
;; Keeps: Y
FLIPCURSOR:
    lda MODE80                      ; $CE1F
    and #$10                        ; $CE22
    bne FLIPCURSOR_2                ; $CE24

;; Inverts the character at column $057B, whatever $04FB bit 4 says: <FLIPCURSOR> without its cursor-off check.
;; Keeps: A, Y
FLIPCURSOR_1:
    pha                             ; $CE26
    tya                             ; $CE27
    pha                             ; $CE28
    ldy OURCH                       ; $CE29
    jsr GETSCRCHAR                  ; $CE2C
    eor #$80                        ; $CE2F
    jsr PUTSCRCHAR                  ; $CE31
    pla                             ; $CE34
    tay                             ; $CE35
    pla                             ; $CE36

FLIPCURSOR_2:
    rts                             ; $CE37

;; Stores A at column Y via PUTSCRCHAR, clearing bit 7 first when INVFLG bit 7 is clear.
;; Keeps: A
PUTINV:
    pha                             ; $CE38
    bit INVFLG                      ; $CE39
    bmi PUTINV_1                    ; $CE3B
    and #$7F                        ; $CE3D

PUTINV_1:
    jsr PUTSCRCHAR                  ; $CE3F
    pla                             ; $CE42

PUTINV_2:
    rts                             ; $CE43


;; Reads the screen character at window column Y (with 80VID: aux for even, main for odd columns);
;; with ALTCHAR on, codes below $20 get $40 added.
;; In: Y, BASL/BASH
;; Out: A = character; Y preserved
;; Uses: BAS2L
GETSCRCHAR:
    lda (BASL),y                    ; $CE44
    bit RD80VID                     ; $CE46
    bpl GETSCRCHAR_2                ; $CE49
    sta SET80STORE                  ; $CE4B
    sty BAS2L                       ; $CE4E
    tya                             ; $CE50
    eor WNDLFT                      ; $CE51
    ror a                           ; $CE53
    bcs GETSCRCHAR_1                ; $CE54
    lda HISCR                       ; $CE56
    iny                             ; $CE59

GETSCRCHAR_1:
    tya                             ; $CE5A
    lsr a                           ; $CE5B
    tay                             ; $CE5C
    lda (BASL),y                    ; $CE5D
    bit LOWSCR                      ; $CE5F
    ldy BAS2L                       ; $CE62

GETSCRCHAR_2:
    bit RDALTCHAR                   ; $CE64
    bpl GETSCRCHAR_3                ; $CE67
    cmp #$20                        ; $CE69
    bcs GETSCRCHAR_3                ; $CE6B
    ora #$40                        ; $CE6D

GETSCRCHAR_3:
    rts                             ; $CE6F

;; Stores A at window column Y (80VID: aux or main byte as GETSCRCHAR). With $04FB bit 0 and ALTCHAR
;; on, inverse $40-$5F are stored as $00-$1F so they show as inverse capitals instead of MouseText.
;; In: A, Y, BASL/BASH
;; Keeps: A, Y
;; Uses: BAS2L
PUTSCRCHAR:
    pha                             ; $CE70
    and #$FF                        ; $CE71
    bmi PUTSCRCHAR_1                ; $CE73
    lda MODE80                      ; $CE75
    ror a                           ; $CE78
    pla                             ; $CE79
    pha                             ; $CE7A
    bcc PUTSCRCHAR_1                ; $CE7B
    bit RDALTCHAR                   ; $CE7D
    bpl PUTSCRCHAR_1                ; $CE80
    eor #$40                        ; $CE82
    bit PUTSCRCHAR_3                ; $CE84
    beq PUTSCRCHAR_1                ; $CE87
    eor #$40                        ; $CE89

PUTSCRCHAR_1:
    bit RD80VID                     ; $CE8B
    bpl PUTSCRCHAR_4                ; $CE8E
    sta SET80STORE                  ; $CE90
    pha                             ; $CE93
    sty BAS2L                       ; $CE94
    tya                             ; $CE96
    eor WNDLFT                      ; $CE97
    lsr a                           ; $CE99
    bcs PUTSCRCHAR_2                ; $CE9A
    lda HISCR                       ; $CE9C
    iny                             ; $CE9F

PUTSCRCHAR_2:
    tya                             ; $CEA0
    lsr a                           ; $CEA1
    tay                             ; $CEA2
    pla                             ; $CEA3
    sta (BASL),y                    ; $CEA4
    lda LOWSCR                      ; $CEA6
    ldy BAS2L                       ; $CEA9
    pla                             ; $CEAB

PUTSCRCHAR_3:
    rts                             ; $CEAC

;; 40-column store for PUTSCRCHAR.
PUTSCRCHAR_4:
    sta (BASL),y                    ; $CEAD
    pla                             ; $CEAF
    rts                             ; $CEB0

;; Saves the character at $057B in $067B and shows a "+" there (inverse over a normal character).
;; Keeps: A, Y
ESCCURSOR:
    pha                             ; $CEB1
    tya                             ; $CEB2
    pha                             ; $CEB3
    ldy OURCH                       ; $CEB4
    jsr GETSCRCHAR                  ; $CEB7
    sta CHAR                        ; $CEBA
    and #$80                        ; $CEBD
    eor #'+'                        ; $CEBF
    jmp RESTCHAR_1                  ; $CEC1

;; Puts $067B back at column $057B.
;; Keeps: A, Y
RESTCHAR:
    pha                             ; $CEC4
    tya                             ; $CEC5
    pha                             ; $CEC6
    ldy OURCH                       ; $CEC7
    lda CHAR                        ; $CECA

RESTCHAR_1:
    jsr PUTSCRCHAR                  ; $CECD
    pla                             ; $CED0
    tay                             ; $CED1
    pla                             ; $CED2
    rts                             ; $CED3

;; Pascal state: full 80-column window, INVFLG $FF ($7F when $04FB bit 2 is set), BASL/BASH from
;; $077B/$07FB and CV from $05FB.
PASRESTORE:
    jsr FULLWND_1                   ; $CED4
    lda #$FF                        ; $CED7
    sta INVFLG                      ; $CED9
    lda MODE80                      ; $CEDB
    and #$04                        ; $CEDE
    beq PASRESTORE_1                ; $CEE0
    lsr INVFLG                      ; $CEE2

PASRESTORE_1:
    lda OLDBASL                     ; $CEE4
    sta BASL                        ; $CEE7
    lda OLDBASH                     ; $CEE9
    sta BASH                        ; $CEEC
    lda OURCV                       ; $CEEE
    sta CV                          ; $CEF1
    rts                             ; $CEF3

;; If language card RAM is being read and its $FBB3 is not $06, copies the ROM $F800-$FFFF into that
;; RAM (reading ROM while writing RAM) and restores the bank and write state. Appears meant to make
;; sure a Monitor in language card RAM is the IIe one.
;; Uses: CSWL/CSWH (the pointer), X, Y
LCMONCOPY:
    bit RDLCRAM                     ; $CEF4
    bpl LCMONCOPY_4                 ; $CEF7
    lda #$06                        ; $CEF9
    cmp VERSION                     ; $CEFB
    beq LCMONCOPY_4                 ; $CEFE
    ldx #$03                        ; $CF00
    bit RDLCBNK2                    ; $CF02
    bmi LCMONCOPY_1                 ; $CF05
    ldx #$0B                        ; $CF07

LCMONCOPY_1:
    sta VERSION                     ; $CF09
    bit $C080                       ; $CF0C
    lda VERSION                     ; $CF0F
    cmp #$06                        ; $CF12
    beq LCMONCOPY_2                 ; $CF14
    inx                             ; $CF16

LCMONCOPY_2:
    bit ROMIN                       ; $CF17
    bit ROMIN                       ; $CF1A
    ldy #$00                        ; $CF1D
    lda #$F8                        ; $CF1F
    sta CSWH                        ; $CF21
    sty CSWL                        ; $CF23

LCMONCOPY_3:
    lda (CSWL),y                    ; $CF25
    sta (CSWL),y                    ; $CF27
    iny                             ; $CF29
    bne LCMONCOPY_3                 ; $CF2A
    inc CSWH                        ; $CF2C
    bne LCMONCOPY_3                 ; $CF2E
    lda $C080,x                     ; $CF30
    lda $C080,x                     ; $CF33

LCMONCOPY_4:
    rts                             ; $CF36
    .byte $00, $00, $00             ; $CF37

;; Mini-assembler relative branch: computes the offset from PC to A2 into A2L and fails when out of
;; range. $CF55 stores LENGTH+1 bytes (opcode in A1H, operand in A2) at PC, then moves up two lines and
;; lets the Monitor's $FCE3 display the instruction.
MINIREL:
    sbc #$81                        ; $CF3A
    lsr a                           ; $CF3C
    bne MINIREL_3                   ; $CF3D
    ldy A2H                         ; $CF3F
    ldx A2L                         ; $CF41
    bne MINIREL_1                   ; $CF43
    dey                             ; $CF45

MINIREL_1:
    dex                             ; $CF46
    txa                             ; $CF47
    clc                             ; $CF48
    sbc PCL                         ; $CF49
    sta A2L                         ; $CF4B
    bpl MINIREL_2                   ; $CF4D
    iny                             ; $CF4F

MINIREL_2:
    tya                             ; $CF50
    sbc PCH                         ; $CF51

MINIREL_3:
    bne MINIFIND_2                  ; $CF53

MINIREL_4:
    ldy LENGTH                      ; $CF55 store the instruction

MINIREL_5:
    lda a:A1H,y                     ; $CF57
    sta (PCL),y                     ; $CF5A
    dey                             ; $CF5C
    bpl MINIREL_5                   ; $CF5D
    jsr PRBLNK                      ; $CF5F
    jsr UP                          ; $CF62
    jsr UP                          ; $CF65
    jmp $FCE3                       ; $CF68

;; Mini-assembler opcode search: for each opcode A1H from $FF down, compares its mnemonic (via INSDS2,
;; MNEMR, MNEML) with A4L/A4H and its format with A5L/MASK. $CF95 reports an error: X = YSAV and the
;; Monitor's $FCD2 shows a ^ under the bad column and prompts again.
MINIFIND:
    lda A1H                         ; $CF6B
    jsr $F88E                       ; $CF6D
    tax                             ; $CF70
    lda MNEMR,x                     ; $CF71
    cmp A4L                         ; $CF74
    bne MINIFIND_1                  ; $CF76
    lda MNEML,x                     ; $CF78
    cmp A4H                         ; $CF7B
    bne MINIFIND_1                  ; $CF7D
    lda A5L                         ; $CF7F
    ldy MASK                        ; $CF81
    cpy #$9D                        ; $CF83 the relative mode's format
    beq MINIREL                     ; $CF85
    cmp MASK                        ; $CF87
    beq MINIREL_4                   ; $CF89

MINIFIND_1:
    dec A1H                         ; $CF8B
    bne MINIFIND                    ; $CF8D
    inc A5L                         ; $CF8F
    dec YSAV1                       ; $CF91
    beq MINIFIND                    ; $CF93

MINIFIND_2:
    ldy YSAV                        ; $CF95

MINIFIND_3:
    tya                             ; $CF97 error at column Y
    tax                             ; $CF98
    jmp $FCD2                       ; $CF99

;; Mini-assembler line (from the Monitor's $FCFA after the "!" prompt): a blank first character means
;; an instruction, a lone CR returns; anything else is taken as an address (MINIPARSE).
MINILINE:
    jsr ZMODE                       ; $CF9C
    lda IN                          ; $CF9F
    cmp #' '                        ; $CFA2
    beq MINIPARSE_2                 ; $CFA4
    cmp #KEY_CR                     ; $CFA6
    bne MINIPARSE                   ; $CFA8
    rts                             ; $CFAA

;; Reads an address with GETNUM; it must be followed by ":" (sets PC with the Monitor's A1PC). Then
;; packs three mnemonic letters into A4L/A4H and parses the operand with MINIOPND.
MINIPARSE:
    jsr GETNUM                      ; $CFAB
    cmp #((':' ^ $B0) + $89) & $FF  ; $CFAE GETNUM leaves the next character as (c ^ $B0) + $89

MINIPARSE_1:
    bne MINIFIND_3                  ; $CFB0
    txa                             ; $CFB2
    beq MINIFIND_3                  ; $CFB3
    jsr A1PCLP                      ; $CFB5

MINIPARSE_2:
    lda #$03                        ; $CFB8
    sta A1H                         ; $CFBA

MINIPARSE_3:
    jsr SKIPBLNK                    ; $CFBC
    asl a                           ; $CFBF
    sbc #$BE                        ; $CFC0
    cmp #$C2                        ; $CFC2
    bcc MINIFIND_3                  ; $CFC4
    asl a                           ; $CFC6
    asl a                           ; $CFC7
    ldx #$04                        ; $CFC8

MINIPARSE_4:
    asl a                           ; $CFCA
    rol A4L                         ; $CFCB
    rol A4H                         ; $CFCD
    dex                             ; $CFCF
    bpl MINIPARSE_4                 ; $CFD0
    dec A1H                         ; $CFD2
    beq MINIPARSE_4                 ; $CFD4
    bpl MINIPARSE_3                 ; $CFD6
    ldx #$05                        ; $CFD8
    jsr MINIOPND                    ; $CFDA

;; Combines A5L and YSAV1 into the operand format in A5L; the line must end in ";" or CR, then MINIFIND.
MINIFMT:
    lda A5L                         ; $CFDD
    asl a                           ; $CFDF
    asl a                           ; $CFE0
    ora YSAV1                       ; $CFE1
    cmp #$20                        ; $CFE3
    bcs MINIFMT_1                   ; $CFE5
    ldx YSAV1                       ; $CFE7
    beq MINIFMT_1                   ; $CFE9
    ora #$80                        ; $CFEB

MINIFMT_1:
    sta A5L                         ; $CFED
    sty YSAV                        ; $CFEF
    lda IN,y                        ; $CFF1
    cmp #';'                        ; $CFF4
    beq MINIFMT_2                   ; $CFF6
    cmp #KEY_CR                     ; $CFF8

    bne MINIPARSE_1                 ; $CFFA

MINIFMT_2:
    jmp MINIFIND                    ; $CFFC

;; Last ROM byte; reading $CFFF releases the slots' $C800 expansion ROM (SETMSLOT3 does this).
CLRROM:
    .byte $DF                       ; $CFFF
