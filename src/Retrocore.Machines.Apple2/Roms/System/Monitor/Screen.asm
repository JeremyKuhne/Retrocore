;; Computes a text line's base address on page one.
;; In: A = line (0-23)
;; Out: BASL/BASH
;; Keeps: X, Y
BASCALC:
    pha                             ; $FBC1
    lsr a                           ; $FBC2
    and #$03                        ; $FBC3
    ora #$04                        ; $FBC5
    sta BASH                        ; $FBC7
    pla                             ; $FBC9
    and #$18                        ; $FBCA
    bcc BASCLC2                     ; $FBCC
    adc #$7F                        ; $FBCE

BASCLC2:
    sta BASL                        ; $FBD0
    asl a                           ; $FBD2
    asl a                           ; $FBD3
    ora BASL                        ; $FBD4
    sta BASL                        ; $FBD6
    rts                             ; $FBD8

;; Rings the bell when A is Control-G ($87): about 0.1 seconds at roughly 1 kHz. VIDOUT sends other
;; control characters here too, and they are ignored.
;; Uses A, Y.
BELL1:
    cmp #KEY_BELL                   ; $FBD9
    bne RTS2B                       ; $FBDB
    lda #$40                        ; $FBDD from here the bell rings whatever A holds
    jsr WAIT                        ; $FBDF
    ldy #$C0                        ; $FBE2

BELL2:
    lda #$0C                        ; $FBE4
    jsr WAIT                        ; $FBE6
    lda SPKR                        ; $FBE9
    dey                             ; $FBEC
    bne BELL2                       ; $FBED

RTS2B:
    rts                             ; $FBEF

;; Stores a printable character at the cursor, then advances the cursor (ADVANCE).
STORADV:
    ldy CH                          ; $FBF0
    sta (BASL),y                    ; $FBF2

;; Moves the cursor right; at the window's right edge, starts a new line (CR).
ADVANCE:
    inc CH                          ; $FBF4
    lda CH                          ; $FBF6
    cmp WNDWDTH                     ; $FBF8
    bcs CR                          ; $FBFA

RTS3:
    rts                             ; $FBFC

;; The screen's character output: prints A at the cursor, or performs carriage return, line feed,
;; backspace or bell.
;; In: A = character with the high bit set
VIDOUT:
    cmp #' '                        ; $FBFD
    bcs STORADV                     ; $FBFF
    tay                             ; $FC01
    bpl STORADV                     ; $FC02
    cmp #KEY_CR                     ; $FC04
    beq CR                          ; $FC06
    cmp #KEY_LF                     ; $FC08
    beq LF                          ; $FC0A
    cmp #KEY_BS                     ; $FC0C
    bne BELL1                       ; $FC0E

;; Moves the cursor left; at the window's left edge, to the end of the line above.
BS:
    dec CH                          ; $FC10
    bpl RTS3                        ; $FC12
    lda WNDWDTH                     ; $FC14
    sta CH                          ; $FC16
    dec CH                          ; $FC18

;; Moves the cursor up a line unless it is on the window's top line.
UP:
    lda WNDTOP                      ; $FC1A
    cmp CV                          ; $FC1C
.if ENHANCED
    bcs RTS3                        ; $FC1E
.else
    bcs RTS4                        ; $FC1E
.endif
    dec CV                          ; $FC20

;; Sets BASL/BASH for the cursor's line, CV.
VTAB:
    lda CV                          ; $FC22

;; Sets BASL/BASH for a line, offset by the window's left edge.
;; In: A = line
;; The Enhanced IIe asks the internal firmware (function 4), which knows the 80-column layout.
VTABZ:
.if ENHANCED
    sta BASL                        ; $FC24
    tya                             ; $FC26
    ldy #$04                        ; $FC27
.else
    jsr BASCALC                     ; $FC24
    adc WNDLFT                      ; $FC27
.endif

VTABZ_1:
.if ENHANCED
    bne GOTOCX                      ; $FC29
    .byte $00                       ; $FC2B unused
.else
    sta BASL                        ; $FC29

RTS4:
    rts                             ; $FC2B
.endif

;; Performs an escape command: @ clears the window (HOME), A/B/C/D move the cursor right, left,
;; down and up, E clears to the end of the line, F to the end of the window.
;; In: A = command character
ESC1:
    eor #'@'                        ; $FC2C
    beq HOME                        ; $FC2E
    adc #$FD                        ; $FC30
    bcc ADVANCE                     ; $FC32
    beq BS                          ; $FC34
    adc #$FD                        ; $FC36
    bcc LF                          ; $FC38
    beq UP                          ; $FC3A
    adc #$FD                        ; $FC3C
    bcc CLREOL                      ; $FC3E
.if ENHANCED
    bne RTS3                        ; $FC40
.else
    bne RTS4                        ; $FC40
.endif

;; Clears from the cursor to the end of the window.
;;
;; The Apple II's Monitors clear the window here themselves, a line at a time from the cursor's line
;; down (CLREOLZ), then set BASL/BASH for the cursor's line again (VTAB).
CLREOP:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$0A                        ; $FC42
    bne VTABZ_1                     ; $FC44

CLREOP_1:
    bit RD80VID                     ; $FC46
    bpl CLREOP_2                    ; $FC49
.endif
    ldy #$00                        ; $FC4B original $FC42
.if ENHANCED
    beq HOME_1                      ; $FC4D
.else
    beq XGOTOCX                     ; $FC44

CLREOP_1:
    .byte "(C) 1981-"               ; $FC46 unused bytes holding a copyright notice
.endif

CLREOP_2:
.if ENHANCED
    tya                             ; $FC4F
    pha                             ; $FC50
    jsr VIDWAIT                     ; $FC51
    pla                             ; $FC54
    ldy YSAV1                       ; $FC55
    rts                             ; $FC57
.else
    .byte "82, APPLE"               ; $FC4F
.endif
.else
    ldy CH                          ; $FC42 the first line clears from the cursor
    lda CV                          ; $FC44

CLEOP1:
    pha                             ; $FC46
    jsr VTABZ                       ; $FC47
    jsr CLREOLZ                     ; $FC4A returns with the carry set
    ldy #$00                        ; $FC4D the other lines clear from column 0
    pla                             ; $FC4F
    adc #$00                        ; $FC50 the next line (plus the carry)
    cmp WNDBTM                      ; $FC52
    bcc CLEOP1                      ; $FC54
    bcs VTAB                        ; $FC56
.endif

;; Clears the window and puts the cursor at its top left.
;;
;; The Apple II's Monitors move the cursor to the window's top line, column 0, and clear from there
;; in CLREOP.
HOME:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$05                        ; $FC58
.else
    ldy #$01                        ; $FC58
.endif

HOME_1:
.if ENHANCED
    jmp GOTOCX                      ; $FC5A
    .byte $53, $5C, $5C, $00, $00   ; $FC5D
.else
    bne XGOTOCX                     ; $FC5A
    .byte "RICK A"                  ; $FC5C
.endif
.else
    lda WNDTOP                      ; $FC58
    sta CV                          ; $FC5A
    ldy #$00                        ; $FC5C
    sty CH                          ; $FC5E
    beq CLEOP1                      ; $FC60
.endif

;; Carriage return: moves the cursor to the start of the next line (LF).
CR:
    lda #$00                        ; $FC62
    sta CH                          ; $FC64

;; Line feed: moves the cursor down a line, scrolling the window at the bottom.
LF:
    inc CV                          ; $FC66
    lda CV                          ; $FC68
    cmp WNDBTM                      ; $FC6A
    bcc VTABZ                       ; $FC6C
    dec CV                          ; $FC6E

;; Scrolls the text window up one line and clears the bottom line.
;;
;; The Apple II's Monitors scroll here themselves: from the window's top line down, each line gets a
;; copy of the one below it, from the right edge of the window to the left. The bottom line is then
;; cleared and BASL/BASH set for the cursor's line again (VTAB).
SCROLL:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$06                        ; $FC70
    bne VTABZ_1                     ; $FC72

XGOTOCX_1:
    sta SETSLOTCXROM                ; $FC74
    jmp (IRQLOC)                    ; $FC77
.else
    ldy #$02                        ; $FC70

XGOTOCX:
    jmp GOTOCX                      ; $FC72

;; Original IIe: returning from the internal firmware. Restores page one when 80STORE is on and page
;; two was displayed, briefly enables interrupts with slot ROM switched in so a pending interrupt can
;; run, and restores the saved ROM selection and display page.
;; Enhanced IIe: these bytes select a slot's $C800 ROM (MSLOT) for the interrupt handler, then continue
;; in the internal firmware at $C47C.
VIDSYNC:
    pha                             ; $FC75
    lda RD80STORE                   ; $FC76
    asl a                           ; $FC79
.endif

VIDSYNC_1:
    pla                             ; $FC7A
.if ENHANCED
    sta MSLOT                       ; $FC7B
    cmp #$C1                        ; $FC7E
    bcc IRQNOSLT                    ; $FC80
    sta CLRROM                      ; $FC82
    ldy #$00                        ; $FC85
    ldx LOC1                        ; $FC87
    sta LOC1                        ; $FC89
    lda (LOC0),y                    ; $FC8B
    stx LOC1                        ; $FC8D

;; Enhanced IIe: switches internal ROM back in and continues in the firmware's interrupt code (IRQRESTORE).
IRQNOSLT:
.else
    bit RDPAGE2                     ; $FC7B
    php                             ; $FC7E
    bcc RDCX                        ; $FC7F
    sta LOWSCR                      ; $FC81

RDCX:
    bit RDCXROM                     ; $FC84
    sta SETSLOTCXROM                ; $FC87
    cli                             ; $FC8A
    sei                             ; $FC8B
    bpl ISSLOTS                     ; $FC8C
.endif
    sta SETINTCXROM                 ; $FC8F original $FC8E
.if ENHANCED
    jmp IRQRESTORE                  ; $FC92

;; Enhanced IIe: COUT1's printable-character path: applies INVFLG and prints the character (COUTZ).
DOCOUT1:
    bcc DOCOUT2                     ; $FC95
    and INVFLG                      ; $FC97

DOCOUT2:
    jmp COUTZ_1                     ; $FC99
.else

;; Original IIe: restores the saved status and, when page two was displayed, switches back to it.
ISSLOTS:
    plp                             ; $FC91
    bcc ISPAGE1                     ; $FC92
    bpl ISPAGE1                     ; $FC94
    bit HISCR                       ; $FC96

ISPAGE1:
    rts                             ; $FC99
    .byte $EA, $EA                  ; $FC9A
.endif
.else
    lda WNDTOP                      ; $FC70
    pha                             ; $FC72 the line number being filled
    jsr VTABZ                       ; $FC73

SCRL1:
    lda BASL                        ; $FC76 the line just read becomes the one to fill
    sta BAS2L                       ; $FC78
    lda BASH                        ; $FC7A
    sta BAS2H                       ; $FC7C
    ldy WNDWDTH                     ; $FC7E
    dey                             ; $FC80
    pla                             ; $FC81
    adc #$01                        ; $FC82 the next line down
    cmp WNDBTM                      ; $FC84
    bcs SCRL3                       ; $FC86
    pha                             ; $FC88
    jsr VTABZ                       ; $FC89

SCRL2:
    lda (BASL),y                    ; $FC8C
    sta (BAS2L),y                   ; $FC8E
    dey                             ; $FC90
    bpl SCRL2                       ; $FC91
    bmi SCRL1                       ; $FC93

SCRL3:
    ldy #$00                        ; $FC95
    jsr CLREOLZ                     ; $FC97 BASL/BASH still hold the bottom line; returns with the carry set
    bcs VTAB                        ; $FC9A
.endif

;; Clears from the cursor to the end of the line.
CLREOL:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    sec                             ; $FC9C
    .byte $90                       ; $FC9D bcc: skips the next byte
.else
    clc                             ; $FC9C
    .byte $B0                       ; $FC9D bcs: skips the next byte
.endif
.else
    ldy CH                          ; $FC9C
.endif

;; Clears a line from a column to its end.
;;
;; The Apple II's Monitors store blanks here themselves, up to the window's width, and return with the
;; carry set. Their listings call it CLEOLZ.
;; In: Y = column; BASL/BASH = the line
CLREOLZ:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    clc                             ; $FC9E
    sty BAS2L                       ; $FC9F
    ldy #$07                        ; $FCA1
    bcs KEYIN_1                     ; $FCA3
.else
    sec                             ; $FC9E
    sty $1F                         ; $FC9F
    ldy #$03                        ; $FCA1
    bcc XGOTOCX                     ; $FCA3
.endif
    iny                             ; $FCA5
.if ENHANCED
    bne KEYIN_1                     ; $FCA6
.else
    bne XGOTOCX                     ; $FCA6
.endif
.else
    lda #' '                        ; $FC9E

CLEOL2:
    sta (BASL),y                    ; $FCA0
    iny                             ; $FCA1
    cpy WNDWDTH                     ; $FCA3
    bcc CLEOL2                      ; $FCA5
    rts                             ; $FCA7
.endif
