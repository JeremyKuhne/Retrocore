;; SOS .RAM DRIVER: HARMONY SYSTEMS' RAM DISK FOR TITAN'S III+IIE CARD
;;
;; Harmony Systems' RAM disk driver for Titan's III+IIe card, as Titan's "III Plus IIe Startup Disk" carries it in
;; RAMDISK.DRIVER. It makes a block device, .RAM, of 280 blocks (140K), as many as a Disk III. The card, in a slot
;; (slot 3 here), gives an Apple III an Apple IIe's memory switches and 128K of IIe memory, which the driver sees 16K
;; at a time at $D000-$FFFF through extension byte $8F.
;;
;; The blocks live in two places (<MAPBLOCK>):
;;
;; - Blocks 0-23 are 12K inside the driver itself, <RAM_STORE>. SOS loads them with the driver, so each boot starts
;;   with the empty volume the driver file holds there: /SOS.DRIVE, a four-block volume directory in blocks 2-5 and
;;   its bitmap in block 6.
;; - Blocks 24-279 are the card's 128K: eight 16K banks, picked by the IIe-style switches at $C002-$C009, each laid
;;   out as a IIe's language card is (a 4K bank 1 and a 4K bank 2 at $D000, and 8K at $E000), two pages a block.
;;
;; Each request runs at 1 MHz with interrupts off, after the driver reads a byte of the card's $Cn page; it leaves
;; the language card reading ROM ($C082) and the environment register as the caller had it (<RAM_MAIN>). An error
;; goes straight to <SYSERR>, leaving both as the request had them.
;;
;; Requests (see <REQSTSW>):
;;
;; - D_READ (<RAM_READ>) and D_WRITE (<RAM_WRITE>): whole blocks, the byte count a multiple of 512. The buffer
;;   pointer moves on only one page a block, so in a request of more than one block each later block lands a page
;;   early in the buffer.
;; - D_STATUS (<RAM_STATUS>): code 0 answers 0, and code $FE, which formatters ask, answers $FFFF.
;; - D_CONTROL (<RAM_CONTROL>): codes 0 (reset) and $FE (format) are accepted and do nothing.
;; - D_INIT (<RAM_INIT>): claims the slot's interrupt resource and checks that the slot's expansion ROM can be
;;   selected.
;; - D_REPEAT (<RAM_REPEAT>): repeats the last read or write.
;; - D_OPEN, D_CLOSE, 4 and 5 are refused as bad requests.
;;
;; One DIB, .RAM (<RAM_DIB>): device type $D0, subtype 0, slot 3, 280 blocks, manufacturer 0, release $100D (1.00,
;; qualifier $D) and no configuration block. Harmony's copyright follows it. There is no comment record: the code
;; file's segment starts with the DIB.
;;
;; D A DataSystems' "Enhanced RamDisk" (Drivers/Ram/Ram.asm) drives the same card and shares most of this code, line
;; for line: the entry, dispatch, status, control, init and repeat requests, the buffer handling and the card's bank
;; mapping. Where this driver keeps blocks 0-23 in itself and the rest on the card, D A DataSystems' adds 24 to every
;; block (its BLOCK_BIAS) and keeps all 256 on the card, with its limit still 24 + 256. It also drops <RAM_STORE>;
;; moves the buffer on two pages a block, through its normalizing routine after each page; normalizes extended
;; addresses at page $82 and above where this driver's <BUF_NORMALIZE> handles only page $FF (whose code it keeps,
;; unreached); sends errors through a routine that first puts the language card and the speed back; and adds an
;; AutoFormat routine and a comment record.
;;
;; The names are ours; the standard parts follow the SOS Device Driver Writer's Guide
;; (https://archive.org/details/Apple_III_SOS_Device_Driver_Writers_Guide), and the rest follow Ram.asm where the
;; code is the same.
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to the driver in Titan's RAMDISK.DRIVER.

.cpu Mos6502

;; Performs an N-way branch on a switch index, through a table of addresses less one.
;;
;; It loads the index (when given), checks it against the bounds (when given; carry set and falling through when
;; it is larger), then pushes the table entry and returns to it. With `*` as the fourth parameter it pushes the
;; address but falls through instead.
;; Parameters: index = the index's location, or blank for A, bounds = the largest index, or blank for no check,
;;   table = the table of addresses less one, low byte first, stay = `*` to fall through
.macro SWITCH index, bounds, table, stay
    .local M010
    .ifnblank index
    lda index
    .endif
    .ifnblank bounds
    cmp #<(bounds+$01)
    bcs M010
    .endif
    asl a
    tay
    lda a:table+$01,y
    pha
    lda a:table,y
    pha
    .if .not .xmatch({stay}, {*})
    rts
    .endif
M010:
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; SOS: the kernel's calls, error codes and the request block.
; ---------------------------------------------------------------------------------------------------------------------

;; Allocates system internal resources: A = the table's length, X/Y = its address; carry = set on failure.
ALLOCSIR = $1913

;; Selects a slot's $C800 expansion ROM, A = the slot, or deselects it with A = 0; carry = set on failure.
SELC800 = $1922

;; Returns an error from the SOS call: A = the error code. It doesn't return.
SYSERR = $1928

;; SOS's extend page: the extension byte of the pointer at zero-page address n is at SXPAGE+n+1.
SXPAGE = $1400

XREQCODE = $20                          ;; the request code is invalid
XCTLCODE = $21                          ;; the control or status code is invalid
XNOTOPEN = $23                          ;; the device is not open
XNORESRC = $25                          ;; the slot's interrupt resource is taken
XBADOP = $26                            ;; the operation is invalid: a repeat with no read or write to repeat
XNODRIVE = $28                          ;; no slot is set, or the slot's expansion ROM can't be selected
XBYTECNT = $2C                          ;; the byte count is not a multiple of 512
XBLKNUM = $2D                           ;; the block number is past the last block

D_READ = 0                              ;; request: read
D_WRITE = 1                             ;; request: write
D_STATUS = 2                            ;; request: status
D_CONTROL = 3                           ;; request: control
D_OPEN = 6                              ;; request: open
D_CLOSE = 7                             ;; request: close
D_INIT = 8                              ;; request: initialize, at boot
D_REPEAT = 9                            ;; request: repeat the last read or write

;; The request block SOS passes to a driver, in zero page.
SOSINT = $C0

REQCODE = SOSINT+$00                    ;; the request code
UNITNUM = SOSINT+$01                    ;; the unit
BUFFER = SOSINT+$02                     ;; read/write: the buffer's address, with its extension byte at SXPAGE+BUFFER+1
REQCNT = SOSINT+$04                     ;; read/write: the byte count
BLOCKNUM = SOSINT+$06                   ;; read/write: the first block
BYTESRD = SOSINT+$08                    ;; read: where to put the count of bytes read
CTLSTAT = SOSINT+$02                    ;; status/control: the code
CSLIST = SOSINT+$03                     ;; status/control: the list's address

; The driver's zero-page locations, after the request block.
CARDPTR = $CA                           ;; a pointer into the card's $Cn page
BUFPTR = $D0                            ;; the caller's buffer, with its extension byte at SXPAGE+BUFPTR+1
BLOCK = $D2                             ;; the block in progress (two bytes)
BLOCKS = $D4                            ;; the blocks left in the request
RAMPTR = $D6                            ;; the block's place in the RAM disk, with its extension byte

; ---------------------------------------------------------------------------------------------------------------------
; Hardware.
; ---------------------------------------------------------------------------------------------------------------------

E_REG = $FFDF                           ;; the environment register; bit 7 = 1 MHz

E_1MHZ = $80                            ;; the environment register's 1 MHz bit

;; The extension byte that reaches the RAM at $C000-$FFFF in the system bank, where the card's banks appear.
RAM_XBYTE = $8F

LCROM = $C082                           ;; language card: read ROM, no writes
LCBANK2 = $C083                         ;; language card: read and write RAM, bank 2 at $D000 (read twice)
LCBANK1_OFFSET = $08                    ;; added to <LCBANK2>: bank 1 at $D000 instead

RAMRDOFF = $C002                        ;; IIe switch: reads from main memory
RAMRDON = $C003                         ;; IIe switch: reads from auxiliary memory
RAMWRTOFF = $C004                       ;; IIe switch: writes to main memory
RAMWRTON = $C005                        ;; IIe switch: writes to auxiliary memory
SETSLOTCXROM = $C006                    ;; IIe switch: slot ROM at $C100-$CFFF
SETINTCXROM = $C007                     ;; IIe switch: internal ROM at $C100-$CFFF
SETSTDZP = $C008                        ;; IIe switch: main zero page, stack and language card
SETALTZP = $C009                        ;; IIe switch: auxiliary zero page, stack and language card

; ---------------------------------------------------------------------------------------------------------------------
; The RAM disk.
; ---------------------------------------------------------------------------------------------------------------------

;; The blocks kept inside the driver, in <RAM_STORE>: blocks 0-23.
STORE_BLOCKS = 24

;; The blocks kept on the card: 128K.
CARD_BLOCKS = 256

;; The RAM disk's size in 512-byte blocks.
RAM_BLOCKS = STORE_BLOCKS+CARD_BLOCKS

;; The page at which a bank's language-card window starts: $C0 put into the block's page within its bank.
WINDOW_PAGE = $C0

;; The page of bank 1 at $D000, which holds the first eight blocks of each 16K bank.
BANK1_PAGE = $D0

; ---------------------------------------------------------------------------------------------------------------------
; The device information block.
; ---------------------------------------------------------------------------------------------------------------------

;; .RAM's device information block: the only device this driver has.
RAM_DIB:
    .word $0000                         ; no next DIB
    .word RAM_MAIN                      ; the entry point
    .byte 4                             ; the name's length
    .byte ".RAM"
    .res 11, $00
    .byte $80                           ; active
;; The slot of the III+IIe card; $FF (bit 7 set) for none.
DIB_SLOT:
    .byte $03
    .byte $00                           ; the unit
    .byte $D0                           ; the device type: a block device
    .byte $00                           ; the subtype
    .byte $00
    .word RAM_BLOCKS                    ; the blocks
    .word $0000                         ; the manufacturer
    .word $100D                         ; the release: 1.00, qualifier $D
    .word $0000                         ; no configuration block

;; Harmony Systems' copyright.
COPYRIGHT:
    .byte "(C) 1984, 1985 BY HARMONY SYSTEMS INC."

; ---------------------------------------------------------------------------------------------------------------------
; The driver's data.
; ---------------------------------------------------------------------------------------------------------------------

;; The last request's code, for <RAM_REPEAT>.
LASTREQ:
    .byte $00
    .res 3, $00                         ; unused

;; The address of <SIRTABLE>, for <ALLOCSIR>.
SIRADDR:
    .word SIRTABLE

;; The system internal resource the driver claims: the slot's, $10 plus the slot (added by <RAM_INIT>), with no
;; interrupt handler. The entry is the resource, the ID byte, and the handler's address and bank.
SIRTABLE:
    .byte $10, $00
    .word $0000
    .byte $00
SIRCOUNT = * - SIRTABLE                 ;; the table's length in bytes

; ---------------------------------------------------------------------------------------------------------------------
; The requests.
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: does the request and returns to SOS.
;;
;; It slows the machine to 1 MHz, turns interrupts off and reads a byte of the card's $Cn page, then does the request
;; (<DISPATCH>). Afterwards it records the request for <RAM_REPEAT>, sets the language card to read ROM, and puts the
;; environment register and the interrupt flag back as the caller had them.
;; In: REQCODE = the request, its parameters at $C1-$C9
;; Out: carry = clear
;; Uses: A, X, Y
RAM_MAIN:
    php
    lda E_REG
    pha
    ora #E_1MHZ
    sta E_REG
    sei
    lda a:DIB_SLOT
    ora #$C0                            ; the card's page, $Cn
    sta CARDPTR+1
    ldy #$00
    sty SXPAGE+CARDPTR+1
    lda (CARDPTR),y
    jsr DISPATCH
    lda REQCODE
    sta a:LASTREQ
    sta LCROM
    pla
    pha
    and #<~E_1MHZ
    sta E_REG                           ; 2 MHz first, then the caller's setting
    pla
    sta E_REG
    plp
    clc
    rts

;; Repeats the last request, which must have been a read or a write.
;; In: LASTREQ = the last request
;; Errors: XBADOP = the last request was neither
;; Uses: A, X, Y
RAM_REPEAT:
    lda a:LASTREQ
    beq RAM_REPEAT_1
    cmp #D_WRITE
    beq RAM_REPEAT_1
    lda #XBADOP
    jsr SYSERR
RAM_REPEAT_1:
    sta REQCODE

;; Sets up the request's pointers and goes to its routine.
;;
;; The caller's buffer goes in <BUFPTR> and the first block in <BLOCK>.
;; In: REQCODE = the request, BUFFER = the buffer, BLOCKNUM = the first block
;; Errors: XREQCODE = an unknown request
;; Uses: A, X, Y
;; See: <REQSTSW>
DISPATCH:
    lda BUFFER
    sta BUFPTR
    lda BUFFER+1
    sta BUFPTR+1
    lda SXPAGE+BUFFER+1
    sta SXPAGE+BUFPTR+1
    lda BLOCKNUM
    sta BLOCK
    lda BLOCKNUM+1
    sta BLOCK+1
    SWITCH REQCODE, D_REPEAT, REQSTSW

;; Fails the request: its code is not one the driver does.
BADREQ:
    lda #XREQCODE
    jsr SYSERR

    ; Nothing comes here: a not-open error.
    lda #XNOTOPEN
    jsr SYSERR

;; The request routines' addresses less one, by request code.
REQSTSW:
    .word RAM_READ-1                    ; D_READ
    .word RAM_WRITE-1                   ; D_WRITE
    .word RAM_STATUS-1                  ; D_STATUS
    .word RAM_CONTROL-1                 ; D_CONTROL
    .word BADREQ-1                      ; 4
    .word BADREQ-1                      ; 5
    .word BADREQ-1                      ; D_OPEN
    .word BADREQ-1                      ; D_CLOSE
    .word RAM_INIT-1                    ; D_INIT
    .word RAM_REPEAT-1                  ; D_REPEAT

;; Initializes the driver at boot: claims the slot's interrupt resource, and checks that the slot's expansion ROM can
;; be selected.
;; In: DIB_SLOT = the slot
;; Out: A = 0
;; Errors: XNODRIVE = no slot, or its ROM can't be selected, XNORESRC = the slot's resource is taken
;; Uses: A, X, Y
RAM_INIT:
    lda a:DIB_SLOT
    bmi RAM_INIT_1
    clc
    adc a:SIRTABLE
    sta a:SIRTABLE                      ; the slot's resource, $10 plus the slot
    lda #SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+1
    jsr ALLOCSIR
    bcs RAM_INIT_2
    lda a:DIB_SLOT
    jsr SELC800
    bcs RAM_INIT_1
    lda #$00
    jsr SELC800                         ; deselected again
    lda #$00
    rts
RAM_INIT_1:
    lda #XNODRIVE
    jsr SYSERR
RAM_INIT_2:
    lda #XNORESRC
    jsr SYSERR

;; Answers a status request: code 0 answers a status byte of 0, and code $FE answers $FFFF, no preference for where
;; a volume's bitmap starts.
;; In: CTLSTAT = the status code, CSLIST = where to put the answer
;; Errors: XCTLCODE = another code
;; Uses: A, Y
RAM_STATUS:
    lda CTLSTAT
    beq RAM_STATUS_1
    cmp #$FE
    beq RAM_STATUS_2
    lda #XCTLCODE
    jsr SYSERR
RAM_STATUS_1:
    lda #$00
    ldy #$00
    sta (CSLIST),y
    rts
RAM_STATUS_2:
    ldy #$00
    lda #$FF
    sta (CSLIST),y
    iny
    sta (CSLIST),y
    rts

;; Answers a control request: codes 0 (reset) and $FE (format) do nothing.
;; In: CTLSTAT = the control code
;; Errors: XCTLCODE = another code
;; Uses: A
RAM_CONTROL:
    lda CTLSTAT
    beq RAM_CONTROL_1
    cmp #$FE
    beq RAM_CONTROL_1
    lda #XCTLCODE
    jsr SYSERR
RAM_CONTROL_1:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Moving through the caller's buffer and the RAM disk.
; ---------------------------------------------------------------------------------------------------------------------

;; Moves <BUFPTR> on a page, then keeps it where 256 bytes can't run past the end of its bank pair (<BUF_NORMALIZE>).
;; Nothing calls it.
;; In: BUFPTR = the caller's buffer
;; Out: BUFPTR = a page on
;; Uses: A
BUF_NEXTPAGE:
    inc BUFPTR+1

;; Moves <BUFPTR> off the two pages of an extended address that sit at a bank pair's ends.
;;
;; Page $00 moves up to page $80 of the pair below; page $00 of pair $80 is bank 0's $2000, extension byte $8F.
;; Page $FF moves down to page $7F of the next pair. Other addresses stay as they are; the extension byte is not
;; checked.
;; In: BUFPTR = the caller's buffer
;; Out: BUFPTR = the same memory, adjusted
;; Uses: A
BUF_NORMALIZE:
    lda BUFPTR+1
    beq BUF_NORMALIZE_1
    cmp #$FF
    beq BUF_NORMALIZE_2
    rts
BUF_NORMALIZE_1:
    lda #$80
    sta BUFPTR+1
    dec SXPAGE+BUFPTR+1                 ; the bank pair below
    lda SXPAGE+BUFPTR+1
    cmp #$7F
    bne BUF_NORMALIZE_3
    lda #$20                            ; below pair $80: bank 0 at $2000
    sta BUFPTR+1
    lda #RAM_XBYTE
    sta SXPAGE+BUFPTR+1
    bne BUF_NORMALIZE_3
BUF_NORMALIZE_2:
    lsr BUFPTR+1                        ; page $7F
    inc SXPAGE+BUFPTR+1                 ; of the next bank pair
BUF_NORMALIZE_3:
    rts

;; Counts the blocks a read or write moves.
;; In: REQCNT = the byte count
;; Out: BLOCKS = the blocks, carry = set when the count is not a multiple of 512
;; Uses: A
BLOCKCOUNT:
    sec
    lda REQCNT
    bne BLOCKCOUNT_1
    lda REQCNT+1
    lsr a
    sta BLOCKS
BLOCKCOUNT_1:
    rts

;; Finds a block in the RAM disk and, for a block on the card, switches its bank in.
;;
;; Blocks 0-23 are in <RAM_STORE>, two pages each, reached with extension byte 0. The others, less 24, are on the
;; card: the bank is that number divided by 32, and the switches for it come from <BANK_SWITCHES>: bit 0 selects
;; <SETINTCXROM>, bit 1 <SETALTZP>, bit 2 <RAMRDON> and <RAMWRTON>, each otherwise left off. Within the bank, the first
;; eight blocks are in language-card bank 1 at $D000-$DFFF, and the other 24 in bank 2 at $D000 and at $E000-$FFFF.
;; In: BLOCK = the block
;; Out: carry = clear, RAMPTR = the block's address and extension byte, with its bank switched in;
;;   carry = set when the block is past the last
;; Uses: A, X, Y
MAPBLOCK:
    lda BLOCK+1
    bne MAPBLOCK_1
    lda BLOCK
    cmp #STORE_BLOCKS
    bcs MAPBLOCK_1
    asl a                               ; two pages a block
    adc STORE_ADDR+1
    sta RAMPTR+1
    lda STORE_ADDR
    sta RAMPTR
    lda #$00
    sta SXPAGE+RAMPTR+1                 ; the driver's own memory
    clc
    rts
MAPBLOCK_1:
    sec
    lda BLOCK
    sbc #<RAM_BLOCKS
    lda BLOCK+1
    sbc #>RAM_BLOCKS
    bcs MAPBLOCK_8
    lda BLOCK+1
    sta RAMPTR+1
    lda BLOCK
    sbc #STORE_BLOCKS-1                 ; carry clear: takes off the blocks in the driver
    bcs MAPBLOCK_2
    dec RAMPTR+1
MAPBLOCK_2:
    asl a
    rol RAMPTR+1
    pha                                 ; the block's first page
    asl a
    rol RAMPTR+1
    asl a
    rol RAMPTR+1
    ldx RAMPTR+1                        ; the bank, the block divided by 32
    ldy BANK_SWITCHES,x
    and #$C0                            ; which 4K of the bank
    beq MAPBLOCK_3
    pla
    ldx #$00                            ; bank 2
    beq MAPBLOCK_4
MAPBLOCK_3:
    ldx #LCBANK1_OFFSET                 ; the first 4K: bank 1
    pla
    ora #BANK1_PAGE
MAPBLOCK_4:
    ora #WINDOW_PAGE
    sta RAMPTR+1
    lda #$00
    sta RAMPTR
    lda #RAM_XBYTE
    sta SXPAGE+RAMPTR+1
    lda LCBANK2,x
    lda LCBANK2,x                       ; read twice: RAM read and written
    tya
    sta SETSLOTCXROM
    sta SETSTDZP
    sta RAMRDOFF
    sta RAMWRTOFF
    lsr a
    bcc MAPBLOCK_5
    sta SETINTCXROM
MAPBLOCK_5:
    lsr a
    bcc MAPBLOCK_6
    sta SETALTZP
MAPBLOCK_6:
    lsr a
    bcc MAPBLOCK_7
    sta RAMRDON
    sta RAMWRTON
MAPBLOCK_7:
    clc
MAPBLOCK_8:
    rts

;; The switches for each of the card's eight 16K banks, as <MAPBLOCK> reads them.
BANK_SWITCHES:
    .byte 0, 1, 2, 3, 4, 5, 6, 7

;; Copies a block from the RAM disk to the caller's buffer.
;; In: RAMPTR = the block, from <MAPBLOCK>, BUFPTR = the buffer
;; Out: BUFPTR = a page on, RAMPTR = a page on
;; Uses: A, Y
RAM_READ_BLOCK:
    ldy #$00
RAM_READ_BLOCK_1:
    lda (RAMPTR),y
    sta (BUFPTR),y
    iny
    bne RAM_READ_BLOCK_1
    inc RAMPTR+1
    inc BUFPTR+1
RAM_READ_BLOCK_2:
    lda (RAMPTR),y
    sta (BUFPTR),y
    iny
    bne RAM_READ_BLOCK_2
    rts

;; Copies a block from the caller's buffer to the RAM disk.
;; In: RAMPTR = the block, from <MAPBLOCK>, BUFPTR = the buffer
;; Out: BUFPTR = a page on, RAMPTR = a page on
;; Uses: A, Y
RAM_WRITE_BLOCK:
    ldy #$00
RAM_WRITE_BLOCK_1:
    lda (BUFPTR),y
    sta (RAMPTR),y
    iny
    bne RAM_WRITE_BLOCK_1
    inc RAMPTR+1
    inc BUFPTR+1
RAM_WRITE_BLOCK_2:
    lda (BUFPTR),y
    sta (RAMPTR),y
    iny
    bne RAM_WRITE_BLOCK_2
    rts

;; Reads blocks into the caller's buffer, counting the bytes read as it goes.
;;
;; The first block is checked even when the count is 0. Each block moves the buffer on one page, not two (see
;; <RAM_READ_BLOCK>).
;; In: BUFPTR = the buffer, BLOCK = the first block, REQCNT = the byte count, BYTESRD = where to count the bytes read
;; Errors: XBYTECNT = the count is not whole blocks, XBLKNUM = a block is past the last
;; Uses: A, X, Y
RAM_READ:
    jsr BLOCKCOUNT
    bcc RAM_READ_1
    lda #XBYTECNT
    jsr SYSERR
RAM_READ_1:
    ldy #$00
    tya
    sta (BYTESRD),y
    iny
    sta (BYTESRD),y
    jsr BUF_NORMALIZE
RAM_READ_2:
    jsr MAPBLOCK
    bcc RAM_READ_3
    lda #XBLKNUM
    jsr SYSERR
RAM_READ_3:
    lda BLOCKS
    bne RAM_READ_5
RAM_READ_4:
    rts
RAM_READ_5:
    jsr RAM_READ_BLOCK
    ldy #$01
    lda (BYTESRD),y
    adc #$02                            ; 512 more bytes read
    sta (BYTESRD),y
    inc BLOCK
    bne RAM_READ_6
    inc BLOCK+1
RAM_READ_6:
    dec BLOCKS
    beq RAM_READ_4
    bne RAM_READ_2

;; Writes blocks from the caller's buffer.
;;
;; The first block is checked even when the count is 0. Each block moves the buffer on one page, not two (see
;; <RAM_WRITE_BLOCK>).
;; In: BUFPTR = the buffer, BLOCK = the first block, REQCNT = the byte count
;; Errors: XBYTECNT = the count is not whole blocks, XBLKNUM = a block is past the last
;; Uses: A, X, Y
RAM_WRITE:
    jsr BLOCKCOUNT
    bcc RAM_WRITE_1
    lda #XBYTECNT
    jsr SYSERR
RAM_WRITE_1:
    jsr BUF_NORMALIZE
RAM_WRITE_2:
    jsr MAPBLOCK
    bcc RAM_WRITE_3
    lda #XBLKNUM
    jsr SYSERR
RAM_WRITE_3:
    lda BLOCKS
    bne RAM_WRITE_5
RAM_WRITE_4:
    rts
RAM_WRITE_5:
    jsr RAM_WRITE_BLOCK
    inc BLOCK
    bne RAM_WRITE_6
    inc BLOCK+1
RAM_WRITE_6:
    dec BLOCKS
    beq RAM_WRITE_4
    bne RAM_WRITE_2

; ---------------------------------------------------------------------------------------------------------------------
; The blocks kept in the driver.
; ---------------------------------------------------------------------------------------------------------------------

;; Blocks 0-23 of the RAM disk, 512 bytes each, as SOS loads them: an empty volume, /SOS.DRIVE.
RAM_STORE:
    .res 2*512, $00                     ; blocks 0 and 1, the boot blocks: empty
    ; Block 2: the volume directory's first block, with the volume header.
    .word 0, 3                          ; previous and next blocks
    .byte $F0 | 9                       ; a volume header, its name nine characters
    .byte "SOS.DRIVE      "
    .res 8, $00
    .word $E454                         ; the creation date, as the driver file has it
    .word $0000                         ; the creation time
    .byte $00                           ; the version
    .byte $00                           ; the oldest version that can read it
    .byte $C3                           ; access: destroy, rename, write and read
    .byte $27                           ; the entry length, 39
    .byte $0D                           ; the entries per block, 13
    .word 0                             ; no files
    .word 6                             ; the bitmap's first block
    .word RAM_BLOCKS                    ; the blocks on the volume
    .res 512-43, $00
    ; Blocks 3-5: the rest of the volume directory, empty.
    .word 2, 4                          ; previous and next blocks
    .res 512-4, $00
    .word 3, 5
    .res 512-4, $00
    .word 4, 0
    .res 512-4, $00
    ; Block 6: the volume bitmap: blocks 0-6 used, 7-279 free.
    .byte $01
    .res RAM_BLOCKS/8-1, $FF
    .res 512-RAM_BLOCKS/8, $00
    .res (STORE_BLOCKS-7)*512, $00      ; blocks 7-23: empty

;; The address of <RAM_STORE>, for <MAPBLOCK>.
STORE_ADDR:
    .word RAM_STORE
