; retrocore: style=strict
;; The screen modes and the text window ($FB2F-$FB5F): text, mixed lo-res graphics, the window and the cursor's
;; line.

; The text screen.

;; The text screen's width in 40-column mode, which the Apple II's Monitors set the window to.
SCREEN_WIDTH = 40

;; The text screen's lines.
SCREEN_LINES = 24

;; The first text line in mixed graphics, below the lo-res graphics' 40 rows.
MIXED_TEXT_TOP = 20

;; Sets text mode with a full window, and the lo-res and page-one switches for later graphics; clears STATUS.
;;
;; At $FB2F.
;; Out: SavedStatus = 0
;; Also: INIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc InitDisplay
    .assert * = $FB2F, "InitDisplay must stay at $FB2F."
    lda #0
    sta SavedStatus
    lda HiResOff
    lda Page2Off
    ; Falls into SetText.
.endproc

;; Sets text mode with a full window.
;;
;; At $FB39.
;; Also: SETTXT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetText
    .assert * = $FB39, "SetText must stay at $FB39."
    lda TextOn
    lda #0
    beq SetWindow
.endproc

;; Sets mixed lo-res graphics with four text lines, and clears the graphics area.
;;
;; At $FB40. The text window is the four lines below the graphics.
;; Also: SETGR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetGraphics
    .assert * = $FB40, "SetGraphics must stay at $FB40."
    lda TextOff
    lda MixedOn
    jsr LowRes::ClearTop
    lda #MIXED_TEXT_TOP
    ; Falls into SetWindow.
.endproc

;; Sets the text window from line A down: WNDTOP = A, WNDLFT = 0, and the width and bottom for the current
;; display, through the internal firmware, which also moves the cursor to the bottom line.
;;
;; At $FB4B. The Apple II's Monitors set the 40-column width here themselves, then WNDBTM = 24, and move the
;; cursor to the bottom line (<VerticalTabTo>).
;; In: A = the window's top line
;; Out: WindowTop, WindowLeft, WindowWidth, WindowBottom, CV = the bottom line
;; Also: SETWND (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetWindow
    .assert * = $FB4B, "SetWindow must stay at $FB4B."
    sta WindowTop
    lda #0
    sta WindowLeft
.if MONITOR = MONITOR_IIE

    ; The firmware does the rest, for 40 or 80 columns.
    ldy #FIRMWARE_SET_WINDOW
    bne CallFirmware
.else

    ; 40 columns.
    lda #SCREEN_WIDTH
    sta WindowWidth
.endif

    ; The full screen's bottom, and the cursor on its last line. On the IIe nothing reaches these six bytes.
    lda #SCREEN_LINES
    sta WindowBottom
    lda #SCREEN_LINES - 1
    ; Falls into VerticalTabTo.
.endproc

;; Moves the cursor to a line.
;;
;; At $FB5B.
;; In: A = the line, 0-23
;; Out: CV = A, TextBase/TextBaseHigh = its base address (<VerticalTab>)
;; Also: TABV (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc VerticalTabTo
    .assert * = $FB5B, "VerticalTabTo must stay at $FB5B."
    sta CV
    jmp VerticalTab
.endproc
