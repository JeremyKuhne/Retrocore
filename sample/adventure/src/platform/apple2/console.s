; retrocore: style=strict
;; The Apple II's console: the Monitor's screen output and line input, for the engine
;;
;; Each machine's platform folder gives the engine the same things: the screen's width, four zero-page pointers, and
;; the routines of the <Console> scope. The engine itself uses no machine's addresses. This one runs on any Apple II,
;; from the Monitor's routines alone, with no DOS or BASIC needed, so it serves a bare machine and a DOS one alike.

; What the engine needs of every platform.

;; The screen's width, which the engine wraps its text to.
SCREEN_COLUMNS = 40

;; The engine's pointer into the game's string it is writing. The pointers are in bytes neither the Monitor nor
;; DOS 3.3 uses. AppleSoft keeps its number conversion vectors, for USR routines, in $06-$09, which the engine
;; may take as it never returns to BASIC.
TextPointer = $06

;; The engine's pointer into one of the game's tables.
TablePointer = $08

;; The engine's pointer to the action it is looking at.
ActionPointer = $FA

;; The engine's pointer to the word or text it is reading.
WordPointer = $FC

; The Monitor's routines and locations the console uses.

;; Inherit: <Monitor:CharacterOut>
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

;; Inherit: <Monitor:GetLine::NoPrompt>
;; Also: GETLN1 (A2RM79, IIETRM85)
GetLineNoPrompt = $FD6F

;; Inherit: <Monitor:InitDisplay>
;; Also: INIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
InitDisplay = $FB2F

;; Inherit: <Monitor:SetNormal>
;; Also: SETNORM (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetNormal = $FE84

;; Inherit: <Monitor:SetKeyboard>
;; Also: SETKBD (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetKeyboard = $FE89

;; Inherit: <Monitor:SetScreen>
;; Also: SETVID (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetScreen = $FE93

;; Inherit: <Monitor:Home>
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
Home = $FC58

;; Inherit: <Monitor:Delay>
;; Also: WAIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
Delay = $FCA8

;; The line <GetLineNoPrompt> reads, each character with its high bit set, ending in a Return.
;; Also: IN (A2RM78, A2RM79, IIEROM82, IIETRM85)
InputBuffer = $0200

;; The character <GetLineNoPrompt> shows again after a line is cancelled, with Control-X or a backspace at its start.
;; Also: PROMPT (A2RM78, A2RM79, IIEROM82, IIETRM85)
PromptCharacter = $33

; Characters.

;; A Return, with its high bit set, as the screen takes it.
RETURN = $8D

;; The high bit the Apple II's screen and keyboard give characters.
HIGH_BIT = $80

;; The engine's prompt, as the Monitor shows it, with its high bit set.
ENGINE_PROMPT = '>' | HIGH_BIT

;; The bit that makes a lowercase letter a capital when cleared.
LOWERCASE_BIT = $20

;; The <Delay> count of the longest wait, about a sixth of a second.
LONGEST_DELAY = 0

;; How many of the longest waits <Console::Pause> makes, about two seconds.
PAUSE_DELAYS = 12

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

;; The waits <Pause> has left.
Waits:
    .res 1

.section CODE

;; Sets up the screen and keyboard: text mode, the whole screen as the window, normal text, the Monitor's own
;; screen and keyboard routines, and a clear screen.
.proc Start
    ; The Monitor shows its prompt character again when a line is cancelled, so it is the engine's.
    lda #ENGINE_PROMPT
    sta PromptCharacter
    jsr InitDisplay
    jsr SetNormal
    jsr SetKeyboard
    jsr SetScreen
    jmp Home
.endproc

;; Writes a character on the screen, in capitals, as the Apple II and II Plus show no lowercase.
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
    ora #HIGH_BIT
Show:
    jsr CharacterOut
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Reads a line into <InputLine>, in capitals, ending in 0. The Monitor shows it as it is typed, and ends the
;; screen's line after it.
.proc ReadLine
    jsr GetLineNoPrompt

    ; The line's length is in X, with its Return at InputBuffer,X; the engine takes at most INPUT_SIZE - 1.
    cpx #INPUT_SIZE
    bcc Fits
    ldx #INPUT_SIZE - 1
Fits:
    stx SavedX
    ldy #0
NextCharacter:
    cpy SavedX
    beq Done
    lda InputBuffer,y
    and #$FF - HIGH_BIT
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

;; Clears the screen.
.proc Clear
    jmp Home
.endproc

;; Waits about two seconds.
.proc Pause
    lda #PAUSE_DELAYS
    sta Waits
NextWait:
    lda #LONGEST_DELAY
    jsr Delay
    dec Waits
    bne NextWait
    rts
.endproc

;; Stops at the end of the game. It never returns: the machine's Reset key leaves it.
.proc Finish
    jmp Finish
.endproc

.endscope
