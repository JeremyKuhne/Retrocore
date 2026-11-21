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
