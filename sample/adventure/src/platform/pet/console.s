; retrocore: style=strict
;; The PET's console: the kernal's screen output and line input, for the engine
;;
;; Each machine's platform folder gives the engine the same things: the screen's width, four zero-page pointers, and
;; the routines of the <Console> scope. This one runs on any PET, from the kernal's jump table alone. The screen
;; shows PETSCII, whose letters from $41 to $5A are capitals, so the engine's text shows in capitals, and the screen
;; editor reads a line as BASIC's INPUT does.

; What the engine needs of every platform.

;; The screen's width, the SDK's: 40 columns. The engine's lines are a column narrower, so none fills a row.
SCREEN_COLUMNS = RC_SCREEN_COLUMNS

;; The engine's pointer into the game's string it is writing. The four pointers are in BASIC's floating-point work
;; bytes, $54-$5B, which the kernal and the screen editor leave alone; the engine never returns to BASIC.
TextPointer = $54

;; The engine's pointer into one of the game's tables.
TablePointer = $56

;; The engine's pointer to the action it is looking at.
ActionPointer = $58

;; The engine's pointer to the word or text it is reading.
WordPointer = $5A

; The kernal's routines and the PET's hardware.

.include <machine.inc>

; Characters.

;; A Return, which ends a line on the screen and one the editor reads.
RETURN = $0D

;; The bit that makes an ASCII lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; The bit PETSCII adds to a letter typed with SHIFT: shifted A is $C1.
SHIFT_BIT = $80

;; The loops of 256 times 256 <Console::Pause> makes: each takes about 0.33 seconds at the PET's 1 MHz.
PAUSE_LOOPS = 6

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

;; The loops <Pause> has left.
Loops:
    .res 1

.section CODE

;; Sets up the screen: clears it.
.proc Start
    jmp Clear
.endproc

;; Writes a character on the screen, in capitals.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    stx SavedX
    sty SavedY
    cmp #NEW_LINE
    bne Character
    lda #RETURN
    bne Show
Character:
    jsr Capital
Show:
    jsr KernalCharacterOut
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0. The screen editor shows it as it is typed, and moves to
;; the next line after it.
.proc ReadLine
    ldy #0
NextCharacter:
    sty SavedY
    jsr KernalCharacterIn
    ldy SavedY
    cmp #RETURN
    beq Done

    ; A shifted letter is PETSCII's capital with the shift bit; the engine takes at most INPUT_SIZE - 1.
    and #$FF - SHIFT_BIT
    jsr Capital
    cpy #INPUT_SIZE - 1
    bcs NextCharacter
    sta InputLine,y
    iny
    bne NextCharacter
Done:
    lda #0
    sta InputLine,y
    rts
.endproc

;; Makes a lowercase letter a capital.
;; In: A = the character
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

;; Clears the screen.
.proc Clear
    lda #CLEAR_SCREEN
    jmp KernalCharacterOut
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

;; Stops at the end of the game. It never returns.
.proc Finish
    jmp Finish
.endproc

.endscope
