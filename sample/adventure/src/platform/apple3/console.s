; retrocore: style=strict
;; The Apple III's console: its own text screen and keyboard routines, for the engine
;;
;; Each machine's platform folder gives the engine the same things: the screen's width, four zero-page pointers, and
;; the routines of the <Console> scope. The Apple III's boot ROM has no routines for a program to call, so this one
;; writes text page 1 and reads the keyboard itself, in 40-column text. The screen shows the character set in RAM,
;; which SOS loads as it boots: a bare program shows its text once a character set is there. Where the text shows in
;; colour, page 2 holds each character's colours, which <Console::Clear> sets to white on black; scrolling moves only
;; the characters, as every row's colours are the same.

; What the engine needs of every platform.

;; The screen's width, the SDK's: 40 columns. The engine's lines are a column narrower, so none fills a row.
SCREEN_COLUMNS = RC_SCREEN_COLUMNS

;; The engine's pointer into the game's string it is writing. The four pointers, and the console's own two, are in
;; $06-$11 of page zero.
TextPointer = $06

;; The engine's pointer into one of the game's tables.
TablePointer = $08

;; The engine's pointer to the action it is looking at.
ActionPointer = $0A

;; The engine's pointer to the word or text it is reading.
WordPointer = $0C

;; The console's pointer to the screen row it is writing.
RowPointer = $0E

;; The console's pointer to the row it is scrolling up into <RowPointer>'s, or to the colours of the row it clears.
ScrollPointer = $10

; The Apple III's hardware.

.include <machine.inc>

;; Clears the video's page 2 switch, so the screen shows text page 1.
Page1Switch = $C054

;; Clears the video's hi-res switch, so text shows rather than graphics.
TextSwitch = $C056

; Characters.

;; A Return, as the keyboard gives it without its high bit.
RETURN = $0D

;; The keyboard's left arrow, which takes back the last character typed.
LEFT_ARROW = $08

;; The bit the keyboard sets on a waiting key, and that makes a character on the screen show normally.
HIGH_BIT = $80

;; A space, as the screen shows it.
SCREEN_SPACE = ' ' | HIGH_BIT

;; How far a row's colours on text page 2 are from its characters on page 1.
COLOR_PAGE_OFFSET = $0400

;; A character's colours where 40-column text shows in colour, as it does with VIA 1's PA6 set: white on black.
WHITE_ON_BLACK = $F0

;; The bit that makes a lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; The loops of 256 times 256 <Console::Pause> makes: each takes about 0.33 seconds at 1 MHz.
PAUSE_LOOPS = 6

;; The console the engine writes to and reads from.
.scope Console

.section BSS

;; The column the next character goes in.
Column:
    .res 1

;; The row the next character goes in.
Row:
    .res 1

;; X while <Write> runs.
SavedX:
    .res 1

;; Y while <Write> runs.
SavedY:
    .res 1

;; A while <Write> runs.
SavedA:
    .res 1

;; The loops <Pause> has left.
Loops:
    .res 1

.section RODATA

;; The low byte of each text row's first address: rows 0-7, 8-15 and 16-23 each step $80, and the three groups $28.
RowLow:
.repeat RC_SCREEN_ROWS, row
    .byte <(TextPage + ((row .mod 8) * $80) + ((row / 8) * SCREEN_COLUMNS))
.endrepeat

;; The high byte of each text row's first address.
RowHigh:
.repeat RC_SCREEN_ROWS, row
    .byte >(TextPage + ((row .mod 8) * $80) + ((row / 8) * SCREEN_COLUMNS))
.endrepeat

.section CODE

;; Sets up the screen: 40-column text from page 1, cleared, white on black whether it shows in colour or not.
.proc Start
    lda TXTMD
    lda COL40SW
    lda Page1Switch
    lda TextSwitch
    jmp Clear
.endproc

;; Writes a character on the screen, in capitals, as the screen's character set may have no lowercase.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    stx SavedX
    sty SavedY
    cmp #NEW_LINE
    beq NewLine
    jsr Capital
    ora #HIGH_BIT
    ldy Column
    sta (RowPointer),y
    iny
    sty Column
    cpy #SCREEN_COLUMNS
    bcc Restore
NewLine:
    jsr NextRow
Restore:
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0, showing each key as it is typed and a new line after it.
.proc ReadLine
    ldx #0
NextKey:
    lda KBD
    bpl NextKey
    sta KBDSTRB
    and #$FF - HIGH_BIT
    cmp #RETURN
    beq Done
    cmp #LEFT_ARROW
    bne Key

    ; The left arrow takes back the last character, and its place on the screen; not past the start of a row the
    ; line has wrapped onto.
    cpx #0
    beq NextKey
    lda Column
    beq NextKey
    dex
    dec Column
    ldy Column
    lda #SCREEN_SPACE
    sta (RowPointer),y
    jmp NextKey
Key:
    ; The engine takes at most INPUT_SIZE - 1 characters; a full line takes no more.
    cpx #INPUT_SIZE - 1
    bcs NextKey
    jsr Capital
    sta InputLine,x
    inx
    jsr Write
    jmp NextKey
Done:
    lda #0
    sta InputLine,x

    ; A line that just filled its row has already moved to the next.
    lda Column
    beq Ended
    jmp NextRow
Ended:
    rts
.endproc

;; Makes a lowercase letter a capital.
;; In: A = the character, without its high bit
;; Out: A = the character, as a capital if it was a lowercase letter
;; Keeps: X, Y
.proc Capital
    cmp #'a'
    bcc Done
    cmp #'z' + 1
    bcs Done
    and #$FF - LOWERCASE_BIT
Done:
    rts
.endproc

;; Clears the screen and starts at its top left.
.proc Clear
    ldx #RC_SCREEN_ROWS - 1
NextCleared:
    jsr ClearRow
    dex
    bpl NextCleared
    lda #0
    sta Row
    jmp SetRow
.endproc

;; Moves to the start of the next row, scrolling the screen up a row from the last.
.proc NextRow
    lda Row
    cmp #RC_SCREEN_ROWS - 1
    bcs Scroll
    inc Row
    jmp SetRow
Scroll:
    ; Each row takes the one below it, and the last is cleared.
    ldx #0
NextScrolled:
    lda RowLow + 1,x
    sta ScrollPointer
    lda RowHigh + 1,x
    sta ScrollPointer + 1
    jsr PointAtRow
    ldy #SCREEN_COLUMNS - 1
NextCharacter:
    lda (ScrollPointer),y
    sta (RowPointer),y
    dey
    bpl NextCharacter
    inx
    cpx #RC_SCREEN_ROWS - 1
    bcc NextScrolled
    jsr ClearRow
    jmp SetRow
.endproc

;; Points <RowPointer> at the start of <Row>, at its first column.
.proc SetRow
    lda #0
    sta Column
    ldx Row
    jmp PointAtRow
.endproc

;; Points <RowPointer> at a row.
;; In: X = the row
;; Keeps: X, Y
.proc PointAtRow
    lda RowLow,x
    sta RowPointer
    lda RowHigh,x
    sta RowPointer + 1
    rts
.endproc

;; Fills a row with spaces, white on black.
;; In: X = the row
;; Keeps: X
.proc ClearRow
    jsr PointAtRow
    lda RowPointer
    sta ScrollPointer
    lda RowPointer + 1
    clc
    adc #>COLOR_PAGE_OFFSET
    sta ScrollPointer + 1
    ldy #SCREEN_COLUMNS - 1
NextColumn:
    lda #SCREEN_SPACE
    sta (RowPointer),y
    lda #WHITE_ON_BLACK
    sta (ScrollPointer),y
    dey
    bpl NextColumn
    rts
.endproc

;; Waits about two seconds.
.proc Pause
    lda #PAUSE_LOOPS
    sta Loops
    ldx #0
    ldy #0
NextLoop:
    dey
    bne NextLoop
    dex
    bne NextLoop
    dec Loops
    bne NextLoop
    rts
.endproc

;; Stops at the end of the game. It never returns: the machine's Reset key leaves it.
.proc Finish
    jmp Finish
.endproc

.endscope
