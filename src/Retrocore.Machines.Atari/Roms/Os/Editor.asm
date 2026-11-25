;; THE DISPLAY HANDLER AND THE SCREEN EDITOR ($F3E4-$F6E1)
;;
;; The display handler (S:) opens a display mode: it builds ANTIC's display list and allocates the screen memory below
;; RAMTOP, with a text window of four lines below the graphics when asked, and sets the colours and the tab stops.
;; Its get reads the character or pixel at the cursor, and its put writes one there. The screen editor (E:) is the
;; same handler in mode 0: its put obeys the control codes and shows the other characters, and its get echoes the
;; keys typed until RETURN and then returns the logical line from the screen, a character a call. The cursor
;; movement, the scrolling and the control codes' routines are in <EDIT_ESCAPE> and after; the mode tables
;; (<MODE_ANTIC_CODES>, <MODE_MEMORY_SIZES>, <MODE_LINE_COUNTS>, <MODE_LIST_PAGES>) are in the tables at $FE45.

; The characters the handlers act on, and the key codes they share with the keyboard handler.

DISPLAY_INVERSE = $80               ;; a character's bit for inverse video, and the cursor's
KEY_NONE = $FF                      ;; CH with no key waiting
KEY_SHIFT = $40                     ;; a key code's SHIFT bit, and SHFLOK's value for upper case
KEY_CONTROL = $80                   ;; a key code's CTRL bit, and SHFLOK's value for control characters
KEYBOARD_IRQS = IRQ_BREAK | IRQ_KEY                 ;; IRQEN's BREAK key (bit 7) and keyboard (bit 6) interrupts

; The display modes, as the open's tables number them (GRAPHICS 0-11).

DISPLAY_MODE_BITS = $0F             ;; ICAX2's display mode bits; in ICAX1, the direction and forced read bits
DISPLAY_FIRST_HIRES = 8             ;; the first mode whose screen crosses a 4K boundary, needing a second LMS
DISPLAY_FIRST_GTIA = 9              ;; the first of GTIA's modes, which have no text window
DISPLAY_GTIA_HUES = 11              ;; GTIA's mode of 16 hues, which takes its luminance from COLOR4
DISPLAY_GTIA_LUMINANCE = $06        ;; the luminance mode 11 sets in COLOR4
DISPLAY_GTIA_BITS = $C0             ;; PRIOR's GTIA mode bits

; The screen's layout.

DISPLAY_LINE_BYTES = 40             ;; a text line's bytes, and the unit MODE_MEMORY_SIZES counts the screen memory in
DISPLAY_LINES = 24                  ;; the text lines of a full screen, BOTSCR's value
DISPLAY_WINDOW_LINES = 4            ;; the text lines of a split screen's window, BOTSCR's value
DISPLAY_BOUNDARY_PAD = 16           ;; unused bytes above modes 8-11's screen, so a line starts on the 4K boundary
DISPLAY_UPPER_LINES = 93            ;; modes 8-11's lines between the first LMS line and the one at the 4K boundary
DISPLAY_WAIT_VCOUNT = $7A           ;; VCOUNT at scan line 244, below the screen, where the open waits
DISPLAY_TAB_STOPS = $01             ;; each TABMAP byte after an open: a stop at the last of its eight columns
DISPLAY_CHACTL = $02                ;; CHACTL's setting: characters with bit 7 shown in inverse video
DISPLAY_DMA_NORMAL = $02            ;; DMACTL's normal playfield width, 40 characters
DISPLAY_DMA_LIST = $20              ;; DMACTL's display list DMA
EDITOR_BELL_COLUMN = 113            ;; the column of the 120-column logical line where typing sounds the bell

; ANTIC's display list instructions, as the open builds them.

DL_BLANK_8 = $70                    ;; eight blank scan lines
DL_LMS = $40                        ;; load memory scan: the next two bytes are the line's address
DL_JVB = $41                        ;; jump and wait for the vertical blank: the next two bytes are the list's start
DL_TEXT = $02                       ;; ANTIC mode 2, 40 characters, the text window's lines
DL_HIRES = $0F                      ;; ANTIC mode 15, 320 dots, the lines of modes 8-11

;; Initializes the display, editor and keyboard handlers, at power-up and SYSTEM RESET: no key waiting, RAMTOP from
;; MEMTOP, and caps lock on.
;;
;; All three handlers' tables have this as their initialization. RAMTOP is MEMTOP's page rounded down to a 4K
;; boundary.
;; Out: CH = KEY_NONE, RAMTOP, SHFLOK = KEY_SHIFT
;; Uses: A
;; Keeps: X, Y
;; See: <EDITRV>, <SCRENV>, <KEYBDV>
EDITOR_INIT:
    lda #KEY_NONE
    sta CH
    lda MEMTOP+1
    and #$F0                        ; a 4K boundary
    sta RAMTOP
    lda #KEY_SHIFT
    sta SHFLOK
    rts

;; The display handler's (S:) open: sets up the display mode ICAX2 asks for, with a text window and a cleared screen
;; as ICAX1 asks.
;;
;; Mode 0 opens as the screen editor does (<EDITOR_OPEN>), full and cleared whatever ICAX1 says. The open sets the
;; character set, the colours and the tab stops, then allocates the screen memory down from RAMTOP and builds the
;; display list below it, backwards, ending at the top of a page in modes 7-11 so that it doesn't cross a 1K
;; boundary. Modes 8-11 take a second LMS at the 4K boundary their screen crosses, and modes 9-11 set GTIA's mode
;; in GPRIOR. A split screen's window is four text lines at RAMTOP-$A0, which TXTMSC holds; the graphics' screen
;; starts at SAVMSC. MEMTOP ends just below the display list. Unless ICAX1 says not to, the screen is cleared and
;; the window's cursor homed. On an error the screen editor is opened again in mode 0.
;; In: ICAX1Z = the open mode (OSPLIT for a text window, OCLEAR not to clear), ICAX2Z = the display mode
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Errors: Y = BADMOD for a mode beyond 11, SCRMEM when the screen would reach APPMHI
;; Uses: X, DINDEX, CHBAS, CHACT, SDMCTL, POKMSK, IRQEN, TINDEX, SWPFLG, CRSINH, TABMAP, COLOR0..COLOR4, TXTMSC,
;;   GPRIOR, SAVMSC, BOTSCR, SDLSTL, SDLSTH, MEMTOP, TXTROW, TXTCOL, HOLD1, ADRESS, SAVADR, TOADR
;; See: <EDITOR_OPEN>, <DISPLAY_SHOW_CURSOR>
DISPLAY_OPEN:
    lda ICAX2Z
    and #DISPLAY_MODE_BITS
    bne EDITOR_OPEN_MODE            ; a graphics mode

;; The screen editor's (E:) open, and the display handler's for mode 0: a full text screen, cleared.
;;
;; <SCREEN_EDITOR_CHECK> calls it to put mode 0 back when the editor is used on a full graphics screen.
;; It changes what <DISPLAY_OPEN> lists.
;; In: ICAX1Z = the open mode
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; See: <DISPLAY_OPEN>
EDITOR_OPEN:
    lda ICAX1Z
    and #DISPLAY_MODE_BITS          ; no text window, and clear the screen
    sta ICAX1Z
    lda #$00
EDITOR_OPEN_MODE:
    sta DINDEX
    lda #>DISPLAY_CHARACTER_SET
    sta CHBAS
    lda #DISPLAY_CHACTL
    sta CHACT
    sta SDMCTL                      ; DISPLAY_DMA_NORMAL: the display list off while it's built
    lda #SUCCES
    sta DSTAT
    lda #KEYBOARD_IRQS
    ora POKMSK
    sta POKMSK
    sta IRQEN
    lda #$00
    sta TINDEX                      ; the text window is mode 0
    sta ADRESS
    sta SWPFLG
    sta CRSINH
    ldy #LOGMAP-TABMAP-1
    lda #DISPLAY_TAB_STOPS
EDITOR_OPEN_TABS:
    sta TABMAP,y
    dey
    bpl EDITOR_OPEN_TABS
    ldx #COLOR4-COLOR0
EDITOR_OPEN_COLOURS:
    lda DEFAULT_COLOURS,x
    sta COLOR0,x
    dex
    bpl EDITOR_OPEN_COLOURS
    ldy RAMTOP
    dey
    sty TXTMSC+1
    lda #$100 - DISPLAY_WINDOW_LINES * DISPLAY_LINE_BYTES
    sta TXTMSC                      ; the window's four lines end at RAMTOP
    ldx DINDEX
    lda MODE_ANTIC_CODES,x                    ; the mode's ANTIC mode
    bne EDITOR_OPEN_VALID
    lda #BADMOD                     ; past the table: 0
    sta DSTAT
EDITOR_OPEN_VALID:
    sta HOLD1
    lda RAMTOP
    sta ADRESS+1
    ldy MODE_MEMORY_SIZES,x                    ; the screen's size, in lines of 40 bytes
EDITOR_OPEN_ALLOCATE:
    lda #DISPLAY_LINE_BYTES
    jsr SCREEN_RESERVE
    dey
    bne EDITOR_OPEN_ALLOCATE
    lda GPRIOR
    and #DISPLAY_GTIA_BITS ^ $FF
    sta TOADR+1
    tay
    cpx #DISPLAY_FIRST_HIRES
    bcc EDITOR_OPEN_PRIORITY
    txa                             ; carry is set: modes 8-11 rotate to $00, $40, $80, $C0
    ror A
    ror A
    ror A
    and #DISPLAY_GTIA_BITS
    ora TOADR+1
    tay
    lda #DISPLAY_BOUNDARY_PAD
    jsr SCREEN_RESERVE
    cpx #DISPLAY_GTIA_HUES
    bne EDITOR_OPEN_PRIORITY
    lda #DISPLAY_GTIA_LUMINANCE
    sta COLOR4
EDITOR_OPEN_PRIORITY:
    sty GPRIOR
    lda ADRESS
    sta SAVMSC
    lda ADRESS+1
    sta SAVMSC+1
EDITOR_OPEN_WAIT:
    lda VCOUNT
    cmp #DISPLAY_WAIT_VCOUNT
    bne EDITOR_OPEN_WAIT
    jsr SCREEN_RESERVE_1                      ; the display list's last byte
    lda MODE_LIST_PAGES,x
    beq EDITOR_OPEN_LIST
    lda #$FF                        ; a long list: from the top of the page below
    sta ADRESS
    dec ADRESS+1
EDITOR_OPEN_LIST:
    lda ADRESS
    sta SAVADR                      ; where the jump's address goes, last
    lda ADRESS+1
    sta SAVADR+1
    jsr SCREEN_RESERVE_2
    lda #DL_JVB
    jsr SCREEN_PUT_BYTE
    stx TOADR                       ; the mode, MODE_LINE_COUNTS's index
    lda #DISPLAY_LINES
    sta BOTSCR
    lda DINDEX
    cmp #DISPLAY_FIRST_GTIA
    bcs EDITOR_OPEN_LINES
    lda ICAX1Z
    and #OSPLIT
    beq EDITOR_OPEN_LINES
    lda #DISPLAY_WINDOW_LINES
    sta BOTSCR
    ldx #DISPLAY_WINDOW_LINES-2
EDITOR_OPEN_WINDOW:
    lda #DL_TEXT
    jsr SCREEN_PUT_BYTE
    dex
    bpl EDITOR_OPEN_WINDOW
    ldy RAMTOP
    dey
    tya
    jsr SCREEN_PUT_BYTE
    lda #$100 - DISPLAY_WINDOW_LINES * DISPLAY_LINE_BYTES
    jsr SCREEN_PUT_BYTE
    lda #DL_LMS | DL_TEXT           ; the window's first line, at TXTMSC
    jsr SCREEN_PUT_BYTE
    clc
    lda #MODE_COUNT         ; the split screens' line counts
    adc TOADR
    sta TOADR
EDITOR_OPEN_LINES:
    ldy TOADR
    ldx MODE_LINE_COUNTS,y                    ; the lines after the first
EDITOR_OPEN_LOWER:
    lda HOLD1
    jsr SCREEN_PUT_BYTE
    dex
    bne EDITOR_OPEN_LOWER
    lda DINDEX
    cmp #DISPLAY_FIRST_HIRES
    bcc EDITOR_OPEN_TOP
    ldx #DISPLAY_UPPER_LINES
    lda RAMTOP
    sec
    sbc #$10                        ; RAMTOP less 4K
    jsr SCREEN_PUT_BYTE
    lda #$00
    jsr SCREEN_PUT_BYTE
    lda #DL_LMS | DL_HIRES          ; the line at the 4K boundary
    jsr SCREEN_PUT_BYTE
EDITOR_OPEN_UPPER:
    lda HOLD1
    jsr SCREEN_PUT_BYTE
    dex
    bne EDITOR_OPEN_UPPER
EDITOR_OPEN_TOP:
    lda SAVMSC+1
    jsr SCREEN_PUT_BYTE
    lda SAVMSC
    jsr SCREEN_PUT_BYTE
    lda HOLD1
    ora #DL_LMS                     ; the first line, at SAVMSC
    jsr SCREEN_PUT_BYTE
    lda #DL_BLANK_8
    jsr SCREEN_PUT_BYTE
    lda #DL_BLANK_8
    jsr SCREEN_PUT_BYTE
    lda ADRESS
    sta SDLSTL
    lda ADRESS+1
    sta SDLSTH
    lda #DL_BLANK_8                 ; the list's first instruction
    jsr SCREEN_PUT_BYTE
    lda ADRESS
    sta MEMTOP
    lda ADRESS+1
    sta MEMTOP+1
    lda SAVADR
    sta ADRESS
    lda SAVADR+1
    sta ADRESS+1
    lda SDLSTH                      ; the jump's address
    jsr SCREEN_PUT_BYTE
    lda SDLSTL
    jsr SCREEN_PUT_BYTE
    lda DSTAT
    bpl EDITOR_OPEN_CLEAR
    pha
    jsr EDITOR_OPEN                 ; back to mode 0
    pla
    tay
    rts
EDITOR_OPEN_CLEAR:
    lda ICAX1Z
    and #OCLEAR
    bne EDITOR_OPEN_ENABLE
    jsr EDIT_CLEAR_SCREEN
    sta TXTROW
    lda LMARGN
    sta TXTCOL
EDITOR_OPEN_ENABLE:
    lda #DISPLAY_DMA_LIST | DISPLAY_DMA_NORMAL
    ora SDMCTL
    sta SDMCTL
    jmp DISPLAY_SHOW_CURSOR

;; The display handler's (S:) get: reads the character or pixel at the cursor and moves the cursor on.
;;
;; <EDITOR_GET> reads a logical line's characters from the screen with it.
;; Out: A = the ATASCII character or the pixel's colour, Y = the status, DSTAT = SUCCES
;; Errors: Y = CRSROR when the cursor is outside the screen, BRKABT for BREAK
;; Uses: X, ATACHR, CHAR, COLCRS, ROWCRS, LOGCOL
DISPLAY_GET:
    jsr SCREEN_CHECK_CURSOR
    jsr DISPLAY_READ
    jsr SCREEN_TO_ATASCII                      ; to ATASCII
    jsr SCREEN_ADVANCE
    jmp DISPLAY_RETURN

;; Reads the data at the cursor: a character's internal code, or a pixel's colour.
;; Out: A = CHAR = the data, zero = it is 0
;; Uses: X, Y, ADRESS, SHFAMT
DISPLAY_READ:
    jsr SCREEN_LOCATE
    lda (ADRESS),y
    and DMASK
DISPLAY_READ_SHIFT:
    lsr SHFAMT
    bcs DISPLAY_READ_DONE
    lsr A
    bpl DISPLAY_READ_SHIFT          ; always
DISPLAY_READ_DONE:
    sta CHAR
    cmp #$00
    rts

;; The display handler's (S:) put: writes a character or a pixel at the cursor and moves the cursor on.
;;
;; Of the control codes, only clear screen and EOL are obeyed; the rest are shown.
;; In: A = the ATASCII character, or the colour
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Errors: Y = CRSROR when the cursor is outside the screen, BRKABT for BREAK
;; Uses: X, ATACHR, CHAR, COLCRS, ROWCRS, LOGCOL, OLDROW, OLDCOL
DISPLAY_PUT:
    sta ATACHR
    jsr SCREEN_CHECK_CURSOR
    lda ATACHR
    cmp #CLEAR_SCREEN
    bne DISPLAY_SHOW
    jsr EDIT_CLEAR_SCREEN
    jmp DISPLAY_SHOW_CURSOR

;; Shows the character in ATACHR at the cursor and moves the cursor on, or starts a new line for EOL.
;;
;; <EDITOR_PUT_CHARACTER> joins here for a character it doesn't obey.
;; In: ATACHR = the character
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Uses: X, CHAR, COLCRS, ROWCRS, LOGCOL, OLDROW, OLDCOL
DISPLAY_SHOW:
    lda ATACHR
    cmp #EOL
    bne DISPLAY_SHOW_CHARACTER
    jsr SCREEN_NEW_LINE_EOL
    jmp DISPLAY_SHOW_CURSOR
DISPLAY_SHOW_CHARACTER:
    jsr DISPLAY_PLOT
    jsr SCREEN_ADVANCE_WRITE
    jmp DISPLAY_SHOW_CURSOR

;; Writes the character or colour in ATACHR at the cursor, after waiting while CTRL+1 has stopped the screen.
;;
;; The cursor's position is kept in OLDROW and OLDCOL, where DRAWTO starts. The character goes from ATASCII to the
;; internal code; a colour's bits pass through, the rest being masked off.
;; In: ATACHR = the character or colour
;; Uses: A, X, Y, CHAR, OLDROW, OLDCOL, TMPCHR
;; See: <ATASCII_TO_INTERNAL>
DISPLAY_PLOT:
    lda SSFLAG
    bne DISPLAY_PLOT                ; stopped
    ldx #$02
DISPLAY_PLOT_CURSOR:
    lda ROWCRS,x
    sta OLDROW,x
    dex
    bpl DISPLAY_PLOT_CURSOR
    lda ATACHR
    tay
    rol A
    rol A
    rol A
    rol A
    and #$03                        ; bits 5 and 6
    tax
    tya
    and #$9F
    ora ATASCII_TO_INTERNAL,x

;; Writes a character's internal code, or a colour, at the cursor.
;; In: A = the data
;; Out: CHAR = the data
;; Uses: A, X, Y, ADRESS, SHFAMT, TMPCHR
DISPLAY_WRITE:
    sta CHAR
    jsr SCREEN_LOCATE
    lda CHAR
DISPLAY_WRITE_SHIFT:
    lsr SHFAMT
    bcs DISPLAY_WRITE_MERGE
    asl A
    jmp DISPLAY_WRITE_SHIFT
DISPLAY_WRITE_MERGE:
    and DMASK
    sta TMPCHR
    lda DMASK
    eor #$FF
    and (ADRESS),y
    ora TMPCHR
    sta (ADRESS),y
    rts

;; Keeps the data under the cursor in OLDCHR and, in mode 0 unless CRSINH hides it, shows the cursor by inverting
;; it; then returns the status.
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Uses: X, OLDCHR, CHAR
DISPLAY_SHOW_CURSOR:
    jsr DISPLAY_READ
    sta OLDCHR
    ldx DINDEX
    bne DISPLAY_RETURN
    ldx CRSINH
    bne DISPLAY_RETURN
    eor #DISPLAY_INVERSE
    jsr DISPLAY_WRITE

;; Returns the display handler's status and resets it: the end of each handler call, and the close of E:, S: and K:.
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Entry: DISPLAY_IGNORE = only returns: the SPECIAL of E: and K:, and K:'s PUT BYTE
;; Keeps: X
DISPLAY_RETURN:
    ldy DSTAT
    lda #SUCCES
    sta DSTAT
    lda ATACHR
DISPLAY_IGNORE:
    rts

;; The screen editor's (E:) get: returns the next character of a logical line, reading the line from the screen once
;; RETURN has been pressed.
;;
;; When no line is waiting, it echoes the keys typed and obeys their control codes, sounding the bell as the logical
;; line nears its end, until RETURN. It then measures the logical line from BUFSTR, where the input began or the
;; cursor moves put it, to its last character that isn't blank, and returns it a character a call, then an EOL,
;; after which the cursor goes to the next line. With a forced read open, <KEYBOARD_GET> answers RETURN at once, so
;; the line already on the screen is read. BREAK and CTRL+3 end the line with their status.
;; Out: A = the character, Y = the status, DSTAT = SUCCES
;; Errors: Y = BRKABT for BREAK, EOFERR for CTRL+3, CRSROR when the cursor is outside the screen
;; Uses: X, ATACHR, BUFCNT, BUFSTR, ROWCRS, COLCRS, LOGCOL, OLDCHR, SWPFLG
;; See: <EDITOR_PUT_CHARACTER>, <SCREEN_MEASURE_LINE>
EDITOR_GET:
    jsr SCREEN_SWAP_RETURN                      ; the text window's variables
    jsr SCREEN_EDITOR_CHECK
    lda BUFCNT
    bne EDITOR_GET_BUFFERED
    lda ROWCRS
    sta BUFSTR
    lda COLCRS
    sta BUFSTR+1
EDITOR_GET_KEY:
    jsr KEYBOARD_GET
    sty DSTAT
    lda ATACHR
    cmp #EOL
    beq EDITOR_GET_LINE
    jsr EDITOR_PUT_CHARACTER
    jsr SCREEN_SWAP_RETURN
    lda LOGCOL
    cmp #EDITOR_BELL_COLUMN
    bne EDITOR_GET_NEXT
    jsr EDIT_BELL
EDITOR_GET_NEXT:
    jmp EDITOR_GET_KEY
EDITOR_GET_LINE:
    jsr SCREEN_ERASE_CURSOR                      ; the cursor off
    jsr SCREEN_MEASURE_LINE
    lda BUFSTR
    sta ROWCRS
    lda BUFSTR+1
    sta COLCRS
EDITOR_GET_BUFFERED:
    lda BUFCNT
    beq EDITOR_GET_END
EDITOR_GET_SKIP:
    dec BUFCNT
    beq EDITOR_GET_END
    lda DSTAT
    bmi EDITOR_GET_SKIP             ; an error: to the line's end
    jsr DISPLAY_GET
    sta ATACHR
    jmp SCREEN_SWAP_RETURN
EDITOR_GET_END:
    jsr SCREEN_NEW_LINE_EOL
    lda #EOL
    sta ATACHR
    jsr DISPLAY_SHOW_CURSOR
    sty DSTAT                       ; the status, for SCREEN_SWAP_RETURN to return
    jmp SCREEN_SWAP_RETURN

;; Jumps to the routine at ADRESS, so that a JSR here calls it.
;; In: ADRESS = the routine
EDITOR_CALL_ADRESS:
    jmp (ADRESS)

;; The screen editor's (E:) put: obeys a control code, or shows any other character, in the text window.
;; In: A = the ATASCII character
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Errors: Y = CRSROR when the cursor is outside the screen, BRKABT for BREAK
;; Uses: X, ATACHR, ESCFLG, ROWCRS, COLCRS, LOGCOL, OLDCHR, SWPFLG
;; See: <EDITOR_PUT_CHARACTER>
EDITOR_PUT:
    sta ATACHR
    jsr SCREEN_SWAP_RETURN                      ; the text window's variables
    jsr SCREEN_EDITOR_CHECK

;; Obeys the control code in ATACHR or shows the character, with the text window's variables swapped in, and swaps
;; them out again.
;;
;; A control code is shown instead when DSPFLG is set or it follows ESC; either way ESCFLG is cleared. Its routine
;; comes from the control code table, <CONTROL_CODES>.
;; In: ATACHR = the character
;; Out: Y = the status, A = ATACHR (Y again on an error), DSTAT = SUCCES
;; Uses: X, ESCFLG, ADRESS, ROWCRS, COLCRS, LOGCOL, OLDCHR, SWPFLG
EDITOR_PUT_CHARACTER:
    jsr SCREEN_ERASE_CURSOR                      ; the cursor off
    jsr SCREEN_FIND_CONTROL_CODE
    beq EDITOR_PUT_CONTROL
EDITOR_PUT_SHOW:
    asl ESCFLG
    jsr DISPLAY_SHOW
    jmp SCREEN_SWAP_RETURN
EDITOR_PUT_CONTROL:
    lda DSPFLG
    ora ESCFLG
    bne EDITOR_PUT_SHOW
    asl ESCFLG
    inx                             ; the routine's address
    lda CONTROL_CODES,x
    sta ADRESS
    lda CONTROL_CODES+1,x
    sta ADRESS+1
    jsr EDITOR_CALL_ADRESS
    jsr DISPLAY_SHOW_CURSOR
    jmp SCREEN_SWAP_RETURN

;; Discards the key in CH and waits for another, for a key that types nothing.
;; Out: A = the character, Y = the status, DSTAT = SUCCES
;; See: <KEYBOARD_GET>
KEYBOARD_GET_AGAIN:
    lda #KEY_NONE
    sta CH
