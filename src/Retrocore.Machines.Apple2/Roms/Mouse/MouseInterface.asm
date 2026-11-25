; retrocore: style=strict
;; APPLE MOUSE INTERFACE CARD FIRMWARE (341-0270-C)
;;
;; The 6502 firmware of Apple's mouse card for the II, II Plus and IIe (the AppleMouse II), in its 2 KB EPROM.
;; The card has no $C800 ROM: its 6821 PIA's port B bits 1-3 drive the EPROM's A8-A10, so the firmware switches
;; eight 256-byte banks through its own page, $Cn00-$CnFF, while it runs. A 68705 microcontroller (341-0269) does
;; the card's real work: it counts the mouse's quadrature pulses, keeps the position within its bounds, times
;; vertical blanking and pulls the slot's IRQ line. The firmware only passes bytes to and from it through the PIA.
;;
;; Assembles byte-identically to the 341-0270-C EPROM (2048 bytes, SHA-1 3a9d881a8a8d30f55b9719aceebbcf717f829d6f).
;; Maintained by hand; MouseInterfaceSourceTests pins it by digest. It is a reference for the emulator's own mouse
;; firmware, Mouse.rom.asm, which answers the same calls without a microcontroller; the emulator does not run it.
;; docs/Apple2.md compares the two.
;;
;; THE BANKS
;;
;;   0  Identification, the entry points, and the dispatch every call starts and ends in (top level).
;;   1  <CopyrightBank>: the copyright message ($Cn1B), and a factory request with slot 0's holes ($Cn1A).
;;   2  <InitializeBank>: <InitializeMouse>, which resets the microcontroller and times it to vertical blanking.
;;   3  <CommandBank>: sends one command byte: <SetMouse>, <ClearMouse>, <HomeMouse>, the factory's $Bx and $C0,
;;      and <ServeMouse>, which reads one back.
;;   4  <BasicBank>: BASIC's `IN#` and `PR#`: the hooks, turning the mouse on or off, and reading it for INPUT.
;;   5  <LineBank>: writes BASIC's "X,Y,B" line into the input buffer.
;;   6  <ByteBank>: sends or receives one byte, and <ReadMouse>'s five.
;;   7  <ParameterBank>: sends a command with its parameters: <PositionMouse>, <ClampMouse>, and the factory's $9x
;;      and $A0.
;;
;; Every bank holds the same four instructions at $Cn70 (each bank's `Switch`): they put the bank in <NextBank> on
;; port B, which switches the EPROM under the 6502 as it runs, so the next instruction, at $Cn7B, is the new bank's.
;; That instruction pulls an entry code (ENTRY_*) that the new bank acts on: <ENTRY_MAIN> for the bank's main
;; routine, others for its other routines, and <ENTRY_RETURN> to return through an address pushed earlier. A routine
;; that must come back to the bank that called it finds that bank, times 2, in <MouseMode>'s upper nibble, which the
;; caller set.
;;
;; THE CALLS
;;
;; The mouse routines ($Cn12-$Cn19) are called with X = $Cn and Y = $n0, and use them throughout: X to reach the
;; slot's screen holes, Y the PIA. They return carry clear, or set for an error; A is not kept. Only <ServeMouse>,
;; which an interrupt handler may call with the language card's RAM over the Monitor, finds the slot itself, with an
;; RTS it writes at $06 rather than the Monitor's <SaveRegisters::Return>. BASIC's entries find it with
;; <SaveRegisters::Return> and leave <ExpansionRomSlot> = $Cn. The Pascal entries, <PascalEntry>, all answer error 3,
;; and $Cn1A-$Cn1F are the factory's own.
;;
;; NAMES
;;
;; The routines' names follow the calls Apple's AppleMouse II documentation gives programs (SETMOUSE ...), and the
;; screen holes' the names Apple II mouse programs use (MOUXL ...); no document in hand gives them, so they cite
;; UNKN. Every other name in this file is the SDK's own: the source was rebuilt from the EPROM, with no listing.

.cpu Mos6502

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The Monitor's entries and the expansion ROM switch, which MonitorEntries.asm does not have.

;; Inherit: <Monitor:CharacterOut>
;; At $FDED. The copyright message prints through it.
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

;; Inherit: <Monitor:ExpansionRomOff>
;; Its read here also latches the byte the video is reading into port B's bit 0 (<PORT_B_SYNC>).
;; Also: CLRROM (A2RM79, IIEROM82, IIETRM85)
ExpansionRomOff = $CFFF

;; The 6502's stack page: a routine finds the bytes it pushed at `Stack+1,x` and up after a TSX.
Stack = $0100

; The bytes the firmware is found by, as Apple's identification rules have them.

;; The opcode of BCC, whose offset is the CLC at $Cn07.
OPCODE_BCC = $90

;; The opcode of RTS, which <ServeMouse> writes at <Pointer>.
OPCODE_RTS = $60

;; $Cn0B: a firmware card with the generic Pascal 1.1 signature.
PASCAL_GENERIC = $01

;; $Cn0C: the card's device class: an X-Y pointing device, the mouse.
DEVICE_MOUSE = $20

;; $CnFB: the byte mouse programs check, after the Pascal bytes, to know the card is a mouse.
MOUSE_ID = $D6

;; The error the Pascal entries answer, in X.
PASCAL_ERROR = 3

;; The byte <ModelId> holds on the IIe.
IIE_MODEL_ID = $06

; The screen holes: slot 0's column holds ClampMouse's bounds, each slot's its own mouse. The firmware reaches slot
; n's as the hole's address less $C0, indexed by X = $Cn.

;; X = $Cn, so a screen hole's address less this, indexed by X, is slot n's own hole.
SLOT_PAGE = $C0

;; The mouse's X position, low byte; slot 0's is <ClampMouse>'s minimum, low byte.
;; Also: MOUXL (UNKN)
MouseX = $0478

;; The mouse's Y position, low byte; slot 0's is <ClampMouse>'s maximum, low byte.
;; Also: MOUYL (UNKN)
MouseY = $04F8

;; The mouse's X position, high byte; slot 0's is <ClampMouse>'s minimum, high byte.
;; Also: MOUXH (UNKN)
MouseXHigh = $0578

;; The mouse's Y position, high byte; slot 0's is <ClampMouse>'s maximum, high byte.
;; Also: MOUYH (UNKN)
MouseYHigh = $05F8

;; The firmware's own: port B's bank bits for the next switch, the bank times 2.
NextBank = $0678

;; The firmware's own: the command being sent, the byte read, or a count of bytes.
Argument = $06F8

;; The mouse's status, with the STATUS_* bits.
;; Also: MOUSTAT (UNKN)
MouseStatus = $0778

;; The mouse's mode, with the MODE_* bits, and in its upper nibble the bank to return to, times 2.
;; Also: MOUMODE (UNKN)
MouseMode = $07F8

;; <ClampMouse>'s minimum, low byte, in slot 0's holes.
ClampMinimum = MouseX

;; The high byte of <ClampMinimum>.
ClampMinimumHigh = MouseXHigh

;; <ClampMouse>'s maximum, low byte, in slot 0's holes.
ClampMaximum = MouseY

;; The high byte of <ClampMaximum>.
ClampMaximumHigh = MouseYHigh

; The status and mode bits.

;; Status: the button is down.
STATUS_BUTTON = $80

;; Status: the button was down at the last read.
STATUS_BUTTON_BEFORE = $40

;; Status: the mouse moved since the last read.
STATUS_MOVED = $20

;; Status, bits 1-3: the interrupt came from movement (bit 1), the button (bit 2) or vertical blanking (bit 3).
STATUS_INTERRUPTS = $0E

;; Mode: the mouse is on.
MODE_ON = $01

;; Mode, bits 0-3: on, and interrupts on movement, the button and vertical blanking.
MODE_FLAGS = $0F

;; The first mode <SetMouse> refuses.
MODE_LIMIT = $10

;; Mode: set by BASIC's entries. As a return bank (the upper nibble, the bank times 2) it is also bank 4, <BasicBank>.
MODE_BASIC = $80

;; How far the return bank is shifted in <MouseMode>.
RETURN_BANK_SHIFT = 4

; The PIA, indexed by Y = $n0. A control register's bit 2 selects the data register, clear the direction register.

;; Port A: the byte to or from the microcontroller.
PortA = $C080

;; Port A's control register.
PortAControl = $C081

;; Port B: 0 the sync latch, 1-3 the EPROM bank, 4-7 the handshake with the microcontroller (PORT_B_*).
PortB = $C082

;; Port B's control register.
PortBControl = $C083

;; A control register's bit 2: the port's data register, not its direction register.
SELECT_DATA = $04

;; Port A's direction: every bit out.
PORT_A_OUTPUT = $FF

;; Port A's direction: every bit in.
PORT_A_INPUT = $00

;; Port B, bit 0, in: the video byte's bit 0, latched by a read of <ExpansionRomOff>.
PORT_B_SYNC = $01

;; Port B, bits 1-3, out: the EPROM bank, times 2.
PORT_B_BANK = $0E

;; Port B, bit 4, out: the 6502 has taken the byte the microcontroller offered.
PORT_B_ACKNOWLEDGE = $10

;; Port B, bit 5, out: the 6502 has put a byte on port A.
PORT_B_STROBE = $20

;; Port B, bit 6, in: the microcontroller has put a byte on port A.
PORT_B_OFFERED = $40

;; Port B, bit 7, in: the microcontroller is taking a byte.
PORT_B_BUSY = $80

;; Port B's direction: the bank bits and the strobes out, the rest in.
PORT_B_OUTPUTS = PORT_B_BANK | PORT_B_ACKNOWLEDGE | PORT_B_STROBE

; The banks, which code writes times 2, as port B's bits 1-3 take them.

;; Bank 0: identification, the entry points, and the dispatch.
BANK_MAIN = 0

;; Bank 1: <CopyrightBank>.
BANK_COPYRIGHT = 1

;; Bank 2: <InitializeBank>.
BANK_INITIALIZE = 2

;; Bank 3: <CommandBank>.
BANK_COMMAND = 3

;; Bank 4: <BasicBank>.
BANK_BASIC = 4

;; Bank 5: <LineBank>.
BANK_LINE = 5

;; Bank 6: <ByteBank>.
BANK_BYTE = 6

;; Bank 7: <ParameterBank>.
BANK_PARAMETERS = 7

; The entry codes a bank pulls after a switch. What each means is in each bank's `Switch`.

;; The bank's main routine; in bank 0, the call is done.
ENTRY_MAIN = 0

;; The bank's second routine; in bank 0, a BASIC call is done.
ENTRY_SECOND = 1

;; The bank's third routine; in bank 0, the call is done with an error.
ENTRY_THIRD = 2

;; Negative: return through the address pushed below the code.
ENTRY_RETURN = $80

; The microcontroller's commands, as the firmware sends them in <Argument>.

;; $00-$0F: set the mode, <SetMouse>'s; $00 also turns BASIC's mouse off.
COMMAND_SET_MODE = $00

;; Read the position and status: five bytes back.
COMMAND_READ = $10

;; Read the interrupt status, for <ServeMouse>.
COMMAND_SERVE = $20

;; Set the position to 0, 0.
COMMAND_CLEAR = $30

;; Set the position: X and Y follow.
COMMAND_POSITION = $40

;; Reset; sent again as vertical blanking starts.
COMMAND_RESET = $50

;; Clamp X ($60) or Y ($61): the minimum and maximum follow.
COMMAND_CLAMP = $60

;; The bit of <COMMAND_CLAMP> that picks Y.
CLAMP_Y = $01

;; Move to the bounds' minimums.
COMMAND_HOME = $70

;; Turn the mouse on for BASIC, from `PR#`.
COMMAND_BASIC_ON = $80

;; The factory's $90-$9F, with none to three parameters as bits 2 and 3 say.
COMMAND_FACTORY_9 = $90

;; The factory's $A0, with the caller's A.
COMMAND_FACTORY_A = $A0

;; The factory's $B0-$BF, sent alone.
COMMAND_FACTORY_B = $B0

;; The factory's $C0.
COMMAND_FACTORY_C = $C0

;; The factory's $F0 or $F1, with slot 0's holes.
COMMAND_FACTORY_F = $F0

;; The bit of <COMMAND_FACTORY_F> that sends slot 0's <MouseXHigh>; clear, it reads a byte back into it.
FACTORY_SEND_HIGH = $01

;; A factory command's low nibble, from the caller's A.
LOW_NIBBLE = $0F

;; The bits of a factory command that say how many parameters follow.
FACTORY_PARAMETERS = $0C

;; How many bytes <COMMAND_READ> answers: X low and high, Y low and high, and the status, in the order they come.
READ_LENGTH = 5

; Page zero and the input buffer, which the firmware borrows and puts back.

;; A pointer, or a counter's low bytes; <ServeMouse>'s RTS.
Pointer = $06

;; The high byte of <InitializeBank>'s three-byte counter.
CountTop = $08

;; The number being written in decimal, low byte, past the end of BASIC's line in the input buffer.
Number = $0221

;; The high byte of <Number>.
NumberHigh = $0220

;; Y during BASIC's input.
BasicY = $0222

; BASIC's line in the input buffer, "+XXXXX,+YYYYY,+BB" and a return: the place of each number's sign and last
; digit.

;; X's sign.
LINE_X_SIGN = 0

;; X's last digit.
LINE_X_END = 5

;; Y's sign.
LINE_Y_SIGN = 7

;; Y's last digit.
LINE_Y_END = 12

;; The button's sign.
LINE_BUTTON_SIGN = 14

;; The button's last digit.
LINE_BUTTON_END = 16

;; The line's length, and the place of its return.
LINE_LENGTH = $11

;; The steps of a 16-bit division by 10, one per bit and one to shift the last quotient bit in.
DIVISION_STEPS = 17

; What InitializeMouse puts in hi-res page 1 on the II and II Plus.

;; Hi-res page 1's first page.
HIRES_PAGE = $20

;; The page after hi-res page 1.
HIRES_END = $40

;; A mark in the last line, which the video reads just before vertical blanking: its bit 0 is what the sync latch
;; sees.
SYNC_MARK = $01

;; The first mark.
FirstSyncMark = $3FD0

;; The second mark.
SecondSyncMark = $3FE0

;; The value of <CountTop> at or above which, after a carry into it, <InitializeMouse> stops looking for the marks.
SYNC_TIMEOUT = $01

; Bank 0: identification, the entry points, and the dispatch every call starts and ends in.
.logicalorg $C400

;; BASIC's entry, where `PR#n` or `IN#n` points a hook: BIT sets overflow, which says neither input nor output yet.
;;
;; Output keeps A, X and Y; input returns the line's length in both X and Y.
;; In:    A = the character to print, or the character under the cursor
;; Out:   A = RETURN for input, with the line in <InputBuffer> and X = Y = $11, its length
.proc BasicEntry
    bit SaveRegisters::Return       ; an RTS, $60: overflow set
    bvs EnterBasic
.endproc

;; BASIC's input entry ($Cn05), with carry set. Its BCC's offset, $18, is <BasicOutput>'s CLC.
.proc BasicInput
.assert * = $C405, "BasicInput must stay at $Cn05."
    sec
    .byte OPCODE_BCC                ; never taken from here; its offset is BasicOutput's CLC
.endproc

;; BASIC's output entry ($Cn07), with carry clear.
.proc BasicOutput
.assert * = $C407, "BasicOutput must stay at $Cn07."
    clc
    clv
    bvc EnterBasic
.endproc

; The Pascal 1.1 identification and the routines' offsets.
.assert * = $C40B, "The identification must start at $Cn0B."
    .byte PASCAL_GENERIC
    .byte DEVICE_MOUSE
    .byte <PascalEntry, <PascalEntry, <PascalEntry, <PascalEntry ; INIT, READ, WRITE and STATUS all answer error 3
    .byte $00                       ; $Cn11: more entries follow
.assert * = $C412, "The mouse routines' offsets must start at $Cn12."
    .byte <SetMouse, <ServeMouse, <ReadMouse, <ClearMouse
    .byte <PositionMouse, <ClampMouse, <HomeMouse, <InitializeMouse
    .byte <FactoryRequest, <ShowCopyright, <FactoryCommand9, <FactoryCommandA, <FactoryCommandB, <FactoryCommandC

;; Finds the slot for BASIC's entries, keeps the registers, sets <ExpansionRomSlot> to $Cn, and goes to <BasicBank>
;; as overflow and carry say.
;; In:    overflow = set from $Cn00, else carry = set for input, clear for output
;; Out:   ExpansionRomSlot = $Cn
.proc EnterBasic
    php
    sei
    sta ExpansionRomSlot            ; A, for a moment
    pha
    tya
    pha
    txa
    pha

    ; The Monitor's RTS leaves its return address's high byte, $Cn, just below the stack.
    jsr SaveRegisters::Return
    tsx
    lda Stack,x
    tax                             ; X = $Cn
    php
    asl a
    asl a
    asl a
    asl a
    plp
    tay                             ; Y = $n0

    ; The character, for bank 4.
    lda ExpansionRomSlot
    stx ExpansionRomSlot
    pha
    lda #BANK_BASIC * 2
    bvs EnterBank                   ; $Cn00: bank 4 works out the hook
    bcc EnterBankSecond             ; output
    bcs EnterBankThird              ; input
.endproc

;; $Cn1A, the factory's: sends command $F0 or $F1 with slot 0's holes, through <CopyrightBank::SendRequest>: $F1
;; also sends slot 0's <MouseXHigh>, and $F0 reads a byte back into it.
;; In:    A = 0 or 1, X = $Cn, Y = $n0
.proc FactoryRequest
    and #FACTORY_SEND_HIGH
    ora #COMMAND_FACTORY_F
    sta Argument - SLOT_PAGE,x
    lda #BANK_COPYRIGHT * 2
    bne EnterBankSecond
.endproc

;; $Cn1C, the factory's: sends command $90-$9F with parameters.
;; In:    A = the low nibble, X = $Cn, Y = $n0
.proc FactoryCommand9
    and #LOW_NIBBLE
    ora #COMMAND_FACTORY_9
    bne SendWithParameters
.endproc

    .res 2, $FF                     ; unused

;; Readies port B, with its bank, acknowledgment and strobe bits as outputs, and switches to the bank in
;; <NextBank>, which pulls its entry code.
;;
;; `Switch`, at $Cn70, is where every bank switches: the code after it is bank 0's, run when a bank switches back
;; to it. Its entry codes: <ENTRY_MAIN>, the call is done; <ENTRY_SECOND>, a BASIC call is done, with A, Y and X
;; on the stack as <EnterBasic> pushed them (or as <LineBank> pushed them for input), and P below; <ENTRY_THIRD>,
;; the call is done with carry set.
;;
;; Every bank switches back to bank 0 at `Switch`, without readying the port again, and <SetMouse> returns through
;; `Return` with carry as it left it.
;; In:    NextBank = the bank times 2, the stack = the entry code
.proc SwitchBank
    lda PortBControl,y
    and #<~SELECT_DATA
    sta PortBControl,y
    lda #PORT_B_OUTPUTS
    sta PortB,y
    lda PortBControl,y
    ora #SELECT_DATA
    sta PortBControl,y
Switch:
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_OUTPUTS           ; a new bank, with the acknowledgment and the strobe down
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    beq Succeed
    ror a
    bcc PascalEntry::Fail

    ; A BASIC call: its registers back.
    pla
    tax
    pla
    tay
    pla
    plp
    rts

Succeed:
    clc
Return:
    rts
.endproc

;; Bounds X (A = 0) or Y (A = 1) to slot 0's <ClampMinimum> and <ClampMaximum>.
;; In:    A = the axis, X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: CLAMPMOUSE (UNKN)
.proc ClampMouse
    and #CLAMP_Y
    ora #COMMAND_CLAMP
    ; Falls into SendWithParameters.
.endproc

;; Sends the command in A with its parameters, through <ParameterBank>.
;; In:    A = the command, X = $Cn, Y = $n0
.proc SendWithParameters
    sta Argument - SLOT_PAGE,x
    lda #BANK_PARAMETERS * 2
    ; Falls into EnterBankSecond.
.endproc

;; Enters a bank with <ENTRY_SECOND>.
;;
;; <EnterBankThird> goes on at `PushCode` with its own code in A.
;; In:    A = the bank times 2, X = $Cn, Y = $n0
.proc EnterBankSecond
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_SECOND
PushCode:
    pha
    bne SwitchBank
.endproc

;; Copies the status and position into the screen holes, if the mouse is on, through <ByteBank>.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: READMOUSE (UNKN)
.proc ReadMouse
    lda #BANK_BYTE * 2
    ; Falls into EnterBankThird.
.endproc

;; Enters a bank with <ENTRY_THIRD>.
;; In:    A = the bank times 2, X = $Cn, Y = $n0
.proc EnterBankThird
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_THIRD
    bne EnterBankSecond::PushCode
.endproc

;; Sets the position to 0, 0, and the holes with it.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: CLEARMOUSE (UNKN)
.proc ClearMouse
    lda #COMMAND_CLEAR
    ; Falls into SendCommand.
.endproc

;; Sends the one-byte command in A, through <CommandBank>.
;; In:    A = the command, X = $Cn, Y = $n0
.proc SendCommand
    sta Argument - SLOT_PAGE,x
    lda #BANK_COMMAND * 2
    ; Falls into EnterBank.
.endproc

;; Enters a bank at its main routine, with <ENTRY_MAIN>.
;; In:    A = the bank times 2, X = $Cn, Y = $n0
.proc EnterBank
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_MAIN
    pha
    beq SwitchBank
.endproc

;; Sets the mode: bit 0 on, bits 1, 2 and 3 interrupt on movement, the button and vertical blanking.
;; In:    A = the mode, X = $Cn, Y = $n0
;; Out:   carry = set if the mode is above $0F
;; Also: SETMOUSE (UNKN)
.proc SetMouse
    cmp #MODE_LIMIT
    bcs SwitchBank::Return
    sta MouseMode - SLOT_PAGE,x
    bcc SendCommand
.endproc

;; Resets the microcontroller: the mouse off at 0, 0 within 0-1023, its clock set by vertical blanking. The work is
;; <InitializeBank>'s.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: INITMOUSE (UNKN)
.proc InitializeMouse
    lda #BANK_INITIALIZE * 2
    bne EnterBank
.endproc

;; Sets the position from the slot's holes.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: POSMOUSE (UNKN)
.proc PositionMouse
    lda #COMMAND_POSITION
    bne SendWithParameters
.endproc

;; Called from an interrupt handler: finds the slot without the Monitor, which the language card may hide, and puts
;; the interrupt's cause in <MouseStatus>'s bits 1-3.
;; Out:   carry = clear if the mouse interrupted, X = $Cn, Y = $n0
;; Also: SERVEMOUSE (UNKN)
.proc ServeMouse
    ldy Pointer
    lda #OPCODE_RTS
    sta Pointer
    jsr Pointer
    sty Pointer
    tsx
    lda Stack,x                     ; $Cn, from the JSR
    tax
    asl a
    asl a
    asl a
    asl a
    tay
    lda #COMMAND_SERVE
    bne SendCommand
.endproc

;; Moves the position to the bounds' minimums.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Also: HOMEMOUSE (UNKN)
.proc HomeMouse
    lda #COMMAND_HOME
    bne SendCommand
.endproc

;; $Cn1D, the factory's: sends command $A0 with A.
;; In:    A = the parameter, X = $Cn, Y = $n0
.proc FactoryCommandA
    pha
    lda #COMMAND_FACTORY_A
    bne SendWithParameters
.endproc

;; $Cn1E, the factory's: sends command $B0-$BF.
;; In:    A = the low nibble, X = $Cn, Y = $n0
.proc FactoryCommandB
    and #LOW_NIBBLE
    ora #COMMAND_FACTORY_B
    bne SendCommand
.endproc

;; $Cn1F, the factory's: sends command $C0.
;; In:    X = $Cn, Y = $n0
.proc FactoryCommandC
    lda #COMMAND_FACTORY_C
    bne SendCommand
.endproc

;; $Cn1B: clears the screen and prints the copyright message, through <CopyrightBank>.
;; In:    X = $Cn, Y = $n0
.proc ShowCopyright
    lda #BANK_COPYRIGHT * 2
    bne EnterBank
.endproc

;; Pascal's INIT, READ, WRITE and STATUS: the card has no Pascal driver.
;;
;; Bank 0's switch fails a call at `Fail`, which returns carry set, keeping X.
;; Out:   X = 3, carry = set
.proc PascalEntry
    ldx #PASCAL_ERROR
Fail:
    sec
    rts
.endproc

    .res 3, $FF                     ; unused
.assert * = $C4FB, "The mouse's identification byte must be at $CnFB."
    .byte MOUSE_ID
    .byte $FF, $FF, $FF, $01        ; the page's last bytes, which the firmware never reads
.assert * = $C500, "Bank 0 must fill its page."

; Bank 1.
.logicalorg $C400

;; Bank 1: the copyright message, and $Cn1A's factory request.
.scope CopyrightBank

;; Clears the screen and prints <CopyrightText>, then goes back to bank 0, keeping Y and <Pointer>.
;; In:    X = $Cn, Y = $n0
.proc Show
    tya
    pha
    lda Pointer
    pha
    lda Pointer + 1
    pha
    stx Pointer + 1
    lda #<CopyrightText
    sta Pointer
    jsr Home

    ; The message, to its zero.
    ldy #0
NextCharacter:
    lda (Pointer),y
    beq Restore
    jsr CharacterOut
    iny
    bne NextCharacter

Restore:
    pla
    sta Pointer + 1
    pla
    sta Pointer
    pla
    tay
    bne Switch::Done                ; always: Y = $n0
.endproc

;; The copyright message, in high ASCII, ending in a zero.
CopyrightText:
    .hiascii "AppleMouse"
    .byte KEY_RETURN
    .hiascii "Copyright 1983 by Apple Computer, Inc."
    .byte KEY_RETURN, KEY_RETURN
    .hiascii "Bachman/Marks/MacKay"
    .byte KEY_RETURN, $00

;; Bank 1's switch. Its entry codes: <ENTRY_MAIN>, <Show>; <ENTRY_SECOND>, <SendRequest>; <ENTRY_RETURN>, return
;; through the address pushed below the code.
;;
;; The bank's routines go back to bank 0, done, at `Done`.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    bmi Return
    beq Show
    bne SendRequest
Done:
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    pha                             ; ENTRY_MAIN
    beq Switch
Return:
    rts
.endproc

;; $Cn1A's request: sends the command in <Argument> and slot 0's <MouseX> and <MouseY>, one byte at a time through
;; <ByteBank>; then for $F1 slot 0's <MouseXHigh> too, and for $F0 reads a byte back into slot 0's <MouseXHigh>.
;; In:    Argument = $F0 or $F1, X = $Cn, Y = $n0
.proc SendRequest
    lda MouseMode - SLOT_PAGE,x
    and #MODE_FLAGS
    ora #(BANK_COPYRIGHT * 2) << RETURN_BANK_SHIFT ; come back to bank 1
    sta MouseMode - SLOT_PAGE,x

    ; $Cn: the high byte of each address to come back through.
    txa
    pha
    pha
    pha
    pha
    lda #<(CommandSent - 1)
    pha
    lda Argument - SLOT_PAGE,x
Send:
    pha
    lda #BANK_BYTE * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_MAIN
    pha
    beq Switch
CommandSent:
    lda #<(FirstSent - 1)
    pha
    lda MouseX
    clc
    bcc Send
FirstSent:
    lda #<(SecondSent - 1)
    pha
    lda MouseY
    clc
    bcc Send
SecondSent:
    lda #<(Switch::Done - 1)
    pha
    ror Argument - SLOT_PAGE,x      ; $F1 sends MouseXHigh, $F0 reads it
    bcc Receive
    lda MouseXHigh
    bcs Send

    ; Reads a byte through bank 6 into Argument, coming back to Received.
Receive:
    txa
    pha
    lda #<(Received - 1)
    pha
    lda #BANK_BYTE * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_SECOND
    pha
    bne Switch
Received:
    lda Argument - SLOT_PAGE,x
    sta MouseXHigh
    rts                             ; to Switch::Done
.endproc

.endscope

    .res 31, $FF                    ; unused
    .byte $C2                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 1 must fill its page."

; Bank 2.
.logicalorg $C400

;; Bank 2: <InitializeMouse>'s reset, timed to vertical blanking.
.scope InitializeBank

;; Resets the microcontroller with <COMMAND_RESET>, reads its answer, and then sends the reset again as vertical
;; blanking starts, so its clock keeps time with the display. The IIe reads <DrawingState> for that. The II and II
;; Plus cannot, so this clears hi-res page 1 but for two marks in its last line, shows it, and watches the video's
;; bytes through the PIA's sync latch for the marks; it leaves the display in text, with lo-res, page 1 and no
;; mixing.
;; In:    X = $Cn, Y = $n0
;; Uses:  $2000..$3FFF (the II and II Plus's hi-res page 1)
.proc Reset
    lda MouseMode - SLOT_PAGE,x
    and #MODE_FLAGS
    ora #(BANK_INITIALIZE * 2) << RETURN_BANK_SHIFT ; come back to bank 2
    sta MouseMode - SLOT_PAGE,x
    txa
    pha
    pha
    pha
    lda #<(ResetSent - 1)
    bne Send

    ; The answer, read through bank 6.
ResetSent:
    lda #<(AnswerRead - 1)
    pha
    lda #BANK_BYTE * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_SECOND
    pha
    bne Switch

AnswerRead:
    lda ModelId
    cmp #IIE_MODEL_ID
    bne ClearHiRes

    ; The IIe: waits out the picture, then blanking, then the picture again, so that vertical blanking starts now.
WaitForBlanking:
    lda DrawingState
    bmi WaitForBlanking
WaitForPicture:
    lda DrawingState
    bpl WaitForPicture
WaitForNextBlanking:
    lda DrawingState
    bmi WaitForNextBlanking
    lda #<(Switch::Done - 1)
    bne Send

    ; Sends the reset through bank 6, which comes back through the address in A.
Send:
    pha
    lda #COMMAND_RESET
    pha
    lda #BANK_BYTE * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_MAIN
    pha
    beq Switch

    ; The II and II Plus: clears hi-res page 1.
ClearHiRes:
    lda Pointer
    pha
    lda Pointer + 1
    pha
    tya
    pha
    lda #HIRES_PAGE
    sta Pointer + 1
    ldy #0
    sty Pointer
NextPage:
    lda #0
ClearByte:
    sta (Pointer),y
    iny
    bne ClearByte
    inc Pointer + 1
    lda Pointer + 1
    cmp #HIRES_END
    bne NextPage
    pla
    tay
    lda CountTop
    pha
    lda #0
    beq Synchronize
.endproc

    .byte $FF                       ; unused

;; Bank 2's switch. Its entry codes: <ENTRY_MAIN>, <Reset>; <ENTRY_RETURN>, return through the address pushed below
;; the code.
;;
;; The bank's routines go back to bank 0, done, at `Done`.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    bmi Return
    beq Reset
Done:
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    pha                             ; ENTRY_MAIN
    beq Switch
Return:
    rts
ToSend:
    bne Reset::Send
.endproc

;; The II and II Plus: shows the cleared page with its two marks, and reads the sync latch, in a loop timed to the
;; cycle, until bit 0 of the latched video byte is 0, or the count gives up (<SYNC_TIMEOUT>); then sends the reset.
;;
;; The stack holds the old <CountTop> on top of the old <Pointer>, high byte then low, which it puts back.
;; In:    X = $Cn, Y = $n0
.proc Synchronize
    lda #SYNC_MARK
    sta FirstSyncMark
    sta SecondSyncMark
    lda HiResOn
    lda Page2Off
    lda MixedOff
    lda TextOff
    nop

    ; The counter's three bytes start from the byte TextOff's read left in A, the video's floating bus.
    sta Pointer
    sta Pointer + 1
    sta CountTop
Count:
    inc Pointer
    bne PauseLonger
    inc Pointer + 1
    bne Pause
    inc CountTop
    lda CountTop
    cmp #SYNC_TIMEOUT
    bcc Sample
    bcs Synchronized                ; given up
PauseLonger:
    php                             ; timing
    plp
Pause:
    php
    plp
    lda #0
    lda SlotPointer                 ; timing
Sample:
    lda ExpansionRomOff             ; the read latches the video byte's bit 0
    lda PortB,y
    lsr a
    nop
    nop
    bcs Count
    lda ExpansionRomOff
    lda PortB,y
    lsr a
    lda SlotPointer                 ; timing
    nop
    bcs Count

Synchronized:
    pla
    sta CountTop
    pla
    sta Pointer + 1
    pla
    sta Pointer
    lda #<(ShowText - 1)
    bne Switch::ToSend

    ; After the reset, the text display again.
ShowText:
    lda TextOn
    lda HiResOff
    clc
    bcc Switch::Done
.endproc

.endscope

    .res 18, $FF                    ; unused
    .byte $C1                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 2 must fill its page."

; Bank 3.
.logicalorg $C400

;; Bank 3: sends one command byte, and for <ServeMouse> reads the interrupt status back.
.scope CommandBank

;; Sends <Argument>'s command. For <COMMAND_SERVE> it reads the answer and ORs it into <MouseStatus> in place of
;; its interrupt bits; for <COMMAND_CLEAR> it clears the position's holes.
;; In:    Argument = the command, X = $Cn, Y = $n0
;; Out:   carry = clear, or set when the serve command finds no interrupt (as it returns to bank 0)
.proc Send
    lda Argument - SLOT_PAGE,x
    cmp #COMMAND_SERVE
    bne NoAnswer
    lda #$7F
    adc #$01                        ; overflow set: an answer to read
    bvs WaitUntilFree
NoAnswer:
    clv

WaitUntilFree:
    lda PortB,y
    bmi WaitUntilFree

    ; Port A out, and the command on it.
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_OUTPUT
    sta PortA,y
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y
    lda Argument - SLOT_PAGE,x
    sta PortA,y
    lda PortB,y
    ora #PORT_B_STROBE
    sta PortB,y
WaitUntilTaken:
    lda PortB,y
    bpl WaitUntilTaken
    and #<~PORT_B_STROBE
    sta PortB,y
    bvs ReadAnswer

    ; The clear command clears the holes too.
    lda Argument - SLOT_PAGE,x
    cmp #COMMAND_CLEAR
    bne Switch::Done
    lda #0
    sta MouseXHigh - SLOT_PAGE,x
    sta MouseX - SLOT_PAGE,x
    sta MouseYHigh - SLOT_PAGE,x
    sta MouseY - SLOT_PAGE,x
    beq Switch::Done
.endproc

    .res 23, $FF                    ; unused

;; Bank 3's switch. Its entry code: <ENTRY_MAIN>, <Send>.
;;
;; The bank's routines go back to bank 0, done, at `Done`.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    beq Send
Done:
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    pha                             ; ENTRY_MAIN
    beq Switch
.endproc

;; Reads the interrupt status and ORs it into <MouseStatus> in place of its interrupt bits; goes back to bank 0
;; with <ENTRY_THIRD>, carry set, when the interrupt was not the mouse's.
;; In:    X = $Cn, Y = $n0
.proc ReadAnswer
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_INPUT
    sta PortA,y
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y
WaitForByte:
    lda PortB,y
    asl a
    bpl WaitForByte                 ; until it offers a byte
    lda PortA,y
    sta Argument - SLOT_PAGE,x
    lda PortB,y
    ora #PORT_B_ACKNOWLEDGE
    sta PortB,y
WaitUntilSeen:
    lda PortB,y
    asl a
    bmi WaitUntilSeen               ; until it sees the acknowledgment
    lda PortB,y
    and #<~PORT_B_ACKNOWLEDGE
    sta PortB,y

    ; The answer, ORed in place of the status's interrupt bits.
    lda MouseStatus - SLOT_PAGE,x
    and #<~STATUS_INTERRUPTS
    ora Argument - SLOT_PAGE,x
    sta MouseStatus - SLOT_PAGE,x
    and #STATUS_INTERRUPTS
    bne Switch::Done                ; the mouse's interrupt
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_THIRD                ; not the mouse's: carry set
    pha
    bne Switch
.endproc

.endscope

    .res 41, $FF                    ; unused
    .byte $C3                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 3 must fill its page."

; Bank 4.
.logicalorg $C400

;; Bank 4: BASIC's `IN#` and `PR#`.
.scope BasicBank

;; From $Cn00: output when <OutputHook> points at the card and has not been moved to $Cn07 yet, else input when
;; <InputHook> points at it, else output. It moves the hook it finds to $Cn07 or $Cn05.
;; In:    X = $Cn, Y = $n0, the stack = the character
.proc FindHook
    cpx OutputHookHigh
    bne CheckInput
    lda #<BasicOutput
    cmp OutputHook
    beq CheckInput
    sta OutputHook
    ; Falls into Output.
.endproc

;; Output: a return is ignored; any other character turns the mouse on with an odd code and off with an even one,
;; as CHR$(1) and CHR$(0) do, and puts it in BASIC mode.
;; In:    X = $Cn, Y = $n0, the stack = the character
.proc Output
    pla
    cmp #KEY_RETURN
    beq Switch::Done
    and #MODE_ON
    ora #MODE_BASIC
    sta MouseMode - SLOT_PAGE,x

    ; The command, through bank 6, coming back to Switch::Done.
    txa
    pha
    lda #<(Switch::Done - 1)
    pha
    lda MouseMode - SLOT_PAGE,x
    lsr a
    lda #COMMAND_BASIC_ON
    bcs SendIt
    asl a                           ; off: COMMAND_SET_MODE with mode 0
SendIt:
    pha
    lda #BANK_BYTE * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_MAIN
    pha
    beq Switch
.endproc

;; The rest of <FindHook>: input when <InputHook> points at the card.
;; In:    X = $Cn, Y = $n0, the stack = the character
.proc CheckInput
    cpx InputHookHigh
    bne Output
    lda #<BasicInput
    sta InputHook
    ; Falls into Input.
.endproc

;; Input: reads the mouse, if it is on, and writes the line through <LineBank>. With the mouse off the position is
;; 0, 0 and the status <STATUS_BUTTON> and <STATUS_BUTTON_BEFORE>, which the line gives as B = 1.
;; In:    X = $Cn, Y = $n0, the stack = the character
.proc Input
    lda MouseMode - SLOT_PAGE,x
    and #MODE_ON
    bne Read

    ; The character, and EnterBasic's X, Y and A.
    pla
    pla
    pla
    pla
    lda #0
    sta MouseX - SLOT_PAGE,x
    sta MouseXHigh - SLOT_PAGE,x
    sta MouseY - SLOT_PAGE,x
    sta MouseYHigh - SLOT_PAGE,x
    beq Off

Read:
    lda MouseMode - SLOT_PAGE,x
    and #MODE_ON
    ora #MODE_BASIC                 ; BASIC mode, which also brings bank 6 back here
    sta MouseMode - SLOT_PAGE,x
    txa
    pha
    lda #<(ReadPosition - 1)
    pha
    lda #COMMAND_READ
    pha
    lda #BANK_BYTE * 2
    bne SwitchTo
.endproc

    .res 6, $FF                     ; unused

;; Bank 4's switch. Its entry codes: <ENTRY_MAIN>, <FindHook>; <ENTRY_SECOND>, <Output>; <ENTRY_THIRD>, <Input>;
;; <ENTRY_RETURN>, return through the address pushed below the code.
;;
;; <Output> goes back to bank 0 at `Done`, with <ENTRY_SECOND>, which puts back <EnterBasic>'s registers; <Input>
;; goes back through <LineBank>.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    bmi Return
    beq FindHook
    ror a
    bcs Output
    bcc Input
Done:
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_SECOND
    pha
    bne Switch
Return:
    rts
.endproc

;; The mouse is off: the status that reads as B = 1, then the line.
;; In:    X = $Cn, Y = $n0
.proc Off
    lda #STATUS_BUTTON | STATUS_BUTTON_BEFORE
    sta MouseStatus - SLOT_PAGE,x
    ; Falls into WriteLine.
.endproc

;; Writes the line through <LineBank>.
;; In:    X = $Cn, Y = $n0
.proc WriteLine
    sty BasicY
    lda #BANK_LINE * 2
    ; Falls into SwitchTo.
.endproc

;; Enters a bank at its main routine.
;; In:    A = the bank times 2, X = $Cn, Y = $n0
.proc SwitchTo
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_MAIN
    pha
    beq Switch
.endproc

;; After <COMMAND_READ>: reads the five bytes into <MouseStatus>, <MouseYHigh>, <MouseY>, <MouseXHigh> and
;; <MouseX>, then writes the line.
;; In:    X = $Cn, Y = $n0
.proc ReadPosition
    ; The character, and EnterBasic's X, Y and A.
    pla
    pla
    pla
    pla

    ; Port A in.
    lda #READ_LENGTH
    sta Argument - SLOT_PAGE,x
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_INPUT
    sta PortA,y
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y

    ; Each byte onto the stack.
WaitForByte:
    lda PortB,y
    asl a
    bpl WaitForByte
    lda PortA,y
    pha
    lda PortB,y
    ora #PORT_B_ACKNOWLEDGE
    sta PortB,y
WaitUntilSeen:
    lda PortB,y
    asl a
    bmi WaitUntilSeen
    lda PortB,y
    and #<~PORT_B_ACKNOWLEDGE
    sta PortB,y
    dec Argument - SLOT_PAGE,x
    bne WaitForByte

    ; Into the holes.
    pla
    sta MouseStatus - SLOT_PAGE,x
    pla
    sta MouseYHigh - SLOT_PAGE,x
    pla
    sta MouseY - SLOT_PAGE,x
    pla
    sta MouseXHigh - SLOT_PAGE,x
    pla
    sta MouseX - SLOT_PAGE,x
    clc
    bcc WriteLine
.endproc

.endscope

    .res 3, $FF                     ; unused
    .byte $C8                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 4 must fill its page."

; Bank 5.
.logicalorg $C400

;; Bank 5: BASIC's "X,Y,B" line.
.scope LineBank

;; Writes "+XXXXX,+YYYYY,+BB" and a return into <InputBuffer> ($0200-$0211), each number signed and in decimal, and
;; returns the return with X = $11, the line's length, as <Monitor:GetLine> would; so INPUT reads it, and nothing is
;; echoed. B is 1 for the button down and down at the last read, 2 pressed since, 3 released since and 4 up; negative
;; when a key waits.
;; In:    X = $Cn, ExpansionRomSlot = $Cn, BasicY = Y
;; Out:   (through bank 0) A = $8D, X = Y = $11
.proc Write
    ; $Cn: the high byte of each address to come back through.
    txa
    pha
    pha
    pha

    ; X.
    lda #<(XWritten - 1)
    pha
    ldy MouseX - SLOT_PAGE,x
    lda MouseXHigh - SLOT_PAGE,x
    tax
    tya
    ldy #LINE_X_END
    bne WriteSigned

    ; Y.
XWritten:
    ldx ExpansionRomSlot
    lda #<(YWritten - 1)
    pha
    ldy MouseY - SLOT_PAGE,x
    lda MouseYHigh - SLOT_PAGE,x
    tax
    tya
    ldy #LINE_Y_END
    bne WriteSigned

    ; The button: 1 down and down, 2 pressed, 3 released, 4 up; negative when a key waits.
YWritten:
    ldx ExpansionRomSlot
    lda #<(ButtonWritten - 1)
    pha
    lda Keyboard
    asl a
    php                             ; carry: a key is waiting
    lda MouseStatus - SLOT_PAGE,x
    rol a
    rol a
    rol a
    and #$03                        ; the button now, and before
    eor #$03
    sec
    adc #$00
    plp
    ldx #0
    ldy #LINE_BUTTON_END
    bne WriteDecimal

    ; The return, and the registers bank 0 returns: A, Y and X.
ButtonWritten:
    lda #KEY_RETURN
    sta InputBuffer + LINE_LENGTH
    pha
    lda #LINE_LENGTH
    pha
    pha
    lda #BANK_MAIN * 2
    beq Finish
.endproc

    .res 18, $FF                    ; unused

;; Goes back to bank 0 with <ENTRY_SECOND>, which returns the A, Y and X just pushed.
;; In:    A = <BANK_MAIN> times 2
.proc Finish
    ldx ExpansionRomSlot
    ldy BasicY
    sta NextBank - SLOT_PAGE,x
    lda #ENTRY_SECOND
    pha
    ; Falls into Switch.
.endproc

;; Bank 5's switch. Its entry codes: <ENTRY_MAIN>, <Write>; <ENTRY_RETURN>, return through the address pushed below
;; the code.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    bmi WriteDecimal::Return
    beq Write
    ; Falls into WriteSigned.
.endproc

;; Writes a signed number, sign first, then five digits ending at <InputBuffer>+Y, then a comma after it.
;; In:    X/A = the number, high/low, Y = the place of its last digit
.proc WriteSigned
    cpx #$80
    bcc WriteDecimal

    ; Negative: carry is set, so each EOR and ADC negates.
    eor #$FF
    adc #$00
    pha
    txa
    eor #$FF
    adc #$00
    tax
    pla
    sec
    ; Falls into WriteDecimal.
.endproc

;; Writes a number's digits, from <InputBuffer>+Y down to the place after a sign, then the sign, and a comma after the
;; digits.
;; In:    X/A = the number, high/low, Y = the place of its last digit, carry = set for a minus sign
;;
;; Bank 5's switch returns through the address pushed below its code at `Return`.
.proc WriteDecimal
    sta Number
    stx NumberHigh
    lda #'+' | $80
    bcc PushSign
    lda #'-' | $80
PushSign:
    pha
    lda #',' | $80
    sta InputBuffer + 1,y

    ; Divides Number by 10, the remainder in A, for each digit.
NextDigit:
    ldx #DIVISION_STEPS
    lda #0
    clc
Divide:
    rol a
    cmp #10
    bcc Shift
    sbc #10
Shift:
    rol Number
    rol NumberHigh
    dex
    bne Divide
    ora #'0' | $80
    sta InputBuffer,y
    dey
    beq PlaceSign
    cpy #LINE_Y_SIGN
    beq PlaceSign
    cpy #LINE_BUTTON_SIGN
    bne NextDigit

PlaceSign:
    pla
    sta InputBuffer,y
Return:
    rts
.endproc

.assert LINE_X_SIGN = 0, "WriteDecimal stops at X's sign by finding Y zero."

.endscope

    .res 50, $FF                    ; unused
    .byte $CD                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 5 must fill its page."

; Bank 6.
.logicalorg $C400

;; Bank 6: sends or receives one byte, and <ReadMouse>'s bytes.
.scope ByteBank

;; Sends the byte on the stack, then returns to the bank in <MouseMode>'s upper nibble, or to bank 0.
;; In:    the stack = the byte, X = $Cn, Y = $n0
.proc SendByte
    clv
    bvc Read::Send
.endproc

;; <ReadMouse>'s work: when the mouse is on, sends <COMMAND_READ> and reads the five bytes into the holes.
;; In:    X = $Cn, Y = $n0
;;
;; <SendByte> goes on at `Send`, which sends the byte on the stack and, with overflow set, then reads <Argument>'s
;; count of bytes.
.proc Read
    lda MouseMode - SLOT_PAGE,x
    and #MODE_ON
    beq Back::SetBank               ; off: back to bank 0
    lda #COMMAND_READ
    pha
    lda #READ_LENGTH
    sta Argument - SLOT_PAGE,x
    lda #$7F
    adc #$01                        ; overflow set: an answer to read
Send:
    lda PortB,y
    bmi Send

    ; Port A out, and the byte on it.
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_OUTPUT
    sta PortA,y
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y
    pla
    sta PortA,y
    lda PortB,y
    ora #PORT_B_STROBE
    sta PortB,y
WaitUntilTaken:
    lda PortB,y
    bpl WaitUntilTaken
    and #<~PORT_B_STROBE
    sta PortB,y
    bvs ReceiveBytes
    ; Falls into Back.
.endproc

;; Returns to the bank in <MouseMode>'s upper nibble, through the address its caller pushed, or to bank 0.
;; In:    overflow = clear, or set to go to the bank in A
;;
;; <Read> goes on at `SetBank`, which goes to the bank in A.
.proc Back
    bvs SetBank
    lda MouseMode - SLOT_PAGE,x
    lsr a
    lsr a
    lsr a
    lsr a
SetBank:
    clv
    sta NextBank - SLOT_PAGE,x
    beq PushCode
    lda #ENTRY_RETURN               ; another bank: return through the stack
PushCode:
    pha
    bvc Switch
.endproc

    .res 20, $FF                    ; unused

;; Bank 6's switch. Its entry codes: <ENTRY_MAIN>, <SendByte>; <ENTRY_SECOND>, <Receive>; <ENTRY_THIRD>, <Read>.
;;
;; <ReceiveBytes> goes on to <Back> through `ToBack`.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    beq SendByte
    cmp #ENTRY_THIRD
    beq Read
    bne Receive
ToBack:
    beq Back
.endproc

;; Receives a byte into <Argument>.
;; In:    X = $Cn, Y = $n0
.proc Receive
    clv
    ; Falls into ReceiveBytes.
.endproc

;; Receives a byte into <Argument>; with overflow set (for <ReadMouse>), receives <Argument>'s count of bytes onto the
;; stack instead, and puts them in the holes.
;; In:    X = $Cn, Y = $n0
.proc ReceiveBytes
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_INPUT
    sta PortA,y
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y
WaitForByte:
    lda PortB,y
    asl a
    bpl WaitForByte
    lda PortA,y
    bvs Push
    sta Argument - SLOT_PAGE,x
    bvc Acknowledge
Push:
    pha
Acknowledge:
    lda PortB,y
    ora #PORT_B_ACKNOWLEDGE
    sta PortB,y
WaitUntilSeen:
    lda PortB,y
    asl a
    bmi WaitUntilSeen
    lda PortB,y
    and #<~PORT_B_ACKNOWLEDGE
    sta PortB,y
    bvc Finished
    dec Argument - SLOT_PAGE,x
    bne WaitForByte

    ; ReadMouse's bytes, into the holes.
    pla
    sta MouseStatus - SLOT_PAGE,x
    pla
    sta MouseYHigh - SLOT_PAGE,x
    pla
    sta MouseY - SLOT_PAGE,x
    pla
    sta MouseXHigh - SLOT_PAGE,x
    pla
    sta MouseX - SLOT_PAGE,x
Finished:
    lda #BANK_MAIN * 2              ; for ReadMouse, with overflow set
    beq Switch::ToBack
.endproc

.endscope

    .res 29, $FF                    ; unused
    .byte $C1                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 6 must fill its page."

; Bank 7.
.logicalorg $C400

;; Bank 7: a command with its parameters.
.scope ParameterBank

;; Sends <Argument>'s command and its parameters: for <COMMAND_POSITION> the slot's <MouseX>, <MouseXHigh>,
;; <MouseY> and <MouseYHigh>; for <COMMAND_CLAMP> slot 0's <ClampMinimum>, <ClampMaximum>, <ClampMinimumHigh> and
;; <ClampMaximumHigh>; for <COMMAND_FACTORY_A> the caller's A; for the factory's $9x, as bits 2 and 3 say, none,
;; slot 0's <MouseXHigh>, its <MouseX> and <MouseY>, or all three.
;; In:    Argument = the command, X = $Cn, Y = $n0
.proc Send
    lda Argument - SLOT_PAGE,x
    cmp #COMMAND_POSITION
    beq Position
    cmp #COMMAND_CLAMP
    beq Clamp
    cmp #COMMAND_CLAMP | CLAMP_Y
    beq Clamp
    cmp #COMMAND_FACTORY_A
    bne OtherCommand

    ; The command, and the caller's A below it.
    pha
    lda #2
    bne SetCount

Clamp:
    lda ClampMaximumHigh
    pha
    lda ClampMinimumHigh
    pha
    lda ClampMaximum
    pha
    lda ClampMinimum
    bcs PushCommand                 ; always: the CMP matched

Position:
    lda MouseYHigh - SLOT_PAGE,x
    pha
    lda MouseY - SLOT_PAGE,x
    pha
    lda MouseXHigh - SLOT_PAGE,x
    pha
    lda MouseX - SLOT_PAGE,x
PushCommand:
    pha
    lda Argument - SLOT_PAGE,x
    pha
    lda #5
    bne SetCount

    ; The factory's: bit 2 set, two or three of slot 0's holes; else bit 3 set, one; else none.
OtherCommand:
    and #FACTORY_PARAMETERS
    lsr a
    lsr a
    lsr a
    bcs SlotZeroHoles
    lsr a
    bcc CommandOnly
    lda MouseXHigh
    pha
    lda Argument - SLOT_PAGE,x
    pha
    lda #2
    bne SetCount
CommandOnly:
    lda Argument - SLOT_PAGE,x
    pha
    lda #1
SetCount:
    sta Argument - SLOT_PAGE,x
    bne SendBytes
.endproc

    .res 14, $FF                    ; unused

;; Bank 7's switch. Its entry code: <ENTRY_SECOND>, <Send>.
;;
;; The bank's routines go back to bank 0, done, at `Done`.
.proc Switch
.assert * = $C470, "Every bank's switch must be at $Cn70."
    lda PortB,y
    and #<~PORT_B_BANK
    ora NextBank - SLOT_PAGE,x
    sta PortB,y
    pla
    bne Send
Done:
    lda #BANK_MAIN * 2
    sta NextBank - SLOT_PAGE,x
    pha                             ; ENTRY_MAIN
    beq Switch
.endproc

;; The factory's commands with two or three of slot 0's holes: <MouseX> and <MouseY>, and with bit 3 <MouseXHigh>.
;; In:    A = the command's bit 3 in bit 0, X = $Cn, Y = $n0
.proc SlotZeroHoles
    lsr a
    bcs Three
    lda MouseY
    pha
    lda MouseX
    pha
    lda Argument - SLOT_PAGE,x
    pha
    lda #3
    sta Argument - SLOT_PAGE,x
    bne SendBytes
Three:
    lda MouseXHigh
    pha
    lda MouseY
    pha
    lda MouseX
    pha
    lda Argument - SLOT_PAGE,x
    pha
    lda #4
    sta Argument - SLOT_PAGE,x
    ; Falls into SendBytes.
.endproc

;; Sends <Argument>'s count of bytes from the stack, then goes back to bank 0.
;; In:    Argument = the count, X = $Cn, Y = $n0
.proc SendBytes
    lda PortB,y
    bmi SendBytes

    ; Port A out.
    lda PortAControl,y
    and #<~SELECT_DATA
    sta PortAControl,y
    lda #PORT_A_OUTPUT
    sta PortA,y

    ; Each byte.
NextByte:
    lda PortAControl,y
    ora #SELECT_DATA
    sta PortAControl,y
    pla
    sta PortA,y
    lda PortB,y
    ora #PORT_B_STROBE
    sta PortB,y
WaitUntilTaken:
    lda PortB,y
    bpl WaitUntilTaken
    and #<~PORT_B_STROBE
    sta PortB,y
    dec Argument - SLOT_PAGE,x
    beq Switch::Done
WaitUntilFree:
    lda PortB,y
    bmi WaitUntilFree
    bpl NextByte
.endproc

.endscope

    .res 18, $FF                    ; unused
    .byte $CE                       ; the bank's last byte, which the firmware never reads
.assert * = $C500, "Bank 7 must fill its page."
