;; *EXEC: closes the *EXEC file, if there is one, then opens the named file as the new one.
;;
;; <CLOSE_EXEC> falls into it with no name. The escape acknowledgement and OSFSC 6 close the file that way.
;; In: X/Y = the file name, A = 0, zero = set when there is no name
;; Out: Y = the new file's handle, or Y as it came in when there is no name
;; Uses: A, OS_WORK+2
;; Errors: "File not found", from the OSFIND that opens the file
;; See: <EXEC_HANDLE>, <FILE_NOT_FOUND_ERROR>
STAR_EXEC:
    php
    sty OS_WORK+2
    ldy EXEC_HANDLE
    sta EXEC_HANDLE
    beq STAR_EXEC_OPEN
    jsr OSFIND                      ; close the old file
STAR_EXEC_OPEN:
    ldy OS_WORK+2
    plp
    beq STAR_EXEC_DONE
    lda #OSFIND_OPEN_INPUT
    jsr OSFIND
    tay
    beq FILE_NOT_FOUND_ERROR
    sta EXEC_HANDLE
STAR_EXEC_DONE:
    rts

;; Reads the input file's next block into <INPUT_BUFFER>, for OSBGET.
;;
;; It reads the next header for the file named in <CFS_INPUT_NAME>, then falls into <READ_INPUT_BLOCK>.
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: those of <READ_INPUT_BLOCK>
READ_NEXT_INPUT_BLOCK:
    ldx #<(CFS_INPUT_NAME - 1)
    jsr COPY_SEARCH_NAME
    jsr READ_HEADER
;; Reads the data of the block whose header has just been read into <INPUT_BUFFER>, as the input file's block
;; <CFS_NEXT_BLOCK>.
;;
;; A protected file is "Locked". On an error it finds the block again and retries, or aborts, as *OPT 2 says. It
;; keeps the block's length, flag and last byte for OSBGET, counts the block, and releases the cassette.
;; In: Y = nonzero to show "Loading"
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Locked", and the block errors
;; See: <LOAD_BLOCK>, <BGETV_DEFAULT>
READ_INPUT_BLOCK:
    lda CFS_BLOCK_FLAGS
    lsr a                           ; carry = protected
    bcc READ_INPUT_BLOCK_UNLOCKED
    jmp LOCKED_ERROR
READ_INPUT_BLOCK_UNLOCKED:
    lda CFS_NEXT_BLOCK
    sta CFS_WANTED_BLOCK
    lda CFS_NEXT_BLOCK+1
    sta CFS_WANTED_BLOCK+1
    lda #<INPUT_BUFFER              ; the data goes to &FFFF0A00
    sta CFS_DATA_ADDRESS
    lda #>INPUT_BUFFER
    sta CFS_DATA_ADDRESS+1
    lda #$FF
    sta CFS_DATA_ADDRESS+2
    sta CFS_DATA_ADDRESS+3
    jsr RECEIVE_DATA
    jsr LOAD_BLOCK
    bne READ_INPUT_BLOCK_RETRY
    lda INPUT_BUFFER+$FF
    sta CFS_LAST_CHARACTER
    jsr SET_NEXT_BLOCK
    stx CFS_NEXT_BLOCK
    sty CFS_NEXT_BLOCK+1
    ldx #$02                        ; the length and the flag
READ_INPUT_BLOCK_COPY:
    lda CFS_BLOCK_LENGTH,x
    sta CFS_BLOCK_SIZE,x
    dex
    bpl READ_INPUT_BLOCK_COPY
    bit CFS_BLOCK_FLAG
    bpl READ_INPUT_BLOCK_DONE
    jsr FINISH_LINE
READ_INPUT_BLOCK_DONE:
    jmp RELEASE_CASSETTE
READ_INPUT_BLOCK_RETRY:
    jsr FIND_BLOCK
    bne READ_INPUT_BLOCK            ; always taken

;; Takes the first byte of a ROM filing system block, which says what follows: "*" a header, "#" a short header,
;; which only moves the block number on, or anything else "Bad ROM".
;;
;; It returns as <READ_HEADER> does.
;; In: A = the byte
;; Errors: "Bad ROM"
;; Entry: BAD_ROM_ERROR = ends any catalogue and gives the "Bad ROM" error
;; See: <READ_HEADER>
ROM_BLOCK_START:
    cmp #SYNC_BYTE
    beq READ_HEADER_BYTES
    cmp #ROM_SHORT_HEADER
    bne BAD_ROM_ERROR
    inc CFS_BLOCK_NUMBER
    bne ROM_BLOCK_START_SHORT
    inc CFS_BLOCK_NUMBER+1
ROM_BLOCK_START_SHORT:
    ldx #$FF
    bit OVERFLOW_BYTE               ; set overflow, a header read
    bne READ_HEADER_DONE            ; always taken: A is "#"
BAD_ROM_ERROR:
    lda #$FF - CFS_CATALOGUING
    jsr CLEAR_STATUS_BITS
    brk
    .byte ERROR_BAD_ROM, "Bad ROM", 0

;; Reads a block header from tape: turns the motor on, waits for the high tone and the synchronisation byte, then
;; reads the header.
;;
;; The name is read up to its zero, ten characters at most, and the rest of the header, with its CRC, to the fixed
;; places after <CFS_BLOCK_NAME>. High tone in the middle ends the header early. Taking in the CRC leaves
;; <CFS_CRC> zero when the header is good, and <CFS_HEADER_BAD> is set from it. A header without a name is ignored
;; and the next one read. It returns as <READ_HEADER> does.
;; Entry: READ_HEADER_BYTES = reads the header after the synchronisation byte
;; See: <READ_HEADER>, <CASSETTE_INTERRUPT>
READ_TAPE_HEADER:
    ldy #$FF
    jsr MOTOR_ON
    lda #$01
    sta CFS_RECEIVE_STATE
    jsr START_RECEIVING
READ_TAPE_HEADER_WAIT:
    jsr CHECK_ESCAPE
    lda #$03
    cmp CFS_RECEIVE_STATE
    bne READ_TAPE_HEADER_WAIT       ; until the sync byte
READ_HEADER_BYTES:
    ldy #$00
    jsr SET_CRC
READ_HEADER_NAME:
    jsr READ_BYTE
    bvc READ_HEADER_END             ; high tone
    sta CFS_BLOCK_NAME,y
    beq READ_HEADER_REST
    iny
    cpy #CFS_NAME_SIZE
    bne READ_HEADER_NAME
    dey                             ; eleven characters: keep ten
READ_HEADER_REST:
    ldx #CFS_BLOCK_LOAD - CFS_BLOCK_NAME
READ_HEADER_REST_LOOP:
    jsr READ_BYTE
    bvc READ_HEADER_END
    sta CFS_BLOCK_NAME,x
    inx
    cpx #CFS_HEADER_CRC + 2 - CFS_BLOCK_NAME
    bne READ_HEADER_REST_LOOP
READ_HEADER_END:
    tya
    tax
    lda #$00
    sta CFS_BLOCK_NAME,y
    lda CFS_CRC
    ora CFS_CRC+1
    sta CFS_HEADER_BAD
READ_HEADER_DONE:
    jsr CLEAR_CRC_AND_FLAG
    sty CFS_RECEIVE_STATE           ; idle
    txa
    bne ADD_TO_CRC_DONE
;; Reads the next block header, from tape or from the ROM filing system's ROMs, into <CFS_BLOCK_NAME>.
;;
;; In the ROM filing system "+" ends a ROM, and the next ROM is tried; while cataloguing a new line starts.
;; In: CFS_RFS_SWITCH = which filing system
;; Out:
;;   overflow = set when a header was read, clear when the ROMs ran out or tape high tone cut the header short
;;   zero = clear after a header
;;   X = after a header, the name's length, or &FF for a ROM's short header
;;   Y = 0 after a header
;;   CFS_HEADER_BAD = nonzero when the header's CRC failed
;; Uses: A, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Bad ROM", "Escape"
;; See: <READ_TAPE_HEADER>, <ROM_BLOCK_START>
READ_HEADER:
    lda CFS_RFS_SWITCH
    beq READ_TAPE_HEADER
READ_ROM_HEADER:
    jsr RFS_GET_BYTE                       ; read the next ROM byte
    cmp #ROM_END_MARKER
    bne ROM_BLOCK_START
    lda #CFS_CATALOGUING
    and CFS_STATUS
    beq READ_ROM_HEADER_NEXT_ROM
    jsr CFS_NEW_LINE
READ_ROM_HEADER_NEXT_ROM:
    jsr RFS_NEXT_ROM                       ; the next ROM
    bcc READ_ROM_HEADER
    clv                             ; no more ROMs
    rts

;; Reads the next byte of a header, from tape or a ROM, and adds it to the CRC.
;; Out: A = the byte, overflow = clear when tape high tone ended the header instead
;; Keeps: X, Y
;; Uses: CFS_BYTE_DONE, CFS_CRC, CFS_CRC_BITS
;; See: <WAIT_FOR_BYTE>, <ADD_TO_CRC>
READ_BYTE:
    lda CFS_RFS_SWITCH
    beq READ_BYTE_WAIT
    txa
    pha
    tya
    pha
    jsr RFS_GET_BYTE                       ; read the next ROM byte
    sta CFS_BYTE
    lda #$FF                        ; done, with bit 6 set
    sta CFS_BYTE_DONE
    pla
    tay
    pla
    tax
READ_BYTE_WAIT:
    jsr WAIT_FOR_BYTE
;; Adds a byte to the CRC in <CFS_CRC>: the CRC-16 of the tape format, with the polynomial &1021.
;;
;; The high byte takes the byte, then for each of eight bits the CRC shifts left, and when a bit leaves the top it
;; is exclusive-ORed with &0810 before the shift and has bit 0 set by it, together &1021.
;; In: A = the byte
;; Keeps: A, X, Y, carry, zero, negative, overflow
;; Uses: CFS_CRC_BITS
ADD_TO_CRC:
    php
    pha
    sec
    ror CFS_CRC_BITS                ; a bit that counts eight shifts
    eor CFS_CRC+1
    sta CFS_CRC+1
ADD_TO_CRC_BIT:
    lda CFS_CRC+1
    rol a
    bcc ADD_TO_CRC_SHIFT
    ror a
    eor #>$0810
    sta CFS_CRC+1
    lda CFS_CRC
    eor #<$0810
    sta CFS_CRC
    sec
ADD_TO_CRC_SHIFT:
    rol CFS_CRC
    rol CFS_CRC+1
    lsr CFS_CRC_BITS
    bne ADD_TO_CRC_BIT
    pla
    plp
ADD_TO_CRC_DONE:
    rts

;; Gets <CASSETTE_INTERRUPT> ready to store the data of the block whose header has just been read.
;;
;; It starts state 4, reading the data, when the header was read and the block has data; otherwise it leaves the
;; reading idle.
;; In: overflow = set when the header was read
;; Out: X = the state
;; Uses: A, FS_SCRATCH+12
;; Entry: RECEIVE_DATA_MODE = with A = &FF to read the data and drop it, or 0 to store it
;; See: <CASSETTE_INTERRUPT>
RECEIVE_DATA:
    lda #$00
RECEIVE_DATA_MODE:
    sta CFS_BYTE
    ldx #$00
    stx FS_SCRATCH+12
    bvc RECEIVE_DATA_STATE
    lda CFS_BLOCK_LENGTH
    ora CFS_BLOCK_LENGTH+1
    beq RECEIVE_DATA_STATE
    ldx #$04
RECEIVE_DATA_STATE:
    stx CFS_RECEIVE_STATE
    rts

;; Writes a block to tape: the high tone, the header, the data, and their CRCs.
;;
;; Block 0 has five seconds of tone first, the others the gap in <CFS_GAP>. The name comes from
;; <CFS_SEARCH_NAME>, the rest of the header from <CFS_BLOCK_LOAD> on, with the spare bytes cleared, and the data
;; from <CFS_DATA_ADDRESS> or across the Tube. After the block it shows the catalogue line, and after the last block
;; of the file five more seconds of tone, the bell and the end of the line. <START_WRITING> has started the 6850.
;; In: CFS_BLOCK_LOAD..CFS_BLOCK_FLAGS = the header, CFS_SEARCH_NAME = the name
;; Out: negative = set when it was the file's last block
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: "Escape"
;; See: <WRITE_BYTE>, <SHOW_BLOCK_INFO>
WRITE_BLOCK:
    php
    ldx #$03
    lda #$00
WRITE_BLOCK_CLEAR:
    sta CFS_BLOCK_SPARE,x
    dex
    bpl WRITE_BLOCK_CLEAR
    lda CFS_BLOCK_NUMBER
    ora CFS_BLOCK_NUMBER+1
    bne WRITE_BLOCK_GAP
    jsr WAIT_LEADER
    beq WRITE_BLOCK_HEADER          ; always taken
WRITE_BLOCK_GAP:
    jsr WAIT_GAP
WRITE_BLOCK_HEADER:
    lda #SYNC_BYTE
    sta CFS_BYTE
    jsr CLEAR_CRC_AND_FLAG
    jsr START_TRANSMITTING
    jsr WAIT_FOR_BYTE               ; the sync byte goes
    dey
WRITE_BLOCK_NAME:
    iny
    lda CFS_SEARCH_NAME,y
    sta CFS_BLOCK_NAME,y
    jsr WRITE_BYTE_CRC
    bne WRITE_BLOCK_NAME            ; up to and including its zero
    ldx #CFS_BLOCK_LOAD - CFS_BLOCK_NAME
WRITE_BLOCK_HEADER_REST:
    lda CFS_BLOCK_NAME,x
    jsr WRITE_BYTE_CRC
    inx
    cpx #CFS_HEADER_CRC - CFS_BLOCK_NAME
    bne WRITE_BLOCK_HEADER_REST
    jsr WRITE_CRC
    lda CFS_BLOCK_LENGTH
    ora CFS_BLOCK_LENGTH+1
    beq WRITE_BLOCK_END
    ldy #$00
    jsr SET_CRC
WRITE_BLOCK_DATA:
    lda (CFS_DATA_ADDRESS),y
    jsr CHECK_TUBE_ADDRESS
    beq WRITE_BLOCK_DATA_BYTE
    ldx TUBE_R3_DATA
WRITE_BLOCK_DATA_BYTE:
    txa
    jsr WRITE_BYTE_CRC
    iny
    cpy CFS_BLOCK_LENGTH
    bne WRITE_BLOCK_DATA
    jsr WRITE_CRC
WRITE_BLOCK_END:
    jsr WAIT_FOR_BYTE               ; two more byte times, sending the last byte again, before the 6850 stops
    jsr WAIT_FOR_BYTE
    jsr RESET_ACIA
    lda #$01                        ; 0.2 seconds
    jsr WAIT_TENTHS
    plp
    jsr SHOW_BLOCK_INFO
    bit CFS_BLOCK_FLAGS
    bpl WRITE_BLOCK_DONE
    php
    jsr WAIT_LEADER
    jsr FINISH_TAPE
    plp
WRITE_BLOCK_DONE:
    rts

;; Writes a byte to tape and adds it to the CRC.
;; In: A = the byte
;; Out: A = the byte, zero = set when it is 0
;; Keeps: X, Y
;; Uses: CFS_BYTE, CFS_BYTE_DONE, CFS_CRC, CFS_CRC_BITS
;; Errors: "Escape"
;; See: <WRITE_BYTE>, <ADD_TO_CRC>
WRITE_BYTE_CRC:
    jsr WRITE_BYTE
    jmp ADD_TO_CRC

;; Writes the CRC in <CFS_CRC> to tape, the high byte first.
;; Keeps: X, Y
;; Uses: A, CFS_BYTE, CFS_BYTE_DONE
;; Errors: "Escape"
WRITE_CRC:
    lda CFS_CRC+1
    jsr WRITE_BYTE
    lda CFS_CRC
;; Writes a byte to tape: leaves it in <CFS_BYTE> and waits until the transmit interrupt has taken it.
;; In: A = the byte
;; Out: A = the byte, zero = set when it is 0
;; Keeps: X, Y
;; Uses: CFS_BYTE_DONE
;; Errors: "Escape"
;; Entry: WAIT_FOR_BYTE = only waits for the interrupt to take or deliver a byte, returning CFS_BYTE
;; See: <CASSETTE_INTERRUPT>
WRITE_BYTE:
    sta CFS_BYTE
WAIT_FOR_BYTE:
    jsr CHECK_ESCAPE
    bit CFS_BYTE_DONE
    bpl WAIT_FOR_BYTE
    lda #$00
    sta CFS_BYTE_DONE
    lda CFS_BYTE
    rts

;; Waits 5.1 seconds, the high tone before a file's first block and after its last.
;; Out: X = 0
;; Uses: A, CFS_TIMEOUT
;; Errors: "Escape"
;; Entry: WAIT_GAP = waits for the gap in <CFS_GAP>, WAIT_TENTHS = waits A + 1 tenths of a second
;; See: <CFS_TIMEOUT>
WAIT_LEADER:
    lda #LEADER_TENTHS
    bne WAIT_TENTHS                 ; always taken
WAIT_GAP:
    lda CFS_GAP
WAIT_TENTHS:
    ldx #$05                        ; five times A + 1 vertical syncs, at 50 a second
WAIT_TENTHS_LOOP:
    sta CFS_TIMEOUT
WAIT_TENTHS_FIELD:
    jsr CHECK_ESCAPE
    bit CFS_TIMEOUT
    bpl WAIT_TENTHS_FIELD
    dex
    bne WAIT_TENTHS_LOOP
    rts

;; Shows the catalogue line of the block whose header has just been read, starting a new line for a new file.
;;
;; A new file is block 0 or a block after a file's last; the line is left alone after a block error.
;; Uses: A, X, Y, CFS_ERRORS, CFS_LAST_FLAGS, CFS_FILE_LENGTH
;; Entry: SHOW_BLOCK_NEW_LINE = always starts a new line
;; See: <SHOW_BLOCK_INFO>
SHOW_BLOCK:
    lda CFS_BLOCK_NUMBER
    ora CFS_BLOCK_NUMBER+1
    beq SHOW_BLOCK_NEW_LINE
    bit CFS_LAST_FLAGS
    bpl SHOW_BLOCK_INFO
SHOW_BLOCK_NEW_LINE:
    jsr FINISH_LINE
;; Shows a block's catalogue line, when messages are on: the name, the block number, and for the last block the
;; file's length and, with extended messages, its load and execution addresses, all in hexadecimal.
;;
;; The line starts with a carriage return alone, so each block's line overwrites the last until the file ends.
;; Characters in the name that do not print show as "?". The ROM filing system shows only the name unless
;; extended messages are on. The length is worked out into <CFS_FILE_LENGTH> as it is shown: the block number
;; plus the last block's length.
;; Uses: A, X, Y, CFS_FILE_LENGTH
;; Out: CFS_ERRORS = 0, CFS_LAST_FLAGS = the block's flag
;; See: <SHOW_BLOCK>, <PRINT_HEX>
SHOW_BLOCK_INFO:
    ldy #$00
    sty CFS_ERRORS
    lda CFS_BLOCK_FLAGS
    sta CFS_LAST_FLAGS
    jsr CHECK_CFS_MESSAGES                       ; messages on?
    beq SHOW_BLOCK_DONE
    lda #$0D
    jsr OSWRCH
SHOW_BLOCK_NAME:
    lda CFS_BLOCK_NAME,y
    beq SHOW_BLOCK_PAD
    cmp #' '
    bcc SHOW_BLOCK_UNPRINTABLE
    cmp #$7F
    bcc SHOW_BLOCK_CHARACTER
SHOW_BLOCK_UNPRINTABLE:
    lda #'?'
SHOW_BLOCK_CHARACTER:
    jsr OSWRCH
    iny
    bne SHOW_BLOCK_NAME             ; always taken
SHOW_BLOCK_PAD:
    lda CFS_RFS_SWITCH
    beq SHOW_BLOCK_SPACE
    bit CFS_CURRENT_OPTIONS
    bvc SHOW_BLOCK_DONE             ; ROM files without extended messages: the name alone
SHOW_BLOCK_SPACE:
    jsr PRINT_SPACE
    iny
    cpy #CFS_NAME_SIZE
    bcc SHOW_BLOCK_PAD
    lda CFS_BLOCK_NUMBER
    tax
    jsr PRINT_HEX
    bit CFS_BLOCK_FLAGS
    bpl SHOW_BLOCK_DONE
    txa
    clc
    adc CFS_BLOCK_LENGTH+1
    sta CFS_FILE_LENGTH+1
    jsr PRINT_SPACE_HEX
    lda CFS_BLOCK_LENGTH
    sta CFS_FILE_LENGTH
    jsr PRINT_HEX
    bit CFS_CURRENT_OPTIONS
    bvc SHOW_BLOCK_DONE
    ldx #$04
SHOW_BLOCK_GAP:
    jsr PRINT_SPACE
    dex
    bne SHOW_BLOCK_GAP
    ldx #CFS_BLOCK_LOAD + 3 - CFS_BLOCK_NAME
    jsr PRINT_HEADER_ADDRESS
    jsr PRINT_SPACE
    ldx #CFS_BLOCK_EXEC + 3 - CFS_BLOCK_NAME
;; Prints a four-byte address from the block header in hexadecimal, the high byte first.
;; In: X = the offset of the address's high byte from <CFS_BLOCK_NAME>
;; Out: X = 4 less, Y = 0
;; Uses: A
PRINT_HEADER_ADDRESS:
    ldy #$04
PRINT_HEADER_ADDRESS_LOOP:
    lda CFS_BLOCK_NAME,x
    jsr PRINT_HEX
    dex
    dey
    bne PRINT_HEADER_ADDRESS_LOOP
SHOW_BLOCK_DONE:
    rts

;; Gets the tape ready to write: turns the motor on, starts the 6850 writing, and when messages are on asks for
;; RECORD and waits for RETURN.
;;
;; The ROM filing system cannot be written to, and gives "Bad command".
;; Uses: A, X, Y
;; Errors: "Bad command", "Escape"
;; See: <START_WRITING>
PROMPT_RECORD:
    lda CFS_RFS_SWITCH
    beq PROMPT_RECORD_TAPE
    jmp USERV_DEFAULT               ; "Bad command"
PROMPT_RECORD_TAPE:
    jsr MOTOR_ON_WRITING
    jsr START_WRITING
    jsr CHECK_CFS_MESSAGES                       ; messages on?
    beq SHOW_BLOCK_DONE
    jsr PRINT_CFS_MESSAGE
    .byte "RECORD then RETURN", 0
PROMPT_RECORD_WAIT:
    jsr CHECK_ESCAPE
    jsr OSRDCH
    cmp #$0D
    bne PROMPT_RECORD_WAIT
    jmp OSNEWL

;; Moves <CFS_DATA_ADDRESS> on by a page, to the next block's data.
;; Keeps: A, X, Y
NEXT_PAGE:
    inc CFS_DATA_ADDRESS+1
    bne NEXT_PAGE_DONE
    inc CFS_DATA_ADDRESS+2
    bne NEXT_PAGE_DONE
    inc CFS_DATA_ADDRESS+3
NEXT_PAGE_DONE:
    rts

;; Prints a space, then a byte in hexadecimal.
;; In: A = the byte
;; Keeps: X, Y
;; Uses: A
;; See: <PRINT_HEX>
PRINT_SPACE_HEX:
    pha
    jsr PRINT_SPACE
    pla
;; Prints a byte in hexadecimal, two digits.
;; In: A = the byte
;; Keeps: X, Y
;; Uses: A
;; Entry: PRINT_HEX_DIGIT = prints A's low nibble as a digit
PRINT_HEX:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PRINT_HEX_DIGIT
    pla
PRINT_HEX_DIGIT:
    clc
    and #$0F
    adc #'0'
    cmp #'9' + 1
    bcc PRINT_HEX_DIGIT_WRITE
    adc #'A' - '9' - 2              ; the carry adds the last 1
PRINT_HEX_DIGIT_WRITE:
    jmp OSWRCH

;; Prints a space.
;; Out: A = " "
;; Keeps: X, Y
PRINT_SPACE:
    lda #' '
    bne PRINT_HEX_DIGIT_WRITE       ; always taken

;; Checks for ESCAPE while the cassette filing system waits, and gives the "Escape" error if it has been pressed.
;;
;; While the filing system is being called for *EXEC or *SPOOL (<CASSETTE_CRITICAL>) escapes are left alone. Before
;; the error it ends any catalogue, releases the cassette and acknowledges the escape.
;; Keeps: A, X, Y, carry, zero, negative, overflow
;; Errors: "Escape"
CHECK_ESCAPE:
    php
    bit CASSETTE_CRITICAL
    bmi CHECK_ESCAPE_DONE
    bit ESCAPE_FLAG
    bmi CHECK_ESCAPE_ERROR
CHECK_ESCAPE_DONE:
    plp
    rts
CHECK_ESCAPE_ERROR:
    jsr END_CATALOGUE
    jsr RELEASE_CASSETTE
    lda #OSBYTE_ACKNOWLEDGE_ESCAPE
    jsr OSBYTE
    brk
    .byte ERROR_ESCAPE, "Escape", 0

;; Reads a block's data and checks the block, after its header: the name, the block number and both CRCs.
;;
;; A bad header is a "Data?" error, a block of another file "File?", one out of sequence "Block?", and data whose
;; CRC fails "Data?". Errors go to <BLOCK_ERROR>, which may abort, retry or carry on. <RECEIVE_DATA> has started
;; the data's reading.
;; In: Y = nonzero to show "Loading" first
;; Out: zero = set when the block is good or its error is ignored, clear to read it again
;; Uses: A, X, Y, FS_SCRATCH..FS_WORKSPACE+$0F, CFS_OUTPUT_HEADER..CFS_LAST_FLAGS
;; Errors: the block errors, "Escape"
;; Entry: CHECK_BLOCK = checks the block's number and CRCs, not its name, with X = 0 to report errors and carry on,
;;   or &FF to act on them as *OPT 2 says
;; See: <BLOCK_ERROR>, <SHOW_BLOCK>
LOAD_BLOCK:
    tya
    beq LOAD_BLOCK_CHECK
    jsr PRINT_CFS_MESSAGE
    .byte $0D, "Loading", $0D, 0
LOAD_BLOCK_CHECK:
    sta CFS_ERRORS                  ; 0
    ldx #$FF
    lda CFS_HEADER_BAD
    bne CHECK_BLOCK
    jsr COMPARE_NAMES
    php
    ldx #$FF
    ldy #<FILE_ERROR
    lda #>FILE_ERROR
    plp
    bne CHECK_BLOCK_ERROR
CHECK_BLOCK:
    ldy #<DATA_ERROR
    lda CFS_HEADER_BAD
    beq CHECK_BLOCK_NUMBER
    lda #>DATA_ERROR
    bne CHECK_BLOCK_ERROR           ; always taken
CHECK_BLOCK_NUMBER:
    lda CFS_BLOCK_NUMBER
    cmp CFS_WANTED_BLOCK
    bne CHECK_BLOCK_WRONG
    lda CFS_BLOCK_NUMBER+1
    cmp CFS_WANTED_BLOCK+1
    beq CHECK_BLOCK_READ
CHECK_BLOCK_WRONG:
    ldy #<BLOCK_NUMBER_ERROR
    lda #>BLOCK_NUMBER_ERROR
CHECK_BLOCK_ERROR:
    pha
    tya
    pha
    txa
    pha
    jsr SHOW_BLOCK_NEW_LINE
    pla
    tax
    pla
    tay
    pla
    bne BLOCK_ERROR                 ; always taken
CHECK_BLOCK_READ:
    txa
    pha
    jsr SHOW_BLOCK
    jsr WAIT_BLOCK_END
    pla
    tax
    lda CFS_CRC
    ora CFS_CRC+1
    beq COMPARE_NAMES_DONE          ; good
    ldy #<DATA_ERROR
    lda #>DATA_ERROR
;; Acts on a block error as *OPT 2 says: aborts with the error, or shows its message and asks to rewind the tape for
;; a retry, or carries on.
;;
;; It aborts when the filing system is being called for *EXEC or *SPOOL, or, with X = &FF, for any error in the
;; ROM filing system or when *OPT 2 says to; then it closes the *EXEC file, releases the cassette and jumps to the
;; error's BRK.
;; Otherwise it prints the error's text as a message, through <PRINT_CFS_MESSAGE>, which returns after the text,
;; to the BNE there. Messages on or off, that BNE reaches <BLOCK_ERROR_RETRY>: the return address's increment
;; leaves zero clear. "Block?" has no BNE and falls into it.
;; In: A/Y = the error's BRK (high byte in A), X = 0 to report the error and carry on, or &FF to act on it
;; Out: zero = set to carry on, clear to read the block again
;; Uses: A, X, Y, CFS_MESSAGE_POINTER, CFS_ERRORS
;; See: <DATA_ERROR>, <FILE_ERROR>, <BLOCK_NUMBER_ERROR>
BLOCK_ERROR:
    dec CFS_ERRORS
    pha
    bit CASSETTE_CRITICAL
    bmi BLOCK_ERROR_ABORT
    txa
    and CFS_RFS_SWITCH
    bne BLOCK_ERROR_ABORT
    txa
    and #OPT_ABORT | OPT_ABORT >> 4
    and CFS_CURRENT_OPTIONS
    beq BLOCK_ERROR_MESSAGE
BLOCK_ERROR_ABORT:
    pla
    sta CFS_MESSAGE_POINTER+1
    sty CFS_MESSAGE_POINTER
    jsr CLOSE_EXEC
    lsr CASSETTE_CRITICAL
    jsr STOP_TAPE
    jmp (CFS_MESSAGE_POINTER)
BLOCK_ERROR_MESSAGE:
    pla                             ; push the address of the error number, as a JSR's return address would be
    iny
    bne BLOCK_ERROR_PUSH
    clc
    adc #$01
BLOCK_ERROR_PUSH:
    pha
    tya
    pha
;; Prints the zero-terminated message that follows the JSR to it, when messages are on, and returns after it.
;; Out: A = 0, Y = 0
;; Keeps: X
;; Uses: CFS_MESSAGE_POINTER
;; Entry: PRINT_INLINE = prints the message when Y is nonzero, whatever the options
;; See: <CHECK_CFS_MESSAGES>
PRINT_CFS_MESSAGE:
    jsr CHECK_CFS_MESSAGES                       ; messages on?
    tay
PRINT_INLINE:
    pla
    sta CFS_MESSAGE_POINTER
    pla
    sta CFS_MESSAGE_POINTER+1
    tya
    php
PRINT_INLINE_NEXT:
    inc CFS_MESSAGE_POINTER
    bne PRINT_INLINE_CHARACTER
    inc CFS_MESSAGE_POINTER+1
PRINT_INLINE_CHARACTER:
    ldy #$00
    lda (CFS_MESSAGE_POINTER),y
    beq PRINT_INLINE_END
    plp
    php
    beq PRINT_INLINE_NEXT           ; not printing
    jsr OSASCI
    jmp PRINT_INLINE_NEXT
PRINT_INLINE_END:
    plp
    inc CFS_MESSAGE_POINTER
    bne PRINT_INLINE_RETURN
    inc CFS_MESSAGE_POINTER+1
PRINT_INLINE_RETURN:
    jmp (CFS_MESSAGE_POINTER)

;; Compares the name in the block header with the one searched for, ignoring the case of letters.
;;
;; An empty search name matches any file.
;; Out: zero = set when they match
;; Uses: A, X
;; See: <CFS_SEARCH_NAME>, <CFS_BLOCK_NAME>
COMPARE_NAMES:
    ldx #$FF
COMPARE_NAMES_LOOP:
    inx
    lda CFS_SEARCH_NAME,x
    bne COMPARE_NAMES_CHARACTER
    txa
    beq COMPARE_NAMES_END
    lda CFS_BLOCK_NAME,x
COMPARE_NAMES_END:
    rts
COMPARE_NAMES_CHARACTER:
    jsr CHECK_LETTER                       ; carry = clear for a letter
    eor CFS_BLOCK_NAME,x
    bcs COMPARE_NAMES_NEXT
    and #%11011111                  ; ignore the case bit
COMPARE_NAMES_NEXT:
    beq COMPARE_NAMES_LOOP
COMPARE_NAMES_DONE:
    rts

;; The "Data?" error: a header or data CRC failed.
;;
;; <BLOCK_ERROR> jumps to the BRK, or prints the text and continues at the BNE after it.
;; See: <BLOCK_ERROR>
DATA_ERROR:
    brk
    .byte ERROR_DATA, $0D, "Data?", 0
    bne BLOCK_ERROR_RETRY
;; The "File?" error: a block of a file other than the one being read.
;; See: <BLOCK_ERROR>
FILE_ERROR:
    brk
    .byte ERROR_FILE, $0D, "File?", 0
    bne BLOCK_ERROR_RETRY
;; The "Block?" error: a block other than the one expected next.
;; See: <BLOCK_ERROR>
BLOCK_NUMBER_ERROR:
    brk
    .byte ERROR_BLOCK, $0D, "Block?", 0
;; Finishes a block error that was not an abort: asks to rewind the tape for a retry, or carries on.
;;
;; With retries on, X = &FF and <CFS_ERRORS> nonzero (as <BLOCK_ERROR> leaves it), it resets the 6850, prints
;; "Rewind tape" and returns zero clear. Otherwise it ends the line, waits for the block's data to finish, and
;; returns zero set.
;; In: X = 0 to carry on, &FF to act on *OPT 2
;; Out: zero = clear to read the block again
;; Uses: A, Y
;; Entry: BLOCK_ERROR_CONTINUE = ends the line and waits for the block to end
BLOCK_ERROR_RETRY:
    lda CFS_ERRORS
    beq BLOCK_ERROR_CONTINUE
    txa
    beq BLOCK_ERROR_CONTINUE
    lda #OPT_RETRY | OPT_RETRY >> 4
    bit CFS_CURRENT_OPTIONS
    beq BLOCK_ERROR_CONTINUE
    jsr RESET_ACIA
    tay                             ; nonzero: print
    jsr PRINT_INLINE
    .byte $0D, $07, "Rewind tape", $0D, $0D, 0
WAIT_BLOCK_END_DONE:
    rts
BLOCK_ERROR_CONTINUE:
    jsr CFS_NEW_LINE
;; Waits until <CASSETTE_INTERRUPT> has finished reading the block, feeding it the bytes in the ROM filing system.
;; Out: A = 0, zero = set
;; Uses: X, Y, FS_SCRATCH..FS_WORKSPACE+$0F
;; Errors: "Escape"
WAIT_BLOCK_END:
    lda CFS_RECEIVE_STATE
    beq WAIT_BLOCK_END_DONE
    jsr CHECK_ESCAPE
    lda CFS_RFS_SWITCH
    beq WAIT_BLOCK_END
    jsr CASSETTE_INTERRUPT
    jmp WAIT_BLOCK_END

;; Stops the tape at the end of an operation: rings the bell if messages are on, then releases the cassette.
;; Uses: A, X, Y
;; See: <RELEASE_CASSETTE>
STOP_TAPE:
    jsr CHECK_CFS_MESSAGES                       ; messages on?
    beq RELEASE_CASSETTE
    lda #$07
    jsr OSWRCH
;; Gives the 6850 back to RS-423: turns the motor off, restores the serial ULA, and resets the 6850 to its RS-423
;; setting.
;;
;; When the data address is in the second processor it first makes the Tube's release call, through <CALL_TUBE>,
;; which claims the Tube before it. <RS423_TIMEOUT> is left 0, as if RS-423 had timed out.
;; Uses: A, X, Y
;; Entry: RESTORE_SERIAL = without the Tube or the motor
;; See: <CLAIM_SERIAL>, <RESTORE_ACIA>
RELEASE_CASSETTE:
    lda #CFS_TUBE_RELEASE
    jsr START_TUBE_TRANSFER
    ldx #$00
    jsr SET_MOTOR
RESTORE_SERIAL:
    php
    sei
    lda SERIAL_ULA_COPY
    sta SERIAL_ULA
    lda #$00
    sta RS423_TIMEOUT
    beq RESTORE_ACIA_LOCKED         ; always taken
;; Resets the 6850 and sets it from <ACIA_CONTROL_COPY>, the RS-423 setting.
;; Keeps: X, Y, interrupt
;; Uses: A
;; Entry: RESTORE_ACIA_LOCKED = with the flags already pushed
RESTORE_ACIA:
    php
RESTORE_ACIA_LOCKED:
    jsr RESET_ACIA
    lda ACIA_CONTROL_COPY
    jmp WRITE_ACIA_CONTROL                       ; set the 6850 and its copy, and pull the flags
CLAIM_SERIAL_BUSY:
    plp
    bit ESCAPE_FLAG
    bpl CLAIM_SERIAL                ; wait, unless ESCAPE has been pressed
    rts

;; Sets up a sequential file operation: its options, the low nibble of <CFS_OPTIONS>, and the gap between blocks
;; from <CFS_BLOCK_GAP>; then claims the 6850.
;;
;; A gap of 0, which *OPT 3 cannot set, falls into <SET_LOAD_SAVE_OPTIONS> instead.
;; Uses: A
;; Keeps: X, Y
;; See: <CLAIM_SERIAL>
SET_SEQUENTIAL_OPTIONS:
    lda CFS_OPTIONS
    asl a
    asl a
    asl a
    asl a
    sta CFS_CURRENT_OPTIONS
    lda CFS_BLOCK_GAP
    bne SET_GAP
;; Sets up a LOAD or SAVE: its options, the high nibble of <CFS_OPTIONS>, and the gap between blocks; then claims
;; the 6850.
;; Uses: A
;; Keeps: X, Y
;; Entry: SET_GAP = sets the gap from A
;; See: <CLAIM_SERIAL>
SET_LOAD_SAVE_OPTIONS:
    lda CFS_OPTIONS
    and #%11110000
    sta CFS_CURRENT_OPTIONS
    lda #LOAD_SAVE_GAP
SET_GAP:
    sta CFS_GAP
;; Claims the 6850 for the cassette from RS-423, waiting while RS-423 is busy or has not timed out, and resets it.
;;
;; It enables interrupts, and gives up without the 6850 if ESCAPE is pressed, which the next <CHECK_ESCAPE> reports.
;; Out: RS423_TIMEOUT = 1, the cassette's
;; Uses: A
;; Keeps: X, Y
;; See: <RELEASE_CASSETTE>
CLAIM_SERIAL:
    cli
    php
    sei
    bit RS423_BUSY
    bpl CLAIM_SERIAL_BUSY
    lda RS423_TIMEOUT
    bmi CLAIM_SERIAL_BUSY
    lda #$01
    sta RS423_TIMEOUT
    jsr RESET_ACIA
    plp
    rts

;; Resets the 6850 (a master reset), stopping it.
;; Out: A = 3
;; Keeps: X, Y
RESET_ACIA:
    lda #CFS_ACIA_RESET
    bne SET_ACIA                    ; always taken
;; Starts the 6850 writing to tape, its transmit interrupt sending <CFS_BYTE>.
;; Uses: A
;; Keeps: X, Y
START_TRANSMITTING:
    lda #CFS_ACIA_WRITING
    sta CFS_TRANSMITTING
    bne SET_ACIA_SPEED              ; always taken
;; Starts the 6850 reading from tape, its receive interrupt stepping <CASSETTE_INTERRUPT>.
;;
;; First it turns the serial ULA's motor bit off for about 0.6 ms and back on.
;; Out: X = 0
;; Uses: A
;; Keeps: Y
;; Entry: SET_ACIA_SPEED = sets the 6850 to A ORed with the tape speed, SET_ACIA = sets the 6850 to A
START_RECEIVING:
    lda #CFS_ULA_MOTOR_OFF
    sta SERIAL_ULA
    ldx #$FF
START_RECEIVING_DELAY:
    dex
    bne START_RECEIVING_DELAY
    stx CFS_TRANSMITTING
    lda #CFS_ULA_MOTOR_ON
    sta SERIAL_ULA
    lda #CFS_ACIA_READING
SET_ACIA_SPEED:
    ora CFS_ACIA_SPEED
SET_ACIA:
    sta ACIA_CONTROL
    rts

;; Sets <CFS_WANTED_BLOCK> to the block after the one whose header was read.
;; Out: X/Y = that block's number
;; Keeps: A
SET_NEXT_BLOCK:
    ldx CFS_BLOCK_NUMBER
    ldy CFS_BLOCK_NUMBER+1
    inx
    stx CFS_WANTED_BLOCK
    bne SET_NEXT_BLOCK_HIGH
    iny
SET_NEXT_BLOCK_HIGH:
    sty CFS_WANTED_BLOCK+1
    rts

;; Clears <CFS_CRC> and <CFS_BYTE_DONE>, ready for a block.
;; Out: Y = 0
;; Keeps: A, X
;; Entry: SET_CRC = sets the CRC to Y
CLEAR_CRC_AND_FLAG:
    ldy #$00
    sty CFS_BYTE_DONE
SET_CRC:
    sty CFS_CRC
    sty CFS_CRC+1
    rts

;; Copies a zero-terminated name from the cassette workspace in page 3 to <CFS_SEARCH_NAME>.
;; In: X = the name's offset in page 3, less one
;; Out: A = 0, Y = the name's length
;; Uses: X
COPY_SEARCH_NAME:
    ldy #$FF
COPY_SEARCH_NAME_LOOP:
    iny
    inx
    lda CFS_SEARCH_NAME & $FF00,x
    sta CFS_SEARCH_NAME,y
    bne COPY_SEARCH_NAME_LOOP
    rts

;; Turns the cassette motor on for writing, with OSBYTE &89.
;; Uses: A, X, Y
;; Entry: MOTOR_ON = turns it on with Y = 0 to write or nonzero to read, SET_MOTOR = turns it off (X = 0) or on
;;   (X = 1), as <CFS_MOTOR_MODE> says
MOTOR_ON_WRITING:
    ldy #$00
MOTOR_ON:
    cli
    ldx #$01
    sty CFS_MOTOR_MODE
SET_MOTOR:
    lda #OSBYTE_CASSETTE_MOTOR
    ldy CFS_MOTOR_MODE
    jmp OSBYTE

;; Checks that a handle is the cassette filing system's and open, for OSBGET, OSBPUT and OSFSC 1.
;;
;; The handles are 1 for input and 2 for output, or 3 for input in the ROM filing system, which has no output.
;; In: Y = the handle, A = the <CFS_STATUS> bits it may be (CFS_INPUT_OPEN, CFS_OUTPUT_OPEN or both)
;; Out: carry = set
;; Uses: A, Y, FS_SCRATCH+12
;; Errors: "Channel"
;; Entry: CHANNEL_ERROR = gives the "Channel" error
CHECK_HANDLE:
    sta FS_SCRATCH+12
    tya
    eor CFS_RFS_SWITCH              ; handle 3 becomes 1 in the ROM filing system
    tay
    lda CFS_STATUS
    and FS_SCRATCH+12
    lsr a                           ; carry = input open
    dey
    beq CHECK_HANDLE_OPEN
    lsr a                           ; carry = output open
    dey
    bne CHANNEL_ERROR
CHECK_HANDLE_OPEN:
    bcs START_WRITING_DONE
CHANNEL_ERROR:
    brk
    .byte ERROR_CHANNEL, "Channel", 0

;; Starts a load's transfer across the Tube, when the data goes to the second processor.
;; Uses: A, X, Y
;; Entry: START_TUBE_TRANSFER = starts the transfer or Tube call in A instead
;; See: <CALL_TUBE>, <CHECK_TUBE_ADDRESS>
START_TUBE_LOAD:
    lda #CFS_TUBE_WRITE
START_TUBE_TRANSFER:
    jsr CHECK_TUBE_ADDRESS
    beq START_WRITING_DONE          ; the data is in this machine
    txa
    ldx #<CFS_DATA_ADDRESS
    ldy #>CFS_DATA_ADDRESS
;; Claims the Tube for the filing system, waiting until it is free, then makes a Tube call.
;; In: A = the call, X/Y = its control block, the four-byte address
;; Uses: A, X, Y
;; See: <TUBE_TRANSFER>
CALL_TUBE:
    pha
    lda #CFS_TUBE_CLAIM
CALL_TUBE_CLAIM:
    jsr TUBE_TRANSFER
    bcc CALL_TUBE_CLAIM
    pla
    jmp TUBE_TRANSFER

;; Checks whether <CFS_DATA_ADDRESS> is in the second processor: a Tube is fitted and the address's high half is not
;; &FFFF.
;; In: A = a byte to keep
;; Out: X = that byte, zero = set when the address is in this machine, A = &80 when not
;; Keeps: Y
CHECK_TUBE_ADDRESS:
    tax
    lda CFS_DATA_ADDRESS+2
    and CFS_DATA_ADDRESS+3
    cmp #$FF
    beq CHECK_TUBE_ADDRESS_DONE
    lda TUBE_PRESENT
    and #$80
CHECK_TUBE_ADDRESS_DONE:
    rts

;; Starts the 6850 for writing to tape: turns the motor on, sets the 6850 without interrupts, waits for its
;; transmit register to be empty, and sends &AA.
;; Uses: A
;; Keeps: X, Y
;; Errors: "Escape"
;; See: <START_TRANSMITTING>
START_WRITING:
    lda #CFS_ULA_MOTOR_ON
    sta SERIAL_ULA
    jsr RESET_ACIA
    lda #CFS_ACIA_IDLE
    jsr SET_ACIA_SPEED
START_WRITING_WAIT:
    jsr CHECK_ESCAPE
    lda ACIA_STATUS
    and #CFS_ACIA_TX_EMPTY
    beq START_WRITING_WAIT
    lda #$AA
    sta ACIA_DATA
START_WRITING_DONE:
    rts

    .byte $00                       ; unused, the last byte before FRED
    .assert * = FRED, "The cassette filing system ends where FRED begins."
