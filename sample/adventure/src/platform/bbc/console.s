; retrocore: style=strict
;; The BBC Micro's console: the MOS's character output and line input, for the engine
;;
;; Each machine's platform folder gives the engine the same things: the screen's width, four zero-page pointers, and
;; the routines of the <Console> scope. This one runs on the model A or B in the mode the MOS starts in, MODE 7, from
;; the MOS's calls alone: <OSWRCH> writes, <OSWORD> 0 reads a line, and <OSBYTE> waits. MODE 7 shows lowercase, so
;; the engine's text keeps its case; the line typed is read in capitals.

; What the engine needs of every platform.

;; The screen's width, the SDK's: MODE 7's 40 columns. The engine's lines are a column narrower, so none fills a row.
SCREEN_COLUMNS = RC_SCREEN_COLUMNS

;; The engine's pointer into the game's string it is writing. The four pointers are in $70-$77, of the bytes
;; $70-$8F the MOS leaves to the user's programs.
TextPointer = $70

;; The engine's pointer into one of the game's tables.
TablePointer = $72

;; The engine's pointer to the action it is looking at.
ActionPointer = $74

;; The engine's pointer to the word or text it is reading.
WordPointer = $76

; The MOS's calls and locations.

.include <machine.inc>

; The MOS's codes.

;; The <OSWORD> call that reads a line.
OSWORD_READ_LINE = 0

;; The <OSBYTE> call that waits for the start of the next frame, a fiftieth of a second.
OSBYTE_WAIT_FOR_VSYNC = $13

;; The <OSBYTE> call that acknowledges an Escape.
OSBYTE_ACKNOWLEDGE_ESCAPE = $7E

;; The VDU code that clears the text window and homes the cursor.
VDU_CLEAR = 12

;; The lowest character <OSWORD> 0 keeps in the line: a space.
FIRST_CHARACTER = ' '

;; The highest character <OSWORD> 0 keeps in the line.
LAST_CHARACTER = '~'

;; The bit that makes a lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; The frames <Console::Pause> waits, two seconds at 50 a second.
PAUSE_FRAMES = 100

;; The console the engine writes to and reads from.
.scope Console

.section BSS

;; X while <Write> runs.
SavedX:
    .res 1

;; Y while <Write> runs.
SavedY:
    .res 1

;; A while <Write> runs.
SavedA:
    .res 1

;; The frames <Pause> has left.
Frames:
    .res 1

.section RODATA

;; <OSWORD> 0's parameter block: where the line goes, its longest length, and the characters it keeps.
LineBlock:
    .word InputLine
    .byte INPUT_SIZE - 1, FIRST_CHARACTER, LAST_CHARACTER

.section CODE

;; Sets up the screen: clears it.
.proc Start
    jmp Clear
.endproc

;; Writes a character on the screen.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    stx SavedX
    sty SavedY
    cmp #NEW_LINE
    bne Character
    jsr OSNEWL
    jmp Restore
Character:
    jsr OSWRCH
Restore:
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0. The MOS shows it as it is typed, and ends the screen's
;; line after it. An Escape gives an empty line.
.proc ReadLine
    lda #OSWORD_READ_LINE
    ldx #<LineBlock
    ldy #>LineBlock
    jsr OSWORD
    bcc Typed

    ; Escape: the MOS wants it acknowledged, and the line is empty.
    lda #OSBYTE_ACKNOWLEDGE_ESCAPE
    jsr OSBYTE
    jsr OSNEWL
    ldy #0
Typed:
    ; Y is the line's length, with its Return after it.
    lda #0
    sta InputLine,y
NextCharacter:
    dey
    bmi Done
    lda InputLine,y
    cmp #'a'
    bcc NextCharacter
    cmp #'z' + 1
    bcs NextCharacter
    and #$FF - LOWERCASE_BIT
    sta InputLine,y
    bcc NextCharacter
Done:
    rts
.endproc

;; Clears the screen.
.proc Clear
    lda #VDU_CLEAR
    jmp OSWRCH
.endproc

;; Waits about two seconds.
.proc Pause
    lda #PAUSE_FRAMES
    sta Frames
NextFrame:
    lda #OSBYTE_WAIT_FOR_VSYNC
    jsr OSBYTE
    dec Frames
    bne NextFrame
    rts
.endproc

;; Stops at the end of the game. It never returns: Break leaves it.
.proc Finish
    jmp Finish
.endproc

.endscope
