; retrocore: style=strict
;; The console: polling the keyboard or the console's card into the type-ahead buffer, and the BIOS's console init
;; and read calls.

; Keys ConsoleCheck acts on.

;; The bits of a key's ASCII code, without bit 7.
ASCII_BITS = $7F

; The console's keys in SYSCOM, which ConsoleCheck reads through SyscomPointer.

;; The offset in SYSCOM of the flush key, which switches <ConsoleFlags>' <CONSOLE_FLUSHED> on or off.
;; Also: CRTINFO_FLUSH (A2POSRM, UCSD20)
SYSCOM_FLUSH_KEY = $53

;; The offset in SYSCOM of the break key, which runs the break handler.
;; Also: CRTINFO_BREAK (A2POSRM, UCSD20)
SYSCOM_BREAK_KEY = $54

;; The offset in SYSCOM of the stop key, which switches <ConsoleFlags>' <CONSOLE_STOPPED> on or off.
;; Also: CRTINFO_STOP (A2POSRM, UCSD20)
SYSCOM_STOP_KEY = $55

; ConsoleFlags' bits.

;; Output is stopped: <ConsoleCheck> waits for the stop key again.
CONSOLE_STOPPED = $80

;; Output is flushed: <ConsoleWrite> drops it.
CONSOLE_FLUSHED = $40

;; The view follows the cursor.
CONSOLE_FOLLOW = $01

; Type-ahead and the firmware.

;; The places in <TypeAhead>. It holds one key fewer: <ConsoleCheck> counts it full with one place left empty.
;; Also: CBUFLEN (A2PBIOS)
TYPE_AHEAD_SIZE = 78

;; <FirmwareStatus>'s request to a <CARD_PASCAL_FIRMWARE> card: is it ready for output?
FIRMWARE_ASK_OUTPUT = 0

;; <FirmwareStatus>'s request to a <CARD_PASCAL_FIRMWARE> card: has it input?
FIRMWARE_ASK_INPUT = 1

;; Polls the console's input, the keyboard or the console's card, into <TypeAhead>: acts on the stop, break and flush
;; keys, Control-A, Control-Z and the case keys, counts <PollCount>, and polls on while output is stopped.
;;
;; <IoControl>'s bit 0 skips Control-K, Control-A, Control-Z and the case keys, and its bit 1 the stop, break and
;; flush keys, which then go into <TypeAhead> as they are. The break key does not return: it goes to <BreakJump>.
;; Keeps: A, X, Y, P
;; Also: CONCK (A2PBIOS, WK11)
.proc ConsoleCheck
    php
    pha
    txa
    pha
    tya
    pha

;; Counts the poll in PollCount.
;; Also: RNDINC (A2PBIOS)
Poll:
    inc PollCount
    bne ByCard
    inc PollCount+1

;; Polls the console's card, if it has one. A CARD_PASCAL_FIXED card is read only by ConsoleRead.
;; Also: RNDOK (A2PBIOS)
ByCard:
    lda SlotTypes + CONSOLE_SLOT - 1
    cmp #CARD_SERIAL
    beq SerialKey
    cmp #CARD_PASCAL_FIXED
    beq NoKey
    cmp #CARD_PASCAL_FIRMWARE
    beq FirmwareKey

    ; Take a key from the keyboard, if there is one.
    lda KBD
    bpl NoKey
    sta KBDSTRB
    and #ASCII_BITS
    tax

    ; Skip the keyboard's keys if IoControl says so, leaving its bit 1 in bit 0 for TestSystemKeys.
    lda IoControl
    ror a
    bcs TestSystemKeys
    txa

    ; Control-K is "[".
    cmp #CTRL_K
    bne NotCtrlK
    lda #'['

;; Control-A: shows the other half of the screen, and stops following the cursor.
;; Also: NOTK (A2PBIOS)
NotCtrlK:
    cmp #CTRL_A
    bne NotCtrlA
    jsr ViewHalf::Toggle
    lda ConsoleFlags
    and #<(~CONSOLE_FOLLOW)
    sta ConsoleFlags
    jmp CheckStopped

;; Control-Z: follows the cursor. ORA leaves A not 0, so its branch is always taken.
;; Also: NTTAB (A2PBIOS)
NotCtrlA:
    cmp #CTRL_Z
    bne CaseKeys
    lda ConsoleFlags
    ora #CONSOLE_FOLLOW
    sta ConsoleFlags
    bne CheckStopped

;; Takes a key from a CARD_SERIAL card's ACIA, if it has one.
;; Also: COMCK (A2PBIOS, WK11)
SerialKey:
    lda Slot3AciaStatus
    lsr a
    bcc CheckStopped
    lda Slot3AciaData

;; Takes a key in A: strips it to seven bits.
;; Also: GOTCH (WK11), GOTCHAR (A2PBIOS)
StripKey:
    and #ASCII_BITS

;; Skips the stop, break and flush keys if IoControl's bit 1 says so.
;; Also: NOTFOL (A2PBIOS)
SystemKeys:
    tax
    lda IoControl
    ror a

;; Rotates IoControl's bit 1 into carry: set skips the stop, break and flush keys.
;; Also: NOTFOLP2 (A2PBIOS)
TestSystemKeys:
    ror a
    bcs StoreX
    txa

    ; The stop key: stop output, or start it again.
    ldy #SYSCOM_STOP_KEY
    cmp (SyscomPointer),y
    bne NotStop
    lda ConsoleFlags
    eor #CONSOLE_STOPPED
    sta ConsoleFlags

;; Goes on to poll again while output is stopped.
;; Also: JDONCK (A2PBIOS)
NoKey:
    jmp CheckStopped

;; Takes a key from a CARD_PASCAL_FIRMWARE card, if it has one.
;; Also: FIRMCK (A2PBIOS)
FirmwareKey:
    lda #FIRMWARE_ASK_INPUT
    ldy #CONSOLE_SLOT * 16
    jsr FirmwareStatus
    bcc CheckStopped
    jsr FirmwareRead
    jmp StripKey

;; The break key: starts output again, stops flushing it, and runs the break handler.
;; Also: NOTSTOP (A2PBIOS)
NotStop:
    .assert SYSCOM_BREAK_KEY = SYSCOM_STOP_KEY - 1, "ConsoleCheck steps Y down from the stop key to the break key."
    dey
    cmp (SyscomPointer),y
    bne NotBreak
    lda ConsoleFlags
    and #<(~(CONSOLE_STOPPED | CONSOLE_FLUSHED))
    sta ConsoleFlags
    jmp BreakJump

;; The flush key: flushes output, or stops flushing it.
;; Also: NOTBRK (A2PBIOS, WK11)
NotBreak:
    .assert SYSCOM_FLUSH_KEY = SYSCOM_BREAK_KEY - 1, "ConsoleCheck steps Y down from the break key to the flush key."
    dey
    cmp (SyscomPointer),y
    bne Store
    lda ConsoleFlags
    eor #CONSOLE_FLUSHED
    sta ConsoleFlags
    jmp CheckStopped

;; Stores the key in X in TypeAhead, or beeps if it is full.
;; Also: NFMI1 (A2PBIOS)
StoreX:
    txa

;; Stores the key in A in TypeAhead, or beeps if it is full.
;; Also: NOTFLUS (A2PBIOS)
Store:
    ldx TypeAheadIn
    jsr NextTypeAhead
    cpx TypeAheadOut
    bne Stored
    jsr Beep
    jmp CheckStopped

;; Stores the key at the type-ahead's new write position.
;; Also: BUFOK (A2PBIOS)
Stored:
    stx TypeAheadIn
    sta TypeAhead,x

;; Polls again while output is stopped.
;; Also: DONECK (A2PBIOS)
CheckStopped:
    bit ConsoleFlags
    bpl Return
    jmp Poll

    ; With the shift key up (Button2's bit 7 set) and no upper case lock, lower a capital letter.
CaseKeys:
    tax
    bit Button2
    bpl Shifted
    lda KeyboardCase
    rol a
    txa
    bcs OneKey
    cmp #'A'
    bcc OneKey
    cmp #'Z' + 1
    bcs OneKey
    ora #'a' - 'A'

    ; ORA leaves A not 0, so this always branches; the lowered letter matches no ShiftKeysFrom entry.
    bne Shifted

    ; A trampoline for NotCtrlW's branch, which cannot reach SystemKeys.
ToSystemKeys:
    jmp SystemKeys

    ; With the shift key down, turn the keys ShiftKeysFrom lists into ShiftKeysTo's.
Shifted:
    ldx #ShiftKeysTo - ShiftKeysFrom - 1
FindShifted:
    cmp ShiftKeysFrom,x
    beq Unshift
    dex
    bpl FindShifted
    bmi OneKey
Unshift:
    lda ShiftKeysTo,x

    ; After a key typed in upper case for one key only, go back to lower case.
OneKey:
    pha
    lda KeyboardCase
    and #KEYBOARD_ONE_KEY
    beq CtrlE
    lda #0
    sta KeyboardCase
CtrlE:
    pla

    ; Control-E: switch the upper case lock.
    cmp #CTRL_E
    bne NotCtrlE
    lda KeyboardCase
    eor #KEYBOARD_UPPER
    jmp SetCase

    ; Control-W: upper case for the next key. Any other key goes on to the system keys.
NotCtrlE:
    cmp #CTRL_W
    bne ToSystemKeys
    lda #KEYBOARD_UPPER | KEYBOARD_ONE_KEY

    ; Either case key shows capital letters inverse. InverseCapitalsOn leaves A not 0, so this always branches.
SetCase:
    sta KeyboardCase
    jsr InverseCapitalsOn
    bne CheckStopped

;; Restores the registers and returns.
;; Also: CKEXIT (A2PBIOS)
Return:
    pla
    tay
    pla
    tax
    pla
    plp
    rts
.endproc

;; Steps a <TypeAhead> index on, wrapping round to 0.
;; In: X = the index
;; Out: X = the next index
;; Keeps: A, Y
;; Also: BUMP (A2PBIOS), IXZE78 (WK11)
.proc NextTypeAhead
    inx
    cpx #TYPE_AHEAD_SIZE
    bne Done
    ldx #0

;; Returns with the position in X.
;; Also: BMPRTS (A2PBIOS)
Done:
    rts
.endproc

;; The BIOS's console init: takes SYSCOM's address and the break handler's from under its return address, empties
;; <TypeAhead>, starts output again, stops flushing it and following the cursor, and shows the screen's left half.
;; In: Stack = under the return address, SYSCOM's address, then the break handler's
;; Out: X = <IO_OK>
;; Also: CINIT (A2PBIOS, WK11), CONINIT (A2PBIOS)
.proc ConsoleInit

;; The return address, kept while <ConsoleInit> pulls its arguments from under it.
Caller = CardPointer

    ; Pull the return address, SYSCOM's address and the break handler's, and put the return address back.
    pla
    sta Caller
    pla
    sta Caller+1
    pla
    sta SyscomPointer
    pla
    sta SyscomPointer+1
    pla
    sta ConsoleBreakVector
    pla
    sta ConsoleBreakVector+1
    lda Caller+1
    pha
    lda Caller
    pha

    ; Empty TypeAhead.
    lda TypeAheadOut
    sta TypeAheadIn

    ; Clear the console's flags, and show the left half.
    lda ConsoleFlags
    and #<(~(CONSOLE_STOPPED | CONSOLE_FLUSHED | CONSOLE_FOLLOW))
    sta ConsoleFlags
    jsr ViewHalf::ShowLeft
    ldx #IO_OK
    rts
.endproc

;; The BIOS's console read: moves the view to the cursor if it follows it, and waits for a key in <TypeAhead>, or
;; reads one from a <CARD_PASCAL_FIXED> console card.
;; Out: A = the key, X = <IO_OK>
;; Also: CREAD (A2PBIOS, WK11)
.proc ConsoleRead
Wait:
    jsr FollowCursor

    ; Read a CARD_PASCAL_FIXED card directly.
    ldy #CONSOLE_SLOT * 16
    lda SlotTypes + CONSOLE_SLOT - 1
    cmp #CARD_PASCAL_FIXED
    bne FromTypeAhead
    jsr FixedRomRead
    and #ASCII_BITS
    rts

;; Polls until TypeAhead has a key, and takes it.
;; Also: CREAD2 (A2PBIOS)
FromTypeAhead:
    jsr ConsoleCheck
    ldx TypeAheadOut
    cpx TypeAheadIn
    beq Wait
    jsr NextTypeAhead
    stx TypeAheadOut
    lda TypeAhead,x
    ldx #IO_OK
    rts
.endproc
