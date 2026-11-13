;; APPLE III EQUATES: I/O PAGE, SYSTEM VIAS AND ENVIRONMENT
;;
;; The Apple III's built-in I/O locations at $C000-$C0FF, the slot spaces, the RAM vectors under the ROM, and the
;; two system 6522 VIAs at $FFD0 and $FFE0 whose ports are the environment, zero-page and bank registers. Names are
;; the ones Apple's boot ROM listing gives them; where the listing uses a bare address, the name is ours. Where the
;; listing has two names for one location (the diagnostics and the monitor were separate sources), both are here.
;;
;; The disk switches are written as the Disk II's slot-relative bases ($C080-$C08F): the boot ROM indexes them with
;; X = $60, the built-in controller's slot number times 16, to reach $C0E0-$C0EF.

; The keyboard.

;; The keyboard's data port: the last key's code in bits 0-6, with bit 7 set while a new key waits.
;;
;; Reading it does not clear the strobe; <KBDSTRB> does. The boot ROM's monitor tests bit 7 with BIT and shifts it
;; out with ASL to see whether a key is waiting.
;; See: <KBDSTRB>, <KEYBD>, <KYBD>
KBD = $C000

;; The diagnostics' name for the keyboard port, <KBD>; they read every address of the page from it to exercise the
;; I/O decoding.
;; See: <KBD>
KYBD = $C000

;; The keyboard's second port: modifier keys and the keyboard's status, active low.
;;
;; Bit 2 is clear while Control is held and bit 4 while Open Apple is held: at power-up, Control skips the
;; diagnostics and Open Apple enters the monitor. Bit 6 is set while the keyboard is connected.
;; See: <KBD>
KEYBD = $C008

;; Clears the keyboard strobe, bit 7 of <KBD>, when read or written.
;; See: <KBD>
KBDSTRB = $C010

; Sound, slots and video.

;; Deselects the expansion ROM space of Apple III peripheral cards (slot pin 39) when read or written.
;; See: <EXPROM>
IODESEL = $C020

;; Toggles the speaker when read or written.
;; See: <BEEP>
SPKR = $C030

;; Sounds the bell, a 1 kHz tone for about a tenth of a second, when read or written.
;; See: <SPKR>
BEEP = $C040

;; Selects graphics display when read or written.
;; See: <TXTMD>
GRMD = $C050

;; Selects text display when read or written.
;; See: <GRMD>, <COL40SW>, <COL80SW>
TXTMD = $C051

;; Selects 40-column text when read or written.
;; See: <COL80SW>, <TXTMD>
COL40SW = $C052

;; Selects 80-column text when read or written.
;; See: <COL40SW>, <TXTMD>
COL80SW = $C053

;; The first of the analog-input switches, $C058-$C05F.
;;
;; The pairs at $C058, $C05A and $C05E clear (even address) or set (odd) one bit of the input number; $C05C charges
;; the timing capacitor and $C05D starts its ramp, which <ADTO> then reports.
;; See: <ADTO>
PDLEN = $C058

;; The analog timeout: bit 7 is set while the ramp started at <PDLEN>+5 runs, and clear once it reaches the
;; selected input's voltage.
;; See: <PDLEN>, <JOYRDY>
ADTO = $C066

;; The disk routines' name for the analog timeout, <ADTO>, which the joystick timer waits on.
;; See: <ADTO>
JOYRDY = $C066

; The built-in disk controller, as offsets from $C080 for X = $60.

;; Turns stepper phase (A AND 3) off, at offset 2 times the phase.
;; See: <PHASEON>
PHASEOFF = $C080

;; Turns stepper phase (A AND 3) on, at offset 2 times the phase plus 1.
;; See: <PHASEOFF>
PHASEON = $C081

;; Turns the selected drive's motor off.
;; See: <MOTORON>
MOTOROFF = $C088

;; Turns the selected drive's motor on.
;; See: <MOTOROFF>
MOTORON = $C089

;; Selects the built-in drive (.D1).
;; See: <DRV1EN>
DRV0EN = $C08A

;; Selects an external drive, the one <DISKOFF>'s switches number.
;; See: <DRV0EN>, <DISKOFF>
DRV1EN = $C08B

;; Q6 off: reads the data latch, or with Q7 on, shifts a byte out.
;; See: <Q6H>, <Q7L>, <Q7H>
Q6L = $C08C

;; Q6 on: with Q7 off, loads the write-protect sense into the latch's bit 7; with Q7 on, loads the latch to write.
;; See: <Q6L>, <Q7L>
Q6H = $C08D

;; Q7 off: read mode.
;; See: <Q7H>, <Q6L>
Q7L = $C08E

;; Q7 on: write mode.
;; See: <Q7L>, <Q6H>
Q7H = $C08F

;; The first of the external drive's select switches, $C0D0-$C0D3; the diagnostics read every other one of
;; $C0D0-$C0DE to put the disk and video switches in a known state.
;; See: <DRV1EN>
DISKOFF = $C0D0

;; Ends loading the character generator RAM.
;; See: <CWRTON>
CWRTOFF = $C0DA

;; Lets the video circuits load the character generator RAM from the screen holes during vertical retrace.
;; See: <CWRTOFF>
CWRTON = $C0DB

;; The built-in 6551 ACIA's status register.
;; See: <ACIACM>, <ACIACN>
ACIAST = $C0F1

;; The ACIA's command register.
;; See: <ACIAST>, <ACIACN>
ACIACM = $C0F2

;; The ACIA's control register.
;; See: <ACIAST>, <ACIACM>
ACIACN = $C0F3

;; Slot 1's I/O select space, $C100-$C1FF.
;; See: <SLT2>, <EXPROM>
SLT1 = $C100

;; Slot 2's I/O select space, $C200-$C2FF.
;; See: <SLT1>
SLT2 = $C200

;; Slot 3's I/O select space, $C300-$C3FF.
;; See: <SLT1>
SLT3 = $C300

;; Slot 4's I/O select space, $C400-$C4FF.
;; See: <SLT1>
SLT4 = $C400

;; Turns every card's expansion ROM off at $C800-$CFFF when read.
;; See: <IODESEL>, <SLT1>
EXPROM = $CFFF

; The RAM vectors under the ROM, which the ROM's NMI and IRQ vectors point at.

;; Where the ROM's NMI vector points: a JMP in system RAM that the operating system sets.
;;
;; The monitor's <SETUP> copies <NMIRQ> here, a JMP to <RECON> followed by an RTI, so that until SOS takes over an
;; NMI (the RESET key) restarts the machine and an IRQ returns at once.
;; See: <IRQVEC>, <NMIRQ>
NMIVEC = $FFCA

;; Where the ROM's IRQ vector points, three bytes after <NMIVEC>.
;; See: <NMIVEC>
IRQVEC = $FFCD

; VIA D at $FFD0: port A is the environment register, port B the zero-page register.

;; The zero-page register, VIA D's port B: the page the 6502 sees as page zero.
;;
;; The stack moves with it, to the page with the low bit flipped, unless the environment register forces the
;; primary stack. Zero page in $18-$1F also turns on extended addressing for (zp),Y and (zp,X).
;; See: <ENVIRON>, <ENV_STACK>, <SYSD2>
ZPREG = $FFD0

;; VIA D's data direction register for port B, the zero-page register; all ones makes every bit an output.
;; See: <ZPREG>, <SYSD3>
SYSD2 = $FFD2

;; VIA D's data direction register for port A, the environment register.
;; See: <ENVIRON>, <SYSD2>
SYSD3 = $FFD3

;; VIA D's timer 2, low byte. The disk listing calls it timer 1.
;;
;; The joystick routine <BootRom:ANALOG> starts the timer counting down and reads it when the analog input times out.
;; See: <TIMER1H>, <TIMLATCH>
TIMER1L = $FFD8

;; VIA D's timer 2, high byte: writing it loads and starts the counter.
;; See: <TIMER1L>, <TIMLATCH>
TIMER1H = $FFD9

;; The disk listing's name for <TIMER1H> when it is written to start the timer.
;; See: <TIMER1H>
TIMLATCH = $FFD9

;; VIA D's peripheral control register.
;; See: <CB2CTRL>
DPCR = $FFDC

;; The environment register, VIA D's port A (without handshake): CPU speed, the I/O page, video, the RESET key,
;; write protection, the stack and the ROM.
;;
;; The ENV_ constants name its bits. The boot ROM sets it to $53 at power-up (2 MHz, I/O, RESET enabled, ROM),
;; to $77 to run the monitor and boot, and sets or clears <ONEMEG> around disk transfers.
;; See: <ENV_1MHZ>, <ENV_IO>, <ENV_VIDEO>, <ENV_NMI>, <ENV_WP>, <ENV_STACK>, <ENV_ROMSEL>, <ENV_ROM>, <SYSD1>
ENVIRON = $FFDF

;; The diagnostics' name for the environment register, <ENVIRON>.
;; See: <ENVIRON>
SYSD1 = $FFDF

; VIA E at $FFE0: port A is the bank register and interrupt status, port B drives the DAC.

;; VIA E's port B: the 6-bit sound DAC, and the screen-blank input.
;; See: <SYSE2>, <BNKSW>
SYSE0 = $FFE0

;; VIA E's data direction register for port B.
;; See: <SYSE0>, <SYSE3>
SYSE2 = $FFE2

;; VIA E's data direction register for port A.
;; See: <BNKSW>, <SYSE2>
SYSE3 = $FFE3

;; VIA E's peripheral control register; bits 5-7 set how CB2, the vertical retrace input, interrupts.
;; See: <CB2INT>, <DPCR>
CB2CTRL = $FFEC

;; VIA E's interrupt flag register; bit 3 is set when CB2 sees vertical retrace, and writing it clears it.
;; See: <CB2CTRL>
CB2INT = $FFED

;; The bank register, VIA E's port A (without handshake): bits 0-3 pick the bank at $2000-$9FFF, bit 6 keeps the
;; VIAs at $FFD0-$FFEF, and bit 7 reads the interrupt request line, clear while a device interrupts.
;; See: <INTERUPT>, <SYSE3>, <ZPREG>
BNKSW = $FFEF

;; The disk listing's name for <BNKSW> when it is read for bit 7, the interrupt request line.
;; See: <BNKSW>
INTERUPT = $FFEF

; The environment register's bits.

;; Environment bit 7: the CPU runs at 1 MHz rather than 2.
;; See: <ENVIRON>, <ONEMEG>
ENV_1MHZ = $80

;; Environment bit 6: the I/O page and slot space answer at $C000-$CFFF.
;; See: <ENVIRON>
ENV_IO = $40

;; Environment bit 5: video is on.
;; See: <ENVIRON>
ENV_VIDEO = $20

;; Environment bit 4: the RESET key may interrupt (NMI) or reset.
;; See: <ENVIRON>
ENV_NMI = $10

;; Environment bit 3: RAM at $C000-$FFFF in the system bank is read-only.
;; See: <ENVIRON>
ENV_WP = $08

;; Environment bit 2: the stack is page 1 of the system bank, wherever zero page is.
;; See: <ENVIRON>, <ZPREG>
ENV_STACK = $04

;; Environment bit 1: the ROM select line; the boot ROM always sets it.
;; See: <ENVIRON>, <ENV_ROM>
ENV_ROMSEL = $02

;; Environment bit 0: the boot ROM answers reads at $F000-$FFFF.
;; See: <ENVIRON>, <ENV_ROMSEL>
ENV_ROM = $01

;; Sets the 1 MHz bit when ORed into <ENVIRON>, as the disk routines do around a transfer.
;; See: <TWOMEG>, <ENV_1MHZ>
ONEMEG = ENV_1MHZ

;; Clears the 1 MHz bit when ANDed with <ENVIRON>, for 2 MHz.
;; See: <ONEMEG>
TWOMEG = ONEMEG ^ $FF
