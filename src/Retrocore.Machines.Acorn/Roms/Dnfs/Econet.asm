; ---------------------------------------------------------------------------------------------------------------------
; The Econet: transmitting and receiving frames through the 68B54 ADLC, the NMI handlers that do it, and the NMI code
; the NFS copies to page &0D.
;
; Every exchange starts with a scout frame: the destination's station and network, the source's, a control byte and
; a port. For an ordinary port the destination answers with an acknowledgement, the source sends a data frame, and
; the destination ends with a final acknowledgement: four frames. A broadcast (station and network &FF) is the scout
; alone, carrying eight bytes of data. Port 0 carries the immediate operations, control bytes &81-&88: PEEK, POKE, a
; remote JSR, a user procedure call, an OS procedure call, HALT, CONTINUE and a request for the machine type. PEEK
; and the machine type are answered by a frame that carries the data in place of the acknowledgement, and HALT and
; CONTINUE by the acknowledgement alone. Each frame begins with its destination and source, two bytes each; the
; network is 0 for this one.
;
; The 68B54 interrupts on the NMI, whose code the NFS copies to &0D00 (<NFS_NMI>). It jumps to the current handler,
; and each handler deals with one step of a frame and installs the next one, through <NFS_SET_NMI_HANDLER>, when it
; returns. The handlers keep X, which the NMI code does not save. When nothing is happening the handler is
; <RECEIVE_SCOUT>.
;
; A transmit control block (TXCB) holds the control byte (bit 7 set), the port, the destination's station and
; network, the buffer's start and end addresses (four bytes each, the end being the address after the last byte), and
; for an immediate operation the remote address (bytes 12-15). When the exchange ends the control byte is replaced by
; the result: 0, or an error &40-&44. A receive control block (RXCB) has the same layout to byte 11; its control byte
; is &7F while it waits, a port or station of 0 accepts any, and a frame that arrives sets the control byte's bit 7 and
; fills in the port, the source and the end address.
;
; The register addresses of the 68B54 are in the Advanced User Guide, section 25.2; the constants below name the
; register bits the code uses, as the 68B54 defines them.
; ---------------------------------------------------------------------------------------------------------------------

; The NFS's variables in page &0D, after its NMI code.

ECONET_SCOUT = NMI_ROUTINE + $20    ;; &0D20-&0D2D, the scout this station sends, from its destination station on
ECONET_SCOUT_NETWORK = ECONET_SCOUT + 1 ;; the scout's destination network
ECONET_SCOUT_SOURCE = ECONET_SCOUT + 2 ;; this station's number, then 0 for its network, as the scout's source
ECONET_SCOUT_CONTROL = ECONET_SCOUT + 4 ;; the scout's control byte
ECONET_SCOUT_PORT = ECONET_SCOUT + 5 ;; the scout's port
ECONET_SCOUT_ADDRESS = ECONET_SCOUT + 6 ;; an immediate operation's remote address, or a broadcast's first data bytes
ECONET_SCOUT_END = ECONET_SCOUT + 10 ;; PEEK's and POKE's remote end address, or a broadcast's last four data bytes
ECONET_RX_SCOUT = NMI_ROUTINE + $3D ;; &0D3D-&0D49, the scout received, from its source station on
ECONET_RX_NETWORK = ECONET_RX_SCOUT + 1 ;; the received scout's source network
ECONET_RX_CONTROL = ECONET_RX_SCOUT + 2 ;; the received scout's control byte
ECONET_RX_PORT = ECONET_RX_SCOUT + 3 ;; the received scout's port
ECONET_RX_EXTRA = ECONET_RX_SCOUT + 4 ;; the scout's further bytes: an address and end address, or broadcast data
ECONET_FRAME = $0D4A                ;; the exchange's flags: <ECONET_FRAME_TWO_WAY> and the others below
ECONET_AFTER_ACK = $0D4B            ;; two bytes, the NMI handler <SEND_ACK> installs once its frame has ended
ECONET_SCOUT_INDEX = $0D4F          ;; the offset in <ECONET_SCOUT> of the next byte <SEND_SCOUT> sends
ECONET_SCOUT_LENGTH = $0D50         ;; the number of bytes of <ECONET_SCOUT> to send
ECONET_SAVED_SHIFT_MODE = $0D51     ;; the system VIA's shift register mode, bits 2-4 of its ACR, while the NFS uses it
ECONET_IRQ_OPERATION = $0D57        ;; the control byte of the immediate operation <SERVICE_UNRECOGNISED_INTERRUPT> runs
ECONET_PROCEDURE_ADDRESS = $0D58    ;; four bytes, the address a remote JSR or procedure call gave
ECONET_TUBE_TYPE = $0D5C            ;; the data's Tube transfer type: 2 to read the second processor, 3 to write it
ECONET_ODD_BYTE = $0D5D             ;; the last byte of a frame received for the Tube, when it came alone
ECONET_NMI_OWNED = $0D66            ;; bit 7 set while the NFS owns the NMI

; Zero page, as the Econet code uses it.

ECONET_TUBE_GUARD = $98             ;; bit 7 set: the next <RELEASE_TUBE> only clears it, keeping the Tube
ECONET_RX_BLOCKS_PAGE = $9F         ;; the page that holds the user's receive control blocks
ECONET_TX_BLOCK = NMI_WORKSPACE     ;; &A0-&A1, the address of the transmit control block
ECONET_INDEX = NMI_WORKSPACE + 2    ;; the Y offset from <ECONET_BUFFER> of the next byte, or the scout byte's offset
ECONET_PAGES = NMI_WORKSPACE + 3    ;; one more than the page crossings left before the buffer's end
ECONET_BUFFER = NMI_WORKSPACE + 4   ;; &A4-&A5, the base the data is indexed from, so the end falls at an offset of 0
ECONET_COUNT = NMI_WORKSPACE + 2    ;; &A2-&A5, for the Tube: the start less the end, counting up to 0
ECONET_BLOCK = NMI_WORKSPACE + 6    ;; &A6-&A7, the control block whose buffer is being filled or sent

; Offsets in a transmit or receive control block.

ECONET_CB_CONTROL = 0               ;; the control byte, which becomes the result or the received control byte
ECONET_CB_PORT = 1                  ;; the port
ECONET_CB_STATION = 2               ;; the station: the destination, or for receiving the source wanted (0 for any)
ECONET_CB_NETWORK = 3               ;; the network
ECONET_CB_START = 4                 ;; the buffer's start address, four bytes
ECONET_CB_END = 8                   ;; the buffer's end address, four bytes
ECONET_CB_REMOTE = 12               ;; an immediate operation's remote address, four bytes

; Bits of ECONET_FRAME.

ECONET_FRAME_REPLY = %10000000      ;; the data travels in the scout's acknowledgement: a PEEK's or machine type's reply
ECONET_FRAME_BROADCAST = %01000000  ;; the scout is a broadcast, with no acknowledgement
ECONET_FRAME_ODD_BYTE = %00100000   ;; the last byte received for the Tube waits in <ECONET_ODD_BYTE>
ECONET_FRAME_TUBE = %00000010       ;; the data goes through the Tube
ECONET_FRAME_TWO_WAY = %00000001    ;; the scout's acknowledgement, or a reply in its place, ends the exchange

; Control bytes, ports and results.

ECONET_PEEK = $81                   ;; immediate operation: read the remote station's memory
ECONET_POKE = $82                   ;; immediate operation: write the remote station's memory
ECONET_JSR = $83                    ;; immediate operation: call a routine in the remote station
ECONET_USER_PROCEDURE = $84         ;; immediate operation: a user procedure call, which raises the Econet event
ECONET_OS_PROCEDURE = $85           ;; immediate operation: an OS procedure call, run by the remote NFS
ECONET_HALT = $86                   ;; immediate operation: stop the remote station until CONTINUE
ECONET_CONTINUE = $87               ;; immediate operation: let a halted station go on
ECONET_MACHINE_TYPE = $88           ;; immediate operation: read the remote station's machine type and NFS version
ECONET_RX_OPEN = $7F                ;; a receive control block's control byte while it waits for a frame
ECONET_BROADCAST = $FF              ;; the station, and the network, of a broadcast
ECONET_HEADER = 6                   ;; the bytes of a scout before any further bytes
ECONET_SUCCESS = $00                ;; result: the exchange succeeded
ECONET_LINE_JAMMED = $40            ;; result: the line never became free ("Line Jammed")
ECONET_NET_ERROR = $41              ;; result: a frame went wrong ("Net Error")
ECONET_NOT_LISTENING = $42          ;; result: no station acknowledged the scout ("Not listening")
ECONET_NO_CLOCK = $43               ;; result: the 68B54 sees no carrier, so no clock ("No Clock")
ECONET_BAD_CONTROL = $44            ;; result: the control byte is not a transmit, or names no immediate operation
ECONET_FREE = %10000000             ;; <NFS_TRANSMIT_FREE> and <ECONET_NMI_OWNED>: set
ECONET_PROCEDURE_CALLS = %00011100  ;; <NFS_PROTECTION>'s bits for JSR, user and OS procedure calls
ECONET_STATE_HALTED = %00000100     ;; <NFS_LISTENING>: a HALT is holding this station
ECONET_ARGUMENTS = $82              ;; the offset in the NFS's workspace page where a procedure call's arguments go
;; The ROM header's machine type (1, 0) and NFS version (&60, &03), which a machine type operation replies with.
ECONET_MACHINE_TYPE_BYTES = NFS_ERROR_OFFSETS + 9

; The OS and the Tube.

ECONET_SERVICE_INTERRUPT = 5        ;; service call 5, an unrecognised interrupt
ECONET_SERVICE_NMI_CLAIM = $0C      ;; service call &0C, NMI claim
ECONET_OSBYTE_SERVICE = $8F         ;; OSBYTE &8F: issue a paged ROM service call
ECONET_OSBYTE_TUBE = $EA            ;; OSBYTE &EA: read whether a Tube is fitted
ECONET_EVENT = 8                    ;; event 8, the Econet event
ECONET_FILING_SYSTEM = 5            ;; the NFS's filing system number, which NMI claim returns in Y
ECONET_TUBE_CLAIM = $C2             ;; Tube call: claim the Tube for the Econet, claimant 2
ECONET_TUBE_RELEASE = $82           ;; Tube call: release the Econet's claim
ECONET_TUBE_WRITE = 1               ;; Tube transfer: write the second processor's memory a byte at a time
ECONET_TUBE_READ_PAIRS = 2          ;; Tube transfer: read the second processor's memory two bytes at a time
ECONET_TUBE_WRITE_PAIRS = 3         ;; Tube transfer: write the second processor's memory two bytes at a time
ECONET_NMI_OFF = STATION_ID         ;; reading the station ID register at &FE18 holds back the Econet's NMIs
ECONET_NMI_ON = VIDEO_ULA_CONTROL   ;; reading &FE20 lets the Econet's NMIs through again

; The system VIA's shift register, which the NFS borrows to turn an NMI into an IRQ.

ECONET_VIA_SHIFT = %00000100        ;; IFR and IER bit 2: the shift register's interrupt
ECONET_VIA_SHIFT_ON = %10000100     ;; IER: enable the shift register's interrupt
ECONET_VIA_SHIFT_MODE = %00011100   ;; ACR bits 2-4: the shift register's mode
ECONET_VIA_SHIFT_IN = %00001000     ;; ACR: shift in under the system clock, finishing eight clocks later

; The 68B54's control register 1. Bit 0 selects control registers 3 and 4 at the other addresses, bit 1 enables the
; receive interrupt and bit 2 the transmit interrupt, bit 5 discontinues the frame being received, and bits 6 and 7
; hold the receiver and the transmitter reset.

ADLC_CR1_QUIET = %00000000          ;; neither interrupt, nothing held reset
ADLC_CR1_RECEIVE = %10000010        ;; the transmitter reset, the receive interrupt on
ADLC_CR1_DISCONTINUE = %10100010    ;; as <ADLC_CR1_RECEIVE>, discarding the rest of the frame being received
ADLC_CR1_TRANSMIT = %01000100       ;; the receiver reset, the transmit interrupt on
ADLC_CR1_RESET = %11000001          ;; both reset, and control registers 3 and 4 selected

; The 68B54's control register 2. Bit 0 prioritises the status, bit 1 selects two-byte transfers, bit 2 sends flags
; (rather than marks) when idle, bit 3 makes status register 1's bit 6 frame complete rather than TDRA, bit 4 ends the
; frame after the data written, bits 5 and 6 clear the receive and transmit status, and bit 7 is RTS.

ADLC_CR2_IDLE = %00000111           ;; prioritised status, two-byte transfers, flag idle; RTS off
ADLC_CR2_LISTEN = %01100111         ;; as <ADLC_CR2_IDLE>, clearing the receive and transmit status
ADLC_CR2_FRAME_END = %10000100      ;; RTS on, flag idle; one-byte transfers and every status bit seen as it is
ADLC_CR2_TRANSMIT = %10100111       ;; RTS on, clearing the receive status; prioritised, two-byte, flag idle
ADLC_CR2_START = %11100111          ;; as <ADLC_CR2_TRANSMIT>, clearing the transmit status as well
ADLC_CR2_LAST_DATA = %00111111      ;; end the frame, frame complete for bit 6, clear the receive status; RTS off

; The 68B54's control registers 3 and 4, reached with control register 1's bit 0 set.

ADLC_CONTROL_3 = ADLC_CONTROL_2     ;; the 68B54's control register 3, written at <ADLC_CONTROL_2>
ADLC_CONTROL_4 = ADLC_TX_TERMINATE  ;; the 68B54's control register 4, written at <ADLC_TX_TERMINATE>
ADLC_CR3_NONE = %00000000           ;; no extended fields, no address extension, not loop mode
ADLC_CR4_8_BITS = %00011110         ;; eight-bit words for transmitting (bits 1-2) and receiving (bits 3-4)

; The 68B54's status bits the code tests. Status register 1's bit 6 (TDRA, or frame complete) and bit 7 (an
; interrupt is waiting), and status register 2's bit 7 (receive data available), are tested with BIT's overflow and
; negative flags.

ADLC_SR1_CTS = %00010000            ;; status register 1: the CTS bit, which must be set before transmitting
ADLC_SR2_ADDRESS = %00000001        ;; status register 2: address present, a frame's first byte is waiting
ADLC_SR2_FRAME_VALID = %00000010    ;; status register 2: the frame ended with a good CRC
ADLC_SR2_IDLE = %00000100           ;; status register 2: the line has gone idle
ADLC_SR2_NO_CLOCK = %00100000       ;; status register 2: DCD, set when the Econet has no clock
ADLC_SR2_DATA = %10000000           ;; status register 2: receive data available

;; One entry of a dispatch table: the low byte of a routine's address less one.
;;
;; The dispatcher pushes the high byte all the table's routines share, then this, and returns into the routine.
;; Parameters:
;;   routine = the routine
;;   page = the high byte of every routine's address less one in the table
.macro ECONET_DISPATCH routine, page
    .byte <((routine) - 1)
    .assert >((routine) - 1) = (page), "An Econet dispatch table's routine is out of its page."
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The jump table the rest of the ROM calls. The Tube host code's copy loop copies &9630-&9661 to page six with it,
; harmlessly; these run in the ROM.
; ---------------------------------------------------------------------------------------------------------------------

;; Starts transmitting the frame a transmit control block describes.
;; See: <TX_START>
ECONET_TRANSMIT:
    jmp TX_START

;; Starts the Econet: resets the 68B54, reads whether a Tube is fitted, and claims the NMI.
;; See: <INITIALISE_ECONET>
ECONET_INITIALISE:
    jmp INITIALISE_ECONET

;; The NFS's service call &0C, NMI claim: gives up the NMI once no frame is in progress.
;; See: <GIVE_UP_NMI>
NFS_SERVICE_NMI_CLAIM:
    jmp GIVE_UP_NMI

;; The NFS's service call &0B, NMI release: takes the NMI back and copies the NMI code to page &0D.
;; See: <TAKE_NMI>
NFS_SERVICE_NMI_RELEASE:
    jmp TAKE_NMI

;; Service call 5, an unrecognised interrupt: runs an immediate operation another station asked for.
;;
;; The NMI handlers cannot run a remote JSR, a procedure call, HALT or CONTINUE themselves, so <RAISE_IMMEDIATE_IRQ>
;; sets the system VIA's shift register running, and its interrupt comes here. This restores the shift register's
;; mode and turns its interrupt off, then runs the operation in <ECONET_IRQ_OPERATION> through <IRQ_OPERATIONS>.
;; A remote JSR, user procedure or OS procedure first protects the station from further ones, saving the protection
;; in <NFS_SAVED_PROTECTION> for the NFS to restore.
;; In: A = 5
;; Out: A = 0 when the interrupt was the shift register's, otherwise 5
;; Keeps: X, Y
;; See: <IRQ_OPERATIONS>, <IMMEDIATE_IRQ_DONE>
SERVICE_UNRECOGNISED_INTERRUPT:
    lda #ECONET_VIA_SHIFT
    bit SYS_VIA_IFR
    bne SERVICE_UNRECOGNISED_INTERRUPT_OURS
    lda #ECONET_SERVICE_INTERRUPT
    rts
SERVICE_UNRECOGNISED_INTERRUPT_OURS:
    txa
    pha
    tya
    pha
    lda SYS_VIA_ACR
    and #<~ECONET_VIA_SHIFT_MODE
    ora ECONET_SAVED_SHIFT_MODE     ; give the shift register its mode back
    sta SYS_VIA_ACR
    lda SYS_VIA_SR
    lda #ECONET_VIA_SHIFT
    sta SYS_VIA_IFR                 ; clear the shift register's interrupt
    sta SYS_VIA_IER                 ; and disable it
    ldy ECONET_IRQ_OPERATION
    cpy #ECONET_HALT
    bcs SERVICE_UNRECOGNISED_INTERRUPT_RUN
    lda NFS_PROTECTION           ; a JSR or procedure call: refuse others while it runs
    sta NFS_SAVED_PROTECTION
    ora #ECONET_PROCEDURE_CALLS
    sta NFS_PROTECTION
SERVICE_UNRECOGNISED_INTERRUPT_RUN:
    lda #>(RUN_JSR - 1)
    pha
    lda IRQ_OPERATIONS - ECONET_JSR,y
    pha
    rts

;; Starts the Econet: resets the 68B54, reads whether a Tube is fitted, asks the NMI's owner to give it up, and takes
;; it.
;;
;; It issues service call &0C (NMI claim) through OSBYTE &8F, then falls through into <TAKE_NMI>.
;; Uses: A, X, Y
;; See: <ECONET_INITIALISE>, <TAKE_NMI>
INITIALISE_ECONET:
    bit ECONET_NMI_OFF
    jsr RESET_ADLC
    lda #ECONET_OSBYTE_TUBE
    ldx #$00
    stx ECONET_NMI_OWNED
    ldy #$FF
    jsr OSBYTE
    stx NFS_TUBE_PRESENT
    lda #ECONET_OSBYTE_SERVICE
    ldx #ECONET_SERVICE_NMI_CLAIM
    ldy #$FF
    jsr OSBYTE

;; Takes the NMI: copies the NMI code to &0D00 and makes the Econet ready to receive.
;;
;; The NMI code is given this ROM's number, and the scout's source the station's number and network 0. The Econet is
;; free to transmit, the NFS owns the NMI, and the NMIs are let through. This is service call &0B, NMI release; it
;; takes the NMI whoever released it.
;; Out: Y = 0
;; Uses: A
;; See: <NFS_SERVICE_NMI_RELEASE>, <NFS_NMI>, <GIVE_UP_NMI>
TAKE_NMI:
    ldy #NFS_NMI_END - NFS_NMI
TAKE_NMI_COPY:
    lda NFS_NMI_IMAGE - 1,y
    sta NMI_ROUTINE - 1,y
    dey
    bne TAKE_NMI_COPY
    lda ROMSEL_COPY
    sta NFS_NMI_ROM + 1
    lda #ECONET_FREE
    sta NFS_TRANSMIT_FREE
    sta ECONET_NMI_OWNED
    lda STATION_ID
    sta ECONET_SCOUT_SOURCE
    sty ECONET_SCOUT_SOURCE + 1     ; network 0
    sty ECONET_TUBE_GUARD
    bit ECONET_NMI_ON
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Receiving a scout. These are NMI handlers, each run through <NFS_NMI> and ending through <NFS_SET_NMI_HANDLER> or
; <NFS_NMI_RETURN>.
; ---------------------------------------------------------------------------------------------------------------------

;; The NMI handler while nothing is happening: takes a scout's first byte, its destination station.
;;
;; A frame for this station, or for station &FF (marked a broadcast), goes on to <RECEIVE_SCOUT_NETWORK>; any other
;; is discontinued.
;; See: <RECEIVE_SCOUT_NETWORK>, <WAIT_FOR_SCOUT>
RECEIVE_SCOUT:
    lda #ADLC_SR2_ADDRESS
    bit ADLC_STATUS_2
    beq RECEIVE_SCOUT_ERROR
    lda ADLC_RX_DATA
    cmp STATION_ID
    beq RECEIVE_SCOUT_FOR_US
    cmp #ECONET_BROADCAST
    bne RECEIVE_SCOUT_IGNORE
    lda #ECONET_FRAME_BROADCAST
    sta ECONET_FRAME
RECEIVE_SCOUT_FOR_US:
    lda #<RECEIVE_SCOUT_NETWORK
    .assert >RECEIVE_SCOUT_NETWORK = >RECEIVE_SCOUT, "RECEIVE_SCOUT_NETWORK shares RECEIVE_SCOUT's page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for a scout's second byte, its destination network: 0 for this network, or &FF.
;;
;; Network 0 clears <ECONET_FRAME>, so a frame to station &FF is a broadcast only on network &FF. Another network's
;; frame is discontinued. The rest goes on to <RECEIVE_SCOUT_BODY>.
;; Entry: RECEIVE_SCOUT_IGNORE = discontinues the frame being received and waits for the next
;; See: <RECEIVE_SCOUT>, <RECEIVE_SCOUT_BODY>
RECEIVE_SCOUT_NETWORK:
    bit ADLC_STATUS_2
    bpl RECEIVE_SCOUT_ERROR
    lda ADLC_RX_DATA
    beq RECEIVE_SCOUT_NETWORK_LOCAL
    eor #ECONET_BROADCAST
    beq RECEIVE_SCOUT_NETWORK_START
RECEIVE_SCOUT_IGNORE:
    lda #ADLC_CR1_DISCONTINUE
    sta ADLC_CONTROL_1
    jmp WAIT_FOR_SCOUT
RECEIVE_SCOUT_NETWORK_LOCAL:
    sta ECONET_FRAME
RECEIVE_SCOUT_NETWORK_START:
    sta ECONET_INDEX                ; the scout's source goes first in ECONET_RX_SCOUT
    lda #<RECEIVE_SCOUT_BODY
    ldy #>RECEIVE_SCOUT_BODY
    jmp NFS_SET_NMI_HANDLER

;; Ends a scout that went wrong: resets the 68B54 if a byte or an address was waiting, then listens again.
;; See: <RESET_ADLC>, <END_FRAME>
RECEIVE_SCOUT_ERROR:
    lda ADLC_STATUS_2
    and #ADLC_SR2_ADDRESS | ADLC_SR2_DATA
    beq RECEIVE_SCOUT_ERROR_LISTEN
    jsr RESET_ADLC
    jmp WAIT_FOR_SCOUT
RECEIVE_SCOUT_ERROR_LISTEN:
    jmp END_FRAME_LISTEN

;; The NMI handler for the rest of a scout: reads it into <ECONET_RX_SCOUT>, two bytes at a time, then acts on it.
;;
;; At the frame's end, or after twelve bytes, it takes the last byte with the frame-valid status. It then turns the
;; receiver off and the transmitter on, ready to acknowledge, and marks the Tube unclaimed for this frame. Port 0 goes
;; to <IMMEDIATE_OPERATION>. Otherwise it looks for an open receive control block that matches: the NFS's own at
;; &00C0 while bit 7 of <NFS_LISTENING> is set, then the user's in the page <ECONET_RX_BLOCKS_PAGE>, twelve bytes
;; apiece, while bit 6 is set. A block matches when its control byte is &7F, its port is 0 or the scout's, and its
;; station is 0 or its station and network are the scout's source. A zero control byte ends the search, and so does
;; the end of the page. A broadcast drops RTS, as no acknowledgement follows.
;; Entry: RECEIVE_SCOUT_ACCEPT = sets the buffer up from the control block at <ECONET_BLOCK> and acknowledges,
;;   SEND_SCOUT_ACK = acknowledges the scout
;; See: <RECEIVE_SCOUT_NETWORK>, <SET_UP_TRANSFER>, <SCOUT_ACK_SENT>
RECEIVE_SCOUT_BODY:
    ldy ECONET_INDEX
    lda ADLC_STATUS_2
RECEIVE_SCOUT_BODY_LOOP:
    bpl RECEIVE_SCOUT_ERROR
    lda ADLC_RX_DATA
    sta ECONET_RX_SCOUT,y
    iny
    lda ADLC_STATUS_2
    bmi RECEIVE_SCOUT_BODY_SECOND
    bne RECEIVE_SCOUT_BODY_END      ; something other than data: the frame has ended
RECEIVE_SCOUT_BODY_SECOND:
    lda ADLC_RX_DATA
    sta ECONET_RX_SCOUT,y
    iny
    cpy #12
    beq RECEIVE_SCOUT_BODY_END
    sty ECONET_INDEX
    lda ADLC_STATUS_2
    bne RECEIVE_SCOUT_BODY_LOOP
    jmp NFS_NMI_RETURN
RECEIVE_SCOUT_BODY_END:
    lda #ADLC_CR1_QUIET
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_FRAME_END
    sta ADLC_CONTROL_2
    lda #ADLC_SR2_FRAME_VALID
    bit ADLC_STATUS_2
    beq RECEIVE_SCOUT_ERROR
    bpl RECEIVE_SCOUT_ERROR
    lda ADLC_RX_DATA
    sta ECONET_RX_SCOUT,y
    lda #ADLC_CR1_TRANSMIT
    sta ADLC_CONTROL_1
    sec
    ror ECONET_TUBE_GUARD
    lda ECONET_RX_PORT
    bne RECEIVE_SCOUT_PORT
    jmp IMMEDIATE_OPERATION
RECEIVE_SCOUT_PORT:
    bit ECONET_FRAME
    bvc RECEIVE_SCOUT_FIND
    lda #ADLC_CR2_IDLE              ; a broadcast: drop RTS
    sta ADLC_CONTROL_2
RECEIVE_SCOUT_FIND:
    bit NFS_LISTENING
    bpl RECEIVE_SCOUT_USER_BLOCKS
    lda #<FS_WORKSPACE              ; the NFS's own block
    ldy #>FS_WORKSPACE
RECEIVE_SCOUT_FIND_FROM:
    sta ECONET_BLOCK
    sty ECONET_BLOCK + 1
RECEIVE_SCOUT_FIND_LOOP:
    ldy #ECONET_CB_CONTROL
    lda (ECONET_BLOCK),y
    beq RECEIVE_SCOUT_NO_BLOCK
    cmp #ECONET_RX_OPEN
    bne RECEIVE_SCOUT_FIND_NEXT
    iny
    lda (ECONET_BLOCK),y
    beq RECEIVE_SCOUT_FIND_STATION ; port 0: any port
    cmp ECONET_RX_PORT
    bne RECEIVE_SCOUT_FIND_NEXT
RECEIVE_SCOUT_FIND_STATION:
    iny
    lda (ECONET_BLOCK),y
    beq RECEIVE_SCOUT_ACCEPT        ; station 0: any station
    cmp ECONET_RX_SCOUT
    bne RECEIVE_SCOUT_FIND_NEXT
    iny
    lda (ECONET_BLOCK),y
    cmp ECONET_RX_NETWORK
    beq RECEIVE_SCOUT_ACCEPT
RECEIVE_SCOUT_FIND_NEXT:
    lda ECONET_BLOCK + 1
    beq RECEIVE_SCOUT_USER_BLOCKS   ; that was the NFS's block in zero page
    lda ECONET_BLOCK
    clc
    adc #12
    sta ECONET_BLOCK
    bcc RECEIVE_SCOUT_FIND_LOOP
RECEIVE_SCOUT_NO_BLOCK:
    jmp DISCARD_FRAME
RECEIVE_SCOUT_USER_BLOCKS:
    bit NFS_LISTENING
    bvc RECEIVE_SCOUT_NO_BLOCK
    lda #$00
    ldy ECONET_RX_BLOCKS_PAGE
    bne RECEIVE_SCOUT_FIND_FROM
RECEIVE_SCOUT_ACCEPT:
    lda #ECONET_TUBE_WRITE_PAIRS
    sta ECONET_TUBE_TYPE
    jsr SET_UP_TRANSFER
    bcc DISCARD_FRAME
    bit ECONET_FRAME
    bvc SEND_SCOUT_ACK
    jmp RECEIVE_BROADCAST
SEND_SCOUT_ACK:
    lda #ADLC_CR1_TRANSMIT
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_TRANSMIT
    sta ADLC_CONTROL_2
    lda #<SCOUT_ACK_SENT
    ldy #>SCOUT_ACK_SENT
    jmp SEND_ACK

; ---------------------------------------------------------------------------------------------------------------------
; Receiving the data frame
; ---------------------------------------------------------------------------------------------------------------------

;; The NMI handler once the scout's acknowledgement has gone: turns to receiving, for the data frame.
;; See: <RECEIVE_DATA_FRAME>
SCOUT_ACK_SENT:
    lda #ADLC_CR1_RECEIVE
    sta ADLC_CONTROL_1
    lda #<RECEIVE_DATA_FRAME
    .assert >RECEIVE_DATA_FRAME = >SCOUT_ACK_SENT, "RECEIVE_DATA_FRAME shares SCOUT_ACK_SENT's page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for the data frame's first byte, which must be this station's number.
;; See: <RECEIVE_DATA_NETWORK>
RECEIVE_DATA_FRAME:
    lda #ADLC_SR2_ADDRESS
    bit ADLC_STATUS_2
    beq DISCARD_FRAME
    lda ADLC_RX_DATA
    cmp STATION_ID
    bne DISCARD_FRAME
    lda #<RECEIVE_DATA_NETWORK
    .assert >RECEIVE_DATA_NETWORK = >RECEIVE_DATA_FRAME, "RECEIVE_DATA_NETWORK shares RECEIVE_DATA_FRAME's page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for the data frame's second byte, which must be network 0, then its source and its data.
;;
;; The source's two bytes are read and not checked. The data goes to <RECEIVE_MEMORY_DATA>, or to
;; <RECEIVE_TUBE_DATA> when it goes through the Tube; each handler is run at once when the 68B54 has another interrupt
;; waiting.
;; Entry: RECEIVE_DATA_SOURCE = reads the source, RECEIVE_DATA_START = goes on to the data, as when a PEEK's or
;;   machine type's reply follows its header
;; See: <RECEIVE_DATA_FRAME>, <RECEIVE_MEMORY_DATA>, <RECEIVE_TUBE_DATA>
RECEIVE_DATA_NETWORK:
    bit ADLC_STATUS_2
    bpl DISCARD_FRAME
    lda ADLC_RX_DATA
    bne DISCARD_FRAME
    lda #<RECEIVE_DATA_SOURCE
    ldy #>RECEIVE_DATA_SOURCE
    bit ADLC_STATUS_1
    bmi RECEIVE_DATA_SOURCE
    jmp NFS_SET_NMI_HANDLER
RECEIVE_DATA_SOURCE:
    bit ADLC_STATUS_2
    bpl DISCARD_FRAME
    lda ADLC_RX_DATA
    lda ADLC_RX_DATA
RECEIVE_DATA_START:
    lda #ECONET_FRAME_TUBE
    bit ECONET_FRAME
    bne RECEIVE_DATA_START_TUBE
    lda #<RECEIVE_MEMORY_DATA
    ldy #>RECEIVE_MEMORY_DATA
    bit ADLC_STATUS_1
    bmi RECEIVE_MEMORY_DATA
    jmp NFS_SET_NMI_HANDLER
RECEIVE_DATA_START_TUBE:
    lda #<RECEIVE_TUBE_DATA
    ldy #>RECEIVE_TUBE_DATA
    jmp NFS_SET_NMI_HANDLER

;; Abandons the frame being received, or the transmission waiting for a reply.
;;
;; While <ECONET_FRAME_REPLY> is set the exchange ends as a failed transmission, with "Net Error" in the transmit
;; control block. Otherwise the 68B54 is reset and the Econet listens again.
;; Entry: DISCARD_FRAME_RESET = resets the 68B54 and ends the frame
;; See: <TX_NET_ERROR>, <END_FRAME>
DISCARD_FRAME:
    lda ECONET_FRAME
    bpl DISCARD_FRAME_RESET
    jmp TX_NET_ERROR
DISCARD_FRAME_RESET:
    jsr RESET_ADLC
    jmp END_FRAME

;; The NMI handler for a data frame's data, into memory: two bytes at a time at <ECONET_BUFFER>, Y = <ECONET_INDEX>.
;;
;; A first byte with no room left discards the frame. At the frame's end it takes the last byte with the frame-valid
;; status, if there is room, and goes on to <DATA_FRAME_RECEIVED>; a frame that is not valid is discarded.
;; Entry: RECEIVE_MEMORY_DATA_LAST_BYTE = with zero set discards the frame, otherwise stores the last byte
;; See: <SET_UP_TRANSFER>, <DATA_FRAME_RECEIVED>
RECEIVE_MEMORY_DATA:
    ldy ECONET_INDEX
    lda ADLC_STATUS_2
RECEIVE_MEMORY_DATA_LOOP:
    bpl RECEIVE_MEMORY_DATA_END
    lda ADLC_RX_DATA
    sta (ECONET_BUFFER),y
    iny
    bne RECEIVE_MEMORY_DATA_SECOND
    inc ECONET_BUFFER + 1
    dec ECONET_PAGES
    beq DISCARD_FRAME               ; no room
RECEIVE_MEMORY_DATA_SECOND:
    lda ADLC_STATUS_2
    bmi RECEIVE_MEMORY_DATA_SECOND_BYTE
    bne RECEIVE_MEMORY_DATA_END
RECEIVE_MEMORY_DATA_SECOND_BYTE:
    lda ADLC_RX_DATA
    sta (ECONET_BUFFER),y
    iny
    sty ECONET_INDEX
    bne RECEIVE_MEMORY_DATA_NEXT
    inc ECONET_BUFFER + 1
    dec ECONET_PAGES
    beq RECEIVE_MEMORY_DATA_END            ; the buffer is full
RECEIVE_MEMORY_DATA_NEXT:
    lda ADLC_STATUS_2
    bne RECEIVE_MEMORY_DATA_LOOP
    jmp NFS_NMI_RETURN
RECEIVE_MEMORY_DATA_END:
    lda #ADLC_CR2_FRAME_END
    sta ADLC_CONTROL_2
    lda #ADLC_CR1_QUIET
    sta ADLC_CONTROL_1
    sty ECONET_INDEX
    lda #ADLC_SR2_FRAME_VALID
    bit ADLC_STATUS_2
    beq DISCARD_FRAME
    bpl RECEIVE_MEMORY_DATA_DONE           ; no last byte
    lda ECONET_PAGES
RECEIVE_MEMORY_DATA_LAST_BYTE:
    beq DISCARD_FRAME
    lda ADLC_RX_DATA
    ldy ECONET_INDEX
    sta (ECONET_BUFFER),y
    inc ECONET_INDEX
    bne RECEIVE_MEMORY_DATA_DONE
    inc ECONET_BUFFER + 1
RECEIVE_MEMORY_DATA_DONE:
    jmp DATA_FRAME_RECEIVED

;; The NMI handler for a data frame's data through the Tube: two bytes at a time to register 3, counting
;; <ECONET_COUNT> up to zero.
;;
;; A first byte with no room left discards the frame. At the frame's end a last byte that came alone is kept in
;; <ECONET_ODD_BYTE>, with <ECONET_FRAME_ODD_BYTE> set, for <FINISH_TUBE_TRANSFER> to send once the two-byte transfer
;; is over; it too needs room. A frame that is not valid is discarded. Falls through into <DATA_FRAME_RECEIVED>.
;; See: <SET_UP_TRANSFER>, <COUNT_TUBE_BYTE>, <DATA_FRAME_RECEIVED>
RECEIVE_TUBE_DATA:
    lda ADLC_STATUS_2
RECEIVE_TUBE_DATA_LOOP:
    bpl RECEIVE_TUBE_DATA_END
    lda ADLC_RX_DATA
    jsr COUNT_TUBE_BYTE
    beq RECEIVE_MEMORY_DATA_LAST_BYTE      ; no room: discard
    sta TUBE_R3_DATA
    lda ADLC_RX_DATA
    sta TUBE_R3_DATA
    jsr COUNT_TUBE_BYTE
    beq RECEIVE_TUBE_DATA_END       ; the buffer is full
    lda ADLC_STATUS_2
    bne RECEIVE_TUBE_DATA_LOOP
    jmp NFS_NMI_RETURN
RECEIVE_TUBE_DATA_END:
    lda #ADLC_CR1_QUIET
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_FRAME_END
    sta ADLC_CONTROL_2
    lda #ADLC_SR2_FRAME_VALID
    bit ADLC_STATUS_2
    beq RECEIVE_MEMORY_DATA_LAST_BYTE      ; not valid: discard
    bpl DATA_FRAME_RECEIVED         ; no last byte
    lda ECONET_COUNT
    ora ECONET_COUNT + 1
    ora ECONET_COUNT + 2
    ora ECONET_COUNT + 3
    beq RECEIVE_MEMORY_DATA_LAST_BYTE      ; no room: discard
    lda ADLC_RX_DATA
    sta ECONET_ODD_BYTE
    lda #ECONET_FRAME_ODD_BYTE
    ora ECONET_FRAME
    sta ECONET_FRAME

;; Ends a data frame received: finishes a PEEK's or machine type's reply, or sends the final acknowledgement.
;;
;; A reply ends the transmission that asked for it, with the transmit control block's end address set to the
;; address after the last byte received.
;; Entry: SEND_FINAL_ACK = sends the final acknowledgement
;; See: <FINISH_TUBE_TRANSFER>, <TX_SUCCEEDED>, <FINAL_ACK_SENT>
DATA_FRAME_RECEIVED:
    lda ECONET_FRAME
    bpl SEND_FINAL_ACK
    jsr FINISH_TUBE_TRANSFER
    jmp TX_SUCCEEDED
SEND_FINAL_ACK:
    lda #ADLC_CR1_TRANSMIT
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_TRANSMIT
    sta ADLC_CONTROL_2
    lda #<FINAL_ACK_SENT
    ldy #>FINAL_ACK_SENT

;; Starts an acknowledgement, or a reply in its place: sends the received scout's source as the frame's destination.
;;
;; The 68B54 must already be set to transmit. The next NMI sends this station's number and network 0
;; (<SEND_ACK_SOURCE>). A frame that already went wrong is discarded.
;; In: A/Y = the NMI handler to install once the frame has ended, low byte in A
;; See: <SEND_ACK_SOURCE>, <ECONET_AFTER_ACK>
SEND_ACK:
    sta ECONET_AFTER_ACK
    sty ECONET_AFTER_ACK + 1
    lda ECONET_RX_SCOUT
    bit ADLC_STATUS_1
    bvc SEND_ACK_FAILED             ; no room to transmit
    sta ADLC_TX_CONTINUE
    lda ECONET_RX_NETWORK
    sta ADLC_TX_CONTINUE
    lda #<SEND_ACK_SOURCE
    ldy #>SEND_ACK_SOURCE
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler that sends an acknowledgement's source, this station and network 0, and ends the frame.
;;
;; A reply (<ECONET_FRAME_REPLY>) goes on to send its data instead. Otherwise the frame ends after these bytes, and the
;; handler <SEND_ACK> was given is installed.
;; Entry: SEND_ACK_FAILED = discards the frame
;; See: <SEND_ACK>, <SEND_DATA_START>
SEND_ACK_SOURCE:
    lda STATION_ID
    bit ADLC_STATUS_1
    bvc SEND_ACK_FAILED
    sta ADLC_TX_CONTINUE
    lda #$00
    sta ADLC_TX_CONTINUE
    lda ECONET_FRAME
    bmi SEND_ACK_REPLY
    lda #ADLC_CR2_LAST_DATA
    sta ADLC_CONTROL_2
    lda ECONET_AFTER_ACK
    ldy ECONET_AFTER_ACK + 1
    jmp NFS_SET_NMI_HANDLER
SEND_ACK_REPLY:
    jmp SEND_DATA_START
SEND_ACK_FAILED:
    jmp DISCARD_FRAME

;; Ends a data transfer through the Tube: sets the control block's end address and sends a last odd byte.
;;
;; The end address becomes the address after the last byte transferred. A byte kept in <ECONET_ODD_BYTE> is then
;; written to the second processor with a one-byte transfer at that address, and the end address moved past it.
;; In: ECONET_BLOCK = the control block, ECONET_COUNT = as the transfer left it
;; Out: A = &FF and zero clear after a Tube transfer; zero set when the data was not for the Tube
;; Keeps: X
;; See: <SET_UP_TRANSFER>, <RECEIVE_TUBE_DATA>
FINISH_TUBE_TRANSFER:
    lda #ECONET_FRAME_TUBE
    bit ECONET_FRAME
    beq FINISH_TUBE_TRANSFER_DONE
    clc
    php
    ldy #ECONET_CB_END
FINISH_TUBE_TRANSFER_END:
    lda (ECONET_BLOCK),y
    plp
    adc a:ECONET_COUNT - ECONET_CB_END,y
    sta (ECONET_BLOCK),y
    iny
    php
    cpy #ECONET_CB_END + 4
    bcc FINISH_TUBE_TRANSFER_END
    plp
    lda #ECONET_FRAME_ODD_BYTE
    bit ECONET_FRAME
    beq FINISH_TUBE_TRANSFER_TUBE
    txa
    pha
    lda #ECONET_CB_END
    clc
    adc ECONET_BLOCK
    tax
    ldy ECONET_BLOCK + 1
    lda #ECONET_TUBE_WRITE
    jsr TUBE_TRANSFER
    lda ECONET_ODD_BYTE
    sta TUBE_R3_DATA
    sec
    ldy #ECONET_CB_END
FINISH_TUBE_TRANSFER_STEP:
    lda #$00
    adc (ECONET_BLOCK),y
    sta (ECONET_BLOCK),y
    iny
    bcs FINISH_TUBE_TRANSFER_STEP
    pla
    tax
FINISH_TUBE_TRANSFER_TUBE:
    lda #$FF
FINISH_TUBE_TRANSFER_DONE:
    rts

;; The NMI handler once the final acknowledgement has gone: completes the reception.
;;
;; A frame to a port, and a POKE, are complete; a remote JSR or procedure call goes on to <PROCEDURE_RECEIVED>.
;; See: <COMPLETE_RECEPTION>, <PROCEDURE_RECEIVED>
FINAL_ACK_SENT:
    lda ECONET_RX_PORT
    bne COMPLETE_RECEPTION
    ldy ECONET_RX_CONTROL
    cpy #ECONET_POKE
    beq COMPLETE_RECEPTION
    jmp PROCEDURE_RECEIVED

;; Completes a reception: fills in the receive control block, then ends the frame.
;;
;; The block's end address becomes the address after the last byte received. For a port, its control byte gets the
;; scout's with bit 7 set, and its port, station and network the scout's.
;; In: ECONET_BLOCK = the receive control block
;; See: <FINISH_TUBE_TRANSFER>, <END_FRAME>
COMPLETE_RECEPTION:
    jsr FINISH_TUBE_TRANSFER
    bne COMPLETE_RECEPTION_BLOCK
    lda ECONET_INDEX
    clc
    adc ECONET_BUFFER
    bcc COMPLETE_RECEPTION_END
    inc ECONET_BUFFER + 1
COMPLETE_RECEPTION_END:
    ldy #ECONET_CB_END
    sta (ECONET_BLOCK),y
    iny
    lda ECONET_BUFFER + 1
    sta (ECONET_BLOCK),y
COMPLETE_RECEPTION_BLOCK:
    lda ECONET_RX_PORT
    beq END_FRAME
    lda ECONET_RX_NETWORK
    ldy #ECONET_CB_NETWORK
    sta (ECONET_BLOCK),y
    dey
    lda ECONET_RX_SCOUT
    sta (ECONET_BLOCK),y
    dey
    lda ECONET_RX_PORT
    sta (ECONET_BLOCK),y
    dey
    lda ECONET_RX_CONTROL
    ora #%10000000                  ; marks the block as received
    sta (ECONET_BLOCK),y

;; Ends a frame: releases the Tube if this frame used it, sets the 68B54 listening, and waits for the next scout.
;;
;; Runs within an NMI, returning from it; it is also installed as a handler, to run when a reply has gone.
;; Entry: END_FRAME_LISTEN = only sets the 68B54 listening and waits, WAIT_FOR_SCOUT = only waits
;; See: <RECEIVE_SCOUT>, <RELEASE_TUBE>, <SET_ADLC_LISTENING>
END_FRAME:
    lda #ECONET_FRAME_TUBE
    and NFS_TUBE_PRESENT
    bit ECONET_FRAME
    beq END_FRAME_LISTEN
    jsr RELEASE_TUBE
END_FRAME_LISTEN:
    jsr SET_ADLC_LISTENING
WAIT_FOR_SCOUT:
    lda #<RECEIVE_SCOUT
    ldy #>RECEIVE_SCOUT
    jmp NFS_SET_NMI_HANDLER

;; Receives a broadcast: copies the eight bytes the scout carried to the receive block's buffer, then completes.
;;
;; A buffer too small for all eight discards the frame.
;; In: ECONET_BLOCK = the receive control block, its buffer set up by <SET_UP_TRANSFER>
;; See: <COMPLETE_RECEPTION>
RECEIVE_BROADCAST:
    txa
    pha
    ldx #4                          ; from ECONET_RX_EXTRA
    lda #ECONET_FRAME_TUBE
    bit ECONET_FRAME
    bne RECEIVE_BROADCAST_TUBE
    ldy ECONET_INDEX
RECEIVE_BROADCAST_LOOP:
    lda ECONET_RX_SCOUT,x
    sta (ECONET_BUFFER),y
    iny
    bne RECEIVE_BROADCAST_NEXT
    inc ECONET_BUFFER + 1
    dec ECONET_PAGES
    beq RECEIVE_BROADCAST_FULL
RECEIVE_BROADCAST_NEXT:
    inx
    sty ECONET_INDEX
    cpx #12
    bne RECEIVE_BROADCAST_LOOP
RECEIVE_BROADCAST_DONE:
    pla
    tax
    jmp COMPLETE_RECEPTION
RECEIVE_BROADCAST_TUBE:
    lda ECONET_RX_SCOUT,x
    sta TUBE_R3_DATA
    jsr COUNT_TUBE_BYTE
    beq RECEIVE_BROADCAST_TUBE_FULL
    inx
    cpx #12
    bne RECEIVE_BROADCAST_TUBE
    beq RECEIVE_BROADCAST_DONE

;; Releases the Tube, unless bit 7 of <ECONET_TUBE_GUARD> is set; either way clears that bit.
;;
;; Each frame sets the bit as it starts, and <SET_UP_TRANSFER> calls this once after claiming the Tube, which only
;; clears it. So <END_FRAME> releases the Tube only when this frame claimed it.
;; Uses: A
;; Keeps: X, Y
RELEASE_TUBE:
    bit ECONET_TUBE_GUARD
    bmi RELEASE_TUBE_DONE
    lda #ECONET_TUBE_RELEASE
    jsr TUBE_TRANSFER
RELEASE_TUBE_DONE:
    lsr ECONET_TUBE_GUARD
    rts

;; Counts a byte through the Tube: adds one to the four bytes of <ECONET_COUNT>.
;; Out: zero = the count has reached 0, so the buffer is full
;; Keeps: A, X, Y
COUNT_TUBE_BYTE:
    inc ECONET_COUNT
    bne COUNT_TUBE_BYTE_DONE
    inc ECONET_COUNT + 1
    bne COUNT_TUBE_BYTE_DONE
    inc ECONET_COUNT + 2
    bne COUNT_TUBE_BYTE_DONE
    inc ECONET_COUNT + 3
COUNT_TUBE_BYTE_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Receiving an immediate operation
; ---------------------------------------------------------------------------------------------------------------------

;; Acts on a scout to port 0, an immediate operation, through <RX_OPERATIONS>.
;;
;; A control byte outside &81-&88 is discarded. PEEK, POKE, JSR, the procedure calls and HALT are refused, and the
;; Econet listens again, when their bit of <NFS_PROTECTION> is set; CONTINUE and the machine type are always
;; answered.
;; Entry: RECEIVE_BROADCAST_FULL = ends a broadcast whose buffer filled, RECEIVE_BROADCAST_TUBE_FULL = the same
;;   through the Tube, IMMEDIATE_REFUSED = discards the frame
;; See: <RX_OPERATIONS>, <RECEIVE_SCOUT_BODY>
IMMEDIATE_OPERATION:
    ldy ECONET_RX_CONTROL
    cpy #ECONET_PEEK
    bcc IMMEDIATE_REFUSED
    cpy #ECONET_MACHINE_TYPE + 1
    bcs IMMEDIATE_REFUSED
    cpy #ECONET_CONTINUE
    bcs IMMEDIATE_OPERATION_RUN
    tya
    sec
    sbc #ECONET_PEEK
    tay
    lda NFS_PROTECTION
IMMEDIATE_OPERATION_PROTECTED:
    ror a
    dey
    bpl IMMEDIATE_OPERATION_PROTECTED
    bcs END_FRAME_LISTEN            ; protected: ignore it
IMMEDIATE_OPERATION_RUN:
    ldy ECONET_RX_CONTROL
    lda #>(RECEIVE_PROCEDURE_CALL - 1)
    pha
    lda RX_OPERATIONS - ECONET_PEEK,y
    pha
    rts
RECEIVE_BROADCAST_FULL:
    inc ECONET_INDEX
RECEIVE_BROADCAST_TUBE_FULL:
    cpx #11
    beq RECEIVE_BROADCAST_DONE      ; that was the last byte
    pla
    tax
IMMEDIATE_REFUSED:
    jmp DISCARD_FRAME

;; The routines that receive each immediate operation, &81-&88, as the low bytes of their addresses less one.
;; See: <IMMEDIATE_OPERATION>
RX_OPERATIONS:
    ECONET_DISPATCH RECEIVE_PEEK, >(RECEIVE_PROCEDURE_CALL - 1)             ; &81 PEEK
    ECONET_DISPATCH RECEIVE_POKE, >(RECEIVE_PROCEDURE_CALL - 1)             ; &82 POKE
    ECONET_DISPATCH RECEIVE_PROCEDURE_CALL, >(RECEIVE_PROCEDURE_CALL - 1)   ; &83 JSR
    ECONET_DISPATCH RECEIVE_PROCEDURE_CALL, >(RECEIVE_PROCEDURE_CALL - 1)   ; &84 user procedure
    ECONET_DISPATCH RECEIVE_PROCEDURE_CALL, >(RECEIVE_PROCEDURE_CALL - 1)   ; &85 OS procedure
    ECONET_DISPATCH RECEIVE_HALT, >(RECEIVE_PROCEDURE_CALL - 1)             ; &86 HALT
    ECONET_DISPATCH RECEIVE_HALT, >(RECEIVE_PROCEDURE_CALL - 1)             ; &87 CONTINUE
    ECONET_DISPATCH RECEIVE_MACHINE_TYPE, >(RECEIVE_PROCEDURE_CALL - 1)     ; &88 machine type

;; Receives a remote JSR, user procedure or OS procedure call: keeps its address and takes the arguments.
;;
;; The arguments go to offset &82 of the page <NFS_WORKSPACE_PAGE> points into, up to the page's end, and the scout's
;; four further bytes to <ECONET_PROCEDURE_ADDRESS>. Then it acknowledges the scout.
;; See: <PROCEDURE_RECEIVED>, <SEND_SCOUT_ACK>
RECEIVE_PROCEDURE_CALL:
    lda #$00
    sta ECONET_BUFFER
    lda #ECONET_ARGUMENTS
    sta ECONET_INDEX
    lda #1
    sta ECONET_PAGES
    lda NFS_WORKSPACE_PAGE + 1
    sta ECONET_BUFFER + 1
    ldy #3
RECEIVE_PROCEDURE_CALL_ADDRESS:
    lda ECONET_RX_EXTRA,y
    sta ECONET_PROCEDURE_ADDRESS,y
    dey
    bpl RECEIVE_PROCEDURE_CALL_ADDRESS
    jmp SEND_SCOUT_ACK

;; Receives a POKE: the scout's further bytes, laid out as a control block's start and end addresses, say where the
;; data goes.
;; See: <RECEIVE_SCOUT_ACCEPT>
RECEIVE_POKE:
    lda #<ECONET_RX_SCOUT
    sta ECONET_BLOCK
    lda #>ECONET_RX_SCOUT
    sta ECONET_BLOCK + 1
    jmp RECEIVE_SCOUT_ACCEPT

;; Receives a request for the machine type: replies with the four bytes at <ECONET_MACHINE_TYPE_BYTES>.
;; See: <SEND_REPLY>
RECEIVE_MACHINE_TYPE:
    lda #1
    sta ECONET_PAGES
    lda #$100 - 4                   ; four bytes before the end at offset 0
    sta ECONET_INDEX
    lda #<(ECONET_MACHINE_TYPE_BYTES + 4 - $100)
    sta ECONET_BUFFER
    lda #>(ECONET_MACHINE_TYPE_BYTES + 4 - $100)
    sta ECONET_BUFFER + 1
    bne SEND_REPLY

;; Receives a PEEK: replies with the memory between the start and end addresses the scout's further bytes give.
;;
;; A PEEK of the second processor's memory that cannot claim the Tube is ignored.
;; Entry: SEND_REPLY = replies with the data <ECONET_BUFFER> describes, RECEIVE_HALT = acknowledges a HALT or
;;   CONTINUE, which <SERVICE_UNRECOGNISED_INTERRUPT> then runs
;; See: <SET_UP_TRANSFER>, <SEND_ACK>, <RAISE_IMMEDIATE_IRQ>
RECEIVE_PEEK:
    lda #<ECONET_RX_SCOUT
    sta ECONET_BLOCK
    lda #>ECONET_RX_SCOUT
    sta ECONET_BLOCK + 1
    lda #ECONET_TUBE_READ_PAIRS
    sta ECONET_TUBE_TYPE
    jsr SET_UP_TRANSFER
    bcc IMMEDIATE_DONE
SEND_REPLY:
    lda ECONET_FRAME
    ora #ECONET_FRAME_REPLY
    sta ECONET_FRAME
RECEIVE_HALT:
    lda #ADLC_CR1_TRANSMIT
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_TRANSMIT
    sta ADLC_CONTROL_2
    lda #<RAISE_IMMEDIATE_IRQ
    ldy #>RAISE_IMMEDIATE_IRQ
    jmp SEND_ACK

;; Finishes receiving a remote JSR or procedure call, then has <SERVICE_UNRECOGNISED_INTERRUPT> run it.
;;
;; Just before the arguments, at offsets &7F-&81 from <NFS_WORKSPACE_PAGE>, it stores the number of argument bytes plus
;; two, and the caller's station and network.
;; See: <RECEIVE_PROCEDURE_CALL>, <RAISE_IMMEDIATE_IRQ>
PROCEDURE_RECEIVED:
    lda ECONET_INDEX
    clc
    adc #$100 - (ECONET_ARGUMENTS - 2)
    ldy #ECONET_ARGUMENTS - 3
    sta (NFS_WORKSPACE_PAGE),y
    ldy #ECONET_ARGUMENTS - 2
    lda ECONET_RX_SCOUT
    sta (NFS_WORKSPACE_PAGE),y
    iny
    lda ECONET_RX_NETWORK
    sta (NFS_WORKSPACE_PAGE),y

;; Hands an immediate operation to the foreground: keeps its control byte and starts the system VIA's shift register,
;; whose interrupt follows eight clocks later.
;;
;; The shift register's mode is saved in <ECONET_SAVED_SHIFT_MODE> and its interrupt enabled; reading the shift
;; register starts it. <SERVICE_UNRECOGNISED_INTERRUPT> takes the interrupt. Runs as an NMI handler after a HALT's or
;; CONTINUE's acknowledgement, and ends by listening for the next scout.
;; Entry: IMMEDIATE_DONE = listens for the next scout
;; See: <SERVICE_UNRECOGNISED_INTERRUPT>, <END_FRAME>
RAISE_IMMEDIATE_IRQ:
    lda ECONET_RX_CONTROL
    sta ECONET_IRQ_OPERATION
    lda #ECONET_VIA_SHIFT_ON
    sta SYS_VIA_IER
    lda SYS_VIA_ACR
    and #ECONET_VIA_SHIFT_MODE
    sta ECONET_SAVED_SHIFT_MODE
    lda SYS_VIA_ACR
    and #<~ECONET_VIA_SHIFT_MODE
    ora #ECONET_VIA_SHIFT_IN
    sta SYS_VIA_ACR
    bit SYS_VIA_SR                  ; start shifting
IMMEDIATE_DONE:
    jmp END_FRAME_LISTEN

;; The routines that run immediate operations &83-&87 in the foreground, as the low bytes of their addresses less one.
;; See: <SERVICE_UNRECOGNISED_INTERRUPT>
IRQ_OPERATIONS:
    ECONET_DISPATCH RUN_JSR, >(RUN_JSR - 1)                                 ; &83 JSR
    ECONET_DISPATCH RUN_USER_PROCEDURE, >(RUN_JSR - 1)                      ; &84 user procedure
    ECONET_DISPATCH RUN_OS_PROCEDURE, >(RUN_JSR - 1)                        ; &85 OS procedure
    ECONET_DISPATCH RUN_HALT, >(RUN_JSR - 1)                                ; &86 HALT
    ECONET_DISPATCH RUN_CONTINUE, >(RUN_JSR - 1)                            ; &87 CONTINUE

;; Runs a remote JSR: calls the address another station gave, which returns to <IMMEDIATE_IRQ_DONE>.
;; In: ECONET_PROCEDURE_ADDRESS = the address
RUN_JSR:
    lda #>(IMMEDIATE_IRQ_DONE - 1)
    pha
    lda #<(IMMEDIATE_IRQ_DONE - 1)
    pha
    jmp (ECONET_PROCEDURE_ADDRESS)

;; Runs a user procedure call: raises event 8, the Econet event, with the address another station gave in X and A.
;; In: ECONET_PROCEDURE_ADDRESS = the address: X gets its low byte and A the next
;; See: <IMMEDIATE_IRQ_DONE>
RUN_USER_PROCEDURE:
    ldy #ECONET_EVENT
    ldx ECONET_PROCEDURE_ADDRESS
    lda ECONET_PROCEDURE_ADDRESS + 1
    jsr OSEVEN
    jmp IMMEDIATE_IRQ_DONE

;; Runs an OS procedure call: calls the ROM's language entry, <NFS_LANGUAGE_ENTRY>, which runs the NFS's OS procedure X.
;; In: ECONET_PROCEDURE_ADDRESS = the procedure's number, for X, and a byte for Y
;; See: <IMMEDIATE_IRQ_DONE>
RUN_OS_PROCEDURE:
    ldx ECONET_PROCEDURE_ADDRESS
    ldy ECONET_PROCEDURE_ADDRESS + 1
    jsr NFS_LANGUAGE_ENTRY
    jmp IMMEDIATE_IRQ_DONE

;; Runs a HALT: marks the station halted and waits, with interrupts enabled, until a CONTINUE clears the mark.
;;
;; A HALT while halted does nothing. The CONTINUE arrives as another interrupt, which <RUN_CONTINUE> handles.
;; See: <RUN_CONTINUE>, <IMMEDIATE_IRQ_DONE>
RUN_HALT:
    lda #ECONET_STATE_HALTED
    bit NFS_LISTENING
    bne IMMEDIATE_IRQ_DONE
    ora NFS_LISTENING
    sta NFS_LISTENING
    lda #ECONET_STATE_HALTED
    cli
RUN_HALT_WAIT:
    bit NFS_LISTENING
    bne RUN_HALT_WAIT
    beq IMMEDIATE_IRQ_DONE

;; Runs a CONTINUE: clears the halted mark, letting a waiting <RUN_HALT> go on.
;; See: <RUN_HALT>
RUN_CONTINUE:
    lda NFS_LISTENING
    and #<~ECONET_STATE_HALTED
    sta NFS_LISTENING

;; Ends an immediate operation run in the foreground: restores Y and X, which
;; <SERVICE_UNRECOGNISED_INTERRUPT> pushed, and claims the interrupt.
;; Out: A = 0, the service call claimed
IMMEDIATE_IRQ_DONE:
    pla
    tay
    pla
    tax
    lda #$00
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Transmitting
; ---------------------------------------------------------------------------------------------------------------------

;; Starts transmitting the exchange a transmit control block describes, and returns once the scout has begun.
;;
;; The caller has taken <NFS_TRANSMIT_FREE>. The scout's destination, control byte and port come from the block. For an
;; immediate operation its further bytes are the remote address and, for PEEK and POKE, the remote end address, the
;; remote address plus the buffer's length; the scout's length and the exchange's flags come from <SCOUT_LENGTHS> and
;; <IMMEDIATE_FLAGS>. It then waits for the line: with the clock present, it waits for the 68B54 to see the line idle
;; and its CTS bit set, with NMIs held back, trying &30000 times. With the line taken, the scout is sent by the NMI
;; handler <SEND_SCOUT>, while this sets up the data through <TX_OPERATIONS> or for a port. The NMI handlers finish
;; the exchange and put the result in the block's control byte, freeing <NFS_TRANSMIT_FREE>. A result found here goes
;; in at once: &44 for a bad control byte, &43 "No Clock", or &40 "Line Jammed".
;; In: ECONET_TX_BLOCK = the transmit control block
;; Keeps: X
;; See: <ECONET_TRANSMIT>, <SEND_SCOUT>, <TX_OPERATIONS>
TX_START:
    txa
    pha
    ldy #ECONET_CB_STATION
    lda (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT
    iny
    lda (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_NETWORK
    ldy #ECONET_CB_CONTROL
    lda (ECONET_TX_BLOCK),y
    bmi TX_CONTROL
    jmp TX_BAD_CONTROL
TX_CONTROL:
    sta ECONET_SCOUT_CONTROL
    tax
    iny
    lda (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_PORT
    bne TX_WAIT
    cpx #ECONET_JSR
    bcs TX_IMMEDIATE
    sec                             ; PEEK and POKE: the end address less the start, the length
    php
    ldy #ECONET_CB_END
TX_LENGTH:
    lda (ECONET_TX_BLOCK),y
    dey
    dey
    dey
    dey
    plp
    sbc (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_END - ECONET_CB_START,y
    iny
    iny
    iny
    iny
    iny
    php
    cpy #ECONET_CB_END + 4
    bcc TX_LENGTH
    plp
TX_IMMEDIATE:
    cpx #ECONET_PEEK
    bcc TX_BAD_CONTROL
    cpx #ECONET_MACHINE_TYPE + 1
    bcs TX_BAD_CONTROL
    ldy #ECONET_CB_REMOTE
TX_REMOTE:
    lda (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_ADDRESS - ECONET_CB_REMOTE,y
    iny
    cpy #ECONET_CB_REMOTE + 4
    bcc TX_REMOTE
TX_WAIT:
    lda #ADLC_SR2_NO_CLOCK
    bit ADLC_STATUS_2
    bne TX_NO_CLOCK
    lda #$FD                        ; a three-byte count on the stack, &FD0000 up to &1000000
    pha
    lda #ECONET_HEADER
    sta ECONET_SCOUT_LENGTH
    lda #$00
    sta ECONET_SCOUT_INDEX
    pha
    pha
    ldy #ADLC_CR2_START
TX_WAIT_LOOP:
    lda #ADLC_SR2_IDLE
    php
    sei
    bit ECONET_NMI_OFF
    bit ECONET_NMI_OFF
    bit ADLC_STATUS_2
    beq TX_WAIT_AGAIN         ; the line is busy
    lda ADLC_STATUS_1
    lda #ADLC_CR2_LISTEN
    sta ADLC_CONTROL_2
    lda #ADLC_SR1_CTS
    bit ADLC_STATUS_1
    bne TX_LINE_TAKEN
TX_WAIT_AGAIN:
    bit ECONET_NMI_ON
    plp
    tsx
    inc STACK + 1,x
    bne TX_WAIT_LOOP
    inc STACK + 2,x
    bne TX_WAIT_LOOP
    inc STACK + 3,x
    bne TX_WAIT_LOOP
    beq TX_JAMMED
TX_BAD_CONTROL:
    lda #ECONET_BAD_CONTROL
    bne TX_RESULT
TX_JAMMED:
    lda #ADLC_CR2_IDLE
    sta ADLC_CONTROL_2
    pla
    pla
    pla
    lda #ECONET_LINE_JAMMED
    bne TX_RESULT
TX_NO_CLOCK:
    lda #ECONET_NO_CLOCK
TX_RESULT:
    ldy #ECONET_CB_CONTROL
    sta (ECONET_TX_BLOCK),y
    lda #ECONET_FREE
    sta NFS_TRANSMIT_FREE
    pla
    tax
    rts
TX_LINE_TAKEN:
    sty ADLC_CONTROL_2              ; ADLC_CR2_START: RTS on
    ldx #ADLC_CR1_TRANSMIT
    stx ADLC_CONTROL_1
    ldx #<SEND_SCOUT
    ldy #>SEND_SCOUT
    stx NFS_NMI_JUMP + 1
    sty NFS_NMI_JUMP + 2
    sec
    ror ECONET_TUBE_GUARD
    bit ECONET_NMI_ON
    lda ECONET_SCOUT_PORT
    bne TX_PORT
    ldy ECONET_SCOUT_CONTROL
    lda IMMEDIATE_FLAGS - ECONET_PEEK,y
    sta ECONET_FRAME
    lda SCOUT_LENGTHS - ECONET_PEEK,y
    sta ECONET_SCOUT_LENGTH
    lda #>(TX_MACHINE_TYPE - 1)
    pha
    lda TX_OPERATIONS - ECONET_PEEK,y
    pha
    rts

;; The routines that set up the data for transmitting each immediate operation, &81-&88, as the low bytes of their
;; addresses less one.
;; See: <TX_START>
TX_OPERATIONS:
    ECONET_DISPATCH TX_PEEK, >(TX_MACHINE_TYPE - 1)             ; &81 PEEK
    ECONET_DISPATCH TX_POKE, >(TX_MACHINE_TYPE - 1)             ; &82 POKE
    ECONET_DISPATCH TX_PROCEDURE_CALL, >(TX_MACHINE_TYPE - 1)   ; &83 JSR
    ECONET_DISPATCH TX_PROCEDURE_CALL, >(TX_MACHINE_TYPE - 1)   ; &84 user procedure
    ECONET_DISPATCH TX_PROCEDURE_CALL, >(TX_MACHINE_TYPE - 1)   ; &85 OS procedure
    ECONET_DISPATCH TX_RETURN, >(TX_MACHINE_TYPE - 1)           ; &86 HALT: no data
    ECONET_DISPATCH TX_RETURN, >(TX_MACHINE_TYPE - 1)           ; &87 CONTINUE: no data
    ECONET_DISPATCH TX_MACHINE_TYPE, >(TX_MACHINE_TYPE - 1)     ; &88 machine type

;; Sets up for a machine type request: the reply comes to the transmit control block's buffer.
;;
;; The routines from here to <TX_RETURN> end <TX_START>, with its saved X and status on the stack.
;; Entry: TX_PEEK = sets up a PEEK, whose reply comes to the buffer, TX_POKE = sets up a POKE, sending the
;;   buffer, TX_PORT = sets up a frame to a port, TX_PROCEDURE_CALL = sets up a remote JSR or procedure
;;   call, sending the buffer as its arguments, TX_RETURN = returns from <TX_START>
;; See: <TX_OPERATIONS>, <SET_UP_TRANSFER>
TX_MACHINE_TYPE:
    lda #ECONET_TUBE_WRITE_PAIRS
    bne TX_TUBE_TYPE
TX_PEEK:
    lda #ECONET_TUBE_WRITE_PAIRS
    bne TX_REMOTE_END
TX_POKE:
    lda #ECONET_TUBE_READ_PAIRS
TX_REMOTE_END:
    sta ECONET_TUBE_TYPE
    clc                             ; the remote end address: the remote address plus the length
    php
    ldy #ECONET_CB_REMOTE
TX_REMOTE_END_LOOP:
    lda ECONET_SCOUT_END - ECONET_CB_REMOTE,y
    plp
    adc (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_END - ECONET_CB_REMOTE,y
    iny
    php
    cpy #ECONET_CB_REMOTE + 4
    bcc TX_REMOTE_END_LOOP
    plp
    bne TX_BUFFER             ; always: zero is clear from INY
TX_PORT:
    lda ECONET_SCOUT
    and ECONET_SCOUT_NETWORK
    cmp #ECONET_BROADCAST
    bne TX_PORT_DATA
    lda #ECONET_HEADER + 8          ; a broadcast: the scout carries the block's bytes 4-11 as its data
    sta ECONET_SCOUT_LENGTH
    lda #ECONET_FRAME_BROADCAST
    sta ECONET_FRAME
    ldy #ECONET_CB_START
TX_BROADCAST_DATA:
    lda (ECONET_TX_BLOCK),y
    sta ECONET_SCOUT_ADDRESS - ECONET_CB_START,y
    iny
    cpy #ECONET_CB_START + 8
    bcc TX_BROADCAST_DATA
    bcs TX_RETURN
TX_PORT_DATA:
    lda #$00
    sta ECONET_FRAME
TX_PROCEDURE_CALL:
    lda #ECONET_TUBE_READ_PAIRS
TX_TUBE_TYPE:
    sta ECONET_TUBE_TYPE
TX_BUFFER:
    lda ECONET_TX_BLOCK
    sta ECONET_BLOCK
    lda ECONET_TX_BLOCK + 1
    sta ECONET_BLOCK + 1
    jsr SET_UP_TRANSFER
TX_RETURN:
    plp
    pla
    pla
    pla
    pla
    tax
    rts

;; The NMI handler that sends the scout from <ECONET_SCOUT>, two bytes at a time, then ends the frame.
;;
;; A transmitter with no room for more fails the transmission with "Net Error".
;; Entry: NOT_LISTENING = fails the transmission with "Not listening", TX_FAILED = fails it with the result in
;;   A, after a delay that is different for each station
;; See: <TX_START>, <SCOUT_SENT>, <TX_DONE>
SEND_SCOUT:
    ldy ECONET_SCOUT_INDEX
    bit ADLC_STATUS_1
SEND_SCOUT_LOOP:
    bvc SEND_SCOUT_UNDERRUN
    lda ECONET_SCOUT,y
    sta ADLC_TX_CONTINUE
    iny
    lda ECONET_SCOUT,y
    iny
    sty ECONET_SCOUT_INDEX
    sta ADLC_TX_CONTINUE
    cpy ECONET_SCOUT_LENGTH
    bcs SEND_SCOUT_LAST
    bit ADLC_STATUS_1
    bmi SEND_SCOUT_LOOP
    jmp NFS_NMI_RETURN
NOT_LISTENING:
    lda #ECONET_NOT_LISTENING
    bne TX_FAILED
SEND_SCOUT_UNDERRUN:
    lda #ADLC_CR2_LISTEN
    sta ADLC_CONTROL_2
    lda #ECONET_NET_ERROR
TX_FAILED:
    ldy STATION_ID                  ; wait about 12 cycles for each station number above this one's
TX_FAILED_DELAY:
    pha
    pla
    iny
    bne TX_FAILED_DELAY
    jmp TX_DONE
SEND_SCOUT_LAST:
    lda #ADLC_CR2_LAST_DATA
    sta ADLC_CONTROL_2
    lda #<SCOUT_SENT
    ldy #>SCOUT_SENT
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler once the scout has gone: turns to receiving its acknowledgement.
;;
;; A broadcast has succeeded. A HALT or CONTINUE, and a PEEK or machine type, wait for the frame that ends the
;; exchange; anything else waits for the scout's acknowledgement.
;; See: <RECEIVE_SCOUT_ACK>, <WAIT_FOR_FINAL_ACK>
SCOUT_SENT:
    lda #ADLC_CR1_RECEIVE
    sta ADLC_CONTROL_1
    bit ECONET_FRAME
    bvc SCOUT_SENT_NOT_BROADCAST
    jmp TX_SUCCEEDED
SCOUT_SENT_NOT_BROADCAST:
    lda #ECONET_FRAME_TWO_WAY
    bit ECONET_FRAME
    beq SCOUT_SENT_ACK
    jmp WAIT_FOR_FINAL_ACK
SCOUT_SENT_ACK:
    lda #<RECEIVE_SCOUT_ACK
    .assert >RECEIVE_SCOUT_ACK = >SCOUT_SENT, "RECEIVE_SCOUT_ACK shares SCOUT_SENT's page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for the scout acknowledgement's first byte, which must be this station's number.
;;
;; No frame at all means no station took the scout: "Not listening".
;; See: <RECEIVE_SCOUT_ACK_NETWORK>
RECEIVE_SCOUT_ACK:
    lda #ADLC_SR2_ADDRESS
    bit ADLC_STATUS_2
    beq NOT_LISTENING
    lda ADLC_RX_DATA
    cmp STATION_ID
    bne RECEIVE_SCOUT_ACK_FAILED
    lda #<RECEIVE_SCOUT_ACK_NETWORK
    .assert >RECEIVE_SCOUT_ACK_NETWORK = >RECEIVE_SCOUT_ACK, "RECEIVE_SCOUT_ACK_NETWORK shares a page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for the scout acknowledgement's network, 0, and its source, which must be the scout's destination;
;; then starts the data frame.
;;
;; A valid acknowledgement turns the 68B54 to transmitting and sends the data frame's destination;
;; <SEND_DATA_SOURCE> follows, and <WAIT_FOR_FINAL_ACK> once the data has gone. Anything else fails the transmission
;; with "Net Error".
;; Entry: RECEIVE_SCOUT_ACK_FAILED = fails the transmission, RECEIVE_SCOUT_ACK_SOURCE = checks the source
;; See: <RECEIVE_SCOUT_ACK>, <SEND_DATA_SOURCE>
RECEIVE_SCOUT_ACK_NETWORK:
    bit ADLC_STATUS_2
    bpl RECEIVE_SCOUT_ACK_FAILED
    lda ADLC_RX_DATA
    bne RECEIVE_SCOUT_ACK_FAILED
    lda #<RECEIVE_SCOUT_ACK_SOURCE
    bit ADLC_STATUS_1
    bmi RECEIVE_SCOUT_ACK_SOURCE
    .assert >RECEIVE_SCOUT_ACK_SOURCE = >RECEIVE_SCOUT_ACK, "RECEIVE_SCOUT_ACK_SOURCE shares a page."
    jmp NFS_SET_NMI_HANDLER_LOW
RECEIVE_SCOUT_ACK_FAILED:
    jmp TX_NET_ERROR
RECEIVE_SCOUT_ACK_SOURCE:
    bit ADLC_STATUS_2
    bpl RECEIVE_SCOUT_ACK_FAILED
    lda ADLC_RX_DATA
    cmp ECONET_SCOUT
    bne RECEIVE_SCOUT_ACK_FAILED
    lda ADLC_RX_DATA
    cmp ECONET_SCOUT_NETWORK
    bne RECEIVE_SCOUT_ACK_FAILED
    lda #ADLC_SR2_FRAME_VALID
    bit ADLC_STATUS_2
    beq RECEIVE_SCOUT_ACK_FAILED
    lda #ADLC_CR2_TRANSMIT
    sta ADLC_CONTROL_2
    lda #ADLC_CR1_TRANSMIT
    sta ADLC_CONTROL_1
    lda #<WAIT_FOR_FINAL_ACK
    ldy #>WAIT_FOR_FINAL_ACK
    sta ECONET_AFTER_ACK
    sty ECONET_AFTER_ACK + 1
    lda ECONET_SCOUT
    bit ADLC_STATUS_1
    bvc SEND_DATA_LOOP              ; no room: fail
    sta ADLC_TX_CONTINUE
    lda ECONET_SCOUT_NETWORK
    sta ADLC_TX_CONTINUE
    lda #<SEND_DATA_SOURCE
    ldy #>SEND_DATA_SOURCE
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler that sends the data frame's source, this station and network 0, then goes on to the data.
;;
;; The data comes from memory (<SEND_DATA>) or through the Tube (<SEND_TUBE_DATA>).
;; Entry: SEND_DATA_START = goes on to the data, as a PEEK's or machine type's reply does after its header
;; See: <RECEIVE_SCOUT_ACK_NETWORK>, <SEND_ACK_SOURCE>
SEND_DATA_SOURCE:
    lda STATION_ID
    bit ADLC_STATUS_1
    bvc SEND_DATA_LOOP              ; no room: fail
    sta ADLC_TX_CONTINUE
    lda #$00
    sta ADLC_TX_CONTINUE
SEND_DATA_START:
    lda #ECONET_FRAME_TUBE
    bit ECONET_FRAME
    bne SEND_DATA_START_TUBE
    lda #<SEND_DATA
    ldy #>SEND_DATA
    jmp NFS_SET_NMI_HANDLER
SEND_DATA_START_TUBE:
    lda #<SEND_TUBE_DATA
    ldy #>SEND_TUBE_DATA
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler that sends the data from memory, two bytes at a time from <ECONET_BUFFER>, Y = <ECONET_INDEX>,
;; then ends the frame.
;;
;; At the buffer's end the frame ends after the bytes written. A reply then ends the exchange, through <END_FRAME>;
;; otherwise <ECONET_AFTER_ACK> is installed. A transmitter with no room for more fails: a reply is abandoned, and a
;; transmission ends with "Net Error".
;; Entry: SEND_DATA_LOOP = with overflow clear fails the frame, SEND_DATA_END = ends the frame
;; See: <SEND_DATA_SOURCE>, <SEND_TUBE_DATA>
SEND_DATA:
    ldy ECONET_INDEX
    bit ADLC_STATUS_1
SEND_DATA_LOOP:
    bvc SEND_DATA_FAILED
    lda (ECONET_BUFFER),y
    sta ADLC_TX_CONTINUE
    iny
    bne SEND_DATA_SECOND
    dec ECONET_PAGES
    beq SEND_DATA_END
    inc ECONET_BUFFER + 1
SEND_DATA_SECOND:
    lda (ECONET_BUFFER),y
    sta ADLC_TX_CONTINUE
    iny
    sty ECONET_INDEX
    bne SEND_DATA_NEXT
    dec ECONET_PAGES
    beq SEND_DATA_END
    inc ECONET_BUFFER + 1
SEND_DATA_NEXT:
    bit ADLC_STATUS_1
    bmi SEND_DATA_LOOP
    jmp NFS_NMI_RETURN
SEND_DATA_END:
    lda #ADLC_CR2_LAST_DATA
    sta ADLC_CONTROL_2
    lda ECONET_FRAME
    bpl SEND_DATA_END_AFTER_ACK
    lda #<END_FRAME
    ldy #>END_FRAME
    jmp NFS_SET_NMI_HANDLER
SEND_DATA_END_AFTER_ACK:
    lda ECONET_AFTER_ACK
    ldy ECONET_AFTER_ACK + 1
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler that sends the data through the Tube, two bytes at a time from register 3, counting
;; <ECONET_COUNT> up to zero, then ends the frame as <SEND_DATA> does.
;; See: <SEND_DATA>, <SET_UP_TRANSFER>
SEND_TUBE_DATA:
    bit ADLC_STATUS_1
SEND_TUBE_DATA_LOOP:
    bvc SEND_DATA_FAILED
    lda TUBE_R3_DATA
    sta ADLC_TX_CONTINUE
    inc ECONET_COUNT
    bne SEND_TUBE_DATA_SECOND
    inc ECONET_COUNT + 1
    bne SEND_TUBE_DATA_SECOND
    inc ECONET_COUNT + 2
    bne SEND_TUBE_DATA_SECOND
    inc ECONET_COUNT + 3
    beq SEND_DATA_END
SEND_TUBE_DATA_SECOND:
    lda TUBE_R3_DATA
    sta ADLC_TX_CONTINUE
    inc ECONET_COUNT
    bne SEND_TUBE_DATA_NEXT
    inc ECONET_COUNT + 1
    bne SEND_TUBE_DATA_NEXT
    inc ECONET_COUNT + 2
    bne SEND_TUBE_DATA_NEXT
    inc ECONET_COUNT + 3
    beq SEND_DATA_END
SEND_TUBE_DATA_NEXT:
    bit ADLC_STATUS_1
    bmi SEND_TUBE_DATA_LOOP
    jmp NFS_NMI_RETURN

;; Fails a data frame the transmitter had no room for: abandons a reply, or ends a transmission with "Net Error".
;; See: <END_FRAME>, <TX_NET_ERROR>
SEND_DATA_FAILED:
    lda ECONET_FRAME
    bpl TX_NET_ERROR
    jmp END_FRAME

;; The NMI handler once a frame this station sent has ended: turns to receiving the frame that ends the exchange.
;;
;; That is the final acknowledgement, a HALT's or CONTINUE's acknowledgement, or a PEEK's or machine type's reply.
;; See: <RECEIVE_FINAL_ACK>
WAIT_FOR_FINAL_ACK:
    lda #ADLC_CR1_RECEIVE
    sta ADLC_CONTROL_1
    lda #<RECEIVE_FINAL_ACK
    ldy #>RECEIVE_FINAL_ACK
    jmp NFS_SET_NMI_HANDLER

;; The NMI handler for the final acknowledgement's first byte, which must be this station's number.
;; See: <RECEIVE_FINAL_ACK_NETWORK>
RECEIVE_FINAL_ACK:
    lda #ADLC_SR2_ADDRESS
    bit ADLC_STATUS_2
    beq TX_NET_ERROR
    lda ADLC_RX_DATA
    cmp STATION_ID
    bne TX_NET_ERROR
    lda #<RECEIVE_FINAL_ACK_NETWORK
    .assert >RECEIVE_FINAL_ACK_NETWORK = >RECEIVE_FINAL_ACK, "RECEIVE_FINAL_ACK_NETWORK shares a page."
    jmp NFS_SET_NMI_HANDLER_LOW

;; The NMI handler for the final acknowledgement's network, 0, and its source, which must be the scout's
;; destination; then ends the transmission.
;;
;; A PEEK's or machine type's reply goes on to receive its data. Otherwise a valid frame is success, and anything
;; else "Net Error".
;; Entry: RECEIVE_FINAL_ACK_SOURCE = checks the source, TX_SUCCEEDED = ends the transmission with success,
;;   TX_NET_ERROR = ends it with "Net Error", TX_DONE = ends it with the result in A
;; See: <RECEIVE_FINAL_ACK>, <RECEIVE_DATA_START>, <END_FRAME>
RECEIVE_FINAL_ACK_NETWORK:
    bit ADLC_STATUS_2
    bpl TX_NET_ERROR
    lda ADLC_RX_DATA
    bne TX_NET_ERROR
    lda #<RECEIVE_FINAL_ACK_SOURCE
    bit ADLC_STATUS_1
    bmi RECEIVE_FINAL_ACK_SOURCE
    .assert >RECEIVE_FINAL_ACK_SOURCE = >RECEIVE_FINAL_ACK, "RECEIVE_FINAL_ACK_SOURCE shares a page."
    jmp NFS_SET_NMI_HANDLER_LOW
RECEIVE_FINAL_ACK_SOURCE:
    bit ADLC_STATUS_2
    bpl TX_NET_ERROR
    lda ADLC_RX_DATA
    cmp ECONET_SCOUT
    bne TX_NET_ERROR
    lda ADLC_RX_DATA
    cmp ECONET_SCOUT_NETWORK
    bne TX_NET_ERROR
    lda ECONET_FRAME
    bpl RECEIVE_FINAL_ACK_VALID
    jmp RECEIVE_DATA_START          ; a reply: its data follows
RECEIVE_FINAL_ACK_VALID:
    lda #ADLC_SR2_FRAME_VALID
    bit ADLC_STATUS_2
    beq TX_NET_ERROR
TX_SUCCEEDED:
    lda #ECONET_SUCCESS
    beq TX_DONE
TX_NET_ERROR:
    lda #ECONET_NET_ERROR
TX_DONE:
    ldy #ECONET_CB_CONTROL
    sta (ECONET_TX_BLOCK),y
    lda #ECONET_FREE
    sta NFS_TRANSMIT_FREE
    jmp END_FRAME

;; The length of the scout for each immediate operation, &81-&88: the header, then the remote address and end address
;; as the operation needs them.
;; See: <TX_START>
SCOUT_LENGTHS:
    .byte ECONET_HEADER + 8         ; &81 PEEK: the remote address and end address
    .byte ECONET_HEADER + 8         ; &82 POKE: the remote address and end address
    .byte ECONET_HEADER + 4         ; &83 JSR: the address
    .byte ECONET_HEADER + 4         ; &84 user procedure: the address
    .byte ECONET_HEADER + 4         ; &85 OS procedure: the number
    .byte ECONET_HEADER             ; &86 HALT
    .byte ECONET_HEADER             ; &87 CONTINUE
    .byte ECONET_HEADER + 4         ; &88 machine type: four bytes the receiver ignores

;; The flags each immediate operation, &81-&88, starts <ECONET_FRAME> with.
;; See: <TX_START>
IMMEDIATE_FLAGS:
    .byte ECONET_FRAME_REPLY | ECONET_FRAME_TWO_WAY ; &81 PEEK
    .byte 0                         ; &82 POKE
    .byte 0                         ; &83 JSR
    .byte 0                         ; &84 user procedure
    .byte 0                         ; &85 OS procedure
    .byte ECONET_FRAME_TWO_WAY      ; &86 HALT
    .byte ECONET_FRAME_TWO_WAY      ; &87 CONTINUE
    .byte ECONET_FRAME_REPLY | ECONET_FRAME_TWO_WAY ; &88 machine type

;; Sets up a control block's buffer for receiving or sending: in memory, or through the Tube.
;;
;; The Tube takes the data when one is fitted and the start address's top two bytes are not &FFFF. Then it sets
;; <ECONET_FRAME_TUBE>, puts the start less the end in <ECONET_COUNT>, claims the Tube and starts a transfer of
;; <ECONET_TUBE_TYPE> at the start address. Otherwise it sets <ECONET_INDEX>, <ECONET_PAGES> and <ECONET_BUFFER> so
;; that the start is <ECONET_BUFFER> plus <ECONET_INDEX> and the end falls where <ECONET_INDEX> wraps to 0 with
;; <ECONET_PAGES> run down to 0.
;; In: ECONET_BLOCK = the control block, ECONET_TUBE_TYPE = the Tube transfer type
;; Out: carry = set when the buffer is ready, clear when the Tube could not be claimed
;; Uses: A, Y
;; Keeps: X
;; Entry: SET_UP_MEMORY_TRANSFER = sets up a buffer in memory
;; See: <RELEASE_TUBE>, <FINISH_TUBE_TRANSFER>
SET_UP_TRANSFER:
    ldy #ECONET_CB_START + 2
    lda (ECONET_BLOCK),y
    iny
    and (ECONET_BLOCK),y
    cmp #$FF
    beq SET_UP_MEMORY_TRANSFER      ; the I/O processor's memory
    lda NFS_TUBE_PRESENT
    beq SET_UP_MEMORY_TRANSFER
    lda ECONET_FRAME
    ora #ECONET_FRAME_TUBE
    sta ECONET_FRAME
    sec
    php
    ldy #ECONET_CB_START
SET_UP_TRANSFER_COUNT:
    lda (ECONET_BLOCK),y
    iny
    iny
    iny
    iny
    plp
    sbc (ECONET_BLOCK),y
    sta a:ECONET_COUNT - ECONET_CB_END,y
    dey
    dey
    dey
    php
    cpy #ECONET_CB_END
    bcc SET_UP_TRANSFER_COUNT
    plp
    txa
    pha
    lda #ECONET_CB_START
    clc
    adc ECONET_BLOCK
    tax
    ldy ECONET_BLOCK + 1
    lda #ECONET_TUBE_CLAIM
    jsr TUBE_TRANSFER
    bcc SET_UP_TRANSFER_DONE
    lda ECONET_TUBE_TYPE
    jsr TUBE_TRANSFER
    jsr RELEASE_TUBE                ; only marks the Tube claimed for this frame
    sec
SET_UP_TRANSFER_DONE:
    pla
    tax
    rts
SET_UP_MEMORY_TRANSFER:
    ldy #ECONET_CB_START
    lda (ECONET_BLOCK),y
    ldy #ECONET_CB_END
    sec
    sbc (ECONET_BLOCK),y
    sta ECONET_INDEX                ; the start's low byte less the end's
    ldy #ECONET_CB_START + 1
    lda (ECONET_BLOCK),y
    sbc #$00
    sta ECONET_BUFFER + 1
    ldy #ECONET_CB_END
    lda (ECONET_BLOCK),y
    sta ECONET_BUFFER               ; the end's low byte
    ldy #ECONET_CB_END + 1
    lda (ECONET_BLOCK),y
    sec
    sbc ECONET_BUFFER + 1
    sta ECONET_PAGES
    sec
    rts

;; Resets the 68B54 and sets it up for the Econet, then sets it listening.
;;
;; Control register 1 resets both halves and selects control registers 3 and 4, which get eight-bit words and no
;; options. Falls through into <SET_ADLC_LISTENING>.
;; Uses: A
;; Keeps: X, Y
RESET_ADLC:
    lda #ADLC_CR1_RESET
    sta ADLC_CONTROL_1
    lda #ADLC_CR4_8_BITS
    sta ADLC_CONTROL_4
    lda #ADLC_CR3_NONE
    sta ADLC_CONTROL_3

;; Sets the 68B54 listening: the transmitter reset, the receive interrupt on, and the status cleared.
;; Uses: A
;; Keeps: X, Y
SET_ADLC_LISTENING:
    lda #ADLC_CR1_RECEIVE
    sta ADLC_CONTROL_1
    lda #ADLC_CR2_LISTEN
    sta ADLC_CONTROL_2
    rts

;; Gives up the NMI to another filing system, once no frame is in progress: service call &0C, NMI claim.
;;
;; If the NFS owns the NMI it waits until the handler is <RECEIVE_SCOUT> again, holds the NMIs back, marks the Econet
;; busy and the NMI not the NFS's, and returns the NFS's filing system number. Either way the 68B54 is left listening.
;; Out: Y = 5 when the NFS owned the NMI, otherwise unchanged
;; Uses: A
;; See: <NFS_SERVICE_NMI_CLAIM>, <TAKE_NMI>
GIVE_UP_NMI:
    bit ECONET_NMI_OWNED
    bpl GIVE_UP_NMI_LISTEN
GIVE_UP_NMI_WAIT:
    lda NFS_NMI_JUMP + 1
    cmp #<RECEIVE_SCOUT
    bne GIVE_UP_NMI_WAIT
    lda NFS_NMI_JUMP + 2
    cmp #>RECEIVE_SCOUT
    bne GIVE_UP_NMI_WAIT
    bit ECONET_NMI_OFF
    bit ECONET_NMI_OFF
    lda #$00
    sta NFS_TRANSMIT_FREE
    sta ECONET_NMI_OWNED
    ldy #ECONET_FILING_SYSTEM
GIVE_UP_NMI_LISTEN:
    jmp SET_ADLC_LISTENING

;; The NFS's NMI code, which <TAKE_NMI> copies to &0D00, where the NMI vector points, whenever the NFS takes the NMI.
;;
;; It holds further NMIs back, saves A and Y (not X), pages this ROM in and jumps to the current handler, whose
;; address the handlers change in <NFS_NMI_JUMP>. <TAKE_NMI> puts this ROM's number in <NFS_NMI_ROM>.
;; See: <NFS_SET_NMI_HANDLER>, <TAKE_NMI>
NFS_NMI_IMAGE:
    .logicalorg $0D00
NFS_NMI:
    bit ECONET_NMI_OFF
    pha
    tya
    pha
NFS_NMI_ROM:
    lda #$00                        ; the NFS's ROM number
    sta ROMSEL
NFS_NMI_JUMP:
    jmp RECEIVE_SCOUT               ; the current handler

;; Installs the next NMI handler and returns from the NMI: the handler's address is stored in <NFS_NMI_JUMP>.
;;
;; The ROM that was paged in is paged back, Y and A restored, and the NMIs let through again.
;; In: A/Y = the next handler, low byte in A
;; Entry: NFS_SET_NMI_HANDLER_LOW = changes only the low byte, for a handler in the same page as the current one,
;;   NFS_NMI_RETURN = keeps the current handler
NFS_SET_NMI_HANDLER:
    sty NFS_NMI_JUMP + 2
NFS_SET_NMI_HANDLER_LOW:
    sta NFS_NMI_JUMP + 1
NFS_NMI_RETURN:
    lda ROMSEL_COPY
    sta ROMSEL
    pla
    tay
    pla
    bit ECONET_NMI_ON
    rti
NFS_NMI_END:
    .assert NFS_NMI_END - NFS_NMI = $20, "TAKE_NMI copies 32 bytes of NMI code."
    .logicalorg
