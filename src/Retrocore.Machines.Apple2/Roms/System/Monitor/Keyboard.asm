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

; The internal firmware's functions: the number in Y when the Monitor calls <GOTOCX>. The two IIe models
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
.if ENHANCED

;; Reads a key through the input hook, <KSWL>, with the cursor shown.
;;
;; At $FD0C. The internal firmware shows the cursor, for 40 or 80 columns.
;; Out: A = the key, with its high bit set
;; Also: RDKEY (IIETRM85)
.proc ReadKey
.assert * = $FD0C, "ReadKey must stay at $FD0C."
    ldy #FIRMWARE_READ_KEY
    bne ToFirmware

    ; Not reached.
    jmp Hook

;; Calls the firmware function in Y.
ToFirmware:
    jsr CallFirmware
    nop
    nop

;; Reads the key through the input hook.
;; Also: RDKEYHOOK (UNKN)
Hook:
    jmp (KSWL)
.endproc
.else

;; Reads a key through the input hook, <KSWL>, with the cursor shown.
;;
;; At $FD0C. The cursor is the character under it, flashing; the input routine puts the character back.
;; Out: A = the key, with its high bit set
;; Also: RDKEY (A2RM78, A2RM79, IIEROM82)
.proc ReadKey
.assert * = $FD0C, "ReadKey must stay at $FD0C."
    ; The input routine gets the character in A and the cursor's column in Y.
    ldy CH
    lda (BASL),y
    pha
    and #CHARACTER_BITS
    ora #FLASHING
    sta (BASL),y
    pla

;; Reads the key through the input hook.
;; Also: RDKEYHOOK (UNKN)
Hook:
    jmp (KSWL)
.endproc
.endif
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
;; Also: KEYIN (IIEROM82, IIETRM85)
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

;; Reads a key with the 80-column firmware taking escape sequences: clearing <MSLOT>'s bit 7 tells it to.
;;
;; At $FD28.
;; Out: A = the key
.proc ReadKeyAllowEscape
.assert * = $FD28, "Escape::ReadKeyAllowEscape must stay at $FD28."
    lsr MSLOT
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
    sta SETSLOTCXROM

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
;; At $FD1B. <RNDL>/<RNDH> count up while it waits, for programs to seed random numbers from.
;; In: A = the character under the cursor, Y = <CH>
;; Out: A = the key, with its high bit set
;; Keeps: X, Y
;; Also: KEYIN (A2RM78, A2RM79)
.proc KeyboardIn
.assert * = $FD1B, "KeyboardIn must stay at $FD1B."
    inc RNDL
    bne Check
    inc RNDH

;; Waits until a key is typed.
;; Also: KEYIN2 (A2RM78, A2RM79)
Check:
    bit KBD
    bpl KeyboardIn

    ; The key: the cursor's character back, then the strobe cleared.
    sta (BASL),y
    lda KBD
    bit KBDSTRB
    rts
.endproc
.endif

; Escape: the escape-mode loop.
.scope Escape continued

;; Escape mode: reads and performs escape commands, then reads the next character.
;;
;; At $FD2F. The Apple II Monitor performs one command and leaves escape mode; the others stay in it while
;; the keys are I, J, K and M.
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
;; At $FD35.
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
    cmp #KEY_ESC
    beq Escape::Sequence
    rts
.endproc
