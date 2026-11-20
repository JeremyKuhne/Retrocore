;; DNFS EQUATES: THE DFS'S CATALOGUE AND WORKSPACE, AND THE NFS'S
;;
;; The RAM the two filing systems in the DNFS ROM keep. The DFS holds the current disc's catalogue in &0E00-&0FFF,
;; its own variables in page &10, and a buffer and a block of variables for each open file from &1100. The NFS keeps
;; its variables in pages &0E-&10 while it is the current filing system, and its private workspace in the pages the
;; MOS gives it. Both run their NMI code in page &0D, which the MOS's NMI vector points at. The MOS's names for the
;; hardware, the vectors and its own workspace are in MosEquates.asm.
;;
;; Acorn's documentation describes the catalogue's format (the Disc Filing System User Guide's technical
;; information); the names here, and the workspace the parts name for themselves, are ours.

; ---------------------------------------------------------------------------------------------------------------------
; The DFS's copy of the catalogue: sectors 0 and 1 of the current disc
; ---------------------------------------------------------------------------------------------------------------------

;; The catalogue's first sector: the disc title's first eight characters, then each file's name and directory.
;;
;; File n's entry is at CATALOGUE_NAMES+8+8n: seven characters of name, padded with spaces, and the directory's
;; letter, whose bit 7 is set when the file is locked. There are 31 entries at most.
;; See: <CATALOGUE_INFO>
CATALOGUE_NAMES = $0E00

;; The catalogue's second sector: the rest of the title, the disc's counts and options, then each file's addresses.
;;
;; Bytes 0-3 end the title, byte 4 is the sequence number, byte 5 eight times the number of files, byte 6 the boot
;; option (bits 4-5) and the top two bits of the disc's sector count (bits 0-1), and byte 7 the count's low byte.
;; File n's entry, at CATALOGUE_INFO+8+8n, holds the low two bytes of its load address, its execution address and
;; its length, then a byte with the top bits of the start sector (0-1), load address (2-3), length (4-5) and
;; execution address (6-7), and the start sector's low byte.
;; See: <CATALOGUE_NAMES>
CATALOGUE_INFO = $0F00

CATALOGUE_SEQUENCE = CATALOGUE_INFO + 4     ;; the catalogue's sequence number, in BCD, one more with each write
CATALOGUE_SIZE = CATALOGUE_INFO + 5         ;; eight times the number of files in the catalogue
CATALOGUE_OPTION = CATALOGUE_INFO + 6       ;; the boot option (bits 4-5) and the sector count's top bits (0-1)
CATALOGUE_SECTORS = CATALOGUE_INFO + 7      ;; the low byte of the number of sectors on the disc

; ---------------------------------------------------------------------------------------------------------------------
; The DFS's workspace
; ---------------------------------------------------------------------------------------------------------------------

DFS_WORKSPACE = $1000               ;; the DFS's variables, page &10; the parts name the fields they use
DFS_CHANNELS = $1100                ;; the open files' variables and sector buffers, from &1100
DFS_BUFFER_TRANSFER = DFS_WORKSPACE + $DD ;; zero while a channel's buffer is being read or written, else &FF

; ---------------------------------------------------------------------------------------------------------------------
; The NFS's workspace, which its parts share
; ---------------------------------------------------------------------------------------------------------------------

; The ports the file server's requests and replies use.

NFS_PORT_REPLY = $90                ;; the port the file server's replies to requests come back to
NFS_PORT_ACKNOWLEDGE = $91          ;; the port the file server acknowledges each block of a save on
NFS_PORT_DATA = $92                 ;; the port the file server sends a load's data to
NFS_PORT_COMMAND = $99              ;; the file server's command port, which every request goes to

; Zero page: the network's pointers, and the filing system scratch while the NFS is the filing system.

NFS_ESCAPE_ENABLE = $97             ;; bit 7 set while ESCAPE may abandon a wait on the network
NFS_BLOCK_POINTER = $9A             ;; a pointer to the control block being transmitted or awaited, two bytes
NFS_WORKSPACE_PAGE = $9C            ;; a pointer to the NFS's first private workspace page; its low byte varies
NFS_BLOCKS_PAGE = $9E               ;; a pointer to the NFS's second private page, which holds its receive blocks
NFS_FILE_START = FS_SCRATCH         ;; while a file is loaded or saved, its data's first address, four bytes
NFS_SEQUENCE_RESULT = FS_SCRATCH + 3 ;; the sequence bits a sequenced transfer leaves
NFS_FILE_END = FS_SCRATCH + 4       ;; while a file is loaded or saved, the address after its data, four bytes
NFS_SAVE_PORT = FS_SCRATCH + 8      ;; while a file is saved, the port its acknowledgements come back to
NFS_CALL_XY = FS_SCRATCH + 11       ;; the X and Y the current filing system call was made with, two bytes
NFS_CALL_A = FS_SCRATCH + 13        ;; the A the current filing system call was made with
NFS_NAME_POINTER = FS_SCRATCH + 14  ;; a pointer to the command or file name being sent
NFS_FS_BLOCK = FS_WORKSPACE         ;; the file server control block's control byte: &80 to transmit, &7F to receive
NFS_FS_BLOCK_PORT = FS_WORKSPACE + 1 ;; the file server control block's port
NFS_FS_BLOCK_STATION = FS_WORKSPACE + 2 ;; the file server control block's station, then its network
NFS_FS_BLOCK_START = FS_WORKSPACE + 4 ;; the file server control block's buffer start, four bytes
NFS_FS_BLOCK_END = FS_WORKSPACE + 8 ;; the file server control block's buffer end, four bytes

; Offsets in the NFS's private workspace pages, and the service call's result.

NFS_BLOCK_0_STATION = $02           ;; receive block 0's station and network numbers, &EB (235) after a hard reset
NFS_STATION = $14                   ;; this station's number, as STATION_ID gave it
NFS_FREE_BLOCK = $3F                ;; the control byte of a receive control block that is not in use
NFS_SERVICE_RESULT = OS_COMMAND_WORKSPACE + 1 ;; the service call result: zero claims the call

; Page &0D, after the NMI code, and the file server's details in page &0E.

NFS_TRANSMIT_FREE = $0D62           ;; bit 7 set while the transmitter is free; a caller claims it by clearing it
NFS_PROTECTION = $0D63              ;; the immediate operations this station refuses: bit n refuses operation &81+n
NFS_LISTENING = $0D64               ;; bit 7: receive into the block at &00C0; bit 6: into the private receive blocks
NFS_SAVED_PROTECTION = $0D65        ;; <NFS_PROTECTION> as it was before a remote call changed it
NFS_TUBE_PRESENT = $0D67            ;; &FF when a second processor is attached, as OSBYTE &EA reads it
NFS_FS_STATION = $0E00              ;; the file server's station number, then its network number
NFS_URD = $0E02                     ;; the file server's handle for the user root directory, before <NFS_CSD>, <NFS_LIB>
NFS_CSD = $0E03                     ;; the file server's handle for the currently selected directory
NFS_LIB = $0E04                     ;; the file server's handle for the library
NFS_BOOT_OPTION = $0E05             ;; the boot option the file server gave at log on, 0-3
NFS_MESSAGES = $0E06                ;; nonzero when *OPT 1 asks for each file's information to be shown
NFS_EOF_FLAGS = $0E07               ;; a bit for each open file, set when it may be at its end
NFS_SEQUENCE_BITS = $0E08           ;; a bit for each open file: the sequence number of its next byte transfer
NFS_LAST_ERROR = $0E09              ;; the number of the last error the file server reported

; Page &0F: the request being sent to the file server, which its reply then overwrites.

NFS_REQUEST = $0F00                 ;; a request to the file server: the port for the reply
NFS_REQUEST_FUNCTION = $0F01        ;; the request's function code
NFS_REQUEST_URD = $0F02             ;; the user root directory's handle, or the port for a load's data
NFS_REQUEST_CSD = $0F03             ;; the current directory's handle
NFS_REQUEST_LIB = $0F04             ;; the library's handle
NFS_REQUEST_DATA = $0F05            ;; the function's own data
NFS_REPLY_COMMAND = $0F03           ;; the file server's reply, over the request: its command code
NFS_REPLY_RESULT = $0F04            ;; the reply's return code, zero or an error number
NFS_REPLY_DATA = $0F05              ;; the reply's data, or an error message ending with a carriage return
