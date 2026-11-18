;; COMMODORE PET 2001 BASIC 1 SCREEN EDITOR ($E1E1-$E7FF)
;;
;; The screen editor is the PET 2001's console: it starts the I/O chips and the screen at reset, takes the 60 Hz
;; interrupt that scans the keyboard, blinks the cursor and runs the jiffy clock, prints characters on the 40 by 25
;; screen, and reads back the line the cursor is on when RETURN is pressed, so that any line on the screen can be
;; edited and entered again.
;;
;; The screen is made of logical lines of one or two rows. The link table, <LDTB1>, holds each row's page in video
;; RAM with bit 7 set when the row starts a line; printing past a line's 40th column joins the next row onto it, and
;; scrolling and inserting move the links with the text. <PNT>, <PNTR> and <TBLX> are the cursor: its line's address,
;; its column in the line, and its row.
;;
;; The kernal calls the editor through four routines: <PRT> puts a character on the screen, acting on the cursor
;; and editing keys; <LOOP5> reads a line from the screen; <LP2> takes a key from the keyboard buffer; and <CINT>
;; starts the hardware. The 2001's video RAM shows snow if the 6502 writes it while the screen is drawn, so the editor
;; stores characters only during vertical blanking (<DSPP>), and blanks the screen while it moves a whole screen's
;; text.
;;
;; The chip, 901447-05 at $E000-$E7FF, starts with the end of BASIC 1: the end of its math package, <INIT>, the
;; sign-on and some patches run to $E1E0, and BASIC's sources build them. This file is the editor, from $E1E1 to the
;; end of the chip, but for six bytes at $E7F3-$E7F8 that are another BASIC patch, ARYINC, which it reserves.
;;
;; The routines take Commodore's names from its BASIC 4 kernal listing of 1979 where BASIC 4 has the same code,
;; and otherwise are named after what they do.
;;
;; It includes ../PetEquates.asm (the hardware), Equates.asm (the RAM the editor and kernal share, and what they use
;; of BASIC) and KernalEntries.asm (the kernal routines it calls).
;;
;; Assembles byte-identically to the 901447-05 ROM's $E1E1-$E7F2 and $E7F9-$E7FF.
;;
;; Maintained by hand.

.cpu Mos6502

.include "../PetEquates.asm"
.include "Equates.asm"
.include "KernalEntries.asm"

COLUMNS = 40                        ;; the screen's width, and the length of a row in video RAM
ROWS = 25                           ;; the screen's height
KEYBUF_SIZE = 10                    ;; the keys the keyboard buffer holds
KEY_COUNT = 80                      ;; the keys in the keyboard matrix: 10 rows of 8
BLINK_JIFFIES = 20                  ;; the cursor's blink rate: three times a second

.org $E1E1

;; Starts the hardware and the editor at reset: clears page 2, points <CINV> at <KEY>, makes the screen the output
;; device, sets up both PIAs and the VIA, stops the cursor, and clears the screen (<CLSR>).
;;
;; The VIA's interrupts are turned off, PIA 1's port A drives the keyboard rows, and PIA 1 interrupts on the retrace
;; through CB1; both cassette motors are stopped and the IEEE-488 lines are let go. It also sets <BUF>-4 and <BUF>-3 for
;; BASIC.
;;
;; Out: X = 0, Y = 0, from homing the cursor
;; Uses: A
;; Entry: CINT_PAGE2 = the kernal's test enters here with X = the bytes of page 2 to clear plus one
CINT:
    lda #$7F                        ; the VIA's interrupts off
    sta VIA_IER
    sta BUF-4                       ; nonzero bytes before BASIC's buffer
    sta BUF-3
    ldx #$00
    txa

CINT_1:
    sta TIME,x                      ; clear page 2

CINT_PAGE2:
    dex
    bne CINT_1
    dex                             ; X = $FF
    lda #<KEY
    sta CINV
    lda #>KEY
    sta CINV+1
    lda #DEV_SCREEN                 ; output to the screen
    sta DFLTO
    lda #$0F                        ; PIA 1: PA0-PA3 out, the keyboard row
    sta PIA1_PA
    asl a                           ; the VIA: PB1-PB4 out, with NRFD and ATN high, and the motor stopped
    sta VIA_ORB
    sta VIA_DDRB
    stx PIA2_PB                     ; PIA 2: port B, the bus's data out, all outputs
    stx VIA_T1CH                    ; start timer 1
    lda #PIA_HIGH_IRQ               ; PIA 1: the retrace interrupts, and motor 1 stopped
    sta PIA1_CRB
    bit PIA1_PB                     ; clear its flag
    lda #PIA_HIGH                   ; NDAC, DAV and EOI high
    sta PIA2_CRA
    sta PIA2_CRB
    sta PIA1_CRA
    stx PIA2_PB                     ; the bus's data lines let go
    lda #$0C                        ; the uppercase and graphics characters
    sta VIA_PCR
    sta BLNCT                       ; the cursor does not blink
    sta BLNSW

;; Clears the screen to spaces, turns reverse off, makes every row a logical line of its own in <LDTB1>, and homes the
;; cursor (<NXTD>).
;;
;; Uses: A, X, Y
CLSR:
    ldy #$00
    sty RVS                         ; reverse off
    sty PNT
    lda #>(SCREEN+$400)             ; $8400, the page past video RAM
    sta PNT+1

CLSR_1:
    lda #' '                        ; a page of spaces, from the top page down
    dec PNT+1

CLSR_2:
    sta (PNT),y
    dey
    bne CLSR_2
    lda PNT+1
    cmp #>SCREEN
    bne CLSR_1
    lda #>SCREEN                    ; every row starts a line, in page $80
    ldx #ROWS

CLSR_3:
    sta LDTB1-1,x
    dex
    bne CLSR_3
    ldy #ROWS-7                     ; rows 7-24 are in page $81 or later
    jsr LDTBINC
    ldy #ROWS-13                    ; rows 13-24 in $82 or later
    jsr LDTBINC
    ldy #ROWS-20                    ; rows 20-24 in $83
    jsr LDTBINC

;; Puts the cursor in the top left corner.
;;
;; Out: X = 0, the row from <STUPT>, Y = 0
;; Uses: A
NXTD:
    ldy #$00
    sty PNTR
    sty TBLX
    jsr STUPT
    rts

;; Adds one to the page in the last entries of <LDTB1>, for the rows that start in a later page of video RAM.
;;
;; In: Y = the number of rows
;; Out: X = the row before them, Y = 0
LDTBINC:
    ldx #ROWS-1

LDTBINC_1:
    inc LDTB1,x
    dex
    dey
    bne LDTBINC_1
    rts

;; Takes the oldest key out of the keyboard buffer, moving the others down, and enables interrupts.
;;
;; The caller disables interrupts and checks that <NDX> is not zero.
;;
;; Out: A = the key
;; Uses: X, Y
LP2:
    ldy KEYD
    ldx #$00

LP2_1:
    lda KEYD+1,x
    sta KEYD,x
    inx
    cpx NDX
    bne LP2_1
    dec NDX
    tya
    cli
    rts

;; Prints the key in A, then waits for more (<LOOP3>).
;;
;; In: A = the key
LOOP4:
    jsr PRT

;; Lets the user type: blinks the cursor while the keyboard buffer is empty, and prints each key, until RETURN; then
;; reads the line the cursor is on, from the column input started at (<LXSP>) when that is on this row, and returns
;; its first character (<LOOP5>).
;;
;; SHIFT and STOP, RUN, puts "LOAD", RETURN, "RUN", RETURN in the keyboard buffer. The line ends at its last character
;; that is not a space (<INDX>).
;;
;; Out: A = the first character, or RETURN for an empty line
LOOP3:
    lda NDX
    sta BLNSW
    beq LOOP3
    sei
    lda BLNON
    beq LOOP3_1
    lda GDBLN
    ldy #$00
    sty BLNON
    jsr DSPP

LOOP3_1:
    jsr LP2
    cmp #CHR_RUN                    ; SHIFT and STOP
    bne LOOP3_3
    sei
    ldx #9                          ; type LOAD and RUN
    stx NDX

LOOP3_2:
    lda RUNTB-1,x
    sta KEYD-1,x
    dex
    bne LOOP3_2
    beq LOOP3

LOOP3_3:
    cmp #CHR_RETURN                 ; any key but RETURN is printed
    bne LOOP4
    ldy LNMX                        ; read the line from its last column
    sty CRSW

LOOP3_4:
    lda (PNT),y                     ; back over the spaces at its end
    cmp #' '
    bne LOOP3_5
    dey
    bne LOOP3_4

LOOP3_5:
    iny
    sty INDX
    ldy #$00
    sty PNTR
    sty QTSW
    lda LXSP                        ; did input start on this row?
    bmi LOOP5_1
    cmp TBLX
    bne LOOP5_1
    lda LXSP+1                      ; yes: start where it did
    sta PNTR
    cmp INDX
    bcc LOOP5_1
    jmp LOOP5_5                     ; nothing typed after the prompt

;; Reads a character from the screen: the next one of the line <CRSW> says is being read, or when none is, the first
;; of a line the user types (<LOOP3>).
;;
;; Each screen code becomes the PET's ASCII again, keeping reversed characters inside quotes and turning screen code
;; $5E back into pi. After the line's last character it returns RETURN, printing one too when the output device is not
;; the screen.
;;
;; Out: A = the character
;; Keeps: X, Y
LOOP5:
    tya                             ; the entry
    pha
    txa
    pha
    lda CRSW                        ; a line under way?
    beq LOOP3

LOOP5_1:
    ldy PNTR
    lda (PNT),y
    sta DATAX                       ; screen code: bit 7 reverse, bit 6 the shifted set
    and #$3F
    asl DATAX
    bit DATAX
    bpl LOOP5_2
    ora #$80

LOOP5_2:
    bcc LOOP5_3                     ; reversed: keep it so in quotes
    ldx QTSW
    bne LOOP5_4

LOOP5_3:
    bvs LOOP5_4
    ora #$40                        ; unshifted letters and the like, $40-$5F

LOOP5_4:
    inc PNTR
    jsr QTSWC
    cpy INDX                        ; the line's end?
    bne LOOP5_7

LOOP5_5:
    lda #$00
    sta CRSW
    lda #CHR_RETURN
    ldx DFLTO                       ; echo RETURN unless printing goes to the screen anyway
    cpx #DEV_SCREEN
    beq LOOP5_6
    jsr PRT

LOOP5_6:
    lda #CHR_RETURN

LOOP5_7:
    sta DATAX
    pla
    tax
    pla
    tay
    lda DATAX
    cmp #'^' | $80                  ; pi, screen code $5E
    bne LOOP5_8
    lda #CHR_PI

LOOP5_8:
    rts

;; Toggles quote mode when the character is a quotation mark.
;;
;; In: A = the character
;; Keeps: A, X, Y
QTSWC:
    cmp #'"'
    bne QTSWC_1
    lda QTSW
    eor #$01
    sta QTSW
    lda #'"'

QTSWC_1:
    rts

;; Prints a character from the shifted half of the PET's ASCII, $A0-$FE, with bit 7 cleared: setting bit 6 makes it its
;; screen code.
;;
;; Puts the screen code at the cursor, reversed while reverse is on, and moves the cursor right, joining the next row
;; onto the line, or starting a new line or scrolling, as the line fills. Inserts pending count down. It ends through
;; <LOOP2>, so the caller has pushed A, X and Y as <PRT> does.
;;
;; In: A = the character, bit 7 cleared
;; Entry: NXT3 = A is the screen code, NC3 = prints it reversed whatever reverse is
NXT33:
    ora #$40

NXT3:
    ldx RVS
    beq NXT33_1

NC3:
    ora #$80

NXT33_1:
    ldx INSRT                       ; an insert pending?
    beq NXT33_2
    dec INSRT

NXT33_2:
    jsr DSPP                        ; put it on the screen
    inc PNTR
    ldy LNMX
    cpy PNTR                        ; still inside the line?
    bcs LOOP2
    ldx TBLX
    cpy #2*COLUMNS-1                ; the second row's end: start a new line
    bne NXT33_3
    jsr JSTSX
    jsr NXLN
    lda #$00
    sta PNTR
    jmp LOOP2

NXT33_3:
    cpx #ROWS-1                     ; the bottom row: scroll first
    bne JTS2
    jsr SCRL

;; The end of <PRT>: restores Y and X from the stack, leaves quote mode while inserts are pending, pulls the
;; character back into A, and enables interrupts.
;;
;; Out: A = the character printed
LOOP2:
    pla
    tay
    lda INSRT                       ; inserts pending end quote mode
    beq LOOP2_1
    lsr QTSW

LOOP2_1:
    pla
    tax
    pla
    cli
    rts

;; Makes the row two below the given one start a logical line, unless it is past the bottom.
;;
;; In: X = the row
;; Keeps: X, Y
JSTSX:
    cpx #ROWS-2
    bcs JSTSX_1
    lda LDTB1+2,x
    ora #$80
    sta LDTB1+2,x

JSTSX_1:
    rts

;; Joins the row below onto the cursor's line (<JSTS2>), then ends <PRT>.
JTS2:
    jsr JSTS2                       ; join the next row onto the line
    jmp LOOP2

;; Scrolls the screen up a row and moves the cursor up with it, then joins the row below onto the cursor's line.
;;
;; Entry: JSTS2 = joins the row after the cursor's onto its line, without scrolling
;; Uses: A, X, Y
SCRL:
    jsr SCROL
    dec TBLX
    ldx TBLX

JSTS2:
    asl LDTB1+1,x                   ; clear the next row's start bit
    lsr LDTB1+1,x
    jsr JSTSX
    lda PNTR                        ; STUPT moves PNTR back into one row
    pha
    jsr STUPT
    pla
    sta PNTR
    rts

;; Moves the cursor to the end of the logical line above, for a cursor left or DEL in the line's first column.
;;
;; On the top row it leaves the cursor in column 0 and ends <PRT> (<LOOP2>), dropping its caller.
;;
;; Out: Y = the new column
;; Uses: A, X
BKLN:
    ldy #COLUMNS-1
    ldx TBLX
    bne BKLN_1
    stx PNTR
    pla
    pla
    bne LOOP2

BKLN_1:
    lda LDTB1-1,x                   ; the row above starts a line: its end is column 39
    bmi BKLN_2
    dex
    lda LDTB1-1,x
    ldy #2*COLUMNS-1                ; otherwise the line above is two rows

BKLN_2:
    dex
    stx TBLX
    sta PNT+1
    lda LDTB2,x
    sta PNT
    sty PNTR
    sty LNMX
    rts

;; Prints a character on the screen at the cursor, acting on the cursor and editing keys.
;;
;; RETURN starts a new line and ends reverse, quote and insert modes; DEL, INST, the cursor keys, HOME, CLR and
;; reverse on and off do their work, except in quote mode or while inserts are pending, when they print as reversed
;; characters. Two keys differ: DEL deletes in quote mode too, printing reversed only while inserts are pending, and
;; INST inserts while inserts are pending, printing reversed only in quote mode. A quotation mark toggles quote mode.
;; The kernal's <Kernal1:BSOUT> calls it for the screen.
;;
;; In: A = the character
;; Keeps: A, X, Y
PRT:
    pha
    sta DATAX
    txa
    pha
    tya
    pha
    lda #$00                        ; output stops a screen read
    sta CRSW
    ldy PNTR
    lda DATAX                       ; shifted characters
    bpl PRT_1
    jmp NXTX

PRT_1:
    cmp #CHR_RETURN
    bne PRT_2
    jmp NXT1

PRT_2:
    cmp #' '                        ; control characters
    bcc PRT_3
    and #$3F                        ; a printable character's screen code
    jsr QTSWC
    jmp NXT3

PRT_3:
    ldx INSRT                       ; with inserts pending, a control character prints
    beq PRT_4
    jmp NC3

PRT_4:
    cmp #CHR_DEL                    ; DEL
    bne PRT_7
    dey
    sty PNTR
    bpl PRT_5
    jsr BKLN
    jmp PRT_6

PRT_5:
    iny                             ; move the rest of the line left
    lda (PNT),y
    dey
    sta (PNT),y
    iny
    cpy LNMX
    bne PRT_5

PRT_6:
    lda #' '                        ; and blank its end
    sta (PNT),y
    bne PRT_14

PRT_7:
    ldx QTSW                        ; in quotes, a control character prints
    beq PRT_8
    jmp NC3

PRT_8:
    cmp #CHR_RVS                    ; reverse on
    bne PRT_9
    sta RVS

PRT_9:
    cmp #CHR_HOME                   ; home
    bne PRT_10
    jsr NXTD

PRT_10:
    cmp #CHR_RIGHT                  ; cursor right
    bne PRT_13
    iny
    sty PNTR
    dey
    cpy LNMX
    bcc PRT_12
    jsr NXLN
    ldy #$00

PRT_11:
    sty PNTR

PRT_12:
    jmp LOOP2

PRT_13:
    cmp #CHR_DOWN                   ; cursor down
    bne PRT_14
    clc
    tya
    adc #COLUMNS
    tay
    cmp LNMX
    bcc PRT_11
    beq PRT_11
    jsr NXLN

PRT_14:
    jmp LOOP2

; Unused: a cursor-down step that nothing reaches, left between PRINT's parts.
    inx
    sta TBLX
    tya
    sbc #$28
    sta PNTR
    inc TBLX
    lda LDTB2
    sta PNT
    lda LDTB1
    sta PNT+1
    bne PRT_14

;; Prints a character from $80-$FF, the shifted keys: their graphics, and shifted RETURN, INST, cursor up and left, CLR
;; and reverse off. The rest of <PRT>.
;;
;; In: A = the character, Y = <PNTR>
NXTX:
    and #$7F
    cmp #$7F                        ; pi
    bne NXTX_1
    lda #'^'

NXTX_1:
    cmp #' '                        ; graphics
    bcc NXTX_2
    jmp NXT33

NXTX_2:
    cmp #CHR_RETURN                 ; shifted RETURN
    bne NXTX_3
    jmp NXT1

NXTX_3:
    ldx QTSW
    bne NXTX_8
    cmp #CHR_DEL                    ; INST
    bne NXTX_7
    ldy LNMX                        ; room at the line's end?
    lda (PNT),y
    cmp #' '
    bne NXTX_4
    cpy PNTR
    bne NXTX_5

NXTX_4:
    cpy #2*COLUMNS-1                ; a full second row: no room
    beq PRT_14
    jsr NEWLN                       ; a full first row: open a row for the second

NXTX_5:
    ldy LNMX

NXTX_6:
    dey                             ; move the line right of the cursor right
    lda (PNT),y
    iny
    sta (PNT),y
    dey
    cpy PNTR
    bne NXTX_6
    lda #' '                        ; and put a space at the cursor
    sta (PNT),y
    inc INSRT
    bne NXTX_15

NXTX_7:
    ldx INSRT
    beq NXTX_9

NXTX_8:
    ora #$40
    jmp NC3

NXTX_9:
    cmp #CHR_DOWN                   ; cursor up
    bne NXTX_12
    lda PNTR
    cmp #COLUMNS
    bcc NXTX_10
    sbc #COLUMNS
    sta PNTR
    bcs NXTX_15

NXTX_10:
    ldx TBLX
    beq NXTX_15
    lda LDTB1-1,x                   ; the row above starts a line
    bpl NXTX_11
    dec TBLX
    jsr STUPT
    bcc NXTX_15

NXTX_11:
    dex                             ; the line above is two rows: its second
    dex
    stx TBLX
    jsr STUPT
    lda PNTR
    clc
    adc #COLUMNS
    sta PNTR
    bne NXTX_15

NXTX_12:
    cmp #CHR_RVS                    ; reverse off
    bne NXTX_13
    lda #$00
    sta RVS

NXTX_13:
    cmp #CHR_RIGHT                  ; cursor left
    bne NXTX_14
    dey
    sty PNTR
    bpl NXTX_15
    jsr BKLN
    jmp LOOP2

NXTX_14:
    cmp #CHR_HOME                   ; clear the screen
    bne NXTX_15
    jsr CLSR

NXTX_15:
    jmp LOOP2

;; Moves the cursor down to the next logical line, keeping its column, scrolling when it is on the last one; RETURN
;; (<NXT1>) clears the column first.
;;
;; The SEC before its shift of <LXSP> does nothing: the shift always clears bit 7.
;;
;; Uses: A, X, Y
NXLN:
    sec
    lsr LXSP
    ldx TBLX

NXLN_1:
    inx
    cpx #ROWS
    bne NXLN_2
    jsr SCROL

NXLN_2:
    lda LDTB1,x                     ; skip the rows that continue a line
    bpl NXLN_1
    stx TBLX
    jmp STUPT

;; Ends the line for RETURN: leaves insert, reverse and quote modes and moves the cursor to the start of the next
;; line, then ends <PRT>.
NXT1:
    lda #$00
    sta INSRT
    sta RVS
    sta QTSW
    sta PNTR
    jsr NXLN
    jmp LOOP2

;; Scrolls the screen up a logical line, one or two rows, with the screen blanked while the text moves, and moves the
;; links in <LDTB1> up with it.
;;
;; While RVS is held, the key the last scan's row reads as $FE, it waits about half a second after each scroll, and
;; empties the keyboard buffer.
;;
;; Out: X = <TBLX>, moved up with the text
;; Uses: A, Y, SAL
SCROL:
    sei
    ldy #$00
    sty PNT
    lda #>SCREEN
    sta SAL+1
    sta PNT+1
    lda #COLUMNS                    ; copy from the next row on
    bit LDTB1+1                     ; which starts a line
    bmi SCROL_1
    lda #2*COLUMNS                  ; or the one after, for a two-row line

SCROL_1:
    sta SAL
    lda #PIA_LOW                    ; blank the screen
    sta PIA1_CRA

SCROL_2:
    lda (SAL),y                     ; move the text up
    sta (PNT),y
    iny
    bne SCROL_2
    inc SAL+1
    inc PNT+1
    lda #>(SCREEN+$400)
    cmp SAL+1
    bne SCROL_2
    lda #<(SCREEN+SCREEN_SIZE)      ; then blank from the screen's end back
    sta PNT
    dec PNT+1
    lda #' '

SCROL_3:
    dec PNT
    dec SAL
    sta (PNT),y
    bne SCROL_3
    ldx #ROWS
    stx TBLX

SCROL_4:
    ldx #$00                        ; move the links up a row
    dec TBLX

SCROL_5:
    lda LDTB1,x
    and #$7F
    ldy LDTB1+1,x
    bpl SCROL_6
    ora #$80

SCROL_6:
    sta LDTB1,x
    inx
    cpx #ROWS
    bne SCROL_5
    lda #>(SCREEN+(ROWS-1)*COLUMNS) ; the bottom row starts a line
    sta LDTB1+ROWS-1
    lda LDTB1                       ; again while the top row continues a line
    bpl SCROL_4
    lda #PIA_HIGH                   ; show the screen
    sta PIA1_CRA
    cli
    lda #$FE                        ; RVS held?
    cmp PIA1_PB
    bne SCROL_9
    ldy #8                          ; eight of timer 1's runs

SCROL_7:
    sta VIA_T1CH

SCROL_8:
    bit VIA_IFR
    bvc SCROL_8
    dey
    bne SCROL_7
    sty NDX

SCROL_9:
    ldx TBLX
    rts

;; Sets <PNT> and <LNMX> for the cursor's row, and brings <PNTR> back inside one row's width when it is past it.
;;
;; Out: X = <TBLX>
;; Uses: A
STUPT:
    ldx TBLX
    lda LDTB1,x
    ora #$80
    sta PNT+1
    lda LDTB2,x
    sta PNT
    lda #COLUMNS-1                  ; a line of one row
    sta LNMX
    cpx #ROWS-1
    beq STUPT_1
    lda LDTB1+1,x                   ; or two, when the next row continues it
    bmi STUPT_1
    lda #2*COLUMNS-1
    sta LNMX

STUPT_1:
    lda PNTR
    cmp #COLUMNS
    bcc STUPT_2
    sbc #COLUMNS
    sta PNTR

STUPT_2:
    rts

;; Opens a blank row below the cursor's line for an insert that runs off its end: moves the rows below down one,
;; links the new row onto the line, and blanks it, with the screen blanked while the text moves. Near the bottom it
;; scrolls instead (<SCRL>).
;;
;; Uses: A, X, Y, SAL
NEWLN:
    ldx TBLX
    inx
    sei
    lda #PIA_LOW                    ; blank the screen
    sta PIA1_CRA
    cpx #ROWS-2                     ; near the bottom, scroll
    beq NEWLN_5
    bcc NEWLN_1
    jmp SCRL

NEWLN_1:
    ldx #ROWS-2                     ; from the second row from the bottom up

NEWLN_2:
    lda LDTB1+1,x                   ; the row below takes this row's link
    ora #$80
    sta SAL+1
    ldy LDTB1,x
    bmi NEWLN_3
    and #$7F

NEWLN_3:
    sta LDTB1+1,x
    tya
    ora #$80
    sta PNT+1
    ldy #COLUMNS-1
    lda LDTB2+1,x
    sta SAL
    lda LDTB2,x
    sta PNT

NEWLN_4:
    lda (PNT),y                     ; copy the row down
    sta (SAL),y
    dey
    bpl NEWLN_4
    dex
    cpx TBLX
    bne NEWLN_2
    inx

NEWLN_5:
    lda LDTB1,x                     ; the new row continues the line
    ora #$80
    sta PNT+1
    and #$7F
    sta LDTB1,x
    lda LDTB2,x
    sta PNT
    ldy #COLUMNS-1                  ; blank it
    lda #' '

NEWLN_6:
    sta (PNT),y
    dey
    bpl NEWLN_6
    lda #PIA_HIGH                   ; show the screen
    sta PIA1_CRA
    cli
    jmp STUPT

;; The IRQ entry, where the 6502's IRQ vector points: saves A, X and Y on the stack and goes through <CBINV> for a BRK
;; instruction or <CINV> for an interrupt.
PULS:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda STACK+4,x                   ; the stacked status: B for a BRK
    and #$10
    beq PULS_1
    jmp (CBINV)

PULS_1:
    jmp (CINV)

;; Ends an interrupt: restores Y, X and A from the stack and returns from it.
PREND:
    pla
    tay
    pla
    tax
    pla
    rti

; Unused: an RTS that nothing reaches.
    rts

;; The 60 Hz interrupt, from the retrace: counts the jiffy clock (<Kernal1:JUDTIM>), blinks the cursor, runs the cassette
;; motors for the PLAY keys, and scans the keyboard, putting a new key in the keyboard buffer.
;;
;; The motor of a cassette whose PLAY key is down runs, and stops when the key is let go, unless the kernal has the
;; motor (<CAS1>, <CAS2>). Of several keys down, the last the scan finds counts, and only when it changes: holding a key
;; gives it once. When the buffer is full, a new key starts it again from the first place.
KEY:
    jsr JUDTIM                      ; the jiffy clock
    lda BLNSW                       ; blink the cursor?
    bne KEY_4
    dec BLNCT
    bne KEY_4
    lda #BLINK_JIFFIES              ; time to blink
    sta BLNCT
    ldy PNTR
    lsr BLNON                       ; take the character, and note whether it was shown
    lda (PNT),y
    bcs KEY_1
    inc BLNON
    sta GDBLN                       ; showing it: keep the character

KEY_1:
    asl a                           ; reverse bit 7
    bcs KEY_2
    sec
    bcs KEY_3

KEY_2:
    clc

KEY_3:
    ror a
    sta (PNT),y

KEY_4:
    ldx #$FF                        ; no key yet
    stx SFDX
    inx
    stx SHFLAG                      ; no SHIFT yet
    ldx #KEY_COUNT                  ; count the keys down from 80
    lda PIA1_PA                     ; start at row 0
    and #$F0
    sta PIA1_PA
    ldy #$00
    lda PIA1_PA                     ; the cassettes' PLAY keys
    asl a
    asl a
    asl a
    bpl KEY_5
    sty CAS1                        ; cassette 1 up: let the motor go, and stop it
    lda #PIA_HIGH_IRQ
    bne KEY_6

KEY_5:
    lda CAS1                        ; down: run it, unless the kernal has it
    bne KEY_7
    lda #PIA_LOW_IRQ

KEY_6:
    sta PIA1_CRB

KEY_7:
    bcc KEY_8                       ; cassette 2
    sty CAS2                        ; up: let the motor go, and stop it
    lda VIA_ORB
    ora #VIAB_MOTOR2
    bne KEY_9

KEY_8:
    lda CAS2                        ; down: run it, unless the kernal has it
    bne KEY_10
    lda VIA_ORB
    and #$FF-VIAB_MOTOR2

KEY_9:
    sta VIA_ORB

KEY_10:
    ldy #8                          ; the row's eight keys
    lda PIA1_PB                     ; read the row until it holds still
    cmp PIA1_PB
    bne KEY_10

KEY_11:
    lsr a                           ; a key down reads low
    bcs KEY_12
    pha
    jsr KEYCHK
    pla

KEY_12:
    dex
    beq KEY_13
    dey
    bne KEY_11
    inc PIA1_PA                     ; the next row
    bne KEY_10

KEY_13:
    lda SFDX                        ; the key found
    cmp LSTX                        ; a new one?
    beq KEY_16
    sta LSTX
    tax
    bmi KEY_16                      ; none
    lda CHAR-1,x
    lsr SHFLAG                      ; shifted characters have bit 7 set
    bcc KEY_14
    ora #$80

KEY_14:
    ldx NDX                         ; into the buffer
    sta KEYD,x
    inx
    cpx #KEYBUF_SIZE                ; full: start it again
    bne KEY_15
    ldx #$00

KEY_15:
    stx NDX

KEY_16:
    jmp PREND

;; Notes a key the scan found down: SHIFT sets <SHFLAG>, a key that does nothing is skipped, the < key is skipped while
;; PIA 1's CA1 flag is set, and any other key's number goes into <SFDX>.
;;
;; In: X = the key's number, 1-80
;; Keeps: X, Y
KEYCHK:
    lda CHAR-1,x
    bne KEYCHK_1
    lda #$01                        ; SHIFT
    sta SHFLAG
    bne KEYCHK_END

KEYCHK_1:
    cmp #$FF                        ; keys that give nothing
    beq KEYCHK_END
    cmp #'<'                        ; the < key, unless PIA 1's CA1 flag is set
    bne KEYCHK_2
    bit PIA1_CRA
    bmi KEYCHK_END

KEYCHK_2:
    stx SFDX

KEYCHK_END:
    rts

;; The keyboard: the character each key gives, by its number less one. The scan counts the keys down from 80 at row 0's
;; bit 0, so the table starts at row 9's bit 7. A zero is SHIFT, and $FF a key that gives nothing. <KEYCHK> and <KEY>
;; index it from the RTS just before it, since key numbers start at 1.
CHAR:
    .byte '=', '.', $FF, $03, '<', ' ', '[', $12                  ; row 9, bits 7-0
    .byte '-', '0', $00, '>', $FF, ']', '@', $00                  ; row 8, bits 7-0
    .byte '+', '2', $FF, '?', ',', 'N', 'V', 'X'                  ; row 7, bits 7-0
    .byte '3', '1', $0D, ';', 'M', 'B', 'C', 'Z'                  ; row 6, bits 7-0
    .byte '*', '5', $FF, ':', 'K', 'H', 'F', 'S'                  ; row 5, bits 7-0
    .byte '6', '4', $FF, 'L', 'J', 'G', 'D', 'A'                  ; row 4, bits 7-0
    .byte '/', '8', $FF, 'P', 'I', 'Y', 'R', 'W'                  ; row 3, bits 7-0
    .byte '9', '7', '^', 'O', 'U', 'T', 'E', 'Q'                  ; row 2, bits 7-0
    .byte $14, $11, $FF, ')', $5C, $27, '$', '"'                  ; row 1, bits 7-0
    .byte $1D, $13, '_', '(', '&', '%', '#', '!'                  ; row 0, bits 7-0

;; Stores a screen code at the cursor, waiting for vertical blanking first.
;;
;; In: A = the screen code
;; Out: Y = <PNTR>
;; Keeps: A, X
DSPP:
    tay

DSPP_1:
    lda VIA_ORB                     ; wait for vertical blanking
    and #VIAB_RETRACE
    bne DSPP_1
    tya
    ldy PNTR
    sta (PNT),y
    rts

; Unused: a PLA and RTS that nothing reaches.
    pla
    rts

;; The low byte of each row's address in video RAM, from the top. <LDTB1> holds the high bytes.
LDTB2:
    .byte <(SCREEN+0*COLUMNS)                       ; row 0
    .byte <(SCREEN+1*COLUMNS)                       ; row 1
    .byte <(SCREEN+2*COLUMNS)                       ; row 2
    .byte <(SCREEN+3*COLUMNS)                       ; row 3
    .byte <(SCREEN+4*COLUMNS)                       ; row 4
    .byte <(SCREEN+5*COLUMNS)                       ; row 5
    .byte <(SCREEN+6*COLUMNS)                       ; row 6
    .byte <(SCREEN+7*COLUMNS)                       ; row 7
    .byte <(SCREEN+8*COLUMNS)                       ; row 8
    .byte <(SCREEN+9*COLUMNS)                       ; row 9
    .byte <(SCREEN+10*COLUMNS)                      ; row 10
    .byte <(SCREEN+11*COLUMNS)                      ; row 11
    .byte <(SCREEN+12*COLUMNS)                      ; row 12
    .byte <(SCREEN+13*COLUMNS)                      ; row 13
    .byte <(SCREEN+14*COLUMNS)                      ; row 14
    .byte <(SCREEN+15*COLUMNS)                      ; row 15
    .byte <(SCREEN+16*COLUMNS)                      ; row 16
    .byte <(SCREEN+17*COLUMNS)                      ; row 17
    .byte <(SCREEN+18*COLUMNS)                      ; row 18
    .byte <(SCREEN+19*COLUMNS)                      ; row 19
    .byte <(SCREEN+20*COLUMNS)                      ; row 20
    .byte <(SCREEN+21*COLUMNS)                      ; row 21
    .byte <(SCREEN+22*COLUMNS)                      ; row 22
    .byte <(SCREEN+23*COLUMNS)                      ; row 23
    .byte <(SCREEN+24*COLUMNS)                      ; row 24

;; What SHIFT and STOP type: LOAD and RUN, each with RETURN, put in the keyboard buffer.
RUNTB:
    .byte "LOAD", CHR_RETURN, "RUN", CHR_RETURN

;; Prints one of the kernal's messages on the screen.
;;
;; In: Y = the message's offset in <Kernal1:MSG1>
;; Out: Y = the offset just past it
;; Uses: A
MSG:
    lda MSG1,y                      ; messages end with bit 7 set
    php
    and #$7F
    jsr PRT
    iny
    plp
    bpl MSG
    rts

; Unused bytes, around six that are BASIC's ARYINC, which BASIC's sources build.
    .res 7, 0
    .res 6                          ; $E7F3-$E7F8, BASIC's ARYINC
    .res 7, 0
