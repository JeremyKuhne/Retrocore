; retrocore: style=strict
;; The Apple-1's console: the Woz Monitor's character output and the PIA's keyboard, for the engine
;;
;; Each machine's platform folder gives the engine the same things: the screen's width, four zero-page pointers, and
;; the routines of the <Console> scope. This one runs on an Apple-1 with 32K, from the Woz Monitor's ROM alone. The
;; terminal shows capitals only and has no cursor keys, so the engine's text shows in capitals, a line is read from
;; the keyboard here, and the Apple-1's rubout, the underscore, takes back a character.

; What the engine needs of every platform.

;; The screen's width, the SDK's: the terminal's 40 columns. The engine's lines are a column narrower, so none fills
;; a row.
SCREEN_COLUMNS = RC_SCREEN_COLUMNS

;; The engine's pointer into the game's string it is writing. The four pointers are in $06-$0D, below the Woz
;; Monitor's page-zero bytes at $24-$2B.
TextPointer = $06

;; The engine's pointer into one of the game's tables.
TablePointer = $08

;; The engine's pointer to the action it is looking at.
ActionPointer = $0A

;; The engine's pointer to the word or text it is reading.
WordPointer = $0C

; The Woz Monitor's routines and the PIA.

.include <machine.inc>

; Characters, with bit 7 set as the terminal and keyboard take and give them.

;; A Return.
RETURN = $8D

;; The Apple-1's rubout, an underscore, which takes back the last character typed.
RUBOUT = $DF

;; The high bit the terminal and keyboard give characters, <KEY_BIT>.
HIGH_BIT = KEY_BIT

;; The bit that makes a lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; The loops of 256 times 256 <Console::Pause> makes: each takes about 0.33 seconds at the Apple-1's 1 MHz.
PAUSE_LOOPS = 6

;; The console the engine writes to and reads from.
.scope Console

.section BSS

;; A while <Write> runs.
SavedA:
    .res 1

;; The loops <Pause> has left.
Loops:
    .res 1

.section CODE

;; Sets up the terminal: starts on a new line.
.proc Start
    lda #RETURN
    jmp CharacterOut
.endproc

;; Writes a character on the terminal, in capitals.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    cmp #NEW_LINE
    bne Character
    lda #RETURN
    bne Show
Character:
    jsr Capital
    ora #HIGH_BIT
Show:
    jsr CharacterOut
    lda SavedA
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0, showing each key as it is typed and a new line after it.
.proc ReadLine
    ldy #0
NextKey:
    lda KeyboardControl
    bpl NextKey
    lda Keyboard
    cmp #RETURN
    beq Done
    cmp #RUBOUT
    bne Key

    ; A rubout takes back the last character; the terminal shows the underscore.
    cpy #0
    beq NextKey
    jsr CharacterOut
    dey
    jmp NextKey
Key:
    ; The engine takes at most INPUT_SIZE - 1 characters; a full line takes no more.
    cpy #INPUT_SIZE - 1
    bcs NextKey
    jsr CharacterOut
    and #$FF - HIGH_BIT
    jsr Capital
    sta InputLine,y
    iny
    bne NextKey
Done:
    jsr CharacterOut
    lda #0
    sta InputLine,y
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

;; Clears the screen: the terminal has no clear, so a screen of new lines scrolls the text away.
.proc Clear
    ldx #RC_SCREEN_ROWS
NextLine:
    lda #RETURN
    jsr CharacterOut
    dex
    bne NextLine
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

;; Returns to the Woz Monitor at the end of the game.
.proc Finish
    jmp MonitorCommandLine
.endproc

.endscope
