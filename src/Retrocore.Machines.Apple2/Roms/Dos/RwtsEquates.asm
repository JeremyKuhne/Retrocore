;; DOS 3.3 AND 3.2 RWTS: NAMES FOR THE LOW-LEVEL DISK ROUTINES (COREQUS)
;;
;; The names shared by RWTS's lowest layer, the routines that talk to the Disk II controller nibble by nibble:
;; PRENIB16 and POSTNB16 convert a 256-byte sector to and from 6-and-2 values, WRITE16 and READ16 write and
;; read a data field, RDADR16 reads an address field, SEEK moves the head and MSWAIT waits. They run from $B800
;; where DOS runs, right after the boot loader's two pages, through the tables and buffers that end at $BC55.
;; RWTS proper, the routine DOS calls with an IOB, is in Rwts1.asm and Rwts2.asm; the formatter is in
;; Formatter.asm. docs/DiskII.md explains nibbles, the 6-and-2 encoding, the fields of a sector and the
;; controller's switches.
;;
;; DOS 3.2's routines are an earlier form of these for 13-sector disks, with the same names but 13 for 16:
;; PRENIB13 and POSTNB13 convert to and from 5-and-3 values, and the tables and buffers end at $BCB9. Its RWTS
;; proper is in Rwts32.asm and its formatter in Formatter32.asm. They use some zero-page bytes differently.
;;
;; The code depends on exact cycle counts. A Disk II nibble passes the head every 32 cycles (eight 4-cycle bit
;; cells), so the write routines store a nibble exactly every 32 cycles and the read routines must take each
;; one before the next replaces it. A branch taken across a page boundary, or an indexed access that crosses
;; one, costs an extra cycle; so the timed loops each sit within one page, and the tables and buffers they index
;; (NIBL, DNIBL, NBUF1, NBUF2, in MsWait.asm, or NibbleBuffers32.asm in DOS 3.2) are placed on purpose.
;;
;; Most temporaries here are zero-page bytes the Monitor also uses as working storage. Several names
;; share one byte, because the routines that use them never run at the same time: $26 is a count, a checksum
;; or a saved value depending on the routine. Others are in the text screen's "screen holes", the eight bytes
;; at the end of each 128-byte block of $0400-$07FF that the display never shows; the Apple II gives slot n
;; the hole bytes at $0478 + n, $04F8 + n and so on, and RWTS keeps per-slot values in them, using slot 0's
;; bytes (no disk controller is ever in slot 0) for its own variables.

;; The start of the first range of code the relocator adjusts in RWTS (ASC1 to AEC1, $B800-$BA10, or
;; $B800-$BA8E in DOS 3.2); see Relocator.asm.
ASC1:
; For PRENIB16 and POSTNB16.
;; The pointer to the caller's 256-byte sector buffer, low byte first (2 bytes).
;;
;; <RWTS> copies it from IOB bytes 08-09, with the DCT pointer, through <PTRSDEST>. The prenibble routine
;; (<Dos33:PRENIB16>, <Dos32:PRENIB13>) reads the sector to write from it, and the postnibble routine
;; (<Dos33:POSTNB16>, <Dos32:POSTNB13>) stores the sector it rebuilds there.
;; See: <PTRSDEST>, <RWTS>
BUF = $3E

.if DOS32
;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's first byte, with two more bits above them.
;;
;; <Dos32:PRENIB13> shifts in a bit of the group's fourth byte and one of its fifth, making a five-bit value
;; for NBUF2. <GROUP3> shares the byte.
;; See: <GROUP1>, <GROUP2>, <Dos32:PRENIB13>
GROUP0 = $26

;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's second byte, with two more bits above them.
;;
;; Made like <GROUP0>'s, for NBUF2's second run of values. <GROUP4> shares the byte.
;; See: <GROUP0>, <GROUP2>, <Dos32:PRENIB13>
GROUP1 = $27

;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's third byte, with two more bits above them.
;;
;; Made like <GROUP0>'s, for NBUF2's third run of values.
;; See: <GROUP0>, <GROUP1>, <Dos32:PRENIB13>
GROUP2 = $2A

;; DOS 3.2's <Dos32:POSTNB13>: the low bits of a group's fourth byte, gathered from the group's three NBUF2
;; values.
;;
;; <Dos32:POSTNB13> takes one bit from each value's top as it rebuilds the group. <GROUP0> shares the byte.
;; See: <GROUP4>, <Dos32:POSTNB13>
GROUP3 = $26

;; DOS 3.2's <Dos32:POSTNB13>: the low bits of a group's fifth byte, gathered from the group's three NBUF2
;; values.
;;
;; Gathered like <GROUP3>'s. <GROUP1> shares the byte.
;; See: <GROUP3>, <Dos32:POSTNB13>
GROUP4 = $27
.else
;; The number of bytes <Dos33:POSTNB16> rebuilds in <BUF>, 0 meaning all 256.
;;
;; RWTS sets it to 0 just before it calls <Dos33:POSTNB16>. It shares $26 with the other routines'
;; temporaries.
;; See: <BUF>, <Dos33:POSTNB16>
T0 = $26
.endif

; For READ16, WRITE16 and RDADR16 (in DOS 3.2, READ13, WRITE13 and RDADR13).
;; The address field reader's count of nibbles to search, high byte.
;;
;; The reader (<Dos33:RDADR16>, <Dos32:RDADR13>) counts it and Y up from $FCFC and gives up when they reach
;; zero, about 770 nibbles, two sectors' worth, without a field. It shares $26 with the other routines'
;; temporaries.
;; See: <LAST>, <CSUM>, <CSSTV>
COUNT = $26

;; The first, odd-bits nibble of a 4-and-4 pair, shifted into place, while the address field reader reads the
;; second.
;;
;; The reader rotates the first nibble left and ands it with the second to rebuild the byte. It shares $26
;; with <COUNT> and the other routines' temporaries.
;; See: <COUNT>, <CSUM>, <CSSTV>
LAST = $26

;; The running checksum of the address field being read: its bytes exclusive-ored together.
;;
;; The address field reader (<Dos33:RDADR16>, <Dos32:RDADR13>) fails unless all four bytes, the checksum
;; included, exclusive-or to zero.
;; See: <CSSTV>, <COUNT>
CSUM = $27

;; The address field just read, four bytes from $2C: the checksum, the sector, the track and the volume.
;;
;; The address field reader (<Dos33:RDADR16>, <Dos32:RDADR13>) stores the bytes from the volume down. RWTS
;; names the last three <SECT>, <TRACK> and <VOLUME>, and compares them with what the caller asked for.
;; See: <SECT>, <TRACK>, <VOLUME>, <CSUM>
CSSTV = $2C

;; The write routine's zero-page copy of NBUF2's first value, which it loads in 3 cycles instead of 4.
;;
;; The data field writer (<Dos33:WRITE16>, <Dos32:WRITE13>) copies it here before the timed part starts. It
;; shares $26 with the other routines' temporaries.
;; See: <SLOTZ>, <Dos33:WRITE16>
WTEMP = $26

;; The slot times 16, in zero page so that the write routine can load it in 3 cycles.
;;
;; The data field writer (<Dos33:WRITE16>, <Dos32:WRITE13>) stores the slot here and in SLOTABS ($0678), and
;; reloads X from one or the other to make each path last exactly 32 cycles.
;; See: <WTEMP>, <Dos33:WRITE16>
SLOTZ = $27

SLOTABS = $678                      ;; WRITE16: slot * 16 again, outside zero page (a 4-cycle load)

;; The data field reader's buffer index, kept here while Y holds the nibble being decoded.
;;
;; The reader (<Dos33:READ16>, <Dos32:READ13>) swaps Y with it on each nibble. It shares $26 with the other
;; routines' temporaries.
;; See: <Dos33:READ16>
IDX = $26

; For SEEK.
;; The number of half-tracks <SEEK> has moved the head so far.
;;
;; <SEEK> counts it up from 0 and indexes its acceleration tables with the smaller of it and the half-tracks
;; still to go. It shares $26 with the other routines' temporaries.
;; See: <PRIOR>, <TRKN>, <SEEK>
TRKCNT = $26

;; The half-track the head is leaving, whose stepper phase <SEEK> turns off once the next one is on.
;; See: <TRKCNT>, <TRKN>, <SEEK>
PRIOR = $27

;; The half-track <SEEK> is moving the head to, and after the seek the half-track it is on.
;;
;; <SEEK> compares the current half-track with it to decide the direction and the steps left.
;; See: <TRKCNT>, <PRIOR>, <SEEK>, <MYSEEK>
TRKN = $2A

;; The slot times 16, kept by <SEEK> while X indexes a stepper phase's switch.
;;
;; <SEEK> adds the phase number times 2 to it to reach <PHASEOFF> or <PHASEON> for that phase.
;; See: <SEEK>, <PHASEOFF>, <PHASEON>
SLOTTEMP = $2B

CURTRK = $478                       ;; SEEK: the half-track the head is on; after MYSEEK, the track (slot 0's hole)

; For MSWAIT and the motor's start.
;; The low byte of the motor-on count, which <MSWAIT> adds 1 to for every 100 microseconds it waits.
;;
;; <RWTS> starts the count at a negative value from the DCT when it turns a motor on, and waits until it
;; reaches zero, so that the time spent seeking counts toward the motor's start-up. RWTS names the pair
;; <MONTIME>.
;; See: <MONTIMEH>, <MONTIME>, <MSWAIT>
MONTIMEL = $46

;; The high byte of the motor-on count at <MONTIMEL>.
;;
;; <RWTS> sets it from DCT byte 03, $D8 for the Disk II, and waits until the count reaches zero.
;; See: <MONTIMEL>, <MONTIME>
MONTIMEH = $47

; For the formatter (WADR16 and DSKFORM).
.if DOS32
;; The volume number the formatter writes in each address field, 1-254.
;;
;; RWTS stores the IOB's volume here before it calls <DSKFORM>. In DOS 3.2 it is <CSSTV>'s last byte.
;; See: <TRK>, <NSECT>, <DSKFORM>
NVOL = $2F

;; The track the formatter is formatting, 0-34.
;; See: <NVOL>, <NSECT>, <DSKFORM>
TRK = $41

;; DOS 3.2's formatter: the count of runs of $FF nibbles left in a sector's data area.
;;
;; <DSKFORM> writes $FF nibbles where each data field will go, since it writes no data fields.
;; See: <GAPLEN>, <DSKFORM>
GAPCNT = $46

;; DOS 3.2's formatter: how many self-sync bytes come before each address field.
;;
;; <DSKFORM> starts it at 80 and adds 2 for each track after the first. When a track does not read back with
;; sector 0 first, it formats the track again with one less, and fails below 16.
;; See: <GAPCNT>, <DSKFORM>
GAPLEN = $47

;; Holds $AA while the disk is being formatted, so that <WBYTE> can use a 3-cycle ORA where `ORA #$AA` takes 2.
;; See: <WBYTE>, <DSKFORM>
AA = $4A

;; The sector number the formatter writes in the next address field.
;;
;; <DSKFORM> counts it through the sectors in the order it lays them down the track.
;; See: <NVOL>, <TRK>, <DSKFORM>
NSECT = $4B
.else
;; Holds $AA while the disk is being formatted, so that <Dos33:WADR16> can use a 3-cycle ORA where `ORA #$AA`
;; takes 2.
;;
;; <DSKFORM> sets it. It shares the byte with <BUF>'s low byte, which formatting does not use.
;; See: <Dos33:WADR16>, <WBYTE>, <DSKFORM>
AA = $3E

;; The sector number the formatter writes in the next address field, 0-15.
;;
;; <Dos33:WADR16> writes it, and <DSKFORM> steps it through the sectors as it writes a track. It shares the
;; byte with <BUF>'s high byte.
;; See: <NVOL>, <TRK>, <DSKFORM>
NSECT = $3F

;; The volume number the formatter writes in each address field, 1-254.
;;
;; <DSKFORM> copies it from IOB byte 03, and <Dos33:WADR16> writes it in each address field.
;; See: <TRK>, <NSECT>, <DSKFORM>
NVOL = $41

;; The track the formatter is formatting, 0-34.
;;
;; <DSKFORM> counts it up from 0, and <Dos33:WADR16> writes it in each address field.
;; See: <NVOL>, <NSECT>, <DSKFORM>
TRK = $44
.endif

; The controller's switches, at these addresses plus slot * 16. Q6 and Q7 together pick the mode: read (both
; off), sense write protect (Q6 on), write (Q7 on) and load a byte to write (both on).
;; Reading it turns stepper phase 0 off; PHASEOFF + n * 2, plus slot * 16, turns phase n off (n = 0-3).
;;
;; The Disk II's head moves when the phase next to the one that holds it is turned on and the old one off.
;; <SEEK> does this one half-track at a time, reaching each phase's switch through <SLOTTEMP>. <PHASEON>, the
;; next address, turns the phase on.
;; See: <PHASEON>, <SEEK>, <SLOTTEMP>
PHASEOFF = $C080

;; Reading it turns stepper phase 0 on; PHASEON + n * 2, plus slot * 16, turns phase n on (n = 0-3).
;;
;; DOS reaches it as <PHASEOFF> + 1: <SEEK> turns on the phase for the next half-track before it turns off the
;; one it leaves.
;; See: <PHASEOFF>, <SEEK>
PHASEON = $C081

;; Reading it, plus slot * 16, turns Q6 off and returns the data latch: in read mode, the nibble being read.
;;
;; With Q6 and Q7 off, the controller shifts bits from the disk into the latch, and a nibble is complete when
;; bit 7 is set. In write mode, Q6 off shifts the loaded nibble out to the disk. <RWTS> also reads it to tell
;; whether a drive is turning: a stopped disk leaves the latch unchanged.
;; See: <Q6H>, <Q7L>, <Q7H>, <Dos33:READ16>
Q6L = $C08C

;; Reading or writing it, plus slot * 16, turns Q6 on: load mode in write mode, or sense write protect in
;; read mode.
;;
;; In write mode, storing a nibble here loads it into the latch for the controller to write. In read mode, with
;; Q6 on, reading <Q7L> returns the write-protect switch in bit 7. The write routines (<Dos33:WRITE16>,
;; <Dos33:WADR16>) check it before they write.
;; See: <Q6L>, <Q7L>, <Q7H>, <Dos33:WRITE16>
Q6H = $C08D

;; Reading it, plus slot * 16, turns Q7 off: read mode.
;;
;; With Q6 off as well, the controller reads nibbles into the latch at <Q6L>. With Q6 on, it returns the
;; write-protect switch in bit 7. The write routines end by reading it, to go back to read mode.
;; See: <Q7H>, <Q6L>, <Q6H>
Q7L = $C08E

;; Reading or writing it, plus slot * 16, turns Q7 on: write mode.
;;
;; With Q6 on as well, the value stored is loaded into the latch; then each read of <Q6L> shifts it out to the
;; disk, one bit every 4 cycles. The write routines (<Dos33:WRITE16>, <Dos33:WADR16>) store the first self-sync
;; nibble here, and <Q7L> returns to read mode.
;; See: <Q7L>, <Q6H>, <Q6L>
Q7H = $C08F
