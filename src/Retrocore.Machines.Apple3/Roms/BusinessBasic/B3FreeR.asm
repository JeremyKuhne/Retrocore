; B3FREER: marking a string's space free; the bank and page arithmetic every pointer into BASIC's banked memory goes
; through; the IF statement; and the WINDOW statement.
;
; BASIC's program, variables and strings live in the Apple III's banked memory, reached through enhanced indirect
; addressing: a pointer has a bank byte (its X-byte) as well as its two address bytes. BASIC keeps a pointer's page
; between MINPG and MAXPG-1 ($02-$81); a page past that is the same memory as the page $80 lower in the next bank. Each
; bank therefore holds $80 pages, and these routines carry and borrow between page and bank to keep pointers in range.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Pointer maintenance
; ---------------------------------------------------------------------------------------------------------------------

;; Marks a string's space free, for garbage collection to reclaim.
;;
;; The three info bytes after a string's text normally hold its owner's type ($41 a simple variable, $81 an array) and a
;; pointer back to its descriptor. A free block has a type of 0, a zero byte, and its length.
;; In: A = the string's length, INDEX, INDEXB = its text
;; Out: GRBTOP, GRBTOPB = the text, HEADER, HEADERB = its info bytes
;; Uses: A, X, Y, TEMP
;; See: <FRESPA>
TSTFRE:
    ldx INDEX
    ldy INDEX+1
    stx GRBTOP
    sty GRBTOP+1
    ldx INDEXB
    stx GRBTOPB
    sta TEMP
    clc
    adc GRBTOP
    sta HEADER
    lda #0
    adc GRBTOP+1
    ldy GRBTOPB
    jsr FIXADC
    sta HEADER+1
    sty HEADERB
    lda TEMP                                ; the length goes last
    ldy #2

;; Writes the length, then two zeros, into the info bytes at (<HEADER>).
FREIT1:
    sta (HEADER),Y
    lda #0
    dey
    bpl FREIT1
    rts

;; Brings a page back into range after a subtract that may have borrowed.
;;
;; A borrow out of the page (carry clear) takes $100 pages, two banks, from the bank.
;; In: A = the page, Y = the bank, carry = clear for a borrow out of the page
;; Out: A = the page, between MINPG and MAXPG-1, Y = the bank, carry = set
;; See: <FIXADC>, <FIXSB2>
FIXSBC:
    bcs *+4
    dey
    dey

;; Brings a page back into range, a bank's $80 pages up or down, without looking at the carry.
;; In: A = the page, Y = the bank
;; Out: A = the page, between MINPG and MAXPG-1, Y = the bank, carry = set
FIXSB2:
    cmp #MINPG
    bcs *+5
    adc #MAXPG-MINPG                        ; below MINPG: up a bank's worth of pages
    dey                                     ; from the bank below
    cmp #MAXPG
    bcc *+5
    sbc #MAXPG-MINPG                        ; MAXPG or above: down into the next bank
    iny
    sec
    rts

;; Brings a page back into range after an add that may have carried.
;;
;; A carry out of the page (carry set) adds $100 pages, two banks, to the bank.
;; In: A = the page, Y = the bank, carry = set for a carry out of the page
;; Out: A = the page, between MINPG and MAXPG-1, Y = the bank, carry = clear
;; See: <FIXSBC>
FIXADC:
    bcc *+4
    iny
    iny
    jsr FIXSB2
    clc
    rts

;; Subtracts a count of pages from a bank and page, the high half of taking an ordinary 16-bit length from a pointer.
;;
;; Bit 7 of X stands for a bank's $80 pages; its other bits are pages.
;; In: A = the page, Y = the bank, X = the pages to subtract, carry = clear for a borrow from the low bytes
;; Out: A = the page, between MINPG and MAXPG-1, Y = the bank, carry = set
;; Uses: CHARAC
;; See: <FIXAY>, <FIXSBC>
FIXYAX:
    php
    pha
    txa
    asl
    bcc *+3
    dey                                     ; bit 7: one bank less
    lsr
    sta CHARAC
    pla
    plp
    sbc CHARAC                              ; the borrow from the caller's low bytes
    jmp FIXSBC

;; Steps a bank and page pointer back a page.
;;
;; Apple's comment says it increments; it decrements.
;; In: X = the bank, Y = the page
;; Out: X = the bank, Y = the page, between MINPG and MAXPG-1
;; Keeps: A
FIXXY:
    dey
    cpy #MINPG
    bcs FIXRTSX
    ldy #MAXPG-1
    dex
    rts

;; Brings a page past the bank's window down into the next bank.
;; In: X = the bank, Y = the page, below MAXPG + $80
;; Out: X = the bank, Y = the page, below MAXPG
;; Keeps: A
FIXYX:
    cpy #MAXPG
    bcc FIXRTSX
    pha
    tya
    sbc #MAXPG-MINPG
    tay
    pla
    inx

;; An RTS for <FIXXY> and <FIXYX>.
FIXRTSX:
    rts

;; Finishes the difference of two banked pointers as a 16-bit count of pages.
;; In: A = the first pointer's page less the second's, Y = the first pointer's bank, X = the second pointer's bank,
;;   carry = from the page subtract, clear for a borrow out of the page
;; Out: Y = the high byte of the difference in pages, A = its low byte
;; Uses: CHARAC
;; See: <FIXAY>
FIXAYX:
    jsr FIXSBC
    pha
    tya
    stx CHARAC
    sbc CHARAC                              ; the difference of the banks
    tay
    pla

;; Packs a bank and page into one 16-bit count of pages, bank * $80 + page.
;;
;; The bank is signed, so a pointer difference from <FIXSBC> (whose bank may be -1 with the page $80) packs to the
;; plain difference in pages: the high bytes of an ordinary length.
;; In: A = the page, Y = the bank
;; Out: Y = the count's high byte, A = its low byte
;; See: <FIXYA>, <FIXAYX>
FIXAY:
    sec
    sbc #MINPG
    asl
    pha
    tya
    cmp #$80                                ; the bank's sign into the carry
    ror
    tay
    pla
    ror                                     ; the bank's low bit into bit 7
    adc #MINPG
    bcc *+3
    iny
    rts

;; Unpacks a count of pages in A, as a string descriptor holds its address, into a bank and page.
;;
;; Bit 7 of A adds one to the bank in Y and the page is brought into range, keeping bank * $80 + page the same. With
;; Y = 0, as callers pass it, this undoes <FIXAY> for a count below $100.
;; In: A = the packed page, Y = the bank
;; Out: A = the page, between MINPG and MAXPG-1, Y = the bank
;; Keeps: carry
;; See: <FIXAY>, <NOTNOW>
FIXYA:
    php
    asl
    pha
    tya
    adc #0
    tay
    pla
    lsr
    cmp #MINPG
    bcs *+5
    adc #MAXPG-MINPG
    dey
    plp
    rts

; ---------------------------------------------------------------------------------------------------------------------
; IF...THEN...ELSE
; ---------------------------------------------------------------------------------------------------------------------

;; The IF statement: runs what follows THEN or GOTO when the condition is true, or what follows the matching ELSE when
;; it is false.
;;
;; The condition is a real or long integer formula; zero is false. THEN may be followed by a line number or by
;; statements; GOTO by a line number. When false, the rest of the line is searched for its ELSE, counting the IFs it
;; passes so that a nested IF's ELSE is skipped; with no ELSE, the next line runs. A line number after ELSE is a GOTO.
;; In: TXTPTR = past the IF token
;; Errors: ERRTM = a string condition, ERRSN = neither THEN nor GOTO
;; See: <ELSE1>, <DOCOND>
IF:
    lda #1
    sta LVLCNT                              ; one IF to match
    lda #$20
    sta VALTYP                              ; any numeric type
    jsr FRMEVL
    bit VALTYP
    bpl *+5
    jmp MISERR
    jsr CHRGOT
    cmp #GOTOTK
    beq OKGOTO
    lda #THENTK                             ; THEN, an escape token
    jsr MSTESC

;; Tests the condition: a long integer by all its bytes, a real by its exponent.
OKGOTO:
    bit VALTYP
    bvc EXPBYTC                             ; not a long integer
    ldx #0
    lda #<(FAC)
    ldy #>(FAC)
    jsr LORALL                              ; zero when all of FAC is
    bvs ISATRUE                             ; always: LORALL leaves the overflow flag from the BIT

;; Tests a real condition: an exponent of 0 is a zero.
EXPBYTC:
    lda FACEXP

;; Runs THEN's part when the condition is true, or else looks for the ELSE.
;; In: zero = set for false
ISATRUE:
    bne DOCOND
    ldy #$FF

;; Scans the line for the ELSE that matches the IF, through Y; with none, goes on at the next line.
;; In: LVLCNT = the IFs still to match, Y = one before the next character to look at
ELSE1:
    iny
    lda (TXTPTR),Y
    bne NOTEOL
    jmp ADDON                               ; the line's end: on to the next line

;; Counts an IF or ELSE in the scan; at the matching ELSE, goes on after it.
NOTEOL:
    cmp #IFTOKN
    beq PLSONE
    cmp #ELSETK
    bne ELSE1
    dec LVLCNT
    bne ELSE1                               ; a nested IF's ELSE
    jsr ADDON                               ; TXTPTR to the ELSE
    jsr CHRGET
    bcc DOCOND1                             ; a line number: GOTO it
    bcs DOCO

;; Counts a nested IF, whose ELSE must be passed over.
PLSONE:
    inc LVLCNT
    bcs ELSE1                               ; always

;; Runs what follows THEN or GOTO: a line number goes to that line; anything else runs as statements.
DOCOND:
    lda #$0
    sta LVLCNT
    jsr CHRGOT
    bcs DOCO

;; Goes to the line number at TXTPTR.
DOCOND1:
    jmp GOTO

;; Runs the statement at TXTPTR, dropping NEWSTT's return address and backing TXTPTR up so <NWSTT> reads it afresh.
DOCO:
    pla
    pla
    jsr DECTPT
    jmp NWSTT

; ---------------------------------------------------------------------------------------------------------------------
; WINDOW
; ---------------------------------------------------------------------------------------------------------------------

;; The WINDOW statement: `WINDOW x1,y1 TO x2,y2` sets the console's viewport to that rectangle.
;;
;; The corners may come in either order; columns and lines count from 1. The viewport is set with the console's
;; control codes: 1 to release it to the full screen, 26 to move the cursor to a column and line, 3 and 2 to make the
;; cursor's position the bottom right and top left corners. Last, code 25 moves the cursor to the bottom line's number.
;; In: TXTPTR = past the WINDOW token
;; Out: SLEFT, STOPS = the left column and top line, SWIDTH, SBOTTOM = the right column and bottom line
;; Errors: ERRFC = a number out of a byte's range, ERRSN = a missing comma or TO
;; See: <DOITOUT>, <VWINDER>
WINDOW:
    jsr GETBYT
    stx SLEFT
    jsr CHKCOM
    jsr GETBYT
    stx SBOTTOM
    lda #TOTK                               ; TO, an escape token
    jsr MSTESC
    jsr GETBYT
    stx SWIDTH                              ; the right column, despite the name
    cpx SLEFT
    bcs NOTIN
    lda SLEFT                               ; the larger column on the right
    stx SLEFT
    sta SWIDTH

;; Takes the second line and puts the larger line at the bottom.
NOTIN:
    jsr CHKCOM
    jsr GETBYT
    stx STOPS
    cpx SBOTTOM
    bcc WINDER
    lda SBOTTOM
    stx SBOTTOM
    sta STOPS

;; Sends the console the codes that set the viewport, then moves the cursor to the bottom line.
WINDER:
    lda #1                                  ; release the viewport
    jsr PRNACHAR
    lda #$1A                                ; the cursor to the bottom right
    jsr PRNACHAR
    lda SWIDTH
    jsr DOITOUT
    lda SBOTTOM
    jsr DOITOUT
    lda #3                                  ; the viewport's bottom right
    jsr PRNACHAR
    lda #$1A                                ; the cursor to the top left
    jsr PRNACHAR
    lda SLEFT
    jsr DOITOUT
    lda STOPS
    jsr DOITOUT
    lda #2                                  ; the viewport's top left
    jsr PRNACHAR
    ldx SBOTTOM
    lda #25                                 ; the cursor to that line
    jmp VWINDER

;; Sends a column or line counted from 1 to the console as one counted from 0; 0 stays 0.
;; In: A = the column or line
DOITOUT:
    sec
    sbc #$1
    bcs *+4
    lda #0
    jmp PRNACHAR
