;; TRS-80 MODEL III AND MODEL 4 BASIC ($0000-$37FF)
;;
;; The Model III's 14K ROM is three chips: ROM A ($0000-$1FFF) and ROM B ($2000-$2FFF) hold Level II 1.3 with the
;; Model III's own drivers, cassette routines and start-up in place of the Model I's, and ROM C ($3000-$37FF) holds
;; what did not fit there. This file assembles the whole ROM: it includes Level2.asm with MODEL = 3, which
;; assembles $0000-$2FFF, and then gives ROM C.
;;
;; ROM C starts with a table of jumps that programs and Level2.asm's Model III blocks call, followed by:
;;
;; - the keyboard driver, whose 256-byte translation table KBTAB is indexed by key number, shift and shift lock,
;;   with small routines in the slots no key uses;
;; - the cassette routines at 500 baud, as Level II's, and at 1500 baud, where each bit is one cycle of the tape's
;;   signal and its edges interrupt the Z80;
;; - the power-up, which boots a disk when one is present, and the disk boot itself;
;; - the real-time clock's interrupt, which blinks the cursor, counts the time and date, and can show them;
;; - the interrupt dispatcher, the RS-232 drivers and the I/O router;
;; - the RAM image of vectors and device control blocks copied to $4000 and $41E5 at power-up.
;;
;; MODEL selects the machine: 3 (the default) or 4. The Model 4's ROM shares ROM A and B and changes ROM C: its
;; keyboard driver reads the Model 4's CTRL, CAPS and function keys, its keyboard table holds no code, its
;; start-up clears the 6845 and asks Cass ? from a new place, and it has no I/O router. Its routines that only
;; moved keep their Model III names. ROMC selects the Model III's revision of ROM C: 'C' (the default, 8040316C)
;; or 'B' (8040316B).
;;
;; Labels are those of Radio Shack's Model III source, as trs-80.com's annotated disassembly of the Model I, III
;; and 4 ROMs gives them, with any $ dropped. The comments are our own.
;;
;; Maintained by hand. Trs80RomSourceTests check that each revision assembles byte-identically to the ROMs.

.ifndef MODEL
MODEL = 3
.endif
.ifndef ROMC
ROMC = 'C'
.endif
.assert (ROMC = 'B') | (ROMC = 'C'), "ROMC is 'B' or 'C'."
.assert (MODEL = 3) | (MODEL = 4), "MODEL is 3 or 4."
.assert (MODEL = 3) | (ROMC = 'C'), "ROMC selects a Model III revision."

.include "Level2.asm"
.assert * = $3000, "ROM C starts at $3000."

;; The entries programs and ROM A call, three bytes apart.

;; Writes the leader and sync byte at 500 baud.
WSYNCZ:
    JP WSYNC

;; Writes the leader and sync byte at 1500 baud.
SYNCWZ:
    JP SYNCW

;; Waits for the leader and sync byte at 500 baud.
RSYNCZ:
    JP RSYNC

;; Waits for the leader and sync byte at 1500 baud.
SYNCRZ:
    JP SYNCR

;; Stops the cassette motor.
CASOFF:
    JP CASOFZ

;; Starts the cassette motor and waits for it to come up to speed.
CTONZ:
    JP CTON

;; Boots the disk in drive 0.
BOOT:
    JP BOOTZZ

;; Starts the machine at power-up and reset.
INIT:
    JP INITZ

;; Finds which device interrupted, through RST $38.
POLLZ:
    JP POLL

;; The RS-232 set-up driver.
RSINIZ:
    JP RSINIT

;; The RS-232 input driver.
RSINZ:
    JP RSIN

;; The RS-232 output driver.
RSOUTZ:
    JP RSOUT

;; The keyboard driver.
KEYBDZ:
    JP KEYBD

;; The router's driver; the Model 4 has no router.
DOROTZ:
.if MODEL = 4
    RET
    NOP
    NOP
.else
    JP DOROT
.endif

;; Takes a PRINT #-n or INPUT #-n's number for SWITCH.
LKSEE:
    JP LK

;; Watches quotes and colons as PLOOP copies a line.
KANA:
    JP CPATCH

;; The TIME$ function: the date and time as a string.
DOTIME:
    JP ZTIME

;; Writes the date at HL, as MM/DD/YY.
RTDATZ:
    JP RTDAT

;; Writes the time at HL, as HH:MM:SS.
RTCLKZ:
    JP RTCLK

;; The nonmaskable interrupt, through NMI at $0066: the reset button restarts the machine; otherwise the disk
;; controller interrupted, and the DOS's handler at NMI_VECTOR takes it.
DOSIT:
    IN A,[NMI_PORT]
    BIT 5,A                         ; clear while reset is held
    JP DOINIT
.if MODEL = 4
    .byte $AA, $AA
.else
    JR INIT                         ; never reached
.endif

;; Asks for the cassette's speed.
CPRMPZ:
    JP CPRMPT

;; The keyboard's translation table, indexed by key number: the row times eight plus the column, plus 64 with
;; shift and 128 with shift lock. Rows 0-3 are @ and the letters, 4 and 5 the digits and punctuation, 6 ENTER,
;; CLEAR, BREAK, the arrows and space; row 7 is the shift keys, which never index it. The Model III fills the slots
;; no key uses with routines, and the Model 4 with zeros; the Model 4's shift cancels shift lock, so its last
;; quarter, for both, holds the cassette prompt instead.
KBTAB:
    .byte "@abcdefghijklmnopqrstuvwxyz"
.if MODEL = 4
    .res 5, $00
.else

;; Tests whether the two shift keys work separately, as SHFEQU says: zero when they are one key, as on early
;; machines.
CHKEQU:
    LD A,[SHFEQU]
    OR A
    RET
.endif
    .byte "0123456789:;,-./"
    .byte $0D, $1F, $01, $5B, $0A, $08, $09, $20 ; ENTER, CLEAR, BREAK, up, down, left, right, space

.if MODEL = 4
    .res 8, $00
.else

;; No key is down: the next one repeats only after the full delay.
;; Out:   A = 0
NOKEY:
    LD HL,1500
    LD [TDELAY],HL
    XOR A
    RET
.endif
    .byte "`ABCDEFGHIJKLMNOPQRSTUVWXYZ" ; with shift
.if MODEL = 4
    .res 5, $00
.else

;; Stores the shift lock flag, and returns no key.
FLP1:
    LD [HL],A
EXITNK:
    XOR A
    RET
    .byte $AA, $AA
.endif
    .byte $00, "!", $22, "#$%&'()*+<=>?" ; with shift: shift and 0 is the shift lock key
    .byte $0D, $1F, $01, $1B, $1A, $18, $19, $20
.if MODEL = 4
    .res 8, $00
.else

;; Turns shift lock on or off.
FLPFLP:
    LD A,$01
    LD HL,SHFLCK
    XOR [HL]
    JR FLP1
.endif
    .byte "@ABCDEFGHIJKLMNOPQRSTUVWXYZ" ; with shift lock
.if MODEL = 4
    .res 5, $00
.else

;; Control-*: prints the screen, and returns no key.
GOSCRP:
    CALL SCRPRT
    XOR A
    RET
.endif
    .byte "0123456789:;,-./"
    .byte $0D, $1F, $01, $5B, $0A, $08, $09, $20
.if MODEL = 4
    .res 8, $00

;; Asks for the cassette's speed, and goes on starting BASIC.
CASMSG:
    CALL CPRMPT
    JP INIT2

;; Asks Cass ? until H (or ENTER) chooses 1500 baud or L chooses 500.
CPRMPT:
    EI
    CALL CR
    LD HL,CASSMG
    CALL VDLINE
    CALL KBWAIT
    CP $0D
    JR Z,CASMS1
    PUSH AF
    CALL DISPLAY_CHAR
    POP AF
    CP 'H'
    JR Z,CASMS1
    CP 'L'
    JR NZ,CPRMPT
    XOR A
CASMS1:
    LD [CASDCB],A

;; Shows a carriage return.
CR:
    LD A,$0D
    JP DISPLAY_CHAR

;; The cassette prompt: the cursor on, then Cass ?.
CASSMG:
    .byte $0E, "Cass ? ", $03

;; Control-*: prints the screen, and returns no key.
GOSCRP:
    CALL PRTSCR
    XOR A
    RET
    .res 5, $00
.else

;; Finishes a key: control-* prints the screen and BREAK makes a DOS request through RST $28.
;; In:    A = the key, zero = set for control-*, HL = CNTFLG
;; Out:   A = the key
CHKBRK:
    JR Z,GOSCRP
    AND [HL]                        ; with control, letters become control codes
    CP $01
    RET NZ
    RST $28
    RET
    .byte "`ABCDEFGHIJKLMNOPQRSTUVWXYZ" ; with shift and shift lock

;; Moves the scan to the next row.
BUMP:
    INC D                           ; the next row's first key
    INC HL                          ; its place in KEYBOARD_IMAGE
    RLC C                           ; its address; negative after the last row
    RET
    .byte $00, "!", $22, "#$%&'()*+<=>?"
    .byte $0D, $1F, $01, $1B, $1A, $18, $19, $20

;; Gets the key last pressed, to see whether it is still down.
;; Out:   L = its row's place in KEYBOARD_IMAGE, A = its bit
GETRC:
    LD A,[LROW]
    LD L,A
    LD A,[LCOL]
    RET
.endif
.assert * = KBTAB + 256, "KBTAB is 256 bytes."

;; The printer's translation of the printable characters, $20-$7F: each as itself, except that revision B prints
;; ` as @.
VDTAB:
.repeat $40, index
    .byte $20 + index
.endrepeat
.if ROMC = 'B'
    .byte '@'
.else
    .byte '`'
.endif
.repeat $1F, index
    .byte $61 + index
.endrepeat

;; Writes a 500 baud pulse: positive, then negative, then back to rest, and waits out the rest of half a cell.
CTPULS:
    LD A,$01
    OUT [CASSETTE_PORT],A
    LD B,$0D
CTPULS_1:
    DJNZ CTPULS_1
    LD A,$02
    OUT [CASSETTE_PORT],A
    LD B,$0D
CTPULS_2:
    DJNZ CTPULS_2
    CALL CTSTAT
    LD B,$78
CTPULS_3:
    DJNZ CTPULS_3
    RET

;; Stops the motor after CLOAD? finds a difference.
;; Out:   HL = the BAD message
CTOFFX:
    LD HL,NOOKCS

;; Stops the motor, and puts back the interrupts the tape turned off.
CASOFZ:
    LD A,[MSKSTA]
    OUT [INTERRUPT_PORT],A
    IN A,[CASSETTE_PORT]            ; clears the cassette's interrupts
    LD A,[IOSTAT]
    AND $FD
    CALL CASET
    EI
    RET

;; Starts the motor, clears the tape's marks from the screen, and waits half a second for the tape to come up to
;; speed.
;; Keeps: BC, DE, HL
CTON:
    EX DE,HL
    EX [SP],HL                      ; DE on the stack, the return address in HL
    PUSH BC
    PUSH HL
    EX DE,HL
    IN A,[OPTIONS_PORT]             ; acknowledges the clock
    LD DE,$2020                     ; two spaces
    LD [CASSETTE_STATUS_CHAR],DE
    CALL CTON0
    LD BC,$7D00                     ; about half a second
    JP DELAY

;; Starts the motor.
CTON0:
    LD A,[IOSTAT]
    OR $02

;; Writes OPTIONS_PORT and its copy in IOSTAT.
;; In:    A = the value
CASET:
    LD [IOSTAT],A
    OUT [OPTIONS_PORT],A
    RET

;; Puts the cassette output at rest, which also clears the 500 baud input latch.
CTSTAT:
    XOR A
CTCHG:
    OUT [CASSETTE_PORT],A
    RET

;; Takes the #-n and comma of PRINT #-n and INPUT #-n, which go to the 500 baud routine whatever the speed; without
;; a #, SWTC1 chooses the speed.
;; In:    HL = the text, the routine's vector on the stack
LK:
    LD A,[HL]
    SUB '#'
    JP NZ,SWTC1
    CALL GETINT
    RST $08
    .byte ','
    RET

;; Reads a byte at 500 baud.
;; Out:   A = the byte
RDATA:
    LD B,8
CTBO:
    CALL CTBIT
    DJNZ CTBO

;; Blinks the asterisk at the top right every 32 bytes.
;; In:    D = the byte
;; Out:   A = the byte
CTB1:
    LD A,[BLINK]
    INC A
    AND $5F
    LD [BLINK],A
    JR NZ,CTB2
    LD A,[CASSETTE_BLINK_CHAR]
    XOR $0A                         ; between * and a space
    LD [CASSETTE_BLINK_CHAR],A
CTB2:
    LD A,D
    JR EXITBC

;; Reads a 500 baud bit into D: waits for the clock pulse, then looks for a data pulse a half cell later. BREAK
;; gives up.
;; In:    D = the bits so far
;; Out:   D = shifted left, with the bit at the bottom
CTBIT:
    PUSH BC
CB0:
    IN A,[CASSETTE_PORT]
    RLA
    JR C,CB1
    CALL BRKCHK
    JR Z,CB0
    JP ABORT
CB1:
    LD B,$6E                        ; past the clock pulse
CB2:
    DJNZ CB2
    CALL CTSTAT
    LD B,$98                        ; to the data pulse
CB3:
    DJNZ CB3
    IN A,[CASSETTE_PORT]
CB4:
    POP BC
    RLA
    RL D
    JR CTSTAT

;; Writes the byte in A at 500 baud: a clock pulse for each bit, and a data pulse after it for a 1.
;; In:    A = the byte
;; Keeps: AF, BC, DE
WDATA:
    PUSH AF
    PUSH BC
    PUSH DE
    LD C,8
    LD D,A
BYT0:
    CALL CTPULS
    RLC D
    JR NC,BYT2
    CALL CTPULS
BYT1:
    DEC C
    JR NZ,BYT0
EXITD:
    POP DE
EXITB:
    POP BC
    POP AF
    RET
BYT2:
    LD B,$9A                        ; a 0 waits out the time of the data pulse
BYT3:
    DJNZ BYT3
    JR BYT1

;; Writes the 500 baud leader of zero bytes and the $A5 sync byte, and makes WDATA the tape writer.
;; Keeps: HL
WSYNC:
    PUSH HL
    LD HL,WDATA
    LD [WRILOC],HL
    LD B,$53
    XOR A
CSAV1:
    CALL WDATA
    DJNZ CSAV1
    LD A,$A5
    CALL WDATA
    JR EXITH

;; Waits for a 500 baud leader of 64 zero bits and the $A5 sync byte, shows ** at the top right, and makes RDATA the
;; tape reader.
;; Keeps: HL
RSYNC:
    PUSH HL
    LD HL,RDATA
    LD [REDLOC],HL
HEADR:
    LD B,64
    LD D,$00
HEADR1:
    CALL CTBIT
    LD A,D
    OR A
    JR NZ,HEADR                     ; a 1: start counting again
    DJNZ HEADR1
CLOD1:
    CALL CTBIT
    LD A,D
    CP $A5
    JR NZ,CLOD1
CLOD2:
    LD HL,$2A2A                     ; **
    LD [CASSETTE_STATUS_CHAR],HL
    LD A,H
EXITH:
    POP HL
EXITBC:
    POP BC
    POP DE
    RET

;; Writes the 1500 baud leader of 256 $55 bytes and the $7F sync byte, and makes DATAW the tape writer. The $A5 in
;; A on return is the 500 baud sync byte, which CLOAD then writes, as a 500 baud tape has it.
;; Keeps: HL
SYNCW:
    PUSH HL
    LD HL,DATAW
    LD [WRILOC],HL
    LD B,0
SYNLP1:
    LD A,$55
    CALL DATAWA
    DJNZ SYNLP1
    LD A,$7F
    CALL DATAWA
    LD A,$A5
    JR EXITH

;; Writes a byte at 1500 baud without its start bit, for the leader.
DATAWA:
    PUSH AF
    PUSH BC
    PUSH DE
    LD C,A
    JR DATAW1

;; Writes the byte in A at 1500 baud: a 0 start bit, then the bits from the top.
;; In:    A = the byte
;; Keeps: AF, BC, DE
DATAW:
    PUSH AF
    PUSH BC
    PUSH DE
    LD C,A
    CALL BIT0
DATAW1:
    LD B,8
DATAW2:
    CALL BITOUT
    DJNZ DATAW2
    JR EXITD

;; Reads a byte at 1500 baud: its start bit, then eight.
;; Out:   A = the byte
DATAR:
    CALL SEEK
    LD B,8
DATAR1:
    CALL SEEK
    CALL CONVRT
    DJNZ DATAR1
    JP CTB1

;; Waits for a 1500 baud leader and the $7F sync byte, shows ** at the top right, and makes DATAR the tape reader.
;; The leader's cycles tell which edge to time from: the edge whose intervals are steady.
;; Keeps: HL
SYNCR:
    PUSH HL
    LD HL,DATAR
    LD [REDLOC],HL
    LD A,INT_CASSETTE_RISE
    OUT [INTERRUPT_PORT],A
BAD:
    LD B,128                        ; 128 cycles of the leader's length in a row
LOOK:
    CALL SEEK
    LD A,C
    CP LOWCT
    JR C,BAD
    CP HIGHCT
    JR NC,BAD
    DJNZ LOOK
EDGE:
    LD HL,$0000                     ; H counts steady rising edges, L uneven ones
    LD B,64
EDGE1:
    CALL SEEK
    CALL SEEK
    LD D,C
    CALL SEEK
    LD A,D
    SUB C
    JR NC,EDGE2
    NEG
EDGE2:
    CP HALF_DIFFERENCE
    JR C,INCL
INCH:
    INC H
    DJNZ EDGE1
    JR CHEZK
INCL:
    INC L
    DJNZ EDGE1
CHEZK:
    LD A,64
    CP H
    JR Z,SETFR                      ; the rising edges are steady
    CP L
    JR NZ,EDGE                      ; neither is steady: count again
SETF:
    LD A,INT_CASSETTE_FALL          ; time from the falling edges instead
    OUT [INTERRUPT_PORT],A
    CALL SEEK
SETFR:
    LD D,$00
FDSYNC:
    CALL SEEK
    CALL CONVRT
    LD A,D
    CP $7F
    JR NZ,FDSYNC
    JP CLOD2

;; Writes the top bit of C at 1500 baud: one cycle, high then low, short for a 1 and long for a 0.
;; In:    C = the bits
;; Out:   C = rotated left
BITOUT:
    RLC C
    JR NC,BIT0
BIT1:
    LD DE,$1217                     ; a 1: 18 and 23 passes
    JR BIT3
BIT0:
    LD DE,$2B2F                     ; a 0: 43 and 47 passes
BIT3:
    DEC D
    JR NZ,BIT3
    LD A,$02
    OUT [CASSETTE_PORT],A
BIT4:
    DEC E
    JR NZ,BIT4
    LD A,$01
    OUT [CASSETTE_PORT],A
    RET

;; Counts until the tape's next edge interrupts: RCASIN or FCASIN then returns past SEEK's caller's call. BREAK
;; gives up.
;; Out:   C = the count, which CONVRT turns into a bit
SEEK:
    EI
    LD C,$00
SEEK1:
    INC C
    LD A,[KEYBOARD_ROW6]
    AND $04
    JR Z,SEEK1
    DI

;; Gives up a tape on BREAK: shows BK at the top right and goes to BREAK_VECTOR.
ABORT:
    LD HL,'B' | ('K' << 8)
    LD [CASSETTE_STATUS_CHAR],HL
    JP BREAK_VECTOR

;; The tape's signal rose, through POLL.
RCASIN:
    LD E,$01
    JR CASINT

;; The tape's signal fell, through POLL.
FCASIN:
    LD E,$00

;; Ends SEEK's count when the level matches the edge, returning to SEEK's caller; a glitch lets SEEK go on.
;; In:    E = the level the edge leaves, C = SEEK's count, AF and SEEK's return on the stack
CASINT:
    LD A,6                          ; the time the interrupt took
    ADD A,C
    LD C,A
    IN A,[CASSETTE_PORT]
    AND $01
    CP E
    JR NZ,EXTRA
    POP AF
    POP AF                          ; drop the interrupt's return, into SEEK's loop
    RET
EXTRA:
    POP AF
    EI
    RET

;; Shifts the bit a count stands for into D: a short cycle is a 1. A count out of range shows D at the top right.
;; In:    C = the count, D = the bits so far
;; Out:   D = shifted left, with the bit at the bottom
CONVRT:
    LD A,C
    CP HALF
    RL D
    CP LOWCT
    JR C,ERROR1
    CP HIGHCT
    RET C
ERROR1:
    LD A,'D'
    LD [CASSETTE_STATUS_CHAR],A
    RET

.if MODEL = 4
;; The keyboard driver: returns the character of a newly pressed key, or of a held key when it repeats. A newly
;; pressed function key on row 7 returns its code from RAM: F1 FKEY1, F2 FKEY2 and F3 FKEY3. CAPS turns shift lock
;; on or off, and CTRL, or shift and the down arrow, is control.
;; Out:   A = the character, or zero for none
KEYBD:
    LD HL,FKEYS
    LD A,[SHFKEY]
    AND $7C                         ; CTRL, CAPS, F1, F2 and F3
    OR A
    JR Z,NOFKEY
    LD E,A
    XOR [HL]
    LD [HL],E
    AND E
    JR Z,KEYSCN                     ; none just went down
    LD BC,1476                      ; about 22 ms
    CALL DELAY
    LD A,[SHFKEY]
    AND $7C
    CP E
    JP NZ,EXITNK                    ; it bounced
    RLA
    RLA
    JR NC,FKEY2_1
    LD A,[FKEY3]
    RET
FKEY2_1:
    RLA
    JR NC,FKEY1_1
    LD A,[FKEY2]
    RET
FKEY1_1:
    RLA
    JR NC,CAPKEY
    LD A,[FKEY1]
    RET
CAPKEY:
    RLA
    JP C,FLPFLP
    JR KEYCTL                       ; CTRL
NOFKEY:
    LD [HL],A
    LD A,$FF
    LD HL,DNAROW
    BIT DARW,[HL]
    JR Z,NOCTRL
    SLA L                           ; the shift keys' row
    BIT SKEY,[HL]
    JR Z,NOCTRL
KEYCTL:
    LD A,$1F                        ; control: letters become $01-$1A
NOCTRL:
    LD [CNTFLG],A
KEYSCN:
    CALL KSCAN
    RET NC
    CALL KEYXLT
    CP $1A                          ; shift and the down arrow: control, not a key
    JP Z,EXITNK
    OR A                            ; shift and 0
    JP Z,FLPFLP
    LD HL,CNTFLG
    BIT 7,[HL]
    JR NZ,KEYBRK                    ; no control
    CP '*'
    JP Z,GOSCRP
    AND [HL]                        ; with control, letters become control codes
KEYBRK:
    CP $01
    RET NZ
    RST $28                         ; BREAK: a DOS request
    RET

.else
;; The keyboard driver: returns the character of a newly pressed key, or of a held key when it repeats. Pressing
;; the right shift key alone, on machines whose shift keys work separately, turns shift lock on or off. Shift and
;; the down arrow is control.
;; Out:   A = the character, or zero for none
KEYBD:
    CALL CHKEQU
    JR NZ,KEYBD1                    ; one shift key
    LD BC,SHFKEY
    LD HL,SKROB
    LD A,[BC]
    AND $02                         ; the right shift key
    LD E,A
    XOR [HL]
    LD [HL],E
    AND E
    JP NZ,FLPFLP                    ; it just went down
KEYBD1:
    LD A,$FF
    LD HL,DNAROW
    BIT DARW,[HL]
    JR Z,NOCTRL
    SLA L                           ; the shift keys' row
    BIT SKEY,[HL]
    JR Z,NOCTRL
    LD A,$1F                        ; control: letters become $01-$1A
NOCTRL:
    LD [CNTFLG],A
    LD BC,KBROW
    LD HL,KEYBOARD_IMAGE
    LD D,$00
KLOOP1:
    LD A,[BC]
    LD E,A
    XOR [HL]
    LD [HL],E
    AND E                           ; the keys that just went down
    JR NZ,KEYDWN
    CALL BUMP
    JP P,KLOOP1
    CALL GETRC
    AND [HL]
    JR NZ,REPKEY                    ; the last key is still down
    SBC HL,HL
    LD [TCOUNT],HL
    JP NOKEY

;; A key is held: counts the scans, and repeats it when they reach TDELAY, faster after the first time.
REPKEY:
    PUSH HL
    LD HL,[TCOUNT]
    INC HL
    LD [TCOUNT],HL
    LD DE,[TDELAY]
    SBC HL,DE
    POP DE
    JP C,EXITNK
    XOR A
    LD [DE],A                       ; forget the key, so the scan finds it again
    LD [TCOUNT],HL
    LD L,150
    LD [TDELAY],HL
    JR KEYBD1

;; A key went down: debounces it and finds its number.
;; In:    A = its bit, BC = its row, D = the row's first key, L = its place in KEYBOARD_IMAGE
KEYDWN:
    LD E,A
    PUSH BC
    LD BC,1476                      ; about 22 ms
    CALL DELAY
    POP BC
    LD A,[BC]
    AND E
    RET Z                           ; it bounced
    LD [LCOL],A
    LD A,L
    LD [LROW],A
NEWKEY:
    LD A,D
    RLA
    RLA
    RLA
    LD D,A
    LD A,E
KLOOP2:
    RRCA
    JR C,CHKSHF
    INC D
    JR KLOOP2

;; Adds shift and shift lock to the key number, and translates it through KBTAB.
CHKSHF:
    CALL CHKEQU
    LD A,[SHFKEY]
    JR NZ,EQU                       ; either shift key
    AND $01                         ; only the left one: the right is shift lock
EQU:
    AND $03
    JR Z,CHSHLK
    SET 6,D
CHSHLK:
    LD A,[SHFLCK]
    OR A
    JR Z,DONE
    SET 7,D
DONE:
    LD HL,KBTAB
    LD E,D
    LD D,$00
    ADD HL,DE
    LD A,[HL]
    CP $1A                          ; shift and the down arrow: control, not a key
    JP Z,EXITNK
    LD B,A
    CALL CHKEQU
    LD A,B
    JR Z,DONE1
    OR A                            ; shift and 0
    JP Z,FLPFLP
DONE1:
    LD HL,CNTFLG
    CP '*'
    JR NZ,DONE2
    LD A,$1F
    CP [HL]                         ; zero for control-*
    LD A,B
DONE2:
    JP CHKBRK

.endif

;; Starts the machine: sets up the hardware, copies the RAM image, clears the screen, and boots a disk unless BREAK
;; is held or there is no disk controller, or else asks for the cassette's speed and starts BASIC. The Model 4 first
;; clears the 6845's registers, so the display starts at the top of video RAM.
;; In:    A = 0
INITZ:
    IM 1
    LD SP,MSTACK
.if MODEL = 4
    LD B,15
    LD C,CRTC_ADDRESS_PORT
CRTCLR:
    OUT [C],B
    OUT [CRTC_DATA_PORT],A
    DJNZ CRTCLR
.endif
    OUT [NMI_PORT],A                ; no NMIs
    OR $20
    OUT [OPTIONS_PORT],A            ; video wait, 64 characters, cassette off
    LD A,DRIVE_0_DOUBLE
    OUT [DRIVE_SELECT_PORT],A
    LD A,$D0                        ; force interrupt: stop anything the controller was doing
    OUT [FDC_STATUS_PORT],A
.if ROMC = 'B'
    CALL STALL
.else
    PUSH BC                         ; STALL's delay, without the call
    POP BC
    NOP
.endif
    LD A,INT_CLOCK
    OUT [INTERRUPT_PORT],A
    LD A,$0B                        ; restore: back to track 0
    OUT [FDC_STATUS_PORT],A
    LD HL,RAM_VECTORS
    LD DE,RST08_VECTOR
    LD BC,RAM_VECTORS_END - RAM_VECTORS
    LDIR
    LD HL,RAM_RS232
    LD DE,RS232_INPUT_DCB
    LD BC,RAM_RS232_END - RAM_RS232
    LDIR
    CALL CLS
    CALL BRKCHK
    JP NZ,CASMSG                    ; BREAK: BASIC
    IN A,[FDC_STATUS_PORT]
    INC A
    JP Z,CASMSG                     ; no controller: BASIC

;; Waits up to about a second for the head to reach track 0, or starts BASIC.
DOBOOT:
    LD BC,$0000
INIT1:
    DEC BC
    LD A,DRIVE_0_DOUBLE             ; keeps the motor turning
    OUT [DRIVE_SELECT_PORT],A
    LD A,B
    OR C
    JP Z,CASMSG
    IN A,[FDC_STATUS_PORT]
    BIT 2,A
    JR Z,INIT1

;; Boots drive 0: waits for five index holes, showing Diskette? while none come, then reads sector 1 of track 0 to
;; BOOT_BUFFER and runs it. The read takes each byte with INI, the drive select's wait holding the Z80 until the
;; byte is ready, until the controller's NMI ends it at INTUPT.
BOOTZZ:
    LD E,5
BOOTZX:
    LD BC,$0000
BOOTZY:
    IN A,[FDC_STATUS_PORT]
    BIT 1,A                         ; the index hole
    JR NZ,BOOTZW
    DEC BC
    LD A,DRIVE_0_DOUBLE
    OUT [DRIVE_SELECT_PORT],A
    LD A,B
    OR C
    JR NZ,BOOTZY
    LD HL,DSKMSG
    CALL VDLINE
    JR BOOTZZ
BOOTZW:
    DEC E
    JR NZ,BOOTZX
RETRY:
    LD A,DRIVE_0_DOUBLE
    OUT [DRIVE_SELECT_PORT],A
    LD HL,INTUPT
    LD [NMI_VECTOR + 1],HL
    LD A,$C3                        ; JP INTUPT
    LD [NMI_VECTOR],A
    LD A,NMI_DISK
    OUT [NMI_PORT],A
    LD BC,FDC_DATA_PORT             ; B = 0: INI never stops
    LD HL,BOOT_BUFFER
    LD A,1
    OUT [FDC_SECTOR_PORT],A
    LD A,$80                        ; read sector
    OUT [FDC_STATUS_PORT],A
    CALL STALL
VLOOP:
    IN A,[FDC_STATUS_PORT]
    AND $02
    JP Z,VLOOP
    INI
BOOTLP:
    LD A,DRIVE_0_DOUBLE
    OR DRIVE_WAIT
    OUT [DRIVE_SELECT_PORT],A
    INI
    JP BOOTLP

;; The read ended: runs the boot sector, or reads it again after an error.
INTUPT:
    XOR A
    OUT [NMI_PORT],A
    LD HL,$45ED                     ; RETN, at NMI_VECTOR
    LD [NMI_VECTOR],HL
    CALL STALL
    IN A,[FDC_STATUS_PORT]
    POP HL                          ; the NMI's return into BOOTLP
    AND $1C                         ; not found, CRC error or lost data
    JP Z,BOOT_BUFFER
    JR RETRY

.if MODEL = 3

;; Waits a few microseconds for the disk controller.
STALL:
    PUSH BC
    POP BC
    NOP
    RET
.endif

;; DOSIT's ending: a disk NMI goes to NMI_VECTOR, and reset waits for the button to be let go and restarts.
;; In:    zero = set for reset
DOINIT:
    JP NZ,NMI_VECTOR
DOINI1:
    IN A,[NMI_PORT]
    BIT 5,A
    JR Z,DOINI1
    JP RESET
.if MODEL = 4

;; Adds shift and shift lock to the key number, and translates it through KBTAB. Shift cancels shift lock.
;; In:    D = the key number
;; Out:   A = the character
KEYXLT:
    LD A,[SHFKEY]
    AND $03
    JR Z,KEYXL1
    SET 6,D
KEYXL1:
    LD A,[SHFLCK]
    OR A
    JR Z,KEYXL2
    SET 7,D
    LD A,[SHFKEY]
    AND $03
    JR Z,KEYXL2
    RES 7,D
KEYXL2:
    LD HL,KBTAB
    LD E,D
    LD D,$00
    ADD HL,DE
    LD A,[HL]
    RET

;; Prints the screen on the printer, a row to a line, with each graphics character as a period; codes from $C0
;; print as they are.
PRTSCR:
    LD HL,VIDEO
PRTSC1:
    LD A,[HL]
    RLCA
    JR NC,PRTSC2
    RLCA
    JR C,PRTSC2
    LD A,'.'
    JR PRTSC3
PRTSC2:
    LD A,[HL]
PRTSC3:
    CALL PRINTER_CHAR
    INC HL
    BIT 6,H
    JP NZ,SCREND
    LD A,L
    AND $3F
    JR NZ,PRTSC1
    CALL SCREND
    JR PRTSC1
    .res 10, $00
.else
    RST $38                         ; never reached
.endif

;; The real-time clock's interrupt, 30 times a second through CLOCK_VECTOR: blinks the cursor every seven ticks,
;; counts the time and date each second, and shows the time at the top right when CLOCKN has turned it on.
CLOCKZ:
    LD DE,CLKOUT
    PUSH DE
    IN A,[OPTIONS_PORT]             ; acknowledges the clock
    LD A,[CURCAR]
    OR A
    JR Z,CLOCK5                     ; the cursor is off
    LD A,[BLKON]
    OR A
    JR NZ,CLOCK5                    ; it does not blink
    LD HL,BLKCNT
    DEC [HL]
    JR NZ,CLOCK5
    LD [HL],7
    INC HL
    LD A,[HL]
    AND $01
    XOR $01
    LD [HL],A
    LD HL,[CURSOR_ADDRESS]
    JR Z,CLOCK4
    LD A,[CURSOR_CHAR]
    JR CLOCK3
CLOCK4:
    LD A,' '
CLOCK3:
    LD [HL],A
CLOCK5:
    LD HL,TICKIT
    DEC [HL]
    RET NZ
    LD [HL],30
    INC HL
    LD DE,MAXTIM
    LD B,3
TIMLOP:
    INC [HL]                        ; seconds, then minutes, then hours
    LD A,[DE]
    SUB [HL]
    RET NZ
    LD [HL],A
    INC HL
    INC DE
    DJNZ TIMLOP
    INC HL
    INC [HL]                        ; the day
    INC HL
    LD A,[HL]
    DEC HL
    DEC A
    ADD A,E                         ; the month's length in MAXTIM
    LD E,A
    LD A,[DE]
    CP [HL]
    RET NC
    LD A,[HL]
    CP 30
    JR NC,DAYRST
    DEC HL                          ; February's 29th: a leap year keeps it
    LD A,[HL]
    INC HL
    AND $03
    RET Z
DAYRST:
    LD [HL],1
    INC HL
    INC [HL]                        ; the month
    LD A,[HL]
    SUB 13
    RET C
    LD [HL],1
    DEC HL
    DEC HL
    INC [HL]                        ; the year
    RET

;; Shows the time at the top right when a second has passed, if CLOCKN turned it on.
CLKOUT:
    LD A,[IOSTAT]
    BIT 0,A
    RET Z
    LD A,[TICKIT]
    CP 30
    RET NZ
CLKTRA:
    LD HL,VIDEO + $35

;; Writes the time as HH:MM:SS.
;; In:    HL = where
;; Out:   HL = past it
RTCLK:
    LD DE,HOUR
    LD C,':'
RTCLK1:
    LD B,3
RTLOOP:
    LD A,[DE]
    DEC DE
    LD [HL],'0' - 1
RTLOP1:
    INC [HL]                        ; the tens
    SUB 10
    JR NC,RTLOP1
    ADD A,'0' + 10
    INC HL
    LD [HL],A
    INC HL
    DEC B
    RET Z
    LD [HL],C
    INC HL
    JR RTLOOP

;; Writes the date as MM/DD/YY.
;; In:    HL = where
;; Out:   HL = past it
RTDAT:
    LD DE,MONTH
    LD C,'/'
    JR RTCLK1

;; The maskable interrupt, through RST $38: reads which devices interrupted and goes to the first one's routine.
;; The cassette's edges go straight to RCASIN and FCASIN; the others return through POLDON.
POLL:
    PUSH AF
    IN A,[INTERRUPT_PORT]
    RRA
    JP NC,RCASIN
    RRA
    JP NC,FCASIN
    PUSH BC
    PUSH DE
    PUSH HL
    PUSH IX
    PUSH IY
    LD HL,POLDON
    PUSH HL
    RRA
    JP NC,CLOCK_VECTOR
    RRA
    JP NC,IO_BUS_VECTOR
    RRA
    JP NC,RS232_RECEIVE_VECTOR
    RRA
    JP NC,RS232_TRANSMIT_VECTOR
    RRA
    JP NC,RS232_ERROR_VECTOR
    RRA
    JP NC,INTERRUPT7_VECTOR
NOPOLL:
    POP HL                          ; none: a glitch
POLDON:
    POP IY
    POP IX
    POP HL
    POP DE
    POP BC
    POP AF
    EI
POLOUT:
    RET

;; The RS-232 set-up driver: sets the baud rate and the UART's control from the set-up block, and turns the input
;; and output drivers on, waiting for each byte or not. A zero control, or no RS-232 board, turns them off.
;; In:    IX = RS232_INIT_DCB: +3 the baud rate, +4 the UART's control, +5 nonzero to wait
RSINIT:
    DI
    IN A,[RS232_STATUS_PORT]
    CP $FF
    JR Z,RSOFF                      ; no RS-232 board
RSINI0:
    XOR A
    OUT [RS232_RESET_PORT],A
    LD A,[IX+$03]
    OUT [RS232_BAUD_PORT],A
    LD A,[IX+$04]
    OR A
    JR Z,RSOFF
    OUT [RS232_STATUS_PORT],A
    LD IY,RS232_INPUT_DCB
    CALL CLEAN
    LD A,[IX+$05]
    OR A
    JR Z,RSN00
    SET 1,[IY+$04]                  ; wait for each byte
RSN00:
    SET 2,[IY+$04]                  ; on
    LD IY,RS232_OUTPUT_DCB
    OR A
    JR Z,RSN01
    SET 1,[IY+$04]
RSN01:
    SET 2,[IY+$04]
RSN02:
    IN A,[RS232_RESET_PORT]         ; clears any interrupt the set-up caused
    EI
    RET

;; Turns the RS-232 port and its drivers off.
RSOFF:
    XOR A
    LD B,4
    LD C,RS232_RESET_PORT
RSOFF0:
    OUT [C],A
    INC C
    DJNZ RSOFF0

;; Clears the RS-232 input and output blocks' buffer, flags and error.
CLEAN:
    LD HL,RS232_INPUT_BUFFER
    LD B,3
RSOFF1:
    LD [HL],$00
    INC HL
    DJNZ RSOFF1
    LD HL,RS232_OUTPUT_BUFFER
    LD B,3
RSOFF2:
    LD [HL],$00
    INC HL
    DJNZ RSOFF2
    JR RSN02

;; The RS-232 input driver: a byte received, or zero, waiting for one if the block says to. BREAK gives up.
;; Out:   A and the block's buffer = the byte
RSIN:
    LD IX,RS232_INPUT_DCB
    XOR A
    LD [IX+$03],A
    BIT 2,[IX+$04]
    RET Z                           ; off
RSINLP:
    IN A,[RS232_STATUS_PORT]
    BIT 7,A                         ; a byte received
    JR NZ,RSINL1
    BIT 1,[IX+$04]
    RET Z                           ; not waiting
    CALL BRKCHK
    JR Z,RSINLP
    JP BREAK_VECTOR
RSINL1:
    IN A,[RS232_DATA_PORT]
    LD [IX+$03],A
    RET

;; The RS-232 output driver: sends the block's buffer, or the byte in C when it is empty, waiting for the UART if
;; the block says to. BREAK gives up.
;; In:    C = the byte
RSOUT:
    LD IX,RS232_OUTPUT_DCB
    BIT 2,[IX+$04]
    RET Z                           ; off
RSLOOP:
    IN A,[RS232_STATUS_PORT]
    BIT 6,A                         ; ready to send
    JR NZ,RSLOP1
    BIT 1,[IX+$04]
    RET Z
    CALL BRKCHK
    JR Z,RSLOOP
    JP BREAK_VECTOR
RSLOP1:
    LD A,[IX+$03]
    OR A
    JR NZ,RSLOP2
    LD A,C
RSLOP2:
    OUT [RS232_DATA_PORT],A
    LD [IX+$03],$00
    RET

;; The RAM image INITZ copies to $4000: the RST vectors, the keyboard, video and printer control blocks, and the DOS
;; and interrupt vectors.
RAM_VECTORS:
    JP SYNCHK                       ; RST08_VECTOR
RT2:
    JP CHRGTR                       ; RST $10
RT3:
    JP DCOMPR                       ; RST $18
RT4:
    JP GETYPR                       ; RST $20
RT5:
    RET                             ; RST $28: DOS requests, which BASIC ignores
    NOP
    NOP
RT6:
    RET                             ; RST $30
    NOP
    NOP
RT7:
    JP POLLZ                        ; RST $38: the interrupts

;; The keyboard, video and printer control blocks, which SETDCB also restores.
RAM_DCBS:
    .byte $01                       ; KEYBOARD_DCB: type 1, input
    .word KEYBDZ
    .byte $00                       ; SKROB
    .byte $01                       ; SHFLCK: on
    .byte $07                       ; BLKCNT
    .byte $00                       ; BLKFLG
    .byte $00                       ; BLKON: blinking
    .byte $07                       ; VIDEO_DCB: type 7, input, output and control
    .word VIDEOZ
    .word VIDEO                     ; CURSOR_ADDRESS
    .byte $00                       ; CURCAR: the cursor is off
    .byte $B0                       ; CURSOR_CHAR: a block
    .byte $00                       ; CURSWT
    .byte $06                       ; PRINTER_DCB: type 6, output and control
    .word PRINTZ
    .byte 67                        ; lines a page, plus one
    .byte 1                         ; the line
    .byte 0                         ; the column
    .byte $FF                       ; the width: none
.if MODEL = 4
    .byte $00
.else
    .byte 'R'
.endif

;; DOS vectors.
RAM_DOS_VECTORS:
    JP DOS_EXIT_DEFAULT             ; DOS_EXIT_VECTOR
ABORTZ:
    RST $00                         ; DOS_ABORT_VECTOR
    NOP
    NOP
CIOEX:
    XOR A                           ; DCB_REQUEST_HOOK: nothing to do without a DOS
    RET
    NOP
.if MODEL = 4
    .res 7, $00                     ; KEYBOARD_IMAGE
.else
    .byte $AA, $AA, $AA, $AA, $AA, $AA, $AA ; KEYBOARD_IMAGE
.endif
IODRVZ:
    JP POLOUT                       ; IO_BUS_VECTOR
POL6ZZ:
    JP POLOUT                       ; RS232_ERROR_VECTOR
POL7ZZ:
    JP POLOUT                       ; INTERRUPT7_VECTOR
CLKZZ:
    JP CLOCKZ                       ; CLOCK_VECTOR
DOS:
    RST $00                         ; NMI_VECTOR: restarts until a DOS takes the disk's NMI
    NOP
    NOP
RAM_VECTORS_END:
.assert RAM_VECTORS_END - RAM_VECTORS = NMI_VECTOR + 3 - RST08_VECTOR, "The image ends with NMI_VECTOR."
    .byte $00, $00, $00

;; The RAM image INITZ copies to $41E5: the RS-232 control blocks, the keyboard's repeat, the vectors for BREAK and
;; the UART, the tape's routines and state, the clock and the router.
RAM_RS232:
    .byte $01                       ; RS232_INPUT_DCB: type 1, input
    .word RSINZ
    .byte $00, $00, $00             ; the byte, flags, error
.if MODEL = 4
    .byte '`', $1B                  ; FKEY1 and FKEY2: F1 is `, F2 escape
.else
    .byte "RI"
.endif
    .byte $02                       ; RS232_OUTPUT_DCB: type 2, output
    .word RSOUTZ
    .byte $00, $00, $00
.if MODEL = 4
    .byte $08, $00                  ; FKEY3, a backspace, and FKEYS
.else
    .byte "RO"
.endif
    .byte $02                       ; RS232_INIT_DCB
    .word RSINIZ
    .byte $55                       ; 300 baud
    .byte $6C                       ; eight bits, one stop bit, no parity
    .byte $FF                       ; wait
.if MODEL = 4
    .byte $00, $00
.else
    .byte "RN"
.endif
RAM_RS232_DCBS_END:
    .byte $00                       ; LROW
    .byte $00                       ; LCOL
    .word $FFFF                     ; TDELAY
    .word $0000                     ; TCOUNT
    JP BASIC                        ; BREAK_VECTOR
    JP POLOUT                       ; RS232_RECEIVE_VECTOR
    JP POLOUT                       ; RS232_TRANSMIT_VECTOR
    .word WDATA                     ; WRILOC
    .word RDATA                     ; REDLOC
    .byte $28                       ; IOSTAT
    .byte $03                       ; CASDCB: 1500 baud
    .byte $3C                       ; BLINK
    .byte INT_CLOCK                 ; MSKSTA
    .byte $00                       ; SCRLCT
    .byte $00                       ; MSKSAV
    .byte 30                        ; TICKIT
    .byte $00, $00, $00, $00, $00, $00 ; the time and date
.if MODEL = 4
    .byte $00, $00, $00             ; ROUTE_DCB: no router
.else
    .byte $02                       ; ROUTE_DCB
    .word DOROT
.endif
    .word $0000                     ; ROUTE_SOURCE
    .word $0000                     ; ROUTE_DESTINATION
    .byte $FF                       ; CNTFLG
RAM_RS232_END:
.assert RAM_RS232_END - RAM_RS232 = CNTFLG + 1 - RS232_INPUT_DCB, "The image fills $41E5-$4224."

.if MODEL = 4
;; Scans the keyboard's rows 0-6 for a key that just went down, debounces it and returns its number, or repeats the
;; key last pressed when it has been held long enough, faster after the first time.
;; Out:   carry = set with D = the key number, else A = 0
KSCAN:
    LD BC,KBROW
    LD HL,KEYBOARD_IMAGE
    LD D,$00
KLOOP1:
    LD A,[BC]
    LD E,A
    XOR [HL]
    LD [HL],E
    AND E                           ; the keys that just went down
    JR NZ,KEYDWN
    INC D                           ; the next row's first key
    INC HL
    RLC C
    JP P,KLOOP1
    LD A,[LROW]
    LD L,A
    LD A,[LCOL]
    AND [HL]
    JP NZ,REPKEY                    ; the last key is still down
    SBC HL,HL
    LD [TCOUNT],HL
    LD HL,1500
    LD [TDELAY],HL
    XOR A
    RET

;; A key went down: debounces it and finds its number.
;; In:    A = its bit, BC = its row, D = the row, L = its place in KEYBOARD_IMAGE
KEYDWN:
    LD E,A
    PUSH BC
    LD BC,1476                      ; about 22 ms
    CALL DELAY
    POP BC
    LD A,[BC]
    AND E
    RET Z                           ; it bounced
    LD [LCOL],A
    LD A,L
    LD [LROW],A
    LD A,D
    RLA
    RLA
    RLA
    LD D,A
    LD A,E
KLOOP2:
    RRCA
    RET C
    INC D
    JR KLOOP2

;; A key is held: counts the scans, and repeats it when they reach TDELAY. The repeat goes back to NOFKEY with HL
;; no longer at FKEYS, so its store lands in ROM.
REPKEY:
    PUSH HL
    LD HL,[TCOUNT]
    INC HL
    LD [TCOUNT],HL
    LD DE,[TDELAY]
    SBC HL,DE
    POP DE
    JP C,EXITNK
    XOR A
    LD [DE],A                       ; forget the key, so the scan finds it again
    LD [TCOUNT],HL
    LD L,150
    LD [TDELAY],HL
    JP NOFKEY

.else
;; The router's driver, from ROUTE (RO at $006C): copies the type and driver of the device the route block's
;; second letter names (I, O or another device's letter) over those of the one its first letter names, so that
;; the first device's input or output goes to the second.
;; In:    IX = ROUTE_DCB: +3 the source's letters, +5 the destination's
DOROT:
    LD A,[IX+$03]
    CP 'R'
    JR NZ,ROUTE1
    LD A,[IX+$04]                   ; RI and RO go by their second letter
ROUTE1:
    CALL CHECK
    RET NZ
    PUSH HL
    LD A,[IX+$05]
    CP 'R'
    JR NZ,ROUTE2
    LD A,[IX+$06]
ROUTE2:
    CALL CHECK
    EX DE,HL
    POP HL
    RET NZ
    LD BC,3
    LDIR
    RET

;; Finds a device's control block by its letter.
;; In:    A = the letter
;; Out:   HL = the block, zero = set when found
CHECK:
    LD HL,ROTTAB
    LD BC,TABEND - ROTTAB
    CPIR
    RET NZ
GETADD:
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    RET

;; The devices the router knows, by letter.
ROTTAB:
    .byte 'K'
    .word KEYBOARD_DCB
    .byte 'D'
    .word VIDEO_DCB
    .byte 'P'
    .word PRINTER_DCB
    .byte 'I'
    .word RS232_INPUT_DCB
    .byte 'O'
    .word RS232_OUTPUT_DCB
TABEND:

.endif

;; Watches the character PLOOP copied: a quote turns RUBSW's quote bit over, and a colon outside quotes ends DATA.
;; In:    A = the character
CPATCH:
    CP '"'
    JR NZ,BFCHKC
    LD A,[RUBSW]
    XOR $01
    LD [RUBSW],A
    LD A,'"'
BFCHKC:
    CP ':'
    JP NZ,NTEMBL
    LD A,[RUBSW]
    RRA
    JP C,QTCOLN                     ; inside quotes
    RLA
    JP CPATC2

;; The TIME$ function: the date and time, as MM/DD/YY HH:MM:SS.
ZTIME:
    RST $10
    PUSH HL
    LD A,17
    CALL STRINI
    LD HL,[DSCTMP_PTR]
    CALL RTDAT
    LD [HL],' '
    INC HL
    CALL RTCLK
    JP PUTNEW

.if MODEL = 4
;; Turns shift lock on or off, and returns no key.
FLPFLP:
    LD A,$01
    LD HL,SHFLCK
    XOR [HL]
FLP1:
    LD [HL],A
EXITNK:
    XOR A
    RET

;; Waits a few microseconds for the disk controller.
STALL:
    PUSH BC
    POP BC
    NOP
    RET
    .byte $00, $00, $00             ; filler
    .byte $FF, $FF                  ; under the printer at $37E8, which hides them

.else
;; Asks for the cassette's speed, and goes on starting BASIC.
CASMSG:
    CALL CPRMPT
    JP INIT2

;; Asks Cass? until H (or ENTER) chooses 1500 baud or L chooses 500.
CPRMPT:
    EI
    CALL CR
    LD HL,CASSMG
    CALL VDLINE
    CALL KBWAIT
    CP $0D
    JR Z,CASMS1
    PUSH AF
    CALL DISPLAY_CHAR
    POP AF
    CP 'H'
    JR Z,CASMS1
    CP 'L'
    JR NZ,CPRMPT
    XOR A
CASMS1:
    LD [CASDCB],A

;; Shows a carriage return.
CR:
    LD A,$0D
    JP DISPLAY_CHAR

;; Points BASIC's TIME$ at DOTIME, and goes to READY.
SETTIM:
    LD HL,DOTIME
    LD [HOOK_TIME + 1],HL
    JP BASIC
    .byte $AA, $AA, $AA             ; filler
    .byte $AA, $AA                  ; under the printer at $37E8, which hides them

.endif

;; Nonzero when the two shift keys work separately, the right one being shift lock; the Model 4 has CAPS instead.
SHFEQU:
.if MODEL = 4
    .byte $00
.else
    .byte $01
.endif

;; Prints the banner at HL and the copyright, and sets up TIME$.
;; In:    HL = the banner
PRTNAM:
    CALL VDLINE
    LD HL,COPRIG
    CALL VDLINE
.if MODEL = 4
    LD HL,DOTIME                    ; points BASIC's TIME$ at DOTIME, and goes to READY
    LD [HOOK_TIME + 1],HL
    JP BASIC
    .byte $E5, $E5, $FF
.else
    JR SETTIM

;; The cassette prompt: the cursor on, then Cass?.
CASSMG:
    .byte $0E, "Cass? ", $03
    .byte $AA, $AA
.endif
.assert * = $3800, "ROM C ends at $37FF."
