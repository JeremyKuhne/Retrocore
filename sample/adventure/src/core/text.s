; retrocore: style=strict
;; The printer: the engine's text, wrapped to the screen's width, and the game's compressed strings
;;
;; Everything the engine shows goes through <Printer::Write>, a character at a time, and on to the platform's
;; <Console::Write>. A word waits until the space or new line after it, so it can go on the next line when it doesn't
;; fit on this one, and spaces wait until the word after them, so no line ends in one. A line holds at most
;; <LINE_WIDTH> characters, a column fewer than the screen, so no line fills the screen's width and makes the machine
;; wrap it a second time. `tools/WrappedOutput.cs` wraps the same way, so the reference engine's transcripts match.
;;
;; The game's strings are compressed: a byte below <FIRST_TOKEN> is a character, and one from it up is an entry of the
;; game's dictionary, which <Printer::WriteEntry> expands.

;; The character that ends a line, in the engine's text and the game's.
NEW_LINE = $0A

;; The byte that ends each of the game's strings, and each of the engine's.
STRING_END = 0

;; The first byte that stands for a dictionary entry: entry 0 is this byte, entry 1 the next, and so on to $FF.
FIRST_TOKEN = $80

;; The widest a line is.
LINE_WIDTH = SCREEN_COLUMNS - 1

;; Prints one of the engine's own strings, through <Printer::WriteText>.
;; Parameters:
;;   text = the string, ending in <STRING_END>
.macro Print text
    lda #<text
    ldy #>text
    jsr Printer::WriteText
.endmacro

;; Writing text to the console.
.scope Printer

.section BSS

;; The column the next character sent goes in.
Column:
    .res 1

;; The spaces waiting to go before the next word, at most <LINE_WIDTH>.
Spaces:
    .res 1

;; How many letters of <Word> are waiting.
Waiting:
    .res 1

;; The letters of the word waiting to be sent.
Word:
    .res LINE_WIDTH

;; X while <Write> runs.
SavedX:
    .res 1

;; Y while <Write> runs.
SavedY:
    .res 1

;; The number <WriteNumber> is writing.
Number:
    .res 2

;; Set once <WriteNumber> has written a digit.
Started:
    .res 1

.section CODE

;; Writes a character, holding a word back until the space or new line after it shows where its line ends.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: X, Y
.proc Write
    stx SavedX
    sty SavedY
    cmp #NEW_LINE
    beq NewLine
    cmp #' '
    beq Space

    ; A letter waits with the rest of its word; a word as wide as a line goes at once.
    ldx Waiting
    sta Word,x
    inx
    stx Waiting
    cpx #LINE_WIDTH
    bne Done
    jsr SendWord
    jmp Done

NewLine:
    jsr SendWord
    lda #0
    sta Spaces
    lda #NEW_LINE
    jsr Send
    jmp Done

Space:
    jsr SendWord
    lda Spaces
    cmp #LINE_WIDTH
    bcs Done
    inc Spaces
Done:
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Sends the waiting word after the spaces before it, or on a new line without them when they don't fit on this one.
;; Keeps: X
.proc SendWord
    lda Waiting
    beq Done

    ; Does the word fit after the spaces? The line's start always takes it.
    lda Column
    beq Fits
    clc
    adc Spaces
    adc Waiting
    cmp #LINE_WIDTH + 1
    bcc Fits
    lda #0
    sta Spaces
    lda #NEW_LINE
    jsr Send
Fits:
    jsr SendSpaces

    ; Then its letters.
    ldy #0
NextLetter:
    lda Word,y
    jsr Send
    iny
    cpy Waiting
    bne NextLetter
    lda #0
    sta Waiting
Done:
    rts
.endproc

;; Sends the waiting spaces.
;; Keeps: X
.proc SendSpaces
    lda Spaces
    beq Done
    lda #' '
    jsr Send
    dec Spaces
    jmp SendSpaces
Done:
    rts
.endproc

;; Sends a character to the console, and moves <Column> on.
;; In: A = the character
;; Keeps: A, X, Y
.proc Send
    jsr Console::Write
    cmp #NEW_LINE
    beq LineStart
    inc Column
    rts
LineStart:
    pha
    lda #0
    sta Column
    pla
    rts
.endproc

;; Sends the word and the spaces waiting, before the engine reads a line.
;; Keeps: X
.proc Flush
    jsr SendWord
    jmp SendSpaces
.endproc

;; Ends the line, unless nothing has been written on it, dropping the spaces waiting.
;; Keeps: X
.proc EndLine
    jsr SendWord
    lda #0
    sta Spaces
    lda Column
    beq Done
    lda #NEW_LINE
    jmp Send
Done:
    rts
.endproc

;; Sends what is waiting and notes that the cursor is at a line's start, after a line typed in or a cleared screen.
;; Keeps: X
.proc AtLineStart
    jsr Flush
    lda #0
    sta Column
    rts
.endproc

;; Writes one of the engine's own strings.
;; In: A = the string's address (low), Y = the string's address (high)
;; Keeps: X
.proc WriteText
    sta WordPointer
    sty WordPointer + 1
    ldy #0
NextCharacter:
    lda (WordPointer),y
    beq Done
    jsr Write
    iny
    bne NextCharacter
Done:
    rts
.endproc

;; Writes one of the game's strings, expanding its dictionary entries.
;; In: A = the string's number in its table,
;;   X = the table, <Tables::ROOM_TEXTS>, <Tables::MESSAGES> or <Tables::ITEM_TEXTS>
.proc WriteString
    pha
    lda TableAddress,x
    sta TextPointer
    lda TableAddress + 1,x
    sta TextPointer + 1
    pla
    tax

    ; Pass the strings before it.
    beq NextByte
SkipString:
    jsr ReadByte
    bne SkipString
    dex
    bne SkipString

    ; Then write it.
NextByte:
    jsr ReadByte
    beq Done
    cmp #FIRST_TOKEN
    bcs Entry
    jsr Write
    jmp NextByte
Entry:
    jsr WriteEntry
    jmp NextByte
Done:
    rts
.endproc

;; Reads the byte at <TextPointer> and moves past it.
;; Out: A = the byte, zero = set at a string's end
;; Keeps: X
.proc ReadByte
    ldy #0
    lda (TextPointer),y
    inc TextPointer
    bne Read
    inc TextPointer + 1
Read:
    cmp #STRING_END
    rts
.endproc

;; Writes a dictionary entry's characters.
;; In: A = the byte that stands for it, <FIRST_TOKEN> or more
.proc WriteEntry
    sec
    sbc #FIRST_TOKEN
    tax

    ; The entries start after the dictionary's count.
    clc
    lda TableAddress + Tables::DICTIONARY
    adc #1
    sta TablePointer
    lda TableAddress + Tables::DICTIONARY + 1
    adc #0
    sta TablePointer + 1

    ; Pass the entries before it: each is its length, then that many characters.
    ldy #0
    txa
    beq Found
SkipEntry:
    lda (TablePointer),y
    sec
    adc TablePointer
    sta TablePointer
    bcc Skipped
    inc TablePointer + 1
Skipped:
    dex
    bne SkipEntry

    ; Then write its characters.
Found:
    lda (TablePointer),y
    tax
NextCharacter:
    iny
    lda (TablePointer),y
    jsr Write
    dex
    bne NextCharacter
    rts
.endproc

;; Writes one of the game's messages and ends its line.
;; In: A = the message's number
.proc WriteMessage
    ldx #Tables::MESSAGES
    jsr WriteString
    lda #NEW_LINE
    jmp Write
.endproc

;; Writes a number in decimal, with a minus sign when it is negative.
;; In: A = the number (low), X = the number (high), a signed 16-bit number
.proc WriteNumber
    sta Number
    stx Number + 1
    txa
    bpl Positive

    ; A negative number is its minus sign and its magnitude, which fits 16 bits unsigned.
    lda #'-'
    jsr Write
    sec
    lda #0
    sbc Number
    sta Number
    lda #0
    sbc Number + 1
    sta Number + 1
Positive:
    lda #0
    sta Started

    ; Each power of ten, from the largest, gives a digit: how many times it can be taken away.
    ldx #0
NextPower:
    ldy #'0'
TakeAway:
    sec
    lda Number
    sbc Powers,x
    pha
    lda Number + 1
    sbc Powers + 1,x
    bcc Digit
    sta Number + 1
    pla
    sta Number
    iny
    jmp TakeAway
Digit:
    pla

    ; Leading zeros are left out, but the units digit is always written.
    tya
    cmp #'0'
    bne WriteDigit
    lda Started
    bne WriteZero
    cpx #(POWER_COUNT - 1) * 2
    bne NextDigit
WriteZero:
    tya
WriteDigit:
    jsr Write
    lda #1
    sta Started
NextDigit:
    inx
    inx
    cpx #POWER_COUNT * 2
    bne NextPower
    rts

;; The powers of ten a 16-bit number has digits for, from the largest.
Powers:
    .word 10000, 1000, 100, 10, 1

;; The number of <Powers>.
POWER_COUNT = 5
.assert * - Powers = POWER_COUNT * 2, "Powers holds POWER_COUNT words."
.endproc

.endscope
