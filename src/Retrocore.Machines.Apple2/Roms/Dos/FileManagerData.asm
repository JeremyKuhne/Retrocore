;; DOS 3.3 AND 3.2 FILE MANAGER: WORK CELLS, BUFFERS AND CONTROL BLOCKS (FVCBUFS)
;;
;; The file manager's data: a few variables and tables, a buffer for the VTOC (track 17 sector 0) and one for a
;; catalog sector, each with its fields named as they are on the disk; the parameter list, CCB, through which
;; the file manager is called; and the file control block, FCB, the 45 bytes that describe an open file while
;; a request runs. Each open file keeps its own copy of the FCB in its DOS buffer (the file manager workarea):
;; CLCFCB copies it in when a request starts and RTNFCB copies it back when it ends. A track/sector list
;; sector, held in a buffer of its own, is laid out by FILDIR (in BootLoader.asm).
;;
;; Where DOS runs, this is $B397-$B5FD, just below the boot loader's page at $B600.
;;
;; Where Apple's source only reserves space (.res) or skips to the end of a buffer (.org), each master holds
;; whatever was in memory when its DOS image was saved; the master's VTOC and catalog buffers, parameter list
;; and FCB still held data then (in the 1980 and DOS 3.2 masters, mostly the VTOC of a freshly formatted disk
;; and zeros). Those bytes are kept here as data, after a "leftover" comment naming Apple's directive, so each
;; image is exact. They mean nothing: DOS reads a sector into a buffer, or fills in the
;; parameter list or FCB, before it uses them.
;; docs/Dos.md describes the VTOC, the catalog and the file manager's calls.

;; The track of the catalog sector in the catalog buffer, where WRVDIR writes it back.
CVDTRK:
    LEFTOVER $00, $11, $00
;; The sector of the catalog sector in the catalog buffer, where WRVDIR writes it back.
CVDSEC:
    LEFTOVER $00, $0D, $00
;; Two bytes nothing in DOS refers to.
CURCCB:
    .byte 0, 0
;; The stack pointer when the file manager was entered (DOSENT); RETURN restores it to leave from any depth.
ENTSTK:
    LEFTOVER $00, $F5, $F5
;; Scratch: the offset of the catalog entry being looked at (FNDFIL, OPEN, DELETE, LOCK, RENAME, CATALOG).
TEMP1:
    LEFTOVER $00, $23, $00
;; Scratch: FNDFIL's pass (1, then 0), GNWSEC's saved index, the lines left on CATALOG's screen.
TEMP2:
    LEFTOVER $00, $01, $00
;; Scratch: GETSEC's search state (1 once it has turned round at track 0); the lock bit for LOCK and UNLOCK.
TEMP3:
    .byte 0
;; A byte nothing in DOS refers to.
ENTSLT:
    .byte 0
;; The free-sector map of an empty 16-sector track, last byte first: INIT (FFMT) copies it into the VTOC from
;; the end, giving $FF $FF $00 $00 for every track but 0 to 2 (DOS) and 17 (the VTOC and catalog). DOS 3.2's
;; is that of a 13-sector track, $FF $F8 $00 $00.
ALC10S:
.if DOS32
    .byte 0, 0, $F8, $FF
.else
    .byte 0, 0, $FF, $FF
.endif
;; The powers of ten CATALOG's PRNUM divides by, used from 100 down, to print a three-digit number.
CVTAB:
    .byte 1, 10, 100
;; The letter CATALOG prints for each file type, indexed by the position of the type's highest set bit:
;; T (text, $00), I (Integer BASIC, $01), A (Applesoft, $02), B (binary, $04), S ($08), R (relocatable, $10),
;; A ($20) and B ($40).
FTTAB:
    .hiascii "TIAB"
    .hiascii "SRAB"
;; "DISK VOLUME " backwards: CATALOG prints it from the last byte to the first, before the volume number.
VOLMES:
    .hiascii " EMULOV KSID"
VML = *-VOLMES-1                    ;; the index of VOLMES's last byte, where printing starts
;; The VTOC buffer: one 256-byte sector, the volume table of contents, read from and written to track 17
;; sector 0 (RDVTOC, WRVTOC).
;;
;; The VTOC says where the catalog starts and which sectors are free. The values assembled here are those of an
;; empty 35-track, 16-sector disk (13-sector in DOS 3.2). INIT (FFMT) sets the volume number, the allocation
;; fields and the bit map, zeroing everything from VSECAL on, then writes the buffer as the new disk's VTOC; the
;; other fields go out as the buffer holds them at the time. Byte 0, VDOST, is 4 (2 in DOS 3.2); nothing in DOS
;; reads it.
VTOC:
VDOST:
.if DOS32
    .byte 2
.else
    .byte 4
.endif
;; VTOC byte 1: the track of the first catalog sector.
VDIRTK:
    .byte 17
;; VTOC byte 2: the sector of the first catalog sector: 15, or 12 in DOS 3.2.
VDIRSC:
.if DOS32
    .byte 12
.else
    .byte 15
.endif
;; VTOC byte 3: the DOS release that initialized the disk, 4 here and 2 in DOS 3.2. Nothing in DOS reads it.
;; Bytes 4 and 5 are unused.
VDOSRN:
.if DOS32
    .byte 2
.else
    .byte 4
.endif
    .byte 0
    .byte 0
;; VTOC byte 6: the disk's volume number, 1 to 254. Bytes 7 to $26 are unused.
VVOLNO:
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
;; VTOC byte $27: how many track/sector pairs fit in one track/sector list sector, 122. OPEN copies it to
;; DCBDMS.
VTDMS:
    .byte 122
;; VTOC bytes $28 to $2F: unused.
VSPARE:
    ; leftover: .res 8
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FC, $FC, $FD, $FC, $FC, $FE, $FC
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00, $00
.endif
;; VTOC byte $30: the track GETSEC last reserved, where its search for a free track starts.
VALCA1:
    .byte 17
;; VTOC byte $31: the direction of GETSEC's search, 1 (up) or $FF (down, -1).
VALCA2:
    .byte 1
;; VTOC byte $32: unused.
VALCA3:
    .byte 0
;; VTOC byte $33: unused.
VALCA4:
    .byte 0
;; VTOC byte $34: the number of tracks on the disk, 35.
VNOTRK:
    .byte 35
;; VTOC byte $35: the number of sectors per track, 16 (13 in DOS 3.2).
VNOSEC:
.if DOS32
    .byte 13
.else
    .byte 16
.endif
;; VTOC bytes $36-$37: the bytes per sector, 256. Nothing in DOS reads it; DOPEN sets DCBSDL to 256 itself.
VSECLN:
    .word 256
;; VTOC bytes $38-$FF: the free-sector bit map, 4 bytes per track, track 0 first (room for 50 tracks).
;;
;; A set bit is a free sector. The first byte holds sectors 15 to 8 and the second 7 to 0, the highest sector
;; in bit 7; the last two bytes are unused on a 16-sector disk. GETSEC, FRETRK and FRESEC read and change it.
;; On DOS 3.2's 13-sector disks the first byte holds sectors 12 to 5 and the second 4 to 0, and the second
;; byte's low three bits are unused too.
VSECAL:
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
    .assert * = VTOC+256
;; The catalog buffer: one 256-byte catalog sector (RDVDIR, WRVDIR).
;;
;; The catalog is a chain of sectors, normally track 17 sectors 15 down to 1 (12 down to 1 in DOS 3.2), each
;; holding seven file entries.
;; Byte 0, VDTCDE, is 2 here; nothing in DOS reads it, and INIT zeroes the buffer before writing the catalog.
VOLDIR:
VDTCDE:
    LEFTOVER $02, $00, $00
;; Catalog byte 1: the track of the next catalog sector, 0 in the last one.
VDLTRK:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
;; Catalog byte 2: the sector of the next catalog sector.
VDLSEC:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; Catalog byte 3: unused; nothing in DOS reads it.
VDNF:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; Catalog bytes 4 to $0A: unused.
VDSPAR:
    ; leftover: .res 7
.if DOS32 = 0 && YEAR = 1983
    .byte $FC, $FD, $FC, $FD, $FD, $FC, $FC
.else
    ; leftover: what the 1980 master holds here, as the DOS 3.2 master does
    .byte $00, $00, $00, $00, $00, $00, $00
.endif
;; Catalog bytes $0B-$FF: seven file entries of 35 bytes each.
;;
;; Each entry:
;; - +0: the track of the file's first track/sector list; 0 if the entry was never used, $FF if the file was
;;   deleted (DELETE then keeps the old track in +32, the last byte of the name).
;; - +1: the sector of the first track/sector list.
;; - +2: the file type ($00 text, $01 Integer BASIC, $02 Applesoft, $04 binary, $08 S, $10 relocatable,
;;   $20 A, $40 B), plus $80 when the file is locked.
;; - +3 to +32: the name, 30 characters with bit 7 set, padded with spaces.
;; - +33 and +34: the file's length in sectors, counting its track/sector lists, low byte first.
VDFILE:
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
    .assert * = VOLDIR+256
;; The end of the catalog buffer.
VDEND:
VDLEN = *-VOLDIR                    ;; the catalog buffer's size, 256
VDFLEN = *-VDFILE                   ;; the size of the file entries, 245: seven of 35 bytes
;; The file manager's parameter list, CCB: the request and its parameters, and the return code (22 bytes).
;;
;; The command interpreter fills it in and calls the file manager (DOSENT); several fields mean different
;; things for different requests, so several names share a byte. Byte 0, CCBREQ, is the request, one of the
;; CRQ codes below.
CCB:
CCBREQ:
    ; leftover: .res 1
    LEFTOVER $FD, $0B, $0B
CRQNUL = 0                          ;; does nothing
CRQOPN = 1                          ;; OPEN: find the file, creating it if the command allows
CRQCLS = 2                          ;; CLOSE: write what is pending and update the catalog
CRQRD = 3                           ;; READ, as CCBRQM says
CRQWR = 4                           ;; WRITE, as CCBRQM says
CRQDEL = 5                          ;; DELETE
CRQDIR = 6                          ;; CATALOG
CRQLCK = 7                          ;; LOCK
CRQUNL = 8                          ;; UNLOCK
CRQRNM = 9                          ;; RENAME
CRQPOS = 10                         ;; POSITION: set the position from CCBRRN and CCBBYT
CRQFMT = 11                         ;; INIT: format the disk and write DOS, the VTOC and the catalog
CRQVAR = 12                         ;; VERIFY: read every sector of the file
CRQMAX = 13                         ;; the first code out of range (ERROR2)
;; Byte 1: for READ and WRITE, the kind of transfer, one of the CRM codes below (CCBRQM); for INIT, the page
;; where the DOS image to write starts (CCBBSA).
CCBBSA:
CCBRQM:
    ; leftover: .res 1
    LEFTOVER $FD, $1B, $1B
CRMNUL = 0                          ;; does nothing
CRMNBT = 1                          ;; the next byte
CRMNBL = 2                          ;; the next block of bytes
CRMSBT = 3                          ;; position (as POSITION), then one byte
CRMSBL = 4                          ;; position, then a block
CRMMAX = 5                          ;; the first code out of range (ERROR3)
;; Bytes 2-3: for POSITION and positioned transfers, the record number (CCBRRN), set on return to the record
;; of the last byte transferred; for RENAME, the address of the new name (CCBFN2); for OPEN, the record
;; length, 0 meaning 1 (CCBRLN).
CCBRRN:
CCBFN2:
CCBRLN:
    ; leftover: .res 2
    LEFTOVER $FD, $01, $01
    LEFTOVER $FC, $00, $00
;; Bytes 4-5: for POSITION and positioned transfers, the byte offset in the record (CCBBYT), set on return
;; like CCBRRN. Byte 4 alone: for OPEN and INIT, the volume number, 0 for any (CCBVOL); every disk access sets
;; it to the volume found on the disk.
CCBBYT:
CCBVOL:
    ; leftover: .res 1
    LEFTOVER $FC, $FE, $FE
;; Byte 5: for OPEN and the other requests that name a disk, the drive, 1 or 2.
CCBDRV:
    ; leftover: .res 1
    LEFTOVER $FD, $01, $01
;; Bytes 6-7: for block transfers, the number of bytes (CCBBLN). Byte 6 alone: the slot, 1 to 7 (CCBSLT).
CCBBLN:
CCBSLT:
    ; leftover: .res 1
    LEFTOVER $FF, $06, $06
;; Byte 7: for OPEN, the type for a new file; on return, the type of the file opened.
CCBFUC:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
;; Bytes 8-9: the address of the file's name (CCBFN1); for block transfers, the address of the caller's
;; buffer, advanced as bytes go (CCBBBA); for single-byte transfers, the byte, in byte 8 (CCBDAT).
CCBFN1:
CCBBBA:
CCBDAT:
    ; leftover: .res 2
    LEFTOVER $FC, $75, $75
    LEFTOVER $FD, $2A, $2A
;; Byte $0A: the return code, one of the CRE codes below; 0 for success. Carry is also set on an error.
CCBSTA:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
CREFUN = 1                          ;; LANGUAGE NOT AVAILABLE in DOS's messages; OPEN gives it when ISTATE = $C0
CRERR = 2                           ;; the request code is out of range
CREMRE = 3                          ;; the READ or WRITE subcode is out of range
CREPRO = 4                          ;; the disk is write protected
CREEOF = 5                          ;; a read ran past the end of the file
CREFNF = 6                          ;; file not found; with carry clear, OPEN created it
CREVMM = 7                          ;; volume mismatch
CREIOE = 8                          ;; any other disk error
CRENSA = 9                          ;; no sectors available: the disk or the catalog is full
CREFLK = 10                         ;; the file is locked
;; Byte $0B: nothing in DOS refers to it.
CCBSM:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
;; Bytes $0C-$0D: the address of the open file's workarea, its 45-byte copy of the FCB.
CCBFCB:
    ; leftover: .res 2
    LEFTOVER $FF, $00, $00
    LEFTOVER $FC, $18, $18
;; Bytes $0E-$0F: the address of the file's track/sector list buffer, laid out by FILDIR.
CCBDBP:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $17, $17
;; Bytes $10-$11: the address of the file's data sector buffer.
CCBSBP:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $16, $16
;; Bytes $12-$15: unused.
CCBSPR:
    ; leftover: .res 4
    LEFTOVER $FF, $00, $00
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
CCBLEN = *-CCB                      ;; the parameter list's size, 22
; The names MVFCBP, MVFCBD and MVFCBS use for the three buffer addresses, reached as CFCBAD + 0, 2 and 4: the
; three must stay in this order.
CFCBAD = CCBFCB                     ;; the workarea's address
CFCBDR = CCBDBP                     ;; the track/sector list buffer's address
CFCBSB = CCBSBP                     ;; the data sector buffer's address
;; The file control block, FCB: the 45 bytes that describe the open file while a request runs.
;;
;; CLCFCB copies the file's workarea here when a request starts, and RTNFCB copies it back when it ends, so a
;; file's state lives in its DOS buffer between requests. OPEN (DCBSUP) clears it and fills it in. The FCB is
;; all DCB, "data control block"; the names come from Apple's source. Byte 0, DCBFDT, is the track of the
;; file's first track/sector list.
FCB:
FCBDCB:
DCBFDT:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; FCB byte 1: the sector of the file's first track/sector list.
DCBFDS:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; FCB byte 2: the track of the track/sector list in the list buffer.
DCBCDT:
    ; leftover: .res 1
    LEFTOVER $FF, $00, $00
;; FCB byte 3: the sector of the track/sector list in the list buffer.
DCBCDS:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; FCB byte 4: what needs writing. $80: the track/sector list buffer was changed; $40: the data sector buffer
;; was changed; $02: something was written to the disk since OPEN, so CLOSE updates the catalog's sector count.
DCBWRF:
    ; leftover: .res 1
    LEFTOVER $FC, $02, $02
;; FCB byte 5: the track of the data sector in the data buffer.
DCBTRK:
    ; leftover: .res 1
    LEFTOVER $FF, $00, $00
;; FCB byte 6: the sector of the data sector in the data buffer.
DCBSEC:
    ; leftover: .res 1
    LEFTOVER $FF, $00, $00
;; FCB byte 7: which catalog sector holds the file's entry, counting from 1 along the chain.
DCBVDR:
    ; leftover: .res 1
    LEFTOVER $FE, $00, $00
;; FCB byte 8: the offset of the file's entry in that sector's VDFILE.
DCBVDI:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; FCB bytes 9-$0A: how many sectors one track/sector list covers, 122 (from VTDMS).
DCBDMS:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FE, $00, $00
;; FCB bytes $0B-$0C: the relative sector of the first data sector the list in memory covers.
DCBDFS:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $0D-$0E: the relative sector just past the list in memory, DCBDFS + DCBDMS.
DCBDNF:
    ; leftover: .res 2
    LEFTOVER $FF, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $0F-$10: the relative sector in the data buffer; $FFFF for none.
DCBCMS:
    ; leftover: .res 2
    LEFTOVER $FE, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $11-$12: the length of a sector, 256, given to RWTS.
DCBSDL:
    ; leftover: .res 2
    LEFTOVER $FE, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $13-$14: the position's relative sector, counting from 0 at the start of the file.
DCBCRS:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $15-$16: the position's byte in that sector; only the first byte is used.
DCBCSB:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FD, $00, $00
;; FCB bytes $17-$18: the record length, from OPEN.
DCBRCL:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FF, $00, $00
;; FCB bytes $19-$1A: the position's record number.
DCBCRR:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB bytes $1B-$1C: the position's byte in that record.
DCBCRB:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FF, $00, $00
;; FCB bytes $1D-$1E: the file's length in sectors, as in its catalog entry; GETSEC adds to it.
DCBNSA:
    ; leftover: .res 2
    LEFTOVER $FC, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB byte $1F: the reserved track's sector count-down for GETSEC: the last sector number it tried.
DCBALS:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
;; FCB byte $20: the track reserved for the file, 0 for none.
DCBATK:
    ; leftover: .res 1
    LEFTOVER $FC, $00, $00
;; FCB bytes $21-$24: the reserved track's free-sector map, shifted left once for each sector GETSEC tried.
DCBABM:
    ; leftover: .res 4
    LEFTOVER $FE, $00, $00
    LEFTOVER $FE, $00, $00
    LEFTOVER $FF, $00, $00
    LEFTOVER $FC, $00, $00
;; FCB byte $25: the file's type and lock bit, as in its catalog entry.
DCBFUC:
    ; leftover: .res 1
    LEFTOVER $FD, $00, $00
;; FCB byte $26: the slot times 16, for RWTS.
DCBSLT:
    ; leftover: .res 1
    LEFTOVER $FF, $60, $60
;; FCB byte $27: the drive, 1 or 2.
DCBDRV:
    ; leftover: .res 1
    LEFTOVER $FC, $01, $01
;; FCB byte $28: the volume number, complemented (DCBIO complements it back for RWTS).
DCBVOL:
    ; leftover: .res 1
    LEFTOVER $FE, $01, $01
;; FCB byte $29: the VTOC's track, 17.
DCBVTN:
    ; leftover: .res 1
    LEFTOVER $FD, $11, $11
;; FCB bytes $2A-$2C: unused.
DCBSPR:
    ; leftover: .res 3
    LEFTOVER $FC, $00, $00
    LEFTOVER $FD, $00, $00
    LEFTOVER $FC, $00, $00
DCBLEN = *-FCBDCB                   ;; the DCB's size, 45
FCBLEN = *-FCB                      ;; the FCB's size, 45: the DCB is all of it
