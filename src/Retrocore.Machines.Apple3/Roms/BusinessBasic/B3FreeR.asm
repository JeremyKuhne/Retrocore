; retrocore: style=strict
;; Marking a string's space free (<Strings::MarkFree>); the page and bank arithmetic every pointer into BASIC's banked
;; memory goes through (<Memory>); the `IF` statement; and the `WINDOW` statement.
;;
;; BASIC's program, variables and strings live in the Apple III's banked memory, reached through enhanced indirect
;; addressing: a pointer has an X-byte, which picks a bank pair, as well as its two address bytes. BASIC keeps a
;; pointer's page between <MINPG> and <MAXPG>-1 ($02-$81); a page past that is the same memory as the page $80 lower
;; through the next X-byte. Each step of the X-byte is therefore $80 pages, 32K, and these routines carry and borrow
;; between page and X-byte to keep pointers in range.

; ---------------------------------------------------------------------------------------------------------------------
; Freeing a string's space
; ---------------------------------------------------------------------------------------------------------------------

.scope Strings continued

;; Marks a string's space free, for the garbage collector to reclaim.
;;
;; The three information bytes after a string's text normally hold its owner's type (<SIMTYP> a simple variable,
;; <ARYTYP> an array element) and where its descriptor is. A free block has a type of 0, a zero byte, and its length.
;; In: A = the string's length, <INDEX>, INDEXB = its text
;; Out: GRBTOP, GRBTOPB = the text, <HEADER>, HEADERB = its information bytes
;; Uses: A, X, Y, TEMP
;; See: <Strings::FreeSpace>
;; Also: TSTFRE (BB13)
.proc MarkFree
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
    jsr Memory::NormalizeAfterAdd
    sta HEADER+1
    sty HEADERB
    lda TEMP                                ; the length goes last
    ldy #2

;; Writes the length, then two zeros, into the information bytes at (<HEADER>).
;; Also: FREIT1 (BB13)
Loop:
    sta (HEADER),Y
    lda #0
    dey
    bpl Loop
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Pointer arithmetic
; ---------------------------------------------------------------------------------------------------------------------

;; The arithmetic that keeps a banked pointer's page between <MINPG> and <MAXPG>-1, carrying into and borrowing from its
;; X-byte, and that packs a page and X-byte into one count of pages and back.
.scope Memory

;; Brings a page back into range after a subtract that may have borrowed.
;;
;; A borrow out of the page (carry clear) takes $100 pages, two X-byte steps, from the X-byte.
;; In: A = the page, Y = the X-byte, carry = clear for a borrow out of the page
;; Out: A = the page, between <MINPG> and <MAXPG>-1, Y = the X-byte, carry = set
;; Keeps: X
;; See: <Memory::NormalizeAfterAdd>, <Memory::NormalizePage>
;; Also: FIXSBC (BB13)
.proc NormalizeAfterSubtract
    bcs NormalizePage
    dey
    dey
    ; Falls into NormalizePage.
.endproc

;; Brings a page back into range, one X-byte step's $80 pages up or down, without looking at the carry.
;; In: A = the page, Y = the X-byte
;; Out: A = the page, between <MINPG> and <MAXPG>-1, Y = the X-byte, carry = set
;; Keeps: X
;; Also: FIXSB2 (BB13)
.proc NormalizePage
    cmp #MINPG
    bcs NotBelow
    adc #MAXPG-MINPG                        ; below MINPG: up an X-byte step's worth of pages
    dey                                     ; from the X-byte below
NotBelow:
    cmp #MAXPG
    bcc InRange
    sbc #MAXPG-MINPG                        ; MAXPG or above: down into the next X-byte
    iny
InRange:
    sec
    rts
.endproc

;; Brings a page back into range after an add that may have carried.
;;
;; A carry out of the page (carry set) adds $100 pages, two X-byte steps, to the X-byte.
;; In: A = the page, Y = the X-byte, carry = set for a carry out of the page
;; Out: A = the page, between <MINPG> and <MAXPG>-1, Y = the X-byte, carry = clear
;; Keeps: X
;; See: <Memory::NormalizeAfterSubtract>
;; Also: FIXADC (BB13)
.proc NormalizeAfterAdd
    bcc NoCarry
    iny
    iny
NoCarry:
    jsr NormalizePage
    clc
    rts
.endproc

;; Subtracts a count of pages from an X-byte and page, the high half of taking a 16-bit offset, packed by
;; <Memory::PackPages>, from a pointer.
;;
;; Bit 7 of X stands for an X-byte step's $80 pages; its other bits are pages.
;; In: A = the page, Y = the X-byte, X = the pages to subtract, carry = clear for a borrow from the low bytes
;; Out: A = the page, between <MINPG> and <MAXPG>-1, Y = the X-byte, carry = set
;; Uses: CHARAC
;; Keeps: X
;; See: <Memory::PackPages>, <Memory::NormalizeAfterSubtract>
;; Also: FIXYAX (BB13)
.proc SubtractPageCount
    php
    pha
    txa
    asl
    bcc NoStep
    dey                                     ; bit 7: one X-byte step less
NoStep:
    lsr
    sta CHARAC
    pla
    plp
    sbc CHARAC                              ; the borrow from the caller's low bytes
    jmp NormalizeAfterSubtract
.endproc

;; Steps an X-byte and page pointer back a page.
;;
;; Apple's comment says it increments; it decrements.
;; In: X = the X-byte, Y = the page
;; Out: X = the X-byte, Y = the page, between <MINPG> and <MAXPG>-1
;; Keeps: A
;; Also: FIXXY (BB13)
.proc PreviousPage
    dey
    cpy #MINPG
    bcs WrapPage::Done
    ldy #MAXPG-1
    dex
    rts
.endproc

;; Brings a page past the X-byte's window down through the next X-byte.
;; In: X = the X-byte, Y = the page, below <MAXPG> + $80
;; Out: X = the X-byte, Y = the page, below <MAXPG>
;; Keeps: A
;; Entry:
;;   Done = returns; <Memory::PreviousPage> branches here
;; Also: FIXYX (BB13)
.proc WrapPage
    cpy #MAXPG
    bcc Done
    pha
    tya
    sbc #MAXPG-MINPG
    tay
    pla
    inx

;; Returns.
;; Also: FIXRTSX (BB13)
Done:
    rts
.endproc

;; Finishes the difference of two banked pointers as a 16-bit count of pages.
;; In: A = the first pointer's page less the second's, Y = the first pointer's X-byte, X = the second pointer's
;;   X-byte, carry = from the page subtract, clear for a borrow out of the page
;; Out: Y = the high byte of the difference in pages, A = its low byte
;; Uses: CHARAC
;; See: <Memory::PackPages>
;; Also: FIXAYX (BB13)
.proc PageDifference
    jsr NormalizeAfterSubtract
    pha
    tya
    stx CHARAC
    sbc CHARAC                              ; the difference of the X-bytes
    tay
    pla
    ; Falls into PackPages.
.endproc

;; Packs an X-byte and page into one 16-bit count of pages, X-byte * $80 + page.
;;
;; The X-byte is signed, so a pointer difference from <Memory::NormalizeAfterSubtract> (whose X-byte may be -1 with
;; the page $80) packs to the plain difference in pages: the high bytes of an ordinary length.
;; In: A = the page, Y = the X-byte
;; Out: Y = the count's high byte, A = its low byte
;; Keeps: X
;; See: <Memory::UnpackPages>, <Memory::PageDifference>
;; Also: FIXAY (BB13)
.proc PackPages
    sec
    sbc #MINPG
    asl
    pha
    tya
    cmp #$80                                ; the X-byte's sign into the carry
    ror
    tay
    pla
    ror                                     ; the X-byte's low bit into bit 7
    adc #MINPG
    bcc Done
    iny
Done:
    rts
.endproc

;; Unpacks a count of pages in A, as a string descriptor holds its address, into an X-byte and page.
;;
;; Bit 7 of A adds one to the X-byte in Y and the page is brought into range, keeping X-byte * $80 + page the same.
;; With Y = 0, as callers pass it, this undoes <Memory::PackPages> for a count below $100.
;; In: A = the packed page, Y = the X-byte
;; Out: A = the page, between <MINPG> and <MAXPG>-1, Y = the X-byte
;; Keeps: X, carry
;; See: <Memory::PackPages>, <Strings::FindFromDescriptor>
;; Also: FIXYA (BB13)
.proc UnpackPages
    php
    asl
    pha
    tya
    adc #0
    tay
    pla
    lsr
    cmp #MINPG
    bcs Done
    adc #MAXPG-MINPG
    dey
Done:
    plp
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `IF`...`THEN`...`ELSE`
; ---------------------------------------------------------------------------------------------------------------------

.scope Statements continued

;; The `IF` statement: runs what follows `THEN` or `GOTO` when the condition is true, or what follows the matching
;; `ELSE` when it is false.
;;
;; The condition is a real or long integer formula; zero is false. `THEN` may be followed by a line number or by
;; statements; `GOTO` by a line number. When false, the rest of the line is searched for its `ELSE`, counting the
;; `IF`s it passes so that a nested `IF`'s `ELSE` is skipped; with no `ELSE`, the next line runs. A line number after
;; `ELSE` is a `GOTO`.
;; In: TXTPTR = past the `IF` token
;; Errors: ERRTM = a string condition, ERRSN = neither `THEN` nor <GOTO>
;; See: <Statements::IfTrue>
;; Also: IF (BB13)
.proc If
    lda #1
    sta LVLCNT                              ; one `IF` to match
    lda #VALUE_TYPE_ANY
    sta VALTYP                              ; any numeric type
    jsr FRMEVL
    bit VALTYP
    bpl Numeric
    jmp MISERR
Numeric:
    jsr CHRGOT
    cmp #GOTOTK
    beq Test
    lda #THENTK                             ; `THEN`, an escape token
    jsr MSTESC

;; Tests the condition: a long integer by all its bytes, a real by its exponent.
;; Also: OKGOTO (BB13)
Test:
    bit VALTYP
    bvc TestReal                            ; not a long integer
    ldx #0
    lda #<(FAC)
    ldy #>(FAC)
    jsr LORALL                              ; zero when all of FAC is
    bvs Branch                              ; always: LORALL leaves the overflow flag from the BIT

;; Tests a real condition: an exponent of 0 is a zero.
;; Also: EXPBYTC (BB13)
TestReal:
    lda FACEXP

;; Runs `THEN`'s part when the condition is true, or else looks for the `ELSE`.
;; In: zero = set for false
;; Also: ISATRUE (BB13)
Branch:
    bne IfTrue
    ldy #$FF

;; Scans the line for the `ELSE` that matches the `IF`, through Y; with none, goes on at the next line.
;; In: LVLCNT = the IFs still to match, Y = one before the next character to look at
;; Also: ELSE1 (BB13)
FindElse:
    iny
    lda (TXTPTR),Y
    bne CheckToken
    jmp ADDON                               ; the line's end: on to the next line

;; Counts an `IF` or `ELSE` in the scan; at the matching `ELSE`, goes on after it.
;; Also: NOTEOL (BB13)
CheckToken:
    cmp #IFTOKN
    beq NestedIf
    cmp #ELSETK
    bne FindElse
    dec LVLCNT
    bne FindElse                            ; a nested `IF`'s `ELSE`
    jsr ADDON                               ; TXTPTR to the `ELSE`
    jsr CHRGET
    bcc IfTrue::ToGoTo                      ; a line number: `GOTO` it
    bcs IfTrue::ToExecuteStatement

;; Counts a nested `IF`, whose `ELSE` must be passed over.
;; Also: PLSONE (BB13)
NestedIf:
    inc LVLCNT
    bcs FindElse                            ; always
.endproc

;; Runs what follows `THEN` or `GOTO`: a line number goes to that line; anything else runs as statements.
;; In: TXTPTR = the `THEN` or <GOTO> token
;; Entry:
;;   ToGoTo = goes to the line number at TXTPTR; <Statements::If> goes here for a line number after `ELSE`
;;   ToExecuteStatement = runs the statement at TXTPTR; <Statements::If> goes here for statements after `ELSE`
;; Also: DOCOND (BB13)
.proc IfTrue
    lda #0
    sta LVLCNT
    jsr CHRGOT
    bcs ToExecuteStatement

;; Goes to the line number at <TXTPTR>.
;; Also: DOCOND1 (BB13)
ToGoTo:
    jmp GOTO

;; Runs the statement at <TXTPTR>, dropping <NEWSTT>'s return address and backing <TXTPTR> up so <NWSTT> reads it
;; afresh.
;; Also: DOCO (BB13)
ToExecuteStatement:
    pla
    pla
    jsr BackUpTextPointer
    jmp NWSTT
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; `WINDOW`
; ---------------------------------------------------------------------------------------------------------------------

;; The `WINDOW` statement: `WINDOW x1,y1 TO x2,y2` sets the console's viewport to that rectangle.
;;
;; The corners may come in either order; columns and lines count from 1. The viewport is set with the console's
;; control codes: one to release it to the full screen, one to move the cursor to a column and line, and two to make
;; the cursor's position the viewport's bottom right and top left corners. Last, <VWINDER> moves the cursor to the
;; bottom line.
;; In: TXTPTR = past the `WINDOW` token
;; Out: SLEFT, STOPS = the left column and top line, <SWIDTH>, SBOTTOM = the right column and bottom line
;; Errors: ERRFC = a number out of a byte's range, ERRSN = a missing comma or TO
;; See: <SendCoordinate>, <VWINDER>
;; Also: WINDOW (BB13)
.proc Window
;; The console's code that releases the viewport to the full screen.
RESET_VIEWPORT = 1
;; The console's code that moves the cursor to the column and line in the two bytes after it.
MOVE_CURSOR = $1A
;; The console's code that makes the cursor's position the viewport's bottom right corner.
SET_BOTTOM_RIGHT = 3
;; The console's code that makes the cursor's position the viewport's top left corner.
SET_TOP_LEFT = 2
;; The console's code that moves the cursor to the line in the byte after it.
MOVE_TO_LINE = 25

    jsr GETBYT
    stx SLEFT
    jsr CheckComma
    jsr GETBYT
    stx SBOTTOM
    lda #TOTK                               ; TO, an escape token
    jsr MSTESC
    jsr GETBYT
    stx SWIDTH                              ; the right column, despite the name
    cpx SLEFT
    bcs SortLines
    lda SLEFT                               ; the larger column on the right
    stx SLEFT
    sta SWIDTH

;; Takes the second line and puts the larger line at the bottom.
;; Also: NOTIN (BB13)
SortLines:
    jsr CheckComma
    jsr GETBYT
    stx STOPS
    cpx SBOTTOM
    bcc SetViewport
    lda SBOTTOM
    stx SBOTTOM
    sta STOPS

;; Sends the console the codes that set the viewport, then moves the cursor to the bottom line.
;; Also: WINDER (BB13)
SetViewport:
    lda #RESET_VIEWPORT
    jsr PRNACHAR
    lda #MOVE_CURSOR                        ; the cursor to the bottom right
    jsr PRNACHAR
    lda SWIDTH
    jsr SendCoordinate
    lda SBOTTOM
    jsr SendCoordinate
    lda #SET_BOTTOM_RIGHT
    jsr PRNACHAR
    lda #MOVE_CURSOR                        ; the cursor to the top left
    jsr PRNACHAR
    lda SLEFT
    jsr SendCoordinate
    lda STOPS
    jsr SendCoordinate
    lda #SET_TOP_LEFT
    jsr PRNACHAR
    ldx SBOTTOM
    lda #MOVE_TO_LINE
    jmp VWINDER
.endproc

.endscope

;; Sends a column or line counted from 1 to the console as one counted from 0; 0 stays 0.
;; In: A = the column or line
;; See: <PRNACHAR>
;; Also: DOITOUT (BB13)
.proc SendCoordinate
    sec
    sbc #1
    bcs Send
    lda #0
Send:
    jmp PRNACHAR
.endproc
