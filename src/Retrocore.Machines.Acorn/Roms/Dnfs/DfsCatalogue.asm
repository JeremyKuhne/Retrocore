; ---------------------------------------------------------------------------------------------------------------------
; The DFS's catalogue and its 8271 driver: *TITLE, *ACCESS, *OPT, *ENABLE and *RENAME; finding room for a file and
; adding it to the catalogue; reading and writing the catalogue; selecting drives, sending the 8271 its commands and
; handling its results; the NMI code the DFS copies to page &0D; and OSFIND, which opens and closes files.
;
; The catalogue is sectors 0 and 1 of track 0 (the Disc Filing System User Guide's technical information), which the
; DFS keeps at &0E00-&0FFF (DnfsEquates.asm). A disc has 10 sectors of 256 bytes on each track. Drives 0 and 1 are
; the two drives' first sides and drives 2 and 3 their second sides.
;
; The 8271 is programmed in its non-DMA mode, so it raises an NMI for each byte and again when a command ends (the
; Intel data sheet). The DFS claims the NMI from the MOS (<SET_UP_NMI_CODE>), copies one of the handlers below to &0D00,
; and lets the handler move the bytes and start each track's command in turn, while the foreground waits for the 8271 to
; be idle.
; ---------------------------------------------------------------------------------------------------------------------

; The 8271's commands, with neither drive select bit; the forms that take a record length and count (multi-record).

FDC_SCAN_DATA = $00                 ;; 8271 command: scan data, a pattern in memory against sectors
FDC_SCAN_DATA_AND_DELETED = $04     ;; 8271 command: scan data and deleted data
FDC_WRITE_DATA_128 = $0A            ;; 8271 command: write data, one 128-byte sector
FDC_WRITE_DATA = $0B                ;; 8271 command: write data: track, sector, then length code and count
FDC_WRITE_DELETED_DATA_128 = $0E    ;; 8271 command: write deleted data, one 128-byte sector
FDC_WRITE_DELETED_DATA = $0F        ;; 8271 command: write deleted data: track, sector, then length code and count
FDC_READ_DATA_128 = $12             ;; 8271 command: read data, one 128-byte sector
FDC_READ_DATA = $13                 ;; 8271 command: read data: track, sector, then length code and count
FDC_READ_DATA_AND_DELETED_128 = $16 ;; 8271 command: read data and deleted data, one 128-byte sector
FDC_READ_DATA_AND_DELETED = $17     ;; 8271 command: read data and deleted data: track, sector, length code and count
FDC_READ_ID = $1B                   ;; 8271 command: read ID fields: track, then a zero, then the number of fields
FDC_VERIFY_128 = $1E                ;; 8271 command: verify data and deleted data, one 128-byte sector
FDC_VERIFY = $1F                    ;; 8271 command: verify data and deleted data, checking CRCs without a transfer
FDC_FORMAT = $23                    ;; 8271 command: format a track
FDC_SEEK = $29                      ;; 8271 command: seek to a track, the parameter
FDC_READ_DRIVE_STATUS = $2C         ;; 8271 command: read the drive status, with no parameters; clears not ready
FDC_SPECIFY = $35                   ;; 8271 command: specify the drives' timing or bad tracks
FDC_WRITE_SPECIAL_REGISTER = $3A    ;; 8271 command: write a special register: its address, then the value
FDC_READ_SPECIAL_REGISTER = $3D     ;; 8271 command: read a special register, whose address is the parameter

; The parts of a command and its parameters.

FDC_SELECT_0 = $40                  ;; 8271 command: bit 6, select 0, for drives 0 and 2
FDC_SELECT_1 = $80                  ;; 8271 command: bit 7, select 1, for drives 1 and 3
FDC_SPECIFY_INITIALISATION = $0D    ;; specify: step rate, head settling time, then index count and head load time
FDC_SPECIFY_BAD_TRACKS_0 = $10      ;; specify: surface 0's two bad tracks, then its current track
FDC_SPECIFY_BAD_TRACKS_1 = $18      ;; specify: surface 1's two bad tracks, then its current track
FDC_SECTOR_256 = $20                ;; a length code and count parameter: 256-byte sectors, ORed with the count
FDC_MODE_NON_DMA = $C1              ;; the mode register: bits 6-7 set as required, single actuator off, non-DMA mode

; The 8271's special registers, the parameter of FDC_READ_SPECIAL_REGISTER and FDC_WRITE_SPECIAL_REGISTER.

FDC_REGISTER_SCAN_SECTOR = $06      ;; 8271 register: the scan sector number, or the sector a multi-sector error hit
FDC_REGISTER_SURFACE_0_BAD_1 = $10  ;; 8271 register: surface 0's first bad track
FDC_REGISTER_SURFACE_0_BAD_2 = $11  ;; 8271 register: surface 0's second bad track
FDC_REGISTER_SURFACE_0_TRACK = $12  ;; 8271 register: surface 0's current track
FDC_REGISTER_SCAN_COUNT_LOW = $13   ;; 8271 register: the scan count, low byte
FDC_REGISTER_SCAN_COUNT_HIGH = $14  ;; 8271 register: the scan count, high byte
FDC_REGISTER_MODE = $17             ;; 8271 register: the mode register
FDC_REGISTER_SURFACE_1_BAD_1 = $18  ;; 8271 register: surface 1's first bad track
FDC_REGISTER_SURFACE_1_BAD_2 = $19  ;; 8271 register: surface 1's second bad track
FDC_REGISTER_SURFACE_1_TRACK = $1A  ;; 8271 register: surface 1's current track
FDC_REGISTER_DRIVE_INPUT = $22      ;; 8271 register: the drive control input port
FDC_REGISTER_DRIVE_OUTPUT = $23     ;; 8271 register: the drive control output port

; Bits of the drive control output port.

FDC_OUTPUT_LOAD_HEAD = $08          ;; drive control output: load head
FDC_OUTPUT_SIDE_1 = $20             ;; drive control output: the write fault reset output, set for drives 2 and 3
FDC_OUTPUT_SELECT_0 = $40           ;; drive control output: select 0
FDC_OUTPUT_SELECT_1 = $80           ;; drive control output: select 1

; Bits of the status register and of the drive status.

FDC_STATUS_BUSY = $80               ;; 8271 status: a command is in progress
FDC_STATUS_COMMAND_FULL = $40       ;; 8271 status: the command register is full
FDC_STATUS_PARAMETER_FULL = $20     ;; 8271 status: the parameter register is full
FDC_STATUS_RESULT_FULL = $10        ;; 8271 status: the result register is full
FDC_STATUS_INTERRUPT = $08          ;; 8271 status: an interrupt request, a command ended; reading the result clears it
FDC_STATUS_DATA_REQUEST = $04       ;; 8271 status: a non-DMA data request, a byte to read or write
FDC_DRIVE_READY_0 = $04             ;; drive status: ready 0, the select 0 drive is ready
FDC_DRIVE_READY_1 = $40             ;; drive status: ready 1, the select 1 drive is ready

; The 8271's result codes: the completion type in bits 3-4 and its code in bits 1-2.

FDC_RESULT_OK = $00                 ;; 8271 result: good completion, or a scan not met
FDC_RESULT_SCAN_EQUAL = $02         ;; 8271 result: scan met equal
FDC_RESULT_SCAN_NOT_EQUAL = $04     ;; 8271 result: scan met not equal
FDC_RESULT_CLOCK_ERROR = $08        ;; 8271 result: clock error
FDC_RESULT_LATE_DMA = $0A           ;; 8271 result: late DMA, a byte not taken or given in time
FDC_RESULT_ID_CRC_ERROR = $0C       ;; 8271 result: ID field CRC error
FDC_RESULT_DATA_CRC_ERROR = $0E     ;; 8271 result: data field CRC error
FDC_RESULT_NOT_READY = $10          ;; 8271 result: drive not ready
FDC_RESULT_WRITE_PROTECT = $12      ;; 8271 result: write protect
FDC_RESULT_TRACK_0_NOT_FOUND = $14  ;; 8271 result: track 0 not found
FDC_RESULT_WRITE_FAULT = $16        ;; 8271 result: write fault
FDC_RESULT_SECTOR_NOT_FOUND = $18   ;; 8271 result: sector not found
FDC_RESULT_DELETED_DATA = $20       ;; 8271 result: bit 5, deleted data found
FDC_RESULT_TYPE_LOW = $08           ;; 8271 result: bit 3, set for completion types 01 and 11 (recoverable, not found)
FDC_SEQUENCE_END = $EA              ;; ends a sequence in <FDC_SEQUENCES>

; The disc's layout.

DFS_SECTORS_PER_TRACK = 10          ;; the sectors on a track, numbered 0-9
DFS_DRIVES = 4                      ;; the drives, 0-3
DFS_TITLE_LENGTH = 12               ;; the characters of a disc's title: eight begin the first sector, four the second
DFS_MAX_FILES = 31                  ;; the most files a catalogue holds
DFS_RETRY_COUNT = 10                ;; the tries a command gets, as the data sheet advises for recoverable errors
DFS_FIRST_HANDLE = $11              ;; the first file handle the DFS gives, for the channel at &1120
DFS_LAST_HANDLE = $15               ;; the last file handle the DFS gives, for the channel at &11A0
DFS_CHANNEL_SIZE = $20              ;; the bytes of each channel's variables at <DFS_CHANNELS>

; Each open file's variables: a block of DFS_CHANNEL_SIZE bytes at DFS_CHANNELS + DFS_CHANNEL_SIZE * n, n = 1-5.
; Bytes 0-15 hold the file's catalogue entry interleaved, the name's characters at even offsets and its information at
; odd ones.

DFS_CHANNEL_READ_ONLY = 12          ;; a channel: the name's seventh character, whose bit 7 is set when opened for input
DFS_CHANNEL_MIXED = 13              ;; a channel: the catalogue's byte of high bits for the file
DFS_CHANNEL_DIRECTORY = 14          ;; a channel: the file's directory, bit 7 set when it is locked
DFS_CHANNEL_POINTER = 16            ;; a channel: PTR, three bytes
DFS_CHANNEL_BUFFER = 19             ;; a channel: the page of its sector buffer, &12-&16
DFS_CHANNEL_EXTENT = 20             ;; a channel: EXT, the file's length, three bytes
DFS_CHANNEL_FLAGS = 23              ;; a channel: bits 0-1 the drive, bit 5 EXT changed, bit 6 the buffer changed
DFS_CHANNEL_BIT = 27                ;; a channel: its bit in <DFS_OPEN_CHANNELS>
DFS_CHANNEL_EXTENT_CHANGED = $20    ;; DFS_CHANNEL_FLAGS: the catalogue's length must be set from EXT

; The DFS's variables in page &10 that this part uses.

DFS_TRANSFER_SAVE = $1040           ;; a copy of <DFS_TRANSFER_COUNT> and <DFS_TRANSFER_ADDRESS> for a retry
DFS_TUBE_ADDRESS = $1072            ;; the second processor's address for a transfer, four bytes
DFS_LOAD_HIGH = DFS_TUBE_ADDRESS + 2 ;; bits 16-31 of a file's load address, the transfer address's high bytes
DFS_EXEC_HIGH = $1076               ;; bits 16-31 of a file's execution address
DFS_START_HIGH = $1078              ;; bits 16-31 of the start address of the memory *SAVE or OSFILE saves
DFS_END_HIGH = $107A                ;; bits 16-31 of the end address of the memory being saved
DFS_COMMAND_SECTORS = $107C         ;; the sectors the current command moves, those left on its track at most
DFS_TUBE_TYPE = $1080               ;; the Tube transfer type of the current transfer, for restarting it on a retry
DFS_CATALOGUE_DRIVE = $1082         ;; the drive whose catalogue is at &0E00, &FF when there is none
DFS_SELECTED_DRIVE = $1083          ;; the drive last selected through the drive control output port
DFS_DRIVES_RECALIBRATED = $1085     ;; bit 7 once drive 0 has been sent to track 0 since a reset, bit 6 for drive 1
DFS_CLOSE_MODE = $1086              ;; ANDed with DFS_CHANNEL_FLAGS on closing: DFS_CHANNEL_EXTENT_CHANGED to update
DFS_OPEN_CHANNELS = $10C0           ;; a bit for each open channel: bit 7 for the channel at &1120 to bit 3 for &11A0
DFS_FREE_CHANNEL_BIT = $10C1        ;; the bit of the free channel <FIND_OPEN_CHANNEL> found
DFS_CHANNEL = $10C2                 ;; the current channel's offset in DFS_CHANNELS, &20-&A0, or 0 for none free
DFS_CHANNEL_ENTRY = $10C3           ;; the offset in the catalogue of the current channel's file
DFS_COPY_COUNT = $10C4              ;; a count of the characters <DFS_OSFIND> copies
DFS_SAVED_X = $10C5                 ;; X, kept while a channel is closed
DFS_MESSAGES_OFF = $10C6            ;; bit 7 set for *OPT 1,0: no file information is shown
DFS_ENABLE = $10C7                  ;; 1 after *ENABLE, until the next command
DFS_DEFAULT_DIRECTORY = $10C9       ;; the directory *DIR set
DFS_DEFAULT_DRIVE = $10CA           ;; the drive *DRIVE set
DFS_TUBE_TRANSFER = $10D5           ;; nonzero while the transfer is to or from the second processor
DFS_NO_TUBE = $10D6                 ;; &FF when there is no second processor, 0 when there is

; The NMI workspace (&A0-&A7) as the transfers use it.

DFS_TRANSFER_COMMAND = NMI_WORKSPACE + 1 ;; the 8271 command for each track of the transfer, with select 0
DFS_RETRIES = NMI_WORKSPACE + 2     ;; the tries left for the current command, less one
DFS_TRANSFER_COUNT = NMI_WORKSPACE + 3 ;; the bytes left: low, middle and high, the last two counting from 1
DFS_TRANSFER_ADDRESS = NMI_WORKSPACE + 6 ;; the address in this machine's memory of the next byte

; The filing system workspace as the catalogue routines use it.

DFS_LENGTH_HIGH = FS_WORKSPACE + 4  ;; the length's third byte, while a file is saved
DFS_TRACK = FS_WORKSPACE + 14       ;; the track of the current 8271 command
DFS_SECTOR = FS_WORKSPACE + 15      ;; the sector of the current 8271 command

ACCESS_LOCK = OS_COMMAND_WORKSPACE + 2 ;; *ACCESS: &80 to lock the files, 0 to unlock them
NEW_ENTRY_SLOT = FS_SCRATCH         ;; <MAKE_CATALOGUE_ENTRY>: the offset of the new file's entry
RENAME_ENTRY = FS_SCRATCH + 3       ;; *RENAME: the offset of the file's entry in the catalogue
OSFIND_MODE = FS_SCRATCH + 4        ;; <DFS_OSFIND>: the call, &40 to open for input, &80 for output, &C0 for update
CHANNEL_SEARCH_COUNT = FS_SCRATCH + 2 ;; <FIND_OPEN_CHANNEL>: the characters left to compare
CHANNEL_SEARCH_OFFSET = FS_SCRATCH + 3 ;; <FIND_OPEN_CHANNEL>: the offset of the channel being looked at
CHANNEL_SEARCH_BIT = FS_SCRATCH + 5 ;; <FIND_OPEN_CHANNEL>: the channel's bit in <DFS_OPEN_CHANNELS>

; Calls, and the error numbers the routines here raise.

DFS_NMI_WRITE = 0                   ;; <SET_UP_NMI_CODE>: the transfer handler with the write patch
DFS_NMI_READ = 1                    ;; <SET_UP_NMI_CODE>: the transfer handler as it is, for reading
DFS_NMI_NONE = 2                    ;; <SET_UP_NMI_CODE>: an RTI alone, for commands that move no data
DFS_TUBE_READ = 0                   ;; Tube transfer: start reading the second processor's memory
DFS_TUBE_WRITE = 1                  ;; Tube transfer: start writing the second processor's memory
DFS_TUBE_CLAIM = $C1                ;; Tube call: claim the Tube for the DFS, claimant 1
DFS_OSBYTE_CLOSE_SPOOL_EXEC = $77   ;; OSBYTE &77: close any *SPOOL and *EXEC files
DFS_ERROR_ESCAPE = $11              ;; the "Escape" error
DFS_ERROR_CATALOGUE_FULL = $BE      ;; the "Cat full" error
DFS_ERROR_TOO_MANY_OPEN = $C0       ;; the "Too many open" error
DFS_ERROR_OPEN = $C2                ;; the "Open" error
DFS_ERROR_EXISTS = $C4              ;; the "Exists" error
DFS_ERROR_DISK_FULL = $C6           ;; the "Disk full" error
DFS_ERROR_FAULT = $C7               ;; the "Disk fault" and "Drive fault" errors
DFS_ERROR_DISK_CHANGED = $C8        ;; the "Disk changed" error
DFS_ERROR_DISK_READ_ONLY = $C9      ;; the "Disk read only" error
DFS_ERROR_BAD_OPTION = $CB          ;; the "Bad option" error
DFS_ERROR_BAD_DRIVE = $CD           ;; the "Bad drive" error
DFS_ERROR_BAD_ATTRIBUTE = $CF       ;; the "Bad attribute" error

;; *TITLE: sets the current drive's disc title.
;;
;; The title is up to 12 characters, padded with spaces: the first eight in the catalogue's first sector and the rest
;; in its second. The catalogue is read afresh, changed and written back.
;; In: TEXT_POINTER/Y = the command's argument
;; Entry: TITLE_COMMAND_WRITE = writes the catalogue back; other commands call it to do that
TITLE_COMMAND:
    jsr REQUIRE_ARGUMENT                       ; a title must be given
    jsr SELECT_DEFAULTS
    jsr FETCH_CATALOGUE                       ; read the catalogue
    ldx #DFS_TITLE_LENGTH - 1
    lda #' '
TITLE_COMMAND_CLEAR:
    jsr SET_TITLE_CHARACTER
    dex
    bpl TITLE_COMMAND_CLEAR
TITLE_COMMAND_LOOP:
    inx
    jsr READ_NAME_CHARACTER                       ; the next character, carry set at the end
    bcs TITLE_COMMAND_WRITE
    jsr SET_TITLE_CHARACTER
    cpx #DFS_TITLE_LENGTH - 1
    bcc TITLE_COMMAND_LOOP
TITLE_COMMAND_WRITE:
    jmp WRITE_CATALOGUE

;; Stores a character of the disc title.
;; In: A = the character, X = its position, 0-11
;; Keeps: A, X, Y
SET_TITLE_CHARACTER:
    cpx #8
    bcc SET_TITLE_CHARACTER_1
    sta CATALOGUE_INFO-8,x          ; characters 8-11 begin the second sector
    rts
SET_TITLE_CHARACTER_1:
    sta CATALOGUE_NAMES,x
    rts

;; *ACCESS: locks or unlocks the files that match a name, which may have wildcards.
;;
;; The attribute is L to lock the files, or nothing to unlock them. A matching file that is open stops the command with
;; the "Open" error, after the files before it are changed in the catalogue in memory but not on the disc. Each file is
;; shown when *OPT 1 is on.
;; In: TEXT_POINTER/Y = the command's argument
;; Errors: &CF = "Bad attribute", &D6 = "Not found", &C2 = "Open"
ACCESS_COMMAND:
    jsr ALLOW_WILDCARDS                       ; allow wildcards
    jsr REQUIRE_ARGUMENT
    jsr READ_NAME                       ; read the file name
    ldx #0                          ; unlocked, unless an L follows
    jsr START_STRING
    bne ACCESS_COMMAND_ATTRIBUTE
ACCESS_COMMAND_SET:
    stx ACCESS_LOCK
    jsr FIND_FIRST                       ; find the first file
    bcs ACCESS_COMMAND_LOOP
    jmp NOT_FOUND                       ; "Not found"
ACCESS_COMMAND_LOOP:
    jsr CHECK_NOT_OPEN                       ; "Open" if it is open
    lda CATALOGUE_NAMES+15,y        ; the directory, bit 7 the lock
    and #$7F
    ora ACCESS_LOCK
    sta CATALOGUE_NAMES+15,y
    jsr PRINT_INFO_IF_ON                       ; show it if *OPT 1 is on
    jsr FIND_NEXT                       ; the next file that matches
    bcs ACCESS_COMMAND_LOOP
    bcc TITLE_COMMAND_WRITE         ; always
ACCESS_COMMAND_LOCK:
    ldx #$80
ACCESS_COMMAND_ATTRIBUTE:
    jsr READ_NAME_CHARACTER
    bcs ACCESS_COMMAND_SET          ; the end of the attribute
    and #$5F                        ; to capitals
    cmp #'L'
    beq ACCESS_COMMAND_LOCK
    jsr BAD_ERROR                       ; "Bad attribute"
    .byte DFS_ERROR_BAD_ATTRIBUTE
    .byte "attribute",0

;; OSFSC 0, *OPT: sets the DFS's options.
;;
;; *OPT 0 and *OPT 1 turn the information shown as files are used on (a nonzero value) or off; *OPT 4 sets the boot
;; option in the current drive's catalogue, bits 0-1 of the value.
;; In: X = the option, Y = its value
;; Keeps: A, X, Y
;; Errors: &CB = "Bad option" for any other option
DFS_FSC_OPT:
    jsr SAVE_REGISTERS                       ; keep A, X and Y for the caller
    txa
    cmp #4
    beq DFS_FSC_OPT_BOOT
    cmp #2
    bcc DFS_FSC_OPT_MESSAGES
    jsr BAD_ERROR                       ; "Bad option"
    .byte DFS_ERROR_BAD_OPTION
    .byte "option",0
DFS_FSC_OPT_MESSAGES:
    ldx #$FF                        ; off
    tya
    beq DFS_FSC_OPT_SET
    ldx #0                          ; on
DFS_FSC_OPT_SET:
    stx DFS_MESSAGES_OFF
    rts
DFS_FSC_OPT_BOOT:
    tya
    pha
    jsr SELECT_DEFAULTS
    jsr READ_CATALOGUE
    pla
    jsr SHIFT_LEFT_4                       ; the option to bits 4-5
    eor CATALOGUE_OPTION
    and #$30
    eor CATALOGUE_OPTION
    sta CATALOGUE_OPTION
    jmp WRITE_CATALOGUE

;; Raises the "Disk full" error, &C6.
DISK_FULL:
    jsr DISK_ERROR                       ; "Disk "
    .byte DFS_ERROR_DISK_FULL
    .byte "full",0

;; Makes the catalogue entry of a file about to be saved, replacing any file of that name.
;;
;; The length is the end address less the start address. The new entry is written to the disc, and the transfer is
;; set to start at the start address.
;; In: DFS_NAME_POINTER = the address of the file's name, DFS_LOAD = the load address's low bytes,
;;   DFS_EXEC = the execution address's low bytes, DFS_LENGTH = the start address's low bytes (until they are
;;   replaced by the length), DFS_TOP_BITS/DFS_START_SECTOR = the end address's low bytes, DFS_LOAD_HIGH, DFS_EXEC_HIGH,
;;   DFS_START_HIGH, DFS_END_HIGH = the high bytes of the addresses
;; Out: Y = the entry's offset, DFS_LOAD/DFS_LOAD_HIGH = the start address, the transfer's
;; Errors: &C3 = "Locked", &C2 = "Open", &BE = "Cat full", &C6 = "Disk full"
CREATE_FILE:
    jsr READ_BLOCK_NAME                       ; read the name
    jsr FIND_FIRST
    bcc CREATE_FILE_1
    jsr DELETE_ENTRY                       ; delete the old file
CREATE_FILE_1:
    lda DFS_LENGTH             ; keep the start address
    pha
    lda DFS_LENGTH+1
    pha
    sec                             ; the length, end less start
    lda DFS_TOP_BITS
    sbc DFS_LENGTH
    sta DFS_LENGTH
    lda DFS_START_SECTOR
    sbc DFS_LENGTH+1
    sta DFS_LENGTH+1
    lda DFS_END_HIGH
    sbc DFS_START_HIGH
    sta DFS_LENGTH_HIGH
    jsr MAKE_CATALOGUE_ENTRY
    lda DFS_START_HIGH+1            ; the transfer starts at the start address
    sta DFS_LOAD_HIGH+1
    lda DFS_START_HIGH
    sta DFS_LOAD_HIGH
    pla
    sta DFS_LOAD+1
    pla
    sta DFS_LOAD
    rts

;; Finds room for a file and adds its entry to the catalogue, which is then written to the disc.
;;
;; Entries are kept in order of start sector, highest first, so the gaps between files are found by walking from the
;; last entry back: first the gap between sector 2 (after the catalogue) and the last file, then the gap after each
;; file up to the next, and finally the gap after the first file up to the end of the disc. The file goes in the first
;; gap that holds it, and its entry is inserted there.
;; In: DFS_NAME = the name and directory, DFS_LOAD, DFS_EXEC, DFS_LENGTH, DFS_LENGTH_HIGH,
;;   DFS_LOAD_HIGH, DFS_EXEC_HIGH = the file's addresses and length
;; Out: Y = the entry's offset, DFS_LOAD..DFS_START_SECTOR = the entry's information, its start sector included
;; Errors: &BE = "Cat full", &C6 = "Disk full"
MAKE_CATALOGUE_ENTRY:
    lda #0                          ; the first free sector, after the catalogue
    sta DFS_TOP_BITS
    lda #2
    sta DFS_START_SECTOR
    ldy CATALOGUE_SIZE
    cpy #DFS_MAX_FILES * 8
    bcs CATALOGUE_FULL
    jsr CHECK_GAP                       ; carry set when the gap below the last file is enough
    jmp MAKE_CATALOGUE_ENTRY_CHECK
MAKE_CATALOGUE_ENTRY_NEXT:
    beq DISK_FULL                   ; no gaps left
    jsr PREVIOUS_ENTRY                       ; back one entry
    jsr CHECK_GAP_AFTER_FILE                       ; the gap after that file
MAKE_CATALOGUE_ENTRY_CHECK:
    tya
    bcc MAKE_CATALOGUE_ENTRY_NEXT
    sty NEW_ENTRY_SLOT
    ldy CATALOGUE_SIZE
MAKE_CATALOGUE_ENTRY_SHIFT:
    cpy NEW_ENTRY_SLOT              ; move the entries after the slot up by one
    beq MAKE_CATALOGUE_ENTRY_INSERT
    lda CATALOGUE_NAMES+7,y
    sta CATALOGUE_NAMES+15,y
    lda CATALOGUE_SECTORS,y
    sta CATALOGUE_SECTORS+8,y
    dey
    bcs MAKE_CATALOGUE_ENTRY_SHIFT  ; always
MAKE_CATALOGUE_ENTRY_INSERT:
    ldx #0
    jsr MAKE_MIXED_BYTE
MAKE_CATALOGUE_ENTRY_NAME:
    lda DFS_NAME,x
    sta CATALOGUE_NAMES+8,y
    iny
    inx
    cpx #8
    bne MAKE_CATALOGUE_ENTRY_NAME
MAKE_CATALOGUE_ENTRY_INFO:
    lda DFS_LOAD-1,x                ; DFS_LOAD..DFS_START_SECTOR, X counting 8 down to 1
    dey
    sta CATALOGUE_SECTORS+1,y
    dex
    bne MAKE_CATALOGUE_ENTRY_INFO
    jsr PRINT_INFO_IF_ON                       ; show it if *OPT 1 is on
    tya
    pha
    ldy CATALOGUE_SIZE
    jsr NEXT_ENTRY                       ; one more file
    sty CATALOGUE_SIZE
    jsr WRITE_CATALOGUE
    pla
    tay
    rts

;; Raises the "Cat full" error, &BE.
CATALOGUE_FULL:
    jsr DFS_ERROR
    .byte DFS_ERROR_CATALOGUE_FULL
    .byte "Cat full",0

;; Packs the high bits of a file's addresses into its catalogue entry's byte of high bits.
;;
;; The byte holds bits 16-17 of the execution address (bits 6-7), the length (4-5) and the load address (2-3), and
;; bits 8-9 of the start sector (0-1), which are already there.
;; In: DFS_EXEC_HIGH, DFS_LENGTH_HIGH, DFS_LOAD_HIGH = the high bytes, DFS_TOP_BITS = the start sector's top bits
;; Out: DFS_TOP_BITS = the byte
;; Uses: A
MAKE_MIXED_BYTE:
    lda DFS_EXEC_HIGH
    and #$03
    asl a
    asl a
    eor DFS_LENGTH_HIGH
    and #$FC
    eor DFS_LENGTH_HIGH
    asl a
    asl a
    eor DFS_LOAD_HIGH
    and #$FC
    eor DFS_LOAD_HIGH
    asl a
    asl a
    eor DFS_TOP_BITS
    and #$FC
    eor DFS_TOP_BITS
    sta DFS_TOP_BITS
    rts

;; *ENABLE: enables the next command, as *BACKUP and *DESTROY need, or they give "Not enabled".
;;
;; OSFSC 8 counts the 1 down as each command starts, so it lasts until the command after next starts.
ENABLE_COMMAND:
    lda #1
    sta DFS_ENABLE
    rts

;; Unpacks bits 16-31 of a file's load address from its catalogue entry's byte of high bits.
;;
;; Bits 2-3 of the byte are bits 16-17 of the address; 3 stands for &FFFF, the I/O processor's memory.
;; In: DFS_TOP_BITS = the byte
;; Out: DFS_LOAD_HIGH = the high bytes
;; Uses: A
UNPACK_LOAD_HIGH:
    lda #0
    sta DFS_LOAD_HIGH+1
    lda DFS_TOP_BITS
    jsr BITS_2_3                       ; bits 2-3 to 0-1
    cmp #3
    bne UNPACK_LOAD_HIGH_1
    lda #$FF
    sta DFS_LOAD_HIGH+1
UNPACK_LOAD_HIGH_1:
    sta DFS_LOAD_HIGH
    rts

;; Unpacks bits 16-31 of a file's execution address from its catalogue entry's byte of high bits.
;;
;; Bits 6-7 of the byte are bits 16-17 of the address; 3 stands for &FFFF.
;; In: DFS_TOP_BITS = the byte
;; Out: DFS_EXEC_HIGH = the high bytes
;; Uses: A
UNPACK_EXEC_HIGH:
    lda #0
    sta DFS_EXEC_HIGH+1
    lda DFS_TOP_BITS
    jsr BITS_6_7                       ; bits 6-7 to 0-1
    cmp #3
    bne UNPACK_EXEC_HIGH_1
    lda #$FF
    sta DFS_EXEC_HIGH+1
UNPACK_EXEC_HIGH_1:
    sta DFS_EXEC_HIGH
    rts

;; Makes the default directory and drive, set by *DIR and *DRIVE, the current ones.
;; Out: DFS_NAME_DIRECTORY, DFS_CURRENT_DRIVE
;; Uses: A
;; Entry: SELECT_DEFAULT_DRIVE = sets only the drive
SELECT_DEFAULTS:
    lda DFS_DEFAULT_DIRECTORY
    sta DFS_NAME_DIRECTORY
SELECT_DEFAULT_DRIVE:
    lda DFS_DEFAULT_DRIVE
    jmp SET_DRIVE                       ; the drive, once the 8271 is idle

;; Reads an optional drive number from the command line, or uses the default drive.
;;
;; A colon before the number is skipped.
;; In: TEXT_POINTER/Y = the command line
;; Out: DFS_CURRENT_DRIVE = the drive, carry = clear
;; Errors: &CD = "Bad drive"
;; Entry: READ_DRIVE_NUMBER = the number must be there
READ_DRIVE_ARGUMENT:
    jsr START_STRING
    beq SELECT_DEFAULT_DRIVE        ; none given
READ_DRIVE_NUMBER:
    jsr READ_NAME_CHARACTER
    bcs BAD_DRIVE
    cmp #':'
    beq READ_DRIVE_NUMBER
    sec
    sbc #'0'
    bcc BAD_DRIVE
    cmp #DFS_DRIVES
    bcs BAD_DRIVE
    jsr SET_DRIVE
    clc
    rts

;; Raises the "Bad drive" error, &CD.
BAD_DRIVE:
    jsr BAD_ERROR                       ; "Bad "
    .byte DFS_ERROR_BAD_DRIVE
    .byte "drive",0

;; *RENAME: renames a file.
;;
;; Both names must be on the same drive, and the file must be unlocked and closed. The new name may be in another
;; directory. The catalogue is written back with the new name in the file's entry.
;; In: TEXT_POINTER/Y = the command's arguments, the old name and the new
;; Errors: &D6 = "Not found", &C3 = "Locked", &C2 = "Open", &CD = "Bad drive", &C4 = "Exists"
RENAME_COMMAND:
    jsr DISABLE_WILDCARDS                       ; no wildcards
    jsr REQUIRE_ARGUMENT
    jsr READ_NAME                       ; the old name
    tya
    pha
    jsr FIND_OR_ERROR                       ; find it, or "Not found"
    jsr CHECK_NOT_LOCKED_OR_OPEN                       ; "Locked" or "Open"
    sty RENAME_ENTRY
    pla
    tay
    jsr REQUIRE_ARGUMENT
    lda DFS_CURRENT_DRIVE
    pha
    jsr READ_NAME                       ; the new name
    pla
    cmp DFS_CURRENT_DRIVE
    bne BAD_DRIVE
    jsr FIND_FIRST
    bcc RENAME_COMMAND_STORE
    cpy RENAME_ENTRY                ; renaming a file to its own name is allowed
    beq RENAME_COMMAND_STORE
    jsr DFS_ERROR
    .byte DFS_ERROR_EXISTS
    .byte "Exists",0
RENAME_COMMAND_STORE:
    ldy RENAME_ENTRY
    jsr NEXT_ENTRY                       ; to the entry's end
    ldx #7
RENAME_COMMAND_LOOP:
    lda DFS_NAME,x             ; the name and directory
    sta CATALOGUE_NAMES+7,y
    dey
    dex
    bpl RENAME_COMMAND_LOOP
                                    ; and write the catalogue

;; Writes the catalogue to the current drive's disc, with its sequence number one more.
;;
;; The sequence number counts in decimal. The drive is selected and the head moved to track 0, where sectors 8 and 9 are
;; verified, which on a disc whose sectors are in order leaves the head just before sector 0, and then sectors 0 and
;; 1 are written. Each command is tried
;; up to 10 times.
;; Out: DFS_CATALOGUE_DRIVE = the drive
;; Errors: &C9 = "Disk read only", &C7 = "Disk fault" or "Drive fault", &11 = "Escape"
WRITE_CATALOGUE:
    clc
    sed
    lda CATALOGUE_SEQUENCE
    adc #1
    cld
    sta CATALOGUE_SEQUENCE
    jsr PREPARE_CATALOGUE_TRANSFER
    jsr RESET_RETRIES
WRITE_CATALOGUE_VERIFY:
    ldy #FDC_VERIFY_SECTORS_8_9 - FDC_SEQUENCES
    dec DFS_RETRIES
    bmi DISC_ERROR
    jsr FDC_EXECUTE_SEQUENCE
    bne WRITE_CATALOGUE_VERIFY
    jsr PREPARE_WRITE_NMI
    bne START_CATALOGUE_TRANSFER    ; always

;; Reads a drive number from the command line, then makes sure the catalogue in memory is that drive's.
;; In: TEXT_POINTER/Y = the command line
;; Errors: &CD = "Bad drive", and those of <READ_CATALOGUE>
READ_DRIVE_AND_CATALOGUE:
    jsr READ_DRIVE_ARGUMENT

;; Makes sure the catalogue in memory is the current drive's, reading it if it may not be.
;;
;; The catalogue is kept when it came from this drive and the drive is still ready; a drive that is not ready may have
;; had its disc changed.
;; In: DFS_CURRENT_DRIVE = the drive
;; Errors: those of <READ_CATALOGUE>
ENSURE_CATALOGUE:
    jsr CHECK_DRIVE_READY
    beq READ_CATALOGUE
    lda DFS_CATALOGUE_DRIVE
    cmp DFS_CURRENT_DRIVE
    beq CHECK_DRIVE_READY_DONE

;; Reads the current drive's catalogue, sectors 0 and 1 of track 0, into &0E00-&0FFF.
;; In: DFS_CURRENT_DRIVE = the drive
;; Out: DFS_CATALOGUE_DRIVE = the drive
;; Errors: &C7 = "Disk fault" or "Drive fault", &11 = "Escape"
;; Entry: START_CATALOGUE_TRANSFER = starts the command <PREPARE_TRANSFER> set up, and waits for it
READ_CATALOGUE:
    jsr PREPARE_CATALOGUE_TRANSFER
    jsr PREPARE_READ_NMI
START_CATALOGUE_TRANSFER:
    lda #0
    sta DFS_TUBE_ADDRESS+1
    sta DFS_TUBE_TRANSFER           ; the catalogue is in this machine's memory
    jsr ISSUE_TRANSFER
    lda DFS_CURRENT_DRIVE
    sta DFS_CATALOGUE_DRIVE
    jmp WAIT_AND_RELEASE_NMI                       ; wait for the 8271, then release the NMI

;; Reads the current drive's status from the 8271, and returns whether it is ready.
;;
;; Reading the status also clears the 8271's latched not ready condition.
;; In: DFS_CURRENT_DRIVE = the drive
;; Out: A = <FDC_DRIVE_READY_0> when the drive is ready, zero = clear when it is ready,
;;   carry = set for drives 1 and 3
;; Uses: A
CHECK_DRIVE_READY:
    lda #FDC_SELECT_0 | FDC_READ_DRIVE_STATUS
    jsr FDC_SEND_DRIVE_COMMAND
    jsr FDC_READ_RESULT
    bcc CHECK_DRIVE_READY_1
    jsr SHIFT_RIGHT_4                       ; ready 1, bit 6, to bit 2
    sec
CHECK_DRIVE_READY_1:
    and #FDC_DRIVE_READY_0
CHECK_DRIVE_READY_DONE:
    rts

;; Sends the 8271 a command and its parameters from <FDC_SEQUENCES>, without waiting for it to finish.
;;
;; The command goes through <FDC_SEND_DRIVE_COMMAND>, so its select bits are swapped for drives 1 and 3.
;; In: Y = the sequence's offset in FDC_SEQUENCES, DFS_CURRENT_DRIVE = the drive
;; Out: Y = the offset after the sequence, A = <FDC_SEQUENCE_END>, zero = set
FDC_SEND_SEQUENCE:
    lda FDC_SEQUENCES,y
    jsr FDC_SEND_DRIVE_COMMAND
    iny
FDC_SEND_SEQUENCE_LOOP:
    lda FDC_SEQUENCES,y
    iny
    cmp #FDC_SEQUENCE_END
    beq CHECK_DRIVE_READY_DONE
    jsr FDC_SEND_PARAMETER
    jmp FDC_SEND_SEQUENCE_LOOP

;; Selects the current drive and moves its head to track 0, ready to transfer the catalogue.
;; In: DFS_CURRENT_DRIVE = the drive
;; Errors: those of <SELECT_DRIVE> and <SEEK_TRACK_0>
PREPARE_CATALOGUE_TRANSFER:
    jsr SELECT_DRIVE

;; Moves the current drive's head to track 0, and sets the transfer to two sectors from sector 0 of track 0.
;;
;; The NMI handler is the RTI alone, as a seek moves no data. The count is 512 bytes, the catalogue's two sectors.
;; In: DFS_CURRENT_DRIVE = the drive
;; Out: DFS_TRACK, DFS_SECTOR = 0, DFS_TRANSFER_COUNT = 512 bytes, zero = set
;; Errors: those of <DISC_ERROR>
SEEK_TRACK_0:
    lda #DFS_NMI_NONE
    jsr SET_UP_NMI_CODE                       ; claim the NMI and copy the handler
    ldy #0
    sty DFS_TRACK
    sty DFS_SECTOR
    sty DFS_TRANSFER_COUNT          ; 0, 2, 1: 512 bytes
    iny
    sty DFS_TRANSFER_COUNT+2
    iny
    sty DFS_TRANSFER_COUNT+1
    ldy #FDC_SEEK_TRACK_0 - FDC_SEQUENCES
    jsr FDC_EXECUTE_SEQUENCE
    beq CHECK_DRIVE_READY_DONE

;; Raises the error for an 8271 command that failed.
;;
;; The NMI and the Tube are released first. A write protected disc gives "Disk read only". The recoverable errors and
;; sector not found give "Disk fault", and the other results, such as a drive not ready, late DMA, track 0 not found
;; and write fault, reset the 8271 and give "Drive fault". Both faults add the result, the track and the sector, as in
;; "Disk fault 18 at 00/09", the sector read from the 8271's scan sector register.
;;
;; A transfer that runs out of tries raises this from inside the NMI (<TRANSFER_INTERRUPT>).
;; In: A = the 8271's result
;; Errors: &C9 = "Disk read only", &C7 = "Disk fault" or "Drive fault"
DISC_ERROR:
    jsr RELEASE_NMI_AND_TUBE                       ; release the NMI and the Tube
    cmp #FDC_RESULT_WRITE_PROTECT
    bne DISC_ERROR_FAULT
    jsr DISK_ERROR                       ; "Disk "
    .byte DFS_ERROR_DISK_READ_ONLY
    .byte "read only",0
DISC_ERROR_FAULT:
    pha
    cmp #FDC_RESULT_LATE_DMA
    beq DRIVE_FAULT
    and #$0F                        ; without the deleted data bit and the type's high bit
    cmp #FDC_RESULT_TYPE_LOW
    bcc DRIVE_FAULT
    jsr DISK_ERROR                       ; "Disk "
    .byte $00                       ; a stand-in error number, until DISC_FAULT_MESSAGE's
    bcc DISC_FAULT_MESSAGE          ; ends the text, and runs next with carry clear
DRIVE_FAULT:
    jsr RESET_FDC
    jsr DFS_ERROR
    .byte $00                       ; a stand-in error number, until DISC_FAULT_MESSAGE's
    .byte "Drive "
    nop                             ; ends the text, and runs next
DISC_FAULT_MESSAGE:
    jsr ERROR_APPEND                       ; add to the message
    .byte DFS_ERROR_FAULT
    .byte "fault "
    nop                             ; ends the text, and runs next
    pla
    jsr APPEND_FAULT_DETAILS
    jsr ERROR_APPEND                       ; raise the error
    .byte DFS_ERROR_FAULT
    .byte 0

;; Sends a drive to track 0 the first time it is used after the 8271 is reset; otherwise pauses.
;;
;; Drives 2 and 3 are the other sides of drives 0 and 1, so they share their bits of DFS_DRIVES_RECALIBRATED.
;; In: carry = set for drives 1 and 3, DFS_CURRENT_DRIVE = the drive
;; Errors: those of <SEEK_TRACK_0>
RECALIBRATE_ONCE:
    lda #$80
    bit DFS_DRIVES_RECALIBRATED
    bcs RECALIBRATE_ONCE_DRIVE_1
    bmi SETTLE_DELAY                ; drive 0 has been to track 0 already
RECALIBRATE_ONCE_MARK:
    ora DFS_DRIVES_RECALIBRATED
    sta DFS_DRIVES_RECALIBRATED
    bne SEEK_TRACK_0                ; always
RECALIBRATE_ONCE_DRIVE_1:
    bvs SETTLE_DELAY                ; drive 1 has been to track 0 already
    lsr a
    bcc RECALIBRATE_ONCE_MARK       ; always

;; Waits about 45 ms, the pause after selecting a drive that has been to track 0.
;; Keeps: A, X, Y
SETTLE_DELAY:
    jsr SAVE_REGISTERS
    ldy #70
SETTLE_DELAY_LOOP:
    dex
    bne SETTLE_DELAY_LOOP
    dey
    bne SETTLE_DELAY_LOOP
    rts

;; Selects the current drive, and waits until it is ready.
;;
;; Nothing is done when the drive is the one selected last and it is still ready. Otherwise the drive control output
;; port is set from <DRIVE_OUTPUT_VALUES> until the 8271 reads back the head loaded, the catalogue in memory is
;; forgotten, and the routine waits for the drive to be ready, with interrupts let in so that Escape can stop it. A
;; drive's first use after a reset seeks track 0; later ones pause instead (<RECALIBRATE_ONCE>).
;; In: DFS_CURRENT_DRIVE = the drive
;; Out: DFS_SELECTED_DRIVE = the drive
;; Keeps: A, X, Y
;; Errors: &11 = "Escape", and those of <SEEK_TRACK_0>
SELECT_DRIVE:
    jsr SAVE_REGISTERS
    lda DFS_CURRENT_DRIVE
    tay
    cmp DFS_SELECTED_DRIVE
    bne SELECT_DRIVE_OUTPUT
    jsr CHECK_DRIVE_READY
    bne SET_HOST_ADDRESS_DONE       ; selected and ready
SELECT_DRIVE_OUTPUT:
    sty DFS_SELECTED_DRIVE
    lda #FDC_WRITE_SPECIAL_REGISTER
    jsr FDC_SEND_COMMAND
    lda #FDC_REGISTER_DRIVE_OUTPUT
    jsr FDC_SEND_PARAMETER
    lda DRIVE_OUTPUT_VALUES,y
    jsr FDC_SEND_PARAMETER
    tya
    ror a                           ; no effect: FDC_SEND_DRIVE_COMMAND finds the drive itself
    ldy #FDC_READ_DRIVE_OUTPUT - FDC_SEQUENCES
    jsr FDC_EXECUTE_SEQUENCE
    ldy DFS_SELECTED_DRIVE
    and #FDC_OUTPUT_LOAD_HEAD
    beq SELECT_DRIVE_OUTPUT
    lda #$FF
    sta DFS_CATALOGUE_DRIVE
SELECT_DRIVE_WAIT:
    jsr CHECK_DRIVE_READY
    bne RECALIBRATE_ONCE
    php                             ; let pending interrupts in
    cli
    plp
    bit ESCAPE_FLAG
    bpl SELECT_DRIVE_WAIT
    jsr RESET_FDC                   ; and raise "Escape"

;; Acknowledges an escape and raises the "Escape" error, &11.
ESCAPE_ERROR:
    jsr DFS_ACKNOWLEDGE_ESCAPE                       ; OSBYTE &7E
    jsr BUILD_ERROR
    .byte DFS_ERROR_ESCAPE
    .byte "Escape",0

;; Resets the 8271 and programs it again, then releases the NMI and the Tube.
;; Out: X = the Tube's presence, from OSBYTE &EA: &FF with a Tube, otherwise 0
;; Uses: A, Y
RESET_FDC:
    lda #1                          ; 1 then 0 resets the 8271
    sta FDC_RESET
    tax
    dex
    stx FDC_RESET
    jsr INITIALISE_FDC
    jmp RELEASE_NMI_AND_TUBE

;; The value <SELECT_DRIVE> writes to the 8271's drive control output port for each drive, 0-3.
;;
;; Select 0 or 1 picks the drive; the data sheet's write fault reset output, bit 5, picks the disc's second side for
;; drives 2 and 3. Each loads the head.
DRIVE_OUTPUT_VALUES:
    .byte FDC_OUTPUT_SELECT_0 | FDC_OUTPUT_LOAD_HEAD                        ; drive 0
    .byte FDC_OUTPUT_SELECT_1 | FDC_OUTPUT_LOAD_HEAD                        ; drive 1
    .byte FDC_OUTPUT_SELECT_0 | FDC_OUTPUT_SIDE_1 | FDC_OUTPUT_LOAD_HEAD    ; drive 2
    .byte FDC_OUTPUT_SELECT_1 | FDC_OUTPUT_SIDE_1 | FDC_OUTPUT_LOAD_HEAD    ; drive 3

;; Sets the transfer's address to be in this machine's memory, by setting its high bytes to &FFFF.
;; Out: DFS_LOAD_HIGH = &FFFF
;; Keeps: A, X, Y
SET_HOST_ADDRESS:
    pha
    lda #$FF
    sta DFS_LOAD_HIGH
    sta DFS_LOAD_HIGH+1
    pla
SET_HOST_ADDRESS_DONE:
    rts

;; Prepares a read of sectors with the 8271's read data command, starting a Tube transfer when the address is in the
;; second processor.
;; In: DFS_LOAD, DFS_LOAD_HIGH = the address
;; Out: A = nonzero
;; Uses: X, Y
;; Entry: PREPARE_READ_NMI = without the Tube, for the catalogue
PREPARE_READ:
    lda #DFS_TUBE_WRITE
    jsr START_TUBE_TRANSFER
PREPARE_READ_NMI:
    lda #DFS_NMI_READ
    jsr SET_UP_NMI_CODE
    lda #FDC_SELECT_0 | FDC_READ_DATA
    bne PREPARE_TRANSFER            ; always

;; Prepares a write of sectors with the 8271's write data command, starting a Tube transfer when the address is in
;; the second processor.
;; In: DFS_LOAD, DFS_LOAD_HIGH = the address
;; Out: A = nonzero
;; Uses: X, Y
;; Entry: PREPARE_WRITE_NMI = without the Tube, for the catalogue
PREPARE_WRITE:
    lda #DFS_TUBE_READ
    jsr START_TUBE_TRANSFER
PREPARE_WRITE_NMI:
    lda #DFS_NMI_WRITE
    jsr SET_UP_NMI_CODE
    lda #FDC_SELECT_0 | FDC_WRITE_DATA

;; Sets the transfer's command, its address to the catalogue at &0E00, and its tries.
;;
;; Callers that transfer elsewhere set <DFS_TRANSFER_ADDRESS> afterwards.
;; In: A = the 8271 command
;; Out: A = DFS_RETRY_COUNT, zero = clear
;; Entry: RESET_RETRIES = sets only the tries
PREPARE_TRANSFER:
    sta DFS_TRANSFER_COMMAND
    lda #<CATALOGUE_NAMES
    sta DFS_TRANSFER_ADDRESS
    lda #>CATALOGUE_NAMES
    sta DFS_TRANSFER_ADDRESS+1
RESET_RETRIES:
    lda #DFS_RETRY_COUNT
    sta DFS_RETRIES
    rts

;; Starts the Tube transfer again from its beginning, for a retry.
;; Out: carry = clear when a Tube transfer was started
;; Uses: A, X, Y
RESTART_TUBE_TRANSFER:
    lda DFS_TUBE_TYPE
    pha
    lda DFS_TUBE_TRANSFER
    jmp START_TUBE_TRANSFER_1

;; Decides whether a transfer is to or from the second processor, and if so claims the Tube and starts it.
;;
;; The transfer goes across the Tube when there is a second processor and the address's high bytes are not &FFFF.
;; In: A = the Tube transfer type, DFS_LOAD = the address's low bytes, DFS_LOAD_HIGH = its high bytes
;; Out: DFS_TUBE_TRANSFER = nonzero for the Tube, DFS_TUBE_ADDRESS = the address,
;;   carry = clear when a Tube transfer was started
;; Keeps: A
;; Uses: X, Y
START_TUBE_TRANSFER:
    pha
    sta DFS_TUBE_TYPE
    lda DFS_LOAD
    sta DFS_TUBE_ADDRESS
    lda DFS_LOAD+1
    sta DFS_TUBE_ADDRESS+1
    lda DFS_LOAD_HIGH
    and DFS_LOAD_HIGH+1
    ora DFS_NO_TUBE
    eor #$FF
    sta DFS_TUBE_TRANSFER
START_TUBE_TRANSFER_1:
    sec
    beq START_TUBE_TRANSFER_DONE
    jsr DFS_CLAIM_TUBE
    ldx #<DFS_TUBE_ADDRESS
    ldy #>DFS_TUBE_ADDRESS
    pla
    pha
    jsr TUBE_ENTRY_TRANSFER                       ; start the transfer
    clc
START_TUBE_TRANSFER_DONE:
    pla
    rts

;; Claims the Tube for the DFS, waiting until it is free.
;; Keeps: A
DFS_CLAIM_TUBE:
    pha
DFS_CLAIM_TUBE_LOOP:
    lda #DFS_TUBE_CLAIM
    jsr TUBE_ENTRY_TRANSFER
    bcc DFS_CLAIM_TUBE_LOOP         ; carry set once claimed
    pla
    rts

;; Handles the end of an 8271 command during a transfer; the NMI handler calls it with this ROM paged in.
;;
;; After a good result, the transfer moves to sector 0 of the next track, the Tube address is moved on by the sectors
;; just transferred, and the next command is started if bytes are left. After an error, the command is tried again
;; from the state saved when it started, with the Tube transfer restarted, until the tries run out and the error is
;; raised from inside the NMI.
;; Keeps: X
;; Uses: A, Y
;; Errors: those of <DISC_ERROR>
TRANSFER_INTERRUPT:
    jsr FDC_READ_RESULT             ; which ends the interrupt
    bne TRANSFER_INTERRUPT_RETRY
    jsr RESET_RETRIES
    inc DFS_TRACK
    lda #0
    sta DFS_SECTOR
    lda DFS_COMMAND_SECTORS
    clc
    adc DFS_TUBE_ADDRESS+1
    sta DFS_TUBE_ADDRESS+1
    bcc ISSUE_TRANSFER
    inc DFS_TUBE_ADDRESS+2
    bne ISSUE_TRANSFER
    inc DFS_TUBE_ADDRESS+3
    bcs ISSUE_TRANSFER              ; always
TRANSFER_INTERRUPT_RETRY:
    dec DFS_RETRIES
    bpl TRANSFER_INTERRUPT_RESTORE
    jmp DISC_ERROR
TRANSFER_INTERRUPT_RESTORE:
    ldy #4
TRANSFER_INTERRUPT_RESTORE_LOOP:
    lda DFS_TRANSFER_SAVE,y
    sta a:DFS_TRANSFER_COUNT,y
    dey
    bpl TRANSFER_INTERRUPT_RESTORE_LOOP
    txa
    pha
    jsr RESTART_TUBE_TRANSFER
    pla
    tax

;; Starts the 8271 transferring the next sectors, up to the end of the current track.
;;
;; Nothing is done when the count is used up. The count and address are saved for a retry, and the command is sent
;; with the track, the sector and the number of 256-byte sectors: the rest of the track, or fewer when the count ends
;; sooner.
;; In: DFS_TRANSFER_COMMAND, DFS_TRACK, DFS_SECTOR, DFS_TRANSFER_COUNT, DFS_TRANSFER_ADDRESS, DFS_CURRENT_DRIVE
;; Out: DFS_COMMAND_SECTORS = the sectors the command moves
;; Uses: A, Y
ISSUE_TRANSFER:
    lda DFS_TRANSFER_COUNT+2
    beq FDC_SEND_PARAMETER_DONE     ; the transfer is complete
    ldy #4
ISSUE_TRANSFER_SAVE:
    lda a:DFS_TRANSFER_COUNT,y
    sta DFS_TRANSFER_SAVE,y
    dey
    bpl ISSUE_TRANSFER_SAVE
    lda DFS_TRANSFER_COMMAND
    jsr FDC_SEND_DRIVE_COMMAND
    lda DFS_TRACK
    jsr FDC_SEND_PARAMETER
    lda DFS_SECTOR
    jsr FDC_SEND_PARAMETER
    lda #DFS_SECTORS_PER_TRACK      ; the sectors left on the track
    sec
    sbc DFS_SECTOR
    sta DFS_COMMAND_SECTORS
    lda DFS_TRANSFER_COUNT+2
    cmp #1
    bne ISSUE_TRANSFER_REST_OF_TRACK ; 64K or more left
    lda DFS_TRANSFER_COUNT+1        ; the sectors left, counting a part sector
    beq ISSUE_TRANSFER_REST_OF_TRACK ; 0 stands for 256
    cmp DFS_COMMAND_SECTORS
    bcc ISSUE_TRANSFER_COUNT
ISSUE_TRANSFER_REST_OF_TRACK:
    lda DFS_COMMAND_SECTORS
ISSUE_TRANSFER_COUNT:
    ora #FDC_SECTOR_256

;; Writes a parameter to the 8271, once its parameter register is empty.
;; In: A = the parameter
;; Uses: A
FDC_SEND_PARAMETER:
    pha
FDC_SEND_PARAMETER_WAIT:
    lda FDC_STATUS
    and #FDC_STATUS_PARAMETER_FULL
    bne FDC_SEND_PARAMETER_WAIT
    pla
    sta FDC_PARAMETER
FDC_SEND_PARAMETER_DONE:
    rts

;; Writes a command to the 8271 for the current drive, written for drive 0 and changed for the others.
;;
;; For drives 1 and 3 both select bits are swapped, so select 0 becomes select 1; a command with neither select bit,
;; as specify and the special registers have, goes with both set.
;; In: A = the command, with select 0, DFS_CURRENT_DRIVE = the drive
;; Out: carry = set for drives 1 and 3
;; Uses: A
;; Entry: FDC_SEND_COMMAND = writes the command as it is
FDC_SEND_DRIVE_COMMAND:
    pha
    lda DFS_CURRENT_DRIVE
    ror a
    pla
    bcc FDC_SEND_COMMAND
    eor #FDC_SELECT_0 | FDC_SELECT_1
FDC_SEND_COMMAND:
    bit FDC_STATUS                  ; wait while the 8271 is busy
    bmi FDC_SEND_COMMAND
    sta FDC_COMMAND
    rts

;; Sends a sequence from <FDC_SEQUENCES> and waits for its result.
;; In: Y = the sequence's offset in FDC_SEQUENCES, DFS_CURRENT_DRIVE = the drive
;; Out: A = the 8271's result, zero = set for success, Y = the offset after the sequence
;; Entry: FDC_READ_RESULT = only waits and reads the result
FDC_EXECUTE_SEQUENCE:
    jsr FDC_SEND_SEQUENCE
FDC_READ_RESULT:
    jsr FDC_WAIT_IDLE
    lda FDC_RESULT
    rts

;; Waits until the 8271 is idle.
;;
;; The status is read twice: one read could find the 8271 idle in the moment between one track's command ending and
;; the NMI handler starting the next.
;; Keeps: A, X, Y
FDC_WAIT_IDLE:
    bit FDC_STATUS
    bmi FDC_WAIT_IDLE
    bit FDC_STATUS
    bmi FDC_WAIT_IDLE
    rts

;; Programs the 8271 after a reset: the drives' timing, no bad tracks and the non-DMA mode.
;;
;; The timing is one of four sequences, chosen by bits 4-5 of the start-up options, keyboard links 3 and 4. The drives
;; must then seek track 0 again.
;; Out: X = 0, DFS_DRIVES_RECALIBRATED = 0
;; Uses: A, Y
INITIALISE_FDC:
    jsr READ_STARTUP_OPTIONS                       ; OSBYTE &FF, the start-up options in X
    txa
    and #$30
    lsr a                           ; 6 times bits 4-5, a timing sequence's offset
    lsr a
    sta FS_SCRATCH
    lsr a
    adc FS_SCRATCH
    tay
    jsr FDC_SEND_SEQUENCE
    ldy #FDC_BAD_TRACKS_0 - FDC_SEQUENCES
    ldx #3                          ; both surfaces' bad tracks, then the mode
INITIALISE_FDC_LOOP:
    jsr FDC_SEND_SEQUENCE
    dex
    bne INITIALISE_FDC_LOOP
    stx DFS_DRIVES_RECALIBRATED
    rts

;; Lays out a specify initialisation sequence for <FDC_SEQUENCES>.
;;
;; The BBC Micro's 8271 counts in the data sheet's units for mini-floppies: 2 ms for the step rate and the settling
;; time, and 8 ms for the head load time.
;; Parameters:
;;   step = the step rate, in 2 ms
;;   settle = the head settling time, in 2 ms
;;   unload = the revolutions before the head unloads
;;   load = the head load time, in 8 ms
.macro SPECIFY_TIMING step, settle, unload, load
    .byte FDC_SPECIFY, FDC_SPECIFY_INITIALISATION, step, settle, unload << 4 | load, FDC_SEQUENCE_END
.endmacro

;; The 8271 command sequences: each a command, its parameters, and FDC_SEQUENCE_END.
;;
;; Routines take a sequence by its offset in the table. Commands written with select 0 are for drive 0, and
;; <FDC_SEND_DRIVE_COMMAND> changes them for the current drive. The four timing sequences match the four rows of the
;; user guides' table of links 3 and 4: steps of 4, 6, 6 and 24 ms, settling of 16, 16, 16 and 20 ms, and head loads
;; of 0, 0, 56 and 64 ms.
;; See: <FDC_SEND_SEQUENCE>, <FDC_EXECUTE_SEQUENCE>, <INITIALISE_FDC>
FDC_SEQUENCES:
    SPECIFY_TIMING 2, 8, 12, 0
    SPECIFY_TIMING 3, 8, 12, 0
    SPECIFY_TIMING 3, 8, 12, 7
    SPECIFY_TIMING 12, 10, 12, 8
FDC_BAD_TRACKS_0:                   ; surface 0: no bad tracks, at track 0
    .byte FDC_SPECIFY, FDC_SPECIFY_BAD_TRACKS_0, $FF, $FF, 0, FDC_SEQUENCE_END
FDC_BAD_TRACKS_1:                   ; surface 1: no bad tracks, at track 0
    .byte FDC_SPECIFY, FDC_SPECIFY_BAD_TRACKS_1, $FF, $FF, 0, FDC_SEQUENCE_END
FDC_SET_MODE:                       ; the mode register: non-DMA
    .byte FDC_WRITE_SPECIAL_REGISTER, FDC_REGISTER_MODE, FDC_MODE_NON_DMA, FDC_SEQUENCE_END
FDC_SEEK_TRACK_0:                   ; seek track 0
    .byte FDC_SELECT_0 | FDC_SEEK, 0, FDC_SEQUENCE_END
FDC_VERIFY_SECTORS_8_9:             ; verify track 0, sectors 8 and 9
    .byte FDC_SELECT_0 | FDC_VERIFY, 0, 8, FDC_SECTOR_256 | 2, FDC_SEQUENCE_END
FDC_READ_SCAN_SECTOR:               ; read the scan sector register, the sector an error stopped at
    .byte FDC_READ_SPECIAL_REGISTER, FDC_REGISTER_SCAN_SECTOR, FDC_SEQUENCE_END
FDC_READ_DRIVE_OUTPUT:              ; read the drive control output port
    .byte FDC_SELECT_0 | FDC_READ_SPECIAL_REGISTER, FDC_REGISTER_DRIVE_OUTPUT, FDC_SEQUENCE_END
    .assert FDC_BAD_TRACKS_0 - FDC_SEQUENCES = 4 * 6, "INITIALISE_FDC takes the timing sequences as 6 bytes each."
    .assert FDC_SET_MODE - FDC_BAD_TRACKS_1 = FDC_BAD_TRACKS_1 - FDC_BAD_TRACKS_0, "The three follow each other."

;; The patch <SET_UP_NMI_CODE> copies over &0D0A-&0D1C of <DFS_NMI_TRANSFER_CODE> to make it write instead of read.
;;
;; At each data request it sends the 8271 the next byte, from the Tube's register 3 or from memory. It has no check of
;; the count: the 8271 asks for whole sectors, and gets the bytes after the count to the end of the last one too. The
;; memory path ends at the handler's next instruction, which moves the address on; the Tube path jumps to its count.
DFS_NMI_WRITE_PATCH:
    .logicalorg $0D0A
DFS_NMI_WRITE_START:
    ldy DFS_TUBE_TRANSFER
    beq DFS_NMI_WRITE_FROM_MEMORY        ; Y is then 0 for the indexed load
    lda TUBE_R3_DATA                ; the next byte from the second processor
    sta FDC_DATA                    ; to the 8271
    jmp DFS_NMI_COUNT
DFS_NMI_WRITE_FROM_MEMORY:
    lda (DFS_TRANSFER_ADDRESS),y
    sta FDC_DATA                    ; to the 8271
DFS_NMI_WRITE_END:
    .logicalorg
    .assert DFS_NMI_WRITE_START = DFS_NMI_DATA, "The patch replaces the handler from its data read."
    .assert DFS_NMI_WRITE_END = DFS_NMI_ADVANCE, "The patch ends where the handler moves the address on."
    .assert DFS_NMI_TRANSFER_CODE - DFS_NMI_WRITE_PATCH = $13, "SET_UP_NMI_CODE copies the patch as 19 bytes."

;; The NMI handler for the DFS's transfers, which <SET_UP_NMI_CODE> copies to &0D00 for reads (and, with
;; <DFS_NMI_WRITE_PATCH>, for writes).
;;
;; At each data request it takes a byte from the 8271 and passes it to the Tube's register 3 or stores it in memory,
;; dropping it once the count is used up, and counts it. When the 8271 interrupts at the end of a command, it pages
;; in this ROM, whose number SET_UP_NMI_CODE writes into the code, and calls <TRANSFER_INTERRUPT> to start the next
;; track or retry. Only A and Y are kept, so the routines it calls keep X.
;;
;; The count is three bytes, low first, decremented as one number with the middle and high bytes counting from 1: it
;; is used up when the high byte reaches 0. The RTI at its end is also copied alone, as the handler for commands that
;; move no data.
DFS_NMI_TRANSFER_CODE:
    .logicalorg $0D00
;; Inherit: <DFS_NMI_TRANSFER_CODE>
DFS_NMI_TRANSFER:
    pha
    tya
    pha
    lda FDC_STATUS
    and #FDC_STATUS_DATA_REQUEST
    beq DFS_NMI_INTERRUPT
DFS_NMI_DATA:
    lda FDC_DATA                    ; the byte from the 8271
    ldy DFS_TRANSFER_COUNT+2
    beq DFS_NMI_RETURN              ; past the count: drop it
    ldy DFS_TUBE_TRANSFER
    beq DFS_NMI_STORE               ; Y is then 0 for the indexed store
    sta TUBE_R3_DATA                ; to the second processor
    bne DFS_NMI_COUNT               ; always
DFS_NMI_STORE:
    sta (DFS_TRANSFER_ADDRESS),y
DFS_NMI_ADVANCE:
    inc DFS_TRANSFER_ADDRESS
    bne DFS_NMI_COUNT
    inc DFS_TRANSFER_ADDRESS+1
DFS_NMI_COUNT:
    dec DFS_TRANSFER_COUNT
    bne DFS_NMI_RETURN
    dec DFS_TRANSFER_COUNT+1
    bne DFS_NMI_RETURN
    dec DFS_TRANSFER_COUNT+2
DFS_NMI_RETURN:
    pla
    tay
    pla
DFS_NMI_RTI:
    rti
DFS_NMI_INTERRUPT:
    lda FDC_STATUS
    and #FDC_STATUS_INTERRUPT
    beq DFS_NMI_RETURN
    lda ROMSEL_COPY
    pha
DFS_NMI_PAGE_IN:
    lda #$00                        ; this ROM's number, which SET_UP_NMI_CODE writes over the zero
    sta ROMSEL_COPY
    sta ROMSEL
    jsr TRANSFER_INTERRUPT
    pla
    sta ROMSEL_COPY                 ; page back the ROM that was in
    sta ROMSEL
    sec
    bcs DFS_NMI_RETURN              ; always
    .logicalorg
DFS_NMI_ROM_NUMBER = DFS_NMI_PAGE_IN + 1 ;; the operand SET_UP_NMI_CODE sets to this ROM's number
DFS_NMI_NONE_CODE = DFS_NMI_TRANSFER_CODE + DFS_NMI_RTI - NMI_ROUTINE ;; the RTI, which SET_UP_NMI_CODE copies alone
    .assert DFS_NMI_ROM_NUMBER = NMI_ROUTINE + 60, "SET_UP_NMI_CODE writes the ROM number at &0D3C."
    .assert DFS_NMI_READ_MEMORY_CODE - DFS_NMI_TRANSFER_CODE = $4E, "SET_UP_NMI_CODE copies the handler as 78 bytes."

;; An NMI handler, copied to &0D00 by <SET_UP_NMI_CODE>, that reads bytes from the 8271 into memory.
;;
;; It has no count: the 8271's command decides how many bytes come, and the end of the command is left to the
;; foreground. It and the three after it are for OSWORD &7F, whose caller gives the 8271 its command.
DFS_NMI_READ_MEMORY_CODE:
    .logicalorg $0D00
    pha
    tya
    pha
    lda FDC_STATUS
    and #FDC_STATUS_DATA_REQUEST
    beq DFS_NMI_READ_MEMORY_RETURN
    lda FDC_DATA
    ldy #0
    sta (DFS_TRANSFER_ADDRESS),y
    inc DFS_TRANSFER_ADDRESS
    bne DFS_NMI_READ_MEMORY_RETURN
    inc DFS_TRANSFER_ADDRESS+1
DFS_NMI_READ_MEMORY_RETURN:
    pla
    tay
    pla
    rti
    .logicalorg

;; An NMI handler, copied to &0D00 by <SET_UP_NMI_CODE>, that writes bytes from memory to the 8271.
;;
;; Like <DFS_NMI_READ_MEMORY_CODE>, it leaves the count and the end of the command to the 8271 and the foreground.
DFS_NMI_WRITE_MEMORY_CODE:
    .logicalorg $0D00
    pha
    tya
    pha
    lda FDC_STATUS
    and #FDC_STATUS_DATA_REQUEST
    beq DFS_NMI_WRITE_MEMORY_RETURN
    ldy #0
    lda (DFS_TRANSFER_ADDRESS),y
    sta FDC_DATA
    inc DFS_TRANSFER_ADDRESS
    bne DFS_NMI_WRITE_MEMORY_RETURN
    inc DFS_TRANSFER_ADDRESS+1
DFS_NMI_WRITE_MEMORY_RETURN:
    pla
    tay
    pla
    rti
    .logicalorg

;; An NMI handler, copied to &0D00 by <SET_UP_NMI_CODE>, that passes bytes from the 8271 to the Tube's register 3.
;;
;; Like <DFS_NMI_READ_MEMORY_CODE>, it leaves the count and the end of the command to the 8271 and the foreground.
DFS_NMI_READ_TUBE_CODE:
    .logicalorg $0D00
    pha
    lda FDC_STATUS
    and #FDC_STATUS_DATA_REQUEST
    beq DFS_NMI_READ_TUBE_RETURN
    lda FDC_DATA
    sta TUBE_R3_DATA                ; to the second processor
DFS_NMI_READ_TUBE_RETURN:
    pla
    rti
    .logicalorg

;; An NMI handler, copied to &0D00 by <SET_UP_NMI_CODE>, that passes bytes from the Tube's register 3 to the 8271.
;;
;; Like <DFS_NMI_READ_MEMORY_CODE>, it leaves the count and the end of the command to the 8271 and the foreground.
DFS_NMI_WRITE_TUBE_CODE:
    .logicalorg $0D00
    pha
    lda FDC_STATUS
    and #FDC_STATUS_DATA_REQUEST
    beq DFS_NMI_WRITE_TUBE_RETURN
    lda TUBE_R3_DATA                ; from the second processor
    sta FDC_DATA
DFS_NMI_WRITE_TUBE_RETURN:
    pla
    rti
    .logicalorg

;; Adds an 8271 result, the track and the sector to an error message, as "18 at 00/09", in hexadecimal.
;;
;; The sector is the 8271's scan sector register, where a failing multi-sector command stopped.
;; In: A = the result, X = the message's length at STACK
;; Out: X = the new length
;; Uses: A, Y
APPEND_FAULT_DETAILS:
    jsr APPEND_HEX_BYTE
    jsr ERROR_APPEND                       ; add to the message
    .byte $00                       ; replaces the error number, which the caller sets again
    .byte " at "
    lda DFS_TRACK                   ; ends the text, and runs next
    jsr APPEND_HEX_BYTE
    jsr ERROR_APPEND                       ; add to the message
    .byte $00                       ; the error number again
    .byte "/"
    ldy #FDC_READ_SCAN_SECTOR - FDC_SEQUENCES ; ends the text, and runs next
    jsr FDC_EXECUTE_SEQUENCE

;; Adds a byte to an error message as two hexadecimal digits.
;; In: A = the byte, X = the message's length at STACK
;; Out: X = the new length
;; Uses: A
APPEND_HEX_BYTE:
    pha
    jsr SHIFT_RIGHT_4                       ; the high digit
    jsr HEX_DIGIT
    sta STACK,x
    inx
    pla
    jsr HEX_DIGIT
    sta STACK,x
    inx
    rts

;; OSFSC 7: gives the range of file handles the DFS uses.
;; Out: X = &11, the lowest, Y = &15, the highest
DFS_FSC_HANDLE_RANGE:
    ldx #DFS_FIRST_HANDLE
    ldy #DFS_LAST_HANDLE
DFS_FSC_HANDLE_RANGE_DONE:
    rts

;; OSFSC 6: another filing system is taking over; closes the *SPOOL and *EXEC files.
;; Keeps: A, X, Y
DFS_FSC_NEW_FILING_SYSTEM:
    jsr SAVE_REGISTERS
    lda #DFS_OSBYTE_CLOSE_SPOOL_EXEC
    jmp OSBYTE

;; Closes the *SPOOL and *EXEC files and then every channel.
;; Out: A = 0
;; Uses: X, Y
CLOSE_ALL_FILES:
    jsr DFS_FSC_NEW_FILING_SYSTEM

;; Closes every channel, updating their files' entries as DFS_CLOSE_MODE allows.
;;
;; It tries each offset from &20 to &E0; those that are not open channels are passed over.
;; Out: A = 0
;; Uses: X, Y
CLOSE_ALL_CHANNELS:
    lda #0
CLOSE_ALL_CHANNELS_LOOP:
    clc
    adc #DFS_CHANNEL_SIZE
    beq DFS_FSC_HANDLE_RANGE_DONE
    tay
    jsr CLOSE_CHANNEL
    bne CLOSE_ALL_CHANNELS_LOOP     ; always

;; Closes a file, or all files, putting each one's length in the catalogue if it has changed.
;; In: Y = the handle, or 0 for all files and the *SPOOL and *EXEC files
;; Uses: A, X, Y
;; Errors: &DE = "Channel", and those of <CLOSE_CHANNEL>
CLOSE_FILE:
    lda #DFS_CHANNEL_EXTENT_CHANGED
    sta DFS_CLOSE_MODE
    tya
    beq CLOSE_ALL_FILES
    jsr FIND_CHANNEL                       ; the channel's offset, or "Channel"

;; Closes the channel at an offset, if it is open.
;;
;; Its bit in DFS_OPEN_CHANNELS is cleared. When EXT has changed and DFS_CLOSE_MODE allows, the file's entry is found
;; again and its length set from EXT, and the catalogue is written; a changed buffer is written back.
;; In: Y = the channel's offset in DFS_CHANNELS, DFS_CLOSE_MODE = DFS_CHANNEL_EXTENT_CHANGED to update the length
;; Keeps: A, X
;; Uses: Y
;; Errors: &C8 = "Disk changed" when the file is no longer on the disc, and those of <WRITE_CATALOGUE>
CLOSE_CHANNEL:
    pha
    jsr CHECK_CHANNEL_OPEN                       ; carry clear when open, X kept in DFS_SAVED_X
    bcs CLOSE_CHANNEL_DONE
    lda DFS_CHANNELS+DFS_CHANNEL_BIT,y
    eor #$FF
    and DFS_OPEN_CHANNELS
    sta DFS_OPEN_CHANNELS
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    and #DFS_CHANNEL_EXTENT_CHANGED | DFS_BUFFER_CHANGED
    beq CLOSE_CHANNEL_DONE          ; nothing to write
    jsr FIND_CHANNEL_FILE
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    and DFS_CLOSE_MODE
    beq CLOSE_CHANNEL_FLUSH
    ldx DFS_CHANNEL_ENTRY           ; the length from EXT
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT,y
    sta CATALOGUE_SECTORS+5,x
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+1,y
    sta CATALOGUE_SECTORS+6,x
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+2,y
    jsr SHIFT_LEFT_4                       ; to bits 4-5
    eor CATALOGUE_SECTORS+7,x
    and #$30
    eor CATALOGUE_SECTORS+7,x
    sta CATALOGUE_SECTORS+7,x
    jsr WRITE_CATALOGUE
    ldy DFS_CHANNEL
CLOSE_CHANNEL_FLUSH:
    jsr SAVE_BUFFER                       ; write the buffer if it changed
CLOSE_CHANNEL_DONE:
    ldx DFS_SAVED_X
    pla
    rts

;; Finds the entry in the catalogue of an open channel's file, on the channel's drive.
;; In: Y = the channel's offset in DFS_CHANNELS, which is also in DFS_CHANNEL
;; Out: DFS_CHANNEL_ENTRY = the entry's offset, Y = the channel's offset,
;;   DFS_CURRENT_DRIVE, DFS_NAME_DIRECTORY = the file's
;; Uses: A, X
;; Errors: &C8 = "Disk changed" when the file is not found
;; Entry: FIND_CHANNEL_FILE_NAME = on the current drive, with DFS_NAME_DIRECTORY already set
FIND_CHANNEL_FILE:
    jsr SELECT_CHANNEL_DRIVE
FIND_CHANNEL_FILE_NAME:
    ldx #6
FIND_CHANNEL_FILE_LOOP:
    lda DFS_CHANNELS+DFS_CHANNEL_READ_ONLY,y ; the name's characters, every other byte, from the last
    sta DFS_NAME,x
    dey
    dey
    dex
    bpl FIND_CHANNEL_FILE_LOOP
    jsr FIND_NAMED_FILE                       ; find the name, carry set when found
    bcc DISK_CHANGED
    sty DFS_CHANNEL_ENTRY
    ldy DFS_CHANNEL
FIND_CHANNEL_FILE_DONE:
    rts

;; Makes an open channel's directory and drive the current ones.
;; In: Y = the channel's offset in DFS_CHANNELS
;; Out: DFS_NAME_DIRECTORY, DFS_CURRENT_DRIVE
;; Uses: A
SELECT_CHANNEL_DRIVE:
    lda DFS_CHANNELS+DFS_CHANNEL_DIRECTORY,y
    and #$7F
    sta DFS_NAME_DIRECTORY
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    jmp SET_DRIVE                       ; bits 0-1, the drive

;; Checks that the disc has not been changed, by reading its catalogue again and comparing the sequence numbers.
;; Keeps: A, X, Y
;; Errors: &C8 = "Disk changed"
CHECK_DISC_UNCHANGED:
    jsr SAVE_REGISTERS
    lda CATALOGUE_SEQUENCE
    jsr FETCH_CATALOGUE                       ; read the catalogue
    cmp CATALOGUE_SEQUENCE
    beq FIND_CHANNEL_FILE_DONE

;; Raises the "Disk changed" error, &C8.
DISK_CHANGED:
    jsr DISK_ERROR                       ; "Disk "
    .byte DFS_ERROR_DISK_CHANGED
    .byte "changed",0

;; The DFS's OSFIND: opens a file and returns its handle, or closes a file or all files.
;;
;; A file may be open on several channels for input, but on only one for output or update. Opening for output a file
;; that does not exist makes one with room for 16K (64 sectors), and opening one that does exist keeps its place on the
;; disc; either way it starts empty. A file opened for input is marked read only on its channel.
;; In: A = 0 to close, &40 to open for input, &80 for output or &C0 for update, X/Y = the address of the file's
;;   name when opening, Y = the handle when closing, 0 for all files
;; Out: A = the handle, &11-&15, or 0 when a file to open for input or update is not found
;; Keeps: X, Y
;; Errors: &C0 = "Too many open", &C2 = "Open", &C3 = "Locked", &BE = "Cat full", &C6 = "Disk full",
;;   &DE = "Channel", &C8 = "Disk changed"
DFS_OSFIND:
    and #$C0
    bne DFS_OSFIND_OPEN
    jsr SAVE_REGISTERS                       ; keep A, X and Y
    jmp CLOSE_FILE
DFS_OSFIND_OPEN:
    jsr SAVE_X_Y                       ; keep X and Y, and return A
    stx DFS_NAME_POINTER
    sty DFS_NAME_POINTER+1
    sta OSFIND_MODE
    bit OSFIND_MODE                 ; bit 7 for output and update, bit 6 for input and update
    php
    jsr READ_BLOCK_NAME                       ; read the name
    jsr DISABLE_WILDCARDS                       ; no wildcards
    jsr FIND_FIRST
    bcs DFS_OSFIND_FOUND
    plp
    bvc DFS_OSFIND_CREATE           ; output: make the file
    lda #0                          ; input or update: no handle
    rts
DFS_OSFIND_CREATE:
    php
    lda #0                          ; no addresses, and a length of &4000
    ldx #7
DFS_OSFIND_CLEAR:
    sta DFS_LOAD,x
    sta DFS_LOAD_HIGH,x
    dex
    bpl DFS_OSFIND_CLEAR
    lda #$40
    sta DFS_START_SECTOR             ; the end address, &4000
    jsr CREATE_FILE
DFS_OSFIND_FOUND:
    plp
    php
    bvs DFS_OSFIND_SEARCH
    jsr CHECK_NOT_LOCKED                       ; output: "Locked" if it is locked
DFS_OSFIND_SEARCH:
    jsr FIND_OPEN_CHANNEL
    bcc DFS_OSFIND_ALLOCATE
DFS_OSFIND_ALREADY_OPEN:
    lda DFS_CHANNELS+DFS_CHANNEL_READ_ONLY,y
    bpl FILE_OPEN_ERROR             ; open for output or update
    bit OSFIND_MODE
    bmi FILE_OPEN_ERROR             ; open for input, but this is for output or update
    jsr CONTINUE_CHANNEL_SEARCH
    bcs DFS_OSFIND_ALREADY_OPEN
DFS_OSFIND_ALLOCATE:
    ldy DFS_CHANNEL
    bne DFS_OSFIND_FILL
    jsr DFS_ERROR
    .byte DFS_ERROR_TOO_MANY_OPEN
    .byte "Too many open",0

;; Raises the "Open" error, &C2.
FILE_OPEN_ERROR:
    jsr DFS_ERROR
    .byte DFS_ERROR_OPEN
    .byte "Open",0

DFS_OSFIND_FILL:
    lda #8
    sta DFS_COPY_COUNT
DFS_OSFIND_COPY:
    lda CATALOGUE_NAMES+8,x         ; the entry's name and information, interleaved
    sta DFS_CHANNELS,y
    iny
    lda CATALOGUE_SECTORS+1,x
    sta DFS_CHANNELS,y
    iny
    inx
    dec DFS_COPY_COUNT
    bne DFS_OSFIND_COPY
    ldx #16
    lda #0
DFS_OSFIND_ZERO:
    sta DFS_CHANNELS,y              ; PTR, EXT, the flags and the rest
    iny
    dex
    bne DFS_OSFIND_ZERO
    lda DFS_CHANNEL
    tay
    jsr SHIFT_RIGHT_5                       ; the channel's number, 1-5
    adc #$11                        ; its buffer's page, &12-&16
    sta DFS_CHANNELS+DFS_CHANNEL_BUFFER,y
    lda DFS_FREE_CHANNEL_BIT
    sta DFS_CHANNELS+DFS_CHANNEL_BIT,y
    ora DFS_OPEN_CHANNELS
    sta DFS_OPEN_CHANNELS
    lda DFS_CHANNELS+9,y            ; carry is clear: carry = the length's low byte is not 0
    adc #$FF
    lda DFS_CHANNELS+11,y           ; the length in sectors, rounded up
    adc #0
    sta DFS_CHANNELS+DFS_CHANNEL_SPACE+1,y
    lda DFS_CHANNELS+DFS_CHANNEL_MIXED,y
    ora #$0F                        ; a carry goes into bit 4, the length's bit 16
    adc #0
    jsr BITS_4_5                       ; bits 4-5 to 0-1
    sta DFS_CHANNELS+DFS_CHANNEL_SPACE+2,y
    plp
    bvc DFS_OSFIND_OUTPUT
    bmi DFS_OSFIND_EXTENT           ; update
    lda #$80                        ; input: read only
    ora DFS_CHANNELS+DFS_CHANNEL_READ_ONLY,y
    sta DFS_CHANNELS+DFS_CHANNEL_READ_ONLY,y
DFS_OSFIND_EXTENT:
    lda DFS_CHANNELS+9,y            ; EXT is the file's length
    sta DFS_CHANNELS+DFS_CHANNEL_EXTENT,y
    lda DFS_CHANNELS+11,y
    sta DFS_CHANNELS+DFS_CHANNEL_EXTENT+1,y
    lda DFS_CHANNELS+DFS_CHANNEL_MIXED,y
    jsr BITS_4_5
    sta DFS_CHANNELS+DFS_CHANNEL_EXTENT+2,y
DFS_OSFIND_DRIVE:
    lda DFS_CURRENT_DRIVE
    ora DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    sta DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    tya
    jsr SHIFT_RIGHT_5
    ora #$10                        ; the handle, &11-&15
    rts
DFS_OSFIND_OUTPUT:
    lda #DFS_CHANNEL_EXTENT_CHANGED ; EXT is 0
    sta DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    bne DFS_OSFIND_DRIVE            ; always

;; Goes on looking for another channel that has the same file open, after <FIND_OPEN_CHANNEL> found one.
;; Inherit: <FIND_OPEN_CHANNEL> Out
;; In: X = the file's offset in the catalogue, CHANNEL_SEARCH_OFFSET, CHANNEL_SEARCH_BIT = the channel found
CONTINUE_CHANNEL_SEARCH:
    txa
    pha
    jmp FIND_OPEN_CHANNEL_SKIP

;; Looks for a channel that has a file open, and notes a free channel on the way.
;;
;; The channels are looked at from &11A0 down to &1120; a channel matches when it is on the current drive and its name
;; and directory match the entry's, ignoring bit 7.
;; In: Y = the file's offset in the catalogue, DFS_CURRENT_DRIVE = the drive
;; Out: carry = set when an open channel has the file, Y = that channel's offset, A = its bit, X = the file's offset,
;;   DFS_CHANNEL = the offset of the last free channel seen, or 0, DFS_FREE_CHANNEL_BIT = its bit
FIND_OPEN_CHANNEL:
    lda #0
    sta DFS_CHANNEL
    lda #$08                        ; the bit of the channel at &11A0
    sta CHANNEL_SEARCH_BIT
    tya
    tax
    ldy #5 * DFS_CHANNEL_SIZE
FIND_OPEN_CHANNEL_LOOP:
    sty CHANNEL_SEARCH_OFFSET
    txa
    pha
    lda #8
    sta CHANNEL_SEARCH_COUNT
    lda CHANNEL_SEARCH_BIT
    bit DFS_OPEN_CHANNELS
    beq FIND_OPEN_CHANNEL_FREE
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    eor DFS_CURRENT_DRIVE
    and #$03
    bne FIND_OPEN_CHANNEL_SKIP      ; another drive
FIND_OPEN_CHANNEL_COMPARE:
    lda CATALOGUE_NAMES+8,x
    eor DFS_CHANNELS,y
    and #$7F
    bne FIND_OPEN_CHANNEL_SKIP
    inx
    iny
    iny
    dec CHANNEL_SEARCH_COUNT
    bne FIND_OPEN_CHANNEL_COMPARE
    sec                             ; found
    bcs FIND_OPEN_CHANNEL_STEP      ; always
FIND_OPEN_CHANNEL_FREE:
    sty DFS_CHANNEL
    sta DFS_FREE_CHANNEL_BIT
FIND_OPEN_CHANNEL_SKIP:
    sec                             ; the next channel down
    lda CHANNEL_SEARCH_OFFSET
    sbc #DFS_CHANNEL_SIZE
    sta CHANNEL_SEARCH_OFFSET
    asl CHANNEL_SEARCH_BIT
    clc
FIND_OPEN_CHANNEL_STEP:
    pla
    tax
    ldy CHANNEL_SEARCH_OFFSET
    lda CHANNEL_SEARCH_BIT
    bcs FIND_OPEN_CHANNEL_DONE
    bne FIND_OPEN_CHANNEL_LOOP      ; until the bit moves out
FIND_OPEN_CHANNEL_DONE:
    rts
