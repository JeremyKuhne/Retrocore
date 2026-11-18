;; The NFS's OSWORD &14, its NETV handler and the remote control and network printer code behind it ($8FF0-$9320).
;;
;; - <NFS_OSWORD_14> sends a command to the file server and takes its reply, or sends OS procedure calls to another
;;   station: characters for its keyboard, or an error.
;; - <NETV_HANDLER> is where NETV points. While another station has this one under remote control (the Advanced
;;   User Guide's *REMOTE facility), it passes OSWRCH's characters, some OSBYTEs and the SOUND and ENVELOPE OSWORDs to
;;   that station, and waits for that station's answer to the OSBYTEs that read the keyboard. It is also the network
;;   printer's driver, printer type 4: it collects the printer buffer into blocks and sends them to the printer
;;   server.
;; - <READ_SCREEN_STATE>, OS procedure call 2, collects this machine's screen state where the calling station can
;;   read it.
;; - <BUILD_BLOCK> fills in Econet control blocks in the NFS's workspace from templates.
;;
;; The NFS has two pages of private workspace: <NFS_WORKSPACE_PAGE> points at the first, <NFS_BLOCKS_PAGE> at the
;; second. An Econet control block holds a control byte, a port, the station and network, then the buffer's start
;; and end, each four bytes (&FFFF in the top half for this machine's memory), and for an immediate operation the
;; remote address or procedure number.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; The NFS's zero page, as this part uses it.
NFS_PRINT_STATE = $99               ;; the network printer: bit 0 set when VDU 3 came last, bit 7 the sequence bit

; The NFS's variables in pages &0D and &0E.
NFS_PRINT_INDEX = $0D61             ;; the offset in the first workspace page of the next byte for the printer

; Offsets in the first workspace page (NFS_WORKSPACE_PAGE).
NFS_PRINT_BUFFER = $1F              ;; the bytes collected for the network printer, up to NFS_PRINT_BUFFER_LAST
NFS_PRINT_BUFFER_LAST = $6E         ;; a block is sent once a byte has been put here
NFS_PROCEDURE_BLOCK = $6F           ;; the control block for OS procedure calls to another station
NFS_PROCEDURE_DATA = $7D            ;; the byte an OS procedure call sends

; Offsets in the second workspace page (NFS_BLOCKS_PAGE).
NFS_PRINT_BLOCK = $00               ;; the control block that sends the printer buffer to the printer server
NFS_REMOTE_BLOCK = $0C              ;; the control block for messages to the station controlling this one
NFS_COMMAND_BLOCK = $18             ;; the control block for OSWORD &14's file server command
NFS_REMOTE_MESSAGE = $D9            ;; a message to the controlling station: its type, then up to 15 bytes
NFS_SCREEN_STATE = $E9              ;; &E9-&FF, the screen state that OS procedure call 2 collects

; Econet.
NFS_CONTROL_SEND = $80              ;; a control byte for transmitting; bit 7 is cleared when the transmission ends
NFS_CONTROL_RECEIVE = $7F           ;; a control byte for receiving: bit 7 is set when a message has arrived
NFS_CONTROL_SENT = $3F              ;; left in the remote block's control byte after a message to the controller
NFS_REMOTE_PORT = $93               ;; port &93, which carries messages between a station and its controller
NFS_PRINTER_PORT = $D1              ;; port &D1, the printer server's
NFS_PROCEDURE_ERROR = 3             ;; OS procedure call 3: the other station raises error 0, with no message

; Types of message to the controlling station, in NFS_REMOTE_MESSAGE.
NFS_REMOTE_OSWRCH = 0               ;; a character OSWRCH printed, in the next byte
NFS_REMOTE_OSWORD = 1               ;; an OSWORD: its number, then its control block
NFS_REMOTE_OSBYTE = 2               ;; an OSBYTE's A, X and Y, needing no reply
NFS_REMOTE_OSBYTE_REPLY = 3         ;; an OSBYTE's A, X and Y, whose results the controller sends back

; The templates that <BUILD_BLOCK> copies.
NFS_TEMPLATE_PAGE = $FC             ;; a template byte for the workspace page, which also goes in NFS_BLOCK_POINTER
NFS_TEMPLATE_SKIP = $FD             ;; a template byte that leaves the block's byte as it is
NFS_TEMPLATE_END = $FE              ;; a template byte that ends the template

; NETV, OSBYTE and OSWORD.
NETV_REASONS = 9                    ;; the NETV reasons the NFS takes, 0-8
NFS_NETWORK_PRINTER = 4             ;; printer type 4, the network printer
NFS_OSBYTE_INKEY = $81              ;; OSBYTE &81: read a key within a time limit, or scan for a key with Y = &FF
NFS_OSBYTE_SCREEN_BOTTOM = $85      ;; OSBYTE &85: the bottom of the screen memory a mode would use
NFS_OSBYTE_READ_BUFFER = $91        ;; OSBYTE &91: take a character from a buffer; carry set when it is empty
NFS_OSBYTE_MARK_PERIOD = $C2        ;; OSBYTE &C2: read or write the first flashing colour's duration
NFS_OSBYTE_SPACE_PERIOD = $C3       ;; OSBYTE &C3: read or write the second flashing colour's duration
NFS_OSWORD_SOUND = $07              ;; OSWORD 7: SOUND
NFS_OSWORD_ENVELOPE = $08           ;; OSWORD 8: ENVELOPE
NFS_OSWORD_READ_PALETTE = $0B       ;; OSWORD &0B: read the physical colour of a logical colour
NFS_BUFFER_PRINTER = $03            ;; buffer 3, the printer buffer
NFS_RETURN = $0D                    ;; the carriage return that ends OSWORD &14's characters

; Where OS procedure call 2 counts.
NFS_SCREEN_STATE_INDEX = OS_COMMAND_WORKSPACE + 5 ;; the logical colour, then the entry in NFS_SCREEN_STATE_OSBYTES
NFS_OSWORD_14_INDEX = OS_COMMAND_WORKSPACE + 3 ;; the offset of OSWORD &14's next character in its control block

; ---------------------------------------------------------------------------------------------------------------------
; OSWORD &14
; ---------------------------------------------------------------------------------------------------------------------

;; OSWORD &14: sends a command to the file server and receives its reply, or makes OS procedure calls to another
;; station.
;;
;; The first byte of the control block at OS_X/OS_Y picks the operation:
;;
;; - 0: the block, from byte 2, is a file server command. Bytes 2 and 4-6 are filled in with the reply port, &90,
;;   and the three handles from NFS_URD, so the caller gives the function code in byte 3, the data from byte 7
;;   and in byte 1 the offset of the end of the command. The command goes to the file server's port &99 through
;;   <NFS_COMMAND_BLOCK>, and the reply comes back over the block, from byte 2. ESCAPE can abandon the transmission's
;;   retries, but not the wait for the reply, which ends only with the reply or "No reply".
;; - 1: bytes 1 and 2 are a station and network; the text from byte 3, up to a carriage return (sent) or a zero (not
;;   sent), goes to that station one character at a time, each as OS procedure call 0, which puts it in that
;;   station's keyboard buffer. A short pause follows each.
;; - 2 or more: bytes 1 and 2 are a station and network, which is sent OS procedure call 3, which
;;   makes the NFS there raise error 0.
;;
;; The NFS's service call 8 handler, <SERVICE_UNRECOGNISED_OSWORD>, comes here with OSWORD &14.
;; In: A = the control block's first byte, Y = 0, OS_X/OS_Y = the control block
;; Uses: A, X, Y, NFS_BLOCK_POINTER
;; See: <SET_OSWORD_14_BUFFER>, <TRANSMIT>, <AWAIT_RECEPTION>, <BUILD_OS_PROCEDURE_BLOCK>
NFS_OSWORD_14:
    cmp #$01
    bcs NFS_OSWORD_14_STATION
    ldy #NFS_COMMAND_BLOCK + 11
NFS_OSWORD_14_TEMPLATE:
    lda FS_CONTROL_BLOCK_TEMPLATE - NFS_COMMAND_BLOCK,y ; the file server command block's template, in NetService.asm
    bne NFS_OSWORD_14_STORE
    lda NFS_FS_STATION - NFS_COMMAND_BLOCK - 2,y ; its zeros: the file server's station and network
NFS_OSWORD_14_STORE:
    sta (NFS_BLOCKS_PAGE),y
    dey
    cpy #NFS_COMMAND_BLOCK - 1
    bne NFS_OSWORD_14_TEMPLATE
    iny
    sty NFS_BLOCK_POINTER
    jsr SET_OSWORD_14_BUFFER ; the buffer: the control block from byte 2 (carry is set) to byte 1's offset
    ldy #$02
    lda #NFS_PORT_REPLY                 ; also sets bit 7 of NFS_ESCAPE_ENABLE
    sta NFS_ESCAPE_ENABLE
    sta (OS_X),y                        ; byte 2: the reply port
    iny
    iny
NFS_OSWORD_14_HANDLES:
    lda NFS_URD - 4,y               ; bytes 4-6: the three handles
    sta (OS_X),y
    iny
    cpy #$07
    bne NFS_OSWORD_14_HANDLES
    lda NFS_BLOCKS_PAGE + 1
    sta NFS_BLOCK_POINTER + 1
    cli
    jsr TRANSMIT                           ; transmit the command
    ldy #NFS_COMMAND_BLOCK + 8          ; receive the reply over it, the buffer's end now &FFFF
    lda #$FF
    sta (NFS_BLOCKS_PAGE),y
    iny
    sta (NFS_BLOCKS_PAGE),y
    ldy #NFS_COMMAND_BLOCK + 1
    lda #NFS_PORT_REPLY
    sta (NFS_BLOCKS_PAGE),y
    dey
    lda #NFS_CONTROL_RECEIVE
    sta (NFS_BLOCKS_PAGE),y
    jmp AWAIT_RECEPTION                           ; wait for it
NFS_OSWORD_14_STATION:
    php                                 ; zero set for operation 1
    ldy #$01
    lda (OS_X),y
    tax
    iny
    lda (OS_X),y
    iny
    sty NFS_OSWORD_14_INDEX             ; the text starts at byte 3
    ldy #NFS_PROCEDURE_BLOCK + 3
    sta (NFS_WORKSPACE_PAGE),y            ; the network
    dey
    txa
    sta (NFS_WORKSPACE_PAGE),y            ; the station
    plp
    bne NFS_OSWORD_14_ERROR
NFS_OSWORD_14_CHARACTER:
    ldy NFS_OSWORD_14_INDEX
    inc NFS_OSWORD_14_INDEX
    lda (OS_X),y
    beq NFS_OSWORD_14_DONE
    ldy #NFS_PROCEDURE_DATA
    sta (NFS_WORKSPACE_PAGE),y
    pha
    jsr BUILD_OS_PROCEDURE_BLOCK        ; OS procedure call 0, with the character
    jsr TRANSMIT_WITH_INTERRUPTS
NFS_OSWORD_14_PAUSE:
    dex                                 ; X is 0 after the transmission: 256 times round
    bne NFS_OSWORD_14_PAUSE
    pla
    eor #NFS_RETURN
    bne NFS_OSWORD_14_CHARACTER
NFS_OSWORD_14_DONE:
    rts
NFS_OSWORD_14_ERROR:
    jsr BUILD_OS_PROCEDURE_BLOCK
    ldy #NFS_PROCEDURE_BLOCK + 12
    lda (NFS_WORKSPACE_PAGE),y
    adc #NFS_PROCEDURE_ERROR            ; carry is clear after BUILD_OS_PROCEDURE_BLOCK
    sta (NFS_WORKSPACE_PAGE),y            ; the procedure number
    ; Falls through into TRANSMIT_WITH_INTERRUPTS.

;; Enables interrupts and transmits the control block at NFS_BLOCK_POINTER.
;; Uses: A, X, Y
;; See: <TRANSMIT>
TRANSMIT_WITH_INTERRUPTS:
    cli
    jmp TRANSMIT

; ---------------------------------------------------------------------------------------------------------------------
; NETV
; ---------------------------------------------------------------------------------------------------------------------

;; The NFS's NETV handler: carries out NETV reasons 0-8, returning the registers as each reason's routine leaves them.
;;
;; The MOS calls NETV for the printer drivers (reasons 0-3 and 5, with Y the printer type), for OSWRCH (4), OSRDCH
;; (6), OSBYTE (7) and OSWORD (8) when OSBYTEs &CE-&D0 ask for them, and with &0D when a line has been read. Each
;; routine is entered with X = the reason, A = OS_A and Y as the MOS gave it. They return results by changing the
;; registers and flags stacked here: the stacked flags are at STACK+6,X after a TSX in the routine, A at STACK+5,X, X
;; at STACK+4,X and Y at STACK+3,X.
;; In: A = the reason, Y = depends on the reason
;; Out: A, X, Y = as on entry, but for OSBYTE (7) the controlling station's results
;; See: <NETV_ROUTINES_LOW>
NETV_HANDLER:
    php
    pha
    txa
    pha
    tya
    pha
    tsx
    lda STACK + 3,x                     ; the reason
    cmp #NETV_REASONS
    bcs NETV_HANDLER_EXIT
    tax
    jsr NETV_DISPATCH
NETV_HANDLER_EXIT:
    pla
    tay
    pla
    tax
    pla
    plp
    rts

;; Calls the routine for a NETV reason, through <NETV_ROUTINES_LOW> and <NETV_ROUTINES_HIGH>.
;; In: X = the reason
;; Out: A = OS_A on entry to the routine
NETV_DISPATCH:
    lda NETV_ROUTINES_HIGH,x
    pha
    lda NETV_ROUTINES_LOW,x
    pha
    lda OS_A
    rts

;; The low bytes of the NETV routines' addresses less one, indexed by the reason; the high bytes follow.
;; See: <NETV_DISPATCH>
NETV_ROUTINES_LOW:
    .byte <(NFS_NO_OPERATION-1)                    ; 0, the printer poll: nothing to do
    .byte <(NETV_PRINTER-1)             ; 1, characters are waiting for a dormant printer
    .byte <(NETV_PRINTER-1)             ; 2, VDU 2
    .byte <(NETV_PRINTER-1)             ; 3, VDU 3
    .byte <(NETV_OSWRCH-1)              ; 4, OSWRCH
    .byte <(NETV_PRINTER_TYPE-1)        ; 5, OSBYTE 5 is selecting a printer type
    .byte <(NFS_NO_OPERATION-1)                    ; 6, OSRDCH: nothing to do
    .byte <(NETV_OSBYTE-1)              ; 7, OSBYTE
    .byte <(NETV_OSWORD-1)              ; 8, OSWORD

;; The high bytes of the NETV routines' addresses less one, indexed by the reason.
;; See: <NETV_ROUTINES_LOW>
NETV_ROUTINES_HIGH:
    .byte >(NFS_NO_OPERATION-1)
    .byte >(NETV_PRINTER-1)
    .byte >(NETV_PRINTER-1)
    .byte >(NETV_PRINTER-1)
    .byte >(NETV_OSWRCH-1)
    .byte >(NETV_PRINTER_TYPE-1)
    .byte >(NFS_NO_OPERATION-1)
    .byte >(NETV_OSBYTE-1)
    .byte >(NETV_OSWORD-1)

;; NETV 4: passes a character OSWRCH is printing to the controlling station, and lets OSWRCH print it here as well.
;; In: Y = the character
;; Uses: A, X, Y
;; See: <SEND_REMOTE_MESSAGE>
NETV_OSWRCH:
    tsx
    ror STACK + 6,x                     ; clear the stacked carry: OSWRCH goes on to print the character
    asl STACK + 6,x
    tya
    ldy #NFS_REMOTE_MESSAGE + 1
    sta (NFS_BLOCKS_PAGE),y
    lda #NFS_REMOTE_OSWRCH
    ; Falls through into SEND_REMOTE_MESSAGE.

;; Sends a message to the station controlling this one: its type and the bytes after it, through
;; <NFS_REMOTE_BLOCK> to port &93.
;;
;; The block's buffer is NFS_REMOTE_MESSAGE to &DE, as <BUILD_REMOTE_BLOCK> sets it, unless <NETV_OSWORD> has moved
;; its end. Afterwards the block's control byte is left at &3F, which <NFS_OSBYTE_POLL_RECEIVE> looks for.
;; In: A = the message type
;; Out: X = 0
;; Uses: A, Y
;; Keeps: NFS_BLOCK_POINTER
SEND_REMOTE_MESSAGE:
    ldy #NFS_REMOTE_MESSAGE
    sta (NFS_BLOCKS_PAGE),y
    lda #NFS_CONTROL_SEND
    ldy #NFS_REMOTE_BLOCK
    sta (NFS_BLOCKS_PAGE),y
    lda NFS_BLOCK_POINTER
    pha
    lda NFS_BLOCK_POINTER + 1
    pha
    sty NFS_BLOCK_POINTER
    ldx NFS_BLOCKS_PAGE + 1
    stx NFS_BLOCK_POINTER + 1
    jsr TRANSMIT
    lda #NFS_CONTROL_SENT
    sta (NFS_BLOCK_POINTER,x)
    pla
    sta NFS_BLOCK_POINTER + 1
    pla
    sta NFS_BLOCK_POINTER
    rts

;; NETV 7: passes an OSBYTE to the controlling station when it is one that concerns the keyboard or the display.
;;
;; The ten OSBYTEs in <REMOTE_OSBYTES> are sent as message type 2 and also carried out here. The five in
;; <REMOTE_OSBYTES_WITH_REPLY> are sent as type 3, and this station waits for the controller's reply on the same
;; block: four bytes that become the caller's Y, X, A and flags, with overflow set so that the MOS does not carry out
;; the call itself. OSBYTE &81 goes by its Y: a key scan (Y = &80-&FF) waits for a reply, a timed read with Y = 1-&7F
;; is sent without one, and one with Y = 0 is not sent.
;; In: A = the OSBYTE number, OS_A/OS_X/OS_Y = the call
;; Uses: A, X, Y
NETV_OSBYTE:
    ldy OS_Y
    cmp #NFS_OSBYTE_INKEY
    beq NETV_OSBYTE_SEND
    ldy #$01
    ldx #REMOTE_OSBYTES_WITH_REPLY - REMOTE_OSBYTES - 1
    jsr FIND_REMOTE_OSBYTE
    beq NETV_OSBYTE_SEND
    dey
    dey
    ldx #REMOTE_OSBYTES_WITH_REPLY - REMOTE_OSBYTES + 4
    jsr FIND_REMOTE_OSBYTE
    beq NETV_OSBYTE_SEND                ; Y = &FF: wait for a reply
    iny                                 ; Y = 0: not sent
NETV_OSBYTE_SEND:
    ldx #NFS_REMOTE_OSBYTE
    tya
    beq NETV_OSBYTE_DONE
    php
    bpl NETV_OSBYTE_COPY
    inx
NETV_OSBYTE_COPY:
    ldy #NFS_REMOTE_MESSAGE + 3
NETV_OSBYTE_COPY_LOOP:
    lda a:OS_A - NFS_REMOTE_MESSAGE - 1,y ; OS_A, OS_X and OS_Y
    sta (NFS_BLOCKS_PAGE),y
    dey
    cpy #NFS_REMOTE_MESSAGE + 1
    bpl NETV_OSBYTE_COPY_LOOP
    txa
    jsr SEND_REMOTE_MESSAGE
    plp
    bpl NETV_OSBYTE_DONE
    lda #NFS_CONTROL_RECEIVE            ; receive the reply on the same block
    ldy #NFS_REMOTE_BLOCK
    sta (NFS_BLOCKS_PAGE),y
NETV_OSBYTE_WAIT:
    lda (NFS_BLOCKS_PAGE),y
    bpl NETV_OSBYTE_WAIT
    tsx
    ldy #NFS_REMOTE_MESSAGE + 4
    lda (NFS_BLOCKS_PAGE),y          ; the flags, with overflow (the call is taken) and interrupt disable
    ora #%01000100
    bne NETV_OSBYTE_RESULT
NETV_OSBYTE_RESULT_LOOP:
    dey                                 ; then A, X and Y
    dex
    lda (NFS_BLOCKS_PAGE),y
NETV_OSBYTE_RESULT:
    sta STACK + 6,x
    cpy #NFS_REMOTE_MESSAGE + 1
    bne NETV_OSBYTE_RESULT_LOOP
NETV_OSBYTE_DONE:
    rts

;; Looks an OSBYTE number up in <REMOTE_OSBYTES> and <REMOTE_OSBYTES_WITH_REPLY>.
;; In: A = the OSBYTE number, X = the last entry to look at
;; Out: zero = set when found, X = its entry
;; Keeps: A, Y
FIND_REMOTE_OSBYTE:
    cmp REMOTE_OSBYTES,x
    beq FIND_REMOTE_OSBYTE_DONE
    dex
    bpl FIND_REMOTE_OSBYTE
FIND_REMOTE_OSBYTE_DONE:
    rts

;; The OSBYTEs passed to the controlling station without waiting for a reply.
;; See: <NETV_OSBYTE>
REMOTE_OSBYTES:
    .byte $04                           ; cursor editing
    .byte $09                           ; the first flashing colour's duration
    .byte $0A                           ; the second flashing colour's duration
    .byte $15                           ; flush a buffer
    .byte $9A                           ; write the video ULA's control register
    .byte $9B                           ; write the video ULA's palette
    .byte $E1, $E2, $E3, $E4            ; how the function keys and character codes &C0-&FF are interpreted

;; The OSBYTEs passed to the controlling station, which answers them; they follow <REMOTE_OSBYTES>.
;; See: <NETV_OSBYTE>
REMOTE_OSBYTES_WITH_REPLY:
    .byte $0B                           ; the auto-repeat delay
    .byte $0C                           ; the auto-repeat period
    .byte $0F                           ; flush the buffers
    .byte $79                           ; scan the keyboard
    .byte $7A                           ; scan the keyboard from key 16

;; NETV 8: passes SOUND and ENVELOPE (OSWORDs 7 and 8) to the controlling station, which makes the sound.
;;
;; The message is type 1: the OSWORD number at NFS_REMOTE_MESSAGE+1, then the control block from +2. Fifteen bytes
;; of the block are copied, but the remote block's buffer is lengthened only to end at &E9, which is exclusive, so
;; the message sent is sixteen bytes, with fourteen of the block (it stays so for later messages). It falls through
;; into <BUILD_OS_PROCEDURE_BLOCK>.
;; In: A = the OSWORD number, OS_X/OS_Y = the control block
;; Uses: A, X, Y, NFS_BLOCK_POINTER
NETV_OSWORD:
    ldy #$0E
    cmp #NFS_OSWORD_SOUND
    beq NETV_OSWORD_SEND
    cmp #NFS_OSWORD_ENVELOPE
    bne FIND_REMOTE_OSBYTE_DONE
NETV_OSWORD_SEND:
    ldx #NFS_REMOTE_MESSAGE + 2         ; the pointer's low byte moved to the message's third byte
    stx NFS_BLOCKS_PAGE
NETV_OSWORD_COPY:
    lda (OS_X),y
    sta (NFS_BLOCKS_PAGE),y
    dey
    bpl NETV_OSWORD_COPY
    iny
    dec NFS_BLOCKS_PAGE
    lda OS_A
    sta (NFS_BLOCKS_PAGE),y
    sty NFS_BLOCKS_PAGE              ; back to the page's start
    ldy #NFS_REMOTE_BLOCK + 8           ; the buffer's end
    lda #NFS_REMOTE_MESSAGE + 16
    sta (NFS_BLOCKS_PAGE),y
    lda #NFS_REMOTE_OSWORD
    jsr SEND_REMOTE_MESSAGE
    stx NFS_BLOCKS_PAGE              ; X = 0
    ; Falls through into BUILD_OS_PROCEDURE_BLOCK.

; ---------------------------------------------------------------------------------------------------------------------
; Control blocks
; ---------------------------------------------------------------------------------------------------------------------

;; Builds the control block for an OS procedure call to another station, at NFS_PROCEDURE_BLOCK in the first
;; workspace page, from <OS_PROCEDURE_TEMPLATE>.
;;
;; The block sends the byte at NFS_PROCEDURE_DATA as OS procedure call 0; the caller has set the station and may
;; change the procedure number.
;; Out: NFS_BLOCK_POINTER = the block, carry = clear
;; Uses: A, X, Y
;; See: <BUILD_BLOCK>
BUILD_OS_PROCEDURE_BLOCK:
    ldx #REMOTE_TEMPLATE - OS_PROCEDURE_TEMPLATE - 2
    ldy #NFS_PROCEDURE_BLOCK + 13
    bit FS_CONTROL_BLOCK_TEMPLATE_HIGH ; a byte of &FF in NetService.asm: sets overflow, for the first page
    bvs BUILD_BLOCK_LOOP

;; Builds the control block for messages to the controlling station, at NFS_REMOTE_BLOCK in the second workspace
;; page, from <REMOTE_TEMPLATE>: control byte &80, port &93, its buffer NFS_REMOTE_MESSAGE to &DE.
;;
;; The caller sets the station.
;; Out: NFS_BLOCK_POINTER = the block, carry = set, from the NFS_TEMPLATE_END before the template
;; Uses: A, X, Y
;; See: <BUILD_BLOCK>
BUILD_REMOTE_BLOCK:
    ldy #NFS_REMOTE_BLOCK + 11
    ldx #PRINT_TEMPLATE - OS_PROCEDURE_TEMPLATE - 2
    ; Falls through into BUILD_BLOCK.

;; Fills in a control block in the second workspace page from a template in <OS_PROCEDURE_TEMPLATE> and those after
;; it, working backwards.
;;
;; Each template byte is copied, except that NFS_TEMPLATE_SKIP leaves the block's byte alone, NFS_TEMPLATE_PAGE
;; stands for the workspace page's number (also stored in NFS_BLOCK_POINTER+1), and NFS_TEMPLATE_END, or running off
;; the start of the templates, ends it. NFS_BLOCK_POINTER is left at the block's first byte.
;; In: X = the template's last byte, as an offset from OS_PROCEDURE_TEMPLATE, Y = its offset in the page
;; Out: Y = the block's first byte, NFS_BLOCK_POINTER = the block when the template has a page byte
;; Uses: A, X
;; Entry: BUILD_BLOCK_LOOP = with overflow set, builds the block in the first workspace page instead
BUILD_BLOCK:
    clv
BUILD_BLOCK_LOOP:
    lda OS_PROCEDURE_TEMPLATE,x
    cmp #NFS_TEMPLATE_END
    beq BUILD_BLOCK_DONE
    cmp #NFS_TEMPLATE_SKIP
    beq BUILD_BLOCK_NEXT
    cmp #NFS_TEMPLATE_PAGE
    bne BUILD_BLOCK_STORE
    lda NFS_WORKSPACE_PAGE + 1
    bvs BUILD_BLOCK_PAGE
    lda NFS_BLOCKS_PAGE + 1
BUILD_BLOCK_PAGE:
    sta NFS_BLOCK_POINTER + 1
BUILD_BLOCK_STORE:
    bvs BUILD_BLOCK_FIRST_PAGE
    sta (NFS_BLOCKS_PAGE),y
    bvc BUILD_BLOCK_NEXT
BUILD_BLOCK_FIRST_PAGE:
    sta (NFS_WORKSPACE_PAGE),y
BUILD_BLOCK_NEXT:
    dey
    dex
    bpl BUILD_BLOCK_LOOP
BUILD_BLOCK_DONE:
    iny
    sty NFS_BLOCK_POINTER
    rts

;; The template of the OS procedure call block, at NFS_PROCEDURE_BLOCK in the first workspace page.
;; See: <BUILD_OS_PROCEDURE_BLOCK>
OS_PROCEDURE_TEMPLATE:
    .byte $85, $00                      ; control byte &85, an OS procedure call, to port 0, the immediate operations
    .byte NFS_TEMPLATE_SKIP, NFS_TEMPLATE_SKIP ; the station and network
    .byte NFS_PROCEDURE_DATA, NFS_TEMPLATE_PAGE, $FF, $FF ; the buffer's start: NFS_PROCEDURE_DATA
    .byte NFS_PROCEDURE_DATA + 1, NFS_TEMPLATE_PAGE, $FF, $FF ; its end, one byte on
    .byte $00, $00                      ; the procedure number
    .byte NFS_TEMPLATE_END

;; The template of the block for messages to the controlling station, at NFS_REMOTE_BLOCK in the second page.
;; See: <BUILD_REMOTE_BLOCK>
REMOTE_TEMPLATE:
    .byte NFS_CONTROL_SEND, NFS_REMOTE_PORT
    .byte NFS_TEMPLATE_SKIP, NFS_TEMPLATE_SKIP ; the station and network
    .byte NFS_REMOTE_MESSAGE, NFS_TEMPLATE_PAGE, $FF, $FF ; the buffer's start
    .byte NFS_REMOTE_MESSAGE + 5, NFS_TEMPLATE_PAGE, $FF, $FF ; its end: a type and four bytes
    .byte NFS_TEMPLATE_END

;; The template of the block that sends the printer buffer, at NFS_PRINT_BLOCK in the second page, from its port
;; on: <SEND_PRINT_BUFFER> sets the control byte, the pages and the end.
;; See: <SEND_PRINT_BUFFER>
PRINT_TEMPLATE:
    .byte NFS_PRINTER_PORT
    .byte NFS_TEMPLATE_SKIP, NFS_TEMPLATE_SKIP ; the printer server's station and network
    .byte NFS_PRINT_BUFFER, NFS_TEMPLATE_SKIP, $FF, $FF ; the buffer's start
    .byte NFS_TEMPLATE_SKIP, NFS_TEMPLATE_SKIP, $FF, $FF ; its end

; ---------------------------------------------------------------------------------------------------------------------
; The network printer
; ---------------------------------------------------------------------------------------------------------------------

;; NETV 5: OSBYTE 5 is selecting a printer type. Selecting the network printer empties the printer's block and sets
;; NFS_PRINT_STATE to &41; any other type leaves NFS_PRINT_STATE at A, 5.
;; In: A = 5, X = 5, OS_X = the new printer type
;; Uses: A (&41 for the network printer), X
NETV_PRINTER_TYPE:
    dex
    cpx OS_X
    bne NETV_PRINTER_TYPE_SET
    lda #NFS_PRINT_BUFFER
    sta NFS_PRINT_INDEX
    lda #$41
NETV_PRINTER_TYPE_SET:
    sta NFS_PRINT_STATE
NETV_PRINTER_DONE:
    rts

;; NETV 1-3 for the network printer, printer type 4.
;;
;; Reason 1, characters waiting in the printer buffer: takes them all into the network printer's buffer, sending
;; each block that fills, and returns with carry set, leaving the driver dormant. Reasons 2 and 3 go to
;; <NETV_PRINTER_VDU>.
;; In: X = the reason, Y = the printer type
;; Uses: A, X, Y
NETV_PRINTER:
    cpy #NFS_NETWORK_PRINTER
    bne NETV_PRINTER_DONE
    txa
    dex
    bne NETV_PRINTER_VDU
    tsx
    ora STACK + 6,x                     ; set the stacked carry
    sta STACK + 6,x
NETV_PRINTER_DRAIN:
    lda #NFS_OSBYTE_READ_BUFFER
    ldx #NFS_BUFFER_PRINTER
    jsr OSBYTE
    bcs NETV_PRINTER_DONE               ; the buffer is empty
    tya
    jsr ADD_TO_PRINT_BUFFER
    cpy #NFS_PRINT_BUFFER_LAST
    bcc NETV_PRINTER_DRAIN
    jsr SEND_PRINT_BUFFER
    bcc NETV_PRINTER_DRAIN              ; always

;; Puts a byte in the network printer's buffer.
;; In: A = the byte
;; Out: Y = the offset it went to
;; Keeps: A, X
ADD_TO_PRINT_BUFFER:
    ldy NFS_PRINT_INDEX
    sta (NFS_WORKSPACE_PAGE),y
    inc NFS_PRINT_INDEX
    rts

;; NETV 2 and 3, VDU 2 and VDU 3, for the network printer.
;;
;; Puts a marker in the buffer, 0 for VDU 2 or 3 for VDU 3. When VDU 2 comes after VDU 3, or VDU 3 after VDU 2, the
;; buffer is sent, for VDU 3 after bit 0 of NFS_PRINT_STATE has been set (the control byte carries it). Then bit 0 of
;; NFS_PRINT_STATE is set for VDU 3 and cleared for VDU 2, and bits 1-3 cleared.
;; In: A = the reason, X = the reason less one
;; Uses: A, X, Y
NETV_PRINTER_VDU:
    pha
    txa
    eor #$01                            ; 0 for VDU 2, 3 for VDU 3
    jsr ADD_TO_PRINT_BUFFER
    eor NFS_PRINT_STATE
    ror a
    bcc NETV_PRINTER_VDU_STATE          ; no change
    rol a
    sta NFS_PRINT_STATE
    jsr SEND_PRINT_BUFFER
NETV_PRINTER_VDU_STATE:
    lda NFS_PRINT_STATE                 ; keep bits 4-7 and take bit 0 from the reason
    and #$F0
    ror a
    tax
    pla
    ror a
    txa
    rol a
    sta NFS_PRINT_STATE
    rts

;; Sends the network printer's buffer to the printer server, port &D1, and waits for its acknowledgement.
;;
;; The control byte is bits 0-6 of NFS_PRINT_STATE shifted left, with bit 0 the sequence bit, bit 7 of
;; NFS_PRINT_STATE, which is then flipped for the next block. The buffer is emptied.
;; Out: carry = clear
;; Uses: A, X, Y, NFS_BLOCK_POINTER
;; See: <PRINT_TEMPLATE>, <SEND_SEQUENCED_BLOCK>
SEND_PRINT_BUFFER:
    ldy #NFS_PRINT_BLOCK + 8            ; the buffer's end: the next free byte
    lda NFS_PRINT_INDEX
    sta (NFS_BLOCKS_PAGE),y
    lda NFS_WORKSPACE_PAGE + 1
    iny
    sta (NFS_BLOCKS_PAGE),y
    ldy #NFS_PRINT_BLOCK + 5            ; the start's page
    sta (NFS_BLOCKS_PAGE),y
    ldy #NFS_PRINT_BLOCK + 11
    ldx #PRINT_TEMPLATE - OS_PROCEDURE_TEMPLATE + 10
    jsr BUILD_BLOCK
    dey
    lda NFS_PRINT_STATE
    pha
    rol a                               ; carry = the sequence bit
    pla
    eor #$80                            ; flip it for the next block
    sta NFS_PRINT_STATE
    rol a
    sta (NFS_BLOCKS_PAGE),y          ; the control byte
    ldy #NFS_PRINT_BUFFER
    sty NFS_PRINT_INDEX
    lda #$00                            ; no file's sequence bit
    tax                                 ; X/Y = NFS_PRINT_BLOCK
    ldy NFS_BLOCKS_PAGE + 1
    cli
    ; Falls through into SEND_SEQUENCED_BLOCK.

;; Transmits a control block, then waits for the acknowledgement, a reply whose control byte has the same bit 0.
;;
;; The data transfers to the file server number their blocks with a bit for each file in NFS_SEQUENCE_BITS; the
;; network printer numbers them with bit 7 of NFS_PRINT_STATE, already in the control byte. The acknowledgement is
;; received over the same block, on port &90 for the file server or &D1 for the printer server. ESCAPE can abandon
;; the transmission's retries when NFS_ESCAPE_ENABLE allows it, but not the wait for the acknowledgement, which
;; ends only with one or "No reply".
;; In: A = the file's bit in NFS_SEQUENCE_BITS, or 0 for the printer, X/Y = the control block
;; Out: A = NFS_SEQUENCE_BITS with that bit flipped
;; Uses: X, Y, NFS_BLOCK_POINTER
;; See: <TRANSMIT>, <AWAIT_RECEPTION>
SEND_SEQUENCED_BLOCK:
    stx NFS_BLOCK_POINTER
    sty NFS_BLOCK_POINTER + 1
    pha
    and NFS_SEQUENCE_BITS
    beq SEND_SEQUENCED_BLOCK_BIT
    lda #$01
SEND_SEQUENCED_BLOCK_BIT:
    ldy #$00
    ora (NFS_BLOCK_POINTER),y           ; the sequence bit into the control byte
    pha
    sta (NFS_BLOCK_POINTER),y
    jsr TRANSMIT
    lda #$FF                            ; the acknowledgement may fill the I/O processor's memory to &FFFF
    ldy #$08
    sta (NFS_BLOCK_POINTER),y
    iny
    sta (NFS_BLOCK_POINTER),y
    pla
    tax                                 ; the control byte sent
    ldy #NFS_PRINTER_PORT
    pla
    pha
    beq SEND_SEQUENCED_BLOCK_PORT
    ldy #NFS_PORT_REPLY
SEND_SEQUENCED_BLOCK_PORT:
    tya
    ldy #$01
    sta (NFS_BLOCK_POINTER),y
    txa
    dey
    pha
SEND_SEQUENCED_BLOCK_WAIT:
    lda #NFS_CONTROL_RECEIVE
    sta (NFS_BLOCK_POINTER),y
    jsr AWAIT_RECEPTION
    pla
    pha
    eor (NFS_BLOCK_POINTER),y
    ror a
    bcs SEND_SEQUENCED_BLOCK_WAIT       ; the wrong sequence bit: wait for another
    pla
    pla
    eor NFS_SEQUENCE_BITS
    rts

; ---------------------------------------------------------------------------------------------------------------------
; OS procedure call 2
; ---------------------------------------------------------------------------------------------------------------------

;; OS procedure call 2 (the NFS's language entry with X = 2): collects this machine's screen state at
;; NFS_SCREEN_STATE in the second workspace page, where the calling station can read it.
;;
;; From &E9: the screen start address, the MOS's byte address (two bytes; the 6845 is given it divided by eight in
;; modes 0-6, and converted otherwise in mode 7); the physical colours of logical colours
;; 0-15 (sixteen bytes); the screen mode; the bottom of that mode's screen memory (two bytes); then the two flashing
;; colours' durations. It falls into <RESTORE_PROTECTION>.
;; Uses: A, X, Y
;; Keeps: NFS_SCREEN_STATE_INDEX
;; See: <NFS_PROCEDURE_CALL>
READ_SCREEN_STATE:
    lda NFS_SCREEN_STATE_INDEX
    pha
    lda #NFS_SCREEN_STATE
    sta NFS_BLOCKS_PAGE
    ldy #$00
    sty NFS_SCREEN_STATE_INDEX
    lda SCREEN_START
    sta (NFS_BLOCKS_PAGE),y
    inc NFS_BLOCKS_PAGE
    lda SCREEN_START + 1
    pha
    tya
READ_SCREEN_STATE_PALETTE:
    sta (NFS_BLOCKS_PAGE),y          ; OSWORD &0B's block: the logical colour
    ldx NFS_BLOCKS_PAGE
    ldy NFS_BLOCKS_PAGE + 1
    lda #NFS_OSWORD_READ_PALETTE
    jsr OSWORD
    pla                                 ; put back the byte the block overwrote
    ldy #$00
    sta (NFS_BLOCKS_PAGE),y
    iny
    lda (NFS_BLOCKS_PAGE),y          ; the physical colour, which the next block overwrites
    pha
    ldx NFS_BLOCKS_PAGE
    inc NFS_BLOCKS_PAGE
    inc NFS_SCREEN_STATE_INDEX
    dey
    lda NFS_SCREEN_STATE_INDEX
    cpx #NFS_SCREEN_STATE + 16
    bne READ_SCREEN_STATE_PALETTE
    pla
    sty NFS_SCREEN_STATE_INDEX
    inc NFS_BLOCKS_PAGE
    jsr STORE_SCREEN_MODE
    inc NFS_BLOCKS_PAGE              ; from &FF round to 0, the page's start
    pla
    sta NFS_SCREEN_STATE_INDEX
    ; Falls through into RESTORE_PROTECTION.

;; Restores NFS_PROTECTION from NFS_SAVED_PROTECTION, as it was before the immediate operation that is ending.
;; Uses: A
;; Keeps: X, Y
RESTORE_PROTECTION:
    lda NFS_SAVED_PROTECTION
    sta NFS_PROTECTION
    rts

;; Stores the screen mode, the bottom of its screen memory and the two flashing colours' durations, for
;; <READ_SCREEN_STATE>.
;; In: NFS_BLOCKS_PAGE = where the mode goes, Y = 0, NFS_SCREEN_STATE_INDEX = 0
;; Out: NFS_BLOCKS_PAGE = the last byte stored, X = 0
;; Uses: A, Y
STORE_SCREEN_MODE:
    lda SCREEN_MODE
    sta (NFS_BLOCKS_PAGE),y
    tax
    jsr STORE_OSBYTE                    ; OSBYTE &85 for the mode
    inc NFS_BLOCKS_PAGE
    tya
    sta (NFS_BLOCKS_PAGE,x)          ; its high byte
    jsr STORE_OSBYTE_READ               ; OSBYTE &C2; falling through makes &C3
    ; Falls through into STORE_OSBYTE_READ.

;; Makes the next OSBYTE in <NFS_SCREEN_STATE_OSBYTES> and stores the X it returns in the next byte of the second
;; workspace page.
;; In: NFS_BLOCKS_PAGE = the byte before
;; Out: NFS_BLOCKS_PAGE = the byte stored, X = 0, Y = the OSBYTE's Y
;; Uses: A
;; Entry: STORE_OSBYTE = makes the OSBYTE with the X given, not 0
STORE_OSBYTE_READ:
    ldx #$00
STORE_OSBYTE:
    ldy NFS_SCREEN_STATE_INDEX
    inc NFS_SCREEN_STATE_INDEX
    inc NFS_BLOCKS_PAGE
    lda NFS_SCREEN_STATE_OSBYTES,y
    ldy #$FF
    jsr OSBYTE
    txa
    ldx #$00
    sta (NFS_BLOCKS_PAGE,x)
    rts

;; The OSBYTEs <STORE_SCREEN_MODE> makes, in order.
NFS_SCREEN_STATE_OSBYTES:
    .byte NFS_OSBYTE_SCREEN_BOTTOM, NFS_OSBYTE_MARK_PERIOD, NFS_OSBYTE_SPACE_PERIOD
