; retrocore: style=strict
;; DOS 3.3 and 3.2: the IOB, the DCT and the track/sector list
;;
;; The layouts the disk routines and the file manager share: the IOB, the block a caller fills in to ask <Rwts>
;; ("read or write a track and sector") for one disk access; the DCT, the table that describes the drive; and the
;; track/sector list, the sectors that say where a file's data is on the disk. Each is a struct, for programs that
;; reach a block through a pointer, and DOS's own IOB and DCT are labeled bytes tied to the structs by the asserts
;; at the end. docs/Dos.md explains the IOB and track/sector lists, and docs/DiskII.md the drive.
;;
;; The boot loader (BootLoader.asm) includes this file where DOS's IOB and DCT sit, at the end of
;; the boot loader's second page: $B7E8-$B7FE where DOS runs, in both versions. The page-3 vector at $03E3,
;; <LocateIob at IOBLDR>, gives programs the IOB's address.

; RWTS's I/O block.

;; The layout of an IOB, the I/O block that says what <Rwts> is to do (19 bytes).
;;
;; The caller fills it in and calls <Rwts> with its address in A (high) and Y (low), through the vector at $03D9 or
;; DOS's <CallRwts>. RWTS reads the request through a pointer and writes back the return code, the volume found and
;; the slot and drive it used. DOS's own IOB is <DosIob>.
.struct Iob
    ;; The IOB's type, always 1. Nothing reads it.
    TYPE .byte
    ;; The slot times 16, such as $60 for slot 6.
    SLOT_TIMES_16 .byte
    ;; The drive, 1 or 2.
    DRIVE .byte
    ;; The volume expected, where 0 accepts any; for <RWTS_FORMAT>, the volume to write.
    VOLUME .byte
    ;; The track, 0 to 34.
    TRACK .byte
    ;; The sector. In DOS 3.3, 0 to 15 as DOS numbers them, which the interleave table <PhysicalSectors> turns into the
    ;; number on the disk; in DOS 3.2, 0 to 12, the number on the disk.
    SECTOR .byte
    ;; The address of the drive's DCT, laid out as <DeviceTable>.
    DEVICE_TABLE .addr
    ;; The address of the 256-byte buffer to read into or write from.
    BUFFER .addr
    ;; A byte count, which the file manager sets to the sector length, 256, and nothing reads.
    DATA_LENGTH .word
    ;; The command: <RWTS_SEEK>, <RWTS_READ>, <RWTS_WRITE> or <RWTS_FORMAT>.
    COMMAND .byte
    ;; The error RWTS returns when it sets the carry: <RWTS_WRITE_PROTECTED>, <RWTS_VOLUME_MISMATCH>,
    ;; <RWTS_DRIVE_ERROR>, <RWTS_READ_ERROR> or <RWTS_FORMAT_ERROR>.
    RETURN_CODE .byte
    ;; The volume found on the disk, which RWTS stores once it is on the right track.
    VOLUME_FOUND .byte
    ;; The slot times 16 of the previous call. RWTS compares it with the new slot, waits for the old slot's drive to
    ;; stop if they differ, then updates it.
    PREVIOUS_SLOT .byte
    ;; The drive of the previous call, which RWTS reads and updates.
    PREVIOUS_DRIVE .byte
    ;; Two bytes nothing uses.
    SPARE .res 2
.endstruct

; The commands, for <Iob::COMMAND>.

;; RWTS command: moves the head to the track and does nothing more.
;; Also: IBCNUL (DOS33, DOS31)
RWTS_SEEK = 0

;; RWTS command: reads a sector into the buffer.
;; Also: IBCRTS (DOS33, DOS31)
RWTS_READ = 1

;; RWTS command: writes a sector from the buffer.
;;
;; The file manager also stores this value in a file's write flags, where it means the file has been written
;; since it was opened.
;; Also: IBCWTS (DOS33, DOS31)
RWTS_WRITE = 2

;; RWTS command: formats the whole disk, writing every track's address fields and empty data fields.
;; Also: IBFMT (DOS33, DOS31)
RWTS_FORMAT = 4

.if DOS32 = 0
;; RWTS command, in DOS 3.3's list only: writes the boot tracks. Nothing in DOS uses it, and RWTS has no code for
;; it: with bit 0 clear, it would be taken as a write.
;; Also: IBBOOT (DOS33, DOS31)
RWTS_WRITE_BOOT = 8
.endif

; The errors, for <Iob::RETURN_CODE>. Each is one bit.

;; RWTS error: the sector could not be found or read. DOS 3.2's RWTS returns it; DOS 3.3's never does, and
;; reports an unreadable sector as <RWTS_DRIVE_ERROR>.
;; Also: IBRERR (DOS33, DOS31)
RWTS_READ_ERROR = $80

;; RWTS error: the drive failed: no address field or sector could be read on the track. DOS 3.2's formatter also
;; returns it when the disk cannot be formatted.
;; Also: IBDERR (DOS33, DOS31)
RWTS_DRIVE_ERROR = $40

;; RWTS error: the disk's volume is not the one the IOB asks for.
;; Also: IBVMME (DOS33, DOS31)
RWTS_VOLUME_MISMATCH = $20

;; RWTS error: the disk is write-protected.
;; Also: IBWPER (DOS33, DOS31)
RWTS_WRITE_PROTECTED = $10

;; DOS 3.3's formatter's error: a track could not be written or checked. The formatter writes it as a number.
RWTS_FORMAT_ERROR = 8

; The device characteristics table.

;; The layout of a DCT, the device characteristics table that describes a drive to <Rwts> (4 bytes).
;;
;; The IOB points at it (<Iob::DEVICE_TABLE>). DOS's own, for the Disk II, is <DosDeviceTable>.
.struct DeviceTable
    ;; The device type, 0 for the Disk II. Nothing reads it.
    DEVICE_TYPE .byte
    ;; Bit 0 set when the IOB gives whole tracks, which RWTS doubles into the half-tracks the head steps in; 1 for
    ;; the Disk II. Beneath Apple DOS calls the byte "phases per track", but a Disk II track is two half-track steps.
    WHOLE_TRACKS .byte
    ;; The motor's start-up wait, which RWTS loads into the motor-on count, <MotorTime>, and counts up to 0: $D8EF for
    ;; the Disk II. DOS 3.3's RWTS reads only the high byte, DOS 3.2's both.
    MOTOR_DELAY .word
.endstruct

; The track/sector list.

;; The number of pairs in a track/sector list, 122, the value of <Vtoc::PAIRS_PER_LIST>.
LIST_PAIR_COUNT = 122

;; A pair in a track/sector list: one data sector's place on the disk.
.struct TrackSectorPair
    ;; The track, or 0 when no sector has been allocated for this part of the file.
    ;; Also: FDTRK (DOS33, DOS31)
    TRACK .byte
    ;; The sector.
    ;; Also: FDSEC (DOS33, DOS31)
    SECTOR .byte
.endstruct

;; The layout of a track/sector list sector, which says where a stretch of a file's data is (256 bytes).
;;
;; A file's catalog entry points at its first list, and each list at the next. Each holds the places of up to 122
;; of the file's sectors, in the order of the file, starting at the relative sector in
;; <TrackSectorList::FIRST_SECTOR>. Apple's listing calls the layout FILDIR, a file directory, and the code reads
;; its fields through a pointer with Y = the offset. docs/Dos.md explains the lists.
.struct TrackSectorList
    ;; Byte 0: nothing uses it.
    ;; Also: FDUCDE (DOS33, DOS31)
    TYPE_CODE .byte
    ;; The track of the next list, or 0 in the last.
    ;; Also: FDLTRK (DOS33, DOS31)
    NEXT_TRACK .byte
    ;; The sector of the next list.
    ;; Also: FDLSEC (DOS33, DOS31)
    NEXT_SECTOR .byte
    ;; Byte 3: nothing uses it.
    ;; Also: FDNSA (DOS33, DOS31)
    SECTOR_COUNT .byte
    ;; Byte 4: nothing uses it.
    ;; Also: FDLSDL (DOS33, DOS31)
    LAST_LENGTH .byte
    ;; The relative sector, counting from 0 at the start of the file, that this list's first pair holds.
    ;; Also: FDFRS (DOS33, DOS31)
    FIRST_SECTOR .word
    ;; Bytes 7 to $0B: nothing uses them.
    ;; Also: FDSPAR (DOS33, DOS31)
    SPARE .res 5
    ;; The pairs, from byte $0C to the end of the sector.
    ;; Also: FDENT (DOS33, DOS31)
    PAIRS .tag TrackSectorPair, LIST_PAIR_COUNT
.endstruct

;; The size of a track/sector list, a whole sector: 256.
;; Also: FDLAST (DOS33, DOS31)
TRACK_SECTOR_LIST_SIZE = .sizeof(TrackSectorList)

; DOS's own IOB and DCT.

;; DOS's own IOB, laid out as <Iob>, which the boot loader's second stage, the file manager and
;; INIT fill in.
;;
;; At $B7E8 where DOS runs, in both versions; <LocateIob at IOBLDR> ($03E3) gives its address. It starts set for
;; slot 6, drive 1 and track 0, and the boot loader stores the boot slot in it; the rest holds what the master left
;; there.
;; Also: IOB (DOS33, DOS31)
.proc DosIob
.assert MASTER || * = $B7E8, "DOS's IOB is at $B7E8 where DOS runs."
;; <Iob::TYPE>: 1.
;; Also: IBTYPE (DOS33, DOS31)
Type:
    .byte 1
;; <Iob::SLOT_TIMES_16>: slot 6.
;; Also: IBSLOT (DOS33, DOS31)
SlotTimes16:
    .byte 6 * 16
;; <Iob::DRIVE>: drive 1.
;; Also: IBDRVN (DOS33, DOS31)
Drive:
    .byte 1
;; <Iob::VOLUME>: any volume.
;; Also: IBVOL (DOS33, DOS31)
Volume:
    .byte 0
;; <Iob::TRACK>: track 0.
;; Also: IBTRK (DOS33, DOS31)
Track:
    .byte 0
;; <Iob::SECTOR>.
;; Also: IBSECT (DOS33, DOS31)
Sector:
    Leftover $00, $01, $01
;; <Iob::DEVICE_TABLE>: DOS's DCT. The relocator adjusts it.
;; Also: IBDCTP (DOS33, DOS31)
DeviceTable:
    .word DosDeviceTable
;; <Iob::BUFFER>.
;; Also: IBBUFP (DOS33, DOS31)
Buffer:
    Leftover $00, $00, $00
    Leftover $00, $37, $37
;; <Iob::DATA_LENGTH>.
;; Also: IBDLEN (DOS33, DOS31)
DataLength:
    Leftover $00, $00, $00
    Leftover $01, $00, $00
;; <Iob::COMMAND>.
;; Also: IBCMD (DOS33, DOS31)
Command:
    Leftover $00, $02, $02
;; <Iob::RETURN_CODE>.
;; Also: IBSTAT (DOS33, DOS31)
ReturnCode:
    Leftover $00, $07, $07
;; <Iob::VOLUME_FOUND>.
;; Also: IBSMOD (DOS33, DOS31)
VolumeFound:
    Leftover $00, $FE, $FE
;; <Iob::PREVIOUS_SLOT>: slot 6.
;; Also: IBPSLT (DOS33, DOS31)
PreviousSlot:
    .byte 6 * 16
;; <Iob::PREVIOUS_DRIVE>: drive 1.
;; Also: IBPDRV (DOS33, DOS31)
PreviousDrive:
    .byte 1
;; <Iob::SPARE>.
;; Also: IBSPAR (DOS33, DOS31)
Spare:
    .res 2, 0
.endproc

;; DOS's DCT, laid out as <DeviceTable>: the Disk II's.
;;
;; At $B7FB where DOS runs, in both versions. <DosIob> points at it.
;; Also: DCT (DOS33, DOS31)
.proc DosDeviceTable
;; <DeviceTable::DEVICE_TYPE>: 0, the Disk II.
DeviceType:
    .byte 0
;; <DeviceTable::WHOLE_TRACKS>: 1, tracks of two half-track steps.
WholeTracks:
    .byte 1
;; <DeviceTable::MOTOR_DELAY>: $D8EF.
MotorDelay:
    .word $D8EF
.endproc

; The labeled bytes match the structs.
.assert .sizeof(DosIob) = .sizeof(Iob), "DosIob is an Iob."
.assert DosIob::Type - DosIob = Iob::TYPE, "DosIob::Type is Iob::TYPE."
.assert DosIob::SlotTimes16 - DosIob = Iob::SLOT_TIMES_16, "DosIob::SlotTimes16 is Iob::SLOT_TIMES_16."
.assert DosIob::Drive - DosIob = Iob::DRIVE, "DosIob::Drive is Iob::DRIVE."
.assert DosIob::Volume - DosIob = Iob::VOLUME, "DosIob::Volume is Iob::VOLUME."
.assert DosIob::Track - DosIob = Iob::TRACK, "DosIob::Track is Iob::TRACK."
.assert DosIob::Sector - DosIob = Iob::SECTOR, "DosIob::Sector is Iob::SECTOR."
.assert DosIob::DeviceTable - DosIob = Iob::DEVICE_TABLE, "DosIob::DeviceTable is Iob::DEVICE_TABLE."
.assert DosIob::Buffer - DosIob = Iob::BUFFER, "DosIob::Buffer is Iob::BUFFER."
.assert DosIob::DataLength - DosIob = Iob::DATA_LENGTH, "DosIob::DataLength is Iob::DATA_LENGTH."
.assert DosIob::Command - DosIob = Iob::COMMAND, "DosIob::Command is Iob::COMMAND."
.assert DosIob::ReturnCode - DosIob = Iob::RETURN_CODE, "DosIob::ReturnCode is Iob::RETURN_CODE."
.assert DosIob::VolumeFound - DosIob = Iob::VOLUME_FOUND, "DosIob::VolumeFound is Iob::VOLUME_FOUND."
.assert DosIob::PreviousSlot - DosIob = Iob::PREVIOUS_SLOT, "DosIob::PreviousSlot is Iob::PREVIOUS_SLOT."
.assert DosIob::PreviousDrive - DosIob = Iob::PREVIOUS_DRIVE, "DosIob::PreviousDrive is Iob::PREVIOUS_DRIVE."
.assert DosIob::Spare - DosIob = Iob::SPARE, "DosIob::Spare is Iob::SPARE."
.assert .sizeof(DosDeviceTable) = .sizeof(DeviceTable), "DosDeviceTable is a DeviceTable."
.assert DosDeviceTable::DeviceType - DosDeviceTable = DeviceTable::DEVICE_TYPE, "DeviceType is DEVICE_TYPE."
.assert DosDeviceTable::WholeTracks - DosDeviceTable = DeviceTable::WHOLE_TRACKS, "WholeTracks is WHOLE_TRACKS."
.assert DosDeviceTable::MotorDelay - DosDeviceTable = DeviceTable::MOTOR_DELAY, "MotorDelay is MOTOR_DELAY."
.assert TRACK_SECTOR_LIST_SIZE = 256, "A track/sector list is one sector."
