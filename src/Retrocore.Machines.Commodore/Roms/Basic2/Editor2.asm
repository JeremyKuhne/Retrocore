;; COMMODORE PET BASIC 2 SCREEN EDITOR ($E1DE-$E7FF)
;;
;; The screen editor is the PET's screen and keyboard in the 2001-N and the upgrade ROMs for the 2001: it prints
;; characters and cursor controls on the 40-by-25 screen, scans the keyboard sixty times a second from the
;; retrace interrupt, and reads lines typed on the screen, so that any line can be edited and entered again.
;;
;; It is laid out in this order:
;;
;; - Reset of the I/O chips and the screen (<CINT>, <CLSR>, <NXTD>, <STUPT>).
;; - Input (<LOOP3>, <LOOP5>): the keys typed are echoed until RETURN, then the logical line the cursor
;;   is on is read back from video RAM, a character at a time, as the kernal's BASIN asks.
;; - Output (<PRT>): printable characters, the cursor keys, HOME and CLR, RVS, DEL and INST, with quote
;;   mode (<QTSW>) and inserts (<INSRT>) printing cursor keys as reversed characters instead.
;; - Scrolling (<SCROL>) and opening a line (<NEWLN>).
;; - The interrupt entry (<PULS>) and the retrace interrupt (<KEY>): the jiffy clock, the cursor's blink,
;;   the cassette motors and the keyboard scan.
;; - The keyboard's table (<CHAR>), the rows' addresses (<LDTB2>) and shifted RUN's text (<RUNTB>).
;; - The monitor's hexadecimal input and output, which the kernal's monitor calls.
;;
;; A logical line is one or two rows of 40 columns. The link table <LDTB1> holds each row's page of video RAM
;; with bit 7 clear for a row that continues the row above, so a line grows to 80 columns when printing runs off
;; its first row, and scrolling moves the top line whole.
;;
;; The chip holds more than the editor: its first $1DE bytes, $E000-$E1DD, are the end of BASIC (the math
;; package's end, INIT and the sign-on message), which BASIC's source builds; this source starts at the editor's
;; first byte. The two together assemble byte-identically to the editor ROM 901447-24.
;;
;; The routines take Commodore's names from its BASIC 4 kernal listing of 1979 where BASIC 4 has the same code,
;; and otherwise are named after what they do.
;;
;; Maintained by hand.

.cpu Mos6502

.include "../PetEquates.asm"
.include "Equates.asm"
.include "BasicEntries.asm"
.include "KernalEntries.asm"

KEY_NONE = $FF              ;; In <CHAR>, a place in the matrix with no key.
KEY_SHIFT = $00             ;; In <CHAR>, a SHIFT key.
KEY_COUNT = 80              ;; The places in the keyboard's matrix: 10 rows of 8.
PI_SCREEN = $DE             ;; The character pi as <LOOP5> converts it from video RAM.
PI = $FF                    ;; The character pi as the PET's character code.
BLINK_JIFFIES = 20          ;; The jiffies between the cursor's blinks.
STACK = $0100               ;; The 6502's stack page.
STATUS_BREAK = $10          ;; The break bit of the status register the interrupt pushed: set for BRK.

.org $E1DE

;; Sets up the I/O chips, the editor's page zero and the screen, at reset.
;;
;; It clears page zero from <CQTIMR> to <CAS2>, points <CINV> at <KEY>, makes the screen the output device,
;; sets each chip's port directions and lines (the keyboard row select and the bus outputs, the motors off, the
;; retrace interrupt on, the uppercase and graphics characters), then clears the screen.
;; Uses: A, X, Y
CINT:
    lda #VIA_IRQ_ALL
    sta VIA_IER
    ldx #CAS2 - CQTIMR
    lda #$00
CINT_1:
    sta CQTIMR,x
    dex
    bpl CINT_1
    lda #<KEY
    sta CINV
    lda #>KEY
    sta CINV+1
    lda #DEV_SCREEN
    sta DFLTO
    lda #$0F
    sta PIA1_PA                             ; the direction register: PA0-PA3 out
    asl a
    sta VIA_ORB                             ; NRFD, ATN, the write line and motor 2 high...
    sta VIA_DDRB                            ; ...and outputs
    stx PIA2_PB                             ; the direction register: all out
    stx VIA_T1CH                            ; start timer 1
    lda #PIA_HIGH_IRQ
    sta PIA1_CRB
    bit PIA1_PB                             ; clear the retrace flag
    lda #PIA_HIGH
    sta PIA2_CRA
    sta PIA2_CRB
    sta PIA1_CRA                            ; EOI high, the screen on
    stx PIA2_PB                             ; release the data lines
    lda #$0C
    sta VIA_PCR                             ; CA2 low: uppercase and graphics
    sta BLNCT
    sta BLNSW                               ; nonzero: no blink yet

;; Clears the screen: links every row as a line of its own, fills video RAM with spaces and homes the cursor.
;; Uses: A, X, Y
CLSR:
    ldy #>SCREEN + 3
    ldx #SCREEN_ROWS - 1
CLSR_1:
    sty LDTB1,x
    cpx #20
    beq CLSR_2
    cpx #13
    beq CLSR_2
    cpx #7
    bne CLSR_3
CLSR_2:
    dey                                     ; the rows before go in the page below
CLSR_3:
    dex
    bpl CLSR_1
    sty PNT+1
    inx
    stx RVS
    stx PNT
    lda #' '
CLSR_4:
    sta SCREEN,x
    sta SCREEN + $100,x
    sta SCREEN + $200,x
    sta SCREEN + $300,x
    dex
    bne CLSR_4

;; Moves the cursor to the top left of the screen.
;; Uses: A, X, Y
NXTD:
    ldy #$00
    sty PNTR
    sty TBLX

;; Points <PNT> at the cursor's line and sets <LNMX> for its length, 40 or 80 columns.
;;
;; A column past the first row's end is moved back by 40, whatever the line's length; a caller that keeps the column
;; in a second row saves <PNTR> around the call, as <JSTS2> does.
;; In: TBLX = the line's first row
;; Uses: A, X
STUPT:
    ldx TBLX
    lda LDTB1,x
    ora #$80
    sta PNT+1
    lda LDTB2,x
    sta PNT
    lda #SCREEN_COLUMNS - 1
    sta LNMX
    cpx #SCREEN_ROWS - 1
    beq STUPT_1
    lda LDTB1+1,x
    bmi STUPT_1
    lda #2 * SCREEN_COLUMNS - 1
    sta LNMX
STUPT_1:
    lda PNTR
    cmp #SCREEN_COLUMNS
    bcc STUPT_2
    sbc #SCREEN_COLUMNS
    sta PNTR
STUPT_2:
    rts

;; Takes the first key from the keyboard buffer, moving the others up.
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

;; Echoes a key typed and waits for the next, while a line is typed.
;;
;; The cursor blinks while the buffer is empty. Shifted RUN types <RUNTB>; RETURN ends the line: the logical
;; line the cursor is on is then read from its first column, or from where the INPUT began when that was on this
;; line, up to its last nonblank character.
LOOP4:
    jsr PRT

;; Waits for a key while a line is typed, then as <LOOP4>.
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
    cmp #KEY_SHIFT_RUN                      ; shifted RUN?
    bne LOOP3_3
    sei
    ldx #RUN_TEXT_END - RUNTB
    stx NDX
LOOP3_2:
    lda RUNTB - 1,x
    sta KEYD - 1,x
    dex
    bne LOOP3_2
    beq LOOP3
LOOP3_3:
    cmp #KEY_RETURN
    bne LOOP4
    ldy LNMX
    sty CRSW
LOOP3_4:
    lda (PNT),y
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
    lda INPUT_ROW                           ; did INPUT begin on this line?
    bmi LOOP5_1
    cmp TBLX
    bne LOOP5_1
    lda INPUT_COLUMN
    sta PNTR
    cmp INDX
    bcc LOOP5_1
    bcs LOOP5_5

;; Reads a character from the screen for the kernal's BASIN.
;;
;; Reading from the keyboard, it waits for a line (<LOOP3>) first. It reads the cursor's logical line from
;; video RAM, turning each screen code back into the character code that prints it (reversed characters inside
;; quotes giving the cursor keys), and ends with a carriage return.
;; Out: A = the character
;; Keeps: X, Y
LOOP5:
    tya
    pha
    txa
    pha
    lda CRSW
    beq LOOP3
LOOP5_1:
    ldy PNTR
    lda (PNT),y
    sta CHAR_TEMP                           ; turn the screen code into a character
    and #$3F
    asl CHAR_TEMP
    bit CHAR_TEMP
    bpl LOOP5_2
    ora #$80
LOOP5_2:
    bcc LOOP5_3
    ldx QTSW
    bne LOOP5_4
LOOP5_3:
    bvs LOOP5_4
    ora #$40
LOOP5_4:
    inc PNTR
    jsr QTSWC
    cpy INDX
    bne LOOP5_7
LOOP5_5:
    lda #$00
    sta CRSW
    lda #KEY_RETURN
    ldx DFLTO
    cpx #DEV_SCREEN
    beq LOOP5_6
    jsr PRT
LOOP5_6:
    lda #KEY_RETURN
LOOP5_7:
    sta CHAR_TEMP
    pla
    tax
    pla
    tay
    lda CHAR_TEMP
    cmp #PI_SCREEN                          ; pi
    bne LOOP5_8
    lda #PI
LOOP5_8:
    rts

;; Turns quote mode on or off for a quotation mark.
;; In: A = the character
;; Out: A = the character, QTSW = toggled for a quotation mark
QTSWC:
    cmp #'"'
    bne QTSWC_1
    lda QTSW
    eor #1
    sta QTSW
    lda #'"'
QTSWC_1:
    rts

;; Prints a shifted character (bit 6 added), then as <NXT3>.
;; In: A = the screen code
NXT33:
    ora #$40

;; Prints a screen code at the cursor, reversed while <RVS> is on, and moves the cursor right.
;;
;; Running off the end of the logical line's first row makes the line two rows long, scrolling first at the
;; bottom; off the second, it goes to the next line. Then it returns from <PRT>.
;; In: A = the screen code
NXT3:
    ldx RVS
    beq NC3_1

;; Prints a screen code reversed at the cursor.
;; Inherit: <NXT3> In
NC3:
    ora #$80
NC3_1:
    ldx INSRT
    beq NC3_2
    dec INSRT
NC3_2:
    jsr DSPP
    inc PNTR
    ldy LNMX
    cpy PNTR
    bcs LOOP2
    ldx TBLX
    cpy #2 * SCREEN_COLUMNS - 1
    bne NC3_3
    jsr JSTSX
    jsr NXLN
    lda #$00
    sta PNTR
    beq LOOP2
NC3_3:
    cpx #SCREEN_ROWS - 1
    bne JTS2
    jsr SCRL

;; Ends <PRT>: pulls Y, X and A, which it pushed, ends quote mode when inserts are pending, and enables
;; interrupts.
LOOP2:
    pla
    tay
    lda INSRT
    beq LOOP2_1
    lsr QTSW
LOOP2_1:
    pla
    tax
    pla
    cli
    rts

;; Marks the row two below a row as starting a logical line, when there is one.
;; In: X = the row
;; Uses: A
JSTSX:
    cpx #SCREEN_ROWS - 2
    bcs JSTSX_1
    lda LDTB1+2,x
    ora #$80
    sta LDTB1+2,x
JSTSX_1:
    rts

;; Makes the cursor's line two rows long and ends <PRT>, for <NXT3> running off a line's first row.
JTS2:
    jsr JSTS2
    jmp LOOP2

;; Scrolls the screen up, then makes the cursor's line (now a row higher) two rows long.
SCRL:
    jsr SCROL
    dec TBLX
    ldx TBLX

;; Makes a logical line two rows long: links the row below it, and starts a line at the row after.
;; In: X = the line's row
;; Uses: A, X
JSTS2:
    asl LDTB1+1,x
    lsr LDTB1+1,x
    jsr JSTSX
    lda PNTR
    pha
    jsr STUPT
    pla
    sta PNTR
    rts

;; Moves the cursor back to the last column of the logical line above, for DEL and cursor left at a line's start.
;;
;; On the top row it leaves the cursor in column 0 and returns from <PRT>.
;; Uses: A, X, Y
BKLN:
    ldy #SCREEN_COLUMNS - 1
    ldx TBLX
    bne BKLN_1
    stx PNTR
    pla
    pla
    bne LOOP2
BKLN_1:
    lda LDTB1 - 1,x
    bmi BKLN_2
    dex
    lda LDTB1 - 1,x
    ldy #2 * SCREEN_COLUMNS - 1
BKLN_2:
    dex
    stx TBLX
    sta PNT+1
    lda LDTB2,x
    sta PNT
    sty PNTR
    sty LNMX
    rts

;; Prints a character on the screen at the cursor: the kernal's BSOUT for the screen.
;;
;; Printable characters are stored as their screen codes. RETURN (or shifted RETURN) moves to the next line and
;; ends quote mode, inserts and reversing. The cursor keys, HOME, CLR, RVS, DEL and INST do their jobs, except in
;; quote mode or while inserts are pending, where they print as reversed characters instead.
;; In: A = the character
;; Keeps: A, X, Y
PRT:
    pha
    sta CHAR_TEMP
    txa
    pha
    tya
    pha
    lda #$00
    sta CRSW
    ldy PNTR
    lda CHAR_TEMP
    bpl PRT_1
    jmp NXTX
PRT_1:
    cmp #KEY_RETURN
    bne PRT_2
    jmp NXT1
PRT_2:
    cmp #' '
    bcc PRT_3
    and #$3F
    jsr QTSWC
    jmp NXT3
PRT_3:
    ldx INSRT
    beq PRT_4
    jmp NC3
PRT_4:
    cmp #KEY_DEL                            ; DEL
    bne PRT_7
    dey
    sty PNTR
    bpl PRT_5
    jsr BKLN
    jmp PRT_6
PRT_5:
    iny
    lda (PNT),y
    dey
    sta (PNT),y
    iny
    cpy LNMX
    bne PRT_5
PRT_6:
    lda #' '
    sta (PNT),y
    bne JPL3
PRT_7:
    ldx QTSW
    beq PRT_8
    jmp NC3
PRT_8:
    cmp #KEY_RVS                            ; RVS on
    bne PRT_9
    sta RVS
PRT_9:
    cmp #KEY_HOME                           ; HOME
    bne PRT_10
    jsr NXTD
PRT_10:
    cmp #KEY_RIGHT                          ; cursor right
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
    cmp #KEY_DOWN                           ; cursor down
    bne JPL3
    clc
    tya
    adc #SCREEN_COLUMNS
    tay
    cmp LNMX
    bcc PRT_11
    beq PRT_11
    jsr NXLN

;; Inherit: <LOOP2>
JPL3:
    jmp LOOP2
    ; Unreachable: nothing jumps to these bytes.
    inx
    sta TBLX
    tya
    sbc #SCREEN_COLUMNS
    sta PNTR
    inc TBLX
    lda LDTB2
    sta PNT
    lda LDTB1
    sta PNT+1
    bne JPL3

;; Inherit: <PRT>
;; Prints a character with bit 7 set: the shifted characters, cursor up and left, CLR, RVS off and INST.
NXTX:
    and #$7F
    cmp #$7F
    bne NXTX_1
    lda #'^'
NXTX_1:
    cmp #' '
    bcc NXTX_2
    jmp NXT33
NXTX_2:
    cmp #KEY_RETURN
    bne NXTX_3
    jmp NXT1
NXTX_3:
    ldx QTSW
    bne NXTX_8
    cmp #KEY_DEL                            ; INST
    bne NXTX_7
    ldy LNMX
    lda (PNT),y
    cmp #' '
    bne NXTX_4
    cpy PNTR
    bne NXTX_5
NXTX_4:
    cpy #2 * SCREEN_COLUMNS - 1
    beq JPL3
    jsr NEWLN
NXTX_5:
    ldy LNMX
NXTX_6:
    dey
    lda (PNT),y
    iny
    sta (PNT),y
    dey
    cpy PNTR
    bne NXTX_6
    lda #' '
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
    cmp #KEY_DOWN                           ; cursor up
    bne NXTX_12
    lda PNTR
    cmp #SCREEN_COLUMNS
    bcc NXTX_10
    sbc #SCREEN_COLUMNS
    sta PNTR
    bcs NXTX_15
NXTX_10:
    ldx TBLX
    beq NXTX_15
    lda LDTB1 - 1,x
    bpl NXTX_11
    dec TBLX
    jsr STUPT
    bcc NXTX_15
NXTX_11:
    dex
    dex
    stx TBLX
    jsr STUPT
    lda PNTR
    clc
    adc #SCREEN_COLUMNS
    sta PNTR
    bne NXTX_15
NXTX_12:
    cmp #KEY_RVS                            ; RVS off
    bne NXTX_13
    lda #$00
    sta RVS
NXTX_13:
    cmp #KEY_RIGHT                          ; cursor left
    bne NXTX_14
    dey
    sty PNTR
    bpl NXTX_15
    jsr BKLN
    jmp LOOP2
NXTX_14:
    cmp #KEY_HOME                           ; CLR
    bne NXTX_15
    jsr CLSR
NXTX_15:
    jmp LOOP2

;; Moves the cursor down to the next logical line, scrolling at the bottom, and clears <INPUT_ROW>'s top bit.
;; Uses: A, X
NXLN:
    sec
    lsr INPUT_ROW
    ldx TBLX
NXLN_1:
    inx
    cpx #SCREEN_ROWS
    bne NXLN_2
    jsr SCROL
NXLN_2:
    lda LDTB1,x
    bpl NXLN_1
    stx TBLX
    jmp STUPT

;; Prints RETURN: ends quote mode, inserts and reversing, and moves to the start of the next line.
NXT1:
    lda #$00
    sta INSRT
    sta RVS
    sta QTSW
    sta PNTR
    jsr NXLN
    jmp LOOP2

;; Scrolls the screen up by the top logical line, one row or two, and clears the rows it opens at the bottom.
;;
;; The screen is blanked while video RAM moves. With RVS down (the only key down in row 9), it then waits about
;; half a second and empties the keyboard buffer, so holding RVS slows a listing.
;; Out: X = TBLX
;; Uses: A, Y
SCROL:
    sei
    ldy #$00
    sty PNT
    lda #>SCREEN
    sta SAL+1
    sta PNT+1
    lda #<(SCREEN + SCREEN_COLUMNS)
    bit LDTB1+1
    bmi SCROL_1
    lda #<(SCREEN + 2 * SCREEN_COLUMNS)
SCROL_1:
    sta SAL
    lda #PIA_LOW
    sta PIA1_CRA                            ; blank the screen
SCROL_2:
    lda (SAL),y                             ; move the screen up
    sta (PNT),y
    iny
    bne SCROL_2
    inc SAL+1
    inc PNT+1
    lda #>SCREEN + 4
    cmp SAL+1
    bne SCROL_2
    lda #<(SCREEN + SCREEN_SIZE)
    sta PNT
    dec PNT+1
    lda #' '
SCROL_3:
    dec PNT                                 ; clear the rows opened
    dec SAL
    sta (PNT),y
    bne SCROL_3
    ldx #SCREEN_ROWS
    stx TBLX
SCROL_4:
    ldx #$00
    dec TBLX
SCROL_5:
    lda LDTB1,x                             ; move the links' bit 7 up a row
    and #$7F
    ldy LDTB1+1,x
    bpl SCROL_6
    ora #$80
SCROL_6:
    sta LDTB1,x
    inx
    cpx #SCREEN_ROWS
    bne SCROL_5
    lda #>SCREEN + 3
    sta LDTB1 + SCREEN_ROWS - 1
    lda LDTB1
    bpl SCROL_4
    lda #PIA_HIGH
    sta PIA1_CRA
    cli
    lda #(~$01) & $FF
    cmp PIA1_PB                             ; only RVS down?
    bne SCROL_9
    ldy #$08
SCROL_7:
    sta VIA_T1CH                            ; wait about half a second
SCROL_8:
    bit VIA_IFR
    bvc SCROL_8
    dey
    bne SCROL_7
    sty NDX                                 ; empty the keyboard buffer
SCROL_9:
    ldx TBLX
    rts

;; Opens a row below the cursor's line, for INST when the line is full, moving the rows below down one.
;;
;; The row becomes the line's second row. On the last rows it scrolls instead.
;; Uses: A, X, Y
NEWLN:
    ldx TBLX
    inx
    sei
    lda #PIA_LOW
    sta PIA1_CRA
    cpx #SCREEN_ROWS - 1
    beq NEWLN_5
    bcc NEWLN_1
    jmp SCRL
NEWLN_1:
    ldx #SCREEN_ROWS - 2
NEWLN_2:
    lda LDTB1+1,x
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
    ldy #SCREEN_COLUMNS - 1
    lda LDTB2 + 1,x
    sta SAL
    lda LDTB2,x
    sta PNT
NEWLN_4:
    lda (PNT),y
    sta (SAL),y
    dey
    bpl NEWLN_4
    dex
    cpx TBLX
    bne NEWLN_2
    inx
NEWLN_5:
    lda LDTB1,x
    ora #$80
    sta PNT+1
    and #$7F
    sta LDTB1,x
    lda LDTB2,x
    sta PNT
    ldy #SCREEN_COLUMNS - 1
    lda #' '
NEWLN_6:
    sta (PNT),y
    dey
    bpl NEWLN_6
    lda #PIA_HIGH
    sta PIA1_CRA
    cli
    jmp STUPT

;; Takes the IRQ and BRK: pushes A, X and Y, then goes through <CBINV> for BRK or <CINV> for an interrupt.
PULS:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda STACK + 4,x                         ; the status the interrupt pushed
    and #STATUS_BREAK
    beq PULS_1
    jmp (CBINV)
PULS_1:
    jmp (CINV)

;; Handles the retrace interrupt, sixty times a second.
;;
;; It updates the jiffy clock (<JUDTIM>), blinks the cursor every 20 jiffies while <BLNSW> is zero, starts each
;; cassette's motor while its PLAY key is down (unless the kernal runs it), and scans the keyboard: a key found
;; down that wasn't at the last scan goes into <KEYD>, shifted with SHIFT. A key held down doesn't repeat.
KEY:
    jsr JUDTIM                              ; the jiffy clock
    lda BLNSW                               ; blink the cursor
    bne KEY_2
    dec BLNCT
    bne KEY_2
    lda #BLINK_JIFFIES
    sta BLNCT
    ldy PNTR
    lsr BLNON
    lda (PNT),y
    bcs KEY_1
    inc BLNON
    sta GDBLN
KEY_1:
    eor #$80
    sta (PNT),y
KEY_2:
    ldx #$FF                                ; scan the keyboard
    stx SFDX
    inx
    stx SHFLAG
    ldx #KEY_COUNT
    lda PIA1_PA
    and #$F0
    sta PIA1_PA
    ldy #$00
    lda PIA1_PA                             ; the cassettes' keys: PA4 into negative, PA5 into carry
    asl a
    asl a
    asl a
    bpl KEY_3
    sty CAS1
    lda #PIA_HIGH_IRQ
    bne KEY_4
KEY_3:
    lda CAS1
    bne KEY_5
    lda #PIA_LOW_IRQ
KEY_4:
    sta PIA1_CRB                            ; cassette 1's motor
KEY_5:
    bcc KEY_6
    sty CAS2
    lda VIA_ORB
    ora #VIA_MOTOR2
    bne KEY_7
KEY_6:
    lda CAS2
    bne KEY_8
    lda VIA_ORB
    and #(~VIA_MOTOR2) & $FF
KEY_7:
    sta VIA_ORB                             ; cassette 2's motor
KEY_8:
    ldy #$08
    lda PIA1_PB                             ; read the row until steady
    cmp PIA1_PB
    bne KEY_8
KEY_9:
    lsr a
    bcs KEY_13
    pha
    lda CHAR - 1,x
    bne KEY_10
    lda #$01
    sta SHFLAG                              ; a SHIFT key
    bne KEY_12
KEY_10:
    cmp #KEY_NONE
    beq KEY_12
    cmp #'<'
    bne KEY_11
    bit PIA1_CRA                            ; '<' doesn't count while CA1's flag is set
    bmi KEY_12
KEY_11:
    stx SFDX
KEY_12:
    pla
KEY_13:
    dex
    beq KEY_14
    dey
    bne KEY_9
    inc PIA1_PA
    bne KEY_8
KEY_14:
    lda SFDX
    cmp LSTX                                ; the same key as last time?
    beq PREND
    sta LSTX
    tax
    bmi PREND
    lda CHAR - 1,x
    lsr SHFLAG
    bcc KEY_15
    ora #KEY_SHIFTED
KEY_15:
    ldx NDX
    sta KEYD,x
    inx
    cpx #KEY_BUFFER_SIZE
    bne KEY_16
    ldx #$00                                ; a full buffer starts again
KEY_16:
    stx NDX

;; Ends an interrupt: pulls Y, X and A, which <PULS> pushed, and returns.
PREND:
    pla
    tay
    pla
    tax
    pla
    rti

;; Stores a screen code at the cursor, waiting for the retrace so the 2001's screen doesn't flicker.
;; In: A = the screen code
;; Keeps: A, X
DSPP:
    tay
DSPP_1:
    lda VIA_ORB                             ; wait for vertical blanking
    and #VIA_RETRACE
    bne DSPP_1
    tya
    ldy PNTR
    sta (PNT),y
    rts

;; The keyboard's matrix, from the last place scanned to the first: each row from column 7 (PB7) down to column 0
;; (PB0), from row 9 up to row 0. <KEY> counts an index down from <KEY_COUNT> as it scans, and reads the
;; key at the index less one, so the table's first byte is index 1. A key typed with SHIFT gets <KEY_SHIFTED> added.
CHAR:
    .byte '=', '.', KEY_NONE, KEY_STOP, '<', ' ', '[', KEY_RVS            ; row 9, columns 7-0
    .byte '-', '0', KEY_SHIFT, '>', KEY_NONE, ']', '@', KEY_SHIFT         ; row 8, columns 7-0
    .byte '+', '2', KEY_NONE, '?', ',', 'N', 'V', 'X'                     ; row 7, columns 7-0
    .byte '3', '1', KEY_RETURN, ';', 'M', 'B', 'C', 'Z'                   ; row 6, columns 7-0
    .byte '*', '5', KEY_NONE, ':', 'K', 'H', 'F', 'S'                     ; row 5, columns 7-0
    .byte '6', '4', KEY_NONE, 'L', 'J', 'G', 'D', 'A'                     ; row 4, columns 7-0
    .byte '/', '8', KEY_NONE, 'P', 'I', 'Y', 'R', 'W'                     ; row 3, columns 7-0
    .byte '9', '7', '^', 'O', 'U', 'T', 'E', 'Q'                          ; row 2, columns 7-0
    .byte KEY_DEL, KEY_DOWN, KEY_NONE, ')', $5C, $27, '$', $22            ; row 1, columns 7-0
    .byte KEY_RIGHT, KEY_HOME, '_', '(', '&', '%', '#', '!'               ; row 0, columns 7-0
    .assert * - CHAR = KEY_COUNT, "CHAR has a byte for each place in the matrix."

;; The low byte of each screen row's address in video RAM; <LDTB1> holds the high bytes.
LDTB2:
.repeat SCREEN_ROWS, row
    .byte <(SCREEN + row * SCREEN_COLUMNS)
.endrepeat

;; What SHIFT and RUN type: LOAD, then RUN, each with RETURN.
RUNTB:
    .byte "LOAD", KEY_RETURN, "RUN", KEY_RETURN
RUN_TEXT_END:
    .assert RUNTB - LDTB2 = SCREEN_ROWS, "LOOP3 reads RUNTB from just after LDTB2."

;; Prints <STAL> as four hexadecimal digits.
;; Uses: A, X
WROA:
    ldx #$01
    lda STAL - 1,x
    pha
    lda STAL,x
    jsr WROB
    pla

;; Prints a byte as two hexadecimal digits.
;; In: A = the byte
;; Uses: A, X
WROB:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr ASCII
    tax
    pla
    and #$0F
    jsr ASCII

;; Prints two characters: the one in X, then the one in A.
;; In: A = the second, X = the first
;; Keeps: A
WRTWO:
    pha
    txa
    jsr OUTCH
    pla
    jmp OUTCH

;; Turns a number from 0 to 15 into its hexadecimal digit.
;; In: A = the number
;; Out: A = the digit
ASCII:
    clc
    adc #$F6
    bcc ASCII_1
    adc #$06
ASCII_1:
    adc #$3A
    rts

;; Swaps <STAL> with <MEMUSS>.
;; Uses: A, X
T2T2:
    ldx #$02
T2T2_1:
    lda STAL - 1,x
    pha
    lda MEMUSS - 1,x
    sta STAL - 1,x
    pla
    sta MEMUSS - 1,x
    dex
    bne T2T2_1
    rts

;; Reads a hexadecimal address typed, four digits, into <STAL>.
;; Out: carry = set when read
;; Uses: A
RDOA:
    jsr RDOB
    bcc RDOA_1
    sta STAL+1
RDOA_1:
    jsr RDOB
    bcc RDOA_2
    sta STAL
RDOA_2:
    rts

;; Reads a hexadecimal byte typed: two digits, or a space and one digit; two spaces read nothing.
;; Out: A = the byte, carry = set when read
;; Uses: A
RDOB:
    lda #$00
    sta HEX_TEMP
    jsr RDOC
    cmp #' '
    bne RDOB_1
    jsr RDOC
    cmp #' '
    bne RDOB_2
    clc
    rts
RDOB_1:
    jsr HEXIT
    asl a
    asl a
    asl a
    asl a
    sta HEX_TEMP
    jsr RDOC
RDOB_2:
    jsr HEXIT
    ora HEX_TEMP
    sec
    rts

;; Turns a hexadecimal digit into its value.
;; In: A = the digit
;; Out: A = its value
HEXIT:
    cmp #'9' + 1
    php
    and #$0F
    plp
    bcc HEXIT_1
    adc #$08
HEXIT_1:
    rts

;; Reads a character typed for the monitor; RETURN ends the command, back to the prompt.
;; Out: A = the character
RDOC:
    jsr CQINCH
    cmp #KEY_RETURN
    bne HEXIT_1
    pla
    pla
    jmp MON_RESUME

;; Prints "?" and returns to the monitor's prompt, for a command it couldn't read.
ERROPR:
    lda #'?'
    jsr OUTCH
    jmp STRT
    .byte $FF                                                   ; unused
