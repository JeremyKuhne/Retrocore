;; Entry from the Monitor's $FBB4 (P with the old RDCXROM state is on the stack, Y = function number).
;; In: Y = function number (see CXDISPATCH)
B_FUNC:
    jmp CXDISPATCH                  ; $C100

;; 40-column clear to end of window: clears from CH on the cursor line, then every following line
;; through WNDBTM-1, and recomputes BASL for CV. Function $0A when the 80-column firmware is inactive.
;; $C119 is 40-column HOME (function 5): CV = WNDTOP, CH = 0, then the same clearing loop.
;; $C123 is 40-column SCROLL (function 6): copies each window line up one, clears the bottom line.
;; In: CH, CV, WNDTOP, WNDBTM, WNDWDTH
;; Uses: BASL/BASH, BAS2L/BAS2H (scroll), A, Y
CLREOP40:
    ldy CH                          ; $C103
    lda CV                          ; $C105

CLREOP40_1:
    pha                             ; $C107
    jsr VTAB80_1                    ; $C108
    jsr CLRLINE40                   ; $C10B
    ldy #$00                        ; $C10E
    pla                             ; $C110
    adc #$00                        ; $C111
    cmp WNDBTM                      ; $C113
    bcc CLREOP40_1                  ; $C115
    bcs CLREOP40_2                  ; $C117

HOME40:
    lda WNDTOP                      ; $C119 HOME40 entry (function 5)
    sta CV                          ; $C11B
    ldy #$00                        ; $C11D
    sty CH                          ; $C11F
    beq CLREOP40_1                  ; $C121

SCROLL40:
    lda WNDTOP                      ; $C123 SCROLL40 entry (function 6)
    pha                             ; $C125
    jsr VTAB80_1                    ; $C126

SCROLL40_1:
    lda BASL                        ; $C129
    sta BAS2L                       ; $C12B
    lda BASH                        ; $C12D
    sta BAS2H                       ; $C12F
    ldy WNDWDTH                     ; $C131
    dey                             ; $C133
    pla                             ; $C134
    adc #$01                        ; $C135
    cmp WNDBTM                      ; $C137
    bcs SCROLL40_3                  ; $C139
    pha                             ; $C13B
    jsr VTAB80_1                    ; $C13C

SCROLL40_2:
    lda (BASL),y                    ; $C13F
    sta (BAS2L),y                   ; $C141
    dey                             ; $C143
    bpl SCROLL40_2                  ; $C144
    bmi SCROLL40_1                  ; $C146

SCROLL40_3:
    ldy #$00                        ; $C148
    jsr CLRLINE40                   ; $C14A

CLREOP40_2:
    lda CV                          ; $C14D

CLREOP40_3:
    jmp VTAB80_1                    ; $C14F

;; Finishes the Monitor's SETWND (function $0C): WNDWDTH = 40, WNDBTM = 24, CV = 23, then BASL/BASH for
;; row 23 (via VTAB80's base calculation, which adds WNDLFT).
;; $C160 is 40-column CLREOLZ (function 8): Y = BAS2L, then clears to the end of the line.
;; Out: WNDWDTH, WNDBTM, CV, BASL/BASH
SETWNDREST:
    lda #$28                        ; $C152
    sta WNDWDTH                     ; $C154
    lda #$18                        ; $C156
    sta WNDBTM                      ; $C158
    lda #$17                        ; $C15A
    sta CV                          ; $C15C
    bne CLREOP40_3                  ; $C15E

CLREOLZ40:
    ldy BAS2L                       ; $C160 CLREOLZ40 entry (function 8): Y from BAS2L
    jmp CLRLINE40                   ; $C162

;; Function 6 (SCROLL) with the 80-column firmware active: jumps into SCROLL80's scroll-up entry.
CXSCROLL80:
    jmp SCROLLUP80                  ; $C165

;; Function 7 (CLREOL) with the 80-column firmware active: clears from column $057B to the line end.
CXCLREOL80:
    jmp CLREOL80                    ; $C168

;; Function 8 (CLREOLZ) with the 80-column firmware active: clears from column BAS2L to the line end.
CXCLREOLZ80:
    ldy BAS2L                       ; $C16B
    jmp CLRLINE80_2                 ; $C16D

;; Function $0A (CLREOP) with the 80-column firmware active: jumps to CLREOP80.
CXCLREOP80:
    jmp CLREOP80                    ; $C170

;; Function $0C (SETWND) with the 80-column firmware active: jumps to SETWND80, which runs SETWNDREST,
;; doubles WNDWDTH when 80VID is on, and copies CV to $05FB.
CXSETWND80:
    jmp SETWND80                    ; $C173

;; Function 9 (reset) in both modes: jumps to RESETFW. The routines after it, to $C1B5, are reached
;; through the dispatcher's table, CXFUNCTBL.
CXRESET:
    jmp RESETFW                     ; $C176

;; Function $0B (RDKEY) with the 80-column firmware active: jumps to RDKEY80.
CXRDKEY80:
    jmp RDKEY80                     ; $C179

;; Function 5 (HOME), 80 columns: clears the screen (CLRSCRN80), then sets CH and $047B to the
;; 80-column cursor column ($057B) and recomputes the base address (VTAB80).
CXHOME80:
    jsr CLRSCRN80                   ; $C17C
    lda OURCH                       ; $C17F
    sta CH                          ; $C182
    sta OLDCH                       ; $C184
    jmp VTAB80                      ; $C187

;; Function $0E, 80 columns, after OUTPORT or INPORT set a hook at (LOC0,X): a hook low byte of $00 (a
;; slot) is left alone; KEYIN's low byte keeps KSW at $C305 while CSWH is $C3 (CXPORTC3); otherwise
;; OFF80 runs and the high byte becomes $FD.
;; $C195 (CXPORT40) is function $0E with the firmware inactive: a non-slot hook gets high byte $FD.
;; Out: A = LOC1,X
CXPORT80:
    ldy LOC0,x                      ; $C18A
    beq CXPORT40_2                  ; $C18C
    cpy #<KEYIN                     ; $C18E
    beq CXPORTC3                    ; $C190
    jsr OFF80                       ; $C192

CXPORT40:
    ldy LOC0,x                      ; $C195
    beq CXPORT40_2                  ; $C197

CXPORT40_1:
    lda #>KEYIN                     ; $C199 the Monitor's I/O page
    sta LOC1,x                      ; $C19B

CXPORT40_2:
    lda LOC1,x                      ; $C19D
    rts                             ; $C19F

;; Function $0E with KSW at KEYIN: while output goes to slot 3 (CSWH = $C3), KSW goes back to BASICIN
;; (SETC3HOOKS_1); otherwise the hook gets high byte $FD.
CXPORTC3:
    lda CSWH                        ; $C1A0
    cmp #>BASICOUT                  ; $C1A2
    bne CXPORT40_1                  ; $C1A4
    jmp SETC3HOOKS_1                ; $C1A6

;; Function $0B (RDKEY), 40 columns: replaces the character at (BASL),CH with its flashing form (and
;; #$3F, ora #$40) to show the cursor.
;; Out: A = the original character
RDKEY40:
    ldy CH                          ; $C1A9
    lda (BASL),y                    ; $C1AB
    pha                             ; $C1AD
    and #$3F                        ; $C1AE
    ora #$40                        ; $C1B0
    sta (BASL),y                    ; $C1B2
    pla                             ; $C1B4
    rts                             ; $C1B5

;; Function 2: A holds the caller's Y and BASL a row; computes the row's base address with ROWBASE (no
;; window offset). ROWBASE always returns carry clear, so this always exits through CXEXIT.
;; $C1BE is function 1 (from the Monitor's escape-key reader): upshifts A, then maps the arrow keys
;; (left, right, down, up, from ARROWKEYS) to J, K, M, I (from ARROWLETTERS).
;; $C1D0 is function 0 (80-column character output from the Monitor's COUT1): calls CHARIO80.
;; In: A = key (function 1) or the caller's Y (function 2)
;; Out: A = translated key (function 1)
CXBASCALC:
    tay                             ; $C1B6
    lda BASL                        ; $C1B7
    jsr ROWBASE                     ; $C1B9
    bcc CXEXIT                      ; $C1BC

CXESCKEY:
    jsr UPSHIFT                     ; $C1BE function 1 entry: upshift and map arrows
    ldy #ARROWS - 1                 ; $C1C1

CXESCKEY_1:
    cmp ARROWKEYS,y                 ; $C1C3
    bne CXESCKEY_2                  ; $C1C6
    lda ARROWLETTERS,y              ; $C1C8

CXESCKEY_2:
    dey                             ; $C1CB
    bpl CXESCKEY_1                  ; $C1CC
    bmi CXEXIT                      ; $C1CE

CXCOUT80:
    jsr CHARIO80                    ; $C1D0 function 0 entry: 80-column output
    jmp CXEXIT                      ; $C1D3

;; Function $10 (from the Monitor's INSDS2): LENGTH = X and 3, then computes the mnemonic index from
;; the opcode in BAS2L (anded with $8F) through MNEMINDEX.
;; In: X = disassembler format byte, BAS2L = opcode
;; Out: A = mnemonic index, LENGTH set
CXINSDS2:
    txa                             ; $C1D6
    and #$03                        ; $C1D7
    sta LENGTH                      ; $C1D9
    lda BAS2L                       ; $C1DB
    and #$8F                        ; $C1DD
    jmp MNEMINDEX                   ; $C1DF

;; Function $0D (from the Monitor's mini-assembler command): calls the Monitor's $FCF0, which prompts
;; with "!", reads a line and runs MINILINE; on return stores X in YSAV.
CXMINIASM:
    jsr $FCF0                       ; $C1E2
    txa                             ; $C1E5
    sta YSAV                        ; $C1E6
    rts                             ; $C1E8

;; Function $0F (from GETLN when the right arrow, ctrl-U, is typed): returns the character under the
;; 80-column cursor column $057B with bit 7 set.
;; In: BASL/BASH, $057B
;; Out: A = screen character | $80
CXSCRNCHAR:
    ldy OURCH                       ; $C1E9
    jsr GETSCRCHAR                  ; $C1EC
    ora #$80                        ; $C1EF
    rts                             ; $C1F1

;; Function 7 (CLREOL), 40 columns: clears from CH to the end of the line.
CLREOL40:
    ldy CH                          ; $C1F2

;; Clears from column Y to WNDWDTH-1 of (BASL) with a blank: a space, or $20 (inverse space) when the
;; alternate character set is on and INVFLG bit 7 is clear.
;; In: Y = first column, BASL/BASH
;; Out:   carry = set
CLRLINE40:
    lda #' '                        ; $C1F4
    bit RDALTCHAR                   ; $C1F6
    bpl CLRLINE40_1                 ; $C1F9
    bit INVFLG                      ; $C1FB
    bmi CLRLINE40_1                 ; $C1FD
    lda #$20                        ; $C1FF inverse space

CLRLINE40_1:
    jmp CLRLINE80_3                 ; $C201

;; Function 4 (from the Monitor's VTABZ): A holds the caller's Y and BASL the row; computes BASL/BASH
;; with VTAB80's base calculation (adds WNDLFT, halved when 80VID is on).
;; CXEXIT ($C20A) is the common exit: pulls the flags the Monitor's $FBB4 pushed and returns through $FEC8 if
;; internal $CX ROM was already on, or $FEC5 (SETSLOTCXROM) otherwise.
CXVTABZ:
    tay                             ; $C204
    lda BASL                        ; $C205
    jsr VTAB80_1                    ; $C207

CXEXIT:
    plp                             ; $C20A common exit (functions 5 and up return here)
    bmi CXEXITINT                   ; $C20B
    jmp SLOTRTS                     ; $C20D

;; Exit when internal $CX ROM was on before: jumps to the Monitor's $FEC8 (rts).
CXEXITINT:
    jmp $FEC8                       ; $C210

;; Dispatches a Monitor function number in Y. 0-4 go to fixed handlers: 0 80-column output, 1 escape
;; key translation, 2 base address, 3 KEYIN, 4 VTABZ. For 5 and up it pushes CXEXIT-1 (so the handler
;; returns to CXEXIT) and picks a handler from CXFUNCTBL: the first twelve entries are used when
;; $04FB and $D6 is nonzero (80-column firmware not active), otherwise twelve is added and SYNCCH and
;; VTAB80 run first. Handlers live in page $C1 (the table holds address-1 low bytes).
;; Functions: 5 HOME, 6 SCROLL, 7 CLREOL, 8 CLREOLZ, 9 reset, $0A CLREOP, $0B RDKEY, $0C SETWND,
;; $0D mini-assembler line, $0E OUTPORT/INPORT fixup, $0F character under cursor, $10 INSDS2.
;; In: Y = function number; registers as the Monitor routine left them
;; Uses: $04FB
CXDISPATCH:
    dey                             ; $C213
    bmi CXCOUT80                    ; $C214
    dey                             ; $C216
    bmi CXESCKEY                    ; $C217
    dey                             ; $C219
    bmi CXBASCALC                   ; $C21A
    dey                             ; $C21C
    bmi CXKEYIN                     ; $C21D
    dey                             ; $C21F
    bmi CXVTABZ                     ; $C220
    lda #>(CXEXIT - 1)              ; $C222
    pha                             ; $C224
    lda #<(CXEXIT - 1)              ; $C225
    pha                             ; $C227
    lda MODE80                      ; $C228
    and #$D6                        ; $C22B
    bne CXDISPATCH_1                ; $C22D
    tya                             ; $C22F
    clc                             ; $C230
    adc #CXFUNCS                    ; $C231
    pha                             ; $C233
    jsr SYNCCH                      ; $C234
    jsr VTAB80                      ; $C237
    pla                             ; $C23A
    tay                             ; $C23B

CXDISPATCH_1:
    lda #CXFUNC_PAGE                ; $C23C
    pha                             ; $C23E
    lda CXFUNCTBL,y                 ; $C23F
    pha                             ; $C242
    rts                             ; $C243

;; Low bytes (address-1, page $C1) of the function 5-$10 handlers: twelve for the 40-column/inactive
;; case followed by twelve for the active 80-column firmware. See CXDISPATCH.
CXFUNC_PAGE = $C1

.macro CXFUNC handler
    .assert >(handler - 1) = CXFUNC_PAGE, "A function handler must follow the first byte of page $C1."
    .byte <(handler - 1)
.endmacro

CXFUNCTBL:
    CXFUNC HOME40                   ; $C244 5 HOME
    CXFUNC SCROLL40                 ; $C245 6 SCROLL
    CXFUNC CLREOL40                 ; $C246 7 CLREOL
    CXFUNC CLREOLZ40                ; $C247 8 CLREOLZ
    CXFUNC CXRESET                  ; $C248 9 reset
    CXFUNC CLREOP40                 ; $C249 $0A CLREOP
    CXFUNC RDKEY40                  ; $C24A $0B RDKEY
    CXFUNC SETWNDREST               ; $C24B $0C SETWND
    CXFUNC CXMINIASM                ; $C24C $0D mini-assembler line
    CXFUNC CXPORT40                 ; $C24D $0E OUTPORT/INPORT fixup
    CXFUNC CXSCRNCHAR               ; $C24E $0F character under cursor
    CXFUNC CXINSDS2                 ; $C24F $10 INSDS2
CXFUNCS = * - CXFUNCTBL
    CXFUNC CXHOME80                 ; $C250 5 HOME, 80-column firmware active
    CXFUNC CXSCROLL80               ; $C251 6 SCROLL
    CXFUNC CXCLREOL80               ; $C252 7 CLREOL
    CXFUNC CXCLREOLZ80              ; $C253 8 CLREOLZ
    CXFUNC CXRESET                  ; $C254 9 reset
    CXFUNC CXCLREOP80               ; $C255 $0A CLREOP
    CXFUNC CXRDKEY80                ; $C256 $0B RDKEY
    CXFUNC CXSETWND80               ; $C257 $0C SETWND
    CXFUNC CXMINIASM                ; $C258 $0D mini-assembler line
    CXFUNC CXPORT80                 ; $C259 $0E OUTPORT/INPORT fixup
    CXFUNC CXSCRNCHAR               ; $C25A $0F character under cursor
    CXFUNC CXINSDS2                 ; $C25B $10 INSDS2
.assert * - CXFUNCTBL = 2 * CXFUNCS, "Both halves of CXFUNCTBL need the same functions."

;; Function 3 (the Monitor's KEYIN): with 80VID on, reads a key through CHARIO80's input entry;
;; otherwise falls into KEYIN40.
;; In: A = the character under the cursor (from RDKEY)
;; Out: A = key
CXKEYIN:
    bit RD80VID                     ; $C25C
    bpl KEYIN40                     ; $C25F
    jsr CHARIO80_1                  ; $C261

CXKEYIN_1:
    jmp CXEXIT                      ; $C264

;; 40-column key wait with a blinking cursor: alternately stores $FF and the entry character at
;; (BASL),CH, switching each time bit 6 of RNDH changes while RNDL/RNDH count up. On a key it puts
;; the original character back, clears the keyboard strobe and exits through CXEXIT.
;; SETWND80 ($C2A0) at the end is a separate routine: the 80-column SETWND finish.
;; In: A = character under the cursor, BASL/BASH, CH
;; Out: A = key; X preserved
;; Uses: RNDL/RNDH
KEYIN40:
    tay                             ; $C267
    txa                             ; $C268
    pha                             ; $C269
    tya                             ; $C26A
    pha                             ; $C26B
    pha                             ; $C26C

KEYIN40_1:
    pla                             ; $C26D
    cmp #$FF                        ; $C26E
    beq KEYIN40_2                   ; $C270
    lda #$FF                        ; $C272
    bne KEYIN40_3                   ; $C274

KEYIN40_2:
    pla                             ; $C276
    pha                             ; $C277

KEYIN40_3:
    pha                             ; $C278
    ldy CH                          ; $C279
    sta (BASL),y                    ; $C27B

KEYIN40_4:
    inc RNDL                        ; $C27D
    bne KEYIN40_5                   ; $C27F
    lda RNDH                        ; $C281
    inc RNDH                        ; $C283
    eor RNDH                        ; $C285
    and #$40                        ; $C287
    bne KEYIN40_1                   ; $C289

KEYIN40_5:
    lda KBD                         ; $C28B
    bpl KEYIN40_4                   ; $C28E
    pla                             ; $C290
    pla                             ; $C291
    ldy CH                          ; $C292
    sta (BASL),y                    ; $C294
    pla                             ; $C296
    tax                             ; $C297
    lda KBD                         ; $C298
    sta KBDSTRB                     ; $C29B
    bmi CXKEYIN_1                   ; $C29E

SETWND80:
    jsr SETWNDREST                  ; $C2A0 SETWND finish for function $0C (80-column)
    bit RD80VID                     ; $C2A3
    bpl SETWND80_1                  ; $C2A6
    asl WNDWDTH                     ; $C2A8

SETWND80_1:
    lda CV                          ; $C2AA
    sta OURCV                       ; $C2AC
    rts                             ; $C2AF

;; Function 9 (from the Monitor's RESET): $04FB = $FF (80-column firmware inactive), CLRAN2, CLRAN3.
;; If BUTN1 (solid apple) is down it runs SELFTEST. If BUTN0 (open apple) is down it first writes
;; $A0 into two bytes of every page from $BF down to $02 (the offset moving down one per page),
;; which appears meant to spoil memory so a warm restart is not taken. Then it selects slot 3's ROM,
;; and switches to the internal $C3 ROM when SLOT3CHECK returns Z.
;; Uses: A1L/A1H, $04FB
RESETFW:
    lda #$FF                        ; $C2B0
    sta MODE80                      ; $C2B2
    lda CLRAN2                      ; $C2B5
    lda CLRAN3                      ; $C2B8
    lda BUTN1                       ; $C2BB
    bpl RESETFW_1                   ; $C2BE
    jmp SELFTEST                    ; $C2C0

;; Open-apple memory scramble and the $C3 ROM choice (see RESETFW).
RESETFW_1:
    lda BUTN0                       ; $C2C3
    bpl RESETFW_3                   ; $C2C6
    ldy #$B0                        ; $C2C8
    lda #$00                        ; $C2CA
    sta A1L                         ; $C2CC
    lda #$BF                        ; $C2CE
    sec                             ; $C2D0

RESETFW_2:
    sta A1H                         ; $C2D1
    pha                             ; $C2D3
    lda #$A0                        ; $C2D4
    sta (A1L),y                     ; $C2D6
    dey                             ; $C2D8
    sta (A1L),y                     ; $C2D9
    pla                             ; $C2DB
    sbc #$01                        ; $C2DC
    cmp #$01                        ; $C2DE
    bne RESETFW_2                   ; $C2E0

RESETFW_3:
    sta SETSLOTC3ROM                ; $C2E2
    jsr SLOT3CHECK                  ; $C2E5
    bne RESETFW_4                   ; $C2E8
    sta SETINTC3ROM                 ; $C2EA

RESETFW_4:
    rts                             ; $C2ED

;; Arrow key codes (left, right, down, up) matched by function 1; their replacements are in
;; ARROWLETTERS.
ARROWKEYS:
    .byte KEY_BS, KEY_RIGHT, KEY_LF, KEY_CTRL_K ; $C2EE
ARROWS = * - ARROWKEYS

; Function $0B (RDKEY), 80 columns: reads the character at (BASL),CH; returns it if 80VID is on,
; otherwise inverts the character at $057B (FLIPCURSOR_1).

RDKEY80:
    ldy CH                          ; $C2F2
    lda (BASL),y                    ; $C2F4
    bit RD80VID                     ; $C2F6
    bmi RESETFW_4                   ; $C2F9
    jmp FLIPCURSOR_1                ; $C2FB
    .byte $00, $00                  ; $C2FE
