; retrocore: style=strict
;; The Apple III's console under SOS: .CONSOLE, through SOS calls, for the engine
;;
;; It takes the place of the bare Apple III's console.s, which drives the screen itself, as SOS's console driver has
;; the screen and the keyboard, and the character set the bare machine lacks. SOS starts the interpreter at its first
;; byte, so this file, first of the target's, starts with a jump to the code that readies the zero page's pointers and
;; starts the engine. The console reads a line with the
;; driver's echo and editing, in new-line mode, so a READ ends at Return.

; What the engine needs of every platform.

;; The screen's width the engine wraps to: 40 columns, as the transcripts are, on SOS's 80-column console.
SCREEN_COLUMNS = 40

;; The engine's pointer into the game's string it is writing, in the interpreter's zero page, which is all its own.
TextPointer = $06

;; The engine's pointer into one of the game's tables.
TablePointer = $08

;; The engine's pointer to the action it is looking at.
ActionPointer = $0A

;; The engine's pointer to the word or text it is reading.
WordPointer = $0C

.include <environment.inc>

;; The new-line mode NEWLINE turns on: bit 7 set.
NEWLINE_ON = $80

;; The most characters a line <Console::ReadLine> reads holds, with its Return, as the engine's line is: the platform
;; assembles before the engine, so before its INPUT_SIZE is known.
LINE_SIZE = 64

;; The bit that makes a lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; How many times <Console::Pause>'s inner loop runs, which with its outer loop waits about two seconds at the Apple
;; III's 1.8 MHz.
PAUSE_LOOPS = 14

.section CODE

;; The interpreter's first byte, where SOS starts it: on to <Begin>.
.proc Interpreter
    jmp Begin
.endproc

;; Clears the X-bytes of the interpreter's zero-page pointers, which SOS leaves set, so the engine's pointers read the
;; system bank, then starts the engine.
.proc Begin
    lda #0
    tax
NextByte:
    sta EXTEND_PAGE,x
    inx
    bne NextByte
    jmp Engine::Start
.endproc

;; The console the engine writes to and reads from.
.scope Console

.section BSS

;; A while <Write> runs.
SavedA:
    .res 1

;; X while <Write> runs.
SavedX:
    .res 1

;; Y while <Write> runs.
SavedY:
    .res 1

;; The line <ReadLine> reads, with its Return.
Line:
    .res LINE_SIZE

.section DATA

;; .CONSOLE's pathname: its length, then its name.
ConsoleName:
    .byte ConsoleNameEnd - ConsoleName - 1, ".CONSOLE"
ConsoleNameEnd:

;; OPEN's parameters for .CONSOLE.
OpenList:
    .byte OPEN_COUNT
    .word ConsoleName
OpenReference:
    .byte 0
    .word 0
    .byte 0

;; NEWLINE's parameters: on, at Return.
NewlineList:
    .byte NEWLINE_COUNT
NewlineReference:
    .byte 0
    .byte NEWLINE_ON, CONSOLE_RETURN

;; WRITE's parameters, for one character.
WriteList:
    .byte WRITE_COUNT
WriteReference:
    .byte 0
    .word WriteCharacter
    .word 1

;; The character <Write> writes.
WriteCharacter:
    .byte 0

;; READ's parameters, for a line.
ReadList:
    .byte READ_COUNT
ReadReference:
    .byte 0
    .word Line
    .word LINE_SIZE
ReadLength:
    .word 0

.section CODE

;; Opens .CONSOLE, puts its reference number in each call's parameters, turns new-line mode on, and clears the screen.
.proc Start
    SosCall OPEN_CALL, OpenList
    bne Failed
    lda OpenReference
    sta NewlineReference
    sta WriteReference
    sta ReadReference
    SosCall NEWLINE_CALL, NewlineList
    jmp Clear
Failed:
    jmp Finish
.endproc

;; Writes a character, a Return for a new line.
;; In: A = the character, <NEW_LINE> for a new line
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    stx SavedX
    sty SavedY
    cmp #NEW_LINE
    bne Character
    lda #CONSOLE_RETURN
Character:
    sta WriteCharacter
    SosCall WRITE_CALL, WriteList
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0. The driver shows it as it is typed, its Return ending the
;; screen's line.
.proc ReadLine
    SosCall READ_CALL, ReadList
    ldx ReadLength

    ; The line ends at its Return, or at the count; the engine takes at most INPUT_SIZE - 1.
    beq Done
    dex
    lda Line,x
    cmp #CONSOLE_RETURN
    beq Fits
    inx
Fits:
    cpx #INPUT_SIZE
    bcc Copy
    ldx #INPUT_SIZE - 1
Copy:
    stx SavedX
    ldy #0
NextCharacter:
    cpy SavedX
    beq Done
    lda Line,y
    jsr Capital
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

;; Clears the screen with the console's control code.
.proc Clear
    lda #CONSOLE_CLEAR
    sta WriteCharacter
    SosCall WRITE_CALL, WriteList
    rts
.endproc

;; Waits about two seconds.
.proc Pause
    ldy #PAUSE_LOOPS
Outer:
    ldx #0
Middle:
    lda #0
Inner:
    sec
    sbc #1
    bne Inner
    dex
    bne Middle
    dey
    bne Outer
    rts
.endproc

;; Stops at the end of the game. It never returns.
.proc Finish
    jmp Finish
.endproc

.endscope
