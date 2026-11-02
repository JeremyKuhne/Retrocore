;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ORIGINAL IIE
;;
;; Layout of the original IIe's internal $C100-$CFFF ROM:
;;   $C100-$C2FF  Screen and keyboard helpers for the Monitor. The Monitor's switch routine at $FBB4 saves P,
;;                sets SETINTCXROM and jumps to $C100 with a function number in Y: 0 CLREOP, 1 HOME, 2 SCROLL,
;;                3 CLREOL, 4 CLREOLZ, 5 reset, 6 KEYIN (blinking cursor), 7 escape-key translation. Functions
;;                0-5 have a 40-column and an 80-column version. All return through F_RETURN ($FD29/$FD2C), which
;;                switches slot ROMs back in unless internal ROM was already in.
;;   $C300-$C3FF  Slot-3 entry points: BASICINT ($C300, PR#3), BASICIN ($C305) and BASICOUT ($C307) for the
;;                KSW/CSW hooks; the Pascal 1.1 ID bytes and PASCALOFS offsets to JPINIT/JPREAD/JPWRITE/
;;                JPSTAT; AUXMOVE and XFER for main/auxiliary memory. Running from $C3xx selects the internal
;;                $C800 ROM; BASICINT/IN/OUT also read $CFFF so no peripheral card's $C800 ROM stays selected.
;;   $C400-$C7FF  Built-in self-test, entered from the reset function when Solid-Apple (BUTN1) is held: MMU and
;;                IOU switch checks, ROM checksums, a RAM test, and a message on failure.
;;   $C800-$CFFF  The body of the 80-column firmware: output, input with escape-mode cursor moves, control
;;                characters, 40/80 conversion, Pascal I/O, and the low-level screen access through 80STORE.
;; The 80-column firmware keeps its state in slot 3's screen holes: $047B last CH it set, $04FB mode
;; flags ($FF = firmware inactive; bit 7 uppercase input, 6 in BASICIN, 5 Pascal, 4 inside quotes, 3 GOTOXY
;; pending, 2 inverse, 0 interrupts allowed), $057B 80-column cursor column, $05FB cursor row, $067B
;; current character, $06FB GOTOXY column, $077B/$07FB saved BASL/BASH. $0478 is scratch.
;;
;; Assembles byte-identically to the internal $C100-$CFFF ROM: the 80-column firmware in slot three's
;; space and $C800, and the routines the Monitor calls with internal ROM switched in. Names are Apple's
;; documented entry points; other labels are named after the routine they are in.
;; It includes IIeEquates.asm (the IIe's page zero, soft switches and keys), MonitorEntries.asm (the Monitor's
;; entry points) and FirmwareEquates.asm (the equates both firmware models share).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Mos6502

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; A screen hole only this model's firmware uses.
TEMP1 = $0478                       ;; 80-column firmware: scratch (slot-3 screen hole)

; The expansion ROM switch, a label in the Enhanced IIe's firmware, so not in IIeEquates.asm.
;; Inherit: <Monitor:CLRROM>
CLRROM = $CFFF

; More characters with bit 7 set. CTLCHAR and Pascal take control characters with bit 7 clear, written KEY_x & $7F.
KEY_FF = $8C                        ;; Control-L: home and clear
KEY_CTRL_Q = $91                    ;; 40 columns
KEY_CTRL_R = $92                    ;; 80 columns
KEY_FS = $9C                        ;; Control-\: cursor right
KEY_GS = $9D                        ;; Control-]: clear to the end of the line
KEY_GOTOXY = $9E                    ;; Control-^: Pascal's GOTOXY
KEY_US = $9F                        ;; Control-_: cursor up

.org $C100

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

;; BASICINT, the PR#3 entry: sets V (the byte at $FF58 is an RTS) and enters the common BASIC entry, which
;; initializes the 80-column firmware and then prints A.
BASICINT:
    bit IORTS                       ; $C300
    bvs BASICENT                    ; $C303

;; BASICIN, the input hook (KSW): carry set, V clear. The SEC here and the CLC at $C307 are also the $38 and
;; $18 bytes a Pascal 1.1 card is identified by.
BASICIN:
    sec                             ; $C305
    .byte $90                       ; $C306 bcc: skips the next byte

;; BASICOUT, the output hook (CSW): carry clear, V clear.
BASICOUT:
    clc                             ; $C307
    clv                             ; $C308
    bvc BASICENT                    ; $C309

;; Pascal 1.1 firmware ID: $01 marks the protocol, $88 is the device signature byte.
PASCALID:
    .byte $01, $88                  ; $C30B

;; Pascal 1.1 entry offsets into page $C3: init $C34B, read $C351, write $C357, status $C35D.
PASCALOFS:
    .byte <JPINIT, <JPREAD, <JPWRITE, <JPSTAT ; $C30D

;; AUXMOVE: copies memory between main and auxiliary RAM (C3_MOVE).
AUXMOVE:
    jmp C3_MOVE                     ; $C311

;; XFER: transfers control to an address in main or auxiliary memory (C3_XFER).
XFER:
    jmp C3_XFER                     ; $C314

;; Common entry for BASICINT, BASICIN and BASICOUT. Saves A in $067B and pushes A, Y, X and P. Sets mode
;; bit 0 if the caller had interrupts enabled. Copies CV to $05FB and sets MSLOT to $C3. V set goes to
;; BASICINIT, otherwise to the shared input/output path at C8BASIC (carry set = input).
;; In: A = character, C/V as set by the entry
BASICENT:
    sta CHAR                        ; $C317
    pha                             ; $C31A
    tya                             ; $C31B
    pha                             ; $C31C
    txa                             ; $C31D
    pha                             ; $C31E
    php                             ; $C31F
    lda MODE80                      ; $C320
    and #$FE                        ; $C323
    sta MODE80                      ; $C325
    pla                             ; $C328
    pha                             ; $C329
    and #$04                        ; $C32A
    bne BASICENT2                   ; $C32C
    lda MODE80                      ; $C32E
    ora #$01                        ; $C331
    sta MODE80                      ; $C333

BASICENT2:
    lda CLRROM                      ; $C336 reading $CFFF releases every $C800 ROM; the next fetch from $C3xx selects the internal one again
    lda CV                          ; $C339
    sta OURCV                       ; $C33B
    jsr SETC8                       ; $C33E
    plp                             ; $C341
    php                             ; $C342
    bvs JBASINIT                    ; $C343
    jmp C8BASIC                     ; $C345

;; Path for BASICINT: jumps to BASICINIT.
JBASINIT:
    jmp BASICINIT                   ; $C348

;; Pascal init entry (offset $4B): sets MSLOT and jumps to PINIT.
JPINIT:
    jsr SETC8                       ; $C34B
    jmp PINIT                       ; $C34E

;; Pascal read entry (offset $51): sets MSLOT and jumps to C8_PREAD.
JPREAD:
    jsr SETC8                       ; $C351
    jmp C8_PREAD                    ; $C354

;; Pascal write entry (offset $57): sets MSLOT and jumps to PWRITE.
JPWRITE:
    jsr SETC8                       ; $C357
    jmp PWRITE                      ; $C35A

;; Pascal status entry (offset $5D): sets MSLOT and jumps to PSTATUS.
JPSTAT:
    jsr SETC8                       ; $C35D
    jmp PSTATUS                     ; $C360

;; Body of AUXMOVE: copies A1L/A1H through A2L/A2H to A4L/A4H. Carry set copies main to auxiliary memory
;; (reads main, writes card), carry clear copies auxiliary to main. Restores RAMRD and RAMWRT afterwards.
;; In: A1 = source start, A2 = source end, A4 = destination, carry = direction
;; Out: A1 = A2+1, A4 advanced past the copy
;; Keeps: A, Y
C3_MOVE:
    pha                             ; $C363
    tya                             ; $C364
    pha                             ; $C365
    lda RDRAMRD                     ; $C366
    pha                             ; $C369
    lda RDRAMWRT                    ; $C36A
    pha                             ; $C36D
    bcc MOVEC2M                     ; $C36E
    sta RDMAINRAM                   ; $C370
    sta WRCARDRAM                   ; $C373
    bcs MOVESTRT                    ; $C376

MOVEC2M:
    sta WRMAINRAM                   ; $C378
    sta RDCARDRAM                   ; $C37B

MOVESTRT:
    ldy #$00                        ; $C37E

MOVELOOP:
    lda (A1L),y                     ; $C380
    sta (A4L),y                     ; $C382
    inc A4L                         ; $C384
    bne C3_NXTA1                    ; $C386
    inc A4H                         ; $C388

C3_NXTA1:
    lda A1L                         ; $C38A
    cmp A2L                         ; $C38C
    lda A1H                         ; $C38E
    sbc A2H                         ; $C390
    inc A1L                         ; $C392
    bne C01                         ; $C394
    inc A1H                         ; $C396

C01:
    bcc MOVELOOP                    ; $C398
    sta WRMAINRAM                   ; $C39A
    pla                             ; $C39D
    bpl C03                         ; $C39E
    sta WRCARDRAM                   ; $C3A0

C03:
    sta RDMAINRAM                   ; $C3A3
    pla                             ; $C3A6
    bpl MOVERET                     ; $C3A7
    sta RDCARDRAM                   ; $C3A9

MOVERET:
    pla                             ; $C3AC
    tay                             ; $C3AD
    pla                             ; $C3AE
    rts                             ; $C3AF

;; Body of XFER: jumps to the address in $03ED/$03EE with main (carry clear) or auxiliary (carry set) memory
;; selected for reading and writing, and the standard (V clear) or alternate (V set) zero page and stack.
;; Keeps: A
C3_XFER:
    pha                             ; $C3B0
    lda $03ED                       ; $C3B1 the address is pushed and pulled back so it is stored again into the newly selected bank
    pha                             ; $C3B4
    lda $03EE                       ; $C3B5
    pha                             ; $C3B8
    bcc XFERC2M                     ; $C3B9
    sta RDCARDRAM                   ; $C3BB
    sta WRCARDRAM                   ; $C3BE
    bvc XFERSZP                     ; $C3C1
    bvs XFERAZP                     ; $C3C3

XFERC2M:
    sta RDMAINRAM                   ; $C3C5
    sta WRMAINRAM                   ; $C3C8
    bvc XFERSZP                     ; $C3CB

XFERAZP:
    pla                             ; $C3CD
    sta $03EE                       ; $C3CE
    pla                             ; $C3D1
    sta $03ED                       ; $C3D2
    pla                             ; $C3D5
    sta SETALTZP                    ; $C3D6
    jmp ($03ED)                     ; $C3D9

;; XFER with V clear: rewrites $03ED/$03EE, selects the standard zero page and stack and jumps.
XFERSZP:
    pla                             ; $C3DC
    sta $03EE                       ; $C3DD
    pla                             ; $C3E0
    sta $03ED                       ; $C3E1
    pla                             ; $C3E4
    sta SETSTDZP                    ; $C3E5
    jmp ($03ED)                     ; $C3E8

;; Stores $C3 in MSLOT so interrupt handlers know whose $C800 ROM is selected.
;; Keeps: A
SETC8:
    pha                             ; $C3EB
    lda #$C3                        ; $C3EC
    sta MSLOT                       ; $C3EE
    pla                             ; $C3F1
    rts                             ; $C3F2
    .byte $00, $00, $00, $00, $00, $00, $00, $00 ; $C3F3
    .byte $00, $00, $00, $00, $00   ; $C3FB

;; Checksum byte: the self-test expects the sum of $C100-$DFFF, excluding this byte, to equal it.
CHECKSUM:
    .byte $1B                       ; $C400

;; Built-in self-test, from B_RESETX with Solid-Apple held. Resets the stack, sends output to COUT1, homes the
;; screen, then checks the MMU status flags ($C011-$C018) against MMUFLAGS and toggles each MMU switch and
;; reads it back, then does the same for the IOU flags ($C01A-$C01F, IOUFLAGS) and switches. Any error prints
;; a header once and the failing flag number (FLAGERR) and the test hangs; otherwise ROM checksums follow.
;; Uses: $04..$0A, all
;;
;; Never returns.
SELFTEST:
    lda BUTN0                       ; $C401
    sta $05                         ; $C404 Open-Apple also held makes the RAM test click the speaker
    ldx #$FF                        ; $C406
    txs                             ; $C408
    lda #<COUT1                     ; $C409
    sta CSWL                        ; $C40B
    lda #>COUT1                     ; $C40D
    sta CSWH                        ; $C40F
    lda LCROM                       ; $C411
    jsr HOME                        ; $C414
    lda #$00                        ; $C417
    sta $09                         ; $C419
    sta $0A                         ; $C41B
    sta $08                         ; $C41D
    tax                             ; $C41F

SELFTEST_1:
    lda RDLCBNK2,x                  ; $C420
    eor MMUFLAGS,x                  ; $C423
    bpl SELFTEST_2                  ; $C426
    jsr FLAGERR                     ; $C428

SELFTEST_2:
    inx                             ; $C42B
    cpx #$08                        ; $C42C
    bne SELFTEST_1                  ; $C42E
    sta LCBANK1                     ; $C430
    bit RDLCBNK2                    ; $C433
    sta LCBANK2                     ; $C436
    bpl SELFTEST_3                  ; $C439
    jsr FLAGERR                     ; $C43B

SELFTEST_3:
    inx                             ; $C43E
    sta LCRAM2                      ; $C43F
    bit RDLCRAM                     ; $C442
    sta LCROM                       ; $C445
    bmi SELFTEST_4                  ; $C448
    jsr FLAGERR                     ; $C44A

SELFTEST_4:
    inx                             ; $C44D
    sta RDCARDRAM                   ; $C44E
    bit RDRAMRD                     ; $C451
    sta RDMAINRAM                   ; $C454
    bmi SELFTEST_5                  ; $C457
    jsr FLAGERR                     ; $C459

SELFTEST_5:
    inx                             ; $C45C
    sta WRCARDRAM                   ; $C45D
    bit RDRAMWRT                    ; $C460
    sta WRMAINRAM                   ; $C463
    bmi SELFTEST_6                  ; $C466
    jsr FLAGERR                     ; $C468

SELFTEST_6:
    inx                             ; $C46B
    sta SETALTZP                    ; $C46C
    bit RDALTZP                     ; $C46F
    sta SETSTDZP                    ; $C472
    bmi SELFTEST_7                  ; $C475
    jsr FLAGERR                     ; $C477

SELFTEST_7:
    inx                             ; $C47A
    sta SETSLOTC3ROM                ; $C47B
    bit RDC3ROM                     ; $C47E
    sta SETINTC3ROM                 ; $C481
    bmi SELFTEST_8                  ; $C484
    jsr FLAGERR                     ; $C486

SELFTEST_8:
    inx                             ; $C489
    sta SET80STORE                  ; $C48A
    bit RD80STORE                   ; $C48D
    sta KBD                         ; $C490
    bmi SELFTEST_9                  ; $C493
    jsr FLAGERR                     ; $C495

SELFTEST_9:
    jsr CROUT                       ; $C498
    ldx #$00                        ; $C49B
    lda #$FF                        ; $C49D
    sta $08                         ; $C49F

SELFTEST_10:
    lda RDTEXT,x                    ; $C4A1
    eor IOUFLAGS,x                  ; $C4A4
    bpl SELFTEST_11                 ; $C4A7
    jsr FLAGERR                     ; $C4A9

SELFTEST_11:
    inx                             ; $C4AC
    cpx #$06                        ; $C4AD
    bne SELFTEST_10                 ; $C4AF
    sta SET80VID                    ; $C4B1
    bit RD80VID                     ; $C4B4
    sta CLR80VID                    ; $C4B7
    bmi SELFTEST_12                 ; $C4BA
    jsr FLAGERR                     ; $C4BC

SELFTEST_12:
    inx                             ; $C4BF
    sta SETALTCHAR                  ; $C4C0
    bit RDALTCHAR                   ; $C4C3
    sta CLRALTCHAR                  ; $C4C6
    bmi SELFTEST_13                 ; $C4C9
    jsr FLAGERR                     ; $C4CB

SELFTEST_13:
    inx                             ; $C4CE
    sta TXTCLR                      ; $C4CF
    bit RDTEXT                      ; $C4D2
    sta TXTSET                      ; $C4D5
    bpl SELFTEST_14                 ; $C4D8
    jsr FLAGERR                     ; $C4DA

SELFTEST_14:
    inx                             ; $C4DD
    sta HISCR                       ; $C4DE
    bit RDPAGE2                     ; $C4E1
    sta LOWSCR                      ; $C4E4
    bmi SELFTEST_15                 ; $C4E7
    jsr FLAGERR                     ; $C4E9

SELFTEST_15:
    inx                             ; $C4EC
    sta MIXSET                      ; $C4ED
    bit RDMIXED                     ; $C4F0
    sta MIXCLR                      ; $C4F3
    bmi SELFTEST_16                 ; $C4F6
    jsr FLAGERR                     ; $C4F8

SELFTEST_16:
    inx                             ; $C4FB
    sta HIRES                       ; $C4FC
    bit RDHIRES                     ; $C4FF
    sta LORES                       ; $C502
    bmi SELFTEST_17                 ; $C505
    jsr FLAGERR                     ; $C507

SELFTEST_17:
    lda $09                         ; $C50A
    ora $0A                         ; $C50C
    beq ROMSUM1                     ; $C50E

SELFTEST_18:
    jmp SELFTEST_18                 ; $C510

;; Reports a failed switch flag: prints "MMU FLAG E4:" (while $08 = 0) or "IOU FLAG E5:" once, then the flag
;; number in hex and a space.
;; In: X = flag number, $08 = 0 for MMU, nonzero for IOU.
;; Out: $09/$0A = set to mark the error
;; Keeps: X
FLAGERR:
    stx $04                         ; $C513
    lda $08                         ; $C515
    bne FLAGERR_1                   ; $C517
    lda $09                         ; $C519
    bne FLAGERR_2                   ; $C51B
    ldx #MSGMMU - TESTMSGS          ; $C51D
    jsr TESTMSG                     ; $C51F
    inc $09                         ; $C522
    bne FLAGERR_2                   ; $C524

FLAGERR_1:
    lda $0A                         ; $C526
    bne FLAGERR_2                   ; $C528
    ldx #MSGIOU - TESTMSGS          ; $C52A
    jsr TESTMSG                     ; $C52C
    inc $0A                         ; $C52F

FLAGERR_2:
    lda $04                         ; $C531
    jsr PRHEX                       ; $C533
    lda #' '                        ; $C536
    jsr COUT1                       ; $C538
    lda $04                         ; $C53B
    tax                             ; $C53D
    rts                             ; $C53E

;; First ROM checksum: adds $C100-$DFFF (skipping $C400) and compares with $C400. On a mismatch prints
;; "ROM:E8" and hangs.
;; Uses: LOC0/LOC1, A, X, Y.
ROMSUM1:
    lda #$C1                        ; $C53F
    sta LOC1                        ; $C541
    lda #$00                        ; $C543
    sta LOC0                        ; $C545
    tay                             ; $C547

ROMSUM1_1:
    clc                             ; $C548
    adc (LOC0),y                    ; $C549
    iny                             ; $C54B
    bne ROMSUM1_1                   ; $C54C
    inc LOC1                        ; $C54E
    ldx LOC1                        ; $C550
    cpx #$C4                        ; $C552
    bne ROMSUM1_2                   ; $C554
    iny                             ; $C556
    bne ROMSUM1_1                   ; $C557

ROMSUM1_2:
    cpx #$E0                        ; $C559
    beq ROMSUM1_3                   ; $C55B
    bne ROMSUM1_1                   ; $C55D

ROMSUM1_3:
    cmp CHECKSUM                    ; $C55F
    beq ROMSUM2                     ; $C562
    ldx #MSGROM1 - TESTMSGS         ; $C564
    jsr TESTMSG                     ; $C566

ROMSUM1_4:
    jmp ROMSUM1_4                   ; $C569

;; Second ROM checksum: adds $E000-$FFFF (skipping $F7FF) and compares with $F7FF. On a mismatch prints
;; "ROM:E10" and hangs.
ROMSUM2:
    ldy #$00                        ; $C56C
    tya                             ; $C56E

ROMSUM2_1:
    clc                             ; $C56F
    adc (LOC0),y                    ; $C570
    iny                             ; $C572
    beq ROMSUM2_2                   ; $C573
    cpy #$FF                        ; $C575
    bne ROMSUM2_1                   ; $C577
    ldx LOC1                        ; $C579
    cpx #$F7                        ; $C57B
    bne ROMSUM2_1                   ; $C57D
    iny                             ; $C57F

ROMSUM2_2:
    inc LOC1                        ; $C580
    bne ROMSUM2_1                   ; $C582
    cmp $F7FF                       ; $C584
    beq RAMTEST                     ; $C587
    ldx #MSGROM2 - TESTMSGS         ; $C589
    jsr TESTMSG                     ; $C58B

ROMSUM2_3:
    jmp ROMSUM2_3                   ; $C58E

;; RAM test, shown on the hi-res screen: fills $0006-$BFFF, $D000-$DFFF in both language card banks and
;; $E000-$FFFF with 0, then makes passes upward and downward that check each byte holds the expected value
;; and replace it with its complement. Clicks the speaker per page when $05 bit 7 is set.
;; Uses: LOC0/LOC1 (the pointer), $02 (the expected value), $03 (lower limit), $04 (read/write marker), X
RAMTEST:
    lda TXTCLR                      ; $C591
    lda HIRES                       ; $C594
    lda MIXCLR                      ; $C597
    lda LCBANK2                     ; $C59A
    lda LCBANK2                     ; $C59D
    lda #$01                        ; $C5A0
    sta $04                         ; $C5A2
    lda #$FF                        ; $C5A4
    sta $03                         ; $C5A6
    lda #$00                        ; $C5A8
    tax                             ; $C5AA
    sta LOC0                        ; $C5AB
    sta LOC1                        ; $C5AD
    ldy #$06                        ; $C5AF

RAMTEST_1:
    sta (LOC0),y                    ; $C5B1
    iny                             ; $C5B3
    bne RAMTEST_1                   ; $C5B4
    bit $05                         ; $C5B6
    bpl RAMTEST_2                   ; $C5B8
    sta SPKR                        ; $C5BA

RAMTEST_2:
    inc LOC1                        ; $C5BD
    beq RAMTEST_6                   ; $C5BF
    lda LOC1                        ; $C5C1
    cmp #$C0                        ; $C5C3
    bne RAMTEST_3                   ; $C5C5
    lda #$D0                        ; $C5C7
    sta LOC1                        ; $C5C9
    bmi RAMTEST_5                   ; $C5CB

RAMTEST_3:
    cmp #$E0                        ; $C5CD
    bne RAMTEST_5                   ; $C5CF
    bit RDLCBNK2                    ; $C5D1
    bpl RAMTEST_4                   ; $C5D4
    lda LCBANK1                     ; $C5D6
    lda LCBANK1                     ; $C5D9
    lda #$D0                        ; $C5DC
    sta LOC1                        ; $C5DE
    bmi RAMTEST_5                   ; $C5E0

RAMTEST_4:
    lda LCBANK2                     ; $C5E2
    lda LCBANK2                     ; $C5E5

RAMTEST_5:
    txa                             ; $C5E8
    beq RAMTEST_1                   ; $C5E9

RAMTEST_6:
    sta $02                         ; $C5EB
    eor #$FF                        ; $C5ED
    tax                             ; $C5EF

RAMTEST_7:
    lda #$00                        ; $C5F0
    sta LOC1                        ; $C5F2
    ldy #$06                        ; $C5F4

RAMTEST_8:
    bit $05                         ; $C5F6
    bpl RAMTEST_9                   ; $C5F8
    sta SPKR                        ; $C5FA

RAMTEST_9:
    dec $04                         ; $C5FD
    lda (LOC0),y                    ; $C5FF
    cmp $02                         ; $C601
    beq RAMUP                       ; $C603
    jmp RAMFAIL                     ; $C605

;; RAM test, upward pass: writes the complement, verifies it and advances, switching language card banks at
;; $D000/$E000.
RAMUP:
    inc $04                         ; $C608
    txa                             ; $C60A
    sta (LOC0),y                    ; $C60B
    cmp (LOC0),y                    ; $C60D
    beq RAMUPNEXT                   ; $C60F
    jmp RAMFAIL                     ; $C611

;; RAM test, upward pass: next byte or page.
RAMUPNEXT:
    iny                             ; $C614
    bne RAMTEST_8                   ; $C615
    inc LOC1                        ; $C617
    beq RAMDOWN                     ; $C619
    lda LOC1                        ; $C61B
    cmp #$C0                        ; $C61D
    bne RAMUPNEXT_1                 ; $C61F
    lda #$D0                        ; $C621
    sta LOC1                        ; $C623
    bmi RAMTEST_8                   ; $C625

RAMUPNEXT_1:
    cmp #$E0                        ; $C627
    bne RAMTEST_8                   ; $C629
    bit RDLCBNK2                    ; $C62B
    bpl RAMUPNEXT_2                 ; $C62E
    lda LCBANK1                     ; $C630
    lda LCBANK1                     ; $C633
    lda #$D0                        ; $C636
    sta LOC1                        ; $C638
    bmi RAMTEST_8                   ; $C63A

RAMUPNEXT_2:
    lda LCBANK2                     ; $C63C
    lda LCBANK2                     ; $C63F
    jmp RAMTEST_8                   ; $C642

;; RAM test: start of the downward pass, with the expected value swapped for its complement.
RAMDOWN:
    sta $02                         ; $C645
    eor #$FF                        ; $C647
    tax                             ; $C649
    beq RAMTEST_7                   ; $C64A

RAMDOWN_1:
    lda #$FF                        ; $C64C
    sta LOC1                        ; $C64E
    tay                             ; $C650

RAMDOWN_2:
    bit $05                         ; $C651
    bpl RAMDOWN_3                   ; $C653
    sta SPKR                        ; $C655

RAMDOWN_3:
    dec $04                         ; $C658
    lda (LOC0),y                    ; $C65A
    cmp $02                         ; $C65C
    bne RAMFAIL                     ; $C65E
    inc $04                         ; $C660
    txa                             ; $C662
    sta (LOC0),y                    ; $C663
    cmp (LOC0),y                    ; $C665
    bne RAMFAIL                     ; $C667
    dey                             ; $C669
    cpy $03                         ; $C66A
    bne RAMDOWN_2                   ; $C66C
    dec LOC1                        ; $C66E
    lda LOC1                        ; $C670
    cmp #$FF                        ; $C672
    beq RAMDOWN_7                   ; $C674
    cmp #$CF                        ; $C676
    bne RAMDOWN_5                   ; $C678
    bit RDLCBNK2                    ; $C67A
    bpl RAMDOWN_4                   ; $C67D
    lda LCBANK1                     ; $C67F
    lda LCBANK1                     ; $C682
    lda #$DF                        ; $C685
    sta LOC1                        ; $C687
    bmi RAMDOWN_2                   ; $C689

RAMDOWN_4:
    lda LCBANK2                     ; $C68B
    lda LCBANK2                     ; $C68E
    lda #$BF                        ; $C691
    sta LOC1                        ; $C693
    bmi RAMDOWN_2                   ; $C695

RAMDOWN_5:
    cmp #$00                        ; $C697
    beq RAMDOWN_6                   ; $C699
    bne RAMDOWN_2                   ; $C69B

RAMDOWN_6:
    lda #$06                        ; $C69D
    sta $03                         ; $C69F
    bne RAMDOWN_2                   ; $C6A1

RAMDOWN_7:
    txa                             ; $C6A3
    beq TESTPASS                    ; $C6A4
    sta $02                         ; $C6A6
    sta $03                         ; $C6A8
    eor #$FF                        ; $C6AA
    tax                             ; $C6AC
    beq RAMDOWN_1                   ; $C6AD

;; RAM test failure: switches language card ROM back in, resets the text screen and prints "RAM:",
;; then works out which bits failed (RAMBITS). $04 tells whether the bad byte was found on the read (0)
;; or on the write-back check (1).
RAMFAIL:
    lda LCROM                       ; $C6AF
    jsr TESTSCRN                    ; $C6B2
    lda TXTSET                      ; $C6B5
    ldx #MSGRAM - TESTMSGS          ; $C6B8
    jsr TESTMSG                     ; $C6BA
    lda $04                         ; $C6BD
    beq RAMBITS                     ; $C6BF
    lda $02                         ; $C6C1
    eor #$FF                        ; $C6C3
    eor (LOC0),y                    ; $C6C5
    sta $06                         ; $C6C7
    jmp RAMBITS_1                   ; $C6C9

;; RAM test failure, part two: XORs the expected value with the byte read to find the bad bits ($06), then
;; prints a chip location ("F13" for bit 7 down to "F6" for bit 0) for each, and hangs.
RAMBITS:
    lda $02                         ; $C6CC
    eor (LOC0),y                    ; $C6CE
    sta $06                         ; $C6D0

RAMBITS_1:
    lda $06                         ; $C6D2
    asl a                           ; $C6D4
    bcc RAMBITS_2                   ; $C6D5
    ldx #MSGF13 - TESTMSGS          ; $C6D7
    jsr TESTMSG                     ; $C6D9

RAMBITS_2:
    asl a                           ; $C6DC
    bcc RAMBITS_3                   ; $C6DD
    ldx #MSGF12 - TESTMSGS          ; $C6DF
    jsr TESTMSG                     ; $C6E1

RAMBITS_3:
    asl a                           ; $C6E4
    bcc RAMBITS_4                   ; $C6E5
    ldx #MSGF11 - TESTMSGS          ; $C6E7
    jsr TESTMSG                     ; $C6E9

RAMBITS_4:
    asl a                           ; $C6EC
    bcc RAMBITS_5                   ; $C6ED
    ldx #MSGF10 - TESTMSGS          ; $C6EF
    jsr TESTMSG                     ; $C6F1

RAMBITS_5:
    asl a                           ; $C6F4
    bcc RAMBITS_6                   ; $C6F5
    ldx #MSGF9 - TESTMSGS           ; $C6F7
    jsr TESTMSG                     ; $C6F9

RAMBITS_6:
    asl a                           ; $C6FC
    bcc RAMBITS_7                   ; $C6FD
    ldx #MSGF8 - TESTMSGS           ; $C6FF
    jsr TESTMSG                     ; $C701

RAMBITS_7:
    asl a                           ; $C704
    bcc RAMBITS_8                   ; $C705
    ldx #MSGF7 - TESTMSGS           ; $C707
    jsr TESTMSG                     ; $C709

RAMBITS_8:
    asl a                           ; $C70C
    bcc RAMBITS_9                   ; $C70D
    ldx #MSGF6 - TESTMSGS           ; $C70F
    jsr TESTMSG                     ; $C711

RAMBITS_9:
    jmp RAMBITS_9                   ; $C714

;; All tests passed: restores the text screen. If both Apple keys are still held, runs TESTLOOP; otherwise
;; prints "KERNEL OK" and hangs.
TESTPASS:
    lda LCROM                       ; $C717
    jsr TESTSCRN                    ; $C71A
    lda TXTSET                      ; $C71D
    lda BUTN0                       ; $C720
    and BUTN1                       ; $C723
    bmi TESTLOOP                    ; $C726
    ldx #MSGOK - TESTMSGS           ; $C728
    jsr TESTMSG                     ; $C72A

TESTPASS_1:
    jmp TESTPASS_1                  ; $C72D

;; Copies the 53-byte program at LOOPCODE to $0100 and runs it.
TESTLOOP:
    ldx #$00                        ; $C730

TESTLOOP_1:
    lda LOOPCODE,x                  ; $C732
    sta $0100,x                     ; $C735
    inx                             ; $C738
    cpx #LOOPCODEEND - LOOPCODE     ; $C739
    bne TESTLOOP_1                  ; $C73B
    jmp $0100                       ; $C73D

;; Prints the zero-terminated message at TESTMSGS+X through COUT1.
;; In: X = offset of the message
;; Keeps: A (via $07)
;; Out: X = the offset of the terminator
TESTMSG:
    sta $07                         ; $C740

TESTMSG_1:
    lda TESTMSGS,x                  ; $C742
    beq TESTMSG_2                   ; $C745
    jsr COUT1                       ; $C747
    inx                             ; $C74A
    bne TESTMSG_1                   ; $C74B

TESTMSG_2:
    lda $07                         ; $C74D
    rts                             ; $C74F

;; Self-test messages for TESTMSG, each ended by $00 and found by its offset from TESTMSGS. The RAM chip
;; locations run from F13 (bit 7) down to F6 (bit 0).
TESTMSGS:
MSGROM1:
    .byte "ROM:E8", KEY_CR, 0       ; $C750
MSGROM2:
    .byte "ROM:E10", KEY_CR, 0      ; $C758
MSGRAM:
    .byte "RAM:", 0                 ; $C761
MSGOK:
    .byte "KERNEL OK", 0            ; $C766
MSGF13:
    .byte "F13 ", 0                 ; $C770
MSGF12:
    .byte "F12 ", 0                 ; $C775
MSGF11:
    .byte "F11 ", 0                 ; $C77A
MSGF10:
    .byte "F10 ", 0                 ; $C77F
MSGF9:
    .byte "F9 ", 0                  ; $C784
MSGF8:
    .byte "F8 ", 0                  ; $C788
MSGF7:
    .byte "F7 ", 0                  ; $C78C
MSGF6:
    .byte "F6 ", 0                  ; $C790
MSGMMU:
    .byte "MMU FLAG E4:", 0         ; $C794
MSGIOU:
    .byte "IOU FLAG E5:", 0         ; $C7A1

;; Code copied to $0100 by TESTLOOP and run there: selects slot ROMs, reads and rewrites every byte from
;; $C090 to $CFFF, reads $C079 down to $C001, switches internal ROM and text back in and restarts SELFTEST
;; at $C401. It is assembled here; it has only relative branches and no absolute references to itself,
;; so it runs the same at $0100.
LOOPCODE:
    sta SETSLOTCXROM                ; $C7AE
    sta CLRROM                      ; $C7B1
    ldy #$00                        ; $C7B4
    lda #$C0                        ; $C7B6
    sta LOC1                        ; $C7B8
    lda #$00                        ; $C7BA
    sta LOC0                        ; $C7BC
    ldy #$90                        ; $C7BE

LOOPCODE_1:
    lda (LOC0),y                    ; $C7C0
    sta (LOC0),y                    ; $C7C2
    iny                             ; $C7C4
    bne LOOPCODE_1                  ; $C7C5
    inc LOC1                        ; $C7C7
    lda LOC1                        ; $C7C9
    cmp #$D0                        ; $C7CB
    bne LOOPCODE_1                  ; $C7CD
    lda #$C0                        ; $C7CF
    sta LOC1                        ; $C7D1
    ldy #$79                        ; $C7D3

LOOPCODE_2:
    lda (LOC0),y                    ; $C7D5
    dey                             ; $C7D7
    bne LOOPCODE_2                  ; $C7D8
    sta SETINTCXROM                 ; $C7DA
    sta TXTSET                      ; $C7DD
    jmp SELFTEST                    ; $C7E0
LOOPCODEEND:

;; Resets the text screen for the self-test: INIT, normal video (INVFLG = $FF) and HOME.
TESTSCRN:
    jsr INIT                        ; $C7E3
    lda #$FF                        ; $C7E6
    sta INVFLG                      ; $C7E8
    jsr HOME                        ; $C7EA
    rts                             ; $C7ED

;; Expected MMU flag states for $C011-$C018 (bit 7): bank 2 and internal $CX ROM on, the rest off.
MMUFLAGS:
    .byte $80, $00, $00, $00, $80, $00, $00, $00 ; $C7EE

;; Expected IOU flag states for $C01A-$C01F (bit 7): text on, the rest off.
IOUFLAGS:
    .byte $80, $00, $00, $00, $00, $00 ; $C7F6
    .byte $00, $00, $00, $00        ; $C7FC

;; A fixed entry at the start of the $C800 ROM: jumps to $CA4A.
C8ENTRY:
    jmp PINIT1_0                    ; $C800

;; BASICINT: checks that the Monitor version byte reads $06; if not (language card RAM holding another
;; Monitor) copies the ROM Monitor into it with COPYROM and checks again, and hangs if it still differs.
BASICINIT:
    lda #$06                        ; $C803
    cmp VERSION                     ; $C805
    beq BINIT1                      ; $C808
    jsr COPYROM                     ; $C80A
    cmp VERSION                     ; $C80D
    beq BINIT1                      ; $C810
    sei                             ; $C812

HANG:
    jmp HANG                        ; $C813

;; Points CSW at $C307 and KSW at $C305, sets a 40-column window (top 20 if graphics are on), remembers CH in
;; $047B and clears every mode bit except bit 0.
BINIT1:
    lda #>BASICIN                   ; $C816 BASICIN and BASICOUT share page $C3
    sta CSWH                        ; $C818
    sta KSWH                        ; $C81A
    lda #<BASICIN                   ; $C81C
    sta KSWL                        ; $C81E
    lda #<BASICOUT                  ; $C820
    sta CSWL                        ; $C822
    lda #$00                        ; $C824
    sta WNDLFT                      ; $C826
    lda #$00                        ; $C828
    bit RDTEXT                      ; $C82A
    bmi BINIT1A                     ; $C82D
    lda #$14                        ; $C82F

BINIT1A:
    sta WNDTOP                      ; $C831
    lda #$18                        ; $C833
    sta WNDBTM                      ; $C835
    lda #$28                        ; $C837
    sta WNDWDTH                     ; $C839
    lda CH                          ; $C83B
    sta OLDCH                       ; $C83D
    lda #$01                        ; $C840
    and MODE80                      ; $C842
    sta MODE80                      ; $C845
    jmp BINIT2                      ; $C848
    .byte $00, $00                  ; $C84B
    jmp JPREAD                      ; $C84D not referenced in this ROM

;; When an 80-column card answers, doubles WNDWDTH and turns on 80STORE and 80VID. Always selects the
;; alternate character set, homes and clears the window, then continues as output of the character in A.
;; The label C8BASIC ($C866) is the shared input/output path: makes sure 80STORE is on and WNDWDTH even in
;; 80 columns, adopts CH as the cursor column if a program changed it, repeats the version check, and goes
;; to input or output by the saved carry.
BINIT2:
    jsr TESTCARD                    ; $C850
    bne CLEARIT                     ; $C853
    asl WNDWDTH                     ; $C855
    sta SET80STORE                  ; $C857
    sta SET80VID                    ; $C85A

CLEARIT:
    sta SETALTCHAR                  ; $C85D
    jsr X_FF                        ; $C860
    plp                             ; $C863
    clc                             ; $C864
    php                             ; $C865

C8BASIC:
    bit RD80VID                     ; $C866
    bpl C8B2                        ; $C869
    sta SET80STORE                  ; $C86B
    lda WNDWDTH                     ; $C86E
    and #$FE                        ; $C870
    sta WNDWDTH                     ; $C872

C8B2:
    lda CH                          ; $C874
    cmp OLDCH                       ; $C876
    beq C8B3                        ; $C879
    sta OURCH                       ; $C87B

C8B3:
    lda #$06                        ; $C87E
    cmp VERSION                     ; $C880
    beq C8B4                        ; $C883
    jsr COPYROM                     ; $C885
    cmp VERSION                     ; $C888
    beq C8B4                        ; $C88B
    jmp HANG                        ; $C88D

;; Pulls the entry P and goes to BINPUT when carry is set, output otherwise.
C8B4:
    plp                             ; $C890
    bcc BOUT                        ; $C891
    jmp BINPUT                      ; $C893

;; Output path: clears mode bit 6 (not in input).
BOUT:
    lda MODE80                      ; $C896
    and #$BF                        ; $C899
    sta MODE80                      ; $C89B
    jmp BPRINT                      ; $C89E

;; Outputs the character in $067B. A carriage return with Control-S waiting pauses until another key
;; (Control-C is left in the keyboard buffer). Control characters go to CTLCHAR, others to BPNCTL.
BPRINT:
    lda CHAR                        ; $C8A1
    cmp #KEY_CR                     ; $C8A4
    bne C8_NOWAIT                   ; $C8A6
    ldy KBD                         ; $C8A8
    bpl C8_NOWAIT                   ; $C8AB
    cpy #KEY_CTRL_S                 ; $C8AD
    bne C8_NOWAIT                   ; $C8AF
    bit KBDSTRB                     ; $C8B1

C8_KBDWAIT:
    ldy KBD                         ; $C8B4
    bpl C8_KBDWAIT                  ; $C8B7
    cpy #KEY_CTRL_C                 ; $C8B9
    beq C8_NOWAIT                   ; $C8BB
    bit KBDSTRB                     ; $C8BD

C8_NOWAIT:
    and #$7F                        ; $C8C0
    cmp #' ' & $7F                  ; $C8C2 below the space: a control character
    bcs BPNCTL                      ; $C8C4
    jsr CTLCHAR                     ; $C8C6
    jmp BIORET                      ; $C8C9

;; Displays $067B at the cursor (honoring inverse) and advances, wrapping with X_CR at the right edge.
;; BIORET ($C8E2) is the common exit: copies the cursor to CH (SETCH) and $05FB to CV, restores X and
;; Y and returns with A = $067B.
BPNCTL:
    ldy OURCH                       ; $C8CC
    lda CHAR                        ; $C8CF
    jsr STORCHAR                    ; $C8D2
    inc OURCH                       ; $C8D5
    lda OURCH                       ; $C8D8
    cmp WNDWDTH                     ; $C8DB
    bcc BIORET                      ; $C8DD
    jsr X_CR                        ; $C8DF

BIORET:
    lda OURCH                       ; $C8E2
    jsr SETCH                       ; $C8E5
    lda OURCV                       ; $C8E8
    sta CV                          ; $C8EB
    pla                             ; $C8ED
    tax                             ; $C8EE
    pla                             ; $C8EF
    tay                             ; $C8F0
    pla                             ; $C8F1
    lda CHAR                        ; $C8F2
    rts                             ; $C8F5

;; Input path: sets mode bit 6, puts back the character the Monitor's RDKEY changed at CH, then waits for a
;; key with the cursor shown by inverting the character at the 80-column cursor. ESC enters ESCAPING; other
;; keys go to NOESC.
BINPUT:
    lda MODE80                      ; $C8F6
    ora #$40                        ; $C8F9
    sta MODE80                      ; $C8FB
    lda CHAR                        ; $C8FE
    ldy CH                          ; $C901
    sta (BASL),y                    ; $C903

B_INPUT:
    jsr INVERT                      ; $C905
    jsr GETKEY80                    ; $C908
    sta CHAR                        ; $C90B
    jsr INVERT                      ; $C90E
    cmp #KEY_ESC                    ; $C911
    beq ESCAPING                    ; $C913
    jmp NOESC                       ; $C915

;; Escape mode: shows an inverse "+" cursor, reads a key, uppercases it and looks it up in ESCTAB. A match
;; performs ESCCHAR's control character; if that byte has bit 7 set, escape mode continues. Control-Q quits
;; the 80-column firmware and returns Control-X; R and T set and clear uppercase input (mode bit 7). Any
;; other key ends escape mode.
ESCAPING:
    jsr ESCON                       ; $C918
    jsr GETKEY80                    ; $C91B
    jsr ESCOFF                      ; $C91E
    and #$7F                        ; $C921
    cmp #'`' & $7F                  ; $C923 lowercase letters to uppercase
    bcc C8_ESC1                     ; $C925
    and #$DF                        ; $C927

C8_ESC1:
    ldy #ESCCHAR - ESCTAB           ; $C929 one past the last entry, so ESCCHAR's first byte is compared too

ESC2:
    cmp ESCTAB,y                    ; $C92B
    beq ESC3                        ; $C92E
    dey                             ; $C930
    bpl ESC2                        ; $C931
    bmi ESCSPEC                     ; $C933

ESC3:
    lda ESCCHAR,y                   ; $C935
    and #$7F                        ; $C938
    jsr CTLCHAR                     ; $C93A
    lda ESCCHAR,y                   ; $C93D
    bmi ESCAPING                    ; $C940
    jmp B_INPUT                     ; $C942

;; Escape mode, key not in the table: Control-Q runs QUIT and returns $98 (Control-X) as the key.
ESCSPEC:
    cmp #KEY_CTRL_Q & $7F           ; $C945
    bne ESCSPEC2                    ; $C947
    jsr QUIT                        ; $C949
    lda #KEY_CTRL_X                 ; $C94C
    sta CHAR                        ; $C94E
    jmp BIORET                      ; $C951

;; Escape R: sets mode bit 7 (lowercase input is converted to uppercase).
ESCSPEC2:
    cmp #'R' & $7F                  ; $C954
    bne ESCSPEC3                    ; $C956
    lda MODE80                      ; $C958
    ora #$80                        ; $C95B
    sta MODE80                      ; $C95D

ESCNONE:
    jmp B_INPUT                     ; $C960

;; Escape T: clears mode bit 7.
ESCSPEC3:
    cmp #'T' & $7F                  ; $C963
    bne ESCNONE                     ; $C965
    lda MODE80                      ; $C967
    and #$7F                        ; $C96A
    sta MODE80                      ; $C96C
    jmp B_INPUT                     ; $C96F

;; The escape-mode keys and the control character each performs. ESCTAB ($C972) holds the keys and
;; ESCCHAR ($C983) the control characters, both with bit 7 clear; ESC_STAY in ESCCHAR keeps escape mode on.
ESC_STAY = $80
.set ESCKEYS, 0

.macro ESCKEY key, control, stay
    .ident(.sprintf("ESCKEY_%d", ESCKEYS)) = (key) & $7F
    .ident(.sprintf("ESCCHAR_%d", ESCKEYS)) = (control) & $7F | (stay)
    .set ESCKEYS, ESCKEYS + 1
.endmacro

    ESCKEY '@', KEY_FF, 0           ; home and clear the window
    ESCKEY 'A', KEY_FS, 0           ; right
    ESCKEY 'B', KEY_BS, 0           ; left
    ESCKEY 'C', KEY_LF, 0           ; down
    ESCKEY 'D', KEY_US, 0           ; up
    ESCKEY 'E', KEY_GS, 0           ; clear to the end of the line
    ESCKEY 'F', KEY_CTRL_K, 0       ; clear to the end of the window
    ESCKEY 'I', KEY_US, ESC_STAY    ; up
    ESCKEY 'J', KEY_BS, ESC_STAY    ; left
    ESCKEY 'K', KEY_FS, ESC_STAY    ; right
    ESCKEY 'M', KEY_LF, ESC_STAY    ; down
    ESCKEY '4', KEY_CTRL_Q, 0       ; 40 columns
    ESCKEY '8', KEY_CTRL_R, 0       ; 80 columns
    ESCKEY KEY_BS, KEY_BS, ESC_STAY ; the left arrow
    ESCKEY KEY_LF, KEY_LF, ESC_STAY ; the down arrow
    ESCKEY KEY_CTRL_K, KEY_US, ESC_STAY ; the up arrow
    ESCKEY KEY_RIGHT, KEY_FS, ESC_STAY ; the right arrow

ESCTAB:
.repeat ESCKEYS, index
    .byte .ident(.sprintf("ESCKEY_%d", index))
.endrepeat

ESCCHAR:
.repeat ESCKEYS, index
    .byte .ident(.sprintf("ESCCHAR_%d", index))
.endrepeat

;; Pascal status.
;; In:    A = the request
;; Out:   X = 0 for requests 0 and 1, 3 for any other,
;;          carry = set for request 0; for request 1, set if a key is waiting; clear for any other request
PSTATUS:
    tax                             ; $C994
    jsr PSETUP                      ; $C995
    txa                             ; $C998
    bne PSTATUS2                    ; $C999
    sec                             ; $C99B
    bcs PSTATUS4                    ; $C99C

PSTATUS2:
    cmp #$01                        ; $C99E
    beq PSTATUS3                    ; $C9A0
    ldx #$03                        ; $C9A2
    clc                             ; $C9A4
    rts                             ; $C9A5
    .byte $00, $00, $00, $00        ; $C9A6

;; A fixed entry: writes the current character ($067B) through JPWRITE.
C9ENTRY:
    lda CHAR                        ; $C9AA
    jmp JPWRITE                     ; $C9AD

;; Status request 1: carry = bit 7 of KBD.
PSTATUS3:
    lda KBD                         ; $C9B0
    asl a                           ; $C9B3

PSTATUS4:
    ldx #$00                        ; $C9B4
    rts                             ; $C9B6

;; Finishes an input key: right arrow (Control-U) picks up the character under the cursor instead. Tracks
;; quotes: a quote, or a backspace over one, toggles mode bit 4; inside quotes a quote, Control-X or return
;; clears it. With mode bit 7 set and outside quotes, lowercase is converted to uppercase. Returns the key.
NOESC:
    cmp #KEY_RIGHT                  ; $C9B7
    bne B_NOPICK                    ; $C9B9
    ldy OURCH                       ; $C9BB
    jsr PICK                        ; $C9BE
    ora #$80                        ; $C9C1
    sta CHAR                        ; $C9C3

B_NOPICK:
    lda MODE80                      ; $C9C6
    and #$10                        ; $C9C9
    bne B_CHKCAN                    ; $C9CB
    lda CHAR                        ; $C9CD
    cmp #'"'                        ; $C9D0
    beq B_FLIP                      ; $C9D2
    cmp #KEY_BS                     ; $C9D4
    bne B_FIXCHR                    ; $C9D6
    jsr GETPRIOR                    ; $C9D8
    bne B_FIXCHR                    ; $C9DB
    beq B_FLIP                      ; $C9DD

B_CHKCAN:
    lda CHAR                        ; $C9DF
    cmp #'"'                        ; $C9E2
    beq B_CANLIT                    ; $C9E4
    cmp #KEY_CTRL_X                 ; $C9E6
    beq B_CANLIT                    ; $C9E8
    cmp #KEY_CR                     ; $C9EA
    beq B_CANLIT                    ; $C9EC
    cmp #KEY_BS                     ; $C9EE
    bne B_FIXCHR                    ; $C9F0
    jsr GETPRIOR                    ; $C9F2
    bne B_FIXCHR                    ; $C9F5

B_FLIP:
    lda MODE80                      ; $C9F7
    eor #$10                        ; $C9FA
    sta MODE80                      ; $C9FC
    jmp B_FIXCHR                    ; $C9FF

;; Clears mode bit 4 (leaving a quoted string).
B_CANLIT:
    lda MODE80                      ; $CA02
    and #$EF                        ; $CA05
    sta MODE80                      ; $CA07

B_FIXCHR:
    lda MODE80                      ; $CA0A
    and #$80                        ; $CA0D
    beq B_INRET                     ; $CA0F
    lda MODE80                      ; $CA11
    and #$10                        ; $CA14
    bne B_INRET                     ; $CA16
    lda CHAR                        ; $CA18
    cmp #'`'                        ; $CA1B above it: lowercase
    bcc B_INRET                     ; $CA1D
    and #$DF                        ; $CA1F
    sta CHAR                        ; $CA21

B_INRET:
    jmp BIORET                      ; $CA24

;; Reads the character before the cursor (moving left and back right).
;; Out:   $0478 = the character, zero = set if it is a quote ($A2), or if the cursor is at the top left
;; Keeps: Y
GETPRIOR:
    lda OURCV                       ; $CA27
    ora OURCH                       ; $CA2A
    beq GPX                         ; $CA2D
    tya                             ; $CA2F
    pha                             ; $CA30
    jsr X_BS                        ; $CA31
    ldy OURCH                       ; $CA34
    jsr PICK                        ; $CA37
    ora #$80                        ; $CA3A
    sta TEMP1                       ; $CA3C
    jsr X_FS                        ; $CA3F
    pla                             ; $CA42
    tay                             ; $CA43
    lda TEMP1                       ; $CA44
    cmp #'"'                        ; $CA47

GPX:
    rts                             ; $CA49

;; Sets the mode byte to $22 and continues as PINIT. Reached from the JMP at $C800.
PINIT1_0:
    lda #$22                        ; $CA4A
    jmp PINIT2                      ; $CA4C

;; Pascal init: sets the mode byte to $20 (or $22 from $CA4A), the full 80x24 window and inverse state.
;; With no 80-column card returns X = 9; otherwise turns on 80STORE, 80VID and the alternate character
;; set, homes and clears the screen, shows the cursor and returns X = 0.
PINIT:
    lda #$20                        ; $CA4F

PINIT2:
    sta MODE80                      ; $CA51
    jsr FULL80                      ; $CA54
    jsr PSETUP                      ; $CA57
    jsr TESTCARD                    ; $CA5A
    beq PIGOOD                      ; $CA5D
    ldx #$09                        ; $CA5F
    rts                             ; $CA61

;; Pascal init with a card present: switches 80 columns on and clears the screen.
PIGOOD:
    sta SET80STORE                  ; $CA62
    sta SET80VID                    ; $CA65
    sta SETALTCHAR                  ; $CA68
    jsr X_FF                        ; $CA6B
    jsr INVERT                      ; $CA6E
    ldx #$00                        ; $CA71
    rts                             ; $CA73

;; Pascal read: waits for a key and returns it with bit 7 clear.
;; Out: A = key (also in $067B); X = 0, or $C3 when mode bit 1 is set
C8_PREAD:
    jsr PSETUP                      ; $CA74
    jsr GETKEY80                    ; $CA77
    and #$7F                        ; $CA7A
    sta CHAR                        ; $CA7C
    ldx #$00                        ; $CA7F
    lda MODE80                      ; $CA81
    and #$02                        ; $CA84
    beq PREADRET2                   ; $CA86
    ldx #$C3                        ; $CA88

PREADRET2:
    lda CHAR                        ; $CA8A
    rts                             ; $CA8D

;; Pascal write: hides the cursor, handles the character, shows the cursor.
;; In: A = character.
;; Out: X = 0
;; $1E starts GOTOXY: the next two characters minus 32 are the column ($06FB) and row. Other control
;; characters go to CTLCHAR; printable ones are stored with bit 7 set and advance the cursor, which
;; stays on the last column when mode bit 0 is set, else wraps with a carriage return and line feed.
PWRITE:
    sta CHAR                        ; $CA8E
    jsr PSETUP                      ; $CA91
    jsr INVERT                      ; $CA94
    lda MODE80                      ; $CA97
    and #$08                        ; $CA9A
    beq PWRITE3                     ; $CA9C

PWRITE2:
    lda XCOORD                      ; $CA9E
    bpl GETY                        ; $CAA1
    lda CHAR                        ; $CAA3
    sec                             ; $CAA6
    sbc #$20                        ; $CAA7
    sta XCOORD                      ; $CAA9
    jmp PWRITERET                   ; $CAAC

;; GOTOXY, second byte: sets the row from the character and the column from $06FB, clears mode bit 3.
GETY:
    lda CHAR                        ; $CAAF
    sec                             ; $CAB2
    sbc #$20                        ; $CAB3
    sta OURCV                       ; $CAB5
    jsr C8_BASCALC                  ; $CAB8
    lda XCOORD                      ; $CABB
    sta OURCH                       ; $CABE
    lda MODE80                      ; $CAC1
    and #$F7                        ; $CAC4
    sta MODE80                      ; $CAC6
    bne PWRITERET                   ; $CAC9

PWRITE3:
    lda CHAR                        ; $CACB
    cmp #KEY_GOTOXY & $7F           ; $CACE
    beq STARTXY                     ; $CAD0
    cmp #' ' & $7F                  ; $CAD2 below the space: a control character
    bcs PWRITE4                     ; $CAD4
    jsr CTLCHAR                     ; $CAD6
    jmp PWRITERET                   ; $CAD9

;; Control-^ ($1E): sets mode bit 3 and marks the column byte ($06FB = $FF) as not yet received.
;; PWRITE4 ($CAEB) displays a printable character and PWRITERET ($CB0F) is the common exit.
STARTXY:
    lda MODE80                      ; $CADC
    ora #$08                        ; $CADF
    sta MODE80                      ; $CAE1
    lda #$FF                        ; $CAE4
    sta XCOORD                      ; $CAE6
    bmi PWRITERET                   ; $CAE9

PWRITE4:
    ora #$80                        ; $CAEB
    ldy OURCH                       ; $CAED
    jsr STORCHAR                    ; $CAF0
    inc OURCH                       ; $CAF3
    lda OURCH                       ; $CAF6
    cmp WNDWDTH                     ; $CAF9
    bcc PWRITERET                   ; $CAFB
    lda MODE80                      ; $CAFD
    and #$01                        ; $CB00
    beq PWWRAP                      ; $CB02
    dec OURCH                       ; $CB04
    bne PWRITERET                   ; $CB07

PWWRAP:
    jsr X_CR                        ; $CB09
    jsr X_LF                        ; $CB0C

PWRITERET:
    jsr INVERT                      ; $CB0F
    ldx #$00                        ; $CB12
    rts                             ; $CB14

;; Waits for a key, stirring RNDL/RNDH, and clears the keyboard strobe.
;; Out: A = key (bit 7 set)
GETKEY80:
    inc RNDL                        ; $CB15
    bne GETK2                       ; $CB17
    inc RNDH                        ; $CB19

GETK2:
    lda KBD                         ; $CB1B
    bpl GETKEY80                    ; $CB1E
    sta KBDSTRB                     ; $CB20
    rts                             ; $CB23

;; Tests for an 80-column card: with interrupts off, turns 80STORE and PAGE2 on, writes $88 to $0400 in
;; auxiliary memory, reads it back and restores the byte, PAGE2 and 80STORE.
;; Out:   A = $88 if the card answered, zero = set if the card answered
;; Uses:  A, Y
TESTCARD:
    lda RDPAGE2                     ; $CB24
    asl a                           ; $CB27
    lda #$88                        ; $CB28
    bit RD80STORE                   ; $CB2A
    sta SET80STORE                  ; $CB2D
    php                             ; $CB30
    sei                             ; $CB31
    php                             ; $CB32
    sta HISCR                       ; $CB33
    ldy LINE1                       ; $CB36
    sta LINE1                       ; $CB39
    lda LINE1                       ; $CB3C
    sty LINE1                       ; $CB3F
    plp                             ; $CB42
    bcs STAY2                       ; $CB43
    sta LOWSCR                      ; $CB45

STAY2:
    bmi STAY80                      ; $CB48
    sta KBD                         ; $CB4A

STAY80:
    plp                             ; $CB4D

TESTFAIL:
    cmp #$88                        ; $CB4E
    rts                             ; $CB50

;; Computes BASL/BASH for a text row and saves them in $077B/$07FB. WNDLFT is added halved in 80 columns.
;; If mode bit 0 is set and bit 5 clear, calls the Monitor's $FC75 to let interrupts in.
;; In:    $05FB = the row
;; Entry: C8_BASCALC_1 = takes the row in A
;; Keeps: A
C8_BASCALC:
    clc                             ; $CB51
    bcc BSCLC1                      ; $CB52

C8_BASCALC_1:
    sec                             ; $CB54

BSCLC1:
    pha                             ; $CB55
    bcs BSCLC1A                     ; $CB56
    lda OURCV                       ; $CB58

BSCLC1A:
    pha                             ; $CB5B
    lsr a                           ; $CB5C
    and #$03                        ; $CB5D
    ora #$04                        ; $CB5F
    sta BASH                        ; $CB61
    sta OLDBASH                     ; $CB63
    pla                             ; $CB66
    and #$18                        ; $CB67
    bcc BSCLC2                      ; $CB69
    adc #$7F                        ; $CB6B

BSCLC2:
    sta BASL                        ; $CB6D
    asl a                           ; $CB6F
    asl a                           ; $CB70
    ora BASL                        ; $CB71
    sta BASL                        ; $CB73
    lda WNDLFT                      ; $CB75
    php                             ; $CB77
    bit RD80VID                     ; $CB78
    bpl BASCLC3                     ; $CB7B
    lsr a                           ; $CB7D

BASCLC3:
    plp                             ; $CB7E
    adc BASL                        ; $CB7F
    sta BASL                        ; $CB81
    sta OLDBASL                     ; $CB83
    lda MODE80                      ; $CB86
    and #$01                        ; $CB89
    beq BASCLCX                     ; $CB8B
    lda MODE80                      ; $CB8D
    and #$20                        ; $CB90
    bne BASCLCX                     ; $CB92
    jsr VIDSYNC                     ; $CB94

BASCLCX:
    pla                             ; $CB97
    rts                             ; $CB98

;; Performs a control character at the 80-column cursor.
;; In: A = character ($00-$1F).
;; Out:   carry = clear if handled, set if not
;; Keeps: A, Y
;; Uses: $0478
CTLCHAR:
    sta TEMP1                       ; $CB99
    pha                             ; $CB9C
    tya                             ; $CB9D
    pha                             ; $CB9E
    ldy TEMP1                       ; $CB9F
    cpy #KEY_BELL & $7F             ; $CBA2 Control-G, the first in CTLADL and CTLADH
    bcc CTLCHARX                    ; $CBA4
    lda CTLADH-7,y                  ; $CBA6 Y = 7-$1F: Control-G to Control-_
    bne CTLGO                       ; $CBA9

CTLCHARX:
    sec                             ; $CBAB
    bcs CTLRET                      ; $CBAC

CTLGO:
    jsr CTLXFER                     ; $CBAE
    clc                             ; $CBB1

CTLRET:
    pla                             ; $CBB2
    tay                             ; $CBB3
    pla                             ; $CBB4
    rts                             ; $CBB5

;; Jumps (by RTS) to the handler for control character Y: the caller has pushed the high byte from
;; CTLADH, this pushes the low byte from CTLADL.
CTLXFER:
    pha                             ; $CBB6
    lda CTLADL-7,y                  ; $CBB7 Y = 7-$1F
    pha                             ; $CBBA
    rts                             ; $CBBB

;; Control-G: rings the bell. Pauses, then toggles the speaker 192 times.
X_BELL:
    lda #$40                        ; $CBBC
    jsr C8_WAIT                     ; $CBBE
    ldy #$C0                        ; $CBC1

C8_BELL2:
    lda #$0C                        ; $CBC3
    jsr C8_WAIT                     ; $CBC5
    lda SPKR                        ; $CBC8
    dey                             ; $CBCB
    bne C8_BELL2                    ; $CBCC
    rts                             ; $CBCE

;; A delay, a copy of the Monitor's WAIT.
;; In: A = count
C8_WAIT:
    sec                             ; $CBCF

C8_WAIT2:
    pha                             ; $CBD0

C8_WAIT3:
    sbc #$01                        ; $CBD1
    bne C8_WAIT3                    ; $CBD3
    pla                             ; $CBD5
    sbc #$01                        ; $CBD6
    bne C8_WAIT2                    ; $CBD8
    rts                             ; $CBDA

;; Moves the cursor left; from column 0 goes to the end of the previous line (X_US).
X_BS:
    dec OURCH                       ; $CBDB
    bpl BSDONE                      ; $CBDE
    lda WNDWDTH                     ; $CBE0

BS40:
    sta OURCH                       ; $CBE2
    dec OURCH                       ; $CBE5
    jsr X_US                        ; $CBE8

BSDONE:
    rts                             ; $CBEB

;; Carriage return: in BASIC input (mode bit 6, not Pascal) clears to the end of the line first. Sets the
;; column to 0 and, outside Pascal mode, does a line feed.
X_CR:
    lda MODE80                      ; $CBEC
    and #$20                        ; $CBEF
    bne X_CRPAS                     ; $CBF1
    lda MODE80                      ; $CBF3
    and #$40                        ; $CBF6
    beq X_CRPAS                     ; $CBF8
    jsr X_GS                        ; $CBFA

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
