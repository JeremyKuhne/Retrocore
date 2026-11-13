;; SOS BOOTSTRAP LOADER (BLOCK 0, $A000-$A1FF)
;;
;; Block 0 of an Apple III SOS disk. The boot ROM reads it to $A000 from the built-in drive and jumps to it. It
;; loads SOS.KERNEL and starts it, using the ROM's disk routine (<BLOCKIO>) and the call block the ROM left set up for
;; the built-in drive:
;;
;; - It disables interrupts, sets the environment to 2 MHz with I/O, video and the primary stack, clears the
;;   keyboard strobe, and puts an RTI at the NMI vector so that the RESET key does nothing while it runs.
;; - It switches in the highest bank of memory that answers at $2000 (<FINDBANK>).
;; - It reads block 1 to $A200 and then the volume directory, from block 2 along its chain of next-block pointers,
;;   to $A400 on (<READSOSDIR>).
;; - It searches the directory for a sapling file named SOS.KERNEL (<SRCHSOSKER>), reads the file's index block to
;;   $0C00 (<READIDXBLK>), and reads the file's first block to $1E00, which must start with the label "SOS KRNL"
;;   (<FLVRFY>).
;; - It reads the rest of the file's blocks, in the order the index block lists them, to $2000 on in the bank it
;;   switched in, so that the file lies at $1E00 up (<RDSOSKER>).
;; - It jumps to SOS's loader, SOSLDR, which follows the file's label, its header count and header, and the
;;   loader's own four-byte header (<JUMPSOSKER>).
;;
;; A disk error, a missing SOS.KERNEL or a file that is not a sapling or lacks the label puts a message in the
;; middle of the screen's twelfth line, sounds the bell, and stops (<WRERRMSG>).
;;
;; It builds three copies of the loader:
;;
;; - By default, Apple's "SOS BOOT 1.1", as the Business BASIC 1.23 disk holds it.
;; - With SYSTEM_DEMO = 1, the System Demo disk's copy of it, whose version text reads "7.0" and whose unused bytes
;;   at the end hold three nonzero leftovers; the code is the same.
;; - With ON_THREE = 1, On Three's revision, "SOS BOOT 2.2", as the SOS 1.3 System Utilities disk holds it; its text
;;   reads "by B.C. (c) 1985 by ON THREE." It keeps Apple's code and adds to it: before the bank search it looks
;;   for a bank $E, which only a machine with more than 256K has, and uses it when it keeps what was written to
;;   it. It writes its constants into the instructions where Apple's reads them from a table, finds SOS.KERNEL's
;;   name inside its not-found message, gives each error its message's position as a constant, and shares one
;;   invalid-kernel call between the two places that need it.
;;
;; Labels follow a 1988 listing of another version of Apple's loader, labeled SOS 1.3, "SOS Floppy Bootstrap
;; Loader", in the Apple III Service Reference Manual, where the code does the same job: <ENTRY>, <READSOSDIR>,
;; <RDSOSDIRLP>, <SRCHSOSKER>, <SRCHLP>, <READIDXBLK>, <RD1SOSKER>, <FLVRFY>, <FLVRFYLP>, <RDSOSKER>,
;; <RDSOSKERLP>, <JUMPSOSKER>, <READBLK>, <WRNTFNDERR>, <WRINVKERERR>, <WRDISKERR> and the data's <FLNMELEN>,
;; <FLNME>, <FLVERIFY>, <NTFNDERR>, <INVKERERR> and <DISKERR>, with that listing's <IDXBLK1>, <IDXBLK2>, <LOADADR>,
;; <OFFSET>, <FIRSTPAGE>, <MAINBUFF>, <RETINT>, <SCREENLOC>, <INDXBLKCNT> and <SOSJMPADR>.
;; The others are ours. The disk routine's call block and <BLOCKIO> are the boot ROM's (BootRom.asm), and hardware
;; names are in Apple3Equates.asm, which this file includes.
;;
;; Maintained by hand; tests check it assembles byte-identically to block 0 of the SOS disks named above.

.cpu Mos6502

.include "../Apple3Equates.asm"

.ifndef SYSTEM_DEMO
SYSTEM_DEMO = 0
.endif
.ifndef ON_THREE
ON_THREE = 0
.endif

; ---------------------------------------------------------------------------------------------------------------------
; The boot ROM's disk routine. The ROM leaves zero page at $0300, so these are $0385-$0387 and the loader's own
; locations below are $03E0-$03E9.
; ---------------------------------------------------------------------------------------------------------------------

IBBUFP = $85                        ;; the disk routine's buffer address (two bytes)
IBCMD = $87                         ;; the disk routine's command: 1 to read

;; The disk routine's read command, for <IBCMD>.
RDCMD = 1

;; The boot ROM's routine that reads or writes a 512-byte block of the built-in drive.
;; In: A = the block's low byte, X = its high byte, IBCMD = 1 to read, IBBUFP = the buffer
;; Out: carry = set on an error
BLOCKIO = $F479

; ---------------------------------------------------------------------------------------------------------------------
; Page-zero locations
; ---------------------------------------------------------------------------------------------------------------------

BLOCKNUM = $E0                      ;; the block <READBLK> reads (two bytes)
DIRENT = $E2                        ;; the directory entry being compared (two bytes)
LASTENT = $E4                       ;; the last place an entry can start in the current directory block (two bytes)
DIRBLKCNT = $E6                     ;; directory blocks read, then directory blocks left to search
INDXBLKCNT = $E7                    ;; the index block entry being read
MSGLEN = INDXBLKCNT                 ;; characters of the error message left to put on the screen
SOSJMPADR = $E8                     ;; SOSLDR's address, where the loader jumps (two bytes)

; ---------------------------------------------------------------------------------------------------------------------
; Memory and file layout
; ---------------------------------------------------------------------------------------------------------------------

IDXBLK1 = $0C00                     ;; the index block's first half: the low bytes of the file's block numbers
IDXBLK2 = $0D00                     ;; the index block's second half: the high bytes
LOADADR = $1E00                     ;; where SOS.KERNEL loads; its first block ends at $1FFF in the system bank
OFFSET = LOADADR + 8                ;; the kernel file's header count, after its 8-byte label (two bytes)
FIRSTPAGE = $2000                   ;; the first byte of the switched bank, which the bank search tests
MAINBUFF = $A200                    ;; where block 1 is read; the directory follows it
DIRBLK = MAINBUFF + $200            ;; the volume directory's first block
ENTRYLEN = DIRBLK + $23             ;; the directory's entry length, in the volume header
SCREENLOC = $05A8                   ;; the start of the text screen's twelfth line, where error messages go

;; The offset of SOSLDR from the label's end: the header count's two bytes, then, after the header, the loader's
;; own address and length.
;; See: <JUMPSOSKER>, <OFFSET>
SOSLDROFS = 8 + 2 + 4

;; The length of the name the loader looks for, SOS.KERNEL.
;; See: <FLNME>
KERNLEN = 10

;; A directory entry's storage type, in its first byte's high four bits, for a sapling file: up to 256 data blocks
;; listed in one index block.
SAPLING = $20

;; The storage type of the volume directory's header, the first entry of its first block.
VOLHDR = $F0

;; An RTI, which the loader puts at the NMI vector.
;; See: <NMIVEC>
RETINT = $40

; ---------------------------------------------------------------------------------------------------------------------
; The loader
; ---------------------------------------------------------------------------------------------------------------------

.org $A000

;; The boot ROM's entry: jumps over the loader's text and data to <ENTRY>.
BOOTLDR:
    jmp ENTRY

;; The loader's name and version.
VERSION:
.if ON_THREE
    .byte "SOS BOOT 2.2 by B.C. (c) 1985 by ON THREE. "
.else
  .if SYSTEM_DEMO
    .byte "SOS BOOT  7.0 "
  .else
    .byte "SOS BOOT  1.1 "
  .endif

;; The length of the file name the loader looks for, before <FLNME>.
FLNMELEN:
    .byte KERNLEN

;; The file name the loader looks for, in a 15-character field.
;; See: <FLNMELEN>
FLNME:
    .byte "SOS.KERNEL     "
.endif

;; The label SOS.KERNEL must start with.
FLVERIFY:
    .byte "SOS KRNL"

;; The disk error message; the error messages are indexed from here.
;; See: <WRERRMSG>
DISKERR:
    .byte "I/O ERROR"
DISKERREND:
.if .not ON_THREE
    .byte DISKERREND - 1 - DISKERR, 0
.endif

;; The message for a disk without SOS.KERNEL.
;; See: <WRNTFNDERR>
NTFNDERR:
.if ON_THREE
    .byte "FILE '"

;; The file name the loader looks for, inside <NTFNDERR>.
FLNME:
    .byte "SOS.KERNEL"
    .byte "' NOT FOUND"
.else
    .byte "FILE 'SOS.KERNEL' NOT FOUND"
.endif
NTFNDERREND:
.if .not ON_THREE
    .byte NTFNDERREND - 1 - DISKERR, 0
.endif

;; The message for a SOS.KERNEL that is not a sapling file or lacks its label.
;; See: <WRINVKERERR>
INVKERERR:
    .byte "INVALID KERNEL FILE"
INVKERERREND:
.if .not ON_THREE
    .byte INVKERERREND - 1 - DISKERR, 0

;; Where the index block is read.
IDXBLKP:
    .word IDXBLK1

;; Where SOS.KERNEL loads.
LOADADRP:
    .word LOADADR

;; SOSLDR's address less the kernel file's header count.
SOSLDRP:
    .word LOADADR + SOSLDROFS

;; The volume directory's first entry, its header.
DIRSTARTP:
    .word DIRBLK + 4
.endif

;; Sets up the machine, switches in the highest bank of memory, and goes on to read the directory.
;;
;; Apple's loader tries banks 6 down, writing 0 to $2000 in each until it reads back 0. On Three's first writes $0E
;; to $2000 in bank $E, then 6 to $2000 and $FF to $2034 in bank 6; if bank $E still holds $0E it is a bank of its
;; own, and the loader uses it without the search.
;; Uses: A, X, S
ENTRY:
    sei
    cld
    lda #ENV_IO | ENV_VIDEO | ENV_NMI | ENV_STACK | ENV_ROMSEL | ENV_ROM
    sta ENVIRON                     ; 2 MHz, I/O, video, primary stack, ROM
    ldx #$FB
    txs
    bit KBDSTRB
    lda #RETINT
    sta NMIVEC                      ; RESET returns at once
.if ON_THREE
    lda #$0E
    sta BNKSW
    sta FIRSTPAGE
    lda #$06
    sta BNKSW
    sta FIRSTPAGE
    lda #$FF
    sta FIRSTPAGE + $34
    lda #$0E
    sta BNKSW
    cmp FIRSTPAGE
    beq USEBANK                     ; bank $E is not bank 6
    lsr a
    sta BNKSW                       ; 7, to try 6 first
.else
    lda #$07
    sta BNKSW
.endif
    ldx #$00

;; Steps the bank register down until a 0 written to $2000 reads back.
;; In: BNKSW = one more than the first bank to try, X = 0
;; Out: BNKSW = the bank
;; Uses: A
FINDBANK:
    dec BNKSW
    stx FIRSTPAGE
    lda FIRSTPAGE
    bne FINDBANK
.if ON_THREE
    beq READSOSDIR                  ; always

;; Keeps bank $E switched in.
;; In: A = $0E
USEBANK:
    sta BNKSW
.endif

;; Reads block 1 to <MAINBUFF>, then the volume directory's blocks after it, from block 2 along their next-block
;; pointers until one is 0.
;; Out: DIRBLKCNT = the directory's blocks
;; Uses: A, X, Y, BLOCKNUM, IBBUFP, IBCMD
READSOSDIR:
    lda #$01
    sta BLOCKNUM
    lda #$00
    sta BLOCKNUM+1
    lda #<MAINBUFF
    sta IBBUFP
    lda #>MAINBUFF
    sta IBBUFP+1
    jsr READBLK                     ; block 1
    inc BLOCKNUM                    ; the directory starts at block 2
    lda #$00
    sta DIRBLKCNT
RDSOSDIRLP:
    inc IBBUFP+1
    inc IBBUFP+1                    ; the next 512 bytes
    inc DIRBLKCNT
    jsr READBLK
    ldy #$02
    lda (IBBUFP),y
    sta BLOCKNUM
    iny
    lda (IBBUFP),y
    sta BLOCKNUM+1                  ; the next block
    bne RDSOSDIRLP
    lda BLOCKNUM
    bne RDSOSDIRLP

;; Searches the directory's entries, block by block, for SOS.KERNEL; goes on to <READIDXBLK> when it is a sapling
;; file, or reports the file invalid or not found.
;;
;; A match with the volume header's storage type is passed over.
;; In: DIRBLKCNT = the directory's blocks
;; Out: DIRENT = SOS.KERNEL's entry
;; Uses: A, X, Y, LASTENT, DIRBLKCNT
SRCHSOSKER:
.if ON_THREE
    lda #<(DIRBLK + 4)
    sta DIRENT
    lda #>(DIRBLK + 4)
    sta DIRENT+1
.else
    lda DIRSTARTP
    sta DIRENT
    lda DIRSTARTP+1
    sta DIRENT+1
.endif
SRCHSOSKER_1:
    clc
    lda DIRENT+1
    adc #$02
    sta LASTENT+1
    sec
    lda DIRENT
    sbc ENTRYLEN
    sta LASTENT
    lda LASTENT+1
    sbc #$00
    sta LASTENT+1                   ; 512 bytes on, less an entry

;; Compares one directory entry's name with SOS.KERNEL and checks its storage type.
;; In: DIRENT = the entry, LASTENT = the block's last entry
;; Uses: A, X, Y
SRCHLP:
    ldy #$00
    lda (DIRENT),y
    and #$0F                        ; the name's length
.if ON_THREE
    cmp #KERNLEN
.else
    cmp FLNMELEN
.endif
    bne NEXTENT
    tay
SRCHLP_1:
    lda (DIRENT),y
    cmp FLNME-1,y
    bne NEXTENT
    dey
    bne SRCHLP_1
    ldy #$00
    lda (DIRENT),y
    and #$F0                        ; the storage type
    cmp #SAPLING
    beq READIDXBLK
    cmp #VOLHDR
    beq NEXTENT
.if ON_THREE
    jmp WRINVKERERR
.else
    ldx INVKERERREND
    ldy #INVKERERREND - INVKERERR
    jmp WRERRMSG
.endif

;; Moves to the next directory entry, or the next directory block's first, and goes back to <SRCHLP>; after the last
;; block, reports SOS.KERNEL not found.
;; In: DIRENT = the entry just compared, LASTENT = the block's last entry, DIRBLKCNT = the blocks left
;; Uses: A, X, Y
NEXTENT:
    clc
    lda DIRENT
    adc ENTRYLEN
    sta DIRENT
    lda DIRENT+1
    adc #$00
    sta DIRENT+1
    lda LASTENT
    cmp DIRENT
    lda LASTENT+1
    sbc DIRENT+1
    bcs SRCHLP                      ; another entry fits in this block
    clc
    lda LASTENT
    adc ENTRYLEN
    sta DIRENT
    lda LASTENT+1
    adc #$00
    sta DIRENT+1                    ; the next block's first entry
    dec DIRBLKCNT
    bne SRCHSOSKER_1

;; Puts the not-found message on the screen and stops.
;; See: <NTFNDERR>, <WRERRMSG>
WRNTFNDERR:
.if ON_THREE
    ldx #NTFNDERREND - 1 - DISKERR
.else
    ldx NTFNDERREND
.endif
    ldy #NTFNDERREND - NTFNDERR
    jmp WRERRMSG

;; Reads SOS.KERNEL's index block, from the entry's key pointer, to <IDXBLK1>.
;; In: DIRENT = SOS.KERNEL's directory entry
;; Uses: A, X, Y, BLOCKNUM, IBBUFP, IBCMD
READIDXBLK:
    ldy #$11                        ; the key pointer
    lda (DIRENT),y
    sta BLOCKNUM
    iny
    lda (DIRENT),y
    sta BLOCKNUM+1
.if ON_THREE
    lda #<IDXBLK1
    sta IBBUFP
    lda #>IDXBLK1
    sta IBBUFP+1
.else
    lda IDXBLKP
    sta IBBUFP
    lda IDXBLKP+1
    sta IBBUFP+1
.endif
    jsr READBLK

;; Reads SOS.KERNEL's first block to <LOADADR>.
;; Uses: A, X, Y, BLOCKNUM, IBBUFP, IBCMD
RD1SOSKER:
.if ON_THREE
    lda #<LOADADR
    sta IBBUFP
    lda #>LOADADR
    sta IBBUFP+1
.else
    lda LOADADRP
    sta IBBUFP
    lda LOADADRP+1
    sta IBBUFP+1
.endif
    lda IDXBLK1
    sta BLOCKNUM
    lda IDXBLK2
    sta BLOCKNUM+1
    jsr READBLK

;; Checks that the file starts with the label "SOS KRNL", or reports it invalid.
;; See: <FLVERIFY>
;; Uses: A, X, Y
FLVRFY:
    ldx #$07
FLVRFYLP:
    lda LOADADR,x
    cmp FLVERIFY,x
    beq FLVRFY_1

;; Puts the invalid-kernel message on the screen and stops.
;; See: <INVKERERR>, <WRERRMSG>
WRINVKERERR:
.if ON_THREE
    ldx #INVKERERREND - 1 - DISKERR
.else
    ldx INVKERERREND
.endif
    ldy #INVKERERREND - INVKERERR
    jmp WRERRMSG
FLVRFY_1:
    dex
    bpl FLVRFYLP

;; Reads the rest of SOS.KERNEL's blocks, 512 bytes apart from $2000 on, until the index block lists block 0.
;; In: IBBUFP = <LOADADR>
;; Uses: A, X, Y, BLOCKNUM, IBBUFP, IBCMD, INDXBLKCNT
RDSOSKER:
    lda #$00
    sta INDXBLKCNT
RDSOSKERLP:
    inc INDXBLKCNT
    inc IBBUFP+1
    inc IBBUFP+1                    ; the next 512 bytes
    ldx INDXBLKCNT
    lda IDXBLK1,x
    sta BLOCKNUM
    lda IDXBLK2,x
    sta BLOCKNUM+1
    lda BLOCKNUM
    bne RDSOSKER_1
    lda BLOCKNUM+1
    beq JUMPSOSKER                  ; the end of the file
RDSOSKER_1:
    jsr READBLK
    jmp RDSOSKERLP

;; Jumps to SOSLDR, which starts after the kernel file's label, header count and header and the loader's own
;; address and length.
;; See: <OFFSET>, <SOSLDROFS>
JUMPSOSKER:
    clc
.if ON_THREE
    lda #<(LOADADR + SOSLDROFS)
.else
    lda SOSLDRP
.endif
    adc OFFSET
    sta SOSJMPADR
.if ON_THREE
    lda #>(LOADADR + SOSLDROFS)
.else
    lda SOSLDRP+1
.endif
    adc OFFSET+1
    sta SOSJMPADR+1
    jmp (SOSJMPADR)

;; Reads one block of the built-in drive, or reports a disk error.
;; In: BLOCKNUM = the block, IBBUFP = the buffer
;; Uses: A, X, Y, IBCMD
READBLK:
    lda #RDCMD
    sta IBCMD
    lda BLOCKNUM
    ldx BLOCKNUM+1
    jsr BLOCKIO
    bcs WRDISKERR
    rts

;; Puts the disk error message on the screen and stops.
;; See: <DISKERR>, <WRERRMSG>
WRDISKERR:
.if ON_THREE
    ldx #DISKERREND - 1 - DISKERR
    ldy #DISKERREND - DISKERR
.else
    ldx DISKERREND
    ldy #DISKERREND - DISKERR
    jmp WRERRMSG
.endif

;; Puts an error message in the middle of the screen's twelfth line, sounds the bell, and stops.
;;
;; It copies the message from its last character back. On Three's loader sounds the bell first.
;; In: X = the message's last character's offset from <DISKERR>, Y = the message's length
;; Uses: A, X, Y, MSGLEN
WRERRMSG:
.if ON_THREE
    lda BEEP
.endif
    sty MSGLEN
    sec
    lda #40
    sbc MSGLEN
    lsr a
    clc
    adc MSGLEN
    tay                             ; the column after the message, centered
WRERRMSG_1:
    lda DISKERR,x
    sta SCREENLOC-1,y
    dex
    dey
    dec MSGLEN
    bne WRERRMSG_1
.if ON_THREE
HANG:
    beq HANG
.else
    lda BEEP
HANG:
    jmp HANG
.endif

; The rest of the block is unused; it holds what the disks hold there.
.if SYSTEM_DEMO
    .res $A1FA - *
    .byte $FA, $01, $00, $00, $02
.endif
    .res $A200 - *
    .assert * = $A200, "The loader fills block 0."
