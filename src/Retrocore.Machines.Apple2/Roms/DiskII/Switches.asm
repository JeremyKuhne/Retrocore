; retrocore: style=strict
;; THE DISK II CONTROLLER'S SIXTEEN SWITCHES
;;
;; The controller card answers at $C080-$C08F plus the slot times 16 ($C0E0-$C0EF in slot 6). Each address is a
;; switch: reading it, or storing to it, sets the switch, and each pair turns one switch off (the even address) or on
;; (the odd one). Reading an even address also returns the data latch. Q6 and Q7 together pick the mode: read (both
;; off), sense write protect (Q6 on), write (Q7 on) and load a byte to write (both on). docs/DiskII.md explains the
;; drive and the controller.
;;
;; The boot ROMs, DOS's RWTS (Dos/RwtsEquates.asm) and the programs that talk to the controller themselves
;; (Software/Boot13.1983.asm) include this file. The names are DOS's except for phases 1 to 3, which DOS has no names
;; for: it reaches them as <Phase0Off> and <Phase0On> plus twice the phase. Each switch DOS names cites the documents
;; that give its name.

;; Turns stepper phase 0 off; Phase0Off + n * 2 turns phase n off (n = 0-3).
;;
;; The head moves when the phase next to the one that holds it is turned on and the old one off, half a track at a
;; time: DOS's seek routine (<Dos33:DiskII::MoveHead>) steps it so, and the boot ROM (<Boot16:Boot>) drives it out to
;; track 0 this way.
;; See: <Phase0On>, <Dos33:DiskII::MoveHead>, <Boot16:Boot>
;; Also: PHASEOFF (DOS33, DOS31)
Phase0Off = $C080

;; Turns stepper phase 0 on; Phase0On + n * 2 turns phase n on (n = 0-3).
;; See: <Phase0Off>
;; Also: PHASEON (DOS33, DOS31)
Phase0On = $C081

;; Turns stepper phase 1 off.
Phase1Off = $C082

;; Turns stepper phase 1 on.
Phase1On = $C083

;; Turns stepper phase 2 off.
Phase2Off = $C084

;; Turns stepper phase 2 on.
Phase2On = $C085

;; Turns stepper phase 3 off.
Phase3Off = $C086

;; Turns stepper phase 3 on.
Phase3On = $C087

;; Turns off the motor of the card's selected drive.
;;
;; The Disk II keeps the motor running for about a second after this, so a call that follows soon finds it still
;; turning.
;; See: <MotorOn>
;; Also: MOTOROFF (DOS33)
MotorOff = $C088

;; Turns on the motor of the card's selected drive: <SelectDrive1> and <SelectDrive2> choose which.
;;
;; A motor that was off takes a moment to come up to speed, which <Dos33:Rwts> waits for (<Dos33:MotorTime>).
;; See: <MotorOff>, <SelectDrive1>, <SelectDrive2>, <Dos33:Rwts>
;; Also: MOTORON (DOS33)
MotorOn = $C089

;; Selects drive 1 of the card; while the motor is on (<MotorOn>), the selected drive runs.
;; See: <SelectDrive2>
;; Also: DRV1EN (DOS33)
SelectDrive1 = $C08A

;; Selects drive 2 of the card.
;; See: <SelectDrive1>
;; Also: DRV2EN (DOS33)
SelectDrive2 = $C08B

;; Turns Q6 off and returns the data latch: in read mode, the nibble being read.
;;
;; With Q6 and Q7 off, the controller shifts bits from the disk into the latch, and a nibble is complete when bit 7
;; is set, so a reader reads it until bit 7 is 1. In write mode, Q6 off shifts the loaded nibble out to the disk. A
;; stopped disk leaves the latch unchanged, which RWTS reads to tell whether a drive is turning.
;; See: <LoadLatch>, <ReadMode>, <WriteMode>
;; Also: Q6L (DOS33, DOS31)
DataLatch = $C08C

;; Turns Q6 on: load mode in write mode, or sense write protect in read mode.
;;
;; In write mode, storing a nibble here loads it into the latch for the controller to write. In read mode, with Q6
;; on, reading <ReadMode> returns the write-protect switch in bit 7.
;; See: <DataLatch>, <ReadMode>, <WriteMode>
;; Also: Q6H (DOS33, DOS31)
LoadLatch = $C08D

;; Turns Q7 off: read mode.
;;
;; With Q6 off as well, the controller reads nibbles into the latch at <DataLatch>. With Q6 on, it returns the
;; write-protect switch in bit 7.
;; See: <WriteMode>, <DataLatch>, <LoadLatch>
;; Also: Q7L (DOS33, DOS31)
ReadMode = $C08E

;; Turns Q7 on: write mode.
;;
;; With Q6 on as well, the value stored is loaded into the latch; then each read of <DataLatch> shifts it out to the
;; disk, one bit every 4 cycles.
;; See: <ReadMode>, <LoadLatch>, <DataLatch>
;; Also: Q7H (DOS33, DOS31)
WriteMode = $C08F
