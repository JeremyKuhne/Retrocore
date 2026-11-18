;; The DFS's errors and messages, its * command tables and commands ($9F9D-$A7FE).
;;
;; - The conventions every part of the DFS uses: the error routines, <DISK_ERROR>, <BAD_ERROR>, <DFS_ERROR>,
;;   <BUILD_ERROR> and <ERROR_APPEND>, which take an error number and message from the bytes after their JSR and build
;;   a BRK at &0100; <DFS_PRINT_INLINE>, which prints the text after its JSR; <PRINT_CHARACTER>, which prints without
;;   writing to the *SPOOL file; and <SAVE_REGISTERS>, which restores A, X and Y when its caller returns.
;; - Reading a file specification, `:drive.directory.name`, into <DFS_PATTERN> and <DFS_NAME>, and finding the
;;   files it matches in the catalogue, with `#` and `*` as wildcards where a command allows them.
;; - The * command tables, <DFS_COMMAND_TABLE>, <UTILITY_COMMAND_TABLE> and <HELP_TOPIC_TABLE>, and
;;   <SCAN_COMMAND_TABLE>, which looks a command up in them.
;; - *CAT, <DFS_CAT>, and *INFO, *WIPE, *DELETE, *DESTROY, *DRIVE, *DIR and *LIB; *RUN and running a file from the
;;   library for a command the DFS does not know; and loading and saving a whole file for OSFILE.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; Errors this part raises.
DFS_ERROR_BAD_NAME = $CC            ;; error &CC, "Bad name"
DFS_ERROR_BAD_DIR = $CE             ;; error &CE, "Bad dir"
DFS_ERROR_NOT_FOUND = $D6           ;; error &D6, "Not found"
DFS_ERROR_BAD_COMMAND = $FE         ;; error &FE, "Bad command"
OPCODE_BRK = $00                    ;; the BRK instruction, which the error routines put at &0100

; OSBYTE calls.
OSBYTE_TUBE_PRESENCE = $EA          ;; OSBYTE &EA: reads the Tube flag, &FF if a Tube is present
OSBYTE_OUTPUT_STATUS = $EC          ;; OSBYTE &EC: reads the output stream status, as *FX 3 sets it
OUTPUT_NO_SPOOL = %00010000         ;; in the output stream status: do not write to the *SPOOL file

; The Tube host's calls (A) through its entry at &0406.
DFS_TUBE_EXECUTE = $04              ;; Tube transfer 4: start the second processor running at an address
DFS_TUBE_RELEASE = $81              ;; Tube call: release the Tube, claimant 1, the DFS

; The catalogue.
CATALOGUE_ENTRY_SIZE = 8            ;; the bytes each file takes in each of the catalogue's two sectors
CATALOGUE_LOCKED = $80              ;; bit 7 of a file's directory letter: the file is locked
NAME_LENGTH = 7                     ;; the most characters in a file's name
DFS_DRIVE_MASK = %00000011          ;; the drive number's bits: drives 0-3
LOCKED_ATTRIBUTE = $08              ;; OSFILE's attribute for a locked file: bit 3, not deletable

; The parameters a command takes, by their number in the DFS's syntax strings (SYNTAX_STRINGS); a command's syntax byte
; holds the first in its low nibble and the second in its high nibble, 0 for none.
SYNTAX_NONE = 0                     ;; no parameter
SYNTAX_FSP = 1                      ;; fsp in angle brackets: a file specification
SYNTAX_AFSP = 2                     ;; afsp in angle brackets: an ambiguous file specification, with wildcards
SYNTAX_L = 3                        ;; (L): *ACCESS's attribute
SYNTAX_SOURCE_DEST = 4              ;; source and dest. in angle brackets: two drives
SYNTAX_OLD_NEW = 5                  ;; old fsp and new fsp in angle brackets: *RENAME's names
SYNTAX_DIR = 6                      ;; dir in angle brackets, in parentheses: an optional directory
SYNTAX_OPTIONAL_DRIVE = 7           ;; drive in angle brackets, in parentheses: an optional drive
SYNTAX_TITLE = 8                    ;; title in angle brackets: a disc title
SYNTAX_DRIVE = 9                    ;; drive in angle brackets: a drive

; ---------------------------------------------------------------------------------------------------------------------
; The DFS's workspace in page &10 that this part uses; DfsCatalogue.asm names the rest
; ---------------------------------------------------------------------------------------------------------------------

DFS_LIBRARY = DFS_WORKSPACE + $CB   ;; the library's directory letter, set by *LIB
DFS_LIBRARY_DRIVE = DFS_WORKSPACE + $CC ;; the library's drive, set by *LIB
DFS_WILDCARD_CHARACTER = DFS_WORKSPACE + $CD    ;; '#', which matches any one character, or &FF for no wildcards
DFS_WILDCARD_STRING = DFS_WORKSPACE + $CE       ;; '*', which matches any characters, or &FF for no wildcards
DFS_COMMAND_TAIL = DFS_WORKSPACE + $D9  ;; &10D9-&10DA, the address of the command line after the name *RUN ran
DFS_PATTERN = DFS_WORKSPACE         ;; &1000-&103F, the name being looked for, padded with spaces, wildcards and all
DFS_PATTERN_SIZE = $40              ;; the bytes <PARSE_NAME> pads <DFS_PATTERN> to
DFS_NAMED_PATTERN = DFS_WORKSPACE + $58 ;; &1058-&105F, a copy of <DFS_NAME> that <FIND_NAMED_FILE> looks for
DFS_INFO_BLOCK = DFS_WORKSPACE + $60    ;; &1060-&1071, *INFO's file information, laid out as OSFILE's block
CAT_SORT_KEY = DFS_INFO_BLOCK       ;; &1060-&1067, *CAT's next file to print: its name, then its directory

; ---------------------------------------------------------------------------------------------------------------------
; Zero page that this part uses
; ---------------------------------------------------------------------------------------------------------------------

DFS_BLOCK = FS_SCRATCH              ;; &B0-&B1, a pointer to an OSFILE control block, or to the private workspace
DFS_INLINE_A = FS_SCRATCH + 3       ;; A, kept while the inline routines take their return address
DFS_ENTRY_POINTER = FS_SCRATCH + 6  ;; &B6-&B7, a search's place in the catalogue: CATALOGUE_NAMES + 8 + the entry
DFS_NAME_POINTER = FS_SCRATCH + 10  ;; &BA-&BB, the address of the file specification being read
COMMAND_NAME_OFFSET = FS_SCRATCH + 12   ;; the offset in the command table, less one, of the command being run
DFS_LOAD = FS_SCRATCH + 12          ;; &BC-&BD, the low two bytes of a file's load address
DFS_EXEC = FS_SCRATCH + 14          ;; &BE-&BF, the low two bytes of a file's execution address
DFS_LENGTH = FS_WORKSPACE           ;; &C0-&C1, the low two bytes of a file's length
DFS_TOP_BITS = FS_WORKSPACE + 2     ;; a file's catalogue byte of top bits: start sector, load, length, execution
DFS_START_SECTOR = FS_WORKSPACE + 3 ;; the low byte of a file's start sector
DFS_NAME = FS_WORKSPACE + 5         ;; &C5-&CB, the name read by <PARSE_NAME>, padded with spaces
DFS_NAME_DIRECTORY = FS_WORKSPACE + 12  ;; the directory letter read by <PARSE_NAME>
DFS_CURRENT_DRIVE = FS_WORKSPACE + 13   ;; the drive being used, which a file specification can set
CAT_COLUMN = OS_COMMAND_WORKSPACE   ;; *CAT: 0 when the next name goes in the right-hand column
CAT_LAST_DIRECTORY = OS_COMMAND_WORKSPACE + 2   ;; *CAT: the directory of the last file printed, 0 for the current one
CAT_CANDIDATE = OS_COMMAND_WORKSPACE + 3        ;; *CAT: the catalogue offset of the file in <CAT_SORT_KEY>
DFS_INLINE_POINTER = OS_COMMAND_WORKSPACE + 6   ;; &AE-&AF, the inline routines' pointer to the bytes after their JSR

; ---------------------------------------------------------------------------------------------------------------------
; Entry points, errors and printing
; ---------------------------------------------------------------------------------------------------------------------

;; Offers a service call to the DFS: the NFS's service handler calls or jumps here to pass each call on.
;; In: A = the service call, X = this ROM's number, Y = the call's parameter
DFS_SERVICE_ENTRY:
    jmp DFS_SERVICE_HANDLER

;; Calls the current filing system's control entry, through FSCV.
;; In: A = the OSFSC reason, such as 6 to warn it that another filing system is taking over
DFS_CALL_FSCV:
    jmp (FSCV)

;; Raises a disc error: "Disk " and the message after the JSR, as <DFS_ERROR> does.
;;
;; Used as:
;;
;; > jsr DISK_ERROR
;; > .byte number, "message", 0
;;
;; The message can also end at a byte with bit 7 set, which is code to run, as for <DFS_ERROR>.
;; See: <BAD_ERROR>, <DFS_ERROR>
DISK_ERROR:
    jsr DFS_ERROR
    .byte 0                         ; a dummy number, replaced by the caller's
    .byte "Disk "
    bcc ERROR_APPEND                ; ends the text (bit 7 set); always taken, as carry is clear

;; Raises an error whose message starts "Bad ", followed by the message after the JSR, as <DFS_ERROR> does.
;;
;; Used as:
;;
;; > jsr BAD_ERROR
;; > .byte number, "message", 0
;; See: <DISK_ERROR>, <DFS_ERROR>
BAD_ERROR:
    jsr DFS_ERROR
    .byte 0                         ; a dummy number, replaced by the caller's
    .byte "Bad "
    bcc ERROR_APPEND                ; ends the text (bit 7 set); always taken, as carry is clear

;; Raises the error whose number and message follow the JSR, first tidying up after a failed disc access.
;;
;; The DFS's errors are written inline:
;;
;; > jsr DFS_ERROR
;; > .byte number, "message", 0
;;
;; The routine forgets which drive's catalogue is in memory, so that the next command reads it again, and if the error
;; came while a channel's buffer was being written (<DFS_BUFFER_TRANSFER> is 0), it forgets the *EXEC or *SPOOL file if
;; that is the channel (STOP_EXEC_OR_SPOOL), so that reporting the error doesn't use the file again. Then it builds the
;; error at &0100: a BRK, the number, the message and a zero, releases the Tube, and runs the BRK, which the MOS passes
;; to BRKV.
;;
;; The message can instead end at a byte with bit 7 set: that byte is an instruction, which the routine jumps to,
;; with the message built so far at &0100. <DISK_ERROR> and <BAD_ERROR> build their prefixes that way, and then
;; append their caller's message with <ERROR_APPEND>.
;; Out: X = for a message that ends at an instruction, the offset in page 1 where that byte was copied,
;;   carry = clear
;; Uses: A, Y, DFS_INLINE_POINTER, DFS_INLINE_A
;; Entry: BUILD_ERROR = doesn't tidy up first, ERROR_APPEND = with X = the offset in page 1 of the last byte built,
;;   adds the message after its own JSR to the one being built, its number replacing the number there
;; See: <DISK_ERROR>, <BAD_ERROR>
DFS_ERROR:
    lda DFS_BUFFER_TRANSFER
    bne DFS_ERROR_1                 ; not writing a buffer
    jsr STOP_EXEC_OR_SPOOL                       ; forget the *EXEC or *SPOOL file if it is the channel being written
DFS_ERROR_1:
    lda #$FF
    sta DFS_CATALOGUE_DRIVE         ; read the catalogue again before using it
    sta DFS_BUFFER_TRANSFER
BUILD_ERROR:
    ldx #$02                        ; the message starts at &0102
    lda #OPCODE_BRK
    sta STACK
ERROR_APPEND:
    sta DFS_INLINE_A
    pla                             ; take the return address, which points at the byte before the number
    sta DFS_INLINE_POINTER
    pla
    sta DFS_INLINE_POINTER+1
    lda DFS_INLINE_A
    ldy #$00
    jsr NEXT_INLINE_BYTE
    lda (DFS_INLINE_POINTER),y      ; the error number
    sta STACK+1
    dex
BUILD_ERROR_LOOP:
    jsr NEXT_INLINE_BYTE
    inx
    lda (DFS_INLINE_POINTER),y
    sta STACK,x
    bmi INLINE_RETURN               ; an instruction: run it
    bne BUILD_ERROR_LOOP
    jsr DFS_RELEASE_TUBE            ; the zero that ends the message
    jmp STACK                       ; the BRK

;; Prints the text after the JSR, then continues with the instruction after it.
;;
;; Used as:
;;
;; > jsr DFS_PRINT_INLINE
;; > .byte "text"
;; > (an instruction)
;;
;; The text ends at the first byte with bit 7 set, which is the opcode of the instruction that follows: an LDA, say,
;; or a NOP where nothing else is needed. The text is printed with <PRINT_CHARACTER>, so it doesn't go to a *SPOOL file.
;; Out: carry = clear
;; Uses: DFS_INLINE_POINTER, DFS_INLINE_A
;; Keeps: A, X, Y
DFS_PRINT_INLINE:
    sta DFS_INLINE_A
    pla                             ; take the return address, which points at the byte before the text
    sta DFS_INLINE_POINTER
    pla
    sta DFS_INLINE_POINTER+1
    lda DFS_INLINE_A
    pha
    tya
    pha
    ldy #$00
DFS_PRINT_INLINE_LOOP:
    jsr NEXT_INLINE_BYTE
    lda (DFS_INLINE_POINTER),y
    bmi DFS_PRINT_INLINE_END
    jsr PRINT_CHARACTER
    jmp DFS_PRINT_INLINE_LOOP
DFS_PRINT_INLINE_END:
    pla
    tay
    pla
;; Continues at the byte the inline pointer points to, with carry clear: the end of <DFS_PRINT_INLINE> and of an error
;; message that ends at an instruction (<DFS_ERROR>).
;; In: DFS_INLINE_POINTER = the instruction
;; Out: carry = clear
INLINE_RETURN:
    clc
    jmp (DFS_INLINE_POINTER)

;; Prints the low nibble of A as a hexadecimal digit, then a full stop: a drive number before a directory. Falls
;; through to PRINT_DOT.
;; Out: A = '.'
;; Keeps: X, Y
PRINT_DIGIT_AND_DOT:
    jsr PRINT_HEX_DIGIT
;; Prints a full stop. Falls through to PRINT_CHARACTER.
;; Out: A = '.'
;; Keeps: X, Y
PRINT_DOT:
    lda #'.'
;; Prints a character to the screen, and to the printer if it is on, but not to the *SPOOL file.
;;
;; The character goes through OSASCI, so a carriage return becomes a new line. The output stream status that *FX 3 sets
;; is changed to leave out the *SPOOL file for the one character, then put back.
;; In: A = the character
;; Keeps: A, X, Y
PRINT_CHARACTER:
    jsr SAVE_REGISTERS
    pha
    lda #OSBYTE_OUTPUT_STATUS
    jsr READ_OS_VARIABLE                       ; read the output stream status into X
    txa
    pha
    ora #OUTPUT_NO_SPOOL
    jsr DFS_SELECT_OUTPUT                       ; OSBYTE 3: select those streams
    pla
    tax
    pla
    jsr OSASCI
    jmp DFS_SELECT_OUTPUT_X                       ; OSBYTE 3 with X: put the streams back

;; Prints A as two hexadecimal digits. Falls through to PRINT_HEX_DIGIT for the low one.
;; In: A = the byte
;; Out: A = the character of its low digit
;; Keeps: X, Y
PRINT_HEX_BYTE:
    pha
    jsr SHIFT_RIGHT_4
    jsr PRINT_HEX_DIGIT
    pla
;; Prints the low nibble of A as a hexadecimal digit.
;; In: A = the nibble, in bits 0-3
;; Out: A = the digit's character
;; Keeps: X, Y
PRINT_HEX_DIGIT:
    jsr HEX_DIGIT
    bne PRINT_CHARACTER             ; always taken: a digit's character isn't zero

;; Gives the hexadecimal digit for the low nibble of A.
;; In: A = the nibble, in bits 0-3
;; Out: A = '0'-'9' or 'A'-'F'
;; Keeps: X, Y
HEX_DIGIT:
    and #$0F
    cmp #$0A
    bcc HEX_DIGIT_1
    adc #'A' - '9' - 2              ; carry is set, so this and the next add skip from '9'+1 to 'A'
HEX_DIGIT_1:
    adc #'0'
    rts

; ---------------------------------------------------------------------------------------------------------------------
; OSFILE control blocks
; ---------------------------------------------------------------------------------------------------------------------

;; Copies a four-byte address from an OSFILE control block: its low two bytes to zero page, its high two to page &10.
;;
;; OSFILE (DFS_OSFILE) calls this for each address in its block in turn, so the low bytes land in <DFS_LOAD>,
;; <DFS_EXEC>, <DFS_LENGTH> and <DFS_TOP_BITS> and the high bytes in <DFS_LOAD_HIGH>, <DFS_EXEC_HIGH> and
;; the bytes after them.
;; In: DFS_BLOCK = the control block, Y = the address's offset in it, X = the offset of the low bytes from
;;   DFS_NAME_POINTER, and of the high bytes from DFS_TUBE_ADDRESS
;; Out: X = X + 2, Y = Y + 4
COPY_BLOCK_ADDRESS:
    jsr COPY_BLOCK_WORD
    dex
    dex
    jsr COPY_BLOCK_HIGH_BYTE
;; Copies a byte from the control block at DFS_BLOCK to DFS_TUBE_ADDRESS,X.
;; In: Y = its offset in the block, X = the offset to copy it to
;; Out: X = X + 1, Y = Y + 1
COPY_BLOCK_HIGH_BYTE:
    lda (DFS_BLOCK),y
    sta DFS_TUBE_ADDRESS,x
    inx
    iny
    rts

;; Copies two bytes from the control block at DFS_BLOCK to DFS_NAME_POINTER,X.
;; In: Y = their offset in the block, X = the offset to copy them to
;; Out: X = X + 2, Y = Y + 2
COPY_BLOCK_WORD:
    jsr COPY_BLOCK_BYTE
;; Copies a byte from the control block at DFS_BLOCK to DFS_NAME_POINTER,X.
;; In: Y = its offset in the block, X = the offset to copy it to
;; Out: X = X + 1, Y = Y + 1
COPY_BLOCK_BYTE:
    lda (DFS_BLOCK),y
    sta DFS_NAME_POINTER,x
    inx
    iny
    rts

; ---------------------------------------------------------------------------------------------------------------------
; File specifications
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a file specification from the command line, in the current directory and drive unless it gives others.
;; In: TEXT_POINTER = the command line, Y = the offset of the specification in it
;; Out: Y = the offset after the specification, carry = set, negative = set
;; Uses: A, X
READ_NAME:
    jsr SELECT_DEFAULTS                       ; start from the current directory and drive
    jmp PARSE_NAME

;; Reads the file specification at the address in <DFS_NAME_POINTER>, in the current directory and drive unless it
;; gives others.
;; In: DFS_NAME_POINTER = the specification, as a string GSREAD can read
;; Out: Y = the offset after the specification, carry = set, TEXT_POINTER = the specification
;; Uses: A, X
;; Entry: READ_NAME_AT_POINTER = keeps the directory and drive already set
READ_BLOCK_NAME:
    jsr SELECT_DEFAULTS                       ; start from the current directory and drive
READ_NAME_AT_POINTER:
    lda DFS_NAME_POINTER
    sta TEXT_POINTER
    lda DFS_NAME_POINTER+1
    sta TEXT_POINTER+1
    ldy #$00
    jsr START_STRING
;; Reads a file specification, `:drive.directory.name`, where the drive and the directory can each be left out.
;;
;; A drive changes <DFS_CURRENT_DRIVE> and a directory <DFS_NAME_DIRECTORY>; otherwise they keep what they had. The
;; name, at most seven characters and never a control character or DELETE, goes to <DFS_PATTERN>, padded with spaces
;; to 64 bytes, and its first seven bytes to <DFS_NAME>. Wildcards are kept as they are, for the search to deal
;; with.
;; A specification that starts with a full stop sets the directory to a space.
;;
;; Raises "Bad name" (&CC) for an empty, too long or badly formed specification, and "Bad drive" (&CD) for a bad drive.
;; In: TEXT_POINTER = the text, Y = the offset of the specification in it, after GSINIT
;; Out: Y = the offset after the specification, carry = set, negative = set
;; Uses: A, X
PARSE_NAME:
    ldx #' '                        ; a full stop alone before the name means directory ' '
    jsr READ_NAME_CHARACTER
    bcs BAD_NAME
    sta DFS_PATTERN
    cmp #'.'
    bne PARSE_NAME_DRIVE
PARSE_NAME_DIRECTORY:
    stx DFS_NAME_DIRECTORY
    beq PARSE_NAME                  ; always taken: the directory is set, so read the name
PARSE_NAME_DRIVE:
    cmp #':'
    bne PARSE_NAME_CHARACTERS
    jsr READ_DRIVE_NUMBER                       ; read the drive number
    jsr SET_DRIVE
    jsr READ_NAME_CHARACTER
    bcs BAD_NAME
    cmp #'.'
    beq PARSE_NAME                  ; the drive must be followed by a full stop
;; Raises "Bad name" (&CC).
BAD_NAME:
    jsr BAD_ERROR
    .byte DFS_ERROR_BAD_NAME
    .byte "name",0
PARSE_NAME_CHARACTERS:
    tax                             ; the first character, which may be the directory
    jsr READ_NAME_CHARACTER
    bcs PARSE_NAME_ONE_CHARACTER
    cmp #'.'
    beq PARSE_NAME_DIRECTORY        ; it was the directory
    ldx #$01
PARSE_NAME_LOOP:
    sta DFS_PATTERN,x
    inx
    jsr READ_NAME_CHARACTER
    bcs PARSE_NAME_PAD
    cpx #NAME_LENGTH
    bne PARSE_NAME_LOOP
    beq BAD_NAME                    ; an eighth character

;; Reads the next character of a file specification with GSREAD, checking that it may be part of a name.
;;
;; Raises "Bad name" (&CC) for a control character or DELETE, other than the carriage return that ends the line.
;; In: TEXT_POINTER = the text, Y = the offset of the next character
;; Out: A = the character, with bit 7 clear, carry = set at the end of the string, Y = the offset after it
;; Keeps: X
READ_NAME_CHARACTER:
    jsr GSREAD
    php
    and #$7F
    cmp #$0D                        ; a carriage return
    beq READ_NAME_CHARACTER_1
    cmp #' '
    bcc BAD_NAME
    cmp #$7F                        ; DELETE
    beq BAD_NAME
READ_NAME_CHARACTER_1:
    plp
    rts

PARSE_NAME_ONE_CHARACTER:
    ldx #$01
PARSE_NAME_PAD:
    lda #' '
PARSE_NAME_PAD_LOOP:
    sta DFS_PATTERN,x
    inx
    cpx #DFS_PATTERN_SIZE
    bne PARSE_NAME_PAD_LOOP
    ldx #NAME_LENGTH - 1
PARSE_NAME_COPY:
    lda DFS_PATTERN,x
    sta DFS_NAME,x
    dex
    bpl PARSE_NAME_COPY
    rts

;; Prints a file's name as the catalogue shows it: its directory and a full stop, the name, then `L` if it is locked.
;;
;; A file whose directory byte is zero, as *CAT makes it for the current directory's files, has two spaces in place of
;; the directory. The name is followed by two spaces, `L` or a space, and a space, which makes 13 characters.
;; In: Y = the file's offset in the catalogue
;; Keeps: A, X, Y
PRINT_FILE_NAME:
    jsr SAVE_REGISTERS
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y     ; the directory, with the lock in bit 7
    php
    and #$7F
    bne PRINT_FILE_NAME_DIRECTORY
    jsr DFS_PRINT_TWO_SPACES                       ; two spaces
    beq PRINT_FILE_NAME_NAME        ; always taken
PRINT_FILE_NAME_DIRECTORY:
    jsr PRINT_CHARACTER
    jsr PRINT_DOT
PRINT_FILE_NAME_NAME:
    ldx #NAME_LENGTH - 1
PRINT_FILE_NAME_LOOP:
    lda CATALOGUE_NAMES+8,y
    and #$7F
    jsr PRINT_CHARACTER
    iny
    dex
    bpl PRINT_FILE_NAME_LOOP
    jsr DFS_PRINT_TWO_SPACES                       ; two spaces
    lda #' '
    plp
    bpl PRINT_FILE_NAME_LOCK
    lda #'L'
PRINT_FILE_NAME_LOCK:
    jsr PRINT_CHARACTER
    ldy #$01
;; Prints Y spaces.
;; In: Y = how many, 1-255
;; Out: Y = 0, carry = clear
;; Keeps: A, X
PRINT_SPACES:
    jsr DFS_PRINT_SPACE                       ; a space
    dey
    bne PRINT_SPACES
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Bits of a byte
; ---------------------------------------------------------------------------------------------------------------------

;; Gives bits 6-7 of A in bits 0-1: in a catalogue entry's top bits, those of its execution address.
;; Out: A = 0-3
;; Keeps: X, Y
BITS_6_7:
    lsr a
    lsr a
;; Gives bits 4-5 of A in bits 0-1: in a catalogue entry's top bits, those of its length.
;; Out: A = 0-3
;; Keeps: X, Y
BITS_4_5:
    lsr a
    lsr a
;; Gives bits 2-3 of A in bits 0-1: in a catalogue entry's top bits, those of its load address.
;; Out: A = 0-3
;; Keeps: X, Y
BITS_2_3:
    lsr a
    lsr a
    and #$03
    rts

;; Shifts A right five bits.
;; Keeps: X, Y
SHIFT_RIGHT_5:
    lsr a
;; Shifts A right four bits: its high nibble, in the low nibble.
;; Keeps: X, Y
SHIFT_RIGHT_4:
    lsr a
    lsr a
    lsr a
    lsr a
    rts

;; Shifts A left five bits.
;; Keeps: X, Y
SHIFT_LEFT_5:
    asl a
;; Shifts A left four bits: its low nibble, in the high nibble.
;; Keeps: X, Y
SHIFT_LEFT_4:
    asl a
    asl a
    asl a
    asl a
    rts

;; Sets up a transfer of a whole file: where it goes, how much there is, and the track and sector it starts at.
;;
;; The buffer address goes to <DFS_TRANSFER_ADDRESS>. The length becomes counts for the 8271 driver: the first byte of
;; <DFS_TRANSFER_COUNT> is its low byte, and the next two its middle and top bytes, each one more, less one where the
;; bytes below are zero. The ten-bit start sector, divided by the ten sectors on a track, gives <DFS_TRACK> and
;; <DFS_SECTOR>.
;; In: DFS_LOAD = the buffer, DFS_LENGTH and DFS_TOP_BITS = the length, DFS_TOP_BITS and
;;   DFS_START_SECTOR = the start sector
;; Out: DFS_TRACK, DFS_SECTOR, DFS_TRANSFER_COUNT..DFS_TRANSFER_COUNT+2, DFS_TRANSFER_ADDRESS/DFS_TRANSFER_ADDRESS+1
;; Uses: A, X
SET_UP_FILE_TRANSFER:
    lda DFS_LOAD
    sta DFS_TRANSFER_ADDRESS
    lda DFS_LOAD+1
    sta DFS_TRANSFER_ADDRESS+1
    lda #$FF
    sta DFS_TRACK                   ; the division counts up from 0
    ldx DFS_LENGTH+1
    inx
    stx DFS_TRANSFER_COUNT+1
    lda DFS_TOP_BITS
    jsr BITS_4_5                    ; the length's top bits
    sta DFS_TRANSFER_COUNT+2
    inc DFS_TRANSFER_COUNT+2
    lda DFS_LENGTH
    sta DFS_TRANSFER_COUNT
    bne SET_UP_FILE_TRANSFER_SECTOR
    dec DFS_TRANSFER_COUNT+1
    bne SET_UP_FILE_TRANSFER_SECTOR
    dec DFS_TRANSFER_COUNT+2
SET_UP_FILE_TRANSFER_SECTOR:
    lda DFS_TOP_BITS
    and #$03                        ; the start sector's top bits
    tax
    lda DFS_START_SECTOR
SET_UP_FILE_TRANSFER_DIVIDE:
    sec
SET_UP_FILE_TRANSFER_SUBTRACT:
    inc DFS_TRACK
    sbc #DFS_SECTORS_PER_TRACK
    bcs SET_UP_FILE_TRANSFER_SUBTRACT
    dex                             ; borrow from the top bits
    bpl SET_UP_FILE_TRANSFER_DIVIDE
    adc #DFS_SECTORS_PER_TRACK
    sta DFS_SECTOR
SET_UP_FILE_TRANSFER_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Searching the catalogue
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a file specification from the command line and finds the first file it matches.
;;
;; Raises "Not found" (&D6) if there is none.
;; In: TEXT_POINTER = the command line, Y = the offset of the specification in it
;; Out: Y = the file's offset in the catalogue, carry = set
;; Uses: A, X
;; Entry: FIND_BLOCK_NAME = reads the specification at the address in DFS_NAME_POINTER instead, FIND_OR_ERROR = only
;;   searches, for the specification already read
FIND_NAME:
    jsr READ_NAME
    bmi FIND_OR_ERROR               ; always taken
FIND_BLOCK_NAME:
    jsr READ_BLOCK_NAME
FIND_OR_ERROR:
    jsr FIND_FIRST
    bcs SET_UP_FILE_TRANSFER_DONE   ; found
;; Raises "Not found" (&D6).
NOT_FOUND:
    jsr BUILD_ERROR
    .byte DFS_ERROR_NOT_FOUND
    .byte "Not found",0

;; *INFO: prints the information for each file that matches an ambiguous file specification.
;;
;; Each file's line gives its name, then in hexadecimal its load address, execution address, length and start sector.
;; Raises "Not found" (&D6) if no file matches.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
INFO_COMMAND:
    jsr ALLOW_WILDCARDS                       ; allow wildcards
    jsr REQUIRE_ARGUMENT                       ; a Syntax error if there is no parameter
    jsr FIND_NAME
INFO_COMMAND_LOOP:
    jsr PRINT_INFO
    jsr FIND_NEXT
    bcs INFO_COMMAND_LOOP
    rts

;; Finds the file named in <DFS_NAME>, in the directory in <DFS_NAME_DIRECTORY>, leaving <DFS_PATTERN> alone.
;;
;; The name is copied to <DFS_NAMED_PATTERN> and looked for from the start of the catalogue, which is read first if
;; needed.
;; Out: carry = set if found, Y = the file's offset in the catalogue
;; Uses: A, X
FIND_NAMED_FILE:
    ldx #NAME_LENGTH - 1
FIND_NAMED_FILE_LOOP:
    lda DFS_NAME,x
    sta DFS_NAMED_PATTERN,x
    dex
    bpl FIND_NAMED_FILE_LOOP
    lda #' '
    sta DFS_NAMED_PATTERN+NAME_LENGTH
    lda #DFS_NAMED_PATTERN - DFS_PATTERN
    bne FIND_FIRST_WITH             ; always taken

;; Finds the next file that matches <DFS_PATTERN>, after the one <FIND_FIRST> or the last FIND_NEXT found.
;; In: DFS_ENTRY_POINTER = where the last search stopped
;; Out: carry = set if found, Y = the file's offset in the catalogue, DFS_ENTRY_POINTER = 8 more
;; Uses: A, X
FIND_NEXT:
    ldx #$00
    beq FIND_LOOP                   ; always taken

;; Finds the first file in the catalogue that matches <DFS_PATTERN> and is in the directory <DFS_NAME_DIRECTORY>.
;;
;; The catalogue of <DFS_CURRENT_DRIVE> is read first unless it is already in memory. Names match as
;; <MATCH_NAME> says; the directory letter matches as one of its characters, ignoring the lock.
;; Out: carry = set if found, Y = the file's offset in the catalogue (its name is at CATALOGUE_NAMES+8+Y),
;;   DFS_ENTRY_POINTER = 8 more, for <FIND_NEXT>
;; Uses: A, X
;; Entry: FIND_FIRST_WITH = with A = the pattern's offset from DFS_PATTERN
FIND_FIRST:
    lda #$00
FIND_FIRST_WITH:
    pha
    jsr ENSURE_CATALOGUE                       ; read the catalogue if it isn't in memory
    pla
    tax
    lda #>CATALOGUE_NAMES
    sta DFS_ENTRY_POINTER+1
    lda #$00
    sta DFS_ENTRY_POINTER
FIND_LOOP:
    ldy #$00
    lda DFS_ENTRY_POINTER
    cmp CATALOGUE_SIZE
    bcs MATCH_NAME_FAIL             ; no more files
    adc #CATALOGUE_ENTRY_SIZE
    sta DFS_ENTRY_POINTER
    jsr MATCH_NAME
    bcc FIND_LOOP
    lda DFS_NAME_DIRECTORY
    ldy #NAME_LENGTH                ; the directory letter
    jsr COMPARE_CHARACTER
    bne FIND_LOOP
    ldy DFS_ENTRY_POINTER
    sec
;; Subtracts 8 from Y: steps back one catalogue entry.
;; Keeps: A, X, carry
PREVIOUS_ENTRY:
    dey
    dey
    dey
    dey
    dey
    dey
    dey
    dey
    rts

;; Tests whether the catalogue name at DFS_ENTRY_POINTER matches the pattern, from given places in each.
;;
;; The wildcard in <DFS_WILDCARD_CHARACTER> (`#`) matches any one character, and the one in <DFS_WILDCARD_STRING>
;; (`*`) any number of them, tried by calling this routine again at each place after it. Letters match in either case.
;; The pattern must end, with a space, where the seven-character name does.
;; In: X = the offset in DFS_PATTERN, Y = the offset in the name, DFS_ENTRY_POINTER = the name
;; Out: carry = set if it matches
;; Keeps: A, X, Y
MATCH_NAME:
    jsr SAVE_REGISTERS
MATCH_NAME_LOOP:
    lda DFS_PATTERN,x
    cmp DFS_WILDCARD_STRING
    bne MATCH_NAME_CHARACTER
    inx
MATCH_NAME_STAR:
    jsr MATCH_NAME                  ; the rest of the pattern against the rest of the name, from each place in turn
    bcs MATCH_NAME_DONE
    iny
    cpy #NAME_LENGTH
    bcc MATCH_NAME_STAR
MATCH_NAME_END:
    lda DFS_PATTERN,x
    cmp #' '                        ; the pattern must end here; carry is set if it does
    bne MATCH_NAME_FAIL
    rts
MATCH_NAME_CHARACTER:
    cpy #NAME_LENGTH
    bcs MATCH_NAME_END
    jsr COMPARE_CHARACTER
    bne MATCH_NAME_FAIL
    inx
    iny
    bne MATCH_NAME_LOOP             ; always taken
MATCH_NAME_FAIL:
    clc
MATCH_NAME_DONE:
    rts

;; Compares a pattern character with a character of a catalogue entry.
;;
;; Either wildcard matches anything; a letter matches in either case; the lock bit of a directory letter is ignored.
;; In: A = the pattern's character, DFS_ENTRY_POINTER = the entry, Y = the character's offset in it
;; Out: zero = set if they match
;; Keeps: X, Y
COMPARE_CHARACTER:
    cmp DFS_WILDCARD_STRING
    beq COMPARE_CHARACTER_DONE
    cmp DFS_WILDCARD_CHARACTER
    beq COMPARE_CHARACTER_DONE
    jsr CHECK_LETTER
    eor (DFS_ENTRY_POINTER),y
    bcs COMPARE_CHARACTER_1
    and #$5F                        ; a letter: ignore the case bit
COMPARE_CHARACTER_1:
    and #$7F                        ; ignore the lock bit
COMPARE_CHARACTER_DONE:
    rts

;; Makes a letter capital and clears bit 7, keeping the flags: *CAT compares names with it inside a subtraction.
;; In: A = the character
;; Out: A = the character, with bit 7 clear and a letter in capitals
;; Keeps: X, Y, carry
FOLD_CASE:
    php
    jsr CHECK_LETTER
    bcs FOLD_CASE_1
    and #$5F
FOLD_CASE_1:
    and #$7F
    plp
    rts

;; Removes a file from the catalogue in memory, moving the files after it down.
;;
;; Raises "Locked" (&C3) if the file is locked, or "Open" (&C2) if it is open.
;; In: Y = the file's offset in the catalogue
;; Out: Y = the old catalogue size, carry = clear
;; Uses: A
DELETE_ENTRY:
    jsr CHECK_NOT_LOCKED_OR_OPEN                       ; check that the file is not locked or open
DELETE_ENTRY_LOOP:
    lda CATALOGUE_NAMES+8+CATALOGUE_ENTRY_SIZE,y
    sta CATALOGUE_NAMES+8,y
    lda CATALOGUE_INFO+8+CATALOGUE_ENTRY_SIZE,y
    sta CATALOGUE_INFO+8,y
    iny
    cpy CATALOGUE_SIZE
    bcc DELETE_ENTRY_LOOP
    tya
    sbc #CATALOGUE_ENTRY_SIZE       ; carry is set: one file fewer
    sta CATALOGUE_SIZE
    clc
DELETE_ENTRY_DONE:
    rts

;; Tests whether A is a letter.
;; In: A = the character
;; Out: carry = clear for a letter, A-Z or a-z
;; Keeps: A, X, Y
CHECK_LETTER:
    pha
    and #$5F
    cmp #'A'
    bcc CHECK_LETTER_NOT
    cmp #'Z' + 1
    bcc CHECK_LETTER_DONE
CHECK_LETTER_NOT:
    sec
CHECK_LETTER_DONE:
    pla
    rts

;; Prints a file's information, as <PRINT_INFO> does, if *OPT 1 has turned the messages on.
;; In: Y = the file's offset in the catalogue
PRINT_INFO_IF_ON:
    bit DFS_MESSAGES_OFF
    bmi DELETE_ENTRY_DONE           ; off
;; Prints a line of information about a file, as *INFO does.
;;
;; The line gives the name, as <PRINT_FILE_NAME> prints it; the load address, the execution address and the length,
;; each as six hexadecimal digits; and the start sector, as three. For example:
;;
;; > $.PROGRAM    FF1900 FF8023 000310 002
;; In: Y = the file's offset in the catalogue
;; Keeps: A, X, Y
PRINT_INFO:
    jsr SAVE_REGISTERS
    jsr PRINT_FILE_NAME
    tya
    pha
    lda #<DFS_INFO_BLOCK
    sta DFS_BLOCK
    lda #>DFS_INFO_BLOCK
    sta DFS_BLOCK+1
    jsr GET_FILE_INFO
    ldy #2                          ; the load address's offset in the block
    jsr DFS_PRINT_SPACE                       ; a space
    jsr PRINT_INFO_ADDRESS
    jsr PRINT_INFO_ADDRESS
    jsr PRINT_INFO_ADDRESS
    pla
    tay
    lda CATALOGUE_INFO+8+6,y        ; the top bits
    and #$03                        ; the start sector's
    jsr PRINT_HEX_DIGIT
    lda CATALOGUE_INFO+8+7,y        ; the start sector's low byte
    jsr PRINT_HEX_BYTE
    jsr DFS_PRINT_NEWLINE                       ; a new line
    jmp SELECT_DRIVE

;; Prints three bytes of <DFS_INFO_BLOCK>, the highest first, then a space, and moves on to the next address.
;; In: Y = the offset of the four-byte address in the block
;; Out: Y = the offset of the next address, X = 0
;; Uses: A
PRINT_INFO_ADDRESS:
    ldx #$03
PRINT_INFO_ADDRESS_LOOP:
    lda DFS_INFO_BLOCK+2,y
    jsr PRINT_HEX_BYTE
    dey
    dex
    bne PRINT_INFO_ADDRESS_LOOP
    jsr ADD_7_TO_Y                  ; from three before the address to four after it
    jmp DFS_PRINT_SPACE                       ; a space

;; Reads the catalogue of <DFS_CURRENT_DRIVE> from the disc, keeping the registers.
;; Keeps: A, X, Y
FETCH_CATALOGUE:
    jsr SAVE_REGISTERS
    jmp READ_CATALOGUE

;; Fills in an OSFILE control block with a file's addresses, length and attributes from its catalogue entry.
;;
;; Bytes 2-5 get the load address, 6-9 the execution address, 10-13 the length and 14-17 the attributes, which are
;; <LOCKED_ATTRIBUTE> for a locked file and 0 otherwise. An address whose top bits are both set (a file for the I/O
;; processor) gets &FFFF as its top two bytes.
;; In: DFS_BLOCK = the control block, Y = the file's offset in the catalogue
;; Keeps: A, X, Y
GET_FILE_INFO:
    jsr SAVE_REGISTERS
    tya
    pha
    tax
    ldy #$12
    lda #$00
GET_FILE_INFO_CLEAR:
    dey
    sta (DFS_BLOCK),y
    cpy #$02
    bne GET_FILE_INFO_CLEAR
GET_FILE_INFO_ADDRESSES:
    jsr COPY_INFO_WORD              ; the low two bytes of each address and the length
    iny
    iny
    cpy #$0E
    bne GET_FILE_INFO_ADDRESSES
    pla
    tax
    lda CATALOGUE_NAMES+8+NAME_LENGTH,x     ; the directory, with the lock in bit 7
    bpl GET_FILE_INFO_TOP_BITS
    lda #LOCKED_ATTRIBUTE
    sta (DFS_BLOCK),y               ; Y is 14, the attributes
GET_FILE_INFO_TOP_BITS:
    lda CATALOGUE_INFO+8+6,x        ; the top bits
    ldy #$04
    jsr GET_FILE_INFO_HIGH_BITS     ; bits 2-3, the load address's
    ldy #$0C
    lsr a
    lsr a
    pha
    and #$03
    sta (DFS_BLOCK),y               ; bits 4-5, the length's
    pla
    ldy #$08                        ; bits 6-7, the execution address's
;; Stores the low two bits of A, shifted right two first, as the third byte of an address in the control block, with
;; &FFFF as its top two bytes if both bits are set.
;; In: A = the bits, in bits 2-3, Y = the offset of the address's third byte
;; Out: A = A shifted right two bits
GET_FILE_INFO_HIGH_BITS:
    lsr a
    lsr a
    pha
    and #$03
    sta (DFS_BLOCK),y
    cmp #$03
    bne GET_FILE_INFO_DONE
    lda #$FF
    sta (DFS_BLOCK),y
    iny
    sta (DFS_BLOCK),y
GET_FILE_INFO_DONE:
    pla
    rts

;; Copies two bytes of a file's catalogue information to the control block at DFS_BLOCK.
;; In: X = their offset from CATALOGUE_INFO+8, Y = their offset in the block
;; Out: X = X + 2, Y = Y + 2
COPY_INFO_WORD:
    jsr COPY_INFO_BYTE
;; Copies one byte of a file's catalogue information to the control block at DFS_BLOCK.
;; In: X = its offset from CATALOGUE_INFO+8, Y = its offset in the block
;; Out: X = X + 1, Y = Y + 1
COPY_INFO_BYTE:
    lda CATALOGUE_INFO+8,x
    sta (DFS_BLOCK),y
    inx
    iny
    rts

;; Moves the inline routines' pointer on to the next byte.
;; In: DFS_INLINE_POINTER = the byte before
;; Keeps: A, X, Y
NEXT_INLINE_BYTE:
    inc DFS_INLINE_POINTER
    bne NEXT_INLINE_BYTE_DONE
    inc DFS_INLINE_POINTER+1
NEXT_INLINE_BYTE_DONE:
    rts

;; Keeps A, X and Y for the routine that calls it: they are put back when that routine returns.
;;
;; The routine copies its own return address and the three registers below a new frame on the stack, with a return
;; address of <RESTORE_REGISTERS> under them. So when the caller returns, it returns to RESTORE_REGISTERS, which pulls
;; the registers and returns to the caller's caller. The flags are not kept, so the caller can return a result in
;; carry. The stack holds five more bytes while the caller runs.
;; Keeps: A, X, Y
;; See: <SAVE_X_Y>
SAVE_REGISTERS:
    pha
    txa
    pha
    tya
    pha
    lda #>(RESTORE_REGISTERS-1)
    pha
    lda #<(RESTORE_REGISTERS-1)
    pha
;; Inserts the frame for SAVE_REGISTERS and SAVE_X_Y: copies the return address and the three registers above it,
;; then moves those five bytes and the two above them down by two, over the caller's return address.
SAVE_REGISTERS_INSERT:
    ldy #$05
SAVE_REGISTERS_COPY:
    tsx
    lda STACK+7,x
    pha
    dey
    bne SAVE_REGISTERS_COPY
    ldy #$0A
SAVE_REGISTERS_MOVE:
    lda STACK+9,x
    sta STACK+11,x
    dex
    dey
    bne SAVE_REGISTERS_MOVE
    pla
    pla
;; Pulls Y, X and A, then returns: where the routines that called <SAVE_REGISTERS> return to.
RESTORE_REGISTERS:
    pla
    tay
    pla
    tax
    pla
    rts

;; Keeps X and Y for the routine that calls it, putting them back when it returns, with the A it returns.
;;
;; As <SAVE_REGISTERS> does, but the return address it leaves under the registers is its own, so that on the caller's
;; return it stores A over the A it kept before restoring them.
;; Keeps: A, X, Y
SAVE_X_Y:
    pha
    txa
    pha
    tya
    pha
    jsr SAVE_REGISTERS_INSERT
    tsx                             ; the caller has returned here
    sta STACK+3,x                   ; return its A
    jmp RESTORE_REGISTERS

; ---------------------------------------------------------------------------------------------------------------------
; *CAT
; ---------------------------------------------------------------------------------------------------------------------

;; *CAT (OSFSC 5): prints the title and options of a disc, then the names of its files.
;;
;; The heading gives the disc's title and, in brackets, its sequence number; the drive; the boot option set by
;; *OPT 4, by number and name; and the current directory and library. The files follow two to a line, sorted by
;; directory and then name: first those in the current directory, without their directory, then, after a blank
;; line, the rest.
;;
;; To sort, the routine clears the directory letter of each file in the current directory, which puts them first, and
;; sets bit 7 of each file's first character once it is printed. That spoils the catalogue in memory, so it then
;; forgets it (<DFS_CATALOGUE_DRIVE>) for the next command to read it again.
;; In: X/Y = the rest of the command line, which can give a drive
;; Uses: A, X, Y
DFS_CAT:
    jsr SET_TEXT_POINTER
    jsr READ_DRIVE_AND_CATALOGUE                       ; read the drive, if any, and its catalogue
    ldy #$FF
    sty CAT_COLUMN                  ; a new line before the first file
    iny
    sty CAT_LAST_DIRECTORY
DFS_CAT_TITLE:
    lda CATALOGUE_NAMES,y           ; the title's first eight characters
    cpy #$08
    bcc DFS_CAT_TITLE_PRINT
    lda CATALOGUE_INFO-8,y          ; and its last four
DFS_CAT_TITLE_PRINT:
    jsr PRINT_CHARACTER
    iny
    cpy #$0C
    bne DFS_CAT_TITLE
    jsr DFS_PRINT_INLINE
    .byte " ("
    lda CATALOGUE_SEQUENCE          ; ends the text (bit 7 set)
    jsr PRINT_HEX_BYTE
    jsr DFS_PRINT_INLINE
    .byte ")",$0D,"Drive "
    lda DFS_CURRENT_DRIVE           ; ends the text (bit 7 set)
    jsr PRINT_HEX_DIGIT
    ldy #13
    jsr PRINT_SPACES
    jsr DFS_PRINT_INLINE
    .byte "Option "
    lda CATALOGUE_OPTION            ; ends the text (bit 7 set)
    jsr SHIFT_RIGHT_4               ; the boot option
    pha
    jsr PRINT_HEX_DIGIT
    jsr DFS_PRINT_INLINE
    .byte " ("
    ldy #$03                        ; ends the text (bit 7 set)
    pla
    asl a
    asl a
    tax
DFS_CAT_OPTION_NAME:
    lda BOOT_OPTION_NAMES,x
    jsr PRINT_CHARACTER
    inx
    dey
    bpl DFS_CAT_OPTION_NAME
    jsr DFS_PRINT_INLINE
    .byte ")",$0D,"Dir. :"
    lda DFS_DEFAULT_DRIVE           ; ends the text (bit 7 set)
    jsr PRINT_DIGIT_AND_DOT
    lda DFS_DEFAULT_DIRECTORY
    jsr PRINT_CHARACTER
    ldy #11
    jsr PRINT_SPACES
    jsr DFS_PRINT_INLINE
    .byte "Lib. :"
    lda DFS_LIBRARY_DRIVE           ; ends the text (bit 7 set)
    jsr PRINT_DIGIT_AND_DOT
    lda DFS_LIBRARY
    jsr PRINT_CHARACTER
    jsr DFS_PRINT_NEWLINE                       ; a new line
    ldy #$00
DFS_CAT_MARK_CURRENT:
    cpy CATALOGUE_SIZE
    bcs DFS_CAT_NEXT_FILE
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y
    eor DFS_DEFAULT_DIRECTORY
    and #$5F                        ; the same letter, in either case, locked or not
    bne DFS_CAT_MARK_NEXT
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y
    and #CATALOGUE_LOCKED           ; the current directory: keep only the lock
    sta CATALOGUE_NAMES+8+NAME_LENGTH,y
DFS_CAT_MARK_NEXT:
    jsr NEXT_ENTRY
    bcc DFS_CAT_MARK_CURRENT
DFS_CAT_NEXT_FILE:
    ldy #$00
    jsr FIND_UNPRINTED
    bcc DFS_CAT_CANDIDATE
    lda #$FF                        ; all printed
    sta DFS_CATALOGUE_DRIVE
    jmp DFS_PRINT_NEWLINE                       ; a new line

;; Finds the next file *CAT has yet to print, from the one after Y.
;; In: Y = the offset of a file in the catalogue
;; Out: carry = clear if found, Y = its offset
;; Entry: FIND_UNPRINTED = from Y itself
FIND_UNPRINTED_NEXT:
    jsr NEXT_ENTRY
FIND_UNPRINTED:
    cpy CATALOGUE_SIZE
    bcs FIND_UNPRINTED_DONE
    lda CATALOGUE_NAMES+8,y
    bmi FIND_UNPRINTED_NEXT         ; printed already
FIND_UNPRINTED_DONE:
    rts

    ; Find the unprinted file that sorts first: try each in turn against the best so far.
DFS_CAT_CANDIDATE:
    sty CAT_CANDIDATE
    ldx #$00
DFS_CAT_CANDIDATE_COPY:
    lda CATALOGUE_NAMES+8,y
    jsr FOLD_CASE
    sta CAT_SORT_KEY,x
    iny
    inx
    cpx #CATALOGUE_ENTRY_SIZE
    bne DFS_CAT_CANDIDATE_COPY
DFS_CAT_COMPARE:
    jsr FIND_UNPRINTED
    bcs DFS_CAT_PRINT_FILE
    sec
    ldx #NAME_LENGTH - 1
DFS_CAT_COMPARE_LOOP:
    lda CATALOGUE_NAMES+8+NAME_LENGTH-1,y   ; subtract the names, the last character first
    jsr FOLD_CASE
    sbc CAT_SORT_KEY,x
    dey
    dex
    bpl DFS_CAT_COMPARE_LOOP
    jsr ADD_7_TO_Y
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y     ; then the directories
    jsr FOLD_CASE
    sbc CAT_SORT_KEY+NAME_LENGTH
    bcc DFS_CAT_CANDIDATE           ; this one sorts first
    jsr NEXT_ENTRY
    bcs DFS_CAT_COMPARE             ; always taken
DFS_CAT_PRINT_FILE:
    ldy CAT_CANDIDATE
    lda CATALOGUE_NAMES+8,y
    ora #$80                        ; mark it printed
    sta CATALOGUE_NAMES+8,y
    lda CAT_SORT_KEY+NAME_LENGTH
    cmp CAT_LAST_DIRECTORY
    beq DFS_CAT_COLUMN
    ldx CAT_LAST_DIRECTORY
    sta CAT_LAST_DIRECTORY
    bne DFS_CAT_COLUMN              ; not the end of the current directory's files
    jsr DFS_PRINT_NEWLINE                       ; a blank line after them
DFS_CAT_NEW_LINE:
    jsr DFS_PRINT_NEWLINE                       ; a new line
    ldy #$FF
    bne DFS_CAT_PRINT_NAME          ; always taken
DFS_CAT_COLUMN:
    ldy CAT_COLUMN
    bne DFS_CAT_NEW_LINE
    ldy #$05                        ; the right-hand column
    jsr PRINT_SPACES
DFS_CAT_PRINT_NAME:
    iny
    sty CAT_COLUMN
    ldy CAT_CANDIDATE
    jsr DFS_PRINT_TWO_SPACES                       ; two spaces
    jsr PRINT_FILE_NAME
    jmp DFS_CAT_NEXT_FILE

;; The names of the four boot options *OPT 4 sets, four characters each, indexed by four times the option. *CAT
;; prints all four characters, so the shorter names are padded with zeros, which print nothing.
BOOT_OPTION_NAMES:
    .byte "off",0                   ; 0: nothing
    .byte "LOAD"                    ; 1: *LOAD $.!BOOT
    .byte "RUN",0                   ; 2: *RUN $.!BOOT
    .byte "EXEC"                    ; 3: *EXEC $.!BOOT

;; Tests whether the file being saved fits in the gap after a file on the disc.
;;
;; The catalogue keeps its files in order of start sector, the highest first, so the file before this one in the
;; catalogue is the next one on the disc; before the first file, the bytes at that place are the disc's size.
;; In: Y = the file's offset in the catalogue, DFS_LENGTH and DFS_LENGTH_HIGH = the length of the file being saved
;; Out: carry = set if it fits, DFS_TOP_BITS/DFS_START_SECTOR = the first sector after the file
;; Uses: A, X
;; Entry: CHECK_GAP = with the first free sector already in DFS_TOP_BITS (bits 0-1) and DFS_START_SECTOR
CHECK_GAP_AFTER_FILE:
    lda CATALOGUE_INFO+8+6,y        ; the top bits
    jsr BITS_4_5                    ; the length's
    sta DFS_TOP_BITS
    clc
    lda #$FF
    adc CATALOGUE_INFO+8+4,y        ; carry is set if the length's low byte isn't zero: a part sector
    lda CATALOGUE_INFO+8+7,y        ; the start sector
    adc CATALOGUE_INFO+8+5,y        ; plus the sectors the file takes
    sta DFS_START_SECTOR
    lda CATALOGUE_INFO+8+6,y
    and #$03
    adc DFS_TOP_BITS
    sta DFS_TOP_BITS
CHECK_GAP:
    sec
    lda CATALOGUE_INFO+7,y          ; the start sector of the file before, or the disc's size
    sbc DFS_START_SECTOR
    pha
    lda CATALOGUE_INFO+6,y
    and #$03
    sbc DFS_TOP_BITS
    tax
    lda #$00
    cmp DFS_LENGTH                  ; carry is clear if there is a part sector
    pla
    sbc DFS_LENGTH+1
    txa
    sbc DFS_LENGTH_HIGH
;; Does nothing: the routine for a command no table entry matches on service call 4, and for OSGBPB 0.
DFS_DO_NOTHING:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The * command tables
; ---------------------------------------------------------------------------------------------------------------------

;; Lays out a command in a command table: its name, the address of its routine less one, high byte first, and its
;; syntax.
;;
;; The routine's high byte has bit 7 set, as every routine is in the ROM at &8000-&BFFF, and so ends the name. The
;; address is less one because <SCAN_COMMAND_TABLE> pushes it and returns to it.
;; Parameters:
;;   name = the command's name, in capitals
;;   routine = the routine that carries it out
;;   first = the first parameter's syntax string (SYNTAX_FSP and the rest), for help and the Syntax error
;;   second = the second parameter's, if any
.macro DFS_COMMAND name, routine, first, second
.if .paramcount > 3
    .byte name, >(routine-1), <(routine-1), first | second << 4
.else
    .byte name, >(routine-1), <(routine-1), first
.endif
.endmacro

;; Ends a command table with the address, less one, of the routine for a name that no entry matches.
;; Parameters:
;;   routine = that routine
.macro DFS_COMMAND_DEFAULT routine
    .byte >(routine-1), <(routine-1)
.endmacro

;; The DFS's own commands, which it looks up in <SCAN_COMMAND_TABLE> when OSFSC 3 gives it a command the paged ROMs
;; did not claim. A command it doesn't know is a file to run from the library: <RUN_FILE>.
;;
;; *HELP DFS lists these commands with their syntax (HELP_DFS).
DFS_COMMAND_TABLE:
    DFS_COMMAND "ACCESS", ACCESS_COMMAND, SYNTAX_AFSP, SYNTAX_L
    DFS_COMMAND "BACKUP", BACKUP_COMMAND, SYNTAX_SOURCE_DEST
    DFS_COMMAND "COMPACT", COMPACT_COMMAND, SYNTAX_OPTIONAL_DRIVE
    DFS_COMMAND "COPY", COPY_COMMAND, SYNTAX_SOURCE_DEST, SYNTAX_AFSP
    DFS_COMMAND "DELETE", DELETE_COMMAND, SYNTAX_FSP
    DFS_COMMAND "DESTROY", DESTROY_COMMAND, SYNTAX_AFSP
    DFS_COMMAND "DIR", DIR_COMMAND, SYNTAX_DIR
    DFS_COMMAND "DRIVE", DRIVE_COMMAND, SYNTAX_DRIVE
    DFS_COMMAND "ENABLE", ENABLE_COMMAND, SYNTAX_NONE
    DFS_COMMAND "INFO", INFO_COMMAND, SYNTAX_AFSP
    DFS_COMMAND "LIB", LIB_COMMAND, SYNTAX_DIR
    DFS_COMMAND "RENAME", RENAME_COMMAND, SYNTAX_OLD_NEW
    DFS_COMMAND "TITLE", TITLE_COMMAND, SYNTAX_TITLE
    DFS_COMMAND "WIPE", WIPE_COMMAND, SYNTAX_AFSP
    DFS_COMMAND_DEFAULT RUN_FILE

;; The utility commands, which the DFS offers on service call 4, whichever filing system is in use. *DISC and *DISK
;; select the DFS. A command that isn't here is left for other ROMs: <DFS_DO_NOTHING>.
;;
;; *HELP UTILS lists these commands with their syntax (HELP_UTILS).
UTILITY_COMMAND_TABLE:
    DFS_COMMAND "BUILD", BUILD_COMMAND, SYNTAX_FSP
    DFS_COMMAND "DISC", DISC_COMMAND, SYNTAX_NONE
    DFS_COMMAND "DUMP", DUMP_COMMAND, SYNTAX_FSP
    DFS_COMMAND "LIST", LIST_COMMAND, SYNTAX_FSP
    DFS_COMMAND "TYPE", TYPE_COMMAND, SYNTAX_FSP
    DFS_COMMAND "DISK", DISC_COMMAND, SYNTAX_NONE
    DFS_COMMAND_DEFAULT DFS_DO_NOTHING

;; The *HELP topics the DFS answers on service call 9: DFS and UTILS. A word that is neither goes to HELP_OTHER_TOPIC,
;; which looks at the next word.
HELP_TOPIC_TABLE:
    DFS_COMMAND "DFS", HELP_DFS, SYNTAX_NONE
    DFS_COMMAND "UTILS", HELP_UTILS, SYNTAX_NONE
    DFS_COMMAND_DEFAULT HELP_OTHER_TOPIC

    ; The other parts start SCAN_COMMAND_TABLE with X three less than a table's offset from DFS_COMMAND_TABLE.
    .assert UTILITY_COMMAND_TABLE - DFS_COMMAND_TABLE = $71 + 3, "Service call 4 scans the utility commands."
    .assert HELP_TOPIC_TABLE - DFS_COMMAND_TABLE = $9E + 3, "*HELP scans the help topics."

;; OSFSC 3: looks a command the paged ROMs did not claim up in <DFS_COMMAND_TABLE> and runs it.
;; In: X/Y = the command line
DFS_UNRECOGNISED_COMMAND:
    jsr SET_TEXT_POINTER
    ldx #$100 - 3                   ; three before the first table
;; Looks the command at (TEXT_POINTER),Y up in a command table and runs its routine, or the table's default routine.
;;
;; The command's name may be in either case, and may be cut short with a full stop. A name matches only if the
;; character after it is not a letter, so `*INFOX` is not *INFO. The routine is entered by pushing its address and
;; returning to it, with <COMMAND_NAME_OFFSET> set for the syntax error (REQUIRE_ARGUMENT).
;; In: TEXT_POINTER = the command line, Y = the command's offset in it, X = the table's offset from
;;   DFS_COMMAND_TABLE, less three
;; Out: Y = for the routine, the offset after the command's name (or its full stop), or of the name for the default
;;   routine, COMMAND_NAME_OFFSET = the command's offset in the table, less one
SCAN_COMMAND_TABLE:
    tya
    pha
SCAN_NEXT_COMMAND:
    inx                             ; past the address and the syntax byte
    inx
    pla
    pha
    tay
    jsr START_STRING
    inx
    lda DFS_COMMAND_TABLE,x
    bmi SCAN_COMMAND_FOUND          ; the end of the table: the default routine
    dex
    dey
    stx COMMAND_NAME_OFFSET
SCAN_COMMAND_COMPARE:
    inx
    iny
    lda DFS_COMMAND_TABLE,x
    bmi SCAN_COMMAND_END            ; the end of the name: it matches so far
    eor (TEXT_POINTER),y
    and #$5F                        ; in either case
    beq SCAN_COMMAND_COMPARE
    dex
SCAN_SKIP_NAME:
    inx
    lda DFS_COMMAND_TABLE,x
    bpl SCAN_SKIP_NAME
    lda (TEXT_POINTER),y
    cmp #'.'                        ; a short form?
    bne SCAN_NEXT_COMMAND
    iny
    bcs SCAN_COMMAND_FOUND          ; always taken: the full stop left carry set
SCAN_COMMAND_END:
    lda (TEXT_POINTER),y
    jsr CHECK_LETTER
    bcc SCAN_NEXT_COMMAND           ; the command line's word is longer
SCAN_COMMAND_FOUND:
    pla
    lda DFS_COMMAND_TABLE,x
    pha
    lda DFS_COMMAND_TABLE+1,x
    pha
    rts

;; Points TEXT_POINTER at the string X/Y gives, from its start.
;; In: X/Y = the string
;; Out: TEXT_POINTER = the string, Y = 0
;; Keeps: A, X
SET_TEXT_POINTER:
    stx TEXT_POINTER
    sty TEXT_POINTER+1
    ldy #$00
    rts

;; Starts reading a string with GSINIT, where a space ends a string not in quotes.
;; In: TEXT_POINTER = the text, Y = the offset to start at
;; Out: Y = the offset of the first character after any spaces, zero = set if it is the end of the line
;; Uses: A
START_STRING:
    clc
    jmp GSINIT

; ---------------------------------------------------------------------------------------------------------------------
; The commands
; ---------------------------------------------------------------------------------------------------------------------

;; *WIPE: asks about each unlocked file that matches an ambiguous file specification, deleting those answered Y.
;;
;; Each file's name is printed with " : ", and Y deletes it at once, writing the catalogue back. Raises "Not found"
;; (&D6) if no file matches.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
WIPE_COMMAND:
    jsr ALLOW_WILDCARDS                       ; allow wildcards
    jsr REQUIRE_ARGUMENT                       ; a Syntax error if there is no parameter
    jsr FIND_NAME
WIPE_COMMAND_LOOP:
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y
    bmi WIPE_COMMAND_NEXT           ; locked
    jsr PRINT_FILE_NAME
    jsr DFS_PRINT_INLINE
    .byte " : "
    nop                             ; ends the text (bit 7 set)
    jsr ASK_YES_NO                       ; read Y or N
    bne WIPE_COMMAND_NEW_LINE
    jsr CHECK_DISC_UNCHANGED                       ; check that the disc has not been changed
    jsr DELETE_FOUND_ENTRY
    jsr WRITE_CATALOGUE                       ; write the catalogue
WIPE_COMMAND_NEW_LINE:
    jsr DFS_PRINT_NEWLINE                       ; a new line
WIPE_COMMAND_NEXT:
    jsr FIND_NEXT
    bcs WIPE_COMMAND_LOOP
    rts

;; *DELETE: deletes a file.
;;
;; The name may not have wildcards. Raises "Not found" (&D6), "Locked" (&C3) or "Open" (&C2) if the file can't be
;; deleted.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
DELETE_COMMAND:
    jsr DISABLE_WILDCARDS                       ; no wildcards
    jsr REQUIRE_ARGUMENT                       ; a Syntax error if there is no parameter
    jsr FIND_NAME
    jsr PRINT_INFO_IF_ON
    jsr DELETE_ENTRY
    jmp WRITE_CATALOGUE                       ; write the catalogue

;; *DESTROY: lists the unlocked files that match an ambiguous file specification, then deletes them all if told to.
;;
;; It asks "Go (Y/N) ?" after the list, and deletes on Y. Unless *ENABLE came just before, it asks first as well
;; (CONFIRM_UNLESS_ENABLED). It prints "Deleted" at the end. Raises "Not found" (&D6) if no file matches.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
DESTROY_COMMAND:
    jsr CONFIRM_UNLESS_ENABLED                       ; check for *ENABLE, or ask
    jsr ALLOW_WILDCARDS                       ; allow wildcards
    jsr REQUIRE_ARGUMENT                       ; a Syntax error if there is no parameter
    jsr FIND_NAME
DESTROY_COMMAND_LIST:
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y
    bmi DESTROY_COMMAND_LIST_NEXT   ; locked
    jsr PRINT_FILE_NAME
    jsr DFS_PRINT_NEWLINE                       ; a new line
DESTROY_COMMAND_LIST_NEXT:
    jsr FIND_NEXT
    bcs DESTROY_COMMAND_LIST
    jsr ASK_GO                       ; "Go (Y/N) ?"
    beq DESTROY_COMMAND_DELETE
    jmp DFS_PRINT_NEWLINE                       ; not Y: a new line, and stop
DESTROY_COMMAND_DELETE:
    jsr CHECK_DISC_UNCHANGED                       ; check that the disc has not been changed
    jsr FIND_FIRST
DESTROY_COMMAND_LOOP:
    lda CATALOGUE_NAMES+8+NAME_LENGTH,y
    bmi DESTROY_COMMAND_NEXT        ; locked
    jsr DELETE_FOUND_ENTRY
DESTROY_COMMAND_NEXT:
    jsr FIND_NEXT
    bcs DESTROY_COMMAND_LOOP
    jsr WRITE_CATALOGUE                       ; write the catalogue
    jsr DFS_PRINT_INLINE
    .byte $0D,"Deleted",$0D
    ; The INY that ends the text (bit 7 set) is NEXT_ENTRY, which returns from the command.

;; Adds 8 to Y: steps on to the next catalogue entry.
;; Keeps: A, X, carry
NEXT_ENTRY:
    iny
;; Adds 7 to Y.
;; Keeps: A, X, carry
ADD_7_TO_Y:
    iny
    iny
    iny
    iny
    iny
    iny
    iny
    rts

;; Deletes the file a search found, and steps the search back so that <FIND_NEXT> looks next at the file that has
;; taken its place.
;; In: Y = the file's offset in the catalogue, DFS_ENTRY_POINTER = the search's place
;; Out: Y = the search's place, less 8
DELETE_FOUND_ENTRY:
    jsr DELETE_ENTRY
    ldy DFS_ENTRY_POINTER
    jsr PREVIOUS_ENTRY
    sty DFS_ENTRY_POINTER
    rts

;; *DRIVE: sets the current drive, and selects it.
;;
;; Raises "Bad drive" (&CD) for anything but 0-3.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
DRIVE_COMMAND:
    jsr REQUIRE_ARGUMENT                       ; a Syntax error if there is no parameter
    jsr READ_DRIVE_NUMBER                       ; read the drive number
    sta DFS_DEFAULT_DRIVE
;; Makes a drive the one being used, once the 8271 has finished what it is doing.
;; In: A = the drive, in bits 0-1
;; Out: A = the drive, DFS_CURRENT_DRIVE = the drive
;; Keeps: X, Y
SET_DRIVE:
    jsr FDC_WAIT_IDLE                       ; wait until the 8271 isn't busy
    and #DFS_DRIVE_MASK
    sta DFS_CURRENT_DRIVE
    rts

;; OSFILE &FF: loads a file, and fills in the control block with its information.
;;
;; The file goes to its own load address if the execution address's low byte in the block (<DFS_EXEC>) is nonzero,
;; and to the block's load address otherwise. Raises "Not found" (&D6) if there is no such file.
;; In: DFS_NAME_POINTER = the file's name, DFS_LOAD and DFS_LOAD_HIGH = the block's load address,
;;   DFS_EXEC = the block's execution address, DFS_BLOCK = the control block
;; Out: A = 1, a file
DFS_LOAD_FILE:
    jsr FIND_BLOCK_NAME
    jsr RESTORE_OSFILE_POINTER                       ; DFS_BLOCK = the control block again
    jsr GET_FILE_INFO
;; Loads the file a search found.
;;
;; If <DFS_EXEC> is nonzero, the file goes to its own load address; otherwise to the address already in
;; <DFS_LOAD> and <DFS_LOAD_HIGH>. The file's information is printed if *OPT 1 is on. Falls through to
;; READ_FILE_DATA.
;; In: Y = the file's offset in the catalogue
;; Out: A = 1
LOAD_FILE:
    sty DFS_NAME_POINTER            ; keep the file's offset
    ldx #$00
    lda DFS_EXEC
    bne LOAD_FILE_OWN_ADDRESS
    iny                             ; keep the load address given
    iny
    ldx #$02
    bne LOAD_FILE_COPY              ; always taken
LOAD_FILE_OWN_ADDRESS:
    lda CATALOGUE_INFO+8+6,y        ; the top bits
    sta DFS_TOP_BITS
    jsr UNPACK_LOAD_HIGH                       ; the load address's top two bytes
LOAD_FILE_COPY:
    lda CATALOGUE_INFO+8,y          ; the load address, execution address, length, top bits and start sector
    sta DFS_LOAD,x
    iny
    inx
    cpx #$08
    bne LOAD_FILE_COPY
    jsr UNPACK_EXEC_HIGH                       ; the execution address's top two bytes
    ldy DFS_NAME_POINTER
    jsr PRINT_INFO_IF_ON
;; Reads a file's data from the disc: the length in <DFS_LENGTH> from its start sector to <DFS_LOAD>.
;;
;; The data goes to the second processor if the load address's top bytes say so and there is a Tube.
;; In: DFS_LOAD and DFS_LOAD_HIGH = the address, DFS_LENGTH and DFS_TOP_BITS = the length,
;;   DFS_TOP_BITS and DFS_START_SECTOR = the start sector, DFS_CURRENT_DRIVE = the drive
;; Out: A = 1
READ_FILE_DATA:
    jsr PREPARE_READ                       ; set up a read, claiming the Tube if it is needed
    bne TRANSFER_FILE_DATA          ; always taken

;; OSFILE 0: saves a block of memory as a file, and fills in the control block with its information.
;;
;; Any file of the name is deleted first. Raises "Cat full" (&BE) or "Disk full" (&C6) if there is no room, and
;; "Locked" (&C3) if the old file is locked.
;; In: DFS_NAME_POINTER = the file's name, the rest of the control block copied by <COPY_BLOCK_ADDRESS>,
;;   DFS_BLOCK = the control block
;; Out: A = 1
DFS_SAVE_FILE:
    jsr CREATE_FILE                       ; make the catalogue entry
    jsr RESTORE_OSFILE_POINTER                       ; DFS_BLOCK = the control block again
    jsr GET_FILE_INFO
;; Writes a file's data to the disc: the length in <DFS_LENGTH> from <DFS_LOAD> to its start sector.
;; In: DFS_LOAD and DFS_LOAD_HIGH = the address, DFS_LENGTH and DFS_TOP_BITS = the length,
;;   DFS_TOP_BITS and DFS_START_SECTOR = the start sector, DFS_CURRENT_DRIVE = the drive
;; Out: A = 1
WRITE_FILE_DATA:
    jsr PREPARE_WRITE                       ; set up a write, claiming the Tube if it is needed
;; Carries out the read or write that is set up, then releases the NMI and the Tube.
;; Out: A = 1
TRANSFER_FILE_DATA:
    jsr SET_UP_FILE_TRANSFER
    jsr ISSUE_TRANSFER                       ; transfer
    lda #$01
    jsr WAIT_AND_RELEASE_NMI                       ; wait for the 8271 to finish, and release the NMI
    pha
    lda DFS_TUBE_TRANSFER
    beq DFS_RELEASE_TUBE_DONE
DFS_RELEASE_TUBE_NOW:
    lda #DFS_TUBE_RELEASE
    jsr TUBE_ENTRY_TRANSFER                       ; the Tube host's claim and release entry, &0406
    pla
    rts

;; Releases the NMI, if the DFS claimed it, and the Tube, if there is one.
;; Uses: X, Y (from OSBYTE &EA)
;; Keeps: A
RELEASE_NMI_AND_TUBE:
    jsr RELEASE_NMI
;; Releases the Tube, if there is one, for the DFS.
;; Uses: X, Y (from OSBYTE &EA)
;; Keeps: A
DFS_RELEASE_TUBE:
    pha
    lda #OSBYTE_TUBE_PRESENCE
    jsr READ_OS_VARIABLE
    txa
    bne DFS_RELEASE_TUBE_NOW        ; a Tube
DFS_RELEASE_TUBE_DONE:
    pla
    rts

;; *RUN (OSFSC 4) and */ (OSFSC 2): loads a file and runs it.
;; In: X/Y = the command line, from the file's name
DFS_RUN:
    jsr SET_TEXT_POINTER
;; Loads a file and runs it: from the current directory, or else from the library.
;;
;; This is also how a command the DFS doesn't know runs, as the default routine of <DFS_COMMAND_TABLE>. The file loads
;; at its own address, and the address of the rest of the command line is kept in <DFS_COMMAND_TAIL>, for OSARGS to
;; give. If its execution address is in the I/O processor, or there is no Tube, it is called with A = 1; otherwise
;; the second processor is started at it.
;;
;; Raises "Bad command" (&FE) if the file is in neither place.
;; In: TEXT_POINTER = the command line, Y = the name's offset in it
RUN_FILE:
    jsr SET_NAME_POINTER
    sty DFS_COMMAND_TAIL+1          ; keep Y for a moment
    jsr READ_BLOCK_NAME
    sty DFS_COMMAND_TAIL            ; the offset after the name
    jsr FIND_FIRST
    bcs RUN_FILE_FOUND
    ldy DFS_COMMAND_TAIL+1
    lda DFS_LIBRARY
    sta DFS_NAME_DIRECTORY
    lda DFS_LIBRARY_DRIVE
    jsr SET_DRIVE
    jsr READ_NAME_AT_POINTER        ; the name again, in the library
    jsr FIND_FIRST
    bcs RUN_FILE_FOUND
    jsr BAD_ERROR
    .byte DFS_ERROR_BAD_COMMAND
    .byte "command",0
RUN_FILE_FOUND:
    jsr LOAD_FILE
    clc
    lda DFS_COMMAND_TAIL
    tay
    adc TEXT_POINTER
    sta DFS_COMMAND_TAIL
    lda TEXT_POINTER+1
    adc #$00
    sta DFS_COMMAND_TAIL+1
    lda DFS_EXEC_HIGH
    and DFS_EXEC_HIGH+1
    ora DFS_NO_TUBE
    cmp #$FF
    beq RUN_FILE_HERE               ; an I/O processor address, or no Tube
    lda DFS_EXEC                    ; the execution address, as four bytes at DFS_LOAD_HIGH
    sta DFS_LOAD_HIGH
    lda DFS_EXEC+1
    sta DFS_LOAD_HIGH+1
    jsr DFS_CLAIM_TUBE                       ; claim the Tube
    ldx #<DFS_LOAD_HIGH
    ldy #>DFS_LOAD_HIGH
    lda #DFS_TUBE_EXECUTE
    jmp TUBE_ENTRY_TRANSFER                       ; the Tube host's entry, &0406: start the second processor
RUN_FILE_HERE:
    lda #$01
    jmp (DFS_EXEC)

;; Sets up to read a file name from the command line, for a file that loads at its own address.
;; In: TEXT_POINTER = the command line
;; Out: DFS_NAME_POINTER = TEXT_POINTER, DFS_EXEC = &FF
;; Keeps: X, Y
SET_NAME_POINTER:
    lda #$FF
    sta DFS_EXEC                    ; load at the file's own address
    lda TEXT_POINTER
    sta DFS_NAME_POINTER
    lda TEXT_POINTER+1
    sta DFS_NAME_POINTER+1
    rts

;; *DIR: sets the current directory, and the current drive if one is given.
;;
;; Raises "Bad dir" (&CE) or "Bad drive" (&CD) for a bad parameter.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
DIR_COMMAND:
    ldx #$00                        ; the current directory
    beq SET_DIRECTORY               ; always taken

;; *LIB: sets the library's directory, and its drive if one is given.
;;
;; Raises "Bad dir" (&CE) or "Bad drive" (&CD) for a bad parameter.
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
LIB_COMMAND:
    ldx #DFS_LIBRARY - DFS_DEFAULT_DIRECTORY
;; Reads a directory and stores it, and its drive, as the current directory or the library.
;; In: X = 0 for the current directory, 2 for the library
SET_DIRECTORY:
    jsr READ_DIR_PARAMETER
    sta DFS_DEFAULT_DRIVE,x
    lda DFS_NAME_DIRECTORY
    sta DFS_DEFAULT_DIRECTORY,x
    rts

;; Saves the DFS's workspace in its private workspace: &1100-&11BF and &10C0-&10FF, in one page.
;;
;; The page holds &1100-&11BF at offsets 0-&BF and &10C0-&10FF at &C0-&FF. The service call handler
;; (DFS_SERVICE_HANDLER) calls this before another filing system or the NFS takes pages &0E-&11 over, and copies the
;; page back to start again.
;; Keeps: A, X, Y, DFS_BLOCK
SAVE_WORKSPACE:
    jsr SAVE_REGISTERS
    lda DFS_BLOCK
    pha
    lda DFS_BLOCK+1
    pha
    jsr POINT_AT_PRIVATE_WORKSPACE                       ; DFS_BLOCK = the private workspace
    ldy #$00
SAVE_WORKSPACE_LOOP:
    cpy #$C0
    bcc SAVE_WORKSPACE_CHANNELS
    lda DFS_WORKSPACE,y
    bcs SAVE_WORKSPACE_STORE        ; always taken
SAVE_WORKSPACE_CHANNELS:
    lda DFS_CHANNELS,y
SAVE_WORKSPACE_STORE:
    sta (DFS_BLOCK),y
    dey
    bne SAVE_WORKSPACE_LOOP
    pla
    sta DFS_BLOCK+1
    pla
    sta DFS_BLOCK
    rts

;; Reads *DIR's or *LIB's parameter: a directory, `:drive.directory`, or a drive alone, `:drive`.
;;
;; With no parameter, the directory is the current one and the drive 0. A directory alone keeps the current drive.
;; Raises "Bad dir" (&CE) for more than one character, or "Bad drive" (&CD).
;; In: TEXT_POINTER = the command line, Y = the offset after the command's name
;; Out: A = the drive, DFS_NAME_DIRECTORY = the directory
;; Keeps: X
READ_DIR_PARAMETER:
    lda DFS_DEFAULT_DIRECTORY
    sta DFS_NAME_DIRECTORY
    jsr START_STRING
    bne DIR_PARAMETER_DRIVE
    lda #$00                        ; no parameter: drive 0
    jsr SET_DRIVE
    beq DIR_PARAMETER_DONE          ; always taken
DIR_PARAMETER_DRIVE:
    lda DFS_DEFAULT_DRIVE
    jsr SET_DRIVE
DIR_PARAMETER_LOOP:
    jsr READ_NAME_CHARACTER
    bcs BAD_DIR
    cmp #':'
    bne DIR_PARAMETER_LETTER
    jsr READ_DRIVE_NUMBER                       ; read the drive number
    jsr READ_NAME_CHARACTER
    bcs DIR_PARAMETER_DONE          ; a drive alone
    cmp #'.'
    beq DIR_PARAMETER_LOOP
;; Raises "Bad dir" (&CE).
BAD_DIR:
    jsr BAD_ERROR
    .byte DFS_ERROR_BAD_DIR
    .byte "dir",0
DIR_PARAMETER_LETTER:
    sta DFS_NAME_DIRECTORY
    jsr READ_NAME_CHARACTER
    bcc BAD_DIR                     ; more than one character
DIR_PARAMETER_DONE:
    lda DFS_CURRENT_DRIVE
    rts
