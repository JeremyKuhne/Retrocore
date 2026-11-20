; ---------------------------------------------------------------------------------------------------------------------
; The DFS's utilities ($B804-$BFFF): the OSFILE calls that read and change a file's catalogue entry, the checks on
; locked and open files, claiming the NMI and setting up the NMI code in page &0D, the OSBYTE calls the DFS makes,
; the filing system vector and dispatch tables, *HELP and the "Syntax:" error with the syntax text, *COMPACT,
; *BACKUP and *COPY with the sector copier they share, and the utility commands *TYPE, *LIST, *DUMP and *BUILD.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

DFS_CARRIAGE_RETURN = $0D           ;; the carriage return that ends a line of text
DFS_LINE_FEED = $0A                 ;; a line feed, which *TYPE and *LIST leave out

; The OSBYTE calls the DFS makes through the routines here (in A).
DFS_OSBYTE_SELECT_OUTPUT = $03      ;; OSBYTE 3: selects the output streams from X
DFS_OSBYTE_FLUSH_BUFFERS = $0F      ;; OSBYTE &0F: flushes the buffers; X = 1 flushes the input buffer only
DFS_OSBYTE_ACKNOWLEDGE_ESCAPE = $7E ;; OSBYTE &7E: clears an ESCAPE condition
DFS_OSBYTE_READ_OSHWM = $83         ;; OSBYTE &83: reads OSHWM, the bottom of user memory, into X and Y
DFS_OSBYTE_READ_HIMEM = $84         ;; OSBYTE &84: reads HIMEM, the top of user memory, into X and Y
DFS_OSBYTE_SERVICE_CALL = $8F       ;; OSBYTE &8F: issues paged ROM service call X with Y as its parameter
DFS_OSBYTE_STARTUP_OPTIONS = $FF    ;; OSBYTE &FF: reads or writes the start-up options, the keyboard links

; The paged ROM service calls the DFS issues (in X for OSBYTE &8F).
DFS_ISSUE_STATIC_WORKSPACE = $0A    ;; service call &0A: a ROM is claiming the static workspace from its owner
DFS_ISSUE_NMI_RELEASE = $0B         ;; service call &0B: the NMI is released; Y = the owner it goes back to
DFS_ISSUE_NMI_CLAIM = $0C           ;; service call &0C: claims the NMI; returns Y = the owner it was taken from

; OSFIND's reasons (in A).
DFS_FIND_CLOSE = $00                ;; OSFIND 0: closes the file whose handle is in Y
DFS_FIND_INPUT = $40                ;; OSFIND &40: opens a file for input
DFS_FIND_OUTPUT = $80               ;; OSFIND &80: opens a file for output

; Error numbers.
DFS_ERROR_LOCKED = $C3              ;; error &C3, "Locked"
DFS_ERROR_SYNTAX = $DC              ;; error &DC, "Syntax: " and the command's syntax

; The bits of a file's attributes in an OSFILE control block that lock it in the catalogue.
DFS_ATTRIBUTES_LOCKED = %00001010   ;; bit 1, not writable, and bit 3, not deletable

; The flags of an OSGBPB call in <GBPB_FLAGS>.
DFS_GBPB_CURRENT_POINTER = %001     ;; the call uses the file's sequential pointer, not the one in the control block
DFS_GBPB_FILE_DATA = %010           ;; the call transfers bytes of an open file
DFS_GBPB_TO_MEMORY = %100           ;; data goes to the caller's memory; this bit, shifted down, is the Tube reason

; The variants of the NMI code that <SET_UP_NMI_CODE> copies to page &0D, by number (in A).
DFS_NMI_VARIANT_WRITE = 0           ;; <DFS_NMI_TRANSFER_CODE> with <DFS_NMI_WRITE_PATCH>: writes from memory or Tube
DFS_NMI_VARIANT_READ = 1            ;; <DFS_NMI_TRANSFER_CODE>: reads into memory or to the Tube
DFS_NMI_VARIANT_NONE = 2            ;; <DFS_NMI_NONE_CODE>: an RTI alone, for commands that transfer no data
DFS_NMI_VARIANT_WRITE_TUBE = 3      ;; <DFS_NMI_WRITE_TUBE_CODE>: writes bytes from the Tube
DFS_NMI_VARIANT_WRITE_MEMORY = 4    ;; <DFS_NMI_WRITE_MEMORY_CODE>: writes bytes from memory
DFS_NMI_VARIANT_READ_TUBE = 5       ;; <DFS_NMI_READ_TUBE_CODE>: reads bytes to the Tube
DFS_NMI_VARIANT_READ_MEMORY = 6     ;; <DFS_NMI_READ_MEMORY_CODE>: reads bytes into memory

; The lengths of the variants, which DfsCatalogue.asm lays out one after another.
DFS_NMI_TRANSFER_LENGTH = DFS_NMI_READ_MEMORY_CODE - DFS_NMI_TRANSFER_CODE ;; the transfer handler, variants 0 and 1
DFS_NMI_READ_MEMORY_LENGTH = DFS_NMI_WRITE_MEMORY_CODE - DFS_NMI_READ_MEMORY_CODE ;; reading into memory
DFS_NMI_WRITE_MEMORY_LENGTH = DFS_NMI_READ_TUBE_CODE - DFS_NMI_WRITE_MEMORY_CODE ;; writing from memory
DFS_NMI_READ_TUBE_LENGTH = DFS_NMI_WRITE_TUBE_CODE - DFS_NMI_READ_TUBE_CODE ;; reading to the Tube
DFS_NMI_WRITE_TUBE_LENGTH = APPEND_FAULT_DETAILS - DFS_NMI_WRITE_TUBE_CODE ;; writing from the Tube, the last of them
DFS_NMI_WRITE_PATCH_LENGTH = DFS_NMI_TRANSFER_CODE - DFS_NMI_WRITE_PATCH ;; the write patch, before the handler


; The DFS's variables in page &10 that only the routines here use.
DFS_COPY_BUFFER_PAGE = DFS_WORKSPACE + $CF ;; the page the copy buffer starts at, OSHWM
DFS_COPY_BUFFER_PAGES = DFS_WORKSPACE + $D0 ;; the copy buffer's size in pages, from OSHWM to HIMEM
DFS_SOURCE_DRIVE = DFS_WORKSPACE + $D1 ;; the drive *COPY and *BACKUP copy from, and the drive *COMPACT compacts
DFS_DESTINATION_DRIVE = DFS_WORKSPACE + $D2 ;; the drive *COPY and *BACKUP copy to
DFS_VARIABLES_VALID = DFS_WORKSPACE + $D3 ;; &FF, but 0 while the DFS holds the NMI; saved in the private workspace

;; The copy of the state of a file *COPY is copying, which <SWAP_COPY_STATE> exchanges with &BA-&CB.
;;
;; <COPY_COMMAND> fills it with the file's catalogue entry: its name and directory at offset 11, and the second
;; sector's eight bytes (load and execution addresses, length, the byte of top bits and the start sector) at offset 2.
;; Swapped in, these lie where <CREATE_DESTINATION_FILE> wants them: the name at &C5 and the rest at &BC.
DFS_COPY_SAVED_STATE = DFS_WORKSPACE + $45

; The zero page workspace as the routines here use it.
NMI_PREVIOUS_OWNER = NMI_WORKSPACE  ;; the ROM that held the NMI before the DFS claimed it, or &FF
NMI_CODE_POINTER = FS_SCRATCH + 8   ;; the variant of the NMI code <SET_UP_NMI_CODE> is copying
;; A command's offset in the command tables at <DFS_COMMAND_TABLE>, less one, as <SCAN_COMMAND_TABLE> sets it.
HELP_COMMAND_OFFSET = FS_SCRATCH + 12
HELP_ERROR_INDEX = FS_SCRATCH + 9   ;; where <PUT_HELP_CHARACTER> puts the next character in the error, or 0 to print
COPY_SECTORS_LEFT = FS_WORKSPACE + 4 ;; the number of sectors still to copy, two bytes
COPY_SOURCE_SECTOR = FS_WORKSPACE + 6 ;; the sector to copy from next, two bytes, the high byte 0-3
COPY_DESTINATION_SECTOR = FS_WORKSPACE + 8 ;; the sector to copy to next, two bytes, the high byte 0-3
COMPACT_ENTRY = FS_WORKSPACE + 10   ;; the offset of the catalogue entry *COMPACT is moving
COPY_CREATE_FILE = OS_COMMAND_WORKSPACE ;; bit 7 set when <COPY_SECTORS> must create the destination file first
COPY_ONE_DRIVE = OS_COMMAND_WORKSPACE + 1 ;; bit 7 set when the source and destination are the same drive
COPY_DISC_IN_DRIVE = OS_COMMAND_WORKSPACE + 2 ;; with one drive, the disc asked for last: 0 source, &80 destination
COPY_SEARCH_POSITION = OS_COMMAND_WORKSPACE + 3 ;; *COPY's place in the catalogue search, kept across a copy
UTILITY_COUNTER = OS_COMMAND_WORKSPACE ;; two bytes: the line number in BCD, or the offset *DUMP has reached
LIST_LINE_MASK = OS_COMMAND_WORKSPACE + 3 ;; &FF for *LIST, which numbers lines, or 0 for *TYPE, which does not
BUILD_HANDLE = OS_COMMAND_WORKSPACE + 3 ;; the handle of the file *BUILD is writing
BUILD_LINE_LENGTH = OS_COMMAND_WORKSPACE + 2 ;; the length of the line *BUILD has read
UTILITY_BUFFER = OS_COMMAND_WORKSPACE + 4 ;; a pointer to the utilities' buffer, the private workspace's second page
DUMP_INDEX = UTILITY_BUFFER         ;; *DUMP's index into its eight bytes, 7 down to 0, as the buffer pointer's low byte
BUILD_INPUT_MAXIMUM = OS_COMMAND_WORKSPACE + 6 ;; the OSWORD 0 control block's maximum line length
BUILD_INPUT_LOWEST = OS_COMMAND_WORKSPACE + 7 ;; the OSWORD 0 control block's lowest character accepted
BUILD_INPUT_HIGHEST = OS_COMMAND_WORKSPACE + 8 ;; the OSWORD 0 control block's highest character accepted

;; Lays out an entry of <DFS_FILING_SYSTEM_VECTORS>: the MOS's extended vector entry for a vector.
;; Parameters:
;;   vector = the vector, FILEV to FSCV
.macro DFS_VECTOR_ENTRY vector
    .word EXTENDED_VECTOR_ENTRIES + 3 * ((vector) - USERV) / 2
.endmacro

;; Lays out an entry of <DFS_EXTENDED_VECTOR_TABLE>: a routine's address, then a byte for the ROM number.
;; Parameters:
;;   routine = the DFS's routine for the vector
.macro DFS_EXTENDED_VECTOR routine
    .word routine
    .byte 0                         ; the ROM number, which the copy fills in from ROMSEL_COPY
.endmacro

;; Emits a byte of an address: the low byte for part 0, the high byte for part 1.
;; Parameters:
;;   part = 0 for the low byte, 1 for the high byte
;;   address = the address
.macro DFS_ADDRESS_BYTE part, address
.if part = 0
    .byte <(address)
.else
    .byte >(address)
.endif
.endmacro

;; Lays out one half of the OSFSC dispatch table, the routines' addresses less one, which the DFS's OSFSC pushes and
;; enters with an RTS.
;; Parameters:
;;   part = 0 for <FSC_ROUTINES_LOW>, 1 for <FSC_ROUTINES_HIGH>
.macro DFS_FSC_ROUTINES part
    DFS_ADDRESS_BYTE part, DFS_FSC_OPT - 1 ; OSFSC 0: *OPT
    DFS_ADDRESS_BYTE part, CHECK_EOF - 1 ; OSFSC 1: is a file at its end?
    DFS_ADDRESS_BYTE part, DFS_RUN - 1 ; OSFSC 2: */
    DFS_ADDRESS_BYTE part, DFS_UNRECOGNISED_COMMAND - 1 ; OSFSC 3: a command the DFS may know
    DFS_ADDRESS_BYTE part, DFS_RUN - 1 ; OSFSC 4: *RUN
    DFS_ADDRESS_BYTE part, DFS_CAT - 1 ; OSFSC 5: *CAT
    DFS_ADDRESS_BYTE part, DFS_FSC_NEW_FILING_SYSTEM - 1 ; OSFSC 6: another filing system is taking over
    DFS_ADDRESS_BYTE part, DFS_FSC_HANDLE_RANGE - 1 ; OSFSC 7: the range of file handles
    DFS_ADDRESS_BYTE part, COMMAND_STARTING - 1 ; OSFSC 8: OSCLI is about to interpret a command
.endmacro

;; Lays out one half of the OSFILE dispatch table, indexed by the call's A plus one: the routines' addresses less
;; one, which the DFS's OSFILE pushes and enters with an RTS.
;; Parameters:
;;   part = 0 for <OSFILE_ROUTINES_LOW>, 1 for <OSFILE_ROUTINES_HIGH>
.macro DFS_OSFILE_ROUTINES part
    DFS_ADDRESS_BYTE part, DFS_LOAD_FILE - 1 ; OSFILE &FF: loads a file
    DFS_ADDRESS_BYTE part, DFS_SAVE_FILE - 1 ; OSFILE 0: saves a file
    DFS_ADDRESS_BYTE part, DFS_OSFILE_WRITE_INFO - 1
    DFS_ADDRESS_BYTE part, DFS_OSFILE_WRITE_LOAD - 1
    DFS_ADDRESS_BYTE part, DFS_OSFILE_WRITE_EXEC - 1
    DFS_ADDRESS_BYTE part, DFS_OSFILE_WRITE_ATTRIBUTES - 1
    DFS_ADDRESS_BYTE part, DFS_OSFILE_READ_INFO - 1
    DFS_ADDRESS_BYTE part, DFS_OSFILE_DELETE - 1
.endmacro

;; Lays out one half of the OSGBPB dispatch table, indexed by the call's A: the routines' addresses, which the DFS's
;; OSGBPB jumps to through DFS_GBPB_ROUTINE.
;; Parameters:
;;   part = 0 for <GBPB_ROUTINES_LOW>, 1 for <GBPB_ROUTINES_HIGH>
.macro DFS_GBPB_ROUTINES part
    DFS_ADDRESS_BYTE part, DFS_DO_NOTHING    ; OSGBPB 0: does nothing (an RTS)
    DFS_ADDRESS_BYTE part, PUT_BYTES    ; OSGBPB 1: puts bytes at the pointer given
    DFS_ADDRESS_BYTE part, PUT_BYTES    ; OSGBPB 2: puts bytes at the file's pointer
    DFS_ADDRESS_BYTE part, GET_BYTES    ; OSGBPB 3: gets bytes from the pointer given
    DFS_ADDRESS_BYTE part, GET_BYTES    ; OSGBPB 4: gets bytes from the file's pointer
    DFS_ADDRESS_BYTE part, READ_TITLE_AND_OPTION    ; OSGBPB 5: reads the disc's title, boot option and drive
    DFS_ADDRESS_BYTE part, READ_CURRENT_DIRECTORY    ; OSGBPB 6: reads the current directory and drive
    DFS_ADDRESS_BYTE part, READ_LIBRARY    ; OSGBPB 7: reads the library directory and drive
    DFS_ADDRESS_BYTE part, READ_FILE_NAMES    ; OSGBPB 8: reads file names from the current directory
.endmacro

;; Lays out one of <SYNTAX_STRINGS>: the text with bit 7 set in its first character, which marks where it starts.
;; Parameters:
;;   text = the syntax, as *HELP and the "Syntax:" error show it
.macro DFS_SYNTAX text
    .byte .strat(text, 0) | $80
    .repeat .strlen(text) - 1, i
        .byte .strat(text, i + 1)
    .endrepeat
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; Wildcards and the OSFILE calls on a catalogue entry
; ---------------------------------------------------------------------------------------------------------------------

;; Allows wildcards in the file names that follow: "*" for any characters and "#" for any one.
;;
;; The DFS keeps the wildcard for any characters at &10CE and the one for any one character at &10CD, or &FF in
;; each when wildcards are not allowed. Finishes in SET_WILDCARD_CHARACTER, which stores A at &10CD and returns.
;; Out: A = "#"
;; See: <DISABLE_WILDCARDS>
ALLOW_WILDCARDS:
    lda #'*'
    sta DFS_WORKSPACE+$CE           ; the wildcard for any characters
    lda #'#'
    bne SET_WILDCARD_CHARACTER                       ; always taken

;; OSFILE 5: reads a file's catalogue information into the control block.
;; In: FS_SCRATCH = the control block, holding the file name's address
;; Out: A = 1 when the file was found, 0 when it was not
;; Uses: X, Y
DFS_OSFILE_READ_INFO:
    jsr OSFILE_FIND
    jsr GET_FILE_INFO                       ; the entry's addresses, length and attributes into the control block
    lda #$01                        ; a file
    rts

;; OSFILE 6: deletes a file, giving its catalogue information in the control block.
;;
;; Raises error &C3, "Locked", for a locked file, and error &C2, "Open", for an open one.
;; In: FS_SCRATCH = the control block, holding the file name's address
;; Out: A = 1 when the file was found and deleted, 0 when it was not found
;; Uses: X, Y
DFS_OSFILE_DELETE:
    jsr OSFILE_FIND_UNLOCKED
    jsr GET_FILE_INFO                       ; the entry's information into the control block
    jsr DELETE_ENTRY                       ; take the entry out of the catalogue
    bcc DFS_OSFILE_SAVE_CATALOGUE   ; always taken: DELETE_ENTRY returns carry clear

;; OSFILE 1: writes a file's load address, execution address and attributes from the control block.
;; In: FS_SCRATCH = the control block
;; Out: A = 1 when the file was found, 0 when it was not
;; Uses: X, Y
DFS_OSFILE_WRITE_INFO:
    jsr OSFILE_FIND
    jsr SET_ENTRY_LOAD_ADDRESS
    jsr SET_ENTRY_EXEC_ADDRESS
    bvc DFS_OSFILE_ATTRIBUTES_AND_SAVE ; always taken: overflow is clear

;; OSFILE 2: writes a file's load address from the control block.
;; In: FS_SCRATCH = the control block
;; Out: A = 1 when the file was found, 0 when it was not
;; Uses: X, Y
DFS_OSFILE_WRITE_LOAD:
    jsr OSFILE_FIND
    jsr SET_ENTRY_LOAD_ADDRESS
    bvc DFS_OSFILE_SAVE_CATALOGUE   ; always taken: overflow is clear

;; OSFILE 3: writes a file's execution address from the control block.
;; In: FS_SCRATCH = the control block
;; Out: A = 1 when the file was found, 0 when it was not
;; Uses: X, Y
DFS_OSFILE_WRITE_EXEC:
    jsr OSFILE_FIND
    jsr SET_ENTRY_EXEC_ADDRESS
    bvc DFS_OSFILE_SAVE_CATALOGUE   ; always taken: overflow is clear

;; OSFILE 4: writes a file's attributes from the control block, which lock or unlock it.
;;
;; Raises error &C2, "Open", when the file is open.
;; In: FS_SCRATCH = the control block
;; Out: A = 1 when the file was found, 0 when it was not
;; Uses: X, Y
DFS_OSFILE_WRITE_ATTRIBUTES:
    jsr OSFILE_FIND
    jsr CHECK_NOT_OPEN

;; Sets a file's lock from the control block's attributes, then writes the catalogue back to the disc.
;;
;; Falls through into <DFS_OSFILE_SAVE_CATALOGUE>.
;; In: FS_SCRATCH = the control block, X = the file's catalogue offset
;; Out: A = 1
;; Uses: X, Y
DFS_OSFILE_ATTRIBUTES_AND_SAVE:
    jsr SET_ENTRY_ATTRIBUTES

;; Writes the catalogue back to the disc and returns 1, a file, from an OSFILE call.
;; Out: A = 1
;; Uses: X, Y
DFS_OSFILE_SAVE_CATALOGUE:
    jsr TITLE_COMMAND_WRITE
    lda #$01
    rts

;; Sets a catalogue entry's load address from an OSFILE control block.
;;
;; Takes the address's low two bytes and, into bits 2-3 of the entry's byte of top bits, bits 0-1 of its third.
;; Finishes in <SET_ENTRY_EXEC_ADDRESS>'s merge.
;; In: FS_SCRATCH = the control block, X = the entry's catalogue offset
;; Out: overflow = clear
;; Keeps: A, X, Y
SET_ENTRY_LOAD_ADDRESS:
    jsr SAVE_REGISTERS
    ldy #$02                        ; the control block's load address
    lda (FS_SCRATCH),y
    sta CATALOGUE_INFO+8+0,x        ; the entry's load address, low byte
    iny
    lda (FS_SCRATCH),y
    sta CATALOGUE_INFO+8+1,x
    iny
    lda (FS_SCRATCH),y
    asl a
    asl a                           ; bits 0-1 of the third byte to bits 2-3
    eor CATALOGUE_INFO+8+6,x        ; the entry's byte of top bits
    and #%00001100
    bpl SET_ENTRY_EXEC_ADDRESS_MERGE ; always taken

;; Sets a catalogue entry's execution address from an OSFILE control block.
;;
;; Takes the address's low two bytes and, into bits 6-7 of the entry's byte of top bits, bits 0-1 of its third.
;; In: FS_SCRATCH = the control block, X = the entry's catalogue offset
;; Out: overflow = clear
;; Keeps: A, X, Y
;; Entry: SET_ENTRY_EXEC_ADDRESS_MERGE = with A = the top-bits byte's new bits exclusive-ORed with its old ones
SET_ENTRY_EXEC_ADDRESS:
    jsr SAVE_REGISTERS
    ldy #$06                        ; the control block's execution address
    lda (FS_SCRATCH),y
    sta CATALOGUE_INFO+8+2,x        ; the entry's execution address, low byte
    iny
    lda (FS_SCRATCH),y
    sta CATALOGUE_INFO+8+3,x
    iny
    lda (FS_SCRATCH),y
    ror a
    ror a
    ror a                           ; bits 0-1 of the third byte to bits 6-7
    eor CATALOGUE_INFO+8+6,x
    and #%11000000
SET_ENTRY_EXEC_ADDRESS_MERGE:
    eor CATALOGUE_INFO+8+6,x        ; the new bits, the others as they were
    sta CATALOGUE_INFO+8+6,x
    clv
    rts

;; Locks or unlocks a catalogue entry as an OSFILE control block's attributes say.
;;
;; The file is locked, bit 7 of its directory set, when the attributes make it not writable or not deletable.
;; In: FS_SCRATCH = the control block, X = the entry's catalogue offset
;; Uses: A, Y
SET_ENTRY_ATTRIBUTES:
    jsr SAVE_REGISTERS
    ldy #$0E                        ; the control block's attributes
    lda (FS_SCRATCH),y
    and #DFS_ATTRIBUTES_LOCKED
    beq SET_ENTRY_ATTRIBUTES_1
    lda #$80                        ; locked
SET_ENTRY_ATTRIBUTES_1:
    eor CATALOGUE_NAMES+8+7,x       ; the entry's directory
    and #$80
    eor CATALOGUE_NAMES+8+7,x       ; bit 7 from A, the directory as it was
    sta CATALOGUE_NAMES+8+7,x
    rts

;; Finds the file an OSFILE control block names and checks that it is not locked.
;;
;; When there is no such file, it returns from the OSFILE call itself with A = 0. Raises error &C3, "Locked", when the
;; file is locked.
;; In: FS_SCRATCH = the control block
;; Out: X, Y = the file's catalogue offset, carry = set
;; Uses: A
OSFILE_FIND_UNLOCKED:
    jsr OSFILE_SEARCH
    bcc OSFILE_NOT_FOUND

;; Checks that a file is not locked, raising error &C3, "Locked", when it is.
;; In: Y = the file's catalogue offset
;; Uses: A
;; Entry: DFS_LOCKED_ERROR = raises the error
CHECK_NOT_LOCKED:
    lda CATALOGUE_NAMES+8+7,y       ; the file's directory, bit 7 set when it is locked
    bpl OSFILE_NOT_FOUND_RETURN     ; not locked: return
DFS_LOCKED_ERROR:
    jsr DFS_ERROR
    .byte DFS_ERROR_LOCKED
    .byte "Locked",0

;; Checks that a file is neither locked nor open, raising error &C3, "Locked", or &C2, "Open".
;; In: Y = the file's catalogue offset
;; Uses: A
;; Entry: CHECK_NOT_OPEN = checks only that the file is not open
CHECK_NOT_LOCKED_OR_OPEN:
    jsr CHECK_NOT_LOCKED
CHECK_NOT_OPEN:
    jsr SAVE_REGISTERS
    jsr FIND_OPEN_CHANNEL                       ; look for the file among the open files
    bcc RESTORE_OSFILE_POINTER_DONE
    jmp FILE_OPEN_ERROR                       ; "Open"

;; Finds the file an OSFILE control block names, or returns from the OSFILE call with A = 0 when there is none.
;;
;; Returning from the call works by pulling the caller's return address, so the RTS returns to the OSFILE dispatch's
;; caller.
;; In: FS_SCRATCH = the control block
;; Out: X, Y = the file's catalogue offset, carry = set
;; Uses: A
;; Entry: OSFILE_NOT_FOUND = returns A = 0 from the OSFILE call
OSFILE_FIND:
    jsr OSFILE_SEARCH
    bcs RESTORE_OSFILE_POINTER_DONE
OSFILE_NOT_FOUND:
    pla
    pla                             ; drop the return address into the OSFILE routine
    lda #$00                        ; no file
OSFILE_NOT_FOUND_RETURN:
    rts

;; Looks in the catalogue for the file an OSFILE control block names.
;;
;; Reading the name and the catalogue uses FS_SCRATCH, so it then points FS_SCRATCH at the control block again.
;; In: FS_SCRATCH = the control block, FS_SCRATCH+10 = the address of the file name
;; Out: carry = set when found, X, Y = the file's catalogue offset
;; Uses: A
OSFILE_SEARCH:
    jsr READ_BLOCK_NAME                       ; read the file name
    jsr FIND_FIRST                       ; look for it in the catalogue
    bcc RESTORE_OSFILE_POINTER_DONE
    tya
    tax

;; Points FS_SCRATCH at the caller's OSFILE control block again.
;; Out: FS_SCRATCH = the control block's address, which the DFS's OSFILE keeps at &10DB
;; Uses: A
RESTORE_OSFILE_POINTER:
    lda DFS_WORKSPACE+$DB           ; the control block's address, as OSFILE was given it
    sta FS_SCRATCH
    lda DFS_WORKSPACE+$DB+1
    sta FS_SCRATCH+1
RESTORE_OSFILE_POINTER_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Workspace, the NMI and OSBYTE
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the memory *COMPACT, *COPY and *BACKUP use as their copy buffer: from OSHWM up to HIMEM.
;; Out: DFS_COPY_BUFFER_PAGE = OSHWM's page, DFS_COPY_BUFFER_PAGES = the number of pages up to HIMEM
;; Uses: A, X, Y
FIND_COPY_BUFFER:
    lda #DFS_OSBYTE_READ_OSHWM
    jsr OSBYTE
    sty DFS_COPY_BUFFER_PAGE
    lda #DFS_OSBYTE_READ_HIMEM
    jsr OSBYTE
    tya
    sec
    sbc DFS_COPY_BUFFER_PAGE
    sta DFS_COPY_BUFFER_PAGES
    rts

;; Claims the static workspace for the DFS.
;;
;; Issues service call &0A, so that the ROM that has the workspace saves what it keeps there, then sets bytes &D3 and
;; &D4 of the DFS's private workspace, and <DFS_VARIABLES_VALID>, to &FF. The private workspace keeps a copy of
;; &10C0-&10FF at the same offsets; the service call handler in DfsFiles.asm reads byte &D4 to tell whether the DFS
;; has the static workspace.
;; Out: FS_SCRATCH = the DFS's private workspace
;; Uses: A, X, Y
CLAIM_STATIC_WORKSPACE:
    ldx #DFS_ISSUE_STATIC_WORKSPACE
    jsr DFS_ISSUE_SERVICE_CALL
    jsr POINT_AT_PRIVATE_WORKSPACE
    ldy #<DFS_VARIABLES_VALID       ; its copy in the private workspace, at the same offset
    lda #$FF
    sta (FS_SCRATCH),y
    sta DFS_VARIABLES_VALID
    iny                             ; &D4: the DFS has the static workspace
    sta (FS_SCRATCH),y
    rts

;; Points FS_SCRATCH at the DFS's private workspace, whose page the MOS keeps in ROM_WORKSPACE_TABLE.
;;
;; Bits 6 and 7 of the table's byte are flags, not part of the page.
;; Out: FS_SCRATCH = the private workspace's address
;; Keeps: A, Y
POINT_AT_PRIVATE_WORKSPACE:
    pha
    ldx ROMSEL_COPY
    lda #$00
    sta FS_SCRATCH
    lda ROM_WORKSPACE_TABLE,x
    and #%00111111
    sta FS_SCRATCH+1
    pla
    rts

;; Claims the NMI for the DFS, if it does not have it, and copies a variant of the NMI code to page &0D.
;;
;; The claim issues service call &0C, which makes the NMI's owner give it up and returns the owner's number, kept in
;; <NMI_PREVIOUS_OWNER> to give the NMI back. The variants are laid out in DfsCatalogue.asm, and <NMI_CODE_LOW>,
;; <NMI_CODE_HIGH> and <NMI_CODE_LAST> say where each is. The transfer handler, <DFS_NMI_TRANSFER_CODE>, which
;; is variants 0 and 1, pages the DFS in when the 8271 finishes a command, so this ROM's number goes into it
;; (<DFS_NMI_ROM_NUMBER>); for variant 0, <DFS_NMI_WRITE_PATCH> is copied over &0D0A, which makes the handler write
;; to the 8271's data register instead of reading it.
;; In: A = the variant, <DFS_NMI_VARIANT_WRITE> to <DFS_NMI_VARIANT_READ_MEMORY>
;; Keeps: A, X, Y
;; See: <RELEASE_NMI>
SET_UP_NMI_CODE:
    jsr SAVE_REGISTERS
    pha
    bit DFS_WORKSPACE+$C8           ; bit 7 set while the DFS holds the NMI
    bmi SET_UP_NMI_CODE_COPY
    lda #DFS_OSBYTE_SERVICE_CALL
    ldx #DFS_ISSUE_NMI_CLAIM
    jsr OSBYTE_WITH_Y_FF
    sty NMI_PREVIOUS_OWNER
    lda #$FF
    sta DFS_WORKSPACE+$C8           ; the DFS holds the NMI
    inc DFS_VARIABLES_VALID         ; &FF to 0 while the DFS holds the NMI
SET_UP_NMI_CODE_COPY:
    pla
    tax
    lda NMI_CODE_LOW,x
    sta NMI_CODE_POINTER
    lda NMI_CODE_HIGH,x
    sta NMI_CODE_POINTER+1
    ldy NMI_CODE_LAST,x
SET_UP_NMI_CODE_LOOP:
    lda (NMI_CODE_POINTER),y
    sta NMI_ROUTINE,y
    dey
    bpl SET_UP_NMI_CODE_LOOP
    cpx #DFS_NMI_VARIANT_NONE
    bcs SET_UP_NMI_CODE_DONE        ; not the transfer handler
    lda ROMSEL_COPY
    sta DFS_NMI_ROM_NUMBER          ; the ROM the handler pages in
    cpx #DFS_NMI_VARIANT_WRITE
    bne SET_UP_NMI_CODE_DONE
    ldy #DFS_NMI_WRITE_PATCH_LENGTH - 1
SET_UP_NMI_CODE_PATCH:
    lda DFS_NMI_WRITE_PATCH,y
    sta DFS_NMI_WRITE_START,y
    dey
    bpl SET_UP_NMI_CODE_PATCH
SET_UP_NMI_CODE_DONE:
    rts

;; Waits for the 8271 to finish its command, then gives the NMI back.
;;
;; Falls through into <RELEASE_NMI>.
;; Keeps: A, X, Y
WAIT_AND_RELEASE_NMI:
    jsr FDC_WAIT_IDLE

;; Gives the NMI back to the ROM that had it before the DFS claimed it, if the DFS has it.
;;
;; Issues service call &0B with that ROM's number, unless no ROM had the NMI (&FF).
;; Keeps: A, X, Y
;; See: <SET_UP_NMI_CODE>
RELEASE_NMI:
    jsr SAVE_REGISTERS
    bit DFS_WORKSPACE+$C8           ; bit 7 set while the DFS holds the NMI
    bpl RELEASE_NMI_DONE
    dec DFS_VARIABLES_VALID         ; back to &FF
    ldy NMI_PREVIOUS_OWNER
    cpy #$FF
    beq RELEASE_NMI_DONE            ; nobody had it
    ldx #DFS_ISSUE_NMI_RELEASE
    jsr DFS_ISSUE_SERVICE_CALL
RELEASE_NMI_DONE:
    lda #$00
    sta DFS_WORKSPACE+$C8           ; the DFS no longer holds it
    rts

;; Flushes the input buffer, so that a key the DFS asks for is one pressed after the question.
;; Keeps: A, X, Y
DFS_FLUSH_INPUT:
    jsr SAVE_REGISTERS
    lda #DFS_OSBYTE_FLUSH_BUFFERS
    ldx #$01                        ; the input buffer only
    ldy #$00
    beq JUMP_OSBYTE                 ; always taken

;; Selects the output streams (OSBYTE 3) from A.
;; In: A = the streams, as OSBYTE 3 takes them in X
;; Out: X = the streams as they were
;; Uses: A, Y
;; Entry: DFS_SELECT_OUTPUT_X = takes the streams in X
DFS_SELECT_OUTPUT:
    tax
DFS_SELECT_OUTPUT_X:
    lda #DFS_OSBYTE_SELECT_OUTPUT
    bne JUMP_OSBYTE                 ; always taken

;; Clears an ESCAPE condition (OSBYTE &7E).
;; Keeps: A, X, Y
DFS_ACKNOWLEDGE_ESCAPE:
    jsr SAVE_REGISTERS
    lda #DFS_OSBYTE_ACKNOWLEDGE_ESCAPE
    bne JUMP_OSBYTE                 ; always taken

;; Issues a paged ROM service call (OSBYTE &8F).
;; In: X = the service call, Y = its parameter
;; Out: Y = what the ROM that claimed it returned
;; Uses: A, X
DFS_ISSUE_SERVICE_CALL:
    lda #DFS_OSBYTE_SERVICE_CALL
    bne JUMP_OSBYTE                 ; always taken

;; Reads the start-up options (OSBYTE &FF), which the keyboard links set.
;;
;; Falls through into <READ_OS_VARIABLE>.
;; Out: X = the options
;; Uses: A, Y
READ_STARTUP_OPTIONS:
    lda #DFS_OSBYTE_STARTUP_OPTIONS

;; Reads an OS variable: makes OSBYTE call A with X = 0 and Y = &FF.
;;
;; Falls through into <OSBYTE_WITH_Y_FF>.
;; In: A = the OSBYTE call, &A6-&FF
;; Out: X = the variable, Y = the next variable
;; Uses: A
READ_OS_VARIABLE:
    ldx #$00

;; Makes OSBYTE call A with Y = &FF.
;;
;; Falls through into <JUMP_OSBYTE>.
;; In: A = the OSBYTE call, X = its parameter
;; Out: X, Y = its results
;; Uses: A
OSBYTE_WITH_Y_FF:
    ldy #$FF

;; Makes OSBYTE call A with the X and Y given.
;; In: A = the OSBYTE call, X and Y = its parameters
;; Out: X, Y = its results
;; Uses: A
JUMP_OSBYTE:
    jmp OSBYTE

; ---------------------------------------------------------------------------------------------------------------------
; The filing system's vectors and dispatch tables
; ---------------------------------------------------------------------------------------------------------------------

;; The values the DFS puts in the filing system vectors, FILEV to FSCV, when it starts: each points at the MOS's
;; extended vector entry for the vector.
;;
;; The start-up code in DfsFiles.asm copies the fourteen bytes to FILEV, and fills in the extended vectors from
;; <DFS_EXTENDED_VECTOR_TABLE>.
DFS_FILING_SYSTEM_VECTORS:
    DFS_VECTOR_ENTRY FILEV
    DFS_VECTOR_ENTRY ARGSV
    DFS_VECTOR_ENTRY BGETV
    DFS_VECTOR_ENTRY BPUTV
    DFS_VECTOR_ENTRY GBPBV
    DFS_VECTOR_ENTRY FINDV
    DFS_VECTOR_ENTRY FSCV

;; The DFS's routines for the filing system vectors, FILEV to FSCV, three bytes each as in the extended vectors: the
;; routine's address and a byte for the ROM number.
;;
;; The start-up code in DfsFiles.asm copies each address to the extended vectors, and puts the DFS's ROM number from
;; ROMSEL_COPY in the third byte, ignoring the byte here. It indexes this table and the extended vectors with the same
;; register, starting at FILEV's offset, &1B, so it reads the table from <DFS_ISSUE_SERVICE_CALL> plus &1B.
DFS_EXTENDED_VECTOR_TABLE:
    DFS_EXTENDED_VECTOR DFS_OSFILE  ; FILEV
    DFS_EXTENDED_VECTOR DFS_OSARGS  ; ARGSV
    DFS_EXTENDED_VECTOR DFS_OSBGET       ; BGETV: the DFS's OSBGET
    DFS_EXTENDED_VECTOR DFS_OSBPUT       ; BPUTV: the DFS's OSBPUT
    DFS_EXTENDED_VECTOR DFS_OSGBPB  ; GBPBV
    DFS_EXTENDED_VECTOR DFS_OSFIND  ; FINDV
    DFS_EXTENDED_VECTOR DFS_OSFSC   ; FSCV
    .assert DFS_EXTENDED_VECTOR_TABLE - DFS_ISSUE_SERVICE_CALL = 3 * (FILEV - USERV) / 2, "DfsFiles reads it there."

;; The low bytes of the OSFSC routines' addresses less one, indexed by the call's A, 0-8.
;; See: <FSC_ROUTINES_HIGH>, <DFS_FSC_ROUTINES>
FSC_ROUTINES_LOW:
    DFS_FSC_ROUTINES 0

;; The high bytes of the OSFSC routines' addresses less one.
;; See: <FSC_ROUTINES_LOW>, <DFS_FSC_ROUTINES>
FSC_ROUTINES_HIGH:
    DFS_FSC_ROUTINES 1

;; The low bytes of the OSFILE routines' addresses less one, indexed by the call's A plus one, 0-7.
;; See: <OSFILE_ROUTINES_HIGH>, <DFS_OSFILE_ROUTINES>
OSFILE_ROUTINES_LOW:
    DFS_OSFILE_ROUTINES 0

;; The high bytes of the OSFILE routines' addresses less one.
;; See: <OSFILE_ROUTINES_LOW>, <DFS_OSFILE_ROUTINES>
OSFILE_ROUTINES_HIGH:
    DFS_OSFILE_ROUTINES 1

;; The low bytes of where each variant of the NMI code is in the ROM, indexed by the variant.
;; See: <SET_UP_NMI_CODE>, <NMI_CODE_HIGH>, <NMI_CODE_LAST>
NMI_CODE_LOW:
    .byte <DFS_NMI_TRANSFER_CODE    ; 0, DFS_NMI_VARIANT_WRITE
    .byte <DFS_NMI_TRANSFER_CODE    ; 1, DFS_NMI_VARIANT_READ
    .byte <DFS_NMI_NONE_CODE        ; 2, DFS_NMI_VARIANT_NONE
    .byte <DFS_NMI_WRITE_TUBE_CODE  ; 3, DFS_NMI_VARIANT_WRITE_TUBE
    .byte <DFS_NMI_WRITE_MEMORY_CODE ; 4, DFS_NMI_VARIANT_WRITE_MEMORY
    .byte <DFS_NMI_READ_TUBE_CODE   ; 5, DFS_NMI_VARIANT_READ_TUBE
    .byte <DFS_NMI_READ_MEMORY_CODE ; 6, DFS_NMI_VARIANT_READ_MEMORY

;; The high bytes of where each variant of the NMI code is in the ROM, indexed by the variant.
;; See: <NMI_CODE_LOW>
NMI_CODE_HIGH:
    .byte >DFS_NMI_TRANSFER_CODE
    .byte >DFS_NMI_TRANSFER_CODE
    .byte >DFS_NMI_NONE_CODE
    .byte >DFS_NMI_WRITE_TUBE_CODE
    .byte >DFS_NMI_WRITE_MEMORY_CODE
    .byte >DFS_NMI_READ_TUBE_CODE
    .byte >DFS_NMI_READ_MEMORY_CODE

;; The offset of the last byte of each variant of the NMI code, its length less one, indexed by the variant.
;;
;; <SET_UP_NMI_CODE> copies from this offset down to 0.
;; See: <NMI_CODE_LOW>
NMI_CODE_LAST:
    .byte DFS_NMI_TRANSFER_LENGTH - 1
    .byte DFS_NMI_TRANSFER_LENGTH - 1
    .byte 0                         ; the RTI alone
    .byte DFS_NMI_WRITE_TUBE_LENGTH - 1
    .byte DFS_NMI_WRITE_MEMORY_LENGTH - 1
    .byte DFS_NMI_READ_TUBE_LENGTH - 1
    .byte DFS_NMI_READ_MEMORY_LENGTH - 1

;; The low bytes of the OSGBPB routines' addresses, indexed by the call's A, 0-8.
;; See: <GBPB_ROUTINES_HIGH>, <DFS_GBPB_ROUTINES>, <GBPB_FLAGS>
GBPB_ROUTINES_LOW:
    DFS_GBPB_ROUTINES 0

;; The high bytes of the OSGBPB routines' addresses.
;; See: <GBPB_ROUTINES_LOW>, <DFS_GBPB_ROUTINES>
GBPB_ROUTINES_HIGH:
    DFS_GBPB_ROUTINES 1

;; How each OSGBPB call is carried out, indexed by the call's A, 0-8: <DFS_GBPB_CURRENT_POINTER>,
;; <DFS_GBPB_FILE_DATA> and <DFS_GBPB_TO_MEMORY>.
;;
;; The DFS's OSGBPB shifts the flags out of the bottom: the rest, bit 2 alone, is the reason it claims the Tube with
;; for a transfer, 1 to the second processor or 0 from it.
GBPB_FLAGS:
    .byte DFS_GBPB_TO_MEMORY        ; 0: nothing
    .byte DFS_GBPB_FILE_DATA        ; 1: put bytes
    .byte DFS_GBPB_FILE_DATA | DFS_GBPB_CURRENT_POINTER ; 2: put bytes
    .byte DFS_GBPB_TO_MEMORY | DFS_GBPB_FILE_DATA ; 3: get bytes
    .byte DFS_GBPB_TO_MEMORY | DFS_GBPB_FILE_DATA | DFS_GBPB_CURRENT_POINTER ; 4: get bytes
    .byte DFS_GBPB_TO_MEMORY        ; 5: the title
    .byte DFS_GBPB_TO_MEMORY        ; 6: the current directory
    .byte DFS_GBPB_TO_MEMORY        ; 7: the library
    .byte DFS_GBPB_TO_MEMORY        ; 8: file names

; ---------------------------------------------------------------------------------------------------------------------
; *HELP and syntax
; ---------------------------------------------------------------------------------------------------------------------

;; *HELP DFS: lists the DFS's commands with their syntax, then looks at the rest of the *HELP line.
;;
;; Falls through into <PRINT_HELP>.
;; In: Y = the offset in the *HELP line after the word
;; Uses: A, X, Y
HELP_DFS:
    tya
    ldx #$FF                        ; one before the first command, *ACCESS
    ldy #14                         ; *ACCESS to *WIPE

;; Prints the DFS's *HELP heading and a list of commands with their syntax, then looks at the rest of the *HELP line.
;;
;; Each command is on a line of its own, after two spaces. Then it goes on to <HELP_NEXT_TOPIC>.
;; In: A = the offset in the *HELP line to go on from, X = the offset of the first command in the command tables at
;;   DFS_COMMAND_TABLE, less one, Y = the number of commands
;; Uses: A, X, Y
PRINT_HELP:
    pha
    jsr DFS_PRINT_INLINE
    .byte DFS_CARRIAGE_RETURN,"DFS 1.20",DFS_CARRIAGE_RETURN
    stx HELP_COMMAND_OFFSET         ; also ends the text: its opcode has bit 7 set
PRINT_HELP_LOOP:
    lda #$00
    sta HELP_ERROR_INDEX            ; print
    jsr DFS_PRINT_TWO_SPACES
    jsr PRINT_COMMAND_SYNTAX
    jsr DFS_PRINT_NEWLINE
    dey
    bne PRINT_HELP_LOOP
    pla
    tay

;; Looks up the next word of the *HELP line among the DFS's help topics, DFS and UTILS, and goes to its routine.
;;
;; The lookup is SCAN_COMMAND_TABLE's, starting from the help topics at offset &A1 in the command tables. A word that is
;; not a topic goes to <HELP_OTHER_TOPIC>.
;; In: Y = the offset in the *HELP line
;; Uses: A, X, Y
HELP_NEXT_TOPIC:
    ldx #$9E ; SCAN_COMMAND_TABLE adds three: the help topics' first entry, at DFS_COMMAND_TABLE+&A1
    jmp SCAN_COMMAND_TABLE

;; *HELP UTILS: lists the utility commands, *BUILD to *TYPE, with their syntax, then looks at the rest of the line.
;; In: Y = the offset in the *HELP line after the word
;; Uses: A, X, Y
HELP_UTILS:
    tya
    ldx #$73                        ; one before *BUILD, which is at DFS_COMMAND_TABLE+&74
    ldy #5                          ; *BUILD to *TYPE
    bne PRINT_HELP                  ; always taken

;; Skips a word of the *HELP line that is not one of the DFS's topics, and looks at the next.
;;
;; At the end of the line it returns.
;; In: Y = the offset in the *HELP line
;; Uses: A, X, Y
HELP_OTHER_TOPIC:
    jsr START_STRING
    beq PUT_HELP_CHARACTER_DONE     ; the end of the line
HELP_OTHER_TOPIC_SKIP:
    jsr READ_NAME_CHARACTER
    bcc HELP_OTHER_TOPIC_SKIP
    bcs HELP_NEXT_TOPIC             ; always taken: the end of the word

;; Checks that a command has an argument, raising error &DC, "Syntax: ", with the command's syntax when it does not.
;;
;; The syntax error builds the error at STACK, as BUILD_ERROR does, adding the command's name and syntax from the
;; command tables, found with <HELP_COMMAND_OFFSET>.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Out: Y = the offset of the argument, zero = clear
;; Uses: A
;; Entry: DFS_SYNTAX_ERROR = raises the error
REQUIRE_ARGUMENT:
    jsr START_STRING
    bne PUT_HELP_CHARACTER_DONE
DFS_SYNTAX_ERROR:
    jsr BUILD_ERROR
    .byte DFS_ERROR_SYNTAX
    .byte "Syntax: "
    stx HELP_ERROR_INDEX            ; also ends the text; X = where the error's text goes on
    jsr PRINT_COMMAND_SYNTAX
    lda #$00                        ; the zero that ends the error
    jsr PUT_HELP_CHARACTER
    jmp STACK                       ; the BRK that raises it

;; Prints a command's name and syntax, from its entry in the command tables, or adds them to an error.
;;
;; The entry's syntax byte holds two syntax strings, the first in its low nibble and the second in its high nibble.
;; Falls through into <PRINT_SYNTAX_STRING> for the second.
;; In: HELP_COMMAND_OFFSET = the entry's offset in the tables at DFS_COMMAND_TABLE, less one, HELP_ERROR_INDEX = 0 to
;;   print, or
;;   where the text goes in the error at STACK
;; Out: HELP_COMMAND_OFFSET = the offset of the entry's last byte, one before the next entry
;; Uses: A, X
PRINT_COMMAND_SYNTAX:
    ldx HELP_COMMAND_OFFSET
PRINT_COMMAND_SYNTAX_NAME:
    inx
    lda DFS_COMMAND_TABLE,x
    bmi PRINT_COMMAND_SYNTAX_SYNTAX ; the address's high byte ends the name
    jsr PUT_HELP_CHARACTER
    jmp PRINT_COMMAND_SYNTAX_NAME
PRINT_COMMAND_SYNTAX_SYNTAX:
    inx
    inx                             ; past the address, to the syntax byte
    stx HELP_COMMAND_OFFSET
    lda DFS_COMMAND_TABLE,x
    jsr PRINT_SYNTAX_STRING
    jsr SHIFT_RIGHT_4                       ; the high nibble, then fall through to print it

;; Prints one of the syntax strings, after a space, or adds it to an error.
;;
;; Does nothing for string 0.
;; In: A = the string's number in its low nibble, 1-9, HELP_ERROR_INDEX = 0 to print, or where it goes in the error
;; Keeps: A, X, Y
;; See: <SYNTAX_STRINGS>
PRINT_SYNTAX_STRING:
    jsr SAVE_REGISTERS
    and #$0F
    beq PUT_HELP_CHARACTER_DONE
    tay
    lda #' '
    jsr PUT_HELP_CHARACTER
    ldx #$FF
PRINT_SYNTAX_STRING_FIND:
    inx
    lda SYNTAX_STRINGS,x
    bpl PRINT_SYNTAX_STRING_FIND
    dey
    bne PRINT_SYNTAX_STRING_FIND    ; until the Yth string's first character
    and #$7F
PRINT_SYNTAX_STRING_LOOP:
    jsr PUT_HELP_CHARACTER
    inx
    lda SYNTAX_STRINGS,x
    bpl PRINT_SYNTAX_STRING_LOOP    ; until the next string, or the end of the list
    rts

;; Prints a character of *HELP's text, or adds it to the error being built at STACK.
;; In: A = the character, HELP_ERROR_INDEX = 0 to print it, or where it goes in the error
;; Out: HELP_ERROR_INDEX = moved on, when not 0
;; Keeps: A, X, Y
;; Entry: PUT_HELP_CHARACTER_DONE = an RTS, which other routines branch to
PUT_HELP_CHARACTER:
    jsr SAVE_REGISTERS
    ldx HELP_ERROR_INDEX
    beq PUT_HELP_CHARACTER_PRINT
    inc HELP_ERROR_INDEX
    sta STACK,x
PUT_HELP_CHARACTER_DONE:
    rts
PUT_HELP_CHARACTER_PRINT:
    jmp PRINT_CHARACTER

;; The syntax strings that *HELP and the "Syntax:" error show after a command, numbered from 1.
;;
;; Each starts with a character with bit 7 set, and &FF ends the list. A command's syntax byte in the command tables
;; at DFS_COMMAND_TABLE numbers one or two of them.
;; See: <PRINT_SYNTAX_STRING>
SYNTAX_STRINGS:
    DFS_SYNTAX "<fsp>"              ; 1
    DFS_SYNTAX "<afsp>"             ; 2
    DFS_SYNTAX "(L)"                ; 3
    DFS_SYNTAX "<source> <dest.>"   ; 4
    DFS_SYNTAX "<old fsp> <new fsp>" ; 5
    DFS_SYNTAX "(<dir>)"            ; 6
    DFS_SYNTAX "(<drive>)"          ; 7
    DFS_SYNTAX "<title>"            ; 8
    DFS_SYNTAX "<drive>"            ; 9
    .byte $FF                       ; the end of the list

; ---------------------------------------------------------------------------------------------------------------------
; *COMPACT, *BACKUP and *COPY
; ---------------------------------------------------------------------------------------------------------------------

;; *COMPACT, with a drive or none for the current one: moves a disc's files together, leaving the free space in one
;; piece after them.
;;
;; Works through the catalogue from its last entry, the file nearest the start of the disc, to its first. A file
;; that does not start where the one before it ended is copied there through the copy buffer, from OSHWM to HIMEM,
;; and its entry changed and written back. Each file's information line is printed, before moving when *OPT 1 is on,
;; and after. Ends by printing the number of free sectors, in hexadecimal. The copy buffer overwrites what is in
;; user memory.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
COMPACT_COMMAND:
    jsr READ_DRIVE_ARGUMENT                       ; the drive, or the current one
    jsr DFS_PRINT_INLINE
    .byte "Compacting :"
    sta DFS_SOURCE_DRIVE            ; also ends the text; A = the drive
    sta DFS_DESTINATION_DRIVE
    jsr PRINT_HEX_DIGIT
    jsr DFS_PRINT_NEWLINE
    ldy #$00                        ; CLOSE_CHANNEL finds no file open on channel 0 and does nothing
    jsr CLOSE_CHANNEL
    jsr FIND_COPY_BUFFER
    jsr FETCH_CATALOGUE                       ; read the catalogue
    ldy CATALOGUE_SIZE
    sty COMPACT_ENTRY
    lda #$02                        ; the first sector after the catalogue
    sta COPY_DESTINATION_SECTOR
    lda #$00
    sta COPY_DESTINATION_SECTOR+1
COMPACT_LOOP:
    ldy COMPACT_ENTRY
    jsr PREVIOUS_ENTRY                       ; the entry before
    cpy #$F8
    bne COMPACT_FILE                ; not past the first entry
    lda CATALOGUE_SECTORS           ; the free sectors: the disc's size less the first free sector
    sec
    sbc COPY_DESTINATION_SECTOR
    pha
    lda CATALOGUE_OPTION
    and #%00000011
    sbc COPY_DESTINATION_SECTOR+1
    jsr PRINT_HEX_DIGIT
    pla
    jsr PRINT_HEX_BYTE
    jsr DFS_PRINT_INLINE
    .byte " free sectors",DFS_CARRIAGE_RETURN
    nop                             ; ends the text
    rts
COMPACT_FILE:
    sty COMPACT_ENTRY
    jsr PRINT_INFO_IF_ON                       ; its information line, when *OPT 1 is on
    ldy COMPACT_ENTRY
    lda CATALOGUE_INFO+8+4,y        ; the length's low byte
    cmp #$01                        ; carry set unless it is 0: a part sector counts as a whole one
    lda #$00
    sta FS_SCRATCH+12               ; the transfer address's low byte
    sta FS_WORKSPACE                ; the transfer length's low byte
    adc CATALOGUE_INFO+8+5,y        ; the length in sectors, rounded up
    sta COPY_SECTORS_LEFT
    lda CATALOGUE_INFO+8+6,y        ; the byte of top bits
    php
    jsr BITS_4_5                       ; the length's bits 16-17
    plp
    adc #$00
    sta COPY_SECTORS_LEFT+1
    lda CATALOGUE_INFO+8+7,y        ; the start sector
    sta COPY_SOURCE_SECTOR
    lda CATALOGUE_INFO+8+6,y
    and #%00000011
    sta COPY_SOURCE_SECTOR+1
    cmp COPY_DESTINATION_SECTOR+1
    bne COMPACT_MOVE
    lda COPY_SOURCE_SECTOR
    cmp COPY_DESTINATION_SECTOR
    bne COMPACT_MOVE
    clc                             ; already in place: the next file goes after it
    adc COPY_SECTORS_LEFT
    sta COPY_DESTINATION_SECTOR
    lda COPY_DESTINATION_SECTOR+1
    adc COPY_SECTORS_LEFT+1
    sta COPY_DESTINATION_SECTOR+1
    jmp COMPACT_NEXT
COMPACT_MOVE:
    lda COPY_DESTINATION_SECTOR     ; the file's new start sector
    sta CATALOGUE_INFO+8+7,y
    lda CATALOGUE_INFO+8+6,y
    and #%11111100
    ora COPY_DESTINATION_SECTOR+1
    sta CATALOGUE_INFO+8+6,y
    lda #$00
    sta COPY_CREATE_FILE            ; the entry is there already
    sta COPY_ONE_DRIVE              ; one disc: no prompts
    jsr COPY_SECTORS
    jsr WRITE_CATALOGUE                       ; write the catalogue
COMPACT_NEXT:
    ldy COMPACT_ENTRY
    jsr PRINT_INFO                       ; its information line
    jmp COMPACT_LOOP

;; Asks "Go (Y/N) ?" unless *ENABLE came just before, and abandons the command unless the answer is Y.
;;
;; The *ENABLE count lets the next command through; any later command has to ask. Abandoning returns from the
;; caller, by dropping its return address, after a new line.
;; Uses: A
CONFIRM_UNLESS_ENABLED:
    bit DFS_WORKSPACE+$C7           ; *ENABLE's count: 0 for the command after *ENABLE, else negative
    bpl READ_COPY_DRIVES_DONE
    jsr ASK_GO
    beq CONFIRM_UNLESS_ENABLED_NEWLINE
    pla
    pla                             ; return from the caller
CONFIRM_UNLESS_ENABLED_NEWLINE:
    jmp DFS_PRINT_NEWLINE

;; Reads the source and destination drives of *COPY or *BACKUP and announces the copy.
;;
;; Raises error &DC, "Syntax:", when either drive is missing. When the two drives are the same, the copy is made with
;; one drive, asking for the source and destination discs in turn. Also finds the copy buffer.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Out: DFS_SOURCE_DRIVE, DFS_DESTINATION_DRIVE = the drives, COPY_ONE_DRIVE = bit 7 set when they are the same,
;;   Y = the offset after the destination drive, carry = clear
;; Uses: A, X
;; Entry: READ_COPY_DRIVES_DONE = an RTS, which other routines branch to
READ_COPY_DRIVES:
    jsr REQUIRE_ARGUMENT
    jsr READ_DRIVE_NUMBER                       ; the drive
    sta DFS_SOURCE_DRIVE
    jsr REQUIRE_ARGUMENT
    jsr READ_DRIVE_NUMBER
    sta DFS_DESTINATION_DRIVE
    tya
    pha
    lda #$00
    sta COPY_ONE_DRIVE
    lda DFS_DESTINATION_DRIVE
    cmp DFS_SOURCE_DRIVE
    bne READ_COPY_DRIVES_ANNOUNCE
    lda #$FF
    sta COPY_ONE_DRIVE
    sta COPY_DISC_IN_DRIVE          ; no disc asked for yet
READ_COPY_DRIVES_ANNOUNCE:
    jsr FIND_COPY_BUFFER
    jsr DFS_PRINT_INLINE
    .byte "Copying from :"
    lda DFS_SOURCE_DRIVE            ; also ends the text
    jsr PRINT_HEX_DIGIT
    jsr DFS_PRINT_INLINE
    .byte " to :"
    lda DFS_DESTINATION_DRIVE       ; also ends the text
    jsr PRINT_HEX_DIGIT
    jsr DFS_PRINT_NEWLINE
    pla
    tay
    clc
READ_COPY_DRIVES_DONE:
    rts

;; With one drive, asks for the source disc to be put in, unless it was the disc asked for last.
;;
;; Raises error &11, "Escape", when ESCAPE is pressed instead of a key.
;; Keeps: A, X, Y
;; See: <PROMPT_FOR_DESTINATION>
PROMPT_FOR_SOURCE:
    jsr SAVE_REGISTERS
    bit COPY_ONE_DRIVE
    bpl PROMPT_FOR_DESTINATION_DONE
    lda #$00                        ; the source disc
    beq PROMPT_FOR_DISC             ; always taken

;; With one drive, asks for the destination disc to be put in, unless it was the disc asked for last.
;;
;; Prints "Insert destination disk and hit a key", waits for a key, then falls through into <DFS_PRINT_NEWLINE>.
;; Raises error &11, "Escape", when ESCAPE is pressed instead.
;; Keeps: A, X, Y
;; Entry: PROMPT_FOR_DISC = asks for the disc in A, 0 for the source or &80 for the destination
PROMPT_FOR_DESTINATION:
    jsr SAVE_REGISTERS
    bit COPY_ONE_DRIVE
    bmi PROMPT_FOR_DESTINATION_1
PROMPT_FOR_DESTINATION_DONE:
    rts
PROMPT_FOR_DESTINATION_1:
    lda #$80                        ; the destination disc
PROMPT_FOR_DISC:
    cmp COPY_DISC_IN_DRIVE
    beq PROMPT_FOR_DESTINATION_DONE ; it is in already
    sta COPY_DISC_IN_DRIVE
    jsr DFS_PRINT_INLINE
    .byte "Insert "
    nop                             ; ends the text
    bit COPY_DISC_IN_DRIVE
    bmi PROMPT_FOR_DISC_DESTINATION
    jsr DFS_PRINT_INLINE
    .byte "source"
    bcc PROMPT_FOR_DISC_WAIT        ; also ends the text; always taken, as DFS_PRINT_INLINE returns carry clear
PROMPT_FOR_DISC_DESTINATION:
    jsr DFS_PRINT_INLINE
    .byte "destination"
    nop                             ; ends the text
PROMPT_FOR_DISC_WAIT:
    jsr DFS_PRINT_INLINE
    .byte " disk and hit a key"
    nop                             ; ends the text
    jsr DFS_FLUSH_INPUT
    jsr OSRDCH
    bcs READ_KEY_ESCAPE

;; Starts a new line, with a carriage return through PRINT_CHARACTER.
;; Keeps: A, X, Y
DFS_PRINT_NEWLINE:
    pha
    lda #DFS_CARRIAGE_RETURN
    jsr PRINT_CHARACTER
    pla
    rts

;; Asks "Go (Y/N) ? " and reads the answer.
;;
;; Falls through into <ASK_YES_NO>.
;; Out: zero = set when the answer is Y
;; Uses: A
ASK_GO:
    jsr DFS_PRINT_INLINE
    .byte "Go (Y/N) ? "
    nop                             ; ends the text

;; Reads a key and echoes the answer: Y for a Y, in either case, and N for any other key.
;;
;; Raises error &11, "Escape", when ESCAPE is pressed.
;; Out: zero = set when the answer is Y
;; Uses: A
ASK_YES_NO:
    jsr DFS_FLUSH_INPUT
    jsr OSRDCH
    bcs READ_KEY_ESCAPE
    and #%01011111                  ; capitals
    cmp #'Y'
    php
    beq ASK_YES_NO_ECHO
    lda #'N'
ASK_YES_NO_ECHO:
    jsr PRINT_CHARACTER
    plp
    rts

;; Raises error &11, "Escape", for ESCAPE pressed when the DFS was waiting for a key.
READ_KEY_ESCAPE:
    jmp ESCAPE_ERROR

;; Raises error &C6, "Disk full", when *BACKUP's destination disc is smaller than its source.
BACKUP_DISK_FULL:
    jmp DISK_FULL

;; *BACKUP, with a source and a destination drive: copies the whole of one disc to another.
;;
;; Asks "Go (Y/N) ?" first, unless *ENABLE came just before. Copies every sector the source disc has, through the
;; copy buffer, from OSHWM to HIMEM, overwriting what is in user memory; with one drive it asks for the discs in
;; turn. Raises error &C6, "Disk full", when the destination disc has fewer sectors than the source.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
BACKUP_COMMAND:
    jsr READ_COPY_DRIVES
    jsr CONFIRM_UNLESS_ENABLED
    lda #$00
    sta COPY_SOURCE_SECTOR+1
    sta COPY_DESTINATION_SECTOR+1
    sta COPY_DESTINATION_SECTOR
    sta COPY_SOURCE_SECTOR          ; from sector 0 to sector 0
    sta COPY_CREATE_FILE
    jsr PROMPT_FOR_SOURCE
    lda DFS_SOURCE_DRIVE
    sta FS_WORKSPACE+13             ; the drive
    jsr READ_CATALOGUE                       ; read its catalogue
    lda CATALOGUE_SECTORS           ; copy as many sectors as the source disc has
    sta COPY_SECTORS_LEFT
    lda CATALOGUE_OPTION
    and #%00000011
    sta COPY_SECTORS_LEFT+1
    jsr PROMPT_FOR_DESTINATION
    lda DFS_DESTINATION_DRIVE
    sta FS_WORKSPACE+13
    jsr READ_CATALOGUE
    lda CATALOGUE_OPTION            ; is the destination disc at least as big?
    and #%00000011
    cmp COPY_SECTORS_LEFT+1
    bcc BACKUP_DISK_FULL
    bne BACKUP_COPY
    lda CATALOGUE_SECTORS
    cmp COPY_SECTORS_LEFT
    bcc BACKUP_DISK_FULL
BACKUP_COPY:
    jsr COPY_SECTORS
    jmp READ_CATALOGUE                       ; read the new catalogue

;; *COPY, with a source drive, a destination drive and a name: copies the files that match the name, with wildcards.
;;
;; For each match, prints its information line, then copies it through the copy buffer, from OSHWM to HIMEM,
;; overwriting what is in user memory; with one drive it asks for the discs in turn. The copy is given the same name
;; and addresses, replacing a file of that name on the destination. Raises error &D6, "Not found", when nothing matches,
;; and the errors of <CREATE_DESTINATION_FILE>.
;;
;; Each match's catalogue entry is copied twice: to zero page, the name at &C5 and the second sector's eight bytes at
;; &BB-&C2, where the length is worked out from them, and to <DFS_COPY_SAVED_STATE> for making the new entry.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
COPY_COMMAND:
    jsr ALLOW_WILDCARDS
    jsr READ_COPY_DRIVES
    jsr REQUIRE_ARGUMENT
    jsr READ_NAME                       ; the name to match
    jsr PROMPT_FOR_SOURCE
    lda DFS_SOURCE_DRIVE
    jsr SET_DRIVE                       ; the drive
    jsr FIND_OR_ERROR                       ; the first match, or "Not found"
COPY_LOOP:
    lda FS_WORKSPACE+12             ; the directory to match
    pha
    lda FS_SCRATCH+6                ; the place in the catalogue search
    sta COPY_SEARCH_POSITION
    jsr PRINT_INFO                       ; the file's information line
    ldx #$00
COPY_ENTRY_LOOP:
    lda CATALOGUE_NAMES+8,y         ; the name and directory
    sta FS_WORKSPACE+5,x
    sta DFS_COPY_SAVED_STATE+11,x
    lda CATALOGUE_INFO+8,y          ; the addresses, length and start sector
    sta FS_SCRATCH+11,x             ; &BB-&C2
    sta DFS_COPY_SAVED_STATE+2,x
    inx
    iny
    cpx #$08
    bne COPY_ENTRY_LOOP
    lda FS_WORKSPACE+1              ; the byte of top bits, at &C1
    jsr BITS_4_5                       ; the length's bits 16-17
    sta FS_WORKSPACE+3              ; the length's high byte, for now
    lda FS_SCRATCH+15               ; the length's low byte, at &BF
    clc
    adc #$FF                        ; carry set unless it is 0: a part sector counts as a whole one
    lda FS_WORKSPACE                ; the length's middle byte, at &C0
    adc #$00
    sta COPY_SECTORS_LEFT
    lda FS_WORKSPACE+3
    adc #$00
    sta COPY_SECTORS_LEFT+1
    lda DFS_COPY_SAVED_STATE+9      ; the start sector
    sta COPY_SOURCE_SECTOR
    lda DFS_COPY_SAVED_STATE+8      ; the byte of top bits
    and #%00000011
    sta COPY_SOURCE_SECTOR+1
    lda #$FF
    sta COPY_CREATE_FILE
    jsr COPY_SECTORS
    jsr PROMPT_FOR_SOURCE
    lda DFS_SOURCE_DRIVE
    jsr SET_DRIVE
    jsr FETCH_CATALOGUE                       ; read the source catalogue again
    lda COPY_SEARCH_POSITION
    sta FS_SCRATCH+6
    pla
    sta FS_WORKSPACE+12
    jsr FIND_NEXT                       ; the next match
    bcs COPY_LOOP
    rts

;; Makes the catalogue entry for the file *COPY is copying on the destination disc, and gives the sector to copy to.
;;
;; Takes the file's catalogue information from <DFS_COPY_SAVED_STATE>, deletes any file of the same name on the
;; destination, and makes the new entry with MAKE_CATALOGUE_ENTRY, which writes the catalogue. Raises the errors of
;; deleting the old file, &C3, "Locked", and &C2, "Open", and MAKE_CATALOGUE_ENTRY's, "Disk full" and "Cat full".
;; Out: COPY_DESTINATION_SECTOR = the new file's start sector
;; Uses: A, X, Y
CREATE_DESTINATION_FILE:
    jsr SWAP_COPY_STATE
    jsr PROMPT_FOR_DESTINATION
    lda DFS_DESTINATION_DRIVE
    sta FS_WORKSPACE+13             ; the drive
    lda FS_WORKSPACE+12             ; the directory
    pha
    jsr FETCH_CATALOGUE                       ; read the destination catalogue
    jsr FIND_NAMED_FILE                       ; a file of the same name?
    bcc CREATE_DESTINATION_FILE_ADD
    jsr DELETE_ENTRY                       ; delete it
CREATE_DESTINATION_FILE_ADD:
    pla
    sta FS_WORKSPACE+12
    jsr UNPACK_LOAD_HIGH                       ; the load and execution addresses' high bytes
    jsr UNPACK_EXEC_HIGH
    lda FS_WORKSPACE+2              ; the byte of top bits
    jsr BITS_4_5
    sta FS_WORKSPACE+4              ; the length's high byte
    jsr MAKE_CATALOGUE_ENTRY                       ; make the entry
    lda FS_WORKSPACE+2              ; the start sector it chose
    and #%00000011
    pha
    lda FS_WORKSPACE+3
    pha
    jsr SWAP_COPY_STATE
    pla
    sta COPY_DESTINATION_SECTOR
    pla
    sta COPY_DESTINATION_SECTOR+1
    rts

;; Swaps the zero page from &BA to &CB with <DFS_COPY_SAVED_STATE>, eighteen bytes.
;;
;; *COPY keeps the copy's state in zero page while it moves sectors, and the file's catalogue information in the
;; saved state; <CREATE_DESTINATION_FILE> swaps them to make the new entry, then swaps them back.
;; Uses: A, X, Y
SWAP_COPY_STATE:
    ldx #$11
SWAP_COPY_STATE_LOOP:
    lda DFS_COPY_SAVED_STATE,x
    ldy FS_SCRATCH+10,x
    sta FS_SCRATCH+10,x
    tya
    sta DFS_COPY_SAVED_STATE,x
    dex
    bpl SWAP_COPY_STATE_LOOP
    rts

;; Copies sectors from the source drive to the destination drive, as many at a time as the copy buffer holds.
;;
;; With one drive, asks for each disc in turn. When <COPY_CREATE_FILE> has bit 7 set, makes the destination file
;; after the first read, with <CREATE_DESTINATION_FILE>, which sets where to copy to.
;; In: COPY_SECTORS_LEFT = the number of sectors, COPY_SOURCE_SECTOR = the first to read,
;;   COPY_DESTINATION_SECTOR = the first to write, DFS_SOURCE_DRIVE, DFS_DESTINATION_DRIVE = the drives
;; Out: COPY_SECTORS_LEFT = 0, COPY_SOURCE_SECTOR, COPY_DESTINATION_SECTOR = after the sectors copied,
;;   COPY_CREATE_FILE = 0 when it was set
;; Uses: A, X, Y
COPY_SECTORS:
    lda #$00
    sta FS_SCRATCH+12               ; the transfer address's low byte
    sta FS_WORKSPACE                ; the transfer length's low byte
    beq COPY_SECTORS_TEST           ; always taken
COPY_SECTORS_LOOP:
    lda COPY_SECTORS_LEFT           ; this time, the smaller of what is left and the buffer
    tay
    cmp DFS_COPY_BUFFER_PAGES
    lda COPY_SECTORS_LEFT+1
    sbc #$00
    bcc COPY_SECTORS_READ
    ldy DFS_COPY_BUFFER_PAGES
COPY_SECTORS_READ:
    sty FS_WORKSPACE+1              ; the transfer length in sectors
    lda COPY_SOURCE_SECTOR
    sta FS_WORKSPACE+3              ; the start sector
    lda COPY_SOURCE_SECTOR+1
    sta FS_WORKSPACE+2
    lda DFS_COPY_BUFFER_PAGE
    sta FS_SCRATCH+13               ; the transfer address's high byte
    lda DFS_SOURCE_DRIVE
    sta FS_WORKSPACE+13             ; the drive
    jsr PROMPT_FOR_SOURCE
    jsr SET_HOST_ADDRESS                       ; the transfer is in this machine's memory
    jsr SELECT_DRIVE
    jsr READ_FILE_DATA                       ; read
    lda DFS_DESTINATION_DRIVE
    sta FS_WORKSPACE+13
    bit COPY_CREATE_FILE
    bpl COPY_SECTORS_WRITE
    jsr CREATE_DESTINATION_FILE
    lda #$00
    sta COPY_CREATE_FILE
COPY_SECTORS_WRITE:
    lda COPY_DESTINATION_SECTOR
    sta FS_WORKSPACE+3
    lda COPY_DESTINATION_SECTOR+1
    sta FS_WORKSPACE+2
    lda DFS_COPY_BUFFER_PAGE
    sta FS_SCRATCH+13
    jsr PROMPT_FOR_DESTINATION
    jsr SET_HOST_ADDRESS
    jsr SELECT_DRIVE
    jsr WRITE_FILE_DATA                       ; write
    lda FS_WORKSPACE+1
    clc
    adc COPY_DESTINATION_SECTOR
    sta COPY_DESTINATION_SECTOR
    bcc COPY_SECTORS_1
    inc COPY_DESTINATION_SECTOR+1
COPY_SECTORS_1:
    lda FS_WORKSPACE+1
    clc
    adc COPY_SOURCE_SECTOR
    sta COPY_SOURCE_SECTOR
    bcc COPY_SECTORS_2
    inc COPY_SOURCE_SECTOR+1
COPY_SECTORS_2:
    sec
    lda COPY_SECTORS_LEFT
    sbc FS_WORKSPACE+1
    sta COPY_SECTORS_LEFT
    bcs COPY_SECTORS_TEST
    dec COPY_SECTORS_LEFT+1
COPY_SECTORS_TEST:
    lda COPY_SECTORS_LEFT
    ora COPY_SECTORS_LEFT+1
    bne COPY_SECTORS_LOOP
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The utility commands: *TYPE, *LIST, *DUMP and *BUILD
; ---------------------------------------------------------------------------------------------------------------------

;; Points <UTILITY_BUFFER>'s high byte at the second page of the DFS's private workspace, a buffer for *DUMP and
;; *BUILD.
;; Uses: A, X
POINT_AT_UTILITY_BUFFER:
    ldx ROMSEL_COPY
    lda ROM_WORKSPACE_TABLE,x
    and #%00111111
    sta UTILITY_BUFFER+1
    inc UTILITY_BUFFER+1
    rts

;; *TYPE, with a file name: prints a file as text.
;;
;; The MOS offers the command to the paged ROMs as service call 4, and the DFS takes it whichever filing system is
;; current; the file is opened with OSFIND, so it may be on any filing system. Line feeds are left out.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
TYPE_COMMAND:
    jsr READ_UTILITY_FILE_NAME
    lda #$00                        ; no line numbers
    beq LIST_FILE                   ; always taken

;; *LIST, with a file name: prints a file as text, with a line number before each line.
;;
;; As <TYPE_COMMAND>, but each line starts with its number, four decimal digits, and a space. Falls through into
;; <LIST_FILE>.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
LIST_COMMAND:
    jsr READ_UTILITY_FILE_NAME
    lda #$FF                        ; line numbers

;; Prints a file as text for *TYPE and *LIST, then closes it.
;;
;; Line feeds are left out. Raises error &D6, "Not found", when the file cannot be opened, and error &11, "Escape",
;; when ESCAPE is pressed, after closing the file. At the end of the file, falls through into <CLOSE_UTILITY_FILE>.
;; In: A = <LIST_LINE_MASK>, X/Y = the file name
;; Uses: A, X, Y
;; Entry: FILE_NOT_FOUND = raises "Not found"
LIST_FILE:
    sta LIST_LINE_MASK
    lda #DFS_FIND_INPUT
    jsr OSFIND
    tay
    lda #DFS_CARRIAGE_RETURN        ; as if after a line, so the first line is numbered
    cpy #$00
    bne LIST_FILE_CHECK
FILE_NOT_FOUND:
    jmp NOT_FOUND
LIST_FILE_LOOP:
    jsr OSBGET
    bcs LIST_FILE_END
    cmp #DFS_LINE_FEED
    beq LIST_FILE_LOOP
    plp
    bne LIST_FILE_PRINT             ; not the start of a line
    pha
    jsr PRINT_LINE_NUMBER
    jsr DFS_PRINT_SPACE
    pla
LIST_FILE_PRINT:
    jsr OSASCI
    bit ESCAPE_FLAG
    bmi DUMP_LINE                   ; to the escape check there
LIST_FILE_CHECK:
    and LIST_LINE_MASK
    cmp #DFS_CARRIAGE_RETURN        ; zero set after a carriage return, but never for *TYPE
    php
    jmp LIST_FILE_LOOP
LIST_FILE_END:
    plp
    jsr OSNEWL

;; Closes the file a utility command has open.
;; In: Y = the file's handle
;; Uses: A
CLOSE_UTILITY_FILE:
    lda #DFS_FIND_CLOSE
    jmp OSFIND

;; *DUMP, with a file name: prints a file in hexadecimal and as characters, eight bytes to a line.
;;
;; Each line has the offset in the file in hexadecimal, the bytes, then the bytes as characters, with a full stop for
;; any that cannot be printed. The last line is padded with "**". As <TYPE_COMMAND>, the file may be on any filing
;; system. Raises error &D6, "Not found", when the file cannot be opened, and error &11, "Escape", when ESCAPE is
;; pressed, after closing the file.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
DUMP_COMMAND:
    jsr READ_UTILITY_FILE_NAME
    lda #DFS_FIND_INPUT
    jsr OSFIND
    tay
    beq FILE_NOT_FOUND
    jsr POINT_AT_UTILITY_BUFFER
DUMP_LINE:
    bit ESCAPE_FLAG
    bmi UTILITY_ESCAPE
    lda UTILITY_COUNTER+1           ; the offset
    jsr DFS_PRINT_HEX_BYTE
    lda UTILITY_COUNTER
    jsr DFS_PRINT_HEX_BYTE
    jsr DFS_PRINT_SPACE
    lda #$07
    sta DUMP_INDEX
    ldx #$00
DUMP_BYTE:
    jsr OSBGET
    bcs DUMP_END_OF_BYTES
    sta (DUMP_INDEX,x)              ; keep it for the characters
    jsr DFS_PRINT_HEX_BYTE
    jsr DFS_PRINT_SPACE
    dec DUMP_INDEX
    bpl DUMP_BYTE
    clc
DUMP_END_OF_BYTES:
    php                             ; carry set at the end of the file
    bcc DUMP_CHARACTERS
DUMP_PAD:
    lda #'*'
    jsr OSASCI
    jsr OSASCI
    jsr DFS_PRINT_SPACE
    lda #$00
    sta (DUMP_INDEX,x)
    dec DUMP_INDEX
    bpl DUMP_PAD
DUMP_CHARACTERS:
    lda #$07
    sta DUMP_INDEX
DUMP_CHARACTER:
    lda (DUMP_INDEX,x)
    cmp #$7F
    bcs DUMP_UNPRINTABLE
    cmp #' '
    bcs DUMP_PRINT_CHARACTER
DUMP_UNPRINTABLE:
    lda #'.'
DUMP_PRINT_CHARACTER:
    jsr OSASCI
    dec DUMP_INDEX
    bpl DUMP_CHARACTER
    jsr OSNEWL
    lda #$08
    clc
    adc UTILITY_COUNTER
    sta UTILITY_COUNTER
    bcc DUMP_NEXT_LINE
    inc UTILITY_COUNTER+1
DUMP_NEXT_LINE:
    plp
    bcs CLOSE_UTILITY_FILE          ; the end of the file
    bcc DUMP_LINE                   ; always taken

;; Abandons a utility command when ESCAPE is pressed: clears the ESCAPE condition, closes the file and raises error
;; &11, "Escape".
;; In: Y = the file's handle
UTILITY_ESCAPE:
    jsr DFS_ACKNOWLEDGE_ESCAPE
    jsr CLOSE_UTILITY_FILE
    jmp ESCAPE_ERROR

;; *BUILD, with a file name: writes the lines typed at the keyboard to a file, until ESCAPE is pressed.
;;
;; Each line is prompted with its number, four decimal digits, and read with OSWORD 0 into the second page of the
;; DFS's private workspace, then written with a carriage return. As <TYPE_COMMAND>, the file may be on any filing
;; system. ESCAPE closes the file and raises error &11, "Escape".
;; In: TEXT_POINTER, Y = the command line, after the command
;; Uses: A, X, Y
BUILD_COMMAND:
    jsr READ_UTILITY_FILE_NAME
    lda #DFS_FIND_OUTPUT
    jsr OSFIND
    sta BUILD_HANDLE
BUILD_LINE:
    jsr PRINT_LINE_NUMBER
    jsr DFS_PRINT_SPACE
    jsr POINT_AT_UTILITY_BUFFER
    ldx #<UTILITY_BUFFER            ; the OSWORD 0 control block, at &00AC
    ldy #$FF
    sty BUILD_INPUT_MAXIMUM
    sty BUILD_INPUT_HIGHEST
    iny
    sty UTILITY_BUFFER              ; the buffer starts the page
    lda #' '
    sta BUILD_INPUT_LOWEST
    tya                             ; OSWORD 0, with Y = 0 for the block's high byte
    jsr OSWORD
    php                             ; carry set for ESCAPE
    sty BUILD_LINE_LENGTH
    ldy BUILD_HANDLE
    ldx #$00
    beq BUILD_WRITE_TEST            ; always taken
BUILD_WRITE:
    lda (UTILITY_BUFFER,x)
    jsr OSBPUT
    inc UTILITY_BUFFER
BUILD_WRITE_TEST:
    lda UTILITY_BUFFER
    cmp BUILD_LINE_LENGTH
    bne BUILD_WRITE
    plp
    bcs UTILITY_ESCAPE
    lda #DFS_CARRIAGE_RETURN
    jsr OSBPUT
    jmp BUILD_LINE

;; Prints two spaces.
;;
;; Falls through into <DFS_PRINT_SPACE>.
;; Out: carry = clear
;; Keeps: A, X, Y
DFS_PRINT_TWO_SPACES:
    jsr DFS_PRINT_SPACE

;; Prints a space.
;; Out: carry = clear
;; Keeps: A, X, Y
DFS_PRINT_SPACE:
    pha
    lda #' '
    jsr OSASCI
    pla
    clc
    rts

;; Reads the file name argument of *TYPE, *LIST, *DUMP or *BUILD, and claims the service call they came as.
;;
;; The commands come as service call 4, from a handler that keeps its registers with SAVE_REGISTERS: the service call's
;; A is seven bytes up the stack from here, and setting it to 0 claims the call. Raises error &DC, "Syntax:", when there
;; is no name. Zeroes <UTILITY_COUNTER>.
;; In: TEXT_POINTER, Y = the command line, after the command
;; Out: X/Y = the file name, A = 0, UTILITY_COUNTER = 0
READ_UTILITY_FILE_NAME:
    tsx
    lda #$00
    sta STACK+7,x                   ; the service call's A: claimed
    dey
READ_UTILITY_FILE_NAME_SKIP:
    iny
    lda (TEXT_POINTER),y
    cmp #' '
    beq READ_UTILITY_FILE_NAME_SKIP
    cmp #DFS_CARRIAGE_RETURN
    bne READ_UTILITY_FILE_NAME_FOUND
    jmp DFS_SYNTAX_ERROR
READ_UTILITY_FILE_NAME_FOUND:
    lda #$00
    sta UTILITY_COUNTER
    sta UTILITY_COUNTER+1
    pha
    tya
    clc
    adc TEXT_POINTER
    tax
    lda TEXT_POINTER+1
    adc #$00
    tay
    pla
    rts

;; Two bytes, "T ", that nothing refers to.
DFS_UTILITIES_UNUSED:
    .byte "T "

;; Adds one to the line number, in BCD, and prints it as four digits.
;;
;; Falls through into <DFS_PRINT_HEX_BYTE> for the low two digits.
;; Out: carry = set
;; Uses: A
PRINT_LINE_NUMBER:
    sed
    clc
    lda UTILITY_COUNTER
    adc #$01
    sta UTILITY_COUNTER
    lda UTILITY_COUNTER+1
    adc #$00
    sta UTILITY_COUNTER+1
    cld
    jsr DFS_PRINT_HEX_BYTE
    lda UTILITY_COUNTER

;; Prints a byte as two hexadecimal digits.
;;
;; The NFS uses it too.
;; In: A = the byte
;; Out: carry = set
;; Uses: A
DFS_PRINT_HEX_BYTE:
    pha
    jsr SHIFT_RIGHT_4                       ; the high nibble
    jsr DFS_PRINT_HEX_DIGIT
    pla

;; Prints the low nibble of A as a hexadecimal digit.
;; In: A = the digit, in the low nibble
;; Out: carry = set
;; Uses: A
DFS_PRINT_HEX_DIGIT:
    jsr HEX_DIGIT
    jsr OSASCI
    sec
    rts
