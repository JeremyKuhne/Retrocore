; The formatter's data, and the names of the boot ROM's disk routines and work locations it uses. Included by Fmtd1.asm.

;; The sector image's address, low, high, then its extension byte, from the control list.
USERBUF:
    .res $03

;; The environment register.
E_REG = $FFDF

; The boot ROM's disk routines' work locations in zero page, which <DSKFORM> saves and restores.

;; The slot times 16: always $60.
IBSLOT = $81

;; Bit 7 set to keep interrupts off while the ROM's routines run.
IMASK = IBSLOT+$0A

;; The track the head is on.
CURTRK = IBSLOT+$0B

;; The count of interrupts taken while reading.
INTRTRY = IBSLOT+$0E

;; The formatter's count of address fields left to read.
RETRYCNT = IBSLOT+$12

;; The address of the data <PRENIB16> encodes, with its extension byte at $1400+BUF+1.
BUF = IBSLOT+$1A

;; The checksum read from an address field.
CKSUM = IBSLOT+$15

;; The four bytes <RDADR16> reads from an address field: the checksum, the sector, the track and the volume.
CSSTV = IBSLOT+$16

;; The sector of the address field just read.
SECT = CSSTV+$01

;; The track of the address field just read.
TRACK = CSSTV+$02

;; The track <SEEK> goes to, in half tracks.
TRKN = IBSLOT+$1D

;; The motor-on time: its high byte counts up to 0 while the drive comes up to speed (<MSWAIT>).
MONTIME = CSSTV+$02

; The formatter's own zero page.

;; $AA, for writing address fields with the right timing.
AA = $D0

;; The track being formatted.
TRK = $D1

;; The sector being written, or the sectors left to verify.
NSECT = $D2

;; The volume written in the address fields: always 1.
NVOL = $D3

;; The self-sync nibbles written before each address field.
NSYNC = $D4

;; <READ16>'s index.
IDX = $D5

;; The rewrites of the track left.
TRKRETRY = $D6

; The drive's soft switches, indexed by the slot times 16.

MOTOROFF = $C088                        ;; turns the motor off
MOTORON = $C089                         ;; turns the motor on
Q6L = $C08C                             ;; reads a nibble, or writes one in write mode
Q6H = $C08D                             ;; senses write protection, or loads a nibble in write mode
Q7L = $C08E                             ;; read mode
Q7H = $C08F                             ;; write mode

; The boot ROM's disk routines.

RDADR16 = $F1B9                         ;; reads an address field into CSSTV; carry set on an error
WRITE16 = $F216                         ;; writes a data field from the nibble buffers; carry set when write-protected
PRENIB16 = $F2C4                        ;; encodes the data at BUF into the nibble buffers
SEEK = $F400                            ;; moves the head to half track A from CURTRK
MSWAIT = $F456                          ;; waits, counting the motor-on time in MONTIME
DNIBL = $F300                           ;; the table that decodes disk nibbles to six-bit values

;; The ROM's zero page, $80-$9F, while the formatter runs.
ZEROSAVE:
    .res 32

;; The ROM's extension bytes, $1480-$149F, while the formatter runs.
XTNDSAVE:
    .res 32

;; The caller's environment register.
E_SAVE:
    .res $01

;; The caller's processor status, with its interrupt flag.
P_SAVE:
    .res $01

;; The first of the three addresses in $C0xx that select each drive, 1-4.
SEL1:
    .byte $00, $D0, $D5, $D5, $D5

;; The second of the three addresses in $C0xx that select each drive, 1-4.
SEL2:
    .byte $00, $D2, $D1, $D0, $D1

;; The third of the three addresses in $C0xx that select each drive, 1-4.
SEL3:
    .byte $00, $D4, $D2, $D3, $D3

;; Bit 7 set for each sector verified on the track.
FOUND:
    .res 16
