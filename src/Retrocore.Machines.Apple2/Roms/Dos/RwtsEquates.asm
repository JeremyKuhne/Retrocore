; retrocore: style=strict ignore=unlinked-name:RWTS -- the disk layer's name in prose; linked where it means the routine
;; DOS 3.3 and 3.2 RWTS: the Disk II's switches and the names the disk routines share
;;
;; The names shared by RWTS, "read or write a track and sector", and its lowest layer, the routines that talk to the
;; Disk II controller nibble by nibble: the prenibble and postnibble routines convert a 256-byte sector to and from
;; the six-bit values written on the disk, the write and read routines write and read a data field, the address
;; field reader finds a sector, the seek routine moves the head and the wait routine waits. They run from $B800
;; where DOS runs, right after the boot loader's two pages, through the tables and buffers that end at $BC55 ($BCB9
;; in DOS 3.2). RWTS proper, the routine DOS calls with an IOB, is in Rwts1.asm and Rwts2.asm (Rwts32.asm in DOS
;; 3.2), and the formatter in Formatter.asm (Formatter32.asm). docs/DiskII.md explains nibbles, the 6-and-2 encoding
;; (5-and-3 in DOS 3.2), the fields of a sector and the controller's switches.
;;
;; The code depends on exact cycle counts. A Disk II nibble passes the head every 32 cycles (eight 4-cycle bit
;; cells), so the write routines store a nibble exactly every 32 cycles and the read routines must take each one
;; before the next replaces it. A branch taken across a page boundary, or an indexed access that crosses one, costs
;; an extra cycle; so the timed loops each sit within one page, and the tables and buffers they index (in MsWait.asm,
;; or NibbleBuffers32.asm in DOS 3.2) are placed on purpose.
;;
;; Most of the routines' variables are zero-page bytes the Monitor also uses as working storage, under names for
;; what RWTS keeps there. Several share one byte, because the routines that use them never run at the same time:
;; $26 is a count, a checksum or a saved value depending on the routine. Others are in the text screen's "screen
;; holes", the eight bytes at the end of each 128-byte block of $0400-$07FF that the display never shows; the Apple
;; II gives slot n the hole bytes at $0478 + n, $04F8 + n and so on, and RWTS keeps per-slot values in them, using
;; slot 0's bytes (no disk controller is ever in slot 0) for its own variables.
;;
;; Software/Boot13.1980.asm includes this file too, with DOS 3.2's nibble routines.

;; The start of the first range of RWTS's code that the relocator adjusts, at $B800 where DOS runs: the low-level
;; routines up to <AEC1>, $BA10 (the range's last byte), or $BA8E in DOS 3.2. See Relocator.asm.
;; Also: ASC1 (DOS33, DOS31)
LowLevelCodeStart:

; The Disk II controller's switches. Each is at the address given plus slot * 16, and is switched by reading it (a
; store switches it too). Q6 and Q7 together pick the mode:
; read (both off), sense write protect (Q6 on), write (Q7 on) and load a byte to write (both on).

;; Turns stepper phase 0 off; Phase0Off + n * 2 turns phase n off (n = 0-3).
;;
;; The Disk II's head moves when the phase next to the one that holds it is turned on and the old one off. The seek
;; routine (<SEEK>) does this one half-track at a time, reaching each phase's switch through <SLOTTEMP>.
;; <Phase0On>, the next address, turns the phase on.
;; See: <Phase0On>, <SEEK>
;; Also: PHASEOFF (DOS33, DOS31)
Phase0Off = $C080

;; Turns stepper phase 0 on; Phase0On + n * 2 turns phase n on (n = 0-3).
;;
;; DOS 3.3 reaches it as <Phase0Off> + 1. The seek routine turns on the phase for the next half-track before it
;; turns off the one it leaves.
;; See: <Phase0Off>, <SEEK>
;; Also: PHASEON (DOS33, DOS31)
Phase0On = $C081

;; Turns off the motor of the card's selected drive.
;;
;; The Disk II keeps the motor running for about a second after this, so a call that follows soon finds it still
;; turning. RWTS reads it when it finishes (<HNDLERR>), and the formatter when it is done. <MotorOn> turns the motor
;; on.
;; See: <MotorOn>, <SelectDrive1>, <SelectDrive2>, <RWTS>
;; Also: MOTOROFF (DOS33)
MotorOff = $C088

;; Turns on the motor of the card's selected drive.
;;
;; <RWTS> reads it on each call, after checking whether the motor was already turning; if it was not, it waits for
;; the motor to come up to speed (<MotorTime>). <SelectDrive1> and <SelectDrive2> choose the drive, and <MotorOff>
;; turns the motor off.
;; See: <MotorOff>, <SelectDrive1>, <SelectDrive2>, <MotorTime>
;; Also: MOTORON (DOS33)
MotorOn = $C089

;; Selects drive 1 of the card.
;;
;; <RWTS> reads it, or <SelectDrive2>, by the IOB's drive number, and notes the choice in <DRIVNO>. While the motor
;; is on (<MotorOn>), the selected drive runs.
;; See: <SelectDrive2>, <DRIVNO>, <MotorOn>
;; Also: DRV1EN (DOS33)
SelectDrive1 = $C08A

;; Selects drive 2 of the card.
;;
;; <RWTS> reads it, or <SelectDrive1>, by the IOB's drive number, and notes the choice in <DRIVNO>. DOS 3.2's RWTS
;; reads <SelectDrive1> first and then this one to select drive 2.
;; See: <SelectDrive1>, <DRIVNO>, <MotorOn>
;; Also: DRV2EN (DOS33)
SelectDrive2 = $C08B

;; Turns Q6 off and returns the data latch: in read mode, the nibble being read.
;;
;; With Q6 and Q7 off, the controller shifts bits from the disk into the latch, and a nibble is complete when bit 7
;; is set. In write mode, Q6 off shifts the loaded nibble out to the disk. <RWTS> also reads it to tell whether a
;; drive is turning: a stopped disk leaves the latch unchanged.
;; See: <LoadLatch>, <ReadMode>, <WriteMode>
;; Also: Q6L (DOS33, DOS31)
DataLatch = $C08C

;; Turns Q6 on: load mode in write mode, or sense write protect in read mode.
;;
;; In write mode, storing a nibble here loads it into the latch for the controller to write. In read mode, with Q6
;; on, reading <ReadMode> returns the write-protect switch in bit 7. The write routines check it before they write.
;; See: <DataLatch>, <ReadMode>, <WriteMode>
;; Also: Q6H (DOS33, DOS31)
LoadLatch = $C08D

;; Turns Q7 off: read mode.
;;
;; With Q6 off as well, the controller reads nibbles into the latch at <DataLatch>. With Q6 on, it returns the
;; write-protect switch in bit 7. The write routines end by reading it, to go back to read mode.
;; See: <WriteMode>, <DataLatch>, <LoadLatch>
;; Also: Q7L (DOS33, DOS31)
ReadMode = $C08E

;; Turns Q7 on: write mode.
;;
;; With Q6 on as well, the value stored is loaded into the latch; then each read of <DataLatch> shifts it out to the
;; disk, one bit every 4 cycles. The write routines store the first self-sync nibble here, and <ReadMode> returns to
;; read mode.
;; See: <ReadMode>, <LoadLatch>, <DataLatch>
;; Also: Q7H (DOS33, DOS31)
WriteMode = $C08F

; The variables the disk routines share.

;; The pointer to the caller's 256-byte sector buffer (2 bytes).
;;
;; <RWTS> copies it from the IOB's buffer address, with the DCT pointer, through <PTRSDEST>. The prenibble routine
;; (<Dos33:PRENIB16>, <Dos32:PRENIB13>) reads the sector to write from it, and the postnibble routine
;; (<Dos33:POSTNB16>, <Dos32:POSTNB13>) stores the sector it rebuilds there.
;; See: <PTRSDEST>, <RWTS>
;; Also: BUF (DOS33, DOS31)
SectorBuffer = Address2

;; The address field just read, four bytes from $2C: the checksum, the sector, the track and the volume.
;;
;; The address field reader (<Dos33:RDADR16>, <Dos32:RDADR13>) stores the bytes from the volume down. RWTS names the
;; last three <SECT>, <TRACK> and <VOLUME>, and compares them with what the caller asked for. Apple's DOS equates
;; also call the track's byte, $2E, BOOTSL, a name DOS 3.1 used for the boot slot and DOS 3.3 does not use.
;; See: <SECT>, <TRACK>, <VOLUME>, <CSUM>
;; Also: CSSTV (DOS33, DOS31)
AddressField = HorizontalLineEnd

;; The half-track the selected drive's head is on, while the seek routine moves it; after <MYSEEK>, the track.
;;
;; It is slot 0's screen-hole byte at $0478, the same byte as the start of RWTS's per-slot table <DRV1TRK>. <MYSEEK>
;; loads it from the drive's entry in that table before it calls <SEEK>, which compares it with
;; <TargetHalfTrack>.
;; See: <TargetHalfTrack>, <SEEK>, <MYSEEK>
;; Also: CURTRK (DOS33, DOS31)
CurrentTrack = $0478

;; The low byte of the motor-on count, which <MSWAIT> adds 1 to for every 100 microseconds it waits.
;;
;; <RWTS> starts the count at a negative value from the DCT when it turns a motor on, and waits until it reaches
;; zero, so that the time spent seeking counts toward the motor's start-up. RWTS names the pair <MONTIME>.
;; See: <MotorTimeHigh>, <MONTIME>, <MSWAIT>, <DeviceTable::MOTOR_DELAY>
;; Also: MONTIMEL (DOS33, DOS31)
MotorTime = SavedX

;; The high byte of the motor-on count at <MotorTime>.
;;
;; <RWTS> sets it from the DCT's byte 3, $D8 for the Disk II, and waits until the count reaches zero.
;; See: <MotorTime>, <MONTIME>
;; Also: MONTIMEH (DOS33, DOS31)
MotorTimeHigh = SavedY

;; The half-track the seek routine is moving the head to, and after the seek the half-track it is on.
;;
;; <SEEK> compares <CurrentTrack> with it to decide the direction and the steps left. <MYSEEK> sets it.
;; See: <CurrentTrack>, <SEEK>, <MYSEEK>
;; Also: TRKN (DOS33, DOS31)
TargetHalfTrack = ScrollBase

.if DOS32 = 0
;; DOS 3.3: the number of bytes the postnibble routine, <Dos33:POSTNB16>, rebuilds in <SectorBuffer>, 0 meaning all
;; 256.
;;
;; RWTS sets it to 0 just before it calls the routine. It shares $26 with the other routines' temporaries.
;; See: <SectorBuffer>, <Dos33:POSTNB16>
;; Also: T0 (DOS33, DOS31)
RebuildCount = LowResBase
.endif

; The formatter's variables, which <Dos33:WADR16> (DOS 3.2's <WBYTE>) writes into each address field. The two
; versions keep them in different bytes.

.if DOS32
;; The volume number the formatter writes in each address field, 1-254.
;;
;; RWTS stores the IOB's volume here before it calls the formatter, <DSKFORM>. In DOS 3.2 it is <AddressField>'s
;; last byte.
;; See: <FormatTrack>, <FormatSector>, <DSKFORM>
;; Also: NVOL (DOS33)
FormatVolume = AddressField + 3

;; The track the formatter is formatting, 0-34.
;; See: <FormatVolume>, <FormatSector>, <DSKFORM>
;; Also: TRK (DOS33)
FormatTrack = Address3High

;; Holds $AA while the disk is being formatted, so that <WBYTE> can use a 3-cycle ORA where `ORA #$AA` takes 2.
;;
;; DOS 3.2 borrows the low byte of Integer BASIC's LOMEM, <IBLMEM>, for it.
;; See: <WBYTE>, <DSKFORM>
;; Also: AA (DOS33)
FormatMask = IBLMEM

;; The sector number the formatter writes in the next address field.
;;
;; <DSKFORM> counts it through the sectors in the order it lays them down the track. DOS 3.2 borrows the high byte
;; of Integer BASIC's LOMEM, <IBLMEM>, for it.
;; See: <FormatVolume>, <FormatTrack>, <DSKFORM>
;; Also: NSECT (DOS33)
FormatSector = IBLMEM + 1
.else
;; The volume number the formatter writes in each address field, 1-254.
;;
;; The formatter, <DSKFORM>, copies it from the IOB's volume, and <Dos33:WADR16> writes it in each address field.
;; See: <FormatTrack>, <FormatSector>, <DSKFORM>
;; Also: NVOL (DOS33)
FormatVolume = Address3High

;; The track the formatter is formatting, 0-34.
;;
;; <DSKFORM> counts it up from 0, and <Dos33:WADR16> writes it in each address field.
;; See: <FormatVolume>, <FormatSector>, <DSKFORM>
;; Also: TRK (DOS33)
FormatTrack = Address5

;; Holds $AA while the disk is being formatted, so that <Dos33:WADR16> can use a 3-cycle ORA where `ORA #$AA` takes
;; 2.
;;
;; <DSKFORM> sets it. It is <SectorBuffer>'s low byte, which formatting does not use.
;; See: <Dos33:WADR16>, <DSKFORM>
;; Also: AA (DOS33)
FormatMask = Address2

;; The sector number the formatter writes in the next address field, 0-15.
;;
;; <Dos33:WADR16> writes it, and <DSKFORM> steps it through the sectors as it writes a track. It is
;; <SectorBuffer>'s high byte.
;; See: <FormatVolume>, <FormatTrack>, <DSKFORM>
;; Also: NSECT (DOS33)
FormatSector = Address2High
.endif

; The temporaries of single routines, which their routines' owners turn into names inside those routines. Until
; then they keep Apple's names here.

.if DOS32
;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's first byte, with two more bits above them.
;;
;; <Dos32:PRENIB13> shifts in a bit of the group's fourth byte and one of its fifth, making a five-bit value for
;; <NBUF2>. <GROUP3> shares the byte.
;; See: <GROUP1>, <GROUP2>, <Dos32:PRENIB13>
GROUP0 = $26

;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's second byte, with two more bits above them.
;;
;; Made like <GROUP0>'s, for <NBUF2>'s second run of values. <GROUP4> shares the byte.
;; See: <GROUP0>, <GROUP2>, <Dos32:PRENIB13>
GROUP1 = $27

;; DOS 3.2's <Dos32:PRENIB13>: the low three bits of a group's third byte, with two more bits above them.
;;
;; Made like <GROUP0>'s, for <NBUF2>'s third run of values.
;; See: <GROUP0>, <GROUP1>, <Dos32:PRENIB13>
GROUP2 = $2A

;; DOS 3.2's <Dos32:POSTNB13>: the low bits of a group's fourth byte, gathered from the group's three <NBUF2> values.
;;
;; <Dos32:POSTNB13> takes one bit from each value's top as it rebuilds the group. <GROUP0> shares the byte.
;; See: <GROUP4>, <Dos32:POSTNB13>
GROUP3 = $26

;; DOS 3.2's <Dos32:POSTNB13>: the low bits of a group's fifth byte, gathered from the group's three <NBUF2> values.
;;
;; Gathered like <GROUP3>'s. <GROUP1> shares the byte.
;; See: <GROUP3>, <Dos32:POSTNB13>
GROUP4 = $27
.endif

;; The address field reader's count of nibbles to search, high byte.
;;
;; The reader (<Dos33:RDADR16>, <Dos32:RDADR13>) counts it and Y up from $FCFC and gives up when they reach zero,
;; about 770 nibbles, two sectors' worth, without a field. It shares $26 with the other routines' temporaries.
;; See: <LAST>, <CSUM>, <AddressField>
COUNT = $26

;; The first, odd-bits nibble of a 4-and-4 pair, shifted into place, while the address field reader reads the
;; second.
;;
;; The reader rotates the first nibble left and ands it with the second to rebuild the byte. It shares $26 with
;; <COUNT> and the other routines' temporaries.
;; See: <COUNT>, <CSUM>, <AddressField>
LAST = $26

;; The running checksum of the address field being read: its bytes exclusive-ored together.
;;
;; The address field reader (<Dos33:RDADR16>, <Dos32:RDADR13>) fails unless all four bytes, the checksum included,
;; exclusive-or to zero.
;; See: <AddressField>, <COUNT>
CSUM = $27

;; The write routine's zero-page copy of <NBUF2>'s first value, which it loads in 3 cycles instead of 4.
;;
;; The data field writer (<Dos33:WRITE16>, <Dos32:WRITE13>) copies it here before the timed part starts. It shares
;; $26 with the other routines' temporaries.
;; See: <SLOTZ>, <Dos33:WRITE16>
WTEMP = $26

;; The slot times 16, in zero page so that the write routine can load it in 3 cycles.
;;
;; The data field writer (<Dos33:WRITE16>, <Dos32:WRITE13>) stores the slot here and in <SLOTABS>, and reloads X
;; from one or the other to make each path last exactly 32 cycles.
;; See: <WTEMP>, <SLOTABS>, <Dos33:WRITE16>
SLOTZ = $27

;; The slot times 16 again, outside zero page, so that the write routine can load it in 4 cycles.
;; See: <SLOTZ>, <Dos33:WRITE16>
SLOTABS = $0678

;; The data field reader's buffer index, kept here while Y holds the nibble being decoded.
;;
;; The reader (<Dos33:READ16>, <Dos32:READ13>) swaps Y with it on each nibble. It shares $26 with the other
;; routines' temporaries.
;; See: <Dos33:READ16>
IDX = $26

;; The number of half-tracks <SEEK> has moved the head so far.
;;
;; <SEEK> counts it up from 0 and indexes its acceleration tables with the smaller of it and the half-tracks still
;; to go. It shares $26 with the other routines' temporaries.
;; See: <PRIOR>, <TargetHalfTrack>, <SEEK>
TRKCNT = $26

;; The half-track the head is leaving, whose stepper phase <SEEK> turns off once the next one is on.
;; See: <TRKCNT>, <TargetHalfTrack>, <SEEK>
PRIOR = $27

;; The slot times 16, kept by <SEEK> while X indexes a stepper phase's switch.
;;
;; <SEEK> adds the phase number times 2 to it to reach <Phase0Off> or <Phase0On> for that phase.
;; See: <SEEK>, <Phase0Off>, <Phase0On>
SLOTTEMP = $2B

.if DOS32
;; DOS 3.2's formatter: the count of runs of $FF nibbles left in a sector's data area.
;;
;; <DSKFORM> writes $FF nibbles where each data field will go, since it writes no data fields.
;; See: <GAPLEN>, <DSKFORM>
GAPCNT = $46

;; DOS 3.2's formatter: how many self-sync bytes come before each address field.
;;
;; <DSKFORM> starts it at 80 and adds 2 for each track after the first. When a track does not read back with sector
;; 0 first, it formats the track again with one less, and fails below 16.
;; See: <GAPCNT>, <DSKFORM>
GAPLEN = $47
.endif
