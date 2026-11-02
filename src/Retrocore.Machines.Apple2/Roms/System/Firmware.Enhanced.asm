;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ENHANCED IIE
;;
;; How the Enhanced IIe uses its internal $C100-$CFFF ROM, as far as the code shows:
;;   $C100-$C2FF  Monitor extensions. The Monitor's $FBB4 saves RDCXROM in the pushed flags, sets SETINTCXROM
;;                and jumps to $C100 with a function number in Y (see CXDISPATCH); the exit returns through
;;                the Monitor's $FEC5 (back to slot ROM) or $FEC8. Also the reset hook (RESETFW).
;;   $C300-$C3FF  Slot 3: BASICINT/BASICIN/BASICOUT for PR#3/IN#3, the Pascal 1.1 ID bytes and PASCALOFS
;;                ($C34A init, $C350 read, $C356 write, $C35C status), AUXMOVE, XFER, and the IRQ/BRK entry
;;                at $C3FA that the Monitor's IRQ vector code jumps to; it runs on into $C400.
;;   $C400-$C4FF  Interrupt bank-state save/restore and the mini-assembler's operand parser.
;;   $C500-$C5FF  The cassette routines behind the Monitor's HEADR, WRITE and READ, and the AppleSoft
;;                SHLOAD/STORE/RECALL helper at $C500 (called from AppleSoft's $F777).
;;   $C600-$C7FF  Self-test, run when the solid-apple key (BUTN1) is down at reset.
;;   $C800-$CFFF  80-column firmware: output, input with escape sequences, Pascal support, 40/80 screen
;;                conversion, and the rest of the mini-assembler ($CF3A-$CFFE). $C800, $C84D and $C9AA
;;                hold jumps to Pascal init/read/write code (apparently older Pascal entry points).
;; The 80-column state lives in text screen holes: $04FB mode bits, $057B cursor column, $05FB cursor row,
;; $047B the CH the firmware last set, $067B the current character, $06FB/$077B/$07FB scratch.
;; Several routines are reached only through computed RTS addresses (the dispatcher's CXFUNCTBL).
;;
;; Assembles byte-identically to the internal $C100-$CFFF ROM: the 80-column firmware in slot three's
;; space and $C800, and the routines the Monitor calls with internal ROM switched in. Names are Apple's
;; documented entry points; other labels are named after the routine they are in.
;; It includes IIeEquates.asm (the IIe's page zero, soft switches and keys), MonitorEntries.asm (the Monitor's
;; entry points) and FirmwareEquates.asm (the equates both firmware models share).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Rockwell65C02

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; AppleSoft's page zero, for the cassette and SHLOAD/STORE/RECALL helpers.
;; Applesoft's line number, which the cassette helper borrows for a length: of a shape table, or of an array.
;;
;; <BASTAPE> reads a shape table's two-byte length from the tape into <LINNUM>/<LINNUM>+1 for SHLOAD, and
;; <TAPEARRAY> adds an array's length, which Applesoft leaves here, to its address for STORE and RECALL.
;; See: <AppleSoft:LINNUM>, <BASTAPE>, <TAPEARRAY>
LINNUM = $50

;; Applesoft's end of the variables and arrays, the lowest address strings may grow down to.
;;
;; <BASTAPE> refuses a shape table that would reach below it, returning carry set so that Applesoft reports
;; that memory is full.
;; See: <AppleSoft:STREND>, <BASTAPE>, <MEMSIZ>
STREND = $6D

;; Applesoft's bottom of string space, where the next string is stored, just below the strings in use.
;;
;; <TAPESHLOAD> moves it down with HIMEM, <MEMSIZ>, to make room for the shape table it loads.
;; See: <AppleSoft:FRETOP>, <MEMSIZ>, <TAPESHLOAD>
FRETOP = $6F

;; Applesoft's HIMEM, the address just above the memory it uses.
;;
;; <BASTAPE> checks that a shape table fits below it, and <TAPESHLOAD> lowers it by the table's length and
;; loads the table there.
;; See: <AppleSoft:MEMSIZ>, <FRETOP>, <SHAPEPTR>, <TAPESHLOAD>
MEMSIZ = $73

;; Applesoft's block pointer, which the STORE and RECALL helper takes as the start of the array's data.
;;
;; <TAPEARRAY> copies it, as Applesoft's routine at $E0EF leaves it, to <A1L>/<A1H>, the start of the block the
;; Monitor then writes or reads.
;; See: <AppleSoft:HIGHDS>, <TAPEARRAY>, <LOWTR>
HIGHDS = $94

;; Applesoft's pointer to the array that STORE or RECALL names, from its search for the array.
;;
;; <TAPEARRAY> adds the array's length in <LINNUM> to it for <A2L>/<A2H>, the end of the block on tape, and
;; reads the header's fifth byte through it.
;; See: <AppleSoft:LOWTR>, <TAPEARRAY>, <HIGHDS>
LOWTR = $9B

;; Applesoft's pointer to the shape table that DRAW and XDRAW use.
;;
;; <TAPESHLOAD> sets it to the address where it loads the shape table, just below the new HIMEM.
;; See: <AppleSoft:SHPTBL>, <TAPESHLOAD>, <MEMSIZ>
SHAPEPTR = $E8

; A Monitor entry point not in MonitorEntries.asm, since DOS has a routine of its own by the name.
;; Inherit: <Monitor:GETNUM>
GETNUM = $FFA7

; Control codes with bit 7 clear, as DOCTRL and the Pascal entries take them.
CTRL_D = $04                        ;; Control-D: ESC Control-D disables control characters ($04FB bit 5)
CTRL_E = $05                        ;; Control-E: Pascal shows the cursor; ESC Control-E enables control characters
CTRL_F = $06                        ;; Control-F: Pascal hides the cursor
CTRL_G = $07                        ;; Control-G: bell
CTRL_H = $08                        ;; Control-H: cursor left (backspace)
CTRL_J = $0A                        ;; Control-J: cursor down (line feed)
CTRL_K = $0B                        ;; Control-K: clear to the end of the screen
CTRL_L = $0C                        ;; Control-L: clear the screen
CTRL_M = $0D                        ;; Control-M: return
CTRL_N = $0E                        ;; Control-N: normal text
CTRL_O = $0F                        ;; Control-O: inverse text
CTRL_Q = $11                        ;; Control-Q: 40 columns; ESC Control-Q quits the 80-column firmware
CTRL_R = $12                        ;; Control-R: 80 columns
CTRL_U = $15                        ;; Control-U: quit the 80-column firmware
CTRL_V = $16                        ;; Control-V: scroll down
CTRL_W = $17                        ;; Control-W: scroll up
CTRL_X = $18                        ;; Control-X: MouseText off
CTRL_Y = $19                        ;; Control-Y: home the cursor
CTRL_Z = $1A                        ;; Control-Z: clear the line
CTRL_ESC = $1B                      ;; Escape as a control code: MouseText on
CTRL_BACKSLASH = $1C                ;; Control-\: cursor right
CTRL_RBRACKET = $1D                 ;; Control-]: clear to the end of the line
CTRL_CARET = $1E                    ;; Pascal GOTOXY
CTRL_UNDERSCORE = $1F               ;; Control-_: cursor up

.org $C100

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

;; PR#3 entry (also the first output call after PR#3). The bit of an rts opcode sets V, which selects
;; initialization in C3ENTRY. The sec at $C305 and clc at $C307 double as the bytes the Monitor's $F8B7
;; compares to recognize this kind of slot 3 firmware.
BASICINT:
    bit PUTINV_2                    ; $C300 the bit of an rts opcode ($60) sets V
    bvs C3ENTRY                     ; $C303

;; IN#3 input hook: carry set, V clear.
BASICIN:
    sec                             ; $C305
    .byte $90                       ; $C306 bcc: skips the next byte

;; Output hook: carry clear, V clear.
BASICOUT:
    clc                             ; $C307
    clv                             ; $C308
    bvc C3ENTRY                     ; $C309

;; Pascal 1.1 protocol ID bytes: $01 and $88.
PASCALID:
    .byte $01, $88                  ; $C30B

;; Pascal 1.1 entry offsets in page $C3: init, read, write, status.
PASCALOFS:
    .byte <PASINIT, <PASREAD, <PASWRITE, <PASSTATUS ; $C30D

;; Moves memory between main and auxiliary RAM (see DOAUXMOVE).
;; In:  A1 = source start, A2 = source end, A4 = destination, carry = set for main to aux, clear for aux to main
AUXMOVE:
    jmp DOAUXMOVE                   ; $C311

;; Transfers control to the address in $03ED/$03EE in main or auxiliary memory (see DOXFER).
;; In:  carry = set for aux RAM, clear for main; overflow = set for aux zero page and stack, clear for main
XFER:
    jmp DOXFER                      ; $C314

;; Common slot 3 entry: saves A in $067B, pushes Y and X, then sets MSLOT = $C3 (reading $CFFF to
;; release other cards' $C800 ROM). If MSLOT bit 7 was clear on entry (the Monitor's RDCHAR does lsr
;; MSLOT before reading), sets $04FB bit 3 so escape sequences are processed. V set: initialize
;; (C3INIT). Carry clear: output (CHARIO80). Carry set: input (CHARIO80) when $04FB bit 7 is clear;
;; otherwise sets KSW to the Monitor's KEYIN and continues through it.
;; $04FB bits as the code uses them: 0 MouseText translation off; 1 set by the $C800 Pascal entry;
;; 2 Pascal inverse; 3 escapes allowed (BASIC) or GOTOXY pending (Pascal); 4 Pascal cursor off;
;; 5 control characters disabled; 7 Pascal mode, or not initialized ($FF).
;; In: A = character, carry and V as set by BASICINT/BASICIN/BASICOUT
;; Uses: $04FB, $067B, MSLOT, KSWL/KSWH
C3ENTRY:
    sta CHAR                        ; $C317
    tya                             ; $C31A
    pha                             ; $C31B
    txa                             ; $C31C
    pha                             ; $C31D
    php                             ; $C31E
    lda MODE80                      ; $C31F
    bit MSLOT                       ; $C322
    bmi C3ENTRY_1                   ; $C325
    ora #$08                        ; $C327
    sta MODE80                      ; $C329

C3ENTRY_1:
    jsr SETMSLOT3                   ; $C32C
    plp                             ; $C32F
    bvs C3GOINIT                    ; $C330
    bcc C3CHARIO                    ; $C332
    tax                             ; $C334
    bpl C3CHARIO                    ; $C335
    jsr QUIT80_1                    ; $C337
    pla                             ; $C33A
    tax                             ; $C33B
    pla                             ; $C33C
    tay                             ; $C33D
    lda CHAR                        ; $C33E
    jmp (KSWL)                      ; $C341

;; Jumps into CHARIO80 at its carry test (input or output).
C3CHARIO:
    jmp CHARIO80_2                  ; $C344

;; Jumps to C3INIT.
C3GOINIT:
    jmp C3INIT                      ; $C347

;; Pascal init: sets MSLOT, then C9PASINIT_1 with mode $81.
;; Out: X = 0 (or 9 when there is no auxiliary text memory)
PASINIT:
    jsr SETMSLOT3                   ; $C34A
    jmp C9PASINIT_1                 ; $C34D

;; Pascal read: sets MSLOT, then PASGETKEY.
;; Out: A = character, X = result
PASREAD:
    jsr SETMSLOT3                   ; $C350
    jmp PASGETKEY                   ; $C353

;; Pascal write: sets MSLOT, then PASPUTCHAR.
;; In: A = character
PASWRITE:
    jsr SETMSLOT3                   ; $C356
    jmp PASPUTCHAR                  ; $C359

;; Pascal status request.
;; In: A = request: 0 always answers ready; 1 answers ready when a key is waiting
;; Out:   X = 0, or 3 (with carry clear) for any other request, carry = set when ready, clear when not
PASSTATUS:
    tax                             ; $C35C
    beq PASSTATUS_1                 ; $C35D
    dex                             ; $C35F
    bne PASSTATUS_2                 ; $C360
    bit KBD                         ; $C362
    bpl PASSTATUS_3                 ; $C365

PASSTATUS_1:
    sec                             ; $C367
    rts                             ; $C368

;; Status for an unknown request: X = 3, carry clear.
PASSTATUS_2:
    ldx #$03                        ; $C369

PASSTATUS_3:
    clc                             ; $C36B
    rts                             ; $C36C

;; MSLOT = $C3, and reads $CFFF (CLRROM) to release any slot's $C800 expansion ROM.
;; Out: X = $DF (the byte read)
SETMSLOT3:
    ldx #$C3                        ; $C36D
    stx MSLOT                       ; $C36F
    ldx CLRROM                      ; $C372
    rts                             ; $C375

;; AUXMOVE: copies A1..A2 (inclusive) to A4. Carry set: reads main, writes aux; clear: reads aux,
;; writes main. The previous RAMRD/RAMWRT states are saved and restored.
;; In: A1L/A1H, A2L/A2H, A4L/A4H, carry
;; Out: A1 = A2+1, A4 advanced; A and Y preserved
DOAUXMOVE:
    pha                             ; $C376
    tya                             ; $C377
    pha                             ; $C378
    lda RDRAMRD                     ; $C379
    pha                             ; $C37C
    lda RDRAMWRT                    ; $C37D
    pha                             ; $C380
    bcc DOAUXMOVE_1                 ; $C381
    sta RDMAINRAM                   ; $C383
    sta WRCARDRAM                   ; $C386
    bcs DOAUXMOVE_2                 ; $C389

DOAUXMOVE_1:
    sta WRMAINRAM                   ; $C38B
    sta RDCARDRAM                   ; $C38E

DOAUXMOVE_2:
    ldy #$00                        ; $C391

DOAUXMOVE_3:
    lda (A1L),y                     ; $C393
    sta (A4L),y                     ; $C395
    inc A4L                         ; $C397
    bne DOAUXMOVE_4                 ; $C399
    inc A4H                         ; $C39B

DOAUXMOVE_4:
    lda A1L                         ; $C39D
    cmp A2L                         ; $C39F
    lda A1H                         ; $C3A1
    sbc A2H                         ; $C3A3
    inc A1L                         ; $C3A5
    bne DOAUXMOVE_5                 ; $C3A7
    inc A1H                         ; $C3A9

DOAUXMOVE_5:
    bcc DOAUXMOVE_3                 ; $C3AB
    sta WRMAINRAM                   ; $C3AD
    pla                             ; $C3B0
    bpl DOAUXMOVE_6                 ; $C3B1
    sta WRCARDRAM                   ; $C3B3

DOAUXMOVE_6:
    sta RDMAINRAM                   ; $C3B6
    pla                             ; $C3B9
    bpl DOAUXMOVE_7                 ; $C3BA
    sta RDCARDRAM                   ; $C3BC

DOAUXMOVE_7:
    pla                             ; $C3BF
    tay                             ; $C3C0
    pla                             ; $C3C1
    rts                             ; $C3C2

;; XFER: sets RAMRD/RAMWRT both aux (carry set) or both main (carry clear), copies $03ED/$03EE into
;; the newly selected bank, picks the alternate (V set) or main (V clear) zero page and stack, and
;; jumps through ($03ED).
;; The bytes after it at $C3F4 (sta ROMIN; jmp $FC7A) are the return path of IRQHANDLER's fake
;; interrupt frame.
;; In: $03ED/$03EE = target, carry, V; A preserved
DOXFER:
    pha                             ; $C3C3
    lda $03ED                       ; $C3C4
    pha                             ; $C3C7
    lda $03EE                       ; $C3C8
    pha                             ; $C3CB
    bcc DOXFER_1                    ; $C3CC
    sta RDCARDRAM                   ; $C3CE
    sta WRCARDRAM                   ; $C3D1
    bcs DOXFER_2                    ; $C3D4

DOXFER_1:
    sta RDMAINRAM                   ; $C3D6
    sta WRMAINRAM                   ; $C3D9

DOXFER_2:
    pla                             ; $C3DC
    sta $03EE                       ; $C3DD
    pla                             ; $C3E0
    sta $03ED                       ; $C3E1
    pla                             ; $C3E4
    bvs DOXFER_3                    ; $C3E5
    sta SETSTDZP                    ; $C3E7
    bvc DOXFER_4                    ; $C3EA

DOXFER_3:
    sta SETALTZP                    ; $C3EC

DOXFER_4:
    jmp ($03ED)                     ; $C3EF
    .byte $00, $00                  ; $C3F2

;; The IRQ handler's return path: switches language-card ROM back in (ROMIN) and continues in the
;; Monitor at $FC7A.
IRQRETURN:
    sta ROMIN                       ; $C3F4
    jmp $FC7A                       ; $C3F7

;; IRQ and BRK entry, reached from the Monitor's IRQ ($FA44). Sets SETINTCXROM (code continues at
;; $C400 in internal ROM), reserves three stack bytes, saves X and Y, and builds a state byte while
;; switching to a known state: bit 0 internal $CX ROM was on; bit 6 80STORE and PAGE2 were on (sets
;; LOWSCR); bit 5 RAMRD aux and bit 4 RAMWRT aux (both set to main); bits 3-1 language card RAM read
;; ($0C bank 1, $0A bank 2; ROMIN is then selected); bit 7 alternate zero page (saves SP in $0101,
;; loads the main SP from $0100, SETSTDZP). A BRK (B flag) leaves the state in A5L, restores the
;; registers and goes to the Monitor's $FA47; an IRQ goes to IRQCALL.
;; In: A = the interrupted program's A (the Monitor's IRQ reloads it from A5H)
;; Uses: A5L, $0100/$0101
IRQHANDLER:
    bit RDCXROM                     ; $C3FA
    sta SETINTCXROM                 ; $C3FD execution continues in internal ROM at $C400
    cld                             ; $C400
    sec                             ; $C401
    bmi IRQHANDLER_1                ; $C402
    clc                             ; $C404

IRQHANDLER_1:
    pha                             ; $C405
    pha                             ; $C406
    pha                             ; $C407
    txa                             ; $C408
    tsx                             ; $C409
    inx                             ; $C40A
    inx                             ; $C40B
    inx                             ; $C40C
    inx                             ; $C40D
    pha                             ; $C40E
    tya                             ; $C40F
    pha                             ; $C410
    lda $0100,x                     ; $C411 P pushed by the interrupt: B flag selects BRK
    and #$10                        ; $C414
    tay                             ; $C416
    lda RD80STORE                   ; $C417
    and RDPAGE2                     ; $C41A
    and #$80                        ; $C41D
    beq IRQHANDLER_2                ; $C41F
    lda #$20                        ; $C421
    sta LOWSCR                      ; $C423

IRQHANDLER_2:
    rol a                           ; $C426
    bit RDRAMRD                     ; $C427
    bpl IRQHANDLER_3                ; $C42A
    sta RDMAINRAM                   ; $C42C
    ora #$20                        ; $C42F

IRQHANDLER_3:
    bit RDRAMWRT                    ; $C431
    bpl IRQHANDLER_4                ; $C434
    sta WRMAINRAM                   ; $C436
    ora #$10                        ; $C439

IRQHANDLER_4:
    bit RDLCRAM                     ; $C43B
    bpl IRQHANDLER_6                ; $C43E
    ora #$0C                        ; $C440
    bit RDLCBNK2                    ; $C442
    bpl IRQHANDLER_5                ; $C445
    eor #$06                        ; $C447

IRQHANDLER_5:
    sta ROMIN                       ; $C449

IRQHANDLER_6:
    bit RDALTZP                     ; $C44C
    bpl IRQHANDLER_7                ; $C44F
    tsx                             ; $C451
    stx $0101                       ; $C452
    ldx $0100                       ; $C455
    txs                             ; $C458
    sta SETSTDZP                    ; $C459
    ora #$80                        ; $C45C

IRQHANDLER_7:
    dey                             ; $C45E
    bmi IRQCALL                     ; $C45F
    sta A5L                         ; $C461
    pla                             ; $C463
    tay                             ; $C464
    pla                             ; $C465
    tax                             ; $C466
    pla                             ; $C467
    pla                             ; $C468
    pla                             ; $C469
    jmp $FA47                       ; $C46A

;; IRQ path: pushes the state byte and MSLOT, then a fake interrupt frame returning to $C3F4, and
;; goes to the Monitor's $FC74 (SETSLOTCXROM, jmp (IRQLOC)). The handler's RTI lands at $C3F4, which
;; selects ROMIN and goes to the Monitor's $FC7A to restore MSLOT's $C800 ROM and come back to
;; IRQRESTORE.
IRQCALL:
    pha                             ; $C46D
    lda MSLOT                       ; $C46E
    pha                             ; $C471
    lda #>IRQRETURN                 ; $C472
    pha                             ; $C474
    lda #<IRQRETURN                 ; $C475
    pha                             ; $C477
    php                             ; $C478
    jmp $FC74                       ; $C479

;; Undoes IRQHANDLER's state byte: restores the alternate zero page and its SP, touches the soft
;; switches in IRQSWITCHES for each set bit (page 2, RAMRD, RAMWRT, language card bank and RAM), then
;; writes a four-byte routine (sta $C006 or $C007; rti) just below the stack pointer, makes the
;; reserved stack bytes an address that returns into it, pulls X and A, and returns: the stub
;; restores the $CX ROM setting and does the RTI.
;; Uses: $0101 (the stack page below SP)
IRQRESTORE:
    lda ROMIN                       ; $C47C
    pla                             ; $C47F
    bpl IRQRESTORE_1                ; $C480
    sta SETALTZP                    ; $C482
    ldx $0101                       ; $C485
    txs                             ; $C488

IRQRESTORE_1:
    ldy #$06                        ; $C489

IRQRESTORE_2:
    bpl IRQRESTORE_4                ; $C48B

;; Part of IRQRESTORE's bit loop: touches the soft switch for a set state bit (ldx IRQSWITCHES,y; inc KBD,x).
IRQRESTORE_3:
    ldx IRQSWITCHES,y               ; $C48D
    inc KBD,x                       ; $C490

;; Part of IRQRESTORE's bit loop, not a separate routine.
IRQRESTORE_4:
    dey                             ; $C493
    bmi IRQRESTORE_5                ; $C494
    asl a                           ; $C496
    bne IRQRESTORE_2                ; $C497

IRQRESTORE_5:
    asl a                           ; $C499
    asl a                           ; $C49A
    pla                             ; $C49B
    tay                             ; $C49C
    tsx                             ; $C49D
    lda #$40                        ; $C49E builds "sta $C00x / rti" below the stack: rti
    pha                             ; $C4A0
    lda #>SETSLOTCXROM              ; $C4A1
    pha                             ; $C4A3
    lda #<SETSLOTCXROM              ; $C4A4 SETSLOTCXROM, or SETINTCXROM with carry set
    adc #$00                        ; $C4A6
    pha                             ; $C4A8
    lda #$8D                        ; $C4A9 sta absolute
    pha                             ; $C4AB
    txs                             ; $C4AC
    txa                             ; $C4AD
    adc #$03                        ; $C4AE
    tax                             ; $C4B0
    sec                             ; $C4B1
    sbc #$07                        ; $C4B2
    sta $0100,x                     ; $C4B4
    inx                             ; $C4B7
    lda #$01                        ; $C4B8
    sta $0100,x                     ; $C4BA
    pla                             ; $C4BD
    tax                             ; $C4BE
    pla                             ; $C4BF
    rts                             ; $C4C0

;; Soft switch offsets from $C000 that IRQRESTORE touches (inc KBD,x), indexed by state bit - 1: bits
;; 1-3 the language card (bank 2 RAM sets bits 3 and 1, bank 1 bits 3 and 2), bit 4 RAMWRT aux, bit 5
;; RAMRD aux, bit 6 page 2. The last entry is unused.
IRQSWITCHES:
    .byte <LCBANK2, <LCBANK1, <LCBANK1, <WRCARDRAM, <RDCARDRAM, <HISCR, $00 ; $C4C1

;; Mini-assembler operand parser: for X down to 0 compares the input (via the Monitor's $FF13) with
;; the CHAR1/CHAR2 address-mode characters and shifts a match bit into A5L; at X = 3 reads a number
;; with GETNUM into A2 and sets YSAV1 (one higher when A2H is nonzero).
;; In: X = 5 (from MINIPARSE), Y = input index
;; Out: A5L = mode bits, A2 = operand, YSAV1, Y advanced
;; Uses: YSAV, A1H
MINIOPND:
    jsr SKIPBLNK                    ; $C4C8
    sty YSAV                        ; $C4CB
    cmp CHAR1,x                     ; $C4CD
    bne MINIOPND_1                  ; $C4D0
    jsr SKIPBLNK                    ; $C4D2
    cmp CHAR2,x                     ; $C4D5
    beq MINIOPND_3                  ; $C4D8
    lda CHAR2,x                     ; $C4DA
    beq MINIOPND_2                  ; $C4DD
    cmp #'$'                        ; $C4DF
    beq MINIOPND_2                  ; $C4E1
    ldy YSAV                        ; $C4E3

MINIOPND_1:
    clc                             ; $C4E5

MINIOPND_2:
    dey                             ; $C4E6

MINIOPND_3:
    rol A5L                         ; $C4E7
    cpx #$03                        ; $C4E9
    bne MINIOPND_5                  ; $C4EB
    jsr GETNUM                      ; $C4ED
    lda A2H                         ; $C4F0
    beq MINIOPND_4                  ; $C4F2
    inx                             ; $C4F4

MINIOPND_4:
    stx YSAV1                       ; $C4F5
    ldx #$03                        ; $C4F7
    dey                             ; $C4F9

MINIOPND_5:
    stx A1H                         ; $C4FA
    dex                             ; $C4FC
    bpl MINIOPND                    ; $C4FD
    rts                             ; $C4FF

;; AppleSoft cassette helper (from AppleSoft's $F777 with internal ROM switched in).
;; Carry set (SHLOAD): reads the two-byte length into LINNUM with READTAPE, then if the table fits
;; below HIMEM (MEMSIZ) and above STREND continues at TAPESHLOAD; otherwise returns carry set
;; (AppleSoft reports out of memory).
;; Carry clear (STORE/RECALL): continues at TAPEARRAY.
;; Out:   carry = clear on success
BASTAPE:
    bcc TAPEARRAY                   ; $C500
    lda #$00                        ; $C502
    sta A1H                         ; $C504
    sta A2H                         ; $C506
    ldy #LINNUM                     ; $C508
    sty A1L                         ; $C50A
    iny                             ; $C50C
    sty A2L                         ; $C50D
    jsr READTAPE                    ; $C50F
    clc                             ; $C512
    lda MEMSIZ                      ; $C513
    tax                             ; $C515
    dex                             ; $C516
    stx A2L                         ; $C517
    sbc LINNUM                      ; $C519
    pha                             ; $C51B
    lda MEMSIZ+1                    ; $C51C
    tay                             ; $C51E
    inx                             ; $C51F
    bne BASTAPE_1                   ; $C520
    dey                             ; $C522

BASTAPE_1:
    sty A2H                         ; $C523
    sbc LINNUM+1                    ; $C525
    cmp STREND+1                    ; $C527
    bcc BASTAPE_2                   ; $C529
    bne TAPESHLOAD                  ; $C52B

BASTAPE_2:
    sec                             ; $C52D
    rts                             ; $C52E

;; SHLOAD: sets HIMEM, FRETOP, the shape table pointer (SHAPEPTR) and A1 to HIMEM - length,
;; then reads the table from tape (READTAPE's entry at $C5D6 with a short header).
TAPESHLOAD:
    sta MEMSIZ+1                    ; $C52F
    sta FRETOP+1                    ; $C531
    sta A1H                         ; $C533
    sta SHAPEPTR+1                  ; $C535
    pla                             ; $C537
    sta SHAPEPTR                    ; $C538
    sta MEMSIZ                      ; $C53A
    sta FRETOP                      ; $C53C
    sta A1L                         ; $C53E
    jsr RDTAPE2BIT                  ; $C540
    lda #$03                        ; $C543
    jsr READTAPE_1                  ; $C545
    clc                             ; $C548
    rts                             ; $C549

;; STORE/RECALL: A2 = LOWTR + LINNUM, calls AppleSoft's $E0EF with the array header's byte 4, and
;; copies HIGHDS into A1 for the Monitor's WRITE or READ that follows.
TAPEARRAY:
    lda LOWTR                       ; $C54A
    adc LINNUM                      ; $C54C
    sta A2L                         ; $C54E
    lda LOWTR+1                     ; $C550
    adc LINNUM+1                    ; $C552
    sta A2H                         ; $C554
    ldy #$04                        ; $C556
    lda (LOWTR),y                   ; $C558
    jsr $E0EF                       ; $C55A
    lda HIGHDS                      ; $C55D
    sta A1L                         ; $C55F
    lda HIGHDS+1                    ; $C561
    sta A1H                         ; $C563
    clc                             ; $C565
    rts                             ; $C566

;; Cassette header tone (the Monitor's HEADR calls it): toggles TAPEOUT in timed loops; $C574 writes
;; one bit (carry selects the length).
;; In: A = header length, X
;; Uses: Y, TAPEOUT
TAPEHEADR:
    ldy #$4B                        ; $C567
    jsr TAPEHEADR_2                 ; $C569
    bne TAPEHEADR                   ; $C56C
    adc #$FE                        ; $C56E
    bcs TAPEHEADR                   ; $C570
    ldy #$21                        ; $C572

TAPEHEADR_1:
    jsr TAPEHEADR_2                 ; $C574 write one bit (carry = bit)
    iny                             ; $C577
    iny                             ; $C578

TAPEHEADR_2:
    dey                             ; $C579
    bne TAPEHEADR_2                 ; $C57A
    bcc TAPEHEADR_4                 ; $C57C
    ldy #$32                        ; $C57E

TAPEHEADR_3:
    dey                             ; $C580
    bne TAPEHEADR_3                 ; $C581

TAPEHEADR_4:
    ldy TAPEOUT                     ; $C583
    ldy #$2C                        ; $C586
    dex                             ; $C588
    rts                             ; $C589

;; Reads 8 bits from tape into A, one RDTAPE2BIT per bit.
;; Out: A = byte
RDTAPEBYTE:
    ldx #$08                        ; $C58A

RDTAPEBYTE_1:
    pha                             ; $C58C
    jsr RDTAPE2BIT                  ; $C58D
    pla                             ; $C590
    rol a                           ; $C591
    ldy #$3A                        ; $C592
    dex                             ; $C594
    bne RDTAPEBYTE_1                ; $C595
    rts                             ; $C597

;; Waits for two TAPEIN level changes; $C59B waits for one. LENGTH holds the last level; Y counts down
;; during the wait.
;; Out:   carry = the bit, from cpy #$80 on the elapsed time
;; Uses: LENGTH, Y
RDTAPE2BIT:
    jsr RDTAPE2BIT_1                ; $C598

RDTAPE2BIT_1:
    dey                             ; $C59B one level change
    lda TAPEIN                      ; $C59C
    eor LENGTH                      ; $C59F
    bpl RDTAPE2BIT_1                ; $C5A1
    eor LENGTH                      ; $C5A3
    sta LENGTH                      ; $C5A5
    cpy #$80                        ; $C5A7
    rts                             ; $C5A9

;; Cassette write (the Monitor's WRITE): header, then A1..A2 a byte at a time with a running exclusive
;; or, then that checksum; $C5C8 writes the byte in A.
;; In: A1/A2, A = header length
;; Out:   zero = set at the end
WRITETAPE:
    jsr TAPEHEADR                   ; $C5AA
    ldy #$27                        ; $C5AD

WRITETAPE_1:
    ldx #$00                        ; $C5AF
    eor (A1L,x)                     ; $C5B1
    pha                             ; $C5B3
    lda (A1L,x)                     ; $C5B4
    jsr WRITETAPE_2                 ; $C5B6
    jsr NXTA1                       ; $C5B9
    ldy #$1D                        ; $C5BC
    pla                             ; $C5BE
    bcc WRITETAPE_1                 ; $C5BF
    ldy #$22                        ; $C5C1
    jsr WRITETAPE_2                 ; $C5C3
    beq WRITETAPE_4                 ; $C5C6

WRITETAPE_2:
    ldx #$10                        ; $C5C8 write one byte

WRITETAPE_3:
    asl a                           ; $C5CA
    jsr TAPEHEADR_1                 ; $C5CB
    bne WRITETAPE_3                 ; $C5CE

WRITETAPE_4:
    rts                             ; $C5D0

;; Cassette read (the Monitor's READ): finds the header and sync, reads bytes into A1..A2, then reads
;; the checksum byte and compares it with the running exclusive or in MASK. $C5D6 starts with a given
;; header length in A (used by SHLOAD).
;; In: A1/A2
;; Out:   zero = set when the checksum matches
;; Uses: MASK, LENGTH, A1
READTAPE:
    jsr RDTAPE2BIT                  ; $C5D1
    lda #$16                        ; $C5D4

READTAPE_1:
    jsr TAPEHEADR                   ; $C5D6
    sta MASK                        ; $C5D9
    jsr RDTAPE2BIT                  ; $C5DB

READTAPE_2:
    ldy #$24                        ; $C5DE
    jsr RDTAPE2BIT_1                ; $C5E0
    bcs READTAPE_2                  ; $C5E3
    jsr RDTAPE2BIT_1                ; $C5E5
    ldy #$3B                        ; $C5E8

READTAPE_3:
    jsr RDTAPEBYTE                  ; $C5EA
    sta (A1L,x)                     ; $C5ED
    eor MASK                        ; $C5EF
    sta MASK                        ; $C5F1
    jsr NXTA1                       ; $C5F3
    ldy #$35                        ; $C5F6
    bcc READTAPE_3                  ; $C5F8
    jsr RDTAPEBYTE                  ; $C5FA
    cmp MASK                        ; $C5FD
    rts                             ; $C5FF

;; Self-test (from RESETFW when BUTN1 is down; destroys memory). Shows graphics (TXTCLR), fills and
;; checks page zero with five patterns built from TESTPATTERNS (an error goes to TESTFAIL as RAM ZP), then
;; continues with RAMTEST.
;; $C603 is re-entered with the alternate zero page and aux RAM selected to test aux memory.
;; Uses: all
SELFTEST:
    sta TXTCLR                      ; $C600

SELFTEST_1:
    ldy #$04                        ; $C603 re-entered to test auxiliary memory
    ldx #$00                        ; $C605

SELFTEST_2:
    clc                             ; $C607
    adc TESTPATTERNS,y              ; $C608
    sta LOC0,x                      ; $C60B
    inx                             ; $C60D
    bne SELFTEST_2                  ; $C60E

SELFTEST_3:
    clc                             ; $C610
    adc TESTPATTERNS,y              ; $C611
    cmp LOC0,x                      ; $C614
    bne SELFTEST_5                  ; $C616
    inx                             ; $C618
    bne SELFTEST_3                  ; $C619
    ror a                           ; $C61B
    bit RDVBLBAR                    ; $C61C
    bpl SELFTEST_4                  ; $C61F
    eor #$A5                        ; $C621

SELFTEST_4:
    dey                             ; $C623
    bpl SELFTEST_2                  ; $C624
    bmi RAMTEST                     ; $C626

SELFTEST_5:
    eor LOC0,x                      ; $C628
    clc                             ; $C62A
    jmp TESTFAIL_1                  ; $C62B

;; The page the self-test's RAM test is filling or checking.
;;
;; <RAMTEST> counts it from $01 through $FF on each pass, filling the pages and then checking them. Pages
;; $C0-$CF, the I/O space, test language card bank 1 instead, through <TESTPTR>.
;; See: <TESTPTR>, <TESTCOUNT>, <RAMTEST>
TESTPAGE = $01

;; The self-test's pointer to the page it is testing, a page address with the low byte 0.
;;
;; <RAMTEST> sets its high byte from <TESTPAGE>, adding $10 for the pages $C0-$CF so that they reach bank 1 of
;; the language card at $D000-$DFFF, and fills or checks the page through it.
;; See: <TESTPAGE>, <RAMTEST>
TESTPTR = $02

;; The number of passes the self-test's RAM test has left after this one.
;;
;; <RAMTEST> sets it to 4 and makes five passes, each starting from a different pattern.
;; See: <TESTPAGE>, <RAMTEST>
TESTCOUNT = $04

;; Fills pages $01-$FF with patterns and verifies them, five passes ($04 counts). Pages $D0-$FF use
;; language card bank 2 RAM; pages $C0-$CF are redirected to bank 1 ($D0-$DF). A mismatch goes to
;; TESTFAIL. Then AUXRAMTEST: when aux memory answers and aux $0800 does not change along with $0C00
;; (more than 1K of aux memory), sets ALTZP and repeats the whole test there from $C603; otherwise the
;; MMU/IOU test at $C736 follows.
;; Uses: TESTPAGE, TESTPTR, TESTCOUNT, LCBANK2/LCBANK1
RAMTEST:
    stx TESTPAGE                    ; $C62E
    stx TESTPTR                     ; $C630
    stx TESTPTR+1                   ; $C632
    ldx #$04                        ; $C634
    stx TESTCOUNT                   ; $C636

RAMTEST_1:
    inc TESTPAGE                    ; $C638

RAMTEST_2:
    tay                             ; $C63A
    sta LCBANK2                     ; $C63B
    sta LCBANK2                     ; $C63E
    lda TESTPAGE                    ; $C641
    and #$F0                        ; $C643
    cmp #$C0                        ; $C645
    bne RAMTEST_3                   ; $C647
    lda LCBANK1                     ; $C649
    lda LCBANK1                     ; $C64C
    lda TESTPAGE                    ; $C64F
    adc #$0F                        ; $C651
    bne RAMTEST_4                   ; $C653

RAMTEST_3:
    lda TESTPAGE                    ; $C655

RAMTEST_4:
    sta TESTPTR+1                   ; $C657
    tya                             ; $C659
    ldy #$00                        ; $C65A

RAMTEST_5:
    clc                             ; $C65C
    adc TESTPATTERNS,x              ; $C65D
    sta (TESTPTR),y                 ; $C660
    dex                             ; $C662
    bpl RAMTEST_6                   ; $C663
    ldx #$04                        ; $C665

RAMTEST_6:
    iny                             ; $C667
    bne RAMTEST_5                   ; $C668
    inc TESTPAGE                    ; $C66A
    bne RAMTEST_2                   ; $C66C
    inc TESTPAGE                    ; $C66E

RAMTEST_7:
    tay                             ; $C670
    lda LCBANK2                     ; $C671
    lda LCBANK2                     ; $C674
    lda TESTPAGE                    ; $C677
    and #$F0                        ; $C679
    cmp #$C0                        ; $C67B
    bne RAMTEST_8                   ; $C67D
    lda LCBANK1                     ; $C67F
    lda TESTPAGE                    ; $C682
    adc #$0F                        ; $C684
    bne RAMTEST_9                   ; $C686

RAMTEST_8:
    lda TESTPAGE                    ; $C688

RAMTEST_9:
    sta TESTPTR+1                   ; $C68A
    tya                             ; $C68C
    ldy #$00                        ; $C68D

RAMTEST_10:
    clc                             ; $C68F
    adc TESTPATTERNS,x              ; $C690
    eor (TESTPTR),y                 ; $C693
    bne TESTFAIL                    ; $C695
    lda (TESTPTR),y                 ; $C697
    dex                             ; $C699
    bpl RAMTEST_11                  ; $C69A
    ldx #$04                        ; $C69C

RAMTEST_11:
    iny                             ; $C69E
    bne RAMTEST_10                  ; $C69F
    inc TESTPAGE                    ; $C6A1
    bne RAMTEST_7                   ; $C6A3
    ror a                           ; $C6A5
    bit RDVBLBAR                    ; $C6A6
    bpl RAMTEST_12                  ; $C6A9
    eor #$A5                        ; $C6AB

RAMTEST_12:
    dec TESTCOUNT                   ; $C6AD
    bpl RAMTEST_1                   ; $C6AF
    tax                             ; $C6B1
    jsr AUXRAMTEST                  ; $C6B2
    bne RAMTEST_13                  ; $C6B5
    asl $0C00                       ; $C6B7
    asl a                           ; $C6BA
    cmp $0C00                       ; $C6BB

RAMTEST_13:
    bne SWITCHTEST                  ; $C6BE
    cmp $0800                       ; $C6C0
    beq SWITCHTEST                  ; $C6C3
    txa                             ; $C6C5
    sta SETALTZP                    ; $C6C6
    jmp SELFTEST_1                  ; $C6C9

;; Self-test failure display (sec entry: RAM; $C6CD with carry clear: zero page). Resets several
;; switches to main memory and 40 columns, clears the text page, and shows "RAM" or "RAM ZP" (with
;; "*" when aux memory was selected) followed by the failing bits in X as 0/1, then hangs. With X = 0
;; it shows "MMU" (carry clear) or "IOU" (carry set) and hangs.
;; $C736 is the MMU/IOU soft switch test: sets each switch pair from TESTSWITCH1/TESTSWITCH2 by a rotating bit
;; and checks the status byte listed in TESTSTATUS; a mismatch shows MMU (first group) or IOU (second).
;; In: X = failing bits, carry, A
TESTFAIL:
    sec                             ; $C6CC

TESTFAIL_1:
    tax                             ; $C6CD
    lda RDRAMRD                     ; $C6CE
    clv                             ; $C6D1
    bpl TESTFAIL_2                  ; $C6D2
    bit TESTPATTERNS                ; $C6D4

TESTFAIL_2:
    lda #' '                        ; $C6D7
    ldy #$06                        ; $C6D9

TESTFAIL_3:
    sta $BFFE,y                     ; $C6DB stores to $C004/$C002/$C000 and $C00C/$C00A/$C008
    sta SETSLOTCXROM,y              ; $C6DE
    dey                             ; $C6E1
    dey                             ; $C6E2
    bne TESTFAIL_3                  ; $C6E3
    sta TXTSET                      ; $C6E5
    sta LOWSCR                      ; $C6E8

TESTFAIL_4:
    sta LINE1,y                     ; $C6EB
    sta $0500,y                     ; $C6EE
    sta $0600,y                     ; $C6F1
    sta $0700,y                     ; $C6F4
    iny                             ; $C6F7
    bne TESTFAIL_4                  ; $C6F8
    txa                             ; $C6FA
    beq TESTFAIL_9                  ; $C6FB
    ldy #$03                        ; $C6FD
    bcs TESTFAIL_5                  ; $C6FF
    ldy #$05                        ; $C701

TESTFAIL_5:
    lda #'*'                        ; $C703
    bvc TESTFAIL_6                  ; $C705
    sta $05B0                       ; $C707

TESTFAIL_6:
    lda RAMZPTEXT,y                 ; $C70A
    sta $05B1,y                     ; $C70D
    dey                             ; $C710
    bpl TESTFAIL_6                  ; $C711
    ldy #$10                        ; $C713

TESTFAIL_7:
    txa                             ; $C715
    lsr a                           ; $C716
    tax                             ; $C717
    lda #'0' >> 1                   ; $C718
    rol a                           ; $C71A "0" or "1"
    sta $05B6,y                     ; $C71B
    dey                             ; $C71E
    dey                             ; $C71F
    bne TESTFAIL_7                  ; $C720

TESTFAIL_8:
    beq TESTFAIL_8                  ; $C722

TESTFAIL_9:
    ldy #$02                        ; $C724

TESTFAIL_10:
    lda MMUTEXT,y                   ; $C726
    bcc TESTFAIL_11                 ; $C729
    lda IOUTEXT,y                   ; $C72B

TESTFAIL_11:
    sta $05B8,y                     ; $C72E
    dey                             ; $C731
    bpl TESTFAIL_10                 ; $C732

TESTFAIL_12:
    bmi TESTFAIL_12                 ; $C734

SWITCHTEST:
    ldy #$01                        ; $C736 MMU/IOU soft switch test

SWITCHTEST_1:
    lda #$7F                        ; $C738

SWITCHTEST_2:
    ror a                           ; $C73A
    ldx TESTSWITCH1,y               ; $C73B
    beq SWITCHTEST_5                ; $C73E
    bcc SWITCHTEST_3                ; $C740
    ldx TESTSWITCH2,y               ; $C742

SWITCHTEST_3:
    sta $BFFF,x                     ; $C745
    iny                             ; $C748
    bne SWITCHTEST_2                ; $C749

SWITCHTEST_4:
    ldx SPKR                        ; $C74B
    rol a                           ; $C74E

SWITCHTEST_5:
    dey                             ; $C74F
    ldx TESTSTATUS,y                ; $C750
    beq SWITCHTEST_7                ; $C753
    bmi SWITCHTEST_4                ; $C755
    rol a                           ; $C757
    bcc SWITCHTEST_6                ; $C758
    asl KBD,x                       ; $C75A
    bcc SWITCHTEST_8                ; $C75D
    bcs SWITCHTEST_5                ; $C75F

SWITCHTEST_6:
    asl KBD,x                       ; $C761
    bcs SWITCHTEST_8                ; $C764
    bcc SWITCHTEST_5                ; $C766

SWITCHTEST_7:
    rol a                           ; $C768
    iny                             ; $C769
    sec                             ; $C76A
    sbc #$01                        ; $C76B
    bcs SWITCHTEST_2                ; $C76D
    dey                             ; $C76F
    bne TESTPASS                    ; $C770
    ldy #$09                        ; $C772
    bne SWITCHTEST_1                ; $C774

SWITCHTEST_8:
    ldx #$00                        ; $C776
    cpy #$0A                        ; $C778
    jmp TESTFAIL_2                  ; $C77A

;; Repeats the soft switch test while lsr $80 leaves a nonzero value, then clears the screen and loops:
;; with both apple keys down it reruns SELFTEST, otherwise it shows "System OK" (SYSTEMOK).
TESTPASS:
    lsr $80                         ; $C77D
    bne SWITCHTEST                  ; $C77F
    lda #' '                        ; $C781
    ldy #$00                        ; $C783

TESTPASS_1:
    sta LINE1,y                     ; $C785
    sta $0500,y                     ; $C788
    sta $0600,y                     ; $C78B
    sta $0700,y                     ; $C78E
    iny                             ; $C791
    bne TESTPASS_1                  ; $C792

TESTPASS_2:
    lda BUTN0                       ; $C794
    and BUTN1                       ; $C797
    asl a                           ; $C79A
    inc $FF                         ; $C79B
    lda $FF                         ; $C79D
    bcc SYSTEMOK                    ; $C79F
    jmp SELFTEST                    ; $C7A1

;; Shows SYSOKTEXT ("System OK") on the text page and returns to TESTPASS's key loop.
SYSTEMOK:
    lda TXTSET                      ; $C7A4
    ldy #$08                        ; $C7A7

SYSTEMOK_1:
    lda SYSOKTEXT,y                 ; $C7A9
    sta $05B8,y                     ; $C7AC
    dey                             ; $C7AF
    bpl SYSTEMOK_1                  ; $C7B0
    bmi TESTPASS_2                  ; $C7B2

;; Five pattern increments for the RAM tests; also read by a bit instruction to set V.
TESTPATTERNS:
    .byte $53, $43, $2B, $29, $07   ; $C7B4

;; Self-test soft switches ($BFFF + entry), one side of each pair; 0 ends a group.
TESTSWITCH1:
    .byte $00, $89, $31, $03, $05, $09, $0B, $01 ; $C7B9
    .byte $00, $83, $51, $53, $55, $57, $0F, $0D ; $C7C1

;; Self-test soft switches, the other side of each pair in TESTSWITCH1.
TESTSWITCH2:
    .byte $00, $81, $31, $04, $06, $0A, $0C, $02 ; $C7C9
    .byte $00, $84, $52, $54, $56, $58, $10, $0E ; $C7D1

;; Self-test status reads ($C000 + entry) matching TESTSWITCH1/TESTSWITCH2; $FF reads SPKR instead.
TESTSTATUS:
    .byte $00, $11, $FF, $13, $14, $16, $17, $18 ; $C7D9
    .byte $00, $12, $1A, $1B, $1C, $1D, $1E, $1F ; $C7E1
    .byte $00                       ; $C7E9

;; "RAM ZP", shown by TESTFAIL.
RAMZPTEXT:
    .byte "RAM ZP"                  ; $C7EA

;; "MMU", shown by TESTFAIL.
MMUTEXT:
    .byte "MMU"                     ; $C7F0

;; "IOU", shown by TESTFAIL.
IOUTEXT:
    .byte "IOU"                     ; $C7F3

;; "System OK", shown when the self-test passes.
SYSOKTEXT:
    .byte "System OK"               ; $C7F6
    .byte $00                       ; $C7FF


;; A fixed entry at the start of the $C800 ROM: jumps to C9PASINIT.
C8ENTRY:
    jmp C9PASINIT                   ; $C800

;; PR#3 initialization: LCMONCOPY, sets CSW/KSW to $C307/$C305, a full 40-column window (WNDTOP 20
;; in mixed graphics), $04FB = 1; with auxiliary text memory doubles WNDWDTH and sets 80STORE and
;; 80VID. Then SETALTCHAR, clears the screen and prints the character that came with the call.
;; In: $067B = character; Y and X pushed by C3ENTRY
C3INIT:
    jsr LCMONCOPY                   ; $C803
    jsr SETC3HOOKS                  ; $C806
    jsr SET40COL_4                  ; $C809
    lda #$01                        ; $C80C
    sta MODE80                      ; $C80E
    jsr AUXPRESENT                  ; $C811
    bne C3INIT_1                    ; $C814
    asl WNDWDTH                     ; $C816
    sta SET80STORE                  ; $C818
    sta SET80VID                    ; $C81B

C3INIT_1:
    sta SETALTCHAR                  ; $C81E
    jsr CLRSCRN80                   ; $C821
    ldy OURCH                       ; $C824
    jmp CHARIO80_3                  ; $C827

;; CSW = $C307 (BASICOUT), KSW = $C305 (BASICIN).
SETC3HOOKS:
    lda #<BASICOUT                  ; $C82A
    sta CSWL                        ; $C82C
    lda #>BASICOUT                  ; $C82E
    sta CSWH                        ; $C830

SETC3HOOKS_1:
    lda #<BASICIN                   ; $C832
    sta KSWL                        ; $C834
    lda #>BASICIN                   ; $C836
    sta KSWH                        ; $C838
    rts                             ; $C83A

;; Waits for a key while counting RNDL/RNDH, then clears the strobe.
;; Out: A = key
;; The bytes after it ($C84D) hold jmp $C350 (Pascal read).
GETKEYRND:
    inc RNDL                        ; $C83B
    bne GETKEYRND_1                 ; $C83D
    inc RNDH                        ; $C83F

GETKEYRND_1:
    lda KBD                         ; $C841
    bpl GETKEYRND                   ; $C844
    sta KBDSTRB                     ; $C846
    rts                             ; $C849
    .byte $00, $00, $00             ; $C84A

;; A fixed entry: jumps to PASREAD (apparently an older Pascal read entry).
C8PASREAD:
    jmp PASREAD                     ; $C84D

;; Adopts CH into $057B when CH differs from $047B (the value the firmware last stored), copies CV to
;; $05FB, and resets $057B to 0 if it is not inside the window.
;; Out: Y = $057B
SYNCCH:
    lda CV                          ; $C850
    sta OURCV                       ; $C852
    ldy CH                          ; $C855
    cpy OLDCH                       ; $C857
    beq SYNCCH_1                    ; $C85A
    sty OURCH                       ; $C85C

SYNCCH_1:
    lda WNDWDTH                     ; $C85F
    clc                             ; $C861
    sbc OURCH                       ; $C862
    bcs SYNCCH_2                    ; $C865
    ldy #$00                        ; $C867
    sty OURCH                       ; $C869

SYNCCH_2:
    ldy OURCH                       ; $C86C
    rts                             ; $C86F

;; 80-column character I/O. $C870 (function 0): output, restoring Y from YSAV1. $C874: input (carry
;; set). Both save A in $067B and push Y and X; $C87C picks input (INPUT80) or output by carry.
;; Output: after SYNCCH, a CR with ctrl-S waiting pauses until another key (ctrl-C is left in the
;; keyboard); control characters go to DOCTRL, others to PRINT80.
;; In: A = character; carry selects input at $C87C
;; Out: A = $067B (the character or key); X and Y restored
CHARIO80:
    ldy YSAV1                       ; $C870
    clc                             ; $C872
    .byte $B0                       ; $C873 bcs: skips the next byte

CHARIO80_1:
    sec                             ; $C874 input entry
    sta CHAR                        ; $C875
    tya                             ; $C878
    pha                             ; $C879
    txa                             ; $C87A
    pha                             ; $C87B

CHARIO80_2:
    bcs INPUT80                     ; $C87C carry set = input

CHARIO80_3:
    jsr SYNCCH                      ; $C87E output entry used by C3INIT
    lda CHAR                        ; $C881
    cmp #KEY_CR                     ; $C884
    bne CHARIO80_5                  ; $C886
    ldx KBD                         ; $C888
    bpl CHARIO80_5                  ; $C88B
    cpx #KEY_CTRL_S                 ; $C88D
    bne CHARIO80_5                  ; $C88F
    bit KBDSTRB                     ; $C891

CHARIO80_4:
    ldx KBD                         ; $C894
    bpl CHARIO80_4                  ; $C897
    cpx #KEY_CTRL_C                 ; $C899
    beq CHARIO80_5                  ; $C89B
    bit KBDSTRB                     ; $C89D

CHARIO80_5:
    and #$7F                        ; $C8A0
    cmp #$20                        ; $C8A2 control characters are below $20
    bcs PRINT80                     ; $C8A4
    jsr DOCTRL                      ; $C8A6
    jmp PRINT80_1                   ; $C8A9

;; Stores $067B at column $057B (through PUTINV), advances $057B and wraps with CR80 at WNDWDTH.
;; $C8BD clears $04FB bit 3; $C8C5 sets CH (and $047B) to $057B, or to 0 when 80VID is on, then
;; restores X and Y and returns $067B in A.
PRINT80:
    lda CHAR                        ; $C8AC
    jsr PUTINV                      ; $C8AF
    iny                             ; $C8B2
    sty OURCH                       ; $C8B3
    cpy WNDWDTH                     ; $C8B6
    bcc PRINT80_1                   ; $C8B8
    jsr CR80                        ; $C8BA

PRINT80_1:
    lda MODE80                      ; $C8BD
    and #$F7                        ; $C8C0
    sta MODE80                      ; $C8C2

PRINT80_2:
    lda OURCH                       ; $C8C5 common return: update CH, restore X/Y
    bit RD80VID                     ; $C8C8
    bpl PRINT80_3                   ; $C8CB
    lda #$00                        ; $C8CD

PRINT80_3:
    sta CH                          ; $C8CF
    sta OLDCH                       ; $C8D1
    pla                             ; $C8D4
    tax                             ; $C8D5
    pla                             ; $C8D6
    tay                             ; $C8D7
    lda CHAR                        ; $C8D8
    rts                             ; $C8DB

;; 80-column key input: writes $067B back at (BASL),CH, then shows the cursor (FLIPCURSOR) while
;; waiting. Without $04FB bit 3 the key is returned as is. With it: CR clears bit 3, ctrl-U returns the
;; character under the cursor, and ESC enters escape mode: shows ESCCURSOR, upshifts the next key and
;; looks it up in ESCKEYS; a match runs the control code from ESCCODES (through DOCTRL), staying in
;; escape mode when that byte has bit 7 set. ESC ctrl-Q quits 80 columns (QUIT80) and returns ctrl-X;
;; ESC ctrl-E and ctrl-D clear and set $04FB bit 5.
;; Out: A = key (via PRINT80's return)
;; Uses: $067B, $04FB, $057B
INPUT80:
    ldy CH                          ; $C8DC
    lda CHAR                        ; $C8DE
    sta (BASL),y                    ; $C8E1
    jsr SYNCCH                      ; $C8E3

INPUT80_1:
    jsr FLIPCURSOR_1                ; $C8E6
    jsr GETKEYRND                   ; $C8E9
    sta CHAR                        ; $C8EC
    jsr FLIPCURSOR_1                ; $C8EF
    tay                             ; $C8F2
    lda MODE80                      ; $C8F3
    and #$08                        ; $C8F6
    beq PRINT80_2                   ; $C8F8
    cpy #KEY_CR                     ; $C8FA
    bne INPUT80_2                   ; $C8FC
    lda MODE80                      ; $C8FE
    and #$F7                        ; $C901
    sta MODE80                      ; $C903

INPUT80_2:
    cpy #KEY_ESC                    ; $C906
    beq INPUT80_3                   ; $C908
    cpy #KEY_RIGHT                  ; $C90A
    bne PRINT80_2                   ; $C90C
    ldy OURCH                       ; $C90E
    jsr GETSCRCHAR                  ; $C911
    ora #$80                        ; $C914
    sta CHAR                        ; $C916
    bne PRINT80_2                   ; $C919

INPUT80_3:
    jsr ESCCURSOR                   ; $C91B
    jsr GETKEYRND                   ; $C91E
    jsr RESTCHAR                    ; $C921
    jsr UPSHIFT                     ; $C924
    and #$7F                        ; $C927
    ldy #ESCAPE_COUNT - 1           ; $C929

INPUT80_4:
    cmp ESCKEYS,y                   ; $C92B
    beq INPUT80_5                   ; $C92E
    dey                             ; $C930
    bpl INPUT80_4                   ; $C931
    bmi INPUT80_6                   ; $C933

INPUT80_5:
    lda ESCCODES,y                  ; $C935
    and #$7F                        ; $C938
    jsr DOCTRL_1                    ; $C93A
    lda ESCCODES,y                  ; $C93D
    bmi INPUT80_3                   ; $C940
    bpl INPUT80_1                   ; $C942

INPUT80_6:
    tay                             ; $C944
    lda MODE80                      ; $C945
    cpy #CTRL_Q                     ; $C948
    bne INPUT80_7                   ; $C94A
    jsr QUIT80                      ; $C94C
    lda #KEY_CTRL_X                 ; $C94F
    sta CHAR                        ; $C951
    jmp PRINT80_2                   ; $C954

;; ESC ctrl-E: clears $04FB bit 5 (control characters enabled again).
INPUT80_7:
    cpy #CTRL_E                     ; $C957
    bne INPUT80_10                  ; $C959
    and #$DF                        ; $C95B

INPUT80_8:
    sta MODE80                      ; $C95D

INPUT80_9:
    jmp INPUT80_1                   ; $C960

;; ESC ctrl-D: sets $04FB bit 5 (control characters disabled). Other keys return to input.
INPUT80_10:
    cpy #CTRL_D                     ; $C963
    bne INPUT80_9                   ; $C965
    ora #$20                        ; $C967
    bne INPUT80_8                   ; $C969

;; Escape mode's tables: each escape key (upshifted, bit 7 clear) and the control code it runs.
;; ESCAPE_STAY on a code keeps escape mode on after it.
ESCAPE_STAY = $80
.set ESCAPES, 0

.macro ESCAPE key, code
    .ident(.sprintf("ESCAPE_KEY_%d", ESCAPES)) = (key) & $7F
    .ident(.sprintf("ESCAPE_CODE_%d", ESCAPES)) = code
    .set ESCAPES, ESCAPES + 1
.endmacro

    ESCAPE '@', CTRL_L                              ; clear the screen
    ESCAPE 'A', CTRL_BACKSLASH                      ; right
    ESCAPE 'B', CTRL_H                              ; left
    ESCAPE 'C', CTRL_J                              ; down
    ESCAPE 'D', CTRL_UNDERSCORE                     ; up
    ESCAPE 'E', CTRL_RBRACKET                       ; clear to the end of the line
    ESCAPE 'F', CTRL_K                              ; clear to the end of the screen
    ESCAPE 'I', CTRL_UNDERSCORE | ESCAPE_STAY       ; up
    ESCAPE 'J', CTRL_H | ESCAPE_STAY                ; left
    ESCAPE 'K', CTRL_BACKSLASH | ESCAPE_STAY        ; right
    ESCAPE 'M', CTRL_J | ESCAPE_STAY                ; down
    ESCAPE '4', CTRL_Q                              ; 40 columns
    ESCAPE '8', CTRL_R                              ; 80 columns
    ESCAPE KEY_BS, CTRL_H | ESCAPE_STAY             ; the left arrow
    ESCAPE KEY_LF, CTRL_J | ESCAPE_STAY             ; the down arrow
    ESCAPE KEY_CTRL_K, CTRL_UNDERSCORE | ESCAPE_STAY ; the up arrow
    ESCAPE KEY_RIGHT, CTRL_BACKSLASH | ESCAPE_STAY  ; the right arrow
ESCAPE_COUNT = ESCAPES

ESCCODES:
.repeat ESCAPES, index
    .byte .ident(.sprintf("ESCAPE_CODE_%d", index))
.endrepeat

ESCKEYS:
.repeat ESCAPES, index
    .byte .ident(.sprintf("ESCAPE_KEY_%d", index))
.endrepeat

;; Unless RAMRD already reads aux, writes $EE to aux $0C00 and $0800 (leaving RAMRD/RAMWRT on aux)
;; and compares $0C00.
;; Out:   zero = set when aux memory holds the value
AUXRAMTEST:
    bit RDRAMRD                     ; $C98D
    bmi AUXRAMTEST_1                ; $C990
    lda #$EE                        ; $C992
    sta WRCARDRAM                   ; $C994
    sta RDCARDRAM                   ; $C997
    sta $0C00                       ; $C99A
    sta $0800                       ; $C99D
    cmp $0C00                       ; $C9A0

AUXRAMTEST_1:
    rts                             ; $C9A3

;; The letters J, K, M, I that function 1 substitutes for the arrow keys in ARROWKEYS.
ARROWLETTERS:
    .byte "JKMI"                    ; $C9A4
.assert * - ARROWLETTERS = ARROWS, "Each arrow key needs a letter."
    .byte $00, $00                  ; $C9A8

;; A fixed entry: writes the current character ($067B) through PASWRITE (apparently an older Pascal
;; write entry).
C9ENTRY:
    lda CHAR                        ; $C9AA
    jmp PASWRITE                    ; $C9AD

;; Reached from C8ENTRY; appears to be an older Pascal initialization entry.
C9PASINIT:
    lda #$83                        ; $C9B0
    bne C9PASINIT_2                 ; $C9B2

;; Pascal init (mode $81, or $83 from C9PASINIT): without auxiliary text memory returns X = 9. Otherwise
;; $04FB = mode, 80STORE, 80VID and ALTCHAR on, PASRESTORE, clear screen, then PASPUTCHAR's tail
;; (save BASL/BASH, show cursor, X = 0).
;; Out: X = result
C9PASINIT_1:
    lda #$81                        ; $C9B4

C9PASINIT_2:
    pha                             ; $C9B6
    jsr AUXPRESENT                  ; $C9B7
    beq C9PASINIT_3                 ; $C9BA
    pla                             ; $C9BC
    ldx #$09                        ; $C9BD
    rts                             ; $C9BF

;; Pascal init with auxiliary memory present (see C9PASINIT_1).
C9PASINIT_3:
    pla                             ; $C9C0
    sta MODE80                      ; $C9C1
    sta SET80STORE                  ; $C9C4
    sta SET80VID                    ; $C9C7
    sta SETALTCHAR                  ; $C9CA
    jsr PASRESTORE                  ; $C9CD
    jsr CLRSCRN80                   ; $C9D0
    jmp PASPUTCHAR_2                ; $C9D3

;; Pascal read: PASRESTORE, waits for a key, strips bit 7 and keeps it in $067B.
;; Out: A = key, X = 0 (or $C3 when $04FB bit 1 is set)
PASGETKEY:
    jsr PASRESTORE                  ; $C9D6
    jsr GETKEYRND                   ; $C9D9
    and #$7F                        ; $C9DC
    sta CHAR                        ; $C9DE
    ldx #$00                        ; $C9E1
    lda MODE80                      ; $C9E3
    and #$02                        ; $C9E6
    beq PASGETKEY_1                 ; $C9E8
    ldx #$C3                        ; $C9EA

PASGETKEY_1:
    lda CHAR                        ; $C9EC
    rts                             ; $C9EF

;; Pascal write: PASRESTORE, then: a GOTOXY coordinate if $04FB bit 3 is set (PASGOTOXY); a control
;; character through DOCTRL ($1E starts GOTOXY); otherwise stores the character at $057B (normal unless
;; INVFLG says inverse), advances and wraps with LF80. Ends by saving BASL/BASH in $077B/$07FB and
;; showing the cursor.
;; In: A = character
;; Out: X = 0
;; Uses: $057B, $05FB, $06FB, $077B, $07FB, $04FB
PASPUTCHAR:
    and #$7F                        ; $C9F0
    tax                             ; $C9F2
    jsr PASRESTORE                  ; $C9F3
    lda #$08                        ; $C9F6
    bit MODE80                      ; $C9F8
    bne PASGOTOXY                   ; $C9FB
    txa                             ; $C9FD
    bit PASPUTCHAR_4                ; $C9FE
    beq PASGOTOXY_1                 ; $CA01
    ldy OURCH                       ; $CA03
    bit INVFLG                      ; $CA06
    bpl PASPUTCHAR_1                ; $CA08
    ora #$80                        ; $CA0A

PASPUTCHAR_1:
    jsr PUTSCRCHAR                  ; $CA0C
    iny                             ; $CA0F
    sty OURCH                       ; $CA10
    cpy WNDWDTH                     ; $CA13
    bcc PASPUTCHAR_2                ; $CA15
    lda #$00                        ; $CA17
    sta OURCH                       ; $CA19
    jsr LF80                        ; $CA1C

PASPUTCHAR_2:
    lda BASL                        ; $CA1F save base address and show cursor
    sta OLDBASL                     ; $CA21
    lda BASH                        ; $CA24
    sta OLDBASH                     ; $CA26

PASPUTCHAR_3:
    jsr FLIPCURSOR                  ; $CA29
    ldx #$00                        ; $CA2C

PASPUTCHAR_4:
    rts                             ; $CA2E

;; Pascal GOTOXY coordinate: the first byte after $1E (minus $20) goes to $06FB, the second becomes CV;
;; then $057B = $06FB and $04FB bit 3 is cleared. PASGOTOXY_1 ($CA53) handles other control characters.
;; In: X = character
PASGOTOXY:
    jsr FLIPCURSOR                  ; $CA2F
    txa                             ; $CA32
    sec                             ; $CA33
    sbc #$20                        ; $CA34
    bit XCOORD                      ; $CA36
    bmi PASGOTOXY_3                 ; $CA39
    sta OURCV                       ; $CA3B
    sta CV                          ; $CA3E
    jsr ROWBASE                     ; $CA40
    lda XCOORD                      ; $CA43
    sta OURCH                       ; $CA46
    lda #$F7                        ; $CA49
    and MODE80                      ; $CA4B
    sta MODE80                      ; $CA4E
    bne PASPUTCHAR_2                ; $CA51

PASGOTOXY_1:
    jsr FLIPCURSOR                  ; $CA53 control characters
    txa                             ; $CA56
    cmp #CTRL_CARET                 ; $CA57 GOTOXY
    beq PASGOTOXY_2                 ; $CA59
    jsr DOCTRL_1                    ; $CA5B
    jmp PASPUTCHAR_2                ; $CA5E

; Pascal ctrl-^ (GOTOXY): sets $04FB bit 3 and $06FB = $FF to wait for the X coordinate.

PASGOTOXY_2:
    lda #$08                        ; $CA61
    ora MODE80                      ; $CA63
    sta MODE80                      ; $CA66
    lda #$FF                        ; $CA69

PASGOTOXY_3:
    sta XCOORD                      ; $CA6B
    jmp PASPUTCHAR_3                ; $CA6E

;; Disassembler: turns a masked opcode into a mnemonic index by shifting (the second half of the
;; Monitor's INSDS2 work).
;; In: A = opcode and $8F, BAS2L = opcode
;; Out: A = mnemonic index
MNEMINDEX:
    tax                             ; $CA71
    lda BAS2L                       ; $CA72
    ldy #$03                        ; $CA74
    cpx #$8A                        ; $CA76
    beq MNEMINDEX_3                 ; $CA78

MNEMINDEX_1:
    lsr a                           ; $CA7A
    bcc MNEMINDEX_3                 ; $CA7B
    lsr a                           ; $CA7D

MNEMINDEX_2:
    lsr a                           ; $CA7E
    ora #$20                        ; $CA7F
    dey                             ; $CA81
    bne MNEMINDEX_2                 ; $CA82
    iny                             ; $CA84

MNEMINDEX_3:
    dey                             ; $CA85
    bne MNEMINDEX_1                 ; $CA86
    rts                             ; $CA88

;; Calls the Monitor's $F8B7, which compares slot 3's $C305/$C307 bytes with $38/$18 (repeated Y times).
;; On a match returns with Z clear; otherwise returns AUXPRESENT's result.
;; Out:   zero = set to use the internal $C3 ROM
SLOT3CHECK:
    jsr $F8B7                       ; $CA89
    bne AUXPRESENT                  ; $CA8C
    iny                             ; $CA8E
    rts                             ; $CA8F

;; Tests for auxiliary text memory: with 80STORE and HISCR writes $88 to $0400, reads it back and
;; restores the old byte, PAGE2 and 80STORE.
;; Out:   zero = set when aux memory kept the value
AUXPRESENT:
    lda RDPAGE2                     ; $CA90
    asl a                           ; $CA93
    lda #$88                        ; $CA94
    bit RD80STORE                   ; $CA96
    sta SET80STORE                  ; $CA99
    php                             ; $CA9C
    sta HISCR                       ; $CA9D
    ldy LINE1                       ; $CAA0
    sta LINE1                       ; $CAA3
    lda LINE1                       ; $CAA6
    sty LINE1                       ; $CAA9
    plp                             ; $CAAC
    bcs AUXPRESENT_1                ; $CAAD
    sta LOWSCR                      ; $CAAF

AUXPRESENT_1:
    bmi AUXPRESENT_2                ; $CAB2
    sta KBD                         ; $CAB4

AUXPRESENT_2:
    cmp #$88                        ; $CAB7
    rts                             ; $CAB9

;; Text base address of row A in BASL/BASH (no window offset).
;; In: A = row
;; Out:   BASL/BASH = the line's base address, carry = clear
ROWBASE:
    pha                             ; $CABA
    lsr a                           ; $CABB
    and #$03                        ; $CABC
    ora #$04                        ; $CABE
    sta BASH                        ; $CAC0
    pla                             ; $CAC2
    and #$18                        ; $CAC3
    bcc ROWBASE_1                   ; $CAC5
    adc #$7F                        ; $CAC7

ROWBASE_1:
    sta BASL                        ; $CAC9
    asl a                           ; $CACB
    asl a                           ; $CACC
    ora BASL                        ; $CACD
    sta BASL                        ; $CACF
    rts                             ; $CAD1

;; Runs the control character in A through CTRLPAGE and CTRLLOW. $CAD2 (V set) is for BASIC output:
;; codes without CTRL_ALWAYS are skipped when $04FB bit 3 or 5 is set. $CAD6 (V clear) always runs
;; them.
;; In: A = control code ($05-$1F have handlers)
;; Out:   carry = clear when handled, set when ignored
;; Keeps: A, Y
;; Uses: $077B
DOCTRL:
    bit DOCTRL_6                    ; $CAD2 the bit of an rts opcode sets V
    .byte $50                       ; $CAD5 bvc: skips the next byte

DOCTRL_1:
    clv                             ; $CAD6 entry with V clear
    sta OLDBASL                     ; $CAD7
    pha                             ; $CADA
    tya                             ; $CADB
    pha                             ; $CADC
    ldy OLDBASL                     ; $CADD
    cpy #CTRL_FIRST                 ; $CAE0
    bcc DOCTRL_2                    ; $CAE2
    lda CTRLPAGE,y                  ; $CAE4
    beq DOCTRL_2                    ; $CAE7
    bvc DOCTRL_4                    ; $CAE9
    bmi DOCTRL_4                    ; $CAEB
    sta OLDBASL                     ; $CAED
    lda MODE80                      ; $CAF0
    and #$28                        ; $CAF3
    beq DOCTRL_3                    ; $CAF5

DOCTRL_2:
    sec                             ; $CAF7
    bcs DOCTRL_5                    ; $CAF8

DOCTRL_3:
    lda OLDBASL                     ; $CAFA

DOCTRL_4:
    ora #$80                        ; $CAFD
    jsr CTRLJUMP                    ; $CAFF
    clc                             ; $CB02

DOCTRL_5:
    pla                             ; $CB03
    tay                             ; $CB04
    pla                             ; $CB05

DOCTRL_6:
    rts                             ; $CB06

;; Pushes A (handler page) and the handler's low byte from CTRLLOW, and returns into the handler.
;; In: A = handler high byte, Y = control code (CTRL_FIRST or more)
CTRLJUMP:
    pha                             ; $CB07
    lda CTRLLOW - CTRL_FIRST,y      ; $CB08
    pha                             ; $CB0B
    rts                             ; $CB0C

;; Ctrl-E: in Pascal mode clears $04FB bit 4 (cursor shown).
CURSORON:
    lda MODE80                      ; $CB0D
    bpl CURSORON_2                  ; $CB10
    and #$EF                        ; $CB12

CURSORON_1:
    sta MODE80                      ; $CB14

CURSORON_2:
    rts                             ; $CB17

;; Ctrl-F: in Pascal mode sets $04FB bit 4 (cursor hidden).
CURSOROFF:
    lda MODE80                      ; $CB18
    bpl CURSORON_2                  ; $CB1B
    ora #$10                        ; $CB1D
    bne CURSORON_1                  ; $CB1F

;; Ctrl-G: a beep made of DELAYA pauses and SPKR toggles.
BELL80:
    lda #$40                        ; $CB21
    jsr DELAYA                      ; $CB23
    ldy #$C0                        ; $CB26

BELL80_1:
    lda #$0C                        ; $CB28
    jsr DELAYA                      ; $CB2A
    lda SPKR                        ; $CB2D
    dey                             ; $CB30
    bne BELL80_1                    ; $CB31
    rts                             ; $CB33

;; Delay loop of about A*A iterations.
;; In: A = count
;; Out: A = 0
DELAYA:
    sec                             ; $CB34

DELAYA_1:
    pha                             ; $CB35

DELAYA_2:
    sbc #$01                        ; $CB36
    bne DELAYA_2                    ; $CB38
    pla                             ; $CB3A
    sbc #$01                        ; $CB3B
    bne DELAYA_1                    ; $CB3D
    rts                             ; $CB3F

;; Ctrl-H: moves $057B left, wrapping to the end of the previous line (UP80).
BACKSPC80:
    dec OURCH                       ; $CB40
    bpl BACKSPC80_1                 ; $CB43
    lda WNDWDTH                     ; $CB45
    sta OURCH                       ; $CB47
    dec OURCH                       ; $CB4A
    jsr UP80                        ; $CB4D

BACKSPC80_1:
    rts                             ; $CB50

;; Ctrl-M: $057B = 0, then LF80 unless in Pascal mode.
CR80:
    lda #$00                        ; $CB51
    sta OURCH                       ; $CB53
    lda MODE80                      ; $CB56
    bmi CR80_1                      ; $CB59
    jsr LF80                        ; $CB5B

CR80_1:
    rts                             ; $CB5E

;; Ctrl-Y: CV = WNDTOP, $057B = 0, VTAB80.
HOMECURSOR:
    lda WNDTOP                      ; $CB5F
    sta CV                          ; $CB61
    lda #$00                        ; $CB63
    sta OURCH                       ; $CB65
    jmp VTAB80                      ; $CB68

;; Ctrl-\: moves $057B right, wrapping with CR80.
FWDSPACE80:
    inc OURCH                       ; $CB6B
    lda OURCH                       ; $CB6E
    cmp WNDWDTH                     ; $CB71
    bcc FWDSPACE80_1                ; $CB73
    jsr CR80                        ; $CB75

FWDSPACE80_1:
    rts                             ; $CB78

;; Ctrl-_: moves CV up one unless already at WNDTOP, then VTAB80.
UP80:
    lda WNDTOP                      ; $CB79
    cmp CV                          ; $CB7B
    bcs SETINVFLG_1                 ; $CB7D
    dec CV                          ; $CB7F
    jmp VTAB80                      ; $CB81

;; Ctrl-N: INVFLG = $FF (and clears $04FB bit 2 in Pascal mode). INVERSE80 is ctrl-O: INVFLG = $7F
;; (and sets bit 2 in Pascal mode).
NORMAL80:
    lda MODE80                      ; $CB84
    bpl NORMAL80_1                  ; $CB87
    and #$FB                        ; $CB89

NORMAL80_1:
    ldy #$FF                        ; $CB8B
    bne SETINVFLG                   ; $CB8D

INVERSE80:
    lda MODE80                      ; $CB8F
    bpl INVERSE80_1                 ; $CB92
    ora #$04                        ; $CB94

INVERSE80_1:
    ldy #$7F                        ; $CB96

SETINVFLG:
    sta MODE80                      ; $CB98
    sty INVFLG                      ; $CB9B

;; Return used by UP80.
SETINVFLG_1:
    rts                             ; $CB9D

;; The control character handlers, for DOCTRL. Each handler's address-1 is split: the low byte in
;; CTRLLOW, the page in CTRLPAGE with bit 7 replaced by CTRL_ALWAYS (run even while $04FB disables
;; control characters); a zero page byte means no handler. Codes below CTRL_FIRST have none, so
;; CTRLPAGE's first entries are never read, and the end of CTRLLOW overlaps them.
CTRL_FIRST = CTRL_E
CTRL_ALWAYS = $80                   ;; CTRLPAGE flag: the handler runs even while control characters are disabled

.macro CTRL code, handler, flags
    .assert >(handler - 1) >= $80, "A control handler's page must have bit 7 set."
    .ident(.sprintf("CTRL_LOW_%d", code)) = <(handler - 1)
    .ident(.sprintf("CTRL_PAGE_%d", code)) = (>(handler - 1) & $7F) | flags
.endmacro

.macro NOCTRL code
    .ident(.sprintf("CTRL_LOW_%d", code)) = 0
    .ident(.sprintf("CTRL_PAGE_%d", code)) = 0
.endmacro

    CTRL CTRL_E, CURSORON, 0                        ; Pascal: show the cursor
    CTRL CTRL_F, CURSOROFF, 0                       ; Pascal: hide the cursor
    CTRL CTRL_G, BELL80, CTRL_ALWAYS                ; bell
    CTRL CTRL_H, BACKSPC80, CTRL_ALWAYS             ; left
    NOCTRL $09
    CTRL CTRL_J, LF80, CTRL_ALWAYS                  ; down (line feed)
    CTRL CTRL_K, CLREOP80, 0                        ; clear to the end of the screen
    CTRL CTRL_L, CLRSCRN80, 0                       ; clear the screen
    CTRL CTRL_M, CR80, CTRL_ALWAYS                  ; return
    CTRL CTRL_N, NORMAL80, 0                        ; normal text
    CTRL CTRL_O, INVERSE80, 0                       ; inverse text
    NOCTRL $10
    CTRL CTRL_Q, SET40COL, 0                        ; 40 columns
    CTRL CTRL_R, SET80COL, 0                        ; 80 columns
    NOCTRL $13
    NOCTRL $14
    CTRL CTRL_U, QUIT80, 0                          ; quit the 80-column firmware
    CTRL CTRL_V, SCROLLDN80, 0                      ; scroll down
    CTRL CTRL_W, SCROLLUP80, 0                      ; scroll up
    CTRL CTRL_X, MTEXTOFF, 0                        ; MouseText off
    CTRL CTRL_Y, HOMECURSOR, 0                      ; home the cursor
    CTRL CTRL_Z, CLRLINE80, 0                       ; clear the line
    CTRL CTRL_ESC, MTEXTON, 0                       ; MouseText on
    CTRL CTRL_BACKSLASH, FWDSPACE80, 0              ; right
    CTRL CTRL_RBRACKET, CLREOL80, 0                 ; clear to the end of the line
    NOCTRL CTRL_CARET
    CTRL CTRL_UNDERSCORE, UP80, 0                   ; up

;; Low bytes for codes CTRL_FIRST up; the last CTRL_FIRST of them are the start of CTRLPAGE.
CTRLLOW:
.repeat 32 - 2 * CTRL_FIRST, index
    .byte .ident(.sprintf("CTRL_LOW_%d", CTRL_FIRST + index))
.endrepeat

;; Pages for codes 0-31.
CTRLPAGE:
.repeat CTRL_FIRST, index
    .byte .ident(.sprintf("CTRL_LOW_%d", 32 - CTRL_FIRST + index))
.endrepeat
.repeat 32 - CTRL_FIRST, index
    .byte .ident(.sprintf("CTRL_PAGE_%d", CTRL_FIRST + index))
.endrepeat

;; Ctrl-V: scrolls the window down a line.
SCROLLDN80:
    ldy #$00                        ; $CBD4
    beq SCROLL80_2                  ; $CBD6

;; Ctrl-J: moves CV down (and $05FB); at WNDBTM scrolls with SCROLL80.
LF80:
    inc CV                          ; $CBD8
    lda CV                          ; $CBDA
    sta OURCV                       ; $CBDC
    cmp WNDBTM                      ; $CBDF
    bcs SCROLL80                    ; $CBE1
    jmp VTAB80_1                    ; $CBE3

;; LF80 at the bottom: backs CV and $05FB up one, then scrolls up. SCROLLUP80 (Y = 1, ctrl-W) scrolls
;; the window up, SCROLL80_2 with Y = 0 (from SCROLLDN80, ctrl-V) scrolls it down: each line is copied
;; from its neighbor, with 80VID the aux half (HISCR) and main half are copied separately (WNDWDTH is
;; temporarily halved, adjusted for an odd WNDLFT), then the new line is cleared and BASL recomputed.
;; Keeps: X
;; Uses: BAS2L/BAS2H, $077B (direction), WNDWDTH (restored)
SCROLL80:
    dec OURCV                       ; $CBE6
    dec CV                          ; $CBE9

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

;; Inverts the character at column $057B unless $04FB bit 4 (cursor off) is set; FLIPCURSOR_1 always does.
;; Out:   A = $10 when the character is skipped
;; Keeps: A, Y (when the character is inverted)
FLIPCURSOR:
    lda MODE80                      ; $CE1F
    and #$10                        ; $CE22
    bne FLIPCURSOR_2                ; $CE24

FLIPCURSOR_1:
    pha                             ; $CE26 invert regardless of bit 4
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
