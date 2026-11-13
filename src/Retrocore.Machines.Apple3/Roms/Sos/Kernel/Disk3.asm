; DISK3: the driver for the Disk III drives .D1-.D4, built into the kernel. .D1 is the Apple III's built-in drive
; and .D2-.D4 are up to three external drives on its daisy chain. The driver reads and writes 512-byte blocks, two
; 256-byte sectors each, using the boot ROM's low-level disk routines, and keeps track of each drive's head
; position and how long its motor has been on, so that it waits for a motor to spin up only as long as needed.
;
; This file holds the equates, the page-zero names and the four device information blocks (DIBs). The code
; follows in the files it includes: Disk3Main.asm (the request dispatch and reads), Disk3Wrt.asm (writes, status,
; init and the exit path), Disk3Sio.asm (one sector's I/O), Disk3USel.asm (selecting a drive), Disk3Subs.asm
; (helpers) and Disk3Data.asm (the driver's tables).
;
; Names follow Apple's SOS 1.3 listing.

;; Builds the driver for testing on its own when 1, outside SOS ("funny mode" in Apple's listing).
;;
;; A test build is assembled at $2000, does not lock out NMI and RESET while it runs, leaves the boot loader's .D1
;; state alone at INIT, defines the error codes itself, and returns its result in A instead of through SYSERR.
;; SOS.KERNEL is built with 0.
TEST = 0
; Apple's source set the origin here: $2000 for a test build, ORGDISK3 for SOS. SosKernel.asm places this module,
; so both branches are empty.
    .if TEST
    .else
    .endif
ZZORG:                                  ;; the module's first address, for the length check at the end of Disk3Data.asm

;; Builds the driver to work with the first revision of the boot ROM as well when 1.
;;
;; That ROM has its disk routines at slightly different addresses and does not count interrupts during a transfer
;; itself. With 1, INIT looks at the ROM to tell which revision it is and fills a jump table, JMPTAB, with the
;; matching addresses, and <SECTORIO> keeps the interrupt count. SOS.KERNEL is built with 0 and calls the later
;; ROM's routines directly.
REV0ROM = 0
; SOS defines the error codes in SYSGLOB; a test build defines them here.
    .if .not TEST
    .else
XREQCODE = $20                          ;; error: the request code is not one a driver knows
XBADOP = $26                            ;; error: this driver does not do that request
XNODRIVE = $28                          ;; error: no drive is connected as this unit
XIOERROR = $27                          ;; error: the sector could not be read or written
XNOWRITE = $2B                          ;; error: the disk is write-protected
XBYTECNT = $2C                          ;; error: the byte count is not whole blocks, or runs past the disk's end
XBLKNUM = $2D                           ;; error: the block number is past the disk's end
XDISKSW = $2E                           ;; error: the disk was switched since the drive was last used
XCTLCODE = $21                          ;; error: the status code is not one the driver knows
    .endif

; ---------------------------------------------------------------------------------------------------------------------
; Disk III controller soft switches. The built-in drive has a motor select of its own; the external drives share two
; select lines, ext1 and ext2, and each unit is one combination of them:
;
;   .D2 = ext1 off, ext2 on;  .D3 = ext1 on, ext2 off;  .D4 = both on.
; ---------------------------------------------------------------------------------------------------------------------

MS_INT = $C0D4                          ;; selects the built-in drive's motor
MD_INT = $C0D5                          ;; deselects the built-in drive's motor
MS_EXT1 = $C0D3                         ;; turns the external drives' first select line on
MS_EXT2 = $C0D1                         ;; turns the external drives' second select line on
MD_EXT1 = $C0D2                         ;; turns the external drives' first select line off
MD_EXT2 = $C0D0                         ;; turns the external drives' second select line off
IS_INT = $C0EA                          ;; connects the controller's data lines to the built-in drive
IS_EXT = $C0EB                          ;; connects the controller's data lines to the external drives
NOSCROLL = $C0D8                        ;; turns smooth scrolling off; reading it is enough
MOTOROFF = $C0E8                        ;; starts the motors' turn-off delay (they stop about a second later)
MOTORON = $C0E9                         ;; powers the selected motor
Q6L = $C08C                             ;; Q6 off: with Q7 off, reads the data latch
Q6H = $C08D                             ;; Q6 on: with Q7 off, senses write protection
Q7L = $C08E                             ;; Q7 off: the read side
Q7H = $C08F                             ;; Q7 on: the write side
E_REG = $FFDF                           ;; the environment register: bit 7 = 1 MHz, bit 5 = screen, bit 4 = NMI/RESET on
E_IER = $FFEE                           ;; the system VIA's interrupt enable register (bit 7: 1 enables, 0 disables)

;; How many times <SECTORIO> recalibrates before it gives up on a sector.
;;
;; It must not be 0: SECTORIO stores this count in <E1908> as the flag that keeps the mouse driver from interrupting,
;; and 0 would leave the mouse free to.
R_RECAL = 1
R_FIND = 3                              ;; revolutions <FINDSECT> looks for a sector in, 16 address fields each
R_IOERR = 4                             ;; read errors <SECTORIO> takes before it recalibrates
R_IRQ = 6                               ;; interrupts a transfer may stop for before interrupts stay masked

; ---------------------------------------------------------------------------------------------------------------------
; Page-zero locations the boot ROM's disk routines use (their names there are the same). The driver runs with the
; kernel's zero page, so these are in page $18.
; ---------------------------------------------------------------------------------------------------------------------

IBSLOT = $0081                          ;; the controller's slot times 16, $60, set by INIT
IMASK = $008B                           ;; bit 7 set when the ROM routines must leave interrupts masked
CURTRK = $008C                          ;; the head's position in half-tracks, for the ROM's SEEK
INTRTRY = $008F                         ;; interrupts a transfer may still stop for, less one
CSSTV = $0097                           ;; the last address field read: checksum, sector, track, volume
MONTIMEL = CSSTV+2                      ;; the motor-on time count, low byte; counts up to 0 in 100-microsecond steps
MONTIMEH = MONTIMEL+1                   ;; the motor-on time count, high byte; negative while the motor spins up
BUF = $009B                             ;; the sector buffer's address for PRENIB and POSTNIB (two bytes)
TRKN = $009E                            ;; the half-track the ROM's SEEK moves to

; ---------------------------------------------------------------------------------------------------------------------
; The driver's own page-zero work area, from $D0 up.
; ---------------------------------------------------------------------------------------------------------------------

BLKTEMP = $00D0                         ;; the block being transferred (two bytes)
BUFTEMP = $00D2                         ;; where that block goes in memory (two bytes, extension byte in SXPAGE)
TRACK = $00D4                           ;; the track of the sector being transferred
SECTOR = $00D5                          ;; the sector being transferred
RETRYADR = $00D6                        ;; address fields <FINDSECT> may still read
RETRYCNT = $00D7                        ;; read errors <SECTORIO> may still retry
RECALCNT = $00D8                        ;; recalibrations <SECTORIO> may still do
BLKCOUNT = $00D9                        ;; blocks left in the request
SEEKWAIT = $00DA                        ;; nonzero when another external drive was stopped, so a seek must wait first
IRQMASK = $00DB                         ;; bit 7 set when the caller had interrupts masked
TEMP = $00DC                            ;; scratch: the motor time before a seek, or <FINDSECT>'s latency flag

; ---------------------------------------------------------------------------------------------------------------------
; The request's parameters, which the device manager passes to every driver at $C0 in the kernel's zero page.
; ---------------------------------------------------------------------------------------------------------------------

D_COMMAND = $00C0                       ;; the request: 0 read, 1 write, 2 status, 8 init, 9 repeat
D_UNITNUM = $00C1                       ;; the unit: 0-3 for .D1-.D4, from the DIB
D_BUFL = $00C2                          ;; the caller's buffer, an extended address (extension byte in SXPAGE)
D_BUFH = D_BUFL+1                       ;; the buffer address's high byte
D_STATCODE = D_BUFL                     ;; for status: the status code, which must be 0
D_STATBUF = D_BUFH                      ;; for status: the pointer to the status list
D_BYTES = $00C4                         ;; the byte count, which must be a whole number of blocks
D_BLOCK = $00C6                         ;; the first block
D_BYTRD = $00C8                         ;; for read: where to return the count of bytes read

;; The device information block for .D1, the built-in drive, and the head of the list of the driver's DIBs.
;;
;; Each DIB holds: the next DIB's address (0 ends the list), the driver's entry point (<MAIN>), the name's length
;; and the name padded to 15 characters, the device number ($80 here: active), the slot (0: none), the unit number
;; (0-3), the device type $E1 (bit 7 set: a block device) and subtype 1 with a spare byte, the size in blocks
;; (280: 35 tracks of 8 blocks), the manufacturer (1: Apple) and the version ($1100: 1.1).
;; See: <DIB2>, <DIB3>, <DIB4>
DIB1:
    .word DIB2
    .word MAIN
    .byte 3
    .byte ".D1            "
    .byte $80
    .byte 0
    .byte 0
    .byte $E1, 1, 0
    .word 280
    .word 1
    .word $1100
;; The device information block for .D2, the first external drive; laid out as <DIB1>.
;; See: <DIB1>
DIB2:
    .word DIB3
    .word MAIN
    .byte 3
    .byte ".D2            "
    .byte $80
    .byte 0
    .byte 1
    .byte $E1, 1, 0
    .word 280
    .word 1
    .word $1100
;; The device information block for .D3, the second external drive; laid out as <DIB1>.
;; See: <DIB1>
DIB3:
    .word DIB4
    .word MAIN
    .byte 3
    .byte ".D3            "
    .byte $80
    .byte 0
    .byte 2
    .byte $E1, 1, 0
    .word 280
    .word 1
    .word $1100
;; The device information block for .D4, the third external drive and the last in the list; laid out as <DIB1>.
;;
;; Two more words follow it, a second copy of the manufacturer and version, which Apple's listing has too and nothing
;; reads.
;; See: <DIB1>
DIB4:
    .word 0
    .word MAIN
    .byte 3
    .byte ".D4            "
    .byte $80
    .byte 0
    .byte 3
    .byte $E1, 1, 0
    .word 280
    .word 1
    .word $1100
    .word 1
    .word $1100
    .include "Disk3Main.asm"
