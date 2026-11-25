; retrocore: style=strict
;; Marking a string's space free (<Strings::MarkFree>); the page and bank arithmetic every pointer into BASIC's banked
;; memory goes through (<Memory>); the `IF` statement; and the `WINDOW` statement.
;;
;; BASIC's program, variables and strings live in the Apple III's banked memory, reached through enhanced indirect
;; addressing: a pointer has an X-byte, which picks a bank pair, as well as its two address bytes. BASIC keeps a
;; pointer's page between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1 ($02-$81); a page past that is the same memory as the page $80 lower
;; through the next X-byte. Each step of the X-byte is therefore $80 pages, 32K, and these routines carry and borrow
;; between page and X-byte to keep pointers in range.

; ---------------------------------------------------------------------------------------------------------------------
; Freeing a string's space
; ---------------------------------------------------------------------------------------------------------------------

.scope Strings continued

;; Marks a string's space free, for the garbage collector to reclaim.
;;
;; The three information bytes after a string's text normally hold its owner's type (<STRING_TYPE_SIMPLE_VARIABLE> a simple variable,
;; <STRING_TYPE_ARRAY_ELEMENT> an array element) and where its descriptor is. A free block has a type of 0, a zero byte, and its length.
;; In: A = the string's length, <Pointer1>, INDEXB = its text
;; Out: GRBTOP, GRBTOPB = the text, <StringInformationPointer>, HEADERB = its information bytes
;; Uses: A, X, Y, TEMP
;; See: <Strings::FreeSpace>
;; Also: TSTFRE (BB13)
.proc MarkFree
    ldx Pointer1
    ldy Pointer1+1
    stx CollectorTop
    sty CollectorTop+1
    ldx Pointer1XByte
    stx CollectorTopXByte
    sta Temporary
    clc
    adc CollectorTop
    sta StringInformationPointer
    lda #0
    adc CollectorTop+1
    ldy CollectorTopXByte
    jsr Memory::NormalizeAfterAdd
    sta StringInformationPointer+1
    sty StringInformationPointerXByte
    lda Temporary                                ; the length goes last
    ldy #2

;; Writes the length, then two zeros, into the information bytes at (<StringInformationPointer>).
;; Also: FREIT1 (BB13)
Loop:
    sta (StringInformationPointer),Y
    lda #0
    dey
    bpl Loop
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Pointer arithmetic
; ---------------------------------------------------------------------------------------------------------------------

;; The arithmetic that keeps a banked pointer's page between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, carrying into and borrowing from its
;; X-byte, and that packs a page and X-byte into one count of pages and back.
.scope Memory

;; Brings a page back into range after a subtract that may have borrowed.
;;
;; A borrow out of the page (carry clear) takes $100 pages, two X-byte steps, from the X-byte.
;; In: A = the page, Y = the X-byte, carry = clear for a borrow out of the page
;; Out: A = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, Y = the X-byte, carry = set
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
;; Out: A = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, Y = the X-byte, carry = set
;; Keeps: X
;; Also: FIXSB2 (BB13)
.proc NormalizePage
    cmp #POINTER_PAGE_FIRST
    bcs NotBelow
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST                        ; below MINPG: up an X-byte step's worth of pages
    dey                                     ; from the X-byte below
NotBelow:
    cmp #POINTER_PAGE_LIMIT
    bcc InRange
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST                        ; MAXPG or above: down into the next X-byte
    iny
InRange:
    sec
    rts
.endproc

;; Brings a page back into range after an add that may have carried.
;;
;; A carry out of the page (carry set) adds $100 pages, two X-byte steps, to the X-byte.
;; In: A = the page, Y = the X-byte, carry = set for a carry out of the page
;; Out: A = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, Y = the X-byte, carry = clear
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
;; Out: A = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, Y = the X-byte, carry = set
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
    sta Delimiter
    pla
    plp
    sbc Delimiter                              ; the borrow from the caller's low bytes
    jmp NormalizeAfterSubtract
.endproc

;; Steps an X-byte and page pointer back a page.
;;
;; Apple's comment says it increments; it decrements.
;; In: X = the X-byte, Y = the page
;; Out: X = the X-byte, Y = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1
;; Keeps: A
;; Also: FIXXY (BB13)
.proc PreviousPage
    dey
    cpy #POINTER_PAGE_FIRST
    bcs WrapPage::Done
    ldy #POINTER_PAGE_LIMIT-1
    dex
    rts
.endproc

;; Brings a page past the X-byte's window down through the next X-byte.
;; In: X = the X-byte, Y = the page, below <POINTER_PAGE_LIMIT> + $80
;; Out: X = the X-byte, Y = the page, below <POINTER_PAGE_LIMIT>
;; Keeps: A
;; Entry:
;;   Done = returns; <Memory::PreviousPage> branches here
;; Also: FIXYX (BB13)
.proc WrapPage
    cpy #POINTER_PAGE_LIMIT
    bcc Done
    pha
    tya
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
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
    stx Delimiter
    sbc Delimiter                              ; the difference of the X-bytes
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
    sbc #POINTER_PAGE_FIRST
    asl
    pha
    tya
    cmp #$80                                ; the X-byte's sign into the carry
    ror
    tay
    pla
    ror                                     ; the X-byte's low bit into bit 7
    adc #POINTER_PAGE_FIRST
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
;; Out: A = the page, between <POINTER_PAGE_FIRST> and <POINTER_PAGE_LIMIT>-1, Y = the X-byte
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
    cmp #POINTER_PAGE_FIRST
    bcs Done
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
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
;; Errors: ERRTM = a string condition, ERRSN = neither `THEN` nor <GoTo>
;; See: <Statements::IfTrue>
;; Also: IF (BB13)
.proc If
    lda #1
    sta IfDepth                              ; one `IF` to match
    lda #VALUE_TYPE_ANY
    sta ValueType                              ; any numeric type
    jsr EvaluateExpression
    bit ValueType
    bpl Numeric
    jmp Swap::ToTypeMismatch
Numeric:
    jsr GetCurrentCharacter
    cmp #TOKEN_GOTO
    beq Test
    lda #TOKEN_THEN                             ; `THEN`, an escape token
    jsr RequireTwoByteToken

;; Tests the condition: a long integer by all its bytes, a real by its exponent.
;; Also: OKGOTO (BB13)
Test:
    bit ValueType
    bvc TestReal                            ; not a long integer
    ldx #0
    lda #<(Fac)
    ldy #>(Fac)
    jsr LongInteger::IsZero                              ; zero when all of FAC is
    bvs Branch                              ; always: LORALL leaves the overflow flag from the BIT

;; Tests a real condition: an exponent of 0 is a zero.
;; Also: EXPBYTC (BB13)
TestReal:
    lda FacExponent

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
    lda (TextPointer),Y
    bne CheckToken
    jmp AdvanceTextPointer                               ; the line's end: on to the next line

;; Counts an `IF` or `ELSE` in the scan; at the matching `ELSE`, goes on after it.
;; Also: NOTEOL (BB13)
CheckToken:
    cmp #TOKEN_IF
    beq NestedIf
    cmp #TOKEN_ELSE
    bne FindElse
    dec IfDepth
    bne FindElse                            ; a nested `IF`'s `ELSE`
    jsr AdvanceTextPointer                               ; TXTPTR to the `ELSE`
    jsr GetNextCharacter
    bcc IfTrue::ToGoTo                      ; a line number: `GOTO` it
    bcs IfTrue::ToExecuteStatement

;; Counts a nested `IF`, whose `ELSE` must be passed over.
;; Also: PLSONE (BB13)
NestedIf:
    inc IfDepth
    bcs FindElse                            ; always
.endproc

;; Runs what follows `THEN` or `GOTO`: a line number goes to that line; anything else runs as statements.
;; In: TXTPTR = the `THEN` or <GoTo> token
;; Entry:
;;   ToGoTo = goes to the line number at TXTPTR; <Statements::If> goes here for a line number after `ELSE`
;;   ToExecuteStatement = runs the statement at TXTPTR; <Statements::If> goes here for statements after `ELSE`
;; Also: DOCOND (BB13)
.proc IfTrue
    lda #0
    sta IfDepth
    jsr GetCurrentCharacter
    bcs ToExecuteStatement

;; Goes to the line number at <TextPointer>.
;; Also: DOCOND1 (BB13)
ToGoTo:
    jmp GoTo

;; Runs the statement at <TextPointer>, dropping <NextStatement>'s return address and backing <TextPointer> up so <NextStatement::SavePlace> reads it
;; afresh.
;; Also: DOCO (BB13)
ToExecuteStatement:
    pla
    pla
    jsr BackUpTextPointer
    jmp NextStatement::SavePlace
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; `WINDOW`
; ---------------------------------------------------------------------------------------------------------------------

;; The `WINDOW` statement: `WINDOW x1,y1 TO x2,y2` sets the console's viewport to that rectangle.
;;
;; The corners may come in either order; columns and lines count from 1. The viewport is set with the console's
;; control codes: one to release it to the full screen, one to move the cursor to a column and line, and two to make
;; the cursor's position the viewport's bottom right and top left corners. Last, <Console::SendCodeAndPosition> moves the cursor to the
;; bottom line.
;; In: TXTPTR = past the `WINDOW` token
;; Out: SLEFT, STOPS = the left column and top line, <WindowRight>, SBOTTOM = the right column and bottom line
;; Errors: ERRFC = a number out of a byte's range, ERRSN = a missing comma or TO
;; See: <SendCoordinate>, <Console::SendCodeAndPosition>
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

    jsr EvaluateByte
    stx WindowLeft
    jsr CheckComma
    jsr EvaluateByte
    stx WindowBottom
    lda #TOKEN_TO                               ; TO, an escape token
    jsr RequireTwoByteToken
    jsr EvaluateByte
    stx WindowRight                              ; the right column, despite the name
    cpx WindowLeft
    bcs SortLines
    lda WindowLeft                               ; the larger column on the right
    stx WindowLeft
    sta WindowRight

;; Takes the second line and puts the larger line at the bottom.
;; Also: NOTIN (BB13)
SortLines:
    jsr CheckComma
    jsr EvaluateByte
    stx WindowTop
    cpx WindowBottom
    bcc SetViewport
    lda WindowBottom
    stx WindowBottom
    sta WindowTop

;; Sends the console the codes that set the viewport, then moves the cursor to the bottom line.
;; Also: WINDER (BB13)
SetViewport:
    lda #RESET_VIEWPORT
    jsr WriteConsoleCharacter
    lda #MOVE_CURSOR                        ; the cursor to the bottom right
    jsr WriteConsoleCharacter
    lda WindowRight
    jsr SendCoordinate
    lda WindowBottom
    jsr SendCoordinate
    lda #SET_BOTTOM_RIGHT
    jsr WriteConsoleCharacter
    lda #MOVE_CURSOR                        ; the cursor to the top left
    jsr WriteConsoleCharacter
    lda WindowLeft
    jsr SendCoordinate
    lda WindowTop
    jsr SendCoordinate
    lda #SET_TOP_LEFT
    jsr WriteConsoleCharacter
    ldx WindowBottom
    lda #MOVE_TO_LINE
    jmp Console::SendCodeAndPosition
.endproc

.endscope

;; Sends a column or line counted from 1 to the console as one counted from 0; 0 stays 0.
;; In: A = the column or line
;; See: <WriteConsoleCharacter>
;; Also: DOITOUT (BB13)
.proc SendCoordinate
    sec
    sbc #1
    bcs Send
    lda #0
Send:
    jmp WriteConsoleCharacter
.endproc
