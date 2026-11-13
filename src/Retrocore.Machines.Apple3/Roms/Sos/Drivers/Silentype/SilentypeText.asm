; .SILENTYPE's text layer: the bytes a program writes, the commands, and printing a line. Included by Silentype.asm.

; ---------------------------------------------------------------------------------------------------------------------
; The bytes a program writes.
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a byte a program writes, the routine depending on <STATE>.
;; In: A = the byte
;; Uses: A, X, Y, INBYTE
PUTBYTE:
    sta INBYTE
    SWITCH a:STATE, , STATESW, *
    lda INBYTE
    rts

;; The routines for a byte written, less one, by <STATE>.
STATESW:
    .word TEXTBYTE-1                    ; IN_TEXT
    .word CMDLETTER-1                   ; IN_COMMAND
    .word CMDARGBYTE-1                  ; IN_ARGUMENT
    .word SENDMECH-1                    ; IN_GRAPHICS

;; Takes a byte of text: prints a character, acts on a control character, or starts a command.
;; In: A = the byte
;; Uses: A, X, Y
TEXTBYTE:
    and #$7F                            ; ignore bit 7
    cmp #' '
    bcc TEXTBYTE_1
    jmp PRINTABLE
TEXTBYTE_1:
    ldx #CTLCOUNT-1
TEXTBYTE_2:
    cmp CTLCHARS,x
    beq TEXTBYTE_3
    dex
    bpl TEXTBYTE_2
    cmp a:CMDCHAR                       ; the command character as a control character
    beq STARTCMD
    rts
TEXTBYTE_3:
    txa
    asl a
    tax
    lda CTLCHARSW+1,x
    pha
    lda CTLCHARSW,x
    pha
    rts

;; The control characters <TEXTBYTE> acts on.
CTLCHARS:
    .byte $0D                           ; Return
    .byte $0A                           ; Line Feed
    .byte $0C                           ; Form Feed
    .byte ASC_BS                        ; Backspace
    .byte $0E                           ; Control-N: a reverse line feed
    .byte $06                           ; Control-F: print what is buffered
    .assert * - CTLCHARS == CTLCOUNT

;; Their routines' addresses less one, in the same order.
CTLCHARSW:
    .word DO_CR-1
    .word DO_LF-1
    .word DO_FF-1
    .word DO_BS-1
    .word DO_RLF-1
    .word FLUSHLINE-1

;; Starts a command: the next byte is its letter.
STARTCMD:
    inc a:STATE
    rts

;; Return: prints the line and goes back to the left margin, then feeds a line when auto line feed is on.
;; Uses: A, X, Y
DO_CR:
    jsr NEWLINE
    lda #MODE_AUTOLF
    bit a:MODES
    bne ENDLINE_1
    rts

;; Form Feed: prints the line, feeds <FORMLEN> lines, and goes back to the left margin.
;; Uses: A, X, Y
DO_FF:
    jsr PRINTLINE
    jsr FORMFEED
    jmp TOMARGIN

;; Prints the line, goes back to the left margin, and feeds a line.
;; Uses: A, X, Y
ENDLINE:
    jsr NEWLINE
ENDLINE_1:
    jmp LINEFEED

;; Line Feed: feeds a line now when the line is empty, or marks the move in it.
;; Uses: A, X, Y
DO_LF:
    lda a:LINELEN
    beq ENDLINE_1
    lda a:LINESPACE
    sta a:CMDARG
    jmp CMD_VMOVE

;; Control-N: feeds a line backward now when the line is empty, or marks the move in it.
;; Uses: A, X, Y
DO_RLF:
    lda a:LINELEN
    beq DO_RLF_1
    lda a:LINESPACE
    jsr NEGATE
    sta a:CMDARG
    jmp CMD_VMOVE
DO_RLF_1:
    jmp REVLINEFEED

;; Moves <LINEEND> back a character: the glyph, the space after it and the widened columns.
;; Uses: A
BACKCELL:
    lda a:LINEEND
    sec
    sbc a:GLYPHW                        ; less the glyph
    php
    sec
    sbc a:CHARSPACE                     ; less the space after it
    sta a:LINEEND
    bcs BACKCELL_1
    dec a:LINEEND+1
BACKCELL_1:
    plp
    jsr BACKCELL_2
    sec
    lda a:LINEEND
    sbc a:EXTRAW                        ; less the widened columns
    sta a:LINEEND
BACKCELL_2:
    bcs BACKCELL_3
    dec a:LINEEND+1
BACKCELL_3:
    rts

;; Backspace: backs <LINEEND> up a character, and puts the Backspace in the line, unless that is left of 0.
;; Uses: A, X, Y
DO_BS:
    jsr BACKCELL
    lda a:LINEEND+1
    bmi DO_BS_1
    lda #ASC_BS
    jmp BUFFERBYTE
DO_BS_1:
    lda #$00                            ; not left of 0
    sta a:LINEEND
    sta a:LINEEND+1
    rts

;; Control-F: prints what is buffered and goes on from where it ended. <BUFFERBYTE> also calls it when the line is full.
;; Uses: A, X, Y
FLUSHLINE:
    lda a:LINEEND
    pha
    lda a:LINEEND+1
    pha
    jsr PRINTLINE
    pla
    sta a:LINEEND+1
    sta a:LINESTART+1
    pla
    sta a:LINEEND
    sta a:LINESTART
    jmp TOMARGIN_1

;; Prints the line and goes back to the left margin.
;; Uses: A, X, Y
NEWLINE:
    jsr PRINTLINE

;; Starts the next line at the left margin, and releases the head motor.
;; Uses: A, X, Y
TOMARGIN:
    lda a:LMARGIN
    sta a:LINEEND
    sta a:LINESTART
    lda a:LMARGIN+1
    sta a:LINEEND+1
    sta a:LINESTART+1
TOMARGIN_1:
    jmp HEADOFF

;; Puts a printing character in the line, or starts a command for the command character.
;; When the line has passed the right margin it is printed and a line feed starts the next, or, truncating, the rest of
;; the line is dropped.
;; In: A = the character
;; Uses: A, X, Y
PRINTABLE:
    cmp a:CMDCHAR                       ; the command character as a printing character
    bne PRINTABLE_1
    inc a:STATE
    rts
PRINTABLE_1:
    pha
    lda a:RMARGIN+1
    cmp a:LINEEND+1                     ; past the right margin?
    bcc PRINTABLE_2
    bne PRINTABLE_4
    lda a:RMARGIN
    cmp a:LINEEND
    bcs PRINTABLE_4
PRINTABLE_2:
    lda a:MODES
    and #MODE_TRUNCATE
    beq PRINTABLE_3
    lda a:MODES                         ; truncating: drop the rest of the line
    ora #MODE_OVERFLOW
    sta a:MODES
    pla
    rts
PRINTABLE_3:
    jsr NEWLINE
    jsr LINEFEED
PRINTABLE_4:
    lda a:MODES
    and #MODE_OVERFLOW
    beq PRINTABLE_5
    pla
    rts
PRINTABLE_5:
    jsr GLYPHWIDTH                      ; plus the glyph
    clc
    adc a:LINEEND
    php
    adc a:CHARSPACE                     ; plus the space
    sta a:LINEEND
    bcc PRINTABLE_6
    inc a:LINEEND+1
PRINTABLE_6:
    plp
    bcc PRINTABLE_7
    inc a:LINEEND+1
PRINTABLE_7:
    lda a:LINEEND
    clc
    adc a:EXTRAW                        ; plus the widened columns
    sta a:LINEEND
    bcc PRINTABLE_8
    inc a:LINEEND+1
PRINTABLE_8:
    pla

;; Puts a byte in <LINEBUF>, and prints what is buffered when that fills it to <LINEMAX>.
;; In: A = the byte
;; Uses: A, X, Y
BUFFERBYTE:
    ldy a:LINELEN
    sta a:LINEBUF,y
    iny
    sty a:LINELEN
    cpy #LINEMAX
    bcs BUFFERBYTE_2
BUFFERBYTE_1:
    rts
BUFFERBYTE_2:
    jmp FLUSHLINE

;; Puts a byte in <LINEBUF>.
;; In: A = the byte
;; Uses: Y
APPEND:
    ldy a:LINELEN
    sta a:LINEBUF,y
    inc a:LINELEN
    rts

;; Sends a byte to the mechanism layer, setting the write's error when it fails.
;; In: A = the byte
;; Out: carry = set when it failed, ERRCODE = XIOERROR then
;; Uses: A, X, Y, INBYTE
SENDMECH:
    sta INBYTE
    jsr MECHBYTE
    bcc BUFFERBYTE_1
    lda #XIOERROR
    sta ERRCODE
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The commands.
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a command's letter: carries out the command, or waits for its argument byte.
;; An unknown letter ends the command.
;; In: A = the letter
;; Uses: A, X, Y
CMDLETTER:
    ldx #CMDCOUNT-1
    and #$7F                            ; ignore bit 7
CMDLETTER_1:
    cmp CMDLETTERS,x
    beq CMDLETTER_2
    dex
    bpl CMDLETTER_1
    dec a:STATE
    rts
CMDLETTER_2:
    stx a:CMDINDEX
    lda CMDARGS,x
    bne CMDLETTER_3                     ; the command takes an argument

;; Takes a command's argument byte and carries the command out.
;; In: A = the argument
;; Uses: A, X, Y
CMDARGBYTE:
    sta a:CMDARG
    lda #IN_TEXT
    sta a:STATE
    lda a:CMDINDEX
    asl a
    tax
    lda CMDSW+1,x
    pha
    lda CMDSW,x
    pha
    rts
CMDLETTER_3:
    inc a:STATE
    rts

;; The command letters, after the command character.
CMDLETTERS:
    .byte '<'                           ; both directions
    .byte '>'                           ; left to right only
    .byte 'E'                           ; auto line feed on
    .byte 'e'                           ; auto line feed off
    .byte 'F'                           ; nothing
    .byte 'J'                           ; the left margin
    .byte 'K'                           ; the right margin
    .byte 'L'                           ; the lines in a form feed
    .byte '.'                           ; the dots between characters
    .byte '^'                           ; the steps in a line
    .byte 'C'                           ; truncate long lines
    .byte 'c'                           ; wrap long lines
    .byte 'H'                           ; move along the line
    .byte 'V'                           ; move the paper
    .byte '='                           ; reset
    .byte 'W'                           ; widen the characters
    .byte 'w'                           ; normal width
    .byte 'B'                           ; bold on
    .byte 'b'                           ; bold off
    .byte 'G'                           ; graphics
    .byte '?'                           ; the command character
    .assert * - CMDLETTERS == CMDCOUNT

;; The commands' routines, less one, in the same order.
CMDSW:
    .word CMD_BIDIR-1                   ; <
    .word CMD_UNIDIR-1                  ; >
    .word CMD_AUTOLF-1                  ; E
    .word CMD_NOAUTOLF-1                ; e
    .word CMD_FONT-1                    ; F
    .word CMD_LMARGIN-1                 ; J
    .word CMD_RMARGIN-1                 ; K
    .word CMD_FORMLEN-1                 ; L
    .word CMD_SPACING-1                 ; .
    .word CMD_LINESPACE-1               ; ^
    .word CMD_TRUNCATE-1                ; C
    .word CMD_WRAP-1                    ; c
    .word CMD_HMOVE-1                   ; H
    .word CMD_VMOVE-1                   ; V
    .word CTL_RESET-1                   ; =
    .word CMD_WIDTH-1                   ; W
    .word CMD_NORMALW-1                 ; w
    .word CMD_BOLD-1                    ; B
    .word CMD_NOBOLD-1                  ; b
    .word CMD_GRAPHICS-1                ; G
    .word CMD_CMDCHAR-1                 ; ?

;; Which commands take an argument byte: nonzero for those that do, in the same order.
;;
;; The table stops short of `?`, the last command: its entry is the first byte of <CMD_UNIDIR>, an LDA
;; opcode, which is nonzero, so `?` takes an argument as it should.
CMDARGS:
    .byte $00                           ; <
    .byte $00                           ; >
    .byte $00                           ; E
    .byte $00                           ; e
    .byte $80                           ; F
    .byte $80                           ; J
    .byte $80                           ; K
    .byte $80                           ; L
    .byte $80                           ; .
    .byte $80                           ; ^
    .byte $00                           ; C
    .byte $00                           ; c
    .byte $80                           ; H
    .byte $80                           ; V
    .byte $00                           ; =
    .byte $80                           ; W
    .byte $00                           ; w
    .byte $00                           ; B
    .byte $00                           ; b
    .byte $80                           ; G
    .assert * - CMDARGS == CMDCOUNT-1

;; The > command: prints each line left to right.
CMD_UNIDIR:
    lda a:MODES
    ora #MODE_UNIDIR
    bne SETMODES

;; The < command: prints in both directions.
CMD_BIDIR:
    lda a:MODES
    and #<(~MODE_UNIDIR)
    bpl SETMODES

;; The E command: Return also feeds a line.
CMD_AUTOLF:
    lda a:MODES
    ora #MODE_AUTOLF
    bne SETMODES

;; The e command: Return doesn't feed a line.
CMD_NOAUTOLF:
    lda a:MODES
    and #<(~MODE_AUTOLF)

;; Stores the mode bits.
;; In: A = the modes
SETMODES:
    sta a:MODES
    rts

;; The F command: does nothing with its argument.
CMD_FONT:
    rts

;; The J command: moves the left margin to <CMDARG> character cells, when that is left of the right margin, then
;; ends the line.
;; Uses: A, X, Y, FACTOR1, FACTOR2, PRODUCT
CMD_LMARGIN:
    lda a:CMDARG
    sta FACTOR1
    lda a:GLYPHW
    clc
    adc a:CHARSPACE
    sta FACTOR2
    jsr MULTIPLY
    lda PRODUCT+1                       ; is the new margin left of the right one?
    cmp a:RMARGIN+1
    bcc CMD_LMARGIN_2
    bne CMD_LMARGIN_1
    lda PRODUCT
    cmp a:RMARGIN
    bcc CMD_LMARGIN_2
CMD_LMARGIN_1:
    rts
CMD_LMARGIN_2:
    lda PRODUCT
    sta a:LMARGIN
    lda PRODUCT+1
    sta a:LMARGIN+1
    jmp ENDLINE

;; The K command: moves the right margin to <CMDARG> character cells, when that is less than <RMARGINMAX>, then
;; ends the line.
;; Uses: A, X, Y, FACTOR1, FACTOR2, PRODUCT
CMD_RMARGIN:
    lda a:CMDARG
    sta FACTOR1
    lda a:GLYPHW
    clc
    adc a:CHARSPACE
    sta FACTOR2
    jsr MULTIPLY
    lda PRODUCT+1                       ; is the new margin less than RMARGINMAX?
    cmp #>RMARGINMAX
    bcc CMD_RMARGIN_1
    bne CMD_LMARGIN_1
    lda PRODUCT
    cmp #<RMARGINMAX
    bcc CMD_RMARGIN_1
    rts
CMD_RMARGIN_1:
    lda PRODUCT
    sta a:RMARGIN
    lda PRODUCT+1
    sta a:RMARGIN+1
    jmp ENDLINE

;; The . command: sets the dot columns between characters (0-15), marking the change in the line.
;; Uses: A, X, Y
CMD_SPACING:
    lda #MARK_SPACING
    jsr APPEND                          ; a spacing change: mark, old, new, mark
    lda a:CHARSPACE
    jsr APPEND
    lda a:CMDARG
    and #$0F
    sta a:CHARSPACE
    jsr APPEND
    lda #MARK_SPACING
    jmp BUFFERBYTE

;; The L command: sets the lines in a form feed (0-15).
CMD_FORMLEN:
    lda a:CMDARG
    and #$0F
    sta a:FORMLEN
    rts

;; The ^ command: sets the paper steps in a line (0-15).
CMD_LINESPACE:
    lda a:CMDARG
    and #$0F
    sta a:LINESPACE
    rts

;; The H command: moves along the line <CMDARG> dots (signed), marking the move, unless that leaves the margins.
;; Uses: A, X, Y
CMD_HMOVE:
    clc
    lda a:CMDARG
    pha
    ldy a:LINEEND+1
    adc a:LINEEND
    tax
    pla
    bmi CMD_HMOVE_3                     ; a move left
    bcc CMD_HMOVE_1
    iny
CMD_HMOVE_1:
    cpy a:RMARGIN+1
    bcc CMD_HMOVE_5
    bne CMD_HMOVE_2
    cpx a:RMARGIN
    bcc CMD_HMOVE_5
CMD_HMOVE_2:
    rts
CMD_HMOVE_3:
    bcs CMD_HMOVE_4
    dey
    bmi CMD_HMOVE_2
CMD_HMOVE_4:
    cpy a:LMARGIN+1
    bcc CMD_HMOVE_2
    bne CMD_HMOVE_5
    cpx a:LMARGIN
    bcc CMD_HMOVE_2
CMD_HMOVE_5:
    stx a:LINEEND
    sty a:LINEEND+1
    lda #MARK_HMOVE                     ; a move: mark, dots, mark
    pha
    jsr APPEND
    lda a:CMDARG
    jsr APPEND
    pla
CMD_HMOVE_6:
    jmp BUFFERBYTE

;; The V command: moves the paper <CMDARG> steps (signed, 1-15 forward); now when the line is empty, or marked in it.
;; Uses: A, X, Y
CMD_VMOVE:
    lda a:LINELEN
    beq CMD_VMOVE_2                     ; an empty line moves the paper now
    lda #MARK_VMOVE
    jsr APPEND
    lda a:CMDARG
    bmi CMD_VMOVE_1                     ; a move back keeps its high bits
    and #$0F
CMD_VMOVE_1:
    pha
    clc
    adc a:VMOVE                         ; the line's net paper motion
    sta a:VMOVE
    pla
    jsr APPEND
    lda #MARK_VMOVE
    bne CMD_HMOVE_6
CMD_VMOVE_2:
    lda a:CMDARG
    jmp FEEDPAPER

;; The W command: widens the characters by <WIDTHS> entry <CMDARG> (0-7), keeping bold.
;; Uses: A, X, Y
CMD_WIDTH:
    lda a:CMDARG
    and #$07
    tax
    lda a:STYLE
    and #STYLE_BOLD
    ora WIDTHS,x
    jmp SETSTYLE

;; The w command: the normal width, keeping bold.
;; Uses: A, X, Y
CMD_NORMALW:
    lda a:STYLE
    and #STYLE_BOLD
    jmp SETSTYLE

;; The B command: bold.
;; Uses: A, X, Y
CMD_BOLD:
    lda a:STYLE
    bmi SETSTYLE_1
    ora #STYLE_BOLD

;; Sets <STYLE>, marking the change in the line, and counts the columns it adds.
;; In: A = the new style
;; Uses: A, X, Y
SETSTYLE:
    pha
    lda #MARK_STYLE                     ; a style change: mark, old, new, mark
    jsr APPEND
    lda a:STYLE
    jsr APPEND
    pla
    sta a:STYLE
    jsr APPEND
    lda #MARK_STYLE
    jsr BUFFERBYTE
    jsr COUNTEXTRA
SETSTYLE_1:
    rts

;; The b command: not bold.
;; Uses: A, X, Y
CMD_NOBOLD:
    lda a:STYLE
    bpl SETSTYLE_1
    and #<(~STYLE_BOLD)
    bpl SETSTYLE

;; The G command: prints what is buffered, then sends the bytes that follow to the mechanism layer.
;; Uses: A, X, Y
CMD_GRAPHICS:
    jsr FLUSHLINE
    lda #IN_GRAPHICS
    sta a:STATE
    rts

;; The C command: truncates lines at the right margin.
CMD_TRUNCATE:
    lda a:MODES
    ora #MODE_TRUNCATE
    bne STOREMODES

;; The c command: wraps lines at the right margin.
CMD_WRAP:
    lda a:MODES
    and #<(~MODE_TRUNCATE)

;; Stores the mode bits.
;; In: A = the modes
STOREMODES:
    sta a:MODES
    rts

;; The ? command: makes <CMDARG> the command character.
CMD_CMDCHAR:
    lda a:CMDARG
    sta a:CMDCHAR
    rts

;; Multiplies two bytes.
;; In: FACTOR1, FACTOR2 = the factors
;; Out: PRODUCT = their product
;; Uses: A, X
MULTIPLY:
    lda #$00
    sta PRODUCT
    sta PRODUCT+1
    ldx FACTOR1
    beq MULTIPLY_3
MULTIPLY_1:
    clc
    lda FACTOR2
    adc PRODUCT
    sta PRODUCT
    bcc MULTIPLY_2
    inc PRODUCT+1
MULTIPLY_2:
    dex
    bne MULTIPLY_1
MULTIPLY_3:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Printing a line.
; ---------------------------------------------------------------------------------------------------------------------

;; Prints the line in <LINEBUF> and empties it.
;; Trailing spaces are dropped first. Printing only left to right, it starts from the margin switch. Otherwise it prints
;; right to left, from the line's end, when the head is past the end or nearer the end than the start, and then finds
;; the margin again; or left to right from the start. Each way, the settings changed along the line are made at their
;; places (<NEXTENTRY>).
;; Uses: A, X, Y
PRINTLINE:
    ldy a:LINELEN
PRINTLINE_1:
    cpy #$00
    beq PRINTLINE_6
    dey                                 ; drop trailing spaces
    lda a:LINEBUF,y
    cmp #' '
    bne PRINTLINE_2
    sty a:LINELEN
    jsr BACKCELL
    jmp PRINTLINE_1
PRINTLINE_2:
    lda #<LINEHEAT
    sta a:EXTRAHEAT
    lda #>LINEHEAT
    sta a:EXTRAHEAT+1
    lda #MODE_UNIDIR
    bit a:MODES
    beq PRINTLINE_8                     ; bidirectional
    jsr HOMEHEAD                        ; unidirectional: start from home
PRINTLINE_3:
    jsr RESTSTYLE                       ; print left to right
    lda a:HEADPOS
    ora a:HEADPOS+1
    bne PRINTLINE_4
    jsr TOLEFTMARGIN                    ; the head is home: out to the margin
PRINTLINE_4:
    lda a:LINESTART
    sta a:LINEEND
    lda a:LINESTART+1
    sta a:LINEEND+1
    jsr HEADTO
    jsr GORIGHT                         ; left to right
    ldy #$00
    sty ENTRYINDEX
PRINTLINE_5:
    cpy a:LINELEN
    bcc PRINTLINE_7
PRINTLINE_6:
    jmp CLEARLINE
PRINTLINE_7:
    lda a:LINEBUF,y
    sta CHAR
    jsr PRINTENTRY
    inc ENTRYINDEX
    ldy ENTRYINDEX
    bne PRINTLINE_5
PRINTLINE_8:
    lda a:LINEEND+1                     ; is the line's end left of the head?
    cmp a:HEADPOS+1
    bcc PRINTLINE_9
    bne PRINTLINE_11
    lda a:LINEEND
    cmp a:HEADPOS
    bcs PRINTLINE_11
PRINTLINE_9:
    jsr HEADTO                          ; print right to left, from the line's end
    jsr DOVERTICAL                      ; the line's paper motion first
    jsr SAVESTYLE                       ; the end's settings, to put back afterward
    jsr GOLEFT
    lda #M_SPACE+2                      ; two more columns left first
    jsr SENDMECH
PRINTLINE_10:
    ldy a:LINELEN
    beq PRINTLINE_13
    dey
    sty a:LINELEN
    lda a:LINEBUF,y
    sta CHAR
    jsr PRINTENTRY
    jmp PRINTLINE_10
PRINTLINE_11:
    sec                                 ; FACTOR1/FACTOR2 = the distance to the end
    lda a:LINEEND
    sbc a:HEADPOS
    sta FACTOR1
    lda a:LINEEND+1
    sbc a:HEADPOS+1
    sta FACTOR2
    lda a:HEADPOS                       ; PRODUCT = the distance from the start
    sec
    sbc a:LINESTART
    sta PRODUCT
    lda a:HEADPOS+1
    sbc a:LINESTART+1
    bmi PRINTLINE_12                    ; the head is left of the start
    cmp FACTOR2
    bcc PRINTLINE_12
    bne PRINTLINE_9
    lda PRODUCT
    cmp FACTOR1
    bcs PRINTLINE_9
PRINTLINE_12:
    jmp PRINTLINE_3
PRINTLINE_13:
    lda #M_HOME                         ; back home
    jsr SENDMECH
    jsr DOVERTICAL
    jsr RESTSTYLE

;; Empties the line, and saves the settings as they are at its start.
;; Uses: A
CLEARLINE:
    lda #$00
    sta a:LINELEN
    sta a:VMOVE
    lda a:MODES
    and #<(~MODE_OVERFLOW)
    sta a:MODES

;; Saves <FONT>, <STYLE> and <CHARSPACE> in <LINESTYLE>.
;; Uses: A
SAVESTYLE:
    lda a:FONT
    sta a:LINESTYLE
    lda a:STYLE
    sta a:LINESTYLE+1
    lda a:CHARSPACE
    sta a:LINESTYLE+2
SAVESTYLE_1:
    rts

;; Restores <FONT>, <STYLE> and <CHARSPACE> from <LINESTYLE>.
;; Uses: A
RESTSTYLE:
    lda a:LINESTYLE
    sta a:FONT
    lda a:LINESTYLE+1
    sta a:STYLE
    lda a:LINESTYLE+2
    sta a:CHARSPACE
    rts

;; Moves the paper the line's net motion, <VMOVE>, before it is printed right to left.
;; Uses: A, X, Y
DOVERTICAL:
    lda #$00
    sta MOVECOUNT+1
    lda #M_FEED
    sta MOVECMD
    lda a:VMOVE
    sta MOVECOUNT
    beq SAVESTYLE_1
    bpl DOVERTICAL_1
    jsr NEGATE
    sta MOVECOUNT
    lda #M_UNFEED
    sta MOVECMD
DOVERTICAL_1:
    jmp SENDMOVES

;; Prints an entry of the line: a character, a Backspace, or a marked change.
;; In: CHAR = the entry
;; Uses: A, X, Y
PRINTENTRY:
    lda CHAR
    bmi PRINTENTRY_2
    cmp #ASC_BS
    beq PRINTENTRY_1

;; Prints a character and the space after it, the space first when printing right to left.
;; In: CHAR = the character
;; Uses: A, X, Y
PRINTCHAR:
    bit a:DIRECTION
    php
    bpl PRINTCHAR_3
PRINTCHAR_1:
    lda a:CHARSPACE
    beq PRINTCHAR_2
    ora #M_SPACE
    jsr SENDMECH
PRINTCHAR_2:
    plp
    bpl PRINTCHAR_4
PRINTCHAR_3:
    jsr PRINTGLYPH
    bit a:DIRECTION
    bpl PRINTCHAR_1
PRINTCHAR_4:
    rts
PRINTENTRY_1:
    jsr TURNAROUND
    lda #' '
    sta CHAR
    jsr PRINTCHAR

;; Stops the head and turns it around.
;; Uses: A, X, Y
TURNAROUND:
    jsr HEADOFF
    jsr WAIT3
    jsr WAIT3
    jmp TURN
PRINTENTRY_2:
    SWITCH , , MARKSW, *
    jsr NEXTENTRY                       ; past the mark first
    rts

;; Steps to the next entry of the line: <ENTRYINDEX> up, or <LINELEN> down when printing right to left.
NEXTENTRY:
    bit a:DIRECTION
    bmi NEXTENTRY_1
    inc ENTRYINDEX
    rts
NEXTENTRY_1:
    dec a:LINELEN
    rts

;; The routines that make a change marked in <LINEBUF>, less one, by the mark's low bits.
MARKSW:
    .word REPLAY_NONE-1                 ; $80
    .word REPLAY_SPACING-1              ; MARK_SPACING
    .word REPLAY_FONT-1                 ; MARK_FONT
    .word REPLAY_STYLE-1                ; MARK_STYLE
    .word REPLAY_HMOVE-1                ; MARK_HMOVE
    .word REPLAY_VMOVE-1                ; MARK_VMOVE

;; Mark $80, which nothing makes: nothing.
REPLAY_NONE:
    rts

;; Makes a marked change of <CHARSPACE>: the new value left to right, the old right to left.
;; Uses: A, Y
REPLAY_SPACING:
    jsr SKIPREAD
    sta a:CHARSPACE
    rts

;; Makes a marked change of <FONT>.
;; Uses: A, Y
REPLAY_FONT:
    jsr SKIPREAD
    sta a:FONT
    rts

;; Makes a marked change of <STYLE>.
;; Uses: A, Y
REPLAY_STYLE:
    jsr SKIPREAD
    sta a:STYLE
    rts

;; Makes a marked move along the line.
;; Uses: A, X, Y, MOVECOUNT, MOVECMD
REPLAY_HMOVE:
    lda #$00
    sta MOVECOUNT+1
    lda #M_SPACE
    sta MOVECMD
    jsr READENTRY
    tay
    sta MOVECOUNT
    bpl REPLAY_HMOVE_1
    jsr HEADOFF                         ; a move left: stop and wait before turning
    jsr WAIT
    dec MOVECOUNT+1
    lda MOVECOUNT+1
    jmp HEADTO_1
REPLAY_HMOVE_1:
    jmp SENDMOVES

;; Makes a marked move of the paper, backward when printing right to left.
;; Uses: A, X, Y
REPLAY_VMOVE:
    jsr HEADOFF
    jsr READVMOVE

;; Moves the paper 1-15 steps, forward or back, and releases the paper motor.
;; In: A = the steps, signed (0 does nothing)
;; Uses: A, X, Y, FACTOR1
FEEDPAPER:
    tay
    bmi FEEDPAPER_2                     ; back
    and #$0F
    beq NEGATE_1
    sta FACTOR1
    lda #M_FEED
FEEDPAPER_1:
    ora FACTOR1
    jsr SENDMECH
    jmp PAPEROFF
FEEDPAPER_2:
    jsr NEGATE
    and #$0F
    beq NEGATE_1
    sta FACTOR1
    lda #M_UNFEED
    bne FEEDPAPER_1

;; Skips an entry of the line, then reads the next (<READENTRY>).
SKIPREAD:
    jsr NEXTENTRY

;; Reads an entry of the line and steps past it.
;; Out: A = the entry
;; Uses: Y
READENTRY:
    ldy ENTRYINDEX
    bit a:DIRECTION
    bpl READENTRY_1
    ldy a:LINELEN
READENTRY_1:
    lda a:LINEBUF,y
    jmp NEXTENTRY

;; Reads a marked paper move, negated when printing right to left.
;; Out: A = the steps
;; Uses: Y
READVMOVE:
    jsr READENTRY
    bit a:DIRECTION
    bpl NEGATE_1

;; Negates A.
;; In: A = the value
;; Out: A = its negative
NEGATE:
    eor #$FF
    clc
    adc #$01
NEGATE_1:
    rts

;; Feeds a line: <LINESPACE> steps, then releases the paper motor.
;; Uses: A, X, Y
LINEFEED:
    lda a:LINESPACE
    beq NEGATE_1
    lda #M_FEED
LINEFEED_1:
    ora a:LINESPACE
    jsr SENDMECH
LINEFEED_2:
    jmp PAPEROFF

;; Feeds a line backward.
;; Uses: A, X, Y
REVLINEFEED:
    lda a:LINESPACE
    beq NEGATE_1
    lda #M_UNFEED
    bne LINEFEED_1

;; Feeds <FORMLEN> lines.
;; Uses: A, X, Y, MOVECOUNT
FORMFEED:
    lda a:FORMLEN
    beq NEGATE_1
    sta MOVECOUNT
FORMFEED_1:
    lda a:LINESPACE
    beq NEGATE_1
    ora #M_FEED
    jsr SENDMECH
    dec MOVECOUNT
    bne FORMFEED_1
    beq LINEFEED_2

;; Moves the head to <LINEEND>, facing right.
;; Uses: A, X, Y, MOVECOUNT, MOVECMD
HEADTO:
    jsr GORIGHT
    lda #M_SPACE
    sta MOVECMD
    sec
    lda a:LINEEND
    sbc a:HEADPOS
    sta MOVECOUNT
    lda a:LINEEND+1
    sbc a:HEADPOS+1
    sta MOVECOUNT+1
    bpl SENDMOVES
HEADTO_1:
    eor #$FF
    sta MOVECOUNT+1
    lda MOVECOUNT
    eor #$FF
    sta MOVECOUNT
    inc MOVECOUNT
    bne HEADTO_2
    inc MOVECOUNT+1
HEADTO_2:
    lda #M_BACK
    sta MOVECMD

;; Sends a move of any length, as moves of 15 and one of the rest.
;; In: MOVECOUNT = the count, MOVECMD = the kind of move
;; Uses: A, X, Y
SENDMOVES:
    lda MOVECOUNT+1
    bne SENDMOVES_1
    lda MOVECOUNT
    cmp #$10
    bcc SENDMOVES_2
SENDMOVES_1:
    lda MOVECMD
    ora #$0F
    jsr SENDMECH
    sec
    lda MOVECOUNT
    sbc #$0F
    sta MOVECOUNT
    bcs SENDMOVES
    dec MOVECOUNT+1
    bpl SENDMOVES
SENDMOVES_2:
    lda MOVECOUNT
    beq SENDMOVES_3
    ora MOVECMD
    jsr SENDMECH
SENDMOVES_3:
    rts

;; Finds the margin switch, then moves the head to the left margin.
;; Uses: A, X, Y
HOMEHEAD:
    lda #M_HOME
    jsr SENDMECH

;; Moves the head from the margin switch to the left margin, and releases the head motor.
;; Uses: A, X, Y, MOVECOUNT, MOVECMD
TOLEFTMARGIN:
    lda a:LMARGIN
    sta MOVECOUNT
    lda a:LMARGIN+1
    sta MOVECOUNT+1
    jsr GORIGHT
    lda #M_SPACE
    sta MOVECMD
    jsr SENDMOVES
    lda #$00
    sta a:LASTCOL
    sta a:PREVCOL
    jmp HEADOFF

;; Prints a character's glyph, columns in the head's direction, widened and bold as <STYLE> says.
;; Bold prints each column with the one before it, and the last once more.
;; In: CHAR = the character
;; Uses: A, X, Y, GLYPHCOLS, WIDTHBITS, BOLDCOL, GLYPHCOL, MOVECOUNT
PRINTGLYPH:
    jsr GLYPHWIDTH
    sta GLYPHCOLS
    lda a:STYLE
    sta WIDTHBITS
    ldy #$00
    sty BOLDCOL
    bit a:DIRECTION
    bpl PRINTGLYPH_1
    ldy GLYPHCOLS
    dey
PRINTGLYPH_1:
    sty GLYPHCOL
PRINTGLYPH_2:
    jsr GLYPHCOLUMN
    lda DOTS
    sta MOVECOUNT
    bit a:STYLE
    bpl PRINTGLYPH_3
    ora BOLDCOL
    pha
    lda MOVECOUNT
    sta BOLDCOL
    pla
    sta MOVECOUNT
PRINTGLYPH_3:
    ora #M_DOTS
    jsr SENDMECH
    lsr WIDTHBITS
    bcc PRINTGLYPH_4
    lda MOVECOUNT
    ora #M_DOTS
    jsr SENDMECH
PRINTGLYPH_4:
    bit a:DIRECTION
    bpl PRINTGLYPH_5
    dec GLYPHCOL
    bpl PRINTGLYPH_2
    bmi PRINTGLYPH_6
PRINTGLYPH_5:
    inc GLYPHCOL
    lda GLYPHCOL
    cmp GLYPHCOLS
    bne PRINTGLYPH_2
PRINTGLYPH_6:
    bit a:STYLE
    bpl PRINTGLYPH_7
    lda BOLDCOL
    ora #M_DOTS
    jsr SENDMECH
PRINTGLYPH_7:
    rts

;; The widths the W command picks, 0-7: for each, the glyph columns (bit 0 the first) that print twice, symmetric so
;; that they print the same in either direction. Control request 6 replaces the table.
WIDTHS:
    .byte %00000                        ; 0: five columns
    .byte %00100                        ; 1: six
    .byte %10001                        ; 2: seven
    .byte %01010                        ; 3: seven
    .byte %01110                        ; 4: eight
    .byte %10101                        ; 5: eight
    .byte %11011                        ; 6: nine
    .byte %11111                        ; 7: ten
    .assert * - WIDTHS == WIDTHCOUNT
