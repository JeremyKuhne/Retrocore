;; The Tube host code ($9321-$962F), which the NFS copies to zero page and pages four to six when a Tube is fitted.
;;
;; With a second processor (the parasite) on the Tube, this machine (the host) runs no language: it serves the
;; parasite's operating system calls. The code is in two parts, both copied by the NFS's Tube start-up in
;; NetService.asm (<START_TUBE>), which also points BRKV at <TUBE_BRK_HANDLER> and EVNTV at <TUBE_SEND_EVENT>:
;;
;; - &9321-&9361 runs at &0016-&0056: the BRK handler, which passes errors to the parasite, and the idle loop, which
;;   waits for the parasite's characters and calls. The copy takes &61 bytes, so the start of the next part also
;;   lands at &0057-&0076, unused.
;; - &9362-&962F runs at &0400-&06CD: the three entries the MOS and the filing systems call (&0400, &0403 and &0406,
;;   the MOS's TUBE_CODE, TUBE_ESCAPE and TUBE_TRANSFER), claiming and releasing the Tube, starting
;;   transfers through register 3, copying a language across, and a routine for each call the parasite makes. The
;;   copy takes three whole pages from &9362, so &9630-&9661 (the start of Econet.asm, which runs in the ROM) also
;;   lands at &06CE-&06FF, unused.
;;
;; The Tube's four registers each carry their own traffic, as this code uses them:
;;
;; - Register 1, parasite to host: the characters the parasite's OSWRCH prints. Host to parasite: escapes (a byte
;;   with bit 7 set, bit 6 the escape flag) and events (0, then Y, X and A).
;; - Register 2: the parasite's calls, each a command byte (an even number, the offset in <TUBE_COMMANDS>) and its
;;   parameters, and the host's replies.
;; - Register 3: the data of transfers to and from the parasite's memory.
;; - Register 4, host to parasite: the start of each transfer, the release of the Tube, and errors (&FF).
;;
;; A status register's bit 7 is set when its data register holds a byte to read, and bit 6 when it has room for one
;; to be written. Writing register 1's status register sets (bit 7 set) or clears (bit 7 clear) the Tube's flags
;; that bits 0-6 pick.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; Zero page. The host runs no language, so the Tube code uses the language's zero page as well as its own.
TUBE_BLOCK = $00                    ;; &00-&11, where the host builds the control blocks of the parasite's calls
TUBE_COPY_POINTER = $00             ;; while a language is copied across, the address in the ROM, low byte 0
TUBE_BLOCK_POINTER = $12            ;; the control block of the transfer being started, two bytes
TUBE_FREE = $14                     ;; bit 7 set while nobody has claimed the Tube
TUBE_CLAIMANT = $15                 ;; the claim (&C0 plus the claimant's number) of whoever has the Tube

; Other memory.
TUBE_STRING = $0700                 ;; the file names and commands the parasite sends, ending in a carriage return
TUBE_OSWORD_BLOCK = STACK + $28     ;; where an OSWORD's control block is put, at the bottom of the stack page

; The bytes on the registers.
TUBE_REPLY_DONE = $7F               ;; on register 2: a call that returns nothing is done, or a line was read
TUBE_REPLY_ESCAPE = $FF             ;; on register 2: OSWORD 0 ended with ESCAPE
TUBE_ERROR_SIGNAL = $FF             ;; on register 4: an error follows on register 2
TUBE_RELEASE_CODE = $05             ;; on register 4: release the Tube, then the claimant

; Claims and transfers.
TUBE_CLAIM_LANGUAGE = $FF           ;; the claim this code makes to copy a language, claimant &3F
TUBE_TYPE_EXECUTE = 4               ;; transfer type 4: start the parasite running at the address
TUBE_TYPE_PAGE = 7                  ;; transfer type 7: a page from the host to the parasite, as a language is copied
TUBE_CLEAR_FLAGS = $18              ;; register 1 status: clears the flags of bits 3 and 4 before a transfer
TUBE_SET_FLAG_3 = $88               ;; register 1 status: sets the flag of bit 3
TUBE_ROM_RELOCATES = %00100000      ;; ROM_TYPE: the ROM gives a relocation address after its copyright string

; Calls.
TUBE_OSBYTE_BREAK_TYPE = $FD        ;; OSBYTE &FD: read the type of the last BREAK, 0 for a soft BREAK
TUBE_OSBYTE_FAST_BPUT = $9D         ;; OSBYTE &9D: fast Tube BPUT, which gets no reply
TUBE_RETURN = $0D                   ;; the carriage return that ends a string from the parasite

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: &0016-&0056
; ---------------------------------------------------------------------------------------------------------------------

;; The ROM address of the zero page part, which <START_TUBE> copies to TUBE_BRK_HANDLER.
TUBE_ZERO_PAGE_IMAGE = *

    .logicalorg $0016

;; The BRK handler while a Tube is fitted, where BRKV points: passes the error to the parasite, then goes back to
;; waiting for the parasite.
;;
;; It sends &FF on register 4, which interrupts the parasite, empties register 2, then sends on register 2 a zero,
;; the error number and the message, ending with its zero.
;; In: ERROR_POINTER = the error number, after the BRK
;; See: <TUBE_IDLE>
TUBE_BRK_HANDLER:
    lda #TUBE_ERROR_SIGNAL
    jsr TUBE_SEND_R4
    lda TUBE_R2_DATA                    ; discard a byte the parasite has sent
    lda #$00
    jsr TUBE_SEND_R2
    tay
    lda (ERROR_POINTER),y               ; the error number
    jsr TUBE_SEND_R2
TUBE_BRK_HANDLER_LOOP:
    iny
    lda (ERROR_POINTER),y               ; the message, then its zero
    jsr TUBE_SEND_R2
    tax
    bne TUBE_BRK_HANDLER_LOOP
    ; Falls through into TUBE_RESTART.

;; Empties the stack and enters <TUBE_IDLE>, with interrupts enabled.
TUBE_RESTART:
    ldx #$FF
    txs
    cli
    ; Falls through into TUBE_IDLE.

;; The host's idle loop: prints the characters the parasite sends on register 1 and carries out the calls it sends
;; on register 2, characters first.
;;
;; A call's command byte, which is even, picks its routine from <TUBE_COMMANDS> by changing the low byte of the
;; address in the JMP indirect at <TUBE_COMMAND_JUMP>. Each routine reads its parameters from register 2, makes the
;; call, sends the results on register 2 and jumps back here.
TUBE_IDLE:
    bit TUBE_R1_STATUS
    bpl TUBE_IDLE_CALL                  ; no character
TUBE_IDLE_OSWRCH:
    lda TUBE_R1_DATA
    jsr OSWRCH
TUBE_IDLE_CALL:
    bit TUBE_R2_STATUS
    bpl TUBE_IDLE                       ; no call
    bit TUBE_R1_STATUS
    bmi TUBE_IDLE_OSWRCH                ; a character came first
    ldx TUBE_R2_DATA                    ; the command
    stx z:TUBE_COMMAND_JUMP + 1

;; The JMP indirect through <TUBE_COMMANDS>, whose low byte <TUBE_IDLE> sets to the command.
TUBE_COMMAND_JUMP:
    jmp (TUBE_COMMANDS)

;; The address in the parasite that a language is copied to and started at, four bytes: &8000, or the language's
;; relocation address. <TUBE_FIND_LANGUAGE_ADDRESS> sets it.
TUBE_LANGUAGE_ADDRESS:
    .dword LANGUAGE_ENTRY

    .logicalorg

; ---------------------------------------------------------------------------------------------------------------------
; Pages four to six: &0400-&06CD
; ---------------------------------------------------------------------------------------------------------------------

;; The ROM address of the part in pages four to six, which <START_TUBE> copies to TUBE_ENTRY_CODE.
TUBE_PAGES_IMAGE = *

    .logicalorg $0400

;; TUBE_CODE, &0400: the MOS enters here instead of a language when a Tube is fitted.
;; In: A = 1 to start a language, or 0 when there is none, zero = set when A is 0,
;;   carry = set when OSBYTE &8E (such as *BASIC) is starting it, clear at reset
;; See: <TUBE_START_LANGUAGE>
TUBE_ENTRY_CODE:
    jmp TUBE_START_LANGUAGE

;; TUBE_ESCAPE, &0403: the MOS comes here when the escape flag changes.
;; See: <TUBE_SEND_ESCAPE>
TUBE_ENTRY_ESCAPE:
    jmp TUBE_SEND_ESCAPE

;; TUBE_TRANSFER, &0406: claims or releases the Tube, or starts a transfer, for a filing system or other claimant.
;;
;; - A = &C0 plus the claimant's number (0-&3F) claims the Tube: carry is set when it was free, or already this
;;   claimant's, and clear when someone else has it, when the claim should be tried again.
;; - A = &80 plus the claimant's number releases the Tube, if that claimant has it.
;; - A = 0-7 starts a transfer of that type with the parasite's memory, by the Tube's holder (<TUBE_START_TRANSFER>).
;;   The Advanced User Guide documents types 0 (read the parasite's memory through register 3), 1 (write it) and 4
;;   (start the parasite running there).
;; In: A = the call, X/Y = the transfer's control block, its four-byte address, low byte first
;; Out: carry = set when a claim succeeded
;; Uses: A, X, Y
TUBE_ENTRY_TRANSFER:
    cmp #$80
    bcc TUBE_START_TRANSFER
    cmp #$C0
    bcs TUBE_CLAIM
    ora #$40                            ; the claimant's claim
    cmp TUBE_CLAIMANT
    bne TUBE_CLAIM_DONE                 ; it doesn't have the Tube
    ; Falls through into TUBE_RELEASE.

;; Releases the Tube: tells the parasite, on register 4, then marks it free.
;; Out: A = &80
;; Uses: A
;; Keeps: X, Y
;; Entry: TUBE_MARK_FREE = only marks the Tube free, without telling the parasite
TUBE_RELEASE:
    php
    sei
    lda #TUBE_RELEASE_CODE
    jsr TUBE_SEND_R4
    lda TUBE_CLAIMANT
    jsr TUBE_SEND_R4
    plp
TUBE_MARK_FREE:
    lda #$80                            ; free, and a claimant no claim matches
    sta TUBE_CLAIMANT
    sta TUBE_FREE
    rts

;; Claims the Tube, for <TUBE_ENTRY_TRANSFER>.
;; In: A = the claim, &C0 plus the claimant's number
;; Out: carry = set when it is this claimant's
;; Keeps: A, X, Y
TUBE_CLAIM:
    asl TUBE_FREE                       ; carry = free, and now not free
    bcs TUBE_CLAIM_TAKE
    cmp TUBE_CLAIMANT
    beq TUBE_CLAIM_DONE                 ; carry set: it already has it
    clc
    rts
TUBE_CLAIM_TAKE:
    sta TUBE_CLAIMANT
TUBE_CLAIM_DONE:
    rts

;; Starts a transfer between the parasite's memory and register 3, for <TUBE_ENTRY_TRANSFER>.
;;
;; It sends on register 4 the type, the claimant and the address, high byte first, sets the Tube's flags for the
;; type from <TUBE_TRANSFER_FLAGS>, then sends one more byte on register 4 and waits for the parasite to take it.
;; Types whose flags have bit 1 set have register 3 emptied before that byte, and those that also have bit 2 set
;; have the flag of bit 3 set after it. Type 4 starts the parasite running: the Tube is released, &80 is sent on
;; register 2 and the host goes back to <TUBE_RESTART>, never returning.
;; In: A = the type, X/Y = the control block
;; Uses: A, X, Y
TUBE_START_TRANSFER:
    php
    sei
    sty TUBE_BLOCK_POINTER + 1
    stx TUBE_BLOCK_POINTER
    jsr TUBE_SEND_R4
    tax
    ldy #$03
    lda TUBE_CLAIMANT
    jsr TUBE_SEND_R4
TUBE_START_TRANSFER_ADDRESS:
    lda (TUBE_BLOCK_POINTER),y
    jsr TUBE_SEND_R4
    dey
    bpl TUBE_START_TRANSFER_ADDRESS
    ldy #TUBE_CLEAR_FLAGS
    sty TUBE_R1_STATUS
    lda TUBE_TRANSFER_FLAGS,x
    sta TUBE_R1_STATUS                  ; set the type's flags
    lsr a
    lsr a                               ; carry = bit 1
    bcc TUBE_START_TRANSFER_SYNC
    bit TUBE_R3_DATA                    ; empty register 3
    bit TUBE_R3_DATA
TUBE_START_TRANSFER_SYNC:
    jsr TUBE_SEND_R4
TUBE_START_TRANSFER_WAIT:
    bit TUBE_R4_STATUS                  ; wait until the parasite has taken it
    bvc TUBE_START_TRANSFER_WAIT
    bcs TUBE_START_TRANSFER_FLAG
    cpx #TUBE_TYPE_EXECUTE
    bne TUBE_START_TRANSFER_DONE
    ; Falls through into TUBE_EXECUTE.

;; Releases the Tube, sends &80 on register 2 and goes back to waiting for the parasite, which starts running.
TUBE_EXECUTE:
    jsr TUBE_RELEASE
    jsr TUBE_SEND_R2                    ; &80, from TUBE_RELEASE
    jmp TUBE_RESTART

; The rest of TUBE_START_TRANSFER.
TUBE_START_TRANSFER_FLAG:
    lsr a                               ; carry = bit 2
    bcc TUBE_START_TRANSFER_DONE
    ldy #TUBE_SET_FLAG_3
    sty TUBE_R1_STATUS
TUBE_START_TRANSFER_DONE:
    plp
    rts

;; Starts the parasite after a reset or BREAK, or copies a language across to it, for <TUBE_ENTRY_CODE>.
;;
;; With no language, it sends &7F on register 2. After a soft BREAK it copies nothing: it releases the Tube and
;; sends &80 on register 2. Otherwise, and whenever OSBYTE &8E is starting a language, it copies the language ROM
;; (&8000-&BFFF) to the parasite, a page at a time through register 3, and starts it at its address there. Each way
;; it ends in <TUBE_IDLE>.
;; In: A = 1 for a language or 0 for none, zero = set when A is 0, carry = set for OSBYTE &8E
TUBE_START_LANGUAGE:
    cli
    bcs TUBE_COPY_LANGUAGE
    bne TUBE_START_LANGUAGE_BREAK
    jmp TUBE_REPLY_DONE_SEND            ; no language
TUBE_START_LANGUAGE_BREAK:
    ldx #$00
    ldy #$FF
    lda #TUBE_OSBYTE_BREAK_TYPE
    jsr OSBYTE
    txa
    beq TUBE_EXECUTE                    ; a soft BREAK
TUBE_COPY_LANGUAGE:
    lda #TUBE_CLAIM_LANGUAGE
    jsr TUBE_ENTRY_TRANSFER
    bcc TUBE_COPY_LANGUAGE              ; until the Tube is ours
    jsr TUBE_FIND_LANGUAGE_ADDRESS
TUBE_COPY_LANGUAGE_PAGE:
    lda #TUBE_TYPE_PAGE
    jsr TUBE_LANGUAGE_TRANSFER
    ldy #$00
    sty TUBE_COPY_POINTER
TUBE_COPY_LANGUAGE_BYTE:
    lda (TUBE_COPY_POINTER),y
    sta TUBE_R3_DATA
    nop                                 ; give the parasite time to take it
    nop
    nop
    iny
    bne TUBE_COPY_LANGUAGE_BYTE
    inc TUBE_LANGUAGE_ADDRESS + 1       ; the next page in the parasite
    bne TUBE_COPY_LANGUAGE_NEXT
    inc TUBE_LANGUAGE_ADDRESS + 2
    bne TUBE_COPY_LANGUAGE_NEXT
    inc TUBE_LANGUAGE_ADDRESS + 3
TUBE_COPY_LANGUAGE_NEXT:
    inc TUBE_COPY_POINTER + 1
    bit TUBE_COPY_POINTER + 1           ; until page &C0, which has bit 6 set
    bvc TUBE_COPY_LANGUAGE_PAGE
    jsr TUBE_FIND_LANGUAGE_ADDRESS
    lda #TUBE_TYPE_EXECUTE
    ; Falls through into TUBE_LANGUAGE_TRANSFER.

;; Starts a transfer with <TUBE_LANGUAGE_ADDRESS> as its address.
;; In: A = the type
;; Uses: A, X, Y
TUBE_LANGUAGE_TRANSFER:
    ldy #>TUBE_LANGUAGE_ADDRESS
    ldx #<TUBE_LANGUAGE_ADDRESS
    jmp TUBE_ENTRY_TRANSFER

;; Sets <TUBE_LANGUAGE_ADDRESS> to where the selected language ROM goes in the parasite, and TUBE_COPY_POINTER's
;; high byte to &80, its start.
;;
;; That is &8000 unless bit 5 of the ROM's type says that a four-byte relocation address follows the zero that ends
;; the copyright string.
;; Uses: A, X, Y
TUBE_FIND_LANGUAGE_ADDRESS:
    lda #>LANGUAGE_ENTRY
    sta TUBE_LANGUAGE_ADDRESS + 1
    sta TUBE_COPY_POINTER + 1
    lda #TUBE_ROM_RELOCATES
    and ROM_TYPE
    tay
    sty TUBE_LANGUAGE_ADDRESS           ; 0 when there is no relocation address
    beq TUBE_FIND_LANGUAGE_ADDRESS_SET
    ldx COPYRIGHT_OFFSET
TUBE_FIND_LANGUAGE_ADDRESS_LOOP:
    inx                                 ; find the zero that ends the copyright string
    lda LANGUAGE_ENTRY,x
    bne TUBE_FIND_LANGUAGE_ADDRESS_LOOP
    lda LANGUAGE_ENTRY + 1,x
    sta TUBE_LANGUAGE_ADDRESS
    lda LANGUAGE_ENTRY + 2,x
    sta TUBE_LANGUAGE_ADDRESS + 1
    ldy LANGUAGE_ENTRY + 3,x
    lda LANGUAGE_ENTRY + 4,x
TUBE_FIND_LANGUAGE_ADDRESS_SET:
    sta TUBE_LANGUAGE_ADDRESS + 3
    sty TUBE_LANGUAGE_ADDRESS + 2
    rts

;; The routines for the parasite's calls, at &0500, indexed by the command byte it sends on register 2.
;; See: <TUBE_IDLE>
TUBE_COMMANDS:
    .word TUBE_OSRDCH                   ; &00
    .word TUBE_OSCLI                    ; &02
    .word TUBE_OSBYTE_SHORT             ; &04, an OSBYTE that returns only X
    .word TUBE_OSBYTE_LONG              ; &06, an OSBYTE that returns carry, Y and X
    .word TUBE_OSWORD                   ; &08
    .word TUBE_READ_LINE                ; &0A, OSWORD 0
    .word TUBE_OSARGS                   ; &0C
    .word TUBE_OSBGET                   ; &0E
    .word TUBE_OSBPUT                   ; &10
    .word TUBE_OSFIND                   ; &12
    .word TUBE_OSFILE                   ; &14
    .word TUBE_OSGBPB                   ; &16

;; The Tube's flags for each transfer type, 0-7, which <TUBE_START_TRANSFER> writes to register 1's status register.
;;
;; Bit 7 set sets the flags that bits 0-6 pick, and bit 7 clear clears them. Bit 1 also has register 3 emptied
;; before the transfer starts, and bits 1 and 2 together have the flag of bit 3 set once it has.
TUBE_TRANSFER_FLAGS:
    .byte $86                           ; 0, reading the parasite's memory
    .byte $88                           ; 1, writing it
    .byte $96                           ; 2
    .byte $98                           ; 3
    .byte $18                           ; 4, starting the parasite: only clears flags
    .byte $18                           ; 5
    .byte $82                           ; 6
    .byte $18                           ; 7, a page to the parasite

; ---------------------------------------------------------------------------------------------------------------------
; The parasite's calls
; ---------------------------------------------------------------------------------------------------------------------

;; Command &10, OSBPUT. Register 2 brings Y (the handle) and the byte; the reply is &7F.
TUBE_OSBPUT:
    jsr TUBE_READ_R2
    tay
    jsr TUBE_READ_R2
    jsr OSBPUT
    jmp TUBE_REPLY_DONE_SEND

;; Command &0E, OSBGET. Register 2 brings Y (the handle); the reply is the carry (in bit 7) and the byte.
TUBE_OSBGET:
    jsr TUBE_READ_R2
    tay
    jsr OSBGET
    jmp TUBE_REPLY_CARRY

;; Command &00, OSRDCH. The reply is the carry (in bit 7, set after ESCAPE) and the character.
TUBE_OSRDCH:
    jsr OSRDCH
    ; Falls through into TUBE_REPLY_CARRY.

;; Sends the carry, in bit 7 of a byte, then A, on register 2, and goes back to <TUBE_IDLE>.
;; In: A = the result, carry = the result
TUBE_REPLY_CARRY:
    ror a
    jsr TUBE_SEND_R2
    rol a
    jmp TUBE_REPLY

;; Command &12, OSFIND. Register 2 brings A. To open a file, A is followed by the name, ending in a carriage return,
;; and the reply is the handle; to close one (A = 0), it is followed by Y (the handle), and the reply is &7F.
TUBE_OSFIND:
    jsr TUBE_READ_R2
    beq TUBE_OSFIND_CLOSE
    pha
    jsr TUBE_READ_STRING
    pla
    jsr OSFIND
    jmp TUBE_REPLY
TUBE_OSFIND_CLOSE:
    jsr TUBE_READ_R2
    tay
    lda #$00
    jsr OSFIND
    jmp TUBE_REPLY_DONE_SEND

;; Command &0C, OSARGS. Register 2 brings Y (the handle), the four bytes of the control block, last first, then A.
;; The reply is A, then the four bytes, last first.
TUBE_OSARGS:
    jsr TUBE_READ_R2
    tay
    ldx #$04
TUBE_OSARGS_LOOP:
    jsr TUBE_READ_R2
    sta (TUBE_BLOCK - 1) & $FF,x        ; &FF+X wraps round zero page: &03 down to &00
    dex
    bne TUBE_OSARGS_LOOP
    jsr TUBE_READ_R2
    jsr OSARGS                          ; the block at X = TUBE_BLOCK
    jsr TUBE_SEND_R2
    ldx #$03
TUBE_OSARGS_REPLY:
    lda TUBE_BLOCK,x
    jsr TUBE_SEND_R2
    dex
    bpl TUBE_OSARGS_REPLY
    jmp TUBE_IDLE

;; Reads a string from register 2 into TUBE_STRING: up to a carriage return, which is kept, or 256 bytes.
;; Out: X/Y = TUBE_STRING
;; Uses: A
TUBE_READ_STRING:
    ldx #<TUBE_STRING
    ldy #$00
TUBE_READ_STRING_LOOP:
    jsr TUBE_READ_R2
    sta TUBE_STRING,y
    iny
    beq TUBE_READ_STRING_DONE
    cmp #TUBE_RETURN
    bne TUBE_READ_STRING_LOOP
TUBE_READ_STRING_DONE:
    ldy #>TUBE_STRING
    rts

;; Command &02, OSCLI. Register 2 brings the command, ending in a carriage return; the reply is &7F.
;;
;; A command that starts the parasite running (a *RUN of a file in its memory) sends &80 instead, through a type 4
;; transfer, and does not come back here.
TUBE_OSCLI:
    jsr TUBE_READ_STRING
    jsr OSCLI
    ; Falls through into TUBE_REPLY_DONE_SEND.

;; Sends &7F on register 2 and goes back to <TUBE_IDLE>.
;; Entry: TUBE_REPLY = sends A instead
TUBE_REPLY_DONE_SEND:
    lda #TUBE_REPLY_DONE
TUBE_REPLY:
    bit TUBE_R2_STATUS
    bvc TUBE_REPLY
    sta TUBE_R2_DATA
TUBE_REPLY_IDLE:
    jmp TUBE_IDLE

;; Command &14, OSFILE. Register 2 brings bytes 2-17 of the control block (its addresses), last first, the file
;; name, ending in a carriage return, then A. The reply is A, then the sixteen bytes, last first.
TUBE_OSFILE:
    ldx #$10
TUBE_OSFILE_LOOP:
    jsr TUBE_READ_R2
    sta TUBE_BLOCK + 1,x                ; bytes 2-17
    dex
    bne TUBE_OSFILE_LOOP
    jsr TUBE_READ_STRING
    stx TUBE_BLOCK                      ; bytes 0-1: the name's address
    sty TUBE_BLOCK + 1
    ldy #>TUBE_BLOCK
    jsr TUBE_READ_R2
    jsr OSFILE                          ; the block at X = TUBE_BLOCK
    jsr TUBE_SEND_R2
    ldx #$10
TUBE_OSFILE_REPLY:
    lda TUBE_BLOCK + 1,x
    jsr TUBE_SEND_R2
    dex
    bne TUBE_OSFILE_REPLY
    beq TUBE_REPLY_IDLE                 ; always

;; Command &16, OSGBPB. Register 2 brings the control block's thirteen bytes, last first, then A. The reply is the
;; thirteen bytes, last first, then the carry (in bit 7) and A.
TUBE_OSGBPB:
    ldx #$0D
TUBE_OSGBPB_LOOP:
    jsr TUBE_READ_R2
    sta (TUBE_BLOCK - 1) & $FF,x        ; &FF+X wraps round zero page: &0C down to &00
    dex
    bne TUBE_OSGBPB_LOOP
    jsr TUBE_READ_R2
    ldy #>TUBE_BLOCK
    jsr OSGBPB                          ; the block at X = TUBE_BLOCK
    pha
    ldx #$0C
TUBE_OSGBPB_REPLY:
    lda TUBE_BLOCK,x
    jsr TUBE_SEND_R2
    dex
    bpl TUBE_OSGBPB_REPLY
    pla
    jmp TUBE_REPLY_CARRY

;; Command &04, an OSBYTE that returns only X. Register 2 brings X, then A; the reply is X.
TUBE_OSBYTE_SHORT:
    jsr TUBE_READ_R2
    tax
    jsr TUBE_READ_R2
    jsr OSBYTE
    ; Falls through into TUBE_REPLY_X.

;; Sends X on register 2 and goes back to <TUBE_IDLE>.
TUBE_REPLY_X:
    bit TUBE_R2_STATUS
    bvc TUBE_REPLY_X
    stx TUBE_R2_DATA
TUBE_REPLY_X_IDLE:
    jmp TUBE_IDLE

;; Command &06, an OSBYTE that returns carry, Y and X. Register 2 brings X, Y, then A; the reply is the carry (in bit
;; 7), Y and X. OSBYTE &9D, fast Tube BPUT, gets no reply.
TUBE_OSBYTE_LONG:
    jsr TUBE_READ_R2
    tax
    jsr TUBE_READ_R2
    tay
    jsr TUBE_READ_R2
    jsr OSBYTE
    eor #TUBE_OSBYTE_FAST_BPUT
    beq TUBE_REPLY_X_IDLE
    ror a
    jsr TUBE_SEND_R2
TUBE_OSBYTE_LONG_Y:
    bit TUBE_R2_STATUS
    bvc TUBE_OSBYTE_LONG_Y
    sty TUBE_R2_DATA
    bvs TUBE_REPLY_X                    ; always

;; Command &08, OSWORD (any but OSWORD 0). Register 2 brings A, then the length of the control block and its bytes, last
;; first; the block is put at TUBE_OSWORD_BLOCK. After the call it brings the length of the results, and the reply
;; is that many bytes of the block, last first.
TUBE_OSWORD:
    jsr TUBE_READ_R2
    tay
TUBE_OSWORD_IN_LENGTH:
    bit TUBE_R2_STATUS
    bpl TUBE_OSWORD_IN_LENGTH
    ldx TUBE_R2_DATA
    dex
    bmi TUBE_OSWORD_CALL                ; no bytes
TUBE_OSWORD_IN:
    bit TUBE_R2_STATUS
    bpl TUBE_OSWORD_IN
    lda TUBE_R2_DATA
    sta TUBE_OSWORD_BLOCK,x
    dex
    bpl TUBE_OSWORD_IN
    tya
TUBE_OSWORD_CALL:
    ldx #<TUBE_OSWORD_BLOCK
    ldy #>TUBE_OSWORD_BLOCK
    jsr OSWORD
TUBE_OSWORD_OUT_LENGTH:
    bit TUBE_R2_STATUS
    bpl TUBE_OSWORD_OUT_LENGTH
    ldx TUBE_R2_DATA
    dex
    bmi TUBE_OSWORD_DONE                ; no bytes
TUBE_OSWORD_OUT:
    ldy TUBE_OSWORD_BLOCK,x
TUBE_OSWORD_OUT_WAIT:
    bit TUBE_R2_STATUS
    bvc TUBE_OSWORD_OUT_WAIT
    sty TUBE_R2_DATA
    dex
    bpl TUBE_OSWORD_OUT
TUBE_OSWORD_DONE:
    jmp TUBE_IDLE

;; Command &0A, OSWORD 0, reading a line. Register 2 brings the control block's five bytes, last first, which are put
;; at TUBE_BLOCK; the line is read back from TUBE_STRING, so the block's buffer is expected to be there. The reply is
;; &FF after ESCAPE, otherwise &7F and the line, ending with its carriage return.
TUBE_READ_LINE:
    ldx #$04
TUBE_READ_LINE_BLOCK:
    jsr TUBE_READ_R2
    sta TUBE_BLOCK,x
    dex
    bpl TUBE_READ_LINE_BLOCK
    inx
    ldy #>TUBE_BLOCK
    txa                                 ; OSWORD 0
    jsr OSWORD
    bcc TUBE_READ_LINE_REPLY
    lda #TUBE_REPLY_ESCAPE
    jmp TUBE_REPLY
TUBE_READ_LINE_REPLY:
    ldx #$00
    lda #TUBE_REPLY_DONE
    jsr TUBE_SEND_R2
TUBE_READ_LINE_SEND:
    lda TUBE_STRING,x
    jsr TUBE_SEND_R2
    inx
    cmp #TUBE_RETURN
    bne TUBE_READ_LINE_SEND
    jmp TUBE_IDLE

; ---------------------------------------------------------------------------------------------------------------------
; The registers
; ---------------------------------------------------------------------------------------------------------------------

;; Sends a byte on register 2, once there is room.
;; In: A = the byte
;; Keeps: A, X, Y
TUBE_SEND_R2:
    bit TUBE_R2_STATUS
    bvc TUBE_SEND_R2
    sta TUBE_R2_DATA
    rts

;; Sends a byte on register 4, once there is room.
;; In: A = the byte
;; Keeps: A, X, Y
TUBE_SEND_R4:
    bit TUBE_R4_STATUS
    bvc TUBE_SEND_R4
    sta TUBE_R4_DATA
    rts

;; Passes the escape flag to the parasite: a byte on register 1 with bit 7 set and the escape flag in bit 6.
;; Uses: A
TUBE_SEND_ESCAPE:
    lda ESCAPE_FLAG
    sec
    ror a
    bmi TUBE_SEND_R1                    ; always

;; The event handler while a Tube is fitted, &06AD, where EVNTV points: passes the event to the parasite, sending 0,
;; Y, X and A on register 1.
;; In: A = the event, X and Y = its parameters
;; Keeps: A, X, Y
TUBE_SEND_EVENT:
    pha
    lda #$00
    jsr TUBE_SEND_R1
    tya
    jsr TUBE_SEND_R1
    txa
    jsr TUBE_SEND_R1
    pla
    ; Falls through into TUBE_SEND_R1.

;; Sends a byte on register 1, once there is room.
;; In: A = the byte
;; Keeps: A, X, Y
TUBE_SEND_R1:
    bit TUBE_R1_STATUS
    bvc TUBE_SEND_R1
    sta TUBE_R1_DATA
    rts

;; Waits for a byte on register 2 and reads it.
;; Out: A = the byte, zero = set when it is 0
;; Keeps: X, Y
TUBE_READ_R2:
    bit TUBE_R2_STATUS
    bpl TUBE_READ_R2
    lda TUBE_R2_DATA
    rts

    .logicalorg

    .assert TUBE_ENTRY_CODE = TUBE_CODE, "The Tube host code's entries are where the MOS calls them."
    .assert TUBE_ENTRY_ESCAPE = TUBE_ESCAPE, "TUBE_ESCAPE is the second entry."
    .assert TUBE_ENTRY_TRANSFER = TUBE_TRANSFER, "TUBE_TRANSFER is the third entry."
    .assert TUBE_COMMANDS = $0500, "The command table fills the start of page 5, which TUBE_IDLE indexes."
    .assert TUBE_SEND_EVENT = $06AD, "EVNTV is set to &06AD in NetService.asm."
    .assert TUBE_BRK_HANDLER = $0016, "BRKV is set to &0016 in NetService.asm."
    .assert TUBE_LANGUAGE_ADDRESS + 3 < $0100, "The language's address is in zero page."
