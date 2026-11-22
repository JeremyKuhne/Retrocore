; retrocore: style=strict ignore=unlinked-name:LOCK -- commands, messages, RWTS
;; DOS 3.3 and 3.2 file manager: the parameter list, the VTOC and catalog buffers and the file control block
;;
;; The file manager's data and the layouts it works with: the parameter list through which a program or DOS's
;; command interpreter asks the file manager for something, with the codes that go in it; buffers for the VTOC
;; (the volume table of contents, track 17 sector 0) and for one catalog sector, with the fields named as they are
;; on the disk; the file control block, the 45 bytes that describe an open file while a request runs; and the file
;; manager's work cells and CATALOG's tables. docs/Dos.md explains the VTOC, the catalog, track/sector lists and the
;; file manager's calls; the track/sector list's layout is in IoBlock.asm.
;;
;; Where DOS runs, the data is at $B397-$B5FD, just below the boot loader's page at $B600: the work cells and tables
;; from $B397, the VTOC buffer at $B3BB, the catalog buffer at $B4BB, the parameter list at $B5BB and the file control
;; block at $B5D1. Each open file keeps its own copy of the file control block in its DOS buffer (its work area):
;; <FileManager::LoadWorkArea> copies it in when a request starts and <FileManager::SaveWorkArea> copies it back when it
;; ends.
;;
;; Where Apple's source only reserves space (.res) or skips to the end of a buffer (.org), each master holds whatever
;; was in memory when its DOS image was saved; the master's VTOC and catalog buffers, parameter list and file control
;; block still held data then (in the 1980 and DOS 3.2 masters, mostly the VTOC of a freshly formatted disk and
;; zeros). Those bytes are kept here as data, after a "leftover" comment naming Apple's directive, so each image is
;; exact. They mean nothing: DOS reads a sector into a buffer, or fills in the parameter list or file control
;; block, before it uses them.

; The disk.

;; The track of the VTOC and of the catalog, 17, the middle of the disk, so that the head never has far to go.
VTOC_TRACK = 17

;; The number of tracks on a disk, 35.
TRACKS_PER_DISK = 35

.if DOS32
;; The number of sectors on a track: 13 on DOS 3.2's disks.
SECTORS_PER_TRACK = 13
.else
;; The number of sectors on a track: 16 on DOS 3.3's disks.
SECTORS_PER_TRACK = 16
.endif

;; The size of a sector, 256 bytes.
SECTOR_SIZE = 256

;; How many bytes of the VTOC's free-sector map each track has, 4.
FREE_MAP_BYTES_PER_TRACK = 4

; The parameter list.

;; The layout of the file manager's parameter list, which a program fills in and passes to the file manager
;; through the vector at $03D6 (22 bytes).
;;
;; Several fields mean different things for different requests, so they overlap. DOS's own parameter list, which
;; the vector at $03DC returns, is <DosFileParameters>; its labels carry Apple's names.
.struct FileParameters
    ;; The request, a REQUEST_ code such as <REQUEST_OPEN>.
    REQUEST .byte
    .union
        ;; For READ and WRITE: the kind of transfer, a TRANSFER_ code such as <TRANSFER_NEXT_BYTE>.
        TRANSFER .byte
        ;; For INIT: the page where the DOS image to write starts.
        IMAGE_PAGE .byte
    .endunion
    .union
        ;; For POSITION and positioned transfers: the record number; on return, the record of the last byte moved.
        RECORD .word
        ;; For RENAME: the address of the new name.
        NEW_NAME .addr
        ;; For OPEN: the record length, where 0 means 256.
        RECORD_LENGTH .word
    .endunion
    .union
        ;; For POSITION and positioned transfers: the byte in the record; on return, as <RECORD at
        ;; FileParameters::RECORD>.
        BYTE_OFFSET .word
        .struct
            ;; For the requests that name a disk: the volume, 0 for any; on return, the volume found.
            VOLUME .byte
            ;; For the requests that name a disk: the drive, 1 or 2.
            DRIVE .byte
        .endstruct
    .endunion
    .union
        ;; For a range transfer: the number of bytes.
        RANGE_LENGTH .word
        .struct
            ;; For the requests that name a disk: the slot, 1 to 7.
            SLOT .byte
            ;; For OPEN: the type for a new file, a FILE_TYPE_ code; on return, the type of the file opened.
            FILE_TYPE .byte
        .endstruct
    .endunion
    .union
        ;; The address of the file's name: 30 characters with bit 7 set, padded with spaces.
        NAME .addr
        ;; For a range transfer: the address of the caller's buffer, advanced as bytes go.
        RANGE_ADDRESS .addr
        ;; For a one-byte transfer: the byte.
        DATA .byte
    .endunion
    ;; The result: 0 for success, or an ERROR_ code such as <ERROR_FILE_NOT_FOUND>, with the carry set.
    RETURN_CODE .byte
    ;; Nothing uses it.
    RETURN_MODIFIER .byte
    ;; The address of the open file's work area, its copy of the file control block.
    WORK_AREA .addr
    ;; The address of the file's track/sector list buffer.
    LIST_BUFFER .addr
    ;; The address of the file's data sector buffer.
    DATA_BUFFER .addr
    ;; Four bytes nothing uses.
    SPARE .res 4
.endstruct

; The requests, for <FileParameters::REQUEST>.

;; File manager request: does nothing.
;; Also: CRQNUL (DOS33, DOS31)
REQUEST_NONE = 0

;; File manager request: finds the file and sets up its work area, creating the file if the command allows.
;; Also: CRQOPN (DOS33, DOS31)
REQUEST_OPEN = 1

;; File manager request: writes what is pending and updates the file's catalog entry.
;; Also: CRQCLS (DOS33, DOS31)
REQUEST_CLOSE = 2

;; File manager request: reads, as <FileParameters::TRANSFER> says.
;; Also: CRQRD (DOS33, DOS31)
REQUEST_READ = 3

;; File manager request: writes, as <FileParameters::TRANSFER> says. It is the only request for which the file
;; manager allocates new sectors.
;; Also: CRQWR (DOS33, DOS31)
REQUEST_WRITE = 4

;; File manager request: deletes the file, freeing its sectors.
;; Also: CRQDEL (DOS33, DOS31)
REQUEST_DELETE = 5

;; File manager request: prints the catalog. Apple's listing calls it reading the directory.
;; Also: CRQDIR (DOS33, DOS31)
REQUEST_CATALOG = 6

;; File manager request: locks the file.
;; Also: CRQLCK (DOS33, DOS31)
REQUEST_LOCK = 7

;; File manager request: unlocks the file.
;; Also: CRQUNL (DOS33, DOS31)
REQUEST_UNLOCK = 8

;; File manager request: renames the file to the name at <FileParameters::NEW_NAME>.
;; Also: CRQRNM (DOS33, DOS31)
REQUEST_RENAME = 9

;; File manager request: sets the position from <FileParameters::RECORD> and <FileParameters::BYTE_OFFSET>.
;; Also: CRQPOS (DOS33, DOS31)
REQUEST_POSITION = 10

;; File manager request: formats the disk and writes DOS, the VTOC and an empty catalog.
;; Also: CRQFMT (DOS33, DOS31)
REQUEST_INIT = 11

;; File manager request: reads every sector of the file, to check that it can be read.
;; Also: CRQVAR (DOS33, DOS31)
REQUEST_VERIFY = 12

;; The number of requests, the first code out of range, which the file manager refuses with <ERROR_RANGE>.
;; Also: CRQMAX (DOS33, DOS31)
REQUEST_COUNT = 13

; The transfers, for <FileParameters::TRANSFER>.

;; Transfer: none.
;; Also: CRMNUL (DOS33, DOS31)
TRANSFER_NONE = 0

;; Transfer: the next byte, in <FileParameters::DATA>.
;; Also: CRMNBT (DOS33, DOS31)
TRANSFER_NEXT_BYTE = 1

;; Transfer: the next range of bytes, <FileParameters::RANGE_LENGTH> of them at
;; <FileParameters::RANGE_ADDRESS>. Apple's listing calls a range a block.
;; Also: CRMNBL (DOS33, DOS31)
TRANSFER_NEXT_RANGE = 2

;; Transfer: positions as <REQUEST_POSITION> does, then moves one byte.
;; Also: CRMSBT (DOS33, DOS31)
TRANSFER_POSITIONED_BYTE = 3

;; Transfer: positions, then moves a range of bytes.
;; Also: CRMSBL (DOS33, DOS31)
TRANSFER_POSITIONED_RANGE = 4

;; The number of transfers, the first code out of range, which the file manager refuses with
;; <ERROR_TRANSFER_RANGE>.
;; Also: CRMMAX (DOS33, DOS31)
TRANSFER_COUNT = 5

; DOS's error numbers, 1 to 15. The file manager returns 1 to 10 in <FileParameters::RETURN_CODE>; the command
; interpreter adds 11 to 15 for its own errors, and prints each number's message.

;; Error 1, LANGUAGE NOT AVAILABLE: OPEN found no file while the FP command was looking for the RAM Applesoft.
;; Also: CREFUN (DOS33, DOS31)
ERROR_LANGUAGE_NOT_AVAILABLE = 1

;; Error 2, RANGE ERROR: the file manager's request code is out of range, or a command's number is.
;; Also: CRERR (DOS33, DOS31)
ERROR_RANGE = 2

;; Error 3, RANGE ERROR too: the READ or WRITE transfer code is out of range.
;; Also: CREMRE (DOS33, DOS31)
ERROR_TRANSFER_RANGE = 3

;; Error 4, WRITE PROTECTED.
;; Also: CREPRO (DOS33, DOS31)
ERROR_WRITE_PROTECTED = 4

;; Error 5, END OF DATA: a read ran past the end of the file.
;; Also: CREEOF (DOS33, DOS31)
ERROR_END_OF_DATA = 5

;; Error 6, FILE NOT FOUND. With the carry clear, OPEN created the file.
;; Also: CREFNF (DOS33, DOS31)
ERROR_FILE_NOT_FOUND = 6

;; Error 7, VOLUME MISMATCH: the disk's volume is not the one asked for.
;; Also: CREVMM (DOS33, DOS31)
ERROR_VOLUME_MISMATCH = 7

;; Error 8, I/O ERROR: any other disk error.
;; Also: CREIOE (DOS33, DOS31)
ERROR_IO = 8

;; Error 9, DISK FULL: no sector is free, or the catalog has no free entry.
;; Also: CRENSA (DOS33, DOS31)
ERROR_DISK_FULL = 9

;; Error 10, FILE LOCKED.
;; Also: CREFLK (DOS33, DOS31)
ERROR_FILE_LOCKED = 10

;; Error 11, SYNTAX ERROR: the command interpreter could not read a command.
ERROR_SYNTAX = 11

;; Error 12, NO BUFFERS AVAILABLE: every file buffer is in use.
ERROR_NO_BUFFERS = 12

;; Error 13, FILE TYPE MISMATCH: the file is not of the type the command needs.
ERROR_FILE_TYPE_MISMATCH = 13

;; Error 14, PROGRAM TOO LARGE: the program does not fit in memory; SAVE also gives it for a run-only Applesoft
;; program.
ERROR_PROGRAM_TOO_LARGE = 14

;; Error 15, NOT DIRECT COMMAND: a command a program must give was typed.
ERROR_NOT_DIRECT = 15

; The VTOC and the catalog.

;; The layout of the VTOC, the volume table of contents on track 17 sector 0 (256 bytes): where the catalog starts
;; and which sectors are free.
;;
;; The file manager's copy is <FileManager::VtocBuffer>; its labels carry Apple's names.
.struct Vtoc
    ;; Byte 0, which nothing reads: 4, or 2 on DOS 3.2's disks.
    DOS_TYPE .byte
    ;; The track of the first catalog sector, <VTOC_TRACK>.
    CATALOG_TRACK .byte
    ;; The sector of the first catalog sector, the track's last: 15, or 12 on DOS 3.2's disks.
    CATALOG_SECTOR .byte
    ;; The release of DOS that initialized the disk; nothing reads it.
    DOS_RELEASE .byte
    .res 2
    ;; The disk's volume number, 1 to 254.
    VOLUME .byte
    .res 32
    ;; How many track/sector pairs fit in one track/sector list, <LIST_PAIR_COUNT>.
    PAIRS_PER_LIST .byte
    ;; Eight bytes nothing uses.
    SPARE .res 8
    ;; The track the file manager last reserved for a file, where its search for a free track starts.
    LAST_ALLOCATED_TRACK .byte
    ;; The direction of that search, 1 (up) or $FF (down).
    ALLOCATION_DIRECTION .byte
    ;; Nothing uses it.
    ALLOCATION_BYTE_3 .byte
    ;; Nothing uses it.
    ALLOCATION_BYTE_4 .byte
    ;; The number of tracks, <TRACKS_PER_DISK>.
    TRACK_COUNT .byte
    ;; The number of sectors per track, <SECTORS_PER_TRACK>.
    SECTORS_PER_TRACK .byte
    ;; The bytes per sector, <SECTOR_SIZE>; nothing reads it.
    BYTES_PER_SECTOR .word
    ;; The free-sector bit map, <FREE_MAP_BYTES_PER_TRACK> bytes a track from track 0, room for 50 tracks.
    ;;
    ;; A set bit is a free sector. The first byte holds sectors 15 to 8 and the second 7 to 0, the highest sector in
    ;; bit 7; the last two bytes are unused on a 16-sector disk. On DOS 3.2's 13-sector disks the first byte holds
    ;; sectors 12 to 5 and the second 4 to 0, and the second byte's low three bits are unused too.
    FREE_SECTORS .res 200
.endstruct

;; The number of file entries in a catalog sector, 7.
CATALOG_ENTRY_COUNT = 7

;; The length of a file name, 30 characters.
CATALOG_NAME_LENGTH = 30

;; The layout of one file's entry in a catalog sector (35 bytes). Apple's listing has no names for its fields, only
;; offsets from the entries' start.
.struct CatalogEntry
    ;; The track of the file's first track/sector list; 0 if the entry was never used, <ENTRY_DELETED> if the file
    ;; was deleted, when the old track is kept in the name's last byte.
    LIST_TRACK .byte
    ;; The sector of the file's first track/sector list.
    LIST_SECTOR .byte
    ;; The file's type, a FILE_TYPE_ code, plus <FILE_LOCKED> when the file is locked.
    TYPE .byte
    ;; The name, <CATALOG_NAME_LENGTH> characters with bit 7 set, padded with spaces.
    NAME .res CATALOG_NAME_LENGTH
    ;; The file's length in sectors, counting its track/sector lists.
    LENGTH .word
.endstruct

;; The layout of a catalog sector (256 bytes). The catalog is a chain of them, normally track 17 sectors 15 down to
;; 1 (12 down to 1 on DOS 3.2's disks), each holding seven file entries.
;;
;; The file manager's copy is <FileManager::CatalogBuffer>; its labels carry Apple's names.
.struct CatalogSector
    ;; Byte 0, which nothing reads.
    TYPE_CODE .byte
    ;; The track of the next catalog sector, 0 in the last.
    NEXT_TRACK .byte
    ;; The sector of the next catalog sector.
    NEXT_SECTOR .byte
    ;; Byte 3, which nothing uses.
    FILE_COUNT .byte
    ;; Seven bytes nothing uses.
    SPARE .res 7
    ;; The file entries.
    ENTRIES .tag CatalogEntry, CATALOG_ENTRY_COUNT
.endstruct

;; <CatalogEntry::LIST_TRACK>'s value in a deleted file's entry.
ENTRY_DELETED = $FF

;; The bit of <CatalogEntry::TYPE> that is set when the file is locked.
FILE_LOCKED = $80

; The file types, for <CatalogEntry::TYPE> and <FileParameters::FILE_TYPE>. CATALOG prints each as a letter.

;; File type: a text file, T.
FILE_TYPE_TEXT = $00

;; File type: an Integer BASIC program, I.
FILE_TYPE_INTEGER = $01

;; File type: an Applesoft program, A.
FILE_TYPE_APPLESOFT = $02

;; File type: a binary file, B.
FILE_TYPE_BINARY = $04

;; File type: S, which DOS has no command for.
FILE_TYPE_S = $08

;; File type: a relocatable object file, R, which DOS has no command for.
FILE_TYPE_RELOCATABLE = $10

;; File type: A, a second kind DOS has no command for.
FILE_TYPE_A = $20

;; File type: B, a second kind DOS has no command for.
FILE_TYPE_B = $40

; The write flags, for <FileManager::FileControlBlock::WriteFlags>.

;; Write flag: the track/sector list buffer has changed and must be written.
WRITE_LIST = $80

;; Write flag: the data sector buffer has changed and must be written.
WRITE_DATA = $40

;; Write flag: something has been written since OPEN, so CLOSE updates the catalog's sector count. The file
;; manager sets it by ORing in the IOB's command, which is then <RWTS_WRITE>.
WRITTEN = RWTS_WRITE

; The file manager's work cells and CATALOG's tables, at $B397 where DOS runs.
.scope FileManager continued

;; The track of the catalog sector in <CatalogBuffer>, where <FileManager::WriteCatalogSector> writes it back.
;; Also: CVDTRK (DOS33, DOS31)
CurrentCatalogTrack:
    Leftover $00, $11, $00

;; The sector of the catalog sector in <CatalogBuffer>, where <FileManager::WriteCatalogSector> writes it back.
;; Also: CVDSEC (DOS33, DOS31)
CurrentCatalogSector:
    Leftover $00, $0D, $00

;; Two bytes nothing in DOS refers to. DOS 3.1's comment calls them the current parameter list's address.
;; Also: CURCCB (DOS33, DOS31)
CurrentParameters:
    .byte 0, 0

;; The stack pointer when the file manager was entered (<CallFileManager::ForDos>); <FileManager::Leave> restores it to
;; leave from any depth.
;; Also: ENTSTK (DOS33, DOS31)
EntryStack:
    Leftover $00, $F5, $F5

;; Scratch: the offset of the catalog entry being looked at (<FileManager::FindFile>, OPEN, DELETE, LOCK, RENAME,
;;     CATALOG), DELETE's index into the track/sector list, and the relocator's saved X.
;; Also: TEMP1 (DOS33, DOS31)
Scratch1:
    Leftover $00, $23, $00

;; Scratch: <FileManager::FindFile>'s pass (1, then 0), <FileManager::AllocateDataSector>'s saved index, the lines left
;;     on CATALOG's screen.
;; Also: TEMP2 (DOS33, DOS31)
Scratch2:
    Leftover $00, $01, $00

;; Scratch: <FileManager::AllocateSector>'s search state (1 once it has turned round at track 0); the lock bit for LOCK
;;     and UNLOCK.
;; Also: TEMP3 (DOS33, DOS31)
Scratch3:
    .byte 0

;; A byte nothing in DOS refers to. DOS 3.1's comment calls it the boot slot, saved.
;; Also: ENTSLT (DOS33, DOS31)
BootSlot:
    .byte 0

;; The free-sector map of an empty track, last byte first: INIT (<FileManager::InitDisk>) copies it into each track of
;; the VTOC's map from the end, giving $FF $FF $00 $00 (sectors 15 to 0 free) for every track but 0 to 2 (DOS) and 17
;; (the VTOC and catalog). DOS 3.2's is that of a 13-sector track, $FF $F8 $00 $00.
;; Also: ALC10S (DOS33, DOS31)
EmptyTrackMap:
.if DOS32
    .byte 0, 0, $F8, $FF
.else
    .byte 0, 0, $FF, $FF
.endif

;; The powers of ten CATALOG's <FileManager::PrintNumber> divides by, used from 100 down, to print a three-digit number.
;; Also: CVTAB (DOS33, DOS31)
PowersOfTen:
    .byte 1, 10, 100

;; The letter CATALOG prints for each file type, indexed by the position of the type's highest set bit: T (text,
;; $00), I (Integer BASIC, $01), A (Applesoft, $02), B (binary, $04), S ($08), R (relocatable, $10), A ($20) and B
;; ($40).
;; Also: FTTAB (DOS33, DOS31)
TypeLetters:
    .hiascii "TIAB"
    .hiascii "SRAB"

;; "DISK VOLUME " backwards: CATALOG prints it from the last byte to the first, before the volume number.
;; Also: VOLMES (DOS33, DOS31)
VolumeMessage:
    .hiascii " EMULOV KSID"

;; The index of <VolumeMessage>'s last byte, where printing starts.
;; Also: VML (DOS33, DOS31)
VOLUME_MESSAGE_LAST = * - VolumeMessage - 1

;; The VTOC buffer, laid out as <Vtoc>: one sector, read from and written to track 17 sector 0 (<FileManager::ReadVtoc>,
;; <FileManager::WriteVtoc>).
;;
;; At $B3BB where DOS runs. The values assembled here are those of an empty 35-track disk. INIT
;; (<FileManager::InitDisk>) sets the volume number, the allocation fields and the bit map, zeroing everything from
;; <VtocBuffer::FreeSectors> on, then writes the buffer as the new disk's VTOC; the other fields go out as the buffer
;; holds them at the time.
;; Also: VTOC (DOS33, DOS31)
.proc VtocBuffer
;; <Vtoc::DOS_TYPE>: 4, or 2 in DOS 3.2.
;; Also: VDOST (DOS33, DOS31)
DosType:
.if DOS32
    .byte 2
.else
    .byte 4
.endif
;; <Vtoc::CATALOG_TRACK>.
;; Also: VDIRTK (DOS33, DOS31)
CatalogTrack:
    .byte VTOC_TRACK
;; <Vtoc::CATALOG_SECTOR>: the VTOC track's last sector.
;; Also: VDIRSC (DOS33, DOS31)
CatalogSector:
    .byte SECTORS_PER_TRACK - 1
;; <Vtoc::DOS_RELEASE>: 4 here, and 2 in DOS 3.2, then two unused bytes.
;; Also: VDOSRN (DOS33, DOS31)
DosRelease:
.if DOS32
    .byte 2
.else
    .byte 4
.endif
    .byte 0
    .byte 0
;; <Vtoc::VOLUME>: 254, then 32 unused bytes.
;; Also: VVOLNO (DOS33, DOS31)
Volume:
    .byte $FE
; leftover: .res 32
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FE, $FC, $FC, $FE, $FC, $FC, $FD, $FF, $FC, $FF, $FC, $FC, $FD, $FC, $FF
    .byte $FE, $FC, $FD, $FE, $FC, $FC, $FD, $FC, $FF, $FC, $FC, $FF, $FF, $FE, $FC, $FC
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.endif
;; <Vtoc::PAIRS_PER_LIST>. OPEN copies it to the file control block's <FileControlBlock::PairsPerList>.
;; Also: VTDMS (DOS33, DOS31)
PairsPerList:
    .byte LIST_PAIR_COUNT
;; <Vtoc::SPARE>.
;; Also: VSPARE (DOS33, DOS31)
Spare:
; leftover: .res 8
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FC, $FC, $FD, $FC, $FC, $FE, $FC
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00, $00
.endif
;; <Vtoc::LAST_ALLOCATED_TRACK>: the catalog's track, so that the first file goes next to it.
;; Also: VALCA1 (DOS33, DOS31)
LastAllocatedTrack:
    .byte VTOC_TRACK
;; <Vtoc::ALLOCATION_DIRECTION>: up.
;; Also: VALCA2 (DOS33, DOS31)
AllocationDirection:
    .byte 1
;; <Vtoc::ALLOCATION_BYTE_3>. DOS 3.1's comment calls it allocation algorithm byte 3.
;; Also: VALCA3 (DOS33, DOS31)
AllocationByte3:
    .byte 0
;; <Vtoc::ALLOCATION_BYTE_4>.
;; Also: VALCA4 (DOS33, DOS31)
AllocationByte4:
    .byte 0
;; <Vtoc::TRACK_COUNT>.
;; Also: VNOTRK (DOS33, DOS31)
TrackCount:
    .byte TRACKS_PER_DISK
;; <Vtoc::SECTORS_PER_TRACK>.
;; Also: VNOSEC (DOS33, DOS31)
SectorsPerTrack:
    .byte SECTORS_PER_TRACK
;; <Vtoc::BYTES_PER_SECTOR>. Nothing in DOS reads it; the file manager's OPEN sets
;; <FileControlBlock::SectorLength> to 256 itself.
;; Also: VSECLN (DOS33, DOS31)
BytesPerSector:
    .word SECTOR_SIZE
;; <Vtoc::FREE_SECTORS>. <FileManager::AllocateSector>, <FileManager::ReleaseTrack> and <FileManager::MergeFreeMap> read
;; and change it.
;; Also: VSECAL (DOS33, DOS31)
FreeSectors:
; leftover: .org VTOC+256 (the rest of the VTOC buffer)
.if DOS32
    ; leftover: what the DOS 3.2 master holds here
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $00, $00, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00
    .byte $FF, $F8, $00, $00, $FF, $F8, $00, $00, $FF, $F8, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00
.elseif YEAR = 1983
    .byte $FF, $FD, $FC, $FC, $FD, $FC, $FC, $FD, $FD, $FC, $FD, $FE, $FC, $FE, $FF, $FC
    .byte $FD, $FE, $FC, $FE, $FC, $FC, $FD, $FF, $FC, $FF, $FF, $FD, $FF, $FC, $FF, $FC
    .byte $FC, $FD, $FC, $FC, $FC, $FD, $FC, $FF, $FC, $FC, $FF, $FF, $FD, $FD, $FC, $FE
    .byte $FD, $FC, $FC, $FE, $FC, $FC, $FC, $FC, $FE, $FD, $FE, $FC, $FC, $FE, $FD, $FC
    .byte $FC, $FC, $FC, $FD, $FC, $FC, $FC, $FD, $FC, $FD, $FE, $FF, $FE, $FD, $FF, $FC
    .byte $FC, $FE, $FE, $FC, $FE, $FD, $FC, $FD, $FD, $FC, $FF, $FC, $FC, $FD, $FC, $FE
    .byte $FC, $FC, $FD, $FC, $FC, $FC, $FD, $FC, $FF, $FD, $FE, $FF, $FE, $FD, $FC, $FC
    .byte $FF, $FF, $FC, $FC, $FD, $FC, $FC, $FD, $FC, $FE, $FD, $FE, $FF, $FF, $FD, $FD
    .byte $FC, $FC, $FD, $FC, $FD, $FD, $FC, $FC, $FD, $FF, $FC, $FD, $FE, $FF, $FE, $FE
    .byte $FE, $FC, $FD, $FC, $FC, $FF, $FC, $FD, $FF, $FC, $FD, $FC, $FC, $FD, $FE, $FC
    .byte $FC, $FF, $FC, $FF, $FC, $FE, $FF, $FC, $FC, $FF, $FE, $FE, $FE, $FF, $FC, $FC
    .byte $FC, $FC, $FF, $FC, $FC, $FE, $FC, $FC, $FC, $FC, $FE, $FD, $FE, $FD, $FC, $FF
    .byte $FD, $FC, $FC, $FD, $FC, $FD, $FF, $FC
.else
    ; leftover: what the 1980 master holds here
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $00, $00, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00
    .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00
.endif
.endproc

;; The catalog buffer, laid out as <CatalogSector>: one catalog sector (<FileManager::ReadCatalogSector>,
;; <FileManager::WriteCatalogSector>).
;;
;; At $B4BB where DOS runs. INIT zeroes it before it writes the catalog.
;; Also: VOLDIR (DOS33, DOS31)
.proc CatalogBuffer
;; <CatalogSector::TYPE_CODE>.
;; Also: VDTCDE (DOS33, DOS31)
TypeCode:
    Leftover $02, $00, $00
;; <CatalogSector::NEXT_TRACK>.
;; Also: VDLTRK (DOS33, DOS31)
NextTrack:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; <CatalogSector::NEXT_SECTOR>.
;; Also: VDLSEC (DOS33, DOS31)
NextSector:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; <CatalogSector::FILE_COUNT>. DOS 3.1's comment calls it the number of files in the sector.
;; Also: VDNF (DOS33, DOS31)
FileCount:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; <CatalogSector::SPARE>.
;; Also: VDSPAR (DOS33, DOS31)
Spare:
; leftover: .res 7
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FD, $FC, $FD, $FD, $FC, $FC
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00
.endif
;; <CatalogSector::ENTRIES>, each laid out as <CatalogEntry>. The file manager reaches an entry's fields with X
;; = the entry's offset from here.
;; Also: VDFILE (DOS33, DOS31)
Entries:
; leftover: .org VOLDIR+256 (the rest of the catalog buffer)
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FF, $FC, $FC, $FD, $FC, $FC, $FC, $FE, $FC, $FF, $FC, $FC, $FF, $FF, $FD
    .byte $FF, $FF, $FE, $FF, $FD, $FC, $FE, $FC, $FC, $FC, $FC, $FE, $FE, $FE, $FC, $FD
    .byte $FC, $FE, $FC, $FE, $FC, $FC, $FF, $FC, $FC, $FC, $FD, $FC, $FD, $FD, $FC, $FC
    .byte $FF, $FC, $FD, $FD, $FF, $FD, $FE, $FC, $FD, $FD, $FC, $FE, $FF, $FC, $FD, $FF
    .byte $FC, $FF, $FE, $FD, $FE, $FC, $FC, $FD, $FC, $FD, $FE, $FC, $FC, $FC, $FC, $FF
    .byte $FD, $FC, $FF, $FC, $FC, $FC, $FC, $FF, $FC, $FC, $FC, $FD, $FC, $FC, $FD, $FC
    .byte $FE, $FF, $FE, $FC, $FC, $FC, $FF, $FC, $FC, $FC, $FC, $FD, $FC, $FC, $FC, $FC
    .byte $FC, $FD, $FE, $FE, $FD, $FE, $FD, $FF, $FC, $FE, $FE, $FC, $FE, $FD, $FC, $FD
    .byte $FD, $FE, $FF, $FE, $FC, $FF, $FC, $FF, $FC, $FC, $FD, $FC, $FC, $FF, $FC, $FF
    .byte $FF, $FC, $FC, $FC, $FD, $FC, $FE, $FC, $FC, $FD, $FC, $FE, $FC, $FE, $FC, $FD
    .byte $FC, $FC, $FD, $FC, $FE, $FD, $FD, $FC, $FC, $FC, $FC, $FC, $FD, $FF, $FF, $FC
    .byte $FD, $FD, $FC, $FC, $FE, $FC, $FC, $FF, $FC, $FC, $FE, $FD, $FC, $FE, $FE, $FC
    .byte $FD, $FC, $FC, $FF, $FD, $FD, $FF, $FC, $FC, $FF, $FC, $FD, $FE, $FC, $FC, $FF
    .byte $FC, $FF, $FC, $FC, $FF, $FC, $FC, $FD, $FC, $FE, $FD, $FC, $FC, $FC, $FC, $FC
    .byte $FD, $FC, $FE, $FE, $FE, $FD, $FE, $FF, $FE, $FC, $FC, $FC, $FC, $FD, $FC, $FC
    .byte $FC, $FD, $FC, $FD, $FE
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00
.endif
;; The address after the buffer. Nothing uses it.
;; Also: VDEND (DOS33, DOS31)
End:
.endproc

.endscope

;; DOS's own parameter list, laid out as <FileParameters>, which the command interpreter fills in to call the file
;; manager (<CallFileManager::ForDos>).
;;
;; At $B5BB where DOS runs; the vector at $03DC, <LocateParameterList at CCBLDR>, gives its address.
;; <Scanner::ClearParameterList> clears it before each command. Several labels share a byte, as the struct's fields
;; overlap.
;; Also: CCB (DOS33, DOS31)
.proc DosFileParameters
.assert MASTER || * = $B5BB, "DOS's parameter list is at $B5BB where DOS runs."
;; <FileParameters::REQUEST>. The file manager's entry dispatches on it.
;; Also: CCBREQ (DOS33, DOS31)
Request:
    ; leftover: .res 1
    Leftover $FD, $0B, $0B
;; <FileParameters::IMAGE_PAGE>. The boot loader's INIT writer reads it.
;; Also: CCBBSA (DOS33, DOS31)
ImagePage:
;; <FileParameters::TRANSFER>.
;; Also: CCBRQM (DOS33, DOS31)
Transfer:
    ; leftover: .res 1
    Leftover $FD, $1B, $1B
;; <FileParameters::RECORD>.
;; Also: CCBRRN (DOS33, DOS31)
Record:
;; <FileParameters::NEW_NAME>.
;; Also: CCBFN2 (DOS33, DOS31)
NewName:
;; <FileParameters::RECORD_LENGTH>: 0 means 256, as the file manager's OPEN turns it into $0100.
;; Also: CCBRLN (DOS33, DOS31)
RecordLength:
    ; leftover: .res 2
    Leftover $FD, $01, $01
    Leftover $FC, $00, $00
;; <FileParameters::BYTE_OFFSET>.
;; Also: CCBBYT (DOS33, DOS31)
ByteOffset:
;; <FileParameters::VOLUME>. Every disk access sets it to the volume found on the disk.
;; Also: CCBVOL (DOS33, DOS31)
Volume:
    ; leftover: .res 1
    Leftover $FC, $FE, $FE
;; <FileParameters::DRIVE>.
;; Also: CCBDRV (DOS33, DOS31)
Drive:
    ; leftover: .res 1
    Leftover $FD, $01, $01
;; <FileParameters::RANGE_LENGTH>.
;; Also: CCBBLN (DOS33, DOS31)
RangeLength:
;; <FileParameters::SLOT>.
;; Also: CCBSLT (DOS33, DOS31)
Slot:
    ; leftover: .res 1
    Leftover $FF, $06, $06
;; <FileParameters::FILE_TYPE>.
;; Also: CCBFUC (DOS33, DOS31)
FileType:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; <FileParameters::NAME>.
;; Also: CCBFN1 (DOS33, DOS31)
Name:
;; <FileParameters::RANGE_ADDRESS>.
;; Also: CCBBBA (DOS33, DOS31)
RangeAddress:
;; <FileParameters::DATA>.
;; Also: CCBDAT (DOS33, DOS31)
Data:
    ; leftover: .res 2
    Leftover $FC, $75, $75
    Leftover $FD, $2A, $2A
;; <FileParameters::RETURN_CODE>.
;; Also: CCBSTA (DOS33, DOS31)
ReturnCode:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; <FileParameters::RETURN_MODIFIER>. DOS 3.1's comment calls it the status modifier.
;; Also: CCBSM (DOS33, DOS31)
ReturnModifier:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; <FileParameters::WORK_AREA>. <FileManager::PointAtWorkArea>, <FileManager::PointAtListBuffer> and
;; <FileManager::PointAtDataBuffer> reach the three buffer addresses as WorkArea + 0, 2 and 4, so the three stay in this
;; order.
;; Also: CCBFCB (DOS33, DOS31), CFCBAD (DOS33, DOS31)
WorkArea:
    ; leftover: .res 2
    Leftover $FF, $00, $00
    Leftover $FC, $18, $18
;; <FileParameters::LIST_BUFFER>, laid out as <TrackSectorList>.
;; Also: CCBDBP (DOS33, DOS31), CFCBDR (DOS33, DOS31)
ListBuffer:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $17, $17
;; <FileParameters::DATA_BUFFER>.
;; Also: CCBSBP (DOS33, DOS31), CFCBSB (DOS33, DOS31)
DataBuffer:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $16, $16
;; <FileParameters::SPARE>.
;; Also: CCBSPR (DOS33, DOS31)
Spare:
    ; leftover: .res 4
    Leftover $FF, $00, $00
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
.endproc

; The file control block, at $B5D1 where DOS runs.
.scope FileManager continued

;; The file control block: the 45 bytes that describe the open file while a request runs.
;;
;; <FileManager::LoadWorkArea> copies the file's work area here when a request starts, and <FileManager::SaveWorkArea>
;; copies it back when it ends, so a file's state lives in its DOS buffer between requests. OPEN
;; (<FileManager::SetUpWorkArea>) clears it and fills it in. Apple's names for its fields start with DCB, "data control
;; block": the DCB is the whole of it. The pairs of bytes hold a low byte, then a high byte. A relative sector counts
;; the file's sectors from 0 at its start.
;; Also: FCB (DOS33), FCBB (DOS31), FCBDCB (DOS33, DOS31)
.proc FileControlBlock
;; Byte 0: the track of the file's first track/sector list.
;; Also: DCBFDT (DOS33, DOS31)
FirstListTrack:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; Byte 1: the sector of the file's first track/sector list.
;; Also: DCBFDS (DOS33, DOS31)
FirstListSector:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; Byte 2: the track of the track/sector list in the list buffer.
;; Also: DCBCDT (DOS33, DOS31)
ListTrack:
    ; leftover: .res 1
    Leftover $FF, $00, $00
;; Byte 3: the sector of the track/sector list in the list buffer.
;; Also: DCBCDS (DOS33, DOS31)
ListSector:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; Byte 4: what needs writing: <WRITE_LIST>, <WRITE_DATA> and <WRITTEN>.
;; Also: DCBWRF (DOS33, DOS31)
WriteFlags:
    ; leftover: .res 1
    Leftover $FC, $02, $02
;; Byte 5: the track of the data sector in the data buffer.
;; Also: DCBTRK (DOS33, DOS31)
DataTrack:
    ; leftover: .res 1
    Leftover $FF, $00, $00
;; Byte 6: the sector of the data sector in the data buffer.
;; Also: DCBSEC (DOS33, DOS31)
DataSector:
    ; leftover: .res 1
    Leftover $FF, $00, $00
;; Byte 7: which catalog sector holds the file's entry, counting from 1 along the chain.
;; Also: DCBVDR (DOS33, DOS31)
EntryCatalogSector:
    ; leftover: .res 1
    Leftover $FE, $00, $00
;; Byte 8: the offset of the file's entry in that sector's <CatalogBuffer::Entries>.
;; Also: DCBVDI (DOS33, DOS31)
EntryOffset:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; Bytes 9-$0A: how many sectors one track/sector list covers, 122, from the VTOC's
;; <VtocBuffer::PairsPerList>.
;; Also: DCBDMS (DOS33, DOS31)
PairsPerList:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FE, $00, $00
;; Bytes $0B-$0C: the relative sector of the first data sector the list in memory covers.
;; Also: DCBDFS (DOS33, DOS31)
ListFirstSector:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
;; Bytes $0D-$0E: the relative sector just past the list in memory, <ListFirstSector> + <PairsPerList>.
;; Also: DCBDNF (DOS33, DOS31)
ListEndSector:
    ; leftover: .res 2
    Leftover $FF, $00, $00
    Leftover $FC, $00, $00
;; Bytes $0F-$10: the relative sector in the data buffer; $FFFF for none.
;; Also: DCBCMS (DOS33, DOS31)
DataRelativeSector:
    ; leftover: .res 2
    Leftover $FE, $00, $00
    Leftover $FC, $00, $00
;; Bytes $11-$12: the length of a sector, 256, set by OPEN.
;; Also: DCBSDL (DOS33, DOS31)
SectorLength:
    ; leftover: .res 2
    Leftover $FE, $00, $00
    Leftover $FC, $00, $00
;; Bytes $13-$14: the position's relative sector.
;; Also: DCBCRS (DOS33, DOS31)
PositionSector:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
;; Bytes $15-$16: the position's byte in that sector; only the first byte is used.
;; Also: DCBCSB (DOS33, DOS31)
PositionByte:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FD, $00, $00
;; Bytes $17-$18: the record length, from OPEN.
;; Also: DCBRCL (DOS33, DOS31)
RecordLength:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FF, $00, $00
;; Bytes $19-$1A: the position's record number.
;; Also: DCBCRR (DOS33, DOS31)
PositionRecord:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
;; Bytes $1B-$1C: the position's byte in that record.
;; Also: DCBCRB (DOS33, DOS31)
PositionRecordByte:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FF, $00, $00
;; Bytes $1D-$1E: the file's length in sectors, as in its catalog entry; <FileManager::AllocateSector> adds to it.
;; Also: DCBNSA (DOS33, DOS31)
SectorCount:
    ; leftover: .res 2
    Leftover $FC, $00, $00
    Leftover $FC, $00, $00
;; Byte $1F: the reserved track's sector count-down for <FileManager::AllocateSector>: the last sector number it tried.
;; Also: DCBALS (DOS33, DOS31)
ReservedSector:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; Byte $20: the track reserved for the file, 0 for none.
;; Also: DCBATK (DOS33, DOS31)
ReservedTrack:
    ; leftover: .res 1
    Leftover $FC, $00, $00
;; Bytes $21-$24: the reserved track's free-sector map, shifted left once for each sector <FileManager::AllocateSector>
;; tried.
;; Also: DCBABM (DOS33, DOS31)
ReservedMap:
    ; leftover: .res 4
    Leftover $FE, $00, $00
    Leftover $FE, $00, $00
    Leftover $FF, $00, $00
    Leftover $FC, $00, $00
;; Byte $25: the file's type and lock bit, as in its catalog entry.
;; Also: DCBFUC (DOS33, DOS31)
FileType:
    ; leftover: .res 1
    Leftover $FD, $00, $00
;; Byte $26: the slot times 16, for RWTS.
;; Also: DCBSLT (DOS33, DOS31)
SlotTimes16:
    ; leftover: .res 1
    Leftover $FF, $60, $60
;; Byte $27: the drive, 1 or 2.
;; Also: DCBDRV (DOS33, DOS31)
Drive:
    ; leftover: .res 1
    Leftover $FC, $01, $01
;; Byte $28: the volume number, complemented; <FileManager::AccessDisk> complements it back for RWTS, and the boot
;; loader reads it.
;; Also: DCBVOL (DOS33, DOS31)
VolumeComplement:
    ; leftover: .res 1
    Leftover $FE, $01, $01
;; Byte $29: the VTOC's track, 17.
;; Also: DCBVTN (DOS33, DOS31)
VtocTrack:
    ; leftover: .res 1
    Leftover $FD, $11, $11
;; Bytes $2A-$2C: nothing uses them.
;; Also: DCBSPR (DOS33, DOS31)
Spare:
    ; leftover: .res 3
    Leftover $FC, $00, $00
    Leftover $FD, $00, $00
    Leftover $FC, $00, $00
.endproc

.endscope

; The sizes.

;; The size of a parameter list, 22: what <Scanner::ClearParameterList> clears.
;; Also: CCBLEN (DOS33, DOS31)
FILE_PARAMETERS_SIZE = .sizeof(FileParameters)

;; The size of the file control block and of a file's work area, 45.
;; Also: FCBLEN (DOS33, DOS31), DCBLEN (DOS33, DOS31)
FILE_CONTROL_SIZE = 45

;; The size of a catalog sector, 256. Nothing uses it.
;; Also: VDLEN (DOS33, DOS31)
CATALOG_SECTOR_SIZE = .sizeof(CatalogSector)

;; The size of a catalog sector's file entries, 245: seven of 35 bytes. <FileManager::FindFile> stops there.
;; Also: VDFLEN (DOS33, DOS31)
CATALOG_ENTRIES_SIZE = CATALOG_ENTRY_COUNT * .sizeof(CatalogEntry)

; The labeled bytes match the structs.
.assert .sizeof(DosFileParameters) = .sizeof(FileParameters), "DosFileParameters is a FileParameters."
.assert DosFileParameters::Request - DosFileParameters = FileParameters::REQUEST, "Request"
.assert DosFileParameters::ImagePage - DosFileParameters = FileParameters::IMAGE_PAGE, "ImagePage"
.assert DosFileParameters::Transfer - DosFileParameters = FileParameters::TRANSFER, "Transfer"
.assert DosFileParameters::Record - DosFileParameters = FileParameters::RECORD, "Record"
.assert DosFileParameters::NewName - DosFileParameters = FileParameters::NEW_NAME, "NewName"
.assert DosFileParameters::RecordLength - DosFileParameters = FileParameters::RECORD_LENGTH, "RecordLength"
.assert DosFileParameters::ByteOffset - DosFileParameters = FileParameters::BYTE_OFFSET, "ByteOffset"
.assert DosFileParameters::Volume - DosFileParameters = FileParameters::VOLUME, "Volume"
.assert DosFileParameters::Drive - DosFileParameters = FileParameters::DRIVE, "Drive"
.assert DosFileParameters::RangeLength - DosFileParameters = FileParameters::RANGE_LENGTH, "RangeLength"
.assert DosFileParameters::Slot - DosFileParameters = FileParameters::SLOT, "Slot"
.assert DosFileParameters::FileType - DosFileParameters = FileParameters::FILE_TYPE, "FileType"
.assert DosFileParameters::Name - DosFileParameters = FileParameters::NAME, "Name"
.assert DosFileParameters::RangeAddress - DosFileParameters = FileParameters::RANGE_ADDRESS, "RangeAddress"
.assert DosFileParameters::Data - DosFileParameters = FileParameters::DATA, "Data"
.assert DosFileParameters::ReturnCode - DosFileParameters = FileParameters::RETURN_CODE, "ReturnCode"
.assert DosFileParameters::ReturnModifier - DosFileParameters = FileParameters::RETURN_MODIFIER, "ReturnModifier"
.assert DosFileParameters::WorkArea - DosFileParameters = FileParameters::WORK_AREA, "WorkArea"
.assert DosFileParameters::ListBuffer - DosFileParameters = FileParameters::LIST_BUFFER, "ListBuffer"
.assert DosFileParameters::DataBuffer - DosFileParameters = FileParameters::DATA_BUFFER, "DataBuffer"
.assert DosFileParameters::Spare - DosFileParameters = FileParameters::SPARE, "Spare"
.assert DosFileParameters::ListBuffer = DosFileParameters::WorkArea + 2, "MVFCBD reaches ListBuffer as WorkArea + 2."
.assert DosFileParameters::DataBuffer = DosFileParameters::WorkArea + 4, "MVFCBS reaches DataBuffer as WorkArea + 4."

.scope FileManager continued
.assert .sizeof(VtocBuffer) = .sizeof(Vtoc), "VtocBuffer is a Vtoc."
.assert VtocBuffer::DosType - VtocBuffer = Vtoc::DOS_TYPE, "DosType"
.assert VtocBuffer::CatalogTrack - VtocBuffer = Vtoc::CATALOG_TRACK, "CatalogTrack"
.assert VtocBuffer::CatalogSector - VtocBuffer = Vtoc::CATALOG_SECTOR, "CatalogSector"
.assert VtocBuffer::DosRelease - VtocBuffer = Vtoc::DOS_RELEASE, "DosRelease"
.assert VtocBuffer::Volume - VtocBuffer = Vtoc::VOLUME, "Volume"
.assert VtocBuffer::PairsPerList - VtocBuffer = Vtoc::PAIRS_PER_LIST, "PairsPerList"
.assert VtocBuffer::Spare - VtocBuffer = Vtoc::SPARE, "Spare"
.assert VtocBuffer::LastAllocatedTrack - VtocBuffer = Vtoc::LAST_ALLOCATED_TRACK, "LastAllocatedTrack"
.assert VtocBuffer::AllocationDirection - VtocBuffer = Vtoc::ALLOCATION_DIRECTION, "AllocationDirection"
.assert VtocBuffer::AllocationByte3 - VtocBuffer = Vtoc::ALLOCATION_BYTE_3, "AllocationByte3"
.assert VtocBuffer::AllocationByte4 - VtocBuffer = Vtoc::ALLOCATION_BYTE_4, "AllocationByte4"
.assert VtocBuffer::TrackCount - VtocBuffer = Vtoc::TRACK_COUNT, "TrackCount"
.assert VtocBuffer::SectorsPerTrack - VtocBuffer = Vtoc::SECTORS_PER_TRACK, "SectorsPerTrack"
.assert VtocBuffer::BytesPerSector - VtocBuffer = Vtoc::BYTES_PER_SECTOR, "BytesPerSector"
.assert VtocBuffer::FreeSectors - VtocBuffer = Vtoc::FREE_SECTORS, "FreeSectors"
.assert .sizeof(CatalogBuffer) = .sizeof(CatalogSector), "CatalogBuffer is a CatalogSector."
.assert CatalogBuffer::TypeCode - CatalogBuffer = CatalogSector::TYPE_CODE, "TypeCode"
.assert CatalogBuffer::NextTrack - CatalogBuffer = CatalogSector::NEXT_TRACK, "NextTrack"
.assert CatalogBuffer::NextSector - CatalogBuffer = CatalogSector::NEXT_SECTOR, "NextSector"
.assert CatalogBuffer::FileCount - CatalogBuffer = CatalogSector::FILE_COUNT, "FileCount"
.assert CatalogBuffer::Spare - CatalogBuffer = CatalogSector::SPARE, "Spare"
.assert CatalogBuffer::Entries - CatalogBuffer = CatalogSector::ENTRIES, "Entries"
.assert CatalogBuffer::End - CatalogBuffer = CATALOG_SECTOR_SIZE, "End"
.assert .sizeof(FileControlBlock) = FILE_CONTROL_SIZE, "The file control block is FILE_CONTROL_SIZE bytes."
.endscope
.assert CATALOG_SECTOR_SIZE = SECTOR_SIZE && .sizeof(Vtoc) = SECTOR_SIZE, "A catalog sector and the VTOC are sectors."
.assert CATALOG_ENTRIES_SIZE = 245, "Seven entries of 35 bytes."
