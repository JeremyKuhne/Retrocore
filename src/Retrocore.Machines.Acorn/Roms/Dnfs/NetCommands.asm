;; The NFS's * commands, its catalogue, the rest of its filing system calls, and its Econet OSBYTE and OSWORD calls
;; ($8841-$8FEF).
;;
;; - The filing system calls: OSFILE's reasons 1-6 (<NFS_OSFILE_INFO>), <NFS_OSARGS>, <NFS_OSFIND>, <NFS_OSGBPB>,
;;   and the FSCV calls for *OPT, EOF#, *RUN, unrecognised commands and *CAT.
;; - The NFS's own commands in <NFS_COMMAND_TABLE> (*I AM, *EX and *BYE; anything else goes to the file server), the
;;   catalogue that *CAT and *EX print, and the routines that act on a reply's command code: logging on, setting the
;;   directories, running a file.
;; - OSBYTE &32-&34 and OSWORD &10-&14, the Econet calls, which work on the transmit and receive control blocks in
;;   the NFS's private workspace.
;;
;; Every request to the file server is built in <NFS_REQUEST> (&0F00): the port the reply should come back to, the
;; function code, the handles of the user's root directory, the current directory and the library, then the
;; request's own data from &0F05. <FS_COMMAND> and the routines around it send it and wait for the reply, which arrives
;; at &0F03: the command code (what the client should do next), the return code (0, or an error, which they raise),
;; then the reply's data, again from &0F05. The file server's handles are one-bit masks; the NFS gives its callers
;; the handles &20-&27 instead (<HANDLE_IN_A_TO_MASK> and <MASK_TO_HANDLE> convert them).

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

NFS_CR = $0D                        ;; carriage return, which ends names and commands sent to the file server

; The file server's function codes, in <NFS_REQUEST_FUNCTION>.
NFS_FS_EXAMINE = $03                ;; list a directory's entries, from a given one, in a given format
NFS_FS_LOAD_COMMAND = $05           ;; load the file a * command names, to run it
NFS_FS_OPEN = $06                   ;; open a file; the reply holds its handle
NFS_FS_CLOSE = $07                  ;; close a file, or every file for handle 0
NFS_FS_GET_BYTES = $0A              ;; read a group of bytes from an open file, for OSGBPB 3 and 4
NFS_FS_PUT_BYTES = $0B              ;; write a group of bytes to an open file, for OSGBPB 1 and 2
NFS_FS_READ_ARGUMENTS = $0C         ;; read an open file's pointer or extent
NFS_FS_SET_ARGUMENTS = $0D          ;; set an open file's pointer
NFS_FS_EOF = $11                    ;; ask whether an open file's pointer is at its end
NFS_FS_READ_INFO = $12              ;; read an object's information; the first data byte says which
NFS_FS_SET_INFO = $13               ;; set an object's addresses or access; the first data byte says which, as OSFILE
NFS_FS_DELETE = $14                 ;; delete an object
NFS_FS_READ_ENVIRONMENT = $15       ;; read the disc's title and the names of the current directory and library
NFS_FS_SET_BOOT_OPTION = $16        ;; set the user's boot option

; Arguments of the requests above.
NFS_FS_INFO_DIRECTORY = 6           ;; NFS_FS_READ_INFO: a directory's name, ownership and cycle number
NFS_FS_EXAMINE_LONG = 1             ;; NFS_FS_EXAMINE: entries as text, as *EX prints them, one to a line
NFS_FS_EXAMINE_NAMES = 2            ;; NFS_FS_EXAMINE: each name after its length, as OSGBPB 8 returns them
NFS_FS_EXAMINE_SHORT = 3            ;; NFS_FS_EXAMINE: entries as text, as *CAT prints them, four to a line
NFS_FS_NAME_LENGTH = 10             ;; the length of a name in the file server's replies, padded with spaces
NFS_FS_TITLE_LENGTH = 16            ;; the length of a disc's title in the file server's replies

; Econet ports and control bytes.
NFS_CONTROL_TRANSMIT = $80          ;; the control byte the NFS transmits its requests and data with

; The receive control blocks that OSWORD &11 opens, in the second page of the NFS's private workspace.
NFS_RECEIVE_BLOCK_SIZE = 12         ;; the size of each receive control block, from offset 0 of the page
NFS_RECEIVE_BLOCKS = 18             ;; the number of receive control blocks
NFS_FIRST_OPENED_BLOCK = 3          ;; the first block OSWORD &11 offers when asked for any free one

; Offsets in the first page of the NFS's private workspace (<NFS_WORKSPACE_PAGE>).
NFS_TRANSMIT_OFFSET = $6F           ;; OSWORD &10's transmit control block, 16 bytes
NFS_TRANSMIT_SIZE = 16              ;; the size of OSWORD &10's control block
NFS_ARGUMENTS_SIZE_OFFSET = $7F     ;; the length of the last remote procedure call's arguments
NFS_ARGUMENTS_OFFSET = $80          ;; the arguments themselves

; Offsets in the second page (<NFS_BLOCKS_PAGE>).
NFS_OSWORD_14_START = $1C           ;; the buffer start of the control block OSWORD &14 transmits from offset &18
NFS_OSWORD_14_END = $20             ;; that control block's buffer end

; The Tube host code's entry at &0406 (<TUBE_ENTRY_TRANSFER>).
NFS_TUBE_CLAIM = $C3                ;; claims the Tube for the NFS, as user 3
NFS_TUBE_RELEASE = $83              ;; releases the NFS's claim
NFS_TUBE_TO_PARASITE = 1            ;; starts a transfer into the second processor's memory, through TUBE_R3_DATA
NFS_TUBE_EXECUTE = 4                ;; starts the second processor executing at an address

NFS_OSBYTE_CLOSE_FILES = $77        ;; OSBYTE &77: close the *SPOOL and *EXEC files

NFS_ERROR_INDEX_BAD_OPTION = 7      ;; the index <NFS_ERROR> raises error &CB, "Bad Option", for
NFS_CASE_MASK = $DF                 ;; clears bit 5, so that a letter matches in either case
NFS_RUN_REQUEST_LENGTH = $4A        ;; the bytes NFS_RUN_COMMAND sends from &0F05: the command, and whatever follows it

; The NFS's variables in pages &0D and &0E, as this part uses them.
NFS_COMMAND_TAIL = $0E0A            ;; the address of the text after the name of the file last run, for OSARGS 1
NFS_RUN_BLOCK = $0E10               ;; the OSFILE control block that NFS_RUN_COMMAND loads a file with

; The request buffer: requests are built in page &0F, and replies arrive in it from &0F03.
NFS_INFO_NAME = $0F08               ;; NFS_FS_INFO_DIRECTORY's reply: the directory's name, 10 characters
NFS_INFO_OWNER = $0F12              ;; NFS_FS_INFO_DIRECTORY's reply: 0 when the user owns the directory
NFS_INFO_CYCLE = $0F13              ;; NFS_FS_INFO_DIRECTORY's reply: the directory's cycle number
NFS_ENVIRONMENT_TITLE = $0F06       ;; NFS_FS_READ_ENVIRONMENT's reply: the disc's title, 16 characters
NFS_ENVIRONMENT_CSD = $0F16         ;; NFS_FS_READ_ENVIRONMENT's reply: the current directory's name
NFS_ENVIRONMENT_LIBRARY = $0F20     ;; NFS_FS_READ_ENVIRONMENT's reply: the library's name

; Zero page: Econet's &90-&9F and the filing system scratch space, as this part uses them.
NFS_COLUMN = FS_SCRATCH + 9         ;; PRINT_REPLY_LIST's column, 0-3, or negative to print one entry to a line
NFS_COPY_SOURCE = FS_SCRATCH        ;; COPY_REPLY_TO_CALLER: the index of the next byte from &0F05
NFS_COPY_DESTINATION = FS_SCRATCH + 1 ;; COPY_REPLY_TO_CALLER: the index of the next byte at NFS_NAME_POINTER
NFS_COPY_COUNT = FS_SCRATCH + 2     ;; COPY_REPLY_TO_CALLER: the bytes left to copy
NFS_ADJUST_SIGN = FS_SCRATCH + 2    ;; ADJUST_GBPB_FIELD: bit 7 set to subtract, clear to add
NFS_EXAMINE_START = FS_SCRATCH + 4  ;; the catalogue: the number of the first entry asked for
NFS_EXAMINE_COUNT = FS_SCRATCH + 5  ;; the catalogue: the number of entries asked for at a time
NFS_EXAMINE_FORMAT = FS_SCRATCH + 7 ;; the catalogue: NFS_FS_EXAMINE_LONG or NFS_FS_EXAMINE_SHORT
NFS_DIVISOR = FS_SCRATCH + 8        ;; PRINT_DECIMAL_DIGIT's power of ten
NFS_GBPB_TUBE = OS_COMMAND_WORKSPACE + 1 ;; OSGBPB 5-8: nonzero to send the data over the Tube
NFS_OSWORD_SAVED = OS_COMMAND_WORKSPACE + 2 ;; &AA-&AC, which the OSWORD calls save in the workspace and use
NFS_RECEIVE_NUMBER = OS_COMMAND_WORKSPACE + 2 ;; OSWORD &11: the receive block the caller asked for
NFS_OSWORD_POINTER = OS_COMMAND_WORKSPACE + 3 ;; the OSWORD calls' pointer into the NFS's workspace
NFS_HANDLE_INDEX = OS_COMMAND_WORKSPACE ;; OSWORD &13: the handle being written, 3 down to 1

; The NFS's own control block in &C0-&CB, which it sends requests and data from and receives replies into.

;; Lays out an entry of <NFS_COMMAND_TABLE>: the command's name, then its handler's address less one, high byte first.
;;
;; The high byte has bit 7 set, as every address in the ROM does, which ends the name.
;; Parameters:
;;   handler = the handler's address
;;   name = the command's name in capitals, or nothing for the entry that matches anything
;;   ending = a byte the command must be followed by, or nothing
.macro NFS_COMMAND handler, name, ending
.ifnblank name
    .byte name
.endif
.ifnblank ending
    .byte ending
.endif
    .byte >(handler-1), <(handler-1)
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; OSFILE, OSARGS and OSFIND
; ---------------------------------------------------------------------------------------------------------------------

;; Copies a file's load and execution addresses and its length from a load reply into the OSFILE control block.
;;
;; The reply holds the load address at &0F05, the execution address at &0F09 and three bytes of length at &0F0D;
;; they go to bytes 2-12 of the control block, and X to byte 13, the length's top byte. Falls into
;; <SUBTRACT_4_FROM_Y>.
;; In:    X = the length's top byte, NFS_CALL_XY = the OSFILE control block
;; Out:   Y = &FD, carry = clear
;; Uses:  A
COPY_FILE_INFO_TO_BLOCK:
    ldy #$0D
    txa
COPY_FILE_INFO_TO_BLOCK_LOOP:
    sta (NFS_CALL_XY),y
    lda NFS_REQUEST+2,y             ; the reply byte for the next block byte down
    dey
    cpy #$02
    bcs COPY_FILE_INFO_TO_BLOCK_LOOP
;; Subtracts 4 from Y, to step back from one four-byte field of a control block to the one before.
;; Out:   Y = Y - 4 (Y - 3 from SUBTRACT_3_FROM_Y)
;; Keeps: A, X, carry
;; Entry: SUBTRACT_3_FROM_Y = subtracts 3
SUBTRACT_4_FROM_Y:
    dey
SUBTRACT_3_FROM_Y:
    dey
    dey
    dey
    rts

;; Sends the memory from NFS_FILE_START to NFS_FILE_END to the file server, block by block.
;;
;; Each block is at most the size the server gave (&0F06-&0F07), and is transmitted to port A. After each block but
;; the last it opens the control block at &C0 for receiving on NFS_PORT_ACKNOWLEDGE, into &0F04, and waits for the
;; server's acknowledgement (<AWAIT_RECEPTION>); after the last it leaves the control block set to receive on
;; NFS_SAVE_PORT for the caller to wait on. Nothing is sent when the start and end are already equal.
;; In:    A = the server's data port, NFS_FILE_START, NFS_FILE_END, NFS_REPLY_DATA+1 = the largest block
;;          (two bytes), NFS_SAVE_PORT
;; Out:   carry = set once the last block has been sent (unchanged if there was nothing to send),
;;          Y = NFS_CALL_XY+1
;; Uses:  X, NFS_FILE_START (moved past the data), NFS_FS_BLOCK..NFS_FS_BLOCK_END+3
;; Keeps: A
;; See:   <NFS_EOF_RETURN>
SEND_DATA_BLOCKS:
    pha
    jsr NFS_COMPARE_ADDRESSES                       ; is the start the same as the end?
    beq NFS_EOF_RETURN
SEND_DATA_BLOCKS_LOOP:
    lda #$00                        ; push the largest block as four bytes, low byte last
    pha
    pha
    tax
    lda NFS_REPLY_DATA+2
    pha
    lda NFS_REPLY_DATA+1
    pha
    ldy #$04
    clc
SEND_DATA_BLOCKS_RANGE:
    lda NFS_FILE_START,x        ; the block runs from the next byte to send
    sta NFS_FS_BLOCK_START,x
    pla
    adc NFS_FILE_START,x        ; for the largest block's length
    sta NFS_FS_BLOCK_END,x
    sta NFS_FILE_START,x
    inx
    dey
    bne SEND_DATA_BLOCKS_RANGE
    sec
SEND_DATA_BLOCKS_COMPARE:
    lda a:NFS_FILE_START,y      ; compare the new start with the end
    sbc a:NFS_FILE_END,y
    iny
    dex
    bne SEND_DATA_BLOCKS_COMPARE
    bcc SEND_DATA_BLOCKS_TRANSMIT   ; there is more to send after this block
    ldx #$03
SEND_DATA_BLOCKS_LAST:
    lda NFS_FILE_END,x          ; the last block ends at the end
    sta NFS_FS_BLOCK_END,x
    dex
    bpl SEND_DATA_BLOCKS_LAST
SEND_DATA_BLOCKS_TRANSMIT:
    pla
    pha
    php                             ; carry set for the last block
    sta NFS_FS_BLOCK_PORT
    lda #NFS_CONTROL_TRANSMIT
    sta NFS_FS_BLOCK
    jsr TRANSMIT_FS_BLOCK                       ; transmit it
    lda NFS_SAVE_PORT
    jsr SET_UP_RECEIVE_BLOCK                       ; and set the block at &C0 to receive into &0F03
    plp
    bcs NFS_EOF_RETURN
    lda #NFS_PORT_ACKNOWLEDGE
    sta NFS_FS_BLOCK_PORT
    inc NFS_FS_BLOCK_START             ; into &0F04
    jsr AWAIT_RECEPTION                       ; wait for the acknowledgement
    bne SEND_DATA_BLOCKS_LOOP       ; (always)

;; FSCV 1, EOF#: says whether an open file's pointer is at its end.
;;
;; A handle whose bit in NFS_EOF_FLAGS is clear is not at its end, and the file server is not asked. Otherwise it sends
;; NFS_FS_EOF with the handle's mask as its one data byte; the reply's first data byte is nonzero at the end of
;; the file, and when it is zero the handle's hint is cleared.
;; In:    X = the handle
;; Out:   X = nonzero at the end of the file, 0 if not
;; Uses:  NFS_REQUEST
;; Keeps: A, Y
;; Entry: NFS_EOF_RETURN = pulls A and reloads Y from NFS_CALL_XY+1
NFS_EOF:
    pha
    txa
    jsr HANDLE_IN_A_TO_MASK                       ; the handle's mask, in Y
    tya
    and NFS_EOF_FLAGS
    tax
    beq NFS_EOF_RETURN
    pha
    sty NFS_REQUEST_DATA
    ldy #NFS_FS_EOF
    ldx #$01                        ; one byte of data
    jsr FS_COMMAND
    pla
    ldx NFS_REPLY_DATA
    bne NFS_EOF_RETURN
    jsr CLEAR_EOF_FLAGS                       ; not at the end: clear the handle's hint
NFS_EOF_RETURN:
    pla
    ldy NFS_CALL_XY+1
    rts

;; OSFILE with A = 1-6: writes or reads a file's catalogue information, or deletes it.
;;
;; The NFS's OSFILE, at &870C, comes here for any A from 1 up, with the name already read into &0E30. Each request
;; carries the OSFILE reason first, then its data, then the name:
;;
;; - A = 1: NFS_FS_SET_INFO with the load and execution addresses (&0F06-&0F0D) and the access byte (&0F0E),
;;   translated from the control block's attributes by <ATTRIBUTES_TO_ACCESS>.
;; - A = 2 or 3: NFS_FS_SET_INFO with the load or the execution address (&0F06-&0F09).
;; - A = 4: NFS_FS_SET_INFO with the access byte (&0F06).
;; - A = 5: NFS_FS_READ_INFO. The reply holds the object's type (&0F05), its load and execution addresses
;;   (&0F06-&0F0D), three bytes of length (&0F0E-&0F10), its access byte (&0F11) and its date (&0F12-&0F13); they
;;   go into the control block, the access translated by <ACCESS_TO_ATTRIBUTES>.
;; - A = 6: NFS_FS_DELETE with just the name.
;;
;; Larger values of A do nothing. An error the server returns is raised.
;; In:    A = OSFILE's A, NFS_CALL_XY = the control block, NFS_NAME_POINTER = the name, ending in a carriage return
;; Out:   A = for A = 5, the object's type (0 not found, 1 a file, 2 a directory); otherwise NFS_CALL_A,
;;          X, Y = the call's
;; Uses:  NFS_REQUEST
NFS_OSFILE_INFO:
    sta NFS_REQUEST_DATA
    cmp #$06
    beq NFS_OSFILE_DELETE
    bcs NFS_OSFILE_INFO_DONE
    cmp #$05
    beq NFS_OSFILE_READ_INFO
    cmp #$04
    beq NFS_OSFILE_WRITE_ACCESS
    cmp #$01
    beq NFS_OSFILE_WRITE_ALL
    asl a                           ; A = 2 or 3: Y = 5 for the load address, 9 for the execution address
    asl a
    tay
    jsr SUBTRACT_3_FROM_Y
    ldx #$03
NFS_OSFILE_INFO_ADDRESS:
    lda (NFS_CALL_XY),y
    sta NFS_REQUEST_DATA+1,x
    dey
    dex
    bpl NFS_OSFILE_INFO_ADDRESS
    ldx #$05                        ; the reason and four bytes of address
    bne NFS_OSFILE_INFO_SEND
NFS_OSFILE_WRITE_ALL:
    jsr ATTRIBUTES_TO_ACCESS                       ; the attributes as the server's access byte
    sta NFS_REQUEST_DATA+9
    ldy #$09
    ldx #$08
NFS_OSFILE_WRITE_ALL_LOOP:
    lda (NFS_CALL_XY),y          ; both addresses, from bytes 2-9
    sta NFS_REQUEST_DATA,x
    dey
    dex
    bne NFS_OSFILE_WRITE_ALL_LOOP
    ldx #$0A                        ; the reason, eight bytes of address and the access byte
NFS_OSFILE_INFO_SEND:
    jsr COPY_NAME_TO_REQUEST_AT_X
    ldy #NFS_FS_SET_INFO
    bne NFS_OSFILE_INFO_REQUEST
NFS_OSFILE_DELETE:
    jsr COPY_NAME_TO_REQUEST
    ldy #NFS_FS_DELETE
NFS_OSFILE_INFO_REQUEST:
    bit FS_CONTROL_BLOCK_TEMPLATE_HIGH                       ; sets overflow (it holds &FF) for FS_COMMAND_IF_FOUND
    jsr FS_COMMAND_IF_FOUND
NFS_OSFILE_INFO_DONE:
    bcs NFS_OSFILE_INFO_RETURN
    bcc NFS_OSARGS_DONE
NFS_OSFILE_WRITE_ACCESS:
    jsr ATTRIBUTES_TO_ACCESS
    sta NFS_REQUEST_DATA+1
    ldx #$02                        ; the reason and the access byte
    bne NFS_OSFILE_INFO_SEND
NFS_OSFILE_READ_INFO:
    ldx #$01                        ; the name follows the reason, 5
    jsr COPY_NAME_TO_REQUEST_AT_X
    ldy #NFS_FS_READ_INFO
    jsr FS_COMMAND
    lda NFS_REPLY_DATA+12           ; the access byte
    stx NFS_REPLY_DATA+12           ; becomes the length's top byte, 0
    stx NFS_REPLY_DATA+15           ; and the attributes' top byte is 0
    jsr ACCESS_TO_ATTRIBUTES
    ldy #$0E
    sta (NFS_CALL_XY),y
    dey
    ldx #$0C
NFS_OSFILE_READ_INFO_LOOP:
    lda NFS_REPLY_DATA,x            ; the addresses and length, into bytes 2-13
    sta (NFS_CALL_XY),y
    dey
    dex
    bne NFS_OSFILE_READ_INFO_LOOP
    inx
    inx
    ldy #$11
NFS_OSFILE_READ_INFO_DATE:
    lda NFS_REPLY_DATA+13,x         ; the date and a zero, into bytes 15-17
    sta (NFS_CALL_XY),y
    dey
    dex
    bpl NFS_OSFILE_READ_INFO_DATE
    lda NFS_REPLY_DATA              ; the object's type
NFS_OSFILE_INFO_RETURN:
    bpl NFS_CALL_RETURN_A

;; ARGSV: OSARGS, reading or writing an open file's pointer or extent, or the filing system's own details.
;;
;; With Y = 0, A = 0 returns 5, the Econet filing system's number; A = 1 writes NFS_COMMAND_TAIL, the address of the
;; rest of the line after the name of the file last run, into the zero page block, as an I/O processor address;
;; A = 2 returns 1.
;;
;; With a handle in Y, A = 0 (pointer) and A = 2 (extent) send NFS_FS_READ_ARGUMENTS, and A = 1 sends
;; NFS_FS_SET_ARGUMENTS. The request's data is the handle's mask, then 0 for the pointer or 1 for the extent,
;; then for a write three bytes of the new pointer; a read's reply holds three bytes of the value, which go into the
;; zero page block with a zero top byte. Writing the pointer sets the handle's bit in NFS_EOF_FLAGS. Other values of A
;; do nothing. An error the server returns is raised.
;; In:    A = the reason, X = the zero page control block, Y = the handle, or 0
;; Out:   A = 0, or the filing system's number for Y = 0, A = 0; the call's A for A from 3 up
;; Keeps: X, Y
NFS_OSARGS:
    jsr SAVE_CALL_REGISTERS
    cmp #$03
    bcs NFS_CALL_RETURN
    cpy #$00
    beq NFS_OSARGS_FILING_SYSTEM
    jsr HANDLE_TO_MASK                       ; the handle's mask, in Y
    sty NFS_REQUEST_DATA
    lsr a                           ; 0 for the pointer, 1 for the extent; carry set to write
    sta NFS_REQUEST_DATA+1
    bcs NFS_OSARGS_WRITE_POINTER
    ldy #NFS_FS_READ_ARGUMENTS
    ldx #$02                        ; the mask and the 0 or 1
    jsr FS_COMMAND
    sta NFS_CALL_A                  ; 0, returned
    ldx NFS_CALL_XY
    ldy #$02
    sta $03,x                       ; the value's top byte
NFS_OSARGS_READ_LOOP:
    lda NFS_REPLY_DATA,y
    sta $02,x                       ; X moves down too, so this fills bytes 2, 1 and 0
    dex
    dey
    bpl NFS_OSARGS_READ_LOOP
NFS_OSARGS_DONE:
    bcc NFS_CALL_RETURN
NFS_OSARGS_WRITE_POINTER:
    tya
    pha
    ldy #$03
NFS_OSARGS_WRITE_POINTER_LOOP:
    lda $03,x                       ; the new pointer, to &0F07-&0F0A
    sta NFS_REQUEST_DATA+2,y
    dex
    dey
    bpl NFS_OSARGS_WRITE_POINTER_LOOP
    ldy #NFS_FS_SET_ARGUMENTS
    ldx #$05                        ; the mask, the 0 and three bytes of pointer
    jsr FS_COMMAND
    stx NFS_CALL_A                  ; 0, returned
    pla
    jsr SET_EOF_FLAGS                       ; set the handle's hint

;; Returns from a filing system call with the A it was called with, or the one put in NFS_CALL_A, and its X and Y.
;; Out:   A = NFS_CALL_A (unchanged from NFS_CALL_RETURN_A), X = NFS_CALL_XY, Y = NFS_CALL_XY+1
;; Entry: NFS_CALL_RETURN_A = returns A as it is
NFS_CALL_RETURN:
    lda NFS_CALL_A
NFS_CALL_RETURN_A:
    ldx NFS_CALL_XY
    ldy NFS_CALL_XY+1
    rts
NFS_OSARGS_FILING_SYSTEM:
    cmp #$02
    beq NFS_OSARGS_HALVE
    bcs NFS_RETURN_ZERO
    tay
    bne NFS_OSARGS_COMMAND_TAIL
    lda #$0A                        ; A = 0: halved, 5, the Econet filing system
NFS_OSARGS_HALVE:
    lsr a
    bne NFS_CALL_RETURN_A
NFS_OSARGS_COMMAND_TAIL:
    lda NFS_COMMAND_TAIL,y
    sta (NFS_CALL_XY),y
    dey
    bpl NFS_OSARGS_COMMAND_TAIL
    sty $02,x                       ; &FFFF: an address in the I/O processor
    sty $03,x

;; Returns from a filing system call with A = 0, and its X and Y.
;; Out:   A = 0, X = NFS_CALL_XY, Y = NFS_CALL_XY+1
NFS_RETURN_ZERO:
    lda #$00
    bpl NFS_CALL_RETURN_A

;; FINDV: OSFIND, opening or closing a file on the file server.
;;
;; To open, it sends NFS_FS_OPEN with two bytes and the name: &80 if the file is opened for input or update,
;; else 0, then 1 if it is opened for input only, else 0. The reply's first data byte is the file's handle, as a
;; mask: its bit is set in NFS_EOF_FLAGS and it is returned as a handle &20-&27. A with any of bits 0-5 set returns 0.
;;
;; To close, it sends NFS_FS_CLOSE with the handle's mask, or 0 to close every file, which first closes the
;; *SPOOL and *EXEC files with OSBYTE &77; the handle's bit is then set in NFS_EOF_FLAGS. An error the server returns
;; is raised.
;; In:    A = 0 to close, &40 to open for input, &80 for output, &C0 for update; X, Y = the name's address to open,
;;          Y = the handle to close, or 0 for all
;; Out:   A = the new handle, or 0; A = 0 after closing
;; Keeps: X, Y
NFS_OSFIND:
    jsr SAVE_COMMAND_REGISTERS
    sec
    jsr HANDLE_TO_MASK_KEEP_ZERO                       ; Y's mask, if Y is not 0
    tax
    beq NFS_OSFIND_CLOSE
    and #$3F
    bne NFS_RETURN_ZERO
    txa
    eor #$80
    asl a                           ; bit 6 of A, input or update, to bit 7
    sta NFS_REQUEST_DATA
    rol a                           ; 1 when bit 7 of A is clear: input only
    sta NFS_REQUEST_DATA+1
    jsr NFS_READ_FILE_NAME_TEXT                       ; read the name into &0E30
    ldx #$02
    jsr COPY_NAME_TO_REQUEST_AT_X
    ldy #NFS_FS_OPEN
    bit FS_CONTROL_BLOCK_TEMPLATE_HIGH                       ; sets overflow (it holds &FF) for FS_COMMAND_IF_FOUND
    jsr FS_COMMAND_IF_FOUND
    bcs NFS_CALL_RETURN_A
    lda NFS_REPLY_DATA              ; the new handle's mask
    tax
    jsr SET_EOF_FLAGS                       ; set its hint
    txa
    jsr MASK_TO_HANDLE                       ; as a handle number
    bne NFS_CALL_RETURN_A           ; (always)
NFS_OSFIND_CLOSE:
    tya
    bne NFS_OSFIND_CLOSE_HANDLE
    lda #NFS_OSBYTE_CLOSE_FILES
    jsr OSBYTE
    ldy #$00
NFS_OSFIND_CLOSE_HANDLE:
    sty NFS_REQUEST_DATA
    ldx #$01                        ; one byte of data
    ldy #NFS_FS_CLOSE
    jsr FS_COMMAND
    lda NFS_REQUEST_DATA            ; the handle's mask, which the reply leaves alone
    jsr SET_EOF_FLAGS
NFS_OSFIND_DONE:
    bcc NFS_CALL_RETURN

;; FSCV 0, *OPT: sets the NFS's options.
;;
;; *OPT 0 and *OPT 1 set NFS_MESSAGES to Y, which turns the messages on loading and saving on or off. *OPT 4 sets the
;; boot option to Y, 0-3, both on the file server (NFS_FS_SET_BOOT_OPTION, with Y as its data) and in
;; NFS_BOOT_OPTION. Anything else raises error &CB, "Bad Option".
;; In:    X, Y = *OPT's two numbers, zero = set when X is 0
;; Out:   A, X, Y = the call's
NFS_OPT:
    beq NFS_OPT_MESSAGES
    cpx #$04
    bne NFS_OPT_1
    cpy #$04
    bcc NFS_OPT_BOOT
NFS_OPT_1:
    dex
    bne NFS_OPT_BAD
NFS_OPT_MESSAGES:
    sty NFS_MESSAGES
    bcc NFS_OPT_DONE
NFS_OPT_BAD:
    lda #NFS_ERROR_INDEX_BAD_OPTION
    jmp NFS_ERROR
NFS_OPT_BOOT:
    sty NFS_REQUEST_DATA
    ldy #NFS_FS_SET_BOOT_OPTION
    jsr FS_COMMAND
    ldy NFS_CALL_XY+1
    sty NFS_BOOT_OPTION
NFS_OPT_DONE:
    bcc NFS_OSFIND_DONE

; ---------------------------------------------------------------------------------------------------------------------
; OSGBPB
; ---------------------------------------------------------------------------------------------------------------------

;; Adds the four-byte count at &0F06 to an OSGBPB control block's pointer (bytes 9-12), then its address (bytes 1-4).
;;
;; Falls into <ADD_TRANSFER_TO_ADDRESS>. Each subtracts instead when bit 7 of NFS_ADJUST_SIGN is set.
;; In:    NFS_REPLY_DATA+1 = the count, four bytes, NFS_CALL_XY = the control block, NFS_ADJUST_SIGN
;; Out:   Y = 5, X = 0
;; Uses:  A
ADD_TRANSFER_TO_POINTER:
    ldy #$09
    jsr ADJUST_GBPB_FIELD
;; Adds the four-byte count at &0F06 to an OSGBPB control block's address (bytes 1-4).
;;
;; Falls into <ADJUST_GBPB_FIELD>.
;; In:    NFS_REPLY_DATA+1 = the count, four bytes, NFS_CALL_XY = the control block, NFS_ADJUST_SIGN
;; Out:   Y = 5, X = 0
;; Uses:  A
ADD_TRANSFER_TO_ADDRESS:
    ldy #$01
;; Adds the four-byte count at &0F06 to four bytes of an OSGBPB control block, or subtracts it.
;;
;; It adds when bit 7 of NFS_ADJUST_SIGN is clear and subtracts when it is set. ADJUST_GBPB_FIELD_CARRY takes the carry
;; as it is: set to subtract.
;; In:    Y = the field's offset in the block, NFS_CALL_XY = the control block, NFS_REPLY_DATA+1 = the count,
;;          NFS_ADJUST_SIGN
;; Out:   Y = the offset after the field, X = 0, zero = set
;; Uses:  A
;; Entry: ADJUST_GBPB_FIELD_CARRY = with the carry already set up
ADJUST_GBPB_FIELD:
    clc
ADJUST_GBPB_FIELD_CARRY:
    ldx #$FC                        ; -4: X counts up to 0, and the count is read from &0F06 on
ADJUST_GBPB_FIELD_LOOP:
    lda (NFS_CALL_XY),y
    bit NFS_ADJUST_SIGN
    bmi ADJUST_GBPB_FIELD_SUBTRACT
    adc NFS_REPLY_DATA+1-$FC,x
    jmp ADJUST_GBPB_FIELD_STORE
ADJUST_GBPB_FIELD_SUBTRACT:
    sbc NFS_REPLY_DATA+1-$FC,x
ADJUST_GBPB_FIELD_STORE:
    sta (NFS_CALL_XY),y
    iny
    inx
    bne ADJUST_GBPB_FIELD_LOOP
    rts

;; GBPBV: OSGBPB, reading or writing a group of bytes of an open file, or reading the user's environment.
;;
;; A = 1-4 transfer data. It sends NFS_FS_PUT_BYTES (A = 1 or 2) or NFS_FS_GET_BYTES (A = 3 or 4) through
;; <FS_COMMAND_SEQUENCED>, which sends it with the handle's sequence bit; the request's third byte is the port the
;; client uses, NFS_PORT_ACKNOWLEDGE or NFS_PORT_DATA, and its data is the handle's mask, 0 to use the block's pointer
;; (A = 1, 3) or 1 to use the file's own (A = 2, 4), three bytes of count and three of pointer. The first reply, at
;; &0F00, gives the server's data port (byte 2) and the largest block it takes (bytes 3-4); the data then goes to the
;; server with <SEND_DATA_BLOCKS> or comes from it with <RECEIVE_DATA>. The final reply's first data byte has bit 7 set
;; when the file ended before the transfer was done, and the next four bytes count the bytes transferred, which are
;; added to the block's address and pointer and taken from its count.
;;
;; A = 5-8 read the user's environment into memory at the block's address, over the Tube when one is attached and
;; the address's top two bytes are not &FFFF:
;;
;; - A = 5: NFS_FS_READ_ENVIRONMENT; the title's length (16), the title and the boot option.
;; - A = 6 and 7: NFS_FS_READ_INFO with NFS_FS_INFO_DIRECTORY for the current directory or the library: a zero (the
;;   device's length), the name's length (10), the name and the ownership byte.
;; - A = 8: NFS_FS_EXAMINE of the current directory with NFS_FS_EXAMINE_NAMES, from the entry in the block's
;;   pointer, for as many names as its count. Byte 0 gets the directory's cycle number, the pointer moves past the
;;   names, the address past their bytes, and the count drops by the names returned.
;;
;; Other values of A do nothing. An error the server returns is raised.
;; In:    A = the reason, X, Y = the control block's address
;; Out:   A = 0, or the call's A when it does nothing; carry = set when A = 1-4 reached the file's end
;; Keeps: X, Y
NFS_OSGBPB:
    jsr SAVE_CALL_REGISTERS
    tax
    beq NFS_OSGBPB_IGNORE
    dex
    cpx #$08
    bcc NFS_OSGBPB_VALID
NFS_OSGBPB_IGNORE:
    jmp NFS_CALL_RETURN
NFS_OSGBPB_VALID:
    txa
    ldy #$00
    pha                             ; A - 1, 0-7
    cmp #$04
    bcc NFS_OSGBPB_TRANSFER
    jmp NFS_OSGBPB_INFO
NFS_OSGBPB_TRANSFER:
    lda (NFS_CALL_XY),y          ; the handle
    jsr HANDLE_IN_A_TO_MASK
    sty NFS_REQUEST_DATA            ; as its mask
    ldy #$0B
    ldx #$06
NFS_OSGBPB_COPY_LOOP:
    lda (NFS_CALL_XY),y          ; the pointer (bytes 9-11) and count (5-7), to &0F07-&0F0C
    sta NFS_REQUEST_DATA+1,x
    dey
    cpy #$08
    bne NFS_OSGBPB_COPY_NEXT
    dey                             ; skip byte 8, the count's top byte
NFS_OSGBPB_COPY_NEXT:
    dex
    bne NFS_OSGBPB_COPY_LOOP
    pla
    lsr a                           ; carry set for A = 2 and 4, which use the file's pointer
    pha                             ; 0 to put bytes, 1 to get them
    bcc NFS_OSGBPB_POINTER_FLAG
    inx
NFS_OSGBPB_POINTER_FLAG:
    stx NFS_REQUEST_DATA+1
    ldy #NFS_FS_PUT_BYTES
    ldx #NFS_PORT_ACKNOWLEDGE
    pla
    pha
    beq NFS_OSGBPB_REQUEST
    ldx #NFS_PORT_DATA
    dey                             ; NFS_FS_GET_BYTES
NFS_OSGBPB_REQUEST:
    stx NFS_REQUEST_URD
    stx NFS_SAVE_PORT
    ldx #$08                        ; eight bytes of data
    lda NFS_REQUEST_DATA            ; the handle's mask, for its sequence bit
    jsr FS_COMMAND_SEQUENCED
    lda NFS_SEQUENCE_RESULT
    sta NFS_SEQUENCE_BITS
    ldx #$04
NFS_OSGBPB_RANGE_LOOP:
    lda (NFS_CALL_XY),y          ; Y = 1-4: the address, as the start of the transfer
    sta a:NFS_FILE_START-1,y
    sta a:NFS_FS_BLOCK_END-1,y
    jsr ADD_4_TO_Y                       ; Y + 4: the count
    adc (NFS_CALL_XY),y
    sta a:NFS_FILE_START-1,y    ; the end of the transfer, in NFS_FILE_END
    jsr SUBTRACT_3_FROM_Y
    dex
    bne NFS_OSGBPB_RANGE_LOOP
    inx
NFS_OSGBPB_BLOCK_SIZE:
    lda NFS_REQUEST+3,x             ; the first reply's largest block, to &0F06-&0F07 for SEND_DATA_BLOCKS
    sta NFS_REPLY_DATA+1,x
    dex
    bpl NFS_OSGBPB_BLOCK_SIZE
    pla
    bne NFS_OSGBPB_RECEIVE
    lda NFS_REQUEST_URD             ; the first reply's data port
    jsr SEND_DATA_BLOCKS
    bcs NFS_OSGBPB_FINISH
NFS_OSGBPB_RECEIVE:
    jsr RECEIVE_DATA
NFS_OSGBPB_FINISH:
    jsr FS_AWAIT_REPLY                       ; wait for the final reply
    lda (NFS_CALL_XY,x)          ; the handle's number, not its mask, used as one below
    bit NFS_REPLY_DATA
    bmi NFS_OSGBPB_MARK_EOF
    jsr CLEAR_EOF_FLAGS
NFS_OSGBPB_MARK_EOF:
    jsr SET_EOF_FLAGS
    stx NFS_ADJUST_SIGN             ; 0: add
    jsr ADD_TRANSFER_TO_POINTER
    dec NFS_ADJUST_SIGN             ; &FF: subtract
    sec
    jsr ADJUST_GBPB_FIELD_CARRY     ; from the count
    asl NFS_REPLY_DATA              ; carry set when the file ended
    jmp NFS_RETURN_ZERO
NFS_OSGBPB_READ_TITLE:
    ldy #NFS_FS_READ_ENVIRONMENT
    jsr FS_COMMAND
    lda NFS_BOOT_OPTION
    sta NFS_ENVIRONMENT_CSD         ; after the title
    stx NFS_COPY_SOURCE
    stx NFS_COPY_DESTINATION
    lda #NFS_FS_TITLE_LENGTH+2          ; the title's length, the title and the boot option
    sta NFS_COPY_COUNT
    bne COPY_REPLY_TO_CALLER
NFS_OSGBPB_INFO:
    ldy #$04
    lda NFS_TUBE_PRESENT
    beq NFS_OSGBPB_SET_DESTINATION
    cmp (NFS_CALL_XY),y          ; &FF, as the address's top byte is for the I/O processor
    bne NFS_OSGBPB_SET_DESTINATION
    dey
    sbc (NFS_CALL_XY),y          ; zero when the next byte is &FF too
NFS_OSGBPB_SET_DESTINATION:
    sta NFS_GBPB_TUBE
NFS_OSGBPB_ADDRESS_LOOP:
    lda (NFS_CALL_XY),y          ; the address, to NFS_NAME_POINTER
    sta a:NFS_NAME_POINTER-1,y
    dey
    bne NFS_OSGBPB_ADDRESS_LOOP
    pla
    and #$03
    beq NFS_OSGBPB_READ_TITLE
    lsr a
    beq NFS_OSGBPB_READ_DIRECTORY
    bcs NFS_OSGBPB_READ_NAMES
NFS_OSGBPB_READ_DIRECTORY:
    tay                             ; 0 for the current directory, 1 for the library
    lda NFS_CSD,y
    sta NFS_REQUEST_CSD
    lda NFS_LIB
    sta NFS_REQUEST_LIB
    lda NFS_URD
    sta NFS_REQUEST_URD
    ldx #NFS_FS_READ_INFO
    stx NFS_REQUEST_FUNCTION
    lda #NFS_CR                     ; no name: the directory in the CSD byte
    sta NFS_REQUEST_DATA+1
    sta NFS_COPY_COUNT              ; 13 bytes to copy
    lsr a                           ; NFS_FS_INFO_DIRECTORY
    sta NFS_REQUEST_DATA
    clc
    jsr FS_SEND_REQUEST
    stx NFS_COPY_DESTINATION
    inx
    stx NFS_COPY_SOURCE

;; Copies bytes of a reply into the caller's memory, then returns from the filing system call with A = 0.
;;
;; The bytes go to (NFS_NAME_POINTER) in the I/O processor, or, when NFS_GBPB_TUBE is nonzero, through the Tube to the
;; address in bytes 1-4 of the caller's control block, with a short delay after each.
;; In:    NFS_COPY_SOURCE = the first byte's index from &0F05, NFS_COPY_DESTINATION = its index at NFS_NAME_POINTER,
;;          NFS_COPY_COUNT = the number of bytes, NFS_GBPB_TUBE, NFS_CALL_XY = the control block
;; Out:   A = 0, X = NFS_CALL_XY, Y = NFS_CALL_XY+1, NFS_COPY_COUNT = 0
COPY_REPLY_TO_CALLER:
    lda NFS_GBPB_TUBE
    bne COPY_REPLY_TO_CALLER_TUBE
    ldx NFS_COPY_SOURCE
    ldy NFS_COPY_DESTINATION
COPY_REPLY_TO_CALLER_LOOP:
    lda NFS_REPLY_DATA,x
    sta (NFS_NAME_POINTER),y
    inx
    iny
    dec NFS_COPY_COUNT
    bne COPY_REPLY_TO_CALLER_LOOP
    beq COPY_REPLY_TO_CALLER_DONE
COPY_REPLY_TO_CALLER_TUBE:
    jsr CLAIM_TUBE
    lda #NFS_TUBE_TO_PARASITE
    ldx NFS_CALL_XY              ; X, Y = the control block's address, plus one
    ldy NFS_CALL_XY+1
    inx
    bne COPY_REPLY_TO_CALLER_START
    iny
COPY_REPLY_TO_CALLER_START:
    jsr TUBE_ENTRY_TRANSFER
    ldx NFS_COPY_SOURCE
COPY_REPLY_TO_CALLER_TUBE_LOOP:
    lda NFS_REPLY_DATA,x
    sta TUBE_R3_DATA                ; to the second processor
    inx
    ldy #$06
COPY_REPLY_TO_CALLER_DELAY:
    dey
    bne COPY_REPLY_TO_CALLER_DELAY
    dec NFS_COPY_COUNT
    bne COPY_REPLY_TO_CALLER_TUBE_LOOP
    lda #NFS_TUBE_RELEASE
    jsr TUBE_ENTRY_TRANSFER
COPY_REPLY_TO_CALLER_DONE:
    jmp NFS_RETURN_ZERO
NFS_OSGBPB_READ_NAMES:
    ldy #$09
    lda (NFS_CALL_XY),y          ; the pointer: the first entry to read
    sta NFS_REQUEST_DATA+1
    ldy #$05
    lda (NFS_CALL_XY),y          ; the count: the number of names
    sta NFS_REQUEST_DATA+2
    ldx #NFS_CR                     ; no name: the current directory; also the length of data sent
    stx NFS_REQUEST_DATA+3
    ldy #NFS_FS_EXAMINE_NAMES
    sty NFS_COPY_SOURCE             ; the names start at &0F07
    sty NFS_REQUEST_DATA
    iny                             ; NFS_FS_EXAMINE
    jsr FS_COMMAND
    stx NFS_COPY_DESTINATION
    lda NFS_REPLY_DATA+1            ; the cycle number, to byte 0
    sta (NFS_CALL_XY,x)
    lda NFS_REPLY_DATA              ; the number of names returned
    ldy #$09
    adc (NFS_CALL_XY),y          ; moves the pointer past them
    sta (NFS_CALL_XY),y
    lda NFS_FS_BLOCK_END               ; where the reply ended
    sbc #$07                        ; less the header and the two bytes before the names
    sta NFS_REPLY_DATA+1
    sta NFS_COPY_COUNT
    beq NFS_OSGBPB_READ_NAMES_COUNT
    jsr COPY_REPLY_TO_CALLER
NFS_OSGBPB_READ_NAMES_COUNT:
    ldx #$02
NFS_OSGBPB_READ_NAMES_ZERO:
    sta NFS_REPLY_DATA+2,x          ; A = 0: &0F06-&0F09 is the number of bytes copied
    dex
    bpl NFS_OSGBPB_READ_NAMES_ZERO
    jsr ADD_TRANSFER_TO_ADDRESS
    sec
    dec NFS_ADJUST_SIGN             ; &FF: subtract
    lda NFS_REPLY_DATA
    sta NFS_REPLY_DATA+1            ; and now the number of names
    jsr ADJUST_GBPB_FIELD_CARRY     ; from the count
    beq COPY_REPLY_TO_CALLER_DONE   ; (always)

;; Claims the Tube for the NFS, waiting until it is free.
;; Out:   carry = set
;; Uses:  A, X, Y
CLAIM_TUBE:
    lda #NFS_TUBE_CLAIM
    jsr TUBE_ENTRY_TRANSFER
    bcc CLAIM_TUBE
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The * commands and the catalogue
; ---------------------------------------------------------------------------------------------------------------------

;; FSCV 3: a * command no paged ROM recognised, which the NFS looks up in <NFS_COMMAND_TABLE>.
;;
;; It compares the command with each name in turn, in either case. A "." in the command where it stops matching ends
;; it as an abbreviation of that name. The handler is called through RTS, with the command's text at (TEXT_POINTER),Y.
;; The last entry matches anything, and sends the command to the file server. <NFS_BOOT> comes here with the start-up
;; command "I .BOOT".
;; In:    X, Y = the command's address
;; Out:   Y = the index after the name in the command, for the handler
;; Uses:  A, X, NFS_COLUMN (set negative, one entry to a line), NFS_ESCAPE_ENABLE (set)
NFS_UNRECOGNISED_COMMAND:
    jsr SAVE_COMMAND_REGISTERS
    ldx #$FF
    stx NFS_COLUMN
    stx NFS_ESCAPE_ENABLE
NFS_UNRECOGNISED_COMMAND_ENTRY:
    ldy #$FF
NFS_UNRECOGNISED_COMMAND_NEXT:
    iny
    inx
NFS_UNRECOGNISED_COMMAND_COMPARE:
    lda NFS_COMMAND_TABLE,x
    bmi NFS_UNRECOGNISED_COMMAND_FOUND ; the address's high byte: the name matched
    eor (NFS_NAME_POINTER),y
    and #NFS_CASE_MASK
    beq NFS_UNRECOGNISED_COMMAND_NEXT
    dex
NFS_UNRECOGNISED_COMMAND_SKIP:
    inx                             ; skip to the address's high byte
    lda NFS_COMMAND_TABLE,x
    bpl NFS_UNRECOGNISED_COMMAND_SKIP
    lda (NFS_NAME_POINTER),y
    inx
    cmp #'.'
    bne NFS_UNRECOGNISED_COMMAND_ENTRY
    iny                             ; an abbreviation: take this entry
    dex
    bcs NFS_UNRECOGNISED_COMMAND_COMPARE ; (always)
NFS_UNRECOGNISED_COMMAND_FOUND:
    pha
    lda NFS_COMMAND_TABLE+1,x
    pha
    rts

;; The NFS's * commands, which <NFS_UNRECOGNISED_COMMAND> searches in order.
;;
;; Each entry is an <NFS_COMMAND>: the name, then the handler's address less one, high byte first. "I." comes first
;; so that *I. goes to the file server rather than being read as *I AM. *BYE must end the line. The last entry, with
;; no name, sends any other command to the file server (in <I_AM_COMMAND_FIND_COLON>'s routine).
NFS_COMMAND_TABLE:
    NFS_COMMAND FILE_SERVER_COMMAND_SEND-4, "I."       ; to the file server
    NFS_COMMAND I_AM_COMMAND_SKIP+1, "I AM"     ; logs on
    NFS_COMMAND EX_COMMAND, "EX"
    NFS_COMMAND FS_COMMAND_WITH_PORT+3, "BYE", NFS_CR ; logs off
    NFS_COMMAND FILE_SERVER_COMMAND_SEND-4             ; anything else, to the file server

;; *EX: prints a directory's details and those of its entries, one to a line.
;;
;; Sets up <NFS_CATALOGUE> to ask for three entries at a time with NFS_FS_EXAMINE_LONG, and goes on into it.
;; In:    Y = the index of the directory's name in the command, at (TEXT_POINTER),Y
EX_COMMAND:
    ldx #NFS_FS_EXAMINE_LONG
    lda #$03                        ; entries at a time
    bne NFS_CATALOGUE

;; FSCV 5, *CAT: prints a directory's details and its entries' names, four to a line.
;;
;; Sets up <NFS_CATALOGUE> to ask for eleven entries at a time with NFS_FS_EXAMINE_SHORT, and goes on into it.
;; In:    TEXT_POINTER = the rest of the command line: the directory's name
NFS_CAT:
    ldx #NFS_FS_EXAMINE_SHORT
    stx NFS_COLUMN                  ; so that the first entry starts a new line
    ldy #$FF
    sty NFS_ESCAPE_ENABLE
    iny
    lda #$0B                        ; entries at a time

;; Prints a directory's catalogue: its details, the disc's, and then its entries, as *CAT and *EX do.
;;
;; It sends NFS_FS_READ_INFO with NFS_FS_INFO_DIRECTORY and the directory's name, and prints the name, the cycle
;; number in brackets, and "Owner" or "Public"; then NFS_FS_READ_ENVIRONMENT, and prints the disc's title, the
;; boot option as a number and a name (<NFS_BOOT_OPTION_NAMES>), and the names of the current directory and the library.
;; Then it sends NFS_FS_EXAMINE again and again, each asking for the next NFS_EXAMINE_COUNT entries in
;; NFS_EXAMINE_FORMAT, and prints what comes back with <PRINT_REPLY_LIST>, until a reply holds none. An error the
;; server returns is raised.
;;
;; Each examine request's data is the format, the first entry, the number of entries and the directory's name; its
;; reply holds the number of entries returned, a byte, then the entries' text, each ending in a zero, then &80.
;; In:    A = entries to ask for at a time, X = the format, Y = the index of the name at (TEXT_POINTER),Y
;; Uses:  A, X, Y, NFS_REQUEST, NFS_EXAMINE_START, NFS_EXAMINE_COUNT, NFS_EXAMINE_FORMAT, NFS_COLUMN
NFS_CATALOGUE:
    sta NFS_EXAMINE_COUNT
    stx NFS_EXAMINE_FORMAT
    lda #NFS_FS_INFO_DIRECTORY
    sta NFS_REQUEST_DATA
    jsr NFS_READ_FILE_NAME_AT                       ; read the name into &0E30
    ldx #$01
    jsr COPY_NAME_TO_REQUEST_AT_X
    ldy #NFS_FS_READ_INFO
    jsr FS_COMMAND
    ldx #NFS_INFO_NAME-NFS_REPLY_DATA
    jsr PRINT_REPLY_NAME
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "("
    lda NFS_INFO_CYCLE
    jsr PRINT_DECIMAL
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte ")     "
    ldy NFS_INFO_OWNER
    bne NFS_CATALOGUE_PUBLIC
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "Owner",NFS_CR
    bne NFS_CATALOGUE_DISC          ; (always: the text ends with Z clear)
NFS_CATALOGUE_PUBLIC:
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "Public",NFS_CR
NFS_CATALOGUE_DISC:
    ldy #NFS_FS_READ_ENVIRONMENT
    jsr FS_COMMAND
    inx                             ; NFS_ENVIRONMENT_TITLE
    ldy #NFS_FS_TITLE_LENGTH
    jsr PRINT_REPLY_TEXT
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "    Option "
    lda NFS_BOOT_OPTION
    tax
    jsr DFS_PRINT_HEX_BYTE                       ; in hexadecimal
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte " ("
    ldy NFS_BOOT_OPTION_NAMES,x
NFS_CATALOGUE_OPTION_NAME:
    lda NFS_BOOT_OPTION_NAMES,y
    bmi NFS_CATALOGUE_DIRECTORIES   ; the name ends at the code after it
    jsr OSASCI
    iny
    bne NFS_CATALOGUE_OPTION_NAME
NFS_CATALOGUE_DIRECTORIES:
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte ")",NFS_CR,"Dir. "
    ldx #NFS_ENVIRONMENT_CSD-NFS_REPLY_DATA
    jsr PRINT_REPLY_NAME
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "     Lib. "
    ldx #NFS_ENVIRONMENT_LIBRARY-NFS_REPLY_DATA
    jsr PRINT_REPLY_NAME
    jsr OSNEWL
NFS_CATALOGUE_EXAMINE:
    sty NFS_REQUEST_DATA+1          ; the first entry
    sty NFS_EXAMINE_START
    ldx NFS_EXAMINE_COUNT
    stx NFS_REQUEST_DATA+2
    ldx NFS_EXAMINE_FORMAT
    stx NFS_REQUEST_DATA
    ldx #$03
    jsr COPY_NAME_TO_REQUEST_AT_X
    ldy #NFS_FS_EXAMINE
    jsr FS_COMMAND
    inx
    lda NFS_REPLY_DATA              ; the number of entries returned
    bne NFS_CATALOGUE_ENTRIES
    jmp OSNEWL
NFS_CATALOGUE_ENTRIES:
    pha
NFS_CATALOGUE_FIND_END:
    iny
    lda NFS_REPLY_DATA,y
    bpl NFS_CATALOGUE_FIND_END
    sta NFS_REQUEST_DATA-1,y        ; the end over the last entry's zero, so no separator follows it
    jsr PRINT_REPLY_LIST_SEPARATOR
    pla
    clc
    adc NFS_EXAMINE_START           ; the next request starts after these
    tay
    bne NFS_CATALOGUE_EXAMINE       ; (falls into PRINT_REPLY_NAME only after entry 255)

;; Prints a name from a reply: ten characters at &0F05+X.
;;
;; PRINT_REPLY_TEXT prints Y characters.
;; In:    X = the name's index from NFS_REPLY_DATA, Y = the number of characters for PRINT_REPLY_TEXT
;; Out:   X = the index after the text, Y = 0
;; Uses:  A
;; Entry: PRINT_REPLY_TEXT = with the length in Y
PRINT_REPLY_NAME:
    ldy #NFS_FS_NAME_LENGTH
PRINT_REPLY_TEXT:
    lda NFS_REPLY_DATA,x
    jsr OSASCI
    inx
    dey
    bne PRINT_REPLY_TEXT
    rts

;; The offsets of the boot options' names from this table, indexed by the option, for the catalogue.
;;
;; Each name lies between two routines, and ends at the next routine's first byte, which has bit 7 set.
NFS_BOOT_OPTION_NAMES:
    .byte NFS_BOOT_OFF_NAME-NFS_BOOT_OPTION_NAMES   ; option 0
    .byte NFS_BOOT_LOAD_NAME-NFS_BOOT_OPTION_NAMES  ; option 1
    .byte NFS_BOOT_RUN_NAME-NFS_BOOT_OPTION_NAMES   ; option 2
    .byte NFS_BOOT_EXEC_NAME-NFS_BOOT_OPTION_NAMES  ; option 3

;; The command that boot option 1 runs on logging on, which loads !BOOT. Option 2's command, which runs it, is the
;; end of this one.
NFS_BOOT_LOAD_COMMAND:
    .byte "L.!BOOT",NFS_CR

;; The command that boot option 3 runs on logging on, which *EXECs !BOOT. Option 0's command, an empty line, is its
;; carriage return.
NFS_BOOT_EXEC_COMMAND:
    .byte "E.!BOOT",NFS_CR

;; The low bytes of the boot commands' addresses, indexed by the boot option, for <NFS_LOG_ON>.
NFS_BOOT_COMMANDS:
    .byte <(NFS_BOOT_EXEC_COMMAND+7)    ; option 0: the carriage return
    .byte <NFS_BOOT_LOAD_COMMAND        ; option 1: L.!BOOT
    .byte <(NFS_BOOT_LOAD_COMMAND+2)    ; option 2: !BOOT
    .byte <NFS_BOOT_EXEC_COMMAND        ; option 3: E.!BOOT
    .assert >NFS_BOOT_LOAD_COMMAND = >(NFS_BOOT_EXEC_COMMAND+7), "The boot commands share a page."

;; Boot option 3's name.
NFS_BOOT_EXEC_NAME:
    .byte "Exec"

;; Prints four bytes of the caller's control block in hexadecimal, from byte Y down, then a space.
;;
;; *OPT 1's messages print a file's addresses and length with it.
;; In:    Y = the first byte's offset, X = the number of bytes, for PRINT_BLOCK_HEX_X, NFS_CALL_XY
;; Out:   Y = the offset before the last byte printed, X = 0
;; Uses:  A
;; Entry: PRINT_BLOCK_HEX_X = prints X bytes, PRINT_SPACE = prints just the space
PRINT_BLOCK_HEX:
    ldx #$04
PRINT_BLOCK_HEX_X:
    lda (NFS_CALL_XY),y
    jsr DFS_PRINT_HEX_BYTE
    dey
    dex
    bne PRINT_BLOCK_HEX_X
PRINT_SPACE:
    lda #' '
    bne PRINT_DECIMAL_CHARACTER

;; Boot option 0's name.
NFS_BOOT_OFF_NAME:
    .byte "Off"

;; Copies a name ending in a carriage return from (NFS_NAME_POINTER) into the request's data, carriage return and all.
;; In:    NFS_NAME_POINTER = the name, X = the index from NFS_REQUEST_DATA, for COPY_NAME_TO_REQUEST_AT_X
;; Out:   X = the index after the carriage return, the length of the request's data, Y = the name's length with
;;          its carriage return, A = 0, zero = set
;; Entry: COPY_NAME_TO_REQUEST_AT_X = copies to NFS_REQUEST_DATA+X
COPY_NAME_TO_REQUEST:
    ldx #$00
COPY_NAME_TO_REQUEST_AT_X:
    ldy #$00
COPY_NAME_TO_REQUEST_LOOP:
    lda (NFS_NAME_POINTER),y
    sta NFS_REQUEST_DATA,x
    inx
    iny
    eor #NFS_CR
    bne COPY_NAME_TO_REQUEST_LOOP
COPY_NAME_TO_REQUEST_RETURN:
    rts

;; Boot option 1's name.
NFS_BOOT_LOAD_NAME:
    .byte "Load"

;; Prints the text in a reply, a list of entries each ending in a zero, up to a byte with bit 7 set.
;;
;; The file server's reply with command code 4 comes here, as does the catalogue. Each zero prints a separator: a
;; new line when NFS_COLUMN is negative; otherwise NFS_COLUMN counts 0-3, and a new line starts at 0 and two spaces
;; go between the others, giving four entries to a line.
;; In:    X = the index of the first character from NFS_REPLY_DATA, for PRINT_REPLY_LIST_AT, NFS_COLUMN
;; Out:   X = the index of the end byte, A = the end byte
;; Uses:  Y, NFS_COLUMN
;; Entry: PRINT_REPLY_LIST_AT = from index X, PRINT_REPLY_LIST_SEPARATOR = prints a separator first, then the text
;;          from X+1
PRINT_REPLY_LIST:
    ldx #$00
PRINT_REPLY_LIST_AT:
    lda NFS_REPLY_DATA,x
    bmi COPY_NAME_TO_REQUEST_RETURN
    bne PRINT_REPLY_LIST_CHARACTER
PRINT_REPLY_LIST_SEPARATOR:
    ldy NFS_COLUMN
    bmi PRINT_REPLY_LIST_NEWLINE
    iny
    tya
    and #$03
    sta NFS_COLUMN
    beq PRINT_REPLY_LIST_NEWLINE
    jsr NFS_PRINT_INLINE                       ; prints the text that follows
    .byte "  "
    bne PRINT_REPLY_LIST_NEXT       ; (always: the text ends with Z clear)
PRINT_REPLY_LIST_NEWLINE:
    lda #NFS_CR
PRINT_REPLY_LIST_CHARACTER:
    jsr OSASCI
PRINT_REPLY_LIST_NEXT:
    inx
    bne PRINT_REPLY_LIST_AT

;; Boot option 2's name.
NFS_BOOT_RUN_NAME:
    .byte "Run"

;; Prints A in decimal, as three digits with leading zeros.
;; In:    A = the number
;; Uses:  A, X, Y, NFS_DIVISOR
;; See:   <PRINT_DECIMAL_DIGIT>
PRINT_DECIMAL:
    tay
    lda #100
    jsr PRINT_DECIMAL_DIGIT
    lda #10
    jsr PRINT_DECIMAL_DIGIT
    lda #1
;; Prints one decimal digit: how many times a power of ten goes into Y.
;; In:    A = the power of ten, Y = the number
;; Out:   Y = the remainder
;; Uses:  A, X, NFS_DIVISOR
;; Entry: PRINT_DECIMAL_CHARACTER = prints the character in A with OSASCI
PRINT_DECIMAL_DIGIT:
    sta NFS_DIVISOR
    tya
    ldx #'0'-1
    sec
PRINT_DECIMAL_LOOP:
    inx
    sbc NFS_DIVISOR
    bcs PRINT_DECIMAL_LOOP
    adc NFS_DIVISOR
    tay
    txa
PRINT_DECIMAL_CHARACTER:
    jmp OSASCI

; ---------------------------------------------------------------------------------------------------------------------
; Running files, and the replies' command codes
; ---------------------------------------------------------------------------------------------------------------------

;; FSCV 2 and 4, */ and *RUN: loads a file from the file server and runs it.
;;
;; Reads the name into &0E30 and the request's data, and goes on into <NFS_RUN_COMMAND>.
;; In:    TEXT_POINTER = the name, then the rest of the command line
NFS_RUN:
    jsr NFS_READ_FILE_NAME_TEXT
    jsr COPY_NAME_TO_REQUEST

;; Loads the file a command names and runs it: the file server's reply with command code 8 comes here.
;;
;; It skips the name at (TEXT_POINTER) and spaces after it, keeping the address of the rest of the line in
;; NFS_COMMAND_TAIL for OSARGS 1. It loads the file with <NFS_LOAD_FILE>, sending NFS_FS_LOAD_COMMAND and the command at
;; &0F05, through the control block at NFS_RUN_BLOCK, whose byte 6 it sets nonzero so that the file loads at its own
;; address. The file then runs at its execution address, from the reply at &0F09: in the second processor, through
;; the Tube, when one is attached and the address's top two bytes are not &FFFF; otherwise by JMP, with A from ROL A.
;; In:    TEXT_POINTER = the command line, NFS_REQUEST_DATA = the command
NFS_RUN_COMMAND:
    ldy #$00
    clc
    jsr GSINIT
NFS_RUN_COMMAND_SKIP_NAME:
    jsr GSREAD
    bcc NFS_RUN_COMMAND_SKIP_NAME
    jsr NFS_SKIP_SPACES                       ; skip spaces
    clc
    tya
    adc TEXT_POINTER
    sta NFS_COMMAND_TAIL
    lda TEXT_POINTER+1
    adc #$00
    sta NFS_COMMAND_TAIL+1
    ldx #>NFS_RUN_BLOCK
    stx NFS_CALL_XY+1
    lda #<NFS_RUN_BLOCK
    sta NFS_CALL_XY
    sta NFS_RUN_BLOCK+6             ; nonzero: load at the file's own address
    ldx #NFS_RUN_REQUEST_LENGTH
    ldy #NFS_FS_LOAD_COMMAND
    jsr NFS_LOAD_FILE
    lda NFS_TUBE_PRESENT
    beq NFS_RUN_COMMAND_IO
    adc NFS_REPLY_DATA+6            ; carry set when the execution address's top two bytes are &FFFF
    adc NFS_REPLY_DATA+7
    bcs NFS_RUN_COMMAND_IO
    jsr CLAIM_TUBE
    ldx #<(NFS_REPLY_DATA+4)        ; the execution address
    ldy #>(NFS_REPLY_DATA+4)
    lda #NFS_TUBE_EXECUTE
    jmp TUBE_ENTRY_TRANSFER
NFS_RUN_COMMAND_IO:
    rol a
    jmp (NFS_REPLY_DATA+4)

;; Sets the library's handle: the file server's reply with command code 9 comes here.
;;
;; Falls into <NFS_SET_DIRECTORY> when the carry is set; it is clear when a reply is acted on.
;; In:    Y = the new handle (mask), the reply's first data byte, carry = clear
;; Out:   A, X, Y = the call's
NFS_SET_LIBRARY:
    sty NFS_LIB
    bcc NFS_SET_HANDLES_DONE

;; Sets the current directory's handle: the file server's reply with command code 7, after *DIR, comes here.
;; In:    Y = the new handle (mask), the reply's first data byte
;; Out:   A, X, Y = the call's
NFS_SET_DIRECTORY:
    sty NFS_CSD
NFS_SET_HANDLES_DONE:
    jmp NFS_CALL_RETURN

;; Logs on: the file server's reply with command code 5, after *I AM, comes here.
;;
;; It takes the handles of the root directory, the current directory and the library, and the boot option, from the
;; reply's first four data bytes, then runs the boot option's command from <NFS_BOOT_COMMANDS> with OSCLI. Falls into
;; <NFS_SET_HANDLES> with the carry set.
NFS_LOG_ON:
    sec

;; Sets the handles of the root directory, the current directory and the library from the reply: the file server's
;; reply with command code 6 comes here.
;; In:    carry = clear (set from NFS_LOG_ON)
;; Out:   A, X, Y = the call's
NFS_SET_HANDLES:
    ldx #$03
    bcc NFS_SET_HANDLES_NEXT
NFS_SET_HANDLES_LOOP:
    lda NFS_REPLY_DATA,x
    sta NFS_URD,x
NFS_SET_HANDLES_NEXT:
    dex
    bpl NFS_SET_HANDLES_LOOP
    bcc NFS_SET_HANDLES_DONE
    ldy NFS_BOOT_OPTION
    ldx NFS_BOOT_COMMANDS,y
    ldy #>NFS_BOOT_LOAD_COMMAND
    jmp OSCLI

; ---------------------------------------------------------------------------------------------------------------------
; OSBYTE &32-&34 and OSWORD &10-&14: the Econet calls
; ---------------------------------------------------------------------------------------------------------------------

;; Finds a receive control block in the second page of the NFS's private workspace, by its number in OS_X.
;;
;; The blocks are NFS_RECEIVE_BLOCK_SIZE bytes each, from the page's start, and there are NFS_RECEIVE_BLOCKS of them.
;; In:    OS_X = the block's number, A = it for FIND_RECEIVE_BLOCK
;; Out:   carry = clear for a valid number, with Y = its offset and A = four times the number; set for one too
;;          large, with A and Y = 0
;; Entry: FIND_RECEIVE_BLOCK = with the number in A
FIND_RECEIVE_BLOCK_X:
    lda OS_X
FIND_RECEIVE_BLOCK:
    asl a
    asl a
    pha
    asl a
    tsx
    adc STACK+1,x                   ; 8 times plus 4 times: 12 times the number
    tay
    pla
    cmp #NFS_RECEIVE_BLOCKS*4
    bcc FIND_RECEIVE_BLOCK_RETURN
    ldy #$00
    tya
FIND_RECEIVE_BLOCK_RETURN:
    rts

;; OSBYTE &32: polls the transmission OSWORD &10 started, returning its control byte in X.
;;
;; Bit 7 is set while the transmission is in progress.
;; In:    carry = clear
;; Out:   OS_X = the transmit control block's control byte
NFS_OSBYTE_POLL_TRANSMIT:
    ldy #NFS_TRANSMIT_OFFSET
    lda (NFS_WORKSPACE_PAGE),y
    bcc NFS_OSBYTE_RESULT

;; OSBYTE &33: polls receive control block X, returning its control byte in X.
;;
;; Bit 7 is set once something has been received into it. A block that is not open, or a number too large, gives 0.
;; In:    OS_X = the block's number
;; Out:   OS_X = its control byte, or 0
;; Entry: NFS_OSBYTE_NONE = returns 0, NFS_OSBYTE_RESULT = returns A
NFS_OSBYTE_POLL_RECEIVE:
    jsr FIND_RECEIVE_BLOCK_X
    bcs NFS_OSBYTE_NONE
    lda (NFS_BLOCKS_PAGE),y
    cmp #NFS_FREE_BLOCK
    bne NFS_OSBYTE_RESULT
NFS_OSBYTE_NONE:
    lda #$00
NFS_OSBYTE_RESULT:
    sta OS_X
    rts

;; OSBYTE &34: deletes receive control block X, so that it is free for OSWORD &11 to open again.
;; In:    OS_X = the block's number
;; Out:   OS_X = 0 if the number is too large
NFS_OSBYTE_DELETE_RECEIVE:
    jsr FIND_RECEIVE_BLOCK_X
    bcs NFS_OSBYTE_NONE
    lda #NFS_FREE_BLOCK
    sta (NFS_BLOCKS_PAGE),y
    rts

;; Service call 8, an unrecognised OSWORD: carries out OSWORD &10-&14, the Econet calls.
;;
;; OSWORD &10 transmits, &11 opens or reads a receive control block, &12 reads the arguments of a remote procedure
;; call, &13 reads or writes the station's information, and &14 talks to the file server (<NFS_OSWORD_14>). The handler,
;; from <NFS_OSWORD_LOW> and <NFS_OSWORD_HIGH>, runs with &AA-&AC saved in the first bytes of the private workspace, and
;; they are put back afterwards.
;; In:    OS_A = the OSWORD number, OS_X/OS_Y = its control block, carry = clear
;; Out:   NFS_SERVICE_RESULT = 0 to claim the call, for the numbers the NFS handles
SERVICE_UNRECOGNISED_OSWORD:
    lda OS_A
    sbc #$0F                        ; the carry is clear: A - &10
    bmi SERVICE_UNRECOGNISED_OSWORD_RETURN
    cmp #$05
    bcs SERVICE_UNRECOGNISED_OSWORD_RETURN
    jsr NFS_OSWORD_DISPATCH
    ldy #$02
SERVICE_UNRECOGNISED_OSWORD_RESTORE:
    lda (NFS_WORKSPACE_PAGE),y
    sta a:NFS_OSWORD_SAVED,y
    dey
    bpl SERVICE_UNRECOGNISED_OSWORD_RESTORE
    rts

;; Calls the handler for an Econet OSWORD, through RTS.
;;
;; It saves &AA-&AC in the first three bytes of the private workspace, claims the service call, and enters the
;; handler with the control block's first byte.
;; In:    A = the OSWORD number less &10, 0-4, OS_X/OS_Y = the control block, carry = clear
;; Out:   (to the handler) A = the control block's first byte, X = the OSWORD number less &10, Y = 0,
;;          carry = clear
NFS_OSWORD_DISPATCH:
    tax
    lda NFS_OSWORD_HIGH,x
    pha
    lda NFS_OSWORD_LOW,x
    pha
    ldy #$02
NFS_OSWORD_DISPATCH_SAVE:
    lda a:NFS_OSWORD_SAVED,y
    sta (NFS_WORKSPACE_PAGE),y
    dey
    bpl NFS_OSWORD_DISPATCH_SAVE
    iny
    lda (OS_X),y
    sty NFS_SERVICE_RESULT
SERVICE_UNRECOGNISED_OSWORD_RETURN:
    rts

;; The low bytes of the Econet OSWORD handlers' addresses less one, indexed by the OSWORD number less &10.
;; See: <NFS_OSWORD_HIGH>, <NFS_OSWORD_DISPATCH>
NFS_OSWORD_LOW:
    .byte <(NFS_OSWORD_TRANSMIT-1)      ; OSWORD &10
    .byte <(NFS_OSWORD_RECEIVE-1)       ; OSWORD &11
    .byte <(NFS_OSWORD_READ_ARGUMENTS-1) ; OSWORD &12
    .byte <(NFS_OSWORD_STATION_INFO-1)  ; OSWORD &13
    .byte <(NFS_OSWORD_14-1)                    ; OSWORD &14

;; The high bytes of the Econet OSWORD handlers' addresses less one, indexed by the OSWORD number less &10.
;; See: <NFS_OSWORD_LOW>, <NFS_OSWORD_DISPATCH>
NFS_OSWORD_HIGH:
    .byte >(NFS_OSWORD_TRANSMIT-1)
    .byte >(NFS_OSWORD_RECEIVE-1)
    .byte >(NFS_OSWORD_READ_ARGUMENTS-1)
    .byte >(NFS_OSWORD_STATION_INFO-1)
    .byte >(NFS_OSWORD_14-1)

;; OSWORD &10: transmits, from the caller's 16-byte transmit control block.
;;
;; When a transmission is already in progress (bit 7 of NFS_TRANSMIT_FREE clear), it writes 0 to the block's first
;; byte and returns. Otherwise it takes the flag, copies the block to the first page of the private workspace at
;; NFS_TRANSMIT_OFFSET, where OSBYTE &32 polls it, and starts the transmission with <ECONET_TRANSMIT>.
;; In:    Y = 0, OS_X/OS_Y = the control block
;; Uses:  A, X, Y, NMI_WORKSPACE, NFS_OSWORD_POINTER
NFS_OSWORD_TRANSMIT:
    asl NFS_TRANSMIT_FREE           ; carry = bit 7: idle
    tya
    bcc NFS_OSWORD_STORE
    lda NFS_WORKSPACE_PAGE+1
    sta NFS_OSWORD_POINTER+1
    sta NMI_WORKSPACE+1
    lda #NFS_TRANSMIT_OFFSET
    sta NFS_OSWORD_POINTER
    sta NMI_WORKSPACE
    ldx #NFS_TRANSMIT_SIZE-1
    jsr COPY_CONTROL_BLOCK          ; the carry is set: into the workspace
    jmp ECONET_TRANSMIT

;; OSWORD &12: reads the arguments of the last remote procedure call into the caller's control block.
;;
;; The arguments' length is at NFS_ARGUMENTS_SIZE_OFFSET of the first page of the private workspace, and the
;; arguments follow it. Afterwards <RESTORE_PROTECTION> puts back the protection mask.
;; In:    OS_X/OS_Y = the control block, carry = clear
;; Uses:  A, X, Y, NFS_OSWORD_POINTER
NFS_OSWORD_READ_ARGUMENTS:
    lda NFS_WORKSPACE_PAGE+1
    sta NFS_OSWORD_POINTER+1
    ldy #NFS_ARGUMENTS_SIZE_OFFSET
    lda (NFS_WORKSPACE_PAGE),y
    iny                             ; NFS_ARGUMENTS_OFFSET
    sty NFS_OSWORD_POINTER
    tax
    dex
    ldy #$00
    jsr COPY_CONTROL_BLOCK          ; the carry is clear: to the caller
    jmp RESTORE_PROTECTION

;; OSWORD &13 with A = 9: reads the arguments' length into byte 1 of the control block, and &80 into byte 2.
;; In:    OS_X/OS_Y = the control block
;; Entry: NFS_OSWORD_STORE = writes A to byte Y of the control block
NFS_OSWORD_ARGUMENTS_SIZE:
    ldy #NFS_ARGUMENTS_SIZE_OFFSET
    lda (NFS_WORKSPACE_PAGE),y
    ldy #$01
    sta (OS_X),y
    iny
    lda #NFS_ARGUMENTS_OFFSET
NFS_OSWORD_STORE:
    sta (OS_X),y
    rts

;; The low bytes of pointers one byte before the two station numbers OSWORD &13 0-3 read and write, indexed by the
;; function / 2: the file server's, in page &0D (<NFS_FS_STATION>), and receive block 0's, in the second page of the
;; private workspace (NFS_BLOCK_0_STATION), which is &EB (235) after a hard reset.
NFS_SERVER_POINTERS:
    .byte <(NFS_FS_STATION-1)
    .byte NFS_BLOCK_0_STATION-1

;; OSWORD &13: reads or writes the station's information, as the control block's first byte selects.
;;
;; - 0 and 1: read and write the file server's station and network numbers, in bytes 1-2.
;; - 2 and 3: read and write receive block 0's station and network numbers, in bytes 1-2.
;; - 4 and 5: read and write the protection mask, in byte 1; both write NFS_SAVED_PROTECTION too.
;; - 6 and 7: read and write the handles of the root directory, the current directory and the library, in bytes
;;   1-3, as &20-&27.
;; - 8: reads this station's number into byte 1.
;; - 9: reads the remote procedure call's arguments' length into byte 1 (<NFS_OSWORD_ARGUMENTS_SIZE>).
;; - 10 and above: read the number of the file server's last error into byte 1.
;; In:    A = the function, the control block's first byte, Y = 0, OS_X/OS_Y = the control block
;; Uses:  A, X, Y, NFS_OSWORD_POINTER, NFS_HANDLE_INDEX
NFS_OSWORD_STATION_INFO:
    cmp #$06
    bcs NFS_OSWORD_STATION_INFO_HIGH
    cmp #$04
    bcs NFS_OSWORD_PROTECTION
    lsr a                           ; 0 for the file server, 1 for receive block 0; carry set to write
    ldx #>(NFS_FS_STATION-1)
    tay
    beq NFS_OSWORD_SERVER
    ldx NFS_BLOCKS_PAGE+1
NFS_OSWORD_SERVER:
    stx NFS_OSWORD_POINTER+1
    lda NFS_SERVER_POINTERS,y
    sta NFS_OSWORD_POINTER
    ldx #$01                        ; two bytes
    ldy #$01                        ; from byte 1

;; Copies bytes between an OSWORD control block and the NFS's workspace.
;;
;; With the carry set it copies each byte from the control block into the workspace first; either way it copies each
;; byte from the workspace to the control block, so that the block ends with what the workspace holds.
;; In:    X = the number of bytes less one, Y = the first byte's offset in both, OS_X/OS_Y = the control block,
;;          NFS_OSWORD_POINTER = the workspace's address, carry = set to write the workspace
;; Out:   X = &FF, Y = the offset after the last byte
;; Uses:  A
;; Keeps: carry
COPY_CONTROL_BLOCK:
    bcc COPY_CONTROL_BLOCK_READ
    lda (OS_X),y
    sta (NFS_OSWORD_POINTER),y
COPY_CONTROL_BLOCK_READ:
    lda (NFS_OSWORD_POINTER),y
    sta (OS_X),y
    iny
    dex
    bpl COPY_CONTROL_BLOCK
    rts
NFS_OSWORD_PROTECTION:
    lsr a                           ; carry set to write
    iny
    lda (OS_X),y
    bcs NFS_OSWORD_PROTECTION_SET
    lda NFS_PROTECTION
    sta (OS_X),y
NFS_OSWORD_PROTECTION_SET:
    sta NFS_PROTECTION
    sta NFS_SAVED_PROTECTION
    rts
NFS_OSWORD_READ_STATION:
    ldy #NFS_STATION
    lda (NFS_WORKSPACE_PAGE),y
    ldy #$01
    sta (OS_X),y
    rts
NFS_OSWORD_STATION_INFO_HIGH:
    cmp #$08
    beq NFS_OSWORD_READ_STATION
    cmp #$09
    beq NFS_OSWORD_ARGUMENTS_SIZE
    bpl NFS_OSWORD_READ_ERROR
    ldy #$03
    lsr a                           ; carry set to write
    bcc NFS_OSWORD_READ_HANDLES
    sty NFS_HANDLE_INDEX
NFS_OSWORD_WRITE_HANDLES:
    ldy NFS_HANDLE_INDEX
    lda (OS_X),y
    jsr HANDLE_IN_A_TO_MASK                       ; the handle's mask, in Y
    tya
    ldy NFS_HANDLE_INDEX
    sta NFS_URD-1,y
    dec NFS_HANDLE_INDEX
    bne NFS_OSWORD_WRITE_HANDLES
    rts
NFS_OSWORD_READ_ERROR:
    iny
    lda NFS_LAST_ERROR
    sta (OS_X),y
    rts
NFS_OSWORD_READ_HANDLES:
    lda NFS_URD-1,y
    jsr MASK_TO_HANDLE                       ; as a handle number
    sta (OS_X),y
    dey
    bne NFS_OSWORD_READ_HANDLES
    rts

;; OSWORD &11: opens a receive control block, or reads one and frees it.
;;
;; The control block's first byte is a receive block's number, and the twelve bytes after it are the receive block.
;; With the number 0, it opens the first free block from NFS_FIRST_OPENED_BLOCK up, returning its number in the first
;; byte; with 1, it opens block 1 if it is free. Opening copies the caller's twelve bytes into the block. With any
;; other number of an open block, or 1 when block 1 is open, it copies the block to the caller and frees it. When no
;; block is free, the number is too large, or the block is not open, the first byte becomes 0. (The search for a
;; free block also stops at a block whose control byte is 0, and writes that 0 at the block's offset in the caller's
;; control block rather than its first byte.)
;;
;; While it works, NFS_LISTENING is rotated right a place through the clear carry, which clears bit 7 and moves
;; it to bit 6; ROL moves the bits back afterwards.
;; In:    A = the number, the control block's first byte, Y = 0, OS_X/OS_Y = the control block, carry = clear
;; Uses:  A, X, Y, NFS_OSWORD_POINTER, NFS_RECEIVE_NUMBER
NFS_OSWORD_RECEIVE:
    ldx NFS_BLOCKS_PAGE+1
    stx NFS_OSWORD_POINTER+1
    sty NFS_OSWORD_POINTER
    ror NFS_LISTENING
    lda (OS_X),y
    sta NFS_RECEIVE_NUMBER
    bne NFS_OSWORD_RECEIVE_BLOCK
    lda #NFS_FIRST_OPENED_BLOCK
NFS_OSWORD_RECEIVE_FIND_FREE:
    jsr FIND_RECEIVE_BLOCK
    bcs NFS_OSWORD_RECEIVE_FAIL
    lsr a
    lsr a
    tax
    lda (NFS_OSWORD_POINTER),y
    beq NFS_OSWORD_RECEIVE_FAIL
    cmp #NFS_FREE_BLOCK
    beq NFS_OSWORD_RECEIVE_ALLOCATED
    inx
    txa
    bne NFS_OSWORD_RECEIVE_FIND_FREE
NFS_OSWORD_RECEIVE_ALLOCATED:
    txa
    ldx #$00
    sta (OS_X,x)                    ; the number, for the caller
NFS_OSWORD_RECEIVE_BLOCK:
    jsr FIND_RECEIVE_BLOCK
    bcs NFS_OSWORD_RECEIVE_FAIL
    dey
    sty NFS_OSWORD_POINTER          ; one byte before the block, as the caller's block has its number first
    lda #$C0
    ldy #$01
    ldx #NFS_RECEIVE_BLOCK_SIZE-1
    cpy NFS_RECEIVE_NUMBER          ; carry set when the caller asked for 0 or 1
    adc (NFS_OSWORD_POINTER),y      ; &C0 + &3F + carry is 0 for a free block
    beq NFS_OSWORD_RECEIVE_COPY     ; free, and the carry set: open it
    bmi NFS_OSWORD_RECEIVE_NOT_OPEN
NFS_OSWORD_RECEIVE_READ:
    clc
NFS_OSWORD_RECEIVE_COPY:
    jsr COPY_CONTROL_BLOCK
    bcs NFS_OSWORD_RECEIVE_DONE
    lda #NFS_FREE_BLOCK           ; read: free the block
    ldy #$01
    sta (NFS_OSWORD_POINTER),y
    bne NFS_OSWORD_RECEIVE_DONE
NFS_OSWORD_RECEIVE_NOT_OPEN:
    adc #$01                        ; zero only for a free block the caller cannot open
    bne NFS_OSWORD_RECEIVE_READ
    dey
NFS_OSWORD_RECEIVE_FAIL:
    sta (OS_X),y
NFS_OSWORD_RECEIVE_DONE:
    rol NFS_LISTENING
    rts

;; Sets the buffer of the control block that OSWORD &14 transmits from, offset &18 of the second page, to the
;; caller's control block.
;;
;; The buffer starts at the control block plus one plus the carry, and ends at the control block plus its byte 1.
;; In:    OS_X/OS_Y = the control block, carry = added to the start
;; Out:   Y = NFS_OSWORD_14_END+1
;; Uses:  A
;; Entry: SET_OSWORD_14_POINTER = stores A and OS_Y plus the carry at offsets Y and Y+1 of the second page
SET_OSWORD_14_BUFFER:
    ldy #NFS_OSWORD_14_START
    lda OS_X
    adc #$01
    jsr SET_OSWORD_14_POINTER
    ldy #$01
    lda (OS_X),y
    ldy #NFS_OSWORD_14_END
    adc OS_X
SET_OSWORD_14_POINTER:
    sta (NFS_BLOCKS_PAGE),y
    iny
    lda OS_Y
    adc #$00
    sta (NFS_BLOCKS_PAGE),y
    rts
