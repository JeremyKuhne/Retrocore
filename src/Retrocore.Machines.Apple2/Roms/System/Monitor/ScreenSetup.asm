;; Sets text mode with a full window, and the lo-res and page-one switches for later graphics.
;; Clears STATUS.
INIT:
    lda #$00                        ; $FB2F
    sta STATUS                      ; $FB31
    lda LORES                       ; $FB33
    lda LOWSCR                      ; $FB36

;; Sets text mode with a full window.
SETTXT:
    lda TXTSET                      ; $FB39
    lda #$00                        ; $FB3C
    beq SETWND                      ; $FB3E

;; Sets mixed lo-res graphics with four text lines, and clears the graphics area.
SETGR:
    lda TXTCLR                      ; $FB40
    lda MIXSET                      ; $FB43
    jsr CLRTOP                      ; $FB46
    lda #$14                        ; $FB49

;; Sets the text window: WNDTOP = A, WNDLFT = 0, and the width and bottom for the current
;; display (40 or 80 columns) through the internal firmware.
;;
;; The Apple II's Monitors set the 40-column width here themselves, then WNDBTM = 24, and move the
;; cursor to the bottom line (TABV).
;; In: A = top line
SETWND:
    sta WNDTOP                      ; $FB4B
    lda #$00                        ; $FB4D
    sta WNDLFT                      ; $FB4F
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$0C                        ; $FB51
.else
    ldy #$08                        ; $FB51
.endif
    bne GOTOCX                      ; $FB53
.else
    lda #$28                        ; $FB51
    sta WNDWDTH                     ; $FB53
.endif

SETWND_1:
    lda #$18                        ; $FB55
    sta WNDBTM                      ; $FB57
    lda #$17                        ; $FB59

;; Moves the cursor to a line.
;; In: A = line (0-23)
;; Out: CV = A, BASL/BASH set for it (VTAB)
TABV:
    sta CV                          ; $FB5B
    jmp VTAB                        ; $FB5D
