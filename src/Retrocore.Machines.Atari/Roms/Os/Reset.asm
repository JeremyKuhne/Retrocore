;; RESET: POWER-UP, SYSTEM RESET AND THE BOOTS ($F0E3-$F3E3)
;;
;; The handler table copied into HATABS, the start-up messages, the power-up (<COLD_START>) and SYSTEM RESET
;; (<WARM_START>) initialization, the cartridge checks, the cassette and disk boots, and the memo pad (<MEMO_PAD>),
;; which runs when no cartridge or booted program takes over. The OS User's Manual's section 7 lists the steps in
;; the order this code takes them, and its section 10 describes the boots.

; The start-up's constants.

RESET_LEFT_MARGIN = 2               ;; LMARGN's start-up value: the two leftmost columns are hidden on many televisions
RESET_RIGHT_MARGIN = 39             ;; RMARGN's start-up value, for a 38-character line
RESET_MEMLO = $0700                 ;; MEMLO's start-up value, the bottom of free memory before a boot moves it
RESET_MESSAGE_LENGTH = $FF          ;; the longest message the start-up prints; each ends sooner, at its end of line
CONSOL_START = $01                  ;; START's bit in CONSOL, 0 while held
MEMORY_TEST_STEP = $10              ;; the memory test's step, in pages: it tests the first byte of each 4K block
RIGHT_SLOT_RAM = $90                ;; a RAMSIZ at or above this: RAM fills the right cartridge's slot, so no cartridge
LEFT_SLOT_RAM = $B0                 ;; a RAMSIZ at or above this: RAM fills the left cartridge's slot, so no cartridge

; BOOTQ's bits.

BOOTQ_DISK = $01                    ;; a disk boot succeeded: SYSTEM RESET calls DOSINI
BOOTQ_CASSETTE = $02                ;; a cassette boot succeeded: SYSTEM RESET calls CASINI

; The boots.

BOOT_FIRST_SECTOR = 1               ;; the disk's first sector, where a boot starts
BOOT_UNIT = 1                       ;; the drive a boot reads, D1:
BOOT_BUFFER = CASBUF + 3            ;; $0400, where each boot sector or cassette record's data is read
BOOT_BLOCK_SIZE = 128               ;; the bytes in a boot sector or a cassette record
BOOT_HEADER_SIZE = 4                ;; the boot header's bytes copied to DFLAGS, DBSECT and BOOTAD
BOOT_DOSINI = BOOT_BUFFER + 4       ;; where the first block holds the booted program's DOSINI
BOOT_INIT_OFFSET = 6                ;; the offset from BOOTAD of the code that the boot calls once it has loaded
BOOT_SHORT_GAPS = $80               ;; FTYPE for short gaps between records, which a cassette boot reads

;; A handler's entry in <DEFAULT_HANDLERS>: its device letter and its table of vectors.
;; Parameters:
;;   letter = the device's name, such as 'E'
;;   table = the handler's table of vectors
.macro DEFAULT_HANDLER letter, table
    .byte letter
    .word table
.endmacro

;; The handler table that start-up copies to <HATABS>: the printer, the cassette, the screen editor, the display
;; and the keyboard.
;;
;; HATABS is cleared first, so the zero after these entries ends the table until DOS adds its own.
;; See: <COLD_START>, <HATABS>
DEFAULT_HANDLERS:
    DEFAULT_HANDLER 'P', PRINTV
    DEFAULT_HANDLER 'C', CASETV
    DEFAULT_HANDLER 'E', EDITRV
    DEFAULT_HANDLER 'S', SCRENV
    DEFAULT_HANDLER 'K', KEYBDV

;; The memo pad's message: a clear screen and its title.
;; See: <MEMO_PAD>
MEMO_PAD_MESSAGE:
    .byte CLEAR_SCREEN, "ATARI COMPUTER - MEMO PAD", EOL

;; The message a failed boot prints.
;; See: <SHOW_BOOT_ERROR>
BOOT_ERROR_MESSAGE:
    .byte "BOOT ERROR", EOL

;; The screen editor's device name, which start-up opens on IOCB 0.
;; See: <COLD_START>
EDITOR_NAME:
    .byte "E:", EOL

;; Starts again after SYSTEM RESET, WARMSV's target: the power-up start without clearing all of RAM.
;;
;; When the last power-up start did not finish (COLDST is still set), this is a power-up start. Otherwise it sets
;; WARMST and joins <COLD_START>, which clears only the OS's RAM, calls the booted programs' initialization again
;; and restarts the cartridge, the booted program or the memo pad.
;; See: <COLD_START>, <WARMST>, <COLDST>
WARM_START:
    sei
    lda COLDST
    bne COLD_START                  ; the start-up never finished: start again from the top
    lda #$FF                        ; WARMST = $FF, a SYSTEM RESET
    bne COLD_START_FLAG             ; always

;; Starts the machine at power-up, COLDSV's target: tests and clears RAM, sets up the hardware and the OS, starts
;; the cartridges and the handlers, boots the cassette and the disk, and runs a cartridge, the booted program or the
;; memo pad.
;;
;; In order:
;; - Starts a diagnostic cartridge (<TEST_MEMORY>), finds the top of RAM in TRAMSZ, and zeroes the hardware
;;   registers.
;; - Power-up clears RAM from $0008 to the top, points DOSVEC at the memo pad and sets COLDST; SYSTEM RESET clears
;;   only $0010-$007F and pages two and three, keeping the boot flags and vectors below POKMSK.
;; - Sets the margins, the interrupt vectors (from <DEFAULT_INTERRUPT_VECTORS>) and the OS's variables, starts the
;;   handlers, CIO, SIO and the interrupts (<INIT_OS>), enables IRQs and copies <DEFAULT_HANDLERS> to HATABS.
;; - Starts each cartridge there is, the right one (B) first: TSTDAT and TRAMSZ then say whether each is there.
;; - Opens the screen editor on IOCB 0, starting again if that fails, and waits a few frames for the screen.
;; - Boots the cassette if START was held (<CASSETTE_BOOT>), then the disk when there is no cartridge or a cartridge
;;   asks for it (<DISK_BOOT>). After SYSTEM RESET these only call the booted programs' initialization.
;; - Clears COLDST, then runs the left cartridge, or the right one, if its flags say to run, and otherwise jumps
;;   through DOSVEC.
;;
;; A right cartridge without its run bit (and no left one that runs) sends this back to the disk boot, again and
;; again, without end.
;;
;; Entry:
;;   COLD_START_FLAG = <WARM_START> joins here, with A = $FF for WARMST
;; See: <WARM_START>, <TEST_MEMORY>, <INIT_OS>, <CASSETTE_BOOT>, <DISK_BOOT>, <MEMO_PAD>
COLD_START:
    sei
    lda #$00                        ; WARMST = 0, a power-up start
COLD_START_FLAG:
    sta WARMST
    cld
    ldx #$FF
    txs
    jsr TEST_MEMORY
    jsr CLEAR_HARDWARE
    lda WARMST
    bne COLD_START_WARM_CLEAR

; Power-up: clear RAM from $0008 to the top that the memory test found.
    lda #$00
    ldy #WARMST                     ; from $0008: RAMLO, TRAMSZ and TSTDAT below it are in use
    sta RAMLO
    sta RAMLO+1
COLD_START_CLEAR_RAM:
    sta (RAMLO),y
    iny
    cpy #$00
    bne COLD_START_CLEAR_RAM
    inc RAMLO+1
    ldx RAMLO+1
    cpx TRAMSZ
    bne COLD_START_CLEAR_RAM
    lda BLKBDV+1                    ; DOSVEC = the memo pad, BLKBDV's JMP's target
    sta DOSVEC
    lda BLKBDV+2
    sta DOSVEC+1
    lda #$FF
    sta COLDST                      ; set until the start-up finishes
    bne COLD_START_SET_UP           ; always

; SYSTEM RESET: clear pages two and three, then $0010-$007F.
COLD_START_WARM_CLEAR:
    ldx #$00
    txa
COLD_START_WARM_CLEAR_PAGES:
    sta VDSLST,x
    sta DDEVIC,x
    dex
    bne COLD_START_WARM_CLEAR_PAGES
    ldx #POKMSK                     ; keeps CASINI, BOOTQ, DOSVEC, DOSINI and APPMHI below it
COLD_START_WARM_CLEAR_ZERO_PAGE:
    sta LINZBS,x
    inx
    bpl COLD_START_WARM_CLEAR_ZERO_PAGE

COLD_START_SET_UP:
    lda #RESET_LEFT_MARGIN
    sta LMARGN
    lda #RESET_RIGHT_MARGIN
    sta RMARGN
    ldx #VVBLKD + 1 - VDSLST        ; the interrupt vectors, VDSLST to VVBLKD
COLD_START_VECTORS:
    lda DEFAULT_INTERRUPT_VECTORS,x
    sta VDSLST,x
    dex
    bpl COLD_START_VECTORS
    jsr INIT_OS
    cli
    ldx #MEMO_PAD_MESSAGE - DEFAULT_HANDLERS - 1
COLD_START_HANDLERS:
    lda DEFAULT_HANDLERS,x
    sta HATABS,x
    dex
    bpl COLD_START_HANDLERS

; Start the cartridges. From here TSTDAT is 1 when the right cartridge is there and TRAMSZ 1 when the left is.
    ldx #$00
    stx TSTDAT
    stx TRAMSZ
    ldx RAMSIZ
    cpx #RIGHT_SLOT_RAM
    bcs COLD_START_LEFT_CART
    lda CARTB
    bne COLD_START_LEFT_CART
    inc TSTDAT
    jsr INIT_RIGHT_CART
COLD_START_LEFT_CART:
    ldx RAMSIZ
    cpx #LEFT_SLOT_RAM
    bcs COLD_START_OPEN_EDITOR
    ldx CART
    bne COLD_START_OPEN_EDITOR
    inc TRAMSZ
    jsr INIT_LEFT_CART

COLD_START_OPEN_EDITOR:
    lda #COPN
    ldx #$00                        ; IOCB 0
    sta ICCOM,x
    lda #<EDITOR_NAME
    sta ICBAL,x
    lda #>EDITOR_NAME
    sta ICBAH,x
    lda #OREAD | OWRIT
    sta ICAX1,x
    jsr CIOV
    bpl COLD_START_DELAY
    jmp COLD_START                  ; the editor would not open: start again
COLD_START_DELAY:
    inx                             ; Y = 1, the status: 127 times 256 loops, a few frames, for a vertical blank
    bne COLD_START_DELAY
    iny
    bpl COLD_START_DELAY
    jsr CASSETTE_BOOT
    lda TRAMSZ
    ora TSTDAT
    beq COLD_START_DISK_BOOT        ; no cartridge: boot the disk
    lda TRAMSZ
    beq COLD_START_RIGHT_FLAGS
    lda CARTFG
COLD_START_RIGHT_FLAGS:
    ldx TSTDAT
    beq COLD_START_BOOT_FLAG
    ora CARTFGB
COLD_START_BOOT_FLAG:
    and #CART_BOOT_DISK
    beq COLD_START_FINISHED
COLD_START_DISK_BOOT:
    jsr DISK_BOOT
COLD_START_FINISHED:
    lda #$00
    sta COLDST                      ; the start-up finished
    lda TRAMSZ
    beq COLD_START_RIGHT_RUN
    lda CARTFG
    and #CART_RUN
    beq COLD_START_RIGHT_RUN
    jmp (CARTCS)
COLD_START_RIGHT_RUN:
    lda TSTDAT
    beq COLD_START_DOS
    lda CARTFGB
    and #CART_RUN
    beq COLD_START_DISK_BOOT        ; a right cartridge that doesn't run: back to the disk boot, without end
    jmp (CARTCSB)
COLD_START_DOS:
    jmp (DOSVEC)

;; The memo pad, BLKBDV's target and DOSVEC's at power-up: clears the screen, shows its title, and reads lines from
;; the screen editor for ever, so that what is typed can be edited on the screen and goes nowhere.
;; See: <BLKBDV>, <DOSVEC>, <CALL_EDITOR_GET>
MEMO_PAD:
    ldx #<MEMO_PAD_MESSAGE
    ldy #>MEMO_PAD_MESSAGE
    jsr SHOW_MESSAGE
MEMO_PAD_LOOP:
    jsr CALL_EDITOR_GET
    jmp MEMO_PAD_LOOP

;; Gets a byte from the screen editor, through the GET BYTE vector in its table of vectors.
;; Out: A = the byte, Y = the status
;; See: <EDITRV>
CALL_EDITOR_GET:
    lda EDITRV+5                    ; the vector, less 1, is pushed for RTS
    pha
    lda EDITRV+4
    pha
    rts

;; Initializes the left cartridge (A) through CARTAD.
;; See: <CARTAD>
INIT_LEFT_CART:
    jmp (CARTAD)

;; Initializes the right cartridge (B) through CARTADB.
;; See: <CARTADB>
INIT_RIGHT_CART:
    jmp (CARTADB)

;; Starts a diagnostic cartridge, if the left slot holds one, and otherwise finds the top of RAM.
;;
;; A diagnostic cartridge has a zero at CART that a write doesn't change (so it is ROM) and bit 7 set in CARTFG; it
;; starts through CARTAD and never returns. The memory test then complements the first byte of each 4K block from
;; $1000 up, restoring it, until one doesn't change.
;;
;; Rev. A decrements CART even when it is nonzero, so with RAM in the left slot each SYSTEM RESET takes 1 from that
;; byte of RAM; rev. B leaves it alone. Rev. A also keeps the byte under test in TSTDAT and its complement in RAMLO,
;; where rev. B compares with the byte in memory and complements it back.
;; Out: TRAMSZ = the page where RAM ends, a multiple of $10
;; Uses: A, Y, RAMLO, RAMLO+1, TSTDAT
;; Keeps: X
;; See: <CART>, <CARTFG>, <RAMSIZ>
TEST_MEMORY:
    lda CART
.if VERSION = VERSION_B
    bne TEST_MEMORY_RAM             ; no cartridge
.else
    bne TEST_MEMORY_RESTORE         ; no cartridge, but rev. A still decrements CART
.endif
    inc CART
    lda CART
    bne TEST_MEMORY_RESTORE         ; RAM: put it back
    lda CARTFG
.if VERSION = VERSION_B
    bpl TEST_MEMORY_RESTORE         ; not a diagnostic cartridge
.else
    and #CART_DIAGNOSTIC
    beq TEST_MEMORY_RESTORE         ; not a diagnostic cartridge
.endif
    jmp (CARTAD)
TEST_MEMORY_RESTORE:
    dec CART
.if VERSION = VERSION_B
TEST_MEMORY_RAM:
    ldy #$00
    sty RAMLO+1                     ; the pointer at RAMLO+1 is 0 and TRAMSZ: the block's first byte
    lda #MEMORY_TEST_STEP
    sta TRAMSZ
TEST_MEMORY_LOOP:
    lda (RAMLO+1),y
    eor #$FF
    sta (RAMLO+1),y
    cmp (RAMLO+1),y
    bne TEST_MEMORY_DONE            ; not RAM
    eor #$FF
    sta (RAMLO+1),y
.else
    lda #$00
    sta RAMLO+1                     ; the pointer at RAMLO+1 is 0 and TRAMSZ: the block's first byte
    lda #MEMORY_TEST_STEP
    sta TRAMSZ
    ldy #$00
TEST_MEMORY_LOOP:
    lda (RAMLO+1),y
    sta TSTDAT                      ; the byte, to put back
    eor #$FF
    sta RAMLO                       ; its complement, to compare
    sta (RAMLO+1),y
    lda (RAMLO+1),y
    cmp RAMLO
    bne TEST_MEMORY_DONE            ; not RAM
    lda TSTDAT
    sta (RAMLO+1),y
.endif
    lda TRAMSZ
    clc
    adc #MEMORY_TEST_STEP
    sta TRAMSZ
    bne TEST_MEMORY_LOOP
TEST_MEMORY_DONE:
    rts

;; Writes zero to every address of GTIA's, POKEY's, the PIA's and ANTIC's pages, most of which the chips don't decode.
;; Out: A = 0, X = 0
;; Keeps: Y
CLEAR_HARDWARE:
    lda #$00
    tax
CLEAR_HARDWARE_LOOP:
    sta HPOSP0,x
    sta DMACTL,x
    sta AUDF1,x
    sta PORTA,x
    inx
    bne CLEAR_HARDWARE_LOOP
    rts

;; Sets the OS's variables, starts the handlers, CIO, SIO and the interrupts, and notes START held for a cassette
;; boot.
;;
;; BRKKEY becomes $FF (BREAK not pressed), BRKKY points at the BREAK key's handler (in rev. B, which added it),
;; RAMSIZ and MEMTOP at the top of RAM, and MEMLO at $0700. Each handler starts through the JMP at the end of its
;; table of vectors: the screen editor, the display, the keyboard, the printer and the cassette.
;; Out: CKEY = incremented when START is held
;; Uses: A, X, Y
;; See: <COLD_START>, <CIOINV>, <SIOINV>, <INTINV>
INIT_OS:
    dec BRKKEY                      ; 0 after the clearing, so $FF
.if VERSION = VERSION_B
    lda #<BREAK_KEY_HANDLER
    sta BRKKY
    lda #>BREAK_KEY_HANDLER
    sta BRKKY+1
.endif
    lda TRAMSZ
    sta RAMSIZ
    sta MEMTOP+1
    lda #$00
    sta MEMTOP
    lda #<RESET_MEMLO
    sta MEMLO
    lda #>RESET_MEMLO
    sta MEMLO+1
    jsr EDITRV+12                   ; each handler's initialization, the JMP at the end of its vectors
    jsr SCRENV+12
    jsr KEYBDV+12
    jsr PRINTV+12
    jsr CASETV+12
    jsr CIOINV
    jsr SIOINV
    jsr INTINV
    lda CONSOL
    and #CONSOL_START
    bne INIT_OS_DONE
    inc CKEY                        ; START held: boot the cassette
INIT_OS_DONE:
    rts

;; Boots the disk at power-up, or calls the disk-booted program's initialization after SYSTEM RESET.
;;
;; When drive 1 answers a status command, the boot reads sector 1 into $0400 and goes on in <BOOT_LOAD>. A read or
;; initialization error prints "BOOT ERROR" and starts the boot again from sector 1, for as long as it fails. After
;; SYSTEM RESET, it calls DOSINI if a disk boot succeeded.
;; Uses: A, X, Y
;; See: <BOOT_LOAD>, <BOOTQ>, <DOSINI>
DISK_BOOT:
    lda WARMST
    beq DISK_BOOT_COLD
    lda BOOTQ
    and #BOOTQ_DISK
    beq DISK_BOOT_DONE
    jsr CALL_DOSINI
DISK_BOOT_DONE:
    rts
DISK_BOOT_COLD:
    lda #BOOT_UNIT
    sta DUNIT
    lda #DISK_STATUS
    sta DCOMND
    jsr DSKINV
    bpl DISK_BOOT_START
    rts                             ; no drive
DISK_BOOT_START:
    lda #>BOOT_FIRST_SECTOR
    sta DAUX2
    lda #<BOOT_FIRST_SECTOR
    sta DAUX1
    lda #<BOOT_BUFFER
    sta DBUFLO
    lda #>BOOT_BUFFER
    sta DBUFHI

;; Loads a boot from the disk or the cassette, block by block, and starts it.
;;
;; The first block's header gives the boot's flags (DFLAGS), its number of blocks (DBSECT), where it loads (BOOTAD)
;; and its initialization (DOSINI). Each 128-byte block is copied from $0400 to its place; a cassette boot then reads
;; the end of the file. The boot's code at BOOTAD+6 is called, and returns carry set on failure; then DOSINI is
;; called, and BOOTQ gets bit 0.
;;
;; On a disk, a failed read is tried again and a failed initialization restarts the boot. On the cassette, a
;; failure prints "BOOT ERROR" and returns (twice, when a block after the first fails).
;; Out: BOOTQ = incremented on success
;; Uses: A, X, Y, RAMLO
;; See: <DISK_BOOT>, <CASSETTE_BOOT>, <DFLAGS>, <DBSECT>, <BOOTAD>, <DOSINI>
BOOT_LOAD:
    jsr READ_BOOT_BLOCK
    bpl BOOT_LOAD_HEADER
BOOT_LOAD_FAILED:
    jsr SHOW_BOOT_ERROR
    lda CASSBT
    beq DISK_BOOT_START             ; a disk: start again
    rts
BOOT_LOAD_HEADER:
    ldx #BOOT_HEADER_SIZE - 1
BOOT_LOAD_HEADER_LOOP:
    lda BOOT_BUFFER,x
    sta DFLAGS,x
    dex
    bpl BOOT_LOAD_HEADER_LOOP
    lda BOOTAD
    sta RAMLO
    lda BOOTAD+1
    sta RAMLO+1
    lda BOOT_DOSINI
    sta DOSINI
    lda BOOT_DOSINI+1
    sta DOSINI+1
BOOT_LOAD_BLOCK:
    ldy #BOOT_BLOCK_SIZE - 1
BOOT_LOAD_COPY:
    lda BOOT_BUFFER,y
    sta (RAMLO),y
    dey
    bpl BOOT_LOAD_COPY
    clc
    lda RAMLO
    adc #BOOT_BLOCK_SIZE
    sta RAMLO
    lda RAMLO+1
    adc #$00
    sta RAMLO+1
    dec DBSECT
    beq BOOT_LOAD_LAST
    inc DAUX1                       ; the next sector
BOOT_LOAD_NEXT:
    jsr READ_BOOT_BLOCK
    bpl BOOT_LOAD_BLOCK
    jsr SHOW_BOOT_ERROR
    lda CASSBT
    bne BOOT_LOAD_FAILED            ; the cassette: prints the error again and gives up
    beq BOOT_LOAD_NEXT              ; a disk: read the sector again
BOOT_LOAD_LAST:
    lda CASSBT
    beq BOOT_LOAD_INIT
    jsr READ_BOOT_BLOCK             ; the cassette's end of file, unchecked
BOOT_LOAD_INIT:
    jsr CALL_BOOT_INIT
    bcs BOOT_LOAD_FAILED
    jsr CALL_DOSINI
    inc BOOTQ                       ; bit 0, from 0 at power-up
    rts

;; Calls the boot's own code, 6 bytes into what it loaded, which returns carry set when the boot failed.
;; Out: carry = set when the boot failed
;; Uses: RAMLO
;; See: <BOOTAD>
CALL_BOOT_INIT:
    clc
    lda BOOTAD
    adc #BOOT_INIT_OFFSET
    sta RAMLO
    lda BOOTAD+1
    adc #$00
    sta RAMLO+1
    jmp (RAMLO)

;; Calls the disk-booted program's initialization through DOSINI.
;; See: <DOSINI>
CALL_DOSINI:
    jmp (DOSINI)

;; Prints "BOOT ERROR" on the screen editor.
;; Out: Y = the status
;; Uses: A, X
;; See: <SHOW_MESSAGE>
SHOW_BOOT_ERROR:
    ldx #<BOOT_ERROR_MESSAGE
    ldy #>BOOT_ERROR_MESSAGE

;; Prints a message, ending with an end of line, through IOCB 0, the screen editor.
;; In: X = the message's address, low byte, Y = its high byte
;; Out: Y = the status, negative = an error
;; Uses: A, X
;; See: <CIOV>
SHOW_MESSAGE:
    txa
    ldx #$00                        ; IOCB 0
    sta ICBAL,x
    tya
    sta ICBAH,x
    lda #CPTXTR
    sta ICCOM,x
    lda #RESET_MESSAGE_LENGTH
    sta ICBLL,x
    jsr CIOV
    rts

;; Reads a boot's next block into $0400: a cassette record when CASSBT is set, and otherwise sector DAUX1 from
;; drive 1.
;; Out: Y = the status, negative = an error
;; Uses: A, X
;; See: <RBLOKV>, <DSKINV>
READ_BOOT_BLOCK:
    lda CASSBT
    beq READ_BOOT_BLOCK_DISK
    jmp RBLOKV
READ_BOOT_BLOCK_DISK:
    lda #DISK_READ
    sta DCOMND
    lda #BOOT_UNIT
    sta DUNIT
    jsr DSKINV
    rts

;; Boots the cassette at power-up when START was held, or calls the cassette-booted program's initialization after
;; SYSTEM RESET.
;;
;; The boot opens the cassette for reading with short gaps between records and loads through <BOOT_LOAD>. On
;; success BOOTQ's bit 0 moves to bit 1, and the booted program's DOSINI becomes CASINI.
;; Uses: A, X, Y
;; See: <BOOT_LOAD>, <CKEY>, <CASINI>, <BOOTQ>
CASSETTE_BOOT:
    lda WARMST
    beq CASSETTE_BOOT_COLD
    lda BOOTQ
    and #BOOTQ_CASSETTE
    beq CASSETTE_BOOT_DONE
    jsr CALL_CASINI
CASSETTE_BOOT_DONE:
    rts
CASSETTE_BOOT_COLD:
    lda CKEY
    beq CASSETTE_BOOT_EXIT
    lda #BOOT_SHORT_GAPS
    sta FTYPE
    inc CASSBT
    jsr CSOPIV
    jsr BOOT_LOAD
    lda #$00
    sta CASSBT
    sta CKEY
    asl BOOTQ                       ; BOOTQ_DISK becomes BOOTQ_CASSETTE
    lda DOSINI
    sta CASINI
    lda DOSINI+1
    sta CASINI+1
CASSETTE_BOOT_EXIT:
    rts

;; Calls the cassette-booted program's initialization through CASINI.
;; See: <CASINI>
CALL_CASINI:
    jmp (CASINI)
