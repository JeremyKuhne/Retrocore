; ---------------------------------------------------------------------------------------------------------------------
; The DFS's filing system calls and its service calls ($B00A-$B803)
; ---------------------------------------------------------------------------------------------------------------------

; The open files. Each of the five channels has a block of DFS_CHANNEL_SIZE bytes from DFS_CHANNELS + &20 * n, for
; n = 1-5 and handles &11-&15, and a sector buffer in page &11 + n; DfsCatalogue.asm names the block's fields. The
; routines here index a field with Y = &20 * n, the channel's offset, as DFS_CHANNELS + field,y.

DFS_CHANNEL_COUNT = 5               ;; the number of channels, and so of files that can be open at once
DFS_HANDLE_BASE = $10               ;; the handle that channel offset 0 would have: handle &10 + n is channel n
DFS_CHANNEL_START = 15              ;; a channel: the low byte of the file's start sector
DFS_CHANNEL_SPACE = 24              ;; a channel: the file's room on the disc in bytes, three bytes, the low one 0
DFS_CHANNEL_SECTOR = 28             ;; a channel: the sector its buffer holds, two bytes, low byte first

DFS_BUFFER_VALID = $80              ;; DFS_CHANNEL_FLAGS: the buffer holds the sector PTR# is in
DFS_BUFFER_CHANGED = $40            ;; DFS_CHANNEL_FLAGS: the buffer has been written to since it was read
DFS_EOF_PASSED = $10                ;; DFS_CHANNEL_FLAGS: OSBGET has returned end of file once at this PTR#

; The DFS's variables in page &10 that these calls use.

DFS_GBPB_BLOCK = DFS_WORKSPACE + $60 ;; &1060-&106C, OSGBPB's copy of its control block
DFS_GBPB_HANDLE = DFS_GBPB_BLOCK    ;; the block's file handle, and the catalogue's cycle number from OSGBPB 8
DFS_GBPB_ADDRESS = DFS_GBPB_BLOCK + 1 ;; four bytes: the address of the data in memory
DFS_GBPB_COUNT = DFS_GBPB_BLOCK + 5 ;; four bytes: the number of bytes (or names) to transfer
DFS_GBPB_POINTER = DFS_GBPB_BLOCK + 9 ;; four bytes: the sequential pointer, or for OSGBPB 8 the catalogue offset
DFS_GBPB_BLOCK_SIZE = 13            ;; the bytes of an OSGBPB control block
DFS_GBPB_BLOCK_ADDRESS = DFS_WORKSPACE + $7D ;; two bytes: the address of the caller's OSGBPB control block
DFS_GBPB_TUBE_TYPE = DFS_WORKSPACE + $7F ;; the Tube transfer type for OSGBPB: 0 from the parasite, 1 to it
DFS_GBPB_TUBE = DFS_WORKSPACE + $81 ;; bit 7 set while OSGBPB's data goes through the Tube
DFS_PTR_SECTOR = DFS_WORKSPACE + $C4 ;; the low byte of the sector PTR# is in, while it is worked out
DFS_NMI_CLAIMED = DFS_WORKSPACE + $C8 ;; bit 7 set while the DFS holds the NMI
DFS_GBPB_ROUTINE = DFS_WORKSPACE + $D7 ;; two bytes: the routine OSGBPB calls for each byte or name
DFS_FILE_BLOCK = DFS_WORKSPACE + $DB ;; two bytes: the address of the caller's OSFILE control block
DFS_SAVED_VARIABLES = DFS_WORKSPACE + $C0 ;; &10C0-&10FF, which the private workspace keeps with &1100-&11BF

; The DFS's private workspace: two pages the MOS gives it at service call 2.

DFS_PRIVATE_SAVED = $D3             ;; the copy of &10D3: bit 7 set when the copy of the workspace is usable
DFS_PRIVATE_OWNER = $D4             ;; bit 7 set while the DFS's workspace is in &0E00-&16FF

; Zero page the filing system calls use.

DFS_BOOT_FLAG = FS_SCRATCH + 3      ;; zero when the DFS, as it starts, runs the disc's !BOOT
DFS_GBPB_BLOCK_POINTER = FS_SCRATCH + 4 ;; two bytes: the caller's OSGBPB control block
DFS_FSC_X = FS_SCRATCH + 5          ;; OSFSC's X, while the reason code picks the routine
DFS_GBPB_PTR = FS_SCRATCH + 6       ;; four bytes: the sequential pointer for an OSGBPB transfer
DFS_GBPB_DATA_POINTER = FS_SCRATCH + 8 ;; two bytes: the next byte of OSGBPB's data in the I/O processor
DFS_BYTE_POINTER = FS_SCRATCH + 10  ;; two bytes: the byte at PTR# in the channel's buffer
DFS_IO_LENGTH = FS_WORKSPACE        ;; two bytes: the bytes a disc transfer moves, low byte first
DFS_IO_SECTOR_HIGH = FS_WORKSPACE + 2 ;; the top bits of the sector a disc transfer starts at
DFS_IO_SECTOR = FS_WORKSPACE + 3    ;; the low byte of that sector
DFS_IO_ADDRESS = FS_SCRATCH + 12    ;; two bytes: the address in memory of a disc transfer

; The numbers the filing system calls and service calls use.

DFS_FILING_SYSTEM = 4               ;; the DFS's filing system number, from OSARGS 0 and for service call &12
DFS_FSC_TAKEOVER = 6                ;; OSFSC 6: a new filing system is about to take over
DFS_FSC_CALLS = 9                   ;; OSFSC's reason codes, 0-8
DFS_GBPB_CALLS = 9                  ;; OSGBPB's reason codes, 0-8
DFS_FILE_CALLS = 8                  ;; OSFILE's reason codes, &FF and 0-6
DFS_FILE_BLOCK_SIZE = $12           ;; the bytes of an OSFILE control block
DFS_ABSOLUTE_TOP = >(DFS_CHANNELS + $100 * (DFS_CHANNEL_COUNT + 1)) ;; the page after the channels' buffers, &17
DFS_PRIVATE_PAGES = 2               ;; the pages of private workspace the DFS claims

DFS_SERVICE_ABSOLUTE_WORKSPACE = $01 ;; service call &01: absolute workspace claim
DFS_SERVICE_PRIVATE_WORKSPACE = $02 ;; service call &02: private workspace claim
DFS_SERVICE_AUTO_BOOT = $03         ;; service call &03: auto-boot
DFS_SERVICE_COMMAND = $04           ;; service call &04: unrecognised command
DFS_SERVICE_OSWORD = $08            ;; service call &08: unrecognised OSWORD
DFS_SERVICE_HELP = $09              ;; service call &09: *HELP
DFS_SERVICE_STATIC_WORKSPACE = $0A  ;; service call &0A: claim static workspace
DFS_SERVICE_VECTORS_CLAIMED = $0F   ;; service call &0F: vectors claimed
DFS_SERVICE_SELECT = $12            ;; service call &12: initialise filing system

DFS_OSBYTE_KEYBOARD_SCAN = $7A      ;; OSBYTE &7A: scan the keyboard from internal key 16
DFS_OSBYTE_KEYS_PRESSED = $78       ;; OSBYTE &78: write the keys-pressed information
DFS_OSBYTE_EXTENDED_VECTORS = $A8   ;; OSBYTE &A8: read the address of the extended vectors
DFS_OSBYTE_EXEC_HANDLE = $C6        ;; OSBYTE &C6: read or write the *EXEC file's handle
DFS_OSBYTE_SPOOL_HANDLE = $C7       ;; OSBYTE &C7: read or write the *SPOOL file's handle
DFS_OSBYTE_TUBE = $EA               ;; OSBYTE &EA: read the Tube's presence, &FF when there is one
DFS_OSBYTE_BREAK_TYPE = $FD         ;; OSBYTE &FD: read the last BREAK's type, 0 soft, 1 power-on, 2 hard
DFS_KEY_D = $32                     ;; the internal key number of D, which selects the DFS at BREAK
DFS_OSWORD_CYCLE = $7D              ;; OSWORD &7D: read the catalogue's cycle number
DFS_OSWORD_SIZE = $7E               ;; OSWORD &7E: read the size of the disc
DFS_OSWORD_DISC_ACCESS = $7F        ;; OSWORD &7F: give the 8271 a command

DFS_ERROR_CANT_EXTEND = $BF         ;; error &BF, "Can't extend"
DFS_ERROR_READ_ONLY = $C1           ;; error &C1, "Read only"
DFS_ERROR_CHANNEL = $DE             ;; error &DE, "Channel"
DFS_ERROR_EOF = $DF                 ;; error &DF, "EOF"

;; OSARGS &FF: writes the buffers of one open file, or of all of them, to the disc, and returns A = 0.
;; In: Y = the file's handle, or 0 for every open file
;; Out: A = 0, through the frame of <SAVE_REGISTERS> in <DFS_OSARGS>
;; Uses: A, X, Y
;; See: <ENSURE_FILES>
DFS_OSARGS_UPDATE:
    jsr ZERO_SAVED_A
;; Writes the buffers of one open file, or of all of them, to the disc, and leaves the files open.
;;
;; It closes them as OSFIND would, then puts back <DFS_OPEN_CHANNELS>, so the buffers and the catalogue are brought up
;; to date without closing anything. For one file the catalogue entry also gets the file's new length; for all of
;; them only the buffers are written.
;; In: Y = the file's handle, or 0 for every open file
;; Uses: A, X, Y, DFS_CLOSE_MODE
;; See: <CLOSE_ALL_CHANNELS>, <CLOSE_FILE>
ENSURE_FILES:
    lda DFS_OPEN_CHANNELS
    pha
    lda #$00                        ; for all files, leave the lengths in the catalogue alone
    sta DFS_CLOSE_MODE
    tya
    bne ENSURE_FILES_ONE
    jsr CLOSE_ALL_CHANNELS                       ; close every channel
    beq ENSURE_FILES_DONE           ; always: CLOSE_ALL_CHANNELS returns zero set
ENSURE_FILES_ONE:
    jsr CLOSE_FILE                       ; close the one channel, which also writes its length
ENSURE_FILES_DONE:
    pla
    sta DFS_OPEN_CHANNELS           ; and open them all again
    rts

;; Sets to zero the A that the caller will return, so that the call reports success or claims the service call.
;;
;; It must be called directly by a routine that called <SAVE_REGISTERS> first: the A that <SAVE_REGISTERS>'s frame puts
;; back is the ninth byte up the stack from here, above X and A pushed here, this call's return address, the frame's own
;; return address, and the saved Y and X.
;; Out: zero = set when A is zero
;; Keeps: A, X, Y
ZERO_SAVED_A:
    pha
    txa
    pha
    lda #$00
    tsx
    sta STACK+9,x                   ; the A in the caller's SAVE_REGISTERS frame
    pla
    tax
    pla
    rts

;; OSARGS for the DFS: reads or changes a file's sequential pointer or extent, or reads the filing system's details.
;;
;; With Y = 0: A = 0 returns 4, the DFS's number; A = 1 writes the address of the command line's tail; A = &FF
;; updates every file. With a handle in Y: A = 0 reads PTR#, A = 1 writes it, A = 2 reads EXT#, and A = &FF updates
;; the file. A is 0 after those, except as said, and is kept for any other call.
;; In: A = the reason code, X = the four-byte block in zero page, Y = the file's handle or 0
;; Out: A = 0, or 4 for the filing system's number
;; Keeps: X, Y
;; Errors: "Channel", for a handle that is not open
;; See: <DFS_OSARGS_UPDATE>, <READ_POINTER_OR_LENGTH>, <WRITE_SEQUENTIAL_POINTER>
DFS_OSARGS:
    jsr SAVE_REGISTERS                       ; keep A, X and Y for the caller
    cmp #$FF
    beq DFS_OSARGS_UPDATE
    cpy #$00
    beq DFS_OSARGS_FILING_SYSTEM
    cmp #$03                        ; nothing beyond OSARGS 2 on a file
    bcs DFS_OSARGS_DONE
    jsr ZERO_SAVED_A
    cmp #$01
    bne READ_POINTER_OR_LENGTH      ; OSARGS 0 and 2
    jmp WRITE_SEQUENTIAL_POINTER
DFS_OSARGS_FILING_SYSTEM:
    cmp #$02                        ; only OSARGS 0 and 1 without a file
    bcs DFS_OSARGS_DONE
    jsr ZERO_SAVED_A
    beq DFS_OSARGS_NUMBER
    lda #$FF                        ; OSARGS 1: the tail is in the I/O processor, &FFFFxxxx
    sta $02,x
    sta $03,x
    lda DFS_COMMAND_TAIL
    sta $00,x
    lda DFS_COMMAND_TAIL+1
    sta $01,x
DFS_OSARGS_DONE:
    rts
DFS_OSARGS_NUMBER:
    lda #DFS_FILING_SYSTEM
    tsx
    sta STACK+5,x                   ; the A in the SAVE_REGISTERS frame
    rts

;; OSARGS 0 and 2: reads a file's sequential pointer or its extent into a four-byte block in zero page.
;; In: A = 0 for PTR#, 2 for EXT#, X = the block, Y = the file's handle
;; Out: Y = the channel's offset plus A * 2
;; Uses: A, DFS_CHANNEL, DFS_SAVED_X
;; Keeps: X
;; Errors: "Channel"
;; See: <DFS_OSARGS>
READ_POINTER_OR_LENGTH:
    jsr FIND_CHANNEL
    sty DFS_CHANNEL
    asl a                           ; EXT# is four bytes after PTR#
    adc DFS_CHANNEL
    tay
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    sta $00,x
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    sta $01,x
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    sta $02,x
    lda #$00
    sta $03,x
    rts

;; Finds whether the channel at an offset is open.
;;
;; Offset 0, which a handle out of range gives, is never open.
;; In: Y = the channel's offset, from <HANDLE_TO_CHANNEL>, X = the caller's X
;; Out: Y = DFS_CHANNEL = the offset, carry = clear when the channel is open
;; Uses: DFS_SAVED_X (X)
;; Keeps: A, X
CHECK_CHANNEL_OPEN:
    pha
    stx DFS_SAVED_X
    tya
    and #$E0                        ; the channel's number times &20
    sta DFS_CHANNEL
    beq CHECK_CHANNEL_OPEN_NOT
    jsr SHIFT_RIGHT_5                       ; the channel's number, 1-7
    tay
    lda #$00
    sec
CHECK_CHANNEL_OPEN_MASK:
    ror a                           ; bit 8 - n: channel 1 is bit 7
    dey
    bne CHECK_CHANNEL_OPEN_MASK
    ldy DFS_CHANNEL
    bit DFS_OPEN_CHANNELS
    bne CHECK_CHANNEL_OPEN_YES
CHECK_CHANNEL_OPEN_NOT:
    pla
    sec
    rts
CHECK_CHANNEL_OPEN_YES:
    pla
    clc
    rts

;; Turns the file handle in X into a channel's offset in Y, as <HANDLE_TO_CHANNEL> does for one in Y.
;;
;; Nothing in the ROM calls it.
;; In: X = the handle
;; Out: Y = the channel's offset, or 0 for a handle outside &10-&17
;; Keeps: A, X
HANDLE_X_TO_CHANNEL:
    pha
    txa
    jmp HANDLE_TO_CHANNEL_A
;; Turns a file handle into the offset of its channel's block.
;;
;; Handles &10-&17 give &20 times their low three bits; any other handle gives 0, which no channel has.
;; In: Y = the handle
;; Out: Y = the channel's offset
;; Keeps: A, X
;; Entry: HANDLE_TO_CHANNEL_A = takes the handle in A, with the caller's A pushed
HANDLE_TO_CHANNEL:
    pha
    tya
HANDLE_TO_CHANNEL_A:
    cmp #DFS_HANDLE_BASE
    bcc HANDLE_TO_CHANNEL_BAD
    cmp #DFS_HANDLE_BASE + 8
    bcc HANDLE_TO_CHANNEL_SHIFT
HANDLE_TO_CHANNEL_BAD:
    lda #$08                        ; 8 * &20 is 0 in a byte
HANDLE_TO_CHANNEL_SHIFT:
    jsr SHIFT_LEFT_5                       ; times &20, dropping the handle's top bits
    tay
    pla
    rts

;; Stops *EXEC or *SPOOL, by setting its handle to 0, when its file is the channel at DFS_CHANNEL.
;;
;; Errors on a channel call it first, so that the MOS does not go on reading or writing a file the error is about.
;; It does not close the file. Once it has stopped *EXEC it leaves *SPOOL alone.
;; In: DFS_CHANNEL = the channel
;; Uses: A, X, Y
;; See: <IS_CURRENT_CHANNEL>
STOP_EXEC_OR_SPOOL:
    lda #DFS_OSBYTE_EXEC_HANDLE
    jsr READ_OS_VARIABLE                       ; X = the *EXEC file's handle
    txa
    beq STOP_EXEC_OR_SPOOL_SPOOL
    jsr IS_CURRENT_CHANNEL
    bne STOP_EXEC_OR_SPOOL_SPOOL
    lda #DFS_OSBYTE_EXEC_HANDLE
    bne STOP_EXEC_OR_SPOOL_FORGET   ; always
STOP_EXEC_OR_SPOOL_SPOOL:
    lda #DFS_OSBYTE_SPOOL_HANDLE
    jsr READ_OS_VARIABLE                       ; X = the *SPOOL file's handle
    jsr IS_CURRENT_CHANNEL
    bne IS_CURRENT_CHANNEL_DONE
    lda #DFS_OSBYTE_SPOOL_HANDLE
STOP_EXEC_OR_SPOOL_FORGET:
    ldx #$00                        ; write a handle of 0
    ldy #$00
    jmp OSBYTE

;; Finds whether a file handle is the channel at DFS_CHANNEL.
;; In: X = the handle
;; Out: zero = set when it is, Y = the handle's channel offset
;; Keeps: X
IS_CURRENT_CHANNEL:
    txa
    tay
    jsr HANDLE_TO_CHANNEL
    cpy DFS_CHANNEL
IS_CURRENT_CHANNEL_DONE:
    rts

;; OSFSC 1: finds whether a file's sequential pointer is at its end.
;; In: X = the file's handle
;; Out: X = &FF at the end of the file, otherwise 0
;; Uses: DFS_CHANNEL, DFS_SAVED_X
;; Keeps: A, Y
;; Errors: "Channel"
CHECK_EOF:
    pha
    tya
    pha
    txa
    tay
    jsr FIND_CHANNEL
    tya
    jsr COMPARE_POINTER             ; PTR# with EXT#
    bne CHECK_EOF_NOT_END
    ldx #$FF
    bne CHECK_EOF_DONE              ; always
CHECK_EOF_NOT_END:
    ldx #$00
CHECK_EOF_DONE:
    pla
    tay
    pla
FIND_CHANNEL_DONE:
    rts

;; Finds the open channel for a file handle, or gives the "Channel" error.
;; In: Y = the handle, X = the caller's X
;; Out: Y = DFS_CHANNEL = the channel's offset
;; Uses: DFS_SAVED_X (X)
;; Keeps: A, X
;; Errors: &DE "Channel", after <STOP_EXEC_OR_SPOOL>, when no file is open with the handle
FIND_CHANNEL:
    jsr HANDLE_TO_CHANNEL
    jsr CHECK_CHANNEL_OPEN
    bcc FIND_CHANNEL_DONE
    jsr STOP_EXEC_OR_SPOOL
    jsr DFS_ERROR
    .byte DFS_ERROR_CHANNEL, "Channel", 0

;; Gives the "EOF" error, for OSBGET when a file's end has already been reported.
;; Errors: &DF "EOF"
EOF_ERROR:
    jsr DFS_ERROR
    .byte DFS_ERROR_EOF, "EOF", 0

;; OSBGET for the DFS: reads the byte at a file's sequential pointer and moves the pointer on.
;;
;; At the end of the file it returns carry set and A = &FE the first time, and marks the channel; a second read there
;; is the "EOF" error. Writing PTR# clears the mark. The sector holding the pointer is read into the channel's buffer
;; when the buffer holds another, after any changes to that one are written back.
;; In: Y = the file's handle
;; Out: A = the byte, or &FE at the end, carry = set at the end of the file
;; Keeps: X, Y
;; Errors: "Channel", &DF "EOF", and the disc errors
;; See: <DFS_OSBPUT>
DFS_OSBGET:
    jsr SAVE_X_Y                       ; keep X and Y for the caller
    jsr FIND_CHANNEL
    tya
    jsr COMPARE_POINTER             ; PTR# with EXT#
    bne DFS_OSBGET_READ
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    and #DFS_EOF_PASSED
    bne EOF_ERROR
    lda #DFS_EOF_PASSED
    jsr SET_CHANNEL_FLAGS
    ldx DFS_SAVED_X
    lda #$FE
    sec
    rts
DFS_OSBGET_READ:
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    bmi DFS_OSBGET_BYTE             ; the buffer holds the sector already
    jsr SELECT_CHANNEL_DRIVE                       ; the channel's drive
    jsr SAVE_BUFFER
    sec
    jsr TRANSFER_BUFFER             ; read the sector PTR# is in
DFS_OSBGET_BYTE:
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    sta DFS_BYTE_POINTER
    lda DFS_CHANNELS+DFS_CHANNEL_BUFFER,y
    sta DFS_BYTE_POINTER+1
    ldy #$00
    lda (DFS_BYTE_POINTER),y
    pha
    ldy DFS_CHANNEL
    ldx DFS_BYTE_POINTER
    inx
    txa
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    bne DFS_OSBGET_DONE
    clc                             ; into the next sector
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    adc #$01
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    adc #$00
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    jsr MARK_BUFFER_INVALID
DFS_OSBGET_DONE:
    clc
    pla
    rts

;; Makes the sector that a channel's sequential pointer is in the one its buffer holds, and marks the buffer valid.
;;
;; The sector is the file's start sector plus the pointer's top two bytes. It falls into <MARK_BUFFER_VALID>.
;; In: Y = the channel's offset
;; Out: DFS_IO_SECTOR_HIGH/DFS_IO_SECTOR = the sector, high byte first, as the 8271 commands take it, carry = clear
;; Uses: A
;; Keeps: X, Y
SET_BUFFER_SECTOR:
    clc
    lda DFS_CHANNELS+DFS_CHANNEL_START,y
    adc DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    sta DFS_IO_SECTOR
    sta DFS_CHANNELS+DFS_CHANNEL_SECTOR,y
    lda DFS_CHANNELS+DFS_CHANNEL_MIXED,y
    and #$03                        ; the start sector's top bits
    adc DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    sta DFS_IO_SECTOR_HIGH
    sta DFS_CHANNELS+DFS_CHANNEL_SECTOR+1,y
;; Marks a channel's buffer as holding the sector its pointer is in.
;; In: Y = the channel's offset
;; Out: carry = clear
;; Uses: A
;; Keeps: X, Y
MARK_BUFFER_VALID:
    lda #DFS_BUFFER_VALID
;; Sets bits in a channel's flags.
;; In: A = the bits, Y = the channel's offset
;; Out: carry = clear
;; Uses: A
;; Keeps: X, Y
SET_CHANNEL_FLAGS:
    ora DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    bne STORE_CHANNEL_FLAGS         ; always: A has a bit set
;; Marks a channel's buffer as no longer holding the sector its pointer is in.
;; In: Y = the channel's offset
;; Out: carry = clear
;; Uses: A
;; Keeps: X, Y
MARK_BUFFER_INVALID:
    lda #$FF - DFS_BUFFER_VALID
;; Clears bits in a channel's flags.
;; In: A = the bits to keep, Y = the channel's offset
;; Out: carry = clear
;; Uses: A
;; Keeps: X, Y
CLEAR_CHANNEL_FLAGS:
    and DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
STORE_CHANNEL_FLAGS:
    sta DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    clc
    rts

;; Writes a channel's buffer back to its sector when the buffer has been changed.
;;
;; It falls into <TRANSFER_BUFFER> with carry clear to write.
;; In: Y = DFS_CHANNEL = the channel's offset
;; Out: Y = DFS_CHANNEL
;; Uses: A, X, DFS_IO_ADDRESS, DFS_IO_ADDRESS+1, DFS_IO_LENGTH..DFS_IO_SECTOR
;; Errors: the disc errors
SAVE_BUFFER:
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    and #DFS_BUFFER_CHANGED
    beq TRANSFER_BUFFER_END
    clc
;; Reads into a channel's buffer the sector its sequential pointer is in, or writes the buffer back to its sector.
;;
;; DFS_BUFFER_TRANSFER is zero while it runs, so that an error on the way stops *EXEC or *SPOOL on the file (see
;; <DFS_ERROR>). The whole sector, 256 bytes, goes between the disc and the buffer page in the I/O processor. A write
;; clears DFS_BUFFER_CHANGED; a read sets the buffer's sector from the pointer and marks it valid.
;; In: Y = DFS_CHANNEL = the channel's offset, carry = set to read, clear to write
;; Out: Y = DFS_CHANNEL
;; Uses: A, X, DFS_IO_ADDRESS, DFS_IO_ADDRESS+1, DFS_IO_LENGTH..DFS_IO_SECTOR
;; Errors: the disc errors, and "Escape" while the drive is not ready
TRANSFER_BUFFER:
    php
    inc DFS_BUFFER_TRANSFER
    jsr SELECT_DRIVE                       ; start the drive
    ldy DFS_CHANNEL
    lda DFS_CHANNELS+DFS_CHANNEL_BUFFER,y
    sta DFS_IO_ADDRESS+1                  ; the transfer's address: the buffer
    jsr SET_HOST_ADDRESS                       ; in the I/O processor
    lda #$00
    sta DFS_IO_ADDRESS
    sta DFS_IO_LENGTH                  ; 256 bytes: one sector
    lda #$01
    sta DFS_IO_LENGTH+1
    plp
    bcs TRANSFER_BUFFER_READ
    lda DFS_CHANNELS+DFS_CHANNEL_SECTOR,y ; write to the sector the buffer came from
    sta DFS_IO_SECTOR
    lda DFS_CHANNELS+DFS_CHANNEL_SECTOR+1,y
    sta DFS_IO_SECTOR_HIGH
    jsr WRITE_FILE_DATA                       ; write it
    ldy DFS_CHANNEL
    lda #$FF - DFS_BUFFER_CHANGED
    jsr CLEAR_CHANNEL_FLAGS
    bcc TRANSFER_BUFFER_DONE        ; always
TRANSFER_BUFFER_READ:
    jsr SET_BUFFER_SECTOR
    jsr READ_FILE_DATA                       ; read it
TRANSFER_BUFFER_DONE:
    dec DFS_BUFFER_TRANSFER
    ldy DFS_CHANNEL
TRANSFER_BUFFER_END:
    rts

;; Gives the "Locked" error, for OSBPUT to a locked file.
;; Errors: "Locked"
DFS_OSBPUT_LOCKED:
    jmp DFS_LOCKED_ERROR

;; Gives the "Read only" error, for OSBPUT to a file opened for input.
;; Errors: &C1 "Read only"
READ_ONLY_ERROR:
    jsr DFS_ERROR
    .byte DFS_ERROR_READ_ONLY, "Read only", 0

;; Writes a byte to the channel at an offset, as <DFS_OSBPUT> does for a handle.
;; In: A = the byte, Y = DFS_CHANNEL = the channel's offset
;; Keeps: A, X, Y
;; Errors: those of <DFS_OSBPUT>, but "Channel"
PUT_BYTE:
    jsr SAVE_REGISTERS
    jmp DFS_OSBPUT_CHANNEL
;; OSBPUT for the DFS: writes a byte at a file's sequential pointer and moves the pointer on.
;;
;; When the pointer reaches the end of the space the file has on the disc, the file grows into the free space after
;; it: up to the next file or the end of the disc, or to the next multiple of 64K bytes when that is nearer. The
;; catalogue gets the new length, and the file "Can't extend" when there is no space after it. When the pointer
;; passes the extent, the extent follows it and is marked to be written to the catalogue on closing.
;; In: A = the byte, Y = the file's handle
;; Keeps: A, X, Y
;; Errors: "Channel", &C1 "Read only", &C3 "Locked", &BF "Can't extend", and the disc errors
;; Entry: DFS_OSBPUT_CHANNEL = with the channel's offset in Y, after the caller's <SAVE_REGISTERS>, which puts its
;;   registers back, as <PUT_BYTE> does; keeps nothing
;; See: <DFS_OSBGET>, <PUT_BYTE>
DFS_OSBPUT:
    jsr SAVE_REGISTERS                       ; keep A, X and Y for the caller
    jsr FIND_CHANNEL
DFS_OSBPUT_CHANNEL:
    pha
    lda DFS_CHANNELS+DFS_CHANNEL_READ_ONLY,y
    bmi READ_ONLY_ERROR
    lda DFS_CHANNELS+DFS_CHANNEL_DIRECTORY,y
    bmi DFS_OSBPUT_LOCKED
    jsr SELECT_CHANNEL_DRIVE                       ; the channel's drive
    tya
    clc
    adc #DFS_CHANNEL_SPACE - DFS_CHANNEL_EXTENT
    jsr COMPARE_POINTER             ; PTR# with the file's space
    bne DFS_OSBPUT_BUFFER
    jsr FIND_CHANNEL_FILE_NAME                       ; find the file in the catalogue
    ldx DFS_CHANNEL_ENTRY
    sec                             ; the sectors from the file's start to the next file above, or the disc's end
    lda CATALOGUE_SECTORS,x         ; the start of the entry before, or the disc's size for the first
    sbc CATALOGUE_SECTORS+8,x       ; less the file's start
    pha
    lda CATALOGUE_OPTION,x
    sbc CATALOGUE_SECTORS+7,x
    and #$03
    cmp DFS_CHANNELS+DFS_CHANNEL_SPACE+2,y
    bne DFS_OSBPUT_GROW_64K
    pla
    cmp DFS_CHANNELS+DFS_CHANNEL_SPACE+1,y
    bne DFS_OSBPUT_GROW
    sty FS_SCRATCH+4                ; the channel; nothing on the way to the error reads it
    sty DFS_CHANNEL
    jsr STOP_EXEC_OR_SPOOL
    jsr DFS_ERROR
    .byte DFS_ERROR_CANT_EXTEND, "Can't extend", 0
DFS_OSBPUT_GROW_64K:
    lda DFS_CHANNELS+DFS_CHANNEL_SPACE+2,y ; the space's next multiple of 256 sectors
    clc
    adc #$01
    sta DFS_CHANNELS+DFS_CHANNEL_SPACE+2,y
    asl a                           ; into bits 4-5, the length's top bits
    asl a
    asl a
    asl a
    eor CATALOGUE_SECTORS+7,x
    and #$30
    eor CATALOGUE_SECTORS+7,x
    sta CATALOGUE_SECTORS+7,x
    pla
    lda #$00
DFS_OSBPUT_GROW:
    sta CATALOGUE_SECTORS+6,x       ; the length's middle byte
    sta DFS_CHANNELS+DFS_CHANNEL_SPACE+1,y
    lda #$00
    sta CATALOGUE_SECTORS+5,x       ; and its low byte
    jsr WRITE_CATALOGUE                       ; write the catalogue
    jsr WAIT_AND_RELEASE_NMI
    ldy DFS_CHANNEL
DFS_OSBPUT_BUFFER:
    lda DFS_CHANNELS+DFS_CHANNEL_FLAGS,y
    bmi DFS_OSBPUT_STORE            ; the buffer holds the sector already
    jsr SAVE_BUFFER
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT,y
    bne DFS_OSBPUT_READ_SECTOR
    tya
    jsr COMPARE_POINTER             ; PTR# with EXT#
    bne DFS_OSBPUT_READ_SECTOR
    jsr SET_BUFFER_SECTOR           ; a new sector at the end: nothing to read
    bne DFS_OSBPUT_STORE            ; always: A has bit 7 set
DFS_OSBPUT_READ_SECTOR:
    sec
    jsr TRANSFER_BUFFER
DFS_OSBPUT_STORE:
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    sta DFS_BYTE_POINTER
    lda DFS_CHANNELS+DFS_CHANNEL_BUFFER,y
    sta DFS_BYTE_POINTER+1
    pla
    ldy #$00
    sta (DFS_BYTE_POINTER),y
    ldy DFS_CHANNEL
    lda #DFS_BUFFER_CHANGED
    jsr SET_CHANNEL_FLAGS
    inc DFS_BYTE_POINTER
    lda DFS_BYTE_POINTER
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    bne DFS_OSBPUT_EXTENT
    jsr MARK_BUFFER_INVALID         ; into the next sector, with carry clear
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    adc #$01
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    adc #$00
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
DFS_OSBPUT_EXTENT:
    tya
    jsr COMPARE_POINTER             ; PTR# with EXT#
    bcc DFS_OSBPUT_DONE
    lda #DFS_CHANNEL_EXTENT_CHANGED
    jsr SET_CHANNEL_FLAGS
    ldx #$02
DFS_OSBPUT_EXTENT_LOOP:
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER,y ; EXT# = PTR#
    sta DFS_CHANNELS+DFS_CHANNEL_EXTENT,y
    iny
    dex
    bpl DFS_OSBPUT_EXTENT_LOOP
DFS_OSBPUT_DONE:
    rts

;; OSARGS 1: sets a file's sequential pointer.
;;
;; A pointer beyond the extent extends the file with zeros up to it, a byte at a time through <PUT_BYTE>. That keeps
;; DFS_GBPB_PTR..DFS_GBPB_PTR+2 for OSGBPB, which passes its pointer there. Then it checks whether the buffer still
;; holds the pointer's sector.
;; In: X = the four-byte block in zero page holding the pointer, Y = the file's handle
;; Out: DFS_CHANNEL = the channel's offset
;; Keeps: A, X, Y
;; Errors: "Channel", and those of <DFS_OSBPUT> while the file is extended
;; See: <CHECK_BUFFER_SECTOR>
WRITE_SEQUENTIAL_POINTER:
    jsr SAVE_REGISTERS
    jsr FIND_CHANNEL
    ldy DFS_CHANNEL
WRITE_SEQUENTIAL_POINTER_LOOP:
    jsr COMPARE_EXTENT
    bcs WRITE_SEQUENTIAL_POINTER_SET
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT,y ; PTR# = EXT#, then write a zero there
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+1,y
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+2,y
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    jsr CHECK_BUFFER_SECTOR
    lda DFS_GBPB_PTR
    pha
    lda DFS_GBPB_PTR+1
    pha
    lda DFS_GBPB_PTR+2
    pha
    lda #$00
    jsr PUT_BYTE
    pla
    sta DFS_GBPB_PTR+2
    pla
    sta DFS_GBPB_PTR+1
    pla
    sta DFS_GBPB_PTR
    jmp WRITE_SEQUENTIAL_POINTER_LOOP
WRITE_SEQUENTIAL_POINTER_SET:
    lda $00,x
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    lda $01,x
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    lda $02,x
    sta DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
;; After a channel's pointer has moved, marks its buffer valid if it holds the sector the pointer is now in, and
;; invalid if not; either way the end of file is no longer reported.
;; In: Y = the channel's offset
;; Uses: A, DFS_PTR_SECTOR
;; Keeps: X, Y
CHECK_BUFFER_SECTOR:
    lda #$FF - DFS_BUFFER_VALID - DFS_EOF_PASSED
    jsr CLEAR_CHANNEL_FLAGS         ; carry clear
    lda DFS_CHANNELS+DFS_CHANNEL_START,y
    adc DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    sta DFS_PTR_SECTOR
    lda DFS_CHANNELS+DFS_CHANNEL_MIXED,y
    and #$03
    adc DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    cmp DFS_CHANNELS+DFS_CHANNEL_SECTOR+1,y
    bne DFS_OSBPUT_DONE
    lda DFS_PTR_SECTOR
    cmp DFS_CHANNELS+DFS_CHANNEL_SECTOR,y
    bne DFS_OSBPUT_DONE
    jmp MARK_BUFFER_VALID

;; Compares a channel's sequential pointer with three bytes four on from a channel's offset.
;;
;; With the channel's own offset in A, that is its extent; with the offset plus four, the space the file has on the
;; disc, whose low byte is always 0.
;; In: Y = the channel's offset, A = the same offset for the extent, or the offset plus 4 for the space
;; Out: zero = set when they are equal, carry = set when the pointer is not less, X = A
COMPARE_POINTER:
    tax
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+2,y
    cmp DFS_CHANNELS+DFS_CHANNEL_EXTENT+2,x
    bne COMPARE_POINTER_DONE
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER+1,y
    cmp DFS_CHANNELS+DFS_CHANNEL_EXTENT+1,x
    bne COMPARE_POINTER_DONE
    lda DFS_CHANNELS+DFS_CHANNEL_POINTER,y
    cmp DFS_CHANNELS+DFS_CHANNEL_EXTENT,x
COMPARE_POINTER_DONE:
    rts

;; Compares a channel's extent with a three-byte value in zero page.
;; In: Y = the channel's offset, X = the value
;; Out: carry = set when the extent is not less than the value
;; Uses: A
;; Keeps: X, Y
COMPARE_EXTENT:
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT,y
    cmp $00,x
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+1,y
    sbc $01,x
    lda DFS_CHANNELS+DFS_CHANNEL_EXTENT+2,y
    sbc $02,x
    rts

;; The command that boot option 1 runs: *LOAD !BOOT.
;; See: <SELECT_DFS>
DFS_BOOT_LOAD_COMMAND:
    .byte "L.!BOOT", $0D
;; The command that boot option 3 runs, *EXEC !BOOT, whose tail is option 2's.
;; See: <DFS_BOOT_RUN_COMMAND>
DFS_BOOT_EXEC_COMMAND:
    .byte "E."
;; The command that boot option 2 runs: *!BOOT, which runs the file.
;; See: <DFS_BOOT_EXEC_COMMAND>
DFS_BOOT_RUN_COMMAND:
    .byte "!BOOT", $0D
    .assert >DFS_BOOT_LOAD_COMMAND = >DFS_BOOT_RUN_COMMAND, "The boot commands share a page."

;; Starts the DFS at BREAK, from service call 3: prints "Acorn DFS" and selects the DFS, running !BOOT when asked.
;; In: DFS_BOOT_FLAG = the service call's Y, 0 to boot
;; See: <SELECT_DFS>
START_DFS:
    lda DFS_BOOT_FLAG
    jsr DFS_PRINT_INLINE
    .byte "Acorn DFS", $0D, $0D     ; ends at the BCC, whose opcode has bit 7 set
    bcc SELECT_DFS                  ; always: DFS_PRINT_INLINE returns carry clear
;; *DISC and *DISK, and service call &12 for filing system 4: selects the DFS without running !BOOT.
;; See: <SELECT_DFS>
DISC_COMMAND:
    lda #$FF
;; Makes the DFS the filing system, and runs the disc's !BOOT when asked.
;;
;; - Tells the old filing system with OSFSC 6, points FILEV to FSCV at the extended vector entries, fills in the
;;   extended vectors with the DFS's routines and its ROM number, and issues service call &0F.
;; - When the DFS still owns its workspace in &0E00-&16FF, that is all. When the private workspace holds a copy of it,
;;   saved at a soft BREAK or when another ROM claimed the space, it claims the space back and restores the copy, so
;;   files left open stay open; their buffers must be read again. Otherwise, or when booting, it starts afresh: no
;;   files open, directory $ and library $ on drive 0.
;; - Notes whether there is a Tube, then for a boot reads drive 0's catalogue and runs the command for its boot
;;   option, *LOAD, *RUN or *EXEC !BOOT.
;; In: A = 0 to boot, X = the ROM number
;; Out: A = 0, through the caller's frame of <SAVE_REGISTERS>, when there is one
;; Uses: A, X, Y, FS_SCRATCH, FS_SCRATCH+1
;; See: <START_DFS>, <DISC_COMMAND>, <DFS_FILING_SYSTEM_VECTORS>
SELECT_DFS:
    jsr ZERO_SAVED_A
    pha
    lda #DFS_FSC_TAKEOVER
    jsr DFS_CALL_FSCV                       ; OSFSC 6 to the old filing system
    ldx #FSCV + 1 - FILEV
SELECT_DFS_VECTORS:
    lda DFS_FILING_SYSTEM_VECTORS,x                     ; FILEV-FSCV to the extended vector entries
    sta FILEV,x
    dex
    bpl SELECT_DFS_VECTORS
    lda #DFS_OSBYTE_EXTENDED_VECTORS
    jsr READ_OS_VARIABLE
    sty FS_SCRATCH+1
    stx FS_SCRATCH
    ldx #(FSCV + 2 - FILEV) / 2
    ldy #(FILEV - USERV) / 2 * 3    ; FILEV's three bytes in the extended vectors
SELECT_DFS_EXTENDED:
    ; The routines' addresses follow the vector table at DFS_FILING_SYSTEM_VECTORS, so Y indexes both.
    lda DFS_FILING_SYSTEM_VECTORS + (FSCV + 2 - FILEV) - (FILEV - USERV) / 2 * 3,y
    sta (FS_SCRATCH),y
    iny
    lda DFS_FILING_SYSTEM_VECTORS + (FSCV + 2 - FILEV) - (FILEV - USERV) / 2 * 3,y
    sta (FS_SCRATCH),y
    iny
    lda ROMSEL_COPY
    sta (FS_SCRATCH),y
    iny
    dex
    bne SELECT_DFS_EXTENDED
    stx DFS_CURRENT_DRIVE           ; drive 0
    sty DFS_CATALOGUE_DRIVE         ; Y = &30, no drive: read the catalogue again
    sty DFS_SELECTED_DRIVE
    ldx #DFS_SERVICE_VECTORS_CLAIMED
    jsr DFS_ISSUE_SERVICE_CALL
    jsr POINT_AT_PRIVATE_WORKSPACE                       ; FS_SCRATCH = the private workspace
    ldy #DFS_PRIVATE_SAVED
    lda (FS_SCRATCH),y
    bpl SELECT_DFS_INITIALISE
    pla
    pha
    beq SELECT_DFS_INITIALISE       ; a boot starts afresh
    ldy #DFS_PRIVATE_OWNER
    lda (FS_SCRATCH),y
    bmi SELECT_DFS_TUBE             ; the workspace is still the DFS's
    jsr CLAIM_STATIC_WORKSPACE                       ; claim it
    ldy #$00
SELECT_DFS_RESTORE:
    lda (FS_SCRATCH),y              ; &10C0-&10FF and &1100-&11BF from the copy
    cpy #<DFS_SAVED_VARIABLES
    bcc SELECT_DFS_CHANNEL_BLOCK
    sta DFS_WORKSPACE,y
    bcs SELECT_DFS_RESTORE_NEXT     ; always
SELECT_DFS_CHANNEL_BLOCK:
    sta DFS_CHANNELS,y
SELECT_DFS_RESTORE_NEXT:
    dey
    bne SELECT_DFS_RESTORE
    lda #DFS_CHANNEL_SIZE * DFS_CHANNEL_COUNT
SELECT_DFS_CHANNELS:
    tay                             ; each channel's buffer is lost
    pha
    lda #$FF - DFS_BUFFER_VALID - DFS_BUFFER_CHANGED
    jsr CLEAR_CHANNEL_FLAGS
    pla
    sta DFS_CHANNELS+DFS_CHANNEL_SECTOR+1,y ; a sector no disc has
    sbc #DFS_CHANNEL_SIZE - 1       ; carry is clear
    bne SELECT_DFS_CHANNELS
    beq SELECT_DFS_TUBE             ; always
SELECT_DFS_INITIALISE:
    jsr CLAIM_STATIC_WORKSPACE                       ; claim the workspace
    lda #'$'
    sta DFS_DEFAULT_DIRECTORY
    sta DFS_LIBRARY
    ldy #$00
    sty DFS_DEFAULT_DRIVE
    sty DFS_LIBRARY_DRIVE
    ldy #$00
    sty DFS_OPEN_CHANNELS
    sty DFS_NMI_CLAIMED
    ldy #$FF
    sty DFS_ENABLE
    sty DFS_MESSAGES_OFF
    sty DFS_BUFFER_TRANSFER
SELECT_DFS_TUBE:
    lda #DFS_OSBYTE_TUBE
    jsr READ_OS_VARIABLE
    txa
    eor #$FF
    sta DFS_NO_TUBE
    pla
    bne SELECT_DFS_DONE
    jsr READ_CATALOGUE                       ; read the catalogue of drive 0
    lda CATALOGUE_OPTION
    jsr SHIFT_RIGHT_4                       ; the boot option
    bne SELECT_DFS_BOOT
SELECT_DFS_DONE:
    rts
SELECT_DFS_BOOT:
    ldy #>DFS_BOOT_LOAD_COMMAND
    ldx #<DFS_BOOT_LOAD_COMMAND
    cmp #$02
    bcc SELECT_DFS_OSCLI            ; option 1
    beq SELECT_DFS_RUN
    ldx #<DFS_BOOT_EXEC_COMMAND         ; option 3
    bne SELECT_DFS_OSCLI            ; always
SELECT_DFS_RUN:
    ldx #<DFS_BOOT_RUN_COMMAND
SELECT_DFS_OSCLI:
    jmp OSCLI

;; The DFS's service call handler, which the NFS's handler passes each call to.
;;
;; It ignores every call when bits 0 and 1 of the 8271's status register, which always read 0 on an 8271, are not
;; both clear, so with no controller fitted, or when bit 6 of its ROM's byte in <ROM_WORKSPACE_TABLE> is set. Then:
;; - &01: claims absolute workspace up to &16FF, for the catalogue, the variables and the five buffers.
;; - &02: claims two pages of private workspace. It records the page, keeping bit 7 of the ROM's byte, and after a
;;   soft BREAK copies the DFS's workspace there if it still owned it, so the open files survive.
;; - &03: starts the DFS when no key or D is held.
;; - &04: looks the command up in the utilities' table, &09: answers *HELP, &0A: gives up the workspace, &12:
;;   selects the DFS for filing system 4, &08: OSWORD &7D-&7F.
;; In: A = the service call, X = the ROM's number, Y = the call's parameter
;; Out: A = 0 when the call is claimed, otherwise unchanged; Y = as the call returns it
;; Keeps: X
;; See: <DFS_SERVICE_ENTRY>
DFS_SERVICE_HANDLER:
    pha
    lda FDC_STATUS                  ; the 8271's status
    and #$03                        ; bits that an 8271 never sets
    bne DFS_SERVICE_PASS
    lda ROM_WORKSPACE_TABLE,x
    asl a
    bmi DFS_SERVICE_PASS            ; bit 6: the DFS is disabled
    pla
    cmp #DFS_SERVICE_ABSOLUTE_WORKSPACE
    bne DFS_SERVICE_PRIVATE_WORKSPACE_CHECK
    cpy #DFS_ABSOLUTE_TOP
    bcs DFS_SERVICE_ABSOLUTE_DONE
    ldy #DFS_ABSOLUTE_TOP
DFS_SERVICE_ABSOLUTE_DONE:
    rts
DFS_SERVICE_PRIVATE_WORKSPACE_CHECK:
    cmp #DFS_SERVICE_PRIVATE_WORKSPACE
    bne DFS_SERVICE_AUTO_BOOT_CHECK
    pha
    tya
    pha
    sta FS_SCRATCH+1                ; the private workspace's page
    asl a
    asl ROM_WORKSPACE_TABLE,x       ; carry = the byte's bit 7
    ror a                           ; the page, with that bit 7
    sta ROM_WORKSPACE_TABLE,x
    lda #$00
    sta FS_SCRATCH
    lda #DFS_OSBYTE_BREAK_TYPE
    jsr READ_OS_VARIABLE
    dex                             ; A = &FF after a soft BREAK, 0 after power-on, 1 after a hard BREAK
    txa
    ldy #DFS_PRIVATE_SAVED
    and (FS_SCRATCH),y              ; the copy is kept only through a soft BREAK
    sta (FS_SCRATCH),y
    php
    iny                             ; DFS_PRIVATE_OWNER
    plp
    bpl DFS_SERVICE_PRIVATE_NOT_OWNER
    lda (FS_SCRATCH),y
    bpl DFS_SERVICE_PRIVATE_NOT_OWNER
    jsr SAVE_WORKSPACE                       ; copy the workspace there
DFS_SERVICE_PRIVATE_NOT_OWNER:
    lda #$00
    sta (FS_SCRATCH),y
    jsr INITIALISE_FDC
    ldx ROMSEL_COPY
    pla
    tay
    .repeat DFS_PRIVATE_PAGES
    iny
    .endrepeat
DFS_SERVICE_PASS:
    pla
DFS_SERVICE_DONE:
    rts
DFS_SERVICE_AUTO_BOOT_CHECK:
    jsr SAVE_REGISTERS                       ; keep A, X and Y for the rest
    cmp #DFS_SERVICE_AUTO_BOOT
    bne DFS_SERVICE_COMMAND_CHECK
    sty DFS_BOOT_FLAG
    lda #DFS_OSBYTE_KEYBOARD_SCAN
    jsr OSBYTE
    txa
    bmi DFS_SERVICE_AUTO_BOOT_START ; no key: the DFS
    cmp #DFS_KEY_D
    bne DFS_SERVICE_DONE
    lda #DFS_OSBYTE_KEYS_PRESSED    ; D: note it as pressed, so it is not typed
    jsr OSBYTE
DFS_SERVICE_AUTO_BOOT_START:
    jmp START_DFS
DFS_SERVICE_COMMAND_CHECK:
    cmp #DFS_SERVICE_COMMAND
    bne DFS_SERVICE_SELECT_CHECK
    ldx #$71                        ; three before the utilities' table at &A566, from DFS_COMMAND_TABLE
DFS_SERVICE_COMMAND_SEARCH:
    jmp SCAN_COMMAND_TABLE
DFS_SERVICE_SELECT_CHECK:
    cmp #DFS_SERVICE_SELECT
    bne DFS_SERVICE_HELP_CHECK
    cpy #DFS_FILING_SYSTEM
    bne DFS_SERVICE_RETURN
    jmp DISC_COMMAND
DFS_SERVICE_HELP_CHECK:
    cmp #DFS_SERVICE_HELP
    bne DFS_SERVICE_STATIC_WORKSPACE_CHECK
    lda (TEXT_POINTER),y
    ldx #$9E                        ; three before the *HELP topics at &A593, from DFS_COMMAND_TABLE
    cmp #$0D
    bne DFS_SERVICE_COMMAND_SEARCH  ; *HELP with a topic
    tya
    inx                             ; the topics, two of them
    inx
    ldy #$02
    jmp PRINT_HELP
DFS_SERVICE_STATIC_WORKSPACE_CHECK:
    jsr ZERO_SAVED_A
    cmp #DFS_SERVICE_STATIC_WORKSPACE
    bne DFS_SERVICE_OSWORD_CHECK
    jsr POINT_AT_PRIVATE_WORKSPACE
    ldy #DFS_PRIVATE_OWNER
    lda (FS_SCRATCH),y
    bpl DFS_SERVICE_STATIC_PASS     ; another ROM has it already
    ldy #$00
    jsr ENSURE_FILES                ; write every buffer
    jsr SAVE_WORKSPACE                       ; copy the workspace to the private workspace
    ldy #DFS_PRIVATE_OWNER
    lda #$00
    sta (FS_SCRATCH),y
    rts
DFS_SERVICE_STATIC_PASS:
    lda #DFS_SERVICE_STATIC_WORKSPACE
DFS_SERVICE_RESTORE_A:
    tsx
    sta STACK+5,x                   ; the A in the SAVE_REGISTERS frame
DFS_SERVICE_RETURN:
    rts
DFS_SERVICE_OSWORD_CHECK:
    cmp #DFS_SERVICE_OSWORD
    bne DFS_SERVICE_RESTORE_A
    ldy OS_A
    bmi DFS_SERVICE_RESTORE_A
    cpy #DFS_OSWORD_CYCLE
    bcc DFS_SERVICE_RESTORE_A
    ldx OS_X
    stx FS_SCRATCH
    ldx OS_Y
    stx FS_SCRATCH+1
    iny
    bpl OSWORD_READ_DISC_INFO       ; &7D and &7E
;; OSWORD &7F: gives the 8271 a command with its parameters, transfers the data, and returns its result.
;;
;; The block holds the drive, or a negative number for the current one; the data's four-byte address; the number of
;; parameters; the command; the parameters; and then a byte for the result, 0 for success. The command's top bits
;; are adjusted for drives 1 and 3. Bit 4 of the command says which way the data goes: set from the disc. The NMI
;; routine for that direction, through the Tube or not, is copied to &0D00, and released afterwards with the Tube.
;; In: FS_SCRATCH/FS_SCRATCH+1 = the OSWORD block
;; Uses: A, X, Y, DFS_IO_ADDRESS, DFS_IO_ADDRESS+1
;; See: <FDC_SEND_DRIVE_COMMAND>, <SET_UP_NMI_CODE>
OSWORD_DISC_ACCESS:
    cli
    ldy #$00
    lda (FS_SCRATCH),y
    bmi OSWORD_DISC_ACCESS_DRIVE
    jsr SET_DRIVE                       ; select the drive
OSWORD_DISC_ACCESS_DRIVE:
    jsr SELECT_DRIVE                       ; start it
    iny
    ldx #$02
    jsr COPY_BLOCK_ADDRESS                       ; the data's address
    lda (FS_SCRATCH),y
    iny
    pha                             ; the number of parameters
    lda (FS_SCRATCH),y
    pha
    jsr FDC_SEND_DRIVE_COMMAND                       ; the command, to the 8271
    pla
    jsr SHIFT_RIGHT_4
    and #$01                        ; 1 to read from the disc
    jsr START_TUBE_TRANSFER                       ; carry = clear through the Tube
    rol a
    adc #$03                        ; NMI routine 3-6: 3 or 4 write, 5 or 6 read, the lower through the Tube
    jsr SET_UP_NMI_CODE
    lda DFS_IO_ADDRESS
    sta NMI_WORKSPACE+6             ; where the NMI routine puts or takes the data
    lda DFS_IO_ADDRESS+1
    sta NMI_WORKSPACE+7
    ldy #$07
    pla
    tax
    beq OSWORD_DISC_ACCESS_RESULT
OSWORD_DISC_ACCESS_PARAMETERS:
    lda (FS_SCRATCH),y
    jsr FDC_SEND_PARAMETER                       ; to the 8271's parameter register
    iny
    dex
    bne OSWORD_DISC_ACCESS_PARAMETERS
OSWORD_DISC_ACCESS_RESULT:
    jsr FDC_READ_RESULT                       ; wait, and read the 8271's result register
    sta (FS_SCRATCH),y
    jmp RELEASE_NMI_AND_TUBE                       ; release the NMI and the Tube
;; OSWORD &7D and &7E: reads the current drive's catalogue cycle number, or the size of its disc in bytes.
;;
;; &7D writes the catalogue's sequence number to the block's first byte; &7E writes the disc's size, the number of
;; sectors times 256, as four bytes.
;; In: Y = &7E for OSWORD &7D, &7F for &7E (the OSWORD number plus one), FS_SCRATCH/FS_SCRATCH+1 = the OSWORD block
;; Uses: A, Y
;; Errors: the disc errors
OSWORD_READ_DISC_INFO:
    jsr SELECT_DEFAULTS                       ; the current drive
    jsr FETCH_CATALOGUE                       ; and its catalogue
    iny
    bmi OSWORD_READ_DISC_SIZE
    ldy #$00
    lda CATALOGUE_SEQUENCE
    sta (FS_SCRATCH),y
    rts
OSWORD_READ_DISC_SIZE:
    lda #$00
    tay
    sta (FS_SCRATCH),y
    iny
    lda CATALOGUE_SECTORS
    sta (FS_SCRATCH),y
    iny
    lda CATALOGUE_OPTION
    and #$03                        ; the sector count's top bits
    sta (FS_SCRATCH),y
    iny
    lda #$00
    sta (FS_SCRATCH),y
    rts

;; OSFILE for the DFS: copies the control block, then runs the routine for the reason code.
;;
;; The name's address goes to FS_SCRATCH+10/FS_SCRATCH+11. Of the four addresses that follow, the low halves go to
;; FS_SCRATCH+12..FS_SCRATCH+19 and the high halves to &1074-&107B. Wildcards are not allowed in the name. A reason
;; code without a routine returns A = 0.
;; In: A = the reason code, &FF to 6, X/Y = the control block
;; Out: A = the routine's result, the file's type
;; Keeps: X, Y
;; See: <OSFILE_ROUTINES_LOW>, <OSFILE_ROUTINES_HIGH>
DFS_OSFILE:
    jsr SAVE_X_Y                       ; keep X and Y for the caller
    pha
    jsr DISABLE_WILDCARDS
    stx FS_SCRATCH
    stx DFS_FILE_BLOCK
    sty FS_SCRATCH+1
    sty DFS_FILE_BLOCK+1
    ldx #$00
    ldy #$00
    jsr COPY_BLOCK_WORD                       ; the name's address
DFS_OSFILE_BLOCK:
    jsr COPY_BLOCK_ADDRESS                       ; and each address
    cpy #DFS_FILE_BLOCK_SIZE
    bne DFS_OSFILE_BLOCK
    pla
    tax
    inx                             ; &FF to 6 as 0 to 7
    cpx #DFS_FILE_CALLS
    bcs DFS_RETURN_ZERO
    lda OSFILE_ROUTINES_HIGH,x
    pha
    lda OSFILE_ROUTINES_LOW,x
    pha
;; Returns A = 0; after a routine's address has been pushed, this enters it with A = 0.
;; Out: A = 0
DFS_RETURN_ZERO:
    lda #$00
    rts

;; OSFSC for the DFS: runs the routine for the reason code, 0-8, with A, X and Y as they came.
;;
;; A reason code beyond 8 returns A = 0.
;; In: A = the reason code, X, Y = its parameters
;; See: <FSC_ROUTINES_LOW>, <FSC_ROUTINES_HIGH>
DFS_OSFSC:
    cmp #DFS_FSC_CALLS
    bcs DFS_RETURN_ZERO
    stx DFS_FSC_X
    tax
    lda FSC_ROUTINES_HIGH,x
    pha
    lda FSC_ROUTINES_LOW,x
    pha
    txa
    ldx DFS_FSC_X
DFS_OSFSC_RETURN:
    rts

;; OSGBPB for the DFS: transfers bytes to or from an open file, or reads the disc's title, the directories or the file
;; names.
;;
;; Reason codes beyond 8 return at once with nothing changed. The control block is updated as the Advanced User Guide
;; describes, and the Tube is released afterwards.
;; In: A = the reason code, X/Y = the control block
;; Out: A = 0, carry = set when the transfer could not be completed
;; Keeps: X, Y
;; Errors: "Channel", and those of OSBGET and OSBPUT
;; See: <GBPB_TRANSFER>
DFS_OSGBPB:
    cmp #DFS_GBPB_CALLS
    bcs DFS_OSFSC_RETURN
    jsr SAVE_REGISTERS                       ; keep X and Y for the caller
    jsr ZERO_SAVED_A
    stx DFS_GBPB_BLOCK_ADDRESS
    sty DFS_GBPB_BLOCK_ADDRESS+1
    tay
    jsr GBPB_TRANSFER
    php
    jsr DFS_RELEASE_TUBE                       ; release the Tube
    plp
    rts

;; Carries out an OSGBPB call: copies the block, starts any Tube transfer, then calls the reason code's routine once,
;; or once for each byte or name.
;;
;; <GBPB_FLAGS> gives each reason code three bits: bit 0, keep PTR# rather than set it from the block; bit 1, a transfer
;; to or from a file; bit 2, the Tube transfer type (1 to the parasite). The count is turned into its negative and
;; counted up to zero. For a file the block's pointer is set from or read into PTR#, and stepped with each byte.
;; Afterwards the block gets the bytes not transferred, the address and the pointer that come next.
;; In: Y = the reason code
;; Out: carry = set when the routine stopped the transfer early
;; Uses: A, X, Y, DFS_GBPB_BLOCK..DFS_GBPB_BLOCK+12, DFS_GBPB_PTR..DFS_GBPB_PTR+3
;; See: <GBPB_ROUTINES_LOW>, <GBPB_ROUTINES_HIGH>
GBPB_TRANSFER:
    lda GBPB_ROUTINES_LOW,y
    sta DFS_GBPB_ROUTINE
    lda GBPB_ROUTINES_HIGH,y
    sta DFS_GBPB_ROUTINE+1
    lda GBPB_FLAGS,y
    lsr a
    php                             ; bit 0: keep PTR#
    lsr a
    php                             ; bit 1: a file
    sta DFS_GBPB_TUBE_TYPE
    jsr GET_GBPB_BLOCK
    ldy #DFS_GBPB_BLOCK_SIZE - 1
GBPB_TRANSFER_COPY:
    lda (DFS_GBPB_BLOCK_POINTER),y
    sta DFS_GBPB_BLOCK,y
    dey
    bpl GBPB_TRANSFER_COPY
    lda DFS_GBPB_ADDRESS+2
    and DFS_GBPB_ADDRESS+3
    ora DFS_NO_TUBE
    clc
    adc #$01                        ; zero, and carry set, for &FFFFxxxx or no Tube
    beq GBPB_TRANSFER_TUBE
    jsr DFS_CLAIM_TUBE                       ; claim the Tube
    clc
    lda #$FF
GBPB_TRANSFER_TUBE:
    sta DFS_GBPB_TUBE
    lda DFS_GBPB_TUBE_TYPE
    bcs GBPB_TRANSFER_KIND
    ldx #<DFS_GBPB_ADDRESS
    ldy #>DFS_GBPB_ADDRESS
    jsr TUBE_ENTRY_TRANSFER                       ; start the Tube transfer at the address
GBPB_TRANSFER_KIND:
    plp
    bcs GBPB_TRANSFER_FILE
    plp
;; Calls OSGBPB's routine for the reason code, through DFS_GBPB_ROUTINE.
;; See: <GBPB_TRANSFER>
CALL_GBPB_ROUTINE:
    jmp (DFS_GBPB_ROUTINE)
GBPB_TRANSFER_FILE:
    ldx #$03
GBPB_TRANSFER_POINTER_IN:
    lda DFS_GBPB_POINTER,x
    sta DFS_GBPB_PTR,x
    dex
    bpl GBPB_TRANSFER_POINTER_IN
    ldx #DFS_GBPB_PTR
    ldy DFS_GBPB_HANDLE
    lda #$00
    plp
    bcs GBPB_TRANSFER_READ_POINTER
    jsr WRITE_SEQUENTIAL_POINTER    ; PTR# from the block
GBPB_TRANSFER_READ_POINTER:
    jsr READ_POINTER_OR_LENGTH      ; and the block's pointer from PTR#
    ldx #$03
GBPB_TRANSFER_POINTER_OUT:
    lda DFS_GBPB_PTR,x
    sta DFS_GBPB_POINTER,x
    dex
    bpl GBPB_TRANSFER_POINTER_OUT
GBPB_TRANSFER_LOOP_START:
    jsr COMPLEMENT_GBPB_COUNT
    bmi GBPB_TRANSFER_COUNT         ; always: X is &FF
GBPB_TRANSFER_LOOP:
    ldy DFS_GBPB_HANDLE
    jsr CALL_GBPB_ROUTINE
    bcs GBPB_TRANSFER_END
    ldx #DFS_GBPB_POINTER - DFS_GBPB_BLOCK
    jsr INCREMENT_GBPB_FIELD
GBPB_TRANSFER_COUNT:
    ldx #DFS_GBPB_COUNT - DFS_GBPB_BLOCK
    jsr INCREMENT_GBPB_FIELD
    bne GBPB_TRANSFER_LOOP
    clc
GBPB_TRANSFER_END:
    php
    jsr COMPLEMENT_GBPB_COUNT       ; the count left, from its negative
    ldx #DFS_GBPB_COUNT - DFS_GBPB_BLOCK
    jsr INCREMENT_GBPB_FIELD
    ldy #DFS_GBPB_BLOCK_SIZE - 1
    jsr GET_GBPB_BLOCK
GBPB_TRANSFER_COPY_BACK:
    lda DFS_GBPB_BLOCK,y
    sta (DFS_GBPB_BLOCK_POINTER),y
    dey
    bpl GBPB_TRANSFER_COPY_BACK
    plp
    rts

;; OSGBPB 8: reads file names from the current directory, a name for each count in the block.
;;
;; The block's pointer is the offset in the catalogue to search from, 0 at first.
;; See: <READ_NEXT_FILE_NAME>
READ_FILE_NAMES:
    jsr SELECT_DEFAULTS                       ; the current directory and drive
    jsr ENSURE_CATALOGUE                       ; and the catalogue
    lda #<READ_NEXT_FILE_NAME
    sta DFS_GBPB_ROUTINE
    lda #>READ_NEXT_FILE_NAME
    sta DFS_GBPB_ROUTINE+1
    bne GBPB_TRANSFER_LOOP_START    ; always
;; Puts the next file name in the current directory into OSGBPB's data: its length, 7, then its seven characters.
;;
;; It searches from the catalogue offset in the block's pointer, and leaves the pointer seven bytes into the entry,
;; so that the pointer's step after each name moves it to the next. The handle's byte gets the catalogue's cycle
;; number. Directory letters match either case.
;; Out: carry = set when there are no more names
;; Uses: A, X, Y, FS_SCRATCH
READ_NEXT_FILE_NAME:
    ldy DFS_GBPB_POINTER
READ_NEXT_FILE_NAME_SEARCH:
    cpy CATALOGUE_SIZE
    bcs READ_NEXT_FILE_NAME_END
    lda CATALOGUE_NAMES+15,y        ; the file's directory
    jsr CHECK_LETTER                       ; carry = clear for a letter
    eor DFS_NAME_DIRECTORY          ; the directory wanted
    bcs READ_NEXT_FILE_NAME_COMPARE
    and #$DF                        ; a letter in either case
READ_NEXT_FILE_NAME_COMPARE:
    and #$7F                        ; not the lock
    beq READ_NEXT_FILE_NAME_FOUND
    jsr NEXT_ENTRY                       ; the next entry
    bne READ_NEXT_FILE_NAME_SEARCH
READ_NEXT_FILE_NAME_FOUND:
    lda #$07
    jsr PUT_DATA_BYTE
    sta FS_SCRATCH
READ_NEXT_FILE_NAME_COPY:
    lda CATALOGUE_NAMES+8,y
    jsr PUT_DATA_BYTE
    iny
    dec FS_SCRATCH
    bne READ_NEXT_FILE_NAME_COPY
    clc
READ_NEXT_FILE_NAME_END:
    sty DFS_GBPB_POINTER
    lda CATALOGUE_SEQUENCE
    sta DFS_GBPB_HANDLE
    rts

;; OSGBPB 5: puts the current disc's title and boot option into OSGBPB's data: 12, the title's twelve characters, the
;; option, and the drive.
;; Uses: A, X, Y
READ_TITLE_AND_OPTION:
    jsr SELECT_DEFAULTS                       ; the current drive
    jsr ENSURE_CATALOGUE                       ; and its catalogue
    lda #$0C
    jsr PUT_DATA_BYTE
    ldy #$00
READ_TITLE_LOOP:
    cpy #$08
    bcs READ_TITLE_SECOND
    lda CATALOGUE_NAMES,y           ; the title's first eight characters
    bcc READ_TITLE_PUT              ; always
READ_TITLE_SECOND:
    lda CATALOGUE_INFO - 8,y        ; and its last four
READ_TITLE_PUT:
    jsr PUT_DATA_BYTE
    iny
    cpy #$0C
    bne READ_TITLE_LOOP
    lda CATALOGUE_OPTION
    jsr SHIFT_RIGHT_4                       ; the boot option
    jsr PUT_DATA_BYTE
    lda DFS_CURRENT_DRIVE
    jmp PUT_DATA_BYTE

;; OSGBPB 6: puts the current directory into OSGBPB's data: 1, the drive's digit, 1, the directory's letter.
;; Uses: A, X
READ_CURRENT_DIRECTORY:
    jsr PUT_LENGTH_ONE
    lda DFS_DEFAULT_DRIVE
    ora #'0'
    jsr PUT_DATA_BYTE
    jsr PUT_LENGTH_ONE
    lda DFS_DEFAULT_DIRECTORY
    bne PUT_DATA_BYTE               ; always
;; OSGBPB 7: puts the library into OSGBPB's data: 1, the drive's digit, 1, the directory's letter.
;; Uses: A, X
READ_LIBRARY:
    jsr PUT_LENGTH_ONE
    lda DFS_LIBRARY_DRIVE
    ora #'0'
    jsr PUT_DATA_BYTE
    jsr PUT_LENGTH_ONE
    lda DFS_LIBRARY
    bne PUT_DATA_BYTE               ; always

;; Points DFS_GBPB_DATA_POINTER at OSGBPB's data in the I/O processor.
;; Out: X = 0, for (DFS_GBPB_DATA_POINTER,x)
;; Keeps: A, Y
SET_DATA_POINTER:
    pha
    lda DFS_GBPB_ADDRESS
    sta DFS_GBPB_DATA_POINTER
    lda DFS_GBPB_ADDRESS+1
    sta DFS_GBPB_DATA_POINTER+1
    ldx #$00
    pla
    rts

;; Moves OSGBPB's data address on by one.
;; Keeps: A, X, Y
NEXT_DATA_ADDRESS:
    jsr SAVE_REGISTERS
    ldx #DFS_GBPB_ADDRESS - DFS_GBPB_BLOCK
;; Adds one to a four-byte field of OSGBPB's copy of the block.
;; In: X = the field's offset in DFS_GBPB_BLOCK
;; Out: zero = set when the field has wrapped round to 0
;; Uses: X, Y
INCREMENT_GBPB_FIELD:
    ldy #$04
INCREMENT_GBPB_FIELD_LOOP:
    inc DFS_GBPB_BLOCK,x
    bne INCREMENT_GBPB_FIELD_DONE
    inx
    dey
    bne INCREMENT_GBPB_FIELD_LOOP
INCREMENT_GBPB_FIELD_DONE:
    rts

;; Inverts each bit of OSGBPB's count, so that one more makes its negative, or after the transfer the count left.
;; Out: X = &FF
;; Uses: A
;; Keeps: Y
COMPLEMENT_GBPB_COUNT:
    ldx #$03
COMPLEMENT_GBPB_COUNT_LOOP:
    lda #$FF
    eor DFS_GBPB_COUNT,x
    sta DFS_GBPB_COUNT,x
    dex
    bpl COMPLEMENT_GBPB_COUNT_LOOP
    rts

;; Points DFS_GBPB_BLOCK_POINTER at the caller's OSGBPB control block.
;; Uses: A
;; Keeps: X, Y
GET_GBPB_BLOCK:
    lda DFS_GBPB_BLOCK_ADDRESS
    sta DFS_GBPB_BLOCK_POINTER
    lda DFS_GBPB_BLOCK_ADDRESS+1
    sta DFS_GBPB_BLOCK_POINTER+1
GET_GBPB_BLOCK_DONE:
    rts

;; Puts a 1, the length of a drive's or a directory's name, into OSGBPB's data.
;; Uses: A, X
;; Keeps: Y
PUT_LENGTH_ONE:
    lda #$01
    bne PUT_DATA_BYTE               ; always
;; OSGBPB 3 and 4: reads one byte from the file into OSGBPB's data.
;; In: Y = the file's handle
;; Out: carry = set at the end of the file
;; Uses: A, X
;; See: <DFS_OSBGET>
GET_BYTES:
    jsr DFS_OSBGET
    bcs GET_GBPB_BLOCK_DONE
;; Puts a byte into OSGBPB's data, through the Tube or into the I/O processor's memory, and moves the address on.
;; In: A = the byte
;; Uses: X
;; Keeps: A, Y
PUT_DATA_BYTE:
    bit DFS_GBPB_TUBE
    bpl PUT_DATA_BYTE_IO
    sta TUBE_R3_DATA                ; to the parasite through register 3
    bmi NEXT_DATA_ADDRESS           ; always
PUT_DATA_BYTE_IO:
    jsr SET_DATA_POINTER
    sta (DFS_GBPB_DATA_POINTER,x)
    jmp NEXT_DATA_ADDRESS

;; OSGBPB 1 and 2: writes the next byte of OSGBPB's data to the file.
;; In: Y = the file's handle
;; Out: carry = clear
;; Uses: A, X
;; See: <DFS_OSBPUT>
PUT_BYTES:
    jsr GET_DATA_BYTE
    jsr DFS_OSBPUT
    clc
    rts
;; Takes the next byte of OSGBPB's data, through the Tube or from the I/O processor's memory, and moves the address on.
;; Out: A = the byte
;; Uses: X
;; Keeps: Y
GET_DATA_BYTE:
    bit DFS_GBPB_TUBE
    bpl GET_DATA_BYTE_IO
    lda TUBE_R3_DATA                ; from the parasite through register 3
    jmp NEXT_DATA_ADDRESS
GET_DATA_BYTE_IO:
    jsr SET_DATA_POINTER
    lda (DFS_GBPB_DATA_POINTER,x)
    jmp NEXT_DATA_ADDRESS

;; OSFSC 8: a * command is about to be processed. Counts down *ENABLE, and turns wildcards off.
;;
;; *ENABLE sets the count to 1, so the command after it is enabled and the one after that is not.
;; Uses: A
;; See: <DISABLE_WILDCARDS>
COMMAND_STARTING:
    bit DFS_ENABLE
    bmi DISABLE_WILDCARDS
    dec DFS_ENABLE
;; Turns wildcards off, so that "#" and "*" in a name match only themselves.
;; Out: A = &FF
;; Keeps: X, Y
;; Entry: SET_WILDCARD_CHARACTER = sets only the one-character wildcard, to A
DISABLE_WILDCARDS:
    lda #$FF
    sta DFS_WILDCARD_STRING
SET_WILDCARD_CHARACTER:
    sta DFS_WILDCARD_CHARACTER
    rts
