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
