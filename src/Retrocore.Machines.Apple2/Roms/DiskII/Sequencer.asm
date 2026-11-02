;; DISK II LOGIC STATE SEQUENCER (P6): THE COMMANDS, THE TABLES AND THE CHIP'S WIRING
;;
;; Shared by Sequencer13.asm and Sequencer16.asm, which include it, add their own reading table and end with
;; SEQUENCER. It holds the writing table, the same on both cards. docs/DiskII.md explains the controller as a
;; whole.
;;
;; The Disk II controller has no microprocessor. A small state machine, the logic state sequencer, moves bits
;; between the drive and an 8-bit shift register, the data latch (Sather's "data register"), while the 6502
;; reads or writes the latch a whole byte at a time. The machine is a 256-byte PROM and a 4-bit register
;; holding its state, clocked at 2 MHz, twice the 6502's speed. Each clock the PROM looks up the entry for the
;; current state and inputs. The entry's high four bits are the next state; its low four bits are a command for
;; the latch:
;;
;;   CLR   clear the latch (codes $0-$7)
;;   NOP   leave it alone ($8, also $C)
;;   SL0   shift it left, bringing in a 0 ($9)
;;   SL1   shift it left, bringing in a 1 ($D)
;;   SR    shift it right, bringing in the write-protect sensor as bit 7 ($A, also $E)
;;   LD    load it from the 6502's data bus ($B, also $F)
;;
;; Apple's tables use only the first code of each, so a name gives back the exact byte. The inputs are:
;;
;;   Q7, Q6  the mode the 6502 selected with the controller's Q6 and Q7 switches:
;;           Q7 off, Q6 off   read: shift in bits from the drive
;;           Q7 off, Q6 on    sense write protect: shift in the write-protect sensor
;;           Q7 on, Q6 off    write, shifting: shift bits out to the drive
;;           Q7 on, Q6 on     write, loading: load the next byte to write from the 6502
;;   QA      the latch's bit 7, which is 1 once a whole nibble has been shifted in, or while a 1 is to be written
;;   RP      the read pulse: 0 while the drive reports a flux transition passing under the head (it is
;;           active low), 1 otherwise. Sather writes these columns RP and NO RP.
;;
;; In reading, a flux transition within a bit's time is a 1 and none is a 0. The sequencer counts the time
;; since the last pulse, shifts in bits as they come, and holds a byte once its top bit is set so the 6502 can
;; see it, then clears the latch for the next. In writing, the state's top bit is the write signal to the
;; drive: each change of it is a flux transition. A pass through eight states takes 4 microseconds, one bit,
;; and the write signal changes at its end when QA is 1, before the latch shifts left to bring up the next bit.

; The entries. Each define makes one sequencer entry byte: the state to go to next in the high nibble and the
; command for the data latch in the low nibble.

;; A sequencer entry that clears the data latch to 0 and goes to {state}.
;;
;; The entry is command code $0. The chip treats $1-$7 as the same command, but Apple's tables use only $0.
;; The reading tables clear the latch once the 6502 has had time to read a complete nibble (QA set), so the
;; next nibble starts shifting into an empty latch.
;;
;; Example:
;; > CLR($A)   ; the byte $A0: clear the latch, then go to state $A
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <NOP>, <SL0>, <SL1>, <SR>, <LD>, <READING>, <WRITING>
.define CLR(state) ((state) << 4 | $0)

;; A sequencer entry that leaves the data latch alone and goes to {state}.
;;
;; The entry is command code $8 (Sather's NOP); $C is the same command, unused by Apple. Most entries are
;; NOP: while reading, the sequencer counts clocks from state to state waiting for the next read pulse, and
;; while writing it steps through its loop of eight states between shifts. A nibble held with QA set also
;; sits under NOP until the 6502 has read it.
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <CLR>, <SL0>, <SL1>, <SR>, <LD>, <READING>, <WRITING>
.define NOP(state) ((state) << 4 | $8)

;; A sequencer entry that shifts the data latch left, bringing in a 0 as bit 0, and goes to {state}.
;;
;; The entry is command code $9. In reading, it records a bit time that passed with no read pulse: a 0 bit.
;; In writing, it moves the next bit to write up into QA, the latch's bit 7, which decides whether the write
;; signal changes at the end of the next bit time.
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <SL1>, <CLR>, <NOP>, <SR>, <LD>, <READING>, <WRITING>
.define SL0(state) ((state) << 4 | $9)

;; A sequencer entry that shifts the data latch left, bringing in a 1 as bit 0, and goes to {state}.
;;
;; The entry is command code $D. Only reading uses it: the read states reach it after the drive reported a
;; read pulse, a flux transition, within the bit time, which is a 1 bit. Once the first 1 of a nibble reaches bit 7, QA is set
;; and the 6502 sees a complete nibble.
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <SL0>, <CLR>, <NOP>, <SR>, <LD>, <READING>
.define SL1(state) ((state) << 4 | $D)

;; A sequencer entry that shifts the data latch right, bringing in the write-protect sensor as bit 7, and goes
;; to {state}.
;;
;; The entry is command code $A; $E is the same command, unused by Apple. The sense write protect mode (Q7
;; off, Q6 on) uses it: after a few clocks every bit of the latch is the sensor, so the 6502 reads the latch
;; and tests bit 7, set when the disk is write protected.
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <LD>, <CLR>, <NOP>, <SL0>, <SL1>, <READING>
.define SR(state) ((state) << 4 | $A)

;; A sequencer entry that loads the data latch from the 6502's data bus and goes to {state}.
;;
;; The entry is command code $B; $F is the same command, unused by Apple. The write loading mode (Q7 on, Q6
;; on) uses it in place of a shift, once per bit time, so the byte the 6502 stores to the controller becomes
;; the next nibble to write, its bit 7 in QA first.
;;
;; Parameters: state = the state to go to next, $0-$F; it becomes the entry's high nibble
;; See: <SR>, <CLR>, <NOP>, <SL0>, <SL1>, <WRITING>
.define LD(state) ((state) << 4 | $B)

;; Names one sequencer entry by its state and inputs, so <SEQUENCER> can find it.
;;
;; The name is SEQ_ and two hex digits: the state, then the inputs as four bits, Q7 Q6 QA RP. RP is 0 while
;; the drive reports a read pulse.
;;
;; Parameters:
;;   state  = the current state, $0-$F
;;   inputs = Q7, Q6, QA and RP as bits 3-0, such as %1010 for write shifting with QA 1 and a read pulse
;;   entry  = the entry byte, made with a command such as <NOP>($1)
;; See: <READING>, <WRITING>, <SEQUENCER>
.macro ENTRY state, inputs, entry
    .ident(.sprintf("SEQ_%02X", (state) << 4 | (inputs))) = entry
.endmacro

;; Defines one state's entries for the two reading modes: read, and sense write protect.
;;
;; Q7 is off in both modes; Q6 selects which. Each card's reading table lists the entries in the order the
;; parameters take them, QA RP = 00, 01, 10 and 11 in each mode. RP is 0 while the drive reports a read
;; pulse, so the 00 and 10 columns are the ones with a pulse.
;;
;; Parameters:
;;   state   = the state, $0-$F
;;   read00  = read mode (Q6 off), QA 0, a read pulse
;;   read01  = read mode, QA 0, no pulse
;;   read10  = read mode, QA 1, a read pulse
;;   read11  = read mode, QA 1, no pulse
;;   sense00 = sense write protect mode (Q6 on), QA 0, a read pulse
;;   sense01 = sense write protect mode, QA 0, no pulse
;;   sense10 = sense write protect mode, QA 1, a read pulse
;;   sense11 = sense write protect mode, QA 1, no pulse
;; See: <WRITING>, <ENTRY>, <CLR>, <NOP>, <SL0>, <SL1>, <SR>
.macro READING state, read00, read01, read10, read11, sense00, sense01, sense10, sense11
    ENTRY state, %0000, read00
    ENTRY state, %0001, read01
    ENTRY state, %0010, read10
    ENTRY state, %0011, read11
    ENTRY state, %0100, sense00
    ENTRY state, %0101, sense01
    ENTRY state, %0110, sense10
    ENTRY state, %0111, sense11
.endmacro

;; Defines one state's entries for the two writing modes: shifting, and loading.
;;
;; Q7 is on in both modes; Q6 selects which. The writing table lists the entries in the order the parameters
;; take them, QA RP = 00, 01, 10 and 11 in each mode. RP does not matter in writing, so each pair of entries
;; that differs only in RP is the same.
;;
;; Parameters:
;;   state   = the state, $0-$F
;;   shift00 = write shifting mode (Q6 off), QA 0, a read pulse
;;   shift01 = write shifting mode, QA 0, no pulse
;;   shift10 = write shifting mode, QA 1, a read pulse
;;   shift11 = write shifting mode, QA 1, no pulse
;;   load00  = write loading mode (Q6 on), QA 0, a read pulse
;;   load01  = write loading mode, QA 0, no pulse
;;   load10  = write loading mode, QA 1, a read pulse
;;   load11  = write loading mode, QA 1, no pulse
;; See: <READING>, <ENTRY>, <NOP>, <SL0>, <LD>
.macro WRITING state, shift00, shift01, shift10, shift11, load00, load01, load10, load11
    ENTRY state, %1000, shift00
    ENTRY state, %1001, shift01
    ENTRY state, %1010, shift10
    ENTRY state, %1011, shift11
    ENTRY state, %1100, load00
    ENTRY state, %1101, load01
    ENTRY state, %1110, load10
    ENTRY state, %1111, load11
.endmacro

;; Emits the chip's 256 bytes, each entry at the address the chip's pins give it.
;;
;; <ENTRY> names each entry by its state and inputs, in that order: state, Q7, Q6, QA, RP. The chip's address
;; pins take them in another order, chosen to simplify the circuit board: A7-A0 are state bits 3 and 2, state
;; bit 0, RP, Q7, Q6, QA and state bit 1. Its data pins hold the next state in D7-D4 and the command in D3-D0.
;; For each address, SEQUENCER moves the pins' bits back into entry order and emits that entry.
;;
;; See: <ENTRY>, <READING>, <WRITING>
.macro SEQUENCER
.repeat 256, Pins
    Logical .set Pins & $C0                     ; A7-A6: state bits 3 and 2
    Logical .set Logical | ((Pins & $01) << 5)  ; A0: state bit 1
    Logical .set Logical | ((Pins & $20) >> 1)  ; A5: state bit 0
    Logical .set Logical | (Pins & $0E)         ; A3-A1: Q7, Q6, QA
    Logical .set Logical | ((Pins & $10) >> 4)  ; A4: RP
    .byte .ident(.sprintf("SEQ_%02X", Logical))
.endrepeat
.endmacro

; Writing, the same on both cards; each card's source has its own reading table. Each state goes to the next,
; around a loop of eight, 4 microseconds, one bit. At the end of the loop (state $7 or $F), the state's top bit,
; the write signal, changes when QA is 1. Then the latch shifts left (SL0), or in loading mode loads the byte the
; 6502 stores (LD), to put the next bit in QA.
;
;               shifting                              loading
;  QA RP:       00       01       10       11         00       01       10       11
    WRITING $0, NOP($1), NOP($1), NOP($1), NOP($1),   NOP($1), NOP($1), NOP($1), NOP($1)
    WRITING $1, NOP($2), NOP($2), NOP($2), NOP($2),   NOP($2), NOP($2), NOP($2), NOP($2)
    WRITING $2, SL0($3), SL0($3), SL0($3), SL0($3),   LD($3),  LD($3),  LD($3),  LD($3)
    WRITING $3, NOP($4), NOP($4), NOP($4), NOP($4),   NOP($4), NOP($4), NOP($4), NOP($4)
    WRITING $4, NOP($5), NOP($5), NOP($5), NOP($5),   NOP($5), NOP($5), NOP($5), NOP($5)
    WRITING $5, NOP($6), NOP($6), NOP($6), NOP($6),   NOP($6), NOP($6), NOP($6), NOP($6)
    WRITING $6, NOP($7), NOP($7), NOP($7), NOP($7),   NOP($7), NOP($7), NOP($7), NOP($7)
    WRITING $7, NOP($0), NOP($0), NOP($8), NOP($8),   NOP($0), NOP($0), NOP($8), NOP($8)
    WRITING $8, NOP($9), NOP($9), NOP($9), NOP($9),   NOP($9), NOP($9), NOP($9), NOP($9)
    WRITING $9, NOP($A), NOP($A), NOP($A), NOP($A),   NOP($A), NOP($A), NOP($A), NOP($A)
    WRITING $A, SL0($B), SL0($B), SL0($B), SL0($B),   LD($B),  LD($B),  LD($B),  LD($B)
    WRITING $B, NOP($C), NOP($C), NOP($C), NOP($C),   NOP($C), NOP($C), NOP($C), NOP($C)
    WRITING $C, NOP($D), NOP($D), NOP($D), NOP($D),   NOP($D), NOP($D), NOP($D), NOP($D)
    WRITING $D, NOP($E), NOP($E), NOP($E), NOP($E),   NOP($E), NOP($E), NOP($E), NOP($E)
    WRITING $E, NOP($F), NOP($F), NOP($F), NOP($F),   NOP($F), NOP($F), NOP($F), NOP($F)
    WRITING $F, NOP($8), NOP($8), NOP($0), NOP($0),   NOP($8), NOP($8), NOP($0), NOP($0)
