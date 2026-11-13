;; APPLE CASSETTE INTERFACE ($C100-$C1FF)
;;
;; The firmware of the Apple Cassette Interface (ACI), Steve Wozniak's cassette card for the Apple-1's expansion
;; slot, in one 256-byte PROM at $C100-$C1FF. "C100R" in the Monitor starts it with a "*" prompt, which takes a
;; line of commands:
;;
;;   start.endW   writes memory from start to end to tape, after a leader tone of about ten seconds
;;   start.endR   reads a recording into memory from start to end
;;
;; Several can share a line (such as "E000.EFFFW 0004.00FFW"). Return goes back to the Monitor, and ESC or a
;; character that is not a hex digit starts the line again.
;;
;; The card has no other registers. Any access to $C000-$C0FF flips the flip-flop that drives the tape output,
;; and a read there returns the PROM's byte with address bit 0 taken from the tape input, so reading $C081 gives
;; the byte at $C180 ($D0) or $C181 ($FA) as the input is low or high; the routines only look for a change. They
;; time each half cycle of the tape's square wave in loops of known length:
;;
;; - The leader is long half cycles, and the end of the leader one short one.
;; - Each bit is a full cycle, most significant bit first: a long one (about 1000 Hz) for 1 and a short one
;;   (about 2000 Hz) for 0.
;;
;; There is no checksum; a recording plays back into whatever range the R command names.
;;
;; The labels are this source's names for the routines; the zero-page and I/O names are the Monitor's. Maintained
;; by hand; Apple1RomTests pins the build's digest.

.cpu Mos6502

; The Apple-1's keyboard sets bit 7, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

;; The low byte of the hex number being parsed: the end of the range once a "." has been read.
;; See: <HEXH>
HEXL = $24

;; The high byte of the hex number being parsed.
;; See: <HEXL>
HEXH = $25

;; The low byte of the next address to write to tape or read into.
;; See: <ADRH>
ADRL = $26

;; The high byte of the next address to write to tape or read into.
;; See: <ADRL>
ADRH = $27

;; Where in the line the command being carried out ends, kept while the tape runs.
SAVEX = $28

;; The tape input's level last read, as <TAPEIN> gives it.
LASTSTATE = $29

;; The Monitor's input buffer.
IN = $0200

;; The flip-flop driving the tape output: any access to $C000-$C0FF flips it.
TAPEOUT = $C000

;; The tape input: a read gives $D0 or $FA, the PROM's bytes at $C180 and $C181, as the input is low or high
;; (and flips the output).
TAPEIN = $C081

;; The PIA's port A: the key last typed, with bit 7 set.
KBD = $D010

;; The PIA's port A control: bit 7 is set when a key is typed, until KBD is read.
KBDCR = $D011

;; The Monitor's escape: shows a backslash and takes a new Monitor line.
ESCAPE = $FF1A

;; The Monitor's character output.
ECHO = $FFEF

    .org $C100

;; Starts the cassette command line: shows "*" and takes a line of commands into IN.
RESET:
    LDA #'*'
    JSR ECHO
    LDA #$8D                        ; Return
    JSR ECHO
    LDY #$FF                        ; the INY makes it 0
NEXTCHAR:
    INY
KBDWAIT:
    LDA KBDCR
    BPL KBDWAIT                     ; until a key is typed
    LDA KBD
    STA IN,Y
    JSR ECHO
    CMP #$9B                        ; ESC starts the line again
    BEQ RESET
    CMP #$8D                        ; Return
    BNE NEXTCHAR

; Runs the line.
    LDX #$FF                        ; the INX makes it 0
; Starts a command: clears the range.
NEXTCMD:
    LDA #0
    STA HEXL
    STA HEXH
    STA ADRL
    STA ADRH
; Takes the line's next character.
NEXTCHR:
    INX
    LDA IN,X
    CMP #'R'
    BEQ READ
    CMP #'W'
    BEQ WRITE
    CMP #'.'
    BEQ SEP
    CMP #$8D                        ; Return: back to the Monitor
    BEQ GOESC
    CMP #' '
    BEQ NEXTCHR
    EOR #'0'                        ; "0"-"9" become 0-9
    CMP #10
    BCC DIG
    ADC #$88                        ; "A"-"F" become $FA-$FF (carry set)
    CMP #$FA
    BCC RESET                       ; not a hex digit: start the line again
DIG:
    ASL                             ; the digit to the high nibble
    ASL
    ASL
    ASL
    LDY #4
HEXSHIFT:
    ASL                             ; one bit at a time into HEXL and HEXH
    ROL HEXL
    ROL HEXH
    DEY
    BNE HEXSHIFT
    BEQ NEXTCHR                     ; always
GOESC:
    JMP ESCAPE

; ".": the number so far starts the range, and the next one ends it.
SEP:
    LDA HEXL
    STA ADRL
    LDA HEXH
    STA ADRH
    BCS NEXTCHR                     ; always: the CMP found "."

;; Writes ADRL/ADRH through HEXL/HEXH to tape: a leader of $40 x 256 long half cycles, the short half cycle that
;; ends it, then the bytes.
WRITE:
    LDA #$40
    JSR WHEADER
WRNEXT:
    DEY                             ; a little less time between bytes, for the code around them
    LDX #0
    LDA (ADRL,X)
    LDX #2 * 8                      ; two half cycles for each of eight bits
WRBIT:
    ASL                             ; the next bit to carry
    JSR WRITEBIT
    BNE WRBIT
    JSR INCADDR
    LDY #$1E                        ; the first half cycle's delay, less the time to here
    BCC WRNEXT                      ; until the range is done
; Ends a command: goes on with the rest of the line.
RESTORE:
    LDX SAVEX
    BCS NEXTCMD                     ; always

;; Reads a recording into ADRL/ADRH through HEXL/HEXH: lets the leader settle, finds the short half cycle that
;; ends it, then reads the bytes.
READ:
    JSR FULLCYCLE
    LDA #$16                        ; about two seconds of leader to pass before looking for its end
    JSR WHEADER
    JSR FULLCYCLE
NOTSTART:
    LDY #$1F
    JSR CMPLEVEL
    BCS NOTSTART                    ; until a short half cycle
    JSR CMPLEVEL                    ; its other half
    LDY #$3A
RDBYTE:
    LDX #8
RDBIT:
    PHA
    JSR FULLCYCLE                   ; carry = set for a long cycle, a 1
    PLA
    ROL
    LDY #$39
    DEX
    BNE RDBIT
    STA (ADRL,X)                    ; X = 0
    JSR INCADDR
    LDY #$35
    BCC RDBYTE                      ; until the range is done
    BCS RESTORE                     ; always

;; Times a full cycle of the tape input: two half cycles.
;;
;; In: Y = the count to start from, lower for a shorter allowance
;; Out: carry = set for a long cycle, Y = the count left
;; Uses: A, Y
;; Keeps: X
FULLCYCLE:
    JSR CMPLEVEL
;; Times a half cycle of the tape input: counts Y down until the input changes.
;;
;; In: Y = the count to start from
;; Out: carry = set when Y counted below 0 (a long half cycle), A = the new level
;; Uses: A, Y
;; Keeps: X
CMPLEVEL:
    DEY
    LDA TAPEIN
    CMP LASTSTATE
    BEQ CMPLEVEL                    ; until the level changes
    STA LASTSTATE
    CPY #$80
    RTS

;; Writes a leader of A x 256 long half cycles, then the short half cycle that ends it.
;;
;; In: A = the leader's length, in 256 half cycles
;; Uses: A, X, Y
WHEADER:
    STX SAVEX
HCOUNT:
    LDY #$42                        ; a long half cycle
    JSR WDELAY
    BNE HCOUNT                      ; 256 of them
    ADC #$FE                        ; less one, with the carry WDELAY left
    BCS HCOUNT
    LDY #$1E                        ; the short half cycle
;; Writes one half cycle of a bit, then the next half's delay: long for a 1, short for a 0.
;;
;; In: carry = the bit, X = the half cycles left
;; Out: X = one fewer, zero = set when none are left
;; Uses: Y
WRITEBIT:
    JSR WDELAY
    LDY #$2C
;; Waits out a half cycle and flips the tape output.
;;
;; In: Y = the delay, carry = set for the longer wait of a 1
;; Out: X = one fewer, zero = set when X reaches 0
;; Uses: Y
WDELAY:
    DEY
    BNE WDELAY
    BCC WRITE1                      ; a 0 bit: the shorter wait
    LDY #$2F
WDELAY1:
    DEY
    BNE WDELAY1
WRITE1:
    LDY TAPEOUT,X                   ; flip the output
    LDY #$29
    DEX
    RTS

;; Steps ADRL/ADRH to the next address.
;;
;; Out: carry = set when the address was HEXL/HEXH, the end of the range
;; Uses: A
;; Keeps: X, Y
INCADDR:
    LDA ADRL
    CMP HEXL
    LDA ADRH
    SBC HEXH
    INC ADRL
    BNE INCADDR_1
    INC ADRH
INCADDR_1:
    RTS

    .assert * = $C200, "The ACI's PROM is 256 bytes."
