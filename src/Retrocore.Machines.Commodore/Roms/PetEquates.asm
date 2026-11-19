;; COMMODORE PET 2001 HARDWARE
;;
;; The PET's I/O and video RAM, shared by the editor and kernal sources of every BASIC version.
;;
;; Video RAM is 1K at $8000, 40 columns by 25 rows, one byte a character: bits 0-6 pick the character from the
;; character ROM, and bit 7 shows it reversed.
;;
;; The I/O is three chips in $E800-$EFFF. Address bit 4 selects PIA 1, bit 5 PIA 2 and bit 6 the VIA, so each
;; repeats through the 2K; these are the addresses the ROMs use.
;;
;; PIA 1 ($E810) runs the keyboard, cassette 1 and the retrace interrupt:
;;
;;   PA0-PA3   out: the keyboard row, 0-9, through a 74145 decoder
;;   PA4       in: cassette 1's keys, low while PLAY is down
;;   PA5       in: cassette 2's keys, low while PLAY is down
;;   PA6       in: EOI from the IEEE-488 bus
;;   PA7       in: the diagnostic sense line, low with the diagnostic jumper on the user port
;;   PB0-PB7   in: the keyboard row's keys, low while down
;;   CA1       in: cassette 1's read line
;;   CA2       out: EOI to the IEEE-488 bus; low blanks the screen on the 2001
;;   CB1       in: VIDEO ON, whose fall at the start of vertical blanking interrupts 60 times a second
;;   CB2       out: cassette 1's motor, running while low
;;
;; PIA 2 ($E820) is the IEEE-488 bus's data:
;;
;;   PA0-PA7   in: DIO1-DIO8, inverted
;;   PB0-PB7   out: DIO1-DIO8, inverted
;;   CA1       in: ATN
;;   CA2       out: NDAC
;;   CB1       in: SRQ
;;   CB2       out: DAV
;;
;; The VIA ($E840) has the rest:
;;
;;   PA0-PA7   the user port
;;   PB0       in: NDAC
;;   PB1       out: NRFD
;;   PB2       out: ATN
;;   PB3       out: the cassettes' write line
;;   PB4       out: cassette 2's motor, running while low
;;   PB5       in: VIDEO ON, low during vertical blanking
;;   PB6       in: NRFD
;;   PB7       in: DAV
;;   CA1       in: the user port's CA1
;;   CA2       out: the character set: low, uppercase and graphics; high, the set with lowercase
;;   CB1       in: cassette 2's read line
;;   CB2       the user port's CB2, which the shift register drives for sound
;;
;; Names follow the chips' data sheets.

SCREEN = $8000              ;; The first byte of video RAM, the top left character.
SCREEN_SIZE = 1000          ;; The bytes of video RAM the screen shows: 25 rows of 40.

PIA1_PA = $E810             ;; PIA 1's port A, or its direction register while CRA bit 2 is clear.
PIA1_CRA = $E811            ;; PIA 1's control register A: CA1 and CA2.
PIA1_PB = $E812             ;; PIA 1's port B, or its direction register while CRB bit 2 is clear.
PIA1_CRB = $E813            ;; PIA 1's control register B: CB1 and CB2.

PIA2_PA = $E820             ;; PIA 2's port A, or its direction register while CRA bit 2 is clear.
PIA2_CRA = $E821            ;; PIA 2's control register A: CA1 and CA2.
PIA2_PB = $E822             ;; PIA 2's port B, or its direction register while CRB bit 2 is clear.
PIA2_CRB = $E823            ;; PIA 2's control register B: CB1 and CB2.

VIA_ORB = $E840             ;; The VIA's port B.
VIA_ORA = $E841             ;; The VIA's port A, with the CA1 and CA2 handshake.
VIA_DDRB = $E842            ;; The VIA's port B direction register: a set bit is an output.
VIA_DDRA = $E843            ;; The VIA's port A direction register: a set bit is an output.
VIA_T1CL = $E844            ;; Timer 1: read, the counter's low byte; write, the latch's low byte.
VIA_T1CH = $E845            ;; Timer 1's counter's high byte: writing it loads the counter and starts it.
VIA_T1LL = $E846            ;; Timer 1's latch's low byte.
VIA_T1LH = $E847            ;; Timer 1's latch's high byte.
VIA_T2CL = $E848            ;; Timer 2: read, the counter's low byte; write, the latch's low byte.
VIA_T2CH = $E849            ;; Timer 2's counter's high byte: writing it loads the counter and starts it.
VIA_SR = $E84A              ;; The shift register.
VIA_ACR = $E84B             ;; The auxiliary control register: the timers' modes, the shift mode and latching.
VIA_PCR = $E84C             ;; The peripheral control register: CA1, CA2, CB1 and CB2.
VIA_IFR = $E84D             ;; The interrupt flag register.
VIA_IER = $E84E             ;; The interrupt enable register.
VIA_ORANH = $E84F           ;; The VIA's port A, without the handshake.
