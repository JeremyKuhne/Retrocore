; retrocore: style=strict
;; Keyboard input, $FD0C-$FD3C: reading a key through the input hook with a cursor shown, the keyboard's own
;; input routine, escape mode's key reading, and reading a character with escape sequences handled.

; The cursor.

;; The bits of a screen character that <ReadKey> keeps when it shows the cursor: its character, without the bits
;; that pick normal, flashing or inverse.
CHARACTER_BITS = %00111111

;; The bit that makes a screen character, with its high bit clear, flash.
FLASHING = %01000000
.if MONITOR = MONITOR_IIE

; The internal firmware's functions: the number in Y when the Monitor calls <CallFirmware>. The two IIe models
; number them differently.
.if ENHANCED

;; The firmware function that translates a key read in escape mode.
FIRMWARE_ESCAPE_KEY = $01

;; The firmware function that waits for a key, as <KeyboardIn> does.
FIRMWARE_KEYBOARD_IN = $03

;; The firmware function that shows the cursor, in 40 or 80 columns, before <ReadKey> reads a key.
FIRMWARE_READ_KEY = $0B
.else

;; The firmware function that waits for a key, as <KeyboardIn> does.
FIRMWARE_KEYBOARD_IN = $06

;; The firmware function that translates a key read in escape mode.
FIRMWARE_ESCAPE_KEY = $07
.endif
.endif

;; Reads a key through the input hook, <InputHook>, with the cursor shown.
;;
;; At $FD0C. On the Apple II's Monitors and the original IIe the cursor is the character under it, flashing, and
;; the input routine puts the character back; on the Enhanced IIe the internal firmware shows the cursor, for 40 or
;; 80 columns.
;; Out: A = the key, with its high bit set
;; Also: RDKEY (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadKey
.assert * = $FD0C, "ReadKey must stay at $FD0C."
.if ENHANCED
    ldy #FIRMWARE_READ_KEY
    bne ToFirmware

    ; Not reached.
    jmp Hook

;; Calls the firmware function in Y.
ToFirmware:
    jsr CallFirmware
    nop
    nop
.else
    ; The input routine gets the character in A and the cursor's column in Y.
    ldy CursorColumn
    lda (TextBase),y
    pha
    and #CHARACTER_BITS
    ora #FLASHING
    sta (TextBase),y
    pla
.endif

;; Reads the key through the input hook.
;; Also: RDKEYHOOK (UNKN)
Hook:
    jmp (InputHook)
.endproc
.if MONITOR = MONITOR_IIE

;; The keyboard's input routine, the input hook's default: the internal firmware waits for a key, then
;; clears the strobe.
;;
;; At $FD1B. The original IIe's firmware takes the character under the cursor in A and flashes it while it
;; waits.
;; Out: A = the key, with its high bit set
;; Entry:
;;   ToFirmware = goes to the firmware function in Y; on the Enhanced IIe, <ClearLineFrom> and
;;     <Escape::ReadEscapeKey> branch here too
;; Also: KEYIN (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc KeyboardIn
.assert * = $FD1B, "KeyboardIn must stay at $FD1B."
    ldy #FIRMWARE_KEYBOARD_IN

;; Goes to the firmware function in Y; on the Enhanced IIe, <ClearLineFrom> and <Escape::ReadEscapeKey> branch here
;; too.
ToFirmware:
    jmp CallFirmware

    ; Unused.
    .byte $EA
.endproc

; Escape: reading its keys.
.scope Escape continued

;; Reads a key, then has the internal firmware translate it as an escape-mode key: lowercase to uppercase, and
;; the arrow keys to I, J, K and M.
;;
;; At $FD21.
;; Out: A = the key
;; Also: RDESC (IIEROM82, IIETRM85)
.proc ReadEscapeKey
.assert * = $FD21, "Escape::ReadEscapeKey must stay at $FD21."
    jsr ReadKey
    ldy #FIRMWARE_ESCAPE_KEY
.if ENHANCED
    bne KeyboardIn::ToFirmware
.else
    jmp CallFirmware
.endif
.endproc
.if ENHANCED

;; Reads a key with the 80-column firmware taking escape sequences: clearing <ExpansionRomSlot>'s bit 7 tells it to.
;;
;; At $FD28.
;; Out: A = the key
.proc ReadKeyAllowEscape
.assert * = $FD28, "Escape::ReadKeyAllowEscape must stay at $FD28."
    lsr ExpansionRomSlot
    jmp ReadKey

    ; Unused.
    .byte $EA
.endproc
.endif

.endscope
.if .not ENHANCED

;; The internal firmware's way back: switches slot ROM in, then returns with the status it saved.
;;
;; At $FD29.
;; Entry:
;;   PullStatus = returns with the saved status, the ROM left as it is; the firmware jumps here too
;; Also: SLOTRTN (UNKN)
.proc SlotRomReturn
.assert * = $FD29, "SlotRomReturn must stay at $FD29."
    sta InternalCxRomOff

;; Returns with the saved status, the ROM left as it is; the firmware jumps here too.
PullStatus:
.assert * = $FD2C, "SlotRomReturn::PullStatus must stay at $FD2C."
    plp
    rts

    ; Unused.
    .byte $60
.endproc
.endif
.else

;; The keyboard's input routine, the input hook's default: waits for a key, then puts back the character the
;; cursor covered and clears the strobe.
;;
;; At $FD1B. <RandomSeed>/<RandomSeedHigh> count up while it waits, for programs to seed random numbers from.
;; In: A = the character under the cursor, Y = <CursorColumn>
;; Out: A = the key, with its high bit set
;; Keeps: X, Y
;; Also: KEYIN (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc KeyboardIn
.assert * = $FD1B, "KeyboardIn must stay at $FD1B."
    inc RandomSeed
    bne Check
    inc RandomSeedHigh

;; Waits until a key is typed.
;; Also: KEYIN2 (A2RM78, A2RM79)
Check:
    bit Keyboard
    bpl KeyboardIn

    ; The key: the cursor's character back, then the strobe cleared.
    sta (TextBase),y
    lda Keyboard
    bit KeyboardStrobe
    rts
.endproc
.endif

; Escape: the escape-mode loop.
.scope Escape continued

;; Escape mode: reads and performs escape commands, then reads the next character.
;;
;; At $FD2F. The Apple II Monitor performs one command and leaves escape mode; the others stay in it while
;; the keys are I, J, K and M. The IIe's read the key through <Escape::ReadEscapeKey>, which takes lowercase and
;; the arrow keys.
;; Also: ESC (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Sequence
.assert * = $FD2F, "Escape::Sequence must stay at $FD2F."
.if MONITOR = MONITOR_IIE
    jsr ReadEscapeKey
.else
    jsr ReadKey
.endif
.if MONITOR = MONITOR_II
    jsr Command
.else
    jsr Escape::NextKey
.endif
; Falls into ReadCharacter.
.endproc

.endscope

;; Reads a character, performing escape sequences (cursor moves) instead of returning them.
;;
;; At $FD35. On the Enhanced IIe it reads with the 80-column firmware taking escape sequences
;; (<Escape::ReadKeyAllowEscape>).
;; Out: A = the character
;; Also: RDCHAR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadCharacter
.assert * = $FD35, "ReadCharacter must stay at $FD35."
.if ENHANCED
    jsr Escape::ReadKeyAllowEscape
.else
    jsr ReadKey
.endif
    ; ESC: the compare, equal, leaves the carry set, as Escape::Command needs.
    cmp #KEY_ESCAPE
    beq Escape::Sequence
    rts
.endproc
