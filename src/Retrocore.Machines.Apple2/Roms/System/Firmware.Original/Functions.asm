;; Entry from the Monitor's switch routine at $FBB4 (internal ROM already switched in). Selects a function by Y.
;; In: Y = function number (0-7), A = character for functions 6 and 7; the stack holds the caller's P and a
;;      second P whose N bit is the RDCXROM state on entry.
;; Y=6 goes to B_KEYIN, Y=7 to B_ESCFIX; others continue at B_FUNCNK/B_FUNCNE.
B_FUNC:
    cpy #$06                        ; $C100
    bne B_FUNCNK                    ; $C102
    jmp B_KEYIN                     ; $C104

;; Function 7 test: sends Y=7 to B_ESCFIX, everything else on to B_FUNCNE.
B_FUNCNK:
    cpy #$07                        ; $C107
    bne B_FUNCNE                    ; $C109
    jmp B_ESCFIX                    ; $C10B

;; Chooses the 40- or 80-column version of functions 0-5: when an 80-column card answers (TESTCARD) and
;; mode bits 5 and 3 of $04FB are clear, goes to B_FUNC0, otherwise B_OLDFUNC.
;; Uses: A, Y (restored for the dispatch)
B_FUNCNE:
    tya                             ; $C10E
    pha                             ; $C10F
    jsr TESTCARD                    ; $C110
    bne B_OLDFUNC                   ; $C113
    lda MODE80                      ; $C115
    and #$28                        ; $C118
    bne B_OLDFUNC                   ; $C11A
    jmp B_FUNC0                     ; $C11C

;; Dispatches functions 0-5 to their 40-column versions through F_TABLE by pushing $C1 and the table byte
;; and executing RTS.
B_OLDFUNC:
    pla                             ; $C11F
    tay                             ; $C120
    lda #$C1                        ; $C121 the page of F_TABLE's functions
    pha                             ; $C123
    lda F_TABLE,y                   ; $C124
    pha                             ; $C127
    rts                             ; $C128

;; Function 0, 40 columns: clears from CH to the end of the line and then every line down to WNDBTM.
;; Uses: A, Y, BASL/BASH (left at CV's line by VTAB)
F_CLREOP:
    ldy CH                          ; $C129
    lda CV                          ; $C12B

CLEOP1:
    pha                             ; $C12D
    jsr VTABZ                       ; $C12E
    jsr X_CLEOLZ                    ; $C131
    ldy #$00                        ; $C134
    pla                             ; $C136
    adc #$00                        ; $C137 carry is set by X_CLEOLZ, so this adds one
    cmp WNDBTM                      ; $C139
    bcc CLEOP1                      ; $C13B
    jsr VTAB                        ; $C13D
    jmp F_RETURN                    ; $C140

;; Function 1, 40 columns: moves the cursor to WNDTOP, column 0, and clears the window from there down.
;; Out: CV = WNDTOP, CH = 0
F_HOME:
    lda WNDTOP                      ; $C143
    sta CV                          ; $C145
    ldy #$00                        ; $C147
    sty CH                          ; $C149
    beq CLEOP1                      ; $C14B

;; Function 2, 40 columns: copies each window line up one line, from WNDTOP+1 to WNDBTM-1, then blanks the
;; bottom line. Reached only through F_TABLE; nothing branches here.
;; Uses: A, Y, BASL/BASH, BAS2L/BAS2H
F_SCROLL:
    lda WNDTOP                      ; $C14D
    pha                             ; $C14F
    jsr VTABZ                       ; $C150

SCRL1:
    lda BASL                        ; $C153
    sta BAS2L                       ; $C155
    lda BASH                        ; $C157
    sta BAS2H                       ; $C159
    ldy WNDWDTH                     ; $C15B
    dey                             ; $C15D
    pla                             ; $C15E
    adc #$01                        ; $C15F
    cmp WNDBTM                      ; $C161
    bcs SCRL3                       ; $C163
    pha                             ; $C165
    jsr VTABZ                       ; $C166

SCRL2:
    lda (BASL),y                    ; $C169
    sta (BAS2L),y                   ; $C16B
    dey                             ; $C16D
    bpl SCRL2                       ; $C16E
    bmi SCRL1                       ; $C170

SCRL3:
    ldy #$00                        ; $C172
    jsr X_CLEOLZ                    ; $C174
    jsr VTAB                        ; $C177
    jmp F_RETURN                    ; $C17A

;; Function 3, 40 columns: stores spaces ($A0) from CH to the window's right edge.
;; Uses: A, Y
;; The bytes at $C18A-$C19B (set a 40-wide window to line 23) are not reached by any code in this ROM.
F_CLREOL:
    ldy CH                          ; $C17D
    lda #' '                        ; $C17F

CLEOL2:
    sta (BASL),y                    ; $C181
    iny                             ; $C183
    cpy WNDWDTH                     ; $C184
    bcc CLEOL2                      ; $C186
    bcs F_GORET                     ; $C188

F_SETWND:
    lda #$28                        ; $C18A
    sta WNDWDTH                     ; $C18C
    lda #$18                        ; $C18E
    sta WNDBTM                      ; $C190
    lda #$17                        ; $C192
    sta CV                          ; $C194
    jsr VTAB                        ; $C196
    jmp F_RETURN                    ; $C199

;; Function 4 (CLREOLZ), 40 columns: clears from the column the Monitor saved in $1F to the end of the
;; line (X_CLEOLZ), then exits through F_GORET.
F_CLEOLZ:
    ldy $1F                         ; $C19C
    jsr X_CLEOLZ                    ; $C19E

;; Exit used by functions 3 and 4: jumps to F_RETURN.
F_GORET:
    jmp F_RETURN                    ; $C1A1

;; Dispatches functions 0-5 to their 80-column versions. Clears mode bit 0, then sets it if the Monitor's
;; caller had interrupts enabled (I clear in the first P on the stack). Copies CV to $05FB, computes the
;; base address, and if CH differs from the value the firmware last left in it ($047B), or 80 columns is
;; off, takes CH as the new 80-column cursor column ($057B). Then dispatches through B_TABLE via RTS.
;; Uses: A, Y, $0478 (scratch for the saved P)
B_FUNC0:
    pla                             ; $C1A4
    tay                             ; $C1A5
    lda MODE80                      ; $C1A6
    and #$FE                        ; $C1A9
    sta MODE80                      ; $C1AB
    pla                             ; $C1AE
    sta TEMP1                       ; $C1AF
    pla                             ; $C1B2
    pha                             ; $C1B3
    lsr a                           ; $C1B4
    lsr a                           ; $C1B5
    lsr a                           ; $C1B6
    lda TEMP1                       ; $C1B7
    pha                             ; $C1BA
    bcs NOI                         ; $C1BB
    lda MODE80                      ; $C1BD
    ora #$01                        ; $C1C0
    sta MODE80                      ; $C1C2

NOI:
    lda CV                          ; $C1C5
    sta OURCV                       ; $C1C7
    jmp B_VECTOR                    ; $C1CA

;; Function 2, 80 columns: scrolls the window up one line (SCROLLUP).
B_SCROLL:
    jsr SCROLLUP                    ; $C1CD
    jmp F_RETURN                    ; $C1D0

;; Function 3, 80 columns: clears from the 80-column cursor to the end of the line (X_GS).
B_CLREOL:
    jsr X_GS                        ; $C1D3
    jmp F_RETURN                    ; $C1D6

;; Function 4, 80 columns: clears from column $1F (Y saved there by the Monitor's CLREOLZ) to the end of the
;; line.
B_CLEOLZ:
    ldy $1F                         ; $C1D9
    jsr X_GSEOLZ                    ; $C1DB
    jmp F_RETURN                    ; $C1DE

;; Function 0, 80 columns: clears from the cursor to the end of the window (X_VT).
B_CLREOP:
    jsr X_VT                        ; $C1E1
    jmp F_RETURN                    ; $C1E4

;; Jumps to B_SETWNDX. Neither dispatch table nor any branch in this ROM refers to it.
B_SETWND:
    jmp B_SETWNDX                   ; $C1E7

;; Function 5 (the Monitor's RESET), reached through both dispatch tables: jumps to B_RESETX.
B_RESET:
    jmp B_RESETX                    ; $C1EA

;; Function 1, 80 columns: homes the cursor and clears the window (X_FF), then copies the new cursor
;; to CH, $047B and CV and recomputes the base address.
;; The label B_VECTOR ($C1FF) is the continuation of B_FUNC0.
B_HOME:
    jsr X_FF                        ; $C1ED
    lda OURCH                       ; $C1F0
    sta CH                          ; $C1F3
    sta OLDCH                       ; $C1F5
    lda OURCV                       ; $C1F8
    sta CV                          ; $C1FB
    bpl GOBACK                      ; $C1FD

B_VECTOR:
    jsr C8_BASCALC                  ; $C1FF
    lda CH                          ; $C202
    bit RD80VID                     ; $C204
    bpl B_GETCH                     ; $C207
    cmp OLDCH                       ; $C209
    beq B_FUNC1                     ; $C20C

B_GETCH:
    sta OURCH                       ; $C20E

B_FUNC1:
    lda #$C1                        ; $C211 the page of B_TABLE's functions
    pha                             ; $C213
    lda B_TABLE,y                   ; $C214
    pha                             ; $C217
    rts                             ; $C218

;; Sets the window to full width (80 if 80VID is on, else 40) and bottom 24, puts the cursor on line 23
;; ($05FB and CV), computes the base address and exits through F_RETURN. Only reached from $C1E7.
B_SETWNDX:
    lda #$50                        ; $C219
    bit RD80VID                     ; $C21B
    bmi B_SETWND2                   ; $C21E
    lsr a                           ; $C220

B_SETWND2:
    sta WNDWDTH                     ; $C221
    lda #$18                        ; $C223
    sta WNDBTM                      ; $C225
    lda #$17                        ; $C227
    sta OURCV                       ; $C229
    sta CV                          ; $C22C

GOBACK:
    jsr C8_BASCALC                  ; $C22E
    jmp F_RETURN                    ; $C231

;; Function 5, called by the Monitor's RESET. Marks the 80-column firmware inactive ($04FB = $FF) and turns
;; annunciators 2 and 3 on (<CLRAN2> and <CLRAN3>, despite their names). With Solid-Apple (BUTN1) held, runs
;; SELFTEST. With only Open-Apple (BUTN0) held, stores page numbers into two bytes of every page from $BF down
;; to $02 (offsets $B0 descending by two per page), so a program in memory will not survive the reset. Then
;; RESETRET.
;; Uses: A, Y, A1L/A1H
B_RESETX:
    lda #$FF                        ; $C234
    sta MODE80                      ; $C236
    lda CLRAN2                      ; $C239
    lda CLRAN3                      ; $C23C
    lda BUTN1                       ; $C23F
    bmi DIAGS                       ; $C242
    lda BUTN0                       ; $C244
    bpl RESETRET                    ; $C247
    ldy #$B0                        ; $C249
    lda #$00                        ; $C24B
    sta A1L                         ; $C24D
    lda #$BF                        ; $C24F
    sec                             ; $C251

BLAST:
    sta A1H                         ; $C252
    sta (A1L),y                     ; $C254
    dey                             ; $C256
    sta (A1L),y                     ; $C257
    sbc #$01                        ; $C259
    cmp #$01                        ; $C25B
    bne BLAST                       ; $C25D
    beq RESETRET                    ; $C25F

DIAGS:
    jmp SELFTEST                    ; $C261

;; End of the reset function: when no 80-column card answers (TESTCARD), selects slot 3's own ROM
;; (SETSLOTC3ROM). Exits through F_RETURN.
RESETRET:
    jsr TESTCARD                    ; $C264
    beq GORETN                      ; $C267
    sta SETSLOTC3ROM                ; $C269
    bne GORETN                      ; $C26C

;; Function 7, called by the Monitor after reading a key in escape mode: clears bit 5 (lowercase to
;; uppercase) and turns the arrow keys left, right, down and up ($88, $95, $8A, $8B) into J, K, M and I.
;; In: A = key.
;; Out: A = translated key.
;; Uses: Y
B_ESCFIX:
    and #$DF                        ; $C26E
    ldy #$03                        ; $C270

B_ESCFIX2:
    cmp ESCIN,y                     ; $C272
    bne B_ESCFIX3                   ; $C275
    lda ESCOUT,y                    ; $C277

B_ESCFIX3:
    dey                             ; $C27A
    bpl B_ESCFIX2                   ; $C27B

GORETN:
    jmp F_RETURN                    ; $C27D

;; Arrow-key codes looked up by B_ESCFIX: left, right, down, up.
ESCIN:
    .byte KEY_BS, KEY_RIGHT, KEY_LF, KEY_CTRL_K ; $C280

;; Letters B_ESCFIX substitutes for ESCIN's keys: J, K, M, I.
ESCOUT:
    .byte "JKMI"                    ; $C284

;; Function 6, the original Monitor's KEYIN: waits for a key while alternating the screen byte at CH between
;; $FF and the original character. If the caller had interrupts enabled, the wait loop calls the Monitor's
;; $FC75 so interrupts can be serviced (V set as the flag). Stirs RNDL/RNDH while waiting.
;; In: A = character under the cursor.
;; Out: A = key (bit 7 set); keyboard strobe cleared
;; Uses: Y, $0478 (saved character)
;; Keeps: X
B_KEYIN:
    sta TEMP1                       ; $C288
    pla                             ; $C28B
    tay                             ; $C28C
    pla                             ; $C28D
    pha                             ; $C28E
    ror a                           ; $C28F
    ror a                           ; $C290
    ror a                           ; $C291
    tya                             ; $C292
    pha                             ; $C293
    txa                             ; $C294
    pha                             ; $C295
    clv                             ; $C296
    bcs B_KEYIN2                    ; $C297
    bit SEV                         ; $C299 BIT SEV sets V

B_KEYIN2:
    lda #$FF                        ; $C29C
    ldy CH                          ; $C29E
    sta (BASL),y                    ; $C2A0
    jsr KEYDLY                      ; $C2A2
    bcs GOTKEY                      ; $C2A5
    lda TEMP1                       ; $C2A7
    ldy CH                          ; $C2AA
    sta (BASL),y                    ; $C2AC
    jsr KEYDLY                      ; $C2AE
    bcs GOTKEY                      ; $C2B1
    bcc B_KEYIN2                    ; $C2B3

GOTKEY:
    lda TEMP1                       ; $C2B5
    ldy CH                          ; $C2B8
    sta (BASL),y                    ; $C2BA
    pla                             ; $C2BC
    tax                             ; $C2BD
    lda KBD                         ; $C2BE
    sta KBDSTRB                     ; $C2C1
    bmi F_RETURN                    ; $C2C4

;; Subroutine of B_KEYIN: polls the keyboard for a fixed time ($0C00 loops with interrupt windows, $3100
;; without), stirring RNDL/RNDH.
;; In:    overflow = set to call $FC75 each loop
;; Out:   A = the last keyboard read: the key, with bit 7 set, when one is waiting,
;;          carry = set if a key is waiting, clear on timeout
;; Uses:  X, Y
KEYDLY:
    ldx #$0C                        ; $C2C6
    bvs IK1                         ; $C2C8
    ldx #$31                        ; $C2CA

IK1:
    ldy #$00                        ; $C2CC

IK2:
    bvc IK2A                        ; $C2CE
    php                             ; $C2D0
    jsr VIDSYNC                     ; $C2D1
    plp                             ; $C2D4

IK2A:
    inc RNDL                        ; $C2D5
    bne IK3                         ; $C2D7
    inc RNDH                        ; $C2D9

IK3:
    lda KBD                         ; $C2DB
    bmi KDRETY                      ; $C2DE
    dey                             ; $C2E0
    bne IK2                         ; $C2E1
    dex                             ; $C2E3
    bne IK1                         ; $C2E4

KDRETN:
    clc                             ; $C2E6
    bcc KDRET                       ; $C2E7

KDRETY:
    sec                             ; $C2E9

KDRET:
    rts                             ; $C2EA

;; Common exit for the $C100 functions: pulls the second P and, if internal $CX ROM was not in on entry,
;; jumps to the Monitor's $FD29 (SETSLOTCXROM, PLP, RTS); otherwise to $FD2C (PLP, RTS).
F_RETURN:
    plp                             ; $C2EB
    bmi F_RET1                      ; $C2EC
    jmp SLOTRTN                     ; $C2EE

;; Exit when internal ROM was already in: jumps to $FD2C, which restores P and returns.
F_RET1:
    jmp SLOTRTN + 3                 ; $C2F1 past SLOTRTN's SETSLOTCXROM: PLP and RTS

;; Stores spaces ($A0) at (BASL),Y from Y up to WNDWDTH-1.
;; In: Y = first column.
;; Out: Y = WNDWDTH, carry set.
;; Uses: A
X_CLEOLZ:
    lda #' '                        ; $C2F4

X_CLEOL2:
    sta (BASL),y                    ; $C2F6
    iny                             ; $C2F8
    cpy WNDWDTH                     ; $C2F9
    bcc X_CLEOL2                    ; $C2FB
    rts                             ; $C2FD
    .byte $00, $00                  ; $C2FE
