;; APPLE-1 MONITOR ($FF00-$FFFF)
;;
;; Steve Wozniak's monitor for the Apple-1 (1976), the 256 bytes of the board's two 256x4 PROMs. Their eight
;; address lines see only the low byte of the address, so the Monitor shows through all of $F000-$FFFF, and the
;; 6502's vectors at $FFFA-$FFFF are its last six bytes.
;;
;; RESET sets up the PIA and enters GETLINE, which shows a backslash after an escape and takes a line into
;; the input buffer at $0200, echoing each key. Underscore (the keyboard's back arrow) takes back a key, though
;; the screen keeps it; ESC drops the line; more than 127 keys drop it too. Return runs the line, item by item:
;;
;;   hex          examines that address, showing "ADDR: BYTE"
;;   hex.hex      examines a range, eight bytes a line
;;   hex: hex ... stores the bytes from that address on
;;   R            runs the program at the last address examined
;;
;; Items are separated by spaces, and a line can hold several (such as "300: A9 00 R"). A character that is not
;; a hex digit, space, period, colon or R ends the line, after the items before it have run.
;;
;; Keys come from the PIA's port A (KBD), whose bit 7 the keyboard holds high, so every character here has bit
;; 7 set. Characters go out through port B (DSP); bit 7 of DSP reads 1 while the terminal is still taking the
;; last one, which can be up to a frame, 1/60 s.
;;
;; Names are Wozniak's, from the listing in the Apple-1 Operation Manual. Maintained by hand; Apple1RomTests
;; pins the build's digest.

.cpu Mos6502

; The Apple-1's keyboard sets bit 7, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

;; The low byte of the address being examined, the last one opened.
;; See: <XAMH>
XAML = $24

;; The high byte of the address being examined.
;; See: <XAML>
XAMH = $25

;; The low byte of the address the next stored byte goes to.
;; See: <STH>
STL = $26

;; The high byte of the address the next stored byte goes to.
;; See: <STL>
STH = $27

;; The low byte of the hex number just parsed.
;; See: <H>
L = $28

;; The high byte of the hex number just parsed.
;; See: <L>
H = $29

;; Where in the line the hex number being parsed started, to tell whether it had any digits.
YSAV = $2A

;; What the line's hex numbers do: $00 to examine one address, $AE (bit 7 set, from ".") to examine up to one,
;; $74 (bit 6 set, from ":" shifted left) to store.
MODE = $2B

;; The input buffer, a line of up to 127 keys.
IN = $0200

;; The PIA's port A: the key last typed, with bit 7 set. Reading it clears KBDCR's bit 7.
;; See: <KBDCR>
KBD = $D010

;; The PIA's port A control: bit 7 is set when a key is typed, until KBD is read.
;; See: <KBD>
KBDCR = $D011

;; The PIA's port B: writing a character sends it to the terminal; bit 7 reads 1 while the terminal is busy.
;; See: <DSPCR>
DSP = $D012

;; The PIA's port B control.
;; See: <DSP>
DSPCR = $D013

;; Where NMI goes: RAM at $0F00, for a program or an expansion to fill.
NMI_HANDLER = $0F00

;; Where IRQ and BRK go: RAM at $0000, for a program to fill.
IRQ_HANDLER = $0000

    .org $FF00

;; Resets the machine: sets up the PIA and starts the command line.
;;
;; Port B's bits 0-6 become outputs to the terminal and bit 7 an input from it. Both ports take their keys and
;; acknowledgements on the rising edge of CA1 and CB1, and CB2 strobes the terminal on each write.
RESET:
    CLD                             ; binary arithmetic
    CLI
    LDY #%01111111                  ; DSP bits 0-6 are outputs
    STY DSP                         ; (DSPCR's bit 2 is clear after reset: this is DDRB)
    LDA #%10100111                  ; CA1/CB1 rising edges; CB2 strobes writes; select the data registers
    STA KBDCR
    STA DSPCR
; A typed key that is not Return. Y = its place in the line.
NOTCR:
    CMP #'_'                        ; the back arrow
    BEQ BACKSPACE
    CMP #$9B                        ; ESC
    BEQ ESCAPE
    INY
    BPL NEXTCHAR                    ; until the line passes 127 keys
; Drops the line: shows a backslash and starts a new one.
ESCAPE:
    LDA #'\'
    JSR ECHO
;; Starts a new line: goes to the next screen line and takes keys into IN.
GETLINE:
    LDA #$8D                        ; Return
    JSR ECHO
    LDY #1                          ; the DEY makes it 0
; Takes back a key; before the start of the line, starts again.
BACKSPACE:
    DEY
    BMI GETLINE
; Waits for a key, stores it and echoes it.
NEXTCHAR:
    LDA KBDCR
    BPL NEXTCHAR                    ; until a key is typed
    LDA KBD
    STA IN,Y
    JSR ECHO
    CMP #$8D                        ; Return
    BNE NOTCR

; Runs the line.
    LDY #$FF                        ; the INY makes it 0
    LDA #0                          ; examine
    TAX
; ":": stores the numbers that follow (A = ":", which shifts left to $74, bit 6 set and bit 7 clear).
SETSTOR:
    ASL
; ".": examines up to the number that follows (A = $AE, bit 7 set).
SETMODE:
    STA MODE
; Skips a space, or any other character below ".".
BLSKIP:
    INY
; Takes the line's next item.
NEXTITEM:
    LDA IN,Y
    CMP #$8D                        ; Return: the line is done
    BEQ GETLINE
    CMP #'.'
    BCC BLSKIP
    BEQ SETMODE
    CMP #':'
    BEQ SETSTOR
    CMP #'R'
    BEQ RUN
    STX L                           ; X = 0: the number starts at 0
    STX H
    STY YSAV
; Shifts the next hex digit into H and L.
NEXTHEX:
    LDA IN,Y
    EOR #'0'                        ; "0"-"9" become 0-9
    CMP #10
    BCC DIG
    ADC #$88                        ; "A"-"F" become $FA-$FF (carry set)
    CMP #$FA
    BCC NOTHEX
DIG:
    ASL                             ; the digit to the high nibble
    ASL
    ASL
    ASL
    LDX #4
HEXSHIFT:
    ASL                             ; one bit at a time into L and H
    ROL L
    ROL H
    DEX
    BNE HEXSHIFT
    INY
    BNE NEXTHEX
; The number ends: stores it, examines it, or ends the line when it has no digits.
NOTHEX:
    CPY YSAV
    BEQ ESCAPE                      ; no digits: an error drops the rest of the line
    BIT MODE
    BVC NOTSTOR
    LDA L                           ; store mode: store the number's low byte
    STA (STL,X)                     ; X = 0
    INC STL
    BNE NEXTITEM
    INC STH
TONEXTITEM:
    JMP NEXTITEM

;; Runs the program at the last address examined.
RUN:
    JMP (XAML)

; Examine mode: shows the bytes from XAM up to the number, or opens the number when MODE is 0.
NOTSTOR:
    BMI XAMNEXT                     ; "." mode: XAM is already set
    LDX #2                          ; copy the number into STL/STH and XAML/XAMH
SETADR:
    LDA L-1,X
    STA STL-1,X
    STA XAML-1,X
    DEX
    BNE SETADR
; Shows the address before the first byte and every eighth one (Z = set to show it).
NXTPRNT:
    BNE PRDATA
    LDA #$8D                        ; Return
    JSR ECHO
    LDA XAMH
    JSR PRBYTE
    LDA XAML
    JSR PRBYTE
    LDA #':'
    JSR ECHO
; Shows the byte at XAM.
PRDATA:
    LDA #' '
    JSR ECHO
    LDA (XAML,X)                    ; X = 0
    JSR PRBYTE
; Moves on to the next byte, until XAM passes the number.
XAMNEXT:
    STX MODE                        ; examine mode, X = 0
    LDA XAML
    CMP L
    LDA XAMH
    SBC H
    BCS TONEXTITEM                  ; XAM is the number: done
    INC XAML
    BNE MOD8CHK
    INC XAMH
MOD8CHK:
    LDA XAML
    AND #7                          ; a new line every eight bytes
    BPL NXTPRNT                     ; always

;; Shows a byte as two hex digits.
;;
;; In: A = the byte
;; Uses: A
;; Keeps: X, Y
PRBYTE:
    PHA
    LSR
    LSR
    LSR
    LSR
    JSR PRHEX                       ; the high digit
    PLA
;; Shows the low four bits of a byte as a hex digit.
;;
;; In: A = the digit, in bits 0-3
;; Uses: A
;; Keeps: X, Y
PRHEX:
    AND #$0F
    ORA #'0'
    CMP #'9'+1
    BCC ECHO
    ADC #6                          ; "A"-"F" (carry set)
;; Sends a character to the terminal, waiting until it is ready for one.
;;
;; In: A = the character, bit 7 set
;; Keeps: A, X, Y
ECHO:
    BIT DSP
    BMI ECHO                        ; until the terminal takes the last character
    STA DSP
    RTS

    .word $0000                     ; unused
    .assert * = $FFFA, "The Monitor ends at the 6502's vectors."
    .word NMI_HANDLER
    .word RESET
    .word IRQ_HANDLER
