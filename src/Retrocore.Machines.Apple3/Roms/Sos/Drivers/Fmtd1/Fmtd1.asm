;; SOS .FMTD1 DRIVER 1.30: THE DISK /// FORMATTER
;;
;; Formats a disk in one of the Disk /// drives, .D1-.D4, through four devices, .FMTD1-.FMTD4, one DIB each. A
;; program asks for a format with D_CONTROL code $FE, the control list holding the address of a 256-byte sector
;; image. The driver selects the drive, saves the boot ROM's zero page and extension bytes, then writes and verifies
;; all 35 tracks with the ROM's disk routines: sixteen sectors of the image on each, volume 1, with the gaps between
;; sectors tuned until sector 0 comes round right after sector 15 (<WT16>).
;;
;; Requests:
;;
;; - D_CONTROL $FE formats the drive; D_CONTROL 0 (reset) does nothing. A format fails with XWPROT for a
;;   write-protected disk, XIOERR for a disk that won't verify, and XDEVSPEC+3 or XDEVSPEC+4 ($33, $34) for a drive
;;   that spins too slowly or too fast.
;; - D_STATUS $FE answers $FFFF: the driver has no preference for where the volume's bitmap starts.
;; - D_INIT does nothing; D_READ, D_WRITE, D_OPEN and D_CLOSE return XBADOP.
;;
;; The DIBs have device type $11, subtype $01, release 1.30, 280 blocks, and no configuration block. The first DIB is
;; page-aligned and comes first; the other three come last. After the first DIB, four bytes set the formatter's limits
;; (<DCB_MINSYNC>). The comment record "(C) Apple Computer, 1983.  Disk /// Formatter Driver." leads the source.
;;
;; Labels follow Apple's listing, "Apple /// Disk /// Floppy Disk Formatter Driver 1.30 Source Code Listing", and the
;; comments are our own. Labels inside routines are named after the routine (<FMTCTRL_020>). The listing's source
;; files are included in its order: FmtData.asm, FmtRead.asm, FmtWrAddr.asm, FmtFormat.asm and FmtWTrack.asm.
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .FMTD1 1.30.

.cpu Mos6502

;; The device type: a formatter.
DEVTYPE = $11

;; The subtype: for the Disk ///.
SUBTYPE = $01

;; The manufacturer: Apple.
APPLE = $01

;; The driver's release, 1.30.
RELEASE = $1300

;; The blocks on a formatted disk.
DEVBLKS = 280

;; The times <WT16> rewrites a track that won't verify before giving up.
MAXTRKRETRY = 3

;; The address fields read while looking for a sector; twice as many while looking for sector 15.
MAXSECTRETRY = 16

;; The usual count of self-sync nibbles in the gaps between sectors, for a drive at the right speed.
GOODSYNC = 22

;; How far over <GOODSYNC> the gaps may grow before the drive is too slow.
DELTAS = 3

;; How far under <GOODSYNC> the gaps may shrink before the drive is too fast.
DELTAF = 3

;; The fewest self-sync nibbles in a gap: fewer means the drive is too fast.
MINSYNC = GOODSYNC-DELTAF

;; The most self-sync nibbles in a gap: this many or more means the drive is too slow.
MAXSYNC = GOODSYNC+DELTAS

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
    lda table+$01,y
    pha
    lda table,y
    pha
    .if .not .xmatch({stay}, {*})
    rts
    .endif
M010:
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; SOS: the kernel's call, error codes and the request block.
; ---------------------------------------------------------------------------------------------------------------------

;; Returns an error from the SOS call: A = the error code. It doesn't return.
SYSERR = $1928

XCTLCODE = $21                          ;; the control or status code is invalid
XCTLPARM = $22                          ;; the control or status parameter is invalid
XNOTOPEN = $23                          ;; the device is not open
XNOTAVAIL = $24                         ;; the device is not available
XBADOP = $26                            ;; the operation is invalid
XIOERR = $27                            ;; an I/O error: the disk won't format
XWPROT = $2B                            ;; the disk is write-protected
XDEVSPEC = $30                          ;; the first of the driver's own errors: +3 too slow, +4 too fast

TRUE = $80                              ;; a true flag
FALSE = $00                             ;; a false flag

;; The request block SOS passes to a driver, in zero page.
SOSINT = $C0

REQCODE = SOSINT+$00                    ;; the request code
UNITNUM = SOSINT+$01                    ;; the unit: 0-3 for .FMTD1-.FMTD4
CTLSTAT = SOSINT+$02                    ;; status/control: the code
CSLIST = SOSINT+$03                     ;; status/control: the list's address, with its extension byte at $1400+CSLIST+1

; ---------------------------------------------------------------------------------------------------------------------
; The comment record and the first DIB.
; ---------------------------------------------------------------------------------------------------------------------

;; The comment record SOS.DRIVER keeps apart from the code: $FFFF, the text's length, the text.
DRIVER_COMMENT:
    .word $FFFF
    .word DRIVER_COMMENT_END - DRIVER_COMMENT - 4
    .byte "(C) Apple Computer, 1983.  "
    .byte "Disk /// Formatter Driver."
DRIVER_COMMENT_END:
    .logicalorg * - (DRIVER_COMMENT_END - DRIVER_COMMENT)

;; .FMTD1's device information block, first so that the driver is page-aligned.
DIBD1:
    .word DIBD2                         ; the next DIB
    .word FMTMAIN                       ; the entry point
    .byte 6                             ; the name's length
    .byte ".FMTD1         "
    .byte $C0                           ; active, page-aligned
    .byte $00, $00                      ; slot and unit
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word DEVBLKS
    .word APPLE
    .word RELEASE
    .word $00                           ; no configuration block

;; The fewest self-sync nibbles in a gap before the drive is too fast (<MINSYNC>).
DCB_MINSYNC:
    .byte MINSYNC

;; The self-sync nibbles in a gap at which the drive is too slow (<MAXSYNC>).
DCB_MAXSYNC:
    .byte MAXSYNC

;; The times a track is rewritten before giving up (<MAXTRKRETRY>).
DCB_TRKRETRY:
    .byte MAXTRKRETRY

;; The address fields read while looking for a sector (<MAXSECTRETRY>).
DCB_SECTRETRY:
    .byte MAXSECTRETRY

    .include "FmtData.asm"
    .include "FmtRead.asm"
    .include "FmtWrAddr.asm"
    .include "FmtFormat.asm"
    .include "FmtWTrack.asm"

; ---------------------------------------------------------------------------------------------------------------------
; The requests.
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: goes to the request's routine.
;; In: REQCODE = the request
;; See: <REQSTSW>
FMTMAIN:
    SWITCH REQCODE, 8, REQSTSW

;; Fails the request: the formatter doesn't do it.
BADREQ:
    lda #XBADOP
    jsr SYSERR

;; The request routines' addresses less one, by request code.
REQSTSW:
    .word BADREQ-1                      ; 0: read
    .word BADREQ-1                      ; 1: write
    .word FMTSTATUS-1                   ; 2: status
    .word FMTCTRL-1                     ; 3: control
    .word BADREQ-1                      ; 4
    .word BADREQ-1                      ; 5
    .word BADREQ-1                      ; 6: open
    .word BADREQ-1                      ; 7: close
    .word FMTINIT-1                     ; 8: initialize

;; Answers a control request: code 0 (reset) does nothing, and code $FE formats the unit's drive.
;; In: CTLSTAT = the control code, UNITNUM = the unit, CSLIST = the address of the 256-byte sector image
;; Errors: XCTLCODE = another code, XWPROT = write-protected, XIOERR = the disk won't format,
;;   XDEVSPEC+3 = the drive is too slow, XDEVSPEC+4 = the drive is too fast
;; Uses: A, X, Y
;; See: <DSKFORM>
FMTCTRL:
    lda CTLSTAT
    cmp #$00
    bne FMTCTRL_005
    rts                                 ; reset: nothing to do
FMTCTRL_005:
    cmp #$FE
    beq FMTCTRL_020
    lda #XCTLCODE
FMTCTRL_010:
    jsr SYSERR
FMTCTRL_020:
    jsr FMTSTARTUP
    cmp #$00
    bne FMTCTRL_010
    lda CSLIST                          ; the sector image's address, and its extension byte
    sta a:USERBUF
    lda CSLIST+$01
    sta a:USERBUF+$01
    lda $1400+CSLIST+$01
    sta a:USERBUF+$02
    ldx UNITNUM
    inx                                 ; the drive, 1-4
    jsr DSKFORM
    cmp #$00
    bne FMTCTRL_030
    rts
FMTCTRL_030:
    cmp #$02
    bne FMTCTRL_040
    lda #XWPROT
    jsr SYSERR
FMTCTRL_040:
    cmp #$01
    bne FMTCTRL_050
    lda #XIOERR
    jsr SYSERR
FMTCTRL_050:
    clc
    adc #XDEVSPEC                       ; 3, too slow, or 4, too fast
    jsr SYSERR

;; Fails a control request: the drive is invalid. Nothing branches here.
BADDRIVE:
    lda #XCTLPARM
    jsr SYSERR

;; Answers a status request: code $FE answers $FFFF, no preference for where the volume's bitmap starts.
;; In: CTLSTAT = the status code, CSLIST = where to put the answer
;; Errors: XCTLCODE = another code
;; Uses: A, Y
FMTSTATUS:
    lda CTLSTAT
    cmp #$FE
    beq FMTSTATUS_010
    lda #XCTLCODE
    jsr SYSERR
FMTSTATUS_010:
    ldy #$00
    lda #$FF
    sta (CSLIST),y
    iny
    sta (CSLIST),y
    rts

;; Initializes the driver at boot: there is nothing to do.
;; Out: carry = clear
FMTINIT:
    clc
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The other DIBs, last so that they don't move the code.
; ---------------------------------------------------------------------------------------------------------------------

;; .FMTD2's device information block.
DIBD2:
    .word DIBD3                         ; the next DIB
    .word FMTMAIN
    .byte 6
    .byte ".FMTD2         "
    .byte $80                           ; active
    .byte $00, $01                      ; slot and unit
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word DEVBLKS
    .word APPLE
    .word RELEASE
    .word $00                           ; no configuration block

;; .FMTD3's device information block.
DIBD3:
    .word DIBD4                         ; the next DIB
    .word FMTMAIN
    .byte 6
    .byte ".FMTD3         "
    .byte $80                           ; active
    .byte $00, $02                      ; slot and unit
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word DEVBLKS
    .word APPLE
    .word RELEASE
    .word $00                           ; no configuration block

;; .FMTD4's device information block, the last.
DIBD4:
    .word $00                           ; no next DIB
    .word FMTMAIN
    .byte 6
    .byte ".FMTD4         "
    .byte $80                           ; active
    .byte $00, $03                      ; slot and unit
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word DEVBLKS
    .word APPLE
    .word RELEASE
    .word $00                           ; no configuration block
