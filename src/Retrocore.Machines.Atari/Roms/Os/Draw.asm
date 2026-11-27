;; DRAWTO AND FILL ($FCFC-$FE44)
;;
;; The display handler's special commands: DRAWTO draws a line from the last point drawn to the cursor, and FILL
;; draws the same line, filling right from each point of it.

;; The display handler's SPECIAL entry: runs DRAWTO (CDRAW) or FILL (CFILL), and refuses any other command.
;; In: ICCOMZ = the command
;; Out: Y = the status: NVALID for another command, otherwise as <DRAW_LINE>'s
;; Uses: A, X
;; See: <DRAW_LINE>
SCREEN_SPECIAL:
    ldx #$00
    lda ICCOMZ
    cmp #CDRAW
    beq DRAW_LINE
    cmp #CFILL
    beq SCREEN_SPECIAL_FILL
    ldy #NVALID
    rts
SCREEN_SPECIAL_FILL:
    inx

;; Draws a line in ATACHR's colour from the last point drawn (OLDROW, OLDCOL) to the cursor, optionally filling.
;;
;; The longer of the row and column changes is ENDPT, the number of points drawn after the first; the first isn't
;; drawn again. For each point, DELTAR is added to ROWAC and DELTAC to COLAC, and an accumulator that reaches ENDPT
;; steps its axis by ROWINC or COLINC and drops by ENDPT. The longer axis so steps every time; the shorter one's
;; accumulator starts at half of ENDPT, so its steps fall midway.
;;
;; When filling, each point is followed by a run to the right in FILDAT's colour, up to the first point that isn't
;; colour 0, wrapping from the right edge to the left edge of the same row. In GRAPHICS 9-11 the cursor doesn't wrap,
;; so a run that reaches the right edge ends the FILL with CRSROR.
;;
;; It ends with the cursor at the line's end. The next DRAWTO starts from OLDROW and OLDCOL, the last point drawn,
;; which after a FILL can be the end of the last run rather than the line's end. A point out of range for the mode
;; ends it with CRSROR, and BREAK with BRKABT (<SCREEN_CHECK_CURSOR>).
;; In: X = 1 to fill, 0 not to, ATACHR = the line's colour, FILDAT = the fill's colour
;; Out: Y = the status, A = ATACHR
;; Uses: X, FILFLG, NEWROW, NEWCOL, ROWAC, COLAC, ENDPT, DELTAR, DELTAC, ROWINC, COLINC, COUNTR, OLDROW, OLDCOL,
;;   HOLD4, TMPROW, TMPCOL
DRAW_LINE:
    stx FILFLG
    lda ROWCRS
    sta NEWROW
    lda COLCRS
    sta NEWCOL
    lda COLCRS+1
    sta NEWCOL+1
    lda #$01
    sta ROWINC
    sta COLINC
    sec
    lda NEWROW
    sbc OLDROW
    sta DELTAR
    bcs DRAW_LINE_COLUMNS
    lda #$FF                        ; up: -1, and negate DELTAR
    sta ROWINC
    lda DELTAR
    eor #$FF
    clc
    adc #$01
    sta DELTAR
DRAW_LINE_COLUMNS:
    sec
    lda NEWCOL
    sbc OLDCOL
    sta DELTAC
    lda NEWCOL+1
    sbc OLDCOL+1
    sta DELTAC+1
    bcs DRAW_LINE_START
    lda #$FF                        ; left: -1, and negate DELTAC
    sta COLINC
    lda DELTAC
    eor #$FF
    sta DELTAC
    lda DELTAC+1
    eor #$FF
    sta DELTAC+1
    inc DELTAC
    bne DRAW_LINE_START
    inc DELTAC+1
DRAW_LINE_START:
    ldx #$02
    ldy #$00
    sty COLAC+1
DRAW_LINE_CLEAR:
    tya
    sta ROWAC,x                     ; ROWAC and COLAC's low byte = 0
    lda OLDROW,x
    sta ROWCRS,x                    ; the cursor back to the start
    dex
    bpl DRAW_LINE_CLEAR
    lda DELTAC
    inx                             ; X = 0: the rows are the shorter axis
    tay
    lda DELTAC+1
    sta COUNTR+1
    sta ENDPT+1
    bne DRAW_LINE_LONGER
    lda DELTAC
    cmp DELTAR
    bcs DRAW_LINE_LONGER
    lda DELTAR                      ; the rows change more
    ldx #$02                        ; X = 2: the columns are the shorter axis
    tay
DRAW_LINE_LONGER:
    tya
    sta COUNTR
    sta ENDPT
    pha
    lda ENDPT+1
    lsr A
    pla
    ror A                           ; half of ENDPT ...
    sta ROWAC,x                     ; ... starts the shorter axis's accumulator
DRAW_LINE_LOOP:
    lda COUNTR
    ora COUNTR+1
    bne DRAW_LINE_ROW
    jmp DRAW_LINE_DONE
DRAW_LINE_ROW:
    clc
    lda ROWAC
    adc DELTAR
    sta ROWAC
    bcc DRAW_LINE_ROW_TEST
    inc ROWAC+1
DRAW_LINE_ROW_TEST:
    lda ROWAC+1
    cmp ENDPT+1
    bcc DRAW_LINE_COLUMN
    bne DRAW_LINE_ROW_STEP
    lda ROWAC
    cmp ENDPT
    bcc DRAW_LINE_COLUMN
DRAW_LINE_ROW_STEP:
    clc
    lda ROWCRS
    adc ROWINC
    sta ROWCRS
    ldx #$00
    jsr SCREEN_SUBTRACT_ENDPT                      ; ROWAC -= ENDPT
DRAW_LINE_COLUMN:
    clc
    lda COLAC
    adc DELTAC
    sta COLAC
    lda COLAC+1
    adc DELTAC+1
    sta COLAC+1
    cmp ENDPT+1
    bcc DRAW_LINE_PLOT
    bne DRAW_LINE_COLUMN_STEP
    lda COLAC
    cmp ENDPT
    bcc DRAW_LINE_PLOT
DRAW_LINE_COLUMN_STEP:
    bit COLINC
    bpl DRAW_LINE_RIGHT
    dec COLCRS
    lda COLCRS
    cmp #$FF
    bne DRAW_LINE_COLUMN_DONE
    lda COLCRS+1
    beq DRAW_LINE_COLUMN_DONE
    dec COLCRS+1
    bpl DRAW_LINE_COLUMN_DONE       ; always
DRAW_LINE_RIGHT:
    inc COLCRS
    bne DRAW_LINE_COLUMN_DONE
    inc COLCRS+1
DRAW_LINE_COLUMN_DONE:
    ldx #$02
    jsr SCREEN_SUBTRACT_ENDPT                      ; COLAC -= ENDPT
DRAW_LINE_PLOT:
    jsr SCREEN_CHECK_CURSOR                      ; check the point, or end with an error
    jsr DISPLAY_PLOT                      ; draw it, which makes it OLDROW and OLDCOL
    lda FILFLG
    beq DRAW_LINE_COUNT
    jsr SCREEN_SAVE_CURSOR                      ; keep the point
    lda ATACHR
    sta HOLD4
DRAW_LINE_FILL:
    lda ROWCRS
    pha
    jsr SCREEN_ADVANCE_KEEP                      ; right a point, wrapping at the edge ...
    pla
    sta ROWCRS                      ; ... in the same row
    jsr SCREEN_CHECK_CURSOR
    jsr DISPLAY_READ
    bne DRAW_LINE_FILL_DONE         ; up to a point that isn't colour 0
    lda FILDAT
    sta ATACHR
    jsr DISPLAY_PLOT
    jmp DRAW_LINE_FILL
DRAW_LINE_FILL_DONE:
    lda HOLD4
    sta ATACHR
    jsr SCREEN_RESTORE_CURSOR                      ; back to the point
DRAW_LINE_COUNT:
    sec
    lda COUNTR
    sbc #$01
    sta COUNTR
    lda COUNTR+1
    sbc #$00
    sta COUNTR+1
    bmi DRAW_LINE_DONE
    jmp DRAW_LINE_LOOP
DRAW_LINE_DONE:
    jmp DISPLAY_RETURN                      ; Y = the status
