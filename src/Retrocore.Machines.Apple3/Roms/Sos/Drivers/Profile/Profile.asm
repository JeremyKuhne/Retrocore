;; SOS .PROFILE DRIVER 1.30
;;
;; The SOS block device driver for Apple's ProFile hard disk, a 5 MB drive that the Apple III reaches through
;; the ProFile interface card in one of its slots. SOS loads it from SOS.DRIVER and calls it through the entry
;; point in its device information block, <MAIN>, with the request in SOS's driver parameters at $C0-$C9.
;;
;; The ProFile has its own Z8 controller with a buffer for one block. The driver and the Z8 talk through the card's
;; data port and two lines: CMD, which the driver raises and drops by reading the card's $CN00 locations, and BSY,
;; which the ProFile drives and the driver reads at $C082+slot*16. Each exchange is a handshake (<SNDCMD>): the
;; driver waits for BSY low, raises CMD and waits for BSY high, when the ProFile has a response byte on the port
;; saying what it is ready for. The driver answers $55 to go on or $AA to refuse, drops CMD and waits for BSY low
;; again. A block read or write takes these handshakes:
;;
;; - Response 1, ready for a command: the driver sends six bytes (<SND_CMDBYTES>), the command (0 read, 1 write,
;;   2 write and verify), the three-byte block number, the retry count and the sparing threshold.
;; - For a read, response 2: the ProFile has read the block, and the driver takes four status bytes (<GETSTAT>),
;;   then the 512 bytes of data (<DATRANS>).
;; - For a write, response 3 (or 4 to verify): the driver sends the 512 bytes and six check bytes, the block number
;;   and its complement; after response 6, when the ProFile has written the block, it takes the four status bytes.
;;
;; After the last block the driver makes one more handshake and sends command $FF (<GOODEXIT>), which lets the
;; ProFile finish any update to its table of spare blocks.
;;
;; Data moves a byte at a time where the caller's buffer starts or ends partway into a page, and otherwise in
;; pages by the ROM's pseudo-DMA loop at $F800, which the driver reaches through a few bytes it copies to $18F0
;; (<RELCODE>) so that the loop can reach any bank (<GO_DMA>). The driver slows the machine to 1 MHz only while it
;; talks to the card (<S2M> returns to 2 MHz). Parity errors and refused handshakes are retried, and a ProFile
;; that stops answering is reset once (<RESET_PIPPIN>) before the driver reports an I/O error.
;;
;; Requests (see <SW_TABLE>):
;;
;; - 0, read (<DREAD>), and 1, write (<DWRITE>): whole blocks, the byte count a multiple of 512.
;; - 2, status (<DSTATUS>): code 0 gives the busy and online bits, code 1 the last four status bytes, and code $FE,
;;   which formatters ask, gives $FFFF.
;; - 3, control (<FDCONTROL>): codes 0 (reset) and $FE (format) are accepted and do nothing, since the ProFile
;;   comes formatted.
;; - 8, initialize (<DINIT>): sets up the slot's addresses, claims the slot's interrupt resource and turns the
;;   card's interrupts off.
;; - 9, repeat (<DREPEAT>): repeats the last read or write to the same unit.
;; - 4 and 5 are refused as bad requests, and 6 and 7 as bad operations.
;;
;; The driver has one device, .PROFILE (<DIB_LINK1>). The System Configuration Program sets its slot
;; (<DIB_SLOT1>), unit and block count (<DIB_BLOCK1>); its one configuration byte, <WRTVER>, chooses whether
;; writes are verified. Its comment record, <DRIVER_COMMENT>, comes first; SOS.DRIVER keeps it apart from the
;; code, whose addresses count from the device information block.
;;
;; Labels follow Apple's listing of the driver, "Apple /// ProFile Hard Disk Driver 1.30 Source Code Listing"
;; (https://www.apple3.org/Documents/SourceCode/apple3_SRC_Profile_Driver.pdf), and the comments are our own.
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .PROFILE 1.30.

.cpu Mos6502

;; The device type in the device information block: a block device, the ProFile.
DEVTYPE = $D1

;; The device subtype in the device information block.
SUBTYPE = $01

;; The manufacturer in the device information block: 1 for Apple.
MANUF = $01

;; The driver's release, 1.30, as SOS reports it.
RELEASE = $1300

;; The ProFile's size in 512-byte blocks, 9,728 (4,980,736 bytes), not counting the blocks it keeps as spares.
MAXBLOCK = $2600

;; Jumps to the routine a table gives for an index: the table holds each routine's address minus one, and the
;; jump is an RTS to the address it pushes.
;;
;; When the index is out of range the macro falls through to the code after it. A fourth argument of * leaves
;; out the RTS, so the code after the macro makes the jump.
;; Parameters:
;;   p1 = the index, loaded into A first when given
;;   p2 = the highest index, checked when given
;;   p3 = the table of addresses minus one
;;   p4 = * to leave the jump to the code that follows
;; Uses: A, Y
.macro SWITCH p1, p2, p3, p4, p5, p6
    .local M010
    .ifnblank p1
    lda p1
    .endif
    .ifnblank p2
    cmp #<(p2+$01)
    bcs M010
    .endif
    asl a
    tay
    lda a:p3+$01,y
    pha
    lda a:p3,y
    pha
    .if .not .xmatch({p4}, {*})
    rts
    .endif
M010:
.endmacro

    .include "ProfileA.asm"
    .include "ProfileB.asm"
