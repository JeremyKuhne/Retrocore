;; KAYPRO II MONITOR ROM 81-149C ($0000-$07FF)
;;
;; The Kaypro II's only ROM: 2K at $0000, banked in with the 4K of video RAM at $3000 while the system port's bit 7
;; is set. It sets up the SIO, the PIOs and the screen, then boots CP/M from drive A: it reads the disk's first
;; 128-byte sector to $FA00, which says where the system loads, where it starts and how many sectors it has, reads
;; those sectors from track 0 and track 1, and jumps to it.
;;
;; CP/M's BIOS calls the ROM for everything it does with the hardware, through the jump table at $0000. The table's
;; disk entries are those of the CP/M 2.2 BIOS (SELDSK, SETTRK, SETSEC, SETDMA, READ, WRITE, SECTRAN), and READ and
;; WRITE block and deblock 128-byte CP/M records into the double-density disk's 512-byte sectors with the
;; algorithm of Appendix G of Digital Research's CP/M 2.2 Alteration Guide, whose names the variables and routines
;; here take. A disk is tried in double density when its drive is first selected, and in single density
;; (eighteen 128-byte sectors a track, as an 8-inch CP/M disk's) when that fails.
;;
;; The ROM copies its disk parameter headers and blocks and the routines that move bytes to and from the disk into
;; the top of RAM at $FE71-$FF53, where they work with the ROM banked out: BDOS reads the parameters there, and the
;; transfer routines can reach the RAM under the ROM.
;;
;; The floppy disk controller is an FD1793. Its interrupt and data requests reach the Z80's NMI only while the Z80 is
;; halted, so the ROM moves each byte with HALT then INI or OUTI, and waits for a command to end with HALT. The NMI
;; vector, $0066, is a RET in the ROM, and the transfer routines put a RET there in RAM while the ROM is out.
;;
;; The screen is 24 lines of 80 characters, each line 128 bytes apart in video RAM from $3000; a character with bit 7
;; set blinks, which is how the ROM shows its cursor. The keyboard is a serial device on the SIO's channel B at
;; 300 baud.
;;
;; The labels are our own, named after what each routine does, and after the CP/M BIOS entries and Digital
;; Research's deblocking names where the code is theirs.
;;
;; Maintained by hand. KayproRomSourceTests check that it assembles byte-identically to the ROM.

.cpu Z80

; Ports.
SERIAL_BAUD_PORT = $00              ;; the serial port's baud rate generator: a rate from 0 (50) to 15 (19200)
SERIAL_DATA_PORT = $04              ;; the SIO's channel A, the RS-232 serial port
KEYBOARD_DATA_PORT = $05            ;; the SIO's channel B, the keyboard
SERIAL_CONTROL_PORT = $06
KEYBOARD_CONTROL_PORT = $07
PRINTER_DATA_PORT = $08             ;; the general-purpose PIO's port A, the Centronics printer's data
PRINTER_CONTROL_PORT = $09
GENERAL_B_DATA_PORT = $0A           ;; the general-purpose PIO's port B, not connected
GENERAL_B_CONTROL_PORT = $0B
KEYBOARD_BAUD_PORT = $0C            ;; the keyboard's baud rate generator
FDC_COMMAND_PORT = $10              ;; the FD1793's status, and its command when written
FDC_TRACK_PORT = $11
FDC_SECTOR_PORT = $12
FDC_DATA_PORT = $13
UNUSED_PORT = $14                   ;; nothing answers it on the Kaypro II
SYSTEM_PORT = $1C                   ;; the system PIO's port A: the bits below
SYSTEM_CONTROL_PORT = $1D

; System port bits.
SYSTEM_DRIVE_A = 0                  ;; selects drive A
SYSTEM_DRIVE_B = 1                  ;; selects drive B
SYSTEM_PRINTER_READY = 3            ;; input: clear while the printer is busy
SYSTEM_PRINTER_STROBE = 4
SYSTEM_SINGLE_DENSITY = 5           ;; set for single density (FM), clear for double (MFM)
SYSTEM_MOTORS_OFF = 6
SYSTEM_ROM = 7                      ;; set to bank the ROM in at $0000 and video RAM at $3000
SYSTEM_DRIVES = $03                 ;; both drive bits
SINGLE_DENSITY = 1 << SYSTEM_SINGLE_DENSITY

; SIO read register 0.
SIO_RECEIVED = 0                    ;; a character is waiting
SIO_TRANSMIT_EMPTY = 2              ;; the transmitter can take one

; FD1793 commands and status.
FDC_RESTORE = $00                   ;; to track 0, at the fastest stepping rate
FDC_SEEK = $10                      ;; to the track in the data register
FDC_READ = $88                      ;; one sector, with its side checked
FDC_WRITE = $AC                     ;; one sector, after the head settles, with no write precompensation
FDC_READ_ADDRESS = $C4              ;; the next ID field, after the head settles; its track goes in the sector register
FDC_FORCE_INTERRUPT = $D0           ;; ends a command with no interrupt
FDC_BUSY = 0                        ;; status bit
FDC_NOT_FOUND = 4                   ;; status bit: no ID field matched
FDC_READ_ERRORS = $9C               ;; not ready, not found, CRC error, lost data
FDC_WRITE_ERRORS = $FC              ;; and write protect and write fault

; Console characters.
BELL = $07
BACKSPACE = $08                     ;; moves the cursor left
LINE_FEED = $0A
CURSOR_UP = $0B
CURSOR_RIGHT = $0C
RETURN = $0D
CLEAR_TO_END_OF_SCREEN = $17
CLEAR_TO_END_OF_LINE = $18
CLEAR_SCREEN = $1A                  ;; and homes the cursor
ESCAPE = $1B
HOME = $1E
SPACE = $20
CURSOR = $DF                        ;; a blinking underline, shown where the cursor is on a space
KEYBOARD_BELL = $04                 ;; what the keyboard takes to sound its bell

; The screen.
VIDEO = $3000                       ;; 24 lines of 80 characters, each line LINE_BYTES apart
LINES = 24
COLUMNS = 80
LINE_BYTES = $80
VIDEO_SIZE = LINES * LINE_BYTES
LAST_LINE = VIDEO + (LINES - 1) * LINE_BYTES
VIDEO_END = VIDEO + VIDEO_SIZE      ;; just past the last line
BLINK = 7                           ;; a character's blinking bit
NORMAL_CHARACTERS = $7F             ;; the character mask: ASCII
GREEK_CHARACTERS = $1F              ;; lowercase letters as the Greek letters at $00-$1F

; CP/M.
SECTOR_SIZE = 128                   ;; a CP/M record
HOST_SIZE = 512                     ;; a double-density sector
HOST_SECTORS = 10                   ;; double-density sectors on a track
CPM_SECTORS = HOST_SECTORS * HOST_SIZE / SECTOR_SIZE ;; CP/M records a double-density track holds
SECTOR_MASK = HOST_SIZE / SECTOR_SIZE - 1
SECTOR_SHIFT = 2                    ;; log2 of CP/M records in a host sector
UNALLOCATED_RECORDS = 8             ;; the records in an allocation block, which a new block's writes skip reading
WRITE_ALLOCATED = 0                 ;; WRITE's type in C: to an allocated block
WRITE_DIRECTORY = 1                 ;; to the directory, written at once
WRITE_UNALLOCATED = 2               ;; to the first record of an unallocated block
BOOT_RECORD = $FA00                 ;; where the boot record loads: the BOOT_* words below
BOOT_LOAD = BOOT_RECORD + 2         ;; where the system loads
BOOT_START = BOOT_RECORD + 4        ;; where it starts
BOOT_RECORDS = BOOT_RECORD + 6      ;; how many 128-byte records it has
TRACK_1_FIRST_RECORD = 16           ;; the record on track 1 the system goes on from
NMI_VECTOR = $0066
DELAY_COUNT = 1670                  ;; about 16 ms of DELAY's inner loop at 2.5 MHz
MOTOR_START_DELAY = 50              ;; DELAY's count for the motors to come up to speed
RESET_DELAY = 10
WRITE_TRIES = 3                     ;; writes, each read back, before an error
SEEK_TRIES = $040F                  ;; four seeks, with fifteen tries at each

; Deblocking variables, Appendix G's names, under the host buffer.
.dum $FC00
SEKDSK: .res 1                      ;; the drive to seek
SEKTRK: .res 2                      ;; the track to seek
SEKSEC: .res 1                      ;; the CP/M record to seek
HSTDSK: .res 1                      ;; the drive of the sector in the host buffer
HSTTRK: .res 2                      ;; its track
HSTSEC: .res 1                      ;; its sector
SEKHST: .res 1                      ;; SEKSEC's host sector
HSTACT: .res 1                      ;; nonzero when the host buffer holds a sector
HSTWRT: .res 1                      ;; nonzero when the host buffer needs writing
UNACNT: .res 1                      ;; records left in an unallocated block
UNADSK: .res 1                      ;; the unallocated block's drive
UNATRK: .res 2                      ;; its track
UNASEC: .res 1                      ;; its next record
ERFLAG: .res 1                      ;; nonzero after a disk error
RSFLAG: .res 1                      ;; nonzero when the host sector must be read first
READOP: .res 1                      ;; 1 for READ, 0 for WRITE
WRTYPE: .res 1                      ;; WRITE's type
DMAADR: .res 2                      ;; where CP/M's record goes
HSTBUF: .res HOST_SIZE              ;; the host buffer
FDC_DRIVE: .res 1                   ;; the drive the controller has selected, $FF for none
DENSITY: .res 1                     ;; its density: SINGLE_DENSITY, or 0 for double
TRACK_A: .res 1                     ;; the track register for drive A while B is selected, $FF before its first select
TRACK_B: .res 1                     ;; and for drive B
.dend
.assert HSTBUF + HOST_SIZE = FDC_DRIVE, "The drive state follows the host buffer."

; CP/M's scratch areas, used by BDOS.
CSV_A = $FE1A                       ;; drive A's directory checksums
ALV_A = $FE2A                       ;; drive A's allocation bits
CSV_B = $FE43
ALV_B = $FE53
DIRBUF = $FF73                      ;; BDOS's directory buffer

; Console variables.
.dum $FE6C
ESCAPE_STATE: .res 1                ;; 0, or ESCAPE_STATE_* while an escape sequence is under way
CURSOR_LINE: .res 1                 ;; the line of an ESC = sequence, plus 32
CURSOR_ADDRESS: .res 2              ;; the cursor's place in video RAM
CHARACTER_MASK: .res 1              ;; NORMAL_CHARACTERS, or GREEK_CHARACTERS after ESC G
.dend
ESCAPE_STATE_ESCAPE = 1             ;; ESCAPE came last
ESCAPE_STATE_LINE = 2               ;; ESC = came last: the line follows
ESCAPE_STATE_COLUMN = 3             ;; and then the column

; Where the ROM copies its tables and transfer routines.
DPH_A = $FE71                       ;; drive A's disk parameter header, and its density at DPH_DENSITY
DPH_B = DPH_A + DPH_SIZE
DPH_SIZE = 17
DPH_DPB = 10                        ;; offset of the disk parameter block's address
DPH_DENSITY = 16                    ;; offset of the drive's density, past CP/M's 16 bytes
DPB_SINGLE = DPH_B + DPH_SIZE       ;; the single-density disk parameter block
DPB_DOUBLE = DPB_SINGLE + DPB_SIZE  ;; the double-density one
DPB_SIZE = 15
XLT_SINGLE = DPB_DOUBLE + DPB_SIZE  ;; the single-density sector translation
RELOCATED = $FECD                   ;; the transfer routines

.org $0000

;; The ROM's entry points, which CP/M's BIOS calls.
COLD_ENTRY:
    JP COLD                         ; $00
DISK_RESET_ENTRY:
    JP DISK_RESET                   ; $03
VIDEO_RESET_ENTRY:
    JP VIDEO_RESET                  ; $06
DEVICE_RESET_ENTRY:
    JP DEVICE_RESET                 ; $09
HOME_ENTRY:
    JP HOME_DISK                    ; $0C
SELDSK_ENTRY:
    JP SELDSK                       ; $0F
SETTRK_ENTRY:
    JP SETTRK                       ; $12
SETSEC_ENTRY:
    JP SETSEC                       ; $15
SETDMA_ENTRY:
    JP SETDMA                       ; $18
READ_ENTRY:
    JP READ                         ; $1B
WRITE_ENTRY:
    JP WRITE                        ; $1E
SECTRAN_ENTRY:
    JP SECTRAN                      ; $21
MOTOR_ON_ENTRY:
    JP MOTOR_ON                     ; $24
MOTOR_OFF_ENTRY:
    JP MOTOR_OFF                    ; $27
KEYBOARD_STATUS_ENTRY:
    JP KEYBOARD_STATUS              ; $2A
KEYBOARD_IN_ENTRY:
    JP KEYBOARD_IN                  ; $2D
KEYBOARD_OUT_ENTRY:
    JP KEYBOARD_OUT                 ; $30
SERIAL_STATUS_ENTRY:
    JP SERIAL_STATUS                ; $33
SERIAL_IN_ENTRY:
    JP SERIAL_IN                    ; $36
SERIAL_OUT_ENTRY:
    JP SERIAL_OUT                   ; $39
PRINTER_STATUS_ENTRY:
    JP PRINTER_STATUS               ; $3C
PRINTER_OUT_ENTRY:
    JP PRINTER_OUT                  ; $3F
SERIAL_OUT_STATUS_ENTRY:
    JP SERIAL_OUT_STATUS            ; $42
VIDEO_OUT_ENTRY:
    JP VIDEO_OUT                    ; $45
DELAY_ENTRY:
    JP DELAY                        ; $48

;; Power-up and reset: sets up the devices, the screen and the disks, then boots CP/M from drive A.
COLD:
    DI
    LD SP,$FFFF
    LD B,RESET_DELAY
    CALL DELAY
    CALL DEVICE_RESET
    CALL VIDEO_RESET
    CALL DISK_RESET
    JR SIGN_ON

; Unused bytes before the NMI vector.
    .byte $3D
    .res 6,0

;; The NMI the floppy disk controller raises while the Z80 is halted: it only ends the HALT.
NMI:
    RET
.assert NMI = NMI_VECTOR, "The NMI vector is at $0066."

;; Shows the sign-on and boots the system from drive A's first records.
SIGN_ON:
    CALL PRINT
    .byte ESCAPE, "=", 10 + 32, 31 + 32, "*    KAYPRO II    *"
    .byte ESCAPE, "=", 13 + 32, 20 + 32, " Please place your diskette into Drive A", BACKSPACE, 0
    LD C,0
    CALL SELDSK
    LD BC,0
    CALL SETTRK
    LD C,0
    CALL SETSEC
    LD BC,BOOT_RECORD
    CALL SETDMA
    CALL READ
    DI
    OR A
    JR NZ,BOOT_FAILED
    LD BC,[BOOT_LOAD]
    LD [DMAADR],BC
    LD BC,[BOOT_START]
    PUSH BC                         ; where the last RET goes
    LD BC,[BOOT_RECORDS]
    LD B,C
    LD C,1

;; Reads the system's records from SETTRK's track, record C on, B of them, and starts it.
SIGN_ON_READ:
    PUSH BC
    CALL SETSEC
    CALL READ
    DI
    POP BC
    OR A
    JR NZ,BOOT_FAILED
    LD HL,[DMAADR]
    LD DE,SECTOR_SIZE
    ADD HL,DE
    LD [DMAADR],HL
    DEC B
    RET Z                           ; to the system
    INC C
    LD A,CPM_SECTORS
    CP C
    JR NZ,SIGN_ON_READ
    LD C,TRACK_1_FIRST_RECORD
    PUSH BC
    LD BC,1
    CALL SETTRK
    POP BC
    JR SIGN_ON_READ

;; Reports a disk that cannot be read, turns the motors off and stops.
BOOT_FAILED:
    CALL PRINT
    .byte LINE_FEED, RETURN, LINE_FEED, RETURN, BELL, "I cannot read your diskette.", 0
    CALL MOTOR_OFF
BOOT_FAILED_STOP:
    JR BOOT_FAILED_STOP

;; The disk parameter headers, blocks and single-density sector translation that DISK_RESET copies to DPH_A on.
DISK_TABLES:
    ; Drive A: no translation until a disk is found to be single density, BDOS's scratch, and its density.
    .word 0, 0, 0, 0, DIRBUF, DPB_DOUBLE, CSV_A, ALV_A
    .byte 0
    ; Drive B.
    .word 0, 0, 0, 0, DIRBUF, DPB_DOUBLE, CSV_B, ALV_B
    .byte 0
    ; Single density: 18 records a track, 1K blocks, 83 of them, 32 directory entries, 3 system tracks.
    .word 18
    .byte 3, 7, 0
    .word 82, 31
    .byte $80, $00
    .word 8, 3
    ; Double density: 40 records a track, 1K blocks, 195 of them, 64 directory entries, 1 system track.
    .word CPM_SECTORS
    .byte 3, 7, 0
    .word 194, 63
    .byte $F0, $00
    .word 16, 1
    ; The single-density records in the order they are read, six apart.
    .byte 1, 6, 11, 16, 3, 8, 13, 18, 5, 10, 15, 2, 7, 12, 17, 4, 9, 14
DISK_TABLES_END:
.assert DISK_TABLES_END - DISK_TABLES = 2 * DPH_SIZE + 2 * DPB_SIZE + 18, "The tables are as DPH_A on lays them out."

;; Copies the transfer routines and disk tables to the top of RAM and forgets every drive's state.
DISK_RESET:
    LD HL,TRANSFER
    LD DE,RELOCATED
    LD BC,TRANSFER_END - TRANSFER
    LDIR
    LD HL,DISK_TABLES
    LD DE,DPH_A
    LD BC,DISK_TABLES_END - DISK_TABLES
    LDIR
    XOR A
    LD [HSTACT],A
    LD [UNACNT],A
    LD A,0
    LD [DENSITY],A
    LD A,$FF
    LD [FDC_DRIVE],A
    LD [TRACK_A],A
    LD [TRACK_B],A
    RET

;; CP/M's SELDSK: selects a drive.
;; In: C = the drive, 0 for A or 1 for B
;; Out: HL = its disk parameter header, or 0 for no such drive
SELDSK:
    LD A,C
    LD [SEKDSK],A
    JP SELECT_DRIVE

;; CP/M's SETSEC: sets the record to read or write.
;; In: C = the record, from 0
SETSEC:
    LD A,C
    LD [SEKSEC],A
    LD A,[DENSITY]
    OR A
    JP NZ,SET_SECTOR                ; a single-density record is a sector
    RET

;; CP/M's SETDMA: sets where READ and WRITE move the record.
;; In: BC = the address
SETDMA:
    LD [DMAADR],BC
    RET

;; CP/M's SETTRK: sets the track to read or write.
;; In: BC = the track
SETTRK:
    LD [SEKTRK],BC
    LD A,[DENSITY]
    OR A
    JP NZ,SEEK                      ; a single-density disk seeks at once
    RET

;; CP/M's HOME: moves the selected drive's head to track 0, first writing the host buffer if a write is pending.
HOME_DISK:
    LD A,[DENSITY]
    OR A
    JP NZ,RESTORE
    LD A,[HSTWRT]
    OR A
    JP NZ,HOME_DISK_RESTORE
    LD [HSTACT],A
HOME_DISK_RESTORE:
    JP RESTORE

;; CP/M's READ: reads the record SETTRK and SETSEC set to the DMA address.
;; Out: A = 0, or 1 after an error
READ:
    LD A,[DENSITY]
    OR A
    JP NZ,READ_SINGLE
    XOR A
    LD [UNACNT],A
    LD A,1
    LD [READOP],A
    LD [RSFLAG],A
    LD A,WRITE_UNALLOCATED
    LD [WRTYPE],A
    JP RWOPER

;; CP/M's WRITE: writes the record SETTRK and SETSEC set from the DMA address.
;; In: C = WRITE_ALLOCATED, WRITE_DIRECTORY or WRITE_UNALLOCATED
;; Out: A = 0, or 1 after an error
WRITE:
    LD A,[DENSITY]
    OR A
    JP NZ,WRITE_SINGLE
    XOR A
    LD [READOP],A
    LD A,C
    LD [WRTYPE],A
    CP WRITE_UNALLOCATED
    JP NZ,CHKUNA
    ; The first record of a new block: the block's records need not be read before they are written.
    LD A,UNALLOCATED_RECORDS
    LD [UNACNT],A
    LD A,[SEKDSK]
    LD [UNADSK],A
    LD HL,[SEKTRK]
    LD [UNATRK],HL
    LD A,[SEKSEC]
    LD [UNASEC],A

;; Whether this write is the next record of an unallocated block, which needs no read.
CHKUNA:
    LD A,[UNACNT]
    OR A
    JP Z,ALLOC
    DEC A
    LD [UNACNT],A
    LD A,[SEKDSK]
    LD HL,UNADSK
    CP [HL]
    JP NZ,ALLOC
    LD HL,UNATRK
    CALL SEKTRKCMP
    JP NZ,ALLOC
    LD A,[SEKSEC]
    LD HL,UNASEC
    CP [HL]
    JP NZ,ALLOC
    INC [HL]
    LD A,[HL]
    CP CPM_SECTORS
    JP C,NOOVF
    LD [HL],0
    LD HL,[UNATRK]
    INC HL
    LD [UNATRK],HL
NOOVF:
    XOR A
    LD [RSFLAG],A
    JP RWOPER

;; Not in an unallocated block: the host sector must be read first.
ALLOC:
    XOR A
    LD [UNACNT],A
    INC A
    LD [RSFLAG],A

;; Reads or writes a record through the host buffer, reading or writing its host sector as needed.
;; Out: A = ERFLAG
RWOPER:
    XOR A
    LD [ERFLAG],A
    LD A,[SEKSEC]
    OR A
    RRA
    OR A
    RRA
    LD [SEKHST],A
    LD HL,HSTACT
    LD A,[HL]
    LD [HL],1
    OR A
    JP Z,FILHST
    ; Is the host buffer this sector?
    LD A,[SEKDSK]
    LD HL,HSTDSK
    CP [HL]
    JP NZ,NOMATCH
    LD HL,HSTTRK
    CALL SEKTRKCMP
    JP NZ,NOMATCH
    LD A,[SEKHST]
    LD HL,HSTSEC
    CP [HL]
    JP Z,MATCH
NOMATCH:
    LD A,[HSTWRT]
    OR A
    CALL NZ,WRITEHST
FILHST:
    LD A,[SEKDSK]
    LD [HSTDSK],A
    LD HL,[SEKTRK]
    LD [HSTTRK],HL
    LD A,[SEKHST]
    LD [HSTSEC],A
    LD A,[RSFLAG]
    OR A
    CALL NZ,READHST
    XOR A
    LD [HSTWRT],A
MATCH:
    ; The record's place in the host buffer.
    LD A,[SEKSEC]
    AND SECTOR_MASK
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,HSTBUF
    ADD HL,DE
    LD DE,[DMAADR]
    LD BC,SECTOR_SIZE
    LD A,[READOP]
    OR A
    JR NZ,RWMOVE
    LD A,1
    LD [HSTWRT],A
    EX DE,HL
RWMOVE:
    CALL MOVE_UNDER_ROM
    LD A,[WRTYPE]
    CP WRITE_DIRECTORY
    LD A,[ERFLAG]
    RET NZ
    OR A
    RET NZ
    ; A directory write goes to the disk at once.
    XOR A
    LD [HSTWRT],A
    CALL WRITEHST
    LD A,[ERFLAG]
    RET

;; Compares SEKTRK with a track.
;; In: HL = the track's address
;; Out: zero = the same
;; Uses: DE, HL
SEKTRKCMP:
    EX DE,HL
    LD HL,SEKTRK
    LD A,[DE]
    CP [HL]
    RET NZ
    INC DE
    INC HL
    LD A,[DE]
    CP [HL]
    RET

;; Selects a drive for the controller, saving the track register of the one it leaves. The first time a drive is
;; selected, it is restored to track 0 and its disk's density is found by reading an ID field: double density if one
;; reads, single otherwise.
;; In: C = the drive
;; Out: HL = its disk parameter header, or 0 for no such drive
SELECT_DRIVE:
    LD HL,0
    LD A,C
    CP 2
    RET NC
    OR A
    LD HL,DPH_A
    JR Z,SELECT_DRIVE_HEADER
    LD HL,DPH_B
SELECT_DRIVE_HEADER:
    LD A,[FDC_DRIVE]
    CP C
    RET Z
    LD A,C
    LD [FDC_DRIVE],A
    OR A
    PUSH HL
    LD DE,DPH_DENSITY
    ADD HL,DE
    LD A,[HL]
    LD [DENSITY],A
    ; Save the track register for the other drive.
    LD HL,TRACK_B
    JR Z,SELECT_DRIVE_SAVE
    DEC HL
SELECT_DRIVE_SAVE:
    LD A,[HL]
    CP $FF
    JR Z,SELECT_DRIVE_RESTORE
    IN A,[FDC_TRACK_PORT]
    LD [HL],A
SELECT_DRIVE_RESTORE:
    LD A,C
    OR A
    LD HL,TRACK_A
    JR Z,SELECT_DRIVE_TRACK
    INC HL
SELECT_DRIVE_TRACK:
    LD A,[HL]
    OUT [FDC_TRACK_PORT],A
    EX DE,HL
    POP HL
    CP $FF
    RET NZ
    ; The drive's first select.
    CALL FDC_SELECT
    CALL HOME_DISK
    IN A,[SYSTEM_PORT]
    AND ~SINGLE_DENSITY & $FF
    OR 0
    OUT [SYSTEM_PORT],A
    CALL READ_ADDRESS
    JR Z,SELECT_DRIVE_DOUBLE
    IN A,[SYSTEM_PORT]
    AND ~SINGLE_DENSITY & $FF
    OR SINGLE_DENSITY
    OUT [SYSTEM_PORT],A
    CALL READ_ADDRESS
    RET NZ
    JR SELECT_DRIVE_SINGLE
SELECT_DRIVE_DOUBLE:
    PUSH HL
    PUSH DE
    LD DE,0                         ; no translation
    LD [HL],E
    INC HL
    LD [HL],D
    LD DE,DPH_DPB - 1
    ADD HL,DE
    LD DE,DPB_DOUBLE
    LD [HL],E
    INC HL
    LD [HL],D
    LD DE,DPH_DENSITY - DPH_DPB - 1
    ADD HL,DE
    LD A,0
    LD [HL],A
    LD [DENSITY],A
    JR SELECT_DRIVE_FOUND
SELECT_DRIVE_SINGLE:
    PUSH HL
    PUSH DE
    LD DE,XLT_SINGLE
    LD [HL],E
    INC HL
    LD [HL],D
    LD DE,DPH_DPB - 1
    ADD HL,DE
    LD DE,DPB_SINGLE
    LD [HL],E
    INC HL
    LD [HL],D
    LD DE,DPH_DENSITY - DPH_DPB - 1
    ADD HL,DE
    LD A,SINGLE_DENSITY
    LD [HL],A
    LD [DENSITY],A
SELECT_DRIVE_FOUND:
    ; READ ADDRESS left the head's track in the sector register.
    POP DE
    POP HL
    IN A,[FDC_SECTOR_PORT]
    OUT [FDC_TRACK_PORT],A
    LD [DE],A
    RET

;; Reads the next ID field under the head.
;; Out: zero = one was found
READ_ADDRESS:
    LD A,FDC_READ_ADDRESS
    OUT [FDC_COMMAND_PORT],A
    CALL FDC_WAIT
    BIT FDC_NOT_FOUND,A
    RET

;; Moves the selected drive's head to track 0.
;; Out: A = the controller's status
RESTORE:
    CALL FDC_SELECT
    LD A,FDC_RESTORE
    OUT [FDC_COMMAND_PORT],A
    JR FDC_WAIT

;; Moves the selected drive's head to a track.
;; In: C = the track
;; Out: A = the controller's status
SEEK:
    CALL FDC_SELECT
    LD A,C
    OUT [FDC_DATA_PORT],A
    LD A,FDC_SEEK
    OUT [FDC_COMMAND_PORT],A
    JR FDC_WAIT

;; Sets the sector to read or write.
;; In: C = the sector
SET_SECTOR:
    LD A,C
    OUT [FDC_SECTOR_PORT],A
    RET

;; CP/M's SECTRAN: translates a record to the sector that holds it.
;; In: BC = the record, DE = the translation table, or 0 for none
;; Out: HL = the sector
SECTRAN:
    LD A,D
    OR E
    LD H,B
    LD L,C
    RET Z
    EX DE,HL
    ADD HL,BC
    LD L,[HL]
    LD H,0
    RET

;; Stops the controller's command, turns the motors on and selects FDC_DRIVE at DENSITY.
;; Keeps: BC, DE, HL
FDC_SELECT:
    PUSH HL
    PUSH DE
    PUSH BC
    LD A,FDC_FORCE_INTERRUPT
    OUT [FDC_COMMAND_PORT],A
    CALL MOTOR_ON
    LD A,[FDC_DRIVE]
    LD E,A
    IN A,[SYSTEM_PORT]
    AND ~SYSTEM_DRIVES & $FF
    OR E
    INC A                           ; drive 0 is bit 0, drive 1 bit 1
    AND ~SINGLE_DENSITY & $FF
    LD HL,DENSITY
    OR [HL]
    OUT [SYSTEM_PORT],A
    POP BC
    POP DE
    POP HL
    RET

;; Turns the drive motors on, waiting for them to come up to speed if they were off.
;; Uses: A, B, DE
MOTOR_ON:
    IN A,[SYSTEM_PORT]
    BIT SYSTEM_MOTORS_OFF,A
    RET Z
    RES SYSTEM_MOTORS_OFF,A
    OUT [SYSTEM_PORT],A
    LD B,MOTOR_START_DELAY
    CALL DELAY
    RET

;; Turns the drive motors off.
MOTOR_OFF:
    IN A,[SYSTEM_PORT]
    SET SYSTEM_MOTORS_OFF,A
    OUT [SYSTEM_PORT],A
    RET

;; Waits about 16 ms for each count.
;; In: B = the count
;; Out: B = 0
;; Uses: A, DE
DELAY:
    LD DE,DELAY_COUNT
DELAY_LOOP:
    DEC DE
    LD A,D
    OR E
    JP NZ,DELAY_LOOP
    DJNZ DELAY
    RET

;; Waits for the controller's command to end: halts until its interrupt, then until it is no longer busy.
;; Out: A = the controller's status
FDC_WAIT:
    HALT
FDC_WAIT_BUSY:
    IN A,[FDC_COMMAND_PORT]
    BIT FDC_BUSY,A
    JR NZ,FDC_WAIT_BUSY
    RET

;; Writes the host buffer to its sector and reads it back, trying again until the read finds no error.
;; Out: ERFLAG = 0, or the error status, or $FF after the last try
WRITEHST:
    LD L,WRITE_TRIES
WRITEHST_TRY:
    LD DE,SEEK_TRIES
WRITEHST_SEEK:
    PUSH HL
    PUSH DE
    CALL SEEK_HOST
    CALL WRITE_HOST_SECTOR
    POP DE
    POP HL
    JR Z,WRITEHST_VERIFY
    DEC E
    JR NZ,WRITEHST_SEEK
    DEC D
    JR Z,WRITEHST_DONE
    CALL RESTORE
    LD E,15
    JR WRITEHST_SEEK
WRITEHST_VERIFY:
    ; Read the sector back, dropping its bytes, to check it.
    LD B,0
    LD A,FDC_READ
    OUT [FDC_COMMAND_PORT],A
WRITEHST_VERIFY_FIRST:
    HALT
    IN A,[FDC_DATA_PORT]
    DJNZ WRITEHST_VERIFY_FIRST
WRITEHST_VERIFY_SECOND:
    HALT
    IN A,[FDC_DATA_PORT]
    DJNZ WRITEHST_VERIFY_SECOND
    CALL FDC_WAIT
    AND FDC_READ_ERRORS
WRITEHST_DONE:
    LD [ERFLAG],A
    RET Z
    DEC L
    JR NZ,WRITEHST_TRY
    LD A,$FF
    JR WRITEHST_DONE

;; Reads the host buffer's sector, seeking again after errors.
;; Out: ERFLAG = 0, or the error status; zero = read
READHST:
    LD DE,SEEK_TRIES
READHST_SEEK:
    PUSH DE
    CALL SEEK_HOST
    CALL READ_HOST_SECTOR
    LD [ERFLAG],A
    POP DE
    RET Z
    DEC E
    JR NZ,READHST_SEEK
    DEC D
    RET Z
    CALL RESTORE
    LD E,15
    JR READHST_SEEK

;; Selects the host buffer's drive, seeks its track and sets its sector.
SEEK_HOST:
    LD A,[HSTDSK]
    LD C,A
    CALL SELECT_DRIVE
    LD BC,[HSTTRK]
    CALL SEEK
    LD A,[HSTSEC]
    LD C,A
    CALL SET_SECTOR
    RET

;; The transfer routines, which DISK_RESET copies to RELOCATED so they can reach the RAM under the ROM.
TRANSFER:
.logicalorg RELOCATED

;; Moves bytes with the ROM banked out, as LDIR does.
;; In: HL = from, DE = to, BC = the count
MOVE_UNDER_ROM:
    IN A,[SYSTEM_PORT]
    RES SYSTEM_ROM,A
    OUT [SYSTEM_PORT],A
    LDIR
    IN A,[SYSTEM_PORT]
    SET SYSTEM_ROM,A
    OUT [SYSTEM_PORT],A
    RET

;; Reads a single-density sector to the DMA address.
;; Out: A = 0, or 1 after an error; zero = read
READ_SINGLE:
    LD HL,[DMAADR]
    LD B,1
    JR READ_SECTOR

;; Reads a double-density sector to the host buffer.
;; Out: A = 0, or 1 after an error; zero = read
READ_HOST_SECTOR:
    LD HL,HSTBUF
    LD B,HOST_SIZE / SECTOR_SIZE
READ_SECTOR:
    LD DE,FDC_READ_ERRORS << 8 | FDC_READ
    JR TRANSFER_SECTOR

;; Writes a single-density sector from the DMA address.
;; Out: A = 0, or 1 after an error; zero = written
WRITE_SINGLE:
    LD HL,[DMAADR]
    LD B,1
    JR WRITE_SECTOR

;; Writes a double-density sector from the host buffer.
;; Out: A = 0, or 1 after an error; zero = written
WRITE_HOST_SECTOR:
    LD HL,HSTBUF
    LD B,HOST_SIZE / SECTOR_SIZE
WRITE_SECTOR:
    LD DE,FDC_WRITE_ERRORS << 8 | FDC_WRITE

;; Reads or writes a sector of 128 or 512 bytes with the ROM banked out, a byte for each NMI.
;; In: HL = the bytes, B = 1 for 128 bytes or 4 for 512, D = the status bits that are errors, E = the command
;; Out: A = 0, or 1 after an error; zero = no error
TRANSFER_SECTOR:
    CALL FDC_SELECT
    DI
    IN A,[SYSTEM_PORT]
    RES SYSTEM_ROM,A
    OUT [SYSTEM_PORT],A
    ; Put a RET at RAM's NMI vector, keeping its byte.
    PUSH HL
    LD HL,NMI_VECTOR
    LD A,[HL]
    EX AF,AF'
    LD [HL],$C9
    POP HL
    LD A,B
    LD BC,SECTOR_SIZE << 8 | FDC_DATA_PORT
    BIT 0,A
    JR NZ,TRANSFER_SECTOR_COUNT
    LD B,0                          ; 512 bytes: two runs of 256
TRANSFER_SECTOR_COUNT:
    CP 1
    PUSH AF
    LD A,E
    CP FDC_WRITE
    JR Z,TRANSFER_SECTOR_WRITE
    OUT [FDC_COMMAND_PORT],A
    POP AF
    JR Z,TRANSFER_SECTOR_READ_LAST
TRANSFER_SECTOR_READ_FIRST:
    HALT
    INI
    JR NZ,TRANSFER_SECTOR_READ_FIRST
TRANSFER_SECTOR_READ_LAST:
    HALT
    INI
    JR NZ,TRANSFER_SECTOR_READ_LAST
    JR TRANSFER_SECTOR_DONE
TRANSFER_SECTOR_WRITE:
    OUT [FDC_COMMAND_PORT],A
    POP AF
    JR Z,TRANSFER_SECTOR_WRITE_LAST
TRANSFER_SECTOR_WRITE_FIRST:
    HALT
    OUTI
    JR NZ,TRANSFER_SECTOR_WRITE_FIRST
TRANSFER_SECTOR_WRITE_LAST:
    HALT
    OUTI
    JR NZ,TRANSFER_SECTOR_WRITE_LAST
TRANSFER_SECTOR_DONE:
    EX AF,AF'
    LD [NMI_VECTOR],A
    IN A,[SYSTEM_PORT]
    SET SYSTEM_ROM,A
    OUT [SYSTEM_PORT],A
    EI
    CALL FDC_WAIT
    AND D
    RET Z
    LD A,1
    RET

.logicalorg
TRANSFER_END:
.assert RELOCATED + TRANSFER_END - TRANSFER <= DIRBUF, "The transfer routines end below DIRBUF."

;; The SIO's and PIOs' setup: a count, then each port and the byte written to it.
DEVICE_TABLE:
    .byte (DEVICE_TABLE_END - DEVICE_TABLE - 1) / 2
    ; The keyboard: reset, 300 baud, 16x clock, 1 stop bit, no parity, 8-bit receive and transmit, DTR and RTS.
    .byte KEYBOARD_CONTROL_PORT, $18
    .byte KEYBOARD_BAUD_PORT, $05
    .byte KEYBOARD_CONTROL_PORT, $04, KEYBOARD_CONTROL_PORT, $44
    .byte KEYBOARD_CONTROL_PORT, $03, KEYBOARD_CONTROL_PORT, $C1
    .byte KEYBOARD_CONTROL_PORT, $05, KEYBOARD_CONTROL_PORT, $E8
    .byte KEYBOARD_CONTROL_PORT, $01, KEYBOARD_CONTROL_PORT, $00
    ; The serial port: the same, with auto enables.
    .byte SERIAL_CONTROL_PORT, $18
    .byte SERIAL_BAUD_PORT, $05
    .byte SERIAL_CONTROL_PORT, $04, SERIAL_CONTROL_PORT, $44
    .byte SERIAL_CONTROL_PORT, $03, SERIAL_CONTROL_PORT, $E1
    .byte SERIAL_CONTROL_PORT, $05, SERIAL_CONTROL_PORT, $E8
    .byte SERIAL_CONTROL_PORT, $01, SERIAL_CONTROL_PORT, $00
    ; The system port: no interrupts, the ROM in and drive A selected, bits 2 and 3 inputs.
    .byte SYSTEM_CONTROL_PORT, $03
    .byte SYSTEM_PORT, 1 << SYSTEM_ROM | 1 << SYSTEM_DRIVE_A
    .byte SYSTEM_CONTROL_PORT, $CF, SYSTEM_CONTROL_PORT, $0C
    ; The printer port as outputs and the general-purpose port B as inputs.
    .byte PRINTER_CONTROL_PORT, $03, PRINTER_CONTROL_PORT, $0F
    .byte GENERAL_B_CONTROL_PORT, $03, GENERAL_B_CONTROL_PORT, $4F
DEVICE_TABLE_END:

;; Sets up the SIO, the PIOs and the baud rate generators from DEVICE_TABLE.
;; Uses: A, B, C, HL
DEVICE_RESET:
    LD HL,DEVICE_TABLE
    LD B,[HL]
DEVICE_RESET_LOOP:
    INC HL
    LD C,[HL]
    INC HL
    LD A,[HL]
    OUT [C],A
    DJNZ DEVICE_RESET_LOOP
    RET

;; Whether a key is waiting.
;; Out: A = $FF if one is, 0 if not; zero = none
KEYBOARD_STATUS:
    IN A,[KEYBOARD_CONTROL_PORT]
    AND 1 << SIO_RECEIVED
    RET Z
    LD A,$FF
    RET

;; Waits for a key, translating the cursor and keypad keys to $80-$91.
;; Out: A = the key
KEYBOARD_IN:
    CALL KEYBOARD_STATUS
    JR Z,KEYBOARD_IN
    IN A,[KEYBOARD_DATA_PORT]
    CALL TRANSLATE_KEY
    RET

;; Sends a byte to the keyboard, such as KEYBOARD_BELL.
;; In: C = the byte
KEYBOARD_OUT:
    IN A,[KEYBOARD_CONTROL_PORT]
    AND 1 << SIO_TRANSMIT_EMPTY
    JR Z,KEYBOARD_OUT
    LD A,C
    OUT [KEYBOARD_DATA_PORT],A
    RET

;; Translates a cursor or keypad key's code to its place in KEY_CODES.
;; In: A = the key
;; Out: A = the translated key, or the key itself
;; Uses: BC, DE, HL
TRANSLATE_KEY:
    LD HL,KEYBOARD_KEYS
    LD BC,KEYBOARD_KEYS_END - KEYBOARD_KEYS
    CPIR
    RET NZ
    LD DE,KEYBOARD_KEYS
    OR A
    SBC HL,DE                       ; the key's place plus one
    LD DE,KEY_CODES - 1
    ADD HL,DE
    LD A,[HL]
    RET

;; The codes the keyboard sends for the arrows (up, down, left, right), then the keypad's 0 to 9, minus, comma,
;; ENTER and period. The $FF at the end matches the byte after KEY_CODES.
KEYBOARD_KEYS:
    .byte $F1, $F2, $F3, $F4
    .byte $B1, $C0, $C1, $C2, $D0, $D1, $D2, $E1, $E2, $E3, $E4, $D3, $C3, $B2
    .byte $FF
KEYBOARD_KEYS_END:

;; What KEYBOARD_IN returns for each of KEYBOARD_KEYS, which CP/M's BIOS translates again.
KEY_CODES:
    .byte $80, $81, $82, $83, $84, $85, $86, $87, $88, $89, $8A, $8B, $8C, $8D, $8E, $8F, $90, $91

;; Whether the serial port has received a character.
;; Out: A = $FF if it has, 0 if not; zero = none
SERIAL_STATUS:
    IN A,[SERIAL_CONTROL_PORT]
    AND 1 << SIO_RECEIVED
    JR STATUS_RESULT

;; Waits for a character from the serial port.
;; Out: A = the character
SERIAL_IN:
    CALL SERIAL_STATUS
    JR Z,SERIAL_IN
    IN A,[SERIAL_DATA_PORT]
    RET

;; Sends a character to the serial port.
;; In: C = the character
SERIAL_OUT:
    IN A,[SERIAL_CONTROL_PORT]
    AND 1 << SIO_TRANSMIT_EMPTY
    JR Z,SERIAL_OUT
    LD A,C
    OUT [SERIAL_DATA_PORT],A
    RET

;; Whether the serial port can take a character.
;; Out: A = $FF if it can, 0 if not; zero = not
SERIAL_OUT_STATUS:
    IN A,[SERIAL_CONTROL_PORT]
    AND 1 << SIO_TRANSMIT_EMPTY
    JR STATUS_RESULT

;; Whether the printer can take a character.
;; Out: A = $FF if it can, 0 if not; zero = not
PRINTER_STATUS:
    IN A,[SYSTEM_PORT]
    BIT SYSTEM_PRINTER_READY,A
STATUS_RESULT:
    RET Z
    LD A,$FF
    RET

;; Sends a character to the printer, strobing it.
;; In: C = the character
PRINTER_OUT:
    CALL PRINTER_STATUS
    JR Z,PRINTER_OUT
    LD A,C
    OUT [PRINTER_DATA_PORT],A
    IN A,[SYSTEM_PORT]
    SET SYSTEM_PRINTER_STROBE,A
    OUT [SYSTEM_PORT],A
    RES SYSTEM_PRINTER_STROBE,A
    OUT [SYSTEM_PORT],A
    RET

;; Clears the screen and homes the cursor, ending any escape sequence and the Greek characters.
VIDEO_RESET:
    LD A,SPACE
    LD [CURSOR_LINE],A
    CALL CLEAR
    LD [CURSOR_ADDRESS],HL
    XOR A
    LD [ESCAPE_STATE],A
    LD A,$17
    OUT [UNUSED_PORT],A
    LD A,NORMAL_CHARACTERS
    LD [CHARACTER_MASK],A
    RET

;; Shows a character on the screen, or does what a control character or an escape sequence says:
;; BELL beeps, LINE_FEED, RETURN, BACKSPACE, CURSOR_RIGHT, CURSOR_UP and HOME move the cursor, CLEAR_TO_END_OF_LINE,
;; CLEAR_TO_END_OF_SCREEN and CLEAR_SCREEN clear, and ESCAPE starts ESC = (line plus 32, column plus 32), ESC G
;; and ESC A (Greek on and off), ESC R (delete the line) and ESC E (insert a line).
;; In: C = the character
VIDEO_OUT:
    LD A,[ESCAPE_STATE]
    OR A
    JP NZ,VIDEO_ESCAPE
    LD A,BELL
    CP C
    JR NZ,VIDEO_OUT_CHARACTER
    LD C,KEYBOARD_BELL
    JP KEYBOARD_OUT
VIDEO_OUT_CHARACTER:
    CALL HIDE_CURSOR
    LD DE,SHOW_CURSOR
    PUSH DE                         ; every case returns through SHOW_CURSOR with HL the cursor
    LD A,C
    CP LINE_FEED
    JR Z,DOWN
    CP RETURN
    JP Z,LINE_START
    CP BACKSPACE
    JR Z,LEFT
    CP CURSOR_RIGHT
    JR Z,RIGHT
    CP CURSOR_UP
    JR Z,UP
    CP ESCAPE
    JP Z,START_ESCAPE
    CP CLEAR_TO_END_OF_LINE
    JP Z,CLEAR_LINE_END
    CP CLEAR_TO_END_OF_SCREEN
    JR Z,CLEAR_SCREEN_END
    CP CLEAR_SCREEN
    JR Z,CLEAR
    CP HOME
    JR Z,HOME_CURSOR
    CP $60
    JR C,VIDEO_STORE
    LD A,[CHARACTER_MASK]           ; lowercase, or Greek
    AND C
VIDEO_STORE:
    LD [HL],A
    INC HL
    LD A,L
    AND LINE_BYTES - 1
    CP COLUMNS
    RET C
    CALL LINE_START
    JR DOWN

;; Scrolls the screen up a line if the cursor is past the last line.
;; In: HL = the cursor
;; Out: HL = the cursor
SCROLL_IF_NEEDED:
    LD DE,VIDEO_END - 1
    LD A,D
    CP H
    JR C,SCROLL
    RET NZ
    LD A,E
    CP L
    RET NC

;; Scrolls the screen up a line, clearing the last, and puts the cursor at its start.
;; Out: HL = the last line
SCROLL:
    LD B,LINES - 1
    LD HL,VIDEO + LINE_BYTES
    LD DE,VIDEO
SCROLL_LINE:
    PUSH BC
    LD BC,COLUMNS
    LDIR
    LD BC,LINE_BYTES - COLUMNS
    ADD HL,BC
    EX DE,HL
    ADD HL,BC
    EX DE,HL
    POP BC
    DJNZ SCROLL_LINE
    LD HL,LAST_LINE
    JR CLEAR_LINE_END

;; Moves the cursor down a line, scrolling at the bottom.
DOWN:
    LD DE,LINE_BYTES
    ADD HL,DE
    JR SCROLL_IF_NEEDED

;; Moves the cursor left, but not past the start of the line.
LEFT:
    LD A,L
    AND LINE_BYTES - 1
    RET Z
    DEC HL
    RET

;; Moves the cursor right, but not past the end of the line.
RIGHT:
    LD A,L
    AND LINE_BYTES - 1
    CP COLUMNS - 1
    RET NC
    INC HL
    RET

;; Moves the cursor up a line, but not past the top.
UP:
    PUSH HL
    LD DE,-LINE_BYTES & $FFFF
    ADD HL,DE
    PUSH HL
    OR A
    LD DE,VIDEO
    SBC HL,DE
    POP HL
    POP DE
    RET NC
    EX DE,HL
    RET

;; Fills video RAM with spaces.
;; Out: HL = VIDEO, the cursor's home
CLEAR:
    LD HL,VIDEO
    LD DE,VIDEO + 1
    LD BC,VIDEO_SIZE - 1
    LD [HL],SPACE
    LDIR
    LD HL,VIDEO
    RET

;; Moves the cursor home.
;; Out: HL = VIDEO
HOME_CURSOR:
    LD HL,VIDEO
    RET

;; Clears from the cursor to the end of the screen.
;; In: HL = the cursor
CLEAR_SCREEN_END:
    PUSH HL
    CALL CLEAR_LINE_END
    LD DE,LINE_BYTES
    LD A,L
    AND LINE_BYTES
    LD L,A
    ADD HL,DE
    LD A,>VIDEO_END
    CP H
    JR Z,CLEAR_SCREEN_END_DONE
    LD E,L
    LD D,H
    OR A
    LD HL,VIDEO_END - 1
    SBC HL,DE
    LD C,L
    LD B,H
    LD H,D
    LD L,E
    INC DE
    LD [HL],SPACE
    LDIR
CLEAR_SCREEN_END_DONE:
    POP HL
    RET

;; Clears from the cursor to the end of its line.
;; In: HL = the cursor
CLEAR_LINE_END:
    LD A,L
    AND LINE_BYTES - 1
    CP COLUMNS - 1
    JR C,CLEAR_LINE_END_FILL
    LD [HL],SPACE
    RET
CLEAR_LINE_END_FILL:
    PUSH HL
    PUSH HL
    LD A,L
    AND LINE_BYTES
    LD L,A
    LD DE,COLUMNS - 1
    ADD HL,DE
    POP DE
    PUSH DE
    OR A
    SBC HL,DE
    LD C,L
    LD B,H
    POP HL
    LD E,L
    LD D,H
    INC DE
    LD [HL],SPACE
    LDIR
    POP HL
    RET

;; Takes the cursor off the screen: clears the character's blink, or puts back the space under a CURSOR.
;; Out: HL = the cursor
HIDE_CURSOR:
    LD HL,[CURSOR_ADDRESS]
    LD A,[HL]
    CP CURSOR
    LD A,SPACE
    JR NZ,HIDE_CURSOR_BLINK
    LD [HL],A
HIDE_CURSOR_BLINK:
    RES BLINK,[HL]
    RET

;; Moves the cursor to the start of its line.
;; In: HL = the cursor
;; Out: HL = the start of its line
LINE_START:
    LD A,L
    AND LINE_BYTES
    LD L,A
    RET

;; Starts an escape sequence.
START_ESCAPE:
    LD A,ESCAPE_STATE_ESCAPE
    LD [ESCAPE_STATE],A
    RET

;; Takes the character after ESCAPE, or a cursor address's line or column.
;; In: A = ESCAPE_STATE, C = the character
VIDEO_ESCAPE:
    LD HL,ESCAPE_RETURN
    PUSH HL
    LD HL,ESCAPE_STATE
    LD [HL],0
    CP ESCAPE_STATE_ESCAPE
    JR NZ,VIDEO_ESCAPE_LINE
    LD A,C
    RES 7,A
    CP 'G'
    JR Z,GREEK_ON
    CP 'A'
    JR Z,GREEK_OFF
    CP 'R'
    JR Z,DELETE_LINE
    CP 'E'
    JR Z,INSERT_LINE
    CP '='
    RET NZ
    LD [HL],ESCAPE_STATE_LINE
    RET
VIDEO_ESCAPE_LINE:
    CP ESCAPE_STATE_LINE
    JR NZ,VIDEO_ESCAPE_COLUMN
    LD A,C
    LD [CURSOR_LINE],A
    LD [HL],ESCAPE_STATE_COLUMN
    RET
VIDEO_ESCAPE_COLUMN:
    CP ESCAPE_STATE_COLUMN
    RET NZ
    ; Move the cursor to the line and column, each less 32 and taken modulo the screen's size.
    CALL HIDE_CURSOR
    POP HL
    LD HL,VIDEO
    LD A,C
    SUB SPACE
VIDEO_ESCAPE_COLUMN_MODULO:
    SUB COLUMNS
    JR NC,VIDEO_ESCAPE_COLUMN_MODULO
    ADD A,COLUMNS
    LD L,A
    LD A,[CURSOR_LINE]
    SUB SPACE
VIDEO_ESCAPE_LINE_MODULO:
    SUB LINES
    JR NC,VIDEO_ESCAPE_LINE_MODULO
    ADD A,LINES
    LD DE,LINE_BYTES
VIDEO_ESCAPE_LINE_ADD:
    JP Z,SHOW_CURSOR
    ADD HL,DE
    DEC A
    JR VIDEO_ESCAPE_LINE_ADD

;; Shows the cursor: sets the character's blink, showing CURSOR on a space, and keeps its place.
;; In: HL = the cursor
SHOW_CURSOR:
    LD A,[HL]
    CP SPACE
    JR NZ,SHOW_CURSOR_BLINK
    LD A,CURSOR
SHOW_CURSOR_BLINK:
    SET BLINK,A
    LD [HL],A
    LD [CURSOR_ADDRESS],HL
ESCAPE_RETURN:
    RET

;; ESC G: lowercase letters show as Greek letters.
GREEK_ON:
    LD A,GREEK_CHARACTERS
    LD [CHARACTER_MASK],A
    RET

;; ESC A: lowercase letters show as themselves.
GREEK_OFF:
    LD A,NORMAL_CHARACTERS
    LD [CHARACTER_MASK],A
    RET

;; ESC R: deletes the cursor's line, moving the lines below it up and clearing the last.
DELETE_LINE:
    POP HL
    CALL LINES_BELOW
    PUSH DE
    JR Z,DELETE_LINE_LAST
    LDIR
DELETE_LINE_LAST:
    LD HL,LAST_LINE
    CALL CLEAR_LINE_END
    POP HL
    JR SHOW_CURSOR

;; ESC E: inserts a line at the cursor's, moving it and the lines below it down and dropping the last.
INSERT_LINE:
    POP HL
    CALL LINES_BELOW
    PUSH DE
    JR Z,INSERT_LINE_CLEAR
    LD DE,VIDEO_END - 1
    LD HL,LAST_LINE - 1
    LDDR
INSERT_LINE_CLEAR:
    POP HL
    PUSH HL
    CALL CLEAR_LINE_END
    POP HL
    JR SHOW_CURSOR

;; The bytes from the line below the cursor's to the last line.
;; Out: HL = the next line, DE = the cursor's line, BC = the bytes between it and the last line; zero = none
LINES_BELOW:
    CALL HIDE_CURSOR
    CALL LINE_START
    PUSH HL
    EX DE,HL
    LD HL,LAST_LINE
    OR A
    SBC HL,DE
    LD B,H
    LD C,L
    POP HL
    PUSH HL
    LD DE,LINE_BYTES
    ADD HL,DE
    POP DE
    LD A,B
    OR C
    RET

;; Shows the zero-terminated string after the CALL and returns past it.
;; Uses: A, BC, DE, HL
PRINT:
    EX [SP],HL
    LD A,[HL]
    INC HL
    EX [SP],HL
    OR A
    RET Z
    LD C,A
    CALL VIDEO_OUT
    JR PRINT

; Unused.
    .byte $FF, $00
.assert * = $0800, "The ROM is 2K."
