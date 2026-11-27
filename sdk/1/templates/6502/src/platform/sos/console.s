; retrocore: style=strict
;; The Apple III's console under SOS: .CONSOLE, through SOS calls
;;
;; SOS's console driver has the screen, and the character set the bare Apple III lacks, so the console is the
;; environment's, in `src/platform/sos/`, rather than the machine's. SOS starts the interpreter at its first byte, so
;; this file, the first the target assembles, starts with a jump to the program's entry. The console shows lowercase
;; letters, so the target sets `LOWERCASE` to 1.

.include <environment.inc>

.section CODE

;; The interpreter's first byte, where SOS starts it: on to the program's entry, <Main>.
.proc Interpreter
    jmp Main
.endproc

;; The console the program writes to.
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

;; WRITE's parameters, for a new line.
NewLineList:
    .byte WRITE_COUNT
NewLineReference:
    .byte 0
    .word NewLineCharacters
    .word NewLineEnd - NewLineCharacters

;; A new line on the console, whose automatic line feed is off: a Return, then a line feed.
NewLineCharacters:
    .byte CONSOLE_RETURN, CONSOLE_LINE_FEED
NewLineEnd:

.section CODE

;; Opens .CONSOLE and puts its reference number in each call's parameters. If it cannot be opened, the program
;; stops there, as it has nowhere to write.
.proc Start
    SosCall OPEN_CALL, OpenList
    bne Failed
    lda OpenReference
    sta WriteReference
    sta NewLineReference
    rts
Failed:
    jmp Failed
.endproc

;; Writes a character.
;; In: A = the character, in ASCII
;; Keeps: A, X, Y
.proc Write
    sta SavedA
    stx SavedX
    sty SavedY
    sta WriteCharacter
    SosCall WRITE_CALL, WriteList
    lda SavedA
    ldx SavedX
    ldy SavedY
    rts
.endproc

;; Ends the line.
;; Keeps: X, Y
.proc NewLine
    stx SavedX
    sty SavedY
    SosCall WRITE_CALL, NewLineList
    ldx SavedX
    ldy SavedY
    rts
.endproc

.endscope
