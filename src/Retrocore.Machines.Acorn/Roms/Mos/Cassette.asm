; ---------------------------------------------------------------------------------------------------------------------
; The cassette filing system and the ROM filing system: OSARGS, OSFSC, OSFILE, OSFIND, OSBGET and OSBPUT, *OPT and
; the file search. The block reading and writing they share is in CassetteFiles.asm.
;
; A file on tape is a run of blocks, each a header and up to 256 bytes of data (the Advanced User Guide, section
; 16.10): high tone, a synchronisation byte (&2A, "*"), the file name ending in a zero, the load and execution
; addresses, the block number and length, a flag byte, four spare bytes and the header's CRC, then the data and its
; CRC. The ROM filing system reads the same format from paged ROMs and speech PHROMs, where "+" ends a ROM and "#"
; stands for a header that only moves the block number on.
; ---------------------------------------------------------------------------------------------------------------------

; The filing system scratch space, &B0-&BF, as the cassette filing system uses it.

CFS_DATA_ADDRESS = FS_SCRATCH       ;; the address of the current block's data, four bytes, &FFFFxxxx for this machine
CFS_SAVE_END = FS_SCRATCH + 4       ;; while saving, the address after the last byte to save, four bytes
CFS_WANTED_BLOCK = FS_SCRATCH + 4   ;; the number of the block expected next, two bytes
CFS_SEARCH_BLOCK = FS_SCRATCH + 6   ;; the number of the block <SEARCH> stops at, two bytes
CFS_MESSAGE_POINTER = FS_SCRATCH + 8 ;; the pointer <PRINT_INLINE> walks through a message, then jumps through
CFS_ERRORS = FS_SCRATCH + 10        ;; zero, or decremented once for each block error reported since the last line
CFS_CURRENT_OPTIONS = FS_SCRATCH + 11 ;; the operation's options, a nibble of <CFS_OPTIONS> in bits 4-7
CFS_BYTE = FS_SCRATCH + 13          ;; the byte being written or just read, and the discard flag while data arrives
CFS_CRC = FS_SCRATCH + 14           ;; the CRC being worked out, low byte then high byte

; The filing system's own workspace, &C0-&CF, as the cassette filing system uses it.

CFS_BYTE_DONE = FS_WORKSPACE        ;; bit 7 set once the interrupt has taken a byte to write or delivered one read
CFS_HEADER_BAD = FS_WORKSPACE + 1   ;; nonzero when the last header read failed its CRC
CFS_RECEIVE_STATE = FS_WORKSPACE + 2 ;; the state of <CASSETTE_INTERRUPT>'s reading, 0 (idle) to 5
CFS_MOTOR_MODE = FS_WORKSPACE + 3   ;; the Y for OSBYTE &89: 0 to write, nonzero to read
CFS_BPUT_BYTE = FS_WORKSPACE + 4    ;; the byte OSBPUT is writing
CFS_ACIA_SPEED = FS_WORKSPACE + 6   ;; the 6850's counter divide for the tape speed: 5 for 1200 baud, 6 for 300
CFS_GAP = FS_WORKSPACE + 7          ;; the gap before each block but the first, in tenths of a second, less one
CFS_OSFILE_BLOCK = FS_WORKSPACE + 8 ;; the address of the OSFILE control block
CFS_TRANSMITTING = FS_WORKSPACE + 10 ;; nonzero while the 6850 is writing to tape
CFS_CRC_BITS = FS_WORKSPACE + 11    ;; the bit counter of <ADD_TO_CRC>, a bit moving down from bit 7
CFS_FILE_LENGTH = FS_WORKSPACE + 12 ;; a file's length, two bytes, as the last block's catalogue line works it out

; The header of the block OSBPUT is filling, laid out as the tape header from its name on.

CFS_OUTPUT_LOAD = CFS_OUTPUT_HEADER + 12 ;; the output block's load address, four bytes
CFS_OUTPUT_NUMBER = CFS_OUTPUT_HEADER + 20 ;; the output block's number, two bytes
CFS_OUTPUT_LENGTH = CFS_OUTPUT_HEADER + 22 ;; the output block's length, two bytes
CFS_OUTPUT_FLAGS = CFS_OUTPUT_HEADER + 24 ;; the output block's flag

; Bits of CFS_STATUS.

CFS_INPUT_OPEN = %00000001          ;; CFS_STATUS: a file is open for input
CFS_OUTPUT_OPEN = %00000010         ;; CFS_STATUS: a file is open for output
CFS_CATALOGUING = %00001000         ;; CFS_STATUS: *CAT is running
CFS_AT_EOF = %01000000              ;; CFS_STATUS: the input file is at its end
CFS_EOF_WARNED = %10000000          ;; CFS_STATUS: OSBGET has returned the end of the file once

; Bits of a block's flag byte.

BLOCK_PROTECTED = %00000001         ;; a block's flag: the file can only be *RUN
BLOCK_LAST = %10000000              ;; a block's flag: the file's last block

; Bits of CFS_OPTIONS (both nibbles) and CFS_CURRENT_OPTIONS (the high nibble).

OPT_ABORT = %00010000               ;; CFS_CURRENT_OPTIONS: abort on an error
OPT_RETRY = %00100000               ;; CFS_CURRENT_OPTIONS: ask for a retry on an error
OPT_LONG_MESSAGES = %01000000       ;; CFS_CURRENT_OPTIONS: extended messages
OPT_MESSAGES = %10000000            ;; CFS_CURRENT_OPTIONS: messages
OPT_ERROR_BITS = %00110011          ;; CFS_OPTIONS: both nibbles' error actions, which *OPT 1 keeps
OPT_MESSAGE_BITS = %11001100        ;; CFS_OPTIONS: both nibbles' message settings, which *OPT 2 keeps

; The tape format.

SYNC_BYTE = '*'                     ;; the byte that starts a block's header on tape and in a ROM
ROM_END_MARKER = '+'                ;; in a ROM filing system ROM: the end of this ROM's files
ROM_SHORT_HEADER = '#'              ;; in a ROM filing system ROM: a header that only moves the block number on
LEADER_TENTHS = 50                  ;; the high tone before a file's first block and after its last, less a tenth
LOAD_SAVE_GAP = 6                   ;; the gap between blocks for LOAD and SAVE, less a tenth, in tenths of a second
DEFAULT_GAP = 25                    ;; the gap between sequential blocks that *OPT 3 restores, less a tenth
CFS_NAME_SIZE = 11                  ;; the room for a file name in the workspace: ten characters and a zero
FSC_CALLS = 7                       ;; the OSFSC calls the cassette filing system takes, 0-6

; The 6850 and the serial ULA, as the cassette filing system sets them.

CFS_ACIA_RESET = %00000011          ;; 6850 control: a master reset
CFS_ACIA_TX_EMPTY = %00000010       ;; 6850 status: the transmit data register is empty
CFS_ACIA_IDLE = %00010000           ;; 6850 control, ORed with the speed: no interrupts, RTS low, 8 bits, 1 stop bit
CFS_ACIA_WRITING = %00110000        ;; 6850 control, ORed with the speed: the transmit interrupt as well
CFS_ACIA_READING = %11010000        ;; 6850 control, ORed with the speed: the receive interrupt, RTS high
CFS_ULA_MOTOR_OFF = %00000101       ;; serial ULA: the cassette, its motor off
CFS_ULA_MOTOR_ON = %10000101        ;; serial ULA: the cassette, its motor on

; Calls.

OSBYTE_ACKNOWLEDGE_ESCAPE = $7E     ;; OSBYTE &7E: acknowledge an escape
OSBYTE_CASSETTE_MOTOR = $89         ;; OSBYTE &89: switch the cassette motor relay
OSFIND_OPEN_INPUT = $40             ;; OSFIND &40: open a file for input
CFS_TUBE_READ = 0                   ;; Tube transfer: start reading the second processor's memory
CFS_TUBE_WRITE = 1                  ;; Tube transfer: start writing the second processor's memory
CFS_TUBE_EXECUTE = 4                ;; Tube transfer: start the second processor running at an address
CFS_TUBE_RELEASE = $80              ;; Tube call: the filing system's release, claimant 0
CFS_TUBE_CLAIM = $C0                ;; Tube call: the filing system's claim, claimant 0

; Errors.

ERROR_ESCAPE = $11                  ;; the "Escape" error
ERROR_LOCKED = $D5                  ;; the "Locked" error, loading a protected file
ERROR_FILE_NOT_FOUND = $D6          ;; the "File not found" error
ERROR_BAD_ROM = $D7                 ;; the "Bad ROM" error
ERROR_DATA = $D8                    ;; the "Data?" error: a CRC failed
ERROR_BLOCK = $DA                   ;; the "Block?" error: a block out of sequence
ERROR_FILE = $DB                    ;; the "File?" error: a block of another file
ERROR_CHANNEL = $DE                 ;; the "Channel" error: a handle that is not open
ERROR_EOF = $DF                     ;; the "EOF" error: reading past the end of a file

;; The cassette and ROM filing systems' OSARGS: reads which filing system is active.
;;
;; Only OSARGS with A = 0 and Y = 0 does anything. The number comes from the tape speed's counter divide (5 or 6,
;; whose bit 2 is cleared to leave 1 or 2) and <CFS_RFS_SWITCH> (0, or 2 for the ROM filing system), which is ORed
;; in on both sides of a shift so that 1 and 2 both become 3.
;; In: A = the call, Y = a handle
;; Out: A = 1 for the cassette at 1200 baud, 2 at 300 baud, or 3 for the ROM filing system, when A and Y were 0;
;;   otherwise A is unchanged
;; Keeps: X, Y
ARGSV_DEFAULT:
    ora #$00
    bne ARGSV_DEFAULT_DONE
    cpy #$00
    bne ARGSV_DEFAULT_DONE
    lda CFS_ACIA_SPEED
    and #%11111011                  ; 5 or 6 becomes 1 or 2
    ora CFS_RFS_SWITCH
    asl a
    ora CFS_RFS_SWITCH
    lsr a
ARGSV_DEFAULT_DONE:
    rts

;; The OSFSC calls the cassette filing system handles, each an address less one for <FSCV_DEFAULT> to return to.
;;
;; Indexed by the call number: *OPT (0), the end of file check (1), */ (2), an unrecognised command (3), *RUN (4),
;; *CAT (5) and a new filing system taking over (6), which closes the *SPOOL and *EXEC files.
;; See: <FSCV_DEFAULT>
FSC_ROUTINES:
    .word SET_OPTIONS-1             ; 0: *OPT
    .word CHECK_EOF-1               ; 1: the end of a file
    .word RUN_FILE-1                ; 2: */
    .word USERV_DEFAULT-1           ; 3: an unrecognised command is "Bad command"
    .word RUN_FILE-1                ; 4: *RUN
    .word CATALOGUE-1               ; 5: *CAT
    .word CLOSE_SPOOL_AND_EXEC-1                   ; 6: a new filing system
    .assert * - FSC_ROUTINES = FSC_CALLS * 2, "FSC_ROUTINES has an entry for each call."

;; The cassette and ROM filing systems' OSFSC: dispatches a filing system control call.
;;
;; It pushes the routine's address from <FSC_ROUTINES> and returns to it, so the routine returns to the caller.
;; Calls 7 and above do nothing.
;; In: A = the call, X and Y = its parameters
;; Uses: FS_SCRATCH+12
;; See: <FSC_ROUTINES>
FSCV_DEFAULT:
    cmp #FSC_CALLS
    bcs ARGSV_DEFAULT_DONE
    stx FS_SCRATCH+12
    asl a
    tax
    lda FSC_ROUTINES+1,x
    pha
    lda FSC_ROUTINES,x
    pha
    ldx FS_SCRATCH+12
    rts

;; Loads the file named in <CFS_SEARCH_NAME>, for OSFILE and *RUN.
;;
;; It finds block 0, then reads the blocks one by one to <CFS_DATA_ADDRESS> or across the Tube, retrying or
;; aborting on an error as *OPT 2 says. A nonzero <CFS_BLOCK_EXEC> asks for the file's own load address, which must
;; not be &FFFFFFFF ("Bad address"). A protected file can only be *RUN, and then ESCAPE is disabled and BREAK clears
;; memory. At the end it writes the file's length to bytes 10-13 of the control block at <CFS_OSFILE_BLOCK>, as
;; <SHOW_BLOCK_INFO> worked it out from the last block. For *RUN that is the last OSFILE call's block. "Loading"
;; is shown when the first block is found.
;; In: A = &FF for OSFILE or 0 for *RUN, CFS_DATA_ADDRESS = the load address, CFS_BLOCK_EXEC = nonzero to load at
;;   the file's own address
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Locked", "Bad address", and the block errors
;; Entry: LOCKED_ERROR = releases the cassette and gives the "Locked" error
;; See: <RUN_FILE>, <FILEV_DEFAULT>, <LOAD_BLOCK>
LOAD_FILE:
    php
    pha
    jsr SET_LOAD_SAVE_OPTIONS
    lda CFS_BLOCK_EXEC
    pha
    jsr FIND_FILE
    pla
    beq LOAD_FILE_CHECK_LOCK
    ldx #$03                        ; take the file's own load address, ANDing its bytes
    lda #$FF
LOAD_FILE_COPY_ADDRESS:
    pha
    lda CFS_BLOCK_LOAD,x
    sta CFS_DATA_ADDRESS,x
    pla
    and CFS_DATA_ADDRESS,x
    dex
    bpl LOAD_FILE_COPY_ADDRESS
    cmp #$FF
    bne LOAD_FILE_CHECK_LOCK
    jsr STOP_TAPE
    jmp BAD_ADDRESS                       ; "Bad address"
LOAD_FILE_CHECK_LOCK:
    lda CFS_BLOCK_FLAGS
    lsr a                           ; carry = protected
    pla
    beq LOAD_FILE_RUN
    bcc LOAD_FILE_BLOCK
LOCKED_ERROR:
    jsr RELEASE_CASSETTE
    brk
    .byte ERROR_LOCKED, "Locked", 0
LOAD_FILE_RUN:
    bcc LOAD_FILE_BLOCK
    lda #%00000011                  ; *RUN of a protected file: no ESCAPE, and BREAK clears memory
    sta ESCAPE_BREAK_EFFECT
LOAD_FILE_BLOCK:
    lda #OPT_ABORT | OPT_RETRY
    and CFS_CURRENT_OPTIONS
    beq LOAD_FILE_RECEIVE           ; ignoring errors: read the data whatever the header
    lda CFS_HEADER_BAD
    bne LOAD_FILE_READ
LOAD_FILE_RECEIVE:
    tya
    pha
    jsr START_TUBE_LOAD
    pla
    tay
    jsr RECEIVE_DATA
LOAD_FILE_READ:
    jsr LOAD_BLOCK
    bne LOAD_FILE_RETRY
    jsr SET_NEXT_BLOCK
    bit CFS_BLOCK_FLAGS
    bmi LOAD_FILE_DONE
    jsr NEXT_PAGE
    jsr READ_HEADER
    bne LOAD_FILE_BLOCK
LOAD_FILE_DONE:
    ldy #$0A                        ; the control block's length field
    lda CFS_FILE_LENGTH
    sta (CFS_OSFILE_BLOCK),y
    iny
    lda CFS_FILE_LENGTH+1
    sta (CFS_OSFILE_BLOCK),y
    lda #$00
    iny
    sta (CFS_OSFILE_BLOCK),y
    iny
    sta (CFS_OSFILE_BLOCK),y
    plp
;; Ends a file's transfer: rings the bell if messages are on, releases the cassette, and ends the line.
;;
;; The line is left alone after a block error, whose message already ended it.
;; Uses: A, X, Y
;; Entry: FINISH_LINE = only ends the line, CFS_NEW_LINE = ends the line if messages are on, whatever the errors,
;;   keeping the flags
;; See: <STOP_TAPE>, <PRINT_CFS_MESSAGE>
FINISH_TAPE:
    jsr STOP_TAPE
FINISH_LINE:
    bit CFS_ERRORS
    bmi FINISH_TAPE_DONE
CFS_NEW_LINE:
    php
    jsr PRINT_CFS_MESSAGE
    .byte $0D, 0
    plp
FINISH_TAPE_DONE:
    rts
LOAD_FILE_RETRY:
    jsr FIND_BLOCK                  ; find the block again
    bne LOAD_FILE_BLOCK             ; always taken

;; Reads a file name from a command line or OSFILE block into <CFS_SEARCH_NAME>, with GSREAD.
;;
;; A name of more than ten characters, or one with a zero character in it, is a "Bad string".
;; In: X/Y = the address of the name
;; Out: X = the name's length, A = 0, CFS_SEARCH_NAME = the name, ending in a zero
;; Uses: Y, TEXT_POINTER
;; Errors: "Bad string"
;; Entry: READ_FILE_NAME_BAD = gives the "Bad string" error
;; See: <GSREAD_HANDLER>
READ_FILE_NAME:
    stx TEXT_POINTER
    sty TEXT_POINTER+1
    ldy #$00
    jsr GSINIT_SPACE_ENDS                       ; GSINIT, the name ending at a space
    ldx #$00
READ_FILE_NAME_LOOP:
    jsr GSREAD_HANDLER
    bcs READ_FILE_NAME_END
    beq READ_FILE_NAME_BAD
    sta CFS_SEARCH_NAME,x
    inx
    cpx #CFS_NAME_SIZE
    bne READ_FILE_NAME_LOOP
READ_FILE_NAME_BAD:
    jmp BAD_STRING                       ; "Bad string"
READ_FILE_NAME_END:
    lda #$00
    sta CFS_SEARCH_NAME,x
    rts

;; The cassette and ROM filing systems' OSFILE: loads (A = &FF) or saves (A = 0) a whole file.
;;
;; It reads the name, copies the load and execution addresses into <CFS_BLOCK_LOAD> and <CFS_DATA_ADDRESS>, and
;; for a save the start and end addresses into CFS_DATA_ADDRESS and <CFS_SAVE_END>. A save asks for RECORD and
;; writes the file in blocks of 256 bytes, the last with the rest. Other values of A return at once.
;; In: A = &FF to load or 0 to save, X/Y = the control block
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Bad string", and the errors of <LOAD_FILE> and <WRITE_BLOCK>
;; See: <LOAD_FILE>, <WRITE_BLOCK>
FILEV_DEFAULT:
    pha
    stx CFS_OSFILE_BLOCK
    sty CFS_OSFILE_BLOCK+1
    ldy #$00
    lda (CFS_OSFILE_BLOCK),y
    tax
    iny
    lda (CFS_OSFILE_BLOCK),y
    tay
    jsr READ_FILE_NAME
    ldy #$02
FILEV_DEFAULT_COPY:
    lda (CFS_OSFILE_BLOCK),y        ; bytes 2-9, the load and execution addresses
    sta CFS_BLOCK_LOAD-2,y
    sta a:CFS_DATA_ADDRESS-2,y
    iny
    cpy #$0A
    bne FILEV_DEFAULT_COPY
    pla
    beq SAVE_FILE
    cmp #$FF
    bne FINISH_TAPE_DONE
    jmp LOAD_FILE
SAVE_FILE:
    sta CFS_BLOCK_NUMBER
    sta CFS_BLOCK_NUMBER+1
SAVE_FILE_COPY:
    lda (CFS_OSFILE_BLOCK),y        ; bytes 10-17, the start and end addresses
    sta a:CFS_DATA_ADDRESS-10,y
    iny
    cpy #$12
    bne SAVE_FILE_COPY
    txa
    beq READ_FILE_NAME_BAD          ; no name
    jsr SET_LOAD_SAVE_OPTIONS
    jsr PROMPT_RECORD
    lda #CFS_TUBE_READ
    jsr START_TUBE_TRANSFER
    jsr START_WRITING
SAVE_FILE_BLOCK:
    sec                             ; the length left, CFS_SAVE_END - CFS_DATA_ADDRESS, into CFS_BLOCK_LENGTH..+2
    ldx #$FD
SAVE_FILE_LENGTH:
    lda $FF00 + CFS_SAVE_END + 3,x  ; X = &FD-&FF wraps round to zero page
    sbc $FF00 + CFS_DATA_ADDRESS + 3,x
    sta CFS_BLOCK_LENGTH + 3 - $100,x
    inx
    bne SAVE_FILE_LENGTH
    tay
    bne SAVE_FILE_FULL_BLOCK        ; 64K or more left
    cpx CFS_BLOCK_LENGTH            ; carry = set when the low byte is 0
    lda #$01
    sbc CFS_BLOCK_LENGTH+1
    bcc SAVE_FILE_FULL_BLOCK        ; more than 256 bytes left
    ldx #BLOCK_LAST
    bne SAVE_FILE_WRITE             ; always taken
SAVE_FILE_FULL_BLOCK:
    lda #$01                        ; 256 bytes
    sta CFS_BLOCK_LENGTH+1
    stx CFS_BLOCK_LENGTH
SAVE_FILE_WRITE:
    stx CFS_BLOCK_FLAGS
    jsr WRITE_BLOCK
    bmi STORE_STATUS_DONE
    jsr NEXT_PAGE
    inc CFS_BLOCK_NUMBER
    bne SAVE_FILE_BLOCK
    inc CFS_BLOCK_NUMBER+1
    bne SAVE_FILE_BLOCK             ; taken short of 65536 blocks, so always
;; OSFSC 2 and 4: *RUN and */, which load a file at its own address and run it.
;;
;; A file whose execution address is not &FFFFxxxx runs in the second processor, when there is one.
;; In: X/Y = the file name
;; Errors: those of <LOAD_FILE>
;; See: <LOAD_FILE>
RUN_FILE:
    jsr READ_FILE_NAME
    ldx #$FF
    stx CFS_BLOCK_EXEC              ; load at the file's own address
    jsr LOAD_FILE
    bit TUBE_PRESENT
    bpl RUN_FILE_HERE
    lda CFS_BLOCK_EXEC+2
    and CFS_BLOCK_EXEC+3
    cmp #$FF
    bne RUN_FILE_TUBE
RUN_FILE_HERE:
    jmp (CFS_BLOCK_EXEC)
RUN_FILE_TUBE:
    ldx #<CFS_BLOCK_EXEC
    ldy #>CFS_BLOCK_EXEC
    lda #CFS_TUBE_EXECUTE
    jmp CALL_TUBE

;; OSFSC 5: *CAT, which lists the blocks on the tape until ESCAPE, or the files in the ROMs.
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; See: <SEARCH>
CATALOGUE:
    lda #CFS_CATALOGUING
    jsr SET_STATUS_BITS
    jsr SET_LOAD_SAVE_OPTIONS
    lda #$00
    jsr SEARCH
    jsr RESTORE_SERIAL
;; Clears the cataloguing bit of <CFS_STATUS>.
;; Out: A = CFS_STATUS
;; Keeps: X, Y, carry
;; Entry: CLEAR_STATUS_BITS = clears the bits clear in A, STORE_STATUS = stores A
END_CATALOGUE:
    lda #$FF - CFS_CATALOGUING
CLEAR_STATUS_BITS:
    and CFS_STATUS
STORE_STATUS:
    sta CFS_STATUS
STORE_STATUS_DONE:
    rts

;; Marks the input file as at its end.
;; Out: A = CFS_STATUS
;; Keeps: X, Y, carry
;; Entry: SET_STATUS_BITS = sets the bits set in A
SET_EOF:
    lda #CFS_AT_EOF
SET_STATUS_BITS:
    ora CFS_STATUS
    bne STORE_STATUS                ; always taken

;; Reads headers until it finds the file and block wanted, or lists every block for *CAT.
;;
;; With A = &FF it looks for a block of the file in <CFS_SEARCH_NAME> and returns with its header read, the data
;; still to come. When errors are ignored any block of the file will do; otherwise it must be block
;; <CFS_SEARCH_BLOCK>. With A = 0 it never finds anything. Blocks it passes are shown as a catalogue, and their data
;; read and checked, unless the ROM filing system can skip the rest of the file. On tape the search goes on until
;; ESCAPE; in the ROM filing system it ends after the last ROM.
;; In: A = &FF to search or 0 to catalogue, CFS_SEARCH_BLOCK = the block to find
;; Out: overflow = clear when the ROM filing system ran out of ROMs
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; See: <FIND_BLOCK>, <CATALOGUE>, <READ_HEADER>
SEARCH:
    pha
    lda CFS_RFS_SWITCH
    beq SEARCH_FIRST
    jsr RFS_START_SEARCH                       ; start the ROM filing system before its first ROM
    jsr RFS_NEXT_ROM                       ; and move to the first ROM
    bcc SEARCH_FIRST
    clv
    bvc SEARCH_DONE                 ; always taken: no ROMs
SEARCH_FIRST:
    jsr READ_HEADER
    lda CFS_BLOCK_NUMBER            ; whatever block comes first is the one expected
    sta CFS_WANTED_BLOCK
    lda CFS_BLOCK_NUMBER+1
    sta CFS_WANTED_BLOCK+1
    ldx #$FF
    stx CFS_LAST_FLAGS
    inx
    stx CFS_ERRORS
    beq SEARCH_CHECK                ; always taken
SEARCH_NEXT:
    jsr SET_NEXT_BLOCK
    jsr READ_HEADER
SEARCH_CHECK:
    lda CFS_RFS_SWITCH
    beq SEARCH_MATCH
    bvc SEARCH_DONE                 ; out of ROMs
SEARCH_MATCH:
    pla
    pha
    beq SEARCH_LIST
    jsr COMPARE_NAMES
    bne SEARCH_SKIP
    lda #OPT_ABORT | OPT_RETRY
    and CFS_CURRENT_OPTIONS
    beq SEARCH_DONE                 ; ignoring errors: any block of the file
    lda CFS_BLOCK_NUMBER
    cmp CFS_SEARCH_BLOCK
    bne SEARCH_SKIP
    lda CFS_BLOCK_NUMBER+1
    cmp CFS_SEARCH_BLOCK+1
    bne SEARCH_SKIP
SEARCH_DONE:
    pla
    rts
SEARCH_SKIP:
    lda CFS_RFS_SWITCH
    beq SEARCH_LIST
SEARCH_SKIP_ROM_FILE:
    jsr RFS_SKIP_FILE                       ; skip to the end of the ROM file
SEARCH_NEXT_FILE:
    lda #$FF                        ; expect block 0 next
    sta CFS_BLOCK_NUMBER
    sta CFS_BLOCK_NUMBER+1
    bne SEARCH_NEXT                 ; always taken
SEARCH_LIST:
    bvc SEARCH_CHECK_BLOCK          ; no header
    lda #$FF
    jsr RECEIVE_DATA_MODE           ; read the data to check it, and drop it
SEARCH_CHECK_BLOCK:
    ldx #$00                        ; report errors, but never retry or abort
    jsr CHECK_BLOCK
    lda CFS_RFS_SWITCH
    beq SEARCH_FOLLOW
    bit CFS_CURRENT_OPTIONS
    bvc SEARCH_SKIP_ROM_FILE        ; without extended messages, one line for each ROM file
SEARCH_FOLLOW:
    bit CFS_BLOCK_FLAGS
    bmi SEARCH_NEXT_FILE
    bpl SEARCH_NEXT                 ; always taken

;; The cassette and ROM filing systems' OSFIND: opens a file for input or output, or closes one or all.
;;
;; One file can be open for input, handle 1 (3 in the ROM filing system), and one for output, handle 2. Opening for
;; input reads the file's first block into <INPUT_BUFFER>; opening for output asks for RECORD, then sets up the
;; header in <CFS_OUTPUT_HEADER> with load and execution addresses of &FFFFFFFF. Closing the output file writes its
;; last block. Closing all files also closes the *SPOOL and *EXEC files.
;; In: A = 0 to close or &40, &80 or &C0 to open, Y = the handle to close (0 for all), X/Y = the name to open
;; Out: A = the handle opened, or 0
;; Keeps: X, Y
;; Uses: FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Bad string", "Channel", and those of <FIND_FILE> and <READ_INPUT_BLOCK>
;; See: <CLOSE_OUTPUT>, <READ_INPUT_BLOCK>
FINDV_DEFAULT:
    sta FS_SCRATCH+12
    txa
    pha
    tya
    pha
    lda FS_SCRATCH+12
    bne FINDV_OPEN
    tya
    bne FINDV_CLOSE
    jsr CLOSE_SPOOL_AND_EXEC                       ; close *SPOOL and *EXEC
    jsr CLOSE_OUTPUT
FINDV_CLOSE_INPUT:
    lsr CFS_STATUS                  ; clear CFS_INPUT_OPEN
    asl CFS_STATUS
    bcc FINDV_CLOSED                ; always taken
FINDV_CLOSE:
    lsr a
    bcs FINDV_CLOSE_INPUT           ; handle 1 or 3
    lsr a
    bcs FINDV_CLOSE_OUTPUT          ; handle 2
    jmp CHANNEL_ERROR
FINDV_CLOSE_OUTPUT:
    jsr CLOSE_OUTPUT
FINDV_CLOSED:
    jmp CFS_RETURN
FINDV_OPEN:
    jsr READ_FILE_NAME
    bit FS_SCRATCH+12
    bvc FINDV_OPEN_OUTPUT
    lda #$00
    sta CFS_INPUT_OFFSET
    sta CFS_NEXT_BLOCK
    sta CFS_NEXT_BLOCK+1
    lda #$FF - (CFS_INPUT_OPEN | CFS_AT_EOF | CFS_EOF_WARNED)
    jsr CLEAR_STATUS_BITS
    jsr SET_SEQUENTIAL_OPTIONS
    php
    jsr FIND_FILE
    jsr READ_INPUT_BLOCK
    plp
    ldx #$FF
FINDV_COPY_NAME:
    inx
    lda CFS_BLOCK_NAME,x
    sta CFS_INPUT_NAME,x
    bne FINDV_COPY_NAME
    lda #CFS_INPUT_OPEN
    jsr SET_STATUS_BITS
    lda CFS_BLOCK_SIZE
    ora CFS_BLOCK_SIZE+1
    bne FINDV_INPUT_HANDLE
    jsr SET_EOF                     ; an empty first block
FINDV_INPUT_HANDLE:
    lda #$01                        ; handle 1, or 3 for the ROM filing system
    ora CFS_RFS_SWITCH
    bne CFS_RETURN_A                ; always taken
FINDV_OPEN_OUTPUT:
    txa
    bne FINDV_OUTPUT_NAME
    jmp BAD_STRING                       ; "Bad string": no name
FINDV_OUTPUT_NAME:
    ldx #$FF
FINDV_OUTPUT_NAME_LOOP:
    inx
    lda CFS_SEARCH_NAME,x
    sta CFS_OUTPUT_HEADER,x
    bne FINDV_OUTPUT_NAME_LOOP
    lda #$FF                        ; load and execution addresses &FFFFFFFF
    ldx #$08
FINDV_OUTPUT_ADDRESSES:
    sta CFS_OUTPUT_LOAD-1,x
    dex
    bne FINDV_OUTPUT_ADDRESSES
    txa                             ; clear the block number to the output offset
    ldx #CFS_OUTPUT_NUMBER - CFS_OUTPUT_HEADER
FINDV_OUTPUT_CLEAR:
    sta CFS_OUTPUT_HEADER,x
    inx
    cpx #CFS_OUTPUT_OFFSET + 1 - CFS_OUTPUT_HEADER
    bne FINDV_OUTPUT_CLEAR
    rol CFS_OUTPUT_LENGTH+1         ; the CPX left carry set: a length of 256
    jsr SET_LOAD_SAVE_OPTIONS
    jsr PROMPT_RECORD
    jsr RELEASE_CASSETTE
    lda #CFS_OUTPUT_OPEN
    jsr SET_STATUS_BITS
    lda #$02                        ; handle 2
;; Returns from a filing system call with A as its result and the caller's X and Y.
;;
;; The caller pushed X and then Y.
;; In: A = the result
;; Out: A = the result, X and Y = as pushed
;; Uses: FS_SCRATCH+12
;; Entry: CFS_RETURN = returns FS_SCRATCH+12
CFS_RETURN_A:
    sta FS_SCRATCH+12
CFS_RETURN:
    pla
    tay
    pla
    tax
    lda FS_SCRATCH+12
CLOSE_OUTPUT_DONE:
    rts

;; Closes the output file, if one is open, writing what is in its buffer as the last block.
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; See: <WRITE_OUTPUT_BLOCK>
CLOSE_OUTPUT:
    lda #CFS_OUTPUT_OPEN
    and CFS_STATUS
    beq CLOSE_OUTPUT_DONE
    lda #$00
    sta CFS_OUTPUT_LENGTH+1
    lda #BLOCK_LAST
    ldx CFS_OUTPUT_OFFSET
    stx CFS_OUTPUT_LENGTH
    sta CFS_OUTPUT_FLAGS
    jsr WRITE_OUTPUT_BLOCK
    lda #$FF - CFS_OUTPUT_OPEN
    jmp CLEAR_STATUS_BITS

;; Writes the output file's buffer, <OUTPUT_BUFFER>, to tape as its next block.
;;
;; It copies the header from <CFS_OUTPUT_HEADER> into the block header, writes the block, and counts it.
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; See: <WRITE_BLOCK>
WRITE_OUTPUT_BLOCK:
    jsr SET_SEQUENTIAL_OPTIONS
    ldx #CFS_HEADER_CRC - CFS_BLOCK_LOAD
WRITE_OUTPUT_BLOCK_COPY:
    lda CFS_OUTPUT_LOAD,x
    sta CFS_BLOCK_LOAD,x
    dex
    bpl WRITE_OUTPUT_BLOCK_COPY
    stx CFS_DATA_ADDRESS+2          ; the data is at &FFFF0900
    stx CFS_DATA_ADDRESS+3
    inx
    stx CFS_DATA_ADDRESS
    lda #>OUTPUT_BUFFER
    sta CFS_DATA_ADDRESS+1
    ldx #<(CFS_OUTPUT_HEADER - 1)
    jsr COPY_SEARCH_NAME
    sta CFS_LAST_FLAGS
    jsr MOTOR_ON_WRITING
    jsr START_WRITING
    jsr WRITE_BLOCK
    inc CFS_OUTPUT_NUMBER
    bne WRITE_OUTPUT_BLOCK_DONE
    inc CFS_OUTPUT_NUMBER+1
WRITE_OUTPUT_BLOCK_DONE:
    rts

;; The cassette and ROM filing systems' OSBGET: reads the next byte of the input file.
;;
;; The block in <INPUT_BUFFER> is used up a byte at a time. Its last byte is kept in <CFS_LAST_CHARACTER>, so that
;; the next block can be read before the byte is returned. Offsets wrap at 256, so only a full block can be followed
;; by another. At the end of the file the first call returns &FE with carry set, and the next is an "EOF" error.
;; In: Y = the handle
;; Out: A = the byte, carry = set at the end of the file
;; Keeps: X, Y
;; Uses: FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Channel", "EOF", and those of <READ_NEXT_INPUT_BLOCK>
;; See: <READ_NEXT_INPUT_BLOCK>
BGETV_DEFAULT:
    txa
    pha
    tya
    pha
    lda #CFS_INPUT_OPEN
    jsr CHECK_HANDLE
    lda CFS_STATUS
    asl a
    bcs EOF_ERROR                   ; CFS_EOF_WARNED
    asl a
    bcc BGETV_NEXT                  ; not CFS_AT_EOF
    lda #CFS_EOF_WARNED
    jsr SET_STATUS_BITS
    lda #$FE
    bcs BGETV_RESULT                ; always taken
BGETV_NEXT:
    ldx CFS_INPUT_OFFSET
    inx
    cpx CFS_BLOCK_SIZE
    bne BGETV_FROM_BUFFER
    bit CFS_BLOCK_FLAG              ; the block's last byte
    bmi BGETV_LAST_BYTE
    lda CFS_LAST_CHARACTER
    pha
    jsr SET_SEQUENTIAL_OPTIONS
    php
    jsr READ_NEXT_INPUT_BLOCK
    plp
    pla
    sta FS_SCRATCH+12
    clc
    bit CFS_BLOCK_FLAG
    bpl BGETV_DONE
    lda CFS_BLOCK_SIZE
    ora CFS_BLOCK_SIZE+1
    bne BGETV_DONE
    jsr SET_EOF                     ; an empty last block
    bne BGETV_DONE                  ; always taken
BGETV_LAST_BYTE:
    jsr SET_EOF
BGETV_FROM_BUFFER:
    dex
    clc
    lda INPUT_BUFFER,x
BGETV_RESULT:
    sta FS_SCRATCH+12
BGETV_DONE:
    inc CFS_INPUT_OFFSET
    jmp CFS_RETURN

;; Gives the "EOF" error, for an OSBGET after the end of the file was returned.
EOF_ERROR:
    brk
    .byte ERROR_EOF, "EOF", 0

;; The cassette filing system's OSBPUT: writes a byte to the output file.
;;
;; Bytes collect in <OUTPUT_BUFFER>; when it holds 256 they are written as a block and the cassette is released.
;; In: A = the byte, Y = the handle
;; Keeps: A, X, Y
;; Uses: FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Channel", and those of <WRITE_OUTPUT_BLOCK>
;; See: <WRITE_OUTPUT_BLOCK>
BPUTV_DEFAULT:
    sta CFS_BPUT_BYTE
    txa
    pha
    tya
    pha
    lda #CFS_OUTPUT_OPEN
    jsr CHECK_HANDLE
    ldx CFS_OUTPUT_OFFSET
    lda CFS_BPUT_BYTE
    sta OUTPUT_BUFFER,x
    inx
    bne BPUTV_STORED
    jsr WRITE_OUTPUT_BLOCK
    jsr RELEASE_CASSETTE
BPUTV_STORED:
    inc CFS_OUTPUT_OFFSET
    lda CFS_BPUT_BYTE
    jmp CFS_RETURN_A

;; OSFSC 0: *OPT, which sets the messages (*OPT 1), the error action (*OPT 2) and the gap between sequential blocks
;; (*OPT 3), or restores the defaults (*OPT 0).
;;
;; *OPT 1 and 2 set both nibbles of <CFS_OPTIONS>, for LOAD and SAVE and for sequential files, from
;; <OPTION_BITS>. *OPT 3 with 0 or a negative number restores the default gap.
;; In: X = the first parameter, Y = the second
;; Uses: A, X, Y
;; Errors: "Bad command", for X above 3 or, with X = 1 or 2, Y above 2
;; See: <OPTION_BITS>
SET_OPTIONS:
    txa
    beq SET_OPTIONS_RESET
    cpx #$03
    beq SET_OPTIONS_GAP
    cpy #$03
    bcs SET_OPTIONS_BAD
    dex
    beq SET_OPTIONS_MESSAGES
    dex
    beq SET_OPTIONS_ERRORS
SET_OPTIONS_BAD:
    jmp USERV_DEFAULT               ; "Bad command"
SET_OPTIONS_MESSAGES:
    lda #OPT_ERROR_BITS
    iny                             ; the message settings are entries 4-6
    iny
    iny
    bne SET_OPTIONS_MERGE           ; always taken
SET_OPTIONS_ERRORS:
    lda #OPT_MESSAGE_BITS
SET_OPTIONS_MERGE:
    iny
    and CFS_OPTIONS
SET_OPTIONS_STORE:
    ora OPTION_BITS,y
    sta CFS_OPTIONS
    rts
SET_OPTIONS_GAP:
    tya
    bmi SET_OPTIONS_DEFAULT_GAP
    bne SET_OPTIONS_STORE_GAP
SET_OPTIONS_DEFAULT_GAP:
    lda #DEFAULT_GAP
SET_OPTIONS_STORE_GAP:
    sta CFS_BLOCK_GAP
    rts
SET_OPTIONS_RESET:
    tay
    beq SET_OPTIONS_STORE           ; always taken

;; The bits *OPT sets in <CFS_OPTIONS>, for both nibbles: the defaults, then the error actions for *OPT 2,0-2,
;; then the messages for *OPT 1,0-1,2.
;;
;; In each nibble bit 0 aborts on an error and bit 1 asks for a retry; bit 3 turns messages on and bit 2 makes them
;; extended.
;; See: <SET_OPTIONS>
OPTION_BITS:
    .byte %10100001                 ; *OPT 0: LOAD and SAVE retry, with messages; sequential files abort, quietly
    .byte %00000000                 ; *OPT 2,0: ignore errors
    .byte %00100010                 ; *OPT 2,1: retry
    .byte %00010001                 ; *OPT 2,2: abort
    .byte %00000000                 ; *OPT 1,0: no messages
    .byte %10001000                 ; *OPT 1,1: messages
    .byte %11001100                 ; *OPT 1,2: extended messages

;; Handles the 6850's interrupt while the cassette filing system has it, writing or reading a byte.
;;
;; Writing, each transmit interrupt sends <CFS_BYTE>. Reading, it takes the received byte and the DCD status bit,
;; which the serial ULA sets while it hears high tone, and steps through <CFS_RECEIVE_STATE>:
;;
;; - 0: idle.
;; - 1: waiting for high tone.
;; - 2: waiting for the tone to end and the synchronisation byte, "*"; any other byte starts again at state 1.
;; - 3: the header: each byte is left in CFS_BYTE for <READ_BYTE>. High tone ends it, with <CFS_BYTE_DONE> &80.
;; - 4: the data: each byte is added to the CRC and stored at <CFS_DATA_ADDRESS> or sent across the Tube, unless
;;   CFS_BYTE is negative, until the block's length is reached. High tone abandons the block.
;; - 5: the data's CRC, two bytes, after which it resets the 6850 and goes back to state 0.
;;
;; Every call decrements CFS_BYTE_DONE, so that it goes negative for the foreground when a byte has gone or come.
;; The ROM filing system calls it too, from <WAIT_BLOCK_END>, and then the byte comes from the ROM. The interrupt
;; handler jumps here, and the RTS returns to the end of its interrupt.
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Entry: CASSETTE_INTERRUPT_STATE = steps the reading with Y = the byte and carry = the DCD bit
;; See: <WRITE_BYTE>, <WAIT_FOR_BYTE>, <START_RECEIVING>
CASSETTE_INTERRUPT:
    dec CFS_BYTE_DONE
    lda CFS_RFS_SWITCH
    beq CASSETTE_INTERRUPT_ACIA
    jsr RFS_GET_BYTE                       ; read the next ROM byte
    tay
    clc
    bcc CASSETTE_INTERRUPT_STATE    ; always taken
CASSETTE_INTERRUPT_ACIA:
    lda ACIA_STATUS
    pha
    and #CFS_ACIA_TX_EMPTY
    beq CASSETTE_INTERRUPT_RECEIVE
    ldy CFS_TRANSMITTING
    beq CASSETTE_INTERRUPT_RECEIVE
    pla
    lda CFS_BYTE
    sta ACIA_DATA
    rts
CASSETTE_INTERRUPT_RECEIVE:
    ldy ACIA_DATA
    pla
    lsr a
    lsr a
    lsr a                           ; carry = DCD, high tone
CASSETTE_INTERRUPT_STATE:
    ldx CFS_RECEIVE_STATE
    beq CASSETTE_INTERRUPT_DONE
    dex
    bne CASSETTE_INTERRUPT_STATE_2
    bcc CASSETTE_INTERRUPT_DONE     ; state 1: no tone yet
    ldy #$02
    bne CASSETTE_INTERRUPT_SET_STATE ; always taken
CASSETTE_INTERRUPT_STATE_2:
    dex
    bne CASSETTE_INTERRUPT_STATE_3
    bcs CASSETTE_INTERRUPT_DONE     ; still tone
    tya
    jsr CLEAR_CRC_AND_FLAG
    ldy #$03
    cmp #SYNC_BYTE
    beq CASSETTE_INTERRUPT_SET_STATE
    jsr START_RECEIVING             ; not the sync byte: listen for tone again
    ldy #$01
    bne CASSETTE_INTERRUPT_SET_STATE ; always taken
CASSETTE_INTERRUPT_STATE_3:
    dex
    bne CASSETTE_INTERRUPT_STATE_4
    bcs CASSETTE_INTERRUPT_HEADER_END
    sty CFS_BYTE
    beq CASSETTE_INTERRUPT_DONE     ; always taken: X is 0
CASSETTE_INTERRUPT_HEADER_END:
    lda #$80                        ; done, with bit 6 clear
    sta CFS_BYTE_DONE
    bne CASSETTE_INTERRUPT_DONE     ; always taken
CASSETTE_INTERRUPT_STATE_4:
    dex
    bne CASSETTE_INTERRUPT_STATE_5
    bcs CASSETTE_INTERRUPT_STOP
    tya
    jsr ADD_TO_CRC
    ldy FS_SCRATCH+12               ; the byte's offset in the block
    inc FS_SCRATCH+12
    bit CFS_BYTE
    bmi CASSETTE_INTERRUPT_COUNT    ; discarding
    jsr CHECK_TUBE_ADDRESS
    beq CASSETTE_INTERRUPT_STORE
    stx TUBE_R3_DATA
    bne CASSETTE_INTERRUPT_COUNT    ; always taken
CASSETTE_INTERRUPT_STORE:
    txa
    sta (CFS_DATA_ADDRESS),y
CASSETTE_INTERRUPT_COUNT:
    iny
    cpy CFS_BLOCK_LENGTH
    bne CASSETTE_INTERRUPT_DONE
    lda #$01                        ; two CRC bytes to come
    sta FS_SCRATCH+12
    ldy #$05
    bne CASSETTE_INTERRUPT_SET_STATE ; always taken
CASSETTE_INTERRUPT_STATE_5:
    tya
    jsr ADD_TO_CRC
    dec FS_SCRATCH+12
    bpl CASSETTE_INTERRUPT_DONE
CASSETTE_INTERRUPT_STOP:
    jsr RESET_ACIA
    ldy #$00
CASSETTE_INTERRUPT_SET_STATE:
    sty CFS_RECEIVE_STATE
CASSETTE_INTERRUPT_DONE:
    rts

;; OSFSC 1: checks whether a file is at its end.
;;
;; The handle must be open. The end of file bit is the input file's, whichever handle is asked about.
;; In: X = the handle
;; Out: X = &40 at the end of the file, otherwise 0
;; Keeps: A, Y
;; Uses: FS_SCRATCH+12
;; Errors: "Channel"
;; See: <CHECK_HANDLE>
CHECK_EOF:
    pha
    tya
    pha
    txa
    tay
    lda #CFS_INPUT_OPEN | CFS_OUTPUT_OPEN
    jsr CHECK_HANDLE
    lda CFS_STATUS
    and #CFS_AT_EOF
    tax
    pla
    tay
    pla
    rts

;; Finds block 0 of the file named in <CFS_SEARCH_NAME>, showing "Searching".
;;
;; <FIND_BLOCK> finds the block in <CFS_WANTED_BLOCK>. Looking for block 0, an empty name takes the name of the
;; first file found, so the later blocks must belong to it. On tape the search goes on until ESCAPE; the ROM filing
;; system gives "File not found" when its ROMs run out. It returns with the block's header read and its data still
;; to come.
;; Out: Y = &FF, zero = clear
;; Uses: A, X, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "File not found", "Escape"
;; Entry: FIND_BLOCK = finds the block in CFS_WANTED_BLOCK
;; See: <SEARCH>
FIND_FILE:
    lda #$00
    sta CFS_WANTED_BLOCK
    sta CFS_WANTED_BLOCK+1
FIND_BLOCK:
    lda CFS_WANTED_BLOCK
    pha
    sta CFS_SEARCH_BLOCK
    lda CFS_WANTED_BLOCK+1
    pha
    sta CFS_SEARCH_BLOCK+1
    jsr PRINT_CFS_MESSAGE
    .byte "Searching", $0D, 0
    lda #$FF
    jsr SEARCH
    pla
    sta CFS_WANTED_BLOCK+1
    pla
    sta CFS_WANTED_BLOCK
    lda CFS_SEARCH_BLOCK
    ora CFS_SEARCH_BLOCK+1
    bne FIND_BLOCK_CHECK
    sta CFS_WANTED_BLOCK
    sta CFS_WANTED_BLOCK+1
    lda CFS_HEADER_BAD
    bne FIND_BLOCK_CHECK
    ldx #<(CFS_BLOCK_NAME - 1)      ; take the name found
    jsr COPY_SEARCH_NAME
FIND_BLOCK_CHECK:
    lda CFS_RFS_SWITCH
    beq FIND_BLOCK_DONE
    bvs FIND_BLOCK_DONE
;; Gives the "File not found" error.
FILE_NOT_FOUND_ERROR:
    brk
    .byte ERROR_FILE_NOT_FOUND, "File not found", 0
FIND_BLOCK_DONE:
    ldy #$FF                        ; the next block shown starts a new line
    sty CFS_LAST_FLAGS
    rts

;; Closes the *EXEC file: falls into <STAR_EXEC> with no name.
CLOSE_EXEC:
    lda #$00
